import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/customer_theme_store.dart';
import 'package:fluxidi_tracking/limousine/limousine_brand_logo.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_discovery.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_discovery_api.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_discovery_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote.dart';
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1a_ux.dart';
import 'package:fluxidi_tracking/limousine/limousine_provider_showroom.dart';
import 'package:fluxidi_tracking/limousine/limousine_provider_showroom_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_public_showroom_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_vehicle_detail_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_vehicle_media.dart';

final Uint8List _kTinyPng = Uint8List.fromList(<int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

const String _kLogoUrl = 'https://cdn.example/fluxidi-logo.png';
const String _kPhotoA = 'https://cdn.example/party-ext.jpg';
const String _kPhotoB = 'https://cdn.example/party-int.jpg';

Map<String, dynamic> _screenshotProfile() {
  return <String, dynamic>{
    'partner_id': 'limo_fluxidi',
    'company_name': 'Fluxidi',
    'is_active': true,
    'profile_enabled': true,
    'limousine_available': true,
    'limousine_service_enabled': true,
    'logo_url': _kLogoUrl,
    'public_city': 'Gent',
    'trust': <String, dynamic>{'verified_partner': true},
    'vehicles': <Map<String, dynamic>>[
      <String, dynamic>{
        'vehicle_id': 'veh_party',
        'name': 'Party Limo',
        'service_category': 'limousine',
        'service_class': 'party_stretch',
        'pax': 16,
        'luggage': 6,
        'features': <String>['comfort'],
        'photo_url': _kPhotoA,
        'gallery_photo_urls': <String>[_kPhotoA, _kPhotoB],
        'is_active': true,
      },
    ],
    'limousine_offers': <Map<String, dynamic>>[
      <String, dynamic>{
        'offer_id': 'off_party',
        'published': true,
        'enabled': true,
        'target_type': 'vehicle',
        'vehicle_id': 'veh_party',
        'price_presentation': 'quote_required',
        'title': <String, String>{
          'nl': 'Prijs op aanvraag',
          'en': 'Price on request',
          'fr': 'Prix sur demande',
          'es': 'Precio bajo petición',
        },
      },
    ],
  };
}

LimousineDiscoveryCard _screenshotCard() {
  return LimousineDiscoveryCard(
    publicPartnerId: 'limo_fluxidi',
    companyName: 'Fluxidi',
    coverImageUrl: _kPhotoA,
    logoUrl: _kLogoUrl,
    logoImage: MemoryImage(_kTinyPng),
    verifiedPartner: true,
    publicCity: 'Gent',
    vehicles: const <LimousineDiscoveryVehicleThumb>[
      LimousineDiscoveryVehicleThumb(
        serviceClassId: 'party_stretch',
        passengerCapacity: 16,
        luggageCapacity: 6,
        photoUrl: _kPhotoA,
      ),
    ],
    price: const LimousineDiscoveryPrice(
      kind: LimousineDiscoveryPriceKind.quoteRequired,
    ),
    testPreview: true,
  );
}

LimousineShowroomVehicle _screenshotVehicle({
  List<LimousinePublishedOffer>? offers,
}) {
  return LimousineShowroomVehicle(
    key: 'veh_party',
    name: 'Party Limo',
    serviceClassId: 'party_stretch',
    photoUrls: const <String>[_kPhotoA, _kPhotoB],
    passengerCapacity: 16,
    luggageCapacity: 6,
    features: const <String>['comfort'],
    vehicleId: 'veh_party',
    offers:
        offers ??
        <LimousinePublishedOffer>[
          LimousinePublishedOffer.fromJson(<String, dynamic>{
            'offer_id': 'off_party',
            'published': true,
            'enabled': true,
            'price_presentation': 'quote_required',
            'title': <String, String>{
              'nl': 'Prijs op aanvraag',
              'en': 'Price on request',
              'fr': 'Prix sur demande',
              'es': 'Precio bajo petición',
            },
          }),
        ],
  );
}

Widget _app(Widget child, {Size size = kLimousineSmX400Portrait}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: child,
    ),
  );
}

