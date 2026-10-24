import { usesCompanyMissionTaxi } from './company_mission_scope.mjs';
// Company-configurable fixed prices on the existing airport_fixed_fares store.
// Airport rules stay compatible. City pairs and overflow are additive.

import { resolveFixedVehicleCategory } from "./company_fixed_vehicle_category.mjs";

import { json } from "./http_response.js";
import { sanitizeTenantString, safeStr } from "./parsing_utils.js";

export const COMPANY_FIXED_PRICE_FALLBACKS = ["calculator", "request_quote"];
export const COMPANY_FIXED_PRICE_PLACE_TYPES = [
  "city",
  "postcode",
  "zone",
  "airport",
  "radius",
];
export const COMPANY_FIXED_PRICE_OVERFLOW_MODES = [
  "no_match",
  "extra_km",
  "zone_surcharge",
];

const ZONE_RANK = {
  none: 0,
  country: 1,
  radius: 2,
  zone: 3,
  city: 3,
  postcode: 4,
  airport: 4,
};

function text(value, max = 160) {
  return sanitizeTenantString(value, max).trim();
}

function upperToken(value, max = 8) {
  return text(value, max).toUpperCase();
}

function intOr(value, fallback, min, max) {
  const n = Number(value);
  if (!Number.isFinite(n)) return fallback;
  const rounded = Math.round(n);
  if (rounded < min || rounded > max) return fallback;
  return rounded;
}

function finiteOrNull(value) {
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

function to2(value) {
  const n = Number(value);
  if (!Number.isFinite(n)) return 0;
  return Math.round(n * 100) / 100;
}

function normCity(value) {
  return text(value, 80)
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

function normPostcode(value) {
  return text(value, 16).toUpperCase().replace(/\s+/g, "");
}

const LOCALITY_COUNTRY_WORDS = new Set([
  "belgie",
  "belgium",
  "belgique",
  "nederland",
  "netherlands",
  "frankrijk",
  "france",
  "duitsland",
  "germany",
  "deutschland",
  "luxemburg",
  "luxembourg",
  "spanje",
  "spain",
  "espana",
  "verenigd koninkrijk",
  "united kingdom",
]);

// A place label is one comma-separated list: "9688, Maarkedal, Oost-Vlaanderen,
// België". Keep the parts as identities instead of matching on the whole
// display string, so a municipality stays recognisable when the label differs.
function localityTokens(raw) {
  const out = [];
  for (const part of text(raw, 240).split(",")) {
    const normalized = normCity(part.replace(/\b\d{4,6}\b/g, " "));
    if (!normalized || LOCALITY_COUNTRY_WORDS.has(normalized)) continue;
    out.push(normalized);
  }
  return out;
}

function collectLocalityTokens(values) {
  const out = [];
  for (const value of values) {
    for (const token of localityTokens(value)) {
      if (!out.includes(token)) out.push(token);
    }
  }
  return out;
}

// Whole-word containment. "leuven station leuven" holds "leuven";
// "gentbrugge" does not hold "gent". The returned index is the first
// comma-separated address part that holds the name. Earlier parts are the
// selected place; later parts are parents such as the municipality.
function tokenHoldsAt(tokens, needle) {
  const want = normCity(needle).split(" ").filter(Boolean);
  if (want.length === 0) return -1;
  for (let index = 0; index < tokens.length; index += 1) {
    const words = String(tokens[index] || "").split(" ").filter(Boolean);
    for (let i = 0; i + want.length <= words.length; i += 1) {
      let hit = true;
      for (let j = 0; j < want.length; j += 1) {
        if (words[i + j] !== want[j]) {
          hit = false;
          break;
        }
      }
      if (hit) return index;
    }
  }
  return -1;
}

function localityHolds(tokens, needle) {
  return tokenHoldsAt(tokens, needle) >= 0;
}

// Beveren in East Flanders is the municipality stored as Beveren-Waas.
// The live suggestion says "Beveren" and names the province. Beveren in
// Waregem and Beveren-aan-de-IJzer stay separate places. A postcode is not
// evidence, and "beveren" is not matched inside a longer word.
const EAST_FLANDERS_BEVEREN = {
  canonical: "beveren waas",
  alias: "beveren",
  center: { lat: 51.212611, lng: 4.257781 },
  nearKm: 18,
  farKm: 40,
  provinces: ["oost vlaanderen", "east flanders"],
  reject: ["west vlaanderen", "west flanders", "waregem", "alveringem"],
};

function qualifiedLocalityRank(tokens, needle, lat, lng) {
  const direct = tokenHoldsAt(tokens, needle);
  if (normCity(needle) !== EAST_FLANDERS_BEVEREN.canonical) return direct;
  if (direct >= 0) return direct;
  const alias = tokens.findIndex((token) => token === EAST_FLANDERS_BEVEREN.alias);
  if (alias < 0) return -1;
  if (EAST_FLANDERS_BEVEREN.reject.some((name) => tokenHoldsAt(tokens, name) >= 0)) {
    return -1;
  }
  const province = EAST_FLANDERS_BEVEREN.provinces.some((name) => tokenHoldsAt(tokens, name) >= 0);
  const distance = haversineKm(lat, lng, EAST_FLANDERS_BEVEREN.center.lat, EAST_FLANDERS_BEVEREN.center.lng);
  if (Number.isFinite(distance) && distance > EAST_FLANDERS_BEVEREN.farKm) return -1;
  const near = Number.isFinite(distance) && distance <= EAST_FLANDERS_BEVEREN.nearKm;
  if (province || near) return alias;
  return -1;
}

// Only a postcode-led part counts ("9688", "9000 Gent"). A house number such
// as "Korenmarkt 1" or "Chaussée 1234" is not a postcode.
function postcodeFromPart(part) {
  const match = text(part, 240).trim().match(/^(\d{4,6})(?:\s*([A-Za-z]{2}))?(?=\s|$)/);
  return match ? `${match[1]}${match[2] ?? ''}`.toUpperCase() : "";
}

function collectPostcodes(explicitValues, labelValues) {
  const out = [];
  const push = (value) => {
    const code = normPostcode(value);
    if (code && !out.includes(code)) out.push(code);
  };
  // The selected endpoint is authoritative when it contains a postcode. An
  // old home/profile hint cannot make a second, incompatible fare zone match.
  for (const part of text(labelValues[0], 240).split(',')) push(postcodeFromPart(part));
  if (out.length > 0) return out;
  for (const value of explicitValues) push(value);
  for (const value of labelValues) {
    for (const part of text(value, 240).split(",")) push(postcodeFromPart(part));
  }
  return out;
}

export function companyFixedPricesKey(scope) {
  const tenant = text(scope?.tenant_id ?? scope?.tenantId, 80);
  const company = text(scope?.company_id ?? scope?.companyId, 80);
  if (!tenant || !company) return "";
  return `tenant:${tenant}:company:${company}:airport_fixed_fares:v1`;
}

export const AIRPORT_AUTO_CALC_OUTSIDE_FIXED_FARES_FIELD = "airport_auto_calc_outside_fixed_fares";
export const AIRPORT_FIXED_FARE_MIN_LEAD_HOURS_FIELD = "airport_fixed_fare_min_lead_hours";
const AIRPORT_FIXED_FARE_MIN_LEAD_HOURS_MAX = 24 * 30;
export const AIRPORT_NO_FIXED_FARE_REASON = "no_fixed_airport_fare";
export const AIRPORT_NO_FIXED_FARE_PRICE_LABEL = "Prijs op aanvraag";
export const AIRPORT_NO_FIXED_FARE_MESSAGE =
  "Voor deze luchthavenrit is geen vast online tarief beschikbaar. Neem contact op met het bedrijf voor een prijsvoorstel.";
export const AIRPORT_NO_FIXED_FARE_ACTION = "contact_company";

// Missing means the company has not chosen. That keeps today's calculator.
// Only an explicit false turns automatic airport pricing off.
export function airportAutoCalcOutsideFixedFaresEnabled(profile) {
  if (!profile || typeof profile !== "object") return true;
  const raw = profile.airport_auto_calc_outside_fixed_fares ?? profile.airportAutoCalcOutsideFixedFares;
  if (raw === undefined || raw === null || raw === "") return true;
  if (raw === false || raw === 0) return false;
  const text = String(raw).trim().toLowerCase();
  if (text === "false" || text === "0" || text === "off" || text === "nee") return false;
  return true;
}

export function profileDeclaresAirportAutoCalcOutsideFixedFares(profile) {
  if (!profile || typeof profile !== "object") return false;
  return Object.prototype.hasOwnProperty.call(profile, "airport_auto_calc_outside_fixed_fares")
    || Object.prototype.hasOwnProperty.call(profile, "airportAutoCalcOutsideFixedFares");
}

export function profileDeclaresAirportFixedFareMinLeadHours(profile) {
  if (!profile || typeof profile !== "object") return false;
  return Object.prototype.hasOwnProperty.call(profile, AIRPORT_FIXED_FARE_MIN_LEAD_HOURS_FIELD)
    || Object.prototype.hasOwnProperty.call(profile, "airportFixedFareMinLeadHours");
}

// Hours until pickup. Null means the company explicitly set no minimum.
// Undefined means the profile does not contain this setting.
// A pickup earlier than the term is too soon. A pickup exactly on the term
// still gets the fixed fare. There is no second clock beside this comparison.
export function airportFixedFareMinLeadHours(profile) {
  if (!profileDeclaresAirportFixedFareMinLeadHours(profile)) return undefined;
  const raw = profile.airport_fixed_fare_min_lead_hours ?? profile.airportFixedFareMinLeadHours;
  if (raw == null || raw === "" || raw === false) return null;
  const hours = Number(raw);
  if (!Number.isFinite(hours) || hours <= 0) return null;
  if (hours > AIRPORT_FIXED_FARE_MIN_LEAD_HOURS_MAX) return AIRPORT_FIXED_FARE_MIN_LEAD_HOURS_MAX;
  return hours;
}

export function refuseAirportBookingWithoutAllowedFare(result) {
  if (!result || result.matched === true) return null;
  if (result.request_quote_required !== true && result.block_calculator !== true) return null;
  return {
    ok: false,
    error: "request_quote_required",
    message: result.message || AIRPORT_NO_FIXED_FARE_MESSAGE,
    reason: result.reason || "request_quote_required",
    price_label: result.price_label || AIRPORT_NO_FIXED_FARE_PRICE_LABEL,
    customer_action: result.customer_action || null,
    ...(Array.isArray(result.conditions) && result.conditions.length > 0
      ? { conditions: result.conditions }
      : {}),
  };
}

function payloadIsAirportRide(payload) {
  const service = text(payload?.service ?? payload?.ride_options?.service, 24).toLowerCase();
  if (service === "airport") return true;
  return !!(
    text(payload?.airport_iata ?? payload?.airportIata, 8) &&
    text(payload?.airport_direction ?? payload?.airportDirection, 24)
  );
}

function noFixedAirportFareResult(doc, needsDetail, candidates, extra = {}) {
  return {
    matched: false,
    block_calculator: true,
    fallback: doc.fallback,
    pricing_source: "request_quote",
    request_quote_required: true,
    reason: AIRPORT_NO_FIXED_FARE_REASON,
    message: AIRPORT_NO_FIXED_FARE_MESSAGE,
    price_label: AIRPORT_NO_FIXED_FARE_PRICE_LABEL,
    customer_action: AIRPORT_NO_FIXED_FARE_ACTION,
    ...(Array.isArray(extra.conditions) && extra.conditions.length > 0
      ? { conditions: extra.conditions }
      : {}),
    needs_more_detail: needsDetail,
    candidates,
    fixed_fare_rule_id: null,
    pricing: null,
    snapshot: null,
  };
}

function fixedFareLeadHoursDeclared(options) {
  return Object.prototype.hasOwnProperty.call(options || {}, "airportFixedFareMinLeadHours");
}

function pickupEarlierThanLeadHours(payload, options, hours) {
  const pickupMs = pickupInstantMs(payload);
  const nowMs = Number.isFinite(Number(options?.nowMs)) ? Number(options.nowMs) : Date.now();
  if (!Number.isFinite(pickupMs) || !Number.isFinite(nowMs)) return false;
  return pickupMs - nowMs < hours * 3600 * 1000;
}

function confirmedFixedFareLeadTooSoon(payload, options) {
  if (!fixedFareLeadHoursDeclared(options) || !payloadIsAirportRide(payload)) return false;
  const hours = Number(options.airportFixedFareMinLeadHours);
  if (!Number.isFinite(hours) || hours <= 0) return false;
  return pickupEarlierThanLeadHours(payload, options, hours);
}

// One company-selected airport booking term, independent of the pricing mode.
// Keep the stored field compatible with existing company settings.
export function airportBookingAdvanceRefusal(payload, hours, nowMs = Date.now()) {
  if (!payloadIsAirportRide(payload) || !Number.isFinite(Number(hours)) || Number(hours) <= 0) return null;
  if (!pickupEarlierThanLeadHours(payload, { nowMs }, Number(hours))) return null;
  return {
    ok: false, error: 'airport_minimum_advance_booking',
    reason: 'airport_minimum_advance_booking',
    message: `Dit bedrijf vraagt om luchthavenritten minstens ${Number(hours)} uur vooraf te boeken.`,
    minimum_advance_hours: Number(hours),
    earliest_pickup_iso: new Date(nowMs + Number(hours) * 3600000).toISOString(),
  };
}

export function haversineKm(lat1, lng1, lat2, lng2) {
  const a1 = Number(lat1);
  const o1 = Number(lng1);
  const a2 = Number(lat2);
  const o2 = Number(lng2);
  if (![a1, o1, a2, o2].every(Number.isFinite)) return null;
  const r = 6371;
  const dLat = ((a2 - a1) * Math.PI) / 180;
  const dLng = ((o2 - o1) * Math.PI) / 180;
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((a1 * Math.PI) / 180) *
      Math.cos((a2 * Math.PI) / 180) *
      Math.sin(dLng / 2) ** 2;
  return r * (2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h)));
}

