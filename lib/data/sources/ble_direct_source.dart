// lib/data/sources/ble_direct_source.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:latlong2/latlong.dart';

import '../models/ble_packet.dart';
import '../models/player.dart';
import '../models/player_state.dart';
import 'data_source.dart';

/// BLE manufacturer ID used by CoMotion firmware.
const int kComotionManufacturerId = 0xFFFF;

/// BLE local name broadcast by CoMotion firmware.
const String kComotionDeviceName = 'CoMotion';

/// Live data source using passive BLE advertisement scanning.
///
/// The firmware continuously broadcasts 20-byte manufacturer data containing
/// intensity, battery, speed and status flags. GPS position will be added
/// via active BLE connection in a future firmware update — for now [position]
/// remains null and callers should fall back to simulated positions.
class BleDirectSource implements DataSource {
  BleDirectSource();

  final Map<String, PlayerState> _states = {};
  final Map<String, Player> _players = {};
  int _playerCounter = 0;

  final _controller = StreamController<List<PlayerState>>.broadcast();
  StreamSubscription<List<ScanResult>>? _scanSub;
  bool _running = false;

  @override
  String get label => 'BLE Direct';

  @override
  bool get isRunning => _running;

  @override
  Stream<List<PlayerState>> get playerStates => _controller.stream;

  @override
  Future<void> start() async {
    if (_running) return;
    _running = true;

    // Confirm BLE adapter is available and on.
    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      // Turn on if possible (Android only); ignore errors.
      try {
        await FlutterBluePlus.turnOn();
      } catch (_) {}
    }

    await FlutterBluePlus.startScan(
      withNames: [kComotionDeviceName],
      continuousUpdates: true,
      removeIfGone: const Duration(seconds: 10),
    );

    _scanSub = FlutterBluePlus.scanResults.listen(_onScanResults);
  }

  @override
  Future<void> stop() async {
    _running = false;
    await _scanSub?.cancel();
    _scanSub = null;
    await FlutterBluePlus.stopScan();
  }

  void _onScanResults(List<ScanResult> results) {
    bool changed = false;

    for (final result in results) {
      final mfr = result.advertisementData.manufacturerData;

      // Debug: print raw advertisement data
      debugPrint('[BLE] Device: ${result.device.platformName} (${result.device.remoteId}) RSSI:${result.rssi}');
      debugPrint('[BLE] ManufacturerData keys: ${mfr.keys.toList()} values: ${mfr.values.map((v) => v.map((b) => b.toRadixString(16).padLeft(2,'0')).join(' ')).toList()}');
      debugPrint('[BLE] ServiceUUIDs: ${result.advertisementData.serviceUuids}');

      // Try exact manufacturer ID first, then fall back to any available data.
      List<int>? data = mfr[kComotionManufacturerId];
      if (data == null || data.isEmpty) {
        if (mfr.isNotEmpty) {
          data = mfr.values.first;
        }
      }
      if (data == null || data.isEmpty) {
        debugPrint('[BLE] No manufacturer data found — skipping');
        continue;
      }
      debugPrint('[BLE] Parsing ${data.length} bytes of manufacturer data');

      final packet = BlePacket.parse(Uint8List.fromList(data));
      if (packet == null) {
        debugPrint('[BLE] Packet parse failed (too short?)');
        continue;
      }
      debugPrint('[BLE] Packet OK — intensity:${packet.intensity1s} bat:${packet.batteryPercent}% gps:${packet.hasGpsFix}');

      final deviceId = result.device.remoteId.str;

      // Register player on first sight.
      if (!_players.containsKey(deviceId)) {
        _playerCounter++;
        _players[deviceId] = Player(
          id: deviceId,
          name: 'Player $_playerCounter',
          number: _playerCounter,
          color: _playerColors[(_playerCounter - 1) % _playerColors.length],
        );
        _states[deviceId] = PlayerState.initial(_players[deviceId]!);
      }

      final prev = _states[deviceId]!;
      var next = prev.copyWith(
        intensity1s:    packet.intensity1s,
        intensity1min:  packet.intensity1min,
        intensity10min: packet.intensity10min,
        speedKmh:       packet.speedKmh,
        maxSpeedKmh:    packet.maxSpeedKmh,
        impactCount:    packet.impactCount,
        movementCount:  packet.movementCount,
        sessionTimeSec: packet.sessionTimeSec,
        batteryPercent: packet.batteryPercent,
        hasGpsFix:      packet.hasGpsFix,
        isLowBattery:   packet.isLowBattery,
        gpsSatellites:  packet.gpsSatellites,
        gpsAgeSec:      packet.gpsAgeSec,
        lastSeen:       DateTime.now(),
      );

      // Apply GPS position from packet bytes 15-18 if available.
      if (packet.gpsPosition != null) {
        next = next.withNewPosition(packet.gpsPosition!);
      }

      next = next.withIntensitySample(packet.intensity1s);
      _states[deviceId] = next;
      changed = true;
    }

    if (changed) {
      _controller.add(_states.values.toList());
    }
  }

  static const List<Color> _playerColors = [
    Color(0xFF2196F3), // blue
    Color(0xFFE91E63), // pink
    Color(0xFF4CAF50), // green
    Color(0xFFFF9800), // orange
    Color(0xFF9C27B0), // purple
  ];

  void dispose() {
    stop();
    _controller.close();
  }
}
