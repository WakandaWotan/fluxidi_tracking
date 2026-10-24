// Targeted adapter for the existing national core and existing financial
// evidence contract. Does not change tariffs, money, claims, or verifier rules.
import {readConfiguredSiteReferenceV1} from './configured_site_access_v1.mjs';
const fail=s=>{throw Error(s);};
const scopeSame=(a,b)=>a?.tenant_id===b?.tenant_id&&a?.company_id===b?.company_id;
const finite=n=>typeof n==='number'&&Number.isFinite(n)&&n>=0;
const hash=async value=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(JSON.stringify(value)))),n=>n.toString(16).padStart(2,'0')).join('');
const text=s=>typeof s==='string'&&s.length>0&&s.length<=200;
const point=p=>p&&Number.isFinite(p.latitude)&&Number.isFinite(p.longitude)&&Math.abs(p.latitude)<=90&&Math.abs(p.longitude)<=180&&p.access?.kind!=='gps';

export function createNationalFinancialRouteAdapterV1({scope,policy,router,clock=Date.now}){
 if(!text(scope?.tenant_id)||!text(scope?.company_id)||!scopeSame(scope,router?.scope)||typeof router?.financialRoute!=='function'
   ||policy?.schema!=='fluxidi-national-financial-policy-v1'||policy.state!=='approved'
   ||!text(policy.version)||!text(policy.durationPolicyVersion)||!text(policy.graphVersion)||!text(policy.evidenceRevision)
   ||!['graphManifestSha256','publicationSha256','acceptanceEvidenceSha256'].every(k=>/^[a-f0-9]{64}$/.test(policy[k]??''))
   ||router.scope.graphVersion!==policy.graphVersion||router.scope.evidenceRevision!==policy.evidenceRevision)fail('national_financial_policy_unproven');
 const fixed=structuredClone(scope),sealed=structuredClone(policy);
 return async function resolve(points){
  if(!Array.isArray(points)||points.length<2||points.length>32||!points.every(point))fail('national_financial_points_invalid');
  if(!scopeSame(fixed,router.scope)||router.scope.graphVersion!==sealed.graphVersion||router.scope.evidenceRevision!==sealed.evidenceRevision)fail('national_financial_scope_changed');
  const legs=[],geometry=[];let validUntil=Infinity;
  for(let i=1;i<points.length;i++){
   const endpoint=async(p,role)=>{
    const binding=readConfiguredSiteReferenceV1(p,{scope:fixed});if(!binding)return p;
    if(typeof router.resolveConfiguredSitePoint!=='function')fail('configured_site_runtime_unavailable');
    return router.resolveConfiguredSitePoint({point:{latitude:p.latitude,longitude:p.longitude},binding,role});
   };
   const origin=await endpoint(points[i-1],'origin'),destination=await endpoint(points[i],'destination');
   const now=clock(),r=await router.financialRoute({scope:router.scope,origin,destination,departureAt:now,gpsRoadContext:false});
   const s=r?.staticFinancialEvidence;
   if(!s||s.schema!=='fluxidi-static-financial-road-basis-v1'||!scopeSame(s,fixed)||s.graphVersion!==sealed.graphVersion
     ||s.evidenceRevision!==sealed.evidenceRevision||!scopeSame(r,fixed)||r.graphVersion!==sealed.graphVersion||r.evidenceRevision!==sealed.evidenceRevision
     ||!finite(r.validUntil)||r.validUntil<=clock()||r.evidenceClass!=='EXACT_STATIC_ROUTE'||!finite(s.staticSeconds)||!finite(s.distanceMeters)
     ||s.staticSeconds!==r.seconds||s.distanceMeters!==r.distanceMeters||!text(s.coreEvidenceId)||!Array.isArray(s.edges)
     ||!s.roadAccessEvidence?.origin||!s.roadAccessEvidence?.destination)fail('national_financial_route_unproven');
   validUntil=Math.min(validUntil,r.validUntil);
   if(s.edges.some(e=>!Number.isSafeInteger(e.id)||!Number.isSafeInteger(e.way)||e.way<=0||!Number.isSafeInteger(e.ordinal)||e.ordinal<0
      ||![1,-1].includes(e.direction)||!finite(e.distanceMeters)||!finite(e.seconds)||e.partial!=null&&e.partial!==true))fail('national_financial_edge_unproven');
   const meters=s.edges.reduce((n,e)=>n+e.distanceMeters,0),seconds=s.edges.reduce((n,e)=>n+e.seconds,0);
   if(Math.abs(meters-s.distanceMeters)>1e-6*Math.max(1,meters)||Math.abs(seconds-s.staticSeconds)>1e-6*Math.max(1,seconds))fail('national_financial_totals_conflict');
   if(!Array.isArray(r.geometry)||r.geometry.length<2&&s.distanceMeters>0||r.geometry.some(p=>!point(p)))fail('national_financial_geometry_unproven');
   if(points[i-1].official_address&&!r.addressContext||points[i].official_address&&!r.addressContext)fail('national_financial_address_unproven');
   const edgeDigest=await hash(s.edges),accessDigest=await hash(s.roadAccessEvidence);
   legs.push({distance_m:s.distanceMeters,duration_s:s.staticSeconds,core_evidence_id:s.coreEvidenceId,
    ordered_edge_sha256:edgeDigest,access_evidence_sha256:accessDigest,...(r.addressContext?{official_access_context_id:r.addressContext.id}:{})});
   for(const p of r.geometry){const prev=geometry.at(-1);if(!prev||prev.latitude!==p.latitude||prev.longitude!==p.longitude)geometry.push(structuredClone(p));}
  }
  if(validUntil<=clock())fail('national_financial_route_unproven');
  return {valid_until_ms:validUntil,financial_route:{source:'fluxidi-national',source_version:sealed.graphVersion,profile:'car',duration_basis:'static_normalized',access_cost:'included',
    graph_checksum:sealed.graphManifestSha256,publication_sha256:sealed.publicationSha256,policy_version:sealed.version,
    duration_policy_version:sealed.durationPolicyVersion,acceptance_evidence_sha256:sealed.acceptanceEvidenceSha256,
    tenant_id:fixed.tenant_id,company_id:fixed.company_id,points:points.map(p=>({lat:p.latitude,lng:p.longitude})),legs},
    route:{distance:legs.reduce((n,l)=>n+l.distance_m,0),duration:legs.reduce((n,l)=>n+l.duration_s,0),
      legs:legs.map(l=>({distance:l.distance_m,duration:l.duration_s})),geometry:{type:'LineString',coordinates:geometry.map(p=>[p.longitude,p.latitude])}}};
 };
}
