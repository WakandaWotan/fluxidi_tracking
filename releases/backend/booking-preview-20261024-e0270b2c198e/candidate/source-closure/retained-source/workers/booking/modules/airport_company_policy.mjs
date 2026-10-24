// Company-scoped policy for newly scheduled airport bookings. A missing choice
// preserves the existing dispatch/pricing behavior, except Taxi Mario's
// explicitly identified company, whose new airport bookings go to its planner.
const TAXI_MARIO_COMPANY_ID = "cmp_taxi-mario_4b6d297325";

export function airportDispatchMode(profile, scope) {
  const chosen = profile?.airport_scheduled_dispatch_mode ?? profile?.airportScheduledDispatchMode;
  if (chosen === "manager_first" || chosen === "auto_available") return chosen;
  return scope?.company_id === TAXI_MARIO_COMPANY_ID &&
      scope?.tenant_id === TAXI_MARIO_COMPANY_ID
    ? "manager_first"
    : "existing";
}

export function airportOutOfAreaMode(profile) {
  const chosen = profile?.airport_out_of_area_mode ?? profile?.airportOutOfAreaMode;
  return chosen === "request_quote" ? "request_quote" : "calculator";
}

export function isNewScheduledAirportRide(payload, pickupIso, nowMs = Date.now()) {
  const service = String(payload?.service ?? payload?.service_type ?? "").trim().toLowerCase();
  const type = String(payload?.booking_type ?? payload?.bookingType ?? "").trim().toLowerCase();
  const source = String(payload?.booking_source ?? payload?.bookingSource ?? "").trim().toLowerCase();
  const airport = service === "airport" || type === "airport_transfer" || source === "airport_module";
  const pickupMs = Date.parse(pickupIso);
  return airport && Number.isFinite(pickupMs) && pickupMs > nowMs;
}

export function companyWorkAreaPostcode(value) {
  for (const part of String(value ?? '').split(',')) {
    const match = part.trim().match(/^([1-9]\d{3})(?:\s*([A-Za-z]{2}))?(?=\s|$)/);
    if (match) return `${match[1]}${match[2] ?? ''}`.toUpperCase();
  }
  return '';
}

export function companyWorkAreaPostcodes(profile) {
  const raw = profile?.publicServedPostcodes ?? profile?.public_served_postcodes ?? '';
  const list = Array.isArray(raw) ? raw : (String(raw).match(/\b[1-9]\d{3}(?:\s*[A-Za-z]{2}\b)?\b/g) ?? []);
  return new Set(list.map(companyWorkAreaPostcode).filter(Boolean));
}

export function airportWorkArea(profile, body, resolvedCustomerPostcode = "") {
  const served = companyWorkAreaPostcodes(profile);
  // The selected endpoint wins over a stale profile/client postcode hint.
  const from = companyWorkAreaPostcode(body?.from ?? body?.pickup ?? body?.pickup_address) ||
    companyWorkAreaPostcode(body?.from_postcode ?? body?.pickup_postcode);
  const to = companyWorkAreaPostcode(body?.to ?? body?.dropoff ?? body?.destination) ||
    companyWorkAreaPostcode(body?.to_postcode ?? body?.destination_postcode);
  const direction = String(body?.airport_direction ?? body?.airportDirection ??
    body?.ride_options?.airport_direction ?? body?.airport_transfer?.airport_direction ?? '').trim().toLowerCase();
  const customerPostcode = direction === "from_airport"
    ? (to || companyWorkAreaPostcode(resolvedCustomerPostcode) || companyWorkAreaPostcode(body?.postcode))
    : direction === "to_airport"
      ? (from || companyWorkAreaPostcode(resolvedCustomerPostcode) || companyWorkAreaPostcode(body?.postcode))
      : "";
  const checked = served.size > 0 && !!customerPostcode;
  return {
    configured: served.size > 0,
    checked,
    // The airport itself need not be in the company's work area. Only the
    // customer's pickup/dropoff side decides the out-of-area policy.
    outside: !checked || !served.has(customerPostcode),
    inside: checked ? served.has(customerPostcode) : null,
    from_postcode: from || null,
    to_postcode: to || null,
    customer_postcode: customerPostcode || null,
  };
}
