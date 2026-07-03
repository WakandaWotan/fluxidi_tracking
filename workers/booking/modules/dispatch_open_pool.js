/* Fluxidi driver "available unassigned" dispatch open-pool helpers (BW-M10).
 *
 * Verbatim extraction from workers/booking/fluxidi_booking_worker.js — no
 * behavior change. This module owns the read-only helpers that decide which
 * canonical bookings are eligible for the Driver → Available Unassigned
 * dispatch pool and the async collectors that materialize that pool from the
 * company bookings list index.
 *
 * Exported scope (11 items, all read-only, no KV writes, no mutation flows):
 *   Constants:
 *     - DRIVER_AVAILABLE_OPEN_LIKE_STATUSES
 *     - DRIVER_AVAILABLE_TERMINAL_STATUSES
 *     - DRIVER_AVAILABLE_ONLINE_PAID_STATUSES
 *   Pure helpers:
 *     - _normalizeDriverAvailableLifecycleToken
 *     - _driverAvailableUnassignedRowLifecycleTokens
 *     - _driverAvailableUnassignedRowIsOpenLike
 *     - _driverAvailableUnassignedPaymentEligible
 *     - _driverAvailableUnassignedCanonicalRecord
 *     - _driverAvailableUnassignedRowHidden
 *   Async collectors (BOOKING_KV read only — never .put/.delete):
 *     - _collectAvailableUnassignedRowsFromCompanyIndex
 *     - _appendDriverAvailableUnassignedBookings
 *
 * Explicitly NOT moved (STOP rule):
 *   - listDriverBookingsAuthoritative,
 *     listAdminDriverBookingsPreviewAuthoritative — orchestrators that also
 *     prune stale assignment indices (KV writes). Deferred (BW-M7C).
 *   - ensurePaidOpenBookingAutoDispatched — mutation flow that reserves via
 *     FleetAllocatorDO and persists assignments. Stays in main.
 *   - _driverBookingTripSignatureKey,
 *     _dedupeBookingListRowsByCanonicalTripSignature — dedupe surface shared
 *     across driver / company / admin list pipelines. Not dispatch-specific.
 *   - KV writers, payment lifecycle mutations, booking create/update/status,
 *     driver/chauffeur mutations, document/Billit/Peppol/Chiron, dev-reset
 *     — not in scope; untouched.
 *
 * Acyclic import graph. New module is a leaf:
 *   parsing_utils.js       ─►  dispatch_open_pool.js
 *   booking_utils.js       ─►  dispatch_open_pool.js
 *   booking_identity.js    ─►  dispatch_open_pool.js
 *   booking_read_model.js  ─►  dispatch_open_pool.js
 *   driver_ops.js          ─►  dispatch_open_pool.js
 *   booking_indexes.js     ─►  dispatch_open_pool.js
 *   dispatch_open_pool.js does NOT import back into main.
 *
 * Private module-local copy:
 *   - _driverBookingsRowDedupeKey — byte-identical duplicate. The original
 *     stays in main (2 external callers in
 *     listAdminDriverBookingsPreviewAuthoritative). Keeping a private copy
 *     here avoids modifying the BW-M7C-deferred orchestrator and mirrors the
 *     same pattern used in booking_read_model.js (BW-M8c).
 */

import { safeStr } from "./parsing_utils.js";
import {
  _pick,
  _bookingIntentMask,
  isTerminalLifecycleStatus,
} from "./booking_utils.js";
import {
  _dashboardBoolLike,
  _dashboardIdentityMeta,
  _dashboardCanonicalBookingNumber,
  _bookingListIsPaymentShadowRecord,
  _resolveCanonicalBookingIdFromShadow,
} from "./booking_identity.js";
import {
  bookingMatchesRequestedTenantScope,
  _flattenBookingForRidesListWithOperationalLegs,
} from "./booking_read_model.js";
import { _maskPublicDriverLoginValue } from "./driver_ops.js";
import { readCompanyBookingsListIndex } from "./booking_indexes.js";

/* -------- Private module-local duplicate ------------------------------ */

