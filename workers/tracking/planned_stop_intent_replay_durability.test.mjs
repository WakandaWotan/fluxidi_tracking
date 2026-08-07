// PLANNED-STOP-HISTORY-DURABILITY-P0-8 — handler tests proving that replaying a
// durable planned STOP intent is safe and materializes Driver History exactly
// once.
//
// Field incident: PLN-2026-000387 / booking 2026-08-168. The OUTBOUND leg became
// COMPLETED while `/trip/record-planned-stop` never landed, so there was no
// tracking trip, no trips_index/driver-history row, no Chiron ride_stop and no
// consumer_sale. `/trip/record-planned-stop` is the ONLY writer of that chain and
// neither `/trip/reconcile-planned-stop` nor `/trip/recover-planned-pending` can
// create a trip row that was never written — they only reconcile existing rows.
//
// The client fix persists the measured STOP payload as a durable intent before
// the booking is projected COMPLETED, then replays it verbatim until the worker
// confirms. These tests pin the server-side properties that make that replay
// safe:
//   - a replayed stop yields exactly ONE trip row and ONE trips_index /
//     driver-index entry (no duplicate Driver History row);
//   - the Chiron ride_stop event_id stays deterministic across replays, so
//     downstream dedupe collapses them to a single compliance event;
//   - the booking-completion bridge is driven from the same deterministic
//     identity, so consumer_sale / Billit cannot be double-registered;
//   - a stop that was lost entirely is still fully materializable later;
//   - street/direct rides are untouched by this path.
//
// Run: node --test workers/tracking/planned_stop_intent_replay_durability.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import worker from "./fluxidi_tracking_api_worker_V2_1_with_route_index.js";

const ADMIN = "test-admin-token";
const SCOPE = { tenant_id: "T1", company_id: "C1" };

const BOOKING_ID = "2026-08-168";
const LEG_ID = "leg-outbound-1";
const DRIVER_ID = "D1";

// Mirrors `plannedStopTripId` in lib/main_parts/planned_stop_durability.dart and
// the worker's own derivation. If these ever diverge, a replay would address a
// different trip and duplicate history.
const TRIP_ID = `planned_${BOOKING_ID}_${LEG_ID}`;
const TRIP_KEY = `tenant:T1:company:C1:trip:${TRIP_ID}`;
const TRIPS_INDEX_KEY = "tenant:T1:company:C1:trips_index";
const DRIVER_INDEX_KEY = `tenant:T1:company:C1:trips_index:driver:${DRIVER_ID}`;

