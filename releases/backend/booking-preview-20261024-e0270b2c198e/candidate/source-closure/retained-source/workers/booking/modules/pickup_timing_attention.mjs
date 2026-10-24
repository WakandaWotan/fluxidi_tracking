import { operationalRideBlocking } from './operational_itinerary.mjs';
// The existing Core approach response is an estimate, never a price or right
// to START. Whitelist it before persistence or a list projection; no positions
// or exceptions are copied. Unavailable/expired evidence stays explicitly null.
export function sanitizeAsapEtaAdvisory(value, nowMs=Date.now()) {
  const range=value?.eta_range_seconds,generated=value?.generated_at_ms,until=value?.valid_until_ms;
  if(value?.source!=='fluxidi/local-product-estimate'||value?.estimated!==true||value?.certified_eta!==false
    ||typeof value.duration_seconds!=='number'||!Number.isFinite(value.duration_seconds)||value.duration_seconds<0
    ||!Array.isArray(range)||range.length!==2||range.some(x=>typeof x!=='number'||!Number.isFinite(x)||x<0)||range[1]<range[0]
    ||value.duration_seconds<range[0]||value.duration_seconds>range[1]
    ||!Number.isSafeInteger(generated)||generated>nowMs||!Number.isSafeInteger(until)||until<=nowMs||until>generated+15000
    ||typeof value.arrival_at!=='string'||Date.parse(value.arrival_at)!==generated+range[1]*1000)return null;
  return {status:'available',estimated:true,source:value.source,certified_eta:false,duration_seconds:value.duration_seconds,
    eta_range_seconds:[...range],arrival_at:new Date(generated+range[1]*1000).toISOString(),generated_at_ms:generated,valid_until_ms:until};
}
// An attention flag is advisory. Clock time never proves no-show or completion.
export function projectPickupTimingAttention(record, legType = '', nowMs = Date.now()) {
  if (['COMPLETED','CANCELLED','CANCELED','NO_SHOW','STOPPED','REJECTED'].includes(String(record?.status).toUpperCase())) return null;
  const raw = record?.dispatch_timing_attention;
  if(raw?.reason==='asap_eta_updated') {
    const legs=record.operational_legs||record.booking?.operational_legs||[],leg=legs.find(x=>x.leg_type==='outbound')||record;
    if(record.pickup_mode!=='asap'||legType&&legType!=='outbound'||!Array.isArray(raw.leg_types)||!raw.leg_types.includes('outbound')
      ||!leg.assigned_driver_id||!leg.assigned_vehicle_id
      ||operationalRideBlocking(leg)||leg.trip?.started_at
      ||['COMPLETED','CANCELLED','CANCELED','NO_SHOW','STOPPED','REJECTED'].includes(String(leg.status).toUpperCase())
      ||raw.scheduled_pickups?.outbound!==(leg.pickup_iso||record.pickup_iso||record.booking?.pickup_iso))return null;
    return {reason:'asap_eta_updated',leg_types:['outbound'],eta:sanitizeAsapEtaAdvisory(raw.eta,nowMs)};
  }
  if(raw?.reason !== 'pickup_overdue' || !Array.isArray(raw.leg_types)) return null;
  const legs = record.operational_legs || record.booking?.operational_legs || [];
  const types = [...new Set(raw.leg_types)].filter(type => {
    if(!['outbound','return'].includes(type) || legType && legType !== type) return false;
    const source = legs.find(row=>row.leg_type===type) || record;
    if(operationalRideBlocking(source) || source.trip?.started_at
      || ['COMPLETED','CANCELLED','NO_SHOW','STOPPED','REJECTED'].includes(String(source.status).toUpperCase())) return false;
    const pickup = source.pickup_iso || (type==='return' ? record.return_pickup_iso || record.booking?.return_pickup_iso
      : record.pickup_iso || record.booking?.pickup_iso);
    return raw.scheduled_pickups?.[type] === pickup && Number.isFinite(Date.parse(pickup)) && Date.parse(pickup)<=nowMs;
  });
  if(!types.length) return null;
  return {reason:'pickup_overdue',leg_types:types,scheduled_pickups:Object.fromEntries(types.map(type=>[type,raw.scheduled_pickups[type]])),
    ...(Number.isFinite(Date.parse(raw.detected_at)) ? {detected_at:raw.detected_at} : {})};
}
