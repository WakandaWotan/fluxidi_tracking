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

// CHIRON-AUTOMATIC-SYNC-AFTER-STOP-P0-FIELD-2026-07-29 -----------------------
// Reuses the same in-memory-KV + fake-booking-API harness above. Adds a fake
// COMPLIANCE_WORKER service binding so the tracking worker's compliance-emit
// path (which the compliance dashboard's Chiron score-summary counts) can be
// exercised end-to-end WITHOUT touching the real compliance worker.

const COMPLIANCE_ENV_BASE = {
  COMPLIANCE_API_URL: "https://compliance.internal",
  COMPLIANCE_ADMIN_TOKEN: "compliance-admin-token",
};

function complianceWorker(handler) {
  return {
    calls: [],
    async fetch(request) {
      const body = await request.json().catch(() => ({}));
      this.calls.push(body);
      return handler(body, this.calls.length);
    },
  };
}

function stopReq(body) {
  return new Request("https://track.internal/trip/stop", {
    method: "POST",
    headers: { "content-type": "application/json", "x-admin-token": ADMIN },
    body: JSON.stringify(body),
  });
}

function makeCtx() {
  const pending = [];
  return {
    waitUntil(p) {
      pending.push(Promise.resolve(p).catch(() => {}));
    },
    async flush() {
      while (pending.length) await pending.shift();
    },
  };
}

function activeTrip(over = {}) {
  return seedTrip({ status: "active", stopped_at: "", ...over });
}

test("STOP persists compliance_emit_state=applied with deterministic event_id after emit succeeds", async () => {
  const kv = makeKV({ [TRIP_KEY]: activeTrip() });
  const booking = bookingApi(() => new Response(JSON.stringify({ ok: true }), { status: 200 }));
  const compliance = complianceWorker(() => new Response(JSON.stringify({ ok: true }), { status: 200 }));
  const env = {
    ...COMPLIANCE_ENV_BASE,
    ADMIN_TOKEN: ADMIN,
    FLUXIDI_TRACKING: kv,
    BOOKING_API: booking,
    COMPLIANCE_WORKER: compliance,
  };
  const ctx = makeCtx();

  const res = await worker.fetch(
    stopReq({ ...scope, trip_id: "trip_abc", km_total: 4.2, wait_seconds_total: 0 }),
    env,
    ctx,
  );
  assert.equal(res.status, 200); // STOP response never awaits Chiron.
  await ctx.flush();

  assert.equal(compliance.calls.length, 1);
  assert.equal(compliance.calls[0].event_id, "ride_stop:T1:C1:trip_abc");
  assert.equal(compliance.calls[0].event_type, "ride_stop");
  assert.equal(compliance.calls[0].tenant_id, "T1");
  assert.equal(compliance.calls[0].company_id, "C1");

  const stored = JSON.parse(kv.store.get(TRIP_KEY));
  assert.equal(stored.compliance_emit_state, "applied");
  assert.equal(stored.compliance_emit_event_id, "ride_stop:T1:C1:trip_abc");
  assert.equal(stored.compliance_emit_attempt_count, 1);
  assert.equal(stored.compliance_emit_last_error_code, null);
});

test("STOP leaves compliance_emit_state=pending with error code when emit fails (response still 200)", async () => {
  const kv = makeKV({ [TRIP_KEY]: activeTrip() });
  const booking = bookingApi(() => new Response(JSON.stringify({ ok: true }), { status: 200 }));
  const compliance = complianceWorker(() => new Response(JSON.stringify({ ok: false }), { status: 503 }));
  const env = {
    ...COMPLIANCE_ENV_BASE,
    ADMIN_TOKEN: ADMIN,
    FLUXIDI_TRACKING: kv,
    BOOKING_API: booking,
    COMPLIANCE_WORKER: compliance,
  };
  const ctx = makeCtx();

  const res = await worker.fetch(
    stopReq({ ...scope, trip_id: "trip_abc", km_total: 4.2, wait_seconds_total: 0 }),
    env,
    ctx,
  );
  assert.equal(res.status, 200);
  await ctx.flush();

  const stored = JSON.parse(kv.store.get(TRIP_KEY));
  assert.equal(stored.compliance_emit_state, "pending");
  assert.equal(stored.compliance_emit_event_id, "ride_stop:T1:C1:trip_abc");
  assert.equal(stored.compliance_emit_attempt_count, 1);
  assert.equal(stored.compliance_emit_last_error_code, "http_503");
});

