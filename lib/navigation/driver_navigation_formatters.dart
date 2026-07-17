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
      nl: 'flauw linksaf',
      en: 'slight left',
      fr: 'légèrement à gauche',
      es: 'ligeramente a la izquierda',
    );
  }
  if (mod.contains('slight right')) {
    return tr(
      nl: 'flauw rechtsaf',
      en: 'slight right',
      fr: 'légèrement à droite',
      es: 'ligeramente a la derecha',
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
  if (t.contains('end of road')) return Icons.u_turn_left_rounded;
  if (mod.contains('sharp left') || combined.contains('sharp left')) {
    return Icons.turn_sharp_left_rounded;
  }
  if (mod.contains('sharp right') || combined.contains('sharp right')) {
    return Icons.turn_sharp_right_rounded;
  }
  if (mod.contains('slight left') || combined.contains('slight left')) {
    return Icons.turn_slight_left_rounded;
  }
  if (mod.contains('slight right') || combined.contains('slight right')) {
    return Icons.turn_slight_right_rounded;
  }
  if (mod.contains('uturn') ||
      mod.contains('u-turn') ||
      combined.contains('u-turn')) {
    return Icons.u_turn_left_rounded;
  }
  if (mod.contains('left') ||
      combined.contains('left') ||
      combined.contains('links') ||
      combined.contains('gauche')) {
    return Icons.turn_left_rounded;
  }
  if (mod.contains('right') ||
      combined.contains('right') ||
      combined.contains('rechts') ||
      combined.contains('droite')) {
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
List<DriverNavLaneGuidance> driverNavLanesForBannerDisplay(
  List<DriverNavLaneGuidance> lanes, {
  bool? featureEnabled,
}) {
  final enabled = featureEnabled ?? driverNavLaneGuidanceFeatureEnabled;
  if (!enabled) return const <DriverNavLaneGuidance>[];
  if (lanes.isEmpty) return const <DriverNavLaneGuidance>[];
  return List<DriverNavLaneGuidance>.unmodifiable(lanes);
}
