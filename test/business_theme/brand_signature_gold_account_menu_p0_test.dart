// GOLD-THEME-ACCOUNT-MENU-RESTORE-P0
//
// The regular business themes render a working account/company menu at the top
// (verified identity + primary company e-mail, Company details, Privacy &
// account, Help & guide, Pair new device, Other company, NL/EN/FR/ES). In the
// Brand Signature Gold theme only the palette (theme) button used to be
// offered, so those account/recovery/help/language entries were unreachable.
//
// The fix adds a SEPARATE account button to the Gold header via a shared
// header slot ([BrandSignatureGoldHeader.accountMenu]) that mounts the EXACT
// same account menu the non-gold header uses ([_businessAccountMenuButton] in
// business_home_page_state.dart) — same state, callbacks, company identity and
// primary e-mail. The palette button is retained as its own separate control.
//
// This suite proves:
//   * Gold shows BOTH the account button and the palette button;
//   * both are separate hit targets with distinct keys and their own semantics;
//   * the account button opens its menu; the palette button opens ONLY the
//     theme selector; both survive repeated open/close;
//   * no overflow on phone/tablet in portrait and landscape;
//   * the default header (no slot) is unchanged (chauffeur Gold / previews);
//   * (source contract) the Gold header reuses the ONE shared account menu with
//     the same state, primary e-mail and all actions — no second/forked menu;
//   * non-gold themes keep the same shared button and are not changed.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/business_theme/brand_signature_palette.dart';
import 'package:fluxidi_tracking/business_theme_cycle.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';
import 'package:fluxidi_tracking/widgets/brand_signature_gold_header.dart';
import 'package:fluxidi_tracking/widgets/business_theme_cycle_button.dart';

// Mirrors the real production key (see the source-contract group below).
const Key _accountKey = Key('business_account_menu_button');
const String _accountTooltip = 'Account & company';

/// A stand-in for the shared account menu used to exercise the header slot in
/// isolation. Behaviourally identical shape (a keyed [PopupMenuButton] with the
/// account entries); the real wiring is asserted by the source-contract group.
Widget _accountMenuStub() {
  return PopupMenuButton<String>(
    key: _accountKey,
    tooltip: _accountTooltip,
    itemBuilder: (_) => const <PopupMenuEntry<String>>[
      PopupMenuItem<String>(value: 'details', child: Text('Company details')),
      PopupMenuItem<String>(
        value: 'privacy_account',
        child: Text('Privacy & account'),
      ),
    ],
    child: const SizedBox(
      width: 40,
      height: 40,
      child: Icon(Icons.account_circle_outlined),
    ),
  );
}

