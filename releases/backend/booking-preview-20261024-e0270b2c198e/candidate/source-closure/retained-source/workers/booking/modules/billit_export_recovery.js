// BILLIT-DURABLE-EXPORT-RECOVERY-P0-1
//
// Pure state machine + record helpers for durable Billit sandbox order-create
// recovery. Once Document Core has issued an invoice, Billit export must no
// longer depend on the phone request remaining connected. This module owns:
//
//   * the export-state vocabulary (pending / in_progress / synced /
//     retryable_error / exhausted_retryable / permanent_error);
//   * bounded exponential backoff for retryable failures;
//   * classification of Billit / self-heal error codes as permanent vs
//     retryable so infinite retry loops on real validation errors are
//     impossible;
//   * exhausted_retryable for transient upstream outages after max
//     attempts, with a long cool-down and a safe operator requeue that
//     never reopens true permanent validation/auth errors;
//   * a stable outbox-record shape carrying `state`, `next_attempt_at`,
//     `first_seen_at`, `in_progress_since`, `last_error_code`,
//     `last_error_status_code` and `attempt_count`;
//   * a small `mergeBillitOutboxAttemptResult` reducer so callers can update
//     the outbox record from a Billit attempt outcome without re-implementing
//     the state machine in every callsite.
//
// Nothing in this module touches KV, Billit, Mollie, or Peppol. It never
// mutates its inputs. Callers persist the returned records themselves.

// Local safe-string sanitizer (no external imports so this module stays a
// pure state-machine leaf that can be unit-tested without env/KV mocks).
function safeStr(value, maxLen = 200) {
  if (value === undefined || value === null) return "";
  const s = String(value);
  return s.length > maxLen ? s.slice(0, maxLen) : s;
}

export const BILLIT_EXPORT_STATES = Object.freeze({
  PENDING: "pending",
  IN_PROGRESS: "in_progress",
  SYNCED: "synced",
  RETRYABLE_ERROR: "retryable_error",
  EXHAUSTED_RETRYABLE: "exhausted_retryable",
  PERMANENT_ERROR: "permanent_error",
});

// Bounded exponential backoff (milliseconds) applied by attempt count.
// After BACKOFF_SCHEDULE_MS.length attempts a *transient* failure escalates
// to exhausted_retryable (cool-down + requeue), never to permanent_error.
// True validation/auth/admin-selection failures still map to permanent_error.
export const BACKOFF_SCHEDULE_MS = Object.freeze([
  30 * 1000, //  30s  after attempt 1
  2 * 60 * 1000, //  2m  after attempt 2
  8 * 60 * 1000, //  8m  after attempt 3
  30 * 60 * 1000, // 30m  after attempt 4
  2 * 60 * 60 * 1000, //  2h  after attempt 5
  6 * 60 * 60 * 1000, //  6h  after attempt 6
  12 * 60 * 60 * 1000, // 12h  after attempt 7
  24 * 60 * 60 * 1000, // 24h  after attempt 8
]);

export const MAX_RETRYABLE_ATTEMPTS = BACKOFF_SCHEDULE_MS.length;

// After the short backoff cycle is exhausted on a transient upstream failure,
// wait this long before the sweep automatically resumes (attempt_count reset).
// Operators may requeue earlier via requeueExhaustedBillitOutbox.
export const EXHAUSTED_COOLDOWN_MS = 24 * 60 * 60 * 1000; // 24 hours

// When an attempt is marked in_progress but never persists a terminal state
// (e.g. worker isolate died before the Billit fetch resolved), the sweep
// treats it as due for retry after this stall window.
export const IN_PROGRESS_STALL_MS = 5 * 60 * 1000; // 5 minutes

// Error codes that must never loop. These are validation / authorization /
// party-selection outcomes that require operator action, not backoff.
const PERMANENT_ERROR_CODES = new Set([
  "billit_oauth_not_configured",
  "billit_config_missing",
  "billit_config_incomplete",
  "billit_auto_create_sandbox_only",
  "billit_administration_selection_required",
  "billit_no_administration",
  "billit_party_id_missing_no_heal",
  "party_missing_required_billing_identity",
  "billit_payload_invalid",
  "billit_total_mismatch",
  "billit_customer_invalid",
  "billit_invoice_lines_invalid",
  "billit_export_sandbox_only",
  "confirm_sandbox_auto_create_required",
]);

// HTTP status codes that indicate a permanent client error. 429 remains
// retryable (rate-limit / throttle).
const PERMANENT_HTTP_STATUS = new Set([400, 401, 403, 404, 405, 409, 422]);

/**
 * Classify a Billit attempt failure as permanent (never retry) or retryable
 * (retry with backoff). Called with the sanitized error code and HTTP status
 * code produced by `ensureBillitOrderForPaidBusinessBooking`.
 */
