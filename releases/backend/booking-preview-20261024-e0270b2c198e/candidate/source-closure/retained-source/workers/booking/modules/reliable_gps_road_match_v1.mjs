// A measurement-to-road contract, not proof of building/driveway access.
// Address centroids must use a separately proven mapped access point. This
// matcher never creates connectors, graph edges, ETA certificates or providers.
const finite=n=>typeof n==='number'&&Number.isFinite(n);
const valid=p=>p&&finite(p.latitude)&&finite(p.longitude)&&Math.abs(p.latitude)<=90&&Math.abs(p.longitude)<=180&&(p.latitude!==0||p.longitude!==0);
const bearing=(a,b)=>{const r=x=>x*Math.PI/180,p=r(a.latitude),q=r(b.latitude),l=r(b.longitude-a.longitude);return (Math.atan2(Math.sin(l)*Math.cos(q),Math.cos(p)*Math.sin(q)-Math.sin(p)*Math.cos(q)*Math.cos(l))*180/Math.PI+360)%360;};
const delta=(a,b)=>Math.abs(((a-b+540)%360)-180);
function project(p,a,b){const x=111195*Math.cos(p.latitude*Math.PI/180),y=111195,dx=(b.longitude-a.longitude)*x,dy=(b.latitude-a.latitude)*y,t=Math.max(0,Math.min(1,((p.longitude-a.longitude)*x*dx+(p.latitude-a.latitude)*y*dy)/(dx*dx+dy*dy||1)));const point={latitude:a.latitude+(b.latitude-a.latitude)*t,longitude:a.longitude+(b.longitude-a.longitude)*t};return {point,t,distanceMeters:Math.hypot((p.longitude-point.longitude)*x,(p.latitude-point.latitude)*y)};}
export function createReliableGpsRoadMatcherV1(corridor,{clock=Date.now,maxSnapMeters=25,maxAgeMs=30000}={}){
 if(!corridor?.graph||!Array.isArray(corridor.coordinates)||!finite(maxSnapMeters)||maxSnapMeters<=0||maxSnapMeters>25||!finite(maxAgeMs)||maxAgeMs<=0||maxAgeMs>30000)throw Error('gps_match_contract_invalid');
 const metrics={queries:0,accepted:0,rejected:0,commercialRoutingCalls:0},grid=new Map(),overflow=[],step=.001;let entries=0;
 const pieces=[...corridor.graph.edges.map(edge=>({edge,from:corridor.coordinates[edge.from],to:corridor.coordinates[edge.to]})),...(corridor.excludedSegments??[]).map(segment=>({...segment,excluded:true}))];
 for(let i=0;i<pieces.length;i++){const s=pieces[i],xmin=Math.floor(Math.min(s.from.latitude,s.to.latitude)/step)-1,xmax=Math.floor(Math.max(s.from.latitude,s.to.latitude)/step)+1,ymin=Math.floor(Math.min(s.from.longitude,s.to.longitude)/step)-1,ymax=Math.floor(Math.max(s.from.longitude,s.to.longitude)/step)+1,count=(xmax-xmin+1)*(ymax-ymin+1);if(count>5000||entries+count>500000){overflow.push(i);continue;}for(let x=xmin;x<=xmax;x++)for(let y=ymin;y<=ymax;y++){const key=x+':'+y;if(!grid.has(key))grid.set(key,[]);grid.get(key).push(i);entries++;}}
 return Object.freeze({kind:'GPS_MEASUREMENT_ROAD_MATCH_V1',diagnostics:()=>({...metrics}),match(sample){
  metrics.queries++;const deny=reason=>(metrics.rejected++,{ok:false,reason,graphVersion:corridor.graph.version,accessProven:false,customerEtaCertified:false});
  const now=clock();
  if(!valid(sample)||sample.crs!=='EPSG:4326'||sample.source!=='gps')return deny('gps_coordinate_or_source_invalid');
  if(!finite(sample.capturedAt)||sample.capturedAt>now||now-sample.capturedAt>maxAgeMs)return deny('gps_stale');
  if(!finite(sample.accuracyMeters)||sample.accuracyMeters<=0||sample.accuracyMeters>maxSnapMeters)return deny('gps_accuracy_unproven');
  if(sample.headingDegrees!=null&&(!finite(sample.headingDegrees)||sample.headingDegrees<0||sample.headingDegrees>=360))return deny('gps_heading_invalid');
  if(sample.headingDegrees!=null&&(!finite(sample.speedMetersPerSecond)||sample.speedMetersPerSecond<2))return deny('gps_heading_unreliable');
  const radius=Math.min(maxSnapMeters,sample.accuracyMeters),groups=new Map();
  // Indexed envelopes are valid for the BE/NL launch latitude band only.
  // Other latitudes are rejected instead of silently missing nearby roads.
  if(sample.latitude<49||sample.latitude>54)return deny('gps_region_unproven');
  // All geometrically plausible roads are retained before direction ranking.
  // In particular, heading cannot erase a parallel-road/access ambiguity.
  for(const index of [...(grid.get(Math.floor(sample.latitude/step)+':'+Math.floor(sample.longitude/step))??[]),...overflow]){const piece=pieces[index],p=project(sample,piece.from,piece.to);if(p.distanceMeters-radius>1e-8)continue;if(piece.excluded)return deny('gps_access_ambiguity');const edge=piece.edge;
   const key=[edge.osmWay,...[edge.from,edge.to].sort((a,b)=>a-b)].join(':');let group=groups.get(key);if(!group){group={...p,edges:[],disabled:false};groups.set(key,group);}group.edges.push(edge);group.disabled||=edge.disabled===true;
  }
  // Excluded/private/conditional/barrier roads remain spatial negative evidence.
  if(groups.size===0)return deny('gps_no_road');
  if(groups.size!==1)return deny('gps_parallel_or_junction_ambiguity');
  const group=groups.values().next().value;
  if(group.disabled)return deny('gps_disabled_road');
  if(group.edges.some(e=>['bridge','tunnel'].includes(e.kind)))return deny('gps_vertical_layer_unproven');
  // Endpoint/junction departure direction needs a stronger transition proof.
  if(group.t<=1e-6||group.t>=1-1e-6)return deny('gps_junction_direction_unproven');
  const edges=group.edges.filter(e=>sample.headingDegrees==null||delta(sample.headingDegrees,bearing(corridor.coordinates[e.from],corridor.coordinates[e.to]))<=35);
  if(!edges.length)return deny('gps_wrong_direction');
  if(group.edges.some(e=>e.oneWay||e.ramp)&&sample.headingDegrees==null)return deny('gps_direction_unproven');
  metrics.accepted++;
  return {ok:true,kind:'GPS_MEASUREMENT_MATCH',point:group.point,distanceMeters:group.distanceMeters,edgeIds:edges.map(e=>e.id),direction:edges.length===1?'directed':'two_way',graphVersion:corridor.graph.version,matchConfidence:'unique_within_reported_accuracy',ambiguity:false,source:'gps',accessProven:false,customerEtaCertified:false,validUntil:Math.min(sample.capturedAt+maxAgeMs,now+15000)};
 }});
}
