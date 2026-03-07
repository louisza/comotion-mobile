// lib/services/field_calibration_service.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import 'field_mapper.dart';

/// Step in the field calibration flow.
enum CalibrationStep {
  idle,           // Not calibrating
  waitingTracker, // Waiting for tracker GPS to appear (center spot)
  captureCoach,   // Waiting for coach to tap "Capture My Position"
  done,           // Calibration complete
}

/// Manages field calibration.
///
/// Two modes:
///   1. **Two-point** (legacy): tracker on center + coach sideline position.
///   2. **Corner tap** (new): user taps two diagonal corners on the satellite map.
///
/// Both produce a [FieldCalibration] with 4 corners and a center.
class FieldCalibrationService extends ChangeNotifier {
  CalibrationStep _step = CalibrationStep.idle;
  LatLng? _trackerCenter;
  LatLng? _coachPosition;
  FieldCalibration? _calibration;
  String? _error;
  bool _capturingGps = false;
  String? _gpsStatus;

  CalibrationStep get step => _step;
  LatLng? get trackerCenter => _trackerCenter;
  LatLng? get coachPosition => _coachPosition;
  FieldCalibration? get calibration => _calibration;
  String? get error => _error;
  bool get capturingGps => _capturingGps;
  bool get isCalibrated => _calibration != null;
  String? get gpsStatus => _gpsStatus;

  FieldMapper get fieldMapper => FieldMapper(calibration: _calibration);

  /// Set calibration directly from two opposite corners tapped on the map.
  /// [cornerA] and [cornerB] are any two diagonally opposite corners.
  void setFromCorners(LatLng cornerA, LatLng cornerB) {
    // Build a non-rotated rectangle from the two GPS corners.
    // cornerA = top-left (or any corner), cornerB = diagonally opposite.
    final minLat = cornerA.latitude < cornerB.latitude ? cornerA.latitude : cornerB.latitude;
    final maxLat = cornerA.latitude > cornerB.latitude ? cornerA.latitude : cornerB.latitude;
    final minLng = cornerA.longitude < cornerB.longitude ? cornerA.longitude : cornerB.longitude;
    final maxLng = cornerA.longitude > cornerB.longitude ? cornerA.longitude : cornerB.longitude;

    final topLeft = LatLng(maxLat, minLng);
    final topRight = LatLng(maxLat, maxLng);
    final bottomRight = LatLng(minLat, maxLng);
    final bottomLeft = LatLng(minLat, minLng);
    final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);

    // Compute field dimensions from the corners
    final widthM = FieldMapper.distanceMetres(topLeft, topRight);
    final lengthM = FieldMapper.distanceMetres(topLeft, bottomLeft);

    _calibration = FieldCalibration(
      centerSpot: center,
      sidelineMid: LatLng(center.latitude, minLng), // left sideline midpoint
      fieldWidthM: widthM < lengthM ? widthM : lengthM, // shorter = width
      corners: [topLeft, topRight, bottomRight, bottomLeft],
    );
    _step = CalibrationStep.done;
    _error = null;
    debugPrint('[CAL] Corners set: TL=$topLeft BR=$bottomRight width=${widthM.toStringAsFixed(1)}m length=${lengthM.toStringAsFixed(1)}m');
    notifyListeners();
  }

  // ── Legacy two-point calibration (kept for compatibility) ──

  void startCalibration() {
    _step = CalibrationStep.waitingTracker;
    _trackerCenter = null;
    _coachPosition = null;
    _error = null;
    _gpsStatus = null;
    notifyListeners();
  }

  void setTrackerCenter(LatLng position) {
    _trackerCenter = position;
    _step = CalibrationStep.captureCoach;
    _error = null;
    notifyListeners();
  }

  Future<void> captureCoachPosition() async {
    // Legacy — kept but the corner-tap method is now preferred
    _error = 'Use corner-tap calibration on the satellite map instead.';
    notifyListeners();
  }

  void cancel() {
    _step = CalibrationStep.idle;
    _error = null;
    _gpsStatus = null;
    _capturingGps = false;
    notifyListeners();
  }

  void clearCalibration() {
    _calibration = null;
    _step = CalibrationStep.idle;
    _gpsStatus = null;
    notifyListeners();
  }
}
