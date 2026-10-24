import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/customer_theme_store.dart';
import 'package:fluxidi_tracking/limousine/limousine_brand_logo.dart';
import 'package:fluxidi_tracking/limousine/limousine_business_setup.dart';
import 'package:fluxidi_tracking/limousine/limousine_business_setup_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_business_setup_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_discovery.dart';
import 'package:fluxidi_tracking/limousine/limousine_hero_contract.dart';
import 'package:fluxidi_tracking/limousine/limousine_offers.dart';
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1a_ux.dart';
import 'package:fluxidi_tracking/limousine/limousine_pricing_local_store.dart';
import 'package:fluxidi_tracking/limousine/limousine_pricing_overlay.dart';
import 'package:fluxidi_tracking/limousine/limousine_profile_identity.dart';
import 'package:fluxidi_tracking/limousine/limousine_provider_showroom.dart';
import 'package:fluxidi_tracking/limousine/limousine_setup_media_pick.dart';
import 'package:fluxidi_tracking/vehicle_management_page.dart';

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

const String _kLogo =
    'https://cdn.example/public-media/t1/c1/limousine/profile-logo.png';
const String _kPrevLogo =
    'https://cdn.example/public-media/t1/c1/limousine/profile-logo-prev.png';
const String _kTaxiLogo =
    'https://cdn.example/public-media/t1/c1/company/logo.png';
const String _kTaxiHero =
    'https://cdn.example/public-media/t1/c1/company/hero.jpg';
const String _kContentUri = 'content://media/external/images/media/88';
const String _kPartnerId = 'limo_fluxidi';

VehicleProfile _vehicle({
  required String id,
  required String name,
  int pax = 16,
}) {
  return VehicleProfile(
    id: id,
    vehicleName: name,
    brandModel: name,
    licensePlate: '1-ABC-123',
    color: 'white',
    passengerCapacity: pax,
    luggageCapacity: 3,
    tierId: 'premium',
    isActive: true,
    driverId: null,
    primaryPhotoRef: 'https://cdn.example/$id.jpg',
    galleryPhotoRefs: const <String>[],
    publicPhotoUrl: 'https://cdn.example/$id.jpg',
    serviceCategory: 'limousine',
    serviceClassId: 'stretch_limousine',
  );
}

