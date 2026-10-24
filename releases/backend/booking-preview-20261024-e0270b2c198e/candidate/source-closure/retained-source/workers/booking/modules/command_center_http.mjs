import {resolveModernSubscriptionPrice} from './subscription_paid_catalog.mjs';
import { affiliatePerson } from './affiliate_http.mjs';
import { affiliateOperation } from './affiliate_ledger.mjs';
import { companySubscriptionFacts } from './company_subscription_facts.mjs';
import { resolveFirstUseTrial } from './company_first_use_trial.mjs';
import {loadInternalDevSubscriptionExemption,isScopedInternalDevSubscriptionExempt} from './internal_dev_subscription_exemption.mjs';
import {commandCenterRegistryPage} from './command_center_registry.mjs';
import {commandCenterProjection} from './command_center_projection.mjs';
import {commandCenterIntegrationFacts} from './command_center_integrations.mjs';
import {commandCenterTaxFacts} from './command_center_tax.mjs';
import {commandCenterInvoiceDrafts} from './command_center_invoice_drafts.mjs';
import {commandCenterProviderPayments,commandCenterProviderSubscriptions} from './command_center_provider_payments.mjs';

const response = (body,status=200) => Response.json(body,{status,headers:{'cache-control':'private, no-store'}});
const failure = (error,status) => response({ok:false,error},status);
const codePattern = /^FLX-[0-9]{4,12}$/;
const safeScope = value => typeof value === 'string' && value.length <= 80 && /^[A-Za-z0-9._-]+$/.test(value) && !value.includes('..') && value !== 'global';

