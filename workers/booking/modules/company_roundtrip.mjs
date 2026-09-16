// Company CRM/agenda roundtrip — same decision table as street
// split_no_wait / continuous_wait / single. Airport ride_options.wait_min
// stays separate from occupancy wait_min.

import { safeStr, sanitizeTenantString } from "./parsing_utils.js";

export const ROUNDTRIP_SINGLE = "single";
export const ROUNDTRIP_SPLIT = "split_no_wait";
export const ROUNDTRIP_CONTINUOUS = "continuous_wait";

export function parseDurationMin(value, fallback = null) {
  const n = Number(value);
  if (!Number.isFinite(n) || n <= 0) return fallback;
  return Math.round(n);
}

export function firstPositiveDurationMin(values) {
  for (const value of values) {
    const parsed = parseDurationMin(value, null);
    if (parsed != null) return parsed;
  }
  return null;
}

function bookingMap(record) {
  return record?.booking && typeof record.booking === "object" ? record.booking : {};
}

function quoteMap(record) {
  return record?.quote && typeof record.quote === "object" ? record.quote : {};
}

function normalizeStopList(raw) {
  if (!Array.isArray(raw)) return [];
  return raw.map((item) => safeStr(item, 240)).filter(Boolean).slice(0, 10);
}

function firstMoney(values) {
  for (const value of values) {
    if (value == null || value === "") continue;
    const n = Number(String(value).replace(",", "."));
    if (Number.isFinite(n)) return n;
  }
  return null;
}

export function resolveBookingDurationMin(record) {
  const booking = bookingMap(record);
  const quote = quoteMap(record);
  const legs = operationalLegsOf(record);
  const outbound =
    legs.find((leg) => String(leg?.leg_type || "").toLowerCase() === "outbound") ||
    legs[0];
  return firstPositiveDurationMin([
    record?.duration_min,
    record?.durationMin,
    record?.duration_minutes,
    record?.durationMinutes,
    booking.duration_min,
    booking.durationMin,
    booking.duration_minutes,
    booking.durationMinutes,
    booking.duration_route_min,
    booking.route_duration_min,
    record?.duration_route_min,
    record?.route_duration_min,
    outbound?.duration_min,
    outbound?.durationMin,
    outbound?.duration_minutes,
    outbound?.durationMinutes,
    quote.duration_min,
    quote.durationMin,
    quote.duration_route_min,
    quote.route_duration_min,
    quote?.pricing_main?.breakdown?.duration_min,
    record?.requested_duration_minutes,
    booking.requested_duration_minutes,
    quote.requested_duration_minutes,
  ]);
}

export function resolveBookingReturnDurationMin(record) {
  const booking = bookingMap(record);
  const quote = quoteMap(record);
  const returnLeg = operationalLegsOf(record).find(
    (leg) => String(leg?.leg_type || "").toLowerCase() === "return",
  );
  const explicit = firstPositiveDurationMin([
    record?.return_duration_min,
    record?.returnDurationMin,
    booking.return_duration_min,
    booking.returnDurationMin,
    returnLeg?.duration_min,
    returnLeg?.durationMin,
    quote?.return?.duration_min,
    quote?.return?.durationMin,
  ]);
  if (explicit != null) return explicit;
  // Waiting return uses the same reverse route; do not require an empty
  // "Duur terugrit" field as the occupancy source.
  if (resolveRoundtripDispatchMode(record) === ROUNDTRIP_CONTINUOUS) {
    return resolveBookingDurationMin(record);
  }
  return null;
}

export function resolveBookingPriceInclVat(record) {
  const booking = bookingMap(record);
  const quote = quoteMap(record);
  const outbound =
    operationalLegsOf(record).find(
      (leg) => String(leg?.leg_type || "").toLowerCase() === "outbound",
    ) || operationalLegsOf(record)[0];
  return firstMoney([
    booking.price_incl_vat,
    record?.price_incl_vat,
    booking.amount_incl_vat,
    record?.amount_incl_vat,
    booking.price,
    record?.price,
    booking.total_price,
    record?.total_price,
    outbound?.price_incl_vat,
    outbound?.priceInclVat,
    outbound?.amount_incl_vat,
    quote?.pricing?.price_incl_vat,
    quote?.pricing_main?.price_incl_vat,
    quote?.price_incl_vat,
  ]);
}

export function resolveBookingPriceExVat(record) {
  const booking = bookingMap(record);
  const quote = quoteMap(record);
  const outbound =
    operationalLegsOf(record).find(
      (leg) => String(leg?.leg_type || "").toLowerCase() === "outbound",
    ) || operationalLegsOf(record)[0];
  return firstMoney([
    booking.price_ex_vat,
    record?.price_ex_vat,
    booking.amount_ex_vat,
    record?.amount_ex_vat,
    outbound?.price_ex_vat,
    quote?.pricing?.price_ex_vat,
    quote?.pricing_main?.price_ex_vat,
  ]);
}

export function resolveBookingPriceVat(record) {
  const booking = bookingMap(record);
  const quote = quoteMap(record);
  const outbound =
    operationalLegsOf(record).find(
      (leg) => String(leg?.leg_type || "").toLowerCase() === "outbound",
    ) || operationalLegsOf(record)[0];
  return firstMoney([
    booking.price_vat,
    record?.price_vat,
    booking.amount_vat,
    record?.amount_vat,
    outbound?.price_vat,
    quote?.pricing?.price_vat,
    quote?.pricing_main?.price_vat,
  ]);
}

export function resolveBookingCurrency(record) {
  const booking = bookingMap(record);
  const quote = quoteMap(record);
  return (
    safeStr(booking.currency || record?.currency || quote?.currency || quote?.pricing?.currency, 8) ||
    "EUR"
  );
}

export function resolveBookingPricingSource(record) {
  const booking = bookingMap(record);
  const quote = quoteMap(record);
  return safeStr(
    record?.pricing_source ||
      booking.pricing_source ||
      quote.pricing_source ||
      quote?.pricing?.pricing_source,
    40,
  );
}

export function resolveBookingDistanceKm(record) {
  const booking = bookingMap(record);
  const quote = quoteMap(record);
  return firstMoney([
    record?.distance_km,
    booking.distance_km,
    quote.distance_km,
    quote?.pricing_main?.breakdown?.distance_km,
  ]);
}

