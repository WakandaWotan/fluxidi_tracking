/**
 * RateHawk content-completeness and live-price contract (P1, mocked only).
 *
 * The existing Fluxidi hotel flow must surface every customer-relevant
 * hotel, room, rate, payment, tax, cancellation and stay-policy field
 * RateHawk supplies. Unknown booking-critical fields fail closed.
 *
 * Static hotel content uses the permitted offline / incremental sync path
 * only. Live prices follow:
 *   search → hotelpage refresh → prebook revalidation →
 *   explicit acceptance of changes → booking
 *
 * This module does not call RateHawk, change Flutter UI, or book.
 */

import {
  EXISTING_HOTEL_PAGE_ACTIONS,
  normalizeRatehawkRateOffer,
} from "./ratehawk_affiliate_contract.mjs";
import { RATEHAWK_DEFAULT_SEARCH_LIMITS } from "./ratehawk_market_search_limits.mjs";

export const RATEHAWK_CUSTOMER_VISIBLE_STAGES = Object.freeze([
  "card",
  "detail",
  "room_rate",
  "confirmation",
]);

export const RATEHAWK_CONTENT_SOURCES = Object.freeze({
  STATIC: "static_content",
  LIVE_RATE: "live_rate",
});

export const RATEHAWK_LIVE_PRICE_PIPELINE = Object.freeze([
  "search",
  "hotelpage_refresh",
  "prebook_revalidation",
  "explicit_acceptance_of_changes",
  "booking",
]);

export const RATEHAWK_PREBOOK_REVALIDATE_DIMENSIONS = Object.freeze([
  "price",
  "currency",
  "taxes",
  "room",
  "meal",
  "payment",
  "cancellation",
  "deposit",
  "no_show",
]);

export const RATEHAWK_REQUIRED_CONTENT_CATEGORIES = Object.freeze([
  "pets",
  "children_age_ranges",
  "cots_extra_beds",
  "child_adult_meals",
  "accessibility",
  "amenities",
  "check_in_check_out",
  "early_late_check_in",
  "internet_parking",
  "hotel_deposits",
  "taxes_additional_fees",
  "important_hotel_information",
  "room_type_beds_occupancy",
  "meals",
  "price_currencies",
  "payment_timing_recipient",
  "cancellation",
  "no_show",
  "availability",
]);

export const RATEHAWK_DISCLOSURE_LOCALES = Object.freeze(["nl", "en", "fr", "es"]);

export const RATEHAWK_REFRESH_FAILED_PRICE_LABEL = "Beschikbaarheid controleren";

export const RATEHAWK_LIVE_RATE_FRESHNESS = Object.freeze({
  search_ttl_ms: RATEHAWK_DEFAULT_SEARCH_LIMITS.rate_cache_ttl_ms,
  hotelpage_cacheable: false,
  prebook_cacheable: false,
  book_hash_max_ms: 24 * 60 * 60 * 1000,
});

export { EXISTING_HOTEL_PAGE_ACTIONS };

const STATIC_FRESHNESS = "offline_incremental_revision";
const LIVE_FRESHNESS = "retrieved_at_plus_stage_expiry";

function field({
  id,
  provider_path,
  provider_keys,
  category,
  source,
  stages,
  booking_critical,
  freshness,
}) {
  return Object.freeze({
    id,
    provider_path,
    provider_keys: Object.freeze([...provider_keys]),
    category,
    source,
    stages: Object.freeze([...stages]),
    known: true,
    normalized: true,
    booking_critical: booking_critical === true,
    freshness,
  });
}

