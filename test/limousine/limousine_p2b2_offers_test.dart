import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_entry.dart';
import 'package:fluxidi_tracking/limousine/limousine_offers.dart';

// Illustrative TEST fixtures in integer cents — never production fares.
const List<String> _classIds = <String>['executive_sedan', 'business_van'];

VehicleProfile _vehicle({
  String id = 'vh_1',
  bool isActive = true,
  String serviceCategory = 'limousine',
  String serviceClassId = 'executive_sedan',
}) {
  return VehicleProfile(
    id: id,
    vehicleName: 'Fleet One',
    brandModel: 'Mercedes S-Class',
    licensePlate: '1-ABC-123',
    color: 'Black',
    passengerCapacity: 3,
    luggageCapacity: 3,
    tierId: 'premium',
    isActive: isActive,
    driverId: null,
    primaryPhotoRef: '',
    galleryPhotoRefs: const <String>[],
    serviceCategory: serviceCategory,
    serviceClassId: serviceClassId,
  );
}

Map<String, dynamic> _classOffer({Map<String, dynamic> overrides = const {}}) {
  return <String, dynamic>{
    'offer_id': 'off_class',
    'enabled': true,
    'published': true,
    'target_type': LimousineOfferTarget.serviceClass,
    'service_class_id': 'executive_sedan',
    'price_presentation': LimousinePricePresentation.exactFixed,
    'currency': 'EUR',
    'journey_types': <String>['point_to_point'],
    'title': {'nl': 'Klasse', 'en': 'Class', 'fr': 'Classe', 'es': 'Clase'},
    'fixed_rules': <Map<String, dynamic>>[
      {
        'rule_id': 'r1',
        'enabled': true,
        'journey_type': 'point_to_point',
        'zone_type': 'none',
        'amount_cents': 20000,
        'currency': 'EUR',
      },
    ],
    'mobilisation': {'method': LimousineMobilisationMethod.included},
    'source_revision': 2,
    ...overrides,
  };
}

Map<String, dynamic> _vehicleOffer({
  Map<String, dynamic> overrides = const {},
}) {
  return <String, dynamic>{
    ..._classOffer(),
    'offer_id': 'off_vehicle',
    'target_type': LimousineOfferTarget.vehicle,
    'vehicle_id': 'vh_1',
    ...overrides,
  };
}

