import 'package:flutter/foundation.dart';

import '../driver_navigation_formatters.dart';
import '../driver_navigation_models.dart';

/// NAV-SIGNAGE-VISUAL-RELEASE-GATE: the single source of truth that turns a
/// live navigation event into one Fluxidi navigation sign.
///
/// Two responsibilities live here and nowhere else:
///   1. navigation event -> [NavSignManeuver] (the internal maneuver id);
///   2. language code + [NavSignManeuver] -> bundled asset path.
///
/// Widgets must never build sign file names themselves. Adding a mapping rule
/// anywhere else re-introduces the drift this resolver exists to prevent.
///
/// Every rule below is derived from fields Fluxidi actually parses out of the
/// Mapbox Directions response (see `driver_navigation_route_parser.dart`):
/// `maneuver.type`, `maneuver.modifier`, `maneuver.exit` and
/// `step.driving_side`. No event name, modifier or field is invented.

/// The 34 signs shipped in `assets/fluxidi_navigation_signs_v3`.
///
/// The enum value name is Dart-side identity; [id] is the on-disk file stem and
/// the only string that may ever be used to build a path.
enum NavSignManeuver {
  straight('straight'),
  followRoute('follow_route'),
  slightLeft('slight_left'),
  slightRight('slight_right'),
  turnLeft('turn_left'),
  turnRight('turn_right'),
  sharpLeft('sharp_left'),
  sharpRight('sharp_right'),
  uturnLeft('uturn_left'),
  uturnRight('uturn_right'),
  roundabout('roundabout'),
  roundaboutExit1('roundabout_exit_1'),
  roundaboutExit2('roundabout_exit_2'),
  roundaboutExit3('roundabout_exit_3'),
  roundaboutExit4('roundabout_exit_4'),
  forkLeft('fork_left'),
  forkStraight('fork_straight'),
  forkRight('fork_right'),
  tLeft('t_left'),
  tStraight('t_straight'),
  tRight('t_right'),
  mergeLeft('merge_left'),
  mergeStraight('merge_straight'),
  mergeRight('merge_right'),
  rampLeft('ramp_left'),
  rampRight('ramp_right'),
  exitLeft('exit_left'),
  exitRight('exit_right'),
  keepLeft('keep_left'),
  keepRight('keep_right'),
  roadEnd('road_end'),
  destinationAhead('destination_ahead'),
  destinationReached('destination_reached'),
  departure('departure');

  const NavSignManeuver(this.id);

  /// On-disk file stem, e.g. `roundabout_exit_2`.
  final String id;

  static NavSignManeuver? fromId(String id) {
    for (final value in NavSignManeuver.values) {
      if (value.id == id) return value;
    }
    return null;
  }
}

/// Language directories that actually exist under the sign asset root.
const List<String> kNavSignLanguageCodes = <String>['nl', 'en', 'fr', 'es'];

/// Unsupported or unknown locales fall back to Dutch.
const String kNavSignFallbackLanguageCode = 'nl';

/// Root of the bundled PNG signs. Registered per language in `pubspec.yaml`.
const String kNavSignAssetRoot = 'assets/fluxidi_navigation_signs_v3/png';

/// Highest roundabout exit that has a dedicated sign. Higher exits are real but
/// undrawn, so they render the generic roundabout sign rather than a wrong one.
const int kNavSignMaxRoundaboutExit = 4;

/// Distance at which an `arrive` maneuver switches from `destination_ahead` to
/// `destination_reached`.
///
/// Mirrors `kDriverManeuverPhaseNearThresholdMeters` — the band in which the
/// banner wording already says the destination is reached — so image and text
/// flip on the same frame. `nav_sign_resolver_test.dart` asserts they stay
/// equal.
const double kNavSignDestinationReachedMeters = 50.0;

/// Normalizes any locale-ish string to a language directory that exists.
///
/// Accepts `nl`, `NL`, `nl_BE`, `nl-BE`. Anything else — including the app's
/// `de`, which has no sign set — resolves to [kNavSignFallbackLanguageCode].
/// Exactly one language is ever returned, so a banner can never show two
/// language variants at once.
String resolveNavSignLanguageCode(String? raw) {
  final trimmed = (raw ?? '').trim().toLowerCase();
  if (trimmed.isEmpty) return kNavSignFallbackLanguageCode;
  final base = trimmed.split(RegExp(r'[_\-.]')).first;
  if (kNavSignLanguageCodes.contains(base)) return base;
  return kNavSignFallbackLanguageCode;
}

