/**
 * RateHawk booking-intent adapter (P3A).
 *
 * Production authority must be durable and injected. Module-global
 * memory is never the production store. No Cloudflare resource is
 * created here: if a store is missing, hotel booking fails closed.
 *
 * Schema (ratehawk_booking_intent_v1):
 *   booking_attempt_id, revision, state, accepted_ref_fingerprint,
 *   hid, checkin, checkout, terms_revision, payment_type, locale,
 *   guest_fields_complete, payment_token_present, finish_submitted_at,
 *   finish_transport_calls, status_poll_count, confirmation_unknown_reason,
 *   provider_order_id, provider_evidence_kind, created_at, updated_at
 *
 * Never persist PAN/CVC, guest PII, hashes, raw payloads, or secrets.
 */

import { sha256Hex } from "./crypto_utils.js";
import {
  RATEHAWK_BOOKING_ATTEMPT_PREFIX,
  RATEHAWK_BOOKING_INTENT_SCHEMA,
  RATEHAWK_BOOKING_STATES,
} from "./ratehawk_booking_contract.mjs";

function _text(value, max = 200) {
  const text = String(value ?? "").trim();
  if (!text) return "";
  return text.length > max ? text.slice(0, max) : text;
}

export async function fingerprintAcceptedRef(token) {
  const text = _text(token, 4000);
  if (!text) return "";
  return sha256Hex(`rha1:${text}`);
}

export async function deriveRatehawkBookingAttemptId(acceptedRef) {
  const fingerprint = await fingerprintAcceptedRef(acceptedRef);
  if (!fingerprint) return "";
  return `${RATEHAWK_BOOKING_ATTEMPT_PREFIX}.${fingerprint.slice(0, 32)}`;
}

export function createMemoryRatehawkBookingIntentStore() {
  const data = new Map();
  return {
    kind: "memory_test_adapter",
    async get(id) {
      const key = _text(id, 120);
      if (!key || !data.has(key)) return null;
      return JSON.parse(JSON.stringify(data.get(key)));
    },
    async put(record) {
      const key = _text(record?.booking_attempt_id, 120);
      if (!key) return { ok: false, reason: "booking_attempt_id_required" };
      data.set(key, JSON.parse(JSON.stringify(record)));
      return { ok: true, record: JSON.parse(JSON.stringify(record)) };
    },
    async compareAndSwap(id, expectedRevision, nextRecord) {
      const key = _text(id, 120);
      const current = key && data.has(key) ? data.get(key) : null;
      const currentRev = current == null ? null : Number(current.revision);
      if (currentRev !== expectedRevision) {
        return { ok: false, reason: "revision_conflict", record: current };
      }
      data.set(key, JSON.parse(JSON.stringify(nextRecord)));
      return { ok: true, record: JSON.parse(JSON.stringify(nextRecord)) };
    },
  };
}

export function resolveRatehawkBookingIntentStore(env = {}, injected = null) {
  if (injected && typeof injected.get === "function" && typeof injected.put === "function") {
    return { ok: true, store: injected, source: "injected" };
  }
  const binding = env?.RATEHAWK_BOOKING_INTENT_STORE;
  if (binding && typeof binding.get === "function" && typeof binding.put === "function") {
    return { ok: true, store: binding, source: "env" };
  }
  return {
    ok: false,
    store: null,
    source: null,
    reason: "booking_intent_store_unconfigured",
  };
}

export function emptyRatehawkBookingIntent({
  bookingAttemptId,
  acceptedRefFingerprint,
  hid,
  checkin,
  checkout,
  termsRevision,
  paymentType,
  locale,
  now = Date.now(),
} = {}) {
  return {
    schema: RATEHAWK_BOOKING_INTENT_SCHEMA,
    booking_attempt_id: bookingAttemptId,
    revision: 0,
    state: RATEHAWK_BOOKING_STATES.ACCEPTED_PREBOOK,
    accepted_ref_fingerprint: acceptedRefFingerprint,
    hid: hid ?? null,
    checkin: checkin ?? null,
    checkout: checkout ?? null,
    terms_revision: termsRevision ?? null,
    payment_type: paymentType ?? null,
    locale: locale || "nl",
    guest_fields_complete: false,
    payment_token_present: false,
    finish_submitted_at: null,
    finish_transport_calls: 0,
    status_poll_count: 0,
    confirmation_unknown_reason: null,
    provider_order_id: null,
    provider_evidence_kind: null,
    created_at: Number(now),
    updated_at: Number(now),
  };
}
