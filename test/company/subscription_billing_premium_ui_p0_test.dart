import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-contract tests for the premium redesign of
/// [CompanySubscriptionBillingPage]. These read the Flutter source directly
/// and never call live APIs or mutate tenant data.
///
/// Run:
///   flutter test test/company/subscription_billing_premium_ui_p0_test.dart
void main() {
  late String billingSource;

  setUpAll(() {
    billingSource = File(
      'lib/main_parts/company_subscription_billing_state.dart',
    ).readAsStringSync();
  });

  group('premium build helpers', () {
    test('subscription hero, usage row and monthly add-ons builders exist', () {
      expect(
        billingSource.contains('_buildSubscriptionHero'),
        isTrue,
        reason: 'missing _buildSubscriptionHero method',
      );
      expect(
        billingSource.contains('_buildUsageLimitsRow'),
        isTrue,
        reason: 'missing _buildUsageLimitsRow method',
      );
      expect(
        billingSource.contains('_buildMonthlyAddonsSection'),
        isTrue,
        reason: 'missing _buildMonthlyAddonsSection method',
      );
      expect(
        billingSource.contains('_buildPdfCreditsSection'),
        isTrue,
        reason: 'missing _buildPdfCreditsSection method',
      );
    });

    test('LayoutBuilder is used for responsive sections', () {
      final count = 'LayoutBuilder'.allMatches(billingSource).length;
      expect(
        count >= 3,
        isTrue,
        reason: 'expected at least 3 LayoutBuilder uses '
            '(usage row / add-ons / PDF grid), found $count',
      );
    });
  });

  group('founder banner gating', () {
    test('founder banner uses isFounderCustomer or founder locked price', () {
      // The generic "Eerste 100 bedrijven" marketing banner MUST be gone on
      // €69 accounts — the new founder banner is only rendered when
      // profile.isFounderCustomer OR the locked price equals the founder
      // price.
      expect(billingSource.contains('Eerste \${catalog.founderSlotsLimit}'),
          isFalse,
          reason: 'legacy "Eerste N bedrijven" banner must be removed');
      expect(billingSource.contains('First \${catalog.founderSlotsLimit}'),
          isFalse,
          reason: 'legacy "First N companies" banner must be removed');
      // Guarded rendering must reference either flag.
      expect(billingSource.contains('profile.isFounderCustomer'), isTrue);
      expect(
        billingSource.contains('lockedCents == founderCents') ||
            billingSource.contains('profile.lockedPriceCents ==') ||
            billingSource.contains('lockedPriceCents ==') ||
            billingSource.contains('isFounderLocked'),
        isTrue,
        reason: 'founder-locked check must be present',
      );
    });

    test('legacy "Fluxidi Platform" hero pill is gone', () {
      // The redesigned hero uses "Fluxidi Pro" plus the market name; the old
      // generic "Fluxidi Platform" branding pill must not linger.
      expect(billingSource.contains("'Fluxidi Platform'"), isFalse);
    });
  });

  group('trial gate preserved', () {
    test('trial marketing hidden when subscription is paid active', () {
      expect(billingSource.contains('if (!isPaidActive)'), isTrue);
      expect(billingSource.contains('2 weken gratis proefperiode'), isTrue);
      expect(billingSource.contains('Proefperiode start/einde'), isTrue);
    });
  });

  group('PDF section new layout', () {
    test('LayoutBuilder used for PDF purchase cards; new copy present', () {
      expect(billingSource.contains('_buildPdfCreditsSection'), isTrue);
      expect(billingSource.contains('credits resterend'), isTrue);
      expect(billingSource.contains('credits remaining'), isTrue);
      expect(billingSource.contains('crédits restants'), isTrue);
      expect(billingSource.contains('créditos restantes'), isTrue);
      expect(billingSource.contains('eenmalig'), isTrue);
      expect(billingSource.contains('one-time'), isTrue);
      expect(billingSource.contains('Vervallen nooit'), isTrue);
      expect(billingSource.contains('Nieuwe maandbundel op'), isTrue);
      expect(billingSource.contains('Inbegrepen deze maand'), isTrue);
      expect(billingSource.contains('Aangekochte PDF-credits'), isTrue);
      expect(billingSource.contains('purchasedPdfCredits'), isTrue);
    });

    test('legacy PDF add-on copy is gone', () {
      expect(billingSource.contains('Beschikbaar als add-on'), isFalse,
          reason: 'legacy fallback label must be removed');
      expect(billingSource.contains('Actief: 1 × 500'), isFalse,
          reason: 'legacy PDF active-quantity chip wording must be removed');
      // Substring form of the templated qty × pdfs badge.
      expect(billingSource.contains('Actief: \$activeQty × \$pdfs'), isFalse);
      expect(billingSource.contains('Nog een pakket'), isFalse,
          reason: 'legacy "Nog een pakket" wording must be removed');
      expect(billingSource.contains('_pdfBundleCancellationControls'), isFalse);
      expect(billingSource.contains('_confirmAndCancelOnePdfBundle'), isFalse);
    });
  });

  group('theme + contrast', () {
    test('theme resolved via businessThemeNotifier + paletteForBusinessTheme',
        () {
      expect(billingSource.contains('businessThemeNotifier'), isTrue);
      expect(billingSource.contains('paletteForBusinessTheme'), isTrue);
    });

    test('no hardcoded Corporate Blue accent hex in billing file', () {
      // Guard against reintroducing the concept-image Corporate Blue accents.
      final lower = billingSource.toLowerCase();
      expect(lower.contains('0xff60a5fa'), isFalse,
          reason: 'Corporate Blue accent 0xFF60A5FA must not be hardcoded');
      expect(lower.contains('0xff3b82f6'), isFalse,
          reason: 'Blue-500 hex 0xFF3B82F6 must not be hardcoded');
      expect(lower.contains('0xff1d4ed8'), isFalse,
          reason: 'Blue-700 hex 0xFF1D4ED8 must not be hardcoded');
    });

    test('prefers textPrimary/textSecondary over heavy opacity dimming', () {
      final primaryHits =
          RegExp(r'textPrimary').allMatches(billingSource).length;
      final secondaryHits =
          RegExp(r'textSecondary').allMatches(billingSource).length;
      expect(primaryHits > 20, isTrue,
          reason: 'expected many textPrimary references, got $primaryHits');
      expect(secondaryHits >= 3, isTrue,
          reason: 'expected textSecondary references for legible captions');
    });
  });

  group('cancel/undo strings preserved', () {
    test('base cancel + scheduled + undo copy still present', () {
      for (final s in <String>[
        '_baseCancelConsequenceLines',
        'Founderprijs',
        'founder price',
        'tarif fondateur',
        'precio fundador',
        'Eén extra voertuig opzeggen',
        'Cancel one extra vehicle',
        'Opgezegd — actief t/m',
        'Cancelled — active until',
        'Opzegging ongedaan maken',
        'Undo cancellation',
        'Vandaag wordt niets aangerekend',
        'Nothing is charged today',
        'undoCancelCompanySubscription',
        'minimumSize: const Size.fromHeight(48)',
        'OutlinedButton.icon',
      ]) {
        expect(billingSource.contains(s), isTrue, reason: 'missing "$s"');
      }
    });

    test('NL/EN/FR/ES cancel labels are all present', () {
      for (final snippet in <String>[
        "nl: 'Abonnement opzeggen'",
        "en: 'Cancel subscription'",
        "fr: 'Résilier l\\'abonnement'",
        "es: 'Cancelar suscripción'",
        "nl: 'Eén extra voertuig opzeggen'",
        "en: 'Cancel one extra vehicle'",
        "fr: 'Résilier un véhicule supplémentaire'",
        "es: 'Cancelar un vehículo extra'",
      ]) {
        expect(billingSource.contains(snippet), isTrue, reason: snippet);
      }
    });
  });

  group('NL/EN/FR/ES new labels', () {
    test('"Inbegrepen mogelijkheden" section title localized', () {
      expect(billingSource.contains("nl: 'Inbegrepen mogelijkheden'"), isTrue);
      expect(
          billingSource.contains("en: 'Included capabilities'"), isTrue,
          reason: 'English equivalent of "Inbegrepen mogelijkheden" missing');
      expect(
          billingSource.contains("fr: 'Fonctionnalités incluses'"), isTrue,
          reason: 'French equivalent missing');
      expect(
          billingSource.contains("es: 'Capacidades incluidas'"), isTrue,
          reason: 'Spanish equivalent missing');
    });

    test('"Nog één toevoegen" NL/EN/FR/ES present', () {
      expect(billingSource.contains("nl: 'Nog één toevoegen'"), isTrue);
      expect(billingSource.contains("en: 'Add one more'"), isTrue);
      expect(billingSource.contains("fr: 'Ajouter un de plus'"), isTrue);
      expect(billingSource.contains("es: 'Añadir uno más'"), isTrue);
    });

    test('PDF "Kopen" and "eenmalig" localized', () {
      for (final s in <String>[
        "nl: 'Kopen'",
        "en: 'Buy'",
        "fr: 'Acheter'",
        "es: 'Comprar'",
        "nl: 'eenmalig'",
        "en: 'one-time'",
        "fr: 'ponctuel'",
        "es: 'único'",
      ]) {
        expect(billingSource.contains(s), isTrue, reason: 'missing "$s"');
      }
    });
  });

  group('SafeArea + no raw ISO dates', () {
    test('viewPadding-based scroll padding present', () {
      expect(
        billingSource.contains('MediaQuery.viewPaddingOf(context).bottom'),
        isTrue,
      );
      expect(billingSource.contains('24 + bottomSafeInset'), isTrue);
    });

    test('_humanDate is used for date rendering', () {
      // We do not attempt to detect every raw ISO print, but the source must
      // still route dates through _humanDate.
      expect(billingSource.contains('_humanDate('), isTrue);
    });
  });
}