/// `assets/fluxidi_navigation_signs_v3/png/<language>/<maneuver_id>.png`.
String navSignAssetPath({
  required String? languageCode,
  required NavSignManeuver maneuver,
}) {
  final language = resolveNavSignLanguageCode(languageCode);
  return '$kNavSignAssetRoot/$language/${maneuver.id}.png';
}

/// Every bundled sign path. Used by the asset-integrity tests and the debug
/// catalog; never by production rendering.
List<String> navSignAllAssetPaths() {
  return <String>[
    for (final language in kNavSignLanguageCodes)
      for (final maneuver in NavSignManeuver.values)
        navSignAssetPath(languageCode: language, maneuver: maneuver),
  ];
}

/// How confidently a sign was chosen. Drives diagnostics, not rendering.
enum NavSignResolutionSource {
  /// Maneuver type and direction were both readable.
  classified,

  /// Roundabout with a trusted 1-based exit ordinal that has its own sign.
  roundaboutExit,

  /// Roundabout whose exit ordinal is missing, invalid or beyond
  /// [kNavSignMaxRoundaboutExit] — the generic roundabout sign.
  roundaboutGeneric,

  /// Maneuver category was readable but the direction was not, so the neutral
  /// member of that category is shown (e.g. `fork` with no modifier).
  categoryFallback,

  /// Nothing reliable in the event — `follow_route`.
  safeFallback,
}

/// A navigation event reduced to the fields that select a sign.
///
/// Field names mirror the parsed Mapbox data so a reader can trace each one
/// back to the response without guessing.
@immutable
class NavSignEvent {
  /// Mapbox `step.maneuver.type`, e.g. `turn`, `roundabout`, `end of road`.
  final String maneuverType;

  /// Mapbox `step.maneuver.modifier`, e.g. `slight left`, `uturn`.
  final String maneuverModifier;

  /// Mapbox `step.maneuver.exit`, kept as the raw string Fluxidi parses.
  final String? exitNumber;

  /// Mapbox `step.driving_side` (`right` | `left`). Decides which way a U-turn
  /// and an unlabelled ramp point. Defaults to right-hand traffic, which is
  /// what all four supported sign languages drive.
  final String? drivingSide;

  /// Remaining distance to the maneuver, used only to tell an approaching
  /// destination from a reached one.
  final double? distanceToManeuverMeters;

  /// Set when the navigation engine has confirmed arrival independently of
  /// distance (see `NavParkingArrivalResult.arrived`).
  final bool arrivalConfirmed;

  /// True when the instruction pipeline produced a neutral placeholder rather
  /// than a described maneuver (`NavInstructionSource.fallback`).
  final bool neutralFallback;

  const NavSignEvent({
    this.maneuverType = '',
    this.maneuverModifier = '',
    this.exitNumber,
    this.drivingSide,
    this.distanceToManeuverMeters,
    this.arrivalConfirmed = false,
    this.neutralFallback = false,
  });

  /// Reads a live [NavInstructionSnapshot] without re-deriving anything.
  ///
  /// The snapshot carries `driving_side` and the engine's arrival state from
  /// the maneuver owner, so production passes neither argument. They stay
  /// available as explicit overrides for tests and for callers that hold a
  /// [DriverNavStep] directly.
  factory NavSignEvent.fromSnapshot(
    NavInstructionSnapshot snapshot, {
    String? drivingSide,
    bool? arrivalConfirmed,
  }) {
    return NavSignEvent(
      maneuverType: snapshot.maneuverType,
      maneuverModifier: snapshot.maneuverModifier,
      exitNumber: snapshot.exitNumber,
      drivingSide: drivingSide ?? snapshot.drivingSide,
      distanceToManeuverMeters: snapshot.distanceToManeuverMeters,
      arrivalConfirmed: arrivalConfirmed ?? snapshot.arrivalConfirmed,
      // A maneuver the owner has not activated yet describes nothing the driver
      // can act on, so it resolves to the same neutral sign as a policy
      // fallback rather than to a turn the driver must not take yet.
      neutralFallback:
          snapshot.source == NavInstructionSource.fallback ||
          snapshot.followRouteForced,
    );
  }

  /// PII-free description used in diagnostics.
  String get diagnosticSignature =>
      'type=${maneuverType.isEmpty ? '-' : maneuverType} '
      'modifier=${maneuverModifier.isEmpty ? '-' : maneuverModifier} '
      'exit=${(exitNumber ?? '').isEmpty ? '-' : exitNumber}';
}

