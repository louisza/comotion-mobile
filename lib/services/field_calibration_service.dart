// lib/services/field_calibration_service.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'field_mapper.dart';

/// Step in the two-point calibration flow.
enum CalibrationStep {
  idle,           // Not calibrating
  waitingTracker, // Waiting for coach to confirm tracker is on center spot
  captureCoach,   // Capturing coach's phone GPS (sideline midpoint)
  done,           // Calibration complete
}

/// Manages the two-point field calibration flow.
///
/// Usage:
///   1. Call [startCalibration] to begin.
///   2. Call [setTrackerCenter] with the GPS point from the tracker's BLE packet.
///   3. Call [captureCoachPosition] — captures the phone's current GPS.
///   4. [calibration] is now populated; [fieldMapper] is updated.
class FieldCalibrationService extends ChangeNotifier {
  CalibrationStep _step = CalibrationStep.idle;
  LatLng? _trackerCenter;
  LatLng? _coachPosition;
  FieldCalibration? _calibration;
  String? _error;
  bool _capturingGps = false;

  CalibrationStep get step => _step;
  LatLng? get trackerCenter => _trackerCenter;
  LatLng? get coachPosition => _coachPosition;
  FieldCalibration? get calibration => _calibration;
  String? get error => _error;
  bool get capturingGps => _capturingGps;
  bool get isCalibrated => _calibration != null;

  FieldMapper get fieldMapper => FieldMapper(calibration: _calibration);

  /// Step 1: Begin calibration. Tracker should be placed on the center spot.
  void startCalibration() {
    _step = CalibrationStep.waitingTracker;
    _trackerCenter = null;
    _coachPosition = null;
    _error = null;
    notifyListeners();
  }

  /// Step 2: Set the tracker's GPS position (decoded from BLE packet).
  /// Call this with the most recent GPS fix from the tracker on the center spot.
  void setTrackerCenter(LatLng position) {
    _trackerCenter = position;
    _step = CalibrationStep.captureCoach;
    _error = null;
    notifyListeners();
  }

  /// Step 3: Capture the coach's current phone GPS (sideline midpoint).
  /// Requests location permission if needed, then reads GPS.
  Future<void> captureCoachPosition() async {
    _capturingGps = true;
    _error = null;
    notifyListeners();

    try {
      // Check / request permissions
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever ||
          perm == LocationPermission.denied) {
        _error = 'Location permission denied. Enable in Settings.';
        _capturingGps = false;
        notifyListeners();
        return;
      }

      // Get a high-accuracy GPS fix (timeout 15s)
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 15),
        ),
      );

      _coachPosition = LatLng(pos.latitude, pos.longitude);

      if (_trackerCenter == null) {
        _error = 'Tracker center not set. Restart calibration.';
        _capturingGps = false;
        notifyListeners();
        return;
      }

      // Compute calibration
      final measuredHalfWidth = FieldMapper.distanceMetres(_trackerCenter!, _coachPosition!);
      // Use measured width if reasonable (20m–40m), else fall back to standard 27.5m
      final halfWidth = (measuredHalfWidth >= 20 && measuredHalfWidth <= 40)
          ? measuredHalfWidth * 2
          : FieldCalibration.kFieldWidthM;

      _calibration = FieldCalibration(
        centerSpot:   _trackerCenter!,
        sidelineMid:  _coachPosition!,
        fieldWidthM:  halfWidth,
      );

      _step = CalibrationStep.done;
    } on TimeoutException {
      _error = 'GPS timeout. Move to open sky and try again.';
    } catch (e) {
      _error = 'GPS error: $e';
    } finally {
      _capturingGps = false;
      notifyListeners();
    }
  }

  /// Cancel / reset calibration.
  void cancel() {
    _step = CalibrationStep.idle;
    _error = null;
    _capturingGps = false;
    notifyListeners();
  }

  /// Clear calibration (revert to default mapping).
  void clearCalibration() {
    _calibration = null;
    _step = CalibrationStep.idle;
    notifyListeners();
  }
}
