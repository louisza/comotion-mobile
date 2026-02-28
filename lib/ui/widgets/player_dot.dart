// lib/ui/widgets/player_dot.dart
import 'package:flutter/material.dart';

import '../../data/models/player_state.dart';

/// A circular player marker with dual intensity rings and jersey number.
///
/// - Inner filled circle:  intensity30s colour
/// - Outer ring stroke:    intensity5min colour
/// - Centre label:         jersey number
///
/// Intensity colour scale: 0-84=green, 85-169=yellow, 170-255=red.
class PlayerDot extends StatelessWidget {
  final PlayerState state;
  final double radius;
  final bool selected;
  final VoidCallback? onTap;

  const PlayerDot({
    super.key,
    required this.state,
    this.radius = 20,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: CustomPaint(
        size: Size(radius * 2 + 6, radius * 2 + 6),
        painter: _DotPainter(
          innerColor: intensityColor(state.intensity30s),
          outerColor: intensityColor(state.intensity5min),
          number: state.player.number,
          selected: selected,
          radius: radius,
        ),
      ),
    );
  }

  /// Convert 0-255 intensity to a colour on green→yellow→red scale.
  static Color intensityColor(int intensity) {
    final t = (intensity / 255.0).clamp(0.0, 1.0);
    if (t < 0.5) {
      // green → yellow
      return Color.lerp(const Color(0xFF4CAF50), const Color(0xFFFFEB3B), t * 2)!;
    } else {
      // yellow → red
      return Color.lerp(const Color(0xFFFFEB3B), const Color(0xFFF44336), (t - 0.5) * 2)!;
    }
  }
}

class _DotPainter extends CustomPainter {
  final Color innerColor;
  final Color outerColor;
  final int number;
  final bool selected;
  final double radius;

  const _DotPainter({
    required this.innerColor,
    required this.outerColor,
    required this.number,
    required this.selected,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Selection glow.
    if (selected) {
      canvas.drawCircle(
        center,
        radius + 5,
        Paint()
          ..color = Colors.white.withOpacity(0.5)
          ..style = PaintingStyle.fill,
      );
    }

    // Outer ring (intensity5min).
    canvas.drawCircle(
      center,
      radius + 3,
      Paint()
        ..color = outerColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    // Inner filled circle (intensity30s).
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = innerColor
        ..style = PaintingStyle.fill,
    );

    // Jersey number label.
    final tp = TextPainter(
      text: TextSpan(
        text: '$number',
        style: TextStyle(
          color: Colors.white,
          fontSize: radius * 0.7,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_DotPainter old) =>
      old.innerColor != innerColor ||
      old.outerColor != outerColor ||
      old.selected != selected;
}
