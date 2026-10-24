import { evaluateDriverEligibility, effectiveWorkState } from './company_dispatch.mjs';

// A chauffeur drives the customer's car, so company-vehicle linkage is irrelevant.
// This is a planning indication, never a reservation or assignment guarantee.
export async function projectPrivateDriverAvailability({ drivers, scope, pickupIso, durationMin,
  presenceMap = {}, liveSnapshot, overlap, nowMs = Date.now() }) {
  const pickupMs = Date.parse(pickupIso);
  if (!Number.isFinite(pickupMs) || pickupMs <= nowMs || !Number.isFinite(durationMin) || durationMin <= 0 || durationMin > 1440) {
    throw new Error('invalid_private_driver_window');
  }
  const output = [];
  for (const driver of drivers || []) {
    const id = String(driver.driver_id ?? driver.driverId ?? driver.id ?? '').trim();
    const hasPrivateRole = Object.hasOwn(driver, 'private_chauffeur_enabled') || Object.hasOwn(driver, 'privateChauffeurEnabled');
    if (hasPrivateRole && driver.private_chauffeur_enabled !== true && driver.privateChauffeurEnabled !== true) continue;
    if (!id || driver.public_profile_enabled !== true || driver.is_active === false || driver.blocked === true ||
        (driver.company_id && driver.company_id !== scope.company_id) ||
        (driver.tenant_id && driver.tenant_id !== scope.tenant_id)) continue;
    let state = 'available';
    const work = effectiveWorkState({ driver, atMs: pickupMs });
    if (!work.roster_configured && work.manual_override?.active !== true) state = 'unknown';
    const evaluation = evaluateDriverEligibility({ driver, pickupIso, durationMin, atMs: nowMs,
      presence: presenceMap[id], vehicles: [], drivers, });
    const reasons = evaluation.reasons.filter(r => r !== 'assignment_driver_no_vehicle');
    if (reasons.includes('assignment_schedule_undeterminable')) state = 'unknown';
    else if (reasons.length) state = 'unavailable';
    // Check the whole hire, including a shift end or break between endpoints.
    if (state === 'available') {
      const endMs = pickupMs + durationMin * 60000;
      for (let t = pickupMs; t < endMs; t = Math.min(t + 60000, endMs)) {
        const slot = effectiveWorkState({ driver, atMs: t });
        if (slot.schedule_undeterminable) { state = 'unknown'; break; }
        if (!slot.working) { state = 'unavailable'; break; }
      }
      if (state === 'available') {
        const lastSlot = effectiveWorkState({ driver, atMs: endMs - 1 });
        if (lastSlot.schedule_undeterminable) state = 'unknown';
        else if (!lastSlot.working) state = 'unavailable';
      }
    }
    if (state === 'available') {
      try {
        const result = await overlap({ scope, driverId: id, vehicleId: '', pickupIso, durationMin,
          roundtripMode: 'single', companyLiveSnapshot: liveSnapshot });
        if (!result.ok) state = result.error === 'assignment_overlap' ? 'unavailable' : 'unknown';
      } catch { state = 'unknown'; }
    }
    output.push({ driver_id: id, availability: state });
  }
  return output;
}
