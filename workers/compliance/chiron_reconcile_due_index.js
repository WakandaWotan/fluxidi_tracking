// CHIRON-COMPLIANCE-DUE-INDEX-P0
//
// Ordered pending/due-marker helpers for the Chiron reconcile path.
// Markers live in the existing COMPLIANCE_KV namespace and are disposable
// hints. The authoritative compliance-event record (plus its Chiron export
// status doc) remains the only state authority.
//
// Official Cloudflare KV limits (retrieved 2026-08-18):
//   https://developers.cloudflare.com/kv/platform/limits/
//   key size      = 512 bytes
//   key metadata  = 1024 bytes (serialized JSON)
//
// Marker key: chiron_reconcile_due:v1:<16-digit-due-at-ms>:<32-hex-ref>
// The ref is SHA-256(eventKey) truncated to 32 hex chars (Web Crypto only;
// never Math.random()). Tenant, company, booking, ride and financial
// identifiers never appear in the marker key or in due-index log lines.

export const CHIRON_RECONCILE_DUE_INDEX_VERSION = 1;
export const CHIRON_RECONCILE_DUE_PREFIX = "chiron_reconcile_due:v1:";
export const CHIRON_RECONCILE_DUE_DONE_KEY = "chiron_reconcile_due:v1:!done";
export const CHIRON_RECONCILE_DUE_MIGRATION_KEY = "chiron_reconcile_due_mig:v1";
export const CHIRON_RECONCILE_DUE_MIGRATION_VERSION = 1;
export const CHIRON_RECONCILE_DUE_MIGRATION_BATCH = 25;
export const CHIRON_RECONCILE_DUE_PROCESS_LIMIT = 20;
export const CHIRON_RECONCILE_DUE_AT_DIGITS = 16;
export const CHIRON_RECONCILE_DUE_LEGACY_EVENT_PREFIX = "compliance_event_v1/";
export const CHIRON_RECONCILE_WAKEUP_PREFIX = "chiron_reconcile_wakeup:v1:";
export const CHIRON_WAITING_RECHECK_MS = 5 * 60 * 1000;
export const CHIRON_BLOCKED_RECHECK_MS = 5 * 60 * 1000;
// Retryable/queued leftovers were re-selected every */5 tick (due-at-0).
// Park them past one cron interval so an idle worker stops value-reading
// the same 20 events forever. Append-time auto-submit is unchanged.
export const CHIRON_RETRYABLE_RECHECK_MS = 30 * 60 * 1000;
export const CHIRON_DUE_RECOVER_CAUGHT_UP_SLACK_MS = 60 * 1000;
// Existing attempt_count drives this ladder. No second retry clock.
// attempt 1 → 15 min, 2 → 1 h, 3 → 6 h, 4+ → 24 h.
// At CHIRON_RETRY_BACKOFF_MAX_ATTEMPTS the marker is retired (dueAt null).
export const CHIRON_RETRY_BACKOFF_STEPS_MS = Object.freeze([
  15 * 60 * 1000,
  60 * 60 * 1000,
  6 * 60 * 60 * 1000,
  24 * 60 * 60 * 1000,
]);
export const CHIRON_RETRY_BACKOFF_MAX_ATTEMPTS = 6;
export const CHIRON_BLOCKED_BY_FAILED_DEPARTURE = "blocked_by_failed_departure";
// Bounded unmarked-event recovery. Never a full five-minute history scan.
// Progress is a durable per-scope watermark (oldest-first, 20 keys/tick) so
// newer keys and a sliding clock cannot hide an unexamined event.
export const CHIRON_RECONCILE_RECOVER_PREFIX = "chiron_reconcile_recover:v1/tenant/";
export const CHIRON_DUE_RECOVER_STATE_VERSION = 1;
export const CHIRON_DUE_RECOVER_WINDOW_MS = 30 * 60 * 1000;
export const CHIRON_DUE_RECOVER_CATCHUP_WINDOW_MS = 2 * 60 * 60 * 1000;
export const CHIRON_DUE_RECOVER_CATCHUP_WALL_MS = 2 * 60 * 60 * 1000;
export const CHIRON_DUE_RECOVER_BATCH = 20;
export const CHIRON_DUE_RECOVER_PREFIX_DIGITS = 6;
export const CHIRON_DUE_RECOVER_PREFIXES_PER_TICK = 2;

/** Official Cloudflare Workers KV limits (docs retrieved 2026-08-18). */
export const CF_KV_KEY_MAX_BYTES = 512;
export const CF_KV_METADATA_MAX_BYTES = 1024;

const MAX_DUE_AT_MS = 10 ** CHIRON_RECONCILE_DUE_AT_DIGITS - 1;

export class ChironDueIndexTestCrash extends Error {
  constructor(step) {
    super(`chiron_due_index_test_crash:${step}`);
    this.name = "ChironDueIndexTestCrash";
    this.step = step;
  }
}

function safeText(value, maxLen = 1024) {
  if (value === undefined || value === null) return "";
  const text = String(value);
  return text.length > maxLen ? text.slice(0, maxLen) : text;
}

function parseIsoMs(iso) {
  const raw = safeText(iso, 64);
  if (!raw) return null;
  const ms = Date.parse(raw);
  return Number.isFinite(ms) ? ms : null;
}

