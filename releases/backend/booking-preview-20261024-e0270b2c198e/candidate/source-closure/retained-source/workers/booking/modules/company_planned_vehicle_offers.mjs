import { usesCompanyVehicleDuty } from './company_vehicle_operation_selection.mjs';
import { fleetVehicleId, fleetPassengerSeats } from './fleet_roster_availability.mjs';
import { resolveVehicleServiceCapacity } from './vehicle_service_capacity.mjs';
import { ASSIGNMENT_SAFETY_MARGIN_MIN } from './company_dispatch.mjs';
import { checkAssignmentOverlap } from './company_agenda.mjs';

// Future manager-reviewed requests select a vehicle preference, not a driver
// or a promise that a currently online car has accepted the ride.
export async function companyPlannedVehicleOffers(env, scope, input, {
  loadProfile, checkOverlap = checkAssignmentOverlap, nowMs = Date.now(),
} = {}) {
  if (input.asap === true || !Number.isFinite(input.pickupMs)
      || input.pickupMs <= nowMs) return null;
  const context = input.context ?? {};
  if (!await usesCompanyVehicleDuty(env, scope, context, loadProfile)
      || context.vehicleDutyProfile?.operating_policy?.scheduled_dispatch !== 'manager_first') return null;
  if (!Number.isFinite(input.durationMin) || input.durationMin <= 0) {
    throw new Error('assignment_availability_unknown');
  }
  const evaluations = [];
  const seen = new Set();
  for (const vehicle of input.vehicles ?? []) {
    const vehicleId = fleetVehicleId(vehicle);
    if (!vehicleId || seen.has(vehicleId) || vehicle.is_active !== true) continue;
    seen.add(vehicleId);
    const seats = fleetPassengerSeats(vehicle);
    const capacity = resolveVehicleServiceCapacity(vehicle, input.service);
    const row = { vehicle_id: vehicleId, passenger_seats: seats,
      driver_id: '', available: false, reason: '', assignment_deferred: true };
    if (seats == null || seats <= 0 || input.pax > seats
        || capacity.passengers != null && input.pax > capacity.passengers
        || capacity.baggage != null && input.bags > capacity.baggage) {
      evaluations.push(async () => ({ ...row, reason: 'assignment_capacity' }));
      continue;
    }
    // Includes durable Room claims before their KV vehicle index catches up.
    // Unknown active ends must remain blocked even for a future preference.
    const marginMs = ASSIGNMENT_SAFETY_MARGIN_MIN * 60000;
    const endMs = input.pickupMs + (input.durationMin + (input.waitMin || 0)
      + (input.returnDurationMin || 0)) * 60000;
    const occupied = (input.demandItems ?? []).find(demand =>
      demand.assigned_vehicle_id === vehicleId
      && (!Number.isFinite(demand.pickupMs) || !Number.isFinite(demand.serviceMin)
        || demand.occupancyEndUnknown === true && endMs + marginMs > demand.pickupMs
        || input.pickupMs - marginMs < demand.pickupMs + demand.serviceMin * 60000
          && demand.pickupMs < endMs + marginMs));
    if (occupied) {
      evaluations.push(async () => ({ ...row, reason: occupied.occupancyEndUnknown
        ? 'active_ride_end_unknown' : 'assignment_vehicle_busy' }));
      continue;
    }
    evaluations.push(async () => {
      const overlap = await checkOverlap(env, {
        scope, vehicleId, driverId: '',
        pickupIso: new Date(input.pickupMs).toISOString(),
        durationMin: input.durationMin,
        returnPickupIso: input.returnPickupIso ?? '',
        returnDurationMin: input.returnDurationMin || null,
        roundtripMode: input.waitMin > 0 && input.returnDurationMin > 0
          ? 'continuous_wait' : 'single',
        companyLiveSnapshot: input.liveSnapshot,
      });
      return { ...row, available: overlap.ok === true,
        reason: overlap.ok === true ? '' : overlap.error || 'assignment_availability_unknown' };
    });
  }
  const offers = [];
  // Without the already-read Room snapshot, checkAssignmentOverlap may fetch
  // /live itself. Keep that fallback serial to avoid simultaneous Room reads.
  const batchSize = input.liveSnapshot ? 10 : 1;
  for (let offset = 0; offset < evaluations.length; offset += batchSize) {
    offers.push(...await Promise.all(evaluations.slice(offset, offset + batchSize).map(evaluate => evaluate())));
  }
  return offers;
}
