// Seat capacity is separate from the fare. The requested passenger count is
// never lowered to fit a smaller vehicle.

function positiveInt(value) {
  const n = Number(value);
  if (!Number.isFinite(n)) return 0;
  return Math.max(0, Math.trunc(n));
}

export function assessPassengerSeatCapacity(vehicles, requestedPax) {
  const requested = positiveInt(requestedPax);
  const real = (Array.isArray(vehicles) ? vehicles : []).filter((vehicle) => {
    if (!vehicle || typeof vehicle !== "object") return false;
    if (vehicle.is_active === false) return false;
    const id = String(vehicle.vehicle_id ?? vehicle.vehicleId ?? "").trim();
    return id !== "default_company_vehicle";
  });
  const capacities = real
    .map((vehicle) => positiveInt(
      vehicle.passenger_capacity ?? vehicle.passengerCapacity ?? vehicle.pax,
    ))
    .filter((capacity) => capacity > 0);
  if (capacities.length === 0) {
    return {
      checked: false,
      exceeded: false,
      requested_pax: requested,
      passenger_count_adjusted: false,
      max_passenger_capacity: null,
      fitting_vehicle_count: null,
      message: null,
    };
  }
  const max = Math.max(...capacities);
  const fitting = capacities.filter((capacity) => capacity >= requested).length;
  if (requested > 0 && fitting === 0) {
    return {
      checked: true,
      exceeded: true,
      requested_pax: requested,
      passenger_count_adjusted: false,
      max_passenger_capacity: max,
      fitting_vehicle_count: 0,
      message: `Geen voertuig met ${requested} passagiersplaatsen. Het grootste voertuig heeft er ${max}. Het opgegeven aantal blijft ${requested}.`,
    };
  }
  return {
    checked: true,
    exceeded: false,
    requested_pax: requested,
    passenger_count_adjusted: false,
    max_passenger_capacity: max,
    fitting_vehicle_count: fitting,
    message: null,
  };
}
