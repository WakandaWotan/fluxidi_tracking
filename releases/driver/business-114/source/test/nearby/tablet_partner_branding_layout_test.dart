// TABLET-PARTNER-BRANDING-LAYOUT-1 + TABLET-PARTNER-MEDIA-POLISH-1
//
// Tablet-only partner card / favorites / profile hero branding splits.
// Phones (shortestSide < 600) keep the historic layouts.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/nearby/nearby_partner_hero_media.dart';
import 'package:fluxidi_tracking/nearby/tablet_partner_branding_layout.dart';

const String _reportDir =
    'test_reports/tablet_partner_photo_single_layer_20260805';

/// Minimal valid 1Ã—1 PNG.
final MemoryImage _tinyPng = MemoryImage(
  Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    ),
  ),
);

MemoryImage? _landscapeVehiclePng;
MemoryImage? _wideLogoPng;
MemoryImage? _squareLogoPng;

Future<MemoryImage> _paintPng({
  required int width,
  required int height,
  required Color fill,
  Color? accent,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = fill,
  );
  if (accent != null) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(width * 0.12, height * 0.28, width * 0.76, height * 0.42),
        const Radius.circular(10),
      ),
      Paint()..color = accent,
    );
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return MemoryImage(Uint8List.view(bytes!.buffer));
}

Widget _phoneShell({required Widget child, Size size = const Size(390, 844)}) {
  return MediaQuery(
    data: MediaQueryData(size: size),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: Padding(padding: const EdgeInsets.all(12), child: child),
      ),
    ),
  );
}

Widget _tabletShell({
  required Widget child,
  Size size = const Size(834, 1194),
  Key? boundaryKey,
}) {
  final body = Padding(padding: const EdgeInsets.all(16), child: child);
  return MediaQuery(
    data: MediaQueryData(size: size),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFE8E0D4),
        body: boundaryKey == null
            ? body
            : RepaintBoundary(key: boundaryKey, child: body),
      ),
    ),
  );
}

Future<void> _writePng(
  WidgetTester tester,
  Key boundaryKey,
  String filename,
) async {
  final boundary =
      tester.renderObject(find.byKey(boundaryKey)) as RenderRepaintBoundary;
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 1.5));
  final bytes = await tester.runAsync(
    () => image!.toByteData(format: ui.ImageByteFormat.png),
  );
  Directory(_reportDir).createSync(recursive: true);
  File('$_reportDir/$filename').writeAsBytesSync(bytes!.buffer.asUint8List());
}

