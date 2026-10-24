import { DirectedRoadGraph, RoutingEvidenceProvider, certifiedRoadSearch } from './routing_evidence_core.mjs';

const clone = value => structuredClone(value);
const stable = value => JSON.stringify(value, (_, v) => v && !Array.isArray(v) && typeof v === 'object'
  ? Object.fromEntries(Object.entries(v).sort(([a], [b]) => a.localeCompare(b))) : v);
const point = p => p && Number.isFinite(p.latitude) && Math.abs(p.latitude) <= 90 &&
  Number.isFinite(p.longitude) && Math.abs(p.longitude) <= 180;
const meters = (a, b) => {
  const rad = x => x * Math.PI / 180, dlat = rad(b.latitude-a.latitude), dlon = rad(b.longitude-a.longitude);
  const h = Math.sin(dlat/2)**2 + Math.cos(rad(a.latitude))*Math.cos(rad(b.latitude))*Math.sin(dlon/2)**2;
  return 12742000*Math.asin(Math.min(1,Math.sqrt(h)));
};
class Heap {
  a=[];
  push(x) { let i=this.a.length;this.a.push(x);while(i){const p=(i-1)>>1;if(this.a[p][0]<=x[0])break;this.a[i]=this.a[p];i=p;}this.a[i]=x; }
  pop() { const first=this.a[0],last=this.a.pop();if(this.a.length){let i=0;while(i*2+1<this.a.length){let c=i*2+1;if(c+1<this.a.length&&this.a[c+1][0]<this.a[c][0])c++;if(last[0]<=this.a[c][0])break;this.a[i]=this.a[c];i=c;}this.a[i]=last;}return first; }
}

