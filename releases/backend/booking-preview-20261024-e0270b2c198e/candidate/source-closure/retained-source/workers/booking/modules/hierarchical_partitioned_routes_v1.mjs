// Portable offline/local routing runtime. Storage is an immutable object/file
// interface, never Booking KV. This module does not activate a binding or
// publish a graph. Incoming-edge portal identities preserve boundary turns.
import {NATIONAL_ACCESS_V1,validateAccessContextV1,resolveRoadAccessV1,resolveDriverContinuityV1,resolveNearPickupRoadAccessV1,resolveDriverGpsRoadAccessV1,provenUnnamedServiceExitV1} from './national_road_access_v1.mjs';
import {resolvePracticalFrontageV1} from './practical_frontage_v1.mjs';
import {resolveNationalTerminalV1,readNationalTerminalContextV1} from './national_terminal_access_v1.mjs';
import {createOfficialAddressRoutePointV1,readOfficialAddressRoutePointV1,verifyOfficialAddressCandidateV1,createOfficialTerminalFrontageV1} from './official_address_route_point_v1.mjs';
import {configuredSiteInputV1,createConfiguredSiteFrontageV1,createConfiguredSiteRoutePointV1,readConfiguredSiteRoutePointV1} from './configured_site_access_v1.mjs';
import {createTerminalNavigationReaderV1} from './national_terminal_navigation_v1.mjs';
// Only immutable, validated graph metadata is shared. Router instances, scope,
// storage, counters, continuity and request limits remain independent.
const preparedImmutableManifests=new WeakMap();
function deeplyImmutableJson(value,seen=new WeakSet()){
 if(!value||typeof value!=='object')return true;
 if(seen.has(value))return false;
 if(!Object.isFrozen(value)||![Object.prototype,Array.prototype,null].includes(Object.getPrototypeOf(value)))return false;
 seen.add(value);
 for(const descriptor of Object.values(Object.getOwnPropertyDescriptors(value))){
  if(!Object.hasOwn(descriptor,'value')||!deeplyImmutableJson(descriptor.value,seen))return false;
 }
 seen.delete(value);return true;
}
const LIMIT=8*1024*1024;
function speedFields(g,e,entry=false){const way=e[entry?7:5],speedProfile=g.access?.ways.get(way)?.speedProfile;return {partitionId:g.id,...(speedProfile?{speedProfile,speedProfileKey:way,direction:e[entry?9:7]}:{})};}
const fail=s=>{throw Error(s);};
const finite=(v)=>Number.isFinite(v);
const id=v=>Number.isSafeInteger(v)&&v>=0;
const token=v=>typeof v==='string'&&/^[a-zA-Z0-9_.-]{1,160}$/.test(v);
function frozen(v){if(v&&typeof v==='object'){for(const x of Object.values(v))frozen(x);Object.freeze(v);}return v;}
function continuityAnchor(input,snap,graphVersion,revision){const a=input.access;return {input:{latitude:input.latitude,longitude:input.longitude,access:{kind:'gps',capturedAt:a.capturedAt,accuracyMeters:a.accuracyMeters,speedMetersPerSecond:a.speedMetersPerSecond,...(a.headingDegrees==null?{}:{headingDegrees:a.headingDegrees})}},snap:{accessEvidence:{wayIds:[...snap.accessEvidence.wayIds]}},graphVersion,revision};}
const sha=async b=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',b)),v=>v.toString(16).padStart(2,'0')).join('');
const contains=(b,p,pad=0)=>b&&p.longitude>=b[0]-pad&&p.longitude<=b[2]+pad&&p.latitude>=b[1]-pad&&p.latitude<=b[3]+pad;
const point=p=>{if(!finite(p?.latitude)||!finite(p?.longitude)||Math.abs(p.latitude)>90||Math.abs(p.longitude)>180)fail('partition_point_invalid');return p;};
const distance=(a,b)=>{const r=Math.PI/180,h=Math.sin((b.latitude-a.latitude)*r/2)**2+Math.cos(a.latitude*r)*Math.cos(b.latitude*r)*Math.sin((b.longitude-a.longitude)*r/2)**2;return 12742000*Math.asin(Math.min(1,Math.sqrt(h)));};
class Heap {
 a=[];positions=new Map();
 push(x){let i=this.positions.get(x[2]);if(i===undefined){i=this.a.length;this.a.push(x);}else if(this.a[i][0]<x[0]||this.a[i][0]===x[0]&&this.a[i][1]<=x[1])return;while(i){const p=(i-1)>>1;if(this.a[p][0]<x[0]||this.a[p][0]===x[0]&&this.a[p][1]<=x[1])break;this.a[i]=this.a[p];this.positions.set(this.a[i][2],i);i=p;}this.a[i]=x;this.positions.set(x[2],i);}
 pop(){const f=this.a[0],v=this.a.pop();this.positions.delete(f[2]);if(this.a.length){let i=0;while(i*2+1<this.a.length){let c=i*2+1;if(c+1<this.a.length&&(this.a[c+1][0]<this.a[c][0]||this.a[c+1][0]===this.a[c][0]&&this.a[c+1][1]<this.a[c][1]))c++;if(this.a[c][0]>v[0]||this.a[c][0]===v[0]&&this.a[c][1]>=v[1])break;this.a[i]=this.a[c];this.positions.set(this.a[i][2],i);i=c;}this.a[i]=v;this.positions.set(v[2],i);}return f;}
}
function decode(v,descriptor,version,certificate){
 if(v.schema!=='fluxidi-partition-v1'||v.id!==descriptor.id||v.graphVersion!==version||!Array.isArray(v.nodes)||!Array.isArray(v.ghosts)||v.nodes.length+v.ghosts.length>100000||!Array.isArray(v.edges)||v.edges.length>500000||!Array.isArray(v.entries??[])||!Array.isArray(v.turns))fail('partition_graph_invalid');
 const nodes=new Map(),components=new Map(),own=new Set(v.nodes.map(n=>n[0])),out=new Map(),incoming=new Map(),edges=new Map(),entries=new Map(),exits=new Map(),bans=new Set();
 const certified=certificate?.complete===true&&certificate.kind==='NECESSARY_REACHABILITY_V1'&&certificate.graphVersion===version;
 if(certificate&&!certified)fail('partition_component_certificate_invalid');
 for(const n of [...v.nodes,...v.ghosts]){if(!id(n[0])||!finite(n[1])||!finite(n[2])||nodes.has(n[0])||certified&&(!id(n[3])||n[3]>=certificate.counts.nodes))fail('partition_node_invalid');nodes.set(n[0],{longitude:n[1],latitude:n[2]});if(certified)components.set(n[0],n[3]);}
 const addIncoming=e=>{if(!incoming.has(e[2]))incoming.set(e[2],[]);incoming.get(e[2]).push(e);};
 for(const e of v.edges){if(e.length!==8||!e.slice(0,3).every(id)||!finite(e[3])||e[3]<0||!finite(e[4])||e[4]<0||!own.has(e[1])||!nodes.has(e[2])||edges.has(e[0])||certified&&components.get(e[1])!==components.get(e[2]))fail('partition_edge_invalid');Object.freeze(e);edges.set(e[0],e);addIncoming(e);if(!out.has(e[1]))out.set(e[1],[]);out.get(e[1]).push(e);if(!own.has(e[2]))exits.set(e[0],e);}
 for(const e of v.entries??[]){if(e.length!==(certified?11:10)||!e.slice(0,3).every(id)||!own.has(e[2])||own.has(e[1])||!finite(e[3])||e[3]<0||!finite(e[4])||e[4]<0||!finite(e[5])||!finite(e[6])||entries.has(e[0])||edges.has(e[0])||certified&&e[10]!==components.get(e[2]))fail('partition_entry_invalid');Object.freeze(e);entries.set(e[0],e);addIncoming(e);nodes.set(e[1],{longitude:e[5],latitude:e[6]});if(certified)components.set(e[1],e[10]);}
 for(const t of v.turns){if(!Array.isArray(t)||t.length!==2||!t.every(id)||!edges.has(t[1])||!(edges.get(t[0])??entries.get(t[0]))||(edges.get(t[0])??entries.get(t[0]))[2]!==edges.get(t[1])[1])fail('partition_turn_invalid');bans.add(t[0]+':'+t[1]);}
 const grid=new Map(),long=[];let refs=0;
 for(const e of [...edges.values(),...entries.values()]){
  const a=nodes.get(e[1]),b=nodes.get(e[2]);if(!a||!b)fail('partition_portal_coordinate_missing');
  const x0=Math.floor(Math.min(a.longitude,b.longitude)/.002),x1=Math.floor(Math.max(a.longitude,b.longitude)/.002),y0=Math.floor(Math.min(a.latitude,b.latitude)/.002),y1=Math.floor(Math.max(a.latitude,b.latitude)/.002);
  if((x1-x0+1)*(y1-y0+1)>64){long.push(e);continue;}
  for(let x=x0;x<=x1;x++)for(let y=y0;y<=y1;y++){const k=x+':'+y;if(!grid.has(k))grid.set(k,[]);grid.get(k).push(e);if(++refs>2000000)fail('partition_spatial_index_limit');}
 }
 // Conservative accounting includes object/map/index overhead. Real isolate
 // peak still needs native measurement; serialized bytes are not heap bytes.
 const access=v.accessContext?validateAccessContextV1(v.accessContext,version):null;
 const residentBytes=nodes.size*128+components.size*48+(edges.size+entries.size)*240+bans.size*96+refs*16+grid.size*96+(access?.residentBytes??0);
 return {id:v.id,nodes,components,own,out,incoming,edges,entries,exits,bans,grid,long,access,residentBytes};
}
export class ImmutablePartitionCacheV1 {
 #cache=new Map();#inflight=new Map();#bytes=0;#routeBytes=0;
 constructor({maxBytes=32*1024*1024}={}){if(!id(maxBytes)||maxBytes<1024||maxBytes>64*1024*1024)fail('partition_cache_limit');this.maxBytes=maxBytes;}
 lookup(key){const r=this.#cache.get(key);if(!r)return null;this.#cache.delete(key);this.#cache.set(key,r);return r.value;}
 retain(key,v,metrics){
  if(!id(v.residentBytes)||v.residentBytes>this.maxBytes)fail('partition_cache_object_oversized');
  if(v.kind==='STATIC_ROUTE_V1'&&v.residentBytes>this.maxBytes/4)fail('partition_route_cache_object_oversized');
  const remove=k=>{const old=this.#cache.get(k);this.#bytes-=old.bytes;if(old.value.kind==='STATIC_ROUTE_V1')this.#routeBytes-=old.bytes;this.#cache.delete(k);};
  if(this.#cache.has(key))remove(key);
  if(v.kind==='STATIC_ROUTE_V1'){
   while(this.#routeBytes+v.residentBytes>this.maxBytes/4){const k=[...this.#cache].find(([,r])=>r.value.kind==='STATIC_ROUTE_V1')[0];remove(k);metrics.partitionCacheEvictions++;}
  }
  // Reserve at most a quarter of the existing budget for exact route reuse.
  // Large unpack graphs must not evict both destination alternatives in
  // turn. Ordinary object LRU retains the remaining budget; total never grows.
  while(this.#bytes+v.residentBytes>this.maxBytes){const victim=[...this.#cache].find(([,r])=>r.value.kind!=='STATIC_ROUTE_V1');const k=victim?.[0]??this.#cache.keys().next().value;remove(k);metrics.partitionCacheEvictions++;}
  this.#cache.set(key,{value:v,bytes:v.residentBytes});this.#bytes+=v.residentBytes;if(v.kind==='STATIC_ROUTE_V1')this.#routeBytes+=v.residentBytes;
 }
 async load(key,read,metrics){
  if(this.#cache.has(key)){const r=this.#cache.get(key);this.#cache.delete(key);this.#cache.set(key,r);metrics.partitionCacheHits++;return r.value;}
  if(this.#inflight.has(key)){metrics.partitionCacheHits++;return this.#inflight.get(key);}
  metrics.partitionCacheMisses++;
  if(this.#inflight.size>=4)fail('partition_concurrent_load_limit');
  const promise=(async()=>{const v=await read();this.retain(key,v,metrics);return v;})();
  this.#inflight.set(key,promise);try{return await promise;}finally{this.#inflight.delete(key);}
 }
 diagnostics(){return {entries:this.#cache.size,residentBytes:this.#bytes,maxBytes:this.maxBytes,staticRouteBytes:this.#routeBytes,maxStaticRouteBytes:this.maxBytes/4,inflight:this.#inflight.size};}
}
function localReverse(g,{target=null,finish=null,exitSeeds=new Map(),costs=new Map(),closed=new Set(),originsBound=null}){
 const d=new Map(),meters=new Map(),next=new Map(),free=new Map(),heap=new Heap();let settled=0;
 const improve=(e,s,m,successor)=>{if(!d.has(e)||s<d.get(e)||s===d.get(e)&&m<meters.get(e)){d.set(e,s);meters.set(e,m);next.set(e,successor);heap.push([s,m,e]);}};
 if(target!==null){if(!g.own.has(target))fail('partition_target_not_owned');const end=finish&&g.edges.get(finish.edge);if(finish&&(!end||end[1]!==target||!finite(finish.fraction)||finish.fraction<0||finish.fraction>1||closed.has(end[0])))fail('partition_destination_edge_invalid');const s=end?(costs.get(end[0])??end[3])*finish.fraction:0,m=end?end[4]*finish.fraction:0;free.set(target,{seconds:s,meters:m,edge:null});for(const e of g.incoming.get(target)??[])if(!closed.has(e[0])&&(!end||!g.bans.has(e[0]+':'+end[0])))improve(e[0],s,m,null);}
 for(const [exit,v] of exitSeeds){if(!g.exits.has(exit)||!finite(v.seconds)||v.seconds<0||!finite(v.meters)||v.meters<0)fail('partition_exit_seed_invalid');if(!closed.has(exit))improve(exit,v.seconds,v.meters,null);}
 while(heap.a.length){
  // Positive-cost branch bound on an already found route for EVERY requested
  // origin, never a candidate count/radius budget. Equal-cost tails stay open.
  if(originsBound&&settled%32===0){const upper=Math.max(...originsBound.map(o=>o.incomingEdge===undefined?(free.get(o.nodeId)?.seconds??Infinity):(d.get(o.incomingEdge)??Infinity)+(costs.get(o.incomingEdge)??(g.edges.get(o.incomingEdge)??g.entries.get(o.incomingEdge))?.[3]??Infinity)*o.initialFraction));if(finite(upper)&&heap.a[0][0]>upper)break;}
  const [s,m,k]=heap.pop();if(s!==d.get(k)||m!==meters.get(k))continue;settled++;if(g.entries.has(k))continue;
  const e=g.edges.get(k);if(!e)fail('partition_state_missing');if(closed.has(k))continue;const w=costs.get(k)??e[3];if(!finite(w)||w<0)fail('partition_cost_invalid');
  const ns=s+w,nm=m+e[4],f=free.get(e[1]);if(!f||ns<f.seconds||ns===f.seconds&&nm<f.meters)free.set(e[1],{seconds:ns,meters:nm,edge:k});
  for(const prev of g.incoming.get(e[1])??[]){if(closed.has(prev[0])||g.bans.has(prev[0]+':'+k))continue;improve(prev[0],ns,nm,k);}
 }
 return {d,meters,next,free,settled,residentBytes:d.size*176+free.size*96};
}
export class HierarchicalPartitionedRouterV1 {
 #parts=new Map();#manifestHash=null;
 constructor({manifest,storage,cache=new ImmutablePartitionCacheV1(),maxRequestBytes=64*1024*1024,maxPortalStates=100000,onProgress=null,continuityStore=new Map(),scope=null}){
  if(manifest?.schema!=='fluxidi-partition-manifest-v1'||manifest.overlayStatus!=='PRECOMPUTED_EXACT_EDGE_STATE_LOCAL'||typeof manifest.graphVersion!=='string'||!Array.isArray(manifest.partitions)||manifest.partitions.length>16384||!manifest.tree?.[manifest.root]||typeof storage?.getObject!=='function'||!id(maxRequestBytes)||maxRequestBytes>64*1024*1024||!id(maxPortalStates)||maxPortalStates>100000)fail('partition_runtime_contract');
  const prepared=preparedImmutableManifests.get(manifest);
  if(!prepared){
  if(new TextEncoder().encode(JSON.stringify(manifest)).byteLength>4*1024*1024)fail('partition_manifest_size');
  if(manifest.accessContext&&(manifest.accessContext.schema!==NATIONAL_ACCESS_V1||manifest.accessContext.fullPublication!==true||typeof manifest.accessContext.revision!=='string'||!manifest.accessContext.revision))fail('access_manifest_invalid_or_partial');
  const treeNodes=new Set();const validateTree=k=>{if(treeNodes.has(k)||treeNodes.size>=100000)fail('partition_index_cycle_or_limit');treeNodes.add(k);const n=manifest.tree[k];if(!n||!Array.isArray(n.bbox)||n.bbox.length!==4||!n.bbox.every(finite))fail('partition_index_invalid');if(n.children){if(n.children.length!==4)fail('partition_index_invalid');for(const c of n.children)validateTree(c);}};validateTree(manifest.root);
  }
  this.scope=scope?frozen({tenant_id:scope.tenant_id,company_id:scope.company_id}):null;
  this.manifest=prepared?.manifest??frozen(structuredClone(manifest));this.certificateKey=JSON.stringify(this.manifest.weakComponents??null);if(this.certificateKey.length>4096)fail('partition_component_certificate_limit');this.storage=storage;this.cache=cache;this.maxRequestBytes=maxRequestBytes;this.maxPortalStates=maxPortalStates;this.onProgress=typeof onProgress==='function'?onProgress:null;
  if(!(continuityStore instanceof Map)||continuityStore.size>512)fail('access_continuity_store_limit');this.continuityStore=continuityStore;for(const[k,v]of continuityStore)if(Date.now()-v.input.access.capturedAt>15000)continuityStore.delete(k);
  if(prepared)this.#parts=new Map(prepared.parts);
  else{
  for(const p of this.manifest.partitions){if(this.#parts.has(p.id)||!id(p.nodes)||!id(p.ghosts)||p.nodes+p.ghosts>100000||!id(p.bytes)||p.bytes>LIMIT||(!/^partitions\/r[0-3]*\.json$/.test(p.key)&&p.key!==`partitions/${p.id}-${p.sha256}.json`)||!/^[a-f0-9]{64}$/.test(p.sha256)||!/^r[0-3]*$/.test(p.id)||!Array.isArray(p.overlay))fail('partition_descriptor_invalid');this.#parts.set(p.id,p);}
   if(deeplyImmutableJson(manifest))preparedImmutableManifests.set(manifest,{manifest:this.manifest,parts:new Map(this.#parts)});
  }
  this.metrics={graphKVReads:0,graphStorageReads:0,partitionPayloadReads:0,portalIndexReads:0,overlayStorageReads:0,partitionCacheHits:0,partitionCacheMisses:0,partitionCacheEvictions:0,requestReuseHits:0,requestEvictions:0,weakComponentRejections:0,localEscapeRejections:0,bytesLoaded:0,routeQueries:0,localSearches:0,unpackSearches:0,unpackReuseHits:0,overlaySearchStates:0,staticRouteCacheHits:0,staticRouteCacheMisses:0,staticRouteCacheSkips:0,commercialDispatchCalls:0,accessQueries:0,accessStaticAccepted:0,driverContinuityAttempts:0,driverContinuityAccepted:0,driverContinuityRejected:0};
 }
 owner(p){point(p);let k=this.manifest.root;for(let i=0;i<20;i++){const n=this.manifest.tree[k];if(!n||!contains(n.bbox,p))fail('partition_coverage_missing');if(n.partition)return n.partition;if(n.empty)fail('partition_empty');const b=n.bbox,x=(b[0]+b[2])/2,y=(b[1]+b[3])/2;k=n.children[(p.longitude>=x?1:0)+(p.latitude>=y?2:0)];}fail('partition_index_depth');}
 async #read(descriptor){if(descriptor.bytes>LIMIT||!id(descriptor.bytes))fail('partition_storage_limit');this.metrics.graphStorageReads++;this.metrics[descriptor.key.startsWith('partitions/')?'partitionPayloadReads':descriptor.key.startsWith('portals/')?'portalIndexReads':'overlayStorageReads']++;const value=await this.storage.getObject(descriptor.key);const b=value instanceof ArrayBuffer?new Uint8Array(value):value instanceof Uint8Array?value:null;if(!b||b.byteLength!==descriptor.bytes||b.byteLength>LIMIT)fail('partition_storage_bytes');this.metrics.bytesLoaded+=b.byteLength;if(await sha(b)!==descriptor.sha256)fail('partition_storage_hash');let v;try{v=JSON.parse(new TextDecoder().decode(b));}catch{fail('partition_storage_json');}return v;}
 async #graph(pid,request){
  if(request?.graphs.has(pid)){this.metrics.requestReuseHits++;const v=request.graphs.get(pid),k='graph:'+pid;request.lru.delete(k);request.lru.set(k,{type:'graph',key:pid,bytes:v.residentBytes});return v;}
  const p=this.#parts.get(pid);if(!p)fail('partition_unknown');const g=await this.cache.load(this.manifest.graphVersion+':'+pid+':'+p.sha256+':'+this.certificateKey,async()=>decode(await this.#read(p),p,this.manifest.graphVersion,this.manifest.weakComponents),this.metrics);
  if(request)this.#retain(request,'graph',pid,g);return g;
 }
 #retain(request,type,key,value){
  if(value.residentBytes>this.maxRequestBytes)fail('partition_request_memory_limit');
  while(request.bytes+value.residentBytes>this.maxRequestBytes){const victim=[...request.lru].find(([k,v])=>!(v.type==='graph'&&v.key===request.pinnedGraph));if(!victim)fail('partition_request_memory_limit');const [k,v]=victim;request.lru.delete(k);request.bytes-=v.bytes;(v.type==='graph'?request.graphs:request.objects).delete(v.key);this.metrics.requestEvictions++;}
  (type==='graph'?request.graphs:request.objects).set(key,value);request.bytes+=value.residentBytes;request.peakBytes=Math.max(request.peakBytes,request.bytes);request.lru.set(type+':'+key,{type,key,bytes:value.residentBytes});
 }
 async #portalIndex(pid,request){
  const p=this.#parts.get(pid),part=p.portalIndex;if(!part||!/^portals\/r[0-3]*\.json$/.test(part.key))fail('partition_portal_index_missing');const key=this.manifest.graphVersion+':'+part.key+':'+part.sha256;
  if(request.objects.has(key)){this.metrics.requestReuseHits++;const v=request.objects.get(key);request.lru.delete('object:'+key);request.lru.set('object:'+key,{type:'object',key,bytes:v.residentBytes});return v;}
  const v=await this.cache.load(key,async()=>{const raw=await this.#read(part);if(raw.schema!=='fluxidi-boundary-portals-v1'||raw.graphVersion!==this.manifest.graphVersion||raw.partition!==pid||!Array.isArray(raw.entries)||!Array.isArray(raw.exits)||raw.entries.some(r=>r.length!==2||!id(r[0])||!this.#parts.has(r[1]))||raw.exits.some(e=>!id(e)))fail('partition_portal_index_invalid');const entries=new Map(raw.entries),exits=new Set(raw.exits);if(entries.size!==raw.entries.length||exits.size!==raw.exits.length)fail('partition_portal_index_duplicate');return {entries,exits,residentBytes:entries.size*128+exits.size*48};},this.metrics);this.#retain(request,'object',key,v);return v;
 }
 async #overlay(pid,exit,request){
  const p=this.#parts.get(pid),part=p.overlay.find(x=>x.firstExit<=exit&&exit<=x.lastExit);if(!part)return [];
  if(!/^overlays\/r[0-3]*-\d+\.json$/.test(part.key))fail('partition_overlay_key');
  const key=this.manifest.graphVersion+':'+part.key+':'+part.sha256;
  let v=request.objects.get(key);
  if(!v){v=await this.cache.load(key,async()=>{const raw=await this.#read(part);if(raw.schema!=='fluxidi-portal-overlay-v1'||raw.graphVersion!==this.manifest.graphVersion||raw.partition!==pid||!Array.isArray(raw.rows)||raw.rows.some(r=>r.length!==4||!id(r[0])||!id(r[1])||!finite(r[2])||r[2]<0||!finite(r[3])||r[3]<0))fail('partition_overlay_invalid');const byExit=new Map();for(const r of raw.rows){if(!byExit.has(r[0]))byExit.set(r[0],[]);byExit.get(r[0]).push(Object.freeze(r));}return {byExit,residentBytes:raw.rows.length*128+byExit.size*80};},this.metrics);this.#retain(request,'object',key,v);}
  else{this.metrics.requestReuseHits++;request.lru.delete('object:'+key);request.lru.set('object:'+key,{type:'object',key,bytes:v.residentBytes});}
  return v.byExit.get(exit)??[];
 }
 async batchNodes({scope,origins,target,costs=new Map(),closed=new Set(),trafficRevision='static',geometry=true,requestContext=null,alternativeGroups=null}){
  if(!token(scope?.tenant_id)||!token(scope.company_id)||scope.graphVersion&&scope.graphVersion!==this.manifest.graphVersion||!Array.isArray(origins)||origins.length>1500||!id(target?.nodeId)||!(costs instanceof Map)||costs.size>8192||!(closed instanceof Set)||closed.size>8192||!token(trafficRevision))fail('partition_route_scope');
  if([...costs].some(([k,v])=>!id(k)||!finite(v)||v<0)||[...closed].some(k=>!id(k)))fail('partition_traffic_invalid');
  if(alternativeGroups!==null&&(!Array.isArray(alternativeGroups)||alternativeGroups.length!==origins.length||!alternativeGroups.every(id)))fail('partition_alternative_groups_invalid');
  const args={scope,origins,target,costs,closed,trafficRevision,geometry,requestContext,alternativeGroups};
  // Cache only immutable static road evidence after batchPoints has freshly
  // proved access. Presence, GPS freshness, schedules and time-dependent ETA
  // remain outside this cache. Changed closures/costs bypass it entirely.
  // Entries share the existing 32 MiB cache, never an additional memory pool.
  if(costs.size||closed.size)return this.#routeNodes(args);
  const lookupStarted=performance.now();this.#manifestHash??=sha(new TextEncoder().encode(JSON.stringify(this.manifest)));
  const key='static-route-v1:'+await this.#manifestHash+':'+await sha(new TextEncoder().encode(JSON.stringify([scope,origins,target,geometry,alternativeGroups,trafficRevision]))),hit=this.cache.lookup(key);
  if(hit&&hit.residentBytes<=this.maxRequestBytes){const result=structuredClone(hit.result);this.metrics.staticRouteCacheHits++;this.metrics.routeQueries++;return {...result,totalMs:performance.now()-lookupStarted,requestResidentBytes:requestContext?.bytes??0,requestPeakResidentBytes:requestContext?.peakBytes??0,diagnostics:this.diagnostics()};}
  this.metrics.staticRouteCacheMisses++;const result=await this.#routeNodes(args);
  const profiles=new Set(result.routes.flatMap(r=>(r.edgeSequence??[]).map(e=>e.speedProfile).filter(Boolean)));
  const residentBytes=4096+result.routes.reduce((n,r)=>n+1024+(r.edgeSequence?.length??0)*928+(r.geometry?.length??0)*192,0)+[...profiles].reduce((n,p)=>n+new TextEncoder().encode(JSON.stringify(p)).byteLength*4,0);
  if(residentBytes<=this.cache.maxBytes/4)this.cache.retain(key,{kind:'STATIC_ROUTE_V1',residentBytes,result:structuredClone(result)},this.metrics);else this.metrics.staticRouteCacheSkips++;
  return {...result,diagnostics:this.diagnostics()};
 }
 async #routeNodes({scope,origins,target,costs,closed,trafficRevision,geometry,requestContext,alternativeGroups}){
  this.metrics.routeQueries++;const started=performance.now(),destPid=this.owner(target),request=requestContext??{graphs:new Map(),objects:new Map(),lru:new Map(),bytes:0,peakBytes:0,pinnedGraph:destPid};request.pinnedGraph=destPid;const dest=await this.#graph(destPid,request);
  if(!dest.own.has(target.nodeId)||distance(dest.nodes.get(target.nodeId),target)>.1)fail('partition_target_binding');
  const groups=new Map(),disconnected=new Set(),localTrapped=new Set();for(const o of origins){if(!id(o.nodeId))fail('partition_origin_binding');const pid=this.owner(o),g=await this.#graph(pid,request);if(!g.own.has(o.nodeId)||distance(g.nodes.get(o.nodeId),o)>.1)fail('partition_origin_binding');if(o.incomingEdge!==undefined){const e=g.edges.get(o.incomingEdge)??g.entries.get(o.incomingEdge);if(!e||e[2]!==o.nodeId||!finite(o.initialFraction)||o.initialFraction<0||o.initialFraction>1)fail('partition_origin_edge_invalid');}if(g.components.size&&dest.components.size&&g.components.get(o.nodeId)!==dest.components.get(target.nodeId)){disconnected.add(o);this.metrics.weakComponentRejections++;continue;}if(!groups.has(pid))groups.set(pid,[]);groups.get(pid).push(o);}
  // Exact necessary reachability: a legal route must reach the destination
  // in this partition or leave through a directed exit. Exhaust the local
  // edge-state graph once per partition; no radius or candidate budget.
  for(const [pid,rows] of groups){
   const g=await this.#graph(pid,request),escape=localReverse(g,{target:pid===destPid?target.nodeId:null,finish:pid===destPid?target.finish:null,exitSeeds:new Map([...g.exits.keys()].map(e=>[e,{seconds:0,meters:0}])),costs,closed});this.metrics.localSearches++;
   const viable=rows.filter(o=>{const ok=o.incomingEdge===undefined?escape.free.has(o.nodeId):escape.d.has(o.incomingEdge);if(!ok){localTrapped.add(o);this.metrics.localEscapeRejections++;}return ok;});
   if(viable.length)groups.set(pid,viable);else groups.delete(pid);
  }
  const distances=new Map(),meters=new Map(),trace=new Map(),portalOwners=new Map(),heap=new Heap();let evaluationDirty=false;
  const improve=(eid,s,m,t,pid)=>{if(!distances.has(eid)||s<distances.get(eid)||s===distances.get(eid)&&m<meters.get(eid)){distances.set(eid,s);meters.set(eid,m);trace.set(eid,t);portalOwners.set(eid,pid);heap.push([s,m,eid]);if(groups.has(pid))evaluationDirty=true;if(distances.size>this.maxPortalStates)fail('partition_portal_state_limit');}};
  const root=localReverse(dest,{target:target.nodeId,finish:target.finish,costs,closed,originsBound:groups.size===1&&groups.has(destPid)?groups.get(destPid):null});this.metrics.localSearches++;
  for(const [eid,e] of dest.entries)if(root.d.has(eid))improve(eid,root.d.get(eid),root.meters.get(eid),{partition:destPid,exit:null},this.owner({longitude:e[5],latitude:e[6]}));
  let trees=new Map(),treeBytes=0,best=new Map(),lastEvaluated=-1;
  const makeTree=async pid=>{const g=await this.#graph(pid,request),seeds=new Map();for(const eid of g.exits.keys())if(distances.has(eid))seeds.set(eid,{seconds:distances.get(eid),meters:meters.get(eid)});const r=localReverse(g,{target:pid===destPid?target.nodeId:null,finish:pid===destPid?target.finish:null,exitSeeds:seeds,costs,closed,originsBound:groups.get(pid)});this.metrics.localSearches++;if(r.residentBytes>16*1024*1024)fail('partition_query_state_limit');while(treeBytes+r.residentBytes>16*1024*1024){const k=trees.keys().next().value;treeBytes-=trees.get(k).residentBytes;trees.delete(k);}trees.set(pid,r);treeBytes+=r.residentBytes;return r;};
  const unpackTree=(pid,g,exit,entry)=>{
   // Only this incoming edge needs a path to this exit. A full partition
   // reverse tree was repeatedly computed for almost identical alternatives.
   // Positive costs allow the existing exact branch bound; cache identity
   // includes entry because the bounded tree is not valid for other entries.
   const key='unpack:'+pid+':'+exit+':'+entry;
   if(trees.has(key)){this.metrics.unpackReuseHits++;return trees.get(key);}
   const r=localReverse(g,{exitSeeds:new Map([[exit,{seconds:0,meters:0}]]),costs,closed,originsBound:[{incomingEdge:entry,initialFraction:0}]});this.metrics.unpackSearches++;
   if(r.residentBytes>16*1024*1024)fail('partition_query_state_limit');
   while(treeBytes+r.residentBytes>16*1024*1024){const k=trees.keys().next().value;treeBytes-=trees.get(k).residentBytes;trees.delete(k);}
   trees.set(key,r);treeBytes+=r.residentBytes;return r;
  };
  const evaluate=async()=>{trees=new Map();treeBytes=0;best=new Map();for(const [pid,rows] of groups){const r=await makeTree(pid),g=await this.#graph(pid,request);for(const o of rows){if(o.incomingEdge===undefined)best.set(o,r.free.get(o.nodeId)??{seconds:Infinity,meters:Infinity,edge:null});else{const e=g.edges.get(o.incomingEdge)??g.entries.get(o.incomingEdge);best.set(o,r.d.has(e[0])?{seconds:r.d.get(e[0])+(costs.get(e[0])??e[3])*o.initialFraction,meters:r.meters.get(e[0])+e[4]*o.initialFraction,edge:r.next.get(e[0])}:{seconds:Infinity,meters:Infinity,edge:null});}}}lastEvaluated=this.metrics.overlaySearchStates;evaluationDirty=false;};
  await evaluate();
  while(groups.size&&heap.a.length){
   const max=Math.max(...[...best.values()].map(v=>v.seconds));if(finite(max)&&heap.a[0][0]>max)break;
   const [s,m,eid]=heap.pop();if(s!==distances.get(eid)||m!==meters.get(eid))continue;this.metrics.overlaySearchStates++;
   if(this.onProgress&&this.metrics.overlaySearchStates%512===0)this.onProgress({elapsedMs:performance.now()-started,portalStates:distances.size,queuedStates:heap.a.length,requestResidentBytes:request.bytes,requestPeakResidentBytes:request.peakBytes,diagnostics:this.diagnostics()});
   const pid=portalOwners.get(eid),portals=await this.#portalIndex(pid,request);if(!portals.exits.has(eid))fail('partition_portal_identity');
   let rows;if(costs.size||closed.size){const g=await this.#graph(pid,request),r=localReverse(g,{exitSeeds:new Map([[eid,{seconds:0,meters:0}]]),costs,closed});this.metrics.localSearches++;rows=[...g.entries.keys()].filter(k=>r.d.has(k)).map(k=>[eid,k,r.d.get(k),r.meters.get(k)]);}else rows=await this.#overlay(pid,eid,request);
   for(const row of rows){const sourcePid=portals.entries.get(row[1]);if(!sourcePid)fail('partition_shortcut_entry');improve(row[1],s+row[2],m+row[3],{partition:pid,exit:eid},sourcePid);}
   if(evaluationDirty&&this.metrics.overlaySearchStates-lastEvaluated>=32)await evaluate();
  }
  await evaluate();
  // batchPoints may have two directed snaps of the same physical origin.
  // Their exact costs are already known. Reconstruct only the winner, keeping
  // the same seconds/meters ordering used by batchPoints below. Ordinary
  // batchNodes callers still receive every requested route.
  const winners=new Map();if(alternativeGroups)for(let i=0;i<origins.length;i++){const o=origins[i],b=best.get(o);if(!finite(b?.seconds))continue;const group=alternativeGroups[i],previous=winners.get(group);if(previous===undefined||b.seconds<best.get(origins[previous]).seconds||b.seconds===best.get(origins[previous]).seconds&&b.meters<best.get(origins[previous]).meters)winners.set(group,i);}
  const result=Array(origins.length),ordered=origins.map((o,i)=>({o,i,pid:this.owner(o)})).sort((a,b)=>a.pid.localeCompare(b.pid));
  for(const {o,i,pid} of ordered){if(localTrapped.has(o)){result[i]={origin:o,reachable:false,reason:'graph_local_no_legal_exit',graphVersion:this.manifest.graphVersion};continue;}if(disconnected.has(o)){result[i]={origin:o,reachable:false,reason:'graph_weak_component_disconnected',graphVersion:this.manifest.graphVersion};continue;}const b=best.get(o);if(!finite(b.seconds)){result[i]={origin:o,reachable:false,reason:'graph_disconnected',graphVersion:this.manifest.graphVersion};continue;}
   if(alternativeGroups&&winners.get(alternativeGroups[i])!==i){result[i]={origin:o,reachable:false,reason:'internal_alternative_not_selected',graphVersion:this.manifest.graphVersion};continue;}
   const originTree=trees.get(pid)??await makeTree(pid),originGraph=await this.#graph(pid,request),edgeRows=[],coordinates=[{...(o.startPoint??originGraph.nodes.get(o.nodeId))}],used=new Set([pid]);let currentPid=pid,r=originTree,edge=b.edge,last=o.nodeId,previous=o.incomingEdge??null,hops=0;
   if(o.incomingEdge!==undefined){const g=originGraph,e=g.edges.get(o.incomingEdge)??g.entries.get(o.incomingEdge),shift=g.entries.has(o.incomingEdge)?2:0;edgeRows.push({id:e[0],...speedFields(g,e,g.entries.has(e[0])),way:e[5+shift],ordinal:e[6+shift],direction:e[7+shift],seconds:(costs.get(e[0])??e[3])*o.initialFraction,distanceMeters:e[4]*o.initialFraction,partial:true});coordinates.push({...g.nodes.get(o.nodeId)});}
   while(edge!==null){if(++hops>100000)fail('partition_route_path_limit');const g=await this.#graph(currentPid,request),e=g.edges.get(edge);if(!e||e[1]!==last||previous!==null&&g.bans.has(previous+':'+edge))fail('partition_route_path_invalid');edgeRows.push({id:e[0],...speedFields(g,e),way:e[5],ordinal:e[6],direction:e[7],seconds:costs.get(e[0])??e[3],distanceMeters:e[4]});last=e[2];coordinates.push({...g.nodes.get(last)});previous=e[0];
    if(g.exits.has(e[0])){const t=trace.get(e[0]);if(!t)fail('partition_trace_missing');currentPid=t.partition;used.add(currentPid);const ng=await this.#graph(currentPid,request);r=t.exit===null?root:unpackTree(currentPid,ng,t.exit,e[0]);edge=r.next.get(e[0]);if(edge===undefined)fail('partition_trace_unreachable');}
    else edge=r.next.get(e[0]);if(edge===undefined)fail('partition_trace_missing');
   }
   if(last!==target.nodeId)fail('partition_route_wrong_destination');if(target.finish){const e=dest.edges.get(target.finish.edge);if(previous!==null&&dest.bans.has(previous+':'+e[0]))fail('partition_destination_turn_invalid');edgeRows.push({id:e[0],...speedFields(dest,e),way:e[5],ordinal:e[6],direction:e[7],seconds:(costs.get(e[0])??e[3])*target.finish.fraction,distanceMeters:e[4]*target.finish.fraction,partial:true});coordinates.push({...target.finish.point});}const seconds=edgeRows.reduce((s,e)=>s+e.seconds,0),meters=edgeRows.reduce((s,e)=>s+e.distanceMeters,0);
   if(Math.abs(seconds-b.seconds)>1e-6*Math.max(1,seconds)||Math.abs(meters-b.meters)>1e-6*Math.max(1,meters))fail('partition_shortcut_unpacked_mismatch');
   result[i]={origin:o,reachable:true,seconds,distanceMeters:meters,graphVersion:this.manifest.graphVersion,trafficRevision,edgeSequence:edgeRows,geometry:geometry?coordinates:null,partitions:[...used],estimated:true,certifiedEta:false};
  }
  return {routes:result,graphVersion:this.manifest.graphVersion,trafficRevision,tenant_id:scope.tenant_id,company_id:scope.company_id,totalMs:performance.now()-started,requestResidentBytes:request.bytes,requestPeakResidentBytes:request.peakBytes,diagnostics:this.diagnostics()};
 }
 async addressAccessContext(input,{radiusMeters=100,requestContext=null,address=null,role='destination'}={}){
  const p=point(input),access=this.manifest.accessContext;
  if(access?.schema!==NATIONAL_ACCESS_V1||access.fullPublication!==true||!finite(radiusMeters)||radiusMeters<=0||radiusMeters>250)fail('address_context_incomplete');
  const latPad=(radiusMeters+1)/111195,lonPad=latPad/Math.cos(p.latitude*Math.PI/180),bounds=this.manifest.tree[this.manifest.root]?.bbox;
  if(!bounds||!contains(bounds,{longitude:p.longitude-lonPad,latitude:p.latitude-latPad})||!contains(bounds,{longitude:p.longitude+lonPad,latitude:p.latitude+latPad}))fail('address_context_incomplete');
  const ids=[],visit=k=>{const n=this.manifest.tree[k];if(!n||!contains(n.snapBbox??n.bbox,p,Math.max(latPad,lonPad)))return;if(n.partition)ids.push(n.partition);else for(const c of n.children??[])visit(c);};visit(this.manifest.root);
  if(!ids.length||ids.length>32)fail('address_context_partition_limit');
  const segments=new Map(),negative=new Map(),bans=new Set(),request=requestContext??{graphs:new Map(),objects:new Map(),lru:new Map(),bytes:0,peakBytes:0,pinnedGraph:null},x=Math.floor(p.longitude/.002),y=Math.floor(p.latitude/.002),gridRadius=Math.max(1,Math.ceil(Math.max(latPad,lonPad)/.002));
  for(const pid of ids){const g=await this.#graph(pid,request);if(g.access?.revision!==access.revision)fail('access_partition_revision');const candidates=new Map();for(let dx=-gridRadius;dx<=gridRadius;dx++)for(let dy=-gridRadius;dy<=gridRadius;dy++){for(const e of g.grid.get((x+dx)+':'+(y+dy))??[])candidates.set(e[0],e);for(const n of g.access.grid.get((x+dx)+':'+(y+dy))??[])negative.set(n[0]+':'+n[1],n);}for(const e of g.long)candidates.set(e[0],e);for(const n of g.access.long)negative.set(n[0]+':'+n[1],n);
   for(const e of candidates.values()){const a=g.nodes.get(e[1]),b=g.nodes.get(e[2]),shift=g.entries.has(e[0])?2:0,way=e[5+shift];segments.set(e[0],{edge:e[0],...speedFields(g,e,g.entries.has(e[0])),way,ordinal:e[6+shift],direction:e[7+shift],from:{nodeId:e[1],...a},to:{nodeId:e[2],...b},seconds:e[3],lengthMeters:e[4],tags:g.access.ways.get(way)});}for(const b of g.bans)bans.add(b);
  }
  if(segments.size>8192||negative.size>150000)fail('address_context_size_limit');
  const terminalRows=address?await readNationalTerminalContextV1({input:{...p,address},manifest:this.manifest,storage:this.storage,cache:this.cache,metrics:this.metrics,maxWays:8}):null;
  let legacyTerminalSnap=null;if(terminalRows?.length){try{legacyTerminalSnap=await resolveNationalTerminalV1({input:{...p,address},manifest:this.manifest,storage:this.storage,segments:[...segments.values()],negative:[...negative.values()],role,cache:this.cache,metrics:this.metrics,sourceRows:terminalRows});}catch{}
   for(const r of terminalRows)for(const e of r.edges)segments.set(e.edge,{...e,tags:r.frontageTags,way:r.way});
  }
  if(segments.size>8192)fail('address_context_size_limit');
  this.metrics.addressContextQueries=(this.metrics.addressContextQueries??0)+1;
  return {graphVersion:this.manifest.graphVersion,revision:access.revision,center:{latitude:p.latitude,longitude:p.longitude},radiusMeters,complete:true,segments:[...segments.values()],negative:[...negative.values()],bans:[...bans],barrierCoverage:null,barriers:[],vehicleProfileKey:this.manifest.vehicleProfileKey??null,terminalRows:terminalRows??[],terminalWayIds:(terminalRows??[]).map(r=>r.way),legacyTerminalSnap};
 }
 async addressRoutePoint({candidate,address,role,context}){
  if(context.graphVersion!==this.manifest.graphVersion||context.revision!==this.manifest.accessContext.revision||candidate.status!=='proven')fail('address_context_changed');
  verifyOfficialAddressCandidateV1(candidate,{graphVersion:context.graphVersion,revision:context.revision,role,addressId:address.id});
  if(!candidate.wayIds.some(w=>context.terminalWayIds.includes(w))){await this.snapPoint(candidate.point);return candidate.point;}
  const frontageOverride=createOfficialTerminalFrontageV1({candidate,graphVersion:context.graphVersion,revision:context.revision,role,addressId:address.id});
  const snap=await resolveNationalTerminalV1({input:{...candidate.point,address:address.address},manifest:this.manifest,storage:this.storage,segments:context.segments.filter(s=>!context.terminalWayIds.includes(s.way)),negative:context.negative,role,cache:this.cache,metrics:this.metrics,sourceRows:context.terminalRows,frontageOverride});
  if(!snap)fail('terminal_frontage_unproven');return createOfficialAddressRoutePointV1({point:candidate.point,snap,graphVersion:context.graphVersion,revision:context.revision,role,candidateId:candidate.id});
 }
 async configuredSiteRoutePoint({point,binding,role}){
  if(!['origin','destination'].includes(role))fail('configured_site_role_invalid');
  const input=configuredSiteInputV1({point,binding,scope:this.scope,manifest:this.manifest});
  const context=await this.addressAccessContext(point,{address:input.address,role});
  const frontageOverride=createConfiguredSiteFrontageV1({input,binding,scope:this.scope,manifest:this.manifest,context});
  const snap=await resolveNationalTerminalV1({input,manifest:this.manifest,storage:this.storage,
   segments:context.segments.filter(s=>!context.terminalWayIds.includes(s.way)),negative:context.negative,role,
   cache:this.cache,metrics:this.metrics,sourceRows:context.terminalRows,frontageOverride});
  if(!snap)fail('configured_site_snap_unproven');
  return createConfiguredSiteRoutePointV1({point,snap,scope:this.scope,manifest:this.manifest,role,frontage:frontageOverride});
 }
 async snapPoint(input,request=null,prior=null,nearPickup=null,gpsRoadContext=false,terminalRole=null){
  const site=readConfiguredSiteRoutePointV1(input,{scope:this.scope,graphVersion:this.manifest.graphVersion,revision:this.manifest.accessContext?.revision,role:terminalRole});if(site)return site;
  const official=readOfficialAddressRoutePointV1(input,{graphVersion:this.manifest.graphVersion,revision:this.manifest.accessContext?.revision,role:terminalRole});if(official)return official;
  // Preserve ordinary precise admission, including an exact legal junction.
  // A genuine no-road result may request bounded practical matching. A
  // multi-road result can only gain the tightly proven common-junction path;
  // all ordinary forbidden/stale gates remain authoritative.
  if(gpsRoadContext&&input.access?.kind==='gps'&&input.access.accuracyMeters<=5){
   try{return await this.snapPoint(input,request,prior,nearPickup,false);}
   catch(error){if(!['access_no_road_within_accuracy','access_parallel_or_junction_ambiguity'].includes(error.message))throw error;}
  }
  this.metrics.accessQueries++;
  const accessRequired=this.manifest.accessContext?.schema===NATIONAL_ACCESS_V1;
  const p=point(input),ids=[],nearRadius=(nearPickup||gpsRoadContext)&&p.access?.kind==='gps'&&finite(p.access.accuracyMeters)&&p.access.accuracyMeters>0?Math.max(50,p.access.accuracyMeters):null;
  const latPad=nearRadius==null?0:(nearRadius+1)/111195,lonPad=nearRadius==null?0:latPad/Math.cos(p.latitude*Math.PI/180),padding=nearRadius==null?accessRequired?(input.address?.003:.0006):.000002:Math.max(.0006,latPad,lonPad);
  const rootBounds=this.manifest.tree[this.manifest.root]?.bbox,completeNearContext=nearRadius!=null&&this.manifest.accessContext?.fullPublication===true&&rootBounds&&p.longitude-lonPad>=rootBounds[0]&&p.longitude+lonPad<=rootBounds[2]&&p.latitude-latPad>=rootBounds[1]&&p.latitude+latPad<=rootBounds[3];
  if(nearRadius!=null&&!completeNearContext)fail(gpsRoadContext?'access_driver_gps_context_incomplete':'access_near_pickup_context_incomplete');
  const visit=k=>{const n=this.manifest.tree[k];if(!n||!contains(n.snapBbox??n.bbox,p,padding))return;if(n.partition)ids.push(n.partition);else for(const c of n.children??[])visit(c);};visit(this.manifest.root);if(!ids.length)fail('partition_snap_coverage');if(ids.length>32)fail('partition_snap_overlap_limit');
  const nearNodes=new Map(),segments=new Map();
  const accessSegments=new Map(),negative=new Map(),accessBans=new Set();
  const gridRadius=nearRadius==null?1:Math.max(1,Math.ceil(Math.max(latPad,lonPad)/.002));
  for(const pid of ids){const g=await this.#graph(pid,request),x=Math.floor(p.longitude/.002),y=Math.floor(p.latitude/.002),candidates=new Map();for(let dx=-gridRadius;dx<=gridRadius;dx++)for(let dy=-gridRadius;dy<=gridRadius;dy++)for(const e of g.grid.get((x+dx)+':'+(y+dy))??[])candidates.set(e[0],e);for(const e of g.long)candidates.set(e[0],e);
   if(accessRequired){
    if(!g.access||g.access.revision!==this.manifest.accessContext.revision)fail('access_partition_revision');
    for(const e of candidates.values()){const a=g.nodes.get(e[1]),b=g.nodes.get(e[2]),shift=g.entries.has(e[0])?2:0,way=e[5+shift];accessSegments.set(e[0],{edge:e[0],...speedFields(g,e,g.entries.has(e[0])),way,ordinal:e[6+shift],direction:e[7+shift],from:{nodeId:e[1],...a},to:{nodeId:e[2],...b},seconds:e[3],lengthMeters:e[4],tags:g.access.ways.get(way)});}
    for(let dx=-gridRadius;dx<=gridRadius;dx++)for(let dy=-gridRadius;dy<=gridRadius;dy++)for(const n of g.access.grid.get((x+dx)+':'+(y+dy))??[])negative.set(n[0]+':'+n[1],n);
    for(const n of g.access.long)negative.set(n[0]+':'+n[1],n);
    for(const ban of g.bans)accessBans.add(ban);
    continue;
   }
   for(const e of candidates.values()){const a=g.nodes.get(e[1]),b=g.nodes.get(e[2]);for(const [n,c]of [[e[1],a],[e[2],b]])if(distance(c,p)<=.1)nearNodes.set(n,{nodeId:n,...c});
    const cos=Math.cos(p.latitude*Math.PI/180),ax=(a.longitude-p.longitude)*cos,ay=a.latitude-p.latitude,bx=(b.longitude-p.longitude)*cos,by=b.latitude-p.latitude,dx=bx-ax,dy=by-ay,len=dx*dx+dy*dy,t=len?Math.max(0,Math.min(1,-(ax*dx+ay*dy)/len)):0,q={longitude:a.longitude+(b.longitude-a.longitude)*t,latitude:a.latitude+(b.latitude-a.latitude)*t};if(distance(q,p)>.1)continue;
    const physical=[Math.min(e[1],e[2]),Math.max(e[1],e[2])].join(':');if(!segments.has(physical))segments.set(physical,new Map());segments.get(physical).set(e[0],{edge:e[0],...speedFields(g,e,g.entries.has(e[0])),from:{nodeId:e[1],...a},to:{nodeId:e[2],...b},fraction:t,seconds:e[3],meters:e[4],point:q});
   }
  }
  let frontage=null;
  if(accessRequired&&input.address){try{frontage=resolvePracticalFrontageV1({input:p,segments:[...accessSegments.values()],graphVersion:this.manifest.graphVersion,revision:this.manifest.accessContext.revision});}catch(error){
   // Only an actual journey endpoint can request a retained source-road
   // destination exception. Ordinary GPS and all transit searches stay closed.
   if(terminalRole&&error.message==='access_address_street_unmatched'){
    const terminal=await resolveNationalTerminalV1({input:p,manifest:this.manifest,storage:this.storage,segments:[...accessSegments.values()],negative:[...negative.values()],role:terminalRole,cache:this.cache,metrics:this.metrics});if(terminal)return terminal;
   }throw error;
  }}
  if(accessRequired){const args={input:frontage?frontage.point:p,segments:[...accessSegments.values()],negative:[...negative.values()],graphVersion:this.manifest.graphVersion,revision:this.manifest.accessContext.revision};
   if(gpsRoadContext&&!frontage){
    try{const result=resolveDriverGpsRoadAccessV1({...args,completeContext:completeNearContext,prior,bans:accessBans});if(result.continuityOnly){this.metrics.driverContinuityAttempts++;this.metrics.driverContinuityAccepted++;}this.metrics.accessStaticAccepted++;return result;}
    catch(error){if(prior&&error.message.startsWith('access_continuity_')){this.metrics.driverContinuityAttempts++;this.metrics.driverContinuityRejected++;}throw error;}
   }
   try{let result=resolveRoadAccessV1(args);
   if(frontage){
    // A street boundary may project onto its real shared graph junction.
    // resolveRoadAccess already proves all roads meet that exact node and
    // checks access/layer/negative evidence. An additional legal street name
    // at that node does not invalidate the selected named frontage. Segment
    // snaps still require an exact street match; no nearby-road fallback.
    if(!result.accessEvidence.wayIds.some(id=>frontage.wayIds.includes(id))||result.kind!=='node'&&result.accessEvidence.wayIds.some(id=>!frontage.wayIds.includes(id)))fail('access_address_snap_street_conflict');
    result={...result,accessEvidence:{...result.accessEvidence,kind:'address_frontage',frontage}};
   }
   else if(prior&&p.access?.kind==='gps'){
    const sameFix=JSON.stringify(continuityAnchor(p,result,this.manifest.graphVersion,this.manifest.accessContext.revision))===JSON.stringify(prior);
    if(!sameFix){this.metrics.driverContinuityAttempts++;try{result=resolveDriverContinuityV1({...args,prior,bans:accessBans});this.metrics.driverContinuityAccepted++;}catch(e){this.metrics.driverContinuityRejected++;throw e;}}
   }
   else if(p.access?.kind==='gps'&&p.access.accuracyMeters>5&&!provenUnnamedServiceExitV1(result,args.segments,accessBans))fail('access_gps_street_confirmation_required');
   this.metrics.accessStaticAccepted++;return result;}catch(e){
    let error=e;
    if(prior&&['access_gps_street_confirmation_required','access_parallel_or_junction_ambiguity','access_outlier_or_adjacent_road_ambiguity','access_junction_transition_unproven','access_direction_unproven'].includes(e.message)){this.metrics.driverContinuityAttempts++;try{const result=resolveDriverContinuityV1({...args,prior,bans:accessBans});this.metrics.driverContinuityAccepted++;return result;}catch(cause){this.metrics.driverContinuityRejected++;error=cause;}}
    if(nearPickup&&['access_gps_stale_or_accuracy','access_gps_street_confirmation_required','access_parallel_or_junction_ambiguity','access_outlier_or_adjacent_road_ambiguity','access_junction_transition_unproven','access_direction_unproven'].includes(e.message))return resolveNearPickupRoadAccessV1({...args,pickup:nearPickup.input,pickupSnap:nearPickup.snap,completeContext:completeNearContext});
    throw error;
   }}
  if(nearNodes.size>1)fail('partition_snap_node_ambiguous');if(nearNodes.size===1)return {kind:'node',node:[...nearNodes.values()][0],graphVersion:this.manifest.graphVersion};
  if(segments.size!==1)fail(segments.size?'partition_snap_ambiguous':'partition_snap_outside_safe_access');return {kind:'segment',alternatives:[...[...segments.values()][0].values()],graphVersion:this.manifest.graphVersion};
 }
 async batchPoints({scope,origins,target,...options}){
  if(!token(scope?.tenant_id)||!token(scope.company_id)||scope.graphVersion&&scope.graphVersion!==this.manifest.graphVersion)fail('partition_route_scope');
  const accessRequest={graphs:new Map(),objects:new Map(),lru:new Map(),bytes:0,peakBytes:0,pinnedGraph:null};
  if(!Array.isArray(origins)||origins.length>500)fail('partition_point_batch_limit');const destination=await this.snapPoint(target,accessRequest,null,null,false,'destination'),snaps=[];
  for(const o of origins){try{const a=o.access,key=a?.kind==='gps'&&typeof a.continuityKey==='string'&&/^[a-zA-Z0-9_.:-]{1,160}$/.test(a.continuityKey)?JSON.stringify([scope?.tenant_id,scope?.company_id,this.manifest.graphVersion,this.manifest.accessContext?.revision,a.continuityKey]):null;
   // The general uncertainty policy is exclusive to server-owned ASAP origin
   // evaluation. A planned/address origin and an ordinary route do not opt in.
   const gpsRoadContext=options.gpsRoadContext===true&&a?.kind==='gps'&&a.accuracyMeters>0&&a.accuracyMeters<=100;
   const nearPickup=key&&a.accuracyMeters>5&&distance(o,target)<=100&&destination.accessEvidence?.kind==='address_frontage'?{input:target,snap:destination}:null,s=await this.snapPoint(o,accessRequest,key?this.continuityStore.get(key):null,nearPickup,gpsRoadContext,'origin');
   snaps.push(s);if(key&&!s.continuityOnly&&s.accessEvidence?.kind!=='driver_gps_road_context'&&a.accuracyMeters<=5){for(const[k,v]of this.continuityStore)if(Date.now()-v.input.access.capturedAt>15000)this.continuityStore.delete(k);if(!this.continuityStore.has(key)&&this.continuityStore.size>=512)this.continuityStore.delete(this.continuityStore.keys().next().value);this.continuityStore.set(key,continuityAnchor(o,s,this.manifest.graphVersion,this.manifest.accessContext.revision));}
  }catch(e){snaps.push({kind:'denied',reason:e.message});}}
  const alternatives=destination.kind==='node'?[{node:destination.node}]:destination.kind==='terminal'?destination.alternatives:destination.alternatives.map(a=>({node:{...a.from,finish:{edge:a.edge,fraction:a.fraction,point:a.point}},segment:a}));const chosen=origins.map((origin,i)=>({origin,reachable:false,reason:snaps[i].reason??'graph_disconnected',graphVersion:this.manifest.graphVersion}));
  for(const d of alternatives){const nodes=[],indices=[];snaps.forEach((s,i)=>{if(s.kind==='node'){nodes.push(s.node);indices.push(i);}else if(s.kind==='segment')for(const a of s.alternatives){nodes.push({...a.to,incomingEdge:a.edge,initialFraction:1-a.fraction,startPoint:a.point});indices.push(i);if(d.segment&&a.edge===d.segment.edge&&a.fraction<=d.segment.fraction&&!options.closed?.has(a.edge)){const fraction=d.segment.fraction-a.fraction,seconds=(options.costs?.get(a.edge)??a.seconds)*fraction,candidate={origin:origins[i],reachable:true,seconds,distanceMeters:a.meters*fraction,graphVersion:this.manifest.graphVersion,trafficRevision:options.trafficRevision??'static',edgeSequence:[{id:a.edge,way:a.way,...(a.partitionId?{partitionId:a.partitionId}:{}),...(a.ordinal!=null?{ordinal:a.ordinal}:{}),...(a.direction!=null?{direction:a.direction}:{}),...(a.speedProfile?{speedProfile:a.speedProfile,speedProfileKey:a.speedProfileKey}:{}),seconds,distanceMeters:a.meters*fraction,partial:true}],geometry:[a.point,d.segment.point],accessEvidence:{origin:s.accessEvidence??null,destination:destination.accessEvidence??null},partitions:[this.owner(a.from)],estimated:true,certifiedEta:false};if(!chosen[i].reachable||seconds<chosen[i].seconds)chosen[i]=candidate;}}});
   // Terminal approach/exit costs vary by portal. They must participate in
   // final route comparison; do not prune these using core-only costs.
   snaps.forEach((s,i)=>{if(s.kind==='terminal')for(const a of s.alternatives){nodes.push({...a.node,terminalLeg:a.terminalLeg});indices.push(i);}});
   if(nodes.length>2048)fail('terminal_batch_limit');
   const terminalJourney=destination.kind==='terminal'||snaps.some(s=>s.kind==='terminal');
   const batch=await this.batchNodes({scope,origins:nodes,target:d.node,...options,requestContext:accessRequest,...(!terminalJourney?{alternativeGroups:indices}:{})});for(let j=0;j<batch.routes.length;j++){let c=batch.routes[j];const i=indices[j];
    if(c.reachable&&terminalJourney){const prefix=nodes[j].terminalLeg,suffix=d.terminalLeg,legs=[prefix,suffix].filter(Boolean);const geometry=[...(prefix?.geometry??[]),...(c.geometry??[]),...(suffix?.geometry??[])].filter((p,k,ps)=>!k||p.latitude!==ps[k-1].latitude||p.longitude!==ps[k-1].longitude);c={...c,seconds:c.seconds+legs.reduce((n,l)=>n+l.seconds,0),distanceMeters:c.distanceMeters+legs.reduce((n,l)=>n+l.distanceMeters,0),edgeSequence:[...(prefix?.edgeSequence??[]),...c.edgeSequence,...(suffix?.edgeSequence??[])],geometry};}
    if(c.reachable&&(!chosen[i].reachable||c.seconds<chosen[i].seconds||c.seconds===chosen[i].seconds&&c.distanceMeters<chosen[i].distanceMeters))chosen[i]={...c,origin:origins[i],accessEvidence:{origin:snaps[i].accessEvidence??null,destination:destination.accessEvidence??null}};}
  }
  for(let i=0;i<chosen.length;i++)if(chosen[i].reachable&&snaps[i].accessEvidence?.kind==='driver_near_pickup'){
   const proof=snaps[i].accessEvidence.nearPickup,f=destination.accessEvidence.frontage;
   chosen[i].nearPickupEvidence={schema:'fluxidi-near-pickup-road-v1',tenant_id:scope.tenant_id,company_id:scope.company_id,graphVersion:this.manifest.graphVersion,accessContextRevision:this.manifest.accessContext.revision,origin:structuredClone(origins[i]),pickup:structuredClone(target),pickupFrontage:{schema:f.schema,graphVersion:f.graphVersion,revision:f.revision,point:structuredClone(f.point),wayIds:[...f.wayIds]},...structuredClone(proof)};
  }
  for(let i=0;i<chosen.length;i++)if(chosen[i].reachable&&snaps[i].accessEvidence?.kind==='driver_gps_road_context'){
   chosen[i].gpsRoadEvidence={schema:'fluxidi-driver-gps-road-v1',tenant_id:scope.tenant_id,company_id:scope.company_id,graphVersion:this.manifest.graphVersion,accessContextRevision:this.manifest.accessContext.revision,origin:structuredClone(origins[i]),pickup:structuredClone(target),...structuredClone(snaps[i].accessEvidence.gpsRoad)};
  }
  return {routes:chosen,graphVersion:this.manifest.graphVersion,diagnostics:this.diagnostics()};
 }
 // Navigation describes the already selected directed edges. It performs no
 // new path selection, access grant, provider request or change of route cost.
 async describeRouteEdges({scope,edges}){
  if(scope?.graphVersion!==this.manifest.graphVersion||!token(scope?.tenant_id)||!token(scope?.company_id)||!Array.isArray(edges)||edges.length>20000)fail('navigation_edge_scope');
  const tags=t=>{
   if(!t||!Array.isArray(t.streetNames))fail('navigation_road_metadata_missing');
   const result={streetNames:t.streetNames.filter(v=>typeof v==='string'&&v.length<=500).slice(0,16)};
   for(const key of ['highway','ref','junction','lanes','oneway'])if(typeof t[key]==='string'&&t[key].length<=500||key==='oneway'&&[0,1,-1].includes(t[key]))result[key]=t[key];
   return result;
  };
  this.#manifestHash??=sha(new TextEncoder().encode(JSON.stringify(this.manifest)));
  const manifestSha256=await this.#manifestHash,terminalReader=createTerminalNavigationReaderV1({manifest:this.manifest,storage:this.storage,cache:this.cache,metrics:this.metrics});
  const rows=[];let g=null,previous=null,previousTerminal=null;
  for(const selected of edges){
   if(selected.terminalObject){
    const described=await terminalReader.describe(selected,previous);
    described.row.terminalMetadata.graphManifestSha256=manifestSha256;
    rows.push(described.row);previous=described.row;previousTerminal=described.source;continue;
   }
   if(!this.#parts.has(selected.partitionId)||!id(selected.id))fail('navigation_edge_partition');
   if(previousTerminal?.bans.has(previous.id+':'+selected.id))fail('navigation_turn_forbidden');
   if(g?.id!==selected.partitionId)g=await this.#graph(selected.partitionId,null);
   const edge=g.edges.get(selected.id)??g.entries.get(selected.id),shift=g.entries.has(selected.id)?2:0;
   if(!edge||edge[5+shift]!==selected.way||edge[6+shift]!==selected.ordinal||edge[7+shift]!==selected.direction||previous&&previous.toNode!==edge[1])fail('navigation_edge_binding');
   const from=g.nodes.get(edge[1]),to=g.nodes.get(edge[2]);
   if(!from||!to)fail('navigation_edge_geometry');
   const all=g.out.get(edge[1])??[];
   const options=all.filter(e=>previous==null||!g.bans.has(previous.id+':'+e[0]));
   if(previous&&g.bans.has(previous.id+':'+selected.id))fail('navigation_turn_forbidden');
   const complete=options.length<=32;
   const negativeAtNode=[...(g.access?.grid.get(Math.floor(from.longitude/.002)+':'+Math.floor(from.latitude/.002))??[]),...(g.access?.long??[])]
    .some(n=>n[7]===edge[1]||n[8]===edge[1]);
   const physicalComplete=g.own.has(edge[1])&&all.length<=32&&!negativeAtNode;
   const row={id:selected.id,way:selected.way,ordinal:selected.ordinal,direction:selected.direction,partitionId:selected.partitionId,fullDistanceMeters:edge[4],
    fromNode:edge[1],toNode:edge[2],from:{...from},to:{...to},tags:tags(g.access?.ways.get(selected.way)),
    junctionComplete:complete,physicalJunctionComplete:physicalComplete,
    physicalOptions:physicalComplete?all.map(e=>({id:e[0],way:e[5],toNode:e[2],to:{...g.nodes.get(e[2])},turnAllowed:previous==null||!g.bans.has(previous.id+':'+e[0]),tags:tags(g.access?.ways.get(e[5]))})):[],
    options:complete?options.map(e=>({id:e[0],way:e[5],toNode:e[2],to:{...g.nodes.get(e[2])},tags:tags(g.access?.ways.get(e[5]))})):[]};
   rows.push(row);previous=row;previousTerminal=null;
  }
  if(new TextEncoder().encode(JSON.stringify(rows)).byteLength>8*1024*1024)fail('navigation_metadata_limit');
  return {schema:'fluxidi-navigation-road-metadata-v1',graphVersion:this.manifest.graphVersion,rows};
 }
 diagnostics(){return {...this.metrics,continuityAnchors:this.continuityStore.size,continuitySerializedBytes:new TextEncoder().encode(JSON.stringify([...this.continuityStore])).byteLength,cache:this.cache.diagnostics()};}
}
