// Direct staging availability requests must carry the actual trip duration.
// Production retains its existing compatibility fallback.
export function stagingAvailabilityDurationV1(env, rawDuration) {
  if (env?.STAGING_TRIAL_MODE !== '1') return null;
  const duration = Number(rawDuration);
  if (rawDuration == null || String(rawDuration).trim() === '' ||
      !Number.isFinite(duration) || duration <= 0) {
    return {ok:false,error:'staging_availability_duration_required',status:422};
  }
  return {ok:true,durationMin:duration};
}
