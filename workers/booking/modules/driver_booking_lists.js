/* Fluxidi driver-facing booking list orchestrators + shared dedupe surface
 * (BW-M7C).
 *
 * Verbatim extraction from workers/booking/fluxidi_booking_worker.js — no
 * behavior change. This module owns:
 *
 *   Pure dedupe surface (used by both driver orchestrators AND main's
 *   company `listBookingsAuthoritative`):
 *     - _driverBookingsRowDedupeKey
 *     - _driverBookingTripSignatureKey
 *     - _dedupeBookingListRowsByCanonicalTripSignature
 *
 *   Read-orchestrators (never mutate booking core / payment / dispatch;
 *   the only KV writes are best-effort stale-index pruning through the
 *   byte-identical BW-M11 writer `saveScopedAssignmentBookingIndex`):
 *     - listDriverBookingsAuthoritative
 *     - listAdminDriverBookingsPreviewAuthoritative
 *
 * Explicitly NOT in this module (STOP rule):
 *   - Route handlers for /driver/bookings and /admin/driver/bookings-preview
 *     — they stay in main.
 *   - listBookingsAuthoritative (company /bookings) — stays in main; it
 *     imports `_dedupeBookingListRowsByCanonicalTripSignature` from here.
 *   - Booking/payment/status/assign mutations, dispatch allocator,
 *     driver/vehicle mutation, document/Billit/Peppol/Chiron, dev-reset —
 *     out of scope; untouched.
 *
 * Behavior guarantees preserved (BW-M7C):
 *   - identical KV reads, identical stale-index pruning semantics,
 *   - identical try/catch around saveScopedAssignmentBookingIndex,
 *   - identical console.log masking (via `_maskPublicDriverLoginValue` and
 *     `_bookingIntentMask`),
 *   - identical dedupe sort/order/limit truncation,
 *   - identical G1/G2 canonical hygiene log tags:
 *       [DRIVER_BOOKINGS][NO_ASSIGNED_INDEX/DEGRADED_INDEX/POST_APPEND/
 *        DEDUP_CANONICAL/FINAL_FILTER_SKIP/FINAL_RESPONSE]
 *       [BOOKING_LIST][SHADOW_CANONICALIZED/SHADOW_SKIPPED/DEDUP_CANONICAL]
 *       [ADMIN_DRIVER_PREVIEW][SHADOW_CANONICALIZED/SHADOW_SKIPPED/
 *        DEDUP_CANONICAL]
 *
 * Acyclic import graph (verified — none of the sources import back from
 * driver_booking_lists.js):
 *   parsing_utils.js       ─►
 *   auth_scope.js          ─►
 *   booking_utils.js       ─►
 *   booking_identity.js    ─►  driver_booking_lists.js
 *   booking_read_model.js  ─►
 *   booking_indexes.js     ─►
 *   dispatch_open_pool.js  ─►
 *   driver_ops.js          ─►
 *
 * No private duplicates are needed: every dependency is either already an
 * export of a modularized helper or lives inside this file.
 */

import { safeStr } from "./parsing_utils.js";
import { _scopeText } from "./auth_scope.js";
import {
  _bookingIntentMask,
  isTerminalLifecycleStatus,
} from "./booking_utils.js";
import {
  _bookingListIsPaymentShadowRecord,
  _resolveCanonicalBookingIdFromShadow,
  _dashboardCanonicalBookingNumber,
} from "./booking_identity.js";
import {
  bookingMatchesRequestedTenantScope,
  _flattenBookingForRidesListWithOperationalLegs,
  _rowIsStreetDirectRide,
} from "./booking_read_model.js";
import {
  driverScopedBookingsIndexKey,
  vehicleScopedBookingsIndexKey,
  readScopedAssignmentBookingIndex,
  saveScopedAssignmentBookingIndex,
  readCompanyBookingsListIndex,
  _companyBookingsListIndexStaleAfterMs,
} from "./booking_indexes.js";
import {
  _appendDriverAvailableUnassignedBookings,
  _driverAvailableUnassignedRowHidden,
  _driverAvailableUnassignedCanonicalRecord,
  _driverAvailableUnassignedRowIsOpenLike,
  _driverAvailableUnassignedPaymentEligible,
} from "./dispatch_open_pool.js";
import { _maskPublicDriverLoginValue } from "./driver_ops.js";

