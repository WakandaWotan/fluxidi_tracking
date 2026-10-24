// Demand 3.2: /common/locations/cities. Never reuse another provider's IDs.
export function demandLanguage(value = 'en-gb') {
  const language = String(value).trim().toLowerCase();
  return /^[a-z]{2}(-[a-z]{2})?$/.test(language) ? language : null;
}
export function translated(value, language = 'en-gb') {
  if (typeof value === 'string') return value.slice(0, 16000);
  if (!value || typeof value !== 'object' || Array.isArray(value)) return '';
  return translated(value[language] ?? value['en-gb'] ?? value['en-us'] ?? Object.values(value)[0], language);
}
export function resolveBookingComLocation(criteria = {}) {
  if (!criteria || typeof criteria !== 'object' || Array.isArray(criteria)) return null;
  const location = criteria.location;
  if (location !== undefined) {
    if (!location || typeof location !== 'object' || Array.isArray(location)) return null;
    if (location.provider !== 'booking-demand' || !['city', 'region', 'district', 'landmark'].includes(location.kind)) return null;
    const id = Number(location.provider_id);
    return Number.isSafeInteger(id) && id !== 0 ? { [location.kind]: id } : null;
  }
  const lat = criteria.latitude ?? criteria.lat, lng = criteria.longitude ?? criteria.lng;
  if (lat != null || lng != null) {
    if ([lat,lng,criteria.radiusKm ?? 5].some(value => !['string','number'].includes(typeof value) || String(value).trim() === '')) return null;
    const latitude = Number(lat), longitude = Number(lng), radius = Number(criteria.radiusKm ?? 5);
    if (![latitude, longitude, radius].every(Number.isFinite) || Math.abs(latitude) > 90 || Math.abs(longitude) > 180 || radius <= 0 || radius > 100) return null;
    return { coordinates: { latitude, longitude, radius } };
  }
  const country = String(criteria.countryCode ?? '').toLowerCase();
  if (!/^[a-z]{2}$/.test(country) || criteria.city || criteria.destination || criteria.searchText) return null;
  return { country };
}
export async function lookupBookingComCity(criteria, request) {
  const country = String(criteria.countryCode ?? '').toLowerCase(), language = demandLanguage(criteria.language);
  const name = String(criteria.city ?? criteria.destination ?? '').trim().normalize('NFC').toLocaleLowerCase();
  if (!/^[a-z]{2}$/.test(country) || !name || !language) return { ok: false, reason: 'booking_demand_location_required' };
  let page;
  const matches = [];
  for (let i = 0; i < 3; i++) {
    const response = await request('/common/locations/cities', { country, languages: [language], rows: 100, ...(page ? { page } : {}) });
    if (!response.ok) return response;
    for (const city of response.data) {
      const id = Number(city?.id);
      if (translated(city?.name, language).trim().normalize('NFC').toLocaleLowerCase() === name && Number.isSafeInteger(id) && id !== 0) {
        matches.push({ id, name: translated(city.name, language) });
      }
    }
    page = response.metadata?.next_page;
    if (!page) break;
  }
  if (page) return { ok: false, reason: 'booking_demand_location_lookup_incomplete' };
  if (matches.length !== 1) return { ok: false, reason: matches.length ? 'booking_demand_location_ambiguous' : 'booking_demand_location_not_found' };
  return { ok: true, location: { city: matches[0].id }, city_name: matches[0].name };
}