export function isPermanentBillitError({
  errorCode = "",
  statusCode = null,
} = {}) {
  const code = safeStr(errorCode, 120);
  if (code && PERMANENT_ERROR_CODES.has(code)) return true;
  const n = Number(statusCode);
  if (Number.isFinite(n) && PERMANENT_HTTP_STATUS.has(n)) return true;
  return false;
}

/**
 * Given a completed attempt count and error classification, return the ISO
 * timestamp of the next attempt (or null when the failure is permanent /
 * max-attempts reached). Never throws.
 */
export function computeNextAttemptSchedule({
  attemptCount = 1,
  errorCode = "",
  statusCode = null,
  now = new Date(),
} = {}) {
  const permanent = isPermanentBillitError({ errorCode, statusCode });
  if (permanent) {
    return {
      state: BILLIT_EXPORT_STATES.PERMANENT_ERROR,
      next_attempt_at: null,
      retryable: false,
      backoff_ms: 0,
      max_attempts_reached: false,
    };
  }
  const attempts = Math.max(1, Number(attemptCount) || 1);
  const base = now instanceof Date ? now : new Date(now);
  if (attempts >= MAX_RETRYABLE_ATTEMPTS) {
    // Transient upstream outage exhausted the short backoff cycle.
    // Stay recoverable: cool down, then the sweep (or an operator requeue)
    // may resume with the same idempotency key. Never permanent_error.
    const next = new Date(base.getTime() + EXHAUSTED_COOLDOWN_MS);
    return {
      state: BILLIT_EXPORT_STATES.EXHAUSTED_RETRYABLE,
      next_attempt_at: next.toISOString(),
      retryable: true,
      backoff_ms: EXHAUSTED_COOLDOWN_MS,
      max_attempts_reached: true,
    };
  }
  const backoffMs = BACKOFF_SCHEDULE_MS[attempts - 1];
  const next = new Date(base.getTime() + backoffMs);
  return {
    state: BILLIT_EXPORT_STATES.RETRYABLE_ERROR,
    next_attempt_at: next.toISOString(),
    retryable: true,
    backoff_ms: backoffMs,
    max_attempts_reached: false,
  };
}

/**
 * Build the initial `state: pending` outbox record persisted BEFORE the first
 * Billit POST is attempted. Once this record exists, a client disconnect,
 * timeout, or worker restart cannot lose the export — the sweep will pick it
 * up.
 */
export function buildPendingOutboxRecord({
  scope,
  documentId,
  documentNumber = null,
  bookingId = null,
  idempotencyKey = null,
  invoiceIdempotencyKey = null,
  now = new Date(),
} = {}) {
  const tenant = safeStr(scope?.tenant_id ?? scope?.tenantId, 96);
  const company = safeStr(scope?.company_id ?? scope?.companyId, 96);
  const doc = safeStr(documentId, 200);
  if (!tenant || !company || !doc) return null;
  const nowIso = (now instanceof Date ? now : new Date(now)).toISOString();
  return {
    provider: "billit",
    environment: "sandbox",
    tenant_id: tenant,
    company_id: company,
    document_id: doc,
    document_number: safeStr(documentNumber, 80) || null,
    booking_id: safeStr(bookingId, 200) || null,
    state: BILLIT_EXPORT_STATES.PENDING,
    retryable: true,
    attempt_count: 0,
    last_error_code: null,
    last_error_status_code: null,
    idempotency_key: safeStr(idempotencyKey, 200) || null,
    invoice_idempotency_key: safeStr(invoiceIdempotencyKey, 200) || null,
    first_seen_at: nowIso,
    next_attempt_at: nowIso, // immediately eligible
    in_progress_since: null,
    created_at: nowIso,
    updated_at: nowIso,
  };
}

/**
 * Transition an outbox record to `in_progress` at the start of an attempt.
 * Increments `attempt_count` optimistically; if the attempt fails the reducer
 * uses this count to compute the next backoff.
 */
export function markOutboxInProgress(previous, { now = new Date() } = {}) {
  const nowIso = (now instanceof Date ? now : new Date(now)).toISOString();
  const src =
    previous && typeof previous === "object" && !Array.isArray(previous)
      ? previous
      : {};
  // Resuming from exhausted_retryable starts a fresh backoff cycle so a
  // recovered upstream is not immediately re-exhausted.
  const priorState = safeStr(src.state, 40);
  const baseCount =
    priorState === BILLIT_EXPORT_STATES.EXHAUSTED_RETRYABLE
      ? 0
      : Math.max(0, Number(src.attempt_count) || 0);
  const attempt = baseCount + 1;
  return {
    ...src,
    state: BILLIT_EXPORT_STATES.IN_PROGRESS,
    retryable: true,
    attempt_count: attempt,
    in_progress_since: nowIso,
    updated_at: nowIso,
  };
}