export function encodeChironDueAtMs(dueAtMs) {
  const n = Number(dueAtMs);
  if (!Number.isFinite(n)) return null;
  const clamped = Math.min(MAX_DUE_AT_MS, Math.max(0, Math.floor(n)));
  return String(clamped).padStart(CHIRON_RECONCILE_DUE_AT_DIGITS, "0");
}

/**
 * Deterministic opaque event reference. Uses Web Crypto SHA-256 only.
 */
export async function chironOpaqueEventRef(eventKey) {
  const key = safeText(eventKey, 1024);
  if (!key) return "";
  const subtle = globalThis.crypto?.subtle;
  if (!subtle || typeof subtle.digest !== "function") {
    throw new Error("web_crypto_unavailable");
  }
  const digest = await subtle.digest("SHA-256", new TextEncoder().encode(key));
  const bytes = new Uint8Array(digest);
  let hex = "";
  for (let i = 0; i < 16; i += 1) {
    hex += bytes[i].toString(16).padStart(2, "0");
  }
  return hex;
}

export async function buildChironDueMarkerKey(dueAtMs, eventKey) {
  const encoded = encodeChironDueAtMs(dueAtMs);
  const ref = await chironOpaqueEventRef(eventKey);
  if (encoded === null || !ref) return null;
  return `${CHIRON_RECONCILE_DUE_PREFIX}${encoded}:${ref}`;
}

export function parseChironDueMarkerKey(name) {
  const key = safeText(name, 512);
  if (!key.startsWith(CHIRON_RECONCILE_DUE_PREFIX)) {
    return { ok: false, error: "not_a_due_marker" };
  }
  if (key === CHIRON_RECONCILE_DUE_DONE_KEY) {
    return { ok: false, error: "migration_done_sentinel" };
  }
  const rest = key.slice(CHIRON_RECONCILE_DUE_PREFIX.length);
  const sep = rest.indexOf(":");
  if (sep !== CHIRON_RECONCILE_DUE_AT_DIGITS) {
    return { ok: false, error: "malformed_due_marker" };
  }
  const digits = rest.slice(0, sep);
  const ref = rest.slice(sep + 1);
  if (!/^[0-9]{16}$/.test(digits)) return { ok: false, error: "malformed_due_at" };
  if (!/^[0-9a-f]{32}$/.test(ref)) return { ok: false, error: "malformed_ref" };
  return { ok: true, dueAtMs: Number(digits), ref, markerKey: key };
}

export function isChironReconcileDueDoneSentinel(name) {
  return safeText(name, 512) === CHIRON_RECONCILE_DUE_DONE_KEY;
}

export function dueListContainsMigrationDone(entries) {
  const rows = Array.isArray(entries) ? entries : [];
  return rows.some((entry) => isChironReconcileDueDoneSentinel(entry?.name));
}

/**
 * Minimum metadata required to resolve the authoritative date-index event
 * key. The event key itself is the pointer; it is never written into the
 * marker key and must never be logged by due-index helpers.
 */
export function buildChironDueMarkerMetadata(eventKey) {
  const ek = safeText(eventKey, 1024);
  if (!ek || !ek.startsWith(CHIRON_RECONCILE_DUE_LEGACY_EVENT_PREFIX)) return null;
  return { v: CHIRON_RECONCILE_DUE_INDEX_VERSION, ek };
}

export function chironDueMarkerMetadataJsonBytes(metadata) {
  if (!metadata || typeof metadata !== "object") return 0;
  return new TextEncoder().encode(JSON.stringify(metadata)).length;
}

export function chironDueMarkerKeyByteLength(markerKey) {
  return new TextEncoder().encode(safeText(markerKey, 1024)).length;
}

export function parseComplianceEventKeyScope(eventKey) {
  const key = safeText(eventKey, 1024);
  const match = /^compliance_event_v1\/tenant\/([^/]+)\/company\/([^/]+)\//.exec(
    key,
  );
  if (!match) return null;
  return { tenantSegment: match[1], companySegment: match[2] };
}

export function eventKeyMatchesScope(eventKey, tenantSegment, companySegment) {
  const parsed = parseComplianceEventKeyScope(eventKey);
  if (!parsed) return false;
  return (
    parsed.tenantSegment === safeText(tenantSegment, 128) &&
    parsed.companySegment === safeText(companySegment, 128)
  );
}

export async function readChironDueMarkerIdentity(entry) {
  const src = entry && typeof entry === "object" ? entry : null;
  if (!src) return { ok: false, error: "missing_entry" };
  const parsed = parseChironDueMarkerKey(src.name);
  if (!parsed.ok) {
    return { ok: false, error: parsed.error, markerKey: safeText(src.name, 512) };
  }
  const meta =
    src.metadata && typeof src.metadata === "object" && !Array.isArray(src.metadata)
      ? src.metadata
      : null;
  const eventKey = safeText(meta?.ek, 1024);
  if (!eventKey) {
    return { ok: false, error: "missing_marker_metadata", markerKey: parsed.markerKey };
  }
  const expectedRef = await chironOpaqueEventRef(eventKey);
  if (!expectedRef || expectedRef !== parsed.ref) {
    return { ok: false, error: "marker_ref_mismatch", markerKey: parsed.markerKey };
  }
  return {
    ok: true,
    markerKey: parsed.markerKey,
    dueAtMs: parsed.dueAtMs,
    ref: parsed.ref,
    eventKey,
  };
}

