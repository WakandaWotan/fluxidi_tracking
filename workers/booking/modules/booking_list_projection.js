/* P0C — projection-first company/driver booking lists.
 *
 * GET never hydrates `booking:{id}` after a scope's complete marker exists.
 * Mutations maintain paged summaries best-effort. Admin rebuild is the only
 * scan path and is never invoked from GET.
 */

import { sanitizeTenantString, safeStr } from "./parsing_utils.js";
import { jsonBase64urlEncode, jsonBase64urlDecode } from "./crypto_utils.js";
import { _scopeText, resolveBookingTenantScopeFromRecord } from "./auth_scope.js";
import { _pick, isTerminalLifecycleStatus } from "./booking_utils.js";
import {
  _dashboardBoolLike,
  _dashboardCanonicalBookingNumber,
  _dashboardUuidLikeId,
  _dashboardIdentityMeta,
  _bookingListIsPaymentShadowRecord,
  _resolveCanonicalBookingIdFromShadow,
} from "./booking_identity.js";
import { bookingMatchesTenantVisibleListScope } from "./legacy_scope_migration.js";
import {
  _flattenBookingForRidesListWithOperationalLegs,
  _rowIsStreetDirectRide,
} from "./booking_read_model.js";
import {
  _driverAvailableUnassignedRowIsOpenLike,
  _driverAvailableUnassignedPaymentEligible,
  _driverAvailableUnassignedCanonicalRecord,
  _driverAvailableUnassignedRowHidden,
} from "./dispatch_open_pool.js";
import { isAllocatorProbeRecord } from "./human_booking_id_allocator.mjs";

export const LIST_PROJ_VERSION = 1;
export const LIST_PROJ_PAGE_SIZE = 200;
export const LIST_PROJ_REBUILD_MAX_RECORDS = 200;
export const LIST_PROJ_GET_MAX_READS = 5;
export const LIST_PROJ_GET_MAX_LISTS = 2;
export const LIST_PROJ_REBUILD_MAX_READS = 800;
export const LIST_PROJ_REBUILD_MAX_LISTS = 4;
export const LIST_PROJ_REBUILD_MAX_WRITES = 800;
export const ACTIONABLE_GRACE_MS = 6 * 60 * 60 * 1000;

const FORBIDDEN_ROW_KEYS = new Set([
  "access_token",
  "accessToken",
  "token",
  "secret",
  "client_secret",
  "clientSecret",
  "api_key",
  "apiKey",
  "authorization",
  "checkout_url",
  "checkoutUrl",
  "redirect_url",
  "redirectUrl",
  "webhook_url",
  "webhookUrl",
  "payment_token",
  "paymentToken",
  "card_number",
  "cardNumber",
]);

export function normalizeListProjectionScope(scope) {
  const tenant = sanitizeTenantString(scope?.tenant_id ?? scope?.tenantId, 80);
  const company = sanitizeTenantString(scope?.company_id ?? scope?.companyId, 80);
  return {
    tenant_id: tenant,
    company_id: company,
    hasScope: !!(tenant && company),
  };
}

export function companyListProjectionMarkerKey(scope) {
  const s = normalizeListProjectionScope(scope);
  if (!s.hasScope) return "";
  return `tenant:${s.tenant_id}:company:${s.company_id}:bookings:list:proj:v1:marker`;
}

export function companyListProjectionRebuildKey(scope) {
  const s = normalizeListProjectionScope(scope);
  if (!s.hasScope) return "";
  return `tenant:${s.tenant_id}:company:${s.company_id}:bookings:list:proj:v1:rebuild`;
}

export function companyListProjectionPendingMarkerKey(scope) {
  const s = normalizeListProjectionScope(scope);
  if (!s.hasScope) return "";
  return `tenant:${s.tenant_id}:company:${s.company_id}:bookings:list:proj:v1:marker:pending`;
}

export function companyListProjectionPageKey(scope, generation, view, pageId) {
  const s = normalizeListProjectionScope(scope);
  const g = Math.max(1, Math.trunc(Number(generation) || 0));
  const v = safeStr(view, 24) || "all";
  const p = safeStr(pageId, 32);
  if (!s.hasScope || !p) return "";
  return `tenant:${s.tenant_id}:company:${s.company_id}:bookings:list:proj:v1:g:${g}:v:${v}:p:${p}`;
}

export function companyListProjectionLocatorKey(scope, generation, bookingId) {
  const s = normalizeListProjectionScope(scope);
  const g = Math.max(1, Math.trunc(Number(generation) || 0));
  const id = safeStr(bookingId, 160);
  if (!s.hasScope || !id) return "";
  return `tenant:${s.tenant_id}:company:${s.company_id}:bookings:list:proj:v1:g:${g}:loc:${id}`;
}

export function actorListProjectionMarkerKey(scope, kind, actorId, { pending = false } = {}) {
  const s = normalizeListProjectionScope(scope);
  const k = kind === "vehicle" ? "vehicle" : "driver";
  const id = sanitizeTenantString(actorId, k === "vehicle" ? 128 : 96);
  if (!s.hasScope || !id) return "";
  return `tenant:${s.tenant_id}:company:${s.company_id}:${k}:${id}:bookings:list:proj:v1:marker${
    pending ? ":pending" : ""
  }`;
}

export function actorListProjectionPageKey(scope, kind, actorId, generation, view, pageId) {
  const s = normalizeListProjectionScope(scope);
  const k = kind === "vehicle" ? "vehicle" : "driver";
  const id = sanitizeTenantString(actorId, k === "vehicle" ? 128 : 96);
  const g = Math.max(1, Math.trunc(Number(generation) || 0));
  const v = safeStr(view, 24) || "all";
  const p = safeStr(pageId, 32);
  if (!s.hasScope || !id || !p) return "";
  return `tenant:${s.tenant_id}:company:${s.company_id}:${k}:${id}:bookings:list:proj:v1:g:${g}:v:${v}:p:${p}`;
}

function emptyView() {
  return { pages: [], row_count: 0, next_page_id: 1 };
}

function emptyMarker(generation = 1) {
  return {
    version: LIST_PROJ_VERSION,
    generation: Math.max(1, Math.trunc(Number(generation) || 1)),
    complete: false,
    health: "ok",
    dirty_reason: "",
    updated_at: "",
    views: {
      all: emptyView(),
      active: emptyView(),
      dispatch: emptyView(),
    },
  };
}

function cloneMarker(marker) {
  return JSON.parse(JSON.stringify(marker || emptyMarker()));
}

function rowKey(row) {
  const bookingId = safeStr(row?.booking_id ?? row?.bookingId ?? row?._proj?.booking_id, 160);
  const legId = safeStr(row?.leg_id ?? row?.legId ?? row?._proj?.leg_id, 200);
  return `${bookingId}::${legId}`;
}

function sortMsFromIso(value) {
  const ms = Date.parse(safeStr(value, 80));
  return Number.isFinite(ms) ? ms : 0;
}

export function compareCompanyListSort(a, b) {
  const ma = Number(a?._proj?.sort_ms || 0);
  const mb = Number(b?._proj?.sort_ms || 0);
  if (mb !== ma) return mb - ma;
  const idA = safeStr(a?._proj?.booking_id ?? a?.booking_id, 160);
  const idB = safeStr(b?._proj?.booking_id ?? b?.booking_id, 160);
  if (idA !== idB) return idB.localeCompare(idA);
  const legA = safeStr(a?._proj?.leg_id ?? a?.leg_id, 200);
  const legB = safeStr(b?._proj?.leg_id ?? b?.leg_id, 200);
  return legB.localeCompare(legA);
}

