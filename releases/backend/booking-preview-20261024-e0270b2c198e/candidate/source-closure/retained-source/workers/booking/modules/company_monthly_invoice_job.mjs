import {hydrateCanonicalFinancialEvidence} from './financial_quote_lifecycle.mjs';
import {assembleCompanyMonthlyInvoice, companyInvoiceMonth} from './company_customer_invoicing.mjs';
import {projectCompanyMonthlyInvoiceRecord} from './company_monthly_invoice_projection.mjs';
import {hashDocumentSnapshot, stableDocumentJson} from './document_core.js';
import {invoiceSourceIndexPage,invoiceSourceIndexFence} from './company_invoice_source_index.mjs';

// Versioned large-invoice contract. The caller is the existing serialized
// company authority. Public callers never supply source lines, parties or money.
// Each source claim, immutable page and exact-cent checkpoint is committed in
// one transaction. Pending claims survive failure; timeout never releases them.
const validId=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,160}$/.test(v);
const same=(a,b)=>a?.tenant_id===b?.tenant_id&&a?.company_id===b?.company_id;
const fail=error=>({ok:false,error,status:409});
const prefix=scope=>`monthly_invoice:v1:${scope.tenant_id}:${scope.company_id}`;
const jobKey=(scope,customerId,month)=>`${prefix(scope)}:job-v2:${customerId}:${month}`;
const claimKey=(scope,id)=>`${prefix(scope)}:source:${id}`;
const pageKey=(job,index)=>`${job.key}:job:${job.job_id}:page:${String(index).padStart(10,'0')}`;
const serializedBytes=value=>new TextEncoder().encode(JSON.stringify(value)).byteLength;
const CHUNK_MAX_BYTES=96*1024;
const taxKey=(job,rate)=>`${job.key}:job:${job.job_id}:tax:${rate}`;
const publicJob=job=>({ok:true,status:job.state==='issued'?200:202,job_id:job.job_id,
 state:job.state,step:job.step,source_count:job.source_count,line_count:job.line_count,
 chunk_count:job.chunk_count,totals:job.totals,content_hash:job.content_hash||null,
 document:job.document||null,artifact:job.artifact||null,revision_fence:job.inventory_revision});
function verifyInput(input){return validId(input.scope?.tenant_id)&&validId(input.scope?.company_id)&&validId(input.customerId)&&/^\d{4}-(0[1-9]|1[0-2])$/.test(input.month||'');}
async function fence(storage,job){const [pin,meta]=await Promise.all([storage.get('canonical-booking-scope'),storage.get('invoice-source-index:v1:meta')]);
 const period=await invoiceSourceIndexFence(storage,{scope:job,customerId:job.customer_id,month:job.month});if(!same(pin,job)||!same(meta,job)||meta?.complete!==true||!period.ok||period.revision!==job.inventory_revision)throw Error('invoice_inventory_revision_changed');}
async function readJob(storage,input){if(!verifyInput(input))throw Error('monthly_invoice_request_invalid');const job=await storage.get(jobKey(input.scope,input.customerId,input.month));if(!job||!same(job,input.scope)||job.customer_id!==input.customerId||job.month!==input.month)throw Error('invoice_job_missing');return job;}
async function verifiedPage(storage,job,index){const page=await storage.get(pageKey(job,index));if(!page||page.index!==index||page.job_id!==job.job_id||page.lines.length>job.chunk_size||serializedBytes(page)>CHUNK_MAX_BYTES||await hashDocumentSnapshot(page.lines)!==page.hash)throw Error('invoice_chunk_unverified');return page;}

