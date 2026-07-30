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

  group('radar country source (locale leak guard)', () {
    test('locale-shaped values resolve to the region, never the language', () {
      expect(parseDemandRadarCountryCode('nl_BE'), 'BE');
      expect(parseDemandRadarCountryCode('fr-BE'), 'BE');
      expect(parseDemandRadarCountryCode('nl_BE_VLG'), 'BE');
      expect(parseDemandRadarCountryCode('fr_FR'), 'FR');
      expect(parseDemandRadarCountryCode(''), '');
      expect(parseDemandRadarCountryCode('  '), '');
    });

    test('country names and ISO2 codes resolve, junk does not', () {
      expect(parseDemandRadarCountryCode('België'), 'BE');
      expect(parseDemandRadarCountryCode('Belgique'), 'BE');
      expect(parseDemandRadarCountryCode('BE'), 'BE');
      expect(parseDemandRadarCountryCode('Nederland'), 'NL');
      expect(parseDemandRadarCountryCode('España'), 'ES');
      expect(parseDemandRadarCountryCode('9688'), '');
      expect(parseDemandRadarCountryCode('Onbekend'), '');
      expect(parseDemandRadarCountryCode('XX'), '');
      expect(parseDemandRadarCountryCode('zz_ZZ'), '');
    });

    test('stored business country wins over the company session code', () {
      final resolved = resolveDemandRadarCountry(
        businessProfileCountry: 'BE',
        companySessionCountryCode: 'NL',
      );
      expect(resolved.country, 'BE');
      expect(resolved.source, DemandRadarCountrySource.businessProfile);
    });

    test('session country is used only when the profile has none', () {
      final resolved = resolveDemandRadarCountry(
        businessProfileCountry: '',
        companySessionCountryCode: 'NL',
      );
      expect(resolved.country, 'NL');
      expect(resolved.source, DemandRadarCountrySource.companySession);
    });

    test('missing or invalid country is unavailable, never guessed', () {
      final missing = resolveDemandRadarCountry(
        businessProfileCountry: '',
        companySessionCountryCode: '',
      );
      expect(missing.country, isEmpty);
      expect(missing.source, DemandRadarCountrySource.none);

      final invalid = resolveDemandRadarCountry(
        businessProfileCountry: 'Onbekend',
        companySessionCountryCode: 'XX',
      );
      expect(invalid.country, isEmpty);
      expect(invalid.source, DemandRadarCountrySource.none);
    });

    test('app language never changes the radar country or cache key', () {
      const stored = 'BE';
      for (final language in <String>['nl', 'fr', 'en', 'es']) {
        final resolved = resolveDemandRadarCountry(
          businessProfileCountry: stored,
          companySessionCountryCode: language,
        );
        expect(resolved.country, 'BE', reason: 'language $language');
        expect(
          demandRadarRegionCacheKey(
            country: resolved.country,
            postcode: '9688 Schorisse',
            radiusKm: 30,
          ),
          'region_interest_v1|BE|9688|r30|live',
          reason: 'language $language',
        );
      }
    });

    test('a Dutch company keeps NL with a Dutch postcode', () {
      final resolved = resolveDemandRadarCountry(
        businessProfileCountry: 'Nederland',
        companySessionCountryCode: '',
      );
      expect(resolved.country, 'NL');
      expect(
        demandRadarRegionCacheKey(
          country: resolved.country,
          postcode: '1012 AB',
          radiusKm: 30,
        ),
        'region_interest_v1|NL|1012|r30|live',
      );
    });

    test('cache key marks an absent country instead of defaulting to BE', () {
      expect(
        demandRadarRegionCacheKey(
          country: '',
          postcode: '9688',
          radiusKm: 30,
        ),
        'region_interest_v1|none|9688|r30|live',
      );
    });

    test('radar page resolves country from stored company data only', () {
      final source = _read(
        'lib/main_parts/business_regional_demand_page_state.dart',
      );
      expect(source.contains('resolveDemandRadarCountry'), isTrue);
      expect(source.contains('businessProfileCountry: backend.country'), isTrue);
      expect(source.contains('country.isNotEmpty && limitedPostcodes'), isTrue);
      expect(source.contains('currentLanguageCode)'), isTrue);
      expect(
        source.contains('_normalizeCountry(currentLanguageCode)'),
        isFalse,
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
