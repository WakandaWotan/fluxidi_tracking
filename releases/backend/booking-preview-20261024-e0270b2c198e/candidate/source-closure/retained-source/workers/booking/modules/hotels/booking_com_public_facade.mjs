import { resolveHotelProvider } from './hotel_provider_registry.mjs';
import { bookingComServerGate } from '../../../booking-com-hotels/modules/booking_com_provider.mjs';
const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: {
  'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'Access-Control-Allow-Origin': '*',
} });
const error = (reason, status = 503) => json({ provider: 'booking-demand', provider_id: null, ok: false, status: 'unavailable', reason },status);
function criteriaFromQuery(params) {
  const read = (...keys) => keys.map(k => params.get(k)).find(value => value !== null);
  const object = key => {
    const raw = params.get(key);
    if (raw == null) return undefined;
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) throw new Error('invalid_query_object');
    return parsed;
  };
  return { city: read('city'), destination: read('destination'), countryCode: read('country_code','countryCode'),
    lat: read('lat','latitude'), lng: read('lng','longitude'), radiusKm: read('radius_km') ?? undefined,
    checkin: read('checkin'), checkout: read('checkout'), adults: read('adults'), rooms: read('rooms') ?? undefined,
    childAges: read('child_ages') ?? undefined, language: read('language') ?? 'en-gb', currency: read('currency') ?? 'EUR',
    bookerCountry: read('booker_country'), platform: read('platform'), limit: read('limit','rows') ?? undefined, cursor: read('cursor','page') ?? undefined,
    location: object('location'), guests: object('guests'), booker: object('booker') };
}
function brokerUrls(result, origin) {
  // Only our worker's encrypted-ticket path can become a client redirect URL.
  const absolute = value => typeof value === 'string' && /^\/public\/hotels\/redirect\/open\?token=[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+(?:&mode=app)?$/.test(value)
    ? origin + value : null;
  if (result.url) result.url = absolute(result.url);
  if (result.deep_link_url) result.deep_link_url = absolute(result.deep_link_url);
  if (result.external_availability_url) result.external_availability_url = absolute(result.external_availability_url);
  if (Array.isArray(result.stays)) result.stays.forEach(stay => { if (stay.external_availability_url) stay.external_availability_url = absolute(stay.external_availability_url); });
  return result;
}
export async function handleBookingComPublicHotels(request, env = {}) {
  const url = new URL(request.url), route = url.pathname;
  const operation = route === '/public/hotels/search' ? 'search' : route.slice('/public/hotels/'.length);
  if (!['search','details','availability','redirect','redirect/open','locations'].includes(operation)) return error('route_not_found',404);
  if (operation === 'search' || operation === 'redirect/open') {
    if (request.method !== 'GET') return error('method_not_allowed',405);
  } else if (request.method !== 'POST') return error('method_not_allowed',405);
  if (url.protocol !== 'https:' || url.username || url.password) return error('booking_demand_https_required',400);
  const gate = bookingComServerGate(env);
  if (gate.status !== 'ok') return json({ provider: 'booking-demand', provider_id: null, ok: false, ...gate },503);
  if (!env.BOOKING_COM_HOTELS?.fetch) return error('booking_demand_service_binding_missing');
  if (operation === 'redirect/open') {
    try {
      const token = url.searchParams.get('token') ?? '';
      if (token.length > 16000) return error('booking_demand_invalid_redirect_ticket',400);
      const target = new URL('https://booking-com-hotels.internal/internal/redirect/open');
      target.searchParams.set('token',token);
      if (url.searchParams.get('mode') === 'app') target.searchParams.set('mode','app');
      const response = await env.BOOKING_COM_HOTELS.fetch(new Request(target,{ headers: { 'x-fluxidi-internal-proxy': 'booking_worker_v1' }, redirect: 'manual' }));
      if (response.status !== 302) return error('booking_demand_invalid_redirect_ticket',400);
      // Destination validated/decrypted exclusively inside the credential worker.
      return response;
    } catch { return error('booking_demand_service_unavailable'); }
  }
  let input;
  if (operation === 'search') {
    try { input = { source: url.searchParams.get('source'), criteria: criteriaFromQuery(url.searchParams) }; }
    catch { return error('booking_demand_invalid_request',400); }
  }
  else {
    try {
      const raw = await request.text();
      if (raw.length > 30000) throw new Error('body_too_large');
      input = JSON.parse(raw);
      if (!input || typeof input !== 'object' || Array.isArray(input)) throw new Error('invalid_body');
    } catch { return error('booking_demand_invalid_request',400); }
  }
  if ((input.source ?? input.provider) !== 'booking-demand') return error('unknown_hotel_provider',400);
  // An explicit sandbox route is authorised by the SERVER enable gate above.
  // The default registry/provider and every existing RateHawk route stay intact.
  const selected = resolveHotelProvider({ env: { ...env, HOTEL_DEFAULT_PROVIDER: 'booking-demand' }, requestedProvider: 'booking-demand' });
  if (!selected.ok) return error(selected.reason);
  let result;
  if (operation === 'locations') {
    try {
      const response = await env.BOOKING_COM_HOTELS.fetch(new Request('https://booking-com-hotels.internal/internal/locations',{
        method: 'POST', headers: { 'Content-Type': 'application/json', 'x-fluxidi-internal-proxy': 'booking_worker_v1' }, body: JSON.stringify({ criteria: input.criteria ?? {} }),
      }));
      result = await response.json();
    } catch { return error('booking_demand_service_unavailable'); }
  } else if (operation === 'search') result = await selected.adapter.search(input.criteria);
  else if (operation === 'details') result = await selected.adapter.details(input.property_reference,input.language);
  else result = await selected.adapter[operation](input.property_reference,input.criteria ?? {});
  const body = brokerUrls(result,url.origin);
  const status = body.ok ? 200 : body.status === 'invalid' ? 400 : body.reason === 'booking_demand_rate_limited' ? 429 : body.reason === 'booking_demand_not_found' ? 404 : 503;
  return json(body,status);
}