export const RATEHAWK_CONTENT_FIELD_REGISTRY = Object.freeze([
  field({
    id: "pets",
    provider_path: "metapolicy_struct.pets",
    provider_keys: ["pets"],
    category: "pets",
    source: RATEHAWK_CONTENT_SOURCES.STATIC,
    stages: ["detail", "confirmation"],
    booking_critical: true,
    freshness: STATIC_FRESHNESS,
  }),
  field({
    id: "children_age_ranges",
    provider_path: "metapolicy_struct.children",
    provider_keys: ["children"],
    category: "children_age_ranges",
    source: RATEHAWK_CONTENT_SOURCES.STATIC,
    stages: ["detail", "room_rate", "confirmation"],
    booking_critical: true,
    freshness: STATIC_FRESHNESS,
  }),
  field({
    id: "cots",
    provider_path: "metapolicy_struct.cot",
    provider_keys: ["cot"],
    category: "cots_extra_beds",
    source: RATEHAWK_CONTENT_SOURCES.STATIC,
    stages: ["detail", "room_rate", "confirmation"],
    booking_critical: true,
    freshness: STATIC_FRESHNESS,
  }),
  field({
    id: "extra_beds",
    provider_path: "metapolicy_struct.extra_bed",
    provider_keys: ["extra_bed"],
    category: "cots_extra_beds",
    source: RATEHAWK_CONTENT_SOURCES.STATIC,
    stages: ["detail", "room_rate", "confirmation"],
    booking_critical: true,
    freshness: STATIC_FRESHNESS,
  }),
  field({
    id: "children_meals",
    provider_path: "metapolicy_struct.children_meal",
    provider_keys: ["children_meal"],
    category: "child_adult_meals",
    source: RATEHAWK_CONTENT_SOURCES.STATIC,
    stages: ["detail", "room_rate", "confirmation"],
    booking_critical: true,
    freshness: STATIC_FRESHNESS,
  }),
  field({
    id: "adult_meals_policy",
    provider_path: "metapolicy_struct.meal",
    provider_keys: ["meal"],
    category: "child_adult_meals",
    source: RATEHAWK_CONTENT_SOURCES.STATIC,
    stages: ["detail", "confirmation"],
    booking_critical: true,
    freshness: STATIC_FRESHNESS,
  }),
  field({
    id: "accessibility_amenities",
    provider_path: "amenity_groups|serp_filters",
    provider_keys: ["amenity_groups", "serp_filters"],
    category: "accessibility",
    source: RATEHAWK_CONTENT_SOURCES.STATIC,
    stages: ["detail", "room_rate"],
    booking_critical: false,
    freshness: STATIC_FRESHNESS,
  }),
  field({
    id: "hotel_amenities",
    provider_path: "amenity_groups",
    provider_keys: ["amenity_groups"],
    category: "amenities",
    source: RATEHAWK_CONTENT_SOURCES.STATIC,
    stages: ["detail"],
    booking_critical: false,
    freshness: STATIC_FRESHNESS,
  }),
  field({
    id: "room_amenities",
    provider_path: "rates.amenities_data|room_groups",
    provider_keys: ["amenities_data", "amenities", "room_groups"],
    category: "amenities",
    source: RATEHAWK_CONTENT_SOURCES.LIVE_RATE,
    stages: ["room_rate", "detail"],
    booking_critical: false,
    freshness: LIVE_FRESHNESS,
  }),
  field({
    id: "check_in_time",
    provider_path: "check_in_time",
    provider_keys: ["check_in_time", "check_in_time_end"],
    category: "check_in_check_out",
    source: RATEHAWK_CONTENT_SOURCES.STATIC,
    stages: ["detail", "confirmation"],
    booking_critical: true,
    freshness: STATIC_FRESHNESS,
  }),
  field({
    id: "check_out_time",
    provider_path: "check_out_time",
    provider_keys: ["check_out_time"],
    category: "check_in_check_out",
    source: RATEHAWK_CONTENT_SOURCES.STATIC,
    stages: ["detail", "confirmation"],
    booking_critical: true,
    freshness: STATIC_FRESHNESS,
  }),
  field({
    id: "early_late_check_in_policy",
    provider_path: "metapolicy_struct.check_in_check_out",
    provider_keys: ["check_in_check_out"],
    category: "early_late_check_in",
    source: RATEHAWK_CONTENT_SOURCES.STATIC,
    stages: ["detail", "room_rate", "confirmation"],
    booking_critical: true,
    freshness: STATIC_FRESHNESS,
  }),
  field({
    id: "early_late_check_in_perks",
    provider_path: "payment_options.payment_types.perks",
    provider_keys: ["perks"],
    category: "early_late_check_in",
    source: RATEHAWK_CONTENT_SOURCES.LIVE_RATE,
    stages: ["room_rate", "confirmation"],
    booking_critical: true,
    freshness: LIVE_FRESHNESS,
  }),
  field({
    id: "internet",
    provider_path: "metapolicy_struct.internet",
    provider_keys: ["internet"],
    category: "internet_parking",
    source: RATEHAWK_CONTENT_SOURCES.STATIC,
    stages: ["detail"],
    booking_critical: false,
    freshness: STATIC_FRESHNESS,
  }),
  field({
    id: "parking",
    provider_path: "metapolicy_struct.parking",
    provider_keys: ["parking"],
    category: "internet_parking",
    source: RATEHAWK_CONTENT_SOURCES.STATIC,
    stages: ["detail"],
    booking_critical: false,
    freshness: STATIC_FRESHNESS,
  }),
  field({
    id: "static_hotel_deposit",
    provider_path: "metapolicy_struct.deposit",
    provider_keys: ["deposit"],
    category: "hotel_deposits",
    source: RATEHAWK_CONTENT_SOURCES.STATIC,
    stages: ["detail", "confirmation"],
    booking_critical: true,
    freshness: STATIC_FRESHNESS,
  }),
  field({
    id: "live_rate_deposit",
    provider_path: "rates.deposit",
    provider_keys: ["deposit"],
    category: "hotel_deposits",
    source: RATEHAWK_CONTENT_SOURCES.LIVE_RATE,
    stages: ["room_rate", "confirmation"],
    booking_critical: true,
    freshness: LIVE_FRESHNESS,
  }),
  field({
    id: "additional_fees",
    provider_path: "metapolicy_struct.add_fee",
    provider_keys: ["add_fee"],
    category: "taxes_additional_fees",
    source: RATEHAWK_CONTENT_SOURCES.STATIC,
    stages: ["detail", "confirmation"],
    booking_critical: true,
    freshness: STATIC_FRESHNESS,
  }),
  field({
    id: "live_taxes",
    provider_path: "payment_options.payment_types.tax_data",
    provider_keys: ["tax_data", "vat_data"],
    category: "taxes_additional_fees",
    source: RATEHAWK_CONTENT_SOURCES.LIVE_RATE,
    stages: ["card", "room_rate", "confirmation"],
    booking_critical: true,
    freshness: LIVE_FRESHNESS,
  }),
  field({
    id: "important_extra_info",
    provider_path: "metapolicy_extra_info",
    provider_keys: ["metapolicy_extra_info"],
    category: "important_hotel_information",
    source: RATEHAWK_CONTENT_SOURCES.STATIC,
    stages: ["detail", "confirmation"],
    booking_critical: true,
    freshness: STATIC_FRESHNESS,
  }),
  field({
    id: "important_policy_struct",
    provider_path: "policy_struct",
    provider_keys: ["policy_struct"],
    category: "important_hotel_information",
    source: RATEHAWK_CONTENT_SOURCES.STATIC,
    stages: ["detail", "confirmation"],
    booking_critical: true,
    freshness: STATIC_FRESHNESS,
  }),
  field({
    id: "static_room_groups",
    provider_path: "room_groups",
    provider_keys: ["room_groups"],
    category: "room_type_beds_occupancy",
    source: RATEHAWK_CONTENT_SOURCES.STATIC,
    stages: ["detail", "room_rate"],
    booking_critical: false,
    freshness: STATIC_FRESHNESS,
  }),
  field({
    id: "live_room_occupancy",
    provider_path: "rates.room_name|rg_ext|occupancy",
    provider_keys: ["room_name", "room_name_info", "room_data_trans", "rg_ext", "occupancy", "bed_type"],
    category: "room_type_beds_occupancy",
    source: RATEHAWK_CONTENT_SOURCES.LIVE_RATE,
    stages: ["room_rate", "confirmation"],
    booking_critical: true,
    freshness: LIVE_FRESHNESS,
  }),
  field({
    id: "live_meal_plan",
    provider_path: "rates.meal_data",
    provider_keys: ["meal", "meal_data"],
    category: "meals",
    source: RATEHAWK_CONTENT_SOURCES.LIVE_RATE,
    stages: ["room_rate", "confirmation"],
    booking_critical: true,
    freshness: LIVE_FRESHNESS,
  }),
  field({
    id: "live_price_currencies",
    provider_path: "payment_options.payment_types.show_amount|amount",
    provider_keys: ["payment_options", "daily_prices"],
    category: "price_currencies",
    source: RATEHAWK_CONTENT_SOURCES.LIVE_RATE,
    stages: ["card", "room_rate", "confirmation"],
    booking_critical: true,
    freshness: LIVE_FRESHNESS,
  }),
  field({
    id: "live_payment",
    provider_path: "payment_options.payment_types.type",
    provider_keys: ["payment_options"],
    category: "payment_timing_recipient",
    source: RATEHAWK_CONTENT_SOURCES.LIVE_RATE,
    stages: ["room_rate", "confirmation"],
    booking_critical: true,
    freshness: LIVE_FRESHNESS,
  }),
  field({
    id: "live_cancellation",
    provider_path: "payment_options.payment_types.cancellation_penalties",
    provider_keys: ["cancellation_penalties"],
    category: "cancellation",
    source: RATEHAWK_CONTENT_SOURCES.LIVE_RATE,
    stages: ["room_rate", "confirmation"],
    booking_critical: true,
    freshness: LIVE_FRESHNESS,
  }),
  field({
    id: "static_no_show_policy",
    provider_path: "metapolicy_struct.no_show",
    provider_keys: ["no_show"],
    category: "no_show",
    source: RATEHAWK_CONTENT_SOURCES.STATIC,
    stages: ["detail", "confirmation"],
    booking_critical: true,
    freshness: STATIC_FRESHNESS,
  }),
  field({
    id: "live_no_show",
    provider_path: "rates.no_show",
    provider_keys: ["no_show"],
    category: "no_show",
    source: RATEHAWK_CONTENT_SOURCES.LIVE_RATE,
    stages: ["room_rate", "confirmation"],
    booking_critical: true,
    freshness: LIVE_FRESHNESS,
  }),
  field({
    id: "live_availability",
    provider_path: "rates.allotment",
    provider_keys: ["allotment"],
    category: "availability",
    source: RATEHAWK_CONTENT_SOURCES.LIVE_RATE,
    stages: ["card", "room_rate", "confirmation"],
    booking_critical: true,
    freshness: LIVE_FRESHNESS,
  }),
  field({
    id: "property_closed",
    provider_path: "is_closed",
    provider_keys: ["is_closed"],
    category: "availability",
    source: RATEHAWK_CONTENT_SOURCES.STATIC,
    stages: ["card", "detail"],
    booking_critical: true,
    freshness: STATIC_FRESHNESS,
  }),
]);

