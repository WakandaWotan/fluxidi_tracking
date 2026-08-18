import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/business_settings_page.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';
import 'package:fluxidi_tracking/limousine/limousine_business_setup.dart';
import 'package:fluxidi_tracking/limousine/limousine_business_setup_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_entry.dart';
import 'package:fluxidi_tracking/limousine/limousine_offer_editor.dart';
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1a_ux.dart';

Widget _app(Widget child, {Size size = kLimousinePhonePortrait}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: child,
    ),
  );
}

Future<void> _pumpInlineSection(
  WidgetTester tester, {
  Size size = kLimousinePhonePortrait,
}) async {
  await tester.pumpWidget(
    _app(
      const BusinessSettingsPage(
        stepMode: true,
        initialFocus: 'limousine_offers_pricing',
      ),
      size: size,
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    appLanguageNotifier.value = AppLanguage.nl;
    businessThemeNotifier.value = BusinessThemeVariant.executiveGold;
  });

  test('inline section source keeps one management CTA', () {
    final settings = File('lib/business_settings_page.dart').readAsStringSync();
    expect(settings.contains("id: 'limousine_offers_pricing'"), isTrue);
    expect(settings.contains('openLimousineBusinessSetup('), isTrue);
    expect(
      settings.contains('onPressed: () => openLimousineBusinessSetup('),
      isTrue,
    );
    expect(settings.contains('kLimousineBusinessSetupOpenKey'), isTrue);
    expect(settings.contains('kLimousineOffersPricingSectionTitle'), isTrue);
    expect(settings.contains('LimousineOfferEditorDialog('), isFalse);
    expect(settings.contains('_editLimousineOffer'), isFalse);
    expect(settings.contains('_saveLimousineOffers'), isFalse);
    expect(settings.contains('_limousineOfferRow'), isFalse);
    expect(settings.contains('Aanbod toevoegen'), isFalse);
    expect(settings.contains('Limousineaanbod actief'), isFalse);
    expect(
      settings.contains("nl: 'Veilige publieke preview'"),
      isTrue,
      reason: 'public-profile preview outside this section stays',
    );
    expect(
      File(
        'lib/limousine/limousine_business_setup_page.dart',
      ).readAsStringSync().contains('LimousineOfferEditorDialog('),
      isTrue,
    );
    expect(
      File('lib/limousine/limousine_offer_editor.dart').existsSync(),
      isTrue,
    );
  });

  test('inline section labels exist in NL/EN/FR/ES', () {
    for (final language in const [
      AppLanguage.nl,
      AppLanguage.en,
      AppLanguage.fr,
      AppLanguage.es,
    ]) {
      expect(kLimousineOffersPricingSectionTitle.of(language), isNotEmpty);
      expect(kLimousineOffersPricingSectionIntro.of(language), isNotEmpty);
      expect(kLimousineBusinessSetupOpenAction.of(language), isNotEmpty);
      expect(kLimousineBusinessSetupTestBadge.of(language), isNotEmpty);
    }
    expect(
      kLimousineOffersPricingSectionTitle.nl,
      'Limousineaanbod en prijzen',
    );
    expect(kLimousineBusinessSetupOpenAction.nl, 'Open Limousine-instellingen');
  });

  testWidgets('inline section shows exactly one management action', (
    tester,
  ) async {
    await _pumpInlineSection(tester);
    expect(find.text(kLimousineOffersPricingSectionTitle.nl), findsWidgets);
    expect(find.text('Optioneel'), findsWidgets);
    expect(find.byKey(kLimousineBusinessSetupOpenKey), findsOneWidget);
    expect(find.text(kLimousineBusinessSetupOpenAction.nl), findsOneWidget);
    expect(LimousineCustomerEntryContract.isVisible, isFalse);
    expect(
      tester
          .widget<ButtonStyleButton>(find.byKey(kLimousineBusinessSetupOpenKey))
          .onPressed,
      isNotNull,
    );
    expect(find.text('Aanbod toevoegen'), findsNothing);
    expect(find.text('Vernieuwen'), findsNothing);
    expect(find.text('Opslaan'), findsNothing);
    expect(find.text('Limousineaanbod actief'), findsNothing);
    expect(find.text('Nog geen limousineaanbod geconfigureerd'), findsNothing);
    expect(find.text('Veilige publieke preview'), findsNothing);
    expect(find.byType(Switch), findsNothing);
    expect(find.byType(LimousineOfferEditorDialog), findsNothing);
    expect(find.textContaining('not_found'), findsNothing);
    expect(find.textContaining('404'), findsNothing);
    expect(find.textContaining('Exception'), findsNothing);
  });

  testWidgets('Open Limousine-instellingen opens the full settings page', (
    tester,
  ) async {
    await _pumpInlineSection(tester);
    tester
        .widget<ButtonStyleButton>(find.byKey(kLimousineBusinessSetupOpenKey))
        .onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(kLimousineBusinessSetupPageKey), findsOneWidget);
    expect(find.byType(LimousineOfferEditorDialog), findsNothing);
  });

  testWidgets('NL/EN/FR/ES keep the compact CTA and no raw errors', (
    tester,
  ) async {
    for (final language in const [
      AppLanguage.nl,
      AppLanguage.en,
      AppLanguage.fr,
      AppLanguage.es,
    ]) {
      appLanguageNotifier.value = language;
      await _pumpInlineSection(tester);
      expect(
        find.text(kLimousineBusinessSetupOpenAction.of(language)),
        findsOneWidget,
      );
      expect(find.text(kLimousineRequestIncompleteHint.en), findsNothing);
      expect(find.textContaining('not_found'), findsNothing);
      expect(find.textContaining('Exception'), findsNothing);
    }
  });

  testWidgets('phone and tablet host the compact section', (tester) async {
    await _pumpInlineSection(tester);
    expect(find.byKey(kLimousineBusinessSetupOpenKey), findsOneWidget);
    await _pumpInlineSection(tester, size: kLimousineSmX400Portrait);
    expect(find.byKey(kLimousineBusinessSetupOpenKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('existing business themes render the compact section', (
    tester,
  ) async {
    for (final variant in BusinessThemeVariant.values) {
      businessThemeNotifier.value = variant;
      await _pumpInlineSection(tester);
      expect(
        find.byKey(kLimousineBusinessSetupOpenKey),
        findsOneWidget,
        reason: variant.name,
      );
    }
  });
}
