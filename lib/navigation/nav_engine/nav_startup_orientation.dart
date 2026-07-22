// NAV-PARKING-ARRIVAL-DEPARTURE-ROUTE-CLARITY-BANNER-TELLERS-2 / Commit 1
//
// Pure, unit-testable startup heading-source selection for a NEW navigation
// session. Field ride B: at departure the camera/vehicle orientation was not
// aligned with the actual departure direction, partly because a stale
// previous-session bearing could seed the new ride and because a stationary GPS
// "course" was treated as authoritative.
//
// Rules (per task):
//  - old-session bearing may never seed the new ride;
//  - while stationary, do not pretend GPS course is authoritative;
//  - once moving with reliable course, transition smoothly to
//    course-over-ground;
//  - use route bearing only as bounded support, not as proof against real
//    movement.

/// Diagnostic events for `[NAV_ORIENTATION]`. PII-free.
enum NavOrientationEvent {
  sourceSelected,
  sourceRejected,
  transitionStarted,
  transitionCompleted,
}

extension NavOrientationEventLabel on NavOrientationEvent {
  String get label {
    switch (this) {
      case NavOrientationEvent.sourceSelected:
        return 'source_selected';
      case NavOrientationEvent.sourceRejected:
        return 'source_rejected';
      case NavOrientationEvent.transitionStarted:
        return 'transition_started';
      case NavOrientationEvent.transitionCompleted:
        return 'transition_completed';
    }
  }
}

enum NavOrientationSource {
  /// No trustworthy startup heading yet — hold the current camera, do not spin.
  none,
  /// Course-over-ground from GPS while genuinely moving.
  gpsCourse,
  /// Movement bearing derived from consecutive positions while moving.
  movementBearing,
  /// Route bearing used only as bounded support.
  routeBearing,
}

class NavStartupOrientationConfig {
  const NavStartupOrientationConfig({
    this.movingSpeedKmh = 6.0,
    this.maxCourseAccuracyDeg = 60.0,
  });

  /// Below this speed the GPS course is not treated as authoritative.
  final double movingSpeedKmh;

  /// If a course accuracy is provided and worse than this, reject the course.
  final double maxCourseAccuracyDeg;
}

class NavStartupOrientationInput {
  const NavStartupOrientationInput({
    required this.isNewSession,
    required this.speedKmh,
    required this.gpsCourseDeg,
    required this.movementBearingDeg,
    required this.routeBearingDeg,
    this.gpsCourseAccuracyDeg,
  });

  /// True on the very first orientation evaluation(s) of a new session.
  final bool isNewSession;
  final double speedKmh;

  /// GPS course-over-ground (null/negative when unavailable).
  final double? gpsCourseDeg;

  /// Movement bearing from consecutive fixes (null when not moving enough).
  final double? movementBearingDeg;

  /// Route forward bearing (bounded support only; null when unknown).
  final double? routeBearingDeg;

  /// Optional GPS course accuracy in degrees.
  final double? gpsCourseAccuracyDeg;
}

class NavStartupOrientationResult {
  const NavStartupOrientationResult({
    required this.source,
    required this.bearingDeg,
    required this.event,
  });

  final NavOrientationSource source;

  /// The chosen bearing, or null when no trustworthy source exists yet.
  final double? bearingDeg;

  final NavOrientationEvent event;
}

/// Pure selector: given the available heading evidence, pick the startup source.
/// Never returns a previous-session bearing (the caller must not pass one in as
/// gpsCourse/movement; this selector additionally refuses stationary course).
class NavStartupOrientationSelector {
  final NavStartupOrientationConfig config;

  NavStartupOrientationSelector({
    this.config = const NavStartupOrientationConfig(),
  });

  bool _courseUsable(NavStartupOrientationInput i) {
    final c = i.gpsCourseDeg;
    if (c == null || !c.isFinite || c < 0) return false;
    final acc = i.gpsCourseAccuracyDeg;
    if (acc != null && acc.isFinite && acc > config.maxCourseAccuracyDeg) {
      return false;
    }
    return true;
  }

  NavStartupOrientationResult select(NavStartupOrientationInput i) {
    final moving = i.speedKmh >= config.movingSpeedKmh;

    // Moving with a usable course-over-ground: authoritative.
    if (moving && _courseUsable(i)) {
      return NavStartupOrientationResult(
        source: NavOrientationSource.gpsCourse,
        bearingDeg: i.gpsCourseDeg,
        event: NavOrientationEvent.sourceSelected,
      );
    }

    // Moving with a movement bearing (course unavailable): authoritative.
    final mv = i.movementBearingDeg;
    if (moving && mv != null && mv.isFinite && mv >= 0) {
      return NavStartupOrientationResult(
        source: NavOrientationSource.movementBearing,
        bearingDeg: mv,
        event: NavOrientationEvent.sourceSelected,
      );
    }

    // Stationary: do NOT pretend GPS course is authoritative. Route bearing may
    // provide bounded support so the camera faces the intended departure, but
    // it is not treated as proof against real movement.
    final rb = i.routeBearingDeg;
    if (!moving && rb != null && rb.isFinite && rb >= 0) {
      return NavStartupOrientationResult(
        source: NavOrientationSource.routeBearing,
        bearingDeg: rb,
        event: NavOrientationEvent.sourceSelected,
      );
    }

    // No trustworthy source: hold current camera, do not spin to a stale value.
    return const NavStartupOrientationResult(
      source: NavOrientationSource.none,
      bearingDeg: null,
      event: NavOrientationEvent.sourceRejected,
    );
  }
}

/// PII-free bounded diagnostic line for `[NAV_ORIENTATION]`.
String formatNavOrientationDiagnostic({
  required NavOrientationEvent event,
  required NavOrientationSource source,
}) {
  return '[NAV_ORIENTATION] event=${event.label} source=${source.name}';
}
