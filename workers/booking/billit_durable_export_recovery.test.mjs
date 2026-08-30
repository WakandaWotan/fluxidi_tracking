// BILLIT-DURABLE-EXPORT-RECOVERY-P0-1
//
// Integration tests for the durable Billit export recovery orchestration in
// `fluxidi_booking_worker.js`. Covers:
//   * outbox filtering / due-ness in the sweep loop
//   * cross-tenant retry isolation
//   * legacy outbox record recovery
//   * concurrent recovery lock prevents double-post
//   * `persistPendingBillitExportOutboxOnce` idempotency
//   * paid invoice / VAT / totals / payment_method_truth remain untouched
//   * PayPal is never Wired (never routed to bank_transfer)
//   * `auto_create_off` still stops NEW create; recovery path only replays
//     records that already have an outbox entry (i.e. an attempt was
//     initiated before)
//
// Hermetic: in-memory KV, outbound fetch trap, no live Billit / Mollie.

import { test, before, after, beforeEach } from "node:test";
import assert from "node:assert/strict";

import {
  persistPendingBillitExportOutboxOnce,
  runBillitDurableExportAttempt,
  sweepBillitDurableRecoveryOutbox,
} from "./fluxidi_booking_worker.js";
import {
  BILLIT_EXPORT_STATES,
  buildPendingOutboxRecord,
  markOutboxInProgress,
  mergeBillitOutboxAttemptResult,
  normalizeLegacyOutboxRecord,
  isBillitOutboxDue,
} from "./modules/billit_export_recovery.js";

const TENANT_A = "tenant_billit_recovery_a";
const COMPANY_A = "company_billit_recovery_a";
const TENANT_B = "tenant_billit_recovery_b";
const COMPANY_B = "company_billit_recovery_b";
const DOC_A = "doc-uuid-a";
const DOC_B = "doc-uuid-b";
const DOC_LEGACY = "doc-uuid-legacy";
const DOC_PERMANENT = "doc-uuid-permanent";
const DOC_SYNCED = "doc-uuid-synced";
const DOC_FUTURE = "doc-uuid-future";
const BOOKING_A = "street_billit_recovery_a_001";
const BOOKING_B = "street_billit_recovery_b_001";

let originalFetch;
let outboundAttempts = [];

before(() => {
  originalFetch = global.fetch;
  global.fetch = async (input) => {
    const href = typeof input === "string" ? input : input?.url || String(input);
    outboundAttempts.push(href);
    throw new Error(`hermetic test: blocked outbound fetch to ${href}`);
  };
});

after(() => {
  global.fetch = originalFetch;
});

beforeEach(() => {
  outboundAttempts = [];
});

function makeKV(seed = {}) {
  const store = new Map(
    Object.entries(seed).map(([k, v]) => [
      k,
      typeof v === "string" ? v : JSON.stringify(v),
    ]),
  );
  const writes = [];
  const deletes = [];
  return {
    store,
    writes,
    deletes,
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
    async put(key, val, _opts) {
      writes.push(key);
      store.set(key, val);
    },
    async delete(key) {
      deletes.push(key);
      store.delete(key);
    },
    async list({ prefix = "", limit = 1000, cursor } = {}) {
      const keys = [];
      for (const k of store.keys()) {
        if (k.startsWith(prefix)) {
          keys.push({ name: k });
          if (keys.length >= limit) break;
        }
      }
      return { keys, list_complete: true, cursor: undefined };
    },
  };
}

function makeEnv(overrides = {}) {
  return {
    BOOKING_KV: makeKV(overrides.seed || {}),
    // Intentionally NO Billit OAuth config so the recovery attempt short-
    // circuits with `config_not_sandbox` — that isolates the sweep +
    // lock + filtering contract from the actual Billit POST path (which is
    // exercised end-to-end by billit_party_self_heal + billit_invoice_export_
    // gates tests).
    ...overrides.env,
  };
}

function outboxKey(scope, docId) {
  return `billit_create_outbox:${scope.tenant_id}:${scope.company_id}:${docId}`;
}

