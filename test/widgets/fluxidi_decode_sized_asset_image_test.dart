import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/widgets/fluxidi_decode_sized_asset_image.dart';

ResizeImage _expectResizeImage(Image image) {
  expect(image.image, isA<ResizeImage>());
  return image.image as ResizeImage;
}

void main() {
  group('fluxidiDecodePixelSize', () {
    test('scales logical size by devicePixelRatio', () {
      final decode = fluxidiDecodePixelSize(
        logicalWidth: 400,
        logicalHeight: 800,
        devicePixelRatio: 2.5,
      );
      expect(decode.width, 1000);
      expect(decode.height, 2000);
    });

    test('ceils fractional physical edges', () {
      final decode = fluxidiDecodePixelSize(
        logicalWidth: 100.2,
        logicalHeight: 50.1,
        devicePixelRatio: 3.0,
      );
      expect(decode.width, 301);
      expect(decode.height, 151);
    });

    test('clamps to max edge and floors invalid ratio', () {
      final decode = fluxidiDecodePixelSize(
        logicalWidth: 5000,
        logicalHeight: 10,
        devicePixelRatio: 0,
        maxEdgePixels: 2048,
      );
      expect(decode.width, 2048);
      expect(decode.height, 10);
    });

    test('returns null for non-finite logical edges', () {
      final decode = fluxidiDecodePixelSize(
        logicalWidth: double.infinity,
        logicalHeight: double.nan,
        devicePixelRatio: 2,
      );
      expect(decode.width, isNull);
      expect(decode.height, isNull);
    });
  });

  group('fluxidiResolvePaintSize', () {
    test('prefers finite constraints over fallback', () {
      final size = fluxidiResolvePaintSize(
        constraints: const BoxConstraints.tightFor(width: 320, height: 640),
        fallback: const Size(1080, 1920),
      );
      expect(size, const Size(320, 640));
    });

    test('falls back when an axis is unbounded', () {
      final size = fluxidiResolvePaintSize(
        constraints: const BoxConstraints(maxWidth: 400),
        fallback: const Size(1080, 1920),
      );
      expect(size.width, 400);
      expect(size.height, 1920);
    });
  });

  group('FluxidiDecodeSizedAssetImage', () {
    testWidgets('applies ResizeImage decode bounds from layout × dpr', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 180,
              height: 120,
              child: FluxidiDecodeSizedAssetImage(
                'assets/fluxidi/fluxidi_logo_horizontal_dark.png',
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final image = tester.widget<Image>(find.byType(Image));
      expect(image.fit, BoxFit.cover);
      final resized = _expectResizeImage(image);
      expect(resized.width, 360);
      expect(resized.height, 240);
    });

    testWidgets('PIN-sized phone surface stays at layout×dpr decode', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(
              child: FluxidiDecodeSizedAssetImage(
                'assets/fluxidi/background_sign_in_page_phone.webp',
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final resized = _expectResizeImage(tester.widget<Image>(find.byType(Image)));
      // 390×844 @ 3.0 dpr — far below decoding a multi‑MB full source raster
      // into an unbounded ImageCache entry.
      expect(resized.width, 1170);
      expect(resized.height, 2532);
    });

    testWidgets('quick-action card decode is far below theme source pixels', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 170,
                height: 118,
                child: FluxidiDecodeSizedAssetImage(
                  'assets/Midday Gold Chauffeur/driver_receipts_midday_gold.webp',
                  fit: BoxFit.cover,
                  alignment: Alignment.centerRight,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final resized = _expectResizeImage(tester.widget<Image>(find.byType(Image)));
      expect(resized.width, 340);
      expect(resized.height, 236);
      // Source theme art is ~1448×1086. Bounded decode must be smaller.
      expect(resized.width! * resized.height!, lessThan(1448 * 1086));
    });
  });
}
