/* Fluxidi booking / driver-vehicle / company index surface (BW-M7B + BW-M11).
 *
 * Verbatim extraction from workers/booking/fluxidi_booking_worker.js — no
 * behavior change. This module owns the *complete* booking-index surface:
 *
 *   BW-M7B (readers + key builders):
 *     - customer/driver/vehicle scoped booking-index KV key builders,
 *     - company bookings-list index KV key builder,
 *     - pure booking-assignment index-item projection,
 *     - read-only KV loaders for the four booking-index shapes above,
 *     - pure "is scoped-booking-index-like key?" regex predicate,
 *     - pure `COMPANY_BOOKINGS_LIST_INDEX_STALE_AFTER_MS` env-flag reader.
 *
 *   BW-M11 (index writers + rebuilders):
 *     - COMPANY_BOOKINGS_LIST_INDEX_MAX_ITEMS,
 *     - bookingListIndexItemFromRecord (projection for company list index),
 *     - upsertCustomerScopedBookingIndexForBooking,
 *     - saveScopedAssignmentBookingIndex,
 *     - upsertDriverVehicleBookingIndexesBestEffort,
 *     - removeDriverVehicleBookingIndexesBestEffort,
 *     - saveCompanyBookingsListIndex,
 *     - upsertCompanyBookingsListIndexBestEffort,
 *     - removeCompanyBookingsListIndexBestEffort,
 *     - rebuildCompanyBookingsListIndexForScope,
 *     - rebuildDriverVehicleBookingIndexesForScope.
 *
 * Explicitly NOT moved (STOP rule — orchestrators, mutation flows, or
 * dev-reset):
 *   - listDriverBookingsAuthoritative,
 *     listAdminDriverBookingsPreviewAuthoritative,
 *     hydrateCustomerBookingsFromScopedIndex — orchestrators.
 *   - _refreshBookingIndexesAfterFutureCompletedRepair — booking-mutation
 *     helper that both reads the record and repairs it in place.
 *   - _safeResetScopedBookingIndexKey — dev-reset domain.
 *   - _logCustomerBookingIndexUpsert — logging helper next to a caller in
 *     main.
 *   - Booking create/update/status/payment mutations, dispatch allocator,
 *     driver list/preview orchestrators, document/Billit/Peppol/Chiron,
 *     dev-reset — not in scope; untouched.
 *
 * Behavior guarantees preserved (BW-M11):
 *   - key formats identical (byte-for-byte), item shapes identical,
 *     sort order identical, item-cap trimming identical (250 / 2000),
 *     idempotency and try/catch/best-effort semantics unchanged.
 *
 * Acyclic import graph:
 *   parsing_utils.js       ─►  booking_indexes.js
 *   auth_scope.js          ─►  booking_indexes.js
 *   booking_utils.js       ─►  booking_indexes.js
 *   booking_identity.js    ─►  booking_indexes.js
 *   booking_read_model.js  ─►  booking_indexes.js
 *   booking_indexes.js does NOT import back into main and does NOT import
 *   from dispatch_open_pool.js or driver_ops.js.
 *
 * Private byte-identical duplicates from main (widely used elsewhere; not
 * co-moved to keep BW-M11 touch-set minimal). Each private helper is
 * behavior-identical to its main counterpart and carries the `_index`
 * prefix to make its module-local status obvious:
 *   - _indexTimestampMs                  ≡ _toMsOrZero (main)
 *   - _indexNormalizeCustomerId          ≡ _normalizeCustomerIdentityId (main)
 *   - _indexBookingMutationReadPath      ≡ _bookingMutationReadPath (main)
 *   - _indexBookingAssignedDriverId      ≡ bookingAssignedDriverId (main)
 *   - _indexBookingAssignedVehicleId     ≡ bookingAssignedVehicleId (main)
 *   - _indexBookingLifecycleValue        ≡ _bookingLifecycleValue (main)
 *   - _indexBookingIntentScopeMask       ≡ _bookingIntentScopeMask (main)
 *   - _indexNormalizeFleetTenantScope    ≡ normalizeFleetTenantScope (main)
 *   - _indexCustomerBookingIdsFromRecord ≡ _customerBookingIdsFromRecord (main)
 *   - _indexParseDurationMin             ≡ parseDurationMin (main)
 *   - _indexNormalizeService             ≡ normalizeService (main)
 *   - _indexShouldSplitOperationalReturnLeg ≡ _shouldSplitOperationalReturnLeg (main)
 *   - _indexRoundtripDispatchContextFromAny ≡ _roundtripDispatchContextFromAny (main)
 *   - _indexIsSplitRoundtripWithoutWaiting ≡ isSplitRoundtripWithoutWaiting (main)
 *   - _indexIsContinuousWaitRoundtrip    ≡ isContinuousWaitRoundtrip (main)
 *   - _indexResolveRoundtripDispatchMode ≡ resolveRoundtripDispatchMode (main)
 */