export function compareDriverActiveSort(a, b) {
  const pa = Number.isFinite(Number(a?._proj?.pickup_ms))
    ? Number(a._proj.pickup_ms)
    : Number.POSITIVE_INFINITY;
  const pb = Number.isFinite(Number(b?._proj?.pickup_ms))
    ? Number(b._proj.pickup_ms)
    : Number.POSITIVE_INFINITY;
  if (pa !== pb) return pa - pb;
  const idA = safeStr(a?._proj?.booking_id ?? a?.booking_id, 160);
  const idB = safeStr(b?._proj?.booking_id ?? b?.booking_id, 160);
  if (idA !== idB) return idA.localeCompare(idB);
  const legA = safeStr(a?._proj?.leg_id ?? a?.leg_id, 200);
  const legB = safeStr(b?._proj?.leg_id ?? b?.leg_id, 200);
  return legA.localeCompare(legB);
}

function compareForView(view, kind) {
  if (kind === "driver" || kind === "vehicle") {
    return view === "active" || view === "dispatch" ? compareDriverActiveSort : compareCompanyListSort;
  }
  return view === "dispatch" ? compareDriverActiveSort : compareCompanyListSort;
}

function sanitizeListRow(row) {
  if (!row || typeof row !== "object") return null;
  const out = {};
  for (const [key, value] of Object.entries(row)) {
    if (FORBIDDEN_ROW_KEYS.has(key)) continue;
    if (key === "_proj") continue;
    out[key] = value;
  }
  return out;
}

function decorateRow(row) {
  const bookingId = safeStr(row?.booking_id ?? row?.bookingId, 160);
  const legId = safeStr(row?.leg_id ?? row?.legId, 200);
  const createdAt = safeStr(row?.created_at ?? row?.createdAt, 80);
  const updatedAt = safeStr(row?.updated_at ?? row?.updatedAt, 80);
  const pickupIso = safeStr(row?.pickup_iso ?? row?.pickupIso, 80);
  const pickupMs = Date.parse(pickupIso);
  const sortMs = Math.max(sortMsFromIso(createdAt), sortMsFromIso(updatedAt), sortMsFromIso(pickupIso));
  const clean = sanitizeListRow(row);
  if (!clean || !bookingId) return null;
  clean.booking_id = bookingId;
  if (legId) {
    clean.leg_id = legId;
    clean.legId = legId;
  }
  return {
    ...clean,
    _proj: {
      sort_ms: sortMs,
      pickup_ms: Number.isFinite(pickupMs) ? pickupMs : 0,
      booking_id: bookingId,
      leg_id: legId,
      updated_at: updatedAt,
    },
  };
}

function publicRow(row) {
  return sanitizeListRow(row);
}

export function listRowHiddenFromCompany(rec) {
  if (!rec || typeof rec !== "object") return true;
  const hiddenFlags = [
    rec?.company_bookings_hidden,
    rec?.hidden_from_company_bookings,
    _pick(rec, ["booking", "company_bookings_hidden"], null),
    _pick(rec, ["booking", "hidden_from_company_bookings"], null),
    rec?.hidden,
    rec?.is_hidden,
    rec?.customer_hidden,
    rec?.archived,
    rec?.deleted,
    _pick(rec, ["booking", "hidden"], null),
    _pick(rec, ["booking", "is_hidden"], null),
    _pick(rec, ["booking", "customer_hidden"], null),
    _pick(rec, ["booking", "archived"], null),
    _pick(rec, ["booking", "deleted"], null),
  ];
  return hiddenFlags.some((value) => _dashboardBoolLike(value));
}

export function companyListRowEligible(bookingId, rec, row) {
  const rowId = safeStr(row?.booking_id ?? row?.bookingId ?? bookingId, 160);
  const from = safeStr(row?.from, 240).trim();
  const to = safeStr(row?.to, 240).trim();
  const isUuidLike = _dashboardUuidLikeId(rowId);
  const isCanonicalId = !!_dashboardCanonicalBookingNumber(rowId);
  if (_bookingListIsPaymentShadowRecord(rec, bookingId)) return false;
  const identityMeta = _dashboardIdentityMeta(rec, bookingId);
  if (
    identityMeta?.record_shape_hint === "provisional_payment_record" &&
    isUuidLike &&
    !isCanonicalId
  ) {
    return false;
  }
  if (isUuidLike && !isCanonicalId && (!from || !to)) return false;
  return true;
}

export function isCompanyActiveListRow(row, nowMs = Date.now()) {
  const status = safeStr(row?.status, 40);
  if (status === "COMPLETED" || status === "CANCELLED") return false;
  const pickupTs = row?.pickup_iso ? Date.parse(row.pickup_iso) : Number.NaN;
  const cutoffMs = nowMs - ACTIONABLE_GRACE_MS;
  if (!Number.isFinite(pickupTs)) {
    const legType = safeStr(row?.leg_type ?? row?.legType, 24).toLowerCase();
    const hasRoute = !!safeStr(row?.from, 240).trim() && !!safeStr(row?.to, 240).trim();
    return (
      legType === "return" &&
      hasRoute &&
      (row?.is_operational_leg === true || row?.isOperationalLeg === true)
    );
  }
  return pickupTs >= cutoffMs;
}

export function isDriverActiveListRow(row, nowMs = Date.now()) {
  const status = safeStr(row?.status, 40);
  if (status === "COMPLETED" || status === "CANCELLED") return false;
  if (isTerminalLifecycleStatus(status)) return false;
  if (_rowIsStreetDirectRide(row)) return false;
  const pickupTs = row?.pickup_iso ? Date.parse(row.pickup_iso) : Number.NaN;
  if (!Number.isFinite(pickupTs)) return false;
  return pickupTs >= nowMs - ACTIONABLE_GRACE_MS;
}

async function promotePendingMarker(env, pendingKey, liveKey, generation) {
  const pending = await kvGetJson(env, pendingKey);
  const next = pending && pending.views ? cloneMarker(pending) : emptyMarker(generation);
  next.generation = generation;
  next.complete = true;
  next.health = "ok";
  next.dirty_reason = "";
  next.updated_at = new Date().toISOString();
  await kvPutJson(env, liveKey, next);
}

export function isDispatchListRow(row, rec, nowMs = Date.now()) {
  if (!row || !rec) return false;
  if (_driverAvailableUnassignedRowHidden(rec)) return false;
  const bookingId = safeStr(row?.booking_id ?? row?.bookingId, 160);
  if (!_driverAvailableUnassignedCanonicalRecord(bookingId, rec)) return false;
  if (safeStr(row?.assigned_driver_id ?? row?.assignedDriverId, 96)) return false;
  if (safeStr(row?.assigned_vehicle_id ?? row?.assignedVehicleId, 128)) return false;
  const status = safeStr(row?.status, 40);
  if (status === "COMPLETED" || status === "CANCELLED" || isTerminalLifecycleStatus(status)) {
    return false;
  }
  if (!_driverAvailableUnassignedRowIsOpenLike(row, rec)) return false;
  const pickupTs = row?.pickup_iso ? Date.parse(row.pickup_iso) : Number.NaN;
  if (!Number.isFinite(pickupTs) || pickupTs < nowMs - ACTIONABLE_GRACE_MS) return false;
  if (!_driverAvailableUnassignedPaymentEligible(rec, row)) return false;
  return true;
}

