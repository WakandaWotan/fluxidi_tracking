// BILLIT-DURABLE-EXPORT-RECOVERY-P0-1
//
// Pure tests for the durable Billit export recovery state machine.

import { test } from "node:test";
import assert from "node:assert/strict";

import {
  BILLIT_EXPORT_STATES,
  BACKOFF_SCHEDULE_MS,
  MAX_RETRYABLE_ATTEMPTS,
  IN_PROGRESS_STALL_MS,
  isPermanentBillitError,
  computeNextAttemptSchedule,
  buildPendingOutboxRecord,
  markOutboxInProgress,
  mergeBillitOutboxAttemptResult,
  isBillitOutboxDue,
  normalizeLegacyOutboxRecord,
} from "./billit_export_recovery.js";

const SCOPE = { tenant_id: "t1", company_id: "c1" };
const DOC = "doc-uuid-1";

test("BILLIT_EXPORT_STATES exposes the required vocabulary", () => {
  assert.equal(BILLIT_EXPORT_STATES.PENDING, "pending");
  assert.equal(BILLIT_EXPORT_STATES.IN_PROGRESS, "in_progress");
  assert.equal(BILLIT_EXPORT_STATES.SYNCED, "synced");
  assert.equal(BILLIT_EXPORT_STATES.RETRYABLE_ERROR, "retryable_error");
  assert.equal(BILLIT_EXPORT_STATES.PERMANENT_ERROR, "permanent_error");
});

test("isPermanentBillitError: known permanent codes and 4xx status", () => {
  assert.equal(
    isPermanentBillitError({ errorCode: "billit_administration_selection_required" }),
    true,
  );
  assert.equal(
    isPermanentBillitError({ errorCode: "billit_oauth_not_configured" }),
    true,
  );
  assert.equal(isPermanentBillitError({ statusCode: 400 }), true);
  assert.equal(isPermanentBillitError({ statusCode: 401 }), true);
  assert.equal(isPermanentBillitError({ statusCode: 422 }), true);
  // 429 is retryable (throttle) — must NOT be permanent
  assert.equal(isPermanentBillitError({ statusCode: 429 }), false);
});

test("isPermanentBillitError: transient signals stay retryable", () => {
  assert.equal(
    isPermanentBillitError({ errorCode: "billit_order_create_failed" }),
    false,
  );
  assert.equal(
    isPermanentBillitError({ errorCode: "billit_order_create_request_failed" }),
    false,
  );
  assert.equal(isPermanentBillitError({ statusCode: 500 }), false);
  assert.equal(isPermanentBillitError({ statusCode: 502 }), false);
  assert.equal(isPermanentBillitError({ statusCode: 503 }), false);
  assert.equal(isPermanentBillitError({ statusCode: null }), false);
  assert.equal(isPermanentBillitError({}), false);
});

test("computeNextAttemptSchedule: retryable failure schedules bounded backoff", () => {
  const now = new Date("2026-08-02T18:00:00.000Z");
  const s1 = computeNextAttemptSchedule({
    attemptCount: 1,
    errorCode: "billit_order_create_failed",
    statusCode: 502,
    now,
  });
  assert.equal(s1.state, "retryable_error");
  assert.equal(s1.retryable, true);
  assert.equal(s1.backoff_ms, BACKOFF_SCHEDULE_MS[0]);
  assert.equal(
    s1.next_attempt_at,
    new Date(now.getTime() + BACKOFF_SCHEDULE_MS[0]).toISOString(),
  );

  const s3 = computeNextAttemptSchedule({
    attemptCount: 3,
    errorCode: "billit_order_create_failed",
    statusCode: null,
    now,
  });
  assert.equal(s3.state, "retryable_error");
  assert.equal(s3.backoff_ms, BACKOFF_SCHEDULE_MS[2]);
});

test("computeNextAttemptSchedule: permanent error yields permanent_error with no schedule", () => {
  const s = computeNextAttemptSchedule({
    attemptCount: 1,
    errorCode: "billit_administration_selection_required",
    statusCode: 409,
  });
  assert.equal(s.state, "permanent_error");
  assert.equal(s.retryable, false);
  assert.equal(s.next_attempt_at, null);
  assert.equal(s.max_attempts_reached, false);
});

test("computeNextAttemptSchedule: max attempts reached is permanent (never loops)", () => {
  const s = computeNextAttemptSchedule({
    attemptCount: MAX_RETRYABLE_ATTEMPTS,
    errorCode: "billit_order_create_failed",
    statusCode: 500,
  });
  assert.equal(s.state, "permanent_error");
  assert.equal(s.retryable, false);
  assert.equal(s.next_attempt_at, null);
  assert.equal(s.max_attempts_reached, true);
});

test("buildPendingOutboxRecord: writes state=pending, retryable, immediately due", () => {
  const now = new Date("2026-08-02T18:00:00.000Z");
  const rec = buildPendingOutboxRecord({
    scope: SCOPE,
    documentId: DOC,
    documentNumber: "INV-2026-000037",
    bookingId: "b1",
    idempotencyKey: "fluxidi-billit-order-create:doc-uuid-1:sandbox:v1",
    invoiceIdempotencyKey: "inv-auto:t1:c1:b1:main:v1",
    now,
  });
  assert.equal(rec.state, "pending");
  assert.equal(rec.retryable, true);
  assert.equal(rec.attempt_count, 0);
  assert.equal(rec.next_attempt_at, now.toISOString());
  assert.equal(rec.first_seen_at, now.toISOString());
  assert.equal(rec.tenant_id, "t1");
  assert.equal(rec.company_id, "c1");
  assert.equal(rec.document_id, DOC);
  assert.equal(rec.provider, "billit");
  assert.equal(rec.environment, "sandbox");
});