/**
 * Server-owned due time from the authoritative Chiron export status.
 * `null` means no marker (terminal / not retryable / unknown fail-closed).
 * Missing status means a new event is immediately due.
 */
export function chironRetryBackoffMs(attemptCount) {
  const n = Math.max(1, Math.floor(Number(attemptCount) || 1));
  const steps = CHIRON_RETRY_BACKOFF_STEPS_MS;
  return steps[Math.min(n, steps.length) - 1];
}

export function chironRetryAttemptCount(statusDoc) {
  const perPayload = Number(statusDoc?.outbound_fingerprint_definitive_attempts);
  if (Number.isFinite(perPayload) && perPayload > 0) return Math.floor(perPayload);
  const attempts = Number(statusDoc?.attempt_count);
  if (Number.isFinite(attempts) && attempts > 0) return Math.floor(attempts);
  return 1;
}

/**
 * Next due time for a temporary failure, using the existing attempt counter.
 * `null` = stop (max attempts). `0` = cooldown already elapsed, due once.
 */
export function chironBackoffDueAtMs(statusDoc, nowMs, options = {}) {
  const now = Number(nowMs);
  if (!Number.isFinite(now)) return null;
  const maxAttempts =
    Number(options.maxAttempts) || CHIRON_RETRY_BACKOFF_MAX_ATTEMPTS;
  const attempts = chironRetryAttemptCount(statusDoc);
  if (attempts >= maxAttempts) return null;
  const wait = chironRetryBackoffMs(attempts);
  const last = parseIsoMs(statusDoc?.last_attempt_at);
  if (last !== null && now - last < wait) return last + wait;
  if (last !== null) return 0;
  return now + wait;
}

export const CHIRON_DUE_HISTORICAL_WINDOW_MS = 14 * 24 * 60 * 60 * 1000;
export const CHIRON_DUE_RETRY_SOON_MS = 15 * 60 * 1000;
const CHIRON_PAYLOAD_TERMINAL_REASONS = new Set([
  "afstand",
  "vertrekpunt_lengtegraad",
  "vertrekpunt_breedtegraad",
  "aankomstpunt_lengtegraad",
  "aankomstpunt_breedtegraad",
  "invalid_zero_coordinate_pair",
]);

/**
 * V2. Only work that can change within minutes stays on the 5-minute cadence
 * (RETRY_SOON). Historical exclusions and finished validation failures leave
 * the due index. Stale builds park on the 24-hour backoff step.
 */
export function classifyChironDueWorkV2({
  status,
  eventAtMs,
  departure,
  nowMs,
  cutoffMs = null,
} = {}) {
  const now = Number(nowMs);
  const eventAt = Number(eventAtMs);
  const state = safeText(status?.sync_state, 32).toLowerCase();
  const reason = safeText(status?.reason_code, 96) || safeText(status?.sanitized_error, 96);
  const ageMs = Number.isFinite(eventAt) ? now - eventAt : null;
  const beforeCutoff =
    Number.isFinite(Number(cutoffMs)) &&
    Number.isFinite(eventAt) &&
    eventAt < Number(cutoffMs);
  const historicalAge = ageMs !== null && ageMs > CHIRON_DUE_HISTORICAL_WINDOW_MS;

  const done = (why) => ({ klass: "DONE", dueAtMs: null, reason: why });
  const terminal = (why) => ({ klass: "TERMINAL", dueAtMs: null, reason: why });
  const historical = (why) => ({
    klass: "NON_ACTIONABLE_HISTORICAL",
    dueAtMs: null,
    reason: why,
  });
  const soon = (why, dueAtMs) => ({ klass: "RETRY_SOON", dueAtMs, reason: why });
  const backoff = (why, dueAtMs) => ({ klass: "RETRY_BACKOFF", dueAtMs, reason: why });

  if (
    state === "synced" ||
    state === "verification_required" ||
    state === "departure_confirmed_external"
  ) {
    return done(state);
  }
  if (state === "waiting_for_departure" && chironDepartureIsTerminalFailure(departure, now)) {
    return terminal("blocked_by_failed_departure");
  }
  if (
    state === "blocked_by_failed_departure" ||
    reason === CHIRON_BLOCKED_BY_FAILED_DEPARTURE
  ) {
    return terminal("blocked_by_failed_departure");
  }
  if (reason === "event_before_testflow_start" || (beforeCutoff && state === "blocked")) {
    return historical("event_before_testflow_start");
  }
  if (state === "blocked" && CHIRON_PAYLOAD_TERMINAL_REASONS.has(reason)) {
    return terminal(reason);
  }
  if (!status) {
    if (beforeCutoff || historicalAge) return historical(beforeCutoff ? "before_testflow_cutoff" : "outside_reconcile_window");
    return soon("no_status_recent", now);
  }
  if (state === "pending_build" || state === "pending") {
    const last = parseIsoMs(status.last_attempt_at);
    const fresh = last !== null && now - last < CHIRON_DUE_RETRY_SOON_MS;
    if (fresh && !historicalAge) return soon(state, last + CHIRON_DUE_RETRY_SOON_MS);
    return backoff(state, now + 24 * 60 * 60 * 1000);
  }
  if (state === "waiting_for_departure") {
    const last = parseIsoMs(status.last_attempt_at);
    const depState = safeText(departure?.sync_state, 32).toLowerCase();
    if (depState === "synced" || depState === "departure_confirmed_external") {
      return soon("departure_ready", now);
    }
    const depYoung =
      last !== null &&
      now - last < CHIRON_DUE_RETRY_SOON_MS &&
      (depState === "pending" || depState === "pending_build");
    if (depYoung) return soon("waiting_for_departure", last + CHIRON_DUE_RETRY_SOON_MS);
    return backoff("waiting_for_departure", now + 24 * 60 * 60 * 1000);
  }
  if (state === "retryable_failed" || state === "queued" || state === "failed") {
    const dueAt = computeChironReconcileDueAtMs(status, now);
    if (dueAt === null) return terminal("max_attempts_or_not_retryable");
    if (dueAt > now && dueAt - now <= CHIRON_DUE_RETRY_SOON_MS) return soon(state, dueAt);
    if (dueAt === 0) return backoff(state, now + chironRetryBackoffMs(chironRetryAttemptCount(status)));
    return backoff(state, dueAt);
  }
  if (state === "blocked") {
    return historical(reason || "blocked");
  }
  if (historicalAge || beforeCutoff) return historical("historical_event");
  return { klass: "UNKNOWN", dueAtMs: null, reason: state || "unclassified" };
}