export function projectBookingListRows(bookingId, rec, nowMs = Date.now()) {
  const safeBookingId = safeStr(bookingId, 160);
  if (!safeBookingId || !rec || typeof rec !== "object") return [];
  if (isAllocatorProbeRecord(rec)) return [];
  if (_bookingListIsPaymentShadowRecord(rec, safeBookingId)) {
    return [];
  }
  if (listRowHiddenFromCompany(rec)) return [];
  const rawRows = _flattenBookingForRidesListWithOperationalLegs(safeBookingId, rec);
  const out = [];
  for (const raw of rawRows) {
    if (!companyListRowEligible(safeBookingId, rec, raw)) continue;
    const row = decorateRow(raw);
    if (!row) continue;
    row._proj.active = isCompanyActiveListRow(row, nowMs);
    row._proj.driver_active = isDriverActiveListRow(row, nowMs);
    row._proj.dispatch = isDispatchListRow(row, rec, nowMs);
    out.push(row);
  }
  return out;
}

export function encodeListCursor(payload) {
  try {
    return jsonBase64urlEncode(payload || {});
  } catch (_) {
    return "";
  }
}

export function decodeListCursor(raw) {
  const text = safeStr(raw, 4000);
  if (!text) return null;
  try {
    const parsed = jsonBase64urlDecode(text);
    if (!parsed || typeof parsed !== "object") return null;
    return parsed;
  } catch (_) {
    return null;
  }
}

async function kvGetJson(env, key) {
  if (!env?.BOOKING_KV || !key) return null;
  try {
    const raw = await env.BOOKING_KV.get(key, { type: "json" });
    return raw && typeof raw === "object" && !Array.isArray(raw) ? raw : null;
  } catch (_) {
    return null;
  }
}

async function kvPutJson(env, key, value) {
  if (!env?.BOOKING_KV || !key) return false;
  await env.BOOKING_KV.put(key, JSON.stringify(value));
  return true;
}

function pageDescriptor(pageId, rows, compareFn) {
  const sorted = [...(rows || [])].sort(compareFn);
  const first = sorted[0];
  const last = sorted[sorted.length - 1];
  return {
    id: safeStr(pageId, 32),
    n: sorted.length,
    hi: first
      ? {
          sort_ms: Number(first._proj?.sort_ms || 0),
          pickup_ms: Number(first._proj?.pickup_ms || 0),
          booking_id: safeStr(first._proj?.booking_id, 160),
          leg_id: safeStr(first._proj?.leg_id, 200),
        }
      : null,
    lo: last
      ? {
          sort_ms: Number(last._proj?.sort_ms || 0),
          pickup_ms: Number(last._proj?.pickup_ms || 0),
          booking_id: safeStr(last._proj?.booking_id, 160),
          leg_id: safeStr(last._proj?.leg_id, 200),
        }
      : null,
  };
}

function refreshViewDescriptors(marker, view, pageStore, compareFn) {
  const viewState = marker.views[view] || emptyView();
  const nextPages = [];
  for (const desc of viewState.pages || []) {
    const page = pageStore.get(desc.id);
    const rows = Array.isArray(page?.rows) ? page.rows : [];
    if (!rows.length) continue;
    nextPages.push(pageDescriptor(desc.id, rows, compareFn));
  }
  viewState.pages = nextPages;
  viewState.row_count = nextPages.reduce((sum, d) => sum + Number(d.n || 0), 0);
  marker.views[view] = viewState;
}

function afterCursor(row, cursor, compareFn) {
  if (!cursor?.after) return true;
  const probe = {
    _proj: {
      sort_ms: Number(cursor.after.sort_ms || 0),
      pickup_ms: Number(cursor.after.pickup_ms || 0),
      booking_id: safeStr(cursor.after.booking_id, 160),
      leg_id: safeStr(cursor.after.leg_id, 200),
    },
  };
  return compareFn(row, probe) > 0;
}

function lastCursorPayload({ generation, scopeKind, view, pageId, row, actorKind, actorId }) {
  return {
    v: LIST_PROJ_VERSION,
    g: generation,
    scope: scopeKind,
    view,
    page_id: pageId,
    actor_kind: actorKind || "",
    actor_id: actorId || "",
    after: {
      sort_ms: Number(row?._proj?.sort_ms || 0),
      pickup_ms: Number(row?._proj?.pickup_ms || 0),
      booking_id: safeStr(row?._proj?.booking_id, 160),
      leg_id: safeStr(row?._proj?.leg_id, 200),
    },
  };
}

export async function readCompanyListProjectionMarker(env, scope) {
  const key = companyListProjectionMarkerKey(scope);
  const raw = await kvGetJson(env, key);
  if (!raw) return { ok: true, exists: false, marker: null, key };
  if (raw.version !== LIST_PROJ_VERSION || !raw.views || typeof raw.views !== "object") {
    return { ok: false, exists: true, marker: raw, key, corrupt: true };
  }
  return { ok: true, exists: true, marker: raw, key };
}

export function isCompanyListProjectionActivated(marker) {
  return !!(marker && marker.complete === true && Number(marker.generation) > 0);
}

function logProjectionIssue(reason, extra = {}) {
  try {
    console.log(
      `[BOOKINGS_LIST_PROJECTION] ${JSON.stringify({
        reason: safeStr(reason, 80),
        ...extra,
      })}`,
    );
  } catch (_) {
    // best-effort
  }
}

async function markProjectionDirty(env, scope, reason) {
  const read = await readCompanyListProjectionMarker(env, scope);
  if (!read.exists || !read.marker) return;
  const marker = cloneMarker(read.marker);
  marker.health = "dirty";
  marker.dirty_reason = safeStr(reason, 120);
  marker.updated_at = new Date().toISOString();
  try {
    await kvPutJson(env, read.key, marker);
  } catch (_) {
    // never throw into booking mutations
  }
  logProjectionIssue("degraded", { health: "dirty" });
}

function collectActorIds(rec, rows) {
  const drivers = new Set();
  const vehicles = new Set();
  const addDriver = (value) => {
    const id = sanitizeTenantString(value, 96);
    if (id) drivers.add(id);
  };
  const addVehicle = (value) => {
    const id = sanitizeTenantString(value, 128);
    if (id) vehicles.add(id);
  };
  addDriver(rec?.assigned_driver_id ?? rec?.assignedDriverId);
  addVehicle(rec?.assigned_vehicle_id ?? rec?.assignedVehicleId ?? rec?.vehicle_id);
  for (const row of rows) {
    addDriver(row?.assigned_driver_id ?? row?.assignedDriverId);
    addVehicle(row?.assigned_vehicle_id ?? row?.assignedVehicleId);
  }
  return { drivers: [...drivers], vehicles: [...vehicles] };
}

function pageStoreKey(kind, actorId, view, pageId) {
  return `${kind}:${actorId || "_"}:${view}:${pageId}`;
}

async function loadPage(env, keyBuilder, view, pageId, cache) {
  const cacheKey = pageStoreKey(keyBuilder.kind, keyBuilder.actorId, view, pageId);
  if (cache.pages.has(cacheKey)) return cache.pages.get(cacheKey);
  const key = keyBuilder.pageKey(view, pageId);
  const raw = await kvGetJson(env, key);
  const page = raw && Array.isArray(raw.rows)
    ? { ...raw, rows: raw.rows.map((row) => decorateRow(row) || row) }
    : { version: LIST_PROJ_VERSION, view, page_id: pageId, rows: [] };
  cache.pages.set(cacheKey, page);
  return page;
}

