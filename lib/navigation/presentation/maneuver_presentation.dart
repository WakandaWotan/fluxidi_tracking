import 'package:flutter/material.dart';

import '../driver_navigation_formatters.dart';
import '../driver_navigation_models.dart';
import 'nav_sign_resolver.dart';

/// NAV-RESPONSIVE-MANEUVER-BANNER-V1: distance bands that drive maneuver wording.
///
/// Timing wording ("Over 1 km linksaf" vs "Sla nu linksaf") is chosen from the
/// urgency phase. Distance thresholds are deterministic and centralized so the
/// same rules can be exercised in pure tests.
enum ManeuverUrgencyPhase { far, approaching, near, now }

/// NAV-RESPONSIVE-MANEUVER-BANNER-V1: high-level visual category for the
/// maneuver arrow icon.
///
/// The visual leads the banner. Left / right / roundabout are unmistakable at
/// a glance regardless of the raw Mapbox modifier string used upstream.
enum ManeuverVisual {
  followRoute,
  straight,
  slightLeft,
  left,
  sharpLeft,
  slightRight,
  right,
  sharpRight,
  uTurn,
  merge,
  fork,
  offRamp,
  onRamp,
  roundabout,
  arrive,
  depart,
}

/// NAV-RESPONSIVE-MANEUVER-BANNER-V1: banner phase thresholds in meters.
///
/// Deterministic V1 thresholds. No speed-adaptive behavior — a follow-up task
/// can layer that on top without changing consumers.
const double kDriverManeuverPhaseFarThresholdMeters = 1000.0;
const double kDriverManeuverPhaseApproachingThresholdMeters = 200.0;
const double kDriverManeuverPhaseNearThresholdMeters = 50.0;

/// NAV-RESPONSIVE-MANEUVER-BANNER-V1: normalized banner presentation.
///
/// Pure value type. Consumers must never mutate navigation state or perform
/// I/O when building or reading a presentation.
class ResponsiveManeuverPresentation {
  final ManeuverVisual maneuverVisual;
  final String distanceLabel;
  final String primaryInstruction;
  final String secondaryInstruction;
  final int? roundaboutExitNumber;
  final ManeuverUrgencyPhase urgencyPhase;
  final String accessibilityLabel;
  final bool isArrival;
  final bool isHighwayLike;

  /// NAV-SIGNAGE-VISUAL-RELEASE-GATE: the sign to display, chosen once by
  /// [resolveNavSign] so every consumer shows the same plate.
  final NavSignManeuver signManeuver;

  /// Language directory the sign is loaded from, after fallback.
  final String signLanguageCode;

  /// Why [signManeuver] was chosen. Diagnostics only.
  final NavSignResolutionSource signResolutionSource;

  const ResponsiveManeuverPresentation({
    required this.maneuverVisual,
    required this.distanceLabel,
    required this.primaryInstruction,
    required this.secondaryInstruction,
    required this.urgencyPhase,
    required this.accessibilityLabel,
    required this.isArrival,
    required this.isHighwayLike,
    this.roundaboutExitNumber,
    this.signManeuver = NavSignManeuver.followRoute,
    this.signLanguageCode = kNavSignFallbackLanguageCode,
    this.signResolutionSource = NavSignResolutionSource.safeFallback,
  });

  /// Full bundle path of the sign for this presentation.
  String get signAssetPath =>
      navSignAssetPath(languageCode: signLanguageCode, maneuver: signManeuver);
}

/// NAV-RESPONSIVE-MANEUVER-BANNER-V1: maps a live snapshot to phase.
ManeuverUrgencyPhase resolveDriverManeuverUrgencyPhase(double distanceMeters) {
  if (!distanceMeters.isFinite || distanceMeters <= 0) {
    return ManeuverUrgencyPhase.now;
  }
  if (distanceMeters <= kDriverManeuverPhaseNearThresholdMeters) {
    return ManeuverUrgencyPhase.now;
  }
  if (distanceMeters <= kDriverManeuverPhaseApproachingThresholdMeters) {
    return ManeuverUrgencyPhase.near;
  }
  if (distanceMeters <= kDriverManeuverPhaseFarThresholdMeters) {
    return ManeuverUrgencyPhase.approaching;
  }
  return ManeuverUrgencyPhase.far;
}

