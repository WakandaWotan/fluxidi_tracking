import 'package:flutter/material.dart';

import 'driver_navigation_map_config.dart';
import 'driver_navigation_models.dart';

typedef DriverNavTranslate =
    String Function({
      required String nl,
      required String en,
      required String fr,
      required String es,
    });

String formatManeuverDistance(double meters) {
  if (meters < 1000) return '${meters.round()} m';
  return '${(meters / 1000.0).toStringAsFixed(1).replaceAll('.', ',')} km';
}

String driverNavDistanceText(double meters) => formatManeuverDistance(meters);

final RegExp _driverHighwayRefPattern = RegExp(
  r'\b([EANR]\d+)\b',
  caseSensitive: false,
);

bool _looksLikeDriverHighwayRef(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return false;
  return _driverHighwayRefPattern.hasMatch(text.toUpperCase());
}

bool isDriverHighwayLikeStep(DriverNavStep step) {
  final type = step.type.toLowerCase();
  if (type.contains('off ramp') ||
      type.contains('on ramp') ||
      type.contains('ramp')) {
    return true;
  }
  if ((step.exitNumber ?? '').trim().isNotEmpty) return true;
  if ((step.destinationText ?? '').trim().isNotEmpty) return true;
  if (_looksLikeDriverHighwayRef(step.roadRef)) return true;
  if (_looksLikeDriverHighwayRef(step.street)) return true;
  // NAV-SIGNAL-P1B: do not read legacy step.banner for live highway-like
  // classification (banner text may describe a different maneuver).
  return false;
}

bool driverNavTypeIsArrival(String? type) {
  final t = (type ?? '').toLowerCase();
  return t.contains('arrive') || t.contains('destination');
}

bool driverNavTypeIsRoundabout(String? type) {
  final t = (type ?? '').toLowerCase();
  return t.contains('roundabout') || t.contains('rotary');
}

String driverShortNavAction(
  String instruction,
  String? type,
  String? modifier, {
  required DriverNavTranslate tr,
}) {
  if (driverNavTypeIsArrival(type)) {
    return tr(
      nl: 'bestemming bereikt',
      en: 'destination reached',
      fr: 'destination atteinte',
      es: 'destino alcanzado',
    );
  }
  if (driverNavTypeIsRoundabout(type)) {
    return tr(
      nl: 'neem de rotonde',
      en: 'take the roundabout',
      fr: 'prenez le rond-point',
      es: 'toma la rotonda',
    );
  }
  final mod = (modifier ?? '').toLowerCase();
  if (mod.contains('slight left')) {
    return tr(
      nl: 'Hou licht links',
      en: 'Keep slight left',
      fr: 'Serrez légèrement à gauche',
      es: 'Mantén ligeramente a la izquierda',
    );
  }
  if (mod.contains('slight right')) {
    return tr(
      nl: 'Hou licht rechts',
      en: 'Keep slight right',
      fr: 'Serrez légèrement à droite',
      es: 'Mantén ligeramente a la derecha',
    );
  }
  if (mod.contains('left')) {
    return tr(
      nl: 'linksaf',
      en: 'turn left',
      fr: 'tournez à gauche',
      es: 'gira a la izquierda',
    );
  }
  if (mod.contains('right')) {
    return tr(
      nl: 'rechtsaf',
      en: 'turn right',
      fr: 'tournez à droite',
      es: 'gira a la derecha',
    );
  }
  if (mod.contains('straight') || mod.contains('forward')) {
    return tr(
      nl: 'rechtdoor',
      en: 'continue straight',
      fr: 'continuez tout droit',
      es: 'sigue recto',
    );
  }

  final lower = instruction.toLowerCase();
  if (lower.contains('links') ||
      lower.contains('left') ||
      lower.contains('gauche')) {
    return tr(
      nl: 'linksaf',
      en: 'turn left',
      fr: 'tournez à gauche',
      es: 'gira a la izquierda',
    );
  }
  if (lower.contains('rechts') ||
      lower.contains('right') ||
      lower.contains('droite')) {
    return tr(
      nl: 'rechtsaf',
      en: 'turn right',
      fr: 'tournez à droite',
      es: 'gira a la derecha',
    );
  }
  if (lower.contains('rotonde') ||
      lower.contains('roundabout') ||
      lower.contains('rond-point')) {
    return tr(
      nl: 'neem de rotonde',
      en: 'take the roundabout',
      fr: 'prenez le rond-point',
      es: 'toma la rotonda',
    );
  }
  if (lower.contains('rechtdoor') ||
      lower.contains('continue') ||
      lower.contains('straight')) {
    return tr(
      nl: 'rechtdoor',
      en: 'continue straight',
      fr: 'continuez tout droit',
      es: 'sigue recto',
    );
  }
  return instruction;
}