export function normalizeCompanyFixedPricePlace(raw, { required = false } = {}) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    return required ? null : emptyPlace();
  }
  const typeRaw = text(raw.type ?? raw.kind ?? raw.place_type, 24).toLowerCase();
  const type = COMPANY_FIXED_PRICE_PLACE_TYPES.includes(typeRaw)
    ? typeRaw
    : "";
  if (!type) return required ? null : emptyPlace();
  const airportIata = upperToken(raw.airport_iata ?? raw.airportIata ?? raw.iata, 8);
  const value = type === "airport"
    ? airportIata
    : type === "postcode"
      ? normPostcode(raw.value ?? raw.postcode ?? raw.postal_code)
      : type === "city"
        ? normCity(raw.value ?? raw.city ?? raw.label)
        : text(raw.value ?? raw.zone ?? raw.label, 80);
  const label = text(raw.label ?? raw.name ?? raw.value ?? airportIata, 120);
  const lat = finiteOrNull(raw.lat ?? raw.center_lat ?? raw.zone_center_lat);
  const lng = finiteOrNull(raw.lng ?? raw.lon ?? raw.center_lng ?? raw.zone_center_lng);
  const radiusKm = finiteOrNull(raw.radius_km ?? raw.radiusKm);
  if (type === "airport" && (airportIata.length < 3 || airportIata.length > 8)) {
    return null;
  }
  if ((type === "city" || type === "postcode" || type === "zone") && !value) {
    return null;
  }
  if (type === "radius") {
    if (!label) return null;
    if (!Number.isFinite(lat) || lat < -90 || lat > 90) return null;
    if (!Number.isFinite(lng) || lng < -180 || lng > 180) return null;
    if (!Number.isFinite(radiusKm) || radiusKm <= 0 || radiusKm > 500) return null;
  }
  return {
    type,
    value: type === "radius" ? label : value,
    label: label || value || airportIata,
    airport_iata: type === "airport" ? airportIata : "",
    lat: type === "radius" ? lat : Number.isFinite(lat) ? lat : null,
    lng: type === "radius" ? lng : Number.isFinite(lng) ? lng : null,
    radius_km: type === "radius" ? radiusKm : null,
    ...(type === "city" && normCity(raw.parent_city) ? {parent_city:normCity(raw.parent_city)} : {}),
  };
}

function emptyPlace() {
  return {
    type: "",
    value: "",
    label: "",
    airport_iata: "",
    lat: null,
    lng: null,
    radius_km: null,
  };
}

function inferKind(raw, origin, destination, airportIata) {
  const kindRaw = text(raw?.kind ?? raw?.rule_kind, 24).toLowerCase();
  if (kindRaw === "city_pair" || kindRaw === "airport") return kindRaw;
  if (origin?.type === "airport" || destination?.type === "airport" || airportIata) {
    return "airport";
  }
  return "city_pair";
}

function returnPackageCover(raw, direction) {
  const covers = text(raw?.price_covers ?? raw?.priceCovers, 32).toLowerCase();
  if (covers === "full_assignment") return "full_assignment";
  if (covers === "return_package" || direction === "return_package") return "return_package";
  return "ride";
}

function payloadRequestsReturn(payload = {}) {
  const raw = payload?.return_enabled ?? payload?.returnEnabled ?? payload?.return;
  if (raw === true) return true;
  const flag = String(raw ?? "").trim().toLowerCase();
  if (flag === "1" || flag === "true" || flag === "yes" || flag === "ja" || flag === "on") {
    return true;
  }
  return !!(
    text(payload?.return_date ?? payload?.returnDate, 32) ||
    text(payload?.return_time ?? payload?.returnTime, 32)
  );
}

function payloadRequestsInvoice(payload = {}) {
  const biz = payload?.business && typeof payload.business === "object" ? payload.business : {};
  const vat = text(
    biz.vat_number ?? payload?.vat_number ?? payload?.vat ?? payload?.btw ?? payload?.btw_number,
    32,
  );
  if (vat) return true;
  const raw = biz.invoice_requested ?? payload?.invoice_requested ?? payload?.invoice ?? payload?.factuur;
  if (raw === true) return true;
  const flag = String(raw ?? "").trim().toLowerCase();
  return flag === "1" || flag === "true" || flag === "yes" || flag === "ja" || flag === "on";
}

function brusselsOffsetMsAt(utcMs) {
  const fmt = new Intl.DateTimeFormat("en-US", {
    timeZone: "Europe/Brussels",
    hourCycle: "h23",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  });
  const parts = {};
  for (const part of fmt.formatToParts(new Date(utcMs))) {
    if (part.type !== "literal") parts[part.type] = part.value;
  }
  const asUtc = Date.UTC(
    Number(parts.year),
    Number(parts.month) - 1,
    Number(parts.day),
    Number(parts.hour),
    Number(parts.minute),
    Number(parts.second),
  );
  return asUtc - utcMs;
}

export function brusselsWallClockToUtcMs(dateStr, timeStr) {
  const date = String(dateStr || "").trim();
  const time = String(timeStr || "").trim() || "00:00";
  let year;
  let month;
  let day;
  const iso = date.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  const eu = date.match(/^(\d{2})\/(\d{2})\/(\d{4})$/);
  if (iso) {
    year = Number(iso[1]);
    month = Number(iso[2]);
    day = Number(iso[3]);
  } else if (eu) {
    day = Number(eu[1]);
    month = Number(eu[2]);
    year = Number(eu[3]);
  } else {
    return null;
  }
  const clock = time.match(/^(\d{1,2}):(\d{2})/);
  const hour = clock ? Number(clock[1]) : 0;
  const minute = clock ? Number(clock[2]) : 0;
  if (![year, month, day, hour, minute].every((n) => Number.isFinite(n))) return null;
  const desired = Date.UTC(year, month - 1, day, hour, minute, 0);
  let utc = desired - brusselsOffsetMsAt(desired);
  const corrected = desired - brusselsOffsetMsAt(utc);
  if (corrected !== utc) utc = corrected;
  return utc;
}