Map<String, dynamic> _offer() {
  return <String, dynamic>{
    'offer_id': 'off_from_250',
    'enabled': true,
    'published': true,
    'target_type': LimousineOfferTarget.serviceClass,
    'price_presentation': LimousinePricePresentation.fromPrice,
    'display_amount_cents': 25000,
    'currency': 'EUR',
    'title': const <String, String>{'nl': 'Avond'},
    'description': const <String, String>{'nl': 'Avondrit'},
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MemoryLimousinePricingLocalStore store;
  late List<Map<String, dynamic>> saves;
  late List<Map<String, String>> uploads;
  late List<Uint8List> uploadBytes;
  late List<VehicleProfile> vehicles;
  var pickCalls = 0;
  var returnLocalUri = false;
  Completer<LimousineSetupPickedImage?>? delayedPick;
  LimousineSetupPickedImage? nextPick;
  String taxiLogoSnapshot = _kTaxiLogo;
  String taxiHeroSnapshot = _kTaxiHero;

  setUp(() {
    store = MemoryLimousinePricingLocalStore();
    limousinePricingLocalStore = store;
    saves = <Map<String, dynamic>>[];
    uploads = <Map<String, String>>[];
    uploadBytes = <Uint8List>[];
    pickCalls = 0;
    returnLocalUri = false;
    delayedPick = null;
    nextPick = LimousineSetupPickedImage(
      path: _kContentUri,
      name: 'logo.png',
      bytes: _kTinyPng,
    );
    vehicles = <VehicleProfile>[
      _vehicle(id: 'vh_party', name: 'Party Limo'),
      _vehicle(id: 'vh_hummer', name: 'Hummer white', pax: 8),
    ];
    appLanguageNotifier.value = AppLanguage.nl;
    customerThemeNotifier.value = CustomerThemeVariant.premiumLight;
  });

  tearDown(() {
    limousinePricingLocalStore = FileLimousinePricingLocalStore();
  });

  Future<Map<String, dynamic>> loadPricing() async {
    return <String, dynamic>{
      'limousine': <String, dynamic>{
        'enabled': true,
        'source_revision': 1,
        'offers': <Map<String, dynamic>>[_offer()],
        'public_hero_photo_url': taxiHeroSnapshot,
      },
    };
  }

  Future<Map<String, dynamic>> savePricing(Map<String, dynamic> section) async {
    saves.add(Map<String, dynamic>.from(section));
    return <String, dynamic>{
      'ok': true,
      'limousine': <String, dynamic>{
        'enabled': true,
        'source_revision': 2,
        'offers': section['offers'],
      },
    };
  }

  Future<LimousineSetupPickedImage?> pickImage() async {
    pickCalls += 1;
    if (delayedPick != null) return delayedPick!.future;
    return nextPick;
  }

  Future<Map<String, dynamic>> uploadMedia({
    required String mediaType,
    required String filePath,
    required String filename,
    Uint8List? fileBytes,
  }) async {
    uploads.add(<String, String>{
      'mediaType': mediaType,
      'filePath': filePath,
      'filename': filename,
      'hasBytes': (fileBytes != null && fileBytes.isNotEmpty).toString(),
    });
    uploadBytes.add(fileBytes ?? Uint8List(0));
    if (returnLocalUri) return <String, dynamic>{'url': filePath};
    if (mediaType == kLimousineProfileLogoMediaType) {
      return <String, dynamic>{'url': _kLogo};
    }
    return <String, dynamic>{
      'url':
          'https://cdn.example/public-media/t1/c1/limousine/profile-cover.jpg',
    };
  }

  Widget setupPage({
    Size size = kLimousineSmX400Portrait,
    Future<Map<String, dynamic>> Function()? load,
  }) {
    return _app(
      LimousineBusinessSetupPage(
        loadPricing: load ?? loadPricing,
        savePricing: savePricing,
        persistVehicles: (_) async {},
        vehicles: vehicles,
        knownClassIds: const <String>['stretch_limousine'],
        entryEnabled: true,
        language: AppLanguage.nl,
        companyName: 'Fluxidi',
        logoUrl: taxiLogoSnapshot,
        pickImage: pickImage,
        uploadMedia: uploadMedia,
      ),
      size: size,
    );
  }

  Future<void> pumpSetup(
    WidgetTester tester, {
    Size size = kLimousineSmX400Portrait,
    Future<Map<String, dynamic>> Function()? load,
  }) async {
    await tester.binding.setSurfaceSize(size);
    await tester.pumpWidget(setupPage(size: size, load: load));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> pumpUpload(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  Future<void> fillVisitingCard(WidgetTester tester) async {
    await tester.ensureVisible(
      find.byKey(kLimousineBusinessSetupPublicTitleKey),
    );
    await tester.enterText(
      find.byKey(kLimousineBusinessSetupPublicTitleKey),
      'Fluxidi',
    );
    await tester.enterText(
      find.byKey(kLimousineBusinessSetupPublicDescriptionKey),
      'Voor elke gelegenheid',
    );
    await tester.pump();
  }

  LimousineSetupLogoPreview logoPreview(WidgetTester tester) {
    return tester.widget<LimousineSetupLogoPreview>(
      find.descendant(
        of: find.byKey(kLimousineBusinessSetupLogoPreviewKey),
        matching: find.byType(LimousineSetupLogoPreview),
      ),
    );
  }

  Image logoImage(WidgetTester tester) {
    return tester.widget<Image>(
      find.descendant(
        of: find.byKey(kLimousineBusinessSetupLogoPreviewKey),
        matching: find.byType(Image),
      ),
    );
  }

  Map<String, dynamic> nearbyPartner() {
    return <String, dynamic>{
      'partner_id': _kPartnerId,
      'company_name': 'Fluxidi',
      'is_active': true,
      'profile_enabled': true,
      'limousine_available': true,
      'limousine_service_enabled': true,
      'logo_url': _kTaxiLogo,
      'hero_photo_url': _kTaxiHero,
      'limousine_vehicles': <Map<String, dynamic>>[
        <String, dynamic>{
          'vehicle_id': 'vh_party',
          'service_category': 'limousine',
          'is_active': true,
          'photo_url': 'https://cdn.example/party.jpg',
          'passenger_capacity': 16,
        },
      ],
      'limousine_offers': <Map<String, dynamic>>[_offer()],
    };
  }

  testWidgets(
    '1-5 logo picker reads content URI, uploads bytes, shows full mark',
    (tester) async {
      delayedPick = Completer<LimousineSetupPickedImage?>();
      await pumpSetup(tester);
      await tester.ensureVisible(
        find.byKey(kLimousineBusinessSetupLogoPickKey),
      );
      expect(find.text(kLimousineBusinessSetupLogoPick.nl), findsOneWidget);
      await tester.tap(find.byKey(kLimousineBusinessSetupLogoPickKey));
      await tester.pump();

      expect(pickCalls, 1);
      expect(
        find.byKey(kLimousineBusinessSetupLogoUploadingKey),
        findsOneWidget,
      );

      delayedPick!.complete(nextPick);
      await pumpUpload(tester);

      expect(uploads, hasLength(1));
      expect(uploads.single['mediaType'], kLimousineProfileLogoMediaType);
      expect(uploads.single['hasBytes'], 'true');
      expect(uploads.single['filePath'], isNot(contains('content://')));
      expect(limousineDetectImageMime(uploadBytes.single), 'image/png');
      expect(limousinePngHasAlpha(uploadBytes.single), isTrue);
      expect(saves, isNotEmpty);
      expect(
        (saves.last[kLimousineProfileLogoKey] as Map)['photo_url'],
        _kLogo,
      );
      expect(saves.last.toString(), isNot(contains('content://')));
      expect(saves.last.toString(), isNot(contains('file:')));
      expect(find.text(kLimousineBusinessSetupLogoReplace.nl), findsOneWidget);
      expect(
        find.text(kLimousineBusinessSetupLogoUploadSuccess.nl),
        findsWidgets,
      );
      expect(logoPreview(tester).imageUrl, _kLogo);
      expect(logoImage(tester).fit, BoxFit.contain);
      expect(taxiLogoSnapshot, _kTaxiLogo);
      expect(taxiHeroSnapshot, _kTaxiHero);
    },
  );

  testWidgets(
    '6 7 12 reopen and restart keep logo; failed upload keeps previous',
    (tester) async {
      await pumpSetup(
        tester,
        load: () async {
          return <String, dynamic>{
            'limousine': <String, dynamic>{
              'enabled': true,
              'offers': <Map<String, dynamic>>[_offer()],
              kLimousineProfileLogoKey: <String, dynamic>{
                'photo_url': _kPrevLogo,
                'explicit_override': true,
              },
            },
          };
        },
      );
      expect(logoPreview(tester).imageUrl, _kPrevLogo);

      returnLocalUri = true;
      await tester.ensureVisible(
        find.byKey(kLimousineBusinessSetupLogoReplaceKey),
      );
      await tester.tap(find.byKey(kLimousineBusinessSetupLogoReplaceKey));
      await pumpUpload(tester);
      expect(
        find.textContaining(kLimousineBusinessSetupLogoNotDurable.nl),
        findsWidgets,
      );
      expect(logoPreview(tester).imageUrl, _kPrevLogo);

      returnLocalUri = false;
      await tester.tap(find.byKey(kLimousineBusinessSetupLogoReplaceKey));
      await pumpUpload(tester);
      expect(logoPreview(tester).imageUrl, _kLogo);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await pumpSetup(tester);
      expect(find.text(kLimousineBusinessSetupLogoReplace.nl), findsOneWidget);
      expect(logoPreview(tester).imageUrl, _kLogo);
    },
  );

  testWidgets('8-11 publish snapshot, discovery and profile use override', (
    tester,
  ) async {
    await pumpSetup(tester);
    await tester.ensureVisible(find.byKey(kLimousineBusinessSetupLogoPickKey));
    await tester.tap(find.byKey(kLimousineBusinessSetupLogoPickKey));
    await pumpUpload(tester);
    await fillVisitingCard(tester);
    tester
        .widget<ButtonStyleButton>(
          find.byKey(kLimousineBusinessSetupPublishKey),
        )
        .onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final published = saves.last;
    final decoded = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(published)) as Map,
    );
    expect(
      (decoded[kLimousinePublishedProfileLogoKey] as Map)['photo_url'],
      _kLogo,
    );
    expect(decoded.toString(), isNot(contains(_kTaxiLogo)));
    expect(taxiLogoSnapshot, _kTaxiLogo);

    final partner = limousineHydratePublicPartnerOverlay(
      nearbyPartner(),
      store: store,
    );
    final card = tryParseLimousineDiscoveryCard(partner)!;
    expect(card.logoUrl, _kLogo);
    final showroom = buildLimousineProviderShowroomData(profile: partner);
    expect(showroom.logoUrl, _kLogo);
  });

  testWidgets('14 15 contain preview; clear restores company logo only', (
    tester,
  ) async {
    await pumpSetup(tester, size: kLimousinePhonePortrait);
    await tester.ensureVisible(find.byKey(kLimousineBusinessSetupLogoPickKey));
    expect(logoPreview(tester).imageUrl, _kTaxiLogo);
    expect(logoImage(tester).fit, BoxFit.contain);
    expect(
      find.text(kLimousineBusinessSetupLogoStatusCompany.nl),
      findsOneWidget,
    );

    await tester.tap(find.byKey(kLimousineBusinessSetupLogoPickKey));
    await pumpUpload(tester);
    expect(logoPreview(tester).imageUrl, _kLogo);
    expect(find.text(kLimousineBusinessSetupLogoStatusOwn.nl), findsOneWidget);

    await tester.tap(find.byKey(kLimousineBusinessSetupLogoClearKey));
    await pumpUpload(tester);
    expect(logoPreview(tester).imageUrl, _kTaxiLogo);
    expect(
      find.text(kLimousineBusinessSetupLogoStatusCompany.nl),
      findsOneWidget,
    );
    expect((saves.last[kLimousineProfileLogoKey] as Map)['photo_url'], isEmpty);
    expect(
      (saves.last[kLimousineProfileLogoKey] as Map)['explicit_override'],
      isFalse,
    );
    expect(taxiLogoSnapshot, _kTaxiLogo);
  });
}
