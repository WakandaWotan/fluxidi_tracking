import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_entry.dart';
import 'package:fluxidi_tracking/limousine/limousine_offers.dart';

VehicleProfile _vehicle({
  String id = 'vh_1',
  bool isActive = true,
  String serviceCategory = 'limousine',
  String serviceClassId = 'executive_sedan',
  String? publicPhotoUrl = 'https://cdn.example.com/v1.jpg',
}) {
  return VehicleProfile(
    id: id,
    vehicleName: 'Fleet One',
    brandModel: 'Mercedes S-Class',
    licensePlate: '1-ABC-123',
    exploitationLicenseNumber: 'EXP-7',
    vehicleRegistrationNumber: 'REG-9',
    color: 'Black',
    passengerCapacity: 3,
    luggageCapacity: 2,
    tierId: 'premium',
    isActive: isActive,
    driverId: 'drv_1',
    primaryPhotoRef: 'local/secret.png',
    galleryPhotoRefs: const <String>[],
    publicPhotoUrl: publicPhotoUrl,
    serviceCategory: serviceCategory,
    serviceClassId: serviceClassId,
  );
}

Map<String, dynamic> _offer({Map<String, dynamic> overrides = const {}}) {
  return <String, dynamic>{
    'offer_id': 'off_full',
    'enabled': true,
    'published': true,
    'target_type': LimousineOfferTarget.vehicle,
    'vehicle_id': 'vh_1',
    'service_class_id': 'executive_sedan',
    'price_presentation': LimousinePricePresentation.exactFixed,
    'currency': 'EUR',
    'journey_types': <String>['airport_transfer', 'hourly_package'],
    'title': {
      'nl': 'Executive',
      'en': 'Executive',
      'fr': 'Exécutive',
      'es': 'Ejecutiva',
    },
    'description': {'nl': 'NL', 'en': 'EN', 'fr': 'FR', 'es': 'ES'},
    'important_information': {
      'nl': 'NLi',
      'en': 'ENi',
      'fr': 'FRi',
      'es': 'ESi',
    },
    'fixed_rules': <Map<String, dynamic>>[
      {
        'rule_id': 'r_bru',
        'enabled': true,
        'journey_type': 'airport_transfer',
        'direction': 'to_airport',
        'airport_iata': 'BRU',
        'zone_type': 'postcode',
        'zone_value': '9000',
        'amount_cents': 18000,
        'currency': 'EUR',
      },
    ],
    'hourly': {
      'enabled': true,
      'first_hour_cents': 12000,
      'additional_hour_cents': 9000,
      'minimum_duration_minutes': 180,
      'maximum_duration_minutes': 600,
      'package_duration_minutes': 240,
      'package_amount_cents': 36000,
      'currency': 'EUR',
    },
    'distance_time': {
      'enabled': true,
      'base_incl_vat_cents': 5000,
      'per_km_incl_vat_cents': 250,
      'per_minute_incl_vat_cents': 120,
      'minimum_incl_vat_cents': 9000,
      'currency': 'EUR',
    },
    'mobilisation': {
      'method': LimousineMobilisationMethod.fixedFee,
      'outbound_charged': true,
      'fee_cents': 4000,
      'currency': 'EUR',
      'disclosure': {'nl': 'NLd', 'en': 'ENd', 'fr': 'FRd', 'es': 'ESd'},
      'operating_base_address': 'Geheimestraat 1, 9000 Gent',
    },
    'included_services': <Map<String, dynamic>>[
      {
        'item_id': 'water',
        'label': {'nl': 'Water', 'en': 'Water', 'fr': 'Eau', 'es': 'Agua'},
        'active': true,
      },
    ],
    'paid_extras': <Map<String, dynamic>>[
      {
        'extra_id': 'wait',
        'label': {
          'nl': 'Wachttijd',
          'en': 'Waiting',
          'fr': 'Attente',
          'es': 'Espera',
        },
        'amount_cents': 2500,
        'currency': 'EUR',
        'active': true,
        'public': true,
      },
    ],
    'source_revision': 4,
    ...overrides,
  };
}

