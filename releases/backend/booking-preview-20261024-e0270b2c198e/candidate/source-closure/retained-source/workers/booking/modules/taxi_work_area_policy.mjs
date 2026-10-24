// A selected taxi company's published area is a commercial boundary at every
// discovery entry point. Airport customer-side semantics remain independent of
// the airport's own postcode; physical street rides/private services stay separate.
import { airportOutOfAreaMode, companyWorkAreaPostcode, companyWorkAreaPostcodes } from './airport_company_policy.mjs';
import { isPrivateChauffeurService } from './private_chauffeur_policy.mjs';
import { isLimousineServiceToken } from './limousine_provider_eligibility.mjs';

export function taxiOutsideWorkAreaMode(profile) {
  // Legacy settings inspection; calculator is not permission to price outside
  // a configured company area under the current public-taxi rule.
  return airportOutOfAreaMode(profile);
}

export function isTaxiWorkAreaRequest(payload) {
  const token = value => String(value ?? '').trim().toLowerCase();
  // Only top-level claims enter the actual private/limousine commercial gates.
  // Nested ride_options alone cannot exempt an ordinary passenger request.
  const services = [payload?.service_category, payload?.service]
    .map(token).filter(Boolean);
  const kind = token(payload?.booking_type ?? payload?.bookingType ?? payload?.trip_kind);
  const source = token(payload?.booking_source ?? payload?.bookingSource);
  if (['direct', 'direct_trip', 'street_hail', 'street_ride'].includes(kind) ||
      ['street_hail', 'street_ride'].includes(source)) return false;
  if (payload?.airport_iata || payload?.airportIata || kind === 'airport_transfer' || source === 'airport_module') return false;
  // Backend unknown service tokens normalize to passenger. A strict alias list
  // would let such tokens bypass the independent quote/create area guard.
  return services.every(service => !isPrivateChauffeurService(service) && !isLimousineServiceToken(service) && service !== 'airport');
}

export function isAirportWorkAreaRequest(payload) {
  const token = value => String(value ?? '').trim().toLowerCase();
  const services = [payload?.service_category, payload?.service].map(token).filter(Boolean);
  const kind = token(payload?.booking_type ?? payload?.bookingType ?? payload?.trip_kind);
  const source = token(payload?.booking_source ?? payload?.bookingSource);
  if (['direct', 'direct_trip', 'street_hail', 'street_ride'].includes(kind) ||
      ['street_hail', 'street_ride'].includes(source)) return false;
  if (services.some(service => isPrivateChauffeurService(service) || isLimousineServiceToken(service))) return false;
  return services.includes('airport') || kind === 'airport_transfer' || source === 'airport_module' ||
    !!(payload?.airport_iata || payload?.airportIata || payload?.airport_transfer?.airport_iata);
}

export function taxiWorkArea(profile, body, resolvedPickupPostcode = '') {
  const served = companyWorkAreaPostcodes(profile);
  const address = body?.from ?? body?.pickup ?? body?.pickup_address;
  // The actual selected address wins over a contradictory client-side hint.
  const pickup = companyWorkAreaPostcode(address) || companyWorkAreaPostcode(resolvedPickupPostcode) ||
    companyWorkAreaPostcode(body?.from_postcode ?? body?.pickup_postcode ?? body?.postcode);
  const configured = served.size > 0;
  const checked = configured && !!pickup;
  return {
    configured,
    checked,
    customer_postcode: pickup || null,
    inside: checked ? served.has(pickup) : null,
    outside: configured && (!checked || !served.has(pickup)),
  };
}

export function taxiWorkAreaContactResult(profile, area, { airport = false } = {}) {
  if (!area.configured || !area.outside) return null;
  return {
    ok: true,
    request_quote_required: true,
    reason: area.checked ? (airport ? 'airport_outside_work_area' : 'taxi_outside_work_area')
      : (airport ? 'airport_work_area_unverified' : 'taxi_work_area_unverified'),
    pricing_source: 'request_quote',
    customer_action: 'contact_company',
    price_label: 'Prijs op aanvraag',
    price_ex_vat: null,
    price_vat: null,
    price_incl_vat: null,
    total_price_ex_vat: null,
    total_price_vat: null,
    total_price_incl_vat: null,
    work_area: area,
  };
}
