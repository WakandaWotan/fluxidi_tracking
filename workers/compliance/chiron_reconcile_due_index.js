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
export const CHIRON_WAITING_RECHECK_MS = 5 * 60 * 1000;
export const CHIRON_BLOCKED_RECHECK_MS = 5 * 60 * 1000;

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
export function computeChironReconcileDueAtMs(statusDoc, nowMs, options = {}) {
  const now = Number(nowMs);
  if (!Number.isFinite(now)) return null;
  const pendingStaleMs = Number(options.pendingStaleMs) || 60 * 1000;
  const definitiveCooldownMs = Number(options.definitiveCooldownMs) || 10 * 60 * 1000;
  const definitiveMaxAttempts = Number(options.definitiveMaxAttempts) || 6;
  const waitingRecheckMs = Number(options.waitingRecheckMs) || CHIRON_WAITING_RECHECK_MS;
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
  if (state === "pending_build") return 0;
  if (state === "waiting_for_departure") {
    const last = parseIsoMs(statusDoc.last_attempt_at);
    const base = last !== null ? last : now;
    return base + waitingRecheckMs;
  }
  if (state === "retryable_failed" || state === "queued") return 0;
  if (state === "failed") {
    if (statusDoc.failure_kind === "definitive") {
      const last = parseIsoMs(statusDoc.last_attempt_at);
      const perPayload = Number(statusDoc.outbound_fingerprint_definitive_attempts);
      const attempts = Number.isFinite(perPayload)
        ? perPayload
        : Number(statusDoc.attempt_count);
      if (Number.isFinite(attempts) && attempts >= definitiveMaxAttempts) {
        return null;
      }
      if (last !== null && now - last < definitiveCooldownMs) {
        return last + definitiveCooldownMs;
      }
      return 0;
    }
    const httpStatus = Number(statusDoc.external_status_code);
    const foutenCount = Number(statusDoc.fouten_count);
    const gotChironResponse =
      Number.isFinite(httpStatus) &&
      httpStatus > 0 &&
      (httpStatus < 200 ||
        httpStatus >= 300 ||
        (Number.isFinite(foutenCount) && foutenCount > 0));
    return gotChironResponse ? 0 : null;
  }
  if (state === "blocked") {
    const last = parseIsoMs(statusDoc.last_attempt_at);
    const base = last !== null ? last : now;
    return base + blockedRecheckMs;
  }
  return null;
}

/**
 * Choose due markers from a lexicographic `list()` page. Stops at the first
 * future timestamp so a quiet pass never value-reads an event.
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
  const selected = [];
  const duplicates = [];
  const stale = [];
  const skip = [];
  let inspected = 0;
  let stoppedAtFuture = false;
  let stoppedAtLimit = false;
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
    if (selected.length >= cap) {
      stoppedAtLimit = true;
      break;
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
    selected.push({
      markerKey: parsed.markerKey,
      dueAtMs: parsed.dueAtMs,
      ref: parsed.ref,
      eventKey,
      entry,
    });
  }

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
 * Non-terminal (next due exists): arm → persist → retire superseded.
 * Terminal (no next due): persist → retire outstanding.
 */
export async function applyChironDueMarkerTransition(kv, {
  eventKey,
  previousDueAtMs = null,
  nextDueAtMs = null,
  persist,
  crashAfter = null,
} = {}) {
  const nextKey =
    nextDueAtMs == null ? null : await buildChironDueMarkerKey(nextDueAtMs, eventKey);
  const prevKey =
    previousDueAtMs == null ? null : await buildChironDueMarkerKey(previousDueAtMs, eventKey);

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
    await retireChironDueMarker(kv, prevKey);
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
 * Due-index log line. Counts and opaque refs only — never tenant, company,
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
