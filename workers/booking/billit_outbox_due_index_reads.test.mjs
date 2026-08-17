// BILLIT-KV-COST-P0
//
// Read-count acceptance contract for the bounded Billit recovery path.
//
// The defect: the `*/2` scheduled sweep listed the first page of
// `billit_create_outbox:*` and value-GET every key just to discover due-ness,
// costing ~3,450 BOOKING_KV reads per run (~2.16M/day with no customers).
//
// These tests use a counting KV adapter that separates list / value-read /
// write / delete operations, and drive the REAL exported worker functions
// (including the real `scheduled` handler) so the assertions prove executable
// wiring, not mock behaviour. Source-level assertions additionally prove the
// old full-scan path is unreachable from the cron and the documents route.
//
// Hermetic: in-memory KV, outbound fetch trapped, no Billit / Mollie / Peppol.

import { test, before, after, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import worker, {
  nudgeBillitDueOutboxForBooking,
  persistPendingBillitExportOutboxOnce,
  processBillitDueOutboxIndex,
  runBillitDurableExportAttempt,
  runBillitDurableRecoveryScheduledPass,
  runBillitOutboxDueMigrationStep,
} from "./fluxidi_booking_worker.js";
import {
  BILLIT_EXPORT_STATES,
  IN_PROGRESS_STALL_MS,
  buildPendingOutboxRecord,
  isBillitOutboxDue,
  markOutboxInProgress,
  mergeBillitOutboxAttemptResult,
} from "./modules/billit_export_recovery.js";
import {
  BILLIT_OUTBOX_DUE_MIGRATION_BATCH,
  BILLIT_OUTBOX_DUE_MIGRATION_KEY,
  BILLIT_OUTBOX_DUE_PREFIX,
  BILLIT_OUTBOX_PREFIX,
  billitOutboxDueAtMs,
  buildBillitOutboxDueMarkerKey,
  buildBillitOutboxDueMarkerMetadata,
  desiredBillitDueMarkerKey,
} from "./modules/billit_outbox_due_index.js";

/** Observed production cost of one pre-fix scheduled run. */
const OLD_READS_PER_CRON_RUN = 3450;
/** Existing unrelated one-shot completion marker read by `scheduled`. */
const OPS_REPAIR_KEY = "ops:invoice_opaque_rgb_logo_repair_v1";

const TENANT = "tenant_kvcost";
const COMPANY = "company_kvcost";
const SCOPE = { tenant_id: TENANT, company_id: COMPANY };
const NOW = new Date("2026-08-17T12:00:00.000Z");

let originalFetch;
let outbound = [];

before(() => {
  originalFetch = global.fetch;
  global.fetch = async (input) => {
    const href = typeof input === "string" ? input : input?.url || String(input);
    outbound.push(href);
    throw new Error(`hermetic test: blocked outbound fetch to ${href}`);
  };
});

after(() => {
  global.fetch = originalFetch;
});

beforeEach(() => {
  outbound = [];
});

/* ===================== counting KV adapter ===================== */

function makeCountingKV(seed = {}) {
  const store = new Map();
  const counts = { list: 0, get: 0, put: 0, delete: 0 };
  const reads = [];
  const writes = [];
  const deletes = [];

  for (const [k, v] of Object.entries(seed)) {
    store.set(k, {
      value: typeof v === "string" ? v : JSON.stringify(v),
      metadata: null,
    });
  }

  const api = {
    counts,
    reads,
    writes,
    deletes,
    store,
    /** Value reads of authoritative outbox records — the metric that regressed. */
    outboxReads: () => reads.filter((k) => k.startsWith(BILLIT_OUTBOX_PREFIX)),
    markerKeys: () =>
      [...store.keys()].filter((k) => k.startsWith(BILLIT_OUTBOX_DUE_PREFIX)).sort(),
    reset() {
      counts.list = 0;
      counts.get = 0;
      counts.put = 0;
      counts.delete = 0;
      reads.length = 0;
      writes.length = 0;
      deletes.length = 0;
    },
    async get(key, opts) {
      counts.get += 1;
      reads.push(key);
      const row = store.get(key);
      if (!row) return null;
      const type = typeof opts === "string" ? opts : opts?.type;
      if (type === "json") {
        try {
          return JSON.parse(row.value);
        } catch (_) {
          return null;
        }
      }
      return row.value;
    },
    async put(key, value, opts) {
      counts.put += 1;
      writes.push(key);
      store.set(key, {
        value: typeof value === "string" ? value : String(value ?? ""),
        metadata: opts && opts.metadata ? opts.metadata : null,
      });
    },
    async delete(key) {
      counts.delete += 1;
      deletes.push(key);
      store.delete(key);
    },
    // Mirrors Workers KV: lexicographic order, prefix filter, capped page size,
    // `list_complete` plus an opaque continuation cursor, and per-key metadata
    // returned WITHOUT a value read.
    async list({ prefix = "", limit = 1000, cursor } = {}) {
      counts.list += 1;
      const all = [...store.keys()].filter((k) => k.startsWith(prefix)).sort();
      const start = cursor
        ? Number(Buffer.from(String(cursor), "base64").toString("utf8")) || 0
        : 0;
      const capped = Math.max(1, Math.min(1000, Number(limit) || 1000));
      const slice = all.slice(start, start + capped);
      const nextIndex = start + slice.length;
      const listComplete = nextIndex >= all.length;
      return {
        keys: slice.map((name) => {
          const row = store.get(name);
          return row && row.metadata
            ? { name, metadata: row.metadata }
            : { name };
        }),
        list_complete: listComplete,
        cursor: listComplete
          ? undefined
          : Buffer.from(String(nextIndex), "utf8").toString("base64"),
      };
    },
  };
  return api;
}

/** Env with no Billit OAuth config, so no attempt can reach a provider. */
function makeEnv(seed = {}) {
  return { BOOKING_KV: makeCountingKV(seed) };
}

function outboxKeyFor(documentId) {
  return `${BILLIT_OUTBOX_PREFIX}${TENANT}:${COMPANY}:${documentId}`;
}

function makeRecord(documentId, overrides = {}) {
  return {
    ...buildPendingOutboxRecord({
      scope: SCOPE,
      documentId,
      bookingId: `booking_${documentId}`,
      now: NOW,
    }),
    ...overrides,
  };
}

/** Seed an authoritative record together with the marker it should own. */
function seedRecordWithMarker(kv, documentId, overrides = {}) {
  const outboxKey = outboxKeyFor(documentId);
  const record = makeRecord(documentId, overrides);
  const markerKey = desiredBillitDueMarkerKey(outboxKey, record);
  const stored = { ...record, due_marker_key: markerKey };
  kv.store.set(outboxKey, { value: JSON.stringify(stored), metadata: null });
  if (markerKey) {
    kv.store.set(markerKey, {
      value: "",
      metadata: buildBillitOutboxDueMarkerMetadata(record),
    });
  }
  return { outboxKey, markerKey, record: stored };
}

function seedMigrationComplete(kv) {
  kv.store.set(BILLIT_OUTBOX_DUE_MIGRATION_KEY, {
    value: JSON.stringify({
      version: 1,
      completed: true,
      cursor: null,
      scanned: 0,
      marked: 0,
      batches: 1,
      started_at: NOW.toISOString(),
      updated_at: NOW.toISOString(),
      completed_at: NOW.toISOString(),
    }),
    metadata: null,
  });
}

function seedOpsRepairDone(kv) {
  kv.store.set(OPS_REPAIR_KEY, {
    value: JSON.stringify({ done: true, at: NOW.toISOString() }),
    metadata: null,
  });
}

function iso(msOffset) {
  return new Date(NOW.getTime() + msOffset).toISOString();
}

// The real `scheduled` handler owns its own clock, so tests that drive it must
// express due-ness relative to wall-clock time rather than the fixed NOW.
function isoFromWallClock(msOffset) {
  return new Date(Date.now() + msOffset).toISOString();
}

/** Run the REAL scheduled handler and await everything it defers. */
async function runScheduled(env) {
  const deferred = [];
  const ctx = { waitUntil: (p) => deferred.push(p) };
  await worker.scheduled({ cron: "*/2 * * * *" }, env, ctx);
  await Promise.all(deferred);
}

/* ===================== 1 + 13. steady-state read floor ===================== */

test("1+13. stable system with migration complete performs zero outbox value reads and stays >99.9% below the old cron cost", async () => {
  const env = makeEnv();
  seedMigrationComplete(env.BOOKING_KV);
  seedOpsRepairDone(env.BOOKING_KV);
  env.BOOKING_KV.reset();

  await runScheduled(env);

  const kv = env.BOOKING_KV;
  assert.deepEqual(kv.outboxReads(), [], "no authoritative outbox value read");

  // Only the migration-state read and the pre-existing one-shot repair marker.
  assert.deepEqual(kv.reads.sort(), [BILLIT_OUTBOX_DUE_MIGRATION_KEY, OPS_REPAIR_KEY].sort());
  assert.equal(kv.counts.get, 2, "exactly two fixed value reads per empty run");
  assert.ok(kv.counts.get <= 3, "within the 1-3 fixed-read steady-state target");

  const reduction = (1 - kv.counts.get / OLD_READS_PER_CRON_RUN) * 100;
  assert.ok(
    reduction >= 99.9,
    `empty-run reduction ${reduction.toFixed(3)}% must be >= 99.9%`,
  );
  assert.deepEqual(outbound, []);
});

/* ===================== 2. non-due records are never read ===================== */

test("2. one thousand future outbox records cost zero value reads during scheduled processing", async () => {
  const env = makeEnv();
  const kv = env.BOOKING_KV;
  seedMigrationComplete(kv);
  seedOpsRepairDone(kv);
  for (let i = 0; i < 1000; i += 1) {
    seedRecordWithMarker(kv, `future-${String(i).padStart(4, "0")}`, {
      state: BILLIT_EXPORT_STATES.RETRYABLE_ERROR,
      attempt_count: 1,
      next_attempt_at: isoFromWallClock(24 * 60 * 60 * 1000 + i),
    });
  }
  kv.reset();

  await runScheduled(env);

  assert.deepEqual(kv.outboxReads(), [], "zero GETs of the 1000 non-due records");
  assert.equal(kv.counts.get, 2, "still only the two fixed reads");
  // A single bounded marker list, stopped at the first future marker.
  assert.equal(kv.counts.list, 1);
  assert.equal(kv.markerKeys().length, 1000, "every future marker survives");
});

/* ===================== 3. only due records are read ===================== */

test("3. twenty due records read exactly those records and no unrelated record", async () => {
  const env = makeEnv();
  const kv = env.BOOKING_KV;
  seedMigrationComplete(kv);

  const dueKeys = [];
  for (let i = 0; i < 20; i += 1) {
    const { outboxKey } = seedRecordWithMarker(kv, `due-${String(i).padStart(3, "0")}`, {
      state: BILLIT_EXPORT_STATES.RETRYABLE_ERROR,
      attempt_count: 1,
      next_attempt_at: iso(-60_000 - i),
    });
    dueKeys.push(outboxKey);
  }
  const untouched = [];
  for (let i = 0; i < 50; i += 1) {
    const { outboxKey } = seedRecordWithMarker(kv, `later-${String(i).padStart(3, "0")}`, {
      state: BILLIT_EXPORT_STATES.RETRYABLE_ERROR,
      attempt_count: 1,
      next_attempt_at: iso(3 * 60 * 60 * 1000 + i),
    });
    untouched.push(outboxKey);
  }
  kv.reset();

  const summary = await processBillitDueOutboxIndex(env, {
    source: "unit_test",
    limit: 20,
    now: NOW,
  });

  assert.equal(summary.ok, true);
  assert.equal(summary.due, 20);
  assert.equal(summary.retried, 20);
  assert.deepEqual(kv.outboxReads().sort(), dueKeys.sort());
  for (const key of untouched) {
    assert.ok(!kv.reads.includes(key), `unrelated record must not be read: ${key}`);
  }
  assert.deepEqual(outbound, [], "no provider call without Billit config");
});

/* ===================== 4. bounded when more than the retry limit is due ===================== */

test("4. more than twenty due records are processed bounded and the remainder stays scheduled", async () => {
  const env = makeEnv();
  const kv = env.BOOKING_KV;
  seedMigrationComplete(kv);
  for (let i = 0; i < 35; i += 1) {
    seedRecordWithMarker(kv, `burst-${String(i).padStart(3, "0")}`, {
      state: BILLIT_EXPORT_STATES.RETRYABLE_ERROR,
      attempt_count: 1,
      next_attempt_at: iso(-120_000 + i),
    });
  }
  kv.reset();

  const summary = await processBillitDueOutboxIndex(env, {
    source: "unit_test",
    limit: 20,
    now: NOW,
  });

  assert.equal(summary.retried, 20, "processing is capped at the retry limit");
  assert.equal(summary.stopped_at_limit, true);
  assert.equal(kv.outboxReads().length, 20, "reads never exceed the retry limit");
  // Nothing was dropped: every marker is still scheduled for a later pass.
  assert.equal(kv.markerKeys().length, 35);
});

/* ===================== 5. bounded, resumable legacy migration ===================== */

test("5. legacy migration reads at most the batch cap per invocation, resumes, completes, and never rescans", async () => {
  const env = makeEnv();
  const kv = env.BOOKING_KV;
  seedOpsRepairDone(kv);

  const legacyTotal = 60;
  for (let i = 0; i < legacyTotal; i += 1) {
    // Legacy shape: no next_attempt_at, no due marker.
    kv.store.set(outboxKeyFor(`legacy-${String(i).padStart(3, "0")}`), {
      value: JSON.stringify({
        provider: "billit",
        environment: "sandbox",
        tenant_id: TENANT,
        company_id: COMPANY,
        document_id: `legacy-${String(i).padStart(3, "0")}`,
        booking_id: `booking_legacy_${i}`,
        state: "pending",
        retryable: true,
        attempt_count: 1,
        created_at: "2026-08-02T17:06:53.134Z",
        updated_at: "2026-08-02T17:06:53.134Z",
      }),
      metadata: null,
    });
  }

  const seenPerBatch = [];
  let completed = false;
  for (let batch = 0; batch < 4 && !completed; batch += 1) {
    kv.reset();
    const step = await runBillitOutboxDueMigrationStep(env, { now: NOW });
    const reads = kv.outboxReads();
    seenPerBatch.push(reads);
    assert.ok(
      reads.length <= BILLIT_OUTBOX_DUE_MIGRATION_BATCH,
      `batch ${batch} read ${reads.length} legacy records, cap is ${BILLIT_OUTBOX_DUE_MIGRATION_BATCH}`,
    );
    completed = step.completed === true;
  }
  assert.equal(completed, true, "migration completes within bounded batches");

  // Every legacy record examined at most once across the whole pass.
  const allSeen = seenPerBatch.flat();
  assert.equal(new Set(allSeen).size, allSeen.length, "no record examined twice");
  assert.equal(allSeen.length, legacyTotal, "every legacy record examined exactly once");

  // Authoritative legacy records are preserved and were never rewritten.
  for (let i = 0; i < legacyTotal; i += 1) {
    const stored = JSON.parse(kv.store.get(outboxKeyFor(`legacy-${String(i).padStart(3, "0")}`)).value);
    assert.equal(stored.state, "pending");
    assert.equal("due_marker_key" in stored, false, "migration must not rewrite the record");
  }
  assert.equal(kv.markerKeys().length, legacyTotal, "each legacy record gained a marker");

  // After completion the scheduled pass never returns to GET-all.
  kv.reset();
  const after = await runBillitOutboxDueMigrationStep(env, { now: NOW });
  assert.equal(after.completed, true);
  assert.deepEqual(kv.outboxReads(), [], "completed migration reads no outbox values");
  assert.equal(kv.counts.get, 1, "only the migration-state read remains");
  assert.equal(kv.counts.list, 0, "completed migration performs no outbox list");
});

/* ===================== 6. terminal states carry no marker ===================== */

test("6. synced and permanent-error records end with no active marker and no recurring reads", async () => {
  const env = makeEnv();
  const kv = env.BOOKING_KV;
  seedMigrationComplete(kv);

  // Markers that raced a terminal transition: due now, record already terminal.
  const synced = seedRecordWithMarker(kv, "doc-synced", {
    state: BILLIT_EXPORT_STATES.RETRYABLE_ERROR,
    next_attempt_at: iso(-60_000),
  });
  const permanent = seedRecordWithMarker(kv, "doc-permanent", {
    state: BILLIT_EXPORT_STATES.RETRYABLE_ERROR,
    next_attempt_at: iso(-60_000),
  });
  kv.store.set(synced.outboxKey, {
    value: JSON.stringify({
      ...synced.record,
      state: BILLIT_EXPORT_STATES.SYNCED,
    }),
    metadata: null,
  });
  kv.store.set(permanent.outboxKey, {
    value: JSON.stringify({
      ...permanent.record,
      state: BILLIT_EXPORT_STATES.PERMANENT_ERROR,
      last_error_code: "billit_administration_selection_required",
      next_attempt_at: null,
    }),
    metadata: null,
  });
  kv.reset();

  const first = await processBillitDueOutboxIndex(env, {
    source: "unit_test",
    limit: 20,
    now: NOW,
  });
  assert.equal(first.retried, 0, "terminal records are never retried");
  assert.equal(first.reconciled, 2);
  assert.equal(kv.outboxReads().length, 2, "each terminal record read once to reconcile");
  assert.deepEqual(kv.markerKeys(), [], "terminal records own no active marker");

  // Second pass: nothing left to look at.
  kv.reset();
  const second = await processBillitDueOutboxIndex(env, {
    source: "unit_test",
    limit: 20,
    now: NOW,
  });
  assert.equal(second.due, 0);
  assert.deepEqual(kv.outboxReads(), [], "no recurring reads of terminal records");
});

test("6b. migration arms no marker for synced or permanent-error legacy records", async () => {
  const env = makeEnv();
  const kv = env.BOOKING_KV;
  kv.store.set(outboxKeyFor("m-synced"), {
    value: JSON.stringify(makeRecord("m-synced", { state: BILLIT_EXPORT_STATES.SYNCED })),
    metadata: null,
  });
  kv.store.set(outboxKeyFor("m-permanent"), {
    value: JSON.stringify(
      makeRecord("m-permanent", {
        state: BILLIT_EXPORT_STATES.PERMANENT_ERROR,
        last_error_code: "billit_payload_invalid",
        next_attempt_at: null,
      }),
    ),
    metadata: null,
  });

  const step = await runBillitOutboxDueMigrationStep(env, { now: NOW });
  assert.equal(step.completed, true);
  assert.equal(step.terminal, 2);
  assert.equal(step.marked, 0);
  assert.deepEqual(kv.markerKeys(), []);
});

/* ===================== 7. future work does no provider work ===================== */

test("7. a future next_attempt_at triggers no Document Core or Billit work before its due time", async () => {
  const env = makeEnv();
  const kv = env.BOOKING_KV;
  seedMigrationComplete(kv);
  const { outboxKey } = seedRecordWithMarker(kv, "doc-future", {
    state: BILLIT_EXPORT_STATES.RETRYABLE_ERROR,
    attempt_count: 2,
    next_attempt_at: iso(30 * 60 * 1000),
  });
  kv.reset();

  const summary = await processBillitDueOutboxIndex(env, {
    source: "unit_test",
    limit: 20,
    now: NOW,
  });

  assert.equal(summary.due, 0);
  assert.equal(summary.retried, 0);
  assert.equal(summary.stopped_at_future, true);
  assert.ok(!kv.reads.includes(outboxKey), "the future record is never read");
  assert.deepEqual(kv.reads, [], "no value read at all");
  assert.deepEqual(outbound, []);

  // Once the clock passes the scheduled moment the same marker becomes due.
  const later = new Date(NOW.getTime() + 31 * 60 * 1000);
  kv.reset();
  const due = await processBillitDueOutboxIndex(env, {
    source: "unit_test",
    limit: 20,
    now: later,
  });
  assert.equal(due.due, 1);
  assert.deepEqual(kv.outboxReads(), [outboxKey]);
});

/* ===================== 8. authoritative backoff drives the marker ===================== */

test("8. a retryable failure yields exactly one marker at the authoritative backoff moment", () => {
  const previous = markOutboxInProgress(
    buildPendingOutboxRecord({
      scope: SCOPE,
      documentId: "doc-backoff",
      bookingId: "booking_backoff",
      now: NOW,
    }),
    { now: NOW },
  );
  const merged = mergeBillitOutboxAttemptResult({
    previous,
    result: { ok: false, error_code: "billit_order_create_failed", status_code: 502 },
    now: NOW,
  });
  assert.equal(merged.state, BILLIT_EXPORT_STATES.RETRYABLE_ERROR);

  const outboxKey = outboxKeyFor("doc-backoff");
  const markerKey = desiredBillitDueMarkerKey(outboxKey, merged);
  const expected = buildBillitOutboxDueMarkerKey(
    Date.parse(merged.next_attempt_at),
    outboxKey,
  );
  assert.equal(markerKey, expected, "marker encodes the authoritative next_attempt_at");
  assert.notEqual(markerKey, desiredBillitDueMarkerKey(outboxKey, previous));
});

test("8b. an attempt that dies before classification leaves exactly one stall marker", async () => {
  const env = makeEnv();
  const kv = env.BOOKING_KV;
  const seeded = seedRecordWithMarker(kv, "doc-stall", {
    state: BILLIT_EXPORT_STATES.RETRYABLE_ERROR,
    attempt_count: 1,
    next_attempt_at: iso(-60_000),
  });
  kv.reset();

  // Sandbox config supplied so the attempt proceeds past the config gate; the
  // booking record is absent so Document Core refuses before any provider call.
  const outcome = await runBillitDurableExportAttempt(env, SCOPE, {
    documentId: "doc-stall",
    bookingId: "booking_doc-stall",
    source: "unit_test",
    config: { environment: "sandbox", configured: true },
    dueMarkerKey: seeded.markerKey,
  });
  assert.equal(outcome.ok, false);
  assert.deepEqual(outbound, [], "no provider call was made");

  const stored = JSON.parse(kv.store.get(seeded.outboxKey).value);
  assert.equal(stored.state, BILLIT_EXPORT_STATES.IN_PROGRESS);

  const markers = kv.markerKeys();
  assert.equal(markers.length, 1, "exactly one marker, no leak of the superseded one");
  const expectedStall = buildBillitOutboxDueMarkerKey(
    Date.parse(stored.in_progress_since) + IN_PROGRESS_STALL_MS,
    seeded.outboxKey,
  );
  assert.equal(markers[0], expectedStall, "marker moved to the stall deadline");
  assert.equal(stored.due_marker_key, expectedStall);
});

/* ===================== 9. stale / duplicate markers ===================== */

test("9. a duplicate marker for the same record cannot produce a second export attempt", async () => {
  const env = makeEnv();
  const kv = env.BOOKING_KV;
  seedMigrationComplete(kv);
  const seeded = seedRecordWithMarker(kv, "doc-dup", {
    state: BILLIT_EXPORT_STATES.RETRYABLE_ERROR,
    attempt_count: 1,
    next_attempt_at: iso(-60_000),
  });
  // A stale marker left behind by an interrupted reschedule: earlier due time,
  // same authoritative record.
  const staleMarker = buildBillitOutboxDueMarkerKey(
    NOW.getTime() - 10 * 60 * 1000,
    seeded.outboxKey,
  );
  kv.store.set(staleMarker, {
    value: "",
    metadata: buildBillitOutboxDueMarkerMetadata(seeded.record),
  });
  assert.equal(kv.markerKeys().length, 2);
  kv.reset();

  const summary = await processBillitDueOutboxIndex(env, {
    source: "unit_test",
    limit: 20,
    now: NOW,
  });

  assert.equal(summary.retried, 1, "the record is attempted exactly once");
  assert.equal(summary.deduped, 1, "the duplicate marker is retired, not attempted");
  assert.equal(
    kv.outboxReads().filter((k) => k === seeded.outboxKey).length,
    1,
    "the authoritative record is read once, not once per marker",
  );
  assert.deepEqual(outbound, []);
});

test("9b. a marker whose metadata does not match its key ref is discarded, not followed", async () => {
  const env = makeEnv();
  const kv = env.BOOKING_KV;
  seedMigrationComplete(kv);
  const victim = seedRecordWithMarker(kv, "doc-victim", {
    state: BILLIT_EXPORT_STATES.RETRYABLE_ERROR,
    next_attempt_at: iso(-60_000),
  });
  // Marker key ref points at one record while metadata names another.
  const forged = buildBillitOutboxDueMarkerKey(
    NOW.getTime() - 5000,
    outboxKeyFor("doc-other"),
  );
  kv.store.set(forged, {
    value: "",
    metadata: buildBillitOutboxDueMarkerMetadata(victim.record),
  });
  kv.reset();

  const summary = await processBillitDueOutboxIndex(env, {
    source: "unit_test",
    limit: 20,
    now: NOW,
  });
  assert.equal(summary.orphaned >= 1, true, "the mismatched marker is retired");
  assert.ok(!kv.markerKeys().includes(forged));
  assert.equal(summary.retried, 1, "only the legitimate record is attempted");
});

/* ===================== 10. crash-ordering simulations ===================== */

test("10a. marker written but authoritative record missing (crash between writes) self-heals", async () => {
  const env = makeEnv();
  const kv = env.BOOKING_KV;
  seedMigrationComplete(kv);
  const orphanRecord = makeRecord("doc-orphan");
  const orphanMarker = buildBillitOutboxDueMarkerKey(
    NOW.getTime() - 1000,
    outboxKeyFor("doc-orphan"),
  );
  kv.store.set(orphanMarker, {
    value: "",
    metadata: buildBillitOutboxDueMarkerMetadata(orphanRecord),
  });
  kv.reset();

  const summary = await processBillitDueOutboxIndex(env, {
    source: "unit_test",
    limit: 20,
    now: NOW,
  });
  assert.equal(summary.ok, true);
  assert.equal(summary.retried, 0);
  assert.equal(summary.orphaned, 1);
  assert.deepEqual(kv.markerKeys(), [], "orphan marker retired");
});

test("10b. authoritative record persisted but the superseded marker delete never ran — work is still done exactly once", async () => {
  const env = makeEnv();
  const kv = env.BOOKING_KV;
  seedMigrationComplete(kv);
  const seeded = seedRecordWithMarker(kv, "doc-crash", {
    state: BILLIT_EXPORT_STATES.RETRYABLE_ERROR,
    attempt_count: 1,
    next_attempt_at: iso(-30_000),
  });
  // Simulate the interrupted step: an older marker survives alongside the
  // current one because the delete never executed.
  const supersededMarker = buildBillitOutboxDueMarkerKey(
    NOW.getTime() - 20 * 60 * 1000,
    seeded.outboxKey,
  );
  kv.store.set(supersededMarker, {
    value: "",
    metadata: buildBillitOutboxDueMarkerMetadata(seeded.record),
  });
  kv.reset();

  const summary = await processBillitDueOutboxIndex(env, {
    source: "unit_test",
    limit: 20,
    now: NOW,
  });
  assert.equal(summary.retried, 1, "due work is not lost and not duplicated");
  assert.equal(
    kv.outboxReads().filter((k) => k === seeded.outboxKey).length,
    1,
  );
});

test("10c. the create path arms the marker BEFORE the authoritative record (no unmarked due work)", async () => {
  const env = makeEnv();
  const kv = env.BOOKING_KV;

  const result = await persistPendingBillitExportOutboxOnce(env, SCOPE, {
    documentId: "doc-order",
    bookingId: "booking_order",
    invoiceIdempotencyKey: "inv-auto:t:c:b:main:v1",
  });
  assert.equal(result.ok, true);
  assert.equal(result.existed, false);

  const markerIndex = kv.writes.findIndex((k) => k.startsWith(BILLIT_OUTBOX_DUE_PREFIX));
  const recordIndex = kv.writes.findIndex((k) => k.startsWith(BILLIT_OUTBOX_PREFIX));
  assert.ok(markerIndex >= 0, "a due marker was written");
  assert.ok(recordIndex >= 0, "the authoritative record was written");
  assert.ok(
    markerIndex < recordIndex,
    "marker must be armed before the record so a crash can never hide due work",
  );

  const stored = JSON.parse(kv.store.get(outboxKeyFor("doc-order")).value);
  assert.equal(stored.state, BILLIT_EXPORT_STATES.PENDING);
  assert.equal(stored.due_marker_key, kv.writes[markerIndex]);
});

test("10d. due-time derivation and the due predicate agree for every outbox state", () => {
  const cases = [
    makeRecord("s1", { state: BILLIT_EXPORT_STATES.PENDING, next_attempt_at: iso(-1000) }),
    makeRecord("s2", { state: BILLIT_EXPORT_STATES.PENDING, next_attempt_at: iso(1000) }),
    makeRecord("s3", { state: BILLIT_EXPORT_STATES.RETRYABLE_ERROR, next_attempt_at: iso(-1) }),
    makeRecord("s4", { state: BILLIT_EXPORT_STATES.RETRYABLE_ERROR, next_attempt_at: iso(1) }),
    makeRecord("s5", { state: BILLIT_EXPORT_STATES.EXHAUSTED_RETRYABLE, next_attempt_at: iso(-5) }),
    makeRecord("s6", { state: BILLIT_EXPORT_STATES.EXHAUSTED_RETRYABLE, next_attempt_at: iso(5) }),
    makeRecord("s7", { state: BILLIT_EXPORT_STATES.SYNCED }),
    makeRecord("s8", {
      state: BILLIT_EXPORT_STATES.PERMANENT_ERROR,
      next_attempt_at: null,
    }),
    makeRecord("s9", {
      state: BILLIT_EXPORT_STATES.IN_PROGRESS,
      in_progress_since: iso(-IN_PROGRESS_STALL_MS - 1),
    }),
    makeRecord("s10", {
      state: BILLIT_EXPORT_STATES.IN_PROGRESS,
      in_progress_since: iso(-1000),
    }),
    // Legacy record with no usable schedule at all.
    { state: "pending", tenant_id: TENANT, company_id: COMPANY, document_id: "s11" },
  ];
  for (const record of cases) {
    const dueAt = billitOutboxDueAtMs(record);
    const predicate = isBillitOutboxDue(record, { now: NOW });
    const derived = dueAt !== null && dueAt <= NOW.getTime();
    assert.equal(
      derived,
      predicate,
      `state=${record.state} dueAt=${dueAt} disagreed with isBillitOutboxDue`,
    );
  }
});

/* ===================== 11. documents route ===================== */

test("11. the documents nudge performs no global scan and reads only this booking's records", async () => {
  const env = makeEnv();
  const kv = env.BOOKING_KV;
  // A large unrelated outbox population that the old global sweep would read.
  for (let i = 0; i < 500; i += 1) {
    seedRecordWithMarker(kv, `unrelated-${String(i).padStart(3, "0")}`, {
      state: BILLIT_EXPORT_STATES.RETRYABLE_ERROR,
      next_attempt_at: iso(-60_000),
    });
  }
  const mine = seedRecordWithMarker(kv, "doc-mine", {
    state: BILLIT_EXPORT_STATES.RETRYABLE_ERROR,
    next_attempt_at: iso(-60_000),
    booking_id: "booking_mine",
  });
  kv.reset();

  const summary = await nudgeBillitDueOutboxForBooking(env, SCOPE, {
    bookingId: "booking_mine",
    documents: [{ document_id: "doc-mine" }],
    source: "documents_refresh_nudge",
    limit: 4,
  });

  assert.equal(summary.ok, true);
  assert.equal(kv.counts.list, 0, "no list operation at all — no global first page");
  assert.deepEqual(kv.outboxReads(), [mine.outboxKey], "only the targeted record is read");
  assert.equal(kv.counts.get, 1);
  assert.deepEqual(outbound, []);
});

test("11b. the documents nudge refuses a document whose record belongs to another booking", async () => {
  const env = makeEnv();
  const kv = env.BOOKING_KV;
  seedRecordWithMarker(kv, "doc-other-booking", {
    state: BILLIT_EXPORT_STATES.RETRYABLE_ERROR,
    next_attempt_at: iso(-60_000),
    booking_id: "booking_someone_else",
  });
  kv.reset();

  const summary = await nudgeBillitDueOutboxForBooking(env, SCOPE, {
    bookingId: "booking_mine",
    documents: [{ document_id: "doc-other-booking" }],
    limit: 4,
  });
  assert.equal(summary.retried, 0, "booking binding is re-checked before any attempt");
  assert.equal(kv.counts.list, 0);
});

/* ===================== 12. idempotency and locking preserved ===================== */

test("12. the per-document recovery lock and synced short-circuit still prevent a second export", async () => {
  const env = makeEnv();
  const kv = env.BOOKING_KV;
  seedRecordWithMarker(kv, "doc-locked", {
    state: BILLIT_EXPORT_STATES.RETRYABLE_ERROR,
    next_attempt_at: iso(-60_000),
  });
  kv.store.set(`billit_recovery_lock:${TENANT}:${COMPANY}:doc-locked`, {
    value: "other_holder",
    metadata: null,
  });

  const locked = await runBillitDurableExportAttempt(env, SCOPE, {
    documentId: "doc-locked",
    bookingId: "booking_doc-locked",
    source: "unit_test",
    config: { environment: "sandbox", configured: true },
  });
  assert.equal(locked.ok, true);
  assert.equal(locked.skipped, true);
  assert.equal(locked.reason, "concurrent_recovery_locked");

  // A synced record short-circuits and drops any marker that raced it.
  const synced = seedRecordWithMarker(kv, "doc-already", {
    state: BILLIT_EXPORT_STATES.RETRYABLE_ERROR,
    next_attempt_at: iso(-60_000),
  });
  kv.store.set(synced.outboxKey, {
    value: JSON.stringify({
      ...synced.record,
      state: BILLIT_EXPORT_STATES.SYNCED,
    }),
    metadata: null,
  });
  const already = await runBillitDurableExportAttempt(env, SCOPE, {
    documentId: "doc-already",
    bookingId: "booking_doc-already",
    source: "unit_test",
    config: { environment: "sandbox", configured: true },
    dueMarkerKey: synced.markerKey,
  });
  assert.equal(already.ok, true);
  assert.equal(already.skipped, true);
  assert.equal(already.reason, "already_synced");
  assert.ok(!kv.markerKeys().includes(synced.markerKey), "synced record keeps no marker");
  assert.deepEqual(outbound, []);
});

/* ===================== executable source wiring ===================== */

const WORKER_SOURCE = readFileSync(
  join(dirname(fileURLToPath(import.meta.url)), "fluxidi_booking_worker.js"),
  "utf8",
);

test("source wiring: the cron and the documents route no longer reach the full-scan sweep", () => {
  // Exactly two occurrences may remain: the declaration and the export entry.
  const occurrences = WORKER_SOURCE.split("sweepBillitDurableRecoveryOutbox").length - 1;
  assert.equal(
    occurrences,
    2,
    "the full-scan sweep must have no production call site (declaration + export only)",
  );
  assert.ok(!WORKER_SOURCE.includes("sweepBillitDurableRecoveryOutbox(env, ctx, {"));
  assert.ok(!WORKER_SOURCE.includes("sweepBillitDurableRecoveryOutbox(env, null,"));

  assert.ok(
    WORKER_SOURCE.includes("runBillitDurableRecoveryScheduledPass(env, {"),
    "scheduled handler must call the bounded pass",
  );
  assert.ok(
    WORKER_SOURCE.includes("nudgeBillitDueOutboxForBooking(env, scope, {"),
    "documents route must call the targeted nudge",
  );
});

test("source wiring: the scheduled pass runs migration then the bounded due-index pass", () => {
  const start = WORKER_SOURCE.indexOf(
    "async function runBillitDurableRecoveryScheduledPass",
  );
  assert.ok(start > 0, "bounded scheduled pass must exist");
  const body = WORKER_SOURCE.slice(start, start + 1400);
  const migrationAt = body.indexOf("runBillitOutboxDueMigrationStep(env");
  const processAt = body.indexOf("processBillitDueOutboxIndex(env");
  assert.ok(migrationAt > 0 && processAt > 0);
  assert.ok(migrationAt < processAt, "migration advances before due processing");
  assert.ok(body.includes("await runBillitOutboxDueMigrationStep"), "migration is awaited");
  assert.ok(body.includes("await processBillitDueOutboxIndex"), "processing is awaited");
});

test("source wiring: the due-index pass lists markers and never lists the outbox prefix", () => {
  const start = WORKER_SOURCE.indexOf("async function processBillitDueOutboxIndex");
  const end = WORKER_SOURCE.indexOf("async function runBillitOutboxDueMigrationStep");
  assert.ok(start > 0 && end > start);
  const body = WORKER_SOURCE.slice(start, end);
  assert.ok(body.includes("prefix: BILLIT_OUTBOX_DUE_PREFIX"), "lists the marker keyspace");
  assert.ok(
    !body.includes("BILLIT_OUTBOX_PREFIX"),
    "the due-index pass must never list or scan the authoritative outbox prefix",
  );
});

test("source wiring: the migration list is capped by the documented batch constant", () => {
  const start = WORKER_SOURCE.indexOf("async function runBillitOutboxDueMigrationStep");
  const end = WORKER_SOURCE.indexOf("async function runBillitDurableRecoveryScheduledPass");
  assert.ok(start > 0 && end > start);
  const body = WORKER_SOURCE.slice(start, end);
  assert.ok(body.includes("BILLIT_OUTBOX_DUE_MIGRATION_BATCH"));
  assert.ok(body.includes("limit: batch"), "the legacy list is capped per invocation");
  assert.ok(
    !body.includes("limit: 1000"),
    "the migration must never issue a one-shot 1000-value scan",
  );
});

test("source wiring: due markers are armed before the authoritative record is persisted", () => {
  const start = WORKER_SOURCE.indexOf(
    "async function _persistBillitOutboxRecordWithDueMarker",
  );
  assert.ok(start > 0);
  const body = WORKER_SOURCE.slice(start, start + 1200);
  const armAt = body.indexOf("_armBillitOutboxDueMarker");
  const putAt = body.indexOf("BOOKING_KV.put(outboxKey");
  const delAt = body.indexOf("_deleteBillitOutboxDueMarker");
  assert.ok(armAt > 0 && putAt > armAt, "arm marker before persisting the record");
  assert.ok(delAt > putAt, "retire the superseded marker only after the record is durable");
});
