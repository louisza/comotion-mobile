// lib/data/sources/data_source.dart
import '../models/player_state.dart';

/// Abstract interface for a live player data feed.
///
/// Concrete implementations:
///   - [BleDirectSource]   — passive BLE scan of CoMotion advertisements
///   - [WifiRelaySource]   — future WiFi relay box
///   - [MockDataSource]    — deterministic simulation for demo / testing
abstract class DataSource {
  /// Stream of the current state list for all detected players.
  /// Emits a new list every time any player state changes.
  Stream<List<PlayerState>> get playerStates;

  /// Start scanning / connecting.
  Future<void> start();

  /// Stop scanning / disconnect.
  Future<void> stop();

  /// Whether this source is currently active.
  bool get isRunning;

  /// Human-readable label for this source (shown in debug UI).
  String get label;
}
