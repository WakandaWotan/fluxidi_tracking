import { HotelProvider, HotelSearchResult, HotelPropertyDetails, HotelAvailabilityResult, HotelRedirectResult, hotelPropertyIdentity, hotelUnavailable } from "../../booking/modules/hotels/hotel_provider_contract.mjs";
import { demandPropertyId, demandStayCriteria } from './booking_com_criteria.mjs';
import { demandLanguage, resolveBookingComLocation, lookupBookingComCity } from './booking_com_locations.mjs';
import { mapDemandProperty, mapDemandAvailability, mapDemandSearchStay } from './booking_com_mapping.mjs';
import { validateDemandRedirect, issueDemandRedirectTicket, openDemandRedirectTicket } from './booking_com_redirect.mjs';

export const BOOKING_DEMAND_SANDBOX_BASE = 'https://demandapi-sandbox.booking.com/3.2';
const flag = value => value === '1' || value === true;
export function bookingComServerGate(env = {}) {
  if (!flag(env.BOOKING_COM_DEMAND_ENABLED)) return { status: 'disabled', reason: 'booking_demand_disabled' };
  const environment = env.BOOKING_COM_DEMAND_ENVIRONMENT ?? 'sandbox';
  if (!['sandbox','production'].includes(environment)) return { status: 'unavailable', reason: 'booking_demand_invalid_environment' };
  if (environment === 'production') return flag(env.BOOKING_COM_DEMAND_PRODUCTION_ENABLED)
    ? { status: 'unavailable', reason: 'booking_demand_production_not_implemented' }
    : { status: 'disabled', reason: 'booking_demand_production_disabled' };
  if ((env.BOOKING_COM_DEMAND_API_VERSION ?? '3.2') !== '3.2') return { status: 'unavailable', reason: 'booking_demand_unsupported_api_version' };
  if (env.BOOKING_DEMAND_BASE_URL != null && env.BOOKING_DEMAND_BASE_URL !== BOOKING_DEMAND_SANDBOX_BASE) return { status: 'unavailable', reason: 'booking_demand_invalid_base_url' };
  return { status: 'ok', reason: null };
}
export function bookingComReadiness(env = {}) {
  const gate = bookingComServerGate(env);
  if (gate.status !== 'ok') return gate;
  if (typeof env.BOOKING_DEMAND_API_KEY !== 'string' || !env.BOOKING_DEMAND_API_KEY.trim() || /\s/.test(env.BOOKING_DEMAND_API_KEY) ||
      typeof env.BOOKING_DEMAND_AFFILIATE_ID !== 'string' || !/^[1-9]\d*$/.test(env.BOOKING_DEMAND_AFFILIATE_ID)) return { status: 'unavailable', reason: 'booking_demand_credentials_missing' };
  return { status: 'ok', reason: null };
}
const endpointPaths = new Set(['/accommodations/search','/accommodations/details','/accommodations/availability','/common/locations/cities']);
class BookingComProvider extends HotelProvider {
  #env; #fetch; #now; #timeout;
  constructor(env, { fetchImpl = (...args) => fetch(...args), now = () => Date.now(), timeoutMs = 10000 } = {}) {
    super(); this.#env = env; this.#fetch = fetchImpl; this.#now = now; this.#timeout = Math.min(10000, Math.max(1, timeoutMs));
  }
  capabilities() {
    const state = bookingComReadiness(this.#env), enabled = state.status === 'ok';
    return { provider: 'booking-demand', provider_id: null, ...state, search: enabled, details: enabled, availability: enabled, redirect: enabled, sandbox: true };
  }
  #blocked(operation, reference) {
    const state = bookingComReadiness(this.#env);
    return state.status === 'ok' ? null : hotelUnavailable(operation, 'booking-demand', state.reason, reference, state.status);
  }
  #safe(result) {
    const scrub = value => {
      if (typeof value === 'string') {
        for (const secret of [this.#env.BOOKING_DEMAND_API_KEY, this.#env.BOOKING_DEMAND_AFFILIATE_ID]) {
          if (typeof secret === 'string' && secret) value = value.replaceAll(secret, '[redacted]');
        }
        return value;
      }
      if (Array.isArray(value)) return value.map(scrub);
      if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([k,v]) => [k,scrub(v)]));
      return value;
    };
    return scrub(result);
  }
  async #request(path, body) {
    const state = bookingComReadiness(this.#env);
    if (state.status !== 'ok') return { ok: false, ...state };
    if (!endpointPaths.has(path)) return { ok: false, reason: 'booking_demand_endpoint_not_allowed' };
    const controller = new AbortController();
    let timer;
    try {
      return await Promise.race([
        (async () => {
          const response = await this.#fetch(BOOKING_DEMAND_SANDBOX_BASE + path, {
            method: 'POST', redirect: 'error', signal: controller.signal,
            headers: { Authorization: 'Bearer ' + this.#env.BOOKING_DEMAND_API_KEY,
              'X-Affiliate-Id': this.#env.BOOKING_DEMAND_AFFILIATE_ID, 'Content-Type': 'application/json', Accept: 'application/json' },
            body: JSON.stringify(body),
          });
          if (!response.ok) {
            const reasons = { 400: 'invalid_request', 401: 'unauthorized', 403: 'forbidden', 404: 'not_found', 429: 'rate_limited' };
            const reason = 'booking_demand_' + (reasons[response.status] ?? (response.status >= 500 ? 'upstream_unavailable' : 'http_error'));
            const rawRetry = response.headers.get('retry-after');
            const retry = /^\d{1,5}$/.test(rawRetry ?? '') ? Math.min(3600, Number(rawRetry)) : null;
            return { ok: false, reason, upstream_status: response.status, retry_after_seconds: retry };
          }
          // Limit the decoded response while streaming, before JSON parsing.
          let raw = '';
          if (response.body?.getReader) {
            const reader = response.body.getReader(), decoder = new TextDecoder();
            let bytes = 0;
            const abort = () => { void reader.cancel().catch(() => {}); };
            controller.signal.addEventListener('abort',abort,{ once: true });
            try { for (;;) {
              const { done, value } = await reader.read();
              if (done) break;
              bytes += value.byteLength;
              if (bytes > 2000000) { await reader.cancel(); return { ok: false, reason: 'booking_demand_response_too_large' }; }
              raw += decoder.decode(value, { stream: true });
            } } finally { controller.signal.removeEventListener('abort',abort); }
            raw += decoder.decode();
          } else raw = await response.text();
          if (controller.signal.aborted) return { ok: false, reason: 'booking_demand_timeout' };
          if (new TextEncoder().encode(raw).byteLength > 2000000) return { ok: false, reason: 'booking_demand_response_too_large' };
          if (!raw.trim()) return { ok: false, reason: 'booking_demand_empty_response' };
          let parsed;
          try { parsed = JSON.parse(raw); } catch { return { ok: false, reason: 'booking_demand_malformed_json' }; }
          if (!parsed || !Array.isArray(parsed.data) || parsed.data.some(row => !row || typeof row !== 'object' || Array.isArray(row))) return { ok: false, reason: 'booking_demand_invalid_response' };
          return { ok: true, data: parsed.data, metadata: typeof parsed.metadata === 'object' ? parsed.metadata : null };
        })(),
        new Promise(resolve => { timer = setTimeout(() => { controller.abort(); resolve({ ok: false, reason: 'booking_demand_timeout' }); }, this.#timeout); }),
      ]);
    } catch { return { ok: false, reason: controller.signal.aborted ? 'booking_demand_timeout' : 'booking_demand_network_error' }; }
    finally { clearTimeout(timer); }
  }
  #error(operation, error, reference) {
    const result = hotelUnavailable(operation, 'booking-demand', error.reason ?? 'booking_demand_unavailable', reference, error.status === 'invalid' ? 'invalid' : 'unavailable');
    if (error.upstream_status) result.upstream_status = error.upstream_status;
    if (error.retry_after_seconds != null) result.retry_after_seconds = error.retry_after_seconds;
    return result;
  }
  async search(criteria = {}) {
    const blocked = this.#blocked('search'); if (blocked) return blocked;
    const context = demandStayCriteria(criteria, this.#now());
    if (!context) return hotelUnavailable('search','booking-demand','booking_demand_invalid_stay_criteria',null,'invalid');
    const rows = Number(criteria.limit ?? criteria.rows ?? 20), page = criteria.cursor ?? criteria.page;
    if (!Number.isInteger(rows) || rows < 10 || rows > 100 || rows % 10 !== 0 || (page != null && (typeof page !== 'string' || page.length > 8192))) return hotelUnavailable('search','booking-demand','booking_demand_invalid_pagination',null,'invalid');
    let location = resolveBookingComLocation(criteria), cityName = '';
    if (!location && criteria.location === undefined && criteria.lat == null && criteria.latitude == null && (criteria.city || criteria.destination)) {
      const found = await lookupBookingComCity(criteria, (p,b) => this.#request(p,b));
      if (!found.ok) return this.#error('search',found);
      location = found.location; cityName = found.city_name;
    }
    if (!location) return hotelUnavailable('search','booking-demand','booking_demand_location_required',null,'invalid');
    const { language, ...body } = context; // Search/availability have no language field in 3.2.
    const response = await this.#request('/accommodations/search', { ...body, ...location, rows, extras: ['extra_charges','products'], ...(page ? { page } : {}) });
    if (!response.ok) return this.#error('search',response);
    const ids = response.data.map(row => demandPropertyId(row.id)).filter(Boolean);
    const result = new HotelSearchResult({ provider: 'booking-demand', status: 'ok', cursor: typeof response.metadata?.next_page === 'string' ? response.metadata.next_page : null });
    result.retrieved_at = new Date(this.#now()).toISOString(); result.sandbox = true; result.source = 'booking-demand';
    if (!ids.length) return this.#safe(result);
    const details = await this.#request('/accommodations/details', { accommodations: [...new Set(ids)].slice(0, 100), languages: [language], extras: ['description','facilities','photos','policies'] });
    if (!details.ok) return this.#error('search',details); // No provider fallback or incomplete guessed cards.
    const byId = new Map(details.data.map(row => [String(row.id),row]));
    result.stays = (await Promise.all(response.data.map(async row => {
      const stay = mapDemandSearchStay(byId.get(String(row.id)),row,context,{ language, cityName, retrievedAt: result.retrieved_at });
      if (!stay) return null;
      const redirect = await this.#redirectResult(row,stay,context);
      stay.external_availability_url = redirect.ok ? redirect.url : null;
      return stay;
    }))).filter(Boolean);
    return this.#safe(result);
  }
  async details(reference, language = 'en-gb') {
    const blocked = this.#blocked('details',reference); if (blocked) return blocked;
    const identity = hotelPropertyIdentity(reference,'booking-demand'), lang = demandLanguage(language), id = demandPropertyId(identity?.provider_id);
    if (!identity || !id || !lang) return hotelUnavailable('details','booking-demand','booking_demand_invalid_property_reference',reference,'invalid');
    const response = await this.#request('/accommodations/details',{ accommodations: [id], languages: [lang], extras: ['description','facilities','photos','policies','rooms'] });
    if (!response.ok) return this.#error('details',response,reference);
    const row = response.data.find(row => String(row.id) === identity.provider_id);
    const property = row ? mapDemandProperty(row,{ language: lang, retrievedAt: new Date(this.#now()).toISOString() }) : null;
    if (!property) return this.#error('details',{ reason: row ? 'booking_demand_invalid_property_data' : 'booking_demand_not_found' },reference);
    return this.#safe(new HotelPropertyDetails({ ...identity, status: 'ok', property }));
  }
  async #available(reference, criteria) {
    const identity = hotelPropertyIdentity(reference,'booking-demand'), id = demandPropertyId(identity?.provider_id), context = demandStayCriteria(criteria,this.#now());
    if (!identity || !id || !context) return { ok: false, reason: 'booking_demand_invalid_stay_criteria', status: 'invalid' };
    const { language, ...body } = context;
    const response = await this.#request('/accommodations/availability',{ ...body, accommodations: [id], extras: ['extra_charges'] });
    if (!response.ok) return response;
    return { ok: true, identity, context, row: response.data.find(row => String(row.id) === identity.provider_id) ?? null };
  }
  async #redirectResult(row, identity, context) {
    const rawWeb = typeof row?.url === 'string' ? row.url : row?.url?.web;
    const rawApp = row?.deep_link_url ?? row?.url?.app;
    const web = validateDemandRedirect(rawWeb, identity.provider_id, context, this.#env.BOOKING_DEMAND_AFFILIATE_ID);
    if (!web || web.includes(this.#env.BOOKING_DEMAND_API_KEY)) return hotelUnavailable('redirect','booking-demand','booking_demand_redirect_unavailable',identity);
    const candidateApp = validateDemandRedirect(rawApp,identity.provider_id,context,this.#env.BOOKING_DEMAND_AFFILIATE_ID,{ app: true });
    const appUrl = candidateApp?.includes(this.#env.BOOKING_DEMAND_API_KEY) ? null : candidateApp;
    const ticket = await issueDemandRedirectTicket({ url: web, appUrl, id: identity.provider_id, criteria: context, env: this.#env, now: this.#now() });
    const path = '/public/hotels/redirect/open?token=' + ticket;
    return new HotelRedirectResult({ ...identity, status: 'ok', url: path, deep_link_url: appUrl ? path + '&mode=app' : null });
  }
  async availability(reference, criteria = {}) {
    const blocked = this.#blocked('availability',reference); if (blocked) return blocked;
    const response = await this.#available(reference,criteria);
    if (!response.ok) return this.#error('availability',response,reference);
    const time = new Date(this.#now()).toISOString();
    const mapped = response.row ? mapDemandAvailability(response.row,response.context,time) : { available: false, currency: response.context.currency, total_price: null, base_price: null, charges: [], offers: [], retrieved_at: time };
    const result = Object.assign(new HotelAvailabilityResult({ ...response.identity, status: 'ok', offers: mapped.offers, retrieved_at: time }), mapped);
    if (mapped.available) {
      const redirect = await this.#redirectResult(response.row,response.identity,response.context);
      result.external_availability_url = redirect.ok ? redirect.url : null;
    }
    result.sandbox = true;
    return this.#safe(result);
  }
  async redirect(reference, criteria = {}) {
    const blocked = this.#blocked('redirect',reference); if (blocked) return blocked;
    const response = await this.#available(reference,criteria);
    if (!response.ok) return this.#error('redirect',response,reference);
    if (!response.row || !mapDemandAvailability(response.row,response.context,new Date(this.#now()).toISOString())?.available) return this.#error('redirect',{ reason: 'booking_demand_not_available' },reference);
    return this.#safe(await this.#redirectResult(response.row,response.identity,response.context));
  }
  async locations(criteria = {}) {
    const state = bookingComReadiness(this.#env);
    if (state.status !== 'ok') return { provider: 'booking-demand', provider_id: null, ok: false, ...state, location: null };
    const result = await lookupBookingComCity(criteria,(p,b) => this.#request(p,b));
    return this.#safe({ provider: 'booking-demand', provider_id: null, status: result.ok ? 'ok' : 'unavailable', ...result });
  }
  async openRedirect(token, app = false) {
    if (bookingComReadiness(this.#env).status !== 'ok') return null;
    return openDemandRedirectTicket(token,this.#env,this.#now(),app);
  }
}
export function createBookingComProvider(env = {}, options = {}) { return new BookingComProvider(env,options); }