import { sanitizeTenantString, safeStr } from "./parsing_utils.js";
import { isAllocatorProbeRecord } from "./human_booking_id_allocator.mjs";
import {
  _scopeText,
  resolveBookingTenantScopeFromRecord,
  bookingMatchesRequiredTenantCompanyScope,
} from "./auth_scope.js";
import {
  _pick,
  _bookingIntentMask,
  _normLifecycleStatus,
} from "./booking_utils.js";
import {
  _bookingListIsPaymentShadowRecord,
  _resolveCanonicalBookingIdFromShadow,
  _dashboardBoolLike,
} from "./booking_identity.js";
import { _flattenBookingForRidesListWithOperationalLegs } from "./booking_read_model.js";

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

/* ========================================================================
 * BW-M11: Booking-index writers + rebuilders.
 * ======================================================================== */

/* ---- Additional private byte-identical duplicates from main ---------- */

// ≡ _bookingMutationReadPath (main). Reads first non-empty scalar reachable
// via any of the provided property paths, coerced via _scopeText.
function _indexBookingMutationReadPath(root, paths = []) {
  for (const path of paths) {
    let cursor = root;
    let ok = true;
    for (const key of path) {
      if (!cursor || typeof cursor !== "object" || !(key in cursor)) {
        ok = false;
        break;
      }
      cursor = cursor[key];
    }
    if (!ok) continue;
    const text = _scopeText(cursor, 128);
    if (text) return text;
  }
  return "";
}

// ≡ bookingAssignedVehicleId (main).
function _indexBookingAssignedVehicleId(rec) {
  return _indexBookingMutationReadPath(rec, [
    ["assigned_vehicle_id"],
    ["assignedVehicleId"],
    ["vehicle_id"],
    ["vehicleId"],
    ["booking", "assigned_vehicle_id"],
    ["booking", "assignedVehicleId"],
    ["booking", "vehicle_id"],
    ["booking", "vehicleId"],
    ["record", "booking", "assigned_vehicle_id"],
    ["record", "booking", "assignedVehicleId"],
    ["record", "booking", "vehicle_id"],
    ["record", "booking", "vehicleId"],
  ]);
}

// ≡ bookingAssignedDriverId (main).
function _indexBookingAssignedDriverId(rec) {
  return _indexBookingMutationReadPath(rec, [
    ["assigned_driver_id"],
    ["assignedDriverId"],
    ["assigned_driver", "driver_id"],
    ["assigned_driver", "driverId"],
    ["assigned_driver", "id"],
    ["assignedDriver", "driver_id"],
    ["assignedDriver", "driverId"],
    ["assignedDriver", "id"],
    ["driver_id"],
    ["driverId"],
    ["booking", "assigned_driver", "driver_id"],
    ["booking", "assigned_driver", "driverId"],
    ["booking", "assigned_driver", "id"],
    ["booking", "assignedDriver", "driver_id"],
    ["booking", "assignedDriver", "driverId"],
    ["booking", "assignedDriver", "id"],
    ["booking", "assigned_driver_id"],
    ["booking", "assignedDriverId"],
    ["booking", "driver_id"],
    ["booking", "driverId"],
    ["record", "booking", "assigned_driver", "driver_id"],
    ["record", "booking", "assigned_driver", "driverId"],
    ["record", "booking", "assigned_driver", "id"],
    ["record", "booking", "assignedDriver", "driver_id"],
    ["record", "booking", "assignedDriver", "driverId"],
    ["record", "booking", "assignedDriver", "id"],
    ["record", "booking", "assigned_driver_id"],
    ["record", "booking", "assignedDriverId"],
    ["record", "booking", "driver_id"],
    ["record", "booking", "driverId"],
  ]);
}

// ≡ _bookingLifecycleValue (main).
function _indexBookingLifecycleValue(rec) {
  return (
    rec?.status ??
    rec?.stage ??
    rec?.booking?.status ??
    rec?.booking?.stage ??
    null
  );
}

// ≡ _bookingIntentScopeMask (main).
function _indexBookingIntentScopeMask(scope = {}) {
  return {
    tenant: _bookingIntentMask(scope?.tenant_id),
    company: _bookingIntentMask(scope?.company_id),
  };
}

// ≡ normalizeFleetTenantScope (main).
function _indexNormalizeFleetTenantScope(scope) {
  const tenantIdRaw = _scopeText(scope?.tenant_id ?? scope?.tenantId);
  const companyIdRaw = _scopeText(scope?.company_id ?? scope?.companyId);
  const tenantId = tenantIdRaw || companyIdRaw || "";
  const companyId = companyIdRaw || tenantId || "";
  return {
    tenant_id: tenantId,
    company_id: companyId,
    hasScope: !!(tenantId || companyId),
  };
}

// ≡ _customerBookingIdsFromRecord (main).
function _indexCustomerBookingIdsFromRecord(rec) {
  const ids = new Set();
  const addId = (value) => {
    const normalized = _indexNormalizeCustomerId(value);
    if (normalized) ids.add(normalized);
  };
  addId(rec?.customer_id);
  addId(rec?.customerId);
  addId(rec?.customer?.customer_id);
  addId(rec?.customer?.customerId);
  addId(rec?.booking?.customer_id);
  addId(rec?.booking?.customerId);
  addId(rec?.booking?.customer?.customer_id);
  addId(rec?.booking?.customer?.customerId);
  return Array.from(ids);
}

