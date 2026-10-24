import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/customer_theme_store.dart';
import 'package:fluxidi_tracking/limousine/limousine_brand_logo.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote.dart';
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1a_ux.dart';
import 'package:fluxidi_tracking/limousine/limousine_provider_showroom.dart';
import 'package:fluxidi_tracking/limousine/limousine_provider_showroom_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_public_copy.dart';
import 'package:fluxidi_tracking/limousine/limousine_public_showroom_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_adaptive_vehicle_photo.dart';
import 'package:fluxidi_tracking/limousine/limousine_vehicle_detail_page.dart';

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

LimousinePublishedOffer _quoteOffer() {
  return LimousinePublishedOffer.fromJson(<String, dynamic>{
    'offer_id': 'off_quote',
    'published': true,
    'enabled': true,
    'price_presentation': 'quote_required',
    'title': <String, String>{'nl': '', 'en': '', 'fr': '', 'es': ''},
  });
}

LimousinePublishedOffer _weddingOffer() {
  return LimousinePublishedOffer.fromJson(<String, dynamic>{
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
  });
}

LimousineShowroomVehicle _vehicle({
  String name = 'Party Limo',
  List<String> photos = const <String>[
    'https://cdn.example/party.jpg',
    'https://cdn.example/party-int.jpg',
  ],
  List<String> features = const <String>[],
  List<LimousinePublishedOffer> offers = const <LimousinePublishedOffer>[],
}) {
  return LimousineShowroomVehicle(
    key: 'veh_party',
    name: name,
    photoUrls: photos,
    passengerCapacity: 8,
    luggageCapacity: 4,
    features: features,
    offers: offers,
  );
}

Widget _app(Widget child, {Size size = kLimousinePhonePortrait}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: child,
    ),
  );
}

Widget _detail({
  required LimousineShowroomVehicle vehicle,
  String companyName = 'Maison Noire',
  String logoUrl = '',
  ImageProvider? logoImage,
}) {
  return LimousineVehicleDetailPage(
    vehicle: vehicle,
    companyName: companyName,
    partnerId: 'limo_1',
    logoUrl: logoUrl,
    logoImage: logoImage,
  );
}

