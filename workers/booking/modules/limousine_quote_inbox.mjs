// LIMOUSINE-MARKETPLACE-P2C2A — company-scoped inbox index, pagination,
// privacy projection and customer status-read orchestration.
//
// Index strategy
// --------------
// Quote records stay at `limousine_quote_record:{id}`. That key cannot be
// listed by company without scanning the whole BOOKING_KV namespace, so this
// module owns a single derived document:
//
//   limousine_quote_inbox_v1:{tenant_id}:{company_id}
//
//   {
//     v: 1,
//     tenant_id, company_id,
//     next_activity_seq,
//     entries: [{ quote_request_id, activity_seq, updated_at, revision, state }]
//   }
//
// Semantics
//   * company-scoped — one company never sees another company's keys;
//   * monotonic activity_seq — newest activity first, id DESC as tie-break;
//   * idempotent upsert — same quote_request_id + revision writes nothing;
//   * stale revision cannot overwrite a newer indexed revision;
//   * tombstone/history preserving — entries are never deleted (oldest drop
//     only when the bounded cap is exceeded);
//   * no customer-private fields (no note, email, phone, status token);
//   * no KV list() — list is an O(1) get of this document, then O(page)
//     record hydrations.
//
// Consistency: last-write-wins on the index document. The quote record is
// authoritative; a missed index write is healed on the next save or on an
// idempotent create replay.

import { sha256Hex } from "./crypto_utils.js";
import {
  LIMOUSINE_QUOTE_STATES,
  appendLimousineQuoteAudit,
  buildLimousineCustomerFingerprint,
  isLimousineQuoteState,
  observeLimousineQuoteExpiry,
  publicLimousineQuoteView,
} from "./limousine_manual_quote.mjs";
import {
  limousineStatusBindingMatches,
  limousineStatusRefLooksWellFormed,
  unsealLimousineStatusRef,
} from "./limousine_status_token.mjs";

export const LIMOUSINE_INBOX_INDEX_VERSION = 1;
export const LIMOUSINE_INBOX_MAX_ENTRIES = 200;
export const LIMOUSINE_INBOX_PAGE_DEFAULT = 20;
export const LIMOUSINE_INBOX_PAGE_MAX = 25;
export const LIMOUSINE_STATUS_RATE_MAX = 80;
export const LIMOUSINE_STATUS_RATE_WINDOW_SECONDS = 15 * 60;

export const LIMOUSINE_INBOX_FORBIDDEN_KEYS = Object.freeze([
  "authorization",
  "headers",
  "cookie",
  "card",
  "cvc",
  "pan",
  "api_key",
  "secret",
  "token",
  "acceptance_reference",
  "status_ref",
  "status_access",
  "customer_fingerprint",
  "email",
  "phone",
  "customer_name",
  "customer_reference",
  "operating_base_address",
  "internal_cost",
  "margin",
  "provider_payload",
  "audit",
  "itinerary_fingerprint",
]);

function asObject(raw) {
  return raw && typeof raw === "object" && !Array.isArray(raw) ? raw : {};
}

function toInt(value) {
  const n = Number(value);
  return Number.isFinite(n) ? Math.trunc(n) : null;
}

function safeText(value, max) {
  return String(value ?? "").trim().slice(0, max);
}

const LIMOUSINE_GLOBAL_CUSTOMER_SCOPE = "global";

/// Fluxidi phone/customer identity is intentionally cross-tenant:
/// `tenant_id = global` and `company_id = global`. That session must not be
/// treated as a partner-scoped company login.
export function isLimousineGlobalCustomerSession(session) {
  const src = asObject(session);
  return (
    safeText(src.tenant_id, 96).toLowerCase() === LIMOUSINE_GLOBAL_CUSTOMER_SCOPE &&
    safeText(src.company_id, 96).toLowerCase() === LIMOUSINE_GLOBAL_CUSTOMER_SCOPE
  );
}

function sanitizeScopePart(value) {
  return safeText(value, 96).toLowerCase().replace(/[^a-z0-9._:-]+/g, "");
}

