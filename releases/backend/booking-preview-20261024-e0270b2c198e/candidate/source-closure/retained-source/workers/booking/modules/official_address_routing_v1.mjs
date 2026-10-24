// Local, not activated. The caller supplies a server-owned official address
// index and the existing owned router. No HTTP/geocoder/provider fallback.
// Index ingestion/publication and app adoption remain separate release gates.
import {resolvePracticalFrontageV1} from './practical_frontage_v1.mjs';
import {projectAccessV1} from './national_road_access_v1.mjs';
export const OFFICIAL_ADDRESS_V1 = 'fluxidi-official-address-v1';
const trustedAddresses = new WeakSet();
const trustedFrontages = new WeakSet();
const fail = code => { throw Error(code); };
const text = value => typeof value === 'string' && value.length > 0 &&
  value.length <= 500 && !/[\r\n\0]/.test(value);
const coordinate = p => p && typeof p.latitude === 'number' &&
  typeof p.longitude === 'number' && Number.isFinite(p.latitude) &&
  Number.isFinite(p.longitude) && Math.abs(p.latitude) <= 90 &&
  Math.abs(p.longitude) <= 180 && !(p.latitude === 0 && p.longitude === 0);
const freeze = value => {
  if (value && typeof value === 'object') {
    Object.values(value).forEach(freeze); Object.freeze(value);
  }
  return value;
};
const canonical = value => JSON.stringify(value,(_,v)=>v && !Array.isArray(v) &&
  typeof v==='object' ? Object.fromEntries(Object.keys(v).sort().map(k=>[k,v[k]])) : v);

// A client may select an ID; it cannot attest that its coordinates, label,
// source, graph match or an alternative street name are official.
export function createOfficialAddressAuthorityV1({ index,allowUnknownOfficialAssignment=false,allowMissingPosition=false }) {
  if (!['OFFICIAL_BELGIAN_ADDRESS_INDEX_V1','OFFICIAL_BE_NL_ADDRESS_INDEX_V1'].includes(index?.kind) ||
      !text(index.revision) || typeof index.get !== 'function') {
    fail('official_address_index_required');
  }
  const revision = index.revision;
  return Object.freeze({
    async resolve(id) {
      if (!text(id)) fail('official_address_id_required');
      if (index.revision !== revision) fail('official_address_index_changed');
      const found = await index.get(id);
      if (index.revision !== revision) fail('official_address_index_changed');
      if (found == null) fail('official_address_not_found');
      const record = structuredClone(found), a = record.address;
      if (record.schema !== OFFICIAL_ADDRESS_V1 || record.id !== id ||
          record.indexRevision !== revision || !text(record.source) ||
          !text(record.sourceVersion) || !text(record.sourceRecordId) ||
          (record.streetId != null && !text(record.streetId)) ||
          !coordinate(record.point)&&!(allowMissingPosition===true&&record.point==null) || !['BE','NL'].includes(a?.country) ||
          !text(a.street) || !text(a.houseNumber) ||
          !(a.country === 'BE' ? /^\d{4}$/ : /^[1-9]\d{3} ?[A-Z]{2}$/).test(a.postcode ?? '') ||
          !text(a.municipality) || (a.locality != null && !text(a.locality)) ||
          ['houseLetter','houseNumberAddition','boxNumber'].some(k=>a[k]!=null && !text(a[k]))) {
        fail('official_address_record_invalid');
      }
      if (record.status !== 'current' || record.officiallyAssigned !== true&&!(allowUnknownOfficialAssignment===true&&record.officiallyAssigned==null)) {
        fail('official_address_not_current');
      }
      // A building/address position is NOT an attested vehicle access point.
      // Retain the official identity; the existing road router still proves
      // access, road restrictions, ambiguity and actual graph reachability.
      const resolved = freeze({
        schema: OFFICIAL_ADDRESS_V1, id, indexRevision: revision,
        source: record.source, sourceVersion: record.sourceVersion,
        sourceRecordId: record.sourceRecordId,
        status:record.status,officiallyAssigned:record.officiallyAssigned??null,
        ...(record.streetId ? {streetId:record.streetId} : {}),
        ...(record.provenance ? {provenance:structuredClone(record.provenance)} : {}),
        address: { street: a.street, houseNumber: a.houseNumber,
          ...(text(a.boxNumber) ? { boxNumber: a.boxNumber } : {}),
          ...(text(a.houseLetter) ? {houseLetter:a.houseLetter} : {}),
          ...(text(a.houseNumberAddition) ? {houseNumberAddition:a.houseNumberAddition} : {}),
          postcode: a.postcode, locality: a.locality ?? a.municipality,
          ...(a.locality ? {municipality:a.municipality} : {}),country: a.country },
        point: record.point==null?null:{ latitude: record.point.latitude, longitude: record.point.longitude },
        accessProven: false,
      });
      trustedAddresses.add(resolved);
      return resolved;
    },
  });
}