export const KNOWN_STATIC_HOTEL_KEYS = Object.freeze([
  "address",
  "amenity_groups",
  "check_in_time",
  "check_in_time_end",
  "check_out_time",
  "description_struct",
  "email",
  "hotel_chain",
  "id",
  "hid",
  "images",
  "images_ext",
  "kind",
  "latitude",
  "longitude",
  "name",
  "metapolicy_struct",
  "metapolicy_extra_info",
  "phone",
  "policy_struct",
  "postal_code",
  "region",
  "room_groups",
  "star_rating",
  "serp_filters",
  "star_certificate",
  "is_closed",
  "keys_pickup",
  "distance_center",
  "giata_code",
  "facts",
  "payment_methods",
  "front_desk_time_start",
  "front_desk_time_end",
  "is_gender_specification_required",
  "deleted",
  "content_revision",
  "synced_at",
]);

export const KNOWN_METAPOLICY_KEYS = Object.freeze([
  "add_fee",
  "check_in_check_out",
  "children",
  "children_meal",
  "cot",
  "deposit",
  "extra_bed",
  "internet",
  "meal",
  "no_show",
  "parking",
  "pets",
  "shuttle",
  "visa",
]);

export const KNOWN_LIVE_RATE_KEYS = Object.freeze([
  "book_hash",
  "match_hash",
  "search_hash",
  "room_name",
  "room_name_info",
  "room_description",
  "room_data_trans",
  "rg_ext",
  "occupancy",
  "bed_type",
  "meal",
  "meal_data",
  "daily_prices",
  "payment_options",
  "cancellation_penalties",
  "allotment",
  "amenities",
  "amenities_data",
  "serp_filters",
  "sell_price_limits",
  "any_residency",
  "is_package",
  "legal_info",
  "deposit",
  "no_show",
  "perks",
  "retrieved_at",
]);

