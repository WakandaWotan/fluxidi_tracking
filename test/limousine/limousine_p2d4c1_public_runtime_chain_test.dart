import 'dart:convert';
import 'dart:typed_data';

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
import 'package:fluxidi_tracking/limousine/limousine_hero_contract.dart';
import 'package:fluxidi_tracking/limousine/limousine_offer_binding.dart';
import 'package:fluxidi_tracking/limousine/limousine_offers.dart';
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1a_ux.dart';
import 'package:fluxidi_tracking/limousine/limousine_pricing_local_store.dart';
import 'package:fluxidi_tracking/limousine/limousine_pricing_overlay.dart';
import 'package:fluxidi_tracking/limousine/limousine_profile_identity.dart';
import 'package:fluxidi_tracking/limousine/limousine_provider_showroom.dart';
import 'package:fluxidi_tracking/limousine/limousine_vehicle_detail_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_vehicle_media.dart';
import 'package:fluxidi_tracking/limousine/limousine_vehicle_public_copy.dart';

final Uint8List _kTinyPng = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

const String _kPartnerId = 'limo_fluxidi';
const String _kPartyId = 'vh_party';
const String _kCover =
    'https://cdn.example/public-media/t1/c1/limousine/profile-cover.jpg';
const String _kLimoLogo =
    'https://cdn.example/public-media/t1/c1/limousine/profile-logo.png';
const String _kTaxiHero =
    'https://cdn.example/public-media/t1/c1/company/hero.jpg';
const String _kTaxiLogo =
    'https://cdn.example/public-media/t1/c1/company/logo.png';
const String _kLocalUri = 'file:///tmp/picked-cover.jpg';

/// Field-shaped public payload: one catalog from-price plus a vehicle
/// projection and a stale snapshot of the same line. IDs are public tokens.
Map<String, dynamic> kLimousineStaleFromPricePublicFixture({
  bool includeDistinctWeekend = false,
}) {
  Map<String, dynamic> fromPrice({
    required String id,
    String? sourceId,
    String? parentId,
    String? projectionId,
    bool appliesToAll = false,
    List<String> vehicleIds = const <String>[],
    String title = 'Avond',
    String updatedAt = '2026-08-19T10:00:00Z',
    int revision = 4,
  }) {
    return <String, dynamic>{
      'offer_id': id,
      if (sourceId != null) 'source_offer_id': sourceId,
      if (parentId != null) 'parent_offer_id': parentId,
      if (sourceId != null) 'canonical_offer_id': sourceId,
      if (projectionId != null) 'projection_id': projectionId,
      'enabled': true,
      'published': true,
      'target_type': appliesToAll || vehicleIds.isEmpty
          ? LimousineOfferTarget.serviceClass
          : LimousineOfferTarget.vehicle,
      'applies_to_all_selected_vehicles': appliesToAll,
      'vehicle_ids': vehicleIds,
      'vehicle_id': vehicleIds.isEmpty ? '' : vehicleIds.first,
      'price_presentation': LimousinePricePresentation.fromPrice,
      'display_amount_cents': 25000,
      'currency': 'EUR',
      'source_revision': revision,
      'created_at': '2026-08-01T09:00:00Z',
      'updated_at': updatedAt,
      'title': <String, String>{
        'nl': title,
        'en': title,
        'fr': title,
        'es': title,
      },
    };
  }

  return <String, dynamic>{
    'partner_id': _kPartnerId,
    'company_name': 'Fluxidi',
    'limousine_available': true,
    'vehicles': <Map<String, dynamic>>[
      <String, dynamic>{
        'vehicle_id': _kPartyId,
        'name': 'Party Limo',
        'service_category': 'limousine',
        'service_class_id': 'stretch_limousine',
        'is_active': true,
        'photo_url': 'https://cdn.example/party.jpg',
        'passenger_capacity': 16,
        'luggage_capacity': 3,
        'public_description': <String, String>{'nl': 'pinky hummer'},
      },
    ],
    kLimousinePublishedVehiclePublicCopyKey: <String, dynamic>{
      _kPartyId: <String, String>{'nl': 'pinky hummer'},
    },
    'limousine_offers': <Map<String, dynamic>>[
      fromPrice(
        id: 'off_from_250',
        sourceId: 'off_from_250',
        appliesToAll: true,
        updatedAt: '2026-08-19T12:00:00Z',
      ),
      fromPrice(
        id: 'off_from_250__vh_party',
        sourceId: 'off_from_250',
        parentId: 'off_from_250',
        projectionId: 'proj_vh_party',
        vehicleIds: const <String>[_kPartyId],
        updatedAt: '2026-08-19T12:00:01Z',
      ),
      fromPrice(
        id: 'off_from_250_stale_v3',
        title: 'Avond',
        appliesToAll: true,
        revision: 3,
        updatedAt: '2026-08-10T08:00:00Z',
      ),
      if (includeDistinctWeekend)
        fromPrice(
          id: 'off_weekend_250',
          sourceId: 'off_weekend_250',
          appliesToAll: true,
          title: 'Weekendarrangement',
          updatedAt: '2026-08-19T12:05:00Z',
        ),
    ],
  };
}

