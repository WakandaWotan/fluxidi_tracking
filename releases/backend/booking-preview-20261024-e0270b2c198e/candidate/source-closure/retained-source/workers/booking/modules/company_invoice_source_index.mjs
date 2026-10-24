import {companyInvoiceMonth,validateCompanyCustomerInvoicingPolicy} from './company_customer_invoicing.mjs';
const META='invoice-source-index:v1:meta',PREFIX='invoice-source-index:v1:row:',CANONICAL='canonical-booking:';
const same=(a,b)=>a?.tenant_id===b?.tenant_id&&a?.company_id===b?.company_id;
const stable=x=>JSON.stringify(sort(x));const sort=x=>Array.isArray(x)?x.map(sort):x&&typeof x==='object'?Object.fromEntries(Object.keys(x).sort().map(k=>[k,sort(x[k])])):x;
function memberships(envelope,scope,id){
 if(!same(envelope,scope)||!same(envelope?.record,scope)||envelope.schema!==1||!Number.isSafeInteger(envelope.version)||envelope.version<1||envelope.record._canonical_version!==envelope.version)throw Error('invoice_source_scope_unverified');
 const record=envelope.record,policy=record.company_customer_invoicing_policy;if(policy==null)return [];
 const verified=validateCompanyCustomerInvoicingPolicy(policy,scope);if(!verified.ok)throw Error(verified.error);
 if(policy.invoice_frequency!=='monthly')return [];
 const lists=[record,record.booking,record.payload].filter(Boolean).flatMap(c=>[c.operational_legs,c.operationalLegs]).filter(Array.isArray).filter(a=>a.length);
 let months=new Set();
 if(lists.some(a=>stable(a)!==stable(lists[0])))months.add('*');
 else for(const row of lists[0]||[record])if((row.status??row.lifecycle_status??row.lifecycleStatus)==='completed')months.add(companyInvoiceMonth(row.completed_at??row.completedAt)||'*');
 return [...months].map(month=>({key:PREFIX+policy.customer_id+':'+month+':'+id,value:{schema:1,...scope,bookingId:id,version:envelope.version}}));
}
// Called only by the serialized company authority, before and after its durable
// canonical write. A crash leaves complete:false; issuance then rebuilds first.
export async function persistCanonicalWithInvoiceIndex(storage,id,envelope,writeCanonical){
 const meta=await storage.get(META);
 if(!meta){await writeCanonical();return;}
 const previous=await storage.get(CANONICAL+id);
 const nextRevision=(meta.revision||0)+1;
 await storage.put(META,{...meta,revision:nextRevision,complete:false,cursor:'',cleared:false});
 await writeCanonical();
 if(meta.complete!==true)return;
 const scope={tenant_id:envelope.tenant_id,company_id:envelope.company_id};
 if(!same(meta,scope))throw Error('invoice_source_scope_unverified');
 const oldRows=previous?memberships(previous,scope,id):[],newRows=memberships(envelope,scope,id);
 for(const row of oldRows)await storage.delete(row.key);
 for(const row of newRows)await storage.put(row.key,row.value);
 const buckets=new Set([...oldRows,...newRows].map(row=>row.key.slice(PREFIX.length,row.key.lastIndexOf(':'))));
 for(const bucket of buckets){const key='invoice-source-index:v1:revision:'+bucket;const revision=await storage.get(key)||0;if(!Number.isSafeInteger(revision)||revision<0)throw Error('invoice_inventory_unverified');await storage.put(key,revision+1);}
 await storage.put(META,{...meta,revision:nextRevision});
}
export async function indexedInvoiceSources(storage,{scope,customerId,month,batchSize=1000,prepare=false,indexOnly=false}){
 if(!storage.put||!storage.delete)return null;
 let meta=await storage.get(META);
 if(meta&&!same(meta,scope))return {ok:false,error:'invoice_source_scope_unverified'};
 if(!meta?.complete&&!prepare)return null;
 if(!meta?.complete){
  meta={schema:1,...scope,revision:meta?.revision||1,generation:(meta?.generation||1)+(meta?.cleared===true?0:1),complete:false,cursor:meta?.cursor||'',cleared:meta?.cleared===true};
  if(!meta.cleared){
   // Cleanup is also bounded and resumable. A failed cleanup cannot prove coverage.
   const old=await storage.list({prefix:PREFIX,limit:batchSize});for(const key of old.keys())await storage.delete(key);
   if(old.size===batchSize){await storage.put(META,meta);return {ok:false,error:'invoice_inventory_warming',scanned:0};}
   meta.cleared=true;
  }
  const page=await storage.list({prefix:CANONICAL,limit:batchSize,...(meta.cursor?{startAfter:meta.cursor}:{})});
  for(const [key,envelope]of page){if(!key.startsWith(CANONICAL)||key<=meta.cursor)throw Error('invoice_inventory_cursor_invalid');
   const id=key.slice(CANONICAL.length);if(!/^[A-Za-z0-9_-]{1,160}$/.test(id))throw Error('invoice_inventory_cursor_invalid');
   for(const row of memberships(envelope,scope,id))await storage.put(row.key,row.value);meta.cursor=key;
  }
  // Only an empty authoritative page proves completion, even with short adapters.
  if(page.size){const remaining=await storage.list({prefix:CANONICAL,startAfter:meta.cursor,limit:1});if(remaining.size){await storage.put(META,meta);return {ok:false,error:'invoice_inventory_warming',scanned:page.size};}}
  meta.complete=true;await storage.put(META,meta);
 }
 if(indexOnly)return{ok:true,complete:meta.complete,revision:meta.revision||1,generation:meta.generation||1};
 const selected=new Map();
 for(const bucket of [month,'*']){let cursor='';const prefix=PREFIX+customerId+':'+bucket+':';for(;;){const page=await storage.list({prefix,limit:100,...(cursor?{startAfter:cursor}:{})});if(!page.size)break;
  for(const [key,row]of page){if(key<=cursor||!same(row,scope))return {ok:false,error:'invoice_source_scope_unverified'};cursor=key;
   const envelope=await storage.get(CANONICAL+row.bookingId);if(envelope?.version!==row.version)return null; // Read-only full canonical fallback; never issue from stale index.
   memberships(envelope,scope,row.bookingId);selected.set(CANONICAL+row.bookingId,envelope);
  }
 }}
 return {ok:true,entries:[...selected].sort(([a],[b])=>a.localeCompare(b))};
}