export async function beginInvoiceJob(storage,env,input,{resolveSeller,now=()=>new Date().toISOString()}={}){
 if(env?.COMPANY_MONTHLY_INVOICING_ENABLED!=='1'||env?.BOOKING_RECORD_AUTHORITY_ENABLED!=='1'||!storage?.transaction)return fail('invoice_source_authority_required');
 if(!verifyInput(input)||!validId(input.requestId)||!Number.isSafeInteger(input.chunkSize??250)||(input.chunkSize??250)<1||(input.chunkSize??250)>1000)return fail('monthly_invoice_request_invalid');
 const instant=now();if(input.month>=companyInvoiceMonth(instant))return fail('invoice_period_not_closed');
 const key=jobKey(input.scope,input.customerId,input.month),existing=await storage.get(key);
 const published=await storage.get(prefix(input.scope)+':issue:'+input.customerId+':'+input.month);
 if(published&&!existing)return fail('invoice_period_already_owned');
 if(existing&&existing.state!=='aborted'){if(existing.request_id!==input.requestId)return fail('invoice_job_already_owned');return publicJob(existing);}
 if(existing?.state==='aborted'&&existing.request_id===input.requestId)return publicJob(existing);
 const [pin,meta,sellerResult]=await Promise.all([storage.get('canonical-booking-scope'),storage.get('invoice-source-index:v1:meta'),resolveSeller?.(env,input.scope)]);
 if(!same(pin,input.scope)||!same(meta,input.scope)||meta?.complete!==true)return fail('invoice_inventory_unverified');
 if(!sellerResult?.ok||!sellerResult.seller_snapshot?.legal_name)return fail('seller_identity_incomplete');
 const period=await invoiceSourceIndexFence(storage,input);if(!period.ok)return fail(period.error);
 const job={schema_version:2,key,...input.scope,customer_id:input.customerId,month:input.month,request_id:input.requestId,
 job_id:crypto.randomUUID().replaceAll('-',''),state:'collecting',created_at:instant,step:0,inventory_revision:period.revision,
 cursor:null,source_count:0,line_count:0,chunk_count:0,chunk_size:input.chunkSize??250,totals:{net_cents:0,vat_cents:0,gross_cents:0},
 chain:await hashDocumentSnapshot({schema_version:2,...input.scope,customerId:input.customerId,month:input.month,inventory_revision:period.revision}),
 seller:structuredClone(sellerResult.seller_snapshot),buyer:null,buyer_identity_key:null,currency:null,document:null,artifact:null};
 await storage.transaction(async tx=>{const old=await tx.get(key);if(old&&!(old.state==='aborted'&&old.job_id===existing?.job_id))throw Error('invoice_job_already_owned');await tx.put(key,job);});
 return publicJob(job);
}

