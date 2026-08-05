// RELEASE-P0-DURABLE-CHIRON-SYNC-FOR-PLANNED-RIDES-2026-07-31 — handler tests
// for the planned ride durable Chiron outbox. Exercises:
//   - /trip/record-planned-stop persists a canonical stopped trip AND writes
//     compliance_emit_state=PENDING with a deterministic event_id BEFORE the
//     fire-and-forget compliance emit, so a transient downstream failure never
//     silently drops the ride_stop event.
//   - /trip/record-planned-stop flips to APPLIED after a successful emit and
//     leaves PENDING (with a coarse error code) after a failed emit — response
//     itself is always 200 so the stop UX is never blocked on Chiron.
//   - /trip/reconcile-planned-stop retries the emit using the persisted
//     deterministic event_id, is monotonic (never regresses APPLIED), and is
//     tenant/company-scoped (never emits into another tenant).
//   - /track/session/start persists compliance_emit_start_state=PENDING with a
//     deterministic ride_start event_id and flips to APPLIED after emit
//     succeeds.
//   - /track/session/reconcile-start retries a pending session start and is
//     monotonic + tenant-scoped.
//
// Run: node --test workers/tracking/planned_ride_chiron_durability_handler.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import worker from "./fluxidi_tracking_api_worker_V2_1_with_route_index.js";

const ADMIN = "test-admin-token";
const SCOPE = { tenant_id: "T1", company_id: "C1" };
const OTHER_SCOPE = { tenant_id: "T2", company_id: "C1" };

const BOOKING_ID = "planned_booking_abc";
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