/* ---- Pure dedupe surface --------------------------------------------- */

export function _driverBookingsRowDedupeKey(row) {
  const bookingId = safeStr(row?.booking_id ?? row?.bookingId, 160);
  const legId = safeStr(row?.leg_id ?? row?.legId, 200);
  return `${bookingId}::${legId}`;
}

// G1: cross-booking-id trip signature for last-resort dedupe. Two rows that
// describe the exact same pickup time + route + price are treated as the same
// operational ride even if their booking_id differs (canonical vs UUID
// shadow). Empty string means "not enough information to dedupe".
export function _driverBookingTripSignatureKey(row) {
  const legId = safeStr(row?.leg_id ?? row?.legId, 200);
  const bookingId = safeStr(row?.booking_id ?? row?.bookingId, 160);
  if (legId && bookingId) {
    return `${bookingId}::${legId}`;
  }
  const pickup = safeStr(row?.pickup_iso ?? row?.pickupIso, 80);
  const from = safeStr(row?.from, 240).toLowerCase().trim();
  const to = safeStr(row?.to, 240).toLowerCase().trim();
  if (!pickup || !from || !to) return "";
  const priceRaw =
    row?.price ?? row?.price_incl_vat ?? row?.priceIncl ?? null;
  let priceText = "";
  if (priceRaw != null) {
    const num = Number(priceRaw);
    priceText = Number.isFinite(num) ? num.toFixed(2) : safeStr(priceRaw, 32);
  }
  return `${pickup}|${from}|${to}|${priceText}`;
}

// G1: prefer canonical-id rows over UUID-shadow rows when both share a trip
// signature. Emits a single compact diagnostic per drop. `logTag` lets the
// caller distinguish driver vs company list traces in production logs.
export function _dedupeBookingListRowsByCanonicalTripSignature(rows, options = {}) {
  // G2-D: defensive copy. Callers that follow the pattern
  //   const dedupedOut = _dedupeBookingListRowsByCanonicalTripSignature(out, ...);
  //   out.length = 0;
  //   for (const row of dedupedOut) out.push(row);
  // would otherwise destroy the very rows they intended to dedupe whenever
  // the early-return path triggered (rows.length < 2 returned the same
  // array reference, so `out.length = 0` cleared `dedupedOut` too).
  // Returning a fresh array is correct in both branches and removes the
  // foot-gun for every existing and future caller.
  if (!Array.isArray(rows)) return [];
  if (rows.length < 2) return rows.slice();
  const logTag = safeStr(options?.logTag, 64) || "BOOKING_LIST";
  const bestBy = new Map();
  const order = [];
  const drops = [];
  for (const row of rows) {
    const sigKey = _driverBookingTripSignatureKey(row);
    if (!sigKey) {
      order.push({ row });
      continue;
    }
    const bookingId = safeStr(row?.booking_id ?? row?.bookingId, 160);
    const isCanonical = !!_dashboardCanonicalBookingNumber(bookingId);
    const previous = bestBy.get(sigKey);
    if (!previous) {
      const slot = { row, isCanonical };
      bestBy.set(sigKey, slot);
      order.push(slot);
      continue;
    }
    if (isCanonical && !previous.isCanonical) {
      drops.push({ kept: row, dropped: previous.row });
      previous.row = row;
      previous.isCanonical = true;
      continue;
    }
    drops.push({ kept: previous.row, dropped: row });
  }
  for (const { kept, dropped } of drops) {
    const keptId = safeStr(kept?.booking_id ?? kept?.bookingId, 160);
    const droppedId = safeStr(dropped?.booking_id ?? dropped?.bookingId, 160);
    console.log(
      `[${logTag}][DEDUP_CANONICAL] kept=${_bookingIntentMask(keptId)} dropped=${_bookingIntentMask(droppedId)}`,
    );
  }
  return order.map((entry) => entry.row);
}

