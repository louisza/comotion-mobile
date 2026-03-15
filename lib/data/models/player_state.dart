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
  final bool isLogging;
  final int gpsSatellites;
  final int gpsAgeSec;
  final double? gpsBearingDeg;  // 0.0–360.0°, null if unavailable
  final double? gpsHdop;        // 0.0–25.5, null if unavailable
  final int? gpsFixQuality;     // 0=none, 1=SPS, 2=DGNSS, 3=PPS, 4=RTK

  // --- Position ---
  final LatLng? position; // null until GPS fix

  // --- History ---
  /// Circular trail of last [kTrailMaxLength] GPS positions.
  final List<LatLng> trail;

  /// ALL GPS positions since session start (for distance calculation).
  final List<LatLng> fullTrail;

  /// Intensity (1s) samples for sparkline, oldest first.
  final List<int> intensityHistory;

  /// Cumulative player load (sum of intensity1s samples / 255).
  final double playerLoad;

  /// Number of sprint bursts (speed crossed above 15 km/h).
  final int sprintCount;

  /// Peak intensity seen this session (for fatigue calculation).
  final int peakIntensity1min;

  /// Seconds with speed < 1 km/h.
  final int standingSeconds;

  /// Whether the player was sprinting in the previous sample.
  final bool _wasSprinting;

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
    required this.isLogging,
    required this.gpsSatellites,
    required this.gpsAgeSec,
    this.gpsBearingDeg,
    this.gpsHdop,
    this.gpsFixQuality,
    required this.position,
    required this.trail,
    this.fullTrail = const [],
    required this.intensityHistory,
    this.playerLoad = 0.0,
    this.sprintCount = 0,
    this.peakIntensity1min = 0,
    this.standingSeconds = 0,
    bool wasSprinting = false,
    required this.lastSeen,
  }) : _wasSprinting = wasSprinting;

  /// Convenience: intensity 30s (maps to intensity1min for now).
  int get intensity30s => intensity1min;

  /// Convenience: intensity 5min (maps to intensity10min clamped to 255).
  int get intensity5min => (intensity10min >> 2).clamp(0, 255);

  /// Total distance in meters from GPS positions.
  double get distanceMeters {
    if (fullTrail.length < 2) return 0.0;
    const distance = Distance();
    double total = 0.0;
    for (int i = 1; i < fullTrail.length; i++) {
      total += distance.as(LengthUnit.Meter, fullTrail[i - 1], fullTrail[i]);
    }
    return total;
  }

  /// Distance per minute (m/min) — key fitness indicator.
  double get distancePerMin {
    if (sessionTimeSec < 10) return 0.0;
    return distanceMeters / (sessionTimeSec / 60.0);
  }

  /// Fatigue ratio: current 1-min intensity vs peak 1-min intensity (0.0–1.0).
  /// Below 0.5 = player is fading.
  double get fatigueRatio {
    if (peakIntensity1min == 0) return 1.0;
    return intensity1min / peakIntensity1min;
  }

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
        isLogging: false,
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
    bool? isLogging,
    int? gpsSatellites,
    int? gpsAgeSec,
    double? gpsBearingDeg,
    double? gpsHdop,
    int? gpsFixQuality,
    LatLng? position,
    List<LatLng>? trail,
    List<LatLng>? fullTrail,
    List<int>? intensityHistory,
    double? playerLoad,
    int? sprintCount,
    int? peakIntensity1min,
    int? standingSeconds,
    bool? wasSprinting,
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
        isLogging: isLogging ?? this.isLogging,
        gpsSatellites: gpsSatellites ?? this.gpsSatellites,
        gpsAgeSec: gpsAgeSec ?? this.gpsAgeSec,
        gpsBearingDeg: gpsBearingDeg ?? this.gpsBearingDeg,
        gpsHdop: gpsHdop ?? this.gpsHdop,
        gpsFixQuality: gpsFixQuality ?? this.gpsFixQuality,
        position: position ?? this.position,
        trail: trail ?? this.trail,
        fullTrail: fullTrail ?? this.fullTrail,
        intensityHistory: intensityHistory ?? this.intensityHistory,
        playerLoad: playerLoad ?? this.playerLoad,
        sprintCount: sprintCount ?? this.sprintCount,
        peakIntensity1min: peakIntensity1min ?? this.peakIntensity1min,
        standingSeconds: standingSeconds ?? this.standingSeconds,
        wasSprinting: wasSprinting ?? _wasSprinting,
        lastSeen: lastSeen ?? this.lastSeen,
      );

  /// Append a new GPS position to the trail (respects max length).
  PlayerState withNewPosition(LatLng newPos) {
    final newTrail = [...trail, newPos];
    if (newTrail.length > kTrailMaxLength) {
      newTrail.removeAt(0);
    }
    final newFullTrail = [...fullTrail, newPos];
    return copyWith(position: newPos, trail: newTrail, fullTrail: newFullTrail);
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
