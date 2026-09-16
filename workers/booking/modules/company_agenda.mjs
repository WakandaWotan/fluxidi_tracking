// COMPANY-AGENDA-P0 — planned rides on the existing company bookings index.
// No booking: prefix scan. Period list reads the company list index once.

import { safeStr, sanitizeTenantString } from "./parsing_utils.js";
import { sha256Hex, jsonBase64urlEncode, jsonBase64urlDecode } from "./crypto_utils.js";
import { putBookingCreateIfAbsent } from "./human_booking_id_allocator.mjs";
import {
  companyBookingsListIndexKey,
  driverScopedBookingsIndexKey,
  vehicleScopedBookingsIndexKey,
  upsertCompanyBookingsListIndexBestEffort,
  upsertDriverVehicleBookingIndexesBestEffort,
  upsertCustomerScopedBookingIndexForBooking,
} from "./booking_indexes.js";
import {
  applyAgendaLegAssignment,
  applyAgendaLegPickup,
  applyCompanyRoundtripFields,
  assignmentWindowsForWrite,
  assignmentWriteFlags,
  clearParsedAssignment,
  decorateAgendaItem,
  indexItemOverlapsPeriod,
  occupancyWindowsForRecord,
  occupancyWindowsFromTimes,
  parseCompanyRoundtripWrite,
  sanitizePublicAssignmentItem,
  sanitizeRecordAssignmentTruth,
  publicItemOverlapsPeriod,
  resolveAgendaLegTarget,
  resolveBookingCurrency,
  resolveBookingDistanceKm,
  resolveBookingDurationMin,
  resolveBookingPriceExVat,
  resolveBookingPriceInclVat,
  resolveBookingPriceVat,
  resolveBookingPricingSource,
  resolveRoundtripDispatchMode,
} from "./company_roundtrip.mjs";
import {
  evaluateCompanyFixedPriceWrite,
  resolveCompanyFixedPrice,
  stampCompanyFixedPriceSnapshot,
} from "./company_fixed_prices.mjs";
import {
  companyAgendaPickupIsEpoch,
  companyAgendaWhenIsNow,
  resolveCompanyAgendaPickupIso,
} from "./company_plan_when.mjs";
import {
  ASSIGNMENT_SAFETY_MARGIN_MIN,
  driverFromFleet,
  evaluateDriverEligibility,
  evaluateVehicleEligibility,
  expandWindowsWithSafetyMargin,
  loadDispatchFleet,
  publicAssignmentChoice,
  resolveAutoVehicle,
  rideIsSoon,
  vehicleFromFleet,
} from "./company_dispatch.mjs";

const AGENDA_LIST_LIMIT = 200;
const OVERLAP_INDEX_CAP = 24;
const AGENDA_LOOKBACK_MS = 12 * 60 * 60 * 1000;
const NON_CAPACITY_STATUSES = new Set([
  "CANCELLED",
  "CANCELED",
  "NO_SHOW",
  "REJECTED",
  "EXPIRED",
  "COMPLETED",
]);

export function matchCompanyAgendaPath(pathname) {
  const path = String(pathname || "");
  if (path === "/company/agenda/rides") return { kind: "rides" };
  if (path === "/company/agenda/overlap") return { kind: "overlap" };
  if (path === "/company/agenda/quote") return { kind: "quote" };
  if (path === "/company/agenda/assignment-choices") return { kind: "assignment-choices" };
  const ride = path.match(
    /^\/company\/agenda\/rides\/([^/]+)(?:\/(assign|unassign|reschedule|phone-confirm))?$/,
  );
  if (!ride) return null;
  return {
    kind: ride[2] || "ride",
    bookingId: decodeURIComponent(ride[1]),
  };
}

export function agendaPeriodMs(fromIso, toIso) {
  const fromMs = Date.parse(String(fromIso || ""));
  const toMs = Date.parse(String(toIso || ""));
  if (!Number.isFinite(fromMs) || !Number.isFinite(toMs) || toMs <= fromMs) {
    return { ok: false, error: "invalid_period" };
  }
  return { ok: true, fromMs, toMs };
}

export function pickupMsFromRow(row) {
  const iso = safeStr(
    row?.pickup_iso || row?.pickupIso || row?.start_at || row?.booking?.pickup_iso,
    80,
  );
  const ms = Date.parse(iso);
  return Number.isFinite(ms) ? ms : 0;
}

export function compareAgendaIndexRows(a, b) {
  const pickupDelta = pickupMsFromRow(a) - pickupMsFromRow(b);
  if (pickupDelta !== 0) return pickupDelta;
  return safeStr(a?.booking_id, 160).localeCompare(safeStr(b?.booking_id, 160));
}

export function encodeAgendaListCursor(row) {
  return jsonBase64urlEncode({
    v: 1,
    p: pickupMsFromRow(row),
    id: safeStr(row?.booking_id, 160),
  });
}

export function decodeAgendaListCursor(raw) {
  const text = safeStr(raw, 800);
  if (!text) return { ok: true, cursor: null };
  try {
    const parsed = jsonBase64urlDecode(text);
    const pickupMs = Number(parsed?.p);
    const bookingId = safeStr(parsed?.id, 160);
    if (parsed?.v !== 1 || !Number.isFinite(pickupMs) || !bookingId) {
      return { ok: false, error: "invalid_cursor" };
    }
    return { ok: true, cursor: { p: pickupMs, id: bookingId } };
  } catch {
    return { ok: false, error: "invalid_cursor" };
  }
}

function rowIsAfterAgendaCursor(row, cursor) {
  const pickupMs = pickupMsFromRow(row);
  const bookingId = safeStr(row?.booking_id, 160);
  if (pickupMs > cursor.p) return true;
  return pickupMs === cursor.p && bookingId > cursor.id;
}

export function isUnscheduledIndexItem(item) {
  return pickupMsFromRow(item) <= 0;
}

export function unscheduledIndexItems(items) {
  const list = Array.isArray(items) ? items : [];
  return list.filter((item) => isUnscheduledIndexItem(item));
}

function indexItemEndMs(item, pickupMs, lookbackMs) {
  const durationMin = Number(item?.duration_min ?? item?.durationMin);
  if (Number.isFinite(durationMin) && durationMin > 0) {
    return pickupMs + durationMin * 60000;
  }
  return pickupMs + lookbackMs;
}

export function filterIndexItemsByPeriod(
  items,
  fromMs,
  toMs,
  { lookbackMs = AGENDA_LOOKBACK_MS } = {},
) {
  const list = Array.isArray(items) ? items : [];
  return list.filter((item) => {
    if (indexItemOverlapsPeriod(item, fromMs, toMs, { lookbackMs })) return true;
    const ms = pickupMsFromRow(item);
    if (!ms) return false;
    const endMs = indexItemEndMs(item, ms, lookbackMs);
    return endMs > fromMs && ms < toMs;
  });
}

export function isCapacityBlockingRecord(record) {
  const status = String(
    record?.status ||
      record?.lifecycle ||
      record?.booking?.status ||
      record?.booking?.lifecycle ||
      "",
  )
    .trim()
    .toUpperCase();
  return !NON_CAPACITY_STATUSES.has(status);
}

export function intervalsOverlap(aStart, aEnd, bStart, bEnd) {
  return aStart < bEnd && bStart < aEnd;
}