function findInsertPageId(viewState, row, compareFn) {
  const pages = Array.isArray(viewState?.pages) ? viewState.pages : [];
  if (!pages.length) return null;
  for (const desc of pages) {
    if (!desc?.lo) return desc.id;
    const loProbe = { _proj: desc.lo };
    if (compareFn(row, loProbe) <= 0) return desc.id;
  }
  return pages[pages.length - 1].id;
}

function removeBookingFromPage(page, bookingId) {
  const id = safeStr(bookingId, 160);
  const before = page.rows.length;
  page.rows = page.rows.filter((row) => safeStr(row?._proj?.booking_id, 160) !== id);
  return page.rows.length !== before;
}

async function insertRowsIntoView(env, cache, keyBuilder, marker, view, rows, compareFn) {
  const viewState = marker.views[view] || emptyView();
  if (!Array.isArray(viewState.pages)) viewState.pages = [];
  if (!Number.isFinite(Number(viewState.next_page_id))) viewState.next_page_id = 1;
  for (const row of rows) {
    let pageId = findInsertPageId(viewState, row, compareFn);
    if (!pageId) {
      pageId = String(viewState.next_page_id++);
      viewState.pages.unshift({ id: pageId, n: 0, hi: null, lo: null });
    }
    const page = await loadPage(env, keyBuilder, view, pageId, cache);
    page.rows = page.rows.filter((existing) => rowKey(existing) !== rowKey(row));
    page.rows.push(row);
    page.rows.sort(compareFn);
    const cacheKey = pageStoreKey(keyBuilder.kind, keyBuilder.actorId, view, pageId);
    cache.dirtyPages.add(cacheKey);
    cache.pageMeta.set(cacheKey, { keyBuilder, view, pageId, generation: marker.generation });
    while (page.rows.length > LIST_PROJ_PAGE_SIZE) {
      const overflow = page.rows.splice(LIST_PROJ_PAGE_SIZE);
      const newId = String(viewState.next_page_id++);
      const newPage = {
        version: LIST_PROJ_VERSION,
        view,
        page_id: newId,
        rows: overflow,
      };
      const newCacheKey = pageStoreKey(keyBuilder.kind, keyBuilder.actorId, view, newId);
      cache.pages.set(newCacheKey, newPage);
      cache.dirtyPages.add(newCacheKey);
      cache.pageMeta.set(newCacheKey, {
        keyBuilder,
        view,
        pageId: newId,
        generation: marker.generation,
      });
      const idx = viewState.pages.findIndex((d) => d.id === pageId);
      viewState.pages.splice(Math.max(0, idx) + 1, 0, { id: newId, n: overflow.length, hi: null, lo: null });
    }
  }
  marker.views[view] = viewState;
  const byId = new Map();
  for (const desc of viewState.pages) {
    const ck = pageStoreKey(keyBuilder.kind, keyBuilder.actorId, view, desc.id);
    if (cache.pages.has(ck)) byId.set(desc.id, cache.pages.get(ck));
  }
  refreshViewDescriptors(marker, view, byId, compareFn);
}

function companyKeyBuilder(scope, generation, { pending = false } = {}) {
  return {
    kind: "company",
    actorId: "",
    pageKey: (view, pageId) => companyListProjectionPageKey(scope, generation, view, pageId),
    markerKey: () =>
      pending
        ? companyListProjectionPendingMarkerKey(scope)
        : companyListProjectionMarkerKey(scope),
  };
}

function actorKeyBuilder(scope, kind, actorId, generation, { pending = false } = {}) {
  return {
    kind,
    actorId,
    pageKey: (view, pageId) => actorListProjectionPageKey(scope, kind, actorId, generation, view, pageId),
    markerKey: () => actorListProjectionMarkerKey(scope, kind, actorId, { pending }),
  };
}

async function flushProjectionCache(env, cache) {
  for (const cacheKey of cache.dirtyPages) {
    const meta = cache.pageMeta.get(cacheKey);
    const page = cache.pages.get(cacheKey);
    if (!meta || !page) continue;
    const key = meta.keyBuilder.pageKey(meta.view, meta.pageId);
    if (!page.rows.length) {
      try {
        await env.BOOKING_KV.delete(key);
      } catch (_) {
        // empty-page delete is best-effort
      }
      continue;
    }
    await kvPutJson(env, key, {
      version: LIST_PROJ_VERSION,
      generation: meta.generation,
      view: meta.view,
      page_id: meta.pageId,
      rows: page.rows.map(publicRow),
    });
  }
  for (const [key, value] of cache.markers.entries()) {
    if (!cache.dirtyMarkers.has(key)) continue;
    value.updated_at = new Date().toISOString();
    await kvPutJson(env, key, value);
  }
  for (const [key, value] of cache.locators.entries()) {
    if (!cache.dirtyLocators.has(key)) continue;
    await kvPutJson(env, key, value);
  }
}

function newCache() {
  return {
    pages: new Map(),
    pageMeta: new Map(),
    dirtyPages: new Set(),
    markers: new Map(),
    dirtyMarkers: new Set(),
    locators: new Map(),
    dirtyLocators: new Set(),
  };
}

async function loadMarkerIntoCache(env, key, cache, generationFallback) {
  if (cache.markers.has(key)) return cache.markers.get(key);
  const raw = await kvGetJson(env, key);
  const marker = raw && raw.views ? cloneMarker(raw) : emptyMarker(generationFallback);
  if (!raw) marker.generation = generationFallback;
  cache.markers.set(key, marker);
  return marker;
}

async function removeBookingFromMarkerViews(env, cache, keyBuilder, marker, bookingId, compareFnByView) {
  for (const view of Object.keys(marker.views || {})) {
    const viewState = marker.views[view];
    const pages = Array.isArray(viewState?.pages) ? viewState.pages : [];
    for (const desc of pages) {
      const page = await loadPage(env, keyBuilder, view, desc.id, cache);
      if (removeBookingFromPage(page, bookingId)) {
        const ck = pageStoreKey(keyBuilder.kind, keyBuilder.actorId, view, desc.id);
        cache.dirtyPages.add(ck);
        cache.pageMeta.set(ck, {
          keyBuilder,
          view,
          pageId: desc.id,
          generation: marker.generation,
        });
      }
    }
    const byId = new Map();
    for (const desc of pages) {
      const ck = pageStoreKey(keyBuilder.kind, keyBuilder.actorId, view, desc.id);
      if (cache.pages.has(ck)) byId.set(desc.id, cache.pages.get(ck));
    }
    refreshViewDescriptors(marker, view, byId, compareFnByView(view));
  }
}