// Byte-identical copy of `_driverBookingsRowDedupeKey` from main. Original
// stays in main for other callers; this local copy exists solely so
// `_collectAvailableUnassignedRowsFromCompanyIndex` can dedupe without
// needing a back-import into main.
function _driverBookingsRowDedupeKey(row) {
  const bookingId = safeStr(row?.booking_id ?? row?.bookingId, 160);
  const legId = safeStr(row?.leg_id ?? row?.legId, 200);
  return `${bookingId}::${legId}`;
}

/* -------- Lifecycle / payment classification sets --------------------- */

export const DRIVER_AVAILABLE_OPEN_LIKE_STATUSES = new Set([
  "pending",
  "planned",
  "open",
  "scheduled",
  "confirmed",
  "assigned",
  "in_progress",
  "booked",
  "accepted",
  "awaiting_pickup",
  "active",
]);

export const DRIVER_AVAILABLE_TERMINAL_STATUSES = new Set([
  "completed",
  "cancelled",
  "canceled",
  "deleted",
  "archived",
  "closed",
  "failed",
  "expired",
  "declined",
]);

export const DRIVER_AVAILABLE_ONLINE_PAID_STATUSES = new Set([
  "paid",
  "settled",
  "captured",
  "completed",
  "confirmed",
  "success",
]);

/* -------- Pure classifier helpers ------------------------------------- */

export function _normalizeDriverAvailableLifecycleToken(value) {
  return String(value || "")
    .trim()
    .toLowerCase()
    .replaceAll("-", "_")
    .replaceAll(" ", "_");
}

export function _driverAvailableUnassignedRowLifecycleTokens(row, rec) {
  const tokens = [];
  for (const value of [
    row?.status,
    row?.lifecycle_status,
    row?.lifecycleStatus,
    row?.lifecycle,
    rec?.status,
    rec?.stage,
    rec?.lifecycle_status,
    rec?.lifecycleStatus,
    rec?.booking_status,
    rec?.bookingStatus,
    _pick(rec, ["booking", "status"], null),
    _pick(rec, ["booking", "stage"], null),
    _pick(rec, ["booking", "lifecycle_status"], null),
    _pick(rec, ["booking", "lifecycleStatus"], null),
    _pick(rec, ["booking", "booking_status"], null),
    _pick(rec, ["booking", "bookingStatus"], null),
  ]) {
    const normalized = _normalizeDriverAvailableLifecycleToken(value);
    if (normalized) tokens.push(normalized);
  }
  return tokens;
}

export function _driverAvailableUnassignedRowIsOpenLike(row, rec) {
  const tokens = _driverAvailableUnassignedRowLifecycleTokens(row, rec);
  if (!tokens.length) return false;
  if (tokens.some((token) => DRIVER_AVAILABLE_TERMINAL_STATUSES.has(token))) return false;
  if (tokens.some((token) => isTerminalLifecycleStatus(token))) return false;
  return tokens.some((token) => DRIVER_AVAILABLE_OPEN_LIKE_STATUSES.has(token));
}

