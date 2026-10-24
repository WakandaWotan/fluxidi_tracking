// Privéchauffeur has its own company tariff; taxi pricing is independent.
// quote_required is the limousine manual-quote outcome (no invented price).
// calculator uses the separate hourly + kilometre tariff, with one extra floor:
// requested hire duration below the company minimum is billed at that minimum.

import { itineraryFingerprint } from "./limousine_manual_quote.mjs";

export const PRIVATE_CHAUFFEUR_SERVICE = "private_chauffeur";
export const PRIVATE_CHAUFFEUR_PRICING_QUOTE = "quote_required";
export const PRIVATE_CHAUFFEUR_PRICING_CALCULATOR = "calculator";
export const PRIVATE_CHAUFFEUR_OFFER_ID = "private_chauffeur";
export const PRIVATE_CHAUFFEUR_NOT_ONLINE_MESSAGE =
  "Dit bedrijf biedt Privéchauffeur nog niet online aan.";
export const PRIVATE_CHAUFFEUR_DURATION_MESSAGE =
  "Geef aan hoe lang je de privéchauffeur nodig hebt.";

const SERVICE_ALIASES = new Set([
  "private_chauffeur",
  "prive_chauffeur",
  "privechauffeur",
]);

function asObject(raw) {
  return raw && typeof raw === "object" && !Array.isArray(raw) ? raw : {};
}

function compactToken(value) {
  return String(value ?? "")
    .trim()
    .toLowerCase()
    .replace(/[\s-]+/g, "_");
}

function tokenList(value) {
  if (!Array.isArray(value)) return [];
  return value.map(compactToken).filter(Boolean);
}

function looksTrue(value) {
  if (value === true || value === 1) return true;
  const token = compactToken(value);
  return token === "true" || token === "1" || token === "yes" || token === "on";
}

function looksFalse(value) {
  if (value === false || value === 0) return true;
  const token = compactToken(value);
  return token === "false" || token === "0" || token === "no" || token === "off";
}

export function isPrivateChauffeurService(value) {
  return SERVICE_ALIASES.has(compactToken(value));
}

/// Explicit offer only. Taxi, airport and limousine tokens are not an offer.
export function partnerOffersPrivateChauffeur(record) {
  const src = asObject(record);
  const caps = asObject(src.booking_capabilities ?? src.bookingCapabilities);
  const capabilities = asObject(src.capabilities);
  const explicit = [
    src.private_chauffeur_enabled,
    src.privateChauffeurEnabled,
    caps.private_chauffeur,
    caps.privateChauffeur,
    capabilities.private_chauffeur,
  ];
  for (const value of explicit) {
    if (value != null && value !== "" && looksFalse(value)) return false;
  }
  for (const value of explicit) {
    if (looksTrue(value)) return true;
  }
  const lists = [
    ...tokenList(src.services),
    ...tokenList(src.publicServiceIds),
    ...tokenList(src.public_service_ids),
  ];
  return lists.some((token) => SERVICE_ALIASES.has(token));
}

export function normalizePrivateChauffeurPricingMode(source) {
  const src = asObject(source);
  const raw = compactToken(
    src.private_chauffeur_pricing_mode ?? src.privateChauffeurPricingMode ?? "",
  );
  if (
    raw === "quote_required" ||
    raw === "manual_quote" ||
    raw === "offerte" ||
    raw === "quote"
  ) {
    return PRIVATE_CHAUFFEUR_PRICING_QUOTE;
  }
  if (raw === "calculator" || raw === "hourly_km" || raw === "route_calc") {
    return PRIVATE_CHAUFFEUR_PRICING_CALCULATOR;
  }
  return "";
}

export function profileDeclaresPrivateChauffeurMinimumHours(source) {
  const src = asObject(source);
  return (
    Object.prototype.hasOwnProperty.call(src, "private_chauffeur_minimum_hours") ||
    Object.prototype.hasOwnProperty.call(src, "privateChauffeurMinimumHours")
  );
}

export function normalizePrivateChauffeurMinimumHours(source) {
  if (!profileDeclaresPrivateChauffeurMinimumHours(source)) return null;
  const src = asObject(source);
  const raw = src.private_chauffeur_minimum_hours ?? src.privateChauffeurMinimumHours;
  if (raw == null || raw === "") return null;
  const hours = Number(raw);
  if (!Number.isFinite(hours) || hours <= 0 || hours > 24) return null;
  return Math.round(hours * 100) / 100;
}

export function privateChauffeurMinimumHoursInvalid(source) {
  if (!profileDeclaresPrivateChauffeurMinimumHours(source)) return false;
  const src = asObject(source);
  const raw = src.private_chauffeur_minimum_hours ?? src.privateChauffeurMinimumHours;
  if (raw == null || raw === "") return false;
  const hours = Number(raw);
  return !Number.isFinite(hours) || hours <= 0 || hours > 24;
}

