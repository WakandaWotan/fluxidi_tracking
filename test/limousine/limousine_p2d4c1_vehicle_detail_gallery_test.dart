import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/customer_theme_store.dart';
import 'package:fluxidi_tracking/limousine/limousine_adaptive_vehicle_photo.dart';
import 'package:fluxidi_tracking/limousine/limousine_business_setup.dart';
import 'package:fluxidi_tracking/limousine/limousine_business_setup_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote.dart';
import 'package:fluxidi_tracking/limousine/limousine_offers.dart';
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1a_ux.dart';
import 'package:fluxidi_tracking/limousine/limousine_provider_showroom.dart';
import 'package:fluxidi_tracking/limousine/limousine_provider_showroom_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_public_showroom.dart';
import 'package:fluxidi_tracking/limousine/limousine_public_showroom_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_vehicle_detail_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_vehicle_public_copy.dart';

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

const Size _kLandscape = Size(1600, 900);
const Size _kPortrait = Size(900, 1600);
const Size _kSquare = Size(1200, 1200);

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

LimousinePublishedOffer _offer({
  required String id,
  String presentation = LimousinePricePresentation.fromPrice,
  List<String> vehicleIds = const <String>[],
  bool appliesToAll = false,
  bool published = true,
  int amount = 25000,
  String title = 'Avond',
}) {
  return LimousinePublishedOffer.fromJson(<String, dynamic>{
    'offer_id': id,
    'enabled': true,
    'published': published,
    'target_type': appliesToAll
        ? LimousineOfferTarget.serviceClass
        : LimousineOfferTarget.vehicle,
    'vehicle_id': vehicleIds.isEmpty ? '' : vehicleIds.first,
    'vehicle_ids': vehicleIds,
    'applies_to_all_selected_vehicles': appliesToAll,
    'price_presentation': presentation,
    'display_amount_cents': amount,
    'currency': 'EUR',
    'title': <String, String>{'nl': title, 'en': title, 'fr': title, 'es': title},
    'description': <String, String>{
      'nl': 'Beschrijving',
      'en': 'Description',
      'fr': 'Description',
      'es': 'Descripción',
    },
  });
}

