import { jsonBase64urlEncode, jsonBase64urlDecode } from './crypto_utils.js';
import { decorateDriverForDispatch, linkedVehicleIds } from './company_dispatch.mjs';
import { scopedDriverDirectoryRecord } from './driver_directory_membership.mjs';
// Advisory management paging. Authorization and mutation authority stay at the caller.
export function prepareDriverManagementIndex(record) {
 const ids=Object.keys(record.drivers||{}).sort(),live=[],byVehicle=new Map(),byType=new Map(),byGram=new Map(),unindexed=[];
 for(const id of ids){const driver=record.drivers[id];if(!driver||record.deleted_drivers?.[id])continue;live.push(id);
  const type=driver.driver_type||'FLEET_DRIVER';if(!byType.has(type))byType.set(type,[]);byType.get(type).push(id);
  for(const vehicle of linkedVehicleIds(driver)){if(!byVehicle.has(vehicle))byVehicle.set(vehicle,[]);byVehicle.get(vehicle).push(id);}}
 return {record,ids,live,byVehicle,byType,byGram,unindexed,queries:new Map(),diagnostics:{examined:0}};
}
function buildSubstringPostings(index){
 for(const id of index.live){const driver=index.record.drivers[id];
  const fields=[driver.display_name,driver.employee_number,id,driver.phone].map(value=>String(value||'').toLowerCase());
  if(fields.some(value=>value.length>4096))index.unindexed.push(id);
  else {const grams=new Set();for(const value of fields)for(let i=0;i+3<=value.length;i++)grams.add(value.slice(i,i+3));for(const gram of grams){if(!index.byGram.has(gram))index.byGram.set(gram,[]);index.byGram.get(gram).push(id);}}
  
 }
 index.searchBuilt=true;
}
export function driverManagementPage(record, scope, options = {}, presence = {}, prepared = null) {
 // Prepared indexes belong to an immutable authoritative generation. Validate
 // each company view before using its cached postings, without rescanning warm pages.
 const owner=prepared?.record===record?prepared:null;
 if(owner){
  const key=JSON.stringify([scope?.tenant_id,scope?.company_id]);
  owner.scopedViews ||= new Map();
  let view=owner.scopedViews.get(key);
  if(!view||view.generation!==record.driver_index_generation){
   const scoped=scopedDriverDirectoryRecord(record,scope);
   view={generation:record.driver_index_generation,record:scoped,index:scoped===record?owner:prepareDriverManagementIndex(scoped)};
   owner.scopedViews.set(key,view);
  }
  record=view.record;prepared=view.index;
 }else record=scopedDriverDirectoryRecord(record,scope);
 const limit=Math.min(100,Math.max(1,Math.floor(Number(options.limit)||50)));
 const q=String(options.q||'').trim().toLowerCase().slice(0,200),vehicle=String(options.vehicle_id||''),id=String(options.driver_id||'');
 const type=String(options.driver_type||'').toUpperCase();
 if(type&&!['FLEET_DRIVER','PARTNER_DRIVER'].includes(type))return {ok:false,status:400,error:'driver_type_invalid'};
 const online=options.online==null||options.online===''?null:['1','true'].includes(String(options.online));
 const now=Date.now();
 const revision=String(record.driver_index_generation||0)+(online===null?'':':'+String(presence.presence_revision??presence.updated_at??'')+(presence.presence_revision==null?':'+Math.floor(now/1000):''));
 let validUntil=Infinity;
 if(online!==null)for(const row of Object.values(presence.drivers||{})){const seen=Date.parse(row?.last_seen_at||row?.lastSeenAt||'');if(!Number.isFinite(seen))continue;for(const boundary of [seen-120000,seen+180001])if(boundary>now)validUntil=Math.min(validUntil,boundary);}
 const filter=JSON.stringify(type?[q,vehicle,id,online,type]:[q,vehicle,id,online]);let offset=0;
 if(options.cursor){let cursor;try{cursor=jsonBase64urlDecode(options.cursor);}catch{return{ok:false,status:400,error:'invalid_cursor'};}
  if(!cursor||cursor.tenant!==scope.tenant_id||cursor.company!==scope.company_id||cursor.filter!==filter||!Number.isSafeInteger(cursor.offset)||cursor.offset<0)return{ok:false,status:400,error:'invalid_cursor'};
  if(cursor.revision!==revision||online!==null&&(now<cursor.issued_at||cursor.valid_until!=null&&now>=cursor.valid_until))return{ok:false,status:409,error:'page_revision_changed'};offset=cursor.offset;}
 const index=prepared?.record===record?prepared:prepareDriverManagementIndex(record),ids=index.ids;
 const queryKey=filter+':'+revision;
 const cached=index.queries.get(queryKey);let matches=cached&&now>=cached.issuedAt&&now<cached.validUntil?cached.ids:null;
 if(!matches){
 const lists=[index.live];if(vehicle)lists.push(index.byVehicle.get(vehicle)||[]);if(type)lists.push(index.byType.get(type)||[]);if(id)lists.push(record.drivers?.[id]&&!record.deleted_drivers?.[id]?[id]:[]);
 if(q.length>=3){if(!index.searchBuilt)buildSubstringPostings(index);const grams=[...new Set(Array.from({length:q.length-2},(_,i)=>q.slice(i,i+3)))];
  const postings=grams.map(gram=>index.byGram.get(gram)||[]),shortest=postings.reduce((a,b)=>a.length<=b.length?a:b),sets=postings.filter(list=>list!==shortest).map(list=>new Set(list));
  const narrowed=shortest.filter(driverId=>sets.every(set=>set.has(driverId)));const candidates=new Set([...narrowed,...index.unindexed]);lists.push([...candidates].sort());}
 const candidates=lists.reduce((a,b)=>a.length<=b.length?a:b);matches=[];index.diagnostics.examined=0;
 if(!q&&!vehicle&&!type&&!id&&online===null)matches=index.live;
 else
 for(const driverId of candidates){index.diagnostics.examined++;const driver=record.drivers[driverId];if(!driver||record.deleted_drivers?.[driverId]||id&&id!==driverId)continue;
  if(type&&(driver.driver_type||'FLEET_DRIVER')!==type)continue;
  if(vehicle&&!linkedVehicleIds(driver).includes(vehicle))continue;
  if(q&&![driver.display_name,driver.employee_number,driverId,driver.phone].some(v=>String(v||'').toLowerCase().includes(q)))continue;
  if(online!==null&&decorateDriverForDispatch(driver,presence.drivers?.[driverId]||{},Date.now()).live_connected!==online)continue;
  matches.push(driverId);}
 if(index.queries.size>=8)index.queries.delete(index.queries.keys().next().value);
 index.queries.set(queryKey,{ids:matches,issuedAt:now,validUntil});
 }
 const selected=matches.slice(offset,offset+limit),drivers=Object.fromEntries(selected.map(driverId=>[driverId,record.drivers[driverId]]));const hasMore=offset+selected.length<matches.length;
 return{ok:true,record:{drivers,driver_index_generation:record.driver_index_generation||0,updated_at:record.updated_at,registered_count:ids.length},total_count:matches.length,has_more:hasMore,next_cursor:hasMore?jsonBase64urlEncode({tenant:scope.tenant_id,company:scope.company_id,filter,revision,offset:offset+selected.length,issued_at:now,valid_until:Number.isFinite(validUntil)?validUntil:null}):'',revision};
}
