// Counted old-vs-new COMPLIANCE_KV ops. No live Chiron, booking or payment.
//   node workers/compliance/chiron_cron_kv_scan_p1_bench.mjs

import { __testInternals } from "./fluxidi_compliance_worker.js";
import {
  CHIRON_RECONCILE_DUE_PREFIX,
  markChironDueMigrationComplete,
} from "./chiron_reconcile_due_index.js";

const {
  _chironCronReconcileAllScopesBestEffort,
  _chironAutoReconcileScopeBestEffort,
  buildChironExportStatusKey,
  safeSegment,
} = __testInternals;

const NOW_MS = Date.parse("2026-09-21T12:00:00.000Z");
const TENANT = "T_bench_p1";
const COMPANY = "C_bench_p1";
const ACC = "https://mow-acc.api.vlaanderen.be/chiron/taxirit";

function connectionDoc() {
  return {
    schema_version: "chiron_connection_status_v1",
    enabled: true,
    environment: "production",
    region: "flanders",
    production_enabled: false,
    test_credentials_stored: true,
    production_credentials_stored: true,
    last_connection_status: "test_passed",
    testflow_auto_submit_enabled: true,
    testflow_started_at: "2026-08-01T05:24:57.669Z",
    test_departure_sent_count: 5,
    test_arrival_sent_count: 5,
    test_messages_sent_count: 10,
    test_rides_completed_count: 5,
    testflow_status: "complete",
  };
}

function rideEvent(kind, bookingId, seq) {
  const created = new Date(NOW_MS - 3 * 60 * 60 * 1000 + seq * 60_000).toISOString();
  return {
    event_type: kind,
    event_id: `${kind}:${TENANT}:${COMPANY}:${bookingId}`,
    tenant_id: TENANT,
    company_id: COMPANY,
    booking_id: bookingId,
    trip_id: `trip_${bookingId}`,
    ride_type: "direct",
    created_at_utc: created,
    timestamps: { event_at_utc: created, started_at_utc: created },
    driver: { driver_id: "drv_1" },
    vehicle: { vehicle_id: "vh_1", license_plate: "TXABC123" },
    locations: {
      pickup: { lat: 50.772, lng: 3.67, label: "o" },
      dropoff: { lat: 50.85, lng: 3.48, label: "d" },
    },
    fare: { currency: "EUR", distance_km: 12.5, total_amount: 20 },
  };
}

function createEnv() {
  const compliance = new Map();
  const counts = { lists: 0, reads: 0, writes: 0, deletes: 0, bookingReads: 0 };
  const listPrefixes = [];
  const eventReads = [];
  const env = {
    CHIRON_EXPORT_MODE: "test",
    CHIRON_EXPORT_BASE_URL: ACC,
    COMPLIANCE_KV: {
      async get(key) {
        counts.reads += 1;
        if (String(key).startsWith("compliance_event_v1/")) eventReads.push(key);
        const row = compliance.get(key);
        return row ? row.value : null;
      },
      async put(key, value, opts = {}) {
        counts.writes += 1;
        compliance.set(key, {
          value: typeof value === "string" ? value : JSON.stringify(value),
          metadata: opts.metadata || null,
        });
      },
      async delete(key) {
        counts.deletes += 1;
        compliance.delete(key);
      },
      async list({ prefix = "", limit = 1000, cursor } = {}) {
        counts.lists += 1;
        listPrefixes.push(prefix);
        const all = [...compliance.keys()].filter((k) => k.startsWith(prefix)).sort();
        const start = cursor
          ? Number(Buffer.from(String(cursor), "base64").toString("utf8")) || 0
          : 0;
        const slice = all.slice(start, start + limit);
        const next = start + slice.length;
        const complete = next >= all.length;
        return {
          keys: slice.map((name) => ({
            name,
            metadata: compliance.get(name)?.metadata || null,
          })),
          list_complete: complete,
          cursor: complete
            ? undefined
            : Buffer.from(String(next), "utf8").toString("base64"),
        };
      },
    },
    BOOKING_KV: {
      async get() {
        counts.bookingReads += 1;
        return null;
      },
    },
  };
  return {
    env,
    counts,
    eventReads,
    listPrefixes,
    snapshot: () => ({
      reads: counts.reads,
      writes: counts.writes,
      lists: counts.lists,
      deletes: counts.deletes,
      bookingReads: counts.bookingReads,
      eventReads: eventReads.length,
      dueLists: listPrefixes.filter((p) => p === CHIRON_RECONCILE_DUE_PREFIX).length,
    }),
    reset() {
      counts.lists = 0;
      counts.reads = 0;
      counts.writes = 0;
      counts.deletes = 0;
      counts.bookingReads = 0;
      eventReads.length = 0;
      listPrefixes.length = 0;
    },
  };
}