Widget _tabletPartnerCard({
  required double maxCoverHeight,
  required double aspectRatio,
  required ImageProvider hero,
  required ImageProvider logo,
  required String company,
  Color panel = const Color(0xFFF3EDE3),
  Color card = const Color(0xFFFAF7F1),
}) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(14),
    child: ColoredBox(
      color: card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NearbyPartnerHeroMedia(
            height: maxCoverHeight,
            backgroundColor: panel,
            heroUrl: 'https://example.com/vehicle.jpg',
            heroImage: hero,
            aspectRatio: aspectRatio,
            borderRadius: 0,
            clipBorderRadius: const BorderRadius.vertical(
              top: Radius.circular(14),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
            child: Row(
              children: [
                NearbyPartnerLogoMark(
                  logoUrl: 'https://cdn.example.com/branding/logo.png',
                  logoImage: logo,
                  maxWidth: 168,
                  maxHeight: 64,
                  lightTheme: true,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    company,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    Directory(_reportDir).createSync(recursive: true);
    _landscapeVehiclePng = await _paintPng(
      width: 640,
      height: 280,
      fill: const Color(0xFF3A4654),
      accent: const Color(0xFFE8C24A),
    );
    _wideLogoPng = await _paintPng(
      width: 420,
      height: 120,
      fill: const Color(0xFF111111),
      accent: const Color(0xFFFFD36A),
    );
    _squareLogoPng = await _paintPng(
      width: 180,
      height: 180,
      fill: const Color(0xFF1B1B1B),
      accent: const Color(0xFF34D29A),
    );
  });

  group('breakpoint', () {
    test('phone shortestSide stays below tablet gate', () {
      expect(isTabletPartnerBrandingLayout(const Size(390, 844)), isFalse);
      expect(isTabletPartnerBrandingLayout(const Size(844, 390)), isFalse);
    });

    test('tablet shortestSide unlocks layout', () {
      expect(isTabletPartnerBrandingLayout(const Size(834, 1194)), isTrue);
      expect(isTabletPartnerBrandingLayout(const Size(1194, 834)), isTrue);
    });
  });

  group('phone nearby cover', () {
    testWidgets('phone nearby keeps a full-width contained cover', (
      tester,
    ) async {
      const size = Size(390, 844);
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _phoneShell(
          size: size,
          child: NearbyPartnerHeroMedia(
            height: nearbyPartnerHeroMediaHeight(size.width),
            backgroundColor: const Color(0xFFEDEDED),
            heroUrl: 'https://example.com/vehicle.jpg',
            heroImage: _tinyPng,
            aspectRatio: 2.4,
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey<String>('nearby_partner_tablet_media_split')),
        findsNothing,
      );
      expect(find.byKey(PartnerTabletPhotoFill.imageKey), findsNothing);
      expect(find.byType(ImageFiltered), findsNothing);
      expect(find.byType(CircleAvatar), findsNothing);
      expect(tester.widget<Image>(find.byType(Image).first).fit, BoxFit.contain);
      final box = tester.getSize(
        find.byKey(const ValueKey<String>('nearby_partner_cover_box')),
      );
      expect(box.width, greaterThan(300));
      expect(box.height, closeTo(box.width / 2.4, 1));
      expect(tester.takeException(), isNull);
    });
  });

  group('tablet nearby cover', () {
    testWidgets('tablet partner card shows the full wide cover above the logo', (
      tester,
    ) async {
      const size = Size(834, 1194);
      const boundaryKey = ValueKey<String>('nearby_tablet_boundary');
      const ratio = 640 / 280;
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _tabletShell(
          size: size,
          boundaryKey: boundaryKey,
          child: _tabletPartnerCard(
            maxCoverHeight: nearbyPartnerHeroMediaHeight(size.width),
            aspectRatio: ratio,
            hero: _landscapeVehiclePng!,
            logo: _wideLogoPng!,
            company:
                'Fluxidi Partner BV â€” Extra Long Company Name For Overflow Guard',
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey<String>('nearby_partner_tablet_media_split')),
        findsNothing,
      );
      expect(find.byType(CircleAvatar), findsNothing);
      expect(find.byType(NearbyPartnerLogoMark), findsOneWidget);
      final cover = tester.widget<Image>(
        find.byKey(const ValueKey<String>('nearby_partner_cover_image')),
      );
      expect(cover.fit, BoxFit.contain);
      final box = tester.getSize(
        find.byKey(const ValueKey<String>('nearby_partner_cover_box')),
      );
      expect(box.height, closeTo(box.width / ratio, 1));
      final coverRect = tester.getRect(
        find.byKey(const ValueKey<String>('nearby_partner_cover_box')),
      );
      final logoRect = tester.getRect(find.byType(NearbyPartnerLogoMark));
      expect(logoRect.top, greaterThan(coverRect.bottom - 1));
      expect(tester.takeException(), isNull);

      await _writePng(
        tester,
        boundaryKey,
        'tablet_nearby_partner_card_wide_logo.png',
      );
    });

    testWidgets('missing cover leaves the logo mark without a split', (
      tester,
    ) async {
      const size = Size(834, 1194);
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _tabletShell(
          child: const Column(
            children: [
              NearbyPartnerHeroMedia(
                height: 220,
                backgroundColor: Colors.grey,
                heroUrl: '',
              ),
              NearbyPartnerLogoMark(
                logoUrl: '',
                maxWidth: 168,
                maxHeight: 64,
                lightTheme: true,
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('nearby_partner_cover_image')),
        findsNothing,
      );
      expect(find.byKey(PartnerBrandingLogoPlate.fallbackKey), findsOneWidget);
      expect(find.byType(NearbyPartnerLogoMark), findsOneWidget);
    });

    testWidgets('wide and square covers keep contain on phone and tablet', (
      tester,
    ) async {
      const boundaryKey = ValueKey<String>('nearby_two_cards_boundary');
      addTearDown(() => tester.binding.setSurfaceSize(null));
      Future<void> pumpAt(Size size) async {
        await tester.binding.setSurfaceSize(size);
        await tester.pumpWidget(
          _tabletShell(
            size: size,
            boundaryKey: boundaryKey,
            child: SingleChildScrollView(
            child: Column(
              children: [
                _tabletPartnerCard(
                  maxCoverHeight: nearbyPartnerHeroMediaHeight(size.width),
                  aspectRatio: 2.8,
                  hero: _landscapeVehiclePng!,
                  logo: _wideLogoPng!,
                  company: 'Taxi Mario â€” brede cover',
                ),
                const SizedBox(height: 12),
                _tabletPartnerCard(
                  maxCoverHeight: nearbyPartnerHeroMediaHeight(size.width),
                  aspectRatio: 1,
                  hero: _squareLogoPng!,
                  logo: _squareLogoPng!,
                  company: 'Partner â€” vierkante cover',
                ),
                const SizedBox(height: 12),
                const NearbyPartnerLogoMark(
                  logoUrl: '',
                  maxWidth: 136,
                  maxHeight: 54,
                  lightTheme: true,
                ),
              ],
            ),
            ),
          ),
        );
        await tester.pump();
        final images = tester
            .widgetList<Image>(
              find.byKey(const ValueKey<String>('nearby_partner_cover_image')),
            )
            .toList();
        expect(images, hasLength(2));
        for (final image in images) {
          expect(image.fit, BoxFit.contain);
        }
        final boxes = tester
            .getSize(
              find.byKey(const ValueKey<String>('nearby_partner_cover_box')).first,
            );
        expect(boxes.width, greaterThan(200));
        expect(tester.takeException(), isNull);
      }

      await pumpAt(const Size(390, 844));
      await pumpAt(const Size(844, 390));
      await pumpAt(const Size(834, 1194));
      await pumpAt(const Size(1194, 834));
      await _writePng(
        tester,
        boundaryKey,
        'tablet_nearby_both_partner_cards.png',
      );
    });
  });

  group('tablet favorites', () {
    testWidgets('tablet favorite uses rectangular logo plate', (tester) async {
      const size = Size(834, 1194);
      const boundaryKey = ValueKey<String>('favorites_tablet_boundary');
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final logo = TabletFavoritePartnerLogoMetrics.resolve(
        layoutWidth: size.width,
      );
      expect(logo.width, inInclusiveRange(110, 150));
      expect(logo.height, inInclusiveRange(60, 84));

      await tester.pumpWidget(
        _tabletShell(
          size: size,
          boundaryKey: boundaryKey,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PartnerBrandingLogoPlate(
                logoUrl: 'https://cdn.example.com/branding/square-mark.png',
                logoImage: _squareLogoPng,
                maxWidth: logo.width,
                maxHeight: logo.height,
                padding: logo.padding,
                backgroundColor: Colors.black26,
                borderColor: const Color(0xFFFFD36A),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mijn favoriete taxi â€” Superlange Bedrijfsnaam BV',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '9688 Maarkedal',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(CircleAvatar), findsNothing);
      expect(find.byType(PartnerBrandingLogoPlate), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _writePng(
        tester,
        boundaryKey,
        'tablet_favorites_square_logo.png',
      );
    });
  });

  group('partner profile hero', () {
    testWidgets('phone profile hero keeps cover + square overlay contract', (
      tester,
    ) async {
      const size = Size(390, 844);
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      expect(isTabletPartnerBrandingLayout(size), isFalse);

      await tester.pumpWidget(
        _phoneShell(
          size: size,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              children: [
                Image(
                  image: _tinyPng,
                  height: 244,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
                Positioned(
                  left: 12,
                  bottom: 10,
                  child: SizedBox(
                    width: 82,
                    height: 82,
                    child: Image(image: _tinyPng, fit: BoxFit.cover),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      final fits = tester
          .widgetList<Image>(find.byType(Image))
          .map((i) => i.fit)
          .toList();
      expect(fits, contains(BoxFit.cover));
      expect(
        find.byKey(const ValueKey<String>('partner_profile_tablet_hero_split')),
        findsNothing,
      );
      expect(find.byKey(PartnerTabletPhotoFill.imageKey), findsNothing);
    });

    testWidgets('tablet profile hero uses 55/45 split and single cover photo', (
      tester,
    ) async {
      const size = Size(834, 1194);
      const boundaryKey = ValueKey<String>('profile_tablet_boundary');
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final split = TabletPartnerProfileHeroSplit.resolve(
        layoutWidth: size.width,
        isLandscape: false,
      );
      expect(split.photoFlex, 55);
      expect(split.brandingFlex, 45);

      await tester.pumpWidget(
        _tabletShell(
          size: size,
          boundaryKey: boundaryKey,
          child: ClipRRect(
            key: const ValueKey<String>('partner_profile_tablet_hero_split'),
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              height: split.height,
              child: Row(
                key: const ValueKey<String>('partner_profile_tablet_hero_row'),
                children: [
                  Expanded(
                    flex: split.photoFlex,
                    child: PartnerTabletPhotoFill(
                      image: _landscapeVehiclePng!,
                    ),
                  ),
                  Expanded(
                    flex: split.brandingFlex,
                    child: ColoredBox(
                      color: const Color(0xFFFAF7F1),
                      child: Padding(
                        padding: split.logoPadding,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            PartnerBrandingLogoPlate(
                              logoUrl:
                                  'https://cdn.example.com/branding/f-fluxidi-wide.png',
                              logoImage: _wideLogoPng,
                              maxWidth: split.logoMaxWidth,
                              maxHeight: split.logoMaxHeight,
                              padding: const EdgeInsets.all(10),
                              backgroundColor: Colors.transparent,
                              borderColor: Colors.transparent,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Fluxidi',
                              style: TextStyle(
                                color: Colors.black87,
                                fontWeight: FontWeight.w800,
                                fontSize: 20,
                              ),
                            ),
                            const Text(
                              'Uw lokale partner',
                              style: TextStyle(color: Colors.black54),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey<String>('partner_profile_tablet_hero_split')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('partner_profile_tablet_hero_row')),
        findsOneWidget,
      );
      expect(find.byType(PartnerBrandingLogoPlate), findsOneWidget);
      expect(find.byType(CircleAvatar), findsNothing);
      // No legacy phone overlay stack layers inside the tablet hero.
      expect(
        find.descendant(
          of: find.byKey(
            const ValueKey<String>('partner_profile_tablet_hero_split'),
          ),
          matching: find.byType(Positioned),
        ),
        findsNothing,
      );
      final logoImage = tester.widget<Image>(
        find.byKey(PartnerBrandingLogoPlate.imageKey),
      );
      expect(logoImage.fit, BoxFit.contain);
      expect(find.byKey(PartnerTabletPhotoFill.imageKey), findsOneWidget);
      expect(
        tester.widget<Image>(find.byKey(PartnerTabletPhotoFill.imageKey)).fit,
        BoxFit.cover,
      );
      expect(find.byType(ImageFiltered), findsNothing);
      expect(find.byType(BackdropFilter), findsNothing);
      expect(tester.takeException(), isNull);

      await _writePng(
        tester,
        boundaryKey,
        'tablet_partner_profile_wide_logo.png',
      );
    });

    testWidgets('tablet profile wide and square logos both use contain', (
      tester,
    ) async {
      const size = Size(1194, 834);
      const boundaryKey = ValueKey<String>('logos_gallery_boundary');
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _tabletShell(
          size: size,
          boundaryKey: boundaryKey,
          child: Row(
            children: [
              PartnerBrandingLogoPlate(
                logoUrl: 'https://cdn.example.com/wide.png',
                logoImage: _wideLogoPng,
                maxWidth: 200,
                maxHeight: 90,
                padding: const EdgeInsets.all(10),
                backgroundColor: Colors.black26,
                borderColor: Colors.amber,
              ),
              const SizedBox(width: 16),
              PartnerBrandingLogoPlate(
                logoUrl: 'https://cdn.example.com/square.png',
                logoImage: _squareLogoPng,
                maxWidth: 120,
                maxHeight: 120,
                padding: const EdgeInsets.all(10),
                backgroundColor: Colors.black26,
                borderColor: Colors.amber,
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      final plates = find.byType(PartnerBrandingLogoPlate);
      expect(plates, findsNWidgets(2));
      for (final img in tester.widgetList<Image>(
        find.byKey(PartnerBrandingLogoPlate.imageKey),
      )) {
        expect(img.fit, BoxFit.contain);
      }
      await _writePng(tester, boundaryKey, 'tablet_wide_and_square_logos.png');
    });
  });
}
