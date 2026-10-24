import 'driver_navigation_models.dart';

typedef DriverDistanceAlongRouteForCoords =
    double Function(List<DriverLonLat> routeCoords, DriverLonLat point);
typedef DriverInstructionLocalizer = String Function(String raw);
typedef DriverRouteParserTranslate =
    String Function({
      required String nl,
      required String en,
      required String fr,
      required String es,
    });

class DriverRouteParseResult {
  final List<DriverLonLat> coords;
  final double distanceMeters;
  final int durationSeconds;
  final List<DriverNavStep> navSteps;
  final int stepsWithBannerCount;
  final int stepsWithLaneGuidanceCount;

  const DriverRouteParseResult({
    required this.coords,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.navSteps,
    this.stepsWithBannerCount = 0,
    this.stepsWithLaneGuidanceCount = 0,
  });
}

String? _trimmedString(dynamic raw) {
  if (raw == null) return null;
  final text = raw.toString().trim();
  return text.isEmpty ? null : text;
}

String? _bannerComponentText(dynamic raw) {
  if (raw is Map<String, dynamic>) {
    final direct = _trimmedString(raw['text']);
    if (direct != null) return direct;
    final components = raw['components'];
    if (components is List<dynamic>) {
      final parts = <String>[];
      for (final component in components) {
        if (component is! Map<String, dynamic>) continue;
        final text = _trimmedString(component['text']);
        if (text != null) parts.add(text);
      }
      if (parts.isNotEmpty) return parts.join(' ').trim();
    }
    return null;
  }
  return _trimmedString(raw);
}

double? _parseBannerDistanceAlongGeometry(Map<String, dynamic> banner) {
  final raw =
      banner['distanceAlongGeometry'] ?? banner['distance_along_geometry'];
  if (raw is num) {
    final value = raw.toDouble();
    if (value.isFinite && value >= 0) return value;
    return null;
  }
  if (raw is String) {
    final value = double.tryParse(raw.trim());
    if (value != null && value.isFinite && value >= 0) return value;
  }
  return null;
}

List<String> _parseBannerDirections(dynamic raw) {
  if (raw is! List<dynamic>) return const <String>[];
  final out = <String>[];
  for (final item in raw) {
    final text = _trimmedString(item);
    if (text != null) out.add(text);
  }
  return out;
}

DriverNavBannerComponent? _parseBannerComponent(dynamic raw) {
  if (raw is! Map<String, dynamic>) return null;
  final text = _trimmedString(raw['text']) ?? '';
  final type = _trimmedString(raw['type']);
  final imageBaseURL = _trimmedString(
    raw['imageBaseURL'] ?? raw['image_base_url'],
  );
  final abbr = _trimmedString(raw['abbr']);
  final abbrPriorityRaw = raw['abbr_priority'] ?? raw['abbrPriority'];
  final abbrPriority = abbrPriorityRaw is num ? abbrPriorityRaw.toInt() : null;
  final directions = _parseBannerDirections(raw['directions']);
  final activeRaw = raw['active'];
  final active = activeRaw is bool ? activeRaw : null;
  final activeDirection = _trimmedString(
    raw['active_direction'] ?? raw['activeDirection'],
  );
  // Skip completely empty components (no text, type, lanes, or shield URL).
  if (text.isEmpty &&
      type == null &&
      imageBaseURL == null &&
      abbr == null &&
      directions.isEmpty &&
      active == null &&
      activeDirection == null) {
    return null;
  }
  return DriverNavBannerComponent(
    type: type,
    text: text,
    imageBaseURL: imageBaseURL,
    abbr: abbr,
    abbrPriority: abbrPriority,
    directions: directions,
    active: active,
    activeDirection: activeDirection,
  );
}

DriverNavBannerView? _parseBannerView(dynamic raw) {
  if (raw == null) return null;
  if (raw is String) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    return DriverNavBannerView(text: text);
  }
  if (raw is! Map<String, dynamic>) return null;
  final text = _trimmedString(raw['text']);
  final componentsRaw = raw['components'];
  final components = <DriverNavBannerComponent>[];
  if (componentsRaw is List<dynamic>) {
    for (final item in componentsRaw) {
      final component = _parseBannerComponent(item);
      if (component != null) components.add(component);
    }
  }
  if ((text == null || text.isEmpty) && components.isEmpty) return null;
  return DriverNavBannerView(
    text: text,
    type: _trimmedString(raw['type']),
    modifier: _trimmedString(raw['modifier']),
    degrees: _finiteDouble(raw['degrees']),
    components: components,
  );
}