// An adapter for an owned, versioned graph. No claim is made that its static
// costs lower-bound an unrelated provider graph. Geometry is supplied by the
// graph importer; it is never fabricated between snapped road nodes.
export class FluxidiRoutingCore {
  #nodes; #roads; #forward; #cache=new Map(); #inflight=new Map(); #clock; #ttl; #limit; #maxBytes; #bytes=0;
  constructor({ graph, coordinates, clock=Date.now, ttlMs=60000, maxEntries=32, maxBytes=4194304 }) {
    if (!(graph instanceof DirectedRoadGraph) || !Array.isArray(coordinates) || coordinates.length!==graph.nodes ||
        coordinates.some(p=>!point(p)) || !Number.isInteger(maxEntries) || maxEntries<1 || maxEntries>128 ||
        !Number.isFinite(ttlMs) || ttlMs<=0 || ttlMs>3600000 || !Number.isSafeInteger(maxBytes)||maxBytes<1||maxBytes>16777216) throw Error('routing_core_invalid');
    Object.defineProperty(this,'graph',{value:graph});this.#nodes=clone(coordinates);
    this.#roads=graph.edges.map(e=>({distanceMeters:e.distanceMeters,geometry:clone(e.geometry)}));
    this.#clock=clock;this.#ttl=ttlMs;this.#limit=maxEntries;this.#maxBytes=maxBytes;
    this.#forward=Array.from({length:graph.reverse.length},()=>[]);
    graph.reverse.forEach((rows,to)=>rows.forEach(row=>this.#forward[row.from].push({...row,to})));
    this.metrics={queries:0,cacheHits:0,cacheMisses:0,manyToOne:0,staticRoutes:0,providerCalls:0};
  }
  snap(position,{maxDistanceMeters}) {
    if(!point(position)||!Number.isFinite(maxDistanceMeters)||maxDistanceMeters<0)throw Error('snap_invalid');
    let best=null;this.#nodes.forEach((p,node)=>{const distance=meters(position,p);if(distance<=maxDistanceMeters&&(!best||distance<best.distanceMeters))best={node,distanceMeters:distance};});
    if(!best)throw Error('snap_unavailable');return {...best,graphVersion:this.graph.version};
  }
  #closed(options={}) {
    if(!options||typeof options!=='object'||Array.isArray(options)||Object.keys(options).some(k=>!['avoidFerries','avoidMotorways','avoidTolls'].includes(k)||typeof options[k]!=='boolean'))throw Error('route_options_unsupported');
    return new Set(this.graph.edges.filter(e=>options.avoidFerries&&e.kind==='ferry'||options.avoidMotorways&&e.kind==='motorway'||options.avoidTolls&&e.toll===true).map(e=>e.id));
  }
  manyToOne(origins,target,options={}) {
    this.metrics.manyToOne++;const row=this.graph.manyToOne(target,{costs:this.graph.edges.map(e=>e.minimum),closed:this.#closed(options)});
    return origins.map(origin=>({originNode:origin,staticSeconds:row.seconds[origin],graphVersion:this.graph.version}));
  }
  manyToMany(origins,targets,options={}) {return targets.map(target=>this.manyToOne(origins,target,options));}
  #validate(c) {
    if(!c?.tenant_id||!c.company_id||!c.leg||c.graphVersion!==this.graph.version||c.profile!==this.graph.profile||
       !Number.isInteger(c.fromNode)||c.fromNode<0||c.fromNode>=this.graph.nodes||!Number.isInteger(c.toNode)||c.toNode<0||c.toNode>=this.graph.nodes||
       !point(c.from)||!point(c.to)||typeof c.departureSemantics!=='string'||!c.departureSemantics)throw Error('route_context_invalid');
  }
  #route(c) {
    const graph=this.graph,closed=this.#closed(c.options),dist=new Float64Array(this.#forward.length);dist.fill(Infinity);
    const prev=new Array(dist.length),heap=new Heap(),targets=new Set(graph.targetStates[c.toNode]);
    heap.push([0,c.fromNode]);dist[c.fromNode]=0;let end=null;
    while(heap.a.length){const[d,s]=heap.pop();if(d!==dist[s])continue;if(targets.has(s)){end=s;break;}
      for(const t of this.#forward[s]){const edge=graph.edges[t.edge];if(edge.disabled||closed.has(edge.id))continue;const next=d+edge.minimum+t.minimumTurn;
        if(next<dist[t.to]){dist[t.to]=next;prev[t.to]={state:s,edge:t.edge,turnSeconds:t.minimumTurn};heap.push([next,t.to]);}}
    }
    if(end===null)throw Error('road_disconnected');const path=[];
    for(let s=end;s!==c.fromNode;){const p=prev[s];path.push(p);s=p.state;}path.reverse();
    const edges=path.map(p=>this.#roads[p.edge]);let distance=0,geometry=[];
    for(const edge of edges){if(!Number.isFinite(edge.distanceMeters)||edge.distanceMeters<0||!Array.isArray(edge.geometry)||edge.geometry.length<2||edge.geometry.some(p=>!point(p)))throw Error('road_geometry_unavailable');
      distance+=edge.distanceMeters;geometry.push(...clone(edge.geometry).slice(geometry.length?1:0));}
    if(!edges.length)geometry=[clone(this.#nodes[c.fromNode])];
    return {staticSeconds:dist[end],distanceMeters:distance,geometry,edges:path.map(p=>({id:p.edge,seconds:graph.edges[p.edge].minimum+p.turnSeconds,distanceMeters:graph.edges[p.edge].distanceMeters})),evidenceClass:'EXACT_STATIC_ROUTE'};
  }
  async routeEvidence(context) {
    this.#validate(context);context={tenant_id:context.tenant_id,company_id:context.company_id,leg:context.leg,
      fromNode:context.fromNode,toNode:context.toNode,from:clone(context.from),to:clone(context.to),
      graphVersion:context.graphVersion,profile:context.profile,options:clone(context.options||{}),departureSemantics:context.departureSemantics};
    const key=stable(context),at=this.#clock();this.metrics.queries++;
    for(const[k,e]of this.#cache)if(at<e.at||at>=e.until){this.#bytes-=e.bytes;this.#cache.delete(k);}
    if(this.#cache.has(key)){this.metrics.cacheHits++;return clone(this.#cache.get(key).value);}
    if(this.#inflight.has(key)){this.metrics.cacheHits++;return clone(await this.#inflight.get(key));}
    this.metrics.cacheMisses++;
    const compute=async()=>{this.metrics.staticRoutes++;const route=this.#route(context);
      const digest=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(key+'\n'+stable(route)));
      const value={...clone(context),...route,evidenceId:[...new Uint8Array(digest)].map(b=>b.toString(16).padStart(2,'0')).join(''),timestamp:at,validUntil:at+this.#ttl,source:'owned-graph',routeScope:'snapped-node-to-node',snapAccessCost:'NOT_INCLUDED'};
      const bytes=new TextEncoder().encode(key+JSON.stringify(value)).byteLength;
      if(bytes<=this.#maxBytes){while(this.#cache.size&&(this.#cache.size>=this.#limit||this.#bytes+bytes>this.#maxBytes)){const k=this.#cache.keys().next().value;this.#bytes-=this.#cache.get(k).bytes;this.#cache.delete(k);}
        this.#cache.set(key,{value,at,until:at+this.#ttl,bytes});this.#bytes+=bytes;}return value;};
    if(this.#inflight.size>=this.#limit)return clone(await compute());
    const pending=compute();this.#inflight.set(key,pending);try{return clone(await pending);}finally{this.#inflight.delete(key);}
  }
  diagnostics(){return{entries:this.#cache.size,inflight:this.#inflight.size,bytes:this.#bytes,...this.metrics};}
}

// Model A: budget is observational, never an exclusion rule. If proof is weak,
// all remaining candidates are evaluated. Authority/capacity live elsewhere.
export async function progressiveTrafficSearch(candidates,{graph,context,evaluate,budget=10}) {
  if(!Number.isInteger(budget)||budget<1||budget>5000)throw Error('provider_budget_invalid');
  const provider=new RoutingEvidenceProvider({graph,premium:evaluate});
  const result=await certifiedRoadSearch(candidates,{provider,context,evaluate:c=>provider.trafficRoute(c,context)});
  return {...result,premiumCalls:provider.metrics.providerCalls,budgetExceeded:provider.metrics.providerCalls>budget,
    policy:'premium-exhaustive-equivalent-v1',authorityCommitted:false};
}

// Deliberately distinct Model B for quality analysis. Traffic has zero ranking
// weight, static travel plus readiness determines the winner. It is not wired
// into the live allocator and must not be described as equivalent to Model A.
export function staticPrimaryPolicy(candidates,core,target) {
  const rows=core.manyToOne(candidates.map(c=>c.originNode),target).map((r,i)=>({...candidates[i],pickupSeconds:r.staticSeconds+(candidates[i].readySeconds||0)}))
    .filter(r=>Number.isFinite(r.pickupSeconds)).sort((a,b)=>a.pickupSeconds-b.pickupSeconds||a.order-b.order);
  return {best:rows[0]||null,policy:'static-primary-zero-traffic-weight-v1',authorityCommitted:false};
}

// Explicit route-purpose contract. Pricing/traffic policy is supplied by the
// existing authoritative caller, never inferred from a future departure date.
// This gateway is not wired into quote/pricing until regional road coverage,
// access-edge snapping and each tariff's route semantics have been validated.
export function createRoutingGateway({core,premium}) {
  return {async resolve(context,{requiresPremium=true}={}) {
    let failure=null;
    if(!requiresPremium){try{return{static:await core.routeEvidence(context),premium:null,fallback:false};}catch(error){failure=error.message;}}
    try{return{static:null,premium:await premium(context),fallback:failure!==null,reason:failure};}
    catch(error){const unavailable=new Error('routing_temporarily_unavailable');unavailable.cause=error;throw unavailable;}
  }};
}
