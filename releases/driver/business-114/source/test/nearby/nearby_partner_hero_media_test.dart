import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/nearby/nearby_partner_hero_media.dart';
import 'package:fluxidi_tracking/nearby/tablet_partner_branding_layout.dart';

/// Minimal valid 1Ã—1 PNG (blue-ish).
final MemoryImage _tinyPng = MemoryImage(
  Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    ),
  ),
);

void main() {
  group('nearbyPartnerHeroMediaHeight', () {
    test('phone portrait is taller than legacy 90px crop strip', () {
      final h = nearbyPartnerHeroMediaHeight(390);
      expect(h, greaterThan(kNearbyPartnerHeroMediaLegacyHeight));
      expect(h, inInclusiveRange(220, 320));
    });

    test('tablet uses a taller cap but stays bounded', () {
      final phone = nearbyPartnerHeroMediaHeight(390);
      final tablet = nearbyPartnerHeroMediaHeight(834);
      expect(tablet, greaterThan(phone));
      expect(tablet, lessThanOrEqualTo(kNearbyPartnerHeroMediaMaxHeight));
    });

    test('landscape phone width stays within the shared cap', () {
      final h = nearbyPartnerHeroMediaHeight(844);
      expect(h, lessThanOrEqualTo(kNearbyPartnerHeroMediaMaxHeight));
      expect(h, greaterThan(kNearbyPartnerHeroMediaLegacyHeight));
    });
  });

  group('NearbyPartnerHeroMedia', () {
    testWidgets('vehicle image uses BoxFit.contain and theme background', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: NearbyPartnerHeroMedia(
                  height: nearbyPartnerHeroMediaHeight(390),
                  backgroundColor: const Color(0xFFEDEDED),
                  heroUrl: 'https://tenant-a.example/vehicles/prometheus.jpg',
                  heroImage: _tinyPng,
                  aspectRatio: 1,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final image = tester.widget<Image>(find.byType(Image));
      expect(image.fit, BoxFit.contain);
      expect(image.alignment, Alignment.center);

      final media = tester.widget<NearbyPartnerHeroMedia>(
        find.byType(NearbyPartnerHeroMedia),
      );
      expect(media.backgroundColor, const Color(0xFFEDEDED));
      expect(media.height, nearbyPartnerHeroMediaHeight(390));
      expect(media.height, isNot(kNearbyPartnerHeroMediaLegacyHeight));
    });

    testWidgets('16:9-style phone constraints keep contain fit', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(390, 844)),
            child: Scaffold(
              body: NearbyPartnerHeroMedia(
                height: nearbyPartnerHeroMediaHeight(390),
                backgroundColor: Colors.white,
                heroImage: _tinyPng,
                heroUrl: 'https://tenant-a.example/v/16x9.jpg',
                aspectRatio: 16 / 9,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.contain);
      final size = tester.getSize(find.byType(NearbyPartnerHeroMedia));
      final width = size.width;
      final natural = width / (16 / 9);
      final maxHeight = nearbyPartnerHeroMediaHeight(390);
      expect(size.height, natural > maxHeight ? maxHeight : natural);
      expect(size.height, lessThan(width));
    });

    testWidgets('tablet constraints keep compact contained frame', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(834, 1194)),
            child: Scaffold(
              body: SizedBox(
                width: 700,
                child: NearbyPartnerHeroMedia(
                  height: nearbyPartnerHeroMediaHeight(834),
                  backgroundColor: const Color(0xFFF5F5F5),
                  heroImage: _tinyPng,
                  heroUrl: 'https://tenant-b.example/v/portrait.jpg',
                  aspectRatio: 1,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final size = tester.getSize(find.byType(NearbyPartnerHeroMedia));
      expect(size.height, lessThanOrEqualTo(kNearbyPartnerHeroMediaMaxHeight));
      expect(tester.takeException(), isNull);
      expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.contain);
    });

    testWidgets('missing image shows safe fallback', (tester) async {
      const fallbackKey = Key('fallback-strip');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NearbyPartnerHeroMedia(
              height: 140,
              backgroundColor: Colors.white,
              fallback: Container(
                key: fallbackKey,
                height: 140,
                color: Colors.amber,
                child: const Text('Fluxidi partner'),
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(fallbackKey), findsOneWidget);
      expect(find.text('Fluxidi partner'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('tenant-scoped hero URL is preserved on the widget', (
      tester,
    ) async {
      const scopedUrl = 'https://cdn.example/tenant/prometheus/vehicle.jpg';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NearbyPartnerHeroMedia(
              height: 140,
              backgroundColor: Colors.white,
              heroUrl: scopedUrl,
              heroImage: _tinyPng,
            ),
          ),
        ),
      );
      final widget = tester.widget<NearbyPartnerHeroMedia>(
        find.byType(NearbyPartnerHeroMedia),
      );
      expect(widget.heroUrl, scopedUrl);
      expect(widget.heroUrl.contains('prometheus'), isTrue);
      expect(widget.heroUrl.contains('fluxidi'), isFalse);
    });

    testWidgets('wide cover uses the source ratio across the full width', (
      tester,
    ) async {
      const width = 360.0;
      const ratio = 2.6;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: width,
              child: NearbyPartnerHeroMedia(
                height: 400,
                backgroundColor: const Color(0xFFF4F4F4),
                heroImage: _tinyPng,
                heroUrl: 'https://example.com/wide-cover.jpg',
                aspectRatio: ratio,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final box = tester.getSize(
        find.byKey(const ValueKey<String>('nearby_partner_cover_box')),
      );
      expect(box.width, width);
      expect(box.height, closeTo(width / ratio, 0.5));
      expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.contain);
    });

    testWidgets('square cover stops at the max height without cover crop', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: NearbyPartnerHeroMedia(
                height: 140,
                backgroundColor: Colors.white,
                heroImage: _tinyPng,
                heroUrl: 'https://example.com/square.jpg',
                aspectRatio: 1,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final box = tester.getSize(
        find.byKey(const ValueKey<String>('nearby_partner_cover_box')),
      );
      expect(box.height, 140);
      expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.contain);
    });

    testWidgets('light theme logo mark uses a dark plate', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NearbyPartnerLogoMark(
              logoUrl: '',
              maxWidth: 136,
              maxHeight: 54,
              lightTheme: true,
            ),
          ),
        ),
      );
      final plate = tester.widget<PartnerBrandingLogoPlate>(
        find.byType(PartnerBrandingLogoPlate),
      );
      expect(plate.backgroundColor, const Color(0xFF161616));
    });

    testWidgets('ClipRRect keeps rounded corners on media frame', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NearbyPartnerHeroMedia(
              height: 140,
              backgroundColor: Colors.white,
              heroImage: _tinyPng,
              heroUrl: 'https://tenant-a.example/v.jpg',
              borderRadius: 11,
            ),
          ),
        ),
      );
      await tester.pump();
      final clip = tester.widget<ClipRRect>(find.byType(ClipRRect));
      expect(clip.borderRadius, BorderRadius.circular(11));
    });
  });
}
