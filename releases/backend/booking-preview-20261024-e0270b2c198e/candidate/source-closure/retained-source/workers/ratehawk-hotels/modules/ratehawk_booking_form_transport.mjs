/**
 * Injectable RateHawk booking-form transport (P3A).
 *
 * Live POST /api/b2b/v3/hotel/order/booking/form/ is not authorized.
 * Official request fields remain unresolved. Injected mocks may return
 * allowlisted requirement kinds only.
 */

import {
  RATEHAWK_BOOKING_FORM_PATH,
  RATEHAWK_BOOKING_FORM_REQUIREMENT_KINDS,
  RATEHAWK_BOOKING_UNRESOLVED_PROVIDER_FIELDS,
} from "./ratehawk_booking_contract.mjs";

function _text(value, max = 80) {
  const text = String(value ?? "").trim();
  if (!text) return "";
  return text.length > max ? text.slice(0, max) : text;
}

export function createMockRatehawkBookingFormTransport({
  requirements = [],
  reason = null,
  ok = true,
} = {}) {
  const state = { calls: 0, hashes: [], bodies: [] };
  return {
    state,
    formTransport: async ({ bookHash = null, matchHash = null, body = null } = {}) => {
      state.calls += 1;
      state.hashes.push({
        book_hash_present: Boolean(bookHash),
        match_hash_present: Boolean(matchHash),
      });
      state.bodies.push(body);
      if (ok !== true) {
        return {
          ok: false,
          invoked: true,
          reason: reason || "booking_form_unavailable",
          path: RATEHAWK_BOOKING_FORM_PATH,
          requirements: [],
          unresolved_provider_fields:
            RATEHAWK_BOOKING_UNRESOLVED_PROVIDER_FIELDS.form_request,
        };
      }
      return {
        ok: true,
        invoked: true,
        reason: null,
        path: RATEHAWK_BOOKING_FORM_PATH,
        requirements,
        unresolved_provider_fields:
          RATEHAWK_BOOKING_UNRESOLVED_PROVIDER_FIELDS.form_request,
      };
    },
  };
}

export function normalizeRatehawkBookingFormRequirements(rawRequirements) {
  const list = Array.isArray(rawRequirements) ? rawRequirements : [];
  const normalized = [];
  for (const row of list) {
    const kind = _text(row?.kind || row?.id, 64);
    if (!RATEHAWK_BOOKING_FORM_REQUIREMENT_KINDS.includes(kind)) {
      return {
        ok: false,
        reason: "unknown_form_requirement",
        unknown_requirement: kind || null,
        requirements: [],
      };
    }
    normalized.push({
      id: kind,
      kind,
      required: row?.required !== false,
      source: "assumed_until_official_form_contract",
    });
  }
  return { ok: true, reason: null, requirements: normalized };
}

export async function fetchRatehawkBookingForm({
  formTransport = null,
  bookHash = null,
  matchHash = null,
} = {}) {
  if (typeof formTransport !== "function") {
    return {
      ok: false,
      invoked: false,
      reason: "live_booking_transport_forbidden",
      path: RATEHAWK_BOOKING_FORM_PATH,
      requirements: [],
      unresolved_provider_fields:
        RATEHAWK_BOOKING_UNRESOLVED_PROVIDER_FIELDS.form_request,
    };
  }
  const raw = await formTransport({
    bookHash,
    matchHash,
    path: RATEHAWK_BOOKING_FORM_PATH,
  });
  if (!raw || raw.ok !== true) {
    return {
      ok: false,
      invoked: raw?.invoked === true,
      reason: raw?.reason || "booking_form_unavailable",
      path: RATEHAWK_BOOKING_FORM_PATH,
      requirements: [],
      unresolved_provider_fields:
        RATEHAWK_BOOKING_UNRESOLVED_PROVIDER_FIELDS.form_request,
    };
  }
  const normalized = normalizeRatehawkBookingFormRequirements(raw.requirements);
  if (normalized.ok !== true) {
    return {
      ok: false,
      invoked: true,
      reason: normalized.reason,
      unknown_requirement: normalized.unknown_requirement,
      path: RATEHAWK_BOOKING_FORM_PATH,
      requirements: [],
      unresolved_provider_fields:
        RATEHAWK_BOOKING_UNRESOLVED_PROVIDER_FIELDS.form_request,
    };
  }
  return {
    ok: true,
    invoked: true,
    reason: null,
    path: RATEHAWK_BOOKING_FORM_PATH,
    requirements: normalized.requirements,
    unresolved_provider_fields:
      RATEHAWK_BOOKING_UNRESOLVED_PROVIDER_FIELDS.form_request,
  };
}