/// NAV-RESPONSIVE-MANEUVER-BANNER-V1: material icon for a maneuver visual.
IconData driverManeuverVisualIconData(ManeuverVisual visual) {
  switch (visual) {
    case ManeuverVisual.arrive:
      return Icons.flag_rounded;
    case ManeuverVisual.roundabout:
      return Icons.roundabout_right_rounded;
    case ManeuverVisual.depart:
      return Icons.navigation_rounded;
    case ManeuverVisual.merge:
      return Icons.merge_rounded;
    case ManeuverVisual.fork:
      return Icons.fork_right_rounded;
    case ManeuverVisual.offRamp:
      return Icons.call_split_rounded;
    case ManeuverVisual.onRamp:
      return Icons.alt_route_rounded;
    case ManeuverVisual.sharpLeft:
      return Icons.turn_sharp_left_rounded;
    case ManeuverVisual.sharpRight:
      return Icons.turn_sharp_right_rounded;
    case ManeuverVisual.slightLeft:
      return Icons.turn_slight_left_rounded;
    case ManeuverVisual.slightRight:
      return Icons.turn_slight_right_rounded;
    case ManeuverVisual.uTurn:
      return Icons.u_turn_left_rounded;
    case ManeuverVisual.left:
      return Icons.turn_left_rounded;
    case ManeuverVisual.right:
      return Icons.turn_right_rounded;
    case ManeuverVisual.straight:
    case ManeuverVisual.followRoute:
      return Icons.straight_rounded;
  }
}

/// NAV-END-OF-ROAD-MANEUVER-CORRECTNESS-P0-1: single modifier-normalization
/// helper shared by both the `end of road` branch and the ordinary
/// modifier-precedence flow. Returns `null` when the modifier is empty or
/// unknown so the caller can choose a safe neutral fallback.
///
/// Precedence matches the existing turn/uturn ordering: sharp > slight >
/// uturn > left/right > straight/forward. Never invents a U-turn from
/// missing data — an unknown modifier is `null`, not `uTurn`.
ManeuverVisual? _driverManeuverVisualFromModifier(String modLower) {
  if (modLower.contains('sharp left')) return ManeuverVisual.sharpLeft;
  if (modLower.contains('sharp right')) return ManeuverVisual.sharpRight;
  if (modLower.contains('slight left')) return ManeuverVisual.slightLeft;
  if (modLower.contains('slight right')) return ManeuverVisual.slightRight;
  if (modLower.contains('uturn') || modLower.contains('u-turn')) {
    return ManeuverVisual.uTurn;
  }
  if (modLower.contains('left')) return ManeuverVisual.left;
  if (modLower.contains('right')) return ManeuverVisual.right;
  if (modLower.contains('straight') || modLower.contains('forward')) {
    return ManeuverVisual.straight;
  }
  return null;
}

