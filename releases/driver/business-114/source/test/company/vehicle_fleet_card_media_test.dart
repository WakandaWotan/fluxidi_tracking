import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/vehicle_fleet_card_media.dart';

/// 1x1 PNG so widget tests do not depend on network or assets.
final Uint8List _kTinyPng = Uint8List.fromList(const <int>[
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
  0x0A,
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

final Uint8List _kPng16x9 = Uint8List.fromList(const <int>[
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  0,
  0,
  0,
  13,
  73,
  72,
  68,
  82,
  0,
  0,
  0,
  16,
  0,
  0,
  0,
  9,
  8,
  6,
  0,
  0,
  0,
  59,
  42,
  172,
  50,
  0,
  0,
  0,
  22,
  73,
  68,
  65,
  84,
  120,
  218,
  99,
  216,
  192,
  160,
  240,
  159,
  18,
  204,
  48,
  106,
  192,
  168,
  1,
  64,
  12,
  0,
  90,
  0,
  4,
  128,
  103,
  21,
  56,
  247,
  0,
  0,
  0,
  0,
  73,
  69,
  78,
  68,
  174,
  66,
  96,
  130,
]);
Widget _host({required Size size, required Widget child, double? maxWidth}) {
  return _hostList(size: size, maxWidth: maxWidth, children: [child]);
}

Widget _hostList({
  required Size size,
  required List<Widget> children,
  double? maxWidth,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: maxWidth ?? size.width,
            child: ListView(padding: EdgeInsets.zero, children: children),
          ),
        ),
      ),
    ),
  );
}

FleetVehicleCardMedia _card({
  Key? key,
  String photo = 'https://cdn.example/limo.jpg',
  int extra = 0,
  FleetCardMediaLayout layout = FleetCardMediaLayout.stacked,
  VoidCallback? onOpen,
  ImageProvider? image,
  double? sourceAspectRatio,
}) {
  return FleetVehicleCardMedia(
    key: key,
    photoRef: photo,
    placeholderText: 'Geen voertuigfoto',
    background: const Color(0xFF1A1A1A),
    gold: const Color(0xFFC9A227),
    extraPhotoCount: extra,
    extraPhotosLabel: extra > 0 ? '+$extra extra foto\'s' : '',
    layout: layout,
    onOpen: onOpen,
    imageOverride: image,
    sourceAspectRatio: sourceAspectRatio,
  );
}

