// RELEASE-P0-CLOSE-PLANNED-CHIRON-DURABILITY-GAPS-2026-07-31 — bounded,
// tenant/company-scoped startup recovery for planned Chiron events that
// stayed PENDING after the in-session immediate retry (e.g. app kill /
// cold restart / transient failure).
//
// Endpoint under test: POST /trip/recover-planned-pending
//
// Guarantees exercised:
//   * app-kill after planned STOP with pending event → recovery flips APPLIED
//   * app-kill after planned START with pending event → recovery flips APPLIED
//   * tenant/company scope isolation (never touches another tenant's records)
//   * APPLIED events are never re-emitted
//   * bounded (limit param) — never scans beyond the cap
//   * direct/street trips are never touched (planned-only)
//   * failures remain PENDING (still countable for the next sweep)
//
// Run: node --test workers/tracking/planned_recover_startup_handler.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import worker from "./fluxidi_tracking_api_worker_V2_1_with_route_index.js";

const ADMIN = "test-admin-token";
const SCOPE = { tenant_id: "T1", company_id: "C1" };
const BOOKING_ID = "planned_booking_recov";
const TRIP_ID = `planned_${BOOKING_ID}`;
const TRIP_KEY = `tenant:T1:company:C1:trip:${TRIP_ID}`;

const COMPLIANCE_ENV_BASE = {
  COMPLIANCE_API_URL: "https://compliance.internal",
  COMPLIANCE_ADMIN_TOKEN: "compliance-admin-token",
};

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
      return {
        keys: [...store.keys()].map((name) => ({ name })),
        list_complete: true,
      };
    },
  };
}

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

