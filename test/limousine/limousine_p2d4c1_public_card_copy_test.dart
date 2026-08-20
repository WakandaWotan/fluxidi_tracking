import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/customer_theme_store.dart';
import 'package:fluxidi_tracking/limousine/limousine_business_setup.dart';
import 'package:fluxidi_tracking/limousine/limousine_business_setup_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_business_setup_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_discovery.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_discovery_api.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_discovery_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_offers.dart';
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1a_ux.dart';
import 'package:fluxidi_tracking/limousine/limousine_pricing_local_store.dart';
import 'package:fluxidi_tracking/limousine/limousine_public_company_card.dart';
import 'package:fluxidi_tracking/limousine/limousine_vehicle_media.dart';
import 'package:fluxidi_tracking/vehicle_management_page.dart';

const String _kPartnerId = 'limo_fluxidi';
const String _kTitle = 'Party Ride';
const String _kFullDescription =
    'Limoservice biedt een uitgebreid gamma aan unieke wagens voor elke gelegenheid.\n'
    'Flexibiliteit staat voorop: voor elk arrangement bieden we een oplossing op maat.\n'
    'Contacteer ons voor meer info.';

Map<String, dynamic> _nearby() {
  return <String, dynamic>{
    'partner_id': _kPartnerId,
    'company_name': 'Fluxidi BV',
    'is_active': true,
    'profile_enabled': true,
    'limousine_available': true,
    'limousine_service_enabled': true,
    'logo_url': 'https://cdn.example/fluxidi-logo.png',
    'published_public_title': const <String, String>{
      'nl': _kTitle,
      'en': _kTitle,
    },
    'published_public_description': const <String, String>{
      'nl': _kFullDescription,
      'en': _kFullDescription,
    },
    'published_limousine_hero': <String, dynamic>{
      'photo_url': 'https://cdn.example/white-stretch.jpg',
      'alignment': 'center',
    },
    'limousine_vehicles': <Map<String, dynamic>>[
      <String, dynamic>{
        'vehicle_id': 'vh_party',
        'name': 'Party Limo',
        'service_category': 'limousine',
        'is_active': true,
        'photo_url': 'https://cdn.example/party.jpg',
        'passenger_capacity': 16,
      },
      <String, dynamic>{
        'vehicle_id': 'vh_hummer',
        'name': 'Hummer white',
        'service_category': 'limousine',
        'is_active': true,
        'photo_url': 'https://cdn.example/hummer.jpg',
        'passenger_capacity': 8,
      },
    ],
    'limousine_offers': <Map<String, dynamic>>[
      <String, dynamic>{
        'offer_id': 'off_from_250',
        'enabled': true,
        'published': true,
        'price_presentation': 'from_price',
        'display_amount_cents': 25000,
        'currency': 'EUR',
      },
    ],
  };
}

Widget _app(Widget child, {Size size = kLimousineSmX400Portrait}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: child,
    ),
  );
}

