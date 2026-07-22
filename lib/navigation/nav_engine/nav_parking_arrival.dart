// NAV-PARKING-ARRIVAL-DEPARTURE-ROUTE-CLARITY-BANNER-TELLERS-2 / Commit 1
//
// Pure, unit-testable bounded destination-proximity arrival evaluator.
//
// Field ride A: the driver was physically standing on the Hubo parking lot with
// the destination POI beneath the vehicle, yet the app kept presenting road
// guidance toward surrounding public-road segments instead of confidently
// declaring arrival — because the snapped route endpoint lands on the public
// road, not inside the lot, and arrival was only ever driven by Mapbox's
// `maneuverType == 'arrive'` + step-pass thresholds.
//
// This evaluator adds a SECOND, bounded arrival path that never overwrites the
// original destination and never fires on a vehicle merely driving past:
// it requires proximity to the original destination AND a short low-speed dwell
// AND acceptable GPS accuracy, evaluated together — never one unconditional
// large radius.

/// Diagnostic events for `[NAV_ARRIVAL]`. PII-free.
enum NavArrivalEvent {
  candidate,
  dwellStarted,
  confirmedRouteProgress,
  confirmedDestinationProximity,
  rejected,
  closeDestinationRerouteSuppressed,
}

extension NavArrivalEventLabel on NavArrivalEvent {
  String get label {
    switch (this) {
      case NavArrivalEvent.candidate:
        return 'candidate';
      case NavArrivalEvent.dwellStarted:
        return 'dwell_started';
      case NavArrivalEvent.confirmedRouteProgress:
        return 'confirmed_route_progress';
      case NavArrivalEvent.confirmedDestinationProximity:
        return 'confirmed_destination_proximity';
      case NavArrivalEvent.rejected:
        return 'rejected';
      case NavArrivalEvent.closeDestinationRerouteSuppressed:
        return 'close_destination_reroute_suppressed';
    }
  }
}

/// Tunables for bounded proximity arrival. All bounds are conservative so a
/// vehicle driving past cannot arrive.
class NavParkingArrivalConfig {
  const NavParkingArrivalConfig({
    this.originalDestinationRadiusM = 45.0,
    this.routeEndpointRadiusM = 60.0,
    this.remainingRouteMaxM = 80.0,
    this.maxAccuracyM = 35.0,
    this.dwellSpeedKmh = 4.0,
    this.requiredDwellMs = 4000,
    this.rerouteSuppressRadiusM = 90.0,
  });

  /// Must be within this distance of the ORIGINAL selected destination.
  final double originalDestinationRadiusM;

  /// Supporting proximity to the active route endpoint.
  final double routeEndpointRadiusM;

  /// Remaining route distance must be essentially exhausted.
  final double remainingRouteMaxM;

  /// GPS accuracy gate — poor accuracy can never cause arrival.
  final double maxAccuracyM;

  /// Dwell requires speed at/below this to accrue.
  final double dwellSpeedKmh;

  /// Minimum continuous low-speed dwell before confirming proximity arrival.
  final int requiredDwellMs;

  /// Within this distance of the destination, contradictory close-destination
  /// rerouting is suppressed.
  final double rerouteSuppressRadiusM;
}

/// Inputs for one proximity-arrival evaluation tick.
class NavParkingArrivalInput {
  const NavParkingArrivalInput({
    required this.timestampMs,
    required this.distanceToOriginalDestinationM,
    required this.distanceToRouteEndpointM,
    required this.remainingRouteM,
    required this.gpsAccuracyM,
    required this.speedKmh,
    required this.progressingTowardDestination,
  });

  final int timestampMs;
  final double distanceToOriginalDestinationM;
  final double distanceToRouteEndpointM;
  final double remainingRouteM;
  final double gpsAccuracyM;
  final double speedKmh;

  /// True when the vehicle is still moving toward (not away from) the
  /// destination. When false at close range it indicates arrival, not pass-by.
  final bool progressingTowardDestination;
}

enum NavArrivalDecision {
  none,
  candidate,
  dwelling,
  confirmedProximity,
  rejected,
}

class NavParkingArrivalResult {
  const NavParkingArrivalResult({
    required this.decision,
    required this.arrived,
    required this.suppressCloseDestinationReroute,
    required this.event,
    required this.dwellMs,
  });

  final NavArrivalDecision decision;

  /// True only when bounded proximity arrival is confirmed this tick.
  final bool arrived;

  /// True when close-destination rerouting must be suppressed.
  final bool suppressCloseDestinationReroute;

  /// The single diagnostic event to emit this tick (null = nothing new).
  final NavArrivalEvent? event;

  final int dwellMs;
}

/// Bounded destination-proximity arrival state machine. Idempotent once
/// confirmed. Does not touch the original destination or route endpoint.
class NavParkingArrivalEvaluator {
  final NavParkingArrivalConfig config;

  NavParkingArrivalEvaluator({
    this.config = const NavParkingArrivalConfig(),
  });

  int? _dwellStartedAtMs;
  bool _confirmed = false;
  bool _dwellEventEmitted = false;
  bool _candidateEventEmitted = false;

  bool get confirmed => _confirmed;

