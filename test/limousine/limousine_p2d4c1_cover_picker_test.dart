import 'dart:async';
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
import 'package:fluxidi_tracking/limousine/limousine_cover_gallery_picker.dart';
import 'package:fluxidi_tracking/limousine/limousine_hero_contract.dart';
import 'package:fluxidi_tracking/limousine/limousine_offers.dart';
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1a_ux.dart';
import 'package:fluxidi_tracking/limousine/limousine_pricing_local_store.dart';
import 'package:fluxidi_tracking/limousine/limousine_public_cover_view.dart';
import 'package:fluxidi_tracking/limousine/limousine_setup_media_pick.dart';
import 'package:fluxidi_tracking/limousine/limousine_vehicle_media.dart';
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

const String _kCover =
    'https://cdn.example/public-media/t1/c1/limousine/profile-cover.jpg';
const String _kPrevCover =
    'https://cdn.example/public-media/t1/c1/limousine/profile-cover-prev.jpg';
const String _kTaxiHero =
    'https://cdn.example/public-media/t1/c1/company/hero.jpg';
const String _kContentUri = 'content://media/external/images/media/42';

VehicleProfile _vehicle({
  required String id,
  required String name,
  String photo = '',
  List<String> gallery = const <String>[],
}) {
  final primary = photo.isEmpty ? 'https://cdn.example/$id.jpg' : photo;
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
    primaryPhotoRef: primary,
    galleryPhotoRefs: gallery,
    publicPhotoUrl: primary,
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

void expectPublicPreviewHasNoInternalScope(WidgetTester tester) {
  final preview = find.byKey(kLimousineBusinessSetupPreviewKey);
  expect(preview, findsOneWidget);
  expect(
    find.descendant(
      of: preview,
      matching: find.textContaining('Zichtbaar bij'),
    ),
    findsNothing,
  );
  expect(
    find.descendant(of: preview, matching: find.text('Party Limo · 2')),
    findsNothing,
  );
  expect(
    find.descendant(of: preview, matching: find.text('Hummer white · 4')),
    findsNothing,
  );
  expect(
    find.descendant(of: preview, matching: find.textContaining('Party Limo ·')),
    findsNothing,
  );
  expect(
    find.descendant(
      of: preview,
      matching: find.textContaining('Hummer white ·'),
    ),
    findsNothing,
  );
  expect(
    find.descendant(of: preview, matching: find.text('Party Limo')),
    findsNothing,
  );
  expect(
    find.descendant(of: preview, matching: find.text('Hummer white')),
    findsNothing,
  );
  expect(
    find.descendant(of: preview, matching: find.textContaining('2 limousines')),
    findsNothing,
  );
  expect(
    find.descendant(
      of: preview,
      matching: find.textContaining('tot 16 personen'),
    ),
    findsNothing,
  );
  expect(
    find.descendant(of: preview, matching: find.textContaining('Vanaf €250')),
    findsNothing,
  );
  expect(find.byKey(kLimousineBusinessSetupPreviewFleetKey), findsNothing);
  expect(find.byKey(kLimousineBusinessSetupPreviewPriceKey), findsNothing);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MemoryLimousinePricingLocalStore store;
  late List<Map<String, dynamic>> saves;
  late List<Map<String, String>> uploads;
  late List<VehicleProfile> vehicles;
  var pickCalls = 0;
  var returnLocalUri = false;
  Completer<LimousineSetupPickedImage?>? delayedPick;
  LimousineSetupPickedImage? nextPick;
  LimousineSetupPickedImage? lostPick;
  String taxiHeroSnapshot = _kTaxiHero;

  setUp(() {
    store = MemoryLimousinePricingLocalStore();
    limousinePricingLocalStore = store;
    saves = <Map<String, dynamic>>[];
    uploads = <Map<String, String>>[];
    pickCalls = 0;
    returnLocalUri = false;
    delayedPick = null;
    nextPick = LimousineSetupPickedImage(
      path: _kContentUri,
      name: 'IMG_1001.jpg',
      bytes: _kTinyPng,
    );
    lostPick = null;
    vehicles = <VehicleProfile>[
      _vehicle(
        id: 'vh_party',
        name: 'Party Limo',
        photo: 'https://cdn.example/party.jpg',
        gallery: <String>[
          'https://cdn.example/party.jpg?v=2',
          'https://cdn.example/party-side.jpg',
          'https://cdn.example/party.jpg#dup',
        ],
      ),
      _vehicle(
        id: 'vh_hummer',
        name: 'Hummer white',
        photo: 'https://cdn.example/hummer.jpg',
        gallery: <String>[
          'https://cdn.example/hummer.jpg',
          'https://cdn.example/hummer-rear.jpg',
        ],
      ),
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

  Future<LimousineSetupPickedImage?> recoverLost() async => lostPick;

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
    if (returnLocalUri) return <String, dynamic>{'url': filePath};
    return <String, dynamic>{'url': _kCover};
  }

  Widget setupPage({
    Size size = kLimousineSmX400Portrait,
    Future<Map<String, dynamic>> Function()? load,
    bool includeRecover = false,
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
        logoUrl: 'https://cdn.example/public-media/t1/c1/company/logo.png',
        pickImage: pickImage,
        recoverLostImage: includeRecover ? recoverLost : null,
        uploadMedia: uploadMedia,
      ),
      size: size,
    );
  }

  Future<void> pumpSetup(
    WidgetTester tester, {
    Size size = kLimousineSmX400Portrait,
    Future<Map<String, dynamic>> Function()? load,
    bool includeRecover = false,
  }) async {
    await tester.binding.setSurfaceSize(size);
    await tester.pumpWidget(
      setupPage(size: size, load: load, includeRecover: includeRecover),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expectPublicPreviewHasNoInternalScope(tester);
  }

  Future<void> pumpUpload(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  test('content URI and image bytes are classified without a local path', () {
    expect(limousinePickedPathIsContentUri(_kContentUri), isTrue);
    expect(limousinePickedPathIsContentUri('/tmp/cover.jpg'), isFalse);
    expect(limousineDetectImageMime(_kTinyPng), 'image/png');
    expect(limousineDetectImageMime(Uint8List.fromList(<int>[0, 1, 2])), '');
    expect(limousineHeroRefIsDurable(_kCover), isTrue);
    expect(limousineHeroRefIsDurable(_kContentUri), isFalse);
    expect(limousineHeroRefIsDurable('file:///tmp/cover.jpg'), isFalse);
  });

  test('gallery items keep one row per media identity', () {
    final items = limousineCoverGalleryItems(vehicles);
    expect(items.map((item) => item.url).toList(), <String>[
      'https://cdn.example/party.jpg',
      'https://cdn.example/party-side.jpg',
      'https://cdn.example/hummer.jpg',
      'https://cdn.example/hummer-rear.jpg',
    ]);
    expect(
      items.where((item) => item.vehicleName == 'Party Limo'),
      hasLength(2),
    );
    expect(
      items
          .where((item) => item.vehicleName == 'Party Limo')
          .map((item) => item.photoIndex),
      <int>[1, 2],
    );
  });

  test('setup media validation reads size and rejects oversized files', () {
    expect(limousineImagePixelSize(_kTinyPng)?.width, 1);
    expect(limousinePngHasAlpha(_kTinyPng), isTrue);
    final huge = Uint8List(4 * 1024 * 1024 + 8);
    huge.setRange(0, _kTinyPng.length, _kTinyPng);
    expect(
      () => limousineValidateSetupMedia(
        huge,
        target: limousineSetupMediaTarget(LimousineSetupMediaKind.logo),
      ),
      throwsA(
        isA<LimousinePickedMediaException>().having(
          (error) => error.isTooLarge,
          'isTooLarge',
          isTrue,
        ),
      ),
    );
    final wide = Uint8List.fromList(_kTinyPng);
    wide[16] = 0;
    wide[17] = 0;
    wide[18] = 0x23;
    wide[19] = 0x28; // 9000
    expect(
      () => limousineValidateSetupMedia(
        wide,
        target: limousineSetupMediaTarget(LimousineSetupMediaKind.cover),
      ),
      throwsA(isA<LimousinePickedMediaException>()),
    );
  });

  test('11 settings preview uses the public card crop spec', () {
    final tablet = limousinePublicCoverSpec(
      viewport: kLimousineSmX400Portrait,
      explicitCover: true,
      alignment: Alignment.bottomCenter,
    );
    expect(tablet.aspectRatio, kLimousinePublicCoverTabletAspect);
    expect(tablet.fit, BoxFit.cover);
    expect(tablet.alignment, Alignment.bottomCenter);
    expect(tablet.minHeight, 240);
    final size = limousinePublicCoverPreviewSize(
      maxWidth: kLimousineSmX400Portrait.width,
      spec: tablet,
    );
    expect(size.height, greaterThan(148));
    expect(size.height / size.width, closeTo(1 / tablet.aspectRatio, 0.02));

    final phone = limousinePublicCoverSpec(
      viewport: kLimousinePhonePortrait,
      explicitCover: false,
    );
    expect(phone.aspectRatio, kLimousinePublicCoverPhoneAspect);
    expect(phone.fit, BoxFit.contain);
  });

  testWidgets('1-6 content URI pick uploads bytes and refreshes the preview', (
    tester,
  ) async {
    delayedPick = Completer<LimousineSetupPickedImage?>();
    await pumpSetup(tester);
    await tester.ensureVisible(
      find.byKey(kLimousineBusinessSetupCoverUploadKey),
    );
    await tester.tap(find.byKey(kLimousineBusinessSetupCoverUploadKey));
    await tester.pump();

    expect(pickCalls, 1);
    expect(
      find.byKey(kLimousineBusinessSetupCoverUploadingKey),
      findsOneWidget,
    );
    expect(
      tester
          .widget<ButtonStyleButton>(
            find.byKey(kLimousineBusinessSetupCoverUploadKey),
          )
          .onPressed,
      isNull,
    );

    delayedPick!.complete(nextPick);
    await pumpUpload(tester);

    expect(uploads, hasLength(1));
    expect(uploads.single['mediaType'], kLimousineProfileCoverMediaType);
    expect(uploads.single['hasBytes'], 'true');
    expect(uploads.single['filePath'], isNot(contains('content://')));
    expect(saves, isNotEmpty);
    expect(
      (saves.last[kLimousineProfileCoverKey] as Map)['photo_url'],
      _kCover,
    );
    expect(saves.last.toString(), isNot(contains('content://')));
    expect(saves.last.toString(), isNot(contains('file:')));
    expect(find.text(kLimousineBusinessSetupCoverReplace.nl), findsOneWidget);
    expect(
      find.text(kLimousineBusinessSetupCoverUploadSuccess.nl),
      findsWidgets,
    );
    final preview = tester.widget<LimousineContainPhoto>(
      find.descendant(
        of: find.byKey(kLimousineBusinessSetupCoverPreviewKey),
        matching: find.byType(LimousineContainPhoto),
      ),
    );
    expect(preview.imageUrl, _kCover);
    expect(preview.fit, BoxFit.cover);
  });

  testWidgets(
    '2 8 9 lost content URI recovers; failed upload keeps previous hero',
    (tester) async {
      nextPick = null;
      lostPick = LimousineSetupPickedImage(
        path: 'content://media/picker/lost',
        name: 'lost.jpg',
        bytes: _kTinyPng,
      );
      await pumpSetup(
        tester,
        load: () async {
          return <String, dynamic>{
            'limousine': <String, dynamic>{
              'enabled': true,
              'offers': <Map<String, dynamic>>[_offer()],
              kLimousineProfileCoverKey: <String, dynamic>{
                'photo_url': _kPrevCover,
                'alignment': 'center',
                'source_kind': kLimousineHeroSourceUpload,
              },
            },
          };
        },
        includeRecover: true,
      );
      expect(find.text(kLimousineBusinessSetupCoverReplace.nl), findsOneWidget);

      returnLocalUri = true;
      await tester.ensureVisible(
        find.byKey(kLimousineBusinessSetupCoverUploadKey),
      );
      await tester.tap(find.byKey(kLimousineBusinessSetupCoverUploadKey));
      await pumpUpload(tester);
      expect(
        find.text(kLimousineBusinessSetupCoverUploadFailed.nl),
        findsWidgets,
      );
      final kept = tester.widget<LimousineContainPhoto>(
        find.descendant(
          of: find.byKey(kLimousineBusinessSetupCoverPreviewKey),
          matching: find.byType(LimousineContainPhoto),
        ),
      );
      expect(kept.imageUrl, _kPrevCover);

      returnLocalUri = false;
      nextPick = LimousineSetupPickedImage(
        path: _kContentUri,
        name: 'next.jpg',
        bytes: _kTinyPng,
      );
      await tester.tap(find.byKey(kLimousineBusinessSetupCoverUploadKey));
      await pumpUpload(tester);
      expect(
        (saves.last[kLimousineProfileCoverKey] as Map)['photo_url'],
        _kCover,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await pumpSetup(tester);
      expect(find.text(kLimousineBusinessSetupCoverReplace.nl), findsOneWidget);
      expect(
        tester
            .widget<LimousineContainPhoto>(
              find.descendant(
                of: find.byKey(kLimousineBusinessSetupCoverPreviewKey),
                matching: find.byType(LimousineContainPhoto),
              ),
            )
            .imageUrl,
        _kCover,
      );
    },
  );

  testWidgets('7 10 18 reopen keeps cover; taxi hero is untouched', (
    tester,
  ) async {
    await pumpSetup(tester);
    await tester.ensureVisible(
      find.byKey(kLimousineBusinessSetupCoverUploadKey),
    );
    await tester.tap(find.byKey(kLimousineBusinessSetupCoverUploadKey));
    await pumpUpload(tester);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await pumpSetup(tester);
    expect(find.text(kLimousineBusinessSetupCoverReplace.nl), findsOneWidget);
    expect(saves.last.containsKey('publicHeroPhotoUrl'), isFalse);
    expect(saves.last.containsKey('hero_photo_url'), isFalse);
    expect(taxiHeroSnapshot, _kTaxiHero);
    expect(
      (saves.last[kLimousineProfileCoverKey] as Map)['photo_url'],
      isNot(_kTaxiHero),
    );
  });

  testWidgets(
    '12 13 tablet preview is taller, overflow-free and follows focus',
    (tester) async {
      for (final size in <Size>[
        kLimousineSmX400Portrait,
        kLimousineTabletLandscape,
        kLimousinePhonePortrait,
      ]) {
        await pumpSetup(tester, size: size);
        await tester.ensureVisible(
          find.byKey(kLimousineBusinessSetupCoverPreviewKey),
        );
        final rect = tester.getRect(
          find.byKey(kLimousineBusinessSetupCoverPreviewKey),
        );
        expect(rect.height, greaterThan(148));
        expect(tester.takeException(), isNull);
      }

      await tester.ensureVisible(
        find.byKey(limousineBusinessSetupCoverFocusKey('bottom')),
      );
      tester
          .widget<ChoiceChip>(
            find.byKey(limousineBusinessSetupCoverFocusKey('bottom')),
          )
          .onSelected!(true);
      await tester.pump();
      final previewPhoto = tester.widget<LimousineContainPhoto>(
        find.descendant(
          of: find.byKey(kLimousineBusinessSetupCoverPreviewKey),
          matching: find.byType(LimousineContainPhoto),
        ),
      );
      expect(previewPhoto.alignment, Alignment.bottomCenter);
    },
  );

  testWidgets('public preview hides photo counts and internal offer scopes', (
    tester,
  ) async {
    await pumpSetup(tester);
    expect(
      find.descendant(
        of: find.byKey(kLimousineBusinessSetupPreviewKey),
        matching: find.text(kLimousineBusinessSetupAppliesTo.nl),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(kLimousineBusinessSetupPreviewKey),
        matching: find.text('Party Limo · 2'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(kLimousineBusinessSetupPreviewKey),
        matching: find.text('Hummer white · 4'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(kLimousineBusinessSetupPreviewKey),
        matching: find.textContaining('2 limousines'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(kLimousineBusinessSetupPreviewKey),
        matching: find.textContaining('Vanaf €250'),
      ),
      findsNothing,
    );
  });

  testWidgets('14-16 existing photo picker shows unique thumbnails', (
    tester,
  ) async {
    await pumpSetup(tester);
    await tester.ensureVisible(
      find.byKey(kLimousineBusinessSetupCoverPickGalleryKey),
    );
    await tester.tap(find.byKey(kLimousineBusinessSetupCoverPickGalleryKey));
    await tester.pump();

    final dialog = find.byKey(kLimousineBusinessSetupCoverGalleryDialogKey);
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(of: dialog, matching: find.byType(Image)),
      findsWidgets,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('Party Limo')),
      findsNWidgets(2),
    );
    expect(
      find.descendant(of: dialog, matching: find.text('Hummer white')),
      findsNWidgets(2),
    );
    expect(
      find.descendant(of: dialog, matching: find.text('Foto 1')),
      findsNWidgets(2),
    );
    expect(
      find.descendant(of: dialog, matching: find.text('Foto 2')),
      findsNWidgets(2),
    );
    expect(
      find.descendant(of: dialog, matching: find.text('Foto 3')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(
        limousineBusinessSetupCoverGalleryItemKey(
          'https://cdn.example/party-side.jpg',
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(kLimousineBusinessSetupCoverGalleryUseKey));
    await pumpUpload(tester);

    expect(uploads, isEmpty);
    expect(
      (saves.last[kLimousineProfileCoverKey] as Map)['photo_url'],
      'https://cdn.example/party-side.jpg',
    );
    expect(find.text(kLimousineBusinessSetupCoverReplace.nl), findsOneWidget);
  });
}
