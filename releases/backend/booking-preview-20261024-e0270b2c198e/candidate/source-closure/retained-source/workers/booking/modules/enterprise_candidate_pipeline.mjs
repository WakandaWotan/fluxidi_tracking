// Distance changes evaluation order only. All remaining eligible candidates
// are expanded, because no geographic radius or road-time lower bound is a
// business rule. Exact road ETA and original fleet order decide the winner.
export function candidateBatches(vehicles, positions, pickup, initial = 5) {
  const locations = new Map((positions || []).map(row => [row.vehicle_id, row]));
  const rank = vehicle => {
    const row = locations.get(vehicle.vehicle_id);
    if (!row || !Number.isFinite(pickup.lat) || !Number.isFinite(pickup.lng)) return Infinity;
    return (row.latitude - pickup.lat) ** 2 + ((row.longitude - pickup.lng) * Math.cos(pickup.lat * Math.PI / 180)) ** 2;
  };
  const ranked = vehicles.map((vehicle, order) => ({ vehicle, order, distance: rank(vehicle) }))
    .sort((a,b) => a.distance-b.distance || a.order-b.order);
  const batches = []; let offset = 0, end = Math.max(1, initial);
  while (offset < ranked.length) { batches.push(ranked.slice(offset,end)); offset=end; end*=2; }
  return batches;
}