LimousineShowroomVehicle _showroomVehicle({
  String id = 'vh_party',
  String name = 'Party Limo',
  List<String> photos = const <String>[
    'https://cdn.example/party-wide.jpg',
    'https://cdn.example/party-int.jpg',
  ],
  Map<String, String> publicDescription = const <String, String>{},
  List<LimousinePublishedOffer> offers = const <LimousinePublishedOffer>[],
  String classId = 'stretch_limousine',
}) {
  return LimousineShowroomVehicle(
    key: id,
    name: name,
    vehicleId: id,
    serviceClassId: classId,
    photoUrls: photos,
    passengerCapacity: 16,
    luggageCapacity: 3,
    publicDescription: publicDescription,
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

Widget _detail(
  LimousineShowroomVehicle vehicle, {
  Size size = kLimousinePhonePortrait,
  Map<String, Size>? sourceSizes,
  bool quoteEnabled = false,
  bool bookEnabled = false,
}) {
  final image = MemoryImage(_kTinyPng);
  return _app(
    LimousineVehicleDetailPage(
      vehicle: vehicle,
      companyName: 'Maison Noire',
      partnerId: 'limo_1',
      logoImage: image,
      photoImages: [for (final _ in vehicle.photoUrls) image],
      photoSourceSizes: sourceSizes,
      quoteEnabled: quoteEnabled,
      bookEnabled: bookEnabled,
    ),
    size: size,
  );
}

Map<String, dynamic> _publicProfile({
  required List<Map<String, dynamic>> vehicles,
  required List<Map<String, dynamic>> offers,
  Map<String, dynamic>? publicCopy,
  Map<String, dynamic>? publishedCopy,
}) {
  return <String, dynamic>{
    'partner_id': 'limo_1',
    'company_name': 'Maison Noire',
    'limousine_available': true,
    'vehicles': vehicles,
    'limousine_offers': offers,
    if (publicCopy != null) kLimousineVehiclePublicCopyKey: publicCopy,
    if (publishedCopy != null)
      kLimousinePublishedVehiclePublicCopyKey: publishedCopy,
  };
}

Map<String, dynamic> _publicVehicle({
  required String id,
  required String name,
  Map<String, String>? publicDescription,
}) {
  return <String, dynamic>{
    'vehicle_id': id,
    'name': name,
    'service_category': 'limousine',
    'service_class': 'stretch_limousine',
    'is_active': true,
    'pax': 16,
    'luggage': 3,
    'photo_url': 'https://cdn.example/$id.jpg',
    if (publicDescription != null) 'public_description': publicDescription,
  };
}

Map<String, dynamic> _rawOffer({
  required String id,
  List<String> vehicleIds = const <String>[],
  bool appliesToAll = false,
  bool published = true,
  String presentation = LimousinePricePresentation.fromPrice,
  int amount = 25000,
}) {
  return <String, dynamic>{
    'offer_id': id,
    'enabled': true,
    'published': published,
    'target_type': appliesToAll
        ? LimousineOfferTarget.serviceClass
        : LimousineOfferTarget.vehicle,
    'vehicle_id': vehicleIds.isEmpty ? '' : vehicleIds.first,
    'vehicle_ids': vehicleIds,
    'applies_to_all_selected_vehicles': appliesToAll,
    'price_presentation': presentation,
    'display_amount_cents': amount,
    'currency': 'EUR',
    'title': <String, String>{'nl': id, 'en': id, 'fr': id, 'es': id},
  };
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

  test('source aspect thresholds classify landscape square and portrait', () {
    expect(
      limousinePhotoOrientationFromSize(_kLandscape),
      LimousinePhotoOrientation.landscape,
    );
    expect(
      limousinePhotoOrientationFromSize(_kPortrait),
      LimousinePhotoOrientation.portrait,
    );
    expect(
      limousinePhotoOrientationFromSize(_kSquare),
      LimousinePhotoOrientation.square,
    );
    expect(
      limousinePhotoOrientationFromSize(const Size(1000, 1100)),
      LimousinePhotoOrientation.square,
    );
    expect(
      limousinePhotoOrientationFromSize(const Size(1100, 1000)),
      LimousinePhotoOrientation.square,
    );
    expect(limousineAdaptivePhotoUsesBlurredBackdrop(
      LimousinePhotoOrientation.landscape,
    ), isFalse);
    expect(limousineAdaptivePhotoUsesBlurredBackdrop(
      LimousinePhotoOrientation.square,
    ), isFalse);
    expect(limousineAdaptivePhotoUsesBlurredBackdrop(
      LimousinePhotoOrientation.portrait,
    ), isTrue);
  });

  testWidgets('1-3 landscape photo is full-width, contained, without blur', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(kLimousinePhonePortrait);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _detail(
        _showroomVehicle(photos: const <String>['https://cdn.example/wide.jpg']),
        sourceSizes: const {'https://cdn.example/wide.jpg': _kLandscape},
      ),
    );
    await tester.pump();
    expect(
      find.byKey(limousineAdaptivePhotoOrientationKey(
        LimousinePhotoOrientation.landscape,
      )),
      findsOneWidget,
    );
    expect(find.byKey(kLimousineAdaptivePhotoBlurKey), findsNothing);
    final sharp = tester.widget<Image>(find.byKey(kLimousineAdaptivePhotoSharpKey));
    expect(sharp.fit, BoxFit.contain);
    final photo = tester.getRect(find.byType(LimousineAdaptiveVehiclePhoto));
    expect(photo.width, kLimousinePhonePortrait.width);
    expect(photo.height, lessThanOrEqualTo(kLimousineAdaptiveHeroPhoneMax));
    expect(tester.takeException(), isNull);
  });

  testWidgets('4-5 portrait uses subtle blur and keeps the sharp photo visible', (
    tester,
  ) async {
    await tester.pumpWidget(
      _detail(
        _showroomVehicle(
          photos: const <String>['https://cdn.example/tall.jpg'],
        ),
        sourceSizes: const {'https://cdn.example/tall.jpg': _kPortrait},
      ),
    );
    await tester.pump();
    expect(find.byKey(kLimousineAdaptivePhotoBlurKey), findsOneWidget);
    expect(find.byKey(kLimousineAdaptivePhotoSharpKey), findsOneWidget);
    final blur = tester.widget<ImageFiltered>(
      find.byKey(kLimousineAdaptivePhotoBlurKey),
    );
    expect(blur.imageFilter, isA<ImageFilter>());
    final sharp = tester.getRect(find.byKey(kLimousineAdaptivePhotoSharpKey));
    expect(sharp.width, greaterThan(kLimousinePhonePortrait.width * 0.45));
    expect(tester.takeException(), isNull);
  });

  testWidgets('6 square photo stays overflow-free', (tester) async {
    await tester.binding.setSurfaceSize(kLimousinePhonePortrait);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _detail(
        _showroomVehicle(
          photos: const <String>['https://cdn.example/square.jpg'],
        ),
        sourceSizes: const {'https://cdn.example/square.jpg': _kSquare},
      ),
    );
    await tester.pump();
    expect(
      find.byKey(limousineAdaptivePhotoOrientationKey(
        LimousinePhotoOrientation.square,
      )),
      findsOneWidget,
    );
    expect(find.byKey(kLimousineAdaptivePhotoBlurKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('7-9 thumbnails, fullscreen swipe and close keep the selection', (
    tester,
  ) async {
    await tester.pumpWidget(
      _detail(
        _showroomVehicle(),
        sourceSizes: const {
          'https://cdn.example/party-wide.jpg': _kLandscape,
          'https://cdn.example/party-int.jpg': _kLandscape,
        },
      ),
    );
    await tester.pump();
    expect(find.byKey(kLimousineDetailGalleryThumbsKey), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
    await tester.ensureVisible(find.byKey(limousineDetailGalleryThumbKey(1)));
    await tester.tap(find.byKey(limousineDetailGalleryThumbKey(1)));
    await tester.pumpAndSettle();
    expect(find.byKey(kLimousineDetailFullscreenViewerKey), findsOneWidget);
    expect(find.byKey(kLimousineDetailFullscreenPageViewKey), findsOneWidget);
    await tester.drag(
      find.byKey(kLimousineDetailFullscreenPageViewKey),
      const Offset(300, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kLimousineDetailFullscreenCloseKey));
    await tester.pumpAndSettle();
    expect(find.byKey(kLimousineDetailFullscreenViewerKey), findsNothing);
    expect(find.text('2 / 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('10 phone and tablet stay overflow-free', (tester) async {
    Future<void> pump(Size size) async {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        _detail(
          _showroomVehicle(
            offers: <LimousinePublishedOffer>[
              _offer(id: 'off_from', appliesToAll: true),
            ],
            publicDescription: const <String, String>{
              'nl': 'Feestlimousine voor een avond uit.',
            },
          ),
          size: size,
          sourceSizes: const {
            'https://cdn.example/party-wide.jpg': _kLandscape,
            'https://cdn.example/party-int.jpg': _kPortrait,
          },
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Party Limo'), findsOneWidget);
      expect(find.text('Stretchlimousine'), findsOneWidget);
      expect(find.text('Limousineklasse'), findsNothing);
    }

    await pump(kLimousinePhonePortrait);
    await pump(kLimousineSmX400Portrait);
    await pump(kLimousineTabletLandscape);
    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  test('11-14 public copy is keyed by vehicle id and stays isolated', () {
    final working = limousineVehiclePublicCopyById(<String, dynamic>{
      'vh_party': <String, String>{
        'nl': 'Party Limo voor een avond uit.',
        'en': 'Party Limo for a night out.',
      },
    });
    final published = limousineVehiclePublicCopyPayload(
      publish: true,
      working: working,
      published: const {},
    );
    expect(
      (published[kLimousineVehiclePublicCopyKey] as Map)['vh_party']['nl'],
      'Party Limo voor een avond uit.',
    );
    expect(
      (published[kLimousinePublishedVehiclePublicCopyKey] as Map)['vh_party']['nl'],
      'Party Limo voor een avond uit.',
    );
    final draft = limousineVehiclePublicCopyPayload(
      publish: false,
      working: <String, Map<String, String>>{
        'vh_party': <String, String>{'nl': 'Nieuw concept'},
      },
      published: working,
    );
    expect(
      (draft[kLimousinePublishedVehiclePublicCopyKey] as Map)['vh_party']['nl'],
      'Party Limo voor een avond uit.',
    );
    final profile = _publicProfile(
      vehicles: <Map<String, dynamic>>[
        _publicVehicle(id: 'vh_party', name: 'Party Limo'),
        _publicVehicle(id: 'vh_hummer', name: 'Hummer white'),
      ],
      offers: const <Map<String, dynamic>>[],
      publishedCopy: Map<String, dynamic>.from(
        published[kLimousinePublishedVehiclePublicCopyKey] as Map,
      ),
    );
    final data = buildLimousineProviderShowroomData(profile: profile);
    final party = data.vehicles.firstWhere((v) => v.vehicleId == 'vh_party');
    final hummer = data.vehicles.firstWhere((v) => v.vehicleId == 'vh_hummer');
    expect(
      limousineResolvePublicCopyText(party.publicDescription, AppLanguage.nl),
      'Party Limo voor een avond uit.',
    );
    expect(
      limousineResolvePublicCopyText(hummer.publicDescription, AppLanguage.nl),
      isEmpty,
    );
  });

  test('15-16 language variant and fallback never return null', () {
    final localized = <String, String>{
      'nl': 'Nederlandse tekst',
      'en': 'English text',
      'fr': '',
      'es': '',
      'de': '',
    };
    expect(
      limousineResolvePublicCopyText(localized, AppLanguage.en),
      'English text',
    );
    expect(
      limousineResolvePublicCopyText(localized, AppLanguage.fr),
      'Nederlandse tekst',
    );
    expect(
      limousineResolvePublicCopyText(localized, AppLanguage.de),
      'Nederlandse tekst',
    );
    expect(limousineResolvePublicCopyText(const {}, AppLanguage.nl), isEmpty);
  });

  testWidgets('17 empty description hides the whole about section', (
    tester,
  ) async {
    await tester.pumpWidget(_detail(_showroomVehicle()));
    await tester.pump();
    expect(find.byKey(kLimousineDetailAboutSectionKey), findsNothing);
    expect(find.text(kLimousineDetailAboutHeading.nl), findsNothing);
    await tester.pumpWidget(
      _detail(
        _showroomVehicle(
          publicDescription: const <String, String>{
            'nl': 'Feestlimousine voor een avond uit.',
          },
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(kLimousineDetailAboutSectionKey), findsOneWidget);
    expect(find.text('Feestlimousine voor een avond uit.'), findsOneWidget);
  });

  test('18 taxi profile and vehicle notes stay untouched', () {
    final vehicle = _fleetVehicle(id: 'vh_party', name: 'Party Limo');
    final payload = limousineVehiclePublicCopyPayload(
      publish: true,
      working: <String, Map<String, String>>{
        vehicle.id: const <String, String>{'nl': 'Publiek'},
      },
      published: const {},
    );
    expect(limousinePublicCopyTouchesPrivateVehicleFields(payload), isFalse);
    expect(payload.containsKey('notes'), isFalse);
    expect(vehicle.serviceCategory, 'limousine');
    expect(vehicle.vehicleName, 'Party Limo');
    final source = File('lib/app_config.dart').readAsStringSync();
    final start = source.indexOf('class VehicleProfile {');
    final end = source.indexOf('class DriverProfile {');
    final body = source.substring(start, end);
    expect(body.contains('notes'), isFalse);
    expect(body.contains('publicDescription'), isFalse);
  });

  testWidgets('11-12 setup stores copy per vehicle and reloads it', (
    tester,
  ) async {
    final saves = <Map<String, dynamic>>[];
    final party = _fleetVehicle(id: 'vh_party', name: 'Party Limo');
    final hummer = _fleetVehicle(
      id: 'vh_hummer',
      name: 'Hummer white',
      classId: 'luxury_van',
    );
    var persisted = <VehicleProfile>[party, hummer];
    await tester.pumpWidget(
      _app(
        LimousineBusinessSetupPage(
          loadPricing: () async => <String, dynamic>{
            'limousine': <String, dynamic>{'offers': <dynamic>[]},
          },
          savePricing: (section) async {
            saves.add(section);
            return <String, dynamic>{'ok': true, 'limousine': section};
          },
          persistVehicles: (vehicles) async => persisted = vehicles,
          vehicles: <VehicleProfile>[party, hummer],
          knownClassIds: const <String>['stretch_limousine', 'luxury_van'],
          language: AppLanguage.nl,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(limousineBusinessSetupEditPublicDetailsKey('vh_party')),
    );
    await tester.tap(
      find.byKey(limousineBusinessSetupEditPublicDetailsKey('vh_party')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(kLimousineVehiclePublicCopyFieldKey),
      'Party Limo voor een avond uit.',
    );
    await tester.tap(find.byKey(kLimousineVehiclePublicCopySaveKey));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(kLimousineBusinessSetupDraftSaveKey));
    await tester.tap(find.byKey(kLimousineBusinessSetupDraftSaveKey));
    await tester.pumpAndSettle();
    expect(saves, isNotEmpty);
    final copy = limousineVehiclePublicCopyById(
      saves.last[kLimousineVehiclePublicCopyKey],
    );
    expect(copy['vh_party']?['nl'], 'Party Limo voor een avond uit.');
    expect(copy.containsKey('vh_hummer'), isFalse);
    expect(persisted.map((v) => v.id), <String>['vh_party', 'vh_hummer']);
    expect(persisted.first.vehicleName, 'Party Limo');

    await tester.tap(
      find.byKey(limousineBusinessSetupEditPublicDetailsKey('vh_party')),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(kLimousineVehiclePublicCopyFieldKey))
          .controller
          ?.text,
      'Party Limo voor een avond uit.',
    );
    await tester.tap(find.byKey(kLimousineVehiclePublicCopyCancelKey));
    await tester.pumpAndSettle();
  });

  test('19-22 published offers dedupe by id and stay vehicle-bound', () {
    final profile = _publicProfile(
      vehicles: <Map<String, dynamic>>[
        _publicVehicle(id: 'vh_party', name: 'Party Limo'),
        _publicVehicle(id: 'vh_hummer', name: 'Hummer white'),
      ],
      offers: <Map<String, dynamic>>[
        _rawOffer(id: 'off_from', appliesToAll: true),
        _rawOffer(
          id: 'off_from',
          appliesToAll: true,
          vehicleIds: const <String>['vh_party'],
        ),
        _rawOffer(
          id: 'off_from',
          appliesToAll: true,
          vehicleIds: const <String>['vh_hummer'],
        ),
        _rawOffer(
          id: 'off_hummer',
          vehicleIds: const <String>['vh_hummer'],
          presentation: LimousinePricePresentation.quoteRequired,
        ),
        _rawOffer(
          id: 'off_party_extra',
          vehicleIds: const <String>['vh_party'],
          presentation: LimousinePricePresentation.exactFixed,
          amount: 40000,
        ),
        _rawOffer(id: 'off_draft', appliesToAll: true, published: false),
      ],
    );
    final data = buildLimousineProviderShowroomData(profile: profile);
    final party = data.vehicles.firstWhere((v) => v.vehicleId == 'vh_party');
    final hummer = data.vehicles.firstWhere((v) => v.vehicleId == 'vh_hummer');
    expect(party.offers.where((o) => o.offerId == 'off_from'), hasLength(1));
    expect(hummer.offers.where((o) => o.offerId == 'off_from'), hasLength(1));
    expect(party.offers.any((o) => o.offerId == 'off_hummer'), isFalse);
    expect(hummer.offers.any((o) => o.offerId == 'off_party_extra'), isFalse);
    expect(party.offers.any((o) => o.offerId == 'off_party_extra'), isTrue);
    expect(party.offers.any((o) => o.offerId == 'off_draft'), isFalse);
    expect(
      collectLimousineShowroomOffers(profile)
          .where((o) => o.offerId == 'off_from'),
      hasLength(1),
    );
  });

  testWidgets('23 from-price card never repeats Vanaf in the value', (
    tester,
  ) async {
    await tester.pumpWidget(
      _detail(
        _showroomVehicle(
          offers: <LimousinePublishedOffer>[_offer(id: 'off_from')],
        ),
      ),
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(kLimousineDetailPricesSectionKey));
    expect(find.text('Vanafprijs'), findsOneWidget);
    expect(find.text('€250'), findsOneWidget);
    expect(find.text('Vanaf €250'), findsNothing);
    expect(find.text('Vanaf'), findsNothing);
    expect(
      find.text(kLimousineOfferFromPriceDisclaimer.nl),
      findsOneWidget,
    );
  });

  testWidgets('24-26 quote-on-request, gates and compact tap targets', (
    tester,
  ) async {
    await tester.pumpWidget(
      _detail(
        _showroomVehicle(
          offers: <LimousinePublishedOffer>[
            _offer(
              id: 'off_quote',
              presentation: LimousinePricePresentation.quoteRequired,
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(find.text(kLimousineShowroomPriceOnRequest.nl), findsOneWidget);
    expect(find.text(kLimousineDetailQuoteComingSoon.nl), findsOneWidget);
    expect(find.text(kLimousineDetailQuoteCta.nl), findsNothing);
    final gated = tester.widget<ButtonStyleButton>(
      find.byKey(kLimousineDetailQuoteCtaKey),
    );
    expect(gated.onPressed, isNull);
    expect(kLimousineCustomerQuoteGateEnabled, isFalse);
    expect(kLimousineCustomerManualQuoteGateEnabled, isFalse);
    expect(kLimousineCustomerBookGateEnabled, isFalse);
    expect(tester.getSize(find.byKey(kLimousineDetailQuoteCtaKey)).height, 44);

    await tester.pumpWidget(
      _detail(
        _showroomVehicle(
          offers: <LimousinePublishedOffer>[
            _offer(
              id: 'off_quote',
              presentation: LimousinePricePresentation.quoteRequired,
            ),
          ],
        ),
        quoteEnabled: true,
      ),
    );
    await tester.pump();
    expect(find.text(kLimousineDetailQuoteCta.nl), findsOneWidget);
    expect(find.text('Offerte aanvragen'), findsOneWidget);
    final open = tester.widget<ButtonStyleButton>(
      find.byKey(kLimousineDetailQuoteCtaKey),
    );
    expect(open.onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });
}
