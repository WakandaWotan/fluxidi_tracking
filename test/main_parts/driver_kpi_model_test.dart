import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/main_parts/driver_kpi_model.dart';

DriverKpiRideRecord _ride({
  required String id,
  required DateTime started,
  DateTime? stopped,
  double amount = 10.0,
  double? km,
  bool completed = true,
  bool cancelled = false,
  DriverKpiPaymentState payment = DriverKpiPaymentState.paid,
}) {
  return DriverKpiRideRecord(
    rideId: id,
    startedAt: started,
    stoppedAt: stopped ?? started.add(const Duration(minutes: 20)),
    amountEur: amount,
    kmTotal: km,
    isCompleted: completed,
    isCancelled: cancelled,
    paymentState: payment,
  );
}

void main() {
  // Saturday 2026-07-18 → ISO week Mon 2026-07-13 .. Sun 2026-07-19.
  final now = DateTime(2026, 7, 18, 15, 0);

  group('FASE12 driver KPI period ranges', () {
    test('today window is the local calendar day', () {
      final range = driverKpiPeriodRange(DriverKpiPeriod.today, now);
      expect(range.start, DateTime(2026, 7, 18));
      expect(range.endExclusive, DateTime(2026, 7, 19));
    });

    test('week window starts Monday (ISO-8601)', () {
      final range = driverKpiPeriodRange(DriverKpiPeriod.week, now);
      expect(range.start, DateTime(2026, 7, 13));
      expect(range.endExclusive, DateTime(2026, 7, 20));
    });

    test('month window spans the calendar month', () {
      final range = driverKpiPeriodRange(DriverKpiPeriod.month, now);
      expect(range.start, DateTime(2026, 7, 1));
      expect(range.endExclusive, DateTime(2026, 8, 1));
    });

    test('month window rolls over the year in December', () {
      final dec = DateTime(2026, 12, 20, 12);
      final range = driverKpiPeriodRange(DriverKpiPeriod.month, dec);
      expect(range.start, DateTime(2026, 12, 1));
      expect(range.endExclusive, DateTime(2027, 1, 1));
    });
  });

  group('FASE12 driver KPI aggregation', () {
    test('today/week/month load the correct period totals', () {
      final rides = <DriverKpiRideRecord>[
        _ride(
          id: 'a',
          started: DateTime(2026, 7, 18, 9),
          stopped: DateTime(2026, 7, 18, 9, 30),
          amount: 10.0,
          km: 5,
          payment: DriverKpiPaymentState.paid,
        ),
        _ride(
          id: 'b',
          started: DateTime(2026, 7, 18, 10),
          stopped: DateTime(2026, 7, 18, 10, 20),
          amount: 20.04,
          payment: DriverKpiPaymentState.outstanding,
        ),
        _ride(
          id: 'c',
          started: DateTime(2026, 7, 15, 8),
          amount: 30.0,
          payment: DriverKpiPaymentState.invoiceInProcessing,
        ),
        _ride(
          id: 'd',
          started: DateTime(2026, 7, 5, 8),
          amount: 40.0,
          payment: DriverKpiPaymentState.paid,
        ),
        _ride(
          id: 'e',
          started: DateTime(2026, 6, 30, 8),
          amount: 99.0,
          payment: DriverKpiPaymentState.paid,
        ),
      ];

      final today = aggregateDriverKpi(
        rides: rides,
        period: DriverKpiPeriod.today,
        now: now,
      );
      expect(today.completedCount, 2);
      expect(today.revenueTotal, 30.04);

      final week = aggregateDriverKpi(
        rides: rides,
        period: DriverKpiPeriod.week,
        now: now,
      );
      expect(week.completedCount, 3);
      expect(week.revenueTotal, 60.04);

      final month = aggregateDriverKpi(
        rides: rides,
        period: DriverKpiPeriod.month,
        now: now,
      );
      expect(month.completedCount, 4);
      expect(month.revenueTotal, 100.04);
    });

    test('a street ride with a linked booking is never double-counted', () {
      final rides = <DriverKpiRideRecord>[
        _ride(id: 'street-1', started: DateTime(2026, 7, 18, 9), amount: 12.5),
        // Same canonical ride id arriving again (e.g. booking + street row).
        _ride(id: 'street-1', started: DateTime(2026, 7, 18, 9), amount: 999.0),
      ];
      final snap = aggregateDriverKpi(
        rides: rides,
        period: DriverKpiPeriod.today,
        now: now,
      );
      expect(snap.completedCount, 1);
      expect(snap.ridesCount, 1);
      expect(snap.revenueTotal, 12.5);
    });

    test('paid / outstanding / invoice-in-processing stay separate', () {
      final rides = <DriverKpiRideRecord>[
        _ride(
          id: 'p',
          started: DateTime(2026, 7, 18, 9),
          amount: 10.0,
          payment: DriverKpiPaymentState.paid,
        ),
        _ride(
          id: 'o',
          started: DateTime(2026, 7, 18, 10),
          amount: 20.0,
          payment: DriverKpiPaymentState.outstanding,
        ),
        _ride(
          id: 'i',
          started: DateTime(2026, 7, 18, 11),
          amount: 30.0,
          payment: DriverKpiPaymentState.invoiceInProcessing,
        ),
        _ride(
          id: 'u',
          started: DateTime(2026, 7, 18, 12),
          amount: 5.0,
          payment: DriverKpiPaymentState.unknown,
        ),
      ];
      final snap = aggregateDriverKpi(
        rides: rides,
        period: DriverKpiPeriod.today,
        now: now,
      );
      expect(snap.paidRevenue, 10.0);
      expect(snap.outstandingRevenue, 20.0);
      expect(snap.invoiceInProcessingRevenue, 30.0);
      // Unknown contributes to total but not to any distinct bucket.
      expect(snap.revenueTotal, 65.0);
    });

    test('completed and cancelled rides are counted separately', () {
      final rides = <DriverKpiRideRecord>[
        _ride(id: 'ok', started: DateTime(2026, 7, 18, 9)),
        _ride(
          id: 'cx',
          started: DateTime(2026, 7, 18, 10),
          amount: 50.0,
          completed: false,
          cancelled: true,
        ),
      ];
      final snap = aggregateDriverKpi(
        rides: rides,
        period: DriverKpiPeriod.today,
        now: now,
      );
      expect(snap.completedCount, 1);
      expect(snap.cancelledCount, 1);
      expect(snap.ridesCount, 2);
      // Cancelled rides never contribute revenue.
      expect(snap.revenueTotal, 10.0);
    });

    test('averages use canonical amounts and durations', () {
      final rides = <DriverKpiRideRecord>[
        _ride(
          id: 'a',
          started: DateTime(2026, 7, 18, 9),
          stopped: DateTime(2026, 7, 18, 9, 30),
          amount: 10.0,
        ),
        _ride(
          id: 'b',
          started: DateTime(2026, 7, 18, 10),
          stopped: DateTime(2026, 7, 18, 10, 20),
          amount: 20.0,
        ),
      ];
      final snap = aggregateDriverKpi(
        rides: rides,
        period: DriverKpiPeriod.today,
        now: now,
      );
      expect(snap.averageRidePrice, 15.0);
      expect(snap.averageRideDuration, const Duration(minutes: 25));
    });

    test('empty ride list yields a zeroed snapshot', () {
      final snap = aggregateDriverKpi(
        rides: const [],
        period: DriverKpiPeriod.today,
        now: now,
      );
      expect(snap.hasAnyActivity, isFalse);
      expect(snap.revenueTotal, 0.0);
      expect(snap.averageRidePrice, isNull);
      expect(snap.averageRideDuration, isNull);
    });
  });

  group('FASE12 KPI never re-rounds stored final amounts', () {
    test('a stored €3.20 final amount stays €3.20', () {
      final snap = aggregateDriverKpi(
        rides: [_ride(id: '1', started: DateTime(2026, 7, 18, 9), amount: 3.20)],
        period: DriverKpiPeriod.today,
        now: now,
      );
      expect(snap.revenueTotal, 3.20);
    });

    test('a historical cent-precise €3.19 is preserved, not coerced to €3.20',
        () {
      final snap = aggregateDriverKpi(
        rides: [_ride(id: '1', started: DateTime(2026, 7, 18, 9), amount: 3.19)],
        period: DriverKpiPeriod.today,
        now: now,
      );
      // Must NOT be re-rounded to a €0.10 step after the fact.
      expect(snap.revenueTotal, 3.19);
      expect(snap.revenueTotal, isNot(3.20));
    });

    test('KPI revenue equals the plain sum of the stored receipt/payment amounts',
        () {
      // Mixed stored amounts as they would appear on receipts/payment records:
      // some already on the €0.10 step, some historical cent-precise values.
      final storedAmounts = <double>[3.20, 3.19, 12.50, 0.01, 40.00];
      final rides = <DriverKpiRideRecord>[
        for (var i = 0; i < storedAmounts.length; i++)
          _ride(
            id: 'r$i',
            started: DateTime(2026, 7, 18, 9 + i),
            amount: storedAmounts[i],
          ),
      ];

      // The canonical "receipt/payment" total is the exact sum in cents.
      final receiptTotalCents = storedAmounts
          .map((a) => (a * 100).round())
          .reduce((a, b) => a + b);
      final snap = aggregateDriverKpi(
        rides: rides,
        period: DriverKpiPeriod.today,
        now: now,
      );
      expect((snap.revenueTotal * 100).round(), receiptTotalCents);
      expect((snap.paidRevenue * 100).round(), receiptTotalCents);
    });

    test('no cumulative or double rounding across many .x9 amounts', () {
      // Ten stored €3.19 rides must total exactly €31.90 — never €32.00 and
      // never drifting with floating-point error.
      final rides = <DriverKpiRideRecord>[
        for (var i = 0; i < 10; i++)
          _ride(id: 'r$i', started: DateTime(2026, 7, 18, 8), amount: 3.19),
      ];
      final snap = aggregateDriverKpi(
        rides: rides,
        period: DriverKpiPeriod.today,
        now: now,
      );
      expect(snap.revenueTotal, 31.90);
      expect((snap.revenueTotal * 100).round(), 3190);
    });

    test('stored-amount to cents recovers exact values without coarsening', () {
      expect(fluxidiKpiStoredAmountToCents(3.19), 319);
      expect(fluxidiKpiStoredAmountToCents(3.20), 320);
      expect(fluxidiKpiStoredAmountToCents(0.01), 1);
      expect(fluxidiKpiCentsToEuros(319), 3.19);
    });
  });
}
