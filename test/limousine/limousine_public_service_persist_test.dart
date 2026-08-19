import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/limousine/limousine_business_setup.dart';
import 'package:fluxidi_tracking/limousine/limousine_business_setup_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_entry.dart';
import 'package:fluxidi_tracking/limousine/limousine_offers.dart';
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1a_ux.dart';
import 'package:fluxidi_tracking/limousine/limousine_provider_eligibility.dart';
import 'package:fluxidi_tracking/limousine/limousine_public_service_persist.dart';
import 'package:fluxidi_tracking/limousine/limousine_service_capability.dart';
import 'package:fluxidi_tracking/limousine/limousine_state_composition.dart';

VehicleProfile _limo() {
  return VehicleProfile(
    id: 'veh_stretch',
    vehicleName: 'Party Limo',
    brandModel: 'Party Limo',
    licensePlate: '1-ABC-123',
    color: 'white',
    passengerCapacity: 8,
    luggageCapacity: 4,
    tierId: 'premium',
    isActive: true,
    driverId: null,
    primaryPhotoRef: 'https://cdn.example/limo.jpg',
    galleryPhotoRefs: const <String>['https://cdn.example/limo-2.jpg'],
    publicPhotoUrl: 'https://cdn.example/limo.jpg',
    serviceCategory: 'limousine',
    serviceClassId: 'stretch_limousine',
  );
}

Map<String, dynamic> _publishedOffer() {
  return <String, dynamic>{
    'offer_id': 'off_1',
    'enabled': true,
    'published': true,
    'target_type': LimousineOfferTarget.serviceClass,
    'service_class_id': 'stretch_limousine',
    'price_presentation': LimousinePricePresentation.quoteRequired,
    'currency': 'EUR',
    'title': <String, String>{
      'nl': 'Avondchauffeur',
      'en': 'Evening chauffeur',
      'fr': '',
      'es': '',
    },
    'description': <String, String>{
      'nl': 'Volledige avond',
      'en': 'Full evening',
      'fr': '',
      'es': '',
    },
    'hourly': <String, dynamic>{'enabled': false, 'currency': 'EUR'},
    'distance_time': <String, dynamic>{'enabled': false, 'currency': 'EUR'},
  };
}

class _FakePersistStore {
  Map<String, dynamic> businessProfile = <String, dynamic>{};
  Map<String, dynamic> partnerProfile = <String, dynamic>{};
  int revision = 0;

  Map<String, dynamic> publish(Map<String, dynamic> incoming) {
    final incomingRev = incoming['source_revision'];
    if (incomingRev is int &&
        isStalePublicServiceRevision(
          existingRevision: revision,
          incomingRevision: incomingRev,
        )) {
      throw StateError('stale_partner_profile_revision');
    }
    final services = List<String>.from(
      (incoming['services'] as List?) ?? const <String>[],
    );
    revision += 1;
    partnerProfile = <String, dynamic>{
      ...partnerProfile,
      ...incoming,
      'services': services,
      'source_revision': revision,
      'profile_enabled': true,
      'is_active': true,
      'published_at': '2026-08-19T06:20:00Z',
      'limousine_entitled': true,
      'subscription_status': 'active',
    };
    businessProfile = <String, dynamic>{
      'publicServiceIds': services,
      'publicServicesConfigured': true,
      'source_revision': revision,
    };
    return Map<String, dynamic>.from(partnerProfile);
  }

  PublicServiceSelection hydrate() {
    return PublicServiceSelection(
      ids: List<String>.from(
        (businessProfile['publicServiceIds'] as List?) ?? const <String>[],
      ),
      configured: businessProfile['publicServicesConfigured'] == true,
      sourceRevision: revision,
    );
  }
}