export async function upsertBookingListProjectionsBestEffort(
  env,
  bookingId,
  rec,
  scopeHint = null,
  options = {},
) {
  try {
    if (!env?.BOOKING_KV) return { ok: false, reason: "missing_kv" };
    if (isAllocatorProbeRecord(rec)) return { ok: true, skipped: true, reason: "allocator_probe" };
    const recordScope = resolveBookingTenantScopeFromRecord(rec);
    const scope = normalizeListProjectionScope(scopeHint?.hasScope ? scopeHint : recordScope);
    if (!scope.hasScope) return { ok: false, skipped: true, reason: "missing_scope" };
    if (rec && !bookingMatchesTenantVisibleListScope(rec, scope)) {
      return removeBookingListProjectionsBestEffort(env, bookingId, rec, scope);
    }
    const markerRead = await readCompanyListProjectionMarker(env, scope);
    const liveComplete = isCompanyListProjectionActivated(markerRead.marker);
    const liveGeneration = Number(markerRead.marker?.generation || 0);
    const generations = new Set();
    if (Array.isArray(options.generations) && options.generations.length) {
      for (const g of options.generations) {
        const n = Number(g);
        if (Number.isFinite(n) && n > 0) generations.add(n);
      }
    } else {
      const rebuild = await kvGetJson(env, companyListProjectionRebuildKey(scope));
      const pendingGen = Number(rebuild?.generation || 0);
      const rebuildOpen = pendingGen > 0 && rebuild?.complete !== true;
      if (!liveComplete && !rebuildOpen) {
        return { ok: true, skipped: true, reason: "projection_inactive" };
      }
      if (liveComplete) generations.add(liveGeneration);
      if (rebuildOpen) generations.add(pendingGen);
    }
    if (!generations.size) return { ok: true, skipped: true, reason: "projection_inactive" };
    const rows = projectBookingListRows(bookingId, rec);
    const incomingUpdatedAt = safeStr(
      rec?.updated_at ?? rec?.updatedAt ?? rec?.booking?.updated_at,
      80,
    );
    const incomingUpdatedMs = sortMsFromIso(incomingUpdatedAt);
    const actors = collectActorIds(rec, rows);
    const cache = newCache();
    for (const generation of generations) {
      const pending = !(liveComplete && generation === liveGeneration);
      const companyBuilder = companyKeyBuilder(scope, generation, { pending });
      const companyMarkerKey = companyBuilder.markerKey();
      const companyMarker = await loadMarkerIntoCache(env, companyMarkerKey, cache, generation);
      companyMarker.generation = generation;
      const locatorKey = companyListProjectionLocatorKey(scope, generation, bookingId);
      const existingLocator = cache.locators.has(locatorKey)
        ? cache.locators.get(locatorKey)
        : await kvGetJson(env, locatorKey);
      if (existingLocator) cache.locators.set(locatorKey, existingLocator);
      const existingUpdatedMs = sortMsFromIso(existingLocator?.updated_at);
      if (existingLocator && incomingUpdatedMs && existingUpdatedMs && incomingUpdatedMs < existingUpdatedMs) {
        continue;
      }
      await removeBookingFromMarkerViews(
        env,
        cache,
        companyBuilder,
        companyMarker,
        bookingId,
        (view) => compareForView(view, "company"),
      );
      const prevDrivers = Array.isArray(existingLocator?.drivers) ? existingLocator.drivers : [];
      const prevVehicles = Array.isArray(existingLocator?.vehicles) ? existingLocator.vehicles : [];
      for (const driverId of prevDrivers) {
        const builder = actorKeyBuilder(scope, "driver", driverId, generation, { pending });
        const marker = await loadMarkerIntoCache(env, builder.markerKey(), cache, generation);
        await removeBookingFromMarkerViews(
          env,
          cache,
          builder,
          marker,
          bookingId,
          (view) => compareForView(view, "driver"),
        );
        cache.dirtyMarkers.add(builder.markerKey());
      }
      for (const vehicleId of prevVehicles) {
        const builder = actorKeyBuilder(scope, "vehicle", vehicleId, generation, { pending });
        const marker = await loadMarkerIntoCache(env, builder.markerKey(), cache, generation);
        await removeBookingFromMarkerViews(
          env,
          cache,
          builder,
          marker,
          bookingId,
          (view) => compareForView(view, "vehicle"),
        );
        cache.dirtyMarkers.add(builder.markerKey());
      }
      if (!rows.length) {
        cache.locators.set(locatorKey, {
          generation,
          booking_id: safeStr(bookingId, 160),
          updated_at: incomingUpdatedAt,
          drivers: [],
          vehicles: [],
          removed: true,
        });
        cache.dirtyLocators.add(locatorKey);
        cache.dirtyMarkers.add(companyMarkerKey);
        continue;
      }
      await insertRowsIntoView(env, cache, companyBuilder, companyMarker, "all", rows, compareCompanyListSort);
      await insertRowsIntoView(
        env,
        cache,
        companyBuilder,
        companyMarker,
        "active",
        rows.filter((row) => row._proj.active),
        compareCompanyListSort,
      );
      await insertRowsIntoView(
        env,
        cache,
        companyBuilder,
        companyMarker,
        "dispatch",
        rows.filter((row) => row._proj.dispatch).map((row) => ({
          ...row,
          available_unassigned: true,
          availableUnassigned: true,
        })),
        compareDriverActiveSort,
      );
      cache.dirtyMarkers.add(companyMarkerKey);
      for (const driverId of actors.drivers) {
        const builder = actorKeyBuilder(scope, "driver", driverId, generation, { pending });
        const marker = await loadMarkerIntoCache(env, builder.markerKey(), cache, generation);
        marker.generation = generation;
        const driverRows = rows.filter((row) => {
          const assigned = sanitizeTenantString(row?.assigned_driver_id ?? row?.assignedDriverId, 96);
          return assigned === driverId;
        });
        await insertRowsIntoView(env, cache, builder, marker, "all", driverRows, compareCompanyListSort);
        await insertRowsIntoView(
          env,
          cache,
          builder,
          marker,
          "active",
          driverRows.filter((row) => row._proj.driver_active),
          compareDriverActiveSort,
        );
        cache.dirtyMarkers.add(builder.markerKey());
      }
      for (const vehicleId of actors.vehicles) {
        const builder = actorKeyBuilder(scope, "vehicle", vehicleId, generation, { pending });
        const marker = await loadMarkerIntoCache(env, builder.markerKey(), cache, generation);
        marker.generation = generation;
        const vehicleRows = rows.filter((row) => {
          const assigned = sanitizeTenantString(row?.assigned_vehicle_id ?? row?.assignedVehicleId, 128);
          return assigned === vehicleId;
        });
        await insertRowsIntoView(env, cache, builder, marker, "all", vehicleRows, compareCompanyListSort);
        await insertRowsIntoView(
          env,
          cache,
          builder,
          marker,
          "active",
          vehicleRows.filter((row) => row._proj.driver_active),
          compareDriverActiveSort,
        );
        cache.dirtyMarkers.add(builder.markerKey());
      }
      cache.locators.set(locatorKey, {
        generation,
        booking_id: safeStr(bookingId, 160),
        updated_at: incomingUpdatedAt,
        drivers: actors.drivers,
        vehicles: actors.vehicles,
        removed: false,
      });
      cache.dirtyLocators.add(locatorKey);
    }
    await flushProjectionCache(env, cache);
    return { ok: true };
  } catch (_) {
    try {
      const scope = normalizeListProjectionScope(scopeHint || resolveBookingTenantScopeFromRecord(rec));
      await markProjectionDirty(env, scope, "projection_upsert_failed");
    } catch (__) {
      // swallow
    }
    return { ok: false, reason: "exception" };
  }
}

