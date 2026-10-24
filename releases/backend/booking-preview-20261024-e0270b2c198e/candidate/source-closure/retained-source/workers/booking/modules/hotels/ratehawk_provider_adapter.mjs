import {
  handlePublicRatehawkCatalog,
  handlePublicRatehawkSearch,
  handlePublicRatehawkHotelpage,
} from "../ratehawk_hotels_facade.mjs";
import {
  HotelProvider, HotelSearchResult, HotelPropertyDetails, HotelAvailabilityResult,
  hotelPropertyIdentity, hotelUnavailable,
} from "./hotel_provider_contract.mjs";

const facade = Object.freeze({
  catalog: handlePublicRatehawkCatalog,
  search: handlePublicRatehawkSearch,
  hotelpage: handlePublicRatehawkHotelpage,
});

/** Additional envelope only. legacy_payload is the facade response, unmodified. */
class RatehawkProviderAdapter extends HotelProvider {
  #env;
  #request;
  constructor({ env = {}, request = null } = {}) {
    super(); this.#env = env; this.#request = request;
  }
  capabilities() {
    return { provider: "ratehawk", provider_id: null, search: true, details: true,
      availability: true, redirect: false, legacy_passthrough: true };
  }
  async search(criteria = {}) {
    const payload = criteria.source === "ratehawk-catalog"
      ? await facade.catalog({ env: this.#env, query: criteria })
      : await facade.search({ env: this.#env, request: this.#request, query: criteria });
    const blocked = payload.ratehawk?.invocation_allowed === false;
    const result = new HotelSearchResult({ provider: "ratehawk", stays: payload.stays ?? [],
      status: payload.ok === false || payload.reason || blocked ? "unavailable" : "ok",
      reason: payload.reason ?? (blocked ? "ratehawk_invocation_blocked" : null) });
    result.legacy_payload = payload;
    return result;
  }
  async #hotelpage(operation, reference, stayCriteria = {}) {
    const identity = hotelPropertyIdentity(reference, "ratehawk");
    // The existing signed facade body is opaque; no new RateHawk field mapping.
    const body = stayCriteria.facade_body ?? reference?.facade_body;
    if (!identity || !body || typeof body !== "object" || Array.isArray(body) ||
        String(body.hid ?? body.stay?.provider_id ?? body.stay?.hid ?? "") !== identity.provider_id) {
      return hotelUnavailable(operation, "ratehawk", "ratehawk_facade_context_required", reference, "invalid");
    }
    const payload = await facade.hotelpage({ env: this.#env, request: this.#request, body });
    const args = { provider: "ratehawk", provider_id: identity.provider_id,
      status: payload.ok === false || payload.reason ? "unavailable" : "ok", reason: payload.reason ?? null };
    const result = operation === "details" ? new HotelPropertyDetails(args) : new HotelAvailabilityResult(args);
    result.legacy_payload = payload;
    return result;
  }
  async details(reference, _language) { return this.#hotelpage("details", reference); }
  async availability(reference, criteria = {}) { return this.#hotelpage("availability", reference, criteria); }
  async redirect(reference, _criteria) {
    // The facade has no redirect operation. Existing CTA/Stay22 stays unchanged.
    return hotelUnavailable("redirect", "ratehawk", "ratehawk_redirect_not_in_facade", reference, "unsupported");
  }
}

export function createRatehawkProviderAdapter(options = {}) { return new RatehawkProviderAdapter(options); }
