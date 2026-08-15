// Durable street-ride START outbox. Mirrors planned START / direct STOP.
//
// Run: node --test workers/tracking/direct_ride_start_chiron_durability_handler.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import worker from "./fluxidi_tracking_api_worker_V2_1_with_route_index.js";

const ADMIN = "test-admin-token";
const SCOPE = { tenant_id: "T1", company_id: "C1" };

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

function startReq(body) {
  return new Request("https://track.internal/trip/start-direct", {
    method: "POST",
    headers: { "content-type": "application/json", "x-admin-token": ADMIN },
    body: JSON.stringify(body),
  });
}

function reconcileReq(body) {
  return new Request("https://track.internal/trip/reconcile-direct-booking", {
    method: "POST",
    headers: { "content-type": "application/json", "x-admin-token": ADMIN },
    body: JSON.stringify(body),
  });
}

function envFor({ kv, compliance } = {}) {
  return {
    ADMIN_TOKEN: ADMIN,
    COMPLIANCE_API_URL: "https://compliance.internal",
    COMPLIANCE_ADMIN_TOKEN: "compliance-admin-token",
    FLUXIDI_TRACKING: kv,
    COMPLIANCE_WORKER: compliance,
    BOOKING_API: {
      async fetch() {
        return new Response(
          JSON.stringify({ ok: true, booking_id: "street_test_booking" }),
          { status: 200 },
        );
      },
    },
  };
}

function findTripKey(kv) {
  for (const key of kv.store.keys()) {
    if (key.includes(":trip:")) return key;
  }
  return null;
}

test("direct START persists pending then applied with deterministic event_id", async () => {
  const kv = makeKV();
  const compliance = complianceWorker(
    () => new Response(JSON.stringify({ ok: true }), { status: 200 }),
  );
  const ctx = makeCtx();
  const res = await worker.fetch(
    startReq({
      ...SCOPE,
      driver_id: "D1",
      vehicle_id: "V1",
      origin: { lat: 51.0, lng: 3.7 },
      destination: { lat: 51.1, lng: 3.8 },
      pricing_snapshot: { currency: "EUR", start_fee: 2.5, per_km: 1.2, wait_per_min: 0.5 },
    }),
    envFor({ kv, compliance }),
    ctx,
  );
  const body = await res.json();
  assert.equal(res.status, 200);
  assert.equal(body.ok, true);
  const tripId = body.trip_id;
  assert.ok(tripId);
  await ctx.flush();

  const expectedEventId = `ride_start:T1:C1:${tripId}`;
  assert.equal(compliance.calls.length, 1);
  assert.equal(compliance.calls[0].event_type, "ride_start");
  assert.equal(compliance.calls[0].event_id, expectedEventId);
  assert.equal(compliance.calls[0].trip_id, tripId);

  const tripKey = findTripKey(kv);
  const stored = JSON.parse(kv.store.get(tripKey));
  assert.equal(stored.compliance_emit_start_state, "applied");
  assert.equal(stored.compliance_emit_start_event_id, expectedEventId);
  assert.equal(stored.compliance_emit_start_attempt_count, 1);
  assert.equal(stored.compliance_emit_start_last_error_code, null);
});

test("direct START stays pending and retries the same event_id after emit failure", async () => {
  const kv = makeKV();
  const compliance = complianceWorker(
    () => new Response(JSON.stringify({ ok: false }), { status: 502 }),
  );
  const ctx = makeCtx();
  const res = await worker.fetch(
    startReq({
      ...SCOPE,
      driver_id: "D1",
      vehicle_id: "V1",
      pricing_snapshot: { currency: "EUR", start_fee: 2.5, per_km: 1.2, wait_per_min: 0.5 },
    }),
    envFor({ kv, compliance }),
    ctx,
  );
  const body = await res.json();
  assert.equal(res.status, 200);
  await ctx.flush();
  const tripId = body.trip_id;
  const tripKey = findTripKey(kv);
  const stored = JSON.parse(kv.store.get(tripKey));
  const expectedEventId = `ride_start:T1:C1:${tripId}`;
  assert.equal(stored.compliance_emit_start_state, "pending");
  assert.equal(stored.compliance_emit_start_event_id, expectedEventId);
  assert.equal(stored.compliance_emit_start_last_error_code, "http_502");

  const complianceUp = complianceWorker(
    () => new Response(JSON.stringify({ ok: true }), { status: 200 }),
  );
  const res2 = await worker.fetch(
    reconcileReq({ ...SCOPE, trip_id: tripId }),
    envFor({ kv, compliance: complianceUp }),
    {},
  );
  const after = JSON.parse(kv.store.get(tripKey));
  assert.equal(after.compliance_emit_start_state, "applied");
  assert.equal(after.compliance_emit_start_event_id, expectedEventId);
  assert.equal(complianceUp.calls.length, 1);
  assert.equal(complianceUp.calls[0].event_id, expectedEventId);
});

test("historical trip with empty start outbox is not re-emitted on reconcile", async () => {
  const tripId = "trip_historical";
  const tripKey = "tenant:T1:company:C1:trip:trip_historical";
  const kv = makeKV({
    [tripKey]: JSON.stringify({
      trip_id: tripId,
      kind: "direct",
      tenant_id: "T1",
      company_id: "C1",
      driver_id: "D1",
      status: "stopped",
      started_at: "2026-08-15T10:00:00.000Z",
      stopped_at: "2026-08-15T10:20:00.000Z",
      booking_finalize_state: "completed",
    }),
  });
  const compliance = complianceWorker(
    () => new Response(JSON.stringify({ ok: true }), { status: 200 }),
  );
  const res = await worker.fetch(
    reconcileReq({ ...SCOPE, trip_id: tripId }),
    envFor({ kv, compliance }),
    {},
  );
  assert.equal(res.status, 200);
  const startCalls = compliance.calls.filter((c) => c.event_type === "ride_start");
  assert.equal(startCalls.length, 0);
});