/// NAV-RESPONSIVE-MANEUVER-BANNER-V1: derives the maneuver visual from a
/// snapshot without falling back to raw instruction words unless nothing else
/// classifies.
ManeuverVisual resolveDriverManeuverVisual(NavInstructionSnapshot snapshot) {
  if (driverNavTypeIsArrival(snapshot.maneuverType)) {
    return ManeuverVisual.arrive;
  }
  if (driverNavTypeIsRoundabout(snapshot.maneuverType)) {
    return ManeuverVisual.roundabout;
  }
  final t = snapshot.maneuverType.toLowerCase();
  final mod = snapshot.maneuverModifier.toLowerCase();
  final hint = '${snapshot.primaryText} ${snapshot.secondaryText}'
      .toLowerCase();

  if (t.contains('depart')) return ManeuverVisual.depart;
  if (t.contains('merge')) return ManeuverVisual.merge;
  // Fork with a directional modifier must show slight/left/right, not a
  // generic split glyph — otherwise synthesized "Hou licht …" loses its arrow.
  if (t.contains('fork')) {
    return _driverManeuverVisualFromModifier(mod) ?? ManeuverVisual.fork;
  }
  if (t.contains('off ramp') || t.contains('off-ramp')) {
    return ManeuverVisual.offRamp;
  }
  if (t.contains('on ramp') || t.contains('on-ramp')) {
    return ManeuverVisual.onRamp;
  }

  // NAV-END-OF-ROAD-MANEUVER-CORRECTNESS-P0-1: `end of road` describes the
  // junction context, not the maneuver direction. Mapbox legitimately emits
  // `end of road` with modifier `left`, `right`, slight/sharp variants or
  // `uturn`. The direction MUST come from the modifier — never a blanket
  // U-turn based on the type alone. Missing/unknown modifier at an
  // `end of road` step is treated as a safe neutral fallback.
  if (t.contains('end of road')) {
    return _driverManeuverVisualFromModifier(mod) ?? ManeuverVisual.followRoute;
  }

  // NAV-SIGNAGE-FIELD-QUALITY-P0-1: plain continue guidance is visually
  // `straight` (upright arrow). Slight/left/right modifiers stay specific;
  // geometry bends alone never become slight/curve.
  if (t.contains('continue') ||
      t.contains('new name') ||
      t.contains('notification')) {
    return _driverManeuverVisualFromModifier(mod) ?? ManeuverVisual.straight;
  }

  final fromModifier = _driverManeuverVisualFromModifier(mod);
  if (fromModifier != null) return fromModifier;

  // Fall back to instruction-text hints only when the modifier is empty.
  if (mod.isEmpty) {
    if (hint.contains('u-turn') || hint.contains('u turn')) {
      return ManeuverVisual.uTurn;
    }
    if (hint.contains('links') ||
        hint.contains(' left') ||
        hint.contains('gauche')) {
      return ManeuverVisual.left;
    }
    if (hint.contains('rechts') ||
        hint.contains(' right') ||
        hint.contains('droite')) {
      return ManeuverVisual.right;
    }
    if (hint.contains('rechtdoor') || hint.contains('straight')) {
      return ManeuverVisual.straight;
    }
  }

  return ManeuverVisual.followRoute;
}

/// NAV-RESPONSIVE-MANEUVER-BANNER-V1: parses `exitNumber` from a snapshot.
///
/// Returns `null` when the string is missing, blank, or non-numeric. Exit
/// numbers must never be invented — a null result means the source data does
/// not supply an ordinal.
///
/// NAV-SIGNAGE-VISUAL-RELEASE-GATE: delegates to [navSignRoundaboutExit] so
/// the wording and the sign can never disagree about which exit is trusted.
int? resolveDriverRoundaboutExitNumber(String? raw) =>
    navSignRoundaboutExit(raw);

/// NAV-RESPONSIVE-MANEUVER-BANNER-V1: Dutch ordinal for roundabout exits.
///
/// 1 → 1ste, 2 → 2de, 3 → 3de, 4+ → 4de, 5de, ...
String driverRoundaboutExitOrdinalDutch(int exit) {
  if (exit <= 1) return '1ste';
  return '${exit}de';
}

String _ordinalEnglish(int n) {
  final abs = n.abs();
  final lastTwo = abs % 100;
  if (lastTwo >= 11 && lastTwo <= 13) return '${n}th';
  switch (abs % 10) {
    case 1:
      return '${n}st';
    case 2:
      return '${n}nd';
    case 3:
      return '${n}rd';
    default:
      return '${n}th';
  }
}

