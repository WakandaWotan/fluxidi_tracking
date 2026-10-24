// Safe lookup acceleration: retain Array.find's first-match semantics.
export function indexDispatchVehicles(vehicles = []) {
  const byId = new Map();
  for (const vehicle of vehicles) {
    const id = String(vehicle.vehicle_id || vehicle.id);
    if (!byId.has(id)) byId.set(id,vehicle);
  }
  return byId;
}

// Research-only preview. NOT used to constrain dispatch candidates.
export function previewDistanceShortlist(candidates, pickup, limit = 5) {
  const distance = position => {
    const radians = n => n*Math.PI/180;
    const dlat = radians(position.latitude-pickup.latitude), dlon = radians(position.longitude-pickup.longitude);
    const a = Math.sin(dlat/2)**2 + Math.cos(radians(position.latitude))*Math.cos(radians(pickup.latitude))*Math.sin(dlon/2)**2;
    return 6_371_000*2*Math.atan2(Math.sqrt(a),Math.sqrt(Math.max(0,1-a)));
  };
  return candidates.map((row,order) => ({ row, order, distance: distance(row.position) }))
    .sort((a,b) => a.distance-b.distance || a.order-b.order).slice(0,limit).map(row => row.row);
}
