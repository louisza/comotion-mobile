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
const String _nordicUartServiceUuid  = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
const String _nordicUartRxCharUuid   = '6e400002-b5a3-f393-e0a9-e50e24dcca9e'; // Write here

/// Live data source using passive BLE advertisement scanning.
/// Supports sending commands (start/stop) via active Nordic UART connection.
class BleDirectSource implements DataSource {
  BleDirectSource();

  final Map<String, PlayerState> _states = {};
  final Map<String, Player> _players = {};
  // Track the most recently seen ScanResult per device for command sending
  final Map<String, ScanResult> _scanResults = {};
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

    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      try { await FlutterBluePlus.turnOn(); } catch (_) {}
    }

    await FlutterBluePlus.startScan(
      withNames: [kComotionDeviceName],
      continuousUpdates: true,
      removeIfGone: const Duration(seconds: 10),
    );

    _scanSub = FlutterBluePlus.scanResults.listen(_onScanResults);

    // Brief delay to let scan find devices, then send 'start' to all trackers
    Future.delayed(const Duration(seconds: 2), () => sendCommandToAll('start'));
  }

  @override
  Future<void> stop() async {
    // Send 'stop' to all trackers before disconnecting
    await sendCommandToAll('stop');
    _running = false;
    await _scanSub?.cancel();
    _scanSub = null;
    await FlutterBluePlus.stopScan();
    _controller.add([]);
  }

  /// Send a command string to all known CoMotion trackers via Nordic UART.
  Future<void> sendCommandToAll(String command) async {
    for (final entry in _scanResults.entries) {
      await _sendCommand(entry.value.device, command);
    }
  }

  /// Connect to [device], write [command] to Nordic UART RX, then disconnect.
  Future<void> _sendCommand(BluetoothDevice device, String command) async {
    try {
      debugPrint('[BLE] Sending "$command" to ${device.platformName}');
      await device.connect(timeout: const Duration(seconds: 5), autoConnect: false);

      final services = await device.discoverServices();
      for (final svc in services) {
        if (svc.uuid.toString().toLowerCase() == _nordicUartServiceUuid) {
          for (final char in svc.characteristics) {
            if (char.uuid.toString().toLowerCase() == _nordicUartRxCharUuid) {
              final bytes = Uint8List.fromList('$command\n'.codeUnits);
              await char.write(bytes, withoutResponse: false);
              debugPrint('[BLE] Sent "$command" OK');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[BLE] sendCommand "$command" failed: $e');
    } finally {
      try { await device.disconnect(); } catch (_) {}
    }
  }

  void _onScanResults(List<ScanResult> results) {
    bool changed = false;

    for (final result in results) {
      final mfr = result.advertisementData.manufacturerData;

      // Debug: print raw advertisement data
      debugPrint('[BLE] Device: ${result.device.platformName} (${result.device.remoteId}) RSSI:${result.rssi}');
      debugPrint('[BLE] ManufacturerData keys: ${mfr.keys.toList()} values: ${mfr.values.map((v) => v.map((b) => b.toRadixString(16).padLeft(2,'0')).join(' ')).toList()}');

      // Keep scan result for command sending
      _scanResults[result.device.remoteId.str] = result;

      // Try exact manufacturer ID first, then fall back to any available data.
      List<int>? data = mfr[kComotionManufacturerId];
      if (data == null || data.isEmpty) {
        if (mfr.isNotEmpty) data = mfr.values.first;
      }
      if (data == null || data.isEmpty) continue;

      final packet = BlePacket.parse(Uint8List.fromList(data));
      if (packet == null) continue;
      debugPrint('[BLE] Packet OK — intensity:${packet.intensity1s} bat:${packet.batteryPercent}% gps:${packet.hasGpsFix}');

      final deviceId = result.device.remoteId.str;

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
