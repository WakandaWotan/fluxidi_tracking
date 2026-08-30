// KV-CRON-AMPLIFIERS-P0 — counting tests for Compliance cron / status poll.
// Hermetic in-memory KV. No live Cloudflare or Chiron.

import { test } from "node:test";
import assert from "node:assert/strict";

import worker, { __testInternals } from "./fluxidi_compliance_worker.js";
import {
  wrapKvBudget,
  KvBudgetExceededError,
  noteIsolateReads,
  resetIsolateKvBudgetForTests,
} from "./modules/kv_op_budget.js";

const { _chironAutoReconcileScopeBestEffort, CHIRON_RECONCILE_MAX_KV_READS } =
  __testInternals;

function countingKV(seed = {}) {
  const store = new Map();
  for (const [key, value] of Object.entries(seed)) {
    store.set(key, typeof value === "string" ? value : JSON.stringify(value));
  }
  const counts = { get: 0, list: 0, put: 0, delete: 0, got: [], listed: [] };
  return {
    store,
    counts,
    async get(key, opts) {
      counts.get += 1;
      counts.got.push(key);
      if (!store.has(key)) return null;
      const raw = store.get(key);
      if (opts && (opts === "json" || opts.type === "json")) {
        try {
          return typeof raw === "string" ? JSON.parse(raw) : raw;
        } catch (_) {
          return null;
        }
      }
      return raw;
    },
    async put(key, val) {
      counts.put += 1;
      store.set(key, val);
    },
    async delete(key) {
      counts.delete += 1;
      store.delete(key);
    },
    async list({ prefix = "", limit = 1000, cursor } = {}) {
      counts.list += 1;
      counts.listed.push(prefix);
      const names = [...store.keys()].filter((k) => k.startsWith(prefix)).sort();
      const start = cursor ? Number(cursor) || 0 : 0;
      const page = names.slice(start, start + limit);
      const next = start + page.length;
      return {
        keys: page.map((name) => ({ name })),
        list_complete: next >= names.length,
        cursor: next >= names.length ? undefined : String(next),
      };
    },
  };
}

function eventKey(tenant, company, i) {
  const day = String((i % 28) + 1).padStart(2, "0");
  return `compliance_event_v1/tenant/${tenant}/company/${company}/2026/01/${day}/event_${String(i).padStart(5, "0")}`;
}

function seedEvents(kv, tenant, company, n) {
  for (let i = 0; i < n; i += 1) {
    const key = eventKey(tenant, company, i);
    kv.store.set(
      key,
      JSON.stringify({
        event_id: `ev-${i}`,
        event_type: "ride_stop",
        tenant_id: tenant,
        company_id: company,
        created_at_utc: new Date(Date.now() - i * 1000).toISOString(),
        booking_id: `b-${i}`,
      }),
    );
  }
}

async function runScheduled(env) {
  const pending = [];
  const ctx = {
    waitUntil(p) {
      pending.push(Promise.resolve(p));
    },
  };
  await worker.scheduled({ cron: "*/5 * * * *" }, env, ctx);
  await Promise.all(pending);
}

test("budget wrapper trips after max reads", async () => {
  const inner = countingKV({ a: { ok: true } });
  const wrapped = wrapKvBudget(inner, { maxReads: 1, maxLists: 1, maxWrites: 1 });
  await wrapped.get("a");
  await assert.rejects(() => wrapped.get("a"), KvBudgetExceededError);
});

test("scheduled is a no-op when CHIRON_CRON_ENABLED is off", async () => {
  const kv = countingKV();
  seedEvents(kv, "t1", "c1", 100);
  await runScheduled({ COMPLIANCE_KV: kv, CHIRON_CRON_ENABLED: "0" });
  assert.equal(kv.counts.get, 0);
  assert.equal(kv.counts.list, 0);
});

test("reconcile with 1,400 historical events stays ≤50 value reads", async () => {
  const kv = countingKV();
  const tenant = "tenant_kv_p0";
  const company = "company_kv_p0";
  seedEvents(kv, tenant, company, 1400);
  kv.store.set(
    `tenant:${tenant}:company:${company}:chiron_connection:v1`,
    JSON.stringify({
      schema_version: "chiron_connection_status_v1",
      tenant_id: tenant,
      company_id: company,
      enabled: true,
      environment: "test",
      region: "flanders",
      production_enabled: false,
      official_submit_enabled: false,
      test_credentials_stored: true,
      last_connection_status: "test_passed",
      testflow_auto_submit_enabled: true,
      testflow_started_at: "2026-07-31T15:00:00.000Z",
      test_messages_required: 10,
      test_messages_sent_count: 0,
      test_departure_required: 5,
      test_arrival_required: 5,
      test_rides_required: 5,
      test_departure_sent_count: 0,
      test_arrival_sent_count: 0,
      test_rides_completed_count: 0,
      testflow_status: "in_progress",
      testflow_ritnummers_departure: [],
      testflow_ritnummers_arrival: [],
      testflow_ritnummers_completed: [],
    }),
  );
  kv.counts.get = 0;
  kv.counts.got = [];
  await _chironAutoReconcileScopeBestEffort(
    {
      COMPLIANCE_KV: kv,
      CHIRON_EXPORT_MODE: "test",
      CHIRON_EXPORT_BASE_URL: "https://mow-acc.api.vlaanderen.be/chiron/taxirit",
    },
    tenant,
    company,
    { source: "test" },
  );
  const eventGets = kv.counts.got.filter((k) => k.startsWith("compliance_event_v1/"));
  assert.ok(eventGets.length <= CHIRON_RECONCILE_MAX_KV_READS, `eventGets=${eventGets.length}`);
  assert.ok(kv.counts.get < 1400, `totalGets=${kv.counts.get} must stay far below full history`);
});

