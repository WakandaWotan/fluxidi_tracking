// OSM turn indications supplement, never replace, graph turn/access rules.
// Directional lanes are ordered left-to-right in their driving direction:
// https://wiki.openstreetmap.org/wiki/Lanes
// Complex/conditional/connectivity-dependent cases remain unknown.
const hash=s=>/^[a-f0-9]{64}$/.test(s??'');
const proved=r=>hash(r?.navigationSource?.manifestSha256)&&hash(r?.navigationSource?.objectSha256)&&hash(r?.navigationSource?.sourceSha256)&&r.navigationTags&&Array.isArray(r.navigationUnsupported);
const human=s=>typeof s==='string'&&s.trim()&&!/^[QPW]\d+$/.test(s)&&!/^https?:\/\//i.test(s)?s.trim():'';
const rad=Math.PI/180,bearing=(a,b)=>(Math.atan2((b.longitude-a.longitude)*Math.cos((a.latitude+b.latitude)*rad/2),b.latitude-a.latitude)/rad+360)%360;
const delta=(a,b)=>((b-a+540)%360)-180;
const category=angle=>{
 const n=Math.abs(angle),side=angle<0?'left':'right';
 if(n<=10)return 'straight';if(n>=15&&n<=35)return 'slight '+side;
 if(n>=45&&n<=135)return side;if(n>=145&&n<=165)return 'sharp '+side;
 return null;
};
export function navigationRoadNameV1(road,language='nl'){
 if(proved(road)){
  const t=road.navigationTags,lang=String(language).split(/[-_]/)[0];
  return human(t['name:'+lang])||human(t.name)||human(t.official_name)||human(t.ref)||human(road.tags?.ref);
 }
 return road?.tags?.streetNames?.map(human).find(Boolean)||human(road?.tags?.ref)||'';
}
export function navigationDestinationV1(road){
 if(!proved(road))return null;
 const tags=road.navigationTags,side=road.direction===1?'forward':'backward';
 const directed=tags['destination:'+side],oneway=road.tags?.oneway===road.direction;
 const value=directed??(oneway?tags.destination:null),ref=tags['destination:ref:'+side]??(oneway?tags['destination:ref']:null);
 const values=[value,ref].filter(v=>typeof v==='string').flatMap(v=>v.split(';')).map(human).filter(Boolean);
 return values.length?[...new Set(values)].join(' · '):null;
}
export function navigationPostedSpeedV1(road){
 if(!proved(road)||road.navigationUnsupported.some(k=>k.startsWith('maxspeed'))||Object.keys(road.navigationTags).some(k=>k.startsWith('maxspeed')&&k.includes('conditional')))return null;
 const t=road.navigationTags,side=road.direction===1?'forward':'backward',raw=t['maxspeed:'+side]??t.maxspeed;
 if(typeof raw!=='string'||!/^\d+(?:\.\d+)?(?: km\/h| kmh)?$/.test(raw.trim()))return null;
 const limit=Number.parseFloat(raw);return Number.isFinite(limit)&&limit>0&&limit<=130?limit:null;
}
export function navigationLaneIntersectionV1({incoming,chosen,location,bearingBefore,bearingAfter}){
 if(!proved(incoming)||!proved(chosen)||incoming.navigationSource.manifestSha256!==chosen.navigationSource.manifestSha256
  ||incoming.toNode!==chosen.fromNode||chosen.physicalJunctionComplete!==true||!Array.isArray(chosen.physicalOptions)
  ||![1,-1].includes(incoming.direction)||![1,-1].includes(chosen.direction)
  ||incoming.tags.junction==='roundabout'||chosen.tags.junction==='roundabout')return null;
 const tags=incoming.navigationTags,side=incoming.direction===1?'forward':'backward';
 const allowed=new Set(['lanes','lanes:forward','lanes:backward','turn:lanes','turn:lanes:forward','turn:lanes:backward','change:lanes','change:lanes:forward','change:lanes:backward']);
 const laneKey=k=>k==='lanes'||k.startsWith('lanes:')||k.includes(':lanes');
 if(incoming.navigationUnsupported.some(laneKey)||Object.keys(tags).some(k=>laneKey(k)&&!allowed.has(k)))return null;
 const directed=tags['turn:lanes:'+side];
 // Unqualified reverse-oneway lane order is not established by this adapter.
 const raw=directed??(incoming.direction===1&&incoming.tags.oneway===1?tags['turn:lanes']:null);
 const count=tags['lanes:'+side]??(incoming.tags.oneway===incoming.direction?tags.lanes:null);
 if(typeof raw!=='string'||typeof count!=='string'||!/^\d{1,2}$/.test(count)||Number(count)<2||Number(count)>12)return null;
 const map={left:'left',slight_left:'slight left',sharp_left:'sharp left',through:'straight',slight_right:'slight right',right:'right',sharp_right:'sharp right'};
 const lanes=raw.split('|').map(value=>value.split(';').map(v=>map[v.trim()]));
 if(lanes.length!==Number(count)||lanes.some(l=>!l.length||l.length>4||l.some(v=>!v)))return null;
 const target=category(delta(bearingBefore,bearingAfter));if(!target)return null;
 if(chosen.physicalOptions.some(o=>!o.to||!Number.isFinite(o.to.latitude)||!Number.isFinite(o.to.longitude)))return null;
 const branches=chosen.physicalOptions.filter(o=>o.toNode!==incoming.fromNode).map(o=>({...o,bearing:bearing(chosen.from,o.to)}));
 if(branches.length<2||branches.some(o=>!Number.isFinite(o.bearing)))return null;
 for(const branch of branches)branch.category=category(delta(bearingBefore,branch.bearing));
 if(branches.some(o=>!o.category))return null;
 const matches=branches.filter(o=>o.category===target);
 if(matches.length!==1||matches[0].id!==chosen.id||matches[0].turnAllowed!==true)return null;
 // No indicated arrow may point to an unexplained/multiple physical branch.
 if(lanes.flat().some(indication=>branches.filter(o=>o.category===indication).length!==1))return null;
 if(!lanes.some(indications=>indications.includes(target)))return null;
 const bearings=[{bearing:(bearingBefore+180)%360,entry:false,incoming:true},...branches.map(o=>({bearing:o.bearing,entry:o.turnAllowed===true,id:o.id}))].sort((a,b)=>a.bearing-b.bearing);
 return {location:[location.longitude,location.latitude],bearings:bearings.map(b=>b.bearing),entry:bearings.map(b=>b.entry),
  in:bearings.findIndex(b=>b.incoming),out:bearings.findIndex(b=>b.id===chosen.id),
  lanes:lanes.map(indications=>({indications:[...new Set(indications)],valid:indications.includes(target),...(indications.includes(target)?{valid_indication:target}:{})})),
  source:'fluxidi-national-osm',metadata_sha256:incoming.navigationSource.manifestSha256};
}