function makeKV(seed = {}) {
  const store = new Map(Object.entries(seed));
  return {
    store,
    async get(key, opts) {
      if (!store.has(key)) return null;
      const raw = store.get(key);
      if (opts && opts.type === "json") {
        try {
          return typeof raw === "string" ? JSON.parse(raw) : raw;
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

function bookingApi({ fare = 9.6 } = {}) {
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

function recordPlannedStopReq(body) {
  return new Request("https://track.internal/trip/record-planned-stop", {
    method: "POST",
    headers: { "content-type": "application/json", "x-admin-token": ADMIN },
    body: JSON.stringify(body),
  });
}

/// The exact body a durable intent stores and replays verbatim: measured
/// distance, measured waiting time, real stop timestamp.
function intentPayload(over = {}) {
  return {
    ...SCOPE,
    trip_id: TRIP_ID,
    booking_id: BOOKING_ID,
    parent_booking_id: BOOKING_ID,
    leg_id: LEG_ID,
    leg_type: "outbound",
    row_key: "row-1",
    driver_id: DRIVER_ID,
    vehicle_id: "V1",
    status: "stopped",
    started_at: "2026-08-07T04:51:12.000Z",
    stopped_at: "2026-08-07T05:09:58.000Z",
    km_total: 7.4,
    wait_seconds_total: 185,
    total_eur: 9.6,
    currency: "EUR",
    ...over,
  };
}

function envFor({ kv, compliance, booking, bookingKv, extra = {} } = {}) {
  return {
    COMPLIANCE_API_URL: "https://compliance.internal",
    COMPLIANCE_ADMIN_TOKEN: "compliance-admin-token",
    ADMIN_TOKEN: ADMIN,
    FLUXIDI_TRACKING: kv,
    COMPLIANCE_WORKER: compliance,
    BOOKING_API: booking ?? bookingApi(),
    ...(bookingKv ? { BOOKING_KV: bookingKv } : {}),
    ...extra,
  };
}

function indexOf(kv, key) {
  const raw = kv.store.get(key);
  return raw ? JSON.parse(raw) : null;
}

function occurrences(arr, value) {
  return (arr ?? []).filter((x) => x === value).length;
}

// ---------------------------------------------------------------------------
// Scenario 3 + 7: a stop lost to poor network is fully materializable later,
// exactly once.
// ---------------------------------------------------------------------------

test("replaying a stranded planned STOP intent materializes trip + history exactly once", async () => {
  const kv = makeKV();
  const compliance = complianceWorker(
    () => new Response(JSON.stringify({ ok: true }), { status: 200 }),
  );
  const env = envFor({ kv, compliance });

  // First attempt: this is the request that was lost in the field. Nothing
  // exists yet, which is precisely why no server recovery route could help.
  assert.equal(kv.store.get(TRIP_KEY), undefined);
  assert.equal(indexOf(kv, TRIPS_INDEX_KEY), null);

  const ctx1 = makeCtx();
  const res1 = await worker.fetch(
    recordPlannedStopReq(intentPayload()),
    env,
    ctx1,
  );
  const body1 = await res1.json();
  await ctx1.flush();

  assert.equal(res1.status, 200);
  assert.equal(body1.ok, true);
  assert.equal(body1.trip_id, TRIP_ID);

  // The durable chain now exists: trip row + company index + driver index.
  const stored = JSON.parse(kv.store.get(TRIP_KEY));
  assert.equal(stored.kind, "planned");
  assert.equal(stored.status, "stopped");
  assert.equal(stored.km_total, 7.4);
  assert.equal(stored.wait_seconds_total, 185);
  assert.equal(occurrences(indexOf(kv, TRIPS_INDEX_KEY), TRIP_ID), 1);
  assert.equal(occurrences(indexOf(kv, DRIVER_INDEX_KEY), TRIP_ID), 1);

  // Replay the identical intent twice more, as a drain retry would.
  for (const attempt of [2, 3]) {
    const ctx = makeCtx();
    const res = await worker.fetch(
      recordPlannedStopReq(intentPayload()),
      env,
      ctx,
    );
    await ctx.flush();
    assert.equal(res.status, 200, `replay ${attempt} must succeed`);
  }

  // Exactly ONE Driver History row survives: one trip key, one index entry.
  const tripKeys = [...kv.store.keys()].filter((k) =>
    k.startsWith("tenant:T1:company:C1:trip:"),
  );
  assert.deepEqual(tripKeys, [TRIP_KEY]);
  assert.equal(occurrences(indexOf(kv, TRIPS_INDEX_KEY), TRIP_ID), 1);
  assert.equal(occurrences(indexOf(kv, DRIVER_INDEX_KEY), TRIP_ID), 1);

  // Measured ride truth is unchanged by replay — nothing was recomputed.
  const finalTrip = JSON.parse(kv.store.get(TRIP_KEY));
  assert.equal(finalTrip.km_total, 7.4);
  assert.equal(finalTrip.wait_seconds_total, 185);
});

// ---------------------------------------------------------------------------
// Scenario 8: Chiron emits once / idempotently.
// ---------------------------------------------------------------------------

test("replayed STOP reuses one deterministic Chiron ride_stop event_id", async () => {
  const kv = makeKV();
  const compliance = complianceWorker(
    () => new Response(JSON.stringify({ ok: true }), { status: 200 }),
  );
  const env = envFor({ kv, compliance });

  for (let i = 0; i < 3; i++) {
    const ctx = makeCtx();
    await worker.fetch(recordPlannedStopReq(intentPayload()), env, ctx);
    await ctx.flush();
  }

  const stopEvents = compliance.calls.filter(
    (c) => c.event_type === "ride_stop",
  );
  assert.ok(stopEvents.length >= 1, "at least one ride_stop must be emitted");

  // Every emit carries the SAME deterministic id, so the compliance worker
  // collapses replays into a single Chiron event instead of duplicating a ride.
  const ids = new Set(stopEvents.map((e) => e.event_id));
  assert.deepEqual([...ids], [`ride_stop:T1:C1:${TRIP_ID}`]);
  for (const e of stopEvents) {
    assert.equal(e.ride_type, "planned");
    assert.equal(e.tenant_id, "T1");
    assert.equal(e.company_id, "C1");
    assert.equal(e.booking_id, BOOKING_ID);
    assert.equal(e.trip_id, TRIP_ID);
  }

  const stored = JSON.parse(kv.store.get(TRIP_KEY));
  assert.equal(stored.compliance_emit_event_id, `ride_stop:T1:C1:${TRIP_ID}`);
  assert.equal(stored.compliance_emit_state, "applied");
});

test("a replay after a failed Chiron emit still converges to applied without a second ride", async () => {
  const kv = makeKV();
  let attempts = 0;
  const compliance = complianceWorker(() => {
    attempts += 1;
    // Poor network: the first emit fails, a later replay succeeds.
    return attempts === 1
      ? new Response(JSON.stringify({ ok: false }), { status: 503 })
      : new Response(JSON.stringify({ ok: true }), { status: 200 });
  });
  const env = envFor({ kv, compliance });

  const ctx1 = makeCtx();
  await worker.fetch(recordPlannedStopReq(intentPayload()), env, ctx1);
  await ctx1.flush();
  assert.equal(JSON.parse(kv.store.get(TRIP_KEY)).compliance_emit_state, "pending");

  const ctx2 = makeCtx();
  await worker.fetch(recordPlannedStopReq(intentPayload()), env, ctx2);
  await ctx2.flush();

  const stored = JSON.parse(kv.store.get(TRIP_KEY));
  assert.equal(stored.compliance_emit_state, "applied");
  assert.equal(stored.compliance_emit_event_id, `ride_stop:T1:C1:${TRIP_ID}`);
  // Still exactly one history row.
  assert.equal(occurrences(indexOf(kv, TRIPS_INDEX_KEY), TRIP_ID), 1);
});

// ---------------------------------------------------------------------------
// Scenario 10: no consumer / Billit duplication.
// ---------------------------------------------------------------------------

test("booking completion bridge is driven from one stable identity across replays", async () => {
  const kv = makeKV();
  const compliance = complianceWorker(
    () => new Response(JSON.stringify({ ok: true }), { status: 200 }),
  );
  const booking = bookingApi();
  const env = envFor({ kv, compliance, booking });

  for (let i = 0; i < 3; i++) {
    const ctx = makeCtx();
    await worker.fetch(recordPlannedStopReq(intentPayload()), env, ctx);
    await ctx.flush();
  }

  const completions = booking.calls.filter((c) =>
    c.path.includes("complete-from-planned-stop"),
  );
  assert.ok(completions.length >= 1, "planned stop must drive booking completion");

  // Identical booking + leg + trip identity every time. Downstream leg
  // completion and consumer_sale registration are keyed on exactly these, so
  // repeated bridge calls cannot create a second sale or Billit document.
  for (const c of completions) {
    assert.equal(c.body.booking_id, BOOKING_ID);
    assert.equal(c.body.leg_id, LEG_ID);
    assert.equal(c.body.trip_id, TRIP_ID);
  }
});

// ---------------------------------------------------------------------------
// Leg isolation: an outbound replay must never touch the return leg.
// ---------------------------------------------------------------------------

test("outbound and return legs materialize as separate history rows", async () => {
  const kv = makeKV();
  const compliance = complianceWorker(
    () => new Response(JSON.stringify({ ok: true }), { status: 200 }),
  );
  const env = envFor({ kv, compliance });

  const returnLegId = "leg-return-1";
  const returnTripId = `planned_${BOOKING_ID}_${returnLegId}`;

  const ctxA = makeCtx();
  await worker.fetch(recordPlannedStopReq(intentPayload()), env, ctxA);
  await ctxA.flush();

  const ctxB = makeCtx();
  await worker.fetch(
    recordPlannedStopReq(
      intentPayload({
        trip_id: returnTripId,
        leg_id: returnLegId,
        leg_type: "return",
        row_key: "row-2",
      }),
    ),
    env,
    ctxB,
  );
  await ctxB.flush();

  assert.ok(kv.store.get(TRIP_KEY), "outbound trip must exist");
  assert.ok(
    kv.store.get(`tenant:T1:company:C1:trip:${returnTripId}`),
    "return trip must exist",
  );
  const index = indexOf(kv, TRIPS_INDEX_KEY);
  assert.equal(occurrences(index, TRIP_ID), 1);
  assert.equal(occurrences(index, returnTripId), 1);
});

// ---------------------------------------------------------------------------
// Scenario 11: street ride behaviour unchanged.
// ---------------------------------------------------------------------------

test("street/direct rides remain refused by the shadow guard and write nothing", async () => {
  const directTripId = "trip_direct_1";
  const kv = makeKV({
    [`tenant:T1:company:C1:trip:${directTripId}`]: JSON.stringify({
      trip_id: directTripId,
      kind: "direct",
      status: "stopped",
      tenant_id: "T1",
      company_id: "C1",
    }),
  });
  const bookingKv = makeKV({
    "booking:street-1": JSON.stringify({
      booking_id: "street-1",
      tenant_id: "T1",
      company_id: "C1",
      source: "street_ride",
      ride_type: "direct",
      tracking_trip_id: directTripId,
    }),
  });
  const compliance = complianceWorker(
    () => new Response(JSON.stringify({ ok: true }), { status: 200 }),
  );
  const env = envFor({ kv, compliance, bookingKv });
  const ctx = makeCtx();

  const before = new Set(kv.store.keys());
  const res = await worker.fetch(
    recordPlannedStopReq(
      intentPayload({
        trip_id: "planned_street-1",
        booking_id: "street-1",
        parent_booking_id: "street-1",
        leg_id: "",
        row_key: "",
      }),
    ),
    env,
    ctx,
  );
  const body = await res.json();
  await ctx.flush();

  assert.equal(res.status, 200);
  assert.equal(body.skipped, true);
  // No planned shadow trip, no new index entry: street history stays owned by
  // /trip/start-direct + /trip/stop.
  assert.deepEqual([...kv.store.keys()], [...before]);
  assert.equal(compliance.calls.length, 0);
});

// ---------------------------------------------------------------------------
// Identity contract shared with the Flutter client.
// ---------------------------------------------------------------------------

test("worker derives the planned trip_id the client replay assumes", async () => {
  const kv = makeKV();
  const compliance = complianceWorker(
    () => new Response(JSON.stringify({ ok: true }), { status: 200 }),
  );
  const env = envFor({ kv, compliance });

  // No trip_id supplied: the worker must derive the same value the client's
  // `plannedStopTripId` computes, otherwise replay would fork the history row.
  const ctx = makeCtx();
  const res = await worker.fetch(
    recordPlannedStopReq(intentPayload({ trip_id: undefined })),
    env,
    ctx,
  );
  const body = await res.json();
  await ctx.flush();

  assert.equal(body.trip_id, TRIP_ID);

  // And with no leg identity at all it collapses to `planned_{booking_id}`.
  const kv2 = makeKV();
  const env2 = envFor({ kv: kv2, compliance: complianceWorker(
    () => new Response(JSON.stringify({ ok: true }), { status: 200 }),
  ) });
  const ctx2 = makeCtx();
  const res2 = await worker.fetch(
    recordPlannedStopReq(
      intentPayload({ trip_id: undefined, leg_id: "", row_key: "" }),
    ),
    env2,
    ctx2,
  );
  const body2 = await res2.json();
  await ctx2.flush();
  assert.equal(body2.trip_id, `planned_${BOOKING_ID}`);
});