String _ordinalFrench(int n) => n == 1 ? '1re' : '${n}e';

// NAV-RESPONSIVE-MANEUVER-BANNER-V1: `ª` is not a valid identifier char, so
// concatenation avoids interpolation ambiguity and dart-format churn.
String _ordinalSpanish(int n) => n.toString() + 'ª';

/// NAV-END-OF-ROAD-MANEUVER-CORRECTNESS-P0-1: Portuguese roundabout exit
/// ordinal. Portuguese uses the feminine ordinal marker `.ª` because the noun
/// `saída` is feminine. `1.ª`, `2.ª`, `3.ª`, `4.ª`, … — deterministic.
///
/// The pure helper exists so future PT plumbing (when `AppLanguage.pt` is
/// added) can wire it without a new localization framework. Callers today
/// receive NL/EN/FR/ES via [driverRoundaboutExitOrdinal]; PT is only produced
/// by explicitly calling this helper.
// NAV-END-OF-ROAD-MANEUVER-CORRECTNESS-P0-1: `ª` is not a valid identifier
// character, so concatenation avoids interpolation ambiguity and lint noise —
// same rationale as `_ordinalSpanish` above.
String driverRoundaboutExitOrdinalPortuguese(int n) => n.toString() + '.ª';

/// NAV-END-OF-ROAD-MANEUVER-CORRECTNESS-P0-1: Portuguese roundabout exit
/// sentence, deterministic and framework-free. Matches the app's terse
/// imperative convention used across driver-facing navigation strings.
String driverRoundaboutExitLinePortuguese(int n) =>
    'Pegue a ${driverRoundaboutExitOrdinalPortuguese(n)} saída';

/// NAV-RESPONSIVE-MANEUVER-BANNER-V1: localized roundabout exit ordinal.
String driverRoundaboutExitOrdinal(int exit, DriverNavTranslate tr) {
  return tr(
    nl: driverRoundaboutExitOrdinalDutch(exit),
    en: _ordinalEnglish(exit),
    fr: _ordinalFrench(exit),
    es: _ordinalSpanish(exit),
  );
}

String _followRouteText(DriverNavTranslate tr) => tr(
  nl: 'Volg de route',
  en: 'Follow the route',
  fr: "Suivez l'itinéraire",
  es: 'Sigue la ruta',
);

String _towardWord(DriverNavTranslate tr) =>
    tr(nl: 'naar', en: 'toward', fr: 'vers', es: 'hacia');

String _distancePrefixWord(DriverNavTranslate tr) =>
    tr(nl: 'Over', en: 'In', fr: 'Dans', es: 'En');