// A bounded retry over the same existing graph, not a synthetic road/driveway.
// Only an object resolved by the server index above can opt into the unnamed
// geometry path. Physical barrier coverage must be attested by the same
// trusted graph publication; current legacy publications do not attest it.
export function resolveOfficialAddressFrontageV1({officialAddress, segments,
  barriers, barrierCoverage, graphVersion, revision, radii = [25,50,100], maxRadius = 100}) {
  if (!trustedAddresses.has(officialAddress)) fail('official_address_authority_required');
  if (!text(graphVersion) || !text(revision)) fail('official_address_graph_binding_required');
  if (!Array.isArray(segments) || segments.length > 8192) fail('access_address_context_limit');
  if (!Number.isFinite(maxRadius) || maxRadius <= 0 || maxRadius > 250 ||
      !Array.isArray(radii) || !radii.length || radii.length > 8 ||
      radii.some((r,i) => !Number.isFinite(r) || r <= 0 || r > maxRadius || i > 0 && r <= radii[i-1])) {
    fail('official_address_search_policy_invalid');
  }
  const input = {...officialAddress.point, address:officialAddress.address};
  let last;
  for (const radius of radii) {
    try {
      const frontage = resolvePracticalFrontageV1({input,segments,graphVersion,revision,searchRadiusMeters:radius});
      return finish(frontage,radius,'named_street');
    } catch (error) {
      // A larger radius is a search retry, never an escape from ambiguity,
      // restricted access, vertical conflict or missing source metadata.
      if (error.message !== 'access_address_street_unmatched') throw error;
      last = error;
    }
  }
  if (!completeBarrierContext()) fail('access_address_barrier_context_unproven');
  for (const radius of radii) {
    try {
      const frontage = resolvePracticalFrontageV1({input,segments,graphVersion,revision,
        searchRadiusMeters:radius,officialGeometry:true});
      return finish(frontage,radius,'official_position_unique_road');
    } catch (error) {
      if (error.message !== 'access_address_street_unmatched') throw error;
      last = error;
    }
  }
  throw last;

  function completeBarrierContext() {
    return barrierCoverage?.schema === 'fluxidi-physical-barrier-context-v1' &&
      barrierCoverage.complete === true && barrierCoverage.graphVersion === graphVersion &&
      barrierCoverage.revision === revision && Number.isFinite(barrierCoverage.radiusMeters) &&
      barrierCoverage.radiusMeters >= maxRadius &&
      barrierCoverage.center?.latitude === officialAddress.point.latitude &&
      barrierCoverage.center?.longitude === officialAddress.point.longitude &&
      Array.isArray(barriers) && barriers.length <= 150000;
  }
  function finish(frontage,radius,match) {
    // For a new extended/unnamed match, absent barrier evidence is not proof
    // that an off-road approach is clear. The old named path is not activated
    // or changed by this wrapper; callers must publish this context first.
    if (!completeBarrierContext()) fail('access_address_barrier_context_unproven');
    for (const barrier of barriers) {
      if (!coordinate(barrier?.from) || !coordinate(barrier?.to) || !text(barrier.kind)) {
        fail('access_address_barrier_context_invalid');
      }
      if (crosses(officialAddress.point,frontage.point,barrier.from,barrier.to)) {
        fail('access_address_barrier_crossing');
      }
    }
    const edgeIds = [...new Set(segments.filter(s=>frontage.wayIds.includes(s.way) &&
      Number.isSafeInteger(s.edge) && s.edge>=0 &&
      projectAccessV1(frontage.point,s.from,s.to).meters<=0.1).map(s=>s.edge))].sort((a,b)=>a-b);
    if(!edgeIds.length) fail('official_address_graph_edge_unproven');
    const result = freeze({officialAddress, addressPosition:{...officialAddress.point},edgeIds,
      pickupRoadPoint:{...frontage.point}, frontage, searchRadiusMeters:radius, match,
      // This is a street-side access decision, not proof of a driven connector
      // from the building door, and never an ETA/distance for such a connector.
      doorToRoadRouteProven:false});
    trustedFrontages.add(result);
    return result;
  }
}