void main() {
  final vehicles = <VehicleProfile>[
    _vehicle(),
    _vehicle(id: 'vh_inactive', isActive: false),
    _vehicle(id: 'vh_taxi', serviceCategory: '', serviceClassId: ''),
  ];
  const classIds = <String>['executive_sedan', 'business_van'];

  List<Map<String, dynamic>> project(List<Map<String, dynamic>> offers) {
    return buildSafePublicLimousineOffers(
      offers,
      eligible: true,
      vehicles: vehicles,
      knownClassIds: classIds,
      readiness: true,
    );
  }

  group('editor completeness (source contract)', () {
    final editor = File(
      'lib/limousine/limousine_offer_editor.dart',
    ).readAsStringSync();

    test('every required sub-editor exists', () {
      for (final marker in const [
        '_fixedRulesEditor',
        '_includedServicesEditor',
        '_paidExtrasEditor',
        '_localizedMatrix',
        'maximum_duration_minutes',
        'package_amount_cents',
        'excess_hour_cents',
        'per_minute_incl_vat_cents',
        'included_distance_km',
        'operating_base_address',
        'active_from_ms',
        'radius_km',
        'airport_iata',
      ]) {
        expect(editor.contains(marker), isTrue, reason: marker);
      }
    });

    test('settings page delegates to the complete editor', () {
      final settings = File(
        'lib/business_settings_page.dart',
      ).readAsStringSync();
      expect(settings.contains('LimousineOfferEditorDialog('), isTrue);
      // The old active-language-only inline dialog is gone.
      expect(settings.contains('_langKey()'), isFalse);
    });

    test('the private base address is marked private and never published', () {
      expect(editor.contains('PRIVATE operational data'), isTrue);
      final safe = project(<Map<String, dynamic>>[_offer()]);
      expect(safe.toString().contains('Geheimestraat'), isFalse);
    });
  });

  group('4) NL/EN/FR/ES survive independently', () {
    test('editing one language leaves the others intact', () {
      final base = _offer();
      final edited = <String, dynamic>{
        ...base,
        'title': <String, String>{
          ...limousineLocalizedOf(base['title']),
          'fr': 'Nouveau',
        },
      };
      final safe = project(<Map<String, dynamic>>[edited]).first;
      final title = limousineLocalizedOf(safe['title']);
      expect(title['fr'], 'Nouveau');
      expect(title['nl'], 'Executive');
      expect(title['es'], 'Ejecutiva');
      final info = limousineLocalizedOf(safe['important_information']);
      expect(info['nl'], 'NLi');
      expect(info['es'], 'ESi');
    });
  });

  group('6/7/8) authoritative vehicle join and privacy', () {
    test('safe vehicle comes from the fleet record', () {
      final safe = project(<Map<String, dynamic>>[_offer()]).first;
      final v = Map<String, dynamic>.from(safe['vehicle'] as Map);
      expect(v['vehicle_id'], 'vh_1');
      expect(v['service_class_id'], 'executive_sedan');
      expect(v['passenger_capacity'], 3);
      expect(v['luggage_capacity'], 2);
      expect(v['color'], 'Black');
      expect(v['photo_url'], 'https://cdn.example.com/v1.jpg');
    });

    test('inactive / non-limousine / missing vehicle removes the offer', () {
      for (final id in const ['vh_inactive', 'vh_taxi', 'vh_missing']) {
        expect(
          project(<Map<String, dynamic>>[
            _offer(overrides: {'vehicle_id': id}),
          ]),
          isEmpty,
          reason: id,
        );
      }
      expect(buildSafePublicLimousineVehicle(null), isNull);
      expect(
        buildSafePublicLimousineVehicle(_vehicle(isActive: false)),
        isNull,
      );
      expect(
        buildSafePublicLimousineVehicle(_vehicle(serviceClassId: '')),
        isNull,
      );
    });

    test('plate, VIN, licences, driver and local photo refs never leak', () {
      final rendered = project(<Map<String, dynamic>>[_offer()]).toString();
      for (final secret in const [
        '1-ABC-123',
        'REG-9',
        'EXP-7',
        'drv_1',
        'local/secret.png',
        'Geheimestraat',
      ]) {
        expect(rendered.contains(secret), isFalse, reason: secret);
      }
      for (final key in kLimousinePrivateVehicleFields) {
        expect(rendered.contains(key), isFalse, reason: key);
      }
    });

    test('a non-https public photo is dropped', () {
      final safe = buildSafePublicLimousineVehicle(
        _vehicle(publicPhotoUrl: 'http://insecure.example.com/a.jpg'),
      );
      expect(safe, isNotNull);
      expect(safe!.containsKey('photo_url'), isFalse);
    });
  });

  group('9/10) full projection and exclusions', () {
    test('all safe sections are projected', () {
      final safe = project(<Map<String, dynamic>>[_offer()]).first;
      for (final key in const [
        'offer_id',
        'target_type',
        'vehicle',
        'service_class_id',
        'title',
        'description',
        'important_information',
        'pricing_modes',
        'price_presentation',
        'currency',
        'journey_types',
        'included_services',
        'paid_extras',
        'mobilisation',
        'source_revision',
      ]) {
        expect(safe.containsKey(key), isTrue, reason: key);
      }
      expect(safe['source_revision'], 4);
    });

    test('unpublished and invalid offers are excluded', () {
      expect(
        project(<Map<String, dynamic>>[
          _offer(overrides: {'published': false}),
        ]),
        isEmpty,
      );
      final invalid = _offer(
        overrides: {
          'hourly': {
            'enabled': true,
            'first_hour_cents': 12000,
            'additional_hour_cents': 9000,
            'currency': 'EUR',
          },
        },
      );
      expect(project(<Map<String, dynamic>>[invalid]), isEmpty);
    });
  });

  group('11/12) pricing mode vs presentation independence', () {
    test('modes are identical across every presentation token', () {
      final modes = limousineOfferSupportedPricingModes(_offer())..sort();
      for (final p in LimousinePricePresentation.all) {
        final other = limousineOfferSupportedPricingModes(
          _offer(overrides: {'price_presentation': p}),
        )..sort();
        expect(other, modes, reason: p);
      }
      expect(modes.contains(LimousineOfferPricingMode.fixed), isTrue);
      expect(modes.contains(LimousineOfferPricingMode.package), isTrue);
      expect(modes.contains(LimousineOfferPricingMode.distanceTime), isTrue);
    });

    test('no computable mode falls back to manual', () {
      expect(
        limousineOfferSupportedPricingModes(
          _offer(
            overrides: {
              'fixed_rules': <Map<String, dynamic>>[],
              'hourly': <String, dynamic>{},
              'distance_time': <String, dynamic>{},
            },
          ),
        ),
        <String>[LimousineOfferPricingMode.manual],
      );
    });

    test('only an exact presentation can resolve, regardless of mode', () {
      expect(limousineOfferCanResolvePrice(_offer()), isTrue);
      for (final p in const [
        LimousinePricePresentation.fromPrice,
        LimousinePricePresentation.indicative,
        LimousinePricePresentation.quoteRequired,
        LimousinePricePresentation.unavailable,
      ]) {
        expect(
          limousineOfferCanResolvePrice(
            _offer(overrides: {'price_presentation': p}),
          ),
          isFalse,
          reason: p,
        );
        expect(
          limousineOfferAmountIsSnapshotEligible(
            _offer(overrides: {'price_presentation': p}),
          ),
          isFalse,
          reason: p,
        );
      }
    });
  });

  group('13/14/16) preservation and monotonicity', () {
    test('fleet sync carries the authoritative limousine classification', () {
      final config = File('lib/app_config.dart').readAsStringSync();
      expect(config.contains("'service_category': v.serviceCategory"), isTrue);
      expect(config.contains("'service_class': v.serviceClassId"), isTrue);
    });

    test('taxi and airport stores stay separate and preserved', () {
      final worker = File(
        'workers/booking/fluxidi_booking_worker.js',
      ).readAsStringSync();
      expect(
        worker.contains('normalized.limousine = preservedLimousine'),
        isTrue,
      );
      expect(
        worker.contains(
          'const mergedProfile = { ...rawProfile, limousine: nextSection };',
        ),
        isTrue,
      );
      expect(worker.contains('buildScopedAirportFixedFaresKey'), isTrue);
    });

    test('source revision is monotonic', () {
      expect(
        limousineOffersRevisionAccepts(currentRevision: 7, incomingRevision: 6),
        isFalse,
      );
      expect(
        limousineOffersRevisionAccepts(currentRevision: 7, incomingRevision: 8),
        isTrue,
      );
    });
  });

  group('17) customer marketplace entry remains default OFF', () {
    test('gate off', () {
      expect(LimousineCustomerEntryContract.isVisible, isFalse);
    });
  });
}
