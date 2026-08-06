/* Fluxidi booking flatten / read-model pipeline (BW-M8c).
 *
 * Verbatim extraction from workers/booking/fluxidi_booking_worker.js — no
 * behavior change. This module owns the read-model / projection pipeline
 * that produces rides-list rows from booking records, plus its
 * pipeline-adjacent pure helpers (return-leg synthesis, per-leg
 * enrichment, tenant-scope matching, tracking-id resolution).
 *
 * Exported scope:
 *   - `_flattenBookingForRidesList`
 *   - `_bookingOperationalLegsForReadModel`
 *   - `_flattenOperationalLegForRidesList`
 *   - `_flattenBookingForRidesListWithOperationalLegs`
 *   - `bookingMatchesRequestedTenantScope`
 *   - `isLegacyTenantScopeRequest`   (only caller is bookingMatches...; kept
 *                                     exported so main's other call site keeps
 *                                     working after the move)
 *   - `_projectionLifecycleStatusFromRecord`
 *   - `enrichBookingRecordOperationalLegsForReadModel`
 *   - `_materializeOperationalLegIfMissingFromReadModel`
 *   - `_synthesizeOutboundOperationalLegForReadModel`
 *   - `_synthesizeReturnOperationalLegForReadModel`
 *   - `_estimateReturnPickupIsoForReadModel`
 *   - `_bookingOperationalLegsFromRecord` (BW-M8c: NOT re-exported — kept
 *                                          in main; module has its own copy)
 *   - `_bookingAssignedDriverContactFromRecord`
 *   - `_parentAssignmentEnrichmentFromLegs`
 *   - `_operationalLegFleetEnrichmentFields`
 *   - `_normalizeAssignedDriverSummaryForLeg`
 *   - `_operationalLegTypeFromEntry`
 *   - `_roundtripDispatchModeFromRecord`
 *   - `_parentAssignmentModeFromRecord`
 *   - `_bookingWaitMinFromRecord`
 *   - `_bookingReturnEnabledFromRecord`
 *   - `_bookingReturnFromFromRecord`
 *   - `_bookingReturnToFromRecord`
 *   - `_bookingReturnPickupIsoFromRecord`
 *   - `_bookingExplicitReturnFromFromRecord`
 *   - `_bookingExplicitReturnToFromRecord`
 *   - `_bookingReturnPriceInclVatFromRecord`
 *   - `_bookingMainPriceInclVatFromRecord`
 *   - `_bookingHasReturnDisplayData`
 *   - `_trackingSyncCanonicalBookingId`
 *
 * Explicitly NOT moved (STOP rule — KV writers, dispatch/booking/payment
 * mutations, or unrelated domains):
 *   - listDriverBookingsAuthoritative,
 *     listAdminDriverBookingsPreviewAuthoritative — orchestrators (BW-M7C).
 *   - dispatch open pool, driver assign, payment lifecycle,
 *     document/Billit/Peppol/Chiron, dev reset — untouched.
 *
 * Widely-used base helpers with many external callers in main are kept
 * private module-local BYTE-IDENTICAL copies (BW-M7B pattern). This
 * preserves the acyclic import graph while avoiding a large touch-set of
 * call sites in main:
 *   - `_bookingMutationReadPath`, `bookingAssignedVehicleId`,
 *     `bookingAssignedDriverId`, `_bookingOperationalLegsFromRecord`,
 *     `_roundtripDispatchContextFromAny`, `parseDurationMin`,
 *     `normalizeService`, `_operationalLegServiceValue`,
 *     `_normalizeCustomerCancellationServiceBucket`,
 *     `_buildOperationalLegRecord`, `bookingPickupIsoFromRecord`.
 *
 * Acyclic import graph:
 *   parsing_utils.js           ─►  booking_read_model.js
 *   auth_scope.js              ─►  booking_read_model.js
 *   booking_utils.js           ─►  booking_read_model.js
 *   booking_payment_classify.js ─► booking_read_model.js
 *   compliance_events.js is transitively required by
 *     booking_payment_classify.js but not directly by this module.
 *   booking_read_model.js does NOT import back into main.
 */

import { safeStr } from "./parsing_utils.js";
import { _scopeText, resolveBookingTenantScopeFromRecord } from "./auth_scope.js";
import {
  _pick,
  _bookingIntentMask,
  _normLifecycleStatus,
  isTerminalLifecycleStatus,
} from "./booking_utils.js";
import { _resolveBookingRecordPaymentStatusForProjection } from "./booking_payment_classify.js";

/* =====================================================================
 * PRIVATE MODULE-LOCAL COPIES (byte-identical to main).
 *
 * These helpers are called by exported functions below. They are NOT
 * exported so main's existing declarations remain the single source of
 * truth for their ~135 combined call sites in main. Duplicating them
 * here avoids either (a) touching ~135 main call sites in a single BW
 * patch or (b) creating a bidirectional module ↔ main import graph.
 * ===================================================================== */

