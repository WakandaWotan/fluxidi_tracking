// A running ride never becomes free merely because its original estimate expired.
// Forecasts are request-local: fresh GPS + road routing, never persisted as completion.
import { normalizeRemainingItinerary } from './operational_itinerary.mjs';
function point(value) {
  const lat = value?.lat ?? value?.latitude;
  const lng = value?.lng ?? value?.longitude;
  if (lat == null || lng == null || String(lat).trim() === "" || String(lng).trim() === "") return null;
  const latitude = Number(lat), longitude = Number(lng);
  return Number.isFinite(latitude) && Number.isFinite(longitude)
    && Math.abs(latitude) <= 90 && Math.abs(longitude) <= 180
    ? { lat: latitude, lng: longitude } : null;
}

export async function forecastActiveDemand({ items = [], snapshot, scope, nowMs = Date.now(), route, maxRouteCalls = 64 }) {
  const readyByDriver = new Map();
  let routeCalls = 0;
  const forecast = async demand => {
    if (!demand.activeRide || demand.occupancyEndUnknown) return demand;
    const unknown = (details = {}) => ({ ...demand, occupancyEndUnknown: true, forecastReason: "active_ride_end_unknown", ...details });
    const itinerary = normalizeRemainingItinerary(demand.operationalRoute);
    if (!itinerary.ok || demand.activeRouteComplex && !itinerary.declared) return unknown();
    if (snapshot?.tenant_id !== scope?.tenant_id || snapshot?.company_id !== scope?.company_id) return unknown();
    const driverId = demand.assigned_driver_id;
    const row = (snapshot.drivers || []).find(row => row.driver_id === driverId
      && row.company_id === scope.company_id && row.vehicle_id === demand.assigned_vehicle_id);
    const capturedMs = Date.parse(row?.position_captured_at || row?.captured_at || "");
    const operational = demand.operationalRoute;
    const operationalEnd = operational ? Date.parse(operational.expected_end_iso || '') : 0;
    if (operational && (!point(operational.destination) || !Number.isFinite(operationalEnd))) return unknown();
    const origin = point(row), destination = point(operational?.destination || demand.dropoffPoint);
    if (!driverId || !origin || !destination || row?.location_feed !== "live" || row?.reliable_for_eta !== true
      || !Number.isFinite(capturedMs) || nowMs - capturedMs > 180000 || capturedMs > nowMs + 120000) return unknown();
    // A sample bound to another trip cannot predict this trip's completion.
    if (row.tracking_context) {
      const context = row.tracking_context;
      const matching = demand.parent_booking_id
        ? context.booking_id === demand.parent_booking_id && context.operational_leg === demand.leg_id
        : context.booking_id === demand.booking_id;
      if (context.phase !== 'in_progress' || !matching
        || operational?.operational_leg && operational.operational_leg !== context.operational_leg) return unknown();
    }
    const points = [...itinerary.stops, destination];
    if (routeCalls + points.length > maxRouteCalls) return unknown({ forecastReason: 'active_route_budget_exhausted' });
    routeCalls += points.length;
    let at = nowMs, from = origin;
    for (const stop of points) {
      let travel;
      try { travel = await route(from, point(stop), { depart_at: new Date(at).toISOString() }); }
      catch (_) { return unknown({ forecastRouteUnavailable: true }); }
      const seconds = travel?.travel_seconds;
      if (!travel?.ok || seconds == null || !Number.isFinite(Number(seconds)) || Number(seconds) < 0)
        return unknown({ forecastRouteUnavailable: true });
      at += Number(seconds) * 1000;
      // Return departure can be scheduled; arriving early never shortens its wait.
      at = Math.max(at, Date.parse(stop.not_before_iso || '') || 0) + (stop.wait_seconds || 0) * 1000;
      from = point(stop);
    }
    const handling = itinerary.declared ? Math.max(0, Number(demand.postHandlingSeconds) || 0, Number(operational?.remaining_handling_seconds) || 0)
      : Math.max(0, Number(demand.remainingHandlingSeconds) || 0, Number(operational?.remaining_handling_seconds) || 0);
    const readyAtMs = Math.max(demand.pickupMs + demand.serviceMin * 60000, operationalEnd,
      at + handling * 1000);
    return { ...demand, serviceMin: Math.max(1, (readyAtMs - demand.pickupMs) / 60000),
      dropoffPoint: operational ? { ...destination, address: operational.destination.address } : demand.dropoffPoint,
      dropoffAtMs: readyAtMs, forecastReadyAtMs: readyAtMs, forecastCapturedMs: capturedMs,
      forecastReason: "active_ride_live_forecast" };
  };
  // Bound simultaneous routing calls; preserve original demand order.
  const forecasts = new Array(items.length);
  let cursor = 0;
  await Promise.all(Array.from({ length: Math.min(4, items.length) }, async () => {
    while (cursor < items.length) {
      const index = cursor++;
      forecasts[index] = await forecast(items[index]);
    }
  }));
  // Multiple active rides for one person are inconsistent; never pick one silently.
  const activeByDriver = new Map();
  for (const demand of forecasts.filter(d => d.activeRide)) {
    const rows = activeByDriver.get(demand.assigned_driver_id) || [];
    rows.push(demand); activeByDriver.set(demand.assigned_driver_id, rows);
  }
  for (const [driverId, rows] of activeByDriver) {
    if (driverId && rows.length === 1 && Number.isFinite(rows[0].forecastReadyAtMs)) {
      readyByDriver.set(driverId, rows[0].forecastReadyAtMs);
    } else {
      for (const row of rows) { row.occupancyEndUnknown = true; delete row.forecastReadyAtMs; }
    }
  }
  return { items: forecasts, readyByDriver };
}
