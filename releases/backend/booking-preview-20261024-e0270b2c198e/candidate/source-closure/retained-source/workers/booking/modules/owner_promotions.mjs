// Canonical business-profile capability. Only an explicit boolean true enables
// promotions; no company names, global defaults, or subscription dependencies.
export function ownerPromotionsEnabled(profile) {
  return profile?.show_owner_promotions === true;
}

export function projectOwnerPromotions(profile) {
  return { show_owner_promotions: ownerPromotionsEnabled(profile) };
}

export function parseOwnerPromotionsBody(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body) ||
      Object.keys(body).some(key => !['tenant_id', 'company_id', 'show_owner_promotions'].includes(key)) ||
      typeof body.show_owner_promotions !== 'boolean') {
    return { ok: false, error: 'explicit_owner_promotions_boolean_required' };
  }
  return { ok: true, enabled: body.show_owner_promotions };
}

export function applyOwnerPromotions(existing, enabled) {
  if (typeof enabled !== 'boolean') throw new TypeError('explicit_boolean_required');
  return { ...existing, show_owner_promotions: enabled };
}
