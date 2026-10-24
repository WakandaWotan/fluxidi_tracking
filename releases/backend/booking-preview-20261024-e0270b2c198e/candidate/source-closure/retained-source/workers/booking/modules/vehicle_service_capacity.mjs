function positiveInt(value) {
  const n = Number(value);
  if (!Number.isFinite(n) || n < 0) return null;
  return Math.floor(n);
}

export function normalizeServiceKind(service) {
  const text = String(service || "").trim().toLowerCase();
  if (text === "airport" || text === "luchthaven" || text === "airport_transfer") return "airport";
  return "taxi";
}

export function readServiceCapacityBlock(vehicle) {
  const raw = vehicle?.service_capacity ?? vehicle?.serviceCapacity;
  if (!raw || typeof raw !== "object") return null;
  const taxi = raw.taxi && typeof raw.taxi === "object" ? raw.taxi : null;
  const airport = raw.airport && typeof raw.airport === "object" ? raw.airport : null;
  if (!taxi && !airport) return null;
  const block = (row) => {
    if (!row) return null;
    const passengers = positiveInt(row.passengers ?? row.passenger_capacity ?? row.passengerCapacity);
    const baggage = positiveInt(row.baggage ?? row.luggage ?? row.luggage_capacity ?? row.luggageCapacity);
    if (passengers == null && baggage == null) return null;
    return {
      ...(passengers != null ? { passengers } : {}),
      ...(baggage != null ? { baggage } : {}),
    };
  };
  const taxiBlock = block(taxi);
  const airportBlock = block(airport);
  if (!taxiBlock && !airportBlock) return null;
  return {
    ...(taxiBlock ? { taxi: taxiBlock } : {}),
    ...(airportBlock ? { airport: airportBlock } : {}),
  };
}

export function resolveVehicleServiceCapacity(vehicle, service) {
  const kind = normalizeServiceKind(service);
  const stored = readServiceCapacityBlock(vehicle);
  const specific = stored?.[kind] || null;
  const passengers = specific?.passengers ?? positiveInt(vehicle?.passenger_capacity ?? vehicle?.passengerCapacity);
  const baggage = specific?.baggage ?? positiveInt(vehicle?.luggage_capacity ?? vehicle?.luggageCapacity);
  return { service: kind, passengers, baggage };
}

export function vehicleFitsServiceCapacity(vehicle, { service = "taxi", passengers = null, baggage = null } = {}) {
  const cap = resolveVehicleServiceCapacity(vehicle, service);
  const reqPax = positiveInt(passengers);
  const reqBags = positiveInt(baggage);
  if (reqPax != null && cap.passengers != null && reqPax > cap.passengers) return false;
  if (cap.service === "airport" && reqBags != null && cap.baggage != null && reqBags > cap.baggage) return false;
  return true;
}
