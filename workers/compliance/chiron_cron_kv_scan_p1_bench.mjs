// Counted old-vs-new COMPLIANCE_KV ops. No live Chiron, booking or payment.
//   node workers/compliance/chiron_cron_kv_scan_p1_bench.mjs
// Writes workers/compliance/chiron_cron_kv_scan_p1_bench_out.json when the
// scale run reaches migration_done. A timeout without that flag is not proof.

import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { __testInternals } from "./fluxidi_compliance_worker.js";
import {
  CHIRON_RECONCILE_DUE_PREFIX,
  armChironDueMarker,
  markChironDueMigrationComplete,
} from "./chiron_reconcile_due_index.js";

const {
  _chironCronReconcileAllScopesBestEffort,
  _chironAutoReconcileScopeBestEffort,
  _chironMarkScopeDueMigrationComplete,
  CHIRON_SCOPE_DUE_MIGRATION_BATCH,
  buildChironExportStatusKey,
  safeSegment,
} = __testInternals;

const NOW_MS = Date.parse("2026-09-21T12:00:00.000Z");
const TENANT = "T_bench_p1";
const COMPANY = "C_bench_p1";
const ACC = "https://mow-acc.api.vlaanderen.be/chiron/taxirit";
const OUT_PATH = join(dirname(fileURLToPath(import.meta.url)), "chiron_cron_kv_scan_p1_bench_out.json");

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