export function normalizeReturnEnabled(body) {
  const explicit = !!(
    body?.return_enabled ??
    body?.returnEnabled ??
    body?.return ??
    body?.isReturn ??
    body?.retour ??
    body?.retour_enabled
  );
  return { explicit, forced: false, enabled: explicit };
}

export function normalizeRoundtripChoice(raw) {
  const text = String(raw || "")
    .trim()
    .toLowerCase()
    .replace(/-/g, "_");
  if (
    text === ROUNDTRIP_SPLIT ||
    text === "split" ||
    text === "no_wait" ||
    text === "heen_terug_geen_wacht"
  ) {
    return ROUNDTRIP_SPLIT;
  }
  if (
    text === ROUNDTRIP_CONTINUOUS ||
    text === "continuous" ||
    text === "wait" ||
    text === "heen_terug_wacht"
  ) {
    return ROUNDTRIP_CONTINUOUS;
  }
  if (text === ROUNDTRIP_SINGLE || text === "one_way" || text === "enkele_rit") {
    return ROUNDTRIP_SINGLE;
  }
  return "";
}

function firstText(source, keys, max = 240) {
  const rec = source && typeof source === "object" ? source : {};
  for (const key of keys) {
    const value = safeStr(rec[key], max);
    if (value) return value;
  }
  return "";
}

function firstCoord(source, keys) {
  const rec = source && typeof source === "object" ? source : {};
  for (const key of keys) {
    const n = Number(rec[key]);
    if (Number.isFinite(n)) return n;
  }
  return null;
}

export function readRoundtripContext(source) {
  const rec = source && typeof source === "object" ? source : {};
  const booking = rec.booking && typeof rec.booking === "object" ? rec.booking : {};
  const payload = rec.payload && typeof rec.payload === "object" ? rec.payload : {};
  const quote = rec.quote && typeof rec.quote === "object" ? rec.quote : {};
  const returnEnabled = !!(
    rec.return_enabled ??
    rec.returnEnabled ??
    booking.return_enabled ??
    booking.returnEnabled ??
    payload.return_enabled ??
    payload.return ??
    quote.return?.enabled ??
    false
  );
  const returnPickupIso = firstText(rec, [
    "return_pickup_iso",
    "returnPickupIso",
  ], 80) ||
    firstText(booking, ["return_pickup_iso", "returnPickupIso"], 80) ||
    firstText(payload, ["return_pickup_iso", "returnPickupIso"], 80) ||
    safeStr(quote.return?.pickup_iso, 80);
  const occupancyWait = parseDurationMin(
    rec.occupancy_wait_min ??
      rec.occupancyWaitMin ??
      booking.occupancy_wait_min ??
      rec.wait_min ??
      rec.waitMin ??
      booking.wait_min ??
      booking.waitMin ??
      payload.wait_min ??
      quote.wait_min,
    0,
  );
  const stamped = normalizeRoundtripChoice(
    rec.roundtrip_dispatch_mode ??
      rec.roundtripDispatchMode ??
      booking.roundtrip_dispatch_mode ??
      payload.roundtrip_dispatch_mode ??
      quote.roundtrip_dispatch_mode,
  );
  return {
    returnEnabled,
    hasReturnSchedule: !!returnPickupIso,
    returnPickupIso,
    occupancyWaitMin: Math.max(0, occupancyWait || 0),
    stampedMode: stamped,
  };
}

export function shouldSplitOperationalReturnLeg(ctx) {
  if (!ctx?.returnEnabled) return false;
  if (Math.max(0, Number(ctx.occupancyWaitMin) || 0) > 0) return false;
  return !!ctx.hasReturnSchedule;
}

export function resolveRoundtripDispatchMode(source) {
  const ctx = readRoundtripContext(source);
  if (ctx.stampedMode === ROUNDTRIP_SPLIT || ctx.stampedMode === ROUNDTRIP_CONTINUOUS || ctx.stampedMode === ROUNDTRIP_SINGLE) {
    if (ctx.stampedMode === ROUNDTRIP_SINGLE) return ROUNDTRIP_SINGLE;
    if (!ctx.returnEnabled || !ctx.hasReturnSchedule) return ROUNDTRIP_SINGLE;
    return ctx.stampedMode;
  }
  if (shouldSplitOperationalReturnLeg(ctx)) return ROUNDTRIP_SPLIT;
  if (ctx.returnEnabled && !shouldSplitOperationalReturnLeg(ctx) && ctx.occupancyWaitMin > 0) {
    return ROUNDTRIP_CONTINUOUS;
  }
  return ROUNDTRIP_SINGLE;
}

export function computeOccupancyWaitMin({
  pickupIso,
  durationMin,
  returnPickupIso,
} = {}) {
  const start = Date.parse(String(pickupIso || ""));
  const ret = Date.parse(String(returnPickupIso || ""));
  const duration = parseDurationMin(durationMin, null);
  if (!Number.isFinite(start) || !Number.isFinite(ret) || duration == null) {
    return { ok: false, waitMin: null, unknown: true };
  }
  const outboundEnd = start + duration * 60000;
  const waitMin = Math.max(0, Math.round((ret - outboundEnd) / 60000));
  return { ok: true, waitMin, unknown: false, outboundEnd };
}

export function rideWindow(pickupIso, durationMin) {
  const start = Date.parse(String(pickupIso || ""));
  if (!Number.isFinite(start)) return { ok: false, error: "invalid_pickup_iso" };
  const duration = parseDurationMin(durationMin, null);
  if (duration == null) {
    return { ok: true, start, end: null, durationUnknown: true };
  }
  return { ok: true, start, end: start + duration * 60000, durationUnknown: false };
}

