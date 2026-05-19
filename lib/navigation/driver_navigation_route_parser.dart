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

  const DriverRouteParseResult({
    required this.coords,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.navSteps,
  });
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
        ),
      );
    }
  }

  return DriverRouteParseResult(
    coords: out,
    distanceMeters: distance,
    durationSeconds: duration,
    navSteps: navSteps,
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
