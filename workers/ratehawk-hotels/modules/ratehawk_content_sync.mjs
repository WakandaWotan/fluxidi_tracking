/**
 * Scoped RateHawk hotel-content synchronization foundation (P2).
 *
 * Filter values → market hotel IDs → capped hids → hotel content by IDs →
 * normalized offline projection. The all-hotels dump is forbidden.
 *
 * Runs only from scheduled / queue / admin-internal execution. Never from
 * page open, search, View stay or another customer request. This module
 * does not call RateHawk and does not download image binaries.
 */

import {
  RATEHAWK_DISCLOSURE_LOCALES,
  RATEHAWK_REQUIRED_CONTENT_CATEGORIES,
  normalizeStaticHotelPolicies,
} from "./ratehawk_content_freshness_contract.mjs";
import {
  RATEHAWK_DEFAULT_SEARCH_LIMITS,
  resolveMarketSearchConfig,
} from "./ratehawk_market_search_limits.mjs";
import {
  RATEHAWK_CONTENT_STRATEGIES,
  resolveRatehawkContentStrategy,
} from "./ratehawk_content_strategy.mjs";
import { envFlag } from "./parsing_utils.js";

export const RATEHAWK_CONTENT_DUMP_PATH = "/api/b2b/v3/hotel/info/dump/";
export const RATEHAWK_CONTENT_INCREMENTAL_DUMP_PATH =
  "/api/b2b/v3/hotel/info/incremental_dump/";
export const RATEHAWK_CONTENT_HOTEL_INFO_PATH = "/api/b2b/v3/hotel/info/";

export const RATEHAWK_CONTENT_SYNC_TRIGGERS = Object.freeze({
  SCHEDULED: "scheduled",
  QUEUE: "queue",
  ADMIN_INTERNAL: "admin_internal",
});

export const RATEHAWK_CONTENT_CUSTOMER_TRIGGERS = Object.freeze([
  "page_open",
  "hotels_page_open",
  "live_search",
  "search",
  "view_stay",
  "hotelpage",
  "card_render",
  "list_card",
  "customer_request",
  "public_hotel_search",
  "prebook",
  "booking",
]);

const LIVE_PRICE_KEYS = Object.freeze([
  "rates",
  "payment_options",
  "book_hash",
  "match_hash",
  "search_hash",
  "show_amount",
  "show_currency_code",
  "allotment",
  "rooms_available",
  "reconciliation_amount",
]);

function _text(value, max = 400) {
  const text = String(value ?? "").trim();
  if (!text) return "";
  return text.length > max ? text.slice(0, max) : text;
}

function _lower(value) {
  return _text(value, 80).toLowerCase();
}

function _int(value, fallback = 0) {
  const n = Number(value);
  if (!Number.isFinite(n)) return fallback;
  return Math.trunc(n);
}

export function isRatehawkFullDumpRequest(pathOrOperation) {
  const raw = _lower(pathOrOperation);
  const slashed = raw.replace(/_/g, "/");
  return (
    slashed.includes("hotel/info/dump") ||
    slashed.includes("incremental/dump") ||
    raw.includes("incremental_dump") ||
    raw.includes("dump_all") ||
    raw.includes("full_dump") ||
    raw.includes("all_hotels_dump") ||
    raw.includes("custom_dump") ||
    slashed.includes("hotel/info/custom")
  );
}

export function assertContentOperationAllowed(operation, path = "") {
  if (isRatehawkFullDumpRequest(operation) || isRatehawkFullDumpRequest(path)) {
    return {
      ok: false,
      allowed: false,
      reason: "full_dump_forbidden",
      path: RATEHAWK_CONTENT_DUMP_PATH,
    };
  }
  return { ok: true, allowed: true, reason: null };
}

export function shouldRunRatehawkContentSync({
  trigger,
  env = {},
} = {}) {
  const value = _lower(trigger);
  if (RATEHAWK_CONTENT_CUSTOMER_TRIGGERS.includes(value)) {
    return {
      run: false,
      reason: "content_sync_forbidden_on_customer_request",
    };
  }
  if (!envFlag(env.RATEHAWK_CONTENT_SYNC_ENABLED)) {
    return { run: false, reason: "content_sync_disabled" };
  }
  if (
    value !== RATEHAWK_CONTENT_SYNC_TRIGGERS.SCHEDULED &&
    value !== RATEHAWK_CONTENT_SYNC_TRIGGERS.QUEUE &&
    value !== RATEHAWK_CONTENT_SYNC_TRIGGERS.ADMIN_INTERNAL
  ) {
    return { run: false, reason: "content_sync_trigger_invalid" };
  }
  return { run: true, reason: null };
}

