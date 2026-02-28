// lib/data/sources/wifi_relay_source.dart
import 'dart:async';

import '../models/player_state.dart';
import 'data_source.dart';

/// Stub implementation for a future WiFi relay box.
///
/// The relay box will receive CoMotion BLE advertisements locally and forward
/// them over a LAN WebSocket/UDP to the phone, removing the need for the phone
/// to be physically near the players.
///
/// Implementation steps (not yet done):
///   1. Discover relay box via mDNS (service: _comotion._tcp).
///   2. Open WebSocket to ws://<box-ip>:8765/stream.
///   3. Receive JSON frames with device ID + 20-byte manufacturer data.
///   4. Parse BlePacket and update PlayerState map (same logic as BleDirectSource).
class WifiRelaySource implements DataSource {
  WifiRelaySource();

  final _controller = StreamController<List<PlayerState>>.broadcast();
  bool _running = false;

  @override
  String get label => 'WiFi Relay (stub)';

  @override
  bool get isRunning => _running;

  @override
  Stream<List<PlayerState>> get playerStates => _controller.stream;

  @override
  Future<void> start() async {
    _running = true;
    // TODO(wifi-relay): Implement mDNS discovery and WebSocket connection.
    // For now, emit an empty list immediately so consumers don't wait forever.
    _controller.add([]);
  }

  @override
  Future<void> stop() async {
    _running = false;
    // TODO(wifi-relay): Close WebSocket.
  }

  void dispose() {
    stop();
    _controller.close();
  }
}
