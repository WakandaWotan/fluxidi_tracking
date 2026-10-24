// Derived from immutable ledger.claims identity, never persisted authority.
// Index grows only with the already-bounded authoritative ledger, not tenants
// in a global Map. Candidate windows/expiry are still tested by the ledger.
const indexes = new WeakMap();
export function invalidateCapacityResourceIndex(claims) { indexes.delete(claims); }
export function capacityResourceIndex(claims) {
  let index=indexes.get(claims);if(index)return index;
  const driver=new Map(),vehicle=new Map(),owner=new Map();
  const add=(map,id,claim)=>{if(!id)return;if(!map.has(id))map.set(id,[]);map.get(id).push(claim);};
  for(const claim of Object.values(claims||{})){add(driver,claim.driver_id,claim);add(vehicle,claim.vehicle_id,claim);add(owner,claim.owner_id,claim);}
  index={driver,vehicle,owner};if(claims&&typeof claims==='object')indexes.set(claims,index);return index;
}
export function claimsForResource(claims, resource, index=capacityResourceIndex(claims)) {
  const found=new Map();for(const claim of [...(index.driver.get(resource.driver_id)||[]),...(index.vehicle.get(resource.vehicle_id)||[])])found.set(claim.claim_id,claim);
  return [...found.values()];
}
export function claimsForOwner(claims, ownerId) { return capacityResourceIndex(claims).owner.get(ownerId)||[]; }