void _expectCommercialFirstImpression(WidgetTester tester, Finder root) {
  expect(
    find.descendant(of: root, matching: find.text(_kTitle)),
    findsOneWidget,
  );
  expect(
    find.descendant(of: root, matching: find.text(_kFullDescription)),
    findsOneWidget,
  );
  expect(
    find.descendant(
      of: root,
      matching: find.textContaining(
        'Limoservice biedt een uitgebreid gamma aan unieke wagens',
      ),
    ),
    findsOneWidget,
  );
  expect(
    find.descendant(
      of: root,
      matching: find.textContaining('Flexibiliteit staat voorop'),
    ),
    findsOneWidget,
  );
  expect(
    find.descendant(
      of: root,
      matching: find.textContaining('Contacteer ons voor meer info.'),
    ),
    findsOneWidget,
  );
  expect(
    find.descendant(of: root, matching: find.textContaining('2 limousines')),
    findsNothing,
  );
  expect(
    find.descendant(of: root, matching: find.textContaining('tot 16 personen')),
    findsNothing,
  );
  expect(
    find.descendant(of: root, matching: find.textContaining('Vanaf €250')),
    findsNothing,
  );
  expect(
    find.descendant(of: root, matching: find.text('Party Limo · 2')),
    findsNothing,
  );
  expect(
    find.descendant(of: root, matching: find.text('Hummer white · 4')),
    findsNothing,
  );
  expect(
    find.descendant(of: root, matching: find.textContaining('Zichtbaar bij')),
    findsNothing,
  );
  expect(
    find.descendant(
      of: root,
      matching: find.text(kLimousineBusinessSetupAppliesTo.nl),
    ),
    findsNothing,
  );
  expect(
    find.descendant(of: root, matching: find.text('Bekijk aanbod')),
    findsOneWidget,
  );
  expect(
    find.descendant(of: root, matching: find.text('Meer info')),
    findsOneWidget,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MemoryLimousinePricingLocalStore store;

  setUp(() {
    store = MemoryLimousinePricingLocalStore();
    limousinePricingLocalStore = store;
    appLanguageNotifier.value = AppLanguage.nl;
    customerThemeNotifier.value = CustomerThemeVariant.premiumLight;
  });

  tearDown(() {
    limousinePricingLocalStore = FileLimousinePricingLocalStore();
  });

  test('description helper keeps entered line breaks', () {
    expect(
      limousinePublicCardDescriptionText(_kFullDescription).split('\n'),
      hasLength(3),
    );
    expect(
      limousineDiscoveryCardDescription(
        LimousineDiscoveryCard(
          publicPartnerId: _kPartnerId,
          companyName: 'Fluxidi',
          publicTitle: const <String, String>{'nl': _kTitle},
          publicDescription: const <String, String>{'nl': _kFullDescription},
        ),
        AppLanguage.nl,
      ),
      _kFullDescription,
    );
  });

  testWidgets('1-13 discovery card shows the full visiting-card copy only', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(kLimousineSmX400Portrait);
    final gateway = MemoryLimousineDiscoveryGateway(
      searchHandler: (_) async => LimousineDiscoveryPageData(
        listingMode: 'test_preview',
        cards: limousineDiscoveryCardsFromNearbyPartners(<dynamic>[_nearby()]),
      ),
    );
    await tester.pumpWidget(
      _app(
        LimousineCustomerDiscoveryPage(
          gateway: gateway,
          customerHomeBuilder: (_) => const SizedBox.shrink(),
        ),
        size: kLimousineSmX400Portrait,
      ),
    );
    await tester.pumpAndSettle();

    final card = find.byKey(limousineDiscoveryCardKey(_kPartnerId));
    _expectCommercialFirstImpression(tester, card);
    expect(find.text(_kFullDescription), findsOneWidget);

    final description = tester.widget<Text>(
      find.byKey(limousineDiscoveryCardDescriptionKey(_kPartnerId)),
    );
    expect(description.data, _kFullDescription);
    expect(description.data!.contains('\n'), isTrue);
    expect(description.maxLines, isNull);
    expect(description.overflow, isNot(TextOverflow.ellipsis));

    final titleRect = tester.getRect(
      find.byKey(limousineDiscoveryCardTitleKey(_kPartnerId)),
    );
    final descriptionRect = tester.getRect(
      find.byKey(limousineDiscoveryCardDescriptionKey(_kPartnerId)),
    );
    final coverRect = tester.getRect(
      find.byKey(limousineDiscoveryCardCoverKey(_kPartnerId)),
    );
    final offersRect = tester.getRect(
      find.byKey(limousineDiscoveryOffersCtaKey(_kPartnerId)),
    );
    expect(descriptionRect.top, greaterThan(titleRect.bottom - 1));
    expect(coverRect.overlaps(descriptionRect), isFalse);
    expect(offersRect.top, greaterThan(descriptionRect.bottom - 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('5 6 settings preview uses the same full public card copy', (
    tester,
  ) async {
    limousinePricingLocalStore = store;
    await tester.binding.setSurfaceSize(kLimousineSmX400Portrait);
    await tester.pumpWidget(
      _app(
        LimousineBusinessSetupPage(
          loadPricing: () async => <String, dynamic>{
            'limousine': <String, dynamic>{
              'enabled': true,
              'offers': <Map<String, dynamic>>[
                <String, dynamic>{
                  'offer_id': 'off_from_250',
                  'enabled': true,
                  'published': true,
                  'target_type': LimousineOfferTarget.serviceClass,
                  'price_presentation': LimousinePricePresentation.fromPrice,
                  'display_amount_cents': 25000,
                  'currency': 'EUR',
                  'title': const <String, String>{'nl': 'Avond'},
                  'description': const <String, String>{'nl': 'Avondrit'},
                },
              ],
              'public_title': const <String, String>{'nl': _kTitle},
              'public_description': const <String, String>{
                'nl': _kFullDescription,
              },
            },
          },
          savePricing: (_) async => <String, dynamic>{'ok': true},
          persistVehicles: (_) async {},
          vehicles: <VehicleProfile>[
            VehicleProfile(
              id: 'vh_party',
              vehicleName: 'Party Limo',
              brandModel: 'Party Limo',
              licensePlate: '1-ABC-123',
              color: 'white',
              passengerCapacity: 16,
              luggageCapacity: 3,
              tierId: 'premium',
              isActive: true,
              driverId: null,
              primaryPhotoRef: 'https://cdn.example/party.jpg',
              galleryPhotoRefs: const <String>[
                'https://cdn.example/party.jpg',
                'https://cdn.example/party-side.jpg',
              ],
              publicPhotoUrl: 'https://cdn.example/party.jpg',
              serviceCategory: 'limousine',
              serviceClassId: 'stretch_limousine',
            ),
            VehicleProfile(
              id: 'vh_hummer',
              vehicleName: 'Hummer white',
              brandModel: 'Hummer white',
              licensePlate: '1-XYZ-999',
              color: 'white',
              passengerCapacity: 8,
              luggageCapacity: 2,
              tierId: 'premium',
              isActive: true,
              driverId: null,
              primaryPhotoRef: 'https://cdn.example/hummer.jpg',
              galleryPhotoRefs: const <String>[
                'https://cdn.example/hummer.jpg',
                'https://cdn.example/hummer-rear.jpg',
                'https://cdn.example/hummer-side.jpg',
                'https://cdn.example/hummer-front.jpg',
              ],
              publicPhotoUrl: 'https://cdn.example/hummer.jpg',
              serviceCategory: 'limousine',
              serviceClassId: 'stretch_limousine',
            ),
          ],
          knownClassIds: const <String>['stretch_limousine'],
          entryEnabled: true,
          language: AppLanguage.nl,
          companyName: 'Fluxidi',
          logoUrl: 'https://cdn.example/public-media/t1/c1/company/logo.png',
        ),
        size: kLimousineSmX400Portrait,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    final preview = find.byKey(kLimousineBusinessSetupPreviewKey);
    await tester.ensureVisible(preview);
    await tester.pump();
    _expectCommercialFirstImpression(tester, preview);
    expect(
      find.descendant(
        of: preview,
        matching: find.byType(LimousinePublicCompanyCard),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: preview, matching: find.text(_kFullDescription)),
      findsOneWidget,
    );

    final description = tester.widget<Text>(
      find.byKey(
        limousineDiscoveryCardDescriptionKey(kLimousineSetupPreviewPartnerId),
      ),
    );
    expect(description.maxLines, isNull);
    expect(description.overflow, isNot(TextOverflow.ellipsis));
    expect(description.data!.split('\n'), hasLength(3));

    final cover = tester.getRect(
      find.descendant(
        of: preview,
        matching: find.byType(LimousineContainPhoto),
      ),
    );
    final descriptionRect = tester.getRect(
      find.byKey(
        limousineDiscoveryCardDescriptionKey(kLimousineSetupPreviewPartnerId),
      ),
    );
    expect(cover.overlaps(descriptionRect), isFalse);
    expect(tester.takeException(), isNull);
  });
}
