import { parseCompanyMissionTariff } from './company_mission_tariff_config.mjs';
import { resolveCompanyMissionRoute } from './company_mission_route.mjs';
import { quoteCompanyMission } from './company_mission_pricing.mjs';
import {nationalFinancialRequestInfoV1} from './financial_national_request_v1.mjs';
const unavailable = reason => ({handled:true,ok:false,request_quote:true,reason});
const city = value => typeof value==='string' ? value.trim().toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/[-\s]+/g,' ') : '';

// Called by both quote and booking. All configuration, category and VAT values
// must be resolved by the backend; client money/route metrics are never read.
export async function quoteConfiguredCompanyMission({enabled,tariff,excluded=false,vehicleCategory,pickup,destination,stops,
  pickupLocalDate,billingMode,waitingMinutes=0,vatRate,geocode,directions,municipality,financialRequest=null,scope=null}) {
  if (!enabled || excluded || tariff == null || tariff.enabled===false) return {handled:false};
  const parsed=parseCompanyMissionTariff(tariff);
  if (!parsed.ok) return unavailable('mission_tariff_invalid');
  if (!vehicleCategory || !tariff.categories[vehicleCategory]) return unavailable('vehicle_tariff_missing');
  if (!['immediate','business_invoice'].includes(billingMode)) return unavailable('billing_mode_required');
  if (typeof vatRate!=='number' || !Number.isFinite(vatRate) || vatRate<0 || vatRate>1) return unavailable('vat_rate_required');
  if (typeof waitingMinutes!=='number' || !Number.isFinite(waitingMinutes) || waitingMinutes<0) return unavailable('waiting_minutes_invalid');
  // Holiday and invalid date checks do not require paid upstream routing.
  const preflight=quoteCompanyMission({tariff,vehicleCategory,missionKm:0,missionMinutes:0,pickupLocalDate,billingMode});
  if (!preflight.ok && ['exception_day','pickup_local_date_required'].includes(preflight.reason)) return unavailable(preflight.reason);
  const own=financialRequest==null?null:nationalFinancialRequestInfoV1(financialRequest);
  if(financialRequest!=null&&(!own||own.scope.tenant_id!==scope?.tenant_id||own.scope.company_id!==scope?.company_id))return unavailable('mission_route_provider_not_approved');
  const routeProvider=own?'fluxidi-national':tariff.route_provider ?? 'mapbox';
  // New financial route sources require explicit approval; Google is oracle-only.
  if (routeProvider !== 'mapbox'&&!own) return unavailable('mission_route_provider_not_approved');
  const selectedDirections=own?financialRequest.directions:directions;
  if (typeof selectedDirections!=='function') return unavailable('mission_route_provider_unavailable');
  const route=await resolveCompanyMissionRoute({depot:tariff.depot,pickup,destination,stops,geocode,directions:selectedDirections,financialRequest,scope});
  if (!route.ok) return unavailable(route.reason);
  let municipalities;
  try {
    if(own){const points=await Promise.all([pickup,destination].map(p=>typeof p==='string'?financialRequest.geocode(p):p));municipalities=await financialRequest.municipality(points);}
    else municipalities=await municipality(pickup,destination);
  } catch { return unavailable('local_municipality_unresolved'); }
  if (!Array.isArray(municipalities) || municipalities.length!==2 || municipalities.some(v=>!city(v))) return unavailable('local_municipality_unresolved');
  const localRide=municipalities.every(v=>city(v)===city(tariff.local_municipality));
  const evaluated=quoteCompanyMission({tariff,vehicleCategory,...route,missionMinutes:route.missionMinutes+waitingMinutes,
    pickupLocalDate,billingMode,localRide,waitingMinutes});
  if (!evaluated.ok) return unavailable(evaluated.reason);
  const base=evaluated.amount_cents;
  const inclusive=evaluated.vat_basis==='inclusive';
  const inclCents=inclusive ? base : Math.round(base*(1+vatRate));
  const exCents=inclusive ? Math.round(base/(1+vatRate)) : base;
  return {handled:true,ok:true,route_evidence:route.route_evidence,tariff_evidence:structuredClone(tariff),
    vehicle_pricing:{category:vehicleCategory,vehicle_ids:[...(tariff.categories[vehicleCategory].vehicle_ids??[])]},
    pricing:{price_ex_vat:exCents/100,price_vat:(inclCents-exCents)/100,price_incl_vat:inclCents/100,
    note:'Bedrijfstarief op basis van de volledige opdracht. Bevestiging na acceptatie.',
    breakdown:{kind:'company_mission',route_provider:routeProvider,price_rounding:tariff.price_rounding ?? 'cent',vehicle_category:vehicleCategory,local_meter:localRide,vat_mode:inclusive?'incl':'excl',vat_rate:vatRate,
      mission_distance_km:route.missionKm,mission_duration_min:route.missionMinutes+waitingMinutes,occupied_distance_km:route.occupiedKm,
      waiting_minutes:waitingMinutes,tariff_amount_cents:base,minimum_applied:evaluated.minimum_applied,
      distance_amount_cents:evaluated.distance_amount_cents,minimum_amount_cents:evaluated.minimum_amount_cents,
      total_ex:exCents/100,vat_amount:(inclCents-exCents)/100,total_incl:inclCents/100}}};
}
