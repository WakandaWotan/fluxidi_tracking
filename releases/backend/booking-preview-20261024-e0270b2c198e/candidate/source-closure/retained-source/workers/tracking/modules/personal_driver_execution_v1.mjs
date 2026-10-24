import {driverDispatchDevices} from './dispatch_device_capability.mjs';
import {frozenRideExecutionIdentityV1} from '../../shared/ride_execution_identity_v1.mjs';
// Private Room binding input only. Public Booking endpoints construct this
// context themselves and never forward a client execution/auth assertion.
export function personalDriverExecutionV1({input,devices,duty,offer,nowMs=Date.now()}){
 const a=input?.personal_execution_auth;
 if(a?.source!=='booking_personal_driver_session_v1'||a.tenant_id!==input.tenant_id||a.company_id!==input.company_id
  ||a.driver_id!==input.driver_id||a.vehicle_id!==input.vehicle_id||a.device_key!==input.device_key
  ||!Number.isFinite(a.session_expires_ms)||a.session_expires_ms<=nowMs)return null;
 const registered=driverDispatchDevices(devices,input,input.driver_id,nowMs,input.device_key);
 if(registered.length!==1||registered[0].vehicle_device_id)return null;
 // A personal login may never take over an active/paused vehicle duty.
 if(duty?.duties?.some(d=>d.ended_at_ms===null&&(d.driver_id===input.driver_id||d.vehicle_id===input.vehicle_id)))return null;
 if(!offer||offer.tenant_id!==input.tenant_id||offer.company_id!==input.company_id
  ||offer.offer_id!==input.offer_id||offer.version!==input.version||offer.human_acceptance_required!==true
  ||!offer.claims?.some(c=>c.driver_id===input.driver_id&&c.vehicle_id===input.vehicle_id))return null;
 const previous=offer.receipts?.[input.driver_id]?.execution_identity;
 if(previous)return frozenRideExecutionIdentityV1(previous,input,input.driver_id,input.vehicle_id);
 return {tenant_id:input.tenant_id,company_id:input.company_id,driver_id:input.driver_id,vehicle_id:input.vehicle_id,
  kind:'personal_driver_session',acceptance_id:'acceptance:'+crypto.randomUUID()};
}