export function occupancyWindowsFromTimes({
  mode,
  pickupIso,
  durationMin,
  returnPickupIso,
  returnDurationMin,
} = {}) {
  const resolved = normalizeRoundtripChoice(mode) || ROUNDTRIP_SINGLE;
  const outbound = rideWindow(pickupIso, durationMin);
  if (!outbound.ok) return { ok: false, error: outbound.error, windows: [], unknown: true };

  if (resolved === ROUNDTRIP_SINGLE) {
    return {
      ok: true,
      unknown: outbound.durationUnknown,
      windows: outbound.durationUnknown ? [] : [outbound],
    };
  }

  if (resolved === ROUNDTRIP_SPLIT) {
    const ret = rideWindow(returnPickupIso, returnDurationMin);
    const windows = [];
    let unknown = false;
    if (outbound.durationUnknown) unknown = true;
    else windows.push(outbound);
    if (!ret.ok) unknown = true;
    else if (ret.durationUnknown) unknown = true;
    else windows.push(ret);
    return { ok: true, unknown, windows };
  }

  const wait = computeOccupancyWaitMin({
    pickupIso,
    durationMin,
    returnPickupIso,
  });
  const returnDuration =
    parseDurationMin(returnDurationMin, null) ?? parseDurationMin(durationMin, null);
  if (wait.unknown || returnDuration == null || !Number.isFinite(Date.parse(String(returnPickupIso || "")))) {
    return { ok: true, unknown: true, windows: [] };
  }
  const returnStart = Date.parse(String(returnPickupIso));
  return {
    ok: true,
    unknown: false,
    windows: [
      {
        ok: true,
        start: outbound.start,
        end: returnStart + returnDuration * 60000,
        durationUnknown: false,
      },
    ],
  };
}

const NON_CAPACITY_LEG_STATUSES = new Set([
  "cancelled",
  "canceled",
  "no_show",
  "rejected",
  "expired",
  "completed",
  "deleted",
  "void",
]);

export function operationalLegsOf(record) {
  const booking = record?.booking && typeof record.booking === "object" ? record.booking : {};
  if (Array.isArray(record?.operational_legs) && record.operational_legs.length) {
    return record.operational_legs;
  }
  if (Array.isArray(booking.operational_legs)) return booking.operational_legs;
  return [];
}

export function isCapacityBlockingLeg(leg) {
  if (!leg || typeof leg !== "object") return true;
  const status = String(
    leg.status || leg.lifecycle_status || leg.lifecycleStatus || leg.lifecycle || "",
  )
    .trim()
    .toLowerCase();
  if (!status) return true;
  return !NON_CAPACITY_LEG_STATUSES.has(status);
}

export function occupancyWindowsForRecord(record) {
  const booking = record?.booking && typeof record.booking === "object" ? record.booking : {};
  const mode = resolveRoundtripDispatchMode(record);
  const legs = operationalLegsOf(record);
  if (mode === ROUNDTRIP_SPLIT && legs.length) {
    const windows = [];
    let unknown = false;
    for (const leg of legs) {
      if (!isCapacityBlockingLeg(leg)) continue;
      const pickup = firstText(leg, ["pickup_iso", "pickupIso"], 80);
      const duration = firstPositiveDurationMin([
        leg.duration_min,
        leg.durationMin,
        String(leg?.leg_type || "").toLowerCase() === "return"
          ? resolveBookingReturnDurationMin(record)
          : resolveBookingDurationMin(record),
      ]);
      const window = rideWindow(pickup, duration);
      if (!window.ok || window.durationUnknown) unknown = true;
      else windows.push(window);
    }
    return { ok: true, unknown, windows };
  }
  const pickupIso = firstText(record, ["pickup_iso", "pickupIso"], 80) ||
    firstText(booking, ["pickup_iso", "pickupIso", "pickupStartIso"], 80);
  const durationMin = resolveBookingDurationMin(record);
  const returnPickupIso = firstText(record, ["return_pickup_iso", "returnPickupIso"], 80) ||
    firstText(booking, ["return_pickup_iso", "returnPickupIso"], 80);
  const returnDurationMin = resolveBookingReturnDurationMin(record);
  return occupancyWindowsFromTimes({
    mode,
    pickupIso,
    durationMin,
    returnPickupIso,
    returnDurationMin,
  });
}

