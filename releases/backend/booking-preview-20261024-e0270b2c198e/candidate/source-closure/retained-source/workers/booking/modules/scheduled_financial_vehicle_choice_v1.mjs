import {financialEvidenceStore,verifyBookingFinancialEvidence} from './financial_quote_lifecycle.mjs';
import {mapboxAutomaticDispatchEnabledV1} from './mapbox_quote_request_v1.mjs';
import {asapSearchState} from './asap_dispatch_timing.mjs';

// Later uses its existing planned allocator, not an ASAP selection lease.
// Only a durable, accepted, customer/vehicle-bound sale can enter that path.
// This does not attest current availability: the allocator still checks it.
export async function scheduledFinancialVehicleChoiceV1(env,scope,bookingId,record){
 try{
  if(!bookingId)return null;
  const evidence=await verifyBookingFinancialEvidence(record),inputs=evidence?.inputs;
  const provider=evidence?.version===2&&inputs?.pricing_options?.booking_mode==='provider_automatic'&&mapboxAutomaticDispatchEnabledV1(env,scope);
  if(record?.pickup_mode!=='scheduled'&&!provider)return null;
  if(!evidence||evidence.scope.tenant_id!==scope.tenant_id||evidence.scope.company_id!==scope.company_id
   ||inputs?.pricing_options?.pickup_mode!==(provider?record.pickup_mode:'scheduled')
   ||inputs.financial_context?.schema!=='fluxidi-vehicle-financial-context-v1'
   ||!inputs.financial_context.customer_id||!inputs.vehicle
   ||!(evidence.route?.source==='fluxidi-national'||provider))return null;
  const when=Date.parse(inputs.pricing_options.pickup_iso);
  const times=[record.pickup_iso,record.pickupStartIso,
   record.booking?.pickup_iso,record.booking?.pickupStartIso].filter(v=>v!=null&&v!=='');
  if(!Number.isFinite(when)||!times.length)return null;
  if(provider&&record.pickup_mode==='asap'){
    const search=asapSearchState(record);if(!search.valid||search.expired)return null;
  }else if(times.some(v=>Date.parse(v)!==when))return null;
  const aliases=['vehicle_id','vehicleId','required_vehicle_id','requiredVehicleId',
   'preferred_vehicle_id','preferredVehicleId','customer_requested_vehicle_id','requested_vehicle_id'];
  const values=[record,record.booking,record.payload].filter(Boolean)
   .flatMap(row=>aliases.map(k=>row[k]).filter(v=>v!=null&&v!==''));
  if(!values.length||values.some(v=>v!==inputs.vehicle))return null;
  const store=financialEvidenceStore(env,scope);
  if(!store)return null;
  const accepted=await store.readAccepted({bookingId,scope,inputs});
  return accepted?.booking_id===bookingId&&accepted.evidence.id===evidence.id?inputs.vehicle:null;
 }catch{return null;}
}
