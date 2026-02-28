// lib/ui/widgets/player_card.dart
import 'package:flutter/material.dart';


import '../../data/models/player_state.dart';
import 'player_dot.dart';

/// Bottom sheet showing detailed metrics for a single player.
void showPlayerCard(BuildContext context, PlayerState state) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1A1A2E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => PlayerCard(state: state),
  );
}

class PlayerCard extends StatelessWidget {
  final PlayerState state;

  const PlayerCard({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme
        .apply(bodyColor: Colors.white, displayColor: Colors.white);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar.
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header: number + name + GPS.
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: state.player.color,
                child: Text(
                  '${state.player.number}',
                  style: textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(state.player.name,
                        style: textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    Text(
                      state.hasGpsFix
                          ? '${state.gpsSatellites} sats · ${state.gpsAgeSec}s ago'
                          : 'No GPS fix',
                      style: textTheme.bodySmall
                          ?.copyWith(color: Colors.white54),
                    ),
                  ],
                ),
              ),
              _BatteryBadge(percent: state.batteryPercent),
            ],
          ),
          const SizedBox(height: 24),

          // Intensity gauge.
          Text('Intensity (1s)', style: textTheme.labelLarge?.copyWith(color: Colors.white54)),
          const SizedBox(height: 6),
          _IntensityGauge(value: state.intensity1s / 255.0),
          const SizedBox(height: 20),

          // Sparkline.
          Text('Last 5 min', style: textTheme.labelLarge?.copyWith(color: Colors.white54)),
          const SizedBox(height: 6),
          SizedBox(
            height: 48,
            child: _Sparkline(samples: state.intensityHistory),
          ),
          const SizedBox(height: 20),

          // Stats grid.
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _StatChip(label: 'Speed', value: '${state.speedKmh} km/h'),
              _StatChip(label: 'Max Speed', value: '${state.maxSpeedKmh} km/h'),
              _StatChip(label: 'Impacts', value: '${state.impactCount}'),
              _StatChip(label: 'Movements', value: '${state.movementCount}'),
              _StatChip(
                label: 'Session',
                value: _formatTime(state.sessionTimeSec),
              ),
              _StatChip(label: 'Int. 1min', value: state.intensity1min.toString()),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

class _IntensityGauge extends StatelessWidget {
  final double value; // 0-1

  const _IntensityGauge({required this.value});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: LinearProgressIndicator(
        value: value,
        minHeight: 20,
        backgroundColor: Colors.white12,
        valueColor: AlwaysStoppedAnimation<Color>(
          PlayerDot.intensityColor((value * 255).toInt()),
        ),
      ),
    );
  }
}

class _Sparkline extends StatelessWidget {
  final List<int> samples;

  const _Sparkline({required this.samples});

  @override
  Widget build(BuildContext context) {
    if (samples.isEmpty) {
      return const Center(
        child: Text('No data yet', style: TextStyle(color: Colors.white38)),
      );
    }
    return CustomPaint(
      painter: _SparklinePainter(samples: samples),
      size: Size.infinite,
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<int> samples;
  const _SparklinePainter({required this.samples});

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.length < 2) return;

    final path = Path();
    for (int i = 0; i < samples.length; i++) {
      final x = i / (samples.length - 1) * size.width;
      final y = size.height - (samples[i] / 255.0) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = PlayerDot.intensityColor(samples.last)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) => old.samples != samples;
}

class _BatteryBadge extends StatelessWidget {
  final int percent;
  const _BatteryBadge({required this.percent});

  @override
  Widget build(BuildContext context) {
    final color = percent > 30
        ? const Color(0xFF4CAF50)
        : percent > 15
            ? const Color(0xFFFFEB3B)
            : const Color(0xFFF44336);
    return Row(
      children: [
        Icon(Icons.battery_full, color: color, size: 18),
        const SizedBox(width: 2),
        Text('$percent%', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ],
      ),
    );
  }
}
