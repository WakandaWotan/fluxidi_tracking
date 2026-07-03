/* Fluxidi pure booking/driver-index helpers (BW-M7B).
 *
 * Verbatim extraction from workers/booking/fluxidi_booking_worker.js — no
 * behavior change. Strictly-acyclic helpers only:
 *
 *   - customer/driver/vehicle scoped booking-index KV key builders,
 *   - company bookings-list index KV key builder,
 *   - pure booking-assignment index-item projection (no booking-core deps),
 *   - read-only KV loaders for the four booking-index shapes above,
 *   - pure "is scoped-booking-index-like key?" regex predicate,
 *   - pure `COMPANY_BOOKINGS_LIST_INDEX_STALE_AFTER_MS` env-flag reader.
 *
 * Explicitly NOT moved (STOP rule — writers, orchestrators, or booking-core
 * coupling):
 *   - listDriverBookingsAuthoritative, listAdminDriverBookingsPreviewAuthoritative,
 *     hydrateCustomerBookingsFromScopedIndex — orchestrators.
 *   - upsertCustomerScopedBookingIndexForBooking, saveScopedAssignmentBookingIndex,
 *     upsertDriverVehicleBookingIndexesBestEffort,
 *     removeDriverVehicleBookingIndexesBestEffort, saveCompanyBookingsListIndex,
 *     upsertCompanyBookingsListIndexBestEffort,
 *     removeCompanyBookingsListIndexBestEffort,
 *     rebuildCompanyBookingsListIndexForScope,
 *     rebuildDriverVehicleBookingIndexesForScope,
 *     _refreshBookingIndexesAfterFutureCompletedRepair — KV writers.
 *   - bookingListIndexItemFromRecord, _companyBookingsListShouldEmitRow —
 *     depend on booking-core (`_bookingListIsPaymentShadowRecord`,
 *     `_resolveCanonicalBookingIdFromShadow`, `_dashboardIdentityMeta`,
 *     `_normLifecycleStatus`, `_bookingLifecycleValue`,
 *     `bookingAssignedDriverId`, `bookingAssignedVehicleId`, `_pick`,
 *     `_dashboardBoolLike`, `_bookingIntentMask`).
 *   - _safeResetScopedBookingIndexKey — dev-reset domain.
 *   - _logCustomerBookingIndexUpsert — belongs next to its upsert writer.
 *   - COMPANY_BOOKINGS_LIST_INDEX_MAX_ITEMS — only used by the writer that
 *     stays in main.
 *
 * Acyclic import graph:
 *   parsing_utils.js ─►  booking_indexes.js
 * booking_indexes.js does NOT import back into main.
 *
 * `_toMsOrZero` and `_normalizeCustomerIdentityId` from main are needed by
 * some of the moved helpers. Rather than co-moving them (49 main call-sites
 * combined — out of BW-M7B scope), we keep private byte-identical duplicates
 * here under module-local names.
 */

import { sanitizeTenantString, safeStr } from "./parsing_utils.js";

/* ---- Private, byte-identical duplicates of main pure helpers --------
 * Behavior-identical to `_toMsOrZero` and `_normalizeCustomerIdentityId` in
 * fluxidi_booking_worker.js, kept private here to avoid touching the ~49
 * combined call-sites in main (out of BW-M7B scope). */

function _indexTimestampMs(value) {
  const ms = Date.parse(safeStr(value, 80));
  return Number.isFinite(ms) ? ms : 0;
}

function _indexNormalizeCustomerId(value) {
  return sanitizeTenantString(value, 160).replace(/[^a-zA-Z0-9._-]+/g, "");
}

/* ---- Key builders ---------------------------------------------------- */

export function customerScopedBookingsIndexKey(tenantId, companyId, customerId) {
  const tenant = sanitizeTenantString(tenantId, 80);
  const company = sanitizeTenantString(companyId, 80);
  const customer = _indexNormalizeCustomerId(customerId);
  if (!tenant || !company || !customer) return "";
  return `tenant:${tenant}:company:${company}:customer:${customer}:bookings:v1`;
}

export function driverScopedBookingsIndexKey(scope, driverId) {
  const tenant = sanitizeTenantString(scope?.tenant_id ?? scope?.tenantId, 80);
  const company = sanitizeTenantString(scope?.company_id ?? scope?.companyId, 80);
  const driver = sanitizeTenantString(driverId, 96);
  if (!tenant || !company || !driver) return "";
  return `tenant:${tenant}:company:${company}:driver:${driver}:bookings:v1`;
}

