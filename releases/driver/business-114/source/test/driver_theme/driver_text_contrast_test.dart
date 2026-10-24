import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/business_theme/brand_signature_palette.dart';
import 'package:fluxidi_tracking/driver_theme/driver_custom_huis_stijl.dart';
import 'package:fluxidi_tracking/driver_theme/driver_readable_pill.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';

void main() {
  tearDown(
    () => driverBrandSignaturePaletteNotifier.value =
        BrandSignaturePalette.defaults,
  );

  test(
    'labels remain readable across custom colours and translucent tints',
    () {
      // Include middle luminance colours where warm white/dark brown both fail.
      for (var r = 0; r <= 255; r += 51) {
        for (var g = 0; g <= 255; g += 51) {
          for (var b = 0; b <= 255; b += 51) {
            final surface = Color.fromARGB(255, r, g, b);
            for (final tint in [
              Colors.white,
              Colors.black,
              const Color(0xFFD4AF37),
              const Color(0x889DD8FF),
            ]) {
              final text = driverReadableTextOn(surface, tint);
              expect(
                brandSignatureContrastRatio(text, surface),
                greaterThanOrEqualTo(4.5),
              );
              expect(text.a, 1);
            }
          }
        }
      }
    },
  );

  test('selected gold keeps dark labels readable over the entire gradient', () {
    final colors = driverSelectedGoldGradient.colors;
    for (var i = 0; i < colors.length - 1; i++) {
      for (var step = 0; step <= 20; step++) {
        final surface = Color.lerp(colors[i], colors[i + 1], step / 20)!;
        expect(
          brandSignatureContrastRatio(const Color(0xFF2B2113), surface),
          greaterThanOrEqualTo(4.5),
        );
      }
    }
  });

  for (final variant in DriverThemeVariant.values) {
    testWidgets('actual ride badges use readable text and icons: $variant', (
      tester,
    ) async {
      final palette = paletteForDriverTheme(variant);
      final card = driverRideCardColors(variant);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Wrap(
              children: [
                for (final tint in [
                  palette.textPrimary,
                  palette.textMuted,
                  palette.accent,
                  const Color(0xFF9DD8FF),
                ])
                  DriverReadablePill(
                    text: '1 passagier',
                    icon: Icons.person_outline,
                    surface: card.surface,
                    foreground: tint,
                    border: palette.border,
                  ),
              ],
            ),
          ),
        ),
      );
      for (final text in tester.widgetList<Text>(find.text('1 passagier'))) {
        expect(
          brandSignatureContrastRatio(text.style!.color!, card.surface),
          greaterThanOrEqualTo(4.5),
        );
      }
      for (final icon in tester.widgetList<Icon>(find.byType(Icon))) {
        expect(
          brandSignatureContrastRatio(icon.color!, card.surface),
          greaterThanOrEqualTo(4.5),
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final base in [
    Colors.white,
    const Color(0xFF8A8A8A),
    const Color(0xFF8B00FF),
    const Color(0xFF00FF80),
    Colors.black,
  ]) {
    test('custom ride card text uses its real surface: $base', () {
      driverBrandSignaturePaletteNotifier.value =
          BrandSignaturePalette.fromColor(base);
      final palette = paletteForDriverTheme(DriverThemeVariant.customHuisstijl);
      final card = driverRideCardColors(DriverThemeVariant.customHuisstijl);
      expect(card.surface, palette.surface);
      for (final text in [card.foreground, card.muted]) {
        expect(
          brandSignatureContrastRatio(text, card.surface),
          greaterThanOrEqualTo(4.5),
        );
      }
      expect(
        brandSignatureContrastRatio(
          driverReadableTextOn(palette.accent, Colors.white),
          palette.accent,
        ),
        greaterThanOrEqualTo(4.5),
      );
    });
  }
}