export function parseConfiguredContentMarkets(env = {}, markets = null) {
  if (Array.isArray(markets)) {
    return resolveMarketSearchConfig(env, { markets });
  }
  const raw = _text(env.RATEHAWK_CONTENT_MARKETS, 8000);
  if (!raw) return resolveMarketSearchConfig(env, { markets: [] });
  try {
    const parsed = JSON.parse(raw);
    return resolveMarketSearchConfig(env, {
      markets: Array.isArray(parsed) ? parsed : [],
    });
  } catch {
    return resolveMarketSearchConfig(env, { markets: [] });
  }
}

export function planScopedContentSync({
  env = {},
  markets = null,
  locales = RATEHAWK_DISCLOSURE_LOCALES,
  hidLists = {},
  strategy = RATEHAWK_CONTENT_STRATEGIES.SINGLE_HID_INFO,
} = {}) {
  const dump = assertContentOperationAllowed("hotel_content_by_ids");
  if (dump.ok !== true) {
    return { ok: false, jobs: [], reason: dump.reason, executed: false, provider_requested: false };
  }
  const resolved = resolveRatehawkContentStrategy(strategy);
  if (resolved.ok !== true) {
    return {
      ok: false,
      jobs: [],
      reason: resolved.reason,
      executed: false,
      provider_requested: false,
      fallback_used: false,
    };
  }
  const config = parseConfiguredContentMarkets(env, markets);
  const enabled = (config.enabled_markets || []).filter((row) => row.enabled !== false);
  if (!enabled.length) {
    return {
      ok: true,
      jobs: [],
      reason: "no_configured_markets",
      executed: false,
      provider_requested: false,
    };
  }
  const jobs = [];
  const supportedLocales = (Array.isArray(locales) ? locales : RATEHAWK_DISCLOSURE_LOCALES).filter(
    (locale) => RATEHAWK_DISCLOSURE_LOCALES.includes(locale),
  );
  for (const market of enabled) {
    const marketKey = `${market.country_code}:${market.city_key}`;
    const supplied = Array.isArray(hidLists[marketKey]) ? hidLists[marketKey] : [];
    const unique = [];
    const seen = new Set();
    for (const hid of supplied) {
      const id = _text(hid?.hid ?? hid, 16);
      if (!/^\d{1,10}$/.test(id) || seen.has(id)) continue;
      seen.add(id);
      unique.push(Number(id));
    }
    const cap = Math.min(
      unique.length,
      config.limits.absolute_maximum,
      config.limits.max_hids_per_request,
    );
    const hids = unique.slice(0, cap);
    for (const hid of hids) {
      for (const locale of supportedLocales) {
        jobs.push({
          strategy: RATEHAWK_CONTENT_STRATEGIES.SINGLE_HID_INFO,
          market_key: marketKey,
          country_code: market.country_code,
          city_key: market.city_key,
          hid,
          locale,
          hids: [hid],
          hid_limit: 1,
          truncated: unique.length > cap,
          path: RATEHAWK_CONTENT_HOTEL_INFO_PATH,
          dump_forbidden: true,
          batch: false,
        });
      }
    }
  }
  return {
    ok: true,
    jobs,
    reason: jobs.length ? null : "no_configured_hids",
    executed: false,
    provider_requested: false,
    limits: config.limits,
    strategy: RATEHAWK_CONTENT_STRATEGIES.SINGLE_HID_INFO,
  };
}

function _imageReferences(hotel) {
  const raw = [
    ...(Array.isArray(hotel?.images) ? hotel.images : []),
    ...(Array.isArray(hotel?.images_ext) ? hotel.images_ext : []),
    ...(Array.isArray(hotel?.image_refs) ? hotel.image_refs : []),
  ];
  return raw
    .map((image) => {
      if (typeof image === "string") return { ref: image, binary: false };
      const ref = _text(image?.url ?? image?.ref ?? image?.id, 400);
      if (!ref) return null;
      return {
        ref,
        category: image?.category ?? null,
        binary: false,
      };
    })
    .filter(Boolean);
}

function _stripLivePrice(hotel) {
  const out = { ...(hotel && typeof hotel === "object" ? hotel : {}) };
  for (const key of LIVE_PRICE_KEYS) delete out[key];
  return out;
}