// The generation fences recovery/rebuilds; bucket revisions only invalidate
// jobs affected by canonical changes in their exact customer/month or wildcard.
// Ordinary bookings in another period do not invalidate a closed-month job.
const bucketRevisionKey=(customerId,month)=>`invoice-source-index:v1:revision:${customerId}:${month}`;
export async function invoiceSourceIndexFence(storage,{scope,customerId,month}){
 const meta=await storage.get(META);if(!same(meta,scope)||meta?.complete!==true)return{ok:false,error:'invoice_inventory_unverified'};
 const values=await Promise.all([storage.get(bucketRevisionKey(customerId,month)),storage.get(bucketRevisionKey(customerId,'*'))]);
 if(values.some(v=>v!=null&&(!Number.isSafeInteger(v)||v<0)))return{ok:false,error:'invoice_inventory_unverified'};
 return{ok:true,revision:JSON.stringify([meta.generation||1,...values.map(v=>v||0)])};
}
export async function invoiceSourceIndexPage(storage,{scope,customerId,month,cursor=null,limit=125,revision}){
 if(!/^[A-Za-z0-9_-]{1,160}$/.test(customerId||'')||!/^\d{4}-(0[1-9]|1[0-2])$/.test(month||'')||!Number.isSafeInteger(limit)||limit<1||limit>500)return{ok:false,error:'invoice_inventory_cursor_invalid'};
 const fenced=await invoiceSourceIndexFence(storage,{scope,customerId,month});if(!fenced.ok||fenced.revision!==revision)return{ok:false,error:'invoice_inventory_revision_changed'};
 let phase=cursor?.phase??0,after=cursor?.after||'';if(!Number.isSafeInteger(phase)||phase<0||phase>2)return{ok:false,error:'invoice_inventory_cursor_invalid'};
 while(phase<2){const prefix=PREFIX+customerId+':'+[month,'*'][phase]+':';if(after&&!after.startsWith(prefix))return{ok:false,error:'invoice_inventory_cursor_invalid'};
  const page=await storage.list({prefix,limit,...(after?{startAfter:after}:{})});if(!(page instanceof Map)||page.size>limit)return{ok:false,error:'invoice_inventory_unverified'};
  if(!page.size){phase++;after='';continue;}
  const entries=[];for(const[key,row]of page){if(!key.startsWith(prefix)||key<=after||!same(row,scope)||row.schema!==1||!/^[A-Za-z0-9_-]{1,160}$/.test(row.bookingId||'')||key!==prefix+row.bookingId)return{ok:false,error:'invoice_inventory_cursor_invalid'};
   after=key;const envelope=await storage.get(CANONICAL+row.bookingId);if(envelope?.version!==row.version)return{ok:false,error:'invoice_source_revision_changed'};const member=memberships(envelope,scope,row.bookingId);if(!member.some(m=>m.key===key))return{ok:false,error:'invoice_inventory_unverified'};entries.push([CANONICAL+row.bookingId,envelope]);
  }
  return{ok:true,entries,cursor:{phase,after},complete:false};
 }
 return{ok:true,entries:[],cursor:{phase:2,after:''},complete:true};
}