String _directionActionWord({
  required ManeuverVisual visual,
  required DriverNavTranslate tr,
}) {
  switch (visual) {
    case ManeuverVisual.left:
      return tr(
        nl: 'linksaf',
        en: 'turn left',
        fr: 'à gauche',
        es: 'a la izquierda',
      );
    case ManeuverVisual.right:
      return tr(
        nl: 'rechtsaf',
        en: 'turn right',
        fr: 'à droite',
        es: 'a la derecha',
      );
    case ManeuverVisual.slightLeft:
      return tr(
        nl: 'Hou licht links',
        en: 'Keep slight left',
        fr: 'Serrez légèrement à gauche',
        es: 'Mantén ligeramente a la izquierda',
      );
    case ManeuverVisual.slightRight:
      return tr(
        nl: 'Hou licht rechts',
        en: 'Keep slight right',
        fr: 'Serrez légèrement à droite',
        es: 'Mantén ligeramente a la derecha',
      );
    case ManeuverVisual.sharpLeft:
      return tr(
        nl: 'scherp linksaf',
        en: 'sharp left',
        fr: 'à gauche sévère',
        es: 'brusco a la izquierda',
      );
    case ManeuverVisual.sharpRight:
      return tr(
        nl: 'scherp rechtsaf',
        en: 'sharp right',
        fr: 'à droite sévère',
        es: 'brusco a la derecha',
      );
    case ManeuverVisual.straight:
      return tr(
        nl: 'rechtdoor',
        en: 'continue straight',
        fr: 'continuez tout droit',
        es: 'sigue recto',
      );
    case ManeuverVisual.uTurn:
      return tr(
        nl: 'keer om',
        en: 'make a U-turn',
        fr: 'faites demi-tour',
        es: 'da la vuelta',
      );
    case ManeuverVisual.merge:
      return tr(
        nl: 'voeg in',
        en: 'merge',
        fr: 'insérez-vous',
        es: 'incorpórate',
      );
    case ManeuverVisual.fork:
      return tr(
        nl: 'volg de splitsing',
        en: 'keep at the fork',
        fr: 'suivez la fourche',
        es: 'sigue la bifurcación',
      );
    case ManeuverVisual.offRamp:
      return tr(
        nl: 'neem de afslag',
        en: 'take the exit',
        fr: 'prenez la sortie',
        es: 'toma la salida',
      );
    case ManeuverVisual.onRamp:
      return tr(
        nl: 'volg de oprit',
        en: 'take the ramp',
        fr: 'prenez la bretelle',
        es: 'toma la rampa',
      );
    case ManeuverVisual.depart:
      return tr(
        nl: 'begin de rit',
        en: 'start driving',
        fr: 'commencez à conduire',
        es: 'empieza a conducir',
      );
    case ManeuverVisual.arrive:
      return tr(
        nl: 'bestemming bereikt',
        en: 'destination reached',
        fr: 'destination atteinte',
        es: 'destino alcanzado',
      );
    case ManeuverVisual.roundabout:
    case ManeuverVisual.followRoute:
      return _followRouteText(tr);
  }
}

String _nowPrimary({
  required ManeuverVisual visual,
  required DriverNavTranslate tr,
}) {
  switch (visual) {
    case ManeuverVisual.left:
      return tr(
        nl: 'Sla nu linksaf',
        en: 'Turn left now',
        fr: 'Tournez à gauche maintenant',
        es: 'Gira a la izquierda ahora',
      );
    case ManeuverVisual.right:
      return tr(
        nl: 'Sla nu rechtsaf',
        en: 'Turn right now',
        fr: 'Tournez à droite maintenant',
        es: 'Gira a la derecha ahora',
      );
    case ManeuverVisual.slightLeft:
      return tr(
        nl: 'Nu licht links houden',
        en: 'Keep slight left now',
        fr: 'Serrez à gauche maintenant',
        es: 'Mantén a la izquierda ahora',
      );
    case ManeuverVisual.slightRight:
      return tr(
        nl: 'Nu licht rechts houden',
        en: 'Keep slight right now',
        fr: 'Serrez à droite maintenant',
        es: 'Mantén a la derecha ahora',
      );
    case ManeuverVisual.sharpLeft:
      return tr(
        nl: 'Nu scherp linksaf',
        en: 'Sharp left now',
        fr: 'À gauche sévère maintenant',
        es: 'Brusco a la izquierda ahora',
      );
    case ManeuverVisual.sharpRight:
      return tr(
        nl: 'Nu scherp rechtsaf',
        en: 'Sharp right now',
        fr: 'À droite sévère maintenant',
        es: 'Brusco a la derecha ahora',
      );
    case ManeuverVisual.straight:
      return tr(
        nl: 'Nu rechtdoor',
        en: 'Continue straight now',
        fr: 'Continuez tout droit maintenant',
        es: 'Sigue recto ahora',
      );
    case ManeuverVisual.uTurn:
      return tr(
        nl: 'Keer nu om',
        en: 'Make a U-turn now',
        fr: 'Faites demi-tour maintenant',
        es: 'Da la vuelta ahora',
      );
    case ManeuverVisual.merge:
      return tr(
        nl: 'Voeg nu in',
        en: 'Merge now',
        fr: 'Insérez-vous maintenant',
        es: 'Incorpórate ahora',
      );
    case ManeuverVisual.fork:
      return tr(
        nl: 'Volg nu de splitsing',
        en: 'Keep at the fork now',
        fr: 'Suivez la fourche maintenant',
        es: 'Sigue la bifurcación ahora',
      );
    case ManeuverVisual.offRamp:
      return tr(
        nl: 'Neem nu de afslag',
        en: 'Take the exit now',
        fr: 'Prenez la sortie maintenant',
        es: 'Toma la salida ahora',
      );
    case ManeuverVisual.onRamp:
      return tr(
        nl: 'Volg nu de oprit',
        en: 'Take the ramp now',
        fr: 'Prenez la bretelle maintenant',
        es: 'Toma la rampa ahora',
      );
    case ManeuverVisual.roundabout:
      return tr(
        nl: 'Op de rotonde',
        en: 'In the roundabout',
        fr: 'Dans le rond-point',
        es: 'En la rotonda',
      );
    case ManeuverVisual.arrive:
      return tr(
        nl: 'Bestemming bereikt',
        en: 'Destination reached',
        fr: 'Destination atteinte',
        es: 'Destino alcanzado',
      );
    case ManeuverVisual.depart:
    case ManeuverVisual.followRoute:
      return _followRouteText(tr);
  }
}

