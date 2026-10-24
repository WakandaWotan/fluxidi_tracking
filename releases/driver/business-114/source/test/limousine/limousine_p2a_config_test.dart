import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_entry.dart';
import 'package:fluxidi_tracking/limousine/limousine_marketplace_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_provider_eligibility.dart';
import 'package:fluxidi_tracking/limousine/limousine_state_composition.dart';

VehicleProfile _vehicle({
  String serviceCategory = '',
  String serviceClassId = '',
  bool isActive = true,
}) {
  return VehicleProfile(
    id: 'veh_1',
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

Map<String, dynamic> _company({
  String subscriptionStatus = 'active',
  bool entitled = true,
  List<String> services = const ['limousine'],
  bool published = true,
  bool bookable = true,
  List<Map<String, dynamic>>? vehicles,
  Map<String, dynamic>? extra,
}) {
  return <String, dynamic>{
    'subscription_status': subscriptionStatus,
    'features': <String, dynamic>{'limousine': entitled},
    'is_active': true,
    'services': services,
    'profile_enabled': published,
    'published_at': published ? '2026-08-17T10:00:00Z' : '',
    'bookable': bookable,
    'vehicles':
        vehicles ??
        <Map<String, dynamic>>[
          {
            'service_category': 'limousine',
            'service_class': 'executive_sedan',
            'category': 'limousine',
            'is_active': true,
          },
        ],
    'limousine_available': true,
    'limousine_offers': <Map<String, dynamic>>[
      <String, dynamic>{
        'offer_id': 'off_quote',
        'enabled': true,
        'published': true,
        'price_presentation': 'quote_required',
      },
    ],
    ...?extra,
  };
}

void main() {
  group('authoritative service-class catalog', () {
    test('5/6/7) known ids resolve; free text/brand/marketing fail closed', () {
      expect(isKnownActiveLimousineServiceClassId('executive_sedan'), isTrue);
      expect(isKnownActiveLimousineServiceClassId('business_van'), isTrue);
      expect(isKnownActiveLimousineServiceClassId(''), isFalse);
      expect(isKnownActiveLimousineServiceClassId('mercedes'), isFalse);
      expect(isKnownActiveLimousineServiceClassId('premium'), isFalse);
      expect(
        isKnownActiveLimousineServiceClassId('executive s-class vip'),
        isFalse,
      );
      expect(isKnownActiveLimousineServiceClassId('unknown_class'), isFalse);
    });

    test('catalog exposes stable id + separate localized labels', () {
      final classes = appConfig.enabledLimousineServiceClasses;
      expect(classes, isNotEmpty);
      final exec = limousineServiceClassById('executive_sedan');
      expect(exec, isNotNull);
      expect(exec!.id, 'executive_sedan');
      expect(exec.labelFor(AppLanguage.nl), isNotEmpty);
      expect(exec.labelFor(AppLanguage.en), isNotEmpty);
      expect(exec.labelFor(AppLanguage.fr), isNotEmpty);
      expect(exec.labelFor(AppLanguage.es), isNotEmpty);
      // Tiers are a different axis and are not limousine classes.
      expect(isKnownActiveLimousineServiceClassId('comfort'), isFalse);
      expect(isKnownActiveLimousineServiceClassId('private'), isFalse);
    });
  });

  group('vehicle limousine classification', () {
    test('3) defaults OFF (no category/class)', () {
      final v = _vehicle();
      expect(v.serviceCategory, '');
      expect(v.serviceClassId, '');
    });

    test('8) valid explicit configuration persists via copyWith', () {
      final v = _vehicle().copyWith(
        serviceCategory: 'limousine',
        serviceClassId: 'executive_sedan',
      );
      expect(v.serviceCategory, 'limousine');
      expect(v.serviceClassId, 'executive_sedan');
    });

    test(
      '9) removing classification removes eligibility, keeps the vehicle',
      () {
        final configured = _vehicle(
          serviceCategory: 'limousine',
          serviceClassId: 'executive_sedan',
        );
        expect(
          isEligibleLimousineVehicle(<String, dynamic>{
            'service_category': configured.serviceCategory,
            'service_class': configured.serviceClassId,
            'is_active': true,
          }),
          isTrue,
        );
        final cleared = configured.copyWith(
          serviceCategory: '',
          serviceClassId: '',
        );
        expect(cleared.id, configured.id); // vehicle preserved
        expect(
          isEligibleLimousineVehicle(<String, dynamic>{
            'service_category': cleared.serviceCategory,
            'service_class': cleared.serviceClassId,
            'is_active': true,
          }),
          isFalse,
        );
      },
    );

    test('4) category must be explicit — brand/model/tier never implies it', () {
      // A premium Mercedes without explicit limousine category is not eligible.
      expect(
        isEligibleLimousineVehicle(<String, dynamic>{
          'brand_model': 'Mercedes S-Class',
          'category': 'Premium',
          'tierId': 'premium',
          'is_active': true,
        }),
        isFalse,
      );
    });

    test('10) inactive vehicle removes readiness', () {
      expect(
        isEligibleLimousineVehicle(<String, dynamic>{
          'service_category': 'limousine',
          'service_class': 'executive_sedan',
          'is_active': false,
        }),
        isFalse,
      );
    });
  });

  group('22) business-settings shows all six readiness states', () {
    test('publicly available', () {
      expect(
        composeLimousinePublicAvailability(_company()).state,
        LimousinePublicAvailabilityState.publiclyAvailable,
      );
    });
    test('unavailable under subscription', () {
      expect(
        composeLimousinePublicAvailability(_company(entitled: false)).state,
        LimousinePublicAvailabilityState.unavailableUnderSubscription,
      );
    });
    test('entitled but disabled by company', () {
      expect(
        composeLimousinePublicAvailability(
          _company(services: const ['taxi_vvb']),
        ).state,
        LimousinePublicAvailabilityState.entitledButDisabledByCompany,
      );
    });
    test('enabled but profile not published', () {
      expect(
        composeLimousinePublicAvailability(_company(published: false)).state,
        LimousinePublicAvailabilityState.enabledButProfileNotPublished,
      );
    });
    test('published but no eligible active vehicle', () {
      expect(
        composeLimousinePublicAvailability(_company(vehicles: const [])).state,
        LimousinePublicAvailabilityState.publishedButTemporarilyUnavailable,
      );
    });
    test('suspended/blocked', () {
      expect(
        composeLimousinePublicAvailability(
          _company(extra: const {'suspended': true}),
        ).state,
        LimousinePublicAvailabilityState.suspendedOrBlocked,
      );
    });
  });

  group('23) NL/EN/FR/ES labels for classes and readiness states', () {
    test('every service class has four localized labels', () {
      for (final c in appConfig.enabledLimousineServiceClasses) {
        for (final lang in const [
          AppLanguage.nl,
          AppLanguage.en,
          AppLanguage.fr,
          AppLanguage.es,
        ]) {
          expect(c.labelFor(lang).trim(), isNotEmpty, reason: '${c.id}/$lang');
        }
      }
    });
    test('all six readiness states have four localized labels', () {
      for (final s in LimousinePublicAvailabilityState.values) {
        for (final lang in const [
          AppLanguage.nl,
          AppLanguage.en,
          AppLanguage.fr,
          AppLanguage.es,
        ]) {
          expect(
            limousineAvailabilityStateLabelFor(s, lang).trim(),
            isNotEmpty,
            reason: '${s.name}/$lang',
          );
        }
      }
    });
  });

  group('vehicle editor UI wiring (source contract)', () {
    final source = File('lib/vehicle_management_page.dart').readAsStringSync();

    test(
      'editor has an optional limousine section, default off, no upgrade CTA',
      () {
        expect(source.contains('_limousineVehicleConfigSection'), isTrue);
        expect(
          source.contains("serviceCategory: resolvedServiceCategory"),
          isTrue,
        );
        expect(
          source.contains("serviceClassId: resolvedServiceClassId"),
          isTrue,
        );
        // entitlement gate present
        expect(
          source.contains("subProfile.features['limousine'] == true"),
          isTrue,
        );
        // required-class validation present
        expect(source.contains('isKnownActiveLimousineServiceClassId'), isTrue);
        // no upgrade/checkout CTA introduced in this section
        expect(source.contains('Upgrade'), isFalse);
      },
    );

    test('5) saving limousine without a class is blocked', () {
      expect(
        source.contains(
          'Select a limousine class to save the limousine service.',
        ),
        isTrue,
      );
    });
  });

  group('24) customer-entry gate remains default OFF', () {
    test('gate off', () {
      expect(LimousineCustomerEntryContract.isVisible, isFalse);
    });
  });

  group('28) no pricing/checkout/booking path introduced in P2A files', () {
    test(
      'vehicle + settings limousine additions carry no price/quote/checkout',
      () {
        final vehicleSrc = File(
          'lib/vehicle_management_page.dart',
        ).readAsStringSync();
        // The limousine section must not introduce pricing/quote/checkout words.
        final limoStart = vehicleSrc.indexOf(
          'Widget _limousineVehicleConfigSection({',
        );
        expect(limoStart, greaterThan(0));
        final limoEnd = vehicleSrc.indexOf(
          'void _showMissingCompanyScopeSnackbar',
          limoStart,
        );
        expect(limoEnd, greaterThan(limoStart));
        final window = vehicleSrc.substring(limoStart, limoEnd);
        for (final banned in const [
          'price',
          'quote',
          'checkout',
          'tariff',
          'fare',
        ]) {
          expect(
            RegExp(banned, caseSensitive: false).hasMatch(window),
            isFalse,
            reason: banned,
          );
        }
      },
    );
  });
}