Map<String, dynamic> _strippedNearby() {
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
        'vehicle_id': _kPartyId,
        'service_category': 'limousine',
        'service_class_id': 'stretch_limousine',
        'is_active': true,
        'photo_url': 'https://cdn.example/party.jpg',
        'passenger_capacity': 16,
      },
      <String, dynamic>{
        'vehicle_id': 'vh_hummer',
        'service_category': 'limousine',
        'service_class_id': 'luxury_van',
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
    'limousine_price_presentation': 'from_price',
    'display_amount_cents': 25000,
    'currency': 'EUR',
  };
}

VehicleProfile _fleetVehicle({
  required String id,
  required String name,
  String classId = 'stretch_limousine',
}) {
  return VehicleProfile(
    id: id,
    vehicleName: name,
    brandModel: name,
    licensePlate: '1-ABC-123',
    color: 'white',
    passengerCapacity: 16,
    luggageCapacity: 3,
    tierId: 'premium',
    isActive: true,
    driverId: null,
    primaryPhotoRef: 'https://cdn.example/$id.jpg',
    galleryPhotoRefs: const <String>[],
    publicPhotoUrl: 'https://cdn.example/$id.jpg',
    serviceCategory: 'limousine',
    serviceClassId: classId,
  );
}

Map<String, dynamic> _publishedOffer() {
  return <String, dynamic>{
    'offer_id': 'off_from_250',
    'enabled': true,
    'published': true,
    'target_type': LimousineOfferTarget.serviceClass,
    'service_class_id': 'stretch_limousine',
    'price_presentation': LimousinePricePresentation.fromPrice,
    'display_amount_cents': 25000,
    'currency': 'EUR',
    'applies_to_all_selected_vehicles': true,
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
  };
}

Map<String, dynamic> _stripVisiting(Map<String, dynamic> section) {
  final next = Map<String, dynamic>.from(section);
  for (final key in <String>[
    'public_title',
    'public_description',
    'published_public_title',
    'published_public_description',
    kLimousineProfileCoverKey,
    kLimousinePublishedProfileCoverKey,
    'limousine_hero',
    'published_limousine_hero',
    kLimousineProfileLogoKey,
    kLimousinePublishedProfileLogoKey,
    'limousine_logo',
    'published_limousine_logo',
    kLimousineVisitingCardKey,
    kLimousinePublishedVisitingCardKey,
    kLimousinePublishedOffersOverlayKey,
  ]) {
    next.remove(key);
  }
  return next;
}

