import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/limousine/limousine_business_setup.dart';
import 'package:fluxidi_tracking/limousine/limousine_business_setup_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_business_setup_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_marketplace_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_offers.dart';
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1a_ux.dart';
import 'package:fluxidi_tracking/limousine/limousine_public_service_persist.dart';
import 'package:fluxidi_tracking/limousine/limousine_state_composition.dart';

VehicleProfile _limo() {
  return VehicleProfile(
    id: 'vh_party',
    vehicleName: 'Party Limo',
    brandModel: 'Party Limo',
    licensePlate: '1-ABC-123',
    color: 'white',
    passengerCapacity: 8,
    luggageCapacity: 4,
    tierId: 'premium',
    isActive: true,
    driverId: null,
    primaryPhotoRef: 'https://cdn.example/main.jpg',
    galleryPhotoRefs: const <String>[],
    publicPhotoUrl: 'https://cdn.example/main.jpg',
    serviceCategory: 'limousine',
    serviceClassId: 'stretch_limousine',
  );
}

Map<String, dynamic> _offer({bool published = false}) {
  return <String, dynamic>{
    'offer_id': 'off_1',
    'enabled': true,
    'published': published,
    'target_type': LimousineOfferTarget.serviceClass,
    'service_class_id': 'stretch_limousine',
    'price_presentation': LimousinePricePresentation.quoteRequired,
    'currency': 'EUR',
    'title': <String, String>{
      'nl': 'Avond',
      'en': 'Evening',
      'fr': 'Soiree',
      'es': 'Noche',
    },
    'description': <String, String>{
      'nl': 'Avondrit',
      'en': 'Evening ride',
      'fr': 'Soiree',
      'es': 'Noche',
    },
    'hourly': <String, dynamic>{'enabled': false, 'currency': 'EUR'},
    'distance_time': <String, dynamic>{'enabled': false, 'currency': 'EUR'},
  };
}