Future<void> _pumpPortrait({
  required WidgetTester tester,
  required Size viewport,
  required double cardWidth,
  required List<Widget> children,
}) async {
  await tester.binding.setSurfaceSize(viewport);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    _hostList(size: viewport, maxWidth: cardWidth, children: children),
  );
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void _expectPortraitPhotoContract({
  required WidgetTester tester,
  required Finder frameFinder,
  required double cardWidth,
  required double sourceAspect,
}) {
  expect(tester.takeException(), isNull);
  expect(find.byKey(kFleetVehicleCardPortraitFullWidthKey), findsWidgets);
  expect(find.byKey(kFleetVehicleCardFillImageKey), findsNothing);

  final frameBox = tester.widget<SizedBox>(frameFinder);
  expect(frameBox.width, double.infinity);

  final contain = tester.widget<Image>(
    find.descendant(
      of: frameFinder,
      matching: find.byKey(kFleetVehicleCardContainImageKey),
    ),
  );
  expect(contain.fit, BoxFit.contain);
  expect(contain.fit, isNot(BoxFit.cover));
  expect(contain.fit, isNot(BoxFit.fill));

  final frame = tester.getSize(frameFinder);
  expect(frame.width, closeTo(cardWidth, 0.5));
  expect(
    frame.height,
    closeTo(
      fleetCardPortraitPhotoHeight(
        availableWidth: cardWidth,
        aspectRatio: sourceAspect,
      ),
      1.0,
    ),
  );
  expect(frame.width / frame.height, closeTo(sourceAspect, 0.02));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'portrait screen uses full available width and source aspect height',
    () {
      const viewport = Size(800, 1280);
      const cardWidth = 756.0;
      expect(fleetCardMediaIsPortraitScreen(viewport), isTrue);
      expect(
        fleetCardMediaUsesFullWidthPortraitLayout(
          layout: FleetCardMediaLayout.stacked,
          viewport: viewport,
        ),
        isTrue,
      );
      final wide = fleetCardMediaBox(
        availableWidth: cardWidth,
        viewport: viewport,
        sourceAspectRatio: 16 / 9,
      );
      expect(wide.width, cardWidth);
      expect(wide.height, closeTo(cardWidth / (16 / 9), 0.01));
      expect(wide.height, greaterThan(kFleetCardTabletPortraitMaxHeight));

      final square = fleetCardMediaBox(
        availableWidth: cardWidth,
        viewport: viewport,
        sourceAspectRatio: 1,
      );
      expect(square.height, cardWidth);
      expect(square.height, isNot(equals(wide.height)));
    },
  );

  test('phone portrait also uses full width and source aspect', () {
    const viewport = Size(390, 844);
    const cardWidth = 346.0;
    final box = fleetCardMediaBox(
      availableWidth: cardWidth,
      viewport: viewport,
      sourceAspectRatio: 16 / 9,
    );
    expect(box.width, cardWidth);
    expect(box.height, closeTo(cardWidth / (16 / 9), 0.01));
    expect(
      fleetCardMediaUsesContainStrategy(
        sharpFit: kFleetVehicleCardSharpPhotoFit,
        height: box.height,
        viewport: viewport,
      ),
      isTrue,
    );
  });

  test('3 sharp photo fit is contain, never fill or stretch', () {
    expect(kFleetVehicleCardSharpPhotoFit, BoxFit.contain);
    expect(kFleetVehicleCardFillPhotoFit, BoxFit.cover);
    expect(kFleetVehicleCardSharpPhotoFit, isNot(BoxFit.fill));
    expect(kFleetVehicleCardSharpPhotoFit, isNot(BoxFit.cover));
  });

  test(
    '4-6 landscape stays compact; portrait no longer uses the 16:9 clamp',
    () {
      expect(kFleetVehicleCardSharpPhotoFit, BoxFit.contain);
      final landscape = fleetCardMediaHeight(
        availableWidth: 417,
        viewport: const Size(1280, 800),
        layout: FleetCardMediaLayout.sideColumn,
      );
      expect(landscape, greaterThan(kFleetCardOldTabletLandscapeBannerHeight));
      final portrait = fleetCardMediaHeight(
        availableWidth: 346,
        viewport: const Size(390, 844),
        sourceAspectRatio: 16 / 9,
      );
      expect(portrait, closeTo(346 / (16 / 9), 0.01));
      final ultraWide = fleetCardMediaBox(
        availableWidth: 756,
        viewport: const Size(800, 1280),
        sourceAspectRatio: 16 / 9,
      );
      expect(ultraWide.width, 756);
      expect(ultraWide.height, closeTo(756 / (16 / 9), 0.01));
    },
  );

  test('7 no distortion constants remain', () {
    expect(kFleetVehicleCardSharpPhotoFit, BoxFit.contain);
    expect(kFleetCardMediaAspect, 16 / 9);
  });

  test('portrait stacked source has no narrow maxWidth photo column', () {
    final src = File('lib/vehicle_fleet_card_media.dart').readAsStringSync();
    expect(
      src.contains('math.min(availableWidth, height * kFleetCardMediaAspect)'),
      isFalse,
    );
    expect(src.contains('width: double.infinity'), isTrue);
    expect(src.contains('letterboxFill: false'), isTrue);
    expect(src.contains('fleetCardPortraitPhotoHeight'), isTrue);
  });

  testWidgets(
    'tablet portrait: full card width, source aspect, contain, no overflow',
    (tester) async {
      const viewport = Size(800, 1280);
      const cardWidth = 756.0;
      final wide = MemoryImage(_kPng16x9);
      final square = MemoryImage(_kTinyPng);

      await _pumpPortrait(
        tester: tester,
        viewport: viewport,
        cardWidth: cardWidth,
        children: [
          _card(
            key: const Key('tesla'),
            image: wide,
            sourceAspectRatio: 16 / 9,
          ),
          _card(key: const Key('van'), image: square, sourceAspectRatio: 1),
        ],
      );

      expect(find.byKey(kFleetVehicleCardMediaFrameKey), findsNWidgets(2));
      expect(find.byKey(kFleetVehicleCardFillImageKey), findsNothing);
      expect(find.byKey(kFleetVehicleCardContainImageKey), findsNWidgets(2));
      expect(tester.takeException(), isNull);

      final teslaFrame = find.descendant(
        of: find.byKey(const Key('tesla')),
        matching: find.byKey(kFleetVehicleCardMediaFrameKey),
      );
      final vanFrame = find.descendant(
        of: find.byKey(const Key('van')),
        matching: find.byKey(kFleetVehicleCardMediaFrameKey),
      );
      _expectPortraitPhotoContract(
        tester: tester,
        frameFinder: teslaFrame,
        cardWidth: cardWidth,
        sourceAspect: 16 / 9,
      );
      _expectPortraitPhotoContract(
        tester: tester,
        frameFinder: vanFrame,
        cardWidth: cardWidth,
        sourceAspect: 1,
      );

      final first = tester.getSize(teslaFrame);
      final second = tester.getSize(vanFrame);
      expect(first.width, second.width);
      expect(first.width, cardWidth);
      expect(first.height, isNot(equals(second.height)));
      expect(first.height, greaterThan(kFleetCardTabletPortraitMaxHeight));
    },
  );

  testWidgets(
    'phone portrait: full card width, source aspect, contain, no overflow',
    (tester) async {
      const viewport = Size(390, 844);
      const cardWidth = 346.0;
      final wide = MemoryImage(_kPng16x9);
      final fourThree = MemoryImage(_kTinyPng);

      await _pumpPortrait(
        tester: tester,
        viewport: viewport,
        cardWidth: cardWidth,
        children: [
          _card(
            key: const Key('tesla-phone'),
            image: wide,
            sourceAspectRatio: 16 / 9,
          ),
          _card(
            key: const Key('sprinter-phone'),
            image: fourThree,
            sourceAspectRatio: 1,
          ),
        ],
      );

      expect(find.byKey(kFleetVehicleCardMediaFrameKey), findsNWidgets(2));
      expect(find.byKey(kFleetVehicleCardFillImageKey), findsNothing);
      expect(tester.takeException(), isNull);

      final teslaFrame = find.descendant(
        of: find.byKey(const Key('tesla-phone')),
        matching: find.byKey(kFleetVehicleCardMediaFrameKey),
      );
      final sprinterFrame = find.descendant(
        of: find.byKey(const Key('sprinter-phone')),
        matching: find.byKey(kFleetVehicleCardMediaFrameKey),
      );
      _expectPortraitPhotoContract(
        tester: tester,
        frameFinder: teslaFrame,
        cardWidth: cardWidth,
        sourceAspect: 16 / 9,
      );
      _expectPortraitPhotoContract(
        tester: tester,
        frameFinder: sprinterFrame,
        cardWidth: cardWidth,
        sourceAspect: 1,
      );

      expect(
        tester.getSize(teslaFrame).width,
        tester.getSize(sprinterFrame).width,
      );
      expect(
        tester.getSize(teslaFrame).height,
        isNot(equals(tester.getSize(sprinterFrame).height)),
      );
    },
  );

  testWidgets('8 no overflow on SM-X400 portrait', (tester) async {
    final image = MemoryImage(_kPng16x9);
    await tester.binding.setSurfaceSize(const Size(800, 1280));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _host(
        size: const Size(800, 1280),
        maxWidth: 756,
        child: _card(image: image),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.takeException(), isNull);
    expect(find.byKey(kFleetVehicleCardMediaFrameKey), findsOneWidget);
    final frame = tester.getSize(find.byKey(kFleetVehicleCardMediaFrameKey));
    expect(frame.width, 756);
    expect(frame.height, closeTo(756 / (16 / 9), 1.0));
    expect(find.byKey(kFleetVehicleCardFillImageKey), findsNothing);
    expect(find.byKey(kFleetVehicleCardContainImageKey), findsOneWidget);
  });

  testWidgets('9 no overflow in tablet landscape / split-screen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _host(
        size: const Size(1280, 800),
        maxWidth: 420,
        child: _card(
          layout: FleetCardMediaLayout.sideColumn,
          image: MemoryImage(_kTinyPng),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    final frame = tester.getSize(find.byKey(kFleetVehicleCardMediaFrameKey));
    expect(frame.height, lessThan(800));
    expect(frame.height, greaterThan(kFleetCardOldTabletLandscapeBannerHeight));

    await tester.binding.setSurfaceSize(const Size(600, 800));
    final splitImage = MemoryImage(_kPng16x9);
    await tester.pumpWidget(
      _host(
        size: const Size(600, 800),
        maxWidth: 556,
        child: _card(image: splitImage),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.takeException(), isNull);
    final split = tester.getSize(find.byKey(kFleetVehicleCardMediaFrameKey));
    expect(split.width, 556);
    expect(split.height, closeTo(556 / (16 / 9), 1.0));
  });

  testWidgets('10 mobile layout stays usable', (tester) async {
    final image = MemoryImage(_kPng16x9);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _host(
        size: const Size(390, 844),
        maxWidth: 346,
        child: _card(image: image),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.takeException(), isNull);
    final frame = tester.getSize(find.byKey(kFleetVehicleCardMediaFrameKey));
    expect(frame.width, 346);
    expect(frame.height, closeTo(346 / (16 / 9), 1.0));
    expect(frame.height, greaterThan(kFleetCardOldPortraitBannerHeight));
  });

  testWidgets('11 invalid URL shows a clean placeholder', (tester) async {
    await tester.pumpWidget(
      _host(
        size: const Size(390, 844),
        child: _card(photo: '', image: null),
      ),
    );
    await tester.pump();
    expect(find.byKey(kFleetVehicleCardPlaceholderKey), findsOneWidget);
    expect(find.text('Geen voertuigfoto'), findsOneWidget);
    expect(find.byIcon(Icons.directions_car_filled_outlined), findsOneWidget);
    expect(find.byIcon(Icons.broken_image), findsNothing);
  });

  testWidgets('12 multiple photos show +N outside the image', (tester) async {
    await tester.pumpWidget(
      _host(
        size: const Size(800, 1280),
        child: _card(extra: 3, image: MemoryImage(_kTinyPng)),
      ),
    );
    await tester.pump();
    expect(find.byKey(kFleetVehicleCardExtraPhotosKey), findsOneWidget);
    expect(find.text('+3 extra foto\'s'), findsOneWidget);
    final photoBottom = tester.getBottomLeft(
      find.byKey(kFleetVehicleCardMediaFrameKey),
    );
    final labelTop = tester.getTopLeft(
      find.byKey(kFleetVehicleCardExtraPhotosKey),
    );
    expect(labelTop.dy, greaterThanOrEqualTo(photoBottom.dy));
  });

  test('extra photo count uses unique refs, not names or indexes', () {
    expect(
      fleetVehicleExtraPhotoCount(
        primaryPhotoRef: 'https://cdn.example/a.jpg',
        galleryPhotoRefs: const <String>[
          'https://cdn.example/a.jpg',
          'https://cdn.example/b.jpg',
          'https://cdn.example/c.jpg',
        ],
      ),
      2,
    );
    expect(
      fleetVehicleExtraPhotoCount(
        primaryPhotoRef: '',
        galleryPhotoRefs: const <String>[],
      ),
      0,
    );
    expect(
      fleetVehicleExtraPhotoCount(
        primaryPhotoRef: 'https://cdn.example/photo.jpg?v=1',
        galleryPhotoRefs: const <String>[
          'https://cdn.example/photo.jpg?v=2',
          'https://cdn.example/photo.jpg?v=3',
        ],
      ),
      0,
    );
  });

  testWidgets('3 tablet portrait has one contain photo and no fill layer', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        size: const Size(800, 1280),
        child: _card(image: MemoryImage(_kTinyPng)),
      ),
    );
    await tester.pump();
    final contain = tester.widget<Image>(
      find.byKey(kFleetVehicleCardContainImageKey),
    );
    expect(contain.fit, BoxFit.contain);
    expect(find.byKey(kFleetVehicleCardFillImageKey), findsNothing);
  });

  testWidgets('landscape keeps the compact fill-plus-contain column', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _host(
        size: const Size(1280, 800),
        maxWidth: 420,
        child: _card(
          layout: FleetCardMediaLayout.sideColumn,
          image: MemoryImage(_kTinyPng),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(kFleetVehicleCardFillImageKey), findsOneWidget);
    expect(find.byKey(kFleetVehicleCardContainImageKey), findsOneWidget);
  });

  testWidgets('13 media tap opens without changing the photo ref', (
    tester,
  ) async {
    var opens = 0;
    await tester.pumpWidget(
      _host(
        size: const Size(800, 1280),
        child: _card(
          extra: 2,
          image: MemoryImage(_kTinyPng),
          onOpen: () => opens++,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(kFleetVehicleCardMediaFrameKey));
    await tester.pump();
    expect(opens, 1);
  });

  testWidgets('wide and narrow source photos stay contained without overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1280));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final sample in <({MemoryImage image, double aspect})>[
      (image: MemoryImage(_kPng16x9), aspect: 16 / 9),
      (image: MemoryImage(_kTinyPng), aspect: 1),
    ]) {
      await tester.pumpWidget(
        _host(
          size: const Size(800, 1280),
          maxWidth: 756,
          child: _card(image: sample.image, sourceAspectRatio: sample.aspect),
        ),
      );
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.takeException(), isNull);
      final contain = tester.widget<Image>(
        find.byKey(kFleetVehicleCardContainImageKey),
      );
      expect(contain.fit, BoxFit.contain);
      expect(find.byKey(kFleetVehicleCardFillImageKey), findsNothing);
      final frame = tester.getSize(find.byKey(kFleetVehicleCardMediaFrameKey));
      expect(frame.width, 756);
      expect(frame.height, closeTo(756 / sample.aspect, 1.0));
    }
  });

  test('13 edit, delete and driver actions stay on the vehicles page', () {
    final page = File('lib/vehicle_management_page.dart').readAsStringSync();
    expect(page.contains('FleetVehicleCardMedia'), isTrue);
    expect(page.contains('_fleetListPhoto'), isTrue);
    expect(page.contains("nl: 'Bewerken'"), isTrue);
    expect(page.contains("nl: 'Verwijderen'"), isTrue);
    expect(page.contains('deleteVehicle(v.id)'), isTrue);
    expect(
      page.contains('Gekoppelde chauffeur') || page.contains('chauffeur'),
      isTrue,
    );
    expect(page.contains('_openVehicleEditor(existing: v)'), isTrue);
    expect(page.contains('focusGallery: true'), isTrue);
    expect(page.contains('height: isCompactLandscape ? 110 : 176'), isFalse);
    expect(
      page.contains('final photoHeight = tablet ? 168.0 : 130.0'),
      isFalse,
    );
  });
}
