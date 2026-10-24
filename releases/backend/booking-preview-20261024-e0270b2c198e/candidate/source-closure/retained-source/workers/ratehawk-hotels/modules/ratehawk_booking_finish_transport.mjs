/**
 * Injectable RateHawk finish transport (P3A).
 *
 * Live POST /api/b2b/v3/hotel/order/booking/finish/ is not authorized.
 * Callers must persist the attempt before invoking the mock. This
 * module never retries and never logs payment tokens or guest data.
 */

import {
  RATEHAWK_BOOKING_FINISH_PATH,
  RATEHAWK_BOOKING_UNRESOLVED_PROVIDER_FIELDS,
} from "./ratehawk_booking_contract.mjs";

export function createMockRatehawkBookingFinishTransport({
  outcome = "confirmed",
  providerOrderId = "RH-TEST-ORDER-1",
  evidenceKind = "finish_status",
} = {}) {
  const state = { calls: 0, intents: [] };
  return {
    state,
    finishTransport: async ({ bookingAttemptId = null } = {}) => {
      state.calls += 1;
      state.intents.push(bookingAttemptId);
      if (outcome === "timeout") {
        return {
          ok: false,
          invoked: true,
          ambiguous: true,
          reason: "finish_timeout",
          path: RATEHAWK_BOOKING_FINISH_PATH,
          provider_order_id: null,
          provider_evidence_kind: null,
        };
      }
      if (outcome === "ambiguous") {
        return {
          ok: false,
          invoked: true,
          ambiguous: true,
          reason: "finish_ambiguous",
          path: RATEHAWK_BOOKING_FINISH_PATH,
          provider_order_id: null,
          provider_evidence_kind: null,
        };
      }
      if (outcome === "pending") {
        return {
          ok: true,
          invoked: true,
          pending: true,
          reason: null,
          path: RATEHAWK_BOOKING_FINISH_PATH,
          provider_order_id: null,
          provider_evidence_kind: null,
        };
      }
      if (outcome === "declined") {
        return {
          ok: false,
          invoked: true,
          declined: true,
          reason: "provider_declined",
          path: RATEHAWK_BOOKING_FINISH_PATH,
          provider_order_id: null,
          provider_evidence_kind: evidenceKind,
        };
      }
      return {
        ok: true,
        invoked: true,
        reason: null,
        path: RATEHAWK_BOOKING_FINISH_PATH,
        provider_order_id: providerOrderId,
        provider_evidence_kind: evidenceKind,
      };
    },
  };
}

export async function fetchRatehawkBookingFinish({
  finishTransport = null,
  bookingAttemptId = null,
} = {}) {
  if (typeof finishTransport !== "function") {
    return {
      ok: false,
      invoked: false,
      reason: "live_booking_transport_forbidden",
      path: RATEHAWK_BOOKING_FINISH_PATH,
      unresolved_provider_fields:
        RATEHAWK_BOOKING_UNRESOLVED_PROVIDER_FIELDS.finish_request,
    };
  }
  const raw = await finishTransport({
    bookingAttemptId,
    path: RATEHAWK_BOOKING_FINISH_PATH,
  });
  return {
    ok: raw?.ok === true,
    invoked: raw?.invoked === true,
    ambiguous: raw?.ambiguous === true,
    declined: raw?.declined === true,
    pending: raw?.pending === true,
    reason: raw?.reason || (raw?.ok === true ? null : "finish_unavailable"),
    path: RATEHAWK_BOOKING_FINISH_PATH,
    provider_order_id: raw?.provider_order_id || null,
    provider_evidence_kind: raw?.provider_evidence_kind || null,
    unresolved_provider_fields:
      RATEHAWK_BOOKING_UNRESOLVED_PROVIDER_FIELDS.finish_request,
  };
}