export function chironDepartureIsTerminalFailure(statusDoc, nowMs, options = {}) {
  if (!statusDoc || typeof statusDoc !== "object" || Array.isArray(statusDoc)) return false;
  const state = safeText(statusDoc.sync_state, 32).toLowerCase();
  if (state !== "failed") return false;
  return computeChironReconcileDueAtMs(statusDoc, nowMs, options) === null;
}

export function computeChironReconcileDueAtMs(statusDoc, nowMs, options = {}) {
  const now = Number(nowMs);
  if (!Number.isFinite(now)) return null;
  const pendingStaleMs = Number(options.pendingStaleMs) || 60 * 1000;
  const definitiveMaxAttempts = Number(options.definitiveMaxAttempts) || CHIRON_RETRY_BACKOFF_MAX_ATTEMPTS;
  const blockedRecheckMs = Number(options.blockedRecheckMs) || CHIRON_BLOCKED_RECHECK_MS;
  const departureConfirmedExternal =
    safeText(options.departureConfirmedExternal, 64) || "departure_confirmed_external";

  if (!statusDoc || typeof statusDoc !== "object" || Array.isArray(statusDoc)) {
    return 0;
  }
  const state = safeText(statusDoc.sync_state, 32).toLowerCase();
  if (
    state === "synced" ||
    state === "verification_required" ||
    state === departureConfirmedExternal
  ) {
    return null;
  }
  if (state === "pending") {
    const last = parseIsoMs(statusDoc.last_attempt_at);
    if (last !== null && now - last < pendingStaleMs) return last + pendingStaleMs;
    return 0;
  }
  // A young pending_build is an in-flight append/cron attempt. Keep it off
  // the due-at-0 lane so the same hash-ordered historical builds cannot
  // monopolize the process cap. Once stale, it becomes immediately due again.
  if (state === "pending_build") {
    const last = parseIsoMs(statusDoc.last_attempt_at);
    if (last !== null && now - last < pendingStaleMs) return last + pendingStaleMs;
    return 0;
  }
  if (
    state === "blocked_by_failed_departure" ||
    safeText(statusDoc.reason_code, 64) === CHIRON_BLOCKED_BY_FAILED_DEPARTURE ||
    safeText(statusDoc.sanitized_error, 64) === CHIRON_BLOCKED_BY_FAILED_DEPARTURE
  ) {
    return null;
  }
  if (state === "waiting_for_departure") {
    if (options.pairedDepartureTerminal === true) return null;
    return chironBackoffDueAtMs(statusDoc, now, {
      maxAttempts: Number(options.maxAttempts) || CHIRON_RETRY_BACKOFF_MAX_ATTEMPTS,
    });
  }
  if (state === "retryable_failed" || state === "queued") {
    return chironBackoffDueAtMs(statusDoc, now, {
      maxAttempts: Number(options.maxAttempts) || CHIRON_RETRY_BACKOFF_MAX_ATTEMPTS,
    });
  }
  if (state === "failed") {
    if (statusDoc.failure_kind === "definitive") {
      const attempts = chironRetryAttemptCount(statusDoc);
      if (attempts >= (Number(options.maxAttempts) || definitiveMaxAttempts)) return null;
      return chironBackoffDueAtMs(statusDoc, now, {
        maxAttempts: Number(options.maxAttempts) || definitiveMaxAttempts,
      });
    }
    const httpStatus = Number(statusDoc.external_status_code);
    const foutenCount = Number(statusDoc.fouten_count);
    const gotChironResponse =
      Number.isFinite(httpStatus) &&
      httpStatus > 0 &&
      (httpStatus < 200 ||
        httpStatus >= 300 ||
        (Number.isFinite(foutenCount) && foutenCount > 0));
    if (gotChironResponse) {
      return chironBackoffDueAtMs(statusDoc, now, {
        maxAttempts: Number(options.maxAttempts) || definitiveMaxAttempts,
      });
    }
    return null;
  }
  if (state === "blocked") {
    if (options.blockedIsTerminal === true) return null;
    const last = parseIsoMs(statusDoc.last_attempt_at);
    const base = last !== null ? last : now;
    return base + blockedRecheckMs;
  }
  return null;
}

