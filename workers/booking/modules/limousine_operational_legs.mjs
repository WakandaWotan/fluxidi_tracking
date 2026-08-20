// LIMOUSINE-MARKETPLACE-P2C2 — per-leg allocation for Limousine operational legs.
//
// Completes the P2C1 deferral: an outbound and a return operational leg each
// carry their OWN authoritative components and amounts, and the two leg totals
// reconcile EXACTLY with the single-rounded booking total.
//
// Allocation rules:
//   * journey components go to their own leg;
//   * mobilisation outbound/return each appear exactly once, on their own leg;
//   * non-leg components (paid extras) are allocated to the outbound leg;
//   * the €0.10 rounding delta between the component sum and the single-rounded
//     customer total is applied once, to the outbound leg, so
//     outbound + return === booking total to the cent.

import { LIMOUSINE_COMPONENT_TYPES } from "./limousine_booking.mjs";

const RETURN_COMPONENT_TYPES = new Set([
  LIMOUSINE_COMPONENT_TYPES.RETURN_JOURNEY,
  LIMOUSINE_COMPONENT_TYPES.MOBILISATION_RETURN,
]);

function toInt(value) {
  const n = Number(value);
  return Number.isFinite(n) ? Math.trunc(n) : 0;
}

function splitVat(inclCents, vatRate) {
  const rate = Math.max(0, Math.min(1, Number(vatRate) || 0));
  const incl = toInt(inclCents);
  if (rate <= 0) return { incl_cents: incl, ex_cents: incl, vat_cents: 0 };
  const ex = Math.round(incl / (1 + rate));
  return { incl_cents: incl, ex_cents: ex, vat_cents: incl - ex };
}

/// Allocates a composed Limousine total into outbound/return operational legs.
/// Returns cents plus euro amounts ready for `_buildOperationalLegRecord`.
export function allocateLimousineOperationalLegs(total) {
  const t = total && typeof total === "object" ? total : {};
  const components = Array.isArray(t.components) ? t.components : [];
  const vatRate = Number(t.vat_rate) || 0;

  const outboundComponents = [];
  const returnComponents = [];
  for (const c of components) {
    if (RETURN_COMPONENT_TYPES.has(c?.type)) returnComponents.push(c);
    else outboundComponents.push(c);
  }

  const hasReturn = returnComponents.length > 0;
  const returnRaw = returnComponents.reduce((sum, c) => sum + toInt(c.amount_cents), 0);
  const componentSum = components.reduce((sum, c) => sum + toInt(c.amount_cents), 0);

  // The authoritative customer total is the single-rounded figure. Any €0.10
  // rounding delta is absorbed by the outbound leg so the legs reconcile.
  const bookingTotalCents = toInt(
    t.total_incl_vat_cents != null
      ? t.total_incl_vat_cents
      : Math.round((Number(t.price_incl_vat) || 0) * 100),
  );
  const roundingDeltaCents = bookingTotalCents - componentSum;
  const outboundCents = bookingTotalCents - (hasReturn ? returnRaw : 0);

  const outbound = splitVat(outboundCents, vatRate);
  const ret = hasReturn ? splitVat(returnRaw, vatRate) : null;

  return {
    has_return_leg: hasReturn,
    booking_total_cents: bookingTotalCents,
    component_sum_cents: componentSum,
    rounding_delta_cents: roundingDeltaCents,
    outbound: {
      components: outboundComponents,
      ...outbound,
      price_incl_vat: outbound.incl_cents / 100,
      price_ex_vat: outbound.ex_cents / 100,
      price_vat: outbound.vat_cents / 100,
    },
    ...(hasReturn
      ? {
          return: {
            components: returnComponents,
            ...ret,
            price_incl_vat: ret.incl_cents / 100,
            price_ex_vat: ret.ex_cents / 100,
            price_vat: ret.vat_cents / 100,
          },
        }
      : {}),
  };
}

/// Reconciliation proof: outbound + return must equal the booking total, and
/// each mobilisation direction may appear at most once across all legs.
export function limousineLegsReconcile(allocation) {
  const a = allocation && typeof allocation === "object" ? allocation : {};
  const outbound = toInt(a.outbound?.incl_cents);
  const ret = toInt(a.return?.incl_cents);
  const total = toInt(a.booking_total_cents);
  const sumMatches = outbound + ret === total;

  const allComponents = [
    ...(Array.isArray(a.outbound?.components) ? a.outbound.components : []),
    ...(Array.isArray(a.return?.components) ? a.return.components : []),
  ];
  const countOf = (type) => allComponents.filter((c) => c?.type === type).length;
  const mobilisationOk =
    countOf(LIMOUSINE_COMPONENT_TYPES.MOBILISATION_OUTBOUND) <= 1 &&
    countOf(LIMOUSINE_COMPONENT_TYPES.MOBILISATION_RETURN) <= 1;

  return {
    ok: sumMatches && mobilisationOk,
    sum_matches: sumMatches,
    mobilisation_not_duplicated: mobilisationOk,
    outbound_cents: outbound,
    return_cents: ret,
    booking_total_cents: total,
  };
}
