/// Match phase state management.
///
/// Tracks the overall match state (pre-match → Q1 → break → Q2 → etc.)
/// and ensures any device that comes online during an active quarter
/// is automatically put into logging state.
library;

import 'package:flutter/foundation.dart';

/// The phase of a hockey match.
enum MatchPhase {
  preMatch,   // Before match starts
  q1,
  break1,     // Between Q1 and Q2
  q2,
  halfTime,
  q3,
  break3,     // Between Q3 and Q4
  q4,
  fullTime,   // Match over
}

extension MatchPhaseX on MatchPhase {
  /// Whether devices should be logging during this phase.
  bool get isActive => switch (this) {
    MatchPhase.q1 || MatchPhase.q2 || MatchPhase.q3 || MatchPhase.q4 => true,
    _ => false,
  };

  /// Human-readable label.
  String get label => switch (this) {
    MatchPhase.preMatch  => 'Pre-Match',
    MatchPhase.q1        => 'Q1',
    MatchPhase.break1    => 'Break',
    MatchPhase.q2        => 'Q2',
    MatchPhase.halfTime  => 'Half Time',
    MatchPhase.q3        => 'Q3',
    MatchPhase.break3    => 'Break',
    MatchPhase.q4        => 'Q4',
    MatchPhase.fullTime  => 'Full Time',
  };

  /// The next phase in sequence, or null if at fullTime.
  MatchPhase? get next => switch (this) {
    MatchPhase.preMatch  => MatchPhase.q1,
    MatchPhase.q1        => MatchPhase.break1,
    MatchPhase.break1    => MatchPhase.q2,
    MatchPhase.q2        => MatchPhase.halfTime,
    MatchPhase.halfTime  => MatchPhase.q3,
    MatchPhase.q3        => MatchPhase.break3,
    MatchPhase.break3    => MatchPhase.q4,
    MatchPhase.q4        => MatchPhase.fullTime,
    MatchPhase.fullTime  => null,
  };

  /// The previous phase, or null if at preMatch.
  MatchPhase? get previous => switch (this) {
    MatchPhase.preMatch  => null,
    MatchPhase.q1        => MatchPhase.preMatch,
    MatchPhase.break1    => MatchPhase.q1,
    MatchPhase.q2        => MatchPhase.break1,
    MatchPhase.halfTime  => MatchPhase.q2,
    MatchPhase.q3        => MatchPhase.halfTime,
    MatchPhase.break3    => MatchPhase.q3,
    MatchPhase.q4        => MatchPhase.break3,
    MatchPhase.fullTime  => MatchPhase.q4,
  };

  /// Button label for advancing to the next phase.
  String get actionLabel => switch (this) {
    MatchPhase.preMatch  => 'Start Q1',
    MatchPhase.q1        => 'End Q1',
    MatchPhase.break1    => 'Start Q2',
    MatchPhase.q2        => 'End Q2 (Half)',
    MatchPhase.halfTime  => 'Start Q3',
    MatchPhase.q3        => 'End Q3',
    MatchPhase.break3    => 'Start Q4',
    MatchPhase.q4        => 'End Match',
    MatchPhase.fullTime  => 'Match Over',
  };

  /// Color for the phase indicator.
  bool get showsGreen => isActive;
}