/**
 * Recency from the date-index event key (`.../YYYY/MM/DD/<13-digit-ms>_...`).
 * Used only to rank already-listed due markers ÔÇö no extra KV read.
 */
export function chironDueMarkerEventRecencyMs(eventKey) {
  const key = safeText(eventKey, 1024);
  const match = /\/(\d{4})\/(\d{2})\/(\d{2})\/(\d{13})_/.exec(key);
  if (match) {
    const ms = Number(match[4]);
    return Number.isFinite(ms) ? ms : 0;
  }
  return 0;
}

function utcDateParts(ms) {
  const d = new Date(ms);
  return {
    y: String(d.getUTCFullYear()).padStart(4, "0"),
    m: String(d.getUTCMonth() + 1).padStart(2, "0"),
    day: String(d.getUTCDate()).padStart(2, "0"),
  };
}

/**
 * Timestamp-seek prefixes for recent date-index keys. A 6-digit ms bucket
 * is ~2.7 h and does not match older same-day history (e.g. 1780000… vs
 * 1789992…). Day boundaries emit a second prefix.
 */
export function buildChironRecentDateIndexPrefixes({
  tenantSeg,
  companySeg,
  fromMs,
  toMs,
  digits = CHIRON_DUE_RECOVER_PREFIX_DIGITS,
} = {}) {
  const tenant = safeText(tenantSeg, 128);
  const company = safeText(companySeg, 128);
  const from = Math.floor(Number(fromMs));
  const to = Math.floor(Number(toMs));
  const width = Math.min(13, Math.max(1, Math.floor(Number(digits) || CHIRON_DUE_RECOVER_PREFIX_DIGITS)));
  if (!tenant || !company || !Number.isFinite(from) || !Number.isFinite(to) || to < from) {
    return [];
  }
  const step = 10 ** (13 - width);
  const prefixes = [];
  const seen = new Set();
  const pushAt = (ms) => {
    const parts = utcDateParts(ms);
    const bucket = String(Math.max(0, Math.floor(ms))).padStart(13, "0").slice(0, width);
    const prefix = [
      CHIRON_RECONCILE_DUE_LEGACY_EVENT_PREFIX.slice(0, -1),
      "tenant",
      tenant,
      "company",
      company,
      parts.y,
      parts.m,
      parts.day,
      bucket,
    ].join("/");
    if (seen.has(prefix)) return;
    seen.add(prefix);
    prefixes.push(prefix);
  };
  let t = from;
  let guard = 0;
  while (t <= to && guard < 16) {
    pushAt(t);
    const next = Math.floor(t / step) * step + step;
    t = next <= t ? t + step : next;
    guard += 1;
  }
  pushAt(to);
  return prefixes;
}

/**
 * Sequential date-index prefixes from a watermark toward `toMs`.
 * Does not jump to `toMs`, so a long pause cannot skip unexamined hours.
 */
export function buildChironDateIndexPrefixesFromWatermark({
  tenantSeg,
  companySeg,
  fromMs,
  toMs,
  digits = CHIRON_DUE_RECOVER_PREFIX_DIGITS,
  limit = CHIRON_DUE_RECOVER_PREFIXES_PER_TICK,
} = {}) {
  const tenant = safeText(tenantSeg, 128);
  const company = safeText(companySeg, 128);
  const from = Math.floor(Number(fromMs));
  const to = Math.floor(Number(toMs));
  const width = Math.min(13, Math.max(1, Math.floor(Number(digits) || CHIRON_DUE_RECOVER_PREFIX_DIGITS)));
  const max = Math.min(16, Math.max(1, Math.floor(Number(limit) || 1)));
  if (!tenant || !company || !Number.isFinite(from) || !Number.isFinite(to) || to < from) {
    return [];
  }
  const step = 10 ** (13 - width);
  const prefixes = [];
  const seen = new Set();
  const pushAt = (ms) => {
    const parts = utcDateParts(ms);
    const bucket = String(Math.max(0, Math.floor(ms))).padStart(13, "0").slice(0, width);
    const prefix = [
      CHIRON_RECONCILE_DUE_LEGACY_EVENT_PREFIX.slice(0, -1),
      "tenant",
      tenant,
      "company",
      company,
      parts.y,
      parts.m,
      parts.day,
      bucket,
    ].join("/");
    if (seen.has(prefix)) return;
    seen.add(prefix);
    prefixes.push(prefix);
  };
  let t = from;
  let guard = 0;
  while (t <= to && guard < max) {
    pushAt(t);
    const next = Math.floor(t / step) * step + step;
    t = next <= t ? t + step : next;
    guard += 1;
  }
  return prefixes;
}

export function chironEventKeyAfterRecoverWatermark(eventKey, fromMs, lastKey) {
  const name = safeText(eventKey, 1024);
  if (!name) return false;
  const ts = chironDueMarkerEventRecencyMs(name);
  const floor = Math.max(0, Math.floor(Number(fromMs) || 0));
  if (ts > floor) return true;
  if (ts < floor) return false;
  const last = safeText(lastKey, 1024);
  if (!last) return true;
  return name > last;
}

export function isChironFullScopeEventListPrefix(prefix) {
  return /^compliance_event_v1\/tenant\/[^/]+\/company\/[^/]+\/$/.test(
    safeText(prefix, 1024),
  );
}