export async function removeBookingListProjectionsBestEffort(env, bookingId, recOrScopeHint = null, scopeHint = null) {
  try {
    if (!env?.BOOKING_KV) return { ok: false, reason: "missing_kv" };
    const rec = recOrScopeHint && typeof recOrScopeHint === "object" && !recOrScopeHint.hasScope
      ? recOrScopeHint
      : null;
    const scope = normalizeListProjectionScope(
      scopeHint?.hasScope
        ? scopeHint
        : recOrScopeHint?.hasScope
          ? recOrScopeHint
          : rec
            ? resolveBookingTenantScopeFromRecord(rec)
            : recOrScopeHint,
    );
    if (!scope.hasScope) return { ok: false, skipped: true, reason: "missing_scope" };
    const markerRead = await readCompanyListProjectionMarker(env, scope);
    const rebuild = await kvGetJson(env, companyListProjectionRebuildKey(scope));
    const liveComplete = isCompanyListProjectionActivated(markerRead.marker);
    const pendingGen = Number(rebuild?.generation || 0);
    const rebuildOpen = pendingGen > 0 && rebuild?.complete !== true;
    if (!liveComplete && !rebuildOpen) return { ok: true, skipped: true, reason: "projection_inactive" };
    const generations = new Set();
    const liveGeneration = Number(markerRead.marker?.generation || 0);
    if (liveComplete) generations.add(liveGeneration);
    if (rebuildOpen) generations.add(pendingGen);
    const cache = newCache();
    for (const generation of generations) {
      const pending = !(liveComplete && generation === liveGeneration);
      const locatorKey = companyListProjectionLocatorKey(scope, generation, bookingId);
      const locator = await kvGetJson(env, locatorKey);
      const companyBuilder = companyKeyBuilder(scope, generation, { pending });
      const companyMarker = await loadMarkerIntoCache(env, companyBuilder.markerKey(), cache, generation);
      await removeBookingFromMarkerViews(
        env,
        cache,
        companyBuilder,
        companyMarker,
        bookingId,
        (view) => compareForView(view, "company"),
      );
      cache.dirtyMarkers.add(companyBuilder.markerKey());
      const drivers = new Set([
        ...(Array.isArray(locator?.drivers) ? locator.drivers : []),
        sanitizeTenantString(rec?.assigned_driver_id ?? rec?.assignedDriverId, 96),
      ]);
      const vehicles = new Set([
        ...(Array.isArray(locator?.vehicles) ? locator.vehicles : []),
        sanitizeTenantString(rec?.assigned_vehicle_id ?? rec?.assignedVehicleId, 128),
      ]);
      for (const driverId of drivers) {
        if (!driverId) continue;
        const builder = actorKeyBuilder(scope, "driver", driverId, generation, { pending });
        const marker = await loadMarkerIntoCache(env, builder.markerKey(), cache, generation);
        await removeBookingFromMarkerViews(
          env,
          cache,
          builder,
          marker,
          bookingId,
          (view) => compareForView(view, "driver"),
        );
        cache.dirtyMarkers.add(builder.markerKey());
      }
      for (const vehicleId of vehicles) {
        if (!vehicleId) continue;
        const builder = actorKeyBuilder(scope, "vehicle", vehicleId, generation, { pending });
        const marker = await loadMarkerIntoCache(env, builder.markerKey(), cache, generation);
        await removeBookingFromMarkerViews(
          env,
          cache,
          builder,
          marker,
          bookingId,
          (view) => compareForView(view, "vehicle"),
        );
        cache.dirtyMarkers.add(builder.markerKey());
      }
      cache.locators.set(locatorKey, {
        generation,
        booking_id: safeStr(bookingId, 160),
        updated_at: new Date().toISOString(),
        drivers: [],
        vehicles: [],
        removed: true,
      });
      cache.dirtyLocators.add(locatorKey);
    }
    await flushProjectionCache(env, cache);
    return { ok: true };
  } catch (_) {
    try {
      const scope = normalizeListProjectionScope(scopeHint || recOrScopeHint);
      await markProjectionDirty(env, scope, "projection_remove_failed");
    } catch (__) {
      // swallow
    }
    return { ok: false, reason: "exception" };
  }
}

export async function onBookingIndexMutation(event = {}) {
  const env = event.env;
  const bookingId = event.bookingId;
  if (event.removed === true) {
    return removeBookingListProjectionsBestEffort(env, bookingId, event.rec, event.scopeHint);
  }
  return upsertBookingListProjectionsBestEffort(env, bookingId, event.rec, event.scopeHint);
}

async function listFromMarker({
  env,
  marker,
  keyBuilder,
  view,
  limit,
  cursor,
  scopeKind,
  actorKind = "",
  actorId = "",
  nowMs = Date.now(),
  expireActive = false,
}) {
  const lim = Math.min(200, Math.max(1, Number(limit) || 50));
  const compareFn = compareForView(view, actorKind || "company");
  const viewState = marker?.views?.[view] || emptyView();
  const pages = Array.isArray(viewState.pages) ? viewState.pages : [];
  if (!pages.length) {
    return {
      ok: true,
      items: [],
      count: 0,
      next_cursor: null,
      has_more: false,
      source: "projection",
    };
  }
  let startIdx = 0;
  if (cursor?.page_id) {
    const found = pages.findIndex((d) => d.id === safeStr(cursor.page_id, 32));
    if (found >= 0) startIdx = found;
  }
  const items = [];
  let lastPageId = pages[startIdx]?.id;
  let lastRow = null;
  let pagesRead = 0;
  for (let i = startIdx; i < pages.length; i += 1) {
    if (pagesRead >= 2 && items.length >= lim) break;
    const desc = pages[i];
    const key = keyBuilder.pageKey(view, desc.id);
    const page = await kvGetJson(env, key);
    pagesRead += 1;
    if (!page || !Array.isArray(page.rows)) {
      return { ok: false, error: "bookings_list_projection_unavailable", corrupt: true };
    }
    const decorated = page.rows.map((row) => decorateRow(row)).filter(Boolean);
    decorated.sort(compareFn);
    for (const row of decorated) {
      if (cursor && !afterCursor(row, cursor, compareFn) && desc.id === safeStr(cursor.page_id, 32)) {
        continue;
      }
      if (cursor && cursor.page_id && desc.id === cursor.page_id && !afterCursor(row, cursor, compareFn)) {
        continue;
      }
      if (expireActive) {
        const stillActive =
          actorKind === "driver" || actorKind === "vehicle" || view === "dispatch"
            ? isDriverActiveListRow(row, nowMs)
            : isCompanyActiveListRow(row, nowMs);
        if (!stillActive) continue;
      }
      items.push(row);
      lastPageId = desc.id;
      lastRow = row;
      if (items.length > lim) break;
    }
    if (items.length > lim) break;
  }
  const hasMore = items.length > lim || startIdx + pagesRead < pages.length;
  const sliced = items.slice(0, lim);
  const tail = sliced[sliced.length - 1] || lastRow;
  return {
    ok: true,
    items: sliced.map(publicRow),
    count: sliced.length,
    next_cursor:
      hasMore && tail
        ? encodeListCursor(
            lastCursorPayload({
              generation: marker.generation,
              scopeKind,
              view,
              pageId: lastPageId,
              row: tail,
              actorKind,
              actorId,
            }),
          )
        : null,
    has_more: hasMore,
    source: "projection",
    degraded: marker.health === "dirty",
  };
}

export async function tryListCompanyBookingsProjected(
  env,
  { limit = 50, includeHistory = false, cursor = "", tenantScope = null } = {},
) {
  if (!tenantScope?.hasScope) return { useLegacy: true };
  if (!env?.BOOKING_KV) return { useLegacy: true };
  const scope = normalizeListProjectionScope(tenantScope);
  const read = await readCompanyListProjectionMarker(env, scope);
  if (read.corrupt) {
    logProjectionIssue("corrupt", { health: "corrupt" });
    return { ok: false, error: "bookings_list_projection_unavailable", degraded: true };
  }
  if (!read.exists || !isCompanyListProjectionActivated(read.marker)) {
    return { useLegacy: true };
  }
  if (read.marker.health === "corrupt") {
    logProjectionIssue("corrupt", { health: "corrupt" });
    return { ok: false, error: "bookings_list_projection_unavailable", degraded: true };
  }
  const parsedCursor = decodeListCursor(cursor);
  const view = includeHistory ? "all" : "active";
  const listed = await listFromMarker({
    env,
    marker: read.marker,
    keyBuilder: companyKeyBuilder(scope, read.marker.generation),
    view,
    limit,
    cursor: parsedCursor && parsedCursor.view === view ? parsedCursor : null,
    scopeKind: "company",
    expireActive: !includeHistory,
  });
  if (listed.ok === false && listed.corrupt) {
    logProjectionIssue("corrupt", { health: "missing_page" });
    return { ok: false, error: "bookings_list_projection_unavailable", degraded: true };
  }
  return listed;
}

