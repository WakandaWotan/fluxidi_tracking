// Company-configurable fixed prices on the existing airport_fixed_fares store.
// Airport rules stay compatible. City pairs and overflow are additive.

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
// "gentbrugge" does not hold "gent".
function localityHolds(tokens, needle) {
  const want = text(needle, 80).split(" ").filter(Boolean);
  if (want.length === 0) return false;
  for (const token of tokens) {
    const words = token.split(" ").filter(Boolean);
    for (let i = 0; i + want.length <= words.length; i += 1) {
      let hit = true;
      for (let j = 0; j < want.length; j += 1) {
        if (words[i + j] !== want[j]) {
          hit = false;
          break;
        }
      }
      if (hit) return true;
    }
  }
  return false;
}

// Only a postcode-led part counts ("9688", "9000 Gent"). A house number such
// as "Korenmarkt 1" or "Chaussée 1234" is not a postcode.
function postcodeFromPart(part) {
  const match = text(part, 240).trim().match(/^(\d{4,6})(?:\s|$)/);
  return match ? match[1] : "";
}

function collectPostcodes(explicitValues, labelValues) {
  const out = [];
  const push = (value) => {
    const code = normPostcode(value);
    if (code && !out.includes(code)) out.push(code);
  };
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

function normalizeDirection(raw, kind) {
  const value = text(raw?.direction, 24).toLowerCase();
  if (kind === "airport") {
    if (value === "to_airport" || value === "from_airport" || value === "both") return value;
    if (value === "one_way") return "to_airport";
    return "";
  }
  if (value === "both" || value === "both_ways") return "both";
  if (value === "one_way" || value === "to_airport" || value === "from_airport") return "one_way";
  return "one_way";
}

export function normalizeCompanyFixedPriceRule(raw, idx = 0) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
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
    price_covers: text(raw.price_covers ?? raw.priceCovers, 32) === "full_assignment"
      ? "full_assignment"
      : "ride",
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
    if (!localityHolds(tokens, place.value)) {
      return { matched: false, reason: "city_mismatch" };
    }
    return { matched: true, reason: "city", specificity: ZONE_RANK.city };
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
    if (!localityHolds(tokens, normCity(place.value || place.label))) {
      return { matched: false, reason: "zone_mismatch" };
    }
    return { matched: true, reason: "zone", specificity: ZONE_RANK.zone };
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
  return {
    matched: true,
    reason: swapped ? "city_pair_swapped" : "city_pair",
    specificity: Math.max(origin.specificity || 0, destination.specificity || 0),
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
  if (!winner?.rule) {
    const needsDetail = candidates
      .filter((row) => row.needs)
      .map((row) => ({ rule_id: row.rule_id, name: row.name, ...row.needs }));
    return {
      matched: false,
      fallback: doc.fallback,
      pricing_source: doc.fallback === "request_quote" ? "request_quote" : "route_calc",
      request_quote_required: doc.fallback === "request_quote",
      needs_more_detail: needsDetail,
      candidates,
      snapshot: null,
    };
  }
  const surchargeTotal = (winner.match.surcharges || []).reduce(
    (sum, item) => sum + Number(item.amount_incl_vat || 0),
    0,
  );
  const total = to2(winner.rule.price_incl_vat + surchargeTotal);
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
  return {
    ok: true,
    document: normalizeCompanyFixedPricesDocument({
      ...stored,
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
  return resolveCompanyFixedPriceFromDocument(loaded.document, payload, options);
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