export function limousineInboxIndexKey(tenantId, companyId) {
  const tenant = sanitizeScopePart(tenantId);
  const company = sanitizeScopePart(companyId);
  if (!tenant || !company) return "";
  return `limousine_quote_inbox_v1:${tenant}:${company}`;
}

/// One-way digest of the complete token. The token itself is never stored
/// as the rate-limit key.
export async function limousineStatusRateKey(statusRef) {
  const ref = safeText(statusRef, 800);
  if (!ref) return "";
  const digest = await sha256Hex(ref);
  return `limousine_status_rl:v1:${digest.slice(0, 32)}`;
}

export function emptyLimousineInboxIndex(tenantId, companyId) {
  return {
    v: LIMOUSINE_INBOX_INDEX_VERSION,
    tenant_id: safeText(tenantId, 96),
    company_id: safeText(companyId, 96),
    next_activity_seq: 1,
    entries: [],
  };
}

export function normalizeLimousineInboxIndex(raw, tenantId, companyId) {
  const src = asObject(raw);
  const tenant = safeText(tenantId || src.tenant_id, 96);
  const company = safeText(companyId || src.company_id, 96);
  if (src.v !== LIMOUSINE_INBOX_INDEX_VERSION) {
    return emptyLimousineInboxIndex(tenant, company);
  }
  if (safeText(src.tenant_id, 96) !== tenant || safeText(src.company_id, 96) !== company) {
    return emptyLimousineInboxIndex(tenant, company);
  }
  const entries = Array.isArray(src.entries)
    ? src.entries
        .map((e) => {
          const row = asObject(e);
          const id = safeText(row.quote_request_id, 120);
          const seq = toInt(row.activity_seq);
          if (!id || seq == null || seq < 1) return null;
          return {
            quote_request_id: id,
            activity_seq: seq,
            updated_at: safeText(row.updated_at, 40),
            revision: toInt(row.revision) ?? 0,
            state: safeText(row.state, 40),
          };
        })
        .filter(Boolean)
        .slice(0, LIMOUSINE_INBOX_MAX_ENTRIES)
    : [];
  const next = toInt(src.next_activity_seq);
  return {
    v: LIMOUSINE_INBOX_INDEX_VERSION,
    tenant_id: tenant,
    company_id: company,
    next_activity_seq: next && next > 0 ? next : 1,
    entries,
  };
}

function compareInboxEntries(a, b) {
  const seq = (toInt(b.activity_seq) ?? 0) - (toInt(a.activity_seq) ?? 0);
  if (seq !== 0) return seq;
  return String(b.quote_request_id || "").localeCompare(String(a.quote_request_id || ""));
}

function isStrictlyOlderThanCursor(entry, cursor) {
  const seq = toInt(entry.activity_seq) ?? 0;
  const cursorSeq = toInt(cursor.activity_seq) ?? 0;
  if (seq !== cursorSeq) return seq < cursorSeq;
  return String(entry.quote_request_id || "") < String(cursor.quote_request_id || "");
}