async function seedHistory(h, n, { synced = false, waiting = 0 } = {}) {
  await h.env.COMPLIANCE_KV.put(
    `tenant:${TENANT}:company:${COMPANY}:chiron_connection:v1`,
    JSON.stringify(connectionDoc()),
  );
  const t = safeSegment(TENANT, "");
  const c = safeSegment(COMPANY, "");
  for (let i = 0; i < n; i += 1) {
    const event = rideEvent("ride_stop", `old_${i}`, i);
    const key = `compliance_event_v1/tenant/${t}/company/${c}/2026/09/21/${String(
      1_780_000_000_000 + i,
    ).padStart(13, "0")}_old_${i}`;
    await h.env.COMPLIANCE_KV.put(key, JSON.stringify(event));
    if (!synced) continue;
    const statusKey = buildChironExportStatusKey(
      t,
      c,
      `candidate_v1:${event.event_id}`,
    );
    const isWaiting = i < waiting;
    await h.env.COMPLIANCE_KV.put(
      statusKey,
      JSON.stringify({
        sync_state: isWaiting ? "waiting_for_departure" : "synced",
        last_attempt_at: new Date(NOW_MS - (isWaiting ? 0 : 60_000)).toISOString(),
        official_status: "aankomst",
      }),
    );
  }
}

const originalFetch = global.fetch;
global.fetch = async (input) => {
  const href = typeof input === "string" ? input : input?.url || String(input);
  throw new Error(`hermetic bench: blocked ${href}`);
};

const HISTORY = 80;
const rows = {};

const oldH = createEnv();
await seedHistory(oldH, HISTORY);
oldH.reset();
await _chironAutoReconcileScopeBestEffort(oldH.env, TENANT, COMPANY, {
  source: "old_scan",
  nowMs: NOW_MS,
});
rows.old_full_scan_one_tick = oldH.snapshot();

const migH = createEnv();
await seedHistory(migH, HISTORY);
migH.reset();
await _chironCronReconcileAllScopesBestEffort(migH.env, {
  source: "cron",
  nowMs: NOW_MS,
});
rows.first_tick_migration = migH.snapshot();
migH.reset();
await _chironCronReconcileAllScopesBestEffort(migH.env, {
  source: "cron",
  nowMs: NOW_MS + 60_000,
});
rows.second_tick_after_migration = migH.snapshot();

const idleH = createEnv();
await seedHistory(idleH, HISTORY);
await markChironDueMigrationComplete(idleH.env.COMPLIANCE_KV, {
  now: new Date(NOW_MS),
});
idleH.reset();
await _chironCronReconcileAllScopesBestEffort(idleH.env, {
  source: "cron",
  nowMs: NOW_MS,
});
rows.idle_after_done = idleH.snapshot();
idleH.reset();
await _chironCronReconcileAllScopesBestEffort(idleH.env, {
  source: "cron",
  nowMs: NOW_MS + 300_000,
});
rows.idle_repeat_tick = idleH.snapshot();

const prodH = createEnv();
await seedHistory(prodH, HISTORY, { synced: true, waiting: 3 });
prodH.reset();
await _chironCronReconcileAllScopesBestEffort(prodH.env, {
  source: "cron",
  nowMs: NOW_MS,
});
rows.prod_shaped_first_tick_migration = prodH.snapshot();
prodH.reset();
await _chironCronReconcileAllScopesBestEffort(prodH.env, {
  source: "cron",
  nowMs: NOW_MS + 60_000,
});
rows.prod_shaped_lasting_tick = prodH.snapshot();

global.fetch = originalFetch;
console.log(JSON.stringify({ history_events: HISTORY, rows }, null, 2));
