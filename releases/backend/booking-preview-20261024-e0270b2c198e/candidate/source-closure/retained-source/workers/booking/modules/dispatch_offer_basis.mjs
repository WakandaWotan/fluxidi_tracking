// A payment receipt or note must not invalidate delivery. Route, timing,
// passenger requirements and sealed vehicle choices must require a new offer.
const routeKeys = new Set(['from', 'to', 'pickup', 'destination', 'pickup_iso', 'pickupIso', 'pickupStartIso',
  'pickup_mode', 'asap_requested_at', 'asap_search_expires_at',
  'return_from', 'return_to', 'return_pickup_iso', 'returnPickupIso', 'return_enabled', 'returnEnabled',
  'hasReturnSchedule', 'duration_route_min', 'durationRouteMin', 'duration_min', 'durationMin', 'return_duration_min', 'returnDurationMin',
  'wait_min', 'waitMin', 'occupancy_wait_min', 'occupancyWaitMin', 'roundtrip_dispatch_mode', 'roundtripDispatchMode', 'service_min',
  'tier', 'pax', 'bags', 'stops', 'stop_count', 'service', 'leg_id', 'legId', 'leg_type', 'legType',
  'customer_requested_vehicle_id', 'customerRequestedVehicleId', 'customer_requested_return_vehicle_id', 'customerRequestedReturnVehicleId',
  'p12_reliable_choice', 'returnFrom', 'returnTo', 'dropoff', 'operational_leg', 'operationalLeg']);
const sorted = value => Array.isArray(value) ? value.map(sorted) : value && typeof value === 'object'
  ? Object.fromEntries(Object.keys(value).sort().map(key => [key, sorted(value[key])])) : value;
function route(source) {
  return Object.fromEntries(Object.entries(source || {}).filter(([key]) => routeKeys.has(key)
    || /^(return_?)?(from|pickup|to|dropoff|destination)(_?(lat|lng|lon)|Latitude|Longitude)$/i.test(key)));
}
export async function dispatchOfferBasis(record) {
  const value = { root: route(record), booking: route(record.booking), payload: route(record.payload),
    quote: route(record.quote), return_quote: route(record.quote?.return),
    legs: (record.operational_legs || record.operationalLegs || record.booking?.operational_legs || record.booking?.operationalLegs || []).map(route),
    accepted_vehicle: record.quote?.limousine_accepted_price?.vehicle_id || record.limousine_accepted_price?.vehicle_id || '' };
  const bytes = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(JSON.stringify(sorted(value))));
  return Array.from(new Uint8Array(bytes), byte => byte.toString(16).padStart(2, '0')).join('');
}
