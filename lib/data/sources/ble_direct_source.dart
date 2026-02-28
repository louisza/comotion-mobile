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

// Nordic UART Service UUIDs
const String _nordicUartServiceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
const String _nordicUartRxCharUuid  = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';

/// Live data source using passive BLE advertisement scanning.
/// On first discovery of each tracker, sends 'start' via Nordic UART.
/// On stop(), sends 'stop' to all known trackers.
class BleDirectSource implements DataSource {
  BleDirectSource();

  final Map<String, PlayerState> _states = {};
  final Map<String, Player> _players = {};
  // Track discovered devices so we can send commands
  final Map<String, BluetoothDevice> _devices = {};
  // Track which devices have already received 'start'
  final Set<String> _startedDevices = {};

  int _playerCounter = 0;
  final _controller = StreamController<List<PlayerState>>.broadcast();
  StreamSubscription<List<ScanResult>>? _scanSub;
  bool _running = false;
  bool _sendingCommand = false;

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

    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      try { await FlutterBluePlus.turnOn(); } catch (_) {}
    }

    _startScan();
  }

  void _startScan() {
    FlutterBluePlus.startScan(
      withNames: [kComotionDeviceName],
      continuousUpdates: true,
      removeIfGone: const Duration(seconds: 10),
    );
    _scanSub = FlutterBluePlus.scanResults.listen(_onScanResults);
  }

  @override
  Future<void> stop() async {
    if (!_running) return;
    _running = false;

    await _scanSub?.cancel();
    _scanSub = null;
    await FlutterBluePlus.stopScan();

    // Send 'stop' to all known trackers
    for (final device in _devices.values) {
      await _sendCommand(device, 'stop');
    }

    _controller.add([]);
  }

  /// Send a command to a single tracker.
  /// Stops scan → connects → writes → disconnects → restarts scan.
  Future<void> _sendCommand(BluetoothDevice device, String command) async {
    if (_sendingCommand) return;
    _sendingCommand = true;

    // Pause scan during connection to avoid Android BLE conflicts
    try { await FlutterBluePlus.stopScan(); } catch (_) {}
    await _scanSub?.cancel();
    _scanSub = null;

    try {
      debugPrint('[BLE] Connecting to ${device.platformName} to send "$command"');
      await device.connect(
        timeout: const Duration(seconds: 8),
        autoConnect: false,
      );

      final services = await device.discoverServices();
      bool sent = false;
      for (final svc in services) {
        if (svc.uuid.toString().toLowerCase() == _nordicUartServiceUuid) {
          for (final char in svc.characteristics) {
            if (char.uuid.toString().toLowerCase() == _nordicUartRxCharUuid) {
              final bytes = Uint8List.fromList('$command\n'.codeUnits);
              await char.write(bytes, withoutResponse: false);
              debugPrint('[BLE] ✅ Sent "$command" to ${device.platformName}');
              sent = true;
            }
          }
        }
      }
      if (!sent) debugPrint('[BLE] ⚠️ UART RX characteristic not found on ${device.platformName}');
    } catch (e) {
      debugPrint('[BLE] ❌ sendCommand "$command" error: $e');
    } finally {
      try { await device.disconnect(); } catch (_) {}
      _sendingCommand = false;

      // Resume passive scan if still running
      if (_running) {
        await Future.delayed(const Duration(milliseconds: 500));
        _startScan();
      }
    }
  }

  void _onScanResults(List<ScanResult> results) {
    bool changed = false;

    for (final result in results) {
      final deviceId = result.device.remoteId.str;

      // Track device reference
      _devices[deviceId] = result.device;

      // Send 'start' the first time we see this device
      if (!_startedDevices.contains(deviceId)) {
        _startedDevices.add(deviceId);
        debugPrint('[BLE] New tracker found: ${result.device.platformName} — sending start');
        // Run async, don't block scan results
        _sendCommand(result.device, 'start');
        return; // Skip packet parse this cycle; next scan update will have data
      }

      final mfr = result.advertisementData.manufacturerData;

      // Try exact manufacturer ID, fall back to first available entry
      List<int>? data = mfr[kComotionManufacturerId];
      if (data == null || data.isEmpty) {
        if (mfr.isNotEmpty) data = mfr.values.first;
      }
      if (data == null || data.isEmpty) {
        debugPrint('[BLE] ${result.device.platformName} — no manufacturer data yet (waiting for start)');
        continue;
      }

      debugPrint('[BLE] ${result.device.platformName} RSSI:${result.rssi} — ${data.map((b) => b.toRadixString(16).padLeft(2,'0')).join(' ')}');

      final packet = BlePacket.parse(Uint8List.fromList(data));
      if (packet == null) {
        debugPrint('[BLE] Packet parse failed (length: ${data.length})');
        continue;
      }

      debugPrint('[BLE] intensity:${packet.intensity1s} bat:${packet.batteryPercent}% gps:${packet.hasGpsFix}');

      // Register player on first sight
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
    Color(0xFF2196F3),
    Color(0xFFE91E63),
    Color(0xFF4CAF50),
    Color(0xFFFF9800),
    Color(0xFF9C27B0),
  ];

  void dispose() {
    stop();
    _controller.close();
  }
}
