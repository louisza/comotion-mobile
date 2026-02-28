// lib/ui/widgets/field_view.dart
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../data/models/player_state.dart';
import '../../services/field_mapper.dart';
import 'player_dot.dart';

/// Top-down hockey field view with player dots and trails.
///
/// Draws a green field with white markings, then overlays player dots
/// positioned by GPS. Trails are shown as fading dots behind each player.
class FieldView extends StatelessWidget {
  final List<PlayerState> players;
  final FieldMapper mapper;
  final String? selectedPlayerId;
  final ValueChanged<PlayerState>? onPlayerTap;

  const FieldView({
    super.key,
    required this.players,
    required this.mapper,
    this.selectedPlayerId,
    this.onPlayerTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      return Stack(
        children: [
          // Field background painting.
          CustomPaint(
            size: size,
            painter: _FieldPainter(),
          ),

          // Trails layer.
          CustomPaint(
            size: size,
            painter: _TrailsPainter(players: players, mapper: mapper, size: size),
          ),

          // Player dots — positioned absolutely.
          ...players
              .where((p) => p.position != null)
              .map((p) => _buildDot(p, size)),
        ],
      );
    });
  }

  Widget _buildDot(PlayerState p, Size canvasSize) {
    final pos = mapper.toCanvas(p.position!, canvasSize);
    if (pos == null) return const SizedBox.shrink();

    const r = 20.0;
    return Positioned(
      left: pos.dx - r - 3,
      top: pos.dy - r - 3,
      child: PlayerDot(
        state: p,
        radius: r,
        selected: p.player.id == selectedPlayerId,
        onTap: () => onPlayerTap?.call(p),
      ),
    );
  }
}

/// Paints the hockey field: green surface + white lines.
class _FieldPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Field surface.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..color = const Color(0xFF2E7D32),
    );

    final whiteLine = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // Outer boundary.
    canvas.drawRect(
      Rect.fromLTRB(w * 0.02, h * 0.02, w * 0.98, h * 0.98),
      whiteLine,
    );

    // Centre line.
    canvas.drawLine(Offset(w / 2, h * 0.02), Offset(w / 2, h * 0.98), whiteLine);

    // Centre circle.
    canvas.drawCircle(Offset(w / 2, h / 2), h * 0.12, whiteLine);

    // Penalty spots (D circles).
    final dRadius = h * 0.22;
    // Left D.
    canvas.drawArc(
      Rect.fromCircle(center: Offset(w * 0.12, h / 2), radius: dRadius),
      -1.0,
      2.0,
      false,
      whiteLine,
    );
    // Right D.
    canvas.drawArc(
      Rect.fromCircle(center: Offset(w * 0.88, h / 2), radius: dRadius),
      2.14,
      2.0,
      false,
      whiteLine,
    );

    // Goal posts (simplified).
    final goalWidth = h * 0.15;
    final goalDepth = w * 0.015;
    // Left goal.
    canvas.drawRect(
      Rect.fromLTWH(w * 0.02 - goalDepth, h / 2 - goalWidth / 2, goalDepth, goalWidth),
      whiteLine,
    );
    // Right goal.
    canvas.drawRect(
      Rect.fromLTWH(w * 0.98, h / 2 - goalWidth / 2, goalDepth, goalWidth),
      whiteLine,
    );

    // 23m lines.
    canvas.drawLine(Offset(w * 0.25, h * 0.02), Offset(w * 0.25, h * 0.98), whiteLine);
    canvas.drawLine(Offset(w * 0.75, h * 0.02), Offset(w * 0.75, h * 0.98), whiteLine);
  }

  @override
  bool shouldRepaint(_FieldPainter _) => false;
}

/// Paints fading trail lines behind each player.
class _TrailsPainter extends CustomPainter {
  final List<PlayerState> players;
  final FieldMapper mapper;
  final Size size;

  const _TrailsPainter({
    required this.players,
    required this.mapper,
    required this.size,
  });

  @override
  void paint(Canvas canvas, Size canvasSize) {
    for (final p in players) {
      if (p.trail.length < 2) continue;
      final points = p.trail
          .map((pos) => mapper.toCanvas(pos, canvasSize))
          .whereType<Offset>()
          .toList();
      if (points.length < 2) continue;

      final color = PlayerDot.intensityColor(p.intensity30s);

      for (int i = 1; i < points.length; i++) {
        final alpha = (i / points.length * 0.6).clamp(0.0, 1.0);
        canvas.drawLine(
          points[i - 1],
          points[i],
          Paint()
            ..color = color.withOpacity(alpha)
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_TrailsPainter old) => true; // always repaint on new data
}