/* ---- Street/direct planned-projection exclusion (P0-FIELD-REPAIR-1) --- */

/**
 * Removes street/direct rides from a driver PLANNED/OPEN projection.
 *
 * Product contract: a street/direct ride is owned by the active street-ride
 * lifecycle while it runs and belongs to Completed/history once stopped. It is
 * never a "planned" or "next" ride, so it must not reach the driver's
 * planned/open list in either state. The canonical record itself is untouched —
 * this is a read-side projection filter only, and it is never applied to the
 * history projection (`include_history=1`) or to the company bookings list.
 *
 * Returns a new array; input order is preserved. Emits one bounded, masked
 * diagnostic per excluded row.
 */
export function _excludeStreetDirectFromPlannedProjection(rows, options = {}) {
  if (!Array.isArray(rows)) return [];
  const logTag = safeStr(options?.logTag, 64) || "DRIVER_BOOKINGS";
  const kept = [];
  for (const row of rows) {
    if (_rowIsStreetDirectRide(row)) {
      const droppedId = safeStr(row?.booking_id ?? row?.bookingId, 160);
      console.log(
        `[${logTag}][STREET_DIRECT_NOT_PLANNED] booking=${_bookingIntentMask(droppedId)} status=${safeStr(row?.status, 40) || "-"} reason=street_direct_never_planned`,
      );
      continue;
    }
    kept.push(row);
  }
  return kept;
}

/* ---- Driver-facing read orchestrators -------------------------------- */