String _roundaboutApproachPrimary({
  required String distanceLabel,
  required DriverNavTranslate tr,
}) {
  final prefix = _distancePrefixWord(tr);
  final entry = tr(
    nl: 'de rotonde op',
    en: 'enter the roundabout',
    fr: 'entrez dans le rond-point',
    es: 'entra en la rotonda',
  );
  return '$prefix $distanceLabel $entry';
}

String _turnApproachPrimary({
  required String distanceLabel,
  required ManeuverVisual visual,
  required DriverNavTranslate tr,
}) {
  final prefix = _distancePrefixWord(tr);
  final action = _directionActionWord(visual: visual, tr: tr);
  return '$prefix $distanceLabel $action';
}

String _towardLabel({
  required NavInstructionSnapshot snapshot,
  required DriverNavTranslate tr,
}) {
  final ref = (snapshot.roadRef ?? '').trim();
  final dest = (snapshot.destinationText ?? '').trim();
  final road = snapshot.roadName.trim();
  final target = ref.isNotEmpty
      ? ref
      : dest.isNotEmpty
      ? dest
      : road;
  if (target.isEmpty) return '';
  return '${_towardWord(tr)} $target';
}

String _roundaboutExitLine(int exit, DriverNavTranslate tr) {
  final ordinal = driverRoundaboutExitOrdinal(exit, tr);
  return tr(
    nl: 'Neem de $ordinal afslag',
    en: 'Take the $ordinal exit',
    fr: 'Prenez la $ordinal sortie',
    es: 'Toma la $ordinal salida',
  );
}

class _ManeuverWording {
  final String primary;
  final String secondary;
  final String accessibility;
  final bool showDistanceChip;

  const _ManeuverWording({
    required this.primary,
    required this.secondary,
    required this.accessibility,
    required this.showDistanceChip,
  });
}

String _accessibilityFor({
  required String primary,
  required String secondary,
  required String distanceLabel,
  required bool showDistanceChip,
  required DriverNavTranslate tr,
}) {
  final buf = StringBuffer();
  if (showDistanceChip && distanceLabel.isNotEmpty) {
    buf.write('${_distancePrefixWord(tr)} $distanceLabel. ');
  }
  buf.write(primary);
  if (secondary.isNotEmpty) {
    buf.write('. ');
    buf.write(secondary);
  }
  buf.write('.');
  return buf.toString();
}