function pickupInstantMs(payload = {}) {
  const iso = text(payload.pickup_iso ?? payload.pickupIso ?? payload.pickup_start_iso, 40);
  const parsedIso = iso ? Date.parse(iso) : NaN;
  if (Number.isFinite(parsedIso)) return parsedIso;
  return brusselsWallClockToUtcMs(
    payload.date ?? payload.pickup_date ?? payload.pickupDate,
    payload.time ?? payload.pickup_time ?? payload.pickupTime ?? "00:00",
  );
}

function normalizePendingPriceConditions(source) {
  const raw = source?.pending_price_conditions ?? source?.pendingPriceConditions;
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  const hours = Number(raw.lead_time_hours ?? raw.leadTimeHours);
  const lead = Number.isFinite(hours) && hours > 0 && hours <= 24 * 30 ? hours : null;
  const invoice = raw.invoice_terms_missing === true || raw.invoiceTermsMissing === true;
  if (lead == null && !invoice) return null;
  return {
    ...(lead != null ? { lead_time_hours: lead } : {}),
    ...(invoice ? { invoice_terms_missing: true } : {}),
  };
}

const PRICE_ON_REQUEST = "Prijs op aanvraag";

function unconfirmedPriceHold(doc, payload, options = {}) {
  const pending = doc?.pending_price_conditions;
  if (!pending) return null;
  const conditions = [];
  const hours = Number(pending.lead_time_hours);
  if (!fixedFareLeadHoursDeclared(options) && Number.isFinite(hours) && hours > 0) {
    if (pickupEarlierThanLeadHours(payload, options, hours)) {
      conditions.push("lead_time");
    }
  }
  if (pending.invoice_terms_missing === true && payloadRequestsInvoice(payload)) {
    conditions.push("invoice");
  }
  if (conditions.length === 0) return null;
  return {
    matched: false,
    block_calculator: true,
    fallback: doc.fallback,
    pricing_source: "request_quote",
    request_quote_required: true,
    reason: "unconfirmed_price_conditions",
    conditions,
    message: PRICE_ON_REQUEST,
    price_label: PRICE_ON_REQUEST,
    fixed_fare_rule_id: null,
    pricing: null,
    snapshot: null,
  };
}

// A quote-only display never grants a price snapshot or booking authority.
// The caller supplies this work-area proof from its exact scoped profile,
// never from client fields. All normal rule eligibility still precedes this.
function restrictedAirportFareDisplay(doc, payload, options, winner, conditions) {
  const area = options.fixedFareDisplayWorkArea;
  const rule = winner?.rule;
  if (area?.configured !== true || area.checked !== true || area.inside !== true
    || !payloadIsAirportRide(payload) || rule?.kind !== 'airport' || rule.enabled !== true) return {};
  const rawAmount = to2(rule.price_incl_vat + (winner.match?.surcharges || [])
    .reduce((sum, surcharge) => sum + Number(surcharge.amount_incl_vat || 0), 0));
  if (!Number.isFinite(rawAmount) || rawAmount <= 0) return {};
  // Reuse the same VAT/rounding path as an eligible tariff. Visibility must
  // not introduce a different amount from the eventual payable quote.
  const amount = splitCompanyFixedPriceVat(rawAmount, {
    vatRate: options.vatRate, vatMode: options.vatMode,
  }).price_incl_vat;
  const hours = Number(fixedFareLeadHoursDeclared(options)
    ? options.airportFixedFareMinLeadHours : doc.pending_price_conditions?.lead_time_hours);
  const nowMs = Number.isFinite(Number(options.nowMs)) ? Number(options.nowMs) : Date.now();
  return {
    booking_allowed: false,
    booking_restriction: {
      reason: 'airport_price_conditions',
      conditions,
      ...(conditions.includes('lead_time') && Number.isFinite(hours) && hours > 0
        ? { minimum_advance_hours: hours, earliest_pickup_iso: new Date(nowMs + hours * 3600000).toISOString() } : {}),
    },
    fixed_fare_display: {
      display_only: true, pricing_source: 'airport_fixed_fare',
      fixed_fare_rule_id: rule.rule_id, currency: rule.currency || 'EUR',
      price_incl_vat: amount, price_covers: rule.price_covers === 'return_package'
        ? 'return_package' : (rule.price_covers === 'full_assignment' ? 'full_assignment' : 'one_way'),
    },
  };
}

function normalizeDirection(raw, kind) {
  const value = text(raw?.direction, 24).toLowerCase();
  if (kind === "airport") {
    if (
      value === "to_airport" ||
      value === "from_airport" ||
      value === "both" ||
      value === "return_package"
    ) {
      return value;
    }
    if (value === "one_way") return "to_airport";
    return "";
  }
  if (value === "both" || value === "both_ways") return "both";
  if (value === "one_way" || value === "to_airport" || value === "from_airport") return "one_way";
  return "one_way";
}

export function normalizeCompanyFixedPriceRule(raw, idx = 0) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  const vehicleCategory = raw.vehicle_category ?? raw.vehicleCategory;
  if (vehicleCategory != null && vehicleCategory !== "" && !["car", "minibus"].includes(vehicleCategory)) return null;
  const airportIata = upperToken(raw.airport_iata ?? raw.airportIata, 8);
  let origin = normalizeCompanyFixedPricePlace(raw.origin ?? raw.from_place, {
    required: false,
  });
  let destination = normalizeCompanyFixedPricePlace(
    raw.destination ?? raw.to_place,
    { required: false },
  );
  if ((!origin || !origin.type) && airportIata) {
    origin = normalizeCompanyFixedPricePlace({
      type: "airport",
      airport_iata: airportIata,
      label: airportIata,
    });
  }
  if ((!destination || !destination.type) && airportIata) {
    const zoneType = text(raw.zone_type ?? raw.zoneType ?? "none", 24).toLowerCase();
    if (zoneType === "radius") {
      destination = normalizeCompanyFixedPricePlace({
        type: "radius",
        label: raw.zone_label ?? raw.zoneLabel,
        lat: raw.zone_center_lat ?? raw.zoneCenterLat,
        lng: raw.zone_center_lng ?? raw.zoneCenterLng,
        radius_km: raw.radius_km ?? raw.radiusKm,
      });
    } else if (zoneType === "city" || zoneType === "postcode" || zoneType === "zone") {
      destination = normalizeCompanyFixedPricePlace({
        type: zoneType === "zone" ? "zone" : zoneType,
        value: raw.zone_value ?? raw.zoneValue,
        label: raw.zone_label ?? raw.zoneLabel ?? raw.zone_value,
      });
    }
  }
  const kind = inferKind(raw, origin, destination, airportIata);
  const direction = normalizeDirection(raw, kind);
  if (!direction) return null;
  if (kind === "airport") {
    const iata = airportIata || origin?.airport_iata || destination?.airport_iata;
    if (!iata || iata.length < 3) return null;
  } else if (!origin?.type || !destination?.type) {
    return null;
  }

  const price = Number(raw.price_incl_vat ?? raw.priceInclVat);
  if (!Number.isFinite(price) || price <= 0) return null;
  const currency = upperToken(raw.currency ?? "EUR", 8) || "EUR";
  if (currency !== "EUR") return null;

  const overflowModeRaw = text(
    raw.overflow_mode ?? raw.overflowMode ?? "no_match",
    32,
  ).toLowerCase();
  const overflow_mode = COMPANY_FIXED_PRICE_OVERFLOW_MODES.includes(overflowModeRaw)
    ? overflowModeRaw
    : "no_match";
  const overflowMeasureRaw = text(
    raw.overflow_measure ?? raw.overflowMeasure ?? "radius",
    24,
  ).toLowerCase();
  const overflow_measure = overflowMeasureRaw === "road" ? "road" : "radius";
  const overflowFromRaw = text(
    raw.overflow_from ?? raw.overflowFrom ?? "boundary",
    24,
  ).toLowerCase();
  const overflow_from = overflowFromRaw === "center" ? "center" : "boundary";
  const included_km = finiteOrNull(raw.included_km ?? raw.includedKm);
  const extra_per_km = finiteOrNull(raw.extra_per_km ?? raw.extraPerKm);
  const overflow_surcharge = finiteOrNull(
    raw.overflow_surcharge ?? raw.overflowSurcharge ?? raw.zone_surcharge,
  );
  if (overflow_mode === "extra_km") {
    if (!Number.isFinite(extra_per_km) || extra_per_km < 0) return null;
    if (overflow_measure === "road" && (!Number.isFinite(included_km) || included_km < 0)) {
      return null;
    }
  }
  if (overflow_mode === "zone_surcharge") {
    if (!Number.isFinite(overflow_surcharge) || overflow_surcharge < 0) return null;
  }

  const activeFrom = text(raw.active_from ?? raw.activeFrom ?? "", 64) || null;
  const activeUntil = text(raw.active_until ?? raw.activeUntil ?? "", 64) || null;
  const activeFromMs = activeFrom ? Date.parse(activeFrom) : null;
  const activeUntilMs = activeUntil ? Date.parse(activeUntil) : null;
  if (activeFrom && !Number.isFinite(activeFromMs)) return null;
  if (activeUntil && !Number.isFinite(activeUntilMs)) return null;

  const includes = raw.includes && typeof raw.includes === "object" ? raw.includes : {};
  const paxMin = intOr(raw.pax_min ?? raw.paxMin, 1, 1, 99);
  const paxMax = intOr(raw.pax_max ?? raw.paxMax, 99, paxMin, 99);
  const name = text(raw.name ?? raw.label ?? raw.rule_id, 120);
  const zoneType = destination?.type === "radius" || origin?.type === "radius"
    ? "radius"
    : destination?.type === "postcode" || origin?.type === "postcode"
      ? "postcode"
      : destination?.type === "city" || origin?.type === "city"
        ? "city"
        : destination?.type === "zone" || origin?.type === "zone"
          ? "zone"
          : airportIata
            ? text(raw.zone_type ?? "none", 24).toLowerCase() || "none"
            : "none";

  return {
    rule_id: text(raw.rule_id ?? raw.ruleId, 96) || `rule_${idx + 1}`,
    name: name || `Regel ${idx + 1}`,
    enabled: raw.enabled !== false,
    public_visible: raw.public_visible === true || raw.publicVisible === true,
    priority: intOr(raw.priority, 0, 0, 1_000_000),
    rule_version: intOr(raw.rule_version ?? raw.ruleVersion, 1, 1, 10_000),
    kind,
    airport_iata:
      kind === "airport"
        ? airportIata || origin?.airport_iata || destination?.airport_iata
        : "",
    direction,
    origin: origin && origin.type ? origin : emptyPlace(),
    destination: destination && destination.type ? destination : emptyPlace(),
    tier: text(raw.tier ?? "", 24).toLowerCase(),
    ...(vehicleCategory ? { vehicle_category: vehicleCategory } : {}),
    pax_min: paxMin,
    pax_max: paxMax,
    bags_max: intOr(raw.bags_max ?? raw.bagsMax, 99, 0, 99),
    zone_type: ["none", "postcode", "city", "country", "radius", "zone"].includes(zoneType)
      ? zoneType
      : "none",
    zone_value: destination?.type && destination.type !== "airport" && destination.type !== "radius"
      ? destination.value
      : text(raw.zone_value ?? raw.zoneValue, 80),
    zone_label: destination?.label || text(raw.zone_label ?? raw.zoneLabel, 120),
    zone_center_lat: destination?.type === "radius" ? destination.lat : origin?.type === "radius" ? origin.lat : null,
    zone_center_lng: destination?.type === "radius" ? destination.lng : origin?.type === "radius" ? origin.lng : null,
    radius_km: destination?.type === "radius" ? destination.radius_km : origin?.type === "radius" ? origin.radius_km : null,
    price_incl_vat: to2(price),
    currency,
    price_covers: returnPackageCover(raw, direction),
    outside_pax: text(raw.outside_pax ?? raw.outsidePax, 24).toLowerCase() === "no_price"
      ? "no_price"
      : "",
    overflow_mode,
    overflow_measure,
    overflow_from,
    included_km: Number.isFinite(included_km) ? to2(included_km) : null,
    extra_per_km: Number.isFinite(extra_per_km) ? to2(extra_per_km) : null,
    overflow_surcharge: Number.isFinite(overflow_surcharge) ? to2(overflow_surcharge) : null,
    includes: {
      wait: includes.wait === true,
      bags: includes.bags === true,
      extras: includes.extras === true,
      note: text(includes.note, 200),
    },
    apply_night_surcharge: raw.apply_night_surcharge === true,
    apply_weekend_surcharge: raw.apply_weekend_surcharge === true,
    active_from: activeFrom,
    active_until: activeUntil,
    active_from_ms: Number.isFinite(activeFromMs) ? activeFromMs : null,
    active_until_ms: Number.isFinite(activeUntilMs) ? activeUntilMs : null,
  };
}

