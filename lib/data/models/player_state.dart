// lib/data/models/player_state.dart
import 'package:latlong2/latlong.dart';
import 'player.dart';

/// Maximum trail positions stored per player.
const int kTrailMaxLength = 20;

/// Maximum sparkline history samples (approx 5 min at 1 Hz).
const int kSparklineMaxLength = 300;

/// Live telemetry state for a single player.
class PlayerState {
  final Player player;

  // --- Intensity ---
  final int intensity1s; // 0-255
  final int intensity1min; // 0-255 (≈30s avg from firmware perspective)
  final int intensity10min; // uint16

  // --- Movement / activity ---
  final double speedKmh;
  final double maxSpeedKmh;
  final int impactCount;
  final int movementCount;
  final int sessionTimeSec;

  // --- Device health ---
  final int batteryPercent;
  final bool hasGpsFix;
  final bool isLowBattery;
  final int gpsSatellites;
  final int gpsAgeSec;

  // --- Position ---
  final LatLng? position; // null until GPS fix

  // --- History ---
  /// Circular trail of last [kTrailMaxLength] GPS positions.
  final List<LatLng> trail;

  /// Intensity (1s) samples for sparkline, oldest first.
  final List<int> intensityHistory;

  final DateTime lastSeen;

  const PlayerState({
    required this.player,
    required this.intensity1s,
    required this.intensity1min,
    required this.intensity10min,
    required this.speedKmh,
    required this.maxSpeedKmh,
    required this.impactCount,
    required this.movementCount,
    required this.sessionTimeSec,
    required this.batteryPercent,
    required this.hasGpsFix,
    required this.isLowBattery,
    required this.gpsSatellites,
    required this.gpsAgeSec,
    required this.position,
    required this.trail,
    required this.intensityHistory,
    required this.lastSeen,
  });

  /// Convenience: intensity 30s (maps to intensity1min for now).
  int get intensity30s => intensity1min;

  /// Convenience: intensity 5min (maps to intensity10min clamped to 255).
  int get intensity5min => (intensity10min >> 2).clamp(0, 255);

  /// Create a zeroed-out initial state for a player.
  factory PlayerState.initial(Player player) => PlayerState(
        player: player,
        intensity1s: 0,
        intensity1min: 0,
        intensity10min: 0,
        speedKmh: 0.0,
        maxSpeedKmh: 0.0,
        impactCount: 0,
        movementCount: 0,
        sessionTimeSec: 0,
        batteryPercent: 100,
        hasGpsFix: false,
        isLowBattery: false,
        gpsSatellites: 0,
        gpsAgeSec: 0,
        position: null,
        trail: const [],
        intensityHistory: const [],
        lastSeen: DateTime.now(),
      );

  PlayerState copyWith({
    int? intensity1s,
    int? intensity1min,
    int? intensity10min,
    double? speedKmh,
    double? maxSpeedKmh,
    int? impactCount,
    int? movementCount,
    int? sessionTimeSec,
    int? batteryPercent,
    bool? hasGpsFix,
    bool? isLowBattery,
    int? gpsSatellites,
    int? gpsAgeSec,
    LatLng? position,
    List<LatLng>? trail,
    List<int>? intensityHistory,
    DateTime? lastSeen,
  }) =>
      PlayerState(
        player: player,
        intensity1s: intensity1s ?? this.intensity1s,
        intensity1min: intensity1min ?? this.intensity1min,
        intensity10min: intensity10min ?? this.intensity10min,
        speedKmh: speedKmh ?? this.speedKmh,
        maxSpeedKmh: maxSpeedKmh ?? this.maxSpeedKmh,
        impactCount: impactCount ?? this.impactCount,
        movementCount: movementCount ?? this.movementCount,
        sessionTimeSec: sessionTimeSec ?? this.sessionTimeSec,
        batteryPercent: batteryPercent ?? this.batteryPercent,
        hasGpsFix: hasGpsFix ?? this.hasGpsFix,
        isLowBattery: isLowBattery ?? this.isLowBattery,
        gpsSatellites: gpsSatellites ?? this.gpsSatellites,
        gpsAgeSec: gpsAgeSec ?? this.gpsAgeSec,
        position: position ?? this.position,
        trail: trail ?? this.trail,
        intensityHistory: intensityHistory ?? this.intensityHistory,
        lastSeen: lastSeen ?? this.lastSeen,
      );

  /// Append a new GPS position to the trail (respects max length).
  PlayerState withNewPosition(LatLng newPos) {
    final newTrail = [...trail, newPos];
    if (newTrail.length > kTrailMaxLength) {
      newTrail.removeAt(0);
    }
    return copyWith(position: newPos, trail: newTrail);
  }

  /// Append intensity sample to history (respects max length).
  PlayerState withIntensitySample(int sample) {
    final newHistory = [...intensityHistory, sample];
    if (newHistory.length > kSparklineMaxLength) {
      newHistory.removeAt(0);
    }
    return copyWith(intensityHistory: newHistory);
  }
}
