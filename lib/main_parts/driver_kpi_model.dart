/// FASE 12 — Driver KPI (performance) model + aggregation.
///
/// Pure Dart (no Flutter/UI, no I/O) so the aggregation is fully unit-testable
/// and can never introduce jank. The driver-home side fetches the canonical
/// `/trips/history` rows (already scoped to the effective driver), maps each
/// row to a [DriverKpiRideRecord] using the app's existing payment/status
/// classifiers, and hands the list to [aggregateDriverKpi].
///
/// Financial policy (IMPORTANT): the definitive Fluxidi ride price is rounded
/// to the nearest €0.10. That rounding MUST happen exactly once, in the central
/// fare-finalization step (the server-side pricing finalization that computes
/// the final ride total), BEFORE the amount is persisted. The single stored
/// final amount is then the authoritative value reused for the receipt, the
/// payment, the business/Billit invoice and all KPI/revenue totals — they all
/// read the same persisted number.
///
/// This KPI layer performs NO independent ride rounding of its own:
/// - it sums the exact stored final amounts as they were persisted;
/// - it never re-rounds a per-ride line or the running total;
/// - historical cent-precise amounts (e.g. €3.19) are preserved exactly and
///   are never coerced to a €0.10 step after the fact.
///
/// Integer-cent accumulation is used purely to keep the summation free of
/// binary floating-point drift; it recovers the exact stored cent value and is
/// not a rounding policy. A ride can contribute at most once because we dedupe
/// by canonical ride id and read from a single canonical source.
library;

/// Period selector for the KPI page.
enum DriverKpiPeriod { today, week, month }

/// Auth/scope context the KPIs were resolved under. Used for bounded
/// diagnostics only; never affects the numbers themselves.
enum DriverKpiAuthMode { driver, companyAdmin }

/// Canonical payment state buckets kept strictly separate on the KPI page.
/// "Invoice created" is NOT automatically "paid": a business invoice that is
/// still syncing/awaiting settlement is [invoiceInProcessing], not [paid].
enum DriverKpiPaymentState { paid, outstanding, invoiceInProcessing, unknown }

String driverKpiPeriodToken(DriverKpiPeriod period) {
  switch (period) {
    case DriverKpiPeriod.today:
      return 'today';
    case DriverKpiPeriod.week:
      return 'week';
    case DriverKpiPeriod.month:
      return 'month';
  }
}

String driverKpiAuthModeToken(DriverKpiAuthMode mode) {
  switch (mode) {
    case DriverKpiAuthMode.driver:
      return 'driver';
    case DriverKpiAuthMode.companyAdmin:
      return 'companyAdmin';
  }
}

/// Recovers the exact integer-cent value of a *stored* final ride amount.
///
/// This is NOT a rounding policy. The definitive €0.10 rounding happens once, in
/// the central fare-finalization layer, before the amount is persisted. Here we
/// merely convert the already-final stored euro value into cents so that sums do
/// not accumulate binary floating-point error: 3.19 → 319, 3.20 → 320. The
/// stored value is preserved exactly and never coarsened.
int fluxidiKpiStoredAmountToCents(double storedAmount) {
  if (storedAmount.isNaN || storedAmount.isInfinite) return 0;
  return (storedAmount * 100).round();
}

/// Converts accumulated integer cents back to euros for display. Exact.
double fluxidiKpiCentsToEuros(int cents) => cents / 100.0;

/// Inclusive-start / exclusive-end local time window for a period.
class DriverKpiPeriodRange {
  const DriverKpiPeriodRange({required this.start, required this.endExclusive});
  final DateTime start;
  final DateTime endExclusive;

  bool contains(DateTime moment) {
    return !moment.isBefore(start) && moment.isBefore(endExclusive);
  }
}