export async function handleCommandCenterRequest({request,url,env,loadCustomerSession,loadGlobalIdentity,resolveCompany,loadAccount,loadProfile,loadOverride,loadBusinessProfile,manageCompany,readProviderPayments=commandCenterProviderPayments,now=Date.now()}) {
  if (!url.pathname.startsWith('/command-center/')) return null;
  if (env.COMMAND_CENTER_READ_ENABLED !== '1') return failure('command_center_not_enabled',503);
  const management=/^\/command-center\/companies\/(FLX-[0-9]{4,12})\/(account|trial-entitlement)$/.exec(url.pathname);
  if (request.method !== 'GET'&&!(management&&request.method==='POST')) return failure('method_not_allowed',405);
  const match = management||/^\/command-center\/companies\/(FLX-[0-9]{4,12})\/(subscription|projection|payments|invoice-drafts|provider-payments|provider-subscriptions|paid-options)$/.exec(url.pathname);
  const directory=url.pathname==='/command-center/companies';
  const identity=url.pathname==='/command-center/identity';
  if (!identity&&!directory&&(!match || !codePattern.test(match[1]))) return failure('route_not_found',404);
  try {
    const person = await affiliatePerson(request,env,loadCustomerSession,loadGlobalIdentity);
    if (!person) return failure('personal_login_required',401);
    const authorize = async () => {
      const result = await affiliateOperation(env,'capability',{person_id:person.customer_id});
      return result.ok && result.role === 'ceo';
    };
    if (!await authorize()) return failure('ceo_required',403);
    if(management&&(env.COMMAND_CENTER_COMPANY_MANAGEMENT_ENABLED!=='1'||person.customer_id!==env.COMMAND_CENTER_MANAGEMENT_OWNER_ID||typeof manageCompany!=='function'))return failure('company_management_not_enabled',403);
    if(identity){
      const current=await affiliatePerson(request,env,loadCustomerSession,loadGlobalIdentity);
      if(current?.customer_id!==person.customer_id||!await authorize())return failure('authorization_changed',403);
      return response({ok:true,schema_version:'command_center_identity_v1',person_id:person.customer_id,role:'ceo'});
    }
    if(directory){
      const page=Number(url.searchParams.get('page')||'1');
      const generation=url.searchParams.has('generation')?Number(url.searchParams.get('generation')):null;
      const rows=await commandCenterRegistryPage(env.BOOKING_KV,{page,generation});
      const current=await affiliatePerson(request,env,loadCustomerSession,loadGlobalIdentity);
      if(current?.customer_id!==person.customer_id||!await authorize())return failure('authorization_changed',403);
      return response({ok:true,provenance:'booking_company_registry',...rows});
    }
    const company = await resolveCompany(env,match[1]);
    if (!company || company.company_code !== match[1] || !safeScope(company.tenant_id) || !safeScope(company.company_id)) return failure('company_not_found',404);
    const scope = {tenant_id:company.tenant_id,company_id:company.company_id,company_code:match[1]};
    if(management){
      let body={};
      if(request.method==='POST'){
        if(!request.headers.get('content-type')?.startsWith('application/json'))return failure('json_required',400);
        const raw=await request.text();if(raw.length>8192)return failure('body_too_large',413);
        try{body=JSON.parse(raw);}catch{return failure('invalid_body',400);}
        const allowed=match[2]==='account'?['action','reason','confirmation']:['vehicles_allowed','drivers_allowed','trial_ends_at','reason','preview_only'];
        if(!body||typeof body!=='object'||Array.isArray(body)||Object.keys(body).some(key=>!allowed.includes(key)))return failure('management_field_not_allowed',400);
        if(typeof body.reason!=='string'||body.reason.trim().length<3||body.reason.length>500)return failure('reason_required',400);
        if(match[2]==='account'&&!['confirm','pause','resume','block','unblock','close'].includes(body.action))return failure('action_not_available',400);
        if(body.action==='close'&&(body.confirmation?.company_code!==scope.company_code||typeof body.confirmation?.display_name!=='string'||!body.confirmation.display_name.trim()))return failure('close_confirmation_required',409);
      }
      const current=await affiliatePerson(request,env,loadCustomerSession,loadGlobalIdentity);
      if(current?.customer_id!==person.customer_id||!await authorize())return failure('authorization_changed',403);
      // Scope and actor come only from the verified registry and personal identity.
      return await manageCompany({resource:match[2],method:request.method,scope,body:{...body,...scope,actor_id:person.customer_id}});
    }
    if(match[2]==='paid-options'){
      const stored=await loadProfile(env,scope),profile=stored?.subscription_profile??stored;
      if(profile?.tenant_id!==scope.tenant_id||profile?.company_id!==scope.company_id)return failure('source_scope_conflict',503);
      const options=['standard','smart'].map(plan_code=>resolveModernSubscriptionPrice(env,{market:profile.market,plan_code,nowMs:now}));
      const current=await affiliatePerson(request,env,loadCustomerSession,loadGlobalIdentity);
      if(current?.customer_id!==person.customer_id||!await authorize())return failure('authorization_changed',403);
      if(options.some(option=>!option.ok))return failure('subscription_paid_plan_catalog_unavailable',503);
      return response({ok:true,schema_version:'command_center_paid_options_v1',provenance:'reviewed_server_paid_catalog',company_code:scope.company_code,generated_at:new Date(now).toISOString(),checkout_available:false,options});
    }
    if(match[2]==='provider-subscriptions'){
      const links=await commandCenterProviderSubscriptions(env,scope,url.searchParams,{now});
      const current=await affiliatePerson(request,env,loadCustomerSession,loadGlobalIdentity);
      if(current?.customer_id!==person.customer_id||!await authorize())return failure('authorization_changed',403);
      return response({...links,company_code:scope.company_code});
    }
    if(match[2]==='provider-payments'){
      if(env.COMMAND_CENTER_PROVIDER_PAYMENTS_READ_ENABLED!=='1')return failure('provider_payments_not_enabled',503);
      const stored=await loadProfile(env,scope),profile=stored?.subscription_profile??stored;
      if(profile?.tenant_id!==scope.tenant_id||profile?.company_id!==scope.company_id)return failure('source_scope_conflict',503);
      const payments=await readProviderPayments(env,scope,stored,url.searchParams,{now});
      const current=await affiliatePerson(request,env,loadCustomerSession,loadGlobalIdentity);
      if(current?.customer_id!==person.customer_id||!await authorize())return failure('authorization_changed',403);
      return response({...payments,company_code:scope.company_code});
    }
    if(match[2]==='invoice-drafts'){
      const drafts=await commandCenterInvoiceDrafts(env,scope,url.searchParams);
      const current=await affiliatePerson(request,env,loadCustomerSession,loadGlobalIdentity);
      if(current?.customer_id!==person.customer_id||!await authorize())return failure('authorization_changed',403);
      return response({...drafts,company_code:scope.company_code});
    }
    if(match[2]==='payments'){
      const payments=await affiliateOperation(env,'cc_company_receipts',{person_id:person.customer_id,tenant_id:scope.tenant_id,company_id:scope.company_id,cursor:url.searchParams.get('cursor')||'',limit:Number(url.searchParams.get('limit')||50)},{actor_id:person.customer_id,admin:true,server_admin:false});
      const current=await affiliatePerson(request,env,loadCustomerSession,loadGlobalIdentity);
      if(current?.customer_id!==person.customer_id||!await authorize())return failure('authorization_changed',403);
      if(!payments.ok||payments.schema_version!=='command_center_company_receipts_v1'||payments.provenance!=='verified_receipt_ledger'||payments.complete_provider_history!==false)return failure('payment_source_unavailable',503);
      return response({...payments,company_code:scope.company_code,capture_enabled:env.AFFILIATE_PROGRAM_ENABLED==='1'});
    }
    const [account,rawProfile,override,internalDevExemption] = await Promise.all([loadAccount(env,scope),loadProfile(env,scope),loadOverride(env,scope),loadInternalDevSubscriptionExemption(env.BOOKING_KV,{tenantId:scope.tenant_id,companyId:scope.company_id})]);
    const profile=rawProfile?.subscription_profile??rawProfile;
    const business=match[2]==='projection'?await loadBusinessProfile(env,scope):null;
    const integrations=match[2]==='projection'?await commandCenterIntegrationFacts(env,scope):null;
    const tax=match[2]==='projection'?await commandCenterTaxFacts(env,scope,now):null;
    // Role revocation and session invalidation during source IO prevent release.
    const current = await affiliatePerson(request,env,loadCustomerSession,loadGlobalIdentity);
    if (current?.customer_id !== person.customer_id || !await authorize()) return failure('authorization_changed',403);
    if (!profile || typeof profile !== 'object' || Array.isArray(profile)) return failure('subscription_source_unavailable',503);
    if([account,profile].some(row=>row&&((row.tenant_id&&row.tenant_id!==scope.tenant_id)||(row.company_id&&row.company_id!==scope.company_id)))) return failure('source_scope_conflict',503);
    const effectiveProfile=isScopedInternalDevSubscriptionExempt(internalDevExemption,scope)?profile:await resolveFirstUseTrial(env,scope,profile,{now});
    const facts=companySubscriptionFacts({profile:effectiveProfile,account,override,internalDevExemption,scope,now});
    if(match[2]==='projection')return response({ok:true,...commandCenterProjection({scope,index:company,businessProfile:business,rawSubscription:{...rawProfile,subscription_profile:effectiveProfile},account,facts,observedAt:new Date().toISOString()}),integrations,tax});
    return response({ok:true,provenance:'booking_authority',company_code:match[1],facts});
  } catch (_) { return failure('command_center_source_unavailable',503); }
}