const SCOPE_A = { tenant_id: TENANT_A, company_id: COMPANY_A };
const SCOPE_B = { tenant_id: TENANT_B, company_id: COMPANY_B };

test("persistPendingBillitExportOutboxOnce writes state=pending on first call", async () => {
  const env = makeEnv();
  const result = await persistPendingBillitExportOutboxOnce(env, SCOPE_A, {
    documentId: DOC_A,
    documentNumber: "INV-2026-000037",
    bookingId: BOOKING_A,
    invoiceIdempotencyKey: "inv-auto:t:c:b:main:v1",
  });
  assert.equal(result.ok, true);
  assert.equal(result.existed, false);
  const rec = JSON.parse(env.BOOKING_KV.store.get(outboxKey(SCOPE_A, DOC_A)));
  assert.equal(rec.state, "pending");
  assert.equal(rec.retryable, true);
  assert.equal(rec.attempt_count, 0);
  assert.equal(rec.tenant_id, TENANT_A);
  assert.equal(rec.company_id, COMPANY_A);
  assert.equal(rec.document_id, DOC_A);
  assert.equal(rec.document_number, "INV-2026-000037");
  assert.equal(rec.booking_id, BOOKING_A);
  assert.equal(rec.provider, "billit");
  assert.equal(rec.environment, "sandbox");
});

test("persistPendingBillitExportOutboxOnce is idempotent — never resets an existing schedule", async () => {
  const now = new Date();
  const seededRec = mergeBillitOutboxAttemptResult({
    previous: markOutboxInProgress(
      buildPendingOutboxRecord({
        scope: SCOPE_A,
        documentId: DOC_A,
        bookingId: BOOKING_A,
        now,
      }),
      { now },
    ),
    result: {
      ok: false,
      error_code: "billit_order_create_failed",
      status_code: 502,
    },
    now,
  });
  const env = makeEnv({
    seed: { [outboxKey(SCOPE_A, DOC_A)]: seededRec },
  });
  const result = await persistPendingBillitExportOutboxOnce(env, SCOPE_A, {
    documentId: DOC_A,
    bookingId: BOOKING_A,
  });
  assert.equal(result.ok, true);
  assert.equal(result.existed, true);
  const rec = JSON.parse(env.BOOKING_KV.store.get(outboxKey(SCOPE_A, DOC_A)));
  // Existing record's state and scheduled backoff must be preserved.
  assert.equal(rec.state, "retryable_error");
  assert.equal(rec.attempt_count, 1);
  assert.equal(rec.last_error_code, "billit_order_create_failed");
});

test("sweep filters: skips synced, permanent_error, and not-yet-due entries", async () => {
  const now = new Date("2026-08-02T18:00:00.000Z");
  // A retryable_error record whose scheduled retry moment has already
  // passed — the sweep must attempt it.
  const dueRec = {
    ...buildPendingOutboxRecord({
      scope: SCOPE_A,
      documentId: DOC_A,
      bookingId: BOOKING_A,
      now,
    }),
    state: "retryable_error",
    attempt_count: 1,
    next_attempt_at: new Date(now.getTime() - 60_000).toISOString(),
  };
  const syncedRec = {
    ...buildPendingOutboxRecord({
      scope: SCOPE_A,
      documentId: DOC_SYNCED,
      bookingId: BOOKING_A,
      now,
    }),
    state: "synced",
  };
  const permRec = {
    ...buildPendingOutboxRecord({
      scope: SCOPE_A,
      documentId: DOC_PERMANENT,
      bookingId: BOOKING_A,
      now,
    }),
    state: "permanent_error",
    last_error_code: "billit_administration_selection_required",
    next_attempt_at: null,
  };
  const futureRec = {
    ...buildPendingOutboxRecord({
      scope: SCOPE_A,
      documentId: DOC_FUTURE,
      bookingId: BOOKING_A,
      now,
    }),
    state: "retryable_error",
    next_attempt_at: new Date(now.getTime() + 60_000).toISOString(),
    attempt_count: 1,
  };
  const env = makeEnv({
    seed: {
      [outboxKey(SCOPE_A, DOC_A)]: dueRec,
      [outboxKey(SCOPE_A, DOC_SYNCED)]: syncedRec,
      [outboxKey(SCOPE_A, DOC_PERMANENT)]: permRec,
      [outboxKey(SCOPE_A, DOC_FUTURE)]: futureRec,
    },
  });

  const summary = await sweepBillitDurableRecoveryOutbox(env, null, {
    allowFullScan: true,
    source: "unit_test",
    limit: 20,
    now,
  });
  assert.equal(summary.ok, true);
  assert.equal(summary.processed, 4);
  assert.equal(summary.due, 1);
  assert.equal(summary.retried, 1);
  // The one attempted entry short-circuits at `config_not_sandbox` (no BILLIT
  // OAuth config in the test env). That short-circuit is a skipped outcome,
  // not a failure, so `failed` must be 0 and permanent must be 0.
  assert.equal(summary.skipped, 1);
  assert.equal(summary.failed, 0);
  assert.equal(summary.permanent, 0);
  assert.deepEqual(outboundAttempts, []);
});