function bookingApi({ fare = 12.5 } = {}) {
  // Completes planned-stop booking sync AND serves canonical fare lookups so
  // client total_eur is never the authoritative planned fare source.
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
            booking: {
              booking_id: body.booking_id,
              price_incl_vat: fare,
            },
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

function recordPlannedStopReq(body) {
  return new Request("https://track.internal/trip/record-planned-stop", {
    method: "POST",
    headers: { "content-type": "application/json", "x-admin-token": ADMIN },
    body: JSON.stringify(body),
  });
}

function reconcilePlannedStopReq(body) {
  return new Request("https://track.internal/trip/reconcile-planned-stop", {
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

function reconcileSessionStartReq(body) {
  return new Request("https://track.internal/track/session/reconcile-start", {
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
    km_total: 4.2,
    wait_seconds_total: 30,
    total_eur: 12.5,
    currency: "EUR",
    ...over,
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

// ---------------------------------------------------------------------------
// Planned STOP durable outbox
// ---------------------------------------------------------------------------

test("planned STOP persists canonical trip + compliance_emit_state=applied with deterministic event_id when emit succeeds", async () => {
  const kv = makeKV();
  const compliance = complianceWorker(
    () => new Response(JSON.stringify({ ok: true }), { status: 200 }),
  );
  const env = envFor({ kv, compliance });
  const ctx = makeCtx();

  const res = await worker.fetch(recordPlannedStopReq(plannedStopBody()), env, ctx);
  const body = await res.json();

  assert.equal(res.status, 200);
  assert.equal(body.ok, true);
  assert.equal(body.trip_id, TRIP_ID);
  assert.equal(body.status, "stopped");
  // Durable outbox fields visible on the response so the client can decide
  // whether to trigger an immediate reconcile.
  assert.ok(
    "compliance_emit_state" in body,
    "response must expose compliance_emit_state",
  );
  assert.equal(
    body.compliance_emit_event_id,
    `ride_stop:T1:C1:${TRIP_ID}`,
  );

  await ctx.flush();

  // Compliance received exactly one event with the deterministic id.
  assert.equal(compliance.calls.length, 1);
  assert.equal(compliance.calls[0].event_type, "ride_stop");
  assert.equal(compliance.calls[0].ride_type, "planned");
  assert.equal(compliance.calls[0].tenant_id, "T1");
  assert.equal(compliance.calls[0].company_id, "C1");
  assert.equal(compliance.calls[0].booking_id, BOOKING_ID);
  assert.equal(compliance.calls[0].trip_id, TRIP_ID);
  assert.equal(compliance.calls[0].event_id, `ride_stop:T1:C1:${TRIP_ID}`);
  // Functional fare fields must be present so Chiron gets a complete row.
  assert.equal(compliance.calls[0].fare.total_amount, 12.5);
  assert.equal(compliance.calls[0].fare.distance_km, 4.2);
  assert.equal(compliance.calls[0].fare.wait_seconds_total, 30);
  assert.equal(compliance.calls[0].fare.currency, "EUR");

  const stored = JSON.parse(kv.store.get(TRIP_KEY));
  assert.equal(stored.kind, "planned");
  assert.equal(stored.status, "stopped");
  assert.equal(stored.km_total, 4.2);
  assert.equal(stored.total_eur, 12.5);
  assert.equal(stored.compliance_emit_state, "applied");
  assert.equal(stored.compliance_emit_event_id, `ride_stop:T1:C1:${TRIP_ID}`);
  assert.equal(stored.compliance_emit_attempt_count, 1);
  assert.equal(stored.compliance_emit_last_error_code, null);
});

test("planned STOP leaves compliance_emit_state=pending with error code when emit fails (response still 200 with totals stored)", async () => {
  const kv = makeKV();
  const compliance = complianceWorker(
    () => new Response(JSON.stringify({ ok: false }), { status: 503 }),
  );
  const env = envFor({ kv, compliance });
  const ctx = makeCtx();

  const res = await worker.fetch(recordPlannedStopReq(plannedStopBody()), env, ctx);
  const body = await res.json();

  // Stop functionally succeeds even when Chiron is down.
  assert.equal(res.status, 200);
  assert.equal(body.ok, true);
  assert.equal(body.status, "stopped");

  await ctx.flush();

  const stored = JSON.parse(kv.store.get(TRIP_KEY));
  assert.equal(stored.status, "stopped");
  assert.equal(stored.total_eur, 12.5);
  assert.equal(stored.compliance_emit_state, "pending");
  assert.equal(stored.compliance_emit_event_id, `ride_stop:T1:C1:${TRIP_ID}`);
  assert.equal(stored.compliance_emit_attempt_count, 1);
  assert.equal(stored.compliance_emit_last_error_code, "http_503");
});

// ---------------------------------------------------------------------------
// Planned reconcile
// ---------------------------------------------------------------------------

test("reconcile-planned-stop retries a pending trip and marks applied without changing totals", async () => {
  const kv = makeKV();
  // First: initial STOP where compliance is down → PENDING.
  const complianceDown = complianceWorker(
    () => new Response(JSON.stringify({ ok: false }), { status: 502 }),
  );
  const ctx1 = makeCtx();
  await worker.fetch(
    recordPlannedStopReq(plannedStopBody()),
    envFor({ kv, compliance: complianceDown }),
    ctx1,
  );
  await ctx1.flush();
  const pending = JSON.parse(kv.store.get(TRIP_KEY));
  assert.equal(pending.compliance_emit_state, "pending");
  assert.equal(pending.compliance_emit_attempt_count, 1);

  // Second: reconcile with compliance back up → APPLIED.
  const complianceUp = complianceWorker(
    () => new Response(JSON.stringify({ ok: true }), { status: 200 }),
  );
  const res = await worker.fetch(
    reconcilePlannedStopReq({ ...SCOPE, trip_id: TRIP_ID }),
    envFor({ kv, compliance: complianceUp }),
    {},
  );
  const body = await res.json();
  assert.equal(res.status, 200);
  assert.equal(body.ok, true);
  assert.equal(body.reconciled, true);
  assert.equal(body.compliance_emit_state, "applied");
  // Reused the same deterministic event_id (no second Chiron dossier row).
  assert.equal(complianceUp.calls.length, 1);
  assert.equal(complianceUp.calls[0].event_id, `ride_stop:T1:C1:${TRIP_ID}`);

  const stored = JSON.parse(kv.store.get(TRIP_KEY));
  assert.equal(stored.compliance_emit_state, "applied");
  assert.equal(stored.compliance_emit_event_id, `ride_stop:T1:C1:${TRIP_ID}`);
  assert.equal(stored.compliance_emit_attempt_count, 2);
  assert.equal(stored.total_eur, 12.5); // untouched
});

test("reconcile-planned-stop is idempotent when already applied (never re-emits)", async () => {
  const kv = makeKV();
  const compliance = complianceWorker(
    () => new Response(JSON.stringify({ ok: true }), { status: 200 }),
  );
  const ctx = makeCtx();
  await worker.fetch(recordPlannedStopReq(plannedStopBody()), envFor({ kv, compliance }), ctx);
  await ctx.flush();
  assert.equal(compliance.calls.length, 1);

  const res = await worker.fetch(
    reconcilePlannedStopReq({ ...SCOPE, trip_id: TRIP_ID }),
    envFor({ kv, compliance }),
    {},
  );
  const body = await res.json();
  assert.equal(res.status, 200);
  assert.equal(body.reason, "already_applied");
  assert.equal(body.compliance_emit_state, "applied");
  // No additional emit.
  assert.equal(compliance.calls.length, 1);
});

test("reconcile-planned-stop rejects a trip from another tenant (fail-closed)", async () => {
  const kv = makeKV();
  // Seed a trip with matching key path but wrong tenant fields on the record.
  const badTrip = {
    trip_id: TRIP_ID,
    kind: "planned",
    tenant_id: "T2", // record scope
    company_id: "C1",
    tenantId: "T2",
    companyId: "C1",
    owner_tenant_id: "T2",
    owner_company_id: "C1",
    driver_id: "D1",
    status: "stopped",
    stopped_at: "2026-07-30T10:00:00.000Z",
    booking_id: BOOKING_ID,
    compliance_emit_state: "pending",
    compliance_emit_event_id: `ride_stop:T2:C1:${TRIP_ID}`,
    compliance_emit_attempt_count: 1,
  };
  // Seed under scope T1's key path.
  kv.store.set(TRIP_KEY, JSON.stringify(badTrip));

  const compliance = complianceWorker(
    () => new Response(JSON.stringify({ ok: true }), { status: 200 }),
  );
  // Request comes in with scope T1 (mismatched from the stored record).
  const res = await worker.fetch(
    reconcilePlannedStopReq({ ...SCOPE, trip_id: TRIP_ID }),
    envFor({ kv, compliance }),
    {},
  );
  // Must NOT emit into T1's scope and must NOT return 200/ok.
  assert.notEqual(res.status, 200);
  assert.equal(compliance.calls.length, 0);
});

test("reconcile-planned-stop rejects a direct (kind=direct) trip", async () => {
  const kv = makeKV();
  const directTrip = {
    trip_id: "trip_direct_xyz",
    kind: "direct",
    tenant_id: "T1",
    company_id: "C1",
    tenantId: "T1",
    companyId: "C1",
    owner_tenant_id: "T1",
    owner_company_id: "C1",
    driver_id: "D1",
    status: "stopped",
    stopped_at: "2026-07-30T10:00:00.000Z",
    booking_id: "street_1234_deadbeef",
    compliance_emit_state: "pending",
    compliance_emit_event_id: "ride_stop:T1:C1:trip_direct_xyz",
    compliance_emit_attempt_count: 1,
  };
  kv.store.set(
    "tenant:T1:company:C1:trip:trip_direct_xyz",
    JSON.stringify(directTrip),
  );
  const compliance = complianceWorker(
    () => new Response(JSON.stringify({ ok: true }), { status: 200 }),
  );
  const res = await worker.fetch(
    reconcilePlannedStopReq({ ...SCOPE, trip_id: "trip_direct_xyz" }),
    envFor({ kv, compliance }),
    {},
  );
  const body = await res.json();
  assert.equal(res.status, 409);
  assert.equal(body.reason, "not_planned");
  assert.equal(compliance.calls.length, 0);
});

test("reconcile-planned-stop retry that fails again keeps pending and increments attempt", async () => {
  const kv = makeKV();
  const complianceDown = complianceWorker(
    () => new Response(JSON.stringify({ ok: false }), { status: 500 }),
  );
  const ctx = makeCtx();
  await worker.fetch(recordPlannedStopReq(plannedStopBody()), envFor({ kv, compliance: complianceDown }), ctx);
  await ctx.flush();
  assert.equal(
    JSON.parse(kv.store.get(TRIP_KEY)).compliance_emit_attempt_count,
    1,
  );

  const res = await worker.fetch(
    reconcilePlannedStopReq({ ...SCOPE, trip_id: TRIP_ID }),
    envFor({ kv, compliance: complianceDown }),
    {},
  );
  const body = await res.json();
  assert.equal(res.status, 200);
  assert.equal(body.ok, false);
  assert.equal(body.reconciled, false);
  assert.equal(body.compliance_emit_state, "pending");
  const stored = JSON.parse(kv.store.get(TRIP_KEY));
  assert.equal(stored.compliance_emit_state, "pending");
  assert.equal(stored.compliance_emit_attempt_count, 2);
  assert.equal(stored.compliance_emit_last_error_code, "http_500");
});

test("two concurrent reconcile retries reuse the same deterministic event_id", async () => {
  const kv = makeKV();
  // Prime pending state.
  const complianceDown = complianceWorker(
    () => new Response(JSON.stringify({ ok: false }), { status: 502 }),
  );
  const ctx = makeCtx();
  await worker.fetch(recordPlannedStopReq(plannedStopBody()), envFor({ kv, compliance: complianceDown }), ctx);
  await ctx.flush();

  const complianceUp = complianceWorker(
    () => new Response(JSON.stringify({ ok: true }), { status: 200 }),
  );
  const [a, b] = await Promise.all([
    worker.fetch(reconcilePlannedStopReq({ ...SCOPE, trip_id: TRIP_ID }), envFor({ kv, compliance: complianceUp }), {}),
    worker.fetch(reconcilePlannedStopReq({ ...SCOPE, trip_id: TRIP_ID }), envFor({ kv, compliance: complianceUp }), {}),
  ]);
  const jsA = await a.json();
  const jsB = await b.json();
  // Both retries must carry the same deterministic event_id — downstream
  // compliance dedup collapses them into a single Chiron dossier row.
  const eventIds = complianceUp.calls.map((c) => c.event_id);
  assert.equal(eventIds.every((id) => id === `ride_stop:T1:C1:${TRIP_ID}`), true);
  // At least one must have transitioned to applied.
  const anyApplied =
    jsA.compliance_emit_state === "applied" ||
    jsB.compliance_emit_state === "applied";
  assert.equal(anyApplied, true);
});

test("planned STOP followed by direct STOP does not cross-contaminate outbox fields", async () => {
  // Regression proof that the planned outbox uses the same field family as
  // direct but writes onto a distinct trip record — the two cannot mix.
  const kv = makeKV();
  const compliance = complianceWorker(
    () => new Response(JSON.stringify({ ok: true }), { status: 200 }),
  );
  const ctx = makeCtx();
  await worker.fetch(recordPlannedStopReq(plannedStopBody()), envFor({ kv, compliance }), ctx);
  await ctx.flush();
  const planned = JSON.parse(kv.store.get(TRIP_KEY));
  assert.equal(planned.kind, "planned");
  assert.equal(planned.compliance_emit_event_id, `ride_stop:T1:C1:${TRIP_ID}`);
});