/// Numeric guidance values are only kept when they are real finite numbers.
double? _finiteDouble(dynamic raw) {
  final value = raw is num ? raw.toDouble() : double.tryParse('$raw');
  if (value == null || !value.isFinite) return null;
  return value;
}

/// NAV-SIGNAL-P1: parse every usable banner stage; skip malformed entries.
List<DriverNavBannerStage> _parseStepBannerInstructions(
  Map<String, dynamic> step,
) {
  final bannersAny = step['bannerInstructions'] ?? step['banner_instructions'];
  if (bannersAny is! List<dynamic> || bannersAny.isEmpty) {
    return const <DriverNavBannerStage>[];
  }

  final out = <DriverNavBannerStage>[];
  for (var i = 0; i < bannersAny.length; i++) {
    final bannerAny = bannersAny[i];
    if (bannerAny is! Map<String, dynamic>) continue;
    final distance = _parseBannerDistanceAlongGeometry(bannerAny);
    if (distance == null) continue;
    final primary = _parseBannerView(bannerAny['primary']);
    final secondary = _parseBannerView(bannerAny['secondary']);
    final sub = _parseBannerView(bannerAny['sub']);
    // A stage must have usable primary display text (no blank primary banner).
    if (primary == null || !primary.hasDisplayText) continue;
    out.add(
      DriverNavBannerStage(
        sourceIndex: i,
        distanceAlongGeometry: distance,
        primary: primary,
        secondary: secondary,
        sub: sub,
      ),
    );
  }
  return out;
}

DriverNavBannerInstruction? _legacyBannerFromStages(
  List<DriverNavBannerStage> stages,
) {
  for (final stage in stages) {
    final legacy = stage.asLegacyInstruction;
    if (legacy.hasContent) return legacy;
  }
  return null;
}

String? _parseExitNumber(Map<String, dynamic> maneuver) {
  final exit = maneuver['exit'];
  if (exit == null) return null;
  return _trimmedString(exit);
}

String? _parseDestinationText(dynamic raw) {
  if (raw is! List<dynamic> || raw.isEmpty) return null;
  final parts = <String>[];
  for (final item in raw) {
    if (item is String) {
      final text = item.trim();
      if (text.isNotEmpty) parts.add(text);
      continue;
    }
    if (item is Map<String, dynamic>) {
      final text = _trimmedString(item['name'] ?? item['text']);
      if (text != null) parts.add(text);
    }
  }
  if (parts.isEmpty) return null;
  return parts.join(' / ');
}

List<String> _parseLaneIndications(dynamic raw) {
  if (raw is! List<dynamic>) return const <String>[];
  final out = <String>[];
  for (final item in raw) {
    final text = _trimmedString(item);
    if (text != null) out.add(text);
  }
  return out;
}

List<double> _parseIntersectionBearings(dynamic raw) {
  if (raw is! List<dynamic>) return const <double>[];
  final out = <double>[];
  for (final item in raw) {
    if (item is num && item.isFinite) out.add(item.toDouble());
  }
  return out;
}

List<bool> _parseIntersectionEntry(dynamic raw) {
  if (raw is! List<dynamic>) return const <bool>[];
  final out = <bool>[];
  for (final item in raw) {
    if (item is bool) out.add(item);
  }
  return out;
}

List<String> _parseIntersectionClasses(dynamic raw) {
  if (raw is! List<dynamic>) return const <String>[];
  final out = <String>[];
  for (final item in raw) {
    final text = _trimmedString(item);
    if (text != null) out.add(text);
  }
  return out;
}