const BOOKING_CRITICAL_HINTS = Object.freeze([
  "payment",
  "amount",
  "currency",
  "tax",
  "vat",
  "fee",
  "cancel",
  "penalty",
  "no_show",
  "deposit",
  "occupancy",
  "meal",
  "book_hash",
  "credit_card",
  "cvc",
  "pet",
  "child",
  "cot",
  "extra_bed",
  "check_in",
  "check_out",
  "accessib",
  "policy",
  "allotment",
  "perk",
]);

const L = (nl, en, fr, es) => Object.freeze({ nl, en, fr, es });

export const RATEHAWK_DISCLOSURE_LABELS = Object.freeze({
  pets: L("Huisdieren", "Pets", "Animaux", "Mascotas"),
  children_age_ranges: L(
    "Kinderen en leeftijden",
    "Children and age ranges",
    "Enfants et tranches d’âge",
    "Niños y franjas de edad",
  ),
  cots_extra_beds: L(
    "Babybedden en extra bedden",
    "Cots and extra beds",
    "Lits bébé et lits supplémentaires",
    "Cunas y camas extra",
  ),
  child_adult_meals: L(
    "Maaltijden kind/volwassene",
    "Child and adult meals",
    "Repas enfant/adulte",
    "Comidas infantil/adulto",
  ),
  accessibility: L("Toegankelijkheid", "Accessibility", "Accessibilité", "Accesibilidad"),
  amenities: L("Voorzieningen", "Amenities", "Équipements", "Servicios"),
  check_in_check_out: L(
    "In- en uitchecken",
    "Check-in and check-out",
    "Arrivée et départ",
    "Entrada y salida",
  ),
  early_late_check_in: L(
    "Vroeg/laat inchecken",
    "Early or late check-in",
    "Arrivée anticipée/tardive",
    "Entrada temprana/tardía",
  ),
  internet_parking: L(
    "Internet en parkeren",
    "Internet and parking",
    "Internet et parking",
    "Internet y aparcamiento",
  ),
  hotel_deposits: L("Hotelwaarborg", "Hotel deposit", "Caution hôtel", "Depósito del hotel"),
  taxes_additional_fees: L(
    "Belastingen en extra kosten",
    "Taxes and additional fees",
    "Taxes et frais supplémentaires",
    "Impuestos y cargos adicionales",
  ),
  important_hotel_information: L(
    "Belangrijke hotelinformatie",
    "Important hotel information",
    "Informations importantes",
    "Información importante del hotel",
  ),
  room_type_beds_occupancy: L(
    "Kamertype, bedden en bezetting",
    "Room type, beds and occupancy",
    "Type de chambre, lits et occupation",
    "Tipo de habitación, camas y ocupación",
  ),
  meals: L("Maaltijden", "Meals", "Repas", "Comidas"),
  price_currencies: L("Prijs en valuta", "Price and currencies", "Prix et devises", "Precio y divisas"),
  payment_timing_recipient: L(
    "Betaling: tijdstip en ontvanger",
    "Payment timing and recipient",
    "Paiement : moment et destinataire",
    "Pago: momento y destinatario",
  ),
  cancellation: L("Annulering", "Cancellation", "Annulation", "Cancelación"),
  no_show: L("No-show", "No-show", "No-show", "No-show"),
  availability: L("Beschikbaarheid", "Availability", "Disponibilité", "Disponibilidad"),
  check_availability: L(
    RATEHAWK_REFRESH_FAILED_PRICE_LABEL,
    "Check availability",
    "Vérifier la disponibilité",
    "Comprobar disponibilidad",
  ),
  accept_changed_terms: L(
    "Gewijzigde voorwaarden accepteren",
    "Accept changed terms",
    "Accepter les conditions modifiées",
    "Aceptar las condiciones modificadas",
  ),
});