// Server-owned, versioned address/road crosswalk. A geometric diagnostic or
// client JSON cannot certify access. Re-read source identity and re-evaluate
// current graph/access context before reusing a persisted link; never migrate
// a way/edge identifier silently to a new graph publication.
export function createOfficialAddressCrosswalkV1({authority,index,graphVersion,revision}) {
  if (typeof authority?.resolve !== 'function' ||
      index?.kind !== 'OFFICIAL_ADDRESS_CROSSWALK_V1' || !text(index.revision) ||
      typeof index.get !== 'function' || !text(graphVersion) || !text(revision)) {
    fail('official_address_crosswalk_required');
  }
  const publication = index.revision;
  const check = () => {if(index.revision !== publication) fail('official_address_crosswalk_changed');};
  const identity = a => ({id:a.id,streetId:a.streetId,indexRevision:a.indexRevision,
    source:a.source,sourceVersion:a.sourceVersion,sourceRecordId:a.sourceRecordId,
    address:a.address,addressPosition:a.point});
  const binding = match => ({schema:'fluxidi-official-address-road-link-v1',
    crosswalkRevision:publication,...identity(match.officialAddress),graphVersion,revision,
    pickupRoadPoint:match.pickupRoadPoint,wayIds:match.frontage.wayIds,
    edgeIds:match.edgeIds,
    searchRadiusMeters:match.searchRadiusMeters,match:match.match,
    doorToRoadRouteProven:false});
  return Object.freeze({
    record(match) {
      check();
      if(!trustedFrontages.has(match) || !text(match.officialAddress.streetId) ||
         match.frontage.graphVersion !== graphVersion || match.frontage.revision !== revision) {
        fail('official_address_crosswalk_access_unproven');
      }
      return freeze(binding(match));
    },
    async resolve(id,context) {
      check();
      const address = await authority.resolve(id);
      const record = await index.get(id);
      check();
      if(!record) fail('official_address_crosswalk_missing');
      if(record.schema !== 'fluxidi-official-address-road-link-v1' ||
         record.crosswalkRevision !== publication || record.graphVersion !== graphVersion ||
         record.revision !== revision || context?.graphVersion !== graphVersion ||
         context?.revision !== revision || !text(address.streetId) ||
         Object.entries(identity(address)).some(([k,v])=>canonical(v)!==canonical(record[k]))) {
        fail('official_address_crosswalk_stale');
      }
      const match = resolveOfficialAddressFrontageV1({...context,officialAddress:address});
      if(canonical(binding(match)) !== canonical(record)) fail('official_address_crosswalk_changed_match');
      return match;
    },
  });
}
function crosses(a,b,c,d) {
  const orientation=(p,q,r)=>(q.longitude-p.longitude)*(r.latitude-p.latitude)-
    (q.latitude-p.latitude)*(r.longitude-p.longitude);
  const on=(p,q,r)=>Math.min(p.longitude,q.longitude)-1e-12<=r.longitude &&
    r.longitude<=Math.max(p.longitude,q.longitude)+1e-12 &&
    Math.min(p.latitude,q.latitude)-1e-12<=r.latitude &&
    r.latitude<=Math.max(p.latitude,q.latitude)+1e-12;
  const x=orientation(a,b,c),y=orientation(a,b,d),z=orientation(c,d,a),w=orientation(c,d,b);
  return x*y<0 && z*w<0 || Math.abs(x)<1e-12 && on(a,b,c) ||
    Math.abs(y)<1e-12 && on(a,b,d) || Math.abs(z)<1e-12 && on(c,d,a) || Math.abs(w)<1e-12 && on(c,d,b);
}