export async function advanceInvoiceJob(storage,env,input,{deriveInvoiceContext}={}){
 if(env?.COMPANY_MONTHLY_INVOICING_ENABLED!=='1'||env?.BOOKING_RECORD_AUTHORITY_ENABLED!=='1')return fail('invoice_source_authority_required');
 let job=await readJob(storage,input);if(input.jobId!==job.job_id)return fail('invoice_job_identity_mismatch');
 if(!Number.isSafeInteger(input.expectedStep)||input.expectedStep<0||input.expectedStep>job.step)return fail('invoice_job_step_conflict');
 if(input.expectedStep<job.step||job.state!=='collecting')return publicJob(job);
 await fence(storage,job);
 // The cursor lives exclusively in the durable job. A client cannot skip a page.
 const selected=await invoiceSourceIndexPage(storage,{scope:input.scope,customerId:input.customerId,month:input.month,cursor:job.cursor,limit:Math.max(1,Math.min(100,Math.floor(job.chunk_size/2))),revision:job.inventory_revision});
 if(!selected.ok)return fail(selected.error);
 const lines=[],claims=new Map();
 for(const [key,envelope]of selected.entries){const id=key.slice('canonical-booking:'.length),old=await storage.get(claimKey(input.scope,id));
  if(envelope.record.invoice_document_id||envelope.record.invoice_number||envelope.record.document_core_invoice||envelope.record.booking?.invoice_document_id||envelope.record.booking?.invoice_number)return fail('invoice_source_ownership_unverified');
  // Refunded/adjusted sources require the existing credit-note reconciliation.
  // Never silently subtract cash or invoice the original gross as an adjustment.
  const layers=[envelope.record,envelope.record.booking,envelope.record.payload,...(envelope.record.operational_legs||[])].filter(Boolean);
  if(layers.some(row=>row.refund_required===true||row.credited_at||row.credit_note_document_id||row.refund_status&&!['none','not_required'].includes(row.refund_status)||Number(row.refunded_amount_cents||row.cumulative_refunded_amount_cents||0)>0||row.financial_adjustments?.length))return fail('invoice_financial_adjustment_requires_review');
  const projected=await projectCompanyMonthlyInvoiceRecord({record:await hydrateCanonicalFinancialEvidence(env,envelope.record,id),scope:input.scope,bookingId:id,customerId:input.customerId,month:input.month,deriveInvoiceContext,
   readSourceOwnership:async({legId})=>{const relevant=old?(legId==null?Object.values(old):[old[''],old[legId]].filter(Boolean)):[];return{verified:true,state:relevant.length?'claimed':'unclaimed'};}});
  if(!projected.ok)return fail(projected.error);
  for(const line of projected.lines){if(line.canonical_version!==envelope.version||line.booking_id!==id)return fail('invoice_source_projection_unverified');lines.push(line);}
  if(projected.lines.length)claims.set(id,{previous:old||{},version:envelope.version,legs:projected.lines.map(x=>x.leg_id??'')});
 }
 if(lines.length>job.chunk_size)return fail('invoice_source_requires_smaller_page');
 const chunks=[];let assembled=null;
 if(lines.length){assembled=assembleCompanyMonthlyInvoice({scope:input.scope,customerId:input.customerId,month:input.month,lines,complete:true});if(!assembled.ok)return fail(assembled.error);
  const invoice=assembled.invoice;if(job.currency&&job.currency!==invoice.currency)return fail('invoice_currency_mismatch');if(job.buyer_identity_key&&job.buyer_identity_key!==invoice.buyer_identity_key)return fail('invoice_buyer_identity_mismatch');
  let pageLines=[],pageBytes=2;
  const flush=async()=>{if(!pageLines.length)return;const chunk={schema_version:2,job_id:job.job_id,index:job.chunk_count+chunks.length,lines:pageLines,hash:await hashDocumentSnapshot(pageLines)};if(serializedBytes(chunk)>CHUNK_MAX_BYTES)throw Error('invoice_line_storage_limit');chunks.push(chunk);pageLines=[];pageBytes=2;};
  for(const line of invoice.lines){const size=serializedBytes(line)+1;if(size>CHUNK_MAX_BYTES-1024)return fail('invoice_line_storage_limit');if(pageLines.length&&pageBytes+size>CHUNK_MAX_BYTES-1024)await flush();pageLines.push(line);pageBytes+=size;}await flush();
 }
 const totals={...job.totals};if(assembled)for(const key of Object.keys(totals)){totals[key]+=assembled.invoice.totals[key];if(!Number.isSafeInteger(totals[key]))return fail('invoice_totals_overflow');}
 const next={...job,step:job.step+1,cursor:selected.cursor,source_count:job.source_count+selected.entries.length,line_count:job.line_count+lines.length,
 chunk_count:job.chunk_count+chunks.length,totals,...(assembled?{currency:assembled.invoice.currency,buyer_identity_key:assembled.invoice.buyer_identity_key,buyer:job.buyer||structuredClone(lines[0].billing_policy.buyer_snapshot)}:{})};
 for(const chunk of chunks)next.chain=await hashDocumentSnapshot({previous:next.chain,index:chunk.index,hash:chunk.hash,count:chunk.lines.length});
 if(selected.complete){if(!next.line_count)return fail('invoice_lines_empty');next.state='sealed';next.manifest={schema_version:2,...input.scope,job_id:job.job_id,customer_id:input.customerId,month:input.month,inventory_revision:job.inventory_revision,
   chain:next.chain,chunk_count:next.chunk_count,line_count:next.line_count,source_count:next.source_count,totals:next.totals,currency:next.currency,buyer_identity_key:next.buyer_identity_key,seller:next.seller,buyer:next.buyer};next.content_hash=await hashDocumentSnapshot(next.manifest);}
 await storage.transaction(async tx=>{const current=await tx.get(job.key);if(current?.step!==job.step||current.job_id!==job.job_id)throw Error('invoice_job_step_conflict');await fence(tx,job);
  for(const [id,claim]of claims){const latest=await tx.get(claimKey(input.scope,id));if(stableDocumentJson(latest||{})!==stableDocumentJson(claim.previous))throw Error('invoice_source_already_claimed');const envelope=await tx.get('canonical-booking:'+id);if(envelope?.version!==claim.version)throw Error('invoice_source_revision_changed');
   const changes={...claim.previous};for(const leg of claim.legs){if(changes[leg]||changes['']||(leg===''&&Object.keys(changes).length))throw Error('invoice_source_duplicate');changes[leg]={job_id:job.job_id,batch_key:job.key,canonical_version:claim.version};}await tx.put(claimKey(input.scope,id),changes);}
  if(chunks.length){for(const group of assembled.invoice.tax_groups){const key=taxKey(job,group.vat_rate_percent),old=await tx.get(key)||{vat_rate_percent:group.vat_rate_percent,net_cents:0,vat_cents:0,gross_cents:0};for(const field of ['net_cents','vat_cents','gross_cents']){old[field]+=group[field];if(!Number.isSafeInteger(old[field]))throw Error('invoice_totals_overflow');}await tx.put(key,old);}for(const chunk of chunks)await tx.put(pageKey(job,chunk.index),chunk);}
  await tx.put(job.key,next);
 });
 return publicJob(next);
}

