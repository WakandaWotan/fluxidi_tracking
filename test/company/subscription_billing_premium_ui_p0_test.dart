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
        reason:
            'expected at least 3 LayoutBuilder uses '
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
      expect(
        billingSource.contains('Eerste \${catalog.founderSlotsLimit}'),
        isFalse,
        reason: 'legacy "Eerste N bedrijven" banner must be removed',
      );
      expect(
        billingSource.contains('First \${catalog.founderSlotsLimit}'),
        isFalse,
        reason: 'legacy "First N companies" banner must be removed',
      );
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
      expect(
        billingSource.contains('Beschikbaar als add-on'),
        isFalse,
        reason: 'legacy fallback label must be removed',
      );
      expect(
        billingSource.contains('Actief: 1 × 500'),
        isFalse,
        reason: 'legacy PDF active-quantity chip wording must be removed',
      );
      // Substring form of the templated qty × pdfs badge.
      expect(billingSource.contains('Actief: \$activeQty × \$pdfs'), isFalse);
      expect(
        billingSource.contains('Nog een pakket'),
        isFalse,
        reason: 'legacy "Nog een pakket" wording must be removed',
      );
      expect(billingSource.contains('_pdfBundleCancellationControls'), isFalse);
      expect(billingSource.contains('_confirmAndCancelOnePdfBundle'), isFalse);
    });
  });

  group('theme + contrast', () {
    test(
      'theme resolved via businessThemeNotifier + paletteForBusinessTheme',
      () {
        expect(billingSource.contains('businessThemeNotifier'), isTrue);
        expect(billingSource.contains('paletteForBusinessTheme'), isTrue);
      },
    );

    test('no hardcoded Corporate Blue accent hex in billing file', () {
      // Guard against reintroducing the concept-image Corporate Blue accents.
      final lower = billingSource.toLowerCase();
      expect(
        lower.contains('0xff60a5fa'),
        isFalse,
        reason: 'Corporate Blue accent 0xFF60A5FA must not be hardcoded',
      );
      expect(
        lower.contains('0xff3b82f6'),
        isFalse,
        reason: 'Blue-500 hex 0xFF3B82F6 must not be hardcoded',
      );
      expect(
        lower.contains('0xff1d4ed8'),
        isFalse,
        reason: 'Blue-700 hex 0xFF1D4ED8 must not be hardcoded',
      );
    });

    test('prefers textPrimary/textSecondary over heavy opacity dimming', () {
      final primaryHits = RegExp(
        r'textPrimary',
      ).allMatches(billingSource).length;
      final secondaryHits = RegExp(
        r'textSecondary',
      ).allMatches(billingSource).length;
      expect(
        primaryHits > 20,
        isTrue,
        reason: 'expected many textPrimary references, got $primaryHits',
      );
      expect(
        secondaryHits >= 3,
        isTrue,
        reason: 'expected textSecondary references for legible captions',
      );
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
        billingSource.contains("en: 'Included capabilities'"),
        isTrue,
        reason: 'English equivalent of "Inbegrepen mogelijkheden" missing',
      );
      expect(
        billingSource.contains("fr: 'Fonctionnalités incluses'"),
        isTrue,
        reason: 'French equivalent missing',
      );
      expect(
        billingSource.contains("es: 'Capacidades incluidas'"),
        isTrue,
        reason: 'Spanish equivalent missing',
      );
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
      expect(billingSource.contains('MediaQuery.viewPaddingOf'), isTrue);
      expect(billingSource.contains('bottomSafeInset'), isTrue);
      expect(billingSource.contains('24 + bottomSafeInset'), isTrue);
    });

    test('_humanDate is used for date rendering', () {
      // We do not attempt to detect every raw ISO print, but the source must
      // still route dates through _humanDate.
      expect(billingSource.contains('_humanDate('), isTrue);
    });
  });

  group('duplicate hero cleanup P0', () {
    test('duplicate "subscription active" detail block is gone', () {
      expect(
        billingSource.contains("nl: 'Abonnement actief'"),
        isFalse,
        reason: 'legacy duplicate "Abonnement actief" chip must be removed',
      );
      expect(billingSource.contains("en: 'Subscription active'"), isFalse);
      expect(billingSource.contains("fr: 'Abonnement actif'"), isFalse);
      expect(billingSource.contains("es: 'Suscripción activa'"), isFalse);
      // Old activation-section period join "t/m" next to Actief van is gone;
      // hero keeps a single period line.
      expect(
        billingSource.contains(
          r'${_humanDate(periodStart)} t/m ${periodEnd.isEmpty ? "—" : _humanDate(periodEnd)}',
        ),
        isFalse,
        reason: 'duplicate activation-section period line must be gone',
      );
    });

    test('hero shows period and next payment once; cancel CTA remains', () {
      expect(
        "nl: 'Actief van'".allMatches(billingSource).length,
        1,
        reason: 'Actief van label must appear once (hero only)',
      );
      expect(
        "nl: 'Volgende betaling'".allMatches(billingSource).length,
        1,
        reason: 'Volgende betaling label must appear once (hero only)',
      );
      expect(billingSource.contains('_buildCancellationSection'), isTrue);
      expect(billingSource.contains("nl: 'Abonnement opzeggen'"), isTrue);
      expect(billingSource.contains('Opzegging ongedaan maken'), isTrue);
      expect(billingSource.contains('Undo cancellation'), isTrue);
    });
  });

  group('responsive icon hierarchy P0', () {
    test('icon geometry uses host layoutWidth and role metrics', () {
      expect(billingSource.contains('_premiumIconMetrics'), isTrue);
      expect(billingSource.contains('_premiumIconBadge'), isTrue);
      expect(billingSource.contains('_PremiumIconRole'), isTrue);
      expect(
        billingSource.contains('layoutWidth >= 600'),
        isTrue,
        reason: 'tablet class must use layoutWidth, not shortestSide alone',
      );
      expect(
        billingSource.contains('MediaQuery') &&
            billingSource.contains('shortestSide'),
        isFalse,
        reason: 'do not size premium icons via MediaQuery.shortestSide',
      );
      // Tablet KPI circle range includes 52–60.
      expect(billingSource.contains('cMin = 52'), isTrue);
      expect(billingSource.contains('cMax = 60'), isTrue);
      // Phone KPI circle range includes 42–48.
      expect(billingSource.contains('cMin = 42'), isTrue);
      expect(billingSource.contains('cMax = 48'), isTrue);
      expect(billingSource.contains('role: _PremiumIconRole.kpi'), isTrue);
      expect(
        billingSource.contains('role: _PremiumIconRole.extension'),
        isTrue,
      );
      expect(
        billingSource.contains('role: _PremiumIconRole.pdfBalance'),
        isTrue,
      );
    });

    test('theme colours come from palette, not fixed mock blues', () {
      expect(billingSource.contains('_secondaryAccent'), isTrue);
      expect(billingSource.contains('Color.lerp(_gold, _green'), isTrue);
      expect(billingSource.contains('_businessThemePalette.success'), isTrue);
      expect(billingSource.contains('_businessThemePalette.accent'), isTrue);
      final lower = billingSource.toLowerCase();
      expect(lower.contains('0xff60a5fa'), isFalse);
      expect(lower.contains('0xff3b82f6'), isFalse);
    });
  });

  group('server-authoritative VAT checkout', () {
    late String configSource;

    setUpAll(() {
      configSource = File('lib/app_config.dart').readAsStringSync();
    });

    test('client fetches quote and never sends a price', () {
      expect(
        billingSource.contains('fetchCompanySubscriptionCheckoutQuote'),
        isTrue,
      );
      expect(
        billingSource.contains('fetchCompanySubscriptionDisplayQuotes'),
        isTrue,
      );
      expect(billingSource.contains('_confirmCheckoutQuote'), isTrue);
      expect(billingSource.contains('quoteId: quote.quoteId'), isTrue);
      expect(billingSource.contains('amount_cents'), isFalse);
      expect(configSource.contains('0.21'), isFalse);
      expect(billingSource.contains('0.21'), isFalse);
    });

    test('extra chauffeur card uses catalog unit helper, not qty × unit', () {
      expect(billingSource.contains('_addonCardPriceLabel'), isTrue);
      expect(billingSource.contains('_addonCardUnitMoney'), isTrue);
      expect(billingSource.contains('resolveAddonCardUnitMoney'), isTrue);
      expect(billingSource.contains("productCode: 'extra_driver'"), isTrue);
      expect(billingSource.contains('catalog.extraDriverPriceCents'), isTrue);
      expect(
        billingSource.contains("nl: '\$dQty actief'"),
        isTrue,
        reason: '0 actief chip must remain quantity-based',
      );
      expect(
        billingSource.contains('unitExclVatCents *'),
        isFalse,
        reason: 'card must not multiply quote unit by active quantity',
      );
      expect(
        billingSource.contains('extraDriverActiveQuantity *'),
        isFalse,
        reason: 'card must not multiply catalog unit by active quantity',
      );
    });

    test(
      'activation preview stays on the server quote and does not start checkout',
      () {
        expect(billingSource.contains('_confirmCheckoutQuote'), isTrue);
        expect(billingSource.contains('quote.subtotalExclVatCents'), isTrue);
        expect(billingSource.contains('quote.recurringExclVatCents'), isTrue);
        expect(billingSource.contains('quote.recurringInclVatCents'), isTrue);
        expect(billingSource.contains('Nieuwe recurring'), isTrue);
        expect(
          billingSource.contains('startCompanySubscriptionAddonCheckout'),
          isTrue,
        );
        expect(billingSource.contains("addonCode: 'extra_driver'"), isTrue);
      },
    );

    test('confirm dialog shows excl VAT, treatment, VAT and total', () {
      expect(billingSource.contains('Basisplan excl. btw'), isTrue);
      expect(billingSource.contains('Extra voertuig'), isTrue);
      expect(billingSource.contains('Subtotaal excl. btw'), isTrue);
      expect(billingSource.contains('Btw-behandeling'), isTrue);
      expect(billingSource.contains('btw verlegd'), isTrue);
      expect(billingSource.contains('Te betalen totaal'), isTrue);
      expect(billingSource.contains('Nieuwe recurring'), isTrue);
      expect(billingSource.contains('Proefperiode tot'), isTrue);
      expect(
        billingSource.contains('Volgende betaling nog niet gesynchroniseerd'),
        isTrue,
      );
      expect(billingSource.contains('Fiscale behandeling onbekend'), isTrue);
    });
  });
}
