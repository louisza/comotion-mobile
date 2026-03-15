/// A snapshot of cumulative metrics at a point in time.
/// Used to compute per-quarter deltas.
class MetricSnapshot {
  final double distanceMeters;
  final double playerLoad;
  final int sprintCount;
  final int impactCount;
  final int standingSeconds;
  final int sessionTimeSec;
  final double maxSpeedKmh;
  final int peakIntensity1min;

  const MetricSnapshot({
    this.distanceMeters = 0,
    this.playerLoad = 0,
    this.sprintCount = 0,
    this.impactCount = 0,
    this.standingSeconds = 0,
    this.sessionTimeSec = 0,
    this.maxSpeedKmh = 0,
    this.peakIntensity1min = 0,
  });

  /// Create a snapshot from the current PlayerState.
  factory MetricSnapshot.fromState(dynamic state) => MetricSnapshot(
    distanceMeters: state.distanceMeters as double,
    playerLoad: state.playerLoad as double,
    sprintCount: state.sprintCount as int,
    impactCount: state.impactCount as int,
    standingSeconds: state.standingSeconds as int,
    sessionTimeSec: state.sessionTimeSec as int,
    maxSpeedKmh: state.maxSpeedKmh as double,
    peakIntensity1min: state.peakIntensity1min as int,
  );
}