export function buildChironScopeRecoverKey(tenantSeg, companySeg) {
  const tenant = safeText(tenantSeg, 128);
  const company = safeText(companySeg, 128);
  if (!tenant || !company) return "";
  return `${CHIRON_RECONCILE_RECOVER_PREFIX}${tenant}/company/${company}`;
}

export function chironDateIndexPrefixCoveredThroughMs(prefix) {
  const m = /\/(\d{4})\/(\d{2})\/(\d{2})\/(\d+)$/.exec(safeText(prefix, 1024));
  if (!m) return null;
  const digits = m[4];
  const start = Number(digits.padEnd(13, "0"));
  if (!Number.isFinite(start)) return null;
  const step = 10 ** (13 - digits.length);
  return start + step - 1;
}

export function normalizeChironDueRecoverState(raw, { initialFromMs = 0 } = {}) {
  const fallback = Math.max(0, Math.floor(Number(initialFromMs) || 0));
  const src = raw && typeof raw === "object" && !Array.isArray(raw) ? raw : null;
  if (!src || Number(src.version) !== CHIRON_DUE_RECOVER_STATE_VERSION) {
    return {
      version: CHIRON_DUE_RECOVER_STATE_VERSION,
      from_ms: fallback,
      last_key: null,
      prefix: null,
      cursor: null,
    };
  }
  return {
    version: CHIRON_DUE_RECOVER_STATE_VERSION,
    from_ms: Math.max(0, Math.floor(Number(src.from_ms) || fallback)),
    last_key: safeText(src.last_key, 1024) || null,
    prefix: safeText(src.prefix, 1024) || null,
    cursor: safeText(src.cursor, 1024) || null,
  };
}

export function chironDueRecoverStateEqual(a, b) {
  if (!a || !b) return false;
  return (
    a.from_ms === b.from_ms &&
    a.last_key === b.last_key &&
    a.prefix === b.prefix &&
    a.cursor === b.cursor
  );
}

export function chironDueRecoverWatermarkCaughtUp(state, nowMs, slackMs = CHIRON_DUE_RECOVER_CAUGHT_UP_SLACK_MS) {
  const now = Number(nowMs);
  const from = Number(state?.from_ms);
  const slack = Math.max(0, Math.floor(Number(slackMs) || 0));
  if (!Number.isFinite(now) || !Number.isFinite(from)) return false;
  if (state?.prefix || state?.cursor) return false;
  return from >= now - slack;
}

/** Same-invocation COMPLIANCE_KV.get cache. Invalidated on put/delete. */
export function memoizeComplianceKvReads(ns) {
  if (!ns || typeof ns.get !== "function") return ns;
  const cache = new Map();
  const cacheKeyFor = (key, opts) => {
    const type =
      opts && typeof opts === "object"
        ? String(opts.type || "")
        : String(opts || "");
    return `${type}::${key}`;
  };
  const invalidate = (key) => {
    const suffix = `::${key}`;
    for (const cached of [...cache.keys()]) {
      if (cached.endsWith(suffix)) cache.delete(cached);
    }
  };
  return {
    get: async (key, opts) => {
      const cacheKey = cacheKeyFor(key, opts);
      if (cache.has(cacheKey)) return cache.get(cacheKey);
      const value = await ns.get(key, opts);
      cache.set(cacheKey, value);
      return value;
    },
    getWithMetadata: async (...args) => {
      if (typeof ns.getWithMetadata !== "function") {
        return { value: null, metadata: null };
      }
      return ns.getWithMetadata(...args);
    },
    list: (...args) => ns.list(...args),
    put: async (key, value, opts) => {
      invalidate(key);
      return ns.put(key, value, opts);
    },
    delete: async (key) => {
      invalidate(key);
      return ns.delete(key);
    },
  };
}

export async function buildChironWakeupKey(eventKey) {
  const ref = await chironOpaqueEventRef(eventKey);
  if (!ref) return null;
  return `${CHIRON_RECONCILE_WAKEUP_PREFIX}${ref}`;
}

export async function armChironWakeupHint(kv, eventKey) {
  if (!kv || typeof kv.put !== "function") return null;
  const key = await buildChironWakeupKey(eventKey);
  const metadata = buildChironDueMarkerMetadata(eventKey);
  if (!key || !metadata) return null;
  await kv.put(key, JSON.stringify({ v: CHIRON_RECONCILE_DUE_INDEX_VERSION }), {
    metadata,
  });
  return key;
}

export async function retireChironWakeupHint(kv, eventKey) {
  if (!kv || typeof kv.delete !== "function") return false;
  const key = await buildChironWakeupKey(eventKey);
  if (!key) return false;
  try {
    await kv.delete(key);
    return true;
  } catch (_) {
    return false;
  }
}

/**
 * Choose due markers from a lexicographic `list()` page. Stops at the first
 * future timestamp so a quiet pass never value-reads an event.
 *
 * All immediately-due markers on the page are collected (the `!done`
 * sentinel is skipped). When more than `limit` are due, newer source
 * events are selected first so historical due-at-0 retries cannot starve
 * a just-appended ride whose opaque ref sorts later.
 */