// ≡ parseDurationMin (main).
function _indexParseDurationMin(x, fallback = 0) {
  if (x == null) return fallback;
  if (typeof x === "number" && Number.isFinite(x)) return Math.trunc(x);
  const s = String(x).trim();
  if (!s) return fallback;
  const m = s.match(/(\d+)/);
  if (!m) return fallback;
  const n = Number(m[1]);
  return Number.isFinite(n) ? Math.trunc(n) : fallback;
}

// ≡ normalizeService (main).
function _indexNormalizeService(svc) {
  const s = String(svc || "").trim().toLowerCase();
  if (s === "airport") return "airport";
  if (s === "business") return "business";
  if (s === "event") return "event";
  if (s === "special" || s === "speciale_gelegenheid") return "event";
  if (s === "wedding") return "event";
  if (s === "hourly") return "hourly";
  if (s === "care") return "care";
  if (s === "courier") return "courier";
  return "passenger";
}

// ≡ _shouldSplitOperationalReturnLeg (main).
function _indexShouldSplitOperationalReturnLeg({
  service,
  returnEnabled,
  hasReturnSchedule,
  waitMin,
} = {}) {
  if (!returnEnabled) return false;
  const normalizedWaitMin = Math.max(0, Number(waitMin) || 0);
  if (normalizedWaitMin > 0) return false;
  // Split only when a real return leg exists (scheduled return pickup).
  // Airport one-way (returnEnabled false) and any booking without return
  // schedule stay non-split regardless of service type.
  return !!hasReturnSchedule;
}

// ≡ _roundtripDispatchContextFromAny (main).
function _indexRoundtripDispatchContextFromAny(source) {
  const rec = source && typeof source === "object" ? source : {};
  const bookingObj = rec?.booking && typeof rec.booking === "object" ? rec.booking : {};
  const payloadObj = rec?.payload && typeof rec.payload === "object" ? rec.payload : {};
  const quoteObj = rec?.quote && typeof rec.quote === "object" ? rec.quote : {};
  const returnEnabled = !!(
    rec?.return_enabled ??
      rec?.returnEnabled ??
      bookingObj?.return_enabled ??
      bookingObj?.returnEnabled ??
      payloadObj?.return_enabled ??
      payloadObj?.return ??
      quoteObj?.return?.enabled ??
      false
  );
  const hasReturnSchedule = !!safeStr(
    rec?.return_pickup_iso ??
      rec?.returnPickupIso ??
      bookingObj?.return_pickup_iso ??
      bookingObj?.returnPickupIso ??
      payloadObj?.return_pickup_iso ??
      payloadObj?.returnPickupIso ??
      quoteObj?.return?.pickup_iso,
    80,
  );
  const waitMin = _indexParseDurationMin(
    rec?.wait_min ??
      rec?.waitMin ??
      bookingObj?.wait_min ??
      bookingObj?.waitMin ??
      payloadObj?.wait_min ??
      payloadObj?.waitMin ??
      payloadObj?.wait_minutes ??
      payloadObj?.waiting_min ??
      quoteObj?.wait_min,
    0,
  );
  const service = _indexNormalizeService(
    rec?.service ??
      bookingObj?.service ??
      payloadObj?.service ??
      "passenger",
  );
  return {
    service,
    returnEnabled,
    hasReturnSchedule,
    waitMin,
    normalizedWaitMin: Math.max(0, Number(waitMin) || 0),
  };
}

// ≡ isSplitRoundtripWithoutWaiting (main).
function _indexIsSplitRoundtripWithoutWaiting(source) {
  const ctx = _indexRoundtripDispatchContextFromAny(source);
  return _indexShouldSplitOperationalReturnLeg(ctx);
}

// ≡ isContinuousWaitRoundtrip (main).
function _indexIsContinuousWaitRoundtrip(source) {
  const ctx = _indexRoundtripDispatchContextFromAny(source);
  if (!ctx.returnEnabled) return false;
  if (_indexIsSplitRoundtripWithoutWaiting(source)) return false;
  return ctx.normalizedWaitMin > 0;
}

// ≡ resolveRoundtripDispatchMode (main).
function _indexResolveRoundtripDispatchMode(source) {
  if (_indexIsSplitRoundtripWithoutWaiting(source)) return "split_no_wait";
  if (_indexIsContinuousWaitRoundtrip(source)) return "continuous_wait";
  return "single";
}

/* ---- Constants ------------------------------------------------------- */

export const COMPANY_BOOKINGS_LIST_INDEX_MAX_ITEMS = 2000;

/* ---- Company bookings-list index item projection --------------------- */

