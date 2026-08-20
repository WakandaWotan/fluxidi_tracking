// BILLIT-KV-COST-P0
//
// Pure key/state helpers for the bounded Billit export "due-work index".
//
// Why this exists
// ---------------
// The original `*/2` cron sweep listed the first page of
// `billit_create_outbox:*` (up to 1,000 keys) and then value-GET every key just
// to discover whether it was due. The retry cap bounded Billit calls but not KV
// value reads, so an idle account still burned ~3,450 BOOKING_KV reads per
// scheduled run.
//
// The fix is an ordered marker keyspace inside the SAME namespace:
//
//   billit_outbox_due:v1:<16-digit due-at ms>:<16-hex outbox ref>
//
// * Keys sort lexicographically by due time because the timestamp is a
//   fixed-width zero-padded decimal, so `list()` returns the earliest-due work
//   first and the scan can stop at the first future marker.
// * The marker value is empty. Identity lives in KV metadata, which `list()`
//   already returns, so resolving a marker to its authoritative outbox record
//   costs no value read.
// * The `billit_create_outbox:*` record stays the only authority for state,
//   attempt_count and backoff. Markers are a disposable, self-healing hint:
//   a stale, duplicate or orphaned marker can never create a second Billit
//   export because processing always re-reads the authoritative record.
//
// Nothing here touches KV, Billit, Mollie or Peppol, and nothing mutates its
// inputs.

import {
  BILLIT_EXPORT_STATES,
  IN_PROGRESS_STALL_MS,
} from "./billit_export_recovery.js";

function safeStr(value, maxLen = 200) {
  if (value === undefined || value === null) return "";
  const s = String(value);
  return s.length > maxLen ? s.slice(0, maxLen) : s;
}

function parseIsoMs(iso) {
  const s = safeStr(iso, 40);
  if (!s) return null;
  const n = Date.parse(s);
  return Number.isFinite(n) ? n : null;
}

export const BILLIT_OUTBOX_PREFIX = "billit_create_outbox:";

export const BILLIT_OUTBOX_DUE_INDEX_VERSION = 1;
export const BILLIT_OUTBOX_DUE_PREFIX = "billit_outbox_due:v1:";

/** Fixed-width due-at encoding so lexicographic order == chronological order. */
export const BILLIT_DUE_AT_DIGITS = 16;
const MAX_DUE_AT_MS = 10 ** BILLIT_DUE_AT_DIGITS - 1;

export const BILLIT_OUTBOX_DUE_MIGRATION_KEY = "billit_outbox_due_migration:v1";
export const BILLIT_OUTBOX_DUE_MIGRATION_VERSION = 1;
/** Hard cap on legacy outbox value reads per scheduled invocation. */
export const BILLIT_OUTBOX_DUE_MIGRATION_BATCH = 25;