export async function listDriverBookingsAuthoritative(
  env,
  { limit = 50, includeHistory = false, tenantScope = null, driverSession = null } = {},
) {
  if (!tenantScope?.hasScope) return { ok: true, items: [] };
  if (!env.BOOKING_KV) throw new Error("BOOKING_KV binding is missing");
  const lim = Math.min(200, Math.max(1, Number(limit) || 50));
  const sessionDriverId = _scopeText(driverSession?.driver_id, 96);
  const sessionVehicleId = _scopeText(driverSession?.assigned_vehicle_id, 128);
  if (!sessionDriverId && !sessionVehicleId) return { ok: true, items: [] };

  const sources = [];
  if (sessionDriverId) {
    sources.push({
      kind: "driver",
      key: driverScopedBookingsIndexKey(tenantScope, sessionDriverId),
    });
  }
  if (sessionVehicleId) {
    sources.push({
      kind: "vehicle",
      key: vehicleScopedBookingsIndexKey(tenantScope, sessionVehicleId),
    });
  }
  const normalizedSources = sources.filter((source) => !!safeStr(source?.key, 260));
  if (!normalizedSources.length) {
    return { ok: false, error: "driver_booking_index_unavailable" };
  }

  const readResults = [];
  let availableCount = 0;
  let unavailableCount = 0;
  let staleUnavailableCount = 0;
  const staleAfterMs = Math.max(
    0,
    Number(env?.DRIVER_BOOKING_INDEX_STALE_AFTER_MS || 0) || 0,
  );
  for (const source of normalizedSources) {
    const read = await readScopedAssignmentBookingIndex(env, source.key);
    const updatedAtMs = Date.parse(safeStr(read?.index?.updated_at ?? read?.index?.updatedAt, 80));
    const stale = staleAfterMs > 0 && (!Number.isFinite(updatedAtMs) || (Date.now() - updatedAtMs) > staleAfterMs);
    const available = !!(read?.ok && read?.exists && read?.valid && read?.index && !stale);
    if (available) {
      availableCount += 1;
    } else {
      unavailableCount += 1;
      if (stale) staleUnavailableCount += 1;
    }
    readResults.push({ ...source, read, available, stale });
  }
  if (!availableCount && normalizedSources.length > 0) {
    // G2-C: do not short-circuit out of the function just because the
    // driver-scoped (or vehicle-scoped) assignment index is missing/stale.
    // Admin preview happily surfaces available_unassigned dispatch work
    // from the company index without an assignment index, and a fresh
    // driver who has never been assigned anything would otherwise never
    // see the dispatch pool. We log the degraded state for traceability
    // and fall through with `availableCount === 0`; the assigned-row loop
    // below will see no available sources and naturally produce zero
    // assigned rows, which is the correct behavior. The available pool
    // append at the end of this function still runs.
    console.log(
      `[DRIVER_BOOKINGS][NO_ASSIGNED_INDEX] tenant=${_maskPublicDriverLoginValue(tenantScope?.tenant_id)} company=${_maskPublicDriverLoginValue(tenantScope?.company_id)} driver=${_maskPublicDriverLoginValue(sessionDriverId)} stale_unavailable=${staleUnavailableCount} unavailable=${unavailableCount}`,
    );
  }
  if (availableCount > 0 && unavailableCount > 0) {
    console.log(
      `[DRIVER_BOOKINGS][DEGRADED_INDEX] tenant=${_maskPublicDriverLoginValue(tenantScope?.tenant_id)} company=${_maskPublicDriverLoginValue(tenantScope?.company_id)} available=${availableCount} unavailable=${unavailableCount} stale=${staleUnavailableCount}`,
    );
  }

  const bookingToSourceKeys = new Map();
  const candidateIds = new Set();
  for (const source of readResults) {
    if (!source.available) continue;
    const items = Array.isArray(source?.read?.index?.items) ? source.read.index.items : [];
    for (const item of items) {
      const bookingId = safeStr(item?.booking_id ?? item?.bookingId, 160);
      if (!bookingId) continue;
      candidateIds.add(bookingId);
      const keySet = bookingToSourceKeys.get(bookingId) || new Set();
      keySet.add(source.key);
      bookingToSourceKeys.set(bookingId, keySet);
    }
  }

  const nowMs = Date.now();
  const actionableGraceMs = 6 * 60 * 60 * 1000;
  const cutoffMs = nowMs - actionableGraceMs;
  const out = [];
  const staleIdsByKey = new Map();

  // G1: canonicalize payment-shadow ids in the driver-scoped index. The
  // shadow ids must never produce ride rows; if a shadow points to a canonical
  // booking, inherit its source-key set so the canonical row appears in the
  // same driver/vehicle scopes the shadow lived in. The shadow id itself is
  // queued for index pruning.
  const recordCache = new Map();
  const canonicalCandidateIds = new Set();
  for (const bookingId of candidateIds) {
    const rec = await env.BOOKING_KV.get(`booking:${bookingId}`, { type: "json" });
    if (!rec || typeof rec !== "object") {
      for (const indexKey of bookingToSourceKeys.get(bookingId) || []) {
        const stale = staleIdsByKey.get(indexKey) || new Set();
        stale.add(bookingId);
        staleIdsByKey.set(indexKey, stale);
      }
      continue;
    }
    recordCache.set(bookingId, rec);
    if (_bookingListIsPaymentShadowRecord(rec, bookingId)) {
      const canonical = _resolveCanonicalBookingIdFromShadow(rec, bookingId);
      if (canonical) {
        console.log(
          `[BOOKING_LIST][SHADOW_CANONICALIZED] shadow=${_bookingIntentMask(bookingId)} canonical=${_bookingIntentMask(canonical)}`,
        );
        canonicalCandidateIds.add(canonical);
        const shadowKeys = bookingToSourceKeys.get(bookingId) || new Set();
        const inherited = bookingToSourceKeys.get(canonical) || new Set();
        for (const k of shadowKeys) inherited.add(k);
        bookingToSourceKeys.set(canonical, inherited);
      } else {
        console.log(
          `[BOOKING_LIST][SHADOW_SKIPPED] shadow=${_bookingIntentMask(bookingId)} reason=no_canonical_reference`,
        );
      }
      for (const indexKey of bookingToSourceKeys.get(bookingId) || []) {
        const stale = staleIdsByKey.get(indexKey) || new Set();
        stale.add(bookingId);
        staleIdsByKey.set(indexKey, stale);
      }
      continue;
    }
    canonicalCandidateIds.add(bookingId);
  }

  for (const bookingId of canonicalCandidateIds) {
    let rec = recordCache.get(bookingId);
    if (!rec) {
      rec = await env.BOOKING_KV.get(`booking:${bookingId}`, { type: "json" });
    }
    if (!rec || typeof rec !== "object") {
      for (const indexKey of bookingToSourceKeys.get(bookingId) || []) {
        const stale = staleIdsByKey.get(indexKey) || new Set();
        stale.add(bookingId);
        staleIdsByKey.set(indexKey, stale);
      }
      continue;
    }
    if (!bookingMatchesRequestedTenantScope(rec, tenantScope)) {
      for (const indexKey of bookingToSourceKeys.get(bookingId) || []) {
        const stale = staleIdsByKey.get(indexKey) || new Set();
        stale.add(bookingId);
        staleIdsByKey.set(indexKey, stale);
      }
      continue;
    }
    const rows = _flattenBookingForRidesListWithOperationalLegs(bookingId, rec);
    let matchedAny = false;
    for (const row of rows) {
      const rowDriverId = safeStr(
        row?.assigned_driver_id ?? row?.assignedDriverId,
        96,
      );
      const rowVehicleId = safeStr(
        row?.assigned_vehicle_id ?? row?.assignedVehicleId,
        128,
      );
      const driverMatch = !!(sessionDriverId && rowDriverId && sessionDriverId === rowDriverId);
      const vehicleMatch = !!(sessionVehicleId && rowVehicleId && sessionVehicleId === rowVehicleId);
      if (!driverMatch && !vehicleMatch) continue;
      matchedAny = true;
      if (
        !includeHistory &&
        (row.status === "COMPLETED" || row.status === "CANCELLED")
      ) continue;
      if (!includeHistory) {
        const pickupTs = row.pickup_iso ? Date.parse(row.pickup_iso) : Number.NaN;
        if (!Number.isFinite(pickupTs)) continue;
        if (Number.isFinite(pickupTs) && pickupTs < cutoffMs) continue;
      }
      out.push(row);
    }
    if (!matchedAny) {
      for (const indexKey of bookingToSourceKeys.get(bookingId) || []) {
        const stale = staleIdsByKey.get(indexKey) || new Set();
        stale.add(bookingId);
        staleIdsByKey.set(indexKey, stale);
      }
      continue;
    }
  }

  for (const source of readResults) {
    const staleIds = staleIdsByKey.get(source.key);
    if (!source.available || !staleIds || staleIds.size === 0) continue;
    try {
      const sourceItems = Array.isArray(source?.read?.index?.items) ? source.read.index.items : [];
      const nextItems = sourceItems.filter((entry) => {
        const bookingId = safeStr(entry?.booking_id ?? entry?.bookingId, 160);
        return bookingId && !staleIds.has(bookingId);
      });
      if (nextItems.length !== sourceItems.length) {
        await saveScopedAssignmentBookingIndex(env, source.key, { items: nextItems });
      }
    } catch (_) {
      // Best-effort stale pruning; never fail the driver bookings response.
    }
  }

  if (!includeHistory) {
    await _appendDriverAvailableUnassignedBookings(env, {
      tenantScope,
      out,
      cutoffMs,
      sessionDriverId,
    });
    // P0-FIELD-REPAIR-1 (A1): a street/direct ride is never a planned or next
    // ride. Applied AFTER the available-pool append so it covers every source
    // that can feed the planned/open projection (assigned index, vehicle
    // index, dispatch pool). History (`include_history=1`) is deliberately
    // untouched so Completed/company history keeps the canonical row.
    const withoutStreetDirect = _excludeStreetDirectFromPlannedProjection(out, {
      logTag: "DRIVER_BOOKINGS",
    });
    if (withoutStreetDirect.length !== out.length) {
      out.length = 0;
      for (const row of withoutStreetDirect) out.push(row);
    }
  }

  // G2-D: snapshot row counts immediately after the available pool was
  // appended. Combined with [DRIVER_BOOKINGS][FINAL_RESPONSE] this makes it
  // trivial to spot any row that goes missing between collection and the
  // final response — a regression that previously surfaced when the dedupe
  // helper returned `out` itself for length-1 inputs and the caller cleared
  // `out` immediately after.
  let postAppendAvailable = 0;
  let postAppendAssigned = 0;
  for (const row of out) {
    if (row?.available_unassigned === true || row?.availableUnassigned === true) {
      postAppendAvailable += 1;
    } else {
      postAppendAssigned += 1;
    }
  }
  console.log(
    `[DRIVER_BOOKINGS][POST_APPEND] tenant=${_maskPublicDriverLoginValue(tenantScope?.tenant_id)} company=${_maskPublicDriverLoginValue(tenantScope?.company_id)} driver=${_maskPublicDriverLoginValue(sessionDriverId)} count=${out.length} available=${postAppendAvailable} assigned=${postAppendAssigned}`,
  );

  // G1: belt-and-braces dedup. After canonicalization the same trip should
  // only have one row, but if any pre-existing index pollution survived (e.g.
  // a UUID shadow row with no resolvable canonical id but the canonical row
  // also present), drop the non-canonical duplicate and prefer the canonical
  // booking-number row. Emits [DRIVER_BOOKINGS][DEDUP_CANONICAL] only when a
  // duplicate is actually dropped.
  const dedupedOut = _dedupeBookingListRowsByCanonicalTripSignature(out, {
    logTag: "DRIVER_BOOKINGS",
  });

  dedupedOut.sort((a, b) => {
    const ta = a.pickup_iso ? Date.parse(a.pickup_iso) : Number.POSITIVE_INFINITY;
    const tb = b.pickup_iso ? Date.parse(b.pickup_iso) : Number.POSITIVE_INFINITY;
    return ta - tb;
  });

  // G2-D: log every row dropped by the final `slice(0, lim)` truncation so
  // any future limit-related row loss is immediately visible. Dedupe drops
  // are already covered by the helper's [DRIVER_BOOKINGS][DEDUP_CANONICAL]
  // log line and are intentionally not duplicated here.
  if (dedupedOut.length > lim) {
    for (let i = lim; i < dedupedOut.length; i++) {
      const truncated = dedupedOut[i];
      const truncatedId = safeStr(
        truncated?.booking_id ?? truncated?.bookingId,
        160,
      );
      console.log(
        `[DRIVER_BOOKINGS][FINAL_FILTER_SKIP] booking=${_bookingIntentMask(truncatedId)} reason=limit_truncated`,
      );
    }
  }

  const finalItems = dedupedOut.slice(0, lim);

  let finalAvailable = 0;
  let finalAssigned = 0;
  for (const row of finalItems) {
    if (row?.available_unassigned === true || row?.availableUnassigned === true) {
      finalAvailable += 1;
    } else {
      finalAssigned += 1;
    }
  }
  console.log(
    `[DRIVER_BOOKINGS][FINAL_RESPONSE] tenant=${_maskPublicDriverLoginValue(tenantScope?.tenant_id)} company=${_maskPublicDriverLoginValue(tenantScope?.company_id)} driver=${_maskPublicDriverLoginValue(sessionDriverId)} count=${finalItems.length} available=${finalAvailable} assigned=${finalAssigned}`,
  );

  return { ok: true, items: finalItems };
}

