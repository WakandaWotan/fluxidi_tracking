// Incident-bounded INTERNAL inspection. No Worker HTTP route is registered.
// Deliberately cannot perform recovery or infer release from missing evidence.
import {_requireAdmin} from './auth_scope.js';
import {canonicalBookingOperation} from './canonical_booking_authority.mjs';
import {financialEvidenceStore} from './financial_quote_lifecycle.mjs';
import {signCanonicalInspectionRequest,verifyCanonicalInspectionRequest} from './booking_cutover_maintenance.mjs';
import {readCapacitySnapshot,hydrateCapacityRecords,CAPACITY_STORAGE_KEY} from '../../tracking/modules/company_capacity_storage.mjs';

const target={bookingId:'2026-10-030',planning:'PLN-2026-000480',publicReference:'2026-10-000019'};
const company='fluxidi_fluxidi_ddmh9g';
const same=(a,b)=>a?.tenant_id===b?.tenant_id&&a?.company_id===b?.company_id;
const hash=async value=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(value))),v=>v.toString(16).padStart(2,'0')).join('');
const copy=value=>structuredClone(value);
const fail=()=>Response.json({ok:false,error:'inspection_forbidden'},{status:403});
export function authorizeCanonicalInspection(request,env,body){
 try{_requireAdmin(request,new URL(request.url),env);}catch{return false;}
 return request.method==='POST'&&inspectionScopeAllowed(body);
}
function inspectionScopeAllowed(body){
 return body?.action==='canonical_booking_inspection'&&Object.entries(target).every(([k,v])=>body?.[k]===v)
  &&body.scope?.tenant_id===company&&body.scope?.company_id===company;
}
// Internal management call only; no public Worker router is extended.
export async function callCanonicalBookingInspection(request,env){
 const body=await request.clone().json().catch(()=>null);
 if(!authorizeCanonicalInspection(request,env,body))return fail();
 const binding=env.COMPANY_CUSTOMER_IMPORT_COORDINATOR;
 if(!binding?.idFromName||!binding?.get)return Response.json(result(['canonical_binding_unavailable']),{status:503});
 try{
  const coordinator=binding.get(binding.idFromName(`${body.scope.tenant_id}:${body.scope.company_id}`));
  return await coordinator.fetch(new Request('https://internal/',{method:'POST',
   headers:{'content-type':'application/json','x-admin-token':env.ADMIN_TOKEN},body:JSON.stringify(body)}));
 }catch{return Response.json(result(['canonical_binding_unavailable']),{status:503});}
}
const result=missing=>({ok:true,consistency:'incomplete',missing,booking_id:target.bookingId,
 capacity_released:null,financial_claim_released:null});

// Called BEFORE Room.load(): no offer expiry, ledger recovery or alarms.
export async function inspectCapacityWithoutMutation(state,env,request,body){
 if(!inspectionScopeAllowed(body)||!await verifyCanonicalInspectionRequest(env,request))return fail();
 const storage=state.storage,root=copy(await storage.get(CAPACITY_STORAGE_KEY));
 if(root==null)return Response.json(result(['capacity_snapshot']));
 try{
  const ledger=await hydrateCapacityRecords(storage,await readCapacitySnapshot(storage),
   {owner:[target.bookingId],offer:body.offerId?[body.offerId]:[],event:body.eventId?[body.eventId]:[]},body.scope);
  const owner=ledger.owners?.[target.bookingId];
  const claims=Object.values(ledger.claims||{}).filter(x=>x.owner_id===target.bookingId);
  const offers=Object.values(ledger.offers||{}).filter(x=>x.owner_id===target.bookingId);
  const events=Object.values(ledger.dispatch_events||{}).filter(x=>x.owner_id===target.bookingId);
  if([owner,...claims,...offers,...events].filter(Boolean).some(x=>!same(x,body.scope)))return fail();
  const end=await storage.get(CAPACITY_STORAGE_KEY);
  const out=result(owner?[]:['capacity_owner']);
  if(JSON.stringify(root)!==JSON.stringify(end))out.consistency='inconsistent';
  else if(owner)out.consistency='sampled';
  out.fingerprint=await hash(JSON.stringify({root,owner,claims,offers,events}));
  out.owner=owner?{version:owner.version,pending:owner.pending===true,released:owner.released===true}:null;
  out.claims=claims.map(x=>({active:x.active===true,pending:x.capacity_pending===true,retiring:x.retiring===true,version:x.capacity_version}));
  out.offers=offers.map(x=>({state:x.state,version:x.version,reason:x.reason}));
  out.events=events.map(x=>({type:x.type,state:x.state,version:x.version}));
  return Response.json(out);
 }catch{return Response.json(result(['capacity_evidence_unverifiable']));}
}