void main() {
  setUp(() {
    appLanguageNotifier.value = AppLanguage.nl;
    customerThemeNotifier.value = CustomerThemeVariant.premiumLight;
  });

  tearDown(() {
    appLanguageNotifier.value = AppLanguage.nl;
    customerThemeNotifier.value = CustomerThemeVariant.premiumLight;
  });

  test('comfort copy hides title-only values and keeps real descriptions', () {
    expect(
      limousineMeaningfulComfortFeatures(const <String>['comfort']),
      isEmpty,
    );
    expect(
      limousineMeaningfulComfortFeatures(const <String>['Comfort']),
      isEmpty,
    );
    expect(
      limousineMeaningfulComfortFeatures(const <String>['  Comfort  ']),
      isEmpty,
    );
    expect(
      limousineMeaningfulComfortFeatures(const <String>['confort']),
      isEmpty,
    );
    expect(
      limousineMeaningfulComfortFeatures(const <String>[
        'Comfort',
        'Lederen zetels, minibar en sfeerverlichting',
      ]),
      <String>['Lederen zetels, minibar en sfeerverlichting'],
    );
    expect(
      limousineShouldShowOfferKindEyebrow(
        'Prijs op aanvraag',
        'Prijs op aanvraag',
      ),
      isFalse,
    );
    expect(limousineShouldShowOfferKindEyebrow('Vaste prijs', '€450'), isTrue);
  });

  test(
    'detail and discovery sources never hardcode Fluxidi or overlay logos',
    () {
      final detail = File(
        'lib/limousine/limousine_vehicle_detail_page.dart',
      ).readAsStringSync();
      final discovery = File(
        'lib/limousine/limousine_customer_discovery_page.dart',
      ).readAsStringSync();
      expect(detail.contains('LimousineBrandLogoCorner'), isFalse);
      expect(detail.contains('LimousineBrandLogoPlaque'), isFalse);
      expect(detail.contains("'Fluxidi'"), isFalse);
      expect(detail.contains('"Fluxidi"'), isFalse);
      expect(discovery.contains('LimousineBrandLogoCorner'), isFalse);
      expect(discovery.contains('LimousineBrandLogoPlaque'), isFalse);
      expect(discovery.contains("'Fluxidi'"), isFalse);
    },
  );

  testWidgets(
    'detail logo sits under thumbnails, above the vehicle name, never on the photo',
    (tester) async {
      await tester.binding.setSurfaceSize(kLimousineSmX400Portrait);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _app(
          _detail(
            vehicle: _vehicle(),
            logoUrl: 'https://cdn.example/logo.png',
            logoImage: MemoryImage(_kTinyPng),
          ),
          size: kLimousineSmX400Portrait,
        ),
      );
      await tester.pump();

      expect(find.byType(LimousineBrandLogoCorner), findsNothing);
      expect(find.byType(LimousineBrandLogoPlaque), findsNothing);
      expect(find.byKey(kLimousineDetailCompanyLogoKey), findsOneWidget);
      expect(find.byKey(kLimousineDetailCompanyNameFallbackKey), findsNothing);
      expect(find.text('Maison Noire'), findsNothing);
      expect(find.text('Fluxidi'), findsNothing);
      expect(find.text('Party Limo'), findsOneWidget);

      final photo = tester.getRect(
        find.byType(LimousineAdaptiveVehiclePhoto).first,
      );
      final thumbs = tester.getRect(
        find.byKey(kLimousineDetailGalleryThumbsKey),
      );
      final logo = tester.getRect(find.byKey(kLimousineDetailCompanyLogoKey));
      final title = tester.getRect(find.byKey(kLimousineDetailVehicleTitleKey));
      expect(photo.overlaps(logo), isFalse);
      expect(thumbs.overlaps(logo), isFalse);
      expect(logo.top, greaterThanOrEqualTo(thumbs.bottom - 0.5));
      expect(title.top, greaterThanOrEqualTo(logo.bottom - 0.5));
      expect(logo.height, 36);
      expect(logo.width, lessThanOrEqualTo(140));
      expect(logo.left, lessThan(title.left + 1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('missing logo falls back to the real company name once', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(_detail(vehicle: _vehicle(photos: const <String>[]))),
    );
    await tester.pump();
    expect(find.byKey(kLimousineDetailCompanyLogoKey), findsNothing);
    expect(find.byKey(kLimousineDetailCompanyNameFallbackKey), findsOneWidget);
    expect(find.text('Maison Noire'), findsOneWidget);
    expect(find.text('Fluxidi'), findsNothing);
    expect(find.text('Party Limo'), findsOneWidget);
    expect(find.byType(LimousineBrandLogoPlaque), findsNothing);
  });

  testWidgets(
    'Comfort is hidden for title-only values and shown for real copy',
    (tester) async {
      await tester.pumpWidget(
        _app(
          _detail(vehicle: _vehicle(features: const <String>['  Comfort  '])),
        ),
      );
      await tester.pump();
      expect(find.byKey(kLimousineDetailComfortSectionKey), findsNothing);
      expect(find.text('Comfort'), findsNothing);
      expect(find.text('comfort'), findsNothing);

      await tester.pumpWidget(
        _app(
          _detail(
            vehicle: _vehicle(
              features: const <String>[
                'comfort',
                'Lederen zetels, minibar en sfeerverlichting',
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(kLimousineDetailComfortSectionKey), findsOneWidget);
      expect(find.text('Comfort'), findsOneWidget);
      expect(find.text('comfort'), findsNothing);
      expect(
        find.text('Lederen zetels, minibar en sfeerverlichting'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'quote-on-request price appears once; named prices keep both lines',
    (tester) async {
      await tester.pumpWidget(
        _app(
          _detail(
            vehicle: _vehicle(offers: <LimousinePublishedOffer>[_quoteOffer()]),
          ),
        ),
      );
      await tester.pump();
      await tester.ensureVisible(find.byKey(kLimousineDetailPricesSectionKey));
      expect(find.text(kLimousineDetailPricesHeading.nl), findsOneWidget);
      expect(find.text(kLimousineShowroomPriceOnRequest.nl), findsOneWidget);
      expect(find.byKey(kLimousineDetailOfferKindEyebrowKey), findsNothing);
      expect(find.byKey(kLimousineDetailOfferPriceKey), findsOneWidget);

      await tester.pumpWidget(
        _app(
          _detail(
            vehicle: _vehicle(
              offers: <LimousinePublishedOffer>[_weddingOffer()],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Wedding Premium'), findsOneWidget);
      expect(find.text('€450'), findsOneWidget);
      expect(find.byKey(kLimousineDetailOfferKindEyebrowKey), findsOneWidget);
      expect(find.text('Vaste prijs'), findsOneWidget);
      expect(find.text('Prijs op aanvraag'), findsNothing);
    },
  );

  testWidgets('phone and tablet detail layouts stay inside the viewport', (
    tester,
  ) async {
    Future<void> pump(Size size) async {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        _app(
          _detail(
            vehicle: _vehicle(
              features: const <String>[
                'Lederen zetels, minibar en sfeerverlichting',
              ],
              offers: <LimousinePublishedOffer>[_weddingOffer()],
            ),
            logoUrl: 'https://cdn.example/wide-logo.png',
            logoImage: MemoryImage(_kTinyPng),
          ),
          size: size,
        ),
      );
      await tester.pump();
      expect(find.byType(LimousineBrandLogoCorner), findsNothing);
      expect(find.byKey(kLimousineDetailCompanyLogoKey), findsOneWidget);
      final logo = tester.getRect(find.byKey(kLimousineDetailCompanyLogoKey));
      expect(
        logo.width,
        lessThanOrEqualTo(
          limousineCompanyIdentityLogoMaxWidth(
            size,
            LimousineCompanyIdentitySurface.vehicleDetail,
          ),
        ),
      );
      expect(
        logo.height,
        limousineCompanyIdentityLogoHeight(
          size,
          LimousineCompanyIdentitySurface.vehicleDetail,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Party Limo'), findsOneWidget);
    }

    await pump(kLimousinePhonePortrait);
    await pump(kLimousineSmX400Portrait);
    await pump(kLimousineTabletLandscape);
    addTearDown(() => tester.binding.setSurfaceSize(null));
  });
}
