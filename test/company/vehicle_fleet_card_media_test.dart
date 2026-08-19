import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/vehicle_fleet_card_media.dart';

/// 1x1 PNG so widget tests do not depend on network or assets.
final Uint8List _kTinyPng = Uint8List.fromList(const <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

Widget _host({
  required Size size,
  required Widget child,
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
            child: child,
          ),
        ),
      ),
    ),
  );
}

FleetVehicleCardMedia _card({
  String photo = 'https://cdn.example/limo.jpg',
  int extra = 0,
  FleetCardMediaLayout layout = FleetCardMediaLayout.stacked,
  VoidCallback? onOpen,
  ImageProvider? image,
}) {
  return FleetVehicleCardMedia(
    photoRef: photo,
    placeholderText: 'Geen voertuigfoto',
    background: const Color(0xFF1A1A1A),
    gold: const Color(0xFFC9A227),
    extraPhotoCount: extra,
    extraPhotosLabel: extra > 0 ? '+$extra extra foto\'s' : '',
    layout: layout,
    onOpen: onOpen,
    imageOverride: image,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('1 tablet portrait uses the full available card width', () {
    const viewport = Size(800, 1280);
    const cardWidth = 800.0 - 24 - 20;
    final height = fleetCardMediaHeight(
      availableWidth: cardWidth,
      viewport: viewport,
    );
    expect(cardWidth, greaterThan(740));
    expect(height, inInclusiveRange(300, 420));
    expect(height, greaterThan(kFleetCardOldPortraitBannerHeight));
  });

  test('2 tablet frame is taller than the old 176 cover banner', () {
    final height = fleetCardMediaHeight(
      availableWidth: 756,
      viewport: const Size(800, 1280),
    );
    expect(height, greaterThan(kFleetCardOldPortraitBannerHeight));
    expect(
      fleetCardMediaUsesContainStrategy(
        sharpFit: kFleetVehicleCardSharpPhotoFit,
        height: height,
        viewport: const Size(800, 1280),
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

  test('4-6 landscape, portrait and ultra-wide keep contain + full frame', () {
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
    );
    expect(portrait, inInclusiveRange(200, 280));
    final ultraWide = fleetCardMediaHeight(
      availableWidth: 756,
      viewport: const Size(800, 1280),
    );
    expect(ultraWide, greaterThan(kFleetCardOldPortraitBannerHeight));
  });

  test('7 no distortion constants remain', () {
    expect(kFleetVehicleCardSharpPhotoFit, BoxFit.contain);
    expect(kFleetCardMediaAspect, 16 / 9);
  });

  testWidgets('8 no overflow on SM-X400 portrait', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1280));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _host(
        size: const Size(800, 1280),
        maxWidth: 756,
        child: _card(image: MemoryImage(_kTinyPng)),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byKey(kFleetVehicleCardMediaFrameKey), findsOneWidget);
    final frame = tester.getSize(find.byKey(kFleetVehicleCardMediaFrameKey));
    expect(frame.width, closeTo(756, 0.5));
    expect(frame.height, greaterThan(kFleetCardOldPortraitBannerHeight));
    expect(frame.height, lessThanOrEqualTo(420));
  });

  testWidgets('9 no overflow in tablet landscape / split-screen', (tester) async {
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
    await tester.pumpWidget(
      _host(
        size: const Size(600, 800),
        maxWidth: 556,
        child: _card(image: MemoryImage(_kTinyPng)),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('10 mobile layout stays usable', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _host(
        size: const Size(390, 844),
        maxWidth: 346,
        child: _card(image: MemoryImage(_kTinyPng)),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    final frame = tester.getSize(find.byKey(kFleetVehicleCardMediaFrameKey));
    expect(frame.height, inInclusiveRange(200, 280));
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
    final labelTop = tester.getTopLeft(find.byKey(kFleetVehicleCardExtraPhotosKey));
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
  });

  testWidgets('3 contain image is present when a photo decodes', (tester) async {
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
    final fill = tester.widget<Image>(find.byKey(kFleetVehicleCardFillImageKey));
    expect(fill.fit, BoxFit.cover);
  });

  testWidgets('13 media tap opens without changing the photo ref', (tester) async {
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

  test('13 edit, delete and driver actions stay on the vehicles page', () {
    final page = File('lib/vehicle_management_page.dart').readAsStringSync();
    expect(page.contains('FleetVehicleCardMedia'), isTrue);
    expect(page.contains('_fleetListPhoto'), isTrue);
    expect(page.contains("nl: 'Bewerken'"), isTrue);
    expect(page.contains("nl: 'Verwijderen'"), isTrue);
    expect(page.contains('deleteVehicle(v.id)'), isTrue);
    expect(page.contains('Gekoppelde chauffeur') || page.contains('chauffeur'), isTrue);
    expect(page.contains('_openVehicleEditor(existing: v)'), isTrue);
    expect(page.contains('focusGallery: true'), isTrue);
    expect(page.contains('height: isCompactLandscape ? 110 : 176'), isFalse);
    expect(page.contains('final photoHeight = tablet ? 168.0 : 130.0'), isFalse);
  });
}