test("reconcile retries compliance emit for a booking-finalized-but-compliance-pending trip and marks applied", async () => {
  // Seed a trip that mirrors the real bug: booking finalize already completed
  // but compliance emit dropped silently at STOP time (pre-fix or transient).
  const kv = makeKV({
    [TRIP_KEY]: seedTrip({
      booking_finalize_state: "completed",
      booking_finalize_attempt_count: 1,
      compliance_emit_state: "pending",
      compliance_emit_attempt_count: 1,
      compliance_emit_last_error_code: "timeout",
    }),
  });
  const booking = bookingApi(() => new Response(JSON.stringify({ ok: true }), { status: 200 }));
  const compliance = complianceWorker(() => new Response(JSON.stringify({ ok: true }), { status: 200 }));
  const env = {
    ...COMPLIANCE_ENV_BASE,
    ADMIN_TOKEN: ADMIN,
    FLUXIDI_TRACKING: kv,
    BOOKING_API: booking,
    COMPLIANCE_WORKER: compliance,
  };

  const res = await worker.fetch(reconcileReq({ ...scope, trip_id: "trip_abc" }), env, {});
  const json = await res.json();

  assert.equal(res.status, 200);
  // Booking side stays idempotent (already completed → no re-finalize).
  assert.equal(booking.calls.length, 0);
  assert.equal(json.reason, "already_completed");
  // Compliance retry ran using the deterministic event id.
  assert.equal(compliance.calls.length, 1);
  assert.equal(compliance.calls[0].event_id, "ride_stop:T1:C1:trip_abc");

  const stored = JSON.parse(kv.store.get(TRIP_KEY));
  assert.equal(stored.compliance_emit_state, "applied");
  assert.equal(stored.compliance_emit_event_id, "ride_stop:T1:C1:trip_abc");
  assert.equal(stored.compliance_emit_attempt_count, 2);
  assert.equal(stored.compliance_emit_last_error_code, null);
});

test("reconcile does NOT re-emit compliance when trip is already applied", async () => {
  const kv = makeKV({
    [TRIP_KEY]: seedTrip({
      booking_finalize_state: "completed",
      compliance_emit_state: "applied",
      compliance_emit_event_id: "ride_stop:T1:C1:trip_abc",
      compliance_emit_attempt_count: 1,
    }),
  });
  const booking = bookingApi(() => new Response(JSON.stringify({ ok: true }), { status: 200 }));
  const compliance = complianceWorker(() => new Response(JSON.stringify({ ok: true }), { status: 200 }));
  const env = {
    ...COMPLIANCE_ENV_BASE,
    ADMIN_TOKEN: ADMIN,
    FLUXIDI_TRACKING: kv,
    BOOKING_API: booking,
    COMPLIANCE_WORKER: compliance,
  };

  await worker.fetch(reconcileReq({ ...scope, trip_id: "trip_abc" }), env, {});

  assert.equal(compliance.calls.length, 0);
  const stored = JSON.parse(kv.store.get(TRIP_KEY));
  assert.equal(stored.compliance_emit_attempt_count, 1); // unchanged
  assert.equal(stored.compliance_emit_state, "applied");
});

test("reconcile compliance retry leaves state pending and increments attempt on repeated failure", async () => {
  const kv = makeKV({
    [TRIP_KEY]: seedTrip({
      booking_finalize_state: "completed",
      compliance_emit_state: "pending",
      compliance_emit_event_id: "ride_stop:T1:C1:trip_abc",
      compliance_emit_attempt_count: 1,
      compliance_emit_last_error_code: "fetch_failed",
    }),
  });
  const booking = bookingApi(() => new Response(JSON.stringify({ ok: true }), { status: 200 }));
  const compliance = complianceWorker(() => new Response(JSON.stringify({ ok: false }), { status: 502 }));
  const env = {
    ...COMPLIANCE_ENV_BASE,
    ADMIN_TOKEN: ADMIN,
    FLUXIDI_TRACKING: kv,
    BOOKING_API: booking,
    COMPLIANCE_WORKER: compliance,
  };

  await worker.fetch(reconcileReq({ ...scope, trip_id: "trip_abc" }), env, {});

  assert.equal(compliance.calls.length, 1);
  const stored = JSON.parse(kv.store.get(TRIP_KEY));
  assert.equal(stored.compliance_emit_state, "pending");
  assert.equal(stored.compliance_emit_attempt_count, 2);
  assert.equal(stored.compliance_emit_last_error_code, "http_502");
  // event_id remains the deterministic one so a future successful retry
  // reaches the same idempotency key.
  assert.equal(stored.compliance_emit_event_id, "ride_stop:T1:C1:trip_abc");
});

