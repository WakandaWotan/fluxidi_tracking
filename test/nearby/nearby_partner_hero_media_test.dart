import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/nearby/nearby_partner_hero_media.dart';

/// Minimal valid 1×1 PNG (blue-ish).
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
      expect(h, inInclusiveRange(128, 176));
    });

    test('tablet uses wider area but stays capped', () {
      final phone = nearbyPartnerHeroMediaHeight(390);
      final tablet = nearbyPartnerHeroMediaHeight(834);
      expect(tablet, greaterThanOrEqualTo(phone));
      expect(tablet, lessThanOrEqualTo(kNearbyPartnerHeroMediaMaxHeight));
    });

    test('landscape phone width stays within compact bounds', () {
      final h = nearbyPartnerHeroMediaHeight(844);
      expect(h, inInclusiveRange(128, 176));
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
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.contain);
      final size = tester.getSize(find.byType(NearbyPartnerHeroMedia));
      expect(size.height, nearbyPartnerHeroMediaHeight(390));
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
