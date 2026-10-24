import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_route_parser.dart';
import 'package:fluxidi_tracking/navigation/nav_backend/driver_navigation_worker_client.dart';

void main() {
  for (final region in ['BE-VLG', 'BE-BRU', 'BE-WAL', 'NL']) {
    test(
      'own $region immutable route survives existing Worker conversion, guidance and banners',
      () async {
        final body = File(
          'test/navigation/fixtures/own-directions/$region.json',
        ).readAsStringSync();
        expect(body.contains('api.mapbox.com'), isFalse);
        expect(body.contains('mapbox://'), isFalse);
        final raw = jsonDecode(body) as Map<String, dynamic>,
            geometry = raw['geometry']['coordinates'] as List;
        expect(raw['source'], 'fluxidi-national');
        expect(raw['provider_source'], isNull);
        // Legacy v2 DTO is retained as a parser fixture, not as a current
        // authenticated route response (it predates metadata/lease binding).
        final result=NavigationWorkerRouteResult(distanceMeters:(raw['distance_m'] as num).toDouble(),durationSeconds:(raw['duration_s'] as num).toInt(),
          coords:[for(final p in geometry)DriverLonLat((p[0] as num).toDouble(),(p[1] as num).toDouble())],maneuvers:[],
          legs:[for(final leg in raw['legs'])Map<String,dynamic>.from(leg)],cache:'bypass');
        expect(result, isNotNull);
        expect(result.hasPreservedLegs, isTrue);
        final parsed = parseDriverDirectionsResponse(
          response: result.toMapboxDirectionsShape(),
          localizeInstruction: (s) => s,
          distanceAlongRouteForCoords: (_, __) => 0,
        );
        expect(parsed.coords.length, geometry.length);
        expect(parsed.distanceMeters, raw['distance_m']);
        expect(
          parsed.navSteps.length,
          (raw['legs'][0]['steps'] as List).length,
        );
        expect(parsed.navSteps.first.type, 'depart');
        expect(parsed.navSteps.last.type, 'arrive');
        expect(parsed.navSteps.every((s) => s.instruction.isNotEmpty), isTrue);
        expect(parsed.stepsWithBannerCount, parsed.navSteps.length);
        expect(parsed.stepsWithLaneGuidanceCount, 0);
        if (region == 'BE-WAL') {
          final roundabouts = parsed.navSteps
              .where((s) => s.type == 'roundabout')
              .toList();
          expect(roundabouts.length, 5);
          expect(roundabouts.map((s) => s.exitNumber), [
            '1',
            '2',
            '2',
            '2',
            '2',
          ]);
        }
      },
    );
  }
}
