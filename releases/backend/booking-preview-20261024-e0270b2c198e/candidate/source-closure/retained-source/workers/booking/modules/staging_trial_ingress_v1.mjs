// A staging speed trial may read booking inputs and request bounded quotes.
// It must not accidentally exercise booking, payment, driver or admin writers.
// Keep this list deliberately narrow; add a path only after its side effects
// and provider usage have been reviewed for the isolated staging environment.
const ALLOWED = new Set([
  'GET /public/bootstrap',
  'GET /public/company/resolve',
  'POST /public/customer/booking-capabilities',
  'POST /public/customer/official-address-search',
  'GET /partners/profile',
  'POST /public/quote',
  'POST /public/customer/vehicle-quotes',
]);

export function stagingTrialIngressV1(request, env) {
  const mode = env?.STAGING_TRIAL_MODE === '1';
  const staging = env?.STAGING_TRIAL_ENVIRONMENT === 'staging';
  const stagingDeployment = String(env?.ENVIRONMENT ?? '').trim().toLowerCase() === 'staging';
  if (!mode && !staging && !stagingDeployment) return null;
  if (!mode || !staging) {
    return Response.json({ok:false,error:'staging_trial_configuration_required'},
      {status:503,headers:{'cache-control':'no-store'}});
  }
  if (request.method === 'OPTIONS') return null;
  const url = new URL(request.url);
  const path = url.pathname;
  // The Mapbox capabilities contract selects provider_automatic; it does not
  // need Reliable Choice's persisted selection lease. Enable only this reviewed
  // read path, independently of trial quotes. Auth, official addresses, real
  // duration, occupancy and the shared Directions budget remain in the handler.
  if (request.method === 'GET' && path === '/partners/availability'
    && env?.STAGING_TRIAL_AVAILABILITY_ENABLED === '1'
    && url.searchParams.getAll('booking_mode').length === 1
    && url.searchParams.get('booking_mode') === 'provider_automatic') return null;
  if (ALLOWED.has(`${request.method} ${path}`)) return null;
  return Response.json({ok:false,error:'staging_trial_operation_not_allowed'},
    {status:403,headers:{'cache-control':'no-store'}});
}