export function bookingListIndexItemFromRecord(bookingId, rec) {
  const safeBookingId = safeStr(bookingId, 160);
  if (!safeBookingId || !rec || typeof rec !== "object") return null;
  if (_bookingListIsPaymentShadowRecord(rec, safeBookingId)) {
    const canonical = _resolveCanonicalBookingIdFromShadow(rec, safeBookingId);
    if (!canonical) {
      return null;
    }
    // Never index the payment-shadow KV key; canonical booking upserts separately.
    return null;
  }
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
  if (hiddenFlags.some((value) => _dashboardBoolLike(value))) return null;
  const bookingObj = rec?.booking && typeof rec.booking === "object" ? rec.booking : {};
  const createdAt = safeStr(
    rec?.created_at ?? rec?.createdAt ?? bookingObj?.created_at ?? bookingObj?.createdAt,
    80,
  );
  const updatedAt = safeStr(
    rec?.updated_at ?? rec?.updatedAt ?? bookingObj?.updated_at ?? bookingObj?.updatedAt,
    80,
  ) || new Date().toISOString();
  const pickupIso = safeStr(
    bookingObj?.pickupStartIso ??
      bookingObj?.pickup_iso ??
      rec?.pickup_iso ??
      rec?.pickupIso ??
      rec?.quote?.pickup_iso,
    80,
  );
  const sortTs = Math.max(
    _indexTimestampMs(pickupIso),
    _indexTimestampMs(updatedAt),
    _indexTimestampMs(createdAt),
    Date.now(),
  );
  const lifecycleRaw = _normLifecycleStatus(_indexBookingLifecycleValue(rec));
  const lifecycle = safeStr(lifecycleRaw, 40).toLowerCase() || "pending";
  const status = safeStr(
    rec?.status ?? rec?.stage ?? bookingObj?.status ?? bookingObj?.stage,
    40,
  ) || (lifecycleRaw || "PENDING");
  const publicBookingReference = safeStr(
    rec?.public_booking_reference ??
      rec?.publicBookingReference ??
      rec?.booking_reference ??
      rec?.bookingReference ??
      bookingObj?.public_booking_reference ??
      bookingObj?.publicBookingReference ??
      bookingObj?.booking_reference ??
      bookingObj?.bookingReference,
    120,
  );
  const planningReference = safeStr(
    rec?.planning_reference ??
      rec?.planningReference ??
      bookingObj?.planning_reference ??
      bookingObj?.planningReference,
    120,
  );
  const assignedDriverId = safeStr(_indexBookingAssignedDriverId(rec), 96);
  const assignedVehicleId = safeStr(_indexBookingAssignedVehicleId(rec), 128);
  return {
    booking_id: safeBookingId,
    sort_ts: sortTs,
    pickup_iso: pickupIso,
    updated_at: updatedAt,
    lifecycle,
    status,
    public_booking_reference: publicBookingReference || null,
    planning_reference: planningReference || null,
    assigned_driver_id: assignedDriverId || null,
    assigned_vehicle_id: assignedVehicleId || null,
  };
}

/* ---- Customer-scoped bookings index writer --------------------------- */

export async function upsertCustomerScopedBookingIndexForBooking(env, bookingId, rec) {
  if (!env?.BOOKING_KV) return { ok: false, reason: "missing_kv" };
  if (isAllocatorProbeRecord(rec)) {
    return { ok: true, skipped: true, reason: "allocator_probe" };
  }
  const recordScope = resolveBookingTenantScopeFromRecord(rec);
  const tenantId = sanitizeTenantString(recordScope?.tenant_id, 80);
  const companyId = sanitizeTenantString(recordScope?.company_id, 80);
  const bookingCustomerIds = _indexCustomerBookingIdsFromRecord(rec);
  const customerId = bookingCustomerIds[0] || "";
  if (!tenantId || !companyId || !customerId) {
    return { ok: false, skipped: true, reason: "missing_scope_or_customer_id" };
  }
  const key = customerScopedBookingsIndexKey(tenantId, companyId, customerId);
  if (!key) return { ok: false, skipped: true, reason: "index_key_invalid" };
  const raw = await env.BOOKING_KV.get(key, { type: "json" });
  const source = raw && typeof raw === "object" && !Array.isArray(raw) ? raw : {};
  const nowIso = new Date().toISOString();
  const createdAt = safeStr(
    rec?.created_at ?? rec?.createdAt ?? rec?.booking?.created_at ?? rec?.booking?.createdAt,
    80,
  );
  const updatedAt = safeStr(
    rec?.updated_at ?? rec?.updatedAt ?? rec?.booking?.updated_at ?? rec?.booking?.updatedAt,
    80,
  ) || nowIso;
  const pickupIso = safeStr(
    rec?.booking?.pickup_iso ?? rec?.booking?.pickupStartIso ?? rec?.quote?.pickup_iso,
    80,
  );
  const publicBookingReference = safeStr(
    rec?.public_booking_reference ??
      rec?.publicBookingReference ??
      rec?.booking_reference ??
      rec?.bookingReference ??
      rec?.booking?.public_booking_reference ??
      rec?.booking?.publicBookingReference ??
      rec?.booking?.booking_reference ??
      rec?.booking?.bookingReference,
    120,
  );
  const planningReference = safeStr(
    rec?.planning_reference ??
      rec?.planningReference ??
      rec?.booking?.planning_reference ??
      rec?.booking?.planningReference,
    120,
  );
  const sortTs = Math.max(
    _indexTimestampMs(pickupIso),
    _indexTimestampMs(updatedAt),
    _indexTimestampMs(createdAt),
    Date.now(),
  );
  const incoming = {
    booking_id: safeStr(bookingId, 160),
    sort_ts: sortTs,
    created_at: createdAt,
    updated_at: updatedAt,
    pickup_iso: pickupIso,
    public_booking_reference: publicBookingReference,
    planning_reference: planningReference,
  };
  const existingItems = Array.isArray(source.items) ? source.items : [];
  const deduped = existingItems
    .map((entry) => (entry && typeof entry === "object" ? entry : null))
    .filter((entry) => !!safeStr(entry?.booking_id ?? entry?.bookingId, 160))
    .filter((entry) => safeStr(entry?.booking_id ?? entry?.bookingId, 160) !== incoming.booking_id);
  deduped.push(incoming);
  deduped.sort((a, b) => Number(b?.sort_ts || b?.sortTs || 0) - Number(a?.sort_ts || a?.sortTs || 0));
  const capped = deduped.slice(0, 250);
  await env.BOOKING_KV.put(
    key,
    JSON.stringify({
      version: 1,
      tenant_id: tenantId,
      company_id: companyId,
      customer_id: customerId,
      updated_at: nowIso,
      items: capped.map((entry) => ({
        booking_id: safeStr(entry?.booking_id ?? entry?.bookingId, 160),
        sort_ts: Number.isFinite(Number(entry?.sort_ts ?? entry?.sortTs))
          ? Math.max(0, Math.trunc(Number(entry?.sort_ts ?? entry?.sortTs)))
          : 0,
        created_at: safeStr(entry?.created_at ?? entry?.createdAt, 80),
        updated_at: safeStr(entry?.updated_at ?? entry?.updatedAt, 80),
        pickup_iso: safeStr(entry?.pickup_iso ?? entry?.pickupIso, 80),
        public_booking_reference: safeStr(
          entry?.public_booking_reference ?? entry?.publicBookingReference,
          120,
        ),
        planning_reference: safeStr(entry?.planning_reference ?? entry?.planningReference, 120),
      })),
    }),
  );
  return { ok: true, key, count: capped.length };
}

