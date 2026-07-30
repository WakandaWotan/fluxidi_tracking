// RELEASE-P0-DEMAND-RADAR-CONSISTENCY
//
// Regional demand radar must return the same aggregated count for the same
// normalized region + radius + snapshot, and must never paint backend errors
// as a numeric `0+`.
//
// Run:
//   flutter test test/business/regional_demand_consistency_p0_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluxidi_tracking/business/regional_demand_consistency.dart';

String _read(String relativePath) => File(relativePath).readAsStringSync();

void main() {
  group('postcode / region normalization', () {
    test('9688 Schorisse and 9688 collapse to the same key', () {
      expect(normalizeDemandRadarPostcode('9688 Schorisse'), '9688');
      expect(normalizeDemandRadarPostcode('9688'), '9688');
      expect(normalizeDemandRadarPostcode('B-9688'), '9688');
      expect(normalizeDemandRadarPostcode(' 9688 '), '9688');
    });

    test('two companies with same region normalize identically', () {
      final a = normalizeDemandRadarPostcode('9688 Schorisse');
      final b = normalizeDemandRadarPostcode('9688');
      expect(a, b);
      expect(
        demandRadarRegionCacheKey(
          country: 'BE',
          postcode: a,
          radiusKm: 30,
        ),
        demandRadarRegionCacheKey(
          country: 'BE',
          postcode: b,
          radiusKm: 30,
        ),
      );
    });
  });

  group('hero total: true zero vs unavailable', () {
    test('successful zero response becomes 0+', () {
      final hero = decideDemandRadarHeroTotal(
        primaryPostcode: '9688',
        rows: const [
          (postcode: '9688', count: 0, unavailable: false),
        ],
      );
      expect(hero.available, isTrue);
      expect(hero.count, 0);
      expect(hero.displayCountOrEmpty(), '0+');
    });

    test('backend error is not shown as 0+', () {
      final hero = decideDemandRadarHeroTotal(
        primaryPostcode: '9688',
        rows: const [
          (postcode: '9688', count: 0, unavailable: true),
        ],
      );
      expect(hero.available, isFalse);
      expect(hero.displayCountOrEmpty(), isEmpty);
      expect(
        demandRadarUnavailableLabel('nl'),
        'Gegevens momenteel niet beschikbaar',
      );
      expect(
        demandRadarUnavailableLabel('en'),
        'Data currently unavailable',
      );
      expect(
        demandRadarUnavailableLabel('fr'),
        'Données momentanément indisponibles',
      );
      expect(
        demandRadarUnavailableLabel('es'),
        'Datos no disponibles temporalmente',
      );
    });

    test('successful 3 response becomes 3+', () {
      final hero = decideDemandRadarHeroTotal(
        primaryPostcode: '9688',
        rows: const [
          (postcode: '9688', count: 3, unavailable: false),
          (postcode: '9700', count: 10, unavailable: false),
        ],
      );
      // Hero uses PRIMARY region only — served postcodes must not inflate it.
      expect(hero.available, isTrue);
      expect(hero.count, 3);
      expect(hero.displayCountOrEmpty(), '3+');
    });

    test('two company sessions with same primary snapshot get same count', () {
      const rows = [
        (postcode: '9688', count: 3, unavailable: false),
        (postcode: '9700', count: 1, unavailable: false),
      ];
      final companyA = decideDemandRadarHeroTotal(
        primaryPostcode: '9688 Schorisse',
        rows: rows,
      );
      final companyB = decideDemandRadarHeroTotal(
        primaryPostcode: '9688',
        rows: rows,
      );
      expect(companyA.count, companyB.count);
      expect(companyA.displayCountOrEmpty(), companyB.displayCountOrEmpty());
    });
  });

  group('language and device do not affect counts', () {
    test('NL vs EN only changes unavailable labels, not numeric counts', () {
      final hero = decideDemandRadarHeroTotal(
        primaryPostcode: '9688',
        rows: const [
          (postcode: '9688', count: 3, unavailable: false),
        ],
      );
      expect(hero.displayCountOrEmpty(), '3+');
      // Labels differ by language; counts do not.
      expect(
        demandRadarUnavailableLabel('nl') != demandRadarUnavailableLabel('en'),
        isTrue,
      );
      expect(
        demandRadarRegionCacheKey(
          country: 'BE',
          postcode: '9688',
          radiusKm: 30,
        ).contains('nl'),
        isFalse,
      );
      expect(
        demandRadarRegionCacheKey(
          country: 'BE',
          postcode: '9688',
          radiusKm: 30,
        ).contains('en'),
        isFalse,
      );
      expect(
        demandRadarRegionCacheKey(
          country: 'BE',
          postcode: '9688',
          radiusKm: 30,
        ).contains('phone'),
        isFalse,
      );
      expect(
        demandRadarRegionCacheKey(
          country: 'BE',
          postcode: '9688',
          radiusKm: 30,
        ).contains('tablet'),
        isFalse,
      );
    });

    test('cache key excludes company and language', () {
      final key = demandRadarRegionCacheKey(
        country: 'BE',
        postcode: '9688',
        radiusKm: 30,
      );
      expect(key, 'region_interest_v1|BE|9688|r30|live');
      expect(key.contains('company'), isFalse);
      expect(key.contains('tenant'), isFalse);
    });
  });

  group('row display and diagnostics', () {
    test('row failure never renders 0+', () {
      expect(
        demandRadarRowDisplayCount(
          unavailable: true,
          count: 0,
          languageCode: 'en',
        ),
        'Data currently unavailable',
      );
      expect(
        demandRadarRowDisplayCount(
          unavailable: false,
          count: 0,
          languageCode: 'en',
        ),
        '0+',
      );
    });

    test('diagnostics mask tenant and postcode without leaking PII', () {
      final line = formatDemandRadarDiag(
        correlationId: 'dr_1',
        country: 'BE',
        postcode: '9688',
        radiusKm: 30,
        httpStatus: 200,
        source: DemandRadarCountSource.network,
        cacheHit: false,
        companyId: 'company-secret-abc',
      );
      expect(line.contains('company-secret-abc'), isFalse);
      expect(line.contains('9688'), isFalse);
      expect(line.contains('corr=dr_1'), isTrue);
      expect(line.contains('source=network'), isTrue);
      expect(line.contains('tenant=t_'), isTrue);
    });
  });

  group('source wiring guards', () {
    test('business radar page no longer paints errors as 0+', () {
      final source = _read(
        'lib/main_parts/business_regional_demand_page_state.dart',
      );
      expect(source.contains("displayCount: '0+'"), isFalse);
      expect(source.contains('decideDemandRadarHeroTotal'), isTrue);
      expect(source.contains('_loadGeneration'), isTrue);
      expect(source.contains('demandRadarUnavailableLabel'), isTrue);
      expect(source.contains('normalizeDemandRadarPostcode'), isTrue);
    });

    test('worker postcode normalize extracts BE 4-digit block', () {
      final worker = _read('workers/booking/fluxidi_booking_worker.js');
      expect(worker.contains(r'match(/(\d{4})/)'), isTrue);
      expect(
        worker.contains(
          'function normalizeRegionInterestPostcode(value) {\n'
          '  return safeStr(value, 24).toUpperCase().replace(/\\s+/g, "");\n'
          '}',
        ),
        isFalse,
      );
    });
  });
}