// Amounts are EUR excluding VAT. Missing fields are never inferred from the
// taxi pricing profile: calculator mode must fail closed until configured.
export function privateChauffeurTariff(source) {
  const src = asObject(source);
  const hour = Number(src.private_chauffeur_hourly_rate_ex_vat);
  const km = Number(src.private_chauffeur_km_rate_ex_vat);
  const vat = Number(src.private_chauffeur_vat_percent);
  const declared = [
    'private_chauffeur_hourly_rate_ex_vat',
    'private_chauffeur_km_rate_ex_vat',
    'private_chauffeur_vat_percent',
  ].every((field) => src[field] !== undefined && src[field] !== null && String(src[field]).trim() !== '');
  if (!declared || !Number.isFinite(hour) || hour <= 0 || hour > 10000 ||
      !Number.isFinite(km) || km < 0 || km > 1000 ||
      !Number.isFinite(vat) || vat < 0 || vat > 100) return null;
  return { hourlyRateExVat: hour, kmRateExVat: km, vatPercent: vat };
}

export function calculatePrivateChauffeurPrice(tariff, billableMinutes, distanceKm) {
  if (!tariff || !Number.isFinite(Number(billableMinutes)) || billableMinutes <= 0 ||
      !Number.isFinite(Number(distanceKm)) || distanceKm < 0) return null;
  const hourCents = Math.round(tariff.hourlyRateExVat * 100);
  const kmCents = Math.round(tariff.kmRateExVat * 100);
  const exCents = Math.round(hourCents * billableMinutes / 60 + kmCents * distanceKm);
  const vatCents = Math.round(exCents * tariff.vatPercent / 100);
  return {
    price_ex_vat: exCents / 100,
    price_vat: vatCents / 100,
    price_incl_vat: (exCents + vatCents) / 100,
    note: 'Privéchauffeur: uurprijs en kilometervergoeding exclusief btw.',
    breakdown: {
      kind: 'private_chauffeur_hourly_km',
      billable_duration_minutes: billableMinutes,
      distance_km: distanceKm,
      hourly_rate_ex_vat: tariff.hourlyRateExVat,
      km_rate_ex_vat: tariff.kmRateExVat,
      vat_rate: tariff.vatPercent / 100,
    },
  };
}

/// Planned hire time from the customer request. Route minutes are not a duration.
export function explicitPrivateChauffeurDuration(body) {
  const src = asObject(body);
  const minuteRaw = src.requested_duration_minutes ?? src.requestedDurationMinutes;
  const hourRaw = src.duration_hours ?? src.durationHours ?? src.planned_hours ?? src.plannedHours;
  const hasMinutes = minuteRaw != null && String(minuteRaw).trim() !== "";
  const hasHours = hourRaw != null && String(hourRaw).trim() !== "";
  if (!hasMinutes && !hasHours) {
    return { present: false, valid: false, minutes: 0 };
  }
  let minutes = 0;
  if (hasMinutes) {
    const explicit = Number(minuteRaw);
    if (!Number.isFinite(explicit)) return { present: true, valid: false, minutes: 0 };
    minutes = Math.trunc(explicit);
  } else {
    const hours = Number(hourRaw);
    if (!Number.isFinite(hours)) return { present: true, valid: false, minutes: 0 };
    minutes = Math.round(hours * 60);
  }
  const valid = minutes > 0 && minutes <= 24 * 60;
  return { present: true, valid, minutes: valid ? minutes : 0 };
}

export function requestedPrivateChauffeurMinutes(body, routeMinutes = null) {
  const explicit = explicitPrivateChauffeurDuration(body);
  if (explicit.present) return explicit.valid ? explicit.minutes : 0;
  const route = Number(routeMinutes);
  if (Number.isFinite(route) && route >= 0) return Math.trunc(route);
  return 0;
}

/// Existing calculator time input. A shorter request is raised to the minimum.
export function billablePrivateChauffeurMinutes(requestedMinutes, minimumHours) {
  const requested = Number.isFinite(Number(requestedMinutes))
    ? Math.max(0, Math.trunc(Number(requestedMinutes)))
    : 0;
  const minimum = Number(minimumHours);
  if (!Number.isFinite(minimum) || minimum <= 0) return requested;
  return Math.max(requested, Math.round(minimum * 60));
}

/// Same customer outcome as a limousine quote_required offer: no euro amount.
export function privateChauffeurManualQuote(body) {
  return {
    ok: true,
    service: PRIVATE_CHAUFFEUR_SERVICE,
    service_category: PRIVATE_CHAUFFEUR_SERVICE,
    manual_quote_required: true,
    request_quote_required: true,
    pricing_source: "manual_quote",
    reason: "manual_quote",
    price_ex_vat: null,
    price_vat: null,
    price_incl_vat: null,
    total_price_incl_vat: null,
    requested_duration_minutes: requestedPrivateChauffeurMinutes(body, null),
  };
}