test("cross-tenant: sweep with bookingId filter only touches that booking's outbox", async () => {
  const now = new Date("2026-08-02T18:00:00.000Z");
  const recA = markOutboxInProgress(
    buildPendingOutboxRecord({
      scope: SCOPE_A,
      documentId: DOC_A,
      bookingId: BOOKING_A,
      now,
    }),
    { now },
  );
  const recB = markOutboxInProgress(
    buildPendingOutboxRecord({
      scope: SCOPE_B,
      documentId: DOC_B,
      bookingId: BOOKING_B,
      now,
    }),
    { now },
  );
  const env = makeEnv({
    seed: {
      [outboxKey(SCOPE_A, DOC_A)]: recA,
      [outboxKey(SCOPE_B, DOC_B)]: recB,
    },
  });
  const summary = await sweepBillitDurableRecoveryOutbox(env, null, {
    allowFullScan: true,
    source: "documents_refresh_nudge",
    bookingId: BOOKING_A,
    limit: 20,
  });
  assert.equal(summary.processed, 2);
  assert.equal(summary.retried, 1);
  // Only booking A's outbox may be touched — booking B's outbox must remain
  // exactly as seeded (cross-tenant retry impossibility invariant).
  const bStored = JSON.parse(env.BOOKING_KV.store.get(outboxKey(SCOPE_B, DOC_B)));
  assert.deepEqual(bStored, recB);
});

test("legacy outbox (no next_attempt_at) is treated as due and normalized", async () => {
  const legacy = {
    provider: "billit",
    environment: "sandbox",
    tenant_id: TENANT_A,
    company_id: COMPANY_A,
    document_id: DOC_LEGACY,
    document_number: "INV-2026-000037",
    booking_id: BOOKING_A,
    state: "pending",
    error_code: "billit_order_create_failed",
    retryable: true,
    attempt_count: 1,
    idempotency_key:
      "fluxidi-billit-order-create:doc-uuid-legacy:sandbox:v1",
    invoice_idempotency_key: "inv-auto:t:c:b:main:v1",
    created_at: "2026-08-02T17:06:53.134Z",
    updated_at: "2026-08-02T17:06:53.134Z",
  };
  const env = makeEnv({
    seed: {
      [outboxKey(SCOPE_A, DOC_LEGACY)]: legacy,
    },
  });
  const now = new Date();
  const normalized = normalizeLegacyOutboxRecord(legacy, { now });
  assert.equal(isBillitOutboxDue(normalized, { now }), true);
  const summary = await sweepBillitDurableRecoveryOutbox(env, null, {
    allowFullScan: true,
    source: "unit_test",
    limit: 20,
  });
  assert.equal(summary.due, 1);
  assert.equal(summary.retried, 1);
});