/**
 * Reducer: apply the outcome of one Billit attempt to a stored outbox
 * record. Callers pass the previous record (as read from KV, or a fresh
 * pending record if none existed) plus a sanitized `result` object:
 *   { ok: boolean, error_code?: string, status_code?: number, order_id?: string }
 * Returns the next outbox record. Returns `null` when the attempt succeeded
 * (caller must delete the outbox key). Never mutates inputs.
 */
export function mergeBillitOutboxAttemptResult({
  previous,
  result,
  now = new Date(),
} = {}) {
  const nowIso = (now instanceof Date ? now : new Date(now)).toISOString();
  const src =
    previous && typeof previous === "object" && !Array.isArray(previous)
      ? previous
      : {};
  const r = result && typeof result === "object" ? result : {};
  if (r.ok === true) {
    // Success → delete outbox. Return null so callers know to remove the key.
    return null;
  }
  const attemptCount = Math.max(
    1,
    Number(src.attempt_count) || 1,
  );
  const schedule = computeNextAttemptSchedule({
    attemptCount,
    errorCode: r.error_code,
    statusCode: r.status_code,
    now,
  });
  return {
    ...src,
    state: schedule.state,
    retryable: schedule.retryable,
    attempt_count: attemptCount,
    last_error_code: safeStr(r.error_code, 120) || null,
    last_error_status_code:
      Number.isFinite(Number(r.status_code)) && r.status_code !== null
        ? Number(r.status_code)
        : null,
    next_attempt_at: schedule.next_attempt_at,
    in_progress_since: null,
    updated_at: nowIso,
  };
}

/**
 * Should the sweep pick this outbox record up right now? True when either:
 *   * state is pending / retryable_error / exhausted_retryable and
 *     `next_attempt_at` has passed, or
 *   * state is in_progress but the previous run stalled past
 *     `IN_PROGRESS_STALL_MS` — a stalled attempt is due for retry.
 * Permanent_error and synced records are never due. Records without a
 * timestamp are treated as due (legacy compatibility with the pre-recovery
 * outbox shape).
 */
export function isBillitOutboxDue(record, { now = new Date() } = {}) {
  const src = record && typeof record === "object" ? record : null;
  if (!src) return false;
  const state = safeStr(src.state, 40);
  if (
    state === BILLIT_EXPORT_STATES.PERMANENT_ERROR ||
    state === BILLIT_EXPORT_STATES.SYNCED
  ) {
    return false;
  }
  const base = now instanceof Date ? now : new Date(now);
  const nowMs = base.getTime();
  if (state === BILLIT_EXPORT_STATES.IN_PROGRESS) {
    const startedAt = _parseIsoMs(
      src.in_progress_since || src.updated_at || src.created_at,
    );
    if (startedAt === null) return true; // legacy record with no marker
    return nowMs - startedAt >= IN_PROGRESS_STALL_MS;
  }
  // pending / retryable_error / exhausted_retryable / legacy shapes
  const dueAt = _parseIsoMs(src.next_attempt_at);
  if (dueAt === null) return true; // legacy: no schedule → treat as due
  return nowMs >= dueAt;
}

function _parseIsoMs(iso) {
  const s = safeStr(iso, 40);
  if (!s) return null;
  const n = Date.parse(s);
  return Number.isFinite(n) ? n : null;
}

/**
 * Normalize a legacy outbox record (as written by the pre-recovery code
 * path) to the new state-machine shape. Legacy records only carried
 * `attempt_count`, `state: "pending"`, `retryable: true` and no
 * `next_attempt_at`; the sweep needs the new fields to schedule further
 * retries correctly.
 */
