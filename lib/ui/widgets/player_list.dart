// lib/ui/widgets/player_list.dart
import 'package:flutter/material.dart';


import '../../data/models/player_state.dart';
import 'player_dot.dart';

/// Scrollable roster list shown at the bottom of the game screen.
class PlayerList extends StatelessWidget {
  final List<PlayerState> players;
  final String? selectedPlayerId;
  final ValueChanged<PlayerState>? onPlayerTap;

  const PlayerList({
    super.key,
    required this.players,
    this.selectedPlayerId,
    this.onPlayerTap,
  });

  @override
  Widget build(BuildContext context) {
    if (players.isEmpty) {
      return const Center(
        child: Text(
          'No players detected',
          style: TextStyle(color: Colors.white38),
        ),
      );
    }

    return ListView.builder(
      scrollDirection: Axis.horizontal,
      itemCount: players.length,
      itemBuilder: (context, index) =>
          _PlayerCard(state: players[index], onTap: () => onPlayerTap?.call(players[index])),
    );
  }
}

class _PlayerCard extends StatelessWidget {
  final PlayerState state;
  final VoidCallback onTap;

  const _PlayerCard({required this.state, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final intensityColor = PlayerDot.intensityColor(state.intensity30s);
    final batteryColor = state.batteryPercent > 30
        ? Colors.greenAccent
        : state.batteryPercent > 15
            ? Colors.yellowAccent
            : Colors.redAccent;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 90,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E3A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: state.player.color.withOpacity(0.4), width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Mini dot indicator.
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: intensityColor,
              ),
              child: Center(
                child: Text(
                  '${state.player.number}',
                  style: const TextStyle(
                      fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              state.player.name.split(' ').first,
              style: const TextStyle(
                  fontSize: 10, color: Colors.white70, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            // Intensity bar.
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: state.intensity30s / 255.0,
                minHeight: 4,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation<Color>(intensityColor),
              ),
            ),
            const SizedBox(height: 4),
            // Battery.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.battery_full, size: 10, color: batteryColor),
                Text(
                  '${state.batteryPercent}%',
                  style: TextStyle(fontSize: 9, color: batteryColor),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
