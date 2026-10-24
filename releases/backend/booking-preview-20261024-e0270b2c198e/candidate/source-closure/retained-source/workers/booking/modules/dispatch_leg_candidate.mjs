import { resolveBookingTrackingCoordinateFields } from './booking_leg_coordinates.mjs';

// A split leg is ranked as its own route. Parent ID remains the demand owner;
// neither suggestion creates a daily allocator reservation.
export function dispatchLegCandidateRecord(record, leg) {
  const returning = String(leg.leg_type || leg.legType).toLowerCase() === 'return';
  const coordinates = resolveBookingTrackingCoordinateFields({ payload: leg, fallbackSources: [leg] });
  const route = { from: leg.from, to: leg.to, pickup_iso: leg.pickup_iso || leg.pickupIso,
    ...(returning ? { pickup_mode: 'scheduled' } : {}),
    ...(record?.financial_evidence?.version === 2 ? { service_min: leg.service_min }
      : { duration_route_min: leg.duration_min || leg.durationMin, duration_min: leg.duration_min || leg.durationMin }),
    wait_min: 0, return_enabled: false, return_pickup_iso: null, return_duration_min: 0,
    roundtrip_dispatch_mode: 'single', roundtripDispatchMode: 'single',
    operational_legs: [], operationalLegs: [], stops: leg.stops || [], stop_coordinates:leg.stop_coordinates??(returning?record.p12_reliable_choice?.request_context?.return_stop_coordinates??record.payload?.return_stop_coordinates:record.p12_reliable_choice?.request_context?.stop_coordinates??record.payload?.stop_coordinates), ...coordinates };
  const copy = structuredClone(record);
  // Every alias must belong to this leg. Leaving an old pickup_lat beside a
  // new from_lat lets the allocator's alias precedence reuse the parent route.
  for (const source of [copy, copy.booking, copy.payload]) {
    if (!source || typeof source !== 'object') continue;
    for (const key of Object.keys(source)) {
      if (/^(from|pickup|to|dropoff|destination)(_?(lat|lng|lon)|Latitude|Longitude)$/i.test(key)
        || ['pickup', 'destination', 'dropoff'].includes(key)) delete source[key];
    }
  }
  return { ...copy, ...route, _reliable_leg_type:returning?'return':'outbound',
    ...(copy.p12_reliable_choice&&returning?{p12_reliable_choice:{...copy.p12_reliable_choice,...(copy.p12_reliable_choice.return_choice??{kind:'type',vehicle_id:copy.customer_requested_return_vehicle_id||'unresolved'}),journey:null}}:{}),
    customer_requested_vehicle_id: returning ? record.customer_requested_return_vehicle_id
      || record.limousine_accepted_price?.vehicle_id || record.quote?.limousine_accepted_price?.vehicle_id || ''
      : record.customer_requested_vehicle_id || record.limousine_accepted_price?.vehicle_id
        || record.quote?.limousine_accepted_price?.vehicle_id || '',
    booking: { ...copy.booking, ...route }, payload: { ...copy.payload, ...route } };
}