test("status poll does not launch reconcile when flag is off", async () => {
  const kv = countingKV();
  seedEvents(kv, "t1", "c1", 200);
  const pending = [];
  const ctx = {
    waitUntil(p) {
      pending.push(Promise.resolve(p));
    },
  };
  const url =
    "https://fluxidi-compliance-api.fluxidi.workers.dev/admin/chiron/config/status?tenant_id=t1&company_id=c1";
  const res = await worker.fetch(
    new Request(url, {
      method: "GET",
      headers: { authorization: "Bearer test-admin" },
    }),
    {
      COMPLIANCE_KV: kv,
      COMPLIANCE_ADMIN_TOKEN: "test-admin",
      CHIRON_STATUS_POLL_RECONCILE_ENABLED: "0",
      CHIRON_EXPORT_MODE: "test",
    },
    ctx,
  );
  assert.ok(res.status === 200 || res.status === 401 || res.status === 400, `status=${res.status}`);
  await Promise.all(pending);
  const eventLists = kv.counts.listed.filter((p) => String(p).includes("compliance_event_v1"));
  assert.equal(eventLists.length, 0);
});

test("testflow disabled: scheduled stays off and does not scan", async () => {
  const kv = countingKV();
  seedEvents(kv, "t1", "c1", 200);
  await runScheduled({
    COMPLIANCE_KV: kv,
    CHIRON_CRON_ENABLED: "0",
    CHIRON_EXPORT_MODE: "test",
  });
  assert.equal(kv.counts.list, 0);
  assert.equal(kv.counts.get, 0);
});

test("checkpoint continuation does not reread already-consumed keys", async () => {
  const kv = countingKV();
  const tenant = "tenant_kv_p0";
  const company = "company_kv_p0";
  seedEvents(kv, tenant, company, 40);
  kv.store.set(
    `tenant:${tenant}:company:${company}:chiron_connection:v1`,
    JSON.stringify({
      schema_version: "chiron_connection_status_v1",
      tenant_id: tenant,
      company_id: company,
      enabled: true,
      environment: "test",
      region: "flanders",
      production_enabled: false,
      official_submit_enabled: false,
      test_credentials_stored: true,
      last_connection_status: "test_passed",
      testflow_auto_submit_enabled: true,
      testflow_started_at: "2026-01-01T00:00:00.000Z",
      test_messages_required: 10,
      test_messages_sent_count: 0,
      test_departure_required: 5,
      test_arrival_required: 5,
      test_rides_required: 5,
      test_departure_sent_count: 0,
      test_arrival_sent_count: 0,
      test_rides_completed_count: 0,
      testflow_status: "in_progress",
      testflow_ritnummers_departure: [],
      testflow_ritnummers_arrival: [],
      testflow_ritnummers_completed: [],
    }),
  );
  const env = {
    COMPLIANCE_KV: kv,
    CHIRON_EXPORT_MODE: "test",
    CHIRON_EXPORT_BASE_URL: "https://mow-acc.api.vlaanderen.be/chiron/taxirit",
  };
  const first = await _chironAutoReconcileScopeBestEffort(env, tenant, company, {
    source: "test",
    nowMs: Date.parse("2026-01-20T00:00:00.000Z"),
  });
  assert.equal(first.ok, true);
  const firstEventGets = kv.counts.got.filter((k) =>
    k.startsWith("compliance_event_v1/"),
  ).length;
  kv.counts.get = 0;
  kv.counts.got = [];
  const second = await _chironAutoReconcileScopeBestEffort(env, tenant, company, {
    source: "test",
    nowMs: Date.parse("2026-01-20T00:00:00.000Z"),
  });
  assert.equal(second.ok, true);
  const secondEventGets = kv.counts.got.filter((k) =>
    k.startsWith("compliance_event_v1/"),
  ).length;
  assert.ok(secondEventGets <= firstEventGets);
  assert.ok(second.scanned <= first.scanned);
});

test("isolate budget kill switch trips", async () => {
  resetIsolateKvBudgetForTests();
  assert.throws(
    () => noteIsolateReads(1, { killSwitch: true }),
    KvBudgetExceededError,
  );
});

test("duplicate scheduled invocation stays disabled", async () => {
  const kv = countingKV();
  seedEvents(kv, "t1", "c1", 50);
  const env = { COMPLIANCE_KV: kv, CHIRON_CRON_ENABLED: "0" };
  await Promise.all([runScheduled(env), runScheduled(env)]);
  assert.equal(kv.counts.get, 0);
  assert.equal(kv.counts.list, 0);
});
