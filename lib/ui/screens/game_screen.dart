// lib/ui/screens/game_screen.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../data/models/ble_packet.dart';
import '../../data/models/match_phase.dart';
import '../../data/models/player_state.dart';
import '../../data/sources/ble_direct_source.dart';
import '../../data/sources/data_source.dart';
import '../../../main.dart' show DataSourceNotifier;
import '../widgets/field_view.dart';
import '../widgets/player_card.dart';
import '../widgets/player_list.dart';
import '../widgets/player_name_dialog.dart';

/// Main live-game screen.
///
/// Layout:
///   - AppBar: session timer + connected count + start/stop
///   - 80% height: FieldView with player dots
///   - 20% height: horizontal PlayerList
///   - FAB (debug): toggle mock / BLE source
class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  List<PlayerState> _players = [];
  StreamSubscription<List<PlayerState>>? _sub;
  String? _selectedPlayerId;
  final _fieldViewKey = GlobalKey<FieldViewState>();

  // Session timer.
  int _sessionSeconds = 0;
  Timer? _sessionTimer;
  MatchPhase _matchPhase = MatchPhase.preMatch;
  bool _debugOverlay = false;

  @override
  @override
  void initState() {
    super.initState();
    // Keep screen on during game — prevents Android from throttling BLE scans
    WakelockPlus.enable();
    WidgetsBinding.instance.addPostFrameCallback((_) => _subscribe());
  }

  void _subscribe() {
    final source = context.read<DataSource>();
    _sub?.cancel();
    _sub = source.playerStates.listen((players) {
      if (mounted) {
        setState(() => _players = players);
      }
    });
  }

  /// Called when the user switches data source (mock ↔ BLE).
  /// Stops the old source, resets session, re-subscribes, and auto-starts.
  void _onSourceChanged() {
    // Reset match state on source switch.
    _sessionTimer?.cancel();
    setState(() {
      _matchPhase = MatchPhase.preMatch;
      _sessionSeconds = 0;
      _players = [];
    });
    // Re-subscribe to new source stream.
    _subscribe();
    // Auto-start scanning so devices appear.
    final source = context.read<DataSource>();
    source.start();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _sessionTimer?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _assignPlayerName(PlayerState player) async {
    final source = context.read<DataSource>();
    if (source is! BleDirectSource) return;

    final device = source.getDevice(player.player.id);
    if (device == null) return;

    final name = await PlayerNameDialog.show(
      context,
      deviceName: device.platformName,
      currentName: player.player.name.startsWith('Player ') ? null : player.player.name,
    );
    if (name == null || name.isEmpty) return;

    // Send NAME: command to device via NUS
    await source.sendCommand(device, 'NAME:$name');

    // Update local player name
    source.updatePlayerName(player.player.id, name);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Set "$name" on ${device.platformName}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _advancePhase() {
    final nextPhase = _matchPhase.next;
    if (nextPhase == null) return; // Already at fullTime

    final source = context.read<DataSource>();
    final wasActive = _matchPhase.isActive;
    final willBeActive = nextPhase.isActive;

    setState(() => _matchPhase = nextPhase);

    // Transition: inactive → active (start quarter)
    if (!wasActive && willBeActive) {
      // Start scanning if not running
      if (!source.isRunning) {
        source.start();
      }
      // Start/restart timer
      _sessionTimer?.cancel();
      _sessionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _sessionSeconds++);
      });
      // Tell BLE source to auto-start all devices
      if (source is BleDirectSource) {
        source.setMatchActive(true);
      }
    }

    // Transition: active → inactive (end quarter / full time)
    if (wasActive && !willBeActive) {
      _sessionTimer?.cancel();
      // Only send stop at full time — keep logging through breaks
      if (nextPhase == MatchPhase.fullTime) {
        if (source is BleDirectSource) {
          source.setMatchActive(false);
        }
        source.stop();
      }
    }

    // Send phase to all devices for CSV logging
    if (source is BleDirectSource) {
      final phaseCmd = 'PHASE:${nextPhase.label}';
      for (final device in source.allDevices) {
        source.sendCommand(device, phaseCmd);
      }
    }
  }

  void _resetMatch() {
    final source = context.read<DataSource>();
    _sessionTimer?.cancel();
    if (source is BleDirectSource) {
      source.setMatchActive(false);
    }
    source.stop();
    setState(() {
      _matchPhase = MatchPhase.preMatch;
      _sessionSeconds = 0;
      _players = [];
    });
  }

  String _formatTimer(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Widget _buildDebugOverlay(BuildContext context) {
    final source = context.read<DataSource>();
    final rawPackets = (source is BleDirectSource) ? source.lastRawPackets : <String, List<int>>{};

    return Positioned(
      top: 4,
      left: 4,
      right: 4,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.85),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('🐛 DEBUG', style: TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            ..._players.take(3).map((p) {
              final raw = rawPackets[p.player.id];
              if (raw == null) {
                return Text('${p.player.name}: no raw data', style: const TextStyle(color: Colors.white54, fontSize: 9));
              }
              final bd = ByteData.sublistView(Uint8List.fromList(raw));
              final len = raw.length;
              final hexStr = raw.take(27).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
              String gpsStr;
              if (len >= 23) {
                final latRaw = bd.getInt32(15, Endian.little);
                final lngRaw = bd.getInt32(19, Endian.little);
                gpsStr = 'v2 lat=${(latRaw / 10000000.0).toStringAsFixed(7)} lng=${(lngRaw / 10000000.0).toStringAsFixed(7)}';
              } else if (len >= 20) {
                final latOff = bd.getInt16(15, Endian.little);
                final lngOff = bd.getInt16(17, Endian.little);
                gpsStr = 'v1 latOff=$latOff lngOff=$lngOff';
              } else {
                gpsStr = 'short packet ($len bytes)';
              }
              final spdByte = raw[6];
              final posStr = p.position != null
                  ? '(${p.position!.latitude.toStringAsFixed(7)}, ${p.position!.longitude.toStringAsFixed(7)})'
                  : 'null';
              final lastUpdate = (source is BleDirectSource) ? source.lastUpdateTime[p.player.id] : null;
              final updateCount = (source is BleDirectSource) ? (source.updateCounts[p.player.id] ?? 0) : 0;
              final ageMs = lastUpdate != null ? DateTime.now().difference(lastUpdate).inMilliseconds : -1;
              final gpsIntervalMs = (source is BleDirectSource) ? source.gpsUpdateIntervalMs[p.player.id] : null;
              final pkt = (source is BleDirectSource) ? source.lastPackets[p.player.id] : null;
              final gpsHz = gpsIntervalMs != null && gpsIntervalMs > 0 ? (1000.0 / gpsIntervalMs).toStringAsFixed(1) : '?';
              final hwId = (source is BleDirectSource) ? source.hardwareIds[p.player.id] : null;
              final hwStr = hwId != null ? ' hw=$hwId' : '';
              final extStr = pkt != null && pkt.packetVersion == 21
                  ? ' brg=${pkt.gpsBearingDeg?.toStringAsFixed(1)}° hdop=${pkt.gpsHdop?.toStringAsFixed(1)} fix=${pkt.fixQualityLabel}'
                  : '';
              final dropped = (source is BleDirectSource) ? (source.droppedCounts[p.player.id] ?? 0) : 0;
              final seqDropped = (source is BleDirectSource) ? (source.seqDroppedCounts[p.player.id] ?? 0) : 0;
              final seqNum = pkt?.seq;
              final statsStr = ' drop=$dropped seqGap=$seqDropped${seqNum != null ? ' seq=$seqNum' : ''}';
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${p.player.name}$hwStr [${len}B] spd=${spdByte / 2.0}km/h age=${ageMs}ms #$updateCount gps=${gpsHz}Hz$extStr$statsStr\n$gpsStr\npos=$posStr\n$hexStr',
                  style: const TextStyle(color: Colors.white70, fontSize: 9, fontFamily: 'monospace'),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final connectedCount = _players.length;
    final activeCount = _players.where(
      (p) => DateTime.now().difference(p.lastSeen).inSeconds < 10).length;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Row(
          children: [
            Text(
              _formatTimer(_sessionSeconds),
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  letterSpacing: 1.5),
            ),
            if (_matchPhase.isActive) ...[
              const SizedBox(width: 8),
              Container(
                width: 8, height: 8,
                decoration: const BoxDecoration(
                  color: Colors.greenAccent,
                  shape: BoxShape.circle,
                ),
              ),
            ],
            const SizedBox(width: 16),
            Row(
              children: [
                const Icon(Icons.bluetooth_connected, color: Colors.lightBlueAccent, size: 16),
                const SizedBox(width: 4),
                Text(
                  '$activeCount/$connectedCount',
                  style: TextStyle(
                    color: activeCount == connectedCount ? Colors.white70 : Colors.orangeAccent,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          // Debug overlay toggle
          IconButton(
            onPressed: () => setState(() => _debugOverlay = !_debugOverlay),
            icon: Icon(
              Icons.bug_report,
              color: _debugOverlay ? Colors.amberAccent : Colors.white38,
              size: 22,
            ),
            tooltip: 'Toggle debug overlay',
          ),
          // Jump to player location
          IconButton(
            onPressed: () {
              final moved = _fieldViewKey.currentState?.jumpToPlayers() ?? false;
              if (!moved) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('No GPS fix on any device yet'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
            icon: const Icon(Icons.my_location, color: Colors.white70, size: 22),
            tooltip: 'Jump to players',
          ),
          // Match phase control
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Phase badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _matchPhase.isActive
                        ? const Color(0xFF4CAF50).withOpacity(0.3)
                        : Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _matchPhase.label,
                    style: TextStyle(
                      color: _matchPhase.isActive ? Colors.greenAccent : Colors.white70,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Advance button
                if (_matchPhase != MatchPhase.fullTime)
                  ElevatedButton(
                    onPressed: _advancePhase,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _matchPhase.next?.isActive == true
                          ? const Color(0xFF4CAF50)
                          : const Color(0xFFF44336),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      minimumSize: Size.zero,
                    ),
                    child: Text(_matchPhase.actionLabel),
                  ),
                // Reset button (only after match started)
                if (_matchPhase != MatchPhase.preMatch) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: _resetMatch,
                    icon: const Icon(Icons.refresh, color: Colors.white38, size: 18),
                    tooltip: 'Reset match',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Field view: 80% of available height.
          Expanded(
            flex: 4,
            child: Stack(
              children: [
                FieldView(
                  key: _fieldViewKey,
                  players: _players,
                  defaultCenter: _players.where((p) => p.position != null).isEmpty
                      ? null
                      : _players.firstWhere((p) => p.position != null).position,
                  selectedPlayerId: _selectedPlayerId,
                  onPlayerTap: (p) {
                    setState(() => _selectedPlayerId = p.player.id);
                    showPlayerCard(context, p);
                  },
                ),
                if (_debugOverlay) _buildDebugOverlay(context),
              ],
            ),
          ),

          // Player list: 20% of available height.
          Expanded(
            flex: 1,
            child: Container(
              color: const Color(0xFF12122A),
              child: PlayerList(
                players: _players,
                selectedPlayerId: _selectedPlayerId,
                onPlayerTap: (p) {
                  setState(() => _selectedPlayerId = p.player.id);
                  showPlayerCard(context, p);
                },
                onPlayerLongPress: (p) => _assignPlayerName(p),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: _SourceToggleFab(onSourceChanged: _onSourceChanged),
    );
  }
}

/// FAB to toggle between Mock (demo) and BLE (live) data source.
class _SourceToggleFab extends StatelessWidget {
  final VoidCallback onSourceChanged;
  const _SourceToggleFab({required this.onSourceChanged});

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<DataSourceNotifier>();
    final isMock = notifier.isMock;
    final isToggling = notifier.toggling;

    return FloatingActionButton.extended(
      backgroundColor: const Color(0xFF1A1A2E),
      tooltip: isMock ? 'Switch to live BLE' : 'Switch to mock demo',
      onPressed: isToggling ? null : () async {
        // 1. Stop old source and switch (fully awaited)
        await notifier.toggle();
        // 2. Provider rebuild is done. Wait one frame so the
        //    Provider<DataSource> subtree has the new instance,
        //    then re-subscribe and start.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          onSourceChanged();
        });
      },
      icon: isToggling
          ? const SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54))
          : Icon(
              isMock ? Icons.bluetooth : Icons.science,
              color: isMock ? Colors.lightBlueAccent : Colors.orangeAccent,
              size: 18,
            ),
      label: Text(
        isToggling ? 'Switching...' : (isMock ? 'Go Live (BLE)' : 'Demo Mode'),
        style: const TextStyle(fontSize: 12, color: Colors.white70),
      ),
    );
  }
}
