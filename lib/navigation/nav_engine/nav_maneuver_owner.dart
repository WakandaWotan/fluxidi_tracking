// NAV-MANEUVER-OWNER-REBASE-1
//
// Single deterministic owner of the visible maneuver.
//
// `nav_banner_resolver` decides *which* step is described. This module is the
// only authority on whether that maneuver may be shown yet, which guidance
// fields travel with it, and whether a late tick is allowed to replace the
// active owner. Presentation (`maneuver_presentation`, `nav_sign_resolver`)
// renders what the owner decided and never re-derives activation.
//
// Activation depends on remaining along-route distance and maneuver class
// only. Vehicle speed is deliberately not an input anywhere in this file.

import '../driver_navigation_formatters.dart';
import '../driver_navigation_models.dart';

/// Roundabouts, ramps, forks and merges: the driver has to read the junction
/// and pick a lane before its geometry starts.
const double kNavManeuverComplexActivationMeters = 300.0;

/// Ordinary turns and T-junctions.
const double kNavManeuverOrdinaryActivationMeters = 200.0;

/// Remaining distance at which a roundabout counts as being driven.
const double kNavRoundaboutCirculatingMeters = 40.0;

/// How a maneuver earns its activation window.
enum NavManeuverActivationClass {
  /// Route endpoints. Always owned — they describe the route, not a junction.
  alwaysActive,

  /// [kNavManeuverComplexActivationMeters].
  complex,

  /// [kNavManeuverOrdinaryActivationMeters].
  ordinary,

  /// Never owns a maneuver sign: plain "keep going" guidance.
  followOnly,
}

enum NavRoundaboutOwnerPhase { none, approach, circulating }

double navManeuverActivationThresholdM(NavManeuverActivationClass klass) {
  switch (klass) {
    case NavManeuverActivationClass.alwaysActive:
      return double.infinity;
    case NavManeuverActivationClass.complex:
      return kNavManeuverComplexActivationMeters;
    case NavManeuverActivationClass.ordinary:
      return kNavManeuverOrdinaryActivationMeters;
    case NavManeuverActivationClass.followOnly:
      return 0.0;
  }
}

bool _hasDirection(String modifier) {
  final m = modifier.trim().toLowerCase();
  return m.contains('left') ||
      m.contains('right') ||
      m.contains('uturn') ||
      m.contains('u-turn');
}

NavManeuverActivationClass classifyNavManeuverActivation({
  required String type,
  required String modifier,
}) {
  final t = type.trim().toLowerCase();
  final m = modifier.trim().toLowerCase();

  if (t.contains('arrive') || t.contains('depart')) {
    return NavManeuverActivationClass.alwaysActive;
  }
  if (t.contains('roundabout') ||
      t.contains('rotary') ||
      t.contains('ramp') ||
      t.contains('fork') ||
      t.contains('merge')) {
    return NavManeuverActivationClass.complex;
  }
  if (t.contains('turn') || t.contains('end of road') || _hasDirection(m)) {
    return NavManeuverActivationClass.ordinary;
  }
  return NavManeuverActivationClass.followOnly;
}

/// True when [distanceToManeuverM] is inside the window for [klass].
///
/// There is no speed parameter by design: identical distances must always
/// produce identical activation, standing still or at motorway speed.
bool navManeuverInsideActivationWindow({
  required double distanceToManeuverM,
  required NavManeuverActivationClass klass,
}) {
  final threshold = navManeuverActivationThresholdM(klass);
  if (threshold.isInfinite) return true;
  if (threshold <= 0) return false;
  if (!distanceToManeuverM.isFinite) return false;
  return distanceToManeuverM <= threshold;
}

/// Stable identity of one maneuver, free of coordinates and of anything that
/// changes on every progress tick.
///
/// [routeVersion] is part of the identity so a maneuver from a replaced route
/// can never compare equal to one on the current route.
String navManeuverIdentity({
  required int routeVersion,
  required int describedStepIndex,
  required String type,
  required String modifier,
  String? exitNumber,
}) {
  final exit = (exitNumber ?? '').trim();
  return 'rv$routeVersion'
      '#s$describedStepIndex'
      '#${type.trim().toLowerCase()}'
      '#${modifier.trim().toLowerCase()}'
      '#e${exit.isEmpty ? '-' : exit}';
}