export function normalizeCompanyFixedPricesDocument(raw) {
  const source =
    raw && typeof raw === "object" && !Array.isArray(raw)
      ? raw.airport_fixed_fares && typeof raw.airport_fixed_fares === "object"
        ? raw.airport_fixed_fares
        : raw.company_fixed_prices && typeof raw.company_fixed_prices === "object"
          ? raw.company_fixed_prices
          : raw
      : {};
  const fallbackRaw = text(
    source.fallback ?? raw?.fallback ?? "calculator",
    32,
  ).toLowerCase();
  const rulesInput = Array.isArray(source.rules) ? source.rules : [];
  const rules = [];
  for (let i = 0; i < rulesInput.length; i += 1) {
    const normalized = normalizeCompanyFixedPriceRule(rulesInput[i], i);
    if (normalized) rules.push(normalized);
  }
  return {
    version: intOr(source.version, 1, 1, 10_000),
    updated_at:
      text(source.updated_at ?? source.updatedAt ?? "", 80) ||
      new Date().toISOString(),
    fallback: fallbackRaw === "request_quote" ? "request_quote" : "calculator",
    rules,
    ...(normalizePendingPriceConditions(source)
      ? { pending_price_conditions: normalizePendingPriceConditions(source) }
      : {}),
  };
}

function collectTexts(payload, keys) {
  const out = [];
  for (const key of keys) {
    const value = text(payload?.[key], 160);
    if (value) out.push(value);
  }
  return out;
}

function firstFinite(payload, keys) {
  for (const key of keys) {
    const value = finiteOrNull(payload?.[key]);
    if (value != null) return value;
  }
  return null;
}

export function buildCompanyFixedPriceContext(payload = {}, options = {}) {
  const transfer =
    payload.airport_transfer && typeof payload.airport_transfer === "object"
      ? payload.airport_transfer
      : {};
  const direction = text(
    payload.airport_direction ??
      payload.airportDirection ??
      transfer.airport_direction ??
      options.direction,
    24,
  ).toLowerCase();
  const airportIata = upperToken(
    payload.airport_iata ??
      payload.airportIata ??
      transfer.airport_iata ??
      options.airportIata,
    8,
  );
  const fromText = text(
    payload.from ?? payload.pickup ?? payload.pickup_address ?? options.from,
    240,
  );
  const toText = text(
    payload.to ?? payload.dropoff ?? payload.destination ?? options.to,
    240,
  );
  const pickupLat = firstFinite(payload, [
    "pickup_lat",
    "pickupLat",
    "from_lat",
    "fromLat",
  ]);
  const pickupLng = firstFinite(payload, [
    "pickup_lng",
    "pickupLon",
    "pickup_lon",
    "from_lng",
    "fromLon",
  ]);
  const dropoffLat = firstFinite(payload, [
    "dropoff_lat",
    "dropoffLat",
    "to_lat",
    "destination_lat",
  ]);
  const dropoffLng = firstFinite(payload, [
    "dropoff_lng",
    "dropoffLon",
    "dropoff_lon",
    "to_lng",
    "destination_lng",
  ]);
  const cities = [
    ...collectTexts(payload, [
      "city",
      "pickup_city",
      "pickupCity",
      "from_city",
      "destination_city",
      "to_city",
    ]),
    fromText,
    toText,
  ].map(normCity).filter(Boolean);
  const postcodes = collectTexts(payload, [
    "postcode",
    "postal_code",
    "pickup_postcode",
    "from_postcode",
    "destination_postcode",
    "to_postcode",
  ]).map(normPostcode).filter(Boolean);
  const genericCity = [payload.city, payload.pickupCity];
  const genericPostcode = [payload.postcode, payload.postal_code];
  const fromLocality = collectLocalityTokens([
    payload.from_city,
    payload.pickup_city,
    options.fromCity,
    ...genericCity,
    fromText,
  ]);
  const toLocality = collectLocalityTokens([
    payload.to_city,
    payload.destination_city,
    options.toCity,
    ...genericCity,
    toText,
  ]);
  const fromPostcodes = collectPostcodes(
    [
      payload.from_postcode,
      payload.pickup_postcode,
      options.fromPostcode,
      ...genericPostcode,
    ],
    [fromText, payload.from_city, payload.pickup_city],
  );
  const toPostcodes = collectPostcodes(
    [
      payload.to_postcode,
      payload.destination_postcode,
      options.toPostcode,
      ...genericPostcode,
    ],
    [toText, payload.to_city, payload.destination_city],
  );
  return {
    from_locality: fromLocality,
    to_locality: toLocality,
    from_postcodes: fromPostcodes,
    to_postcodes: toPostcodes,
    airport_iata: airportIata,
    direction,
    return_requested: payloadRequestsReturn(payload),
    from_text: fromText,
    to_text: toText,
    from_city: normCity(payload.from_city ?? payload.pickup_city ?? options.fromCity ?? fromText),
    to_city: normCity(payload.to_city ?? payload.destination_city ?? options.toCity ?? toText),
    from_postcode: normPostcode(payload.from_postcode ?? payload.pickup_postcode ?? options.fromPostcode),
    to_postcode: normPostcode(payload.to_postcode ?? payload.destination_postcode ?? options.toPostcode),
    pickup_lat: pickupLat,
    pickup_lng: pickupLng,
    dropoff_lat: dropoffLat,
    dropoff_lng: dropoffLng,
    vehicle_category: options.vehicleCategory ?? null,
    tier: text(payload.tier ?? options.tier ?? "", 24).toLowerCase(),
    pax: intOr(payload.pax ?? payload.passengers ?? options.pax, 1, 1, 99),
    bags: intOr(payload.bags ?? options.bags, 0, 0, 99),
    road_distance_km: finiteOrNull(
      payload.road_distance_km ?? payload.distance_km ?? options.roadDistanceKm,
    ),
    now_ms: Number.isFinite(Date.parse(options.nowIso))
      ? Date.parse(options.nowIso)
      : Date.now(),
    cities,
    postcodes,
  };
}

