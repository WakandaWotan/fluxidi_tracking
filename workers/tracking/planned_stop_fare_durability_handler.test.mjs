// PLANNED-RIDE-FIXED-PRICE-PRESENTATION-AND-DURABILITY-1 — handler tests
// Run: node --test workers/tracking/planned_stop_fare_durability_handler.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import worker from "./fluxidi_tracking_api_worker_V2_1_with_route_index.js";

const ADMIN = "test-admin-token";
const SCOPE = { tenant_id: "T1", company_id: "C1" };
const BOOKING_ID = "planned_fare_booking";
const TRIP_ID = `planned_${BOOKING_ID}`;
const TRIP_KEY = `tenant:T1:company:C1:trip:${TRIP_ID}`;

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

function complianceWorker() {
  return {
    calls: [],
    async fetch(request) {
      const body = await request.json().catch(() => ({}));
      this.calls.push(body);
      return new Response(JSON.stringify({ ok: true }), { status: 200 });
    },
  };
}

function bookingApi({ fare = 42.5, returnFare = null } = {}) {
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
              price_incl_vat_main: fare,
              price_incl_vat_return: returnFare,
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

function envFor({ kv, booking, compliance } = {}) {
  return {
    ADMIN_TOKEN: ADMIN,
    FLUXIDI_TRACKING: kv,
    BOOKING_API: booking ?? bookingApi(),
    COMPLIANCE_WORKER: compliance ?? complianceWorker(),
    COMPLIANCE_API_URL: "https://compliance.internal",
    COMPLIANCE_ADMIN_TOKEN: "compliance-admin-token",
  };
}

test("handler: missing client total_eur uses server booking price", async () => {
  const kv = makeKV();
  const booking = bookingApi({ fare: 42.5 });
  const ctx = makeCtx();
  const res = await worker.fetch(
    recordPlannedStopReq({
      ...SCOPE,
      booking_id: BOOKING_ID,
      driver_id: "D1",
      vehicle_id: "V1",
      km_total: 3,
      // total_eur intentionally omitted
    }),
    envFor({ kv, booking }),
    ctx,
  );
  await ctx.flush();
  assert.equal(res.status, 200);
  const stored = JSON.parse(await kv.get(TRIP_KEY));
  assert.equal(stored.total_eur, 42.5);
  assert.equal(stored.price_incl_vat, 42.5);
  assert.ok(
    stored.fare_source === "price_incl_vat" ||
      stored.fare_source === "price_incl_vat_main",
  );
});

test("handler: client total_eur=0 uses server booking price", async () => {
  const kv = makeKV();
  const booking = bookingApi({ fare: 18 });
  const ctx = makeCtx();
  const res = await worker.fetch(
    recordPlannedStopReq({
      ...SCOPE,
      booking_id: BOOKING_ID,
      driver_id: "D1",
      vehicle_id: "V1",
      total_eur: 0,
    }),
    envFor({ kv, booking }),
    ctx,
  );
  await ctx.flush();
  assert.equal(res.status, 200);
  const stored = JSON.parse(await kv.get(TRIP_KEY));
  assert.equal(stored.total_eur, 18);
});

test("handler: manipulated client meter is ignored", async () => {
  const kv = makeKV();
  const booking = bookingApi({ fare: 30 });
  const ctx = makeCtx();
  await worker.fetch(
    recordPlannedStopReq({
      ...SCOPE,
      booking_id: BOOKING_ID,
      driver_id: "D1",
      vehicle_id: "V1",
      total_eur: 999.99,
    }),
    envFor({ kv, booking }),
    ctx,
  );
  await ctx.flush();
  const stored = JSON.parse(await kv.get(TRIP_KEY));
  assert.equal(stored.total_eur, 30);
});

test("handler: offline reconcile repairs zero trip using booking price", async () => {
  const kv = makeKV({
    [TRIP_KEY]: JSON.stringify({
      trip_id: TRIP_ID,
      kind: "planned",
      booking_id: BOOKING_ID,
      parent_booking_id: BOOKING_ID,
      tenant_id: "T1",
      company_id: "C1",
      owner_tenant_id: "T1",
      owner_company_id: "C1",
      owner_driver_id: "D1",
      driver_id: "D1",
      status: "stopped",
      total_eur: 0,
      currency: "EUR",
      compliance_emit_state: "pending",
      compliance_event_id: "evt_planned_stop_1",
    }),
  });
  const booking = bookingApi({ fare: 27.5 });
  const compliance = complianceWorker();
  const res = await worker.fetch(
    reconcilePlannedStopReq({
      ...SCOPE,
      trip_id: TRIP_ID,
      driver_id: "D1",
    }),
    envFor({ kv, booking, compliance }),
  );
  assert.equal(res.status, 200);
  const stored = JSON.parse(await kv.get(TRIP_KEY));
  assert.equal(stored.total_eur, 27.5);
});