Widget _app(Widget child) {
  return MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(size: kLimousinePhonePortrait),
      child: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('draft offer is not 100 percent; published offer is complete', () {
    final draft = limousineBusinessSetupReadiness(
      vehicles: <VehicleProfile>[_limo()],
      offers: <Map<String, dynamic>>[_offer()],
      publicTitle: const <String, String>{'nl': 'Maison'},
      publicDescription: const <String, String>{'nl': 'Limousines'},
      knownClassIds: const <String>['stretch_limousine'],
      sectionEnabled: true,
    );
    final published = limousineBusinessSetupReadiness(
      vehicles: <VehicleProfile>[_limo()],
      offers: <Map<String, dynamic>>[_offer(published: true)],
      publicTitle: const <String, String>{'nl': 'Maison'},
      publicDescription: const <String, String>{'nl': 'Limousines'},
      knownClassIds: const <String>['stretch_limousine'],
      sectionEnabled: true,
    );
    expect(draft.canPublish, isTrue);
    expect(draft.isFullyComplete, isFalse);
    expect(draft.progress, lessThan(1));
    expect(published.isFullyComplete, isTrue);
    expect(published.progress, 1.0);
    final disabledSection = limousineBusinessSetupReadiness(
      vehicles: <VehicleProfile>[_limo()],
      offers: <Map<String, dynamic>>[_offer(published: true)],
      publicTitle: const <String, String>{'nl': 'Maison'},
      publicDescription: const <String, String>{'nl': 'Limousines'},
      knownClassIds: const <String>['stretch_limousine'],
      sectionEnabled: false,
    );
    expect(disabledSection.isFullyComplete, isFalse);
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
  });

  test('Gepubliceerd en zichtbaar requires server public offers', () {
    final localOnly = composeLimousinePublicAvailability(<String, dynamic>{
      'subscription_status': 'active',
      'features': <String, dynamic>{'limousine': true},
      'is_active': true,
      'services': <String>['limousine'],
      'profile_enabled': true,
      'published_at': '2026-08-19T08:00:00Z',
      'vehicles': <Map<String, dynamic>>[
        <String, dynamic>{
          'service_category': 'limousine',
          'service_class': 'stretch_limousine',
          'is_active': true,
        },
      ],
    });
    expect(
      localOnly.state,
      LimousinePublicAvailabilityState.publishedButTemporarilyUnavailable,
    );
    final serverReady = composeLimousinePublicAvailability(<String, dynamic>{
      'subscription_status': 'active',
      'features': <String, dynamic>{'limousine': true},
      'is_active': true,
      'services': <String>['limousine'],
      'profile_enabled': true,
      'published_at': '2026-08-19T08:00:00Z',
      'limousine_available': true,
      'limousine_offers': <Map<String, dynamic>>[_offer(published: true)],
      'vehicles': <Map<String, dynamic>>[
        <String, dynamic>{
          'service_category': 'limousine',
          'service_class': 'stretch_limousine',
          'is_active': true,
        },
      ],
    });
    expect(
      serverReady.state,
      LimousinePublicAvailabilityState.publiclyAvailable,
    );
    expect(
      limousineAvailabilityStateLabelFor(serverReady.state, AppLanguage.nl),
      'Gepubliceerd en zichtbaar',
    );
  });

  test('publish confirmation fails closed without projected offers', () {
    expect(
      limousinePricingPublishConfirmedVisible(<String, dynamic>{
        'ok': true,
        'limousine': <String, dynamic>{'source_revision': 5},
      }),
      isFalse,
    );
    expect(
      limousinePricingPublishConfirmedVisible(<String, dynamic>{
        'ok': true,
        'public_projected_offer_count': 1,
        'discovery_listable': true,
        'visibility_ok': true,
        'source_revision': 5,
      }),
      isTrue,
    );
    expect(limousinePricingResponseRevision(<String, dynamic>{
      'source_revision': 5,
      'limousine': <String, dynamic>{'source_revision': 4},
    }), 5);
    expect(
      limousinePricingSaveIsStaleConflict(Exception('stale_source_revision')),
      isTrue,
    );
  });

  testWidgets('publish does one request with published=true and stores N+1', (
    tester,
  ) async {
    final saves = <Map<String, dynamic>>[];
    await tester.pumpWidget(
      _app(
        LimousineBusinessSetupPage(
          loadPricing: () async => <String, dynamic>{
            'limousine': <String, dynamic>{
              'enabled': true,
              'source_revision': 3,
              'offers': <Map<String, dynamic>>[_offer(published: true)],
              'public_title': <String, String>{'nl': 'Maison'},
              'public_description': <String, String>{'nl': 'Limousines'},
            },
          },
          savePricing: (section) async {
            saves.add(Map<String, dynamic>.from(section));
            return <String, dynamic>{
              'limousine': <String, dynamic>{
                'source_revision': 4,
                'enabled': true,
                'offers': section['offers'],
              },
              'source_revision': 4,
              'public_projected_offer_count': 1,
              'discovery_listable': true,
              'visibility_ok': true,
            };
          },
          persistVehicles: (_) async {},
          vehicles: <VehicleProfile>[_limo()],
          knownClassIds: const <String>['stretch_limousine'],
          language: AppLanguage.nl,
        ),
      ),
    );
    await tester.pumpAndSettle();
    tester
            .widget<ButtonStyleButton>(
              find.byKey(kLimousineBusinessSetupPublishKey),
            )
            .onPressed!();
    await tester.pumpAndSettle();
    expect(saves, hasLength(1));
    expect(saves.single['source_revision'], 3);
    expect(
      (saves.single['offers'] as List).cast<Map>().first['published'],
      isTrue,
    );
    expect(
      find.text(kLimousineBusinessSetupTestMessage.of(AppLanguage.nl)),
      findsWidgets,
    );
  });

  testWidgets('409 stale conflict is not treated as success', (tester) async {
    await tester.pumpWidget(
      _app(
        LimousineBusinessSetupPage(
          loadPricing: () async => <String, dynamic>{
            'limousine': <String, dynamic>{
              'enabled': true,
              'source_revision': 3,
              'offers': <Map<String, dynamic>>[_offer(published: true)],
              'public_title': <String, String>{'nl': 'Maison'},
              'public_description': <String, String>{'nl': 'Limousines'},
            },
          },
          savePricing: (_) async =>
              throw Exception('stale_source_revision 409'),
          persistVehicles: (_) async {},
          vehicles: <VehicleProfile>[_limo()],
          knownClassIds: const <String>['stretch_limousine'],
          language: AppLanguage.nl,
        ),
      ),
    );
    await tester.pumpAndSettle();
    tester
            .widget<ButtonStyleButton>(
              find.byKey(kLimousineBusinessSetupPublishKey),
            )
            .onPressed!();
    await tester.pumpAndSettle();
    expect(
      find.text(kLimousinePricingStaleConflict.of(AppLanguage.nl)),
      findsOneWidget,
    );
    expect(find.byKey(kLimousineBusinessSetupErrorKey), findsOneWidget);
    expect(find.byKey(kLimousineBusinessSetupStatusKey), findsNothing);
    expect(
      find.text(kLimousineBusinessSetupDraftSaved.of(AppLanguage.nl)),
      findsNothing,
    );
  });

  testWidgets('gate-off message appears once in review', (tester) async {
    await tester.pumpWidget(
      _app(
        LimousineBusinessSetupPage(
          loadPricing: () async => <String, dynamic>{
            'limousine': <String, dynamic>{
              'offers': <Map<String, dynamic>>[_offer()],
            },
          },
          savePricing: (_) async => <String, dynamic>{},
          vehicles: <VehicleProfile>[_limo()],
          knownClassIds: const <String>['stretch_limousine'],
          language: AppLanguage.nl,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(kLimousineGatesOffFriendly.of(AppLanguage.nl)),
      findsOneWidget,
    );
  });
}