/// Resolves the local-time window for [period] relative to [now].
/// Week starts on Monday (ISO-8601), matching European convention.
DriverKpiPeriodRange driverKpiPeriodRange(DriverKpiPeriod period, DateTime now) {
  final startOfDay = DateTime(now.year, now.month, now.day);
  switch (period) {
    case DriverKpiPeriod.today:
      return DriverKpiPeriodRange(
        start: startOfDay,
        endExclusive: startOfDay.add(const Duration(days: 1)),
      );
    case DriverKpiPeriod.week:
      final monday = startOfDay.subtract(Duration(days: now.weekday - 1));
      return DriverKpiPeriodRange(
        start: monday,
        endExclusive: monday.add(const Duration(days: 7)),
      );
    case DriverKpiPeriod.month:
      final startOfMonth = DateTime(now.year, now.month, 1);
      final nextMonth = now.month == 12
          ? DateTime(now.year + 1, 1, 1)
          : DateTime(now.year, now.month + 1, 1);
      return DriverKpiPeriodRange(start: startOfMonth, endExclusive: nextMonth);
  }
}

/// One canonical ride, already mapped from a backend `/trips/history` row.
class DriverKpiRideRecord {
  const DriverKpiRideRecord({
    required this.rideId,
    required this.startedAt,
    required this.stoppedAt,
    required this.amountEur,
    required this.kmTotal,
    required this.isCompleted,
    required this.isCancelled,
    required this.paymentState,
  });

  /// Canonical ride/trip id used for dedupe so a ride never counts twice.
  final String rideId;
  final DateTime? startedAt;
  final DateTime? stoppedAt;

  /// Canonical backend final ride price (already the receipt amount).
  final double amountEur;
  final double? kmTotal;
  final bool isCompleted;
  final bool isCancelled;
  final DriverKpiPaymentState paymentState;

  /// Best-effort timestamp used for period bucketing.
  DateTime? get periodTimestamp => startedAt ?? stoppedAt;

  Duration? get rideDuration {
    final start = startedAt;
    final stop = stoppedAt;
    if (start == null || stop == null) return null;
    if (!stop.isAfter(start)) return null;
    return stop.difference(start);
  }
}

/// Aggregated KPI values for one period. All money values are canonical euros
/// rounded to the nearest cent.
class DriverKpiSnapshot {
  const DriverKpiSnapshot({
    required this.period,
    required this.ridesCount,
    required this.completedCount,
    required this.cancelledCount,
    required this.revenueTotal,
    required this.paidRevenue,
    required this.outstandingRevenue,
    required this.invoiceInProcessingRevenue,
    required this.kmTotal,
    required this.averageRidePrice,
    required this.averageRideDuration,
  });

  final DriverKpiPeriod period;
  final int ridesCount;
  final int completedCount;
  final int cancelledCount;
  final double revenueTotal;
  final double paidRevenue;
  final double outstandingRevenue;
  final double invoiceInProcessingRevenue;
  final double kmTotal;
  final double? averageRidePrice;
  final Duration? averageRideDuration;

  bool get hasAnyActivity => ridesCount > 0;

  static const DriverKpiSnapshot emptyToday = DriverKpiSnapshot(
    period: DriverKpiPeriod.today,
    ridesCount: 0,
    completedCount: 0,
    cancelledCount: 0,
    revenueTotal: 0,
    paidRevenue: 0,
    outstandingRevenue: 0,
    invoiceInProcessingRevenue: 0,
    kmTotal: 0,
    averageRidePrice: null,
    averageRideDuration: null,
  );
}

