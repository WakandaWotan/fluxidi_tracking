import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/business_theme/brand_signature_palette.dart';
import 'package:fluxidi_tracking/driver_theme/driver_custom_huis_stijl.dart';
import 'package:fluxidi_tracking/driver_theme/chauffeur_gold_icons.dart';
import 'package:fluxidi_tracking/driver_theme/driver_gold_bottom_nav.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';

void main() {
  tearDown(() {
    driverBrandSignaturePaletteNotifier.value = BrandSignaturePalette.defaults;
  });
  const labels = ['Home', 'Ritten', 'Straatrit', 'Meer'];
  const assets = ['home', 'rides', 'street_ride', 'more'];

  for (final base in [
    Colors.white,
    const Color(0xFFF7F2E7),
    const Color(0xFF8A8A8A),
    Colors.black,
    const Color(0xFF153759),
    const Color(0xFF8B00FF),
    const Color(0xFF00FF80),
  ]) {
    for (final width in [320.0, 600.0]) {
      for (final scale in [1.0, 1.5]) {
        testWidgets('custom footer $base / $width / $scale', (tester) async {
          tester.view.physicalSize = Size(width, 400);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          driverBrandSignaturePaletteNotifier.value =
              BrandSignaturePalette.fromColor(base);
          final palette = paletteForDriverTheme(
            DriverThemeVariant.customHuisstijl,
          );
          final tapped = <String>[];
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  backgroundColor: palette.background,
                  body: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: DriverGoldBottomNavBar(
                        palette: palette,
                        child: Row(
                          children: [
                            for (var i = 0; i < labels.length; i++)
                              Expanded(
                                child: DriverGoldBottomNavItem(
                                  palette: palette,
                                  label: labels[i],
                                  icon: ChauffeurGoldIcon(
                                    assetKey: assets[i],
                                    size: 25,
                                  ),
                                  active: i == 0,
                                  onTap: () => tapped.add(labels[i]),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final bar = tester.widget<Container>(
            find
                .descendant(
                  of: find.byType(DriverGoldBottomNavBar),
                  matching: find.byType(Container),
                )
                .first,
          );
          expect((bar.decoration! as BoxDecoration).color, palette.surface);
          final iconRects = <Rect>[];
          final labelRects = <Rect>[];
          for (var i = 0; i < labels.length; i++) {
            final text = tester.widget<Text>(find.text(labels[i]));
            final item = find.ancestor(
              of: find.text(labels[i]),
              matching: find.byType(DriverGoldBottomNavItem),
            );
            final material = tester.widget<Material>(
              find.descendant(of: item, matching: find.byType(Material)),
            );
            final surfaces = i == 0
                ? driverSelectedGoldGradient.colors
                : [material.color!];
            for (final surface in surfaces) {
              expect(
                brandSignatureContrastRatio(text.style!.color!, surface),
                greaterThanOrEqualTo(4.5),
                reason: '${labels[i]} must use its actual footer surface',
              );
            }
            expect(text.maxLines, 2);
            iconRects.add(
              tester.getRect(find.byKey(chauffeurGoldIconKey(assets[i]))),
            );
            labelRects.add(tester.getRect(find.text(labels[i])));
            await tester.tap(find.text(labels[i]));
          }
          expect(tapped, labels);
          // All four icons and labels align, including inactive entries.
          for (var i = 1; i < labels.length; i++) {
            expect(iconRects[i].top, closeTo(iconRects[0].top, 0.1));
            expect(iconRects[i].size, iconRects[0].size);
            expect(
              labelRects[i].center.dy,
              closeTo(labelRects[0].center.dy, 0.1),
            );
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  test('custom dashboard selects the custom bar before the black fallback', () {
    final source = File(
      'lib/main_parts/driver_home_page_state.dart',
    ).readAsStringSync();
    final footer = source.substring(
      source.indexOf('margin: const EdgeInsets.fromLTRB(10, 0, 10, 8)'),
    );
    expect(
      footer.indexOf('DriverGoldBottomNavBar('),
      lessThan(footer.indexOf('color: const Color(0xFF101113)')),
    );
    expect(source, contains('child: DriverGoldBottomNavItem('));
  });
}