export function parseCompanyRoundtripWrite(body = {}) {
  const choice = normalizeRoundtripChoice(
    body.roundtrip_dispatch_mode ??
      body.roundtripDispatchMode ??
      body.roundtrip_choice ??
      body.roundtripChoice ??
      body.return_mode ??
      body.returnMode,
  );
  const returnEnabledFlag = normalizeReturnEnabled(body).enabled;
  const returnPickupIso = safeStr(body.return_pickup_iso ?? body.returnPickupIso, 80);
  let mode = choice;
  if (!mode) {
    if (!returnEnabledFlag && !returnPickupIso) mode = ROUNDTRIP_SINGLE;
    else if (returnEnabledFlag && returnPickupIso) {
      const explicitWait = parseDurationMin(
        body.occupancy_wait_min ?? body.occupancyWaitMin ?? body.wait_min ?? body.waitMin,
        0,
      );
      mode = explicitWait > 0 ? ROUNDTRIP_CONTINUOUS : ROUNDTRIP_SPLIT;
    } else {
      mode = ROUNDTRIP_SINGLE;
    }
  }

  const pickupIso = safeStr(body.pickup_iso ?? body.pickupIso ?? body.start_at ?? body.startAt, 80);
  const durationMin = parseDurationMin(body.duration_min ?? body.durationMin, null);
  const returnDurationMin = parseDurationMin(
    body.return_duration_min ?? body.returnDurationMin,
    mode === ROUNDTRIP_CONTINUOUS ? durationMin : null,
  );
  const from = safeStr(body.from ?? body.pickup, 240);
  const to = safeStr(body.to ?? body.dropoff, 240);
  const returnFrom = safeStr(body.return_from ?? body.returnFrom, 240) || (mode === ROUNDTRIP_SINGLE ? "" : to);
  const returnTo = safeStr(body.return_to ?? body.returnTo, 240) || (mode === ROUNDTRIP_SINGLE ? "" : from);

  if (mode !== ROUNDTRIP_SINGLE && !returnPickupIso) {
    return { ok: false, error: "return_pickup_iso_required", mode };
  }
  if (mode !== ROUNDTRIP_SINGLE && Number.isFinite(Date.parse(returnPickupIso)) === false) {
    return { ok: false, error: "return_pickup_iso_required", mode };
  }

  let occupancyWaitMin = 0;
  let occupancyUnknown = false;
  if (mode === ROUNDTRIP_CONTINUOUS) {
    const computed = computeOccupancyWaitMin({
      pickupIso,
      durationMin,
      returnPickupIso,
    });
    if (computed.ok) occupancyWaitMin = Math.max(1, computed.waitMin);
    else {
      occupancyUnknown = true;
      occupancyWaitMin = parseDurationMin(
        body.occupancy_wait_min ?? body.occupancyWaitMin,
        1,
      ) || 1;
    }
    if (returnDurationMin == null) occupancyUnknown = true;
  }

  return {
    ok: true,
    mode,
    returnEnabled: mode !== ROUNDTRIP_SINGLE,
    pickupIso,
    durationMin,
    returnPickupIso: mode === ROUNDTRIP_SINGLE ? "" : returnPickupIso,
    returnDurationMin: mode === ROUNDTRIP_SINGLE ? null : returnDurationMin,
    returnFrom,
    returnTo,
    occupancyWaitMin,
    occupancyUnknown,
    from,
    to,
    returnPickupLat: firstCoord(body, ["return_pickup_lat", "returnPickupLat"]),
    returnPickupLon: firstCoord(body, ["return_pickup_lon", "returnPickupLon"]),
    returnPickupPlaceId: safeStr(body.return_pickup_place_id ?? body.returnPickupPlaceId, 80),
    returnDropoffLat: firstCoord(body, ["return_dropoff_lat", "returnDropoffLat"]),
    returnDropoffLon: firstCoord(body, ["return_dropoff_lon", "returnDropoffLon"]),
    returnDropoffPlaceId: safeStr(body.return_dropoff_place_id ?? body.returnDropoffPlaceId, 80),
    returnDriverId: sanitizeTenantString(
      body.return_assigned_driver_id ?? body.return_driver_id ?? body.returnDriverId,
      96,
    ),
    returnVehicleId: sanitizeTenantString(
      body.return_assigned_vehicle_id ?? body.return_vehicle_id ?? body.returnVehicleId,
      128,
    ),
    outboundDriverId: sanitizeTenantString(
      body.assigned_driver_id ?? body.driver_id,
      96,
    ),
    outboundVehicleId: sanitizeTenantString(
      body.assigned_vehicle_id ?? body.vehicle_id,
      128,
    ),
    outboundStops: normalizeStopList(body.stops || body.outbound_stops || body.outboundStops),
    returnStops: normalizeStopList(body.return_stops || body.returnStops),
  };
}

export function parseCompanyRoundtripFromQuote(record = {}) {
  return parseCompanyRoundtripWrite({
    ...record,
    pickup_iso: record.start_at || record.pickup_iso,
    from: record.pickup || record.from,
    to: record.dropoff || record.to,
  });
}

function operationalLeg({
  parentBookingId,
  legKey,
  legType,
  pickupIso,
  from,
  to,
  durationMin,
    assignedDriverId,
    assignedVehicleId,
    createdAt,
    updatedAt,
    status = "PENDING",
    stops = [],
}) {
  const parent = safeStr(parentBookingId, 160);
  const key = safeStr(legKey, 24).toUpperCase() || "LEG";
  const legId = parent ? `${parent}:${key}` : "";
  const lifecycle = String(status || "PENDING").toLowerCase();
  return {
    leg_id: legId,
    legId,
    parent_booking_id: parent,
    parentBookingId: parent,
    leg_type: legType,
    legType,
    pickup_iso: pickupIso || "",
    pickupIso: pickupIso || "",
    from: from || "",
    to: to || "",
    duration_min: durationMin,
    durationMin,
    price_incl_vat: null,
    priceInclVat: null,
    assigned_driver_id: assignedDriverId || null,
    assignedDriverId: assignedDriverId || null,
    assigned_vehicle_id: assignedVehicleId || null,
    assignedVehicleId: assignedVehicleId || null,
    stops: Array.isArray(stops) ? stops : [],
    status,
    lifecycle,
    created_at: createdAt,
    updated_at: updatedAt,
  };
}

export function buildCompanyOperationalLegs({ bookingId, parsed, createdAt, updatedAt, status = "PENDING" }) {
  if (!parsed?.returnEnabled) return [];
  const outbound = operationalLeg({
    parentBookingId: bookingId,
    legKey: "OUTBOUND",
    legType: "outbound",
    pickupIso: parsed.pickupIso,
    from: parsed.from || "",
    to: parsed.to || "",
    durationMin: parsed.durationMin,
    assignedDriverId: parsed.outboundDriverId,
    assignedVehicleId: parsed.outboundVehicleId,
    stops: parsed.outboundStops || [],
    createdAt,
    updatedAt,
    status,
  });
  if (parsed.mode !== ROUNDTRIP_SPLIT) return [outbound];
  return [
    outbound,
    operationalLeg({
      parentBookingId: bookingId,
      legKey: "RETURN",
      legType: "return",
      pickupIso: parsed.returnPickupIso,
      from: parsed.returnFrom,
      to: parsed.returnTo,
      durationMin: parsed.returnDurationMin,
      assignedDriverId: parsed.returnDriverId || parsed.outboundDriverId,
      assignedVehicleId: parsed.returnVehicleId || parsed.outboundVehicleId,
      stops: parsed.returnStops || [],
      createdAt,
      updatedAt,
      status,
    }),
  ];
}