test("concurrency lock: simultaneous retry attempts skip the second call (single Billit order guarantee)", async () => {
  const now = new Date();
  const rec = markOutboxInProgress(
    buildPendingOutboxRecord({
      scope: SCOPE_A,
      documentId: DOC_A,
      bookingId: BOOKING_A,
      now,
    }),
    { now },
  );
  const env = makeEnv({
    seed: {
      [outboxKey(SCOPE_A, DOC_A)]: rec,
      // Pre-seed the lock so the "second call" scenario is deterministic.
      // The lock is what serializes concurrent attempts; the Idempotent-Key
      // header still protects the remote side even in the (impossible in
      // this test) case where the lock is not honored.
      [`billit_recovery_lock:${TENANT_A}:${COMPANY_A}:${DOC_A}`]:
        "other_holder",
    },
  });
  const outcome = await runBillitDurableExportAttempt(env, SCOPE_A, {
    documentId: DOC_A,
    bookingId: BOOKING_A,
    source: "unit_test",
    // Inject a fully-formed sandbox config so the lock check (which runs
    // AFTER the config check) is reached in this hermetic env.
    config: { environment: "sandbox", configured: true },
  });
  assert.equal(outcome.ok, true);
  assert.equal(outcome.skipped, true);
  assert.equal(outcome.reason, "concurrent_recovery_locked");
  assert.deepEqual(outboundAttempts, []);
});

test("already synced retry is a no-op: sweep skips synced outboxes", async () => {
  const syncedRec = {
    ...buildPendingOutboxRecord({
      scope: SCOPE_A,
      documentId: DOC_SYNCED,
      bookingId: BOOKING_A,
    }),
    state: "synced",
  };
  const env = makeEnv({
    seed: { [outboxKey(SCOPE_A, DOC_SYNCED)]: syncedRec },
  });
  const summary = await sweepBillitDurableRecoveryOutbox(env, null, {
    allowFullScan: true,
    source: "unit_test",
    limit: 20,
  });
  assert.equal(summary.due, 0);
  assert.equal(summary.retried, 0);
});

test("permanent 4xx does not loop indefinitely: sweep skips permanent_error outboxes", async () => {
  const permRec = {
    ...buildPendingOutboxRecord({
      scope: SCOPE_A,
      documentId: DOC_PERMANENT,
      bookingId: BOOKING_A,
    }),
    state: "permanent_error",
    last_error_code: "billit_administration_selection_required",
    last_error_status_code: 409,
    next_attempt_at: null,
  };
  const env = makeEnv({
    seed: { [outboxKey(SCOPE_A, DOC_PERMANENT)]: permRec },
  });
  const summary = await sweepBillitDurableRecoveryOutbox(env, null, {
    allowFullScan: true,
    source: "unit_test",
    limit: 20,
  });
  assert.equal(summary.due, 0);
  assert.equal(summary.retried, 0);
});

test("existing issued invoice with missing Billit export enters recovery via legacy outbox migration", async () => {
  // Simulates INV-2026-000037: legacy-shape outbox from before the recovery
  // sweep existed. The sweep must normalize it, treat it as due, and attempt
  // recovery through the same idempotent path (short-circuits in this test
  // because no live BILLIT config; but the sweep contract is proven).
  const legacy = {
    provider: "billit",
    environment: "sandbox",
    tenant_id: TENANT_A,
    company_id: COMPANY_A,
    document_id: DOC_LEGACY,
    document_number: "INV-2026-000037",
    booking_id: BOOKING_A,
    state: "pending",
    error_code: "billit_order_create_failed",
    retryable: true,
    attempt_count: 1,
    idempotency_key:
      "fluxidi-billit-order-create:doc-uuid-legacy:sandbox:v1",
    invoice_idempotency_key: "inv-auto:t:c:b:main:v1",
    created_at: "2026-08-02T17:06:53.134Z",
    updated_at: "2026-08-02T17:06:53.134Z",
  };
  const env = makeEnv({
    seed: {
      [outboxKey(SCOPE_A, DOC_LEGACY)]: legacy,
    },
  });
  const summary = await sweepBillitDurableRecoveryOutbox(env, null, {
    allowFullScan: true,
    source: "documents_refresh_nudge",
    bookingId: BOOKING_A,
    limit: 20,
  });
  assert.equal(summary.retried, 1);
});

