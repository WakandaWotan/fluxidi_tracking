// FARE-ROUNDING-PLANNED-QUOTE-0_10-1 — canonical planned-quote leg finalization.
//
// Rounds a single billable leg's DEFINITIVE incl-VAT price to the nearest €0.10
// (half-up, EXACTLY ONCE) at quote finalization, then re-derives net + VAT from
// the rounded incl-VAT amount so leg_price_incl_vat / price_ex_vat / price_vat
// are internally consistent and every downstream surface reads the same amount.
//
// This reuses the SINGLE canonical rounding policy from
// workers/shared/fluxidi_fare_rounding.mjs (no divergent second implementation).

import { roundFareCentsToNearestTenCents } from "../../shared/fluxidi_fare_rounding.mjs";

/**
 * Finalizes one billable leg's incl-VAT price to the €0.10 policy.
 *
 * @param {object} args
 * @param {number} args.rawInclVat  Raw (unrounded) leg total including VAT.
 * @param {number} [args.vatRate]   VAT rate in [0,1] (e.g. 0.06).
 * @returns {{
 *   price_incl_vat: number,
 *   price_ex_vat: number,
 *   price_vat: number,
 *   rounded: boolean,
 *   rawCents: (number|null),
 *   roundedCents: (number|null),
 * }}
 */
export function finalizeLegPricingInclVat({ rawInclVat, vatRate = 0 } = {}) {
  const raw = Number(rawInclVat);
  if (!Number.isFinite(raw) || raw <= 0) {
    return {
      price_incl_vat: 0,
      price_ex_vat: 0,
      price_vat: 0,
      rounded: false,
      rawCents: null,
      roundedCents: null,
    };
  }
  const rawCents = Math.round(raw * 100);
  const roundedCents = roundFareCentsToNearestTenCents(rawCents);
  const inclCents = roundedCents === null ? rawCents : roundedCents;
  const priceInclVat = inclCents / 100;

  const rate = Math.max(0, Math.min(1, Number(vatRate) || 0));
  let priceExVat;
  let priceVat;
  if (rate > 0) {
    // Derive net + VAT from the ROUNDED incl amount (cent precision), so
    // price_ex_vat + price_vat === price_incl_vat.
    priceExVat = Math.round((priceInclVat / (1 + rate)) * 100) / 100;
    priceVat = Math.round((priceInclVat - priceExVat) * 100) / 100;
  } else {
    priceExVat = priceInclVat;
    priceVat = 0;
  }

  return {
    price_incl_vat: priceInclVat,
    price_ex_vat: priceExVat,
    price_vat: priceVat,
    rounded: roundedCents !== null,
    rawCents,
    roundedCents: inclCents,
  };
}