function placeMatches(place, ctx, { role }) {
  if (!place?.type) return { matched: false, reason: "place_missing" };
  if (place.type === "airport") {
    const iata = role === "origin"
      ? ctx.direction === "from_airport" ? ctx.airport_iata : ctx.airport_iata
      : ctx.airport_iata;
    const hay = [iata, role === "origin" ? ctx.from_text : ctx.to_text]
      .map((value) => upperToken(value, 16))
      .filter(Boolean);
    if (!hay.includes(place.airport_iata)) {
      return { matched: false, reason: "airport_iata_mismatch" };
    }
    return { matched: true, reason: "airport", specificity: ZONE_RANK.airport };
  }
  if (place.type === "city") {
    const tokens = role === "origin" ? ctx.from_locality : ctx.to_locality;
    const point = role === "origin"
      ? { lat: ctx.pickup_lat, lng: ctx.pickup_lng }
      : { lat: ctx.dropoff_lat, lng: ctx.dropoff_lng };
    if (place.parent_city && !localityHolds(tokens, place.parent_city)) return {matched:false,reason:"parent_city_mismatch"};
    const placeRank = qualifiedLocalityRank(tokens, place.value, point.lat, point.lng);
    if (placeRank < 0) {
      return { matched: false, reason: "city_mismatch" };
    }
    return {
      matched: true,
      reason: "city",
      specificity: ZONE_RANK.city,
      place_rank: placeRank,
    };
  }
  if (place.type === "postcode") {
    const needle = place.value;
    const candidates = role === "origin" ? ctx.from_postcodes : ctx.to_postcodes;
    // A postcode rule covers one postcode area, never the whole municipality.
    // Without a postcode the rule cannot be judged; say so instead of
    // reporting a mismatch the company cannot act on.
    if (candidates.length === 0) {
      return {
        matched: false,
        reason: "postcode_unknown",
        needs: {
          role,
          place_type: "postcode",
          value: needle,
          label: place.label || needle,
        },
      };
    }
    if (!candidates.some((item) => item === needle || item.startsWith(needle))) {
      return { matched: false, reason: "postcode_mismatch" };
    }
    return { matched: true, reason: "postcode", specificity: ZONE_RANK.postcode };
  }
  if (place.type === "zone") {
    const tokens = role === "origin" ? ctx.from_locality : ctx.to_locality;
    const point = role === "origin"
      ? { lat: ctx.pickup_lat, lng: ctx.pickup_lng }
      : { lat: ctx.dropoff_lat, lng: ctx.dropoff_lng };
    const placeRank = qualifiedLocalityRank(
      tokens,
      normCity(place.value || place.label),
      point.lat,
      point.lng,
    );
    if (placeRank < 0) {
      return { matched: false, reason: "zone_mismatch" };
    }
    return {
      matched: true,
      reason: "zone",
      specificity: ZONE_RANK.zone,
      place_rank: placeRank,
    };
  }
  if (place.type === "radius") {
    const lat = role === "origin" ? ctx.pickup_lat : ctx.dropoff_lat;
    const lng = role === "origin" ? ctx.pickup_lng : ctx.dropoff_lng;
    const distance = haversineKm(lat, lng, place.lat, place.lng);
    if (!Number.isFinite(distance)) {
      return { matched: false, reason: "radius_context_missing_coords" };
    }
    return {
      matched: true,
      reason: distance <= place.radius_km ? "radius_inside" : "radius_outside",
      inside: distance <= place.radius_km + 0.0001,
      on_boundary: Math.abs(distance - place.radius_km) <= 0.05,
      distance_km: to2(distance),
      radius_km: place.radius_km,
      specificity: ZONE_RANK.radius,
    };
  }
  return { matched: false, reason: "place_unsupported" };
}

function conditionsOk(rule, ctx) {
  if (rule.enabled !== true) return { ok: false, reason: "disabled" };
  if (rule.vehicle_category && rule.vehicle_category !== ctx.vehicle_category) return { ok: false, reason: "vehicle_category_mismatch" };
  if (rule.tier && ctx.tier && rule.tier !== ctx.tier) {
    return { ok: false, reason: "tier_mismatch" };
  }
  if (ctx.pax < rule.pax_min || ctx.pax > rule.pax_max) {
    return { ok: false, reason: "pax_mismatch" };
  }
  if (ctx.bags > rule.bags_max) return { ok: false, reason: "bags_mismatch" };
  if (Number.isFinite(rule.active_from_ms) && ctx.now_ms < rule.active_from_ms) {
    return { ok: false, reason: "inactive_not_started" };
  }
  if (Number.isFinite(rule.active_until_ms) && ctx.now_ms > rule.active_until_ms) {
    return { ok: false, reason: "inactive_expired" };
  }
  return { ok: true };
}

export function applyCompanyFixedPriceOverflow(rule, radiusMatch, ctx) {
  const surcharges = [];
  if (!radiusMatch || radiusMatch.inside !== false) {
    return { ok: true, surcharges, paying_km: 0, measure_used: "" };
  }
  if (rule.overflow_mode === "no_match") {
    return { ok: false, reason: "radius_outside", surcharges };
  }
  if (rule.overflow_mode === "zone_surcharge") {
    surcharges.push({
      kind: "zone_surcharge",
      label: "Zonetoeslag buiten het inbegrepen gebied",
      amount_incl_vat: to2(rule.overflow_surcharge),
    });
    return { ok: true, surcharges, paying_km: 0, measure_used: "zone" };
  }
  if (rule.overflow_mode !== "extra_km") {
    return { ok: false, reason: "overflow_unsupported", surcharges };
  }
  if (rule.overflow_measure === "road") {
    if (!Number.isFinite(ctx.road_distance_km)) {
      return { ok: false, reason: "road_distance_required", surcharges };
    }
    const paying = Math.max(0, ctx.road_distance_km - Number(rule.included_km || 0));
    if (paying > 0) {
      surcharges.push({
        kind: "extra_km",
        label: `Toeslag extra wegkilometers (${to2(paying)} km)`,
        amount_incl_vat: to2(paying * rule.extra_per_km),
        paying_km: to2(paying),
        measure: "road",
      });
    }
    return { ok: true, surcharges, paying_km: to2(paying), measure_used: "road" };
  }
  const distance = Number(radiusMatch.distance_km);
  if (!Number.isFinite(distance)) {
    return { ok: false, reason: "radius_coords_required", surcharges };
  }
  const paying = rule.overflow_from === "center"
    ? distance
    : Math.max(0, distance - Number(radiusMatch.radius_km || 0));
  if (paying > 0) {
    surcharges.push({
      kind: "extra_km",
      label: `Toeslag extra straal-kilometers vanaf de ${rule.overflow_from === "center" ? "kern" : "gebiedsgrens"} (${to2(paying)} km)`,
      amount_incl_vat: to2(paying * rule.extra_per_km),
      paying_km: to2(paying),
      measure: "radius",
    });
  }
  return { ok: true, surcharges, paying_km: to2(paying), measure_used: "radius" };
}

function matchAirportRule(rule, ctx) {
  const iata = rule.airport_iata;
  if (!iata || iata !== ctx.airport_iata) {
    return { matched: false, reason: "airport_iata_mismatch" };
  }
  // A return package is the billable total of a round trip. It must not match
  // a single leg, or a one-way ride would be charged the package price.
  if (rule.direction === "return_package") {
    return { matched: false, reason: "return_package_not_a_leg" };
  }
  if (!(rule.direction === "both" || rule.direction === ctx.direction)) {
    return { matched: false, reason: "direction_mismatch" };
  }
  const cond = conditionsOk(rule, ctx);
  if (!cond.ok) return { matched: false, reason: cond.reason };
  const other = rule.destination?.type && rule.destination.type !== "airport"
    ? rule.destination
    : rule.origin?.type && rule.origin.type !== "airport"
      ? rule.origin
      : null;
  if (!other || !other.type) {
    return { matched: true, reason: "airport_open", specificity: ZONE_RANK.airport, inside: true };
  }
  const role = ctx.direction === "from_airport" ? "destination" : "origin";
  const place = placeMatches(other, ctx, { role: other.type === "radius" || other.type === "city" || other.type === "postcode" || other.type === "zone" ? role : "origin" });
  if (!place.matched && place.reason !== "radius_outside") {
    return { matched: false, reason: place.reason, needs: place.needs };
  }
  if (other.type === "radius") {
    const overflow = applyCompanyFixedPriceOverflow(rule, {
      inside: place.inside === true,
      distance_km: place.distance_km,
      radius_km: place.radius_km,
    }, ctx);
    if (!overflow.ok) {
      return { matched: false, reason: overflow.reason, distance_km: place.distance_km };
    }
    return {
      matched: true,
      reason: place.inside ? "radius_inside" : "radius_overflow",
      specificity: ZONE_RANK.radius,
      inside: place.inside === true,
      on_boundary: place.on_boundary === true,
      distance_km: place.distance_km,
      surcharges: overflow.surcharges,
      measure_used: overflow.measure_used,
    };
  }
  if (!place.matched) return { matched: false, reason: place.reason };
  return {
    matched: true,
    reason: place.reason,
    specificity: place.specificity,
    place_rank: place.place_rank,
    inside: true,
    surcharges: [],
  };
}

function matchCityPair(rule, ctx, { swapped = false } = {}) {
  const cond = conditionsOk(rule, ctx);
  if (!cond.ok) return { matched: false, reason: cond.reason };
  const originRole = swapped ? "destination" : "origin";
  const destRole = swapped ? "origin" : "destination";
  const origin = placeMatches(rule.origin, ctx, { role: originRole });
  const destination = placeMatches(rule.destination, ctx, { role: destRole });
  if (!origin.matched && origin.reason !== "radius_outside") {
    return { matched: false, reason: `origin_${origin.reason}`, needs: origin.needs };
  }
  if (!destination.matched && destination.reason !== "radius_outside") {
    return {
      matched: false,
      reason: `destination_${destination.reason}`,
      needs: destination.needs,
    };
  }
  const radiusHit = origin.reason?.startsWith("radius")
    ? origin
    : destination.reason?.startsWith("radius")
      ? destination
      : null;
  const overflow = applyCompanyFixedPriceOverflow(rule, {
    inside: radiusHit ? radiusHit.inside === true : true,
    distance_km: radiusHit?.distance_km,
    radius_km: radiusHit?.radius_km,
  }, ctx);
  if (!overflow.ok) return { matched: false, reason: overflow.reason };
  const placeRanks = [origin.place_rank, destination.place_rank].filter((rank) => Number.isFinite(rank));
  return {
    matched: true,
    reason: swapped ? "city_pair_swapped" : "city_pair",
    specificity: Math.max(origin.specificity || 0, destination.specificity || 0),
    ...(placeRanks.length > 0 ? { place_rank: Math.min(...placeRanks) } : {}),
    inside: radiusHit ? radiusHit.inside === true : true,
    on_boundary: radiusHit?.on_boundary === true,
    distance_km: radiusHit?.distance_km,
    surcharges: overflow.surcharges,
    measure_used: overflow.measure_used,
    swapped,
  };
}

