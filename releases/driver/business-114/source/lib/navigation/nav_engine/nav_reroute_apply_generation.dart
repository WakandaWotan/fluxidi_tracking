// RELEASE-P0: generation-bound ownership for post-reroute apply writers.
// Pure helpers — unit-testable without the driver page.

/// Outcome of a generation-gated state write after route apply.
enum NavRerouteApplyWriterDecision {
  accepted,
  rejectedStaleGeneration,
}

/// One generation-bound apply transaction id.
class NavRerouteApplyGeneration {
  const NavRerouteApplyGeneration(this.value);
  final int value;

  bool isNewerThan(int other) => value > other;
  bool isSameAs(int other) => value == other;
}

/// Decide whether a callback may write route/camera/progress state.
///
/// After generation G is published, any writer tagged with generation &lt; G
/// must be rejected. Writers with generation == G (or newer) are accepted.
NavRerouteApplyWriterDecision navRerouteApplyAcceptWriter({
  required int writerGeneration,
  required int activeGeneration,
}) {
  if (writerGeneration < activeGeneration) {
    return NavRerouteApplyWriterDecision.rejectedStaleGeneration;
  }
  return NavRerouteApplyWriterDecision.accepted;
}

/// Mutable counter used by diagnostics / tests for stale writer attempts.
class NavRerouteApplyStaleWriterCounter {
  int routeGeometry = 0;
  int routeProgress = 0;
  int maneuverIndex = 0;
  int cameraBearing = 0;
  int nativeFollow = 0;
  int routeLineCoords = 0;

  int get total =>
      routeGeometry +
      routeProgress +
      maneuverIndex +
      cameraBearing +
      nativeFollow +
      routeLineCoords;

  void note(String writer) {
    switch (writer) {
      case 'route_geometry':
        routeGeometry += 1;
        break;
      case 'route_progress':
        routeProgress += 1;
        break;
      case 'maneuver_index':
        maneuverIndex += 1;
        break;
      case 'camera_bearing':
        cameraBearing += 1;
        break;
      case 'native_follow':
        nativeFollow += 1;
        break;
      case 'route_line_coords':
        routeLineCoords += 1;
        break;
      default:
        routeGeometry += 1;
    }
  }

  void reset() {
    routeGeometry = 0;
    routeProgress = 0;
    maneuverIndex = 0;
    cameraBearing = 0;
    nativeFollow = 0;
    routeLineCoords = 0;
  }
}

/// Bounded PII-safe diagnostic for a rejected stale writer.
String formatNavRerouteApplyStaleWriterDiag({
  required String writer,
  required int writerGeneration,
  required int activeGeneration,
  required int rejectedCount,
}) {
  return 'writer=$writer writerGen=$writerGeneration '
      'activeGen=$activeGeneration rejectedStale=$rejectedCount';
}