export function encodeLimousineInboxCursor({ activity_seq, quote_request_id } = {}) {
  const seq = toInt(activity_seq);
  const id = safeText(quote_request_id, 120);
  if (seq == null || seq < 1 || !id) return "";
  const json = JSON.stringify({ v: 1, s: seq, i: id });
  return btoa(json).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function decodeLimousineInboxCursor(raw) {
  const text = String(raw ?? "").trim();
  if (!text || text.length > 400) return { ok: false, reason: "invalid_cursor" };
  try {
    const normalized = text.replace(/-/g, "+").replace(/_/g, "/");
    const padded = normalized + "=".repeat((4 - (normalized.length % 4)) % 4);
    const payload = JSON.parse(atob(padded));
    const seq = toInt(payload?.s ?? payload?.activity_seq);
    const id = safeText(payload?.i ?? payload?.quote_request_id, 120);
    if (payload?.v !== 1 || seq == null || seq < 1 || !id) {
      return { ok: false, reason: "invalid_cursor" };
    }
    return { ok: true, cursor: { activity_seq: seq, quote_request_id: id } };
  } catch (_) {
    return { ok: false, reason: "invalid_cursor" };
  }
}

/// Unknown / unbounded filters fail closed. page_size is required to be a
/// positive integer at most LIMOUSINE_INBOX_PAGE_MAX when provided.
export function parseLimousineInboxQuery(params) {
  const read = (key) => {
    if (!params) return "";
    if (typeof params.get === "function") return params.get(key);
    return params[key];
  };
  const rawSize = read("page_size") ?? read("pageSize");
  let pageSize = LIMOUSINE_INBOX_PAGE_DEFAULT;
  if (rawSize != null && String(rawSize).trim() !== "") {
    const n = Number(rawSize);
    if (!Number.isInteger(n) || n < 1 || n > LIMOUSINE_INBOX_PAGE_MAX) {
      return { ok: false, reason: "invalid_page_size" };
    }
    pageSize = n;
  }

  const rawState = read("state");
  let state = "";
  if (rawState != null && String(rawState).trim() !== "") {
    state = String(rawState).trim().toLowerCase();
    if (!isLimousineQuoteState(state)) {
      return { ok: false, reason: "invalid_state_filter" };
    }
  }

  const rawSince = read("updated_since") ?? read("updatedSince");
  let updatedSinceMs = null;
  if (rawSince != null && String(rawSince).trim() !== "") {
    const text = String(rawSince).trim();
    if (text.length > 40) return { ok: false, reason: "invalid_updated_since" };
    const ms = Date.parse(text);
    if (!Number.isFinite(ms)) return { ok: false, reason: "invalid_updated_since" };
    updatedSinceMs = ms;
  }

  const rawCursor = read("cursor");
  let cursor = null;
  if (rawCursor != null && String(rawCursor).trim() !== "") {
    const decoded = decodeLimousineInboxCursor(rawCursor);
    if (!decoded.ok) return { ok: false, reason: "invalid_cursor" };
    cursor = decoded.cursor;
  }

  return { ok: true, pageSize, state, updatedSinceMs, cursor };
}

/// Idempotent company-inbox upsert. Same revision is a no-op. A lower
/// revision cannot overwrite a newer indexed row.
export function upsertLimousineInboxEntry(index, patch) {
  const tenant = safeText(patch?.tenant_id || index?.tenant_id, 96);
  const company = safeText(patch?.company_id || index?.company_id, 96);
  const idx = normalizeLimousineInboxIndex(index, tenant, company);
  const id = safeText(patch?.quote_request_id, 120);
  if (!id) return { changed: false, reason: "missing_id", index: idx };
  const revision = toInt(patch?.revision) ?? 0;
  const state = safeText(patch?.state, 40);
  const updatedAt = safeText(patch?.updated_at, 40);
  const existing = idx.entries.find((e) => e.quote_request_id === id) || null;
  if (existing) {
    const existingRev = toInt(existing.revision) ?? 0;
    if (revision < existingRev) {
      return { changed: false, reason: "stale_revision", index: idx };
    }
    if (revision === existingRev) {
      return { changed: false, reason: "idempotent", index: idx };
    }
  }
  const activitySeq = idx.next_activity_seq;
  const entry = {
    quote_request_id: id,
    activity_seq: activitySeq,
    updated_at: updatedAt,
    revision,
    state,
  };
  const entries = idx.entries.filter((e) => e.quote_request_id !== id);
  entries.push(entry);
  entries.sort(compareInboxEntries);
  return {
    changed: true,
    entry,
    index: {
      ...idx,
      next_activity_seq: activitySeq + 1,
      entries: entries.slice(0, LIMOUSINE_INBOX_MAX_ENTRIES),
    },
  };
}

export function pageLimousineInboxEntries(index, query = {}) {
  const pageSize = toInt(query.pageSize) || LIMOUSINE_INBOX_PAGE_DEFAULT;
  const bounded = Math.min(Math.max(pageSize, 1), LIMOUSINE_INBOX_PAGE_MAX);
  let items = [...(asObject(index).entries || [])].sort(compareInboxEntries);
  if (query.state) {
    items = items.filter((e) => e.state === query.state);
  }
  if (query.updatedSinceMs != null) {
    const since = Number(query.updatedSinceMs);
    items = items.filter((e) => {
      const ms = Date.parse(e.updated_at);
      return Number.isFinite(ms) && ms >= since;
    });
  }
  if (query.cursor) {
    items = items.filter((e) => isStrictlyOlderThanCursor(e, query.cursor));
  }
  const page = items.slice(0, bounded);
  const hasMore = items.length > bounded;
  const last = page[page.length - 1];
  return {
    entries: page,
    has_more: hasMore,
    next_cursor: hasMore && last
      ? encodeLimousineInboxCursor(last)
      : null,
  };
}

/// Company inbox/detail projection: public quote view + operational fulfilment
/// locations/note + safe inbox metadata. Never includes tokens, audit, costs
/// or customer contact fields.
export function buildLimousineCompanyInboxView(record, {
  activity_seq = null,
  transitions_blocked = false,
} = {}) {
  const rec = asObject(record);
  const req = asObject(rec.request);
  const pub = publicLimousineQuoteView(rec);
  return {
    ...pub,
    fulfilment: {
      from: safeText(req.from, 240),
      to: safeText(req.to, 240),
      ...(req.from_endpoint ? { from_endpoint: req.from_endpoint } : {}),
      ...(req.to_endpoint ? { to_endpoint: req.to_endpoint } : {}),
      stops: Array.isArray(req.stops) ? req.stops.slice(0, 8).map((s) => safeText(s, 240)) : [],
      ...(req.return_pickup_iso ? { return_pickup_iso: safeText(req.return_pickup_iso, 40) } : {}),
      ...(toInt(req.requested_duration_minutes) != null
        ? { requested_duration_minutes: toInt(req.requested_duration_minutes) }
        : {}),
      ...(req.customer_note ? { customer_note: safeText(req.customer_note, 500) } : {}),
      ...(req.locale ? { locale: safeText(req.locale, 8) } : {}),
    },
    inbox: {
      activity_seq: toInt(activity_seq),
      transitions_blocked: transitions_blocked === true,
    },
  };
}

export function projectionContainsForbiddenKey(value, keys = LIMOUSINE_INBOX_FORBIDDEN_KEYS) {
  const rendered = JSON.stringify(value ?? {});
  return keys.filter((key) => {
    const token = String(key || "").trim();
    if (!token) return false;
    const escaped = token.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    // Token boundaries keep short secrets such as "pan" from matching
    // company_viewed, while still catching values like hidden@example.com.
    return new RegExp(`(^|[^A-Za-z])${escaped}([^A-Za-z]|$)`, "i").test(rendered);
  });
}

export function prevalidateLimousineStatusBody(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return { ok: false, reason: "invalid_status_ref" };
  }
  const ref = String(body.status_ref ?? body.statusRef ?? "").trim();
  if (!limousineStatusRefLooksWellFormed(ref)) {
    return { ok: false, reason: "invalid_status_ref" };
  }
  return { ok: true, status_ref: ref };
}