/* ---- Driver/vehicle scoped assignment index writers ------------------ */

export async function saveScopedAssignmentBookingIndex(env, key, indexObj) {
  if (!env?.BOOKING_KV || !safeStr(key, 260)) return { ok: false, key };
  const rawItems = Array.isArray(indexObj?.items) ? indexObj.items : [];
  const deduped = rawItems
    .map((entry) => (entry && typeof entry === "object" ? entry : null))
    .filter((entry) => !!safeStr(entry?.booking_id ?? entry?.bookingId, 160))
    .map((entry) => ({
      booking_id: safeStr(entry?.booking_id ?? entry?.bookingId, 160),
      sort_ts: Number.isFinite(Number(entry?.sort_ts ?? entry?.sortTs))
        ? Math.max(0, Math.trunc(Number(entry?.sort_ts ?? entry?.sortTs)))
        : 0,
      pickup_iso: safeStr(entry?.pickup_iso ?? entry?.pickupIso, 80),
      updated_at: safeStr(entry?.updated_at ?? entry?.updatedAt, 80),
    }));
  const byId = new Map();
  for (const item of deduped) byId.set(item.booking_id, item);
  const cappedItems = Array.from(byId.values())
    .sort((a, b) => Number(b?.sort_ts || 0) - Number(a?.sort_ts || 0))
    .slice(0, 250);
  const payload = {
    version: 1,
    updated_at: new Date().toISOString(),
    items: cappedItems,
  };
  await env.BOOKING_KV.put(key, JSON.stringify(payload));
  return { ok: true, key, count: cappedItems.length };
}

