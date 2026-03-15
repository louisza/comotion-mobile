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

/// Minimum interval between processing packets from the same device.
/// Packets arriving faster than this are dropped (latest-wins).
const Duration _perDeviceThrottle = Duration(milliseconds: 200);

/// If ALL devices are stale for this long, auto-restart the BLE scan.
const Duration _allStaleWatchdog = Duration(seconds: 5);

/// Live data source using passive BLE advertisement scanning.
/// On first discovery of each tracker, sends 'start' via Nordic UART.
/// On stop(), sends 'stop' to all known trackers.
class BleDirectSource implements DataSource {
  BleDirectSource();

  final Map<String, PlayerState> _states = {};
  final Map<String, Player> _players = {};
  final Map<String, BluetoothDevice> _devices = {};
  final Set<String> _startedDevices = {};
  /// Last raw manufacturer data bytes per device (for debug overlay).
  final Map<String, List<int>> lastRawPackets = {};
  /// Timestamp of last BLE update per device.
  final Map<String, DateTime> lastUpdateTime = {};
  /// Count of BLE updates per device (for rate measurement).
  final Map<String, int> updateCounts = {};
  /// Count of BLE packets dropped by throttle per device.
  final Map<String, int> droppedCounts = {};
  /// Hardware device ID from BLE name (e.g. "A3F7" from "CoMotion-A3F7")
  final Map<String, String> hardwareIds = {};
  /// Timestamp of last GPS position *change* per device.
  final Map<String, DateTime> lastGpsChangeTime = {};
  /// Previous GPS position per device (to detect changes).
  final Map<String, LatLng> _lastGpsPosition = {};
  /// Rolling GPS update interval in ms (exponential moving average).
  final Map<String, double> gpsUpdateIntervalMs = {};
  /// Last intensity sample time per device (throttle to ~1Hz for sparkline).
  final Map<String, DateTime> _lastIntensitySampleTime = {};
  /// Last parsed packet per device (for debug overlay).
  final Map<String, BlePacket> lastPackets = {};
  /// Last time we processed a packet per device (for throttle).
  final Map<String, DateTime> _lastProcessedTime = {};
  /// Last sequence number per device (for dropped packet detection).
  final Map<String, int> _lastSeq = {};
  /// Cumulative dropped BLE sequence gaps per device.
  final Map<String, int> seqDroppedCounts = {};

  int _playerCounter = 0;
  final _controller = StreamController<List<PlayerState>>.broadcast();
  StreamSubscription<List<ScanResult>>? _scanSub;
  bool _running = false;
  bool _sendingCommand = false;
  Timer? _watchdogTimer;

  /// When true, any newly discovered device is auto-sent 'start'.
  /// Set by match phase transitions.
  bool _matchActive = false;
  bool get matchActive => _matchActive;

  /// Current match phase label (e.g. "Q1", "Break") for late-joining devices.
  String? _currentPhase;

  /// Devices confirmed logging (isLogging bit in BLE packet).
  final Set<String> _confirmedLogging = {};

  /// Timer that periodically checks if all devices are logging during active match.
  Timer? _syncWatchdog;

  /// Set match active state. If activating, sends 'start' to all known
  /// devices that aren't already logging. If deactivating, sends 'stop' to all.
  Future<void> setMatchActive(bool active) async {
    _matchActive = active;
    if (active) {
      // Send start to all known devices that haven't been started
      for (final entry in _devices.entries) {
        if (!_startedDevices.contains(entry.key)) {
          _startedDevices.add(entry.key);
          debugPrint('[BLE] Match active — sending start to ${entry.value.platformName}');
          _sendCommand(entry.value, 'start');
        }
      }
      _startSyncWatchdog();
    } else {
      _syncWatchdog?.cancel();
      _syncWatchdog = null;
      _confirmedLogging.clear();
      // Send stop to all known devices
      await _stopAll();
    }
  }

  /// Send the current phase to a specific device.
  Future<void> sendPhase(String phase) async {
    _currentPhase = phase;
  }

  /// Periodic check: if match is active, find devices that aren't logging
  /// and re-send start + phase.
  void _startSyncWatchdog() {
    _syncWatchdog?.cancel();
    _syncWatchdog = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!_matchActive || _sendingCommand) return;