export async function readInvoiceJob(storage,input){return publicJob(await readJob(storage,input));}
export async function readInvoiceJobPage(storage,input){const job=await readJob(storage,input);if(input.jobId!==job.job_id||!Number.isSafeInteger(input.index)||input.index<0||input.index>=job.chunk_count)return fail('invoice_chunk_request_invalid');return{ok:true,page:await verifiedPage(storage,job,input.index),sealed:job.state!=='collecting'};}

// Backpressure means one sealed chunk at a time. Export interruption does not
// mutate the invoice or release claims. A replay produces exactly the same lines.
export async function invoiceJobStream(storage,input){const job=await readJob(storage,input);if(input.jobId!==job.job_id||!['sealed','issuing','issued'].includes(job.state)||await hashDocumentSnapshot(job.manifest)!==job.content_hash)throw Error('invoice_manifest_unverified');let index=-1,chain=await hashDocumentSnapshot({schema_version:2,...input.scope,customerId:input.customerId,month:input.month,inventory_revision:job.inventory_revision}),count=0,ended=false;const totals={net_cents:0,vat_cents:0,gross_cents:0};const encoder=new TextEncoder();
 return new ReadableStream({async pull(controller){try{if(index===-1){controller.enqueue(encoder.encode(JSON.stringify({manifest:job.manifest,content_hash:job.content_hash})+'\n'));index=0;return;}if(index>=job.chunk_count){if(ended){controller.close();return;}if(chain!==job.chain||count!==job.line_count||stableDocumentJson(totals)!==stableDocumentJson(job.totals))throw Error('invoice_manifest_chain_mismatch');ended=true;controller.enqueue(encoder.encode(JSON.stringify({seal:job.content_hash,line_count:count,totals})+'\n'));return;}const page=await verifiedPage(storage,job,index++);chain=await hashDocumentSnapshot({previous:chain,index:page.index,hash:page.hash,count:page.lines.length});count+=page.lines.length;for(const line of page.lines)for(const field of Object.keys(totals)){totals[field]+=line[field];if(!Number.isSafeInteger(totals[field]))throw Error('invoice_totals_overflow');}controller.enqueue(encoder.encode(page.lines.map(line=>JSON.stringify(line)+'\n').join('')));}catch(error){controller.error(error);}}});
}