export function vehicleScopedBookingsIndexKey(scope, vehicleId) {
  const tenant = sanitizeTenantString(scope?.tenant_id ?? scope?.tenantId, 80);
  const company = sanitizeTenantString(scope?.company_id ?? scope?.companyId, 80);
  const vehicle = sanitizeTenantString(vehicleId, 128);
  if (!tenant || !company || !vehicle) return "";
  return `tenant:${tenant}:company:${company}:vehicle:${vehicle}:bookings:v1`;
}

export function companyBookingsListIndexKey(scope) {
  const tenant = sanitizeTenantString(scope?.tenant_id ?? scope?.tenantId, 80);
  const company = sanitizeTenantString(scope?.company_id ?? scope?.companyId, 80);
  if (!tenant || !company) return "";
  return `tenant:${tenant}:company:${company}:bookings:list:v1`;
}

/* ---- Pure predicate --------------------------------------------------- */

export function _isScopedBookingIndexLikeKey(key) {
  return /:bookings:v1$/.test(String(key || ""));
}

/* ---- Pure projection helper ------------------------------------------ */

export function bookingAssignmentIndexItemFromRecord(bookingId, rec) {
  const safeBookingId = safeStr(bookingId, 160);
  if (!safeBookingId || !rec || typeof rec !== "object") return null;
  const createdAt = safeStr(
    rec?.created_at ?? rec?.createdAt ?? rec?.booking?.created_at ?? rec?.booking?.createdAt,
    80,
  );
  const updatedAt = safeStr(
    rec?.updated_at ?? rec?.updatedAt ?? rec?.booking?.updated_at ?? rec?.booking?.updatedAt,
    80,
  ) || new Date().toISOString();
  const pickupIso = safeStr(
    rec?.booking?.pickup_iso ??
      rec?.booking?.pickupStartIso ??
      rec?.quote?.pickup_iso ??
      rec?.pickup_iso,
    80,
  );
  const sortTs = Math.max(
    _indexTimestampMs(pickupIso),
    _indexTimestampMs(updatedAt),
    _indexTimestampMs(createdAt),
    Date.now(),
  );
  return {
    booking_id: safeBookingId,
    sort_ts: sortTs,
    pickup_iso: pickupIso,
    updated_at: updatedAt,
  };
}

/* ---- Read-only KV loaders -------------------------------------------- */

export async function readScopedAssignmentBookingIndex(env, key) {
  if (!env?.BOOKING_KV || !safeStr(key, 260)) {
    return { ok: false, key: safeStr(key, 260), index: null, exists: false, valid: false };
  }
  try {
    const raw = await env.BOOKING_KV.get(key, { type: "json" });
    const rawObject = raw && typeof raw === "object" && !Array.isArray(raw) ? raw : null;
    const source = rawObject || {};
    const incomingItems = Array.isArray(source.items) ? source.items : [];
    const items = incomingItems
      .map((entry) => {
        const item = entry && typeof entry === "object" ? entry : {};
        const bookingId = safeStr(item?.booking_id ?? item?.bookingId, 160);
        if (!bookingId) return null;
        const sortTsRaw = Number(item?.sort_ts ?? item?.sortTs);
        return {
          booking_id: bookingId,
          sort_ts: Number.isFinite(sortTsRaw) ? Math.max(0, Math.trunc(sortTsRaw)) : 0,
          pickup_iso: safeStr(item?.pickup_iso ?? item?.pickupIso, 80),
          updated_at: safeStr(item?.updated_at ?? item?.updatedAt, 80),
        };
      })
      .filter((entry) => !!entry);
    return {
      ok: true,
      key,
      exists: !!rawObject,
      valid: !rawObject || Array.isArray(rawObject?.items),
      index: {
        version: 1,
        updated_at: safeStr(source?.updated_at ?? source?.updatedAt, 80),
        items,
      },
    };
  } catch (_) {
    return { ok: false, key, index: null, exists: false, valid: false };
  }
}

