import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/business_theme/brand_signature_palette.dart';
import 'package:fluxidi_tracking/driver_theme/driver_dashboard_notice.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';

void main() {
  for (final variant in DriverThemeVariant.values) {
    for (final paired in [false, true]) {
      for (final scale in [1.0, 1.5]) {
        testWidgets('dashboard identity and pairing $variant/$paired/$scale', (
          tester,
        ) async {
          tester.view.physicalSize = const Size(320, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final palette = paletteForDriverTheme(variant);
          final surface = palette.background;
          var taps = 0;
          final action = paired
              ? 'Open gekoppelde chauffeursmodus'
              : 'Dit toestel koppelen als chauffeur';
          await tester.pumpWidget(
            MaterialApp(
              // Reproduce the conflicting company theme in the screenshots.
              theme: ThemeData(
                textTheme: const TextTheme(
                  bodyMedium: TextStyle(color: Colors.white),
                ),
                outlinedButtonTheme: OutlinedButtonThemeData(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.black,
                    backgroundColor: Colors.transparent,
                  ),
                ),
              ),
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  backgroundColor: surface,
                  body: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DriverDashboardText(
                          text: 'Chauffeur',
                          surface: surface,
                          foreground: palette.textMuted,
                          style: const TextStyle(fontSize: 13.2),
                        ),
                        DriverDashboardText(
                          text: 'Christophe Vanrokeghem — TestDriver',
                          surface: surface,
                          foreground: palette.textPrimary,
                          style: const TextStyle(
                            fontSize: 16.2,
                            fontWeight: FontWeight.w800,
                          ),
                          maxLines: 1,
                        ),
                        DriverDevicePairingNotice(
                          palette: palette,
                          surface: surface,
                          paired: paired,
                          message: paired
                              ? 'Dit toestel is gekoppeld aan deze chauffeur.'
                              : 'Bedrijfsweergave: dit toestel deelt geen locatie voor deze chauffeur.',
                          errorMessage: paired
                              ? 'Achtergrondlocatie is niet gestart.'
                              : null,
                          actionLabel: action,
                          onPressed: () => taps++,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          // Check resolved render colours, including the inherited button label.
          for (final element in find.byType(Text).evaluate()) {
            final text = element.widget as Text;
            final style = DefaultTextStyle.of(element).style.merge(text.style);
            expect(
              brandSignatureContrastRatio(style.color!, surface),
              greaterThanOrEqualTo(4.5),
              reason: '${text.data} on $variant',
            );
          }
          final iconElement = find.byType(Icon).evaluate().single;
          final icon = iconElement.widget as Icon;
          expect(
            brandSignatureContrastRatio(
              icon.color ?? IconTheme.of(iconElement).color!,
              surface,
            ),
            greaterThanOrEqualTo(4.5),
          );
          await tester.tap(find.text(action));
          expect(taps, 1);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets('tablet identity stays light over the dark photo scrim', (
    tester,
  ) async {
    const scrim = Color(0xFF0F3D2E);
    await tester.pumpWidget(
      const MaterialApp(
        home: ColoredBox(
          color: scrim,
          child: DriverDashboardText(
            text: 'TestDriver',
            surface: scrim,
            foreground: Colors.white,
            style: TextStyle(fontSize: 16.2),
          ),
        ),
      ),
    );
    expect(
      tester.widget<Text>(find.text('TestDriver')).style!.color,
      Colors.white,
    );
    expect(tester.takeException(), isNull);
  });
}