/// NAV-RESPONSIVE-MANEUVER-BANNER-V1: builds a normalized presentation from a
/// live snapshot. Pure — no I/O, no navigation-state mutation.
///
/// NAV-SIGNAGE-VISUAL-RELEASE-GATE: [languageCode] is the active customer
/// language and is the only input that selects a sign language. When omitted
/// the sign falls back to Dutch rather than to a device or company locale.
/// [drivingSide] and [arrivalConfirmed] override what the snapshot already
/// carries; production leaves both unset and lets the guidance fields the
/// maneuver owner stamped on the snapshot decide.
///
/// NAV-MANEUVER-OWNER-REBASE-1: when the owner withheld the maneuver — it is
/// still outside its activation window — the banner shows plain follow-route
/// wording and the follow-route sign. Activation itself is never decided here.
ResponsiveManeuverPresentation buildResponsiveManeuverPresentation({
  required NavInstructionSnapshot snapshot,
  required DriverNavTranslate tr,
  String? languageCode,
  String? drivingSide,
  bool? arrivalConfirmed,
}) {
  final rawVisual = resolveDriverManeuverVisual(snapshot);
  final isArrival = rawVisual == ManeuverVisual.arrive;
  final ownerWithholdsManeuver = snapshot.followRouteForced && !isArrival;
  final visual = ownerWithholdsManeuver
      ? ManeuverVisual.followRoute
      : rawVisual;
  final phase = resolveDriverManeuverUrgencyPhase(
    snapshot.distanceToManeuverMeters,
  );
  final sign = resolveNavSign(
    NavSignEvent.fromSnapshot(
      snapshot,
      drivingSide: drivingSide,
      arrivalConfirmed: arrivalConfirmed,
    ),
  );
  final distanceLabel = formatManeuverDistance(
    snapshot.distanceToManeuverMeters,
  );
  final exitNumber = resolveDriverRoundaboutExitNumber(snapshot.exitNumber);
  final isNeutralFallback =
      snapshot.source == NavInstructionSource.fallback ||
      ownerWithholdsManeuver;

  late final _ManeuverWording wording;

  if (isArrival) {
    final txt = _nowPrimary(visual: ManeuverVisual.arrive, tr: tr);
    wording = _ManeuverWording(
      primary: txt,
      secondary: '',
      accessibility: '$txt.',
      showDistanceChip: false,
    );
  } else if (isNeutralFallback ||
      visual == ManeuverVisual.followRoute ||
      visual == ManeuverVisual.depart) {
    final followText = _followRouteText(tr);
    final rawPrimary = snapshot.primaryText.trim();
    // Neutral fallback (policy) => "Volg de route".
    // Depart / unclassified with real text => keep raw text as safe fallback.
    final primary = (isNeutralFallback || rawPrimary.isEmpty)
        ? followText
        : rawPrimary;
    final secondary = _towardLabel(snapshot: snapshot, tr: tr);
    final showChip =
        phase == ManeuverUrgencyPhase.far ||
        phase == ManeuverUrgencyPhase.approaching ||
        phase == ManeuverUrgencyPhase.near;
    final acc = _accessibilityFor(
      primary: primary,
      secondary: secondary,
      distanceLabel: distanceLabel,
      showDistanceChip: showChip,
      tr: tr,
    );
    wording = _ManeuverWording(
      primary: primary,
      secondary: secondary,
      accessibility: acc,
      showDistanceChip: showChip,
    );
  } else if (visual == ManeuverVisual.roundabout) {
    // NAV-ROUNDABOUT-LANE-CLARITY-P0-2026-07-31: when the exit ordinal is
    // known and we are close enough for the driver to act on it (any phase
    // except `far`), "Neem de Nde afslag" is promoted to the PRIMARY
    // instruction. The destination road name — the previous primary
    // approach text — becomes secondary and MAY controllably ellipsize on
    // the second line. This eliminates the ambiguity where the eye first
    // read "Over 400 m ...  de rotonde op" and only then found the small
    // exit ordinal on the next line.
    //
    // When the exit ordinal is missing we keep the legacy approach wording
    // so we never fabricate an ordinal.
    final String primary;
    final String secondary;
    final bool showChip;
    if (phase == ManeuverUrgencyPhase.now) {
      if (exitNumber != null) {
        primary = _roundaboutExitLine(exitNumber, tr);
        secondary = _towardLabel(snapshot: snapshot, tr: tr);
        showChip = false;
      } else {
        primary = _nowPrimary(visual: ManeuverVisual.roundabout, tr: tr);
        secondary = _towardLabel(snapshot: snapshot, tr: tr);
        showChip = false;
      }
    } else if (phase == ManeuverUrgencyPhase.far) {
      // Too far to act on the exit ordinal yet — keep neutral wording.
      primary = _followRouteText(tr);
      secondary = exitNumber != null
          ? _roundaboutExitLine(exitNumber, tr)
          : _towardLabel(snapshot: snapshot, tr: tr);
      showChip = true;
    } else {
      // approaching / near — the exit ordinal IS actionable now.
      if (exitNumber != null) {
        primary = _roundaboutExitLine(exitNumber, tr);
        secondary = _towardLabel(snapshot: snapshot, tr: tr);
        showChip = true;
      } else {
        primary = _roundaboutApproachPrimary(
          distanceLabel: distanceLabel,
          tr: tr,
        );
        secondary = _towardLabel(snapshot: snapshot, tr: tr);
        showChip = false;
      }
    }
    final acc = _accessibilityFor(
      primary: primary,
      secondary: secondary,
      distanceLabel: distanceLabel,
      showDistanceChip: showChip,
      tr: tr,
    );
    wording = _ManeuverWording(
      primary: primary,
      secondary: secondary,
      accessibility: acc,
      showDistanceChip: showChip,
    );
  } else {
    // Turn / merge / fork / ramp / U-turn / straight.
    // Slight forks: show the directional action during far/approaching so the
    // arrow is not delayed until maneuver_instruction (PART B).
    final isSlightFork =
        visual == ManeuverVisual.slightLeft ||
        visual == ManeuverVisual.slightRight;
    final String primary;
    final bool showChip;
    switch (phase) {
      case ManeuverUrgencyPhase.far:
        if (isSlightFork) {
          primary = _turnApproachPrimary(
            distanceLabel: distanceLabel,
            visual: visual,
            tr: tr,
          );
          showChip = false;
        } else {
          primary = _followRouteText(tr);
          showChip = true;
        }
        break;
      case ManeuverUrgencyPhase.approaching:
      case ManeuverUrgencyPhase.near:
        primary = _turnApproachPrimary(
          distanceLabel: distanceLabel,
          visual: visual,
          tr: tr,
        );
        showChip = false;
        break;
      case ManeuverUrgencyPhase.now:
        primary = _nowPrimary(visual: visual, tr: tr);
        showChip = false;
        break;
    }
    final secondary = _towardLabel(snapshot: snapshot, tr: tr);
    final acc = _accessibilityFor(
      primary: primary,
      secondary: secondary,
      distanceLabel: distanceLabel,
      showDistanceChip: showChip,
      tr: tr,
    );
    wording = _ManeuverWording(
      primary: primary,
      secondary: secondary,
      accessibility: acc,
      showDistanceChip: showChip,
    );
  }

  return ResponsiveManeuverPresentation(
    maneuverVisual: visual,
    distanceLabel: wording.showDistanceChip ? distanceLabel : '',
    primaryInstruction: wording.primary,
    secondaryInstruction: wording.secondary,
    roundaboutExitNumber: exitNumber,
    urgencyPhase: phase,
    accessibilityLabel: wording.accessibility,
    isArrival: isArrival,
    isHighwayLike: snapshot.isHighwayLike,
    signManeuver: sign.maneuver,
    signLanguageCode: resolveNavSignLanguageCode(languageCode),
    signResolutionSource: sign.source,
  );
}