export async function inspectCanonicalWithoutMutation(state,env,request,body){
 if(!authorizeCanonicalInspection(request,env,body))return fail();
 const storage=state.storage,scope=body.scope,key='canonical-booking:'+target.bookingId;
 const pin=copy(await storage.get('canonical-booking-scope'));
 if(pin&&!same(pin,scope))return fail();
 const envelope=copy(await storage.get(key));
 if(!envelope)return Response.json(result(['canonical_record']));
 if(!same(envelope,scope)||!same(envelope.record,scope))return fail();
 const markers=async()=>({journal:await storage.get('customer-projection-journal-v1'),
  journalIntent:await storage.get('customer-projection-journal-v1:chunk-intent'),
  recovery:await storage.get('canonical-booking-recovery:'+target.bookingId)});
 const beforeMarkers=copy(await markers());
 const out=result([]),r=envelope.record;
 if(r.planning_reference!==target.planning||r.public_reference!==target.publicReference)out.missing.push('canonical_reference_binding');
 out.canonical={version:envelope.version,revision:r.revision,status:r.status??r.stage??null,
  assigned_driver:!!r.assigned_driver_id,assigned_vehicle:!!r.assigned_vehicle_id,
  dispatch_pending:r.dispatch_search?.pending===true,search_deadline:r.asap_search_expires_at??null,
  offer_state:r.dispatch_offer?.state??null,offer_reason:r.dispatch_offer?.reason??null};
 out.recovery={projection_pending:!!envelope.projection_pending,dispatch_retry:!!envelope.dispatch_retry,
  dispatch_handoff:!!envelope.dispatch_handoff,journal_present:beforeMarkers.journal!=null,
  journal_intent_present:beforeMarkers.journalIntent!=null,recovery_marker_present:beforeMarkers.recovery!=null};
 if(!pin)out.missing.push('canonical_scope_pin');
 if(!Number.isSafeInteger(envelope.version)||envelope.version!==r._canonical_version)out.consistency='inconsistent';
 if(Object.values(out.recovery).some(Boolean))out.missing.push('recovery_markers_require_reconciliation');
 // Existing inspect hydrates and validates frozen accepted financial evidence.
 // Missing legacy evidence is NOT interpreted as a released financial claim.
 let inspected;
 try{inspected=await canonicalBookingOperation(state,env,{operation:'inspect',scope,bookingId:target.bookingId});}
 catch{out.missing.push('financial_evidence_unverifiable');}
 if(!inspected?.ok||!r._canonical_financial_evidence_ref)out.missing.push('accepted_financial_reference');
 out.financial={accepted_reference_verified:inspected?.ok===true&&!!r._canonical_financial_evidence_ref};
 let financialBefore=null;
 const readFinancial=async()=>{
  const evidence=inspected?.record?.financial_evidence??inspected?.record?.booking?.financial_evidence;
  if(!evidence)return null;
  const store=financialEvidenceStore(env,scope);
  return store?.inspectIntent({quoteId:evidence.id,scope,inputs:evidence.inputs});
 };
 try{financialBefore=await readFinancial();}catch{out.missing.push('financial_claim_unverifiable');}
 if(financialBefore?.claim?.booking_id===target.bookingId&&financialBefore?.frozen?.booking_id===target.bookingId
   &&Number.isSafeInteger(financialBefore.claim.revision)){
  out.financial.claim_state=financialBefore.claim.state;out.financial.claim_revision=financialBefore.claim.revision;
 }else out.missing.push('financial_claim_binding');
 let intentKey=null,intentBefore=null;
 if(r._canonical_financial_evidence_ref?.quote_id){
  intentKey='initial-booking-intent:'+await hash(`financial_booking_intent:${scope.tenant_id}:${scope.company_id}:${r._canonical_financial_evidence_ref.quote_id}`);
  intentBefore=copy(await storage.get(intentKey));
 }
 out.idempotency={verified:!!intentBefore&&same(intentBefore,scope)&&intentBefore.bookingId===target.bookingId};
 if(!out.idempotency.verified)out.missing.push('canonical_idempotency_binding');
 let first=null,second=null;
 const readCapacity=async()=>{
  if(!env.COMPANY_TRACKING?.get||!env.COMPANY_TRACKING?.idFromName)return null;
  const room=env.COMPANY_TRACKING.get(env.COMPANY_TRACKING.idFromName(`${scope.tenant_id}\n${scope.company_id}`));
  const internal=await signCanonicalInspectionRequest(env,new Request('https://internal/canonical-inspection',{method:'POST',
   body:JSON.stringify({...body,offerId:r.dispatch_offer?.offer_id,eventId:r.dispatch_search?.event_id})}));
  const response=await room.fetch(internal);
  if(!response.ok)return null;
  const data=await response.json();
  return data?.ok===true&&data.booking_id===target.bookingId?data:null;
 };
 try{first=await readCapacity();second=await readCapacity();}catch{out.missing.push('capacity_transport');}
 out.capacity=first;
 if(!first||!second||first.consistency!=='sampled'||second.consistency!=='sampled')out.missing.push('capacity_snapshot_or_owner');
 if(first?.consistency==='inconsistent'||second?.consistency==='inconsistent'||first?.fingerprint!==second?.fingerprint)out.consistency='inconsistent';
 const expected=r.dispatch_offer?.version??r.dispatch_capacity_checkpoint?.version;
 if(!Number.isSafeInteger(expected))out.missing.push('canonical_capacity_revision');
 else if(first?.owner&&first.owner.version!==expected)out.consistency='inconsistent';
 if(JSON.stringify(envelope)!==JSON.stringify(await storage.get(key))||JSON.stringify(pin)!==JSON.stringify(await storage.get('canonical-booking-scope'))
  ||JSON.stringify(beforeMarkers)!==JSON.stringify(await markers())
  ||intentKey&&JSON.stringify(intentBefore)!==JSON.stringify(await storage.get(intentKey)))out.consistency='inconsistent';
 try{if(JSON.stringify(financialBefore)!==JSON.stringify(await readFinancial()))out.consistency='inconsistent';}
 catch{out.consistency='inconsistent';}
 // This internal branch never claims global transactional snapshot isolation.
 // Financial acceptance/closure may change independently of the company gate.
 out.missing.push('cross_store_financial_revision_fence');
 out.missing=[...new Set(out.missing)];
 return Response.json(out);
}
