import { bookingComServerGate } from '../../../booking-com-hotels/modules/booking_com_provider.mjs';
import { HotelProvider, hotelUnavailable } from './hotel_provider_contract.mjs';

// The gateway never receives Demand credentials. Only the separate worker does.
class BookingComServiceAdapter extends HotelProvider {
  #env;
  constructor(env) { super(); this.#env = env; }
  capabilities() {
    const state = bookingComServerGate(this.#env), enabled = state.status === 'ok' && !!this.#env.BOOKING_COM_HOTELS?.fetch;
    return { provider: 'booking-demand', provider_id: null, ...state, search: enabled, details: enabled, availability: enabled, redirect: enabled };
  }
  async #call(operation, reference, criteria = {}, language = 'en-gb') {
    const state = bookingComServerGate(this.#env);
    if (state.status !== 'ok') return hotelUnavailable(operation,'booking-demand',state.reason,reference,state.status);
    if (!this.#env.BOOKING_COM_HOTELS?.fetch) return hotelUnavailable(operation,'booking-demand','booking_demand_service_binding_missing',reference);
    try {
      const response = await this.#env.BOOKING_COM_HOTELS.fetch(new Request('https://booking-com-hotels.internal/internal/' + operation, {
        method: 'POST', headers: { 'Content-Type': 'application/json', 'x-fluxidi-internal-proxy': 'booking_worker_v1' },
        body: JSON.stringify({ property_reference: reference, criteria, language }),
      }));
      const result = await response.json();
      if (!response.ok || result.provider !== 'booking-demand' || !['ok','disabled','invalid','unavailable'].includes(result.status)) return hotelUnavailable(operation,'booking-demand','booking_demand_service_unavailable',reference);
      return result;
    } catch { return hotelUnavailable(operation,'booking-demand','booking_demand_service_unavailable',reference); }
  }
  async search(criteria) { return this.#call('search',null,criteria); }
  async details(reference, language) { return this.#call('details',reference,{},language); }
  async availability(reference, criteria) { return this.#call('availability',reference,criteria); }
  async redirect(reference, criteria) { return this.#call('redirect',reference,criteria); }
}
export function createBookingComProviderAdapter({ env = {} } = {}) { return new BookingComServiceAdapter(env); }