/// `null` means this is not the private-chauffeur filter, so taxi, airport
/// and limousine discovery keep their existing selection.
export function privateChauffeurNearbyMatch(serviceFilter, profile, signals = null) {
  if (serviceFilter !== PRIVATE_CHAUFFEUR_SERVICE) return null;
  return (
    partnerOffersPrivateChauffeur(profile) ||
    partnerOffersPrivateChauffeur(signals)
  );
}

export function isPrivateChauffeurQuoteRecord(record) {
  const request = asObject(asObject(record).request);
  return isPrivateChauffeurService(request.service_type || request.service);
}

function textField(source, keys, max) {
  const src = asObject(source);
  for (const key of keys) {
    const text = String(src[key] ?? "").trim();
    if (text) return text.slice(0, max);
  }
  return "";
}

function clientSentPrice(body) {
  const src = asObject(body);
  for (const key of [
    "price",
    "price_incl_vat",
    "priceInclVat",
    "total_price_incl_vat",
    "total_incl_vat_cents",
    "totalInclVatCents",
    "amount_cents",
  ]) {
    if (src[key] != null && String(src[key]).trim() !== "") return true;
  }
  return false;
}

/// Inbox request for quote_required. No limousine offer, vehicle or price.
export function validatePrivateChauffeurQuoteSubmission(profile, body) {
  const offered = partnerOffersPrivateChauffeur(profile);
  const mode = normalizePrivateChauffeurPricingMode(profile);
  if (!offered || !mode || privateChauffeurMinimumHoursInvalid(profile)) {
    return {
      ok: false,
      status: 422,
      error: !offered
        ? "private_chauffeur_not_offered"
        : privateChauffeurMinimumHoursInvalid(profile)
          ? "private_chauffeur_minimum_hours_invalid"
          : "private_chauffeur_pricing_mode_missing",
      customer_message: PRIVATE_CHAUFFEUR_NOT_ONLINE_MESSAGE,
      service: PRIVATE_CHAUFFEUR_SERVICE,
    };
  }
  if (mode !== PRIVATE_CHAUFFEUR_PRICING_QUOTE) {
    return {
      ok: false,
      status: 422,
      error: "private_chauffeur_not_quote_mode",
      service: PRIVATE_CHAUFFEUR_SERVICE,
    };
  }
  if (clientSentPrice(body)) {
    return {
      ok: false,
      status: 400,
      error: "client_price_rejected",
      service: PRIVATE_CHAUFFEUR_SERVICE,
    };
  }
  const duration = explicitPrivateChauffeurDuration(body);
  if (!duration.valid) {
    return {
      ok: false,
      status: 422,
      error: "private_chauffeur_duration_required",
      customer_message: PRIVATE_CHAUFFEUR_DURATION_MESSAGE,
      service: PRIVATE_CHAUFFEUR_SERVICE,
    };
  }
  const from = textField(body, ["from"], 240);
  const to = textField(body, ["to"], 240);
  if (!from || !to) {
    return {
      ok: false,
      status: 422,
      error: "private_chauffeur_route_required",
      service: PRIVATE_CHAUFFEUR_SERVICE,
    };
  }
  const scheduled = textField(body, ["scheduled_pickup_iso", "scheduledPickupIso", "pickup_iso"], 40);
  const date = textField(body, ["date"], 40);
  const time = textField(body, ["time"], 16);
  if (!scheduled && !(date && time)) {
    return {
      ok: false,
      status: 422,
      error: "private_chauffeur_schedule_required",
      service: PRIVATE_CHAUFFEUR_SERVICE,
    };
  }
  const request = {
    offer_id: PRIVATE_CHAUFFEUR_OFFER_ID,
    vehicle_id: "",
    journey_type: "point_to_point",
    service_type: PRIVATE_CHAUFFEUR_SERVICE,
    service: PRIVATE_CHAUFFEUR_SERVICE,
    pricing_mode: PRIVATE_CHAUFFEUR_PRICING_QUOTE,
    intent_kind: "quote_request",
    from,
    to,
    date,
    time,
    scheduled_pickup_iso: scheduled,
    requested_duration_minutes: duration.minutes,
    customer_note: textField(body, ["customer_note", "customerNote", "note"], 500),
    pax: 1,
    bags: 0,
    selected_extra_ids: [],
    locale: textField(body, ["locale"], 8) || "nl",
    public_partner_id: textField(body, ["public_partner_id", "publicPartnerId"], 120),
    // Keep the picked route coordinates so an accepted quote can still give
    // customer tracking a destination, a route and an ETA. Text addresses alone
    // can never produce those.
    ...privateChauffeurRequestCoordinates(body),
  };
  return { ok: true, request };
}