/// The chosen sign plus why it was chosen.
@immutable
class NavSignResolution {
  final NavSignManeuver maneuver;
  final NavSignResolutionSource source;

  /// Trusted 1-based roundabout exit, or null when none could be trusted.
  final int? roundaboutExitNumber;

  const NavSignResolution({
    required this.maneuver,
    required this.source,
    this.roundaboutExitNumber,
  });

  /// True when the event did not fully describe the maneuver.
  bool get isFallback =>
      source == NavSignResolutionSource.categoryFallback ||
      source == NavSignResolutionSource.safeFallback;

  String get id => maneuver.id;
}

/// Direction buckets shared by turn, fork, merge, ramp and end-of-road rules.
enum _NavSignDirection {
  sharpLeft,
  left,
  slightLeft,
  straight,
  slightRight,
  right,
  sharpRight,
  uturn,
}

/// Reads Mapbox `modifier` into a direction bucket. Returns null when the
/// modifier is absent or unrecognised so callers pick their own neutral sign
/// instead of inheriting a wrong direction.
///
/// Precedence matches `_driverManeuverVisualFromModifier`: sharp > slight >
/// uturn > left/right > straight.
_NavSignDirection? _direction(String modifier) {
  final mod = modifier.trim().toLowerCase();
  if (mod.isEmpty) return null;
  if (mod.contains('sharp left')) return _NavSignDirection.sharpLeft;
  if (mod.contains('sharp right')) return _NavSignDirection.sharpRight;
  if (mod.contains('slight left')) return _NavSignDirection.slightLeft;
  if (mod.contains('slight right')) return _NavSignDirection.slightRight;
  if (mod.contains('uturn') || mod.contains('u-turn')) {
    return _NavSignDirection.uturn;
  }
  if (mod.contains('left')) return _NavSignDirection.left;
  if (mod.contains('right')) return _NavSignDirection.right;
  if (mod.contains('straight') || mod.contains('forward')) {
    return _NavSignDirection.straight;
  }
  return null;
}

bool _leansLeft(_NavSignDirection d) =>
    d == _NavSignDirection.left ||
    d == _NavSignDirection.slightLeft ||
    d == _NavSignDirection.sharpLeft;

bool _leansRight(_NavSignDirection d) =>
    d == _NavSignDirection.right ||
    d == _NavSignDirection.slightRight ||
    d == _NavSignDirection.sharpRight;

bool _isLeftHandTraffic(String? drivingSide) =>
    driverNavDrivesOnLeft(drivingSide);

/// A U-turn crosses oncoming traffic, so it turns left where traffic keeps
/// right and right where traffic keeps left.
NavSignManeuver _uturnSign(String? drivingSide) =>
    _isLeftHandTraffic(drivingSide)
    ? NavSignManeuver.uturnRight
    : NavSignManeuver.uturnLeft;

/// Trusted 1-based roundabout exit, or null.
///
/// Rejects blank, non-numeric, zero and negative values. Mapbox
/// `maneuver.exit` is 1-based: exit 1 is the first exit off the roundabout, so
/// a `0` is bad data and must never be shifted into exit 1. Nothing here
/// subtracts or adds an offset, which is what keeps exit counting out of
/// zero-based territory.
int? navSignRoundaboutExit(String? rawExitNumber) {
  final trimmed = (rawExitNumber ?? '').trim();
  if (trimmed.isEmpty) return null;
  final parsed = int.tryParse(trimmed);
  if (parsed == null || parsed <= 0) return null;
  return parsed;
}

/// Maps a trusted exit ordinal to its sign.
///
/// Geometry (right-hand traffic, entering from the bottom, travelling
/// anticlockwise): exit 1 leaves right, exit 2 continues straight, exit 3
/// leaves left, exit 4 turns back. Exits beyond
/// [kNavSignMaxRoundaboutExit] have no dedicated artwork.
NavSignManeuver? _roundaboutExitSign(int exit) {
  switch (exit) {
    case 1:
      return NavSignManeuver.roundaboutExit1;
    case 2:
      return NavSignManeuver.roundaboutExit2;
    case 3:
      return NavSignManeuver.roundaboutExit3;
    case 4:
      return NavSignManeuver.roundaboutExit4;
    default:
      return null;
  }
}

