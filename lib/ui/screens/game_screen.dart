// lib/ui/screens/game_screen.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/player_state.dart';
import '../../data/sources/ble_direct_source.dart';
import '../../data/sources/data_source.dart';
import '../../services/field_calibration_service.dart';
import '../../services/field_mapper.dart';
import '../widgets/field_calibration_sheet.dart';
import '../../../main.dart' show DataSourceNotifier;
import '../widgets/field_view.dart';
import '../widgets/player_card.dart';
import '../widgets/player_list.dart';

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

  // Session timer.
  int _sessionSeconds = 0;
  Timer? _sessionTimer;
  bool _sessionActive = false;
  bool _debugOverlay = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _subscribe());
  }

  void _subscribe() {
    final source = context.read<DataSource>();
    _sub?.cancel();
    _sub = source.playerStates.listen((players) {
      if (mounted) {
        setState(() => _players = players);
        // Feed first player's GPS into calibration service if it's waiting
        final calSvc = context.read<FieldCalibrationService>();
        if (calSvc.step == CalibrationStep.waitingTracker) {
          for (final p in players) {
            if (p.hasGpsFix && p.position != null) {
              calSvc.setTrackerCenter(p.position!);
              break;
            }
          }
        }
      }
    });
  }

  /// Called when the user switches data source (mock ↔ BLE).
  /// Stops the old source, resets session, re-subscribes, and auto-starts.
  void _onSourceChanged() {
    // Stop any running session first.
    _sessionTimer?.cancel();
    setState(() {
      _sessionActive = false;
      _sessionSeconds = 0;
      _players = [];
    });
    // Re-subscribe to new source stream.
    _subscribe();
    // Auto-start the new source so players appear immediately.
    _startSession();
  }

  void _startSession() {
    final source = context.read<DataSource>();
    _sessionSeconds = 0;
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _sessionSeconds++);
    });
    source.start();
    setState(() => _sessionActive = true);
  }

  void _stopSession() {
    final source = context.read<DataSource>();
    _sessionTimer?.cancel();
    source.stop();
    setState(() {
      _sessionActive = false;
      _sessionSeconds = 0;
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _sessionTimer?.cancel();
    super.dispose();
  }

  void _toggleSession() {
    if (_sessionActive) {
      _stopSession();
    } else {
      _startSession();
    }
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
              final hexStr = raw.take(23).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
              // Decode based on length
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
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${p.player.name} [${len}B] spd_byte=$spdByte (${spdByte / 2.0}km/h)\n$gpsStr\npos=$posStr\n$hexStr',
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
    final calSvc = context.watch<FieldCalibrationService>();
    final mapper = calSvc.fieldMapper;

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
          // Calibration button
          IconButton(
            onPressed: () => showFieldCalibrationSheet(context),
            icon: Icon(
              Icons.gps_fixed,
              color: calSvc.isCalibrated ? Colors.greenAccent : Colors.white38,
              size: 22,
            ),
            tooltip: calSvc.isCalibrated ? 'Field calibrated' : 'Calibrate field',
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ElevatedButton.icon(
              onPressed: _toggleSession,
              icon: Icon(_sessionActive ? Icons.stop : Icons.play_arrow, size: 16),
              label: Text(_sessionActive ? 'Stop' : 'Start'),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _sessionActive ? const Color(0xFFF44336) : const Color(0xFF4CAF50),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Calibration hint banner (shown when not calibrated)
          if (!calSvc.isCalibrated)
            GestureDetector(
              onTap: () => showFieldCalibrationSheet(context),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                color: const Color(0xFF2196F3).withOpacity(0.15),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Color(0xFF2196F3), size: 14),
                    SizedBox(width: 8),
                    Text(
                      'Tap GPS icon to calibrate field for accurate player positions',
                      style: TextStyle(color: Color(0xFF2196F3), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),

          // Field view: 80% of available height.
          Expanded(
            flex: 4,
            child: Stack(
              children: [
                FieldView(
                  players: _players,
                  mapper: mapper,
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