function _unknownCriticalForReview(hotel) {
  const policies = normalizeStaticHotelPolicies(hotel);
  if (policies.ok === true) {
    return {
      unmapped_critical_field_names: [],
      unmapped_fields_for_review: {},
    };
  }
  const names = policies.unmapped_critical_field_names || [];
  const review = {};
  for (const name of names) {
    const parts = String(name).split(".");
    let cursor = hotel;
    for (const part of parts) {
      cursor = cursor?.[part];
    }
    review[name] = cursor === undefined ? null : cursor;
  }
  return {
    unmapped_critical_field_names: names,
    unmapped_fields_for_review: review,
  };
}

export function normalizeOfflineHotelProjection(
  hotel = {},
  {
    locale = "en",
    retrieved_at = Date.now(),
    revision = null,
    market_key = null,
  } = {},
) {
  const hid = _text(hotel.hid ?? hotel.id, 16);
  if (!/^\d{1,10}$/.test(hid)) {
    return { ok: false, reason: "hid_required" };
  }
  if (!RATEHAWK_DISCLOSURE_LOCALES.includes(locale)) {
    return { ok: false, reason: "locale_unsupported" };
  }
  const staticHotel = _stripLivePrice(hotel);
  const policies = normalizeStaticHotelPolicies(staticHotel);
  const review = _unknownCriticalForReview(staticHotel);
  const categories = {
    pets: policies.pets ?? staticHotel.metapolicy_struct?.pets ?? [],
    children_age_ranges: policies.children ?? staticHotel.metapolicy_struct?.children ?? [],
    cots_extra_beds: [
      ...(policies.cots ?? []),
      ...(policies.extra_beds ?? []),
    ],
    child_adult_meals: [
      ...(policies.children_meals ?? []),
      ...(policies.adult_meals ?? []),
    ],
    accessibility: policies.accessibility ?? [],
    amenities: policies.amenities ?? staticHotel.amenity_groups ?? [],
    check_in_check_out: {
      check_in_time: policies.check_in_time ?? staticHotel.check_in_time ?? null,
      check_out_time: policies.check_out_time ?? staticHotel.check_out_time ?? null,
    },
    early_late_check_in: policies.early_late_check_in ?? [],
    internet_parking: {
      internet: policies.internet ?? [],
      parking: policies.parking ?? [],
    },
    hotel_deposits: policies.hotel_deposits ?? [],
    taxes_additional_fees: policies.additional_fees ?? [],
    important_hotel_information:
      policies.important_hotel_information ?? staticHotel.metapolicy_extra_info ?? null,
    room_type_beds_occupancy: policies.room_groups ?? staticHotel.room_groups ?? [],
    meals: policies.adult_meals ?? [],
    star_category: staticHotel.star_rating ?? staticHotel.kind ?? null,
    price_currencies: { excluded: true, reason: "live_price_pipeline" },
    payment_timing_recipient: { excluded: true, reason: "live_price_pipeline" },
    cancellation: { excluded: true, reason: "live_price_pipeline" },
    no_show: policies.static_no_show ?? staticHotel.metapolicy_struct?.no_show ?? {
      excluded: true,
      reason: "live_price_pipeline",
    },
    availability: { excluded: true, reason: "live_price_pipeline" },
  };
  return {
    ok: true,
    kind: "offline_static",
    hid: Number(hid),
    locale,
    market_key,
    name: staticHotel.name ?? null,
    address: staticHotel.address ?? null,
    coordinates: (() => {
      const lat = staticHotel.lat ?? staticHotel.latitude;
      const lng = staticHotel.lng ?? staticHotel.longitude;
      return lat != null && lng != null ? { lat: Number(lat), lng: Number(lng) } : null;
    })(),
    image_refs: _imageReferences(staticHotel),
    image_binaries_downloaded: false,
    categories,
    metapolicy_extra_info: staticHotel.metapolicy_extra_info ?? null,
    policy_struct: staticHotel.policy_struct ?? [],
    metapolicy_struct: staticHotel.metapolicy_struct ?? null,
    star_rating: staticHotel.star_rating ?? null,
    provenance: {
      source: "ratehawk_content_api",
      content_revision: revision ?? staticHotel.content_revision ?? null,
      retrieved_at,
      locale,
    },
    description_struct: staticHotel.description_struct ?? [],
    description_indexed: false,
    searchable_text_excludes: Object.freeze(["description_struct"]),
    restricted_contact: {
      email_present: Boolean(_text(staticHotel.email, 200)),
      phone_present: Boolean(_text(staticHotel.phone, 80)),
      values_retained: false,
    },
    live_price_excluded: true,
    has_live_rates: false,
    unmapped_critical_field_names: review.unmapped_critical_field_names,
    unmapped_fields_for_review: review.unmapped_fields_for_review,
    state: review.unmapped_critical_field_names.length ? "review_required" : "accepted",
    public_ready: review.unmapped_critical_field_names.length === 0,
    discarded: false,
    tombstone: false,
    required_categories: RATEHAWK_REQUIRED_CONTENT_CATEGORIES,
  };
}