export async function upsertDriverVehicleBookingIndexesBestEffort(env, bookingId, rec, scopeHint = null) {
  try {
    if (!env?.BOOKING_KV) return { ok: false, reason: "missing_kv" };
    if (isAllocatorProbeRecord(rec)) {
      return { ok: true, skipped: true, reason: "allocator_probe" };
    }
    const fallbackScope = resolveBookingTenantScopeFromRecord(rec);
    const scope = _indexNormalizeFleetTenantScope(scopeHint?.hasScope ? scopeHint : fallbackScope);
    if (!scope?.hasScope) return { ok: false, skipped: true, reason: "missing_scope" };
    const safeBookingId = safeStr(bookingId, 160);
    const item = bookingAssignmentIndexItemFromRecord(safeBookingId, rec);
    if (!item) return { ok: false, skipped: true, reason: "invalid_item" };

    const indexTargets = [];
    if (_indexResolveRoundtripDispatchMode(rec) === "split_no_wait") {
      const rows = _flattenBookingForRidesListWithOperationalLegs(safeBookingId, rec);
      const seenDrivers = new Set();
      const seenVehicles = new Set();
      for (const row of rows) {
        const rowDriverId = safeStr(row?.assigned_driver_id ?? row?.assignedDriverId, 96);
        const rowVehicleId = safeStr(row?.assigned_vehicle_id ?? row?.assignedVehicleId, 128);
        if (rowDriverId && !seenDrivers.has(rowDriverId)) {
          seenDrivers.add(rowDriverId);
          indexTargets.push({ kind: "driver", id: rowDriverId });
        }
        if (rowVehicleId && !seenVehicles.has(rowVehicleId)) {
          seenVehicles.add(rowVehicleId);
          indexTargets.push({ kind: "vehicle", id: rowVehicleId });
        }
      }
    } else {
      const assignedDriverId = _indexBookingAssignedDriverId(rec);
      const assignedVehicleId = _indexBookingAssignedVehicleId(rec);
      if (assignedDriverId) indexTargets.push({ kind: "driver", id: assignedDriverId });
      if (assignedVehicleId) indexTargets.push({ kind: "vehicle", id: assignedVehicleId });
    }

    const keys = [];
    for (const target of indexTargets) {
      const key =
        target.kind === "driver"
          ? driverScopedBookingsIndexKey(scope, target.id)
          : vehicleScopedBookingsIndexKey(scope, target.id);
      if (key) keys.push(key);
    }
    if (!keys.length) return { ok: false, skipped: true, reason: "missing_assignment" };
    for (const key of keys) {
      const read = await readScopedAssignmentBookingIndex(env, key);
      const sourceItems = Array.isArray(read?.index?.items) ? read.index.items : [];
      const next = sourceItems.filter(
        (entry) => safeStr(entry?.booking_id ?? entry?.bookingId, 160) !== item.booking_id,
      );
      next.push(item);
      await saveScopedAssignmentBookingIndex(env, key, { items: next });
    }
    const scopeMask = _indexBookingIntentScopeMask(scope);
    console.info({
      event: "driver_vehicle_booking_index_upsert",
      booking_id_preview: _bookingIntentMask(bookingId),
      tenant: scopeMask.tenant || "-",
      company: scopeMask.company || "-",
      driver_assigned: indexTargets.some((target) => target.kind === "driver"),
      vehicle_assigned: indexTargets.some((target) => target.kind === "vehicle"),
      split_no_wait: _indexResolveRoundtripDispatchMode(rec) === "split_no_wait",
      ok: true,
    });
    return {
      ok: true,
      driver_indexed: indexTargets.some((target) => target.kind === "driver"),
      vehicle_indexed: indexTargets.some((target) => target.kind === "vehicle"),
    };
  } catch (err) {
    const scopeMask = _indexBookingIntentScopeMask(scopeHint || {});
    console.warn({
      event: "driver_vehicle_booking_index_upsert",
      booking_id_preview: _bookingIntentMask(bookingId),
      tenant: scopeMask.tenant || "-",
      company: scopeMask.company || "-",
      ok: false,
      reason: safeStr(err?.message || err, 140) || "unknown",
    });
    return { ok: false, reason: "exception" };
  }
}

export async function removeDriverVehicleBookingIndexesBestEffort(env, bookingId, recOrScopeHint = null) {
  try {
    if (!env?.BOOKING_KV) return { ok: false, reason: "missing_kv" };
    const safeBookingId = safeStr(bookingId, 160);
    if (!safeBookingId) return { ok: false, skipped: true, reason: "missing_booking_id" };
    const rec = recOrScopeHint && typeof recOrScopeHint === "object" ? recOrScopeHint : null;
    const scope = _indexNormalizeFleetTenantScope(
      rec?.hasScope
        ? rec
        : (rec ? resolveBookingTenantScopeFromRecord(rec) : recOrScopeHint),
    );
    if (!scope?.hasScope) return { ok: false, skipped: true, reason: "missing_scope" };
    const assignedDriverId = safeStr(
      rec?.assigned_driver_id ??
        rec?.assignedDriverId ??
        (rec ? _indexBookingAssignedDriverId(rec) : ""),
      96,
    );
    const assignedVehicleId = safeStr(
      rec?.assigned_vehicle_id ??
        rec?.assignedVehicleId ??
        rec?.vehicle_id ??
        rec?.vehicleId ??
        (rec ? _indexBookingAssignedVehicleId(rec) : ""),
      128,
    );
    const keys = [];
    const driverKey = driverScopedBookingsIndexKey(scope, assignedDriverId);
    const vehicleKey = vehicleScopedBookingsIndexKey(scope, assignedVehicleId);
    if (driverKey) keys.push(driverKey);
    if (vehicleKey) keys.push(vehicleKey);
    if (!keys.length) return { ok: false, skipped: true, reason: "missing_assignment" };
    for (const key of keys) {
      const read = await readScopedAssignmentBookingIndex(env, key);
      if (!read?.ok || !read?.index) continue;
      const sourceItems = Array.isArray(read.index.items) ? read.index.items : [];
      const next = sourceItems.filter(
        (entry) => safeStr(entry?.booking_id ?? entry?.bookingId, 160) !== safeBookingId,
      );
      if (next.length === sourceItems.length) continue;
      await saveScopedAssignmentBookingIndex(env, key, { items: next });
    }
    return { ok: true };
  } catch (_) {
    return { ok: false, reason: "exception" };
  }
}

/* ---- Company bookings-list index writers ----------------------------- */

