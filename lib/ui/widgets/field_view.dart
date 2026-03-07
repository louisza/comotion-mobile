// lib/ui/widgets/field_view.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../data/models/player_state.dart';
import 'player_dot.dart';

/// Satellite-map field view with player dots overlaid at GPS coordinates.
///
/// Uses Esri World Imagery tiles (free, no API key).
/// Field corners are optional — if set, the map zooms to the defined rectangle
/// and a white overlay outlines the playing area.
class FieldView extends StatefulWidget {
  final List<PlayerState> players;
  final String? selectedPlayerId;
  final ValueChanged<PlayerState>? onPlayerTap;

  /// Optional field boundary: [topLeft, topRight, bottomRight, bottomLeft].
  final List<LatLng>? fieldCorners;

  /// When no field corners or player positions exist, center here.
  final LatLng? defaultCenter;

  const FieldView({
    super.key,
    required this.players,
    this.selectedPlayerId,
    this.onPlayerTap,
    this.fieldCorners,
    this.defaultCenter,
  });

  @override
  State<FieldView> createState() => _FieldViewState();
}

class _FieldViewState extends State<FieldView> {
  final MapController _mapController = MapController();
  bool _initialFitDone = false;

  @override
  void didUpdateWidget(covariant FieldView old) {
    super.didUpdateWidget(old);
    // Re-fit when corners change (new calibration)
    if (widget.fieldCorners != old.fieldCorners && widget.fieldCorners != null) {
      _fitToCorners();
    }
  }

  void _fitToCorners() {
    if (widget.fieldCorners == null || widget.fieldCorners!.length < 2) return;
    try {
      final bounds = LatLngBounds.fromPoints(widget.fieldCorners!);
      _mapController.fitCamera(CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(24)));
    } catch (_) {}
  }

  LatLng get _center {
    // Priority: field corners center > first player with GPS > default > Pretoria
    if (widget.fieldCorners != null && widget.fieldCorners!.length >= 2) {
      final bounds = LatLngBounds.fromPoints(widget.fieldCorners!);
      return bounds.center;
    }
    for (final p in widget.players) {
      if (p.position != null) return p.position!;
    }
    return widget.defaultCenter ?? const LatLng(-25.7479, 28.2293);
  }

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _center,
        initialZoom: 18.0,
        maxZoom: 20.0,
        minZoom: 14.0,
        onMapReady: () {
          if (!_initialFitDone && widget.fieldCorners != null) {
            _fitToCorners();
            _initialFitDone = true;
          }
        },
      ),
      children: [
        // Esri World Imagery — free satellite tiles, no API key
        TileLayer(
          urlTemplate: 'https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}',
          userAgentPackageName: 'com.comotion.mobile',
          maxZoom: 20,
        ),

        // Field boundary outline (if corners defined)
        if (widget.fieldCorners != null && widget.fieldCorners!.length >= 4)
          PolygonLayer(
            polygons: [
              Polygon(
                points: widget.fieldCorners!,
                borderColor: Colors.white,
                borderStrokeWidth: 2.0,
                color: Colors.white.withOpacity(0.05),
              ),
            ],
          ),

        // Player trails
        PolylineLayer(
          polylines: widget.players
              .where((p) => p.trail.length >= 2)
              .map((p) => Polyline(
                    points: p.trail,
                    color: PlayerDot.intensityColor(p.intensity30s).withOpacity(0.5),
                    strokeWidth: 3.0,
                  ))
              .toList(),
        ),

        // Player dots as markers
        MarkerLayer(
          markers: widget.players
              .where((p) => p.position != null)
              .map((p) {
            final ageSec = DateTime.now().difference(p.lastSeen).inSeconds;
            final opacity = ageSec > 15 ? 0.3 : ageSec > 10 ? 0.6 : 1.0;
            return Marker(
              point: p.position!,
              width: 48,
              height: 48,
              child: Opacity(
                opacity: opacity,
                child: PlayerDot(
                  state: p,
                  radius: 20,
                  selected: p.player.id == widget.selectedPlayerId,
                  onTap: () => widget.onPlayerTap?.call(p),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