function _lower(value) {
  return String(value ?? "").trim().toLowerCase();
}

function _text(value, max = 800) {
  const text = String(value ?? "").trim();
  if (!text) return "";
  return text.length > max ? text.slice(0, max) : text;
}

function _isCriticalKey(key) {
  const hint = _lower(key);
  return BOOKING_CRITICAL_HINTS.some((part) => hint.includes(part));
}

function _collectUnknown(obj, knownKeys) {
  const raw = obj && typeof obj === "object" && !Array.isArray(obj) ? obj : {};
  const unmapped = [];
  const critical = [];
  for (const key of Object.keys(raw)) {
    if (knownKeys.includes(key)) continue;
    unmapped.push(key);
    if (_isCriticalKey(key)) critical.push(key);
  }
  return {
    unmapped_field_names: unmapped,
    unmapped_critical_field_names: critical,
    fail_closed: critical.length > 0,
  };
}

export function registryCategories() {
  return [
    ...new Set(RATEHAWK_CONTENT_FIELD_REGISTRY.map((row) => row.category)),
  ];
}

export function assertRegistryCoversRequiredCategories() {
  const present = new Set(registryCategories());
  const missing = RATEHAWK_REQUIRED_CONTENT_CATEGORIES.filter(
    (category) => !present.has(category),
  );
  return {
    ok: missing.length === 0,
    missing_categories: missing,
  };
}

export function collectUnmappedBookingCriticalFields(
  raw,
  { source = RATEHAWK_CONTENT_SOURCES.LIVE_RATE } = {},
) {
  if (source === RATEHAWK_CONTENT_SOURCES.STATIC) {
    const top = _collectUnknown(raw, KNOWN_STATIC_HOTEL_KEYS);
    const meta = _collectUnknown(raw?.metapolicy_struct, KNOWN_METAPOLICY_KEYS);
    const critical = [
      ...top.unmapped_critical_field_names,
      ...meta.unmapped_critical_field_names.map(
        (name) => `metapolicy_struct.${name}`,
      ),
    ];
    return {
      source,
      unmapped_field_names: [
        ...top.unmapped_field_names,
        ...meta.unmapped_field_names.map((name) => `metapolicy_struct.${name}`),
      ],
      unmapped_critical_field_names: critical,
      fail_closed: critical.length > 0,
      reason: critical.length > 0 ? "unmapped_booking_critical_field" : null,
    };
  }
  const live = _collectUnknown(raw, KNOWN_LIVE_RATE_KEYS);
  return {
    source,
    ...live,
    reason: live.fail_closed ? "unmapped_booking_critical_field" : null,
  };
}