function rideEvent(kind, bookingId, seq, tenant = TENANT, company = COMPANY) {
  const created = new Date(NOW_MS - 3 * 60 * 60 * 1000 + seq * 60_000).toISOString();
  return {
    event_type: kind,
    event_id: `${kind}:${tenant}:${company}:${bookingId}`,
    tenant_id: tenant,
    company_id: company,
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
    compliance,
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
    if (!isWaiting) continue;
    const start = rideEvent("ride_start", `old_${i}`, i);
    await h.env.COMPLIANCE_KV.put(
      buildChironExportStatusKey(t, c, `candidate_v1:${start.event_id}`),
      JSON.stringify({
        sync_state: "failed",
        failure_kind: "definitive",
        outbound_fingerprint_definitive_attempts: 6,
        last_attempt_at: new Date(NOW_MS - 60_000).toISOString(),
        official_status: "vertrek",
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
rows.migration = migH.snapshot();
migH.reset();
await _chironCronReconcileAllScopesBestEffort(migH.env, {
  source: "cron",
  nowMs: NOW_MS + 60_000,
});
rows.second_tick_after_migration = migH.snapshot();

const quietH = createEnv();
await seedHistory(quietH, HISTORY, { synced: true, waiting: 0 });
await _chironMarkScopeDueMigrationComplete(quietH.env, TENANT, COMPANY, NOW_MS);
await markChironDueMigrationComplete(quietH.env.COMPLIANCE_KV, {
  now: new Date(NOW_MS),
});
quietH.reset();
await _chironCronReconcileAllScopesBestEffort(quietH.env, {
  source: "cron",
  nowMs: NOW_MS,
});
rows.quiet_no_due_work = quietH.snapshot();
quietH.reset();
await _chironCronReconcileAllScopesBestEffort(quietH.env, {
  source: "cron",
  nowMs: NOW_MS + 300_000,
});
rows.quiet_repeat_tick = quietH.snapshot();

const waitH = createEnv();
await seedHistory(waitH, HISTORY, { synced: true, waiting: 3 });
waitH.reset();
let waitMig = await _chironCronReconcileAllScopesBestEffort(waitH.env, {
  source: "cron",
  nowMs: NOW_MS,
});
rows.waiting_three_arrivals_migration = {
  ...waitH.snapshot(),
  due_selected: waitMig.due_selected,
  migration_done: waitMig.migration_done === true,
};
let waitTicks = 1;
while (!waitMig.migration_done && waitTicks < 8) {
  waitMig = await _chironCronReconcileAllScopesBestEffort(waitH.env, {
    source: "cron",
    nowMs: NOW_MS + waitTicks * 60_000,
  });
  waitTicks += 1;
}
waitH.reset();
const waitQuiet = await _chironCronReconcileAllScopesBestEffort(waitH.env, {
  source: "cron",
  nowMs: NOW_MS + 60_000,
});
rows.waiting_three_arrivals_before_due = {
  ...waitH.snapshot(),
  due_selected: waitQuiet.due_selected,
  note: "T+60s is before last_attempt+5min; not a due-at measurement",
};
waitH.reset();
const waitDue1 = await _chironCronReconcileAllScopesBestEffort(waitH.env, {
  source: "cron",
  nowMs: NOW_MS + 300_000,
});
rows.waiting_three_arrivals_first_due_at = {
  ...waitH.snapshot(),
  due_selected: waitDue1.due_selected,
  now_offset_ms: 300_000,
};
const waitT = safeSegment(TENANT, "");
const waitC = safeSegment(COMPANY, "");
for (const [key, row] of waitH.compliance) {
  if (!String(key).includes("chiron_export_status_v1")) continue;
  if (!/old_[0-2]/.test(String(key))) continue;
  try {
    const doc = JSON.parse(row.value);
    doc.last_attempt_at = new Date(NOW_MS + 300_000).toISOString();
    await waitH.env.COMPLIANCE_KV.put(key, JSON.stringify(doc));
  } catch (_) {}
}
for (let i = 0; i < 3; i += 1) {
  const waitKey = `compliance_event_v1/tenant/${waitT}/company/${waitC}/2026/09/21/${String(
    1_780_000_000_000 + i,
  ).padStart(13, "0")}_old_${i}`;
  await armChironDueMarker(waitH.env.COMPLIANCE_KV, waitKey, NOW_MS + 600_000);
}
waitH.reset();
const waitDue2 = await _chironCronReconcileAllScopesBestEffort(waitH.env, {
  source: "cron",
  nowMs: NOW_MS + 600_000,
});
rows.waiting_three_arrivals_second_due_at = {
  ...waitH.snapshot(),
  due_selected: waitDue2.due_selected,
  now_offset_ms: 600_000,
};

const newWorkH = createEnv();
await seedHistory(newWorkH, HISTORY, { synced: true, waiting: 0 });
await _chironMarkScopeDueMigrationComplete(newWorkH.env, TENANT, COMPANY, NOW_MS);
await markChironDueMigrationComplete(newWorkH.env.COMPLIANCE_KV, {
  now: new Date(NOW_MS),
});
const tNew = safeSegment(TENANT, "");
const cNew = safeSegment(COMPANY, "");
const newAt = NOW_MS - 15_000;
const newEvent = {
  ...rideEvent("ride_start", "new_work", 500),
  created_at_utc: new Date(newAt).toISOString(),
};
const newKey = `compliance_event_v1/tenant/${tNew}/company/${cNew}/2026/09/21/${String(
  newAt,
).padStart(13, "0")}_${safeSegment(newEvent.event_id, "evt")}`;
await newWorkH.env.COMPLIANCE_KV.put(newKey, JSON.stringify(newEvent));
newWorkH.reset();
const newWork = await _chironCronReconcileAllScopesBestEffort(newWorkH.env, {
  source: "cron",
  nowMs: NOW_MS,
});
rows.new_work = {
  ...newWorkH.snapshot(),
  due_selected: newWork.due_selected,
  recovered_unmarked: newWork.recovered_unmarked,
  new_event_read: newWorkH.eventReads.includes(newKey),
};

const TENANT_B = "T_bench_p1_b";
const COMPANY_B = "C_bench_p1_b";
const SCALE_A = 1552;
const SCALE_B = 80;

async function seedScale(h, tenant, company, n) {
  await h.env.COMPLIANCE_KV.put(
    `tenant:${tenant}:company:${company}:chiron_connection:v1`,
    JSON.stringify(connectionDoc()),
  );
  const t = safeSegment(tenant, "");
  const c = safeSegment(company, "");
  for (let i = 0; i < n; i += 1) {
    const event = {
      ...rideEvent("ride_stop", `${company}_${i}`, i, tenant, company),
      tenant_id: tenant,
      company_id: company,
      event_id: `ride_stop:${tenant}:${company}:${company}_${i}`,
    };
    const key = `compliance_event_v1/tenant/${t}/company/${c}/2026/09/21/${String(
      1_780_100_000_000 + i,
    ).padStart(13, "0")}_old_${i}`;
    await h.env.COMPLIANCE_KV.put(key, JSON.stringify(event));
  }
}

const scaleH = createEnv();
await seedScale(scaleH, TENANT, COMPANY, SCALE_A);
await seedScale(scaleH, TENANT_B, COMPANY_B, SCALE_B);
scaleH.reset();
const scaleStarted = Date.now();
const scaleFirst = await _chironCronReconcileAllScopesBestEffort(scaleH.env, {
  source: "cron",
  nowMs: NOW_MS,
});
const scaleFirstSnap = scaleH.snapshot();
const scaleFirstKvOps =
  scaleFirstSnap.reads +
  scaleFirstSnap.writes +
  scaleFirstSnap.lists +
  scaleFirstSnap.deletes;
rows.scale_1552_first_tick = {
  ...scaleFirstSnap,
  ms: Date.now() - scaleStarted,
  kvOps: scaleFirstKvOps,
  subrequest_budget: 1000,
  under_budget: scaleFirstKvOps < 1000,
  migration_done: scaleFirst.migration_done === true,
  batch: CHIRON_SCOPE_DUE_MIGRATION_BATCH,
  examined: scaleFirst.migration_examined,
};

const liveAt = NOW_MS + 45_000;
const liveEvent = {
  ...rideEvent("ride_start", "during_mig", 900),
  created_at_utc: new Date(liveAt).toISOString(),
};
const liveKey = `compliance_event_v1/tenant/${tNew}/company/${cNew}/2026/09/21/${String(
  liveAt,
).padStart(13, "0")}_${safeSegment(liveEvent.event_id, "evt")}`;
await scaleH.env.COMPLIANCE_KV.put(liveKey, JSON.stringify(liveEvent));
scaleH.reset();
const scaleLive = await _chironCronReconcileAllScopesBestEffort(scaleH.env, {
  source: "cron",
  nowMs: NOW_MS + 300_000,
});
rows.new_ride_during_migration = {
  ...scaleH.snapshot(),
  migration_done: scaleLive.migration_done === true,
  due_selected: scaleLive.due_selected,
  recovered_unmarked: scaleLive.recovered_unmarked,
  new_ride_read: scaleH.eventReads.includes(liveKey),
  waited_for_full_history: scaleLive.migration_done === true,
};

let scaleTicks = 2;
let scaleLast = scaleLive;
let scaleExamined = (Number(scaleFirst.migration_examined) || 0) +
  (Number(scaleLive.migration_examined) || 0);
const scaleResumeStarted = Date.now();
while (!scaleLast.migration_done && scaleTicks < 80) {
  scaleH.reset();
  scaleLast = await _chironCronReconcileAllScopesBestEffort(scaleH.env, {
    source: "cron",
    nowMs: NOW_MS + scaleTicks * 300_000,
  });
  scaleExamined += Number(scaleLast.migration_examined) || 0;
  scaleTicks += 1;
}
const scaleFinished = scaleLast.migration_done === true;
rows.scale_1552_complete = {
  ticks: scaleTicks,
  ms: Date.now() - scaleStarted,
  resume_ms: Date.now() - scaleResumeStarted,
  migration_done: scaleFinished,
  examined_total: scaleExamined,
  expected_events: SCALE_A + SCALE_B,
  last_tick: scaleH.snapshot(),
  finished: scaleFinished && scaleExamined >= SCALE_A + SCALE_B,
};

if (!scaleFinished) {
  throw new Error(
    `scale run did not finish: ticks=${scaleTicks} examined=${scaleExamined}`,
  );
}

const report = {
  history_events: HISTORY,
  scale_events: { a: SCALE_A, b: SCALE_B },
  cron_interval_ms: 300_000,
  rows,
  finished_at: new Date().toISOString(),
};

global.fetch = originalFetch;
writeFileSync(OUT_PATH, JSON.stringify(report, null, 2));
console.log(JSON.stringify(report, null, 2));