NavSignManeuver _turnSign(_NavSignDirection direction, String? drivingSide) {
  switch (direction) {
    case _NavSignDirection.sharpLeft:
      return NavSignManeuver.sharpLeft;
    case _NavSignDirection.sharpRight:
      return NavSignManeuver.sharpRight;
    case _NavSignDirection.slightLeft:
      return NavSignManeuver.slightLeft;
    case _NavSignDirection.slightRight:
      return NavSignManeuver.slightRight;
    case _NavSignDirection.left:
      return NavSignManeuver.turnLeft;
    case _NavSignDirection.right:
      return NavSignManeuver.turnRight;
    case _NavSignDirection.straight:
      return NavSignManeuver.straight;
    case _NavSignDirection.uturn:
      return _uturnSign(drivingSide);
  }
}

/// Resolves one navigation event to exactly one sign.
///
/// Deterministic and side-effect free apart from a diagnostic log when the
/// event could not be fully classified.
NavSignResolution resolveNavSign(NavSignEvent event) {
  final resolution = _resolveNavSignInternal(event);
  if (resolution.isFallback) {
    _logUnclassifiedNavSign(event, resolution);
  }
  return resolution;
}

NavSignResolution _resolveNavSignInternal(NavSignEvent event) {
  final type = event.maneuverType.trim().toLowerCase();
  final direction = _direction(event.maneuverModifier);
  final drivingSide = event.drivingSide;

  // A neutral placeholder from the instruction pipeline describes no maneuver,
  // so it must not borrow a direction from stale type/modifier fields.
  if (event.neutralFallback) {
    return const NavSignResolution(
      maneuver: NavSignManeuver.followRoute,
      source: NavSignResolutionSource.safeFallback,
    );
  }

  if (driverNavTypeIsArrival(type)) {
    final reached = event.arrivalConfirmed || _isAtDestination(event);
    return NavSignResolution(
      maneuver: reached
          ? NavSignManeuver.destinationReached
          : NavSignManeuver.destinationAhead,
      source: NavSignResolutionSource.classified,
    );
  }

  if (driverNavTypeIsRoundabout(type)) {
    final exit = navSignRoundaboutExit(event.exitNumber);
    final sign = exit == null ? null : _roundaboutExitSign(exit);
    if (sign != null) {
      return NavSignResolution(
        maneuver: sign,
        source: NavSignResolutionSource.roundaboutExit,
        roundaboutExitNumber: exit,
      );
    }
    // Missing, zero, negative, non-numeric or undrawn (>4) exit: show the
    // roundabout itself instead of guessing an arm.
    return NavSignResolution(
      maneuver: NavSignManeuver.roundabout,
      source: NavSignResolutionSource.roundaboutGeneric,
      roundaboutExitNumber: exit,
    );
  }

  if (type.contains('depart') || type.contains('start')) {
    return const NavSignResolution(
      maneuver: NavSignManeuver.departure,
      source: NavSignResolutionSource.classified,
    );
  }

  // `end of road` is a T-junction: the type is context, the modifier carries
  // the instruction. Without a modifier only the junction itself is known.
  if (type.contains('end of road')) {
    if (direction == null) {
      return const NavSignResolution(
        maneuver: NavSignManeuver.roadEnd,
        source: NavSignResolutionSource.categoryFallback,
      );
    }
    if (_leansLeft(direction)) {
      return const NavSignResolution(
        maneuver: NavSignManeuver.tLeft,
        source: NavSignResolutionSource.classified,
      );
    }
    if (_leansRight(direction)) {
      return const NavSignResolution(
        maneuver: NavSignManeuver.tRight,
        source: NavSignResolutionSource.classified,
      );
    }
    if (direction == _NavSignDirection.uturn) {
      return NavSignResolution(
        maneuver: _uturnSign(drivingSide),
        source: NavSignResolutionSource.classified,
      );
    }
    return const NavSignResolution(
      maneuver: NavSignManeuver.tStraight,
      source: NavSignResolutionSource.classified,
    );
  }

  if (type.contains('fork')) {
    if (direction == null) {
      return const NavSignResolution(
        maneuver: NavSignManeuver.forkStraight,
        source: NavSignResolutionSource.categoryFallback,
      );
    }
    if (_leansLeft(direction)) {
      return const NavSignResolution(
        maneuver: NavSignManeuver.forkLeft,
        source: NavSignResolutionSource.classified,
      );
    }
    if (_leansRight(direction)) {
      return const NavSignResolution(
        maneuver: NavSignManeuver.forkRight,
        source: NavSignResolutionSource.classified,
      );
    }
    return const NavSignResolution(
      maneuver: NavSignManeuver.forkStraight,
      source: NavSignResolutionSource.classified,
    );
  }

  if (type.contains('merge')) {
    if (direction == null) {
      return const NavSignResolution(
        maneuver: NavSignManeuver.mergeStraight,
        source: NavSignResolutionSource.categoryFallback,
      );
    }
    if (_leansLeft(direction)) {
      return const NavSignResolution(
        maneuver: NavSignManeuver.mergeLeft,
        source: NavSignResolutionSource.classified,
      );
    }
    if (_leansRight(direction)) {
      return const NavSignResolution(
        maneuver: NavSignManeuver.mergeRight,
        source: NavSignResolutionSource.classified,
      );
    }
    return const NavSignResolution(
      maneuver: NavSignManeuver.mergeStraight,
      source: NavSignResolutionSource.classified,
    );
  }

  // `off ramp` leaves the motorway -> exit sign. `on ramp` joins it -> ramp
  // sign. Both are checked before the bare `ramp` spelling.
  if (type.contains('off ramp') || type.contains('off-ramp')) {
    return _sideSign(
      direction: direction,
      drivingSide: drivingSide,
      left: NavSignManeuver.exitLeft,
      right: NavSignManeuver.exitRight,
    );
  }
  if (type.contains('on ramp') ||
      type.contains('on-ramp') ||
      type.contains('ramp')) {
    return _sideSign(
      direction: direction,
      drivingSide: drivingSide,
      left: NavSignManeuver.rampLeft,
      right: NavSignManeuver.rampRight,
    );
  }

  // `continue` / `new name` / `notification` keep the driver on the current
  // road; a lateral modifier means "keep to that side", not "turn".
  if (type.contains('continue') ||
      type.contains('new name') ||
      type.contains('notification')) {
    if (direction == null) {
      return const NavSignResolution(
        maneuver: NavSignManeuver.straight,
        source: NavSignResolutionSource.categoryFallback,
      );
    }
    if (direction == _NavSignDirection.uturn) {
      return NavSignResolution(
        maneuver: _uturnSign(drivingSide),
        source: NavSignResolutionSource.classified,
      );
    }
    if (_leansLeft(direction)) {
      return const NavSignResolution(
        maneuver: NavSignManeuver.keepLeft,
        source: NavSignResolutionSource.classified,
      );
    }
    if (_leansRight(direction)) {
      return const NavSignResolution(
        maneuver: NavSignManeuver.keepRight,
        source: NavSignResolutionSource.classified,
      );
    }
    return const NavSignResolution(
      maneuver: NavSignManeuver.straight,
      source: NavSignResolutionSource.classified,
    );
  }

  // `turn` and any other type that still carries a usable direction.
  if (direction != null) {
    return NavSignResolution(
      maneuver: _turnSign(direction, drivingSide),
      source: NavSignResolutionSource.classified,
    );
  }

  return const NavSignResolution(
    maneuver: NavSignManeuver.followRoute,
    source: NavSignResolutionSource.safeFallback,
  );
}