// Shared address-to-journey preparation for ASAP and Later. This does not
// select a driver, invent a future origin, compute a fare or activate a route.
export function createOfficialAddressJourneyV1({ authority, router, scope, clock = Date.now }) {
  if (typeof authority?.resolve !== 'function' ||
      router?.kind !== 'LOCAL_ROUTING_ONLY_V1' ||
      typeof router.resolveForJourney !== 'function' ||
      typeof router.route !== 'function' || typeof router.planRoute !== 'function' ||
      !text(scope?.tenant_id) || !text(scope?.company_id)) {
    fail('official_address_owned_router_required');
  }
  const fixedScope = { tenant_id: scope.tenant_id, company_id: scope.company_id };
  const checkScope = () => {
    const actual = router.scope;
    if (actual?.tenant_id !== fixedScope.tenant_id || actual.company_id !== fixedScope.company_id) {
      fail('official_address_route_scope');
    }
    return actual;
  };
  checkScope();
  return Object.freeze({
    async prepare({ pickupAddressId, destinationAddressId, mode, requestedPickupAt }) {
      if (!['asap', 'later'].includes(mode) ||
          !Number.isFinite(requestedPickupAt) || requestedPickupAt < clock()) {
        fail('official_address_request_invalid');
      }
      checkScope();
      const pickup = await authority.resolve(pickupAddressId);
      const destination = await authority.resolve(destinationAddressId);
      const addresses = freeze({ pickup, destination });
      const point = a => ({ ...a.point, address: { ...a.address }, access: { kind: 'address' } });
      const origin = point(pickup), target = point(destination);
      try {
        checkScope();
        await router.resolveForJourney({
          pickup_lat: origin.latitude, pickup_lng: origin.longitude,
          dropoff_lat: target.latitude, dropoff_lng: target.longitude,
        });
        const context = checkScope();
        const evidence = mode === 'later'
          ? await router.planRoute({ scope: context, origin, destination: target,
            departureAt: requestedPickupAt })
          : await router.route({ scope: context, origin, destination: target,
            departureAt: requestedPickupAt });
        checkScope();
        if (evidence?.graphVersion !== context.graphVersion ||
            evidence.evidenceRevision !== context.evidenceRevision ||
            !Number.isFinite(evidence.validUntil) || evidence.validUntil <= clock() ||
            !Number.isFinite(evidence.distanceMeters) || evidence.distanceMeters < 0 ||
            (mode === 'later' ? evidence.planningOnly !== true ||
              !Number.isFinite(evidence.operationalDurationBoundSeconds) ||
              evidence.operationalDurationBoundSeconds < 0 :
              !Number.isFinite(evidence.seconds) || evidence.seconds < 0)) {
          fail('official_address_route_evidence_invalid');
        }
        // Return the router's genuine evidence untouched. Pickup ETA and
        // driver-to-pickup distance belong to the candidate path, not this leg.
        return { ok: true, addressValid: true, routingStatus: 'routeable',
          addresses, mode, requestedPickupAt, evidence };
      } catch (error) {
        if (error?.message === 'official_address_route_scope') throw error;
        const reason = /^[a-z][a-z0-9_]{0,99}$/.test(error?.message ?? '')
          ? error.message : 'official_address_route_unavailable';
        return { ok: false, addressValid: true, routingStatus: 'unavailable',
          addresses, mode, requestedPickupAt, reason };
      }
    },
  });
}