Widget _goldHeader({
  Widget? accountMenu,
  VoidCallback? onOpenThemeSelector,
  double height = 180,
}) {
  return MaterialApp(
    home: Scaffold(
      body: ListView(
        children: <Widget>[
          BrandSignatureGoldHeader(
            height: height,
            logoRef: '',
            hasCompanyLogo: false,
            companyName: 'FLX',
            onOpenThemeSelector: onOpenThemeSelector,
            accountMenu: accountMenu,
          ),
        ],
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BusinessThemeVariant themeBefore;
  late BrandSignaturePalette paletteBefore;

  setUp(() {
    themeBefore = businessThemeNotifier.value;
    paletteBefore = brandSignaturePaletteNotifier.value;
    businessThemeNotifier.value = BusinessThemeVariant.brandSignatureGold;
    brandSignaturePaletteNotifier.value = BrandSignaturePalette.defaults;
  });

  tearDown(() {
    businessThemeNotifier.value = themeBefore;
    brandSignaturePaletteNotifier.value = paletteBefore;
  });

  group(
    'Gold header offers BOTH the account button and the palette button',
    () {
      testWidgets('both controls render with distinct keys', (tester) async {
        await tester.pumpWidget(_goldHeader(accountMenu: _accountMenuStub()));
        await tester.pump();

        expect(find.byKey(_accountKey), findsOneWidget);
        expect(find.byKey(BusinessThemeCycleButton.buttonKey), findsOneWidget);
        expect(_accountKey == BusinessThemeCycleButton.buttonKey, isFalse);
      });

      testWidgets('each control keeps its own accessibility semantics', (
        tester,
      ) async {
        await tester.pumpWidget(_goldHeader(accountMenu: _accountMenuStub()));
        await tester.pump();

        // Palette button: existing theme-cycle semantics label + tooltip.
        expect(
          find.byTooltip(kBusinessThemeCycleSemanticLabel),
          findsOneWidget,
        );
        // Account button: its own, distinct tooltip / hit target.
        expect(find.byTooltip(_accountTooltip), findsOneWidget);
      });

      testWidgets(
        'default header (no slot) shows only the palette button — chauffeur '
        'Gold / previews unchanged',
        (tester) async {
          await tester.pumpWidget(_goldHeader());
          await tester.pump();

          expect(
            find.byKey(BusinessThemeCycleButton.buttonKey),
            findsOneWidget,
          );
          expect(find.byKey(_accountKey), findsNothing);
        },
      );

      testWidgets(
        'buttons are separate, non-overlapping hit targets that do not cover '
        'the logo',
        (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  width: 800,
                  height: 220,
                  child: BrandSignatureGoldHeader(
                    height: 200,
                    logoRef: '',
                    hasCompanyLogo: false,
                    companyName: 'FLX',
                    accountMenu: _accountMenuStub(),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();

          final header = tester.getRect(
            find.byKey(kBrandSignatureGoldHeaderKey),
          );
          final account = tester.getRect(find.byKey(_accountKey));
          final palette = tester.getRect(
            find.byKey(BusinessThemeCycleButton.buttonKey),
          );
          final logo = tester.getRect(
            find.byKey(kBrandSignatureGoldLogoFallbackKey),
          );

          expect(header.contains(account.center), isTrue);
          expect(header.contains(palette.center), isTrue);
          expect(account.overlaps(palette), isFalse);
          expect(account.overlaps(logo), isFalse);
          expect(palette.overlaps(logo), isFalse);
          // Palette control stays to the right of the account control.
          expect(palette.center.dx > account.center.dx, isTrue);
        },
      );
    },
  );

  group('behaviour: account opens its menu, palette opens only the theme', () {
    testWidgets('palette tap triggers the theme selector, not the menu', (
      tester,
    ) async {
      var themeOpened = 0;
      await tester.pumpWidget(
        _goldHeader(
          accountMenu: _accountMenuStub(),
          onOpenThemeSelector: () => themeOpened++,
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(BusinessThemeCycleButton.buttonKey));
      await tester.pump();

      expect(themeOpened, 1);
      // The account menu must NOT have opened from a palette tap.
      expect(find.text('Company details'), findsNothing);
      expect(find.text('Privacy & account'), findsNothing);
    });

    testWidgets('account tap opens the shared menu entries', (tester) async {
      var themeOpened = 0;
      await tester.pumpWidget(
        _goldHeader(
          accountMenu: _accountMenuStub(),
          onOpenThemeSelector: () => themeOpened++,
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(_accountKey));
      await tester.pumpAndSettle();

      expect(find.text('Company details'), findsOneWidget);
      expect(find.text('Privacy & account'), findsOneWidget);
      // Opening the account menu must not trip the theme selector.
      expect(themeOpened, 0);
    });

    testWidgets('the account menu survives repeated open/close', (
      tester,
    ) async {
      await tester.pumpWidget(_goldHeader(accountMenu: _accountMenuStub()));
      await tester.pump();

      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(_accountKey));
        await tester.pumpAndSettle();
        expect(find.text('Company details'), findsOneWidget);
        await tester.tap(find.text('Company details'));
        await tester.pumpAndSettle();
        expect(find.text('Company details'), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('layout: no overflow on phone/tablet, portrait and landscape', () {
    const sizes = <String, Size>{
      'phone portrait': Size(390, 844),
      'phone landscape': Size(844, 390),
      'tablet portrait': Size(800, 1280),
      'tablet landscape': Size(1280, 800),
    };

    sizes.forEach((label, size) {
      testWidgets('$label shows both controls without overflow', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final double headerHeight = size.shortestSide >= 600 ? 208 : 168;
        await tester.pumpWidget(
          _goldHeader(accountMenu: _accountMenuStub(), height: headerHeight),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.byKey(_accountKey), findsOneWidget);
        expect(find.byKey(BusinessThemeCycleButton.buttonKey), findsOneWidget);
      });
    });
  });

  // --------------------------------------------------------------------------
  // Source-contract guards: the Gold header reuses the ONE shared account menu
  // (same state / primary e-mail / callbacks) — no second, forked menu — and
  // the non-gold header is unchanged.
  // --------------------------------------------------------------------------
  group('source contract: single shared account menu, reused by Gold', () {
    final home = File(
      'lib/main_parts/business_home_page_state.dart',
    ).readAsStringSync();
    final header = File(
      'lib/widgets/brand_signature_gold_header.dart',
    ).readAsStringSync();

    test('the shared account menu is defined exactly once (no fork)', () {
      expect(
        RegExp(r'Widget _businessAccountMenuButton\(').allMatches(home).length,
        1,
      );
      // The account menu is one PopupMenuButton — its entries appear once.
      expect(RegExp("value: 'privacy_account'").allMatches(home).length, 1);
      expect(RegExp("value: 'details'").allMatches(home).length, 1);
      expect(
        RegExp(r"key: kBusinessAccountMenuButtonKey").allMatches(home).length,
        1,
      );
      expect(
        home.contains(
          "const Key kBusinessAccountMenuButtonKey = "
          "Key('business_account_menu_button')",
        ),
        isTrue,
      );
    });

    test('non-gold header reuses the shared button (unchanged)', () {
      expect(
        home.contains('_businessHomeLogo(width: businessLogoWidth)'),
        isTrue,
      );
      expect(
        home.contains('_businessAccountMenuButton(context, profile),'),
        isTrue,
      );
      // The Gold render branch guard is intact.
      expect(home.contains('if (isBrandSignatureGold)'), isTrue);
    });

    test('Gold header reuses the same shared menu (compact), not a copy', () {
      expect(home.contains('accountMenu: _businessAccountMenuButton('), isTrue);
      expect(home.contains('compact: true'), isTrue);
    });

    test('primary company e-mail + identity come from the same state', () {
      // The menu shows the confirmed primary company e-mail from profile,
      // never a fabricated login/support/billing/booking fallback.
      expect(home.contains('profile.email.trim()'), isTrue);
      expect(
        home.contains('_resolvePublicBookingCompanyCodeForDashboard()'),
        isTrue,
      );
      expect(home.contains('appLanguageNotifier.value'), isTrue);
    });

    test('all account actions and NL/EN/FR/ES stay wired to the menu', () {
      expect(home.contains('_openCompanyDetails(context)'), isTrue);
      expect(home.contains('openFluxidiPrivacyAccountPage('), isTrue);
      expect(home.contains('_openBusinessHelpManual(context)'), isTrue);
      expect(home.contains("value: 'pair_new_device'"), isTrue);
      expect(home.contains('_switchCompany(context)'), isTrue);
      expect(home.contains('setAppLanguage(AppLanguage.nl)'), isTrue);
      expect(home.contains('setAppLanguage(AppLanguage.en)'), isTrue);
      expect(home.contains('setAppLanguage(AppLanguage.fr)'), isTrue);
      expect(home.contains('setAppLanguage(AppLanguage.es)'), isTrue);
    });

    test('Gold header slot renders the account menu beside the palette', () {
      expect(header.contains('final Widget? accountMenu;'), isTrue);
      expect(header.contains('accountMenu!'), isTrue);
      expect(header.contains('trailing ?? actions'), isTrue);
      // The palette (theme) control is retained.
      expect(header.contains('BusinessThemeCycleButton('), isTrue);
    });
  });
}