export function selectDueChironMarkers(entries, { nowMs, limit, scopeFilter } = {}) {
  const rows = Array.isArray(entries) ? entries : [];
  const cap = Math.max(1, Math.floor(Number(limit) || CHIRON_RECONCILE_DUE_PROCESS_LIMIT));
  const now = Number(nowMs);
  const tenantSeg = scopeFilter?.tenantSegment
    ? safeText(scopeFilter.tenantSegment, 128)
    : "";
  const companySeg = scopeFilter?.companySegment
    ? safeText(scopeFilter.companySegment, 128)
    : "";
  const duePool = [];
  const duplicates = [];
  const stale = [];
  const skip = [];
  let inspected = 0;
  let stoppedAtFuture = false;
  let sawDoneSentinel = false;
  const seenRef = new Set();

  for (const entry of rows) {
    const name = safeText(entry?.name, 512);
    if (isChironReconcileDueDoneSentinel(name)) {
      sawDoneSentinel = true;
      continue;
    }
    const parsed = parseChironDueMarkerKey(name);
    if (!parsed.ok) {
      skip.push({ markerKey: name, reason: parsed.error });
      continue;
    }
    if (!Number.isFinite(now) || parsed.dueAtMs > now) {
      stoppedAtFuture = true;
      break;
    }
    inspected += 1;
    if (seenRef.has(parsed.ref)) {
      duplicates.push({ markerKey: parsed.markerKey, ref: parsed.ref, dueAtMs: parsed.dueAtMs });
      continue;
    }
    const meta =
      entry?.metadata && typeof entry.metadata === "object" ? entry.metadata : null;
    const eventKey = safeText(meta?.ek, 1024);
    if (tenantSeg && companySeg) {
      if (!eventKey || !eventKeyMatchesScope(eventKey, tenantSeg, companySeg)) {
        skip.push({ markerKey: parsed.markerKey, reason: "scope_mismatch_or_missing_meta" });
        continue;
      }
    }
    seenRef.add(parsed.ref);
    duePool.push({
      markerKey: parsed.markerKey,
      dueAtMs: parsed.dueAtMs,
      ref: parsed.ref,
      eventKey,
      entry,
      recencyMs: chironDueMarkerEventRecencyMs(eventKey),
    });
  }

  duePool.sort((a, b) => {
    if (b.recencyMs !== a.recencyMs) return b.recencyMs - a.recencyMs;
    if (a.dueAtMs !== b.dueAtMs) return a.dueAtMs - b.dueAtMs;
    return a.ref < b.ref ? -1 : a.ref > b.ref ? 1 : 0;
  });
  const stoppedAtLimit = duePool.length > cap;
  const selected = duePool.slice(0, cap).map(({ recencyMs: _recency, ...row }) => row);

  return {
    selected,
    duplicates,
    stale,
    skip,
    inspected,
    stoppedAtFuture,
    stoppedAtLimit,
    sawDoneSentinel,
  };
}

export function buildInitialChironDueMigrationState({ now = new Date() } = {}) {
  const nowIso = (now instanceof Date ? now : new Date(now)).toISOString();
  return {
    version: CHIRON_RECONCILE_DUE_MIGRATION_VERSION,
    completed: false,
    cursor: null,
    scanned: 0,
    marked: 0,
    batches: 0,
    started_at: nowIso,
    updated_at: nowIso,
    completed_at: null,
  };
}

export function normalizeChironDueMigrationState(raw, { now = new Date() } = {}) {
  const src = raw && typeof raw === "object" && !Array.isArray(raw) ? raw : null;
  if (!src) return buildInitialChironDueMigrationState({ now });
  if (Number(src.version) !== CHIRON_RECONCILE_DUE_MIGRATION_VERSION) {
    return buildInitialChironDueMigrationState({ now });
  }
  const nowIso = (now instanceof Date ? now : new Date(now)).toISOString();
  const completed = src.completed === true;
  return {
    version: CHIRON_RECONCILE_DUE_MIGRATION_VERSION,
    completed,
    cursor: completed ? null : safeText(src.cursor, 1024) || null,
    scanned: Math.max(0, Math.floor(Number(src.scanned) || 0)),
    marked: Math.max(0, Math.floor(markedSafe(src.marked))),
    batches: Math.max(0, Math.floor(Number(src.batches) || 0)),
    started_at: safeText(src.started_at, 40) || nowIso,
    updated_at: safeText(src.updated_at, 40) || nowIso,
    completed_at: safeText(src.completed_at, 40) || null,
  };
}

function markedSafe(value) {
  const n = Number(value);
  return Number.isFinite(n) ? n : 0;
}

export function chironDueMigrationIsComplete(state) {
  return normalizeChironDueMigrationState(state).completed === true;
}

export function advanceChironDueMigrationState(
  previous,
  { cursor = null, listComplete = false, scanned = 0, marked = 0, now = new Date() } = {},
) {
  const prev = normalizeChironDueMigrationState(previous, { now });
  const nowIso = (now instanceof Date ? now : new Date(now)).toISOString();
  if (prev.completed) return prev;
  const done = listComplete === true;
  return {
    ...prev,
    completed: done,
    cursor: done ? null : safeText(cursor, 1024) || null,
    scanned: prev.scanned + Math.max(0, Math.floor(Number(scanned) || 0)),
    marked: prev.marked + Math.max(0, Math.floor(Number(marked) || 0)),
    batches: prev.batches + 1,
    updated_at: nowIso,
    completed_at: done ? nowIso : null,
  };
}