      for (final entry in _states.entries) {
        final deviceId = entry.key;
        final state = entry.value;

        // Device is visible but not logging — re-send start
        if (!state.isLogging && _devices.containsKey(deviceId)) {
          debugPrint('[BLE] Sync watchdog: ${_devices[deviceId]?.platformName} not logging — re-sending start');
          _startedDevices.remove(deviceId); // Allow re-start
          _startedDevices.add(deviceId);
          _sendCommand(_devices[deviceId]!, 'start');

          // Also send current phase if we have one
          if (_currentPhase != null) {
            Future.delayed(const Duration(seconds: 3), () {
              if (_matchActive && _devices.containsKey(deviceId)) {
                _sendCommand(_devices[deviceId]!, 'PHASE:$_currentPhase');
              }
            });
          }
        }
      }
    });
  }

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
    _startWatchdog();
  }

  void _startScan() {
    FlutterBluePlus.startScan(
      continuousUpdates: true,
      removeIfGone: const Duration(seconds: 10),
      androidScanMode: AndroidScanMode.lowLatency,
      androidLegacy: false,
    );
    _scanSub = FlutterBluePlus.onScanResults.listen(
      (results) {
        for (final r in results) {
          _onSingleResult(r);
        }
      },
    );
  }

  /// Start the watchdog that detects when all devices go stale.
  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!_running || _sendingCommand || _states.isEmpty) return;

      final now = DateTime.now();
      final allStale = _states.values.every((s) {
        final age = now.difference(s.lastSeen);
        return age > _allStaleWatchdog;
      });

      if (allStale) {
        debugPrint('[BLE] ⚠️ WATCHDOG: All ${_states.length} devices stale — restarting scan');
        _restartScan();
      }
    });
  }

  /// Restart the BLE scan without losing state.
  Future<void> _restartScan() async {
    await _scanSub?.cancel();
    _scanSub = null;
    try { await FlutterBluePlus.stopScan(); } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 500));
    if (_running && !_sendingCommand) {
      _startScan();
      debugPrint('[BLE] Scan restarted by watchdog');
    }
  }

  /// Pause scanning (for BLE connect operations like log transfer).
  Future<void> pauseScanning() async {
    await _scanSub?.cancel();
    _scanSub = null;
    await FlutterBluePlus.stopScan();
    debugPrint('[BLE] Scanning paused');
  }

  /// Resume scanning after a pause.
  void resumeScanning() {
    if (_running) {
      _startScan();
      debugPrint('[BLE] Scanning resumed');
    }
  }

  @override
  Future<void> stop() async {
    if (!_running) return;
    _running = false;

    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _syncWatchdog?.cancel();
    _syncWatchdog = null;

    await _scanSub?.cancel();
    _scanSub = null;
    await FlutterBluePlus.stopScan();

    for (final device in _devices.values) {
      await _sendCommandDirect(device, 'stop');
    }

    _controller.add([]);
  }

  /// Send 'stop' to all known trackers without stopping the scan.
  Future<void> _stopAll() async {
    _startedDevices.clear();
    for (final device in _devices.values) {
      debugPrint('[BLE] Sending stop to ${device.platformName}');
      await _sendCommand(device, 'stop');
    }
  }

  /// Send command during shutdown — no scan management, no guard.
  Future<void> _sendCommandDirect(BluetoothDevice device, String command) async {
    try {
      debugPrint('[BLE] Connecting to ${device.platformName} to send "$command"');
      await device.connect(timeout: const Duration(seconds: 5), autoConnect: false, license: License.free);
      final services = await device.discoverServices();
      for (final svc in services) {
        if (svc.uuid.toString().toLowerCase() == _nordicUartServiceUuid) {
          for (final char in svc.characteristics) {
            if (char.uuid.toString().toLowerCase() == _nordicUartRxCharUuid) {
              await char.write(Uint8List.fromList('$command\n'.codeUnits), withoutResponse: false);
              debugPrint('[BLE] ✅ Sent "$command" to ${device.platformName}');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[BLE] ❌ sendCommand "$command" to ${device.platformName}: $e');
    } finally {
      try { await device.disconnect(); } catch (_) {}
    }
  }

  Future<void> _sendCommand(BluetoothDevice device, String command) async {
    if (_sendingCommand) return;
    _sendingCommand = true;

    try { await FlutterBluePlus.stopScan(); } catch (_) {}
    await _scanSub?.cancel();
    _scanSub = null;

    try {
      debugPrint('[BLE] Connecting to ${device.platformName} to send "$command"');
      await device.connect(
        timeout: const Duration(seconds: 8),
        autoConnect: false,
        license: License.free,
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
      if (!sent) debugPrint('[BLE] ⚠️ UART RX char not found');
    } catch (e) {
      debugPrint('[BLE] ❌ sendCommand "$command" error: $e');
    } finally {
      try { await device.disconnect(); } catch (_) {}
      _sendingCommand = false;

      if (_running) {
        await Future.delayed(const Duration(milliseconds: 500));
        _startScan();
      }
    }
  }

  void _onSingleResult(ScanResult result) {
    if (_sendingCommand) return;

    // Strict filter: must be a CoMotion device
    final name = result.advertisementData.advName;
    final mfr = result.advertisementData.manufacturerData;
    final hasComotionName = name.startsWith(kComotionDeviceName);
    final comotionData = mfr[kComotionManufacturerId];
    final hasComotionMfr = comotionData != null && comotionData.length >= 20;
    if (!hasComotionName && !hasComotionMfr) return;

    // Extract hardware device ID from BLE name
    String? hardwareId;
    if (name.startsWith('CoMotion-') && name.length > 9) {
      hardwareId = name.substring(9);
    }

    final deviceId = result.device.remoteId.str;
    final deviceName = result.device.platformName.isNotEmpty
        ? result.device.platformName
        : name.isNotEmpty ? name : kComotionDeviceName;
    _devices[deviceId] = result.device;
    if (hardwareId != null) {
      hardwareIds[deviceId] = hardwareId;
    }

    // Auto-start new devices if match is active
    if (!_startedDevices.contains(deviceId) && _matchActive) {
      _startedDevices.add(deviceId);
      debugPrint('[BLE] New tracker during active match: ${result.device.platformName} — sending start');
      _sendCommand(result.device, 'start');
      // Send current phase after a short delay (let start complete first)
      if (_currentPhase != null) {
        final phase = _currentPhase;
        Future.delayed(const Duration(seconds: 3), () {
          if (_matchActive && _devices.containsKey(deviceId)) {
            _sendCommand(result.device, 'PHASE:$phase');
          }
        });
      }
    }

    // ─── Per-device throttle: drop packets arriving faster than 200ms ───
    final now = DateTime.now();
    final lastProcessed = _lastProcessedTime[deviceId];
    if (lastProcessed != null && now.difference(lastProcessed) < _perDeviceThrottle) {
      droppedCounts[deviceId] = (droppedCounts[deviceId] ?? 0) + 1;
      return; // Drop — we'll catch the next one
    }
    _lastProcessedTime[deviceId] = now;

    final mfrData = result.advertisementData.manufacturerData;
    List<int>? data = mfrData[kComotionManufacturerId];
    if (data == null || data.isEmpty) {
      if (mfrData.isNotEmpty) data = mfrData.values.first;
    }
    if (data == null || data.isEmpty) return;

    // Store raw bytes and timing for debug overlay
    lastRawPackets[deviceId] = List<int>.from(data);
    lastUpdateTime[deviceId] = now;
    updateCounts[deviceId] = (updateCounts[deviceId] ?? 0) + 1;

    // Debug: log raw bytes for v2 packet troubleshooting
    if (data.length >= 23) {
      debugPrint('[BLE RAW] len=${data.length} bytes=[${data.take(28).map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(', ')}]');
      final bd = ByteData.sublistView(Uint8List.fromList(data));
      final latRaw = bd.getInt32(15, Endian.little);
      final lngRaw = bd.getInt32(19, Endian.little);
      debugPrint('[BLE GPS] lat_raw=$latRaw (${latRaw / 10000000.0}°) lng_raw=$lngRaw (${lngRaw / 10000000.0}°) speed_byte=${data[6]} (${data[6] / 2.0} km/h)');
    }

    final packet = BlePacket.parse(Uint8List.fromList(data));
    if (packet == null) return;

    // ─── Sequence number tracking (dropped packet detection) ───
    if (packet.seq != null) {
      final prevSeq = _lastSeq[deviceId];
      if (prevSeq != null) {
        final expected = (prevSeq + 1) & 0xFF;
        if (packet.seq != expected) {
          final gap = ((packet.seq! - prevSeq) & 0xFF) - 1;
          if (gap > 0 && gap < 128) { // Ignore large backward jumps (likely reboot)
            seqDroppedCounts[deviceId] = (seqDroppedCounts[deviceId] ?? 0) + gap;
            debugPrint('[BLE] ⚠️ Seq gap on $deviceId: expected $expected got ${packet.seq} (dropped ~$gap)');
          }
        }
      }
      _lastSeq[deviceId] = packet.seq!;
    }

    // Store parsed packet for debug
    lastPackets[deviceId] = packet;

    // Track GPS update frequency
    if (packet.gpsPosition != null) {
      final prev = _lastGpsPosition[deviceId];
      if (prev == null ||
          prev.latitude != packet.gpsPosition!.latitude ||
          prev.longitude != packet.gpsPosition!.longitude) {
        final lastChange = lastGpsChangeTime[deviceId];
        if (lastChange != null) {
          final intervalMs = now.difference(lastChange).inMilliseconds.toDouble();
          final prev = gpsUpdateIntervalMs[deviceId];
          gpsUpdateIntervalMs[deviceId] = prev != null
              ? prev * 0.7 + intervalMs * 0.3
              : intervalMs;
        }
        lastGpsChangeTime[deviceId] = now;
        _lastGpsPosition[deviceId] = packet.gpsPosition!;
      }
    }

    debugPrint('[BLE] ${result.device.platformName} RSSI:${result.rssi} v${packet.packetVersion} int:${packet.intensity1s} bat:${packet.batteryPercent}% spd:${packet.speedKmh} gps:${packet.gpsPosition?.latitude.toStringAsFixed(7)},${packet.gpsPosition?.longitude.toStringAsFixed(7)} ses:${packet.sessionTimeSec}s seq:${packet.seq}');

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

    var next = _states[deviceId]!.copyWith(
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
      isLogging:      packet.isLogging,
      gpsSatellites:  packet.gpsSatellites,
      gpsAgeSec:      packet.gpsAgeSec,
      gpsBearingDeg:  packet.gpsBearingDeg,
      gpsHdop:        packet.gpsHdop,
      gpsFixQuality:  packet.gpsFixQuality,
      lastSeen:       now,
    );

    if (packet.gpsPosition != null) {
      next = next.withNewPosition(packet.gpsPosition!);
    }

    // Throttle sparkline samples to ~1Hz
    final lastSample = _lastIntensitySampleTime[deviceId];
    if (lastSample == null || now.difference(lastSample).inMilliseconds >= 1000) {
      next = next.withIntensitySample(packet.intensity1s);
      _lastIntensitySampleTime[deviceId] = now;
    }
    _states[deviceId] = next;
    _controller.add(_states.values.toList());
  }

  /// Get the BluetoothDevice reference for a device ID (for NUS connections).
  BluetoothDevice? getDevice(String deviceId) => _devices[deviceId];
  Iterable<BluetoothDevice> get allDevices => _devices.values;

  /// Public access to known devices map (device ID → BluetoothDevice).
  Map<String, BluetoothDevice> get knownDevices => Map.unmodifiable(_devices);

  /// Send a command to a specific device.
  Future<void> sendCommand(BluetoothDevice device, String command) =>
      _sendCommand(device, command);

  /// Update the local player name for a device (after NAME: command sent).
  void updatePlayerName(String deviceId, String name) {
    final player = _players[deviceId];
    if (player != null) {
      _players[deviceId] = Player(
        id: player.id,
        name: name,
        number: player.number,
        color: player.color,
      );
      // Update state with new player ref
      final state = _states[deviceId];
      if (state != null) {
        _states[deviceId] = PlayerState.initial(_players[deviceId]!).copyWith(
          intensity1s: state.intensity1s,
          intensity1min: state.intensity1min,
          intensity10min: state.intensity10min,
          speedKmh: state.speedKmh,
          maxSpeedKmh: state.maxSpeedKmh,
          impactCount: state.impactCount,
          movementCount: state.movementCount,
          sessionTimeSec: state.sessionTimeSec,
          batteryPercent: state.batteryPercent,
          hasGpsFix: state.hasGpsFix,
          isLowBattery: state.isLowBattery,
          isLogging: state.isLogging,
          gpsSatellites: state.gpsSatellites,
          gpsAgeSec: state.gpsAgeSec,
          lastSeen: state.lastSeen,
          position: state.position,
        );
        _controller.add(_states.values.toList());
      }
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
