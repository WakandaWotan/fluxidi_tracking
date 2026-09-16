import assert from "node:assert/strict";
import test from "node:test";
import {
  applyRideActivityObservation,
  applyRideActivityObservations,
  markRideActivityHistoryComplete,
  observationFromBookingRecord,
  rideActivitySummaryKey,
  upsertRideActivitySummaryBestEffort,
} from "./ride_activity_summary.mjs";

const SCOPE = { tenant_id: "tenant_a", company_id: "cmp_a" };

function memoryKv(seed = {}) {
  const store = new Map(Object.entries(seed));
  return {
    store,
    async get(key, opts) {
      if (!store.has(key)) return null;
      const raw = store.get(key);
      if (opts?.type === "json") return typeof raw === "string" ? JSON.parse(raw) : raw;
      return raw;
    },
    async put(key, value) {
      store.set(key, value);
    },
  };
}

test("duplicate processing does not raise totals", () => {
  const first = applyRideActivityObservation(null, {
    ...SCOPE,
    booking_id: "ride_1",
    created_at: "2026-07-03T13:52:00.000Z",
    lifecycle_status: "created",
  });
  const again = applyRideActivityObservation(first.summary, {
    ...SCOPE,
    booking_id: "ride_1",
    created_at: "2026-07-03T13:52:00.000Z",
    lifecycle_status: "assigned",
  });
  assert.equal(first.summary.total_real_rides, 1);
  assert.equal(again.changed, false);
  assert.equal(again.summary.total_real_rides, 1);
  assert.equal(again.summary.history_complete, false);
});

test("a later older import can move the first timestamps earlier", () => {
  const newerFirst = applyRideActivityObservation(null, {
    ...SCOPE,
    booking_id: "ride_new",
    created_at: "2026-09-01T10:00:00.000Z",
    completed_at: "2026-09-01T11:00:00.000Z",
    lifecycle_status: "completed",
  });
  const olderImport = applyRideActivityObservation(newerFirst.summary, {
    ...SCOPE,
    booking_id: "ride_old",
    created_at: "2026-07-03T13:52:00.000Z",
    completed_at: "2026-07-07T06:24:00.000Z",
    lifecycle_status: "completed",
  });
  assert.equal(olderImport.summary.first_real_ride_id, "ride_old");
  assert.equal(olderImport.summary.first_real_ride_at, "2026-07-03T13:52:00.000Z");
  assert.equal(olderImport.summary.first_completed_ride_id, "ride_old");
  assert.equal(olderImport.summary.first_completed_ride_at, "2026-07-07T06:24:00.000Z");
  assert.equal(olderImport.summary.last_real_ride_id, "ride_new");
  assert.equal(olderImport.summary.total_real_rides, 2);
  assert.equal(olderImport.summary.total_completed_rides, 2);
});

test("created and completed milestones may come from different records", () => {
  const result = applyRideActivityObservations(null, [
    {
      ...SCOPE,
      booking_id: "ride_open",
      created_at: "2026-07-03T13:52:00.000Z",
      lifecycle_status: "assigned",
    },
    {
      ...SCOPE,
      booking_id: "ride_done",
      created_at: "2026-07-04T09:00:00.000Z",
      completed_at: "2026-07-07T06:24:00.000Z",
      lifecycle_status: "completed",
    },
  ]);
  assert.equal(result.summary.first_real_ride_id, "ride_open");
  assert.equal(result.summary.first_completed_ride_id, "ride_done");
});

test("incremental upsert writes once and stays incomplete until backfill marks it", async () => {
  const env = { BOOKING_KV: memoryKv() };
  const rec = {
    ...SCOPE,
    created_at: "2026-07-03T13:52:00.000Z",
    status: "ASSIGNED",
  };
  const first = await upsertRideActivitySummaryBestEffort(env, "ride_1", rec, SCOPE);
  const again = await upsertRideActivitySummaryBestEffort(env, "ride_1", rec, SCOPE);
  assert.equal(first.changed, true);
  assert.equal(again.skipped, true);
  const key = rideActivitySummaryKey(SCOPE.tenant_id, SCOPE.company_id);
  const stored = JSON.parse(env.BOOKING_KV.store.get(key));
  assert.equal(stored.kind, "ride_activity:v1");
  assert.equal(stored.history_complete, false);
  assert.equal(stored.total_real_rides, 1);
  const marked = markRideActivityHistoryComplete(stored);
  assert.equal(marked.summary.history_complete, true);
});

test("observation mapping reads nested booking clocks", () => {
  const observation = observationFromBookingRecord("ride_9", {
    booking: {
      created_at: "2026-07-03T13:52:00.000Z",
      completed_at: "2026-07-07T06:24:00.000Z",
      status: "completed",
    },
  }, SCOPE);
  assert.equal(observation.booking_id, "ride_9");
  assert.equal(observation.created_at, "2026-07-03T13:52:00.000Z");
  assert.equal(observation.completed_at, "2026-07-07T06:24:00.000Z");
});