export function normalizeLegacyOutboxRecord(record, { now = new Date() } = {}) {
  const src = record && typeof record === "object" ? record : null;
  if (!src) return null;
  const nowIso = (now instanceof Date ? now : new Date(now)).toISOString();
  const attemptCount = Math.max(1, Number(src.attempt_count) || 1);
  const resolved = _resolveLegacyState(src);
  const nextAttempt =
    resolved.state === BILLIT_EXPORT_STATES.EXHAUSTED_RETRYABLE &&
    !safeStr(src.next_attempt_at, 40)
      ? nowIso
      : safeStr(src.next_attempt_at, 40) || nowIso;
  return {
    provider: safeStr(src.provider, 24) || "billit",
    environment: safeStr(src.environment, 24) || "sandbox",
    tenant_id: safeStr(src.tenant_id ?? src.tenantId, 96),
    company_id: safeStr(src.company_id ?? src.companyId, 96),
    document_id: safeStr(src.document_id ?? src.documentId, 200),
    document_number: safeStr(src.document_number, 80) || null,
    booking_id: safeStr(src.booking_id ?? src.bookingId, 200) || null,
    state: resolved.state,
    retryable:
      resolved.state === BILLIT_EXPORT_STATES.PERMANENT_ERROR
        ? false
        : src.retryable === true || src.retryable === undefined,
    attempt_count: attemptCount,
    last_error_code: safeStr(src.error_code ?? src.last_error_code, 120) || null,
    last_error_status_code:
      Number.isFinite(Number(src.last_error_status_code))
        ? Number(src.last_error_status_code)
        : null,
    idempotency_key: safeStr(src.idempotency_key, 200) || null,
    invoice_idempotency_key: safeStr(src.invoice_idempotency_key, 200) || null,
    first_seen_at: safeStr(src.first_seen_at ?? src.created_at, 40) || nowIso,
    next_attempt_at: nextAttempt,
    in_progress_since: safeStr(src.in_progress_since, 40) || null,
    created_at: safeStr(src.created_at, 40) || nowIso,
    updated_at: safeStr(src.updated_at, 40) || nowIso,
  };
}

function _resolveLegacyState(src) {
  const state = safeStr(src.state, 40);
  // Migrate pre-requeue "permanent_error after max attempts on transient
  // upstream" into exhausted_retryable so those invoices remain recoverable.
  if (state === BILLIT_EXPORT_STATES.PERMANENT_ERROR) {
    const code = safeStr(src.error_code ?? src.last_error_code, 120);
    const status = Number(src.last_error_status_code);
    const trulyPermanent = isPermanentBillitError({
      errorCode: code,
      statusCode: Number.isFinite(status) ? status : null,
    });
    const maxReached =
      src.max_attempts_reached === true ||
      Math.max(1, Number(src.attempt_count) || 1) >= MAX_RETRYABLE_ATTEMPTS;
    if (!trulyPermanent && (maxReached || src.retryable === true)) {
      return { state: BILLIT_EXPORT_STATES.EXHAUSTED_RETRYABLE };
    }
    return { state: BILLIT_EXPORT_STATES.PERMANENT_ERROR };
  }
  const valid = new Set(Object.values(BILLIT_EXPORT_STATES));
  if (valid.has(state)) return { state };
  return { state: BILLIT_EXPORT_STATES.PENDING };
}

/**
 * Whether an outbox record may be safely requeued. Only exhausted_retryable
 * (or legacy permanent_error that was actually a max-attempts transient
 * outage) may be requeued. True permanent validation/auth/admin-selection
 * errors are refused.
 */
export function canRequeueBillitOutbox(record) {
  const src = record && typeof record === "object" ? record : null;
  if (!src) return { ok: false, reason: "missing_record" };
  const state = safeStr(src.state, 40);
  const code = safeStr(src.last_error_code ?? src.error_code, 120);
  const status = Number(src.last_error_status_code);
  if (
    isPermanentBillitError({
      errorCode: code,
      statusCode: Number.isFinite(status) ? status : null,
    })
  ) {
    return { ok: false, reason: "true_permanent_error" };
  }
  if (state === BILLIT_EXPORT_STATES.EXHAUSTED_RETRYABLE) {
    return { ok: true, reason: "exhausted_retryable" };
  }
  if (state === BILLIT_EXPORT_STATES.PERMANENT_ERROR) {
    // Legacy max-attempts misclassification — only if not a true permanent.
    return { ok: true, reason: "legacy_max_attempts_permanent" };
  }
  if (
    state === BILLIT_EXPORT_STATES.RETRYABLE_ERROR ||
    state === BILLIT_EXPORT_STATES.PENDING
  ) {
    // Already recoverable via normal sweep; requeue is a no-op accelerator.
    return { ok: true, reason: "already_retryable" };
  }
  return { ok: false, reason: `state_${state || "unknown"}` };
}

/**
 * Pure requeue: reset attempt_count, set pending, schedule immediately.
 * Preserves idempotency_key, document identity, tenant/company, and last
 * error diagnostics for audit. Never mutates inputs. Returns null when
 * requeue is not allowed.
 */
export function requeueExhaustedBillitOutbox(record, { now = new Date() } = {}) {
  const gate = canRequeueBillitOutbox(record);
  if (!gate.ok) return null;
  const src = record;
  const nowIso = (now instanceof Date ? now : new Date(now)).toISOString();
  return {
    ...src,
    state: BILLIT_EXPORT_STATES.PENDING,
    retryable: true,
    attempt_count: 0,
    next_attempt_at: nowIso,
    in_progress_since: null,
    updated_at: nowIso,
    // Preserve idempotency_key, last_error_*, document_id, booking_id, etc.
  };
}