export function _driverAvailableUnassignedPaymentEligible(rec, row) {
  const paymentStatus = _normalizeDriverAvailableLifecycleToken(
    row?.payment_status ??
      row?.paymentStatus ??
      rec?.payment_status ??
      rec?.paymentStatus ??
      _pick(rec, ["booking", "payment_status"], null) ??
      _pick(rec, ["booking", "paymentStatus"], null),
  );
  const paymentMode = _normalizeDriverAvailableLifecycleToken(
    rec?.payment_mode ??
      rec?.paymentMode ??
      _pick(rec, ["booking", "payment_mode"], null) ??
      _pick(rec, ["booking", "paymentMode"], null),
  );
  const paymentProvider = _normalizeDriverAvailableLifecycleToken(
    row?.payment_provider ??
      row?.paymentProvider ??
      rec?.payment_provider ??
      rec?.paymentProvider ??
      _pick(rec, ["booking", "payment_provider"], null) ??
      _pick(rec, ["booking", "paymentProvider"], null),
  );
  const paidAt = safeStr(
    rec?.paid_at ??
      rec?.paidAt ??
      _pick(rec, ["booking", "paid_at"], null) ??
      _pick(rec, ["booking", "paidAt"], null),
    80,
  );
  const isMollieLike =
    paymentMode === "mollie" ||
    paymentProvider === "mollie" ||
    _dashboardBoolLike(rec?.mollie) ||
    _dashboardBoolLike(_pick(rec, ["booking", "mollie"], null));
  const isOnlineLike =
    isMollieLike ||
    paymentMode === "online" ||
    paymentMode === "online_payment" ||
    paymentMode === "online_payments" ||
    paymentProvider === "online" ||
    paymentProvider === "online_payment" ||
    paymentProvider === "prepaid" ||
    paymentMode === "prepaid";
  const isManualLike =
    paymentMode === "manual" ||
    paymentMode === "cash" ||
    paymentMode === "invoice" ||
    paymentMode === "in_vehicle" ||
    paymentMode === "in_vehicle_card" ||
    paymentProvider === "manual" ||
    paymentProvider === "cash" ||
    paymentProvider === "invoice" ||
    paymentProvider === "in_vehicle_card" ||
    paymentProvider === "qr";
  const paidLike =
    DRIVER_AVAILABLE_ONLINE_PAID_STATUSES.has(paymentStatus) || !!paidAt;
  const failedLike = new Set([
    "failed",
    "expired",
    "cancelled",
    "canceled",
    "payment_failed",
    "payment_checkout_failed",
    "checkout_failed",
    "checkout_expired",
  ]).has(paymentStatus);

  if (failedLike) return false;
  if (isOnlineLike && !isManualLike) {
    return paidLike;
  }
  return true;
}

export function _driverAvailableUnassignedCanonicalRecord(bookingId, rec) {
  const identityMeta = _dashboardIdentityMeta(rec, bookingId);
  if (identityMeta?.has_canonical_booking_number === true) return true;
  // G1: a UUID-shaped record key is the sentinel for the Mollie payment-shadow
  // KV mirror. Do not allow `has_public_booking_reference` to short-circuit
  // such a record into the available-unassigned list — those rows must be
  // canonicalized via `_resolveCanonicalBookingIdFromShadow` before they can
  // be considered for dispatch.
  if (
    identityMeta?.internal_id_like === true &&
    identityMeta?.has_canonical_booking_number !== true
  ) {
    return false;
  }
  if (identityMeta?.has_public_booking_reference === true) return true;
  if (_dashboardCanonicalBookingNumber(bookingId)) return true;
  if (identityMeta?.record_shape_hint === "provisional_payment_record") return false;
  return !!_dashboardCanonicalBookingNumber(bookingId);
}