export function applyCompanyRoundtripFields(record, parsed, { bookingId, now } = {}) {
  if (!record || !parsed?.ok) return record;
  const id = safeStr(bookingId || record.booking_id, 160);
  const booking = record.booking && typeof record.booking === "object" ? record.booking : {};
  const airportWait = Number(record.ride_options?.wait_min ?? booking.ride_options?.wait_min ?? 0) || 0;
  const occupancyWait = parsed.mode === ROUNDTRIP_CONTINUOUS ? parsed.occupancyWaitMin : 0;
  const bookingWait = parsed.mode === ROUNDTRIP_SINGLE ? airportWait : occupancyWait;
  const legs = buildCompanyOperationalLegs({
    bookingId: id,
    parsed,
    createdAt: record.created_at || now,
    updatedAt: now || record.updated_at,
    status: record.status || "PENDING",
  });
  record.return_enabled = parsed.returnEnabled;
  record.return_pickup_iso = parsed.returnPickupIso || null;
  record.return_from = parsed.returnFrom || "";
  record.return_to = parsed.returnTo || "";
  record.return_duration_min = parsed.returnDurationMin;
  record.return_duration_unknown = parsed.mode !== ROUNDTRIP_SINGLE && parsed.returnDurationMin == null;
  record.occupancy_wait_min = occupancyWait;
  record.occupancy_unknown = parsed.occupancyUnknown === true;
  record.roundtrip_dispatch_mode = parsed.mode;
  record.parent_assignment_mode = parsed.mode === ROUNDTRIP_SPLIT ? "per_leg" : "parent";
  record.wait_min = bookingWait;
  record.return_pickup_lat = parsed.returnPickupLat;
  record.return_pickup_lon = parsed.returnPickupLon;
  record.return_pickup_place_id = parsed.returnPickupPlaceId || "";
  record.return_dropoff_lat = parsed.returnDropoffLat;
  record.return_dropoff_lon = parsed.returnDropoffLon;
  record.return_dropoff_place_id = parsed.returnDropoffPlaceId || "";
  record.outbound_stops = parsed.outboundStops || [];
  record.return_stops = parsed.returnStops || [];
  if (legs.length) record.operational_legs = legs;
  else delete record.operational_legs;

  record.booking = {
    ...booking,
    return_enabled: parsed.returnEnabled,
    return_pickup_iso: parsed.returnPickupIso || null,
    return_from: parsed.returnFrom || "",
    return_to: parsed.returnTo || "",
    return_duration_min: parsed.returnDurationMin,
    occupancy_wait_min: occupancyWait,
    occupancy_unknown: parsed.occupancyUnknown === true,
    roundtrip_dispatch_mode: parsed.mode,
    wait_min: bookingWait,
    return_pickup_lat: parsed.returnPickupLat,
    return_pickup_lon: parsed.returnPickupLon,
    return_pickup_place_id: parsed.returnPickupPlaceId || "",
    return_dropoff_lat: parsed.returnDropoffLat,
    return_dropoff_lon: parsed.returnDropoffLon,
    return_dropoff_place_id: parsed.returnDropoffPlaceId || "",
    outbound_stops: parsed.outboundStops || [],
    return_stops: parsed.returnStops || [],
    ...(legs.length ? { operational_legs: legs } : {}),
  };
  return record;
}

export function quoteRoundtripPublicFields(record = {}) {
  const mode = resolveRoundtripDispatchMode(record);
  return {
    return_enabled: mode !== ROUNDTRIP_SINGLE,
    roundtrip_dispatch_mode: mode,
    return_pickup_iso: firstText(record, ["return_pickup_iso", "returnPickupIso"], 80),
    return_from: firstText(record, ["return_from", "returnFrom"], 240),
    return_to: firstText(record, ["return_to", "returnTo"], 240),
    return_duration_min: parseDurationMin(record.return_duration_min ?? record.returnDurationMin, null),
    occupancy_wait_min: parseDurationMin(record.occupancy_wait_min ?? record.occupancyWaitMin, null),
    occupancy_unknown: record.occupancy_unknown === true,
    return_pickup_lat: firstCoord(record, ["return_pickup_lat", "returnPickupLat"]),
    return_pickup_lon: firstCoord(record, ["return_pickup_lon", "returnPickupLon"]),
    return_pickup_place_id: firstText(record, ["return_pickup_place_id", "returnPickupPlaceId"], 80),
    return_dropoff_lat: firstCoord(record, ["return_dropoff_lat", "returnDropoffLat"]),
    return_dropoff_lon: firstCoord(record, ["return_dropoff_lon", "returnDropoffLon"]),
    return_dropoff_place_id: firstText(record, ["return_dropoff_place_id", "returnDropoffPlaceId"], 80),
    return_assigned_driver_id: firstText(record, ["return_assigned_driver_id", "returnDriverId"], 96),
    return_assigned_vehicle_id: firstText(record, ["return_assigned_vehicle_id", "returnVehicleId"], 128),
    price_covers: mode === ROUNDTRIP_SINGLE ? "ride" : "full_assignment",
  };
}

export function formatQuoteRoundtripHtml(record) {
  const mode = resolveRoundtripDispatchMode(record);
  if (mode === ROUNDTRIP_SINGLE) return "";
  const waitLabel = mode === ROUNDTRIP_CONTINUOUS
    ? "Heen en terug — chauffeur blijft wachten"
    : "Heen en terug — chauffeur wacht niet";
  const returnFrom = firstText(record, ["return_from", "returnFrom"], 240) || record.dropoff || "";
  const returnTo = firstText(record, ["return_to", "returnTo"], 240) || record.pickup || "";
  const returnAt = firstText(record, ["return_pickup_iso", "returnPickupIso"], 80);
  const amountNote = "Het ingevulde bedrag geldt voor de volledige opdracht, niet per ritdeel.";
  return `<p id="roundtrip-choice">${waitLabel}</p>
<p id="outbound-leg">Heenrit: ${record.pickup || ""} → ${record.dropoff || ""} · ${record.start_at || ""}</p>
<p id="return-leg">Terugrit: ${returnFrom} → ${returnTo} · ${returnAt}</p>
<p id="price-covers">${amountNote}</p>`;
}

export function indexRoundtripFields(record) {
  const booking = record?.booking && typeof record.booking === "object" ? record.booking : {};
  const mode = resolveRoundtripDispatchMode(record);
  const returnPickupIso = firstText(record, ["return_pickup_iso", "returnPickupIso"], 80) ||
    firstText(booking, ["return_pickup_iso", "returnPickupIso"], 80);
  const returnDurationMin = parseDurationMin(
    record?.return_duration_min ?? booking.return_duration_min,
    null,
  );
  const occupancy = occupancyWindowsForRecord(record);
  const occupancyEnd = occupancy.windows[0]?.end;
  return {
    return_pickup_iso: returnPickupIso || "",
    return_duration_min: returnDurationMin,
    occupancy_unknown: occupancy.unknown === true,
    occupancy_end_iso: Number.isFinite(occupancyEnd) ? new Date(occupancyEnd).toISOString() : "",
    roundtrip_dispatch_mode: mode,
  };
}

