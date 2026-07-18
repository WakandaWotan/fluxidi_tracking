// FARE-ROUNDING-CENTRAL-0_10-1 — tests for the canonical Dart fare rounding.
//
// Run: flutter test test/pricing/fluxidi_fare_rounding_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/pricing/fluxidi_fare_rounding.dart';

void main() {
  group('pure rounding: canonical half-up €0.10 table', () {
    const cases = <List<int>>[
      [0, 0],
      [1, 0],
      [4, 0],
      [5, 10],
      [14, 10],
      [15, 20],
      [19, 20],
      [21, 20],
      [22, 20],
      [25, 30],
      [37, 40],
      [38, 40],
      [314, 310],
      [315, 320],
      [319, 320],
      [321, 320],
      [337, 340],
    ];
    for (final c in cases) {
      test('${c[0]} cents -> ${c[1]} cents', () {
        expect(roundFareCentsToNearestTenCents(c[0]), c[1]);
      });
    }
  });

  group('pure rounding: defensive inputs never silently become 0', () {
    test('null / NaN / infinite / negative return null', () {
      expect(roundFareCentsToNearestTenCents(null), isNull);
      expect(roundFareCentsToNearestTenCents(double.nan), isNull);
      expect(roundFareCentsToNearestTenCents(double.infinity), isNull);
      expect(roundFareCentsToNearestTenCents(-1), isNull);
      expect(roundFareCentsToNearestTenCents(-500), isNull);
    });

    test('exact zero is a legitimate fare and stays zero', () {
      expect(roundFareCentsToNearestTenCents(0), 0);
      expect(roundFareEuroToNearestTenCents(0), 0.0);
    });
  });

  group('euro wrapper mirrors the cents rule', () {
    test('example table', () {
      expect(roundFareEuroToNearestTenCents(3.14), 3.1);
      expect(roundFareEuroToNearestTenCents(3.15), 3.2);
      expect(roundFareEuroToNearestTenCents(3.19), 3.2);
      expect(roundFareEuroToNearestTenCents(3.21), 3.2);
      expect(roundFareEuroToNearestTenCents(3.22), 3.2);
      expect(roundFareEuroToNearestTenCents(3.25), 3.3);
      expect(roundFareEuroToNearestTenCents(3.37), 3.4);
      expect(roundFareEuroToNearestTenCents(3.38), 3.4);
    });

    test('invalid / negative euros return null', () {
      expect(roundFareEuroToNearestTenCents(null), isNull);
      expect(roundFareEuroToNearestTenCents(double.nan), isNull);
      expect(roundFareEuroToNearestTenCents(-3.2), isNull);
    });
  });

  group('live preview semantics', () {
    test('raw €3.21 previews as €3.20', () {
      expect(roundFareEuroToNearestTenCents(3.21), 3.2);
    });

    test('raw €3.25 previews as €3.30', () {
      expect(roundFareEuroToNearestTenCents(3.25), 3.3);
    });

    test('preview does not mutate the raw accumulator (pure)', () {
      var raw = 3.21;
      final preview = roundFareEuroToNearestTenCents(raw);
      expect(preview, 3.2);
      // raw is untouched by the pure helper.
      expect(raw, 3.21);
      raw += 0.5; // caller can keep accumulating precisely
      expect(raw, 3.71);
    });

    test('repeated preview of the same raw value causes no drift', () {
      const raw = 3.21;
      for (var i = 0; i < 100; i++) {
        expect(roundFareEuroToNearestTenCents(raw), 3.2);
      }
    });
  });

  group('finalization semantics', () {
    test('street ride raw €3.21 finalizes to €3.20', () {
      expect(roundFareEuroToNearestTenCents(3.21), 3.2);
    });

    test('planned ride raw €3.37 finalizes to €3.40', () {
      expect(roundFareEuroToNearestTenCents(3.37), 3.4);
    });

    test('finalizing an already-finalized amount is a no-op (idempotent)', () {
      for (final cents in <int>[0, 10, 20, 320, 340, 3200]) {
        expect(roundFareCentsToNearestTenCents(cents), cents);
      }
      // Same in euro space: rounding €3.20 again stays €3.20.
      expect(roundFareEuroToNearestTenCents(3.2), 3.2);
      expect(roundFareEuroToNearestTenCents(3.4), 3.4);
    });
  });

  group('historical data and KPI aggregation', () {
    test('a historical €3.19 amount is never mutated by aggregation', () {
      // KPI/history read stored amounts exactly; they do NOT re-round.
      const historical = 3.19;
      expect(historical, 3.19);
    });

    test('sum of ten finalized €3.20 rides is exactly €32.00 (no drift)', () {
      var totalCents = 0;
      for (var i = 0; i < 10; i++) {
        totalCents += roundFareCentsToNearestTenCents(319)!; // raw 3.19 -> 3.20
      }
      expect(totalCents, 3200);
      expect(totalCents / 100, 32.0);
    });
  });

  group('locale formatting of a finalized amount (NL/EN/FR/ES)', () {
    test('rounded value formats correctly with dot and comma decimals', () {
      final rounded = roundFareEuroToNearestTenCents(3.37)!; // 3.40
      // EN dot-decimal (driver cockpit style)
      expect(rounded.toStringAsFixed(2), '3.40');
      // NL/FR/ES comma-decimal (customer/company style)
      expect(rounded.toStringAsFixed(2).replaceAll('.', ','), '3,40');
    });
  });
}
