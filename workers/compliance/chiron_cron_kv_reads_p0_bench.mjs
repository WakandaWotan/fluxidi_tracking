// CHIRON-CRON-KV-READS-P0 — before/after KV read bench.
//
// Same fixture, same entry point, two worker builds:
//   worker_prepatch.mjs  = deployed 331ffa95 (live v89 source)
//   worker_postpatch.mjs = 331ffa95 + pass-scoped preload
//
// Hermetic: in-memory KV, outbound fetch trapped. No Chiron submission.
//   node bench.mjs

import { __testInternals as PRE } from "./worker_prepatch.mjs";
import { __testInternals as POST } from "./worker_postpatch.mjs";

const ACC_URL = "https://mow-acc.api.vlaanderen.be/chiron/taxirit";
const TENANT_A = "T_bench_a";
const COMPANY_A = "C_bench_a";
const TENANT_B = "T_bench_b";
const COMPANY_B = "C_bench_b";

const outbound = [];
global.fetch = async (input) => {
  const href = typeof input === "string" ? input : input?.url || String(input);
  outbound.push(href);
  throw new Error(`hermetic bench: blocked outbound fetch to ${href}`);
};

const NOW_MS = Date.now();
const EVENT_BASE_MS = NOW_MS - 3 * 60 * 60 * 1000;
const TESTFLOW_STARTED_AT = new Date(NOW_MS - 7 * 24 * 60 * 60 * 1000).toISOString();

const eventIso = (seq, offsetSeconds = 0) =>
  new Date(EVENT_BASE_MS + seq * 60_000 + offsetSeconds * 1000).toISOString();

const completeFive = () => ({
  schema_version: "chiron_connection_status_v1",
  enabled: true,
  environment: "production",
  region: "flanders",
  production_enabled: false,
  test_credentials_stored: true,
  production_credentials_stored: true,
  last_connection_status: "test_passed",
  last_connection_test_at: "2026-08-03T07:00:00.000Z",
  testflow_auto_submit_enabled: true,
  testflow_started_at: TESTFLOW_STARTED_AT,
  test_departure_sent_count: 5,
  test_arrival_sent_count: 5,
  test_messages_sent_count: 10,
  test_rides_completed_count: 5,
  testflow_status: "complete",
});

function rideEvent(kind, tenantId, companyId, bookingId, seq) {
  const isStop = kind === "ride_stop";
  return {
    event_type: kind,
    event_id: `${kind}:${tenantId}:${companyId}:${bookingId}`,
    tenant_id: tenantId,
    company_id: companyId,
    booking_id: bookingId,
    trip_id: `trip_${bookingId}`,
    ride_type: "direct",
    created_at_utc: eventIso(seq, isStop ? 30 : 0),
    timestamps: {
      event_at_utc: eventIso(seq, isStop ? 30 : 0),
      started_at_utc: eventIso(seq, 0),
      ...(isStop ? { stopped_at_utc: eventIso(seq, 30) } : {}),
    },
    driver: { driver_id: "drv_1" },
    vehicle: { vehicle_id: "vh_1", license_plate: "TXABC123" },
    locations: {
      pickup: { lat: 50.7720114, lng: 3.6695565, label: "origin" },
      dropoff: { lat: 50.850504, lng: 3.482422, label: "dest" },
    },
    fare: { currency: "EUR", distance_km: 12.5, total_amount: 20 },
  };
}

function makeHarness(safeSegment, { scopes, bookingsPerScope, eventsPerBooking }) {
  const complianceStore = new Map();
  const bookingReads = [];
  const complianceReads = [];
  let complianceLists = 0;

  const eventKeyFor = (tenantId, companyId, seq, label) =>
    `compliance_event_v1/tenant/${safeSegment(tenantId, "")}/company/${safeSegment(
      companyId,
      "",
    )}/2026/08/03/${1000 + seq}_${label}`;

  for (const { tenantId, companyId } of scopes) {
    complianceStore.set(
      `tenant:${tenantId}:company:${companyId}:chiron_connection:v1`,
      JSON.stringify(completeFive()),
    );
    let seq = 0;
    for (let b = 0; b < bookingsPerScope; b += 1) {
      const bookingId = `street_${tenantId}_${String(b).padStart(3, "0")}`;
      const kinds = eventsPerBooking === 1 ? ["ride_stop"] : ["ride_start", "ride_stop"];
      for (const kind of kinds) {
        seq += 1;
        complianceStore.set(
          eventKeyFor(tenantId, companyId, seq, `${kind}_${b}`),
          JSON.stringify(rideEvent(kind, tenantId, companyId, bookingId, seq)),
        );
      }
    }
  }

  const env = {
    CHIRON_EXPORT_MODE: "test",
    CHIRON_EXPORT_BASE_URL: ACC_URL,
    COMPLIANCE_KV: {
      async get(key) {
        complianceReads.push(key);
        return complianceStore.get(key) ?? null;
      },
      async put(key, value) {
        complianceStore.set(key, value);
      },
      async list({ prefix = "", limit = 1000, cursor } = {}) {
        complianceLists += 1;
        const all = [...complianceStore.keys()].filter((k) => k.startsWith(prefix)).sort();
        const start = cursor
          ? Number(Buffer.from(String(cursor), "base64").toString("utf8")) || 0
          : 0;
        const slice = all.slice(start, start + limit);
        const next = start + slice.length;
        const complete = next >= all.length;
        return {
          keys: slice.map((name) => ({ name })),
          list_complete: complete,
          cursor: complete ? undefined : Buffer.from(String(next), "utf8").toString("base64"),
        };
      },
    },
    BOOKING_KV: {
      async get(key) {
        bookingReads.push(key);
        return null;
      },
    },
  };

  return {
    env,
    bookingReads,
    complianceReads,
    complianceListCount: () => complianceLists,
    bookingKeyReads: () => bookingReads.filter((k) => k.startsWith("booking:")),
    hydrationReads: () => bookingReads.filter((k) => !k.startsWith("booking:")),
  };
}

