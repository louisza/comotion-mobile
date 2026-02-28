// lib/services/field_mapper.dart
import 'dart:math';

import 'package:flutter/painting.dart';
import 'package:latlong2/latlong.dart';

/// Defines a field by two GPS points:
///   - [centerSpot]   : GPS position of the center spot (from tracker)
///   - [sidelineMid]  : GPS position of the halfway sideline (from coach's phone)
///
/// From these two points the mapper derives:
///   - Field center and orientation (rotation angle)
///   - Field scale (distance * 2 = full field width, standard = 55m)
///   - Full 4-corner bounding box for any standard hockey field
class FieldCalibration {
  /// GPS center spot — set from the tracker's position.
  final LatLng centerSpot;

  /// GPS halfway sideline — set from the coach's phone GPS.
  final LatLng sidelineMid;

  /// Actual field width in metres (defaults to 55m standard hockey).
  /// App auto-computes this from the two-point distance × 2, but can be overridden.
  final double fieldWidthM;

  /// Standard hockey field length in metres.
  static const double kFieldLengthM = 91.4;

  /// Standard hockey field width in metres.
  static const double kFieldWidthM = 55.0;

  const FieldCalibration({
    required this.centerSpot,
    required this.sidelineMid,
    this.fieldWidthM = kFieldWidthM,
  });

  /// Bearing in radians from sidelineMid → centerSpot.
  /// This vector is perpendicular to the long axis of the field.
  double get _bearingToCenter {
    final dLat = centerSpot.latitude - sidelineMid.latitude;
    final dLng = (centerSpot.longitude - sidelineMid.longitude) *
        cos(centerSpot.latitude * pi / 180);
    return atan2(dLng, dLat); // radians, 0 = north
  }

  /// Bearing along the long axis of the field (perpendicular to sideline→center).
  double get _fieldLongAxisBearing => _bearingToCenter + pi / 2;

  /// Half-width in degrees latitude (for offset calculations).
  double get _halfWidthDegLat => (fieldWidthM / 2) / 111320.0;

  /// Half-length in degrees (along long axis).
  double get _halfLengthDegLat => (kFieldLengthM / 2) / 111320.0;

  double get _cosLat => cos(centerSpot.latitude * pi / 180);

  /// Compute a GPS point offset from [origin] by [distLat] degrees lat
  /// and [distLng] degrees lng.
  LatLng _offset(LatLng origin, double dLat, double dLng) =>
      LatLng(origin.latitude + dLat, origin.longitude + dLng);

  /// Unit vector along the long axis of the field.
  (double dLat, double dLng) get _longAxis {
    final b = _fieldLongAxisBearing;
    return (cos(b), sin(b) / _cosLat);
  }

  /// Unit vector along the short axis (sideline → center).
  (double dLat, double dLng) get _shortAxis {
    final b = _bearingToCenter;
    return (cos(b), sin(b) / _cosLat);
  }

  /// The 4 field corners: [topLeft, topRight, bottomRight, bottomLeft]
  /// as viewed with the sideline at the bottom.
  List<LatLng> get corners {
    final (lLat, lLng) = _longAxis;
    final (sLat, sLng) = _shortAxis;
    final hw = _halfWidthDegLat;
    final hl = _halfLengthDegLat;

    final c = centerSpot;

    // topLeft    = center - half_long + half_short (far end, left)
    final topLeft = _offset(c,
        -hl * lLat + hw * sLat,
        -hl * lLng + hw * sLng);
    // topRight   = center + half_long + half_short (far end, right)
    final topRight = _offset(c,
        hl * lLat + hw * sLat,
        hl * lLng + hw * sLng);
    // bottomRight = center + half_long - half_short (near end, right)
    final bottomRight = _offset(c,
        hl * lLat - hw * sLat,
        hl * lLng - hw * sLng);
    // bottomLeft  = center - half_long - half_short (near end, left)
    final bottomLeft = _offset(c,
        -hl * lLat - hw * sLat,
        -hl * lLng - hw * sLng);

    return [topLeft, topRight, bottomRight, bottomLeft];
  }

  /// Measured half-width from the two calibration points (metres).
  double get measuredHalfWidthM => FieldMapper.distanceMetres(centerSpot, sidelineMid);

  /// Measured full width (metres). Should be ~55m for a standard field.
  double get measuredWidthM => measuredHalfWidthM * 2;
}

/// Maps GPS coordinates to canvas pixel positions given a [FieldCalibration].
///
/// Falls back to the default mock bounds if no calibration is set.
class FieldMapper {
  final FieldCalibration? calibration;

  const FieldMapper({this.calibration});

  /// Standard hockey field aspect ratio (91.4m × 55m → ~1.66:1).
  static const double kFieldAspect = 91.4 / 55.0;

  /// Map a GPS [point] to canvas coordinates within a canvas of [size].
  Offset? toCanvas(LatLng point, Size size) {
    if (calibration != null) {
      return _calibratedMap(point, size, calibration!.corners);
    }
    return _defaultMap(point, size);
  }

  /// Bilinear map using the 4 computed corners from calibration.
  Offset? _calibratedMap(LatLng point, Size size, List<LatLng> corners) {
    final tl = corners[0];
    final tr = corners[1];
    final br = corners[2];
    final bl = corners[3];

    double u = 0.5, v = 0.5;
    for (int i = 0; i < 10; i++) {
      final top   = _lerp(tl, tr, u);
      final bot   = _lerp(bl, br, u);
      final left  = _lerp(tl, bl, v);
      final right = _lerp(tr, br, v);
      final newV  = _fraction(top, bot, point, axis: 'lat');
      final newU  = _fraction(left, right, point, axis: 'lng');
      u = newU;
      v = newV;
    }

    if (u < -0.1 || u > 1.1 || v < -0.1 || v > 1.1) return null;
    return Offset(u.clamp(0.0, 1.0) * size.width, v.clamp(0.0, 1.0) * size.height);
  }

  LatLng _lerp(LatLng a, LatLng b, double t) =>
      LatLng(a.latitude  + (b.latitude  - a.latitude)  * t,
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
