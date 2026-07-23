// STREET-RIDE-DURABLE-COMPLETION-2 — handler-level integration tests for the
// bounded dry-run repair endpoint /trip/repair-direct-bookings.
//
// Run: node --test workers/tracking/direct_booking_repair_handler.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import worker from "./fluxidi_tracking_api_worker_V2_1_with_route_index.js";

const ADMIN = "test-admin-token";
const scope = { tenant_id: "T1", company_id: "C1" };
const INDEX_KEY = "tenant:T1:company:C1:trips_index";
const tripKey = (id) => `tenant:T1:company:C1:trip:${id}`;

function base(id, over = {}) {
  return {
    trip_id: id,
    tenant_id: "T1",
    company_id: "C1",
    tenantId: "T1",
    companyId: "C1",
    driver_id: "D1",
    owner_driver_id: "D1",
    currency: "EUR",
    pricing_snapshot: { currency: "EUR" },
    ...over,
  };
}

function seedKV() {
  const trips = {
    trip_stopped: base("trip_stopped", {
      kind: "direct",
      source: "street_ride",
      status: "stopped",
      stopped_at: "2026-07-23T10:00:00.000Z",
      booking_id: "street_stopped_ab",
      total_eur: 3.2,
      price_incl_vat: 3.2,
      vat_rate: 0.21,
    }),
    trip_active: base("trip_active", {
      kind: "direct",
      source: "street_ride",
      status: "active",
      booking_id: "street_active_ab",
      total_eur: 3.2,
      price_incl_vat: 3.2,
    }),
    trip_nofare: base("trip_nofare", {
      kind: "direct",
      source: "street_ride",
      status: "stopped",
      stopped_at: "2026-07-23T10:00:00.000Z",
      booking_id: "street_nofare_ab",
      total_eur: null,
      price_incl_vat: null,
    }),
    trip_done: base("trip_done", {
      kind: "direct",
      source: "street_ride",
      status: "stopped",
      stopped_at: "2026-07-23T10:00:00.000Z",
      booking_id: "street_done_ab",
      total_eur: 4.0,
      price_incl_vat: 4.0,
      booking_finalize_state: "completed",
    }),
    trip_planned: base("trip_planned", {
      kind: "planned",
      source: "planning",
      status: "stopped",
      stopped_at: "2026-07-23T10:00:00.000Z",
      booking_id: "BK-2026-1",
      total_eur: 9.9,
      price_incl_vat: 9.9,
    }),
  };
  const store = new Map();
  store.set(INDEX_KEY, JSON.stringify(Object.keys(trips)));
  for (const [id, rec] of Object.entries(trips)) {
    store.set(tripKey(id), JSON.stringify(rec));
  }
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

function bookingApi() {
  return {
    calls: [],
    async fetch(request) {
      const body = await request.json().catch(() => ({}));
      this.calls.push(body);
      return new Response(JSON.stringify({ ok: true, status: "COMPLETED" }), { status: 200 });
    },
  };
}

function repairReq(body) {
  return new Request("https://track.internal/trip/repair-direct-bookings", {
    method: "POST",
    headers: { "content-type": "application/json", "x-admin-token": ADMIN },
    body: JSON.stringify(body),
  });
}

test("repair dry-run (default) classifies candidates and performs NO writes", async () => {
  const kv = seedKV();
  const api = bookingApi();
  const env = { ADMIN_TOKEN: ADMIN, FLUXIDI_TRACKING: kv, BOOKING_API: api };
  const before = kv.store.get(tripKey("trip_stopped"));

  const res = await worker.fetch(repairReq({ ...scope }), env, {});
  const json = await res.json();

  assert.equal(res.status, 200);
  assert.equal(json.dry_run, true);
  assert.equal(json.summary.candidates, 4); // 4 street/direct trips (planned excluded)
  assert.equal(json.summary.repairable, 1); // only trip_stopped
  assert.equal(json.summary.skipped_non_terminal, 1); // trip_active
  assert.equal(json.summary.skipped_missing_fare, 1); // trip_nofare
  assert.equal(json.summary.already_completed, 1); // trip_done
  assert.equal(json.summary.errors, 0);
  // No writes: booking finalize was never called and the record is byte-identical.
  assert.equal(api.calls.length, 0);
  assert.equal(kv.store.get(tripKey("trip_stopped")), before);
});

test("repair live (dry_run:false) finalizes only the terminal linked street ride", async () => {
  const kv = seedKV();
  const api = bookingApi();
  const env = { ADMIN_TOKEN: ADMIN, FLUXIDI_TRACKING: kv, BOOKING_API: api };

  const res = await worker.fetch(repairReq({ ...scope, dry_run: false }), env, {});
  const json = await res.json();

  assert.equal(json.dry_run, false);
  assert.equal(json.summary.repairable, 1);
  assert.equal(json.summary.errors, 0);
  // finalize-direct called exactly once (only for trip_stopped).
  assert.equal(api.calls.length, 1);
  assert.equal(api.calls[0].booking_id, "street_stopped_ab");
  // trip_stopped is now completed.
  const stopped = JSON.parse(kv.store.get(tripKey("trip_stopped")));
  assert.equal(stopped.booking_finalize_state, "completed");
  // Planned booking untouched (no finalize state written).
  const planned = JSON.parse(kv.store.get(tripKey("trip_planned")));
  assert.equal(planned.booking_finalize_state, undefined);
  // Active trip not completed.
  const active = JSON.parse(kv.store.get(tripKey("trip_active")));
  assert.notEqual(active.booking_finalize_state, "completed");
  // Already-completed trip not re-called / unchanged.
  const done = JSON.parse(kv.store.get(tripKey("trip_done")));
  assert.equal(done.booking_finalize_state, "completed");
});

test("repair honours bounded batch size + cursor continuation", async () => {
  const kv = seedKV();
  const api = bookingApi();
  const env = { ADMIN_TOKEN: ADMIN, FLUXIDI_TRACKING: kv, BOOKING_API: api };

  const first = await (await worker.fetch(repairReq({ ...scope, limit: 2 }), env, {})).json();
  assert.equal(first.scanned, 2);
  assert.equal(first.cursor, 2);
  const second = await (await worker.fetch(repairReq({ ...scope, limit: 2, cursor: 2 }), env, {})).json();
  assert.equal(second.scanned, 2);
  assert.equal(second.cursor, 4);
  const third = await (await worker.fetch(repairReq({ ...scope, limit: 2, cursor: 4 }), env, {})).json();
  assert.equal(third.scanned, 1);
  assert.equal(third.cursor, null); // exhausted
});