export async function saveCompanyBookingsListIndex(env, scope, indexObj) {
  const key = companyBookingsListIndexKey(scope);
  if (!key || !env?.BOOKING_KV) return { ok: false, key };
  const rawItems = Array.isArray(indexObj?.items) ? indexObj.items : [];
  const normalized = rawItems
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
  const dedup = new Map();
  for (const item of normalized) dedup.set(item.booking_id, item);
  const cappedItems = Array.from(dedup.values())
    .sort((a, b) => Number(b?.sort_ts || 0) - Number(a?.sort_ts || 0))
    .slice(0, COMPANY_BOOKINGS_LIST_INDEX_MAX_ITEMS);
  await env.BOOKING_KV.put(
    key,
    JSON.stringify({
      version: 1,
      updated_at: new Date().toISOString(),
      items: cappedItems,
    }),
  );
  return { ok: true, key, count: cappedItems.length };
}

let _listProjectionMutator = null;

export function setBookingListProjectionMutator(fn) {
  _listProjectionMutator = typeof fn === "function" ? fn : null;
}

async function _notifyListProjection(payload) {
  if (typeof _listProjectionMutator !== "function") return;
  try {
    await _listProjectionMutator(payload);
  } catch (_) {
    // Projection maintenance must never fail the authoritative index write.
  }
}

export async function upsertCompanyBookingsListIndexBestEffort(env, bookingId, rec, scopeHint = null) {
  try {
    if (!env?.BOOKING_KV) return { ok: false, reason: "missing_kv" };
    if (isAllocatorProbeRecord(rec)) {
      return { ok: true, skipped: true, reason: "allocator_probe" };
    }
    const recordScope = resolveBookingTenantScopeFromRecord(rec);
    const scope = _indexNormalizeFleetTenantScope(scopeHint?.hasScope ? scopeHint : recordScope);
    if (!scope?.hasScope) return { ok: false, skipped: true, reason: "missing_scope" };
    const item = bookingListIndexItemFromRecord(bookingId, rec);
    if (!item) {
      await _notifyListProjection({
        env,
        bookingId,
        rec,
        scopeHint: scope,
        removed: true,
      });
      return { ok: false, skipped: true, reason: "invalid_item" };
    }
    const read = await readCompanyBookingsListIndex(env, scope);
    const sourceItems = Array.isArray(read?.index?.items) ? read.index.items : [];
    const next = sourceItems.filter(
      (entry) => safeStr(entry?.booking_id ?? entry?.bookingId, 160) !== item.booking_id,
    );
    next.push(item);
    const saved = await saveCompanyBookingsListIndex(env, scope, { items: next });
    await _notifyListProjection({
      env,
      bookingId,
      rec,
      scopeHint: scope,
      removed: false,
    });
    return { ok: true, count: Number(saved?.count || 0), key: saved?.key };
  } catch (_) {
    return { ok: false, reason: "exception" };
  }
}

export async function removeCompanyBookingsListIndexBestEffort(env, bookingId, recOrScopeHint = null) {
  try {
    if (!env?.BOOKING_KV) return { ok: false, reason: "missing_kv" };
    const safeBookingId = safeStr(bookingId, 160);
    if (!safeBookingId) return { ok: false, skipped: true, reason: "missing_booking_id" };
    const rec = recOrScopeHint && typeof recOrScopeHint === "object" ? recOrScopeHint : null;
    const scope = _indexNormalizeFleetTenantScope(
      rec?.hasScope
        ? rec
        : (rec ? resolveBookingTenantScopeFromRecord(rec) : recOrScopeHint),
    );
    if (!scope?.hasScope) return { ok: false, skipped: true, reason: "missing_scope" };
    const read = await readCompanyBookingsListIndex(env, scope);
    if (!read?.ok || !read?.index) return { ok: true, skipped: true, reason: "index_missing" };
    const sourceItems = Array.isArray(read.index.items) ? read.index.items : [];
    const next = sourceItems.filter(
      (entry) => safeStr(entry?.booking_id ?? entry?.bookingId, 160) !== safeBookingId,
    );
    if (next.length === sourceItems.length) {
      await _notifyListProjection({
        env,
        bookingId: safeBookingId,
        rec,
        scopeHint: scope,
        removed: true,
      });
      return { ok: true, skipped: true, reason: "not_found" };
    }
    const saved = await saveCompanyBookingsListIndex(env, scope, { items: next });
    await _notifyListProjection({
      env,
      bookingId: safeBookingId,
      rec,
      scopeHint: scope,
      removed: true,
    });
    return { ok: true, count: Number(saved?.count || 0), key: saved?.key };
  } catch (_) {
    return { ok: false, reason: "exception" };
  }
}

/* ---- Rebuilders (KV list scans, index-only writes) ------------------- */