export function toStoredStaticHotelProjection(projection = {}) {
  if (!projection || projection.ok !== true) return projection;
  const stored = { ...projection };
  delete stored.email;
  delete stored.phone;
  if (livePriceKeysPresent(stored) || livePriceKeysPresent(stored.categories)) {
    return { ok: false, reason: "live_price_forbidden_in_static_content" };
  }
  stored.description_indexed = false;
  stored.restricted_contact = {
    email_present: projection.restricted_contact?.email_present === true,
    phone_present: projection.restricted_contact?.phone_present === true,
    values_retained: false,
  };
  return stored;
}

export function toPublicStaticHotelCard(projection = {}) {
  const stored = toStoredStaticHotelProjection(projection);
  if (!stored || stored.ok !== true) {
    return { ok: false, reason: stored?.reason || "projection_unavailable" };
  }
  return {
    ok: true,
    hid: stored.hid,
    locale: stored.locale,
    name: stored.name,
    address: stored.address,
    coordinates: stored.coordinates,
    image_refs: stored.image_refs,
    star_rating: stored.star_rating,
    description_struct: stored.description_struct ?? [],
    description_indexed: false,
    restricted_contact_excluded: true,
    live_price_excluded: true,
  };
}

export function createMemoryContentStore() {
  const index = new Map();
  const documents = new Map();
  const jobs = new Map();
  const keyOf = (hid, locale) => `${hid}:${locale}`;
  return {
    kind: "memory_foundation",
    async get(hid, locale) {
      return documents.get(keyOf(hid, locale)) || null;
    },
    async put(projection) {
      const stored = toStoredStaticHotelProjection(projection);
      if (!stored || stored.ok !== true) {
        return { written: false, reason: stored?.reason || "projection_unavailable" };
      }
      const key = keyOf(stored.hid, stored.locale);
      const existing = documents.get(key);
      if (existing && !existing.tombstone) {
        const existingRev = _int(existing.provenance?.content_revision, 0);
        const incomingRev = _int(stored.provenance?.content_revision, 0);
        const existingAt = _int(existing.provenance?.retrieved_at, 0);
        const incomingAt = _int(stored.provenance?.retrieved_at, 0);
        if (incomingRev < existingRev || incomingAt < existingAt) {
          return { written: false, reason: "older_content_rejected" };
        }
      }
      documents.set(key, stored);
      index.set(key, {
        hid: stored.hid,
        locale: stored.locale,
        market_key: stored.market_key,
        name: stored.name,
        revision: stored.provenance?.content_revision ?? null,
        retrieved_at: stored.provenance?.retrieved_at ?? null,
        tombstone: stored.tombstone === true,
        description_indexed: false,
      });
      return { written: true, reason: null };
    },
    async tombstone({ hid, locale, revision, retrieved_at }) {
      const key = keyOf(hid, locale);
      const existing = documents.get(key);
      if (existing) {
        const existingRev = _int(existing.provenance?.content_revision, 0);
        if (_int(revision, 0) < existingRev) {
          return { written: false, reason: "older_content_rejected" };
        }
      }
      const row = {
        ok: true,
        hid,
        locale,
        tombstone: true,
        discarded: true,
        provenance: {
          content_revision: revision,
          retrieved_at,
          locale,
        },
      };
      documents.set(key, row);
      index.set(key, {
        hid,
        locale,
        tombstone: true,
        revision,
        retrieved_at,
      });
      return { written: true, reason: null };
    },
    async listIndex() {
      return [...index.values()];
    },
    async saveJob(id, state) {
      jobs.set(id, state);
    },
    async getJob(id) {
      return jobs.get(id) || null;
    },
  };
}

export async function applyOfflineContentWrite(store, projection) {
  if (projection?.tombstone === true) {
    return store.tombstone(projection);
  }
  return store.put(projection);
}

export function livePriceKeysPresent(value) {
  if (!value || typeof value !== "object") return false;
  return LIVE_PRICE_KEYS.some((key) =>
    Object.prototype.hasOwnProperty.call(value, key),
  );
}

export {
  RATEHAWK_DEFAULT_SEARCH_LIMITS,
  RATEHAWK_DISCLOSURE_LOCALES,
  RATEHAWK_REQUIRED_CONTENT_CATEGORIES,
};
