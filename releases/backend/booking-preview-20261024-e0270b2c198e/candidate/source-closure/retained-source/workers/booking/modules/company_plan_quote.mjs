// COMPANY-AGENDA-P0 — authenticated plan-form quote.
// Reuses _handleQuoteRequestInternal + Mapbox + calcPrice. No second calculator.

import { safeStr, sanitizeTenantString } from "./parsing_utils.js";
import { resolveCompanyAgendaPickupIso } from "./company_plan_when.mjs";

export function matchCompanyAgendaQuotePath(pathname) {
  return String(pathname || "") === "/company/agenda/quote";
}

function finiteOrNull(value) {
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

function firstFinite(body, keys) {
  for (const key of keys) {
    const n = finiteOrNull(body?.[key]);
    if (n != null) return n;
  }
  return null;
}

export function agendaPickupToQuoteDateTime(pickupIso) {
  const ms = Date.parse(String(pickupIso || ""));
  if (!Number.isFinite(ms)) return null;
  const parts = new Intl.DateTimeFormat("en-GB", {
    timeZone: "Europe/Brussels",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).formatToParts(new Date(ms));
  const get = (type) => parts.find((part) => part.type === type)?.value || "";
  const date = `${get("year")}-${get("month")}-${get("day")}`;
  const time = `${get("hour")}:${get("minute")}`;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || !/^\d{2}:\d{2}$/.test(time)) return null;
  return { date, time };
}

export function buildCompanyAgendaQuoteRequestBody(body, scope, now = new Date()) {
  const from = safeStr(body?.from || body?.pickup, 240);
  const to = safeStr(body?.to || body?.dropoff, 240);
  if (!from || !to) {
    return { ok: false, error: "route_required" };
  }
  const pickupIso = resolveCompanyAgendaPickupIso(body, now);
  const dt = agendaPickupToQuoteDateTime(pickupIso);
  if (!dt) {
    return { ok: false, error: "pickup_iso_required" };
  }
  const tenantId = sanitizeTenantString(scope?.tenant_id ?? body?.tenant_id ?? body?.tenantId, 80);
  const companyId = sanitizeTenantString(scope?.company_id ?? body?.company_id ?? body?.companyId, 80);
  if (!tenantId || !companyId) {
    return { ok: false, error: "missing_company_scope" };
  }
  const fromLat = firstFinite(body, ["from_lat", "fromLat", "pickup_lat", "pickupLat"]);
  const fromLng = firstFinite(body, ["from_lng", "fromLng", "pickup_lon", "pickupLon", "pickup_lng", "pickupLng"]);
  const toLat = firstFinite(body, ["to_lat", "toLat", "dropoff_lat", "dropoffLat"]);
  const toLng = firstFinite(body, ["to_lng", "toLng", "dropoff_lon", "dropoffLon", "dropoff_lng", "dropoffLng"]);
  const rideOptions = body?.ride_options && typeof body.ride_options === "object"
    ? body.ride_options
    : {};
  const service = safeStr(body?.service || rideOptions.service, 32);
  const tier = safeStr(body?.tier || rideOptions.tier, 32);
  const bags = Math.max(0, Number(body?.bags ?? rideOptions.bags ?? 0) || 0);
  const waitMin = Math.max(0, Number(body?.wait_min ?? rideOptions.wait_min ?? 0) || 0);
  const pax = Math.max(1, Number(body?.passengers ?? body?.pax ?? 1) || 1);
  const returnEnabled = body?.return_enabled === true || body?.returnEnabled === true;
  const returnDt = returnEnabled
    ? agendaPickupToQuoteDateTime(body?.return_pickup_iso || body?.returnPickupIso) || dt
    : null;
  const stops = Array.isArray(body?.stops)
    ? body.stops.map((item) => safeStr(item, 240)).filter(Boolean).slice(0, 10)
    : [];
  const returnStops = Array.isArray(body?.return_stops || body?.returnStops)
    ? (body.return_stops || body.returnStops).map((item) => safeStr(item, 240)).filter(Boolean).slice(0, 10)
    : [];
  const out = {
    tenant_id: tenantId,
    company_id: companyId,
    tenantId,
    companyId,
    from,
    to,
    date: dt.date,
    time: dt.time,
    pickup_iso: pickupIso,
    pax,
    bags,
    wait_min: waitMin,
    currency: safeStr(body?.currency, 8) || "EUR",
  };
  if (service) out.service = service;
  if (tier) out.tier = tier;
  if (fromLat != null && fromLng != null) {
    out.from_lat = fromLat;
    out.from_lng = fromLng;
    out.pickup_lat = fromLat;
    out.pickup_lng = fromLng;
  }
  if (toLat != null && toLng != null) {
    out.to_lat = toLat;
    out.to_lng = toLng;
    out.dropoff_lat = toLat;
    out.dropoff_lng = toLng;
  }
  const airportIata = safeStr(body?.airport_iata || rideOptions.airport_iata, 8);
  const airportDirection = safeStr(body?.airport_direction || rideOptions.airport_direction, 32);
  if (airportIata) out.airport_iata = airportIata;
  if (airportDirection) out.airport_direction = airportDirection;
  if (service === "hourly" || rideOptions.journey_type === "hourly_package") {
    out.journey_type = "hourly_package";
    const requested = Number(body?.requested_duration_minutes ?? rideOptions.requested_duration_minutes);
    if (Number.isFinite(requested) && requested > 0) {
      out.requested_duration_minutes = Math.round(requested);
    }
  }
  if (stops.length) out.stops = stops;
  if (returnEnabled && returnDt) {
    out.return_enabled = true;
    out.return_date = returnDt.date;
    out.return_time = returnDt.time;
    out.return_from = safeStr(body?.return_from, 240) || to;
    out.return_to = safeStr(body?.return_to, 240) || from;
    if (returnStops.length) out.return_stops = returnStops;
    const returnFromLat = firstFinite(body, ["return_from_lat", "returnFromLat", "return_pickup_lat"]);
    const returnFromLng = firstFinite(body, ["return_from_lng", "returnFromLng", "return_pickup_lon", "return_pickup_lng"]);
    const returnToLat = firstFinite(body, ["return_to_lat", "returnToLat", "return_dropoff_lat"]);
    const returnToLng = firstFinite(body, ["return_to_lng", "returnToLng", "return_dropoff_lon", "return_dropoff_lng"]);
    if (returnFromLat != null && returnFromLng != null) {
      out.return_from_lat = returnFromLat;
      out.return_from_lng = returnFromLng;
    }
    if (returnToLat != null && returnToLng != null) {
      out.return_to_lat = returnToLat;
      out.return_to_lng = returnToLng;
    }
  }
  return { ok: true, body: out };
}

function moneyOrNull(value) {
  if (value == null || value === "") return null;
  const n = Number(String(value).replace(",", "."));
  return Number.isFinite(n) ? n : null;
}

export function publicCompanyAgendaQuote(quoteOut) {
  const distance = moneyOrNull(quoteOut?.distance_km);
  const duration = moneyOrNull(quoteOut?.duration_min ?? quoteOut?.duration_route_min);
  const usableRoute =
    Number.isFinite(distance) &&
    distance > 0 &&
    Number.isFinite(duration) &&
    duration > 0;
  const source = safeStr(quoteOut?.pricing_source, 40);
  const requestQuote = quoteOut?.request_quote_required === true || source === "request_quote";
  const calculatorOff = source === "calculator_off";
  const returnBlock = quoteOut?.return && typeof quoteOut.return === "object" ? quoteOut.return : {};
  const returnDistance = moneyOrNull(quoteOut?.return_distance_km ?? returnBlock.distance_km);
  const returnDuration = moneyOrNull(quoteOut?.return_duration_min ?? returnBlock.duration_min);
  const usableReturn =
    Number.isFinite(returnDistance) &&
    returnDistance > 0 &&
    Number.isFinite(returnDuration) &&
    returnDuration > 0;
  const outboundPrice = moneyOrNull(
    quoteOut?.price_incl_vat_main ?? quoteOut?.price_incl_vat,
  );
  const returnPrice = moneyOrNull(
    quoteOut?.price_incl_vat_return ?? returnBlock.price_incl_vat,
  );
  const price = moneyOrNull(
    quoteOut?.total_price_incl_vat ??
      (outboundPrice != null || returnPrice != null
        ? (outboundPrice || 0) + (returnPrice || 0)
        : quoteOut?.price_incl_vat),
  );
  const priceAvailable =
    usableRoute &&
    !requestQuote &&
    !calculatorOff &&
    price != null &&
    Number.isFinite(price) &&
    price >= 0;
  return {
    ok: true,
    distance_km: usableRoute ? Number(distance.toFixed(1)) : null,
    duration_min: usableRoute ? Math.round(duration) : null,
    price_incl_vat: priceAvailable ? price : null,
    price_incl_vat_main: priceAvailable ? outboundPrice : null,
    price_ex_vat: priceAvailable ? moneyOrNull(quoteOut?.total_price_ex_vat ?? quoteOut?.price_ex_vat) : null,
    price_vat: priceAvailable ? moneyOrNull(quoteOut?.total_price_vat ?? quoteOut?.price_vat) : null,
    currency: safeStr(quoteOut?.currency, 8) || "EUR",
    pricing_source: source || (priceAvailable ? "route_calc" : calculatorOff ? "calculator_off" : "request_quote"),
    price_available: priceAvailable,
    request_quote_required: requestQuote,
    calculator_off: calculatorOff,
    fixed_price_snapshot: quoteOut?.fixed_price_snapshot || null,
    pickup_lat: firstFinite(quoteOut?.inputs || {}, ["from_lat"]) ?? firstFinite(quoteOut || {}, ["from_lat"]),
    pickup_lon: firstFinite(quoteOut?.inputs || {}, ["from_lng"]) ?? firstFinite(quoteOut || {}, ["from_lng"]),
    dropoff_lat: firstFinite(quoteOut || {}, ["to_lat"]),
    dropoff_lon: firstFinite(quoteOut || {}, ["to_lng"]),
    return_distance_km: usableReturn ? Number(returnDistance.toFixed(1)) : null,
    return_duration_min: usableReturn ? Math.round(returnDuration) : null,
    return_price_incl_vat: priceAvailable ? returnPrice : null,
    total_price_incl_vat: priceAvailable ? price : null,
    return: usableReturn
      ? {
          distance_km: Number(returnDistance.toFixed(1)),
          duration_min: Math.round(returnDuration),
          price_incl_vat: priceAvailable ? returnPrice : null,
          breakdown: returnBlock.breakdown || null,
        }
      : null,
    breakdown: quoteOut?.breakdown && typeof quoteOut.breakdown === "object"
      ? quoteOut.breakdown
      : null,
    return_breakdown:
      (returnBlock.breakdown && typeof returnBlock.breakdown === "object"
        ? returnBlock.breakdown
        : null),
  };
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

export async function serveCompanyAgendaQuoteHttp({
  env,
  body,
  scope,
  quoteHandler,
}) {
  if (typeof quoteHandler !== "function") {
    return json({ ok: false, error: "quote_handler_missing" }, 500);
  }
  const built = buildCompanyAgendaQuoteRequestBody(body || {}, scope || {});
  if (!built.ok) {
    return json({ ok: false, error: built.error }, 400);
  }
  const quoted = await quoteHandler({
    body: built.body,
    env,
    request: null,
    url: null,
  });
  const out = quoted?.out && typeof quoted.out === "object" ? quoted.out : {};
  const status = Number(quoted?.status) || 500;
  if (out.ok !== true) {
    return json(
      {
        ok: false,
        error: out.error || "route_failed",
        error_code: out.error_code || out.error || "route_failed",
        message:
          out.message ||
          "De route kon niet worden berekend. De ingevulde ritgegevens blijven bewaard.",
        distance_km: null,
        duration_min: null,
        price_incl_vat: null,
      },
      status >= 400 ? status : 422,
    );
  }
  return json(publicCompanyAgendaQuote(out), 200);
}
