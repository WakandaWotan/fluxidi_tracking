import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/widgets/business_theme_cycle_button.dart';
import 'package:fluxidi_tracking/widgets/fluxidi_cover_photo_header.dart';

const Size kWindowsWide = Size(1524, 900);
const Size kWindowsCompact = Size(1100, 720);
const Size kTabletLandscape = Size(1180, 820);
const Size kTabletPortrait = Size(800, 1280);
const Size kPhonePortrait = Size(390, 844);

const List<Size> kRequiredSurfaces = <Size>[
  kWindowsWide,
  kWindowsCompact,
  kTabletLandscape,
  kTabletPortrait,
  kPhonePortrait,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cover fit is never fill', () {
    expect(kFluxidiCoverPhotoFit, BoxFit.cover);
    expect(kFluxidiCoverPhotoFit, isNot(BoxFit.fill));
  });

  test('measured source sizes keep their original aspect', () {
    kBusinessHomeHeaderSourceSizes.forEach((asset, size) {
      expect(size.width, greaterThan(0), reason: asset);
      expect(size.height, greaterThan(0), reason: asset);
    });
    expect(
      kBusinessHomeHeaderSourceSizes[kBusinessHomeHeaderExecutiveGoldPortrait],
      const Size(1086, 1448),
    );
    expect(
      kBusinessHomeHeaderSourceSizes[kBusinessHomeHeaderExecutiveGoldLandscape],
      const Size(1536, 1024),
    );
    expect(
      kBusinessHomeHeaderSourceSizes[kBusinessHomeHeaderCorporateBlue],
      const Size(1672, 941),
    );
  });

  test('Windows landscape gold uses the landscape source, not the portrait', () {
    expect(
      businessHomeHeaderPhotoAsset(
        variant: BusinessThemeVariant.executiveGold,
        landscape: true,
      ),
      kBusinessHomeHeaderExecutiveGoldLandscape,
    );
    expect(
      businessHomeHeaderPhotoAsset(
        variant: BusinessThemeVariant.executiveGold,
        landscape: false,
      ),
      kBusinessHomeHeaderExecutiveGoldPortrait,
    );
  });

  test('every photo theme resolves a catalogued header asset', () {
    for (final variant in <BusinessThemeVariant>[
      BusinessThemeVariant.executiveGold,
      BusinessThemeVariant.corporateBlue,
      BusinessThemeVariant.cleanProfessional,
      BusinessThemeVariant.emeraldIvory,
      BusinessThemeVariant.fluxidiNeonRush,
    ]) {
      for (final landscape in const [true, false]) {
        final asset = businessHomeHeaderPhotoAsset(
          variant: variant,
          landscape: landscape,
        );
        expect(
          kBusinessHomeHeaderSourceSizes.containsKey(asset),
          isTrue,
          reason: '$variant landscape=$landscape',
        );
      }
    }
  });

  test('horizontal and vertical cover scale stay identical on required surfaces', () {
    const horizontalPadding = kBusinessHomeHeaderContentInset * 2;
    for (final surface in kRequiredSurfaces) {
      final landscape = surface.width > surface.height;
      for (final variant in <BusinessThemeVariant>[
        BusinessThemeVariant.executiveGold,
        BusinessThemeVariant.corporateBlue,
        BusinessThemeVariant.cleanProfessional,
        BusinessThemeVariant.emeraldIvory,
        BusinessThemeVariant.fluxidiNeonRush,
      ]) {
        final asset = businessHomeHeaderPhotoAsset(
          variant: variant,
          landscape: landscape,
        );
        final source = businessHomeHeaderSourceSize(asset);
        final overlayPadding = landscape
            ? const EdgeInsets.fromLTRB(10, 8, 10, 10)
            : const EdgeInsets.fromLTRB(12, 12, 12, 14);
        final actionColumns = landscape ? 5 : 2;
        final actionRows = (10 / actionColumns).ceil();
        final cardHeight = landscape
            ? (surface.height * 0.27).clamp(175.0, 230.0)
            : (surface.height * 0.105).clamp(132.0, 148.0);
        final spacing = landscape ? 8.0 : 14.0;
        final actionsHeight =
            actionRows * cardHeight +
            (actionRows > 1 ? (actionRows - 1) * spacing : 0.0);
        final maxHeight = businessHomePhotoHeaderAvailableHeight(
          bodyHeight: surface.height,
          listTop: 12,
          sectionGap: landscape
              ? (surface.height * 0.018).clamp(8.0, 16.0)
              : 10,
          kpiHeight: businessHomeKpiBlockHeight(
            stacked: !landscape && surface.width < 430,
            compact: landscape,
          ),
          titleGap: landscape
              ? (surface.height * 0.022).clamp(10.0, 20.0)
              : 14,
          gridTopGap: landscape
              ? (surface.height * 0.018).clamp(8.0, 16.0)
              : 10,
          actionsHeight: actionsHeight,
          backGap: landscape
              ? (surface.height * 0.04).clamp(14.0, 36.0)
              : 10,
          listBottom: landscape ? 22 : 12,
        );
        final layout = layoutFluxidiCoverPhotoHeader(
          sourceSize: source,
          availableWidth: surface.width - horizontalPadding,
          maxHeight: maxHeight,
          minHeight: businessHomeHeaderOverlayMinHeight(overlayPadding),
        );
        expect(
          layout.scaleX,
          closeTo(layout.scaleY, 1e-9),
          reason: '$variant ${surface.width}x${surface.height}',
        );
        expect(layout.fit, BoxFit.cover);
        expect(layout.fit, isNot(BoxFit.fill));
        expect(layout.zone.width / source.width, closeTo(layout.uniformScale, 1e-9));
        expect(
          layout.paintedSize.width / source.width,
          closeTo(layout.paintedSize.height / source.height, 1e-9),
        );
        expect(layout.zone.height, greaterThan(0));
      }
    }
  });

  testWidgets('decode uses only cacheWidth so the bitmap is not stretched', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1524, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const source = Size(1536, 1024);
    const zone = Size(1492, 220);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1492,
            child: FluxidiCoverPhotoHeader(
              assetName: kBusinessHomeHeaderExecutiveGoldLandscape,
              sourceSize: source,
              maxHeight: 220,
              minHeight: 112,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final image = tester.widget<Image>(
      find.byKey(kFluxidiCoverPhotoHeaderImageKey),
    );
    expect(image.fit, BoxFit.cover);
    expect(image.fit, isNot(BoxFit.fill));
    expect(image.image, isA<ResizeImage>());
    final resized = image.image as ResizeImage;
    expect(resized.width, isNotNull);
    expect(resized.height, isNull);
    expect(
      resized.width,
      fluxidiCoverDecodeCacheWidth(
        sourceSize: source,
        zone: zone,
        devicePixelRatio: 1.0,
      ),
    );
  });

  testWidgets('greeting and theme button stay inside the header overlay', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1524, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FluxidiCoverPhotoHeader(
              assetName: kBusinessHomeHeaderCorporateBlue,
              sourceSize: businessHomeHeaderSourceSize(
                kBusinessHomeHeaderCorporateBlue,
              ),
              maxHeight: 240,
              minHeight: businessHomeHeaderOverlayMinHeight(
                const EdgeInsets.fromLTRB(10, 8, 10, 10),
              ),
              overlay: Stack(
                children: [
                  const Positioned(
                    left: 10,
                    top: 8,
                    child: Text(
                      'Goedenavond!',
                      key: BusinessHomeHeaderThemeRegion.greetingKey,
                      style: TextStyle(color: Colors.white, fontSize: 15),
                    ),
                  ),
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: BusinessThemeCycleButton(
                      heroOverlay: true,
                      onPressed: () {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final header = tester.getRect(find.byKey(kFluxidiCoverPhotoHeaderKey));
    final greeting = tester.getRect(
      find.byKey(BusinessHomeHeaderThemeRegion.greetingKey),
    );
    final button = tester.getRect(find.byKey(BusinessThemeCycleButton.buttonKey));
    expect(header.contains(greeting.topLeft), isTrue);
    expect(header.contains(greeting.bottomRight), isTrue);
    expect(header.contains(button.topLeft), isTrue);
    expect(header.contains(button.bottomRight), isTrue);
    expect(button.overlaps(greeting), isFalse);
  });

}
