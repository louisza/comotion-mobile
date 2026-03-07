// lib/services/field_calibration_service.dart
import 'dart:async';
import 'dart:math' as math;

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
  String? _gpsStatus;

  CalibrationStep get step => _step;
  LatLng? get trackerCenter => _trackerCenter;
  LatLng? get coachPosition => _coachPosition;
  FieldCalibration? get calibration => _calibration;
  String? get error => _error;
  bool get capturingGps => _capturingGps;
  bool get isCalibrated => _calibration != null;
  /// Human-readable GPS acquisition status during calibration.
  String? get gpsStatus => _gpsStatus;

  FieldMapper get fieldMapper => FieldMapper(calibration: _calibration);

  /// Step 1: Begin calibration. Tracker should be placed on the center spot.
  void startCalibration() {
    _step = CalibrationStep.waitingTracker;
    _trackerCenter = null;
    _coachPosition = null;
    _error = null;
    _gpsStatus = null;
    notifyListeners();
  }

  /// Step 2: Set the tracker's GPS position (decoded from BLE packet).
  void setTrackerCenter(LatLng position) {
    _trackerCenter = position;
    _step = CalibrationStep.captureCoach;
    _error = null;
    notifyListeners();
  }

  /// Step 3: Capture the coach's current phone GPS (sideline midpoint).
  ///
  /// Collects GPS readings for up to 10 seconds, keeping only those with
  /// accuracy ≤ 10m, then averages the best readings. This ensures we don't
  /// use a coarse cell-tower/WiFi estimate that could be 50-100m off.
  Future<void> captureCoachPosition() async {
    _capturingGps = true;
    _error = null;
    _gpsStatus = 'Acquiring GPS…';
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
        _gpsStatus = null;
        notifyListeners();
        return;
      }

      // Collect GPS readings over 10 seconds, keeping accurate ones
      final readings = <Position>[];
      final completer = Completer<void>();

      final stream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 0,
        ),
      );

      Timer? timeout;
      StreamSubscription<Position>? sub;

      sub = stream.listen((pos) {
        if (pos.accuracy <= 10.0) {
          readings.add(pos);
          _gpsStatus = '${readings.length} readings (±${pos.accuracy.toStringAsFixed(1)}m)';
          notifyListeners();
        } else {
          _gpsStatus = 'Waiting for accuracy… (±${pos.accuracy.toStringAsFixed(0)}m)';
          notifyListeners();
        }
        // Once we have 5 good readings, we're done
        if (readings.length >= 5) {
          timeout?.cancel();
          sub?.cancel();
          if (!completer.isCompleted) completer.complete();
        }
      });

      // Timeout after 15 seconds regardless
      timeout = Timer(const Duration(seconds: 15), () {
        sub?.cancel();
        if (!completer.isCompleted) completer.complete();
      });

      await completer.future;

      if (readings.isEmpty) {
        // Fall back to single best-effort reading
        _gpsStatus = 'No accurate fix, trying single read…';
        notifyListeners();
        try {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.best,
              timeLimit: Duration(seconds: 10),
            ),
          );
          readings.add(pos);
        } catch (_) {}
      }

      if (readings.isEmpty) {
        _error = 'Could not get GPS fix. Move to open sky and try again.';
        _capturingGps = false;
        _gpsStatus = null;
        notifyListeners();
        return;
      }

      // Average the readings (weighted by accuracy — lower is better)
      double totalWeight = 0;
      double weightedLat = 0;
      double weightedLng = 0;
      double bestAccuracy = double.infinity;
      for (final r in readings) {
        final w = 1.0 / math.max(r.accuracy, 1.0);
        weightedLat += r.latitude * w;
        weightedLng += r.longitude * w;
        totalWeight += w;
        if (r.accuracy < bestAccuracy) bestAccuracy = r.accuracy;
      }
      final avgLat = weightedLat / totalWeight;
      final avgLng = weightedLng / totalWeight;

      _coachPosition = LatLng(avgLat, avgLng);
      _gpsStatus = '✓ ${readings.length} readings, best ±${bestAccuracy.toStringAsFixed(1)}m';
      notifyListeners();

      if (_trackerCenter == null) {
        _error = 'Tracker center not set. Restart calibration.';
        _capturingGps = false;
        _gpsStatus = null;
        notifyListeners();
        return;
      }

      // Compute calibration
      final measuredHalfWidth = FieldMapper.distanceMetres(_trackerCenter!, _coachPosition!);
      // Use measured width × 2 if reasonable (20m–40m half-width), else standard 55m
      final fieldWidth = (measuredHalfWidth >= 20 && measuredHalfWidth <= 40)
          ? measuredHalfWidth * 2
          : FieldCalibration.kFieldWidthM;

      _calibration = FieldCalibration(
        centerSpot:   _trackerCenter!,
        sidelineMid:  _coachPosition!,
        fieldWidthM:  fieldWidth,
      );

      _step = CalibrationStep.done;
      debugPrint('[CAL] center=${_trackerCenter} coach=$_coachPosition dist=${measuredHalfWidth.toStringAsFixed(1)}m width=${fieldWidth.toStringAsFixed(1)}m readings=${readings.length} accuracy=±${bestAccuracy.toStringAsFixed(1)}m');
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
    _gpsStatus = null;
    _capturingGps = false;
    notifyListeners();
  }

  /// Clear calibration (revert to default mapping).
  void clearCalibration() {
    _calibration = null;
    _step = CalibrationStep.idle;
    _gpsStatus = null;
    notifyListeners();
  }
}
