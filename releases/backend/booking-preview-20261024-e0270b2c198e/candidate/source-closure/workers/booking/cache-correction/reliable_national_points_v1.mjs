import {immutableBucketIdentityV1} from './quote_r2_budget_v1.mjs';
import {HierarchicalPartitionedRouterV1,ImmutablePartitionCacheV1} from '../../../retained-source/workers/booking/modules/hierarchical_partitioned_routes_v1.mjs';

// Contract adapter only: the existing national router supplies exact static
// evidence to the existing product ETA/policy chain. No graph KV or network
// fallback. Immutable partition caches are shared; route evidence is scoped.
const caches=new WeakMap();
export function createReliableNationalPointsV1({manifest,bucket,scope}){
 if(typeof bucket?.get!=='function'||!scope?.tenant_id||!scope?.company_id)throw Error('national_binding_required');
 // New publications can use an immutable per-graph object namespace. The
 // manifest's internal partition/portal identities stay unchanged. Never
 // silently retry the legacy keys when a versioned object is absent.
 const namespace=manifest.objectNamespace??'';
 if(typeof namespace!=='string'||namespace&&(!/^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,159}$/.test(manifest.graphVersion)||namespace!==`routing/national/graphs/${manifest.graphVersion}/`))throw Error('national_object_namespace_invalid');
 const cacheIdentity=immutableBucketIdentityV1(bucket);let versions=caches.get(cacheIdentity);if(!versions){versions=new Map();caches.set(cacheIdentity,versions);}
 const key=JSON.stringify(manifest);
 let cache=versions.get(key);if(!cache){if(versions.size>=2)versions.delete(versions.keys().next().value);cache=new ImmutablePartitionCacheV1();versions.set(key,cache);}
 cache.accessContinuity??=new Map();
 const router=new HierarchicalPartitionedRouterV1({manifest,scope,cache,continuityStore:cache.accessContinuity,storage:{async getObject(key){const object=await bucket.get(namespace+key);if(!object)throw Error('national_object_missing');return new Uint8Array(await object.arrayBuffer());}}});
 const fixed={tenant_id:scope.tenant_id,company_id:scope.company_id,graphVersion:manifest.graphVersion,...(manifest.accessContext?.schema==='fluxidi-national-road-access-v1'?{accessContextRevision:manifest.accessContext.revision}:{})};
 return Object.freeze({kind:'STATIC_REGIONAL_POINTS_V1',async routeMany({origins,destination,scope:input,trafficRevision='static',gpsRoadContext=false}){
  if(input?.tenant_id!==fixed.tenant_id||input?.company_id!==fixed.company_id||input?.graphVersion!==fixed.graphVersion||fixed.accessContextRevision&&input?.accessContextRevision!==fixed.accessContextRevision)throw Error('national_route_scope');
  const batch=await router.batchPoints({scope:fixed,origins,target:destination,trafficRevision,geometry:true,gpsRoadContext});
  const results=[];
  for(let i=0;i<batch.routes.length;i++){
   const r=batch.routes[i];if(!r.reachable){results.push({ok:false,reason:r.reason});continue;}
   // Opaque evidence identity: public DTOs must not expose a busy trip origin.
   const bytes=new TextEncoder().encode(JSON.stringify([fixed,origins[i],destination,r.edgeSequence.map(e=>[e.id,e.seconds,e.distanceMeters])]));
   const evidenceId=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)),b=>b.toString(16).padStart(2,'0')).join('');
   const frontage=[r.accessEvidence?.origin?.frontage,r.accessEvidence?.destination?.frontage].filter(Boolean);
   // ETA is to the proven street-side pickup. The point-to-building offset
   // is not a measured walking/driving leg and must not fabricate one.
   // Safe medium frontage uses the existing wider product estimate policy.
   // The exhaustive legal junction proof already bounds every admitted GPS
   // origin in graph seconds. Do not add the generic accuracy-to-time policy
   // to that same uncertainty a second time. Without that proof LOW GPS
   // retains the existing90s policy assumption. HIGH/NORMAL keep the product
   // range unless bounded practical geometry, rather than the raw accuracy,
   // was needed: that uses the existing medium model without inventing a leg.
   const gpsProof=r.gpsRoadEvidence??r.nearPickupEvidence;
   const measuredAccess=origins[i]?.access,preciseGpsApproach=gpsRoadContext===true&&measuredAccess?.kind==='gps'&&Number.isFinite(measuredAccess.accuracyMeters)&&measuredAccess.accuracyMeters>0&&measuredAccess.accuracyMeters<=5&&Number.isFinite(measuredAccess.capturedAt)&&measuredAccess.capturedAt<=Date.now()&&Date.now()-measuredAccess.capturedAt<=30000&&r.accessEvidence?.origin?.kind==='gps'&&r.accessEvidence.origin.confidence==='HIGH';
   const junction=r.gpsRoadEvidence?.roadContext.junction,lowGps=r.gpsRoadEvidence?.roadContext.locationConfidence==='low',boundedJunction=junction?.schema==='fluxidi-common-road-junction-v1'&&Number.isFinite(junction.localLegTimeBoundSeconds)&&junction.localLegTimeBoundSeconds>=0&&Number.isFinite(junction.localLegDistanceBoundMeters)&&junction.localLegDistanceBoundMeters>=0;
   const gpsMargin=boundedJunction?junction.localLegTimeBoundSeconds:(r.gpsRoadEvidence?(lowGps?90*Math.min(1,r.gpsRoadEvidence.roadContext.accuracyMeters/100):0):90);
   const reservationGpsMargin=(r.gpsRoadEvidence?(lowGps?90*Math.min(1,r.gpsRoadEvidence.roadContext.accuracyMeters/100):0):90)+(junction?.localLegTimeBoundSeconds??0);
   results.push({ok:true,route:{graphVersion:r.graphVersion,evidenceClass:'EXACT_STATIC_ROUTE',staticSeconds:r.seconds,distanceMeters:r.distanceMeters,roadAccessEvidence:structuredClone(r.accessEvidence??null),edges:r.edgeSequence.map(e=>({id:e.id,...(e.terminalObject?{terminalObject:structuredClone(e.terminalObject)}:{}),...(e.partitionId?{partitionId:e.partitionId}:{}),...(e.way!=null?{way:e.way}:{}),...(e.ordinal!=null?{ordinal:e.ordinal}:{}),...(e.partial===true?{partial:true}:{}),seconds:e.seconds,distanceMeters:e.distanceMeters,...(e.direction!=null?{direction:e.direction}:{}),...(e.speedProfile?{speedProfile:e.speedProfile,speedProfileKey:e.speedProfileKey}:{})})),geometry:r.geometry,evidenceId:'national:'+evidenceId,frontageConfidence:r.nearPickupEvidence||lowGps||junction||r.gpsRoadEvidence?.roadContext.practicalGeometryMatch===true||frontage.some(f=>f.confidence==='MEDIUM_SAFE')?'medium':'high',...(preciseGpsApproach?{preciseGpsApproach:true}:{}),...(r.nearPickupEvidence?{nearPickupEvidence:structuredClone(r.nearPickupEvidence)}:{}),...(r.gpsRoadEvidence?{gpsRoadEvidence:structuredClone(r.gpsRoadEvidence)}:{}),...(gpsProof?{frontageUncertaintySeconds:(r.frontageUncertaintySeconds??0)+gpsMargin,frontageReservationUncertaintySeconds:(r.frontageUncertaintySeconds??0)+reservationGpsMargin}:{})}});
  }
  return {results};
 },describeRouteEdges:args=>router.describeRouteEdges(args),addressAccessContext:(point,options)=>router.addressAccessContext(point,options),addressRoutePoint:args=>router.addressRoutePoint(args),configuredSiteRoutePoint:args=>router.configuredSiteRoutePoint(args),diagnostics:()=>router.diagnostics()});
}