  void reset() {
    _dwellStartedAtMs = null;
    _confirmed = false;
    _dwellEventEmitted = false;
    _candidateEventEmitted = false;
  }

  bool _accuracyOk(double m) => m.isFinite && m >= 0 && m <= config.maxAccuracyM;

  /// True when the vehicle is close enough to suppress contradictory
  /// close-destination reroutes, regardless of dwell.
  bool _withinRerouteSuppressBand(NavParkingArrivalInput i) {
    return _accuracyOk(i.gpsAccuracyM) &&
        (i.distanceToOriginalDestinationM <= config.rerouteSuppressRadiusM ||
            i.remainingRouteM <= config.rerouteSuppressRadiusM);
  }

  NavParkingArrivalResult evaluate(NavParkingArrivalInput i) {
    // Idempotent: once confirmed, keep confirmed and keep suppressing reroute.
    if (_confirmed) {
      return NavParkingArrivalResult(
        decision: NavArrivalDecision.confirmedProximity,
        arrived: false,
        suppressCloseDestinationReroute: true,
        event: null,
        dwellMs: _dwellDurationMs(i.timestampMs),
      );
    }

    final suppressReroute = _withinRerouteSuppressBand(i);

    // Poor accuracy can never cause arrival.
    if (!_accuracyOk(i.gpsAccuracyM)) {
      _dwellStartedAtMs = null;
      _dwellEventEmitted = false;
      return NavParkingArrivalResult(
        decision: NavArrivalDecision.none,
        arrived: false,
        suppressCloseDestinationReroute: suppressReroute,
        event: suppressReroute
            ? NavArrivalEvent.closeDestinationRerouteSuppressed
            : null,
        dwellMs: 0,
      );
    }

    // All proximity conditions must hold together — never one large radius.
    final nearOriginal =
        i.distanceToOriginalDestinationM <= config.originalDestinationRadiusM;
    final nearEndpoint =
        i.distanceToRouteEndpointM <= config.routeEndpointRadiusM;
    final routeExhausted = i.remainingRouteM <= config.remainingRouteMaxM;
    final proximityCandidate = nearOriginal && nearEndpoint && routeExhausted;

    if (!proximityCandidate) {
      // Not near the destination — pass-by or still en route. Reset dwell.
      _dwellStartedAtMs = null;
      _dwellEventEmitted = false;
      final emitReject = _candidateEventEmitted;
      _candidateEventEmitted = false;
      return NavParkingArrivalResult(
        decision: emitReject ? NavArrivalDecision.rejected : NavArrivalDecision.none,
        arrived: false,
        suppressCloseDestinationReroute: suppressReroute,
        event: emitReject
            ? NavArrivalEvent.rejected
            : (suppressReroute
                ? NavArrivalEvent.closeDestinationRerouteSuppressed
                : null),
        dwellMs: 0,
      );
    }

    // A vehicle merely driving past must not arrive: require low-speed dwell.
    final lowSpeed = i.speedKmh <= config.dwellSpeedKmh;
    final candidateEvent = !_candidateEventEmitted;
    _candidateEventEmitted = true;

    if (!lowSpeed) {
      // Near the destination but still moving at speed — candidate, not dwell.
      _dwellStartedAtMs = null;
      _dwellEventEmitted = false;
      return NavParkingArrivalResult(
        decision: NavArrivalDecision.candidate,
        arrived: false,
        suppressCloseDestinationReroute: true,
        event: candidateEvent
            ? NavArrivalEvent.candidate
            : NavArrivalEvent.closeDestinationRerouteSuppressed,
        dwellMs: 0,
      );
    }

    // Low-speed near destination: accrue dwell.
    _dwellStartedAtMs ??= i.timestampMs;
    final dwellMs = _dwellDurationMs(i.timestampMs);

    if (!_dwellEventEmitted) {
      _dwellEventEmitted = true;
      return NavParkingArrivalResult(
        decision: NavArrivalDecision.dwelling,
        arrived: false,
        suppressCloseDestinationReroute: true,
        event: NavArrivalEvent.dwellStarted,
        dwellMs: dwellMs,
      );
    }

    if (dwellMs >= config.requiredDwellMs) {
      _confirmed = true;
      return NavParkingArrivalResult(
        decision: NavArrivalDecision.confirmedProximity,
        arrived: true,
        suppressCloseDestinationReroute: true,
        event: NavArrivalEvent.confirmedDestinationProximity,
        dwellMs: dwellMs,
      );
    }

    return NavParkingArrivalResult(
      decision: NavArrivalDecision.dwelling,
      arrived: false,
      suppressCloseDestinationReroute: true,
      event: NavArrivalEvent.closeDestinationRerouteSuppressed,
      dwellMs: dwellMs,
    );
  }

  int _dwellDurationMs(int nowMs) {
    final start = _dwellStartedAtMs;
    if (start == null) return 0;
    final d = nowMs - start;
    return d < 0 ? 0 : d;
  }
}

/// PII-free bounded diagnostic line for `[NAV_ARRIVAL]`.
String formatNavArrivalDiagnostic({
  required NavArrivalEvent event,
  int? dwellMs,
}) {
  return '[NAV_ARRIVAL] event=${event.label} dwellMs=${dwellMs ?? -1}';
}