Widget _app(Widget child, {Size size = kLimousineTabletLandscape}) {
  return MaterialApp(
    home: MediaQuery(data: MediaQueryData(size: size), child: child),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MemoryLimousinePricingLocalStore store;
  late List<Map<String, dynamic>> saves;
  late List<Map<String, String>> uploads;
  var returnLocalUri = false;

  final party = _fleetVehicle(id: _kPartyId, name: 'Party Limo');
  final hummer = _fleetVehicle(
    id: 'vh_hummer',
    name: 'Hummer white',
    classId: 'luxury_van',
  );

  setUp(() {
    store = MemoryLimousinePricingLocalStore();
    limousinePricingLocalStore = store;
    saves = <Map<String, dynamic>>[];
    uploads = <Map<String, String>>[];
    returnLocalUri = false;
    appLanguageNotifier.value = AppLanguage.nl;
    customerThemeNotifier.value = CustomerThemeVariant.premiumLight;
  });

  tearDown(() {
    limousinePricingLocalStore = FileLimousinePricingLocalStore();
  });

  Future<Map<String, dynamic>> loadStripped() async {
    return <String, dynamic>{
      'limousine': <String, dynamic>{
        'enabled': true,
        'source_revision': 1,
        'offers': <Map<String, dynamic>>[_publishedOffer()],
      },
    };
  }

  Future<Map<String, dynamic>> saveStripped(Map<String, dynamic> section) async {
    saves.add(Map<String, dynamic>.from(section));
    return <String, dynamic>{
      'ok': true,
      'limousine': _stripVisiting(section),
    };
  }

  Future<LimousineSetupPickedImage?> pickImage() async {
    return (path: _kLocalUri, name: 'cover.jpg');
  }

  Future<Map<String, dynamic>> uploadMedia({
    required String mediaType,
    required String filePath,
    required String filename,
  }) async {
    uploads.add(<String, String>{
      'mediaType': mediaType,
      'filePath': filePath,
      'filename': filename,
    });
    if (returnLocalUri) return <String, dynamic>{'url': filePath};
    if (mediaType == kLimousineProfileLogoMediaType) {
      return <String, dynamic>{'url': _kLimoLogo};
    }
    return <String, dynamic>{'url': _kCover};
  }

  Widget setupPage({Size size = kLimousineTabletLandscape}) {
    return _app(
      LimousineBusinessSetupPage(
        loadPricing: loadStripped,
        savePricing: saveStripped,
        persistVehicles: (_) async {},
        vehicles: <VehicleProfile>[party, hummer],
        knownClassIds: const <String>['stretch_limousine', 'luxury_van'],
        entryEnabled: true,
        language: AppLanguage.nl,
        companyName: 'Fluxidi',
        logoUrl: _kTaxiLogo,
        pickImage: pickImage,
        uploadMedia: uploadMedia,
      ),
      size: size,
    );
  }

  Future<void> pumpSetup(
    WidgetTester tester, {
    Size size = kLimousineTabletLandscape,
  }) async {
    await tester.binding.setSurfaceSize(size);
    await tester.pumpWidget(setupPage(size: size));
    await tester.pumpAndSettle();
  }

  Future<void> fillVisitingCard(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(kLimousineBusinessSetupPublicTitleKey));
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

  test('A/E inspects the field-shaped duplicate from-price lineage', () {
    final offers =
        (kLimousineStaleFromPricePublicFixture()['limousine_offers'] as List)
            .cast<Map<String, dynamic>>();
    final inspected = [
      for (final offer in offers) limousineInspectPublishedOfferLineage(offer),
    ];
    expect(inspected[0]['offer_id'], 'off_from_250');
    expect(inspected[0]['source_offer_id'], 'off_from_250');
    expect(inspected[0]['scope_applies_to_all'], isTrue);
    expect(inspected[0]['vehicle_ids'], isEmpty);
    expect(inspected[1]['offer_id'], 'off_from_250__vh_party');
    expect(inspected[1]['parent_offer_id'], 'off_from_250');
    expect(inspected[1]['projection_id'], 'proj_vh_party');
    expect(inspected[1]['vehicle_ids'], <String>[_kPartyId]);
    expect(inspected[2]['offer_id'], 'off_from_250_stale_v3');
    expect(inspected[2]['source_revision'], 3);
    expect(
      limousineDeduplicateOfferMaps(offers).map(limousineOfferIdOf),
      <String>['off_from_250'],
    );
  });

  testWidgets('1-5 upload, reload, publish and discovery use the durable cover', (
    tester,
  ) async {
    await pumpSetup(tester);
    await fillVisitingCard(tester);
    await tester.ensureVisible(find.byKey(kLimousineBusinessSetupCoverUploadKey));
    await tester.tap(find.byKey(kLimousineBusinessSetupCoverUploadKey));
    await tester.pumpAndSettle();

    expect(uploads.single['mediaType'], kLimousineProfileCoverMediaType);
    expect(uploads.single['filePath'], _kLocalUri);
    expect(saves, isNotEmpty);
    expect(
      (saves.last[kLimousineProfileCoverKey] as Map)['photo_url'],
      _kCover,
    );
    expect(saves.last[kLimousineProfileCoverKey].toString(), isNot(contains('file:')));
    expect(find.text(kLimousineBusinessSetupCoverUpload.nl), findsNothing);
    expect(
      find.text(kLimousineBusinessSetupCoverReplace.nl),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await pumpSetup(tester);
    expect(find.text(kLimousineBusinessSetupCoverReplace.nl), findsOneWidget);
    expect(find.byKey(kLimousineBusinessSetupCoverFallbackKey), findsNothing);

    await fillVisitingCard(tester);
    tester
        .widget<ButtonStyleButton>(find.byKey(kLimousineBusinessSetupPublishKey))
        .onPressed!();
    await tester.pumpAndSettle();

    final published = saves.last;
    final encoded = jsonEncode(published);
    final decoded = Map<String, dynamic>.from(jsonDecode(encoded) as Map);
    expect(decoded['published_public_title'], containsPair('nl', 'Fluxidi'));
    expect(
      decoded['published_public_description'],
      containsPair('nl', 'Voor elke gelegenheid'),
    );
    expect(
      (decoded[kLimousinePublishedProfileCoverKey] as Map)['photo_url'],
      _kCover,
    );

    final stripped = _strippedNearby();
    final card = tryParseLimousineDiscoveryCard(stripped)!;
    expect(card.coverImageUrl, _kCover);
    expect(card.coverIsPlaceholder, isFalse);
    expect(limousineDiscoveryCardTitle(card, AppLanguage.nl), 'Fluxidi');
    expect(
      limousineDiscoveryCardDescription(card, AppLanguage.nl),
      'Voor elke gelegenheid',
    );

    final gateway = MemoryLimousineDiscoveryGateway(
      searchHandler: (_) async => LimousineDiscoveryPageData(
        listingMode: 'test_preview',
        cards: limousineDiscoveryCardsFromNearbyPartners(<dynamic>[stripped]),
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
    expect(find.text('Fluxidi'), findsWidgets);
    expect(find.text('Voor elke gelegenheid'), findsOneWidget);
    final photo = tester.widget<LimousineContainPhoto>(
      find.byKey(limousineDiscoveryCardCoverKey(_kPartnerId)),
    );
    expect(photo.imageUrl, _kCover);
    expect(card.coverIsPlaceholder, isFalse);
  });

  testWidgets('6 description sits directly under Fluxidi on the card', (
    tester,
  ) async {
    store.writeOverlay(
      scopeKeys: const <String>[kLimousinePricingLocalDefaultScope],
      fields: <String, dynamic>{
        'published_public_title': const <String, String>{'nl': 'Fluxidi'},
        'published_public_description': const <String, String>{
          'nl': 'Voor elke gelegenheid',
        },
        kLimousinePublishedProfileCoverKey: <String, dynamic>{
          'photo_url': _kCover,
        },
      },
      revision: 2,
    );
    final gateway = MemoryLimousineDiscoveryGateway(
      searchHandler: (_) async => LimousineDiscoveryPageData(
        cards: limousineDiscoveryCardsFromNearbyPartners(<dynamic>[
          _strippedNearby(),
        ]),
      ),
    );
    await tester.pumpWidget(
      _app(
        LimousineCustomerDiscoveryPage(
          gateway: gateway,
          customerHomeBuilder: (_) => const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final title = tester.getRect(
      find.byKey(limousineDiscoveryCardTitleKey(_kPartnerId)),
    );
    final description = tester.getRect(
      find.byKey(limousineDiscoveryCardDescriptionKey(_kPartnerId)),
    );
    expect(description.top, greaterThan(title.bottom - 1));
    expect(description.top - title.bottom, lessThan(20));
  });

  testWidgets('7-9 logo actions stay reachable and survive publish', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(kLimousineSmX400Portrait);
    await tester.pumpWidget(setupPage(size: kLimousineSmX400Portrait));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(kLimousineBusinessSetupLogoPickKey));
    await tester.pumpAndSettle();
    expect(find.text(kLimousineBusinessSetupLogoPick.nl), findsOneWidget);
    expect(
      find.text(kLimousineBusinessSetupLogoStatusCompany.nl),
      findsOneWidget,
    );
    final button = tester.getRect(find.byKey(kLimousineBusinessSetupLogoPickKey));
    final footer = tester.getRect(find.byKey(kLimousineBusinessSetupFooterKey));
    expect(button.bottom, lessThanOrEqualTo(footer.top + 1));

    await tester.tap(find.byKey(kLimousineBusinessSetupLogoPickKey));
    await tester.pumpAndSettle();
    expect(uploads.single['mediaType'], kLimousineProfileLogoMediaType);
    expect(find.text(kLimousineBusinessSetupLogoReplace.nl), findsOneWidget);
    expect(find.text(kLimousineBusinessSetupLogoStatusOwn.nl), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await pumpSetup(tester, size: kLimousineSmX400Portrait);
    expect(find.text(kLimousineBusinessSetupLogoReplace.nl), findsOneWidget);

    await fillVisitingCard(tester);
    tester
        .widget<ButtonStyleButton>(find.byKey(kLimousineBusinessSetupPublishKey))
        .onPressed!();
    await tester.pumpAndSettle();
    final card = tryParseLimousineDiscoveryCard(_strippedNearby())!;
    expect(card.logoUrl, _kLimoLogo);
  });

  testWidgets('10 failed local URI upload stays unpublished and taxi media stays', (
    tester,
  ) async {
    returnLocalUri = true;
    await pumpSetup(tester);
    await tester.ensureVisible(find.byKey(kLimousineBusinessSetupCoverUploadKey));
    await tester.tap(find.byKey(kLimousineBusinessSetupCoverUploadKey));
    await tester.pumpAndSettle();
    expect(find.text(kLimousineBusinessSetupCoverUploadFailed.nl), findsWidgets);
    expect(saves, isEmpty);
    expect(
      store.peekMerged(const <String>[kLimousinePricingLocalDefaultScope])
          [kLimousineProfileCoverKey],
      isNull,
    );

    returnLocalUri = false;
    await tester.tap(find.byKey(kLimousineBusinessSetupCoverUploadKey));
    await tester.pumpAndSettle();
    await fillVisitingCard(tester);
    tester
        .widget<ButtonStyleButton>(find.byKey(kLimousineBusinessSetupPublishKey))
        .onPressed!();
    await tester.pumpAndSettle();
    expect(saves.last.containsKey('publicHeroPhotoUrl'), isFalse);
    expect(saves.last.containsKey('hero_photo_url'), isFalse);
    expect(saves.last.containsKey('logo_url'), isFalse);
    expect(
      (saves.last[kLimousinePublishedProfileCoverKey] as Map)['photo_url'],
      isNot(_kTaxiHero),
    );
    expect(
      (saves.last[kLimousinePublishedProfileLogoKey] as Map)['photo_url'],
      isNot(_kTaxiLogo),
    );
  });

  testWidgets('11-13 one from-price card; two real offers stay two', (
    tester,
  ) async {
    final stale = kLimousineStaleFromPricePublicFixture();
    final showroom = buildLimousineProviderShowroomData(profile: stale);
    final partyVehicle = showroom.vehicles.singleWhere(
      (item) => item.vehicleId == _kPartyId,
    );
    expect(partyVehicle.offers, hasLength(1));
    expect(partyVehicle.offers.single.offerId, 'off_from_250');

    await tester.pumpWidget(
      _app(
        LimousineVehicleDetailPage(
          vehicle: partyVehicle,
          companyName: 'Fluxidi',
          partnerId: _kPartnerId,
          logoImage: MemoryImage(_kTinyPng),
          photoImages: <MemoryImage>[MemoryImage(_kTinyPng)],
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Vanafprijs'), findsOneWidget);
    expect(find.text('€250'), findsOneWidget);

    final both = kLimousineStaleFromPricePublicFixture(
      includeDistinctWeekend: true,
    );
    final bothShowroom = buildLimousineProviderShowroomData(profile: both);
    expect(
      bothShowroom.vehicles.single.offers.map((offer) => offer.offerId),
      <String>['off_from_250', 'off_weekend_250'],
    );
  });

  testWidgets('14 pinky hummer stays under Over deze limousine', (tester) async {
    final data = buildLimousineProviderShowroomData(
      profile: kLimousineStaleFromPricePublicFixture(),
    );
    final vehicle = data.vehicles.single;
    expect(vehicle.publicDescription['nl'], 'pinky hummer');
    await tester.pumpWidget(
      _app(
        LimousineVehicleDetailPage(
          vehicle: vehicle,
          companyName: 'Fluxidi',
          partnerId: _kPartnerId,
          logoImage: MemoryImage(_kTinyPng),
          photoImages: <MemoryImage>[MemoryImage(_kTinyPng)],
        ),
      ),
    );
    await tester.pump();
    expect(find.text('pinky hummer'), findsOneWidget);
    expect(find.byKey(kLimousineDetailAboutBodyKey), findsOneWidget);
  });

  testWidgets('15 sticky footer does not cover logo or cover actions', (
    tester,
  ) async {
    for (final size in <Size>[
      kLimousineSmX400Portrait,
      kLimousineTabletLandscape,
      kLimousinePhonePortrait,
    ]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(setupPage(size: size));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(kLimousineBusinessSetupCoverUploadKey));
      expect(
        tester.getRect(find.byKey(kLimousineBusinessSetupCoverUploadKey)).bottom,
        lessThanOrEqualTo(
          tester.getRect(find.byKey(kLimousineBusinessSetupFooterKey)).top + 1,
        ),
      );
      await tester.ensureVisible(find.byKey(kLimousineBusinessSetupLogoPickKey));
      expect(
        tester.getRect(find.byKey(kLimousineBusinessSetupLogoPickKey)).bottom,
        lessThanOrEqualTo(
          tester.getRect(find.byKey(kLimousineBusinessSetupFooterKey)).top + 1,
        ),
      );
      expect(
        find.text(kLimousineBusinessSetupCoverUploadHelp.nl),
        findsOneWidget,
      );
      expect(
        find.text(kLimousineBusinessSetupCoverGalleryHelp.nl),
        findsOneWidget,
      );
      expect(
        find.text(kLimousineBusinessSetupCoverPickGallery.nl),
        findsOneWidget,
      );
    }
  });

  test('fallback vehicle photo is never the published discovery cover', () {
    final payload = limousinePublicDisplayPayload(
      publish: true,
      title: const <String, String>{'nl': 'Fluxidi'},
      description: const <String, String>{'nl': 'Voor elke gelegenheid'},
      hero: const <String, dynamic>{},
      publishedTitle: const <String, String>{},
      publishedDescription: const <String, String>{},
      publishedHero: const <String, dynamic>{},
    );
    expect(
      (payload[kLimousinePublishedProfileCoverKey] as Map)['photo_url'] ?? '',
      isEmpty,
    );
    expect(
      tryParseLimousineDiscoveryCard(_strippedNearby())!.coverIsPlaceholder,
      isTrue,
    );
  });
}