export function matchCompanyFixedPriceRule(rule, ctx) {
  if (!rule || !ctx) return { matched: false, reason: "invalid_input" };
  if (rule.kind === "airport") return matchAirportRule(rule, ctx);
  const forward = matchCityPair(rule, ctx, { swapped: false });
  if (forward.matched) return forward;
  if (rule.direction === "both") {
    const back = matchCityPair(rule, ctx, { swapped: true });
    if (back.matched) return back;
  }
  return forward;
}

export function selectBestCompanyFixedPriceRule(matches) {
  if (!Array.isArray(matches) || matches.length === 0) return null;
  const sorted = [...matches].sort((a, b) => {
    const pa = intOr(a?.rule?.priority, 0, 0, 1_000_000);
    const pb = intOr(b?.rule?.priority, 0, 0, 1_000_000);
    if (pb !== pa) return pb - pa;
    const za = Number(a?.match?.specificity || 0);
    const zb = Number(b?.match?.specificity || 0);
    if (zb !== za) return zb - za;
    const placeA = Number(a?.match?.place_rank);
    const placeB = Number(b?.match?.place_rank);
    if (Number.isFinite(placeA) && Number.isFinite(placeB) && placeA !== placeB) {
      return placeA - placeB;
    }
    const ra = Number(a?.rule?.radius_km);
    const rb = Number(b?.rule?.radius_km);
    if (Number.isFinite(ra) && Number.isFinite(rb) && ra !== rb) return ra - rb;
    return text(a?.rule?.rule_id, 120).localeCompare(text(b?.rule?.rule_id, 120));
  });
  return sorted[0] || null;
}

export function splitCompanyFixedPriceVat(priceIncl, { vatRate = 0.06, vatMode = "incl" } = {}) {
  const incl = Number(priceIncl);
  const rate = Math.max(0, Math.min(1, Number(vatRate) || 0));
  if (!Number.isFinite(incl) || incl <= 0) {
    return { price_ex_vat: 0, price_vat: 0, price_incl_vat: 0, vat_rate: rate, vat_mode: vatMode };
  }
  const rounded = Math.round(incl * 10) / 10;
  const ex = vatMode === "excl" ? rounded : rounded / (1 + rate);
  const vat = vatMode === "excl" ? rounded * rate : rounded - ex;
  const inclOut = vatMode === "excl" ? rounded + vat : rounded;
  return {
    price_ex_vat: to2(ex),
    price_vat: to2(vat),
    price_incl_vat: to2(inclOut),
    vat_rate: rate,
    vat_mode: vatMode === "excl" ? "excl" : "incl",
  };
}

function customerLocalityTokens(ctx) {
  return ctx.direction === "from_airport" ? ctx.to_locality : ctx.from_locality;
}

function customerSideText(ctx) {
  return ctx.direction === "from_airport" ? ctx.to_text : ctx.from_text;
}

function airportDocumentHasCityRules(doc, ctx) {
  return doc.rules.some((rule) =>
    rule.enabled === true &&
    rule.kind === "airport" &&
    rule.airport_iata === ctx.airport_iata &&
    (rule.destination?.type === "city" ||
      rule.origin?.type === "city" ||
      rule.zone_type === "city")
  );
}

function pickupAddressRequiredResult(doc, ctx) {
  if (!airportDocumentHasCityRules(doc, ctx)) return null;
  const raw = customerSideText(ctx);
  if (!text(raw, 4) || localityTokens(raw).length > 0) return null;
  const message = ctx.direction === "from_airport"
    ? "Kies een volledig afzetadres. Een postcode alleen legt de gemeente niet vast."
    : "Kies een volledig ophaaladres. Een postcode alleen legt de gemeente niet vast.";
  return {
    matched: false,
    block_calculator: true,
    fallback: doc.fallback,
    pricing_source: "request_quote",
    request_quote_required: true,
    reason: "pickup_address_required",
    message,
    price_label: message,
    fixed_fare_rule_id: null,
    pricing: null,
    snapshot: null,
  };
}

function airportCustomerZoneMatches(rule, ctx) {
  if (!rule || rule.kind !== "airport" || rule.enabled !== true) return false;
  if (!rule.airport_iata || rule.airport_iata !== ctx.airport_iata) return false;
  if (rule.direction === "return_package") {
    if (ctx.return_requested !== true) return false;
  } else if (!(rule.direction === "both" || rule.direction === ctx.direction)) {
    return false;
  }
  const place = rule.destination?.type && rule.destination.type !== "airport"
    ? rule.destination
    : rule.origin?.type && rule.origin.type !== "airport"
      ? rule.origin
      : null;
  if (!place || (place.type !== "city" && place.type !== "zone")) return false;
  const point = ctx.direction === "from_airport"
    ? { lat: ctx.dropoff_lat, lng: ctx.dropoff_lng }
    : { lat: ctx.pickup_lat, lng: ctx.pickup_lng };
  return qualifiedLocalityRank(
    customerLocalityTokens(ctx),
    normCity(place.value || place.label),
    point.lat,
    point.lng,
  ) >= 0;
}

export function resolveReturnPackageFromDocument(document, payload, options = {}) {
  if (!payloadRequestsReturn(payload)) {
    return { matched: false, reason: "not_a_return", pricing: null, snapshot: null };
  }
  const doc = normalizeCompanyFixedPricesDocument(document);
  const ctx = buildCompanyFixedPriceContext(payload, options);
  const tokens = customerLocalityTokens(ctx);
  const point = ctx.direction === "from_airport"
    ? { lat: ctx.dropoff_lat, lng: ctx.dropoff_lng }
    : { lat: ctx.pickup_lat, lng: ctx.pickup_lng };
  const matches = [];
  for (const rule of doc.rules) {
    if (rule.direction !== "return_package" || rule.enabled !== true) continue;
    if (rule.price_covers === "full_assignment") continue;
    if (!rule.airport_iata || rule.airport_iata !== ctx.airport_iata) continue;
    const cond = conditionsOk(rule, ctx);
    if (!cond.ok) continue;
    const place = rule.destination?.type === "city" || rule.destination?.type === "zone"
      ? rule.destination
      : rule.origin?.type === "city" || rule.origin?.type === "zone"
        ? rule.origin
        : null;
    if (!place) continue;
    const placeRank = qualifiedLocalityRank(
      tokens,
      normCity(place.value || place.label),
      point.lat,
      point.lng,
    );
    if (placeRank < 0) continue;
    matches.push({ rule, place_rank: placeRank });
  }
  if (matches.length === 0) {
    return { matched: false, reason: "no_return_package", pricing: null, snapshot: null };
  }
  matches.sort((a, b) => {
    const priority = (b.rule.priority || 0) - (a.rule.priority || 0);
    if (priority !== 0) return priority;
    if (a.place_rank !== b.place_rank) return a.place_rank - b.place_rank;
    return a.rule.rule_id.localeCompare(b.rule.rule_id);
  });
  const held = unconfirmedPriceHold(doc, payload, options);
  if (held) return { ...held, return_package_applied: false,
    ...restrictedAirportFareDisplay(doc, payload, options, matches[0], held.conditions) };
  if (confirmedFixedFareLeadTooSoon(payload, options)) {
    return {
      matched: false,
      reason: "lead_time",
      conditions: ["lead_time"],
      return_package_applied: false,
      pricing: null,
      snapshot: null,
      ...restrictedAirportFareDisplay(doc, payload, options, matches[0], ['lead_time']),
    };
  }
  const rule = matches[0].rule;
  const vat = splitCompanyFixedPriceVat(rule.price_incl_vat, {
    vatRate: options.vatRate,
    vatMode: options.vatMode,
  });
  const note = "Retourpakket. Het bedrag geldt voor de hele heen-en-terugrit en is niet verdeeld over de ritten.";
  return {
    matched: true,
    pricing_source: "airport_fixed_fare",
    fixed_fare_applied: true,
    fixed_fare_rule_id: rule.rule_id,
    return_package_applied: true,
    price_covers: "return_package",
    pricing: {
      price_ex_vat: vat.price_ex_vat,
      price_vat: vat.price_vat,
      price_incl_vat: vat.price_incl_vat,
      note,
    },
    snapshot: {
      pricing_source: "airport_fixed_fare",
      fixed_fare_rule_id: rule.rule_id,
      name: rule.name,
      kind: "airport",
      direction: "return_package",
      price_covers: "return_package",
      total_incl_vat: vat.price_incl_vat,
      base_incl_vat: rule.price_incl_vat,
      note,
    },
  };
}