export function rideWindow(pickupIso, durationMin) {
  const start = Date.parse(String(pickupIso || ""));
  if (!Number.isFinite(start)) return { ok: false, error: "invalid_pickup_iso" };
  const duration = Number(durationMin);
  if (!Number.isFinite(duration) || duration <= 0) {
    return { ok: true, start, end: null, durationUnknown: true };
  }
  return { ok: true, start, end: start + duration * 60000, durationUnknown: false };
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

function scopeIds(scope) {
  const tenantId = sanitizeTenantString(scope?.tenant_id ?? scope?.tenantId, 80);
  const companyId = sanitizeTenantString(scope?.company_id ?? scope?.companyId, 80);
  return { tenantId, companyId };
}

async function kvJson(kv, key) {
  if (!kv || !key) return null;
  const raw = await kv.get(key, { type: "json" }).catch(async () => {
    const text = await kv.get(key);
    if (!text) return null;
    try {
      return JSON.parse(text);
    } catch {
      return null;
    }
  });
  return raw && typeof raw === "object" ? raw : null;
}

async function agendaBookingId(tenantId, companyId, idempotencyKey) {
  const digest = await sha256Hex(`${tenantId}|${companyId}|${idempotencyKey}`);
  return `agb_${digest.slice(0, 32)}`;
}

async function idempotencyRecordKey(tenantId, companyId, idempotencyKey) {
  const digest = await sha256Hex(idempotencyKey);
  return `tenant:${tenantId}:company:${companyId}:agenda:idem:v1:${digest}`;
}

const OVERLAP_INDEX_STORE_CAP = 250;

function overlapIndexItems(raw) {
  return Array.isArray(raw?.items) ? raw.items : Array.isArray(raw) ? raw : [];
}

function overlapCandidateIds(raw, window) {
  const items = overlapIndexItems(raw);
  const relevant = items.filter((item) => {
    if (indexItemOverlapsPeriod(item, window.start, window.end, { lookbackMs: AGENDA_LOOKBACK_MS })) {
      return true;
    }
    const ms = pickupMsFromRow(item);
    if (!ms) return true;
    const endMs = indexItemEndMs(item, ms, AGENDA_LOOKBACK_MS);
    return endMs > window.start && ms < window.end;
  });
  const ids = relevant
    .map((item) => safeStr(item?.booking_id || item?.bookingId, 160))
    .filter(Boolean);
  return {
    ids,
    indexTruncated: items.length >= OVERLAP_INDEX_STORE_CAP,
  };
}

function proposedOccupancyWindows(input) {
  if (Array.isArray(input.windows)) {
    if (!input.windows.length) {
      return { ok: true, unknown: true, windows: [] };
    }
    const unknown = input.windows.some((window) => !window || window.durationUnknown || window.end == null);
    return { ok: true, unknown, windows: input.windows.filter((window) => window?.ok !== false) };
  }
  return occupancyWindowsFromTimes({
    mode: input.roundtripMode || input.roundtrip_dispatch_mode || "single",
    pickupIso: input.pickupIso,
    durationMin: input.durationMin,
    returnPickupIso: input.returnPickupIso || input.return_pickup_iso,
    returnDurationMin: input.returnDurationMin || input.return_duration_min,
  });
}

export async function checkAssignmentOverlap(env, input) {
  const { tenantId, companyId } = scopeIds(input.scope);
  const driverId = sanitizeTenantString(input.driverId, 96);
  const vehicleId = sanitizeTenantString(input.vehicleId, 128);
  if (!driverId && !vehicleId) return { ok: true, checked: false };
  const proposed = proposedOccupancyWindows(input);
  if (!proposed.ok) return proposed;
  if (proposed.unknown || !proposed.windows.length) {
    return { ok: false, error: "assignment_availability_unknown" };
  }
  const proposedWindows = expandWindowsWithSafetyMargin(
    proposed.windows,
    input.safetyMarginMin ?? ASSIGNMENT_SAFETY_MARGIN_MIN,
  );
  const ids = new Set();
  const collect = (raw, window) => {
    const candidates = overlapCandidateIds(raw, window);
    if (candidates.indexTruncated) {
      return { incomplete: true };
    }
    for (const id of candidates.ids) ids.add(id);
    return { incomplete: false };
  };
  for (const window of proposedWindows) {
    if (driverId) {
      const raw = await kvJson(
        env.BOOKING_KV,
        driverScopedBookingsIndexKey({ tenant_id: tenantId, company_id: companyId }, driverId),
      );
      if (collect(raw, window).incomplete) {
        return { ok: false, error: "assignment_availability_unknown" };
      }
    }
    if (vehicleId) {
      const raw = await kvJson(
        env.BOOKING_KV,
        vehicleScopedBookingsIndexKey({ tenant_id: tenantId, company_id: companyId }, vehicleId),
      );
      if (collect(raw, window).incomplete) {
        return { ok: false, error: "assignment_availability_unknown" };
      }
    }
  }
  const exclude = safeStr(input.excludeBookingId, 160);
  for (const bookingId of ids) {
    if (bookingId === exclude) continue;
    const record = await kvJson(env.BOOKING_KV, `booking:${bookingId}`);
    if (!record) {
      return { ok: false, error: "assignment_availability_unknown", booking_id: bookingId };
    }
    if (!isCapacityBlockingRecord(record)) continue;
    const other = occupancyWindowsForRecord(record);
    if (!other.ok || other.unknown) {
      return { ok: false, error: "assignment_availability_unknown", booking_id: bookingId };
    }
    if (!other.windows.length) continue;
    for (const window of proposedWindows) {
      for (const otherWindow of other.windows) {
        if (intervalsOverlap(window.start, window.end, otherWindow.start, otherWindow.end)) {
          return { ok: false, error: "assignment_overlap", booking_id: bookingId };
        }
      }
    }
  }
  return { ok: true, checked: true };
}

function normalizeAgendaRideOptions(body) {
  const src = body?.ride_options && typeof body.ride_options === "object"
    ? body.ride_options
    : body || {};
  const bags = Number(src.bags ?? body?.bags);
  const wait = Number(src.wait_min ?? src.waitMin ?? body?.wait_min ?? body?.waitMin);
  return {
    service: sanitizeTenantString(src.service || body?.service, 32),
    tier: sanitizeTenantString(src.tier || body?.tier, 32),
    bags: Number.isFinite(bags) && bags > 0 ? Math.min(8, Math.round(bags)) : 0,
    wait_min: Number.isFinite(wait) && wait > 0 ? Math.min(240, Math.round(wait)) : 0,
    flight_number: sanitizeTenantString(src.flight_number || body?.flight_number, 16).toUpperCase(),
    airport_direction: sanitizeTenantString(src.airport_direction || body?.airport_direction, 32),
    extra: sanitizeTenantString(src.extra || body?.extra, 32),
    meet_and_greet: src.meet_and_greet === true || src.meetAndGreet === true || body?.meet_and_greet === true,
    name_board: sanitizeTenantString(src.name_board || src.nameBoard || body?.name_board, 80),
    airport_iata: sanitizeTenantString(src.airport_iata || body?.airport_iata, 8).toUpperCase(),
    airport_country: sanitizeTenantString(src.airport_country || body?.airport_country, 8).toUpperCase(),
    flight_at: sanitizeTenantString(src.flight_at || body?.flight_at, 40),
    pickup_arrangement: sanitizeTenantString(
      src.pickup_arrangement || body?.pickup_arrangement,
      32,
    ).toLowerCase(),
    pickup_after_min: Number.isFinite(Number(src.pickup_after_min ?? body?.pickup_after_min))
      ? Math.max(0, Math.round(Number(src.pickup_after_min ?? body?.pickup_after_min)))
      : 0,
    flight_timezone: sanitizeTenantString(
      src.flight_timezone || body?.flight_timezone,
      64,
    ) || "Europe/Brussels",
    return_airport_iata: sanitizeTenantString(
      src.return_airport_iata || body?.return_airport_iata,
      8,
    ).toUpperCase(),
    return_flight_number: sanitizeTenantString(
      src.return_flight_number || body?.return_flight_number,
      16,
    ).toUpperCase(),
    return_flight_at: sanitizeTenantString(src.return_flight_at || body?.return_flight_at, 40),
    return_pickup_arrangement: sanitizeTenantString(
      src.return_pickup_arrangement || body?.return_pickup_arrangement,
      32,
    ).toLowerCase(),
  };
}

function publicAgendaItems(record, bookingId, { stripAll = false } = {}) {
  sanitizeRecordAssignmentTruth(record, { stripAll });
  return decorateAgendaItem(publicAgendaItem(record, bookingId), record, bookingId)
    .map((item) => sanitizePublicAssignmentItem(item, { stripAll }));
}

function publicAgendaItem(record, bookingId) {
  const booking = record?.booking && typeof record.booking === "object" ? record.booking : {};
  const durationMin = resolveBookingDurationMin(record);
  const durationUnknown = durationMin == null;
  const priceInclVat = resolveBookingPriceInclVat(record);
  const priceExVat = resolveBookingPriceExVat(record);
  const priceVat = resolveBookingPriceVat(record);
  return {
    booking_id: bookingId,
    customer_id: safeStr(record?.customer_id || booking.customer_id, 160),
    customer_name: safeStr(
      record?.customer_name || booking.customer_name || booking.customer?.name,
      160,
    ),
    from: safeStr(booking.from || record?.from, 240),
    to: safeStr(booking.to || record?.to, 240),
    pickup_iso: safeStr(record?.pickup_iso || booking.pickup_iso, 80),
    status: safeStr(record?.status || booking.status, 40) || "PENDING",
    assigned_driver_id: safeStr(record?.assigned_driver_id || booking.assigned_driver_id, 96),
    assigned_vehicle_id: safeStr(record?.assigned_vehicle_id || booking.assigned_vehicle_id, 128),
    assignment_state: safeStr(record?.assigned_driver_id || booking.assigned_driver_id, 96)
      ? "assigned"
      : "unassigned",
    assignment_accepted:
      record?.assignment_accepted === true ||
      record?.driver_accepted === true ||
      booking.assignment_accepted === true ||
      booking.driver_accepted === true,
    duration_min: durationMin,
    duration_unknown: durationUnknown,
    do_not_dispatch: record?.do_not_dispatch === true || booking.do_not_dispatch === true,
    revision: Number(record?.revision || booking.revision || 1) || 1,
    phone_confirmed_at: safeStr(
      record?.phone_confirmed_at || booking.phone_confirmed_at,
      80,
    ),
    phone_confirmed_by: safeStr(
      record?.phone_confirmed_by || booking.phone_confirmed_by,
      160,
    ),
    source: safeStr(record?.source || booking.source, 64),
    passengers: Number(booking.pax || record?.pax || 1) || 1,
    price_incl_vat: priceInclVat,
    price_ex_vat: priceExVat,
    price_vat: priceVat,
    currency: resolveBookingCurrency(record),
    distance_km: resolveBookingDistanceKm(record),
    service: safeStr(booking.service || record?.service, 32),
    tier: safeStr(booking.tier || record?.tier, 32),
    bags: Number(booking.bags ?? record?.bags ?? 0) || 0,
    wait_min: Number(booking.wait_min ?? record?.wait_min ?? 0) || 0,
    flight_number: safeStr(booking.flight_number || record?.flight_number, 16),
    airport_iata: safeStr(
      booking.airport_iata || record?.airport_iata || booking.ride_options?.airport_iata,
      8,
    ),
    flight_at: safeStr(booking.flight_at || record?.flight_at || booking.ride_options?.flight_at, 40),
    pickup_arrangement: safeStr(
      booking.pickup_arrangement ||
        record?.pickup_arrangement ||
        booking.ride_options?.pickup_arrangement,
      32,
    ),
    airport_direction: safeStr(booking.airport_direction || record?.airport_direction, 32),
    pricing_source: resolveBookingPricingSource(record),
    fixed_fare_rule_id: safeStr(record?.fixed_fare_rule_id || booking.fixed_fare_rule_id, 96),
    fixed_price_snapshot: record?.fixed_price_snapshot || booking.fixed_price_snapshot || null,
    extra: safeStr(booking.extra || record?.extra, 32),
    meet_and_greet: booking.meet_and_greet === true || record?.meet_and_greet === true,
    name_board: safeStr(booking.name_board || record?.name_board, 80),
    note: safeStr(booking.note || record?.note, 500),
    ride_options: booking.ride_options || record?.ride_options || null,
    return_enabled: record?.return_enabled === true || booking.return_enabled === true,
    roundtrip_dispatch_mode: resolveRoundtripDispatchMode(record),
    return_pickup_iso: safeStr(record?.return_pickup_iso || booking.return_pickup_iso, 80),
    return_from: safeStr(record?.return_from || booking.return_from, 240),
    return_to: safeStr(record?.return_to || booking.return_to, 240),
    return_duration_min: Number.isFinite(Number(record?.return_duration_min ?? booking.return_duration_min))
      ? Number(record?.return_duration_min ?? booking.return_duration_min)
      : null,
    occupancy_wait_min: Number.isFinite(Number(record?.occupancy_wait_min ?? booking.occupancy_wait_min))
      ? Number(record?.occupancy_wait_min ?? booking.occupancy_wait_min)
      : null,
    occupancy_unknown: record?.occupancy_unknown === true || booking.occupancy_unknown === true,
    parent_booking_id: bookingId,
    outbound_stops: Array.isArray(record?.outbound_stops)
      ? record.outbound_stops
      : booking.outbound_stops || booking.stops || [],
    return_stops: Array.isArray(record?.return_stops)
      ? record.return_stops
      : booking.return_stops || [],
    operational_legs: Array.isArray(record?.operational_legs) ? record.operational_legs : booking.operational_legs || null,
  };
}

export async function listAgendaRides(env, {
  scope,
  fromIso,
  toIso,
  limit = AGENDA_LIST_LIMIT,
  cursor = "",
}) {
  const period = agendaPeriodMs(fromIso, toIso);
  if (!period.ok) return period;
  const decoded = decodeAgendaListCursor(cursor);
  if (!decoded.ok) return decoded;
  const { tenantId, companyId } = scopeIds(scope);
  const indexKey = companyBookingsListIndexKey({ tenant_id: tenantId, company_id: companyId });
  const index = await kvJson(env.BOOKING_KV, indexKey);
  const pageSize = Math.min(AGENDA_LIST_LIMIT, Math.max(1, Number(limit) || AGENDA_LIST_LIMIT));
  const matching = filterIndexItemsByPeriod(index?.items, period.fromMs, period.toMs)
    .sort(compareAgendaIndexRows);
  const start = decoded.cursor
    ? matching.findIndex((row) => rowIsAfterAgendaCursor(row, decoded.cursor))
    : 0;
  const from = start < 0 ? matching.length : start;
  const pageRows = matching.slice(from, from + pageSize);
  const items = [];
  for (const row of pageRows) {
    const expanded = await hydrateAgendaIndexRow(env, row);
    for (const item of expanded) {
      if (!item?.pickup_iso || publicItemOverlapsPeriod(item, period.fromMs, period.toMs)) {
        items.push(item);
      }
    }
  }
  const unscheduled = [];
  if (!decoded.cursor) {
    for (const row of unscheduledIndexItems(index?.items).slice(0, pageSize)) {
      const expanded = await hydrateAgendaIndexRow(env, row);
      unscheduled.push(...expanded);
    }
  }
  const last = pageRows[pageRows.length - 1];
  const hasMore = from + pageSize < matching.length;
  return {
    ok: true,
    items,
    unscheduled,
    count: items.length,
    has_more: hasMore,
    next_cursor: hasMore && last ? encodeAgendaListCursor(last) : null,
  };
}

async function hydrateAgendaIndexRow(env, row) {
  const bookingId = safeStr(row.booking_id, 160);
  const record = await kvJson(env.BOOKING_KV, `booking:${bookingId}`);
  if (record) {
    return decorateAgendaItem(publicAgendaItem(record, bookingId), record, bookingId);
  }
  return [{
    booking_id: bookingId,
    agenda_item_id: bookingId,
    parent_booking_id: bookingId,
    pickup_iso: safeStr(row.pickup_iso, 80),
    status: safeStr(row.status, 40) || "PENDING",
    assigned_driver_id: safeStr(row.assigned_driver_id, 96),
    assigned_vehicle_id: safeStr(row.assigned_vehicle_id, 128),
    duration_unknown: true,
    duration_min: null,
    customer_name: "",
    from: "",
    to: "",
    do_not_dispatch: false,
    source: "",
  }];
}

function buildPlannedBookingRecord({ tenantId, companyId, bookingId, body, now }) {
  const clock = now instanceof Date ? now : new Date(now);
  const pickupIso = resolveCompanyAgendaPickupIso(body, clock);
  const durationMin = Number(body.duration_min ?? body.durationMin);
  const durationUnknown = !Number.isFinite(durationMin) || durationMin <= 0;
  const pax = Math.max(1, Number(body.passengers ?? body.pax ?? 1) || 1);
  const price = body.price_incl_vat ?? body.priceInclVat;
  const hasPrice = price != null && String(price).trim() !== "";
  const rideOptions = normalizeAgendaRideOptions(body);
  const note = sanitizeTenantString(body.note || body.description, 500);
  const distanceKm = Number(body.distance_km ?? body.distanceKm);
  const hasDistance = Number.isFinite(distanceKm) && distanceKm > 0;
  const pricingSource = safeStr(body.pricing_source || body.pricingSource, 40);
  const durationRouteMin = Number(body.duration_route_min ?? body.durationRouteMin ?? durationMin);
  return {
    booking_id: bookingId,
    tenant_id: tenantId,
    company_id: companyId,
    customer_id: safeStr(body.customer_id || body.customerId, 160),
    customer_name: safeStr(body.customer_name || body.customerName, 160),
    source: "company_agenda",
    status: "PENDING",
    stage: "PENDING",
    lifecycle: "PENDING",
    do_not_dispatch: true,
    ride_started: false,
    pickup_iso: pickupIso,
    duration_min: durationUnknown ? null : durationMin,
    duration_route_min: durationUnknown ? null : (Number.isFinite(durationRouteMin) && durationRouteMin > 0 ? durationRouteMin : durationMin),
    duration_unknown: durationUnknown,
    ...(hasDistance ? { distance_km: Number(distanceKm.toFixed(1)) } : {}),
    ...(pricingSource ? { pricing_source: pricingSource } : {}),
    assigned_driver_id: safeStr(body.assigned_driver_id || body.driver_id, 96) || null,
    assigned_vehicle_id: safeStr(body.assigned_vehicle_id || body.vehicle_id, 128) || null,
    created_at: now,
    updated_at: now,
    booking: {
      tenant_id: tenantId,
      company_id: companyId,
      from: safeStr(body.from || body.pickup, 240),
      to: safeStr(body.to || body.dropoff, 240),
      pickup_iso: pickupIso,
      pickup_lat: Number.isFinite(Number(body.pickup_lat ?? body.pickupLat))
        ? Number(body.pickup_lat ?? body.pickupLat)
        : null,
      pickup_lon: Number.isFinite(Number(body.pickup_lon ?? body.pickupLon))
        ? Number(body.pickup_lon ?? body.pickupLon)
        : null,
      pickup_place_id: safeStr(body.pickup_place_id || body.pickupPlaceId, 80),
      dropoff_lat: Number.isFinite(Number(body.dropoff_lat ?? body.dropoffLat))
        ? Number(body.dropoff_lat ?? body.dropoffLat)
        : null,
      dropoff_lon: Number.isFinite(Number(body.dropoff_lon ?? body.dropoffLon))
        ? Number(body.dropoff_lon ?? body.dropoffLon)
        : null,
      dropoff_place_id: safeStr(body.dropoff_place_id || body.dropoffPlaceId, 80),
      pickupStartIso: pickupIso,
      pax,
      customer_id: safeStr(body.customer_id || body.customerId, 160),
      customer_name: safeStr(body.customer_name || body.customerName, 160),
      customer_email: safeStr(body.customer_email || body.customerEmail, 160),
      customer_phone: safeStr(body.customer_phone || body.customerPhone, 40),
      currency: safeStr(body.currency, 8) || "EUR",
      ...(hasPrice ? { price_incl_vat: Number(price) } : {}),
      ...(hasDistance ? { distance_km: Number(distanceKm.toFixed(1)) } : {}),
      ...(pricingSource ? { pricing_source: pricingSource } : {}),
      duration_route_min: durationUnknown ? null : (Number.isFinite(durationRouteMin) && durationRouteMin > 0 ? durationRouteMin : durationMin),
      status: "PENDING",
      source: "company_agenda",
      do_not_dispatch: true,
      duration_min: durationUnknown ? null : durationMin,
      duration_unknown: durationUnknown,
      assigned_driver_id: safeStr(body.assigned_driver_id || body.driver_id, 96) || null,
      assigned_vehicle_id: safeStr(body.assigned_vehicle_id || body.vehicle_id, 128) || null,
      ...(rideOptions.service ? { service: rideOptions.service } : {}),
      ...(rideOptions.tier ? { tier: rideOptions.tier } : {}),
      bags: rideOptions.bags,
      wait_min: rideOptions.wait_min,
      ...(rideOptions.flight_number ? { flight_number: rideOptions.flight_number } : {}),
      ...(rideOptions.airport_direction ? { airport_direction: rideOptions.airport_direction } : {}),
      ...(rideOptions.extra ? { extra: rideOptions.extra } : {}),
      ...(rideOptions.meet_and_greet ? { meet_and_greet: true } : {}),
      ...(rideOptions.name_board ? { name_board: rideOptions.name_board } : {}),
      ...(note ? { note } : {}),
      ride_options: rideOptions,
      inputs: { ...rideOptions, pax, note },
    },
    ride_options: rideOptions,
    ...(rideOptions.service ? { service: rideOptions.service } : {}),
    ...(rideOptions.tier ? { tier: rideOptions.tier } : {}),
    bags: rideOptions.bags,
    wait_min: rideOptions.wait_min,
    ...(rideOptions.flight_number ? { flight_number: rideOptions.flight_number } : {}),
    ...(note ? { note } : {}),
  };
}

export async function createAgendaRide(env, { scope, body, idempotencyKey }) {
  const { tenantId, companyId } = scopeIds(scope);
  const key = safeStr(idempotencyKey, 120);
  if (!key) return { ok: false, error: "idempotency_key_required" };
  const customerId = safeStr(body?.customer_id || body?.customerId, 160);
  const pickupIso = resolveCompanyAgendaPickupIso(body, new Date());
  const from = safeStr(body?.from || body?.pickup, 240);
  const to = safeStr(body?.to || body?.dropoff, 240);
  if (!customerId) return { ok: false, error: "customer_required" };
  if (!pickupIso || !Number.isFinite(Date.parse(pickupIso)) || companyAgendaPickupIsEpoch(pickupIso)) {
    return { ok: false, error: companyAgendaWhenIsNow(body) ? "invalid_pickup_iso" : "pickup_iso_required" };
  }
  if (!from || !to) return { ok: false, error: "route_required" };

  const parsed = parseCompanyRoundtripWrite({ ...body, pickup_iso: pickupIso, from, to });
  if (!parsed.ok) return parsed;

  const idemKey = await idempotencyRecordKey(tenantId, companyId, key);
  const existingIdem = await kvJson(env.BOOKING_KV, idemKey);
  if (existingIdem?.booking_id) {
    const existing = await kvJson(env.BOOKING_KV, `booking:${existingIdem.booking_id}`);
    const existingItems = existing
      ? decorateAgendaItem(publicAgendaItem(existing, existingIdem.booking_id), existing, existingIdem.booking_id)
      : [{ booking_id: existingIdem.booking_id }];
    return {
      ok: true,
      idempotent: true,
      booking_id: existingIdem.booking_id,
      item: existingItems[0],
      items: existingItems,
    };
  }

  const plannedChecks = assignmentWindowsForWrite(parsed);
  let assignmentWarning = null;
  const writeBody = { ...(body || {}), pickup_iso: pickupIso, pickupIso };
  const wantsAssignment = plannedChecks.checks.some((check) => check.driverId || check.vehicleId);
  if (wantsAssignment && plannedChecks.unknown) {
    assignmentWarning = { error: "assignment_availability_unknown" };
  }
  if (wantsAssignment && !assignmentWarning) {
    for (const check of plannedChecks.checks) {
      if (!check.window || check.window.durationUnknown || check.window.end == null) {
        if (check.driverId || check.vehicleId) {
          assignmentWarning = { error: "assignment_availability_unknown" };
          break;
        }
        continue;
      }
      const enforced = await enforceDispatchAssignment(env, {
        scope: { tenant_id: tenantId, company_id: companyId },
        driverId: check.driverId,
        vehicleId: check.vehicleId,
        pickupIso: parsed.pickupIso || pickupIso,
        windows: [check.window],
      });
      if (!enforced.ok) {
        assignmentWarning = enforced;
        break;
      }
      if (enforced.legacy || enforced.skipped) {
        const overlap = await checkAssignmentOverlap(env, {
          scope: { tenant_id: tenantId, company_id: companyId },
          driverId: check.driverId,
          vehicleId: check.vehicleId || enforced.vehicleId,
          windows: [check.window],
        });
        if (!overlap.ok) {
          assignmentWarning = overlap;
          break;
        }
      } else if (enforced.vehicleId && !writeBody.assigned_vehicle_id && !writeBody.vehicle_id) {
        writeBody.assigned_vehicle_id = enforced.vehicleId;
      }
    }
  }
  if (assignmentWarning) {
    writeBody.assigned_driver_id = "";
    writeBody.assigned_vehicle_id = "";
    writeBody.driver_id = "";
    writeBody.vehicle_id = "";
    writeBody.return_assigned_driver_id = "";
    writeBody.return_assigned_vehicle_id = "";
    writeBody.return_driver_id = "";
    writeBody.return_vehicle_id = "";
    clearParsedAssignment(parsed);
  }

  const bookingId = await agendaBookingId(tenantId, companyId, key);
  const now = new Date().toISOString();
  const record = buildPlannedBookingRecord({
    tenantId,
    companyId,
    bookingId,
    body: writeBody,
    now,
  });
  applyCompanyRoundtripFields(record, parsed, { bookingId, now });
  if (assignmentWarning) {
    sanitizeRecordAssignmentTruth(record, { stripAll: true });
  }
  const quotedSnapshot =
    writeBody?.fixed_price_snapshot && typeof writeBody.fixed_price_snapshot === "object"
      ? writeBody.fixed_price_snapshot
      : null;
  const lockedQuotePrice =
    writeBody?.quote_price_locked === true ||
    !!safeStr(writeBody?.accepted_quote_id || writeBody?.acceptedQuoteId, 80);
  const live = await resolveCompanyFixedPrice(
    env,
    { tenant_id: tenantId, company_id: companyId, hasScope: true },
    {
      ...writeBody,
      from,
      to,
      pickup_lat: body?.pickup_lat ?? body?.from_lat ?? body?.fromLat,
      pickup_lng: body?.pickup_lng ?? body?.from_lng ?? body?.fromLng,
      dropoff_lat: body?.dropoff_lat ?? body?.to_lat ?? body?.toLat,
      dropoff_lng: body?.dropoff_lng ?? body?.to_lng ?? body?.toLng,
      pax: body?.passengers ?? body?.pax,
      airport_iata: body?.airport_iata ?? body?.airportIata,
      airport_direction: body?.airport_direction ?? body?.airportDirection,
    },
  );
  const priced = evaluateCompanyFixedPriceWrite({
    live,
    quotedSnapshot,
    lockedQuotePrice,
  });
  if (!priced.ok) {
    return {
      ok: false,
      error: priced.error || "price_changed",
      snapshot: priced.snapshot || null,
    };
  }
  if (priced.apply) {
    stampCompanyFixedPriceSnapshot(record, priced.apply);
  }
  const put = await putBookingCreateIfAbsent(
    env.BOOKING_KV,
    bookingId,
    JSON.stringify(record),
    { mode: "create" },
  );
  if (!put.ok && put.collision) {
    const existing = await kvJson(env.BOOKING_KV, `booking:${bookingId}`);
    const existingItems = existing
      ? decorateAgendaItem(publicAgendaItem(existing, bookingId), existing, bookingId)
      : [{ booking_id: bookingId }];
    return {
      ok: true,
      idempotent: true,
      booking_id: bookingId,
      item: existingItems[0],
      items: existingItems,
    };
  }
  if (!put.ok) return { ok: false, error: put.error || "booking_write_failed" };

  const listed = await upsertCompanyBookingsListIndexBestEffort(env, bookingId, record, {
    tenant_id: tenantId,
    company_id: companyId,
    hasScope: true,
  });
  await upsertCustomerScopedBookingIndexForBooking(env, bookingId, record);
  if (record.assigned_driver_id || record.assigned_vehicle_id) {
    await upsertDriverVehicleBookingIndexesBestEffort(env, bookingId, record, {
      tenant_id: tenantId,
      company_id: companyId,
      hasScope: true,
    });
  }
  await env.BOOKING_KV.put(
    idemKey,
    JSON.stringify({ booking_id: bookingId, created_at: now }),
  );
  const items = decorateAgendaItem(publicAgendaItem(record, bookingId), record, bookingId)
    .map((item) => sanitizePublicAssignmentItem(item, { stripAll: !!assignmentWarning }));
  return {
    ok: true,
    idempotent: false,
    booking_id: bookingId,
    listed: listed?.ok === true,
    item: items[0],
    items,
    ...assignmentWriteFlags(record, assignmentWarning),
  };
}

function bookingCompanyMatches(record, tenantId, companyId) {
  const recTenant = sanitizeTenantString(
    record?.tenant_id || record?.booking?.tenant_id,
    80,
  );
  const recCompany = sanitizeTenantString(
    record?.company_id || record?.booking?.company_id,
    80,
  );
  return recTenant === tenantId && recCompany === companyId;
}

function appendAgendaHistory(record, entry) {
  const history = Array.isArray(record.history) ? record.history.slice() : [];
  history.push(entry);
  return history.slice(-40);
}

async function removeBookingFromAssignmentIndexes(env, scope, bookingId, driverId, vehicleId) {
  const ids = [
    driverId ? { kind: "driver", id: driverId } : null,
    vehicleId ? { kind: "vehicle", id: vehicleId } : null,
  ].filter(Boolean);
  for (const target of ids) {
    const key =
      target.kind === "driver"
        ? driverScopedBookingsIndexKey(scope, target.id)
        : vehicleScopedBookingsIndexKey(scope, target.id);
    const raw = await kvJson(env.BOOKING_KV, key);
    const items = Array.isArray(raw?.items) ? raw.items : [];
    const next = items.filter(
      (item) => safeStr(item?.booking_id || item?.bookingId, 160) !== bookingId,
    );
    await env.BOOKING_KV.put(key, JSON.stringify({ ...(raw || {}), items: next }));
  }
}

async function persistAgendaBooking(env, { tenantId, companyId, bookingId, record }) {
  await env.BOOKING_KV.put(`booking:${bookingId}`, JSON.stringify(record));
  const scope = { tenant_id: tenantId, company_id: companyId, hasScope: true };
  await upsertCompanyBookingsListIndexBestEffort(env, bookingId, record, scope);
  await upsertCustomerScopedBookingIndexForBooking(env, bookingId, record);
  if (record.assigned_driver_id || record.assigned_vehicle_id) {
    await upsertDriverVehicleBookingIndexesBestEffort(env, bookingId, record, scope);
  }
}

const ASSIGNMENT_CONFLICT_ERRORS = new Set([
  "assignment_overlap",
  "assignment_vehicle_overlap",
  "assignment_availability_unknown",
  "assignment_driver_inactive",
  "assignment_driver_blocked",
  "assignment_driver_not_scheduled",
  "assignment_driver_outside_hours",
  "assignment_driver_planned_break",
  "assignment_driver_absent",
  "assignment_ride_after_hours",
  "assignment_schedule_undeterminable",
  "assignment_driver_paused",
  "assignment_driver_on_trip",
  "assignment_driver_offline",
  "assignment_driver_not_live",
  "assignment_driver_no_vehicle",
  "assignment_vehicle_unavailable",
  "assignment_vehicle_busy",
  "assignment_vehicle_choice_required",
]);

export function assignmentConflictStatus(error) {
  return ASSIGNMENT_CONFLICT_ERRORS.has(String(error || "")) ? 409 : 0;
}

export async function enforceDispatchAssignment(env, {
  scope,
  driverId,
  vehicleId,
  pickupIso,
  windows,
  excludeBookingId,
}) {
  const fleet = await loadDispatchFleet(env, scope);
  if (fleet.load_failed) {
    return { ok: false, error: "assignment_availability_unknown" };
  }
  const driver = driverFromFleet(fleet, driverId);
  if (!driverId) {
    return { ok: true, vehicleId: sanitizeTenantString(vehicleId, 128), skipped: true };
  }
  if (!driver) {
    return { ok: true, vehicleId: sanitizeTenantString(vehicleId, 128), legacy: true };
  }
  const atMs = Date.now();
  const presence = fleet.presenceMap[driverId] || {};
  const overlap = await checkAssignmentOverlap(env, {
    scope,
    driverId,
    vehicleId,
    windows,
    excludeBookingId,
  });
  const evaluation = evaluateDriverEligibility({
    driver,
    presence,
    vehicles: fleet.vehicles,
    drivers: fleet.drivers,
    atMs,
    pickupIso,
    overlap,
  });
  if (!evaluation.ok) {
    return { ok: false, error: evaluation.error, reasons: evaluation.reasons };
  }
  const auto = resolveAutoVehicle({
    driver,
    vehicles: fleet.vehicles,
    drivers: fleet.drivers,
    atMs,
    requestedVehicleId: vehicleId,
  });
  if (!auto.ok) {
    return { ok: false, error: auto.error, vehicles: auto.choices };
  }
  if (auto.vehicleId) {
    const vehicleOverlap = await checkAssignmentOverlap(env, {
      scope,
      vehicleId: auto.vehicleId,
      windows,
      excludeBookingId,
    });
    const vehicleCheck = evaluateVehicleEligibility({
      vehicle: vehicleFromFleet(fleet, auto.vehicleId),
      drivers: fleet.drivers,
      driver,
      atMs,
      overlap: vehicleOverlap,
    });
    if (!vehicleCheck.ok) return vehicleCheck;
  }
  return {
    ok: true,
    vehicleId: auto.vehicleId,
    auto: auto.auto === true,
  };
}

export async function listAssignmentChoices(env, input = {}) {
  const scope = {
    tenant_id: input.scope?.tenant_id || input.tenant_id,
    company_id: input.scope?.company_id || input.company_id,
  };
  const fleet = await loadDispatchFleet(env, scope);
  if (fleet.load_failed) {
    return {
      ok: false,
      error: "assignment_availability_unknown",
      soon: false,
      current_driver: null,
      drivers: [],
      empty: true,
    };
  }
  const atMs = Date.parse(String(input.now || "")) || Date.now();
  const pickupIso = safeStr(input.pickupIso || input.pickup_iso, 80);
  const durationMin = Number(input.durationMin ?? input.duration_min);
  const excludeBookingId = safeStr(input.excludeBookingId || input.exclude_booking_id, 160);
  const currentDriverId = sanitizeTenantString(
    input.currentDriverId || input.current_driver_id || input.exclude_driver_id,
    96,
  );
  const soon = rideIsSoon(pickupIso, atMs);
  const windows = Number.isFinite(durationMin) && durationMin > 0 && pickupIso
    ? [{ start: Date.parse(pickupIso), end: Date.parse(pickupIso) + durationMin * 60000, durationUnknown: false }]
    : [];
  const drivers = [];
  for (const driver of fleet.drivers) {
    const id = sanitizeTenantString(driver.driver_id || driver.driverId, 96);
    if (!id || id === currentDriverId) continue;
    const overlap = windows.length
      ? await checkAssignmentOverlap(env, {
          scope,
          driverId: id,
          pickupIso,
          durationMin,
          excludeBookingId,
          windows,
        })
      : { ok: false, error: "assignment_availability_unknown" };
    const evaluation = evaluateDriverEligibility({
      driver,
      presence: fleet.presenceMap[id] || {},
      vehicles: fleet.vehicles,
      drivers: fleet.drivers,
      atMs,
      pickupIso,
      overlap,
      soon,
    });
    if (evaluation.ok) {
      drivers.push(publicAssignmentChoice(driver, evaluation));
    }
  }
  const current = currentDriverId ? driverFromFleet(fleet, currentDriverId) : null;
  return {
    ok: true,
    soon,
    current_driver: current
      ? {
          driver_id: currentDriverId,
          display_name: safeStr(current.display_name || current.displayName, 160),
        }
      : null,
    drivers,
    empty: drivers.length === 0,
  };
}

export async function assignAgendaRide(env, { scope, bookingId, body }) {
  const { tenantId, companyId } = scopeIds(scope);
  const id = safeStr(bookingId, 160);
  const record = await kvJson(env.BOOKING_KV, `booking:${id}`);
  if (!record) return { ok: false, error: "booking_not_found" };
  if (!bookingCompanyMatches(record, tenantId, companyId)) {
    return { ok: false, error: "booking_not_found" };
  }
  if (!isCapacityBlockingRecord(record)) {
    return { ok: false, error: "booking_not_assignable" };
  }
  const expectedRevision = Number(body?.revision);
  const currentRevision = Number(record.revision || record.booking?.revision || 1) || 1;
  if (Number.isFinite(expectedRevision) && expectedRevision > 0 && expectedRevision !== currentRevision) {
    return { ok: false, error: "revision_conflict", revision: currentRevision };
  }
  const driverId = sanitizeTenantString(
    body?.assigned_driver_id || body?.driver_id,
    96,
  );
  const vehicleId = sanitizeTenantString(
    body?.assigned_vehicle_id || body?.vehicle_id,
    128,
  );
  if (!driverId && !vehicleId) return { ok: false, error: "assignment_required" };
  const leg = resolveAgendaLegTarget(body, record);
  const nextForCheck = applyAgendaLegAssignment({
    ...record,
    booking: record.booking && typeof record.booking === "object" ? { ...record.booking } : {},
    operational_legs: Array.isArray(record.operational_legs)
      ? record.operational_legs.map((row) => ({ ...row }))
      : [],
  }, { leg, driverId, vehicleId, now: new Date().toISOString() });
  const mode = resolveRoundtripDispatchMode(nextForCheck);
  const occupancy = occupancyWindowsForRecord(nextForCheck);
  const assignWindows =
    mode === "split_no_wait" && leg === "return"
      ? occupancy.windows.filter((_, index) => index > 0)
      : mode === "split_no_wait"
        ? occupancy.windows.slice(0, 1)
        : occupancy.windows;
  const enforced = await enforceDispatchAssignment(env, {
    scope: { tenant_id: tenantId, company_id: companyId },
    driverId,
    vehicleId,
    pickupIso: nextForCheck.pickup_iso || nextForCheck.booking?.pickup_iso,
    windows: assignWindows,
    excludeBookingId: id,
  });
  if (!enforced.ok) return enforced;
  const resolvedVehicleId = enforced.vehicleId || vehicleId;
  if (enforced.legacy || enforced.skipped) {
    const overlap = await checkAssignmentOverlap(env, {
      scope: { tenant_id: tenantId, company_id: companyId },
      driverId,
      vehicleId: resolvedVehicleId,
      windows: assignWindows,
      excludeBookingId: id,
    });
    if (!overlap.ok) return overlap;
  }
  const previousDriver = safeStr(record.assigned_driver_id || record.booking?.assigned_driver_id, 96);
  const previousVehicle = safeStr(record.assigned_vehicle_id || record.booking?.assigned_vehicle_id, 128);
  const now = new Date().toISOString();
  const next = applyAgendaLegAssignment({
    ...record,
    assignment_accepted: false,
    driver_accepted: false,
    do_not_dispatch: record.do_not_dispatch === true || record.booking?.do_not_dispatch === true,
    revision: currentRevision + 1,
    updated_at: now,
    history: appendAgendaHistory(record, {
      at: now,
      action: "manual_assign",
      actor: safeStr(body?.actor || "company_admin", 80),
      leg,
    }),
    booking: {
      ...(record.booking && typeof record.booking === "object" ? record.booking : {}),
      assignment_accepted: false,
      do_not_dispatch: record.do_not_dispatch === true || record.booking?.do_not_dispatch === true,
    },
  }, { leg, driverId, vehicleId: resolvedVehicleId, now });
  await removeBookingFromAssignmentIndexes(
    env,
    { tenant_id: tenantId, company_id: companyId, hasScope: true },
    id,
    previousDriver,
    previousVehicle,
  );
  await persistAgendaBooking(env, { tenantId, companyId, bookingId: id, record: next });
  const items = decorateAgendaItem(publicAgendaItem(next, id), next, id);
  return { ok: true, booking_id: id, item: items[0], items };
}

export async function unassignAgendaRide(env, { scope, bookingId, body }) {
  const { tenantId, companyId } = scopeIds(scope);
  const id = safeStr(bookingId, 160);
  const record = await kvJson(env.BOOKING_KV, `booking:${id}`);
  if (!record) return { ok: false, error: "booking_not_found" };
  if (!bookingCompanyMatches(record, tenantId, companyId)) {
    return { ok: false, error: "booking_not_found" };
  }
  const expectedRevision = Number(body?.revision);
  const currentRevision = Number(record.revision || 1) || 1;
  if (Number.isFinite(expectedRevision) && expectedRevision > 0 && expectedRevision !== currentRevision) {
    return { ok: false, error: "revision_conflict", revision: currentRevision };
  }
  const previousDriver = safeStr(record.assigned_driver_id || record.booking?.assigned_driver_id, 96);
  const previousVehicle = safeStr(record.assigned_vehicle_id || record.booking?.assigned_vehicle_id, 128);
  const now = new Date().toISOString();
  const next = {
    ...record,
    assigned_driver_id: null,
    assigned_vehicle_id: null,
    assignment_accepted: false,
    driver_accepted: false,
    do_not_dispatch: record.do_not_dispatch === true || record.booking?.do_not_dispatch === true,
    revision: currentRevision + 1,
    updated_at: now,
    history: appendAgendaHistory(record, {
      at: now,
      action: "manual_unassign",
      actor: safeStr(body?.actor || "company_admin", 80),
    }),
    booking: {
      ...(record.booking && typeof record.booking === "object" ? record.booking : {}),
      assigned_driver_id: null,
      assigned_vehicle_id: null,
      assignment_accepted: false,
    },
  };
  await removeBookingFromAssignmentIndexes(
    env,
    { tenant_id: tenantId, company_id: companyId, hasScope: true },
    id,
    previousDriver,
    previousVehicle,
  );
  await persistAgendaBooking(env, { tenantId, companyId, bookingId: id, record: next });
  const items = decorateAgendaItem(publicAgendaItem(next, id), next, id);
  return { ok: true, booking_id: id, item: items[0], items };
}

export async function rescheduleAgendaRide(env, { scope, bookingId, body }) {
  const { tenantId, companyId } = scopeIds(scope);
  const id = safeStr(bookingId, 160);
  const record = await kvJson(env.BOOKING_KV, `booking:${id}`);
  if (!record) return { ok: false, error: "booking_not_found" };
  if (!bookingCompanyMatches(record, tenantId, companyId)) {
    return { ok: false, error: "booking_not_found" };
  }
  const pickupIso = safeStr(body?.pickup_iso || body?.pickupIso, 80);
  if (!pickupIso || !Number.isFinite(Date.parse(pickupIso))) {
    return { ok: false, error: "pickup_iso_required" };
  }
  const expectedRevision = Number(body?.revision);
  const currentRevision = Number(record.revision || 1) || 1;
  if (Number.isFinite(expectedRevision) && expectedRevision > 0 && expectedRevision !== currentRevision) {
    return { ok: false, error: "revision_conflict", revision: currentRevision };
  }
  const now = new Date().toISOString();
  const leg = resolveAgendaLegTarget(body, record);
  const next = applyAgendaLegPickup({
    ...record,
    revision: currentRevision + 1,
    updated_at: now,
    history: appendAgendaHistory(record, {
      at: now,
      action: "reschedule",
      actor: safeStr(body?.actor || "company_admin", 80),
      from: safeStr(
        leg === "return"
          ? record.return_pickup_iso || record.booking?.return_pickup_iso
          : record.pickup_iso || record.booking?.pickup_iso,
        80,
      ),
      to: pickupIso,
      leg,
    }),
    booking: record.booking && typeof record.booking === "object" ? { ...record.booking } : {},
    operational_legs: Array.isArray(record.operational_legs)
      ? record.operational_legs.map((row) => ({ ...row }))
      : [],
  }, { leg, pickupIso, now });
  const occupancy = occupancyWindowsForRecord(next);
  const driverId = safeStr(next.assigned_driver_id || next.booking?.assigned_driver_id, 96);
  const vehicleId = safeStr(next.assigned_vehicle_id || next.booking?.assigned_vehicle_id, 128);
  if (driverId || vehicleId) {
    const overlap = await checkAssignmentOverlap(env, {
      scope: { tenant_id: tenantId, company_id: companyId },
      driverId,
      vehicleId,
      windows: occupancy.windows,
      excludeBookingId: id,
    });
    if (!overlap.ok) return overlap;
  }
  if (resolveRoundtripDispatchMode(next) === "split_no_wait") {
    const returnLeg = (Array.isArray(next.operational_legs) ? next.operational_legs : []).find(
      (row) => String(row.leg_type || "").toLowerCase() === "return",
    );
    const returnDriver = safeStr(returnLeg?.assigned_driver_id, 96);
    const returnVehicle = safeStr(returnLeg?.assigned_vehicle_id, 128);
    if ((returnDriver && returnDriver !== driverId) || (returnVehicle && returnVehicle !== vehicleId)) {
      const returnWindow = occupancyWindowsFromTimes({
        mode: "single",
        pickupIso: next.return_pickup_iso,
        durationMin: next.return_duration_min,
      });
      const overlap = await checkAssignmentOverlap(env, {
        scope: { tenant_id: tenantId, company_id: companyId },
        driverId: returnDriver,
        vehicleId: returnVehicle,
        windows: returnWindow.windows,
        excludeBookingId: id,
      });
      if (!overlap.ok) return overlap;
    }
  }
  await persistAgendaBooking(env, { tenantId, companyId, bookingId: id, record: next });
  const items = decorateAgendaItem(publicAgendaItem(next, id), next, id);
  return { ok: true, booking_id: id, item: items[0], items };
}

export async function phoneConfirmAgendaRide(env, { scope, bookingId, body }) {
  const { tenantId, companyId } = scopeIds(scope);
  const id = safeStr(bookingId, 160);
  const record = await kvJson(env.BOOKING_KV, `booking:${id}`);
  if (!record) return { ok: false, error: "booking_not_found" };
  if (!bookingCompanyMatches(record, tenantId, companyId)) {
    return { ok: false, error: "booking_not_found" };
  }
  const now = new Date().toISOString();
  const actor = safeStr(body?.actor || "company_admin", 160);
  const currentRevision = Number(record.revision || 1) || 1;
  const next = {
    ...record,
    phone_confirmed_at: now,
    phone_confirmed_by: actor,
    quote_accepted: false,
    revision: currentRevision + 1,
    updated_at: now,
    history: appendAgendaHistory(record, {
      at: now,
      action: "phone_confirmed",
      actor,
    }),
    booking: {
      ...(record.booking && typeof record.booking === "object" ? record.booking : {}),
      phone_confirmed_at: now,
      phone_confirmed_by: actor,
    },
  };
  await persistAgendaBooking(env, { tenantId, companyId, bookingId: id, record: next });
  const items = decorateAgendaItem(publicAgendaItem(next, id), next, id);
  return { ok: true, booking_id: id, item: items[0], items };
}

async function serveAgendaMutation(env, action, payload) {
  const {
    callCompanyCustomerImportCoordinator,
    hasCompanyCustomerImportCoordinator,
  } = await import("./company_customer_import_coordinator.mjs");
  if (!hasCompanyCustomerImportCoordinator(env)) {
    return { ok: false, error: "import_coordinator_unavailable" };
  }
  return callCompanyCustomerImportCoordinator(env, {
    action,
    scope: payload.scope,
    bookingId: payload.bookingId,
    body: payload.body || {},
  });
}

export async function serveCompanyAgendaHttp({ env, method, route, url, body, request }) {
  const scope = {
    tenant_id: url.searchParams.get("tenant_id") || body?.tenant_id,
    company_id: url.searchParams.get("company_id") || body?.company_id,
  };
  if (route.kind === "rides" && method === "GET") {
    const listed = await listAgendaRides(env, {
      scope,
      fromIso: url.searchParams.get("from") || url.searchParams.get("from_iso"),
      toIso: url.searchParams.get("to") || url.searchParams.get("to_iso"),
      limit: url.searchParams.get("limit"),
      cursor: url.searchParams.get("cursor") || url.searchParams.get("next_cursor") || "",
    });
    if (!listed.ok) return json(listed, 400);
    return json(listed, 200);
  }
  if (route.kind === "rides" && method === "POST") {
    const idem =
      request?.headers?.get?.("idempotency-key") ||
      request?.headers?.get?.("Idempotency-Key") ||
      body?.idempotency_key ||
      body?.idempotencyKey;
    const created = await createAgendaRide(env, {
      scope,
      body: body || {},
      idempotencyKey: idem,
    });
    if (!created.ok) {
      const status = created.error === "price_changed" ? 409 : 400;
      return json(created, status);
    }
    return json(created, created.idempotent ? 200 : 201);
  }
  if (route.kind === "assignment-choices" && method === "GET") {
    const listed = await listAssignmentChoices(env, {
      scope,
      pickupIso: url.searchParams.get("pickup_iso"),
      durationMin: url.searchParams.get("duration_min"),
      excludeBookingId: url.searchParams.get("exclude_booking_id"),
      currentDriverId: url.searchParams.get("current_driver_id"),
      returnPickupIso: url.searchParams.get("return_pickup_iso"),
      returnDurationMin: url.searchParams.get("return_duration_min"),
    });
    return json(listed, 200);
  }
  if (route.kind === "overlap" && method === "GET") {
    const checked = await checkAssignmentOverlap(env, {
      scope,
      driverId: url.searchParams.get("driver_id"),
      vehicleId: url.searchParams.get("vehicle_id"),
      pickupIso: url.searchParams.get("pickup_iso"),
      durationMin: url.searchParams.get("duration_min"),
      returnPickupIso: url.searchParams.get("return_pickup_iso"),
      returnDurationMin: url.searchParams.get("return_duration_min"),
      roundtripMode: url.searchParams.get("roundtrip_dispatch_mode"),
      excludeBookingId: url.searchParams.get("exclude_booking_id"),
    });
    if (!checked.ok) return json(checked, 409);
    return json(checked, 200);
  }
  if (
    (route.kind === "assign" ||
      route.kind === "unassign" ||
      route.kind === "reschedule" ||
      route.kind === "phone-confirm") &&
    (method === "POST" || method === "PATCH")
  ) {
    const action =
      route.kind === "phone-confirm"
        ? "phone_confirm_booking"
        : `${route.kind}_booking`;
    const mutated = await serveAgendaMutation(env, action, {
      scope,
      bookingId: route.bookingId,
      body: body || {},
    });
    if (!mutated.ok) {
      const status =
        assignmentConflictStatus(mutated.error) ||
        mutated.error === "revision_conflict"
          ? 409
          : mutated.error === "booking_not_found"
            ? 404
            : mutated.status || 400;
      return json(mutated, status);
    }
    return json(mutated, 200);
  }
  return json({ ok: false, error: "not_found" }, 404);
}