export async function readCustomerScopedBookingIndex(env, scope) {
  if (!env?.BOOKING_KV) return { ok: false, key: "", index: null };
  const tenantId = sanitizeTenantString(scope?.tenant_id ?? scope?.tenantId, 80);
  const companyId = sanitizeTenantString(scope?.company_id ?? scope?.companyId, 80);
  const customerId = _indexNormalizeCustomerId(scope?.customer_id ?? scope?.customerId);
  const key = customerScopedBookingsIndexKey(tenantId, companyId, customerId);
  if (!key) return { ok: false, key: "", index: null };
  const raw = await env.BOOKING_KV.get(key, { type: "json" });
  const source = raw && typeof raw === "object" && !Array.isArray(raw) ? raw : {};
  const incomingItems = Array.isArray(source.items) ? source.items : [];
  const items = incomingItems
    .map((entry) => {
      const item = entry && typeof entry === "object" ? entry : {};
      const bookingId = safeStr(item.booking_id ?? item.bookingId, 160);
      if (!bookingId) return null;
      const sortTsRaw = Number(item.sort_ts ?? item.sortTs);
      const sortTs = Number.isFinite(sortTsRaw) ? Math.max(0, Math.trunc(sortTsRaw)) : 0;
      return {
        booking_id: bookingId,
        sort_ts: sortTs,
        created_at: safeStr(item.created_at ?? item.createdAt, 80),
        updated_at: safeStr(item.updated_at ?? item.updatedAt, 80),
        pickup_iso: safeStr(item.pickup_iso ?? item.pickupIso, 80),
        public_booking_reference: safeStr(
          item.public_booking_reference ?? item.publicBookingReference,
          120,
        ),
        planning_reference: safeStr(item.planning_reference ?? item.planningReference, 120),
      };
    })
    .filter((entry) => !!entry);
  return {
    ok: true,
    key,
    index: {
      version: 1,
      tenant_id: tenantId,
      company_id: companyId,
      customer_id: customerId,
      updated_at: safeStr(source.updated_at ?? source.updatedAt, 80),
      items,
    },
  };
}

export async function readCompanyBookingsListIndex(env, scope) {
  const key = companyBookingsListIndexKey(scope);
  if (!key || !env?.BOOKING_KV) return { ok: false, key, index: null, exists: false, valid: false };
  try {
    const raw = await env.BOOKING_KV.get(key, { type: "json" });
    const rawObject = raw && typeof raw === "object" && !Array.isArray(raw) ? raw : null;
    const source = rawObject || {};
    const rawItems = Array.isArray(source?.items) ? source.items : [];
    const items = rawItems
      .map((entry) => (entry && typeof entry === "object" ? entry : null))
      .filter((entry) => !!safeStr(entry?.booking_id ?? entry?.bookingId, 160))
      .map((entry) => ({
        booking_id: safeStr(entry?.booking_id ?? entry?.bookingId, 160),
        sort_ts: Number.isFinite(Number(entry?.sort_ts ?? entry?.sortTs))
          ? Math.max(0, Math.trunc(Number(entry?.sort_ts ?? entry?.sortTs)))
          : 0,
        pickup_iso: safeStr(entry?.pickup_iso ?? entry?.pickupIso, 80),
        updated_at: safeStr(entry?.updated_at ?? entry?.updatedAt, 80),
        lifecycle: safeStr(entry?.lifecycle, 40),
        status: safeStr(entry?.status, 40),
        public_booking_reference: safeStr(
          entry?.public_booking_reference ?? entry?.publicBookingReference,
          120,
        ),
        planning_reference: safeStr(entry?.planning_reference ?? entry?.planningReference, 120),
        assigned_driver_id: safeStr(entry?.assigned_driver_id ?? entry?.assignedDriverId, 96),
        assigned_vehicle_id: safeStr(entry?.assigned_vehicle_id ?? entry?.assignedVehicleId, 128),
      }));
    return {
      ok: true,
      key,
      exists: !!rawObject,
      valid: !rawObject || Array.isArray(rawObject?.items),
      index: {
        version: 1,
        updated_at: safeStr(source?.updated_at ?? source?.updatedAt, 80),
        items,
      },
    };
  } catch (_) {
    return { ok: false, key, index: null, exists: false, valid: false };
  }
}

/* ---- Env-flag reader -------------------------------------------------- */

export function _companyBookingsListIndexStaleAfterMs(env, options = {}) {
  const raw = Number(
    options?.staleAfterMs ??
      env?.COMPANY_BOOKINGS_LIST_INDEX_STALE_AFTER_MS ??
      0,
  );
  if (!Number.isFinite(raw)) return 0;
  const normalized = Math.trunc(raw);
  return normalized > 0 ? normalized : 0;
}
