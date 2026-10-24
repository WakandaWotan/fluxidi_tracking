// Optional relationship metadata. Legacy links retain their existing semantics.
// Ownership never grants availability, a device lease, or vehicle capacity.
export function driverVehicleRelation(driver, vehicle) {
  if(!driver||!vehicle||driver.tenant_id!==vehicle.tenant_id||driver.company_id!==vehicle.company_id)return{ok:false,error:'driver_vehicle_scope_conflict'};
  const type=driver.driver_type||'FLEET_DRIVER';
  if(!['FLEET_DRIVER','PARTNER_DRIVER'].includes(type))return{ok:false,error:'driver_type_invalid'};
  const linked=[driver.assigned_vehicle_id,...(driver.vehicle_ids||[])].filter(Boolean);
  if(!linked.includes(vehicle.vehicle_id))return{ok:false,error:'driver_vehicle_link_missing'};
  if(type==='PARTNER_DRIVER'&&(linked.some(id=>id!==vehicle.vehicle_id)||vehicle.owner_driver_id!==driver.driver_id))return{ok:false,error:'partner_vehicle_owner_conflict'};
  return{ok:true,type,vehicle_id:vehicle.vehicle_id,driver_id:driver.driver_id};
}