// A company may send a manually priced offer to its own customer even when
// public requests use calculator mode. It still needs an enabled service and
// a real itinerary; no limousine offer or vehicle is borrowed.
export function validatePrivateChauffeurExternalRequest(profile, body) {
  if (!partnerOffersPrivateChauffeur(profile)) {
    return { ok: false, reason: 'private_chauffeur_not_offered', field: 'service_type' };
  }
  const validated = validatePrivateChauffeurQuoteSubmission({
    ...asObject(profile),
    private_chauffeur_pricing_mode: PRIVATE_CHAUFFEUR_PRICING_QUOTE,
  }, body);
  if (!validated.ok) return { ok: false, reason: validated.error, field: 'request' };
  const pax = Number(body?.pax);
  const bags = Number(body?.bags);
  if (!Number.isInteger(pax) || pax < 1 || pax > 16) return { ok: false, reason: 'invalid_pax', field: 'pax' };
  if (!Number.isInteger(bags) || bags < 0 || bags > 99) return { ok: false, reason: 'invalid_bags', field: 'bags' };
  const stops = Array.isArray(body?.stops) ? body.stops : [];
  if (stops.length > 8 || stops.some((stop) => typeof stop !== 'string' || !stop.trim() || stop.length > 240)) {
    return { ok: false, reason: 'invalid_stops', field: 'stops' };
  }
  const request = sealPrivateChauffeurQuoteRequest({
    ...validated.request,
    pax,
    bags,
    stops: stops.map((stop) => stop.trim()),
  });
  return { ok: true, request, snapshot: null };
}

function coordinateValue(raw, limit) {
  if (raw === null || raw === undefined || typeof raw === "boolean") return null;
  const text = String(raw).trim();
  if (!text) return null;
  const num = Number(text);
  if (!Number.isFinite(num) || Math.abs(num) > limit) return null;
  return num;
}

function coordinatePair(source, latKeys, lngKeys) {
  for (let i = 0; i < latKeys.length; i += 1) {
    const lat = coordinateValue(source?.[latKeys[i]], 90);
    const lng = coordinateValue(source?.[lngKeys[i]], 180);
    if (lat === null || lng === null) continue;
    if (lat === 0 && lng === 0) continue;
    return { lat, lng };
  }
  return null;
}

/// Validated route coordinates from a quote-request body. A textual, partial or
/// out-of-range value is dropped instead of stored.
export function privateChauffeurRequestCoordinates(body) {
  const src = asObject(body);
  const pickup = coordinatePair(
    src,
    ["from_lat", "fromLat", "pickup_lat", "pickupLat"],
    ["from_lng", "fromLng", "pickup_lng", "pickupLng"],
  );
  const destination = coordinatePair(
    src,
    ["to_lat", "toLat", "dropoff_lat", "dropoffLat", "destination_lat", "destinationLat"],
    ["to_lng", "toLng", "dropoff_lng", "dropoffLng", "destination_lng", "destinationLng"],
  );
  return {
    ...(pickup ? { from_lat: pickup.lat, from_lng: pickup.lng } : {}),
    ...(destination ? { to_lat: destination.lat, to_lng: destination.lng } : {}),
  };
}

export function sealPrivateChauffeurQuoteRequest(request) {
  const next = { ...asObject(request) };
  next.itinerary_fingerprint = itineraryFingerprint(next);
  return next;
}

export function resolvePrivateChauffeurCommercial(profile, body, _routeMinutes = null) {
  const offered = partnerOffersPrivateChauffeur(profile);
  const mode = normalizePrivateChauffeurPricingMode(profile);
  const minimumHoursInvalid = privateChauffeurMinimumHoursInvalid(profile);
  const minimumHours = normalizePrivateChauffeurMinimumHours(profile);
  const tariff = privateChauffeurTariff(profile);
  const duration = explicitPrivateChauffeurDuration(body);
  const configurationMissing = !offered || !mode || minimumHoursInvalid;
  return {
    offered,
    mode,
    minimumHours,
    minimumHoursInvalid,
    tariff,
    tariffMissing: mode === PRIVATE_CHAUFFEUR_PRICING_CALCULATOR && tariff === null,
    durationValid: duration.valid,
    requestedMinutes: duration.minutes,
    billableMinutes: duration.valid
      ? billablePrivateChauffeurMinutes(duration.minutes, minimumHours)
      : 0,
    configurationMissing,
    customerMessage: configurationMissing ? PRIVATE_CHAUFFEUR_NOT_ONLINE_MESSAGE : "",
    manualQuote: privateChauffeurManualQuote(body),
  };
}
