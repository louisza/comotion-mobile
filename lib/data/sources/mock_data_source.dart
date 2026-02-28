// lib/data/sources/mock_data_source.dart
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../models/player.dart';
import '../models/player_state.dart';
import 'data_source.dart';

/// Simulated data source for demo and development without hardware.
///
/// Simulates 3 players moving around a hockey field with varying intensity.
/// Players follow pseudo-random walk patterns bounded to the field extents.
class MockDataSource implements DataSource {
  MockDataSource();

  static final List<Player> _mockPlayers = [
    const Player(id: 'mock-1', name: 'Alice van Zyl', number: 7, color: Color(0xFF2196F3)),
    const Player(id: 'mock-2', name: 'Bria Pietersen', number: 11, color: Color(0xFFE91E63)),
    const Player(id: 'mock-3', name: 'Cara Botha', number: 3, color: Color(0xFF4CAF50)),
  ];

  // Field bounds (approximate hockey field in GPS coordinates).
  // Default: small area around (0,0) normalised — real coords set via FieldMapper config.
  static const double _latMin = -26.0010;
  static const double _latMax = -25.9990;
  static const double _lngMin = 28.0990;
  static const double _lngMax = 28.1010;

  final _rng = Random();
  final Map<String, PlayerState> _states = {};
  final Map<String, _PlayerSimState> _simStates = {};

  final _controller = StreamController<List<PlayerState>>.broadcast();
  Timer? _timer;
  bool _running = false;
  int _tick = 0;

  @override
  String get label => 'Mock (demo)';

  @override
  bool get isRunning => _running;

  @override
  Stream<List<PlayerState>> get playerStates => _controller.stream;

  @override
  Future<void> start() async {
    if (_running) return;
    _running = true;
    _tick = 0;

    // Reset player state fresh on every start.
    _states.clear();
    _simStates.clear();

    for (final player in _mockPlayers) {
      final lat = _latMin + _rng.nextDouble() * (_latMax - _latMin);
      final lng = _lngMin + _rng.nextDouble() * (_lngMax - _lngMin);
      final sim = _PlayerSimState(_rng);
      sim.lat = lat;
      sim.lng = lng;
      _states[player.id] = PlayerState.initial(player).withNewPosition(LatLng(lat, lng));
      _simStates[player.id] = sim;
    }

    // Emit initial state immediately.
    _controller.add(_states.values.toList());

    // Update at ~2 Hz.
    _timer = Timer.periodic(const Duration(milliseconds: 500), _onTick);
  }

  @override
  Future<void> stop() async {
    _running = false;
    _timer?.cancel();
    _timer = null;
    // Emit empty list so UI shows cleared field.
    _controller.add([]);
  }

  void _onTick(Timer _) {
    _tick++;

    for (final player in _mockPlayers) {
      final sim = _simStates[player.id]!;
      final prev = _states[player.id]!;

      // Move player.
      sim.step(_rng, _latMin, _latMax, _lngMin, _lngMax);
      final newPos = LatLng(sim.lat, sim.lng);

      // Vary intensity with a sinusoidal base + noise.
      final baseIntensity =
          (128 + 100 * sin(_tick * 0.05 + sim.phaseOffset)).toInt().clamp(0, 255);
      final intensity1s = (baseIntensity + _rng.nextInt(30) - 15).clamp(0, 255);
      final intensity1min = (baseIntensity + _rng.nextInt(20) - 10).clamp(0, 255);
      final intensity10min = (intensity1min * 8 + _rng.nextInt(50)).clamp(0, 1023);

      final speed = (sim.speed + _rng.nextInt(3) - 1).clamp(0, 30);
      sim.speed = speed;

      var next = prev
          .withNewPosition(newPos)
          .withIntensitySample(intensity1s)
          .copyWith(
            intensity1s: intensity1s,
            intensity1min: intensity1min,
            intensity10min: intensity10min,
            speedKmh: speed,
            maxSpeedKmh: max(prev.maxSpeedKmh, speed),
            sessionTimeSec: prev.sessionTimeSec + 1,
            batteryPercent: max(0, prev.batteryPercent - (_tick % 120 == 0 ? 1 : 0)),
            hasGpsFix: true,
            gpsSatellites: 8 + _rng.nextInt(4),
            gpsAgeSec: 0,
            lastSeen: DateTime.now(),
          );

      // Occasional impacts.
      if (_rng.nextInt(100) < 2) {
        next = next.copyWith(impactCount: next.impactCount + 1);
      }
      // Movement count increments with speed.
      if (speed > 3) {
        next = next.copyWith(movementCount: next.movementCount + 1);
      }

      _states[player.id] = next;
    }

    _controller.add(_states.values.toList());
  }

  void dispose() {
    stop();
    _controller.close();
  }
}

/// Internal per-player simulation state.
class _PlayerSimState {
  double lat;
  double lng;
  double vLat;
  double vLng;
  int speed;
  final double phaseOffset;

  _PlayerSimState(Random rng)
      : lat = 0,
        lng = 0,
        vLat = (rng.nextDouble() - 0.5) * 0.00005,
        vLng = (rng.nextDouble() - 0.5) * 0.00005,
        speed = 5 + rng.nextInt(10),
        phaseOffset = rng.nextDouble() * 2 * pi;

  void step(Random rng, double latMin, double latMax, double lngMin, double lngMax) {
    // Random walk with wall bouncing.
    vLat += (rng.nextDouble() - 0.5) * 0.00002;
    vLng += (rng.nextDouble() - 0.5) * 0.00002;

    // Clamp velocity magnitude.
    final speed = sqrt(vLat * vLat + vLng * vLng);
    const maxV = 0.0001;
    if (speed > maxV) {
      vLat = vLat / speed * maxV;
      vLng = vLng / speed * maxV;
    }

    lat += vLat;
    lng += vLng;

    // Bounce off walls.
    if (lat < latMin) {
      lat = latMin;
      vLat = vLat.abs();
    }
    if (lat > latMax) {
      lat = latMax;
      vLat = -vLat.abs();
    }
    if (lng < lngMin) {
      lng = lngMin;
      vLng = vLng.abs();
    }
    if (lng > lngMax) {
      lng = lngMax;
      vLng = -vLng.abs();
    }
  }
}
