import 'package:flutter/material.dart';

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

bool _bannerSecondarySuggestsHighway(String? raw) {
  final lower = (raw ?? '').trim().toLowerCase();
  if (lower.isEmpty) return false;
  const markers = <String>[
    'afrit',
    'exit',
    'sortie',
    'toward',
    'richting',
    'direction',
    'vers ',
    'hacia ',
  ];
  for (final marker in markers) {
    if (lower.contains(marker)) return true;
  }
  return false;
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
  if (_bannerSecondarySuggestsHighway(step.banner?.secondaryText)) return true;
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
  if (driverNavTypeIsArrival(type)) return Icons.flag_rounded;
  if (driverNavTypeIsRoundabout(type)) return Icons.roundabout_right_rounded;
  final combined = '${modifier ?? ''} $instruction'.toLowerCase();
  if (combined.contains('slight left')) return Icons.turn_slight_left_rounded;
  if (combined.contains('slight right')) return Icons.turn_slight_right_rounded;
  if (combined.contains('left') ||
      combined.contains('links') ||
      combined.contains('gauche')) {
    return Icons.turn_left_rounded;
  }
  if (combined.contains('right') ||
      combined.contains('rechts') ||
      combined.contains('droite')) {
    return Icons.turn_right_rounded;
  }
  if ((type ?? '').toLowerCase().contains('exit') ||
      combined.contains('exit') ||
      combined.contains('afrit')) {
    return Icons.call_split_rounded;
  }
  return Icons.straight_rounded;
}
