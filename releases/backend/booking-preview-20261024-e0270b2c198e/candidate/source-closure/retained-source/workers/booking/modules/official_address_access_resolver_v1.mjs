import {createOfficialAddressAuthorityV1} from './official_address_routing_v1.mjs';
import {foldStreetV1,resolvePracticalFrontageV1} from './practical_frontage_v1.mjs';
import {projectAccessV1,resolveRoadAccessV1} from './national_road_access_v1.mjs';
import {officialAddressReferenceV1,officialAddressPositionUsableV1} from './official_address_reference_v1.mjs';
import {registerOfficialAddressCandidateV1} from './official_address_route_point_v1.mjs';
export {officialAddressReferenceV1} from './official_address_reference_v1.mjs';

// Server-owned official index + immutable graph context. No geocoder, network,
// KV, GPS mutation or alternate routing engine. A building point never attests
// its own access. Unproven candidates are retained, not ranked into certainty.
export const ADDRESS_ACCESS_V1='fluxidi-address-access-v1';
export const ADDRESS_ROUTE_CONTEXT_V1='fluxidi-address-route-context-v1';
const fail=reason=>{throw Error(reason);},finite=Number.isFinite;
const text=v=>typeof v==='string'&&v.length>0&&v.length<=500&&!/[\r\n\0]/.test(v);
const coordinate=p=>p&&finite(p.latitude)&&finite(p.longitude)&&Math.abs(p.latitude)<=90&&Math.abs(p.longitude)<=180;
const same=(a,b)=>a?.tenant_id===b?.tenant_id&&a?.company_id===b?.company_id;
const canonical=v=>JSON.stringify(v,(_,x)=>x&&!Array.isArray(x)&&typeof x==='object'?Object.fromEntries(Object.keys(x).sort().map(k=>[k,x[k]])):x);
const sha=async v=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(canonical(v)))),b=>b.toString(16).padStart(2,'0')).join('');
const freeze=v=>{if(v&&typeof v==='object'){Object.values(v).forEach(freeze);Object.freeze(v);}return v;};
const forbidden=new Set(['no','private','customers','delivery','agricultural','forestry','permit']);
const permittedRoads=new Set(['residential','living_street','unclassified','tertiary','secondary','primary','tertiary_link','secondary_link','primary_link','service']);
const identity=a=>({id:a.id,indexRevision:a.indexRevision,source:a.source,sourceVersion:a.sourceVersion,sourceRecordId:a.sourceRecordId,streetId:a.streetId??null,address:a.address});
function crosses(a,b,c,d){
 const x=p=>({x:p.longitude*Math.cos(a.latitude*Math.PI/180)*111195,y:p.latitude*111195}),p=x(a),q=x(b),r=x(c),s=x(d),orient=(a,b,c)=>(b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x),on=(a,b,c)=>Math.min(a.x,b.x)-1e-6<=c.x&&c.x<=Math.max(a.x,b.x)+1e-6&&Math.min(a.y,b.y)-1e-6<=c.y&&c.y<=Math.max(a.y,b.y)+1e-6;
 const u=orient(p,q,r),v=orient(p,q,s),w=orient(r,s,p),z=orient(r,s,q);
 return u*v<0&&w*z<0||Math.abs(u)<1e-6&&on(p,q,r)||Math.abs(v)<1e-6&&on(p,q,s)||Math.abs(w)<1e-6&&on(r,s,p)||Math.abs(z)<1e-6&&on(r,s,q);
}
function roadDenial(s,address,terminal=false){
 const t=s.tags;if(!t||!Array.isArray(t.streetNames))return 'access_metadata_missing';
 if(t.bridge||t.tunnel||t.layer!=null&&String(t.layer)!=='0'||t.level!=null&&String(t.level)!=='0')return 'access_vertical_layer_unproven';
 if(!permittedRoads.has(t.highway)||t.motorroad==='yes')return 'access_motorway_pickup_unproven';
 if(t.denied||t.driveable===false||forbidden.has(t.motorcar??t.motor_vehicle??t.vehicle??t.access)||['no_stopping','no'].includes(t.stopping))return 'access_restricted_road';
 if((t.motorcar??t.motor_vehicle??t.vehicle??t.access)==='destination'&&!terminal)return 'access_terminal_proof_required';
 for(const k of ['postcode','locality'])if(address[k]&&t[k]&&foldStreetV1(address[k])!==foldStreetV1(t[k]))return 'access_address_locality_conflict';
 return null;
}
function completeBarrierContext(context,address,radius){
 const c=context.barrierCoverage;
 return c?.schema==='fluxidi-physical-barrier-context-v1'&&c.complete===true&&c.graphVersion===context.graphVersion&&c.revision===context.revision&&coordinate(c.center)&&c.center.latitude===address.point.latitude&&c.center.longitude===address.point.longitude&&finite(c.radiusMeters)&&c.radiusMeters>=radius&&text(c.source)&&text(c.sourceVersion)&&Array.isArray(context.barriers)&&context.barriers.length<=150000;
}
export function createOfficialAddressAccessResolverV1({index,graph,scope,clock=Date.now,maxCandidates=4,maxContexts=128,searchRadiusMeters=100,crosswalk=null}){
 const verified=new WeakSet();
 if(!same(scope,scope)||!text(scope?.tenant_id)||!text(scope?.company_id)||typeof graph?.readContext!=='function'||!text(graph.graphVersion)||!text(graph.revision)||!Number.isSafeInteger(maxCandidates)||maxCandidates<1||maxCandidates>8||!Number.isSafeInteger(maxContexts)||maxContexts<1||maxContexts>512||!finite(searchRadiusMeters)||searchRadiusMeters<=0||searchRadiusMeters>100)fail('address_access_configuration_invalid');
 const authority=createOfficialAddressAuthorityV1({index,allowUnknownOfficialAssignment:true,allowMissingPosition:true}),revision=index.revision,fixed={tenant_id:scope.tenant_id,company_id:scope.company_id},contexts=new Map(),routePoints=new WeakMap(),metrics={indexReads:0,contextReads:0,cacheHits:0,candidatesExamined:0,routeBatches:0,routePairs:0,crosswalkReads:0,crosswalkHits:0};
 const retainedSizes=new Map();let retainedBytes=0;const maxContextCacheBytes=4*1024*1024;
 const guard=()=>{if(index.revision!==revision)fail('address_index_changed');if(graph.graphVersion!==scope.graphVersion||scope.accessContextRevision&&graph.revision!==scope.accessContextRevision)fail('address_graph_changed');};
 async function resolve(input,{role='destination',vehicleProfileKey=null}={}){
  guard();const ref=officialAddressReferenceV1(input);if(!ref)fail('official_address_id_required');if(ref.index_revision!==revision)fail('address_index_changed');if(!['origin','destination'].includes(role))fail('address_endpoint_role_invalid');
  metrics.indexReads++;const address=await authority.resolve(ref.id);guard();if(address.source!==ref.source||address.sourceVersion!==ref.source_version)fail('address_source_changed');
  if(!officialAddressPositionUsableV1(address))return freeze({schema:ADDRESS_ACCESS_V1,...fixed,indexRevision:revision,address,officialIdentity:identity(address),officialPosition:address.point,graphVersion:graph.graphVersion,revision:graph.revision,role,vehicleProfileKey,candidates:[],rejected:[],status:'data_insufficient',reason:'official_position_unavailable_or_in_research',maxCandidates});
  const signature=await sha({...identity(address),position:address.point,positionProvenance:address.provenance??null}),key=canonical([fixed,signature,graph.graphVersion,graph.revision,role,vehicleProfileKey]);
  if(contexts.has(key)){metrics.cacheHits++;return contexts.get(key);}
  // Preserve ordinary 100m admission. Only an absent official street may
  // expand to the existing frontage policy's 250m bound. A rejected nearby
  // street is never replaced by a more distant candidate to evade a guard.
  let radius=searchRadiusMeters;
  const read=async()=>{
   metrics.contextReads++;const c=await graph.readContext({point:address.point,address,role,radiusMeters:radius,vehicleProfileKey});guard();
   if(c?.graphVersion!==graph.graphVersion||c.revision!==graph.revision||c.complete!==true||!Array.isArray(c.segments)||c.segments.length>8192||!Array.isArray(c.negative)||!coordinate(c.center)||projectAccessV1(address.point,c.center,c.center).meters>.1||!finite(c.radiusMeters)||c.radiusMeters<radius)fail('address_context_incomplete');
   if(vehicleProfileKey!=null&&vehicleProfileKey!==c.vehicleProfileKey)fail('address_vehicle_profile_unproven');
   if(c.barriers?.some(b=>!coordinate(b.from)||!coordinate(b.to)||!text(b.kind)))fail('address_barrier_context_invalid');
   return c;
  };
  let context=await read();
  const matchesStreet=s=>s.tags?.streetNames?.some(n=>foldStreetV1(n)===foldStreetV1(address.address.street))||address.streetId&&s.tags?.officialStreetIds?.includes(address.streetId);
  if(radius===100&&!context.segments.some(s=>matchesStreet(s)&&projectAccessV1(address.point,s.from,s.to).meters<=radius)){
   radius=250;context=await read();
  }
  const rows=context.segments.map(s=>({...s,...projectAccessV1(address.point,s.from,s.to)})),groups=new Map(),rejected=[];
  let legacyFrontage=null;
  const legacyRowCount=rows.filter(s=>s.meters<=radius&&s.tags?.streetNames?.some(n=>foldStreetV1(n)===foldStreetV1(address.address.street))).length;
  if(legacyRowCount<=512)try{legacyFrontage=resolvePracticalFrontageV1({input:{...address.point,address:address.address},segments:context.segments,graphVersion:graph.graphVersion,revision:graph.revision,searchRadiusMeters:radius});}catch{}
  for(const s of rows){
   const named=Array.isArray(s.tags?.streetNames)&&s.tags.streetNames.some(n=>foldStreetV1(n)===foldStreetV1(address.address.street));
   const linked=address.streetId&&Array.isArray(s.tags?.officialStreetIds)&&s.tags.officialStreetIds.includes(address.streetId);
   if(!named&&!linked||s.meters>radius)continue;
   metrics.candidatesExamined++;const denial=roadDenial(s,address.address,context.terminalWayIds?.includes(s.way));if(denial){rejected.push({edge:s.edge,way:s.way,reason:denial});continue;}
   const atNode=[s.from,s.to].find(n=>projectAccessV1(s.point,n,n).meters<=.1),group=atNode?'node:'+atNode.nodeId:[s.way,Math.min(s.from.nodeId,s.to.nodeId),Math.max(s.from.nodeId,s.to.nodeId)].join(':');
   if(!groups.has(group))groups.set(group,[]);groups.get(group).push(s);
  }
  let saved=null;if(crosswalk){if(crosswalk.kind!=='OFFICIAL_ADDRESS_ACCESS_LINK_INDEX_V1'||typeof crosswalk.get!=='function'||!text(crosswalk.revision))fail('address_crosswalk_configuration');metrics.crosswalkReads++;saved=await crosswalk.get(address.id);guard();}
  // Short consecutive pieces of one immutable source way are one local
  // frontage, not one route calculation per OSM node. Do not merge different
  // ways/carriageways, branches or a connection outside the bounded context.
  const localGroups=new Map(groups),keys=[...localGroups.keys()],merged=new Set(),corridors=new Map(),atNode=new Map(),degrees=new Map();let tieCountIsLowerBound=false;
  for(const s of rows)for(const n of [s.from,s.to]){const k=s.way+':'+n.nodeId;if(!degrees.has(k))degrees.set(k,new Set());degrees.get(k).add([Math.min(s.from.nodeId,s.to.nodeId),Math.max(s.from.nodeId,s.to.nodeId)].join(':'));}
  for(const [k,ss]of localGroups)if(new Set(ss.map(s=>s.way)).size===1)for(const n of ss.flatMap(s=>[s.from,s.to]))if(projectAccessV1(address.point,n,n).meters<=radius){const nk=ss[0].way+':'+n.nodeId;if(!atNode.has(nk))atNode.set(nk,new Set());atNode.get(nk).add(k);}
  for(const k of keys){if(merged.has(k))continue;const stack=[k],ss=[];merged.add(k);
   while(stack.length){const current=stack.pop(),part=localGroups.get(current);ss.push(...part);
    if(new Set(part.map(s=>s.way)).size!==1)continue;
    for(const n of part.flatMap(s=>[s.from,s.to])){const nk=part[0].way+':'+n.nodeId;if(degrees.get(nk)?.size>2)continue;for(const next of atNode.get(nk)??[])if(!merged.has(next)){merged.add(next);stack.push(next);}}
   }
   ss.sort((a,b)=>a.meters-b.meters||a.edge-b.edge);const ties=[];for(const s of ss.filter(s=>s.meters<=ss[0].meters+.01))if(!ties.some(t=>projectAccessV1(s.point,t.point,t.point).meters<=.1)){ties.push(s);if(ties.length>maxCandidates){tieCountIsLowerBound=true;break;}}
   if(ties.length>1)for(const t of ties)corridors.set(k+':tie:'+t.edge,[t,...ss.filter(s=>s!==t)]);else corridors.set(k,ss);
  }
  const validFrontage=legacyFrontage??context.legacyTerminalSnap?.accessEvidence?.frontage;
  if(corridors.size>maxCandidates&&!validFrontage){
   const previews=[...corridors].slice(0,32).map(([id,ss])=>({id:'pending:'+id,point:ss[0].point,status:'unproven',reason:'address_candidate_limit',wayIds:[ss[0].way],offsetMeters:ss[0].meters,proof:null}));
   graph.releaseContext?.({address,role});return freeze({schema:ADDRESS_ACCESS_V1,...fixed,indexRevision:revision,address,officialIdentity:identity(address),officialPosition:{...address.point,provenance:address.provenance??null},addressSignature:signature,graphVersion:graph.graphVersion,revision:graph.revision,role,vehicleProfileKey,candidates:previews,rejected:rejected.slice(0,32),candidateCount:corridors.size,candidateCountIsLowerBound:tieCountIsLowerBound,candidatePreviewsTruncated:corridors.size>previews.length,status:'budget_exceeded',maxCandidates});
  }
  const evaluatedCorridors=validFrontage?[...corridors].filter(([,ss])=>projectAccessV1(ss[0].point,validFrontage.point,validFrontage.point).meters<=.1&&ss.some(s=>validFrontage.wayIds.includes(s.way))):[...corridors];
  const candidates=[];
  for(const [group,ss]of evaluatedCorridors){
   const first=ss[0],atPoint=ss.filter(s=>projectAccessV1(first.point,s.from,s.to).meters<=.1),candidate={id:await sha([signature,graph.graphVersion,graph.revision,group,role,vehicleProfileKey]),point:first.point,edgeIds:[...new Set(atPoint.map(s=>s.edge))].sort((a,b)=>a-b),wayIds:[...new Set(atPoint.map(s=>s.way))].sort((a,b)=>a-b),offsetMeters:first.meters,role,proof:null,status:'unproven',reason:'access_barrier_context_unproven'};
   const terminal=context.terminalWayIds?.includes(first.way)===true;
   let access;try{if(!terminal){access=resolveRoadAccessV1({input:first.point,segments:context.segments,negative:context.negative,graphVersion:context.graphVersion,revision:context.revision,clock});if(access.accessEvidence.wayIds.some(w=>!candidate.wayIds.includes(w))&&access.kind!=='node')throw Error('access_graph_attachment_changed');}}catch(e){candidate.status='denied';candidate.reason=e.message;candidates.push(candidate);continue;}
   if(context.barriers?.some(b=>crosses(address.point,first.point,b.from,b.to))){candidate.status='denied';candidate.reason='access_address_barrier_crossing';}
   else if(first.meters<=.1){candidate.proof={kind:'official_position_on_published_road',addressSignature:signature};candidate.status='proven';candidate.reason=null;}
   else if(terminal&&context.legacyTerminalSnap?.accessEvidence?.wayIds.includes(first.way)&&projectAccessV1(context.legacyTerminalSnap.accessEvidence.frontage.point,first.point,first.point).meters<=.1){candidate.proof={kind:'existing_validated_endpoint_only_terminal',addressSignature:signature,doorToRoadRouteProven:false};candidate.status='proven';candidate.reason=null;}
   else if(legacyFrontage&&legacyFrontage.wayIds.some(w=>candidate.wayIds.includes(w))&&projectAccessV1(legacyFrontage.point,first.point,first.point).meters<=.1){
    // Preserve the existing, unchanged named-street admission. This attests
    // the street-side pickup only, never a building entrance or driven leg.
    candidate.proof={kind:'existing_validated_street_frontage',addressSignature:signature,frontageSchema:legacyFrontage.schema,doorToRoadRouteProven:false};candidate.status='proven';candidate.reason=null;
   }
   else if(completeBarrierContext(context,address,radius)){
    if(context.barriers.some(b=>crosses(address.point,first.point,b.from,b.to))){candidate.status='denied';candidate.reason='access_address_barrier_crossing';}
    else if(rows.some(s=>!candidate.edgeIds.includes(s.edge)&&projectAccessV1(first.point,s.from,s.to).meters>.1&&crosses(address.point,first.point,s.from,s.to))){candidate.status='denied';candidate.reason='access_crosses_carriageway';}
    else {candidate.proof={kind:'street_side_with_complete_barrier_context',addressSignature:signature,barrierSource:context.barrierCoverage.source,barrierSourceVersion:context.barrierCoverage.sourceVersion};candidate.status='proven';candidate.reason=null;}
   }
   // Reuse is not an attestation bypass: the exact official identity, directed
   // attachment and current access proof are all checked again independently.
   if(saved&&candidate.status==='proven'&&saved.schema===ADDRESS_ACCESS_V1&&saved.addressSignature===signature&&saved.graphVersion===graph.graphVersion&&saved.revision===graph.revision&&saved.role===role&&saved.vehicleProfileKey===vehicleProfileKey&&saved.candidate?.id===candidate.id&&canonical(saved.candidate.point)===canonical(candidate.point)&&canonical(saved.candidate.edgeIds)===canonical(candidate.edgeIds)){candidate.reused=true;metrics.crosswalkHits++;}
   if(candidate.status==='proven')registerOfficialAddressCandidateV1(candidate,{graphVersion:graph.graphVersion,revision:graph.revision,role,addressId:address.id});
   if(candidate.status==='proven'&&typeof graph.materialize==='function')try{routePoints.set(candidate,await graph.materialize({candidate,address,role}));}catch(error){candidate.status='denied';candidate.reason=error.message;candidate.proof=null;}
   candidates.push(candidate);
  }
  // A successful unchanged frontage proof has already evaluated the entire
  // competing-road context. Additional projections along that same validated
  // street are not independent possible access points. Retain them for the
  // audit, but do not consume the bounded route-candidate budget with every
  // ordinary short edge. Never do this after an ambiguous frontage failure.
  const validatedFrontage=validFrontage;
  const validated=validatedFrontage&&candidates.find(c=>c.status==='proven'&&c.wayIds.some(w=>validatedFrontage.wayIds.includes(w))&&projectAccessV1(c.point,validatedFrontage.point,validatedFrontage.point).meters<=.1);
  if(validated)for(const c of candidates)if(c!==validated&&c.status!=='denied'){c.status='superseded';c.reason='same_existing_validated_frontage';c.proof=null;}
  const plausible=candidates.filter(c=>['proven','unproven'].includes(c.status)),limited=plausible.length>maxCandidates;
  // Never truncate ambiguity and silently select the remaining candidate.
  const incomplete=[...rejected,...candidates].some(c=>/unproven|missing|invalid|incomplete/.test(c.reason??''));
  const result=freeze({schema:ADDRESS_ACCESS_V1,...fixed,indexRevision:revision,address,officialIdentity:identity(address),officialPosition:{...address.point,provenance:address.provenance??null},addressSignature:signature,graphVersion:graph.graphVersion,revision:graph.revision,vehicleProfileKey,role,candidates,rejected:rejected.slice(0,32),candidateCount:corridors.size,validatedProjectionGroupsExcluded:corridors.size-evaluatedCorridors.length,status:limited?'budget_exceeded':plausible.some(c=>c.status==='proven')?'access_proven':plausible.length||incomplete?'access_uncertain':candidates.length||rejected.length?'access_forbidden':'data_insufficient',maxCandidates});
  graph.releaseContext?.({address,role});
  verified.add(result);const size=new TextEncoder().encode(JSON.stringify(result)).byteLength*2;if(size<=maxContextCacheBytes/4){while(contexts.size>=maxContexts||retainedBytes+size>maxContextCacheBytes){const k=contexts.keys().next().value;retainedBytes-=retainedSizes.get(k);retainedSizes.delete(k);contexts.delete(k);}contexts.set(key,result);retainedSizes.set(key,size);retainedBytes+=size;}return result;
 }
 async function route({origin,destination,router,mode='asap',departureAt=clock(),vehicleProfileKey=null}){
  guard();if(!same(router?.scope,fixed)||router.scope.graphVersion!==graph.graphVersion||typeof router.prepareCandidates!=='function'||typeof router.route!=='function'||typeof router.planRoute!=='function'||!['asap','later'].includes(mode)||!finite(departureAt))fail('address_route_scope');
  const endpoints=await Promise.all([resolve(origin,{role:'origin',vehicleProfileKey}),resolve(destination,{role:'destination',vehicleProfileKey})]);
  for(const e of endpoints)if(e.status!=='access_proven')return {ok:false,status:e.status,reason:e.status==='budget_exceeded'?'address_candidate_limit':e.status==='access_uncertain'?'access_address_parallel_ambiguity':e.status==='access_forbidden'?'address_access_forbidden':'address_data_insufficient',endpoints};
  const from=endpoints[0].candidates.filter(c=>c.status==='proven').map(c=>({...c,point:routePoints.get(c)??c.point})),to=endpoints[1].candidates.filter(c=>c.status==='proven').map(c=>({...c,point:routePoints.get(c)??c.point})),routes=[],failed=[];
  for(const d of to){
   guard();metrics.routeBatches++;await router.prepareCandidates({scope:router.scope,origins:from.map(c=>c.point),destination:d.point});
   for(const o of from){metrics.routePairs++;try{const evidence=await router[mode==='later'?'planRoute':'route']({scope:router.scope,origin:o.point,destination:d.point,departureAt});guard();if(evidence.graphVersion!==graph.graphVersion||evidence.evidenceRevision!==router.scope.evidenceRevision||!finite(evidence.validUntil)||evidence.validUntil<=clock()||!finite(evidence.distanceMeters)||evidence.distanceMeters<0||mode==='asap'&&(!finite(evidence.seconds)||evidence.seconds<0)||mode==='later'&&(evidence.planningOnly!==true||!finite(evidence.operationalDurationBoundSeconds)||evidence.operationalDurationBoundSeconds<0))fail('address_route_evidence_invalid');routes.push({origin:o,destination:d,evidence});}catch(e){failed.push({origin:o.id,destination:d.id,reason:/^[a-z][a-z0-9_]{0,99}$/.test(e.message)?e.message:'address_route_evidence_unavailable'});}}
  }
  guard();
  if(!routes.length){const unreachable=failed.length&&failed.every(r=>['graph_disconnected','graph_weak_component_disconnected','graph_local_no_legal_exit'].includes(r.reason));return {ok:false,status:unreachable?'route_unreachable':'route_evidence_unavailable',reason:unreachable?'address_route_unreachable':'address_route_evidence_unavailable',endpoints,failed};}
  routes.sort((a,b)=>(mode==='later'?a.evidence.operationalDurationBoundSeconds-b.evidence.operationalDurationBoundSeconds:a.evidence.seconds-b.evidence.seconds)||a.evidence.distanceMeters-b.evidence.distanceMeters||a.origin.id.localeCompare(b.origin.id)||a.destination.id.localeCompare(b.destination.id));
  const selected=routes[0],binding={schema:ADDRESS_ROUTE_CONTEXT_V1,...fixed,index_revision:revision,graph_version:graph.graphVersion,access_revision:graph.revision,vehicle_profile_key:vehicleProfileKey,addresses:endpoints.map(e=>e.addressSignature),access_candidates:[selected.origin.id,selected.destination.id],points:[selected.origin.point,selected.destination.point],route_evidence_id:selected.evidence.evidenceId,traffic_revision:selected.evidence.productEvidence?.trafficRevision??null};
  const id=await sha(binding),context=freeze({...binding,id,valid_until_ms:Math.min(selected.evidence.validUntil,clock()+15000),status:'routeable'});
  return {ok:true,status:'routeable',endpoints,selected,evidence:selected.evidence,addressContext:context,alternatives:routes.map(r=>({origin:r.origin.id,destination:r.destination.id,distanceMeters:r.evidence.distanceMeters,seconds:r.evidence.seconds??null,planningOnly:r.evidence.planningOnly===true})),failed};
 }
 return Object.freeze({resolve,route,assertCurrent:guard,routePoint(result,candidateId){guard();if(!verified.has(result)||!same(result,fixed))fail('address_crosswalk_access_unproven');const c=result.candidates.find(c=>c.id===candidateId&&c.status==='proven');if(!c)fail('address_crosswalk_access_unproven');return routePoints.get(c)??c.point;},record(result,candidateId){guard();if(!verified.has(result)||!same(result,fixed))fail('address_crosswalk_access_unproven');const candidate=result.candidates.find(c=>c.id===candidateId&&c.status==='proven');if(!candidate)fail('address_crosswalk_access_unproven');return freeze({schema:ADDRESS_ACCESS_V1,addressSignature:result.addressSignature,indexRevision:revision,graphVersion:graph.graphVersion,revision:graph.revision,role:result.role,vehicleProfileKey:result.vehicleProfileKey,candidate:structuredClone(candidate)});},async confirm(previous,args){if(!same(previous,fixed)||previous.schema!==ADDRESS_ROUTE_CONTEXT_V1||previous.valid_until_ms<=clock())fail('address_context_expired');const current=await route(args);if(!current.ok||current.addressContext.id!==previous.id)fail('address_context_changed');return current;},diagnostics:()=>({...metrics,cachedContexts:contexts.size,contextCacheBytes:retainedBytes,maxContextCacheBytes,maxContexts,maxCandidates,additionalKvReads:0,additionalKvWrites:0})});
}