IconData driverManeuverIconData(
  String? type,
  String? modifier,
  String instruction,
) {
  final t = (type ?? '').toLowerCase();
  final mod = (modifier ?? '').toLowerCase();
  final combined = '$mod $instruction'.toLowerCase();

  if (driverNavTypeIsArrival(type)) return Icons.flag_rounded;
  if (driverNavTypeIsRoundabout(type)) return Icons.roundabout_right_rounded;
  if (t.contains('depart')) return Icons.navigation_rounded;
  if (t.contains('merge')) return Icons.merge_rounded;
  if (t.contains('fork')) return Icons.fork_right_rounded;
  if (t.contains('off ramp') || t.contains('off-ramp')) {
    return Icons.call_split_rounded;
  }
  if (t.contains('on ramp') || t.contains('on-ramp')) {
    return Icons.alt_route_rounded;
  }
  // NAV-END-OF-ROAD-MANEUVER-CORRECTNESS-P0-1: `end of road` is a junction
  // context, never a direction on its own. The direction comes strictly from
  // the modifier below. When the modifier is absent, the code falls through
  // to the neutral straight/follow-route default at the bottom of this
  // function — never a false U-turn. Combined text hints must not upgrade an
  // `end of road` step to U-turn either; only an explicit `uturn` modifier
  // may do so.
  final endOfRoad = t.contains('end of road');
  if (mod.contains('sharp left') ||
      (!endOfRoad && combined.contains('sharp left'))) {
    return Icons.turn_sharp_left_rounded;
  }
  if (mod.contains('sharp right') ||
      (!endOfRoad && combined.contains('sharp right'))) {
    return Icons.turn_sharp_right_rounded;
  }
  if (mod.contains('slight left') ||
      (!endOfRoad && combined.contains('slight left'))) {
    return Icons.turn_slight_left_rounded;
  }
  if (mod.contains('slight right') ||
      (!endOfRoad && combined.contains('slight right'))) {
    return Icons.turn_slight_right_rounded;
  }
  if (mod.contains('uturn') ||
      mod.contains('u-turn') ||
      (!endOfRoad && combined.contains('u-turn'))) {
    return Icons.u_turn_left_rounded;
  }
  if (mod.contains('left') ||
      (!endOfRoad &&
          (combined.contains('left') ||
              combined.contains('links') ||
              combined.contains('gauche')))) {
    return Icons.turn_left_rounded;
  }
  if (mod.contains('right') ||
      (!endOfRoad &&
          (combined.contains('right') ||
              combined.contains('rechts') ||
              combined.contains('droite')))) {
    return Icons.turn_right_rounded;
  }
  if (t.contains('exit') ||
      combined.contains('exit') ||
      combined.contains('afrit') ||
      combined.contains('sortie')) {
    return Icons.call_split_rounded;
  }
  if (mod.contains('straight') ||
      mod.contains('forward') ||
      combined.contains('straight') ||
      combined.contains('rechtdoor')) {
    return Icons.straight_rounded;
  }
  return Icons.straight_rounded;
}

/// Compact arrow glyph for a Mapbox lane [indication] string.
String driverLaneIndicationArrow(String indication) {
  final lower = indication.trim().toLowerCase().replaceAll('_', ' ');
  if (lower.isEmpty) return '·';
  if (lower.contains('uturn') || lower.contains('u-turn')) return '↩';
  if (lower.contains('sharp left')) return '↙';
  if (lower.contains('sharp right')) return '↘';
  if (lower.contains('slight left')) return '↖';
  if (lower.contains('slight right')) return '↗';
  if (lower.contains('merge')) {
    if (lower.contains('left')) return '↖';
    if (lower.contains('right')) return '↗';
    return '↗';
  }
  if (lower.contains('left')) return '←';
  if (lower.contains('right')) return '→';
  if (lower.contains('straight') ||
      lower.contains('forward') ||
      lower == 'none') {
    return '↑';
  }
  return '·';
}

/// Short English maneuver word for accessibility labels.
String driverLaneIndicationLabel(String indication) {
  final lower = indication.trim().toLowerCase().replaceAll('_', ' ');
  if (lower.isEmpty) return 'unknown';
  if (lower.contains('uturn') || lower.contains('u-turn')) return 'u-turn';
  if (lower.contains('sharp left')) return 'sharp left';
  if (lower.contains('sharp right')) return 'sharp right';
  if (lower.contains('slight left')) return 'slight left';
  if (lower.contains('slight right')) return 'slight right';
  if (lower.contains('merge')) return 'merge';
  if (lower.contains('left')) return 'left';
  if (lower.contains('right')) return 'right';
  if (lower.contains('straight') ||
      lower.contains('forward') ||
      lower == 'none') {
    return 'straight';
  }
  return lower;
}

/// Display-kind decoded from resolver→snapshot mapping.
///
/// Mapping contract ([mapResolvedLanesForDisplay]):
/// - preferred → valid=true, active=true
/// - usable → valid=true, active=null
/// - unavailable → valid=false
/// - unknown → valid=null
enum DriverLaneDisplayKind { unavailable, usable, preferred, unknown }

