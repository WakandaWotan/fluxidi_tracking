/** Phase 1 hotel read/redirect contract. No reservation or payment operations. */
export const HOTEL_PROVIDERS = Object.freeze(["ratehawk", "booking-demand"]);
export const HOTEL_OPERATIONS = Object.freeze([
  "capabilities", "search", "details", "availability", "redirect",
]);

export class HotelProvider {
  capabilities() { throw new Error("hotel_provider_method_not_implemented"); }
  async search(_criteria) { throw new Error("hotel_provider_method_not_implemented"); }
  async details(_propertyReference, _language) { throw new Error("hotel_provider_method_not_implemented"); }
  async availability(_propertyReference, _stayCriteria) { throw new Error("hotel_provider_method_not_implemented"); }
  async redirect(_propertyReference, _stayCriteria) { throw new Error("hotel_provider_method_not_implemented"); }
}

/** Namespaced references only; never infer a provider from a numeric ID. */
export function hotelPropertyIdentity(reference, expectedProvider) {
  if (!HOTEL_PROVIDERS.includes(expectedProvider)) return null;
  let provider;
  let id;
  if (typeof reference === "string") {
    const parts = reference.split(":");
    if (parts.length !== 2) return null;
    [provider, id] = parts;
  } else if (reference && typeof reference === "object" && !Array.isArray(reference)) {
    provider = reference.provider;
    id = reference.provider_id == null ? "" : String(reference.provider_id);
    if (reference.id != null && reference.id !== `${provider}:${id}`) return null;
  }
  if (provider !== expectedProvider || !/^[1-9]\d{0,19}$/.test(id ?? "")) return null;
  return Object.freeze({ provider, provider_id: id, id: `${provider}:${id}` });
}

class HotelResult {
  constructor({ provider, provider_id = null, status = "unavailable", reason = null } = {}) {
    if (!HOTEL_PROVIDERS.includes(provider)) throw new TypeError("unknown_hotel_provider");
    if (!["ok", "disabled", "unavailable", "invalid", "unsupported"].includes(status)) {
      throw new TypeError("invalid_hotel_result_status");
    }
    if (provider_id !== null && !/^[1-9]\d{0,19}$/.test(String(provider_id))) {
      throw new TypeError("invalid_hotel_provider_id");
    }
    this.provider = provider;
    this.provider_id = provider_id === null ? null : String(provider_id);
    this.ok = status === "ok";
    this.status = status;
    this.reason = reason;
  }
}

/** Collection responses have provider_id=null; each stay retains its own ID. */
export class HotelSearchResult extends HotelResult {
  constructor({ stays = [], cursor = null, ...common } = {}) {
    super(common);
    this.stays = stays;
    this.cursor = cursor;
  }
}

export class HotelPropertyDetails extends HotelResult {
  constructor({ property = null, ...common } = {}) {
    super(common);
    this.property = property;
  }
}

export class HotelAvailabilityResult extends HotelResult {
  constructor({ offers = [], retrieved_at = null, ...common } = {}) {
    super(common);
    this.offers = offers;
    this.retrieved_at = retrieved_at;
  }
}

export class HotelRedirectResult extends HotelResult {
  constructor({ url = null, deep_link_url = null, ...common } = {}) {
    super(common);
    this.url = url;
    this.deep_link_url = deep_link_url;
  }
}

export function hotelUnavailable(operation, provider, reason, reference = null, status = "unavailable") {
  const identity = hotelPropertyIdentity(reference, provider);
  const args = { provider, provider_id: identity?.provider_id ?? null, reason, status };
  switch (operation) {
    case "search": return new HotelSearchResult(args);
    case "details": return new HotelPropertyDetails(args);
    case "availability": return new HotelAvailabilityResult(args);
    case "redirect": return new HotelRedirectResult(args);
    default: throw new TypeError("unknown_hotel_operation");
  }
}
