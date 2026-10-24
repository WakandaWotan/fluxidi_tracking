/// FARE-ROUNDING-CENTRAL-0_10-1 — Canonical Fluxidi final fare rounding policy.
///
/// This is the single source of truth for how a definitive Fluxidi ride price
/// is rounded on the Flutter side:
///
///   * ride prices are rounded to the nearest €0.10;
///   * an exact half step (€0.05) rounds UP (half-up);
///   * rounding happens EXACTLY ONCE, at definitive ride finalization, before
///     the amount is persisted / handed to any downstream surface;
///   * a value that is already finalized must never be rounded again.
///
/// All arithmetic is done in INTEGER CENTS to avoid floating-point drift.
///
/// Distinguish three concepts (do not mix them):
///   1. RAW FARE      — internal, not-yet-rounded running fare (kept precise
///                      during the ride).
///   2. DISPLAY PREVIEW — the live cockpit price; rounded to €0.10 for display
///                      only. It must never write back into the raw accumulator.
///   3. FINALIZED FARE — rounded exactly once at STOP/finalize and stored
///                      canonically; receipt, payment, booking, business
///                      invoice, Billit, Peppol and KPI read this stored value.
library;

/// Rounds a raw amount expressed in integer cents to the nearest 10 cents,
/// half-up.
///
/// Rule for positive fares: `((rawCents + 5) ~/ 10) * 10`.
///
/// Defensive behaviour:
///   * `0` stays `0`;
///   * `null` / NaN / infinite input returns `null` (never silently `0`);
///   * negative amounts (refunds/credits) are NOT treated as a new ride price
///     and return `null` so callers handle them explicitly.
int? roundFareCentsToNearestTenCents(num? rawCents) {
  if (rawCents == null) return null;
  final value = rawCents.toDouble();
  if (value.isNaN || value.isInfinite) return null;
  if (value == 0) return 0;
  if (value < 0) return null;
  final cents = value.round();
  if (cents == 0) return 0;
  return ((cents + 5) ~/ 10) * 10;
}

/// Convenience wrapper for callers that hold euros as a [double]/[num].
///
/// Converts to integer cents, applies [roundFareCentsToNearestTenCents], and
/// converts back to euros. Returns `null` for the same invalid/negative inputs
/// as the integer helper so callers never silently coerce bad data to `0`.
double? roundFareEuroToNearestTenCents(num? rawEuro) {
  if (rawEuro == null) return null;
  final value = rawEuro.toDouble();
  if (value.isNaN || value.isInfinite) return null;
  if (value == 0) return 0.0;
  if (value < 0) return null;
  final cents = (value * 100).round();
  final rounded = roundFareCentsToNearestTenCents(cents);
  if (rounded == null) return null;
  return rounded / 100.0;
}
