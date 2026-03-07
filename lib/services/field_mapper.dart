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
  final LatLng centerSpot;
  final LatLng sidelineMid;
  final double fieldWidthM;

  /// Explicit corners [topLeft, topRight, bottomRight, bottomLeft].
  /// If null, computed from centerSpot + sidelineMid.
  final List<LatLng>? _explicitCorners;

  static const double kFieldLengthM = 91.4;
  static const double kFieldWidthM = 55.0;

  const FieldCalibration({
    required this.centerSpot,
    required this.sidelineMid,
    this.fieldWidthM = kFieldWidthM,
    List<LatLng>? corners,
  }) : _explicitCorners = corners;

  List<LatLng> get corners {
    if (_explicitCorners != null && _explicitCorners!.length >= 4) {
      return _explicitCorners!;
    }
    // Compute from center + sideline (legacy)
    return _computeCorners();
  }

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

  /// The 4 field corners computed from center + sideline orientation.
  List<LatLng> _computeCorners() {
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
///
/// Coordinate system:
///   Canvas x (u) = along the field LENGTH (left ↔ right from coach's view)
///   Canvas y (v) = across the field WIDTH  (far sideline at top, coach at bottom)
///
/// The calibration gives us two points: center spot + sideline midpoint.
/// From these we derive the field orientation (rotation) and project GPS
/// coordinates onto the field's own axes using dot products.
class FieldMapper {
  final FieldCalibration? calibration;

  const FieldMapper({this.calibration});

  /// Standard hockey field aspect ratio (91.4m × 55m → ~1.66:1).
  static const double kFieldAspect = 91.4 / 55.0;

  /// Map a GPS [point] to canvas coordinates within a canvas of [size].
  Offset? toCanvas(LatLng point, Size size) {
    if (calibration != null) {
      return _calibratedMap(point, size, calibration!);
    }
    return _defaultMap(point, size);
  }

  /// Project GPS point onto the field's rotated coordinate system.
  ///
  /// How it works:
  ///   1. Compute bearing from sideline → center (this is the "short axis"
  ///      = across the field width).
  ///   2. Long axis = short axis + 90° (along the field length).
  ///   3. Convert GPS offset from field center to metres.
  ///   4. Dot-product with each axis unit vector → field-local coordinates.
  ///   5. Normalize to 0..1 range using known field dimensions.
  Offset? _calibratedMap(LatLng point, Size size, FieldCalibration cal) {
    final center = cal.centerSpot;
    final cosLat = cos(center.latitude * pi / 180);

    // Offset from field center in metres (north, east)
    final dNorth = (point.latitude - center.latitude) * 111320.0;
    final dEast  = (point.longitude - center.longitude) * 111320.0 * cosLat;

    // Bearing from sideline midpoint → center spot (radians from north, CW)
    final scN = (center.latitude - cal.sidelineMid.latitude) * 111320.0;
    final scE = (center.longitude - cal.sidelineMid.longitude) * 111320.0 * cosLat;
    final bearingRad = atan2(scE, scN);

    // Long axis = perpendicular to sideline→center (along field length)
    final longBearing = bearingRad + pi / 2;

    // Project onto field axes via dot product:
    //   longAxis  unit vector = (cos(longBearing), sin(longBearing)) in (N, E)
    //   shortAxis unit vector = (cos(bearingRad),  sin(bearingRad))  in (N, E)
    final fieldLong  = dNorth * cos(longBearing) + dEast * sin(longBearing);
    final fieldShort = dNorth * cos(bearingRad)  + dEast * sin(bearingRad);

    // fieldLong:  -halfLength..+halfLength (along field)
    // fieldShort: -halfWidth..+halfWidth   (positive = toward coach/sideline)
    final halfLength = FieldCalibration.kFieldLengthM / 2;
    final halfWidth  = cal.fieldWidthM / 2;

    // Canvas mapping:
    //   u (x): left=0 to right=1 along field length
    //   v (y): top=0 (far sideline) to bottom=1 (coach sideline)
    //
    // fieldShort positive = toward center from sideline = away from coach = top
    // So we INVERT: v = 1 - normalized to put coach at bottom
    final u = (fieldLong / halfLength + 1.0) / 2.0;
    final v = 1.0 - (fieldShort / halfWidth + 1.0) / 2.0;

    // Allow 10% overflow before clipping (player slightly off-field)
    if (u < -0.1 || u > 1.1 || v < -0.1 || v > 1.1) return null;
    return Offset(
      u.clamp(0.0, 1.0) * size.width,
      v.clamp(0.0, 1.0) * size.height,
    );
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