export async function armChironDueMarker(kv, eventKey, dueAtMs) {
  if (!kv || typeof kv.put !== "function") return null;
  const markerKey = await buildChironDueMarkerKey(dueAtMs, eventKey);
  const metadata = buildChironDueMarkerMetadata(eventKey);
  if (!markerKey || !metadata) return null;
  await kv.put(markerKey, JSON.stringify({ v: CHIRON_RECONCILE_DUE_INDEX_VERSION }), {
    metadata,
  });
  return markerKey;
}

export async function retireChironDueMarker(kv, markerKey) {
  if (!kv || typeof kv.delete !== "function") return false;
  const key = safeText(markerKey, 512);
  if (!key || isChironReconcileDueDoneSentinel(key)) return false;
  try {
    await kv.delete(key);
    return true;
  } catch (_) {
    return false;
  }
}

/**
 * Crash-ordered marker transition around an authoritative persist.
 *
 * Non-terminal (next due exists): arm ÔåÆ persist ÔåÆ retire superseded.
 * Terminal (no next due): persist ÔåÆ retire outstanding.
 */
export async function applyChironDueMarkerTransition(kv, {
  eventKey,
  previousDueAtMs = null,
  nextDueAtMs = null,
  selectedMarkerKey = null,
  persist,
  crashAfter = null,
} = {}) {
  const nextKey =
    nextDueAtMs == null ? null : await buildChironDueMarkerKey(nextDueAtMs, eventKey);
  let prevKey =
    previousDueAtMs == null ? null : await buildChironDueMarkerKey(previousDueAtMs, eventKey);

  // A terminal cron item may carry a legacy due time that cannot be recovered
  // from its current status. Retire that exact item, never a guessed sibling.
  // Validate its event hash before persist or any other mutation. This override
  // is intentionally terminal-only; ordinary retry transitions are unchanged.
  if (selectedMarkerKey !== null) {
    const selected = parseChironDueMarkerKey(selectedMarkerKey);
    if (
      nextDueAtMs !== null ||
      typeof persist !== "function" ||
      !selected.ok ||
      selectedMarkerKey !== await buildChironDueMarkerKey(selected.dueAtMs, eventKey)
    ) {
      throw new Error("selected_terminal_marker_binding_mismatch");
    }
    prevKey = selectedMarkerKey;
  }

  if (nextKey) {
    await armChironDueMarker(kv, eventKey, nextDueAtMs);
    if (crashAfter === "after_arm") throw new ChironDueIndexTestCrash("after_arm");
  }
  if (typeof persist === "function") {
    await persist();
    if (crashAfter === "after_persist") throw new ChironDueIndexTestCrash("after_persist");
  }
  if (prevKey && prevKey !== nextKey) {
    if (crashAfter === "before_retire") throw new ChironDueIndexTestCrash("before_retire");
    const retired = await retireChironDueMarker(kv, prevKey);
    if (selectedMarkerKey !== null && !retired) {
      throw new Error("selected_terminal_marker_retirement_failed");
    }
  }
  return { nextKey, prevKey };
}

export async function markChironDueMigrationComplete(kv, { now = new Date() } = {}) {
  if (!kv || typeof kv.put !== "function") return false;
  await kv.put(CHIRON_RECONCILE_DUE_DONE_KEY, JSON.stringify({ v: 1 }), {
    metadata: { v: 1, done: true },
  });
  const nowIso = (now instanceof Date ? now : new Date(now)).toISOString();
  const completed = {
    version: CHIRON_RECONCILE_DUE_MIGRATION_VERSION,
    completed: true,
    cursor: null,
    scanned: 0,
    marked: 0,
    batches: 0,
    started_at: nowIso,
    updated_at: nowIso,
    completed_at: nowIso,
  };
  await kv.put(CHIRON_RECONCILE_DUE_MIGRATION_KEY, JSON.stringify(completed));
  return true;
}

/**
 * Due-index log line. Counts and opaque refs only ÔÇö never tenant, company,
 * booking, ride, document, payload or credential material.
 */
export function formatChironDueIndexLog({
  source = "cron",
  dueListed = 0,
  dueSelected = 0,
  eventReads = 0,
  providerCalls = 0,
  writes = 0,
  deletedMarkers = 0,
  migrationExamined = 0,
  migrationDone = false,
} = {}) {
  return [
    "[CHIRON_DUE_INDEX]",
    `src=${safeText(source, 32) || "cron"}`,
    `due_listed=${Number(dueListed) || 0}`,
    `due_selected=${Number(dueSelected) || 0}`,
    `event_reads=${Number(eventReads) || 0}`,
    `provider=${Number(providerCalls) || 0}`,
    `writes=${Number(writes) || 0}`,
    `retired=${Number(deletedMarkers) || 0}`,
    `mig_exam=${Number(migrationExamined) || 0}`,
    `mig_done=${migrationDone === true ? "1" : "0"}`,
  ].join(" ");
}

export function chironDueIndexLogContainsForbiddenIdentity(line) {
  const text = safeText(line, 4000);
  return (
    /tenant[_/:]|company[_/:]|booking[_-]?id|ride[_-]?id|ritnummer|registratie|passenger|driver_id|kenteken|iban|access_token|client_secret/i.test(
      text,
    ) || /compliance_event_v1\//.test(text)
  );
}