export function indexItemOverlapsPeriod(item, fromMs, toMs, { lookbackMs = 12 * 60 * 60 * 1000 } = {}) {
  const pickup = Date.parse(String(item?.pickup_iso || item?.pickupIso || ""));
  const durationMin = parseDurationMin(item?.duration_min ?? item?.durationMin, null);
  const outboundEnd = Number.isFinite(pickup)
    ? pickup + (durationMin != null ? durationMin * 60000 : lookbackMs)
    : 0;
  const outboundHit = Number.isFinite(pickup) && outboundEnd > fromMs && pickup < toMs;
  const returnPickup = Date.parse(String(item?.return_pickup_iso || item?.returnPickupIso || ""));
  const returnDuration = parseDurationMin(item?.return_duration_min, null);
  const returnEnd = Number.isFinite(returnPickup)
    ? returnPickup + (returnDuration != null ? returnDuration * 60000 : lookbackMs)
    : 0;
  const returnHit = Number.isFinite(returnPickup) && returnEnd > fromMs && returnPickup < toMs;
  const occupancyEnd = Date.parse(String(item?.occupancy_end_iso || ""));
  const occupancyHit =
    Number.isFinite(pickup) &&
    Number.isFinite(occupancyEnd) &&
    occupancyEnd > fromMs &&
    pickup < toMs;
  return outboundHit || returnHit || occupancyHit;
}

export function decorateAgendaItem(item, record, bookingId) {
  const mode = resolveRoundtripDispatchMode(record);
  const booking = record?.booking && typeof record.booking === "object" ? record.booking : {};
  const airportWait = Number(item?.ride_options?.wait_min ?? record?.ride_options?.wait_min ?? 0) || 0;
  const occupancy = occupancyWindowsForRecord(record);
  const returnPickupIso = firstText(record, ["return_pickup_iso", "returnPickupIso"], 80) ||
    firstText(booking, ["return_pickup_iso", "returnPickupIso"], 80);
  const returnFrom = firstText(record, ["return_from", "returnFrom"], 240) ||
    firstText(booking, ["return_from", "returnFrom"], 240) ||
    safeStr(item?.to, 240);
  const returnTo = firstText(record, ["return_to", "returnTo"], 240) ||
    firstText(booking, ["return_to", "returnTo"], 240) ||
    safeStr(item?.from, 240);
  const returnDuration = resolveBookingReturnDurationMin(record);
  const legs = Array.isArray(record?.operational_legs) ? record.operational_legs : [];
  const outboundLeg = legs.find((leg) => String(leg?.leg_type || "").toLowerCase() === "outbound");
  const returnLeg = legs.find((leg) => String(leg?.leg_type || "").toLowerCase() === "return");
  const shared = {
    parent_booking_id: bookingId,
    roundtrip_dispatch_mode: mode,
    occupancy_wait_min: parseDurationMin(record?.occupancy_wait_min ?? booking.occupancy_wait_min, null),
    occupancy_unknown: occupancy.unknown === true,
    airport_wait_min: airportWait,
    wait_min: airportWait,
    return_pickup_iso: returnPickupIso,
    return_from: returnFrom,
    return_to: returnTo,
    return_duration_min: returnDuration,
    price_covers: mode === ROUNDTRIP_SINGLE ? "ride" : "full_assignment",
  };

  if (mode !== ROUNDTRIP_SPLIT) {
    const occupancyEnd = occupancy.windows[0]?.end;
    const occupancyMin =
      Number.isFinite(occupancyEnd) && Number.isFinite(Date.parse(item.pickup_iso || ""))
        ? Math.round((occupancyEnd - Date.parse(item.pickup_iso)) / 60000)
        : null;
    return [
      {
        ...item,
        ...shared,
        agenda_item_id: bookingId,
        booking_id: bookingId,
        leg_id: outboundLeg?.leg_id || (mode === ROUNDTRIP_CONTINUOUS ? `${bookingId}:OUTBOUND` : ""),
        leg_type: mode === ROUNDTRIP_CONTINUOUS ? "continuous" : "",
        linked_agenda_item_id: "",
        ...(mode === ROUNDTRIP_CONTINUOUS && occupancyMin != null
          ? {
              occupancy_min: occupancyMin,
              occupancy_end_iso: new Date(occupancyEnd).toISOString(),
              duration_unknown: false,
            }
          : {}),
      },
    ];
  }

  const outboundDriver = firstText(outboundLeg || {}, ["assigned_driver_id", "assignedDriverId"], 96) ||
    item.assigned_driver_id;
  const outboundVehicle = firstText(outboundLeg || {}, ["assigned_vehicle_id", "assignedVehicleId"], 128) ||
    item.assigned_vehicle_id;
  const returnDriver = firstText(returnLeg || {}, ["assigned_driver_id", "assignedDriverId"], 96) ||
    outboundDriver;
  const returnVehicle = firstText(returnLeg || {}, ["assigned_vehicle_id", "assignedVehicleId"], 128) ||
    outboundVehicle;
  const outboundId = `${bookingId}:OUTBOUND`;
  const returnId = `${bookingId}:RETURN`;
  const items = [];
  if (!outboundLeg || isCapacityBlockingLeg(outboundLeg)) {
    items.push({
      ...item,
      ...shared,
      agenda_item_id: outboundId,
      booking_id: bookingId,
      leg_id: outboundLeg?.leg_id || outboundId,
      leg_type: "outbound",
      linked_agenda_item_id: returnId,
      assigned_driver_id: outboundDriver,
      assigned_vehicle_id: outboundVehicle,
      status: outboundLeg?.status || item.status,
    });
  }
  if (!returnLeg || isCapacityBlockingLeg(returnLeg)) {
    items.push({
      ...item,
      ...shared,
      agenda_item_id: returnId,
      booking_id: bookingId,
      leg_id: returnLeg?.leg_id || returnId,
      leg_type: "return",
      linked_agenda_item_id: outboundId,
      pickup_iso: returnPickupIso,
      from: returnFrom,
      to: returnTo,
      duration_min: returnDuration,
      duration_unknown: returnDuration == null,
      assigned_driver_id: returnDriver,
      assigned_vehicle_id: returnVehicle,
      status: returnLeg?.status || item.status,
    });
  }
  return items;
}

