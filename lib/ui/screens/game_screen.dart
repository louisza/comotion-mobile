// lib/ui/screens/game_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import '../../data/models/player_state.dart';
import '../../data/sources/data_source.dart';
import '../../services/field_mapper.dart';
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

  final FieldMapper _mapper = const FieldMapper();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _subscribe());
  }

  void _subscribe() {
    final source = context.read<DataSource>();
    _sub?.cancel();
    _sub = source.playerStates.listen((players) {
      if (mounted) setState(() => _players = players);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _sessionTimer?.cancel();
    super.dispose();
  }

  void _toggleSession() {
    final source = context.read<DataSource>();
    if (_sessionActive) {
      _sessionTimer?.cancel();
      source.stop();
    } else {
      _sessionSeconds = 0;
      _sessionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _sessionSeconds++);
      });
      source.start();
    }
    setState(() => _sessionActive = !_sessionActive);
  }

  String _formatTimer(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final connectedCount = _players.where((p) => p.hasGpsFix).length;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Row(
          children: [
            // Session timer.
            Text(
              _formatTimer(_sessionSeconds),
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  letterSpacing: 1.5),
            ),
            const SizedBox(width: 16),
            // Connected count.
            Row(
              children: [
                const Icon(Icons.bluetooth_connected, color: Colors.lightBlueAccent, size: 16),
                const SizedBox(width: 4),
                Text(
                  '$connectedCount/${_players.length}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ],
        ),
        actions: [
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
          // Field view: 80% of available height.
          Expanded(
            flex: 4,
            child: FieldView(
              players: _players,
              mapper: _mapper,
              selectedPlayerId: _selectedPlayerId,
              onPlayerTap: (p) {
                setState(() => _selectedPlayerId = p.player.id);
                showPlayerCard(context, p);
              },
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
      floatingActionButton: _SourceToggleFab(onSourceChanged: _subscribe),
    );
  }
}

/// Debug FAB to toggle between Mock and BLE data source.
class _SourceToggleFab extends StatelessWidget {
  final VoidCallback onSourceChanged;
  const _SourceToggleFab({required this.onSourceChanged});

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<DataSourceNotifier>();
    final isMock = notifier.isMock;

    return FloatingActionButton.small(
      backgroundColor: const Color(0xFF1A1A2E),
      tooltip: isMock ? 'Switch to BLE' : 'Switch to Mock',
      onPressed: () {
        notifier.toggle();
        onSourceChanged();
      },
      child: Icon(
        isMock ? Icons.wifi_tethering : Icons.bluetooth,
        color: isMock ? Colors.orangeAccent : Colors.lightBlueAccent,
        size: 18,
      ),
    );
  }
}
