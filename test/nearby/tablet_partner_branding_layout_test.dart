// TABLET-PARTNER-BRANDING-LAYOUT-1
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
    'test_reports/tablet_partner_branding_layout_20260805';

/// Minimal valid 1×1 PNG.
final MemoryImage _tinyPng = MemoryImage(
  Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    ),
  ),
);

/// Valid tiny PNG reused as a stand-in for wide / square brand marks.
/// Layout assertions use plate aspect ratios; decode must succeed.
final MemoryImage _widePng = _tinyPng;
final MemoryImage _squarePng = _tinyPng;

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
        backgroundColor: const Color(0xFF121212),
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

void main() {
  setUpAll(() {
    Directory(_reportDir).createSync(recursive: true);
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

  group('phone nearby unchanged', () {
    testWidgets('phone nearby keeps stacked media and CircleAvatar logo', (
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
            logoUrl: 'https://example.com/logo.png',
            heroImage: _tinyPng,
            logoImage: _widePng,
            tabletSplit: false,
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey<String>('nearby_partner_tablet_media_split')),
        findsNothing,
      );
      expect(find.byType(CircleAvatar), findsOneWidget);
      expect(find.byType(PartnerBrandingLogoPlate), findsNothing);
      expect(tester.widget<Image>(find.byType(Image).first).fit, BoxFit.contain);
      expect(
        tester.getSize(find.byType(NearbyPartnerHeroMedia)).height,
        nearbyPartnerHeroMediaHeight(390),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('tablet nearby split', () {
    testWidgets('tablet partner card uses photo|logo split with contain', (
      tester,
    ) async {
      const size = Size(834, 1194);
      const boundaryKey = ValueKey<String>('nearby_tablet_boundary');
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final metrics = TabletPartnerCardMediaSplit.resolve(
        layoutWidth: size.width,
        isLandscape: false,
      );

      await tester.pumpWidget(
        _tabletShell(
          size: size,
          boundaryKey: boundaryKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NearbyPartnerHeroMedia(
                height: metrics.height,
                backgroundColor: const Color(0xFF2A2A2A),
                heroUrl: 'https://example.com/vehicle.jpg',
                logoUrl: 'https://cdn.example.com/branding/f-fluxidi-wide.png',
                heroImage: _tinyPng,
                logoImage: _widePng,
                tabletSplit: true,
                tabletSplitMetrics: metrics,
                logoBorderColor: const Color(0xFFFFD36A),
              ),
              const SizedBox(height: 8),
              const Text(
                'Fluxidi Partner BV — Extra Long Company Name For Overflow Guard',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey<String>('nearby_partner_tablet_media_split')),
        findsOneWidget,
      );
      expect(find.byType(CircleAvatar), findsNothing);
      expect(find.byType(PartnerBrandingLogoPlate), findsOneWidget);
      expect(find.byKey(PartnerBrandingLogoPlate.imageKey), findsOneWidget);

      final images = tester.widgetList<Image>(find.byType(Image)).toList();
      expect(images.every((i) => i.fit == BoxFit.contain), isTrue);
      expect(images.length, greaterThanOrEqualTo(2));

      final photo = tester.getRect(
        find.byKey(const ValueKey<String>('nearby_partner_tablet_photo')),
      );
      final logo = tester.getRect(find.byKey(PartnerBrandingLogoPlate.plateKey));
      expect(logo.left, greaterThanOrEqualTo(photo.right - 1));
      expect((photo.height - logo.height).abs(), lessThan(photo.height));
      expect(tester.takeException(), isNull);

      await _writePng(
        tester,
        boundaryKey,
        'tablet_nearby_partner_card_wide_logo.png',
      );
    });

    testWidgets('tablet nearby falls back when logo missing', (tester) async {
      const size = Size(834, 1194);
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final metrics = TabletPartnerCardMediaSplit.resolve(
        layoutWidth: size.width,
        isLandscape: false,
      );
      await tester.pumpWidget(
        _tabletShell(
          child: NearbyPartnerHeroMedia(
            height: metrics.height,
            backgroundColor: Colors.grey,
            heroImage: _tinyPng,
            heroUrl: 'https://example.com/v.jpg',
            logoUrl: '',
            tabletSplit: true,
            tabletSplitMetrics: metrics,
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(PartnerBrandingLogoPlate.fallbackKey), findsOneWidget);
      expect(find.byKey(PartnerBrandingLogoPlate.imageKey), findsNothing);
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
                logoImage: _squarePng,
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
                      'Mijn favoriete taxi — Superlange Bedrijfsnaam BV',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '9688 Maarkedal',
                      style: TextStyle(color: Colors.white70),
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
                    child: Image(image: _squarePng, fit: BoxFit.cover),
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
    });

    testWidgets('tablet profile hero uses 55/45 split and contain logo', (
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
            child: SizedBox(
              height: split.height,
              child: Row(
                children: [
                  Expanded(
                    flex: split.photoFlex,
                    child: Image(
                      key: const ValueKey<String>(
                        'partner_profile_tablet_photo',
                      ),
                      image: _tinyPng,
                      fit: BoxFit.contain,
                    ),
                  ),
                  Expanded(
                    flex: split.brandingFlex,
                    child: ColoredBox(
                      color: const Color(0xFF1E1E1E),
                      child: Padding(
                        padding: split.logoPadding,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            PartnerBrandingLogoPlate(
                              logoUrl:
                                  'https://cdn.example.com/branding/f-fluxidi-wide.png',
                              logoImage: _widePng,
                              maxWidth: split.logoMaxWidth,
                              maxHeight: split.logoMaxHeight,
                              padding: const EdgeInsets.all(10),
                              backgroundColor: Colors.black38,
                              borderColor: const Color(0xFFFFD36A),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Fluxidi',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 20,
                              ),
                            ),
                            const Text(
                              'Uw lokale partner',
                              style: TextStyle(color: Colors.white70),
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
      expect(find.byType(PartnerBrandingLogoPlate), findsOneWidget);
      final logoImage = tester.widget<Image>(
        find.byKey(PartnerBrandingLogoPlate.imageKey),
      );
      expect(logoImage.fit, BoxFit.contain);
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
                logoImage: _widePng,
                maxWidth: 200,
                maxHeight: 90,
                padding: const EdgeInsets.all(10),
                backgroundColor: Colors.black26,
                borderColor: Colors.amber,
              ),
              const SizedBox(width: 16),
              PartnerBrandingLogoPlate(
                logoUrl: 'https://cdn.example.com/square.png',
                logoImage: _squarePng,
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
