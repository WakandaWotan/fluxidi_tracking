// Direct Durable Object calls do not pass through the Worker's HTTP ingress.
// Keep mutation-only objects closed while a staging speed trial is configured.
export function stagingTrialDoMarkedV1(env) {
  return env?.STAGING_TRIAL_MODE === '1'
    || env?.STAGING_TRIAL_ENVIRONMENT === 'staging'
    || String(env?.ENVIRONMENT ?? '').trim().toLowerCase() === 'staging';
}

export function stagingTrialDoRefusalV1(env) {
  if (!stagingTrialDoMarkedV1(env)) return null;
  const configured = env?.STAGING_TRIAL_MODE === '1'
    && env?.STAGING_TRIAL_ENVIRONMENT === 'staging';
  return Response.json({ok:false,error:configured
    ? 'staging_trial_operation_not_allowed' : 'staging_trial_configuration_required'},
    {status:configured?403:503,headers:{'cache-control':'no-store'}});
}