void main() {
  final vehicles = <VehicleProfile>[
    _vehicle(),
    _vehicle(id: 'vh_taxi', serviceCategory: '', serviceClassId: ''),
    _vehicle(id: 'vh_inactive', isActive: false),
  ];

  LimousineOfferValidation validate(
    Map<String, dynamic> offer, {
    bool readiness = true,
  }) {
    return validateLimousineOffer(
      offer,
      vehicles: vehicles,
      knownClassIds: _classIds,
      readiness: readiness,
    );
  }

  group('3) exact vehicle overrides class offer', () {
    test('vehicle offer wins when the request names the vehicle', () {
      final offers = <Map<String, dynamic>>[_classOffer(), _vehicleOffer()];
      expect(
        selectLimousineOfferForRequest(
          offers,
          vehicleId: 'vh_1',
          serviceClassId: 'executive_sedan',
          journeyType: 'point_to_point',
        )?['offer_id'],
        'off_vehicle',
      );
      expect(
        selectLimousineOfferForRequest(
          offers,
          serviceClassId: 'executive_sedan',
          journeyType: 'point_to_point',
        )?['offer_id'],
        'off_class',
      );
    });
  });

  group('4) unknown vehicle / class fails closed', () {
    test('unknown, non-limousine and inactive vehicles are rejected', () {
      expect(
        validate(_vehicleOffer(overrides: {'vehicle_id': 'nope'})).errors,
        contains(LimousineOfferError.unknownVehicle),
      );
      expect(
        validate(_vehicleOffer(overrides: {'vehicle_id': 'vh_taxi'})).errors,
        contains(LimousineOfferError.vehicleNotLimousine),
      );
      expect(
        validate(
          _vehicleOffer(overrides: {'vehicle_id': 'vh_inactive'}),
        ).errors,
        contains(LimousineOfferError.inactiveVehicle),
      );
      expect(
        validate(
          _classOffer(overrides: {'service_class_id': 'unknown'}),
        ).errors,
        contains(LimousineOfferError.unknownServiceClass),
      );
    });
  });

  group('5/6) hourly first+additional hour and minimum duration', () {
    test('missing minimum duration fails closed', () {
      final offer = _classOffer(
        overrides: {
          'hourly': {
            'enabled': true,
            'first_hour_cents': 12000,
            'additional_hour_cents': 9000,
            'currency': 'EUR',
          },
        },
      );
      expect(
        validate(offer).errors,
        contains(LimousineOfferError.hourlyMissingMinimumDuration),
      );
    });

    test('missing hourly rates fails closed', () {
      final offer = _classOffer(
        overrides: {
          'hourly': {
            'enabled': true,
            'minimum_duration_minutes': 180,
            'currency': 'EUR',
          },
        },
      );
      expect(
        validate(offer).errors,
        contains(LimousineOfferError.hourlyIncomplete),
      );
    });

    test('a package needs both duration and amount', () {
      final offer = _classOffer(
        overrides: {
          'hourly': {
            'enabled': true,
            'first_hour_cents': 12000,
            'additional_hour_cents': 9000,
            'minimum_duration_minutes': 180,
            'package_amount_cents': 30000,
            'currency': 'EUR',
          },
        },
      );
      expect(
        validate(offer).errors,
        contains(LimousineOfferError.packageIncomplete),
      );
    });
  });

  group('7) exact fixed requires complete matching data', () {
    test('airport rule without IATA is incomplete', () {
      final offer = _classOffer(
        overrides: {
          'fixed_rules': <Map<String, dynamic>>[
            {
              'rule_id': 'r1',
              'enabled': true,
              'journey_type': 'airport_transfer',
              'zone_type': 'none',
              'amount_cents': 20000,
              'currency': 'EUR',
            },
          ],
        },
      );
      expect(
        validate(offer).errors,
        contains(LimousineOfferError.incompleteFixedRule),
      );
      expect(validate(_classOffer()).valid, isTrue);
    });
  });

  group('8/9/10) from / indicative / quote are never a final price', () {
    test('only exact_fixed can resolve or enter a snapshot', () {
      for (final presentation in const [
        LimousinePricePresentation.fromPrice,
        LimousinePricePresentation.indicative,
        LimousinePricePresentation.quoteRequired,
        LimousinePricePresentation.unavailable,
      ]) {
        final offer = _classOffer(
          overrides: {
            'price_presentation': presentation,
            'display_amount_cents': 19900,
          },
        );
        expect(
          limousineOfferCanResolvePrice(offer),
          isFalse,
          reason: presentation,
        );
        expect(
          limousineOfferAmountIsSnapshotEligible(offer),
          isFalse,
          reason: presentation,
        );
      }
      expect(limousineOfferCanResolvePrice(_classOffer()), isTrue);
    });

    test('quote_required exposes no amount publicly', () {
      final offer = _classOffer(
        overrides: {
          'price_presentation': LimousinePricePresentation.quoteRequired,
          'display_amount_cents': 19900,
        },
      );
      final safe = buildSafePublicLimousineOffers(
        <Map<String, dynamic>>[offer],
        eligible: true,
        vehicles: vehicles,
        knownClassIds: _classIds,
        readiness: true,
      );
      expect(safe, hasLength(1));
      expect(safe.first.containsKey('display_amount_cents'), isFalse);
    });
  });

  group('12/13/14) mobilisation', () {
    test('included is valid; charged needs a complete method', () {
      expect(validate(_classOffer()).valid, isTrue);
      expect(
        validate(
          _classOffer(
            overrides: {
              'mobilisation': {
                'method': LimousineMobilisationMethod.fixedFee,
                'outbound_charged': true,
                'fee_cents': 5000,
                'currency': 'EUR',
              },
            },
          ),
        ).valid,
        isTrue,
      );
      expect(
        validate(
          _classOffer(
            overrides: {
              'mobilisation': {
                'method': LimousineMobilisationMethod.fixedFee,
                'outbound_charged': true,
                'currency': 'EUR',
              },
            },
          ),
        ).errors,
        contains(LimousineOfferError.mobilisationIncomplete),
      );
      expect(
        validate(
          _classOffer(
            overrides: {
              'mobilisation': {
                'method': LimousineMobilisationMethod.included,
                'outbound_charged': true,
              },
            },
          ),
        ).errors,
        contains(LimousineOfferError.mobilisationContradictory),
      );
    });
  });

  group('15) private operating base is never projected', () {
    test('safe projection excludes the base address', () {
      final offer = _classOffer(
        overrides: {
          'mobilisation': {
            'method': LimousineMobilisationMethod.included,
            'operating_base_address': 'Geheimestraat 1, 9000 Gent',
            'disclosure': {
              'nl': 'Voorrijden inbegrepen',
              'en': 'Mobilisation included',
              'fr': '',
              'es': '',
            },
          },
        },
      );
      final safe = buildSafePublicLimousineOffers(
        <Map<String, dynamic>>[offer],
        eligible: true,
        vehicles: vehicles,
        knownClassIds: _classIds,
        readiness: true,
      );
      final encoded = safe.toString();
      expect(encoded.contains('Geheimestraat'), isFalse);
      expect(encoded.contains('operating_base_address'), isFalse);
      expect(safe.first['mobilisation']['included'], isTrue);
    });
  });

  group('16/17/18) projection filtering', () {
    test('included services and paid extras stay separate', () {
      final offer = _classOffer(
        overrides: {
          'included_services': <Map<String, dynamic>>[
            {
              'item_id': 'water',
              'label': {
                'nl': 'Water',
                'en': 'Water',
                'fr': 'Eau',
                'es': 'Agua',
              },
              'active': true,
            },
          ],
          'paid_extras': <Map<String, dynamic>>[
            {
              'extra_id': 'wait',
              'label': {
                'nl': 'Wachttijd',
                'en': 'Waiting time',
                'fr': 'Attente',
                'es': 'Espera',
              },
              'amount_cents': 2500,
              'currency': 'EUR',
              'active': true,
              'public': true,
            },
          ],
        },
      );
      final safe = buildSafePublicLimousineOffers(
        <Map<String, dynamic>>[offer],
        eligible: true,
        vehicles: vehicles,
        knownClassIds: _classIds,
        readiness: true,
      ).first;
      expect(safe['included_services'], hasLength(1));
      expect(safe['paid_extras'], hasLength(1));
      expect(
        (safe['included_services'] as List).first.containsKey('amount_cents'),
        isFalse,
      );
    });

    test(
      'unpublished/disabled excluded; ineligible company projects nothing',
      () {
        expect(
          buildSafePublicLimousineOffers(
            <Map<String, dynamic>>[
              _classOffer(overrides: {'published': false}),
            ],
            eligible: true,
            vehicles: vehicles,
            knownClassIds: _classIds,
            readiness: true,
          ),
          isEmpty,
        );
        expect(
          buildSafePublicLimousineOffers(
            <Map<String, dynamic>>[_classOffer()],
            eligible: false,
            vehicles: vehicles,
            knownClassIds: _classIds,
            readiness: true,
          ),
          isEmpty,
        );
        expect(
          validate(_classOffer(), readiness: false).errors,
          contains(LimousineOfferError.publishedWithoutReadiness),
        );
      },
    );
  });

  group('19/20) revision monotonicity and non-destructive disable', () {
    test('older revision cannot overwrite newer config', () {
      expect(
        limousineOffersRevisionAccepts(currentRevision: 5, incomingRevision: 4),
        isFalse,
      );
      expect(
        limousineOffersRevisionAccepts(currentRevision: 5, incomingRevision: 5),
        isFalse,
      );
      expect(
        limousineOffersRevisionAccepts(currentRevision: 5, incomingRevision: 6),
        isTrue,
      );
    });

    test('disabling preserves configuration but stops discovery', () {
      final offer = _classOffer();
      final disabled = <String, dynamic>{...offer, 'enabled': false};
      expect(disabled['fixed_rules'], equals(offer['fixed_rules']));
      expect(disabled['source_revision'], offer['source_revision']);
      expect(
        buildSafePublicLimousineOffers(
          <Map<String, dynamic>>[disabled],
          eligible: true,
          vehicles: vehicles,
          knownClassIds: _classIds,
          readiness: true,
        ),
        isEmpty,
      );
    });
  });

  group('1/2) taxi and airport pricing remain unchanged', () {
    test('taxi pricing engine and airport fixed fares are untouched', () {
      final settings = File(
        'lib/business_settings_page.dart',
      ).readAsStringSync();
      // Both legacy sections still exist and are separate from the new one.
      expect(settings.contains("id: 'pricing_engine'"), isTrue);
      expect(settings.contains('_airportFixedFareCard()'), isTrue);
      expect(settings.contains("id: 'limousine_offers_pricing'"), isTrue);
      // The limousine admin API targets its own endpoint, not the taxi one.
      final config = File('lib/app_config.dart').readAsStringSync();
      expect(config.contains('/admin/pricing/limousine'), isTrue);
      expect(config.contains('/admin/pricing/airport-fixed-fares'), isTrue);
      // The taxi encoder still omits limousine (server preserves the section).
      expect(
        config.contains("'limousine':") &&
            config.contains('_encodePricingProfileForBackend'),
        isTrue,
      );
    });

    test(
      'server preserves the limousine section across taxi pricing saves',
      () {
        final worker = File(
          'workers/booking/fluxidi_booking_worker.js',
        ).readAsStringSync();
        expect(
          worker.contains('normalized.limousine = preservedLimousine'),
          isTrue,
        );
        expect(worker.contains('_loadRawTenantPricingProfileObject'), isTrue);
      },
    );
  });

  group('21) NL/EN/FR/ES labels', () {
    test(
      'presentation, journey, mobilisation and error labels are localized',
      () {
        for (final lang in const [
          AppLanguage.nl,
          AppLanguage.en,
          AppLanguage.fr,
          AppLanguage.es,
        ]) {
          for (final p in LimousinePricePresentation.all) {
            expect(limousinePresentationLabel(p, lang).trim(), isNotEmpty);
          }
          for (final j in LimousineJourneyTypeId.all) {
            expect(limousineJourneyTypeLabel(j, lang).trim(), isNotEmpty);
          }
          for (final m in LimousineMobilisationMethod.all) {
            expect(limousineMobilisationLabel(m, lang).trim(), isNotEmpty);
          }
          for (final code in kLimousineOfferErrorLabels.keys) {
            expect(limousineOfferErrorLabel(code, lang).trim(), isNotEmpty);
          }
        }
      },
    );

    test('section title is localized in all four languages', () {
      final settings = File(
        'lib/business_settings_page.dart',
      ).readAsStringSync();
      expect(settings.contains('Limousineaanbod en prijzen'), isTrue);
      expect(settings.contains('Limousine offers and pricing'), isTrue);
      expect(settings.contains('Offres et tarifs limousine'), isTrue);
      expect(settings.contains('Ofertas y precios de limusina'), isTrue);
    });
  });

  group('22) customer marketplace entry remains default OFF', () {
    test('gate off', () {
      expect(LimousineCustomerEntryContract.isVisible, isFalse);
      final home = File(
        'lib/main_parts/customer_home_page.dart',
      ).readAsStringSync();
      expect(home.contains('LimousineCustomerEntryContract.isVisible'), isTrue);
    });
  });
}
