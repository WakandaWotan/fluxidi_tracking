// FARE-ROUNDING-CENTRAL-0_10-1 — Canonical Fluxidi final fare rounding policy.
//
// This is the single source of truth for how a definitive Fluxidi ride price
// is rounded on the worker side:
//
//   * ride prices are rounded to the nearest €0.10;
//   * an exact half step (€0.05) rounds UP (half-up);
//   * rounding happens EXACTLY ONCE, at definitive ride finalization, before
//     the amount is persisted / handed to any downstream surface;
//   * a value that is already finalized must never be rounded again.
//
// All arithmetic is done in INTEGER CENTS to avoid floating-point drift.
//
// Distinguish RAW FARE (internal, precise), DISPLAY PREVIEW (live, rounded for
// display only, never written back) and FINALIZED FARE (rounded once, stored
// canonically; receipt, payment, booking, invoice, Billit, Peppol and KPI all
// read this stored value).

/**
 * Rounds a raw amount in integer cents to the nearest 10 cents, half-up.
 *
 * Rule for positive fares: `Math.floor((rawCents + 5) / 10) * 10`.
 *
 * Defensive behaviour:
 *   - 0 stays 0;
 *   - null / undefined / NaN / Infinity returns null (never silently 0);
 *   - negative amounts (refunds/credits) are NOT treated as a new ride price
 *     and return null so callers handle them explicitly.
 *
 * @param {number|null|undefined} rawCents
 * @returns {number|null} rounded cents (multiple of 10), 0, or null.
 */
export function roundFareCentsToNearestTenCents(rawCents) {
  if (rawCents === null || rawCents === undefined) return null;
  const value = Number(rawCents);
  if (!Number.isFinite(value)) return null;
  if (value === 0) return 0;
  if (value < 0) return null;
  const cents = Math.round(value);
  if (cents === 0) return 0;
  return Math.floor((cents + 5) / 10) * 10;
}

/**
 * Convenience wrapper for callers that hold euros as a float.
 *
 * Converts to integer cents, applies {@link roundFareCentsToNearestTenCents},
 * and converts back to euros. Returns null for the same invalid/negative inputs
 * as the integer helper so callers never silently coerce bad data to 0.
 *
 * @param {number|null|undefined} rawEuro
 * @returns {number|null} rounded euros (multiple of 0.10), 0, or null.
 */
export function roundFareEuroToNearestTenCents(rawEuro) {
  if (rawEuro === null || rawEuro === undefined) return null;
  const value = Number(rawEuro);
  if (!Number.isFinite(value)) return null;
  if (value === 0) return 0;
  if (value < 0) return null;
  const cents = Math.round(value * 100);
  const rounded = roundFareCentsToNearestTenCents(cents);
  if (rounded === null) return null;
  return rounded / 100;
}
