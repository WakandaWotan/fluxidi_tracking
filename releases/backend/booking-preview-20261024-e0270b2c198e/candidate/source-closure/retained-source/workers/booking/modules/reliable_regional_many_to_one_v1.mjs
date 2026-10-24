// Prepared, directed edge-state search for the existing immutable road graph.
// This computes static road evidence, never a regional pickup-ETA certificate.
const stable=v=>JSON.stringify(v,(_,x)=>x&&typeof x==='object'&&!Array.isArray(x)?Object.fromEntries(Object.entries(x).sort(([a],[b])=>a.localeCompare(b))):x);
class Heap{
 a=[];
 push(v){let i=this.a.length;this.a.push(v);while(i){const p=(i-1)>>1;if(this.a[p][0]<=v[0])break;this.a[i]=this.a[p];i=p;}this.a[i]=v;}
 pop(){const v=this.a[0],last=this.a.pop();if(this.a.length){let i=0;while(i*2+1<this.a.length){let c=i*2+1;if(c+1<this.a.length&&this.a[c+1][0]<this.a[c][0])c++;if(last[0]<=this.a[c][0])break;this.a[i]=this.a[c];i=c;}this.a[i]=last;}return v;}
}
const optionsClosed=(graph,options)=>{
 if(!options||typeof options!=='object'||Array.isArray(options)||Object.entries(options).some(([k,v])=>!['avoidFerries','avoidMotorways','avoidTolls'].includes(k)||typeof v!=='boolean'))throw Error('route_options_unsupported');
 return new Set(graph.edges.filter(e=>e.disabled||options.avoidFerries&&e.kind==='ferry'||options.avoidMotorways&&e.kind==='motorway'||options.avoidTolls&&e.toll===true).map(e=>e.id));
};
export function createRegionalManyToOneV1({graph,core,coordinates,clock=Date.now,maxEntries=8,maxBytes=8388608,ttlMs=60000}){
 if(!graph?.reverse||!core?.routeEvidence||coordinates?.length!==graph.nodes||!Number.isInteger(maxEntries)||maxEntries<1||maxEntries>32||!Number.isSafeInteger(maxBytes)||maxBytes<1||maxBytes>16777216||!Number.isFinite(ttlMs)||ttlMs<=0||ttlMs>60000)throw Error('regional_preparation_invalid');
 const points=structuredClone(coordinates),roads=structuredClone(graph.edges);
 const cache=new Map();let bytes=0;
 const metrics={targetPreparations:0,targetCacheHits:0,targetCacheMisses:0,reverseSearches:0,reverseSettled:0,routeQueries:0,forwardTieFallbacks:0,evidenceHashes:0,providerCalls:0};
 function prepare({target,scope,options={},trafficRevision='static',graphVersion=graph.version}){
  if(graphVersion!==graph.version)throw Error('osm_graph_revision_stale');
  if(!scope?.tenant_id||!scope.company_id||!Number.isInteger(target)||target<0||target>=graph.nodes||typeof trafficRevision!=='string'||!trafficRevision||trafficRevision.length>256)throw Error('regional_route_context_invalid');
  const closed=optionsClosed(graph,options),now=clock();
  for(const[k,row]of cache)if(now<row.at||now>=row.until){bytes-=row.bytes;cache.delete(k);}
  const key=stable({graphVersion,profile:graph.profile,target,options,trafficRevision,tenant:scope.tenant_id,company:scope.company_id,policy:scope.policyRevision??null});
  metrics.targetPreparations++;
  if(cache.has(key)){metrics.targetCacheHits++;return cache.get(key).value;}
  metrics.targetCacheMisses++;metrics.reverseSearches++;
  const dist=new Float64Array(graph.reverse.length);dist.fill(Infinity);
  const nextState=new Int32Array(dist.length);nextState.fill(-1);
  const nextEdge=new Int32Array(dist.length);nextEdge.fill(-1);
  const nextTurn=new Float64Array(dist.length),heap=new Heap(),targets=new Set(graph.targetStates[target]);
  for(const state of targets){dist[state]=0;heap.push([0,state]);}
  while(heap.a.length){const[d,s]=heap.pop();if(d!==dist[s])continue;metrics.reverseSettled++;
   for(const t of graph.reverse[s]){if(closed.has(t.edge))continue;const n=d+graph.edges[t.edge].minimum+t.minimumTurn;
    if(n<dist[t.from]){dist[t.from]=n;nextState[t.from]=s;nextEdge[t.from]=t.edge;nextTurn[t.from]=t.minimumTurn;heap.push([n,t.from]);}}
  }
  // Equal/fractionally near-equal alternatives can change forward floating-point
  // tie order. Keep the existing forward core as authority for those routes.
  const ambiguous=new Uint8Array(dist.length),alternatives=new Uint8Array(dist.length);
  const tolerance=s=>Number.EPSILON*32*dist.length*Math.max(1,Math.abs(dist[s]));
  for(let to=0;to<graph.reverse.length;to++)for(const t of graph.reverse[to]){
   if(closed.has(t.edge)||!Number.isFinite(dist[to])||!Number.isFinite(dist[t.from]))continue;
   if(Math.abs(dist[to]+graph.edges[t.edge].minimum+t.minimumTurn-dist[t.from])<=tolerance(t.from)){
    if(alternatives[t.from])ambiguous[t.from]=1;alternatives[t.from]=1;
   }
  }
  const size=dist.byteLength+nextState.byteLength+nextEdge.byteLength+nextTurn.byteLength+ambiguous.byteLength;
  const fixed={tenant_id:scope.tenant_id,company_id:scope.company_id,graphVersion,profile:graph.profile,options:structuredClone(options),leg:'pickup',departureSemantics:'static'};
  const value=Object.freeze({async route(origin){
   if(clock()<now||clock()>=now+ttlMs)throw Error('regional_preparation_expired');
   if(!Number.isInteger(origin)||origin<0||origin>=graph.nodes)throw Error('graph_origin_invalid');
   metrics.routeQueries++;
   if(!Number.isFinite(dist[origin]))throw Error('road_disconnected');
   const context={...fixed,fromNode:origin,toNode:target,from:points[origin],to:points[target]};
   const path=[];let state=origin,tie=false;
   while(!targets.has(state)){
    if(ambiguous[state]||nextState[state]<0||path.length>=dist.length){tie=true;break;}
    path.push({edge:nextEdge[state],turn:nextTurn[state]});state=nextState[state];
   }
   if(tie){metrics.forwardTieFallbacks++;return core.routeEvidence(context);}
   let staticSeconds=0,distanceMeters=0;const geometry=[],edges=[];
   for(const p of path){const e=roads[p.edge];
    if(!Number.isFinite(e.distanceMeters)||e.distanceMeters<0||!Array.isArray(e.geometry)||e.geometry.length<2||e.geometry.some(p=>!Number.isFinite(p.latitude)||!Number.isFinite(p.longitude)||Math.abs(p.latitude)>90||Math.abs(p.longitude)>180))throw Error('road_geometry_unavailable');
    staticSeconds+=e.minimum;staticSeconds+=p.turn;distanceMeters+=e.distanceMeters;
    geometry.push(...e.geometry.slice(geometry.length?1:0));edges.push({id:e.id,seconds:e.minimum+p.turn,distanceMeters:e.distanceMeters});
   }
   if(!path.length)geometry.push(points[origin]);
   const route={staticSeconds,distanceMeters,geometry,edges,evidenceClass:'EXACT_STATIC_ROUTE'};
   const digest=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(stable(context)+'\n'+stable(route)));metrics.evidenceHashes++;
   return {...structuredClone(context),...structuredClone(route),evidenceId:Array.from(new Uint8Array(digest),b=>b.toString(16).padStart(2,'0')).join(''),timestamp:now,validUntil:now+ttlMs,source:'owned-graph',routeScope:'snapped-node-to-node',snapAccessCost:'NOT_INCLUDED'};
  },graphVersion,trafficRevision,target});
  if(size<=maxBytes){while(cache.size&&(cache.size>=maxEntries||bytes+size>maxBytes)){const k=cache.keys().next().value;bytes-=cache.get(k).bytes;cache.delete(k);}cache.set(key,{value,at:now,until:now+ttlMs,bytes:size});bytes+=size;}
  return value;
 }
 return Object.freeze({prepare,diagnostics:()=>({...metrics,cacheEntries:cache.size,cacheBytes:bytes,cacheMaxEntries:maxEntries,cacheMaxBytes:maxBytes})});
}
