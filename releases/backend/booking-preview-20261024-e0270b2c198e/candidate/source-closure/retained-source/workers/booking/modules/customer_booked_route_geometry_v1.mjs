import {verifyBookingFinancialEvidence} from './financial_quote_lifecycle.mjs';
// Cold, already-authorized booking grant only. Reuse its immutable passenger
// route, including an archived provider route, without issuing any new route.
// Never publish whole mission/depot legs, money, GPS or a new ETA assertion.
export async function customerBookedRouteGeometryV1({record,source,legType,customerId,pickup,destination}){
 try{
  if(!['outbound','return'].includes(legType)||!source||source.operational_route)return null;
  for(const [key,aliases]of Object.entries({tenant_id:['tenant_id','tenantId'],company_id:['company_id','companyId']})){
    const expected=record?.[key]??record?.booking?.[key];
    if(aliases.some(alias=>source[alias]!=null&&source[alias]!==expected))return null;
  }
  const evidence=await verifyBookingFinancialEvidence(record);
  if(!evidence||!customerId||evidence.inputs?.financial_context?.customer_id!==customerId)return null;
  const routeOut=legType==='return'?evidence.money.snapshot?.returnRoute:evidence.money.snapshot?.routeOut;
  const route=routeOut?.route,points=routeOut?.financial_route?.points,geometry=route?.geometry;
  const point=p=>p&&typeof p.lat==='number'&&typeof p.lng==='number'&&Number.isFinite(p.lat)&&Number.isFinite(p.lng)&&Math.abs(p.lat)<=90&&Math.abs(p.lng)<=180;
  const same=(a,b)=>point(a)&&b&&typeof b.latitude==='number'&&typeof b.longitude==='number'&&Number.isFinite(b.latitude)&&Number.isFinite(b.longitude)&&Math.abs(a.lat-b.latitude)<=1e-7&&Math.abs(a.lng-b.longitude)<=1e-7;
  if(!Array.isArray(points)||points.length<2||points.length>8||!points.every(point)||!same(points[0],pickup)||!same(points.at(-1),destination)
    ||geometry?.type!=='LineString'||!Array.isArray(geometry.coordinates)||geometry.coordinates.length<2||geometry.coordinates.length>100000
    ||geometry.coordinates.some(p=>!Array.isArray(p)||p.length!==2||!point({lng:p[0],lat:p[1]})))return null;
  return {schema:'fluxidi-booked-route-geometry-v1',type:'LineString',
    pickup:{latitude:pickup.latitude,longitude:pickup.longitude},
    destination:{latitude:destination.latitude,longitude:destination.longitude},
    coordinates:geometry.coordinates.map(p=>[...p])};
 }catch{return null;}
}