// G2-A: admin/company-scoped read-only mirror of /driver/bookings for the
// Business Home → Chauffeurweergave preview surface. The caller is an admin
// (validated by `_requireAdmin` at the route layer) with an explicit tenant /
// company scope (validated by `requireExplicitBookingRouteScope`). Optional
// `driverId` and/or `vehicleId` narrow the result to rows assigned to that
// driver / vehicle, plus the available-unassigned dispatch pool. This
// endpoint MUST NOT mutate, MUST NOT use customer auth, and MUST NOT pretend
// to be a real driver session — it reads the company bookings list index
// directly and applies the same G1 canonical-only hygiene as the other lists.
export async function listAdminDriverBookingsPreviewAuthoritative(
  env,
  {
    limit = 50,
    tenantScope = null,
    driverId = "",
    vehicleId = "",
  } = {},
) {
  if (!tenantScope?.hasScope) return { ok: true, items: [] };
  if (!env?.BOOKING_KV) throw new Error("BOOKING_KV binding is missing");
  const lim = Math.min(200, Math.max(1, Number(limit) || 50));
  const targetDriverId = _scopeText(driverId, 96);
  const targetVehicleId = _scopeText(vehicleId, 128);

  const indexRead = await readCompanyBookingsListIndex(env, tenantScope);
  if (indexRead?.ok && indexRead?.exists === false) {
    return { ok: true, items: [], assigned: 0, available: 0 };
  }
  if (!indexRead?.ok || !indexRead?.valid || !indexRead?.index) {
    return { ok: false, error: "company_bookings_list_index_unavailable" };
  }
  const staleAfterMs = _companyBookingsListIndexStaleAfterMs(env);
  const indexUpdatedAtMs = Date.parse(safeStr(indexRead?.index?.updated_at ?? indexRead?.index?.updatedAt, 80));
  const indexStale = staleAfterMs > 0 && (!Number.isFinite(indexUpdatedAtMs) || (Date.now() - indexUpdatedAtMs) > staleAfterMs);
  if (indexStale) {
    return { ok: false, error: "company_bookings_list_index_stale" };
  }

  const sourceItems = Array.isArray(indexRead?.index?.items) ? indexRead.index.items : [];
  const candidateIds = new Set();
  for (const entry of sourceItems) {
    const bookingId = safeStr(entry?.booking_id ?? entry?.bookingId, 160);
    if (bookingId) candidateIds.add(bookingId);
  }

  // G1 reuse: canonicalize payment-shadow ids before producing rows. We use
  // the [ADMIN_DRIVER_PREVIEW] log tag here so admin-preview traces are
  // attributable to this surface in production logs.
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
          `[ADMIN_DRIVER_PREVIEW][SHADOW_CANONICALIZED] shadow=${_bookingIntentMask(bookingId)} canonical=${_bookingIntentMask(canonical)}`,
        );
        canonicalCandidateIds.add(canonical);
      } else {
        console.log(
          `[ADMIN_DRIVER_PREVIEW][SHADOW_SKIPPED] shadow=${_bookingIntentMask(bookingId)} reason=no_canonical_reference`,
        );
      }
      continue;
    }
    canonicalCandidateIds.add(bookingId);
  }

  const nowMs = Date.now();
  const actionableGraceMs = 6 * 60 * 60 * 1000;
  const cutoffMs = nowMs - actionableGraceMs;
  const out = [];
  let assignedCount = 0;
  let availableCount = 0;
  const seenAssignedKeys = new Set();

  for (const bookingId of canonicalCandidateIds) {
    let rec = recordCache.get(bookingId);
    if (!rec) {
      rec = await env.BOOKING_KV.get(`booking:${bookingId}`, { type: "json" });
    }
    if (!rec || typeof rec !== "object") continue;
    if (!bookingMatchesRequestedTenantScope(rec, tenantScope)) continue;
    if (_driverAvailableUnassignedRowHidden(rec)) continue;

    // P0-FIELD-REPAIR-1 (A1): this preview mirrors the driver planned/open
    // view, so it applies the same "street/direct is never planned" contract.
    // The canonical record stays intact for company bookings and history.
    const rows = _excludeStreetDirectFromPlannedProjection(
      _flattenBookingForRidesListWithOperationalLegs(bookingId, rec),
      { logTag: "ADMIN_DRIVER_PREVIEW" },
    );

    // Pass 1: include rows assigned to the requested driver / vehicle. Past
    // pickups still surface for operational visibility (admin context).
    if (targetDriverId || targetVehicleId) {
      for (const row of rows) {
        const rowDriverId = safeStr(row?.assigned_driver_id ?? row?.assignedDriverId, 96);
        const rowVehicleId = safeStr(row?.assigned_vehicle_id ?? row?.assignedVehicleId, 128);
        const driverMatch = !!(targetDriverId && rowDriverId && targetDriverId === rowDriverId);
        const vehicleMatch = !!(targetVehicleId && rowVehicleId && targetVehicleId === rowVehicleId);
        if (!driverMatch && !vehicleMatch) continue;
        if (
          row.status === "COMPLETED" ||
          row.status === "CANCELLED" ||
          isTerminalLifecycleStatus(row?.status)
        ) {
          continue;
        }
        const pickupTs = row.pickup_iso ? Date.parse(row.pickup_iso) : Number.NaN;
        if (!Number.isFinite(pickupTs)) continue;
        if (pickupTs < cutoffMs) continue;
        const dedupeKey = _driverBookingsRowDedupeKey(row);
        if (seenAssignedKeys.has(dedupeKey)) continue;
        seenAssignedKeys.add(dedupeKey);
        out.push(row);
        assignedCount += 1;
      }
    }

    // Pass 2: include available-unassigned rows from the dispatch pool. Reuse
    // the exact same eligibility checks as `_appendDriverAvailableUnassignedBookings`.
    if (!_driverAvailableUnassignedCanonicalRecord(bookingId, rec)) continue;
    for (const row of rows) {
      const dedupeKey = _driverBookingsRowDedupeKey(row);
      if (seenAssignedKeys.has(dedupeKey)) continue;
      const rowDriverId = safeStr(row?.assigned_driver_id ?? row?.assignedDriverId, 96);
      if (rowDriverId) continue;
      const rowVehicleId = safeStr(row?.assigned_vehicle_id ?? row?.assignedVehicleId, 128);
      if (rowVehicleId) continue;
      if (
        row.status === "COMPLETED" ||
        row.status === "CANCELLED" ||
        isTerminalLifecycleStatus(row?.status)
      ) {
        continue;
      }
      if (!_driverAvailableUnassignedRowIsOpenLike(row, rec)) continue;
      const pickupTs = row.pickup_iso ? Date.parse(row.pickup_iso) : Number.NaN;
      if (!Number.isFinite(pickupTs)) continue;
      if (pickupTs < cutoffMs) continue;
      if (!_driverAvailableUnassignedPaymentEligible(rec, row)) continue;

      out.push({
        ...row,
        available_unassigned: true,
        availableUnassigned: true,
      });
      seenAssignedKeys.add(dedupeKey);
      availableCount += 1;
    }
  }

  // G1 reuse: belt-and-braces canonical-trip dedupe to collapse residual
  // duplicates. Reuses the same helper but with [ADMIN_DRIVER_PREVIEW] tag.
  const dedupedOut = _dedupeBookingListRowsByCanonicalTripSignature(out, {
    logTag: "ADMIN_DRIVER_PREVIEW",
  });

  dedupedOut.sort((a, b) => {
    const ta = a.pickup_iso ? Date.parse(a.pickup_iso) : Number.POSITIVE_INFINITY;
    const tb = b.pickup_iso ? Date.parse(b.pickup_iso) : Number.POSITIVE_INFINITY;
    return ta - tb;
  });

  return {
    ok: true,
    items: dedupedOut.slice(0, lim),
    assigned: assignedCount,
    available: availableCount,
  };
}