DriverNavLaneGuidance? _parseIntersectionLane(dynamic raw) {
  if (raw is! Map<String, dynamic>) return null;
  final indications = _parseLaneIndications(raw['indications']);
  final validRaw = raw['valid'];
  final activeRaw = raw['active'];
  final valid = validRaw is bool ? validRaw : null;
  final active = activeRaw is bool ? activeRaw : null;
  var validIndication = _trimmedString(
    raw['valid_indication'] ?? raw['validIndication'],
  );
  // Keep valid_indication only when it appears in indications.
  if (validIndication != null) {
    final lower = validIndication.toLowerCase();
    final matches = indications.any((i) => i.toLowerCase() == lower);
    if (!matches) validIndication = null;
  }
  if (indications.isEmpty &&
      valid == null &&
      active == null &&
      validIndication == null) {
    return null;
  }
  return DriverNavLaneGuidance(
    indications: indications,
    valid: valid,
    active: active,
    validIndication: validIndication,
  );
}

/// NAV-SIGNAL-P2B: preserve each intersection lane group independently.
List<DriverNavIntersection> _parseStepIntersections(Map<String, dynamic> step) {
  final intersectionsAny = step['intersections'];
  if (intersectionsAny is! List<dynamic>) {
    return const <DriverNavIntersection>[];
  }

  final out = <DriverNavIntersection>[];
  for (var i = 0; i < intersectionsAny.length; i++) {
    final intersectionAny = intersectionsAny[i];
    if (intersectionAny is! Map<String, dynamic>) continue;
    final lanesAny = intersectionAny['lanes'];
    final lanes = <DriverNavLaneGuidance>[];
    if (lanesAny is List<dynamic>) {
      for (final laneAny in lanesAny) {
        final lane = _parseIntersectionLane(laneAny);
        if (lane != null) lanes.add(lane);
      }
    }
    final inRaw = intersectionAny['in'] ?? intersectionAny['inIndex'];
    final outRaw = intersectionAny['out'] ?? intersectionAny['outIndex'];
    out.add(
      DriverNavIntersection(
        sourceIndex: i,
        lanes: lanes,
        bearings: _parseIntersectionBearings(intersectionAny['bearings']),
        entry: _parseIntersectionEntry(intersectionAny['entry']),
        inIndex: inRaw is num ? inRaw.toInt() : null,
        outIndex: outRaw is num ? outRaw.toInt() : null,
        classes: _parseIntersectionClasses(intersectionAny['classes']),
      ),
    );
  }
  return out;
}

