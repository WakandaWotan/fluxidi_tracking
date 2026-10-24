import { createRatehawkProviderAdapter } from "./ratehawk_provider_adapter.mjs";
import { createBookingComProviderAdapter } from "./booking_com_provider_adapter.mjs";
import { bookingComReadiness } from "../../../booking-com-hotels/modules/booking_com_provider.mjs";
import { HOTEL_PROVIDERS } from "./hotel_provider_contract.mjs";

export const HOTEL_PROVIDER_DEFAULTS = Object.freeze({
  HOTEL_DEFAULT_PROVIDER: "ratehawk",
  BOOKING_COM_DEMAND_ENABLED: "0",
  BOOKING_COM_DEMAND_PRODUCTION_ENABLED: "0",
  BOOKING_COM_DEMAND_ENVIRONMENT: "sandbox",
  BOOKING_COM_DEMAND_API_VERSION: "3.2",
});

/** Server env alone selects the provider. Client flags/credentials are ignored. */
export function resolveHotelProvider({ env = {}, requestedProvider = null, request = null } = {}) {
  const selected = env.HOTEL_DEFAULT_PROVIDER ?? HOTEL_PROVIDER_DEFAULTS.HOTEL_DEFAULT_PROVIDER;
  if (!HOTEL_PROVIDERS.includes(selected) ||
      (requestedProvider !== null && !HOTEL_PROVIDERS.includes(requestedProvider))) {
    return { ok: false, provider: null, provider_id: null, status: "invalid", reason: "unknown_hotel_provider", adapter: null };
  }
  const target = requestedProvider ?? selected;
  if (target === "booking-demand") {
    const readiness = bookingComReadiness(env);
    if (readiness.status === "disabled") {
      return { ok: false, provider: target, provider_id: null, ...readiness, adapter: null };
    }
  }
  if (target !== selected) {
    return { ok: false, provider: target, provider_id: null, status: "invalid", reason: "server_provider_selection_required", adapter: null };
  }
  const adapter = target === "ratehawk"
    ? createRatehawkProviderAdapter({ env, request })
    : createBookingComProviderAdapter({ env });
  // Selection does not mean the scaffold can perform a live operation.
  return { ok: true, provider: target, provider_id: null, status: "ok", reason: null, adapter };
}