const shape = (outcome) => ({
  ok: outcome.ok,
  scanned: outcome.scanned,
  considered: outcome.considered,
  processed: outcome.processed,
  submitted: outcome.submitted,
  skipped: outcome.skipped,
  failed: outcome.failed,
  waiting_for_departure: outcome.waiting_for_departure,
});

async function runOne(internals, bookings, eventsPerBooking) {
  const h = makeHarness(internals.safeSegment, {
    scopes: [{ tenantId: TENANT_A, companyId: COMPANY_A }],
    bookingsPerScope: bookings,
    eventsPerBooking,
  });
  const outcome = await internals._chironAutoReconcileScopeBestEffort(
    h.env,
    TENANT_A,
    COMPANY_A,
    { source: "bench" },
  );
  return {
    outcome: shape(outcome),
    booking_kv_reads: h.bookingReads.length,
    booking_record_reads: h.bookingKeyReads().length,
    hydration_reads: h.hydrationReads().length,
    compliance_kv_reads: h.complianceReads.length,
    compliance_kv_lists: h.complianceListCount(),
  };
}

async function runTwoScopes(internals, bookings) {
  const h = makeHarness(internals.safeSegment, {
    scopes: [
      { tenantId: TENANT_A, companyId: COMPANY_A },
      { tenantId: TENANT_B, companyId: COMPANY_B },
    ],
    bookingsPerScope: bookings,
    eventsPerBooking: 2,
  });
  const summary = await internals._chironCronReconcileAllScopesBestEffort(h.env, {
    source: "cron",
  });
  const keys = h.bookingKeyReads();
  const crossA = keys.filter((k) => k.includes(TENANT_A)).length;
  const crossB = keys.filter((k) => k.includes(TENANT_B)).length;
  return {
    summary: { ok: summary.ok, scopes: summary.scopes, ran: summary.ran, failed: summary.failed },
    booking_kv_reads: h.bookingReads.length,
    scope_a_booking_reads: crossA,
    scope_b_booking_reads: crossB,
    leaked: keys.length - crossA - crossB,
  };
}

// Production-shaped: measured plateau was ~6,400 BOOKING_KV reads per tick with
// 20 processed events, i.e. ~317 distinct legless bookings behind the pass.
const BOOKINGS = 317;

const results = {
  fixture: {
    distinct_bookings: BOOKINGS,
    events_per_booking: 2,
    total_events: BOOKINGS * 2,
    note: "BOOKING_KV.get returns null so every distinct legless booking is read, as in production",
  },
  single_scope: {
    prepatch: await runOne(PRE, BOOKINGS, 2),
    postpatch: await runOne(POST, BOOKINGS, 2),
  },
  two_scopes_one_tick: {
    prepatch: await runTwoScopes(PRE, 40),
    postpatch: await runTwoScopes(POST, 40),
  },
  outbound_calls: outbound.length,
};

const pre = results.single_scope.prepatch;
const post = results.single_scope.postpatch;
results.verdict = {
  booking_kv_reads_before: pre.booking_kv_reads,
  booking_kv_reads_after: post.booking_kv_reads,
  reduction_factor: Number((pre.booking_kv_reads / post.booking_kv_reads).toFixed(1)),
  outcome_identical:
    JSON.stringify(pre.outcome) === JSON.stringify(post.outcome),
  compliance_scan_unchanged: pre.compliance_kv_reads === post.compliance_kv_reads,
  per_tick_after: post.booking_kv_reads,
  projected_daily_booking_kv_reads_288_ticks: post.booking_kv_reads * 288,
  projected_daily_before_288_ticks: pre.booking_kv_reads * 288,
};

console.log(JSON.stringify(results, null, 2));