NavSignResolution _sideSign({
  required _NavSignDirection? direction,
  required String? drivingSide,
  required NavSignManeuver left,
  required NavSignManeuver right,
}) {
  if (direction != null && _leansLeft(direction)) {
    return NavSignResolution(
      maneuver: left,
      source: NavSignResolutionSource.classified,
    );
  }
  if (direction != null && _leansRight(direction)) {
    return NavSignResolution(
      maneuver: right,
      source: NavSignResolutionSource.classified,
    );
  }
  // Ramps without a modifier sit on the near side of the carriageway, which is
  // the right in right-hand traffic.
  return NavSignResolution(
    maneuver: _isLeftHandTraffic(drivingSide) ? left : right,
    source: NavSignResolutionSource.categoryFallback,
  );
}

/// Arrival becomes "reached" inside the existing `now` band so the sign flips
/// at the same moment the wording already says the destination is reached.
bool _isAtDestination(NavSignEvent event) {
  final distance = event.distanceToManeuverMeters;
  if (distance == null || !distance.isFinite) return false;
  return distance <= kNavSignDestinationReachedMeters;
}

/// Diagnostic hook for unclassified events. Overridable in tests.
@visibleForTesting
void Function(String message) navSignDiagnosticSink = debugPrint;

void _logUnclassifiedNavSign(NavSignEvent event, NavSignResolution resolution) {
  // Type, modifier and exit only — never road names, coordinates or any other
  // field that could identify a ride.
  navSignDiagnosticSink(
    '[NAV_SIGN_UNCLASSIFIED] ${event.diagnosticSignature} '
    'source=${resolution.source.name} shown=${resolution.maneuver.id}',
  );
}
