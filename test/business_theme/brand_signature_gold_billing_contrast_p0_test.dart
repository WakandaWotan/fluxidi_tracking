import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// GOLD-THEME-BILLING-CONTRAST-P0 regression suite.
///
/// Proves — without live APIs or tenant mutation — that the Brand Signature
/// Gold "Subscription & billing" page:
///   * routes gold text/borders and destructive/warning colors to accessible
///     tokens on its light ivory surface (near-black, dark bronze, dark coral),
///   * keeps the cancellation dialog readable with a prominent filled-gold safe
///     action and a distinct coral destructive action,
///   * shows a transparent, authoritative VAT breakdown with the incl.-VAT
///     total as the dominant figure and an honest "calculated at checkout"
///     fallback, all localized in NL/EN/FR/ES,
///   * never hard-codes a VAT rate or gross total, and
///   * leaves non-Gold themes on their original tokens.
///
/// Run:
///   flutter test test/business_theme/brand_signature_gold_billing_contrast_p0_test.dart
void main() {
  late String billing;

  setUpAll(() {
    billing = File(
      'lib/main_parts/company_subscription_billing_state.dart',
    ).readAsStringSync();
  });

  // ---- WCAG relative-luminance contrast, computed on the actual constants ---
  double lin(double c) {
    final s = c / 255.0;
    return s <= 0.03928
        ? s / 12.92
        : math.pow((s + 0.055) / 1.055, 2.4) as double;
  }

  double luminance(Color c) =>
      0.2126 * lin(c.red.toDouble()) +
      0.7152 * lin(c.green.toDouble()) +
      0.0722 * lin(c.blue.toDouble());

  double contrast(Color a, Color b) {
    final la = luminance(a);
    final lb = luminance(b);
    final hi = math.max(la, lb);
    final lo = math.min(la, lb);
    return (hi + 0.05) / (lo + 0.05);
  }

  // FLX-00001's Gold surface is a light ivory; the metallic accent is D4AF37.
  const ivory = Color(0xFFF6EFE4);
  const goldFill = Color(0xFFD4AF37);
  const bronzeInk = Color(0xFF7A5C0E); // _goldInk
  const nearBlack = Color(0xFF231B05); // _onGoldFill
  const coral = Color(0xFFB3261E); // _billingDanger

  group('accessible Gold billing tokens (numeric contrast)', () {
    test('dark bronze gold text is readable on the ivory surface', () {
      expect(contrast(bronzeInk, ivory), greaterThanOrEqualTo(4.5));
    });

    test('destructive dark coral is readable on the ivory surface', () {
      expect(contrast(coral, ivory), greaterThanOrEqualTo(4.5));
    });

    test('near-black text is readable on a filled bright-gold button', () {
      expect(contrast(nearBlack, goldFill), greaterThanOrEqualTo(4.5));
    });

    test('the bright metallic accent alone is NOT used as text on ivory', () {
      // Documents WHY the bronze token exists: raw D4AF37 fails badly as text.
      expect(contrast(goldFill, ivory), lessThan(3.0));
    });
  });

  group('Gold-on-light semantic color helpers exist and gate correctly', () {
    test('the light-Gold helpers are declared', () {
      for (final token in const <String>[
        'bool get _isGoldOnLight',
        'Color get _goldInk',
        'Color get _onGoldFill',
        'Color get _billingDanger',
      ]) {
        expect(billing.contains(token), isTrue, reason: 'missing $token');
      }
    });

    test(
      '_isGoldOnLight is scoped to Brand Signature Gold on a light palette',
      () {
        expect(
          billing.contains('BusinessThemeVariant.brandSignatureGold') &&
              billing.contains('!_businessThemePalette.isDark'),
          isTrue,
        );
      },
    );

    test('helpers carry the exact accessible constants', () {
      expect(billing.contains('const Color(0xFF7A5C0E)'), isTrue); // bronze
      expect(billing.contains('const Color(0xFF231B05)'), isTrue); // near-black
      expect(billing.contains('const Color(0xFFB3261E)'), isTrue); // coral
    });
  });

  group('destructive / warning elements read as coral on light Gold', () {
    test('_warn routes to the accessible coral when _isGoldOnLight', () {
      expect(
        billing.contains('if (_isGoldOnLight) return _billingDanger;'),
        isTrue,
        reason: 'faint cancel buttons / chips / borders must use coral on Gold',
      );
    });

    test('non-Gold themes keep the original rose-gold _warn blend', () {
      expect(
        billing.contains('Color.lerp(p.danger, p.accent, 0.30)'),
        isTrue,
        reason: 'blue and other themes must be untouched',
      );
    });
  });

  group('cancellation dialog is readable and safe-by-default', () {
    test('Keep is a prominent filled-gold action with near-black text', () {
      // The only near-black-on-gold foreground in the file is the dialog Keep
      // button; the fill stays the bright gold accent.
      expect(
        billing.contains('foregroundColor: _onGoldFill'),
        isTrue,
        reason: 'the safe Keep action should be filled gold with dark text',
      );
      expect(billing.contains('backgroundColor: _gold'), isTrue);
    });

    test('Cancel is a distinct accessible coral action', () {
      expect(
        billing.contains(
          'TextButton.styleFrom(foregroundColor: _billingDanger)',
        ),
        isTrue,
      );
    });

    test('dialogs dismiss via Navigator.pop so the scrim self-clears', () {
      // Standard showDialog manages/removes its own ModalBarrier on pop; there
      // is no persistent hand-rolled barrier left dimming the page.
      expect(billing.contains('showDialog<bool>'), isTrue);
      expect(billing.contains('Navigator.of(ctx).pop(false)'), isTrue);
      expect(billing.contains('Navigator.of(ctx).pop(true)'), isTrue);
      expect(billing.contains('ModalBarrier('), isFalse);
    });
  });

  group('gold text/borders use the bronze ink, fills stay bright gold', () {
    test('the hero plan label and add-on outlined CTAs use _goldInk', () {
      expect(billing.contains('color: _goldInk'), isTrue);
      expect(billing.contains('foregroundColor: _goldInk'), isTrue);
      expect(
        billing.contains('side: BorderSide(color: _goldInk.withOpacity(0.85))'),
        isTrue,
      );
    });

    test(
      'filled CTAs keep the bright gold background (identity preserved)',
      () {
        expect(billing.contains('backgroundColor: _gold'), isTrue);
      },
    );
  });

  group('transparent, authoritative VAT breakdown in the hero', () {
    test('incl.-VAT total is the dominant figure when VAT is known', () {
      // The big 34px figure switches to the incl. total; the excl. subtotal is
      // demoted to a smaller line below.
      expect(billing.contains('_priceFromCents(recurringInclCents)'), isTrue);
      expect(billing.contains('fontSize: 34'), isTrue);
    });

    test('subtotal excl., applicable rate and VAT amount are shown', () {
      expect(billing.contains('Subtotal excl. VAT: '), isTrue);
      expect(
        billing.contains('_recurringVatLine(recurringVatCents, currentQuote)'),
        isTrue,
      );
      expect(billing.contains('String _vatRatePercent(double rate)'), isTrue);
      expect(billing.contains('String _recurringVatLine('), isTrue);
    });

    test('honest fallback when no authoritative VAT is available', () {
      expect(billing.contains('VAT calculated at checkout'), isTrue);
    });

    test('reverse-charge is surfaced, not silently taxed', () {
      expect(billing.contains("currentQuote?.isReverseCharge == true"), isTrue);
      expect(billing.contains('VAT reverse-charged'), isTrue);
    });

    test('no hard-coded VAT rate or gross total anywhere in billing', () {
      expect(billing.contains('129.47'), isFalse);
      expect(billing.contains('0.21'), isFalse);
      expect(billing.contains("'21%'"), isFalse);
    });
  });

  group('all new billing labels are localized NL/EN/FR/ES', () {
    void expectAll(List<String> variants, String label) {
      for (final v in variants) {
        expect(billing.contains(v), isTrue, reason: '$label missing: $v');
      }
    }

    test('incl.-VAT suffix', () {
      expectAll(const <String>[
        "nl: '/ maand incl. btw'",
        "en: '/ month incl. VAT'",
        "fr: '/ mois TTC'",
        "es: '/ mes con IVA'",
      ], 'incl. VAT suffix');
    });

    test('subtotal excl. VAT line', () {
      expectAll(const <String>[
        r"nl: 'Subtotaal excl. btw: $monthlyText'",
        r"en: 'Subtotal excl. VAT: $monthlyText'",
        r"fr: 'Sous-total HT : $monthlyText'",
        r"es: 'Subtotal sin IVA: $monthlyText'",
      ], 'subtotal excl.');
    });

    test('VAT rate + amount line', () {
      expectAll(const <String>[
        r"nl: 'Btw $pct: $vatText'",
        r"en: 'VAT $pct: $vatText'",
        r"fr: 'TVA $pct : $vatText'",
        r"es: 'IVA $pct: $vatText'",
      ], 'VAT rate line');
    });

    test('checkout fallback', () {
      expectAll(const <String>[
        "nl: 'Btw wordt bij het afrekenen berekend'",
        "en: 'VAT calculated at checkout'",
        "fr: 'TVA calculée au paiement'",
        "es: 'IVA calculado al finalizar'",
      ], 'checkout fallback');
    });
  });
}