export function normalizeStaticHotelPolicies(hotel = {}) {
  const unmapped = collectUnmappedBookingCriticalFields(hotel, {
    source: RATEHAWK_CONTENT_SOURCES.STATIC,
  });
  if (unmapped.fail_closed) {
    return {
      ok: false,
      hard_stop: true,
      reason: unmapped.reason,
      unmapped_critical_field_names: unmapped.unmapped_critical_field_names,
    };
  }
  const meta = hotel?.metapolicy_struct && typeof hotel.metapolicy_struct === "object"
    ? hotel.metapolicy_struct
    : {};
  const accessibilityHints = [
    ...(Array.isArray(hotel?.serp_filters) ? hotel.serp_filters : []),
    ...(Array.isArray(hotel?.amenity_groups)
      ? hotel.amenity_groups.flatMap((group) => group?.amenities || [])
      : []),
  ].filter((name) => /access|wheelchair|disabled|mobility/i.test(String(name)));

  return {
    ok: true,
    hard_stop: false,
    content_source: "offline_incremental_sync",
    content_revision: _text(hotel.content_revision, 80) || null,
    synced_at: hotel.synced_at ?? null,
    pets: meta.pets ?? [],
    children: meta.children ?? [],
    cots: meta.cot ?? [],
    extra_beds: meta.extra_bed ?? [],
    children_meals: meta.children_meal ?? [],
    adult_meals: meta.meal ?? [],
    accessibility: accessibilityHints,
    amenities: hotel.amenity_groups ?? [],
    check_in_time: hotel.check_in_time ?? null,
    check_in_time_end: hotel.check_in_time_end ?? null,
    check_out_time: hotel.check_out_time ?? null,
    early_late_check_in: meta.check_in_check_out ?? [],
    internet: meta.internet ?? [],
    parking: meta.parking ?? [],
    hotel_deposits: meta.deposit ?? [],
    additional_fees: meta.add_fee ?? [],
    important_hotel_information: hotel.metapolicy_extra_info ?? null,
    important_policies: hotel.policy_struct ?? [],
    room_groups: hotel.room_groups ?? [],
    static_no_show: meta.no_show ?? null,
    is_closed: hotel.is_closed === true,
    discarded: false,
    unmapped_field_names: unmapped.unmapped_field_names,
  };
}

export function inspectRatehawkContentCompleteness({
  staticHotel = null,
  liveRate = null,
} = {}) {
  const staticResult = staticHotel
    ? collectUnmappedBookingCriticalFields(staticHotel, {
        source: RATEHAWK_CONTENT_SOURCES.STATIC,
      })
    : { fail_closed: false, unmapped_critical_field_names: [] };
  const liveResult = liveRate
    ? collectUnmappedBookingCriticalFields(liveRate, {
        source: RATEHAWK_CONTENT_SOURCES.LIVE_RATE,
      })
    : { fail_closed: false, unmapped_critical_field_names: [] };
  const critical = [
    ...staticResult.unmapped_critical_field_names,
    ...liveResult.unmapped_critical_field_names,
  ];
  return {
    ok: critical.length === 0,
    hard_stop: critical.length > 0,
    reason: critical.length > 0 ? "unmapped_booking_critical_field" : null,
    unmapped_critical_field_names: critical,
    blocks_affected_rate: critical.length > 0,
    silently_ignored: false,
  };
}

export function assertStaticContentSyncPath(context) {
  const mode = _lower(context);
  if (mode === "offline_sync" || mode === "incremental_sync") {
    return { ok: true, reason: null, path: mode };
  }
  if (
    mode === "live_card_render" ||
    mode === "live_search" ||
    mode === "hotelpage" ||
    mode === "prebook"
  ) {
    return {
      ok: false,
      reason: "static_content_forbidden_during_live_path",
    };
  }
  return { ok: false, reason: "content_sync_context_required" };
}

export function assertLiveRateCachePolicy(stage) {
  const value = _lower(stage);
  if (value === "hotelpage" || value === "prebook") {
    return { ok: true, cacheable: false, ttl_ms: 0, stage: value };
  }
  if (value === "search") {
    return {
      ok: true,
      cacheable: true,
      ttl_ms: RATEHAWK_LIVE_RATE_FRESHNESS.search_ttl_ms,
      namespace: "ratehawk_live_rates",
      distinct_from_static: true,
      stage: value,
    };
  }
  return { ok: false, reason: "live_stage_required" };
}

export function annotateLiveRateFreshness({
  retrieved_at = null,
  book_hash = null,
  match_hash = null,
  search_hash = null,
  stage = "search",
  now = Date.now(),
  refresh_failed = false,
} = {}) {
  if (retrieved_at == null || retrieved_at === "") {
    return {
      ok: false,
      bookable: false,
      state: "missing_retrieved_at",
      reason: "live_rate_retrieved_at_required",
      retrieved_at: null,
      expires_at: null,
      book_hash: null,
      match_hash: _text(match_hash, 256) || null,
      search_hash: _text(search_hash, 256) || null,
    };
  }
  const retrieved = Number(retrieved_at);
  if (!Number.isFinite(retrieved)) {
    return {
      ok: false,
      bookable: false,
      state: "missing_retrieved_at",
      reason: "live_rate_retrieved_at_required",
      retrieved_at: null,
      expires_at: null,
      book_hash: null,
      match_hash: null,
      search_hash: null,
    };
  }
  const bookHash = _text(book_hash, 256);
  if (!bookHash) {
    return {
      ok: false,
      bookable: false,
      state: "missing_book_hash",
      reason: "live_rate_book_hash_required",
      retrieved_at: retrieved,
      expires_at: null,
      book_hash: null,
      match_hash: _text(match_hash, 256) || null,
      search_hash: _text(search_hash, 256) || null,
    };
  }
  if (refresh_failed === true) {
    return {
      ok: false,
      bookable: false,
      state: "refresh_failed",
      reason: "live_rate_refresh_failed",
      retrieved_at: retrieved,
      expires_at: retrieved,
      book_hash: bookHash,
      match_hash: _text(match_hash, 256) || null,
      search_hash: _text(search_hash, 256) || null,
    };
  }
  const cache = assertLiveRateCachePolicy(stage);
  const ttl = cache.cacheable
    ? cache.ttl_ms
    : RATEHAWK_LIVE_RATE_FRESHNESS.book_hash_max_ms;
  const expiresAt = retrieved + ttl;
  const expired = Number(now) >= expiresAt;
  return {
    ok: !expired,
    bookable: !expired,
    state: expired ? "expired" : "fresh",
    reason: expired ? "live_rate_expired" : null,
    retrieved_at: retrieved,
    expires_at: expiresAt,
    book_hash: bookHash,
    match_hash: _text(match_hash, 256) || null,
    search_hash: _text(search_hash, 256) || null,
    stage,
    cacheable: cache.cacheable === true,
  };
}

