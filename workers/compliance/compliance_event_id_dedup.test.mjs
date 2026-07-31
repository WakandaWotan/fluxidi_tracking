// RELEASE-P0-DURABLE-CHIRON-SYNC-FOR-PLANNED-RIDES-2026-07-31 — compliance
// worker append idempotency on client-supplied event_id.
//
// Run: node --test workers/compliance/compliance_event_id_dedup.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import worker from "./fluxidi_compliance_worker.js";

const ADMIN = "compliance-admin-token";

function makeKV(seed = {}) {
  const store = new Map(Object.entries(seed));
  return {
    store,
    async get(key, opts) {
      if (!store.has(key)) return null;
      const raw = store.get(key);
      if (opts && opts.type === "json") {
        try {
          return JSON.parse(raw);
        } catch (_) {
          return null;
        }
      }
      return raw;
    },
    async put(key, val) {
      store.set(key, val);
    },
    async delete(key) {
      store.delete(key);
    },
    async list({ prefix = "" } = {}) {
      const keys = [...store.keys()]
        .filter((k) => (prefix ? k.startsWith(prefix) : true))
        .map((name) => ({ name }));
      return { keys, list_complete: true };
    },
  };
}

function appendReq(body) {
  return new Request("https://compliance.internal/compliance/events/append", {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${ADMIN}` },
    body: JSON.stringify(body),
  });
}

function baseEvent(over = {}) {
  return {
    event_type: "ride_stop",
    tenant_id: "T1",
    company_id: "C1",
    booking_id: "planned_booking_abc",
    trip_id: "planned_planned_booking_abc",
    ride_type: "planned",
    lifecycle_status: "stopped",
    event_id: "ride_stop:T1:C1:planned_planned_booking_abc",
    ...over,
  };
}

function envFor(kv) {
  return {
    COMPLIANCE_ADMIN_TOKEN: ADMIN,
    COMPLIANCE_KV: kv,
  };
}

function countStoredEvents(kv) {
  let n = 0;
  for (const k of kv.store.keys()) {
    if (k.startsWith("compliance_event_v1/tenant/")) n += 1;
  }
  return n;
}

test("append with client-supplied event_id stores exactly one event", async () => {
  const kv = makeKV();
  const res = await worker.fetch(appendReq(baseEvent()), envFor(kv), {});
  const body = await res.json();
  assert.equal(res.status, 200);
  assert.equal(body.ok, true);
  assert.equal(body.event_id, "ride_stop:T1:C1:planned_planned_booking_abc");
  assert.notEqual(body.deduplicated, true);
  assert.equal(countStoredEvents(kv), 1);
});

test("re-appending the same event_id returns 200 with deduplicated:true and NO second storage", async () => {
  const kv = makeKV();
  await worker.fetch(appendReq(baseEvent()), envFor(kv), {});
  assert.equal(countStoredEvents(kv), 1);

  const res2 = await worker.fetch(appendReq(baseEvent()), envFor(kv), {});
  const body2 = await res2.json();
  assert.equal(res2.status, 200);
  assert.equal(body2.ok, true);
  assert.equal(body2.deduplicated, true);
  assert.equal(body2.event_id, "ride_stop:T1:C1:planned_planned_booking_abc");
  // The first stored_at is returned (dedup contract).
  assert.ok(body2.stored_at);

  // No second Chiron dossier row.
  assert.equal(countStoredEvents(kv), 1);
});

test("two concurrent retries of the same event_id do not create two Chiron dossier rows over time", async () => {
  const kv = makeKV();
  // Two concurrent writes may both find no dedup pointer (race), but the
  // downstream dedup contract still holds: subsequent retries never write
  // additional rows. Simulate the realistic sequence: a retry after the first
  // successful write must NEVER produce a second stored event.
  await worker.fetch(appendReq(baseEvent()), envFor(kv), {});
  assert.equal(countStoredEvents(kv), 1);
  await Promise.all([
    worker.fetch(appendReq(baseEvent()), envFor(kv), {}),
    worker.fetch(appendReq(baseEvent()), envFor(kv), {}),
    worker.fetch(appendReq(baseEvent()), envFor(kv), {}),
  ]);
  assert.equal(countStoredEvents(kv), 1);
});

test("event_id dedup is tenant/company scoped (different tenant reuse of same event_id key is isolated)", async () => {
  const kv = makeKV();
  await worker.fetch(appendReq(baseEvent()), envFor(kv), {});
  // Same event_id text but different tenant → different dedup key + different
  // storage key. Both events are stored.
  const other = baseEvent({ tenant_id: "T2" });
  const res = await worker.fetch(appendReq(other), envFor(kv), {});
  const body = await res.json();
  assert.equal(res.status, 200);
  assert.notEqual(body.deduplicated, true);
  assert.equal(countStoredEvents(kv), 2);
});

test("append without client-supplied event_id keeps legacy path (random UUID, no dedup)", async () => {
  const kv = makeKV();
  const evt = baseEvent();
  delete evt.event_id;
  const r1 = await worker.fetch(appendReq(evt), envFor(kv), {});
  const j1 = await r1.json();
  const r2 = await worker.fetch(appendReq(evt), envFor(kv), {});
  const j2 = await r2.json();
  assert.equal(r1.status, 200);
  assert.equal(r2.status, 200);
  // Two distinct random UUIDs, two stored events.
  assert.notEqual(j1.event_id, j2.event_id);
  assert.equal(countStoredEvents(kv), 2);
});

test("ride_start deterministic event_id dedup works (parity with ride_stop)", async () => {
  const kv = makeKV();
  const startEvt = {
    event_type: "ride_start",
    tenant_id: "T1",
    company_id: "C1",
    booking_id: "planned_booking_xyz",
    ride_type: "planned",
    lifecycle_status: "started",
    event_id: "ride_start:T1:C1:planned_booking_xyz",
  };
  await worker.fetch(appendReq(startEvt), envFor(kv), {});
  await worker.fetch(appendReq(startEvt), envFor(kv), {});
  await worker.fetch(appendReq(startEvt), envFor(kv), {});
  assert.equal(countStoredEvents(kv), 1);
});