// Byte-identical to `_bookingMutationReadPath` in fluxidi_booking_worker.js.
function _bookingMutationReadPath(root, paths = []) {
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

// Byte-identical to `bookingAssignedVehicleId` in fluxidi_booking_worker.js.
function bookingAssignedVehicleId(rec) {
  return _bookingMutationReadPath(rec, [
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

// Byte-identical to `bookingAssignedDriverId` in fluxidi_booking_worker.js.
function bookingAssignedDriverId(rec) {
  return _bookingMutationReadPath(rec, [
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

// Byte-identical to `_bookingOperationalLegsFromRecord` in fluxidi_booking_worker.js.
function _bookingOperationalLegsFromRecord(rec) {
  if (!rec || typeof rec !== "object") return [];
  const topLevel = Array.isArray(rec?.operational_legs)
    ? rec.operational_legs
    : (Array.isArray(rec?.operationalLegs) ? rec.operationalLegs : null);
  const bookingLevel = Array.isArray(_pick(rec, ["booking", "operational_legs"], null))
    ? _pick(rec, ["booking", "operational_legs"], null)
    : (Array.isArray(_pick(rec, ["booking", "operationalLegs"], null))
      ? _pick(rec, ["booking", "operationalLegs"], null)
      : null);
  const source = topLevel || bookingLevel || [];
  return source
    .map((entry) => (entry && typeof entry === "object" ? entry : null))
    .filter((entry) => !!entry);
}

// Byte-identical to `parseDurationMin` in fluxidi_booking_worker.js.
function parseDurationMin(x, fallback = 0) {
  if (x == null) return fallback;
  if (typeof x === "number" && Number.isFinite(x)) return Math.trunc(x);
  const s = String(x).trim();
  if (!s) return fallback;
  const m = s.match(/(\d+)/);
  if (!m) return fallback;
  const n = Number(m[1]);
  return Number.isFinite(n) ? Math.trunc(n) : fallback;
}

// Byte-identical to `normalizeService` in fluxidi_booking_worker.js.
function normalizeService(svc) {
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

// Byte-identical to `_operationalLegServiceValue` in fluxidi_booking_worker.js.
function _operationalLegServiceValue(serviceRaw) {
  const normalized = normalizeService(serviceRaw);
  if (normalized === "passenger") return "taxi";
  return normalized;
}

// Byte-identical to `_normalizeCustomerCancellationServiceBucket` in
// fluxidi_booking_worker.js.
function _normalizeCustomerCancellationServiceBucket(value) {
  const token = safeStr(value, 64).toLowerCase().replace(/[^a-z0-9_]+/g, "_");
  if (!token) return null;
  if (token === "airport" || token === "luchthaven" || token === "airport_transfer") return "airport";
  if (token === "business" || token === "zakelijk") return "business";
  if (
    token === "private" ||
    token === "taxi" ||
    token === "passenger" ||
    token === "personenvervoer"
  ) {
    return "private";
  }
  return null;
}

// Byte-identical to `_buildOperationalLegRecord` in fluxidi_booking_worker.js.
function _buildOperationalLegRecord({
  parentBookingId,
  legKey,
  legType,
  service,
  serviceBucket = null,
  serviceType = null,
  airportDirection = null,
  airportTransfer = null,
  pickupIso,
  from,
  to,
  distanceKm = null,
  durationMin = null,
  priceInclVat = null,
  priceExVat = null,
  priceVat = null,
  fixedFareApplied = null,
  fixedFareRuleId = null,
  pricingSource = null,
  assignedDriverId = null,
  assignedVehicleId = null,
  lifecycleStatus = "pending",
  createdAt = "",
  updatedAt = "",
} = {}) {
  const bookingId = safeStr(parentBookingId, 160);
  const normalizedLegKey = safeStr(legKey, 24).toUpperCase() || "LEG";
  const legId = bookingId ? `${bookingId}:${normalizedLegKey}` : "";
  const safeLifecycle = safeStr(lifecycleStatus, 24).toLowerCase() || "pending";
  const normalizedLegType = legType === "return" ? "return" : "outbound";
  const normalizedService = _operationalLegServiceValue(service);
  const normalizedServiceBucket =
    _normalizeCustomerCancellationServiceBucket(serviceBucket) ||
    (normalizedService === "airport"
      ? "airport"
      : (normalizedService === "business" ? "business" : "private"));
  const normalizedServiceType = safeStr(serviceType, 64) || normalizedService;
  const normalizedAirportDirection = safeStr(airportDirection, 24) || null;
  const normalizedAirportTransfer =
    airportTransfer === true ||
    (airportTransfer && typeof airportTransfer === "object") ||
    normalizedServiceBucket === "airport";
  return {
    leg_id: legId || null,
    legId: legId || null,
    parent_booking_id: bookingId || null,
    parentBookingId: bookingId || null,
    leg_type: normalizedLegType,
    legType: normalizedLegType,
    service: normalizedService,
    service_type: normalizedServiceType,
    serviceType: normalizedServiceType,
    service_bucket: normalizedServiceBucket,
    serviceBucket: normalizedServiceBucket,
    ...(normalizedAirportDirection
      ? {
          airport_direction: normalizedAirportDirection,
          airportDirection: normalizedAirportDirection,
        }
      : {}),
    ...(normalizedAirportTransfer
      ? {
          airport_transfer: airportTransfer === true ? true : (airportTransfer || true),
          airportTransfer: airportTransfer === true ? true : (airportTransfer || true),
        }
      : {}),
    pickup_iso: safeStr(pickupIso, 80) || null,
    pickupIso: safeStr(pickupIso, 80) || null,
    from: safeStr(from, 320) || "",
    to: safeStr(to, 320) || "",
    distance_km: Number.isFinite(Number(distanceKm)) ? Number(distanceKm) : null,
    distanceKm: Number.isFinite(Number(distanceKm)) ? Number(distanceKm) : null,
    duration_min: Number.isFinite(Number(durationMin)) ? Number(durationMin) : null,
    durationMin: Number.isFinite(Number(durationMin)) ? Number(durationMin) : null,
    price_incl_vat: Number.isFinite(Number(priceInclVat)) ? Number(priceInclVat) : null,
    priceInclVat: Number.isFinite(Number(priceInclVat)) ? Number(priceInclVat) : null,
    price_ex_vat: Number.isFinite(Number(priceExVat)) ? Number(priceExVat) : null,
    priceExVat: Number.isFinite(Number(priceExVat)) ? Number(priceExVat) : null,
    price_vat: Number.isFinite(Number(priceVat)) ? Number(priceVat) : null,
    priceVat: Number.isFinite(Number(priceVat)) ? Number(priceVat) : null,
    fixed_fare_applied:
      typeof fixedFareApplied === "boolean" ? fixedFareApplied : null,
    fixedFareApplied:
      typeof fixedFareApplied === "boolean" ? fixedFareApplied : null,
    fixed_fare_rule_id: safeStr(fixedFareRuleId, 120) || null,
    fixedFareRuleId: safeStr(fixedFareRuleId, 120) || null,
    pricing_source: safeStr(pricingSource, 80) || null,
    pricingSource: safeStr(pricingSource, 80) || null,
    assigned_driver_id: safeStr(assignedDriverId, 96) || null,
    assignedDriverId: safeStr(assignedDriverId, 96) || null,
    assigned_vehicle_id: safeStr(assignedVehicleId, 128) || null,
    assignedVehicleId: safeStr(assignedVehicleId, 128) || null,
    status: safeLifecycle,
    lifecycle_status: safeLifecycle,
    lifecycleStatus: safeLifecycle,
    created_at: safeStr(createdAt, 80) || null,
    createdAt: safeStr(createdAt, 80) || null,
    updated_at: safeStr(updatedAt, 80) || null,
    updatedAt: safeStr(updatedAt, 80) || null,
  };
}

// Byte-identical to `bookingPickupIsoFromRecord` in fluxidi_booking_worker.js.
function bookingPickupIsoFromRecord(rec) {
  return safeStr(
    rec?.booking?.pickupStartIso ||
      rec?.booking?.pickup_iso ||
      rec?.quote?.pickup_iso ||
      rec?.payload?.pickup_iso ||
      rec?.payload?.pickupIso,
  );
}

// Byte-identical to `_roundtripDispatchContextFromAny` in fluxidi_booking_worker.js.
function _roundtripDispatchContextFromAny(source) {
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
  const waitMin = parseDurationMin(
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
  const service = normalizeService(
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

/* =====================================================================
 * EXPORTS
 * ===================================================================== */

/* ---- Tenant-scope matching ------------------------------------------ */

export function isLegacyTenantScopeRequest(requestedScope) {
  const legacyId = "fluxidi";
  const requestedTenant = _scopeText(requestedScope?.tenant_id);
  const requestedCompany = _scopeText(requestedScope?.company_id);
  return requestedTenant === legacyId || requestedCompany === legacyId;
}

/**
 * LEGACY soft matcher — DO NOT use for tenant-visible lists, dispatch,
 * customer hydrate, or any new code.
 *
 * RELEASE-P1: company/driver/customer lists and dispatch open-pool use
 * `bookingMatchesRequiredTenantCompanyScope` (strict) exclusively.
 * This soft helper remains only for a few non-list internal paths that
 * have not yet been migrated; it must never authorize mutations alone.
 *
 * Soft gaps vs strict:
 * - unscoped records match only when the request is legacy `fluxidi`;
 * - missing company on one side can still match when tenant matches.
 */
export function bookingMatchesRequestedTenantScope(rec, requestedScope) {
  if (!requestedScope?.hasScope) return false;
  const recordScope = resolveBookingTenantScopeFromRecord(rec);
  // Legacy MVP bookings may not have tenant/company metadata yet.
  // Keep those readable/updatable only for explicit legacy scope requests.
  if (!recordScope.hasScope) return isLegacyTenantScopeRequest(requestedScope);

  if (
    requestedScope.tenant_id &&
    recordScope.tenant_id &&
    requestedScope.tenant_id !== recordScope.tenant_id
  ) {
    return false;
  }
  if (
    requestedScope.company_id &&
    recordScope.company_id &&
    requestedScope.company_id !== recordScope.company_id
  ) {
    return false;
  }
  return true;
}

/* ---- Tracking-id canonical resolver ---------------------------------- */

export function _trackingSyncCanonicalBookingId(bookingId, rec) {
  const bookingObj = rec?.booking && typeof rec.booking === "object" ? rec.booking : {};
  const payloadObj = rec?.payload && typeof rec.payload === "object" ? rec.payload : {};
  const candidates = [
    rec?.booking_id,
    rec?.bookingId,
    bookingObj?.booking_id,
    bookingObj?.bookingId,
    payloadObj?.__booking_id,
    payloadObj?.booking_id,
    payloadObj?.bookingId,
    rec?.id,
    bookingObj?.id,
    bookingId,
  ];
  for (const value of candidates) {
    const token = safeStr(value, 160);
    if (!token) continue;
    if (/^[0-9]{4}-[0-9]{2}-[0-9]{3,}$/i.test(token)) return token;
  }
  for (const value of candidates) {
    const token = safeStr(value, 160);
    if (token) return token;
  }
  return "";
}

/* ---- Per-leg enrichment helpers -------------------------------------- */

// Read-model helper: extracts the additive vehicle enrichment fields that
// _stampOperationalLegFleetAssignment writes onto an operational leg.
// Returns an object whose keys are intended to be Object.assign-ed onto a
// rides-list row, or null when the leg carries no extra metadata beyond
// its id. Strictly readonly; never mutates the input leg.
export function _operationalLegFleetEnrichmentFields(leg) {
  if (!leg || typeof leg !== "object") return null;
  const vehicleName = safeStr(leg.assigned_vehicle_name ?? leg.assignedVehicleName, 160);
  const brandModel = safeStr(
    leg.assigned_vehicle_brand_model ?? leg.assignedVehicleBrandModel,
    160,
  );
  const licensePlate = safeStr(
    leg.assigned_vehicle_license_plate ??
      leg.assignedVehicleLicensePlate ??
      leg.license_plate ??
      leg.licensePlate,
    64,
  );
  const color = safeStr(leg.assigned_vehicle_color ?? leg.assignedVehicleColor, 80);
  const exploitationLicenseNumber = safeStr(
    leg.assigned_vehicle_exploitation_license_number ??
      leg.assignedVehicleExploitationLicenseNumber,
    120,
  );
  const vehicleRegistrationNumber = safeStr(
    leg.assigned_vehicle_registration_number ??
      leg.assignedVehicleRegistrationNumber,
    120,
  );
  const assignedVehicle =
    leg.assigned_vehicle && typeof leg.assigned_vehicle === "object"
      ? leg.assigned_vehicle
      : (leg.assignedVehicle && typeof leg.assignedVehicle === "object"
        ? leg.assignedVehicle
        : null);
  const out = {};
  if (assignedVehicle) {
    out.assigned_vehicle = assignedVehicle;
    out.assignedVehicle = assignedVehicle;
  }
  if (vehicleName) {
    out.assigned_vehicle_name = vehicleName;
    out.assignedVehicleName = vehicleName;
  }
  if (brandModel) {
    out.assigned_vehicle_brand_model = brandModel;
    out.assignedVehicleBrandModel = brandModel;
  }
  if (licensePlate) {
    out.assigned_vehicle_license_plate = licensePlate;
    out.assignedVehicleLicensePlate = licensePlate;
    out.license_plate = licensePlate;
    out.licensePlate = licensePlate;
  }
  if (color) {
    out.assigned_vehicle_color = color;
    out.assignedVehicleColor = color;
  }
  if (exploitationLicenseNumber) {
    out.assigned_vehicle_exploitation_license_number = exploitationLicenseNumber;
    out.assignedVehicleExploitationLicenseNumber = exploitationLicenseNumber;
  }
  if (vehicleRegistrationNumber) {
    out.assigned_vehicle_registration_number = vehicleRegistrationNumber;
    out.assignedVehicleRegistrationNumber = vehicleRegistrationNumber;
  }
  return Object.keys(out).length === 0 ? null : out;
}

// Resolves the parent's vehicle enrichment by finding an operational leg
// whose assigned_vehicle_id matches `parentVehicleId`. For one-way
// bookings the single leg's enrichment is the parent's. For
// continuous_wait the legs share the vehicle. For split_no_wait the
// parent's "summary" assignment maps to the outbound leg's vehicle and
// its enrichment is the correct one to surface alongside the parent's id.
// Returns null when no match exists or when the matching leg carries no
// metadata beyond its id.
export function _parentAssignmentEnrichmentFromLegs(rec, parentVehicleId) {
  const wantedVehicleId = safeStr(parentVehicleId, 128);
  if (!wantedVehicleId) return null;
  const legs = _bookingOperationalLegsFromRecord(rec);
  if (!legs.length) return null;
  const match = legs.find((leg) => {
    const legVehicleId = safeStr(leg?.assigned_vehicle_id ?? leg?.assignedVehicleId, 128);
    return legVehicleId && legVehicleId === wantedVehicleId;
  });
  if (!match) return null;
  return _operationalLegFleetEnrichmentFields(match);
}

// Reads the {name, phone} contact for the parent's assigned driver from
// the record, preferring whichever layer (rec, rec.booking) carries the
// richer summary. Returns null when nothing usable is present so the
// flattener can omit the field rather than emit empty strings.
export function _bookingAssignedDriverContactFromRecord(rec) {
  if (!rec || typeof rec !== "object") return null;
  const candidates = [
    rec.assigned_driver,
    rec.assignedDriver,
    _pick(rec, ["booking", "assigned_driver"], null),
    _pick(rec, ["booking", "assignedDriver"], null),
  ];
  for (const candidate of candidates) {
    const summary = _normalizeAssignedDriverSummaryForLeg(candidate);
    if (summary && (summary.name || summary.phone)) return summary;
  }
  return null;
}

// Reads the dispatch-mode token stamped by
// _applySplitRoundtripLegAssignmentsToRecord / ensurePaidOpenBookingAuto
// Dispatched. Returns "" when nothing is stamped (e.g. legacy records or
// single-leg bookings whose mode is implicit). Never invents a mode.
export function _roundtripDispatchModeFromRecord(rec) {
  return safeStr(
    rec?.roundtrip_dispatch_mode ??
      rec?.roundtripDispatchMode ??
      _pick(rec, ["booking", "roundtrip_dispatch_mode"], null) ??
      _pick(rec, ["booking", "roundtripDispatchMode"], null) ??
      _pick(rec, ["payload", "roundtrip_dispatch_mode"], null) ??
      _pick(rec, ["payload", "roundtripDispatchMode"], null),
    24,
  );
}

export function _parentAssignmentModeFromRecord(rec) {
  return safeStr(
    rec?.parent_assignment_mode ??
      rec?.parentAssignmentMode ??
      _pick(rec, ["booking", "parent_assignment_mode"], null) ??
      _pick(rec, ["booking", "parentAssignmentMode"], null) ??
      _pick(rec, ["payload", "parent_assignment_mode"], null) ??
      _pick(rec, ["payload", "parentAssignmentMode"], null),
    24,
  );
}

export function _bookingWaitMinFromRecord(rec) {
  const raw =
    _pick(rec, ["booking", "wait_min"], null) ??
    _pick(rec, ["booking", "waitMin"], null) ??
    rec?.wait_min ??
    rec?.waitMin ??
    _pick(rec, ["payload", "wait_min"], null) ??
    _pick(rec, ["payload", "waitMin"], null) ??
    _pick(rec, ["quote", "wait_min"], null);
  if (raw == null || raw === "") return null;
  const num = Number(raw);
  if (!Number.isFinite(num) || num < 0) return null;
  return Math.max(0, Math.trunc(num));
}

// Normalizes any "driver" shape (allocator result, vehicle inventory entry,
// stamped leg field) into a stable {driver_id,name,phone} summary. Strictly
// readonly; returns null when no usable identity is present so callers can
// detect "no enrichment available" without inventing values.
export function _normalizeAssignedDriverSummaryForLeg(driver) {
  if (!driver || typeof driver !== "object") return null;
  const driverId = safeStr(
    driver.driver_id ?? driver.driverId ?? driver.id,
    96,
  );
  const name = safeStr(
    driver.name ?? driver.full_name ?? driver.fullName ?? driver.display_name,
    160,
  );
  const phone = safeStr(driver.phone ?? driver.phone_number ?? driver.phoneNumber, 64);
  if (!driverId && !name && !phone) return null;
  return {
    driver_id: driverId || null,
    name: name || null,
    phone: phone || null,
  };
}

/* ---- Return / roundtrip readers -------------------------------------- */

export function _operationalLegTypeFromEntry(leg) {
  return safeStr(leg?.leg_type ?? leg?.legType, 24).toLowerCase() === "return"
    ? "return"
    : "outbound";
}

export function _bookingReturnEnabledFromRecord(rec) {
  return !!_roundtripDispatchContextFromAny(rec).returnEnabled;
}

export function _bookingReturnFromFromRecord(rec) {
  const booking = rec?.booking && typeof rec.booking === "object" ? rec.booking : {};
  return (
    safeStr(
      rec?.return_from ??
        rec?.returnFrom ??
        booking?.return_from ??
        booking?.returnFrom ??
        _pick(rec, ["quote", "return", "from"], null) ??
        _pick(rec, ["quote", "return_from"], null) ??
        _pick(rec, ["payload", "return_from"], null) ??
        _pick(rec, ["payload", "returnFrom"], null),
      320,
    ) ||
    safeStr(booking?.to ?? _pick(rec, ["quote", "to"], null), 320)
  );
}

export function _bookingReturnToFromRecord(rec) {
  const booking = rec?.booking && typeof rec.booking === "object" ? rec.booking : {};
  return (
    safeStr(
      rec?.return_to ??
        rec?.returnTo ??
        booking?.return_to ??
        booking?.returnTo ??
        _pick(rec, ["quote", "return", "to"], null) ??
        _pick(rec, ["quote", "return_to"], null) ??
        _pick(rec, ["payload", "return_to"], null) ??
        _pick(rec, ["payload", "returnTo"], null),
      320,
    ) ||
    safeStr(booking?.from ?? _pick(rec, ["quote", "from"], null), 320)
  );
}

export function _bookingReturnPickupIsoFromRecord(rec) {
  const booking = rec?.booking && typeof rec.booking === "object" ? rec.booking : {};
  return safeStr(
    rec?.return_pickup_iso ??
      rec?.returnPickupIso ??
      booking?.return_pickup_iso ??
      booking?.returnPickupIso ??
      _pick(rec, ["quote", "return", "pickup_iso"], null) ??
      _pick(rec, ["payload", "return_pickup_iso"], null) ??
      _pick(rec, ["payload", "returnPickupIso"], null),
    80,
  );
}

export function _bookingReturnPriceInclVatFromRecord(rec) {
  const booking = rec?.booking && typeof rec.booking === "object" ? rec.booking : {};
  const raw =
    rec?.price_incl_vat_return ??
    rec?.priceInclVatReturn ??
    booking?.price_incl_vat_return ??
    booking?.priceInclVatReturn ??
    _pick(rec, ["quote", "price_incl_vat_return"], null) ??
    _pick(rec, ["quote", "pricing_return", "price_incl_vat"], null) ??
    _pick(rec, ["quote", "return", "price_incl_vat"], null) ??
    _pick(rec, ["payload", "price_incl_vat_return"], null);
  const num = Number(raw);
  return Number.isFinite(num) ? num : null;
}

export function _bookingMainPriceInclVatFromRecord(rec) {
  const booking = rec?.booking && typeof rec.booking === "object" ? rec.booking : {};
  const raw =
    rec?.price_incl_vat_main ??
    rec?.priceInclVatMain ??
    booking?.price_incl_vat_main ??
    booking?.priceInclVatMain ??
    _pick(rec, ["quote", "price_incl_vat_main"], null) ??
    _pick(rec, ["quote", "pricing_main", "price_incl_vat"], null) ??
    _pick(rec, ["payload", "price_incl_vat_main"], null) ??
    booking?.price_incl_vat ??
    _pick(rec, ["quote", "pricing", "price_incl_vat"], null);
  const num = Number(raw);
  return Number.isFinite(num) ? num : null;
}

// Explicit return origin/destination ONLY (no outbound-address fallback).
// _bookingReturnFromFromRecord / _bookingReturnToFromRecord intentionally fall
// back to the swapped outbound addresses (return_from -> outbound.to,
// return_to -> outbound.from) so that, once we KNOW a leg is a return, it gets
// sensible from/to. They must NOT be used to DECIDE whether a return exists,
// because the fallback makes them truthy for every one-way booking.
export function _bookingExplicitReturnFromFromRecord(rec) {
  const booking = rec?.booking && typeof rec.booking === "object" ? rec.booking : {};
  return safeStr(
    rec?.return_from ??
      rec?.returnFrom ??
      booking?.return_from ??
      booking?.returnFrom ??
      _pick(rec, ["quote", "return", "from"], null) ??
      _pick(rec, ["quote", "return_from"], null) ??
      _pick(rec, ["payload", "return_from"], null) ??
      _pick(rec, ["payload", "returnFrom"], null),
    320,
  );
}

export function _bookingExplicitReturnToFromRecord(rec) {
  const booking = rec?.booking && typeof rec.booking === "object" ? rec.booking : {};
  return safeStr(
    rec?.return_to ??
      rec?.returnTo ??
      booking?.return_to ??
      booking?.returnTo ??
      _pick(rec, ["quote", "return", "to"], null) ??
      _pick(rec, ["quote", "return_to"], null) ??
      _pick(rec, ["payload", "return_to"], null) ??
      _pick(rec, ["payload", "returnTo"], null),
    320,
  );
}

export function _bookingHasReturnDisplayData(rec) {
  // A RETURN leg may only be displayed/synthesized when there is a GENUINE
  // return signal:
  //   - return_enabled === true (booking/payload/quote), or
  //   - an explicit return pickup iso / return schedule, or
  //   - a positive return price, or
  //   - an EXPLICIT return origin AND destination.
  // We deliberately do NOT use _bookingReturnFromFromRecord /
  // _bookingReturnToFromRecord here: their swapped-outbound-address fallback
  // would flag every one-way booking as a roundtrip and produce a phantom
  // RETURN leg. pricing_profile.return_enabled is also intentionally NOT
  // consulted (only the booking's own return flags).
  if (_bookingReturnEnabledFromRecord(rec)) return true;
  if (_bookingReturnPickupIsoFromRecord(rec)) return true;
  const returnPrice = _bookingReturnPriceInclVatFromRecord(rec);
  if (returnPrice != null && returnPrice > 0) return true;
  const explicitReturnFrom = _bookingExplicitReturnFromFromRecord(rec);
  const explicitReturnTo = _bookingExplicitReturnToFromRecord(rec);
  return !!(explicitReturnFrom && explicitReturnTo);
}

export function _estimateReturnPickupIsoForReadModel(rec, outboundPickupIso) {
  const explicit = _bookingReturnPickupIsoFromRecord(rec);
  if (explicit) return explicit;
  const waitMin = _roundtripDispatchContextFromAny(rec).normalizedWaitMin;
  if (!outboundPickupIso || waitMin <= 0) return "";
  const baseMs = Date.parse(outboundPickupIso);
  if (!Number.isFinite(baseMs)) return "";
  return new Date(baseMs + waitMin * 60 * 1000).toISOString();
}

/* ---- Operational-leg synthesis for read-model ------------------------ */

export function _synthesizeOutboundOperationalLegForReadModel(rec, bookingId) {
  const booking = rec?.booking && typeof rec.booking === "object" ? rec.booking : {};
  const pickupIso = bookingPickupIsoFromRecord(rec);
  const from = _pick(rec, ["quote", "from"], null) ?? booking?.from ?? "";
  const to = _pick(rec, ["quote", "to"], null) ?? booking?.to ?? "";
  if (!from || !to) return null;
  const parentStatus = _normLifecycleStatus(rec?.status ?? rec?.stage ?? "PENDING");
  return _buildOperationalLegRecord({
    parentBookingId: bookingId,
    legKey: "OUTBOUND",
    legType: "outbound",
    service: booking?.service ?? rec?.service,
    pickupIso,
    from,
    to,
    priceInclVat: _bookingMainPriceInclVatFromRecord(rec),
    assignedDriverId: bookingAssignedDriverId(rec),
    assignedVehicleId: bookingAssignedVehicleId(rec),
    lifecycleStatus: parentStatus.toLowerCase(),
    createdAt: safeStr(rec?.created_at ?? rec?.createdAt ?? booking?.created_at, 80),
    updatedAt: safeStr(rec?.updated_at ?? rec?.updatedAt ?? booking?.updated_at, 80),
  });
}

export function _synthesizeReturnOperationalLegForReadModel(rec, bookingId, existingLegs = []) {
  if (!_bookingHasReturnDisplayData(rec)) return null;
  const outboundLeg = (existingLegs || []).find(
    (leg) => _operationalLegTypeFromEntry(leg) === "outbound",
  );
  const booking = rec?.booking && typeof rec.booking === "object" ? rec.booking : {};
  const outboundPickup =
    safeStr(outboundLeg?.pickup_iso ?? outboundLeg?.pickupIso, 80) ||
    bookingPickupIsoFromRecord(rec);
  const returnFrom = _bookingReturnFromFromRecord(rec);
  const returnTo = _bookingReturnToFromRecord(rec);
  if (!returnFrom || !returnTo) return null;
  const ctx = _roundtripDispatchContextFromAny(rec);
  const parentStatus = _normLifecycleStatus(rec?.status ?? rec?.stage ?? "PENDING");
  let returnLifecycle = parentStatus.toLowerCase();
  if (ctx.normalizedWaitMin > 0 && outboundLeg) {
    returnLifecycle =
      safeStr(
        outboundLeg?.lifecycle_status ??
          outboundLeg?.lifecycleStatus ??
          outboundLeg?.status,
        24,
      ).toLowerCase() || returnLifecycle;
  }
  return _buildOperationalLegRecord({
    parentBookingId: bookingId,
    legKey: "RETURN",
    legType: "return",
    service: outboundLeg?.service ?? booking?.service ?? rec?.service,
    pickupIso: _estimateReturnPickupIsoForReadModel(rec, outboundPickup),
    from: returnFrom,
    to: returnTo,
    priceInclVat: _bookingReturnPriceInclVatFromRecord(rec),
    assignedDriverId:
      safeStr(outboundLeg?.assigned_driver_id ?? outboundLeg?.assignedDriverId, 96) ||
      bookingAssignedDriverId(rec),
    assignedVehicleId:
      safeStr(outboundLeg?.assigned_vehicle_id ?? outboundLeg?.assignedVehicleId, 128) ||
      bookingAssignedVehicleId(rec),
    lifecycleStatus: returnLifecycle,
    createdAt: safeStr(rec?.created_at ?? rec?.createdAt ?? booking?.created_at, 80),
    updatedAt: safeStr(rec?.updated_at ?? rec?.updatedAt ?? booking?.updated_at, 80),
  });
}

export function _bookingOperationalLegsForReadModel(rec, bookingId) {
  const resolvedBookingId =
    safeStr(_trackingSyncCanonicalBookingId(bookingId, rec), 160) ||
    safeStr(bookingId, 160);
  let stored = _bookingOperationalLegsFromRecord(rec).map((entry) => ({ ...entry }));
  if (!stored.length) {
    // Always synthesize the OUTBOUND leg for a record that has from/to but no
    // persisted operational legs (e.g. legacy bookings). The RETURN leg is
    // added below only when there is genuine return data, so one-way bookings
    // show exactly one (outbound) leg.
    const outbound = _synthesizeOutboundOperationalLegForReadModel(rec, resolvedBookingId);
    if (!outbound) return [];
    stored = [outbound];
  }
  const hasReturn = stored.some((leg) => _operationalLegTypeFromEntry(leg) === "return");
  if (!hasReturn && _bookingHasReturnDisplayData(rec)) {
    const returnLeg = _synthesizeReturnOperationalLegForReadModel(
      rec,
      resolvedBookingId,
      stored,
    );
    if (returnLeg) stored.push(returnLeg);
  }
  return stored;
}

export function enrichBookingRecordOperationalLegsForReadModel(rec, bookingId) {
  const legs = _bookingOperationalLegsForReadModel(rec, bookingId);
  if (!legs.length || !rec || typeof rec !== "object") return rec;
  rec.operational_legs = legs;
  rec.operationalLegs = legs;
  rec.is_roundtrip_parent = legs.length > 1;
  rec.isRoundtripParent = legs.length > 1;
  if (rec.booking && typeof rec.booking === "object") {
    rec.booking.operational_legs = legs;
    rec.booking.operationalLegs = legs;
    rec.booking.is_roundtrip_parent = legs.length > 1;
    rec.booking.isRoundtripParent = legs.length > 1;
  }
  return rec;
}

export function _materializeOperationalLegIfMissingFromReadModel(rec, bookingId, legId) {
  const safeLegId = safeStr(legId, 200);
  if (!rec || typeof rec !== "object" || !safeLegId) {
    return { changed: false, rec };
  }
  const stored = _bookingOperationalLegsFromRecord(rec);
  if (
    stored.some((leg) => safeStr(leg?.leg_id ?? leg?.legId, 200) === safeLegId)
  ) {
    return { changed: false, rec };
  }
  const projected = _bookingOperationalLegsForReadModel(rec, bookingId);
  const match = projected.find(
    (leg) => safeStr(leg?.leg_id ?? leg?.legId, 200) === safeLegId,
  );
  if (!match) return { changed: false, rec };
  const appendLeg = (target, key) => {
    const current = Array.isArray(target?.[key]) ? target[key].slice() : [];
    current.push({ ...match });
    target[key] = current;
  };
  appendLeg(rec, "operational_legs");
  appendLeg(rec, "operationalLegs");
  if (rec.booking && typeof rec.booking === "object") {
    appendLeg(rec.booking, "operational_legs");
    appendLeg(rec.booking, "operationalLegs");
  }
  rec.is_roundtrip_parent = _bookingOperationalLegsFromRecord(rec).length > 1;
  rec.isRoundtripParent = rec.is_roundtrip_parent;
  if (rec.booking && typeof rec.booking === "object") {
    rec.booking.is_roundtrip_parent = rec.is_roundtrip_parent;
    rec.booking.isRoundtripParent = rec.is_roundtrip_parent;
  }
  console.log(
    `[BOOKING][OPERATIONAL_LEGS][MATERIALIZE] booking=${_bookingIntentMask(bookingId)} leg=${_bookingIntentMask(safeLegId)} reason=read_model_leg`,
  );
  return { changed: true, rec };
}

/**
 * STREET-RIDE-DURABLE-COMPLETION-2: true when the record is a driver-started
 * street / direct ride (source street_ride, ride_type direct, or a street_
 * booking id). Used only to refine the ACTIVE projection; planned customer
 * bookings are never matched here.
 */
export function _isStreetDirectRecord(rec) {
  if (!rec || typeof rec !== "object") return false;
  const source = String(
    rec?.source ??
      rec?.booking_source ??
      rec?.booking?.source ??
      rec?.booking?.booking_source ??
      "",
  )
    .trim()
    .toLowerCase();
  const rideType = String(rec?.ride_type ?? rec?.booking?.ride_type ?? "")
    .trim()
    .toLowerCase();
  const id = String(rec?.booking_id ?? rec?.bookingId ?? "").trim().toLowerCase();
  return source === "street_ride" || rideType === "direct" || id.startsWith("street_");
}

/**
 * P0-FIELD-REPAIR-1 (A): canonical street/direct identity fields, read from the
 * record so a projected row can carry them for downstream consumers (driver
 * planned/open filter + Flutter safety net). Values are echoed verbatim from
 * the record; nothing is invented and no default is substituted.
 */
export function _streetDirectIdentityFieldsForRow(rec) {
  if (!rec || typeof rec !== "object") return {};
  const source = safeStr(rec?.source ?? rec?.booking?.source, 64);
  const bookingSource = safeStr(
    rec?.booking_source ?? rec?.bookingSource ?? rec?.booking?.booking_source,
    64,
  );
  const rideType = safeStr(
    rec?.ride_type ?? rec?.rideType ?? rec?.booking?.ride_type,
    64,
  );
  const isStreetDirect = _isStreetDirectRecord(rec);
  return {
    ...(source ? { source, bookingSource: bookingSource || source } : {}),
    ...(bookingSource ? { booking_source: bookingSource } : {}),
    ...(rideType ? { ride_type: rideType, rideType } : {}),
    is_street_direct: isStreetDirect,
    isStreetDirect,
  };
}

/**
 * P0-FIELD-REPAIR-1 (A): row-level street/direct predicate for the driver
 * planned/open projection.
 *
 * Mirrors `_isStreetDirectRecord` but reads a FLATTENED row (which carries the
 * canonical identity fields stamped by `_streetDirectIdentityFieldsForRow`).
 * Honours the authoritative `is_street_direct` hint first, then falls back to
 * canonical source / booking_source / ride_type / `street_` id — never to a
 * display label.
 */
export function _rowIsStreetDirectRide(row) {
  if (!row || typeof row !== "object") return false;
  if (row?.is_street_direct === true || row?.isStreetDirect === true) return true;
  if (row?.is_street_direct === false && row?.isStreetDirect === false) {
    // Explicit authoritative negative from a current worker projection.
    return false;
  }
  const source = String(
    row?.source ?? row?.booking_source ?? row?.bookingSource ?? "",
  )
    .trim()
    .toLowerCase();
  const rideType = String(row?.ride_type ?? row?.rideType ?? "")
    .trim()
    .toLowerCase();
  const id = String(
    row?.booking_id ?? row?.bookingId ?? row?.parent_booking_id ?? row?.parentBookingId ?? "",
  )
    .trim()
    .toLowerCase();
  return (
    source === "street_ride" ||
    source === "streetride" ||
    source === "direct" ||
    source === "direct_ride" ||
    rideType === "direct" ||
    id.startsWith("street_")
  );
}

export function _projectionLifecycleStatusFromRecord(rec, bookingId = null) {
  const parentStatus = _normLifecycleStatus(rec?.status ?? rec?.stage ?? null);
  if (parentStatus === "COMPLETED" || parentStatus === "CANCELLED") {
    return parentStatus;
  }
  const operationalLegs = _bookingOperationalLegsFromRecord(rec);
  // STREET-RIDE-DURABLE-COMPLETION-2: a live street/direct ride (no operational
  // legs, not terminal) must project as ACTIVE, not the generic PENDING that
  // _normLifecycleStatus collapses IN_PROGRESS to. This keeps it out of the
  // "completed" bucket (so it stays in Available while live and moves to
  // History only when COMPLETED) and lets the UI label it "Rit actief".
  // Planned customer bookings (which carry operational legs / are not
  // street/direct) are unaffected.
  if (!operationalLegs.length) {
    if (_isStreetDirectRecord(rec)) return "ACTIVE";
    return parentStatus;
  }
  const legStatuses = operationalLegs.map((legEntry) =>
    _normLifecycleStatus(
      legEntry?.status ??
        legEntry?.lifecycle_status ??
        legEntry?.lifecycleStatus ??
        null,
    ),
  );
  if (legStatuses.length > 0 && legStatuses.every((status) => status === "COMPLETED")) {
    return "COMPLETED";
  }
  if (legStatuses.length > 0 && legStatuses.every((status) => status === "CANCELLED")) {
    return "CANCELLED";
  }
  return parentStatus;
}

/**
 * NAV-PIP-PLANNED-COMPLETION-EVIDENCE-FIX-P0:
 * When stored operational legs unanimously imply a terminal parent lifecycle
 * but `status` / `stage` aliases still disagree (field: GET status=COMPLETED
 * while record.stage=PENDING), sync every parent alias in-memory.
 * Idempotent. Does not invent completion when a genuine open leg remains.
 * Returns { changed, projected, previous_status, previous_stage }.
 */
export function syncCanonicalParentLifecycleAliasesFromProjection(rec, bookingId = null) {
  if (!rec || typeof rec !== "object") {
    return {
      changed: false,
      projected: null,
      previous_status: null,
      previous_stage: null,
    };
  }
  const projected = _projectionLifecycleStatusFromRecord(rec, bookingId);
  const previousStatus = _normLifecycleStatus(rec?.status ?? null);
  const previousStage = _normLifecycleStatus(rec?.stage ?? null);
  if (projected !== "COMPLETED" && projected !== "CANCELLED") {
    return {
      changed: false,
      projected,
      previous_status: previousStatus,
      previous_stage: previousStage,
    };
  }
  const statusMismatch = previousStatus !== projected;
  const stageMismatch = previousStage !== projected;
  if (!statusMismatch && !stageMismatch) {
    return {
      changed: false,
      projected,
      previous_status: previousStatus,
      previous_stage: previousStage,
    };
  }
  const nowIso = new Date().toISOString();
  const lifecycleLower = projected.toLowerCase();
  rec.status = projected;
  rec.stage = projected;
  rec.lifecycle_status = lifecycleLower;
  rec.lifecycleStatus = lifecycleLower;
  rec.booking_status = lifecycleLower;
  rec.bookingStatus = lifecycleLower;
  if (projected === "COMPLETED") {
    rec.completed_at = rec.completed_at || rec.completedAt || nowIso;
    rec.completedAt = rec.completedAt || rec.completed_at;
    rec.progress_state = rec.progress_state || "completed";
    rec.progressState = rec.progressState || rec.progress_state;
  } else if (projected === "CANCELLED") {
    rec.cancelled_at = rec.cancelled_at || rec.cancelledAt || nowIso;
    rec.cancelledAt = rec.cancelledAt || rec.cancelled_at;
    rec.canceled_at = rec.canceled_at || rec.cancelled_at;
    rec.canceledAt = rec.canceledAt || rec.cancelled_at;
    rec.progress_state = rec.progress_state || "cancelled";
    rec.progressState = rec.progressState || rec.progress_state;
  }
  if (rec.booking && typeof rec.booking === "object") {
    rec.booking.status = projected;
    rec.booking.stage = projected;
    rec.booking.lifecycle_status = lifecycleLower;
    rec.booking.lifecycleStatus = lifecycleLower;
    rec.booking.booking_status = lifecycleLower;
    rec.booking.bookingStatus = lifecycleLower;
    if (projected === "COMPLETED") {
      rec.booking.completed_at =
        rec.booking.completed_at || rec.booking.completedAt || rec.completed_at || nowIso;
      rec.booking.completedAt = rec.booking.completedAt || rec.booking.completed_at;
    } else if (projected === "CANCELLED") {
      rec.booking.cancelled_at =
        rec.booking.cancelled_at || rec.booking.cancelledAt || rec.cancelled_at || nowIso;
      rec.booking.cancelledAt = rec.booking.cancelledAt || rec.booking.cancelled_at;
    }
  }
  return {
    changed: true,
    projected,
    previous_status: previousStatus,
    previous_stage: previousStage,
  };
}

/* ---- Rides-list flatten pipeline (core) ------------------------------ */

export function _flattenBookingForRidesList(bookingId, rec) {
  const from = _pick(rec, ["quote", "from"], null) ?? _pick(rec, ["booking", "from"], null);
  const to = _pick(rec, ["quote", "to"], null) ?? _pick(rec, ["booking", "to"], null);
  const tier = _pick(rec, ["booking", "tier"], null) ?? _pick(rec, ["quote", "tier"], null);
  const pax = _pick(rec, ["booking", "pax"], null);
  const bags = _pick(rec, ["booking", "bags"], null);
  const pickupIso =
    _pick(rec, ["booking", "pickupStartIso"], null) ??
    _pick(rec, ["booking", "pickup_iso"], null) ??
    _pick(rec, ["quote", "pickup_iso"], null) ??
    _pick(rec, ["booking", "createdAt"], null);
  const pricing = _pick(rec, ["quote", "pricing"], null) || {};
  const price =
    pricing.price_incl_vat ??
    pricing.total_price ??
    pricing.total ??
    _pick(rec, ["booking", "price_incl_vat"], null) ??
    _pick(rec, ["booking", "price"], null);
  const customerName =
    _pick(rec, ["booking", "customer_name"], null) ??
    _pick(rec, ["booking", "custName"], null) ??
    _pick(rec, ["booking", "name"], null) ??
    _pick(rec, ["booking", "customer", "name"], null);
  const customerPhone =
    _pick(rec, ["booking", "customer_phone"], null) ??
    _pick(rec, ["booking", "custPhone"], null) ??
    _pick(rec, ["booking", "phone"], null) ??
    _pick(rec, ["booking", "customer", "phone"], null);
  const customerEmail =
    _pick(rec, ["booking", "customer_email"], null) ??
    _pick(rec, ["booking", "custEmail"], null) ??
    _pick(rec, ["booking", "email"], null) ??
    _pick(rec, ["booking", "customer", "email"], null);
  const paymentStatus =
    _resolveBookingRecordPaymentStatusForProjection(rec) ??
    rec?.payment_status ??
    rec?.paymentStatus ??
    _pick(rec, ["booking", "payment_status"], null) ??
    _pick(rec, ["booking", "paymentStatus"], null) ??
    _pick(rec, ["payload", "payment_status"], null) ??
    _pick(rec, ["payload", "paymentStatus"], null);
  const paidAt =
    rec?.paid_at ??
    rec?.paidAt ??
    _pick(rec, ["booking", "paid_at"], null) ??
    _pick(rec, ["booking", "paidAt"], null);
  const paymentProvider =
    rec?.payment_provider ??
    rec?.paymentProvider ??
    _pick(rec, ["booking", "payment_provider"], null) ??
    _pick(rec, ["booking", "paymentProvider"], null);
  const paymentId =
    rec?.payment_id ??
    rec?.paymentId ??
    _pick(rec, ["booking", "payment_id"], null) ??
    _pick(rec, ["booking", "paymentId"], null);
  const paymentMethod =
    rec?.payment_method ??
    rec?.paymentMethod ??
    _pick(rec, ["booking", "payment_method"], null) ??
    _pick(rec, ["booking", "paymentMethod"], null);
  const paymentSource =
    rec?.payment_source ??
    rec?.paymentSource ??
    _pick(rec, ["booking", "payment_source"], null) ??
    _pick(rec, ["booking", "paymentSource"], null);
  const refundStatus =
    rec?.refund_status ??
    rec?.refundStatus ??
    _pick(rec, ["booking", "refund_status"], null) ??
    _pick(rec, ["booking", "refundStatus"], null) ??
    _pick(rec, ["payload", "refund_status"], null) ??
    _pick(rec, ["payload", "refundStatus"], null);
  const creditStatus =
    rec?.credit_status ??
    rec?.creditStatus ??
    _pick(rec, ["booking", "credit_status"], null) ??
    _pick(rec, ["booking", "creditStatus"], null) ??
    _pick(rec, ["payload", "credit_status"], null) ??
    _pick(rec, ["payload", "creditStatus"], null);
  const refundRequired =
    rec?.refund_required === true ||
    rec?.refundRequired === true ||
    _pick(rec, ["booking", "refund_required"], false) === true ||
    _pick(rec, ["booking", "refundRequired"], false) === true ||
    _pick(rec, ["payload", "refund_required"], false) === true ||
    _pick(rec, ["payload", "refundRequired"], false) === true;
  const creditDecision =
    rec?.credit_decision ??
    rec?.creditDecision ??
    _pick(rec, ["booking", "credit_decision"], null) ??
    _pick(rec, ["booking", "creditDecision"], null) ??
    _pick(rec, ["payload", "credit_decision"], null) ??
    _pick(rec, ["payload", "creditDecision"], null);
  const creditedAmountCentsRaw =
    rec?.credited_amount_cents ??
    rec?.creditedAmountCents ??
    _pick(rec, ["booking", "credited_amount_cents"], null) ??
    _pick(rec, ["booking", "creditedAmountCents"], null) ??
    _pick(rec, ["payload", "credited_amount_cents"], null) ??
    _pick(rec, ["payload", "creditedAmountCents"], null);
  const creditedAmountCents = Number.isFinite(Number(creditedAmountCentsRaw))
    ? Math.max(0, Math.round(Number(creditedAmountCentsRaw)))
    : null;
  const creditedAt =
    rec?.credited_at ??
    rec?.creditedAt ??
    _pick(rec, ["booking", "credited_at"], null) ??
    _pick(rec, ["booking", "creditedAt"], null) ??
    _pick(rec, ["payload", "credited_at"], null) ??
    _pick(rec, ["payload", "creditedAt"], null);
  const creditedBy =
    rec?.credited_by ??
    rec?.creditedBy ??
    _pick(rec, ["booking", "credited_by"], null) ??
    _pick(rec, ["booking", "creditedBy"], null) ??
    _pick(rec, ["payload", "credited_by"], null) ??
    _pick(rec, ["payload", "creditedBy"], null);
  const mollieRefundId =
    rec?.mollie_refund_id ??
    rec?.mollieRefundId ??
    _pick(rec, ["booking", "mollie_refund_id"], null) ??
    _pick(rec, ["booking", "mollieRefundId"], null) ??
    _pick(rec, ["payload", "mollie_refund_id"], null) ??
    _pick(rec, ["payload", "mollieRefundId"], null);
  const mollieRefundStatus =
    rec?.mollie_refund_status ??
    rec?.mollieRefundStatus ??
    _pick(rec, ["booking", "mollie_refund_status"], null) ??
    _pick(rec, ["booking", "mollieRefundStatus"], null) ??
    _pick(rec, ["payload", "mollie_refund_status"], null) ??
    _pick(rec, ["payload", "mollieRefundStatus"], null);
  const refundedAmountCentsRaw =
    rec?.refunded_amount_cents ??
    rec?.refundedAmountCents ??
    _pick(rec, ["booking", "refunded_amount_cents"], null) ??
    _pick(rec, ["booking", "refundedAmountCents"], null) ??
    _pick(rec, ["payload", "refunded_amount_cents"], null) ??
    _pick(rec, ["payload", "refundedAmountCents"], null);
  const refundedAmountCents = Number.isFinite(Number(refundedAmountCentsRaw))
    ? Math.max(0, Math.round(Number(refundedAmountCentsRaw)))
    : null;
  const refundedAt =
    rec?.refunded_at ??
    rec?.refundedAt ??
    _pick(rec, ["booking", "refunded_at"], null) ??
    _pick(rec, ["booking", "refundedAt"], null) ??
    _pick(rec, ["payload", "refunded_at"], null) ??
    _pick(rec, ["payload", "refundedAt"], null);
  const refundProvider =
    rec?.refund_provider ??
    rec?.refundProvider ??
    _pick(rec, ["booking", "refund_provider"], null) ??
    _pick(rec, ["booking", "refundProvider"], null) ??
    _pick(rec, ["payload", "refund_provider"], null) ??
    _pick(rec, ["payload", "refundProvider"], null);
  const complianceMollieRefundEmittedAt =
    rec?.compliance_mollie_refund_emitted_at ??
    rec?.complianceMollieRefundEmittedAt ??
    _pick(rec, ["booking", "compliance_mollie_refund_emitted_at"], null) ??
    _pick(rec, ["booking", "complianceMollieRefundEmittedAt"], null) ??
    _pick(rec, ["payload", "compliance_mollie_refund_emitted_at"], null) ??
    _pick(rec, ["payload", "complianceMollieRefundEmittedAt"], null);
  const complianceMollieRefundFinalEmittedAt =
    rec?.compliance_mollie_refund_final_emitted_at ??
    rec?.complianceMollieRefundFinalEmittedAt ??
    _pick(rec, ["booking", "compliance_mollie_refund_final_emitted_at"], null) ??
    _pick(rec, ["booking", "complianceMollieRefundFinalEmittedAt"], null) ??
    _pick(rec, ["payload", "compliance_mollie_refund_final_emitted_at"], null) ??
    _pick(rec, ["payload", "complianceMollieRefundFinalEmittedAt"], null);
  const assignedDriverId = bookingAssignedDriverId(rec);
  const assignedVehicleId = bookingAssignedVehicleId(rec);
  // Read-model enrichment (Patch 2): pull additive parent-level fields
  // from the record. Strictly additive — every field below is included
  // only when an actual value exists on the record (or, for vehicle
  // metadata, on a matching operational leg). Never invents a value and
  // never overrides any existing field above.
  const planningReferenceForRow = safeStr(
    rec?.planning_reference ??
      rec?.planningReference ??
      _pick(rec, ["booking", "planning_reference"], null) ??
      _pick(rec, ["booking", "planningReference"], null) ??
      _pick(rec, ["payload", "planning_reference"], null) ??
      _pick(rec, ["payload", "planningReference"], null),
    120,
  );
  const roundtripDispatchModeForRow = _roundtripDispatchModeFromRecord(rec);
  const parentAssignmentModeForRow = _parentAssignmentModeFromRecord(rec);
  const waitMinForRow = _bookingWaitMinFromRecord(rec);
  const parentDriverContact = _bookingAssignedDriverContactFromRecord(rec);
  const parentVehicleEnrichment = _parentAssignmentEnrichmentFromLegs(
    rec,
    assignedVehicleId,
  );
  // Additive list projection of the record's canonical creation timestamp.
  // Read-only: never invents a value and never mutates the stored booking.
  const createdAt = safeStr(
    rec?.created_at ??
      rec?.createdAt ??
      _pick(rec, ["booking", "created_at"], null) ??
      _pick(rec, ["booking", "createdAt"], null) ??
      _pick(rec, ["payload", "created_at"], null) ??
      _pick(rec, ["payload", "createdAt"], null) ??
      rec?.inserted_at ??
      rec?.insertedAt,
    80,
  );

  return {
    booking_id: bookingId,
    pickup_iso: pickupIso,
    ...(createdAt
      ? {
          created_at: createdAt,
          createdAt,
        }
      : {}),
    from,
    to,
    tier,
    pax,
    bags,
    assigned_vehicle_id: assignedVehicleId || null,
    assignedVehicleId: assignedVehicleId || null,
    ...(assignedDriverId
      ? { assigned_driver_id: assignedDriverId, assignedDriverId: assignedDriverId }
      : {}),
    customer_name: customerName,
    customer_phone: customerPhone,
    customer_email: customerEmail,
    custName: customerName,
    custPhone: customerPhone,
    custEmail: customerEmail,
    name: customerName,
    phone: customerPhone,
    email: customerEmail,
    customer: {
      name: customerName || "",
      phone: customerPhone || "",
      email: customerEmail || "",
    },
    status: _projectionLifecycleStatusFromRecord(rec, bookingId),
    price,
    currency: _pick(rec, ["booking", "currency"], "EUR") || "EUR",
    payment_status: paymentStatus,
    paymentStatus,
    paid_at: paidAt,
    paidAt,
    payment_provider: paymentProvider,
    paymentProvider,
    payment_id: paymentId,
    paymentId,
    payment_method: paymentMethod,
    paymentMethod,
    payment_source: paymentSource,
    paymentSource,
    refund_status: refundStatus,
    refundStatus,
    credit_status: creditStatus,
    creditStatus,
    refund_required: refundRequired,
    refundRequired,
    credit_decision: creditDecision,
    creditDecision,
    credited_amount_cents: creditedAmountCents,
    creditedAmountCents: creditedAmountCents,
    credited_at: creditedAt,
    creditedAt,
    credited_by: creditedBy,
    creditedBy,
    mollie_refund_id: mollieRefundId,
    mollieRefundId,
    mollie_refund_status: mollieRefundStatus,
    mollieRefundStatus,
    refunded_amount_cents: refundedAmountCents,
    refundedAmountCents: refundedAmountCents,
    refunded_at: refundedAt,
    refundedAt,
    refund_provider: refundProvider,
    refundProvider,
    compliance_mollie_refund_emitted_at: complianceMollieRefundEmittedAt,
    complianceMollieRefundEmittedAt,
    compliance_mollie_refund_final_emitted_at: complianceMollieRefundFinalEmittedAt,
    complianceMollieRefundFinalEmittedAt,
    ...(planningReferenceForRow
      ? {
          planning_reference: planningReferenceForRow,
          planningReference: planningReferenceForRow,
        }
      : {}),
    ...(roundtripDispatchModeForRow
      ? {
          roundtrip_dispatch_mode: roundtripDispatchModeForRow,
          roundtripDispatchMode: roundtripDispatchModeForRow,
        }
      : {}),
    ...(parentAssignmentModeForRow
      ? {
          parent_assignment_mode: parentAssignmentModeForRow,
          parentAssignmentMode: parentAssignmentModeForRow,
        }
      : {}),
    ...(waitMinForRow != null
      ? {
          wait_min: waitMinForRow,
          waitMin: waitMinForRow,
        }
      : {}),
    ...(parentDriverContact?.name
      ? {
          assigned_driver_name: parentDriverContact.name,
          assignedDriverName: parentDriverContact.name,
        }
      : {}),
    ...(parentDriverContact?.phone
      ? {
          assigned_driver_phone: parentDriverContact.phone,
          assignedDriverPhone: parentDriverContact.phone,
        }
      : {}),
    ...(parentVehicleEnrichment || {}),
    // P0-FIELD-REPAIR-1 (A): canonical street/direct identity travels with the
    // row so the driver planned/open filter and the Flutter safety net can
    // decide on canonical fields instead of a display label.
    ..._streetDirectIdentityFieldsForRow(rec),
  };
}

export function _flattenOperationalLegForRidesList(parentBookingId, rec, leg, options = {}) {
  const parentRow = _flattenBookingForRidesList(parentBookingId, rec);
  const isRoundtripParent = options?.isRoundtripParent === true;
  const legPickupIso = safeStr(leg?.pickup_iso ?? leg?.pickupIso, 80);
  const legFrom = _pick(leg, ["from"], null);
  const legTo = _pick(leg, ["to"], null);
  const legPriceInclVat = leg?.price_incl_vat ?? leg?.priceInclVat;
  const legPriceExVat = leg?.price_ex_vat ?? leg?.priceExVat;
  const legPriceVat = leg?.price_vat ?? leg?.priceVat;
  const legTypeRaw = safeStr(leg?.leg_type ?? leg?.legType, 24).toLowerCase();
  const legType = legTypeRaw === "return" ? "return" : "outbound";
  const resolvedLegPriceInclVat =
    legPriceInclVat != null
      ? legPriceInclVat
      : legType === "return"
        ? _bookingReturnPriceInclVatFromRecord(rec)
        : _bookingMainPriceInclVatFromRecord(rec);
  const parentBooking = rec?.booking && typeof rec.booking === "object" ? rec.booking : {};
  const parentTotalInclVat =
    parentBooking?.price_incl_vat ??
    rec?.price_incl_vat ??
    _pick(rec, ["quote", "pricing", "price_incl_vat"], null) ??
    _pick(rec, ["quote", "pricing", "total_price"], null) ??
    parentRow?.price ??
    null;
  const parentTotalExVat =
    parentBooking?.price_ex_vat ??
    rec?.price_ex_vat ??
    _pick(rec, ["quote", "pricing", "price_ex_vat"], null) ??
    null;
  const parentTotalVat =
    parentBooking?.price_vat ??
    rec?.price_vat ??
    _pick(rec, ["quote", "pricing", "price_vat"], null) ??
    null;
  const legStatusRaw = safeStr(
    leg?.status ?? leg?.lifecycle_status ?? leg?.lifecycleStatus,
    40,
  );
  const parentStatusUpper = _normLifecycleStatus(parentRow?.status || null);
  const legStatusUpper = _normLifecycleStatus(legStatusRaw || parentStatusUpper || "PENDING");
  // Roundtrip operational-leg completion scope: each leg's own lifecycle is
  // the source of truth. A parent COMPLETED must never overwrite a sibling
  // leg's PENDING / SCHEDULED state (split_no_wait airport roundtrips:
  // outbound completed, return still open). Parent terminal lifecycle is
  // only projected when the leg itself has no status stamped (legacy /
  // pre-cascade snapshots).
  //
  // P0-FIELD-REPAIR-1 (A2): a street/direct booking has exactly ONE physical
  // ride, so its single operational leg is a shadow of the parent rather than
  // an independently dispatchable leg. Once the parent reaches a terminal
  // status, a stale leg status (PENDING / SCHEDULED / IN_PROGRESS never
  // cascaded at finalize time) must not resurrect the ride as an open row.
  // Genuine roundtrip parents keep per-leg ownership untouched.
  const isStreetDirectShadowLeg =
    !isRoundtripParent && _isStreetDirectRecord(rec);
  let projectedStatusUpper;
  if (isStreetDirectShadowLeg && isTerminalLifecycleStatus(parentStatusUpper)) {
    projectedStatusUpper = parentStatusUpper;
    if (legStatusRaw && legStatusUpper !== parentStatusUpper) {
      console.log(
        `[STREET_RIDE_SHADOW_LEG][TERMINAL_PARENT_WINS] parent=${_bookingIntentMask(parentBookingId)} leg_status=${legStatusUpper} parent_status=${parentStatusUpper}`,
      );
    }
  } else if (legStatusRaw) {
    projectedStatusUpper = legStatusUpper;
  } else if (isTerminalLifecycleStatus(parentStatusUpper)) {
    projectedStatusUpper = parentStatusUpper;
  } else {
    projectedStatusUpper = legStatusUpper;
  }
  const assignedDriverId = safeStr(
    leg?.assigned_driver_id ??
      leg?.assignedDriverId ??
      parentRow?.assigned_driver_id ??
      parentRow?.assignedDriverId,
    96,
  );
  const assignedVehicleId = safeStr(
    leg?.assigned_vehicle_id ??
      leg?.assignedVehicleId ??
      parentRow?.assigned_vehicle_id ??
      parentRow?.assignedVehicleId,
    128,
  );
  const legId = safeStr(leg?.leg_id ?? leg?.legId, 200);
  const parentBookingReference = safeStr(
    parentRow?.public_booking_reference ??
      rec?.public_booking_reference ??
      rec?.publicBookingReference ??
      rec?.booking_reference ??
      rec?.bookingReference ??
      _pick(rec, ["booking", "public_booking_reference"], null) ??
      _pick(rec, ["booking", "publicBookingReference"], null) ??
      _pick(rec, ["booking", "booking_reference"], null) ??
      _pick(rec, ["booking", "bookingReference"], null),
    120,
  );
  const planningReference = safeStr(
    parentRow?.planning_reference ??
      rec?.planning_reference ??
      rec?.planningReference ??
      _pick(rec, ["booking", "planning_reference"], null) ??
      _pick(rec, ["booking", "planningReference"], null),
    120,
  );
  const legCreatedAt = safeStr(
    leg?.created_at ??
      leg?.createdAt ??
      parentRow?.created_at ??
      parentRow?.createdAt,
    80,
  );
  const row = {
    ...parentRow,
    booking_id: parentBookingId,
    parent_booking_id: parentBookingId,
    parentBookingId: parentBookingId,
    leg_id: legId || null,
    legId: legId || null,
    leg_type: legType,
    legType: legType,
    is_operational_leg: true,
    isOperationalLeg: true,
    is_roundtrip_parent: isRoundtripParent,
    isRoundtripParent: isRoundtripParent,
    ...(legCreatedAt
      ? {
          created_at: legCreatedAt,
          createdAt: legCreatedAt,
        }
      : {}),
    pickup_iso: legPickupIso || parentRow?.pickup_iso || null,
    pickupIso: legPickupIso || parentRow?.pickup_iso || null,
    from: legFrom ?? parentRow?.from ?? null,
    to: legTo ?? parentRow?.to ?? null,
    status: projectedStatusUpper,
    lifecycle: projectedStatusUpper.toLowerCase(),
    lifecycle_status: projectedStatusUpper.toLowerCase(),
    lifecycleStatus: projectedStatusUpper.toLowerCase(),
    parent_status: parentStatusUpper,
    parentStatus: parentStatusUpper,
    assigned_driver_id: assignedDriverId || null,
    assignedDriverId: assignedDriverId || null,
    assigned_vehicle_id: assignedVehicleId || null,
    assignedVehicleId: assignedVehicleId || null,
    service:
      safeStr(leg?.service ?? _pick(rec, ["booking", "service"], null), 32) ||
      null,
    tier: safeStr(_pick(rec, ["booking", "tier"], null) ?? parentRow?.tier, 24) || null,
    return_enabled: !!_pick(rec, ["booking", "return_enabled"], false),
    returnEnabled: !!_pick(rec, ["booking", "return_enabled"], false),
    price:
      (resolvedLegPriceInclVat != null
        ? resolvedLegPriceInclVat
        : parentRow?.price) ?? null,
    leg_price_incl_vat: resolvedLegPriceInclVat ?? null,
    legPriceInclVat: resolvedLegPriceInclVat ?? null,
    leg_price_ex_vat: legPriceExVat ?? null,
    legPriceExVat: legPriceExVat ?? null,
    leg_price_vat: legPriceVat ?? null,
    legPriceVat: legPriceVat ?? null,
    parent_price_incl_vat: parentTotalInclVat ?? null,
    parentPriceInclVat: parentTotalInclVat ?? null,
    parent_price_ex_vat: parentTotalExVat ?? null,
    parentPriceExVat: parentTotalExVat ?? null,
    parent_price_vat: parentTotalVat ?? null,
    parentPriceVat: parentTotalVat ?? null,
    parent_total_price: parentTotalInclVat ?? null,
    parentTotalPrice: parentTotalInclVat ?? null,
    public_booking_reference: parentBookingReference || null,
    publicBookingReference: parentBookingReference || null,
    booking_reference: parentBookingReference || null,
    bookingReference: parentBookingReference || null,
    parent_booking_reference: parentBookingReference || null,
    parentBookingReference: parentBookingReference || null,
    linked_order_reference: planningReference || parentBookingReference || null,
    linkedOrderReference: planningReference || parentBookingReference || null,
    planning_reference: planningReference || null,
    planningReference: planningReference || null,
  };
  if (isRoundtripParent) {
    console.log(
      `[ROUNDTRIP_LEG_UI][COMPANY_FILTER] parent=${_bookingIntentMask(parentBookingId)} leg=${_bookingIntentMask(legId)} leg_type=${legType || "-"} parent_status=${parentStatusUpper || "-"} leg_status=${legStatusUpper || "-"} projected_status=${projectedStatusUpper || "-"}`,
    );
    if (projectedStatusUpper !== "CANCELLED") {
      console.log(
        `[ROUNDTRIP_LEG_UI][ACTIVE_LEG_VISIBLE] parent=${_bookingIntentMask(parentBookingId)} leg=${_bookingIntentMask(legId)} leg_type=${legType || "-"} projected_status=${projectedStatusUpper || "-"}`,
      );
    }
  }
  // Read-model enrichment (Patch 2): leg-first override of the additive
  // fields that may have leaked in via the `...parentRow` spread. Vehicle
  // and driver enrichment are stamped per-leg by Patch 1; when the leg's
  // assignment matches the parent's summary the inherited row already
  // shows the correct values, but split_no_wait legs with their OWN
  // different vehicle/driver must show their own metadata (and clear the
  // parent's "summary" metadata that would otherwise mislead the UI).
  const legOwnDriverId = safeStr(leg?.assigned_driver_id ?? leg?.assignedDriverId, 96);
  const legOwnVehicleId = safeStr(leg?.assigned_vehicle_id ?? leg?.assignedVehicleId, 128);
  const parentRowDriverId = safeStr(
    parentRow?.assigned_driver_id ?? parentRow?.assignedDriverId,
    96,
  );
  const parentRowVehicleId = safeStr(
    parentRow?.assigned_vehicle_id ?? parentRow?.assignedVehicleId,
    128,
  );
  const legDriverContact =
    _normalizeAssignedDriverSummaryForLeg(leg?.assigned_driver ?? leg?.assignedDriver);
  const legDriverNameOwn =
    (legDriverContact && legDriverContact.name) ||
    safeStr(leg?.assigned_driver_name ?? leg?.assignedDriverName, 160) ||
    "";
  const legDriverPhoneOwn =
    (legDriverContact && legDriverContact.phone) ||
    safeStr(leg?.assigned_driver_phone ?? leg?.assignedDriverPhone, 64) ||
    "";
  if (legDriverNameOwn) {
    row.assigned_driver_name = legDriverNameOwn;
    row.assignedDriverName = legDriverNameOwn;
  } else if (legOwnDriverId && legOwnDriverId !== parentRowDriverId) {
    // Different driver, no leg-own name available: do not let parent's
    // summary driver name mislead the UI for this leg.
    row.assigned_driver_name = null;
    row.assignedDriverName = null;
  }
  if (legDriverPhoneOwn) {
    row.assigned_driver_phone = legDriverPhoneOwn;
    row.assignedDriverPhone = legDriverPhoneOwn;
  } else if (legOwnDriverId && legOwnDriverId !== parentRowDriverId) {
    row.assigned_driver_phone = null;
    row.assignedDriverPhone = null;
  }
  const legVehicleEnrichment = _operationalLegFleetEnrichmentFields(leg);
  if (legVehicleEnrichment) {
    Object.assign(row, legVehicleEnrichment);
  } else if (legOwnVehicleId && legOwnVehicleId !== parentRowVehicleId) {
    // Different vehicle, no leg-own metadata available: clear the
    // parent's vehicle metadata that bled in via the spread so the leg
    // never displays the other leg's vehicle name / plate.
    const VEHICLE_ENRICHMENT_KEYS = [
      "assigned_vehicle",
      "assignedVehicle",
      "assigned_vehicle_name",
      "assignedVehicleName",
      "assigned_vehicle_brand_model",
      "assignedVehicleBrandModel",
      "assigned_vehicle_license_plate",
      "assignedVehicleLicensePlate",
      "license_plate",
      "licensePlate",
      "assigned_vehicle_color",
      "assignedVehicleColor",
      "assigned_vehicle_exploitation_license_number",
      "assignedVehicleExploitationLicenseNumber",
      "assigned_vehicle_registration_number",
      "assignedVehicleRegistrationNumber",
    ];
    for (const key of VEHICLE_ENRICHMENT_KEYS) {
      if (key in row) row[key] = null;
    }
  }
  // Allocator diagnostics are per-leg. Parent diagnostics inherited via
  // the spread refer to the summary allocation and must not bleed into
  // a leg that has its own allocator decision recorded.
  const legAllocatorDiagnostics =
    (leg && typeof leg.allocator_diagnostics === "object" && leg.allocator_diagnostics) ||
    (leg && typeof leg.allocatorDiagnostics === "object" && leg.allocatorDiagnostics) ||
    null;
  if (legAllocatorDiagnostics) {
    row.allocator_diagnostics = legAllocatorDiagnostics;
    row.allocatorDiagnostics = legAllocatorDiagnostics;
  } else {
    if ("allocator_diagnostics" in row) row.allocator_diagnostics = null;
    if ("allocatorDiagnostics" in row) row.allocatorDiagnostics = null;
  }
  // Roundtrip dispatch mode and wait_min are parent-scoped. They may
  // already be present via the spread when _flattenBookingForRidesList
  // emitted them, but make them explicit here so the leg row always
  // exposes the parent context regardless of evaluation order.
  const legRowRoundtripMode = _roundtripDispatchModeFromRecord(rec);
  if (legRowRoundtripMode) {
    row.roundtrip_dispatch_mode = legRowRoundtripMode;
    row.roundtripDispatchMode = legRowRoundtripMode;
  }
  const legRowWaitMin = _bookingWaitMinFromRecord(rec);
  if (legRowWaitMin != null) {
    row.wait_min = legRowWaitMin;
    row.waitMin = legRowWaitMin;
  }
  const legRefundStatus = safeStr(leg?.refund_status ?? leg?.refundStatus, 64);
  const legCreditStatus = safeStr(leg?.credit_status ?? leg?.creditStatus, 64);
  const legRefundRequired =
    leg?.refund_required === true || leg?.refundRequired === true;
  const legCreditDecision = safeStr(leg?.credit_decision ?? leg?.creditDecision, 64);
  const legCreditedAmountCentsRaw =
    leg?.credited_amount_cents ?? leg?.creditedAmountCents;
  const legCreditedAmountCents = Number.isFinite(Number(legCreditedAmountCentsRaw))
    ? Math.max(0, Math.round(Number(legCreditedAmountCentsRaw)))
    : null;
  if (legStatusUpper === "CANCELLED") {
    const legHasOwnCreditState =
      !!(legRefundStatus || legCreditStatus || legCreditDecision || legRefundRequired);
    const legMollieRefundId = safeStr(leg?.mollie_refund_id ?? leg?.mollieRefundId, 120);
    const legMollieRefundStatus = safeStr(
      leg?.mollie_refund_status ?? leg?.mollieRefundStatus,
      64,
    );
    const legRefundedAmountCentsRaw = leg?.refunded_amount_cents ?? leg?.refundedAmountCents;
    const legRefundedAmountCents = Number.isFinite(Number(legRefundedAmountCentsRaw))
      ? Math.max(0, Math.round(Number(legRefundedAmountCentsRaw)))
      : null;
    if (legHasOwnCreditState) {
      row.refund_status = legRefundStatus || null;
      row.refundStatus = row.refund_status;
      row.credit_status = legCreditStatus || null;
      row.creditStatus = row.credit_status;
      row.refund_required = legRefundRequired === true;
      row.refundRequired = row.refund_required;
      if (legCreditDecision) {
        row.credit_decision = legCreditDecision;
        row.creditDecision = legCreditDecision;
      }
      if (legCreditedAmountCents != null) {
        row.credited_amount_cents = legCreditedAmountCents;
        row.creditedAmountCents = legCreditedAmountCents;
      }
      if (legMollieRefundId) {
        row.mollie_refund_id = legMollieRefundId;
        row.mollieRefundId = legMollieRefundId;
      }
      if (legMollieRefundStatus) {
        row.mollie_refund_status = legMollieRefundStatus;
        row.mollieRefundStatus = legMollieRefundStatus;
      }
      if (legRefundedAmountCents != null) {
        row.refunded_amount_cents = legRefundedAmountCents;
        row.refundedAmountCents = legRefundedAmountCents;
      }
    } else {
      // Defensive: when a cancelled leg row has no own credit/refund state,
      // strip any credit/refund fields that the `...parentRow` spread above
      // inherited from the parent record. Without this, the parent's
      // pending_credit (set by applyPendingCreditStateOnPaidCancellation)
      // leaks into a leg row whose leg entry is empty, the company overview
      // projects "pending credit", and the leg-scoped credit-decision
      // endpoint then correctly refuses with `credit_decision_not_pending`.
      // Steps 1 and 2 of this patch ensure healthy data always has leg-own
      // state; this clear is a safety net for any future projection drift.
      row.refund_status = null;
      row.refundStatus = null;
      row.credit_status = null;
      row.creditStatus = null;
      row.refund_required = false;
      row.refundRequired = false;
      row.credit_decision = null;
      row.creditDecision = null;
      row.credited_amount_cents = null;
      row.creditedAmountCents = null;
      row.credited_at = null;
      row.creditedAt = null;
      console.log(
        `[CREDIT_CLASSIFY][CLEAR_PARENT_CREDIT_INHERITANCE] booking=${_bookingIntentMask(parentBookingId)} leg=${_bookingIntentMask(legId)} reason=leg_cancelled_without_own_credit_state`,
      );
    }
    // Leg-truthful refund identity:
    // An operational leg row must only expose a mollie_refund_id/status when
    // the leg itself owns it. Without this normalization the parent's refund
    // id (inherited via the `...parentRow` spread above) leaks into a leg row
    // that was never refunded, which causes the company UI to show
    // "Controleer terugbetalingsstatus" and then fail with
    // missing_mollie_refund_id when the leg-only refund target is resolved.
    if (!legMollieRefundId) {
      row.mollie_refund_id = null;
      row.mollieRefundId = null;
      console.log(
        `[LEG_REFUND_FLATTEN][CLEARED_PARENT_REFUND_ID] parent=${_bookingIntentMask(parentBookingId)} leg=${_bookingIntentMask(legId)} reason=leg_has_no_own_refund_id`,
      );
    }
    if (!legMollieRefundStatus) {
      row.mollie_refund_status = null;
      row.mollieRefundStatus = null;
    }
    if (legRefundedAmountCents == null) {
      row.refunded_amount_cents = null;
      row.refundedAmountCents = null;
    }
  } else if (parentStatusUpper !== "CANCELLED") {
    row.refund_status = null;
    row.refundStatus = null;
    row.credit_status = null;
    row.creditStatus = null;
    row.refund_required = false;
    row.refundRequired = false;
    row.credit_decision = null;
    row.creditDecision = null;
    row.credited_amount_cents = null;
    row.creditedAmountCents = null;
    row.credited_at = null;
    row.creditedAt = null;
  }
  return row;
}

export function _flattenBookingForRidesListWithOperationalLegs(bookingId, rec, options = {}) {
  const operationalLegs = _bookingOperationalLegsForReadModel(rec, bookingId);
  if (!operationalLegs.length) {
    return [_flattenBookingForRidesList(bookingId, rec)];
  }
  const isRoundtripParent = operationalLegs.length > 1;
  return operationalLegs.map((leg) => _flattenOperationalLegForRidesList(
    bookingId,
    rec,
    leg,
    {
      ...options,
      isRoundtripParent,
    },
  ));
}