function fnv1a32(input, seed) {
  let h = seed >>> 0;
  for (let i = 0; i < input.length; i += 1) {
    const code = input.charCodeAt(i);
    h = (h ^ (code & 0xff)) >>> 0;
    h = Math.imul(h, 0x01000193) >>> 0;
    h = (h ^ ((code >>> 8) & 0xff)) >>> 0;
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h >>> 0;
}

/**
 * Deterministic, non-reversible 64-bit reference for an authoritative outbox
 * key. Marker key names therefore carry no tenant, company, document or
 * financial identifier — those live only in KV metadata.
 */
export function billitOutboxRefFromKey(outboxKey) {
  const key = safeStr(outboxKey, 512);
  if (!key) return "";
  const a = fnv1a32(key, 0x811c9dc5);
  const b = fnv1a32(key, 0x9dc5811c);
  return `${a.toString(16).padStart(8, "0")}${b.toString(16).padStart(8, "0")}`;
}

export function encodeBillitDueAt(dueAtMs) {
  const n = Number(dueAtMs);
  if (!Number.isFinite(n)) return null;
  const clamped = Math.min(MAX_DUE_AT_MS, Math.max(0, Math.floor(n)));
  return String(clamped).padStart(BILLIT_DUE_AT_DIGITS, "0");
}

export function buildBillitOutboxDueMarkerKey(dueAtMs, outboxKey) {
  const encoded = encodeBillitDueAt(dueAtMs);
  const ref = billitOutboxRefFromKey(outboxKey);
  if (encoded === null || !ref) return null;
  return `${BILLIT_OUTBOX_DUE_PREFIX}${encoded}:${ref}`;
}

export function parseBillitOutboxDueMarkerKey(name) {
  const key = safeStr(name, 512);
  if (!key.startsWith(BILLIT_OUTBOX_DUE_PREFIX)) {
    return { ok: false, error: "not_a_due_marker" };
  }
  const rest = key.slice(BILLIT_OUTBOX_DUE_PREFIX.length);
  const sep = rest.indexOf(":");
  if (sep !== BILLIT_DUE_AT_DIGITS) return { ok: false, error: "malformed_due_marker" };
  const digits = rest.slice(0, sep);
  const ref = rest.slice(sep + 1);
  if (!/^[0-9]{16}$/.test(digits)) return { ok: false, error: "malformed_due_at" };
  if (!/^[0-9a-f]{16}$/.test(ref)) return { ok: false, error: "malformed_ref" };
  return { ok: true, dueAtMs: Number(digits), ref, markerKey: key };
}

/**
 * Marker metadata: the minimum needed to rebuild the authoritative outbox key.
 * Deliberately excludes booking id, document number, amounts and error codes —
 * the authoritative record is read for anything beyond identity.
 */
export function buildBillitOutboxDueMarkerMetadata(record) {
  const src = record && typeof record === "object" && !Array.isArray(record) ? record : null;
  if (!src) return null;
  const t = safeStr(src.tenant_id ?? src.tenantId, 96);
  const c = safeStr(src.company_id ?? src.companyId, 96);
  const d = safeStr(src.document_id ?? src.documentId, 200);
  if (!t || !c || !d) return null;
  return { v: BILLIT_OUTBOX_DUE_INDEX_VERSION, t, c, d };
}

export function buildBillitOutboxKeyFromParts(tenantId, companyId, documentId) {
  const t = safeStr(tenantId, 96);
  const c = safeStr(companyId, 96);
  const d = safeStr(documentId, 200);
  if (!t || !c || !d) return null;
  return `${BILLIT_OUTBOX_PREFIX}${t}:${c}:${d}`;
}

/**
 * Resolve one `list()` entry into the authoritative outbox key it points at.
 * Requires the key-name ref to match the metadata identity so a hand-written or
 * corrupted marker can never redirect processing at an unrelated record.
 */
export function readBillitOutboxDueMarkerIdentity(entry) {
  const src = entry && typeof entry === "object" ? entry : null;
  if (!src) return { ok: false, error: "missing_entry" };
  const parsed = parseBillitOutboxDueMarkerKey(src.name);
  if (!parsed.ok) return { ok: false, error: parsed.error, markerKey: safeStr(src.name, 512) };
  const meta = src.metadata && typeof src.metadata === "object" ? src.metadata : null;
  if (!meta) {
    return { ok: false, error: "missing_marker_metadata", markerKey: parsed.markerKey };
  }
  const outboxKey = buildBillitOutboxKeyFromParts(meta.t, meta.c, meta.d);
  if (!outboxKey) {
    return { ok: false, error: "incomplete_marker_metadata", markerKey: parsed.markerKey };
  }
  if (billitOutboxRefFromKey(outboxKey) !== parsed.ref) {
    return { ok: false, error: "marker_ref_mismatch", markerKey: parsed.markerKey };
  }
  return {
    ok: true,
    markerKey: parsed.markerKey,
    dueAtMs: parsed.dueAtMs,
    outboxKey,
    tenantId: safeStr(meta.t, 96),
    companyId: safeStr(meta.c, 96),
    documentId: safeStr(meta.d, 200),
  };
}

/**
 * Server-owned due time for an authoritative outbox record.
 *
 * Returns `null` when the record must carry no active marker (synced /
 * permanent_error). Returns `0` for legacy records with no usable timestamp so
 * they are treated as immediately due — the bias is always toward processing,
 * never toward silently dropping recovery work.
 *
 * Invariant asserted by tests: `isBillitOutboxDue(record, { now })` is true
 * exactly when this returns a number `<= now`.
 */
export function billitOutboxDueAtMs(record) {
  const src = record && typeof record === "object" && !Array.isArray(record) ? record : null;
  if (!src) return null;
  const state = safeStr(src.state, 40);
  if (
    state === BILLIT_EXPORT_STATES.SYNCED ||
    state === BILLIT_EXPORT_STATES.PERMANENT_ERROR
  ) {
    return null;
  }
  if (state === BILLIT_EXPORT_STATES.IN_PROGRESS) {
    const startedAt = parseIsoMs(
      src.in_progress_since || src.updated_at || src.created_at,
    );
    if (startedAt === null) return 0;
    return startedAt + IN_PROGRESS_STALL_MS;
  }
  const dueAt = parseIsoMs(src.next_attempt_at);
  if (dueAt === null) return 0;
  return dueAt;
}

/** The marker key an authoritative record should currently own (or null). */
export function desiredBillitDueMarkerKey(outboxKey, record) {
  const dueAtMs = billitOutboxDueAtMs(record);
  if (dueAtMs === null) return null;
  return buildBillitOutboxDueMarkerKey(dueAtMs, outboxKey);
}

/**
 * Choose which due markers one scheduled pass may act on.
 *
 * `entries` must be the raw `list()` output in ascending key order. Because
 * marker keys embed a fixed-width due timestamp, the first entry whose due time
 * is in the future proves every remaining entry is also in the future, so the
 * scan stops there having read zero values.
 */
export function selectDueBillitMarkers(entries, { nowMs = Date.now(), limit = 20 } = {}) {
  const rows = Array.isArray(entries) ? entries : [];
  const cap = Math.max(1, Math.floor(Number(limit) || 1));
  const now = Number(nowMs);
  const selected = [];
  const duplicates = [];
  const orphans = [];
  const seen = new Set();
  let inspected = 0;
  let stoppedAtFuture = false;
  let stoppedAtLimit = false;

  for (const entry of rows) {
    const parsed = parseBillitOutboxDueMarkerKey(entry?.name);
    if (!parsed.ok) {
      orphans.push({ markerKey: safeStr(entry?.name, 512), reason: parsed.error });
      continue;
    }
    if (parsed.dueAtMs > now) {
      stoppedAtFuture = true;
      break;
    }
    inspected += 1;
    const identity = readBillitOutboxDueMarkerIdentity(entry);
    if (!identity.ok) {
      orphans.push({ markerKey: identity.markerKey, reason: identity.error });
      continue;
    }
    if (seen.has(identity.outboxKey)) {
      duplicates.push(identity);
      continue;
    }
    if (selected.length >= cap) {
      stoppedAtLimit = true;
      break;
    }
    seen.add(identity.outboxKey);
    selected.push(identity);
  }

  return { selected, duplicates, orphans, inspected, stoppedAtFuture, stoppedAtLimit };
}

/* ===================== legacy migration state ===================== */

export function buildInitialBillitOutboxMigrationState({ now = new Date() } = {}) {
  const nowIso = (now instanceof Date ? now : new Date(now)).toISOString();
  return {
    version: BILLIT_OUTBOX_DUE_MIGRATION_VERSION,
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

/**
 * Read stored migration state defensively. An unknown/corrupt version restarts
 * the pass from the beginning, which is safe: every step is bounded to
 * `BILLIT_OUTBOX_DUE_MIGRATION_BATCH` value reads and marker writes are
 * deterministic, so a replay re-derives identical markers.
 */
export function normalizeBillitOutboxMigrationState(raw, { now = new Date() } = {}) {
  const src = raw && typeof raw === "object" && !Array.isArray(raw) ? raw : null;
  if (!src) return buildInitialBillitOutboxMigrationState({ now });
  if (Number(src.version) !== BILLIT_OUTBOX_DUE_MIGRATION_VERSION) {
    return buildInitialBillitOutboxMigrationState({ now });
  }
  const nowIso = (now instanceof Date ? now : new Date(now)).toISOString();
  const completed = src.completed === true;
  return {
    version: BILLIT_OUTBOX_DUE_MIGRATION_VERSION,
    completed,
    // A completed pass never resumes, so its cursor is intentionally dropped.
    cursor: completed ? null : safeStr(src.cursor, 1024) || null,
    scanned: Math.max(0, Math.floor(Number(src.scanned) || 0)),
    marked: Math.max(0, Math.floor(Number(src.marked) || 0)),
    batches: Math.max(0, Math.floor(Number(src.batches) || 0)),
    started_at: safeStr(src.started_at, 40) || nowIso,
    updated_at: safeStr(src.updated_at, 40) || nowIso,
    completed_at: safeStr(src.completed_at, 40) || null,
  };
}

export function billitOutboxMigrationIsComplete(state) {
  return normalizeBillitOutboxMigrationState(state).completed === true;
}

/**
 * Advance migration state after one bounded batch. The cursor only moves
 * forward and completion is terminal, so no legacy record is examined twice
 * across the pass and a finished migration never re-scans outbox values.
 */
export function advanceBillitOutboxMigrationState(previous, {
  cursor = null,
  listComplete = false,
  scanned = 0,
  marked = 0,
  now = new Date(),
} = {}) {
  const prev = normalizeBillitOutboxMigrationState(previous, { now });
  const nowIso = (now instanceof Date ? now : new Date(now)).toISOString();
  if (prev.completed) return prev;
  const done = listComplete === true;
  const nextCursor = done ? null : safeStr(cursor, 1024) || null;
  return {
    ...prev,
    completed: done,
    cursor: nextCursor,
    scanned: prev.scanned + Math.max(0, Math.floor(Number(scanned) || 0)),
    marked: prev.marked + Math.max(0, Math.floor(Number(marked) || 0)),
    batches: prev.batches + 1,
    updated_at: nowIso,
    completed_at: done ? nowIso : null,
  };
}
