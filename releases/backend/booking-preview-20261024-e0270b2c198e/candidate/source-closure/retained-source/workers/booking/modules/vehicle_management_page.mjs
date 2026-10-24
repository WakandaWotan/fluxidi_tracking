import { jsonBase64urlEncode, jsonBase64urlDecode, sha256Hex } from './crypto_utils.js';
export async function vehicleManagementPage(rows,scope,options={},sourceRevision=0){
 const limit=Math.min(100,Math.max(1,Math.floor(Number(options.limit)||50))),q=String(options.q||'').trim().toLowerCase().slice(0,200),id=String(options.vehicle_id||'');
 const active=options.is_active==null?null:['1','true'].includes(String(options.is_active));
 const filter=JSON.stringify([q,id,active]);const revision=sourceRevision ? String(sourceRevision) : await sha256Hex(JSON.stringify(rows));let offset=0;
 if(options.cursor){let c;try{c=jsonBase64urlDecode(options.cursor);}catch{return{ok:false,status:400,error:'invalid_cursor'};}
  if(!c||c.tenant!==scope.tenant_id||c.company!==scope.company_id||c.filter!==filter||!Number.isSafeInteger(c.offset)||c.offset<0)return{ok:false,status:400,error:'invalid_cursor'};
  if(c.revision!==revision)return{ok:false,status:409,error:'page_revision_changed'};offset=c.offset;}
 const seen=new Set();const filtered=rows.filter(v=>{const key=String(v?.vehicle_id||v?.id||'');if(!key||seen.has(key)||id&&id!==key)return false;seen.add(key);
  if(active!==null&&!(v.is_active===false||v.is_active==='false'||v.is_active===0) !==active)return false;
  return !q||[key,v.name,v.vehicle_name,v.brand_model,v.license_plate].some(value=>String(value||'').toLowerCase().includes(q));}).sort((a,b)=>String(a.vehicle_id||a.id).localeCompare(String(b.vehicle_id||b.id)));
 const vehicles=filtered.slice(offset,offset+limit),hasMore=offset+vehicles.length<filtered.length;
 return{ok:true,vehicles,total_count:filtered.length,has_more:hasMore,revision,next_cursor:hasMore?jsonBase64urlEncode({tenant:scope.tenant_id,company:scope.company_id,filter,revision,offset:offset+vehicles.length}):''};
}
