const fail=error=>({ok:false,error,status:409});
// Caller supplies an already authenticated server session and scoped index row.
export function personalDriverDispatchContextV1({session,driver,policy,nowMs=Date.now()}){
 if(!session?.tenant_id||!session.company_id||!session.driver_id||session.vehicle_device_id
  ||!Number.isFinite(nowMs)||!Number.isFinite(Date.parse(session.expires_at))||Date.parse(session.expires_at)<=nowMs
  ||!/^[a-f0-9]{64}$/.test(session.token_hash??''))return fail('personal_driver_auth_required');
 if(policy?.device_binding==='vehicle'||policy?.availability_source==='manual_duty')return fail('vehicle_device_auth_required');
 const assigned=driver?.assigned_vehicle_id??driver?.assignedVehicleId;
 if(!assigned||assigned!==session.assigned_vehicle_id||driver.driver_id&&driver.driver_id!==session.driver_id
  ||driver.tenant_id&&driver.tenant_id!==session.tenant_id||driver.company_id&&driver.company_id!==session.company_id)return fail('vehicle_session_mismatch');
 return {ok:true,vehicle_id:assigned,auth:{source:'booking_personal_driver_session_v1',tenant_id:session.tenant_id,
  company_id:session.company_id,driver_id:session.driver_id,vehicle_id:assigned,device_key:session.token_hash,
  session_expires_ms:Date.parse(session.expires_at)}};
}