void main() {
  test('omitted field keeps existing true', () {
    final merged = mergePublicServiceSelection(
      local: const PublicServiceSelection(
        ids: <String>['taxi_vvb', 'limousine'],
        configured: true,
        sourceRevision: 4,
      ),
      server: const PublicServiceSelection(
        ids: <String>[],
        configured: false,
      ),
      serverFieldPresent: false,
    );
    expect(merged.limousineEnabled, isTrue);
    expect(merged.configured, isTrue);
  });

  test('explicit disable stores false', () {
    final merged = mergePublicServiceSelection(
      local: const PublicServiceSelection(
        ids: <String>['taxi_vvb', 'limousine'],
        configured: true,
      ),
      server: const PublicServiceSelection(
        ids: <String>['taxi_vvb'],
        configured: true,
      ),
    );
    expect(merged.limousineEnabled, isFalse);
    expect(merged.ids, <String>['taxi_vvb']);
  });

  test('stale response cannot roll true back', () {
    final merged = mergePublicServiceSelection(
      local: const PublicServiceSelection(
        ids: <String>['limousine'],
        configured: true,
        sourceRevision: 9,
      ),
      server: const PublicServiceSelection(
        ids: <String>['taxi_vvb'],
        configured: true,
        sourceRevision: 3,
      ),
    );
    expect(merged.limousineEnabled, isTrue);
  });

  test('hero/fleet/offer saves do not drop the toggle', () {
    const current = PublicServiceSelection(
      ids: <String>['limousine', 'taxi_vvb'],
      configured: true,
    );
    expect(
      applyPublishedPartnerServices(
        current: current,
        publishedServices: const <String>['limousine', 'taxi_vvb'],
      ).limousineEnabled,
      isTrue,
    );
    expect(
      mappedPublicServiceIdsForPublish(
        configured: true,
        selected: const <String>['limousine'],
        legacyFallback: const <String>['taxi_vvb'],
      ),
      <String>['limousine'],
    );
  });

  test('general profile publish keeps limousine when the chip stays on', () {
    expect(
      mappedPublicServiceIdsForPublish(
        configured: true,
        selected: const <String>['taxi_vvb', 'limousine'],
        legacyFallback: const <String>['taxi_vvb'],
      ),
      contains(kLimousinePublicServiceId),
    );
  });

  test('gates off do not lower completion or hide capability', () {
    expect(LimousineCustomerEntryContract.isVisible, isFalse);
    const quoteEnabled = bool.fromEnvironment(
      'LIMOUSINE_QUOTE_ENABLED',
      defaultValue: false,
    );
    const bookEnabled = bool.fromEnvironment(
      'LIMOUSINE_BOOK_ENABLED',
      defaultValue: false,
    );
    expect(quoteEnabled, isFalse);
    expect(bookEnabled, isFalse);
    expect(
      limousineBusinessSettingsCardIsComplete(
        publicServiceEnabled: true,
        sectionEnabled: true,
        hasEligibleVehicle: true,
        hasPublishedOffer: true,
        hasPublicText: true,
        hasSafePublicMedia: true,
      ),
      isTrue,
    );
    expect(
      partnerHasExplicitLimousineCapability(<String, dynamic>{
        'services': <String>['limousine'],
        'booking_capabilities': <String, dynamic>{'limousine': false},
        'bookable': false,
      }),
      isTrue,
    );
  });

  test('taxi and airport stay selectable without inventing limousine', () {
    expect(
      mappedPublicServiceIdsForPublish(
        configured: true,
        selected: const <String>['taxi_vvb', 'airport_transfer'],
        legacyFallback: const <String>['taxi_vvb'],
      ),
      <String>['taxi_vvb', 'airport_transfer'],
    );
    expect(
      partnerHasExplicitLimousineCapability(<String, dynamic>{
        'services': <String>['taxi_vvb', 'airport_transfer'],
      }),
      isFalse,
    );
  });

  test('full persist reopen discovery chain keeps Limousine on', () {
    final store = _FakePersistStore();
    var selection = const PublicServiceSelection(
      ids: <String>['taxi_vvb'],
      configured: true,
    );

    // 1-3 public partner profile: toggle on and publish.
    selection = selection.copyWith(
      ids: <String>['taxi_vvb', 'limousine'],
      configured: true,
    );
    final payload = <String, dynamic>{
      'services': mappedPublicServiceIdsForPublish(
        configured: selection.configured,
        selected: selection.ids,
        legacyFallback: const <String>['taxi_vvb'],
      ),
      'booking_capabilities': <String, dynamic>{
        'limousine': selection.limousineEnabled,
      },
      'vehicles': <Map<String, dynamic>>[
        <String, dynamic>{
          'name': 'Party Limo',
          'service_category': 'limousine',
          'service_class': 'stretch_limousine',
          'is_active': true,
        },
      ],
      'limousine_offers': <Map<String, dynamic>>[_publishedOffer()],
    };
    store.publish(payload);

    // 4 dispose Flutter state.
    PublicServiceSelection? disposed;
    disposed = selection;
    selection = const PublicServiceSelection(ids: <String>[], configured: false);
    expect(identical(disposed, selection), isFalse);

    // 5-7 fresh GET + reopen hydrates the toggle back on.
    selection = mergePublicServiceSelection(
      local: selection,
      server: store.hydrate(),
      serverFieldPresent: true,
    );
    expect(selection.limousineEnabled, isTrue);
    expect(
      composeLimousinePublicAvailability(<String, dynamic>{
        ...store.partnerProfile,
        'features': <String, dynamic>{'limousine': true},
      }).state,
      isNot(LimousinePublicAvailabilityState.entitledButDisabledByCompany),
    );

    // 8-11 limousine settings keep vehicles, classes, offers, text, hero.
    final vehicles = <VehicleProfile>[_limo()];
    final offers = <Map<String, dynamic>>[_publishedOffer()];
    final readiness = limousineBusinessSetupReadiness(
      vehicles: vehicles,
      offers: offers,
      publicTitle: const <String, String>{'nl': 'Avondchauffeur'},
      publicDescription: const <String, String>{'nl': 'Volledige avond'},
      knownClassIds: const <String>['stretch_limousine'],
      entryEnabled: false,
      sectionEnabled: true,
    );
    expect(readiness.items.every((item) => item.complete), isTrue);
    expect(readiness.canPublish, isTrue);

    // 12-13 business settings card is Compleet, not Optioneel.
    expect(
      limousineBusinessSettingsCardIsOptional(
        publicServiceEnabled: selection.limousineEnabled,
        sectionEnabled: true,
      ),
      isFalse,
    );
    expect(
      limousineBusinessSettingsCardIsComplete(
        publicServiceEnabled: selection.limousineEnabled,
        sectionEnabled: true,
        hasEligibleVehicle: true,
        hasPublishedOffer: true,
        hasPublicText: true,
        hasSafePublicMedia: true,
      ),
      isTrue,
    );

    // 14-19 discovery keeps the company unscoped, 9688 and 1000.
    final company = <String, dynamic>{
      ...store.partnerProfile,
      'features': <String, dynamic>{'limousine': true},
      'limousine_available': true,
      'coverage': <String, dynamic>{
        'primary_postcode': '9688',
        'postcodes': <String>['9688', '9000'],
      },
    };
    expect(isPubliclyEligibleLimousineProvider(company), isTrue);
    expect(
      isPubliclyEligibleLimousineProvider(
        company,
        request: const LimousineMarketRequest(postcode: '9688'),
      ),
      isTrue,
    );
    expect(
      isPubliclyEligibleLimousineProvider(
        company,
        request: const LimousineMarketRequest(postcode: '1000'),
      ),
      isTrue,
    );

    // 20 quote/book gates stay off and only produce the transaction copy.
    expect(
      limousineBusinessSetupFriendlyStatus(
        gatesOff: true,
        language: AppLanguage.nl,
      ),
      kLimousineBusinessSetupTransactionsOff.nl,
    );
    expect(
      kLimousineBusinessSetupTestMessage.nl.contains('toegelaten testgebruikers'),
      isTrue,
    );
    expect(
      kLimousineBusinessSetupTestMessage.nl.contains('nog niet zichtbaar voor klanten'),
      isFalse,
    );
  });
}