export async function tryListDriverBookingsProjected(
  env,
  {
    limit = 50,
    includeHistory = false,
    cursor = "",
    tenantScope = null,
    driverId = "",
    vehicleId = "",
    includeDispatch = true,
  } = {},
) {
  if (!tenantScope?.hasScope) return { useLegacy: true };
  if (!env?.BOOKING_KV) return { useLegacy: true };
  const scope = normalizeListProjectionScope(tenantScope);
  const companyRead = await readCompanyListProjectionMarker(env, scope);
  if (companyRead.corrupt) {
    logProjectionIssue("corrupt", { health: "corrupt" });
    return { ok: false, error: "bookings_list_projection_unavailable", degraded: true };
  }
  if (!companyRead.exists || !isCompanyListProjectionActivated(companyRead.marker)) {
    return { useLegacy: true };
  }
  const generation = companyRead.marker.generation;
  const parsedCursor = decodeListCursor(cursor);
  const view = includeHistory ? "all" : "active";
  const actorKind = sanitizeTenantString(driverId, 96)
    ? "driver"
    : sanitizeTenantString(vehicleId, 128)
      ? "vehicle"
      : "";
  const actorId = actorKind === "driver"
    ? sanitizeTenantString(driverId, 96)
    : sanitizeTenantString(vehicleId, 128);
  if (!actorId) {
    if (!includeDispatch) {
      return {
        ok: true,
        items: [],
        count: 0,
        next_cursor: null,
        has_more: false,
        source: "projection",
      };
    }
    return listFromMarker({
      env,
      marker: companyRead.marker,
      keyBuilder: companyKeyBuilder(scope, generation),
      view: "dispatch",
      limit,
      cursor: parsedCursor && parsedCursor.view === "dispatch" ? parsedCursor : null,
      scopeKind: "company",
      expireActive: true,
    });
  }
  const actorMarkerKey = actorListProjectionMarkerKey(scope, actorKind, actorId);
  const actorMarkerRaw = await kvGetJson(env, actorMarkerKey);
  const actorMarker = actorMarkerRaw && actorMarkerRaw.views
    ? actorMarkerRaw
    : emptyMarker(generation);
  actorMarker.generation = generation;
  actorMarker.complete = true;
  const listed = await listFromMarker({
    env,
    marker: actorMarker,
    keyBuilder: actorKeyBuilder(scope, actorKind, actorId, generation),
    view,
    limit,
    cursor: parsedCursor && parsedCursor.actor_id === actorId ? parsedCursor : null,
    scopeKind: "driver",
    actorKind,
    actorId,
    expireActive: !includeHistory,
  });
  if (listed.ok === false && listed.corrupt) {
    logProjectionIssue("corrupt", { health: "missing_page" });
    return { ok: false, error: "bookings_list_projection_unavailable", degraded: true };
  }
  if (includeHistory || includeDispatch !== true) return listed;
  const dispatch = await listFromMarker({
    env,
    marker: companyRead.marker,
    keyBuilder: companyKeyBuilder(scope, generation),
    view: "dispatch",
    limit: Math.min(200, Number(limit) || 50),
    cursor: null,
    scopeKind: "company",
    expireActive: true,
  });
  if (dispatch.ok === false && dispatch.corrupt) {
    logProjectionIssue("corrupt", { health: "missing_dispatch_page" });
    return { ok: false, error: "bookings_list_projection_unavailable", degraded: true };
  }
  const seen = new Set((listed.items || []).map((row) => rowKey(row)));
  const merged = [...(listed.items || [])];
  for (const row of dispatch.items || []) {
    const key = rowKey(row);
    if (seen.has(key)) continue;
    merged.push(row);
    seen.add(key);
  }
  merged.sort(compareDriverActiveSort);
  const lim = Math.min(200, Math.max(1, Number(limit) || 50));
  const sliced = merged.slice(0, lim);
  return {
    ok: true,
    items: sliced.map(publicRow),
    count: sliced.length,
    next_cursor: listed.next_cursor,
    has_more: listed.has_more === true || merged.length > lim,
    source: "projection",
    assigned: (listed.items || []).length,
    available: (dispatch.items || []).length,
  };
}