/// Mapbox banner `degrees` for [step], or null when the route never carried it.
///
/// Never synthesised: an invented angle would be indistinguishable from a real
/// one downstream.
double? navManeuverBannerDegrees(DriverNavStep step) {
  for (final stage in step.bannerInstructions) {
    final degrees = stage.primary?.degrees;
    if (degrees != null && degrees.isFinite) return degrees;
  }
  return null;
}

/// Signed turn angle from the step bearings, normalised to (-180, 180].
/// Negative turns left, positive turns right. Null when either bearing is
/// missing. This is a different quantity than [navManeuverBannerDegrees] and
/// is kept separate on purpose.
double? navManeuverBearingDeltaDegrees(DriverNavStep step) {
  final before = step.bearingBefore;
  final after = step.bearingAfter;
  if (before == null || after == null) return null;
  if (!before.isFinite || !after.isFinite) return null;
  var delta = after - before;
  while (delta > 180) {
    delta -= 360;
  }
  while (delta <= -180) {
    delta += 360;
  }
  return delta;
}

/// The visible maneuver for one render tick.
class NavVisibleManeuverOwner {
  final int routeVersion;
  final int legIndex;

  /// Step the driver is traversing.
  final int traversalStepIndex;

  /// Step whose maneuver is being described.
  final int describedStepIndex;

  final String maneuverIdentity;
  final String maneuverType;
  final String maneuverModifier;
  final String? exitNumber;

  /// Monotonic progress counter; guards out-of-order writes.
  final int progressEpoch;

  final NavManeuverActivationClass activationClass;
  final double activationThresholdM;
  final double distanceToManeuverM;
  final NavRoundaboutOwnerPhase roundaboutPhase;

  final String? drivingSide;
  final double? bearingBefore;
  final double? bearingAfter;
  final double? bannerDegrees;

  /// True when this tick was refused and the previous owner stayed in place.
  final bool staleWriteRejected;
  final String ownerChangeReason;

  const NavVisibleManeuverOwner({
    required this.routeVersion,
    required this.legIndex,
    required this.traversalStepIndex,
    required this.describedStepIndex,
    required this.maneuverIdentity,
    required this.maneuverType,
    required this.maneuverModifier,
    required this.progressEpoch,
    required this.activationClass,
    required this.activationThresholdM,
    required this.distanceToManeuverM,
    required this.roundaboutPhase,
    required this.staleWriteRejected,
    required this.ownerChangeReason,
    this.exitNumber,
    this.drivingSide,
    this.bearingBefore,
    this.bearingAfter,
    this.bannerDegrees,
  });

  /// Whether a maneuver sign and maneuver wording may be shown.
  bool get isActive => navManeuverInsideActivationWindow(
    distanceToManeuverM: distanceToManeuverM,
    klass: activationClass,
  );

  /// Inverse of [isActive]: the banner must fall back to follow-route.
  bool get showFollowRoute => !isActive;

  NavVisibleManeuverOwner _rejected() => NavVisibleManeuverOwner(
    routeVersion: routeVersion,
    legIndex: legIndex,
    traversalStepIndex: traversalStepIndex,
    describedStepIndex: describedStepIndex,
    maneuverIdentity: maneuverIdentity,
    maneuverType: maneuverType,
    maneuverModifier: maneuverModifier,
    exitNumber: exitNumber,
    progressEpoch: progressEpoch,
    activationClass: activationClass,
    activationThresholdM: activationThresholdM,
    distanceToManeuverM: distanceToManeuverM,
    roundaboutPhase: roundaboutPhase,
    drivingSide: drivingSide,
    bearingBefore: bearingBefore,
    bearingAfter: bearingAfter,
    bannerDegrees: bannerDegrees,
    staleWriteRejected: true,
    ownerChangeReason: 'stale_write_rejected',
  );
}

/// Whether an incoming tick must be refused in favour of [active].
///
/// A newer route always wins. An older route, an older progress epoch, or a
/// maneuver that walks backwards inside the same tick is a late write from
/// state that no longer exists.
bool navManeuverOwnerTickIsStale({
  required int candidateRouteVersion,
  required int candidateProgressEpoch,
  required int candidateDescribedStepIndex,
  required NavVisibleManeuverOwner? active,
}) {
  if (active == null) return false;
  if (candidateRouteVersion != active.routeVersion) {
    return candidateRouteVersion < active.routeVersion;
  }
  if (candidateProgressEpoch != active.progressEpoch) {
    return candidateProgressEpoch < active.progressEpoch;
  }
  return candidateDescribedStepIndex < active.describedStepIndex;
}

