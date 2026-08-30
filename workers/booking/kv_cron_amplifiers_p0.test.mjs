// KV-CRON-AMPLIFIERS-P0 — counting tests for Booking scheduled recovery.
// Hermetic in-memory KV. No live Cloudflare, Billit, or deploy.

import { test } from "node:test";
import assert from "node:assert/strict";

import worker, {
  runBillitDurableRecoveryScheduledPass,
  runBillitOutboxDueMigrationStep,
  processBillitDueOutboxIndex,
  sweepBillitDurableRecoveryOutbox,
} from "./fluxidi_booking_worker.js";
import {
  BILLIT_OUTBOX_DUE_MIGRATION_KEY,
  BILLIT_OUTBOX_DUE_MIGRATION_VERSION,
  BILLIT_OUTBOX_PREFIX,
  buildBillitOutboxDueMarkerKey,
  buildBillitOutboxDueMarkerMetadata,
} from "./modules/billit_outbox_due_index.js";
import {
  wrapKvBudget,
  KvBudgetExceededError,
  noteIsolateReads,
  resetIsolateKvBudgetForTests,
} from "./modules/kv_op_budget.js";

function countingKV(seed = {}) {
  const store = new Map();
  const meta = new Map();
  for (const [key, value] of Object.entries(seed)) {
    store.set(key, typeof value === "string" ? value : JSON.stringify(value));
  }
  const counts = { get: 0, list: 0, put: 0, delete: 0, got: [] };
  return {
    store,
    meta,
    counts,
    async get(key, opts) {
      counts.get += 1;
      counts.got.push(key);
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
    async put(key, val, opts) {
      counts.put += 1;
      store.set(key, val);
      if (opts?.metadata) meta.set(key, opts.metadata);
    },
    async delete(key) {
      counts.delete += 1;
      store.delete(key);
      meta.delete(key);
    },
    async list({ prefix = "", limit = 1000, cursor } = {}) {
      counts.list += 1;
      const names = [...store.keys()].filter((k) => k.startsWith(prefix)).sort();
      const start = cursor ? Number(cursor) || 0 : 0;
      const page = names.slice(start, start + limit);
      const next = start + page.length;
      return {
        keys: page.map((name) => ({
          name,
          metadata: meta.get(name) || null,
        })),
        list_complete: next >= names.length,
        cursor: next >= names.length ? undefined : String(next),
      };
    },
  };
}

function completedMigration() {
  const now = new Date().toISOString();
  return {
    version: BILLIT_OUTBOX_DUE_MIGRATION_VERSION,
    completed: true,
    cursor: null,
    scanned: 0,
    marked: 0,
    batches: 1,
    started_at: now,
    updated_at: now,
    completed_at: now,
  };
}

function pendingOutbox(scope, documentId, bookingId, dueAtMs) {
  return {
    schema: "billit_create_outbox_v1",
    tenant_id: scope.tenant_id,
    company_id: scope.company_id,
    document_id: documentId,
    booking_id: bookingId,
    state: "pending",
    retryable: true,
    attempt_count: 0,
    next_attempt_at: new Date(dueAtMs).toISOString(),
    due_at: new Date(dueAtMs).toISOString(),
  };
}

async function runScheduled(env) {
  const pending = [];
  const ctx = {
    waitUntil(p) {
      pending.push(Promise.resolve(p));
    },
  };
  await worker.scheduled({ cron: "*/2 * * * *" }, env, ctx);
  await Promise.all(pending);
}

test("budget wrapper trips after max reads", async () => {
  const inner = countingKV({ a: { ok: true } });
  const wrapped = wrapKvBudget(inner, { maxReads: 1, maxLists: 1, maxWrites: 1 });
  await wrapped.get("a");
  await assert.rejects(() => wrapped.get("a"), KvBudgetExceededError);
});

test("scheduled is a no-op when BILLIT_RECOVERY_CRON_ENABLED is off", async () => {
  const kv = countingKV({
    [BILLIT_OUTBOX_DUE_MIGRATION_KEY]: completedMigration(),
    [`${BILLIT_OUTBOX_PREFIX}t:c:doc1`]: { state: "pending" },
  });
  await runScheduled({ BOOKING_KV: kv, BILLIT_RECOVERY_CRON_ENABLED: "0" });
  assert.equal(kv.counts.get, 0);
  assert.equal(kv.counts.list, 0);
  assert.equal(kv.counts.put, 0);
});

test("idle tick: completed migration, zero due → ≤3 reads, ≤1 list, 0 writes", async () => {
  const kv = countingKV({
    [BILLIT_OUTBOX_DUE_MIGRATION_KEY]: completedMigration(),
    "ops:invoice_opaque_rgb_logo_repair_v1": { done: true },
  });
  await runScheduled({ BOOKING_KV: kv, BILLIT_RECOVERY_CRON_ENABLED: "1" });
  assert.ok(kv.counts.get <= 3, `reads=${kv.counts.get}`);
  assert.ok(kv.counts.list <= 1, `lists=${kv.counts.list}`);
  assert.equal(kv.counts.put, 0);
});

test("1,000 non-due historical outbox records: 0 value-GET of those keys", async () => {
  const seed = {
    [BILLIT_OUTBOX_DUE_MIGRATION_KEY]: completedMigration(),
  };
  for (let i = 0; i < 1000; i += 1) {
    seed[`${BILLIT_OUTBOX_PREFIX}t:c:hist${i}`] = {
      state: "synced",
      tenant_id: "t",
      company_id: "c",
      document_id: `hist${i}`,
      booking_id: `b${i}`,
    };
  }
  const kv = countingKV(seed);
  await runScheduled({ BOOKING_KV: kv, BILLIT_RECOVERY_CRON_ENABLED: "1" });
  const historicalGets = kv.counts.got.filter((k) =>
    k.startsWith(`${BILLIT_OUTBOX_PREFIX}t:c:hist`),
  );
  assert.equal(historicalGets.length, 0);
  assert.ok(kv.counts.get <= 3);
});

test("one due item: only that outbox record is value-GET", async () => {
  const scope = { tenant_id: "t", company_id: "c" };
  const dueAt = Date.now() - 60_000;
  const outboxKey = `${BILLIT_OUTBOX_PREFIX}t:c:due1`;
  const rec = pendingOutbox(scope, "due1", "booking-due-1", dueAt);
  const marker = buildBillitOutboxDueMarkerKey(dueAt, outboxKey);
  const kv = countingKV({
    [BILLIT_OUTBOX_DUE_MIGRATION_KEY]: completedMigration(),
    [outboxKey]: rec,
  });
  kv.store.set(marker, "");
  kv.meta.set(marker, buildBillitOutboxDueMarkerMetadata(rec));
  const summary = await runBillitDurableRecoveryScheduledPass(
    { BOOKING_KV: kv },
    { source: "test", limit: 20, now: new Date() },
  );
  assert.equal(summary.processed.due, 1);
  assert.equal(kv.counts.got.filter((k) => k === outboxKey).length >= 1, true);
  assert.equal(kv.counts.got.filter((k) => k.startsWith(BILLIT_OUTBOX_PREFIX) && k !== outboxKey).length, 0);
});

test("twenty due items: ≤20 targeted outbox value reads in the index pass", async () => {
  const seed = { [BILLIT_OUTBOX_DUE_MIGRATION_KEY]: completedMigration() };
  const kv = countingKV(seed);
  const now = Date.now();
  for (let i = 0; i < 20; i += 1) {
    const scope = { tenant_id: "t", company_id: "c" };
    const dueAt = now - (i + 1) * 1000;
    const outboxKey = `${BILLIT_OUTBOX_PREFIX}t:c:due${i}`;
    const rec = pendingOutbox(scope, `due${i}`, `booking-${i}`, dueAt);
    kv.store.set(outboxKey, JSON.stringify(rec));
    const marker = buildBillitOutboxDueMarkerKey(dueAt, outboxKey);
    kv.store.set(marker, "");
    kv.meta.set(marker, buildBillitOutboxDueMarkerMetadata(rec));
  }
  kv.counts.get = 0;
  kv.counts.got = [];
  const summary = await runBillitDurableRecoveryScheduledPass(
    { BOOKING_KV: kv },
    { source: "test", limit: 20, now: new Date(now) },
  );
  assert.equal(summary.processed.due, 20);
  const outboxGets = kv.counts.got.filter((k) => k.startsWith(BILLIT_OUTBOX_PREFIX));
  assert.ok(outboxGets.length <= 20, `outboxGets=${outboxGets.length}`);
});

test("sweep is hard-gated without explicit allow", async () => {
  const kv = countingKV({
    [`${BILLIT_OUTBOX_PREFIX}t:c:doc1`]: pendingOutbox(
      { tenant_id: "t", company_id: "c" },
      "doc1",
      "b1",
      Date.now() - 1000,
    ),
  });
  const gated = await sweepBillitDurableRecoveryOutbox(
    { BOOKING_KV: kv },
    null,
    { source: "unit_test" },
  );
  assert.equal(gated.ok, false);
  assert.equal(gated.error, "sweep_hard_gated");
  assert.equal(kv.counts.get, 0);
});

test("migration checkpoint continues then stops permanently", async () => {
  const seed = {};
  for (let i = 0; i < 40; i += 1) {
    seed[`${BILLIT_OUTBOX_PREFIX}t:c:mig${String(i).padStart(2, "0")}`] = {
      state: "synced",
      tenant_id: "t",
      company_id: "c",
      document_id: `mig${String(i).padStart(2, "0")}`,
      booking_id: `b${i}`,
    };
  }
  const kv = countingKV(seed);
  const first = await runBillitOutboxDueMigrationStep(
    { BOOKING_KV: kv },
    { now: new Date() },
  );
  assert.equal(first.completed, false);
  assert.equal(first.scanned, 25);
  const afterFirst = kv.counts.get;
  const second = await runBillitOutboxDueMigrationStep(
    { BOOKING_KV: kv },
    { now: new Date() },
  );
  assert.equal(second.completed, true);
  assert.ok(second.scanned <= 25);
  const third = await runBillitOutboxDueMigrationStep(
    { BOOKING_KV: kv },
    { now: new Date() },
  );
  assert.equal(third.completed, true);
  assert.equal(third.scanned, 0);
  assert.equal(third.skipped, "already_complete");
  assert.ok(kv.counts.get <= afterFirst + second.scanned + 2);
});

test("retries re-read only the due record, never historical values", async () => {
  const scope = { tenant_id: "t", company_id: "c" };
  const dueAt = Date.now() - 60_000;
  const outboxKey = `${BILLIT_OUTBOX_PREFIX}t:c:retry1`;
  const rec = pendingOutbox(scope, "retry1", "booking-retry-1", dueAt);
  const marker = buildBillitOutboxDueMarkerKey(dueAt, outboxKey);
  const seed = { [BILLIT_OUTBOX_DUE_MIGRATION_KEY]: completedMigration() };
  for (let i = 0; i < 50; i += 1) {
    seed[`${BILLIT_OUTBOX_PREFIX}t:c:hist${i}`] = {
      state: "synced",
      tenant_id: "t",
      company_id: "c",
      document_id: `hist${i}`,
      booking_id: `bh${i}`,
    };
  }
  const kv = countingKV(seed);
  kv.store.set(outboxKey, JSON.stringify(rec));
  kv.store.set(marker, "");
  kv.meta.set(marker, buildBillitOutboxDueMarkerMetadata(rec));
  await processBillitDueOutboxIndex(
    { BOOKING_KV: kv },
    { source: "test", limit: 20, now: new Date() },
  );
  await processBillitDueOutboxIndex(
    { BOOKING_KV: kv },
    { source: "test", limit: 20, now: new Date() },
  );
  const historicalGets = kv.counts.got.filter((k) =>
    k.startsWith(`${BILLIT_OUTBOX_PREFIX}t:c:hist`),
  );
  assert.equal(historicalGets.length, 0);
  assert.ok(kv.counts.got.filter((k) => k === outboxKey).length >= 2);
});

test("isolate hourly budget kill switch trips", async () => {
  resetIsolateKvBudgetForTests();
  noteIsolateReads(5, { hourlyLimit: 10, dailyLimit: 100 });
  assert.throws(
    () => noteIsolateReads(6, { hourlyLimit: 10, dailyLimit: 100 }),
    KvBudgetExceededError,
  );
});

test("duplicate scheduled invocation stays disabled and cheap", async () => {
  const kv = countingKV({
    [BILLIT_OUTBOX_DUE_MIGRATION_KEY]: completedMigration(),
  });
  const env = { BOOKING_KV: kv, BILLIT_RECOVERY_CRON_ENABLED: "0" };
  await Promise.all([runScheduled(env), runScheduled(env)]);
  assert.equal(kv.counts.get, 0);
  assert.equal(kv.counts.list, 0);
});
