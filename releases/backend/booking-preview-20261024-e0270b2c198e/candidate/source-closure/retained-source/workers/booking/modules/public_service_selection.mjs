// Explicit company settings override an old published profile or saved favorite.
export function selectedPublicService(body = {}) {
  const token = String(body.service_type ?? body.service_category ?? body.service ?? 'taxi').trim().toLowerCase().replace(/[ -]/g, '_');
  if (['private_chauffeur', 'privechauffeur'].includes(token)) return 'private_chauffeur';
  if (token.includes('limousine')) return 'limousine';
  if (token.includes('airport') || body.airport_iata || body.airport_direction) return 'airport_transfer';
  return 'taxi_vvb';
}

export function companyOffersSelectedPublicService(profile, body) {
  if (!profile || !(profile.publicServicesConfigured === true || profile.public_services_configured === true)) return true;
  const ids = profile.publicServiceIds ?? profile.public_service_ids;
  return Array.isArray(ids) && ids.includes(selectedPublicService(body));
}
