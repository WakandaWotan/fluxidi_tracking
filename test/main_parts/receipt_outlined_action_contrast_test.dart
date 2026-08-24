import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/business_theme/brand_signature_palette.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/driver_theme/driver_custom_huis_stijl.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';
import 'package:fluxidi_tracking/main_parts/receipt_action_style.dart';

/// Reproduces the production Fluxidi driver shell: dark Material theme with
/// white outlined-button foreground and a gold outline. That inherited white
/// is what made Ritbon outlined labels/icons vanish on a light "Bon" card.
ThemeData _hostileDriverShellTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFFFFD400),
      secondary: Color(0xFFFFD400),
      onPrimary: Colors.black,
      onSecondary: Colors.black,
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Color(0xFFFFD400), width: 1.2),
      ),
    ),
  );
}

const Map<String, String> _nlLabels = <String, String>{
  'sharePdf': 'Deel PDF',
  'whatsappPdf': 'Stuur PDF via WhatsApp',
  'emailPdf': 'Stuur PDF via e-mail',
  'printReceipt': 'Print bon',
};

Future<void> _pumpBonCard(
  WidgetTester tester, {
  required ReceiptOutlinedActionColors colors,
  required Size size,
  bool hasEmail = true,
  bool busy = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: _hostileDriverShellTheme(),
      home: Scaffold(
        backgroundColor: colors.surface,
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final spec in kReceiptOutlinedPdfActions) ...[
                    ReceiptOutlinedActionButton(
                      key: ValueKey<String>(
                        'receipt_outlined_action_${spec.id}',
                      ),
                      colors: colors,
                      icon: spec.icon,
                      label: _nlLabels[spec.labelKey]!,
                      onPressed: spec.id == 'emailPdf' && !hasEmail
                          ? null
                          : () {},
                      busy: busy && spec.id == 'sharePdf',
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
}

void _expectReadableAction({
  required WidgetTester tester,
  required ReceiptOutlinedActionSpec spec,
  required ReceiptOutlinedActionColors colors,
  required bool disabled,
  required bool busy,
}) {
  final label = _nlLabels[spec.labelKey]!;
  expect(label.trim(), isNotEmpty);

  final buttonFinder = find.byKey(
    ValueKey<String>('receipt_outlined_action_${spec.id}'),
  );
  expect(buttonFinder, findsOneWidget);

  final text = tester.widget<Text>(
    find.descendant(of: buttonFinder, matching: find.text(label)),
  );
  expect(text.data, label);
  final fg = text.style?.color;
  expect(fg, isNotNull);

  final surfaceIsLight =
      brandSignatureRelativeLuminance(colors.surface) >= 0.70;
  if (surfaceIsLight) {
    expect(fg, isNot(Colors.white));
    expect(fg, isNot(const Color(0xFFFFFFFF)));
    expect(brandSignatureRelativeLuminance(fg!), lessThan(0.85));
  }

  final expected = colors.resolveForeground(disabled: disabled, busy: busy);
  expect(fg, expected);

  final minContrast = disabled ? 3.0 : 4.5;
  expect(
    brandSignatureContrastRatio(fg!, colors.surface),
    greaterThanOrEqualTo(minContrast),
  );

  if (busy) {
    final spinner = tester.widget<CircularProgressIndicator>(
      find.descendant(
        of: buttonFinder,
        matching: find.byType(CircularProgressIndicator),
      ),
    );
    expect(spinner.color, expected);
    expect(
      brandSignatureContrastRatio(spinner.color!, colors.surface),
      greaterThanOrEqualTo(4.5),
    );
  } else {
    final icon = tester.widget<Icon>(
      find.descendant(of: buttonFinder, matching: find.byIcon(spec.icon)),
    );
    expect(icon.color, expected);
    expect(
      brandSignatureContrastRatio(icon.color!, colors.surface),
      greaterThanOrEqualTo(minContrast),
    );
  }

  final style = receiptOutlinedActionButtonStyle(colors);
  expect(style.foregroundColor?.resolve(const <WidgetState>{}), colors.foreground);
  expect(
    style.foregroundColor?.resolve(const <WidgetState>{WidgetState.pressed}),
    colors.foreground,
  );
  expect(
    style.foregroundColor?.resolve(const <WidgetState>{WidgetState.disabled}),
    colors.disabledForeground,
  );
  expect(
    style.iconColor?.resolve(const <WidgetState>{}),
    colors.foreground,
  );
  expect(
    style.iconColor?.resolve(const <WidgetState>{WidgetState.disabled}),
    colors.disabledForeground,
  );
  expect(
    style.overlayColor?.resolve(const <WidgetState>{WidgetState.pressed}),
    colors.pressedOverlay,
  );
  expect(style.side?.resolve(const <WidgetState>{})?.color, colors.outline);
  if (surfaceIsLight) {
    expect(colors.foreground, isNot(Colors.white));
  }
  expect(
    brandSignatureContrastRatio(colors.foreground, colors.surface),
    greaterThanOrEqualTo(4.5),
  );
  expect(
    brandSignatureContrastRatio(colors.disabledForeground, colors.surface),
    greaterThanOrEqualTo(3.0),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final previousDriverBrand = driverBrandSignaturePaletteNotifier.value;
  final previousBusinessBrand = brandSignaturePaletteNotifier.value;

  setUp(() {
    driverBrandSignaturePaletteNotifier.value =
        BrandSignaturePalette.fromColor(const Color(0xFFF6EFE4));
    brandSignaturePaletteNotifier.value = BrandSignaturePalette.fromColor(
      const Color(0xFFF6EFE4),
    );
  });

  tearDown(() {
    driverBrandSignaturePaletteNotifier.value = previousDriverBrand;
    brandSignaturePaletteNotifier.value = previousBusinessBrand;
  });

  test('outlined receipt actions stay share / WhatsApp / email / print', () {
    expect(
      kReceiptOutlinedPdfActions.map((spec) => spec.id).toList(),
      <String>['sharePdf', 'whatsappPdf', 'emailPdf', 'printReceipt'],
    );
    expect(
      kReceiptOutlinedPdfActions.map((spec) => spec.labelKey).toList(),
      <String>['sharePdf', 'whatsappPdf', 'emailPdf', 'printReceipt'],
    );
    expect(kReceiptOutlinedPdfActions[0].icon, Icons.share_outlined);
    expect(kReceiptOutlinedPdfActions[1].icon, Icons.chat_outlined);
    expect(kReceiptOutlinedPdfActions[2].icon, Icons.email_outlined);
    expect(kReceiptOutlinedPdfActions[3].icon, Icons.print_outlined);
  });

  test('Ritbon Bon card wires shared outlined actions without renaming them', () {
    final source = File(
      'lib/main_parts/ride_receipt_body_state.dart',
    ).readAsStringSync();
    final start = source.indexOf('Widget _receiptActionsSection(');
    expect(start, greaterThanOrEqualTo(0));
    final end = source.indexOf('Widget build(BuildContext context)', start);
    expect(end, greaterThan(start));
    final section = source.substring(start, end);

    expect(section.contains('ReceiptOutlinedActionButton'), isTrue);
    expect(section.contains('kReceiptOutlinedPdfActions'), isTrue);
    expect(section.contains("_receiptText('viewPdf')"), isTrue);
    expect(section.contains("_shareReceiptPdf(context)"), isTrue);
    expect(section.contains("_shareReceiptPdfViaWhatsApp(context)"), isTrue);
    expect(section.contains("_shareReceiptPdfViaEmail(context)"), isTrue);
    expect(section.contains("_printReceiptPdf(context)"), isTrue);
    expect(section.contains('hasEmail'), isTrue);
    expect(section.contains('FilledButton.icon'), isTrue);

    final shareAt = section.indexOf("_shareReceiptPdf(context)");
    final whatsappAt = section.indexOf("_shareReceiptPdfViaWhatsApp(context)");
    final emailAt = section.indexOf("_shareReceiptPdfViaEmail(context)");
    final printAt = section.indexOf("_printReceiptPdf(context)");
    expect(shareAt, greaterThan(0));
    expect(whatsappAt, greaterThan(shareAt));
    expect(emailAt, greaterThan(whatsappAt));
    expect(printAt, greaterThan(emailAt));
  });

  test('light surfaces reject inherited white / gold-as-ink', () {
    const ivory = Color(0xFFFFFFFF);
    const inheritedWhite = Color(0xFFFFFFFF);
    const gold = Color(0xFFD4AF37);
    const darkInk = Color(0xFF143028);

    final fromWhite = receiptOutlinedActionForeground(
      surface: ivory,
      preferred: inheritedWhite,
    );
    expect(fromWhite, isNot(inheritedWhite));
    expect(brandSignatureContrastRatio(fromWhite, ivory), greaterThanOrEqualTo(4.5));

    expect(brandSignatureContrastRatio(gold, ivory), lessThan(3.0));
    final fromGold = receiptOutlinedActionForeground(
      surface: ivory,
      preferred: gold,
    );
    expect(fromGold, isNot(gold));
    expect(brandSignatureContrastRatio(fromGold, ivory), greaterThanOrEqualTo(4.5));

    expect(
      receiptOutlinedActionForeground(surface: ivory, preferred: darkInk),
      darkInk,
    );
  });

  for (final variant in DriverThemeVariant.values) {
    testWidgets(
      'driver theme ${variant.name} outlined receipt actions stay readable',
      (tester) async {
        if (variant == DriverThemeVariant.customHuisstijl) {
          driverBrandSignaturePaletteNotifier.value =
              BrandSignaturePalette.fromColor(const Color(0xFFF6EFE4));
        }
        final palette = paletteForDriverTheme(variant);
        final colors = ReceiptOutlinedActionColors.fromDriverTheme(palette);
        await _pumpBonCard(
          tester,
          colors: colors,
          size: const Size(390, 844),
          hasEmail: false,
        );
        for (final spec in kReceiptOutlinedPdfActions) {
          _expectReadableAction(
            tester: tester,
            spec: spec,
            colors: colors,
            disabled: spec.id == 'emailPdf',
            busy: false,
          );
        }
      },
    );
  }

  for (final variant in BusinessThemeVariant.values) {
    testWidgets(
      'business theme ${variant.name} outlined receipt actions stay readable',
      (tester) async {
        if (variant == BusinessThemeVariant.brandSignatureGold) {
          brandSignaturePaletteNotifier.value =
              BrandSignaturePalette.fromColor(const Color(0xFFF6EFE4));
        }
        final palette = paletteForBusinessTheme(variant);
        final colors = ReceiptOutlinedActionColors.fromBusinessTheme(palette);
        await _pumpBonCard(
          tester,
          colors: colors,
          size: const Size(800, 1280),
          hasEmail: false,
        );
        for (final spec in kReceiptOutlinedPdfActions) {
          _expectReadableAction(
            tester: tester,
            spec: spec,
            colors: colors,
            disabled: spec.id == 'emailPdf',
            busy: false,
          );
        }
      },
    );
  }

  testWidgets('phone and tablet light-emerald cards keep the same four labels', (
    tester,
  ) async {
    final colors = ReceiptOutlinedActionColors.fromDriverTheme(
      paletteForDriverTheme(DriverThemeVariant.lightEmerald),
    );
    expect(colors.surface, const Color(0xFFFFFFFF));

    for (final size in const <Size>[Size(390, 844), Size(800, 1280)]) {
      await _pumpBonCard(tester, colors: colors, size: size);
      for (final spec in kReceiptOutlinedPdfActions) {
        _expectReadableAction(
          tester: tester,
          spec: spec,
          colors: colors,
          disabled: false,
          busy: false,
        );
      }
    }
  });

  testWidgets('pressed / disabled / loading keep readable explicit ink', (
    tester,
  ) async {
    final colors = ReceiptOutlinedActionColors.fromDriverTheme(
      paletteForDriverTheme(DriverThemeVariant.lightEmerald),
    );
    await _pumpBonCard(
      tester,
      colors: colors,
      size: const Size(390, 844),
      hasEmail: false,
      busy: true,
    );

    _expectReadableAction(
      tester: tester,
      spec: kReceiptOutlinedPdfActions[0],
      colors: colors,
      disabled: false,
      busy: true,
    );
    _expectReadableAction(
      tester: tester,
      spec: kReceiptOutlinedPdfActions[2],
      colors: colors,
      disabled: true,
      busy: false,
    );

    expect(
      receiptOutlinedActionButtonStyle(colors).foregroundColor?.resolve(
        const <WidgetState>{WidgetState.pressed},
      ),
      colors.foreground,
    );
    expect(
      brandSignatureContrastRatio(colors.foreground, colors.surface),
      greaterThanOrEqualTo(4.5),
    );
  });
}