const STATUS_FAIL = Object.freeze({
  status: 404,
  body: { ok: false, error: "invalid_status_ref" },
});

/// Customer status-read orchestrator. Malformed bodies return before any
/// injected KV. Rate-limit denial never calls loadRecord. A live (non-expired)
/// poll performs zero persistExpired writes.
export async function executeLimousineStatusRead({
  body,
  nowIso = null,
  secret,
  bookingKvPresent,
  customerSession = null,
  loadCustomerSession = null,
  rateLimit,
  loadRecord,
  persistExpired,
  isCompanyAllowlisted = null,
  loadPaymentCapability = null,
} = {}) {
  const pre = prevalidateLimousineStatusBody(body);
  if (!pre.ok) {
    return { ...STATUS_FAIL, wrote: false, loaded_record: false, limiter_called: false };
  }
  if (!bookingKvPresent) {
    return {
      status: 500,
      body: { ok: false, error: "BOOKING_KV binding is missing" },
      wrote: false,
      loaded_record: false,
      limiter_called: false,
    };
  }
  const rate = await rateLimit(pre.status_ref);
  if (rate?.limited) {
    return {
      status: 429,
      body: { ok: false, error: "rate_limited" },
      wrote: false,
      loaded_record: false,
      limiter_called: true,
    };
  }
  if (!customerSession && typeof loadCustomerSession === "function") {
    try {
      customerSession = await loadCustomerSession();
    } catch (_) {
      customerSession = null;
    }
  }
  const unsealed = await unsealLimousineStatusRef({
    secret,
    reference: pre.status_ref,
    nowIso,
  });
  if (!unsealed.ok) {
    return { ...STATUS_FAIL, wrote: false, loaded_record: false, limiter_called: true };
  }
  const binding = unsealed.binding || {};
  if (typeof isCompanyAllowlisted === "function") {
    let allowed = false;
    try {
      allowed = isCompanyAllowlisted(binding.company_id) === true;
    } catch (_) {
      allowed = false;
    }
    if (!allowed) {
      return { ...STATUS_FAIL, wrote: false, loaded_record: false, limiter_called: true };
    }
  }
  const record = await loadRecord(binding.quote_request_id);
  if (!record || typeof record !== "object") {
    return { ...STATUS_FAIL, wrote: false, loaded_record: true, limiter_called: true };
  }
  const expected = {
    purpose: "customer_status",
    tenant_id: record.tenant_id,
    company_id: record.company_id,
    quote_request_id: record.quote_request_id,
    customer_fingerprint: asObject(record.status_access).customer_fingerprint,
    created_revision: asObject(record.status_access).created_revision,
  };
  const match = limousineStatusBindingMatches(binding, expected);
  if (!match.ok) {
    return { ...STATUS_FAIL, wrote: false, loaded_record: true, limiter_called: true };
  }
  if (customerSession) {
    const session = asObject(customerSession);
    const globalCustomer = isLimousineGlobalCustomerSession(session);
    if (
      !globalCustomer &&
      (safeText(session.tenant_id, 96) !== safeText(binding.tenant_id, 96) ||
        safeText(session.company_id, 96) !== safeText(binding.company_id, 96))
    ) {
      return { ...STATUS_FAIL, wrote: false, loaded_record: true, limiter_called: true };
    }
    const customerRef = safeText(session.customer_id, 160);
    if (!customerRef || !safeText(binding.customer_fingerprint, 80)) {
      return { ...STATUS_FAIL, wrote: false, loaded_record: true, limiter_called: true };
    }
    // Global sessions are not partner-scoped. Rebuild the create-time
    // fingerprint on the quote's tenant/company so the same customer still
    // matches and a different customer still fails closed.
    const sessionFp = buildLimousineCustomerFingerprint({
      tenantId: globalCustomer ? binding.tenant_id : session.tenant_id,
      companyId: globalCustomer ? binding.company_id : session.company_id,
      customerRef,
      quoteRequestId: binding.quote_request_id,
      itineraryFingerprint: asObject(record.request).itinerary_fingerprint,
    });
    if (!sessionFp || sessionFp !== binding.customer_fingerprint) {
      return { ...STATUS_FAIL, wrote: false, loaded_record: true, limiter_called: true };
    }
  }

  const now = nowIso || new Date().toISOString();
  const observed = observeLimousineQuoteExpiry(record, { nowIso: now });
  let viewRecord = observed.record || record;
  let wrote = false;
  if (observed.ok && observed.changed) {
    viewRecord = appendLimousineQuoteAudit(viewRecord, observed.audit);
    if (typeof persistExpired === "function") {
      await persistExpired(viewRecord);
    }
    wrote = true;
  }
  const view = publicLimousineQuoteView(viewRecord);
  // An accepted quote is booked against this partner, so the customer's payment
  // picker needs the partner's capability — including after a process death,
  // when this poll is the only authoritative read the app still holds.
  let capability = null;
  if (
    typeof loadPaymentCapability === "function" &&
    viewRecord.state === LIMOUSINE_QUOTE_STATES.ACCEPTED
  ) {
    try {
      const loaded = await loadPaymentCapability(viewRecord);
      capability = loaded && typeof loaded === "object" ? loaded : null;
    } catch (_) {
      capability = null;
    }
  }
  return {
    status: 200,
    body: {
      ok: true,
      quote_request: view,
      ...(capability ? { payment_capability: capability } : {}),
    },
    wrote,
    loaded_record: true,
    limiter_called: true,
  };
}

export { LIMOUSINE_QUOTE_STATES };