export function publicItemOverlapsPeriod(item, fromMs, toMs) {
  const start = Date.parse(String(item?.pickup_iso || ""));
  if (!Number.isFinite(start)) return false;
  const duration = parseDurationMin(item?.duration_min, null);
  const end = duration != null ? start + duration * 60000 : start + 1;
  return end > fromMs && start < toMs;
}

export function resolveAgendaLegTarget(body, record) {
  const raw = safeStr(body?.leg_id ?? body?.legId ?? body?.leg_type ?? body?.legType, 40).toLowerCase();
  const mode = resolveRoundtripDispatchMode(record);
  if (raw.includes("return") || raw.endsWith(":return")) return "return";
  if (raw.includes("outbound") || raw.endsWith(":outbound") || raw.includes("continuous")) {
    return "outbound";
  }
  if (mode === ROUNDTRIP_SPLIT) return "outbound";
  return "outbound";
}

export function applyAgendaLegPickup(record, { leg, pickupIso, now }) {
  const booking = record.booking && typeof record.booking === "object" ? record.booking : {};
  const legs = Array.isArray(record.operational_legs) ? record.operational_legs.map((row) => ({ ...row })) : [];
  if (leg === "return") {
    record.return_pickup_iso = pickupIso;
    booking.return_pickup_iso = pickupIso;
    for (const row of legs) {
      if (String(row.leg_type || row.legType || "").toLowerCase() === "return") {
        row.pickup_iso = pickupIso;
        row.pickupIso = pickupIso;
        row.updated_at = now;
      }
    }
  } else {
    record.pickup_iso = pickupIso;
    booking.pickup_iso = pickupIso;
    booking.pickupStartIso = pickupIso;
    for (const row of legs) {
      if (String(row.leg_type || row.legType || "").toLowerCase() !== "return") {
        row.pickup_iso = pickupIso;
        row.pickupIso = pickupIso;
        row.updated_at = now;
      }
    }
  }
  record.booking = booking;
  if (legs.length) record.operational_legs = legs;
  const parsed = parseCompanyRoundtripWrite({
    roundtrip_dispatch_mode: resolveRoundtripDispatchMode(record),
    return_enabled: record.return_enabled,
    pickup_iso: record.pickup_iso,
    duration_min: record.duration_min,
    return_pickup_iso: record.return_pickup_iso,
    return_duration_min: record.return_duration_min,
    return_from: record.return_from,
    return_to: record.return_to,
    from: booking.from,
    to: booking.to,
    assigned_driver_id: record.assigned_driver_id,
    assigned_vehicle_id: record.assigned_vehicle_id,
    return_assigned_driver_id: legs.find((row) => String(row.leg_type || "").toLowerCase() === "return")?.assigned_driver_id,
    return_assigned_vehicle_id: legs.find((row) => String(row.leg_type || "").toLowerCase() === "return")?.assigned_vehicle_id,
  });
  if (parsed.ok) applyCompanyRoundtripFields(record, parsed, { bookingId: record.booking_id, now });
  return record;
}

export function applyAgendaLegAssignment(record, { leg, driverId, vehicleId, now }) {
  const booking = record.booking && typeof record.booking === "object" ? record.booking : {};
  const legs = Array.isArray(record.operational_legs) ? record.operational_legs.map((row) => ({ ...row })) : [];
  const mode = resolveRoundtripDispatchMode(record);
  if (mode === ROUNDTRIP_SPLIT && leg === "return") {
    for (const row of legs) {
      if (String(row.leg_type || row.legType || "").toLowerCase() === "return") {
        row.assigned_driver_id = driverId || null;
        row.assignedDriverId = driverId || null;
        row.assigned_vehicle_id = vehicleId || null;
        row.assignedVehicleId = vehicleId || null;
        row.updated_at = now;
      }
    }
  } else {
    record.assigned_driver_id = driverId || null;
    record.assigned_vehicle_id = vehicleId || null;
    booking.assigned_driver_id = driverId || null;
    booking.assigned_vehicle_id = vehicleId || null;
    for (const row of legs) {
      if (String(row.leg_type || row.legType || "").toLowerCase() !== "return") {
        row.assigned_driver_id = driverId || null;
        row.assignedDriverId = driverId || null;
        row.assigned_vehicle_id = vehicleId || null;
        row.assignedVehicleId = vehicleId || null;
        row.updated_at = now;
      }
    }
    if (mode !== ROUNDTRIP_SPLIT) {
      for (const row of legs) {
        row.assigned_driver_id = driverId || null;
        row.assigned_vehicle_id = vehicleId || null;
      }
    }
  }
  record.booking = booking;
  if (legs.length) record.operational_legs = legs;
  return record;
}

export function assignmentWindowsForWrite(parsed) {
  if (!parsed?.ok) return { ok: false, unknown: true, checks: [] };
  const occupancy = occupancyWindowsFromTimes(parsed);
  if (parsed.mode === ROUNDTRIP_SPLIT) {
    const outbound = rideWindow(parsed.pickupIso, parsed.durationMin);
    const ret = rideWindow(parsed.returnPickupIso, parsed.returnDurationMin);
    const checks = [];
    if (parsed.outboundDriverId || parsed.outboundVehicleId) {
      checks.push({
        driverId: parsed.outboundDriverId,
        vehicleId: parsed.outboundVehicleId,
        window: outbound,
      });
    }
    if (parsed.returnDriverId || parsed.returnVehicleId) {
      checks.push({
        driverId: parsed.returnDriverId || parsed.outboundDriverId,
        vehicleId: parsed.returnVehicleId || parsed.outboundVehicleId,
        window: ret,
      });
    } else if (parsed.outboundDriverId || parsed.outboundVehicleId) {
      checks.push({
        driverId: parsed.outboundDriverId,
        vehicleId: parsed.outboundVehicleId,
        window: ret,
      });
    }
    return { ok: true, unknown: occupancy.unknown, checks };
  }
  const driverId = parsed.outboundDriverId;
  const vehicleId = parsed.outboundVehicleId;
  if (!driverId && !vehicleId) return { ok: true, unknown: occupancy.unknown, checks: [] };
  if (occupancy.unknown || !occupancy.windows.length) {
    return { ok: true, unknown: true, checks: [{ driverId, vehicleId, window: { ok: true, durationUnknown: true } }] };
  }
  return {
    ok: true,
    unknown: false,
    checks: occupancy.windows.map((window) => ({ driverId, vehicleId, window })),
  };
}

