import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/business_settings_page.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';

double _luminanceContrast(Color a, Color b) {
  final lighter = a.computeLuminance() > b.computeLuminance() ? a : b;
  final darker = identical(lighter, a) ? b : a;
  return (lighter.computeLuminance() + 0.05) /
      (darker.computeLuminance() + 0.05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    appLanguageNotifier.value = AppLanguage.en;
    businessThemeNotifier.value = BusinessThemeVariant.executiveGold;
  });

  testWidgets('selected public service is readable in the light theme', (
    tester,
  ) async {
    appLanguageNotifier.value = AppLanguage.nl;
    businessThemeNotifier.value = BusinessThemeVariant.cleanProfessional;
    await tester.binding.setSurfaceSize(const Size(800, 1280));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: BusinessSettingsPage()),
      ),
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Publiek partnerprofiel'),
      360,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Publiek partnerprofiel'));
    await tester.pump(const Duration(milliseconds: 200));

    final service = find.widgetWithText(FilterChip, 'Taxi & VVB');
    expect(service, findsOneWidget);
    final chip = tester.widget<FilterChip>(service);
    final palette = paletteForBusinessTheme(
      BusinessThemeVariant.cleanProfessional,
    );
    if (chip.selected) {
      expect(chip.selectedColor, palette.accent);
      expect(chip.labelStyle?.color, palette.textOnAccent);
      expect(
        _luminanceContrast(chip.labelStyle!.color!, chip.selectedColor!),
        greaterThanOrEqualTo(4.5),
      );
    } else {
      await tester.ensureVisible(service);
      await tester.tap(service);
      await tester.pump();
      final selected = tester.widget<FilterChip>(service);
      expect(selected.selected, isTrue);
      expect(selected.selectedColor, palette.accent);
      expect(selected.labelStyle?.color, palette.textOnAccent);
      expect(
        _luminanceContrast(
          selected.labelStyle!.color!,
          selected.selectedColor!,
        ),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

  testWidgets('light-theme pending badge is readable on the settings card', (
    tester,
  ) async {
    appLanguageNotifier.value = AppLanguage.nl;
    businessThemeNotifier.value = BusinessThemeVariant.cleanProfessional;
    await tester.binding.setSurfaceSize(const Size(800, 1280));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: BusinessSettingsPage())),
    );
    await tester.pump();

    await tester.scrollUntilVisible(
      find.text('Mollie terminals'),
      360,
      scrollable: find.byType(Scrollable).first,
    );
    final pending = find.text('Activering volgt').first;
    final label = tester.widget<Text>(pending);
    final ink = label.style?.color;
    expect(ink, isNotNull);
    final palette = paletteForBusinessTheme(
      BusinessThemeVariant.cleanProfessional,
    );
    expect(_luminanceContrast(ink!, palette.surface), greaterThanOrEqualTo(4.5));
    expect(
      _luminanceContrast(ink, palette.surfaceAlt),
      greaterThanOrEqualTo(4.5),
    );
  });
}
