import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/main_parts/street_business_invoice_support.dart';
import 'package:fluxidi_tracking/main_parts/street_business_invoice_widgets.dart';

/// Widget tests for the SHARED request form (used by both the company card and
/// the driver receipt). Focus: SafeArea/keyboard-aware layout, bounded height,
/// scrollable body, and an always-reachable bottom action bar on phone + tablet
/// (portrait & landscape) with the keyboard open — no RenderFlex overflow.

const _theme = StreetInvoiceActionTheme(
  accent: Color(0xFF1E88E5),
  textPrimary: Color(0xFF101418),
  textSecondary: Color(0xFF5B6570),
  textTertiary: Color(0xFF8A929B),
  danger: Color(0xFFD32F2F),
  paidText: Color(0xFF2E7D32),
  unpaidText: Color(0xFFEF6C00),
  surface: Color(0xFFFFFFFF),
  surfaceAlt: Color(0xFFF2F4F7),
  border: Color(0xFFCBD2D9),
);

Future<void> _pumpForm(
  WidgetTester tester, {
  required Size size,
  double keyboardInset = 0,
  AppLanguage language = AppLanguage.nl,
  bool isPaidBooking = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          viewInsets: EdgeInsets.only(bottom: keyboardInset),
          padding: const EdgeInsets.only(bottom: 24),
        ),
        child: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: StreetBusinessInvoiceForm(
              theme: _theme,
              language: language,
              isPaidBooking: isPaidBooking,
              initial: const StreetBusinessInvoiceBuyerInput(),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

final Finder _requestButton = find.widgetWithText(
  FilledButton,
  'Factuur aanvragen',
);
final Finder _cancelButton = find.widgetWithText(OutlinedButton, 'Annuleren');

void _expectActionsReachable(WidgetTester tester, Size size, double inset) {
  expect(tester.takeException(), isNull);
  expect(_requestButton, findsOneWidget);
  expect(_cancelButton, findsOneWidget);
  final requestRect = tester.getRect(_requestButton);
  final cancelRect = tester.getRect(_cancelButton);
  final reachableBottom = size.height - inset + 0.5;
  // Buttons are never hidden behind the keyboard / system navigation area.
  expect(requestRect.bottom, lessThanOrEqualTo(reachableBottom));
  expect(cancelRect.bottom, lessThanOrEqualTo(reachableBottom));
  expect(requestRect.top, greaterThanOrEqualTo(0));
}

void main() {
  testWidgets('phone form is scrollable and has no overflow', (tester) async {
    const size = Size(400, 780);
    await _pumpForm(tester, size: size);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);
    // The scroll body can actually scroll (long field list on a short phone).
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -200),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    _expectActionsReachable(tester, size, 0);
  });

  testWidgets('tablet portrait keeps action buttons visible', (tester) async {
    const size = Size(834, 1194);
    await _pumpForm(tester, size: size);
    _expectActionsReachable(tester, size, 0);
    // Bounded height: the sheet never exceeds 90% of the screen.
    final formRect = tester.getRect(find.byType(StreetBusinessInvoiceForm));
    expect(formRect.height, lessThanOrEqualTo(size.height * 0.9 + 1));
  });

  testWidgets('tablet landscape keeps action buttons visible', (tester) async {
    const size = Size(1194, 834);
    await _pumpForm(tester, size: size);
    _expectActionsReachable(tester, size, 0);
  });

  testWidgets('keyboard-open layout keeps actions reachable', (tester) async {
    const size = Size(400, 780);
    const inset = 336.0;
    await _pumpForm(tester, size: size, keyboardInset: inset);
    _expectActionsReachable(tester, size, inset);
  });

  testWidgets('empty required fields block submit (no pop)', (tester) async {
    const size = Size(400, 780);
    await _pumpForm(tester, size: size);
    await tester.tap(_requestButton);
    await tester.pump();
    // Still on the form; a required-field message is shown.
    expect(_requestButton, findsOneWidget);
    expect(find.text('Verplicht veld'), findsWidgets);
  });

  group('form renders localized title + primary action', () {
    const titles = <AppLanguage, String>{
      AppLanguage.nl: 'Zakelijke factuur aanvragen',
      AppLanguage.en: 'Request business invoice',
      AppLanguage.fr: 'Demander une facture professionnelle',
      AppLanguage.es: 'Solicitar factura comercial',
    };
    for (final entry in titles.entries) {
      testWidgets('locale ${entry.key.name}', (tester) async {
        await _pumpForm(
          tester,
          size: const Size(400, 780),
          language: entry.key,
        );
        expect(find.text(entry.value), findsOneWidget);
        expect(find.textContaining('nl:'), findsNothing);
      });
    }
  });

  testWidgets('unpaid booking shows the outstanding-payment explanation', (
    tester,
  ) async {
    await _pumpForm(
      tester,
      size: const Size(400, 780),
      isPaidBooking: false,
      language: AppLanguage.en,
    );
    expect(
      find.text(
        'This invoice remains outstanding until payment is registered.',
      ),
      findsOneWidget,
    );
  });
}
