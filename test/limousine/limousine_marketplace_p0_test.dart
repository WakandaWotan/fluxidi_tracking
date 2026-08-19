import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_entry.dart';
import 'package:fluxidi_tracking/limousine/limousine_marketplace_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_provider_eligibility.dart';
import 'package:fluxidi_tracking/limousine/limousine_service_capability.dart';

Map<String, dynamic> _validLimousineCompany({
  List<String> services = const ['limousine'],
  List<Map<String, dynamic>>? vehicles,
  bool isActive = true,
  bool profileEnabled = true,
  bool bookable = true,
  String publishedAt = '2026-08-17T10:00:00Z',
  Map<String, dynamic>? extra,
}) {
  return <String, dynamic>{
    'company_name': 'Coachline',
    'is_active': isActive,
    'bookable': bookable,
    'availability_status': isActive ? 'active' : 'inactive',
    'profile_enabled': profileEnabled,
    'published_at': publishedAt,
    'services': services,
    'vehicles':
        vehicles ??
        const [
          <String, dynamic>{
            'name': 'Fleet One',
            'category': 'limousine',
            'is_active': true,
          },
        ],
    ...?extra,
  };
}

(int, int) _webpCanvasSize(Uint8List bytes) {
  expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
  expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WEBP');
  final fourcc = String.fromCharCodes(bytes.sublist(12, 16));
  if (fourcc == 'VP8X') {
    final width = 1 + (bytes[24] | (bytes[25] << 8) | (bytes[26] << 16));
    final height = 1 + (bytes[27] | (bytes[28] << 8) | (bytes[29] << 16));
    return (width, height);
  }
  if (fourcc == 'VP8L') {
    final bits =
        bytes[21] | (bytes[22] << 8) | (bytes[23] << 16) | (bytes[24] << 24);
    return ((bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1);
  }
  if (fourcc == 'VP8 ') {
    for (var i = 20; i < bytes.length - 10; i++) {
      if (bytes[i] == 0x9d && bytes[i + 1] == 0x01 && bytes[i + 2] == 0x2a) {
        final width = bytes[i + 3] | (bytes[i + 4] << 8);
        final height = bytes[i + 5] | (bytes[i + 6] << 8);
        return (width & 0x3FFF, height & 0x3FFF);
      }
    }
  }
  fail('Unsupported WebP bitstream: $fourcc');
}

void main() {
  group('limousine asset contract', () {
    test(
      'hero webp exists, decodes, keeps source geometry, and is smaller',
      () {
        final asset = File(kLimousineMarketplaceHeroAsset);
        expect(asset.existsSync(), isTrue);
        final bytes = asset.readAsBytesSync();
        expect(bytes.length, greaterThan(32));
        expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
        expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WEBP');
        final size = _webpCanvasSize(Uint8List.fromList(bytes));
        expect(size.$1, 1927);
        expect(size.$2, 816);
        expect(bytes.length, lessThan(1765280));
        expect(bytes.length, lessThan(400 * 1024));

        final pubspec = File('pubspec.yaml').readAsStringSync();
        expect(pubspec.contains('- assets/fluxidi/'), isTrue);
        expect(
          pubspec.contains('customer_home_limousine_banner.webp'),
          isFalse,
          reason: 'directory registration already covers the banner',
        );
        expect(
          File('assets/fluxidi/limousine_marketplace_hero.webp').existsSync(),
          isFalse,
        );
        expect(
          Directory('assets/fluxidi').listSync().whereType<File>().any(
            (file) =>
                file.path.toLowerCase().endsWith('.png') &&
                file.path.toLowerCase().contains('limousine'),
          ),
          isFalse,
        );
      },
    );

    test('entry contract points at the production banner and stays gated', () {
      expect(
        LimousineCustomerEntryContract.visualAsset,
        kLimousineMarketplaceHeroAsset,
      );
      expect(
        LimousineCustomerEntryContract.publicServiceId,
        kLimousinePublicServiceId,
      );
      expect(LimousineCustomerEntryContract.isVisible, isFalse);
      expect(
        LimousineCustomerEntryContract.sharedEngineSeam,
        contains('CalculatorPage'),
      );
      expect(
        LimousineCustomerEntryContract.missingBackendContract,
        contains('GET /partners/nearby'),
      );
    });
  });

  group('limousine capability normalization', () {
    test('canonical and alias tokens normalize; taxi/airport do not', () {
      expect(normalizeLimousineServiceId('limousine'), 'limousine');
      expect(normalizeLimousineServiceId('Limousine Service'), 'limousine');
      expect(normalizeLimousineServiceId('limousine-service'), 'limousine');
      expect(normalizeLimousineServiceId('taxi_vvb'), isNull);
      expect(normalizeLimousineServiceId('airport_transfer'), isNull);
      expect(normalizeLimousineServiceId('airport'), isNull);
      expect(normalizeLimousineServiceId('passenger'), isNull);
      expect(normalizeLimousineServiceId('hourly'), isNull);
      expect(normalizeLimousineServiceId('premium'), isNull);
      expect(normalizeLimousineServiceId('Mercedes Limousine'), isNull);
    });

    test('missing capability fails closed', () {
      expect(
        partnerHasExplicitLimousineCapability(<String, dynamic>{}),
        isFalse,
      );
      expect(
        partnerHasExplicitLimousineCapability(<String, dynamic>{
          'services': <String>['taxi_vvb', 'airport_transfer'],
        }),
        isFalse,
      );
      expect(
        partnerHasExplicitLimousineCapability(<String, dynamic>{
          'limousine_service_enabled': false,
          'services': <String>['limousine'],
        }),
        isTrue,
      );
    });

    test('explicit services token or boolean enables capability', () {
      expect(
        partnerHasExplicitLimousineCapability(<String, dynamic>{
          'services': <String>['taxi_vvb', 'limousine'],
        }),
        isTrue,
      );
      expect(
        partnerHasExplicitLimousineCapability(<String, dynamic>{
          'limousine_service_enabled': true,
        }),
        isTrue,
      );
      expect(
        partnerHasExplicitLimousineCapability(<String, dynamic>{
          'capabilities': <String, dynamic>{'limousine': true},
        }),
        isTrue,
      );
    });
  });

  group('limousine provider eligibility', () {
    test('valid limousine company is included', () {
      final company = _validLimousineCompany();
      expect(isEligibleLimousineProvider(company), isTrue);
      expect(evaluateLimousineProviderEligibility(company).denial, isNull);
    });

    test('missing capability fails closed', () {
      final company = _validLimousineCompany(services: const ['taxi_vvb']);
      final result = evaluateLimousineProviderEligibility(company);
      expect(result.eligible, isFalse);
      expect(result.denial, LimousineEligibilityDenial.missingCapability);
    });

    test('inactive company is excluded', () {
      final company = _validLimousineCompany(isActive: false);
      final result = evaluateLimousineProviderEligibility(company);
      expect(result.eligible, isFalse);
      expect(result.denial, LimousineEligibilityDenial.companyInactive);
    });

    test('deleted or tombstoned company is excluded', () {
      final deleted = evaluateLimousineProviderEligibility(
        _validLimousineCompany(extra: const {'deleted': true}),
      );
      expect(deleted.eligible, isFalse);
      expect(deleted.denial, LimousineEligibilityDenial.companyDeleted);

      final tombstoned = evaluateLimousineProviderEligibility(
        _validLimousineCompany(extra: const {'tombstoned': true}),
      );
      expect(tombstoned.eligible, isFalse);
      expect(tombstoned.denial, LimousineEligibilityDenial.companyDeleted);
    });

    test('unpublished public profile is excluded', () {
      final company = _validLimousineCompany(
        profileEnabled: false,
        extra: const {'published_at': ''},
      );
      company['published_at'] = '';
      final result = evaluateLimousineProviderEligibility(company);
      expect(result.eligible, isFalse);
      expect(result.denial, LimousineEligibilityDenial.profileNotPublished);
    });

    test('no eligible active limousine vehicle/service is excluded', () {
      final noVehicles = evaluateLimousineProviderEligibility(
        _validLimousineCompany(vehicles: const []),
      );
      expect(noVehicles.eligible, isFalse);
      expect(noVehicles.denial, LimousineEligibilityDenial.noEligibleVehicle);

      final inactiveVehicle = evaluateLimousineProviderEligibility(
        _validLimousineCompany(
          vehicles: const [
            <String, dynamic>{
              'name': 'Stretch One',
              'category': 'limousine',
              'is_active': false,
            },
          ],
        ),
      );
      expect(inactiveVehicle.eligible, isFalse);
      expect(
        inactiveVehicle.denial,
        LimousineEligibilityDenial.noEligibleVehicle,
      );

      final premiumNameOnly = evaluateLimousineProviderEligibility(
        _validLimousineCompany(
          vehicles: const [
            <String, dynamic>{
              'name': 'Black Limousine',
              'brand_model': 'Mercedes S-Class Limousine',
              'category': 'Premium',
              'tierId': 'premium',
              'is_active': true,
            },
          ],
        ),
      );
      expect(premiumNameOnly.eligible, isFalse);
      expect(
        premiumNameOnly.denial,
        LimousineEligibilityDenial.noEligibleVehicle,
      );

      final missingVehicleKey = Map<String, dynamic>.from(
        _validLimousineCompany(),
      )..remove('vehicles');
      expect(isEligibleLimousineProvider(missingVehicleKey), isFalse);
    });

    test('taxi-only company is excluded from limousine results', () {
      final taxiOnly = _validLimousineCompany(
        services: const ['taxi_vvb', 'online_payments'],
        vehicles: const [
          <String, dynamic>{
            'name': 'Taxi 12',
            'category': 'Comfort',
            'tierId': 'premium',
            'is_active': true,
          },
        ],
      );
      expect(isEligibleLimousineProvider(taxiOnly), isFalse);
      expect(
        filterLimousineEligibleProviders(<Map<String, dynamic>>[
          taxiOnly,
          _validLimousineCompany(),
        ]),
        hasLength(1),
      );
    });

    test('historical rides never enable a company', () {
      final company = _validLimousineCompany(
        services: const ['taxi_vvb'],
        extra: const {
          'historical_services': <String>['limousine'],
          'past_rides': <String>['limousine'],
        },
      );
      expect(isEligibleLimousineProvider(company), isFalse);
    });

    test('FLX company codes are not a special allowlist', () {
      final flx = _validLimousineCompany(
        services: const ['taxi_vvb'],
        extra: const {'company_code': 'FLX-00021', 'company_id': 'FLX-00021'},
      );
      expect(isEligibleLimousineProvider(flx), isFalse);
    });

    test('market mismatch does not hide a published limousine provider', () {
      final company = _validLimousineCompany(
        extra: const {
          'coverage': <String, dynamic>{
            'primary_postcode': '9000',
            'postcodes': <String>['9000', '9050'],
            'country': 'BE',
          },
        },
      );
      expect(
        isEligibleLimousineProvider(
          company,
          request: const LimousineMarketRequest(
            postcode: '9000',
            countryCode: 'BE',
          ),
        ),
        isTrue,
      );
      expect(
        evaluateLimousineProviderEligibility(
          company,
          request: const LimousineMarketRequest(postcode: '1000'),
        ).eligible,
        isTrue,
      );
    });
  });

  group('existing taxi and airport capabilities stay unchanged', () {
    test('calculator enabledServices still has no limousine id', () {
      final source = File('lib/app_config.dart').readAsStringSync();
      final start = source.indexOf('enabledServices: <AppOption>[');
      final end = source.indexOf('enabledTiers: <AppOption>[');
      expect(start, greaterThan(0));
      expect(end, greaterThan(start));
      final window = source.substring(start, end);
      expect(window.contains("id: 'airport'"), isTrue);
      expect(window.contains("id: 'passenger'"), isTrue);
      expect(window.contains("id: 'limousine'"), isFalse);
    });

    test(
      'public catalog keeps taxi and airport and only appends limousine',
      () {
        final source = File(
          'lib/business_settings_page.dart',
        ).readAsStringSync();
        final start = source.indexOf(
          'static const List<String> _publicServiceCatalog',
        );
        final end = source.indexOf(
          'static const List<String> _publicPaymentOptionCatalog',
        );
        final window = source.substring(start, end);
        expect(
          window.indexOf("'taxi_vvb'"),
          lessThan(window.indexOf("'airport_transfer'")),
        );
        expect(window.contains("'airport_transfer'"), isTrue);
        expect(window.contains("kLimousinePublicServiceId"), isTrue);
        expect(
          window.indexOf("'online_payments'"),
          lessThan(window.indexOf('kLimousinePublicServiceId')),
        );
      },
    );

    test('airport nearby filter is still the only selectionMode filter', () {
      final source = File('lib/nearby_partners_page.dart').readAsStringSync();
      expect(source.contains('_airportServiceEnabledFromPartner'), isTrue);
      expect(source.contains('_limousineServiceEnabledFromPartner'), isFalse);
      expect(source.contains("token == 'airport_transfer'"), isTrue);
    });

    test('customer home does not show a live limousine card in P0', () {
      final source = File(
        'lib/main_parts/customer_home_page.dart',
      ).readAsStringSync();
      expect(source.contains('customer_home_airport_banner.webp'), isTrue);
      expect(source.contains('_openAirportFlow'), isTrue);
      expect(source.contains('_openHotelsPage'), isTrue);
      expect(source.contains('_openEventsPage'), isTrue);
      expect(
        source.contains('LimousineCustomerEntryContract.isVisible'),
        isTrue,
      );
      expect(LimousineCustomerEntryContract.isVisible, isFalse);
    });
  });

  group('limousine localization labels', () {
    test('book-a-limousine labels are present for NL/EN/FR/ES', () {
      expect(kLimousineBookLabel.nl, 'Boek een limousine');
      expect(kLimousineBookLabel.en, 'Book a limousine');
      expect(kLimousineBookLabel.fr, 'Réserver une limousine');
      expect(kLimousineBookLabel.es, 'Reservar una limusina');
      expect(limousineBookLabelFor(AppLanguage.nl), 'Boek een limousine');
      expect(limousineBookLabelFor(AppLanguage.en), 'Book a limousine');
      expect(limousineBookLabelFor(AppLanguage.fr), 'Réserver une limousine');
      expect(limousineBookLabelFor(AppLanguage.es), 'Reservar una limusina');
      expect(LimousineCustomerEntryContract.bookLabel.en, 'Book a limousine');
    });

    test('business settings and partner profile resolve the catalog label', () {
      expect(
        limousineCatalogLabelOrNull('limousine', AppLanguage.es),
        'Limusina',
      );
      expect(limousineCatalogLabelOrNull('taxi_vvb', AppLanguage.en), isNull);
      expect(
        limousineCatalogLabelOrNull('airport_transfer', AppLanguage.nl),
        isNull,
      );
      final settings = File(
        'lib/business_settings_page.dart',
      ).readAsStringSync();
      expect(
        settings.contains('limousinePublicServiceLabelFor(_lang)'),
        isTrue,
      );
      final profile = File(
        'lib/limousine/limousine_public_profile_page.dart',
      ).readAsStringSync();
      expect(profile.contains('buildLimousinePublicProfileData'), isTrue);
      expect(
        File(
          'lib/limousine/limousine_marketplace_labels.dart',
        ).readAsStringSync().contains('limousinePublicServiceLabelFor'),
        isTrue,
      );
    });
  });
}