/// Aggregates [rides] into a [DriverKpiSnapshot] for [period] relative to [now].
///
/// Rules:
/// - Dedupe by canonical [DriverKpiRideRecord.rideId] (a ride counts once).
/// - Bucket by [DriverKpiRideRecord.periodTimestamp] into the period window.
/// - Revenue/payment/km/duration derive only from completed rides.
/// - Paid / outstanding / invoice-in-processing stay strictly separate.
DriverKpiSnapshot aggregateDriverKpi({
  required List<DriverKpiRideRecord> rides,
  required DriverKpiPeriod period,
  required DateTime now,
}) {
  final range = driverKpiPeriodRange(period, now);

  final seenIds = <String>{};
  final deduped = <DriverKpiRideRecord>[];
  for (final ride in rides) {
    final id = ride.rideId.trim();
    if (id.isEmpty) {
      // Keep id-less rows (rare) but they cannot be deduped.
      deduped.add(ride);
      continue;
    }
    if (seenIds.add(id)) deduped.add(ride);
  }

  var ridesCount = 0;
  var completedCount = 0;
  var cancelledCount = 0;
  // Revenue is accumulated in exact integer cents so summation introduces no
  // floating-point drift and never re-rounds any stored ride amount.
  var revenueCents = 0;
  var paidCents = 0;
  var outstandingCents = 0;
  var invoiceInProcessingCents = 0;
  var kmTotal = 0.0;
  var durationSum = Duration.zero;
  var durationCount = 0;

  for (final ride in deduped) {
    final stamp = ride.periodTimestamp;
    if (stamp == null || !range.contains(stamp)) continue;

    if (ride.isCancelled && !ride.isCompleted) {
      cancelledCount++;
      ridesCount++;
      continue;
    }
    if (!ride.isCompleted) continue;

    completedCount++;
    ridesCount++;

    // Sum the exact stored final amount as persisted; no per-ride rounding.
    final cents = fluxidiKpiStoredAmountToCents(ride.amountEur);
    revenueCents += cents;
    switch (ride.paymentState) {
      case DriverKpiPaymentState.paid:
        paidCents += cents;
        break;
      case DriverKpiPaymentState.outstanding:
        outstandingCents += cents;
        break;
      case DriverKpiPaymentState.invoiceInProcessing:
        invoiceInProcessingCents += cents;
        break;
      case DriverKpiPaymentState.unknown:
        break;
    }

    final km = ride.kmTotal;
    if (km != null && km.isFinite && km > 0) kmTotal += km;

    final duration = ride.rideDuration;
    if (duration != null) {
      durationSum += duration;
      durationCount++;
    }
  }

  // Average ride price is a derived statistic, not a stored ride amount, so it
  // is exposed as the exact quotient (the UI formats it for display). It never
  // feeds back into any revenue total.
  final averageRidePrice = completedCount > 0
      ? revenueCents / (100.0 * completedCount)
      : null;
  final averageRideDuration = durationCount > 0
      ? Duration(
          milliseconds: (durationSum.inMilliseconds / durationCount).round(),
        )
      : null;

  return DriverKpiSnapshot(
    period: period,
    ridesCount: ridesCount,
    completedCount: completedCount,
    cancelledCount: cancelledCount,
    revenueTotal: fluxidiKpiCentsToEuros(revenueCents),
    paidRevenue: fluxidiKpiCentsToEuros(paidCents),
    outstandingRevenue: fluxidiKpiCentsToEuros(outstandingCents),
    invoiceInProcessingRevenue: fluxidiKpiCentsToEuros(invoiceInProcessingCents),
    kmTotal: double.parse(kmTotal.toStringAsFixed(1)),
    averageRidePrice: averageRidePrice,
    averageRideDuration: averageRideDuration,
  );
}

/// A short, PII-free payment-mix summary for bounded diagnostics, e.g.
/// `paid:3/out:1/proc:0`.
String driverKpiPaymentMixToken(DriverKpiSnapshot snapshot) {
  int countBucket(double value) => value > 0 ? 1 : 0;
  // Counts are not tracked per bucket in the snapshot; expose presence flags so
  // logs never leak amounts while still signalling which buckets are non-zero.
  return 'paid:${countBucket(snapshot.paidRevenue)}'
      '/out:${countBucket(snapshot.outstandingRevenue)}'
      '/proc:${countBucket(snapshot.invoiceInProcessingRevenue)}';
}
