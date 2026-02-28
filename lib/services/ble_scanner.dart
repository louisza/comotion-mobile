// lib/services/ble_scanner.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../data/models/ble_packet.dart';
import '../data/sources/ble_direct_source.dart';

/// Raw BLE scan helper — wraps flutter_blue_plus for CoMotion advertisements.
///
/// This class is used by [BleDirectSource]. It provides a filtered stream of
/// (deviceId, BlePacket) pairs from CoMotion advertisement frames.
///
/// Usage:
/// ```dart
/// final scanner = BleScanner();
/// scanner.packets.listen((event) {
///   // event.deviceId, event.packet
/// });
/// await scanner.start();
/// ```
class BleScanner {
  final _controller = StreamController<BleScanEvent>.broadcast();
  StreamSubscription<List<ScanResult>>? _sub;
  bool _running = false;

  /// Stream of decoded [BleScanEvent]s from CoMotion devices.
  Stream<BleScanEvent> get packets => _controller.stream;

  bool get isRunning => _running;

  Future<void> start() async {
    if (_running) return;
    _running = true;

    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      try {
        await FlutterBluePlus.turnOn();
      } catch (_) {}
    }

    await FlutterBluePlus.startScan(
      withNames: [kComotionDeviceName],
      continuousUpdates: true,
      removeIfGone: const Duration(seconds: 10),
    );

    _sub = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        final mfr = result.advertisementData.manufacturerData;
        final raw = mfr[kComotionManufacturerId];
        if (raw == null) continue;
        final packet = BlePacket.parse(Uint8List.fromList(raw));
        if (packet == null) continue;
        _controller.add(BleScanEvent(
          deviceId: result.device.remoteId.str,
          deviceName: result.device.platformName,
          rssi: result.rssi,
          packet: packet,
        ));
      }
    });
  }

  Future<void> stop() async {
    _running = false;
    await _sub?.cancel();
    _sub = null;
    await FlutterBluePlus.stopScan();
  }

  void dispose() {
    stop();
    _controller.close();
  }
}

/// A single decoded advertisement event from a CoMotion device.
class BleScanEvent {
  final String deviceId;
  final String deviceName;
  final int rssi;
  final BlePacket packet;

  const BleScanEvent({
    required this.deviceId,
    required this.deviceName,
    required this.rssi,
    required this.packet,
  });
}
