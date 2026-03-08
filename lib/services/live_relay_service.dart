// lib/services/live_relay_service.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/models/player_state.dart';
import 'cloud_config.dart';

/// Relays live BLE data from the phone to the web API for live dashboard viewing.
///
/// Batches packets and posts every [batchIntervalMs] milliseconds.
/// Designed to be lightweight — won't block the UI or BLE scanning.
class LiveRelayService {
  static const int batchIntervalMs = 2000; // Post every 2 seconds
  static const int maxBatchSize = 50;

  String? _matchId;
  Timer? _batchTimer;
  final List<Map<String, dynamic>> _pendingPackets = [];
  bool _active = false;
  int _sentCount = 0;
  int _errorCount = 0;

  bool get isActive => _active;
  int get sentCount => _sentCount;
  int get errorCount => _errorCount;

  /// Start relaying live data for a match.
  void start(String matchId) {
    _matchId = matchId;
    _active = true;
    _sentCount = 0;
    _errorCount = 0;
    _pendingPackets.clear();

    _batchTimer?.cancel();
    _batchTimer = Timer.periodic(
      const Duration(milliseconds: batchIntervalMs),
      (_) => _flushBatch(),
    );

    debugPrint('[LiveRelay] Started for match $matchId');
  }

  /// Stop relaying.
  void stop() {
    _batchTimer?.cancel();
    _batchTimer = null;
    _active = false;
    _flushBatch(); // Send any remaining packets
    debugPrint('[LiveRelay] Stopped. Sent $_sentCount packets total.');
  }

  /// Queue a player state update for relay.
  void enqueue(PlayerState state) {
    if (!_active || _matchId == null) return;

    _pendingPackets.add({
      'device_id': state.player.id,
      'timestamp': DateTime.now().millisecondsSinceEpoch / 1000.0,
      'lat': state.positionHistory.isNotEmpty ? state.positionHistory.last.latitude : null,
      'lng': state.positionHistory.isNotEmpty ? state.positionHistory.last.longitude : null,
      'speed_kmh': state.speedKmh,
      'intensity_1s': state.intensity1s,
      'intensity_1min': state.intensity1min,
      'battery_pct': state.batteryPercent,
      'bearing_deg': state.gpsBearingDeg,
      'hdop': state.gpsHdop,
      'impact_count': state.impactCount,
    });

    // Cap buffer size
    if (_pendingPackets.length > maxBatchSize * 3) {
      _pendingPackets.removeRange(0, _pendingPackets.length - maxBatchSize * 3);
    }
  }

  /// Flush pending packets to the web API.
  Future<void> _flushBatch() async {
    if (_pendingPackets.isEmpty || _matchId == null) return;

    final baseUrl = CloudConfig.apiBaseUrl;
    if (baseUrl.isEmpty) return;

    // Take up to maxBatchSize packets
    final batch = _pendingPackets.take(maxBatchSize).toList();
    _pendingPackets.removeRange(0, batch.length);

    try {
      final uri = Uri.parse('$baseUrl/api/v1/matches/$_matchId/live');
      final body = jsonEncode({
        'match_id': _matchId,
        'packets': batch,
      });

      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (CloudConfig.authToken != null)
            'Authorization': 'Bearer ${CloudConfig.authToken}',
        },
        body: body,
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        _sentCount += batch.length;
      } else {
        _errorCount++;
        debugPrint('[LiveRelay] POST failed: ${response.statusCode}');
        // Re-queue on failure
        _pendingPackets.insertAll(0, batch);
      }
    } catch (e) {
      _errorCount++;
      // Re-queue on failure
      _pendingPackets.insertAll(0, batch);
      // Don't log every error to avoid spam
      if (_errorCount % 10 == 1) {
        debugPrint('[LiveRelay] Error: $e (count: $_errorCount)');
      }
    }
  }

  void dispose() {
    stop();
  }
}