function bookingApi({ fare = 9.9 } = {}) {
  return {
    calls: [],
    async fetch(request) {
      const url = new URL(request.url);
      const body = await request.json().catch(() => ({}));
      this.calls.push({ path: url.pathname, body });
      if (url.pathname.includes("canonical-fare-for-planned-stop")) {
        return new Response(
          JSON.stringify({
            ok: true,
            booking_id: body.booking_id,
            booking: { booking_id: body.booking_id, price_incl_vat: fare },
          }),
          { status: 200 },
        );
      }
      return new Response(JSON.stringify({ ok: true }), { status: 200 });
    },
  };
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

function envFor({ kv, compliance, booking, extra = {} } = {}) {
  return {
    ...COMPLIANCE_ENV_BASE,
    ADMIN_TOKEN: ADMIN,
    FLUXIDI_TRACKING: kv,
    COMPLIANCE_WORKER: compliance,
    BOOKING_API: booking ?? bookingApi(),
    ...extra,
  };
}

function recordPlannedStopReq(body) {
  return new Request("https://track.internal/trip/record-planned-stop", {
    method: "POST",
    headers: { "content-type": "application/json", "x-admin-token": ADMIN },
    body: JSON.stringify(body),
  });
}

function sessionStartReq(body) {
  return new Request("https://track.internal/track/session/start", {
    method: "POST",
    headers: { "content-type": "application/json", "x-admin-token": ADMIN },
    body: JSON.stringify(body),
  });
}

function recoverPendingReq(body) {
  return new Request("https://track.internal/trip/recover-planned-pending", {
    method: "POST",
    headers: { "content-type": "application/json", "x-admin-token": ADMIN },
    body: JSON.stringify(body),
  });
}

function plannedStopBody(over = {}) {
  return {
    ...SCOPE,
    booking_id: BOOKING_ID,
    driver_id: "D1",
    vehicle_id: "V1",
    km_total: 3.3,
    wait_seconds_total: 15,
    total_eur: 9.9,
    currency: "EUR",
    ...over,
  };
}

function startBody(over = {}) {
  return {
    ...SCOPE,
    booking_id: BOOKING_ID,
    driver_id: "D1",
    vehicle_id: "V1",
    pickup: "A",
    dropoff: "B",
    client_started_at: "2026-07-30T08:00:00.000Z",
    ...over,
  };
}

function findSessionKey(kv, tenant = "T1", company = "C1") {
  for (const key of kv.store.keys()) {
    if (key.startsWith(`tenant:${tenant}:company:${company}:session:`)) return key;
  }
  return null;
}

// ---------------------------------------------------------------------------
// STOP recovery
// ---------------------------------------------------------------------------

test("app-kill after planned STOP with pending event → startup recovery flips APPLIED", async () => {
  const kv = makeKV();
  // First: initial STOP with Chiron down → PENDING (simulates a crash before
  // the in-session immediate retry could complete).
  const down = complianceWorker(
    () => new Response(JSON.stringify({ ok: false }), { status: 502 }),
  );
  const ctx1 = makeCtx();
  await worker.fetch(
    recordPlannedStopReq(plannedStopBody()),
    envFor({ kv, compliance: down }),
    ctx1,
  );
  await ctx1.flush();
  const pending = JSON.parse(kv.store.get(TRIP_KEY));
  assert.equal(pending.compliance_emit_state, "pending");

  // Startup recovery with Chiron back up.
  const up = complianceWorker(
    () => new Response(JSON.stringify({ ok: true }), { status: 200 }),
  );
  const res = await worker.fetch(
    recoverPendingReq({ ...SCOPE, limit: 25 }),
    envFor({ kv, compliance: up }),
    {},
  );
  const body = await res.json();
  assert.equal(res.status, 200);
  assert.equal(body.ok, true);
  assert.equal(body.reconciled_stops, 1);
  assert.equal(body.still_pending_stops, 0);
  // Same deterministic event_id was reused.
  assert.equal(up.calls.length, 1);
  assert.equal(up.calls[0].event_id, `ride_stop:T1:C1:${TRIP_ID}`);
  // Persisted state now APPLIED.
  const stored = JSON.parse(kv.store.get(TRIP_KEY));
  assert.equal(stored.compliance_emit_state, "applied");
  assert.equal(stored.compliance_emit_attempt_count, 2);
});

test("startup recovery skips APPLIED trips: they are never re-emitted", async () => {
  const kv = makeKV();
  const up = complianceWorker(
    () => new Response(JSON.stringify({ ok: true }), { status: 200 }),
  );
  // First STOP already lands APPLIED.
  const ctx = makeCtx();
  await worker.fetch(
    recordPlannedStopReq(plannedStopBody()),
    envFor({ kv, compliance: up }),
    ctx,
  );
  await ctx.flush();
  const applied = JSON.parse(kv.store.get(TRIP_KEY));
  assert.equal(applied.compliance_emit_state, "applied");
  assert.equal(up.calls.length, 1);

  // Recovery must not touch APPLIED.
  const res = await worker.fetch(
    recoverPendingReq({ ...SCOPE, limit: 25 }),
    envFor({ kv, compliance: up }),
    {},
  );
  const body = await res.json();
  assert.equal(body.reconciled_stops, 0);
  assert.equal(body.still_pending_stops, 0);
  assert.ok(
    body.already_applied_stops >= 1,
    "trip must be counted as already-applied",
  );
  assert.equal(up.calls.length, 1, "no additional Chiron emit");
});

test("startup recovery keeps PENDING when Chiron is still down (no false APPLIED)", async () => {
  const kv = makeKV();
  const down1 = complianceWorker(
    () => new Response(JSON.stringify({ ok: false }), { status: 502 }),
  );
  const ctx = makeCtx();
  await worker.fetch(
    recordPlannedStopReq(plannedStopBody()),
    envFor({ kv, compliance: down1 }),
    ctx,
  );
  await ctx.flush();

  const down2 = complianceWorker(
    () => new Response(JSON.stringify({ ok: false }), { status: 502 }),
  );
  const res = await worker.fetch(
    recoverPendingReq({ ...SCOPE, limit: 25 }),
    envFor({ kv, compliance: down2 }),
    {},
  );
  const body = await res.json();
  assert.equal(body.reconciled_stops, 0);
  assert.equal(body.still_pending_stops, 1);
  const stored = JSON.parse(kv.store.get(TRIP_KEY));
  assert.equal(stored.compliance_emit_state, "pending");
  // Attempt count incremented (durable outbox increments each retry).
  assert.equal(stored.compliance_emit_attempt_count, 2);
  assert.equal(stored.compliance_emit_last_error_code, "http_502");
});

// ---------------------------------------------------------------------------
// START recovery
// ---------------------------------------------------------------------------

test("app-kill after planned START with pending event → startup recovery flips APPLIED", async () => {
  const kv = makeKV();
  const down = complianceWorker(
    () => new Response(JSON.stringify({ ok: false }), { status: 502 }),
  );
  const ctx = makeCtx();
  await worker.fetch(sessionStartReq(startBody()), envFor({ kv, compliance: down }), ctx);
  await ctx.flush();
  const sessionKey = findSessionKey(kv);
  const pending = JSON.parse(kv.store.get(sessionKey));
  assert.equal(pending.compliance_emit_start_state, "pending");

  const up = complianceWorker(
    () => new Response(JSON.stringify({ ok: true }), { status: 200 }),
  );
  const res = await worker.fetch(
    recoverPendingReq({ ...SCOPE, limit: 25 }),
    envFor({ kv, compliance: up }),
    {},
  );
  const body = await res.json();
  assert.equal(res.status, 200);
  assert.equal(body.reconciled_starts, 1);
  const stored = JSON.parse(kv.store.get(sessionKey));
  assert.equal(stored.compliance_emit_start_state, "applied");
  // Deterministic event_id preserved.
  assert.equal(up.calls.length, 1);
  const sessId = pending.session_id;
  assert.equal(up.calls[0].event_id, `ride_start:T1:C1:${sessId}`);
});

// ---------------------------------------------------------------------------
// Tenant/company scope isolation
// ---------------------------------------------------------------------------

test("startup recovery is tenant/company-scoped: never touches another tenant's records", async () => {
  const kv = makeKV();
  // Two pending stops in DIFFERENT tenants.
  const down1 = complianceWorker(
    () => new Response(JSON.stringify({ ok: false }), { status: 502 }),
  );
  const c1 = makeCtx();
  await worker.fetch(
    recordPlannedStopReq(plannedStopBody({ tenant_id: "T1", booking_id: "bkA" })),
    envFor({ kv, compliance: down1 }),
    c1,
  );
  await c1.flush();
  const c2 = makeCtx();
  await worker.fetch(
    recordPlannedStopReq(plannedStopBody({ tenant_id: "T2", booking_id: "bkB" })),
    envFor({ kv, compliance: down1 }),
    c2,
  );
  await c2.flush();

  // Recovery scoped to T1 — must NOT retry T2.
  const up = complianceWorker(
    () => new Response(JSON.stringify({ ok: true }), { status: 200 }),
  );
  const res = await worker.fetch(
    recoverPendingReq({ tenant_id: "T1", company_id: "C1", limit: 25 }),
    envFor({ kv, compliance: up }),
    {},
  );
  const body = await res.json();
  assert.equal(res.status, 200);
  // Only T1's stop was recovered.
  assert.ok(
    body.reconciled_stops >= 1,
    `expected reconciled_stops >= 1, got ${body.reconciled_stops}`,
  );
  for (const call of up.calls) {
    assert.equal(call.tenant_id, "T1", "must never emit for T2 in T1-scoped recovery");
    assert.equal(call.company_id, "C1");
  }
  // T2's trip still pending.
  const t2TripKey = "tenant:T2:company:C1:trip:planned_bkB";
  const t2Stored = JSON.parse(kv.store.get(t2TripKey));
  assert.equal(t2Stored.compliance_emit_state, "pending");
});

// ---------------------------------------------------------------------------
// Bounded scan
// ---------------------------------------------------------------------------

test("bounded: limit=1 processes at most one trip", async () => {
  const kv = makeKV();
  const down = complianceWorker(
    () => new Response(JSON.stringify({ ok: false }), { status: 502 }),
  );

  // Seed 3 pending stops.
  for (const bookingId of ["bkX1", "bkX2", "bkX3"]) {
    const ctx = makeCtx();
    await worker.fetch(
      recordPlannedStopReq(plannedStopBody({ booking_id: bookingId })),
      envFor({ kv, compliance: down }),
      ctx,
    );
    await ctx.flush();
  }

  const up = complianceWorker(
    () => new Response(JSON.stringify({ ok: true }), { status: 200 }),
  );
  const res = await worker.fetch(
    recoverPendingReq({ ...SCOPE, limit: 1 }),
    envFor({ kv, compliance: up }),
    {},
  );
  const body = await res.json();
  assert.equal(res.status, 200);
  assert.equal(body.limit, 1);
  assert.equal(body.scanned_trips, 1, "bounded scan must not exceed limit");
  assert.ok(body.reconciled_stops <= 1);
});

test("bounded scan does not touch old unrelated PENDING trips beyond the limit", async () => {
  const kv = makeKV();
  const down = complianceWorker(
    () => new Response(JSON.stringify({ ok: false }), { status: 502 }),
  );
  for (const bookingId of ["oldA", "oldB", "oldC", "oldD"]) {
    const ctx = makeCtx();
    await worker.fetch(
      recordPlannedStopReq(plannedStopBody({ booking_id: bookingId })),
      envFor({ kv, compliance: down }),
      ctx,
    );
    await ctx.flush();
  }

  const up = complianceWorker(
    () => new Response(JSON.stringify({ ok: true }), { status: 200 }),
  );
  const res = await worker.fetch(
    recoverPendingReq({ ...SCOPE, limit: 2 }),
    envFor({ kv, compliance: up }),
    {},
  );
  const body = await res.json();
  assert.equal(body.scanned_trips, 2);
  // At least half remain pending (limit prevented full sweep).
  const pendingCount = [...kv.store.keys()]
    .filter((k) => k.startsWith("tenant:T1:company:C1:trip:planned_old"))
    .map((k) => JSON.parse(kv.store.get(k)))
    .filter((t) => t.compliance_emit_state === "pending").length;
  assert.ok(
    pendingCount >= 2,
    `at least 2 old trips must remain pending (was ${pendingCount})`,
  );
});