export async function rebuildCompanyBookingsListProjectionForScope(
  env,
  scope,
  { dryRun = false, compare = false, cursor = undefined, reset = false } = {},
) {
  const normalizedScope = normalizeListProjectionScope(scope);
  if (!normalizedScope.hasScope) return { ok: false, error: "missing_tenant_scope" };
  if (!env?.BOOKING_KV) return { ok: false, error: "Missing BOOKING_KV binding" };
  const progressKey = companyListProjectionRebuildKey(normalizedScope);
  const live = await readCompanyListProjectionMarker(env, normalizedScope);
  let progress = {
    generation: Number(live.marker?.generation || 0) + 1,
    cursor: null,
    scanned: 0,
    matched_scope: 0,
    indexed: 0,
    skipped: 0,
    compared: 0,
    mismatched: 0,
    drivers: [],
    vehicles: [],
    complete: false,
  };
  if (reset !== true) {
    const existing = await kvGetJson(env, progressKey);
    if (existing && typeof existing === "object") progress = { ...progress, ...existing };
  }
  if (progress.complete === true && reset !== true && !compare) {
    progress = {
      generation: Number(live.marker?.generation || progress.generation || 0) + 1,
      cursor: null,
      scanned: 0,
      matched_scope: 0,
      indexed: 0,
      skipped: 0,
      compared: 0,
      mismatched: 0,
      drivers: [],
      vehicles: [],
      complete: false,
    };
  }
  const generation = Math.max(1, Math.trunc(Number(progress.generation) || 1));
  const touchedDrivers = new Set(Array.isArray(progress.drivers) ? progress.drivers : []);
  const touchedVehicles = new Set(Array.isArray(progress.vehicles) ? progress.vehicles : []);
  if (!dryRun && !compare) {
    await kvPutJson(env, progressKey, {
      ...progress,
      generation,
      complete: false,
      updated_at: new Date().toISOString(),
    });
  }
  const listCursor =
    cursor !== undefined && cursor !== null && String(cursor).trim()
      ? String(cursor)
      : progress.cursor || undefined;
  const page = await env.BOOKING_KV.list({
    prefix: "booking:",
    limit: LIST_PROJ_REBUILD_MAX_RECORDS,
    cursor: listCursor,
  });
  let scanned = 0;
  let matched = 0;
  let indexed = 0;
  let skipped = 0;
  let compared = 0;
  let mismatched = 0;
  for (const item of page?.keys || []) {
    if (scanned >= LIST_PROJ_REBUILD_MAX_RECORDS) break;
    const key = safeStr(item?.name, 240);
    if (!key || !key.startsWith("booking:")) continue;
    scanned += 1;
    const bookingId = key.slice("booking:".length);
    if (!bookingId) {
      skipped += 1;
      continue;
    }
    const rec = await env.BOOKING_KV.get(key, { type: "json" });
    if (!rec || typeof rec !== "object") {
      skipped += 1;
      continue;
    }
    if (isAllocatorProbeRecord(rec)) {
      skipped += 1;
      continue;
    }
    if (!bookingMatchesTenantVisibleListScope(rec, normalizedScope)) continue;
    matched += 1;
    if (compare) {
      compared += 1;
      const rows = projectBookingListRows(bookingId, rec);
      const locator = await kvGetJson(
        env,
        companyListProjectionLocatorKey(normalizedScope, live.marker?.generation || generation, bookingId),
      );
      const expectPresent = rows.length > 0;
      const actuallyPresent = !!(locator && locator.removed !== true);
      if (expectPresent !== actuallyPresent) mismatched += 1;
      continue;
    }
    if (!dryRun) {
      const actors = collectActorIds(rec, projectBookingListRows(bookingId, rec));
      for (const driverId of actors.drivers) touchedDrivers.add(driverId);
      for (const vehicleId of actors.vehicles) touchedVehicles.add(vehicleId);
      const result = await upsertBookingListProjectionsBestEffort(
        env,
        bookingId,
        rec,
        normalizedScope,
        { generations: [generation] },
      );
      if (result?.ok) indexed += 1;
      else skipped += 1;
    } else {
      indexed += 1;
    }
  }
  const nextCursor = page?.list_complete === false && page?.cursor ? String(page.cursor) : null;
  const complete = page?.list_complete !== false;
  const nextProgress = {
    generation,
    cursor: nextCursor,
    scanned: Number(progress.scanned || 0) + scanned,
    matched_scope: Number(progress.matched_scope || 0) + matched,
    indexed: Number(progress.indexed || 0) + indexed,
    skipped: Number(progress.skipped || 0) + skipped,
    compared: Number(progress.compared || 0) + compared,
    mismatched: Number(progress.mismatched || 0) + mismatched,
    drivers: [...touchedDrivers],
    vehicles: [...touchedVehicles],
    complete,
    updated_at: new Date().toISOString(),
  };
  if (!dryRun && !compare) {
    if (complete) {
      for (const driverId of touchedDrivers) {
        await promotePendingMarker(
          env,
          actorListProjectionMarkerKey(normalizedScope, "driver", driverId, { pending: true }),
          actorListProjectionMarkerKey(normalizedScope, "driver", driverId),
          generation,
        );
      }
      for (const vehicleId of touchedVehicles) {
        await promotePendingMarker(
          env,
          actorListProjectionMarkerKey(normalizedScope, "vehicle", vehicleId, { pending: true }),
          actorListProjectionMarkerKey(normalizedScope, "vehicle", vehicleId),
          generation,
        );
      }
      await promotePendingMarker(
        env,
        companyListProjectionPendingMarkerKey(normalizedScope),
        companyListProjectionMarkerKey(normalizedScope),
        generation,
      );
      try {
        await env.BOOKING_KV.delete(progressKey);
      } catch (_) {
        // progress cleanup is best-effort
      }
    } else {
      await kvPutJson(env, progressKey, nextProgress);
    }
  }
  logProjectionIssue("rebuild_summary", {
    dry_run: dryRun === true,
    compare: compare === true,
    complete,
    scanned: nextProgress.scanned,
    matched: nextProgress.matched_scope,
    indexed: nextProgress.indexed,
  });
  return {
    ok: true,
    dry_run: dryRun === true,
    compare: compare === true,
    complete,
    cursor: nextCursor,
    generation,
    scanned: nextProgress.scanned,
    matched_scope: nextProgress.matched_scope,
    indexed: nextProgress.indexed,
    skipped: nextProgress.skipped,
    compared: nextProgress.compared,
    mismatched: nextProgress.mismatched,
    batch_scanned: scanned,
    batch_limit: LIST_PROJ_REBUILD_MAX_RECORDS,
  };
}

export function seedProjectedCompanyPages(scope, rows, { includeHistory = true } = {}) {
  const normalized = normalizeListProjectionScope(scope);
  const generation = 1;
  const view = includeHistory ? "all" : "active";
  const compareFn = compareCompanyListSort;
  const decorated = rows.map((row) => decorateRow(row)).filter(Boolean);
  decorated.sort(compareFn);
  const pages = [];
  for (let i = 0; i < decorated.length; i += LIST_PROJ_PAGE_SIZE) {
    pages.push(decorated.slice(i, i + LIST_PROJ_PAGE_SIZE));
  }
  const marker = emptyMarker(generation);
  marker.complete = true;
  marker.health = "ok";
  marker.updated_at = new Date().toISOString();
  const seed = {};
  const viewState = emptyView();
  pages.forEach((pageRows, idx) => {
    const pageId = String(idx + 1);
    viewState.pages.push(pageDescriptor(pageId, pageRows, compareFn));
    viewState.next_page_id = idx + 2;
    seed[companyListProjectionPageKey(normalized, generation, view, pageId)] = {
      version: LIST_PROJ_VERSION,
      generation,
      view,
      page_id: pageId,
      rows: pageRows.map(publicRow),
    };
  });
  viewState.row_count = decorated.length;
  marker.views[view] = viewState;
  if (view === "all") {
    const activeRows = decorated.filter((row) => isCompanyActiveListRow(row));
    const activeState = emptyView();
    const activePages = [];
    for (let i = 0; i < activeRows.length; i += LIST_PROJ_PAGE_SIZE) {
      activePages.push(activeRows.slice(i, i + LIST_PROJ_PAGE_SIZE));
    }
    activePages.forEach((pageRows, idx) => {
      const pageId = String(idx + 1);
      activeState.pages.push(pageDescriptor(pageId, pageRows, compareFn));
      activeState.next_page_id = idx + 2;
      seed[companyListProjectionPageKey(normalized, generation, "active", pageId)] = {
        version: LIST_PROJ_VERSION,
        generation,
        view: "active",
        page_id: pageId,
        rows: pageRows.map(publicRow),
      };
    });
    activeState.row_count = activeRows.length;
    marker.views.active = activeState;
  }
  seed[companyListProjectionMarkerKey(normalized)] = marker;
  return seed;
}

export function seedProjectedDriverPages(scope, driverId, rows, { includeHistory = false } = {}) {
  const normalized = normalizeListProjectionScope(scope);
  const generation = 1;
  const view = includeHistory ? "all" : "active";
  const compareFn = compareForView(view, "driver");
  const decorated = rows.map((row) => decorateRow(row)).filter(Boolean);
  decorated.sort(compareFn);
  const marker = emptyMarker(generation);
  marker.complete = true;
  marker.health = "ok";
  marker.updated_at = new Date().toISOString();
  const seed = seedProjectedCompanyPages(normalized, rows, { includeHistory: true });
  const viewState = emptyView();
  const pages = [];
  for (let i = 0; i < decorated.length; i += LIST_PROJ_PAGE_SIZE) {
    pages.push(decorated.slice(i, i + LIST_PROJ_PAGE_SIZE));
  }
  pages.forEach((pageRows, idx) => {
    const pageId = String(idx + 1);
    viewState.pages.push(pageDescriptor(pageId, pageRows, compareFn));
    viewState.next_page_id = idx + 2;
    seed[actorListProjectionPageKey(normalized, "driver", driverId, generation, view, pageId)] = {
      version: LIST_PROJ_VERSION,
      generation,
      view,
      page_id: pageId,
      rows: pageRows.map(publicRow),
    };
  });
  viewState.row_count = decorated.length;
  marker.views[view] = viewState;
  seed[actorListProjectionMarkerKey(normalized, "driver", driverId)] = marker;
  return seed;
}