export function resolveCompanyFixedPriceFromDocument(document, payload, options = {}) {
  const doc = normalizeCompanyFixedPricesDocument(document);
  const ctx = buildCompanyFixedPriceContext(payload, options);
  const candidates = [];
  for (const rule of doc.rules) {
    const match = matchCompanyFixedPriceRule(rule, ctx);
    candidates.push({
      rule_id: rule.rule_id,
      name: rule.name,
      priority: rule.priority,
      matched: match.matched === true,
      reason: match.reason,
      ...(match.needs ? { needs: match.needs } : {}),
    });
    if (match.matched) {
      candidates[candidates.length - 1].selected = false;
    }
  }
  const matched = [];
  for (const rule of doc.rules) {
    const match = matchCompanyFixedPriceRule(rule, ctx);
    if (match.matched) matched.push({ rule, match });
  }
  const winner = selectBestCompanyFixedPriceRule(matched);
  const held = winner?.rule ? unconfirmedPriceHold(doc, payload, options) : null;
  if (held) {
    return { ...held, candidates, needs_more_detail: [],
      ...restrictedAirportFareDisplay(doc, payload, options, winner, held.conditions) };
  }
  const fixedFareLeadTooSoon = !!(winner?.rule && confirmedFixedFareLeadTooSoon(payload, options));
  const applicableWinner = fixedFareLeadTooSoon ? null : winner;
  if (!applicableWinner?.rule) {
    const needsDetail = candidates
      .filter((row) => row.needs)
      .map((row) => ({ rule_id: row.rule_id, name: row.name, ...row.needs }));
    const paxBlocked = doc.rules.filter((rule) =>
      rule.outside_pax === "no_price" &&
      airportCustomerZoneMatches(rule, ctx) &&
      (ctx.pax < rule.pax_min || ctx.pax > rule.pax_max)
    );
    if (paxBlocked.length > 0) {
      return {
        matched: false,
        block_calculator: true,
        fallback: doc.fallback,
        pricing_source: "request_quote",
        request_quote_required: true,
        reason: "pax_not_covered",
        message:
          "Geen vaste luchthavenprijs voor dit passagiersaantal. Het supplement voor 4–8 personen en het minimum van €125 zijn niet geactiveerd.",
        needs_more_detail: needsDetail,
        candidates,
        fixed_fare_rule_id: null,
        pricing: null,
        snapshot: null,
      };
    }
    const addressRequired = pickupAddressRequiredResult(doc, ctx);
    if (addressRequired) {
      return { ...addressRequired, candidates, needs_more_detail: needsDetail };
    }
    if (
      options.airportAutoCalcOutsideFixedFares === false &&
      payloadIsAirportRide(payload)
    ) {
      return { ...noFixedAirportFareResult(
        doc,
        needsDetail,
        candidates,
        fixedFareLeadTooSoon ? { conditions: ["lead_time"] } : {},
      ), ...(fixedFareLeadTooSoon
        ? restrictedAirportFareDisplay(doc, payload, options, winner, ['lead_time']) : {}) };
    }
    return {
      matched: false,
      fallback: doc.fallback,
      pricing_source: doc.fallback === "request_quote" ? "request_quote" : "route_calc",
      request_quote_required: doc.fallback === "request_quote",
      needs_more_detail: needsDetail,
      candidates,
      snapshot: null,
      ...(fixedFareLeadTooSoon
        ? restrictedAirportFareDisplay(doc, payload, options, winner, ['lead_time']) : {}),
    };
  }
  const surchargeTotal = (applicableWinner.match.surcharges || []).reduce(
    (sum, item) => sum + Number(item.amount_incl_vat || 0),
    0,
  );
  const total = to2(applicableWinner.rule.price_incl_vat + surchargeTotal);
  const vat = splitCompanyFixedPriceVat(total, {
    vatRate: options.vatRate,
    vatMode: options.vatMode,
  });
  for (const row of candidates) {
    if (row.rule_id === winner.rule.rule_id) row.selected = true;
  }
  const snapshot = {
    pricing_source:
      winner.rule.kind === "airport" ? "airport_fixed_fare" : "company_fixed_price",
    fixed_fare_applied: true,
    fixed_fare_rule_id: winner.rule.rule_id,
    rule_version: winner.rule.rule_version,
    document_version: doc.version,
    name: winner.rule.name,
    kind: winner.rule.kind,
    direction: winner.rule.direction,
    price_covers: winner.rule.price_covers,
    currency: winner.rule.currency,
    base_incl_vat: winner.rule.price_incl_vat,
    surcharges: winner.match.surcharges || [],
    total_incl_vat: vat.price_incl_vat,
    price_ex_vat: vat.price_ex_vat,
    price_vat: vat.price_vat,
    vat_rate: vat.vat_rate,
    vat_mode: vat.vat_mode,
    overflow_mode: winner.rule.overflow_mode,
    overflow_measure: winner.match.measure_used || winner.rule.overflow_measure,
    overflow_from: winner.rule.overflow_from,
    distance_km: winner.match.distance_km ?? null,
    inside: winner.match.inside !== false,
    on_boundary: winner.match.on_boundary === true,
    candidates,
    note:
      winner.rule.kind === "airport"
        ? "Vaste luchthavenprijs toegepast."
        : "Vaste bedrijfsprijs toegepast.",
  };
  return {
    matched: true,
    fallback: doc.fallback,
    pricing_source: snapshot.pricing_source,
    request_quote_required: false,
    fixed_fare_applied: true,
    fixed_fare_rule_id: winner.rule.rule_id,
    pricing: {
      price_ex_vat: vat.price_ex_vat,
      price_vat: vat.price_vat,
      price_incl_vat: vat.price_incl_vat,
      note: snapshot.note,
      breakdown: {
        kind: snapshot.pricing_source,
        ...snapshot,
      },
    },
    snapshot,
    candidates,
  };
}

export function companyFixedPriceTotalsDiffer(left, right) {
  return Math.round(Number(left) * 100) !== Math.round(Number(right) * 100);
}

export function isCompanyAirportKindRule(rule) {
  const kind = text(rule?.kind, 24).toLowerCase();
  if (kind === "airport") return true;
  if (kind === "city_pair") return false;
  return !!upperToken(rule?.airport_iata ?? rule?.airportIata, 8);
}

export function companyFixedPriceRuleIsAirportCatalog(rule) {
  if (isCompanyAirportKindRule(rule)) return true;
  const originType = text(rule?.origin?.type, 24).toLowerCase();
  const destType = text(rule?.destination?.type, 24).toLowerCase();
  return originType === "airport" || destType === "airport";
}

function ruleIsActiveAt(rule, atMs) {
  if (!Number.isFinite(atMs)) return true;
  if (Number.isFinite(rule.active_from_ms) && atMs < rule.active_from_ms) return false;
  if (Number.isFinite(rule.active_until_ms) && atMs > rule.active_until_ms) return false;
  return true;
}

function publicCoordinate(value) {
  if (value === null || value === undefined || value === "") return null;
  return finiteOrNull(value);
}

function publicPlace(place) {
  return {
    type: text(place?.type, 24),
    value: text(place?.value, 80),
    label: text(place?.label || place?.value, 120),
    airport_iata: upperToken(place?.airport_iata, 8),
    lat: publicCoordinate(place?.lat),
    lng: publicCoordinate(place?.lng),
    radius_km: publicCoordinate(place?.radius_km),
  };
}

export function companyFixedPricePublicEntry(rule, { vatRate, documentVersion } = {}) {
  const vat = splitCompanyFixedPriceVat(rule.price_incl_vat, {
    vatRate: Number.isFinite(Number(vatRate)) ? Number(vatRate) : undefined,
    vatMode: "incl",
  });
  return {
    rule_id: rule.rule_id,
    name: rule.name,
    kind: rule.kind,
    airport_iata: rule.airport_iata || "",
    direction: rule.direction,
    origin: publicPlace(rule.origin),
    destination: publicPlace(rule.destination),
    price_incl_vat: vat.price_incl_vat,
    price_ex_vat: vat.price_ex_vat,
    price_vat: vat.price_vat,
    vat_rate: vat.vat_rate,
    currency: rule.currency,
    price_covers: rule.price_covers,
    tier: rule.tier || "",
    ...(rule.vehicle_category ? {vehicle_category:rule.vehicle_category} : {}),
    pax_min: rule.pax_min,
    pax_max: rule.pax_max,
    bags_max: rule.bags_max,
    includes: { ...rule.includes },
    overflow_mode: rule.overflow_mode,
    overflow_measure: rule.overflow_measure,
    zone_surcharge:
      rule.overflow_mode === "zone_surcharge" ? rule.overflow_surcharge : null,
    extra_per_km: rule.overflow_mode === "extra_km" ? rule.extra_per_km : null,
    included_km: rule.overflow_mode === "extra_km" ? rule.included_km : null,
    apply_night_surcharge: rule.apply_night_surcharge === true,
    apply_weekend_surcharge: rule.apply_weekend_surcharge === true,
    rule_version: rule.rule_version,
    document_version: documentVersion ?? null,
  };
}

export function publicCompanyFixedPricesFromDocument(document, options = {}) {
  const doc = normalizeCompanyFixedPricesDocument(document);
  const atMs = options.nowIso ? Date.parse(options.nowIso) : Date.now();
  const airport = [];
  const city = [];
  for (const rule of doc.rules) {
    if (rule.public_visible !== true) continue;
    if (rule.enabled === false) continue;
    if (!ruleIsActiveAt(rule, atMs)) continue;
    const entry = companyFixedPricePublicEntry(rule, {
      vatRate: options.vatRate,
      documentVersion: doc.version,
    });
    if (companyFixedPriceRuleIsAirportCatalog(rule)) airport.push(entry);
    else city.push(entry);
  }
  const byPriority = (left, right) =>
    left.price_incl_vat - right.price_incl_vat || left.name.localeCompare(right.name);
  airport.sort(byPriority);
  city.sort(byPriority);
  return {
    fallback: doc.fallback,
    document_version: doc.version,
    updated_at: doc.updated_at,
    airport,
    city,
    total: airport.length + city.length,
  };
}

export async function loadPublicCompanyFixedPrices(env, scope, options = {}) {
  const loaded = await loadCompanyFixedPricesDocument(env, scope);
  return publicCompanyFixedPricesFromDocument(loaded.document, options);
}