// Financial publication is separately resumable and uses the existing
// idempotent number allocator. It is a manifest document + immutable annex,
// never a fictitious successful 100k-line PDF render.
export async function publishInvoiceJob(storage,env,input,{allocateReference,now=()=>new Date().toISOString()}={}){
 let job=await readJob(storage,input);if(input.jobId!==job.job_id||input.expectedContentHash!==job.content_hash)return fail('invoice_manifest_unverified');
 if(job.state==='issued'){
  const {content_hash,...snapshot}=job.document||{};
  const artifact=await storage.get(job.key+':job:'+job.job_id+':artifact');
  const journal=await storage.get(prefix(input.scope)+':issue:'+input.customerId+':'+input.month);
  if(!same(journal,input.scope)||journal.job_id!==job.job_id||stableDocumentJson(journal.document)!==stableDocumentJson(job.document))return fail('invoice_publication_unverified');
  if(await hashDocumentSnapshot(job.manifest)!==job.content_hash||!content_hash||await hashDocumentSnapshot(snapshot)!==content_hash||job.document?.monthly_content_hash!==job.content_hash||job.document?.document_number!==job.reference||stableDocumentJson(artifact)!==stableDocumentJson(job.artifact))return fail('invoice_publication_unverified');
  return publicJob(job);
 }if(env?.COMPANY_MONTHLY_INVOICING_ENABLED!=='1'||env?.BOOKING_RECORD_AUTHORITY_ENABLED!=='1')return fail('invoice_source_authority_required');
 if(!['sealed','issuing'].includes(job.state)||await hashDocumentSnapshot(job.manifest)!==job.content_hash)return fail('invoice_manifest_unverified');
 await fence(storage,job);
 const publicationKey=prefix(input.scope)+':issue:'+input.customerId+':'+input.month;
 const publication=await storage.get(publicationKey);
 if(publication&&publication.job_id!==job.job_id)return fail('invoice_period_already_owned');
 if(typeof allocateReference!=='function')return fail('invoice_allocation_pending');
 {
  const reader=(await invoiceJobStream(storage,{...input,jobId:job.job_id})).getReader();
  try{while(!(await reader.read()).done){/* Backpressure verifies each chunk and terminal manifest before numbering. */}}finally{reader.releaseLock();}
 }
 if(job.state==='sealed'){const next={...job,state:'issuing',issued_at:now()};await storage.transaction(async tx=>{const current=await tx.get(job.key);if(current.state!=='sealed'||current.content_hash!==job.content_hash)throw Error('invoice_job_step_conflict');await tx.put(job.key,next)});job=next;}
 const reference=job.reference||await allocateReference({scope:input.scope,contentHash:job.content_hash,issueTimestamp:job.issued_at});if(!/^INV-[A-Za-z0-9_-]+$/.test(reference||''))return fail('invoice_allocation_pending');
 if(!job.reference){const next={...job,reference};await storage.transaction(async tx=>{const current=await tx.get(job.key);if(current.job_id!==job.job_id||current.content_hash!==job.content_hash||current.reference&&current.reference!==reference)throw Error('invoice_allocation_conflict');await tx.put(job.key,next)});job=next;}
 // The annex stays in the existing private company authority. A bucket named
 // PUBLIC_MEDIA is not assumed private. No new binding or public PII artifact.
 const artifact={kind:'private_authority_annex',job_id:job.job_id,content_type:'application/x-ndjson',content_hash:job.content_hash,chunk_count:job.chunk_count,line_count:job.line_count};
 const artifactKey=job.key+':job:'+job.job_id+':artifact',existing=await storage.get(artifactKey);if(existing&&stableDocumentJson(existing)!==stableDocumentJson(artifact))return fail('invoice_artifact_conflict');if(!existing)await storage.put(artifactKey,artifact);
 await fence(storage,job);
 const document={schema_version:2,...input.scope,document_id:'monthly_stream_'+job.content_hash,document_number:reference,lifecycle_state:'issued',issued_at:job.issued_at,
   customer_id:input.customerId,month:input.month,currency:job.currency,totals:job.totals,source_manifest:job.manifest,monthly_content_hash:job.content_hash,
   artifact,pdf_status:'not_rendered'};
 document.content_hash=await hashDocumentSnapshot(document);
 const next={...job,state:'issued',document,artifact:document.artifact};await storage.transaction(async tx=>{const current=await tx.get(job.key);if(current.job_id!==job.job_id||current.content_hash!==job.content_hash)throw Error('invoice_job_step_conflict');await fence(tx,job);if(stableDocumentJson(await tx.get(artifactKey))!==stableDocumentJson(artifact))throw Error('invoice_artifact_unverified');const published=await tx.get(publicationKey);if(published&&published.job_id!==job.job_id)throw Error('invoice_period_already_owned');
 await tx.put(publicationKey,{schema_version:2,...input.scope,customer_id:input.customerId,month:input.month,job_id:job.job_id,document});await tx.put(job.key,next);});return publicJob(next);
}