export function _driverAvailableUnassignedRowHidden(rec) {
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

/* -------- Async collectors (KV read-only) ----------------------------- */

export async function _appendDriverAvailableUnassignedBookings(
  env,
  { tenantScope, out, cutoffMs, sessionDriverId } = {},
) {
  if (!tenantScope?.hasScope || !env?.BOOKING_KV || !Array.isArray(out)) {
    return { added: 0, scanned: 0, skipped: 0 };
  }

  const seenKeys = new Set(out.map((row) => _driverBookingsRowDedupeKey(row)));
  const collected = await _collectAvailableUnassignedRowsFromCompanyIndex(env, {
    tenantScope,
    cutoffMs,
    seenKeys,
    logTag: "DRIVER_BOOKINGS",
    sessionDriverId,
  });
  for (const row of collected.rows) out.push(row);

  const added = collected.rows.length;
  const scanned = collected.scanned;
  const skipped = collected.skipped;

  if (added > 0 || scanned > 0) {
    console.log(
      `[DRIVER_BOOKINGS][AVAILABLE_INCLUDE_UNASSIGNED] tenant=${_maskPublicDriverLoginValue(tenantScope?.tenant_id)} company=${_maskPublicDriverLoginValue(tenantScope?.company_id)} driver=${_maskPublicDriverLoginValue(sessionDriverId)} added=${added} scanned=${scanned} skipped=${skipped}`,
    );
  }

  return {
    added,
    scanned,
    skipped,
    ...(collected.indexUnavailable ? { index_unavailable: true } : {}),
  };
}

// G2-C: shared helper that materializes the available-unassigned dispatch
// pool from the company bookings list index. Both /driver/bookings (via
// _appendDriverAvailableUnassignedBookings) and the admin preview route
// (listAdminDriverBookingsPreviewAuthoritative) use this exact same gate
// chain, so any drift between the two surfaces is impossible. The helper
// is read-only — it never writes to KV. All emitted diagnostics are masked
// (no personal data, no full booking ids).
//
// Eligibility gates (in order):
//   1. record present, tenant scope match, not hidden, canonical (G1)
//   2. row not already in `seenKeys` (caller-provided dedupe set)
//   3. no assigned_driver_id, no assigned_vehicle_id
//   4. status not COMPLETED / CANCELLED / terminal lifecycle
//   5. lifecycle is open-like (pending / planned / scheduled / confirmed
//      / booked / accepted / awaiting_pickup / active / open / in_progress
//      / assigned)
//   6. pickup_iso parses to a finite timestamp >= cutoffMs
//   7. payment is eligible: online/mollie/prepaid require paid/settled/
//      captured/completed/confirmed/success/paid_at; manual/cash/qr/invoice
//      pass through.
//
// Returns { rows, scanned, skipped, indexUnavailable }. Rows are stamped
// `available_unassigned: true` and `availableUnassigned: true`.
export async function _collectAvailableUnassignedRowsFromCompanyIndex(
  env,
  {
    tenantScope = null,
    cutoffMs = Number.NaN,
    seenKeys = new Set(),
    logTag = "BOOKING_LIST",
    sessionDriverId = "",
  } = {},
) {
  const result = { rows: [], scanned: 0, skipped: 0, indexUnavailable: false };
  if (!tenantScope?.hasScope || !env?.BOOKING_KV) return result;

  const indexRead = await readCompanyBookingsListIndex(env, tenantScope);
  const sourceItems = Array.isArray(indexRead?.index?.items) ? indexRead.index.items : [];
  if (!indexRead?.ok || sourceItems.length === 0) {
    result.indexUnavailable = indexRead?.ok !== true;
    console.log(
      `[${logTag}][AVAILABLE_POOL_START] tenant=${_maskPublicDriverLoginValue(tenantScope?.tenant_id)} company=${_maskPublicDriverLoginValue(tenantScope?.company_id)} driver=${_maskPublicDriverLoginValue(sessionDriverId)} candidates=0 index_ok=${indexRead?.ok === true} source_items=${sourceItems.length}`,
    );
    return result;
  }

  const candidateIds = new Set();
  for (const entry of sourceItems) {
    const bookingId = safeStr(entry?.booking_id ?? entry?.bookingId, 160);
    if (bookingId) candidateIds.add(bookingId);
  }

  // G1 reuse: drop UUID-shaped payment-shadow ids and replace them with
  // their canonical counterpart. Logs go under [BOOKING_LIST] so shadow
  // diagnostics are attributable to the index, not to the calling surface.
  const recordCache = new Map();
  const canonicalCandidateIds = new Set();
  for (const bookingId of candidateIds) {
    const rec = await env.BOOKING_KV.get(`booking:${bookingId}`, { type: "json" });
    if (!rec || typeof rec !== "object") continue;
    recordCache.set(bookingId, rec);
    if (_bookingListIsPaymentShadowRecord(rec, bookingId)) {
      const canonical = _resolveCanonicalBookingIdFromShadow(rec, bookingId);
      if (canonical) {
        console.log(
          `[BOOKING_LIST][SHADOW_CANONICALIZED] shadow=${_bookingIntentMask(bookingId)} canonical=${_bookingIntentMask(canonical)}`,
        );
        canonicalCandidateIds.add(canonical);
      } else {
        console.log(
          `[BOOKING_LIST][SHADOW_SKIPPED] shadow=${_bookingIntentMask(bookingId)} reason=no_canonical_reference`,
        );
      }
      continue;
    }
    canonicalCandidateIds.add(bookingId);
  }

  console.log(
    `[${logTag}][AVAILABLE_POOL_START] tenant=${_maskPublicDriverLoginValue(tenantScope?.tenant_id)} company=${_maskPublicDriverLoginValue(tenantScope?.company_id)} driver=${_maskPublicDriverLoginValue(sessionDriverId)} candidates=${canonicalCandidateIds.size} source_items=${sourceItems.length}`,
  );

  const logSkip = (bookingId, legId, reason) => {
    console.log(
      `[${logTag}][AVAILABLE_POOL_SKIP] booking=${_bookingIntentMask(bookingId)} leg=${_bookingIntentMask(legId)} reason=${reason}`,
    );
  };

  for (const bookingId of canonicalCandidateIds) {
    result.scanned += 1;
    let rec = recordCache.get(bookingId);
    if (!rec) {
      rec = await env.BOOKING_KV.get(`booking:${bookingId}`, { type: "json" });
    }
    if (!rec || typeof rec !== "object") {
      result.skipped += 1;
      logSkip(bookingId, "", "record_missing");
      continue;
    }
    if (!bookingMatchesRequestedTenantScope(rec, tenantScope)) {
      result.skipped += 1;
      logSkip(bookingId, "", "tenant_mismatch");
      continue;
    }
    if (_driverAvailableUnassignedRowHidden(rec)) {
      result.skipped += 1;
      logSkip(bookingId, "", "row_hidden");
      continue;
    }
    if (!_driverAvailableUnassignedCanonicalRecord(bookingId, rec)) {
      result.skipped += 1;
      logSkip(bookingId, "", "non_canonical_record");
      continue;
    }

    const rows = _flattenBookingForRidesListWithOperationalLegs(bookingId, rec);
    for (const row of rows) {
      const dedupeKey = _driverBookingsRowDedupeKey(row);
      const legId = safeStr(row?.leg_id ?? row?.legId, 200);
      if (seenKeys.has(dedupeKey)) {
        result.skipped += 1;
        logSkip(bookingId, legId, "already_seen");
        continue;
      }
      const rowDriverId = safeStr(row?.assigned_driver_id ?? row?.assignedDriverId, 96);
      if (rowDriverId) {
        result.skipped += 1;
        logSkip(bookingId, legId, "row_assigned_driver");
        continue;
      }
      const rowVehicleId = safeStr(row?.assigned_vehicle_id ?? row?.assignedVehicleId, 128);
      if (rowVehicleId) {
        result.skipped += 1;
        logSkip(bookingId, legId, "row_assigned_vehicle");
        continue;
      }
      if (
        row.status === "COMPLETED" ||
        row.status === "CANCELLED" ||
        isTerminalLifecycleStatus(row?.status)
      ) {
        result.skipped += 1;
        logSkip(bookingId, legId, "terminal_status");
        continue;
      }
      if (!_driverAvailableUnassignedRowIsOpenLike(row, rec)) {
        result.skipped += 1;
        logSkip(bookingId, legId, "not_open_like");
        continue;
      }
      const pickupTs = row.pickup_iso ? Date.parse(row.pickup_iso) : Number.NaN;
      if (!Number.isFinite(pickupTs)) {
        result.skipped += 1;
        logSkip(bookingId, legId, "pickup_invalid");
        continue;
      }
      if (Number.isFinite(cutoffMs) && pickupTs < cutoffMs) {
        result.skipped += 1;
        logSkip(bookingId, legId, "pickup_past_cutoff");
        continue;
      }
      if (!_driverAvailableUnassignedPaymentEligible(rec, row)) {
        result.skipped += 1;
        logSkip(bookingId, legId, "payment_not_eligible");
        continue;
      }

      result.rows.push({
        ...row,
        available_unassigned: true,
        availableUnassigned: true,
      });
      seenKeys.add(dedupeKey);
      console.log(
        `[${logTag}][AVAILABLE_POOL_APPEND] booking=${_bookingIntentMask(bookingId)} leg=${_bookingIntentMask(legId)}`,
      );
    }
  }

  return result;
}
