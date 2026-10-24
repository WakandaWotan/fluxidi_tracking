// NAVIGATION-SINGLE-ACTIVE-TARGET-TRUTH-P0-5
//
// Structured, PII-safe diagnostics for split-brain proof between visible route,
// active target, arrival detector, Google Maps and PiP.

import 'active_navigation_target_snapshot.dart';

class NavTargetTruthLogSample {
  const NavTargetTruthLogSample({
    required this.event,
    this.bookingId,
    this.legId,
    this.lifecyclePhase,
    this.routeSessionId,
    this.targetSnapshotId,
    this.destinationKind,
    this.targetCoordinateHash,
    this.visibleRouteEndpointHash,
    this.arrivalDetectorTargetHash,
    this.googleMapsTargetHash,
    this.pipTargetHash,
    this.remainingRouteMetres,
    this.straightLineTargetDistanceM,
    this.gpsAccuracyM,
    this.arrivalFlagSource,
    this.previousNavigationPhase,
    this.previousArrivalState,
  });

  final String event;
  final String? bookingId;
  final String? legId;
  final String? lifecyclePhase;
  final String? routeSessionId;
  final String? targetSnapshotId;
  final String? destinationKind;
  final String? targetCoordinateHash;
  final String? visibleRouteEndpointHash;
  final String? arrivalDetectorTargetHash;
  final String? googleMapsTargetHash;
  final String? pipTargetHash;
  final double? remainingRouteMetres;
  final double? straightLineTargetDistanceM;
  final double? gpsAccuracyM;
  final String? arrivalFlagSource;
  final String? previousNavigationPhase;
  final String? previousArrivalState;

  /// Compact single-line payload for `[NAV_TARGET_TRUTH]`.
  String toLogLine() {
    final parts = <String>[
      'event=$event',
      'booking=${navigationBookingIdLogToken(bookingId)}',
      'leg=${_token(legId)}',
      'phase=${_token(lifecyclePhase)}',
      'route_session=${_token(routeSessionId)}',
      'snapshot=${_token(targetSnapshotId)}',
      'dest_kind=${_token(destinationKind)}',
      'target_hash=${_token(targetCoordinateHash)}',
      'route_end_hash=${_token(visibleRouteEndpointHash)}',
      'arrival_hash=${_token(arrivalDetectorTargetHash)}',
      'maps_hash=${_token(googleMapsTargetHash)}',
      'pip_hash=${_token(pipTargetHash)}',
      'remain_m=${_fmt(remainingRouteMetres)}',
      'straight_m=${_fmt(straightLineTargetDistanceM)}',
      'gps_acc=${_fmt(gpsAccuracyM)}',
      'arrival_src=${_token(arrivalFlagSource)}',
      'prev_phase=${_token(previousNavigationPhase)}',
      'prev_arrival=${_token(previousArrivalState)}',
    ];
    return parts.join(' ');
  }
}

String _token(String? v) {
  final t = (v ?? '').trim();
  return t.isEmpty ? '-' : t;
}

String _fmt(double? v) {
  if (v == null || !v.isFinite) return '-';
  return v.toStringAsFixed(1);
}

NavTargetTruthLogSample buildNavTargetTruthLogSample({
  required String event,
  ActiveNavigationTargetSnapshot? target,
  ActiveNavigationTargetSnapshot? previous,
  String? routeSessionId,
  String? visibleRouteEndpointHash,
  String? arrivalDetectorTargetHash,
  String? googleMapsTargetHash,
  String? pipTargetHash,
  double? remainingRouteMetres,
  double? straightLineTargetDistanceM,
  double? gpsAccuracyM,
  String? arrivalFlagSource,
  bool? previousArrivalConfirmed,
}) {
  return NavTargetTruthLogSample(
    event: event,
    bookingId: target?.bookingId ?? previous?.bookingId,
    legId: target?.legId ?? previous?.legId,
    lifecyclePhase: target?.navigationPhase.name,
    routeSessionId: routeSessionId ?? target?.routeId,
    targetSnapshotId: target?.snapshotId,
    destinationKind: target?.destinationKind.name,
    targetCoordinateHash: target?.targetCoordinateHash,
    visibleRouteEndpointHash: visibleRouteEndpointHash,
    arrivalDetectorTargetHash: arrivalDetectorTargetHash,
    googleMapsTargetHash: googleMapsTargetHash,
    pipTargetHash: pipTargetHash,
    remainingRouteMetres: remainingRouteMetres,
    straightLineTargetDistanceM: straightLineTargetDistanceM,
    gpsAccuracyM: gpsAccuracyM,
    arrivalFlagSource: arrivalFlagSource,
    previousNavigationPhase: previous?.navigationPhase.name,
    previousArrivalState: previousArrivalConfirmed == null
        ? null
        : (previousArrivalConfirmed ? 'confirmed' : 'clear'),
  );
}