DriverLaneDisplayKind driverLaneDisplayKind(DriverNavLaneGuidance lane) {
  if (lane.valid == false) return DriverLaneDisplayKind.unavailable;
  if (lane.valid == true && lane.active == true) {
    return DriverLaneDisplayKind.preferred;
  }
  if (lane.valid == true) return DriverLaneDisplayKind.usable;
  return DriverLaneDisplayKind.unknown;
}

/// True only for explicitly preferred lanes (not every usable lane).
bool driverLaneIsPreferred(DriverNavLaneGuidance lane) =>
    driverLaneDisplayKind(lane) == DriverLaneDisplayKind.preferred;

/// True when the lane is usable or preferred for the current maneuver.
bool driverLaneIsUsableForManeuver(DriverNavLaneGuidance lane) {
  final kind = driverLaneDisplayKind(lane);
  return kind == DriverLaneDisplayKind.usable ||
      kind == DriverLaneDisplayKind.preferred;
}

/// Legacy name retained for call-site compatibility — means preferred only.
bool driverLaneIsRecommended(DriverNavLaneGuidance lane) =>
    driverLaneIsPreferred(lane);

/// Picks the lane indication glyph to show, preferring maneuver alignment.
String? driverLaneIndicationForDisplay(
  DriverNavLaneGuidance lane, {
  String? maneuverModifier,
}) {
  final indications = lane.indications;
  final validHint = (lane.validIndication ?? '').trim().toLowerCase();
  if (validHint.isNotEmpty) {
    for (final indication in indications) {
      final lower = indication.toLowerCase();
      if (lower == validHint || lower.contains(validHint)) {
        return indication;
      }
    }
  }
  final mod = (maneuverModifier ?? '').trim().toLowerCase();
  if (mod.isNotEmpty) {
    for (final indication in indications) {
      final lower = indication.toLowerCase();
      if (mod.contains('left') && lower.contains('left')) return indication;
      if (mod.contains('right') && lower.contains('right')) return indication;
      if ((mod.contains('straight') || mod.contains('forward')) &&
          (lower.contains('straight') ||
              lower.contains('forward') ||
              lower == 'none')) {
        return indication;
      }
      if (mod.contains('uturn') &&
          (lower.contains('uturn') || lower.contains('u-turn'))) {
        return indication;
      }
      if (mod.contains('merge') && lower.contains('merge')) return indication;
    }
  }
  if (indications.isEmpty) return null;
  return indications.first;
}

String driverLaneSemanticLabel(
  DriverNavLaneGuidance lane, {
  String? maneuverModifier,
}) {
  final indication = driverLaneIndicationForDisplay(
    lane,
    maneuverModifier: maneuverModifier,
  );
  final label = driverLaneIndicationLabel(indication ?? '');
  final kind = driverLaneDisplayKind(lane);
  final prefix = switch (kind) {
    DriverLaneDisplayKind.preferred => 'Preferred lane',
    DriverLaneDisplayKind.usable => 'Usable lane',
    DriverLaneDisplayKind.unavailable => 'Unavailable lane',
    DriverLaneDisplayKind.unknown => 'Lane',
  };
  if (indication == null || indication.trim().isEmpty) return prefix;
  return '$prefix: $label';
}

/// Lanes rendered in the navigation banner.
///
/// When the master feature gate is on, returns the snapshot list 1:1 so
/// displayed column count equals resolver column count. Empty/unsupported
/// indications remain as visible neutral columns (never dropped).
///
/// NAV-ROUNDABOUT-LANE-CLARITY-P0-2026-07-31: when [driverNavLanesHaveConfidence]
/// returns false the strip is suppressed entirely to prevent a misleading
/// panel of purely "unknown" pills that could look like guidance the source
/// data never provided.
List<DriverNavLaneGuidance> driverNavLanesForBannerDisplay(
  List<DriverNavLaneGuidance> lanes, {
  bool? featureEnabled,
}) {
  final enabled = featureEnabled ?? driverNavLaneGuidanceFeatureEnabled;
  if (!enabled) return const <DriverNavLaneGuidance>[];
  if (lanes.isEmpty) return const <DriverNavLaneGuidance>[];
  if (!driverNavLanesHaveConfidence(lanes)) {
    return const <DriverNavLaneGuidance>[];
  }
  return List<DriverNavLaneGuidance>.unmodifiable(lanes);
}

/// NAV-ROUNDABOUT-LANE-CLARITY-P0-2026-07-31: true iff the incoming lane list
/// carries enough source-data confidence to render meaningful guidance.
///
/// A lane row is only "confident" when at least one lane carries a concrete
/// `valid=true`, `valid=false`, or `active=true` signal. When every lane in
/// the list is `unknown` (valid=null AND active=null) we treat the row as
/// uncertain and the caller must not render a lane strip — otherwise the
/// driver would see a bar of neutral arrows that suggests guidance that the
/// data never provided.
///
/// Empty list is not confident by definition (nothing to render).
bool driverNavLanesHaveConfidence(List<DriverNavLaneGuidance> lanes) {
  if (lanes.isEmpty) return false;
  for (final lane in lanes) {
    if (lane.valid == true || lane.valid == false || lane.active == true) {
      return true;
    }
  }
  return false;
}
