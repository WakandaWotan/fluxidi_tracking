// STREET-RIDE-DURABLE-COMPLETION-2 — handler-level integration tests for
// /trip/reconcile-direct-booking driven through the worker's default.fetch with
// an in-memory KV and a fake booking-worker service binding.
//
// Run: node --test workers/tracking/direct_booking_reconcile_handler.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import worker from "./fluxidi_tracking_api_worker_V2_1_with_route_index.js";

const ADMIN = "test-admin-token";
const scope = { tenant_id: "T1", company_id: "C1" };
const TRIP_KEY = "tenant:T1:company:C1:trip:trip_abc";

function makeKV(seed = {}) {
  const store = new Map(Object.entries(seed));
  return {
    store,
    async get(key) {
      return store.has(key) ? store.get(key) : null;
    },
    async put(key, val) {
      store.set(key, val);
    },
    async delete(key) {
      store.delete(key);
    },
    async list() {
      return { keys: [...store.keys()].map((name) => ({ name })), list_complete: true };
    },
  };
}

function seedTrip(over = {}) {
  return JSON.stringify({
    trip_id: "trip_abc",
    kind: "direct",
    source: "street_ride",
    tenant_id: "T1",
    company_id: "C1",
    tenantId: "T1",
    companyId: "C1",
    driver_id: "D1",
    owner_driver_id: "D1",
    owner_tenant_id: "T1",
    owner_company_id: "C1",
    status: "stopped",
    stopped_at: "2026-07-23T10:00:00.000Z",
    booking_id: "street_1752863820000_ab12cd34",
    total_eur: 3.2,
    price_incl_vat: 3.2,
    price_ex_vat: 2.64,
    price_vat: 0.56,
    vat_rate: 0.21,
    currency: "EUR",
    pricing_snapshot: { currency: "EUR" },
    ...over,
  });
}

function reconcileReq(body) {
  return new Request("https://track.internal/trip/reconcile-direct-booking", {
    method: "POST",
    headers: { "content-type": "application/json", "x-admin-token": ADMIN },
    body: JSON.stringify(body),
  });
}

function bookingApi(handler) {
  return {
    calls: [],
    async fetch(request) {
      const body = await request.json().catch(() => ({}));
      this.calls.push(body);
      return handler(body, this.calls.length);
    },
  };
}

test("reconcile finalizes booking, persists completed, derives fare from trip", async () => {
  const kv = makeKV({ [TRIP_KEY]: seedTrip() });
  let capturedPayload = null;
  const api = bookingApi((body) => {
    capturedPayload = body;
    return new Response(JSON.stringify({ ok: true, status: "COMPLETED" }), { status: 200 });
  });
  const env = { ADMIN_TOKEN: ADMIN, FLUXIDI_TRACKING: kv, BOOKING_API: api };

  const res = await worker.fetch(reconcileReq({ ...scope, trip_id: "trip_abc" }), env, {});
  const json = await res.json();

  assert.equal(res.status, 200);
  assert.equal(json.ok, true);
  assert.equal(json.booking_finalized, true);
  assert.equal(json.booking_finalize_state, "completed");
  assert.equal(json.booking_id, "street_1752863820000_ab12cd34");
  // fare came from the persisted trip totals, not from request input
  assert.equal(capturedPayload.total_eur, 3.2);
  assert.equal(capturedPayload.source, "street_ride_stop");
  const stored = JSON.parse(kv.store.get(TRIP_KEY));
  assert.equal(stored.booking_finalize_state, "completed");
  assert.equal(stored.booking_finalize_attempt_count, 1);
});

test("reconcile ignores any client-provided fare in the request body", async () => {
  const kv = makeKV({ [TRIP_KEY]: seedTrip() });
  let capturedPayload = null;
  const api = bookingApi((body) => {
    capturedPayload = body;
    return new Response(JSON.stringify({ ok: true }), { status: 200 });
  });
  const env = { ADMIN_TOKEN: ADMIN, FLUXIDI_TRACKING: kv, BOOKING_API: api };

  await worker.fetch(
    reconcileReq({ ...scope, trip_id: "trip_abc", total_eur: 999.99, price_incl_vat: 999.99 }),
    env,
    {},
  );
  assert.equal(capturedPayload.total_eur, 3.2);
});