LimousineCustomerDiscoveryPage _discoveryPage({
  required MemoryLimousineDiscoveryGateway gateway,
  required LimousineDiscoveryController controller,
}) {
  return LimousineCustomerDiscoveryPage(
    gateway: gateway,
    controller: controller,
    customerHomeBuilder: (_) => const SizedBox.shrink(),
    autoLoadRecommended: false,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    appLanguageNotifier.value = AppLanguage.nl;
    customerThemeNotifier.value = CustomerThemeVariant.premiumLight;
  });

  tearDown(() {
    appLanguageNotifier.value = AppLanguage.nl;
    customerThemeNotifier.value = CustomerThemeVariant.premiumLight;
  });

  test('customer home opens the same discovery page used at runtime', () {
    final source = File(
      'lib/main_parts/customer_home_page.dart',
    ).readAsStringSync();
    expect(source.contains('openLimousineCustomerDiscovery('), isTrue);
    expect(source.contains('LimousineCustomerDiscoveryPage('), isFalse);
  });

  testWidgets(
    'runtime discovery card keeps the logo off the photo and hides Fluxidi',
    (tester) async {
      final gateway = MemoryLimousineDiscoveryGateway();
      final controller = LimousineDiscoveryController(gateway: gateway);
      controller.phase = LimousineDiscoveryPhase.ready;
      controller.cards = <LimousineDiscoveryCard>[_screenshotCard()];

      await tester.binding.setSurfaceSize(kLimousineSmX400Portrait);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _app(_discoveryPage(gateway: gateway, controller: controller)),
      );
      await tester.pump();

      final card = find.byKey(limousineDiscoveryCardKey('limo_fluxidi'));
      expect(card, findsOneWidget);
      expect(find.byType(LimousineCustomerDiscoveryPage), findsOneWidget);
      expect(find.byType(LimousineBrandLogoCorner), findsNothing);
      expect(find.byType(LimousineBrandLogoPlaque), findsNothing);
      expect(
        find.descendant(
          of: find.byType(LimousineContainPhoto),
          matching: find.byKey(kLimousineDiscoveryCompanyLogoKey),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(LimousineContainPhoto),
          matching: find.byType(LimousineBrandLogoCorner),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: card,
          matching: find.byKey(kLimousineDiscoveryCompanyLogoKey),
        ),
        findsOneWidget,
      );
      expect(find.text('Fluxidi'), findsNothing);
      expect(find.text('Bekijk aanbod'), findsOneWidget);
      expect(find.text('Bekijk profiel'), findsOneWidget);

      final photo = tester.getRect(
        find.descendant(of: card, matching: find.byType(LimousineContainPhoto)),
      );
      final logo = tester.getRect(
        find.byKey(kLimousineDiscoveryCompanyLogoKey),
      );
      expect(photo.overlaps(logo), isFalse);
      expect(logo.left, greaterThan(photo.right - 1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'runtime detail page matches the Meer-info order and hides duplicate copy',
    (tester) async {
      await tester.binding.setSurfaceSize(kLimousineSmX400Portrait);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _app(
          LimousineVehicleDetailPage(
            vehicle: _screenshotVehicle(),
            companyName: 'Fluxidi',
            partnerId: 'limo_fluxidi',
            logoUrl: _kLogoUrl,
            logoImage: MemoryImage(_kTinyPng),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(kLimousineVehicleDetailPageKey), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(kLimousineVehicleDetailPageKey),
          matching: find.byType(LimousineBrandLogoCorner),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(LimousineContainPhoto),
          matching: find.byKey(kLimousineDetailCompanyLogoKey),
        ),
        findsNothing,
      );
      expect(find.byKey(kLimousineDetailCompanyLogoKey), findsOneWidget);
      expect(find.text('Fluxidi'), findsNothing);
      expect(find.text('Party Limo'), findsOneWidget);
      expect(find.byKey(kLimousineDetailComfortSectionKey), findsNothing);
      expect(find.text('Comfort'), findsNothing);
      expect(find.text('comfort'), findsNothing);
      await tester.ensureVisible(find.byKey(kLimousineDetailPricesSectionKey));
      expect(find.text(kLimousineDetailPricesHeading.nl), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(limousineDetailOfferCardKey('off_party')),
          matching: find.text(kLimousineShowroomPriceOnRequest.nl),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(limousineDetailOfferCardKey('off_party')),
          matching: find.byKey(kLimousineDetailOfferKindEyebrowKey),
        ),
        findsNothing,
      );

      final thumbs = tester.getRect(
        find.byKey(kLimousineDetailGalleryThumbsKey),
      );
      final logo = tester.getRect(find.byKey(kLimousineDetailCompanyLogoKey));
      final title = tester.getRect(find.byKey(kLimousineDetailVehicleTitleKey));
      expect(thumbs.overlaps(logo), isFalse);
      expect(logo.top, greaterThanOrEqualTo(thumbs.bottom - 0.5));
      expect(title.top, greaterThanOrEqualTo(logo.bottom - 0.5));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Bekijk aanbod then Meer info opens the same runtime detail widget',
    (tester) async {
      final profile = _screenshotProfile();
      final gateway = MemoryLimousineDiscoveryGateway(
        profileHandler: (_) async => profile,
      );
      final controller = LimousineDiscoveryController(gateway: gateway);
      controller.phase = LimousineDiscoveryPhase.ready;
      controller.cards = <LimousineDiscoveryCard>[_screenshotCard()];

      await tester.binding.setSurfaceSize(kLimousineSmX400Portrait);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _app(_discoveryPage(gateway: gateway, controller: controller)),
      );
      await tester.pump();

      tester
          .widget<ButtonStyleButton>(
            find.byKey(limousineDiscoveryOffersCtaKey('limo_fluxidi')),
          )
          .onPressed!();
      await tester.pumpAndSettle();
      expect(find.byKey(kLimousineProviderShowroomPageKey), findsOneWidget);
      expect(find.text('Party Limo'), findsWidgets);

      tester
          .widget<ButtonStyleButton>(
            find.byKey(limousineShowroomMoreInfoCtaKey('veh_party')),
          )
          .onPressed!();
      await tester.pumpAndSettle();
      expect(find.byKey(kLimousineVehicleDetailPageKey), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(kLimousineVehicleDetailPageKey),
          matching: find.byType(LimousineBrandLogoCorner),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(kLimousineVehicleDetailPageKey),
          matching: find.byKey(kLimousineDetailCompanyLogoKey),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(kLimousineVehicleDetailPageKey),
          matching: find.text('Fluxidi'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(kLimousineVehicleDetailPageKey),
          matching: find.text('Party Limo'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(kLimousineVehicleDetailPageKey),
          matching: find.byKey(kLimousineDetailComfortSectionKey),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(limousineDetailOfferCardKey('off_party')),
          matching: find.text(kLimousineShowroomPriceOnRequest.nl),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'distinct arrangement name and price both stay visible on the same card',
    (tester) async {
      await tester.pumpWidget(
        _app(
          LimousineVehicleDetailPage(
            vehicle: _screenshotVehicle(
              offers: <LimousinePublishedOffer>[
                LimousinePublishedOffer.fromJson(<String, dynamic>{
                  'offer_id': 'off_wedding',
                  'published': true,
                  'enabled': true,
                  'price_presentation': 'exact_fixed',
                  'display_amount_cents': 45000,
                  'currency': 'EUR',
                  'title': <String, String>{
                    'nl': 'Wedding Premium',
                    'en': 'Wedding Premium',
                    'fr': 'Wedding Premium',
                    'es': 'Wedding Premium',
                  },
                }),
              ],
            ),
            companyName: 'Fluxidi',
            partnerId: 'limo_fluxidi',
            logoUrl: _kLogoUrl,
            logoImage: MemoryImage(_kTinyPng),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Wedding Premium'), findsOneWidget);
      expect(find.text('€450'), findsOneWidget);
      expect(find.byKey(kLimousineDetailOfferKindEyebrowKey), findsOneWidget);
      expect(find.text('Prijs op aanvraag'), findsNothing);
      expect(find.text('Fluxidi'), findsNothing);
    },
  );
}