export function mergeCompanyFixedPricesViewSave(storedRaw, incomingRaw, viewRaw = "all") {
  const stored = normalizeCompanyFixedPricesDocument(storedRaw);
  const incoming = incomingRaw && typeof incomingRaw === "object" && !Array.isArray(incomingRaw)
    ? incomingRaw
    : {};
  const view = text(viewRaw, 16).toLowerCase();
  const expected = text(
    incoming.expected_updated_at ?? incoming.base_updated_at,
    80,
  );
  if (expected && stored.updated_at && expected !== stored.updated_at) {
    return {
      ok: false,
      error: "stale_fixed_prices",
      status: 409,
      document: stored,
    };
  }
  const incomingRules = (Array.isArray(incoming.rules) ? incoming.rules : [])
    .map((rule, idx) => normalizeCompanyFixedPriceRule(rule, idx))
    .filter(Boolean);
  if (view !== "airport" && view !== "city") {
    return {
      ok: true,
      document: normalizeCompanyFixedPricesDocument({
        ...stored,
        ...incoming,
        rules: incomingRules,
      }),
    };
  }
  const incomingView = incomingRules.filter((rule) =>
    view === "airport"
      ? companyFixedPriceRuleIsAirportCatalog(rule)
      : !companyFixedPriceRuleIsAirportCatalog(rule),
  );
  const keptOther = stored.rules.filter((rule) =>
    view === "airport"
      ? !companyFixedPriceRuleIsAirportCatalog(rule)
      : companyFixedPriceRuleIsAirportCatalog(rule),
  );
  return {
    ok: true,
    document: normalizeCompanyFixedPricesDocument({
      ...stored,
      fallback: incoming.fallback || stored.fallback,
      rules: [...keptOther, ...incomingView],
    }),
  };
}

export function mergeLegacyAirportFixedFaresSave(storedRaw, incomingRaw) {
  const stored = normalizeCompanyFixedPricesDocument(storedRaw);
  const incoming = incomingRaw && typeof incomingRaw === "object" && !Array.isArray(incomingRaw)
    ? incomingRaw
    : {};
  const expected = text(
    incoming.expected_updated_at ?? incoming.base_updated_at,
    80,
  );
  if (expected && stored.updated_at && expected !== stored.updated_at) {
    return {
      ok: false,
      error: "stale_fixed_prices",
      status: 409,
      document: stored,
    };
  }
  const incomingRules = Array.isArray(incoming.rules) ? incoming.rules : [];
  const upserts = [];
  for (let i = 0; i < incomingRules.length; i += 1) {
    const rule = normalizeCompanyFixedPriceRule(incomingRules[i], i);
    if (!rule || !isCompanyAirportKindRule(rule)) continue;
    upserts.push(rule);
  }
  const upsertIds = new Set(upserts.map((rule) => rule.rule_id));
  const kept = stored.rules.filter((rule) => !upsertIds.has(rule.rule_id));
  const pending = Object.prototype.hasOwnProperty.call(incoming, "pending_price_conditions")
    ? incoming.pending_price_conditions
    : stored.pending_price_conditions;
  return {
    ok: true,
    document: normalizeCompanyFixedPricesDocument({
      ...stored,
      pending_price_conditions: pending,
      fallback: stored.fallback,
      rules: [...kept, ...upserts],
    }),
  };
}

export function evaluateCompanyFixedPriceWrite({
  live,
  quotedSnapshot,
  lockedQuotePrice = false,
} = {}) {
  if (lockedQuotePrice) {
    return {
      ok: true,
      apply: quotedSnapshot && typeof quotedSnapshot === "object" ? quotedSnapshot : null,
      reason: "locked_quote",
    };
  }
  const quotedTotal = Number(quotedSnapshot?.total_incl_vat);
  const hasQuoted =
    Number.isFinite(quotedTotal) &&
    !!text(quotedSnapshot?.fixed_fare_rule_id, 120);
  if (live?.matched && live.snapshot) {
    if (hasQuoted && companyFixedPriceTotalsDiffer(quotedTotal, live.snapshot.total_incl_vat)) {
      return { ok: false, error: "price_changed", snapshot: live.snapshot };
    }
    return { ok: true, apply: live.snapshot, reason: "live" };
  }
  if (hasQuoted) {
    return { ok: false, error: "price_changed", snapshot: live?.snapshot || null };
  }
  return { ok: true, apply: null, reason: "no_fixed_price" };
}

export async function loadCompanyFixedPricesDocument(env, scope) {
  const key = companyFixedPricesKey(scope);
  if (!key) {
    return { key: "", document: normalizeCompanyFixedPricesDocument({ rules: [] }) };
  }
  if (!env?.BOOKING_KV) {
    return { key, document: normalizeCompanyFixedPricesDocument({ rules: [] }) };
  }
  try {
    const raw = await env.BOOKING_KV.get(key, { type: "json" });
    return { key, document: normalizeCompanyFixedPricesDocument(raw || { rules: [] }) };
  } catch {
    return { key, document: normalizeCompanyFixedPricesDocument({ rules: [] }) };
  }
}

export async function saveCompanyFixedPricesDocument(env, scope, incoming) {
  const key = companyFixedPricesKey(scope);
  if (!key) return { ok: false, error: "missing_scope" };
  if (!env?.BOOKING_KV) return { ok: false, error: "missing_booking_kv" };
  const normalized = normalizeCompanyFixedPricesDocument(incoming);
  const updatedAt = new Date().toISOString();
  const out = { ...normalized, updated_at: updatedAt };
  await env.BOOKING_KV.put(
    key,
    JSON.stringify({
      version: 1,
      updated_at: updatedAt,
      airport_fixed_fares: out,
      company_fixed_prices: out,
    }),
  );
  return { ok: true, key, document: out };
}

export async function resolveCompanyFixedPrice(env, scope, payload, options = {}) {
  const loaded = await loadCompanyFixedPricesDocument(env, scope);
  const category = await resolveFixedVehicleCategory(env, scope, payload, loaded.document);
  if (!category.ok) return { matched:false,block_calculator:true,request_quote_required:true,pricing_source:'request_quote',reason:category.reason };
  const result = resolveCompanyFixedPriceFromDocument(loaded.document, payload, {...options,vehicleCategory:category.category});
  if (category.category && result.matched) {
    result.vehicle_pricing={category:category.category,vehicle_ids:category.vehicle_ids};
    result.snapshot.vehicle_pricing=result.vehicle_pricing;
  }
  if (category.category && !result.matched) Object.assign(result,{block_calculator:true,request_quote_required:true});
  if (!result.matched && !result.reason && !result.needs_more_detail?.length
      && await usesCompanyMissionTaxi(env, scope, payload)) {
    // A real matched fixed fare still wins. Only the catalog's generic
    // no-match fallback yields to this company's ordinary mission calculator.
    result.block_calculator = false;
    result.request_quote_required = false;
    result.pricing_source = 'route_calc';
  }
  return result;
}

export async function resolveReturnPackage(env, scope, payload, options = {}) {
  const loaded = await loadCompanyFixedPricesDocument(env, scope);
  const category = await resolveFixedVehicleCategory(env,scope,payload,loaded.document);
  if (!category.ok) return {matched:false,reason:category.reason};
  const result=resolveReturnPackageFromDocument(loaded.document,payload,{...options,vehicleCategory:category.category});
  if (category.category && result.matched) {result.vehicle_pricing={category:category.category,vehicle_ids:category.vehicle_ids};result.snapshot.vehicle_pricing=result.vehicle_pricing;}
  return result;
}

export function matchCompanyFixedPricesPath(pathname) {
  const path = String(pathname || "");
  if (path === "/company/fixed-prices") return { kind: "list" };
  if (path === "/company/fixed-prices/preview") return { kind: "preview" };
  if (path === "/company/fixed-prices/quote") return { kind: "quote" };
  return null;
}

export async function serveCompanyFixedPricesHttp({
  env,
  method,
  route,
  body,
  scope,
}) {
  if (!route) return json({ ok: false, error: "not_found" }, 404);
  if (route.kind === "list" && method === "GET") {
    const loaded = await loadCompanyFixedPricesDocument(env, scope);
    return json({ ok: true, company_fixed_prices: loaded.document }, 200);
  }
  if (route.kind === "list" && method === "POST") {
    const loaded = await loadCompanyFixedPricesDocument(env, scope);
    const incoming = body?.company_fixed_prices || body?.airport_fixed_fares || body || {};
    const merged = mergeCompanyFixedPricesViewSave(
      loaded.document,
      {
        ...(incoming && typeof incoming === "object" ? incoming : {}),
        expected_updated_at:
          body?.expected_updated_at ||
          incoming?.expected_updated_at ||
          incoming?.base_updated_at,
      },
      body?.view || incoming?.view || "all",
    );
    if (!merged.ok) {
      return json(
        {
          ok: false,
          error: merged.error,
          company_fixed_prices: merged.document,
        },
        merged.status || 409,
      );
    }
    const saved = await saveCompanyFixedPricesDocument(env, scope, merged.document);
    if (!saved.ok) return json({ ok: false, error: saved.error }, 400);
    return json({ ok: true, company_fixed_prices: saved.document }, 200);
  }
  if ((route.kind === "preview" || route.kind === "quote") && method === "POST") {
    const result = await resolveCompanyFixedPrice(env, scope, body || {}, {
      vatRate: body?.vat_rate,
      vatMode: body?.vat_mode,
      nowIso: body?.now_iso,
      fromCity: body?.from_city,
      toCity: body?.to_city,
      roadDistanceKm: body?.road_distance_km,
    });
    return json({ ok: true, ...result }, 200);
  }
  return json({ ok: false, error: "method_not_allowed" }, 405);
}

export function stampCompanyFixedPriceSnapshot(record, snapshot) {
  if (!record || !snapshot?.fixed_fare_rule_id) return record;
  record.pricing_source = snapshot.pricing_source;
  record.fixed_fare_rule_id = snapshot.fixed_fare_rule_id;
  record.fixed_fare_rule_version = snapshot.rule_version;
  record.fixed_price_snapshot = snapshot;
  if (record.booking && typeof record.booking === "object") {
    record.booking.pricing_source = snapshot.pricing_source;
    record.booking.fixed_fare_rule_id = snapshot.fixed_fare_rule_id;
    record.booking.fixed_price_snapshot = snapshot;
    if (snapshot.total_incl_vat != null) {
      record.booking.price_incl_vat = snapshot.total_incl_vat;
    }
  }
  if (snapshot.total_incl_vat != null) {
    record.price_incl_vat = snapshot.total_incl_vat;
  }
  return record;
}