test("duplicate reconcile is idempotent and does not re-call finalize", async () => {
  const kv = makeKV({ [TRIP_KEY]: seedTrip() });
  const api = bookingApi(() => new Response(JSON.stringify({ ok: true }), { status: 200 }));
  const env = { ADMIN_TOKEN: ADMIN, FLUXIDI_TRACKING: kv, BOOKING_API: api };

  const first = await (await worker.fetch(reconcileReq({ ...scope, trip_id: "trip_abc" }), env, {})).json();
  assert.equal(first.booking_finalized, true);
  const second = await (await worker.fetch(reconcileReq({ ...scope, trip_id: "trip_abc" }), env, {})).json();
  assert.equal(second.booking_finalized, true);
  assert.equal(second.reconciled, false);
  assert.equal(second.reason, "already_completed");
  // finalize-direct called exactly once across both reconcile calls
  assert.equal(api.calls.length, 1);
});

test("failed downstream finalize leaves trip pending and retryable", async () => {
  const kv = makeKV({ [TRIP_KEY]: seedTrip() });
  let attempt = 0;
  const api = bookingApi(() => {
    attempt += 1;
    if (attempt === 1) return new Response(JSON.stringify({ ok: false, error: "http_500" }), { status: 500 });
    return new Response(JSON.stringify({ ok: true }), { status: 200 });
  });
  const env = { ADMIN_TOKEN: ADMIN, FLUXIDI_TRACKING: kv, BOOKING_API: api };

  const failed = await (await worker.fetch(reconcileReq({ ...scope, trip_id: "trip_abc" }), env, {})).json();
  assert.equal(failed.ok, false);
  assert.equal(failed.booking_finalized, false);
  assert.equal(failed.booking_finalize_state, "pending");
  const storedPending = JSON.parse(kv.store.get(TRIP_KEY));
  assert.equal(storedPending.booking_finalize_state, "pending");
  assert.equal(storedPending.booking_finalize_attempt_count, 1);

  // Retry succeeds and completes.
  const ok = await (await worker.fetch(reconcileReq({ ...scope, trip_id: "trip_abc" }), env, {})).json();
  assert.equal(ok.booking_finalized, true);
  const storedDone = JSON.parse(kv.store.get(TRIP_KEY));
  assert.equal(storedDone.booking_finalize_state, "completed");
  assert.equal(storedDone.booking_finalize_attempt_count, 2);
});

test("reconcile rejects a non-terminal (still active) trip", async () => {
  const kv = makeKV({ [TRIP_KEY]: seedTrip({ status: "active", stopped_at: "" }) });
  const api = bookingApi(() => new Response(JSON.stringify({ ok: true }), { status: 200 }));
  const env = { ADMIN_TOKEN: ADMIN, FLUXIDI_TRACKING: kv, BOOKING_API: api };

  const res = await worker.fetch(reconcileReq({ ...scope, trip_id: "trip_abc" }), env, {});
  const json = await res.json();
  assert.equal(res.status, 409);
  assert.equal(json.reason, "skipped_non_terminal");
  assert.equal(api.calls.length, 0);
});

test("reconcile rejects a trip with no authoritative fare", async () => {
  const kv = makeKV({ [TRIP_KEY]: seedTrip({ total_eur: null, price_incl_vat: null }) });
  const api = bookingApi(() => new Response(JSON.stringify({ ok: true }), { status: 200 }));
  const env = { ADMIN_TOKEN: ADMIN, FLUXIDI_TRACKING: kv, BOOKING_API: api };

  const res = await worker.fetch(reconcileReq({ ...scope, trip_id: "trip_abc" }), env, {});
  const json = await res.json();
  assert.equal(res.status, 409);
  assert.equal(json.reason, "skipped_missing_fare");
  assert.equal(api.calls.length, 0);
});