DriverRouteParseResult parseDriverDirectionsResponse({
  required Map<String, dynamic> response,
  required DriverInstructionLocalizer localizeInstruction,
  required DriverDistanceAlongRouteForCoords distanceAlongRouteForCoords,
}) {
  final routes = (response['routes'] as List<dynamic>? ?? []);
  if (routes.isEmpty) throw Exception('No route returned.');
  final r0 = routes.first as Map<String, dynamic>;
  final distance = (r0['distance'] as num?)?.toDouble() ?? 0.0;
  final duration = (r0['duration'] as num?)?.toInt() ?? 0;
  final geom = (r0['geometry'] as Map<String, dynamic>?) ?? {};
  final line = (geom['coordinates'] as List<dynamic>? ?? []);
  final out = <DriverLonLat>[];
  for (final c in line) {
    final pair = c as List<dynamic>;
    out.add(
      DriverLonLat((pair[0] as num).toDouble(), (pair[1] as num).toDouble()),
    );
  }
  final navSteps = <DriverNavStep>[];
  var stepsWithBannerCount = 0;
  var stepsWithLaneGuidanceCount = 0;
  final legs = (r0['legs'] as List<dynamic>? ?? const <dynamic>[]);
  for (final legAny in legs) {
    final leg = (legAny is Map<String, dynamic>) ? legAny : <String, dynamic>{};
    final steps = (leg['steps'] as List<dynamic>? ?? const <dynamic>[]);
    for (final stepAny in steps) {
      final step = (stepAny is Map<String, dynamic>)
          ? stepAny
          : <String, dynamic>{};
      final maneuver = (step['maneuver'] is Map<String, dynamic>)
          ? (step['maneuver'] as Map<String, dynamic>)
          : <String, dynamic>{};
      final loc = (maneuver['location'] as List<dynamic>? ?? const <dynamic>[]);
      if (loc.length < 2) continue;
      final lon = (loc[0] as num?)?.toDouble();
      final lat = (loc[1] as num?)?.toDouble();
      if (lat == null || lon == null) continue;
      final rawInstruction = (maneuver['instruction'] ?? '').toString().trim();
      final instruction = localizeInstruction(rawInstruction);
      final street = (step['name'] ?? '').toString().trim();
      final type = (maneuver['type'] ?? '').toString().trim();
      final modifier = (maneuver['modifier'] ?? '').toString().trim();
      final stepDistance = (step['distance'] as num?)?.toDouble();
      final stepDuration = (step['duration'] as num?)?.toInt();
      final bannerInstructions = _parseStepBannerInstructions(step);
      final banner = _legacyBannerFromStages(bannerInstructions);
      final exitNumber = _parseExitNumber(maneuver);
      final destinationText = _parseDestinationText(step['destinations']);
      final roadRef = _trimmedString(step['ref']);
      final drivingSide = _trimmedString(
        step['driving_side'] ?? step['drivingSide'],
      );
      final intersections = _parseStepIntersections(step);
      final hasLaneGroup = intersections.any((i) => i.hasLanes);
      if (bannerInstructions.isNotEmpty) stepsWithBannerCount += 1;
      if (hasLaneGroup) stepsWithLaneGuidanceCount += 1;
      if (instruction.isEmpty && street.isEmpty) continue;
      navSteps.add(
        DriverNavStep(
          lat: lat,
          lon: lon,
          instruction: instruction,
          street: street,
          type: type,
          modifier: modifier,
          distanceAlongRouteM: distanceAlongRouteForCoords(
            out,
            DriverLonLat(lon, lat),
          ),
          distanceM: stepDistance,
          durationSec: stepDuration,
          bearingBefore: _finiteDouble(
            maneuver['bearing_before'] ?? maneuver['bearingBefore'],
          ),
          bearingAfter: _finiteDouble(
            maneuver['bearing_after'] ?? maneuver['bearingAfter'],
          ),
          banner: banner,
          bannerInstructions: bannerInstructions,
          intersections: intersections,
          exitNumber: exitNumber,
          destinationText: destinationText,
          roadRef: roadRef,
          drivingSide: drivingSide,
          // Legacy DriverNavStep.lanes stays at its empty default — never concat.
        ),
      );
    }
  }

  return DriverRouteParseResult(
    coords: out,
    distanceMeters: distance,
    durationSeconds: duration,
    navSteps: navSteps,
    stepsWithBannerCount: stepsWithBannerCount,
    stepsWithLaneGuidanceCount: stepsWithLaneGuidanceCount,
  );
}

String localizeDriverNavInstructionMvp({
  required String raw,
  required String languageCode,
  required DriverRouteParserTranslate tr,
}) {
  if (raw.isEmpty) return raw;
  final lang = languageCode.toLowerCase().trim();
  if (lang == 'en') return raw;
  final lower = raw.toLowerCase();

  if (lower.contains('your destination is on the left')) {
    return tr(
      nl: 'Je bestemming bevindt zich links',
      en: 'Your destination is on the left',
      fr: 'Votre destination se trouve sur la gauche',
      es: 'Tu destino está a la izquierda',
    );
  }
  if (lower.contains('your destination is on the right')) {
    return tr(
      nl: 'Je bestemming bevindt zich rechts',
      en: 'Your destination is on the right',
      fr: 'Votre destination se trouve sur la droite',
      es: 'Tu destino está a la derecha',
    );
  }
  if (lower.startsWith('turn left') || lower.contains(' turn left')) {
    return tr(
      nl: 'Sla linksaf',
      en: 'Turn left',
      fr: 'Tournez à gauche',
      es: 'Gira a la izquierda',
    );
  }
  if (lower.startsWith('turn right') || lower.contains(' turn right')) {
    return tr(
      nl: 'Sla rechtsaf',
      en: 'Turn right',
      fr: 'Tournez à droite',
      es: 'Gira a la derecha',
    );
  }
  if (lower.startsWith('continue') || lower.contains(' continue')) {
    return tr(
      nl: 'Rijd rechtdoor',
      en: 'Continue',
      fr: 'Continuez',
      es: 'Continúa',
    );
  }
  return raw;
}