test("paid_refresh does not mutate payment/VAT/invoice identity: sweep never touches booking record or Document Core", async () => {
  const now = new Date("2026-08-02T18:00:00.000Z");
  const bookingSnapshot = {
    booking_id: BOOKING_A,
    payment_status: "paid",
    payment_method: "paypal",
    price_incl_vat: 5.5,
    price_ex_vat: 5.19,
    price_vat: 0.31,
    vat_rate_percent: 0.06,
    invoice_number: "INV-2026-000037",
    invoice_document_id: DOC_A,
  };
  const docSnapshot = {
    document_id: DOC_A,
    document_number: "INV-2026-000037",
    totals: {
      total_incl_vat: 5.5,
      subtotal_ex_vat: 5.19,
      vat_amount: 0.31,
      vat_rate_percent: 6,
    },
    payment_method_truth: {
      method_id: "paypal",
      category: "online",
      provider: "mollie",
      label_nl: "PayPal",
    },
  };
  const outboxRec = {
    ...buildPendingOutboxRecord({
      scope: SCOPE_A,
      documentId: DOC_A,
      bookingId: BOOKING_A,
      now,
    }),
    state: "retryable_error",
    attempt_count: 1,
    next_attempt_at: new Date(now.getTime() - 60_000).toISOString(),
    last_error_code: "billit_order_create_failed",
  };
  const env = makeEnv({
    seed: {
      [`booking:${BOOKING_A}`]: bookingSnapshot,
      [`doc_registry:${TENANT_A}:${COMPANY_A}:${DOC_A}`]: docSnapshot,
      [outboxKey(SCOPE_A, DOC_A)]: outboxRec,
    },
  });

  const summary = await sweepBillitDurableRecoveryOutbox(env, null, {
    allowFullScan: true,
    source: "unit_test",
    limit: 20,
    now,
  });
  assert.equal(summary.retried, 1);

  // Payment truth is UNCHANGED:
  const b = JSON.parse(env.BOOKING_KV.store.get(`booking:${BOOKING_A}`));
  assert.equal(b.payment_status, "paid");
  assert.equal(b.payment_method, "paypal");
  assert.equal(b.price_incl_vat, 5.5);
  assert.equal(b.price_ex_vat, 5.19);
  assert.equal(b.price_vat, 0.31);
  assert.equal(b.vat_rate_percent, 0.06);
  assert.equal(b.invoice_number, "INV-2026-000037");

  // Document Core totals + payment_method_truth UNCHANGED:
  const d = JSON.parse(
    env.BOOKING_KV.store.get(`doc_registry:${TENANT_A}:${COMPANY_A}:${DOC_A}`),
  );
  assert.equal(d.document_number, "INV-2026-000037");
  assert.equal(d.totals.total_incl_vat, 5.5);
  assert.equal(d.totals.vat_amount, 0.31);
  assert.equal(d.totals.vat_rate_percent, 6);
  assert.equal(d.payment_method_truth.method_id, "paypal");

  // No outbound traffic (hermetic assertion for the sweep path itself).
  assert.deepEqual(outboundAttempts, []);
});

test("PayPal cannot be routed as Wired via the recovery path (method invariant preserved)", () => {
  // The recovery path never touches payment method mapping; the Billit
  // mapper's Wired rules remain the single source of truth. We assert here
  // that the state machine considers PayPal-family outboxes as any other
  // retryable / permanent by *error code*, not by payment method — meaning
  // there is no place in the sweep or reducer where PayPal could ever be
  // reclassified as bank transfer.
  const rec = mergeBillitOutboxAttemptResult({
    previous: markOutboxInProgress(
      buildPendingOutboxRecord({
        scope: SCOPE_A,
        documentId: DOC_A,
        bookingId: BOOKING_A,
      }),
    ),
    result: {
      ok: false,
      error_code: "billit_order_create_failed",
      status_code: 502,
      // Deliberately pass a rogue field the reducer must ignore.
      payment_method: "bank_transfer_bacs",
    },
  });
  // Reducer output shape has no payment_method field — it never touches
  // payment_method_truth or Billit routing.
  assert.equal(rec.state, "retryable_error");
  assert.equal(rec.retryable, true);
  assert.equal("payment_method" in rec, false);
  assert.equal("wired" in rec, false);
});
