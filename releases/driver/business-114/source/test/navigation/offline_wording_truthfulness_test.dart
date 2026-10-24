// P0-FIELD-REPAIR-1 (C) — user-facing offline wording must stay truthful.
//
// The app can download BASEMAP TILES only. Route calculation, search, traffic
// and rerouting still require a network connection (see the documented scope
// in `lib/navigation/driver_offline_maps_service.dart`).
//
// During the field navigation freeze the driver reasonably expected the map to
// keep working because the entry point was labelled "Offline kaarten", which
// reads as full offline navigation. These are source-contract tests: they pin
// the truthful wording so a future edit cannot re-introduce a promise the app
// does not keep.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

File _libFile(String relativePath) {
  final file = File(relativePath);
  expect(file.existsSync(), isTrue, reason: 'missing source file $relativePath');
  return file;
}

const String _offlineMapsPage = 'lib/navigation/driver_offline_maps_page.dart';
const String _driverHome = 'lib/main_parts/driver_home_page_state.dart';

/// The approved truthful description (NL), as a single normalized line.
const String _approvedNlDescription =
    'Kaartweergave kan offline beschikbaar zijn. Routeberekening, zoeken, '
    'verkeersinformatie en herberekenen vereisen momenteel internet.';

/// Collapses Dart adjacent-string-literal concatenation and whitespace so a
/// multi-line source literal can be compared against the approved sentence.
String _normalizeSource(String source) => source
    .replaceAll(RegExp(r"'\s*\n\s*'"), '')
    .replaceAll(RegExp(r'\s+'), ' ');

void main() {
  group('offline entry points name tiles, not navigation', () {
    test('the offline screen title says "Offline kaarttegels"', () {
      final source = _libFile(_offlineMapsPage).readAsStringSync();
      expect(source, contains("nl: 'Offline kaarttegels'"));
      expect(source, contains("en: 'Offline map tiles'"));
    });

    test('the driver-home entry points say "Offline kaarttegels"', () {
      final source = _libFile(_driverHome).readAsStringSync();
      expect(
        RegExp("nl: 'Offline kaarttegels'").allMatches(source).length,
        greaterThanOrEqualTo(2),
        reason: 'both the compact nav chip and the cockpit rail must be truthful',
      );
    });

    test('no user-facing label still promises "Offline kaarten"', () {
      for (final path in <String>[_offlineMapsPage, _driverHome]) {
        final source = _libFile(path).readAsStringSync();
        expect(
          source,
          isNot(contains("nl: 'Offline kaarten'")),
          reason: '$path still promises full offline maps',
        );
        expect(
          source,
          isNot(contains("en: 'Offline maps'")),
          reason: '$path still promises full offline maps',
        );
      }
    });

    test('the downloaded-maps section is headed "Gedownloade kaarten"', () {
      final source = _libFile(_offlineMapsPage).readAsStringSync();
      expect(source, contains("nl: 'Gedownloade kaarten'"));
      expect(source, contains("en: 'Downloaded maps'"));
    });
  });

  group('the capability boundary is stated explicitly', () {
    test('the offline screen carries the approved NL description', () {
      final source = _normalizeSource(
        _libFile(_offlineMapsPage).readAsStringSync(),
      );
      expect(source, contains(_approvedNlDescription));
    });

    test('the route-corridor card carries the approved NL description', () {
      final source = _normalizeSource(_libFile(_driverHome).readAsStringSync());
      expect(source, contains(_approvedNlDescription));
    });

    test('the description names every online-only capability', () {
      final source = _normalizeSource(
        _libFile(_offlineMapsPage).readAsStringSync(),
      );
      for (final capability in <String>[
        'Routeberekening',
        'zoeken',
        'verkeersinformatie',
        'herberekenen',
      ]) {
        expect(
          source,
          contains(capability),
          reason: 'the wording must name "$capability" as online-only',
        );
      }
    });

    test('the English description mirrors the NL boundary', () {
      final source = _normalizeSource(
        _libFile(_offlineMapsPage).readAsStringSync(),
      );
      expect(
        source,
        contains(
          'Map display can be available offline. Route calculation, search, '
          'traffic information and rerouting currently require internet.',
        ),
      );
    });
  });

  group('no new offline capability was promised', () {
    test('the documented service scope still says routing needs network', () {
      final source = _libFile(
        'lib/navigation/driver_offline_maps_service.dart',
      ).readAsStringSync();
      expect(
        source.toLowerCase(),
        contains('offline'),
        reason: 'the service scope documentation must remain present',
      );
      // This task deliberately ships no offline routing engine; the honest
      // scope note must therefore stay in place.
      expect(
        source.toLowerCase().contains('still require network') ||
            source.toLowerCase().contains('require network'),
        isTrue,
        reason: 'the "routing still requires network" scope note is required',
      );
    });
  });
}
