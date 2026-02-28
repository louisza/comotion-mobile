// lib/services/field_mapper.dart
import 'dart:math';

import 'package:flutter/painting.dart';
import 'package:latlong2/latlong.dart';

/// Maps GPS coordinates to canvas pixel positions given 4 corner coordinates.
///
/// Corner order: [topLeft, topRight, bottomRight, bottomLeft]
/// (matching the field as viewed from above, north-ish up)
///
/// If no corners are configured, defaults to a 91.4m × 55m hockey field
/// centred on a placeholder origin, and maps proportionally.
class FieldMapper {
  /// GPS corners: [topLeft, topRight, bottomRight, bottomLeft]
  final List<LatLng>? corners;

  const FieldMapper({this.corners});

  /// Standard hockey field aspect ratio (91.4m × 55m → ~1.66:1).
  static const double kFieldAspect = 91.4 / 55.0;

  /// Map a GPS [point] to canvas coordinates within a canvas of [size].
  /// Returns null if the point cannot be mapped.
  Offset? toCanvas(LatLng point, Size size) {
    if (corners != null && corners!.length == 4) {
      return _bilinearMap(point, size);
    }
    return _defaultMap(point, size);
  }

  /// Bilinear interpolation across the 4-corner quadrilateral.
  Offset? _bilinearMap(LatLng point, Size size) {
    final tl = corners![0];
    final tr = corners![1];
    final br = corners![2];
    final bl = corners![3];

    // Compute u,v in [0,1] via iterative bilinear inversion.
    // For small fields the simple average approach works well.
    double u = 0.5, v = 0.5;
    for (int i = 0; i < 10; i++) {
      final top = _lerp(tl, tr, u);
      final bot = _lerp(bl, br, u);
      final left = _lerp(tl, bl, v);
      final right = _lerp(tr, br, v);
      final newV = _fraction(top, bot, point, axis: 'lat');
      final newU = _fraction(left, right, point, axis: 'lng');
      u = newU;
      v = newV;
    }

    if (u < -0.05 || u > 1.05 || v < -0.05 || v > 1.05) return null;
    return Offset(u.clamp(0, 1) * size.width, v.clamp(0, 1) * size.height);
  }

  LatLng _lerp(LatLng a, LatLng b, double t) =>
      LatLng(a.latitude + (b.latitude - a.latitude) * t,
          a.longitude + (b.longitude - a.longitude) * t);

  double _fraction(LatLng a, LatLng b, LatLng p, {required String axis}) {
    if (axis == 'lat') {
      final range = b.latitude - a.latitude;
      if (range.abs() < 1e-10) return 0.5;
      return ((p.latitude - a.latitude) / range).clamp(0.0, 1.0);
    } else {
      final range = b.longitude - a.longitude;
      if (range.abs() < 1e-10) return 0.5;
      return ((p.longitude - a.longitude) / range).clamp(0.0, 1.0);
    }
  }

  /// Fallback mapping using the default mock GPS bounds.
  Offset _defaultMap(LatLng point, Size size) {
    const latMin = -26.0010;
    const latMax = -25.9990;
    const lngMin = 28.0990;
    const lngMax = 28.1010;

    final u = ((point.longitude - lngMin) / (lngMax - lngMin)).clamp(0.0, 1.0);
    final v = 1.0 - ((point.latitude - latMin) / (latMax - latMin)).clamp(0.0, 1.0);
    return Offset(u * size.width, v * size.height);
  }

  /// Returns the recommended canvas Size given available width, preserving
  /// the standard hockey field aspect ratio.
  static Size recommendedSize(double availableWidth) =>
      Size(availableWidth, availableWidth / kFieldAspect);

  /// Haversine distance in metres between two GPS points.
  static double distanceMetres(LatLng a, LatLng b) {
    const R = 6371000.0;
    final dLat = _toRad(b.latitude - a.latitude);
    final dLng = _toRad(b.longitude - a.longitude);
    final sinDlat = sin(dLat / 2);
    final sinDlng = sin(dLng / 2);
    final hav = sinDlat * sinDlat +
        cos(_toRad(a.latitude)) * cos(_toRad(b.latitude)) * sinDlng * sinDlng;
    return 2 * R * asin(sqrt(hav));
  }

  static double _toRad(double deg) => deg * pi / 180;
}