// A source revision can invalidate preparation. Only an unnumbered job may
// release its own claims, one immutable chunk per call. No timeout releases
// financial ownership and an issuing/issued job is never aborted.
export async function abortInvoiceJob(storage,env,input){
 if(env?.COMPANY_MONTHLY_INVOICING_ENABLED!=='1'||env?.BOOKING_RECORD_AUTHORITY_ENABLED!=='1')return fail('invoice_source_authority_required');
 const job=await readJob(storage,input),pin=await storage.get('canonical-booking-scope');
 if(!same(pin,input.scope)||input.jobId!==job.job_id)return fail('invoice_job_identity_mismatch');
 if(job.state==='aborted')return publicJob(job);
 if(job.reference||!['collecting','sealed','aborting'].includes(job.state))return fail('invoice_job_abort_forbidden');
 if(!Number.isSafeInteger(input.expectedStep)||input.expectedStep>job.step||input.expectedStep<0)return fail('invoice_job_step_conflict');
 if(input.expectedStep<job.step)return publicJob(job);
 const index=job.abort_cursor||0,page=index<job.chunk_count?await verifiedPage(storage,job,index):null;
 const next={...job,state:page?'aborting':'aborted',abort_cursor:index+(page?1:0),step:job.step+1};
 await storage.transaction(async tx=>{
  const current=await tx.get(job.key);if(current.job_id!==job.job_id||current.step!==job.step||current.reference||!['collecting','sealed','aborting'].includes(current.state))throw Error('invoice_job_abort_forbidden');
  const ids=new Set((page?.lines||[]).map(line=>line.booking_id));
  for(const id of ids){const key=claimKey(input.scope,id),claims=await tx.get(key)||{},owned={...claims};
   for(const[leg,claim]of Object.entries(owned))if(claim.job_id===job.job_id&&claim.batch_key===job.key)delete owned[leg];
   if(Object.keys(owned).length)await tx.put(key,owned);else await tx.delete(key);
  }
  if(next.state==='aborted')await tx.put(job.key+':archive:'+job.job_id,next);
  await tx.put(job.key,next);
 });return publicJob(next);
}

export async function readPublishedInvoiceJob(storage,input){
 const job=await readJob(storage,input);if(job.state!=='issued')return fail('monthly_invoice_not_issued');
 const journal=await storage.get(prefix(input.scope)+':issue:'+input.customerId+':'+input.month);
 if(!same(journal,input.scope)||journal.job_id!==job.job_id||stableDocumentJson(journal.document)!==stableDocumentJson(job.document))return fail('invoice_publication_unverified');
 // Reuse the full immutable publication replay verification without allocating.
 return publishInvoiceJob(storage,{}, {...input,jobId:job.job_id,expectedContentHash:job.content_hash});
}