/// Resolve the one owner for this tick.
///
/// Returns [previous] marked as rejected when the tick is stale, so a delayed
/// write can never resurrect a maneuver from a replaced route.
NavVisibleManeuverOwner resolveNavVisibleManeuverOwner({
  required DriverNavStep describedStep,
  required int describedStepIndex,
  required int traversalStepIndex,
  required double distanceToManeuverM,
  required int routeVersion,
  required int progressEpoch,
  int legIndex = 0,
  NavVisibleManeuverOwner? previous,
}) {
  if (navManeuverOwnerTickIsStale(
    candidateRouteVersion: routeVersion,
    candidateProgressEpoch: progressEpoch,
    candidateDescribedStepIndex: describedStepIndex,
    active: previous,
  )) {
    return previous!._rejected();
  }

  final klass = classifyNavManeuverActivation(
    type: describedStep.type,
    modifier: describedStep.modifier,
  );
  final identity = navManeuverIdentity(
    routeVersion: routeVersion,
    describedStepIndex: describedStepIndex,
    type: describedStep.type,
    modifier: describedStep.modifier,
    exitNumber: describedStep.exitNumber,
  );
  final active = navManeuverInsideActivationWindow(
    distanceToManeuverM: distanceToManeuverM,
    klass: klass,
  );

  var roundaboutPhase = NavRoundaboutOwnerPhase.none;
  if (active && driverNavTypeIsRoundabout(describedStep.type)) {
    roundaboutPhase = distanceToManeuverM <= kNavRoundaboutCirculatingMeters
        ? NavRoundaboutOwnerPhase.circulating
        : NavRoundaboutOwnerPhase.approach;
  }

  final String reason;
  if (previous == null) {
    reason = 'initial';
  } else if (previous.routeVersion != routeVersion) {
    reason = 'route_version_change';
  } else if (previous.describedStepIndex != describedStepIndex) {
    reason = 'step_change';
  } else if (previous.maneuverIdentity != identity) {
    reason = 'maneuver_identity_change';
  } else {
    reason = 'progress_tick';
  }

  return NavVisibleManeuverOwner(
    routeVersion: routeVersion,
    legIndex: legIndex,
    traversalStepIndex: traversalStepIndex,
    describedStepIndex: describedStepIndex,
    maneuverIdentity: identity,
    maneuverType: describedStep.type,
    maneuverModifier: describedStep.modifier,
    exitNumber: (describedStep.exitNumber ?? '').trim().isEmpty
        ? null
        : describedStep.exitNumber!.trim(),
    progressEpoch: progressEpoch,
    activationClass: klass,
    activationThresholdM: navManeuverActivationThresholdM(klass),
    distanceToManeuverM: distanceToManeuverM,
    roundaboutPhase: roundaboutPhase,
    drivingSide: describedStep.drivingSide,
    bearingBefore: describedStep.bearingBefore,
    bearingAfter: describedStep.bearingAfter,
    bannerDegrees: navManeuverBannerDegrees(describedStep),
    staleWriteRejected: false,
    ownerChangeReason: reason,
  );
}

/// PII-free owner diagnostics.
String formatNavManeuverOwnerDiag(NavVisibleManeuverOwner owner) {
  return '[NAV_MANEUVER_OWNER] '
      'routeVersion=${owner.routeVersion} '
      'progressEpoch=${owner.progressEpoch} '
      'traversalStep=${owner.traversalStepIndex} '
      'describedStep=${owner.describedStepIndex} '
      'identity=${owner.maneuverIdentity} '
      'class=${owner.activationClass.name} '
      'thresholdM=${owner.activationThresholdM.isFinite ? owner.activationThresholdM.toStringAsFixed(0) : 'always'} '
      'distanceM=${owner.distanceToManeuverM.toStringAsFixed(1)} '
      'active=${owner.isActive} '
      'drivingSide=${owner.drivingSide ?? '-'} '
      'exit=${owner.exitNumber ?? '-'} '
      'bannerDegrees=${owner.bannerDegrees?.toStringAsFixed(1) ?? '-'} '
      'roundaboutPhase=${owner.roundaboutPhase.name} '
      'reason=${owner.ownerChangeReason} '
      'staleWriteRejected=${owner.staleWriteRejected}';
}