export async function rebuildCompanyBookingsListIndexForScope(env, scope, { dryRun = false } = {}) {
  const normalizedScope = _indexNormalizeFleetTenantScope(scope || {});
  if (!normalizedScope?.hasScope) {
    return { ok: false, error: "missing_tenant_scope" };
  }
  if (!env?.BOOKING_KV) {
    return { ok: false, error: "Missing BOOKING_KV binding" };
  }
  let scanned = 0;
  let matchedScope = 0;
  let indexed = 0;
  let invalidSkipped = 0;
  const items = [];
  let cursor = undefined;
  do {
    const page = await env.BOOKING_KV.list({
      prefix: "booking:",
      limit: 1000,
      cursor,
    });
    for (const item of page?.keys || []) {
      const key = safeStr(item?.name, 240);
      if (!key || !key.startsWith("booking:")) continue;
      scanned += 1;
      const bookingId = key.slice("booking:".length);
      if (!bookingId) {
        invalidSkipped += 1;
        continue;
      }
      const rec = await env.BOOKING_KV.get(key, { type: "json" });
      if (!rec || typeof rec !== "object") {
        invalidSkipped += 1;
        continue;
      }
      if (isAllocatorProbeRecord(rec)) {
        invalidSkipped += 1;
        continue;
      }
      if (!bookingMatchesRequiredTenantCompanyScope(rec, normalizedScope)) continue;
      matchedScope += 1;
      const indexItem = bookingListIndexItemFromRecord(bookingId, rec);
      if (!indexItem) {
        invalidSkipped += 1;
        continue;
      }
      items.push(indexItem);
      indexed += 1;
    }
    cursor = page?.cursor;
    if (page?.list_complete !== false) break;
    if (!cursor) break;
  } while (cursor);

  const previous = await readCompanyBookingsListIndex(env, normalizedScope);
  const prevCount = Number(previous?.index?.items?.length || 0);
  const dedup = new Map();
  for (const entry of items) dedup.set(entry.booking_id, entry);
  const nextCount = dedup.size;
  const removedOrRebuilt = Math.max(prevCount, nextCount);
  if (!dryRun) {
    await saveCompanyBookingsListIndex(env, normalizedScope, { items: Array.from(dedup.values()) });
  }
  return {
    ok: true,
    scanned,
    matched_scope: matchedScope,
    indexed: nextCount,
    invalid_skipped: invalidSkipped,
    removed_or_rebuilt: removedOrRebuilt,
    dry_run: dryRun === true,
  };
}

export async function rebuildDriverVehicleBookingIndexesForScope(env, scope, { dryRun = false } = {}) {
  const normalizedScope = _indexNormalizeFleetTenantScope(scope || {});
  if (!normalizedScope?.hasScope) {
    return { ok: false, error: "missing_tenant_scope" };
  }
  if (!env?.BOOKING_KV) {
    return { ok: false, error: "Missing BOOKING_KV binding" };
  }
  let scanned = 0;
  let matchedScope = 0;
  let driverIndexed = 0;
  let vehicleIndexed = 0;
  let assignmentlessSkipped = 0;
  let invalidSkipped = 0;
  let removedOrRebuilt = 0;
  const byKey = new Map();
  const addByKey = (key, item) => {
    if (!key) return;
    const arr = byKey.get(key) || [];
    arr.push(item);
    byKey.set(key, arr);
  };
  let cursor = undefined;
  do {
    const listed = await env.BOOKING_KV.list({
      prefix: "booking:",
      limit: 1000,
      cursor,
    });
    for (const keyEntry of listed?.keys || []) {
      const key = safeStr(keyEntry?.name, 240);
      if (!key || !key.startsWith("booking:")) continue;
      scanned += 1;
      const bookingId = key.slice("booking:".length);
      if (!bookingId) {
        invalidSkipped += 1;
        continue;
      }
      const rec = await env.BOOKING_KV.get(key, { type: "json" });
      if (!rec || typeof rec !== "object") {
        invalidSkipped += 1;
        continue;
      }
      if (!bookingMatchesRequiredTenantCompanyScope(rec, normalizedScope)) continue;
      matchedScope += 1;
      const item = bookingAssignmentIndexItemFromRecord(bookingId, rec);
      if (!item) {
        invalidSkipped += 1;
        continue;
      }
      const driverKey = driverScopedBookingsIndexKey(
        normalizedScope,
        _indexBookingAssignedDriverId(rec),
      );
      const vehicleKey = vehicleScopedBookingsIndexKey(
        normalizedScope,
        _indexBookingAssignedVehicleId(rec),
      );
      if (!driverKey && !vehicleKey) {
        assignmentlessSkipped += 1;
        continue;
      }
      if (driverKey) {
        driverIndexed += 1;
        addByKey(driverKey, item);
      }
      if (vehicleKey) {
        vehicleIndexed += 1;
        addByKey(vehicleKey, item);
      }
    }
    cursor = listed?.cursor;
    if (listed?.list_complete !== false) break;
    if (!cursor) break;
  } while (cursor);

  for (const [indexKey, items] of byKey.entries()) {
    if (!dryRun) {
      const existing = await readScopedAssignmentBookingIndex(env, indexKey);
      const prevCount = Number(existing?.index?.items?.length || 0);
      const saved = await saveScopedAssignmentBookingIndex(env, indexKey, { items });
      const nextCount = Number(saved?.count || 0);
      removedOrRebuilt += Math.max(prevCount, nextCount);
    } else {
      removedOrRebuilt += items.length;
    }
  }
  return {
    ok: true,
    scanned,
    matched_scope: matchedScope,
    driver_indexed: driverIndexed,
    vehicle_indexed: vehicleIndexed,
    assignmentless_skipped: assignmentlessSkipped,
    invalid_skipped: invalidSkipped,
    removed_or_rebuilt: removedOrRebuilt,
    dry_run: dryRun === true,
  };
}