test("STOP waitUntil re-reads the trip before writing: preserves booking-finalize AND out-of-band mutations (no lost update)", async () => {
  // Concurrency invariants proven end-to-end:
  //   1. STOP persists compliance_emit_state=pending BEFORE returning.
  //   2. STOP synchronously runs booking finalize, which updates the trip row
  //      AFTERWARD (still within the request).
  //   3. An OUT-OF-BAND writer (simulating another handler on the same trip)
  //      modifies the row between STOP's synchronous end and the waitUntil
  //      callback firing.
  //   4. The compliance emit resolves AFTERWARD; the waitUntil callback must
  //      preserve BOTH the booking-finalize result and the out-of-band field.
  const kv = makeKV({ [TRIP_KEY]: activeTrip() });
  const booking = bookingApi(() => new Response(JSON.stringify({ ok: true }), { status: 200 }));

  // Compliance handler blocked until we explicitly release, so we can inject
  // the concurrent write in the window between STOP's response and waitUntil.
  let releaseEmit;
  const emitBarrier = new Promise((resolve) => {
    releaseEmit = resolve;
  });
  const compliance = complianceWorker(async () => {
    await emitBarrier;
    return new Response(JSON.stringify({ ok: true }), { status: 200 });
  });
  const env = {
    ...COMPLIANCE_ENV_BASE,
    ADMIN_TOKEN: ADMIN,
    FLUXIDI_TRACKING: kv,
    BOOKING_API: booking,
    COMPLIANCE_WORKER: compliance,
  };
  const ctx = makeCtx();

  // (1) & (2) STOP returns immediately; waitUntil is pending on the barrier.
  const res = await worker.fetch(
    stopReq({ ...scope, trip_id: "trip_abc", km_total: 4.2, wait_seconds_total: 0 }),
    env,
    ctx,
  );
  assert.equal(res.status, 200);

  const beforeInjection = JSON.parse(kv.store.get(TRIP_KEY));
  assert.equal(beforeInjection.status, "stopped");
  assert.equal(beforeInjection.booking_finalize_state, "completed"); // (2)
  assert.equal(beforeInjection.compliance_emit_state, "pending"); // (1)
  // (3) Concurrent out-of-band writer touches the same KV row.
  beforeInjection.probe_out_of_band = "external_write_before_waituntil";
  beforeInjection.booking_finalize_attempt_count = 7; // simulate a repair bumping the counter
  await kv.put(TRIP_KEY, JSON.stringify(beforeInjection));

  // (4) Release the emit and let the waitUntil callback complete.
  releaseEmit();
  await ctx.flush();

  const finalRow = JSON.parse(kv.store.get(TRIP_KEY));
  // Compliance emit landed applied with the deterministic id.
  assert.equal(finalRow.compliance_emit_state, "applied");
  assert.equal(finalRow.compliance_emit_event_id, "ride_stop:T1:C1:trip_abc");
  assert.equal(finalRow.compliance_emit_attempt_count, 1);
  // Booking finalize result is preserved (would be lost by a stale-closure write).
  assert.equal(finalRow.booking_finalize_state, "completed");
  // Out-of-band mutations are preserved — this is the lost-update proof.
  assert.equal(finalRow.probe_out_of_band, "external_write_before_waituntil");
  assert.equal(finalRow.booking_finalize_attempt_count, 7);
  // Every other field the STOP originally persisted is still intact.
  assert.equal(finalRow.status, "stopped");
  assert.equal(finalRow.tenant_id, "T1");
  assert.equal(finalRow.company_id, "C1");
});

test("reconcile is a no-op for compliance emit when configuration is missing (leaves state pending, no crash)", async () => {
  const kv = makeKV({
    [TRIP_KEY]: seedTrip({
      booking_finalize_state: "completed",
      compliance_emit_state: "pending",
    }),
  });
  const booking = bookingApi(() => new Response(JSON.stringify({ ok: true }), { status: 200 }));
  const env = {
    // no COMPLIANCE_API_URL / COMPLIANCE_ADMIN_TOKEN / COMPLIANCE_WORKER
    ADMIN_TOKEN: ADMIN,
    FLUXIDI_TRACKING: kv,
    BOOKING_API: booking,
  };

  const res = await worker.fetch(reconcileReq({ ...scope, trip_id: "trip_abc" }), env, {});
  assert.equal(res.status, 200);
  const stored = JSON.parse(kv.store.get(TRIP_KEY));
  assert.equal(stored.compliance_emit_state, "pending");
  assert.equal(stored.compliance_emit_last_error_code, "missing_config");
});