test("buildPendingOutboxRecord: refuses missing scope / document", () => {
  assert.equal(buildPendingOutboxRecord({ scope: {}, documentId: DOC }), null);
  assert.equal(buildPendingOutboxRecord({ scope: SCOPE, documentId: "" }), null);
});

test("markOutboxInProgress: increments attempt count and stamps in_progress_since", () => {
  const now = new Date("2026-08-02T18:00:00.000Z");
  const prev = buildPendingOutboxRecord({
    scope: SCOPE,
    documentId: DOC,
    now,
  });
  const later = new Date(now.getTime() + 60_000);
  const next = markOutboxInProgress(prev, { now: later });
  assert.equal(next.state, "in_progress");
  assert.equal(next.attempt_count, 1);
  assert.equal(next.in_progress_since, later.toISOString());
  // pending record is not mutated
  assert.equal(prev.state, "pending");
  assert.equal(prev.attempt_count, 0);
});

test("mergeBillitOutboxAttemptResult: success returns null (delete outbox)", () => {
  const prev = buildPendingOutboxRecord({ scope: SCOPE, documentId: DOC });
  const next = mergeBillitOutboxAttemptResult({
    previous: markOutboxInProgress(prev),
    result: { ok: true, order_id: "ORD-1" },
  });
  assert.equal(next, null);
});

test("mergeBillitOutboxAttemptResult: retryable failure updates state + schedule", () => {
  const now = new Date("2026-08-02T18:00:00.000Z");
  const prev = markOutboxInProgress(
    buildPendingOutboxRecord({ scope: SCOPE, documentId: DOC, now }),
    { now },
  );
  const next = mergeBillitOutboxAttemptResult({
    previous: prev,
    result: {
      ok: false,
      error_code: "billit_order_create_failed",
      status_code: 502,
    },
    now,
  });
  assert.equal(next.state, "retryable_error");
  assert.equal(next.retryable, true);
  assert.equal(next.attempt_count, 1);
  assert.equal(next.last_error_code, "billit_order_create_failed");
  assert.equal(next.last_error_status_code, 502);
  assert.equal(next.in_progress_since, null);
  assert.equal(
    next.next_attempt_at,
    new Date(now.getTime() + BACKOFF_SCHEDULE_MS[0]).toISOString(),
  );
});

test("mergeBillitOutboxAttemptResult: permanent 4xx never schedules another retry", () => {
  const prev = markOutboxInProgress(
    buildPendingOutboxRecord({ scope: SCOPE, documentId: DOC }),
  );
  const next = mergeBillitOutboxAttemptResult({
    previous: prev,
    result: {
      ok: false,
      error_code: "billit_administration_selection_required",
      status_code: 409,
    },
  });
  assert.equal(next.state, "permanent_error");
  assert.equal(next.retryable, false);
  assert.equal(next.next_attempt_at, null);
  assert.equal(next.last_error_code, "billit_administration_selection_required");
});

test("isBillitOutboxDue: due after next_attempt_at, not before", () => {
  const now = new Date("2026-08-02T18:00:00.000Z");
  const rec = {
    state: "retryable_error",
    next_attempt_at: new Date(now.getTime() + 60_000).toISOString(),
  };
  assert.equal(isBillitOutboxDue(rec, { now }), false);
  assert.equal(
    isBillitOutboxDue(rec, { now: new Date(now.getTime() + 61_000) }),
    true,
  );
});

test("isBillitOutboxDue: permanent_error and synced are never due", () => {
  const now = new Date();
  assert.equal(
    isBillitOutboxDue({ state: "permanent_error", next_attempt_at: null }, { now }),
    false,
  );
  assert.equal(
    isBillitOutboxDue({ state: "synced", next_attempt_at: null }, { now }),
    false,
  );
});

test("isBillitOutboxDue: stalled in_progress is due after IN_PROGRESS_STALL_MS", () => {
  const now = new Date("2026-08-02T18:00:00.000Z");
  const startedRecent = new Date(now.getTime() - 60_000).toISOString();
  const startedStalled = new Date(
    now.getTime() - IN_PROGRESS_STALL_MS - 1000,
  ).toISOString();
  assert.equal(
    isBillitOutboxDue(
      { state: "in_progress", in_progress_since: startedRecent },
      { now },
    ),
    false,
  );
  assert.equal(
    isBillitOutboxDue(
      { state: "in_progress", in_progress_since: startedStalled },
      { now },
    ),
    true,
  );
});

test("normalizeLegacyOutboxRecord: adopts pre-recovery outbox shape into state machine", () => {
  const legacy = {
    provider: "billit",
    environment: "sandbox",
    tenant_id: "t1",
    company_id: "c1",
    document_id: DOC,
    document_number: "INV-2026-000037",
    booking_id: "street_1785690320683_fw5y1im0",
    state: "pending",
    error_code: "billit_order_create_failed",
    retryable: true,
    attempt_count: 1,
    idempotency_key: "fluxidi-billit-order-create:doc-uuid-1:sandbox:v1",
    invoice_idempotency_key: "inv-auto:t1:c1:b1:main:v1",
    created_at: "2026-08-02T17:06:53.134Z",
    updated_at: "2026-08-02T17:06:53.134Z",
  };
  const now = new Date("2026-08-02T18:00:00.000Z");
  const rec = normalizeLegacyOutboxRecord(legacy, { now });
  assert.equal(rec.state, "pending");
  assert.equal(rec.attempt_count, 1);
  assert.equal(rec.last_error_code, "billit_order_create_failed");
  // Legacy without next_attempt_at is treated as immediately due.
  assert.equal(isBillitOutboxDue(rec, { now }), true);
});