export function resolveLiveRatePresentation({
  freshness = null,
  refresh_failed = false,
  offer = null,
} = {}) {
  const failed =
    refresh_failed === true || freshness?.state === "refresh_failed";
  const bookable = failed !== true && freshness?.bookable === true;
  if (!bookable) {
    return {
      bookable: false,
      stale_shown_as_bookable: false,
      price_label: RATEHAWK_REFRESH_FAILED_PRICE_LABEL,
      stay22_fallback_retained: true,
      existing_page_actions_preserved: EXISTING_HOTEL_PAGE_ACTIONS,
    };
  }
  return {
    bookable: true,
    stale_shown_as_bookable: false,
    price_label: offer?.customer_total_label ?? null,
    stay22_fallback_retained: true,
    existing_page_actions_preserved: EXISTING_HOTEL_PAGE_ACTIONS,
  };
}

function _moneyIdentity(money) {
  if (!money) return { amount_minor: null, currency: null };
  return {
    amount_minor: money.amount_minor ?? null,
    currency: money.currency ?? null,
  };
}

function _stable(value) {
  return JSON.stringify(value ?? null);
}

function _change(dimension, before, after) {
  if (_stable(before) === _stable(after)) return null;
  return { dimension, before, after };
}

export function evaluateRatehawkStayTermChanges(beforeOffer, afterOffer) {
  if (!beforeOffer?.ok || !afterOffer?.ok) {
    return {
      ok: false,
      hard_stop: true,
      reason: "prebook_offers_incomplete",
    };
  }
  const changes = [
    _change(
      "price",
      _moneyIdentity(beforeOffer.customer_total),
      _moneyIdentity(afterOffer.customer_total),
    ),
    _change(
      "currency",
      {
        customer: beforeOffer.customer_total?.currency ?? null,
        charge: beforeOffer.reconciliation_amount?.currency ?? null,
      },
      {
        customer: afterOffer.customer_total?.currency ?? null,
        charge: afterOffer.reconciliation_amount?.currency ?? null,
      },
    ),
    _change(
      "taxes",
      {
        included: beforeOffer.included_taxes ?? [],
        excluded: beforeOffer.excluded_taxes ?? [],
      },
      {
        included: afterOffer.included_taxes ?? [],
        excluded: afterOffer.excluded_taxes ?? [],
      },
    ),
    _change("room", beforeOffer.room_name ?? null, afterOffer.room_name ?? null),
    _change("meal", beforeOffer.meal_plan ?? null, afterOffer.meal_plan ?? null),
    _change(
      "payment",
      {
        type: beforeOffer.payment?.payment_type ?? null,
        recipient: beforeOffer.payment?.payment_recipient ?? null,
        timing: beforeOffer.payment?.payment_timing ?? null,
      },
      {
        type: afterOffer.payment?.payment_type ?? null,
        recipient: afterOffer.payment?.payment_recipient ?? null,
        timing: afterOffer.payment?.payment_timing ?? null,
      },
    ),
    _change(
      "cancellation",
      {
        refundable: beforeOffer.refundable === true,
        free_cancellation_before: beforeOffer.free_cancellation_before ?? null,
        penalties: beforeOffer.cancellation_penalties ?? [],
      },
      {
        refundable: afterOffer.refundable === true,
        free_cancellation_before: afterOffer.free_cancellation_before ?? null,
        penalties: afterOffer.cancellation_penalties ?? [],
      },
    ),
    _change(
      "deposit",
      {
        disclosed: beforeOffer.deposit?.disclosed === true,
        amount: _moneyIdentity(beforeOffer.deposit?.amount),
        refundable: beforeOffer.deposit?.refundable ?? null,
      },
      {
        disclosed: afterOffer.deposit?.disclosed === true,
        amount: _moneyIdentity(afterOffer.deposit?.amount),
        refundable: afterOffer.deposit?.refundable ?? null,
      },
    ),
    _change(
      "no_show",
      {
        disclosed: beforeOffer.no_show?.disclosed === true,
        amount: _moneyIdentity(beforeOffer.no_show?.amount),
        currency: beforeOffer.no_show?.currency ?? null,
        from_time: beforeOffer.no_show?.from_time ?? null,
      },
      {
        disclosed: afterOffer.no_show?.disclosed === true,
        amount: _moneyIdentity(afterOffer.no_show?.amount),
        currency: afterOffer.no_show?.currency ?? null,
        from_time: afterOffer.no_show?.from_time ?? null,
      },
    ),
  ].filter(Boolean);

  return {
    ok: true,
    changed: changes.length > 0,
    changes,
    dimensions: RATEHAWK_PREBOOK_REVALIDATE_DIMENSIONS,
    must_redisplay_to_customer: changes.length > 0,
    explicit_acceptance_required: changes.length > 0,
    auto_finish_forbidden: true,
  };
}