export function quoteWriteRoundtripValue(body) {
  const parsed = parseCompanyRoundtripWrite({
    ...body,
    pickup_iso: body.start_at || body.pickup_iso,
    from: body.pickup || body.from,
    to: body.dropoff || body.to,
  });
  if (!parsed.ok && parsed.error === "return_pickup_iso_required") {
    return { ok: false, fields: { return_pickup_iso: "required" } };
  }
  if (!parsed.ok) return { ok: false, fields: { return: parsed.error } };
  return {
    ok: true,
    value: {
      return_enabled: parsed.returnEnabled,
      roundtrip_dispatch_mode: parsed.mode,
      return_pickup_iso: parsed.returnPickupIso,
      return_from: parsed.returnFrom,
      return_to: parsed.returnTo,
      return_duration_min: parsed.returnDurationMin,
      occupancy_wait_min: parsed.occupancyWaitMin,
      occupancy_unknown: parsed.occupancyUnknown,
      return_pickup_lat: parsed.returnPickupLat,
      return_pickup_lon: parsed.returnPickupLon,
      return_pickup_place_id: parsed.returnPickupPlaceId,
      return_dropoff_lat: parsed.returnDropoffLat,
      return_dropoff_lon: parsed.returnDropoffLon,
      return_dropoff_place_id: parsed.returnDropoffPlaceId,
      return_assigned_driver_id: parsed.returnDriverId,
      return_assigned_vehicle_id: parsed.returnVehicleId,
    },
  };
}

export function pairedAssignmentIds(driverId, vehicleId) {
  const driver = sanitizeTenantString(driverId, 96);
  const vehicle = sanitizeTenantString(vehicleId, 128);
  if (driver && vehicle) return { driverId: driver, vehicleId: vehicle };
  return { driverId: "", vehicleId: "" };
}

export function clearParsedAssignment(parsed) {
  if (!parsed || typeof parsed !== "object") return parsed;
  parsed.outboundDriverId = "";
  parsed.outboundVehicleId = "";
  parsed.returnDriverId = "";
  parsed.returnVehicleId = "";
  return parsed;
}

export function pairParsedAssignment(parsed) {
  if (!parsed || typeof parsed !== "object") return parsed;
  const outbound = pairedAssignmentIds(parsed.outboundDriverId, parsed.outboundVehicleId);
  parsed.outboundDriverId = outbound.driverId;
  parsed.outboundVehicleId = outbound.vehicleId;
  const inbound = pairedAssignmentIds(parsed.returnDriverId, parsed.returnVehicleId);
  parsed.returnDriverId = inbound.driverId;
  parsed.returnVehicleId = inbound.vehicleId;
  return parsed;
}

function applyPairedIds(target, driverId, vehicleId) {
  const paired = pairedAssignmentIds(driverId, vehicleId);
  if (!target || typeof target !== "object") return paired;
  target.assigned_driver_id = paired.driverId || null;
  target.assignedDriverId = paired.driverId || null;
  target.assigned_vehicle_id = paired.vehicleId || null;
  target.assignedVehicleId = paired.vehicleId || null;
  return paired;
}

export function recordHasAssignmentIds(record) {
  if (!record || typeof record !== "object") return false;
  if (pairedAssignmentIds(record.assigned_driver_id, record.assigned_vehicle_id).driverId) {
    return true;
  }
  const booking = record.booking && typeof record.booking === "object" ? record.booking : {};
  if (pairedAssignmentIds(booking.assigned_driver_id, booking.assigned_vehicle_id).driverId) {
    return true;
  }
  for (const leg of Array.isArray(record.operational_legs) ? record.operational_legs : []) {
    if (pairedAssignmentIds(leg?.assigned_driver_id || leg?.assignedDriverId, leg?.assigned_vehicle_id || leg?.assignedVehicleId).driverId) {
      return true;
    }
  }
  return false;
}

export function sanitizeRecordAssignmentTruth(record, { stripAll = false } = {}) {
  if (!record || typeof record !== "object") return record;
  const parent = stripAll
    ? { driverId: "", vehicleId: "" }
    : pairedAssignmentIds(record.assigned_driver_id, record.assigned_vehicle_id);
  record.assigned_driver_id = parent.driverId || null;
  record.assigned_vehicle_id = parent.vehicleId || null;
  record.assignment_state = parent.driverId ? "assigned" : "unassigned";
  if (record.booking && typeof record.booking === "object") {
    const booked = stripAll
      ? { driverId: "", vehicleId: "" }
      : pairedAssignmentIds(record.booking.assigned_driver_id, record.booking.assigned_vehicle_id);
    record.booking.assigned_driver_id = booked.driverId || parent.driverId || null;
    record.booking.assigned_vehicle_id = booked.vehicleId || parent.vehicleId || null;
  }
  if (Array.isArray(record.operational_legs)) {
    record.operational_legs = record.operational_legs.map((leg) => {
      const next = { ...leg };
      if (stripAll) applyPairedIds(next, "", "");
      else applyPairedIds(next, next.assigned_driver_id || next.assignedDriverId, next.assigned_vehicle_id || next.assignedVehicleId);
      return next;
    });
  }
  return record;
}

export function assignmentWriteFlags(record, warning) {
  const hasIds = recordHasAssignmentIds(record);
  if (warning) return { assignment_warning: warning, saved_unassigned: true };
  if (hasIds) return {};
  return {};
}

export function sanitizePublicAssignmentItem(item, { stripAll = false } = {}) {
  if (!item || typeof item !== "object") return item;
  const paired = stripAll
    ? { driverId: "", vehicleId: "" }
    : pairedAssignmentIds(item.assigned_driver_id, item.assigned_vehicle_id);
  return {
    ...item,
    assigned_driver_id: paired.driverId || "",
    assigned_vehicle_id: paired.vehicleId || "",
    assignment_state: paired.driverId ? "assigned" : "unassigned",
  };
}
