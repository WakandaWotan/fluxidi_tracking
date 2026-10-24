// Normalizes durable server acceptance evidence, never an authorization input.
// A personal driver acceptance is distinct from an actual vehicle duty.
export function frozenRideExecutionIdentityV1(identity,scope,driverId,vehicleId){
 if(!identity||identity.tenant_id!==scope?.tenant_id||identity.company_id!==scope?.company_id
  ||!driverId||!vehicleId||identity.driver_id!==driverId||identity.vehicle_id!==vehicleId)return null;
 const base={tenant_id:scope.tenant_id,company_id:scope.company_id,driver_id:driverId,vehicle_id:vehicleId};
 if(identity.kind==='personal_driver_session'){
  if(identity.duty_id!=null||typeof identity.acceptance_id!=='string'
   ||!/^acceptance:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(identity.acceptance_id))return null;
  return {...base,kind:identity.kind,acceptance_id:identity.acceptance_id};
 }
 if(identity.kind!=null||identity.acceptance_id!=null||typeof identity.duty_id!=='string'||!identity.duty_id)return null;
 return {...base,duty_id:identity.duty_id};
}
