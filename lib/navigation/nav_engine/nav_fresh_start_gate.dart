/// NAV-LATENCY-1 (Part B): fresh-location start gate.
///
/// Pure, side-effect-free policy that decides whether a candidate position is
/// fresh enough to launch active follow-camera motion. A multi-minute-old
/// last-known fix must never drive a follow animation; it may at most be used
/// for a bounded static orientation/placeholder, and anything older than the
/// placeholder window is unusable (wait for a live fix).
library;

enum NavFreshStartAction {
  /// Fresh live fix — safe to animate the follow camera.
  animateFollow,

  /// Stale but bounded — only static orientation/placeholder is allowed; the
  /// follow camera waits for a fresh live fix before animating.
  staticPlaceholder,

  /// No usable fix — wait for a fresh live fix, do not move the camera.
  waitForFix,
}

class NavFreshStartGate {
  /// A fix at or under this age may launch active follow-camera motion. Matches
  /// the existing passive follow-camera staleness gate (12 s).
  static const int freshFollowMaxAgeMs = 12000;

  /// A stale last-known fix may be used for bounded static orientation up to
  /// this age. Beyond it (e.g. the field-log targetAgeMs=284916) it is unusable.
  static const int stalePlaceholderMaxAgeMs = 120000;

  /// Resolve the start action for a candidate fix of the given [ageMs].
  static NavFreshStartAction resolve({required int? ageMs}) {
    if (ageMs == null || ageMs < 0) return NavFreshStartAction.waitForFix;
    if (ageMs <= freshFollowMaxAgeMs) return NavFreshStartAction.animateFollow;
    if (ageMs <= stalePlaceholderMaxAgeMs) {
      return NavFreshStartAction.staticPlaceholder;
    }
    return NavFreshStartAction.waitForFix;
  }

  /// Whether active follow-camera motion may be launched from [ageMs].
  static bool mayAnimateFollow({required int? ageMs}) =>
      resolve(ageMs: ageMs) == NavFreshStartAction.animateFollow;
}
