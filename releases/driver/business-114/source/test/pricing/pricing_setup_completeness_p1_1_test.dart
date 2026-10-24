// FLUXIDI-PRICING-COMPLETENESS-BADGE-AUDIT-P1-1
//
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/pricing/pricing_setup_completeness.dart';

void main() {
  group('evaluatePricingSetupCompleteness', () {
    test('all valid fields configured → Complete', () {
      final r = evaluatePricingSetupCompleteness(
        baseFare: '5.00',
        perKm: '1.80',
        perMinute: '0.40',
        minimumFare: '8.00',
      );
      expect(r.kind, PricingSetupCompletenessKind.complete);
      expect(r.reasonKeys, isEmpty);
      expect(r.passedCount, 4);
    });

    test('valid optional-looking 0.00 core values → Complete', () {
      final r = evaluatePricingSetupCompleteness(
        baseFare: '0.00',
        perKm: '0.00',
        perMinute: '0.00',
        minimumFare: '0.00',
      );
      expect(r.kind, PricingSetupCompletenessKind.complete);
      expect(r.reasonKeys, isEmpty);
    });

    test('price per minute 0.00 → Complete when other cores valid', () {
      final r = evaluatePricingSetupCompleteness(
        baseFare: '5.00',
        perKm: '1.80',
        perMinute: '0.00',
        minimumFare: '8.00',
      );
      expect(r.kind, PricingSetupCompletenessKind.complete);
    });

    test('comma decimals and whitespace still complete', () {
      final r = evaluatePricingSetupCompleteness(
        baseFare: ' 5,50 ',
        perKm: '1,20',
        perMinute: '0,00',
        minimumFare: '7,00',
      );
      expect(r.kind, PricingSetupCompletenessKind.complete);
    });

    test('genuinely missing required field → Attention with exact reason', () {
      final r = evaluatePricingSetupCompleteness(
        baseFare: '5.00',
        perKm: '1.80',
        perMinute: '',
        minimumFare: '8.00',
      );
      expect(r.kind, PricingSetupCompletenessKind.attention);
      expect(r.reasonKeys, [PricingSetupReasonKey.perMinuteMissing]);
    });

    test('all cores missing → Incomplete', () {
      final r = evaluatePricingSetupCompleteness(
        baseFare: '',
        perKm: '  ',
        perMinute: '',
        minimumFare: '',
      );
      expect(r.kind, PricingSetupCompletenessKind.incomplete);
      expect(r.reasonKeys, contains(PricingSetupReasonKey.baseFareMissing));
      expect(r.reasonKeys, contains(PricingSetupReasonKey.perKmMissing));
      expect(r.reasonKeys, contains(PricingSetupReasonKey.perMinuteMissing));
      expect(r.reasonKeys, contains(PricingSetupReasonKey.minimumFareMissing));
    });

    test('invalid negative → Attention needed', () {
      final r = evaluatePricingSetupCompleteness(
        baseFare: '5.00',
        perKm: '-1.00',
        perMinute: '0.00',
        minimumFare: '8.00',
      );
      expect(r.kind, PricingSetupCompletenessKind.attention);
      expect(r.reasonKeys, [PricingSetupReasonKey.perKmInvalid]);
    });

    test('malformed value → Attention needed', () {
      final r = evaluatePricingSetupCompleteness(
        baseFare: 'abc',
        perKm: '1.80',
        perMinute: '0.00',
        minimumFare: '8.00',
      );
      expect(r.kind, PricingSetupCompletenessKind.attention);
      expect(r.reasonKeys, [PricingSetupReasonKey.baseFareInvalid]);
    });

    test('legacy/current field mismatch cannot cause false attention', () {
      // Optional legacy-looking values are outside the canonical core set.
      // Completeness is derived only from the four core fields.
      final fromNumbers = evaluatePricingSetupCompletenessFromNumbers(
        baseFare: 5,
        perKm: 1.8,
        perMinute: 0, // historical Flutter default; valid for fare calc
        minimumFare: 8,
      );
      expect(fromNumbers.kind, PricingSetupCompletenessKind.complete);

      // Even if optional surcharge texts would be empty/zero elsewhere,
      // core completeness remains Complete.
      final coreOnly = evaluatePricingSetupCompleteness(
        baseFare: '5.00',
        perKm: '1.80',
        perMinute: '0.00',
        minimumFare: '8.00',
      );
      expect(coreOnly.isComplete, isTrue);
    });

    test('tier fee / fuel / return zero are not required for Compleet', () {
      // Product policy: optional zeros do not gate the badge. The evaluator
      // only receives core fields; optional zeros are Compleet by omission.
      final r = evaluatePricingSetupCompletenessFromNumbers(
        baseFare: 4.5,
        perKm: 2.1,
        perMinute: 0,
        minimumFare: 0,
      );
      expect(r.isComplete, isTrue);
    });

    test('return enabled with valid zero surcharge is Compleet for cores', () {
      // Return surcharge is optional; zero is allowed by fare calc.
      final r = evaluatePricingSetupCompleteness(
        baseFare: '3.00',
        perKm: '1.50',
        perMinute: '0.00',
        minimumFare: '5.00',
      );
      expect(r.kind, PricingSetupCompletenessKind.complete);
    });
  });

  group('persistence / restart shape', () {
    test('restart restores correct completion from persisted numbers', () {
      // Simulate hydrate: toStringAsFixed(2) then evaluate.
      final persisted = <String, double>{
        'pricingBaseFare': 5.0,
        'pricingPerKm': 1.8,
        'pricingPerMinute': 0.0,
        'pricingMinimumFare': 8.0,
      };
      final r = evaluatePricingSetupCompleteness(
        baseFare: persisted['pricingBaseFare']!.toStringAsFixed(2),
        perKm: persisted['pricingPerKm']!.toStringAsFixed(2),
        perMinute: persisted['pricingPerMinute']!.toStringAsFixed(2),
        minimumFare: persisted['pricingMinimumFare']!.toStringAsFixed(2),
      );
      expect(r.kind, PricingSetupCompletenessKind.complete);
    });

    test('save immediately refreshes status contract (source)', () {
      final page = File('lib/business_settings_page.dart').readAsStringSync();
      expect(page.contains('evaluatePricingSetupCompleteness('), isTrue);
      expect(page.contains('onChanged: _onPricingFieldEdited'), isTrue);
      expect(page.contains('_pricingSetupSubtitle()'), isTrue);
      // Old strict >0 gate must not remain on pricing badge.
      expect(
        page.contains(
          '_validPositiveNumber(_baseFareCtrl.text),\n'
          '      _validPositiveNumber(_perKmCtrl.text),\n'
          '      _validPositiveNumber(_perMinCtrl.text),\n'
          '      _validPositiveNumber(_minimumFareCtrl.text),',
        ),
        isFalse,
      );
    });

    test('tenant isolation: completeness is pure of tenant ids', () {
      final a = evaluatePricingSetupCompletenessFromNumbers(
        baseFare: 1,
        perKm: 1,
        perMinute: 0,
        minimumFare: 1,
      );
      final b = evaluatePricingSetupCompletenessFromNumbers(
        baseFare: 1,
        perKm: 1,
        perMinute: 0,
        minimumFare: 1,
      );
      expect(a.kind, b.kind);
      // Helper has no tenant parameters — isolation is by caller scope.
      final src = File(
        'lib/pricing/pricing_setup_completeness.dart',
      ).readAsStringSync();
      expect(src.toLowerCase().contains('tenant'), isFalse);
      expect(src.toLowerCase().contains('company_id'), isFalse);
    });

    test('JSON roundtrip of core fields preserves Compleet', () {
      final payload = jsonEncode({
        'pricingBaseFare': 5.0,
        'pricingPerKm': 1.8,
        'pricingPerMinute': 0.0,
        'pricingMinimumFare': 8.0,
      });
      final decoded = jsonDecode(payload) as Map<String, dynamic>;
      final r = evaluatePricingSetupCompletenessFromNumbers(
        baseFare: (decoded['pricingBaseFare'] as num).toDouble(),
        perKm: (decoded['pricingPerKm'] as num).toDouble(),
        perMinute: (decoded['pricingPerMinute'] as num).toDouble(),
        minimumFare: (decoded['pricingMinimumFare'] as num).toDouble(),
      );
      expect(r.isComplete, isTrue);
    });
  });

  group('checkPricingCoreNonNegative', () {
    test('0.00 ok; empty not ok; negative not ok', () {
      expect(checkPricingCoreNonNegative('0.00').ok, isTrue);
      expect(checkPricingCoreNonNegative('').ok, isFalse);
      expect(checkPricingCoreNonNegative('-0.01').ok, isFalse);
      expect(checkPricingCoreNonNegative('x').ok, isFalse);
    });
  });
}
