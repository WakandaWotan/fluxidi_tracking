// Server-only complete mission evidence. Callers supply trusted depot/locations
// and routing functions; client-supplied distance/time is deliberately absent.
import {nationalFinancialRequestInfoV1} from './financial_national_request_v1.mjs';
const validPoint = p => p && Number.isFinite(p.lat) && Number.isFinite(p.lng)
  && Math.abs(p.lat) <= 90 && Math.abs(p.lng) <= 180;
const unavailable = reason => ({ ok: false, request_quote: true, reason });

export async function resolveCompanyMissionRoute({ depot, pickup, destination, stops = [], geocode, directions, financialRequest = null, scope = null }) {
  const own=financialRequest==null?null:nationalFinancialRequestInfoV1(financialRequest);
  if(financialRequest!=null&&(!own||own.scope.tenant_id!==scope?.tenant_id||own.scope.company_id!==scope?.company_id))return unavailable('mission_route_provider_not_approved');
  if(own){geocode=financialRequest.geocode;directions=financialRequest.directions;}
  if (!validPoint(depot)) return unavailable('mission_depot_required');
  if (!Array.isArray(stops) || typeof directions !== 'function') return unavailable('mission_route_inputs_invalid');
  async function resolve(value) {
    if (validPoint(value)) return { lat: value.lat, lng: value.lng };
    if (typeof value !== 'string' || !value.trim() || typeof geocode !== 'function') throw new Error('location');
    const point = await geocode(value.trim());
    if (!validPoint(point)) throw new Error('location');
    return { lat: point.lat, lng: point.lng };
  }
  let occupied;
  try {
    occupied = [];
    for (const location of [pickup, ...stops, destination]) occupied.push(await resolve(location));
  } catch { return unavailable('mission_location_unresolved'); }
  const home = { lat: depot.lat, lng: depot.lng };
  const coords = [home, ...occupied, { ...home }];
  let route;
  try { route = await directions(coords); }
  catch { return unavailable('mission_route_unavailable'); }
  const legs = route?.legs;
  if (!Array.isArray(legs) || legs.length !== coords.length - 1
    || !legs.every(leg => typeof leg.distance === 'number' && Number.isFinite(leg.distance) && leg.distance >= 0
      && typeof leg.duration === 'number' && Number.isFinite(leg.duration) && leg.duration >= 0)) {
    return unavailable('mission_route_incomplete');
  }
  // Sum raw metres/seconds, never rounded display kilometres/minutes.
  const sum = items => ({ distance: items.reduce((n,l) => n+l.distance,0), duration: items.reduce((n,l) => n+l.duration,0) });
  const mission = sum(legs);
  const passenger = sum(legs.slice(1,-1));
  if (!Number.isFinite(mission.distance) || !Number.isFinite(mission.duration)) return unavailable('mission_route_incomplete');
  const financial=own?route._financial_route:null;
  if(own&&(!financial||financial.source!=='fluxidi-national'||financial.tenant_id!==scope.tenant_id||financial.company_id!==scope.company_id
    ||financial.graph_checksum!==own.policy.graphManifestSha256||financial.publication_sha256!==own.policy.publicationSha256
    ||JSON.stringify(financial.points)!==JSON.stringify(coords)||financial.legs?.length!==legs.length
    ||financial.legs.some((l,i)=>l.distance_m!==legs[i].distance||l.duration_s!==legs[i].duration)))return unavailable('mission_route_incomplete');
  return { ok: true, route_evidence: own?structuredClone(financial):{source:'mapbox',source_version:'directions/v5',profile:'mapbox/driving',
    duration_basis:'provider_driving',access_cost:'included',points:coords,
    legs:legs.map(l=>({distance_m:l.distance,duration_s:l.duration}))},
    missionKm: mission.distance/1000, missionMinutes: mission.duration/60,
    occupiedKm: passenger.distance/1000, occupiedMinutes: passenger.duration/60, legCount: legs.length };
}