export function disclosureLabelsFor(locale = "nl") {
  const key = RATEHAWK_DISCLOSURE_LOCALES.includes(_lower(locale))
    ? _lower(locale)
    : "en";
  const out = {};
  for (const [name, labels] of Object.entries(RATEHAWK_DISCLOSURE_LABELS)) {
    out[name] = labels[key];
  }
  return out;
}

export function projectCustomerRelevantStayContent({
  staticHotel = {},
  liveRate = null,
  locale = "nl",
  retrieved_at = null,
  now = Date.now(),
  refresh_failed = false,
  stage = "search",
} = {}) {
  const completeness = inspectRatehawkContentCompleteness({
    staticHotel,
    liveRate,
  });
  if (completeness.hard_stop) {
    return {
      ok: false,
      hard_stop: true,
      reason: completeness.reason,
      unmapped_critical_field_names: completeness.unmapped_critical_field_names,
      silently_ignored: false,
    };
  }

  const policies = normalizeStaticHotelPolicies(staticHotel);
  if (policies.ok !== true) {
    return policies;
  }

  let offer = null;
  if (liveRate) {
    offer = normalizeRatehawkRateOffer(liveRate);
    if (offer.ok !== true) {
      return {
        ok: false,
        hard_stop: true,
        reason: offer.reason,
        silently_ignored: false,
      };
    }
  }

  const freshness = liveRate
    ? annotateLiveRateFreshness({
        retrieved_at,
        book_hash: liveRate.book_hash,
        match_hash: liveRate.match_hash,
        search_hash: liveRate.search_hash,
        stage,
        now,
        refresh_failed,
      })
    : null;
  const presentation = resolveLiveRatePresentation({
    freshness,
    refresh_failed,
    offer,
  });

  return {
    ok: true,
    discarded: false,
    labels: disclosureLabelsFor(locale),
    existing_page_actions_preserved: EXISTING_HOTEL_PAGE_ACTIONS,
    pipeline: RATEHAWK_LIVE_PRICE_PIPELINE,
    static_policies: policies,
    live_offer: offer,
    freshness,
    presentation,
    customer_visible: {
      pets: policies.pets,
      children_age_ranges: policies.children,
      cots: policies.cots,
      extra_beds: policies.extra_beds,
      children_meals: policies.children_meals,
      adult_meals: policies.adult_meals,
      accessibility: policies.accessibility,
      amenities: policies.amenities,
      check_in_time: policies.check_in_time,
      check_out_time: policies.check_out_time,
      early_late_check_in: policies.early_late_check_in,
      internet: policies.internet,
      parking: policies.parking,
      hotel_deposits: policies.hotel_deposits,
      taxes: offer
        ? {
            included: offer.included_taxes,
            excluded: offer.excluded_taxes,
          }
        : null,
      additional_fees: policies.additional_fees,
      important_hotel_information: policies.important_hotel_information,
      room: offer
        ? {
            name: offer.room_name,
            occupancy: offer.occupancy,
            beds: offer.bed_information,
          }
        : null,
      meals: offer?.meal_plan ?? null,
      price: offer
        ? {
            customer_total: offer.customer_total,
            reconciliation_amount: offer.reconciliation_amount,
          }
        : null,
      payment: offer?.payment ?? null,
      cancellation: offer
        ? {
            refundable: offer.refundable,
            free_cancellation_before: offer.free_cancellation_before,
            penalties: offer.cancellation_penalties,
          }
        : null,
      no_show: offer?.no_show ?? policies.static_no_show,
      availability: offer?.remaining_availability ?? null,
    },
  };
}

export function existingPageActionsPreserved() {
  return [...EXISTING_HOTEL_PAGE_ACTIONS];
}
