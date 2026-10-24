var __defProp = Object.defineProperty;
var __getOwnPropNames = Object.getOwnPropertyNames;
var __esm = (fn, res) => function __init() {
  return fn && (res = (0, fn[__getOwnPropNames(fn)[0]])(fn = 0)), res;
};
var __export = (target2, all) => {
  for (var name in all)
    __defProp(target2, name, { get: all[name], enumerable: true });
};

// retained-source/workers/booking/modules/owned_release_fetch_v1.mjs
function ownedReleaseFetchV1(input, init) {
  const url = new URL(typeof input === "string" || input instanceof URL ? String(input) : input.url);
  const host = url.hostname.toLowerCase().replace(/\.$/, "");
  if (host === "mapbox.com" || host.endsWith(".mapbox.com") || host === "mapbox.cn" || host.endsWith(".mapbox.cn")) {
    const error = Error("mapbox_runtime_disabled");
    error.providerRequestMade = false;
    throw error;
  }
  return globalThis.fetch(input, init);
}
var init_owned_release_fetch_v1 = __esm({
  "retained-source/workers/booking/modules/owned_release_fetch_v1.mjs"() {
  }
});

// retained-source/workers/booking/modules/driver_vehicle_relation.mjs
var init_driver_vehicle_relation = __esm({
  "retained-source/workers/booking/modules/driver_vehicle_relation.mjs"() {
  }
});

// retained-source/workers/booking/modules/routing_evidence_core.mjs
var EvidenceClass;
var init_routing_evidence_core = __esm({
  "retained-source/workers/booking/modules/routing_evidence_core.mjs"() {
    EvidenceClass = Object.freeze({
      LOWER: "CERTIFIED_LOWER_BOUND",
      UPPER: "CERTIFIED_UPPER_BOUND",
      STATIC: "EXACT_STATIC_ROUTE",
      TRAFFIC: "TRAFFIC_ESTIMATE",
      ADVISORY: "ADVISORY_ONLY"
    });
  }
});

// retained-source/workers/booking/modules/routing_core_v1.mjs
var init_routing_core_v1 = __esm({
  "retained-source/workers/booking/modules/routing_core_v1.mjs"() {
    init_routing_evidence_core();
  }
});

// retained-source/workers/booking/modules/osm_speed_rules_v1.mjs
var formatter;
var init_osm_speed_rules_v1 = __esm({
  "retained-source/workers/booking/modules/osm_speed_rules_v1.mjs"() {
    formatter = new Intl.DateTimeFormat("en-GB", { timeZone: "Europe/Brussels", weekday: "short", hour: "2-digit", minute: "2-digit", hourCycle: "h23" });
  }
});

// retained-source/workers/booking/modules/osm_vehicle_access_v1.mjs
var init_osm_vehicle_access_v1 = __esm({
  "retained-source/workers/booking/modules/osm_vehicle_access_v1.mjs"() {
    init_osm_speed_rules_v1();
  }
});

// retained-source/workers/booking/modules/reliable_regional_many_to_one_v1.mjs
var init_reliable_regional_many_to_one_v1 = __esm({
  "retained-source/workers/booking/modules/reliable_regional_many_to_one_v1.mjs"() {
  }
});

// retained-source/workers/booking/modules/reliable_gps_road_match_v1.mjs
var init_reliable_gps_road_match_v1 = __esm({
  "retained-source/workers/booking/modules/reliable_gps_road_match_v1.mjs"() {
  }
});

// retained-source/workers/booking/modules/reliable_osm_point_routes_v1.mjs
var init_reliable_osm_point_routes_v1 = __esm({
  "retained-source/workers/booking/modules/reliable_osm_point_routes_v1.mjs"() {
    init_routing_evidence_core();
    init_routing_core_v1();
    init_reliable_regional_many_to_one_v1();
    init_reliable_gps_road_match_v1();
  }
});

// retained-source/workers/booking/modules/reliable_osm_corridor_v1.mjs
var init_reliable_osm_corridor_v1 = __esm({
  "retained-source/workers/booking/modules/reliable_osm_corridor_v1.mjs"() {
    init_routing_evidence_core();
    init_routing_core_v1();
    init_osm_vehicle_access_v1();
    init_reliable_osm_point_routes_v1();
  }
});

// workers/booking/cache-correction/product_estimated_eta_v1.mjs
var TRAFFIC_PUBLICATION_STATES;
var init_product_estimated_eta_v1 = __esm({
  "workers/booking/cache-correction/product_estimated_eta_v1.mjs"() {
    init_osm_speed_rules_v1();
    TRAFFIC_PUBLICATION_STATES = Object.freeze(["AVAILABLE", "UNAVAILABLE", "STALE"]);
  }
});

// workers/booking/cache-correction/quote_r2_budget_v1.mjs
var init_quote_r2_budget_v1 = __esm({
  "workers/booking/cache-correction/quote_r2_budget_v1.mjs"() {
  }
});

// retained-source/workers/booking/modules/national_road_access_v1.mjs
var finite;
var init_national_road_access_v1 = __esm({
  "retained-source/workers/booking/modules/national_road_access_v1.mjs"() {
    init_osm_speed_rules_v1();
    finite = Number.isFinite;
  }
});

// retained-source/workers/booking/modules/official_address_reference_v1.mjs
var init_official_address_reference_v1 = __esm({
  "retained-source/workers/booking/modules/official_address_reference_v1.mjs"() {
  }
});

// retained-source/workers/booking/modules/practical_frontage_v1.mjs
var init_practical_frontage_v1 = __esm({
  "retained-source/workers/booking/modules/practical_frontage_v1.mjs"() {
    init_national_road_access_v1();
    init_official_address_reference_v1();
  }
});

// retained-source/workers/booking/modules/official_address_route_point_v1.mjs
var init_official_address_route_point_v1 = __esm({
  "retained-source/workers/booking/modules/official_address_route_point_v1.mjs"() {
  }
});

// retained-source/workers/booking/modules/configured_site_access_v1.mjs
var init_configured_site_access_v1 = __esm({
  "retained-source/workers/booking/modules/configured_site_access_v1.mjs"() {
    init_practical_frontage_v1();
  }
});

// retained-source/workers/booking/modules/national_terminal_access_v1.mjs
var finite2;
var init_national_terminal_access_v1 = __esm({
  "retained-source/workers/booking/modules/national_terminal_access_v1.mjs"() {
    init_practical_frontage_v1();
    init_national_road_access_v1();
    init_official_address_route_point_v1();
    init_configured_site_access_v1();
    finite2 = Number.isFinite;
  }
});

// retained-source/workers/booking/modules/national_terminal_navigation_v1.mjs
var init_national_terminal_navigation_v1 = __esm({
  "retained-source/workers/booking/modules/national_terminal_navigation_v1.mjs"() {
  }
});

// retained-source/workers/booking/modules/hierarchical_partitioned_routes_v1.mjs
var LIMIT;
var init_hierarchical_partitioned_routes_v1 = __esm({
  "retained-source/workers/booking/modules/hierarchical_partitioned_routes_v1.mjs"() {
    init_national_road_access_v1();
    init_practical_frontage_v1();
    init_national_terminal_access_v1();
    init_official_address_route_point_v1();
    init_configured_site_access_v1();
    init_national_terminal_navigation_v1();
    LIMIT = 8 * 1024 * 1024;
  }
});

// workers/booking/cache-correction/reliable_national_points_v1.mjs
var init_reliable_national_points_v1 = __esm({
  "workers/booking/cache-correction/reliable_national_points_v1.mjs"() {
    init_quote_r2_budget_v1();
    init_hierarchical_partitioned_routes_v1();
  }
});

// workers/booking/cache-correction/reliable_national_publication_v1.mjs
var limit;
var init_reliable_national_publication_v1 = __esm({
  "workers/booking/cache-correction/reliable_national_publication_v1.mjs"() {
    init_quote_r2_budget_v1();
    limit = 4 * 1024 * 1024;
  }
});

// retained-source/workers/booking/modules/official_address_routing_v1.mjs
var init_official_address_routing_v1 = __esm({
  "retained-source/workers/booking/modules/official_address_routing_v1.mjs"() {
    init_practical_frontage_v1();
    init_national_road_access_v1();
  }
});

// retained-source/workers/booking/modules/official_address_access_resolver_v1.mjs
var finite3;
var init_official_address_access_resolver_v1 = __esm({
  "retained-source/workers/booking/modules/official_address_access_resolver_v1.mjs"() {
    init_official_address_routing_v1();
    init_practical_frontage_v1();
    init_national_road_access_v1();
    init_official_address_reference_v1();
    init_official_address_route_point_v1();
    init_official_address_reference_v1();
    finite3 = Number.isFinite;
  }
});

// retained-source/workers/booking/modules/official_address_operational_adapter_v1.mjs
var init_official_address_operational_adapter_v1 = __esm({
  "retained-source/workers/booking/modules/official_address_operational_adapter_v1.mjs"() {
    init_official_address_access_resolver_v1();
    init_official_address_routing_v1();
    init_official_address_reference_v1();
    init_national_road_access_v1();
  }
});

// retained-source/workers/booking/vendor/official-address-index/official_address_index_v1.mjs
var encoder;
var init_official_address_index_v1 = __esm({
  "retained-source/workers/booking/vendor/official-address-index/official_address_index_v1.mjs"() {
    encoder = new TextEncoder();
  }
});

// retained-source/workers/booking/vendor/official-address-index/official_address_bootstrap_v1.mjs
var init_official_address_bootstrap_v1 = __esm({
  "retained-source/workers/booking/vendor/official-address-index/official_address_bootstrap_v1.mjs"() {
    init_official_address_index_v1();
  }
});

// retained-source/workers/booking/vendor/official-address-index/official_address_index_v2.mjs
var encoder2;
var init_official_address_index_v2 = __esm({
  "retained-source/workers/booking/vendor/official-address-index/official_address_index_v2.mjs"() {
    encoder2 = new TextEncoder();
  }
});

// retained-source/workers/booking/modules/official_address_runtime_index_v2.mjs
var encoder3;
var init_official_address_runtime_index_v2 = __esm({
  "retained-source/workers/booking/modules/official_address_runtime_index_v2.mjs"() {
    init_official_address_index_v2();
    encoder3 = new TextEncoder();
  }
});

// retained-source/workers/booking/modules/official_address_runtime_bootstrap_v2.mjs
var init_official_address_runtime_bootstrap_v2 = __esm({
  "retained-source/workers/booking/modules/official_address_runtime_bootstrap_v2.mjs"() {
    init_official_address_runtime_index_v2();
    init_quote_r2_budget_v1();
  }
});

// retained-source/workers/booking/modules/official_address_index_binding_v1.mjs
var init_official_address_index_binding_v1 = __esm({
  "retained-source/workers/booking/modules/official_address_index_binding_v1.mjs"() {
    init_official_address_bootstrap_v1();
    init_official_address_runtime_bootstrap_v2();
  }
});

// retained-source/workers/booking/modules/reliable_operational_routes_v1.mjs
import { validateNationalPublicationPolicyV1, nationalPublicationPolicyCurrentV1 } from "./operational-publication-policy.mjs";
var installed, MAX_GRAPH_BYTES;
var init_reliable_operational_routes_v1 = __esm({
  "retained-source/workers/booking/modules/reliable_operational_routes_v1.mjs"() {
    init_reliable_osm_corridor_v1();
    init_reliable_osm_point_routes_v1();
    init_product_estimated_eta_v1();
    init_reliable_national_points_v1();
    init_reliable_national_publication_v1();
    init_official_address_operational_adapter_v1();
    init_official_address_index_binding_v1();
    installed = Symbol("fluxidiOperationalRouting");
    MAX_GRAPH_BYTES = 8 * 1024 * 1024;
  }
});

// retained-source/workers/booking/modules/parsing_utils.js
function safeStr(v) {
  if (v === null || v === void 0) return "";
  return String(v).trim();
}
var init_parsing_utils = __esm({
  "retained-source/workers/booking/modules/parsing_utils.js"() {
  }
});

// retained-source/workers/booking/modules/company_dispatch.mjs
var LIVE_HEARTBEAT_TTL_MS, HEARTBEAT_WRITE_THROTTLE_MS, DRIVER_PAUSE_MAX_MS, NOW_PICKUP_GRACE_MS;
var init_company_dispatch = __esm({
  "retained-source/workers/booking/modules/company_dispatch.mjs"() {
    init_parsing_utils();
    LIVE_HEARTBEAT_TTL_MS = 3 * 60 * 1e3;
    HEARTBEAT_WRITE_THROTTLE_MS = 45 * 1e3;
    DRIVER_PAUSE_MAX_MS = 60 * 60 * 1e3;
    NOW_PICKUP_GRACE_MS = 2 * 60 * 1e3;
  }
});

// retained-source/workers/booking/modules/fleet_roster_availability.mjs
var init_fleet_roster_availability = __esm({
  "retained-source/workers/booking/modules/fleet_roster_availability.mjs"() {
    init_driver_vehicle_relation();
    init_reliable_operational_routes_v1();
    init_product_estimated_eta_v1();
    init_company_dispatch();
    init_parsing_utils();
  }
});

// retained-source/workers/booking/modules/vehicle_fallback_asset.mjs
var VEHICLE_FALLBACK_ASSETS;
var init_vehicle_fallback_asset = __esm({
  "retained-source/workers/booking/modules/vehicle_fallback_asset.mjs"() {
    VEHICLE_FALLBACK_ASSETS = Object.freeze([
      "assets/vehicles/fallback/v1/fluxidi_vehicle_compact_hatchback_v1.webp",
      "assets/vehicles/fallback/v1/fluxidi_vehicle_sedan_v1.webp",
      "assets/vehicles/fallback/v1/fluxidi_vehicle_station_wagon_v1.webp",
      "assets/vehicles/fallback/v1/fluxidi_vehicle_suv_crossover_v1.webp",
      "assets/vehicles/fallback/v1/fluxidi_vehicle_mpv_minivan_v1.webp",
      "assets/vehicles/fallback/v1/fluxidi_vehicle_passenger_minibus_v1.webp",
      "assets/vehicles/fallback/v1/fluxidi_vehicle_premium_limousine_v1.webp",
      "assets/vehicles/fallback/v1/fluxidi_vehicle_wheelchair_accessible_v1.webp",
      "assets/vehicles/fallback/v1/fluxidi_vehicle_stretch_limousine_v1.webp",
      "assets/vehicles/fallback/v1/fluxidi_vehicle_hummer_stretch_v1.webp"
    ]);
  }
});

// retained-source/workers/booking/modules/public_booking_vehicles.mjs
var init_public_booking_vehicles = __esm({
  "retained-source/workers/booking/modules/public_booking_vehicles.mjs"() {
    init_vehicle_fallback_asset();
  }
});

// retained-source/workers/booking/modules/crypto_utils.js
var init_crypto_utils = __esm({
  "retained-source/workers/booking/modules/crypto_utils.js"() {
  }
});

// retained-source/workers/booking/modules/http_response.js
var init_http_response = __esm({
  "retained-source/workers/booking/modules/http_response.js"() {
  }
});

// retained-source/workers/booking/modules/driver_ops.js
var COMPANY_DRIVER_LINK_DEFAULT_TTL_SECONDS, COMPANY_DRIVER_LINK_MAX_TTL_SECONDS;
var init_driver_ops = __esm({
  "retained-source/workers/booking/modules/driver_ops.js"() {
    init_parsing_utils();
    init_crypto_utils();
    init_http_response();
    COMPANY_DRIVER_LINK_DEFAULT_TTL_SECONDS = 10 * 60;
    COMPANY_DRIVER_LINK_MAX_TTL_SECONDS = 30 * 60;
  }
});

// retained-source/workers/booking/modules/scoped_route_cache.mjs
var init_scoped_route_cache = __esm({
  "retained-source/workers/booking/modules/scoped_route_cache.mjs"() {
  }
});

// retained-source/workers/tracking/modules/customer_live_snapshot.mjs
function trackingPhaseForStatus(status) {
  const token = String(status || "").trim().toLowerCase().replace(/[\s-]+/g, "_");
  if (!token || token === "unassigned" || token === "quoted" || token === "pending") return "unassigned";
  if (token === "assigned" || token === "accepted" || token === "confirmed") return "assigned";
  if (token === "en_route" || token === "en_route_pickup" || token === "on_the_way" || token === "driving_to_pickup") {
    return "en_route_pickup";
  }
  if (token === "arrived_pickup") return "arrived_pickup";
  if (token === "started" || token === "in_progress" || token === "on_trip" || token === "picked_up" || token === "driving") {
    return "in_progress";
  }
  if (token === "stopped" || token === "stop") return "stopped";
  if (token === "completed" || token === "complete") return "completed";
  if (["cancelled", "canceled", "no_show", "rejected", "expired"].includes(token)) return "cancelled";
  return "assigned";
}
var init_customer_live_snapshot = __esm({
  "retained-source/workers/tracking/modules/customer_live_snapshot.mjs"() {
    init_vehicle_fallback_asset();
    init_scoped_route_cache();
  }
});

// retained-source/workers/booking/modules/booking_utils.js
function _normLifecycleStatus(v) {
  const raw = String(v || "").toUpperCase().trim();
  if (raw === "COMPLETED" || raw === "COMPLETE" || raw === "DONE" || raw === "CLOSED") {
    return "COMPLETED";
  }
  if (raw === "CANCELLED" || raw === "CANCELED" || raw === "DELETED" || raw === "ARCHIVED" || raw === "DECLINED" || raw === "FAILED" || raw === "EXPIRED" || raw === "NO_SHOW" || raw === "REJECTED") {
    return "CANCELLED";
  }
  if (raw === "BOOKED" || raw === "CONFIRMED" || raw === "PENDING" || raw === "ACTIVE" || raw === "OPEN") {
    return "PENDING";
  }
  return "PENDING";
}
var init_booking_utils = __esm({
  "retained-source/workers/booking/modules/booking_utils.js"() {
    init_parsing_utils();
  }
});

// retained-source/workers/booking/modules/subscription_profile_authority.mjs
var init_subscription_profile_authority = __esm({
  "retained-source/workers/booking/modules/subscription_profile_authority.mjs"() {
  }
});

// retained-source/workers/booking/modules/subscription_profile_source.mjs
var init_subscription_profile_source = __esm({
  "retained-source/workers/booking/modules/subscription_profile_source.mjs"() {
    init_subscription_profile_authority();
  }
});

// retained-source/workers/booking/modules/company_primary_email_recovery.mjs
var init_company_primary_email_recovery = __esm({
  "retained-source/workers/booking/modules/company_primary_email_recovery.mjs"() {
  }
});

// retained-source/workers/booking/modules/public_company_contact.mjs
var init_public_company_contact = __esm({
  "retained-source/workers/booking/modules/public_company_contact.mjs"() {
    init_company_primary_email_recovery();
  }
});

// retained-source/workers/booking/modules/company_account_lifecycle.mjs
var PUBLIC_VISIBILITY_VALUES, HARD_PROTECTED_COMPANY_CODES, ACCOUNT_STATES, CONFIRMED_ACCOUNT_STATES, ACCOUNT_STATE_PRIORITY, ACCOUNT_ACTIONS, ROUTE_CLASSES, IN_PROGRESS_ACTIONS, REFUSE, ALLOW, MATRIX, TRANSITIONS, PROTECTED_ACCOUNT_STATES;
var init_company_account_lifecycle = __esm({
  "retained-source/workers/booking/modules/company_account_lifecycle.mjs"() {
    init_public_company_contact();
    PUBLIC_VISIBILITY_VALUES = Object.freeze(["listed", "hidden"]);
    HARD_PROTECTED_COMPANY_CODES = Object.freeze(["FLX-00001", "FLX-00020"]);
    ACCOUNT_STATES = Object.freeze([
      "unknown",
      "active",
      "paused",
      "blocked",
      "closed",
      "archived"
    ]);
    CONFIRMED_ACCOUNT_STATES = Object.freeze([
      "active",
      "paused",
      "blocked",
      "closed",
      "archived"
    ]);
    ACCOUNT_STATE_PRIORITY = Object.freeze({
      closed: 50,
      archived: 45,
      blocked: 40,
      paused: 30,
      active: 20,
      unknown: 10
    });
    ACCOUNT_ACTIONS = Object.freeze([
      "confirm",
      "pause",
      "resume",
      "block",
      "unblock",
      "close",
      "archive"
    ]);
    ROUTE_CLASSES = Object.freeze({
      public_login: "public_login",
      company_login: "company_login",
      new_booking: "new_booking",
      new_quote: "new_quote",
      in_progress_ride: "in_progress_ride",
      fleet_sync: "fleet_sync",
      bootstrap: "bootstrap",
      company_admin_write: "company_admin_write",
      public_active_list: "public_active_list",
      public_profile: "public_profile",
      integration_auto: "integration_auto"
    });
    IN_PROGRESS_ACTIONS = Object.freeze([
      "status_existing",
      "payment_existing",
      "complete_existing",
      "cancel_existing"
    ]);
    REFUSE = "refuse";
    ALLOW = "allow";
    MATRIX = Object.freeze({
      unknown: {
        public_login: ALLOW,
        company_login: ALLOW,
        new_booking: ALLOW,
        new_quote: ALLOW,
        in_progress_ride: ALLOW,
        fleet_sync: ALLOW,
        bootstrap: ALLOW,
        company_admin_write: ALLOW,
        public_active_list: REFUSE,
        public_profile: REFUSE,
        integration_auto: ALLOW
      },
      active: {
        public_login: ALLOW,
        company_login: ALLOW,
        new_booking: ALLOW,
        new_quote: ALLOW,
        in_progress_ride: ALLOW,
        fleet_sync: ALLOW,
        bootstrap: ALLOW,
        company_admin_write: ALLOW,
        public_active_list: ALLOW,
        public_profile: ALLOW,
        integration_auto: ALLOW
      },
      paused: {
        public_login: REFUSE,
        company_login: REFUSE,
        new_booking: REFUSE,
        new_quote: REFUSE,
        in_progress_ride: ALLOW,
        fleet_sync: ALLOW,
        bootstrap: ALLOW,
        company_admin_write: ALLOW,
        public_active_list: REFUSE,
        public_profile: REFUSE,
        integration_auto: REFUSE
      },
      blocked: {
        public_login: REFUSE,
        company_login: REFUSE,
        new_booking: REFUSE,
        new_quote: REFUSE,
        in_progress_ride: ALLOW,
        fleet_sync: REFUSE,
        bootstrap: REFUSE,
        company_admin_write: REFUSE,
        public_active_list: REFUSE,
        public_profile: REFUSE,
        integration_auto: REFUSE
      },
      closed: {
        public_login: REFUSE,
        company_login: REFUSE,
        new_booking: REFUSE,
        new_quote: REFUSE,
        in_progress_ride: ALLOW,
        fleet_sync: REFUSE,
        bootstrap: REFUSE,
        company_admin_write: REFUSE,
        public_active_list: REFUSE,
        public_profile: REFUSE,
        integration_auto: REFUSE
      },
      archived: {
        public_login: REFUSE,
        company_login: REFUSE,
        new_booking: REFUSE,
        new_quote: REFUSE,
        in_progress_ride: ALLOW,
        fleet_sync: REFUSE,
        bootstrap: REFUSE,
        company_admin_write: REFUSE,
        public_active_list: REFUSE,
        public_profile: REFUSE,
        integration_auto: REFUSE
      }
    });
    TRANSITIONS = Object.freeze({
      confirm: { unknown: "active" },
      pause: { active: "paused", paused: "paused" },
      resume: { paused: "active" },
      block: { active: "blocked", paused: "blocked", unknown: "blocked", blocked: "blocked" },
      unblock: { blocked: "active" },
      close: {
        active: "closed",
        paused: "closed",
        blocked: "closed",
        unknown: "closed",
        closed: "closed"
      },
      archive: { closed: "archived", archived: "archived" }
    });
    PROTECTED_ACCOUNT_STATES = Object.freeze([
      "paused",
      "blocked",
      "closed",
      "archived"
    ]);
  }
});

// retained-source/workers/booking/modules/fleet_vehicle_capacity.mjs
var init_fleet_vehicle_capacity = __esm({
  "retained-source/workers/booking/modules/fleet_vehicle_capacity.mjs"() {
  }
});

// retained-source/workers/booking/modules/company_trial_entitlement.mjs
var init_company_trial_entitlement = __esm({
  "retained-source/workers/booking/modules/company_trial_entitlement.mjs"() {
    init_fleet_vehicle_capacity();
  }
});

// retained-source/workers/booking/modules/company_first_use_trial.mjs
var FIRST_USE_TRIAL_MS;
var init_company_first_use_trial = __esm({
  "retained-source/workers/booking/modules/company_first_use_trial.mjs"() {
    init_company_trial_entitlement();
    FIRST_USE_TRIAL_MS = 14 * 864e5;
  }
});

// retained-source/workers/booking/modules/subscription_plan_access.mjs
var MAX_TRIAL_MS;
var init_subscription_plan_access = __esm({
  "retained-source/workers/booking/modules/subscription_plan_access.mjs"() {
    MAX_TRIAL_MS = 14 * 864e5;
  }
});

// retained-source/workers/booking/modules/internal_dev_subscription_exemption.mjs
var INTERNAL_DEV_PRESENTATION, CLIENT_INTERNAL_DEV_FIELDS;
var init_internal_dev_subscription_exemption = __esm({
  "retained-source/workers/booking/modules/internal_dev_subscription_exemption.mjs"() {
    INTERNAL_DEV_PRESENTATION = Object.freeze({
      account_kind: "Intern ontwikkelaccount",
      price_label: "Gratis \u2014 geen abonnementsincasso",
      limits_label: "Onbeperkt voertuigen en chauffeurs",
      ride_payments_note: "Ritten blijven via de bestaande Mollie-koppeling betaald. Gratis Fluxidi-gebruik maakt ritten niet automatisch betaald."
    });
    CLIENT_INTERNAL_DEV_FIELDS = Object.freeze([
      "internal_dev_account",
      "internalDevAccount",
      "subscription_billing_exempt",
      "subscriptionBillingExempt",
      "unlimited_vehicles",
      "unlimitedVehicles",
      "unlimited_drivers",
      "unlimitedDrivers"
    ]);
  }
});

// retained-source/workers/booking/modules/company_subscription_facts.mjs
var COMPANY_SUBSCRIPTION_OPERATIONS;
var init_company_subscription_facts = __esm({
  "retained-source/workers/booking/modules/company_subscription_facts.mjs"() {
    init_subscription_plan_access();
    init_company_account_lifecycle();
    init_internal_dev_subscription_exemption();
    COMPANY_SUBSCRIPTION_OPERATIONS = Object.freeze([
      "receive_request",
      "view_requests",
      "view_history",
      "view_profile",
      "accept_request",
      "start_street_hail",
      "create_company_booking",
      "start_booked_trip",
      "assign_driver",
      "respond_quote",
      "edit_booking",
      "manage_fleet",
      "automatic_dispatch",
      "customer_live_tracking",
      "traffic_eta",
      "finish_existing_trip",
      "cancel_existing_trip"
    ]);
  }
});

// retained-source/workers/booking/modules/company_operation_guard.mjs
var init_company_operation_guard = __esm({
  "retained-source/workers/booking/modules/company_operation_guard.mjs"() {
    init_subscription_profile_source();
    init_company_account_lifecycle();
    init_company_trial_entitlement();
    init_company_first_use_trial();
    init_company_subscription_facts();
    init_internal_dev_subscription_exemption();
  }
});

// retained-source/workers/booking/modules/company_vehicle_duty.mjs
function dutyForRideExecution(state, actor, vehicleId) {
  if (!actor?.driver_id || !sameScope(state, actor)) return deny("driver_auth_required");
  const matches4 = state.duties.filter((row) => row.driver_id === actor.driver_id && row.vehicle_id === vehicleId && row.ended_at_ms === null);
  if (matches4.length !== 1 || matches4[0].paused_at_ms !== null) return deny("active_duty_required");
  const duty = matches4[0];
  return { ok: true, execution_identity: Object.freeze({
    tenant_id: actor.tenant_id,
    company_id: actor.company_id,
    driver_id: duty.driver_id,
    vehicle_id: duty.vehicle_id,
    duty_id: duty.duty_id
  }) };
}
var deny, sameScope;
var init_company_vehicle_duty = __esm({
  "retained-source/workers/booking/modules/company_vehicle_duty.mjs"() {
    deny = (error) => ({ ok: false, error });
    sameScope = (a, b) => a?.tenant_id === b?.tenant_id && a?.company_id === b?.company_id;
  }
});

// retained-source/workers/tracking/modules/company_vehicle_duty_storage.mjs
var VEHICLE_DUTY_STATE_KEY, VEHICLE_DUTY_PROJECTION_KEY;
var init_company_vehicle_duty_storage = __esm({
  "retained-source/workers/tracking/modules/company_vehicle_duty_storage.mjs"() {
    init_company_vehicle_duty();
    VEHICLE_DUTY_STATE_KEY = "vehicle_duty_active_v1";
    VEHICLE_DUTY_PROJECTION_KEY = "vehicle_duty_projection_v1";
  }
});

// retained-source/workers/tracking/modules/company_capacity_storage.mjs
async function digest(text3) {
  return [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes(text3)))].map((value) => value.toString(16).padStart(2, "0")).join("");
}
async function capacityArchiveKey(kind, id4) {
  if (!tables[kind] || typeof id4 !== "string" || !id4 || id4.length > 500) throw Error("capacity_archive_identity_invalid");
  return `capacity_archive_v1:${kind}:${await digest(id4)}`;
}
function validateLedger(ledger) {
  if (!validMap(ledger) || !validMap(ledger.claims) || !validMap(ledger.owners)) throw Error("capacity_storage_invalid");
  return ledger;
}
function manifestPages(root) {
  if (!Array.isArray(root.pages) || !root.pages.length || root.pages.length > 1024 || typeof root.generation !== "string" || !/^[a-f\d-]{36}$/.test(root.generation) || !Number.isSafeInteger(root.bytes) || root.bytes < 1 || root.bytes > CAPACITY_SNAPSHOT_MAX_BYTES || !/^[a-f\d]{64}$/.test(root.sha256 || "") || root.pages.some((key2, i) => key2 !== `capacity_page_v2:${root.generation}:${i}`)) throw Error("capacity_snapshot_manifest_invalid");
  return root.pages;
}
async function readCapacitySnapshot(storage) {
  const root = await storage.get(CAPACITY_STORAGE_KEY);
  if (root == null) return { claims: {}, owners: {} };
  if (root.format !== FORMAT) return validateLedger(root);
  manifestPages(root);
  const parts = [];
  for (let i = 0; i < root.pages.length; i++) {
    const key2 = `capacity_page_v2:${root.generation}:${i}`;
    const part = await storage.get(key2);
    if (typeof part !== "string" || part.length > PAGE_CHARS) throw Error("capacity_snapshot_page_missing");
    parts.push(part);
  }
  const text3 = parts.join("");
  if (bytes(text3).length !== root.bytes || await digest(text3) !== root.sha256) throw Error("capacity_snapshot_checksum_invalid");
  return validateLedger(JSON.parse(text3));
}
async function hydrateCapacityRecords(storage, ledger, identities, scope2) {
  let next = ledger;
  const pending = Object.entries(identities).flatMap(([kind, ids]) => ids.map((id4) => [kind, id4]));
  const seen = /* @__PURE__ */ new Set();
  for (let i = 0; i < pending.length; i++) {
    const [kind, id4] = pending[i], table3 = tables[kind];
    if (!table3 || typeof id4 !== "string" || !id4 || id4.length > 500 || seen.has(`${kind}:${id4}`)) continue;
    seen.add(`${kind}:${id4}`);
    let row = next[table3]?.[id4];
    if (!Object.hasOwn(next[table3] || {}, id4)) {
      const archived = await storage.get(await capacityArchiveKey(kind, id4));
      if (archived == null) continue;
      row = archived.record;
      if (archived.kind !== kind || archived.id !== id4 || !validMap(row) || row.tenant_id !== scope2.tenant_id || row.company_id !== scope2.company_id || kind === "owner" && (!Number.isSafeInteger(row.version) || row.version < 1 || row.pending || !row.released) || kind === "offer" && row.offer_id !== id4 || kind === "event" && row.event_id !== id4) {
        throw Error("capacity_archive_record_invalid");
      }
      next = { ...next, [table3]: { ...next[table3], [id4]: row } };
    }
    if (row.owner_id) pending.push(["owner", row.owner_id]);
    if (kind === "event" && row.offer_id && row.type !== "dispatch_search") pending.push(["offer", row.offer_id]);
  }
  return next;
}
var CAPACITY_STORAGE_KEY, CAPACITY_ARCHIVE_AFTER_MS, CAPACITY_SNAPSHOT_MAX_BYTES, INLINE_BYTES, PAGE_CHARS, FORMAT, encoder4, tables, validMap, bytes;
var init_company_capacity_storage = __esm({
  "retained-source/workers/tracking/modules/company_capacity_storage.mjs"() {
    CAPACITY_STORAGE_KEY = "company_capacity_ledger_v1";
    CAPACITY_ARCHIVE_AFTER_MS = 24 * 60 * 6e4;
    CAPACITY_SNAPSHOT_MAX_BYTES = 8 * 1024 * 1024;
    INLINE_BYTES = 80 * 1024;
    PAGE_CHARS = 24 * 1024;
    FORMAT = "company-capacity-pages-v2";
    encoder4 = new TextEncoder();
    tables = { owner: "owners", offer: "offers", event: "dispatch_events" };
    validMap = (value) => value && typeof value === "object" && !Array.isArray(value);
    bytes = (value) => encoder4.encode(value);
  }
});

// retained-source/workers/tracking/modules/company_vehicle_device.mjs
var init_company_vehicle_device = __esm({
  "retained-source/workers/tracking/modules/company_vehicle_device.mjs"() {
    init_company_capacity_storage();
  }
});

// retained-source/workers/tracking/modules/dispatch_device_capability.mjs
function driverDispatchDevices2(store, scope2, driverId, nowMs, deviceKey = "") {
  if (!matches2(store?.scope, scope2)) return [];
  return Object.values(store.devices || {}).filter((row) => matches2(row, scope2) && row.driver_id === driverId && (!deviceKey || row.device_key === deviceKey) && valid2(row, nowMs));
}
var matches2, valid2;
var init_dispatch_device_capability = __esm({
  "retained-source/workers/tracking/modules/dispatch_device_capability.mjs"() {
    matches2 = (row, scope2) => row?.tenant_id === scope2.tenant_id && row?.company_id === scope2.company_id;
    valid2 = (row, nowMs) => row?.protocol === 1 && Number.isFinite(row.seen_at_ms) && row.seen_at_ms <= nowMs && nowMs < row.valid_until_ms;
  }
});

// retained-source/workers/shared/ride_execution_identity_v1.mjs
function frozenRideExecutionIdentityV12(identity, scope2, driverId, vehicleId) {
  if (!identity || identity.tenant_id !== scope2?.tenant_id || identity.company_id !== scope2?.company_id || !driverId || !vehicleId || identity.driver_id !== driverId || identity.vehicle_id !== vehicleId) return null;
  const base = { tenant_id: scope2.tenant_id, company_id: scope2.company_id, driver_id: driverId, vehicle_id: vehicleId };
  if (identity.kind === "personal_driver_session") {
    if (identity.duty_id != null || typeof identity.acceptance_id !== "string" || !/^acceptance:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(identity.acceptance_id)) return null;
    return { ...base, kind: identity.kind, acceptance_id: identity.acceptance_id };
  }
  if (identity.kind != null || identity.acceptance_id != null || typeof identity.duty_id !== "string" || !identity.duty_id) return null;
  return { ...base, duty_id: identity.duty_id };
}
var init_ride_execution_identity_v1 = __esm({
  "retained-source/workers/shared/ride_execution_identity_v1.mjs"() {
  }
});

// retained-source/workers/tracking/modules/personal_driver_execution_v1.mjs
function personalDriverExecutionV12({ input, devices, duty, offer, nowMs = Date.now() }) {
  const a = input?.personal_execution_auth;
  if (a?.source !== "booking_personal_driver_session_v1" || a.tenant_id !== input.tenant_id || a.company_id !== input.company_id || a.driver_id !== input.driver_id || a.vehicle_id !== input.vehicle_id || a.device_key !== input.device_key || !Number.isFinite(a.session_expires_ms) || a.session_expires_ms <= nowMs) return null;
  const registered = driverDispatchDevices2(devices, input, input.driver_id, nowMs, input.device_key);
  if (registered.length !== 1 || registered[0].vehicle_device_id) return null;
  if (duty?.duties?.some((d) => d.ended_at_ms === null && (d.driver_id === input.driver_id || d.vehicle_id === input.vehicle_id))) return null;
  if (!offer || offer.tenant_id !== input.tenant_id || offer.company_id !== input.company_id || offer.offer_id !== input.offer_id || offer.version !== input.version || offer.human_acceptance_required !== true || !offer.claims?.some((c) => c.driver_id === input.driver_id && c.vehicle_id === input.vehicle_id)) return null;
  const previous = offer.receipts?.[input.driver_id]?.execution_identity;
  if (previous) return frozenRideExecutionIdentityV12(previous, input, input.driver_id, input.vehicle_id);
  return {
    tenant_id: input.tenant_id,
    company_id: input.company_id,
    driver_id: input.driver_id,
    vehicle_id: input.vehicle_id,
    kind: "personal_driver_session",
    acceptance_id: "acceptance:" + crypto.randomUUID()
  };
}
var init_personal_driver_execution_v1 = __esm({
  "retained-source/workers/tracking/modules/personal_driver_execution_v1.mjs"() {
    init_dispatch_device_capability();
    init_ride_execution_identity_v1();
  }
});

// retained-source/workers/tracking/modules/per_driver_state.mjs
var init_per_driver_state = __esm({
  "retained-source/workers/tracking/modules/per_driver_state.mjs"() {
  }
});

// retained-source/workers/booking/modules/active_spatial_index.mjs
var init_active_spatial_index = __esm({
  "retained-source/workers/booking/modules/active_spatial_index.mjs"() {
  }
});

// retained-source/workers/tracking/modules/customer_adaptive_eta.mjs
var init_customer_adaptive_eta = __esm({
  "retained-source/workers/tracking/modules/customer_adaptive_eta.mjs"() {
  }
});

// retained-source/workers/booking/modules/tenant_cost_metrics.mjs
var metered;
var init_tenant_cost_metrics = __esm({
  "retained-source/workers/booking/modules/tenant_cost_metrics.mjs"() {
    metered = Symbol("tenantCostMetered");
  }
});

// retained-source/workers/booking/modules/route_observability.mjs
var init_route_observability = __esm({
  "retained-source/workers/booking/modules/route_observability.mjs"() {
    init_tenant_cost_metrics();
  }
});

// retained-source/workers/booking/modules/staging_trial_budget_v1.mjs
var init_staging_trial_budget_v1 = __esm({
  "retained-source/workers/booking/modules/staging_trial_budget_v1.mjs"() {
  }
});

// retained-source/workers/booking/modules/company_dispatch_mapbox.mjs
var init_company_dispatch_mapbox = __esm({
  "retained-source/workers/booking/modules/company_dispatch_mapbox.mjs"() {
    init_owned_release_fetch_v1();
    init_route_observability();
    init_staging_trial_budget_v1();
  }
});

// retained-source/workers/tracking/modules/customer_grant_storage.mjs
var CUSTOMER_GRANT_ARCHIVE_AFTER_MS, CUSTOMER_GRANT_SNAPSHOT_MAX_BYTES, INLINE_BYTES2, PAGE_CHARS2, encoder5;
var init_customer_grant_storage = __esm({
  "retained-source/workers/tracking/modules/customer_grant_storage.mjs"() {
    init_customer_live_snapshot();
    CUSTOMER_GRANT_ARCHIVE_AFTER_MS = 24 * 60 * 6e4;
    CUSTOMER_GRANT_SNAPSHOT_MAX_BYTES = 8 * 1024 * 1024;
    INLINE_BYTES2 = 80 * 1024;
    PAGE_CHARS2 = 24 * 1024;
    encoder5 = new TextEncoder();
  }
});

// retained-source/workers/tracking/modules/capacity_resource_index.mjs
var init_capacity_resource_index = __esm({
  "retained-source/workers/tracking/modules/capacity_resource_index.mjs"() {
  }
});

// retained-source/workers/tracking/modules/company_capacity_ledger.mjs
var UNSTARTED_CAPACITY_GRACE_MS;
var init_company_capacity_ledger = __esm({
  "retained-source/workers/tracking/modules/company_capacity_ledger.mjs"() {
    init_capacity_resource_index();
    UNSTARTED_CAPACITY_GRACE_MS = 15 * 60 * 1e3;
  }
});

// retained-source/workers/tracking/modules/driver_location_owner.mjs
function boundLocationOwner(owner2, nowMs) {
  return Boolean(owner2 && /^[a-f0-9]{64}$/.test(owner2.session_hash || "") && label(owner2.activation_id) && (owner2.native_device_id == null || label(owner2.native_device_id)) && Number.isFinite(owner2.session_expires_ms) && owner2.session_expires_ms > nowMs);
}
var label;
var init_driver_location_owner = __esm({
  "retained-source/workers/tracking/modules/driver_location_owner.mjs"() {
    label = (value) => typeof value === "string" && /^[A-Za-z0-9_-]{1,128}$/.test(value);
  }
});

// retained-source/workers/tracking/modules/company_dispatch_amendment.mjs
var init_company_dispatch_amendment = __esm({
  "retained-source/workers/tracking/modules/company_dispatch_amendment.mjs"() {
    init_company_capacity_ledger();
  }
});

// retained-source/workers/tracking/modules/company_dispatch_offers.mjs
var CONFIRMED_RECHECK_HORIZON_MS;
var init_company_dispatch_offers = __esm({
  "retained-source/workers/tracking/modules/company_dispatch_offers.mjs"() {
    init_dispatch_device_capability();
    init_company_capacity_ledger();
    init_company_dispatch_amendment();
    CONFIRMED_RECHECK_HORIZON_MS = 15 * 6e4;
  }
});

// retained-source/workers/tracking/modules/company_tracking_room.mjs
var init_company_tracking_room = __esm({
  "retained-source/workers/tracking/modules/company_tracking_room.mjs"() {
    init_company_operation_guard();
    init_company_vehicle_duty_storage();
    init_company_vehicle_device();
    init_company_vehicle_duty();
    init_personal_driver_execution_v1();
    init_per_driver_state();
    init_active_spatial_index();
    init_customer_adaptive_eta();
    init_company_dispatch_mapbox();
    init_reliable_operational_routes_v1();
    init_tenant_cost_metrics();
    init_customer_live_snapshot();
    init_customer_grant_storage();
    init_dispatch_device_capability();
    init_company_capacity_ledger();
    init_company_capacity_storage();
    init_driver_location_owner();
    init_company_dispatch_offers();
  }
});

// retained-source/workers/booking/modules/operational_itinerary.mjs
var init_operational_itinerary = __esm({
  "retained-source/workers/booking/modules/operational_itinerary.mjs"() {
  }
});

// retained-source/workers/booking/modules/financial_sale_projection_v2.mjs
function price(value) {
  if (value == null) return null;
  return {
    ...pick(value, [...moneyFields, "pricing_source", "fixed_fare_applied", "fixed_fare_rule_id", "currency"]),
    ...value.breakdown ? { breakdown: pick(value.breakdown, breakdownFields) } : {}
  };
}
function fare(value) {
  if (!value) return { matched: false };
  return {
    ...pick(value, ["matched", "pricing_source", "fixed_fare_applied", "fixed_fare_rule_id"]),
    ...value.pricing ? { pricing: price(value.pricing) } : {},
    ...value.snapshot ? { snapshot: pick(value.snapshot, ["rule_id", "rule_version", "fixed_fare_rule_id", "currency", "total_incl_vat", "total_ex_vat", "vat_amount", "price_incl_vat"]) } : {},
    ...value.vehicle_pricing ? { vehicle_pricing: pick(value.vehicle_pricing, ["category", "vehicle_ids"]) } : {}
  };
}
function mission(value) {
  return value ? {
    ...pick(value, ["handled", "ok", "request_quote", "reason"]),
    ...value.pricing ? { pricing: price(value.pricing) } : {},
    ...value.vehicle_pricing ? { vehicle_pricing: pick(value.vehicle_pricing, ["category", "vehicle_ids"]) } : {}
  } : { handled: false };
}
function projectFinancialSaleMoneyV2(money) {
  const s = money?.snapshot ?? {}, q = s.quote ?? {};
  return {
    ...pick(money, ["currency", "net_cents", "vat_cents", "gross_cents", "vat_mode"]),
    components: { main: pick(money?.components?.main, breakdownFields), return: money?.components?.return ? pick(money.components.return, breakdownFields) : null },
    snapshot: {
      quote: {
        ...price(q),
        ...pick(q, ["ok", "pricing_source", "pricing_model", "fixed_fare_applied", "fixed_fare_rule_id"]),
        inputs: pick(q.inputs, ["vat_rate", "vat_mode"]),
        pricing_profile: pick(q.pricing_profile, ["return_enabled"]),
        ...q.return ? { return: price(q.return) } : {}
      },
      mainPricing: price(s.mainPricing),
      returnPricing: price(s.returnPricing),
      mission: mission(s.mission),
      fixedFare: fare(s.fixedFare),
      returnPackage: fare(s.returnPackage)
    }
  };
}
function assertFinancialSaleMoneyV2(money) {
  if (canonicalSaleV2(money) !== canonicalSaleV2(projectFinancialSaleMoneyV2(money))) fail("financial_sale_projection_invalid");
  const q = money.snapshot.quote;
  for (const [key2, part] of [["total_price_ex_vat", "net_cents"], ["total_price_vat", "vat_cents"], ["total_price_incl_vat", "gross_cents"]]) {
    const v = q[key2], n = typeof v === "number" ? v : typeof v === "string" && /^(0|[1-9][0-9]*)(\.[0-9]{1,2})?$/.test(v) ? Number(v) : NaN;
    if (!Number.isFinite(n) || n < 0 || !Number.isSafeInteger(Math.round(n * 100)) || Math.abs(n * 100 - Math.round(n * 100)) > 1e-7 || Math.round(n * 100) !== money[part]) fail("financial_sale_money_conflict");
  }
}
var clone, pick, moneyFields, breakdownFields, canonicalSaleV2, fail, TRANSIENT_PROVIDER_BOOK_FIELDS_V2;
var init_financial_sale_projection_v2 = __esm({
  "retained-source/workers/booking/modules/financial_sale_projection_v2.mjs"() {
    clone = (v) => structuredClone(v);
    pick = (v, keys) => Object.fromEntries(keys.filter((k) => v?.[k] != null).map((k) => [k, clone(v[k])]));
    moneyFields = ["price_ex_vat", "price_vat", "price_incl_vat", "total_price_ex_vat", "total_price_vat", "total_price_incl_vat"];
    breakdownFields = [
      "kind",
      "vat_rate",
      "vat_mode",
      "vehicle_category",
      "local_meter",
      "price_rounding",
      "tariff_amount_cents",
      "minimum_applied",
      "minimum_amount_cents",
      "distance_amount_cents",
      "total_ex",
      "vat_amount",
      "total_incl"
    ];
    canonicalSaleV2 = (v) => JSON.stringify(v, (_, x) => x && typeof x === "object" && !Array.isArray(x) ? Object.fromEntries(Object.keys(x).sort().map((k) => [k, x[k]])) : x);
    fail = (r) => {
      throw Error(r);
    };
    TRANSIENT_PROVIDER_BOOK_FIELDS_V2 = Object.freeze([
      "route_preview",
      "return_route_preview",
      "distance_km",
      "duration_min",
      "route_distance_km",
      "route_duration_min",
      "road_distance_km",
      "route",
      "route_geometry",
      "financial_snapshot",
      "legs",
      "routeOut",
      "returnRoute",
      "mission_distance_km",
      "mission_duration_min",
      "occupied_distance_km",
      "return_distance_km",
      "return_duration_min"
    ]);
  }
});

// retained-source/workers/booking/modules/financial_route_evidence.mjs
function canonical(value) {
  if (value === null || typeof value === "string" || typeof value === "boolean") return JSON.stringify(value);
  if (typeof value === "number" && Number.isFinite(value)) return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(canonical).join(",")}]`;
  if (value && typeof value === "object") return `{${Object.keys(value).sort().map((k) => `${JSON.stringify(k)}:${canonical(value[k])}`).join(",")}}`;
  return fail2("evidence_value_invalid");
}
async function digest2(value) {
  const bytes4 = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(canonical(value)));
  return [...new Uint8Array(bytes4)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
function scopeOf(scope2) {
  if (!scope2 || !["tenant_id", "company_id"].every((k) => typeof scope2[k] === "string" && scope2[k].trim())) fail2("evidence_scope_required");
  return { tenant_id: scope2.tenant_id, company_id: scope2.company_id };
}
function checkRoute(route) {
  const approvedLegacy = route?.source === "mapbox" && route.source_version === "directions/v5" && route.profile === "mapbox/driving" && route.duration_basis === "provider_driving";
  const certifiedInternal = route?.duration_basis === "static_normalized" && route.source && route.source_version && route.graph_checksum;
  if (!route || route.access_cost !== "included" || !approvedLegacy && !certifiedInternal) fail2("financial_route_not_certified");
  if (!Array.isArray(route.points) || route.points.length < 2 || !route.points.every((p) => Number.isFinite(p.lat) && Math.abs(p.lat) <= 90 && Number.isFinite(p.lng) && Math.abs(p.lng) <= 180)) fail2("evidence_points_invalid");
  if (!Array.isArray(route.legs) || route.legs.length !== route.points.length - 1 || !route.legs.every((l) => ["distance_m", "duration_s"].every((k) => Number.isFinite(l[k]) && l[k] >= 0))) fail2("evidence_legs_invalid");
  if (route.additional_routes != null) {
    if (!Array.isArray(route.additional_routes)) fail2("evidence_legs_invalid");
    route.additional_routes.forEach(checkRoute);
  }
  return clone2(route);
}
function moneyOf(money) {
  if (!money || money.currency !== "EUR" || !["net_cents", "vat_cents", "gross_cents"].every((k) => Number.isSafeInteger(money[k]) && money[k] >= 0) || money.net_cents + money.vat_cents !== money.gross_cents) fail2("evidence_money_invalid");
  return clone2(money);
}
async function verifyFinancialQuoteEvidence(record, { scope: scope2, inputs, tariff, now, accepted = false }) {
  const { id: id4, ...content } = record ?? {};
  if (![1, 2].includes(content.version) || id4 !== await digest2(content)) fail2("evidence_integrity_failed");
  if (content.version === 2) {
    if (Object.keys(content).some((k) => !["version", "scope", "input_hash", "inputs", "tariff_hash", "tariff", "money", "created_at", "expires_at"].includes(k))) fail2("financial_sale_projection_invalid");
    assertFinancialSaleMoneyV2(content.money);
  }
  if (canonical(content.scope) !== canonical(scopeOf(scope2))) fail2("evidence_scope_mismatch");
  let checkedInputs = inputs;
  if (accepted && content.inputs?.financial_inputs_version == null && Object.hasOwn(content.inputs ?? {}, "pricing_options") && inputs?.financial_inputs_version === 2) {
    checkedInputs = { ...inputs };
    delete checkedInputs.financial_inputs_version;
    if (!Object.hasOwn(content.inputs, "stop_coordinates")) delete checkedInputs.stop_coordinates;
    if (checkedInputs.return && typeof checkedInputs.return === "object") {
      checkedInputs.return = { ...checkedInputs.return };
      if (!Object.hasOwn(content.inputs.return ?? {}, "stop_coordinates")) delete checkedInputs.return.stop_coordinates;
    }
  }
  if (content.input_hash !== await digest2(checkedInputs)) fail2("evidence_inputs_changed");
  if (!accepted && content.tariff_hash !== await digest2(tariff)) fail2("evidence_tariff_changed");
  if (!accepted && (!Number.isSafeInteger(now) || now >= content.expires_at)) fail2("evidence_expired");
  if (content.version === 1) checkRoute(content.route);
  moneyOf(content.money);
  return clone2(record);
}
var clone2, fail2, FinancialRouteEvidenceStore;
var init_financial_route_evidence = __esm({
  "retained-source/workers/booking/modules/financial_route_evidence.mjs"() {
    init_financial_sale_projection_v2();
    clone2 = (value) => structuredClone(value);
    fail2 = (reason) => {
      throw new Error(reason);
    };
    FinancialRouteEvidenceStore = class {
      constructor(storage) {
        if (typeof storage?.get !== "function" || typeof storage?.insertIfAbsent !== "function") fail2("atomic_evidence_storage_required");
        this.storage = storage;
      }
      async saveQuote(record) {
        const { id: id4, ...content } = record;
        if (id4 !== await digest2(content)) fail2("evidence_integrity_failed");
        if ((await this.storage.get(`acceptance:${id4}`))?.state === "closed") fail2("financial_intent_closed");
        await this.storage.insertIfAbsent(`quote:${id4}`, clone2(record));
        return id4;
      }
      // Reserve one durable canonical identity before any operational side effect.
      // A restart can recover it even when the KV booking projection was not written.
      async reserveAcceptance({ quoteId, allocateBookingId, ...validation }) {
        const record = await this.storage.get(`quote:${quoteId}`);
        const key2 = `acceptance:${quoteId}`;
        const existing = await this.storage.get(key2);
        await verifyFinancialQuoteEvidence(record, { ...validation, accepted: !!existing });
        if (await this.storage.get(`historical-hold:${quoteId}`)) fail2("financial_historical_execution_held");
        if (existing?.state === "closed") fail2("financial_intent_closed");
        if (existing) return clone2(existing);
        const candidate = { booking_id: await allocateBookingId(), ...typeof this.storage.compareAndSet === "function" ? { state: "reserved", revision: 1 } : {} };
        await this.storage.insertIfAbsent(key2, candidate);
        const winner = await this.storage.get(key2);
        if (winner?.state === "closed") fail2("financial_intent_closed");
        if (!winner?.booking_id) fail2("acceptance_identity_missing");
        return clone2(winner);
      }
      async accept({ quoteId, bookingId, ...validation }) {
        if (typeof bookingId !== "string" || !bookingId) fail2("booking_id_required");
        const record = await this.storage.get(`quote:${quoteId}`);
        const priorClaim = await this.storage.get(`acceptance:${quoteId}`);
        if (priorClaim?.state === "closed") fail2("financial_intent_closed");
        if (priorClaim && priorClaim.booking_id !== bookingId) fail2("quote_already_accepted");
        await verifyFinancialQuoteEvidence(record, { ...validation, accepted: !!priorClaim });
        if (await this.storage.get(`historical-hold:${quoteId}`)) fail2("financial_historical_execution_held");
        const claimKey = `acceptance:${record.id}`;
        const claim = { booking_id: bookingId };
        const claimed = await this.storage.insertIfAbsent(claimKey, claim);
        if (!claimed && (await this.storage.get(claimKey))?.booking_id !== bookingId) fail2("quote_already_accepted");
        const live = await this.storage.get(claimKey);
        if (live?.state === "closed") fail2("financial_intent_closed");
        if (live?.state === "reserved") {
          if (!await this.storage.compareAndSet(claimKey, live, { ...live, state: "executing", revision: live.revision + 1 })) {
            const changed = await this.storage.get(claimKey);
            if (changed?.state === "closed") fail2("financial_intent_closed");
            if (changed?.booking_id !== bookingId || changed?.state !== "executing") fail2("financial_intent_transition_conflict");
          }
        }
        const key2 = `booking:${await digest2({ scope: scopeOf(validation.scope), bookingId })}`;
        const frozen2 = { booking_id: bookingId, evidence: record };
        const inserted = await this.storage.insertIfAbsent(key2, clone2(frozen2));
        const stored = inserted ? frozen2 : await this.storage.get(key2);
        if (stored?.evidence?.id !== record.id) fail2("booking_evidence_already_frozen");
        return clone2(stored);
      }
      async readAccepted({ bookingId, scope: scope2, inputs }) {
        const key2 = `booking:${await digest2({ scope: scopeOf(scope2), bookingId })}`;
        const stored = await this.storage.get(key2);
        if (!stored) fail2("booking_evidence_missing");
        await verifyFinancialQuoteEvidence(stored.evidence, { scope: scope2, inputs, accepted: true });
        if (await this.storage.get(`historical-hold:${stored.evidence.id}`)) fail2("financial_historical_execution_held");
        return clone2(stored);
      }
      // The accepted sale is already frozen in this D1 table. Canonical booking
      // storage may hold a scoped reference instead of copying a large tariff
      // snapshot into every booking revision. Read-only consumers may inspect a
      // historical hold; execution callers must still honour it.
      async readAcceptedReference({ bookingId, scope: scope2, quoteId, enforceHold = false }) {
        const key2 = `booking:${await digest2({ scope: scopeOf(scope2), bookingId })}`;
        const stored = await this.storage.get(key2);
        if (stored?.booking_id !== bookingId || stored?.evidence?.id !== quoteId) fail2("booking_evidence_reference_missing");
        await verifyFinancialQuoteEvidence(stored.evidence, { scope: scope2, inputs: stored.evidence.inputs, accepted: true });
        const claim = await this.storage.get(`acceptance:${quoteId}`);
        if (claim?.booking_id !== bookingId || claim?.state === "closed") fail2("booking_evidence_reference_conflict");
        if (enforceHold && await this.storage.get(`historical-hold:${quoteId}`)) fail2("financial_historical_execution_held");
        return clone2(stored.evidence);
      }
      async inspectIntent({ quoteId, scope: scope2, inputs }) {
        const quote = await this.storage.get(`quote:${quoteId}`);
        await verifyFinancialQuoteEvidence(quote, { scope: scope2, inputs, accepted: true });
        const claim = await this.storage.get(`acceptance:${quoteId}`);
        const bookingId = claim?.booking_id ?? claim?.closed_booking_id;
        const frozen2 = bookingId ? await this.storage.get(`booking:${await digest2({ scope: scopeOf(scope2), bookingId })}`) : null;
        return { quote, claim: claim ?? null, frozen: frozen2 ?? null };
      }
      async closeUnusedIntent({ quoteId, scope: scope2, inputs, expectedRevision, ownerId, now }) {
        if (typeof this.storage.compareAndSet !== "function") fail2("financial_recovery_atomic_storage_required");
        if (typeof this.storage.assertCloseFence !== "function") fail2("financial_recovery_storage_fence_required");
        await this.storage.assertCloseFence();
        const { quote, claim, frozen: frozen2 } = await this.inspectIntent({ quoteId, scope: scope2, inputs });
        if (claim?.state === "closed") {
          if (frozen2) fail2("financial_recovery_replay_required");
          return clone2(claim);
        }
        if (frozen2 || claim && claim.state !== "reserved") fail2("financial_recovery_replay_required");
        const revision = claim?.revision ?? 0;
        if (expectedRevision !== revision) fail2("financial_recovery_revision_changed");
        const receipt = {
          schema: "fluxidi-financial-intent-closure-v1",
          financial_quote_id: quoteId,
          scope: scopeOf(scope2),
          owner_id: ownerId,
          financial_input_hash: quote.input_hash,
          booking_id: claim?.booking_id ?? null,
          previous_revision: revision,
          revision: revision + 1,
          closed_at: now,
          reason: "no_execution_started",
          active_booking: false,
          provider_payment_started: false,
          active_financial_claim: false
        };
        const closed = {
          ...claim,
          booking_id: claim?.booking_id ?? null,
          closed_booking_id: claim?.booking_id ?? null,
          state: "closed",
          revision: revision + 1,
          storage_fence_version: 1,
          _scope_key: JSON.stringify([quote.scope.tenant_id, quote.scope.company_id]),
          _owner_key: JSON.stringify([quote.scope.tenant_id, quote.scope.company_id, ownerId]),
          receipt: { ...receipt, id: await digest2(receipt) }
        };
        const key2 = `acceptance:${quoteId}`;
        const won = claim ? await this.storage.compareAndSet(key2, claim, closed) : await this.storage.insertIfAbsent(key2, closed);
        if (!won) {
          const current = await this.storage.get(key2);
          if (current?.state === "closed") return clone2(current);
          fail2("financial_recovery_revision_changed");
        }
        return clone2(closed);
      }
    };
  }
});

// retained-source/workers/booking/modules/financial_historical_hold_v1.mjs
var table, historicalHoldExistsSql, historical, id, FINANCIAL_HISTORICAL_HOLD_OBJECTS_V1;
var init_financial_historical_hold_v1 = __esm({
  "retained-source/workers/booking/modules/financial_historical_hold_v1.mjs"() {
    table = "financial_route_evidence_v1";
    historicalHoldExistsSql = (quoteId, bookingId) => `EXISTS(SELECT 1 FROM ${table} h WHERE h.evidence_key='historical-hold:'||${quoteId} AND json_extract(h.payload_json,'$.schema')='fluxidi-historical-execution-hold-v1' AND json_extract(h.payload_json,'$.financial_quote_id')=${quoteId} AND json_extract(h.payload_json,'$.booking_id')=${bookingId})`;
    historical = "substr(NEW.evidence_key,1,16)='historical-hold:'";
    id = "substr(NEW.evidence_key,17)";
    FINANCIAL_HISTORICAL_HOLD_OBJECTS_V1 = [
      { name: "financial_fence_historical_insert_v1", type: "trigger", sql: `CREATE TRIGGER IF NOT EXISTS financial_fence_historical_insert_v1 BEFORE INSERT ON ${table} BEGIN
 SELECT (CASE WHEN ${historical} AND (json_valid(NEW.payload_json)=0 OR json_extract(NEW.payload_json,'$.schema') IS NOT 'fluxidi-historical-execution-hold-v1' OR json_extract(NEW.payload_json,'$.financial_quote_id') IS NOT ${id} OR json_extract(NEW.payload_json,'$.effect') IS NOT 'deny_execution_preserve_evidence' OR json_extract(NEW.payload_json,'$.payment_settled') IS NOT 0 OR length(json_extract(NEW.payload_json,'$.source_capture_sha256')) IS NOT 64 OR NOT EXISTS(SELECT 1 FROM ${table} a JOIN ${table} q ON q.evidence_key='quote:'||${id} JOIN ${table} b ON substr(b.evidence_key,1,8)='booking:' AND json_extract(b.payload_json,'$.evidence.id')=${id} WHERE a.evidence_key='acceptance:'||${id} AND json_extract(a.payload_json,'$.state') IS NULL AND json_extract(a.payload_json,'$._owner_key') IS NULL AND json_extract(q.payload_json,'$.inputs.financial_context.customer_id') IS NULL AND json_extract(a.payload_json,'$.booking_id')=json_extract(NEW.payload_json,'$.booking_id') AND json_extract(b.payload_json,'$.booking_id')=json_extract(a.payload_json,'$.booking_id') AND json_extract(q.payload_json,'$.scope.tenant_id')=json_extract(NEW.payload_json,'$.scope.tenant_id') AND json_extract(q.payload_json,'$.scope.company_id')=json_extract(NEW.payload_json,'$.scope.company_id'))) THEN RAISE(ABORT,'financial_historical_hold_binding_invalid') END);
 SELECT (CASE WHEN ${historical} AND EXISTS(SELECT 1 FROM ${table} h WHERE h.evidence_key=NEW.evidence_key AND h.payload_json<>NEW.payload_json) THEN RAISE(ABORT,'financial_historical_hold_immutable') END);
 SELECT (CASE WHEN substr(NEW.evidence_key,1,11)='acceptance:' AND EXISTS(SELECT 1 FROM ${table} h WHERE h.evidence_key='historical-hold:'||substr(NEW.evidence_key,12)) THEN RAISE(ABORT,'financial_historical_execution_held') END);
 SELECT (CASE WHEN substr(NEW.evidence_key,1,8)='booking:' AND EXISTS(SELECT 1 FROM ${table} h WHERE h.evidence_key='historical-hold:'||json_extract(NEW.payload_json,'$.evidence.id')) THEN RAISE(ABORT,'financial_historical_execution_held') END);
 END` },
      { name: "financial_fence_historical_update_v1", type: "trigger", sql: `CREATE TRIGGER IF NOT EXISTS financial_fence_historical_update_v1 BEFORE UPDATE ON ${table} BEGIN
 SELECT (CASE WHEN substr(OLD.evidence_key,1,16)='historical-hold:' OR substr(NEW.evidence_key,1,16)='historical-hold:' THEN RAISE(ABORT,'financial_historical_hold_immutable') END);
 SELECT (CASE WHEN substr(OLD.evidence_key,1,11)='acceptance:' AND EXISTS(SELECT 1 FROM ${table} h WHERE h.evidence_key='historical-hold:'||substr(OLD.evidence_key,12)) AND NEW.payload_json<>OLD.payload_json THEN RAISE(ABORT,'financial_historical_execution_held') END);
 END` },
      { name: "financial_fence_historical_delete_v1", type: "trigger", sql: `CREATE TRIGGER IF NOT EXISTS financial_fence_historical_delete_v1 BEFORE DELETE ON ${table} BEGIN
 SELECT (CASE WHEN substr(OLD.evidence_key,1,16)='historical-hold:' THEN RAISE(ABORT,'financial_historical_hold_immutable') END);
 END` }
    ];
  }
});

// retained-source/workers/booking/modules/financial_acceptance_fence_v1.mjs
async function assertFinancialAcceptanceFenceV1(db) {
  const row = await db.prepare("SELECT json_group_array(json_object('name',name,'sql',sql,'type',type)) AS objects FROM sqlite_master WHERE name LIKE 'financial_fence_%_v1'").bind().first();
  const actual = JSON.parse(row?.objects ?? "[]");
  if (FINANCIAL_FENCE_OBJECTS_V1.some((x) => !actual.some((a) => a.name === x.name && a.type === x.type && normalized(a.sql ?? "") === normalized(x.sql)))) throw Error("financial_recovery_storage_fence_required");
  const marker = await db.prepare(`SELECT payload_json FROM ${table2} WHERE evidence_key='fence:old-writer-v1'`).bind().first();
  if (marker?.payload_json !== '{"version":1}') throw Error("financial_recovery_storage_fence_required");
}
var table2, extract, owner, scope, claimQuote, bookingQuote, active, ownerBlocked, frozen, trigger, insertion, update, stamp, deletion, FINANCIAL_FENCE_OBJECTS_V1, backfill, FINANCIAL_FENCE_MIGRATION_V1, normalized;
var init_financial_acceptance_fence_v1 = __esm({
  "retained-source/workers/booking/modules/financial_acceptance_fence_v1.mjs"() {
    init_financial_historical_hold_v1();
    table2 = "financial_route_evidence_v1";
    extract = (row, path) => `json_extract(${row},'$.${path}')`;
    owner = (q) => `CASE WHEN ${extract(q, "inputs.financial_context.schema")}='fluxidi-vehicle-financial-context-v1' AND json_type(${q},'$.inputs.financial_context.customer_id')='text' AND length(${extract(q, "inputs.financial_context.customer_id")})>0 THEN json_array(${extract(q, "scope.tenant_id")},${extract(q, "scope.company_id")},${extract(q, "inputs.financial_context.customer_id")}) END`;
    scope = (q) => `json_array(${extract(q, "scope.tenant_id")},${extract(q, "scope.company_id")})`;
    claimQuote = `(SELECT payload_json FROM ${table2} WHERE evidence_key='quote:'||substr(NEW.evidence_key,12))`;
    bookingQuote = `json_extract(NEW.payload_json,'$.evidence.id')`;
    active = `coalesce(json_extract(a.payload_json,'$.state'),'legacy') NOT IN ('closed','resolved')`;
    ownerBlocked = (q, id4) => `EXISTS(SELECT 1 FROM ${table2} a WHERE substr(a.evidence_key,1,11)='acceptance:' AND a.evidence_key<>'acceptance:'||${id4} AND ${active} AND NOT ${historicalHoldExistsSql("substr(a.evidence_key,12)", "json_extract(a.payload_json,'$.booking_id')")} AND (json_extract(a.payload_json,'$._owner_key')=${owner(q)} OR json_extract(a.payload_json,'$._owner_key') IS NULL AND json_extract(a.payload_json,'$._scope_key')=${scope(q)}))`;
    frozen = (id4) => `EXISTS(SELECT 1 FROM ${table2} b WHERE substr(b.evidence_key,1,8)='booking:' AND json_extract(b.payload_json,'$.evidence.id')=${id4})`;
    trigger = (name, event, body) => ({ name, type: "trigger", sql: `CREATE TRIGGER IF NOT EXISTS ${name} ${event} ON ${table2} BEGIN ${body} END` });
    insertion = trigger("financial_fence_insert_v1", "BEFORE INSERT", `
 SELECT (CASE WHEN json_valid(NEW.payload_json)=0 THEN RAISE(ABORT,'financial_payload_invalid') END);
 SELECT (CASE WHEN NEW.evidence_key='fence:old-writer-v1' AND EXISTS(SELECT 1 FROM ${table2} a WHERE substr(a.evidence_key,1,11)='acceptance:' AND json_extract(a.payload_json,'$.state')='closed' AND (json_extract(a.payload_json,'$.storage_fence_version') IS NOT 1 OR ${frozen("substr(a.evidence_key,12)")})) THEN RAISE(ABORT,'financial_migration_closed_unproven') END);
 SELECT (CASE WHEN NEW.evidence_key='fence:old-writer-v1' AND EXISTS(SELECT 1 FROM ${table2} a WHERE substr(a.evidence_key,1,11)='acceptance:' AND ${active} AND json_extract(a.payload_json,'$._owner_key') IS NOT NULL GROUP BY json_extract(a.payload_json,'$._owner_key') HAVING count(*)>1) THEN RAISE(ABORT,'financial_migration_owner_conflict') END);
 SELECT (CASE WHEN substr(NEW.evidence_key,1,6)='quote:' AND EXISTS(SELECT 1 FROM ${table2} a WHERE a.evidence_key='acceptance:'||substr(NEW.evidence_key,7) AND json_extract(a.payload_json,'$.state')='closed') THEN RAISE(ABORT,'financial_intent_closed') END);
 SELECT (CASE WHEN substr(NEW.evidence_key,1,6)='quote:' AND NOT EXISTS(SELECT 1 FROM ${table2} WHERE evidence_key=NEW.evidence_key) AND (${owner("NEW.payload_json")} IS NULL OR ${ownerBlocked("NEW.payload_json", "substr(NEW.evidence_key,7)")}) THEN RAISE(ABORT,'financial_owner_replay_required') END);
 SELECT (CASE WHEN substr(NEW.evidence_key,1,11)='acceptance:' AND NOT EXISTS(SELECT 1 FROM ${table2} WHERE evidence_key='quote:'||substr(NEW.evidence_key,12)) THEN RAISE(ABORT,'financial_quote_missing') END);
 SELECT (CASE WHEN substr(NEW.evidence_key,1,11)='acceptance:' AND NOT EXISTS(SELECT 1 FROM ${table2} WHERE evidence_key=NEW.evidence_key) AND coalesce(json_extract(NEW.payload_json,'$.state'),'legacy')<>'closed' AND (${owner(claimQuote)} IS NULL OR ${ownerBlocked(claimQuote, "substr(NEW.evidence_key,12)")}) THEN RAISE(ABORT,'financial_owner_replay_required') END);
 SELECT (CASE WHEN substr(NEW.evidence_key,1,11)='acceptance:' AND json_extract(NEW.payload_json,'$.state')='closed' AND (json_extract(NEW.payload_json,'$.storage_fence_version') IS NOT 1 OR ${frozen("substr(NEW.evidence_key,12)")}) THEN RAISE(ABORT,'financial_acceptance_started') END);
 SELECT (CASE WHEN substr(NEW.evidence_key,1,8)='booking:' AND NOT EXISTS(SELECT 1 FROM ${table2} a WHERE a.evidence_key='acceptance:'||${bookingQuote} AND json_extract(a.payload_json,'$.booking_id')=json_extract(NEW.payload_json,'$.booking_id') AND coalesce(json_extract(a.payload_json,'$.state'),'legacy') NOT IN ('closed','resolved')) AND NOT EXISTS(SELECT 1 FROM ${table2} b WHERE b.evidence_key=NEW.evidence_key AND json_extract(b.payload_json,'$.evidence.id')=${bookingQuote} AND json_extract(b.payload_json,'$.booking_id')=json_extract(NEW.payload_json,'$.booking_id')) THEN RAISE(ABORT,'financial_closed_or_identity_conflict') END);
`);
    update = trigger("financial_fence_update_v1", "BEFORE UPDATE", `
 SELECT (CASE WHEN NEW.evidence_key<>OLD.evidence_key THEN RAISE(ABORT,'financial_key_immutable') END);
 SELECT (CASE WHEN (substr(OLD.evidence_key,1,6)='quote:' OR substr(OLD.evidence_key,1,8)='booking:' OR OLD.evidence_key='fence:old-writer-v1') AND NEW.payload_json<>OLD.payload_json THEN RAISE(ABORT,'financial_evidence_immutable') END);
 SELECT (CASE WHEN substr(OLD.evidence_key,1,11)='acceptance:' AND json_extract(OLD.payload_json,'$.state')='closed' AND NEW.payload_json<>OLD.payload_json THEN RAISE(ABORT,'financial_closed_immutable') END);
 SELECT (CASE WHEN substr(OLD.evidence_key,1,11)='acceptance:' AND json_extract(OLD.payload_json,'$.state')='resolved' AND NEW.payload_json<>OLD.payload_json THEN RAISE(ABORT,'financial_resolved_immutable') END);
 SELECT (CASE WHEN substr(OLD.evidence_key,1,11)='acceptance:' AND json_extract(OLD.payload_json,'$._scope_key') IS NOT NULL AND json_extract(NEW.payload_json,'$._scope_key') IS NOT json_extract(OLD.payload_json,'$._scope_key') THEN RAISE(ABORT,'financial_scope_immutable') END);
 SELECT (CASE WHEN substr(OLD.evidence_key,1,11)='acceptance:' AND json_extract(OLD.payload_json,'$._owner_key') IS NOT NULL AND (json_extract(NEW.payload_json,'$._owner_key') IS NOT json_extract(OLD.payload_json,'$._owner_key') OR json_extract(NEW.payload_json,'$._scope_key') IS NOT json_extract(OLD.payload_json,'$._scope_key')) THEN RAISE(ABORT,'financial_owner_immutable') END);
 SELECT (CASE WHEN substr(OLD.evidence_key,1,11)='acceptance:' AND json_extract(NEW.payload_json,'$.state')='closed' AND (json_extract(OLD.payload_json,'$.state') IS NOT 'reserved' OR json_extract(NEW.payload_json,'$.storage_fence_version') IS NOT 1 OR json_extract(NEW.payload_json,'$.booking_id') IS NOT json_extract(OLD.payload_json,'$.booking_id') OR json_extract(NEW.payload_json,'$.closed_booking_id') IS NOT json_extract(OLD.payload_json,'$.booking_id') OR ${frozen("substr(OLD.evidence_key,12)")}) THEN RAISE(ABORT,'financial_acceptance_started') END);
 SELECT (CASE WHEN substr(OLD.evidence_key,1,11)='acceptance:' AND json_extract(NEW.payload_json,'$.state') IS NOT 'closed' AND json_extract(NEW.payload_json,'$.booking_id') IS NOT json_extract(OLD.payload_json,'$.booking_id') THEN RAISE(ABORT,'financial_booking_identity_immutable') END);
 SELECT (CASE WHEN substr(OLD.evidence_key,1,11)='acceptance:' AND json_extract(OLD.payload_json,'$.state') IN ('executing','resolved') AND coalesce(json_extract(NEW.payload_json,'$.state'),'legacy') NOT IN ('executing','resolved') THEN RAISE(ABORT,'financial_execution_monotonic') END);
 SELECT (CASE WHEN substr(OLD.evidence_key,1,11)='acceptance:' AND json_extract(NEW.payload_json,'$.state')='resolved' AND (NOT ${frozen("substr(OLD.evidence_key,12)")} OR json_extract(NEW.payload_json,'$.resolution.booking_id') IS NOT json_extract(OLD.payload_json,'$.booking_id') OR json_extract(NEW.payload_json,'$.resolution.financial_quote_id') IS NOT substr(OLD.evidence_key,12) OR json_extract(NEW.payload_json,'$.resolution.stage') IS NOT 'BOOKED' OR json_extract(NEW.payload_json,'$.resolution.payment_resolved') IS NOT 1) THEN RAISE(ABORT,'financial_resolution_unproven') END);
`);
    stamp = trigger("financial_fence_stamp_v1", "AFTER INSERT", `
 UPDATE ${table2} SET payload_json=json_set(payload_json,'$._owner_key',${owner(claimQuote)},'$._scope_key',${scope(claimQuote)}) WHERE evidence_key=NEW.evidence_key AND substr(NEW.evidence_key,1,11)='acceptance:' AND coalesce(json_extract(NEW.payload_json,'$.state'),'legacy') NOT IN ('closed','resolved');
 UPDATE ${table2} SET payload_json=json_set(payload_json,'$.state','executing','$.revision',coalesce(json_extract(payload_json,'$.revision'),0)+1) WHERE evidence_key='acceptance:'||${bookingQuote} AND substr(NEW.evidence_key,1,8)='booking:' AND coalesce(json_extract(payload_json,'$.state'),'legacy') NOT IN ('closed','resolved','executing');
`);
    deletion = trigger("financial_fence_delete_v1", "BEFORE DELETE", `
 SELECT (CASE WHEN substr(OLD.evidence_key,1,6)='quote:' OR substr(OLD.evidence_key,1,11)='acceptance:' OR substr(OLD.evidence_key,1,8)='booking:' OR OLD.evidence_key='fence:old-writer-v1' THEN RAISE(ABORT,'financial_audit_immutable') END);
`);
    FINANCIAL_FENCE_OBJECTS_V1 = [
      { name: "financial_fence_owner_idx_v1", type: "index", sql: `CREATE INDEX IF NOT EXISTS financial_fence_owner_idx_v1 ON ${table2}(json_extract(payload_json,'$._owner_key'),json_extract(payload_json,'$.state')) WHERE substr(evidence_key,1,11)='acceptance:'` },
      { name: "financial_fence_scope_idx_v1", type: "index", sql: `CREATE INDEX IF NOT EXISTS financial_fence_scope_idx_v1 ON ${table2}(json_extract(payload_json,'$._scope_key')) WHERE substr(evidence_key,1,11)='acceptance:'` },
      { name: "financial_fence_booking_idx_v1", type: "index", sql: `CREATE INDEX IF NOT EXISTS financial_fence_booking_idx_v1 ON ${table2}(json_extract(payload_json,'$.evidence.id')) WHERE substr(evidence_key,1,8)='booking:'` },
      insertion,
      update,
      stamp,
      deletion,
      ...FINANCIAL_HISTORICAL_HOLD_OBJECTS_V1
    ];
    backfill = `UPDATE ${table2} SET payload_json=json_set(payload_json,'$._owner_key',(SELECT ${owner("q.payload_json")} FROM ${table2} q WHERE q.evidence_key='quote:'||substr(${table2}.evidence_key,12)),'$._scope_key',(SELECT ${scope("q.payload_json")} FROM ${table2} q WHERE q.evidence_key='quote:'||substr(${table2}.evidence_key,12))) WHERE substr(evidence_key,1,11)='acceptance:' AND json_extract(payload_json,'$.state') IS NOT 'closed' AND json_extract(payload_json,'$._scope_key') IS NULL`;
    FINANCIAL_FENCE_MIGRATION_V1 = [...FINANCIAL_FENCE_OBJECTS_V1.slice(0, 3).map((x) => x.sql), backfill, ...FINANCIAL_FENCE_OBJECTS_V1.slice(3).map((x) => x.sql), `INSERT OR IGNORE INTO ${table2}(evidence_key,payload_json) VALUES('fence:old-writer-v1','{"version":1}')`];
    normalized = (sql) => sql.replace(/IF NOT EXISTS\s+/gi, "").replace(/\s+/g, " ").replace(/;\s*$/, "").trim();
  }
});

// retained-source/workers/booking/modules/financial_route_evidence_d1.mjs
var D1FinancialRouteEvidenceStorage;
var init_financial_route_evidence_d1 = __esm({
  "retained-source/workers/booking/modules/financial_route_evidence_d1.mjs"() {
    init_financial_acceptance_fence_v1();
    D1FinancialRouteEvidenceStorage = class {
      constructor(db) {
        if (typeof db?.prepare !== "function") throw new Error("financial_evidence_database_required");
        this.db = typeof db.withSession === "function" ? db.withSession("first-primary") : db;
      }
      async get(key2) {
        const row = await this.db.prepare("SELECT payload_json FROM financial_route_evidence_v1 WHERE evidence_key = ?").bind(key2).first();
        return row ? JSON.parse(row.payload_json) : void 0;
      }
      async insertIfAbsent(key2, value) {
        const result2 = await this.db.prepare("INSERT OR IGNORE INTO financial_route_evidence_v1 (evidence_key, payload_json) VALUES (?, ?)").bind(key2, JSON.stringify(value)).run();
        if (result2.success !== true) throw new Error("financial_evidence_write_failed");
        return result2.meta?.changes === 1;
      }
      async compareAndSet(key2, expected, value) {
        const result2 = await this.db.prepare("UPDATE financial_route_evidence_v1 SET payload_json = ? WHERE evidence_key = ? AND payload_json = ?").bind(JSON.stringify(value), key2, JSON.stringify(expected)).run();
        if (result2.success !== true) throw new Error("financial_evidence_write_failed");
        return result2.meta?.changes === 1;
      }
      async assertCloseFence() {
        await assertFinancialAcceptanceFenceV1(this.db);
      }
      async hasCloseFence() {
        try {
          await this.assertCloseFence();
          return true;
        } catch {
          return false;
        }
      }
    };
  }
});

// retained-source/workers/booking/modules/financial_route_batch_candidate.mjs
var slot;
var init_financial_route_batch_candidate = __esm({
  "retained-source/workers/booking/modules/financial_route_batch_candidate.mjs"() {
    slot = Symbol("financial-route-batch-v1");
  }
});

// retained-source/workers/booking/modules/financial_quote_lifecycle.mjs
function financialEvidenceStore(env, scope2) {
  if (scope2 && !String(env?.FINANCIAL_EVIDENCE_COMPANIES ?? "").split(",").map((v) => v.trim()).includes(`${scope2.tenant_id}/${scope2.company_id}`)) return null;
  return env?.FINANCIAL_EVIDENCE_DB ? new FinancialRouteEvidenceStore(new D1FinancialRouteEvidenceStorage(env.FINANCIAL_EVIDENCE_DB)) : null;
}
async function verifyBookingFinancialEvidence(record) {
  if (record?._canonical_financial_evidence_ref) throw new Error("booking_evidence_reference_unresolved");
  const copies = [record?.financial_evidence, record?.booking?.financial_evidence].filter((value) => value != null);
  if (!copies.length) return null;
  const evidence = copies[0];
  const scope2 = { tenant_id: record.tenant_id ?? record.booking?.tenant_id, company_id: record.company_id ?? record.booking?.company_id };
  for (const copy2 of copies) {
    await verifyFinancialQuoteEvidence(copy2, { scope: scope2, inputs: copy2?.inputs, accepted: true });
    if (copy2.id !== evidence.id) throw new Error("booking_financial_evidence_mismatch");
  }
  for (const row of [record, record.booking]) {
    if (!row) continue;
    for (const [key2, aliases] of Object.entries({ tenant_id: ["tenant_id", "tenantId"], company_id: ["company_id", "companyId"] })) {
      if (aliases.some((alias) => row[alias] != null && row[alias] !== scope2[key2])) throw new Error("booking_financial_evidence_mismatch");
    }
    if (["financial_quote_id", "financialQuoteId"].some((key2) => row[key2] != null && row[key2] !== evidence.id)) throw new Error("booking_financial_evidence_mismatch");
  }
  const expected = evidence.money;
  const fields = {
    net_cents: ["price_ex_vat", "priceExVat", "total_price_ex_vat", "totalPriceExVat", "subtotal_ex_vat", "subtotalExVat"],
    vat_cents: ["price_vat", "priceVat", "total_price_vat", "totalPriceVat", "vat_amount", "vatAmount"],
    gross_cents: ["price_incl_vat", "priceInclVat", "total_price_incl_vat", "totalPriceInclVat", "total_incl_vat", "totalInclVat"]
  };
  for (const candidate of [record, record.booking, record.quote, record.quote?.pricing]) {
    if (!candidate) continue;
    if (["currency", "booking_currency", "bookingCurrency"].some((key2) => candidate[key2] != null && candidate[key2] !== expected.currency)) throw new Error("booking_financial_evidence_mismatch");
    for (const [part, aliases] of Object.entries(fields)) for (const key2 of aliases) {
      if (candidate[key2] != null && strictFinancialEuroCentsV1(candidate[key2]) !== expected[part]) throw new Error("booking_financial_evidence_mismatch");
    }
  }
  return evidence;
}
async function compactCanonicalFinancialEvidence(env, record, bookingId) {
  if (record?._canonical_financial_evidence_ref) throw new Error("booking_evidence_reference_unresolved");
  const evidence = await verifyBookingFinancialEvidence(record);
  if (!evidence) return record;
  const scope2 = { tenant_id: record.tenant_id, company_id: record.company_id };
  const store = financialEvidenceStore(env, scope2);
  if (!store) throw new Error("financial_evidence_store_required");
  const frozen2 = await store.readAcceptedReference({ bookingId, scope: scope2, quoteId: evidence.id });
  if (frozen2.id !== evidence.id) throw new Error("booking_financial_evidence_mismatch");
  const copy2 = structuredClone(record), paths = [];
  if (copy2.financial_evidence != null) {
    delete copy2.financial_evidence;
    paths.push("root");
  }
  if (copy2.booking?.financial_evidence != null) {
    delete copy2.booking.financial_evidence;
    paths.push("booking");
  }
  copy2._canonical_financial_evidence_ref = { schema: 1, booking_id: bookingId, quote_id: evidence.id, paths };
  return copy2;
}
async function hydrateCanonicalFinancialEvidence(env, record, bookingId) {
  const ref = record?._canonical_financial_evidence_ref;
  if (!ref) return structuredClone(record);
  if (Object.keys(ref).sort().join(",") !== "booking_id,paths,quote_id,schema" || ref.schema !== 1 || ref.booking_id !== bookingId || typeof ref.quote_id !== "string" || !Array.isArray(ref.paths) || !ref.paths.length || ref.paths.length > 2 || new Set(ref.paths).size !== ref.paths.length || ref.paths.some((p) => !["root", "booking"].includes(p)) || record.financial_evidence != null || record.booking?.financial_evidence != null || ref.paths.includes("booking") && (!record.booking || typeof record.booking !== "object")) throw new Error("booking_evidence_reference_invalid");
  const scope2 = { tenant_id: record.tenant_id, company_id: record.company_id };
  const store = financialEvidenceStore(env, scope2);
  if (!store) throw new Error("financial_evidence_store_required");
  const evidence = await store.readAcceptedReference({ bookingId, scope: scope2, quoteId: ref.quote_id });
  const copy2 = structuredClone(record);
  delete copy2._canonical_financial_evidence_ref;
  for (const path of ref.paths) (path === "root" ? copy2 : copy2.booking).financial_evidence = structuredClone(evidence);
  await verifyBookingFinancialEvidence(copy2);
  return copy2;
}
function strictFinancialEuroCentsV1(value) {
  if (typeof value !== "string" && (typeof value !== "number" || !Number.isFinite(value) || value < 0)) throw new Error("booking_financial_evidence_mismatch");
  const raw = String(value);
  if (raw.length > 32 || !/^(0|[1-9][0-9]*)(\.[0-9]{1,2})?$/.test(raw)) throw new Error("booking_financial_evidence_mismatch");
  const [major, minor = ""] = raw.split(".");
  const cents = BigInt(major) * 100n + BigInt(minor.padEnd(2, "0"));
  if (cents > BigInt(Number.MAX_SAFE_INTEGER)) throw new Error("booking_financial_evidence_mismatch");
  return Number(cents);
}
var init_financial_quote_lifecycle = __esm({
  "retained-source/workers/booking/modules/financial_quote_lifecycle.mjs"() {
    init_financial_route_evidence();
    init_financial_route_evidence_d1();
    init_financial_sale_projection_v2();
    init_staging_trial_budget_v1();
    init_financial_route_batch_candidate();
  }
});

// retained-source/workers/booking/modules/customer_booked_route_geometry_v1.mjs
var init_customer_booked_route_geometry_v1 = __esm({
  "retained-source/workers/booking/modules/customer_booked_route_geometry_v1.mjs"() {
    init_financial_quote_lifecycle();
  }
});

// retained-source/workers/booking/modules/customer_tracking_access.mjs
function trackingRevision(source) {
  return {
    lifecycle_seq: Number(source?.customer_tracking_seq) || 1,
    assignment_version: Number(source?.customer_tracking_assignment_version) || 1
  };
}
function trackingLegs(rec) {
  return [rec?.operational_legs, rec?.operationalLegs, rec?.booking?.operational_legs, rec?.booking?.operationalLegs].find(Array.isArray)?.filter((v) => v && typeof v === "object") || [];
}
function trackingLegId(leg) {
  return String(leg?.leg_id || leg?.legId || "");
}
function terminalRecordPhase(record) {
  for (const value of [record?.status, record?.stage, record?.lifecycle_status, record?.lifecycleStatus]) {
    const status = _normLifecycleStatus(value);
    if (status === "COMPLETED" || status === "CANCELLED") return status.toLowerCase();
  }
  return "";
}
function trackingSource(rec, requested = "") {
  const legs = trackingLegs(rec);
  if (legs.length <= 1) {
    return !requested || requested === "primary" || requested === trackingLegId(legs[0]) ? rec : null;
  }
  if (requested && requested !== "primary") return legs.find((l) => trackingLegId(l) === requested) || null;
  const open = legs.filter((l) => !terminalRecordPhase(l) && !["completed", "cancelled", "stopped"].includes(trackingPhaseForStatus(l.status || l.customer_tracking_phase)));
  const selected = open.find((l) => String(l.leg_type || l.legType).toLowerCase() === "outbound") || open[0] || legs[0];
  return trackingLegId(selected) ? selected : null;
}
function currentTrackingTrip(source) {
  const trip = source?.trip;
  if (!trip || typeof trip !== "object") return null;
  if (trip.assignment_version != null && Number(trip.assignment_version) !== trackingRevision(source).assignment_version) return null;
  if (trip.operational_leg && trip.operational_leg !== (trackingLegId(source) || "primary")) return null;
  return trip;
}
var init_customer_tracking_access = __esm({
  "retained-source/workers/booking/modules/customer_tracking_access.mjs"() {
    init_fleet_roster_availability();
    init_public_booking_vehicles();
    init_driver_ops();
    init_company_dispatch();
    init_customer_live_snapshot();
    init_booking_utils();
    init_company_tracking_room();
    init_customer_live_snapshot();
    init_operational_itinerary();
    init_customer_booked_route_geometry_v1();
  }
});

// retained-source/workers/booking/modules/company_ride_execution_identity.mjs
function rideExecutionIdentityAtStart(record, { scope: scope2, driverId, vehicleId, leg = "outbound" } = {}) {
  if (record?.dispatch_offer?.human_acceptance_required !== true) return { ok: true, identity: null };
  const identity = record.dispatch_offer.execution_identities?.[leg];
  if (!identity || identity.tenant_id !== scope2?.tenant_id || identity.company_id !== scope2?.company_id || !frozenRideExecutionIdentityV12(identity, scope2, driverId, vehicleId)) {
    return { ok: false, error: "ride_execution_identity_required" };
  }
  return { ok: true, identity: frozenRideExecutionIdentityV12(identity, scope2, driverId, vehicleId) };
}
var init_company_ride_execution_identity = __esm({
  "retained-source/workers/booking/modules/company_ride_execution_identity.mjs"() {
    init_ride_execution_identity_v1();
  }
});

// retained-source/workers/booking/modules/national_navigation_authorization_v1.mjs
var national_navigation_authorization_v1_exports = {};
__export(national_navigation_authorization_v1_exports, {
  authorizeNationalNavigationV1: () => authorizeNationalNavigationV1,
  readCanonicalNavigationAuthorityV1: () => readCanonicalNavigationAuthorityV1,
  readRoomNavigationAuthorityV1: () => readRoomNavigationAuthorityV1
});
async function readCanonicalNavigationAuthorityV1(state, env, request, body) {
  if (!internal(request, env) || body?.action !== "navigation_authority_read_v1" || !id2(body.booking_id) || !id2(body.scope?.tenant_id) || !id2(body.scope?.company_id)) return response(deny2());
  if (env.BOOKING_RECORD_AUTHORITY_ENABLED !== "1") return response(deny2("navigation_authority_unavailable", 503));
  try {
    const pin = await state.storage.get("canonical-booking-scope"), envelope2 = await state.storage.get("canonical-booking:" + body.booking_id), r = envelope2?.record;
    if (!same(pin, body.scope) || !same(envelope2, body.scope) || !same(r, body.scope) || r.booking_id !== body.booking_id) return response(deny2());
    if (envelope2.schema !== 1 || !Number.isSafeInteger(envelope2.version) || envelope2.version < 1 || r._canonical_version !== envelope2.version || envelope2.projection_pending) return response(deny2("navigation_authority_unavailable", 503));
    const source = trackingSource(r, body.operational_leg ?? "");
    if (!source || terminal(r) || terminal(r.booking) || terminal(source)) return response(deny2());
    const driver = source.assigned_driver_id, vehicle = source.assigned_vehicle_id;
    if (!id2(driver) || !id2(vehicle)) return response(deny2());
    if (source.assignedDriverId != null && source.assignedDriverId !== driver || source.assignedVehicleId != null && source.assignedVehicleId !== vehicle) return response(deny2());
    const offer = r.dispatch_offer;
    if (offer?.human_acceptance_required === true && offer.state !== "committed") return response(deny2());
    const execution = rideExecutionIdentityAtStart(r, { scope: body.scope, driverId: driver, vehicleId: vehicle, leg: source.leg_type ?? "outbound" });
    if (!execution.ok) return response(deny2());
    const trip = currentTrackingTrip(source), phase = source.customer_tracking_phase ?? "assigned";
    if (!["assigned", "en_route_pickup", "arrived_pickup", "in_progress"].includes(phase) || trip?.stopped_at) return response(deny2());
    const tripIds = [trip?.session_id, trip?.trip_id].filter(id2);
    if (body.trip_id) {
      if (phase !== "in_progress" || !trip?.started_at || !tripIds.includes(body.trip_id)) return response(deny2());
    } else if (phase === "in_progress" || trip?.started_at) return response(deny2());
    return response({ ok: true, proof: {
      ...body.scope,
      booking_id: body.booking_id,
      operational_leg: source === r ? "primary" : trackingLegId(source),
      canonical_version: envelope2.version,
      driver_id: driver,
      vehicle_id: vehicle,
      phase,
      assignment_version: Number(source.customer_tracking_assignment_version) || 1,
      trip_id: body.trip_id ?? null,
      execution_identity: execution.identity,
      offer_id: offer?.offer_id ?? null,
      offer_version: offer?.version ?? null,
      capacity_version: r.dispatch_capacity_checkpoint?.version ?? null
    } });
  } catch {
    return response(deny2("navigation_authority_unavailable", 503));
  }
}
async function readRoomNavigationAuthorityV1(state, env, request, body, now = Date.now()) {
  if (!internal(request, env) || new URL(request.url).pathname !== "/navigation-authority" || !same(body?.proof, body?.scope) || !id2(body?.driver_id) || !id2(body?.vehicle_id) || !hash(body?.device_key)) return response(deny2());
  if (env.COMPANY_VEHICLE_OPERATIONS_ENABLED !== "1") return response(deny2("navigation_authority_unavailable", 503));
  try {
    const p = body.proof, s = state.storage;
    if (p.driver_id !== body.driver_id || p.vehicle_id !== body.vehicle_id || !Number.isFinite(body.session_expires_ms) || body.session_expires_ms <= now) return response(deny2());
    const devices = await s.get("dispatch_devices_v1"), leases = driverDispatchDevices2(devices, body.scope, body.driver_id, now, body.device_key);
    if (leases.length !== 1 || Boolean(leases[0].vehicle_device_id) !== Boolean(body.vehicle_device_id) || leases[0].vehicle_device_id !== body.vehicle_device_id && Boolean(body.vehicle_device_id)) return response(deny2());
    if (await s.get(VEHICLE_DUTY_PROJECTION_KEY)) return response(deny2());
    const duty = await s.get(VEHICLE_DUTY_STATE_KEY), dutyProof = dutyForRideExecution(duty, { ...body.scope, driver_id: body.driver_id }, body.vehicle_id);
    const ledger = await hydrateCapacityRecords(s, await readCapacitySnapshot(s), { owner: [p.booking_id], offer: p.offer_id ? [p.offer_id] : [] }, body.scope), owner2 = ledger.owners?.[p.booking_id];
    if (!same(ledger.scope ?? ledger.baseline, body.scope) || !owner2 || owner2.pending || owner2.released || owner2.version !== p.capacity_version) return response(deny2());
    const claims = Object.values(ledger.claims ?? {}).filter((c) => same(c, body.scope) && c.owner_id === p.booking_id && c.driver_id === p.driver_id && c.vehicle_id === p.vehicle_id && (p.operational_leg === "primary" || c.claim_id === p.operational_leg) && !c.capacity_pending && !c.retiring);
    if (claims.length !== 1) return response(deny2());
    if (p.execution_identity) {
      const offer = ledger.offers?.[p.offer_id];
      if (offer?.state !== "committed" || JSON.stringify(offer.receipts?.[p.driver_id]?.execution_identity) !== JSON.stringify(p.execution_identity)) return response(deny2());
    }
    if (p.execution_identity?.kind === "personal_driver_session") {
      if (body.vehicle_device_id) return response(deny2());
      const identity = personalDriverExecutionV12({
        input: {
          ...body.scope,
          driver_id: body.driver_id,
          vehicle_id: body.vehicle_id,
          device_key: body.device_key,
          offer_id: p.offer_id,
          version: p.offer_version,
          personal_execution_auth: { source: "booking_personal_driver_session_v1", ...body.scope, driver_id: body.driver_id, vehicle_id: body.vehicle_id, device_key: body.device_key, session_expires_ms: body.session_expires_ms }
        },
        devices,
        duty,
        offer: ledger.offers?.[p.offer_id],
        nowMs: now
      });
      if (identity?.acceptance_id !== p.execution_identity.acceptance_id) return response(deny2());
    } else {
      if (!dutyProof.ok || p.execution_identity && dutyProof.execution_identity.duty_id !== p.execution_identity.duty_id) return response(deny2());
      if (body.vehicle_device_id) {
        const deviceScope = await s.get("vehicle_device_scope_v1"), device = await s.get("vehicle_device_v1:" + body.vehicle_device_id);
        const active2 = duty.duties.find((d) => d.duty_id === dutyProof.execution_identity.duty_id);
        if (!same(deviceScope, body.scope) || !device || device.revoked || device.expires_at_ms <= now || device.vehicle_id !== body.vehicle_id || active2?.vehicle_device_id !== body.vehicle_device_id) return response(deny2());
      }
    }
    const root = await s.get("drivers_v1"), row = root?.format === "per-driver-v2" ? await s.get("tracking-driver:v2:" + encodeURIComponent(body.driver_id)) : root?.[body.driver_id];
    const captured = Date.parse(row?.captured_at ?? "");
    if (!same(row, body.scope) || row.driver_id !== body.driver_id || row.vehicle_id !== body.vehicle_id || row.location_withdrawn === true || !Number.isFinite(captured) || captured > now || now - captured > 3e4 || !Number.isFinite(row.accuracy) || row.accuracy <= 0 || row.accuracy > 100) return response(deny2());
    if (row.publication_owner && (!boundLocationOwner(row.publication_owner, now) || row.publication_owner.session_hash !== body.device_key)) return response(deny2());
    return response({ ok: true, fence: JSON.stringify([p, owner2.version, claims, dutyProof.ok ? dutyProof.execution_identity : p.execution_identity, body.device_key, body.vehicle_device_id ?? null]) });
  } catch {
    return response(deny2("navigation_authority_unavailable", 503));
  }
}
async function privateRead(env, binding, name, path, body) {
  if (!binding?.idFromName || !binding?.get || !env.ADMIN_TOKEN) return deny2("navigation_authority_unavailable", 503);
  try {
    const r = await binding.get(binding.idFromName(name)).fetch(new Request("https://internal" + path, { method: "POST", headers: { "content-type": "application/json", "x-admin-token": env.ADMIN_TOKEN }, body: JSON.stringify(body), signal: AbortSignal.timeout(5e3) }));
    const result2 = await r.json();
    return result2?.ok === true && r.status === 200 ? result2 : deny2(r.status >= 500 ? "navigation_authority_unavailable" : "navigation_trip_forbidden", r.status >= 500 ? 503 : 403);
  } catch {
    return deny2("navigation_authority_unavailable", 503);
  }
}
async function authorizeNationalNavigationV1({ env, actor, body, path, clock = Date.now }) {
  const operational = Boolean(body.trip_id || body.booking_id || body.operational_leg || body.origin_input?.kind === "gps" || path.endsWith("/reroute"));
  if (!operational) return { ok: true, fence: "address-preview" };
  if (actor?.role !== "driver" || !id2(actor.scope?.tenant_id) || !id2(actor.scope?.company_id) || !id2(actor.driver_id) || !id2(actor.vehicle_id) || !hash(actor.session_hash) || !Number.isFinite(actor.session_expires_ms) || actor.session_expires_ms <= clock()) return deny2();
  if (env.BOOKING_RECORD_AUTHORITY_ENABLED !== "1") return deny2("navigation_authority_unavailable", 503);
  let bookingId = body.booking_id;
  if (!bookingId && id2(body.trip_id)) {
    const prefix = `tenant:${actor.scope.tenant_id}:company:${actor.scope.company_id}:tracking:`;
    const ids = [];
    try {
      for (const kind of ["session", "trip"]) {
        const value = await env.BOOKING_KV.get(prefix + kind + ":" + body.trip_id + ":booking:v1", { type: "json" });
        if (value?.booking_id) ids.push(value.booking_id);
      }
    } catch {
      return deny2("navigation_authority_unavailable", 503);
    }
    if (new Set(ids).size === 1) bookingId = ids[0];
  }
  if (!id2(bookingId)) return deny2();
  const input = { action: "navigation_authority_read_v1", scope: actor.scope, booking_id: bookingId, ...body.trip_id ? { trip_id: body.trip_id } : {}, ...body.operational_leg ? { operational_leg: body.operational_leg } : {} };
  const read = () => privateRead(env, env.COMPANY_CUSTOMER_IMPORT_COORDINATOR, actor.scope.tenant_id + ":" + actor.scope.company_id, "/navigation-authority", input);
  const first = await read();
  if (!first.ok) return first;
  if (first.proof?.driver_id !== actor.driver_id || first.proof?.vehicle_id !== actor.vehicle_id) return deny2();
  const room = await privateRead(env, env.COMPANY_TRACKING, actor.scope.tenant_id + "\n" + actor.scope.company_id, "/navigation-authority", {
    scope: actor.scope,
    proof: first.proof,
    driver_id: actor.driver_id,
    vehicle_id: actor.vehicle_id,
    device_key: actor.session_hash,
    session_expires_ms: actor.session_expires_ms,
    ...actor.vehicle_device_id ? { vehicle_device_id: actor.vehicle_device_id } : {}
  });
  if (!room.ok) return room;
  const second = await read();
  if (!second.ok) return second;
  if (JSON.stringify(first.proof) !== JSON.stringify(second.proof)) return deny2("navigation_assignment_changed", 409);
  return { ok: true, fence: room.fence };
}
var same, id2, hash, deny2, terminal, internal, response;
var init_national_navigation_authorization_v1 = __esm({
  "retained-source/workers/booking/modules/national_navigation_authorization_v1.mjs"() {
    init_customer_tracking_access();
    init_company_ride_execution_identity();
    init_company_vehicle_duty();
    init_company_vehicle_duty_storage();
    init_dispatch_device_capability();
    init_personal_driver_execution_v1();
    init_company_capacity_storage();
    init_driver_location_owner();
    same = (a, b) => a?.tenant_id === b?.tenant_id && a?.company_id === b?.company_id;
    id2 = (s) => typeof s === "string" && s.length > 0 && s.length <= 160 && /^[A-Za-z0-9_.:-]+$/.test(s);
    hash = (s) => typeof s === "string" && /^[a-f0-9]{64}$/.test(s);
    deny2 = (error = "navigation_trip_forbidden", status = 403) => ({ ok: false, error, status });
    terminal = (r) => [r?.status, r?.stage, r?.lifecycle_status, r?.customer_tracking_phase].some((s) => ["COMPLETED", "CANCELLED", "CANCELED", "STOPPED", "REJECTED", "EXPIRED", "NO_SHOW"].includes(String(s ?? "").toUpperCase()));
    internal = (request, env) => request.method === "POST" && typeof env.ADMIN_TOKEN === "string" && env.ADMIN_TOKEN.length > 0 && request.headers.get("x-admin-token") === env.ADMIN_TOKEN;
    response = (r) => Response.json(r, { status: r.ok ? 200 : r.status ?? 503, headers: { "cache-control": "no-store" } });
  }
});

// retained-source/workers/booking/modules/auth_scope.js
function _adminTokenFromRequest(request, url) {
  const h = (request.headers.get("x-admin-token") || "").trim();
  if (h) return h;
  const auth = request.headers.get("authorization") || "";
  const m = auth.match(/^Bearer\s+(.+)$/i);
  if (m && (m[1] || "").trim()) return m[1].trim();
  return "";
}
function _requireAdmin(request, url, env) {
  const expected = (env.ADMIN_TOKEN || "").trim();
  if (!expected) throw new Error("ADMIN_TOKEN is not configured");
  const got = _adminTokenFromRequest(request, url);
  if (!got || got !== expected) throw new Error("Unauthorized");
}
var init_auth_scope = __esm({
  "retained-source/workers/booking/modules/auth_scope.js"() {
    init_parsing_utils();
  }
});

// retained-source/workers/booking/modules/booking_cutover_maintenance.mjs
async function key(env) {
  if (!env.ADMIN_TOKEN) throw Error("cutover_admin_secret_unavailable");
  return crypto.subtle.importKey("raw", new TextEncoder().encode(env.ADMIN_TOKEN), { name: "HMAC", hash: "SHA-256" }, false, ["sign", "verify"]);
}
async function signCanonicalInspectionRequest(env, request) {
  const text3 = await request.clone().text(), body = JSON.parse(text3);
  if (request.method !== "POST" || new URL(request.url).pathname !== "/canonical-inspection" || body.action !== "canonical_booking_inspection" || !valid3(body.scope) || !body.bookingId) {
    throw Error("inspection_capability_scope_invalid");
  }
  const proof = encode(JSON.stringify({
    schema: 1,
    target: inspectionTarget,
    scope: body.scope,
    bookingId: body.bookingId,
    expires: Date.now() + 12e4,
    method: "POST",
    path: "/canonical-inspection",
    digest: hex(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text3)))
  }));
  const signature = hex(await crypto.subtle.sign("HMAC", await key(env), new TextEncoder().encode(proof)));
  return new Request(request.url, {
    method: "POST",
    body: text3,
    headers: { "content-type": "application/json", [inspectionHeader]: `${proof}.${signature}` }
  });
}
async function verifyCanonicalInspectionRequest(env, request) {
  try {
    const parts = (request.headers.get(inspectionHeader) || "").split(".");
    if (parts.length !== 2 || parts[0].length > 1600 || !/^[a-f0-9]{64}$/.test(parts[1])) return null;
    const signature = Uint8Array.from(parts[1].match(/../g), (s) => parseInt(s, 16));
    if (!await crypto.subtle.verify("HMAC", await key(env), signature, new TextEncoder().encode(parts[0]))) return null;
    const proof = JSON.parse(decode(parts[0])), now = Date.now();
    if (proof.schema !== 1 || proof.target !== inspectionTarget || !valid3(proof.scope) || proof.method !== "POST" || request.method !== proof.method || proof.path !== "/canonical-inspection" || new URL(request.url).pathname !== proof.path || !Number.isSafeInteger(proof.expires) || proof.expires <= now || proof.expires > now + 125e3) return null;
    const text3 = await request.clone().text(), body = JSON.parse(text3);
    if (body.action !== "canonical_booking_inspection" || !same2(body.scope, proof.scope) || body.bookingId !== proof.bookingId || proof.digest !== hex(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text3)))) return null;
    return { scope: proof.scope, bookingId: proof.bookingId };
  } catch {
    return null;
  }
}
var context, same2, valid3, encode, decode, hex, inspectionHeader, inspectionTarget;
var init_booking_cutover_maintenance = __esm({
  "retained-source/workers/booking/modules/booking_cutover_maintenance.mjs"() {
    context = Symbol("bookingCutoverMaintenance");
    same2 = (a, b) => a?.tenant_id === b?.tenant_id && a?.company_id === b?.company_id;
    valid3 = (scope2) => typeof scope2?.tenant_id === "string" && typeof scope2?.company_id === "string" && scope2.tenant_id.length > 0 && scope2.company_id.length > 0 && scope2.tenant_id.length <= 80 && scope2.company_id.length <= 80;
    encode = (value) => btoa(String.fromCharCode(...new TextEncoder().encode(value)));
    decode = (value) => new TextDecoder().decode(Uint8Array.from(atob(value), (c) => c.charCodeAt(0)));
    hex = (bytes4) => [...new Uint8Array(bytes4)].map((n) => n.toString(16).padStart(2, "0")).join("");
    inspectionHeader = "x-fluxidi-inspection-proof";
    inspectionTarget = "tracking-canonical-inspection";
  }
});

// retained-source/workers/booking/modules/bounded_json_storage.mjs
var INLINE_BYTES3, CHARS;
var init_bounded_json_storage = __esm({
  "retained-source/workers/booking/modules/bounded_json_storage.mjs"() {
    init_crypto_utils();
    INLINE_BYTES3 = 96 * 1024;
    CHARS = 16 * 1024;
  }
});

// retained-source/workers/booking/modules/customer_projection_journal.mjs
var init_customer_projection_journal = __esm({
  "retained-source/workers/booking/modules/customer_projection_journal.mjs"() {
    init_crypto_utils();
    init_company_customers();
    init_bounded_json_storage();
  }
});

// retained-source/workers/booking/modules/booking_writer_pause.mjs
var init_booking_writer_pause = __esm({
  "retained-source/workers/booking/modules/booking_writer_pause.mjs"() {
  }
});

// retained-source/workers/booking/modules/company_fleet_delta.mjs
var init_company_fleet_delta = __esm({
  "retained-source/workers/booking/modules/company_fleet_delta.mjs"() {
  }
});

// retained-source/workers/booking/modules/company_customers_import.mjs
var init_company_customers_import = __esm({
  "retained-source/workers/booking/modules/company_customers_import.mjs"() {
    init_parsing_utils();
    init_crypto_utils();
    init_http_response();
    init_company_customers();
    init_company_customer_import_coordinator();
  }
});

// retained-source/workers/booking/modules/initial_payment_reconciliation.mjs
var init_initial_payment_reconciliation = __esm({
  "retained-source/workers/booking/modules/initial_payment_reconciliation.mjs"() {
  }
});

// retained-source/workers/booking/modules/initial_booking_intent.mjs
var context2;
var init_initial_booking_intent = __esm({
  "retained-source/workers/booking/modules/initial_booking_intent.mjs"() {
    init_initial_payment_reconciliation();
    context2 = Symbol("initialBookingIntent");
  }
});

// retained-source/workers/booking/modules/vehicle_service_capacity.mjs
var init_vehicle_service_capacity = __esm({
  "retained-source/workers/booking/modules/vehicle_service_capacity.mjs"() {
  }
});

// retained-source/workers/booking/modules/reliable_candidate_v1.mjs
var REQUIRED_BUSINESS_GATES, DEFAULT_RELIABLE_CHOICE_POLICY;
var init_reliable_candidate_v1 = __esm({
  "retained-source/workers/booking/modules/reliable_candidate_v1.mjs"() {
    init_product_estimated_eta_v1();
    init_vehicle_service_capacity();
    init_national_road_access_v1();
    init_official_address_operational_adapter_v1();
    REQUIRED_BUSINESS_GATES = Object.freeze(["tenant", "security", "driver_vehicle_binding", "capacity", "category", "capabilities", "service_area", "fleet_partner_hybrid", "future_bookings", "return", "airport", "reassignment", "payment", "pricing", "operating_policy"]);
    DEFAULT_RELIABLE_CHOICE_POLICY = Object.freeze({ maxCandidates: 5e3, maxGpsAgeMs: 3e4, maxEvidenceAgeMs: 15e3, maxForecastAgeMs: 3e4, pageSize: 25 });
  }
});

// retained-source/workers/booking/modules/address_access_errors_v1.mjs
var init_address_access_errors_v1 = __esm({
  "retained-source/workers/booking/modules/address_access_errors_v1.mjs"() {
  }
});

// retained-source/workers/booking/modules/reliable_prebooking_v1.mjs
var init_reliable_prebooking_v1 = __esm({
  "retained-source/workers/booking/modules/reliable_prebooking_v1.mjs"() {
    init_reliable_candidate_v1();
    init_financial_quote_lifecycle();
    init_reliable_operational_routes_v1();
    init_address_access_errors_v1();
  }
});

// retained-source/workers/booking/modules/staging_trial_do_fence_v1.mjs
var init_staging_trial_do_fence_v1 = __esm({
  "retained-source/workers/booking/modules/staging_trial_do_fence_v1.mjs"() {
  }
});

// retained-source/workers/booking/modules/human_booking_id_allocator.mjs
var init_human_booking_id_allocator = __esm({
  "retained-source/workers/booking/modules/human_booking_id_allocator.mjs"() {
    init_booking_writer_pause();
    init_staging_trial_do_fence_v1();
  }
});

// retained-source/workers/booking/modules/booking_identity.js
var init_booking_identity = __esm({
  "retained-source/workers/booking/modules/booking_identity.js"() {
    init_parsing_utils();
    init_booking_utils();
  }
});

// retained-source/workers/booking/modules/pickup_timing_attention.mjs
var init_pickup_timing_attention = __esm({
  "retained-source/workers/booking/modules/pickup_timing_attention.mjs"() {
    init_operational_itinerary();
  }
});

// retained-source/workers/booking/modules/compliance_events.js
var init_compliance_events = __esm({
  "retained-source/workers/booking/modules/compliance_events.js"() {
    init_parsing_utils();
  }
});

// retained-source/workers/booking/modules/canonical_payment_truth.mjs
var TOKENS_THAT_NEVER_IMPLY_PAID;
var init_canonical_payment_truth = __esm({
  "retained-source/workers/booking/modules/canonical_payment_truth.mjs"() {
    TOKENS_THAT_NEVER_IMPLY_PAID = Object.freeze([
      "completed",
      "confirmed",
      "success",
      "succeeded",
      "captured",
      "bancontact",
      "card",
      "qr",
      "cash",
      "ideal",
      "return_from_checkout",
      "checkout_started",
      "method_selected"
    ]);
  }
});

// retained-source/workers/booking/modules/booking_payment_classify.js
var init_booking_payment_classify = __esm({
  "retained-source/workers/booking/modules/booking_payment_classify.js"() {
    init_parsing_utils();
    init_compliance_events();
    init_canonical_payment_truth();
  }
});

// retained-source/workers/booking/modules/limousine_operational_handoff.mjs
var LIMOUSINE_COMPANY_CONFIRM_RAW_STATUSES;
var init_limousine_operational_handoff = __esm({
  "retained-source/workers/booking/modules/limousine_operational_handoff.mjs"() {
    LIMOUSINE_COMPANY_CONFIRM_RAW_STATUSES = Object.freeze([
      "confirmed",
      "accepted",
      "booked",
      "company_confirmed"
    ]);
  }
});

// retained-source/workers/booking/modules/booking_leg_coordinates.mjs
var init_booking_leg_coordinates = __esm({
  "retained-source/workers/booking/modules/booking_leg_coordinates.mjs"() {
    init_customer_tracking_access();
    init_parsing_utils();
  }
});

// retained-source/workers/booking/modules/booking_read_model.js
var init_booking_read_model = __esm({
  "retained-source/workers/booking/modules/booking_read_model.js"() {
    init_pickup_timing_attention();
    init_parsing_utils();
    init_auth_scope();
    init_booking_utils();
    init_booking_payment_classify();
    init_limousine_operational_handoff();
    init_booking_leg_coordinates();
  }
});

// retained-source/workers/booking/modules/company_roundtrip.mjs
function parseDurationMin(value, fallback = null) {
  const n = Number(value);
  if (!Number.isFinite(n) || n <= 0) return fallback;
  return Math.round(n);
}
function normalizeRoundtripChoice(raw) {
  const text3 = String(raw || "").trim().toLowerCase().replace(/-/g, "_");
  if (text3 === ROUNDTRIP_SPLIT || text3 === "split" || text3 === "no_wait" || text3 === "heen_terug_geen_wacht") {
    return ROUNDTRIP_SPLIT;
  }
  if (text3 === ROUNDTRIP_CONTINUOUS || text3 === "continuous" || text3 === "wait" || text3 === "heen_terug_wacht") {
    return ROUNDTRIP_CONTINUOUS;
  }
  if (text3 === ROUNDTRIP_SINGLE || text3 === "one_way" || text3 === "enkele_rit") {
    return ROUNDTRIP_SINGLE;
  }
  return "";
}
function firstText(source, keys, max = 240) {
  const rec = source && typeof source === "object" ? source : {};
  for (const key2 of keys) {
    const value = safeStr(rec[key2], max);
    if (value) return value;
  }
  return "";
}
function readRoundtripContext(source) {
  const rec = source && typeof source === "object" ? source : {};
  const booking = rec.booking && typeof rec.booking === "object" ? rec.booking : {};
  const payload = rec.payload && typeof rec.payload === "object" ? rec.payload : {};
  const quote = rec.quote && typeof rec.quote === "object" ? rec.quote : {};
  const returnEnabled = !!(rec.return_enabled ?? rec.returnEnabled ?? booking.return_enabled ?? booking.returnEnabled ?? payload.return_enabled ?? payload.return ?? quote.return?.enabled ?? false);
  const returnPickupIso = firstText(rec, [
    "return_pickup_iso",
    "returnPickupIso"
  ], 80) || firstText(booking, ["return_pickup_iso", "returnPickupIso"], 80) || firstText(payload, ["return_pickup_iso", "returnPickupIso"], 80) || safeStr(quote.return?.pickup_iso, 80);
  const occupancyWait = parseDurationMin(
    rec.occupancy_wait_min ?? rec.occupancyWaitMin ?? booking.occupancy_wait_min ?? rec.wait_min ?? rec.waitMin ?? booking.wait_min ?? booking.waitMin ?? payload.wait_min ?? quote.wait_min,
    0
  );
  const stamped = normalizeRoundtripChoice(
    rec.roundtrip_dispatch_mode ?? rec.roundtripDispatchMode ?? booking.roundtrip_dispatch_mode ?? payload.roundtrip_dispatch_mode ?? quote.roundtrip_dispatch_mode
  );
  return {
    returnEnabled,
    hasReturnSchedule: !!returnPickupIso,
    returnPickupIso,
    occupancyWaitMin: Math.max(0, occupancyWait || 0),
    stampedMode: stamped
  };
}
function shouldSplitOperationalReturnLeg(ctx) {
  if (!ctx?.returnEnabled) return false;
  if (Math.max(0, Number(ctx.occupancyWaitMin) || 0) > 0) return false;
  return !!ctx.hasReturnSchedule;
}
function resolveRoundtripDispatchMode(source) {
  const ctx = readRoundtripContext(source);
  if (ctx.stampedMode === ROUNDTRIP_SPLIT || ctx.stampedMode === ROUNDTRIP_CONTINUOUS || ctx.stampedMode === ROUNDTRIP_SINGLE) {
    if (ctx.stampedMode === ROUNDTRIP_SINGLE) return ROUNDTRIP_SINGLE;
    if (!ctx.returnEnabled || !ctx.hasReturnSchedule) return ROUNDTRIP_SINGLE;
    return ctx.stampedMode;
  }
  if (shouldSplitOperationalReturnLeg(ctx)) return ROUNDTRIP_SPLIT;
  if (ctx.returnEnabled && !shouldSplitOperationalReturnLeg(ctx) && ctx.occupancyWaitMin > 0) {
    return ROUNDTRIP_CONTINUOUS;
  }
  return ROUNDTRIP_SINGLE;
}
var ROUNDTRIP_SINGLE, ROUNDTRIP_SPLIT, ROUNDTRIP_CONTINUOUS;
var init_company_roundtrip = __esm({
  "retained-source/workers/booking/modules/company_roundtrip.mjs"() {
    init_booking_leg_coordinates();
    init_parsing_utils();
    ROUNDTRIP_SINGLE = "single";
    ROUNDTRIP_SPLIT = "split_no_wait";
    ROUNDTRIP_CONTINUOUS = "continuous_wait";
  }
});

// retained-source/workers/booking/modules/ride_activity_summary.mjs
var init_ride_activity_summary = __esm({
  "retained-source/workers/booking/modules/ride_activity_summary.mjs"() {
  }
});

// retained-source/workers/booking/modules/booking_indexes.js
var init_booking_indexes = __esm({
  "retained-source/workers/booking/modules/booking_indexes.js"() {
    init_parsing_utils();
    init_human_booking_id_allocator();
    init_auth_scope();
    init_booking_utils();
    init_booking_identity();
    init_booking_read_model();
    init_company_roundtrip();
    init_ride_activity_summary();
  }
});

// retained-source/workers/booking/modules/new_company_capacity.mjs
var init_new_company_capacity = __esm({
  "retained-source/workers/booking/modules/new_company_capacity.mjs"() {
    init_company_tracking_room();
    init_booking_indexes();
  }
});

// retained-source/workers/booking/modules/company_customer_import_coordinator.mjs
var init_company_customer_import_coordinator = __esm({
  "retained-source/workers/booking/modules/company_customer_import_coordinator.mjs"() {
    init_booking_cutover_maintenance();
    init_customer_projection_journal();
    init_bounded_json_storage();
    init_booking_writer_pause();
    init_company_fleet_delta();
    init_tenant_cost_metrics();
    init_company_customers();
    init_company_customers_import();
    init_canonical_booking_authority();
    init_initial_booking_intent();
    init_reliable_operational_routes_v1();
    init_reliable_prebooking_v1();
    init_new_company_capacity();
    init_staging_trial_do_fence_v1();
  }
});

// retained-source/workers/booking/modules/company_customers.mjs
var CUSTOMER_IMPORT_TTL_SECONDS;
var init_company_customers = __esm({
  "retained-source/workers/booking/modules/company_customers.mjs"() {
    init_parsing_utils();
    init_crypto_utils();
    init_http_response();
    init_company_customer_import_coordinator();
    CUSTOMER_IMPORT_TTL_SECONDS = 72 * 60 * 60;
  }
});

// retained-source/workers/booking/modules/company_customer_invoicing.mjs
function validateCompanyCustomerInvoicingPolicy(policy, scope2) {
  if (!policy || policy.schema_version !== 1 || !frequency(policy.invoice_frequency) || !identifier(policy.customer_id) || !identifier(policy.tenant_id) || !identifier(policy.company_id) || !Number.isSafeInteger(policy.customer_revision) || policy.customer_revision < 1 || policy.tenant_id !== scope2?.tenant_id || policy.company_id !== scope2?.company_id) {
    return fail3("billing_policy_unverified");
  }
  return { ok: true, policy: structuredClone(policy) };
}
function companyInvoiceMonth(instant) {
  if (typeof instant !== "string" || !/^\d{4}-\d{2}-\d{2}T.*(?:Z|[+-]\d{2}:\d{2})$/.test(instant)) return null;
  const date = new Date(instant);
  if (!Number.isFinite(date.getTime())) return null;
  const day = instant.slice(0, 10);
  const calendar = /* @__PURE__ */ new Date(`${day}T00:00:00Z`);
  if (!Number.isFinite(calendar.getTime()) || calendar.toISOString().slice(0, 10) !== day) return null;
  const parts = Object.fromEntries(monthFormatter.formatToParts(date).map((p) => [p.type, p.value]));
  return `${parts.year}-${parts.month}`;
}
var identifier, frequency, fail3, monthFormatter;
var init_company_customer_invoicing = __esm({
  "retained-source/workers/booking/modules/company_customer_invoicing.mjs"() {
    init_company_customers();
    identifier = (value) => typeof value === "string" && /^[A-Za-z0-9_-]{1,160}$/.test(value);
    frequency = (value) => value === "per_ride" || value === "monthly";
    fail3 = (error) => ({ ok: false, error });
    monthFormatter = new Intl.DateTimeFormat("en-CA", {
      timeZone: "Europe/Brussels",
      year: "numeric",
      month: "2-digit"
    });
  }
});

// retained-source/workers/booking/modules/company_invoice_source_index.mjs
function memberships(envelope2, scope2, id4) {
  if (!same3(envelope2, scope2) || !same3(envelope2?.record, scope2) || envelope2.schema !== 1 || !Number.isSafeInteger(envelope2.version) || envelope2.version < 1 || envelope2.record._canonical_version !== envelope2.version) throw Error("invoice_source_scope_unverified");
  const record = envelope2.record, policy = record.company_customer_invoicing_policy;
  if (policy == null) return [];
  const verified = validateCompanyCustomerInvoicingPolicy(policy, scope2);
  if (!verified.ok) throw Error(verified.error);
  if (policy.invoice_frequency !== "monthly") return [];
  const lists = [record, record.booking, record.payload].filter(Boolean).flatMap((c) => [c.operational_legs, c.operationalLegs]).filter(Array.isArray).filter((a) => a.length);
  let months = /* @__PURE__ */ new Set();
  if (lists.some((a) => stable(a) !== stable(lists[0]))) months.add("*");
  else for (const row of lists[0] || [record]) if ((row.status ?? row.lifecycle_status ?? row.lifecycleStatus) === "completed") months.add(companyInvoiceMonth(row.completed_at ?? row.completedAt) || "*");
  return [...months].map((month) => ({ key: PREFIX + policy.customer_id + ":" + month + ":" + id4, value: { schema: 1, ...scope2, bookingId: id4, version: envelope2.version } }));
}
async function persistCanonicalWithInvoiceIndex(storage, id4, envelope2, writeCanonical) {
  const meta = await storage.get(META);
  if (!meta) {
    await writeCanonical();
    return;
  }
  const previous = await storage.get(CANONICAL + id4);
  const nextRevision = (meta.revision || 0) + 1;
  await storage.put(META, { ...meta, revision: nextRevision, complete: false, cursor: "", cleared: false });
  await writeCanonical();
  if (meta.complete !== true) return;
  const scope2 = { tenant_id: envelope2.tenant_id, company_id: envelope2.company_id };
  if (!same3(meta, scope2)) throw Error("invoice_source_scope_unverified");
  const oldRows = previous ? memberships(previous, scope2, id4) : [], newRows = memberships(envelope2, scope2, id4);
  for (const row of oldRows) await storage.delete(row.key);
  for (const row of newRows) await storage.put(row.key, row.value);
  const buckets2 = new Set([...oldRows, ...newRows].map((row) => row.key.slice(PREFIX.length, row.key.lastIndexOf(":"))));
  for (const bucket of buckets2) {
    const key2 = "invoice-source-index:v1:revision:" + bucket;
    const revision = await storage.get(key2) || 0;
    if (!Number.isSafeInteger(revision) || revision < 0) throw Error("invoice_inventory_unverified");
    await storage.put(key2, revision + 1);
  }
  await storage.put(META, { ...meta, revision: nextRevision });
}
var META, PREFIX, CANONICAL, same3, stable, sort;
var init_company_invoice_source_index = __esm({
  "retained-source/workers/booking/modules/company_invoice_source_index.mjs"() {
    init_company_customer_invoicing();
    META = "invoice-source-index:v1:meta";
    PREFIX = "invoice-source-index:v1:row:";
    CANONICAL = "canonical-booking:";
    same3 = (a, b) => a?.tenant_id === b?.tenant_id && a?.company_id === b?.company_id;
    stable = (x) => JSON.stringify(sort(x));
    sort = (x) => Array.isArray(x) ? x.map(sort) : x && typeof x === "object" ? Object.fromEntries(Object.keys(x).sort().map((k) => [k, sort(x[k])])) : x;
  }
});

// retained-source/workers/booking/modules/canonical_booking_directory.mjs
async function callDirectory(env, body) {
  const binding = env[CANONICAL_BOOKING_DIRECTORY_BINDING];
  let result2;
  if (!binding?.idFromName || !binding?.get) result2 = failed("canonical_directory_unavailable");
  else try {
    const response2 = await binding.get(binding.idFromName(body.bookingId)).fetch(new Request("https://directory/booking", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body)
    }));
    result2 = await response2.json();
    if (!response2.ok && result2.ok === true) result2 = failed("canonical_directory_response_invalid");
  } catch (_) {
    result2 = failed("canonical_directory_unavailable");
  }
  if (result2?.ok !== true) {
    const error = new Error(result2?.error || "canonical_directory_unavailable");
    error.code = result2?.error;
    error.status = result2?.status || 503;
    throw error;
  }
  if (result2.scope && !validScope(result2.scope) || body.operation === "claim" && !sameScope2(result2.scope, scopeOf2(body.scope))) {
    const error = new Error("canonical_directory_response_invalid");
    error.code = error.message;
    error.status = 503;
    throw error;
  }
  return result2.scope;
}
var CANONICAL_BOOKING_DIRECTORY_BINDING, scopeOf2, validScope, sameScope2, failed, claimCanonicalBookingScope;
var init_canonical_booking_directory = __esm({
  "retained-source/workers/booking/modules/canonical_booking_directory.mjs"() {
    init_booking_cutover_maintenance();
    init_booking_writer_pause();
    CANONICAL_BOOKING_DIRECTORY_BINDING = "CANONICAL_BOOKING_DIRECTORY";
    scopeOf2 = (value) => ({ tenant_id: String(value?.tenant_id || "").trim(), company_id: String(value?.company_id || "").trim() });
    validScope = (scope2) => Boolean(scope2.tenant_id && scope2.company_id && scope2.tenant_id.length <= 80 && scope2.company_id.length <= 80);
    sameScope2 = (a, b) => a?.tenant_id === b?.tenant_id && a?.company_id === b?.company_id;
    failed = (error, status = 503) => ({ ok: false, error, status });
    claimCanonicalBookingScope = (env, bookingId, scope2) => callDirectory(env, { operation: "claim", bookingId, scope: scope2 });
  }
});

// retained-source/workers/booking/modules/dispatch_booking_open.mjs
function hasOpenDispatchAmendment(record) {
  const types = record.dispatch_amendment?.leg_types;
  return resolveRoundtripDispatchMode(record) === "split_no_wait" && Array.isArray(types) && types.length === 1 && ["outbound", "return"].includes(types[0]) && (record.operational_legs || []).some((leg) => leg.leg_type === types[0] && !["COMPLETED", "CANCELLED", "CANCELED", "NO_SHOW", "REJECTED", "EXPIRED"].includes(String(leg.status || leg.lifecycle_status || "").toUpperCase()) && !leg.assigned_driver_id && !leg.assignedDriverId && !leg.assigned_vehicle_id && !leg.assignedVehicleId && leg.customer_tracking_phase !== "in_progress");
}
var init_dispatch_booking_open = __esm({
  "retained-source/workers/booking/modules/dispatch_booking_open.mjs"() {
    init_company_roundtrip();
  }
});

// retained-source/workers/booking/modules/legacy_scope_evidence.mjs
function inspectLegacyOwnership(record) {
  const values = { tenant: [], company: [] };
  let invalid = !object(record);
  for (const source of [record, record?.booking]) {
    if (source == null) continue;
    if (!object(source)) {
      invalid = true;
      continue;
    }
    for (const [part, names] of [["tenant", ["tenant_id", "tenantId"]], ["company", ["company_id", "companyId"]]]) {
      for (const name of names) {
        const value = source[name];
        if (value == null || value === "") continue;
        if (!validText(value, 80)) {
          invalid = true;
          continue;
        }
        if (!values[part].includes(value)) values[part].push(value);
      }
    }
  }
  return {
    tenant_raw: values.tenant[0] || "",
    company_raw: values.company[0] || "",
    invalid,
    conflicting: values.tenant.length > 1 || values.company.length > 1,
    values
  };
}
function legacyOwnershipAgreesWithScope(record, scope2) {
  const raw = inspectLegacyOwnership(record);
  return !raw.invalid && !raw.conflicting && raw.values.tenant.every((value) => value === "fluxidi" || value === scope2.tenant_id) && raw.values.company.every((value) => value === "fluxidi" || value === scope2.company_id);
}
function unresolvedLegacyScopeTransition(record, bookingId) {
  return Boolean(record.alias_of || record.canonical_booking_id && record.canonical_booking_id !== bookingId || record.dispatch_search?.state === "pending" || ["prepared", "offered", "received", "committing"].includes(record.dispatch_offer?.state) || record.dispatch_transition || record.dispatch_transition_rollback || record.dispatch_capacity_pending || record.dispatch_assignment_revalidation || record.dispatch_offer_revalidation);
}
function stable2(value) {
  if (Array.isArray(value)) return value.map(stable2);
  if (!object(value)) return value;
  return Object.fromEntries(Object.keys(value).sort().map((key2) => [key2, stable2(value[key2])]));
}
async function legacyScopeEvidenceDigest(value) {
  const bytes4 = new TextEncoder().encode(JSON.stringify(stable2(value)));
  const digest5 = await crypto.subtle.digest("SHA-256", bytes4);
  return [...new Uint8Array(digest5)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}
function checkedLegacyListPage(page, cursor = null) {
  if (!object(page) || !Array.isArray(page.keys) || typeof page.list_complete !== "boolean" || page.keys.some((key2) => !object(key2) || !validText(key2.name, 360))) throw fail4("legacy_scope_inventory_invalid");
  if (!page.list_complete && (!validText(page.cursor, 1024) || page.cursor === cursor)) {
    throw fail4("legacy_scope_inventory_incomplete");
  }
  return {
    keys: page.keys.map((key2) => key2.name),
    cursor: page.list_complete ? null : page.cursor,
    list_complete: page.list_complete
  };
}
async function buildCompanyIndexMembershipMap(env, { maxIndexes = 200 } = {}) {
  if (!Number.isSafeInteger(maxIndexes) || maxIndexes < 1 || maxIndexes > 2e3) throw fail4("legacy_scope_inventory_limit");
  const membership = /* @__PURE__ */ new Map(), snapshots = [], seenKeys = /* @__PURE__ */ new Set(), seenCursors = /* @__PURE__ */ new Set();
  let cursor = null, pages = 0, entries = 0;
  do {
    if (++pages > 100) throw fail4("legacy_scope_inventory_limit");
    const page = checkedLegacyListPage(await env.BOOKING_KV.list({
      prefix: "tenant:",
      limit: 1e3,
      ...cursor ? { cursor } : {}
    }), cursor);
    for (const key2 of page.keys) {
      if (!key2.endsWith(":bookings:list:v1") || seenKeys.has(key2)) continue;
      const parsed = key2.match(/^tenant:([^:]+):company:([^:]+):bookings:list:v1$/);
      if (!parsed || !validText(parsed[1], 80) || !validText(parsed[2], 80) || parsed[1] === "fluxidi" || parsed[2] === "fluxidi") throw fail4("legacy_scope_inventory_invalid");
      if (seenKeys.size >= maxIndexes) throw fail4("legacy_scope_inventory_limit");
      seenKeys.add(key2);
      const index = await env.BOOKING_KV.get(key2, { type: "json" });
      if (!object(index) || !Array.isArray(index.items)) throw fail4("legacy_scope_inventory_invalid");
      snapshots.push({ key: key2, index });
      const seenIds = /* @__PURE__ */ new Set();
      for (const entry of index.items) {
        if (++entries > 1e4) throw fail4("legacy_scope_inventory_limit");
        const id4 = entry?.booking_id ?? entry?.bookingId;
        if (!object(entry) || !validLegacyBookingId(id4) || entry.booking_id != null && entry.bookingId != null && entry.booking_id !== entry.bookingId) {
          throw fail4("legacy_scope_inventory_invalid");
        }
        if (seenIds.has(id4)) continue;
        seenIds.add(id4);
        const owners = membership.get(id4) || [];
        owners.push({ tenant_id: parsed[1], company_id: parsed[2], index_key: key2 });
        membership.set(id4, owners);
      }
    }
    cursor = page.cursor;
    if (cursor && seenCursors.has(cursor)) throw fail4("legacy_scope_inventory_incomplete");
    if (cursor) seenCursors.add(cursor);
  } while (cursor);
  return {
    membership,
    scopes: snapshots.map(({ key: key2 }) => {
      const parts = key2.match(/^tenant:([^:]+):company:([^:]+):bookings:list:v1$/);
      return { tenant_id: parts[1], company_id: parts[2] };
    }),
    indexes_scanned: seenKeys.size,
    complete: true,
    inventory_digest: await legacyScopeEvidenceDigest(snapshots.sort((a, b) => a.key.localeCompare(b.key)))
  };
}
function applyProvenLegacyOwnership(record, scope2, recordDigest) {
  const next = { ...record, ...scope2, tenantId: scope2.tenant_id, companyId: scope2.company_id };
  if (object(record.booking)) next.booking = { ...record.booking, ...scope2, tenantId: scope2.tenant_id, companyId: scope2.company_id };
  next.legacy_scope_migrated_at = (/* @__PURE__ */ new Date()).toISOString();
  next.legacy_scope_migration_source = "company_list_index";
  next.legacy_scope_migration_record_digest = recordDigest;
  return next;
}
var fail4, object, validText, validLegacyBookingId;
var init_legacy_scope_evidence = __esm({
  "retained-source/workers/booking/modules/legacy_scope_evidence.mjs"() {
    fail4 = (code, status = 409) => {
      const error = new Error(code);
      error.code = code;
      error.status = status;
      return error;
    };
    object = (value) => value && typeof value === "object" && !Array.isArray(value);
    validText = (value, max) => typeof value === "string" && value.length > 0 && value.length <= max && value === value.trim() && !/[\s\x00-\x1f\x7f]/.test(value);
    validLegacyBookingId = (value) => validText(value, 160);
  }
});

// retained-source/workers/booking/modules/canonical_booking_authority.mjs
function bookingIdOfKey(key2) {
  if (typeof key2 !== "string" || !key2.startsWith("booking:")) return "";
  const id4 = key2.slice(8);
  if (!id4 || id4.length > 160 || /\s/.test(id4)) throw exception(failed2("canonical_booking_id_invalid", 400));
  return id4;
}
function exception(result2) {
  const error = new Error(result2.error || "canonical_booking_unavailable");
  error.code = result2.error;
  error.status = result2.status || 503;
  return error;
}
function dispatchIntent(record, id4) {
  if (["COMPLETED", "CANCELLED", "CANCELED", "NO_SHOW", "REJECTED", "EXPIRED"].includes(String(record.status || record.lifecycle_status || "").toUpperCase()) || !hasOpenDispatchAmendment(record) && (record.assigned_driver_id || record.assignedDriverId || record.assigned_vehicle_id || record.assignedVehicleId || record.booking?.assigned_driver_id || record.booking?.assigned_vehicle_id)) return null;
  const offer = record.dispatch_offer;
  if (offer?.state === "prepared" && offer.offer_id && Number.isSafeInteger(offer.version)) {
    return { type: "offer", id: offer.offer_id, version: offer.version };
  }
  const search = record.dispatch_search;
  return search?.state === "pending" && Number.isSafeInteger(search.version) ? { type: "search", id: `search:${id4}:${search.version}`, version: search.version } : null;
}
async function envelope(env, scope2, record, version, options, previous, id4) {
  if (record?._canonical_financial_evidence_ref) throw exception(failed2("booking_evidence_reference_unresolved", 409));
  const intent = dispatchIntent(record, id4), handedOff = sameIntent(intent, previous?.dispatch_handoff);
  const next = {
    schema: 1,
    ...scope2,
    version,
    record: { ...record, [VERSION]: version },
    projection_pending: true,
    dispatch_retry: handedOff ? null : intent,
    ...handedOff ? { dispatch_handoff: previous.dispatch_handoff } : {},
    ...options ? { projection_options: options } : {}
  };
  if (new TextEncoder().encode(JSON.stringify(next)).byteLength > MAX_RECORD_BYTES) {
    next.record = await compactCanonicalFinancialEvidence(env, next.record, id4);
  }
  if (new TextEncoder().encode(JSON.stringify(next)).byteLength > MAX_RECORD_BYTES) {
    throw exception(failed2("canonical_booking_too_large", 413));
  }
  return next;
}
async function armRecovery(state) {
  if (!state.storage.setAlarm || !state.storage.list || !state.storage.delete) {
    throw exception(failed2("canonical_booking_recovery_unavailable"));
  }
  const next = Date.now() + RECOVERY_DELAY_MS;
  const alarm = state.storage.getAlarm ? await state.storage.getAlarm() : null;
  if (alarm == null || alarm > next) await state.storage.setAlarm(next);
}
async function persistPending(state, id4, value) {
  await armRecovery(state);
  await state.storage.put(`${RECOVERY_PREFIX}${id4}`, { schema: 1, bookingId: id4, ...scopeOf3(value) });
  await persistCanonicalWithInvoiceIndex(state.storage, id4, value, () => state.storage.put(storageKey(id4), value));
}
async function finishRecovery(state, id4, value) {
  if (!value?.projection_pending && !value?.dispatch_retry) await state.storage.delete(`${RECOVERY_PREFIX}${id4}`);
}
function canonicalBookingAuthorityEnabled(env) {
  return env?.BOOKING_RECORD_AUTHORITY_ENABLED === "1";
}
async function canonicalBookingOperation(state, env, body) {
  if (!canonicalBookingAuthorityEnabled(env)) return failed2("canonical_authority_disabled");
  const scope2 = scopeOf3(body.scope), id4 = String(body.bookingId || "").trim();
  if (!validScope2(scope2) || !id4 || !bookingIdOfKey(`booking:${id4}`) || id4.length > 160) {
    return failed2("canonical_booking_scope_invalid", 400);
  }
  const pin = await state.storage.get("canonical-booking-scope");
  if (pin && !sameScope3(pin, scope2)) return failed2("canonical_booking_scope_conflict", 403);
  const operation = String(body.operation || "read");
  const kv = env[rawBookingKv] || env.BOOKING_KV, key2 = `booking:${id4}`;
  let current = await state.storage.get(storageKey(id4));
  if (current && (!sameScope3(current, scope2) || !sameScope3(scopeOf3(current.record), scope2))) {
    return failed2("canonical_booking_scope_conflict", 403);
  }
  if (operation === "inspect") return { ok: true, record: current ? await hydrateCanonicalFinancialEvidence(env, current.record, id4) : null };
  if (operation === "adopt_legacy_scope" && !["1", "true", "yes", "on"].includes(String(env.LEGACY_SCOPE_MIGRATION_ENABLED || "0").trim().toLowerCase())) return failed2("legacy_scope_migration_disabled", 403);
  if (!pin) await state.storage.put("canonical-booking-scope", scope2);
  if (current) await claimCanonicalBookingScope(env, id4, scope2);
  if (operation === "adopt_legacy_scope" && !current) {
    const inventory = await buildCompanyIndexMembershipMap({ ...env, BOOKING_KV: kv }, { maxIndexes: body.maxIndexes || 200 });
    const legacy = await kv.get(key2, { type: "json" });
    if (!legacy || await legacyScopeEvidenceDigest(legacy) !== body.recordDigest || inventory.inventory_digest !== body.inventoryDigest) return failed2("legacy_scope_review_conflict", 409);
    const owners = inventory.membership.get(id4) || [];
    const uniqueOwners = [...new Map(owners.map((owner2) => [JSON.stringify([owner2.tenant_id, owner2.company_id]), owner2])).values()];
    if (uniqueOwners.length !== 1 || !sameScope3(uniqueOwners[0], scope2) || !legacyOwnershipAgreesWithScope(legacy, scope2) || legacy.legacy_scope_quarantine || ["ambiguous", "legacy_scope_ambiguous"].includes(legacy.legacy_scope_status)) {
      return failed2("legacy_scope_ownership_unresolved", 409);
    }
    if (unresolvedLegacyScopeTransition(legacy, id4)) {
      return failed2("legacy_scope_transition_unresolved", 409);
    }
    const next2 = await envelope(env, scope2, applyProvenLegacyOwnership(legacy, scope2, body.recordDigest), 1, void 0, void 0, id4);
    await claimCanonicalBookingScope(env, id4, scope2);
    await persistPending(state, id4, next2);
    current = next2;
  }
  if (!current && operation !== "adopt_legacy_scope") {
    const legacy = await kv.get(key2, { type: "json" });
    if (legacy) {
      const raw2 = inspectLegacyOwnership(legacy);
      if (raw2.invalid || raw2.conflicting || !sameScope3(scopeOf3(legacy), scope2)) return body.operation === "write" ? failed2("canonical_booking_scope_conflict", 403) : { ok: true, record: null };
      current = await envelope(env, scope2, legacy, 1, void 0, void 0, id4);
      await claimCanonicalBookingScope(env, id4, scope2);
      await persistPending(state, id4, current);
    }
  }
  async function project(value) {
    if (!value.projection_pending) return;
    await kv.put(key2, JSON.stringify(await hydrateCanonicalFinancialEvidence(env, value.record, id4)), value.projection_options);
    const clean = { ...value, projection_pending: false };
    await state.storage.put(storageKey(id4), clean);
    current = clean;
    await finishRecovery(state, id4, clean);
  }
  if (operation === "read" || operation === "adopt_legacy_scope") {
    if (current) await project(current);
    return { ok: true, record: current ? await hydrateCanonicalFinancialEvidence(env, current.record, id4) : null };
  }
  if (operation === "dispatch_handoff") {
    if (!current) return failed2("canonical_booking_unavailable", 409);
    if (!sameIntent(current.dispatch_retry, body.intent) && !sameIntent(current.dispatch_handoff, body.intent)) {
      return failed2("canonical_dispatch_intent_conflict", 409);
    }
    await project(current);
    const handedOff = { ...current, dispatch_retry: null, dispatch_handoff: body.intent };
    await state.storage.put(storageKey(id4), handedOff);
    current = handedOff;
    await finishRecovery(state, id4, handedOff);
    return { ok: true, handed_off: true };
  }
  if (operation !== "write") return failed2("canonical_booking_operation_invalid", 400);
  const record = body.record;
  const raw = inspectLegacyOwnership(record);
  if (!record || typeof record !== "object" || Array.isArray(record) || raw.invalid || raw.conflicting || !sameScope3(scopeOf3(record), scope2)) {
    return failed2("canonical_booking_scope_conflict", 403);
  }
  if (!Number.isSafeInteger(body.expectedVersion) || body.expectedVersion < 0) {
    return failed2("canonical_booking_version_invalid", 400);
  }
  if (body.expectedVersion !== (current?.version || 0)) {
    const replayRecord = current?.record?._canonical_financial_evidence_ref ? await compactCanonicalFinancialEvidence(env, record, id4) : record;
    if (current && JSON.stringify(withoutVersion(replayRecord)) === JSON.stringify(withoutVersion(current.record))) {
      await project(current);
      return { ok: true, record: await hydrateCanonicalFinancialEvidence(env, current.record, id4), idempotent: true };
    }
    return failed2("canonical_booking_revision_conflict", 409);
  }
  const next = await envelope(env, scope2, record, (current?.version || 0) + 1, body.options, current, id4);
  await claimCanonicalBookingScope(env, id4, scope2);
  await persistPending(state, id4, next);
  await project(next);
  return { ok: true, record: await hydrateCanonicalFinancialEvidence(env, current.record, id4) };
}
var rawBookingKv, authorityScope, dispatchHandoff, VERSION, MAX_RECORD_BYTES, MAX_PAGE_RECORD_BYTES, RECOVERY_PREFIX, RECOVERY_DELAY_MS, failed2, scopeOf3, sameScope3, validScope2, storageKey, withoutVersion, sameIntent;
var init_canonical_booking_authority = __esm({
  "retained-source/workers/booking/modules/canonical_booking_authority.mjs"() {
    init_financial_quote_lifecycle();
    init_company_invoice_source_index();
    init_company_customer_import_coordinator();
    init_canonical_booking_directory();
    init_dispatch_booking_open();
    init_legacy_scope_evidence();
    rawBookingKv = Symbol("rawBookingKv");
    authorityScope = Symbol("authorityScope");
    dispatchHandoff = Symbol("dispatchHandoff");
    VERSION = "_canonical_version";
    MAX_RECORD_BYTES = 120 * 1024;
    MAX_PAGE_RECORD_BYTES = 8 * 1024 * 1024;
    RECOVERY_PREFIX = "canonical-booking-recovery:";
    RECOVERY_DELAY_MS = 6e4;
    failed2 = (error, status = 503) => ({ ok: false, error, status });
    scopeOf3 = (value) => ({
      tenant_id: String(value?.tenant_id || value?.tenantId || value?.booking?.tenant_id || "").trim(),
      company_id: String(value?.company_id || value?.companyId || value?.booking?.company_id || "").trim()
    });
    sameScope3 = (a, b) => a?.tenant_id === b?.tenant_id && a?.company_id === b?.company_id;
    validScope2 = (scope2) => Boolean(scope2?.tenant_id && scope2?.company_id && scope2.tenant_id.length <= 80 && scope2.company_id.length <= 80);
    storageKey = (id4) => `canonical-booking:${id4}`;
    withoutVersion = (record) => {
      const copy2 = { ...record };
      delete copy2[VERSION];
      return copy2;
    };
    sameIntent = (a, b) => Boolean(a && b && a.type === b.type && a.id === b.id && a.version === b.version);
  }
});

// retained-source/workers/booking/modules/canonical_booking_inspection.mjs
var canonical_booking_inspection_exports = {};
__export(canonical_booking_inspection_exports, {
  authorizeCanonicalInspection: () => authorizeCanonicalInspection,
  callCanonicalBookingInspection: () => callCanonicalBookingInspection,
  inspectCanonicalWithoutMutation: () => inspectCanonicalWithoutMutation,
  inspectCapacityWithoutMutation: () => inspectCapacityWithoutMutation
});
function authorizeCanonicalInspection(request, env, body) {
  try {
    _requireAdmin(request, new URL(request.url), env);
  } catch {
    return false;
  }
  return request.method === "POST" && inspectionScopeAllowed(body);
}
function inspectionScopeAllowed(body) {
  return body?.action === "canonical_booking_inspection" && Object.entries(target).every(([k, v]) => body?.[k] === v) && body.scope?.tenant_id === company && body.scope?.company_id === company;
}
async function callCanonicalBookingInspection(request, env) {
  const body = await request.clone().json().catch(() => null);
  if (!authorizeCanonicalInspection(request, env, body)) return fail5();
  const binding = env.COMPANY_CUSTOMER_IMPORT_COORDINATOR;
  if (!binding?.idFromName || !binding?.get) return Response.json(result(["canonical_binding_unavailable"]), { status: 503 });
  try {
    const coordinator = binding.get(binding.idFromName(`${body.scope.tenant_id}:${body.scope.company_id}`));
    return await coordinator.fetch(new Request("https://internal/", {
      method: "POST",
      headers: { "content-type": "application/json", "x-admin-token": env.ADMIN_TOKEN },
      body: JSON.stringify(body)
    }));
  } catch {
    return Response.json(result(["canonical_binding_unavailable"]), { status: 503 });
  }
}
async function inspectCapacityWithoutMutation(state, env, request, body) {
  if (!inspectionScopeAllowed(body) || !await verifyCanonicalInspectionRequest(env, request)) return fail5();
  const storage = state.storage, root = copy(await storage.get(CAPACITY_STORAGE_KEY));
  if (root == null) return Response.json(result(["capacity_snapshot"]));
  try {
    const ledger = await hydrateCapacityRecords(
      storage,
      await readCapacitySnapshot(storage),
      { owner: [target.bookingId], offer: body.offerId ? [body.offerId] : [], event: body.eventId ? [body.eventId] : [] },
      body.scope
    );
    const owner2 = ledger.owners?.[target.bookingId];
    const claims = Object.values(ledger.claims || {}).filter((x) => x.owner_id === target.bookingId);
    const offers = Object.values(ledger.offers || {}).filter((x) => x.owner_id === target.bookingId);
    const events = Object.values(ledger.dispatch_events || {}).filter((x) => x.owner_id === target.bookingId);
    if ([owner2, ...claims, ...offers, ...events].filter(Boolean).some((x) => !same4(x, body.scope))) return fail5();
    const end = await storage.get(CAPACITY_STORAGE_KEY);
    const out = result(owner2 ? [] : ["capacity_owner"]);
    if (JSON.stringify(root) !== JSON.stringify(end)) out.consistency = "inconsistent";
    else if (owner2) out.consistency = "sampled";
    out.fingerprint = await hash2(JSON.stringify({ root, owner: owner2, claims, offers, events }));
    out.owner = owner2 ? { version: owner2.version, pending: owner2.pending === true, released: owner2.released === true } : null;
    out.claims = claims.map((x) => ({ active: x.active === true, pending: x.capacity_pending === true, retiring: x.retiring === true, version: x.capacity_version }));
    out.offers = offers.map((x) => ({ state: x.state, version: x.version, reason: x.reason }));
    out.events = events.map((x) => ({ type: x.type, state: x.state, version: x.version }));
    return Response.json(out);
  } catch {
    return Response.json(result(["capacity_evidence_unverifiable"]));
  }
}
async function inspectCanonicalWithoutMutation(state, env, request, body) {
  if (!authorizeCanonicalInspection(request, env, body)) return fail5();
  const storage = state.storage, scope2 = body.scope, key2 = "canonical-booking:" + target.bookingId;
  const pin = copy(await storage.get("canonical-booking-scope"));
  if (pin && !same4(pin, scope2)) return fail5();
  const envelope2 = copy(await storage.get(key2));
  if (!envelope2) return Response.json(result(["canonical_record"]));
  if (!same4(envelope2, scope2) || !same4(envelope2.record, scope2)) return fail5();
  const markers = async () => ({
    journal: await storage.get("customer-projection-journal-v1"),
    journalIntent: await storage.get("customer-projection-journal-v1:chunk-intent"),
    recovery: await storage.get("canonical-booking-recovery:" + target.bookingId)
  });
  const beforeMarkers = copy(await markers());
  const out = result([]), r = envelope2.record;
  if (r.planning_reference !== target.planning || r.public_reference !== target.publicReference) out.missing.push("canonical_reference_binding");
  out.canonical = {
    version: envelope2.version,
    revision: r.revision,
    status: r.status ?? r.stage ?? null,
    assigned_driver: !!r.assigned_driver_id,
    assigned_vehicle: !!r.assigned_vehicle_id,
    dispatch_pending: r.dispatch_search?.pending === true,
    search_deadline: r.asap_search_expires_at ?? null,
    offer_state: r.dispatch_offer?.state ?? null,
    offer_reason: r.dispatch_offer?.reason ?? null
  };
  out.recovery = {
    projection_pending: !!envelope2.projection_pending,
    dispatch_retry: !!envelope2.dispatch_retry,
    dispatch_handoff: !!envelope2.dispatch_handoff,
    journal_present: beforeMarkers.journal != null,
    journal_intent_present: beforeMarkers.journalIntent != null,
    recovery_marker_present: beforeMarkers.recovery != null
  };
  if (!pin) out.missing.push("canonical_scope_pin");
  if (!Number.isSafeInteger(envelope2.version) || envelope2.version !== r._canonical_version) out.consistency = "inconsistent";
  if (Object.values(out.recovery).some(Boolean)) out.missing.push("recovery_markers_require_reconciliation");
  let inspected;
  try {
    inspected = await canonicalBookingOperation(state, env, { operation: "inspect", scope: scope2, bookingId: target.bookingId });
  } catch {
    out.missing.push("financial_evidence_unverifiable");
  }
  if (!inspected?.ok || !r._canonical_financial_evidence_ref) out.missing.push("accepted_financial_reference");
  out.financial = { accepted_reference_verified: inspected?.ok === true && !!r._canonical_financial_evidence_ref };
  let financialBefore = null;
  const readFinancial = async () => {
    const evidence = inspected?.record?.financial_evidence ?? inspected?.record?.booking?.financial_evidence;
    if (!evidence) return null;
    const store = financialEvidenceStore(env, scope2);
    return store?.inspectIntent({ quoteId: evidence.id, scope: scope2, inputs: evidence.inputs });
  };
  try {
    financialBefore = await readFinancial();
  } catch {
    out.missing.push("financial_claim_unverifiable");
  }
  if (financialBefore?.claim?.booking_id === target.bookingId && financialBefore?.frozen?.booking_id === target.bookingId && Number.isSafeInteger(financialBefore.claim.revision)) {
    out.financial.claim_state = financialBefore.claim.state;
    out.financial.claim_revision = financialBefore.claim.revision;
  } else out.missing.push("financial_claim_binding");
  let intentKey = null, intentBefore = null;
  if (r._canonical_financial_evidence_ref?.quote_id) {
    intentKey = "initial-booking-intent:" + await hash2(`financial_booking_intent:${scope2.tenant_id}:${scope2.company_id}:${r._canonical_financial_evidence_ref.quote_id}`);
    intentBefore = copy(await storage.get(intentKey));
  }
  out.idempotency = { verified: !!intentBefore && same4(intentBefore, scope2) && intentBefore.bookingId === target.bookingId };
  if (!out.idempotency.verified) out.missing.push("canonical_idempotency_binding");
  let first = null, second = null;
  const readCapacity = async () => {
    if (!env.COMPANY_TRACKING?.get || !env.COMPANY_TRACKING?.idFromName) return null;
    const room = env.COMPANY_TRACKING.get(env.COMPANY_TRACKING.idFromName(`${scope2.tenant_id}
${scope2.company_id}`));
    const internal2 = await signCanonicalInspectionRequest(env, new Request("https://internal/canonical-inspection", {
      method: "POST",
      body: JSON.stringify({ ...body, offerId: r.dispatch_offer?.offer_id, eventId: r.dispatch_search?.event_id })
    }));
    const response2 = await room.fetch(internal2);
    if (!response2.ok) return null;
    const data = await response2.json();
    return data?.ok === true && data.booking_id === target.bookingId ? data : null;
  };
  try {
    first = await readCapacity();
    second = await readCapacity();
  } catch {
    out.missing.push("capacity_transport");
  }
  out.capacity = first;
  if (!first || !second || first.consistency !== "sampled" || second.consistency !== "sampled") out.missing.push("capacity_snapshot_or_owner");
  if (first?.consistency === "inconsistent" || second?.consistency === "inconsistent" || first?.fingerprint !== second?.fingerprint) out.consistency = "inconsistent";
  const expected = r.dispatch_offer?.version ?? r.dispatch_capacity_checkpoint?.version;
  if (!Number.isSafeInteger(expected)) out.missing.push("canonical_capacity_revision");
  else if (first?.owner && first.owner.version !== expected) out.consistency = "inconsistent";
  if (JSON.stringify(envelope2) !== JSON.stringify(await storage.get(key2)) || JSON.stringify(pin) !== JSON.stringify(await storage.get("canonical-booking-scope")) || JSON.stringify(beforeMarkers) !== JSON.stringify(await markers()) || intentKey && JSON.stringify(intentBefore) !== JSON.stringify(await storage.get(intentKey))) out.consistency = "inconsistent";
  try {
    if (JSON.stringify(financialBefore) !== JSON.stringify(await readFinancial())) out.consistency = "inconsistent";
  } catch {
    out.consistency = "inconsistent";
  }
  out.missing.push("cross_store_financial_revision_fence");
  out.missing = [...new Set(out.missing)];
  return Response.json(out);
}
var target, company, same4, hash2, copy, fail5, result;
var init_canonical_booking_inspection = __esm({
  "retained-source/workers/booking/modules/canonical_booking_inspection.mjs"() {
    init_auth_scope();
    init_canonical_booking_authority();
    init_financial_quote_lifecycle();
    init_booking_cutover_maintenance();
    init_company_capacity_storage();
    target = { bookingId: "2026-10-030", planning: "PLN-2026-000480", publicReference: "2026-10-000019" };
    company = "fluxidi_fluxidi_ddmh9g";
    same4 = (a, b) => a?.tenant_id === b?.tenant_id && a?.company_id === b?.company_id;
    hash2 = async (value) => Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value))), (v) => v.toString(16).padStart(2, "0")).join("");
    copy = (value) => structuredClone(value);
    fail5 = () => Response.json({ ok: false, error: "inspection_forbidden" }, { status: 403 });
    result = (missing) => ({
      ok: true,
      consistency: "incomplete",
      missing,
      booking_id: target.bookingId,
      capacity_released: null,
      financial_claim_released: null
    });
  }
});

// retained-source/workers/tracking/entry_candidate.mjs
init_owned_release_fetch_v1();

// retained-source/workers/tracking/personal-dispatch.mjs
var matches = (row, scope2) => row?.tenant_id === scope2.tenant_id && row?.company_id === scope2.company_id;
var valid = (row, nowMs) => row?.protocol === 1 && Number.isFinite(row.seen_at_ms) && row.seen_at_ms <= nowMs && nowMs < row.valid_until_ms;
function driverDispatchDevices(store, scope2, driverId, nowMs, deviceKey = "") {
  if (!matches(store?.scope, scope2)) return [];
  return Object.values(store.devices || {}).filter((row) => matches(row, scope2) && row.driver_id === driverId && (!deviceKey || row.device_key === deviceKey) && valid(row, nowMs));
}
function frozenRideExecutionIdentityV1(identity, scope2, driverId, vehicleId) {
  if (!identity || identity.tenant_id !== scope2?.tenant_id || identity.company_id !== scope2?.company_id || !driverId || !vehicleId || identity.driver_id !== driverId || identity.vehicle_id !== vehicleId) return null;
  const base = { tenant_id: scope2.tenant_id, company_id: scope2.company_id, driver_id: driverId, vehicle_id: vehicleId };
  if (identity.kind === "personal_driver_session") {
    if (identity.duty_id != null || typeof identity.acceptance_id !== "string" || !/^acceptance:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(identity.acceptance_id)) return null;
    return { ...base, kind: identity.kind, acceptance_id: identity.acceptance_id };
  }
  if (identity.kind != null || identity.acceptance_id != null || typeof identity.duty_id !== "string" || !identity.duty_id) return null;
  return { ...base, duty_id: identity.duty_id };
}
function personalDriverExecutionV1({ input, devices, duty, offer, nowMs = Date.now() }) {
  const a = input?.personal_execution_auth;
  if (a?.source !== "booking_personal_driver_session_v1" || a.tenant_id !== input.tenant_id || a.company_id !== input.company_id || a.driver_id !== input.driver_id || a.vehicle_id !== input.vehicle_id || a.device_key !== input.device_key || !Number.isFinite(a.session_expires_ms) || a.session_expires_ms <= nowMs) return null;
  const registered = driverDispatchDevices(devices, input, input.driver_id, nowMs, input.device_key);
  if (registered.length !== 1 || registered[0].vehicle_device_id) return null;
  if (duty?.duties?.some((d) => d.ended_at_ms === null && (d.driver_id === input.driver_id || d.vehicle_id === input.vehicle_id))) return null;
  if (!offer || offer.tenant_id !== input.tenant_id || offer.company_id !== input.company_id || offer.offer_id !== input.offer_id || offer.version !== input.version || offer.human_acceptance_required !== true || !offer.claims?.some((c) => c.driver_id === input.driver_id && c.vehicle_id === input.vehicle_id)) return null;
  const previous = offer.receipts?.[input.driver_id]?.execution_identity;
  if (previous) return frozenRideExecutionIdentityV1(previous, input, input.driver_id, input.vehicle_id);
  return {
    tenant_id: input.tenant_id,
    company_id: input.company_id,
    driver_id: input.driver_id,
    vehicle_id: input.vehicle_id,
    kind: "personal_driver_session",
    acceptance_id: "acceptance:" + crypto.randomUUID()
  };
}

// retained-source/workers/tracking/entry_candidate.mjs
var deny3 = (error) => ({ ok: false, error });
var sameScope4 = (a, b) => a?.tenant_id === b?.tenant_id && a?.company_id === b?.company_id;
var id3 = (value) => typeof value === "string" && value.trim() && value.length <= 160;
function applyVehicleDutyCommand2(state, command, actor) {
  if (!actor?.tenant_id || !actor?.company_id || !id3(actor.driver_id)) return deny3("driver_auth_required");
  if (!sameScope4(command, actor) || state && !sameScope4(state, actor)) return deny3("duty_scope_mismatch");
  if (!["start", "pause", "resume", "end"].includes(command?.action) || !id3(command?.command_id) || !id3(command?.vehicle_id) || !id3(command?.duty_id) || !Number.isSafeInteger(command?.at_ms) || command.at_ms < 0) return deny3("duty_command_invalid");
  const current = state ?? { tenant_id: actor.tenant_id, company_id: actor.company_id, version: 0, duties: [], receipts: [] };
  const fingerprint2 = JSON.stringify([command.action, command.vehicle_id, command.duty_id, command.at_ms, actor.driver_id]);
  const receipt = current.receipts.find((row) => row.command_id === command.command_id);
  if (receipt) return receipt.fingerprint === fingerprint2 ? { ok: true, state: current, replay: true } : deny3("duty_command_conflict");
  if (command.expected_version !== current.version) return deny3("duty_version_conflict");
  const active2 = current.duties.filter((row) => row.ended_at_ms === null);
  let duties;
  if (command.action === "start") {
    if (current.duties.some((row) => row.duty_id === command.duty_id)) return deny3("duty_id_conflict");
    if (active2.some((row) => row.vehicle_id === command.vehicle_id)) return deny3("vehicle_duty_conflict");
    if (active2.some((row) => row.driver_id === actor.driver_id)) return deny3("driver_duty_conflict");
    duties = [...current.duties, {
      duty_id: command.duty_id,
      driver_id: actor.driver_id,
      vehicle_id: command.vehicle_id,
      ...id3(actor.vehicle_device_id) ? { vehicle_device_id: actor.vehicle_device_id } : {},
      started_at_ms: command.at_ms,
      ended_at_ms: null,
      paused_at_ms: null,
      pause_intervals: []
    }];
  } else {
    const duty = active2.find((row) => row.duty_id === command.duty_id && row.vehicle_id === command.vehicle_id && row.driver_id === actor.driver_id);
    if (!duty) return deny3("duty_not_owned");
    const latest = duty.paused_at_ms ?? duty.pause_intervals.at(-1)?.end_ms ?? duty.started_at_ms;
    if (command.at_ms < latest) return deny3("duty_time_conflict");
    if (command.action === "pause" && duty.paused_at_ms !== null) return deny3("duty_already_paused");
    if (command.action === "resume" && duty.paused_at_ms === null) return deny3("duty_not_paused");
    const next = { ...duty, pause_intervals: [...duty.pause_intervals] };
    if (command.action === "pause") next.paused_at_ms = command.at_ms;
    else {
      if (duty.paused_at_ms !== null) next.pause_intervals.push({ start_ms: duty.paused_at_ms, end_ms: command.at_ms });
      next.paused_at_ms = null;
      if (command.action === "end") next.ended_at_ms = command.at_ms;
    }
    duties = current.duties.map((row) => row.duty_id === next.duty_id ? next : row);
  }
  return { ok: true, replay: false, state: {
    ...current,
    version: current.version + 1,
    duties,
    receipts: [...current.receipts, { command_id: command.command_id, fingerprint: fingerprint2 }]
  } };
}
function dutyForRideExecution2(state, actor, vehicleId) {
  if (!actor?.driver_id || !sameScope4(state, actor)) return deny3("driver_auth_required");
  const matches32 = state.duties.filter((row) => row.driver_id === actor.driver_id && row.vehicle_id === vehicleId && row.ended_at_ms === null);
  if (matches32.length !== 1 || matches32[0].paused_at_ms !== null) return deny3("active_duty_required");
  const duty = matches32[0];
  return { ok: true, execution_identity: Object.freeze({
    tenant_id: actor.tenant_id,
    company_id: actor.company_id,
    driver_id: duty.driver_id,
    vehicle_id: duty.vehicle_id,
    duty_id: duty.duty_id
  }) };
}
function completedDutySummary2(duty) {
  if (duty?.ended_at_ms == null) return deny3("duty_not_completed");
  const elapsed_ms = duty.ended_at_ms - duty.started_at_ms;
  const pause_ms = duty.pause_intervals.reduce((total, row) => total + row.end_ms - row.start_ms, 0);
  return {
    ok: true,
    driver_id: duty.driver_id,
    vehicle_id: duty.vehicle_id,
    duty_id: duty.duty_id,
    elapsed_ms,
    pause_ms,
    duty_ms: elapsed_ms - pause_ms
  };
}
var VEHICLE_DUTY_STATE_KEY2 = "vehicle_duty_active_v1";
var VEHICLE_DUTY_PROJECTION_KEY2 = "vehicle_duty_projection_v1";
var encode2 = (value) => encodeURIComponent(value);
var receiptKey = (id22) => `vehicle_duty_command_v1:${encode2(id22)}`;
var archiveKey = (id22) => `vehicle_duty_archive_v1:${encode2(id22)}`;
var fingerprint = (command, actor, audit) => JSON.stringify([
  command.action,
  command.vehicle_id,
  command.duty_id,
  command.expected_version,
  actor.driver_id,
  ...audit ? [audit.role, audit.company_id, audit.reason, audit.device_id] : []
]);
async function vehicleDutyCommandReplay2(storage, command, actor, { recoveryAudit } = {}) {
  const state = await storage.get(VEHICLE_DUTY_STATE_KEY2);
  if (state && (state.tenant_id !== actor.tenant_id || state.company_id !== actor.company_id)) return { ok: false, error: "duty_scope_mismatch" };
  if (typeof command?.command_id !== "string" || !command.command_id.trim() || command.command_id.length > 160) return { ok: false, error: "duty_command_invalid" };
  const receipt = await storage.get(receiptKey(command.command_id));
  if (!receipt) return null;
  return receipt.fingerprint === fingerprint(command, actor, recoveryAudit) ? { ok: true, replay: true, version: receipt.version, duty: receipt.duty } : { ok: false, error: "duty_command_conflict" };
}
async function persistVehicleDutyCommand2(storage, command, actor, { projectAvailability = false, recoveryAudit } = {}) {
  if (!storage?.transaction) return { ok: false, error: "duty_transaction_unavailable" };
  return storage.transaction(async (tx) => {
    if (actor?.vehicle_device_id && !recoveryAudit) {
      const scope2 = await tx.get("vehicle_device_scope_v1");
      const device = await tx.get(`vehicle_device_v1:${actor.vehicle_device_id}`);
      if (scope2?.tenant_id !== actor.tenant_id || scope2?.company_id !== actor.company_id || !device || device.revoked || device.expires_at_ms <= Date.now() || device.vehicle_id !== command.vehicle_id) return { ok: false, error: "vehicle_device_auth_required" };
    }
    const state = await tx.get(VEHICLE_DUTY_STATE_KEY2);
    if (!actor?.tenant_id || !actor?.company_id || !actor?.driver_id || command?.tenant_id !== actor.tenant_id || command?.company_id !== actor.company_id || state && (state.tenant_id !== actor.tenant_id || state.company_id !== actor.company_id)) {
      return { ok: false, error: "duty_scope_mismatch" };
    }
    if (typeof command?.command_id !== "string" || !command.command_id.trim() || command.command_id.length > 160) return { ok: false, error: "duty_command_invalid" };
    const receipt = await tx.get(receiptKey(command.command_id));
    if (receipt) return receipt.fingerprint === fingerprint(command, actor, recoveryAudit) ? { ok: true, replay: true, version: receipt.version, duty: receipt.duty } : { ok: false, error: "duty_command_conflict" };
    if (projectAvailability && await tx.get(VEHICLE_DUTY_PROJECTION_KEY2)) return { ok: false, error: "duty_projection_pending" };
    if (command.action === "start" && await tx.get(archiveKey(command.duty_id))) return { ok: false, error: "duty_id_conflict" };
    const decision = applyVehicleDutyCommand2(state, command, actor);
    if (!decision.ok) return decision;
    let duty = decision.state.duties.find((row) => row.duty_id === command.duty_id);
    if (recoveryAudit) duty = { ...duty, recovery: { ...recoveryAudit, at_ms: command.at_ms } };
    const next = { ...decision.state, receipts: [], duties: decision.state.duties.filter((row) => row.ended_at_ms === null) };
    if (duty.ended_at_ms !== null) {
      const archived = { ...duty, tenant_id: actor.tenant_id, company_id: actor.company_id, summary: completedDutySummary2(duty) };
      await tx.put(archiveKey(duty.duty_id), archived);
      await tx.put(`vehicle_duty_driver_v1:${encode2(actor.driver_id)}:${String(duty.started_at_ms).padStart(16, "0")}:${encode2(duty.duty_id)}`, { archive_key: archiveKey(duty.duty_id) });
    }
    const result2 = { ok: true, replay: false, version: next.version, duty };
    await tx.put(VEHICLE_DUTY_STATE_KEY2, next);
    if (projectAvailability) await tx.put(VEHICLE_DUTY_PROJECTION_KEY2, {
      tenant_id: actor.tenant_id,
      company_id: actor.company_id,
      driver_id: actor.driver_id,
      vehicle_id: duty.vehicle_id,
      duty_id: duty.duty_id,
      version: next.version,
      action: command.action,
      at_ms: command.at_ms
    });
    await tx.put(receiptKey(command.command_id), { fingerprint: fingerprint(command, actor, recoveryAudit), version: next.version, duty });
    return result2;
  });
}
async function readVehicleDutyHistory2(storage, scope2, driverId, { limit: limit2 = 50, cursor = "" } = {}) {
  if (!scope2?.tenant_id || !scope2?.company_id || typeof driverId !== "string" || !driverId.trim()) return { ok: false, error: "duty_scope_required" };
  const state = await storage.get(VEHICLE_DUTY_STATE_KEY2);
  if (state && (state.tenant_id !== scope2.tenant_id || state.company_id !== scope2.company_id)) return { ok: false, error: "duty_scope_mismatch" };
  const prefix = `vehicle_duty_driver_v1:${encode2(driverId)}:`;
  if (cursor && !cursor.startsWith(prefix)) return { ok: false, error: "duty_cursor_invalid" };
  const count = Math.max(1, Math.min(100, Number.isSafeInteger(limit2) ? limit2 : 50));
  const rows2 = await storage.list({ prefix, limit: count + 1, ...cursor ? { startAfter: cursor } : {} });
  const entries = [...rows2.entries()];
  const items = [];
  for (const [, index] of entries.slice(0, count)) {
    const duty = await storage.get(index.archive_key);
    if (!duty || duty.tenant_id !== scope2.tenant_id || duty.company_id !== scope2.company_id || duty.driver_id !== driverId) return { ok: false, error: "duty_history_inconsistent" };
    items.push(duty);
  }
  return { ok: true, items, cursor: entries.length > count ? entries[count - 1][0] : null };
}
var validId = (value) => typeof value === "string" && /^[a-zA-Z0-9_.-]{1,96}$/.test(value);
var hash3 = (value) => typeof value === "string" && /^[a-f0-9]{64}$/.test(value);
var denied = (error) => ({ ok: false, error });
async function vehicleDeviceCommand2(storage, input, nowMs) {
  if (!validId(input?.tenant_id) || !validId(input?.company_id) || !Number.isSafeInteger(nowMs)) return denied("vehicle_device_invalid");
  return storage.transaction(async (tx) => {
    const scopeKey = "vehicle_device_scope_v1";
    const scope2 = await tx.get(scopeKey);
    if (scope2 && (scope2.tenant_id !== input.tenant_id || scope2.company_id !== input.company_id)) return denied("vehicle_device_scope_mismatch");
    if (["create_transition", "transition"].includes(input.action)) {
      if (!scope2 || !["switch", "unlink"].includes(input.operation) || !validId(input.device_id) || !validId(input.challenge_id) || !hash3(input.pairing_hash)) return denied("vehicle_device_transition_invalid");
      const deviceKey = `vehicle_device_v1:${input.device_id}`;
      const device2 = await tx.get(deviceKey);
      const grantKey3 = `vehicle_device_transition_v1:${input.challenge_id}`;
      if (input.action === "create_transition") {
        if (input.role !== "company_admin") return denied("vehicle_device_admin_required");
        if (!device2 || device2.revoked || device2.expires_at_ms <= nowMs) return denied("vehicle_device_auth_required");
        if (input.operation === "switch" && (!validId(input.vehicle_id) || input.vehicle_id === device2.vehicle_id)) return denied("vehicle_device_target_invalid");
        if (await tx.get(grantKey3)) return denied("vehicle_device_challenge_conflict");
        const grant2 = {
          operation: input.operation,
          device_id: input.device_id,
          old_vehicle_id: device2.vehicle_id,
          vehicle_id: input.operation === "switch" ? input.vehicle_id : null,
          pairing_hash: input.pairing_hash,
          expires_at_ms: nowMs + 3e5,
          consumed: false
        };
        await tx.put(grantKey3, grant2);
        return { ok: true, expires_at_ms: grant2.expires_at_ms };
      }
      const grant = await tx.get(grantKey3);
      if (!grant || grant.operation !== input.operation || grant.device_id !== input.device_id || grant.pairing_hash !== input.pairing_hash || !hash3(input.device_token_hash) || !device2 || device2.token_hash !== input.device_token_hash || device2.vehicle_id !== grant.old_vehicle_id) return denied("vehicle_device_transition_auth_required");
      if (input.operation === "switch" && (!validId(input.replacement_device_id) || input.replacement_device_id === input.device_id || !hash3(input.replacement_token_hash) || input.vehicle_id !== grant.vehicle_id)) return denied("vehicle_device_transition_invalid");
      const fingerprint2 = JSON.stringify([
        input.operation,
        input.device_id,
        input.device_token_hash,
        input.replacement_device_id ?? null,
        input.replacement_token_hash ?? null
      ]);
      if (grant.consumed) return grant.fingerprint === fingerprint2 ? grant.result : denied("vehicle_device_transition_replay_conflict");
      if (grant.expires_at_ms <= nowMs || device2.revoked || device2.expires_at_ms <= nowMs) return denied("vehicle_device_transition_expired");
      const vehicles = new Set([device2.vehicle_id, grant.vehicle_id].filter(Boolean));
      const duty = await tx.get("vehicle_duty_active_v1");
      if (duty && (duty.tenant_id !== input.tenant_id || duty.company_id !== input.company_id || !Array.isArray(duty.duties))) return denied("vehicle_device_operational_state_invalid");
      if (duty?.duties.some((row) => vehicles.has(row.vehicle_id) && row.ended_at_ms == null)) return denied("active_duty_blocks_device_change");
      if (await tx.get("vehicle_duty_projection_v1")) return denied("duty_projection_pending");
      const capacity = await readCapacitySnapshot2(tx);
      const capacityScope = capacity.scope || capacity.baseline;
      if (capacityScope && (capacityScope.tenant_id !== input.tenant_id || capacityScope.company_id !== input.company_id)) return denied("vehicle_device_scope_mismatch");
      const matches4 = (row) => vehicles.has(row?.vehicle_id);
      const direct = await tx.get("direct_occupancy_active_v1");
      if (Object.values(capacity.claims || {}).some(matches4) || Object.values(capacity.direct_holds || {}).some(matches4) || Object.values(direct || {}).some(matches4) || Object.values(capacity.offers || {}).some((row) => matches4(row) && !["cancelled", "expired", "aborted", "superseded"].includes(row.state))) return denied("active_operation_blocks_device_change");
      const newKey = `vehicle_device_v1:${input.replacement_device_id}`;
      if (input.operation === "switch" && await tx.get(newKey)) return denied("vehicle_device_id_conflict");
      const leases = await tx.get("dispatch_devices_v1");
      if (leases && (leases.scope?.tenant_id !== input.tenant_id || leases.scope?.company_id !== input.company_id)) return denied("vehicle_device_scope_mismatch");
      if (Object.values(leases?.devices || {}).some((row) => vehicles.has(row.vehicle_id) && row.vehicle_device_id !== input.device_id && row.valid_until_ms > nowMs)) return denied("active_operation_blocks_device_change");
      const result2 = {
        ok: true,
        operation: input.operation,
        revoked_device_id: input.device_id,
        ...input.operation === "switch" ? {
          device_id: input.replacement_device_id,
          vehicle_id: grant.vehicle_id,
          expires_at_ms: nowMs + 90 * 864e5
        } : {}
      };
      await tx.put(deviceKey, { ...device2, revoked: true });
      if (input.operation === "switch") await tx.put(newKey, {
        device_id: result2.device_id,
        vehicle_id: result2.vehicle_id,
        token_hash: input.replacement_token_hash,
        expires_at_ms: result2.expires_at_ms,
        revoked: false
      });
      if (leases) await tx.put("dispatch_devices_v1", { ...leases, devices: Object.fromEntries(
        Object.entries(leases.devices || {}).filter(([, row]) => row.vehicle_device_id !== input.device_id)
      ) });
      await tx.put(grantKey3, { ...grant, consumed: true, fingerprint: fingerprint2, result: result2 });
      return result2;
    }
    if (!scope2) await tx.put(scopeKey, { tenant_id: input.tenant_id, company_id: input.company_id });
    if (input.action === "list") {
      if (input.role !== "company_admin") return denied("vehicle_device_admin_required");
      if (!validId(input.vehicle_id)) return denied("vehicle_device_invalid");
      const prefix = "vehicle_device_v1:";
      if (input.cursor != null && (typeof input.cursor !== "string" || !input.cursor.startsWith(prefix) || !validId(input.cursor.slice(prefix.length)))) return denied("vehicle_device_cursor_invalid");
      const rows2 = [...(await tx.list({
        prefix,
        limit: 51,
        ...input.cursor ? { startAfter: input.cursor } : {}
      })).entries()];
      const items = [];
      for (const [, device2] of rows2.slice(0, 50)) {
        if (device2.vehicle_id !== input.vehicle_id) continue;
        items.push({
          device_id: device2.device_id,
          vehicle_id: device2.vehicle_id,
          expires_at_ms: device2.expires_at_ms,
          revoked: device2.revoked === true,
          status: device2.revoked ? "revoked" : device2.expires_at_ms <= nowMs ? "expired" : "paired"
        });
      }
      return { ok: true, vehicle_id: input.vehicle_id, items, cursor: rows2.length > 50 ? rows2[49][0] : null };
    }
    if (input.action === "create") {
      if (input.role !== "company_admin") return denied("vehicle_device_admin_required");
      if (!validId(input.vehicle_id) || !validId(input.challenge_id) || !hash3(input.pairing_hash)) return denied("vehicle_device_invalid");
      const key3 = `vehicle_device_challenge_v1:${input.challenge_id}`;
      if (await tx.get(key3)) return denied("vehicle_device_challenge_conflict");
      await tx.put(key3, { vehicle_id: input.vehicle_id, pairing_hash: input.pairing_hash, expires_at_ms: nowMs + 3e5, consumed: false });
      return { ok: true, expires_at_ms: nowMs + 3e5 };
    }
    if (input.action === "redeem") {
      if (!validId(input.challenge_id) || !validId(input.device_id) || !hash3(input.pairing_hash) || !hash3(input.device_token_hash)) return denied("vehicle_device_invalid");
      const key3 = `vehicle_device_challenge_v1:${input.challenge_id}`;
      const challenge = await tx.get(key3);
      if (!challenge || challenge.consumed || challenge.expires_at_ms <= nowMs || challenge.pairing_hash !== input.pairing_hash) return denied("vehicle_device_pairing_invalid");
      const deviceKey = `vehicle_device_v1:${input.device_id}`;
      if (await tx.get(deviceKey)) return denied("vehicle_device_id_conflict");
      const device2 = {
        device_id: input.device_id,
        vehicle_id: challenge.vehicle_id,
        token_hash: input.device_token_hash,
        expires_at_ms: nowMs + 90 * 864e5,
        revoked: false
      };
      await tx.put(key3, { ...challenge, consumed: true });
      await tx.put(deviceKey, device2);
      return { ok: true, device_id: device2.device_id, vehicle_id: device2.vehicle_id, expires_at_ms: device2.expires_at_ms };
    }
    if (!validId(input.device_id)) return denied("vehicle_device_invalid");
    const key2 = `vehicle_device_v1:${input.device_id}`;
    const device = await tx.get(key2);
    if (input.action === "revoke") {
      if (input.role !== "company_admin") return denied("vehicle_device_admin_required");
      if (!device) return denied("vehicle_device_not_found");
      if (input.vehicle_id != null && input.vehicle_id !== device.vehicle_id) return denied("vehicle_device_vehicle_mismatch");
      await tx.put(key2, { ...device, revoked: true });
      const leases = await tx.get("dispatch_devices_v1");
      if (leases?.scope?.tenant_id === input.tenant_id && leases.scope.company_id === input.company_id) {
        await tx.put("dispatch_devices_v1", { ...leases, devices: Object.fromEntries(
          Object.entries(leases.devices || {}).filter(([, lease]) => lease.vehicle_device_id !== input.device_id)
        ) });
      }
      return { ok: true };
    }
    if (input.action !== "authenticate" || !hash3(input.device_token_hash) || !device || device.revoked || device.expires_at_ms <= nowMs || device.token_hash !== input.device_token_hash) return denied("vehicle_device_auth_required");
    return { ok: true, device_id: device.device_id, vehicle_id: device.vehicle_id };
  });
}
function createPerDriverState2(storage, legacyKey, prefix, { extract: extract2 = (value) => value, wrap = (value) => value, onWrite } = {}) {
  const partitioned = typeof storage.list === "function" && typeof storage.transaction === "function";
  let rows2, metadata, loading;
  const key2 = (id22) => prefix + encodeURIComponent(id22);
  async function load() {
    if (rows2) return rows2;
    loading ||= (async () => {
      const raw = await storage.get(legacyKey);
      if (!partitioned) {
        rows2 = extract2(raw || {}) || {};
        metadata = { updated_at: raw?.updated_at };
        return rows2;
      }
      if (raw?.format === "per-driver-v2") {
        const recovered = {};
        let startAfter = "";
        for (; ; ) {
          const page = await storage.list({ prefix, startAfter, limit: 1e3 });
          for (const [recordKey, row] of page) recovered[decodeURIComponent(recordKey.slice(prefix.length))] = row;
          if (page.size < 1e3) break;
          startAfter = [...page.keys()].at(-1);
        }
        rows2 = recovered;
        metadata = raw;
        return rows2;
      }
      const legacy = extract2(raw && typeof raw === "object" ? raw : {}) || {};
      const marker = { format: "per-driver-v2", revision: 1, ...raw?.updated_at ? { updated_at: raw.updated_at } : {} };
      const records = Object.entries(legacy);
      if (raw == null && !records.length) {
        rows2 = {};
        metadata = marker;
        return rows2;
      }
      const progressKey = legacyKey + ":adoption-v2";
      const digestBytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(JSON.stringify(legacy)));
      const digest5 = [...new Uint8Array(digestBytes)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
      const progress = await storage.get(progressKey);
      if (progress && (progress.digest !== digest5 || !Number.isSafeInteger(progress.offset) || progress.offset < 0 || progress.offset > records.length)) throw Error("driver_state_adoption_generation_changed");
      for (let offset = progress?.offset || 0; offset < records.length; offset += 126) {
        await storage.transaction(async (tx) => {
          for (const [id22, row] of records.slice(offset, offset + 126)) await tx.put(key2(id22), row);
          await tx.put(progressKey, { digest: digest5, offset: Math.min(records.length, offset + 126) });
        });
      }
      await storage.transaction(async (tx) => {
        await tx.put(legacyKey, marker);
        await tx.delete(progressKey);
      });
      rows2 = legacy;
      metadata = marker;
      return rows2;
    })().catch((error) => {
      loading = null;
      throw error;
    });
    return loading;
  }
  return {
    load,
    get revision() {
      return metadata?.revision || 0;
    },
    get partitioned() {
      return partitioned;
    },
    get metadata() {
      return metadata;
    },
    async prune(predicate, limit2 = 127) {
      if (!Number.isInteger(limit2) || limit2 < 1 || limit2 > 127) throw Error("driver_prune_limit_invalid");
      await load();
      const ids = [];
      for (const [id22, row] of Object.entries(rows2)) {
        if (predicate(row, id22)) ids.push(id22);
        if (ids.length >= limit2) break;
      }
      if (!ids.length) return { removed: 0, deleted: [], rows: rows2 };
      const next = { ...metadata, revision: (metadata.revision || 0) + 1 };
      if (partitioned) await storage.transaction(async (tx) => {
        for (const id22 of ids) await tx.delete(key2(id22));
        await tx.put(legacyKey, next);
      });
      else {
        const remaining = { ...rows2 };
        for (const id22 of ids) delete remaining[id22];
        await storage.put(legacyKey, wrap(remaining, next));
      }
      for (const id22 of ids) delete rows2[id22];
      metadata = next;
      return { removed: ids.length, deleted: ids, rows: rows2 };
    },
    async clear(fields = {}) {
      await load();
      const next = { ...metadata, ...fields, revision: (metadata.revision || 0) + 1 };
      if (partitioned) {
        const ids = Object.keys(rows2);
        for (let offset = 0; offset < ids.length; offset += 127) await storage.transaction(async (tx) => {
          for (const id22 of ids.slice(offset, offset + 127)) await tx.delete(key2(id22));
        });
        await storage.transaction((tx) => tx.put(legacyKey, next));
      } else await storage.put(legacyKey, wrap({}, next));
      rows2 = {};
      metadata = next;
      return rows2;
    },
    async write(id22, row, fields = {}) {
      await load();
      if (!partitioned) {
        const next2 = { ...rows2 };
        if (row == null) delete next2[id22];
        else next2[id22] = row;
        await storage.put(legacyKey, wrap(next2, { ...metadata, ...fields }));
        rows2 = next2;
        metadata = { ...metadata, ...fields };
        return rows2;
      }
      const next = { ...metadata, ...fields, revision: metadata.revision + 1 };
      await storage.transaction(async (tx) => {
        if (row == null) await tx.delete(key2(id22));
        else await tx.put(key2(id22), row);
        await tx.put(legacyKey, next);
      });
      if (row == null) delete rows2[id22];
      else rows2[id22] = row;
      metadata = next;
      if (onWrite) await onWrite(
        row,
        row == null ? 1 : 2,
        new TextEncoder().encode(JSON.stringify(next)).byteLength + (row == null ? 0 : new TextEncoder().encode(JSON.stringify(row)).byteLength)
      );
      return rows2;
    }
  };
}
var finite4 = (p) => p && Number.isFinite(p.latitude) && Number.isFinite(p.longitude) && Math.abs(p.latitude) <= 90 && Math.abs(p.longitude) <= 180;
function sphericalDistance(a, b) {
  const rad = Math.PI / 180, dy = (b.latitude - a.latitude) * rad, dx = (b.longitude - a.longitude) * rad;
  const h = Math.sin(dy / 2) ** 2 + Math.cos(a.latitude * rad) * Math.cos(b.latitude * rad) * Math.sin(dx / 2) ** 2;
  return 63710088e-1 * 2 * Math.asin(Math.sqrt(Math.min(1, Math.max(0, h))));
}
function createActiveSpatialIndex2(scope2, { maxEntries = 4096, cellDegrees = 0.01, freshnessMs = 18e4 } = {}) {
  if (!scope2?.tenant_id || !scope2.company_id || !Number.isInteger(maxEntries) || maxEntries < 1 || maxEntries > 16384 || !(cellDegrees > 0 && cellDegrees <= 1) || !(freshnessMs > 0)) throw Error("spatial_index_options_invalid");
  const rows2 = /* @__PURE__ */ new Map(), cells = /* @__PURE__ */ new Map();
  let overflow = false;
  const cell = (p) => `${Math.floor(p.latitude / cellDegrees)}:${Math.floor(p.longitude / cellDegrees)}`;
  const remove = (id22) => {
    const old = rows2.get(id22);
    if (!old) return;
    const set = cells.get(old.cell);
    set.delete(id22);
    if (!set.size) cells.delete(old.cell);
    rows2.delete(id22);
  };
  const update2 = (row, nowMs = Date.now()) => {
    const id22 = row?.driver_id;
    if (typeof id22 !== "string" || !id22 || id22.length > 128) return false;
    if (row.tenant_id !== scope2.tenant_id || row.company_id !== scope2.company_id) return false;
    const at = Date.parse(row.position_captured_at || row.captured_at || row.updated_at || row.last_seen_at || "");
    const old = rows2.get(id22);
    if (old && Number.isFinite(at) && at < old.at) return false;
    if (!finite4(row) || !row.vehicle_id || !Number.isFinite(at) || nowMs - at > freshnessMs || at > nowMs + 12e4 || row.location_withdrawn === true || row.availability_status === "offline" || row.availability_status === "paused" || row.is_active === false) {
      remove(id22);
      return true;
    }
    if (!old && rows2.size >= maxEntries) {
      overflow = true;
      return false;
    }
    const key2 = cell(row);
    if (old?.cell !== key2) {
      remove(id22);
      if (!cells.has(key2)) cells.set(key2, /* @__PURE__ */ new Set());
      cells.get(key2).add(id22);
    }
    rows2.set(id22, { ...row, at, cell: key2 });
    return true;
  };
  return {
    update: update2,
    remove,
    get size() {
      return rows2.size;
    },
    get cellCount() {
      return cells.size;
    },
    rebuild(values, nowMs = Date.now()) {
      rows2.clear();
      cells.clear();
      overflow = false;
      for (const row of values) update2(row, nowMs);
    },
    ordered(target2, nowMs = Date.now()) {
      if (!finite4(target2)) return { rows: [], complete: false, cells_visited: 0 };
      const visited = [];
      for (const [key2, ids] of cells) {
        const candidates = [...ids].map((id22) => rows2.get(id22)).filter((row) => nowMs - row.at <= freshnessMs);
        if (candidates.length) visited.push({ key: key2, rows: candidates, distance: Math.min(...candidates.map((row) => sphericalDistance(row, target2))) });
      }
      visited.sort((a, b) => a.distance - b.distance || a.key.localeCompare(b.key));
      const ordered = visited.flatMap((cell2) => cell2.rows).sort((a, b) => sphericalDistance(a, target2) - sphericalDistance(b, target2) || a.driver_id.localeCompare(b.driver_id));
      return { rows: ordered, complete: !overflow, cells_visited: visited.length };
    }
  };
}
var EARTH_METERS = 6371e3;
var radians = (value) => value * Math.PI / 180;
function point(value) {
  if (value?.latitude == null || value?.longitude == null) return null;
  const latitude = Number(value?.latitude), longitude = Number(value?.longitude);
  return Number.isFinite(latitude) && Number.isFinite(longitude) && Math.abs(latitude) <= 90 && Math.abs(longitude) <= 180 ? { latitude, longitude } : null;
}
function distance(a, b) {
  const lat = radians(b.latitude - a.latitude), lon = radians(b.longitude - a.longitude);
  const h = Math.sin(lat / 2) ** 2 + Math.cos(radians(a.latitude)) * Math.cos(radians(b.latitude)) * Math.sin(lon / 2) ** 2;
  return 2 * EARTH_METERS * Math.asin(Math.min(1, Math.sqrt(h)));
}
function routeDistance(origin, route) {
  const coordinates = Array.isArray(route?.coordinates) ? route.coordinates : null;
  if (!Array.isArray(coordinates) || coordinates.length < 2) return Infinity;
  const factor = Math.cos(radians(origin.latitude)), scale = EARTH_METERS * Math.PI / 180;
  const xy = (row) => [(row.longitude - origin.longitude) * scale * factor, (row.latitude - origin.latitude) * scale];
  let best = Infinity;
  for (let i = 1; i < coordinates.length; i++) {
    const a = xy(coordinates[i - 1]), b = xy(coordinates[i]), dx = b[0] - a[0], dy = b[1] - a[1];
    const t = Math.max(0, Math.min(1, -(a[0] * dx + a[1] * dy) / (dx * dx + dy * dy || 1)));
    best = Math.min(best, Math.hypot(a[0] + t * dx, a[1] + t * dy));
  }
  return best;
}
function createAdaptiveEtaCache2(fetcher, now = () => Date.now(), { maxEntries = 128, maxInflight = 32, maxBytes = 4 * 1024 * 1024 } = {}) {
  const entries = /* @__PURE__ */ new Map(), inflight = /* @__PURE__ */ new Map();
  let storedBytes = 0;
  const remove = (key2) => {
    const entry = entries.get(key2);
    if (entry) storedBytes -= entry.bytes;
    entries.delete(key2);
  };
  const limits = { entries: Math.max(1, maxEntries), inflight: Math.max(1, maxInflight), bytes: Math.max(1, maxBytes) };
  function publicValue(entry, origin, cache) {
    const age = Math.max(0, (now() - entry.at) / 1e3);
    return {
      ...entry.value,
      cache,
      estimated: age > 0 || cache === "hit",
      age_seconds: age,
      refreshed_at: new Date(entry.at).toISOString(),
      position_basis: origin,
      provider_origin: entry.origin,
      // No time/distance extrapolation: traffic is not uniform along a route.
      source: "mapbox/driving-traffic",
      estimate_source: age > 0 || cache === "hit" ? "cached_provider_route" : "provider",
      provider_source: "mapbox/driving-traffic",
      route_age_seconds: age,
      valid_until: new Date(entry.at + entry.refreshMs).toISOString()
    };
  }
  return {
    diagnostics: () => ({ entries: entries.size, inflight: inflight.size, bytes: storedBytes }),
    async resolve({ origin: rawOrigin, destination: rawDestination, target: target2, context: context3 = {}, observability }) {
      const origin = point(rawOrigin), destination = point(rawDestination);
      if (!origin || !destination) return null;
      if (!context3.tenant_id || !context3.company_id || !context3.booking_id) throw Error("customer_eta_scope_required");
      const key2 = JSON.stringify([
        context3.tenant_id,
        context3.company_id,
        context3.booking_id,
        context3.operational_leg || "primary",
        context3.session_id || "",
        context3.assignment_version || "",
        context3.lifecycle_seq || "",
        target2,
        "mapbox/driving-traffic",
        "overview=simplified;geometries=geojson",
        destination.latitude,
        destination.longitude
      ]);
      const at = now();
      const capturedAt = Date.parse(rawOrigin?.captured_at || rawOrigin?.position_captured_at || "");
      const sampleAt = Number.isFinite(capturedAt) ? capturedAt : at;
      for (const [oldKey, entry2] of entries) if (at - entry2.at >= 12e4) remove(oldKey);
      const entry = entries.get(key2);
      let speed = entry?.speed ?? null, motionChanged = false;
      if (entry && sampleAt > entry.observedAt) {
        const elapsed = (sampleAt - entry.observedAt) / 1e3;
        const moved = distance(entry.observedOrigin, origin);
        speed = moved / elapsed;
        motionChanged = entry.speed !== null ? entry.speed > 1 && speed < 0.5 || entry.speed < 0.5 && speed > 2 || Math.abs(speed - entry.speed) > 5 : speed > Math.max(5, entry.value.distance_meters / Math.max(1, entry.value.duration_seconds) * 2);
        entry.observedAt = sampleAt;
        entry.observedOrigin = origin;
        entry.speed = speed;
      }
      const refreshMs = speed === null || speed < 0.5 ? 6e4 : speed < 4 ? 5e4 : 4e4;
      if (entry && at >= entry.at && at - entry.at < refreshMs && !motionChanged && distance(entry.origin, origin) < 1200 && routeDistance(origin, entry.value.route) <= 50) {
        entry.refreshMs = refreshMs;
        entries.delete(key2);
        entries.set(key2, entry);
        return publicValue(entry, origin, "hit");
      }
      if (entry) remove(key2);
      const flightKey = JSON.stringify([key2, origin.latitude, origin.longitude]);
      if (inflight.has(flightKey)) return publicValue(await inflight.get(flightKey), origin, "joined");
      const task = (async () => {
        const value = await fetcher({ origin, destination, target: target2, observability });
        if (!value || !Number.isFinite(value.duration_seconds) || value.duration_seconds < 0) throw Error("customer_eta_invalid");
        const saved = {
          at: now(),
          requestedAt: at,
          origin,
          observedOrigin: origin,
          observedAt: sampleAt,
          speed,
          refreshMs,
          value: { target: target2, duration_seconds: value.duration_seconds, distance_meters: value.distance_meters ?? null, route: value.route ?? null }
        };
        saved.bytes = new TextEncoder().encode(JSON.stringify(saved)).byteLength;
        if (saved.bytes <= limits.bytes && (!entries.has(key2) || entries.get(key2).observedAt <= sampleAt && entries.get(key2).requestedAt <= at)) {
          remove(key2);
          while (entries.size >= limits.entries || storedBytes + saved.bytes > limits.bytes) remove(entries.keys().next().value);
          entries.set(key2, saved);
          storedBytes += saved.bytes;
        }
        return saved;
      })();
      if (inflight.size < limits.inflight) inflight.set(flightKey, task);
      try {
        return publicValue(await task, origin, "miss");
      } finally {
        if (inflight.get(flightKey) === task) inflight.delete(flightKey);
      }
    }
  };
}
var allowed = /* @__PURE__ */ new Set([
  "active_drivers",
  "online_drivers",
  "online_driver_seconds",
  "trips",
  "planner",
  "auto_candidate",
  "next_leg",
  "active_ride_forecast",
  "customer_live_eta",
  "reassignment_retry",
  "provider_calls",
  "cache_hit",
  "cache_miss",
  "cache_joined",
  "workers_requests",
  "kv_reads",
  "kv_writes",
  "kv_lists",
  "kv_deletes",
  "do_requests",
  "storage_reads",
  "storage_writes",
  "storage_bytes",
  "prepare_ms",
  "commit_ms",
  "queue_ms",
  "dispatch_ms",
  "candidate_initial",
  "candidate_active",
  "candidate_cheap",
  "candidate_expansions",
  "candidate_pruned",
  "candidate_evaluated"
]);
var rows = /* @__PURE__ */ new Map();
var hashCache = /* @__PURE__ */ new Map();
var buckets = [1, 5, 10, 25, 50, 100, 250, 500, 1e3, 2e3, 3e3, 5e3, 1e4, 3e4, 6e4, Infinity];
async function scopeHash(scope2) {
  const value = JSON.stringify([scope2?.tenant_id, scope2?.company_id]);
  if (!scope2?.tenant_id || !scope2?.company_id) return null;
  if (!hashCache.has(value)) {
    const digest5 = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
    if (hashCache.size >= 128) hashCache.delete(hashCache.keys().next().value);
    hashCache.set(value, [...new Uint8Array(digest5)].map((v) => v.toString(16).padStart(2, "0")).join("").slice(0, 24));
  }
  return hashCache.get(value);
}
async function emitTenantCostMetric2(env, scope2, name, value = 1) {
  if (env?.TENANT_COST_METRICS_ENABLED !== "1" || !allowed.has(name) || !Number.isFinite(value) || value < 0) return;
  try {
    const hash22 = await scopeHash(scope2);
    if (!hash22) return;
    const minute = Math.floor(Date.now() / 6e4), key2 = hash22 + ":" + minute;
    for (const [old, row2] of rows) if (row2.minute < minute - 4) rows.delete(old);
    if (!rows.has(key2)) {
      if (rows.size >= 128) rows.delete(rows.keys().next().value);
      rows.set(key2, { company_scope_hash: hash22, minute, counters: {}, latency: {} });
    }
    const row = rows.get(key2);
    if (name.endsWith("_ms")) {
      const histogram = row.latency[name] ||= Array(buckets.length).fill(0);
      histogram[buckets.findIndex((limit2) => value <= limit2)]++;
    } else if (name === "active_drivers" || name === "online_drivers") row.counters[name] = value;
    else row.counters[name] = (row.counters[name] || 0) + value;
    if (typeof env.__tenantCostMetricSink === "function") await env.__tenantCostMetricSink({ company_scope_hash: hash22, minute, name, value });
  } catch {
  }
}
var metered2 = Symbol("tenantCostMetered");
var operations = /* @__PURE__ */ new Set(["planner", "auto_candidate", "next_leg", "active_ride_forecast", "reassignment_retry", "customer_live_eta"]);
var profiles = /* @__PURE__ */ new Set(["mapbox/driving", "mapbox/driving-traffic"]);
var scopeHashes = /* @__PURE__ */ new Map();
async function digest3(value) {
  const bytes4 = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(bytes4), (b) => b.toString(16).padStart(2, "0")).join("").slice(0, 24);
}
async function emitRouteMetric(env, context3 = {}, result2 = {}) {
  if (env?.TENANT_COST_METRICS_ENABLED === "1") {
    await emitTenantCostMetric2(env, context3.scope, result2.provider_request === false ? `cache_${result2.cache}` : "provider_calls");
    if (result2.provider_request !== false && operations.has(context3.operation)) await emitTenantCostMetric2(env, context3.scope, context3.operation);
  }
  if (env?.ROUTE_METRICS_ENABLED !== "1") return;
  const configured = Number(env.ROUTE_METRICS_SAMPLE_RATE ?? 1);
  const rate = Number.isFinite(configured) ? Math.min(1, Math.max(0, configured)) : 1;
  if (rate === 0 || Math.random() >= rate) return;
  try {
    const scope2 = context3.scope || {};
    const tenant = String(scope2.tenant_id || ""), company2 = String(scope2.company_id || "");
    const key2 = JSON.stringify([tenant, company2]);
    let hashes = scopeHashes.get(key2);
    if (!hashes) {
      hashes = {
        tenant_hash: tenant ? await digest3(`tenant:${tenant}`) : null,
        company_hash: company2 ? await digest3(`company:${key2}`) : null
      };
      if (scopeHashes.size >= 256) scopeHashes.delete(scopeHashes.keys().next().value);
      scopeHashes.set(key2, hashes);
    }
    const record = {
      event: "route_metric_v1",
      ...hashes,
      operation: operations.has(context3.operation) ? context3.operation : "unclassified",
      source: operations.has(context3.source) ? context3.source : operations.has(context3.operation) ? context3.operation : "unclassified",
      profile: profiles.has(context3.profile) ? context3.profile : "unknown",
      cache: ["hit", "miss", "joined", "bypass"].includes(result2.cache) ? result2.cache : "miss",
      provider_request: result2.provider_request !== false,
      success: result2.success === true,
      http_status: Number.isInteger(result2.http_status) && result2.http_status >= 100 && result2.http_status <= 599 ? result2.http_status : null,
      elapsed_ms: Math.max(0, Math.round(Number(result2.elapsed_ms) || 0)),
      eligible_candidates: Number.isSafeInteger(context3.eligible_candidates) && context3.eligible_candidates >= 0 ? context3.eligible_candidates : null,
      retry_attempt: Number.isSafeInteger(context3.retry_attempt) && context3.retry_attempt >= 0 ? context3.retry_attempt : 0,
      sample_rate: rate
    };
    if (typeof env.__routeMetricSink === "function") await env.__routeMetricSink(record);
    else if (env.TENANT_COST_METRICS_ENABLED !== "1") console.log(`[ROUTE_METRICS] ${JSON.stringify(record)}`);
  } catch {
  }
}
async function measureRouteCall2(env, context3, run) {
  const start = performance.now();
  let httpStatus = null, success = false;
  try {
    const value = await run((status) => {
      httpStatus = status;
    });
    success = true;
    return value;
  } finally {
    await emitRouteMetric(env, context3, {
      success,
      http_status: httpStatus,
      elapsed_ms: performance.now() - start,
      provider_request: true,
      cache: "miss"
    });
  }
}
function dispatchDirectionsUrl(token, from, to, departAt, includeGeometry = false) {
  const path = `${from.longitude},${from.latitude};${to.longitude},${to.latitude}`;
  const depart = departAtIso(departAt);
  const departQuery = depart ? `&depart_at=${encodeURIComponent(depart)}` : "";
  return `https://api.mapbox.com/directions/v5/mapbox/driving-traffic/${path}?overview=${includeGeometry ? "simplified&geometries=geojson" : "false"}${departQuery}&access_token=${encodeURIComponent(token)}`;
}
async function mapboxDispatchRouteEta2(env, args = {}) {
  const { origin, destination, depart_at, includeGeometry = false, observability } = args;
  const token = String(env?.MAPBOX_TOKEN || "").trim();
  if (!token) throw new Error("mapbox_unconfigured");
  const from = point2(origin);
  const to = point2(destination);
  if (!from || !to) throw new Error("mapbox_coordinates");
  const url = dispatchDirectionsUrl(token, from, to, depart_at, includeGeometry);
  return measureRouteCall2(env, { ...observability, profile: "mapbox/driving-traffic" }, async (markStatus) => {
    const response2 = await ownedReleaseFetchV1(url);
    markStatus(response2.status);
    if (!response2.ok) throw new Error("mapbox_http");
    const body = await response2.json();
    const route = body?.routes?.[0];
    const duration = Number(route?.duration);
    const distance2 = Number(route?.distance);
    const typical = Number(route?.duration_typical);
    if (!Number.isFinite(duration)) throw new Error("mapbox_empty");
    return {
      ...includeGeometry ? { route: publicRouteGeometry(route?.geometry) } : {},
      duration_seconds: duration,
      duration_typical_seconds: Number.isFinite(typical) ? typical : null,
      distance_meters: Number.isFinite(distance2) ? distance2 : null
    };
  });
}
function departAtIso(value) {
  if (value == null || value === "") return "";
  const ms = Date.parse(String(value));
  if (!Number.isFinite(ms)) return "";
  return new Date(ms).toISOString();
}
function point2(value) {
  const latitude = Number(value?.latitude ?? value?.lat);
  const longitude = Number(value?.longitude ?? value?.lon ?? value?.lng);
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return null;
  if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) return null;
  return { latitude, longitude };
}
function publicRouteGeometry(geometry) {
  if (geometry?.type !== "LineString" || !Array.isArray(geometry.coordinates) || geometry.coordinates.length < 2 || geometry.coordinates.length > 5e3) return null;
  const points = geometry.coordinates.map((c) => Array.isArray(c) && c.length >= 2 && typeof c[0] === "number" && typeof c[1] === "number" ? point2({ longitude: c[0], latitude: c[1] }) : null);
  return points.every(Boolean) ? { coordinates: points } : null;
}
var VEHICLE_FALLBACK_ASSETS2 = Object.freeze([
  "assets/vehicles/fallback/v1/fluxidi_vehicle_compact_hatchback_v1.webp",
  "assets/vehicles/fallback/v1/fluxidi_vehicle_sedan_v1.webp",
  "assets/vehicles/fallback/v1/fluxidi_vehicle_station_wagon_v1.webp",
  "assets/vehicles/fallback/v1/fluxidi_vehicle_suv_crossover_v1.webp",
  "assets/vehicles/fallback/v1/fluxidi_vehicle_mpv_minivan_v1.webp",
  "assets/vehicles/fallback/v1/fluxidi_vehicle_passenger_minibus_v1.webp",
  "assets/vehicles/fallback/v1/fluxidi_vehicle_premium_limousine_v1.webp",
  "assets/vehicles/fallback/v1/fluxidi_vehicle_wheelchair_accessible_v1.webp",
  "assets/vehicles/fallback/v1/fluxidi_vehicle_stretch_limousine_v1.webp",
  "assets/vehicles/fallback/v1/fluxidi_vehicle_hummer_stretch_v1.webp"
]);
function normalizeVehicleFallbackAsset2(value) {
  const asset = String(value ?? "").trim();
  return VEHICLE_FALLBACK_ASSETS2.includes(asset) ? asset : "";
}
var SNAPSHOT_CONTRACT_VERSION = 1;
var GRANT_ACCESS_TTL_MS = 9e4;
var LIVE_PHASES = /* @__PURE__ */ new Set(["en_route_pickup", "arrived_pickup", "in_progress"]);
var TERMINAL_PHASES2 = /* @__PURE__ */ new Set(["stopped", "completed", "cancelled"]);
var PUBLIC_DRIVER_FIELDS = ["display_name"];
var PUBLIC_VEHICLE_FIELDS = ["label", "color", "license_plate"];
function trackingPhaseForStatus2(status) {
  const token = String(status || "").trim().toLowerCase().replace(/[\s-]+/g, "_");
  if (!token || token === "unassigned" || token === "quoted" || token === "pending") return "unassigned";
  if (token === "assigned" || token === "accepted" || token === "confirmed") return "assigned";
  if (token === "en_route" || token === "en_route_pickup" || token === "on_the_way" || token === "driving_to_pickup") {
    return "en_route_pickup";
  }
  if (token === "arrived_pickup") return "arrived_pickup";
  if (token === "started" || token === "in_progress" || token === "on_trip" || token === "picked_up" || token === "driving") {
    return "in_progress";
  }
  if (token === "stopped" || token === "stop") return "stopped";
  if (token === "completed" || token === "complete") return "completed";
  if (["cancelled", "canceled", "no_show", "rejected", "expired"].includes(token)) return "cancelled";
  return "assigned";
}
function etaTargetForPhase(phase) {
  if (phase === "en_route_pickup") return "pickup";
  if (phase === "in_progress") return "destination";
  return null;
}
function publicDriver2(input) {
  const source = input && typeof input === "object" ? input : {};
  const out = {};
  for (const key2 of PUBLIC_DRIVER_FIELDS) {
    const value = source[key2] ?? source.public_driver?.[key2];
    if (value) out[key2] = String(value).slice(0, 80);
  }
  const photo = publicPhotoUrl(source.photo_url ?? source.public_photo_url ?? source.public_driver?.photo_url);
  if (photo) out.photo_url = photo;
  const contact = source.customer_contact;
  if (contact?.customer_allowed === true && /^\+[1-9][0-9]{6,14}$/.test(String(contact.phone_e164 || "")) && (contact.call_allowed === true || contact.whatsapp_allowed === true)) {
    out.customer_contact = {
      customer_allowed: true,
      phone_e164: contact.phone_e164,
      call_allowed: contact.call_allowed === true,
      whatsapp_allowed: contact.whatsapp_allowed === true
    };
  }
  const average = Number(source.rating_average), count = Number(source.rating_count);
  if (Number.isFinite(average) && average > 0 && average <= 5 && Number.isInteger(count) && count > 0) {
    out.rating_average = average;
    out.rating_count = count;
  }
  return out;
}
function publicPhotoUrl(value) {
  try {
    const url = new URL(String(value ?? ""));
    return url.protocol === "https:" && !url.username && !url.password && url.href.length <= 2048 ? url.href : "";
  } catch {
    return "";
  }
}
function publicVehicle2(input) {
  const source = input && typeof input === "object" ? input : {};
  const assigned = source.assigned_vehicle || source.vehicle || source;
  const out = {};
  for (const key2 of PUBLIC_VEHICLE_FIELDS) {
    const value = assigned[key2] ?? assigned[`vehicle_${key2}`];
    if (value) out[key2] = String(value).slice(0, 80);
  }
  const vehicleId = text(assigned.vehicle_id ?? assigned.vehicleId, 96);
  if (vehicleId) out.vehicle_id = vehicleId;
  const fallbackAsset = normalizeVehicleFallbackAsset2(assigned.fallback_asset ?? assigned.fallbackAsset);
  if (fallbackAsset) out.fallback_asset = fallbackAsset;
  const photo = publicPhotoUrl(assigned.photo_url ?? assigned.public_photo_url);
  if (photo) out.photo_url = photo;
  return out;
}
function publicOperationalRoute2(value) {
  const address = value?.destination_address ?? value?.destination?.address;
  const end = value?.expected_end_iso, updated = value?.updated_at;
  if (typeof address !== "string" || !address.trim() || address.length > 400 || typeof end !== "string" || !Number.isFinite(Date.parse(end))) return null;
  return {
    destination_address: address.trim(),
    expected_end_iso: new Date(end).toISOString(),
    ...typeof updated === "string" && Number.isFinite(Date.parse(updated)) ? { updated_at: new Date(updated).toISOString() } : {}
  };
}
function text(value, max) {
  const raw = String(value ?? "").trim();
  return raw ? raw.slice(0, max) : "";
}
function grantKey2(bookingId, leg) {
  return `${text(bookingId, 96)}|${text(leg, 200) || "primary"}`;
}
function applyCustomerLifecycle2(store, event, nowMs) {
  const result2 = applyScopedCustomerLifecycle(store, event, nowMs);
  if (result2.applied && event?.disable_primary === true && result2.grant && TERMINAL_PHASES2.has(result2.grant.tracking_phase)) {
    const grant = result2.grant;
    grant.revoked_token_hashes = [...new Set([...grant.revoked_token_hashes || [], ...grant.access_token_hashes || [], grant.access_token_hash].filter(Boolean))];
    grant.access_token_hash = "";
    grant.access_token_hashes = [];
  }
  if (result2.applied && event?.disable_primary === true && event.operational_leg && event.operational_leg !== "primary") {
    const key2 = grantKey2(event.booking_id, "primary");
    const old = result2.store.grants[key2];
    result2.store.grants[key2] = {
      ...old,
      leg_scope_retired: true,
      position_allowed: false,
      access_token_hash: "",
      access_token_hashes: [],
      tracking_phase: "stopped"
    };
  }
  return result2;
}
function applyScopedCustomerLifecycle(store, event, nowMs) {
  const next = { grants: { ...store?.grants || {} } };
  const bookingId = text(event?.booking_id, 96);
  const tenantId = text(event?.tenant_id, 80);
  const companyId = text(event?.company_id, 80);
  if (!bookingId || !tenantId || !companyId) {
    return { store: next, applied: false, reason: "identity_missing" };
  }
  const leg = text(event?.operational_leg, 200) || "primary";
  const key2 = grantKey2(bookingId, leg);
  const current = next.grants[key2] || null;
  if (current?.leg_scope_retired) return { store: next, applied: false, confirmed: false, reason: "leg_scope_retired", grant: current };
  const seq = Number(event?.lifecycle_seq);
  if (!Number.isFinite(seq)) {
    return { store: next, applied: false, reason: "lifecycle_seq_required" };
  }
  const kind = text(event?.kind, 20) || "lifecycle";
  const phase = trackingPhaseForStatus2(event?.tracking_phase || event?.booking_status);
  const assignmentVersion = Number(event?.assignment_version);
  const tokenHash = text(event?.access_token_hash, 128);
  if (event?.sync_ok === false) {
    return {
      store: next,
      applied: false,
      confirmed: false,
      reason: "sync_report_ignored",
      grant: current
    };
  }
  if (kind === "session_start" || kind === "session_stop") {
    const sessionId = text(event?.session_id, 128);
    const matches32 = current && current.tenant_id === tenantId && current.company_id === companyId && assignmentVersion > 0 && assignmentVersion === current.assignment_version && text(event?.driver_id, 96) === current.driver_id && sessionId;
    if (!matches32 || kind === "session_start" && seq !== current.lifecycle_seq || kind === "session_stop" && sessionId !== current.session_id) {
      return { store: next, applied: false, confirmed: false, reason: "session_assignment_mismatch", grant: current };
    }
    if (TERMINAL_PHASES2.has(current.tracking_phase)) {
      return { store: next, applied: false, confirmed: kind === "session_stop", reason: "session_already_closed", grant: current };
    }
    const grant2 = { ...current, session_id: sessionId, updated_at: new Date(nowMs).toISOString() };
    if (kind === "session_stop") {
      grant2.tracking_phase = "stopped";
      grant2.position_allowed = false;
      grant2.revoked_token_hashes = [...new Set([
        ...current.revoked_token_hashes || [],
        ...current.access_token_hashes || [],
        current.access_token_hash
      ].filter(Boolean))];
    }
    next.grants[key2] = grant2;
    return { store: next, applied: true, confirmed: true, reason: kind, grant: grant2 };
  }
  if (current && Number.isFinite(assignmentVersion) && assignmentVersion < current.assignment_version) {
    return { store: next, applied: false, confirmed: false, reason: "stale_assignment_version", grant: current };
  }
  if (current && TERMINAL_PHASES2.has(current.tracking_phase) && !(assignmentVersion > current.assignment_version) && !TERMINAL_PHASES2.has(phase)) {
    return { store: next, applied: false, confirmed: false, reason: "session_closed", grant: current };
  }
  if (current && seq < current.lifecycle_seq) {
    return { store: next, applied: false, confirmed: false, reason: "stale_lifecycle_seq", grant: current };
  }
  const terminalCorrection = current && assignmentVersion === current.assignment_version && seq === current.lifecycle_seq && ["completed", "cancelled"].includes(phase) && trackingPhaseForStatus2(event.booking_status) === phase && !TERMINAL_PHASES2.has(current.tracking_phase);
  if (current && seq === current.lifecycle_seq && kind === "lifecycle" && !terminalCorrection) {
    return { store: next, applied: false, confirmed: true, reason: "duplicate_lifecycle_seq", grant: current };
  }
  if (current && seq === current.lifecycle_seq && !terminalCorrection && (kind === "renew" || kind === "issue")) {
    const versionOk = !Number.isFinite(assignmentVersion) || assignmentVersion === current.assignment_version;
    const phaseOk = phase === current.tracking_phase;
    if (!versionOk || !phaseOk) {
      return { store: next, applied: false, confirmed: false, reason: "renew_mismatch", grant: current };
    }
    const hashes = Array.isArray(current.access_token_hashes) ? [...current.access_token_hashes] : [];
    if (current.access_token_hash && !hashes.includes(current.access_token_hash)) hashes.push(current.access_token_hash);
    const grant2 = {
      ...current,
      // Metadata only: refresh the confirmed assignment, never a prior label.
      ...assignmentVersion === current.assignment_version && text(event?.driver_id, 96) === current.driver_id ? {
        driver: publicDriver2(event?.driver),
        vehicle: publicVehicle2(event?.assigned_vehicle || event?.vehicle)
      } : {},
      access_until_ms: TERMINAL_PHASES2.has(current.tracking_phase) ? current.access_until_ms : nowMs + GRANT_ACCESS_TTL_MS,
      updated_at: new Date(nowMs).toISOString()
    };
    if (kind === "issue" && tokenHash && !TERMINAL_PHASES2.has(current.tracking_phase) && !(grant2.revoked_token_hashes || []).includes(tokenHash)) {
      if (!hashes.includes(tokenHash)) hashes.push(tokenHash);
      grant2.access_token_hash = tokenHash;
      grant2.access_token_hashes = hashes;
    }
    next.grants[key2] = grant2;
    return { store: next, applied: true, confirmed: true, reason: kind, grant: grant2 };
  }
  const reassigned = current && Number.isFinite(assignmentVersion) && assignmentVersion !== current.assignment_version;
  const grant = {
    contract_version: SNAPSHOT_CONTRACT_VERSION,
    tenant_id: tenantId,
    company_id: companyId,
    booking_id: bookingId,
    operational_leg: leg,
    customer_id: text(event?.customer_id, 96) || current?.customer_id || "",
    assignment_version: Number.isFinite(assignmentVersion) ? assignmentVersion : current?.assignment_version || 0,
    tracking_phase: phase,
    booking_status: text(event?.booking_status, 40),
    session_id: text(event?.session_id, 128) || (reassigned ? "" : current?.session_id || ""),
    driver_id: text(event?.driver_id, 96),
    access_token_hash: tokenHash || (reassigned ? "" : current?.access_token_hash || ""),
    access_token_hashes: tokenHash ? [tokenHash] : reassigned ? [] : [...current?.access_token_hashes || []],
    revoked_token_hashes: reassigned ? [...new Set([...current?.revoked_token_hashes || [], ...current?.access_token_hashes || [], current?.access_token_hash].filter(Boolean))] : [...current?.revoked_token_hashes || []],
    driver: publicDriver2(event?.driver),
    vehicle: publicVehicle2(event?.assigned_vehicle || event?.vehicle),
    pickup: pointOrNull(event?.pickup),
    destination: pointOrNull(event?.destination),
    operational_route: phase === "in_progress" ? publicOperationalRoute2(event?.operational_route) : null,
    position_allowed: LIVE_PHASES.has(phase),
    sync_state: "ok",
    lifecycle_seq: seq,
    access_until_ms: nowMs + GRANT_ACCESS_TTL_MS,
    updated_at: new Date(nowMs).toISOString()
  };
  if (event?.revoke_access_token_hash) {
    grant.revoked_token_hashes = [.../* @__PURE__ */ new Set([...grant.revoked_token_hashes, text(event.revoke_access_token_hash, 128)])];
    if (grant.access_token_hash === text(event.revoke_access_token_hash, 128)) grant.access_token_hash = "";
  }
  next.grants[key2] = grant;
  return { store: next, applied: true, confirmed: true, reason: reassigned ? "reassigned" : "applied", grant };
}
function pointOrNull(value) {
  const latitude = Number(value?.latitude ?? value?.lat);
  const longitude = Number(value?.longitude ?? value?.lon ?? value?.lng);
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return null;
  return { latitude, longitude };
}
function customerAccessAllowed2(grant, query) {
  if (!grant || grant.leg_scope_retired) return { ok: false, error: "not_found", status: 404 };
  if (text(query?.tenant_id, 80) !== grant.tenant_id) return { ok: false, error: "not_found", status: 404 };
  if (text(query?.company_id, 80) !== grant.company_id) return { ok: false, error: "not_found", status: 404 };
  if (text(query?.booking_id, 96) !== grant.booking_id) return { ok: false, error: "not_found", status: 404 };
  const leg = text(query?.operational_leg, 200) || "primary";
  if (leg !== grant.operational_leg) return { ok: false, error: "not_found", status: 404 };
  if (text(query?.customer_id, 96) && text(query.customer_id, 96) !== grant.customer_id) {
    return { ok: false, error: "not_found", status: 404 };
  }
  const token = text(query?.access_token_hash, 128);
  const hashes = Array.isArray(grant.access_token_hashes) ? grant.access_token_hashes : [];
  const previousVersion = Number(text(query?.assignment_version, 20));
  if (token && (grant.revoked_token_hashes || []).includes(token) && Number.isInteger(previousVersion) && previousVersion > 0 && previousVersion < grant.assignment_version && !TERMINAL_PHASES2.has(grant.tracking_phase)) {
    return { ok: false, error: "assignment_changed", status: 409 };
  }
  if (!token || token !== grant.access_token_hash && !hashes.includes(token)) {
    return { ok: false, error: "not_found", status: 404 };
  }
  if ((grant.revoked_token_hashes || []).includes(token)) return { ok: false, error: "not_found", status: 404 };
  const askedVersionRaw = text(query?.assignment_version, 20);
  const askedVersion = askedVersionRaw ? Number(askedVersionRaw) : NaN;
  if (Number.isFinite(askedVersion) && askedVersion !== grant.assignment_version) {
    return { ok: false, error: "not_found", status: 404 };
  }
  const askedSession = text(query?.session_id, 128);
  if (askedSession && grant.session_id && askedSession !== grant.session_id) {
    return { ok: false, error: "not_found", status: 404 };
  }
  return { ok: true };
}
function projectCustomerSnapshot2({ grant, driver, nowMs, eta, route }) {
  const phase = grant?.tracking_phase || "unassigned";
  const expired = !grant || !Number.isFinite(grant.access_until_ms) || nowMs > grant.access_until_ms;
  const syncClosed = grant?.sync_state === "failed";
  const terminal2 = TERMINAL_PHASES2.has(phase) || expired || syncClosed || grant?.position_allowed !== true;
  const sameDriver = driver && grant?.driver_id && driver.driver_id === grant.driver_id;
  const fresh = sameDriver && driver.position_stale !== true && driver.reliable_for_eta !== false;
  const position = !terminal2 && fresh ? {
    latitude: driver.latitude,
    longitude: driver.longitude,
    heading: driver.heading ?? null,
    captured_at: driver.position_captured_at || driver.captured_at || null,
    accuracy: driver.accuracy ?? null
  } : null;
  const feed = !driver || !sameDriver ? "missing" : driver.position_stale ? "stale" : driver.location_feed || "live";
  const target2 = etaTargetForPhase(phase);
  const etaOut = !terminal2 && target2 && eta && eta.target === target2 ? {
    target: target2,
    source: eta.source || "mapbox/driving-traffic",
    duration_seconds: eta.duration_seconds,
    valid_until: eta.valid_until,
    distance_meters: eta.distance_meters ?? null
  } : null;
  return {
    ok: true,
    contract_version: SNAPSHOT_CONTRACT_VERSION,
    tenant_id: grant.tenant_id,
    company_id: grant.company_id,
    booking_id: grant.booking_id,
    operational_leg: grant.operational_leg,
    assignment_version: grant.assignment_version,
    response_version: grant.lifecycle_seq,
    booking_status: grant.booking_status || phase,
    tracking_phase: terminal2 && expired && LIVE_PHASES.has(phase) ? "expired" : phase,
    position,
    pickup: terminal2 ? null : grant.pickup ?? null,
    destination: terminal2 ? null : grant.destination ?? null,
    operational_route: !terminal2 && phase === "in_progress" ? publicOperationalRoute2(grant.operational_route) : null,
    feed: {
      health: terminal2 ? "closed" : feed,
      position_captured_at: sameDriver ? driver.position_captured_at || driver.captured_at || null : null,
      last_seen_at: sameDriver ? driver.last_seen_at || null : null
    },
    eta: etaOut,
    route: !terminal2 && phase !== "arrived_pickup" && route ? route : null,
    driver: terminal2 ? null : grant.driver,
    vehicle: terminal2 ? null : grant.vehicle,
    refresh: {
      poll_after_seconds: terminal2 ? 0 : 10,
      access_until: grant.access_until_ms ? new Date(grant.access_until_ms).toISOString() : null
    }
  };
}
var CUSTOMER_GRANT_STORAGE_KEY = "customer_grants_v1";
var CUSTOMER_GRANT_ARCHIVE_AFTER_MS2 = 24 * 60 * 6e4;
var CUSTOMER_GRANT_SNAPSHOT_MAX_BYTES2 = 8 * 1024 * 1024;
var FORMAT2 = "customer-grant-pages-v2";
var INLINE_BYTES4 = 80 * 1024;
var PAGE_CHARS3 = 24 * 1024;
var ARCHIVE_BATCH = 96;
var encoder6 = new TextEncoder();
var bytes2 = (text3) => encoder6.encode(text3);
var map = (value) => value && typeof value === "object" && !Array.isArray(value);
var sameScope22 = (a, b) => a?.tenant_id === b?.tenant_id && a?.company_id === b?.company_id;
async function digest22(text3) {
  return [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes2(text3)))].map((value) => value.toString(16).padStart(2, "0")).join("");
}
async function customerGrantArchiveKey(key2) {
  if (typeof key2 !== "string" || !key2 || key2.length > 300) throw Error("customer_grant_identity_invalid");
  return "customer_grant_archive_v1:" + await digest22(key2);
}
function validateStore(store) {
  if (!map(store) || !map(store.grants)) throw Error("customer_grant_storage_invalid");
  return store;
}
function manifestPages2(root) {
  if (!Array.isArray(root.pages) || !root.pages.length || root.pages.length > 1024 || !/^[a-f\d-]{36}$/.test(root.generation || "") || !Number.isSafeInteger(root.bytes) || root.bytes < 1 || root.bytes > CUSTOMER_GRANT_SNAPSHOT_MAX_BYTES2 || !/^[a-f\d]{64}$/.test(root.sha256 || "") || root.pages.some((key2, i) => key2 !== `customer_grant_page_v2:${root.generation}:${i}`)) {
    throw Error("customer_grant_manifest_invalid");
  }
  return root.pages;
}
async function readCustomerGrantSnapshot2(storage) {
  const root = await storage.get(CUSTOMER_GRANT_STORAGE_KEY);
  if (root == null) return { grants: {} };
  if (root.format !== FORMAT2) return validateStore(root);
  const parts = [];
  for (const key2 of manifestPages2(root)) {
    const part = await storage.get(key2);
    if (typeof part !== "string" || part.length > PAGE_CHARS3) throw Error("customer_grant_page_missing");
    parts.push(part);
  }
  const text3 = parts.join("");
  if (bytes2(text3).length !== root.bytes || await digest22(text3) !== root.sha256) throw Error("customer_grant_checksum_invalid");
  return validateStore(JSON.parse(text3));
}
async function readStoredCustomerGrant2(storage, store, key2, scope2) {
  if (Object.hasOwn(store.grants, key2)) return store.grants[key2];
  const cold = await storage.get(await customerGrantArchiveKey(key2));
  if (cold == null) return null;
  const row = cold.record;
  if (cold.key !== key2 || !sameScope22(cold.scope, scope2) || !map(row) || !/^[a-f\d]{64}$/.test(cold.sha256 || "") || await digest22(JSON.stringify(row)) !== cold.sha256 || row.position_allowed === true || !(row.leg_scope_retired || TERMINAL_PHASES2.has(row.tracking_phase)) || row.tenant_id && row.tenant_id !== scope2.tenant_id || row.company_id && row.company_id !== scope2.company_id || !row.leg_scope_retired && (!sameScope22(row, scope2) || grantKey2(row.booking_id, row.operational_leg) !== key2 || !Number.isFinite(row.lifecycle_seq) || !Number.isFinite(row.assignment_version))) {
    throw Error("customer_grant_archive_invalid");
  }
  return row;
}
async function hydrateCustomerGrantEvent2(storage, store, event, scope2) {
  const keys = [grantKey2(event.booking_id, event.operational_leg)];
  if (event.disable_primary === true && event.operational_leg && event.operational_leg !== "primary") {
    keys.push(grantKey2(event.booking_id, "primary"));
  }
  let next = store;
  for (const key2 of keys) {
    if (Object.hasOwn(next.grants, key2)) continue;
    const row = await readStoredCustomerGrant2(storage, next, key2, scope2);
    if (row) next = { ...next, grants: { ...next.grants, [key2]: row } };
  }
  return next;
}
async function writeCustomerGrantSnapshot2(storage, store, nowMs) {
  validateStore(store);
  const next = { ...store, grants: { ...store.grants } }, archive = [];
  for (const [key2, original] of Object.entries(next.grants)) {
    if (!map(original)) throw Error("customer_grant_storage_invalid");
    let row = original;
    const closed = row.position_allowed !== true && (row.leg_scope_retired || TERMINAL_PHASES2.has(row.tracking_phase));
    let updated = Date.parse(row.updated_at || "");
    if (closed && !Number.isFinite(updated)) {
      row = { ...row, updated_at: new Date(nowMs).toISOString() };
      next.grants[key2] = row;
      updated = nowMs;
    }
    if (closed && updated <= nowMs - CUSTOMER_GRANT_ARCHIVE_AFTER_MS2 && archive.length < ARCHIVE_BATCH) {
      if (!store.scope?.tenant_id || !store.scope?.company_id) throw Error("customer_grant_archive_scope_required");
      const text4 = JSON.stringify(row);
      if (bytes2(text4).length > INLINE_BYTES4) throw Error("customer_grant_archive_too_large");
      archive.push([await customerGrantArchiveKey(key2), { key: key2, scope: store.scope, record: row, sha256: await digest22(text4) }]);
      delete next.grants[key2];
    }
  }
  const text3 = JSON.stringify(next), length = bytes2(text3).length;
  if (length > CUSTOMER_GRANT_SNAPSHOT_MAX_BYTES2) throw Error("customer_grant_snapshot_too_large");
  const previous = await storage.get(CUSTOMER_GRANT_STORAGE_KEY);
  const oldPages = previous?.format === FORMAT2 ? manifestPages2(previous) : [];
  const entries = [...archive];
  let root = next;
  if (length > INLINE_BYTES4) {
    const generation = crypto.randomUUID(), pages = [];
    for (let at = 0; at < text3.length; at += PAGE_CHARS3) {
      const key2 = `customer_grant_page_v2:${generation}:${pages.length}`;
      entries.push([key2, text3.slice(at, at + PAGE_CHARS3)]);
      pages.push(key2);
    }
    root = { format: FORMAT2, generation, pages, bytes: length, sha256: await digest22(text3) };
  }
  const commit = async (txn) => {
    for (const [key2, value] of entries) await txn.put(key2, value);
    await txn.put(CUSTOMER_GRANT_STORAGE_KEY, root);
    for (const key2 of oldPages) await txn.delete(key2);
  };
  if (typeof storage.transaction === "function") await storage.transaction(commit);
  else {
    if (entries.length || oldPages.length) throw Error("customer_grant_transaction_required");
    await storage.put(CUSTOMER_GRANT_STORAGE_KEY, root);
  }
  return next;
}
var DISPATCH_DEVICE_TTL_MS = 18e4;
var VEHICLE_DISPATCH_DEVICE_TTL_MS = 8e3;
var matches3 = (row, scope2) => row?.tenant_id === scope2.tenant_id && row?.company_id === scope2.company_id;
var valid4 = (row, nowMs) => row?.protocol === 1 && Number.isFinite(row.seen_at_ms) && row.seen_at_ms <= nowMs && nowMs < row.valid_until_ms;
function driverDispatchDevices3(store, scope2, driverId, nowMs, deviceKey = "") {
  if (!matches3(store?.scope, scope2)) return [];
  return Object.values(store.devices || {}).filter((row) => matches3(row, scope2) && row.driver_id === driverId && (!deviceKey || row.device_key === deviceKey) && valid4(row, nowMs));
}
function dispatchDeviceDeadline2(store, scope2, driverId, nowMs) {
  const rows2 = driverDispatchDevices3(store, scope2, driverId, nowMs);
  return rows2.length ? Math.max(...rows2.map((row) => row.valid_until_ms)) : null;
}
function projectDispatchDevices2(store, scope2, nowMs) {
  if (!matches3(store?.scope, scope2)) return [];
  const drivers = /* @__PURE__ */ new Map();
  for (const row of Object.values(store.devices || {})) {
    if (!matches3(row, scope2) || !valid4(row, nowMs)) continue;
    const previous = drivers.get(row.driver_id);
    if (!previous || previous.valid_until_ms < row.valid_until_ms) drivers.set(
      row.driver_id,
      { driver_id: row.driver_id, protocol: 1, seen_at_ms: row.seen_at_ms, valid_until_ms: row.valid_until_ms }
    );
  }
  return [...drivers.values()];
}
function updateDispatchDevice2(store, input, nowMs) {
  if (!input?.tenant_id || !input.company_id || typeof input.driver_id !== "string" || !input.driver_id || input.driver_id.length > 96 || !/^[a-f0-9]{64}$/.test(input.device_key || "") || !Number.isFinite(nowMs) || !Number.isFinite(input.session_expires_ms) || input.session_expires_ms <= nowMs) {
    return { ok: false, error: "dispatch_device_invalid", status: 400 };
  }
  if (store?.scope && !matches3(store.scope, input)) return { ok: false, error: "dispatch_device_scope_conflict", status: 409 };
  const old = store?.devices?.[input.device_key];
  if (old && (!matches3(old, input) || old.driver_id !== input.driver_id)) {
    return { ok: false, error: "dispatch_device_owner_conflict", status: 409 };
  }
  const devices = Object.fromEntries(Object.entries(store?.devices || {}).filter(([, row]) => valid4(row, nowMs)));
  delete devices[input.device_key];
  if (input.protocol === 1) devices[input.device_key] = {
    tenant_id: input.tenant_id,
    company_id: input.company_id,
    driver_id: input.driver_id,
    device_key: input.device_key,
    protocol: 1,
    seen_at_ms: nowMs,
    ...input.vehicle_device_id ? { vehicle_device_id: input.vehicle_device_id } : {},
    valid_until_ms: Math.min(nowMs + (input.vehicle_device_id ? VEHICLE_DISPATCH_DEVICE_TTL_MS : DISPATCH_DEVICE_TTL_MS), input.session_expires_ms)
  };
  const rows2 = Object.values(devices).filter((row) => row.driver_id === input.driver_id).sort((a, b) => b.seen_at_ms - a.seen_at_ms || a.device_key.localeCompare(b.device_key));
  for (const row of rows2.slice(4)) delete devices[row.device_key];
  return { ok: true, store: { scope: { tenant_id: input.tenant_id, company_id: input.company_id }, devices } };
}
var indexes = /* @__PURE__ */ new WeakMap();
function invalidateCapacityResourceIndex2(claims) {
  indexes.delete(claims);
}
function capacityResourceIndex(claims) {
  let index = indexes.get(claims);
  if (index) return index;
  const driver = /* @__PURE__ */ new Map(), vehicle = /* @__PURE__ */ new Map(), owner2 = /* @__PURE__ */ new Map();
  const add = (map3, id22, claim) => {
    if (!id22) return;
    if (!map3.has(id22)) map3.set(id22, []);
    map3.get(id22).push(claim);
  };
  for (const claim of Object.values(claims || {})) {
    add(driver, claim.driver_id, claim);
    add(vehicle, claim.vehicle_id, claim);
    add(owner2, claim.owner_id, claim);
  }
  index = { driver, vehicle, owner: owner2 };
  if (claims && typeof claims === "object") indexes.set(claims, index);
  return index;
}
function claimsForResource2(claims, resource, index = capacityResourceIndex(claims)) {
  const found = /* @__PURE__ */ new Map();
  for (const claim of [...index.driver.get(resource.driver_id) || [], ...index.vehicle.get(resource.vehicle_id) || []]) found.set(claim.claim_id, claim);
  return [...found.values()];
}
function claimsForOwner2(claims, ownerId) {
  return capacityResourceIndex(claims).owner.get(ownerId) || [];
}
function sameCapacityResource2(left, right) {
  return Boolean(left.vehicle_id && left.vehicle_id === right.vehicle_id || left.driver_id && left.driver_id === right.driver_id);
}
function capacityBaselineDecision2(ledger, input) {
  if (!input.tenant_id || !input.company_id || input.inventory_verified !== true || !Array.isArray(input.bookings) || input.bookings.length > 5e3) {
    return { ok: false, error: "capacity_baseline_invalid", status: 400 };
  }
  let next = structuredClone(ledger);
  for (const booking of input.bookings) {
    const checked = capacityClaimDecision2({ claims: {}, owners: {} }, {
      ...booking,
      tenant_id: input.tenant_id,
      company_id: input.company_id,
      action: "reserve",
      replace_owner: false
    }, []);
    if (!checked.ok) return checked;
    if (next.owners[booking.owner_id]) {
      const previous = next.owners[booking.owner_id];
      if (previous.tenant_id !== input.tenant_id || previous.company_id !== input.company_id) {
        return { ok: false, error: "capacity_scope_conflict", status: 409 };
      }
      if (previous.version < booking.version || previous.pending) {
        return { ok: false, error: "capacity_baseline_owner_unresolved", status: 409 };
      }
      if (!previous.released && previous.version === booking.version) {
        const comparable = (claim) => JSON.stringify({
          claim_id: claim.claim_id,
          driver_id: claim.driver_id || "",
          vehicle_id: claim.vehicle_id || "",
          start_ms: claim.start_ms,
          end_ms: claim.end_ms,
          active: claim.active === true
        });
        const held = claimsForOwner2(next.claims, booking.owner_id).filter((claim) => !claim.retiring).map(comparable).sort();
        if (JSON.stringify(held) !== JSON.stringify((booking.claims || []).map(comparable).sort())) {
          return { ok: false, error: "capacity_baseline_owner_unresolved", status: 409 };
        }
      }
      continue;
    }
    if (Object.keys(checked.ledger.claims).some((id22) => next.claims[id22])) {
      return { ok: false, error: "capacity_owner_conflict", status: 409 };
    }
    next = { ...next, claims: { ...next.claims, ...checked.ledger.claims }, owners: { ...next.owners, ...checked.ledger.owners } };
  }
  return { ok: true, ledger: next };
}
var UNSTARTED_CAPACITY_GRACE_MS2 = 15 * 60 * 1e3;
function unstartedCapacityExpired2(claim, nowMs = Date.now(), owner2 = null) {
  return claim?.active !== true && !claim?.retiring && claim?.capacity_pending !== true && owner2?.pending !== true && Number.isFinite(claim?.start_ms) && Number.isFinite(claim?.end_ms) && claim.start_ms < claim.end_ms && nowMs >= claim.end_ms + UNSTARTED_CAPACITY_GRACE_MS2;
}
function overdueCapacityHold2(claim, nowMs = Date.now(), owner2 = null) {
  return claim?.active !== true && Number.isFinite(claim?.start_ms) && Number.isFinite(claim?.end_ms) && claim.start_ms < claim.end_ms && claim.end_ms <= nowMs && !unstartedCapacityExpired2(claim, nowMs, owner2);
}
function capacityClaimDecision2(ledger, input, directRides) {
  const { tenant_id, company_id, owner_id, action, claims = [], version = 1 } = input;
  if (!tenant_id || !company_id || typeof owner_id !== "string" || !owner_id.trim() || owner_id.length > 200 || !["reserve", "release", "confirm", "activate"].includes(action) || !Number.isSafeInteger(version) || version < 1 || !Array.isArray(claims)) {
    return { ok: false, error: "capacity_request_invalid", status: 400 };
  }
  const previous = ledger.owners[owner_id];
  if (previous && (previous.tenant_id !== tenant_id || previous.company_id !== company_id)) {
    return { ok: false, error: "capacity_scope_conflict", status: 409 };
  }
  if (previous?.released && action === "release" && version <= previous.version) return { ok: true, ledger };
  if (previous && version < previous.version) return { ok: false, error: "capacity_revision_conflict", status: 409 };
  if (previous?.pending && action === "release") return { ok: false, error: "capacity_update_pending", status: 409, pending_version: previous.version };
  if (previous?.pending && version !== previous.version) return { ok: false, error: "capacity_update_pending", status: 409, pending_version: previous.version };
  if (action === "activate") {
    let claim = ledger.claims[input.claim_id];
    if (!claim && !previous && typeof input.claim_id === "string" && input.claim_id.length <= 240 && input.driver_id && input.vehicle_id) {
      claim = {
        claim_id: input.claim_id,
        driver_id: input.driver_id,
        vehicle_id: input.vehicle_id,
        start_ms: Date.now(),
        end_ms: Date.now() + 1,
        tenant_id,
        company_id,
        owner_id
      };
    }
    if (previous?.pending || previous?.released || previous && previous.version !== version || !claim || claim.owner_id !== owner_id || claim.retiring || claim.driver_id !== input.driver_id || claim.vehicle_id !== input.vehicle_id) {
      return { ok: false, error: "capacity_revision_conflict", status: 409 };
    }
    if (unstartedCapacityExpired2(claim, Date.now(), previous)) {
      return { ok: false, error: "capacity_reservation_expired", status: 409 };
    }
    if (directRides.some((ride) => ride.tenant_id === tenant_id && ride.company_id === company_id && sameCapacityResource2(ride, claim)) || claimsForResource2(ledger.claims, claim).some((other) => other.owner_id !== owner_id && (other.active || overdueCapacityHold2(other, Date.now(), ledger.owners[other.owner_id])) && other.tenant_id === tenant_id && other.company_id === company_id && sameCapacityResource2(other, claim))) {
      return { ok: false, error: "capacity_conflict", status: 409 };
    }
    return { ok: true, ledger: {
      ...ledger,
      claims: { ...ledger.claims, [input.claim_id]: { ...claim, active: true } },
      owners: { ...ledger.owners, [owner_id]: previous || { tenant_id, company_id, version, signature: "activated", pending: false, released: false } }
    } };
  }
  if (action === "confirm") {
    if (!previous || previous.version !== version) return { ok: false, error: "capacity_revision_conflict", status: 409 };
    if (previous.released) return { ok: true, ledger };
    if (input.canonical_claims) {
      const comparable = (claim) => JSON.stringify({
        claim_id: claim.claim_id,
        driver_id: claim.driver_id || "",
        vehicle_id: claim.vehicle_id || "",
        start_ms: claim.start_ms,
        end_ms: claim.end_ms,
        active: claim.active === true
      });
      const current = claimsForOwner2(ledger.claims, owner_id).filter((claim) => !claim.retiring).map(comparable).sort();
      if (!Array.isArray(input.canonical_claims) || JSON.stringify(current) !== JSON.stringify(input.canonical_claims.map(comparable).sort())) {
        return { ok: false, error: "capacity_checkpoint_conflict", status: 409 };
      }
    }
    const confirmedClaims = Object.fromEntries(Object.entries(ledger.claims).filter(([, claim]) => claim.owner_id !== owner_id || !claim.retiring));
    return { ok: true, ledger: { claims: confirmedClaims, owners: {
      ...ledger.owners,
      [owner_id]: { ...previous, pending: false, released: !Object.values(confirmedClaims).some((claim) => claim.owner_id === owner_id) }
    } } };
  }
  if (action === "reserve" && (!claims.length && input.replace_owner !== true || claims.length > 8)) {
    return { ok: false, error: "capacity_request_invalid", status: 400 };
  }
  if (claims.some((claim) => !claim || typeof claim !== "object" || Array.isArray(claim))) {
    return { ok: false, error: "capacity_request_invalid", status: 400 };
  }
  const normalized2 = claims.map((claim) => ({
    claim_id: claim.claim_id,
    driver_id: claim.driver_id || "",
    vehicle_id: claim.vehicle_id || "",
    start_ms: claim.start_ms,
    end_ms: claim.end_ms,
    active: claim.active === true,
    tenant_id,
    company_id,
    owner_id
  }));
  if (action === "reserve" && normalized2.some((claim) => !claim.claim_id || claim.claim_id.length > 240 || typeof claim.claim_id !== "string" || !claim.driver_id && !claim.vehicle_id || claim.driver_id && (typeof claim.driver_id !== "string" || claim.driver_id.length > 128) || claim.vehicle_id && (typeof claim.vehicle_id !== "string" || claim.vehicle_id.length > 128) || !Number.isFinite(claim.start_ms) || !Number.isFinite(claim.end_ms) || claim.end_ms <= claim.start_ms)) {
    return { ok: false, error: "capacity_request_invalid", status: 400 };
  }
  if (action === "reserve" && new Set(normalized2.map((claim) => claim.claim_id)).size !== normalized2.length) {
    return { ok: false, error: "capacity_request_invalid", status: 400 };
  }
  const ended = input.ended_claim_ids === void 0 ? [] : input.ended_claim_ids;
  if (!Array.isArray(ended) || ended.length > 8 || new Set(ended).size !== ended.length || ended.some((id22) => typeof id22 !== "string" || !id22.trim() || id22.length > 240)) {
    return { ok: false, error: "capacity_request_invalid", status: 400 };
  }
  const signature = JSON.stringify({
    action,
    replace_owner: input.replace_owner === true,
    claims: normalized2,
    ...ended.length ? { ended_claim_ids: [...ended].sort() } : {}
  });
  if (action === "reserve" && previous?.pending && previous.signature !== signature) {
    return { ok: false, error: "capacity_update_pending", status: 409, pending_version: previous.version };
  }
  if (action === "reserve" && previous?.version === version && !previous.pending && previous.signature === signature) {
    return { ok: true, ledger };
  }
  if (previous?.version === version && previous.signature !== signature && (previous.released || action === "reserve" && input.replace_owner === true)) {
    return { ok: false, error: "capacity_revision_conflict", status: 409 };
  }
  if (action === "reserve") {
    for (const held of claimsForOwner2(ledger.claims, owner_id)) {
      if (held.owner_id !== owner_id || held.retiring || !held.active) continue;
      const next = normalized2.find((claim) => claim.claim_id === held.claim_id);
      if (input.replace_owner !== true && !next) continue;
      const preserved = next?.active === true && next.driver_id === held.driver_id && next.vehicle_id === held.vehicle_id;
      if (!preserved && !(ended.includes(held.claim_id) && !next)) {
        return { ok: false, error: "active_assignment_change_requires_completion", status: 409 };
      }
    }
  }
  const nextClaims = { ...ledger.claims };
  if (action === "release" || input.replace_owner === true) {
    for (const [id22, claim] of Object.entries(nextClaims)) {
      if (claim.owner_id === owner_id && claim.tenant_id === tenant_id && claim.company_id === company_id && (action !== "release" || !Array.isArray(input.claim_ids) || input.claim_ids.includes(id22))) {
        if (action === "reserve" && !claim.retiring && !normalized2.some((next) => JSON.stringify(next) === JSON.stringify(claim))) {
          const retiringId = `${id22}:retiring:${version}`;
          nextClaims[retiringId] = { ...claim, claim_id: retiringId, retiring: true };
        }
        if (!claim.retiring || action === "release") delete nextClaims[id22];
      }
    }
  }
  for (const claim of action === "reserve" ? normalized2 : []) {
    const existing = nextClaims[claim.claim_id];
    if (existing && existing.owner_id !== owner_id) return { ok: false, error: "capacity_owner_conflict", status: 409 };
    if (directRides.some((ride) => ride.tenant_id === tenant_id && ride.company_id === company_id && sameCapacityResource2(ride, claim))) return { ok: false, error: "active_ride_end_unknown", status: 409 };
    if (claim.end_ms > Date.now() && claimsForResource2(nextClaims, claim).some((other) => other.claim_id !== claim.claim_id && !(other.owner_id === owner_id && other.retiring) && other.tenant_id === tenant_id && other.company_id === company_id && sameCapacityResource2(other, claim) && overdueCapacityHold2(other, Date.now(), ledger.owners[other.owner_id]))) {
      return { ok: false, error: "capacity_completion_unconfirmed", status: 409 };
    }
    if (claimsForResource2(nextClaims, claim).some((other) => other.claim_id !== claim.claim_id && !(other.owner_id === owner_id && other.retiring) && other.tenant_id === tenant_id && other.company_id === company_id && sameCapacityResource2(other, claim) && claim.start_ms < other.end_ms && other.start_ms < claim.end_ms)) {
      return { ok: false, error: "capacity_conflict", status: 409 };
    }
    if (existing && previous?.version === version && JSON.stringify(existing) !== JSON.stringify(claim)) {
      return { ok: false, error: "capacity_revision_conflict", status: 409 };
    }
    if (existing && JSON.stringify(existing) !== JSON.stringify(claim)) {
      const retiringId = `${claim.claim_id}:retiring:${version}`;
      nextClaims[retiringId] = { ...existing, claim_id: retiringId, retiring: true };
    }
    nextClaims[claim.claim_id] = claim;
    invalidateCapacityResourceIndex2(nextClaims);
  }
  return { ok: true, ledger: { claims: nextClaims, owners: {
    ...ledger.owners,
    [owner_id]: {
      tenant_id,
      company_id,
      version,
      signature,
      pending: action === "reserve" && input.replace_owner === true,
      released: action === "release" && !Object.values(nextClaims).some((claim) => claim.owner_id === owner_id)
    }
  } } };
}
var CAPACITY_STORAGE_KEY2 = "company_capacity_ledger_v1";
var CAPACITY_ARCHIVE_AFTER_MS2 = 24 * 60 * 6e4;
var CAPACITY_SNAPSHOT_MAX_BYTES2 = 8 * 1024 * 1024;
var INLINE_BYTES22 = 80 * 1024;
var PAGE_CHARS22 = 24 * 1024;
var ARCHIVE_BATCH2 = 96;
var FORMAT22 = "company-capacity-pages-v2";
var encoder22 = new TextEncoder();
var tables2 = { owner: "owners", offer: "offers", event: "dispatch_events" };
var validMap2 = (value) => value && typeof value === "object" && !Array.isArray(value);
var bytes22 = (value) => encoder22.encode(value);
async function digest32(text3) {
  return [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes22(text3)))].map((value) => value.toString(16).padStart(2, "0")).join("");
}
async function capacityArchiveKey2(kind, id22) {
  if (!tables2[kind] || typeof id22 !== "string" || !id22 || id22.length > 500) throw Error("capacity_archive_identity_invalid");
  return `capacity_archive_v1:${kind}:${await digest32(id22)}`;
}
function validateLedger2(ledger) {
  if (!validMap2(ledger) || !validMap2(ledger.claims) || !validMap2(ledger.owners)) throw Error("capacity_storage_invalid");
  return ledger;
}
function manifestPages22(root) {
  if (!Array.isArray(root.pages) || !root.pages.length || root.pages.length > 1024 || typeof root.generation !== "string" || !/^[a-f\d-]{36}$/.test(root.generation) || !Number.isSafeInteger(root.bytes) || root.bytes < 1 || root.bytes > CAPACITY_SNAPSHOT_MAX_BYTES2 || !/^[a-f\d]{64}$/.test(root.sha256 || "") || root.pages.some((key2, i) => key2 !== `capacity_page_v2:${root.generation}:${i}`)) throw Error("capacity_snapshot_manifest_invalid");
  return root.pages;
}
async function readCapacitySnapshot2(storage) {
  const root = await storage.get(CAPACITY_STORAGE_KEY2);
  if (root == null) return { claims: {}, owners: {} };
  if (root.format !== FORMAT22) return validateLedger2(root);
  manifestPages22(root);
  const parts = [];
  for (let i = 0; i < root.pages.length; i++) {
    const key2 = `capacity_page_v2:${root.generation}:${i}`;
    const part = await storage.get(key2);
    if (typeof part !== "string" || part.length > PAGE_CHARS22) throw Error("capacity_snapshot_page_missing");
    parts.push(part);
  }
  const text3 = parts.join("");
  if (bytes22(text3).length !== root.bytes || await digest32(text3) !== root.sha256) throw Error("capacity_snapshot_checksum_invalid");
  return validateLedger2(JSON.parse(text3));
}
async function hydrateCapacityRecords2(storage, ledger, identities, scope2) {
  let next = ledger;
  const pending = Object.entries(identities).flatMap(([kind, ids]) => ids.map((id22) => [kind, id22]));
  const seen = /* @__PURE__ */ new Set();
  for (let i = 0; i < pending.length; i++) {
    const [kind, id22] = pending[i], table3 = tables2[kind];
    if (!table3 || typeof id22 !== "string" || !id22 || id22.length > 500 || seen.has(`${kind}:${id22}`)) continue;
    seen.add(`${kind}:${id22}`);
    let row = next[table3]?.[id22];
    if (!Object.hasOwn(next[table3] || {}, id22)) {
      const archived = await storage.get(await capacityArchiveKey2(kind, id22));
      if (archived == null) continue;
      row = archived.record;
      if (archived.kind !== kind || archived.id !== id22 || !validMap2(row) || row.tenant_id !== scope2.tenant_id || row.company_id !== scope2.company_id || kind === "owner" && (!Number.isSafeInteger(row.version) || row.version < 1 || row.pending || !row.released) || kind === "offer" && row.offer_id !== id22 || kind === "event" && row.event_id !== id22) {
        throw Error("capacity_archive_record_invalid");
      }
      next = { ...next, [table3]: { ...next[table3], [id22]: row } };
    }
    if (row.owner_id) pending.push(["owner", row.owner_id]);
    if (kind === "event" && row.offer_id && row.type !== "dispatch_search") pending.push(["offer", row.offer_id]);
  }
  return next;
}
function compact(ledger, previous, nowMs) {
  const owners = { ...ledger.owners }, events = { ...ledger.dispatch_events }, offers = { ...ledger.offers };
  for (const [id22, owner2] of Object.entries(owners)) {
    if (!Number.isFinite(owner2.storage_updated_at_ms) || JSON.stringify(owner2) !== JSON.stringify(previous.owners[id22])) {
      owners[id22] = { ...owner2, storage_updated_at_ms: nowMs };
    }
  }
  for (const [id22, event] of Object.entries(events)) {
    if (event.state === "delivered" && (!Number.isFinite(event.storage_delivered_at_ms) || previous.dispatch_events?.[id22]?.state !== "delivered")) events[id22] = { ...event, storage_delivered_at_ms: nowMs };
  }
  const hot = new Set(Object.values(ledger.claims).map((claim) => claim.owner_id));
  for (const offer of Object.values(offers)) {
    if (["offered", "received", "committing"].includes(offer.state)) hot.add(offer.owner_id);
  }
  for (const event of Object.values(events)) if (event.state !== "delivered") hot.add(event.owner_id);
  const cutoff = nowMs - CAPACITY_ARCHIVE_AFTER_MS2;
  const cold = new Set(Object.entries(owners).filter(([id22, owner2]) => !hot.has(id22) && owner2.released === true && owner2.pending === false && owner2.storage_updated_at_ms <= cutoff).map(([id22]) => id22));
  const archive = [];
  const retire = (kind, table3, id22) => {
    archive.push({ kind, id: id22, record: table3[id22] });
    delete table3[id22];
  };
  for (const [id22, offer] of Object.entries(offers)) {
    if (archive.length >= ARCHIVE_BATCH2) break;
    if (cold.has(offer.owner_id)) retire("offer", offers, id22);
  }
  for (const [id22, event] of Object.entries(events)) {
    if (archive.length >= ARCHIVE_BATCH2) break;
    if (event.state === "delivered" && (cold.has(event.owner_id) || event.type === "dispatch_search" && !hot.has(event.owner_id) && event.storage_delivered_at_ms <= cutoff)) retire("event", events, id22);
  }
  const referenced = new Set([...Object.values(offers), ...Object.values(events)].map((row) => row.owner_id));
  for (const id22 of cold) {
    if (archive.length >= ARCHIVE_BATCH2) break;
    if (!referenced.has(id22)) retire("owner", owners, id22);
  }
  return { ledger: {
    ...ledger,
    owners,
    ...ledger.offers ? { offers } : {},
    ...ledger.dispatch_events ? { dispatch_events: events } : {}
  }, archive };
}
async function writeCapacitySnapshot2(storage, ledger, previous, nowMs) {
  const planned = compact(validateLedger2(ledger), previous, nowMs);
  const text3 = JSON.stringify(planned.ledger), length = bytes22(text3).length;
  if (length > CAPACITY_SNAPSHOT_MAX_BYTES2) throw Error("capacity_snapshot_too_large");
  const existing = await storage.get(CAPACITY_STORAGE_KEY2);
  const oldPages = existing?.format === FORMAT22 ? manifestPages22(existing) : [];
  const entries = [];
  for (const row of planned.archive) {
    if (bytes22(JSON.stringify(row)).length > INLINE_BYTES22) throw Error("capacity_archive_record_too_large");
    entries.push([await capacityArchiveKey2(row.kind, row.id), row]);
  }
  let root = planned.ledger;
  if (length > INLINE_BYTES22) {
    const generation = crypto.randomUUID(), pages = [];
    for (let at = 0; at < text3.length; at += PAGE_CHARS22) {
      const key2 = `capacity_page_v2:${generation}:${pages.length}`;
      entries.push([key2, text3.slice(at, at + PAGE_CHARS22)]);
      pages.push(key2);
    }
    root = { format: FORMAT22, generation, pages, bytes: length, sha256: await digest32(text3) };
  }
  const commit = async (txn) => {
    for (const [key2, value] of entries) await txn.put(key2, value);
    await txn.put(CAPACITY_STORAGE_KEY2, root);
    for (const key2 of oldPages) await txn.delete(key2);
  };
  if (typeof storage.transaction === "function") await storage.transaction(commit);
  else {
    if (entries.length || oldPages.length) throw Error("capacity_storage_transaction_required");
    await storage.put(CAPACITY_STORAGE_KEY2, root);
  }
  return planned.ledger;
}
var LOCATION_RETIRED_OWNER_LIMIT2 = 512;
var label2 = (value) => typeof value === "string" && /^[A-Za-z0-9_-]{1,128}$/.test(value);
function boundLocationOwner2(owner2, nowMs) {
  return Boolean(owner2 && /^[a-f0-9]{64}$/.test(owner2.session_hash || "") && label2(owner2.activation_id) && (owner2.native_device_id == null || label2(owner2.native_device_id)) && Number.isFinite(owner2.session_expires_ms) && owner2.session_expires_ms > nowMs);
}
function sameLocationOwner2(left, right) {
  return Boolean(left && right && left.session_hash === right.session_hash && left.activation_id === right.activation_id && left.native_device_id === right.native_device_id);
}
function retainedLocationOwners2(row, nowMs) {
  return (Array.isArray(row?.retired_publications) ? row.retired_publications : []).filter((owner2) => boundLocationOwner2(owner2, nowMs)).slice(0, LOCATION_RETIRED_OWNER_LIMIT2);
}
function locationOwnerRetired2(row, owner2, nowMs) {
  return Boolean(boundLocationOwner2(owner2, nowMs) && (row?.location_withdrawn === true && sameLocationOwner2(row.publication_owner, owner2) || retainedLocationOwners2(row, nowMs).some((retired) => sameLocationOwner2(retired, owner2))));
}
function nextRetiredLocationOwners2(row, owner2, nowMs) {
  const retained = retainedLocationOwners2(row, nowMs);
  const previous = row?.publication_owner;
  if (boundLocationOwner2(previous, nowMs) && !sameLocationOwner2(previous, owner2) && !retained.some((retired) => sameLocationOwner2(retired, previous))) {
    if (retained.length >= LOCATION_RETIRED_OWNER_LIMIT2) return null;
    retained.push(previous);
  }
  return retained;
}
var fail6 = () => ({ ok: false, error: "dispatch_amendment_conflict", status: 409 });
var comparableDispatchClaim = (claim) => JSON.stringify({
  claim_id: claim.claim_id,
  driver_id: claim.driver_id || "",
  vehicle_id: claim.vehicle_id || "",
  start_ms: claim.start_ms,
  end_ms: claim.end_ms,
  active: claim.active === true
});
var equalClaims = (left, right) => JSON.stringify(left.map(comparableDispatchClaim).sort()) === JSON.stringify(right.map(comparableDispatchClaim).sort());
function amendmentBaseMatches2(ledger, offer) {
  const owner2 = ledger.owners[offer.owner_id];
  const retained = offer.retained_claims;
  const held = Object.values(ledger.claims).filter((claim) => claim.owner_id === offer.owner_id && (!offer.offer_id || claim.offer_id !== offer.offer_id));
  return offer.amendment === true && Number.isSafeInteger(offer.base_version) && offer.base_version > 0 && offer.version >= offer.base_version && owner2?.version === offer.base_version && !owner2.pending && owner2.tenant_id === offer.tenant_id && owner2.company_id === offer.company_id && Array.isArray(retained) && retained.length <= 2 && retained.every((claim) => claim && typeof claim === "object" && typeof claim.claim_id === "string" && Number.isFinite(claim.start_ms) && Number.isFinite(claim.end_ms)) && (retained.length > 0 || owner2.released) && held.every((claim) => !claim.retiring && claim.tenant_id === offer.tenant_id && claim.company_id === offer.company_id) && equalClaims(held, retained);
}
function holdAmendmentClaims2(ledger, input, directRides) {
  if (!amendmentBaseMatches2(ledger, input) || input.version <= input.base_version || !Array.isArray(input.claims) || input.claims.length !== 1 || !["OUTBOUND", "RETURN"].some((type) => input.claims[0].claim_id === `${input.owner_id}:${type}`) || input.retained_claims.some((claim) => input.claims.some((next) => next.claim_id === claim.claim_id))) return fail6();
  const checked = capacityClaimDecision2(ledger, { ...input, action: "reserve", replace_owner: false }, directRides);
  return checked.ok ? { ok: true, ledger: {
    ...checked.ledger,
    owners: { ...checked.ledger.owners, [input.owner_id]: ledger.owners[input.owner_id] }
  } } : checked;
}
function promoteAmendmentClaims2(ledger, offer, directRides) {
  if (!amendmentBaseMatches2(ledger, offer) || !offer.claims.every((claim) => {
    const held = ledger.claims[claim.claim_id];
    return held?.owner_id === offer.owner_id && held.offer_id === offer.offer_id && !held.retiring && comparableDispatchClaim(held) === comparableDispatchClaim(claim);
  })) return fail6();
  const base = { ...ledger, claims: Object.fromEntries(Object.entries(ledger.claims).filter(([, claim]) => claim.owner_id !== offer.owner_id || claim.offer_id !== offer.offer_id)) };
  return capacityClaimDecision2(base, {
    ...offer,
    action: "reserve",
    replace_owner: true,
    claims: [...offer.retained_claims, ...offer.claims]
  }, directRides);
}
function rollbackAmendmentPromotion2(ledger, offer, proof, directRides) {
  const owner2 = ledger.owners[offer.owner_id];
  const held = Object.values(ledger.claims).filter((claim) => claim.owner_id === offer.owner_id && !claim.retiring);
  if (owner2?.version !== offer.version || !owner2.pending || !Number.isSafeInteger(proof.capacity_version) || proof.capacity_version <= offer.version || !Array.isArray(proof.canonical_claims) || !equalClaims(proof.canonical_claims, offer.retained_claims) || !equalClaims(held, [...offer.retained_claims, ...offer.claims])) return fail6();
  const settled = { ...ledger, owners: { ...ledger.owners, [offer.owner_id]: { ...owner2, pending: false } } };
  const reserved = capacityClaimDecision2(settled, {
    ...offer,
    action: "reserve",
    version: proof.capacity_version,
    replace_owner: true,
    claims: proof.canonical_claims
  }, directRides);
  if (!reserved.ok) return reserved;
  return capacityClaimDecision2(reserved.ledger, {
    ...offer,
    action: "confirm",
    version: proof.capacity_version,
    canonical_claims: proof.canonical_claims
  }, directRides);
}
var DISPATCH_ACK_TIMEOUT_MS = 15e4;
var DISPATCH_POSITION_TTL_MS = 18e4;
var PROVISIONAL = /* @__PURE__ */ new Set(["offered", "received"]);
var fail22 = (error, status = 409) => ({ ok: false, error, status });
var scopeMatches = (row, input) => row?.tenant_id === input.tenant_id && row?.company_id === input.company_id;
function dispatchOfferResources2(offer) {
  const pairs = /* @__PURE__ */ new Map();
  for (const claim of offer.claims || []) pairs.set(
    `${claim.driver_id}
${claim.vehicle_id}`,
    { driver_id: claim.driver_id, vehicle_id: claim.vehicle_id }
  );
  return [...pairs.values()];
}
var touches = (offer, row) => dispatchOfferResources2(offer).some((resource) => sameCapacityResource2(resource, row));
var prerequisites = (offer) => offer.prerequisites || (offer.prerequisite_claim_id ? [{
  claim_id: offer.prerequisite_claim_id,
  version: offer.prerequisite_version,
  driver_id: offer.driver_id,
  vehicle_id: offer.vehicle_id
}] : []);
function resourceFresh(offer, drivers, dispatchDevices, nowMs) {
  for (const resource of dispatchOfferResources2(offer)) {
    const position = drivers[resource.driver_id];
    if (!scopeMatches(position, offer) || position.vehicle_id !== resource.vehicle_id || !freshDispatchPosition(position, nowMs)) return { reason: "location_stale", driver_id: resource.driver_id };
    if (!driverDispatchDevices3(dispatchDevices, offer, resource.driver_id, nowMs).length) return { reason: "device_unavailable", driver_id: resource.driver_id };
  }
  return null;
}
function dispatchSearchDecision2(ledger, input, nowMs) {
  if (!input.tenant_id || !input.company_id || typeof input.owner_id !== "string" || !input.owner_id.trim() || input.owner_id.length > 160 || !Number.isSafeInteger(input.version) || input.version < 1 || !Number.isFinite(nowMs)) return fail22("dispatch_search_invalid", 400);
  const eventId = `search:${input.owner_id}:${input.version}`;
  const existing = ledger.dispatch_events?.[eventId];
  if (existing) return scopeMatches(existing, input) ? { ok: true, ledger, event: existing } : fail22("dispatch_event_conflict");
  if (input.amendment === true ? !amendmentBaseMatches2(ledger, input) : ledger.owners[input.owner_id] && !ledger.owners[input.owner_id].released || Object.values(ledger.claims).some((claim) => claim.owner_id === input.owner_id)) return fail22("dispatch_search_hard_assignment");
  const event = {
    ...input,
    event_id: eventId,
    offer_id: eventId,
    type: "dispatch_search",
    state: "pending",
    reason: "no_candidate",
    created_at_ms: nowMs
  };
  return { ok: true, event, ledger: { ...ledger, dispatch_events: { ...ledger.dispatch_events, [eventId]: event } } };
}
function freshDispatchPosition(row, nowMs) {
  if (!row) return false;
  const captured = Date.parse(row.position_captured_at || row.captured_at || "");
  const seen = Date.parse(row.last_seen_at || "");
  const lat = row.latitude, lng = row.longitude;
  return Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180 && !(lat === 0 && lng === 0) && row.reliable_for_eta !== false && row.stale !== true && [captured, seen].every((at) => Number.isFinite(at) && nowMs - at <= DISPATCH_POSITION_TTL_MS && at - nowMs <= 12e4);
}
function cancellation(ledger, offer, reason, nowMs, failedDriverId = offer.driver_id) {
  const claims = Object.fromEntries(Object.entries(ledger.claims).filter(([, claim]) => !(claim.owner_id === offer.owner_id && claim.offer_id === offer.offer_id)));
  const eventId = `${offer.offer_id}:${reason}`;
  return {
    ...ledger,
    claims,
    owners: {
      ...ledger.owners,
      [offer.owner_id]: offer.amendment ? ledger.owners[offer.owner_id] : { ...ledger.owners[offer.owner_id], released: true, pending: false }
    },
    offers: { ...ledger.offers, [offer.offer_id]: {
      ...offer,
      state: reason === "ack_timeout" ? "expired" : "cancelled",
      reason,
      ended_at_ms: nowMs
    } },
    dispatch_events: { ...ledger.dispatch_events, [eventId]: {
      event_id: eventId,
      type: "redispatch",
      ...offer,
      state: "pending",
      reason,
      created_at_ms: nowMs,
      failed_driver_id: failedDriverId
    } }
  };
}
function expireDispatchOffers(ledger, nowMs) {
  let next = ledger;
  for (const offer of Object.values(ledger.offers || {})) {
    if (PROVISIONAL.has(offer.state) && offer.ack_deadline_ms <= nowMs) {
      const missing = dispatchOfferResources2(offer).find((resource) => !offer.receipts?.[resource.driver_id]?.ready);
      next = cancellation(next, offer, "ack_timeout", nowMs, missing?.driver_id || offer.driver_id);
    }
  }
  return next;
}
function preemptOwnerAmendments2(ledger, input, nowMs) {
  let next = ledger;
  for (const offer of Object.values(ledger.offers || {})) {
    if (offer.amendment && offer.owner_id === input.owner_id && scopeMatches(offer, input) && PROVISIONAL.has(offer.state) && ["reserve", "activate", "release"].includes(input.action)) {
      next = cancellation(next, offer, "canonical_changed", nowMs);
    }
  }
  return next;
}
function preemptDispatchOffers2(ledger, street, nowMs) {
  let next = ledger;
  for (const offer of Object.values(ledger.offers || {})) {
    if (!scopeMatches(offer, street) || !PROVISIONAL.has(offer.state)) continue;
    if (touches(offer, street)) next = cancellation(next, offer, "street_hail", nowMs, street.driver_id);
  }
  return next;
}
function revalidateDispatchOffers2(ledger, drivers, nowMs, dispatchDevices) {
  let next = expireDispatchOffers(ledger, nowMs);
  for (const offer of Object.values(next.offers || {})) {
    if (!PROVISIONAL.has(offer.state)) continue;
    const stale = resourceFresh(offer, drivers, dispatchDevices, nowMs);
    let reason = offer.amendment && !amendmentBaseMatches2(next, offer) ? "canonical_changed" : stale?.reason;
    let failedDriverId = stale?.driver_id;
    for (const required of prerequisites(offer)) {
      const prior = next.claims[required.claim_id];
      if (!reason && prior && next.owners[prior.owner_id]?.version !== required.version) {
        reason = "destination_changed";
        failedDriverId = required.driver_id;
      }
      const start = Math.min(...offer.claims.filter((claim) => sameCapacityResource2(claim, required)).map((claim) => claim.start_ms));
      if (!reason && prior && prior.end_ms > start) {
        reason = "forecast_late";
        failedDriverId = required.driver_id;
      }
    }
    if (reason) next = cancellation(next, offer, reason, nowMs, failedDriverId || offer.driver_id);
  }
  return next;
}
function preemptPrerequisiteOffers2(ledger, input, nowMs) {
  if (!["reserve", "activate"].includes(input.action)) return ledger;
  let next = ledger;
  for (const offer of Object.values(ledger.offers || {})) {
    if (PROVISIONAL.has(offer.state) && scopeMatches(offer, input) && prerequisites(offer).some((required) => ledger.claims[required.claim_id]?.owner_id === input.owner_id && required.version !== input.version)) {
      const changed = prerequisites(offer).find((required) => ledger.claims[required.claim_id]?.owner_id === input.owner_id);
      next = cancellation(next, offer, "destination_changed", nowMs, changed?.driver_id || offer.driver_id);
    }
  }
  return next;
}
function dispatchOfferDecision2(ledger, input, { nowMs, directRides = [], driverPosition, drivers = {}, dispatchDevices } = {}) {
  if (!Number.isFinite(nowMs) || !input.tenant_id || !input.company_id || typeof input.offer_id !== "string" || !input.offer_id.trim() || input.offer_id.length > 200 || !Number.isInteger(input.version) || input.version < 1) return fail22("dispatch_offer_invalid", 400);
  if (input.prerequisites != null && (!Array.isArray(input.prerequisites) || input.prerequisites.length > 2 || input.prerequisites.some((row) => !row || typeof row.claim_id !== "string" || !row.claim_id || !Number.isSafeInteger(row.version) || row.version < 1 || !row.driver_id || !row.vehicle_id) || new Set(input.prerequisites.map((row) => row.claim_id)).size !== input.prerequisites.length)) {
    return fail22("dispatch_prerequisite_invalid", 400);
  }
  const current = ledger.offers?.[input.offer_id];
  if (current && (!scopeMatches(current, input) || current.version !== input.version || current.owner_id !== input.owner_id || (["ack", "accept", "decline"].includes(input.action) ? !dispatchOfferResources2(current).some((resource) => resource.driver_id === input.driver_id && resource.vehicle_id === input.vehicle_id) : current.driver_id !== input.driver_id || current.vehicle_id !== input.vehicle_id))) return fail22("dispatch_offer_conflict");
  const next = expireDispatchOffers(ledger, nowMs);
  const offer = next.offers?.[input.offer_id];
  if (input.action === "refresh" && offer?.amendment) {
    const proof = input.canonical_resolution;
    if (offer.state === "aborted") return { ok: true, ledger: next, offer };
    if (proof?.offer_id !== offer.offer_id || proof.version !== offer.version || proof.reason !== "canonical_changed" || proof.unassigned !== true || !Number.isSafeInteger(proof.record_canonical_version) || proof.record_canonical_version <= offer.record_canonical_version || !["offered", "received", "committing", "cancelled", "expired"].includes(offer.state)) return fail22("dispatch_refresh_unconfirmed");
    const rolled = offer.state === "committing" ? rollbackAmendmentPromotion2(next, offer, proof, directRides) : { ok: true, ledger: next };
    if (!rolled.ok) return rolled;
    const cancelled = cancellation({ ...next, ...rolled.ledger }, offer, "canonical_changed", nowMs);
    const aborted = { ...offer, state: "aborted", reason: "canonical_changed", ended_at_ms: nowMs };
    return { ok: true, offer: aborted, ledger: {
      ...cancelled,
      offers: { ...cancelled.offers, [offer.offer_id]: aborted }
    } };
  }
  if (input.action === "refresh") {
    const proof = input.canonical_resolution;
    if (offer?.state === "aborted") return { ok: true, ledger: next, offer };
    if (proof?.offer_id !== input.offer_id || proof?.version !== input.version || proof?.reason !== "canonical_changed" || proof.unassigned !== true || !Number.isSafeInteger(proof.record_canonical_version) || !Number.isSafeInteger(input.record_canonical_version) || input.record_canonical_version < 1 || proof.record_canonical_version <= input.record_canonical_version || offer && (offer.record_canonical_version !== input.record_canonical_version || !["offered", "received", "committing", "cancelled", "expired"].includes(offer.state)) || Object.values(next.claims).some((claim) => claim.owner_id === input.owner_id && (!offer || claim.offer_id !== offer.offer_id))) return fail22("dispatch_refresh_unconfirmed");
    if (!offer) return { ok: true, ledger: next };
    const owner2 = next.owners[offer.owner_id];
    if (owner2?.version !== offer.version) return fail22("dispatch_refresh_unconfirmed");
    const claims = Object.fromEntries(Object.entries(next.claims).filter(([, claim]) => !(claim.owner_id === offer.owner_id && claim.offer_id === offer.offer_id)));
    const aborted = { ...offer, state: "aborted", reason: "canonical_changed", ended_at_ms: nowMs };
    return { ok: true, offer: aborted, ledger: {
      ...next,
      claims,
      owners: { ...next.owners, [offer.owner_id]: { ...owner2, pending: false, released: true } },
      offers: { ...next.offers, [offer.offer_id]: aborted }
    } };
  }
  if (input.action === "defer") {
    if (offer) return offer.state === "cancelled" && offer.reason === "candidate_unavailable" ? { ok: true, ledger: next, offer } : fail22("dispatch_offer_conflict");
    if (input.amendment === true ? !amendmentBaseMatches2(next, input) : next.owners[input.owner_id] && (!next.owners[input.owner_id].released || next.owners[input.owner_id].version >= input.version) || Object.values(next.claims).some((claim) => claim.owner_id === input.owner_id)) return fail22("dispatch_offer_hard_assignment");
    const checked = capacityClaimDecision2({ claims: {}, owners: {} }, { ...input, action: "reserve" }, []);
    if (!checked.ok || !input.driver_id || !input.vehicle_id || ![1, 2].includes(input.claims.length)) return fail22("dispatch_offer_invalid", 400);
    const deferred = {
      tenant_id: input.tenant_id,
      company_id: input.company_id,
      offer_id: input.offer_id,
      owner_id: input.owner_id,
      version: input.version,
      driver_id: input.driver_id,
      vehicle_id: input.vehicle_id,
      claims: input.claims,
      ...input.amendment ? { amendment: true, base_version: input.base_version, retained_claims: input.retained_claims } : {},
      created_at_ms: nowMs,
      state: "offered"
    };
    const released = cancellation({ ...next, owners: {
      ...next.owners,
      [input.owner_id]: input.amendment ? next.owners[input.owner_id] : checked.ledger.owners[input.owner_id]
    } }, deferred, "candidate_unavailable", nowMs);
    return { ok: true, ledger: released, offer: released.offers[input.offer_id] };
  }
  if (input.action === "offer") {
    const asapDeadline = input.asap_search_expires_ms;
    if (asapDeadline != null && (!Number.isSafeInteger(asapDeadline) || !Number.isSafeInteger(input.asap_requested_ms) || input.asap_requested_ms > nowMs || asapDeadline !== input.asap_requested_ms + 6e5)) return fail22("dispatch_asap_deadline_invalid", 400);
    if (asapDeadline != null && asapDeadline <= nowMs && (!offer || PROVISIONAL.has(offer.state))) {
      return fail22("asap_search_expired");
    }
    const timeout = input.ack_timeout_ms ?? DISPATCH_ACK_TIMEOUT_MS;
    if (input.response_starts_on_display === true && (input.human_acceptance_required !== true || input.claims?.length !== 1)) return fail22("dispatch_delivery_invalid", 400);
    if (input.human_acceptance_required === true ? !Number.isSafeInteger(timeout) || timeout <= 0 || !Number.isSafeInteger(nowMs + timeout) : !Number.isInteger(timeout) || timeout < 3e4 || timeout > 18e4 || timeout < DISPATCH_ACK_TIMEOUT_MS && input.delivery_mode !== "live") return fail22("dispatch_delivery_invalid", 400);
    if (offer) {
      if (!PROVISIONAL.has(offer.state) && !["committing", "committed"].includes(offer.state)) return fail22("dispatch_offer_closed");
      if (JSON.stringify(prerequisites(offer)) !== JSON.stringify(prerequisites(input)) || offer.asap_search_expires_ms !== input.asap_search_expires_ms || offer.asap_requested_ms !== input.asap_requested_ms || JSON.stringify(offer.claims) !== JSON.stringify(input.claims) || offer.prerequisite_claim_id !== (input.prerequisite_claim_id || null) || offer.prerequisite_version !== (input.prerequisite_version ?? null) || offer.ack_timeout_ms !== timeout || Boolean(offer.amendment) !== Boolean(input.amendment) || Boolean(offer.human_acceptance_required) !== Boolean(input.human_acceptance_required) || Boolean(offer.response_starts_on_display) !== Boolean(input.response_starts_on_display) || offer.amendment && (offer.base_version !== input.base_version || JSON.stringify(offer.retained_claims) !== JSON.stringify(input.retained_claims))) return fail22("dispatch_offer_conflict");
      return { ok: true, ledger: next, offer };
    }
    if (Object.values(next.offers || {}).some((row) => row.owner_id === input.owner_id && ["offered", "received", "committing"].includes(row.state))) return fail22("dispatch_offer_pending");
    if (!input.amendment && Object.values(next.claims).some((claim) => claim.owner_id === input.owner_id)) return fail22("dispatch_offer_hard_assignment");
    if (typeof input.driver_id !== "string" || !input.driver_id || typeof input.vehicle_id !== "string" || !input.vehicle_id || !Array.isArray(input.claims) || ![1, 2].includes(input.claims.length) || input.claims.some((claim) => !claim.driver_id || !claim.vehicle_id || claim.active) || input.claims[0].driver_id !== input.driver_id || input.claims[0].vehicle_id !== input.vehicle_id || new Set(input.claims.map((claim) => claim.claim_id)).size !== input.claims.length) {
      return fail22("dispatch_offer_invalid", 400);
    }
    const positions = { ...drivers, ...driverPosition ? { [input.driver_id]: driverPosition } : {} };
    const freshness2 = resourceFresh(input, positions, dispatchDevices, nowMs);
    if (freshness2) return fail22(freshness2.reason === "device_unavailable" ? "dispatch_device_unavailable" : "dispatch_offer_location_stale");
    const held = input.amendment ? holdAmendmentClaims2(next, input, directRides) : capacityClaimDecision2(next, { ...input, action: "reserve", replace_owner: false }, directRides);
    if (!held.ok) return held;
    const created = {
      tenant_id: input.tenant_id,
      company_id: input.company_id,
      offer_id: input.offer_id,
      owner_id: input.owner_id,
      version: input.version,
      driver_id: input.driver_id,
      vehicle_id: input.vehicle_id,
      claims: input.claims,
      ...input.human_acceptance_required === true ? { human_acceptance_required: true } : {},
      ...input.response_starts_on_display === true ? { response_starts_on_display: true } : {},
      prerequisite_claim_id: input.prerequisite_claim_id || null,
      prerequisite_version: input.prerequisite_version ?? null,
      ...input.record_canonical_version ? {
        record_canonical_version: input.record_canonical_version,
        record_revision: input.record_revision,
        record_dispatch_basis: input.record_dispatch_basis
      } : {},
      ...input.prerequisites ? { prerequisites: input.prerequisites } : {},
      ...asapDeadline != null ? { asap_requested_ms: input.asap_requested_ms, asap_search_expires_ms: asapDeadline } : {},
      ...input.amendment ? { amendment: true, base_version: input.base_version, retained_claims: input.retained_claims } : {},
      state: "offered",
      created_at_ms: nowMs,
      ack_timeout_ms: timeout,
      ack_deadline_ms: Math.min(nowMs + (input.response_starts_on_display === true ? DISPATCH_ACK_TIMEOUT_MS : timeout), asapDeadline ?? Infinity)
    };
    for (const required2 of prerequisites(created)) {
      const prior2 = next.claims[required2.claim_id];
      if (!prior2?.active || prior2.driver_id !== required2.driver_id || prior2.vehicle_id !== required2.vehicle_id || !scopeMatches(prior2, input) || next.owners[prior2.owner_id]?.version !== required2.version || !dispatchOfferResources2(created).some((resource) => sameCapacityResource2(resource, required2))) {
        return fail22("dispatch_prerequisite_conflict");
      }
    }
    const claims = { ...held.ledger.claims };
    for (const claim of created.claims) claims[claim.claim_id] = { ...claims[claim.claim_id], offer_id: created.offer_id };
    return { ok: true, offer: created, ledger: {
      ...next,
      ...held.ledger,
      claims,
      offers: { ...next.offers, [created.offer_id]: created }
    } };
  }
  if (!offer) return fail22("dispatch_offer_missing", 404);
  if (input.action === "supersede") {
    const owner2 = next.owners[offer.owner_id];
    if (offer.state === "superseded") return { ok: true, ledger: next, offer };
    if (!["committed", "cancelled"].includes(offer.state) || !owner2 || owner2.version <= offer.version || owner2.pending || input.canonical_version !== owner2.version || Object.values(next.claims).some((claim) => claim.owner_id === offer.owner_id && claim.offer_id === offer.offer_id)) {
      return fail22("dispatch_superseded_unconfirmed");
    }
    const superseded = { ...offer, state: "superseded", reason: "canonical_reassignment", ended_at_ms: nowMs };
    return { ok: true, offer: superseded, ledger: { ...next, offers: { ...next.offers, [offer.offer_id]: superseded } } };
  }
  if (input.action === "abort") {
    const proof = input.canonical_resolution;
    if (offer.state === "aborted") return { ok: true, ledger: next, offer };
    if (!["committing", "committed"].includes(offer.state) && !(offer.state === "cancelled" && offer.reason === "canonical_release") || Object.values(next.claims).some((claim) => claim.owner_id === offer.owner_id && claim.offer_id !== offer.offer_id) || proof?.offer_id !== offer.offer_id || proof?.version !== offer.version || !Number.isInteger(proof.record_revision) || proof.record_revision < offer.version - 1 || proof.reason !== "terminal" || !["COMPLETED", "CANCELLED", "CANCELED", "NO_SHOW", "REJECTED", "EXPIRED"].includes(String(proof.status || "").toUpperCase())) return fail22("dispatch_abort_unconfirmed");
    const claims = Object.fromEntries(Object.entries(next.claims).filter(([, claim]) => !(claim.owner_id === offer.owner_id && claim.offer_id === offer.offer_id)));
    const aborted = { ...offer, state: "aborted", reason: "canonical_terminal", ended_at_ms: nowMs };
    return { ok: true, offer: aborted, ledger: {
      ...next,
      claims,
      owners: { ...next.owners, [offer.owner_id]: { ...next.owners[offer.owner_id], pending: false, released: true } },
      offers: { ...next.offers, [offer.offer_id]: aborted }
    } };
  }
  if (input.action === "revoke") {
    if (!PROVISIONAL.has(offer.state)) return fail22("dispatch_offer_hard_assignment");
    const reason = ["destination_changed", "forecast_late", "location_stale", "driver_declined"].includes(input.reason) ? input.reason : "revalidation_failed";
    return { ok: true, ledger: cancellation(next, offer, reason, nowMs), offer: { ...offer, state: "cancelled" } };
  }
  if (input.action === "decline") {
    if (!offer.human_acceptance_required || !PROVISIONAL.has(offer.state)) return fail22("dispatch_offer_closed");
    return { ok: true, ledger: cancellation(next, offer, "driver_declined", nowMs, input.driver_id), offer: { ...offer, state: "cancelled" } };
  }
  if (!["ack", "accept"].includes(input.action)) return fail22("dispatch_offer_invalid", 400);
  if (input.action === "accept" && (!offer.human_acceptance_required || !input.execution_identity || input.execution_identity.driver_id !== input.driver_id || input.execution_identity.vehicle_id !== input.vehicle_id || !scopeMatches(input.execution_identity, input))) return fail22("dispatch_human_acceptance_required");
  if (!["offered", "received", "committing", "committed"].includes(offer.state)) return fail22("dispatch_offer_closed");
  if (["committing", "committed"].includes(offer.state)) return { ok: true, ledger: next, offer };
  if (!scopeMatches(driverPosition, input) || driverPosition.driver_id !== input.driver_id || driverPosition.vehicle_id !== input.vehicle_id || !freshDispatchPosition(driverPosition, nowMs)) return fail22("dispatch_offer_location_stale");
  if (!input.device_key || !driverDispatchDevices3(dispatchDevices, input, input.driver_id, nowMs, input.device_key).length) return fail22("dispatch_device_unavailable");
  if (directRides.some((ride) => scopeMatches(ride, input) && touches(offer, ride))) return fail22("dispatch_driver_busy");
  const required = prerequisites(offer).filter((row) => row.driver_id === input.driver_id);
  const prior = required.map((row) => ({ row, claim: next.claims[row.claim_id] })).filter((pair) => pair.claim);
  if (prior.some(({ row, claim }) => !claim.active || next.owners[claim.owner_id]?.version !== row.version || !scopeMatches(claim, input) || !sameCapacityResource2(claim, input))) return fail22("dispatch_prerequisite_conflict");
  const previousReceipt = offer.receipts?.[input.driver_id];
  const firstDisplay = offer.response_starts_on_display === true && previousReceipt?.displayed_at_ms == null;
  const displayedAt = firstDisplay ? nowMs : previousReceipt?.displayed_at_ms;
  const accepted = input.action === "accept" || previousReceipt?.accepted === true;
  const receipts = { ...offer.receipts, [input.driver_id]: {
    at_ms: nowMs,
    ready: prior.length === 0 && (!offer.human_acceptance_required || accepted),
    ...offer.human_acceptance_required ? {
      accepted,
      ...offer.response_starts_on_display === true ? { displayed_at_ms: displayedAt } : {},
      ...input.action === "accept" ? { execution_identity: input.execution_identity } : previousReceipt?.execution_identity ? { execution_identity: previousReceipt.execution_identity } : {}
    } : {}
  } };
  const resources = dispatchOfferResources2(offer);
  const received = {
    ...offer,
    receipts,
    state: "received",
    acknowledged_at_ms: offer.acknowledged_at_ms || nowMs,
    ...firstDisplay ? { ack_deadline_ms: Math.min(nowMs + offer.ack_timeout_ms, offer.asap_search_expires_ms ?? Infinity) } : {}
  };
  if (!resources.every((resource) => receipts[resource.driver_id]?.ready === true)) {
    return { ok: true, ledger: { ...next, offers: { ...next.offers, [offer.offer_id]: received } }, offer: received };
  }
  if (Object.values(next.claims).some((claim) => claim.owner_id !== offer.owner_id && claim.active && scopeMatches(claim, input) && touches(offer, claim))) return fail22("dispatch_driver_busy");
  const freshness = resourceFresh(offer, { ...drivers, ...driverPosition ? { [input.driver_id]: driverPosition } : {} }, dispatchDevices, nowMs);
  if (freshness) return fail22(freshness.reason === "device_unavailable" ? "dispatch_device_unavailable" : "dispatch_offer_location_stale");
  const promoted = offer.amendment ? promoteAmendmentClaims2(next, offer, directRides) : { ok: true, ledger: next };
  if (!promoted.ok) return promoted;
  const committedClaims = { ...promoted.ledger.claims };
  for (const claim of offer.claims) committedClaims[claim.claim_id] = { ...committedClaims[claim.claim_id], offer_id: offer.offer_id };
  const committing = { ...received, state: "committing" };
  const eventId = `${offer.offer_id}:commit`;
  return { ok: true, offer: committing, ledger: {
    ...next,
    claims: committedClaims,
    owners: { ...promoted.ledger.owners, [offer.owner_id]: { ...promoted.ledger.owners[offer.owner_id], pending: true } },
    offers: { ...next.offers, [offer.offer_id]: committing },
    dispatch_events: { ...next.dispatch_events, [eventId]: {
      ...committing,
      event_id: eventId,
      type: "assignment_commit",
      state: "pending",
      created_at_ms: nowMs
    } }
  } };
}
var CONFIRMED_RECHECK_MS = 6e4;
var CONFIRMED_RECHECK_HORIZON_MS2 = 15 * 6e4;
function monitoredClaims(ledger, offer) {
  const owner2 = ledger.owners[offer.owner_id];
  const split = offer.claims?.every((claim) => ["OUTBOUND", "RETURN"].some((type) => claim.claim_id === `${offer.owner_id}:${type}`));
  if (offer.state !== "committed" || offer.revalidation_paused_reason === "pickup_overdue" || !Number.isSafeInteger(offer.record_canonical_version) || offer.record_canonical_version < 1 || !Number.isSafeInteger(offer.version) || !Number.isSafeInteger(owner2?.version) || owner2.version < offer.version || !scopeMatches(owner2, offer) || owner2.pending || owner2.released || !split && owner2.version !== offer.version) return [];
  return (offer.claims || []).filter((claim) => {
    const held = ledger.claims[claim.claim_id];
    return held?.owner_id === offer.owner_id && scopeMatches(held, offer) && (split || held.offer_id === offer.offer_id) && held.driver_id === claim.driver_id && held.vehicle_id === claim.vehicle_id && held.start_ms === claim.start_ms && held.end_ms === claim.end_ms && Number.isFinite(claim.start_ms) && Number.isFinite(claim.end_ms) && !held.active && !held.retiring;
  });
}
function confirmedAssignments(ledger) {
  return Object.values(ledger.offers || {}).filter((offer) => monitoredClaims(ledger, offer).length);
}
function confirmedRecheckAt(offer, ledger) {
  return Math.max(
    Math.min(...monitoredClaims(ledger, offer).map((claim) => claim.start_ms)) - CONFIRMED_RECHECK_HORIZON_MS2,
    (offer.last_revalidated_at_ms || 0) + CONFIRMED_RECHECK_MS
  );
}
function queueConfirmedSuccessorChecks2(ledger, nowMs, changed = null) {
  let next = ledger;
  for (const offer of confirmedAssignments(ledger)) {
    const eventId = `${offer.offer_id}:revalidate`;
    const previous = next.dispatch_events?.[eventId];
    const affected = changed && monitoredClaims(next, offer).some((claim) => changed.resources.some((resource) => scopeMatches(resource, offer) && resource.claim_id !== claim.claim_id && sameCapacityResource2(claim, resource)));
    if (changed && !affected || previous?.state === "pending" || !affected && confirmedRecheckAt(offer, next) > nowMs) continue;
    const event = {
      ...offer,
      event_id: eventId,
      type: "assignment_revalidate",
      state: "pending",
      revalidation_claim_ids: monitoredClaims(next, offer).map((claim) => claim.claim_id),
      event_generation: (previous?.event_generation || 0) + 1,
      created_at_ms: nowMs
    };
    next = { ...next, dispatch_events: { ...next.dispatch_events, [eventId]: event } };
  }
  return next;
}
function acknowledgeDispatchEvent2(ledger, input) {
  const event = ledger.dispatch_events?.[input.event_id];
  if (!event || !scopeMatches(event, input) || event.offer_id !== input.offer_id || event.version !== input.version || event.owner_id !== input.owner_id) return fail22("dispatch_event_conflict");
  const offer = ledger.offers?.[event.offer_id];
  if (event.type === "assignment_commit" && !["committed", "aborted", "superseded"].includes(offer?.state)) return fail22("dispatch_commit_unconfirmed");
  if (event.type === "assignment_revalidate" && input.event_generation !== event.event_generation) return fail22("dispatch_event_conflict");
  return { ok: true, ledger: {
    ...ledger,
    ...event.type === "assignment_revalidate" && offer ? { offers: {
      ...ledger.offers,
      [offer.offer_id]: {
        ...offer,
        last_revalidated_at_ms: event.created_at_ms,
        ...input.pickup_timing_attention === "pickup_overdue" ? { revalidation_paused_reason: "pickup_overdue" } : {}
      }
    } } : {},
    dispatch_events: {
      ...ledger.dispatch_events,
      [event.event_id]: { ...event, state: "delivered" }
    }
  } };
}
function nextDispatchAlarm2(ledger, drivers = {}, dispatchDevices) {
  const deadlines = Object.values(ledger.offers || {}).filter((offer) => PROVISIONAL.has(offer.state)).flatMap((offer) => {
    return [offer.ack_deadline_ms, ...dispatchOfferResources2(offer).flatMap((resource) => {
      const position = drivers[resource.driver_id];
      const deviceEnd = dispatchDeviceDeadline2(dispatchDevices, offer, resource.driver_id, Date.now());
      return [...deviceEnd == null ? [] : [deviceEnd + 1], ...[position?.position_captured_at || position?.captured_at, position?.last_seen_at].map((value) => Date.parse(value || "") + DISPATCH_POSITION_TTL_MS + 1).filter(Number.isFinite)];
    })];
  });
  deadlines.push(...confirmedAssignments(ledger).filter((offer) => ledger.dispatch_events?.[`${offer.offer_id}:revalidate`]?.state !== "pending").map((offer) => Math.max(Date.now() + 1, confirmedRecheckAt(offer, ledger))));
  return deadlines.length ? Math.min(...deadlines) : null;
}
var LOCATION_RATE_LIMIT_PER_MINUTE = 12;
var LOCATION_DEDUPE_METERS = 15;
var LOCATION_DEDUPE_MS = 2e4;
var LOCATION_FUTURE_SKEW_MS = 12e4;
var LOCATION_STALE_DEFAULT_SECONDS = 300;
var LOCATION_STALE_MIN_SECONDS = 30;
var LOCATION_STALE_MAX_SECONDS = 3600;
var LOCATION_MAX_ACCURACY_M = 150;
var STORAGE_KEY = "drivers_v1";
var DIRECT_OCCUPANCY_KEY = "direct_occupancy_active_v1";
var DISPATCH_DEVICES_KEY = "dispatch_devices_v1";
function clampFreshnessSeconds(value) {
  if (value === void 0 || value === null || value === "") return LOCATION_STALE_DEFAULT_SECONDS;
  const n = Number(value);
  if (!Number.isFinite(n)) return LOCATION_STALE_DEFAULT_SECONDS;
  return Math.min(LOCATION_STALE_MAX_SECONDS, Math.max(LOCATION_STALE_MIN_SECONDS, Math.floor(n)));
}
function haversineMeters(lat1, lon1, lat2, lon2) {
  const r = 6371e3;
  const p1 = lat1 * Math.PI / 180;
  const p2 = lat2 * Math.PI / 180;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(p1) * Math.cos(p2) * Math.sin(dLon / 2) ** 2;
  return 2 * r * Math.asin(Math.min(1, Math.sqrt(h)));
}
function finiteCoord(value, min, max) {
  const n = Number(value);
  if (!Number.isFinite(n) || n < min || n > max) return null;
  return n;
}
function validateLocationSample(input, nowMs) {
  const latitude = finiteCoord(input?.latitude, -90, 90);
  const longitude = finiteCoord(input?.longitude, -180, 180);
  if (latitude === null || longitude === null) {
    return { ok: false, status: 400, error: "location_invalid" };
  }
  if (input?.accuracy !== void 0 && input?.accuracy !== null && input?.accuracy !== "") {
    const accuracy = Number(input.accuracy);
    if (!Number.isFinite(accuracy) || accuracy < 0 || accuracy > LOCATION_MAX_ACCURACY_M) {
      return { ok: false, status: 400, error: "location_accuracy_rejected" };
    }
  }
  let capturedMs = nowMs;
  if (input?.captured_at) {
    capturedMs = Date.parse(String(input.captured_at));
    if (!Number.isFinite(capturedMs)) {
      return { ok: false, status: 400, error: "location_captured_at_invalid" };
    }
  }
  if (capturedMs - nowMs > LOCATION_FUTURE_SKEW_MS) {
    return { ok: false, status: 400, error: "location_captured_at_invalid" };
  }
  return { ok: true, latitude, longitude, capturedMs };
}
function pruneHits(hits, nowMs) {
  const cutoff = nowMs - 6e4;
  return (Array.isArray(hits) ? hits : []).filter((ts) => Number(ts) > cutoff);
}
function matchesTrackingScope(row, context3, grant) {
  return Boolean(row && context3 && grant && !grant.leg_scope_retired && typeof context3.booking_id === "string" && context3.booking_id.length > 0 && typeof context3.operational_leg === "string" && context3.operational_leg.length > 0 && Number.isInteger(context3.assignment_version) && context3.assignment_version > 0 && row.tenant_id === grant.tenant_id && row.company_id === grant.company_id && row.driver_id === grant.driver_id && context3.booking_id === grant.booking_id && context3.operational_leg === grant.operational_leg && context3.assignment_version === grant.assignment_version);
}
function applyLocationUpdate(drivers, input, nowMs) {
  const next = { ...drivers };
  const driverId = String(input.driver_id || "");
  const companyId = String(input.company_id || "");
  if (!driverId || !companyId) {
    return { drivers: next, result: { ok: false, status: 400, error: "location_identity_missing" } };
  }
  const checked = validateLocationSample(input, nowMs);
  if (!checked.ok) {
    return { drivers: next, result: checked };
  }
  const current = next[driverId] ? { ...next[driverId] } : null;
  const hits = pruneHits(current?.recent_hits, nowMs);
  if (hits.length >= LOCATION_RATE_LIMIT_PER_MINUTE) {
    const oldest = hits[0];
    const retryAfter = Math.max(1, Math.ceil((oldest + 6e4 - nowMs) / 1e3));
    return {
      drivers: next,
      result: {
        ok: false,
        status: 429,
        error: "location_rate_limited",
        retry_after_seconds: retryAfter
      }
    };
  }
  hits.push(nowMs);
  const staleLimitMs = clampFreshnessSeconds(input.freshness_seconds) * 1e3;
  if (nowMs - checked.capturedMs > staleLimitMs) {
    if (current) next[driverId] = { ...current, recent_hits: hits };
    return {
      drivers: next,
      result: { ok: true, applied: false, reason: "captured_at_too_old", driver_id: driverId }
    };
  }
  if (current && Number.isFinite(current.captured_ms)) {
    if (checked.capturedMs < current.captured_ms) {
      next[driverId] = { ...current, recent_hits: hits };
      return {
        drivers: next,
        result: { ok: true, applied: false, reason: "older_captured_at", driver_id: driverId }
      };
    }
    if (checked.capturedMs === current.captured_ms && (sameLocationOwner2(input.publication_owner, current.publication_owner) || !input.publication_owner && !current.publication_owner)) {
      const trackingStatus = input.tracking_status ? String(input.tracking_status) : "active";
      const contextChanged = JSON.stringify(input.tracking_context || null) !== JSON.stringify(current.tracking_context || null) || trackingStatus !== String(current.tracking_status || "active");
      if (contextChanged) {
        next[driverId] = {
          ...current,
          recent_hits: hits,
          tracking_context: input.tracking_context || null,
          tracking_status: trackingStatus,
          availability_status: input.availability_status ? String(input.availability_status) : current.availability_status
        };
        return { drivers: next, result: { ok: true, applied: true, reason: "tracking_context_updated", driver_id: driverId } };
      }
      next[driverId] = { ...current, recent_hits: hits };
      return {
        drivers: next,
        result: { ok: true, applied: false, reason: "duplicate_captured_at", driver_id: driverId }
      };
    }
    const moved = haversineMeters(current.latitude, current.longitude, checked.latitude, checked.longitude);
    const statusChanged = String(input.tracking_status || "") !== String(current.tracking_status || "") || JSON.stringify(input.tracking_context || null) !== JSON.stringify(current.tracking_context || null) || JSON.stringify(input.publication_owner || null) !== JSON.stringify(current.publication_owner || null) || current.location_withdrawn === true;
    if (!statusChanged && moved <= LOCATION_DEDUPE_METERS && checked.capturedMs - current.captured_ms <= LOCATION_DEDUPE_MS) {
      next[driverId] = {
        ...current,
        recent_hits: hits,
        last_seen_at: new Date(nowMs).toISOString()
      };
      return {
        drivers: next,
        result: {
          ok: true,
          applied: false,
          liveness_updated: true,
          reason: "duplicate_location",
          driver_id: driverId
        }
      };
    }
  }
  const accuracy = input.accuracy === void 0 || input.accuracy === null || input.accuracy === "" ? null : Number(input.accuracy);
  next[driverId] = {
    driver_id: driverId,
    tenant_id: input.tenant_id || null,
    company_id: companyId,
    vehicle_id: input.vehicle_id ? String(input.vehicle_id) : null,
    latitude: checked.latitude,
    longitude: checked.longitude,
    accuracy,
    heading: Number.isFinite(Number(input.heading)) ? Number(input.heading) : null,
    speed: Number.isFinite(Number(input.speed)) ? Number(input.speed) : null,
    captured_at: new Date(checked.capturedMs).toISOString(),
    captured_ms: checked.capturedMs,
    position_captured_at: new Date(checked.capturedMs).toISOString(),
    last_seen_at: new Date(nowMs).toISOString(),
    received_at: new Date(nowMs).toISOString(),
    availability_status: input.availability_status ? String(input.availability_status) : null,
    tracking_status: input.tracking_status ? String(input.tracking_status) : "active",
    tracking_context: input.tracking_context || null,
    publication_owner: input.publication_owner || null,
    ...current?.retired_publications ? { retired_publications: current.retired_publications } : {},
    recent_hits: hits
  };
  return {
    drivers: next,
    result: { ok: true, applied: true, driver_id: driverId }
  };
}
function projectCompanyLive(drivers, { tenantId, companyId, nowMs, freshnessSeconds }) {
  const freshness = clampFreshnessSeconds(freshnessSeconds);
  const list = [];
  for (const row of Object.values(drivers || {})) {
    if (!row || row.location_withdrawn === true || row.company_id !== companyId || row.tenant_id !== tenantId) continue;
    const positionCapturedAt = row.position_captured_at || row.captured_at || "";
    const lastSeenAt = row.last_seen_at || row.received_at || "";
    const positionAgeMs = nowMs - Date.parse(positionCapturedAt);
    const seenAgeMs = nowMs - Date.parse(lastSeenAt);
    const positionStale = !Number.isFinite(positionAgeMs) || positionAgeMs > freshness * 1e3;
    const locationFeedStale = !Number.isFinite(seenAgeMs) || seenAgeMs > freshness * 1e3;
    const accuracyOk = row.accuracy == null || Number(row.accuracy) >= 0 && Number(row.accuracy) <= LOCATION_MAX_ACCURACY_M;
    list.push({
      driver_id: row.driver_id,
      tenant_id: row.tenant_id,
      company_id: row.company_id,
      vehicle_id: row.vehicle_id ?? null,
      latitude: row.latitude,
      longitude: row.longitude,
      accuracy: row.accuracy ?? null,
      heading: row.heading ?? null,
      speed: row.speed ?? null,
      captured_at: positionCapturedAt,
      position_captured_at: positionCapturedAt,
      last_seen_at: lastSeenAt,
      received_at: row.received_at,
      availability_status: row.availability_status ?? null,
      tracking_status: row.tracking_status ?? null,
      tracking_context: row.tracking_context || null,
      location_feed: locationFeedStale ? "stale" : "live",
      stale: locationFeedStale,
      position_stale: positionStale,
      reliable_for_eta: !positionStale && accuracyOk
    });
  }
  list.sort((a, b) => String(a.driver_id).localeCompare(String(b.driver_id)));
  return {
    ok: true,
    tenant_id: tenantId,
    company_id: companyId,
    freshness_seconds: freshness,
    drivers: list
  };
}
function persistable(drivers) {
  const out = {};
  for (const [id22, row] of Object.entries(drivers || {})) {
    if (!row) continue;
    const copy2 = { ...row };
    delete copy2.recent_hits;
    out[id22] = copy2;
  }
  return out;
}
var CompanyTrackingRoom = class {
  constructor(state, env) {
    this.state = state;
    this.env = env;
    this.drivers = null;
    this.driverRows = createPerDriverState2(state.storage, STORAGE_KEY, "tracking-driver:v2:", {
      onWrite: env.TENANT_COST_METRICS_ENABLED === "1" ? async (row, writes, bytes4) => {
        if (!row?.tenant_id || !row?.company_id) return;
        await emitTenantCostMetric2(env, row, "storage_writes", writes);
        await emitTenantCostMetric2(env, row, "storage_bytes", bytes4);
      } : void 0
    });
    this.driversLoaded = null;
    this.grants = null;
    this.grantsLoaded = null;
    this.directOccupancy = null;
    this.directOccupancyLoaded = null;
    this.directOccupancyQueue = Promise.resolve();
    this.capacity = null;
    this.capacityLoaded = null;
    this.dispatchDrain = null;
    this.dispatchDevices = null;
    this.dispatchDevicesLoaded = null;
    this.hits = /* @__PURE__ */ new Map();
  }
  async load() {
    if (!this.drivers) {
      this.driversLoaded ||= this.driverRows.load().then((stored) => {
        this.drivers = stored && typeof stored === "object" ? stored : {};
      }).catch((error) => {
        this.driversLoaded = null;
        throw error;
      });
      await this.driversLoaded;
    }
    if (!this.grants) {
      this.grantsLoaded ||= readCustomerGrantSnapshot2(this.state.storage).then((stored) => {
        this.grants = stored;
      }).catch((error) => {
        this.grantsLoaded = null;
        throw error;
      });
      await this.grantsLoaded;
    }
    if (!this.directOccupancy) {
      this.directOccupancyLoaded ||= this.state.storage.get(DIRECT_OCCUPANCY_KEY).then((stored) => {
        this.directOccupancy = stored || {};
      }).catch((error) => {
        this.directOccupancyLoaded = null;
        throw error;
      });
      await this.directOccupancyLoaded;
    }
    if (!this.capacity) {
      this.capacityLoaded ||= readCapacitySnapshot2(this.state.storage).then((stored) => {
        this.capacity = stored;
      }).catch((error) => {
        this.capacityLoaded = null;
        throw error;
      });
      await this.capacityLoaded;
    }
    if (!this.dispatchDevices) {
      this.dispatchDevicesLoaded ||= this.state.storage.get(DISPATCH_DEVICES_KEY).then((stored) => {
        this.dispatchDevices = stored || { devices: {} };
      }).catch((error) => {
        this.dispatchDevicesLoaded = null;
        throw error;
      });
      await this.dispatchDevicesLoaded;
    }
    if (this.capacity.direct_holds) this.directOccupancy = this.capacity.direct_holds;
  }
  capacityScopeAllowed(input) {
    const bound = this.capacity.scope || this.capacity.baseline || Object.values(this.capacity.owners)[0] || Object.values(this.directOccupancy)[0] || this.dispatchDevices.scope || this.grants.scope || Object.values(this.grants.grants || {}).find((row) => row?.tenant_id && row?.company_id);
    return !bound || bound.tenant_id === input.tenant_id && bound.company_id === input.company_id;
  }
  async hydrateCapacity(identities, scope2) {
    this.capacity = await hydrateCapacityRecords2(this.state.storage, this.capacity, identities, scope2);
  }
  async writeCapacity(next, scope2) {
    const bound = this.capacity.scope || scope2;
    const stored = { ...next, ...bound ? { scope: { tenant_id: bound.tenant_id, company_id: bound.company_id } } : {} };
    const expiry = nextDispatchAlarm2(stored, this.drivers, this.dispatchDevices);
    const pendingEvents = Object.values(stored.dispatch_events || {}).some((event) => event.state === "pending");
    const delivery = pendingEvents ? Date.now() + 1e3 : null;
    const deadlines = [expiry, delivery].filter((value) => value != null);
    const deadline = deadlines.length ? Math.min(...deadlines) : null;
    if (deadline != null) await this.state.storage.setAlarm(deadline);
    this.capacity = await writeCapacitySnapshot2(this.state.storage, stored, this.capacity, Date.now());
    if (stored.direct_holds) this.directOccupancy = stored.direct_holds;
    if (pendingEvents && this.env.BOOKING_API && this.env.ADMIN_TOKEN && this.state.waitUntil) {
      this.state.waitUntil(Promise.resolve().then(() => this.drainDispatchEvents()));
    }
  }
  async drainDispatchEvents() {
    if (this.dispatchDrain) return this.dispatchDrain;
    const run = async () => {
      let events = [];
      const choose = this.directOccupancyQueue.then(async () => {
        const pending = Object.values(this.capacity.dispatch_events || {}).filter((event) => event.state === "pending").sort((a, b) => a.created_at_ms - b.created_at_ms || a.event_id.localeCompare(b.event_id));
        const last = pending.findIndex((event) => event.event_id === this.capacity.dispatch_delivery_cursor);
        events = [...pending.slice(last + 1), ...pending.slice(0, last + 1)].slice(0, 8);
        if (events.length && this.env.BOOKING_API && this.env.ADMIN_TOKEN) await this.writeCapacity({
          ...this.capacity,
          dispatch_delivery_cursor: events.at(-1).event_id
        });
      });
      this.directOccupancyQueue = choose.catch(() => {
      });
      await choose;
      for (const event of events) {
        if (!this.env.BOOKING_API || !this.env.ADMIN_TOKEN) break;
        try {
          const response2 = await this.env.BOOKING_API.fetch(new Request("https://booking/track/dispatch/event", {
            method: "POST",
            headers: { "content-type": "application/json", "x-admin-token": this.env.ADMIN_TOKEN },
            body: JSON.stringify({ tenant_id: event.tenant_id, company_id: event.company_id, event_id: event.event_id }),
            signal: AbortSignal.timeout(8e3)
          }));
          const result2 = await response2.json();
          if (!response2.ok || result2.ok !== true) continue;
        } catch (_) {
          continue;
        }
      }
      const reschedule = this.directOccupancyQueue.then(async () => {
        const pending = Object.values(this.capacity.dispatch_events || {}).some((event) => event.state === "pending");
        const expiry = nextDispatchAlarm2(this.capacity, this.drivers, this.dispatchDevices);
        const delivery = pending ? Date.now() + 6e4 : null;
        const deadlines = [expiry, delivery].filter((value) => value != null);
        if (deadlines.length) await this.state.storage.setAlarm(Math.min(...deadlines));
        else if (this.state.storage.deleteAlarm) await this.state.storage.deleteAlarm();
      });
      this.directOccupancyQueue = reschedule.catch(() => {
      });
      await reschedule;
    };
    this.dispatchDrain = run().finally(() => {
      this.dispatchDrain = null;
    });
    return this.dispatchDrain;
  }
  async expireOffers(nowMs) {
    const next = queueConfirmedSuccessorChecks2(
      revalidateDispatchOffers2(this.capacity, this.drivers, nowMs, this.dispatchDevices),
      nowMs
    );
    if (next !== this.capacity) await this.writeCapacity(next);
  }
  async alarm() {
    await this.load();
    const operation = this.directOccupancyQueue.then(async () => {
      await this.expireOffers(Date.now());
      const next = nextDispatchAlarm2(this.capacity, this.drivers, this.dispatchDevices);
      if (next != null) await this.state.storage.setAlarm(next);
    });
    this.directOccupancyQueue = operation.catch(() => {
    });
    await operation;
    await this.drainDispatchEvents();
  }
  async fetch(request) {
    if (request.method === "POST" && new URL(request.url).pathname === "/navigation-authority") {
      const run = this.directOccupancyQueue.then(async () => {
        const { readRoomNavigationAuthorityV1: readRoomNavigationAuthorityV12 } = await Promise.resolve().then(() => (init_national_navigation_authorization_v1(), national_navigation_authorization_v1_exports));
        const body = await request.clone().json().catch(() => null);
        return readRoomNavigationAuthorityV12(this.state, this.env, request, body);
      });
      this.directOccupancyQueue = run.then(() => void 0, () => void 0);
      return run;
    }
    if (request.method === "POST" && new URL(request.url).pathname === "/canonical-inspection") {
      const { inspectCapacityWithoutMutation: inspectCapacityWithoutMutation2 } = await Promise.resolve().then(() => (init_canonical_booking_inspection(), canonical_booking_inspection_exports));
      const body = await request.clone().json().catch(() => null);
      return inspectCapacityWithoutMutation2(this.state, this.env, request, body);
    }
    await this.load();
    const url = new URL(request.url);
    const nowMs = Date.now();
    if (request.method === "POST" && url.pathname === "/customer-route") {
      if (this.env.CUSTOMER_ETA_SHARED_ROOM_ENABLED !== "1") return Response.json({ ok: false, error: "shared_eta_disabled" }, { status: 503 });
      const input = await request.json();
      const liveUrl = new URL(url);
      liveUrl.pathname = "/customer-live";
      const read = () => this.fetch(new Request(liveUrl, { method: "GET" }));
      const initial = await read();
      if (!initial.ok) return initial;
      const snapshot = await initial.json();
      if (!snapshot.position || !["en_route_pickup", "in_progress"].includes(snapshot.tracking_phase)) return Response.json({ ok: true, eta: null });
      if (input.response_version !== snapshot.response_version) return Response.json({ ok: false, error: "assignment_changed" }, { status: 409 });
      const grant = await readStoredCustomerGrant2(
        this.state.storage,
        this.grants,
        grantKey2(url.searchParams.get("booking_id"), url.searchParams.get("operational_leg")),
        this.grants.scope
      );
      const target2 = snapshot.tracking_phase === "in_progress" ? "destination" : "pickup";
      this.sharedEta ||= createAdaptiveEtaCache2((args) => typeof this.env.__customerEtaFetch === "function" ? this.env.__customerEtaFetch(args) : mapboxDispatchRouteEta2(this.env, { ...args, includeGeometry: true }));
      const eta = await this.sharedEta.resolve({
        origin: snapshot.position,
        destination: target2 === "destination" ? grant.destination : grant.pickup,
        target: target2,
        context: {
          tenant_id: grant.tenant_id,
          company_id: grant.company_id,
          booking_id: grant.booking_id,
          operational_leg: grant.operational_leg || "primary",
          session_id: grant.session_id,
          assignment_version: grant.assignment_version,
          lifecycle_seq: grant.lifecycle_seq
        },
        observability: { scope: { tenant_id: grant.tenant_id, company_id: grant.company_id }, operation: "customer_live_eta" }
      });
      const final = await read();
      if (!final.ok) return final;
      const latest = await final.json();
      if (!latest.position || latest.response_version !== snapshot.response_version || latest.tracking_phase !== snapshot.tracking_phase)
        return Response.json({ ok: false, error: "assignment_changed" }, { status: 409 });
      return Response.json({ ok: true, eta });
    }
    if (request.method === "POST" && url.pathname === "/vehicle-device") {
      if (this.env?.COMPANY_VEHICLE_OPERATIONS_ENABLED !== "1") return Response.json({ ok: false, error: "vehicle_operations_disabled" }, { status: 503 });
      const input = await request.json();
      const operation = this.directOccupancyQueue.then(async () => {
        if (!this.capacityScopeAllowed(input)) return Response.json({ ok: false, error: "vehicle_device_scope_mismatch" }, { status: 403 });
        if (input.action === "transition") {
          const device = await this.state.storage.get(`vehicle_device_v1:${input.device_id}`);
          if (device && !device.revoked && Object.values(this.drivers || {}).some((row) => [device.vehicle_id, input.operation === "switch" ? input.vehicle_id : null].includes(row.vehicle_id) && row.location_withdrawn !== true && boundLocationOwner2(row.publication_owner, Date.now())))
            return Response.json({ ok: false, error: "gps_publication_blocks_device_change" }, { status: 409 });
        }
        const result2 = await vehicleDeviceCommand2(this.state.storage, input, Date.now());
        if (result2.ok && input.action === "transition") {
          this.dispatchDevicesLoaded = null;
          this.dispatchDevices = await this.state.storage.get(DISPATCH_DEVICES_KEY) || { devices: {} };
        }
        if (result2.ok && input.action === "revoke") {
          this.dispatchDevices = null;
          this.dispatchDevicesLoaded = null;
          this.dispatchDevices = await this.state.storage.get(DISPATCH_DEVICES_KEY) || { devices: {} };
          await this.expireOffers(Date.now());
        }
        return Response.json(result2, { status: result2.ok ? 200 : 403 });
      });
      this.directOccupancyQueue = operation.catch(() => {
      });
      return operation;
    }
    if (request.method === "POST" && url.pathname === "/vehicle-duty-projection") {
      if (this.env?.COMPANY_VEHICLE_OPERATIONS_ENABLED !== "1") return Response.json({ ok: false, error: "vehicle_operations_disabled" }, { status: 503 });
      const input = await request.json();
      const operation = this.directOccupancyQueue.then(async () => {
        if (!this.capacityScopeAllowed(input)) return Response.json({ ok: false, error: "duty_scope_mismatch" }, { status: 403 });
        const pending = await this.state.storage.get(VEHICLE_DUTY_PROJECTION_KEY2);
        if (pending && (pending.tenant_id !== input.tenant_id || pending.company_id !== input.company_id)) return Response.json({ ok: false, error: "duty_scope_mismatch" }, { status: 403 });
        if (input.confirm_version != null) {
          if (pending && pending.version !== input.confirm_version) return Response.json({ ok: false, error: "duty_projection_conflict" }, { status: 409 });
          if (pending) await this.state.storage.delete(VEHICLE_DUTY_PROJECTION_KEY2);
          return Response.json({ ok: true });
        }
        return Response.json({ ok: true, pending: pending ?? null });
      });
      this.directOccupancyQueue = operation.catch(() => {
      });
      return operation;
    }
    if (request.method === "POST" && url.pathname === "/vehicle-duty-admin-state") {
      if (this.env?.COMPANY_VEHICLE_OPERATIONS_ENABLED !== "1") return Response.json({ ok: false, error: "vehicle_operations_disabled" }, { status: 503 });
      const input = await request.json();
      const operation = this.directOccupancyQueue.then(async () => {
        if (input.role !== "company_admin" || !this.capacityScopeAllowed(input)) return Response.json({ ok: false, error: "duty_scope_mismatch" }, { status: 403 });
        const stored = await this.state.storage.get(VEHICLE_DUTY_STATE_KEY2);
        if (stored && (stored.tenant_id !== input.tenant_id || stored.company_id !== input.company_id)) return Response.json({ ok: false, error: "duty_scope_mismatch" }, { status: 403 });
        return Response.json({
          ok: true,
          version: stored?.version ?? 0,
          vehicle_id: input.vehicle_id,
          duties: (stored?.duties || []).filter((row) => row.vehicle_id === input.vehicle_id)
        });
      });
      this.directOccupancyQueue = operation.catch(() => {
      });
      return operation;
    }
    if (request.method === "POST" && url.pathname === "/vehicle-duty-recover") {
      if (this.env?.COMPANY_VEHICLE_OPERATIONS_ENABLED !== "1") return Response.json({ ok: false, error: "vehicle_operations_disabled" }, { status: 503 });
      const input = await request.json();
      const operation = this.directOccupancyQueue.then(async () => {
        if (input.role !== "company_admin" || !this.capacityScopeAllowed(input) || !["device_lost", "device_replaced"].includes(input.reason)) return Response.json({ ok: false, error: "duty_recovery_invalid" }, { status: 403 });
        const actor = { tenant_id: input.tenant_id, company_id: input.company_id, driver_id: input.driver_id };
        if (!/^[a-zA-Z0-9_.-]{1,96}$/.test(input.device_id || "")) return Response.json({ ok: false, error: "duty_recovery_invalid" }, { status: 400 });
        const device = await this.state.storage.get(`vehicle_device_v1:${input.device_id}`);
        if (!device || device.vehicle_id !== input.vehicle_id || !device.revoked && device.expires_at_ms > Date.now()) {
          return Response.json({ ok: false, error: "device_must_be_unpaired_for_recovery" }, { status: 409 });
        }
        const audit = { role: "company_admin", company_id: input.company_id, reason: input.reason, device_id: input.device_id };
        const command = { ...input, action: "end" };
        const replay = await vehicleDutyCommandReplay2(this.state.storage, command, actor, { recoveryAudit: audit });
        if (replay) return Response.json(replay, { status: replay.ok ? 200 : 409 });
        const dutyState = await this.state.storage.get(VEHICLE_DUTY_STATE_KEY2);
        const targetDuty = dutyState?.duties?.find((row) => row.duty_id === input.duty_id && row.driver_id === input.driver_id && row.vehicle_id === input.vehicle_id);
        if (targetDuty?.vehicle_device_id && targetDuty.vehicle_device_id !== input.device_id) {
          return Response.json({ ok: false, error: "duty_recovery_device_mismatch" }, { status: 409 });
        }
        if (this.capacity.baseline?.tenant_id !== input.tenant_id || this.capacity.baseline?.company_id !== input.company_id) {
          return Response.json({ ok: false, error: "capacity_baseline_required" }, { status: 409 });
        }
        const now = Date.now();
        const matches32 = (row) => row.driver_id === input.driver_id || row.vehicle_id === input.vehicle_id;
        const busy = Object.values(this.directOccupancy).some(matches32) || Object.values(this.capacity.claims || {}).some((row) => matches32(row) && (row.active === true || row.end_ms > now || overdueCapacityHold2(row, now, this.capacity.owners?.[row.owner_id])));
        if (busy) return Response.json({ ok: false, error: "active_ride_blocks_duty_change" }, { status: 409 });
        if (Object.values(this.dispatchDevices?.devices || {}).some((row) => row.driver_id === input.driver_id && row.valid_until_ms > now)) {
          return Response.json({ ok: false, error: "connected_device_blocks_duty_recovery" }, { status: 409 });
        }
        const result2 = await persistVehicleDutyCommand2(this.state.storage, command, actor, { projectAvailability: true, recoveryAudit: audit });
        return Response.json(result2, { status: result2.ok ? 200 : 409 });
      });
      this.directOccupancyQueue = operation.catch(() => {
      });
      return operation;
    }
    if (request.method === "POST" && url.pathname === "/vehicle-duty-state") {
      if (this.env?.COMPANY_VEHICLE_OPERATIONS_ENABLED !== "1") return Response.json({ ok: false, error: "vehicle_operations_disabled" }, { status: 503 });
      const input = await request.json();
      const operation = this.directOccupancyQueue.then(async () => {
        if (!this.capacityScopeAllowed(input)) return Response.json({ ok: false, error: "duty_scope_mismatch" }, { status: 403 });
        const stored = await this.state.storage.get(VEHICLE_DUTY_STATE_KEY2);
        if (stored && (stored.tenant_id !== input.tenant_id || stored.company_id !== input.company_id)) return Response.json({ ok: false, error: "duty_scope_mismatch" }, { status: 403 });
        return Response.json({ ok: true, version: stored?.version ?? 0, duties: (stored?.duties || []).filter((row) => row.driver_id === input.driver_id) });
      });
      this.directOccupancyQueue = operation.catch(() => {
      });
      return operation;
    }
    if (request.method === "POST" && url.pathname === "/vehicle-duty") {
      if (this.env?.COMPANY_VEHICLE_OPERATIONS_ENABLED !== "1") return Response.json({ ok: false, error: "vehicle_operations_disabled" }, { status: 503 });
      const input = await request.json();
      const operation = this.directOccupancyQueue.then(async () => {
        if (!this.capacityScopeAllowed(input)) return Response.json({ ok: false, error: "duty_scope_mismatch" }, { status: 403 });
        if (["end", "pause"].includes(input.action)) {
          const matchesDuty = (row) => row.driver_id === input.actor?.driver_id || row.vehicle_id === input.vehicle_id;
          const busy = Object.values(this.directOccupancy).some(matchesDuty) || Object.values(this.capacity.claims || {}).some((row) => matchesDuty(row) && (row.active === true || row.end_ms > nowMs || overdueCapacityHold2(row, nowMs, this.capacity.owners?.[row.owner_id])));
          if (busy) return Response.json({ ok: false, error: "active_ride_blocks_duty_change" }, { status: 409 });
        }
        const result2 = await persistVehicleDutyCommand2(this.state.storage, input, input.actor, { projectAvailability: true });
        return Response.json(result2, { status: result2.ok ? 200 : 409 });
      });
      this.directOccupancyQueue = operation.catch(() => {
      });
      return operation;
    }
    if (request.method === "POST" && url.pathname === "/vehicle-duty-history") {
      if (this.env?.COMPANY_VEHICLE_OPERATIONS_ENABLED !== "1") return Response.json({ ok: false, error: "vehicle_operations_disabled" }, { status: 503 });
      const input = await request.json();
      const operation = this.directOccupancyQueue.then(async () => {
        if (!this.capacityScopeAllowed(input)) return Response.json({ ok: false, error: "duty_scope_mismatch" }, { status: 403 });
        const result2 = await readVehicleDutyHistory2(this.state.storage, input, input.driver_id, { limit: input.limit, cursor: input.cursor });
        return Response.json(result2, { status: result2.ok ? 200 : 409 });
      });
      this.directOccupancyQueue = operation.catch(() => {
      });
      return operation;
    }
    if (request.method === "POST" && url.pathname === "/capacity") {
      const input = await request.json();
      const operation = this.directOccupancyQueue.then(async () => {
        if (!this.capacityScopeAllowed(input)) return Response.json({ ok: false, error: "capacity_scope_conflict" }, { status: 409 });
        await this.hydrateCapacity({ owner: [input.owner_id] }, input);
        await this.expireOffers(Date.now());
        if (String(this.env?.CAPACITY_BASELINE_REQUIRED) === "1" && !this.capacity.baseline && ["reserve", "activate"].includes(input.action)) {
          return Response.json({ ok: false, error: "capacity_baseline_required" }, { status: 503 });
        }
        const amended = preemptOwnerAmendments2(this.capacity, input, Date.now());
        const offer = Object.values(amended.offers || {}).find((row) => row.owner_id === input.owner_id && ["offered", "received", "committing", ...input.action === "release" ? ["committed"] : []].includes(row.state));
        if (offer && ["reserve", "activate"].includes(input.action)) {
          return Response.json({ ok: false, error: "dispatch_offer_pending" }, { status: 409 });
        }
        if (offer && input.action === "confirm" && (offer.state !== "committing" || !Array.isArray(input.canonical_claims))) {
          return Response.json({ ok: false, error: "dispatch_commit_unconfirmed" }, { status: 409 });
        }
        const prepared = preemptPrerequisiteOffers2(amended, input, Date.now());
        const decision = capacityClaimDecision2(prepared, input, Object.values(this.directOccupancy));
        if (!decision.ok) return Response.json({
          ok: false,
          error: decision.error,
          ...decision.pending_version ? { pending_version: decision.pending_version } : {}
        }, { status: decision.status });
        let next = { ...prepared, ...decision.ledger };
        if (input.action === "confirm" && prepared.owners[input.owner_id]?.pending) {
          const resources = Object.values(prepared.claims).filter((claim) => claim.owner_id === input.owner_id && claim.active);
          if (resources.length) next = queueConfirmedSuccessorChecks2(next, Date.now(), { owner_id: input.owner_id, resources });
        }
        if (offer && input.action === "confirm") next.offers = {
          ...next.offers,
          [offer.offer_id]: { ...offer, state: "committed" }
        };
        if (offer && input.action === "release") {
          const remains = Object.values(next.claims).some((claim) => claim.owner_id === offer.owner_id && claim.offer_id === offer.offer_id);
          if (!remains) next.offers = {
            ...next.offers,
            [offer.offer_id]: { ...offer, state: "cancelled", reason: "canonical_release", ended_at_ms: Date.now() }
          };
        }
        await this.writeCapacity(next, input);
        return Response.json({ ok: true, committed: true });
      });
      this.directOccupancyQueue = operation.catch(() => {
      });
      return operation;
    }
    if (request.method === "POST" && url.pathname === "/capacity-baseline") {
      const input = await request.json();
      const operation = this.directOccupancyQueue.then(async () => {
        if (!this.capacityScopeAllowed(input)) return Response.json({ ok: false, error: "capacity_scope_conflict" }, { status: 409 });
        const registrationId = input.new_company_registration;
        if (registrationId !== void 0) {
          if (typeof registrationId !== "string" || !/^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/.test(registrationId) || input.inventory_verified !== true || !Array.isArray(input.bookings) || input.bookings.length) {
            return Response.json({ ok: false, error: "new_company_capacity_identity_invalid" }, { status: 400 });
          }
          if (this.capacity.baseline?.registration_id !== registrationId) {
            if (this.capacity.baseline || await this.state.storage.get(CAPACITY_STORAGE_KEY2) || Object.keys(this.directOccupancy).length || !this.state.storage.list || (await this.state.storage.list({ prefix: "capacity_archive_v1:", limit: 1 })).size) {
              return Response.json({ ok: false, error: "new_company_capacity_existing_history" }, { status: 409 });
            }
          }
        }
        if (this.capacity.baseline) {
          if (this.capacity.baseline.tenant_id !== input.tenant_id || this.capacity.baseline.company_id !== input.company_id) {
            return Response.json({ ok: false, error: "capacity_scope_conflict" }, { status: 409 });
          }
          if (registrationId !== void 0) return Response.json({ ok: true, committed: true, already_initialized: true });
        }
        await this.hydrateCapacity({ owner: (Array.isArray(input.bookings) ? input.bookings.slice(0, 5e3) : []).map((row) => row?.owner_id) }, input);
        const decision = capacityBaselineDecision2(this.capacity, input);
        if (!decision.ok) return Response.json({ ok: false, error: decision.error }, { status: decision.status });
        const initialized = Boolean(this.capacity.baseline);
        if (initialized && JSON.stringify(decision.ledger) === JSON.stringify(this.capacity)) {
          return Response.json({ ok: true, committed: true, already_initialized: true, revalidated: true });
        }
        const next = { ...this.capacity, ...decision.ledger, baseline: this.capacity.baseline || {
          tenant_id: input.tenant_id,
          company_id: input.company_id,
          initialized_at: new Date(nowMs).toISOString(),
          inventory_digest: input.inventory_digest || null,
          ...registrationId ? { registration_id: registrationId, source: "new_company_registration" } : {}
        } };
        await this.writeCapacity(next, input);
        return Response.json({ ok: true, committed: true, ...initialized ? { already_initialized: true, revalidated: true } : {} });
      });
      this.directOccupancyQueue = operation.catch(() => {
      });
      return operation;
    }
    if (request.method === "POST" && url.pathname === "/dispatch-search") {
      const input = await request.json();
      const operation = this.directOccupancyQueue.then(async () => {
        if (!this.capacityScopeAllowed(input)) return Response.json({ ok: false, error: "capacity_scope_conflict" }, { status: 409 });
        await this.hydrateCapacity({ owner: [input.owner_id], event: [`search:${input.owner_id}:${input.version}`] }, input);
        if (!this.capacity.baseline || this.capacity.baseline.tenant_id !== input.tenant_id || this.capacity.baseline.company_id !== input.company_id) {
          return Response.json({ ok: false, error: "capacity_baseline_required" }, { status: 503 });
        }
        const decision = dispatchSearchDecision2(this.capacity, {
          tenant_id: input.tenant_id,
          company_id: input.company_id,
          owner_id: input.owner_id,
          version: input.version,
          ...input.amendment ? { amendment: true, base_version: input.base_version, retained_claims: input.retained_claims } : {}
        }, Date.now());
        if (!decision.ok) return Response.json({ ok: false, error: decision.error }, { status: decision.status });
        await this.writeCapacity(decision.ledger, input);
        return Response.json({ ok: true, committed: true, search_id: decision.event.event_id });
      });
      this.directOccupancyQueue = operation.catch(() => {
      });
      return operation;
    }
    if (request.method === "POST" && url.pathname === "/dispatch-device") {
      const input = await request.json();
      const operation = this.directOccupancyQueue.then(async () => {
        if (!this.capacityScopeAllowed(input)) return Response.json({ ok: false, error: "capacity_scope_conflict" }, { status: 409 });
        if (input.vehicle_device_id) {
          if (this.env?.COMPANY_VEHICLE_OPERATIONS_ENABLED !== "1" || !/^[a-zA-Z0-9_.-]{1,96}$/.test(input.vehicle_device_id)) return Response.json({ ok: false, error: "vehicle_device_auth_required" }, { status: 403 });
          const device = await this.state.storage.get(`vehicle_device_v1:${input.vehicle_device_id}`);
          if (!device || device.revoked || device.expires_at_ms <= Date.now()) return Response.json({ ok: false, error: "vehicle_device_auth_required" }, { status: 403 });
        }
        const changed = updateDispatchDevice2(this.dispatchDevices, input, Date.now());
        if (!changed.ok) return Response.json(changed, { status: changed.status });
        await this.state.storage.put(DISPATCH_DEVICES_KEY, changed.store);
        this.dispatchDevices = changed.store;
        await this.expireOffers(Date.now());
        return Response.json({ ok: true, dispatch_device_contract_version: 1 });
      });
      this.directOccupancyQueue = operation.catch(() => {
      });
      return operation;
    }
    if (request.method === "POST" && url.pathname === "/dispatch-offer") {
      const input = await request.json();
      const operation = this.directOccupancyQueue.then(async () => {
        if (!this.capacityScopeAllowed(input)) return Response.json({ ok: false, error: "capacity_scope_conflict" }, { status: 409 });
        await this.hydrateCapacity({ owner: [input.owner_id], offer: [input.offer_id] }, input);
        if (String(this.env?.CAPACITY_BASELINE_REQUIRED) === "1" && !this.capacity.baseline) {
          return Response.json({ ok: false, error: "capacity_baseline_required" }, { status: 503 });
        }
        await this.expireOffers(Date.now());
        if (input.human_acceptance_required === true && this.env?.COMPANY_VEHICLE_OPERATIONS_ENABLED !== "1") return Response.json({ ok: false, error: "vehicle_operations_disabled" }, { status: 503 });
        if (input.action === "accept") {
          if (this.env?.COMPANY_VEHICLE_OPERATIONS_ENABLED !== "1") return Response.json({ ok: false, error: "vehicle_operations_disabled" }, { status: 503 });
          const duty = await this.state.storage.get(VEHICLE_DUTY_STATE_KEY2);
          const owned = dutyForRideExecution2(duty, input, input.vehicle_id);
          if (await this.state.storage.get(VEHICLE_DUTY_PROJECTION_KEY2)) return Response.json({ ok: false, error: "active_duty_required" }, { status: 409 });
          const personal = !owned.ok && personalDriverExecutionV1({ input, devices: this.dispatchDevices, duty, offer: this.capacity.offers?.[input.offer_id], nowMs: Date.now() });
          if (!owned.ok && !personal) return Response.json({ ok: false, error: "active_duty_required" }, { status: 409 });
          input.execution_identity = owned.ok ? owned.execution_identity : personal;
        }
        const decision = dispatchOfferDecision2(this.capacity, input, {
          nowMs: Date.now(),
          directRides: Object.values(this.directOccupancy),
          driverPosition: this.drivers[input.driver_id],
          dispatchDevices: this.dispatchDevices,
          drivers: this.drivers
        });
        if (!decision.ok) return Response.json({ ok: false, error: decision.error }, { status: decision.status });
        await this.writeCapacity(decision.ledger, input);
        return Response.json({ ok: true, committed: true, offer: decision.offer });
      });
      this.directOccupancyQueue = operation.catch(() => {
      });
      return operation;
    }
    if (request.method === "GET" && url.pathname === "/driver-offers") {
      const input = { tenant_id: url.searchParams.get("tenant_id"), company_id: url.searchParams.get("company_id") };
      const operation = this.directOccupancyQueue.then(async () => {
        if (!this.capacityScopeAllowed(input)) return Response.json({ ok: false, error: "capacity_scope_conflict" }, { status: 409 });
        await this.expireOffers(Date.now());
        const driverId = url.searchParams.get("driver_id");
        const deviceKey = url.searchParams.get("device_key");
        if (!deviceKey || !driverDispatchDevices3(this.dispatchDevices, input, driverId, Date.now(), deviceKey).length) {
          return Response.json({ ok: false, error: "dispatch_device_unavailable" }, { status: 409 });
        }
        const offers = Object.values(this.capacity.offers || {}).filter((offer) => dispatchOfferResources2(offer).some((resource) => resource.driver_id === driverId) && offer.tenant_id === input.tenant_id && offer.company_id === input.company_id && ["offered", "received", "committing"].includes(offer.state)).slice(0, 8).map((offer) => ({
          offer_id: offer.offer_id,
          owner_id: offer.owner_id,
          version: offer.version,
          vehicle_id: dispatchOfferResources2(offer).find((resource) => resource.driver_id === driverId).vehicle_id,
          ack_deadline_ms: offer.ack_deadline_ms,
          state: offer.state,
          ...offer.human_acceptance_required === true ? {
            human_acceptance_required: true,
            ...offer.response_starts_on_display === true ? {
              response_starts_on_display: true,
              response_timeout_ms: offer.ack_timeout_ms,
              displayed_at_ms: offer.receipts?.[driverId]?.displayed_at_ms ?? null
            } : {},
            human_accepted: offer.receipts?.[driverId]?.accepted === true
          } : {}
        }));
        return Response.json({ ok: true, offers });
      });
      this.directOccupancyQueue = operation.catch(() => {
      });
      return operation;
    }
    if (url.pathname === "/dispatch-events") {
      if (request.method === "GET") {
        await this.directOccupancyQueue;
        const input = { tenant_id: url.searchParams.get("tenant_id"), company_id: url.searchParams.get("company_id") };
        if (!this.capacityScopeAllowed(input)) return Response.json({ ok: false, error: "capacity_scope_conflict" }, { status: 409 });
        return Response.json({ ok: true, events: Object.values(this.capacity.dispatch_events || {}).filter((event) => event.state === "pending" && event.tenant_id === input.tenant_id && event.company_id === input.company_id).map((event) => ({ ...event, offer_state: this.capacity.offers?.[event.offer_id]?.state })) });
      }
      if (request.method === "POST") {
        const input = await request.json();
        const operation = this.directOccupancyQueue.then(async () => {
          if (!this.capacityScopeAllowed(input)) return Response.json({ ok: false, error: "capacity_scope_conflict" }, { status: 409 });
          await this.hydrateCapacity({ event: [input.event_id] }, input);
          const decision = acknowledgeDispatchEvent2(this.capacity, input);
          if (!decision.ok) return Response.json({ ok: false, error: decision.error }, { status: decision.status });
          await this.writeCapacity(decision.ledger, input);
          return Response.json({ ok: true, committed: true });
        });
        this.directOccupancyQueue = operation.catch(() => {
        });
        return operation;
      }
    }
    if (request.method === "POST" && url.pathname === "/direct-occupancy") {
      const event = await request.json();
      const operation = this.directOccupancyQueue.then(async () => {
        if (!this.capacityScopeAllowed(event)) return Response.json({ ok: false, error: "capacity_scope_conflict" }, { status: 409 });
        await this.expireOffers(Date.now());
        const key2 = String(event.direct_ride_key || event.trip_id || "").trim();
        if (!key2 || key2.length > 200 || !event.tenant_id || !event.company_id || !event.driver_id || !event.vehicle_id || !["start", "stop"].includes(event.phase)) {
          return Response.json({ ok: false, error: "direct_occupancy_invalid" }, { status: 400 });
        }
        const existing = this.directOccupancy[key2];
        if (existing && ["tenant_id", "company_id", "driver_id", "vehicle_id"].some((field) => existing[field] !== event[field])) {
          return Response.json({ ok: false, error: "direct_occupancy_conflict" }, { status: 409 });
        }
        const stoppedKey = `direct_occupancy_stopped:${key2}`;
        const next = { ...this.directOccupancy };
        if (event.phase === "start") {
          if (String(this.env?.CAPACITY_BASELINE_REQUIRED) === "1" && !this.capacity.baseline) {
            return Response.json({ ok: false, error: "capacity_baseline_required" }, { status: 503 });
          }
          if (await this.state.storage.get(stoppedKey)) {
            return Response.json({ ok: true, applied: false, reason: "already_stopped" });
          }
          const preempted = preemptDispatchOffers2(this.capacity, event, Date.now());
          if (!existing && (Object.values(this.directOccupancy).some((ride) => ride.tenant_id === event.tenant_id && ride.company_id === event.company_id && sameCapacityResource2(ride, event)) || Object.values(preempted.claims).some((claim) => claim.tenant_id === event.tenant_id && claim.company_id === event.company_id && (claim.active || claim.end_ms > nowMs || overdueCapacityHold2(claim, nowMs, preempted.owners[claim.owner_id])) && sameCapacityResource2(claim, event)))) {
            return Response.json({ ok: false, error: "capacity_conflict" }, { status: 409 });
          }
          next[key2] = existing || {
            tenant_id: event.tenant_id,
            company_id: event.company_id,
            driver_id: event.driver_id,
            vehicle_id: event.vehicle_id,
            direct_ride_key: key2,
            trip_id: event.trip_id || null,
            started_at: new Date(nowMs).toISOString()
          };
          await this.writeCapacity({ ...preempted, direct_holds: next }, event);
          return Response.json({ ok: true, applied: true });
        } else {
          await this.state.storage.put(stoppedKey, { stopped_at: new Date(nowMs).toISOString() });
          delete next[key2];
        }
        await this.writeCapacity({ ...this.capacity, direct_holds: next }, event);
        return Response.json({ ok: true, applied: true });
      });
      this.directOccupancyQueue = operation.catch(() => {
      });
      return operation;
    }
    if (request.method === "POST" && url.pathname === "/location") {
      const input = await request.json();
      const operation = this.directOccupancyQueue.then(async () => {
        const nowMs2 = Date.now();
        if (!this.capacityScopeAllowed(input) || this.drivers[input.driver_id] && (this.drivers[input.driver_id].tenant_id !== input.tenant_id || this.drivers[input.driver_id].company_id !== input.company_id)) {
          return Response.json({ ok: false, error: "location_scope_conflict" }, { status: 409 });
        }
        if (input.vehicle_device_presence != null) {
          const proof = input.vehicle_device_presence;
          const device = await vehicleDeviceCommand2(this.state.storage, {
            tenant_id: input.tenant_id,
            company_id: input.company_id,
            action: "authenticate",
            device_id: proof.device_id,
            device_token_hash: proof.device_token_hash
          }, nowMs);
          if (!device.ok || device.vehicle_id !== input.vehicle_id)
            return Response.json({ ok: false, error: "vehicle_device_auth_required" }, { status: 403 });
          const duty = await this.state.storage.get(VEHICLE_DUTY_STATE_KEY2);
          const owned = dutyForRideExecution2(duty, input, device.vehicle_id);
          const activeDuty = duty?.duties?.find((row) => row.duty_id === owned.execution_identity?.duty_id);
          if (await this.state.storage.get(VEHICLE_DUTY_PROJECTION_KEY2) || !owned.ok || activeDuty?.vehicle_device_id !== device.device_id)
            return Response.json({ ok: false, error: "active_duty_required" }, { status: 409 });
        }
        const previous = this.drivers[input.driver_id];
        if (locationOwnerRetired2(previous, input.publication_owner, nowMs2)) {
          return Response.json({ ok: false, error: "location_owner_retired" }, { status: 409 });
        }
        if (boundLocationOwner2(previous?.publication_owner, nowMs2) && !boundLocationOwner2(input.publication_owner, nowMs2)) {
          return Response.json({ ok: false, error: "location_owner_unbound" }, { status: 409 });
        }
        if (input.tracking_context == null && previous?.tracking_context && boundLocationOwner2(input.publication_owner, nowMs2) && sameLocationOwner2(previous.publication_owner, input.publication_owner)) {
          const storedContext = previous.tracking_context;
          const grant = await readStoredCustomerGrant2(
            this.state.storage,
            this.grants,
            grantKey2(storedContext.booking_id, storedContext.operational_leg),
            this.grants.scope || input
          );
          const valid32 = matchesTrackingScope(input, storedContext, grant) && grant.position_allowed === true && (storedContext.phase === "en_route_pickup" ? ["en_route_pickup", "arrived_pickup"].includes(grant.tracking_phase) : storedContext.phase === "in_progress" && grant.tracking_phase === "in_progress" && storedContext.session_id && storedContext.session_id === grant.session_id);
          const startedPickup = matchesTrackingScope(input, storedContext, grant) && grant.position_allowed === true && storedContext.phase === "en_route_pickup" && grant.tracking_phase === "in_progress" && typeof grant.session_id === "string" && grant.session_id.length > 0 && (!storedContext.session_id || storedContext.session_id === grant.session_id) && grant.vehicle?.vehicle_id && previous.vehicle_id === grant.vehicle.vehicle_id && input.vehicle_id === grant.vehicle.vehicle_id;
          if (valid32 || startedPickup) {
            input.tracking_context = startedPickup ? { ...storedContext, phase: "in_progress", session_id: grant.session_id } : storedContext;
            input.tracking_status = input.tracking_context.phase === "in_progress" ? "active" : "en_route_pickup";
            input.availability_status = "on_trip";
          }
        }
        const context3 = input.tracking_context;
        if (input.presence_restricted_reason && !context3) {
          return Response.json({ ok: true, applied: false, reason: input.presence_restricted_reason });
        }
        if (context3 != null && !["en_route_pickup", "in_progress"].includes(context3.phase)) {
          return Response.json({ ok: false, error: "location_context_invalid" }, { status: 409 });
        }
        if (context3?.phase === "en_route_pickup") {
          const grant = await readStoredCustomerGrant2(
            this.state.storage,
            this.grants,
            grantKey2(context3.booking_id, context3.operational_leg),
            this.grants.scope || input
          );
          const valid32 = matchesTrackingScope(input, context3, grant) && grant.position_allowed === true && ["en_route_pickup", "arrived_pickup"].includes(grant.tracking_phase);
          if (!valid32) return Response.json({ ok: false, error: "presence_context_invalid" }, { status: 409 });
          const otherTrip = Object.values(this.grants.grants || {}).some((g) => g.driver_id === input.driver_id && g.tracking_phase === "in_progress" && !g.leg_scope_retired && g.position_allowed === true);
          if (otherTrip) return Response.json({ ok: false, error: "presence_context_invalid" }, { status: 409 });
        }
        if (context3?.phase === "in_progress") {
          const grant = await readStoredCustomerGrant2(
            this.state.storage,
            this.grants,
            grantKey2(context3.booking_id, context3.operational_leg),
            this.grants.scope || input
          );
          const valid32 = matchesTrackingScope(input, context3, grant) && grant.session_id === context3.session_id && context3.session_id && ["assigned", "en_route_pickup", "arrived_pickup", "in_progress"].includes(grant.tracking_phase);
          if (!valid32) return Response.json({ ok: false, error: "trip_context_invalid" }, { status: 409 });
        }
        const mergedHits = previous ? { [input.driver_id]: {
          ...previous,
          ...this.hits.has(input.driver_id) ? { recent_hits: this.hits.get(input.driver_id) } : {}
        } } : {};
        const applied = applyLocationUpdate(mergedHits, input, nowMs2);
        if (applied.result.applied) {
          const retired = nextRetiredLocationOwners2(previous, input.publication_owner, nowMs2);
          if (!retired) return Response.json({ ok: false, error: "location_owner_limit" }, { status: 429 });
          if (retired.length) applied.drivers[input.driver_id].retired_publications = retired;
          else delete applied.drivers[input.driver_id].retired_publications;
        }
        const nextDrivers = persistable(applied.drivers);
        for (const [id22, row] of Object.entries(applied.drivers)) {
          if (row?.recent_hits) this.hits.set(id22, row.recent_hits);
        }
        if (applied.result.applied || applied.result.liveness_updated) {
          this.drivers = await this.driverRows.write(input.driver_id, nextDrivers[input.driver_id]);
          if (this.spatialIndex) this.spatialIndex.update(nextDrivers[input.driver_id], nowMs2);
        }
        await this.expireOffers(nowMs2);
        const status = applied.result.status || 200;
        return Response.json(applied.result, { status });
      });
      this.directOccupancyQueue = operation.catch(() => {
      });
      return operation;
    }
    if (request.method === "POST" && url.pathname === "/location-withdraw") {
      const input = await request.json();
      const operation = this.directOccupancyQueue.then(async () => {
        const nowMs2 = Date.now();
        if (!input.driver_id || !input.tenant_id || !input.company_id || !boundLocationOwner2(input.publication_owner, nowMs2)) {
          return Response.json({ ok: false, error: "location_owner_invalid" }, { status: 400 });
        }
        const previous = this.drivers[input.driver_id];
        if (!this.capacityScopeAllowed(input) || previous && (previous.tenant_id !== input.tenant_id || previous.company_id !== input.company_id)) {
          return Response.json({ ok: false, error: "location_scope_conflict" }, { status: 409 });
        }
        if (previous && !boundLocationOwner2(previous.publication_owner, nowMs2)) {
          return Response.json({ ok: true, cleared: false, reason: "owner_unbound" });
        }
        if (locationOwnerRetired2(previous, input.publication_owner, nowMs2)) {
          return Response.json({ ok: true, cleared: false, reason: "already_withdrawn" });
        }
        const matches32 = sameLocationOwner2(previous?.publication_owner, input.publication_owner);
        const retired = retainedLocationOwners2(previous, nowMs2);
        if (previous && !matches32) {
          if (retired.length >= LOCATION_RETIRED_OWNER_LIMIT2) {
            return Response.json({ ok: false, error: "location_owner_limit" }, { status: 429 });
          }
          retired.push(input.publication_owner);
        }
        let row = previous ? { ...previous, retired_publications: retired } : {
          tenant_id: input.tenant_id,
          company_id: input.company_id,
          driver_id: input.driver_id,
          publication_owner: input.publication_owner,
          retired_publications: []
        };
        if (!previous || matches32) row = {
          tenant_id: input.tenant_id,
          company_id: input.company_id,
          driver_id: input.driver_id,
          publication_owner: input.publication_owner,
          retired_publications: retired,
          location_withdrawn: true
        };
        this.drivers = await this.driverRows.write(input.driver_id, persistable({ [input.driver_id]: row })[input.driver_id]);
        if (this.spatialIndex) this.spatialIndex.update(row, nowMs2);
        if (matches32) this.hits.delete(input.driver_id);
        await this.expireOffers(nowMs2);
        return Response.json({
          ok: true,
          cleared: Boolean(matches32),
          reason: matches32 ? "withdrawn" : previous ? "owner_mismatch" : "location_absent"
        });
      });
      this.directOccupancyQueue = operation.catch(() => {
      });
      return operation;
    }
    if (request.method === "POST" && url.pathname === "/clear") {
      const input = await request.json();
      const operation = this.directOccupancyQueue.then(async () => {
        const previous = this.drivers[input.driver_id];
        if (input.publication_owner && (!previous?.publication_owner || !sameLocationOwner2(previous.publication_owner, input.publication_owner)) || previous?.publication_owner && !input.publication_owner) {
          return Response.json({ ok: true, cleared: false, reason: previous?.publication_owner ? "owner_mismatch" : "owner_unbound" });
        }
        if (previous && input.tenant_id && (previous.tenant_id !== input.tenant_id || previous.company_id !== input.company_id)) {
          return Response.json({ ok: false, error: "location_scope_conflict" }, { status: 409 });
        }
        if (boundLocationOwner2(previous?.publication_owner, Date.now())) {
          return Response.json({ ok: true, cleared: false, reason: "owner_unbound" });
        }
        this.drivers = await this.driverRows.write(String(input.driver_id || ""), null);
        if (this.spatialIndex) this.spatialIndex.remove(String(input.driver_id || ""));
        this.hits.delete(String(input.driver_id || ""));
        await this.expireOffers(Date.now());
        return Response.json({ ok: true, cleared: true });
      });
      this.directOccupancyQueue = operation.catch(() => {
      });
      return operation;
    }
    if (request.method === "POST" && url.pathname === "/customer-grant") {
      const event = await request.json();
      const operation = this.directOccupancyQueue.then(async () => {
        if (!this.capacityScopeAllowed(event)) return Response.json({ ok: false, error: "customer_grant_scope_conflict" }, { status: 409 });
        const previous = await hydrateCustomerGrantEvent2(this.state.storage, this.grants, event, this.grants.scope || event);
        const applied = applyCustomerLifecycle2(previous, event, Date.now());
        if (applied.applied) {
          const stored = { ...applied.store, scope: this.grants.scope || {
            tenant_id: applied.grant.tenant_id,
            company_id: applied.grant.company_id
          } };
          this.grants = await writeCustomerGrantSnapshot2(this.state.storage, stored, Date.now());
        }
        const grant = applied.grant || null;
        return Response.json({
          ok: true,
          applied: applied.applied,
          confirmed: applied.confirmed === true,
          reason: applied.reason,
          // Renewal cannot manufacture access when no usable token survived.
          ...event.kind === "renew" ? { renewal_access_retained: Boolean(grant && [grant.access_token_hash, ...grant.access_token_hashes || []].some((hash22) => hash22 && customerAccessAllowed2(grant, {
            tenant_id: grant.tenant_id,
            company_id: grant.company_id,
            booking_id: grant.booking_id,
            operational_leg: grant.operational_leg,
            customer_id: grant.customer_id,
            access_token_hash: hash22
          }).ok)) } : {},
          lifecycle_seq: grant?.lifecycle_seq ?? null,
          assignment_version: grant?.assignment_version ?? null,
          tracking_phase: grant?.tracking_phase ?? null,
          position_allowed: grant?.position_allowed === true
        });
      });
      this.directOccupancyQueue = operation.catch(() => {
      });
      return operation;
    }
    if (request.method === "GET" && url.pathname === "/customer-live") {
      const operation = this.directOccupancyQueue.then(async () => {
        const snapshotNowMs = Date.now();
        const key2 = grantKey2(url.searchParams.get("booking_id"), url.searchParams.get("operational_leg"));
        const grant = await readStoredCustomerGrant2(this.state.storage, this.grants, key2, this.grants.scope || {
          tenant_id: url.searchParams.get("tenant_id"),
          company_id: url.searchParams.get("company_id")
        });
        const access = customerAccessAllowed2(grant, {
          tenant_id: url.searchParams.get("tenant_id"),
          company_id: url.searchParams.get("company_id"),
          booking_id: url.searchParams.get("booking_id"),
          operational_leg: url.searchParams.get("operational_leg"),
          customer_id: url.searchParams.get("customer_id"),
          access_token_hash: url.searchParams.get("access_token_hash"),
          assignment_version: url.searchParams.get("assignment_version"),
          session_id: url.searchParams.get("session_id")
        });
        if (!access.ok) return Response.json({ ok: false, error: access.error }, { status: access.status });
        const live = projectCompanyLive(this.drivers[grant.driver_id] ? { [grant.driver_id]: this.drivers[grant.driver_id] } : {}, {
          tenantId: grant.tenant_id,
          companyId: grant.company_id,
          nowMs: snapshotNowMs,
          freshnessSeconds: url.searchParams.get("freshness_seconds")
        });
        const driver = (live.drivers || []).find((row) => row.driver_id === grant.driver_id) || null;
        const stored = this.drivers[grant.driver_id];
        const context3 = stored?.tracking_context;
        const matches32 = matchesTrackingScope(stored, context3, grant) && grant.position_allowed === true && ["en_route_pickup", "in_progress"].includes(context3.phase) && (context3.phase === grant.tracking_phase || context3.phase === "en_route_pickup" && grant.tracking_phase === "arrived_pickup") && (context3.phase === "in_progress" ? Boolean(context3.session_id && context3.session_id === grant.session_id) : !context3.session_id || context3.session_id === grant.session_id);
        const snapshot = projectCustomerSnapshot2({ grant, driver: matches32 ? driver : null, nowMs: snapshotNowMs, eta: null, route: null });
        return Response.json(snapshot);
      });
      this.directOccupancyQueue = operation.catch(() => {
      });
      return operation;
    }
    if (request.method === "GET" && url.pathname === "/customer-grant") {
      const operation = this.directOccupancyQueue.then(async () => {
        const key2 = grantKey2(url.searchParams.get("booking_id"), url.searchParams.get("operational_leg"));
        let grant = await readStoredCustomerGrant2(this.state.storage, this.grants, key2, this.grants.scope);
        const driverId = url.searchParams.get("active_driver_id");
        if (grant?.leg_scope_retired && driverId && !url.searchParams.get("operational_leg")) {
          const candidates = Object.values(this.grants.grants || {}).filter((row) => row.booking_id === url.searchParams.get("booking_id") && row.driver_id === driverId && row.position_allowed === true && ["en_route_pickup", "in_progress"].includes(row.tracking_phase));
          grant = candidates.length === 1 ? candidates[0] : null;
        }
        if (!grant) return Response.json({ ok: false, error: "not_found" }, { status: 404 });
        return Response.json({ ok: true, grant });
      });
      this.directOccupancyQueue = operation.catch(() => {
      });
      return operation;
    }
    if (request.method === "GET" && url.pathname === "/live") {
      const expiry = this.directOccupancyQueue.then(async () => {
        await this.expireOffers(Date.now());
        if (this.env.ENTERPRISE_DRIVER_STATE_RETENTION_ENABLED === "1" && nowMs - (this.driverGcAt || 0) >= 36e5) {
          const pruned = await this.driverRows.prune((row) => {
            const seen = Date.parse(row?.last_seen_at || row?.received_at || "");
            return Number.isFinite(seen) && nowMs - seen >= 864e5 && !boundLocationOwner2(row?.publication_owner, nowMs) && retainedLocationOwners2(row, nowMs).length === 0;
          });
          this.drivers = pruned.rows;
          for (const driverId of pruned.deleted) {
            this.hits.delete(driverId);
            if (this.spatialIndex) this.spatialIndex.remove(driverId);
          }
          if (pruned.removed < 127) this.driverGcAt = nowMs;
        }
      });
      this.directOccupancyQueue = expiry.catch(() => {
      });
      await expiry;
      const freshness = url.searchParams.get("freshness_seconds");
      const body = projectCompanyLive(this.drivers, {
        tenantId: url.searchParams.get("tenant_id") || "",
        companyId: url.searchParams.get("company_id") || "",
        nowMs,
        freshnessSeconds: freshness
      });
      let spatial = null;
      if (this.env.ENTERPRISE_SAFE_SEARCH_ENABLED === "1" && url.searchParams.has("spatial_lat") && this.capacityScopeAllowed({ tenant_id: body.tenant_id, company_id: body.company_id })) {
        if (!this.spatialIndex) {
          this.spatialIndex = createActiveSpatialIndex2(body);
          this.spatialIndex.rebuild(Object.values(this.drivers), nowMs);
        }
        const ordered = this.spatialIndex.ordered({
          latitude: Number(url.searchParams.get("spatial_lat")),
          longitude: Number(url.searchParams.get("spatial_lon"))
        }, nowMs);
        spatial = {
          complete: ordered.complete,
          cells_visited: ordered.cells_visited,
          rows: ordered.rows.map((row) => ({ driver_id: row.driver_id, vehicle_id: row.vehicle_id }))
        };
      }
      return Response.json({
        ...body,
        dispatch_offer_contract_version: 1,
        ...spatial ? { dispatch_spatial_order: spatial } : {},
        dispatch_device_contract_version: 1,
        dispatch_devices: projectDispatchDevices2(this.dispatchDevices, { tenant_id: body.tenant_id, company_id: body.company_id }, Date.now()),
        dispatch_offers: Object.values(this.capacity.offers || {}).filter((row) => row.tenant_id === url.searchParams.get("tenant_id") && row.company_id === url.searchParams.get("company_id") && ["offered", "received", "committing"].includes(row.state)),
        capacity_contract_version: 1,
        capacity_baseline: this.capacity.baseline || null,
        capacity_reservations: Object.values(this.capacity.claims).filter((row) => row.tenant_id === url.searchParams.get("tenant_id") && row.company_id === url.searchParams.get("company_id")).map((row) => ({
          ...row,
          capacity_version: this.capacity.owners[row.owner_id]?.version,
          completion_unconfirmed: overdueCapacityHold2(row, nowMs, this.capacity.owners[row.owner_id]),
          reservation_expired: unstartedCapacityExpired2(row, nowMs, this.capacity.owners[row.owner_id]),
          ...row.offer_id ? { capacity_offer_state: this.capacity.offers?.[row.offer_id]?.owner_id === row.owner_id && this.capacity.offers[row.offer_id].tenant_id === row.tenant_id && this.capacity.offers[row.offer_id].company_id === row.company_id ? this.capacity.offers[row.offer_id].state : "unresolved" } : {},
          capacity_pending: this.capacity.owners[row.owner_id]?.pending === true
        })),
        active_direct_rides: Object.values(this.directOccupancy).filter((row) => row.tenant_id === url.searchParams.get("tenant_id") && row.company_id === url.searchParams.get("company_id"))
      });
    }
    return Response.json({ ok: false, error: "not_found" }, { status: 404 });
  }
};
var __defProp2 = Object.defineProperty;
var __getOwnPropNames2 = Object.getOwnPropertyNames;
var __name = (target2, value) => __defProp2(target2, "name", { value, configurable: true });
var __esm2 = (fn, res) => function __init() {
  return fn && (res = (0, fn[__getOwnPropNames2(fn)[0]])(fn = 0)), res;
};
function safeStr2(v) {
  if (v === null || v === void 0) return "";
  return String(v).trim();
}
function sanitizeTenantString2(value, maxLength = 240) {
  const text22 = String(value == null ? "" : value).replace(/\0/g, "").trim();
  return text22.length > maxLength ? text22.slice(0, maxLength) : text22;
}
var init_parsing_utils2 = __esm2({
  "../booking/modules/parsing_utils.js"() {
    __name(safeStr2, "safeStr");
    __name(sanitizeTenantString2, "sanitizeTenantString");
  }
});
function normalizeDispatchAvailability2(raw) {
  const token = sanitizeTenantString2(raw, 40).toLowerCase();
  if (token === "paused" || token === "pause" || token === "unavailable" || token === "not_available") {
    return AVAILABILITY2.PAUSED;
  }
  if (token === "offline") return AVAILABILITY2.OFFLINE;
  if (token === "busy" || token === "on_trip" || token === "on-trip" || token === "on_the_way" || token === "waiting") {
    return AVAILABILITY2.ON_TRIP;
  }
  if (token === "available" || token === "ready" || token === "online") {
    return AVAILABILITY2.AVAILABLE;
  }
  return AVAILABILITY2.AVAILABLE;
}
function parseHm(raw) {
  const text22 = sanitizeTenantString2(raw, 8);
  const match = text22.match(/^(\d{1,2}):(\d{2})$/);
  if (!match) return null;
  const hour = Number(match[1]);
  const minute = Number(match[2]);
  if (!Number.isFinite(hour) || !Number.isFinite(minute) || hour > 23 || minute > 59) {
    return null;
  }
  return hour * 60 + minute;
}
function formatHm(minutes) {
  const wrapped = (minutes % 1440 + 1440) % 1440;
  const hour = String(Math.floor(wrapped / 60)).padStart(2, "0");
  const minute = String(wrapped % 60).padStart(2, "0");
  return `${hour}:${minute}`;
}
function dispatchTimezoneIsSupported(timeZone) {
  const zone = sanitizeTenantString2(timeZone, 64) || DEFAULT_DISPATCH_TIMEZONE;
  try {
    new Intl.DateTimeFormat("en-GB", { timeZone: zone }).format(/* @__PURE__ */ new Date());
    return true;
  } catch {
    return false;
  }
}
function weeklyRosterHasConfiguredBlocks(raw) {
  if (raw == null || typeof raw !== "object" || Array.isArray(raw)) return false;
  const roster = normalizeWeeklyRoster(raw);
  return WEEKDAY_KEYS.some((key2) => (roster.days[key2] || []).length > 0);
}
function weeklyRosterIsConfigured(raw, exceptionsRaw = []) {
  if (raw != null && typeof raw === "object" && !Array.isArray(raw)) {
    if (raw.explicitly_set === true || raw.explicitlySet === true || raw.configured === true) {
      return true;
    }
  }
  if (weeklyRosterHasConfiguredBlocks(raw)) return true;
  return normalizeRosterExceptions(exceptionsRaw).length > 0;
}
function driverRosterLoadFailed(driver) {
  if (!driver || typeof driver !== "object") return false;
  if (driver.weekly_roster_load_failed === true || driver.weeklyRosterLoadFailed === true) {
    return true;
  }
  const status = sanitizeTenantString2(
    driver.weekly_roster_status || driver.weeklyRosterStatus || driver.roster_status,
    40
  ).toLowerCase();
  return status === "load_failed" || status === "error" || status === "unavailable";
}
function resolveScheduleState(rosterRaw, atMs, exceptionsRaw = []) {
  const configured = weeklyRosterIsConfigured(rosterRaw, exceptionsRaw);
  if (!configured) {
    return { configured: false, active: false, undeterminable: false };
  }
  const roster = normalizeWeeklyRoster(rosterRaw);
  if (!dispatchTimezoneIsSupported(roster.timezone)) {
    return {
      configured: true,
      active: false,
      undeterminable: true,
      error: "unsupported_timezone"
    };
  }
  try {
    return {
      configured: true,
      active: scheduledActiveAt(rosterRaw, atMs, exceptionsRaw) === true,
      undeterminable: false
    };
  } catch {
    return {
      configured: true,
      active: false,
      undeterminable: true,
      error: "schedule_eval_failed"
    };
  }
}
function zonedParts(atMs, timeZone = DEFAULT_DISPATCH_TIMEZONE) {
  const ms = Number(atMs);
  if (!Number.isFinite(ms)) return null;
  const zone = sanitizeTenantString2(timeZone, 64) || DEFAULT_DISPATCH_TIMEZONE;
  if (!dispatchTimezoneIsSupported(zone)) return null;
  try {
    const parts = new Intl.DateTimeFormat("en-GB", {
      timeZone: zone,
      weekday: "short",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
      hourCycle: "h23"
    }).formatToParts(new Date(ms));
    const get = /* @__PURE__ */ __name((type) => parts.find((part) => part.type === type)?.value || "", "get");
    const weekdayRaw = get("weekday").slice(0, 3).toLowerCase();
    const weekdayMap = {
      mon: "mon",
      tue: "tue",
      wed: "wed",
      thu: "thu",
      fri: "fri",
      sat: "sat",
      sun: "sun"
    };
    return {
      timeZone: zone,
      weekday: weekdayMap[weekdayRaw] || "mon",
      year: get("year"),
      month: get("month"),
      day: get("day"),
      date: `${get("year")}-${get("month")}-${get("day")}`,
      hour: Number(get("hour")),
      minute: Number(get("minute")),
      second: Number(get("second")),
      minutes: Number(get("hour")) * 60 + Number(get("minute"))
    };
  } catch {
    return null;
  }
}
function normalizeRosterBlock(raw) {
  const start = parseHm(raw?.start ?? raw?.from ?? raw?.begin);
  const end = parseHm(raw?.end ?? raw?.to);
  if (start == null || end == null || start === end) return null;
  const breaks = [];
  if (Array.isArray(raw?.breaks)) {
    for (const slot2 of raw.breaks) {
      const bStart = parseHm(slot2?.start ?? slot2?.from);
      const bEnd = parseHm(slot2?.end ?? slot2?.to);
      if (bStart == null || bEnd == null || bStart === bEnd) continue;
      breaks.push({ start: formatHm(bStart), end: formatHm(bEnd) });
    }
  }
  return {
    start: formatHm(start),
    end: formatHm(end),
    overnight: start > end,
    ...breaks.length ? { breaks } : {}
  };
}
function normalizeWeeklyRoster(raw) {
  const source = raw && typeof raw === "object" && !Array.isArray(raw) ? raw : {};
  const daysSource = source.days && typeof source.days === "object" ? source.days : source;
  const days = {};
  for (const key2 of WEEKDAY_KEYS) {
    const rows2 = Array.isArray(daysSource[key2]) ? daysSource[key2] : [];
    days[key2] = rows2.map(normalizeRosterBlock).filter(Boolean);
  }
  const explicitlySet = source.explicitly_set === true || source.explicitlySet === true || source.configured === true;
  return {
    timezone: sanitizeTenantString2(source.timezone || source.time_zone, 64) || DEFAULT_DISPATCH_TIMEZONE,
    days,
    ...explicitlySet ? { explicitly_set: true } : {}
  };
}
function normalizeRosterExceptions(raw) {
  if (!Array.isArray(raw)) return [];
  return raw.map((row) => {
    const date = sanitizeTenantString2(row?.date || row?.day, 16);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return null;
    const type = sanitizeTenantString2(row?.type || row?.kind, 24).toLowerCase() || "off";
    if (type === "off" || type === "leave" || type === "absent") {
      return { date, type: "off" };
    }
    const blocks = Array.isArray(row?.blocks) ? row.blocks.map(normalizeRosterBlock).filter(Boolean) : [];
    return { date, type: "blocks", blocks };
  }).filter(Boolean);
}
function blocksForDate(roster, parts, exceptions) {
  const exception2 = (exceptions || []).find((row) => row.date === parts.date);
  if (exception2?.type === "off") return [];
  if (exception2?.type === "blocks") return exception2.blocks;
  return roster.days[parts.weekday] || [];
}
function previousDateParts(parts) {
  const noonUtc = Date.parse(`${parts.date}T12:00:00.000Z`);
  const prev = zonedParts(noonUtc - 24 * 60 * 60 * 1e3, parts.timeZone);
  return prev;
}
function blockContainsMinutes(block, minutes, { overnightTail = false } = {}) {
  const start = parseHm(block.start);
  const end = parseHm(block.end);
  if (start == null || end == null) return false;
  if (overnightTail) {
    return start > end && minutes < end;
  }
  if (start < end) return minutes >= start && minutes < end;
  return minutes >= start;
}
function breakContainsMinutes(block, minutes, { overnightTail = false } = {}) {
  const blockStart = parseHm(block.start);
  if (blockStart == null || !Array.isArray(block.breaks)) return false;
  for (const slot2 of block.breaks) {
    let start = parseHm(slot2.start);
    let end = parseHm(slot2.end);
    if (start == null || end == null) continue;
    if (start < blockStart) start += 1440;
    if (end <= start) end += 1440;
    const probe = overnightTail ? minutes + 1440 : minutes;
    if (probe >= start && probe < end) return true;
  }
  return false;
}
function dateIsAbsent(parts, exceptions) {
  return (exceptions || []).some((row) => row.date === parts?.date && row.type === "off");
}
function scheduledSlotAt(rosterRaw, atMs, exceptionsRaw = []) {
  const roster = normalizeWeeklyRoster(rosterRaw);
  const parts = zonedParts(atMs, roster.timezone);
  if (!parts) {
    return { active: false, inBreak: false, absent: false, undeterminable: true };
  }
  const exceptions = normalizeRosterExceptions(exceptionsRaw);
  if (dateIsAbsent(parts, exceptions)) {
    return { active: false, inBreak: false, absent: true, undeterminable: false };
  }
  const today = blocksForDate(roster, parts, exceptions);
  for (const block of today) {
    if (!blockContainsMinutes(block, parts.minutes)) continue;
    if (breakContainsMinutes(block, parts.minutes)) {
      return { active: false, inBreak: true, absent: false, undeterminable: false };
    }
    return { active: true, inBreak: false, absent: false, undeterminable: false };
  }
  const prevParts = previousDateParts(parts);
  if (prevParts) {
    const yesterday = blocksForDate(roster, prevParts, exceptions);
    for (const block of yesterday) {
      if (!blockContainsMinutes(block, parts.minutes, { overnightTail: true })) continue;
      if (breakContainsMinutes(block, parts.minutes, { overnightTail: true })) {
        return { active: false, inBreak: true, absent: false, undeterminable: false };
      }
      return { active: true, inBreak: false, absent: false, undeterminable: false };
    }
  }
  return { active: false, inBreak: false, absent: false, undeterminable: false };
}
function scheduledActiveAt(rosterRaw, atMs, exceptionsRaw = []) {
  return scheduledSlotAt(rosterRaw, atMs, exceptionsRaw).active === true;
}
function addMinutesInZone(atMs, minutes, timeZone) {
  return Number(atMs) + minutes * 6e4;
}
function nextShiftBoundaryMs(rosterRaw, atMs, exceptionsRaw = []) {
  const roster = normalizeWeeklyRoster(rosterRaw);
  const startActive = scheduledActiveAt(roster, atMs, exceptionsRaw);
  for (let step = 15; step <= 8 * 24 * 60; step += 15) {
    const probe = addMinutesInZone(atMs, step, roster.timezone);
    if (scheduledActiveAt(roster, probe, exceptionsRaw) !== startActive) {
      return probe;
    }
  }
  return addMinutesInZone(atMs, 8 * 24 * 60, roster.timezone);
}
function normalizeManualOverride(raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  const kind = sanitizeTenantString2(raw.kind || raw.type || raw.status, 24).toLowerCase();
  if (kind !== "active" && kind !== "inactive" && kind !== "paused") return null;
  const untilMs = Date.parse(String(raw.until || raw.until_iso || raw.untilIso || ""));
  return {
    kind,
    until: Number.isFinite(untilMs) ? new Date(untilMs).toISOString() : "",
    set_at: safeStr2(raw.set_at || raw.setAt, 80)
  };
}
function resolveManualOverride(overrideRaw, { atMs, roster, exceptions } = {}) {
  const override = normalizeManualOverride(overrideRaw);
  if (!override) return { active: false, kind: "", until: "" };
  const untilMs = Date.parse(override.until);
  if (Number.isFinite(untilMs) && untilMs <= Number(atMs)) {
    return { active: false, kind: "", until: override.until, expired: true };
  }
  if (!Number.isFinite(untilMs) && roster) {
    override.until = new Date(nextShiftBoundaryMs(roster, atMs, exceptions)).toISOString();
  }
  return { active: true, kind: override.kind, until: override.until };
}
function effectiveWorkState({
  driver,
  atMs,
  roster,
  exceptions,
  override
} = {}) {
  const isActive = driver?.is_active !== false && driver?.isActive !== false;
  const blocked = driver?.blocked === true || driver?.is_blocked === true;
  const rosterRaw = roster || driver?.weekly_roster || driver?.weeklyRoster;
  const exceptionsRaw = exceptions || driver?.roster_exceptions || driver?.rosterExceptions;
  const loadFailed = driverRosterLoadFailed(driver);
  const schedule = loadFailed ? {
    configured: true,
    active: false,
    undeterminable: true,
    error: "roster_load_failed"
  } : resolveScheduleState(rosterRaw, atMs, exceptionsRaw);
  const scheduled = schedule.active === true;
  const manual = resolveManualOverride(override || driver?.manual_override, {
    atMs,
    roster: rosterRaw,
    exceptions: exceptionsRaw
  });
  let working = schedule.undeterminable ? false : schedule.configured ? scheduled : true;
  if (manual.active && manual.kind === "inactive") working = false;
  if (manual.active && manual.kind === "active") working = true;
  return {
    account_active: isActive,
    blocked,
    scheduled_active: scheduled,
    roster_configured: schedule.configured === true,
    schedule_undeterminable: schedule.undeterminable === true,
    manual_override: manual,
    working: isActive && !blocked && working
  };
}
function readDriverPause(driver) {
  const pausedAt = Date.parse(String(driver?.paused_at || driver?.pausedAt || ""));
  const pausedUntil = Date.parse(String(driver?.paused_until || driver?.pausedUntil || ""));
  if (!Number.isFinite(pausedAt) || !Number.isFinite(pausedUntil) || pausedUntil <= pausedAt) {
    return null;
  }
  return {
    pausedAt,
    pausedUntil: Math.min(pausedUntil, pausedAt + DRIVER_PAUSE_MAX_MS2)
  };
}
function pauseBlocksInstant(driver, atMs) {
  const pause = readDriverPause(driver);
  const at = Number(atMs);
  if (!pause || !Number.isFinite(at)) return false;
  return at < pause.pausedUntil;
}
var DEFAULT_DISPATCH_TIMEZONE;
var LIVE_HEARTBEAT_TTL_MS2;
var HEARTBEAT_WRITE_THROTTLE_MS2;
var DRIVER_PAUSE_MAX_MS2;
var NOW_PICKUP_GRACE_MS2;
var AVAILABILITY2;
var WEEKDAY_KEYS;
var init_company_dispatch2 = __esm2({
  "../booking/modules/company_dispatch.mjs"() {
    init_parsing_utils2();
    DEFAULT_DISPATCH_TIMEZONE = "Europe/Brussels";
    LIVE_HEARTBEAT_TTL_MS2 = 3 * 60 * 1e3;
    HEARTBEAT_WRITE_THROTTLE_MS2 = 45 * 1e3;
    DRIVER_PAUSE_MAX_MS2 = 60 * 60 * 1e3;
    NOW_PICKUP_GRACE_MS2 = 2 * 60 * 1e3;
    AVAILABILITY2 = {
      OFFLINE: "OFFLINE",
      AVAILABLE: "AVAILABLE",
      ON_TRIP: "ON_TRIP",
      PAUSED: "PAUSED"
    };
    WEEKDAY_KEYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];
    __name(normalizeDispatchAvailability2, "normalizeDispatchAvailability");
    __name(parseHm, "parseHm");
    __name(formatHm, "formatHm");
    __name(dispatchTimezoneIsSupported, "dispatchTimezoneIsSupported");
    __name(weeklyRosterHasConfiguredBlocks, "weeklyRosterHasConfiguredBlocks");
    __name(weeklyRosterIsConfigured, "weeklyRosterIsConfigured");
    __name(driverRosterLoadFailed, "driverRosterLoadFailed");
    __name(resolveScheduleState, "resolveScheduleState");
    __name(zonedParts, "zonedParts");
    __name(normalizeRosterBlock, "normalizeRosterBlock");
    __name(normalizeWeeklyRoster, "normalizeWeeklyRoster");
    __name(normalizeRosterExceptions, "normalizeRosterExceptions");
    __name(blocksForDate, "blocksForDate");
    __name(previousDateParts, "previousDateParts");
    __name(blockContainsMinutes, "blockContainsMinutes");
    __name(breakContainsMinutes, "breakContainsMinutes");
    __name(dateIsAbsent, "dateIsAbsent");
    __name(scheduledSlotAt, "scheduledSlotAt");
    __name(scheduledActiveAt, "scheduledActiveAt");
    __name(addMinutesInZone, "addMinutesInZone");
    __name(nextShiftBoundaryMs, "nextShiftBoundaryMs");
    __name(normalizeManualOverride, "normalizeManualOverride");
    __name(resolveManualOverride, "resolveManualOverride");
    __name(effectiveWorkState, "effectiveWorkState");
    __name(readDriverPause, "readDriverPause");
    __name(pauseBlocksInstant, "pauseBlocksInstant");
  }
});
var object2 = /* @__PURE__ */ __name((value) => value && typeof value === "object" && !Array.isArray(value), "object");
function stable3(value) {
  if (Array.isArray(value)) return value.map(stable3);
  if (!object2(value)) return value;
  return Object.fromEntries(Object.keys(value).sort().map((key2) => [key2, stable3(value[key2])]));
}
__name(stable3, "stable");
async function legacyScopeEvidenceDigest2(value) {
  const bytes32 = new TextEncoder().encode(JSON.stringify(stable3(value)));
  const digest322 = await crypto.subtle.digest("SHA-256", bytes32);
  return [...new Uint8Array(digest322)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}
__name(legacyScopeEvidenceDigest2, "legacyScopeEvidenceDigest");
var confirmedTestStreetIds = Object.freeze([
  "street_1785072158262_tbs6g6k2",
  "street_1785222028308_sb3o00k1",
  "street_1785243385514_76ascekh",
  "street_1786035880780_1dghte50",
  "street_1786178313850_09gfx43a",
  "street_1786790574824_6xndx89g",
  "street_1788981344912_3f716i7j"
]);
var confirmedTestStreetScope = Object.freeze({
  tenant_id: "fluxidi_fluxidi_ddmh9g",
  company_id: "fluxidi_fluxidi_ddmh9g"
});
async function retireConfirmedTestTrip(body, hooks) {
  const scope2 = confirmedTestStreetScope, id22 = body.booking_id;
  if (!confirmedTestStreetIds.includes(id22) || body.tenant_id !== scope2.tenant_id || body.company_id !== scope2.company_id) return { ok: false, error: "test_trip_not_confirmed", status: 403 };
  const booking = await hooks.booking(id22, scope2);
  if (!booking || booking.tenant_id !== scope2.tenant_id || booking.company_id !== scope2.company_id || booking.status !== "CANCELLED" || booking.booking?.status !== "CANCELLED" || booking.source !== "street_ride" || booking.ride_type !== "direct") {
    return { ok: false, error: "test_trip_cancelled_booking_required", status: 409 };
  }
  const tripId = booking.tracking_trip_id || booking.trackingTripId;
  if (!tripId || booking.tracking_trip_id && booking.trackingTripId && booking.tracking_trip_id !== booking.trackingTripId) {
    return { ok: false, error: "test_trip_identity_conflict", status: 409 };
  }
  const loaded = await hooks.trip(tripId, scope2), trip = loaded.trip;
  if (!trip) return { ok: true, booking_id: id22, trip_id: tripId, absent: true };
  if (trip.tenant_id !== scope2.tenant_id || trip.company_id !== scope2.company_id || (trip.booking_id || trip.bookingId) !== id22 || trip.booking_id && trip.bookingId && trip.booking_id !== trip.bookingId || trip.trip_id !== tripId || !booking.direct_ride_key || trip.direct_ride_key !== booking.direct_ride_key || trip.kind !== "direct") {
    return { ok: false, error: "test_trip_identity_conflict", status: 403 };
  }
  if (!["active", "cancelled"].includes(trip.status) || trip.booking_finalized === true || trip.booking_finalize_state || trip.paid_at || trip.payment_id || trip.payment_status === "paid" || trip.total_eur != null || trip.price_incl_vat != null) {
    return { ok: false, error: "test_trip_financial_or_lifecycle_review_required", status: 409 };
  }
  const digest322 = await legacyScopeEvidenceDigest2({ scope: scope2, id: id22, trip });
  if (body.dry_run !== false) return { ok: true, dry_run: true, booking_id: id22, trip_id: tripId, review_digest: digest322 };
  if (body.review_digest !== digest322 && body.review_digest !== trip.test_retirement?.review_digest) {
    return { ok: false, error: "test_trip_review_changed", status: 409 };
  }
  const next = structuredClone(trip);
  if (!next.test_retirement) {
    next.status = "cancelled";
    next.archived = true;
    next.stopped_at = (/* @__PURE__ */ new Date()).toISOString();
    next.archived_at = next.stopped_at;
    next.test_retirement = { review_digest: digest322, reason: "operator_confirmed_historical_test", at: next.stopped_at };
    await hooks.persist(loaded.key, next);
  }
  await hooks.release(next);
  return { ok: true, booking_id: id22, trip_id: tripId, status: "cancelled", archived: true };
}
__name(retireConfirmedTestTrip, "retireConfirmedTestTrip");
function _asObject(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : null;
}
__name(_asObject, "_asObject");
function _finiteNumber(value) {
  if (value == null || value === "") return null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}
__name(_finiteNumber, "_finiteNumber");
function _label(value) {
  if (value == null) return "";
  const text22 = String(value).trim();
  return text22 ? text22.slice(0, 256) : "";
}
__name(_label, "_label");
function hasTrustedOriginCoords(origin) {
  const obj = _asObject(origin);
  if (!obj) return false;
  const lat = _finiteNumber(obj.lat ?? obj.latitude);
  const lon = _finiteNumber(obj.lon ?? obj.lng ?? obj.longitude);
  if (lat == null || lon == null) return false;
  if (lat < -90 || lat > 90 || lon < -180 || lon > 180) return false;
  if (lat === 0 && lon === 0) return false;
  return true;
}
__name(hasTrustedOriginCoords, "hasTrustedOriginCoords");
function readTrustedOriginCoords(origin) {
  if (!hasTrustedOriginCoords(origin)) return null;
  const obj = _asObject(origin);
  return {
    lat: _finiteNumber(obj.lat ?? obj.latitude),
    lon: _finiteNumber(obj.lon ?? obj.lng ?? obj.longitude),
    label: _label(obj.label ?? obj.address ?? obj.text)
  };
}
__name(readTrustedOriginCoords, "readTrustedOriginCoords");
function resolvePlannedStopOrigin({
  payloadOrigin = null,
  existingTripOrigin = null,
  sessionOrigin = null,
  sessionPickup = null
} = {}) {
  const payload = _asObject(payloadOrigin);
  const payloadCoords = readTrustedOriginCoords(payload);
  const reused = payloadCoords || readTrustedOriginCoords(existingTripOrigin) || readTrustedOriginCoords(sessionOrigin) || readTrustedOriginCoords(sessionPickup);
  if (!reused) {
    return payload;
  }
  const label222 = _label(payload?.label ?? payload?.address ?? reused.label);
  const out = { lat: reused.lat, lon: reused.lon };
  if (label222) out.label = label222;
  return out;
}
__name(resolvePlannedStopOrigin, "resolvePlannedStopOrigin");
var VEHICLE_FALLBACK_ASSETS22 = Object.freeze([
  "assets/vehicles/fallback/v1/fluxidi_vehicle_compact_hatchback_v1.webp",
  "assets/vehicles/fallback/v1/fluxidi_vehicle_sedan_v1.webp",
  "assets/vehicles/fallback/v1/fluxidi_vehicle_station_wagon_v1.webp",
  "assets/vehicles/fallback/v1/fluxidi_vehicle_suv_crossover_v1.webp",
  "assets/vehicles/fallback/v1/fluxidi_vehicle_mpv_minivan_v1.webp",
  "assets/vehicles/fallback/v1/fluxidi_vehicle_passenger_minibus_v1.webp",
  "assets/vehicles/fallback/v1/fluxidi_vehicle_premium_limousine_v1.webp",
  "assets/vehicles/fallback/v1/fluxidi_vehicle_wheelchair_accessible_v1.webp",
  "assets/vehicles/fallback/v1/fluxidi_vehicle_stretch_limousine_v1.webp",
  "assets/vehicles/fallback/v1/fluxidi_vehicle_hummer_stretch_v1.webp"
]);
function normalizeVehicleFallbackAsset22(value) {
  const asset = String(value ?? "").trim();
  return VEHICLE_FALLBACK_ASSETS22.includes(asset) ? asset : "";
}
__name(normalizeVehicleFallbackAsset22, "normalizeVehicleFallbackAsset");
async function sha256Hex2(text22) {
  const digest322 = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(String(text22 || "")));
  return [...new Uint8Array(digest322)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
__name(sha256Hex2, "sha256Hex");
var SNAPSHOT_CONTRACT_VERSION2 = 1;
var GRANT_ACCESS_TTL_MS2 = 9e4;
var ETA_CACHE_TTL_MS = 45e3;
var ETA_POSITION_BUCKET_DEG = 2e-3;
var LIVE_PHASES2 = /* @__PURE__ */ new Set(["en_route_pickup", "arrived_pickup", "in_progress"]);
var TERMINAL_PHASES22 = /* @__PURE__ */ new Set(["stopped", "completed", "cancelled"]);
var PUBLIC_DRIVER_FIELDS2 = ["display_name"];
var PUBLIC_VEHICLE_FIELDS2 = ["label", "color", "license_plate"];
function trackingPhaseForStatus22(status) {
  const token = String(status || "").trim().toLowerCase().replace(/[\s-]+/g, "_");
  if (!token || token === "unassigned" || token === "quoted" || token === "pending") return "unassigned";
  if (token === "assigned" || token === "accepted" || token === "confirmed") return "assigned";
  if (token === "en_route" || token === "en_route_pickup" || token === "on_the_way" || token === "driving_to_pickup") {
    return "en_route_pickup";
  }
  if (token === "arrived_pickup") return "arrived_pickup";
  if (token === "started" || token === "in_progress" || token === "on_trip" || token === "picked_up" || token === "driving") {
    return "in_progress";
  }
  if (token === "stopped" || token === "stop") return "stopped";
  if (token === "completed" || token === "complete") return "completed";
  if (["cancelled", "canceled", "no_show", "rejected", "expired"].includes(token)) return "cancelled";
  return "assigned";
}
__name(trackingPhaseForStatus22, "trackingPhaseForStatus");
function etaTargetForPhase2(phase) {
  if (phase === "en_route_pickup") return "pickup";
  if (phase === "in_progress") return "destination";
  return null;
}
__name(etaTargetForPhase2, "etaTargetForPhase");
function publicDriver22(input) {
  const source = input && typeof input === "object" ? input : {};
  const out = {};
  for (const key2 of PUBLIC_DRIVER_FIELDS2) {
    const value = source[key2] ?? source.public_driver?.[key2];
    if (value) out[key2] = String(value).slice(0, 80);
  }
  const photo = publicPhotoUrl2(source.photo_url ?? source.public_photo_url ?? source.public_driver?.photo_url);
  if (photo) out.photo_url = photo;
  const contact = source.customer_contact;
  if (contact?.customer_allowed === true && /^\+[1-9][0-9]{6,14}$/.test(String(contact.phone_e164 || "")) && (contact.call_allowed === true || contact.whatsapp_allowed === true)) {
    out.customer_contact = {
      customer_allowed: true,
      phone_e164: contact.phone_e164,
      call_allowed: contact.call_allowed === true,
      whatsapp_allowed: contact.whatsapp_allowed === true
    };
  }
  const average = Number(source.rating_average), count = Number(source.rating_count);
  if (Number.isFinite(average) && average > 0 && average <= 5 && Number.isInteger(count) && count > 0) {
    out.rating_average = average;
    out.rating_count = count;
  }
  return out;
}
__name(publicDriver22, "publicDriver");
function publicPhotoUrl2(value) {
  try {
    const url = new URL(String(value ?? ""));
    return url.protocol === "https:" && !url.username && !url.password && url.href.length <= 2048 ? url.href : "";
  } catch {
    return "";
  }
}
__name(publicPhotoUrl2, "publicPhotoUrl");
function publicVehicle22(input) {
  const source = input && typeof input === "object" ? input : {};
  const assigned = source.assigned_vehicle || source.vehicle || source;
  const out = {};
  for (const key2 of PUBLIC_VEHICLE_FIELDS2) {
    const value = assigned[key2] ?? assigned[`vehicle_${key2}`];
    if (value) out[key2] = String(value).slice(0, 80);
  }
  const vehicleId = text2(assigned.vehicle_id ?? assigned.vehicleId, 96);
  if (vehicleId) out.vehicle_id = vehicleId;
  const fallbackAsset = normalizeVehicleFallbackAsset22(assigned.fallback_asset ?? assigned.fallbackAsset);
  if (fallbackAsset) out.fallback_asset = fallbackAsset;
  const photo = publicPhotoUrl2(assigned.photo_url ?? assigned.public_photo_url);
  if (photo) out.photo_url = photo;
  return out;
}
__name(publicVehicle22, "publicVehicle");
function publicOperationalRoute22(value) {
  const address = value?.destination_address ?? value?.destination?.address;
  const end = value?.expected_end_iso, updated = value?.updated_at;
  if (typeof address !== "string" || !address.trim() || address.length > 400 || typeof end !== "string" || !Number.isFinite(Date.parse(end))) return null;
  return {
    destination_address: address.trim(),
    expected_end_iso: new Date(end).toISOString(),
    ...typeof updated === "string" && Number.isFinite(Date.parse(updated)) ? { updated_at: new Date(updated).toISOString() } : {}
  };
}
__name(publicOperationalRoute22, "publicOperationalRoute");
function text2(value, max) {
  const raw = String(value ?? "").trim();
  return raw ? raw.slice(0, max) : "";
}
__name(text2, "text");
function grantKey22(bookingId, leg) {
  return `${text2(bookingId, 96)}|${text2(leg, 200) || "primary"}`;
}
__name(grantKey22, "grantKey");
function applyCustomerLifecycle22(store, event, nowMs) {
  const result2 = applyScopedCustomerLifecycle2(store, event, nowMs);
  if (result2.applied && event?.disable_primary === true && result2.grant && TERMINAL_PHASES22.has(result2.grant.tracking_phase)) {
    const grant = result2.grant;
    grant.revoked_token_hashes = [...new Set([...grant.revoked_token_hashes || [], ...grant.access_token_hashes || [], grant.access_token_hash].filter(Boolean))];
    grant.access_token_hash = "";
    grant.access_token_hashes = [];
  }
  if (result2.applied && event?.disable_primary === true && event.operational_leg && event.operational_leg !== "primary") {
    const key2 = grantKey22(event.booking_id, "primary");
    const old = result2.store.grants[key2];
    result2.store.grants[key2] = {
      ...old,
      leg_scope_retired: true,
      position_allowed: false,
      access_token_hash: "",
      access_token_hashes: [],
      tracking_phase: "stopped"
    };
  }
  return result2;
}
__name(applyCustomerLifecycle22, "applyCustomerLifecycle");
function applyScopedCustomerLifecycle2(store, event, nowMs) {
  const next = { grants: { ...store?.grants || {} } };
  const bookingId = text2(event?.booking_id, 96);
  const tenantId = text2(event?.tenant_id, 80);
  const companyId = text2(event?.company_id, 80);
  if (!bookingId || !tenantId || !companyId) {
    return { store: next, applied: false, reason: "identity_missing" };
  }
  const leg = text2(event?.operational_leg, 200) || "primary";
  const key2 = grantKey22(bookingId, leg);
  const current = next.grants[key2] || null;
  if (current?.leg_scope_retired) return { store: next, applied: false, confirmed: false, reason: "leg_scope_retired", grant: current };
  const seq = Number(event?.lifecycle_seq);
  if (!Number.isFinite(seq)) {
    return { store: next, applied: false, reason: "lifecycle_seq_required" };
  }
  const kind = text2(event?.kind, 20) || "lifecycle";
  const phase = trackingPhaseForStatus22(event?.tracking_phase || event?.booking_status);
  const assignmentVersion = Number(event?.assignment_version);
  const tokenHash = text2(event?.access_token_hash, 128);
  if (event?.sync_ok === false) {
    return {
      store: next,
      applied: false,
      confirmed: false,
      reason: "sync_report_ignored",
      grant: current
    };
  }
  if (kind === "session_start" || kind === "session_stop") {
    const sessionId = text2(event?.session_id, 128);
    const matches222 = current && current.tenant_id === tenantId && current.company_id === companyId && assignmentVersion > 0 && assignmentVersion === current.assignment_version && text2(event?.driver_id, 96) === current.driver_id && sessionId;
    if (!matches222 || kind === "session_start" && seq !== current.lifecycle_seq || kind === "session_stop" && sessionId !== current.session_id) {
      return { store: next, applied: false, confirmed: false, reason: "session_assignment_mismatch", grant: current };
    }
    if (TERMINAL_PHASES22.has(current.tracking_phase)) {
      return { store: next, applied: false, confirmed: kind === "session_stop", reason: "session_already_closed", grant: current };
    }
    const grant2 = { ...current, session_id: sessionId, updated_at: new Date(nowMs).toISOString() };
    if (kind === "session_stop") {
      grant2.tracking_phase = "stopped";
      grant2.position_allowed = false;
      grant2.revoked_token_hashes = [...new Set([
        ...current.revoked_token_hashes || [],
        ...current.access_token_hashes || [],
        current.access_token_hash
      ].filter(Boolean))];
    }
    next.grants[key2] = grant2;
    return { store: next, applied: true, confirmed: true, reason: kind, grant: grant2 };
  }
  if (current && Number.isFinite(assignmentVersion) && assignmentVersion < current.assignment_version) {
    return { store: next, applied: false, confirmed: false, reason: "stale_assignment_version", grant: current };
  }
  if (current && TERMINAL_PHASES22.has(current.tracking_phase) && !(assignmentVersion > current.assignment_version) && !TERMINAL_PHASES22.has(phase)) {
    return { store: next, applied: false, confirmed: false, reason: "session_closed", grant: current };
  }
  if (current && seq < current.lifecycle_seq) {
    return { store: next, applied: false, confirmed: false, reason: "stale_lifecycle_seq", grant: current };
  }
  const terminalCorrection = current && assignmentVersion === current.assignment_version && seq === current.lifecycle_seq && ["completed", "cancelled"].includes(phase) && trackingPhaseForStatus22(event.booking_status) === phase && !TERMINAL_PHASES22.has(current.tracking_phase);
  if (current && seq === current.lifecycle_seq && kind === "lifecycle" && !terminalCorrection) {
    return { store: next, applied: false, confirmed: true, reason: "duplicate_lifecycle_seq", grant: current };
  }
  if (current && seq === current.lifecycle_seq && !terminalCorrection && (kind === "renew" || kind === "issue")) {
    const versionOk = !Number.isFinite(assignmentVersion) || assignmentVersion === current.assignment_version;
    const phaseOk = phase === current.tracking_phase;
    if (!versionOk || !phaseOk) {
      return { store: next, applied: false, confirmed: false, reason: "renew_mismatch", grant: current };
    }
    const hashes = Array.isArray(current.access_token_hashes) ? [...current.access_token_hashes] : [];
    if (current.access_token_hash && !hashes.includes(current.access_token_hash)) hashes.push(current.access_token_hash);
    const grant2 = {
      ...current,
      // Metadata only: refresh the confirmed assignment, never a prior label.
      ...assignmentVersion === current.assignment_version && text2(event?.driver_id, 96) === current.driver_id ? {
        driver: publicDriver22(event?.driver),
        vehicle: publicVehicle22(event?.assigned_vehicle || event?.vehicle)
      } : {},
      access_until_ms: TERMINAL_PHASES22.has(current.tracking_phase) ? current.access_until_ms : nowMs + GRANT_ACCESS_TTL_MS2,
      updated_at: new Date(nowMs).toISOString()
    };
    if (kind === "issue" && tokenHash && !TERMINAL_PHASES22.has(current.tracking_phase) && !(grant2.revoked_token_hashes || []).includes(tokenHash)) {
      if (!hashes.includes(tokenHash)) hashes.push(tokenHash);
      grant2.access_token_hash = tokenHash;
      grant2.access_token_hashes = hashes;
    }
    next.grants[key2] = grant2;
    return { store: next, applied: true, confirmed: true, reason: kind, grant: grant2 };
  }
  const reassigned = current && Number.isFinite(assignmentVersion) && assignmentVersion !== current.assignment_version;
  const grant = {
    contract_version: SNAPSHOT_CONTRACT_VERSION2,
    tenant_id: tenantId,
    company_id: companyId,
    booking_id: bookingId,
    operational_leg: leg,
    customer_id: text2(event?.customer_id, 96) || current?.customer_id || "",
    assignment_version: Number.isFinite(assignmentVersion) ? assignmentVersion : current?.assignment_version || 0,
    tracking_phase: phase,
    booking_status: text2(event?.booking_status, 40),
    session_id: text2(event?.session_id, 128) || (reassigned ? "" : current?.session_id || ""),
    driver_id: text2(event?.driver_id, 96),
    access_token_hash: tokenHash || (reassigned ? "" : current?.access_token_hash || ""),
    access_token_hashes: tokenHash ? [tokenHash] : reassigned ? [] : [...current?.access_token_hashes || []],
    revoked_token_hashes: reassigned ? [...new Set([...current?.revoked_token_hashes || [], ...current?.access_token_hashes || [], current?.access_token_hash].filter(Boolean))] : [...current?.revoked_token_hashes || []],
    driver: publicDriver22(event?.driver),
    vehicle: publicVehicle22(event?.assigned_vehicle || event?.vehicle),
    pickup: pointOrNull2(event?.pickup),
    destination: pointOrNull2(event?.destination),
    operational_route: phase === "in_progress" ? publicOperationalRoute22(event?.operational_route) : null,
    position_allowed: LIVE_PHASES2.has(phase),
    sync_state: "ok",
    lifecycle_seq: seq,
    access_until_ms: nowMs + GRANT_ACCESS_TTL_MS2,
    updated_at: new Date(nowMs).toISOString()
  };
  if (event?.revoke_access_token_hash) {
    grant.revoked_token_hashes = [.../* @__PURE__ */ new Set([...grant.revoked_token_hashes, text2(event.revoke_access_token_hash, 128)])];
    if (grant.access_token_hash === text2(event.revoke_access_token_hash, 128)) grant.access_token_hash = "";
  }
  next.grants[key2] = grant;
  return { store: next, applied: true, confirmed: true, reason: reassigned ? "reassigned" : "applied", grant };
}
__name(applyScopedCustomerLifecycle2, "applyScopedCustomerLifecycle");
function pointOrNull2(value) {
  const latitude = Number(value?.latitude ?? value?.lat);
  const longitude = Number(value?.longitude ?? value?.lon ?? value?.lng);
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return null;
  return { latitude, longitude };
}
__name(pointOrNull2, "pointOrNull");
function customerAccessAllowed22(grant, query) {
  if (!grant || grant.leg_scope_retired) return { ok: false, error: "not_found", status: 404 };
  if (text2(query?.tenant_id, 80) !== grant.tenant_id) return { ok: false, error: "not_found", status: 404 };
  if (text2(query?.company_id, 80) !== grant.company_id) return { ok: false, error: "not_found", status: 404 };
  if (text2(query?.booking_id, 96) !== grant.booking_id) return { ok: false, error: "not_found", status: 404 };
  const leg = text2(query?.operational_leg, 200) || "primary";
  if (leg !== grant.operational_leg) return { ok: false, error: "not_found", status: 404 };
  if (text2(query?.customer_id, 96) && text2(query.customer_id, 96) !== grant.customer_id) {
    return { ok: false, error: "not_found", status: 404 };
  }
  const token = text2(query?.access_token_hash, 128);
  const hashes = Array.isArray(grant.access_token_hashes) ? grant.access_token_hashes : [];
  const previousVersion = Number(text2(query?.assignment_version, 20));
  if (token && (grant.revoked_token_hashes || []).includes(token) && Number.isInteger(previousVersion) && previousVersion > 0 && previousVersion < grant.assignment_version && !TERMINAL_PHASES22.has(grant.tracking_phase)) {
    return { ok: false, error: "assignment_changed", status: 409 };
  }
  if (!token || token !== grant.access_token_hash && !hashes.includes(token)) {
    return { ok: false, error: "not_found", status: 404 };
  }
  if ((grant.revoked_token_hashes || []).includes(token)) return { ok: false, error: "not_found", status: 404 };
  const askedVersionRaw = text2(query?.assignment_version, 20);
  const askedVersion = askedVersionRaw ? Number(askedVersionRaw) : NaN;
  if (Number.isFinite(askedVersion) && askedVersion !== grant.assignment_version) {
    return { ok: false, error: "not_found", status: 404 };
  }
  const askedSession = text2(query?.session_id, 128);
  if (askedSession && grant.session_id && askedSession !== grant.session_id) {
    return { ok: false, error: "not_found", status: 404 };
  }
  return { ok: true };
}
__name(customerAccessAllowed22, "customerAccessAllowed");
function projectCustomerSnapshot22({ grant, driver, nowMs, eta, route }) {
  const phase = grant?.tracking_phase || "unassigned";
  const expired = !grant || !Number.isFinite(grant.access_until_ms) || nowMs > grant.access_until_ms;
  const syncClosed = grant?.sync_state === "failed";
  const terminal2 = TERMINAL_PHASES22.has(phase) || expired || syncClosed || grant?.position_allowed !== true;
  const sameDriver = driver && grant?.driver_id && driver.driver_id === grant.driver_id;
  const fresh = sameDriver && driver.position_stale !== true && driver.reliable_for_eta !== false;
  const position = !terminal2 && fresh ? {
    latitude: driver.latitude,
    longitude: driver.longitude,
    heading: driver.heading ?? null,
    captured_at: driver.position_captured_at || driver.captured_at || null
  } : null;
  const feed = !driver || !sameDriver ? "missing" : driver.position_stale ? "stale" : driver.location_feed || "live";
  const target2 = etaTargetForPhase2(phase);
  const etaOut = !terminal2 && target2 && eta && eta.target === target2 ? {
    target: target2,
    source: eta.source || "mapbox/driving-traffic",
    duration_seconds: eta.duration_seconds,
    valid_until: eta.valid_until,
    distance_meters: eta.distance_meters ?? null
  } : null;
  return {
    ok: true,
    contract_version: SNAPSHOT_CONTRACT_VERSION2,
    tenant_id: grant.tenant_id,
    company_id: grant.company_id,
    booking_id: grant.booking_id,
    operational_leg: grant.operational_leg,
    assignment_version: grant.assignment_version,
    response_version: grant.lifecycle_seq,
    booking_status: grant.booking_status || phase,
    tracking_phase: terminal2 && expired && LIVE_PHASES2.has(phase) ? "expired" : phase,
    position,
    pickup: terminal2 ? null : grant.pickup ?? null,
    destination: terminal2 ? null : grant.destination ?? null,
    operational_route: !terminal2 && phase === "in_progress" ? publicOperationalRoute22(grant.operational_route) : null,
    feed: {
      health: terminal2 ? "closed" : feed,
      position_captured_at: sameDriver ? driver.position_captured_at || driver.captured_at || null : null,
      last_seen_at: sameDriver ? driver.last_seen_at || null : null
    },
    eta: etaOut,
    route: !terminal2 && phase !== "arrived_pickup" && route ? route : null,
    driver: terminal2 ? null : grant.driver,
    vehicle: terminal2 ? null : grant.vehicle,
    refresh: {
      poll_after_seconds: terminal2 ? 0 : 10,
      access_until: grant.access_until_ms ? new Date(grant.access_until_ms).toISOString() : null
    }
  };
}
__name(projectCustomerSnapshot22, "projectCustomerSnapshot");
function publicLiveMayExposePosition(session, grant, { requireGrant = false } = {}) {
  const status = String(session?.status || "").toLowerCase();
  if (status === "stopped" || status === "completed" || status === "cancelled" || status === "canceled") {
    return false;
  }
  if (!grant) return requireGrant ? false : true;
  if (TERMINAL_PHASES22.has(grant.tracking_phase) || grant.position_allowed !== true || grant.sync_state === "failed") {
    return false;
  }
  if (Number.isFinite(grant.access_until_ms) && Date.now() > grant.access_until_ms) return false;
  if (grant.session_id && session?.session_id && grant.session_id !== session.session_id) return false;
  return true;
}
__name(publicLiveMayExposePosition, "publicLiveMayExposePosition");
function positionBucket(latitude, longitude) {
  const lat = Math.round(Number(latitude) / ETA_POSITION_BUCKET_DEG) * ETA_POSITION_BUCKET_DEG;
  const lon = Math.round(Number(longitude) / ETA_POSITION_BUCKET_DEG) * ETA_POSITION_BUCKET_DEG;
  return `${lat.toFixed(3)},${lon.toFixed(3)}`;
}
__name(positionBucket, "positionBucket");
function createEtaCache(fetcher, now = () => Date.now()) {
  const cache = /* @__PURE__ */ new Map();
  const inflight = /* @__PURE__ */ new Map();
  return {
    cache,
    inflight,
    async resolve({ origin, destination, target: target2 }) {
      if (!origin || !destination || !target2) return null;
      const key2 = `${target2}|${positionBucket(origin.latitude, origin.longitude)}|${destination.latitude},${destination.longitude}`;
      const hit = cache.get(key2);
      const nowMs = now();
      if (hit && hit.expires_at_ms > nowMs) return { ...hit.value, cache: "hit" };
      if (inflight.has(key2)) {
        const shared = await inflight.get(key2);
        return { ...shared, cache: "joined" };
      }
      const pending = Promise.resolve().then(() => fetcher({ origin, destination, target: target2 })).then((value2) => {
        const stored = {
          target: target2,
          source: "mapbox/driving-traffic",
          duration_seconds: value2.duration_seconds,
          distance_meters: value2.distance_meters ?? null,
          route: value2.route ?? null,
          valid_until: new Date(now() + ETA_CACHE_TTL_MS).toISOString()
        };
        cache.set(key2, { value: stored, expires_at_ms: now() + ETA_CACHE_TTL_MS });
        return stored;
      }).finally(() => {
        inflight.delete(key2);
      });
      inflight.set(key2, pending);
      const value = await pending;
      return { ...value, cache: "miss" };
    }
  };
}
__name(createEtaCache, "createEtaCache");
var CUSTOMER_GRANT_STORAGE_KEY2 = "customer_grants_v1";
var CUSTOMER_GRANT_ARCHIVE_AFTER_MS22 = 24 * 60 * 6e4;
var CUSTOMER_GRANT_SNAPSHOT_MAX_BYTES22 = 8 * 1024 * 1024;
var FORMAT3 = "customer-grant-pages-v2";
var INLINE_BYTES32 = 80 * 1024;
var PAGE_CHARS32 = 24 * 1024;
var ARCHIVE_BATCH3 = 96;
var encoder32 = new TextEncoder();
var bytes3 = /* @__PURE__ */ __name((text22) => encoder32.encode(text22), "bytes");
var map2 = /* @__PURE__ */ __name((value) => value && typeof value === "object" && !Array.isArray(value), "map");
var sameScope32 = /* @__PURE__ */ __name((a, b) => a?.tenant_id === b?.tenant_id && a?.company_id === b?.company_id, "sameScope");
async function digest4(text22) {
  return [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes3(text22)))].map((value) => value.toString(16).padStart(2, "0")).join("");
}
__name(digest4, "digest");
async function customerGrantArchiveKey2(key2) {
  if (typeof key2 !== "string" || !key2 || key2.length > 300) throw Error("customer_grant_identity_invalid");
  return "customer_grant_archive_v1:" + await digest4(key2);
}
__name(customerGrantArchiveKey2, "customerGrantArchiveKey");
function validateStore2(store) {
  if (!map2(store) || !map2(store.grants)) throw Error("customer_grant_storage_invalid");
  return store;
}
__name(validateStore2, "validateStore");
function manifestPages3(root) {
  if (!Array.isArray(root.pages) || !root.pages.length || root.pages.length > 1024 || !/^[a-f\d-]{36}$/.test(root.generation || "") || !Number.isSafeInteger(root.bytes) || root.bytes < 1 || root.bytes > CUSTOMER_GRANT_SNAPSHOT_MAX_BYTES22 || !/^[a-f\d]{64}$/.test(root.sha256 || "") || root.pages.some((key2, i) => key2 !== `customer_grant_page_v2:${root.generation}:${i}`)) {
    throw Error("customer_grant_manifest_invalid");
  }
  return root.pages;
}
__name(manifestPages3, "manifestPages");
async function readCustomerGrantSnapshot22(storage) {
  const root = await storage.get(CUSTOMER_GRANT_STORAGE_KEY2);
  if (root == null) return { grants: {} };
  if (root.format !== FORMAT3) return validateStore2(root);
  const parts = [];
  for (const key2 of manifestPages3(root)) {
    const part = await storage.get(key2);
    if (typeof part !== "string" || part.length > PAGE_CHARS32) throw Error("customer_grant_page_missing");
    parts.push(part);
  }
  const text22 = parts.join("");
  if (bytes3(text22).length !== root.bytes || await digest4(text22) !== root.sha256) throw Error("customer_grant_checksum_invalid");
  return validateStore2(JSON.parse(text22));
}
__name(readCustomerGrantSnapshot22, "readCustomerGrantSnapshot");
async function readStoredCustomerGrant22(storage, store, key2, scope2) {
  if (Object.hasOwn(store.grants, key2)) return store.grants[key2];
  const cold = await storage.get(await customerGrantArchiveKey2(key2));
  if (cold == null) return null;
  const row = cold.record;
  if (cold.key !== key2 || !sameScope32(cold.scope, scope2) || !map2(row) || !/^[a-f\d]{64}$/.test(cold.sha256 || "") || await digest4(JSON.stringify(row)) !== cold.sha256 || row.position_allowed === true || !(row.leg_scope_retired || TERMINAL_PHASES22.has(row.tracking_phase)) || row.tenant_id && row.tenant_id !== scope2.tenant_id || row.company_id && row.company_id !== scope2.company_id || !row.leg_scope_retired && (!sameScope32(row, scope2) || grantKey22(row.booking_id, row.operational_leg) !== key2 || !Number.isFinite(row.lifecycle_seq) || !Number.isFinite(row.assignment_version))) {
    throw Error("customer_grant_archive_invalid");
  }
  return row;
}
__name(readStoredCustomerGrant22, "readStoredCustomerGrant");
async function hydrateCustomerGrantEvent22(storage, store, event, scope2) {
  const keys = [grantKey22(event.booking_id, event.operational_leg)];
  if (event.disable_primary === true && event.operational_leg && event.operational_leg !== "primary") {
    keys.push(grantKey22(event.booking_id, "primary"));
  }
  let next = store;
  for (const key2 of keys) {
    if (Object.hasOwn(next.grants, key2)) continue;
    const row = await readStoredCustomerGrant22(storage, next, key2, scope2);
    if (row) next = { ...next, grants: { ...next.grants, [key2]: row } };
  }
  return next;
}
__name(hydrateCustomerGrantEvent22, "hydrateCustomerGrantEvent");
async function writeCustomerGrantSnapshot22(storage, store, nowMs) {
  validateStore2(store);
  const next = { ...store, grants: { ...store.grants } }, archive = [];
  for (const [key2, original] of Object.entries(next.grants)) {
    if (!map2(original)) throw Error("customer_grant_storage_invalid");
    let row = original;
    const closed = row.position_allowed !== true && (row.leg_scope_retired || TERMINAL_PHASES22.has(row.tracking_phase));
    let updated = Date.parse(row.updated_at || "");
    if (closed && !Number.isFinite(updated)) {
      row = { ...row, updated_at: new Date(nowMs).toISOString() };
      next.grants[key2] = row;
      updated = nowMs;
    }
    if (closed && updated <= nowMs - CUSTOMER_GRANT_ARCHIVE_AFTER_MS22 && archive.length < ARCHIVE_BATCH3) {
      if (!store.scope?.tenant_id || !store.scope?.company_id) throw Error("customer_grant_archive_scope_required");
      const text3 = JSON.stringify(row);
      if (bytes3(text3).length > INLINE_BYTES32) throw Error("customer_grant_archive_too_large");
      archive.push([await customerGrantArchiveKey2(key2), { key: key2, scope: store.scope, record: row, sha256: await digest4(text3) }]);
      delete next.grants[key2];
    }
  }
  const text22 = JSON.stringify(next), length = bytes3(text22).length;
  if (length > CUSTOMER_GRANT_SNAPSHOT_MAX_BYTES22) throw Error("customer_grant_snapshot_too_large");
  const previous = await storage.get(CUSTOMER_GRANT_STORAGE_KEY2);
  const oldPages = previous?.format === FORMAT3 ? manifestPages3(previous) : [];
  const entries = [...archive];
  let root = next;
  if (length > INLINE_BYTES32) {
    const generation = crypto.randomUUID(), pages = [];
    for (let at = 0; at < text22.length; at += PAGE_CHARS32) {
      const key2 = `customer_grant_page_v2:${generation}:${pages.length}`;
      entries.push([key2, text22.slice(at, at + PAGE_CHARS32)]);
      pages.push(key2);
    }
    root = { format: FORMAT3, generation, pages, bytes: length, sha256: await digest4(text22) };
  }
  const commit = /* @__PURE__ */ __name(async (txn) => {
    for (const [key2, value] of entries) await txn.put(key2, value);
    await txn.put(CUSTOMER_GRANT_STORAGE_KEY2, root);
    for (const key2 of oldPages) await txn.delete(key2);
  }, "commit");
  if (typeof storage.transaction === "function") await storage.transaction(commit);
  else {
    if (entries.length || oldPages.length) throw Error("customer_grant_transaction_required");
    await storage.put(CUSTOMER_GRANT_STORAGE_KEY2, root);
  }
  return next;
}
__name(writeCustomerGrantSnapshot22, "writeCustomerGrantSnapshot");
var DISPATCH_DEVICE_TTL_MS2 = 18e4;
var matches22 = /* @__PURE__ */ __name((row, scope2) => row?.tenant_id === scope2.tenant_id && row?.company_id === scope2.company_id, "matches");
var valid22 = /* @__PURE__ */ __name((row, nowMs) => row?.protocol === 1 && Number.isFinite(row.seen_at_ms) && row.seen_at_ms <= nowMs && nowMs < row.valid_until_ms, "valid");
function driverDispatchDevices22(store, scope2, driverId, nowMs, deviceKey = "") {
  if (!matches22(store?.scope, scope2)) return [];
  return Object.values(store.devices || {}).filter((row) => matches22(row, scope2) && row.driver_id === driverId && (!deviceKey || row.device_key === deviceKey) && valid22(row, nowMs));
}
__name(driverDispatchDevices22, "driverDispatchDevices");
function dispatchDeviceDeadline22(store, scope2, driverId, nowMs) {
  const rows2 = driverDispatchDevices22(store, scope2, driverId, nowMs);
  return rows2.length ? Math.max(...rows2.map((row) => row.valid_until_ms)) : null;
}
__name(dispatchDeviceDeadline22, "dispatchDeviceDeadline");
function projectDispatchDevices22(store, scope2, nowMs) {
  if (!matches22(store?.scope, scope2)) return [];
  const drivers = /* @__PURE__ */ new Map();
  for (const row of Object.values(store.devices || {})) {
    if (!matches22(row, scope2) || !valid22(row, nowMs)) continue;
    const previous = drivers.get(row.driver_id);
    if (!previous || previous.valid_until_ms < row.valid_until_ms) drivers.set(
      row.driver_id,
      { driver_id: row.driver_id, protocol: 1, seen_at_ms: row.seen_at_ms, valid_until_ms: row.valid_until_ms }
    );
  }
  return [...drivers.values()];
}
__name(projectDispatchDevices22, "projectDispatchDevices");
function updateDispatchDevice22(store, input, nowMs) {
  if (!input?.tenant_id || !input.company_id || typeof input.driver_id !== "string" || !input.driver_id || input.driver_id.length > 96 || !/^[a-f0-9]{64}$/.test(input.device_key || "") || !Number.isFinite(nowMs) || !Number.isFinite(input.session_expires_ms) || input.session_expires_ms <= nowMs) {
    return { ok: false, error: "dispatch_device_invalid", status: 400 };
  }
  if (store?.scope && !matches22(store.scope, input)) return { ok: false, error: "dispatch_device_scope_conflict", status: 409 };
  const old = store?.devices?.[input.device_key];
  if (old && (!matches22(old, input) || old.driver_id !== input.driver_id)) {
    return { ok: false, error: "dispatch_device_owner_conflict", status: 409 };
  }
  const devices = Object.fromEntries(Object.entries(store?.devices || {}).filter(([, row]) => valid22(row, nowMs)));
  delete devices[input.device_key];
  if (input.protocol === 1) devices[input.device_key] = {
    tenant_id: input.tenant_id,
    company_id: input.company_id,
    driver_id: input.driver_id,
    device_key: input.device_key,
    protocol: 1,
    seen_at_ms: nowMs,
    valid_until_ms: Math.min(nowMs + DISPATCH_DEVICE_TTL_MS2, input.session_expires_ms)
  };
  const rows2 = Object.values(devices).filter((row) => row.driver_id === input.driver_id).sort((a, b) => b.seen_at_ms - a.seen_at_ms || a.device_key.localeCompare(b.device_key));
  for (const row of rows2.slice(4)) delete devices[row.device_key];
  return { ok: true, store: { scope: { tenant_id: input.tenant_id, company_id: input.company_id }, devices } };
}
__name(updateDispatchDevice22, "updateDispatchDevice");
function sameCapacityResource22(left, right) {
  return Boolean(left.vehicle_id && left.vehicle_id === right.vehicle_id || left.driver_id && left.driver_id === right.driver_id);
}
__name(sameCapacityResource22, "sameCapacityResource");
function capacityBaselineDecision22(ledger, input) {
  if (!input.tenant_id || !input.company_id || input.inventory_verified !== true || !Array.isArray(input.bookings) || input.bookings.length > 5e3) {
    return { ok: false, error: "capacity_baseline_invalid", status: 400 };
  }
  let next = structuredClone(ledger);
  for (const booking of input.bookings) {
    const checked = capacityClaimDecision22({ claims: {}, owners: {} }, {
      ...booking,
      tenant_id: input.tenant_id,
      company_id: input.company_id,
      action: "reserve",
      replace_owner: false
    }, []);
    if (!checked.ok) return checked;
    if (next.owners[booking.owner_id]) {
      const previous = next.owners[booking.owner_id];
      if (previous.tenant_id !== input.tenant_id || previous.company_id !== input.company_id) {
        return { ok: false, error: "capacity_scope_conflict", status: 409 };
      }
      if (previous.version < booking.version || previous.pending) {
        return { ok: false, error: "capacity_baseline_owner_unresolved", status: 409 };
      }
      if (!previous.released && previous.version === booking.version) {
        const comparable = /* @__PURE__ */ __name((claim) => JSON.stringify({
          claim_id: claim.claim_id,
          driver_id: claim.driver_id || "",
          vehicle_id: claim.vehicle_id || "",
          start_ms: claim.start_ms,
          end_ms: claim.end_ms,
          active: claim.active === true
        }), "comparable");
        const held = Object.values(next.claims).filter((claim) => claim.owner_id === booking.owner_id && !claim.retiring).map(comparable).sort();
        if (JSON.stringify(held) !== JSON.stringify((booking.claims || []).map(comparable).sort())) {
          return { ok: false, error: "capacity_baseline_owner_unresolved", status: 409 };
        }
      }
      continue;
    }
    if (Object.keys(checked.ledger.claims).some((id22) => next.claims[id22])) {
      return { ok: false, error: "capacity_owner_conflict", status: 409 };
    }
    next = { ...next, claims: { ...next.claims, ...checked.ledger.claims }, owners: { ...next.owners, ...checked.ledger.owners } };
  }
  return { ok: true, ledger: next };
}
__name(capacityBaselineDecision22, "capacityBaselineDecision");
var UNSTARTED_CAPACITY_GRACE_MS22 = 15 * 60 * 1e3;
function unstartedCapacityExpired22(claim, nowMs = Date.now(), owner2 = null) {
  return claim?.active !== true && !claim?.retiring && claim?.capacity_pending !== true && owner2?.pending !== true && Number.isFinite(claim?.start_ms) && Number.isFinite(claim?.end_ms) && claim.start_ms < claim.end_ms && nowMs >= claim.end_ms + UNSTARTED_CAPACITY_GRACE_MS22;
}
__name(unstartedCapacityExpired22, "unstartedCapacityExpired");
function overdueCapacityHold22(claim, nowMs = Date.now(), owner2 = null) {
  return claim?.active !== true && Number.isFinite(claim?.start_ms) && Number.isFinite(claim?.end_ms) && claim.start_ms < claim.end_ms && claim.end_ms <= nowMs && !unstartedCapacityExpired22(claim, nowMs, owner2);
}
__name(overdueCapacityHold22, "overdueCapacityHold");
function capacityClaimDecision22(ledger, input, directRides) {
  const { tenant_id, company_id, owner_id, action, claims = [], version = 1 } = input;
  if (!tenant_id || !company_id || typeof owner_id !== "string" || !owner_id.trim() || owner_id.length > 200 || !["reserve", "release", "confirm", "activate"].includes(action) || !Number.isSafeInteger(version) || version < 1 || !Array.isArray(claims)) {
    return { ok: false, error: "capacity_request_invalid", status: 400 };
  }
  const previous = ledger.owners[owner_id];
  if (previous && (previous.tenant_id !== tenant_id || previous.company_id !== company_id)) {
    return { ok: false, error: "capacity_scope_conflict", status: 409 };
  }
  if (previous?.released && action === "release" && version <= previous.version) return { ok: true, ledger };
  if (previous && version < previous.version) return { ok: false, error: "capacity_revision_conflict", status: 409 };
  if (previous?.pending && action === "release") return { ok: false, error: "capacity_update_pending", status: 409, pending_version: previous.version };
  if (previous?.pending && version !== previous.version) return { ok: false, error: "capacity_update_pending", status: 409, pending_version: previous.version };
  if (action === "activate") {
    let claim = ledger.claims[input.claim_id];
    if (!claim && !previous && typeof input.claim_id === "string" && input.claim_id.length <= 240 && input.driver_id && input.vehicle_id) {
      claim = {
        claim_id: input.claim_id,
        driver_id: input.driver_id,
        vehicle_id: input.vehicle_id,
        start_ms: Date.now(),
        end_ms: Date.now() + 1,
        tenant_id,
        company_id,
        owner_id
      };
    }
    if (previous?.pending || previous?.released || previous && previous.version !== version || !claim || claim.owner_id !== owner_id || claim.retiring || claim.driver_id !== input.driver_id || claim.vehicle_id !== input.vehicle_id) {
      return { ok: false, error: "capacity_revision_conflict", status: 409 };
    }
    if (unstartedCapacityExpired22(claim, Date.now(), previous)) {
      return { ok: false, error: "capacity_reservation_expired", status: 409 };
    }
    if (directRides.some((ride) => ride.tenant_id === tenant_id && ride.company_id === company_id && sameCapacityResource22(ride, claim)) || Object.values(ledger.claims).some((other) => other.owner_id !== owner_id && (other.active || overdueCapacityHold22(other, Date.now(), ledger.owners[other.owner_id])) && other.tenant_id === tenant_id && other.company_id === company_id && sameCapacityResource22(other, claim))) {
      return { ok: false, error: "capacity_conflict", status: 409 };
    }
    return { ok: true, ledger: {
      ...ledger,
      claims: { ...ledger.claims, [input.claim_id]: { ...claim, active: true } },
      owners: { ...ledger.owners, [owner_id]: previous || { tenant_id, company_id, version, signature: "activated", pending: false, released: false } }
    } };
  }
  if (action === "confirm") {
    if (!previous || previous.version !== version) return { ok: false, error: "capacity_revision_conflict", status: 409 };
    if (previous.released) return { ok: true, ledger };
    if (input.canonical_claims) {
      const comparable = /* @__PURE__ */ __name((claim) => JSON.stringify({
        claim_id: claim.claim_id,
        driver_id: claim.driver_id || "",
        vehicle_id: claim.vehicle_id || "",
        start_ms: claim.start_ms,
        end_ms: claim.end_ms,
        active: claim.active === true
      }), "comparable");
      const current = Object.values(ledger.claims).filter((claim) => claim.owner_id === owner_id && !claim.retiring).map(comparable).sort();
      if (!Array.isArray(input.canonical_claims) || JSON.stringify(current) !== JSON.stringify(input.canonical_claims.map(comparable).sort())) {
        return { ok: false, error: "capacity_checkpoint_conflict", status: 409 };
      }
    }
    const confirmedClaims = Object.fromEntries(Object.entries(ledger.claims).filter(([, claim]) => claim.owner_id !== owner_id || !claim.retiring));
    return { ok: true, ledger: { claims: confirmedClaims, owners: {
      ...ledger.owners,
      [owner_id]: { ...previous, pending: false, released: !Object.values(confirmedClaims).some((claim) => claim.owner_id === owner_id) }
    } } };
  }
  if (action === "reserve" && (!claims.length && input.replace_owner !== true || claims.length > 8)) {
    return { ok: false, error: "capacity_request_invalid", status: 400 };
  }
  if (claims.some((claim) => !claim || typeof claim !== "object" || Array.isArray(claim))) {
    return { ok: false, error: "capacity_request_invalid", status: 400 };
  }
  const normalized2 = claims.map((claim) => ({
    claim_id: claim.claim_id,
    driver_id: claim.driver_id || "",
    vehicle_id: claim.vehicle_id || "",
    start_ms: claim.start_ms,
    end_ms: claim.end_ms,
    active: claim.active === true,
    tenant_id,
    company_id,
    owner_id
  }));
  if (action === "reserve" && normalized2.some((claim) => !claim.claim_id || claim.claim_id.length > 240 || typeof claim.claim_id !== "string" || !claim.driver_id && !claim.vehicle_id || claim.driver_id && (typeof claim.driver_id !== "string" || claim.driver_id.length > 128) || claim.vehicle_id && (typeof claim.vehicle_id !== "string" || claim.vehicle_id.length > 128) || !Number.isFinite(claim.start_ms) || !Number.isFinite(claim.end_ms) || claim.end_ms <= claim.start_ms)) {
    return { ok: false, error: "capacity_request_invalid", status: 400 };
  }
  if (action === "reserve" && new Set(normalized2.map((claim) => claim.claim_id)).size !== normalized2.length) {
    return { ok: false, error: "capacity_request_invalid", status: 400 };
  }
  const ended = input.ended_claim_ids === void 0 ? [] : input.ended_claim_ids;
  if (!Array.isArray(ended) || ended.length > 8 || new Set(ended).size !== ended.length || ended.some((id22) => typeof id22 !== "string" || !id22.trim() || id22.length > 240)) {
    return { ok: false, error: "capacity_request_invalid", status: 400 };
  }
  const signature = JSON.stringify({
    action,
    replace_owner: input.replace_owner === true,
    claims: normalized2,
    ...ended.length ? { ended_claim_ids: [...ended].sort() } : {}
  });
  if (action === "reserve" && previous?.pending && previous.signature !== signature) {
    return { ok: false, error: "capacity_update_pending", status: 409, pending_version: previous.version };
  }
  if (action === "reserve" && previous?.version === version && !previous.pending && previous.signature === signature) {
    return { ok: true, ledger };
  }
  if (previous?.version === version && previous.signature !== signature && (previous.released || action === "reserve" && input.replace_owner === true)) {
    return { ok: false, error: "capacity_revision_conflict", status: 409 };
  }
  if (action === "reserve") {
    for (const held of Object.values(ledger.claims)) {
      if (held.owner_id !== owner_id || held.retiring || !held.active) continue;
      const next = normalized2.find((claim) => claim.claim_id === held.claim_id);
      if (input.replace_owner !== true && !next) continue;
      const preserved = next?.active === true && next.driver_id === held.driver_id && next.vehicle_id === held.vehicle_id;
      if (!preserved && !(ended.includes(held.claim_id) && !next)) {
        return { ok: false, error: "active_assignment_change_requires_completion", status: 409 };
      }
    }
  }
  const nextClaims = { ...ledger.claims };
  if (action === "release" || input.replace_owner === true) {
    for (const [id22, claim] of Object.entries(nextClaims)) {
      if (claim.owner_id === owner_id && claim.tenant_id === tenant_id && claim.company_id === company_id && (action !== "release" || !Array.isArray(input.claim_ids) || input.claim_ids.includes(id22))) {
        if (action === "reserve" && !claim.retiring && !normalized2.some((next) => JSON.stringify(next) === JSON.stringify(claim))) {
          const retiringId = `${id22}:retiring:${version}`;
          nextClaims[retiringId] = { ...claim, claim_id: retiringId, retiring: true };
        }
        if (!claim.retiring || action === "release") delete nextClaims[id22];
      }
    }
  }
  for (const claim of action === "reserve" ? normalized2 : []) {
    const existing = nextClaims[claim.claim_id];
    if (existing && existing.owner_id !== owner_id) return { ok: false, error: "capacity_owner_conflict", status: 409 };
    if (directRides.some((ride) => ride.tenant_id === tenant_id && ride.company_id === company_id && sameCapacityResource22(ride, claim))) return { ok: false, error: "active_ride_end_unknown", status: 409 };
    if (claim.end_ms > Date.now() && Object.values(nextClaims).some((other) => other.claim_id !== claim.claim_id && !(other.owner_id === owner_id && other.retiring) && other.tenant_id === tenant_id && other.company_id === company_id && sameCapacityResource22(other, claim) && overdueCapacityHold22(other, Date.now(), ledger.owners[other.owner_id]))) {
      return { ok: false, error: "capacity_completion_unconfirmed", status: 409 };
    }
    if (Object.values(nextClaims).some((other) => other.claim_id !== claim.claim_id && !(other.owner_id === owner_id && other.retiring) && other.tenant_id === tenant_id && other.company_id === company_id && sameCapacityResource22(other, claim) && claim.start_ms < other.end_ms && other.start_ms < claim.end_ms)) {
      return { ok: false, error: "capacity_conflict", status: 409 };
    }
    if (existing && previous?.version === version && JSON.stringify(existing) !== JSON.stringify(claim)) {
      return { ok: false, error: "capacity_revision_conflict", status: 409 };
    }
    if (existing && JSON.stringify(existing) !== JSON.stringify(claim)) {
      const retiringId = `${claim.claim_id}:retiring:${version}`;
      nextClaims[retiringId] = { ...existing, claim_id: retiringId, retiring: true };
    }
    nextClaims[claim.claim_id] = claim;
  }
  return { ok: true, ledger: { claims: nextClaims, owners: {
    ...ledger.owners,
    [owner_id]: {
      tenant_id,
      company_id,
      version,
      signature,
      pending: action === "reserve" && input.replace_owner === true,
      released: action === "release" && !Object.values(nextClaims).some((claim) => claim.owner_id === owner_id)
    }
  } } };
}
__name(capacityClaimDecision22, "capacityClaimDecision");
var CAPACITY_STORAGE_KEY22 = "company_capacity_ledger_v1";
var CAPACITY_ARCHIVE_AFTER_MS22 = 24 * 60 * 6e4;
var CAPACITY_SNAPSHOT_MAX_BYTES22 = 8 * 1024 * 1024;
var INLINE_BYTES222 = 80 * 1024;
var PAGE_CHARS222 = 24 * 1024;
var ARCHIVE_BATCH22 = 96;
var FORMAT222 = "company-capacity-pages-v2";
var encoder222 = new TextEncoder();
var tables22 = { owner: "owners", offer: "offers", event: "dispatch_events" };
var validMap22 = /* @__PURE__ */ __name((value) => value && typeof value === "object" && !Array.isArray(value), "validMap");
var bytes222 = /* @__PURE__ */ __name((value) => encoder222.encode(value), "bytes");
async function digest222(text22) {
  return [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes222(text22)))].map((value) => value.toString(16).padStart(2, "0")).join("");
}
__name(digest222, "digest");
async function capacityArchiveKey22(kind, id22) {
  if (!tables22[kind] || typeof id22 !== "string" || !id22 || id22.length > 500) throw Error("capacity_archive_identity_invalid");
  return `capacity_archive_v1:${kind}:${await digest222(id22)}`;
}
__name(capacityArchiveKey22, "capacityArchiveKey");
function validateLedger22(ledger) {
  if (!validMap22(ledger) || !validMap22(ledger.claims) || !validMap22(ledger.owners)) throw Error("capacity_storage_invalid");
  return ledger;
}
__name(validateLedger22, "validateLedger");
function manifestPages222(root) {
  if (!Array.isArray(root.pages) || !root.pages.length || root.pages.length > 1024 || typeof root.generation !== "string" || !/^[a-f\d-]{36}$/.test(root.generation) || !Number.isSafeInteger(root.bytes) || root.bytes < 1 || root.bytes > CAPACITY_SNAPSHOT_MAX_BYTES22 || !/^[a-f\d]{64}$/.test(root.sha256 || "") || root.pages.some((key2, i) => key2 !== `capacity_page_v2:${root.generation}:${i}`)) throw Error("capacity_snapshot_manifest_invalid");
  return root.pages;
}
__name(manifestPages222, "manifestPages");
async function readCapacitySnapshot22(storage) {
  const root = await storage.get(CAPACITY_STORAGE_KEY22);
  if (root == null) return { claims: {}, owners: {} };
  if (root.format !== FORMAT222) return validateLedger22(root);
  manifestPages222(root);
  const parts = [];
  for (let i = 0; i < root.pages.length; i++) {
    const key2 = `capacity_page_v2:${root.generation}:${i}`;
    const part = await storage.get(key2);
    if (typeof part !== "string" || part.length > PAGE_CHARS222) throw Error("capacity_snapshot_page_missing");
    parts.push(part);
  }
  const text22 = parts.join("");
  if (bytes222(text22).length !== root.bytes || await digest222(text22) !== root.sha256) throw Error("capacity_snapshot_checksum_invalid");
  return validateLedger22(JSON.parse(text22));
}
__name(readCapacitySnapshot22, "readCapacitySnapshot");
async function hydrateCapacityRecords22(storage, ledger, identities, scope2) {
  let next = ledger;
  const pending = Object.entries(identities).flatMap(([kind, ids]) => ids.map((id22) => [kind, id22]));
  const seen = /* @__PURE__ */ new Set();
  for (let i = 0; i < pending.length; i++) {
    const [kind, id22] = pending[i], table3 = tables22[kind];
    if (!table3 || typeof id22 !== "string" || !id22 || id22.length > 500 || seen.has(`${kind}:${id22}`)) continue;
    seen.add(`${kind}:${id22}`);
    let row = next[table3]?.[id22];
    if (!Object.hasOwn(next[table3] || {}, id22)) {
      const archived = await storage.get(await capacityArchiveKey22(kind, id22));
      if (archived == null) continue;
      row = archived.record;
      if (archived.kind !== kind || archived.id !== id22 || !validMap22(row) || row.tenant_id !== scope2.tenant_id || row.company_id !== scope2.company_id || kind === "owner" && (!Number.isSafeInteger(row.version) || row.version < 1 || row.pending || !row.released) || kind === "offer" && row.offer_id !== id22 || kind === "event" && row.event_id !== id22) {
        throw Error("capacity_archive_record_invalid");
      }
      next = { ...next, [table3]: { ...next[table3], [id22]: row } };
    }
    if (row.owner_id) pending.push(["owner", row.owner_id]);
    if (kind === "event" && row.offer_id && row.type !== "dispatch_search") pending.push(["offer", row.offer_id]);
  }
  return next;
}
__name(hydrateCapacityRecords22, "hydrateCapacityRecords");
function compact2(ledger, previous, nowMs) {
  const owners = { ...ledger.owners }, events = { ...ledger.dispatch_events }, offers = { ...ledger.offers };
  for (const [id22, owner2] of Object.entries(owners)) {
    if (!Number.isFinite(owner2.storage_updated_at_ms) || JSON.stringify(owner2) !== JSON.stringify(previous.owners[id22])) {
      owners[id22] = { ...owner2, storage_updated_at_ms: nowMs };
    }
  }
  for (const [id22, event] of Object.entries(events)) {
    if (event.state === "delivered" && (!Number.isFinite(event.storage_delivered_at_ms) || previous.dispatch_events?.[id22]?.state !== "delivered")) events[id22] = { ...event, storage_delivered_at_ms: nowMs };
  }
  const hot = new Set(Object.values(ledger.claims).map((claim) => claim.owner_id));
  for (const offer of Object.values(offers)) {
    if (["offered", "received", "committing"].includes(offer.state)) hot.add(offer.owner_id);
  }
  for (const event of Object.values(events)) if (event.state !== "delivered") hot.add(event.owner_id);
  const cutoff = nowMs - CAPACITY_ARCHIVE_AFTER_MS22;
  const cold = new Set(Object.entries(owners).filter(([id22, owner2]) => !hot.has(id22) && owner2.released === true && owner2.pending === false && owner2.storage_updated_at_ms <= cutoff).map(([id22]) => id22));
  const archive = [];
  const retire = /* @__PURE__ */ __name((kind, table3, id22) => {
    archive.push({ kind, id: id22, record: table3[id22] });
    delete table3[id22];
  }, "retire");
  for (const [id22, offer] of Object.entries(offers)) {
    if (archive.length >= ARCHIVE_BATCH22) break;
    if (cold.has(offer.owner_id)) retire("offer", offers, id22);
  }
  for (const [id22, event] of Object.entries(events)) {
    if (archive.length >= ARCHIVE_BATCH22) break;
    if (event.state === "delivered" && (cold.has(event.owner_id) || event.type === "dispatch_search" && !hot.has(event.owner_id) && event.storage_delivered_at_ms <= cutoff)) retire("event", events, id22);
  }
  const referenced = new Set([...Object.values(offers), ...Object.values(events)].map((row) => row.owner_id));
  for (const id22 of cold) {
    if (archive.length >= ARCHIVE_BATCH22) break;
    if (!referenced.has(id22)) retire("owner", owners, id22);
  }
  return { ledger: {
    ...ledger,
    owners,
    ...ledger.offers ? { offers } : {},
    ...ledger.dispatch_events ? { dispatch_events: events } : {}
  }, archive };
}
__name(compact2, "compact");
async function writeCapacitySnapshot22(storage, ledger, previous, nowMs) {
  const planned = compact2(validateLedger22(ledger), previous, nowMs);
  const text22 = JSON.stringify(planned.ledger), length = bytes222(text22).length;
  if (length > CAPACITY_SNAPSHOT_MAX_BYTES22) throw Error("capacity_snapshot_too_large");
  const existing = await storage.get(CAPACITY_STORAGE_KEY22);
  const oldPages = existing?.format === FORMAT222 ? manifestPages222(existing) : [];
  const entries = [];
  for (const row of planned.archive) {
    if (bytes222(JSON.stringify(row)).length > INLINE_BYTES222) throw Error("capacity_archive_record_too_large");
    entries.push([await capacityArchiveKey22(row.kind, row.id), row]);
  }
  let root = planned.ledger;
  if (length > INLINE_BYTES222) {
    const generation = crypto.randomUUID(), pages = [];
    for (let at = 0; at < text22.length; at += PAGE_CHARS222) {
      const key2 = `capacity_page_v2:${generation}:${pages.length}`;
      entries.push([key2, text22.slice(at, at + PAGE_CHARS222)]);
      pages.push(key2);
    }
    root = { format: FORMAT222, generation, pages, bytes: length, sha256: await digest222(text22) };
  }
  const commit = /* @__PURE__ */ __name(async (txn) => {
    for (const [key2, value] of entries) await txn.put(key2, value);
    await txn.put(CAPACITY_STORAGE_KEY22, root);
    for (const key2 of oldPages) await txn.delete(key2);
  }, "commit");
  if (typeof storage.transaction === "function") await storage.transaction(commit);
  else {
    if (entries.length || oldPages.length) throw Error("capacity_storage_transaction_required");
    await storage.put(CAPACITY_STORAGE_KEY22, root);
  }
  return planned.ledger;
}
__name(writeCapacitySnapshot22, "writeCapacitySnapshot");
var LOCATION_RETIRED_OWNER_LIMIT22 = 512;
var label22 = /* @__PURE__ */ __name((value) => typeof value === "string" && /^[A-Za-z0-9_-]{1,128}$/.test(value), "label");
function driverLocationOwner(session, body = {}, { requireActivation = false } = {}) {
  const activation = body.activation_id;
  const suppliedDevice = body.native_device_id;
  if (activation != null && !label22(activation) || suppliedDevice != null && !label22(suppliedDevice) || requireActivation && !label22(activation)) return { ok: false, status: 400, error: "location_owner_invalid" };
  const boundDevice = session?.native_device_id || null;
  if (boundDevice && suppliedDevice !== boundDevice) {
    return { ok: false, status: 403, error: "location_device_mismatch" };
  }
  if (!/^[a-f0-9]{64}$/.test(session?.token_hash || "") || !Number.isFinite(session?.expires_ms)) {
    return requireActivation ? { ok: false, status: 401, error: "unauthorized" } : { ok: true, owner: null };
  }
  return { ok: true, owner: {
    session_hash: session.token_hash,
    activation_id: activation || null,
    native_device_id: boundDevice || suppliedDevice || null,
    session_expires_ms: session.expires_ms
  } };
}
__name(driverLocationOwner, "driverLocationOwner");
function boundLocationOwner22(owner2, nowMs) {
  return Boolean(owner2 && /^[a-f0-9]{64}$/.test(owner2.session_hash || "") && label22(owner2.activation_id) && (owner2.native_device_id == null || label22(owner2.native_device_id)) && Number.isFinite(owner2.session_expires_ms) && owner2.session_expires_ms > nowMs);
}
__name(boundLocationOwner22, "boundLocationOwner");
function sameLocationOwner22(left, right) {
  return Boolean(left && right && left.session_hash === right.session_hash && left.activation_id === right.activation_id && left.native_device_id === right.native_device_id);
}
__name(sameLocationOwner22, "sameLocationOwner");
function retainedLocationOwners22(row, nowMs) {
  return (Array.isArray(row?.retired_publications) ? row.retired_publications : []).filter((owner2) => boundLocationOwner22(owner2, nowMs)).slice(0, LOCATION_RETIRED_OWNER_LIMIT22);
}
__name(retainedLocationOwners22, "retainedLocationOwners");
function locationOwnerRetired22(row, owner2, nowMs) {
  return Boolean(boundLocationOwner22(owner2, nowMs) && (row?.location_withdrawn === true && sameLocationOwner22(row.publication_owner, owner2) || retainedLocationOwners22(row, nowMs).some((retired) => sameLocationOwner22(retired, owner2))));
}
__name(locationOwnerRetired22, "locationOwnerRetired");
function nextRetiredLocationOwners22(row, owner2, nowMs) {
  const retained = retainedLocationOwners22(row, nowMs);
  const previous = row?.publication_owner;
  if (boundLocationOwner22(previous, nowMs) && !sameLocationOwner22(previous, owner2) && !retained.some((retired) => sameLocationOwner22(retired, previous))) {
    if (retained.length >= LOCATION_RETIRED_OWNER_LIMIT22) return null;
    retained.push(previous);
  }
  return retained;
}
__name(nextRetiredLocationOwners22, "nextRetiredLocationOwners");
var fail32 = /* @__PURE__ */ __name(() => ({ ok: false, error: "dispatch_amendment_conflict", status: 409 }), "fail");
var comparableDispatchClaim2 = /* @__PURE__ */ __name((claim) => JSON.stringify({
  claim_id: claim.claim_id,
  driver_id: claim.driver_id || "",
  vehicle_id: claim.vehicle_id || "",
  start_ms: claim.start_ms,
  end_ms: claim.end_ms,
  active: claim.active === true
}), "comparableDispatchClaim");
var equalClaims2 = /* @__PURE__ */ __name((left, right) => JSON.stringify(left.map(comparableDispatchClaim2).sort()) === JSON.stringify(right.map(comparableDispatchClaim2).sort()), "equalClaims");
function amendmentBaseMatches22(ledger, offer) {
  const owner2 = ledger.owners[offer.owner_id];
  const retained = offer.retained_claims;
  const held = Object.values(ledger.claims).filter((claim) => claim.owner_id === offer.owner_id && (!offer.offer_id || claim.offer_id !== offer.offer_id));
  return offer.amendment === true && Number.isSafeInteger(offer.base_version) && offer.base_version > 0 && offer.version >= offer.base_version && owner2?.version === offer.base_version && !owner2.pending && owner2.tenant_id === offer.tenant_id && owner2.company_id === offer.company_id && Array.isArray(retained) && retained.length <= 2 && retained.every((claim) => claim && typeof claim === "object" && typeof claim.claim_id === "string" && Number.isFinite(claim.start_ms) && Number.isFinite(claim.end_ms)) && (retained.length > 0 || owner2.released) && held.every((claim) => !claim.retiring && claim.tenant_id === offer.tenant_id && claim.company_id === offer.company_id) && equalClaims2(held, retained);
}
__name(amendmentBaseMatches22, "amendmentBaseMatches");
function holdAmendmentClaims22(ledger, input, directRides) {
  if (!amendmentBaseMatches22(ledger, input) || input.version <= input.base_version || !Array.isArray(input.claims) || input.claims.length !== 1 || !["OUTBOUND", "RETURN"].some((type) => input.claims[0].claim_id === `${input.owner_id}:${type}`) || input.retained_claims.some((claim) => input.claims.some((next) => next.claim_id === claim.claim_id))) return fail32();
  const checked = capacityClaimDecision22(ledger, { ...input, action: "reserve", replace_owner: false }, directRides);
  return checked.ok ? { ok: true, ledger: {
    ...checked.ledger,
    owners: { ...checked.ledger.owners, [input.owner_id]: ledger.owners[input.owner_id] }
  } } : checked;
}
__name(holdAmendmentClaims22, "holdAmendmentClaims");
function promoteAmendmentClaims22(ledger, offer, directRides) {
  if (!amendmentBaseMatches22(ledger, offer) || !offer.claims.every((claim) => {
    const held = ledger.claims[claim.claim_id];
    return held?.owner_id === offer.owner_id && held.offer_id === offer.offer_id && !held.retiring && comparableDispatchClaim2(held) === comparableDispatchClaim2(claim);
  })) return fail32();
  const base = { ...ledger, claims: Object.fromEntries(Object.entries(ledger.claims).filter(([, claim]) => claim.owner_id !== offer.owner_id || claim.offer_id !== offer.offer_id)) };
  return capacityClaimDecision22(base, {
    ...offer,
    action: "reserve",
    replace_owner: true,
    claims: [...offer.retained_claims, ...offer.claims]
  }, directRides);
}
__name(promoteAmendmentClaims22, "promoteAmendmentClaims");
function rollbackAmendmentPromotion22(ledger, offer, proof, directRides) {
  const owner2 = ledger.owners[offer.owner_id];
  const held = Object.values(ledger.claims).filter((claim) => claim.owner_id === offer.owner_id && !claim.retiring);
  if (owner2?.version !== offer.version || !owner2.pending || !Number.isSafeInteger(proof.capacity_version) || proof.capacity_version <= offer.version || !Array.isArray(proof.canonical_claims) || !equalClaims2(proof.canonical_claims, offer.retained_claims) || !equalClaims2(held, [...offer.retained_claims, ...offer.claims])) return fail32();
  const settled = { ...ledger, owners: { ...ledger.owners, [offer.owner_id]: { ...owner2, pending: false } } };
  const reserved = capacityClaimDecision22(settled, {
    ...offer,
    action: "reserve",
    version: proof.capacity_version,
    replace_owner: true,
    claims: proof.canonical_claims
  }, directRides);
  if (!reserved.ok) return reserved;
  return capacityClaimDecision22(reserved.ledger, {
    ...offer,
    action: "confirm",
    version: proof.capacity_version,
    canonical_claims: proof.canonical_claims
  }, directRides);
}
__name(rollbackAmendmentPromotion22, "rollbackAmendmentPromotion");
var DISPATCH_ACK_TIMEOUT_MS2 = 15e4;
var DISPATCH_POSITION_TTL_MS2 = 18e4;
var PROVISIONAL2 = /* @__PURE__ */ new Set(["offered", "received"]);
var fail222 = /* @__PURE__ */ __name((error, status = 409) => ({ ok: false, error, status }), "fail");
var scopeMatches2 = /* @__PURE__ */ __name((row, input) => row?.tenant_id === input.tenant_id && row?.company_id === input.company_id, "scopeMatches");
function dispatchOfferResources22(offer) {
  const pairs = /* @__PURE__ */ new Map();
  for (const claim of offer.claims || []) pairs.set(
    `${claim.driver_id}
${claim.vehicle_id}`,
    { driver_id: claim.driver_id, vehicle_id: claim.vehicle_id }
  );
  return [...pairs.values()];
}
__name(dispatchOfferResources22, "dispatchOfferResources");
var touches2 = /* @__PURE__ */ __name((offer, row) => dispatchOfferResources22(offer).some((resource) => sameCapacityResource22(resource, row)), "touches");
var prerequisites2 = /* @__PURE__ */ __name((offer) => offer.prerequisites || (offer.prerequisite_claim_id ? [{
  claim_id: offer.prerequisite_claim_id,
  version: offer.prerequisite_version,
  driver_id: offer.driver_id,
  vehicle_id: offer.vehicle_id
}] : []), "prerequisites");
function resourceFresh2(offer, drivers, dispatchDevices, nowMs) {
  for (const resource of dispatchOfferResources22(offer)) {
    const position = drivers[resource.driver_id];
    if (!scopeMatches2(position, offer) || position.vehicle_id !== resource.vehicle_id || !freshDispatchPosition2(position, nowMs)) return { reason: "location_stale", driver_id: resource.driver_id };
    if (!driverDispatchDevices22(dispatchDevices, offer, resource.driver_id, nowMs).length) return { reason: "device_unavailable", driver_id: resource.driver_id };
  }
  return null;
}
__name(resourceFresh2, "resourceFresh");
function dispatchSearchDecision22(ledger, input, nowMs) {
  if (!input.tenant_id || !input.company_id || typeof input.owner_id !== "string" || !input.owner_id.trim() || input.owner_id.length > 160 || !Number.isSafeInteger(input.version) || input.version < 1 || !Number.isFinite(nowMs)) return fail222("dispatch_search_invalid", 400);
  const eventId = `search:${input.owner_id}:${input.version}`;
  const existing = ledger.dispatch_events?.[eventId];
  if (existing) return scopeMatches2(existing, input) ? { ok: true, ledger, event: existing } : fail222("dispatch_event_conflict");
  if (input.amendment === true ? !amendmentBaseMatches22(ledger, input) : ledger.owners[input.owner_id] && !ledger.owners[input.owner_id].released || Object.values(ledger.claims).some((claim) => claim.owner_id === input.owner_id)) return fail222("dispatch_search_hard_assignment");
  const event = {
    ...input,
    event_id: eventId,
    offer_id: eventId,
    type: "dispatch_search",
    state: "pending",
    reason: "no_candidate",
    created_at_ms: nowMs
  };
  return { ok: true, event, ledger: { ...ledger, dispatch_events: { ...ledger.dispatch_events, [eventId]: event } } };
}
__name(dispatchSearchDecision22, "dispatchSearchDecision");
function freshDispatchPosition2(row, nowMs) {
  if (!row) return false;
  const captured = Date.parse(row.position_captured_at || row.captured_at || "");
  const seen = Date.parse(row.last_seen_at || "");
  const lat = row.latitude, lng = row.longitude;
  return Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180 && !(lat === 0 && lng === 0) && row.reliable_for_eta !== false && row.stale !== true && [captured, seen].every((at) => Number.isFinite(at) && nowMs - at <= DISPATCH_POSITION_TTL_MS2 && at - nowMs <= 12e4);
}
__name(freshDispatchPosition2, "freshDispatchPosition");
function cancellation2(ledger, offer, reason, nowMs, failedDriverId = offer.driver_id) {
  const claims = Object.fromEntries(Object.entries(ledger.claims).filter(([, claim]) => !(claim.owner_id === offer.owner_id && claim.offer_id === offer.offer_id)));
  const eventId = `${offer.offer_id}:${reason}`;
  return {
    ...ledger,
    claims,
    owners: {
      ...ledger.owners,
      [offer.owner_id]: offer.amendment ? ledger.owners[offer.owner_id] : { ...ledger.owners[offer.owner_id], released: true, pending: false }
    },
    offers: { ...ledger.offers, [offer.offer_id]: {
      ...offer,
      state: reason === "ack_timeout" ? "expired" : "cancelled",
      reason,
      ended_at_ms: nowMs
    } },
    dispatch_events: { ...ledger.dispatch_events, [eventId]: {
      event_id: eventId,
      type: "redispatch",
      ...offer,
      state: "pending",
      reason,
      created_at_ms: nowMs,
      failed_driver_id: failedDriverId
    } }
  };
}
__name(cancellation2, "cancellation");
function expireDispatchOffers2(ledger, nowMs) {
  let next = ledger;
  for (const offer of Object.values(ledger.offers || {})) {
    if (PROVISIONAL2.has(offer.state) && offer.ack_deadline_ms <= nowMs) {
      const missing = dispatchOfferResources22(offer).find((resource) => !offer.receipts?.[resource.driver_id]?.ready);
      next = cancellation2(next, offer, "ack_timeout", nowMs, missing?.driver_id || offer.driver_id);
    }
  }
  return next;
}
__name(expireDispatchOffers2, "expireDispatchOffers");
function preemptOwnerAmendments22(ledger, input, nowMs) {
  let next = ledger;
  for (const offer of Object.values(ledger.offers || {})) {
    if (offer.amendment && offer.owner_id === input.owner_id && scopeMatches2(offer, input) && PROVISIONAL2.has(offer.state) && ["reserve", "activate", "release"].includes(input.action)) {
      next = cancellation2(next, offer, "canonical_changed", nowMs);
    }
  }
  return next;
}
__name(preemptOwnerAmendments22, "preemptOwnerAmendments");
function preemptDispatchOffers22(ledger, street, nowMs) {
  let next = ledger;
  for (const offer of Object.values(ledger.offers || {})) {
    if (!scopeMatches2(offer, street) || !PROVISIONAL2.has(offer.state)) continue;
    if (touches2(offer, street)) next = cancellation2(next, offer, "street_hail", nowMs, street.driver_id);
  }
  return next;
}
__name(preemptDispatchOffers22, "preemptDispatchOffers");
function revalidateDispatchOffers22(ledger, drivers, nowMs, dispatchDevices) {
  let next = expireDispatchOffers2(ledger, nowMs);
  for (const offer of Object.values(next.offers || {})) {
    if (!PROVISIONAL2.has(offer.state)) continue;
    const stale = resourceFresh2(offer, drivers, dispatchDevices, nowMs);
    let reason = offer.amendment && !amendmentBaseMatches22(next, offer) ? "canonical_changed" : stale?.reason;
    let failedDriverId = stale?.driver_id;
    for (const required of prerequisites2(offer)) {
      const prior = next.claims[required.claim_id];
      if (!reason && prior && next.owners[prior.owner_id]?.version !== required.version) {
        reason = "destination_changed";
        failedDriverId = required.driver_id;
      }
      const start = Math.min(...offer.claims.filter((claim) => sameCapacityResource22(claim, required)).map((claim) => claim.start_ms));
      if (!reason && prior && prior.end_ms > start) {
        reason = "forecast_late";
        failedDriverId = required.driver_id;
      }
    }
    if (reason) next = cancellation2(next, offer, reason, nowMs, failedDriverId || offer.driver_id);
  }
  return next;
}
__name(revalidateDispatchOffers22, "revalidateDispatchOffers");
function preemptPrerequisiteOffers22(ledger, input, nowMs) {
  if (!["reserve", "activate"].includes(input.action)) return ledger;
  let next = ledger;
  for (const offer of Object.values(ledger.offers || {})) {
    if (PROVISIONAL2.has(offer.state) && scopeMatches2(offer, input) && prerequisites2(offer).some((required) => ledger.claims[required.claim_id]?.owner_id === input.owner_id && required.version !== input.version)) {
      const changed = prerequisites2(offer).find((required) => ledger.claims[required.claim_id]?.owner_id === input.owner_id);
      next = cancellation2(next, offer, "destination_changed", nowMs, changed?.driver_id || offer.driver_id);
    }
  }
  return next;
}
__name(preemptPrerequisiteOffers22, "preemptPrerequisiteOffers");
function dispatchOfferDecision22(ledger, input, { nowMs, directRides = [], driverPosition, drivers = {}, dispatchDevices } = {}) {
  if (!Number.isFinite(nowMs) || !input.tenant_id || !input.company_id || typeof input.offer_id !== "string" || !input.offer_id.trim() || input.offer_id.length > 200 || !Number.isInteger(input.version) || input.version < 1) return fail222("dispatch_offer_invalid", 400);
  if (input.prerequisites != null && (!Array.isArray(input.prerequisites) || input.prerequisites.length > 2 || input.prerequisites.some((row) => !row || typeof row.claim_id !== "string" || !row.claim_id || !Number.isSafeInteger(row.version) || row.version < 1 || !row.driver_id || !row.vehicle_id) || new Set(input.prerequisites.map((row) => row.claim_id)).size !== input.prerequisites.length)) {
    return fail222("dispatch_prerequisite_invalid", 400);
  }
  const current = ledger.offers?.[input.offer_id];
  if (current && (!scopeMatches2(current, input) || current.version !== input.version || current.owner_id !== input.owner_id || (input.action === "ack" ? !dispatchOfferResources22(current).some((resource) => resource.driver_id === input.driver_id && resource.vehicle_id === input.vehicle_id) : current.driver_id !== input.driver_id || current.vehicle_id !== input.vehicle_id))) return fail222("dispatch_offer_conflict");
  const next = expireDispatchOffers2(ledger, nowMs);
  const offer = next.offers?.[input.offer_id];
  if (input.action === "refresh" && offer?.amendment) {
    const proof = input.canonical_resolution;
    if (offer.state === "aborted") return { ok: true, ledger: next, offer };
    if (proof?.offer_id !== offer.offer_id || proof.version !== offer.version || proof.reason !== "canonical_changed" || proof.unassigned !== true || !Number.isSafeInteger(proof.record_canonical_version) || proof.record_canonical_version <= offer.record_canonical_version || !["offered", "received", "committing", "cancelled", "expired"].includes(offer.state)) return fail222("dispatch_refresh_unconfirmed");
    const rolled = offer.state === "committing" ? rollbackAmendmentPromotion22(next, offer, proof, directRides) : { ok: true, ledger: next };
    if (!rolled.ok) return rolled;
    const cancelled = cancellation2({ ...next, ...rolled.ledger }, offer, "canonical_changed", nowMs);
    const aborted = { ...offer, state: "aborted", reason: "canonical_changed", ended_at_ms: nowMs };
    return { ok: true, offer: aborted, ledger: {
      ...cancelled,
      offers: { ...cancelled.offers, [offer.offer_id]: aborted }
    } };
  }
  if (input.action === "refresh") {
    const proof = input.canonical_resolution;
    if (offer?.state === "aborted") return { ok: true, ledger: next, offer };
    if (proof?.offer_id !== input.offer_id || proof?.version !== input.version || proof?.reason !== "canonical_changed" || proof.unassigned !== true || !Number.isSafeInteger(proof.record_canonical_version) || !Number.isSafeInteger(input.record_canonical_version) || input.record_canonical_version < 1 || proof.record_canonical_version <= input.record_canonical_version || offer && (offer.record_canonical_version !== input.record_canonical_version || !["offered", "received", "committing", "cancelled", "expired"].includes(offer.state)) || Object.values(next.claims).some((claim) => claim.owner_id === input.owner_id && (!offer || claim.offer_id !== offer.offer_id))) return fail222("dispatch_refresh_unconfirmed");
    if (!offer) return { ok: true, ledger: next };
    const owner2 = next.owners[offer.owner_id];
    if (owner2?.version !== offer.version) return fail222("dispatch_refresh_unconfirmed");
    const claims = Object.fromEntries(Object.entries(next.claims).filter(([, claim]) => !(claim.owner_id === offer.owner_id && claim.offer_id === offer.offer_id)));
    const aborted = { ...offer, state: "aborted", reason: "canonical_changed", ended_at_ms: nowMs };
    return { ok: true, offer: aborted, ledger: {
      ...next,
      claims,
      owners: { ...next.owners, [offer.owner_id]: { ...owner2, pending: false, released: true } },
      offers: { ...next.offers, [offer.offer_id]: aborted }
    } };
  }
  if (input.action === "defer") {
    if (offer) return offer.state === "cancelled" && offer.reason === "candidate_unavailable" ? { ok: true, ledger: next, offer } : fail222("dispatch_offer_conflict");
    if (input.amendment === true ? !amendmentBaseMatches22(next, input) : next.owners[input.owner_id] && (!next.owners[input.owner_id].released || next.owners[input.owner_id].version >= input.version) || Object.values(next.claims).some((claim) => claim.owner_id === input.owner_id)) return fail222("dispatch_offer_hard_assignment");
    const checked = capacityClaimDecision22({ claims: {}, owners: {} }, { ...input, action: "reserve" }, []);
    if (!checked.ok || !input.driver_id || !input.vehicle_id || ![1, 2].includes(input.claims.length)) return fail222("dispatch_offer_invalid", 400);
    const deferred = {
      tenant_id: input.tenant_id,
      company_id: input.company_id,
      offer_id: input.offer_id,
      owner_id: input.owner_id,
      version: input.version,
      driver_id: input.driver_id,
      vehicle_id: input.vehicle_id,
      claims: input.claims,
      ...input.amendment ? { amendment: true, base_version: input.base_version, retained_claims: input.retained_claims } : {},
      created_at_ms: nowMs,
      state: "offered"
    };
    const released = cancellation2({ ...next, owners: {
      ...next.owners,
      [input.owner_id]: input.amendment ? next.owners[input.owner_id] : checked.ledger.owners[input.owner_id]
    } }, deferred, "candidate_unavailable", nowMs);
    return { ok: true, ledger: released, offer: released.offers[input.offer_id] };
  }
  if (input.action === "offer") {
    const asapDeadline = input.asap_search_expires_ms;
    if (asapDeadline != null && (!Number.isSafeInteger(asapDeadline) || !Number.isSafeInteger(input.asap_requested_ms) || input.asap_requested_ms > nowMs || asapDeadline !== input.asap_requested_ms + 6e5)) return fail222("dispatch_asap_deadline_invalid", 400);
    if (asapDeadline != null && asapDeadline <= nowMs && (!offer || PROVISIONAL2.has(offer.state))) {
      return fail222("asap_search_expired");
    }
    const timeout = input.ack_timeout_ms ?? DISPATCH_ACK_TIMEOUT_MS2;
    if (!Number.isInteger(timeout) || timeout < 3e4 || timeout > 18e4 || timeout < DISPATCH_ACK_TIMEOUT_MS2 && input.delivery_mode !== "live") return fail222("dispatch_delivery_invalid", 400);
    if (offer) {
      if (!PROVISIONAL2.has(offer.state) && !["committing", "committed"].includes(offer.state)) return fail222("dispatch_offer_closed");
      if (JSON.stringify(prerequisites2(offer)) !== JSON.stringify(prerequisites2(input)) || offer.asap_search_expires_ms !== input.asap_search_expires_ms || offer.asap_requested_ms !== input.asap_requested_ms || JSON.stringify(offer.claims) !== JSON.stringify(input.claims) || offer.prerequisite_claim_id !== (input.prerequisite_claim_id || null) || offer.prerequisite_version !== (input.prerequisite_version ?? null) || offer.ack_timeout_ms !== timeout || Boolean(offer.amendment) !== Boolean(input.amendment) || offer.amendment && (offer.base_version !== input.base_version || JSON.stringify(offer.retained_claims) !== JSON.stringify(input.retained_claims))) return fail222("dispatch_offer_conflict");
      return { ok: true, ledger: next, offer };
    }
    if (Object.values(next.offers || {}).some((row) => row.owner_id === input.owner_id && ["offered", "received", "committing"].includes(row.state))) return fail222("dispatch_offer_pending");
    if (!input.amendment && Object.values(next.claims).some((claim) => claim.owner_id === input.owner_id)) return fail222("dispatch_offer_hard_assignment");
    if (typeof input.driver_id !== "string" || !input.driver_id || typeof input.vehicle_id !== "string" || !input.vehicle_id || !Array.isArray(input.claims) || ![1, 2].includes(input.claims.length) || input.claims.some((claim) => !claim.driver_id || !claim.vehicle_id || claim.active) || input.claims[0].driver_id !== input.driver_id || input.claims[0].vehicle_id !== input.vehicle_id || new Set(input.claims.map((claim) => claim.claim_id)).size !== input.claims.length) {
      return fail222("dispatch_offer_invalid", 400);
    }
    const positions = { ...drivers, ...driverPosition ? { [input.driver_id]: driverPosition } : {} };
    const freshness2 = resourceFresh2(input, positions, dispatchDevices, nowMs);
    if (freshness2) return fail222(freshness2.reason === "device_unavailable" ? "dispatch_device_unavailable" : "dispatch_offer_location_stale");
    const held = input.amendment ? holdAmendmentClaims22(next, input, directRides) : capacityClaimDecision22(next, { ...input, action: "reserve", replace_owner: false }, directRides);
    if (!held.ok) return held;
    const created = {
      tenant_id: input.tenant_id,
      company_id: input.company_id,
      offer_id: input.offer_id,
      owner_id: input.owner_id,
      version: input.version,
      driver_id: input.driver_id,
      vehicle_id: input.vehicle_id,
      claims: input.claims,
      prerequisite_claim_id: input.prerequisite_claim_id || null,
      prerequisite_version: input.prerequisite_version ?? null,
      ...input.record_canonical_version ? {
        record_canonical_version: input.record_canonical_version,
        record_revision: input.record_revision,
        record_dispatch_basis: input.record_dispatch_basis
      } : {},
      ...input.prerequisites ? { prerequisites: input.prerequisites } : {},
      ...asapDeadline != null ? { asap_requested_ms: input.asap_requested_ms, asap_search_expires_ms: asapDeadline } : {},
      ...input.amendment ? { amendment: true, base_version: input.base_version, retained_claims: input.retained_claims } : {},
      state: "offered",
      created_at_ms: nowMs,
      ack_timeout_ms: timeout,
      ack_deadline_ms: Math.min(nowMs + timeout, asapDeadline ?? Infinity)
    };
    for (const required2 of prerequisites2(created)) {
      const prior2 = next.claims[required2.claim_id];
      if (!prior2?.active || prior2.driver_id !== required2.driver_id || prior2.vehicle_id !== required2.vehicle_id || !scopeMatches2(prior2, input) || next.owners[prior2.owner_id]?.version !== required2.version || !dispatchOfferResources22(created).some((resource) => sameCapacityResource22(resource, required2))) {
        return fail222("dispatch_prerequisite_conflict");
      }
    }
    const claims = { ...held.ledger.claims };
    for (const claim of created.claims) claims[claim.claim_id] = { ...claims[claim.claim_id], offer_id: created.offer_id };
    return { ok: true, offer: created, ledger: {
      ...next,
      ...held.ledger,
      claims,
      offers: { ...next.offers, [created.offer_id]: created }
    } };
  }
  if (!offer) return fail222("dispatch_offer_missing", 404);
  if (input.action === "supersede") {
    const owner2 = next.owners[offer.owner_id];
    if (offer.state === "superseded") return { ok: true, ledger: next, offer };
    if (!["committed", "cancelled"].includes(offer.state) || !owner2 || owner2.version <= offer.version || owner2.pending || input.canonical_version !== owner2.version || Object.values(next.claims).some((claim) => claim.owner_id === offer.owner_id && claim.offer_id === offer.offer_id)) {
      return fail222("dispatch_superseded_unconfirmed");
    }
    const superseded = { ...offer, state: "superseded", reason: "canonical_reassignment", ended_at_ms: nowMs };
    return { ok: true, offer: superseded, ledger: { ...next, offers: { ...next.offers, [offer.offer_id]: superseded } } };
  }
  if (input.action === "abort") {
    const proof = input.canonical_resolution;
    if (offer.state === "aborted") return { ok: true, ledger: next, offer };
    if (!["committing", "committed"].includes(offer.state) && !(offer.state === "cancelled" && offer.reason === "canonical_release") || Object.values(next.claims).some((claim) => claim.owner_id === offer.owner_id && claim.offer_id !== offer.offer_id) || proof?.offer_id !== offer.offer_id || proof?.version !== offer.version || !Number.isInteger(proof.record_revision) || proof.record_revision < offer.version - 1 || proof.reason !== "terminal" || !["COMPLETED", "CANCELLED", "CANCELED", "NO_SHOW", "REJECTED", "EXPIRED"].includes(String(proof.status || "").toUpperCase())) return fail222("dispatch_abort_unconfirmed");
    const claims = Object.fromEntries(Object.entries(next.claims).filter(([, claim]) => !(claim.owner_id === offer.owner_id && claim.offer_id === offer.offer_id)));
    const aborted = { ...offer, state: "aborted", reason: "canonical_terminal", ended_at_ms: nowMs };
    return { ok: true, offer: aborted, ledger: {
      ...next,
      claims,
      owners: { ...next.owners, [offer.owner_id]: { ...next.owners[offer.owner_id], pending: false, released: true } },
      offers: { ...next.offers, [offer.offer_id]: aborted }
    } };
  }
  if (input.action === "revoke") {
    if (!PROVISIONAL2.has(offer.state)) return fail222("dispatch_offer_hard_assignment");
    const reason = ["destination_changed", "forecast_late", "location_stale", "driver_declined"].includes(input.reason) ? input.reason : "revalidation_failed";
    return { ok: true, ledger: cancellation2(next, offer, reason, nowMs), offer: { ...offer, state: "cancelled" } };
  }
  if (input.action !== "ack") return fail222("dispatch_offer_invalid", 400);
  if (!["offered", "received", "committing", "committed"].includes(offer.state)) return fail222("dispatch_offer_closed");
  if (["committing", "committed"].includes(offer.state)) return { ok: true, ledger: next, offer };
  if (!scopeMatches2(driverPosition, input) || driverPosition.driver_id !== input.driver_id || driverPosition.vehicle_id !== input.vehicle_id || !freshDispatchPosition2(driverPosition, nowMs)) return fail222("dispatch_offer_location_stale");
  if (!input.device_key || !driverDispatchDevices22(dispatchDevices, input, input.driver_id, nowMs, input.device_key).length) return fail222("dispatch_device_unavailable");
  if (directRides.some((ride) => scopeMatches2(ride, input) && touches2(offer, ride))) return fail222("dispatch_driver_busy");
  const required = prerequisites2(offer).filter((row) => row.driver_id === input.driver_id);
  const prior = required.map((row) => ({ row, claim: next.claims[row.claim_id] })).filter((pair) => pair.claim);
  if (prior.some(({ row, claim }) => !claim.active || next.owners[claim.owner_id]?.version !== row.version || !scopeMatches2(claim, input) || !sameCapacityResource22(claim, input))) return fail222("dispatch_prerequisite_conflict");
  const receipts = { ...offer.receipts, [input.driver_id]: { at_ms: nowMs, ready: prior.length === 0 } };
  const resources = dispatchOfferResources22(offer);
  const received = { ...offer, receipts, state: "received", acknowledged_at_ms: offer.acknowledged_at_ms || nowMs };
  if (!resources.every((resource) => receipts[resource.driver_id]?.ready === true)) {
    return { ok: true, ledger: { ...next, offers: { ...next.offers, [offer.offer_id]: received } }, offer: received };
  }
  if (Object.values(next.claims).some((claim) => claim.owner_id !== offer.owner_id && claim.active && scopeMatches2(claim, input) && touches2(offer, claim))) return fail222("dispatch_driver_busy");
  const freshness = resourceFresh2(offer, { ...drivers, ...driverPosition ? { [input.driver_id]: driverPosition } : {} }, dispatchDevices, nowMs);
  if (freshness) return fail222(freshness.reason === "device_unavailable" ? "dispatch_device_unavailable" : "dispatch_offer_location_stale");
  const promoted = offer.amendment ? promoteAmendmentClaims22(next, offer, directRides) : { ok: true, ledger: next };
  if (!promoted.ok) return promoted;
  const committedClaims = { ...promoted.ledger.claims };
  for (const claim of offer.claims) committedClaims[claim.claim_id] = { ...committedClaims[claim.claim_id], offer_id: offer.offer_id };
  const committing = { ...received, state: "committing" };
  const eventId = `${offer.offer_id}:commit`;
  return { ok: true, offer: committing, ledger: {
    ...next,
    claims: committedClaims,
    owners: { ...promoted.ledger.owners, [offer.owner_id]: { ...promoted.ledger.owners[offer.owner_id], pending: true } },
    offers: { ...next.offers, [offer.offer_id]: committing },
    dispatch_events: { ...next.dispatch_events, [eventId]: {
      ...committing,
      event_id: eventId,
      type: "assignment_commit",
      state: "pending",
      created_at_ms: nowMs
    } }
  } };
}
__name(dispatchOfferDecision22, "dispatchOfferDecision");
var CONFIRMED_RECHECK_MS2 = 6e4;
var CONFIRMED_RECHECK_HORIZON_MS22 = 15 * 6e4;
function monitoredClaims2(ledger, offer) {
  const owner2 = ledger.owners[offer.owner_id];
  const split = offer.claims?.every((claim) => ["OUTBOUND", "RETURN"].some((type) => claim.claim_id === `${offer.owner_id}:${type}`));
  if (offer.state !== "committed" || offer.revalidation_paused_reason === "pickup_overdue" || !Number.isSafeInteger(offer.record_canonical_version) || offer.record_canonical_version < 1 || !Number.isSafeInteger(offer.version) || !Number.isSafeInteger(owner2?.version) || owner2.version < offer.version || !scopeMatches2(owner2, offer) || owner2.pending || owner2.released || !split && owner2.version !== offer.version) return [];
  return (offer.claims || []).filter((claim) => {
    const held = ledger.claims[claim.claim_id];
    return held?.owner_id === offer.owner_id && scopeMatches2(held, offer) && (split || held.offer_id === offer.offer_id) && held.driver_id === claim.driver_id && held.vehicle_id === claim.vehicle_id && held.start_ms === claim.start_ms && held.end_ms === claim.end_ms && Number.isFinite(claim.start_ms) && Number.isFinite(claim.end_ms) && !held.active && !held.retiring;
  });
}
__name(monitoredClaims2, "monitoredClaims");
function confirmedAssignments2(ledger) {
  return Object.values(ledger.offers || {}).filter((offer) => monitoredClaims2(ledger, offer).length);
}
__name(confirmedAssignments2, "confirmedAssignments");
function confirmedRecheckAt2(offer, ledger) {
  return Math.max(
    Math.min(...monitoredClaims2(ledger, offer).map((claim) => claim.start_ms)) - CONFIRMED_RECHECK_HORIZON_MS22,
    (offer.last_revalidated_at_ms || 0) + CONFIRMED_RECHECK_MS2
  );
}
__name(confirmedRecheckAt2, "confirmedRecheckAt");
function queueConfirmedSuccessorChecks22(ledger, nowMs, changed = null) {
  let next = ledger;
  for (const offer of confirmedAssignments2(ledger)) {
    const eventId = `${offer.offer_id}:revalidate`;
    const previous = next.dispatch_events?.[eventId];
    const affected = changed && monitoredClaims2(next, offer).some((claim) => changed.resources.some((resource) => scopeMatches2(resource, offer) && resource.claim_id !== claim.claim_id && sameCapacityResource22(claim, resource)));
    if (changed && !affected || previous?.state === "pending" || !affected && confirmedRecheckAt2(offer, next) > nowMs) continue;
    const event = {
      ...offer,
      event_id: eventId,
      type: "assignment_revalidate",
      state: "pending",
      revalidation_claim_ids: monitoredClaims2(next, offer).map((claim) => claim.claim_id),
      event_generation: (previous?.event_generation || 0) + 1,
      created_at_ms: nowMs
    };
    next = { ...next, dispatch_events: { ...next.dispatch_events, [eventId]: event } };
  }
  return next;
}
__name(queueConfirmedSuccessorChecks22, "queueConfirmedSuccessorChecks");
function acknowledgeDispatchEvent22(ledger, input) {
  const event = ledger.dispatch_events?.[input.event_id];
  if (!event || !scopeMatches2(event, input) || event.offer_id !== input.offer_id || event.version !== input.version || event.owner_id !== input.owner_id) return fail222("dispatch_event_conflict");
  const offer = ledger.offers?.[event.offer_id];
  if (event.type === "assignment_commit" && !["committed", "aborted", "superseded"].includes(offer?.state)) return fail222("dispatch_commit_unconfirmed");
  if (event.type === "assignment_revalidate" && input.event_generation !== event.event_generation) return fail222("dispatch_event_conflict");
  return { ok: true, ledger: {
    ...ledger,
    ...event.type === "assignment_revalidate" && offer ? { offers: {
      ...ledger.offers,
      [offer.offer_id]: {
        ...offer,
        last_revalidated_at_ms: event.created_at_ms,
        ...input.pickup_timing_attention === "pickup_overdue" ? { revalidation_paused_reason: "pickup_overdue" } : {}
      }
    } } : {},
    dispatch_events: {
      ...ledger.dispatch_events,
      [event.event_id]: { ...event, state: "delivered" }
    }
  } };
}
__name(acknowledgeDispatchEvent22, "acknowledgeDispatchEvent");
function nextDispatchAlarm22(ledger, drivers = {}, dispatchDevices) {
  const deadlines = Object.values(ledger.offers || {}).filter((offer) => PROVISIONAL2.has(offer.state)).flatMap((offer) => {
    return [offer.ack_deadline_ms, ...dispatchOfferResources22(offer).flatMap((resource) => {
      const position = drivers[resource.driver_id];
      const deviceEnd = dispatchDeviceDeadline22(dispatchDevices, offer, resource.driver_id, Date.now());
      return [...deviceEnd == null ? [] : [deviceEnd + 1], ...[position?.position_captured_at || position?.captured_at, position?.last_seen_at].map((value) => Date.parse(value || "") + DISPATCH_POSITION_TTL_MS2 + 1).filter(Number.isFinite)];
    })];
  });
  deadlines.push(...confirmedAssignments2(ledger).filter((offer) => ledger.dispatch_events?.[`${offer.offer_id}:revalidate`]?.state !== "pending").map((offer) => Math.max(Date.now() + 1, confirmedRecheckAt2(offer, ledger))));
  return deadlines.length ? Math.min(...deadlines) : null;
}
__name(nextDispatchAlarm22, "nextDispatchAlarm");
var LOCATION_RATE_LIMIT_PER_MINUTE2 = 12;
var LOCATION_DEDUPE_METERS2 = 15;
var LOCATION_DEDUPE_MS2 = 2e4;
var LOCATION_FUTURE_SKEW_MS2 = 12e4;
var LOCATION_STALE_DEFAULT_SECONDS2 = 300;
var LOCATION_STALE_MIN_SECONDS2 = 30;
var LOCATION_STALE_MAX_SECONDS2 = 3600;
var LOCATION_MAX_ACCURACY_M2 = 150;
var STORAGE_KEY2 = "drivers_v1";
var DIRECT_OCCUPANCY_KEY2 = "direct_occupancy_active_v1";
var DISPATCH_DEVICES_KEY2 = "dispatch_devices_v1";
function companyTrackingObjectName2(tenantId, companyId) {
  return `${tenantId}
${companyId}`;
}
__name(companyTrackingObjectName2, "companyTrackingObjectName");
function clampFreshnessSeconds2(value) {
  if (value === void 0 || value === null || value === "") return LOCATION_STALE_DEFAULT_SECONDS2;
  const n = Number(value);
  if (!Number.isFinite(n)) return LOCATION_STALE_DEFAULT_SECONDS2;
  return Math.min(LOCATION_STALE_MAX_SECONDS2, Math.max(LOCATION_STALE_MIN_SECONDS2, Math.floor(n)));
}
__name(clampFreshnessSeconds2, "clampFreshnessSeconds");
function haversineMeters2(lat1, lon1, lat2, lon2) {
  const r = 6371e3;
  const p1 = lat1 * Math.PI / 180;
  const p2 = lat2 * Math.PI / 180;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(p1) * Math.cos(p2) * Math.sin(dLon / 2) ** 2;
  return 2 * r * Math.asin(Math.min(1, Math.sqrt(h)));
}
__name(haversineMeters2, "haversineMeters");
function finiteCoord2(value, min, max) {
  const n = Number(value);
  if (!Number.isFinite(n) || n < min || n > max) return null;
  return n;
}
__name(finiteCoord2, "finiteCoord");
function validateLocationSample2(input, nowMs) {
  const latitude = finiteCoord2(input?.latitude, -90, 90);
  const longitude = finiteCoord2(input?.longitude, -180, 180);
  if (latitude === null || longitude === null) {
    return { ok: false, status: 400, error: "location_invalid" };
  }
  if (input?.accuracy !== void 0 && input?.accuracy !== null && input?.accuracy !== "") {
    const accuracy = Number(input.accuracy);
    if (!Number.isFinite(accuracy) || accuracy < 0 || accuracy > LOCATION_MAX_ACCURACY_M2) {
      return { ok: false, status: 400, error: "location_accuracy_rejected" };
    }
  }
  let capturedMs = nowMs;
  if (input?.captured_at) {
    capturedMs = Date.parse(String(input.captured_at));
    if (!Number.isFinite(capturedMs)) {
      return { ok: false, status: 400, error: "location_captured_at_invalid" };
    }
  }
  if (capturedMs - nowMs > LOCATION_FUTURE_SKEW_MS2) {
    return { ok: false, status: 400, error: "location_captured_at_invalid" };
  }
  return { ok: true, latitude, longitude, capturedMs };
}
__name(validateLocationSample2, "validateLocationSample");
function pruneHits2(hits, nowMs) {
  const cutoff = nowMs - 6e4;
  return (Array.isArray(hits) ? hits : []).filter((ts) => Number(ts) > cutoff);
}
__name(pruneHits2, "pruneHits");
function matchesTrackingScope2(row, context3, grant) {
  return Boolean(row && context3 && grant && !grant.leg_scope_retired && typeof context3.booking_id === "string" && context3.booking_id.length > 0 && typeof context3.operational_leg === "string" && context3.operational_leg.length > 0 && Number.isInteger(context3.assignment_version) && context3.assignment_version > 0 && row.tenant_id === grant.tenant_id && row.company_id === grant.company_id && row.driver_id === grant.driver_id && context3.booking_id === grant.booking_id && context3.operational_leg === grant.operational_leg && context3.assignment_version === grant.assignment_version);
}
__name(matchesTrackingScope2, "matchesTrackingScope");
function applyLocationUpdate2(drivers, input, nowMs) {
  const next = { ...drivers };
  const driverId = String(input.driver_id || "");
  const companyId = String(input.company_id || "");
  if (!driverId || !companyId) {
    return { drivers: next, result: { ok: false, status: 400, error: "location_identity_missing" } };
  }
  const checked = validateLocationSample2(input, nowMs);
  if (!checked.ok) {
    return { drivers: next, result: checked };
  }
  const current = next[driverId] ? { ...next[driverId] } : null;
  const hits = pruneHits2(current?.recent_hits, nowMs);
  if (hits.length >= LOCATION_RATE_LIMIT_PER_MINUTE2) {
    const oldest = hits[0];
    const retryAfter = Math.max(1, Math.ceil((oldest + 6e4 - nowMs) / 1e3));
    return {
      drivers: next,
      result: {
        ok: false,
        status: 429,
        error: "location_rate_limited",
        retry_after_seconds: retryAfter
      }
    };
  }
  hits.push(nowMs);
  const staleLimitMs = clampFreshnessSeconds2(input.freshness_seconds) * 1e3;
  if (nowMs - checked.capturedMs > staleLimitMs) {
    if (current) next[driverId] = { ...current, recent_hits: hits };
    return {
      drivers: next,
      result: { ok: true, applied: false, reason: "captured_at_too_old", driver_id: driverId }
    };
  }
  if (current && Number.isFinite(current.captured_ms)) {
    if (checked.capturedMs < current.captured_ms) {
      next[driverId] = { ...current, recent_hits: hits };
      return {
        drivers: next,
        result: { ok: true, applied: false, reason: "older_captured_at", driver_id: driverId }
      };
    }
    if (checked.capturedMs === current.captured_ms && (sameLocationOwner22(input.publication_owner, current.publication_owner) || !input.publication_owner && !current.publication_owner)) {
      const trackingStatus = input.tracking_status ? String(input.tracking_status) : "active";
      const contextChanged = JSON.stringify(input.tracking_context || null) !== JSON.stringify(current.tracking_context || null) || trackingStatus !== String(current.tracking_status || "active");
      if (contextChanged) {
        next[driverId] = {
          ...current,
          recent_hits: hits,
          tracking_context: input.tracking_context || null,
          tracking_status: trackingStatus,
          availability_status: input.availability_status ? String(input.availability_status) : current.availability_status
        };
        return { drivers: next, result: { ok: true, applied: true, reason: "tracking_context_updated", driver_id: driverId } };
      }
      next[driverId] = { ...current, recent_hits: hits };
      return {
        drivers: next,
        result: { ok: true, applied: false, reason: "duplicate_captured_at", driver_id: driverId }
      };
    }
    const moved = haversineMeters2(current.latitude, current.longitude, checked.latitude, checked.longitude);
    const statusChanged = String(input.tracking_status || "") !== String(current.tracking_status || "") || JSON.stringify(input.tracking_context || null) !== JSON.stringify(current.tracking_context || null) || JSON.stringify(input.publication_owner || null) !== JSON.stringify(current.publication_owner || null) || current.location_withdrawn === true;
    if (!statusChanged && moved <= LOCATION_DEDUPE_METERS2 && checked.capturedMs - current.captured_ms <= LOCATION_DEDUPE_MS2) {
      next[driverId] = {
        ...current,
        recent_hits: hits,
        last_seen_at: new Date(nowMs).toISOString()
      };
      return {
        drivers: next,
        result: {
          ok: true,
          applied: false,
          liveness_updated: true,
          reason: "duplicate_location",
          driver_id: driverId
        }
      };
    }
  }
  const accuracy = input.accuracy === void 0 || input.accuracy === null || input.accuracy === "" ? null : Number(input.accuracy);
  next[driverId] = {
    driver_id: driverId,
    tenant_id: input.tenant_id || null,
    company_id: companyId,
    vehicle_id: input.vehicle_id ? String(input.vehicle_id) : null,
    latitude: checked.latitude,
    longitude: checked.longitude,
    accuracy,
    heading: Number.isFinite(Number(input.heading)) ? Number(input.heading) : null,
    speed: Number.isFinite(Number(input.speed)) ? Number(input.speed) : null,
    captured_at: new Date(checked.capturedMs).toISOString(),
    captured_ms: checked.capturedMs,
    position_captured_at: new Date(checked.capturedMs).toISOString(),
    last_seen_at: new Date(nowMs).toISOString(),
    received_at: new Date(nowMs).toISOString(),
    availability_status: input.availability_status ? String(input.availability_status) : null,
    tracking_status: input.tracking_status ? String(input.tracking_status) : "active",
    tracking_context: input.tracking_context || null,
    publication_owner: input.publication_owner || null,
    ...current?.retired_publications ? { retired_publications: current.retired_publications } : {},
    recent_hits: hits
  };
  return {
    drivers: next,
    result: { ok: true, applied: true, driver_id: driverId }
  };
}
__name(applyLocationUpdate2, "applyLocationUpdate");
function projectCompanyLive2(drivers, { tenantId, companyId, nowMs, freshnessSeconds }) {
  const freshness = clampFreshnessSeconds2(freshnessSeconds);
  const list = [];
  for (const row of Object.values(drivers || {})) {
    if (!row || row.location_withdrawn === true || row.company_id !== companyId || row.tenant_id !== tenantId) continue;
    const positionCapturedAt = row.position_captured_at || row.captured_at || "";
    const lastSeenAt = row.last_seen_at || row.received_at || "";
    const positionAgeMs = nowMs - Date.parse(positionCapturedAt);
    const seenAgeMs = nowMs - Date.parse(lastSeenAt);
    const positionStale = !Number.isFinite(positionAgeMs) || positionAgeMs > freshness * 1e3;
    const locationFeedStale = !Number.isFinite(seenAgeMs) || seenAgeMs > freshness * 1e3;
    const accuracyOk = row.accuracy == null || Number(row.accuracy) >= 0 && Number(row.accuracy) <= LOCATION_MAX_ACCURACY_M2;
    list.push({
      driver_id: row.driver_id,
      tenant_id: row.tenant_id,
      company_id: row.company_id,
      vehicle_id: row.vehicle_id ?? null,
      latitude: row.latitude,
      longitude: row.longitude,
      accuracy: row.accuracy ?? null,
      heading: row.heading ?? null,
      speed: row.speed ?? null,
      captured_at: positionCapturedAt,
      position_captured_at: positionCapturedAt,
      last_seen_at: lastSeenAt,
      received_at: row.received_at,
      availability_status: row.availability_status ?? null,
      tracking_status: row.tracking_status ?? null,
      tracking_context: row.tracking_context || null,
      location_feed: locationFeedStale ? "stale" : "live",
      stale: locationFeedStale,
      position_stale: positionStale,
      reliable_for_eta: !positionStale && accuracyOk
    });
  }
  list.sort((a, b) => String(a.driver_id).localeCompare(String(b.driver_id)));
  return {
    ok: true,
    tenant_id: tenantId,
    company_id: companyId,
    freshness_seconds: freshness,
    drivers: list
  };
}
__name(projectCompanyLive2, "projectCompanyLive");
function clearDriver(drivers, driverId) {
  const next = { ...drivers };
  delete next[driverId];
  return next;
}
__name(clearDriver, "clearDriver");
function persistable2(drivers) {
  const out = {};
  for (const [id22, row] of Object.entries(drivers || {})) {
    if (!row) continue;
    const copy2 = { ...row };
    delete copy2.recent_hits;
    out[id22] = copy2;
  }
  return out;
}
__name(persistable2, "persistable");
var CompanyTrackingRoom2 = class {
  static {
    __name(this, "CompanyTrackingRoom");
  }
  constructor(state, env) {
    this.state = state;
    this.env = env;
    this.drivers = null;
    this.driversLoaded = null;
    this.grants = null;
    this.grantsLoaded = null;
    this.directOccupancy = null;
    this.directOccupancyLoaded = null;
    this.directOccupancyQueue = Promise.resolve();
    this.capacity = null;
    this.capacityLoaded = null;
    this.dispatchDrain = null;
    this.dispatchDevices = null;
    this.dispatchDevicesLoaded = null;
    this.hits = /* @__PURE__ */ new Map();
  }
  async load() {
    if (!this.drivers) {
      this.driversLoaded ||= this.state.storage.get(STORAGE_KEY2).then((stored) => {
        this.drivers = stored && typeof stored === "object" ? stored : {};
      }).catch((error) => {
        this.driversLoaded = null;
        throw error;
      });
      await this.driversLoaded;
    }
    if (!this.grants) {
      this.grantsLoaded ||= readCustomerGrantSnapshot22(this.state.storage).then((stored) => {
        this.grants = stored;
      }).catch((error) => {
        this.grantsLoaded = null;
        throw error;
      });
      await this.grantsLoaded;
    }
    if (!this.directOccupancy) {
      this.directOccupancyLoaded ||= this.state.storage.get(DIRECT_OCCUPANCY_KEY2).then((stored) => {
        this.directOccupancy = stored || {};
      }).catch((error) => {
        this.directOccupancyLoaded = null;
        throw error;
      });
      await this.directOccupancyLoaded;
    }
    if (!this.capacity) {
      this.capacityLoaded ||= readCapacitySnapshot22(this.state.storage).then((stored) => {
        this.capacity = stored;
      }).catch((error) => {
        this.capacityLoaded = null;
        throw error;
      });
      await this.capacityLoaded;
    }
    if (!this.dispatchDevices) {
      this.dispatchDevicesLoaded ||= this.state.storage.get(DISPATCH_DEVICES_KEY2).then((stored) => {
        this.dispatchDevices = stored || { devices: {} };
      }).catch((error) => {
        this.dispatchDevicesLoaded = null;
        throw error;
      });
      await this.dispatchDevicesLoaded;
    }
    if (this.capacity.direct_holds) this.directOccupancy = this.capacity.direct_holds;
  }
  capacityScopeAllowed(input) {
    const bound = this.capacity.scope || this.capacity.baseline || Object.values(this.capacity.owners)[0] || Object.values(this.directOccupancy)[0] || this.dispatchDevices.scope || this.grants.scope || Object.values(this.grants.grants || {}).find((row) => row?.tenant_id && row?.company_id);
    return !bound || bound.tenant_id === input.tenant_id && bound.company_id === input.company_id;
  }
  async hydrateCapacity(identities, scope2) {
    this.capacity = await hydrateCapacityRecords22(this.state.storage, this.capacity, identities, scope2);
  }
  async writeCapacity(next, scope2) {
    const bound = this.capacity.scope || scope2;
    const stored = { ...next, ...bound ? { scope: { tenant_id: bound.tenant_id, company_id: bound.company_id } } : {} };
    const expiry = nextDispatchAlarm22(stored, this.drivers, this.dispatchDevices);
    const pendingEvents = Object.values(stored.dispatch_events || {}).some((event) => event.state === "pending");
    const delivery = pendingEvents ? Date.now() + 1e3 : null;
    const deadlines = [expiry, delivery].filter((value) => value != null);
    const deadline = deadlines.length ? Math.min(...deadlines) : null;
    if (deadline != null) await this.state.storage.setAlarm(deadline);
    this.capacity = await writeCapacitySnapshot22(this.state.storage, stored, this.capacity, Date.now());
    if (stored.direct_holds) this.directOccupancy = stored.direct_holds;
    if (pendingEvents && this.env.BOOKING_API && this.env.ADMIN_TOKEN && this.state.waitUntil) {
      this.state.waitUntil(Promise.resolve().then(() => this.drainDispatchEvents()));
    }
  }
  async drainDispatchEvents() {
    if (this.dispatchDrain) return this.dispatchDrain;
    const run = /* @__PURE__ */ __name(async () => {
      let events = [];
      const choose = this.directOccupancyQueue.then(async () => {
        const pending = Object.values(this.capacity.dispatch_events || {}).filter((event) => event.state === "pending").sort((a, b) => a.created_at_ms - b.created_at_ms || a.event_id.localeCompare(b.event_id));
        const last = pending.findIndex((event) => event.event_id === this.capacity.dispatch_delivery_cursor);
        events = [...pending.slice(last + 1), ...pending.slice(0, last + 1)].slice(0, 8);
        if (events.length && this.env.BOOKING_API && this.env.ADMIN_TOKEN) await this.writeCapacity({
          ...this.capacity,
          dispatch_delivery_cursor: events.at(-1).event_id
        });
      });
      this.directOccupancyQueue = choose.catch(() => {
      });
      await choose;
      for (const event of events) {
        if (!this.env.BOOKING_API || !this.env.ADMIN_TOKEN) break;
        try {
          const response2 = await this.env.BOOKING_API.fetch(new Request("https://booking/track/dispatch/event", {
            method: "POST",
            headers: { "content-type": "application/json", "x-admin-token": this.env.ADMIN_TOKEN },
            body: JSON.stringify({ tenant_id: event.tenant_id, company_id: event.company_id, event_id: event.event_id }),
            signal: AbortSignal.timeout(8e3)
          }));
          const result2 = await response2.json();
          if (!response2.ok || result2.ok !== true) continue;
        } catch (_) {
          continue;
        }
      }
      const reschedule = this.directOccupancyQueue.then(async () => {
        const pending = Object.values(this.capacity.dispatch_events || {}).some((event) => event.state === "pending");
        const expiry = nextDispatchAlarm22(this.capacity, this.drivers, this.dispatchDevices);
        const delivery = pending ? Date.now() + 6e4 : null;
        const deadlines = [expiry, delivery].filter((value) => value != null);
        if (deadlines.length) await this.state.storage.setAlarm(Math.min(...deadlines));
        else if (this.state.storage.deleteAlarm) await this.state.storage.deleteAlarm();
      });
      this.directOccupancyQueue = reschedule.catch(() => {
      });
      await reschedule;
    }, "run");
    this.dispatchDrain = run().finally(() => {
      this.dispatchDrain = null;
    });
    return this.dispatchDrain;
  }
  async expireOffers(nowMs) {
    const next = queueConfirmedSuccessorChecks22(
      revalidateDispatchOffers22(this.capacity, this.drivers, nowMs, this.dispatchDevices),
      nowMs
    );
    if (next !== this.capacity) await this.writeCapacity(next);
  }
  async alarm() {
    await this.load();
    const operation = this.directOccupancyQueue.then(async () => {
      await this.expireOffers(Date.now());
      const next = nextDispatchAlarm22(this.capacity, this.drivers, this.dispatchDevices);
      if (next != null) await this.state.storage.setAlarm(next);
    });
    this.directOccupancyQueue = operation.catch(() => {
    });
    await operation;
    await this.drainDispatchEvents();
  }
  async fetch(request) {
    await this.load();
    const url = new URL(request.url);
    const nowMs = Date.now();
    if (request.method === "POST" && url.pathname === "/capacity") {
      const input = await request.json();
      const operation = this.directOccupancyQueue.then(async () => {
        if (!this.capacityScopeAllowed(input)) return Response.json({ ok: false, error: "capacity_scope_conflict" }, { status: 409 });
        await this.hydrateCapacity({ owner: [input.owner_id] }, input);
        await this.expireOffers(Date.now());
        if (String(this.env?.CAPACITY_BASELINE_REQUIRED) === "1" && !this.capacity.baseline && ["reserve", "activate"].includes(input.action)) {
          return Response.json({ ok: false, error: "capacity_baseline_required" }, { status: 503 });
        }
        const amended = preemptOwnerAmendments22(this.capacity, input, Date.now());
        const offer = Object.values(amended.offers || {}).find((row) => row.owner_id === input.owner_id && ["offered", "received", "committing", ...input.action === "release" ? ["committed"] : []].includes(row.state));
        if (offer && ["reserve", "activate"].includes(input.action)) {
          return Response.json({ ok: false, error: "dispatch_offer_pending" }, { status: 409 });
        }
        if (offer && input.action === "confirm" && (offer.state !== "committing" || !Array.isArray(input.canonical_claims))) {
          return Response.json({ ok: false, error: "dispatch_commit_unconfirmed" }, { status: 409 });
        }
        const prepared = preemptPrerequisiteOffers22(amended, input, Date.now());
        const decision = capacityClaimDecision22(prepared, input, Object.values(this.directOccupancy));
        if (!decision.ok) return Response.json({
          ok: false,
          error: decision.error,
          ...decision.pending_version ? { pending_version: decision.pending_version } : {}
        }, { status: decision.status });
        let next = { ...prepared, ...decision.ledger };
        if (input.action === "confirm" && prepared.owners[input.owner_id]?.pending) {
          const resources = Object.values(prepared.claims).filter((claim) => claim.owner_id === input.owner_id && claim.active);
          if (resources.length) next = queueConfirmedSuccessorChecks22(next, Date.now(), { owner_id: input.owner_id, resources });
        }
        if (offer && input.action === "confirm") next.offers = {
          ...next.offers,
          [offer.offer_id]: { ...offer, state: "committed" }
        };
        if (offer && input.action === "release") {
          const remains = Object.values(next.claims).some((claim) => claim.owner_id === offer.owner_id && claim.offer_id === offer.offer_id);
          if (!remains) next.offers = {
            ...next.offers,
            [offer.offer_id]: { ...offer, state: "cancelled", reason: "canonical_release", ended_at_ms: Date.now() }
          };
        }
        await this.writeCapacity(next, input);
        return Response.json({ ok: true, committed: true });
      });
      this.directOccupancyQueue = operation.catch(() => {
      });
      return operation;
    }
    if (request.method === "POST" && url.pathname === "/capacity-baseline") {
      const input = await request.json();
      const operation = this.directOccupancyQueue.then(async () => {
        if (!this.capacityScopeAllowed(input)) return Response.json({ ok: false, error: "capacity_scope_conflict" }, { status: 409 });
        const registrationId = input.new_company_registration;
        if (registrationId !== void 0) {
          if (typeof registrationId !== "string" || !/^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/.test(registrationId) || input.inventory_verified !== true || !Array.isArray(input.bookings) || input.bookings.length) {
            return Response.json({ ok: false, error: "new_company_capacity_identity_invalid" }, { status: 400 });
          }
          if (this.capacity.baseline?.registration_id !== registrationId) {
            if (this.capacity.baseline || await this.state.storage.get(CAPACITY_STORAGE_KEY22) || Object.keys(this.directOccupancy).length || !this.state.storage.list || (await this.state.storage.list({ prefix: "capacity_archive_v1:", limit: 1 })).size) {
              return Response.json({ ok: false, error: "new_company_capacity_existing_history" }, { status: 409 });
            }
          }
        }
        if (this.capacity.baseline) {
          if (this.capacity.baseline.tenant_id !== input.tenant_id || this.capacity.baseline.company_id !== input.company_id) {
            return Response.json({ ok: false, error: "capacity_scope_conflict" }, { status: 409 });
          }
          if (registrationId !== void 0) return Response.json({ ok: true, committed: true, already_initialized: true });
        }
        await this.hydrateCapacity({ owner: (Array.isArray(input.bookings) ? input.bookings.slice(0, 5e3) : []).map((row) => row?.owner_id) }, input);
        const decision = capacityBaselineDecision22(this.capacity, input);
        if (!decision.ok) return Response.json({ ok: false, error: decision.error }, { status: decision.status });
        const initialized = Boolean(this.capacity.baseline);
        if (initialized && JSON.stringify(decision.ledger) === JSON.stringify(this.capacity)) {
          return Response.json({ ok: true, committed: true, already_initialized: true, revalidated: true });
        }
        const next = { ...this.capacity, ...decision.ledger, baseline: this.capacity.baseline || {
          tenant_id: input.tenant_id,
          company_id: input.company_id,
          initialized_at: new Date(nowMs).toISOString(),
          inventory_digest: input.inventory_digest || null,
          ...registrationId ? { registration_id: registrationId, source: "new_company_registration" } : {}
        } };
        await this.writeCapacity(next, input);
        return Response.json({ ok: true, committed: true, ...initialized ? { already_initialized: true, revalidated: true } : {} });
      });
      this.directOccupancyQueue = operation.catch(() => {
      });
      return operation;
    }
    if (request.method === "POST" && url.pathname === "/dispatch-search") {
      const input = await request.json();
      const operation = this.directOccupancyQueue.then(async () => {
        if (!this.capacityScopeAllowed(input)) return Response.json({ ok: false, error: "capacity_scope_conflict" }, { status: 409 });
        await this.hydrateCapacity({ owner: [input.owner_id], event: [`search:${input.owner_id}:${input.version}`] }, input);
        if (!this.capacity.baseline || this.capacity.baseline.tenant_id !== input.tenant_id || this.capacity.baseline.company_id !== input.company_id) {
          return Response.json({ ok: false, error: "capacity_baseline_required" }, { status: 503 });
        }
        const decision = dispatchSearchDecision22(this.capacity, {
          tenant_id: input.tenant_id,
          company_id: input.company_id,
          owner_id: input.owner_id,
          version: input.version,
          ...input.amendment ? { amendment: true, base_version: input.base_version, retained_claims: input.retained_claims } : {}
        }, Date.now());
        if (!decision.ok) return Response.json({ ok: false, error: decision.error }, { status: decision.status });
        await this.writeCapacity(decision.ledger, input);
        return Response.json({ ok: true, committed: true, search_id: decision.event.event_id });
      });
      this.directOccupancyQueue = operation.catch(() => {
      });
      return operation;
    }
    if (request.method === "POST" && url.pathname === "/dispatch-device") {
      const input = await request.json();
      const operation = this.directOccupancyQueue.then(async () => {
        if (!this.capacityScopeAllowed(input)) return Response.json({ ok: false, error: "capacity_scope_conflict" }, { status: 409 });
        const changed = updateDispatchDevice22(this.dispatchDevices, input, Date.now());
        if (!changed.ok) return Response.json(changed, { status: changed.status });
        await this.state.storage.put(DISPATCH_DEVICES_KEY2, changed.store);
        this.dispatchDevices = changed.store;
        await this.expireOffers(Date.now());
        return Response.json({ ok: true, dispatch_device_contract_version: 1 });
      });
      this.directOccupancyQueue = operation.catch(() => {
      });
      return operation;
    }
    if (request.method === "POST" && url.pathname === "/dispatch-offer") {
      const input = await request.json();
      const operation = this.directOccupancyQueue.then(async () => {
        if (!this.capacityScopeAllowed(input)) return Response.json({ ok: false, error: "capacity_scope_conflict" }, { status: 409 });
        await this.hydrateCapacity({ owner: [input.owner_id], offer: [input.offer_id] }, input);
        if (String(this.env?.CAPACITY_BASELINE_REQUIRED) === "1" && !this.capacity.baseline) {
          return Response.json({ ok: false, error: "capacity_baseline_required" }, { status: 503 });
        }
        await this.expireOffers(Date.now());
        const decision = dispatchOfferDecision22(this.capacity, input, {
          nowMs: Date.now(),
          directRides: Object.values(this.directOccupancy),
          driverPosition: this.drivers[input.driver_id],
          dispatchDevices: this.dispatchDevices,
          drivers: this.drivers
        });
        if (!decision.ok) return Response.json({ ok: false, error: decision.error }, { status: decision.status });
        await this.writeCapacity(decision.ledger, input);
        return Response.json({ ok: true, committed: true, offer: decision.offer });
      });
      this.directOccupancyQueue = operation.catch(() => {
      });
      return operation;
    }
    if (request.method === "GET" && url.pathname === "/driver-offers") {
      const input = { tenant_id: url.searchParams.get("tenant_id"), company_id: url.searchParams.get("company_id") };
      const operation = this.directOccupancyQueue.then(async () => {
        if (!this.capacityScopeAllowed(input)) return Response.json({ ok: false, error: "capacity_scope_conflict" }, { status: 409 });
        await this.expireOffers(Date.now());
        const driverId = url.searchParams.get("driver_id");
        const deviceKey = url.searchParams.get("device_key");
        if (!deviceKey || !driverDispatchDevices22(this.dispatchDevices, input, driverId, Date.now(), deviceKey).length) {
          return Response.json({ ok: false, error: "dispatch_device_unavailable" }, { status: 409 });
        }
        const offers = Object.values(this.capacity.offers || {}).filter((offer) => dispatchOfferResources22(offer).some((resource) => resource.driver_id === driverId) && offer.tenant_id === input.tenant_id && offer.company_id === input.company_id && ["offered", "received", "committing"].includes(offer.state)).slice(0, 8).map((offer) => ({
          offer_id: offer.offer_id,
          owner_id: offer.owner_id,
          version: offer.version,
          vehicle_id: dispatchOfferResources22(offer).find((resource) => resource.driver_id === driverId).vehicle_id,
          ack_deadline_ms: offer.ack_deadline_ms,
          state: offer.state
        }));
        return Response.json({ ok: true, offers });
      });
      this.directOccupancyQueue = operation.catch(() => {
      });
      return operation;
    }
    if (url.pathname === "/dispatch-events") {
      if (request.method === "GET") {
        await this.directOccupancyQueue;
        const input = { tenant_id: url.searchParams.get("tenant_id"), company_id: url.searchParams.get("company_id") };
        if (!this.capacityScopeAllowed(input)) return Response.json({ ok: false, error: "capacity_scope_conflict" }, { status: 409 });
        return Response.json({ ok: true, events: Object.values(this.capacity.dispatch_events || {}).filter((event) => event.state === "pending" && event.tenant_id === input.tenant_id && event.company_id === input.company_id).map((event) => ({ ...event, offer_state: this.capacity.offers?.[event.offer_id]?.state })) });
      }
      if (request.method === "POST") {
        const input = await request.json();
        const operation = this.directOccupancyQueue.then(async () => {
          if (!this.capacityScopeAllowed(input)) return Response.json({ ok: false, error: "capacity_scope_conflict" }, { status: 409 });
          await this.hydrateCapacity({ event: [input.event_id] }, input);
          const decision = acknowledgeDispatchEvent22(this.capacity, input);
          if (!decision.ok) return Response.json({ ok: false, error: decision.error }, { status: decision.status });
          await this.writeCapacity(decision.ledger, input);
          return Response.json({ ok: true, committed: true });
        });
        this.directOccupancyQueue = operation.catch(() => {
        });
        return operation;
      }
    }
    if (request.method === "POST" && url.pathname === "/direct-occupancy") {
      const event = await request.json();
      const operation = this.directOccupancyQueue.then(async () => {
        if (!this.capacityScopeAllowed(event)) return Response.json({ ok: false, error: "capacity_scope_conflict" }, { status: 409 });
        await this.expireOffers(Date.now());
        const key2 = String(event.direct_ride_key || event.trip_id || "").trim();
        if (!key2 || key2.length > 200 || !event.tenant_id || !event.company_id || !event.driver_id || !event.vehicle_id || !["start", "stop"].includes(event.phase)) {
          return Response.json({ ok: false, error: "direct_occupancy_invalid" }, { status: 400 });
        }
        const existing = this.directOccupancy[key2];
        if (existing && ["tenant_id", "company_id", "driver_id", "vehicle_id"].some((field) => existing[field] !== event[field])) {
          return Response.json({ ok: false, error: "direct_occupancy_conflict" }, { status: 409 });
        }
        const stoppedKey = `direct_occupancy_stopped:${key2}`;
        const next = { ...this.directOccupancy };
        if (event.phase === "start") {
          if (String(this.env?.CAPACITY_BASELINE_REQUIRED) === "1" && !this.capacity.baseline) {
            return Response.json({ ok: false, error: "capacity_baseline_required" }, { status: 503 });
          }
          if (await this.state.storage.get(stoppedKey)) {
            return Response.json({ ok: true, applied: false, reason: "already_stopped" });
          }
          const preempted = preemptDispatchOffers22(this.capacity, event, Date.now());
          if (!existing && (Object.values(this.directOccupancy).some((ride) => ride.tenant_id === event.tenant_id && ride.company_id === event.company_id && sameCapacityResource22(ride, event)) || Object.values(preempted.claims).some((claim) => claim.tenant_id === event.tenant_id && claim.company_id === event.company_id && (claim.active || claim.end_ms > nowMs || overdueCapacityHold22(claim, nowMs, preempted.owners[claim.owner_id])) && sameCapacityResource22(claim, event)))) {
            return Response.json({ ok: false, error: "capacity_conflict" }, { status: 409 });
          }
          next[key2] = existing || {
            tenant_id: event.tenant_id,
            company_id: event.company_id,
            driver_id: event.driver_id,
            vehicle_id: event.vehicle_id,
            direct_ride_key: key2,
            trip_id: event.trip_id || null,
            started_at: new Date(nowMs).toISOString()
          };
          await this.writeCapacity({ ...preempted, direct_holds: next }, event);
          return Response.json({ ok: true, applied: true });
        } else {
          await this.state.storage.put(stoppedKey, { stopped_at: new Date(nowMs).toISOString() });
          delete next[key2];
        }
        await this.writeCapacity({ ...this.capacity, direct_holds: next }, event);
        return Response.json({ ok: true, applied: true });
      });
      this.directOccupancyQueue = operation.catch(() => {
      });
      return operation;
    }
    if (request.method === "POST" && url.pathname === "/location") {
      const input = await request.json();
      const operation = this.directOccupancyQueue.then(async () => {
        const nowMs2 = Date.now();
        if (!this.capacityScopeAllowed(input) || this.drivers[input.driver_id] && (this.drivers[input.driver_id].tenant_id !== input.tenant_id || this.drivers[input.driver_id].company_id !== input.company_id)) {
          return Response.json({ ok: false, error: "location_scope_conflict" }, { status: 409 });
        }
        const previous = this.drivers[input.driver_id];
        if (locationOwnerRetired22(previous, input.publication_owner, nowMs2)) {
          return Response.json({ ok: false, error: "location_owner_retired" }, { status: 409 });
        }
        if (boundLocationOwner22(previous?.publication_owner, nowMs2) && !boundLocationOwner22(input.publication_owner, nowMs2)) {
          return Response.json({ ok: false, error: "location_owner_unbound" }, { status: 409 });
        }
        if (input.tracking_context == null && previous?.tracking_context && boundLocationOwner22(input.publication_owner, nowMs2) && sameLocationOwner22(previous.publication_owner, input.publication_owner)) {
          const storedContext = previous.tracking_context;
          const grant = await readStoredCustomerGrant22(
            this.state.storage,
            this.grants,
            grantKey22(storedContext.booking_id, storedContext.operational_leg),
            this.grants.scope || input
          );
          const valid222 = matchesTrackingScope2(input, storedContext, grant) && grant.position_allowed === true && (storedContext.phase === "en_route_pickup" ? ["en_route_pickup", "arrived_pickup"].includes(grant.tracking_phase) : storedContext.phase === "in_progress" && grant.tracking_phase === "in_progress" && storedContext.session_id && storedContext.session_id === grant.session_id);
          const startedPickup = matchesTrackingScope2(input, storedContext, grant) && grant.position_allowed === true && storedContext.phase === "en_route_pickup" && grant.tracking_phase === "in_progress" && typeof grant.session_id === "string" && grant.session_id.length > 0 && (!storedContext.session_id || storedContext.session_id === grant.session_id) && grant.vehicle?.vehicle_id && previous.vehicle_id === grant.vehicle.vehicle_id && input.vehicle_id === grant.vehicle.vehicle_id;
          if (valid222 || startedPickup) {
            input.tracking_context = startedPickup ? { ...storedContext, phase: "in_progress", session_id: grant.session_id } : storedContext;
            input.tracking_status = input.tracking_context.phase === "in_progress" ? "active" : "en_route_pickup";
            input.availability_status = "on_trip";
          }
        }
        const context3 = input.tracking_context;
        if (input.presence_restricted_reason && !context3) {
          return Response.json({ ok: true, applied: false, reason: input.presence_restricted_reason });
        }
        if (context3 != null && !["en_route_pickup", "in_progress"].includes(context3.phase)) {
          return Response.json({ ok: false, error: "location_context_invalid" }, { status: 409 });
        }
        if (context3?.phase === "en_route_pickup") {
          const grant = await readStoredCustomerGrant22(
            this.state.storage,
            this.grants,
            grantKey22(context3.booking_id, context3.operational_leg),
            this.grants.scope || input
          );
          const valid222 = matchesTrackingScope2(input, context3, grant) && grant.position_allowed === true && ["en_route_pickup", "arrived_pickup"].includes(grant.tracking_phase);
          if (!valid222) return Response.json({ ok: false, error: "presence_context_invalid" }, { status: 409 });
          const otherTrip = Object.values(this.grants.grants || {}).some((g) => g.driver_id === input.driver_id && g.tracking_phase === "in_progress" && !g.leg_scope_retired && g.position_allowed === true);
          if (otherTrip) return Response.json({ ok: false, error: "presence_context_invalid" }, { status: 409 });
        }
        if (context3?.phase === "in_progress") {
          const grant = await readStoredCustomerGrant22(
            this.state.storage,
            this.grants,
            grantKey22(context3.booking_id, context3.operational_leg),
            this.grants.scope || input
          );
          const valid222 = matchesTrackingScope2(input, context3, grant) && grant.session_id === context3.session_id && context3.session_id && ["assigned", "en_route_pickup", "arrived_pickup", "in_progress"].includes(grant.tracking_phase);
          if (!valid222) return Response.json({ ok: false, error: "trip_context_invalid" }, { status: 409 });
        }
        const mergedHits = { ...this.drivers };
        for (const [id22, row] of Object.entries(mergedHits)) {
          const hits = this.hits.get(id22);
          if (hits) mergedHits[id22] = { ...row, recent_hits: hits };
        }
        const applied = applyLocationUpdate2(mergedHits, input, nowMs2);
        if (applied.result.applied) {
          const retired = nextRetiredLocationOwners22(previous, input.publication_owner, nowMs2);
          if (!retired) return Response.json({ ok: false, error: "location_owner_limit" }, { status: 429 });
          if (retired.length) applied.drivers[input.driver_id].retired_publications = retired;
          else delete applied.drivers[input.driver_id].retired_publications;
        }
        const nextDrivers = persistable2(applied.drivers);
        for (const [id22, row] of Object.entries(applied.drivers)) {
          if (row?.recent_hits) this.hits.set(id22, row.recent_hits);
        }
        if (applied.result.applied || applied.result.liveness_updated) {
          await this.state.storage.put(STORAGE_KEY2, nextDrivers);
        }
        this.drivers = nextDrivers;
        await this.expireOffers(nowMs2);
        const status = applied.result.status || 200;
        return Response.json(applied.result, { status });
      });
      this.directOccupancyQueue = operation.catch(() => {
      });
      return operation;
    }
    if (request.method === "POST" && url.pathname === "/location-withdraw") {
      const input = await request.json();
      const operation = this.directOccupancyQueue.then(async () => {
        const nowMs2 = Date.now();
        if (!input.driver_id || !input.tenant_id || !input.company_id || !boundLocationOwner22(input.publication_owner, nowMs2)) {
          return Response.json({ ok: false, error: "location_owner_invalid" }, { status: 400 });
        }
        const previous = this.drivers[input.driver_id];
        if (!this.capacityScopeAllowed(input) || previous && (previous.tenant_id !== input.tenant_id || previous.company_id !== input.company_id)) {
          return Response.json({ ok: false, error: "location_scope_conflict" }, { status: 409 });
        }
        if (previous && !boundLocationOwner22(previous.publication_owner, nowMs2)) {
          return Response.json({ ok: true, cleared: false, reason: "owner_unbound" });
        }
        if (locationOwnerRetired22(previous, input.publication_owner, nowMs2)) {
          return Response.json({ ok: true, cleared: false, reason: "already_withdrawn" });
        }
        const matches222 = sameLocationOwner22(previous?.publication_owner, input.publication_owner);
        const retired = retainedLocationOwners22(previous, nowMs2);
        if (previous && !matches222) {
          if (retired.length >= LOCATION_RETIRED_OWNER_LIMIT22) {
            return Response.json({ ok: false, error: "location_owner_limit" }, { status: 429 });
          }
          retired.push(input.publication_owner);
        }
        let row = previous ? { ...previous, retired_publications: retired } : {
          tenant_id: input.tenant_id,
          company_id: input.company_id,
          driver_id: input.driver_id,
          publication_owner: input.publication_owner,
          retired_publications: []
        };
        if (!previous || matches222) row = {
          tenant_id: input.tenant_id,
          company_id: input.company_id,
          driver_id: input.driver_id,
          publication_owner: input.publication_owner,
          retired_publications: retired,
          location_withdrawn: true
        };
        const next = { ...this.drivers, [input.driver_id]: row };
        await this.state.storage.put(STORAGE_KEY2, persistable2(next));
        this.drivers = persistable2(next);
        if (matches222) this.hits.delete(input.driver_id);
        await this.expireOffers(nowMs2);
        return Response.json({
          ok: true,
          cleared: Boolean(matches222),
          reason: matches222 ? "withdrawn" : previous ? "owner_mismatch" : "location_absent"
        });
      });
      this.directOccupancyQueue = operation.catch(() => {
      });
      return operation;
    }
    if (request.method === "POST" && url.pathname === "/clear") {
      const input = await request.json();
      const operation = this.directOccupancyQueue.then(async () => {
        const previous = this.drivers[input.driver_id];
        if (input.publication_owner && (!previous?.publication_owner || !sameLocationOwner22(previous.publication_owner, input.publication_owner)) || previous?.publication_owner && !input.publication_owner) {
          return Response.json({ ok: true, cleared: false, reason: previous?.publication_owner ? "owner_mismatch" : "owner_unbound" });
        }
        if (previous && input.tenant_id && (previous.tenant_id !== input.tenant_id || previous.company_id !== input.company_id)) {
          return Response.json({ ok: false, error: "location_scope_conflict" }, { status: 409 });
        }
        if (boundLocationOwner22(previous?.publication_owner, Date.now())) {
          return Response.json({ ok: true, cleared: false, reason: "owner_unbound" });
        }
        const next = clearDriver(this.drivers, String(input.driver_id || ""));
        await this.state.storage.put(STORAGE_KEY2, next);
        this.drivers = next;
        this.hits.delete(String(input.driver_id || ""));
        await this.expireOffers(Date.now());
        return Response.json({ ok: true, cleared: true });
      });
      this.directOccupancyQueue = operation.catch(() => {
      });
      return operation;
    }
    if (request.method === "POST" && url.pathname === "/customer-grant") {
      const event = await request.json();
      const operation = this.directOccupancyQueue.then(async () => {
        if (!this.capacityScopeAllowed(event)) return Response.json({ ok: false, error: "customer_grant_scope_conflict" }, { status: 409 });
        const previous = await hydrateCustomerGrantEvent22(this.state.storage, this.grants, event, this.grants.scope || event);
        const applied = applyCustomerLifecycle22(previous, event, Date.now());
        if (applied.applied) {
          const stored = { ...applied.store, scope: this.grants.scope || {
            tenant_id: applied.grant.tenant_id,
            company_id: applied.grant.company_id
          } };
          this.grants = await writeCustomerGrantSnapshot22(this.state.storage, stored, Date.now());
        }
        const grant = applied.grant || null;
        return Response.json({
          ok: true,
          applied: applied.applied,
          confirmed: applied.confirmed === true,
          reason: applied.reason,
          // Renewal cannot manufacture access when no usable token survived.
          ...event.kind === "renew" ? { renewal_access_retained: Boolean(grant && [grant.access_token_hash, ...grant.access_token_hashes || []].some((hash22) => hash22 && customerAccessAllowed22(grant, {
            tenant_id: grant.tenant_id,
            company_id: grant.company_id,
            booking_id: grant.booking_id,
            operational_leg: grant.operational_leg,
            customer_id: grant.customer_id,
            access_token_hash: hash22
          }).ok)) } : {},
          lifecycle_seq: grant?.lifecycle_seq ?? null,
          assignment_version: grant?.assignment_version ?? null,
          tracking_phase: grant?.tracking_phase ?? null,
          position_allowed: grant?.position_allowed === true
        });
      });
      this.directOccupancyQueue = operation.catch(() => {
      });
      return operation;
    }
    if (request.method === "GET" && url.pathname === "/customer-live") {
      const operation = this.directOccupancyQueue.then(async () => {
        const snapshotNowMs = Date.now();
        const key2 = grantKey22(url.searchParams.get("booking_id"), url.searchParams.get("operational_leg"));
        const grant = await readStoredCustomerGrant22(this.state.storage, this.grants, key2, this.grants.scope || {
          tenant_id: url.searchParams.get("tenant_id"),
          company_id: url.searchParams.get("company_id")
        });
        const access = customerAccessAllowed22(grant, {
          tenant_id: url.searchParams.get("tenant_id"),
          company_id: url.searchParams.get("company_id"),
          booking_id: url.searchParams.get("booking_id"),
          operational_leg: url.searchParams.get("operational_leg"),
          customer_id: url.searchParams.get("customer_id"),
          access_token_hash: url.searchParams.get("access_token_hash"),
          assignment_version: url.searchParams.get("assignment_version"),
          session_id: url.searchParams.get("session_id")
        });
        if (!access.ok) return Response.json({ ok: false, error: access.error }, { status: access.status });
        const live = projectCompanyLive2(this.drivers, {
          tenantId: grant.tenant_id,
          companyId: grant.company_id,
          nowMs: snapshotNowMs,
          freshnessSeconds: url.searchParams.get("freshness_seconds")
        });
        const driver = (live.drivers || []).find((row) => row.driver_id === grant.driver_id) || null;
        const stored = this.drivers[grant.driver_id];
        const context3 = stored?.tracking_context;
        const matches222 = matchesTrackingScope2(stored, context3, grant) && grant.position_allowed === true && ["en_route_pickup", "in_progress"].includes(context3.phase) && (context3.phase === grant.tracking_phase || context3.phase === "en_route_pickup" && grant.tracking_phase === "arrived_pickup") && (context3.phase === "in_progress" ? Boolean(context3.session_id && context3.session_id === grant.session_id) : !context3.session_id || context3.session_id === grant.session_id);
        const snapshot = projectCustomerSnapshot22({ grant, driver: matches222 ? driver : null, nowMs: snapshotNowMs, eta: null, route: null });
        return Response.json(snapshot);
      });
      this.directOccupancyQueue = operation.catch(() => {
      });
      return operation;
    }
    if (request.method === "GET" && url.pathname === "/customer-grant") {
      const operation = this.directOccupancyQueue.then(async () => {
        const key2 = grantKey22(url.searchParams.get("booking_id"), url.searchParams.get("operational_leg"));
        let grant = await readStoredCustomerGrant22(this.state.storage, this.grants, key2, this.grants.scope);
        const driverId = url.searchParams.get("active_driver_id");
        if (grant?.leg_scope_retired && driverId && !url.searchParams.get("operational_leg")) {
          const candidates = Object.values(this.grants.grants || {}).filter((row) => row.booking_id === url.searchParams.get("booking_id") && row.driver_id === driverId && row.position_allowed === true && ["en_route_pickup", "in_progress"].includes(row.tracking_phase));
          grant = candidates.length === 1 ? candidates[0] : null;
        }
        if (!grant) return Response.json({ ok: false, error: "not_found" }, { status: 404 });
        return Response.json({ ok: true, grant });
      });
      this.directOccupancyQueue = operation.catch(() => {
      });
      return operation;
    }
    if (request.method === "GET" && url.pathname === "/live") {
      const expiry = this.directOccupancyQueue.then(() => this.expireOffers(Date.now()));
      this.directOccupancyQueue = expiry.catch(() => {
      });
      await expiry;
      const freshness = url.searchParams.get("freshness_seconds");
      const body = projectCompanyLive2(this.drivers, {
        tenantId: url.searchParams.get("tenant_id") || "",
        companyId: url.searchParams.get("company_id") || "",
        nowMs,
        freshnessSeconds: freshness
      });
      return Response.json({
        ...body,
        dispatch_offer_contract_version: 1,
        dispatch_device_contract_version: 1,
        dispatch_devices: projectDispatchDevices22(this.dispatchDevices, { tenant_id: body.tenant_id, company_id: body.company_id }, Date.now()),
        dispatch_offers: Object.values(this.capacity.offers || {}).filter((row) => row.tenant_id === url.searchParams.get("tenant_id") && row.company_id === url.searchParams.get("company_id") && ["offered", "received", "committing"].includes(row.state)),
        capacity_contract_version: 1,
        capacity_baseline: this.capacity.baseline || null,
        capacity_reservations: Object.values(this.capacity.claims).filter((row) => row.tenant_id === url.searchParams.get("tenant_id") && row.company_id === url.searchParams.get("company_id")).map((row) => ({
          ...row,
          capacity_version: this.capacity.owners[row.owner_id]?.version,
          completion_unconfirmed: overdueCapacityHold22(row, nowMs, this.capacity.owners[row.owner_id]),
          reservation_expired: unstartedCapacityExpired22(row, nowMs, this.capacity.owners[row.owner_id]),
          ...row.offer_id ? { capacity_offer_state: this.capacity.offers?.[row.offer_id]?.owner_id === row.owner_id && this.capacity.offers[row.offer_id].tenant_id === row.tenant_id && this.capacity.offers[row.offer_id].company_id === row.company_id ? this.capacity.offers[row.offer_id].state : "unresolved" } : {},
          capacity_pending: this.capacity.owners[row.owner_id]?.pending === true
        })),
        active_direct_rides: Object.values(this.directOccupancy).filter((row) => row.tenant_id === url.searchParams.get("tenant_id") && row.company_id === url.searchParams.get("company_id"))
      });
    }
    return Response.json({ ok: false, error: "not_found" }, { status: 404 });
  }
};
init_company_dispatch2();
var PRESENCE_STILL_UPDATE_SECONDS = 120;
var PRESENCE_DRIVING_UPDATE_SECONDS = 25;
var PRESENCE_DRIVING_SPEED_MPS = 2;
function presenceNextUpdateSeconds(speed) {
  const value = Number(speed);
  if (Number.isFinite(value) && value >= PRESENCE_DRIVING_SPEED_MPS) {
    return PRESENCE_DRIVING_UPDATE_SECONDS;
  }
  return PRESENCE_STILL_UPDATE_SECONDS;
}
__name(presenceNextUpdateSeconds, "presenceNextUpdateSeconds");
function presenceDuty(driver, nowMs) {
  if (!driver || typeof driver !== "object") {
    return { allow: false, reason: "driver_not_found", clear: false, vehicleId: "" };
  }
  const work = effectiveWorkState({ driver, atMs: nowMs });
  const inactive = !work.account_active || work.manual_override?.active && work.manual_override?.kind === "inactive";
  if (inactive) return { allow: false, reason: "driver_inactive", clear: true, vehicleId: "" };
  if (!work.working) return { allow: false, reason: "driver_off_duty", clear: true, vehicleId: "" };
  if (pauseBlocksInstant(driver, nowMs)) {
    return { allow: false, reason: "driver_paused", clear: true, vehicleId: "" };
  }
  const vehicleId = String(driver.assigned_vehicle_id || driver.assignedVehicleId || "").trim();
  return {
    allow: true,
    reason: "",
    clear: false,
    vehicleId,
    availabilityStatus: normalizeDispatchAvailability2(driver.availability_status) === AVAILABILITY2.ON_TRIP ? "on_trip" : "available"
  };
}
__name(presenceDuty, "presenceDuty");
function presenceIdentityConflict(session, body) {
  const conflicts = [
    ["driver_id", session?.driver_id, body?.driver_id ?? body?.driverId],
    ["company_id", session?.company_id, body?.company_id ?? body?.companyId],
    ["tenant_id", session?.tenant_id, body?.tenant_id ?? body?.tenantId]
  ];
  for (const [field, expected, supplied] of conflicts) {
    const value = String(supplied ?? "").trim();
    if (value && value !== String(expected || "")) return field;
  }
  return "";
}
__name(presenceIdentityConflict, "presenceIdentityConflict");
async function acceptDriverPresenceLocation({
  env,
  session,
  body,
  nowMs = Date.now(),
  driver
} = {}) {
  const ops = {
    booking_kv_reads: 1,
    driver_index_reads: driver ? 1 : 0,
    do_requests: 0,
    gps_kv_writes: 0
  };
  const duty = presenceDuty(driver, nowMs);
  const ownership = driverLocationOwner(session, body);
  if (!ownership.ok) return { status: ownership.status, body: { ok: false, error: ownership.error, ops } };
  const boundPickup = body?.pre_start === true && (duty.allow || ["driver_off_duty", "driver_paused"].includes(duty.reason));
  const restrictedExisting = !duty.allow && !body?.pre_start && ownership.owner?.activation_id && ["driver_off_duty", "driver_paused"].includes(duty.reason);
  if (!duty.allow && !boundPickup && !restrictedExisting) {
    let cleared2 = false;
    if (duty.clear && realtimeEnabled(env)) {
      ops.do_requests += 1;
      cleared2 = await clearPresence(env, session, ownership.owner);
    }
    return {
      status: 200,
      body: {
        ok: true,
        applied: false,
        mode: "presence",
        reason: duty.reason,
        cleared: cleared2,
        next_update_seconds: null,
        ops
      }
    };
  }
  if (!realtimeEnabled(env)) {
    return {
      status: 503,
      body: { ok: false, error: "tracking_unavailable", ops }
    };
  }
  ops.do_requests += 1;
  const posted = await postPresence(env, {
    tenant_id: session.tenant_id,
    company_id: session.company_id,
    driver_id: session.driver_id,
    vehicle_id: boundPickup || restrictedExisting ? String(driver?.assigned_vehicle_id || driver?.assignedVehicleId || "").trim() : duty.vehicleId,
    latitude: body?.lat ?? body?.latitude,
    longitude: body?.lon ?? body?.longitude,
    accuracy: body?.accuracy_m ?? body?.accuracy ?? null,
    heading: body?.heading ?? null,
    speed: body?.speed ?? null,
    captured_at: body?.captured_at ?? body?.ts ?? new Date(nowMs).toISOString(),
    availability_status: boundPickup || restrictedExisting ? "on_trip" : duty.availabilityStatus,
    tracking_status: boundPickup ? "en_route_pickup" : "presence",
    publication_owner: ownership.owner,
    ...session.vehicle_device_id ? { vehicle_device_presence: {
      device_id: session.vehicle_device_id,
      device_token_hash: session.vehicle_device_token_hash
    } } : {},
    ...restrictedExisting ? { presence_restricted_reason: duty.reason } : {},
    ...body?.pre_start === true ? { tracking_context: {
      booking_id: String(body.booking_id || ""),
      operational_leg: String(body.operational_leg || ""),
      assignment_version: Number(body.assignment_version),
      phase: "en_route_pickup"
    } } : {},
    freshness_seconds: env?.TRACKING_LOCATION_FRESHNESS_SECONDS
  });
  let cleared = false;
  if (restrictedExisting && posted.body?.reason === duty.reason) {
    ops.do_requests += 1;
    cleared = await clearPresence(env, session, ownership.owner);
  }
  return {
    status: posted.status,
    body: {
      ok: posted.body?.ok !== false && posted.status < 400,
      applied: posted.body?.applied === true,
      mode: "presence",
      reason: posted.body?.reason || posted.body?.error || null,
      cleared,
      next_update_seconds: presenceNextUpdateSeconds(body?.speed),
      ops,
      ...posted.body?.retry_after_seconds ? { retry_after_seconds: posted.body.retry_after_seconds } : {}
    }
  };
}
__name(acceptDriverPresenceLocation, "acceptDriverPresenceLocation");
function realtimeEnabled(env) {
  const value = String(env?.tracking_realtime_do_enabled ?? "").trim().toLowerCase();
  return value === "1" || value === "true" || value === "on" || value === "yes";
}
__name(realtimeEnabled, "realtimeEnabled");
async function roomFetch(env, session, path, init) {
  const ns = env?.COMPANY_TRACKING;
  if (!ns || typeof ns.idFromName !== "function" || typeof ns.get !== "function") {
    throw new Error("tracking_realtime_unavailable");
  }
  const stub = ns.get(ns.idFromName(companyTrackingObjectName2(session.tenant_id, session.company_id)));
  return stub.fetch(`https://company-tracking.internal${path}`, init);
}
__name(roomFetch, "roomFetch");
async function postPresence(env, payload) {
  const response2 = await roomFetch(env, payload, "/location", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(payload)
  });
  const body = await response2.json().catch(() => ({ ok: false, error: "tracking_unavailable" }));
  return { status: response2.status, body };
}
__name(postPresence, "postPresence");
async function clearPresence(env, session, owner2) {
  if (!owner2) return false;
  const response2 = await roomFetch(env, session, owner2.activation_id ? "/location-withdraw" : "/clear", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      tenant_id: session.tenant_id,
      company_id: session.company_id,
      driver_id: session.driver_id,
      publication_owner: owner2
    })
  });
  const result2 = await response2.json();
  if (!response2.ok || result2.ok !== true) throw new Error("tracking_withdraw_unavailable");
  return result2.cleared === true;
}
__name(clearPresence, "clearPresence");
function dispatchDirectionsUrl2(token, from, to, departAt, includeGeometry = false) {
  const path = `${from.longitude},${from.latitude};${to.longitude},${to.latitude}`;
  const depart = departAtIso2(departAt);
  const departQuery = depart ? `&depart_at=${encodeURIComponent(depart)}` : "";
  return `https://api.mapbox.com/directions/v5/mapbox/driving-traffic/${path}?overview=${includeGeometry ? "simplified&geometries=geojson" : "false"}${departQuery}&access_token=${encodeURIComponent(token)}`;
}
__name(dispatchDirectionsUrl2, "dispatchDirectionsUrl");
async function mapboxDispatchRouteEta22(env, { origin, destination, depart_at, includeGeometry = false } = {}) {
  const token = String(env?.MAPBOX_TOKEN || "").trim();
  if (!token) throw new Error("mapbox_unconfigured");
  const from = point3(origin);
  const to = point3(destination);
  if (!from || !to) throw new Error("mapbox_coordinates");
  const url = dispatchDirectionsUrl2(token, from, to, depart_at, includeGeometry);
  const response2 = await ownedReleaseFetchV1(url);
  if (!response2.ok) throw new Error("mapbox_http");
  const body = await response2.json();
  const route = body?.routes?.[0];
  const duration = Number(route?.duration);
  const distance2 = Number(route?.distance);
  const typical = Number(route?.duration_typical);
  if (!Number.isFinite(duration)) throw new Error("mapbox_empty");
  return {
    ...includeGeometry ? { route: publicRouteGeometry2(route?.geometry) } : {},
    duration_seconds: duration,
    duration_typical_seconds: Number.isFinite(typical) ? typical : null,
    distance_meters: Number.isFinite(distance2) ? distance2 : null
  };
}
__name(mapboxDispatchRouteEta22, "mapboxDispatchRouteEta");
function departAtIso2(value) {
  if (value == null || value === "") return "";
  const ms = Date.parse(String(value));
  if (!Number.isFinite(ms)) return "";
  return new Date(ms).toISOString();
}
__name(departAtIso2, "departAtIso");
function point3(value) {
  const latitude = Number(value?.latitude ?? value?.lat);
  const longitude = Number(value?.longitude ?? value?.lon ?? value?.lng);
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return null;
  if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) return null;
  return { latitude, longitude };
}
__name(point3, "point");
function publicRouteGeometry2(geometry) {
  if (geometry?.type !== "LineString" || !Array.isArray(geometry.coordinates) || geometry.coordinates.length < 2 || geometry.coordinates.length > 5e3) return null;
  const points = geometry.coordinates.map((c) => Array.isArray(c) && c.length >= 2 && typeof c[0] === "number" && typeof c[1] === "number" ? point3({ longitude: c[0], latitude: c[1] }) : null);
  return points.every(Boolean) ? { coordinates: points } : null;
}
__name(publicRouteGeometry2, "publicRouteGeometry");
var KvBudgetExceededError = class extends Error {
  static {
    __name(this, "KvBudgetExceededError");
  }
  constructor(kind, used, max) {
    super(`kv_budget_${kind}:${used}/${max}`);
    this.name = "KvBudgetExceededError";
    this.kind = kind;
    this.used = used;
    this.max = max;
  }
};
function logKvPass(label222, payload) {
  try {
    console.log(`[${label222}] ${JSON.stringify(payload)}`);
  } catch (_) {
  }
}
__name(logKvPass, "logKvPass");
function wrapKvBudget(ns, options = {}) {
  const maxReads = Math.max(0, Number(options.maxReads) || 0);
  const maxLists = Math.max(0, Number(options.maxLists) || 0);
  const maxWrites = Math.max(0, Number(options.maxWrites) || 0);
  const maxDeletes = options.maxDeletes == null ? Infinity : Math.max(0, Number(options.maxDeletes) || 0);
  const counts = { read: 0, list: 0, write: 0, delete: 0 };
  if (!ns || typeof ns !== "object") {
    return { counts, namespace: ns };
  }
  const charge = /* @__PURE__ */ __name((kind, max) => {
    counts[kind] += 1;
    if (counts[kind] > max) {
      throw new KvBudgetExceededError(kind, counts[kind], max);
    }
  }, "charge");
  return {
    counts,
    get: /* @__PURE__ */ __name(async (...args) => {
      charge("read", maxReads);
      return ns.get(...args);
    }, "get"),
    getWithMetadata: /* @__PURE__ */ __name(async (...args) => {
      charge("read", maxReads);
      if (typeof ns.getWithMetadata !== "function") return { value: null, metadata: null };
      return ns.getWithMetadata(...args);
    }, "getWithMetadata"),
    list: /* @__PURE__ */ __name(async (...args) => {
      charge("list", maxLists);
      return ns.list(...args);
    }, "list"),
    put: /* @__PURE__ */ __name(async (...args) => {
      charge("write", maxWrites);
      return ns.put(...args);
    }, "put"),
    delete: /* @__PURE__ */ __name(async (...args) => {
      counts.delete += 1;
      if (counts.delete > maxDeletes) {
        throw new KvBudgetExceededError("delete", counts.delete, maxDeletes);
      }
      charge("write", maxWrites);
      return ns.delete(...args);
    }, "delete")
  };
}
__name(wrapKvBudget, "wrapKvBudget");
function json2(data, init = {}) {
  const headers = new Headers(init.headers);
  headers.set("content-type", "application/json; charset=utf-8");
  return new Response(JSON.stringify(data, null, 2), { ...init, headers });
}
__name(json2, "json");
function withCors(resp, origin) {
  const headers = new Headers(resp.headers);
  headers.set("access-control-allow-origin", origin);
  headers.set("access-control-allow-methods", "GET,POST,OPTIONS");
  headers.set("access-control-allow-headers", "content-type,x-admin-token,authorization");
  headers.set("access-control-max-age", "86400");
  return new Response(resp.body, {
    status: resp.status,
    statusText: resp.statusText,
    headers
  });
}
__name(withCors, "withCors");
function getOrigin(req) {
  return req.headers.get("origin") ?? "*";
}
__name(getOrigin, "getOrigin");
function getBearerToken(req) {
  const a = req.headers.get("authorization");
  if (!a) return "";
  const m = a.match(/^Bearer\s+(.+)$/i);
  return m ? (m[1] || "").trim() : "";
}
__name(getBearerToken, "getBearerToken");
function getToken(req, url) {
  const h = req.headers.get("x-admin-token")?.trim();
  if (h) return h;
  const b = getBearerToken(req);
  if (b) return b;
  return "";
}
__name(getToken, "getToken");
function requireAdmin(req, url, env) {
  const expected = (env.ADMIN_TOKEN || "").trim();
  if (!expected) {
    throw new Error("ADMIN_TOKEN is not configured on the Worker (set as secret).");
  }
  const got = getToken(req, url);
  if (!got || got !== expected) throw new Error("Unauthorized");
}
__name(requireAdmin, "requireAdmin");
function hasValidAdminToken(req, url, env) {
  const expected = (env?.ADMIN_TOKEN || "").trim();
  if (!expected) return false;
  const got = getToken(req, url);
  return !!got && got === expected;
}
__name(hasValidAdminToken, "hasValidAdminToken");
var COMPANY_SESSION_KEY_PREFIX = "company_admin:session:";
var COMPANY_SESSION_KEY_SUFFIX = ":v1";
var PUBLIC_DRIVER_SESSION_KEY_PREFIX = "public_driver:session:";
var PUBLIC_DRIVER_SESSION_KEY_SUFFIX = ":v1";
function companySessionKey(tokenHash) {
  const safeHash = safeStr22(tokenHash, 200);
  if (!safeHash) return "";
  return `${COMPANY_SESSION_KEY_PREFIX}${safeHash.toLowerCase()}${COMPANY_SESSION_KEY_SUFFIX}`;
}
__name(companySessionKey, "companySessionKey");
async function sha256Hex22(text22) {
  const data = new TextEncoder().encode(String(text22 || ""));
  const digest322 = await crypto.subtle.digest("SHA-256", data);
  const bytes32 = new Uint8Array(digest322);
  let hex2 = "";
  for (const byte of bytes32) {
    hex2 += byte.toString(16).padStart(2, "0");
  }
  return hex2;
}
__name(sha256Hex22, "sha256Hex");
async function hashCompanySessionToken(token) {
  const normalized2 = safeStr22(token, 512);
  if (!normalized2) return "";
  const hash22 = await sha256Hex22(normalized2);
  const trimmed = safeStr22(hash22, 200);
  return trimmed ? trimmed.toLowerCase() : "";
}
__name(hashCompanySessionToken, "hashCompanySessionToken");
function publicDriverSessionKey(tokenHash) {
  const safeHash = safeStr22(tokenHash, 200);
  if (!safeHash) return "";
  return `${PUBLIC_DRIVER_SESSION_KEY_PREFIX}${safeHash.toLowerCase()}${PUBLIC_DRIVER_SESSION_KEY_SUFFIX}`;
}
__name(publicDriverSessionKey, "publicDriverSessionKey");
async function loadCompanySessionFromRequest(req, env) {
  if (!env?.BOOKING_KV) return null;
  const token = getBearerToken(req);
  if (!token) return null;
  const tokenHash = await hashCompanySessionToken(token);
  if (!tokenHash) return null;
  const key2 = companySessionKey(tokenHash);
  if (!key2) return null;
  const record = await env.BOOKING_KV.get(key2, { type: "json" });
  if (!record || typeof record !== "object" || Array.isArray(record)) return null;
  const role = (safeStr22(record.role, 40) ?? "").toLowerCase();
  if (role !== "company_admin") return null;
  const tenantId = safeStr22(record.tenant_id ?? record.tenantId, 80);
  const companyId = safeStr22(record.company_id ?? record.companyId, 80);
  const expiresAt = safeStr22(record.expires_at ?? record.expiresAt, 80);
  const expiresAtMs = Date.parse(expiresAt || "");
  if (!Number.isFinite(expiresAtMs) || Date.now() >= expiresAtMs) {
    try {
      await env.BOOKING_KV.delete(key2);
    } catch (_) {
    }
    return null;
  }
  if (!tenantId || !companyId) return null;
  return { tenant_id: tenantId, company_id: companyId };
}
__name(loadCompanySessionFromRequest, "loadCompanySessionFromRequest");
async function loadPublicDriverSessionFromRequest(req, env) {
  if (!env?.BOOKING_KV) return null;
  const token = getBearerToken(req);
  if (!token) return null;
  const tokenHash = await hashCompanySessionToken(token);
  if (!tokenHash) return null;
  const key2 = publicDriverSessionKey(tokenHash);
  if (!key2) return null;
  const record = await env.BOOKING_KV.get(key2, { type: "json" });
  if (!record || typeof record !== "object" || Array.isArray(record)) return null;
  const role = (safeStr22(record.role, 24) ?? "").toLowerCase();
  if (role !== "driver") return null;
  const tenantId = safeStr22(record.tenant_id ?? record.tenantId, 80);
  const companyId = safeStr22(record.company_id ?? record.companyId, 80);
  const driverId = safeStr22(record.driver_id ?? record.driverId, 96);
  const expiresAt = safeStr22(record.expires_at ?? record.expiresAt, 80);
  const expiresAtMs = Date.parse(expiresAt || "");
  if (!Number.isFinite(expiresAtMs) || Date.now() >= expiresAtMs) {
    try {
      await env.BOOKING_KV.delete(key2);
    } catch (_) {
    }
    return null;
  }
  if (!tenantId || !companyId || !driverId) return null;
  return {
    tenant_id: tenantId,
    company_id: companyId,
    driver_id: driverId,
    token_hash: tokenHash,
    expires_ms: expiresAtMs,
    native_device_id: safeStr22(record.native_device_id, 128) || null,
    ...record.vehicle_device_id ? {
      vehicle_device_id: safeStr22(record.vehicle_device_id, 96),
      vehicle_device_token_hash: safeStr22(record.vehicle_device_token_hash, 64),
      assigned_vehicle_id: safeStr22(record.assigned_vehicle_id ?? record.assignedVehicleId, 96)
    } : {}
  };
}
__name(loadPublicDriverSessionFromRequest, "loadPublicDriverSessionFromRequest");
function maskScopeForTripKpiLog(value) {
  const text22 = safeStr22(value, 80) ?? "";
  if (!text22) return "-";
  if (text22.length <= 4) return `\u2026${text22.substring(text22.length - 1)}`;
  return `${text22.substring(0, 2)}\u2026${text22.substring(text22.length - 2)}`;
}
__name(maskScopeForTripKpiLog, "maskScopeForTripKpiLog");
function _extractCallerSuppliedDriverId(req, url, body = null) {
  const search = url?.searchParams;
  return safeStr22(
    body?.driver_id ?? body?.driverId ?? body?.actor_driver_id ?? body?.actorDriverId ?? search?.get?.("driver_id") ?? search?.get?.("driverId") ?? req?.headers?.get?.("x-fluxidi-driver-id") ?? req?.headers?.get?.("x-driver-id"),
    96
  ) ?? "";
}
__name(_extractCallerSuppliedDriverId, "_extractCallerSuppliedDriverId");
async function requireDriverSessionOrAdminForScope(req, url, env, { body = null, routeLabel = "" } = {}) {
  const origin = getOrigin(req);
  if (hasValidAdminToken(req, url, env)) {
    if (routeLabel) console.log(`[${routeLabel}][AUTH] auth_mode=admin_token`);
    return { ok: true, auth_mode: "admin_token", driver_session: null };
  }
  const driverSession = await loadPublicDriverSessionFromRequest(req, env);
  if (!driverSession) {
    if (routeLabel) console.log(`[${routeLabel}][AUTH] auth_mode=none result=unauthorized`);
    return {
      ok: false,
      response: withCors(
        json2({ ok: false, error: "unauthorized" }, { status: 401 }),
        origin
      )
    };
  }
  const clientScope = extractScopeFromQueryAndBody(url, body);
  if (clientScope?.tenant_id && clientScope.tenant_id !== driverSession.tenant_id) {
    if (routeLabel) {
      console.log(
        `[${routeLabel}][AUTH] auth_mode=driver_session result=forbidden reason=tenant_mismatch`
      );
    }
    return {
      ok: false,
      response: withCors(json2({ ok: false, error: "forbidden" }, { status: 403 }), origin)
    };
  }
  if (clientScope?.company_id && clientScope.company_id !== driverSession.company_id) {
    if (routeLabel) {
      console.log(
        `[${routeLabel}][AUTH] auth_mode=driver_session result=forbidden reason=company_mismatch`
      );
    }
    return {
      ok: false,
      response: withCors(json2({ ok: false, error: "forbidden" }, { status: 403 }), origin)
    };
  }
  const clientDriverId = _extractCallerSuppliedDriverId(req, url, body);
  if (clientDriverId && clientDriverId !== driverSession.driver_id) {
    if (routeLabel) {
      console.log(
        `[${routeLabel}][AUTH] auth_mode=driver_session result=forbidden reason=driver_mismatch`
      );
    }
    return {
      ok: false,
      response: withCors(json2({ ok: false, error: "forbidden" }, { status: 403 }), origin)
    };
  }
  if (routeLabel) {
    console.log(
      `[${routeLabel}][AUTH] auth_mode=driver_session tenant=${maskScopeForTripKpiLog(driverSession.tenant_id)} company=${maskScopeForTripKpiLog(driverSession.company_id)} driver=${maskScopeForTripKpiLog(driverSession.driver_id)}`
    );
  }
  return { ok: true, auth_mode: "driver_session", driver_session: driverSession };
}
__name(requireDriverSessionOrAdminForScope, "requireDriverSessionOrAdminForScope");
function applyDriverSessionToBody(body, driverSession) {
  if (!driverSession) return body;
  const out = body && typeof body === "object" && !Array.isArray(body) ? { ...body } : {};
  out.tenant_id = driverSession.tenant_id;
  out.tenantId = driverSession.tenant_id;
  out.company_id = driverSession.company_id;
  out.companyId = driverSession.company_id;
  if (!safeStr22(out.driver_id, 96) && !safeStr22(out.driverId, 96)) {
    out.driver_id = driverSession.driver_id;
    out.driverId = driverSession.driver_id;
  }
  if (!safeStr22(out.actor_role, 32) && !safeStr22(out.actorRole, 32)) {
    out.actor_role = "driver";
  }
  if (!safeStr22(out.actor_driver_id, 96) && !safeStr22(out.actorDriverId, 96)) {
    out.actor_driver_id = driverSession.driver_id;
    out.actorDriverId = driverSession.driver_id;
  }
  return out;
}
__name(applyDriverSessionToBody, "applyDriverSessionToBody");
async function requireDriverOrCompanyOrAdminForScope(req, url, env, { body = null, routeLabel = "" } = {}) {
  const origin = getOrigin(req);
  if (hasValidAdminToken(req, url, env)) {
    if (routeLabel) console.log(`[${routeLabel}][AUTH] auth_mode=admin_token`);
    return { ok: true, auth_mode: "admin_token", driver_session: null, company_session: null };
  }
  const clientScope = extractScopeFromQueryAndBody(url, body);
  const companySession = await loadCompanySessionFromRequest(req, env);
  if (companySession) {
    if (clientScope?.tenant_id && clientScope.tenant_id !== companySession.tenant_id) {
      return {
        ok: false,
        response: withCors(json2({ ok: false, error: "forbidden" }, { status: 403 }), origin)
      };
    }
    if (clientScope?.company_id && clientScope.company_id !== companySession.company_id) {
      return {
        ok: false,
        response: withCors(json2({ ok: false, error: "forbidden" }, { status: 403 }), origin)
      };
    }
    if (routeLabel) {
      console.log(
        `[${routeLabel}][AUTH] auth_mode=company_session tenant=${maskScopeForTripKpiLog(companySession.tenant_id)} company=${maskScopeForTripKpiLog(companySession.company_id)}`
      );
    }
    return {
      ok: true,
      auth_mode: "company_session",
      driver_session: null,
      company_session: companySession
    };
  }
  const driverSession = await loadPublicDriverSessionFromRequest(req, env);
  if (driverSession) {
    if (clientScope?.tenant_id && clientScope.tenant_id !== driverSession.tenant_id) {
      return {
        ok: false,
        response: withCors(json2({ ok: false, error: "forbidden" }, { status: 403 }), origin)
      };
    }
    if (clientScope?.company_id && clientScope.company_id !== driverSession.company_id) {
      return {
        ok: false,
        response: withCors(json2({ ok: false, error: "forbidden" }, { status: 403 }), origin)
      };
    }
    const clientDriverId = _extractCallerSuppliedDriverId(req, url, body);
    if (clientDriverId && clientDriverId !== driverSession.driver_id) {
      return {
        ok: false,
        response: withCors(json2({ ok: false, error: "forbidden" }, { status: 403 }), origin)
      };
    }
    if (routeLabel) {
      console.log(
        `[${routeLabel}][AUTH] auth_mode=driver_session tenant=${maskScopeForTripKpiLog(driverSession.tenant_id)} company=${maskScopeForTripKpiLog(driverSession.company_id)} driver=${maskScopeForTripKpiLog(driverSession.driver_id)}`
      );
    }
    return {
      ok: true,
      auth_mode: "driver_session",
      driver_session: driverSession,
      company_session: null
    };
  }
  if (routeLabel) console.log(`[${routeLabel}][AUTH] auth_mode=none result=unauthorized`);
  return {
    ok: false,
    response: withCors(json2({ ok: false, error: "unauthorized" }, { status: 401 }), origin)
  };
}
__name(requireDriverOrCompanyOrAdminForScope, "requireDriverOrCompanyOrAdminForScope");
function _pickFinanceMonthCents(financeMonth, ...keys) {
  const obj = financeMonth && typeof financeMonth === "object" && !Array.isArray(financeMonth) ? financeMonth : {};
  for (const key2 of keys) {
    const n = Number(obj[key2]);
    if (Number.isFinite(n)) return Math.max(0, Math.round(n));
  }
  return null;
}
__name(_pickFinanceMonthCents, "_pickFinanceMonthCents");
async function requireAdminOrCompanySessionForScope(req, url, env, scope2, origin) {
  if (hasValidAdminToken(req, url, env)) {
    console.log("[TRIP_KPIS][AUTH] auth_mode=admin_token");
    return { ok: true, auth_mode: "admin_token" };
  }
  const companySession = await loadCompanySessionFromRequest(req, env);
  if (!companySession) {
    throw new Error("Unauthorized");
  }
  if (scope2.tenant_id !== companySession.tenant_id || scope2.company_id !== companySession.company_id) {
    return {
      ok: false,
      response: withCors(
        json2({ ok: false, error: "forbidden" }, { status: 403 }),
        origin
      )
    };
  }
  console.log(
    `[TRIP_KPIS][AUTH] auth_mode=company_session tenant=${maskScopeForTripKpiLog(companySession.tenant_id)} company=${maskScopeForTripKpiLog(companySession.company_id)}`
  );
  return { ok: true, auth_mode: "company_session" };
}
__name(requireAdminOrCompanySessionForScope, "requireAdminOrCompanySessionForScope");
async function resolveTripsHistoryAuth(req, url, env, scope2, origin) {
  const tenantMasked = maskScopeForTripKpiLog(scope2.tenant_id);
  const companyMasked = maskScopeForTripKpiLog(scope2.company_id);
  const requestedDriverId = safeStr22(url.searchParams.get("driver_id"), 96);
  if (hasValidAdminToken(req, url, env)) {
    console.log(
      `[TRIPS_HISTORY][AUTH] auth_mode=admin tenant=${tenantMasked} company=${companyMasked} driver=${requestedDriverId ? maskScopeForTripKpiLog(requestedDriverId) : "-"}`
    );
    return { ok: true, auth_mode: "admin", forced_driver_id: null };
  }
  const companySession = await loadCompanySessionFromRequest(req, env);
  if (companySession) {
    if (scope2.tenant_id !== companySession.tenant_id || scope2.company_id !== companySession.company_id) {
      return {
        ok: false,
        response: withCors(
          json2({ ok: false, error: "forbidden" }, { status: 403 }),
          origin
        )
      };
    }
    console.log(
      `[TRIPS_HISTORY][AUTH] auth_mode=company_session tenant=${tenantMasked} company=${companyMasked} driver=${requestedDriverId ? maskScopeForTripKpiLog(requestedDriverId) : "-"}`
    );
    return { ok: true, auth_mode: "company_session", forced_driver_id: null };
  }
  const driverSession = await loadPublicDriverSessionFromRequest(req, env);
  if (driverSession) {
    if (scope2.tenant_id !== driverSession.tenant_id || scope2.company_id !== driverSession.company_id) {
      return {
        ok: false,
        response: withCors(
          json2({ ok: false, error: "forbidden" }, { status: 403 }),
          origin
        )
      };
    }
    if (requestedDriverId && requestedDriverId !== driverSession.driver_id) {
      console.log(
        `[TRIPS_HISTORY][AUTH] auth_mode=driver_session tenant=${tenantMasked} company=${companyMasked} driver=${maskScopeForTripKpiLog(requestedDriverId)} result=forbidden_driver_mismatch`
      );
      return {
        ok: false,
        response: withCors(
          json2({ ok: false, error: "forbidden" }, { status: 403 }),
          origin
        )
      };
    }
    console.log(
      `[TRIPS_HISTORY][AUTH] auth_mode=driver_session tenant=${tenantMasked} company=${companyMasked} driver=${maskScopeForTripKpiLog(driverSession.driver_id)}`
    );
    return {
      ok: true,
      auth_mode: "driver_session",
      forced_driver_id: driverSession.driver_id
    };
  }
  throw new Error("Unauthorized");
}
__name(resolveTripsHistoryAuth, "resolveTripsHistoryAuth");
function requireMapbox(env) {
  const t = (env.MAPBOX_TOKEN || "").trim();
  if (!t) throw new Error("MAPBOX_TOKEN is not configured on the Worker (set as secret).");
  return t;
}
__name(requireMapbox, "requireMapbox");
async function readJson(req) {
  const ct = req.headers.get("content-type") || "";
  if (!ct.toLowerCase().includes("application/json")) {
    throw new Error("Expected application/json");
  }
  return await req.json();
}
__name(readJson, "readJson");
function nowIso() {
  return (/* @__PURE__ */ new Date()).toISOString();
}
__name(nowIso, "nowIso");
function safeNum(v, min, max) {
  const n = typeof v === "number" ? v : Number(v);
  if (!Number.isFinite(n)) return null;
  return Math.min(max, Math.max(min, n));
}
__name(safeNum, "safeNum");
function safeStr22(v, maxLen = 2e3) {
  if (typeof v !== "string") return null;
  const s = v.trim();
  if (!s) return null;
  return s.length > maxLen ? s.slice(0, maxLen) : s;
}
__name(safeStr22, "safeStr");
function sanitizeTripIdentityToken(value, maxLen = 96) {
  const raw = safeStr22(value, maxLen * 4);
  if (!raw) return null;
  const sanitized = raw.toLowerCase().replace(/[^a-z0-9_-]+/g, "_").replace(/_+/g, "_").replace(/^_+|_+$/g, "");
  if (!sanitized) return null;
  return sanitized.length > maxLen ? sanitized.slice(0, maxLen) : sanitized;
}
__name(sanitizeTripIdentityToken, "sanitizeTripIdentityToken");
function resolveTrackingActorFromRequest(request, url, body = null) {
  const search = url?.searchParams;
  const actor_role = (safeStr22(
    body?.actor_role ?? body?.actorRole ?? search?.get("actor_role") ?? search?.get("actorRole") ?? request?.headers?.get?.("x-fluxidi-actor-role"),
    32
  ) ?? "").toLowerCase();
  const actor_driver_id = safeStr22(
    body?.actor_driver_id ?? body?.actorDriverId ?? body?.driver_id ?? body?.driverId ?? body?.paid_by_driver_id ?? body?.paidByDriverId ?? search?.get("actor_driver_id") ?? search?.get("actorDriverId") ?? search?.get("driver_id") ?? search?.get("driverId") ?? request?.headers?.get?.("x-fluxidi-driver-id") ?? request?.headers?.get?.("x-driver-id"),
    96
  ) ?? null;
  const actor_vehicle_id = safeStr22(
    body?.actor_vehicle_id ?? body?.actorVehicleId ?? body?.vehicle_id ?? body?.vehicleId ?? search?.get("actor_vehicle_id") ?? search?.get("actorVehicleId") ?? search?.get("vehicle_id") ?? search?.get("vehicleId") ?? request?.headers?.get?.("x-fluxidi-vehicle-id") ?? request?.headers?.get?.("x-vehicle-id"),
    96
  ) ?? null;
  return { actor_role, actor_driver_id, actor_vehicle_id };
}
__name(resolveTrackingActorFromRequest, "resolveTrackingActorFromRequest");
function _trackingOwnershipError(error) {
  return { ok: false, error };
}
__name(_trackingOwnershipError, "_trackingOwnershipError");
function _trackingOwnershipValue(v, maxLen = 96) {
  return safeStr22(v, maxLen) ?? "";
}
__name(_trackingOwnershipValue, "_trackingOwnershipValue");
function _trackingOwnershipAllowed({
  actorDriverId,
  actorVehicleId,
  ownerDriverId,
  ownerVehicleId,
  fallbackDriverId = "",
  fallbackVehicleId = ""
}) {
  const actorDriver = _trackingOwnershipValue(actorDriverId);
  const actorVehicle = _trackingOwnershipValue(actorVehicleId);
  const ownerDriver = _trackingOwnershipValue(ownerDriverId);
  const ownerVehicle = _trackingOwnershipValue(ownerVehicleId);
  const tripDriver = _trackingOwnershipValue(fallbackDriverId);
  const tripVehicle = _trackingOwnershipValue(fallbackVehicleId);
  const candidateDriver = ownerDriver || tripDriver;
  const candidateVehicle = ownerVehicle || tripVehicle;
  if (!actorDriver && !actorVehicle) {
    return {
      allowed: false,
      certainMismatch: true,
      reason: "actor_identity_missing",
      candidateDriver,
      candidateVehicle
    };
  }
  if (candidateDriver && actorDriver) {
    if (candidateDriver === actorDriver) {
      return { allowed: true, certainMismatch: false, reason: "driver_match", candidateDriver, candidateVehicle };
    }
    return { allowed: false, certainMismatch: true, reason: "driver_mismatch", candidateDriver, candidateVehicle };
  }
  if (candidateVehicle && actorVehicle) {
    if (candidateVehicle === actorVehicle) {
      return { allowed: true, certainMismatch: false, reason: "vehicle_match", candidateDriver, candidateVehicle };
    }
    return { allowed: false, certainMismatch: true, reason: "vehicle_mismatch", candidateDriver, candidateVehicle };
  }
  if (!candidateDriver && !candidateVehicle) {
    return {
      allowed: true,
      certainMismatch: false,
      reason: "ownership_unknown_allow_compat",
      candidateDriver,
      candidateVehicle
    };
  }
  return {
    allowed: false,
    certainMismatch: false,
    reason: "insufficient_actor_fields",
    candidateDriver,
    candidateVehicle
  };
}
__name(_trackingOwnershipAllowed, "_trackingOwnershipAllowed");
function _logTrackingOwnershipCheck({
  target: target2,
  targetId,
  actor,
  ownerDriverId,
  ownerVehicleId,
  allowed: allowed2,
  reason
}) {
  console.log(
    `[TRACKING_OWNERSHIP][CHECK] target=${target2} id=${targetId} actor_role=${actor.actor_role || "-"} actor_driver=${actor.actor_driver_id || "-"} actor_vehicle=${actor.actor_vehicle_id || "-"} owner_driver=${ownerDriverId || "-"} owner_vehicle=${ownerVehicleId || "-"} allowed=${allowed2} reason=${reason || "-"}`
  );
}
__name(_logTrackingOwnershipCheck, "_logTrackingOwnershipCheck");
function _logTrackingOwnershipBlock({
  target: target2,
  targetId,
  actor,
  ownerDriverId,
  ownerVehicleId,
  error
}) {
  console.log(
    `[TRACKING_OWNERSHIP][BLOCK] target=${target2} id=${targetId} actor_role=${actor.actor_role || "-"} actor_driver=${actor.actor_driver_id || "-"} actor_vehicle=${actor.actor_vehicle_id || "-"} owner_driver=${ownerDriverId || "-"} owner_vehicle=${ownerVehicleId || "-"} error=${error}`
  );
}
__name(_logTrackingOwnershipBlock, "_logTrackingOwnershipBlock");
async function _driverVehicleOwnershipBestEffort(env, { tenant_id, company_id, driver_id, vehicle_id }) {
  const tenantId = _trackingOwnershipValue(tenant_id);
  const companyId = _trackingOwnershipValue(company_id);
  const driverId = _trackingOwnershipValue(driver_id);
  const vehicleId = _trackingOwnershipValue(vehicle_id);
  if (!tenantId || !driverId || !vehicleId) {
    return { allowed: false, certainMismatch: true, reason: "missing_driver_or_vehicle" };
  }
  const scopedKey = companyId ? scopedOwnerVehicleKey({ tenant_id: tenantId, company_id: companyId }, vehicleId) : null;
  const legacyKey = `owner_vehicle:${tenantId}:${vehicleId}`;
  const knownDriverId = _trackingOwnershipValue(
    (scopedKey ? await env.FLUXIDI_TRACKING.get(scopedKey) : null) ?? await env.FLUXIDI_TRACKING.get(legacyKey)
  );
  if (!knownDriverId) {
    return { allowed: true, certainMismatch: false, reason: "no_vehicle_owner_known" };
  }
  if (knownDriverId === driverId) {
    return { allowed: true, certainMismatch: false, reason: "vehicle_owner_match" };
  }
  return { allowed: false, certainMismatch: true, reason: "vehicle_owner_mismatch" };
}
__name(_driverVehicleOwnershipBestEffort, "_driverVehicleOwnershipBestEffort");
async function _rememberVehicleOwnerBestEffort(env, { tenant_id, company_id, driver_id, vehicle_id }) {
  const tenantId = _trackingOwnershipValue(tenant_id);
  const companyId = _trackingOwnershipValue(company_id);
  const driverId = _trackingOwnershipValue(driver_id);
  const vehicleId = _trackingOwnershipValue(vehicle_id);
  if (!tenantId || !driverId || !vehicleId) return;
  const mapKey = companyId ? scopedOwnerVehicleKey({ tenant_id: tenantId, company_id: companyId }, vehicleId) : `owner_vehicle:${tenantId}:${vehicleId}`;
  await env.FLUXIDI_TRACKING.put(mapKey, driverId, { expirationTtl: TTL_TRIP });
}
__name(_rememberVehicleOwnerBestEffort, "_rememberVehicleOwnerBestEffort");
async function _assertTripOwnedByActorOrBlock({
  trip,
  trip_id,
  actor,
  error,
  origin
}) {
  if (actor.actor_role !== "driver") return null;
  const ownerDriverId = _trackingOwnershipValue(trip?.owner_driver_id ?? trip?.driver_id);
  const ownerVehicleId = _trackingOwnershipValue(trip?.owner_vehicle_id ?? trip?.vehicle_id);
  const check = _trackingOwnershipAllowed({
    actorDriverId: actor.actor_driver_id,
    actorVehicleId: actor.actor_vehicle_id,
    ownerDriverId,
    ownerVehicleId,
    fallbackDriverId: _trackingOwnershipValue(trip?.driver_id),
    fallbackVehicleId: _trackingOwnershipValue(trip?.vehicle_id)
  });
  _logTrackingOwnershipCheck({
    target: "trip",
    targetId: _trackingOwnershipValue(trip_id) || "unknown",
    actor,
    ownerDriverId: check.candidateDriver,
    ownerVehicleId: check.candidateVehicle,
    allowed: check.allowed,
    reason: check.reason
  });
  if (check.allowed) return null;
  if (!check.certainMismatch) return null;
  _logTrackingOwnershipBlock({
    target: "trip",
    targetId: _trackingOwnershipValue(trip_id) || "unknown",
    actor,
    ownerDriverId: check.candidateDriver,
    ownerVehicleId: check.candidateVehicle,
    error
  });
  return withCors(json2(_trackingOwnershipError(error), { status: 403 }), origin);
}
__name(_assertTripOwnedByActorOrBlock, "_assertTripOwnedByActorOrBlock");
async function _assertSessionOwnedByActorOrBlock({
  session,
  session_id,
  actor,
  error,
  origin
}) {
  if (actor.actor_role !== "driver") return null;
  const ownerDriverId = _trackingOwnershipValue(session?.owner_driver_id ?? session?.driver_id);
  const ownerVehicleId = _trackingOwnershipValue(session?.owner_vehicle_id ?? session?.vehicle_id);
  const check = _trackingOwnershipAllowed({
    actorDriverId: actor.actor_driver_id,
    actorVehicleId: actor.actor_vehicle_id,
    ownerDriverId,
    ownerVehicleId,
    fallbackDriverId: _trackingOwnershipValue(session?.driver_id),
    fallbackVehicleId: _trackingOwnershipValue(session?.vehicle_id)
  });
  _logTrackingOwnershipCheck({
    target: "session",
    targetId: _trackingOwnershipValue(session_id) || "unknown",
    actor,
    ownerDriverId: check.candidateDriver,
    ownerVehicleId: check.candidateVehicle,
    allowed: check.allowed,
    reason: check.reason
  });
  if (check.allowed) return null;
  if (!check.certainMismatch) return null;
  _logTrackingOwnershipBlock({
    target: "session",
    targetId: _trackingOwnershipValue(session_id) || "unknown",
    actor,
    ownerDriverId: check.candidateDriver,
    ownerVehicleId: check.candidateVehicle,
    error
  });
  return withCors(json2(_trackingOwnershipError(error), { status: 403 }), origin);
}
__name(_assertSessionOwnedByActorOrBlock, "_assertSessionOwnedByActorOrBlock");
var COMPLIANCE_APPEND_PATH = "/compliance/events/append";
function safeKeyPart(value, maxLen = 128) {
  const raw = safeStr22(value, maxLen);
  if (!raw) return null;
  const normalized2 = raw.replace(/[:\r\n\t]/g, "_").trim();
  return normalized2 || null;
}
__name(safeKeyPart, "safeKeyPart");
function normalizeTenantCompanyScope(input = {}) {
  const tenant_id = safeStr22(input.tenant_id ?? input.tenantId, 96) ?? null;
  const company_id = safeStr22(input.company_id ?? input.companyId, 96) ?? null;
  if (!tenant_id && !company_id) return null;
  return { tenant_id, company_id };
}
__name(normalizeTenantCompanyScope, "normalizeTenantCompanyScope");
function extractScopeFromQueryAndBody(url, body = null) {
  const search = url?.searchParams;
  return normalizeTenantCompanyScope({
    tenant_id: body?.tenant_id ?? body?.tenantId ?? search?.get("tenant_id") ?? search?.get("tenantId"),
    company_id: body?.company_id ?? body?.companyId ?? search?.get("company_id") ?? search?.get("companyId")
  });
}
__name(extractScopeFromQueryAndBody, "extractScopeFromQueryAndBody");
function extractScopeFromRecord(record) {
  return normalizeTenantCompanyScope({
    tenant_id: record?.tenant_id ?? record?.tenantId ?? record?.owner_tenant_id ?? record?.ownerTenantId,
    company_id: record?.company_id ?? record?.companyId ?? record?.owner_company_id ?? record?.ownerCompanyId
  });
}
__name(extractScopeFromRecord, "extractScopeFromRecord");
function missingScopeResponse(origin, message = "tenant_id and company_id are required") {
  return withCors(json2({ ok: false, error: message }, { status: 400 }), origin ?? "*");
}
__name(missingScopeResponse, "missingScopeResponse");
function parseRequiredTenantCompanyScope(request, url, body = null, options = {}) {
  const sourceScope = extractScopeFromQueryAndBody(url, body);
  const tenant_id = sourceScope?.tenant_id ?? null;
  const company_id = sourceScope?.company_id ?? null;
  const hasAnyScope = Boolean(tenant_id || company_id);
  if (!tenant_id || !company_id) {
    const message = hasAnyScope ? "tenant_id and company_id must both be provided" : "tenant_id and company_id are required";
    if (options.returnResponse === true) {
      return missingScopeResponse(options.origin, message);
    }
    throw new Error(message);
  }
  return { tenant_id, company_id };
}
__name(parseRequiredTenantCompanyScope, "parseRequiredTenantCompanyScope");
function recordMatchesTenantCompanyScope(record, scope2, options = {}) {
  const recordScope = extractScopeFromRecord(record);
  const targetScope = normalizeTenantCompanyScope(scope2);
  if (!recordScope || !targetScope || !targetScope.tenant_id || !targetScope.company_id) {
    return false;
  }
  if (!recordScope.tenant_id) return false;
  if (recordScope.tenant_id !== targetScope.tenant_id) return false;
  if (!recordScope.company_id) {
    return options.allowLegacyCompanyless === true;
  }
  return recordScope.company_id === targetScope.company_id;
}
__name(recordMatchesTenantCompanyScope, "recordMatchesTenantCompanyScope");
function normalizeScopedKeyScope(scope2) {
  const normalized2 = normalizeTenantCompanyScope(scope2);
  const tenantPart = safeKeyPart(normalized2?.tenant_id, 96);
  const companyPart = safeKeyPart(normalized2?.company_id, 96);
  if (!tenantPart || !companyPart) {
    throw new Error("tenant_id and company_id are required");
  }
  return { tenant_id: tenantPart, company_id: companyPart };
}
__name(normalizeScopedKeyScope, "normalizeScopedKeyScope");
function scopedBookingIndexKey(scope2) {
  const normalizedScope = normalizeScopedKeyScope(scope2);
  return `tenant:${normalizedScope.tenant_id}:company:${normalizedScope.company_id}:booking_index`;
}
__name(scopedBookingIndexKey, "scopedBookingIndexKey");
function scopedBookingSessionKey(scope2, bookingId) {
  const normalizedScope = normalizeScopedKeyScope(scope2);
  const bookingPart = safeKeyPart(bookingId, 128);
  if (!bookingPart) throw new Error("booking_id is required");
  return `tenant:${normalizedScope.tenant_id}:company:${normalizedScope.company_id}:booking:${bookingPart}:session`;
}
__name(scopedBookingSessionKey, "scopedBookingSessionKey");
function scopedSessionKey(scope2, sessionId) {
  const normalizedScope = normalizeScopedKeyScope(scope2);
  const sessionPart = safeKeyPart(sessionId, 128);
  if (!sessionPart) throw new Error("session_id is required");
  return `tenant:${normalizedScope.tenant_id}:company:${normalizedScope.company_id}:session:${sessionPart}`;
}
__name(scopedSessionKey, "scopedSessionKey");
function scopedPingLastKey(scope2, sessionId) {
  const normalizedScope = normalizeScopedKeyScope(scope2);
  const sessionPart = safeKeyPart(sessionId, 128);
  if (!sessionPart) throw new Error("session_id is required");
  return `tenant:${normalizedScope.tenant_id}:company:${normalizedScope.company_id}:ping:${sessionPart}:last`;
}
__name(scopedPingLastKey, "scopedPingLastKey");
function scopedPublicBookingKey(scope2, token) {
  const normalizedScope = normalizeScopedKeyScope(scope2);
  const tokenPart = safeKeyPart(token, 128);
  if (!tokenPart) throw new Error("public token is required");
  return `tenant:${normalizedScope.tenant_id}:company:${normalizedScope.company_id}:public:${tokenPart}:booking`;
}
__name(scopedPublicBookingKey, "scopedPublicBookingKey");
function scopedTripKey(scope2, tripId) {
  const normalizedScope = normalizeScopedKeyScope(scope2);
  const tripPart = safeKeyPart(tripId, 160);
  if (!tripPart) throw new Error("trip_id is required");
  return `tenant:${normalizedScope.tenant_id}:company:${normalizedScope.company_id}:trip:${tripPart}`;
}
__name(scopedTripKey, "scopedTripKey");
function scopedTripsIndexKey(scope2) {
  const normalizedScope = normalizeScopedKeyScope(scope2);
  return `tenant:${normalizedScope.tenant_id}:company:${normalizedScope.company_id}:trips_index`;
}
__name(scopedTripsIndexKey, "scopedTripsIndexKey");
function scopedTripsDriverIndexKey(scope2, driverId) {
  const normalizedScope = normalizeScopedKeyScope(scope2);
  const driverPart = safeKeyPart(driverId, 96);
  if (!driverPart) throw new Error("driver_id is required");
  return `tenant:${normalizedScope.tenant_id}:company:${normalizedScope.company_id}:trips_index:driver:${driverPart}`;
}
__name(scopedTripsDriverIndexKey, "scopedTripsDriverIndexKey");
function scopedOwnerVehicleKey(scope2, vehicleId) {
  const normalizedScope = normalizeScopedKeyScope(scope2);
  const vehiclePart = safeKeyPart(vehicleId, 96);
  if (!vehiclePart) throw new Error("vehicle_id is required");
  return `owner_vehicle:${normalizedScope.tenant_id}:${normalizedScope.company_id}:${vehiclePart}`;
}
__name(scopedOwnerVehicleKey, "scopedOwnerVehicleKey");
function applyCanonicalScopeToRecord(record, scope2) {
  const normalizedScope = normalizeScopedKeyScope(scope2);
  record.tenant_id = normalizedScope.tenant_id;
  record.company_id = normalizedScope.company_id;
  record.tenantId = normalizedScope.tenant_id;
  record.companyId = normalizedScope.company_id;
  return record;
}
__name(applyCanonicalScopeToRecord, "applyCanonicalScopeToRecord");
function scopedDashboardTripKpisKey(scope2) {
  const normalizedScope = normalizeScopedKeyScope(scope2);
  return `tenant:${normalizedScope.tenant_id}:company:${normalizedScope.company_id}:dashboard:trip_kpis:v1`;
}
__name(scopedDashboardTripKpisKey, "scopedDashboardTripKpisKey");
function scopedDashboardTripMonthKpisKey(scope2, month) {
  const normalizedScope = normalizeScopedKeyScope(scope2);
  return `tenant:${normalizedScope.tenant_id}:company:${normalizedScope.company_id}:dashboard:trip_kpis:month:${month}:v1`;
}
__name(scopedDashboardTripMonthKpisKey, "scopedDashboardTripMonthKpisKey");
function scopedDashboardTripContribKey(scope2, tripId) {
  const normalizedScope = normalizeScopedKeyScope(scope2);
  const tripPart = safeKeyPart(tripId, 160);
  if (!tripPart) throw new Error("trip_id is required");
  return `tenant:${normalizedScope.tenant_id}:company:${normalizedScope.company_id}:dashboard:trip_kpi_contrib:${tripPart}:v1`;
}
__name(scopedDashboardTripContribKey, "scopedDashboardTripContribKey");
function scopedDashboardTripPendingBookingKey(scope2, bookingId) {
  const normalizedScope = normalizeScopedKeyScope(scope2);
  const bookingPart = safeKeyPart(bookingId, 160);
  if (!bookingPart) throw new Error("booking_id is required");
  return `tenant:${normalizedScope.tenant_id}:company:${normalizedScope.company_id}:dashboard:trip_kpi_pending_booking:${bookingPart}:v1`;
}
__name(scopedDashboardTripPendingBookingKey, "scopedDashboardTripPendingBookingKey");
function scopedDashboardTripPendingBookingPrefix(scope2) {
  const normalizedScope = normalizeScopedKeyScope(scope2);
  return `tenant:${normalizedScope.tenant_id}:company:${normalizedScope.company_id}:dashboard:trip_kpi_pending_booking:`;
}
__name(scopedDashboardTripPendingBookingPrefix, "scopedDashboardTripPendingBookingPrefix");
function scopedDashboardTripDebugKey(scope2) {
  const normalizedScope = normalizeScopedKeyScope(scope2);
  return `tenant:${normalizedScope.tenant_id}:company:${normalizedScope.company_id}:dashboard:trip_kpi_debug:v1`;
}
__name(scopedDashboardTripDebugKey, "scopedDashboardTripDebugKey");
function scopedDashboardBookingFinanceMonthKey(scope2, month) {
  const normalizedScope = normalizeScopedKeyScope(scope2);
  const monthPart = safeKeyPart(month, 16);
  if (!monthPart) throw new Error("month is required");
  return `tenant:${normalizedScope.tenant_id}:company:${normalizedScope.company_id}:dashboard:booking_finance:month:${monthPart}:v1`;
}
__name(scopedDashboardBookingFinanceMonthKey, "scopedDashboardBookingFinanceMonthKey");
function scopedDashboardKpiDiagnosticsCacheKey(scope2) {
  const normalizedScope = normalizeScopedKeyScope(scope2);
  return `tenant:${normalizedScope.tenant_id}:company:${normalizedScope.company_id}:dashboard:trip_kpi_diagnostics_cache:v1`;
}
__name(scopedDashboardKpiDiagnosticsCacheKey, "scopedDashboardKpiDiagnosticsCacheKey");
function scopedDashboardTripKpisMonthPrefix(scope2) {
  const normalizedScope = normalizeScopedKeyScope(scope2);
  return `tenant:${normalizedScope.tenant_id}:company:${normalizedScope.company_id}:dashboard:trip_kpis:month:`;
}
__name(scopedDashboardTripKpisMonthPrefix, "scopedDashboardTripKpisMonthPrefix");
function scopedDashboardTripKpiContribPrefix(scope2) {
  const normalizedScope = normalizeScopedKeyScope(scope2);
  return `tenant:${normalizedScope.tenant_id}:company:${normalizedScope.company_id}:dashboard:trip_kpi_contrib:`;
}
__name(scopedDashboardTripKpiContribPrefix, "scopedDashboardTripKpiContribPrefix");
function scopedDashboardBookingFinanceMonthPrefix(scope2) {
  const normalizedScope = normalizeScopedKeyScope(scope2);
  return `tenant:${normalizedScope.tenant_id}:company:${normalizedScope.company_id}:dashboard:booking_finance:month:`;
}
__name(scopedDashboardBookingFinanceMonthPrefix, "scopedDashboardBookingFinanceMonthPrefix");
function scopedDashboardBookingFinanceContribPrefix(scope2) {
  const normalizedScope = normalizeScopedKeyScope(scope2);
  return `tenant:${normalizedScope.tenant_id}:company:${normalizedScope.company_id}:dashboard:booking_finance_contrib:`;
}
__name(scopedDashboardBookingFinanceContribPrefix, "scopedDashboardBookingFinanceContribPrefix");
function scopedTripRecordsPrefix(scope2) {
  const normalizedScope = normalizeScopedKeyScope(scope2);
  return `tenant:${normalizedScope.tenant_id}:company:${normalizedScope.company_id}:trip:`;
}
__name(scopedTripRecordsPrefix, "scopedTripRecordsPrefix");
function allowDevResetEndpoints(env) {
  return String(env?.ALLOW_DEV_RESET_ENDPOINTS || "").trim().toLowerCase() === "true";
}
__name(allowDevResetEndpoints, "allowDevResetEndpoints");
function allowDevResetExecute(env) {
  return String(env?.ALLOW_DEV_RESET || "").trim().toLowerCase() === "true";
}
__name(allowDevResetExecute, "allowDevResetExecute");
function _coerceBoolean(value, fallback = false) {
  if (value == null) return fallback;
  const token = (safeStr22(value, 16) ?? "").toLowerCase();
  if (!token) return fallback;
  if (token === "0" || token === "false" || token === "no") return false;
  if (token === "1" || token === "true" || token === "yes") return true;
  return fallback;
}
__name(_coerceBoolean, "_coerceBoolean");
function _isUnsafeDevResetScope(tenantId, companyId) {
  const tenant = String(tenantId || "").trim().toLowerCase();
  const company2 = String(companyId || "").trim().toLowerCase();
  return tenant === "fluxidi" || company2 === "fluxidi";
}
__name(_isUnsafeDevResetScope, "_isUnsafeDevResetScope");
function normalizeDashboardTripLifecycleStatus(value) {
  const raw = safeStr22(value, 64);
  if (!raw) return "unknown";
  const s = raw.toLowerCase().replaceAll("-", "_").replaceAll(" ", "_");
  if (s === "stopped" || s === "completed" || s === "complete" || s === "closed" || s === "done" || s === "finished" || s === "finalized" || s === "finalised") {
    return "completed";
  }
  if (s === "cancelled" || s === "canceled" || s === "deleted" || s === "failed" || s === "expired" || s === "declined") {
    return "cancelled";
  }
  if (s === "active" || s === "running" || s === "pending" || s === "open") {
    return "active";
  }
  return "unknown";
}
__name(normalizeDashboardTripLifecycleStatus, "normalizeDashboardTripLifecycleStatus");
function dashboardTripStatusIsCompleted(value) {
  return normalizeDashboardTripLifecycleStatus(value) === "completed";
}
__name(dashboardTripStatusIsCompleted, "dashboardTripStatusIsCompleted");
function dashboardPaymentIsPaid(value) {
  return normalizeCompliancePaymentStatus2(value) === "paid";
}
__name(dashboardPaymentIsPaid, "dashboardPaymentIsPaid");
function _dashboardTripMonthFromIso(value) {
  const text22 = safeStr22(value, 64);
  if (!text22) return null;
  const ts = Date.parse(text22);
  if (!Number.isFinite(ts)) return null;
  return new Date(ts).toISOString().slice(0, 7);
}
__name(_dashboardTripMonthFromIso, "_dashboardTripMonthFromIso");
function _normalizeDashboardMonth(value) {
  const text22 = safeStr22(value, 16);
  if (!text22) return null;
  const m = text22.match(/^(\d{4})-(\d{2})$/);
  if (!m) return null;
  const mm = Number(m[2]);
  if (!Number.isFinite(mm) || mm < 1 || mm > 12) return null;
  return `${m[1]}-${m[2]}`;
}
__name(_normalizeDashboardMonth, "_normalizeDashboardMonth");
function _dashboardTripAmountCents(value) {
  const n = Number(value);
  if (!Number.isFinite(n)) return null;
  return Math.round(n * 100);
}
__name(_dashboardTripAmountCents, "_dashboardTripAmountCents");
function deriveDashboardTripKpiContribution(trip) {
  const tripId = safeStr22(trip?.trip_id ?? trip?.tripId, 160);
  if (!tripId) return null;
  const completed = dashboardTripStatusIsCompleted(trip?.status ?? trip?.lifecycle_status);
  const paid = dashboardPaymentIsPaid(trip?.payment_status ?? trip?.paymentStatus);
  const paidAtMonth = _dashboardTripMonthFromIso(trip?.paid_at ?? trip?.paidAt);
  const paidFallbackMonth = paid && !paidAtMonth ? _dashboardTripMonthFromIso(
    trip?.stopped_at ?? trip?.stoppedAt ?? trip?.ended_at ?? trip?.endedAt ?? trip?.completed_at ?? trip?.completedAt
  ) ?? null : null;
  const paidMonth = paidAtMonth ?? paidFallbackMonth;
  const amountCents = _dashboardTripAmountCents(trip?.payment_amount) ?? _dashboardTripAmountCents(trip?.paymentAmount) ?? _dashboardTripAmountCents(trip?.final_amount) ?? _dashboardTripAmountCents(trip?.finalAmount) ?? _dashboardTripAmountCents(trip?.final_total) ?? _dashboardTripAmountCents(trip?.finalTotal) ?? _dashboardTripAmountCents(trip?.total_eur) ?? _dashboardTripAmountCents(trip?.totalEur) ?? 0;
  const monthlyPaid = completed && paid && !!paidMonth;
  const missingAmount = monthlyPaid && amountCents <= 0;
  return {
    trip_id: tripId,
    completed_rides_count: completed ? 1 : 0,
    unpaid_completed_rides_count: completed && !paid ? 1 : 0,
    paid_month: monthlyPaid ? paidMonth : null,
    monthly_paid_rides_count: monthlyPaid ? 1 : 0,
    monthly_income_cents: monthlyPaid ? amountCents : 0,
    monthly_missing_amount_count: missingAmount ? 1 : 0
  };
}
__name(deriveDashboardTripKpiContribution, "deriveDashboardTripKpiContribution");
function _readDashboardContribShape(value, fallbackTripId = null) {
  const obj = value && typeof value === "object" && !Array.isArray(value) ? value : {};
  const tripId = safeStr22(obj.trip_id ?? fallbackTripId, 160) || null;
  const completed = Number(obj.completed_rides_count) === 1 ? 1 : 0;
  const unpaid = Number(obj.unpaid_completed_rides_count) === 1 ? 1 : 0;
  const paidMonth = _normalizeDashboardMonth(obj.paid_month);
  const monthlyPaidCount = Number(obj.monthly_paid_rides_count) === 1 ? 1 : 0;
  const monthlyIncomeCents = Number.isFinite(Number(obj.monthly_income_cents)) ? Math.round(Number(obj.monthly_income_cents)) : 0;
  const monthlyMissingAmountCount = Number.isFinite(Number(obj.monthly_missing_amount_count)) ? Math.max(0, Math.round(Number(obj.monthly_missing_amount_count))) : 0;
  return {
    trip_id: tripId,
    completed_rides_count: completed,
    unpaid_completed_rides_count: unpaid,
    paid_month: paidMonth,
    monthly_paid_rides_count: monthlyPaidCount,
    monthly_income_cents: monthlyIncomeCents,
    monthly_missing_amount_count: monthlyMissingAmountCount
  };
}
__name(_readDashboardContribShape, "_readDashboardContribShape");
async function _applyPendingBookingPaymentToTripBestEffort(env, scope2, trip) {
  try {
    if (!env?.FLUXIDI_TRACKING || !trip || typeof trip !== "object") return trip;
    const bookingIdCandidates = [
      safeStr22(trip?.booking_id ?? trip?.bookingId, 160),
      safeStr22(trip?.booking?.booking_id ?? trip?.booking?.bookingId, 160),
      safeStr22(trip?.public_booking_reference ?? trip?.publicBookingReference, 160)
    ].filter((value) => !!value);
    if (!bookingIdCandidates.length) return trip;
    let marker = null;
    let markerKey = "";
    for (const bookingId of bookingIdCandidates) {
      const candidateKey = scopedDashboardTripPendingBookingKey(scope2, bookingId);
      const candidateMarker = await kvGetJson(env.FLUXIDI_TRACKING, candidateKey);
      if (candidateMarker && typeof candidateMarker === "object" && !Array.isArray(candidateMarker)) {
        marker = candidateMarker;
        markerKey = candidateKey;
        break;
      }
    }
    if (!marker || typeof marker !== "object" || Array.isArray(marker)) return trip;
    const markerPayment = normalizeCompliancePaymentStatus2(marker?.payment_status);
    if (markerPayment === "paid") {
      trip.payment_status = "paid";
      trip.paymentStatus = "paid";
      const paidAt = safeStr22(marker?.paid_at, 64);
      if (paidAt) {
        trip.paid_at = paidAt;
        trip.paidAt = paidAt;
      }
      const amountCents = Number(marker?.payment_amount_cents);
      if (Number.isFinite(amountCents)) {
        const amount = Math.round(amountCents) / 100;
        trip.payment_amount = amount;
        trip.paymentAmount = amount;
      }
      const currency = safeStr22(marker?.currency, 8).toUpperCase();
      if (currency) trip.currency = currency;
      const details = trip.booking_details && typeof trip.booking_details === "object" && !Array.isArray(trip.booking_details) ? trip.booking_details : {};
      details.payment_status = "paid";
      details.paymentStatus = "paid";
      if (paidAt) {
        details.paid_at = paidAt;
        details.paidAt = paidAt;
      }
      if (Number.isFinite(amountCents)) {
        details.payment_amount = Math.round(amountCents) / 100;
        details.paymentAmount = Math.round(amountCents) / 100;
      }
      trip.booking_details = details;
    }
    if (markerKey) {
      await kvDel(env.FLUXIDI_TRACKING, markerKey);
    }
    return trip;
  } catch (_) {
    return trip;
  }
}
__name(_applyPendingBookingPaymentToTripBestEffort, "_applyPendingBookingPaymentToTripBestEffort");
async function materializeTripDashboardKpisBestEffort(env, scope2, trip, sourceTag = "unknown") {
  try {
    if (!env?.FLUXIDI_TRACKING) return;
    trip = await _applyPendingBookingPaymentToTripBestEffort(env, scope2, trip);
    const nextRaw = deriveDashboardTripKpiContribution(trip);
    if (!nextRaw?.trip_id) return;
    const normalizedScope = normalizeScopedKeyScope(scope2);
    const tripKpisKey = scopedDashboardTripKpisKey(normalizedScope);
    const contribKey = scopedDashboardTripContribKey(normalizedScope, nextRaw.trip_id);
    const next = _readDashboardContribShape(nextRaw, nextRaw.trip_id);
    const prev = _readDashboardContribShape(
      await kvGetJson(env.FLUXIDI_TRACKING, contribKey),
      next.trip_id
    );
    const globalCurrent = await kvGetJson(env.FLUXIDI_TRACKING, tripKpisKey) ?? {};
    const currentCompleted = Number.isFinite(Number(globalCurrent.completed_rides_count)) ? Math.round(Number(globalCurrent.completed_rides_count)) : 0;
    const currentUnpaid = Number.isFinite(
      Number(globalCurrent.unpaid_completed_rides_count)
    ) ? Math.round(Number(globalCurrent.unpaid_completed_rides_count)) : 0;
    const nextCompleted = currentCompleted + (next.completed_rides_count - prev.completed_rides_count);
    const nextUnpaid = currentUnpaid + (next.unpaid_completed_rides_count - prev.unpaid_completed_rides_count);
    await kvPutJson(
      env.FLUXIDI_TRACKING,
      tripKpisKey,
      {
        completed_rides_count: Math.max(0, nextCompleted),
        unpaid_completed_rides_count: Math.max(0, nextUnpaid),
        updated_at: nowIso()
      }
    );
    const monthDeltas = {};
    if (prev.paid_month && prev.monthly_paid_rides_count > 0) {
      monthDeltas[prev.paid_month] = monthDeltas[prev.paid_month] || {
        monthly_paid_rides_count: 0,
        monthly_income_cents: 0,
        monthly_missing_amount_count: 0
      };
      monthDeltas[prev.paid_month].monthly_paid_rides_count -= prev.monthly_paid_rides_count;
      monthDeltas[prev.paid_month].monthly_income_cents -= prev.monthly_income_cents;
      monthDeltas[prev.paid_month].monthly_missing_amount_count -= prev.monthly_missing_amount_count;
    }
    if (next.paid_month && next.monthly_paid_rides_count > 0) {
      monthDeltas[next.paid_month] = monthDeltas[next.paid_month] || {
        monthly_paid_rides_count: 0,
        monthly_income_cents: 0,
        monthly_missing_amount_count: 0
      };
      monthDeltas[next.paid_month].monthly_paid_rides_count += next.monthly_paid_rides_count;
      monthDeltas[next.paid_month].monthly_income_cents += next.monthly_income_cents;
      monthDeltas[next.paid_month].monthly_missing_amount_count += next.monthly_missing_amount_count;
    }
    for (const [month, delta] of Object.entries(monthDeltas)) {
      if (!delta || !delta.monthly_paid_rides_count && !delta.monthly_income_cents && !delta.monthly_missing_amount_count) {
        continue;
      }
      const monthKey = scopedDashboardTripMonthKpisKey(normalizedScope, month);
      const current = await kvGetJson(env.FLUXIDI_TRACKING, monthKey) ?? {};
      const currentCount = Number.isFinite(Number(current.monthly_paid_rides_count)) ? Math.round(Number(current.monthly_paid_rides_count)) : 0;
      const currentIncome = Number.isFinite(Number(current.monthly_income_cents)) ? Math.round(Number(current.monthly_income_cents)) : 0;
      const currentMissingAmountCount = Number.isFinite(Number(current.monthly_missing_amount_count)) ? Math.round(Number(current.monthly_missing_amount_count)) : 0;
      await kvPutJson(
        env.FLUXIDI_TRACKING,
        monthKey,
        {
          month,
          currency: "EUR",
          monthly_paid_rides_count: Math.max(
            0,
            currentCount + delta.monthly_paid_rides_count
          ),
          monthly_income_cents: Math.max(
            0,
            currentIncome + delta.monthly_income_cents
          ),
          monthly_missing_amount_count: Math.max(
            0,
            currentMissingAmountCount + delta.monthly_missing_amount_count
          ),
          updated_at: nowIso()
        }
      );
    }
    await kvPutJson(
      env.FLUXIDI_TRACKING,
      contribKey,
      { ...next, updated_at: nowIso(), source: sourceTag }
    );
  } catch (err) {
    console.log(
      `[DASHBOARD_KPI][WARN] source=${sourceTag} reason=${safeStr22(
        err?.message || err,
        200
      ) || "unknown"}`
    );
  }
}
__name(materializeTripDashboardKpisBestEffort, "materializeTripDashboardKpisBestEffort");
async function getScopedOrLegacySessionForScope(env, scope2, sessionId) {
  const scopedKey = scopedSessionKey(scope2, sessionId);
  const scopedSession = await kvGetJson(env.FLUXIDI_TRACKING, scopedKey);
  if (scopedSession) {
    if (!recordMatchesTenantCompanyScope(scopedSession, scope2)) {
      return { session: null, key: scopedKey, source: "scoped_mismatch" };
    }
    return { session: scopedSession, key: scopedKey, source: "scoped" };
  }
  const legacyKey = `session:${sessionId}`;
  const legacySession = await kvGetJson(env.FLUXIDI_TRACKING, legacyKey);
  if (!legacySession) return { session: null, key: scopedKey, source: "missing" };
  if (!recordMatchesTenantCompanyScope(legacySession, scope2)) {
    return { session: null, key: scopedKey, source: "legacy_mismatch" };
  }
  const migrated = applyCanonicalScopeToRecord(legacySession, scope2);
  await kvPutJson(env.FLUXIDI_TRACKING, scopedKey, migrated, TTL_SESSION);
  return { session: migrated, key: scopedKey, source: "legacy_copied" };
}
__name(getScopedOrLegacySessionForScope, "getScopedOrLegacySessionForScope");
async function getScopedOrLegacyTripForScope(env, scope2, tripId) {
  const scopedKey = scopedTripKey(scope2, tripId);
  const scopedTrip = await kvGetJson(env.FLUXIDI_TRACKING, scopedKey);
  if (scopedTrip) {
    if (!recordMatchesTenantCompanyScope(scopedTrip, scope2)) {
      return { trip: null, key: scopedKey, source: "scoped_mismatch" };
    }
    return { trip: scopedTrip, key: scopedKey, source: "scoped" };
  }
  const legacyKey = tripKey(tripId);
  const legacyTrip = await kvGetJson(env.FLUXIDI_TRACKING, legacyKey);
  if (!legacyTrip) return { trip: null, key: scopedKey, source: "missing" };
  if (!recordMatchesTenantCompanyScope(legacyTrip, scope2)) {
    return { trip: null, key: scopedKey, source: "legacy_mismatch" };
  }
  const migrated = applyCanonicalScopeToRecord(legacyTrip, scope2);
  await kvPutJson(env.FLUXIDI_TRACKING, scopedKey, migrated, TTL_TRIP);
  return { trip: migrated, key: scopedKey, source: "legacy_copied" };
}
__name(getScopedOrLegacyTripForScope, "getScopedOrLegacyTripForScope");
async function getScopedOrLegacyBookingMapForScope(env, scope2, bookingId) {
  const scopedKey = scopedBookingSessionKey(scope2, bookingId);
  const scopedMap = await kvGetJson(env.FLUXIDI_TRACKING, scopedKey);
  if (scopedMap) {
    if (!recordMatchesTenantCompanyScope(scopedMap, scope2)) {
      return { map: null, key: scopedKey, source: "scoped_mismatch" };
    }
    return { map: scopedMap, key: scopedKey, source: "scoped" };
  }
  const legacyKey = `booking:${bookingId}:session`;
  const legacyMap = await kvGetJson(env.FLUXIDI_TRACKING, legacyKey);
  if (!legacyMap) return { map: null, key: scopedKey, source: "missing" };
  if (!recordMatchesTenantCompanyScope(legacyMap, scope2)) {
    return { map: null, key: scopedKey, source: "legacy_mismatch" };
  }
  const migrated = applyCanonicalScopeToRecord(legacyMap, scope2);
  await kvPutJson(env.FLUXIDI_TRACKING, scopedKey, migrated, TTL_SESSION);
  return { map: migrated, key: scopedKey, source: "legacy_copied" };
}
__name(getScopedOrLegacyBookingMapForScope, "getScopedOrLegacyBookingMapForScope");
function normalizeComplianceText(v, fallback = "unknown", maxLen = 64) {
  const text22 = safeStr22(v, maxLen);
  if (!text22) return fallback;
  return text22.toLowerCase();
}
__name(normalizeComplianceText, "normalizeComplianceText");
function isUnknownLikeComplianceValue(v) {
  const raw = String(v ?? "").trim().toLowerCase();
  return raw === "" || raw === "unknown" || raw === "onbekend" || raw === "\u2014" || raw === "-" || raw === "null" || raw === "undefined";
}
__name(isUnknownLikeComplianceValue, "isUnknownLikeComplianceValue");
function isMollieLikePaymentId(v) {
  const raw = String(v ?? "").trim();
  return /^tr_[a-z0-9]+$/i.test(raw);
}
__name(isMollieLikePaymentId, "isMollieLikePaymentId");
function resolveDirectTripPaymentProviderForCompliance(trip, paymentPayloadOrResult) {
  const explicitProvider = safeStr22(
    trip?.payment_provider ?? trip?.paymentProvider ?? paymentPayloadOrResult?.payment_provider ?? paymentPayloadOrResult?.paymentProvider,
    64
  );
  if (explicitProvider && !isUnknownLikeComplianceValue(explicitProvider)) {
    return normalizeComplianceText(explicitProvider);
  }
  const source = normalizeComplianceText(
    trip?.payment_source ?? trip?.paymentSource ?? paymentPayloadOrResult?.payment_source ?? paymentPayloadOrResult?.paymentSource
  );
  const method = normalizeComplianceText(
    trip?.payment_method ?? trip?.paymentMethod ?? paymentPayloadOrResult?.payment_method ?? paymentPayloadOrResult?.paymentMethod
  );
  const paymentId = safeStr22(
    trip?.payment_id ?? trip?.paymentId ?? paymentPayloadOrResult?.payment_id ?? paymentPayloadOrResult?.paymentId,
    128
  );
  const molliePaymentId = safeStr22(
    paymentPayloadOrResult?.mollie_payment_id ?? paymentPayloadOrResult?.molliePaymentId ?? trip?.mollie_payment_id ?? trip?.molliePaymentId ?? trip?.mollie?.payment_id ?? trip?.mollie?.id,
    128
  );
  const hasReliableExternalPaymentId = isMollieLikePaymentId(paymentId) || isMollieLikePaymentId(molliePaymentId);
  const manualLikeSources = /* @__PURE__ */ new Set([
    "in_car",
    "in_vehicle",
    "manual",
    "driver",
    "driver_app",
    "chauffeur",
    "cash"
  ]);
  const manualLikeMethods = /* @__PURE__ */ new Set([
    "cash",
    "bancontact",
    "card",
    "pin",
    "qr",
    "in_car",
    "manual",
    "driver",
    "chauffeur"
  ]);
  if (manualLikeSources.has(source) && manualLikeMethods.has(method) && !hasReliableExternalPaymentId) {
    return "manual";
  }
  return normalizeComplianceText(explicitProvider);
}
__name(resolveDirectTripPaymentProviderForCompliance, "resolveDirectTripPaymentProviderForCompliance");
function buildComplianceAppendUrl(baseUrlRaw) {
  const normalized2 = safeStr22(baseUrlRaw, 512);
  if (!normalized2) return null;
  try {
    const parsed = new URL(normalized2);
    parsed.search = "";
    parsed.hash = "";
    const normalizedPath = parsed.pathname.replace(/\/+$/, "");
    if (normalizedPath === COMPLIANCE_APPEND_PATH) {
      return parsed;
    }
    if (normalizedPath === "" || normalizedPath === "/") {
      parsed.pathname = COMPLIANCE_APPEND_PATH;
      return parsed;
    }
    return null;
  } catch (_) {
    return null;
  }
}
__name(buildComplianceAppendUrl, "buildComplianceAppendUrl");
function _complianceLocationFromPoint(point22) {
  if (!point22 || typeof point22 !== "object" || Array.isArray(point22)) return null;
  const label222 = safeStr22(point22.label ?? point22.address ?? point22.text, 256) ?? null;
  const lat = Number.isFinite(Number(point22.lat)) ? Number(point22.lat) : null;
  const lng = Number.isFinite(Number(point22.lon ?? point22.lng)) ? Number(point22.lon ?? point22.lng) : null;
  if (!label222 && lat === null && lng === null) return null;
  return { label: label222, lat, lng };
}
__name(_complianceLocationFromPoint, "_complianceLocationFromPoint");
function buildDirectTripStartComplianceEvent(trip, startedAt, canonicalScope = null) {
  const normalizedScope = normalizeTenantCompanyScope(canonicalScope);
  if (canonicalScope && (!normalizedScope?.tenant_id || !normalizedScope?.company_id)) {
    return null;
  }
  const tenantId = normalizedScope?.tenant_id ?? safeStr22(trip?.tenant_id ?? trip?.tenantId ?? trip?.company_id ?? trip?.companyId, 96);
  const companyId = normalizedScope?.company_id ?? safeStr22(trip?.company_id ?? trip?.companyId, 96);
  if (!tenantId || !companyId) {
    console.log("[COMPLIANCE][SKIP_SCOPE] source=tracking reason=missing_tenant_company_scope");
    return null;
  }
  const pickup = _complianceLocationFromPoint(trip?.origin);
  const dropoff = _complianceLocationFromPoint(trip?.destination);
  const eventAt = safeStr22(startedAt, 64) ?? safeStr22(trip?.started_at ?? trip?.startedAt, 64) ?? nowIso();
  const tripId = safeStr22(trip?.trip_id ?? trip?.tripId, 128) ?? void 0;
  const bookingId = safeStr22(trip?.booking_id ?? trip?.bookingId, 128) ?? void 0;
  return {
    event_type: "ride_start",
    tenant_id: tenantId,
    company_id: companyId,
    ...bookingId ? { booking_id: bookingId } : {},
    trip_id: tripId,
    session_id: safeStr22(trip?.session_id ?? trip?.sessionId, 128) ?? void 0,
    receipt_reference: safeStr22(trip?.receipt_reference ?? trip?.receiptReference, 128) ?? void 0,
    ride_type: "direct",
    lifecycle_status: "started",
    timestamps: {
      event_at_utc: eventAt,
      started_at_utc: eventAt
    },
    driver: {
      driver_id: safeStr22(trip?.driver_id ?? trip?.driverId, 96) ?? null
    },
    vehicle: {
      vehicle_id: safeStr22(trip?.vehicle_id ?? trip?.vehicleId, 96) ?? null,
      license_plate: safeStr22(trip?.license_plate ?? trip?.licensePlate, 64) ?? void 0
    },
    locations: {
      pickup,
      dropoff
    },
    provenance: {
      producer: "tracking_worker",
      source_endpoint: "/trip/start-direct",
      backend_confirmed: true,
      validation_state: "exportable",
      // Explicit server alias proof for Flutter defensive grouping.
      ...bookingId && tripId ? {
        ride_identity: {
          canonical: `booking:${bookingId}`,
          booking_id: bookingId,
          trip_id: tripId
        }
      } : tripId ? {
        ride_identity: {
          canonical: `trip:${tripId}`,
          trip_id: tripId
        }
      } : {}
    }
  };
}
__name(buildDirectTripStartComplianceEvent, "buildDirectTripStartComplianceEvent");
function buildPlannedSessionStartComplianceEvent(session, body, startedAt, canonicalScope = null) {
  const normalizedScope = normalizeTenantCompanyScope(canonicalScope);
  if (canonicalScope && (!normalizedScope?.tenant_id || !normalizedScope?.company_id)) {
    return null;
  }
  const tenantId = normalizedScope?.tenant_id ?? safeStr22(
    session?.tenant_id ?? session?.tenantId ?? session?.owner_tenant_id ?? body?.tenant_id ?? body?.tenantId,
    96
  );
  const companyId = normalizedScope?.company_id ?? safeStr22(
    session?.company_id ?? session?.companyId ?? session?.owner_company_id ?? body?.company_id ?? body?.companyId,
    96
  );
  if (!tenantId || !companyId) {
    console.log("[COMPLIANCE][SKIP_SCOPE] source=tracking reason=missing_tenant_company_scope");
    return null;
  }
  const originPoint = _complianceLocationFromPoint(body?.origin) ?? _complianceLocationFromPoint(session?.origin) ?? (safeStr22(session?.pickup ?? body?.pickup, 256) ? { label: safeStr22(session?.pickup ?? body?.pickup, 256), lat: null, lng: null } : null);
  const dropoffLabel = safeStr22(session?.dropoff ?? body?.dropoff, 256);
  const dropoff = dropoffLabel ? { label: dropoffLabel, lat: null, lng: null } : null;
  const eventAt = safeStr22(startedAt, 64) ?? safeStr22(session?.started_at ?? session?.startedAt ?? session?.created_at, 64) ?? nowIso();
  return {
    event_type: "ride_start",
    tenant_id: tenantId,
    company_id: companyId,
    booking_id: safeStr22(session?.booking_id ?? session?.bookingId ?? body?.booking_id, 128) ?? void 0,
    session_id: safeStr22(session?.session_id ?? session?.sessionId, 128) ?? void 0,
    ride_type: "planned",
    lifecycle_status: "started",
    timestamps: {
      event_at_utc: eventAt,
      started_at_utc: eventAt
    },
    driver: {
      driver_id: safeStr22(
        session?.driver_id ?? session?.driverId ?? session?.owner_driver_id ?? body?.driver_id ?? body?.driverId,
        96
      ) ?? null
    },
    vehicle: {
      vehicle_id: safeStr22(
        session?.vehicle_id ?? session?.vehicleId ?? session?.owner_vehicle_id ?? body?.vehicle_id ?? body?.vehicleId,
        96
      ) ?? null
    },
    locations: {
      pickup: originPoint,
      dropoff
    },
    provenance: {
      producer: "tracking_worker",
      source_endpoint: "/track/session/start",
      backend_confirmed: true,
      validation_state: "exportable"
    }
  };
}
__name(buildPlannedSessionStartComplianceEvent, "buildPlannedSessionStartComplianceEvent");
function buildDirectTripStopComplianceEvent(trip, stopPayload, stoppedAt, totals, canonicalScope = null) {
  const normalizedScope = normalizeTenantCompanyScope(canonicalScope);
  if (canonicalScope && (!normalizedScope?.tenant_id || !normalizedScope?.company_id)) {
    return null;
  }
  const tenantFromTrip = safeStr22(
    trip?.tenant_id ?? trip?.tenantId ?? trip?.company_id ?? trip?.companyId,
    96
  );
  const tenantFromPayload = safeStr22(
    stopPayload?.tenant_id ?? stopPayload?.tenantId ?? stopPayload?.company_id ?? stopPayload?.companyId,
    96
  );
  const tenantId = normalizedScope?.tenant_id ?? tenantFromTrip ?? tenantFromPayload;
  const companyFromTrip = safeStr22(trip?.company_id ?? trip?.companyId, 96);
  const companyFromPayload = safeStr22(stopPayload?.company_id ?? stopPayload?.companyId, 96);
  const companyId = normalizedScope?.company_id ?? companyFromTrip ?? companyFromPayload;
  if (!tenantId || !companyId) {
    console.log(
      "[COMPLIANCE][SKIP_SCOPE] source=tracking reason=missing_tenant_company_scope"
    );
    return null;
  }
  const pickup = trip?.origin && typeof trip.origin === "object" ? {
    label: safeStr22(trip.origin.label, 256) ?? null,
    lat: Number.isFinite(Number(trip.origin.lat)) ? Number(trip.origin.lat) : null,
    lng: Number.isFinite(Number(trip.origin.lon)) ? Number(trip.origin.lon) : null
  } : null;
  const dropoff = trip?.destination && typeof trip.destination === "object" ? {
    label: safeStr22(trip.destination.label, 256) ?? null,
    lat: Number.isFinite(Number(trip.destination.lat)) ? Number(trip.destination.lat) : null,
    lng: Number.isFinite(Number(trip.destination.lon)) ? Number(trip.destination.lon) : null
  } : null;
  const paymentAmountRaw = trip?.payment_amount ?? trip?.paymentAmount;
  const paymentAmount = Number.isFinite(Number(paymentAmountRaw)) ? Number(paymentAmountRaw) : null;
  const legId = safeStr22(
    trip?.leg_id ?? trip?.legId ?? stopPayload?.leg_id ?? stopPayload?.legId,
    128
  ) ?? void 0;
  const legType = safeStr22(
    trip?.leg_type ?? trip?.legType ?? stopPayload?.leg_type ?? stopPayload?.legType,
    64
  ) ?? void 0;
  const parentBookingId = safeStr22(
    trip?.parent_booking_id ?? trip?.parentBookingId ?? stopPayload?.parent_booking_id ?? stopPayload?.parentBookingId,
    128
  ) ?? void 0;
  const rowKey = safeStr22(
    trip?.row_key ?? trip?.rowKey ?? stopPayload?.row_key ?? stopPayload?.rowKey,
    196
  ) ?? void 0;
  const fareCurrency = (safeStr22(totals?.currency, 8) ?? safeStr22(trip?.currency, 8) ?? safeStr22(trip?.pricing_snapshot?.currency, 8) ?? "EUR").toUpperCase();
  return {
    event_type: "ride_stop",
    tenant_id: tenantId,
    company_id: companyId,
    booking_id: safeStr22(trip?.booking_id ?? trip?.bookingId, 128) ?? void 0,
    trip_id: safeStr22(trip?.trip_id ?? trip?.tripId, 128) ?? void 0,
    ...legId ? { leg_id: legId } : {},
    ...legType ? { leg_type: legType } : {},
    ...parentBookingId ? { parent_booking_id: parentBookingId } : {},
    ...rowKey ? { row_key: rowKey } : {},
    session_id: safeStr22(trip?.session_id ?? trip?.sessionId, 128) ?? void 0,
    receipt_reference: safeStr22(trip?.receipt_reference ?? trip?.receiptReference, 128) ?? void 0,
    ride_type: "direct",
    lifecycle_status: "stopped",
    timestamps: {
      event_at_utc: stoppedAt,
      started_at_utc: safeStr22(trip?.started_at ?? trip?.startedAt ?? trip?.created_at, 64) ?? null,
      stopped_at_utc: stoppedAt
    },
    driver: {
      driver_id: safeStr22(trip?.driver_id ?? trip?.driverId, 96) ?? null
    },
    vehicle: {
      vehicle_id: safeStr22(trip?.vehicle_id ?? trip?.vehicleId, 96) ?? null,
      license_plate: safeStr22(trip?.license_plate ?? trip?.licensePlate, 64) ?? void 0
    },
    locations: {
      pickup,
      dropoff
    },
    fare: {
      currency: fareCurrency,
      distance_km: Number.isFinite(Number(totals?.km_total)) ? Number(totals.km_total) : null,
      wait_seconds_total: Number.isFinite(Number(totals?.wait_seconds_total)) ? Number(totals.wait_seconds_total) : null,
      total_amount: Number.isFinite(Number(totals?.total_eur)) ? Number(totals.total_eur) : null
    },
    payment: {
      status: normalizeComplianceText(trip?.payment_status ?? trip?.paymentStatus),
      method: normalizeComplianceText(trip?.payment_method ?? trip?.paymentMethod),
      source: normalizeComplianceText(trip?.payment_source ?? trip?.paymentSource),
      provider: normalizeComplianceText(trip?.payment_provider ?? trip?.paymentProvider),
      amount: paymentAmount ?? void 0,
      currency: fareCurrency
    },
    provenance: {
      producer: "tracking_worker",
      source_endpoint: "/trip/stop",
      backend_confirmed: true,
      validation_state: "exportable",
      // Explicit server alias when both ids are known on STOP.
      ...(() => {
        const b = safeStr22(trip?.booking_id ?? trip?.bookingId, 128);
        const t = safeStr22(trip?.trip_id ?? trip?.tripId, 128);
        if (b && t) {
          return {
            ride_identity: {
              canonical: `booking:${b}`,
              booking_id: b,
              trip_id: t
            }
          };
        }
        if (t) {
          return { ride_identity: { canonical: `trip:${t}`, trip_id: t } };
        }
        return {};
      })()
    }
  };
}
__name(buildDirectTripStopComplianceEvent, "buildDirectTripStopComplianceEvent");
function buildPlannedTripStopComplianceEvent(trip, stopPayload, canonicalScope = null) {
  const normalizedScope = normalizeTenantCompanyScope(canonicalScope);
  if (canonicalScope && (!normalizedScope?.tenant_id || !normalizedScope?.company_id)) {
    return null;
  }
  const tenantFromPayload = safeStr22(
    stopPayload?.tenant_id ?? stopPayload?.tenantId ?? stopPayload?.company_id ?? stopPayload?.companyId,
    96
  );
  const tenantFromTrip = safeStr22(
    trip?.tenant_id ?? trip?.tenantId ?? trip?.company_id ?? trip?.companyId,
    96
  );
  const tenantId = normalizedScope?.tenant_id ?? tenantFromPayload ?? tenantFromTrip;
  const companyFromPayload = safeStr22(stopPayload?.company_id ?? stopPayload?.companyId, 96);
  const companyFromTrip = safeStr22(trip?.company_id ?? trip?.companyId, 96);
  const companyId = normalizedScope?.company_id ?? companyFromPayload ?? companyFromTrip;
  if (!tenantId || !companyId) {
    console.log(
      "[COMPLIANCE][SKIP_SCOPE] source=tracking reason=missing_tenant_company_scope"
    );
    return null;
  }
  const stoppedAt = safeStr22(
    trip?.stopped_at ?? trip?.stoppedAt ?? stopPayload?.stopped_at ?? stopPayload?.client_stopped_at,
    64
  ) ?? null;
  const startedAt = safeStr22(
    trip?.started_at ?? trip?.startedAt ?? stopPayload?.started_at ?? stopPayload?.client_started_at,
    64
  ) ?? null;
  const fareCurrency = (safeStr22(trip?.currency, 8) ?? safeStr22(stopPayload?.currency, 8) ?? safeStr22(trip?.pricing_snapshot?.currency, 8) ?? "EUR").toUpperCase();
  const paymentAmountRaw = trip?.payment_amount ?? trip?.paymentAmount;
  const paymentAmount = Number.isFinite(Number(paymentAmountRaw)) ? Number(paymentAmountRaw) : null;
  const legId = safeStr22(
    trip?.leg_id ?? trip?.legId ?? stopPayload?.leg_id ?? stopPayload?.legId,
    128
  ) ?? void 0;
  const legType = safeStr22(
    trip?.leg_type ?? trip?.legType ?? stopPayload?.leg_type ?? stopPayload?.legType,
    64
  ) ?? void 0;
  const parentBookingId = safeStr22(
    trip?.parent_booking_id ?? trip?.parentBookingId ?? stopPayload?.parent_booking_id ?? stopPayload?.parentBookingId,
    128
  ) ?? void 0;
  const rowKey = safeStr22(
    trip?.row_key ?? trip?.rowKey ?? stopPayload?.row_key ?? stopPayload?.rowKey,
    196
  ) ?? void 0;
  const pickup = trip?.origin && typeof trip.origin === "object" ? {
    label: safeStr22(trip.origin.label, 256) ?? null,
    lat: Number.isFinite(Number(trip.origin.lat)) ? Number(trip.origin.lat) : null,
    lng: Number.isFinite(Number(trip.origin.lon)) ? Number(trip.origin.lon) : null
  } : null;
  const dropoff = trip?.destination && typeof trip.destination === "object" ? {
    label: safeStr22(trip.destination.label, 256) ?? null,
    lat: Number.isFinite(Number(trip.destination.lat)) ? Number(trip.destination.lat) : null,
    lng: Number.isFinite(Number(trip.destination.lon)) ? Number(trip.destination.lon) : null
  } : null;
  return {
    event_type: "ride_stop",
    tenant_id: tenantId,
    company_id: companyId,
    booking_id: safeStr22(trip?.booking_id ?? trip?.bookingId ?? stopPayload?.booking_id, 128) ?? void 0,
    trip_id: safeStr22(trip?.trip_id ?? trip?.tripId, 128) ?? void 0,
    leg_id: legId,
    leg_type: legType,
    parent_booking_id: parentBookingId,
    row_key: rowKey,
    session_id: safeStr22(trip?.session_id ?? trip?.sessionId, 128) ?? void 0,
    receipt_reference: safeStr22(trip?.receipt_reference ?? trip?.receiptReference, 128) ?? void 0,
    ride_type: "planned",
    lifecycle_status: "stopped",
    timestamps: {
      event_at_utc: stoppedAt,
      started_at_utc: startedAt,
      stopped_at_utc: stoppedAt
    },
    driver: {
      driver_id: safeStr22(trip?.driver_id ?? trip?.driverId, 96) ?? null
    },
    vehicle: {
      vehicle_id: safeStr22(trip?.vehicle_id ?? trip?.vehicleId, 96) ?? null
    },
    locations: {
      pickup,
      dropoff
    },
    fare: {
      currency: fareCurrency,
      distance_km: Number.isFinite(Number(trip?.km_total)) ? Number(trip.km_total) : null,
      wait_seconds_total: Number.isFinite(Number(trip?.wait_seconds_total)) ? Number(trip.wait_seconds_total) : null,
      total_amount: Number.isFinite(Number(trip?.total_eur)) ? Number(trip.total_eur) : null
    },
    payment: {
      status: normalizeComplianceText(trip?.payment_status ?? trip?.paymentStatus),
      method: normalizeComplianceText(trip?.payment_method ?? trip?.paymentMethod),
      source: normalizeComplianceText(trip?.payment_source ?? trip?.paymentSource),
      provider: normalizeComplianceText(trip?.payment_provider ?? trip?.paymentProvider),
      amount: paymentAmount ?? void 0,
      currency: fareCurrency
    },
    provenance: {
      producer: "tracking_worker",
      source_endpoint: "/trip/record-planned-stop",
      backend_confirmed: true,
      validation_state: "exportable"
    }
  };
}
__name(buildPlannedTripStopComplianceEvent, "buildPlannedTripStopComplianceEvent");
function normalizeCompliancePaymentStatus2(value) {
  const raw = safeStr22(value, 64);
  if (!raw) return "unknown";
  const s = raw.toLowerCase();
  if (s === "paid" || s === "confirmed" || s === "completed" || s === "success" || s === "settled") {
    return "paid";
  }
  if (s === "pending" || s === "authorized" || s === "open" || s === "processing") {
    return "pending";
  }
  if (s === "failed" || s === "cancelled" || s === "canceled" || s === "declined") {
    return "failed";
  }
  if (s === "unpaid" || s === "not_paid") {
    return "unpaid";
  }
  return "unknown";
}
__name(normalizeCompliancePaymentStatus2, "normalizeCompliancePaymentStatus");
function buildTripPaymentUpdateComplianceEvent(trip, paymentPayloadOrResult, canonicalScope = null) {
  const normalizedScope = normalizeTenantCompanyScope(canonicalScope);
  if (canonicalScope && (!normalizedScope?.tenant_id || !normalizedScope?.company_id)) {
    return null;
  }
  const tenantFromPayload = safeStr22(
    paymentPayloadOrResult?.tenant_id ?? paymentPayloadOrResult?.tenantId ?? paymentPayloadOrResult?.company_id ?? paymentPayloadOrResult?.companyId,
    96
  );
  const tenantFromTrip = safeStr22(
    trip?.tenant_id ?? trip?.tenantId ?? trip?.company_id ?? trip?.companyId,
    96
  );
  const tenantId = normalizedScope?.tenant_id ?? tenantFromPayload ?? tenantFromTrip;
  const companyFromPayload = safeStr22(
    paymentPayloadOrResult?.company_id ?? paymentPayloadOrResult?.companyId,
    96
  );
  const companyFromTrip = safeStr22(trip?.company_id ?? trip?.companyId, 96);
  const companyId = normalizedScope?.company_id ?? companyFromPayload ?? companyFromTrip;
  if (!tenantId || !companyId) {
    console.log(
      "[COMPLIANCE][SKIP_SCOPE] source=tracking reason=missing_tenant_company_scope"
    );
    return null;
  }
  const paidAt = safeStr22(
    trip?.paid_at ?? trip?.paidAt ?? paymentPayloadOrResult?.paid_at ?? paymentPayloadOrResult?.paidAt,
    64
  ) ?? nowIso();
  const fareCurrency = (safeStr22(trip?.currency, 8) ?? safeStr22(paymentPayloadOrResult?.currency, 8) ?? safeStr22(trip?.pricing_snapshot?.currency, 8) ?? "EUR").toUpperCase();
  const paymentAmountRaw = paymentPayloadOrResult?.amount ?? paymentPayloadOrResult?.price ?? paymentPayloadOrResult?.total ?? trip?.payment_amount ?? trip?.paymentAmount;
  const paymentAmount = Number.isFinite(Number(paymentAmountRaw)) ? Number(paymentAmountRaw) : null;
  const fareTotalRaw = trip?.total_eur ?? trip?.totalEur ?? paymentPayloadOrResult?.total;
  const fareTotal = Number.isFinite(Number(fareTotalRaw)) ? Number(fareTotalRaw) : null;
  const legId = safeStr22(
    trip?.leg_id ?? trip?.legId ?? paymentPayloadOrResult?.leg_id ?? paymentPayloadOrResult?.legId,
    128
  ) ?? void 0;
  const legType = safeStr22(
    trip?.leg_type ?? trip?.legType ?? paymentPayloadOrResult?.leg_type ?? paymentPayloadOrResult?.legType,
    64
  ) ?? void 0;
  const parentBookingId = safeStr22(
    trip?.parent_booking_id ?? trip?.parentBookingId ?? paymentPayloadOrResult?.parent_booking_id ?? paymentPayloadOrResult?.parentBookingId,
    128
  ) ?? void 0;
  const rowKey = safeStr22(
    trip?.row_key ?? trip?.rowKey ?? paymentPayloadOrResult?.row_key ?? paymentPayloadOrResult?.rowKey,
    196
  ) ?? void 0;
  const rideType = (safeStr22(trip?.trip_id ?? trip?.tripId, 160) ?? "").toLowerCase().startsWith("planned_") ? "planned" : "direct";
  return {
    event_type: "payment_update",
    tenant_id: tenantId,
    company_id: companyId,
    booking_id: safeStr22(trip?.booking_id ?? trip?.bookingId, 128) ?? void 0,
    trip_id: safeStr22(trip?.trip_id ?? trip?.tripId, 128) ?? void 0,
    leg_id: legId,
    leg_type: legType,
    parent_booking_id: parentBookingId,
    row_key: rowKey,
    session_id: safeStr22(trip?.session_id ?? trip?.sessionId, 128) ?? void 0,
    receipt_reference: safeStr22(trip?.receipt_reference ?? trip?.receiptReference, 128) ?? void 0,
    ride_type: rideType,
    lifecycle_status: "payment_updated",
    timestamps: {
      event_at_utc: paidAt,
      paid_at_utc: paidAt
    },
    driver: {
      driver_id: safeStr22(trip?.driver_id ?? trip?.driverId, 96) ?? null
    },
    vehicle: {
      vehicle_id: safeStr22(trip?.vehicle_id ?? trip?.vehicleId, 96) ?? null
    },
    fare: {
      currency: fareCurrency,
      total_amount: fareTotal
    },
    payment: {
      status: normalizeCompliancePaymentStatus2(trip?.payment_status ?? trip?.paymentStatus),
      method: normalizeComplianceText(trip?.payment_method ?? trip?.paymentMethod),
      source: normalizeComplianceText(trip?.payment_source ?? trip?.paymentSource),
      provider: resolveDirectTripPaymentProviderForCompliance(trip, paymentPayloadOrResult),
      payment_id: safeStr22(
        trip?.payment_id ?? trip?.paymentId ?? paymentPayloadOrResult?.payment_id ?? paymentPayloadOrResult?.paymentId,
        128
      ) ?? void 0,
      amount: paymentAmount ?? void 0,
      currency: fareCurrency
    },
    provenance: {
      producer: "tracking_worker",
      source_endpoint: "/trip/payment",
      backend_confirmed: true,
      validation_state: "payment_update"
    }
  };
}
__name(buildTripPaymentUpdateComplianceEvent, "buildTripPaymentUpdateComplianceEvent");
async function emitComplianceEventBestEffort(env, event, options = {}) {
  try {
    const baseUrlRaw = safeStr22(env?.COMPLIANCE_API_URL, 512);
    const adminToken = safeStr22(env?.COMPLIANCE_ADMIN_TOKEN, 512);
    if (!baseUrlRaw || !adminToken) {
      return { ok: false, skipped: "missing_config" };
    }
    if (!event || typeof event !== "object" || Array.isArray(event)) {
      return { ok: false, skipped: "invalid_event" };
    }
    const appendUrl = buildComplianceAppendUrl(baseUrlRaw);
    if (!appendUrl) {
      return { ok: false, skipped: "invalid_url_config" };
    }
    const requestedTimeout = Number(options?.timeoutMs);
    const timeoutMs = Number.isFinite(requestedTimeout) ? Math.max(1, Math.min(1500, Math.round(requestedTimeout))) : 1500;
    const controller = new AbortController();
    const timer = setTimeout(() => {
      controller.abort();
    }, timeoutMs);
    try {
      const req = new Request(appendUrl.toString(), {
        method: "POST",
        headers: {
          "content-type": "application/json",
          authorization: `Bearer ${adminToken}`
        },
        body: JSON.stringify(event),
        signal: controller.signal
      });
      const hasServiceBinding = !!(env?.COMPLIANCE_WORKER && typeof env.COMPLIANCE_WORKER.fetch === "function");
      const transport = hasServiceBinding ? "service_binding" : "public_fetch";
      const logLabel = safeStr22(options?.logLabel, 64) ?? "ride_stop";
      const resp = hasServiceBinding ? await env.COMPLIANCE_WORKER.fetch(req) : await ownedReleaseFetchV1(req);
      if (!resp.ok) {
        console.log(
          `[COMPLIANCE_EMIT][${logLabel}] failed status=${resp.status} transport=${transport} origin=${appendUrl.origin} path=${appendUrl.pathname}`
        );
        return { ok: false, status: resp.status };
      }
      return { ok: true, status: resp.status };
    } catch (err) {
      if (err?.name === "AbortError") {
        const logLabel2 = safeStr22(options?.logLabel, 64) ?? "ride_stop";
        console.log(`[COMPLIANCE_EMIT][${logLabel2}] failed error=timeout`);
        return { ok: false, error: "timeout" };
      }
      const logLabel = safeStr22(options?.logLabel, 64) ?? "ride_stop";
      console.log(`[COMPLIANCE_EMIT][${logLabel}] failed error=fetch_failed`);
      return { ok: false, error: "fetch_failed" };
    } finally {
      clearTimeout(timer);
    }
  } catch (_) {
    return { ok: false, error: "internal_error" };
  }
}
__name(emitComplianceEventBestEffort, "emitComplianceEventBestEffort");
function randToken(len = 20) {
  const alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
  let out = "";
  for (let i = 0; i < len; i++) {
    out += alphabet[Math.floor(Math.random() * alphabet.length)];
  }
  return out;
}
__name(randToken, "randToken");
async function kvPutJson(kv, key2, value, ttlSeconds) {
  const opts = {};
  if (ttlSeconds && Number.isFinite(ttlSeconds)) {
    opts.expirationTtl = Math.floor(ttlSeconds);
  }
  await kv.put(key2, JSON.stringify(value), opts);
}
__name(kvPutJson, "kvPutJson");
async function kvGetJson(kv, key2) {
  const raw = await kv.get(key2);
  if (!raw) return null;
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}
__name(kvGetJson, "kvGetJson");
async function kvDel(kv, key2) {
  try {
    await kv.delete(key2);
  } catch {
  }
}
__name(kvDel, "kvDel");
var TTL_SESSION = 60 * 60 * 24 * 14;
var TTL_LASTPING = 60 * 60 * 24 * 14;
var TTL_INDEX = 60 * 60 * 24 * 30;
var TTL_PUBLIC_TOKEN = 60 * 60 * 24 * 14;
var TTL_TRIP = 60 * 60 * 24 * 30;
async function mapboxGeocode(token, q) {
  const query = encodeURIComponent(q);
  const url = `https://api.mapbox.com/geocoding/v5/mapbox.places/${query}.json?limit=1&language=nl&country=BE&access_token=${encodeURIComponent(token)}`;
  const r = await ownedReleaseFetchV1(url, { method: "GET" });
  if (!r.ok) throw new Error(`Mapbox geocode failed (${r.status})`);
  const j = await r.json();
  const f = Array.isArray(j.features) ? j.features[0] : null;
  if (!f || !Array.isArray(f.center) || f.center.length < 2) {
    throw new Error("Mapbox geocode: no result");
  }
  const lon = Number(f.center[0]);
  const lat = Number(f.center[1]);
  if (!Number.isFinite(lat) || !Number.isFinite(lon)) {
    throw new Error("Mapbox geocode: invalid coordinates");
  }
  return { lat, lon, place_name: f.place_name || q };
}
__name(mapboxGeocode, "mapboxGeocode");
async function mapboxDirections(token, from, to, profile = "driving") {
  const prof = (profile || "driving").toString().trim().toLowerCase();
  const allowed2 = /* @__PURE__ */ new Set(["driving", "driving-traffic", "walking", "cycling"]);
  const p = allowed2.has(prof) ? prof : "driving";
  const coords = `${from.lon},${from.lat};${to.lon},${to.lat}`;
  const url = `https://api.mapbox.com/directions/v5/mapbox/${p}/${coords}?geometries=geojson&overview=full&steps=false&access_token=${encodeURIComponent(token)}`;
  const r = await ownedReleaseFetchV1(url, { method: "GET" });
  if (!r.ok) throw new Error(`Mapbox directions failed (${r.status})`);
  const j = await r.json();
  const route = Array.isArray(j.routes) ? j.routes[0] : null;
  if (!route || !route.geometry) throw new Error("Mapbox directions: no route");
  return {
    distance_m: Number(route.distance) || 0,
    duration_s: Number(route.duration) || 0,
    geometry: route.geometry
    // GeoJSON LineString
  };
}
__name(mapboxDirections, "mapboxDirections");
function makeTripId() {
  if (globalThis.crypto && typeof globalThis.crypto.randomUUID === "function") {
    return `trip_${globalThis.crypto.randomUUID()}`;
  }
  return `trip_${Date.now().toString(36)}_${randToken(12)}`;
}
__name(makeTripId, "makeTripId");
function tripKey(tripId) {
  return `trip:${tripId}`;
}
__name(tripKey, "tripKey");
function money2Num(value) {
  return Math.round((Number(value) || 0) * 100) / 100;
}
__name(money2Num, "money2Num");
function roundFareCentsToNearestTenCents(rawCents) {
  if (rawCents === null || rawCents === void 0) return null;
  const value = Number(rawCents);
  if (!Number.isFinite(value)) return null;
  if (value === 0) return 0;
  if (value < 0) return null;
  const cents = Math.round(value);
  if (cents === 0) return 0;
  return Math.floor((cents + 5) / 10) * 10;
}
__name(roundFareCentsToNearestTenCents, "roundFareCentsToNearestTenCents");
function normalizeDestination(v) {
  if (!v || typeof v !== "object") return null;
  const label222 = safeStr22(v.label ?? v.address ?? v.text ?? "", 256);
  const lat = safeNum(v.lat, -90, 90);
  const lon = safeNum(v.lon ?? v.lng, -180, 180);
  const out = {};
  if (label222) out.label = label222;
  if (lat !== null && lon !== null) {
    out.lat = lat;
    out.lon = lon;
  }
  return Object.keys(out).length ? out : null;
}
__name(normalizeDestination, "normalizeDestination");
function normalizePricingSnapshot(v) {
  if (!v || typeof v !== "object") throw new Error("pricing_snapshot is required");
  const start_fee = safeNum(v.start_fee, 0, 1e4);
  const per_km = safeNum(v.per_km, 0, 1e3);
  const wait_per_min = safeNum(v.wait_per_min, 0, 1e3);
  if (start_fee === null) throw new Error("pricing_snapshot.start_fee is required");
  if (per_km === null) throw new Error("pricing_snapshot.per_km is required");
  if (wait_per_min === null) throw new Error("pricing_snapshot.wait_per_min is required");
  const vat_rate_raw = safeNum(v.vat_rate, 0, 1);
  const vat_rate = vat_rate_raw === null ? 0 : vat_rate_raw;
  const vat_mode_raw = String(v.vat_mode ?? v.vatMode ?? "incl").trim().toLowerCase();
  const vat_mode = vat_mode_raw === "excl" ? "excl" : "incl";
  return {
    start_fee,
    per_km,
    wait_per_min,
    currency: safeStr22(v.currency ?? "EUR", 8) ?? "EUR",
    vat_rate,
    vat_mode
  };
}
__name(normalizePricingSnapshot, "normalizePricingSnapshot");
function normalizeBookingDetails(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const allowed2 = [
    "pickup_address",
    "destination_address",
    "scheduled_pickup_at",
    "subtype",
    "customer_name",
    "customer_phone",
    "customer_email",
    "customerName",
    "customerPhone",
    "customerEmail",
    "name",
    "phone",
    "tel",
    "mobile",
    "email",
    "customer_country",
    "customerCountry",
    "country",
    "countryCode",
    "country_iso",
    "countryIso",
    "locale",
    "language",
    "phone_country_code",
    "phoneCountryCode",
    "dial_code",
    "dialCode",
    "service_type",
    "serviceType",
    "service",
    "tier",
    "vehicle_tier",
    "vehicleTier",
    "passengers",
    "luggage_count",
    "booked_wait_minutes",
    "booking_status",
    "leg_id",
    "legId",
    "leg_type",
    "legType",
    "row_key",
    "rowKey",
    "parent_booking_id",
    "parentBookingId",
    "is_operational_leg",
    "isOperationalLeg",
    "booking_total_eur",
    "segment_price_eur",
    "leg_price_incl_vat",
    "legPriceInclVat",
    "outbound_price_eur",
    "return_price_eur",
    "payment_status",
    "paymentStatus",
    "payment_method",
    "paymentMethod",
    "payment_source",
    "paymentSource",
    "return_scheduled_pickup_at",
    "return_route",
    "route_segments",
    "stops",
    "extras",
    "notes",
    "currency"
  ];
  const out = {};
  for (const key2 of allowed2) {
    if (!(key2 in value)) continue;
    const v = value[key2];
    if (v === null || v === void 0) continue;
    if (typeof v === "string") {
      const s = safeStr22(v, key2 === "route_segments" ? 4096 : 1024);
      if (s) out[key2] = s;
      continue;
    }
    if (typeof v === "number") {
      if (Number.isFinite(v)) out[key2] = v;
      continue;
    }
    if (typeof v === "boolean") {
      out[key2] = v;
      continue;
    }
    if (key2 === "route_segments" && Array.isArray(v)) {
      out[key2] = v.slice(0, 12).map((segment) => {
        if (!segment || typeof segment !== "object") return null;
        return {
          from: safeStr22(segment.from, 1024) ?? null,
          to: safeStr22(segment.to, 1024) ?? null,
          distance_km: safeNum(segment.distance_km, 0, 1e5),
          duration_min: safeNum(segment.duration_min, 0, 1e5),
          kind: safeStr22(segment.kind, 32) ?? null
        };
      }).filter(Boolean);
      continue;
    }
    if (Array.isArray(v)) {
      out[key2] = v.slice(0, 20).map((x) => safeStr22(x, 512)).filter(Boolean);
    }
  }
  return Object.keys(out).length ? out : null;
}
__name(normalizeBookingDetails, "normalizeBookingDetails");
async function prependIndex(kv, key2, value, maxItems) {
  const existing = await kvGetJson(kv, key2) ?? [];
  const arr = Array.isArray(existing) ? existing : [];
  const next = [value, ...arr.filter((x) => x !== value)].slice(0, maxItems);
  await kvPutJson(kv, key2, next, TTL_TRIP);
}
__name(prependIndex, "prependIndex");
function directTripTotals(trip, kmTotal, waitSecondsTotal) {
  const pricing = trip?.pricing_snapshot || {};
  const startFee = Number(pricing.start_fee) || 0;
  const perKm = Number(pricing.per_km) || 0;
  const waitPerMin = Number(pricing.wait_per_min) || 0;
  const waitMinutes = waitSecondsTotal / 60;
  const rawTotal = startFee + kmTotal * perKm + waitMinutes * waitPerMin;
  const vatRateRaw = Number(pricing.vat_rate);
  const vatRate = Number.isFinite(vatRateRaw) ? Math.max(0, Math.min(1, vatRateRaw)) : 0;
  const vatModeRaw = String(pricing.vat_mode ?? pricing.vatMode ?? "incl").trim().toLowerCase();
  const vatMode = vatModeRaw === "excl" ? "excl" : "incl";
  const hasVatMeta = pricing.vat_rate != null || pricing.vat_mode != null || pricing.vatMode != null;
  let priceExVat = rawTotal;
  let priceVat = 0;
  let priceInclVat = rawTotal;
  if (hasVatMeta) {
    if (vatMode === "incl") {
      priceExVat = vatRate > 0 ? rawTotal / (1 + vatRate) : rawTotal;
      priceVat = rawTotal - priceExVat;
      priceInclVat = rawTotal;
    } else {
      priceExVat = rawTotal;
      priceVat = rawTotal * vatRate;
      priceInclVat = rawTotal + priceVat;
    }
  }
  const rawInclCents = Math.round(priceInclVat * 100);
  const roundedInclCents = roundFareCentsToNearestTenCents(rawInclCents);
  const finalInclVat = roundedInclCents === null ? money2Num(priceInclVat) : roundedInclCents / 100;
  let finalExVat;
  let finalVat;
  if (hasVatMeta && vatRate > 0) {
    finalExVat = money2Num(finalInclVat / (1 + vatRate));
    finalVat = money2Num(finalInclVat - finalExVat);
  } else {
    finalExVat = finalInclVat;
    finalVat = 0;
  }
  console.log(
    `[FARE_ROUNDING] phase=finalize source=street rawCents=${rawInclCents} roundedCents=${roundedInclCents === null ? "null" : roundedInclCents} alreadyFinalized=false`
  );
  return {
    km_total: kmTotal,
    wait_seconds_total: waitSecondsTotal,
    wait_minutes: money2Num(waitMinutes),
    total_eur: finalInclVat,
    price_ex_vat: finalExVat,
    price_vat: finalVat,
    price_incl_vat: finalInclVat,
    vat_rate: vatRate,
    vat_mode: vatMode,
    currency: safeStr22(pricing.currency ?? "EUR", 8) ?? "EUR",
    fare_rounding_policy: "nearest_ten_cents_half_up"
  };
}
__name(directTripTotals, "directTripTotals");
var DIRECT_BOOKING_FINALIZE_STATE = { COMPLETED: "completed", PENDING: "pending" };
var DIRECT_RECONCILE_REASON = {
  REPAIRABLE: "repairable",
  ALREADY_COMPLETED: "already_completed",
  MISSING_TRIP: "skipped_missing_trip",
  NOT_STREET_DIRECT: "skipped_not_street_direct",
  MISSING_BOOKING_ID: "skipped_missing_trip",
  NON_TERMINAL: "skipped_non_terminal",
  MISSING_FARE: "skipped_missing_fare"
};
function _dbfStr(v, max = 200) {
  if (v === null || v === void 0) return "";
  const s = String(v).trim();
  return max > 0 ? s.slice(0, max) : s;
}
__name(_dbfStr, "_dbfStr");
function _dbfNumOrNull(v) {
  if (v === null || v === void 0 || v === "") return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}
__name(_dbfNumOrNull, "_dbfNumOrNull");
function isStreetDirectTrip(trip) {
  if (!trip || typeof trip !== "object") return false;
  const kind = _dbfStr(trip.kind).toLowerCase();
  const source = _dbfStr(trip.source).toLowerCase();
  return kind === "direct" || source === "street_ride";
}
__name(isStreetDirectTrip, "isStreetDirectTrip");
function directTripIsTerminal(trip) {
  if (!trip || typeof trip !== "object") return false;
  if (trip.test_retirement || _dbfStr(trip.status).toLowerCase() === "cancelled") return false;
  const status = _dbfStr(trip.status).toLowerCase();
  if (status === "stopped" || status === "completed" || status === "done") return true;
  return _dbfStr(trip.stopped_at).length > 0;
}
__name(directTripIsTerminal, "directTripIsTerminal");
function directBookingIdFromTrip(trip) {
  if (!trip || typeof trip !== "object") return "";
  return _dbfStr(trip.booking_id ?? trip.bookingId, 160);
}
__name(directBookingIdFromTrip, "directBookingIdFromTrip");
function authoritativeTripFareCents(trip) {
  if (!trip || typeof trip !== "object") return null;
  for (const raw of [trip.price_incl_vat, trip.total_eur]) {
    const n = _dbfNumOrNull(raw);
    if (n !== null && n >= 0) return Math.round(n * 100);
  }
  return null;
}
__name(authoritativeTripFareCents, "authoritativeTripFareCents");
function tripHasAuthoritativeFare(trip) {
  return authoritativeTripFareCents(trip) !== null;
}
__name(tripHasAuthoritativeFare, "tripHasAuthoritativeFare");
function tripReconcileEligibility(trip) {
  if (!trip || typeof trip !== "object") return { ok: false, reason: DIRECT_RECONCILE_REASON.MISSING_TRIP };
  if (!isStreetDirectTrip(trip)) return { ok: false, reason: DIRECT_RECONCILE_REASON.NOT_STREET_DIRECT };
  if (!directBookingIdFromTrip(trip)) return { ok: false, reason: DIRECT_RECONCILE_REASON.MISSING_BOOKING_ID };
  if (!directTripIsTerminal(trip)) return { ok: false, reason: DIRECT_RECONCILE_REASON.NON_TERMINAL };
  if (!tripHasAuthoritativeFare(trip)) return { ok: false, reason: DIRECT_RECONCILE_REASON.MISSING_FARE };
  return { ok: true, reason: DIRECT_RECONCILE_REASON.REPAIRABLE };
}
__name(tripReconcileEligibility, "tripReconcileEligibility");
function bookingAlreadyFinalized(trip) {
  return _dbfStr(trip?.booking_finalize_state).toLowerCase() === DIRECT_BOOKING_FINALIZE_STATE.COMPLETED;
}
__name(bookingAlreadyFinalized, "bookingAlreadyFinalized");
function buildFinalizePayloadFromTrip(trip, scope2) {
  return {
    tenant_id: _dbfStr(scope2?.tenant_id, 80),
    company_id: _dbfStr(scope2?.company_id, 80),
    booking_id: directBookingIdFromTrip(trip),
    trip_id: _dbfStr(trip?.trip_id, 160) || null,
    stopped_at: _dbfStr(trip?.stopped_at, 80) || null,
    total_eur: _dbfNumOrNull(trip?.price_incl_vat ?? trip?.total_eur),
    price_ex_vat: _dbfNumOrNull(trip?.price_ex_vat),
    price_vat: _dbfNumOrNull(trip?.price_vat),
    vat_rate_percent: _dbfNumOrNull(trip?.vat_rate),
    currency: _dbfStr(trip?.currency ?? trip?.pricing_snapshot?.currency, 8) || "EUR",
    source: "street_ride_stop"
  };
}
__name(buildFinalizePayloadFromTrip, "buildFinalizePayloadFromTrip");
function deriveFinalizeStateFromResult(res) {
  return res && res.ok === true ? DIRECT_BOOKING_FINALIZE_STATE.COMPLETED : DIRECT_BOOKING_FINALIZE_STATE.PENDING;
}
__name(deriveFinalizeStateFromResult, "deriveFinalizeStateFromResult");
function finalizeErrorCodeFromResult(res) {
  if (res && res.ok === true) return null;
  return _dbfStr(res?.error, 120) || "unknown";
}
__name(finalizeErrorCodeFromResult, "finalizeErrorCodeFromResult");
function applyBookingFinalizeAttempt(trip, { state, errorCode = null, nowIso: nowIso2, attemptDelta = 1 } = {}) {
  if (!trip || typeof trip !== "object") return trip;
  const completed = DIRECT_BOOKING_FINALIZE_STATE.COMPLETED;
  const nextState = bookingAlreadyFinalized(trip) ? completed : state;
  trip.booking_finalize_state = nextState;
  trip.booking_finalize_attempted_at = _dbfStr(nowIso2, 80) || trip.booking_finalize_attempted_at || null;
  const prevCount = Number(trip.booking_finalize_attempt_count);
  trip.booking_finalize_attempt_count = (Number.isFinite(prevCount) ? prevCount : 0) + (Number(attemptDelta) || 0);
  trip.booking_finalize_last_error_code = nextState === completed ? null : errorCode || null;
  return trip;
}
__name(applyBookingFinalizeAttempt, "applyBookingFinalizeAttempt");
function safeBookingFinalizeResponseFields(trip) {
  const completed = bookingAlreadyFinalized(trip);
  return {
    booking_id: directBookingIdFromTrip(trip) || null,
    booking_finalize_state: completed ? DIRECT_BOOKING_FINALIZE_STATE.COMPLETED : DIRECT_BOOKING_FINALIZE_STATE.PENDING,
    booking_finalized: completed
  };
}
__name(safeBookingFinalizeResponseFields, "safeBookingFinalizeResponseFields");
var COMPLIANCE_EMIT_STATE = { APPLIED: "applied", PENDING: "pending" };
function complianceEmitAlreadyApplied(trip) {
  return _dbfStr(trip?.compliance_emit_state).toLowerCase() === COMPLIANCE_EMIT_STATE.APPLIED;
}
__name(complianceEmitAlreadyApplied, "complianceEmitAlreadyApplied");
function buildDeterministicRideStopEventId(tenantId, companyId, tripId) {
  const t = _dbfStr(tenantId, 96);
  const c = _dbfStr(companyId, 96);
  const r = _dbfStr(tripId, 160);
  if (!t || !c || !r) return "";
  return `ride_stop:${t}:${c}:${r}`;
}
__name(buildDeterministicRideStopEventId, "buildDeterministicRideStopEventId");
function deriveComplianceEmitStateFromResult(res) {
  return res && res.ok === true ? COMPLIANCE_EMIT_STATE.APPLIED : COMPLIANCE_EMIT_STATE.PENDING;
}
__name(deriveComplianceEmitStateFromResult, "deriveComplianceEmitStateFromResult");
function complianceEmitErrorCodeFromResult(res) {
  if (res && res.ok === true) return null;
  if (res && typeof res === "object") {
    if (res.skipped) return _dbfStr(res.skipped, 120) || "skipped";
    if (res.error) return _dbfStr(res.error, 120) || "error";
    if (Number.isFinite(Number(res.status))) return `http_${Number(res.status)}`;
  }
  return "unknown";
}
__name(complianceEmitErrorCodeFromResult, "complianceEmitErrorCodeFromResult");
function applyComplianceEmitAttempt(trip, { state, errorCode = null, eventId = null, nowIso: nowIso2, attemptDelta = 1 } = {}) {
  if (!trip || typeof trip !== "object") return trip;
  const applied = COMPLIANCE_EMIT_STATE.APPLIED;
  const nextState = complianceEmitAlreadyApplied(trip) ? applied : state;
  trip.compliance_emit_state = nextState;
  trip.compliance_emit_attempted_at = _dbfStr(nowIso2, 80) || trip.compliance_emit_attempted_at || null;
  const prevCount = Number(trip.compliance_emit_attempt_count);
  trip.compliance_emit_attempt_count = (Number.isFinite(prevCount) ? prevCount : 0) + (Number(attemptDelta) || 0);
  trip.compliance_emit_last_error_code = nextState === applied ? null : errorCode || null;
  const persistedId = _dbfStr(trip.compliance_emit_event_id, 200);
  const incomingId = _dbfStr(eventId, 200);
  if (!persistedId && incomingId) trip.compliance_emit_event_id = incomingId;
  return trip;
}
__name(applyComplianceEmitAttempt, "applyComplianceEmitAttempt");
function complianceEmitRetryEligible(trip) {
  if (!trip || typeof trip !== "object") return false;
  if (!directTripIsTerminal(trip)) return false;
  const state = _dbfStr(trip.compliance_emit_state).toLowerCase();
  return state === "" || state === COMPLIANCE_EMIT_STATE.PENDING;
}
__name(complianceEmitRetryEligible, "complianceEmitRetryEligible");
async function ensureDirectTripStopComplianceEmit(env, {
  trip,
  key: key2,
  scope: scope2,
  body = {},
  tripId,
  logLabel = "ensure_direct_stop",
  timeoutMs = 1500
} = {}) {
  const fieldsEmpty = /* @__PURE__ */ __name(() => safeComplianceEmitResponseFields(trip), "fieldsEmpty");
  if (!trip || typeof trip !== "object") {
    return { event: null, fields: fieldsEmpty(), emitted: false };
  }
  if (complianceEmitAlreadyApplied(trip)) {
    return { event: null, fields: fieldsEmpty(), emitted: false };
  }
  if (!directTripIsTerminal(trip)) {
    return { event: null, fields: fieldsEmpty(), emitted: false };
  }
  const stoppedAt = _dbfStr(trip?.stopped_at, 80) || _dbfStr(body?.client_stopped_at, 80) || nowIso();
  const totals = {
    km_total: trip?.km_total,
    wait_seconds_total: trip?.wait_seconds_total,
    total_eur: trip?.total_eur,
    price_ex_vat: trip?.price_ex_vat,
    price_vat: trip?.price_vat,
    price_incl_vat: trip?.price_incl_vat,
    vat_rate: trip?.vat_rate,
    vat_mode: trip?.vat_mode,
    currency: trip?.currency
  };
  const event = buildDirectTripStopComplianceEvent(
    trip,
    body,
    stoppedAt,
    totals,
    scope2
  );
  if (!event) {
    console.log(
      `[COMPLIANCE_EMIT][${logLabel}] skipped reason=missing_canonical_scope trip_id=${tripId || "-"}`
    );
    return { event: null, fields: fieldsEmpty(), emitted: false };
  }
  const eventId = _dbfStr(trip.compliance_emit_event_id, 200) || buildDeterministicRideStopEventId(
    event.tenant_id,
    event.company_id,
    event.trip_id ?? tripId
  );
  if (eventId) event.event_id = eventId;
  const priorState = _dbfStr(trip.compliance_emit_state).toLowerCase();
  if (priorState !== COMPLIANCE_EMIT_STATE.PENDING) {
    applyComplianceEmitAttempt(trip, {
      state: COMPLIANCE_EMIT_STATE.PENDING,
      errorCode: null,
      eventId,
      nowIso: nowIso(),
      attemptDelta: priorState === "" ? 1 : 0
    });
    applyCanonicalScopeToRecord(trip, scope2);
    await kvPutJson(env.FLUXIDI_TRACKING, key2, trip, TTL_TRIP);
    _chironSyncLog("enqueue", trip, tripId, event, "queued", logLabel);
  }
  let emitRes;
  try {
    emitRes = await emitComplianceEventBestEffort(env, event, {
      timeoutMs,
      logLabel
    });
  } catch (err) {
    emitRes = {
      ok: false,
      error: _dbfStr(err?.message || err, 120) || "internal_error"
    };
  }
  const nextState = deriveComplianceEmitStateFromResult(emitRes);
  applyComplianceEmitAttempt(trip, {
    state: nextState,
    errorCode: complianceEmitErrorCodeFromResult(emitRes),
    eventId,
    nowIso: nowIso()
  });
  applyCanonicalScopeToRecord(trip, scope2);
  await kvPutJson(env.FLUXIDI_TRACKING, key2, trip, TTL_TRIP);
  _chironSyncLog(
    "ensure",
    trip,
    tripId,
    event,
    nextState,
    complianceEmitErrorCodeFromResult(emitRes) || "ok"
  );
  return {
    event,
    fields: safeComplianceEmitResponseFields(trip),
    emitted: nextState === COMPLIANCE_EMIT_STATE.APPLIED
  };
}
__name(ensureDirectTripStopComplianceEmit, "ensureDirectTripStopComplianceEmit");
function complianceEmitStartAlreadyApplied(session) {
  return _dbfStr(session?.compliance_emit_start_state).toLowerCase() === COMPLIANCE_EMIT_STATE.APPLIED;
}
__name(complianceEmitStartAlreadyApplied, "complianceEmitStartAlreadyApplied");
function buildDeterministicRideStartEventId(tenantId, companyId, sessionId) {
  const t = _dbfStr(tenantId, 96);
  const c = _dbfStr(companyId, 96);
  const s = _dbfStr(sessionId, 200);
  if (!t || !c || !s) return "";
  return `ride_start:${t}:${c}:${s}`;
}
__name(buildDeterministicRideStartEventId, "buildDeterministicRideStartEventId");
function buildDeterministicDirectRideStartEventId(tenantId, companyId, tripId) {
  const t = _dbfStr(tenantId, 96);
  const c = _dbfStr(companyId, 96);
  const r = _dbfStr(tripId, 160);
  if (!t || !c || !r) return "";
  return `ride_start:${t}:${c}:${r}`;
}
__name(buildDeterministicDirectRideStartEventId, "buildDeterministicDirectRideStartEventId");
function directTripStartRetryEligible(trip) {
  if (!trip || typeof trip !== "object") return false;
  const state = _dbfStr(trip.compliance_emit_start_state).toLowerCase();
  return state === COMPLIANCE_EMIT_STATE.PENDING;
}
__name(directTripStartRetryEligible, "directTripStartRetryEligible");
function applyComplianceEmitStartAttempt(session, { state, errorCode = null, eventId = null, nowIso: nowIso2, attemptDelta = 1 } = {}) {
  if (!session || typeof session !== "object") return session;
  const applied = COMPLIANCE_EMIT_STATE.APPLIED;
  const nextState = complianceEmitStartAlreadyApplied(session) ? applied : state;
  session.compliance_emit_start_state = nextState;
  session.compliance_emit_start_attempted_at = _dbfStr(nowIso2, 80) || session.compliance_emit_start_attempted_at || null;
  const prevCount = Number(session.compliance_emit_start_attempt_count);
  session.compliance_emit_start_attempt_count = (Number.isFinite(prevCount) ? prevCount : 0) + (Number(attemptDelta) || 0);
  session.compliance_emit_start_last_error_code = nextState === applied ? null : errorCode || null;
  const persistedId = _dbfStr(session.compliance_emit_start_event_id, 200);
  const incomingId = _dbfStr(eventId, 200);
  if (!persistedId && incomingId) {
    session.compliance_emit_start_event_id = incomingId;
  }
  return session;
}
__name(applyComplianceEmitStartAttempt, "applyComplianceEmitStartAttempt");
function complianceEmitStartRetryEligible(session) {
  if (!session || typeof session !== "object") return false;
  if (complianceEmitStartAlreadyApplied(session)) return false;
  return true;
}
__name(complianceEmitStartRetryEligible, "complianceEmitStartRetryEligible");
function plannedTripIsStopped(trip) {
  if (!trip || typeof trip !== "object") return false;
  const status = _dbfStr(trip.status).toLowerCase();
  if (status === "stopped" || status === "completed" || status === "done") {
    return true;
  }
  return _dbfStr(trip.stopped_at).length > 0;
}
__name(plannedTripIsStopped, "plannedTripIsStopped");
function plannedTripComplianceEmitRetryEligible(trip) {
  if (!trip || typeof trip !== "object") return false;
  const kind = _dbfStr(trip.kind).toLowerCase();
  if (kind && kind !== "planned") return false;
  if (!plannedTripIsStopped(trip)) return false;
  const state = _dbfStr(trip.compliance_emit_state).toLowerCase();
  return state === "" || state === COMPLIANCE_EMIT_STATE.PENDING;
}
__name(plannedTripComplianceEmitRetryEligible, "plannedTripComplianceEmitRetryEligible");
function safeComplianceEmitResponseFields(trip) {
  return {
    compliance_emit_state: _dbfStr(trip?.compliance_emit_state).toLowerCase() || COMPLIANCE_EMIT_STATE.PENDING,
    compliance_emit_event_id: _dbfStr(trip?.compliance_emit_event_id, 200) || null,
    compliance_emit_attempt_count: Number.isFinite(Number(trip?.compliance_emit_attempt_count)) ? Number(trip.compliance_emit_attempt_count) : 0
  };
}
__name(safeComplianceEmitResponseFields, "safeComplianceEmitResponseFields");
function safeComplianceEmitStartResponseFields(session) {
  return {
    compliance_emit_start_state: _dbfStr(session?.compliance_emit_start_state).toLowerCase() || COMPLIANCE_EMIT_STATE.PENDING,
    compliance_emit_start_event_id: _dbfStr(session?.compliance_emit_start_event_id, 200) || null,
    compliance_emit_start_attempt_count: Number.isFinite(
      Number(session?.compliance_emit_start_attempt_count)
    ) ? Number(session.compliance_emit_start_attempt_count) : 0
  };
}
__name(safeComplianceEmitStartResponseFields, "safeComplianceEmitStartResponseFields");
function _chironIdHash(v) {
  const s = _dbfStr(v, 256);
  if (!s) return "-";
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = h + ((h << 1) + (h << 4) + (h << 7) + (h << 8) + (h << 24)) >>> 0;
  }
  return h.toString(36).padStart(7, "0").slice(0, 12);
}
__name(_chironIdHash, "_chironIdHash");
function _chironSyncLog(stage, trip, tripId, event, result2, reason) {
  const tenantPresent = !!(event?.tenant_id && event?.company_id);
  const bookingId = _dbfStr(event?.booking_id ?? trip?.booking_id ?? trip?.bookingId, 160);
  const idempotencyKeyPresent = !!(event?.event_id ?? trip?.compliance_emit_event_id);
  const attempt = Number(trip?.compliance_emit_attempt_count) || 0;
  console.log(
    `[CHIRON_SYNC] stage=${stage} tripIdHash=${_chironIdHash(tripId)} bookingIdHash=${_chironIdHash(bookingId)} tenantPresent=${tenantPresent} idempotencyKeyPresent=${idempotencyKeyPresent} result=${result2} reason=${_dbfStr(reason, 40) || "-"} attempt=${attempt}`
  );
}
__name(_chironSyncLog, "_chironSyncLog");
function summarizeTrip(trip) {
  const origin = trip?.origin && typeof trip.origin === "object" ? trip.origin : null;
  const destination = trip?.destination && typeof trip.destination === "object" ? trip.destination : null;
  const bookingDetails = normalizeBookingDetails(trip?.booking_details);
  return {
    trip_id: trip?.trip_id ?? null,
    kind: trip?.kind ?? null,
    booking_id: trip?.booking_id ?? null,
    tenant_id: trip?.tenant_id ?? null,
    driver_id: trip?.driver_id ?? null,
    vehicle_id: trip?.vehicle_id ?? null,
    status: trip?.status ?? null,
    started_at: trip?.started_at ?? trip?.created_at ?? null,
    stopped_at: trip?.stopped_at ?? null,
    origin: origin ? {
      label: origin.label ?? null,
      lat: origin.lat ?? null,
      lon: origin.lon ?? null
    } : null,
    destination: destination ? {
      label: destination.label ?? null,
      lat: destination.lat ?? null,
      lon: destination.lon ?? null
    } : null,
    km_total: Number.isFinite(Number(trip?.km_total)) ? Number(trip.km_total) : null,
    wait_seconds_total: Number.isFinite(Number(trip?.wait_seconds_total)) ? Number(trip.wait_seconds_total) : 0,
    total_eur: Number.isFinite(Number(trip?.total_eur)) ? Number(trip.total_eur) : null,
    currency: safeStr22(trip?.currency ?? trip?.pricing_snapshot?.currency ?? "EUR", 8) ?? "EUR",
    payment_status: safeStr22(trip?.payment_status ?? trip?.paymentStatus ?? "", 32) ?? null,
    paymentStatus: safeStr22(trip?.paymentStatus ?? trip?.payment_status ?? "", 32) ?? null,
    payment_method: safeStr22(trip?.payment_method ?? trip?.paymentMethod ?? "", 32) ?? null,
    paymentMethod: safeStr22(trip?.paymentMethod ?? trip?.payment_method ?? "", 32) ?? null,
    payment_source: safeStr22(trip?.payment_source ?? trip?.paymentSource ?? "", 32) ?? null,
    paymentSource: safeStr22(trip?.paymentSource ?? trip?.payment_source ?? "", 32) ?? null,
    paid_at: safeStr22(trip?.paid_at ?? trip?.paidAt ?? "", 64) ?? null,
    paidAt: safeStr22(trip?.paidAt ?? trip?.paid_at ?? "", 64) ?? null,
    paid_by_driver_id: safeStr22(trip?.paid_by_driver_id ?? trip?.paidByDriverId ?? "", 96) ?? null,
    paidByDriverId: safeStr22(trip?.paidByDriverId ?? trip?.paid_by_driver_id ?? "", 96) ?? null,
    payment_amount: Number.isFinite(Number(trip?.payment_amount)) ? Number(trip.payment_amount) : Number.isFinite(Number(trip?.paymentAmount)) ? Number(trip.paymentAmount) : null,
    paymentAmount: Number.isFinite(Number(trip?.paymentAmount)) ? Number(trip.paymentAmount) : Number.isFinite(Number(trip?.payment_amount)) ? Number(trip.payment_amount) : null,
    booking_details: bookingDetails
  };
}
__name(summarizeTrip, "summarizeTrip");
async function handleHealth(req, env, origin) {
  return withCors(
    json2({ ok: true, service: "fluxidi-tracking-api", time: nowIso() }, { status: 200 }),
    origin
  );
}
__name(handleHealth, "handleHealth");
function _tripKpiMask(value) {
  const text22 = safeStr22(value, 220);
  if (!text22) return null;
  if (text22.length <= 10) return text22;
  return `${text22.slice(0, 3)}...${text22.slice(-3)}`;
}
__name(_tripKpiMask, "_tripKpiMask");
function _tripKpiNormalizeToken(value) {
  return String(value ?? "").trim().toLowerCase().replaceAll("-", "_").replaceAll(" ", "_");
}
__name(_tripKpiNormalizeToken, "_tripKpiNormalizeToken");
var TRIP_KPI_TERMINAL_BOOKING_STATUS_SET = /* @__PURE__ */ new Set([
  "cancelled",
  "canceled",
  "deleted",
  "archived",
  "closed",
  "failed",
  "expired",
  "declined",
  "completed",
  "complete",
  "done",
  "finished"
]);
function _tripKpiVisibleAmountCentsFromTrip(trip) {
  const amountCents = _dashboardTripAmountCents(trip?.payment_amount) ?? _dashboardTripAmountCents(trip?.paymentAmount) ?? _dashboardTripAmountCents(trip?.final_amount) ?? _dashboardTripAmountCents(trip?.finalAmount) ?? _dashboardTripAmountCents(trip?.final_total) ?? _dashboardTripAmountCents(trip?.finalTotal) ?? _dashboardTripAmountCents(trip?.total_eur) ?? _dashboardTripAmountCents(trip?.totalEur) ?? _dashboardTripAmountCents(trip?.total) ?? _dashboardTripAmountCents(trip?.booking_details?.booking_total_eur) ?? _dashboardTripAmountCents(trip?.booking_details?.segment_price_eur) ?? _dashboardTripAmountCents(trip?.booking_details?.outbound_price_eur);
  if (!Number.isFinite(Number(amountCents))) return null;
  const normalized2 = Math.round(Number(amountCents));
  return normalized2 > 0 ? normalized2 : null;
}
__name(_tripKpiVisibleAmountCentsFromTrip, "_tripKpiVisibleAmountCentsFromTrip");
function _tripKpiHasVisiblePaymentArtifact(trip, bookingMap = null) {
  const paymentStatus = normalizeCompliancePaymentStatus2(
    trip?.payment_status ?? trip?.paymentStatus
  );
  if (paymentStatus === "pending" || paymentStatus === "failed") return true;
  const paymentMethod = normalizeComplianceText(trip?.payment_method ?? trip?.paymentMethod, "");
  const paymentSource = normalizeComplianceText(trip?.payment_source ?? trip?.paymentSource, "");
  if (paymentMethod && paymentMethod !== "unknown") return true;
  if (paymentSource && paymentSource !== "unknown") return true;
  const paymentId = safeStr22(
    trip?.payment_id ?? trip?.paymentId ?? trip?.mollie_payment_id ?? trip?.molliePaymentId ?? trip?.mollie?.payment_id ?? trip?.mollie?.id,
    160
  );
  if (paymentId) return true;
  const receiptRef = safeStr22(trip?.receipt_reference ?? trip?.receiptReference, 128);
  if (receiptRef) return true;
  const bookingStatus = _tripKpiNormalizeToken(
    trip?.booking_details?.booking_status ?? bookingMap?.booking_status ?? bookingMap?.bookingStatus
  );
  if (bookingStatus.includes("payment")) return true;
  const hasTripProof = !!safeStr22(trip?.trip_id ?? trip?.tripId, 160) || !!safeStr22(trip?.booking_id ?? trip?.bookingId, 160);
  if (hasTripProof && (_tripKpiVisibleAmountCentsFromTrip(trip) ?? 0) > 0) {
    return true;
  }
  return false;
}
__name(_tripKpiHasVisiblePaymentArtifact, "_tripKpiHasVisiblePaymentArtifact");
function _tripKpiClassifyUnpaidCompleted(trip, bookingMap = null) {
  if (!trip || typeof trip !== "object") return "unpaid_completed_tracking_only";
  const tripStatus = normalizeDashboardTripLifecycleStatus(
    trip?.status ?? trip?.lifecycle_status
  );
  const paymentStatus = normalizeCompliancePaymentStatus2(
    trip?.payment_status ?? trip?.paymentStatus
  );
  const amountCents = _tripKpiVisibleAmountCentsFromTrip(trip) ?? 0;
  const tripIdToken = (safeStr22(trip?.trip_id ?? trip?.tripId, 160) ?? "").toLowerCase();
  const hasLegIdentity = !!safeStr22(
    trip?.leg_id ?? trip?.legId ?? trip?.booking_details?.leg_id ?? trip?.booking_details?.legId,
    160
  ) || !!safeStr22(
    trip?.leg_type ?? trip?.legType ?? trip?.booking_details?.leg_type ?? trip?.booking_details?.legType,
    64
  ) || trip?.booking_details?.is_operational_leg === true || trip?.booking_details?.isOperationalLeg === true;
  const isPlannedOperationalLeg = tripIdToken.startsWith("planned_") && hasLegIdentity;
  const isCompletedUnpaidOperationalLegActionable = isPlannedOperationalLeg && tripStatus === "completed" && paymentStatus !== "paid" && amountCents > 0;
  const bookingId = safeStr22(trip?.booking_id ?? trip?.bookingId, 160);
  if (!bookingId || !bookingMap || typeof bookingMap !== "object") {
    if (isCompletedUnpaidOperationalLegActionable) {
      return "unpaid_completed_actionable";
    }
    return "unpaid_completed_tracking_only";
  }
  const bookingStatus = _tripKpiNormalizeToken(
    trip?.booking_details?.booking_status ?? bookingMap?.booking_status ?? bookingMap?.bookingStatus
  );
  const terminal2 = tripStatus === "cancelled" || TRIP_KPI_TERMINAL_BOOKING_STATUS_SET.has(bookingStatus);
  if (terminal2) return "unpaid_completed_stale_unactionable";
  if (!_tripKpiHasVisiblePaymentArtifact(trip, bookingMap)) {
    return "unpaid_completed_missing_visible_payment_artifact";
  }
  return "unpaid_completed_actionable";
}
__name(_tripKpiClassifyUnpaidCompleted, "_tripKpiClassifyUnpaidCompleted");
async function _classifyTripKpiPendingMarker(env, scope2, marker) {
  const bookingId = safeStr22(marker?.booking_id, 160);
  const markerTripId = safeStr22(marker?.trip_id, 160);
  const tripId = markerTripId || (bookingId ? `planned_${bookingId}` : "");
  const paid = normalizeCompliancePaymentStatus2(marker?.payment_status) === "paid";
  const completed = marker?.completed === true;
  const amountCents = Number.isFinite(Number(marker?.payment_amount_cents)) ? Math.max(0, Math.round(Number(marker.payment_amount_cents))) : 0;
  const statusToken = _tripKpiNormalizeToken(
    marker?.status ?? marker?.lifecycle_status ?? marker?.booking_status
  );
  const terminal2 = marker?.terminal === true || TRIP_KPI_TERMINAL_BOOKING_STATUS_SET.has(statusToken);
  let trip = null;
  let bookingMap = null;
  if (tripId) {
    try {
      const resolved = await getScopedOrLegacyTripForScope(env, scope2, tripId);
      trip = resolved?.trip || null;
    } catch (_) {
      trip = null;
    }
  }
  if (bookingId) {
    try {
      const resolved = await getScopedOrLegacyBookingMapForScope(env, scope2, bookingId);
      bookingMap = resolved?.map || null;
    } catch (_) {
      bookingMap = null;
    }
  }
  const hasTrip = !!(trip && recordMatchesTenantCompanyScope(trip, scope2));
  const hasBookingMap = !!(bookingMap && recordMatchesTenantCompanyScope(bookingMap, scope2));
  if (hasTrip) {
    return {
      classification: "pending_marker_resolvable_to_trip",
      active: true,
      clearable: false,
      bookingId,
      tripId,
      hasTrip,
      hasBookingMap,
      amountCents,
      paid,
      completed
    };
  }
  if (terminal2) {
    return {
      classification: "pending_marker_terminal_or_cancelled",
      active: false,
      clearable: true,
      bookingId,
      tripId,
      hasTrip,
      hasBookingMap,
      amountCents,
      paid,
      completed
    };
  }
  if (!bookingId) {
    return {
      classification: "pending_marker_tracking_only_orphan",
      active: false,
      clearable: true,
      bookingId,
      tripId,
      hasTrip,
      hasBookingMap,
      amountCents,
      paid,
      completed
    };
  }
  if (!hasBookingMap && !hasTrip) {
    return {
      classification: "pending_marker_missing_booking",
      active: false,
      clearable: true,
      bookingId,
      tripId,
      hasTrip,
      hasBookingMap,
      amountCents,
      paid,
      completed
    };
  }
  if (paid && amountCents <= 0) {
    return {
      classification: "pending_marker_zero_amount_stale",
      active: false,
      clearable: true,
      bookingId,
      tripId,
      hasTrip,
      hasBookingMap,
      amountCents,
      paid,
      completed
    };
  }
  return {
    classification: "pending_marker_waiting_for_trip",
    active: true,
    clearable: false,
    bookingId,
    tripId,
    hasTrip,
    hasBookingMap,
    amountCents,
    paid,
    completed
  };
}
__name(_classifyTripKpiPendingMarker, "_classifyTripKpiPendingMarker");
function _tripKpiGlobalStructurallyValidLocal(global) {
  if (!global || typeof global !== "object" || Array.isArray(global)) {
    return false;
  }
  const completed = Number(global.completed_rides_count);
  const unpaid = Number(global.unpaid_completed_rides_count);
  return Number.isFinite(completed) && completed >= 0 && Number.isFinite(unpaid) && unpaid >= 0;
}
__name(_tripKpiGlobalStructurallyValidLocal, "_tripKpiGlobalStructurallyValidLocal");
function _tripKpiMonthStructurallyValidLocal(month) {
  if (!month || typeof month !== "object" || Array.isArray(month)) {
    return false;
  }
  const paid = Number(month.monthly_paid_rides_count);
  const income = Number(month.monthly_income_cents);
  return Number.isFinite(paid) && paid >= 0 && Number.isFinite(income) && income >= 0;
}
__name(_tripKpiMonthStructurallyValidLocal, "_tripKpiMonthStructurallyValidLocal");
function _tripKpiAggregatesStructurallyValidLocal(global, month) {
  return _tripKpiGlobalStructurallyValidLocal(global) && _tripKpiMonthStructurallyValidLocal(month);
}
__name(_tripKpiAggregatesStructurallyValidLocal, "_tripKpiAggregatesStructurallyValidLocal");
function _formatKpiReadDiagnosticLocal({
  endpoint,
  source,
  reconcile,
  elapsedMs,
  status
}) {
  const safeElapsed = Number.isFinite(Number(elapsedMs)) ? Math.max(0, Math.min(6e4, Math.round(Number(elapsedMs)))) : 0;
  const safeStatus = Number.isFinite(Number(status)) ? Math.max(100, Math.min(599, Math.round(Number(status)))) : 500;
  return `[KPI_READ] endpoint=${endpoint} source=${source} reconcile=${reconcile} elapsed_ms=${safeElapsed} status=${safeStatus}`;
}
__name(_formatKpiReadDiagnosticLocal, "_formatKpiReadDiagnosticLocal");
function _coerceReconcileDryRun(value, fallback = true) {
  if (value == null) return fallback;
  const token = (safeStr22(value, 16) ?? "").toLowerCase();
  if (!token) return fallback;
  if (token === "0" || token === "false" || token === "no") return false;
  if (token === "1" || token === "true" || token === "yes") return true;
  return fallback;
}
__name(_coerceReconcileDryRun, "_coerceReconcileDryRun");
function _tripKpiAmountCentsFromTrip(trip) {
  return _dashboardTripAmountCents(trip?.payment_amount) ?? _dashboardTripAmountCents(trip?.paymentAmount) ?? _dashboardTripAmountCents(trip?.final_amount) ?? _dashboardTripAmountCents(trip?.finalAmount) ?? _dashboardTripAmountCents(trip?.final_total) ?? _dashboardTripAmountCents(trip?.finalTotal) ?? _dashboardTripAmountCents(trip?.total_eur) ?? _dashboardTripAmountCents(trip?.totalEur) ?? 0;
}
__name(_tripKpiAmountCentsFromTrip, "_tripKpiAmountCentsFromTrip");
async function handleDashboardTripKpisReconcile(req, url, env, origin) {
  requireAdmin(req, url, env);
  const body = req.method === "POST" ? await readJson(req) : {};
  const requiredScope = parseRequiredTenantCompanyScope(req, url, body, {
    returnResponse: true,
    origin
  });
  if (requiredScope instanceof Response) return requiredScope;
  const scope2 = normalizeScopedKeyScope(requiredScope);
  const dryRun = _coerceReconcileDryRun(url.searchParams.get("dry_run"), true) && _coerceReconcileDryRun(body?.dry_run, true);
  const limitRaw = safeStr22(url.searchParams.get("limit"), 16) || safeStr22(body?.limit, 16);
  const limit2 = Math.max(1, Math.min(500, Number(limitRaw) || 100));
  const pendingPrefix = scopedDashboardTripPendingBookingPrefix(scope2);
  const actions = [];
  const summary = {
    scanned_markers: 0,
    resolved_to_trip_materialized: 0,
    cleared_terminal_marker: 0,
    unresolved_pending: 0,
    scanned_unpaid_completed_contribs: 0,
    unpaid_completed_still_unpaid: 0,
    unpaid_completed_resolvable_to_paid: 0,
    unpaid_completed_missing_booking: 0,
    unpaid_completed_missing_trip: 0,
    unpaid_completed_terminal_or_cancelled: 0,
    unpaid_completed_missing_amount: 0
  };
  const expected_deltas = {
    completed_rides_count: 0,
    unpaid_completed_rides_count: 0,
    monthly_paid_rides_count: 0,
    monthly_income_cents: 0
  };
  let cursor = void 0;
  do {
    const page = await env.FLUXIDI_TRACKING.list({ prefix: pendingPrefix, limit: 1e3, cursor });
    for (const keyMeta of page?.keys || []) {
      if (summary.scanned_markers >= limit2) break;
      summary.scanned_markers += 1;
      const markerKey = safeStr22(keyMeta?.name, 260);
      if (!markerKey) continue;
      const marker = await kvGetJson(env.FLUXIDI_TRACKING, markerKey);
      if (!marker || typeof marker !== "object" || Array.isArray(marker)) continue;
      const markerClass = await _classifyTripKpiPendingMarker(env, scope2, marker);
      const bookingId = markerClass?.bookingId || safeStr22(marker?.booking_id, 160);
      const tripId = markerClass?.tripId || safeStr22(marker?.trip_id, 160) || (bookingId ? `planned_${bookingId}` : "");
      const tripStorageKey = tripId ? scopedTripKey(scope2, tripId) : "";
      const trip = tripStorageKey ? await kvGetJson(env.FLUXIDI_TRACKING, tripStorageKey) : null;
      const markerPaid = markerClass?.paid === true;
      if (trip && recordMatchesTenantCompanyScope(trip, scope2)) {
        const projectedTrip = { ...trip };
        if (markerPaid) {
          projectedTrip.payment_status = "paid";
          projectedTrip.paymentStatus = "paid";
          const paidAt = safeStr22(marker?.paid_at, 64);
          if (paidAt) {
            projectedTrip.paid_at = paidAt;
            projectedTrip.paidAt = paidAt;
          }
          const cents = Number(marker?.payment_amount_cents);
          if (Number.isFinite(cents)) {
            const amount = Math.round(cents) / 100;
            projectedTrip.payment_amount = amount;
            projectedTrip.paymentAmount = amount;
          }
        }
        const contribKey = scopedDashboardTripContribKey(scope2, tripId);
        const prev = _readDashboardContribShape(await kvGetJson(env.FLUXIDI_TRACKING, contribKey), tripId);
        const next = _readDashboardContribShape(deriveDashboardTripKpiContribution(projectedTrip), tripId);
        expected_deltas.completed_rides_count += next.completed_rides_count - prev.completed_rides_count;
        expected_deltas.unpaid_completed_rides_count += next.unpaid_completed_rides_count - prev.unpaid_completed_rides_count;
        expected_deltas.monthly_paid_rides_count += next.monthly_paid_rides_count - prev.monthly_paid_rides_count;
        expected_deltas.monthly_income_cents += next.monthly_income_cents - prev.monthly_income_cents;
        summary.resolved_to_trip_materialized += 1;
        actions.push({
          action: "resolved_to_trip_materialized",
          dry_run: dryRun,
          marker_key_preview: _tripKpiMask(markerKey),
          booking_id_preview: _tripKpiMask(bookingId),
          trip_id_preview: _tripKpiMask(tripId),
          marker_classification: markerClass?.classification || "pending_marker_resolvable_to_trip",
          marker_clearable: markerClass?.clearable === true,
          expected_delta: {
            completed_rides_count: next.completed_rides_count - prev.completed_rides_count,
            unpaid_completed_rides_count: next.unpaid_completed_rides_count - prev.unpaid_completed_rides_count,
            monthly_paid_rides_count: next.monthly_paid_rides_count - prev.monthly_paid_rides_count,
            monthly_income_cents: next.monthly_income_cents - prev.monthly_income_cents
          }
        });
        if (!dryRun) {
          await kvPutJson(env.FLUXIDI_TRACKING, tripStorageKey, projectedTrip, TTL_TRIP);
          await materializeTripDashboardKpisBestEffort(
            env,
            scope2,
            projectedTrip,
            "trip_kpi_reconcile_pending_marker"
          );
          await kvDel(env.FLUXIDI_TRACKING, markerKey);
        }
        continue;
      }
      if (markerClass?.clearable === true) {
        summary.cleared_terminal_marker += 1;
        actions.push({
          action: markerClass?.classification || "pending_marker_terminal_or_cancelled",
          dry_run: dryRun,
          marker_key_preview: _tripKpiMask(markerKey),
          booking_id_preview: _tripKpiMask(bookingId),
          trip_id_preview: _tripKpiMask(tripId),
          marker_classification: markerClass?.classification || null,
          marker_clearable: true,
          reason: markerClass?.classification || "pending_marker_terminal_or_cancelled"
        });
        if (!dryRun) {
          await kvDel(env.FLUXIDI_TRACKING, markerKey);
        }
        continue;
      }
      summary.unresolved_pending += 1;
      actions.push({
        action: markerClass?.classification || "unresolved_pending",
        dry_run: dryRun,
        marker_key_preview: _tripKpiMask(markerKey),
        booking_id_preview: _tripKpiMask(bookingId),
        trip_id_preview: _tripKpiMask(tripId),
        marker_classification: markerClass?.classification || null,
        marker_clearable: markerClass?.clearable === true,
        reason: markerPaid ? "pending_paid_booking_no_trip" : "trip_missing"
      });
    }
    if (summary.scanned_markers >= limit2) break;
    cursor = page?.cursor;
    if (page?.list_complete !== false) break;
  } while (cursor);
  const contribPrefix = `tenant:${scope2.tenant_id}:company:${scope2.company_id}:dashboard:trip_kpi_contrib:`;
  let contribCursor = void 0;
  do {
    const page = await env.FLUXIDI_TRACKING.list({ prefix: contribPrefix, limit: 1e3, cursor: contribCursor });
    for (const keyMeta of page?.keys || []) {
      if (summary.scanned_unpaid_completed_contribs >= limit2) break;
      const contribKeyRaw = safeStr22(keyMeta?.name, 280);
      if (!contribKeyRaw) continue;
      const contrib = _readDashboardContribShape(
        await kvGetJson(env.FLUXIDI_TRACKING, contribKeyRaw),
        null
      );
      if (!contrib?.trip_id) continue;
      if (!(contrib.completed_rides_count === 1 && contrib.unpaid_completed_rides_count === 1 && contrib.monthly_paid_rides_count === 0 && contrib.monthly_income_cents === 0)) {
        continue;
      }
      summary.scanned_unpaid_completed_contribs += 1;
      const tripId = safeStr22(contrib.trip_id, 160);
      let tripResolved = null;
      let trip = null;
      try {
        tripResolved = await getScopedOrLegacyTripForScope(env, scope2, tripId);
        trip = tripResolved?.trip || null;
      } catch (_) {
        trip = null;
      }
      if (!trip || !recordMatchesTenantCompanyScope(trip, scope2)) {
        summary.unpaid_completed_missing_trip += 1;
        actions.push({
          action: "unpaid_completed_missing_trip",
          dry_run: dryRun,
          source_key_type: "trip_kpi_contrib",
          contrib_key_preview: _tripKpiMask(contribKeyRaw),
          trip_id_preview: _tripKpiMask(tripId),
          booking_id_preview: null,
          status: "missing",
          payment_status: "unknown",
          amount_cents: null,
          contribution_shape: {
            completed_rides_count: contrib.completed_rides_count,
            unpaid_completed_rides_count: contrib.unpaid_completed_rides_count,
            monthly_paid_rides_count: contrib.monthly_paid_rides_count,
            monthly_income_cents: contrib.monthly_income_cents,
            paid_month: contrib.paid_month
          }
        });
        continue;
      }
      const tripStatus = normalizeDashboardTripLifecycleStatus(trip?.status ?? trip?.lifecycle_status);
      const tripPaymentStatus = normalizeCompliancePaymentStatus2(trip?.payment_status ?? trip?.paymentStatus);
      const bookingId = safeStr22(trip?.booking_id ?? trip?.bookingId, 160);
      const amountCents = _tripKpiAmountCentsFromTrip(trip);
      const markerKey = bookingId ? scopedDashboardTripPendingBookingKey(scope2, bookingId) : "";
      const marker = markerKey ? await kvGetJson(env.FLUXIDI_TRACKING, markerKey) : null;
      const markerPaid = normalizeCompliancePaymentStatus2(marker?.payment_status) === "paid";
      const markerPaidAt = safeStr22(marker?.paid_at, 64);
      const bookingMap = bookingId ? (await getScopedOrLegacyBookingMapForScope(env, scope2, bookingId))?.map : null;
      const bookingMapPaid = normalizeCompliancePaymentStatus2(
        bookingMap?.payment_status ?? bookingMap?.paymentStatus
      ) === "paid";
      const paidProof = tripPaymentStatus === "paid" || markerPaid || bookingMapPaid;
      const classification = _tripKpiClassifyUnpaidCompleted(trip, bookingMap);
      const actionBase = {
        dry_run: dryRun,
        source_key_type: "trip_kpi_contrib",
        contrib_key_preview: _tripKpiMask(contribKeyRaw),
        trip_id_preview: _tripKpiMask(tripId),
        booking_id_preview: _tripKpiMask(bookingId),
        status: tripStatus || "unknown",
        payment_status: tripPaymentStatus || "unknown",
        amount_cents: amountCents > 0 ? amountCents : null,
        month: contrib.paid_month || null,
        contribution_shape: {
          completed_rides_count: contrib.completed_rides_count,
          unpaid_completed_rides_count: contrib.unpaid_completed_rides_count,
          monthly_paid_rides_count: contrib.monthly_paid_rides_count,
          monthly_income_cents: contrib.monthly_income_cents,
          paid_month: contrib.paid_month
        }
      };
      if (classification === "unpaid_completed_stale_unactionable") {
        summary.unpaid_completed_terminal_or_cancelled += 1;
        actions.push({
          action: "unpaid_completed_stale_unactionable",
          ...actionBase
        });
        continue;
      }
      if (classification === "unpaid_completed_tracking_only") {
        summary.unpaid_completed_missing_booking += 1;
        actions.push({
          action: "unpaid_completed_tracking_only",
          ...actionBase
        });
        continue;
      }
      if (classification === "unpaid_completed_missing_visible_payment_artifact") {
        summary.unpaid_completed_missing_amount += 1;
        actions.push({
          action: "unpaid_completed_missing_visible_payment_artifact",
          ...actionBase
        });
        continue;
      }
      if (!paidProof) {
        summary.unpaid_completed_still_unpaid += 1;
        actions.push({
          action: "unpaid_completed_actionable",
          ...actionBase
        });
        continue;
      }
      if (!(amountCents > 0)) {
        summary.unpaid_completed_missing_amount += 1;
        actions.push({
          action: "unpaid_completed_missing_amount",
          ...actionBase
        });
        continue;
      }
      const projectedTrip = { ...trip };
      projectedTrip.payment_status = "paid";
      projectedTrip.paymentStatus = "paid";
      if (markerPaidAt && !safeStr22(projectedTrip?.paid_at ?? projectedTrip?.paidAt, 64)) {
        projectedTrip.paid_at = markerPaidAt;
        projectedTrip.paidAt = markerPaidAt;
      }
      if (!Number.isFinite(Number(projectedTrip?.payment_amount)) && !Number.isFinite(Number(projectedTrip?.paymentAmount))) {
        const amount = Math.round(amountCents) / 100;
        projectedTrip.payment_amount = amount;
        projectedTrip.paymentAmount = amount;
      }
      const prev = _readDashboardContribShape(await kvGetJson(env.FLUXIDI_TRACKING, contribKeyRaw), tripId);
      const next = _readDashboardContribShape(deriveDashboardTripKpiContribution(projectedTrip), tripId);
      const deltaCompleted = next.completed_rides_count - prev.completed_rides_count;
      const deltaUnpaid = next.unpaid_completed_rides_count - prev.unpaid_completed_rides_count;
      const deltaMonthPaid = next.monthly_paid_rides_count - prev.monthly_paid_rides_count;
      const deltaIncome = next.monthly_income_cents - prev.monthly_income_cents;
      expected_deltas.completed_rides_count += deltaCompleted;
      expected_deltas.unpaid_completed_rides_count += deltaUnpaid;
      expected_deltas.monthly_paid_rides_count += deltaMonthPaid;
      expected_deltas.monthly_income_cents += deltaIncome;
      summary.unpaid_completed_resolvable_to_paid += 1;
      actions.push({
        action: "unpaid_completed_resolvable_to_paid",
        ...actionBase,
        expected_delta: {
          completed_rides_count: deltaCompleted,
          unpaid_completed_rides_count: deltaUnpaid,
          monthly_paid_rides_count: deltaMonthPaid,
          monthly_income_cents: deltaIncome
        }
      });
      if (!dryRun) {
        const tripStorageKey = safeStr22(tripResolved?.key, 260) || scopedTripKey(scope2, tripId);
        await kvPutJson(env.FLUXIDI_TRACKING, tripStorageKey, projectedTrip, TTL_TRIP);
        await materializeTripDashboardKpisBestEffort(
          env,
          scope2,
          projectedTrip,
          "trip_kpi_reconcile_unpaid_completed"
        );
        if (markerKey && marker) {
          await kvDel(env.FLUXIDI_TRACKING, markerKey);
        }
      }
    }
    if (summary.scanned_unpaid_completed_contribs >= limit2) break;
    contribCursor = page?.cursor;
    if (page?.list_complete !== false) break;
  } while (contribCursor);
  return withCors(
    json2(
      {
        ok: true,
        dry_run: dryRun,
        tenant_id: scope2.tenant_id,
        company_id: scope2.company_id,
        generated_at: nowIso(),
        summary,
        expected_deltas,
        actions
      },
      { status: 200 }
    ),
    origin
  );
}
__name(handleDashboardTripKpisReconcile, "handleDashboardTripKpisReconcile");
var _KPI_DIAGNOSTICS_CACHE_FRESH_MS = 6e4;
var _KPI_DIAGNOSTICS_CACHE_MAX_AGE_MS = 15 * 6e4;
function _kpiDiagnosticsCacheClassify(cache) {
  if (!cache || typeof cache !== "object" || Array.isArray(cache)) {
    return { present: false, ageMs: null, freshness: "unavailable" };
  }
  const computedAtMs = Date.parse(safeStr22(cache.computed_at_utc, 64) ?? "");
  if (!Number.isFinite(computedAtMs)) {
    return { present: false, ageMs: null, freshness: "unavailable" };
  }
  const ageMs = Date.now() - computedAtMs;
  if (ageMs < 0) {
    return { present: true, ageMs: 0, freshness: "cached_fresh" };
  }
  if (ageMs <= _KPI_DIAGNOSTICS_CACHE_FRESH_MS) {
    return { present: true, ageMs, freshness: "cached_fresh" };
  }
  if (ageMs <= _KPI_DIAGNOSTICS_CACHE_MAX_AGE_MS) {
    return { present: true, ageMs, freshness: "cached_stale" };
  }
  return { present: false, ageMs, freshness: "unavailable" };
}
__name(_kpiDiagnosticsCacheClassify, "_kpiDiagnosticsCacheClassify");
async function handleDashboardTripKpis(req, url, env, origin, ctx) {
  const requiredScope = parseRequiredTenantCompanyScope(req, url, null, {
    returnResponse: true,
    origin
  });
  if (requiredScope instanceof Response) return requiredScope;
  const scope2 = requiredScope;
  const requestStartedAt = Date.now();
  const authStart = Date.now();
  const auth = await requireAdminOrCompanySessionForScope(req, url, env, scope2, origin);
  const authMs = Date.now() - authStart;
  if (!auth.ok) return auth.response;
  const monthRaw = safeStr22(url.searchParams.get("month"), 16);
  const defaultMonth = (/* @__PURE__ */ new Date()).toISOString().slice(0, 7);
  const selectedMonth = monthRaw ? _normalizeDashboardMonth(monthRaw) : defaultMonth;
  const debugRaw = (safeStr22(url.searchParams.get("debug"), 16) ?? "").toLowerCase();
  const debugEnabled = debugRaw === "1" || debugRaw === "true";
  const debugPaidContributorsRaw = (safeStr22(url.searchParams.get("debug_paid_contributors"), 16) ?? "").toLowerCase();
  const debugPaidContributorsEnabled = debugPaidContributorsRaw === "1" || debugPaidContributorsRaw === "true";
  const debugLimit = Math.max(
    1,
    Math.min(200, Number(safeStr22(url.searchParams.get("debug_limit"), 16) || "50") || 50)
  );
  if (!selectedMonth) {
    return withCors(
      json2({ ok: false, error: "month must be YYYY-MM" }, { status: 400 }),
      origin
    );
  }
  const normalizedScope = normalizeScopedKeyScope(scope2);
  const trackingKv = wrapKvBudget(env.FLUXIDI_TRACKING, {
    maxReads: 5,
    maxLists: 0,
    maxWrites: 1,
    maxDeletes: 0
  });
  const gatedEnv = { ...env, FLUXIDI_TRACKING: trackingKv };
  const kpiReadStartedAt = Date.now();
  let globalPrimary;
  let monthPrimary;
  let financeMonthPrimary;
  let debugCountersPrimary;
  let diagnosticsCachePrimary;
  try {
    [
      globalPrimary,
      monthPrimary,
      financeMonthPrimary,
      debugCountersPrimary,
      diagnosticsCachePrimary
    ] = await Promise.all([
      kvGetJson(gatedEnv.FLUXIDI_TRACKING, scopedDashboardTripKpisKey(normalizedScope)).catch(() => null),
      kvGetJson(gatedEnv.FLUXIDI_TRACKING, scopedDashboardTripMonthKpisKey(normalizedScope, selectedMonth)).catch(() => null),
      kvGetJson(gatedEnv.FLUXIDI_TRACKING, scopedDashboardBookingFinanceMonthKey(normalizedScope, selectedMonth)).catch(() => null),
      kvGetJson(gatedEnv.FLUXIDI_TRACKING, scopedDashboardTripDebugKey(normalizedScope)).catch(() => null),
      kvGetJson(gatedEnv.FLUXIDI_TRACKING, scopedDashboardKpiDiagnosticsCacheKey(normalizedScope)).catch(() => null)
    ]);
  } catch (err) {
    if (err instanceof KvBudgetExceededError) {
      logKvPass("HTTP_KV_BUDGET", {
        route: "trip_kpis",
        reason: String(err.kind || "budget"),
        reads: Number(trackingKv.counts?.read || 0),
        lists: Number(trackingKv.counts?.list || 0),
        writes: Number(trackingKv.counts?.write || 0),
        deletes: Number(trackingKv.counts?.delete || 0)
      });
      return withCors(
        json2(
          {
            ok: false,
            error: "trip_kpi_budget_exceeded",
            data_pending: true,
            degraded: true,
            projection_health: "degraded",
            counts_are_authoritative: false,
            tenant_id: normalizedScope.tenant_id,
            company_id: normalizedScope.company_id,
            month: selectedMonth,
            generated_at: nowIso(),
            currency: "EUR"
          },
          { status: 200 }
        ),
        origin
      );
    }
    throw err;
  }
  const globalAggregate = globalPrimary ?? {};
  const monthAggregate = monthPrimary ?? {};
  const financeMonthEarly = financeMonthPrimary ?? {};
  const debugCountersEarly = debugCountersPrimary ?? {};
  const parallelReadMs = Date.now() - kpiReadStartedAt;
  const aggregatesReady = _tripKpiAggregatesStructurallyValidLocal(
    globalAggregate,
    monthAggregate
  );
  const shouldReconcile = false;
  const reconcileResult = null;
  const reconcileMs = 0;
  const kpiReadSource = aggregatesReady ? "aggregate" : "data_pending";
  const kpiReadReconcile = "skipped";
  const global = globalAggregate;
  const month = monthAggregate;
  const financeMonth = financeMonthEarly;
  const debugCounters = debugCountersEarly;
  const diagnosticsCacheInfo = _kpiDiagnosticsCacheClassify(diagnosticsCachePrimary);
  const diagnosticsCache = diagnosticsCacheInfo.present ? diagnosticsCachePrimary : null;
  const diagnosticsSource = diagnosticsCacheInfo.freshness;
  const pendingDiagnostics = diagnosticsCache ? {
    trip_missing: Math.max(0, Math.round(Number(diagnosticsCache.trip_missing) || 0)),
    trip_missing_active: Math.max(
      0,
      Math.round(Number(diagnosticsCache.trip_missing_active) || 0)
    ),
    paid_but_not_completed: Math.max(
      0,
      Math.round(Number(diagnosticsCache.paid_but_not_completed) || 0)
    ),
    paid_but_not_completed_active: Math.max(
      0,
      Math.round(Number(diagnosticsCache.paid_but_not_completed_active) || 0)
    )
  } : {
    trip_missing: 0,
    trip_missing_active: 0,
    paid_but_not_completed: 0,
    paid_but_not_completed_active: 0
  };
  const unpaidActionableStats = diagnosticsCache ? {
    actionable_count: Math.max(
      0,
      Math.round(Number(diagnosticsCache.actionable_count) || 0)
    ),
    tracking_only: Math.max(
      0,
      Math.round(Number(diagnosticsCache.tracking_only) || 0)
    ),
    stale_unactionable: Math.max(
      0,
      Math.round(Number(diagnosticsCache.stale_unactionable) || 0)
    ),
    missing_visible_payment_artifact: Math.max(
      0,
      Math.round(
        Number(diagnosticsCache.missing_visible_payment_artifact) || 0
      )
    ),
    total_scanned_unpaid_completed: Math.max(
      0,
      Math.round(
        Number(diagnosticsCache.total_scanned_unpaid_completed) || 0
      )
    )
  } : {
    actionable_count: 0,
    tracking_only: 0,
    stale_unactionable: 0,
    missing_visible_payment_artifact: 0,
    total_scanned_unpaid_completed: 0
  };
  const diagnosticsComputedAtUtc = diagnosticsCache?.computed_at_utc ?? null;
  const diagnosticsAgeMs = Number.isFinite(diagnosticsCacheInfo.ageMs) ? diagnosticsCacheInfo.ageMs : null;
  const completed = Number.isFinite(Number(global.completed_rides_count)) ? Math.max(0, Math.round(Number(global.completed_rides_count))) : 0;
  const unpaidRaw = Number.isFinite(Number(global.unpaid_completed_rides_count)) ? Math.max(0, Math.round(Number(global.unpaid_completed_rides_count))) : 0;
  const unpaid = diagnosticsCache ? Math.max(0, Math.round(Number(unpaidActionableStats.actionable_count) || 0)) : unpaidRaw;
  const monthPaid = Number.isFinite(Number(month.monthly_paid_rides_count)) ? Math.max(0, Math.round(Number(month.monthly_paid_rides_count))) : 0;
  const monthIncomeCents = Number.isFinite(Number(month.monthly_income_cents)) ? Math.max(0, Math.round(Number(month.monthly_income_cents))) : 0;
  const monthMissingAmount = Number.isFinite(Number(month.monthly_missing_amount_count)) ? Math.max(0, Math.round(Number(month.monthly_missing_amount_count))) : 0;
  const monthBookingPaidCount = Number.isFinite(Number(financeMonth.monthly_paid_bookings_count)) ? Math.max(0, Math.round(Number(financeMonth.monthly_paid_bookings_count))) : 0;
  const monthBookingPaidIncomeCents = Number.isFinite(Number(financeMonth.monthly_paid_bookings_income_cents)) ? Math.max(0, Math.round(Number(financeMonth.monthly_paid_bookings_income_cents))) : 0;
  const monthCancelledPaidCents = Number.isFinite(Number(financeMonth.monthly_cancelled_paid_bookings_cents)) ? Math.max(0, Math.round(Number(financeMonth.monthly_cancelled_paid_bookings_cents))) : 0;
  const monthPendingCreditCents = Number.isFinite(Number(financeMonth.monthly_pending_credit_cents)) ? Math.max(0, Math.round(Number(financeMonth.monthly_pending_credit_cents))) : 0;
  const monthCreditedCents = Number.isFinite(Number(financeMonth.monthly_credited_cents)) ? Math.max(0, Math.round(Number(financeMonth.monthly_credited_cents))) : 0;
  const pendingCreditCents = monthPendingCreditCents;
  const creditedCents = monthCreditedCents;
  const bookingFinanceNetCents = _pickFinanceMonthCents(
    financeMonth,
    "monthly_net_revenue_cents",
    "monthly_net_income_cents",
    "booking_finance_monthly_net_revenue_cents",
    "booking_finance_monthly_net_income_cents"
  );
  const bookingFinanceGrossCents = _pickFinanceMonthCents(
    financeMonth,
    "monthly_gross_paid_income_cents",
    "monthly_paid_bookings_income_cents",
    "booking_finance_monthly_gross_income_cents"
  ) ?? monthBookingPaidIncomeCents;
  const bookingFinanceCreditedCents = _pickFinanceMonthCents(financeMonth, "monthly_credited_cents", "booking_finance_monthly_credited_cents") ?? creditedCents;
  const bookingFinanceRefundedCents = _pickFinanceMonthCents(financeMonth, "monthly_refunded_cents", "booking_finance_monthly_refunded_cents") ?? 0;
  const bookingFinanceRetainedCents = _pickFinanceMonthCents(financeMonth, "monthly_retained_cents", "booking_finance_monthly_retained_cents") ?? 0;
  const bookingFinanceAmbiguousManualCents = _pickFinanceMonthCents(
    financeMonth,
    "monthly_ambiguous_manual_cents",
    "booking_finance_monthly_ambiguous_manual_cents"
  ) ?? 0;
  const bookingFinanceManualUnresolvedCount = _pickFinanceMonthCents(financeMonth, "manual_unresolved_count", "booking_finance_manual_unresolved_count") ?? 0;
  const bookingFinanceNetIncomeCents = bookingFinanceNetCents != null ? bookingFinanceNetCents : Math.max(0, monthBookingPaidIncomeCents - pendingCreditCents - creditedCents);
  const selectedMonthlyIncomeSource = monthIncomeCents > 0 ? "completed_trip_kpi" : "booking_finance_fallback";
  const selectedMonthlyIncomeCents = selectedMonthlyIncomeSource === "completed_trip_kpi" ? monthIncomeCents : monthBookingPaidIncomeCents;
  const dashboardMonthlyIncomeCents = selectedMonthlyIncomeCents;
  const blendedMonthlyIncomeCents = dashboardMonthlyIncomeCents;
  const grossMonthlyIncomeCents = dashboardMonthlyIncomeCents;
  let netMonthlyIncomeCents = dashboardMonthlyIncomeCents;
  let monthlyNetIncomeCents = dashboardMonthlyIncomeCents;
  let monthlyNetRevenueCents = dashboardMonthlyIncomeCents;
  let selectedNetRevenueSource = selectedMonthlyIncomeSource;
  if (bookingFinanceNetCents != null) {
    netMonthlyIncomeCents = bookingFinanceNetCents;
    monthlyNetIncomeCents = bookingFinanceNetCents;
    monthlyNetRevenueCents = bookingFinanceNetCents;
    selectedNetRevenueSource = "booking_finance_net";
    console.log(
      `[TRIP_KPI][NET_REVENUE_SOURCE] tenant=${maskScopeForTripKpiLog(normalizedScope.tenant_id)} company=${maskScopeForTripKpiLog(normalizedScope.company_id)} month=${selectedMonth} source=booking_finance_net net_cents=${bookingFinanceNetCents} gross_cents=${bookingFinanceGrossCents} credited_cents=${bookingFinanceCreditedCents} refunded_cents=${bookingFinanceRefundedCents}`
    );
  } else {
    console.log(
      `[TRIP_KPI][NET_REVENUE_SOURCE] tenant=${maskScopeForTripKpiLog(normalizedScope.tenant_id)} company=${maskScopeForTripKpiLog(normalizedScope.company_id)} month=${selectedMonth} source=gross_fallback reason=missing_booking_finance_net`
    );
  }
  console.log(
    `[DASHBOARD_REVENUE][DISPLAY_SOURCE] tenant=${maskScopeForTripKpiLog(normalizedScope.tenant_id)} company=${maskScopeForTripKpiLog(normalizedScope.company_id)} month=${selectedMonth} source=${selectedMonthlyIncomeSource} trip_cents=${monthIncomeCents} booking_finance_cents=${monthBookingPaidIncomeCents} booking_finance_net_cents=${bookingFinanceNetIncomeCents} selected_cents=${selectedMonthlyIncomeCents}`
  );
  const scopeMismatchCount = Number.isFinite(Number(debugCounters.scope_mismatch)) ? Math.max(0, Math.round(Number(debugCounters.scope_mismatch))) : 0;
  const missingAmountDebugCount = Number.isFinite(Number(debugCounters.missing_amount)) ? Math.max(0, Math.round(Number(debugCounters.missing_amount))) : 0;
  const payload = {
    ok: true,
    tenant_id: normalizedScope.tenant_id,
    company_id: normalizedScope.company_id,
    month: selectedMonth,
    generated_at: nowIso(),
    currency: "EUR",
    completed_rides_count: completed,
    unpaid_completed_rides_count_raw: unpaidRaw,
    unpaid_completed_rides_count: unpaid,
    monthly_paid_rides_count: monthPaid,
    monthly_income_eur: blendedMonthlyIncomeCents / 100,
    monthly_income_cents: blendedMonthlyIncomeCents,
    gross_monthly_income_cents: grossMonthlyIncomeCents,
    gross_monthly_income_eur: grossMonthlyIncomeCents / 100,
    pending_credit_cents: pendingCreditCents,
    pending_credit_eur: pendingCreditCents / 100,
    monthly_credited_cents: creditedCents,
    monthly_credited_eur: creditedCents / 100,
    credited_cents: creditedCents,
    credited_eur: creditedCents / 100,
    net_monthly_income_cents: netMonthlyIncomeCents,
    net_monthly_income_eur: netMonthlyIncomeCents / 100,
    monthly_net_income_cents: monthlyNetIncomeCents,
    monthly_net_income_eur: monthlyNetIncomeCents / 100,
    monthly_net_revenue_cents: monthlyNetRevenueCents,
    monthly_net_revenue_eur: monthlyNetRevenueCents / 100,
    monthly_paid_bookings_count: monthBookingPaidCount,
    monthly_paid_bookings_income_cents: monthBookingPaidIncomeCents,
    monthly_paid_bookings_income_eur: monthBookingPaidIncomeCents / 100,
    trip_monthly_income_cents: monthIncomeCents,
    trip_monthly_income_eur: monthIncomeCents / 100,
    booking_finance_monthly_income_cents: monthBookingPaidIncomeCents,
    booking_finance_monthly_income_eur: monthBookingPaidIncomeCents / 100,
    booking_finance_net_income_cents: bookingFinanceNetIncomeCents,
    booking_finance_net_income_eur: bookingFinanceNetIncomeCents / 100,
    booking_finance_net_monthly_income_cents: bookingFinanceNetCents ?? bookingFinanceNetIncomeCents,
    booking_finance_net_monthly_revenue_cents: bookingFinanceNetCents ?? bookingFinanceNetIncomeCents,
    booking_finance_gross_monthly_income_cents: bookingFinanceGrossCents,
    booking_finance_credited_cents: bookingFinanceCreditedCents,
    booking_finance_refunded_cents: bookingFinanceRefundedCents,
    booking_finance_retained_cents: bookingFinanceRetainedCents,
    booking_finance_ambiguous_manual_cents: bookingFinanceAmbiguousManualCents,
    booking_finance_manual_unresolved_count: bookingFinanceManualUnresolvedCount,
    dashboard_monthly_income_cents: dashboardMonthlyIncomeCents,
    dashboard_monthly_income_eur: dashboardMonthlyIncomeCents / 100,
    selected_monthly_income_source: selectedNetRevenueSource,
    trip_kpi_reconcile_scanned: Number.isFinite(Number(reconcileResult?.trip_kpi_reconcile_scanned)) ? Math.max(0, Math.round(Number(reconcileResult.trip_kpi_reconcile_scanned))) : 0,
    trip_kpi_reconcile_recovered_missing_amount_count: Number.isFinite(
      Number(reconcileResult?.trip_kpi_reconcile_recovered_missing_amount_count)
    ) ? Math.max(
      0,
      Math.round(Number(reconcileResult.trip_kpi_reconcile_recovered_missing_amount_count))
    ) : 0,
    trip_kpi_reconcile_recovered_missing_amount_cents: Number.isFinite(
      Number(reconcileResult?.trip_kpi_reconcile_recovered_missing_amount_cents)
    ) ? Math.max(
      0,
      Math.round(Number(reconcileResult.trip_kpi_reconcile_recovered_missing_amount_cents))
    ) : 0,
    trip_kpi_reconcile_sum_cents: Number.isFinite(
      Number(reconcileResult?.trip_kpi_reconcile_sum_cents)
    ) ? Math.max(0, Math.round(Number(reconcileResult.trip_kpi_reconcile_sum_cents))) : 0,
    monthly_cancelled_paid_bookings_cents: monthCancelledPaidCents,
    monthly_cancelled_paid_bookings_eur: monthCancelledPaidCents / 100,
    // COMPANY-DATA-LATENCY-P0-REPAIR-1 (Part B): expose the truthfulness of
    // the diagnostic block so the client can render "—" instead of "0"
    // when the background scan hasn't completed yet. Existing integer
    // fields keep their pre-repair contract; the new fields are additive.
    diagnostics_source: diagnosticsSource,
    diagnostics_computed_at_utc: diagnosticsComputedAtUtc,
    diagnostics_age_ms: diagnosticsAgeMs,
    diagnostics: {
      trip_missing: pendingDiagnostics.trip_missing,
      trip_missing_active: pendingDiagnostics.trip_missing_active,
      paid_but_not_completed: pendingDiagnostics.paid_but_not_completed,
      paid_but_not_completed_active: pendingDiagnostics.paid_but_not_completed_active,
      completed_but_unpaid: unpaid,
      completed_but_unpaid_raw: unpaidRaw,
      unpaid_completed_actionable: unpaidActionableStats.actionable_count,
      unpaid_completed_stale_unactionable: unpaidActionableStats.stale_unactionable,
      unpaid_completed_tracking_only: unpaidActionableStats.tracking_only,
      unpaid_completed_missing_visible_payment_artifact: unpaidActionableStats.missing_visible_payment_artifact,
      completed_paid_contributed: monthPaid,
      scope_mismatch: scopeMismatchCount,
      scope_mismatch_historical: scopeMismatchCount,
      missing_amount: Math.max(monthMissingAmount, missingAmountDebugCount),
      missing_amount_historical: missingAmountDebugCount,
      source: diagnosticsSource,
      computed_at_utc: diagnosticsComputedAtUtc,
      age_ms: diagnosticsAgeMs
    },
    completeness: {
      level: "forward_aggregate",
      notes: [
        "Aggregates are maintained from KPI materialization time forward.",
        "Historical retained trips may require a rebuild/backfill endpoint."
      ]
    },
    counts_are_authoritative: aggregatesReady === true,
    projection_health: aggregatesReady ? "ok" : "missing"
  };
  if (!aggregatesReady) {
    payload.data_pending = true;
    payload.degraded = true;
  } else if (diagnosticsSource === "cached_stale" || diagnosticsSource === "unavailable") {
    payload.stale = diagnosticsSource === "cached_stale";
    payload.degraded = diagnosticsSource === "unavailable";
  }
  if (debugEnabled) {
    payload.debug_enabled = true;
    payload.debug_limit = debugLimit;
    payload.debug_note = "debug samples require /admin/dashboard/trip-kpis/reconcile";
  }
  if (debugPaidContributorsEnabled) {
    payload.trip_paid_contributor_debug_rows = [];
    payload.trip_paid_contributor_debug_included = 0;
  }
  console.log(
    _formatKpiReadDiagnosticLocal({
      endpoint: "trip",
      source: kpiReadSource,
      reconcile: kpiReadReconcile,
      elapsedMs: Date.now() - kpiReadStartedAt,
      status: 200
    })
  );
  const totalMs = Date.now() - requestStartedAt;
  console.log(
    `[TRIP_KPI_TIMING] endpoint=trip auth_ms=${authMs} parallel_read_ms=${parallelReadMs} reconcile_ms=${reconcileMs} total_ms=${totalMs} kpi_source=${kpiReadSource} diagnostics_source=${diagnosticsSource}`
  );
  return withCors(
    json2(payload, { status: 200 }),
    origin
  );
}
__name(handleDashboardTripKpis, "handleDashboardTripKpis");
async function _listAllKvKeysByPrefix(kv, prefix) {
  if (!kv || !prefix) return [];
  const out = [];
  let cursor = void 0;
  do {
    const page = await kv.list({ prefix, limit: 1e3, cursor });
    for (const item of page?.keys || []) {
      const name = safeStr22(item?.name, 320);
      if (name) out.push(name);
    }
    cursor = page?.cursor;
    if (page?.list_complete !== false) break;
    if (!cursor) break;
  } while (cursor);
  return out;
}
__name(_listAllKvKeysByPrefix, "_listAllKvKeysByPrefix");
function _buildDashboardKpiResetCategories(scope2, { includeTripHistory = false } = {}) {
  const categories = [
    {
      id: "trip_kpis_global",
      kind: "exact",
      keys: [scopedDashboardTripKpisKey(scope2)]
    },
    {
      id: "trip_kpi_debug",
      kind: "exact",
      keys: [scopedDashboardTripDebugKey(scope2)]
    },
    {
      id: "trip_kpis_month",
      kind: "prefix",
      prefix: scopedDashboardTripKpisMonthPrefix(scope2)
    },
    {
      id: "trip_kpi_contrib",
      kind: "prefix",
      prefix: scopedDashboardTripKpiContribPrefix(scope2)
    },
    {
      id: "trip_kpi_pending_booking",
      kind: "prefix",
      prefix: scopedDashboardTripPendingBookingPrefix(scope2)
    },
    {
      id: "booking_finance_month",
      kind: "prefix",
      prefix: scopedDashboardBookingFinanceMonthPrefix(scope2)
    },
    {
      id: "booking_finance_contrib",
      kind: "prefix",
      prefix: scopedDashboardBookingFinanceContribPrefix(scope2)
    }
  ];
  if (includeTripHistory) {
    categories.push(
      {
        id: "trip_records",
        kind: "prefix",
        prefix: scopedTripRecordsPrefix(scope2)
      },
      {
        id: "trips_index",
        kind: "exact",
        keys: [scopedTripsIndexKey(scope2)]
      },
      {
        id: "trips_index_driver",
        kind: "prefix",
        prefix: `${scopedTripsIndexKey(scope2)}:`
      }
    );
  }
  return categories;
}
__name(_buildDashboardKpiResetCategories, "_buildDashboardKpiResetCategories");
async function _collectExistingDashboardKpiResetCategoryKeys(env, category) {
  if (!env?.FLUXIDI_TRACKING) return [];
  if (category.kind === "exact") {
    const out = [];
    for (const key2 of category.keys || []) {
      if (!key2) continue;
      try {
        const raw = await env.FLUXIDI_TRACKING.get(key2);
        if (raw != null) out.push(key2);
      } catch (_) {
      }
    }
    return out;
  }
  if (category.kind === "prefix" && category.prefix) {
    return await _listAllKvKeysByPrefix(env.FLUXIDI_TRACKING, category.prefix);
  }
  return [];
}
__name(_collectExistingDashboardKpiResetCategoryKeys, "_collectExistingDashboardKpiResetCategoryKeys");
async function _readCurrentDashboardKpiValues(env, scope2, month) {
  const normalizedScope = normalizeScopedKeyScope(scope2);
  const global = await kvGetJson(env.FLUXIDI_TRACKING, scopedDashboardTripKpisKey(normalizedScope)) ?? {};
  const monthData = month ? await kvGetJson(
    env.FLUXIDI_TRACKING,
    scopedDashboardTripMonthKpisKey(normalizedScope, month)
  ) ?? {} : {};
  const financeMonth = month ? await kvGetJson(
    env.FLUXIDI_TRACKING,
    scopedDashboardBookingFinanceMonthKey(normalizedScope, month)
  ) ?? {} : {};
  const completed = Number.isFinite(Number(global.completed_rides_count)) ? Math.max(0, Math.round(Number(global.completed_rides_count))) : 0;
  const unpaid = Number.isFinite(Number(global.unpaid_completed_rides_count)) ? Math.max(0, Math.round(Number(global.unpaid_completed_rides_count))) : 0;
  const monthIncomeCents = Number.isFinite(Number(monthData.monthly_income_cents)) ? Math.max(0, Math.round(Number(monthData.monthly_income_cents))) : 0;
  const bookingFinanceIncomeCents = Number.isFinite(
    Number(financeMonth.monthly_paid_bookings_income_cents)
  ) ? Math.max(0, Math.round(Number(financeMonth.monthly_paid_bookings_income_cents))) : 0;
  return {
    completed_rides_count: completed,
    unpaid_completed_rides_count: unpaid,
    monthly_income_cents: Math.max(monthIncomeCents, bookingFinanceIncomeCents),
    monthly_paid_bookings_income_cents: bookingFinanceIncomeCents,
    trip_monthly_income_cents: monthIncomeCents
  };
}
__name(_readCurrentDashboardKpiValues, "_readCurrentDashboardKpiValues");
async function handleDevDashboardKpisReset(req, url, env, origin, { forceDryRun = false } = {}) {
  requireAdmin(req, url, env);
  if (!allowDevResetEndpoints(env)) {
    return withCors(
      json2({ ok: false, error: "dev reset endpoints are disabled" }, { status: 403 }),
      origin
    );
  }
  let body = {};
  if (req.method === "POST") {
    try {
      body = await readJson(req);
    } catch (_) {
      body = {};
    }
  }
  const requiredScope = parseRequiredTenantCompanyScope(req, url, body, {
    returnResponse: true,
    origin
  });
  if (requiredScope instanceof Response) return requiredScope;
  const tenantId = requiredScope.tenant_id;
  const companyId = requiredScope.company_id;
  if (_isUnsafeDevResetScope(tenantId, companyId)) {
    return withCors(
      json2({ ok: false, error: "unsafe_legacy_scope_not_allowed" }, { status: 400 }),
      origin
    );
  }
  const dryRun = forceDryRun || _coerceReconcileDryRun(url.searchParams.get("dry_run"), true) && _coerceReconcileDryRun(body?.dry_run ?? body?.dryRun, true);
  if (!dryRun && !allowDevResetExecute(env)) {
    return withCors(json2({ ok: false, error: "dev_reset_disabled" }, { status: 403 }), origin);
  }
  const includeTripHistory = _coerceBoolean(
    body?.include_trip_history ?? body?.includeTripHistory ?? url.searchParams.get("include_trip_history"),
    false
  );
  const monthRaw = safeStr22(url.searchParams.get("month") ?? body?.month, 16);
  const month = monthRaw ? _normalizeDashboardMonth(monthRaw) : (/* @__PURE__ */ new Date()).toISOString().slice(0, 7);
  if (!env?.FLUXIDI_TRACKING) {
    return withCors(
      json2({ ok: false, error: "FLUXIDI_TRACKING binding missing" }, { status: 500 }),
      origin
    );
  }
  const normalizedScope = normalizeScopedKeyScope(requiredScope);
  const categoryDefs = _buildDashboardKpiResetCategories(normalizedScope, { includeTripHistory });
  const categories = [];
  const keysByCategory = {};
  let wouldDeleteTotal = 0;
  for (const def of categoryDefs) {
    const keys = await _collectExistingDashboardKpiResetCategoryKeys(env, def);
    keysByCategory[def.id] = keys;
    wouldDeleteTotal += keys.length;
    categories.push({
      id: def.id,
      kind: def.kind,
      count: keys.length,
      sample_key_previews: keys.slice(0, 5).map((key2) => _tripKpiMask(key2))
    });
  }
  const currentDashboardValues = await _readCurrentDashboardKpiValues(env, normalizedScope, month);
  const postResetExpected = {
    completed_rides_count: 0,
    unpaid_completed_rides_count: 0,
    monthly_income_cents: 0,
    monthly_paid_bookings_income_cents: 0
  };
  const errors = [];
  let deletedTotal = 0;
  const deletedByCategory = {};
  if (!dryRun) {
    for (const def of categoryDefs) {
      const keys = keysByCategory[def.id] || [];
      let deleted = 0;
      for (const key2 of keys) {
        try {
          await env.FLUXIDI_TRACKING.delete(key2);
          deleted += 1;
          deletedTotal += 1;
        } catch (err) {
          errors.push({
            category: def.id,
            key_preview: _tripKpiMask(key2),
            error: safeStr22(String(err?.message || err), 120)
          });
        }
      }
      deletedByCategory[def.id] = deleted;
    }
    console.log(
      `[DEV_DASHBOARD_KPI_RESET][EXECUTE] tenant=${_tripKpiMask(tenantId)} company=${_tripKpiMask(companyId)} deleted=${deletedTotal} include_trip_history=${includeTripHistory ? "true" : "false"} errors=${errors.length}`
    );
  } else {
    console.log(
      `[DEV_DASHBOARD_KPI_RESET][DRY_RUN] tenant=${_tripKpiMask(tenantId)} company=${_tripKpiMask(companyId)} would_delete=${wouldDeleteTotal} include_trip_history=${includeTripHistory ? "true" : "false"}`
    );
  }
  return withCors(
    json2(
      {
        ok: true,
        dry_run: dryRun,
        tenant_id: tenantId,
        company_id: companyId,
        month,
        include_trip_history: includeTripHistory,
        categories,
        would_delete_total: wouldDeleteTotal,
        current_dashboard_values: currentDashboardValues,
        post_reset_expected: postResetExpected,
        ...dryRun ? {} : {
          deleted_total: deletedTotal,
          deleted_by_category: deletedByCategory,
          errors
        },
        message: dryRun ? "Dry-run only. Scoped dashboard KPI reset candidates collected." : "Scoped dashboard KPI reset completed."
      },
      { status: 200 }
    ),
    origin
  );
}
__name(handleDevDashboardKpisReset, "handleDevDashboardKpisReset");
var STREET_HISTORY_CANONICAL_VERSION = "1B";
function _streetHistoryCanonicalKind(kind) {
  return String(kind ?? "").trim().toLowerCase();
}
__name(_streetHistoryCanonicalKind, "_streetHistoryCanonicalKind");
function _streetHistoryCanonicalId(id22) {
  return String(id22 ?? "").trim();
}
__name(_streetHistoryCanonicalId, "_streetHistoryCanonicalId");
function _streetHistoryBookingDetails(trip) {
  const d = trip?.booking_details;
  return d && typeof d === "object" && !Array.isArray(d) ? d : {};
}
__name(_streetHistoryBookingDetails, "_streetHistoryBookingDetails");
function _streetHistoryTripIdOf(trip) {
  return _streetHistoryCanonicalId(trip?.trip_id ?? trip?.tripId);
}
__name(_streetHistoryTripIdOf, "_streetHistoryTripIdOf");
function _streetHistoryBookingIdOf(trip) {
  return _streetHistoryCanonicalId(trip?.booking_id ?? trip?.bookingId);
}
__name(_streetHistoryBookingIdOf, "_streetHistoryBookingIdOf");
function _streetHistoryParentBookingId(trip) {
  const details = _streetHistoryBookingDetails(trip);
  return _streetHistoryCanonicalId(
    trip?.parent_booking_id ?? trip?.parentBookingId ?? details.parent_booking_id ?? details.parentBookingId
  );
}
__name(_streetHistoryParentBookingId, "_streetHistoryParentBookingId");
function _streetHistoryLinkedTrackingTripId(trip) {
  const details = _streetHistoryBookingDetails(trip);
  return _streetHistoryCanonicalId(
    trip?.linked_tracking_trip_id ?? trip?.linkedTrackingTripId ?? details.linked_tracking_trip_id ?? details.linkedTrackingTripId
  );
}
__name(_streetHistoryLinkedTrackingTripId, "_streetHistoryLinkedTrackingTripId");
function _streetHistoryIsOperationalLeg(trip) {
  const details = _streetHistoryBookingDetails(trip);
  if (details.is_operational_leg === true || details.isOperationalLeg === true) {
    return true;
  }
  if (trip?.is_operational_leg === true || trip?.isOperationalLeg === true) {
    return true;
  }
  const legId = _streetHistoryCanonicalId(
    trip?.leg_id ?? trip?.legId ?? details.leg_id ?? details.legId
  );
  const legType = _streetHistoryCanonicalId(
    trip?.leg_type ?? trip?.legType ?? details.leg_type ?? details.legType
  );
  return legId !== "" || legType !== "";
}
__name(_streetHistoryIsOperationalLeg, "_streetHistoryIsOperationalLeg");
function _streetHistoryCanonicalRideKey(trip, resolvedLink) {
  if (_streetHistoryCanonicalKind(trip?.kind) === "direct") {
    return _streetHistoryTripIdOf(trip) || _streetHistoryBookingIdOf(trip);
  }
  const linked = _streetHistoryLinkedTrackingTripId(trip) || _streetHistoryCanonicalId(resolvedLink);
  if (linked) return linked;
  return _streetHistoryParentBookingId(trip) || _streetHistoryBookingIdOf(trip);
}
__name(_streetHistoryCanonicalRideKey, "_streetHistoryCanonicalRideKey");
function _streetHistoryFingerprint(value) {
  const s = _streetHistoryCanonicalId(value);
  if (!s) return "-";
  let h = 2166136261;
  for (let i = 0; i < s.length; i += 1) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return (h >>> 0).toString(36).padStart(7, "0").slice(0, 8);
}
__name(_streetHistoryFingerprint, "_streetHistoryFingerprint");
function _streetHistoryTripShape(trip, resolvedLink) {
  const kind = _streetHistoryCanonicalKind(trip?.kind) || "unknown";
  const details = _streetHistoryBookingDetails(trip);
  const bookingId = _streetHistoryBookingIdOf(trip);
  const parentBookingId = _streetHistoryParentBookingId(trip);
  const tripId = _streetHistoryTripIdOf(trip);
  const linked = _streetHistoryLinkedTrackingTripId(trip) || _streetHistoryCanonicalId(resolvedLink);
  const canonicalKey = _streetHistoryCanonicalRideKey(trip, resolvedLink);
  const legTypeRaw = _streetHistoryCanonicalId(
    trip?.leg_type ?? trip?.legType ?? details.leg_type ?? details.legType
  ).toLowerCase();
  const legType = legTypeRaw === "outbound" || legTypeRaw === "return" ? legTypeRaw : "none";
  let tripIdShape = "other";
  if (kind === "direct") {
    tripIdShape = "direct";
  } else if (bookingId && tripId === `planned_${bookingId}` || parentBookingId && tripId === `planned_${parentBookingId}`) {
    tripIdShape = "planned_exact";
  } else if (bookingId && tripId.startsWith(`planned_${bookingId}_`) || parentBookingId && tripId.startsWith(`planned_${parentBookingId}_`)) {
    tripIdShape = "planned_suffix";
  } else if (tripId.startsWith("planned_")) {
    tripIdShape = "planned_other";
  }
  const amount = Number(trip?.total_eur);
  const amountBucket = !Number.isFinite(amount) ? "missing" : amount > 0 ? "positive" : "zero";
  const distance2 = Number(trip?.km_total);
  const sourceType = _streetHistoryCanonicalId(trip?.source).toLowerCase() === "street_ride" ? "streetRide" : kind === "planned" ? "planned" : kind === "direct" ? "streetRide" : "unknown";
  return {
    kind,
    tripIdShape,
    hasBookingId: bookingId !== "",
    hasParentBookingId: parentBookingId !== "",
    hasTrackingTripId: tripId !== "",
    hasLinkedTrackingTripId: linked !== "",
    hasCanonicalKey: canonicalKey !== "",
    isOperationalLeg: _streetHistoryIsOperationalLeg(trip),
    legType,
    sourceType,
    amountBucket,
    hasAmount: Number.isFinite(amount) && amount > 0,
    hasDistance: Number.isFinite(distance2) && distance2 > 0,
    bookingKeyHash: _streetHistoryFingerprint(bookingId),
    parentKeyHash: _streetHistoryFingerprint(parentBookingId),
    trackingKeyHash: _streetHistoryFingerprint(tripId),
    canonicalKeyHash: _streetHistoryFingerprint(canonicalKey)
  };
}
__name(_streetHistoryTripShape, "_streetHistoryTripShape");
function _streetHistoryMaybeLogLiveShape(trip, resolvedLink) {
  const kind = _streetHistoryCanonicalKind(trip?.kind);
  const shape = _streetHistoryTripShape(trip, resolvedLink);
  const isPlannedOutbound = kind === "planned" && shape.legType === "outbound";
  if (kind !== "direct" && !isPlannedOutbound && !shape.isOperationalLeg) return;
  console.log(
    `[STREET_HISTORY_LIVE_SHAPE] kind=${shape.kind} tripIdShape=${shape.tripIdShape} hasBookingId=${shape.hasBookingId} hasParentBookingId=${shape.hasParentBookingId} hasTrackingTripId=${shape.hasTrackingTripId} hasLinkedTrackingTripId=${shape.hasLinkedTrackingTripId} hasCanonicalKey=${shape.hasCanonicalKey} isOperationalLeg=${shape.isOperationalLeg} legType=${shape.legType} sourceType=${shape.sourceType} amountBucket=${shape.amountBucket} bookingKeyHash=${shape.bookingKeyHash} parentKeyHash=${shape.parentKeyHash} trackingKeyHash=${shape.trackingKeyHash} canonicalKeyHash=${shape.canonicalKeyHash}`
  );
}
__name(_streetHistoryMaybeLogLiveShape, "_streetHistoryMaybeLogLiveShape");
function _streetHistoryDirectRideKeySet(trips) {
  const keys = /* @__PURE__ */ new Set();
  for (const trip of trips) {
    if (_streetHistoryCanonicalKind(trip?.kind) !== "direct") continue;
    const tripId = _streetHistoryTripIdOf(trip);
    const bookingId = _streetHistoryBookingIdOf(trip);
    if (tripId) keys.add(tripId);
    if (bookingId) keys.add(bookingId);
  }
  return keys;
}
__name(_streetHistoryDirectRideKeySet, "_streetHistoryDirectRideKeySet");
function _streetHistoryIsCanonicalPlannedShadow(trip, directKeys, resolvedLink) {
  if (_streetHistoryCanonicalKind(trip?.kind) !== "planned") return false;
  const linked = _streetHistoryLinkedTrackingTripId(trip) || _streetHistoryCanonicalId(resolvedLink);
  if (linked && directKeys.has(linked)) return true;
  const parent = _streetHistoryParentBookingId(trip);
  const bookingId = _streetHistoryBookingIdOf(trip);
  const ownedKey = [parent, bookingId].find((k) => k && directKeys.has(k));
  if (!ownedKey) return false;
  if (_streetHistoryIsOperationalLeg(trip)) return true;
  const tripId = _streetHistoryTripIdOf(trip);
  return tripId === `planned_${ownedKey}` || tripId.startsWith(`planned_${ownedKey}_`) || tripId === `planned_${bookingId}` || tripId.startsWith(`planned_${bookingId}_`);
}
__name(_streetHistoryIsCanonicalPlannedShadow, "_streetHistoryIsCanonicalPlannedShadow");
function _streetRideBookingBlocksShadowWrite({
  source = "",
  rideType = "",
  trackingTripId = "",
  directTripExists = false
} = {}) {
  const isStreetDirect = _streetHistoryCanonicalId(source).toLowerCase() === "street_ride" || _streetHistoryCanonicalId(rideType).toLowerCase() === "direct";
  return Boolean(
    isStreetDirect && _streetHistoryCanonicalId(trackingTripId) && directTripExists
  );
}
__name(_streetRideBookingBlocksShadowWrite, "_streetRideBookingBlocksShadowWrite");
function dedupeCanonicalStreetHistoryTrips(trips, resolvedLinks) {
  const list = Array.isArray(trips) ? trips : [];
  const directKeys = _streetHistoryDirectRideKeySet(list);
  const links = resolvedLinks instanceof Map ? resolvedLinks : /* @__PURE__ */ new Map();
  const linkFor = /* @__PURE__ */ __name((trip) => _streetHistoryCanonicalId(
    links.get(_streetHistoryParentBookingId(trip)) || links.get(_streetHistoryBookingIdOf(trip)) || ""
  ), "linkFor");
  const kept = [];
  let dropped = 0;
  for (const trip of list) {
    const kind = _streetHistoryCanonicalKind(trip?.kind);
    const resolvedLink = kind === "planned" ? linkFor(trip) : "";
    const rideKey = _streetHistoryCanonicalRideKey(trip, resolvedLink);
    const shadow = _streetHistoryIsCanonicalPlannedShadow(
      trip,
      directKeys,
      resolvedLink
    );
    _streetHistoryMaybeLogLiveShape(trip, resolvedLink);
    if (trip && typeof trip === "object") {
      trip.canonical_physical_ride_key = rideKey || null;
      trip.canonical_trip_kind = kind === "direct" ? "direct" : shadow ? "operational_shadow" : "planned";
      trip.is_operational_shadow = shadow;
      const linked = _streetHistoryLinkedTrackingTripId(trip) || resolvedLink;
      if (linked) trip.linked_tracking_trip_id = linked;
    }
    if (shadow) {
      dropped += 1;
      console.log(
        "[STREET_HISTORY_CANONICAL] phase=dedupe source=tracking hasLinkedTrip=true hasLinkedBooking=true countContribution=0 reason=street_planned_leg_shadow_of_direct_trip"
      );
      continue;
    }
    console.log(
      `[STREET_HISTORY_CANONICAL] phase=${kind === "planned" ? "keep_separate" : "project"} source=tracking hasLinkedTrip=${kind === "direct"} hasLinkedBooking=${!!rideKey} countContribution=1 reason=${kind === "planned" ? "planned_leg_without_direct_trip_kept" : "canonical_ride_kept"}`
    );
    kept.push(trip);
  }
  return { trips: kept, dropped };
}
__name(dedupeCanonicalStreetHistoryTrips, "dedupeCanonicalStreetHistoryTrips");
async function _resolveStreetHistoryTrackingLinks(env, scope2, trips) {
  const out = /* @__PURE__ */ new Map();
  if (!env?.BOOKING_KV) return out;
  const directKeys = _streetHistoryDirectRideKeySet(trips);
  const candidateIds = /* @__PURE__ */ new Set();
  for (const trip of trips) {
    if (_streetHistoryCanonicalKind(trip?.kind) !== "planned") continue;
    if (_streetHistoryLinkedTrackingTripId(trip)) continue;
    const parent = _streetHistoryParentBookingId(trip);
    const bookingId = _streetHistoryBookingIdOf(trip);
    const alreadyOwned = [parent, bookingId].some((k) => k && directKeys.has(k));
    if (alreadyOwned) continue;
    if (parent) candidateIds.add(parent);
    if (bookingId) candidateIds.add(bookingId);
  }
  const MAX_LOOKUPS = 40;
  let used = 0;
  const tenantId = _streetHistoryCanonicalId(scope2?.tenant_id);
  const companyId = _streetHistoryCanonicalId(scope2?.company_id);
  for (const id22 of candidateIds) {
    if (used >= MAX_LOOKUPS) break;
    used += 1;
    let rec = null;
    try {
      rec = await env.BOOKING_KV.get(`booking:${id22}`, { type: "json" });
    } catch (_) {
      rec = null;
    }
    if (!rec || typeof rec !== "object") continue;
    const recTenant = _streetHistoryCanonicalId(rec.tenant_id ?? rec.tenantId);
    const recCompany = _streetHistoryCanonicalId(rec.company_id ?? rec.companyId);
    if (tenantId && recTenant && recTenant !== tenantId) continue;
    if (companyId && recCompany && recCompany !== companyId) continue;
    const trackingTripId = _streetHistoryCanonicalId(
      rec.tracking_trip_id ?? rec.trackingTripId
    );
    if (trackingTripId && directKeys.has(trackingTripId)) {
      out.set(id22, trackingTripId);
    }
  }
  if (used > 0) {
    console.log(
      `[STREET_HISTORY_CANONICAL] phase=enrich source=booking_kv lookups=${used} resolved=${out.size}`
    );
  }
  return out;
}
__name(_resolveStreetHistoryTrackingLinks, "_resolveStreetHistoryTrackingLinks");
async function _streetRideShadowWriteGuard(env, scope2, bookingId, parentBookingId) {
  const result2 = { block: false, source: "", rideType: "", trackingTripId: "" };
  if (!env?.BOOKING_KV) return result2;
  const tenantId = _streetHistoryCanonicalId(scope2?.tenant_id);
  const companyId = _streetHistoryCanonicalId(scope2?.company_id);
  const ids = [
    _streetHistoryCanonicalId(bookingId),
    _streetHistoryCanonicalId(parentBookingId)
  ].filter((v, i, a) => v && a.indexOf(v) === i);
  for (const id22 of ids) {
    let rec = null;
    try {
      rec = await env.BOOKING_KV.get(`booking:${id22}`, { type: "json" });
    } catch (_) {
      rec = null;
    }
    if (!rec || typeof rec !== "object") continue;
    const recTenant = _streetHistoryCanonicalId(rec.tenant_id ?? rec.tenantId);
    const recCompany = _streetHistoryCanonicalId(rec.company_id ?? rec.companyId);
    if (tenantId && recTenant && recTenant !== tenantId) continue;
    if (companyId && recCompany && recCompany !== companyId) continue;
    const source = _streetHistoryCanonicalId(rec.source ?? rec.booking_source);
    const rideType = _streetHistoryCanonicalId(rec.ride_type ?? rec.rideType);
    const trackingTripId = _streetHistoryCanonicalId(
      rec.tracking_trip_id ?? rec.trackingTripId
    );
    let directTripExists = false;
    if (trackingTripId) {
      try {
        const resolved = await getScopedOrLegacyTripForScope(env, scope2, trackingTripId);
        const directTrip = resolved?.trip;
        directTripExists = !!directTrip && _streetHistoryCanonicalKind(directTrip.kind) === "direct";
      } catch (_) {
        directTripExists = false;
      }
    }
    result2.source = source;
    result2.rideType = rideType;
    result2.trackingTripId = trackingTripId;
    result2.block = _streetRideBookingBlocksShadowWrite({
      source,
      rideType,
      trackingTripId,
      directTripExists
    });
    if (result2.block) return result2;
  }
  return result2;
}
__name(_streetRideShadowWriteGuard, "_streetRideShadowWriteGuard");
var _TRIPS_HISTORY_READ_CONCURRENCY = 16;
async function _tripsHistoryBoundedParallelMap(input, concurrency, mapper) {
  const limit2 = Math.max(1, Math.min(concurrency, input.length || 1));
  const out = new Array(input.length);
  let next = 0;
  const workers = new Array(limit2).fill(0).map(async () => {
    for (; ; ) {
      const i = next;
      next += 1;
      if (i >= input.length) return;
      out[i] = await mapper(input[i], i);
    }
  });
  await Promise.all(workers);
  return out;
}
__name(_tripsHistoryBoundedParallelMap, "_tripsHistoryBoundedParallelMap");
async function handleTripsHistory(req, url, env, origin, ctx) {
  const requestStartedAt = Date.now();
  const requiredScope = parseRequiredTenantCompanyScope(req, url, null, { returnResponse: true, origin });
  if (requiredScope instanceof Response) return requiredScope;
  const scope2 = requiredScope;
  const authStart = Date.now();
  const auth = await resolveTripsHistoryAuth(req, url, env, scope2, origin);
  const authMs = Date.now() - authStart;
  if (!auth.ok) return auth.response;
  const tenant_id = scope2.tenant_id;
  const company_id = scope2.company_id;
  const driver_id = auth.forced_driver_id ?? safeStr22(url.searchParams.get("driver_id"), 96);
  const limit2 = Math.min(200, Math.max(1, Number(url.searchParams.get("limit") || 50)));
  const includeActive = (url.searchParams.get("include_active") || "").toLowerCase() === "1";
  const includeArchived = (url.searchParams.get("include_archived") || "").toLowerCase() === "1";
  const scopedIndexKey = driver_id ? scopedTripsDriverIndexKey(scope2, driver_id) : scopedTripsIndexKey(scope2);
  const scopedIds = await kvGetJson(env.FLUXIDI_TRACKING, scopedIndexKey) ?? [];
  const tripIds = Array.isArray(scopedIds) ? scopedIds : [];
  const readStart = Date.now();
  const resolutions = await _tripsHistoryBoundedParallelMap(
    tripIds,
    _TRIPS_HISTORY_READ_CONCURRENCY,
    async (raw_trip_id, index) => {
      const safeTripId = safeStr22(raw_trip_id, 128);
      if (!safeTripId) return { index, keep: false };
      const scopedTripStorageKey = scopedTripKey(scope2, safeTripId);
      let trip = null;
      try {
        trip = await kvGetJson(env.FLUXIDI_TRACKING, scopedTripStorageKey);
      } catch (_) {
        trip = null;
      }
      let migratedFromLegacy = false;
      let legacyMigrationRecord = null;
      if (!trip) {
        let legacyTrip = null;
        try {
          legacyTrip = await kvGetJson(env.FLUXIDI_TRACKING, tripKey(safeTripId));
        } catch (_) {
          legacyTrip = null;
        }
        if (legacyTrip && recordMatchesTenantCompanyScope(legacyTrip, scope2)) {
          const migratedTrip = applyCanonicalScopeToRecord(
            { ...legacyTrip },
            scope2
          );
          trip = migratedTrip;
          migratedFromLegacy = true;
          legacyMigrationRecord = migratedTrip;
        }
      }
      return {
        index,
        keep: true,
        safeTripId,
        trip,
        scopedTripStorageKey,
        migratedFromLegacy,
        legacyMigrationRecord
      };
    }
  );
  const readMs = Date.now() - readStart;
  const trips = [];
  const cleaned = [];
  const legacyMigrations = [];
  for (const outcome of resolutions) {
    if (!outcome || outcome.keep !== true) continue;
    const trip = outcome.trip;
    if (!trip) continue;
    if (!recordMatchesTenantCompanyScope(trip, scope2)) continue;
    cleaned.push(outcome.safeTripId);
    if (outcome.migratedFromLegacy) {
      legacyMigrations.push({
        key: outcome.scopedTripStorageKey,
        record: outcome.legacyMigrationRecord
      });
    }
    if (!includeActive && trip.status === "active") continue;
    if (!includeArchived && trip.archived === true) continue;
    trips.push(summarizeTrip(trip));
  }
  const persistLegacyMigrations = /* @__PURE__ */ __name(async () => {
    for (const entry of legacyMigrations) {
      try {
        await kvPutJson(env.FLUXIDI_TRACKING, entry.key, entry.record, TTL_TRIP);
      } catch (_) {
      }
    }
  }, "persistLegacyMigrations");
  const persistCleanedIndex = /* @__PURE__ */ __name(async () => {
    if (cleaned.length !== tripIds.length) {
      try {
        await kvPutJson(
          env.FLUXIDI_TRACKING,
          scopedIndexKey,
          cleaned.slice(0, driver_id ? 200 : 500),
          TTL_TRIP
        );
      } catch (_) {
      }
    }
  }, "persistCleanedIndex");
  if (ctx && typeof ctx.waitUntil === "function") {
    if (legacyMigrations.length > 0) ctx.waitUntil(persistLegacyMigrations());
    if (cleaned.length !== tripIds.length) ctx.waitUntil(persistCleanedIndex());
  } else {
    await persistLegacyMigrations();
    await persistCleanedIndex();
  }
  const enrichStart = Date.now();
  const resolvedLinks = await _resolveStreetHistoryTrackingLinks(env, scope2, trips);
  const canonical2 = dedupeCanonicalStreetHistoryTrips(trips, resolvedLinks);
  const canonicalTrips = canonical2.trips.slice(0, limit2);
  const enrichMs = Date.now() - enrichStart;
  console.log(
    `[STREET_HISTORY_RUNTIME] source=worker canonicalVersion=${STREET_HISTORY_CANONICAL_VERSION} rowsBefore=${trips.length} rowsAfter=${canonical2.trips.length} dropped=${canonical2.dropped} returned=${canonicalTrips.length}`
  );
  const totalMs = Date.now() - requestStartedAt;
  console.log(
    `[TRIPS_HISTORY_TIMING] endpoint=trips_history auth_ms=${authMs} read_ms=${readMs} enrich_ms=${enrichMs} total_ms=${totalMs} indexed=${tripIds.length} kept=${cleaned.length} returned=${canonicalTrips.length} concurrency=${_TRIPS_HISTORY_READ_CONCURRENCY}`
  );
  const resp = withCors(
    json2(
      {
        ok: true,
        tenant_id,
        company_id,
        driver_id: driver_id ?? null,
        canonical_version: STREET_HISTORY_CANONICAL_VERSION,
        count: canonicalTrips.length,
        trips: canonicalTrips
      },
      { status: 200 }
    ),
    origin
  );
  try {
    resp.headers.set("X-Fluxidi-History-Canonical", STREET_HISTORY_CANONICAL_VERSION);
  } catch (_) {
  }
  return resp;
}
__name(handleTripsHistory, "handleTripsHistory");
async function handleArchiveTrip(req, url, env, origin) {
  requireAdmin(req, url, env);
  const body = await readJson(req);
  const requiredScope = parseRequiredTenantCompanyScope(req, url, body, { returnResponse: true, origin });
  if (requiredScope instanceof Response) return requiredScope;
  const scope2 = requiredScope;
  const tenant_id = scope2.tenant_id;
  const company_id = scope2.company_id;
  const driver_id = safeStr22(body["driver_id"], 96);
  const trip_id = safeStr22(body["trip_id"], 128);
  if (!trip_id) throw new Error("trip_id is required");
  const tripResolved = await getScopedOrLegacyTripForScope(env, scope2, trip_id);
  const trip = tripResolved.trip;
  if (!trip) throw new Error("Unknown trip_id");
  if (!recordMatchesTenantCompanyScope(trip, scope2)) throw new Error("invalid trip scope");
  const key2 = tripResolved.key;
  const tripDriver = safeStr22(trip.driver_id, 96);
  if (driver_id && tripDriver && tripDriver !== driver_id) {
    throw new Error("Trip driver mismatch");
  }
  const archived = body["archived"] !== false;
  trip.archived = archived;
  if (archived) {
    trip.archived_at = nowIso();
    trip.archived_by = driver_id || "admin";
  } else {
    trip.archived_at = null;
    trip.archived_by = driver_id || "admin";
  }
  applyCanonicalScopeToRecord(trip, scope2);
  await kvPutJson(env.FLUXIDI_TRACKING, key2, trip, TTL_TRIP);
  return withCors(
    json2({ ok: true, archived, trip_id }, { status: 200 }),
    origin
  );
}
__name(handleArchiveTrip, "handleArchiveTrip");
async function ensureDirectTripStartComplianceEmit(env, {
  trip,
  key: key2,
  scope: scope2,
  startedAt,
  ctx = null,
  logLabel = "ride_start_direct",
  timeoutMs = 1500
} = {}) {
  if (!trip || typeof trip !== "object") {
    return { event: null, emitted: false };
  }
  if (complianceEmitStartAlreadyApplied(trip)) {
    return { event: null, emitted: false, already_applied: true };
  }
  const event = buildDirectTripStartComplianceEvent(trip, startedAt, scope2);
  if (!event) return { event: null, emitted: false };
  const tripId = _dbfStr(trip.trip_id ?? trip.tripId, 160);
  const eventId = _dbfStr(trip.compliance_emit_start_event_id, 200) || buildDeterministicDirectRideStartEventId(
    event.tenant_id,
    event.company_id,
    event.trip_id ?? tripId
  );
  if (eventId) event.event_id = eventId;
  applyComplianceEmitStartAttempt(trip, {
    state: COMPLIANCE_EMIT_STATE.PENDING,
    errorCode: null,
    eventId,
    nowIso: nowIso()
  });
  applyCanonicalScopeToRecord(trip, scope2);
  if (key2) await kvPutJson(env.FLUXIDI_TRACKING, key2, trip, TTL_TRIP);
  const emitTask = (async () => {
    let emitRes2;
    try {
      emitRes2 = await emitComplianceEventBestEffort(env, event, {
        timeoutMs,
        logLabel
      });
    } catch (err) {
      emitRes2 = { ok: false, error: _dbfStr(err?.message || err, 120) || "internal_error" };
    }
    try {
      const latest = key2 ? await kvGetJson(env.FLUXIDI_TRACKING, key2) : trip;
      const target2 = latest && recordMatchesTenantCompanyScope(latest, scope2) ? latest : trip;
      const nextState = deriveComplianceEmitStateFromResult(emitRes2);
      applyComplianceEmitStartAttempt(target2, {
        state: nextState,
        errorCode: complianceEmitErrorCodeFromResult(emitRes2),
        eventId: event.event_id,
        nowIso: nowIso(),
        attemptDelta: 0
      });
      applyCanonicalScopeToRecord(target2, scope2);
      if (key2) await kvPutJson(env.FLUXIDI_TRACKING, key2, target2, TTL_TRIP);
    } catch (_) {
    }
    return emitRes2;
  })();
  if (ctx && typeof ctx.waitUntil === "function") {
    ctx.waitUntil(emitTask);
    return { event, emitted: true, deferred: true };
  }
  const emitRes = await emitTask;
  return { event, emitted: emitRes?.ok === true, result: emitRes };
}
__name(ensureDirectTripStartComplianceEmit, "ensureDirectTripStartComplianceEmit");
async function handleStartDirectTrip(req, url, env, origin, ctx) {
  const rawBody = await readJson(req);
  const auth = await requireDriverSessionOrAdminForScope(req, url, env, {
    body: rawBody,
    routeLabel: "TRIP_START_DIRECT"
  });
  if (!auth.ok) return auth.response;
  const body = applyDriverSessionToBody(rawBody, auth.driver_session);
  const requiredScope = parseRequiredTenantCompanyScope(req, url, body, { returnResponse: true, origin });
  if (requiredScope instanceof Response) return requiredScope;
  const scope2 = requiredScope;
  const actor = resolveTrackingActorFromRequest(req, url, body);
  const tenant_id = scope2.tenant_id;
  const company_id = scope2.company_id;
  const driver_id = safeStr22(body["driver_id"], 96);
  if (!driver_id) throw new Error("driver_id is required");
  const vehicle_id = safeStr22(body["vehicle_id"], 96) ?? null;
  const owner_company_id = company_id;
  if (actor.actor_role === "driver") {
    if (!actor.actor_driver_id) {
      _logTrackingOwnershipBlock({
        target: "trip_start_direct",
        targetId: "new",
        actor,
        ownerDriverId: driver_id,
        ownerVehicleId: vehicle_id,
        error: "trip_not_assigned_to_driver"
      });
      return withCors(json2(_trackingOwnershipError("trip_not_assigned_to_driver"), { status: 403 }), origin);
    }
    if (!vehicle_id) {
      _logTrackingOwnershipBlock({
        target: "trip_start_direct",
        targetId: "new",
        actor,
        ownerDriverId: driver_id,
        ownerVehicleId: vehicle_id,
        error: "trip_not_assigned_to_driver"
      });
      return withCors(json2(_trackingOwnershipError("trip_not_assigned_to_driver"), { status: 403 }), origin);
    }
    if (actor.actor_driver_id !== driver_id) {
      _logTrackingOwnershipBlock({
        target: "trip_start_direct",
        targetId: "new",
        actor,
        ownerDriverId: driver_id,
        ownerVehicleId: vehicle_id,
        error: "trip_not_assigned_to_driver"
      });
      return withCors(json2(_trackingOwnershipError("trip_not_assigned_to_driver"), { status: 403 }), origin);
    }
    if (actor.actor_vehicle_id && actor.actor_vehicle_id !== vehicle_id) {
      _logTrackingOwnershipBlock({
        target: "trip_start_direct",
        targetId: "new",
        actor,
        ownerDriverId: driver_id,
        ownerVehicleId: vehicle_id,
        error: "trip_not_assigned_to_driver"
      });
      return withCors(json2(_trackingOwnershipError("trip_not_assigned_to_driver"), { status: 403 }), origin);
    }
    const vehicleOwnership = await _driverVehicleOwnershipBestEffort(env, {
      tenant_id,
      company_id,
      driver_id: actor.actor_driver_id,
      vehicle_id
    });
    _logTrackingOwnershipCheck({
      target: "trip_start_direct_vehicle",
      targetId: vehicle_id,
      actor,
      ownerDriverId: actor.actor_driver_id,
      ownerVehicleId: vehicle_id,
      allowed: vehicleOwnership.allowed,
      reason: vehicleOwnership.reason
    });
    if (!vehicleOwnership.allowed && vehicleOwnership.certainMismatch) {
      _logTrackingOwnershipBlock({
        target: "trip_start_direct_vehicle",
        targetId: vehicle_id,
        actor,
        ownerDriverId: actor.actor_driver_id,
        ownerVehicleId: vehicle_id,
        error: "trip_not_assigned_to_driver"
      });
      return withCors(json2(_trackingOwnershipError("trip_not_assigned_to_driver"), { status: 403 }), origin);
    }
  }
  const originData = normalizeDestination(body["origin"]);
  const destination = normalizeDestination(body["destination"]);
  const pricing_snapshot = normalizePricingSnapshot(body["pricing_snapshot"]);
  const createdAt = nowIso();
  const startedAt = safeStr22(body["client_started_at"], 64) ?? createdAt;
  const trip_id = makeTripId();
  const directRideKey = safeStr22(body["direct_ride_key"] ?? body["directRideKey"], 200) || `direct_${trip_id}`;
  await syncDirectDispatchOccupancy(env, {
    tenant_id,
    company_id,
    driver_id,
    vehicle_id,
    trip_id,
    direct_ride_key: directRideKey
  }, "start");
  let booking_id = null;
  let booking_link_state = "pending";
  const bookingCreateRes = await _callBookingWorkerJson(
    env,
    "/track/booking/create-direct",
    {
      tenant_id,
      company_id,
      direct_ride_key: directRideKey,
      driver_id,
      vehicle_id,
      trip_id,
      origin: originData,
      destination,
      started_at: startedAt,
      currency: safeStr22(pricing_snapshot?.currency, 8) || "EUR",
      pricing_snapshot
    },
    { timeoutMs: 4e3 }
  );
  if (bookingCreateRes?.ok === true && safeStr22(bookingCreateRes?.booking_id, 160)) {
    booking_id = safeStr22(bookingCreateRes.booking_id, 160);
    booking_link_state = "linked";
  } else {
    if (bookingCreateRes?.error === "street_dispatch_sync_failed") {
      booking_id = safeStr22(bookingCreateRes?.booking_id, 160) || null;
    }
    console.log(
      `[DIRECT_TRIP][BOOKING_CREATE][WARN] trip=${trip_id} link_state=pending reason=${safeStr22(bookingCreateRes?.error, 120) || "unknown"}`
    );
  }
  const startEvent = {
    type: "start",
    ts: startedAt,
    source: "driver_app"
  };
  const trip = {
    trip_id,
    kind: "direct",
    tenant_id,
    driver_id,
    vehicle_id,
    booking_id,
    bookingId: booking_id,
    direct_ride_key: directRideKey,
    booking_link_state,
    dispatch_occupancy_registered: Boolean(env?.COMPANY_TRACKING || realtimeDoEnabled(env)),
    source: "street_ride",
    // STREET-RIDE-HISTORY-DUPLICATE-ZERO-BOOKING-1B: write-time canonical
    // contract. The canonical physical ride key is the tracking trip id itself
    // so linked operational shadows can point at it explicitly.
    canonical_physical_ride_key: trip_id,
    canonical_trip_kind: "direct",
    is_operational_shadow: false,
    origin: originData,
    destination,
    pricing_snapshot,
    status: "active",
    timeline: [startEvent],
    created_at: createdAt,
    started_at: startedAt,
    stopped_at: null,
    wait_started_at: null,
    km_total: null,
    wait_seconds_total: 0,
    total_eur: null,
    owner_driver_id: actor.actor_role === "driver" ? actor.actor_driver_id : driver_id,
    owner_vehicle_id: actor.actor_role === "driver" ? actor.actor_vehicle_id ?? vehicle_id : vehicle_id,
    owner_tenant_id: tenant_id,
    owner_company_id
  };
  applyCanonicalScopeToRecord(trip, scope2);
  await kvPutJson(env.FLUXIDI_TRACKING, scopedTripKey(scope2, trip_id), trip, TTL_TRIP);
  if (actor.actor_role === "driver") {
    await _rememberVehicleOwnerBestEffort(env, {
      tenant_id,
      company_id,
      driver_id: actor.actor_driver_id,
      vehicle_id
    });
  }
  await prependIndex(env.FLUXIDI_TRACKING, scopedTripsIndexKey(scope2), trip_id, 500);
  await prependIndex(env.FLUXIDI_TRACKING, scopedTripsDriverIndexKey(scope2, driver_id), trip_id, 200);
  await ensureDirectTripStartComplianceEmit(env, {
    trip,
    key: scopedTripKey(scope2, trip_id),
    scope: scope2,
    startedAt,
    ctx,
    logLabel: "ride_start_direct",
    timeoutMs: 1500
  });
  return withCors(
    json2(
      {
        ok: true,
        trip_id,
        booking_id,
        booking_link_state,
        kind: "direct",
        tenant_id,
        company_id,
        driver_id,
        vehicle_id,
        status: "active",
        created_at: createdAt,
        started_at: startedAt
      },
      { status: 200 }
    ),
    origin
  );
}
__name(handleStartDirectTrip, "handleStartDirectTrip");
async function _callBookingWorkerJson(env, path, payload, { timeoutMs = 4e3 } = {}) {
  const adminToken = safeStr22(env?.ADMIN_TOKEN, 512);
  if (!adminToken) return { ok: false, error: "missing_admin_token" };
  const requestInit = {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${adminToken}`
    },
    body: JSON.stringify(payload || {})
  };
  const serviceBinding = env?.BOOKING_API;
  const baseUrl = safeStr22(env?.BOOKING_API_URL, 200)?.replace(/\/+$/, "");
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    let res;
    if (serviceBinding && typeof serviceBinding.fetch === "function") {
      res = await serviceBinding.fetch(
        new Request(`https://booking.internal${path}`, {
          ...requestInit,
          signal: controller.signal
        })
      );
    } else if (baseUrl) {
      res = await ownedReleaseFetchV1(`${baseUrl}${path}`, {
        ...requestInit,
        signal: controller.signal
      });
    } else {
      return { ok: false, error: "missing_booking_api_target" };
    }
    const text22 = await res.text().catch(() => "");
    let decoded = null;
    try {
      decoded = text22 ? JSON.parse(text22) : null;
    } catch (_) {
      decoded = null;
    }
    if (!res.ok) {
      return {
        ok: false,
        error: safeStr22(decoded?.error, 120) || `http_${res.status}`,
        ...decoded?.error === "street_dispatch_sync_failed" && safeStr22(decoded?.booking_id, 160) ? { booking_id: safeStr22(decoded.booking_id, 160) } : {}
      };
    }
    return decoded && typeof decoded === "object" ? decoded : { ok: true };
  } catch (err) {
    return {
      ok: false,
      error: safeStr22(err?.message || err, 120) || "booking_worker_call_failed"
    };
  } finally {
    clearTimeout(timer);
  }
}
__name(_callBookingWorkerJson, "_callBookingWorkerJson");
async function _notifyBookingWorkerPlannedTripCompletionBestEffort(env, scope2, trip, ctx) {
  const adminToken = safeStr22(env?.ADMIN_TOKEN, 512);
  if (!adminToken) {
    console.log("[TRACKING][PLANNED_STOP][BOOKING_SYNC] skipped reason=missing_admin_token");
    return;
  }
  const bookingId = safeStr22(
    trip?.parent_booking_id ?? trip?.parentBookingId ?? trip?.booking_id ?? trip?.bookingId,
    160
  );
  if (!bookingId) {
    console.log("[TRACKING][PLANNED_STOP][BOOKING_SYNC] skipped reason=missing_booking_id");
    return;
  }
  const payload = {
    tenant_id: scope2?.tenant_id,
    company_id: scope2?.company_id,
    booking_id: bookingId,
    leg_id: safeStr22(trip?.leg_id ?? trip?.legId, 200) || null,
    trip_id: safeStr22(trip?.trip_id ?? trip?.tripId, 160) || null,
    stopped_at: safeStr22(trip?.stopped_at ?? trip?.stoppedAt, 80) || null,
    completion_context: trip?.completion_context || null,
    source: "planned_trip_stop"
  };
  const requestInit = {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${adminToken}`
    },
    body: JSON.stringify(payload)
  };
  const serviceBinding = env?.BOOKING_API;
  const baseUrl = safeStr22(env?.BOOKING_API_URL, 200)?.replace(/\/+$/, "");
  const targetUrl = `${baseUrl || "https://fluxidi-booking-api.fluxidi.workers.dev"}/track/booking/complete-from-planned-stop`;
  const syncTask = (async () => {
    try {
      let res;
      if (serviceBinding && typeof serviceBinding.fetch === "function") {
        res = await serviceBinding.fetch(
          new Request(`https://booking.internal/track/booking/complete-from-planned-stop`, requestInit)
        );
      } else if (baseUrl) {
        res = await ownedReleaseFetchV1(targetUrl, requestInit);
      } else {
        console.log("[TRACKING][PLANNED_STOP][BOOKING_SYNC] skipped reason=missing_booking_api_target");
        return;
      }
      const bodyText = await res.text().catch(() => "");
      console.log(
        `[TRACKING][PLANNED_STOP][BOOKING_SYNC] booking=${bookingId} leg=${safeStr22(trip?.leg_id ?? trip?.legId, 200) || "-"} trip=${safeStr22(trip?.trip_id ?? trip?.tripId, 160) || "-"} http=${res.status} body=${safeStr22(bodyText, 160) || "-"}`
      );
    } catch (err) {
      console.log(
        `[TRACKING][PLANNED_STOP][BOOKING_SYNC] booking=${bookingId} failed reason=${safeStr22(err?.message || err, 120) || "unknown"}`
      );
    }
  })();
  if (ctx && typeof ctx.waitUntil === "function") {
    ctx.waitUntil(syncTask);
  } else {
    await syncTask;
  }
}
__name(_notifyBookingWorkerPlannedTripCompletionBestEffort, "_notifyBookingWorkerPlannedTripCompletionBestEffort");
function _plannedStopPositiveMoney(v) {
  if (v === null || v === void 0 || v === "") return null;
  const n = Number(v);
  return Number.isFinite(n) && n > 0 ? n : null;
}
__name(_plannedStopPositiveMoney, "_plannedStopPositiveMoney");
function _plannedStopAsObject(v) {
  return v && typeof v === "object" && !Array.isArray(v) ? v : null;
}
__name(_plannedStopAsObject, "_plannedStopAsObject");
function _plannedStopLegTypeToken(legType) {
  const t = safeStr22(legType, 32)?.toLowerCase() ?? "";
  return t === "return" ? "return" : t ? "outbound" : "";
}
__name(_plannedStopLegTypeToken, "_plannedStopLegTypeToken");
function resolveCanonicalPlannedBookingFare({
  bookingRecord = null,
  bookingDetails = null,
  legId = null,
  legType = null
} = {}) {
  const record = _plannedStopAsObject(bookingRecord) || {};
  const details = _plannedStopAsObject(bookingDetails) || {};
  const nestedBooking = _plannedStopAsObject(details.booking) || _plannedStopAsObject(details.record) || _plannedStopAsObject(record.booking) || {};
  const sources = [details, nestedBooking, record];
  const wantedLegId = safeStr22(legId, 160) || "";
  const wantedLegType = _plannedStopLegTypeToken(
    legType || details.leg_type || details.legType
  );
  const pickFirst = /* @__PURE__ */ __name((cands) => {
    for (const c of cands) {
      const n = _plannedStopPositiveMoney(c);
      if (n != null) return n;
    }
    return null;
  }, "pickFirst");
  for (const src of sources) {
    const legPrice = pickFirst([
      src.leg_price_incl_vat,
      src.legPriceInclVat,
      src.segment_price_eur,
      src.segmentPriceEur
    ]);
    if (legPrice != null) return { amount: legPrice, source: "leg_price_incl_vat" };
  }
  for (const src of sources) {
    const legs = Array.isArray(src.operational_legs) ? src.operational_legs : Array.isArray(src.legs) ? src.legs : null;
    if (!legs) continue;
    for (const rawLeg of legs) {
      const leg = _plannedStopAsObject(rawLeg);
      if (!leg) continue;
      const entryLegId = safeStr22(leg.leg_id ?? leg.legId, 160) || "";
      const entryType = _plannedStopLegTypeToken(leg.leg_type ?? leg.legType);
      if (wantedLegId && entryLegId && entryLegId !== wantedLegId) continue;
      if (!wantedLegId && wantedLegType && entryType && entryType !== wantedLegType) continue;
      const legPrice = pickFirst([
        leg.leg_price_incl_vat,
        leg.legPriceInclVat,
        leg.price_incl_vat,
        leg.priceInclVat,
        leg.price
      ]);
      if (legPrice != null) return { amount: legPrice, source: "operational_leg_price" };
    }
  }
  if (wantedLegType === "return") {
    for (const src of sources) {
      const returnPrice = pickFirst([
        src.price_incl_vat_return,
        src.priceInclVatReturn,
        src.return_price_eur,
        _plannedStopAsObject(src.quote)?.price_incl_vat_return,
        _plannedStopAsObject(_plannedStopAsObject(src.quote)?.pricing_return)?.price_incl_vat
      ]);
      if (returnPrice != null) return { amount: returnPrice, source: "price_incl_vat_return" };
    }
  } else {
    for (const src of sources) {
      const mainPrice = pickFirst([
        src.price_incl_vat_main,
        src.priceInclVatMain,
        src.outbound_price_eur,
        _plannedStopAsObject(src.quote)?.price_incl_vat_main,
        _plannedStopAsObject(_plannedStopAsObject(src.quote)?.pricing_main)?.price_incl_vat
      ]);
      if (mainPrice != null) return { amount: mainPrice, source: "price_incl_vat_main" };
    }
  }
  for (const src of sources) {
    const canonical2 = pickFirst([
      src.price_incl_vat,
      src.priceInclVat,
      src.total_price_incl_vat,
      src.totalPriceInclVat,
      _plannedStopAsObject(src.quote)?.price_incl_vat,
      _plannedStopAsObject(_plannedStopAsObject(src.quote)?.pricing)?.price_incl_vat,
      src.price,
      src.total_price,
      src.total
    ]);
    if (canonical2 != null) return { amount: canonical2, source: "price_incl_vat" };
  }
  return { amount: null, source: "missing" };
}
__name(resolveCanonicalPlannedBookingFare, "resolveCanonicalPlannedBookingFare");
function resolvePlannedStopTotalEur({
  bookingRecord = null,
  bookingDetails = null,
  legId = null,
  legType = null,
  clientTotalEur = null,
  existingTripTotalEur = null
} = {}) {
  const canonical2 = resolveCanonicalPlannedBookingFare({
    bookingRecord,
    bookingDetails,
    legId,
    legType
  });
  if (canonical2.amount != null) {
    return {
      total_eur: canonical2.amount,
      source: canonical2.source,
      ignored_client_total: true
    };
  }
  const existing = _plannedStopPositiveMoney(existingTripTotalEur);
  if (existing != null) {
    return {
      total_eur: existing,
      source: "existing_trip",
      ignored_client_total: true
    };
  }
  return {
    total_eur: null,
    source: "missing",
    ignored_client_total: true
  };
}
__name(resolvePlannedStopTotalEur, "resolvePlannedStopTotalEur");
async function _loadBookingRecordForPlannedStopBestEffort(env, scope2, bookingId) {
  const id22 = safeStr22(bookingId, 96);
  if (!id22) return null;
  const res = await _callBookingWorkerJson(
    env,
    "/track/booking/canonical-fare-for-planned-stop",
    {
      tenant_id: scope2?.tenant_id,
      company_id: scope2?.company_id,
      booking_id: id22
    }
  );
  if (!res?.ok) return null;
  const booking = _plannedStopAsObject(res.booking);
  return booking || null;
}
__name(_loadBookingRecordForPlannedStopBestEffort, "_loadBookingRecordForPlannedStopBestEffort");
async function handleRecordPlannedStopTrip(req, url, env, origin, ctx) {
  const rawBody = await readJson(req);
  const auth = await requireDriverSessionOrAdminForScope(req, url, env, {
    body: rawBody,
    routeLabel: "TRIP_RECORD_PLANNED_STOP"
  });
  if (!auth.ok) return auth.response;
  const body = applyDriverSessionToBody(rawBody, auth.driver_session);
  const requiredScope = parseRequiredTenantCompanyScope(req, url, body, { returnResponse: true, origin });
  if (requiredScope instanceof Response) return requiredScope;
  const scope2 = requiredScope;
  const actor = resolveTrackingActorFromRequest(req, url, body);
  const booking_id = safeStr22(body["booking_id"], 96);
  if (!booking_id) throw new Error("booking_id is required");
  const tenant_id = scope2.tenant_id;
  const company_id = scope2.company_id;
  const driver_id = safeStr22(body["driver_id"], 96);
  if (!driver_id) throw new Error("driver_id is required");
  const vehicle_id = safeStr22(body["vehicle_id"], 96) ?? null;
  const originData = normalizeDestination(body["origin"]);
  const destination = normalizeDestination(body["destination"]);
  let booking_details = normalizeBookingDetails(body["booking_details"]);
  const leg_id = safeStr22(
    body["leg_id"] ?? body["legId"] ?? booking_details?.leg_id ?? booking_details?.legId,
    160
  ) ?? null;
  const leg_type = safeStr22(
    body["leg_type"] ?? body["legType"] ?? booking_details?.leg_type ?? booking_details?.legType,
    32
  ) ?? null;
  const row_key = safeStr22(
    body["row_key"] ?? body["rowKey"] ?? booking_details?.row_key ?? booking_details?.rowKey,
    240
  ) ?? null;
  const parent_booking_id = safeStr22(
    body["parent_booking_id"] ?? body["parentBookingId"] ?? booking_details?.parent_booking_id ?? booking_details?.parentBookingId,
    96
  ) ?? booking_id;
  const is_operational_leg = !!(leg_id || row_key);
  if (is_operational_leg || parent_booking_id !== booking_id || leg_type) {
    const detailsNext = booking_details && typeof booking_details === "object" ? { ...booking_details } : {};
    if (leg_id) {
      detailsNext.leg_id = leg_id;
      detailsNext.legId = leg_id;
    }
    if (leg_type) {
      detailsNext.leg_type = leg_type;
      detailsNext.legType = leg_type;
    }
    if (row_key) {
      detailsNext.row_key = row_key;
      detailsNext.rowKey = row_key;
    }
    if (parent_booking_id) {
      detailsNext.parent_booking_id = parent_booking_id;
      detailsNext.parentBookingId = parent_booking_id;
    }
    detailsNext.is_operational_leg = is_operational_leg;
    detailsNext.isOperationalLeg = is_operational_leg;
    booking_details = detailsNext;
  }
  const startedAt = safeStr22(body["started_at"] ?? body["client_started_at"], 64) ?? null;
  const stoppedAt = safeStr22(body["stopped_at"] ?? body["client_stopped_at"], 64) ?? nowIso();
  const km_total = safeNum(body["km_total"], 0, 1e5);
  const wait_seconds_total = safeNum(body["wait_seconds_total"] ?? 0, 0, 60 * 60 * 24 * 7) ?? 0;
  const client_total_eur = body["total_eur"];
  const currency = safeStr22(body["currency"] ?? "EUR", 8) ?? "EUR";
  const tripSuffix = sanitizeTripIdentityToken(leg_id, 96) ?? sanitizeTripIdentityToken(row_key, 96);
  const trip_id = tripSuffix ? `planned_${booking_id}_${tripSuffix}` : `planned_${booking_id}`;
  const owner_company_id = company_id;
  console.log(
    `[TRACKING][PLANNED_STOP][LEG_IDENTITY] booking=${booking_id} trip=${trip_id} leg=${leg_id || row_key || "-"} type=${leg_type || "-"}`
  );
  const shadowGuard = await _streetRideShadowWriteGuard(
    env,
    scope2,
    booking_id,
    parent_booking_id
  );
  if (shadowGuard.block) {
    console.log(
      `[STREET_HISTORY_SHADOW_WRITE] action=skip source=streetRide syntheticLeg=true hasDirectTrip=true reason=street_ride_direct_trip_already_stored`
    );
    return withCors(
      json2(
        {
          ok: true,
          skipped: true,
          reason: "street_ride_direct_trip_already_stored",
          linked_tracking_trip_id: shadowGuard.trackingTripId || null,
          canonical_physical_ride_key: shadowGuard.trackingTripId || null,
          booking_id
        },
        { status: 200 }
      ),
      origin
    );
  }
  const existingTripResolved = await getScopedOrLegacyTripForScope(env, scope2, trip_id);
  const existingTrip = existingTripResolved.trip;
  if (existingTrip) {
    const ownershipBlock = await _assertTripOwnedByActorOrBlock({
      trip: existingTrip,
      trip_id,
      actor,
      error: "trip_not_assigned_to_driver",
      origin
    });
    if (ownershipBlock) {
      const resolved = await resolveSessionByBookingForScope(env, scope2, booking_id);
      const resolvedSession = resolved?.session;
      const resolvedMap = resolved?.map;
      const sessionStatus = safeStr22(resolvedSession?.status, 32)?.toLowerCase() ?? "";
      const sessionBookingId = _trackingOwnershipValue(
        resolvedSession?.owner_booking_id ?? resolvedSession?.booking_id ?? resolvedSession?.bookingId ?? resolvedMap?.owner_booking_id
      );
      const sessionOwnerCheck = _trackingOwnershipAllowed({
        actorDriverId: actor.actor_driver_id,
        actorVehicleId: actor.actor_vehicle_id,
        ownerDriverId: _trackingOwnershipValue(
          resolvedSession?.owner_driver_id ?? resolvedSession?.driver_id
        ),
        ownerVehicleId: _trackingOwnershipValue(
          resolvedSession?.owner_vehicle_id ?? resolvedSession?.vehicle_id
        ),
        fallbackDriverId: _trackingOwnershipValue(resolvedSession?.driver_id),
        fallbackVehicleId: _trackingOwnershipValue(resolvedSession?.vehicle_id)
      });
      const sessionOwnershipProofPassed = sessionStatus === "stopped" && (!sessionBookingId || sessionBookingId === booking_id) && sessionOwnerCheck.allowed && (sessionOwnerCheck.reason === "driver_match" || sessionOwnerCheck.reason === "vehicle_match");
      if (!sessionOwnershipProofPassed) return ownershipBlock;
      console.log(
        `[TRACKING_OWNERSHIP][PLANNED_STOP_SESSION_PROOF_OVERRIDE] booking_id=${booking_id} trip_id=${trip_id} reason=stale_existing_trip_owner`
      );
    }
  }
  const linkedTrackingTripId = safeStr22(shadowGuard.trackingTripId, 160) || null;
  const canonicalPhysicalRideKey = linkedTrackingTripId || parent_booking_id || booking_id || null;
  const bookingRecordForFare = await _loadBookingRecordForPlannedStopBestEffort(
    env,
    scope2,
    parent_booking_id || booking_id
  );
  let sessionForOrigin = null;
  try {
    const resolvedSession = await resolveSessionByBookingForScope(env, scope2, booking_id) || (parent_booking_id && parent_booking_id !== booking_id ? await resolveSessionByBookingForScope(env, scope2, parent_booking_id) : null);
    sessionForOrigin = resolvedSession?.session || null;
  } catch (_) {
    sessionForOrigin = null;
  }
  const resolvedOrigin = resolvePlannedStopOrigin({
    payloadOrigin: originData,
    existingTripOrigin: existingTrip?.origin,
    sessionOrigin: sessionForOrigin?.origin,
    sessionPickup: sessionForOrigin?.pickup
  });
  const plannedFare = resolvePlannedStopTotalEur({
    bookingRecord: bookingRecordForFare,
    bookingDetails: booking_details,
    legId: leg_id,
    legType: leg_type,
    clientTotalEur: client_total_eur,
    existingTripTotalEur: existingTrip?.total_eur ?? existingTrip?.price_incl_vat
  });
  const total_eur = plannedFare.total_eur != null ? plannedFare.total_eur : null;
  console.log(
    `[TRACKING][PLANNED_STOP][FARE] booking=${booking_id} trip=${trip_id} source=${plannedFare.source} total=${total_eur == null ? "null" : Number(total_eur).toFixed(2)} ignored_client=${!!plannedFare.ignored_client_total} client_raw=${client_total_eur == null ? "null" : String(client_total_eur)}`
  );
  const completionSessionId = safeStr22(body.session_id, 160);
  const completionSession = completionSessionId ? await kvGetJson(env.FLUXIDI_TRACKING, scopedSessionKey(scope2, completionSessionId)) : null;
  const completionDriver = completionSession?.owner_driver_id || completionSession?.driver_id;
  const completionContext = completionSession && recordMatchesTenantCompanyScope(completionSession, scope2) && completionSession.status === "stopped" && completionSession.booking_id === parent_booking_id && completionDriver === driver_id && (actor.actor_role !== "driver" || completionDriver === actor.actor_driver_id) && Number(completionSession.assignment_version) > 0 && completionSession.operational_leg && (!leg_id || completionSession.operational_leg === leg_id || completionSession.operational_leg === "primary") ? {
    tenant_id,
    company_id,
    booking_id: parent_booking_id,
    operational_leg: completionSession.operational_leg,
    driver_id: completionDriver,
    assignment_version: completionSession.assignment_version,
    session_id: completionSessionId
  } : null;
  const trip = {
    completion_context: completionContext,
    trip_id,
    kind: "planned",
    booking_id,
    leg_id,
    legId: leg_id,
    leg_type,
    legType: leg_type,
    row_key,
    rowKey: row_key,
    parent_booking_id,
    parentBookingId: parent_booking_id,
    is_operational_leg,
    isOperationalLeg: is_operational_leg,
    linked_tracking_trip_id: linkedTrackingTripId,
    linkedTrackingTripId,
    canonical_physical_ride_key: canonicalPhysicalRideKey,
    canonical_trip_kind: "planned",
    is_operational_shadow: false,
    tenant_id,
    driver_id,
    vehicle_id,
    origin: resolvedOrigin || originData,
    destination,
    booking_details,
    status: "stopped",
    timeline: [
      {
        type: "planned_stop",
        ts: stoppedAt,
        source: "driver_app",
        booking_id,
        km_total,
        wait_seconds_total,
        total_eur,
        fare_source: plannedFare.source
      }
    ],
    created_at: startedAt ?? stoppedAt,
    started_at: startedAt,
    stopped_at: stoppedAt,
    wait_started_at: null,
    km_total,
    wait_seconds_total,
    total_eur,
    price_incl_vat: total_eur,
    fare_source: plannedFare.source,
    currency,
    owner_driver_id: actor.actor_role === "driver" ? actor.actor_driver_id : driver_id,
    owner_vehicle_id: actor.actor_role === "driver" ? actor.actor_vehicle_id ?? vehicle_id : vehicle_id,
    owner_tenant_id: tenant_id,
    owner_company_id,
    owner_booking_id: booking_id
  };
  applyCanonicalScopeToRecord(trip, scope2);
  console.log(
    `[STREET_HISTORY_SHADOW_WRITE] action=store source=${shadowGuard.source === "street_ride" ? "streetRide" : "planned"} syntheticLeg=${is_operational_leg} hasDirectTrip=${!!linkedTrackingTripId} reason=planned_leg_stored`
  );
  await kvPutJson(env.FLUXIDI_TRACKING, scopedTripKey(scope2, trip_id), trip, TTL_TRIP);
  await materializeTripDashboardKpisBestEffort(
    env,
    scope2,
    trip,
    "planned_trip_stop"
  );
  await _notifyBookingWorkerPlannedTripCompletionBestEffort(env, scope2, trip, ctx);
  if (actor.actor_role === "driver") {
    await _rememberVehicleOwnerBestEffort(env, {
      tenant_id,
      company_id,
      driver_id: actor.actor_driver_id ?? driver_id,
      vehicle_id: actor.actor_vehicle_id ?? vehicle_id
    });
  }
  await prependIndex(env.FLUXIDI_TRACKING, scopedTripsIndexKey(scope2), trip_id, 500);
  await prependIndex(env.FLUXIDI_TRACKING, scopedTripsDriverIndexKey(scope2, driver_id), trip_id, 200);
  const complianceEvent = buildPlannedTripStopComplianceEvent(trip, body, scope2);
  const tripKey2 = scopedTripKey(scope2, trip_id);
  if (complianceEvent) {
    const complianceEventId = buildDeterministicRideStopEventId(
      complianceEvent.tenant_id,
      complianceEvent.company_id,
      complianceEvent.trip_id ?? trip_id
    );
    if (complianceEventId) complianceEvent.event_id = complianceEventId;
    applyComplianceEmitAttempt(trip, {
      state: COMPLIANCE_EMIT_STATE.PENDING,
      errorCode: null,
      eventId: complianceEventId,
      nowIso: nowIso()
    });
    await kvPutJson(env.FLUXIDI_TRACKING, tripKey2, trip, TTL_TRIP);
    _chironSyncLog("enqueue", trip, trip_id, complianceEvent, "queued", "planned_ride_stop");
    const emitTask = (async () => {
      let emitRes;
      try {
        emitRes = await emitComplianceEventBestEffort(env, complianceEvent, {
          timeoutMs: 1500,
          logLabel: "planned_ride_stop"
        });
      } catch (err) {
        emitRes = { ok: false, error: _dbfStr(err?.message || err, 120) || "internal_error" };
      }
      try {
        const latestResolved = await getScopedOrLegacyTripForScope(env, scope2, trip_id);
        const target2 = latestResolved?.trip || trip;
        const targetKey = latestResolved?.key || tripKey2;
        const nextState = deriveComplianceEmitStateFromResult(emitRes);
        applyComplianceEmitAttempt(target2, {
          state: nextState,
          errorCode: complianceEmitErrorCodeFromResult(emitRes),
          eventId: complianceEvent.event_id,
          nowIso: nowIso(),
          attemptDelta: 0
          // enqueue above already counted this attempt.
        });
        applyCanonicalScopeToRecord(target2, scope2);
        await kvPutJson(env.FLUXIDI_TRACKING, targetKey, target2, TTL_TRIP);
        _chironSyncLog(
          nextState === COMPLIANCE_EMIT_STATE.APPLIED ? "applied" : "failed",
          target2,
          trip_id,
          complianceEvent,
          nextState,
          complianceEmitErrorCodeFromResult(emitRes) || "ok"
        );
      } catch (_) {
        _chironSyncLog("failed", trip, trip_id, complianceEvent, "pending", "kv_write_failed");
      }
    })();
    if (ctx && typeof ctx.waitUntil === "function") {
      ctx.waitUntil(emitTask);
    } else {
      await emitTask;
    }
  }
  const stopEmitFields = complianceEvent ? safeComplianceEmitResponseFields(trip) : null;
  return withCors(
    json2(
      {
        ok: true,
        trip_id,
        kind: "planned",
        booking_id,
        status: "stopped",
        stopped_at: stoppedAt,
        ...stopEmitFields ?? {}
      },
      { status: 200 }
    ),
    origin
  );
}
__name(handleRecordPlannedStopTrip, "handleRecordPlannedStopTrip");
async function handleWaitStartTrip(req, url, env, origin) {
  const rawBody = await readJson(req);
  const auth = await requireDriverSessionOrAdminForScope(req, url, env, {
    body: rawBody,
    routeLabel: "TRIP_WAIT_START"
  });
  if (!auth.ok) return auth.response;
  const body = applyDriverSessionToBody(rawBody, auth.driver_session);
  const requiredScope = parseRequiredTenantCompanyScope(req, url, body, { returnResponse: true, origin });
  if (requiredScope instanceof Response) return requiredScope;
  const scope2 = requiredScope;
  const trip_id = safeStr22(body["trip_id"], 128);
  if (!trip_id) throw new Error("trip_id is required");
  const tripResolved = await getScopedOrLegacyTripForScope(env, scope2, trip_id);
  const trip = tripResolved.trip;
  if (!trip) throw new Error("Unknown trip_id");
  if (!recordMatchesTenantCompanyScope(trip, scope2)) throw new Error("invalid trip scope");
  const key2 = tripResolved.key;
  if (trip.status !== "active") throw new Error("Trip is not active");
  if (trip.wait_started_at) {
    return withCors(
      json2({ ok: false, error: "Wait already active", trip_id, wait_started_at: trip.wait_started_at }, { status: 409 }),
      origin
    );
  }
  const waitStartedAt = safeStr22(body["client_wait_started_at"], 64) ?? nowIso();
  const timeline = Array.isArray(trip.timeline) ? trip.timeline : [];
  timeline.push({
    type: "wait_start",
    ts: waitStartedAt,
    source: "driver_app"
  });
  trip.wait_started_at = waitStartedAt;
  trip.timeline = timeline;
  trip.wait_seconds_total = Number.isFinite(Number(trip.wait_seconds_total)) ? Number(trip.wait_seconds_total) : 0;
  applyCanonicalScopeToRecord(trip, scope2);
  await kvPutJson(env.FLUXIDI_TRACKING, key2, trip, TTL_TRIP);
  return withCors(
    json2({ ok: true, trip_id, status: "active", wait_started_at: waitStartedAt }, { status: 200 }),
    origin
  );
}
__name(handleWaitStartTrip, "handleWaitStartTrip");
async function handleWaitEndTrip(req, url, env, origin) {
  const rawBody = await readJson(req);
  const auth = await requireDriverSessionOrAdminForScope(req, url, env, {
    body: rawBody,
    routeLabel: "TRIP_WAIT_END"
  });
  if (!auth.ok) return auth.response;
  const body = applyDriverSessionToBody(rawBody, auth.driver_session);
  const requiredScope = parseRequiredTenantCompanyScope(req, url, body, { returnResponse: true, origin });
  if (requiredScope instanceof Response) return requiredScope;
  const scope2 = requiredScope;
  const trip_id = safeStr22(body["trip_id"], 128);
  if (!trip_id) throw new Error("trip_id is required");
  const tripResolved = await getScopedOrLegacyTripForScope(env, scope2, trip_id);
  const trip = tripResolved.trip;
  if (!trip) throw new Error("Unknown trip_id");
  if (!recordMatchesTenantCompanyScope(trip, scope2)) throw new Error("invalid trip scope");
  const key2 = tripResolved.key;
  if (trip.status !== "active") throw new Error("Trip is not active");
  if (!trip.wait_started_at) {
    return withCors(
      json2({ ok: false, error: "No active wait", trip_id }, { status: 409 }),
      origin
    );
  }
  const waitEndedAt = safeStr22(body["client_wait_ended_at"], 64) ?? nowIso();
  const startedMs = Date.parse(trip.wait_started_at);
  const endedMs = Date.parse(waitEndedAt);
  const addedWaitSeconds = Number.isFinite(startedMs) && Number.isFinite(endedMs) ? Math.max(0, Math.round((endedMs - startedMs) / 1e3)) : 0;
  const currentWaitSeconds = Number.isFinite(Number(trip.wait_seconds_total)) ? Number(trip.wait_seconds_total) : 0;
  const nextWaitSeconds = currentWaitSeconds + addedWaitSeconds;
  const timeline = Array.isArray(trip.timeline) ? trip.timeline : [];
  timeline.push({
    type: "wait_end",
    ts: waitEndedAt,
    source: "driver_app",
    wait_seconds_added: addedWaitSeconds,
    wait_seconds_total: nextWaitSeconds
  });
  trip.wait_started_at = null;
  trip.wait_seconds_total = nextWaitSeconds;
  trip.timeline = timeline;
  applyCanonicalScopeToRecord(trip, scope2);
  await kvPutJson(env.FLUXIDI_TRACKING, key2, trip, TTL_TRIP);
  return withCors(
    json2(
      {
        ok: true,
        trip_id,
        status: "active",
        wait_ended_at: waitEndedAt,
        wait_seconds_added: addedWaitSeconds,
        wait_seconds_total: nextWaitSeconds
      },
      { status: 200 }
    ),
    origin
  );
}
__name(handleWaitEndTrip, "handleWaitEndTrip");
async function handleStopTrip(req, url, env, origin, ctx) {
  const rawBody = await readJson(req);
  const auth = await requireDriverSessionOrAdminForScope(req, url, env, {
    body: rawBody,
    routeLabel: "TRIP_STOP"
  });
  if (!auth.ok) return auth.response;
  const body = applyDriverSessionToBody(rawBody, auth.driver_session);
  const requiredScope = parseRequiredTenantCompanyScope(req, url, body, { returnResponse: true, origin });
  if (requiredScope instanceof Response) return requiredScope;
  const scope2 = requiredScope;
  const actor = resolveTrackingActorFromRequest(req, url, body);
  const trip_id = safeStr22(body["trip_id"], 128);
  if (!trip_id) throw new Error("trip_id is required");
  const tripResolved = await getScopedOrLegacyTripForScope(env, scope2, trip_id);
  const trip = tripResolved.trip;
  if (!trip) throw new Error("Unknown trip_id");
  if (!recordMatchesTenantCompanyScope(trip, scope2)) throw new Error("invalid trip scope");
  const key2 = tripResolved.key;
  const ownershipBlock = await _assertTripOwnedByActorOrBlock({
    trip,
    trip_id,
    actor,
    error: "trip_not_assigned_to_driver",
    origin
  });
  if (ownershipBlock) return ownershipBlock;
  if (trip.test_retirement || safeStr22(trip.status, 40).toLowerCase() === "cancelled") {
    return withCors(json2({ ok: false, error: "trip_cancelled" }, { status: 409 }), origin);
  }
  const alreadyTerminal = trip.status === "stopped" || trip.status === "completed" || trip.status === "done" || !!safeStr22(trip.stopped_at, 80);
  if (alreadyTerminal) {
    await syncDirectDispatchOccupancy(env, trip, "stop");
    const existingTotals = {
      km_total: trip.km_total,
      wait_seconds_total: trip.wait_seconds_total,
      total_eur: trip.total_eur,
      price_ex_vat: trip.price_ex_vat,
      price_vat: trip.price_vat,
      price_incl_vat: trip.price_incl_vat,
      vat_rate: trip.vat_rate,
      vat_mode: trip.vat_mode,
      currency: trip.currency
    };
    const replayBookingId = safeStr22(
      trip?.booking_id ?? trip?.bookingId ?? body["booking_id"] ?? body["bookingId"],
      160
    );
    if (replayBookingId && !bookingAlreadyFinalized(trip)) {
      const finalizePayload = buildFinalizePayloadFromTrip(trip, scope2);
      let finalizeRes = null;
      try {
        finalizeRes = await _callBookingWorkerJson(
          env,
          "/track/booking/finalize-direct",
          finalizePayload,
          { timeoutMs: 4e3 }
        );
      } catch (err) {
        finalizeRes = {
          ok: false,
          error: safeStr22(err?.message || err, 120) || "finalize_call_failed"
        };
      }
      applyBookingFinalizeAttempt(trip, {
        state: deriveFinalizeStateFromResult(finalizeRes),
        errorCode: finalizeErrorCodeFromResult(finalizeRes),
        nowIso: nowIso()
      });
      applyCanonicalScopeToRecord(trip, scope2);
      await kvPutJson(env.FLUXIDI_TRACKING, key2, trip, TTL_TRIP);
    }
    await ensureDirectTripStopComplianceEmit(env, {
      trip,
      key: key2,
      scope: scope2,
      body,
      tripId: trip_id,
      logLabel: "idempotent_stop_replay",
      timeoutMs: 1500
    });
    const stopFinalizeFields2 = safeBookingFinalizeResponseFields(trip);
    const complianceFields2 = safeComplianceEmitResponseFields(trip);
    return withCors(
      json2(
        {
          ok: true,
          trip_id,
          booking_id: stopFinalizeFields2.booking_id,
          booking_finalize_state: stopFinalizeFields2.booking_finalize_state,
          booking_finalized: stopFinalizeFields2.booking_finalized,
          status: "stopped",
          stopped_at: trip.stopped_at || null,
          totals: existingTotals,
          idempotent_replay: true,
          ...complianceFields2
        },
        { status: 200 }
      ),
      origin
    );
  }
  if (trip.status !== "active") throw new Error("Trip is not active");
  const km_total = safeNum(body["km_total"], 0, 1e5);
  if (km_total === null) throw new Error("km_total is required");
  const wait_seconds_total = safeNum(body["wait_seconds_total"] ?? 0, 0, 60 * 60 * 24 * 7);
  if (wait_seconds_total === null) throw new Error("wait_seconds_total is invalid");
  const stoppedAt = safeStr22(body["client_stopped_at"], 64) ?? nowIso();
  const totals = directTripTotals(trip, km_total, wait_seconds_total);
  console.log(
    `[DIRECT_TRIP][STOP_PRICING] source=snapshot vatMode=${totals.vat_mode ?? "incl"} totalIncl=${Number(totals.price_incl_vat ?? totals.total_eur ?? 0).toFixed(2)}`
  );
  const timeline = Array.isArray(trip.timeline) ? trip.timeline : [];
  timeline.push({
    type: "stop",
    ts: stoppedAt,
    source: "driver_app",
    km_total: totals.km_total,
    wait_seconds_total: totals.wait_seconds_total,
    total_eur: totals.total_eur,
    price_ex_vat: totals.price_ex_vat,
    price_vat: totals.price_vat,
    price_incl_vat: totals.price_incl_vat,
    vat_rate: totals.vat_rate,
    vat_mode: totals.vat_mode
  });
  trip.status = "stopped";
  trip.stopped_at = stoppedAt;
  trip.km_total = totals.km_total;
  trip.wait_seconds_total = totals.wait_seconds_total;
  trip.total_eur = totals.total_eur;
  trip.price_ex_vat = totals.price_ex_vat;
  trip.price_vat = totals.price_vat;
  trip.price_incl_vat = totals.price_incl_vat;
  trip.vat_rate = totals.vat_rate;
  trip.vat_mode = totals.vat_mode;
  trip.timeline = timeline;
  applyCanonicalScopeToRecord(trip, scope2);
  await kvPutJson(env.FLUXIDI_TRACKING, key2, trip, TTL_TRIP);
  await syncDirectDispatchOccupancy(env, trip, "stop");
  await materializeTripDashboardKpisBestEffort(
    env,
    scope2,
    trip,
    "direct_trip_stop"
  );
  const complianceEvent = buildDirectTripStopComplianceEvent(trip, body, stoppedAt, totals, scope2);
  if (!complianceEvent) {
    console.log(`[COMPLIANCE_EMIT][direct_stop] skipped reason=missing_canonical_scope trip_id=${trip_id}`);
  }
  if (complianceEvent) {
    const complianceEventId = buildDeterministicRideStopEventId(
      complianceEvent.tenant_id,
      complianceEvent.company_id,
      complianceEvent.trip_id ?? trip_id
    );
    if (complianceEventId) complianceEvent.event_id = complianceEventId;
    applyComplianceEmitAttempt(trip, {
      state: COMPLIANCE_EMIT_STATE.PENDING,
      errorCode: null,
      eventId: complianceEventId,
      nowIso: nowIso()
    });
    await kvPutJson(env.FLUXIDI_TRACKING, key2, trip, TTL_TRIP);
    _chironSyncLog("enqueue", trip, trip_id, complianceEvent, "queued", "direct_trip_stop");
  }
  const directBookingId = safeStr22(
    trip?.booking_id ?? trip?.bookingId ?? body["booking_id"] ?? body["bookingId"],
    160
  );
  if (directBookingId) {
    const finalizePayload = buildFinalizePayloadFromTrip(trip, scope2);
    let finalizeRes = null;
    try {
      finalizeRes = await _callBookingWorkerJson(
        env,
        "/track/booking/finalize-direct",
        finalizePayload,
        { timeoutMs: 4e3 }
      );
    } catch (err) {
      finalizeRes = { ok: false, error: safeStr22(err?.message || err, 120) || "finalize_call_failed" };
    }
    applyBookingFinalizeAttempt(trip, {
      state: deriveFinalizeStateFromResult(finalizeRes),
      errorCode: finalizeErrorCodeFromResult(finalizeRes),
      nowIso: nowIso()
    });
    applyCanonicalScopeToRecord(trip, scope2);
    await kvPutJson(env.FLUXIDI_TRACKING, key2, trip, TTL_TRIP);
    if (finalizeRes?.ok !== true) {
      console.log(
        `[DIRECT_TRIP][BOOKING_FINALIZE][WARN] booking=${directBookingId} trip=${trip_id} state=pending reason=${finalizeErrorCodeFromResult(finalizeRes) || "unknown"} attempt=${trip.booking_finalize_attempt_count}`
      );
    } else {
      console.log(
        `[DIRECT_TRIP][BOOKING_FINALIZE][OK] booking=${directBookingId} trip=${trip_id} state=completed`
      );
    }
  }
  if (complianceEvent) {
    const emitTask = (async () => {
      let emitRes;
      try {
        emitRes = await emitComplianceEventBestEffort(env, complianceEvent, { timeoutMs: 1500 });
      } catch (err) {
        emitRes = { ok: false, error: _dbfStr(err?.message || err, 120) || "internal_error" };
      }
      try {
        const latestResolved = await getScopedOrLegacyTripForScope(env, scope2, trip_id);
        const target2 = latestResolved?.trip || trip;
        const targetKey = latestResolved?.key || key2;
        const nextState = deriveComplianceEmitStateFromResult(emitRes);
        applyComplianceEmitAttempt(target2, {
          state: nextState,
          errorCode: complianceEmitErrorCodeFromResult(emitRes),
          eventId: complianceEvent.event_id,
          nowIso: nowIso(),
          attemptDelta: 0
          // enqueue above already counted this attempt.
        });
        await kvPutJson(env.FLUXIDI_TRACKING, targetKey, target2, TTL_TRIP);
        _chironSyncLog(
          nextState === COMPLIANCE_EMIT_STATE.APPLIED ? "applied" : "failed",
          target2,
          trip_id,
          complianceEvent,
          nextState,
          complianceEmitErrorCodeFromResult(emitRes) || "ok"
        );
      } catch (_) {
        _chironSyncLog("failed", trip, trip_id, complianceEvent, "pending", "kv_write_failed");
      }
    })();
    if (ctx && typeof ctx.waitUntil === "function") {
      ctx.waitUntil(emitTask);
    } else {
      await emitTask;
    }
  }
  const stopFinalizeFields = safeBookingFinalizeResponseFields(trip);
  const complianceFields = safeComplianceEmitResponseFields(trip);
  return withCors(
    json2(
      {
        ok: true,
        trip_id,
        booking_id: stopFinalizeFields.booking_id,
        booking_finalize_state: stopFinalizeFields.booking_finalize_state,
        booking_finalized: stopFinalizeFields.booking_finalized,
        status: "stopped",
        stopped_at: stoppedAt,
        totals,
        ...complianceFields
      },
      { status: 200 }
    ),
    origin
  );
}
__name(handleStopTrip, "handleStopTrip");
async function handleReconcileDirectBooking(req, url, env, origin) {
  const rawBody = await readJson(req);
  const auth = await requireDriverSessionOrAdminForScope(req, url, env, {
    body: rawBody,
    routeLabel: "TRIP_RECONCILE_DIRECT_BOOKING"
  });
  if (!auth.ok) return auth.response;
  const body = applyDriverSessionToBody(rawBody, auth.driver_session);
  const requiredScope = parseRequiredTenantCompanyScope(req, url, body, { returnResponse: true, origin });
  if (requiredScope instanceof Response) return requiredScope;
  const scope2 = requiredScope;
  const actor = resolveTrackingActorFromRequest(req, url, body);
  const trip_id = safeStr22(body["trip_id"], 128);
  if (!trip_id) throw new Error("trip_id is required");
  const tripResolved = await getScopedOrLegacyTripForScope(env, scope2, trip_id);
  const trip = tripResolved.trip;
  if (!trip) throw new Error("Unknown trip_id");
  if (!recordMatchesTenantCompanyScope(trip, scope2)) throw new Error("invalid trip scope");
  const key2 = tripResolved.key;
  const ownershipBlock = await _assertTripOwnedByActorOrBlock({
    trip,
    trip_id,
    actor,
    error: "trip_not_assigned_to_driver",
    origin
  });
  if (ownershipBlock) return ownershipBlock;
  if (directTripStartRetryEligible(trip)) {
    await ensureDirectTripStartComplianceEmit(env, {
      trip,
      key: key2,
      scope: scope2,
      startedAt: trip.started_at || trip.startedAt || nowIso(),
      logLabel: "reconcile_retry_start",
      timeoutMs: 1500
    });
  }
  if (complianceEmitRetryEligible(trip)) {
    await ensureDirectTripStopComplianceEmit(env, {
      trip,
      key: key2,
      scope: scope2,
      body,
      tripId: trip_id,
      logLabel: "reconcile_retry",
      timeoutMs: 1500
    });
  }
  if (["stopped", "completed", "done"].includes(trip.status) || trip.stopped_at) {
    await syncDirectDispatchOccupancy(env, trip, "stop");
  }
  if (bookingAlreadyFinalized(trip)) {
    const already = safeBookingFinalizeResponseFields(trip);
    return withCors(
      json2({ ok: true, trip_id, reconciled: false, reason: DIRECT_RECONCILE_REASON.ALREADY_COMPLETED, ...already }, { status: 200 }),
      origin
    );
  }
  const elig = tripReconcileEligibility(trip);
  if (!elig.ok) {
    return withCors(
      json2({ ok: false, trip_id, reconciled: false, reason: elig.reason, ...safeBookingFinalizeResponseFields(trip) }, { status: 409 }),
      origin
    );
  }
  const finalizePayload = buildFinalizePayloadFromTrip(trip, scope2);
  let finalizeRes = null;
  try {
    finalizeRes = await _callBookingWorkerJson(
      env,
      "/track/booking/finalize-direct",
      finalizePayload,
      { timeoutMs: 4e3 }
    );
  } catch (err) {
    finalizeRes = { ok: false, error: safeStr22(err?.message || err, 120) || "finalize_call_failed" };
  }
  applyBookingFinalizeAttempt(trip, {
    state: deriveFinalizeStateFromResult(finalizeRes),
    errorCode: finalizeErrorCodeFromResult(finalizeRes),
    nowIso: nowIso()
  });
  applyCanonicalScopeToRecord(trip, scope2);
  await kvPutJson(env.FLUXIDI_TRACKING, key2, trip, TTL_TRIP);
  const out = safeBookingFinalizeResponseFields(trip);
  console.log(
    `[DIRECT_TRIP][RECONCILE] trip=${trip_id} booking=${directBookingIdFromTrip(trip)} state=${out.booking_finalize_state} attempt=${trip.booking_finalize_attempt_count}`
  );
  return withCors(
    json2(
      {
        ok: out.booking_finalized,
        trip_id,
        reconciled: out.booking_finalized,
        reason: out.booking_finalized ? DIRECT_RECONCILE_REASON.REPAIRABLE : finalizeErrorCodeFromResult(finalizeRes) || "pending",
        ...out
      },
      { status: 200 }
    ),
    origin
  );
}
__name(handleReconcileDirectBooking, "handleReconcileDirectBooking");
async function handleReconcilePlannedStop(req, url, env, origin) {
  const rawBody = await readJson(req);
  const auth = await requireDriverSessionOrAdminForScope(req, url, env, {
    body: rawBody,
    routeLabel: "TRIP_RECONCILE_PLANNED_STOP"
  });
  if (!auth.ok) return auth.response;
  const body = applyDriverSessionToBody(rawBody, auth.driver_session);
  const requiredScope = parseRequiredTenantCompanyScope(req, url, body, { returnResponse: true, origin });
  if (requiredScope instanceof Response) return requiredScope;
  const scope2 = requiredScope;
  const actor = resolveTrackingActorFromRequest(req, url, body);
  const trip_id = safeStr22(body["trip_id"], 160);
  if (!trip_id) throw new Error("trip_id is required");
  const tripResolved = await getScopedOrLegacyTripForScope(env, scope2, trip_id);
  const trip = tripResolved.trip;
  if (!trip) throw new Error("Unknown trip_id");
  if (!recordMatchesTenantCompanyScope(trip, scope2)) throw new Error("invalid trip scope");
  const key2 = tripResolved.key;
  const ownershipBlock = await _assertTripOwnedByActorOrBlock({
    trip,
    trip_id,
    actor,
    error: "trip_not_assigned_to_driver",
    origin
  });
  if (ownershipBlock) return ownershipBlock;
  const kind = _dbfStr(trip.kind).toLowerCase();
  if (kind && kind !== "planned") {
    return withCors(
      json2({ ok: false, trip_id, reason: "not_planned", kind }, { status: 409 }),
      origin
    );
  }
  if (complianceEmitAlreadyApplied(trip)) {
    return withCors(
      json2(
        {
          ok: true,
          trip_id,
          reconciled: false,
          reason: "already_applied",
          ...safeComplianceEmitResponseFields(trip)
        },
        { status: 200 }
      ),
      origin
    );
  }
  if (!plannedTripComplianceEmitRetryEligible(trip)) {
    return withCors(
      json2(
        {
          ok: false,
          trip_id,
          reconciled: false,
          reason: plannedTripIsStopped(trip) ? "not_pending" : "non_terminal",
          ...safeComplianceEmitResponseFields(trip)
        },
        { status: 409 }
      ),
      origin
    );
  }
  const reconcileBookingId = safeStr22(
    trip?.parent_booking_id ?? trip?.parentBookingId ?? trip?.booking_id ?? trip?.bookingId,
    96
  ) || null;
  const reconcileBookingRecord = await _loadBookingRecordForPlannedStopBestEffort(
    env,
    scope2,
    reconcileBookingId
  );
  const reconcileFare = resolvePlannedStopTotalEur({
    bookingRecord: reconcileBookingRecord,
    bookingDetails: trip?.booking_details ?? null,
    legId: trip?.leg_id ?? trip?.legId ?? null,
    legType: trip?.leg_type ?? trip?.legType ?? null,
    clientTotalEur: null,
    existingTripTotalEur: trip?.total_eur ?? trip?.price_incl_vat
  });
  if (reconcileFare.total_eur != null && _plannedStopPositiveMoney(trip.total_eur ?? trip.price_incl_vat) == null) {
    trip.total_eur = reconcileFare.total_eur;
    trip.price_incl_vat = reconcileFare.total_eur;
    trip.fare_source = reconcileFare.source;
    await kvPutJson(env.FLUXIDI_TRACKING, key2, trip, TTL_TRIP);
    console.log(
      `[TRACKING][PLANNED_STOP][FARE_REPAIR] trip=${trip_id} source=${reconcileFare.source} total=${Number(reconcileFare.total_eur).toFixed(2)}`
    );
  }
  const retryEvent = buildPlannedTripStopComplianceEvent(trip, body, scope2);
  if (!retryEvent) {
    return withCors(
      json2(
        {
          ok: false,
          trip_id,
          reconciled: false,
          reason: "missing_scope",
          ...safeComplianceEmitResponseFields(trip)
        },
        { status: 409 }
      ),
      origin
    );
  }
  const retryEventId = _dbfStr(trip.compliance_emit_event_id, 200) || buildDeterministicRideStopEventId(
    retryEvent.tenant_id,
    retryEvent.company_id,
    retryEvent.trip_id ?? trip_id
  );
  if (retryEventId) retryEvent.event_id = retryEventId;
  let emitRes;
  try {
    emitRes = await emitComplianceEventBestEffort(env, retryEvent, {
      timeoutMs: 1500,
      logLabel: "reconcile_planned_stop_retry"
    });
  } catch (err) {
    emitRes = { ok: false, error: _dbfStr(err?.message || err, 120) || "internal_error" };
  }
  const nextState = deriveComplianceEmitStateFromResult(emitRes);
  applyComplianceEmitAttempt(trip, {
    state: nextState,
    errorCode: complianceEmitErrorCodeFromResult(emitRes),
    eventId: retryEventId,
    nowIso: nowIso()
  });
  applyCanonicalScopeToRecord(trip, scope2);
  await kvPutJson(env.FLUXIDI_TRACKING, key2, trip, TTL_TRIP);
  _chironSyncLog(
    "retry",
    trip,
    trip_id,
    retryEvent,
    nextState,
    complianceEmitErrorCodeFromResult(emitRes) || "ok"
  );
  const applied = nextState === COMPLIANCE_EMIT_STATE.APPLIED;
  return withCors(
    json2(
      {
        ok: applied,
        trip_id,
        reconciled: applied,
        reason: applied ? "applied" : complianceEmitErrorCodeFromResult(emitRes) || "pending",
        ...safeComplianceEmitResponseFields(trip)
      },
      { status: 200 }
    ),
    origin
  );
}
__name(handleReconcilePlannedStop, "handleReconcilePlannedStop");
async function handleReconcilePlannedSessionStart(req, url, env, origin) {
  const rawBody = await readJson(req);
  const auth = await requireDriverSessionOrAdminForScope(req, url, env, {
    body: rawBody,
    routeLabel: "TRACK_SESSION_RECONCILE_START"
  });
  if (!auth.ok) return auth.response;
  const body = applyDriverSessionToBody(rawBody, auth.driver_session);
  const requiredScope = parseRequiredTenantCompanyScope(req, url, body, { returnResponse: true, origin });
  if (requiredScope instanceof Response) return requiredScope;
  const scope2 = requiredScope;
  const actor = resolveTrackingActorFromRequest(req, url, body);
  const session_id = safeStr22(body["session_id"], 160);
  if (!session_id) throw new Error("session_id is required");
  const sessionKey = scopedSessionKey(scope2, session_id);
  const session = await kvGetJson(env.FLUXIDI_TRACKING, sessionKey);
  if (!session) throw new Error("Unknown session_id");
  if (!recordMatchesTenantCompanyScope(session, scope2)) throw new Error("invalid session scope");
  const ownershipBlock = await _assertSessionOwnedByActorOrBlock({
    session,
    session_id,
    actor,
    error: "session_not_assigned_to_driver",
    origin
  });
  if (ownershipBlock) return ownershipBlock;
  if (complianceEmitStartAlreadyApplied(session)) {
    return withCors(
      json2(
        {
          ok: true,
          session_id,
          reconciled: false,
          reason: "already_applied",
          ...safeComplianceEmitStartResponseFields(session)
        },
        { status: 200 }
      ),
      origin
    );
  }
  if (!complianceEmitStartRetryEligible(session)) {
    return withCors(
      json2(
        {
          ok: false,
          session_id,
          reconciled: false,
          reason: "not_pending",
          ...safeComplianceEmitStartResponseFields(session)
        },
        { status: 409 }
      ),
      origin
    );
  }
  const startedAt = _dbfStr(session?.started_at ?? session?.startedAt ?? session?.created_at, 64) || nowIso();
  const retryEvent = buildPlannedSessionStartComplianceEvent(session, body, startedAt, scope2);
  if (!retryEvent) {
    return withCors(
      json2(
        {
          ok: false,
          session_id,
          reconciled: false,
          reason: "missing_scope",
          ...safeComplianceEmitStartResponseFields(session)
        },
        { status: 409 }
      ),
      origin
    );
  }
  const retryEventId = _dbfStr(session.compliance_emit_start_event_id, 200) || buildDeterministicRideStartEventId(
    retryEvent.tenant_id,
    retryEvent.company_id,
    session_id
  );
  if (retryEventId) retryEvent.event_id = retryEventId;
  let emitRes;
  try {
    emitRes = await emitComplianceEventBestEffort(env, retryEvent, {
      timeoutMs: 1500,
      logLabel: "reconcile_planned_start_retry"
    });
  } catch (err) {
    emitRes = { ok: false, error: _dbfStr(err?.message || err, 120) || "internal_error" };
  }
  const nextState = deriveComplianceEmitStateFromResult(emitRes);
  applyComplianceEmitStartAttempt(session, {
    state: nextState,
    errorCode: complianceEmitErrorCodeFromResult(emitRes),
    eventId: retryEventId,
    nowIso: nowIso()
  });
  applyCanonicalScopeToRecord(session, scope2);
  await kvPutJson(env.FLUXIDI_TRACKING, sessionKey, session, TTL_SESSION);
  _chironSyncLog(
    "retry_start",
    session,
    session_id,
    retryEvent,
    nextState,
    complianceEmitErrorCodeFromResult(emitRes) || "ok"
  );
  const applied = nextState === COMPLIANCE_EMIT_STATE.APPLIED;
  return withCors(
    json2(
      {
        ok: applied,
        session_id,
        reconciled: applied,
        reason: applied ? "applied" : complianceEmitErrorCodeFromResult(emitRes) || "pending",
        ...safeComplianceEmitStartResponseFields(session)
      },
      { status: 200 }
    ),
    origin
  );
}
__name(handleReconcilePlannedSessionStart, "handleReconcilePlannedSessionStart");
async function handleRecoverPlannedPending(req, url, env, origin) {
  const rawBody = await readJson(req);
  const auth = await requireDriverSessionOrAdminForScope(req, url, env, {
    body: rawBody,
    routeLabel: "PLANNED_RECOVER_PENDING"
  });
  if (!auth.ok) return auth.response;
  const body = applyDriverSessionToBody(rawBody, auth.driver_session);
  const requiredScope = parseRequiredTenantCompanyScope(req, url, body, {
    returnResponse: true,
    origin
  });
  if (requiredScope instanceof Response) return requiredScope;
  const scope2 = requiredScope;
  const actor = resolveTrackingActorFromRequest(req, url, body);
  const limitRaw = Number(body?.limit);
  const limit2 = Number.isFinite(limitRaw) ? Math.max(1, Math.min(100, Math.floor(limitRaw))) : 25;
  const summary = {
    scanned_trips: 0,
    scanned_sessions: 0,
    eligible_stops: 0,
    eligible_starts: 0,
    reconciled_stops: 0,
    reconciled_starts: 0,
    still_pending_stops: 0,
    still_pending_starts: 0,
    already_applied_stops: 0,
    already_applied_starts: 0,
    skipped_scope_mismatch: 0,
    skipped_direct_kind: 0,
    skipped_non_terminal: 0,
    skipped_missing: 0,
    errors: 0
  };
  try {
    const tripsIndex = await kvGetJson(env.FLUXIDI_TRACKING, scopedTripsIndexKey(scope2)) ?? [];
    const tripIds = Array.isArray(tripsIndex) ? tripsIndex.slice(0, limit2) : [];
    for (const rawTripId of tripIds) {
      const tripId = safeStr22(rawTripId, 160);
      if (!tripId) continue;
      summary.scanned_trips++;
      try {
        const resolved = await getScopedOrLegacyTripForScope(env, scope2, tripId);
        const trip = resolved.trip;
        if (!trip) {
          summary.skipped_missing++;
          continue;
        }
        if (!recordMatchesTenantCompanyScope(trip, scope2)) {
          summary.skipped_scope_mismatch++;
          continue;
        }
        const kind = _dbfStr(trip.kind).toLowerCase();
        if (kind && kind !== "planned") {
          summary.skipped_direct_kind++;
          continue;
        }
        if (complianceEmitAlreadyApplied(trip)) {
          summary.already_applied_stops++;
          continue;
        }
        if (!plannedTripComplianceEmitRetryEligible(trip)) {
          if (!plannedTripIsStopped(trip)) summary.skipped_non_terminal++;
          continue;
        }
        if (actor && actor.driver_id && trip.driver_id && trip.driver_id !== actor.driver_id) {
          continue;
        }
        summary.eligible_stops++;
        const retryEvent = buildPlannedTripStopComplianceEvent(trip, body, scope2);
        if (!retryEvent) {
          summary.errors++;
          continue;
        }
        const retryEventId = _dbfStr(trip.compliance_emit_event_id, 200) || buildDeterministicRideStopEventId(
          retryEvent.tenant_id,
          retryEvent.company_id,
          retryEvent.trip_id ?? tripId
        );
        if (retryEventId) retryEvent.event_id = retryEventId;
        let emitRes;
        try {
          emitRes = await emitComplianceEventBestEffort(env, retryEvent, {
            timeoutMs: 1500,
            logLabel: "recover_planned_stop"
          });
        } catch (err) {
          emitRes = {
            ok: false,
            error: _dbfStr(err?.message || err, 120) || "internal_error"
          };
        }
        const nextState = deriveComplianceEmitStateFromResult(emitRes);
        applyComplianceEmitAttempt(trip, {
          state: nextState,
          errorCode: complianceEmitErrorCodeFromResult(emitRes),
          eventId: retryEventId,
          nowIso: nowIso()
        });
        applyCanonicalScopeToRecord(trip, scope2);
        await kvPutJson(env.FLUXIDI_TRACKING, resolved.key, trip, TTL_TRIP);
        _chironSyncLog(
          "recover",
          trip,
          tripId,
          retryEvent,
          nextState,
          complianceEmitErrorCodeFromResult(emitRes) || "ok"
        );
        if (nextState === COMPLIANCE_EMIT_STATE.APPLIED) summary.reconciled_stops++;
        else summary.still_pending_stops++;
      } catch (_) {
        summary.errors++;
      }
    }
  } catch (_) {
    summary.errors++;
  }
  try {
    const bookingsIndex = await kvGetJson(env.FLUXIDI_TRACKING, scopedBookingIndexKey(scope2)) ?? [];
    const bookingIds = Array.isArray(bookingsIndex) ? bookingsIndex.slice(0, limit2) : [];
    for (const rawBookingId of bookingIds) {
      const bookingId = safeStr22(rawBookingId, 160);
      if (!bookingId) continue;
      try {
        const mapResolved = await getScopedOrLegacyBookingMapForScope(env, scope2, bookingId);
        const map22 = mapResolved.map;
        const sessionId = safeStr22(map22?.session_id ?? map22?.sessionId, 200);
        if (!sessionId) {
          summary.skipped_missing++;
          continue;
        }
        summary.scanned_sessions++;
        const sessResolved = await getScopedOrLegacySessionForScope(env, scope2, sessionId);
        const session = sessResolved.session;
        if (!session) {
          summary.skipped_missing++;
          continue;
        }
        if (!recordMatchesTenantCompanyScope(session, scope2)) {
          summary.skipped_scope_mismatch++;
          continue;
        }
        if (complianceEmitStartAlreadyApplied(session)) {
          summary.already_applied_starts++;
          continue;
        }
        if (!complianceEmitStartRetryEligible(session)) {
          continue;
        }
        if (actor && actor.driver_id && session.driver_id && session.driver_id !== actor.driver_id) {
          continue;
        }
        summary.eligible_starts++;
        const startedAt = _dbfStr(session?.started_at ?? session?.startedAt ?? session?.created_at, 64) || nowIso();
        const retryEvent = buildPlannedSessionStartComplianceEvent(session, body, startedAt, scope2);
        if (!retryEvent) {
          summary.errors++;
          continue;
        }
        const retryEventId = _dbfStr(session.compliance_emit_start_event_id, 200) || buildDeterministicRideStartEventId(
          retryEvent.tenant_id,
          retryEvent.company_id,
          sessionId
        );
        if (retryEventId) retryEvent.event_id = retryEventId;
        let emitRes;
        try {
          emitRes = await emitComplianceEventBestEffort(env, retryEvent, {
            timeoutMs: 1500,
            logLabel: "recover_planned_start"
          });
        } catch (err) {
          emitRes = {
            ok: false,
            error: _dbfStr(err?.message || err, 120) || "internal_error"
          };
        }
        const nextState = deriveComplianceEmitStateFromResult(emitRes);
        applyComplianceEmitStartAttempt(session, {
          state: nextState,
          errorCode: complianceEmitErrorCodeFromResult(emitRes),
          eventId: retryEventId,
          nowIso: nowIso()
        });
        applyCanonicalScopeToRecord(session, scope2);
        await kvPutJson(env.FLUXIDI_TRACKING, sessResolved.key, session, TTL_SESSION);
        _chironSyncLog(
          "recover_start",
          session,
          sessionId,
          retryEvent,
          nextState,
          complianceEmitErrorCodeFromResult(emitRes) || "ok"
        );
        if (nextState === COMPLIANCE_EMIT_STATE.APPLIED) summary.reconciled_starts++;
        else summary.still_pending_starts++;
      } catch (_) {
        summary.errors++;
      }
    }
  } catch (_) {
    summary.errors++;
  }
  return withCors(json2({ ok: true, limit: limit2, ...summary }, { status: 200 }), origin);
}
__name(handleRecoverPlannedPending, "handleRecoverPlannedPending");
async function handleRepairDirectBookings(req, url, env, origin) {
  requireAdmin(req, url, env);
  const body = await readJson(req);
  const requiredScope = parseRequiredTenantCompanyScope(req, url, body, { returnResponse: true, origin });
  if (requiredScope instanceof Response) return requiredScope;
  const scope2 = requiredScope;
  const dryRun = body?.dry_run !== false && body?.dryRun !== false;
  const limitRaw = Number(body?.limit ?? body?.batch_size);
  const limit2 = Number.isFinite(limitRaw) ? Math.max(1, Math.min(200, Math.floor(limitRaw))) : 50;
  const cursorRaw = Number(body?.cursor);
  const cursorStart = Number.isFinite(cursorRaw) ? Math.max(0, Math.floor(cursorRaw)) : 0;
  const indexKey = scopedTripsIndexKey(scope2);
  const idsRaw = await kvGetJson(env.FLUXIDI_TRACKING, indexKey) ?? [];
  const tripIds = Array.isArray(idsRaw) ? idsRaw : [];
  const slice = tripIds.slice(cursorStart, cursorStart + limit2);
  const summary = {
    candidates: 0,
    repairable: 0,
    skipped_non_terminal: 0,
    skipped_missing_trip: 0,
    skipped_missing_fare: 0,
    already_completed: 0,
    errors: 0
  };
  for (const rawTripId of slice) {
    const tripId = safeStr22(rawTripId, 160);
    if (!tripId) continue;
    try {
      const resolved = await getScopedOrLegacyTripForScope(env, scope2, tripId);
      const trip = resolved.trip;
      if (!trip || !recordMatchesTenantCompanyScope(trip, scope2)) {
        summary.skipped_missing_trip++;
        continue;
      }
      if (!isStreetDirectTrip(trip)) continue;
      summary.candidates++;
      if (bookingAlreadyFinalized(trip)) {
        summary.already_completed++;
        continue;
      }
      const elig = tripReconcileEligibility(trip);
      if (!elig.ok) {
        if (elig.reason === DIRECT_RECONCILE_REASON.NON_TERMINAL) summary.skipped_non_terminal++;
        else if (elig.reason === DIRECT_RECONCILE_REASON.MISSING_FARE) summary.skipped_missing_fare++;
        else summary.skipped_missing_trip++;
        continue;
      }
      summary.repairable++;
      if (!dryRun) {
        let finalizeRes = null;
        try {
          finalizeRes = await _callBookingWorkerJson(
            env,
            "/track/booking/finalize-direct",
            buildFinalizePayloadFromTrip(trip, scope2),
            { timeoutMs: 4e3 }
          );
        } catch (err) {
          finalizeRes = { ok: false, error: safeStr22(err?.message || err, 120) || "finalize_call_failed" };
        }
        applyBookingFinalizeAttempt(trip, {
          state: deriveFinalizeStateFromResult(finalizeRes),
          errorCode: finalizeErrorCodeFromResult(finalizeRes),
          nowIso: nowIso()
        });
        applyCanonicalScopeToRecord(trip, scope2);
        await kvPutJson(env.FLUXIDI_TRACKING, resolved.key, trip, TTL_TRIP);
        if (finalizeRes?.ok !== true) summary.errors++;
      }
    } catch (_) {
      summary.errors++;
    }
  }
  const nextCursor = cursorStart + slice.length;
  const hasMore = nextCursor < tripIds.length;
  console.log(
    `[DIRECT_TRIP][REPAIR] dry_run=${dryRun} scanned=${slice.length} candidates=${summary.candidates} repairable=${summary.repairable} already_completed=${summary.already_completed} skipped_non_terminal=${summary.skipped_non_terminal} skipped_missing_fare=${summary.skipped_missing_fare} skipped_missing_trip=${summary.skipped_missing_trip} errors=${summary.errors}`
  );
  return withCors(
    json2(
      {
        ok: true,
        dry_run: dryRun,
        summary,
        scanned: slice.length,
        index_size: tripIds.length,
        cursor: hasMore ? nextCursor : null
      },
      { status: 200 }
    ),
    origin
  );
}
__name(handleRepairDirectBookings, "handleRepairDirectBookings");
async function handleTripPayment(req, url, env, origin, ctx) {
  requireAdmin(req, url, env);
  const body = await readJson(req);
  const requiredScope = parseRequiredTenantCompanyScope(req, url, body, { returnResponse: true, origin });
  if (requiredScope instanceof Response) return requiredScope;
  const scope2 = requiredScope;
  const actor = resolveTrackingActorFromRequest(req, url, body);
  const trip_id = safeStr22(body["trip_id"], 128);
  if (!trip_id) throw new Error("trip_id is required");
  const tripResolved = await getScopedOrLegacyTripForScope(env, scope2, trip_id);
  const trip = tripResolved.trip;
  if (!trip) throw new Error("Unknown trip_id");
  if (!recordMatchesTenantCompanyScope(trip, scope2)) throw new Error("invalid trip scope");
  const key2 = tripResolved.key;
  const ownershipBlock = await _assertTripOwnedByActorOrBlock({
    trip,
    trip_id,
    actor,
    error: "trip_not_assigned_to_driver",
    origin
  });
  if (ownershipBlock) return ownershipBlock;
  const rawStatus = String(body["payment_status"] ?? body["paymentStatus"] ?? "").trim().toLowerCase();
  const payment_status = rawStatus === "paid" || rawStatus === "confirmed" || rawStatus === "completed" || rawStatus === "success" || rawStatus === "settled" ? "paid" : rawStatus === "pending" || rawStatus === "authorized" || rawStatus === "open" ? "pending" : rawStatus === "failed" || rawStatus === "cancelled" || rawStatus === "canceled" ? "failed" : "paid";
  const payment_method = safeStr22(
    String(body["payment_method"] ?? body["paymentMethod"] ?? "").toLowerCase(),
    32
  );
  const payment_source = safeStr22(
    String(body["payment_source"] ?? body["paymentSource"] ?? "in_car").toLowerCase(),
    32
  ) ?? "in_car";
  const paid_at = safeStr22(body["paid_at"] ?? body["paidAt"], 64) ?? nowIso();
  const currency = (safeStr22(body["currency"], 8) ?? safeStr22(trip?.currency, 8) ?? safeStr22(trip?.pricing_snapshot?.currency, 8) ?? "EUR").toUpperCase();
  const amountRaw = body["amount"] ?? body["price"] ?? body["total"];
  const amountNum = Number(amountRaw);
  const amount = Number.isFinite(amountNum) ? amountNum : null;
  const paid_by_driver_id = safeStr22(
    body["paid_by_driver_id"] ?? body["paidByDriverId"],
    96
  );
  const leg_id = safeStr22(
    body["leg_id"] ?? body["legId"] ?? trip?.leg_id ?? trip?.legId,
    160
  );
  const leg_type = safeStr22(
    body["leg_type"] ?? body["legType"] ?? trip?.leg_type ?? trip?.legType,
    64
  );
  const parent_booking_id = safeStr22(
    body["parent_booking_id"] ?? body["parentBookingId"] ?? trip?.parent_booking_id ?? trip?.parentBookingId,
    160
  );
  const row_key = safeStr22(
    body["row_key"] ?? body["rowKey"] ?? trip?.row_key ?? trip?.rowKey,
    240
  );
  trip.payment_status = payment_status;
  trip.paymentStatus = payment_status;
  trip.payment_source = payment_source;
  trip.paymentSource = payment_source;
  trip.paid_at = paid_at;
  trip.paidAt = paid_at;
  trip.currency = currency;
  if (payment_method) {
    trip.payment_method = payment_method;
    trip.paymentMethod = payment_method;
  }
  if (amount !== null) {
    trip.payment_amount = amount;
    trip.paymentAmount = amount;
  }
  if (paid_by_driver_id) {
    trip.paid_by_driver_id = paid_by_driver_id;
    trip.paidByDriverId = paid_by_driver_id;
  }
  if (leg_id) {
    trip.leg_id = leg_id;
    trip.legId = leg_id;
  }
  if (leg_type) {
    trip.leg_type = leg_type;
    trip.legType = leg_type;
  }
  if (parent_booking_id) {
    trip.parent_booking_id = parent_booking_id;
    trip.parentBookingId = parent_booking_id;
  }
  if (row_key) {
    trip.row_key = row_key;
    trip.rowKey = row_key;
  }
  if (leg_id || leg_type || row_key) {
    trip.is_operational_leg = true;
    trip.isOperationalLeg = true;
  }
  const nextBookingDetails = trip?.booking_details && typeof trip.booking_details === "object" && !Array.isArray(trip.booking_details) ? { ...trip.booking_details } : {};
  if (leg_id) {
    nextBookingDetails.leg_id = leg_id;
    nextBookingDetails.legId = leg_id;
  }
  if (leg_type) {
    nextBookingDetails.leg_type = leg_type;
    nextBookingDetails.legType = leg_type;
  }
  if (parent_booking_id) {
    nextBookingDetails.parent_booking_id = parent_booking_id;
    nextBookingDetails.parentBookingId = parent_booking_id;
  }
  if (row_key) {
    nextBookingDetails.row_key = row_key;
    nextBookingDetails.rowKey = row_key;
  }
  if (leg_id || leg_type || row_key) {
    nextBookingDetails.is_operational_leg = true;
    nextBookingDetails.isOperationalLeg = true;
  }
  nextBookingDetails.payment_status = payment_status;
  nextBookingDetails.paymentStatus = payment_status;
  nextBookingDetails.payment_source = payment_source;
  nextBookingDetails.paymentSource = payment_source;
  nextBookingDetails.paid_at = paid_at;
  nextBookingDetails.paidAt = paid_at;
  if (payment_method) {
    nextBookingDetails.payment_method = payment_method;
    nextBookingDetails.paymentMethod = payment_method;
  }
  if (amount !== null) {
    nextBookingDetails.payment_amount = amount;
    nextBookingDetails.paymentAmount = amount;
  }
  const normalizedBookingDetails = normalizeBookingDetails(nextBookingDetails);
  if (normalizedBookingDetails) {
    trip.booking_details = normalizedBookingDetails;
  }
  const timeline = Array.isArray(trip.timeline) ? trip.timeline : [];
  timeline.push({
    type: "payment_marked",
    ts: paid_at,
    source: "driver_app",
    payment_status,
    payment_method: payment_method ?? null,
    payment_source,
    currency,
    amount,
    paid_by_driver_id: paid_by_driver_id ?? null
  });
  trip.timeline = timeline;
  applyCanonicalScopeToRecord(trip, scope2);
  const tripIdPreview = _tripKpiMask(trip_id) || "-";
  const bookingIdPreview = _tripKpiMask(safeStr22(trip?.booking_id ?? trip?.bookingId, 96)) || "-";
  const legIdPreview = _tripKpiMask(leg_id) || "-";
  console.log(
    `[TRIP_PAYMENT][UPDATE] trip=${tripIdPreview} booking=${bookingIdPreview} leg=${legIdPreview} type=${leg_type || "-"} status=${payment_status} method=${payment_method || "-"} amount=${amount !== null ? amount : "-"}`
  );
  await kvPutJson(env.FLUXIDI_TRACKING, key2, trip, TTL_TRIP);
  await materializeTripDashboardKpisBestEffort(
    env,
    scope2,
    trip,
    "trip_payment_update"
  );
  const complianceEvent = buildTripPaymentUpdateComplianceEvent(trip, body, scope2);
  if (!complianceEvent) {
    console.log(`[COMPLIANCE_EMIT][direct_payment_update] skipped reason=missing_canonical_scope trip_id=${trip_id}`);
  }
  if (complianceEvent) {
    const emitTask = emitComplianceEventBestEffort(env, complianceEvent, {
      timeoutMs: 1500,
      logLabel: "direct_payment_update"
    });
    if (ctx && typeof ctx.waitUntil === "function") {
      ctx.waitUntil(emitTask);
    } else {
      await emitTask;
    }
  }
  return withCors(
    json2(
      {
        ok: true,
        trip_id,
        payment: {
          payment_status,
          payment_method: payment_method ?? null,
          payment_source,
          paid_at,
          currency,
          amount,
          paid_by_driver_id: paid_by_driver_id ?? null
        },
        trip: summarizeTrip(trip)
      },
      { status: 200 }
    ),
    origin
  );
}
__name(handleTripPayment, "handleTripPayment");
async function handleStart(req, url, env, origin, ctx) {
  const rawBody = await readJson(req);
  const auth = await requireDriverSessionOrAdminForScope(req, url, env, {
    body: rawBody,
    routeLabel: "TRACK_SESSION_START"
  });
  if (!auth.ok) return auth.response;
  const body = applyDriverSessionToBody(rawBody, auth.driver_session);
  const requiredScope = parseRequiredTenantCompanyScope(req, url, body, { returnResponse: true, origin });
  if (requiredScope instanceof Response) return requiredScope;
  const scope2 = requiredScope;
  const actor = resolveTrackingActorFromRequest(req, url, body);
  const booking_id = safeStr22(body["booking_id"], 64);
  if (!booking_id) throw new Error("booking_id is required");
  const pickup = safeStr22(body["pickup"], 200) ?? null;
  const dropoff = safeStr22(body["dropoff"], 200) ?? null;
  const originData = normalizeDestination(body["origin"]);
  const startedAt = safeStr22(body["client_started_at"], 64) ?? nowIso();
  const tenant_id = scope2.tenant_id;
  const company_id = scope2.company_id;
  const owner_driver_id = safeStr22(body["driver_id"], 96) ?? actor.actor_driver_id ?? null;
  const owner_vehicle_id = safeStr22(body["vehicle_id"], 96) ?? actor.actor_vehicle_id ?? null;
  const directStartOwnerCheck = _trackingOwnershipAllowed({
    actorDriverId: actor.actor_driver_id,
    actorVehicleId: actor.actor_vehicle_id,
    ownerDriverId: owner_driver_id,
    ownerVehicleId: owner_vehicle_id
  });
  const directStartOwnershipPassed = directStartOwnerCheck.allowed && (directStartOwnerCheck.reason === "driver_match" || directStartOwnerCheck.reason === "vehicle_match");
  if (actor.actor_role === "driver") {
    _logTrackingOwnershipCheck({
      target: "session_start_payload",
      targetId: booking_id,
      actor,
      ownerDriverId: directStartOwnerCheck.candidateDriver,
      ownerVehicleId: directStartOwnerCheck.candidateVehicle,
      allowed: directStartOwnerCheck.allowed,
      reason: directStartOwnerCheck.reason
    });
  }
  if (actor.actor_role === "driver" && !actor.actor_driver_id) {
    _logTrackingOwnershipBlock({
      target: "session_start",
      targetId: booking_id,
      actor,
      ownerDriverId: owner_driver_id,
      ownerVehicleId: owner_vehicle_id,
      error: "booking_not_assigned_to_driver"
    });
    return withCors(json2(_trackingOwnershipError("booking_not_assigned_to_driver"), { status: 403 }), origin);
  }
  if (actor.actor_role === "driver") {
    const explicitLeg = safeStr22(body.operational_leg || body.leg_id || body.legId, 200);
    let existingBookingMap;
    if (explicitLeg && realtimeDoEnabled(env)) {
      let selectedGrant;
      try {
        selectedGrant = await readCustomerGrant(env, scope2, booking_id, explicitLeg, "", true);
      } catch (_) {
        return withCors(json2({ ok: false, error: "tracking_binding_unavailable", retryable: true }, { status: 503 }), origin);
      }
      if (!selectedGrant || selectedGrant.driver_id !== actor.actor_driver_id || selectedGrant.operational_leg !== explicitLeg || !["assigned", "en_route_pickup", "arrived_pickup", "in_progress"].includes(selectedGrant.tracking_phase)) {
        return withCors(json2(_trackingOwnershipError("booking_not_assigned_to_driver"), { status: 403 }), origin);
      }
      existingBookingMap = { ...scope2, owner_driver_id: selectedGrant.driver_id };
    } else {
      existingBookingMap = await kvGetJson(env.FLUXIDI_TRACKING, scopedBookingSessionKey(scope2, booking_id));
    }
    let assignmentOwnershipPassed = false;
    if (existingBookingMap && !recordMatchesTenantCompanyScope(existingBookingMap, scope2)) {
      throw new Error("invalid booking scope");
    }
    if (existingBookingMap) {
      const existingSessionId = safeStr22(existingBookingMap.session_id ?? existingBookingMap.sessionId, 128);
      const existingSession = existingSessionId ? await kvGetJson(env.FLUXIDI_TRACKING, scopedSessionKey(scope2, existingSessionId)) : null;
      if (existingSession && !recordMatchesTenantCompanyScope(existingSession, scope2)) {
        throw new Error("invalid session scope");
      }
      const assignmentOwnerDriverId = _trackingOwnershipValue(
        existingBookingMap.owner_driver_id ?? existingBookingMap.assigned_driver_id ?? existingBookingMap.assignedDriverId ?? existingBookingMap.driver_id ?? existingBookingMap.driverId ?? existingBookingMap?.assigned_driver?.driver_id ?? existingBookingMap?.assigned_driver?.driverId ?? existingBookingMap?.assignedDriver?.driver_id ?? existingBookingMap?.assignedDriver?.driverId ?? existingSession?.owner_driver_id ?? existingSession?.assigned_driver_id ?? existingSession?.assignedDriverId ?? existingSession?.driver_id ?? existingSession?.driverId ?? existingSession?.assigned_driver?.driver_id ?? existingSession?.assigned_driver?.driverId ?? existingSession?.assignedDriver?.driver_id ?? existingSession?.assignedDriver?.driverId
      );
      const assignmentOwnerVehicleId = _trackingOwnershipValue(
        existingBookingMap.owner_vehicle_id ?? existingBookingMap.assigned_vehicle_id ?? existingBookingMap.assignedVehicleId ?? existingBookingMap.vehicle_id ?? existingBookingMap.vehicleId ?? existingSession?.owner_vehicle_id ?? existingSession?.assigned_vehicle_id ?? existingSession?.assignedVehicleId ?? existingSession?.vehicle_id ?? existingSession?.vehicleId
      );
      const ownerCheck = _trackingOwnershipAllowed({
        actorDriverId: actor.actor_driver_id,
        actorVehicleId: actor.actor_vehicle_id,
        ownerDriverId: assignmentOwnerDriverId,
        ownerVehicleId: assignmentOwnerVehicleId
      });
      assignmentOwnershipPassed = ownerCheck.allowed && (ownerCheck.reason === "driver_match" || ownerCheck.reason === "vehicle_match");
      _logTrackingOwnershipCheck({
        target: "session_start_booking",
        targetId: booking_id,
        actor,
        ownerDriverId: ownerCheck.candidateDriver,
        ownerVehicleId: ownerCheck.candidateVehicle,
        allowed: ownerCheck.allowed,
        reason: ownerCheck.reason
      });
      if (!ownerCheck.allowed && ownerCheck.certainMismatch) {
        _logTrackingOwnershipBlock({
          target: "session_start_booking",
          targetId: booking_id,
          actor,
          ownerDriverId: ownerCheck.candidateDriver,
          ownerVehicleId: ownerCheck.candidateVehicle,
          error: "booking_not_assigned_to_driver"
        });
        return withCors(json2(_trackingOwnershipError("booking_not_assigned_to_driver"), { status: 403 }), origin);
      }
    }
    if (actor.actor_vehicle_id) {
      const vehicleOwnership = await _driverVehicleOwnershipBestEffort(env, {
        tenant_id,
        company_id,
        driver_id: actor.actor_driver_id,
        vehicle_id: actor.actor_vehicle_id
      });
      _logTrackingOwnershipCheck({
        target: "session_start_vehicle",
        targetId: actor.actor_vehicle_id,
        actor,
        ownerDriverId: actor.actor_driver_id,
        ownerVehicleId: actor.actor_vehicle_id,
        allowed: vehicleOwnership.allowed,
        reason: vehicleOwnership.reason
      });
      const ownershipProofPassed = assignmentOwnershipPassed || directStartOwnershipPassed;
      if (!vehicleOwnership.allowed && vehicleOwnership.certainMismatch && vehicleOwnership.reason === "vehicle_owner_mismatch" && ownershipProofPassed) {
        console.log(
          `[TRACKING_OWNERSHIP][REPAIR_OWNER_VEHICLE] target=session_start_vehicle vehicle=${actor.actor_vehicle_id} driver=${actor.actor_driver_id} reason=assignment_match_overrides_stale_owner_map`
        );
        await _rememberVehicleOwnerBestEffort(env, {
          tenant_id,
          company_id,
          driver_id: actor.actor_driver_id,
          vehicle_id: actor.actor_vehicle_id
        });
      }
      if (!vehicleOwnership.allowed && vehicleOwnership.certainMismatch && !ownershipProofPassed) {
        _logTrackingOwnershipBlock({
          target: "session_start_vehicle",
          targetId: actor.actor_vehicle_id,
          actor,
          ownerDriverId: actor.actor_driver_id,
          ownerVehicleId: actor.actor_vehicle_id,
          error: "booking_not_assigned_to_driver"
        });
        return withCors(json2(_trackingOwnershipError("booking_not_assigned_to_driver"), { status: 403 }), origin);
      }
    }
  }
  const sessionId = `s_${booking_id}_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 8)}`;
  const public_token = `p_${randToken(24)}`;
  const session = {
    session_id: sessionId,
    booking_id,
    pickup,
    dropoff,
    ...originData ? { origin: originData } : {},
    status: "active",
    created_at: nowIso(),
    started_at: startedAt,
    last_ping_at: null,
    points: [],
    public_token,
    driver_id: owner_driver_id,
    vehicle_id: owner_vehicle_id,
    owner_driver_id: actor.actor_role === "driver" ? actor.actor_driver_id : owner_driver_id,
    owner_vehicle_id: actor.actor_role === "driver" ? actor.actor_vehicle_id ?? owner_vehicle_id : owner_vehicle_id,
    owner_booking_id: booking_id,
    owner_tenant_id: tenant_id,
    owner_company_id: company_id
  };
  applyCanonicalScopeToRecord(session, scope2);
  let trackingSync = null;
  if (realtimeDoEnabled(env)) {
    try {
      let operationalLeg = safeStr22(body.operational_leg || body.leg_id || body.legId, 200) || "";
      const grant = await readCustomerGrant(
        env,
        scope2,
        booking_id,
        operationalLeg,
        session.owner_driver_id || session.driver_id,
        true
      );
      if (!grant) return withCors(json2({
        ok: false,
        error: "tracking_assignment_not_ready",
        tracking_sync: { confirmed: false, reason: "grant_missing_or_ambiguous" }
      }, { status: 409 }), origin);
      operationalLeg = grant.operational_leg || "primary";
      if (body.reuse_bound_session === true && grant.session_id && ["assigned", "en_route_pickup", "arrived_pickup", "in_progress"].includes(grant.tracking_phase)) {
        const existing = await kvGetJson(env.FLUXIDI_TRACKING, scopedSessionKey(scope2, grant.session_id));
        if (existing?.status === "active" && recordMatchesTenantCompanyScope(existing, scope2) && existing.booking_id === booking_id && existing.operational_leg === operationalLeg && existing.assignment_version === grant.assignment_version && grant.driver_id === (session.owner_driver_id || session.driver_id) && (existing.owner_driver_id || existing.driver_id) === (session.owner_driver_id || session.driver_id)) {
          return withCors(json2({
            ok: true,
            session_id: existing.session_id,
            booking_id,
            tracking_sync: { confirmed: true, reason: "session_start", assignment_version: grant.assignment_version }
          }), origin);
        }
      }
      trackingSync = await postCustomerGrant(env, {
        kind: "session_start",
        tenant_id,
        company_id,
        booking_id,
        operational_leg: operationalLeg,
        lifecycle_seq: grant.lifecycle_seq,
        assignment_version: grant.assignment_version,
        driver_id: session.owner_driver_id || session.driver_id,
        session_id: sessionId
      }, true);
      if (trackingSync.confirmed !== true || trackingSync.reason !== "session_start" || !(Number(trackingSync.assignment_version) > 0)) {
        return withCors(json2({ ok: false, error: "tracking_binding_rejected", tracking_sync: trackingSync }, { status: 409 }), origin);
      }
      session.assignment_version = trackingSync.assignment_version;
      session.operational_leg = operationalLeg;
    } catch (_) {
      return withCors(json2({
        ok: false,
        error: "tracking_binding_unavailable",
        retryable: true,
        tracking_sync: { confirmed: false, reason: "customer_tracking_sync_failed" }
      }, { status: 503 }), origin);
    }
  }
  const scopedSession = scopedSessionKey(scope2, sessionId);
  await kvPutJson(env.FLUXIDI_TRACKING, scopedSession, session, TTL_SESSION);
  const bookingMap = {
    session_id: sessionId,
    created_at: session.created_at,
    pickup,
    dropoff,
    public_token,
    owner_driver_id: session.owner_driver_id ?? null,
    owner_vehicle_id: session.owner_vehicle_id ?? null,
    owner_booking_id: booking_id,
    owner_tenant_id: session.owner_tenant_id ?? null,
    owner_company_id: session.owner_company_id ?? null
  };
  applyCanonicalScopeToRecord(bookingMap, scope2);
  await kvPutJson(env.FLUXIDI_TRACKING, scopedBookingSessionKey(scope2, booking_id), bookingMap, TTL_SESSION);
  if (actor.actor_role === "driver") {
    await _rememberVehicleOwnerBestEffort(env, {
      tenant_id,
      company_id,
      driver_id: actor.actor_driver_id,
      vehicle_id: actor.actor_vehicle_id ?? owner_vehicle_id
    });
  }
  await kvPutJson(
    env.FLUXIDI_TRACKING,
    scopedPublicBookingKey(scope2, public_token),
    {
      booking_id,
      session_id: sessionId,
      operational_leg: session.operational_leg || null,
      assignment_version: session.assignment_version || null,
      driver_id: session.owner_driver_id || session.driver_id || null,
      tenant_id,
      company_id,
      tenantId: tenant_id,
      companyId: company_id,
      created_at: session.created_at
    },
    TTL_PUBLIC_TOKEN
  );
  const idx = await kvGetJson(env.FLUXIDI_TRACKING, scopedBookingIndexKey(scope2)) ?? [];
  const next = [booking_id, ...idx.filter((x) => x !== booking_id)].slice(0, 200);
  await kvPutJson(env.FLUXIDI_TRACKING, scopedBookingIndexKey(scope2), next, TTL_INDEX);
  const startComplianceEvent = buildPlannedSessionStartComplianceEvent(session, body, startedAt, scope2);
  if (startComplianceEvent) {
    const startEventId = buildDeterministicRideStartEventId(
      startComplianceEvent.tenant_id,
      startComplianceEvent.company_id,
      sessionId
    );
    if (startEventId) startComplianceEvent.event_id = startEventId;
    applyComplianceEmitStartAttempt(session, {
      state: COMPLIANCE_EMIT_STATE.PENDING,
      errorCode: null,
      eventId: startEventId,
      nowIso: nowIso()
    });
    await kvPutJson(env.FLUXIDI_TRACKING, scopedSession, session, TTL_SESSION);
    _chironSyncLog("enqueue", session, sessionId, startComplianceEvent, "queued", "planned_ride_start");
    const emitTask = (async () => {
      let emitRes;
      try {
        emitRes = await emitComplianceEventBestEffort(env, startComplianceEvent, {
          timeoutMs: 1500,
          logLabel: "ride_start_planned"
        });
      } catch (err) {
        emitRes = { ok: false, error: _dbfStr(err?.message || err, 120) || "internal_error" };
      }
      try {
        const latest = await kvGetJson(env.FLUXIDI_TRACKING, scopedSession);
        const target2 = latest && recordMatchesTenantCompanyScope(latest, scope2) ? latest : session;
        const nextState = deriveComplianceEmitStateFromResult(emitRes);
        applyComplianceEmitStartAttempt(target2, {
          state: nextState,
          errorCode: complianceEmitErrorCodeFromResult(emitRes),
          eventId: startComplianceEvent.event_id,
          nowIso: nowIso(),
          attemptDelta: 0
          // enqueue above already counted this attempt.
        });
        applyCanonicalScopeToRecord(target2, scope2);
        await kvPutJson(env.FLUXIDI_TRACKING, scopedSession, target2, TTL_SESSION);
        _chironSyncLog(
          nextState === COMPLIANCE_EMIT_STATE.APPLIED ? "applied" : "failed",
          target2,
          sessionId,
          startComplianceEvent,
          nextState,
          complianceEmitErrorCodeFromResult(emitRes) || "ok"
        );
      } catch (_) {
        _chironSyncLog("failed", session, sessionId, startComplianceEvent, "pending", "kv_write_failed");
      }
    })();
    if (ctx && typeof ctx.waitUntil === "function") {
      ctx.waitUntil(emitTask);
    } else {
      await emitTask;
    }
  }
  const startEmitFields = startComplianceEvent ? safeComplianceEmitStartResponseFields(session) : null;
  return withCors(
    json2(
      {
        ok: true,
        session_id: sessionId,
        booking_id,
        created_at: session.created_at,
        public_token,
        tracking_sync: trackingSync,
        ...startEmitFields ?? {}
      },
      { status: 200 }
    ),
    origin
  );
}
__name(handleStart, "handleStart");
function envFlagOn(env, name) {
  const v = String(env?.[name] ?? "").trim().toLowerCase();
  return v === "1" || v === "true" || v === "on" || v === "yes";
}
__name(envFlagOn, "envFlagOn");
function realtimeDoEnabled(env) {
  return envFlagOn(env, "tracking_realtime_do_enabled");
}
__name(realtimeDoEnabled, "realtimeDoEnabled");
function legacyKvPingWriteEnabled(env) {
  const raw = env?.tracking_legacy_kv_ping_write_enabled;
  if (raw === void 0 || raw === null || String(raw).trim() === "") return true;
  return envFlagOn(env, "tracking_legacy_kv_ping_write_enabled");
}
__name(legacyKvPingWriteEnabled, "legacyKvPingWriteEnabled");
function companyTrackingStub(env, tenantId, companyId) {
  const ns = env?.COMPANY_TRACKING;
  if (!ns || typeof ns.idFromName !== "function" || typeof ns.get !== "function") {
    throw new Error("tracking_realtime_unavailable");
  }
  return ns.get(ns.idFromName(companyTrackingObjectName2(tenantId, companyId)));
}
__name(companyTrackingStub, "companyTrackingStub");
async function syncDirectDispatchOccupancy(env, trip, phase) {
  if (!env?.COMPANY_TRACKING && !realtimeDoEnabled(env)) return;
  if (phase === "stop" && trip.dispatch_occupancy_registered !== true) return;
  const stub = companyTrackingStub(env, trip.tenant_id, trip.company_id);
  const response2 = await stub.fetch("https://company-tracking.internal/direct-occupancy", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      tenant_id: trip.tenant_id,
      company_id: trip.company_id,
      driver_id: trip.driver_id,
      vehicle_id: trip.vehicle_id,
      trip_id: trip.trip_id,
      direct_ride_key: trip.direct_ride_key || trip.trip_id,
      phase
    })
  });
  const result2 = await response2.json();
  if (!response2.ok || result2?.ok !== true) throw new Error("street_dispatch_sync_failed");
}
__name(syncDirectDispatchOccupancy, "syncDirectDispatchOccupancy");
async function postCompanyLocation(env, payload) {
  const stub = companyTrackingStub(env, payload.tenant_id, payload.company_id);
  const res = await stub.fetch("https://company-tracking.internal/location", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(payload)
  });
  const body = await res.json().catch(() => ({ ok: false, error: "tracking_unavailable" }));
  return { status: res.status, body };
}
__name(postCompanyLocation, "postCompanyLocation");
var customerEtaCache = createEtaCache(async ({ origin, destination }) => {
  if (typeof customerEtaCache.fetcherOverride === "function") {
    return customerEtaCache.fetcherOverride({ origin, destination });
  }
  return mapboxDispatchRouteEta22(customerEtaCache.env || {}, { origin, destination, includeGeometry: true });
});
async function postCustomerGrant(env, event, requireAvailable = false) {
  const stub = companyTrackingStub(env, event.tenant_id, event.company_id);
  const res = await stub.fetch("https://company-tracking.internal/customer-grant", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(event)
  });
  if (requireAvailable && !res.ok) throw new Error("customer_tracking_sync_failed");
  return res.json();
}
__name(postCustomerGrant, "postCustomerGrant");
async function readCustomerGrant(env, scope2, bookingId, leg, activeDriverId = "", requireAvailable = false) {
  const stub = companyTrackingStub(env, scope2.tenant_id, scope2.company_id);
  const liveUrl = new URL("https://company-tracking.internal/customer-grant");
  liveUrl.searchParams.set("booking_id", bookingId);
  if (leg) liveUrl.searchParams.set("operational_leg", leg);
  if (activeDriverId) liveUrl.searchParams.set("active_driver_id", activeDriverId);
  const res = await stub.fetch(liveUrl.toString(), { method: "GET" });
  if (requireAvailable && !res.ok && res.status !== 404) throw new Error("customer_tracking_sync_failed");
  if (!res.ok) return null;
  const body = await res.json();
  if (requireAvailable && !body.grant) throw new Error("customer_tracking_invalid_response");
  return body.grant || null;
}
__name(readCustomerGrant, "readCustomerGrant");
async function clearCompanyLocation(env, payload) {
  const stub = companyTrackingStub(env, payload.tenant_id, payload.company_id);
  await stub.fetch("https://company-tracking.internal/clear", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(payload)
  });
}
__name(clearCompanyLocation, "clearCompanyLocation");
async function handleDriverPresenceLocation(req, url, env, origin) {
  const body = await readJson(req);
  const session = await loadPublicDriverSessionFromRequest(req, env);
  if (!session) {
    return withCors(json2({ ok: false, error: "unauthorized" }, { status: 401 }), origin);
  }
  const conflict = presenceIdentityConflict(session, body);
  if (conflict) {
    return withCors(json2({ ok: false, error: "forbidden", field: conflict }, { status: 403 }), origin);
  }
  const ownership = driverLocationOwner(session, body);
  if (!ownership.ok) return withCors(json2({ ok: false, error: ownership.error }, { status: ownership.status }), origin);
  const indexKey = `tenant:${session.tenant_id}:company:${session.company_id}:drivers:index:v1`;
  const index = await env.BOOKING_KV.get(indexKey, { type: "json" });
  const storedDriver = index?.drivers?.[session.driver_id] || null;
  const driver = storedDriver && session.vehicle_device_id ? { ...storedDriver, assigned_vehicle_id: session.assigned_vehicle_id } : storedDriver;
  let result2;
  try {
    result2 = await acceptDriverPresenceLocation({
      env,
      session,
      body,
      driver
    });
  } catch (_) {
    return withCors(json2({
      ok: false,
      error: "tracking_unavailable",
      ops: { booking_kv_reads: 1, driver_index_reads: 1, do_requests: 0, gps_kv_writes: 0 }
    }, { status: 503 }), origin);
  }
  if (result2.body?.ops) result2.body.ops.driver_index_reads = 1;
  console.info(JSON.stringify({
    event: "driver_presence_location",
    company_id: session.company_id,
    driver_id: session.driver_id,
    vehicle_id: driver?.assigned_vehicle_id || driver?.assignedVehicleId || null,
    lat: body?.lat ?? body?.latitude ?? null,
    lon: body?.lon ?? body?.longitude ?? null,
    captured_at: body?.captured_at ?? body?.ts ?? null,
    applied: result2.body?.applied === true,
    reason: result2.body?.reason || null,
    gps_kv_writes: result2.body?.ops?.gps_kv_writes ?? 0,
    status: result2.status
  }));
  return withCors(json2(result2.body, { status: result2.status }), origin);
}
__name(handleDriverPresenceLocation, "handleDriverPresenceLocation");
async function handleDriverLocationWithdraw(req, url, env, origin) {
  const body = await readJson(req);
  const session = await loadPublicDriverSessionFromRequest(req, env);
  if (!session) return withCors(json2({ ok: false, error: "unauthorized" }, { status: 401 }), origin);
  const conflict = presenceIdentityConflict(session, body);
  if (conflict) return withCors(json2({ ok: false, error: "forbidden", field: conflict }, { status: 403 }), origin);
  const ownership = driverLocationOwner(session, body, { requireActivation: true });
  if (!ownership.ok) return withCors(json2({ ok: false, error: ownership.error }, { status: ownership.status }), origin);
  if (!realtimeDoEnabled(env)) return withCors(json2({ ok: false, error: "tracking_unavailable" }, { status: 503 }), origin);
  try {
    const response2 = await companyTrackingStub(env, session.tenant_id, session.company_id).fetch(
      "https://company-tracking.internal/location-withdraw",
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          tenant_id: session.tenant_id,
          company_id: session.company_id,
          driver_id: session.driver_id,
          publication_owner: ownership.owner
        })
      }
    );
    const result2 = await response2.json();
    return withCors(json2({
      ok: result2.ok === true,
      cleared: result2.cleared === true,
      reason: result2.reason || result2.error || null,
      ops: { gps_kv_writes: 0 }
    }, { status: response2.status }), origin);
  } catch (_) {
    return withCors(json2({ ok: false, error: "tracking_unavailable" }, { status: 503 }), origin);
  }
}
__name(handleDriverLocationWithdraw, "handleDriverLocationWithdraw");
async function handlePing(req, url, env, origin) {
  const rawBody = await readJson(req);
  const auth = await requireDriverSessionOrAdminForScope(req, url, env, {
    body: rawBody,
    routeLabel: "TRACK_PING"
  });
  if (!auth.ok) return auth.response;
  const body = applyDriverSessionToBody(rawBody, auth.driver_session);
  const ownership = driverLocationOwner(auth.driver_session, rawBody);
  if (!ownership.ok) return withCors(json2({ ok: false, error: ownership.error }, { status: ownership.status }), origin);
  const requiredScope = parseRequiredTenantCompanyScope(req, url, body, { returnResponse: true, origin });
  if (requiredScope instanceof Response) return requiredScope;
  const scope2 = requiredScope;
  const actor = resolveTrackingActorFromRequest(req, url, body);
  const session_id = safeStr22(body["session_id"], 128);
  if (!session_id) throw new Error("session_id is required");
  const lat = safeNum(body["lat"], -90, 90);
  const lon = safeNum(body["lon"], -180, 180);
  if (lat === null || lon === null) throw new Error("lat/lon invalid");
  const speed = safeNum(body["speed"], 0, 200) ?? null;
  const heading = safeNum(body["heading"], 0, 360) ?? null;
  const sessionKey = scopedSessionKey(scope2, session_id);
  const session = await kvGetJson(env.FLUXIDI_TRACKING, sessionKey);
  if (!session) throw new Error("Unknown session_id");
  if (!recordMatchesTenantCompanyScope(session, scope2)) throw new Error("invalid session scope");
  const ownershipBlock = await _assertSessionOwnedByActorOrBlock({
    session,
    session_id,
    actor,
    error: "session_not_assigned_to_driver",
    origin
  });
  if (ownershipBlock) return ownershipBlock;
  if (session.status === "stopped") {
    return withCors(json2({ ok: false, error: "Session stopped" }, { status: 409 }), origin);
  }
  const point22 = { lat, lon, ts: nowIso(), speed, heading };
  const serverDriverId = auth.driver_session?.driver_id || session.owner_driver_id || session.driver_id || null;
  const serverVehicleId = session.owner_vehicle_id || session.vehicle_id || null;
  const capturedAt = safeStr22(body["captured_at"] ?? body["ts"], 64) || null;
  let doResult = null;
  if (realtimeDoEnabled(env)) {
    try {
      doResult = await postCompanyLocation(env, {
        tenant_id: scope2.tenant_id,
        company_id: scope2.company_id,
        driver_id: serverDriverId,
        vehicle_id: serverVehicleId,
        latitude: lat,
        longitude: lon,
        accuracy: body["accuracy_m"] ?? body["accuracy"] ?? null,
        heading,
        speed,
        captured_at: capturedAt,
        availability_status: safeStr22(body["availability_status"] ?? body["availabilityStatus"], 32) || null,
        tracking_status: "active",
        publication_owner: ownership.owner,
        ...session.operational_leg && session.assignment_version ? {
          tracking_context: {
            booking_id: session.booking_id,
            operational_leg: session.operational_leg,
            assignment_version: session.assignment_version,
            session_id,
            phase: "in_progress"
          }
        } : {},
        freshness_seconds: env.TRACKING_LOCATION_FRESHNESS_SECONDS
      });
    } catch (_) {
      if (!legacyKvPingWriteEnabled(env)) {
        return withCors(json2({ ok: false, error: "tracking_unavailable" }, { status: 503 }), origin);
      }
      doResult = null;
    }
    if (doResult && doResult.status >= 400) {
      return withCors(json2(doResult.body, { status: doResult.status }), origin);
    }
  }
  if (legacyKvPingWriteEnabled(env)) {
    const points = Array.isArray(session.points) ? session.points : [];
    points.push(point22);
    if (points.length > 1200) points.splice(0, points.length - 1200);
    session.points = points;
    session.last_ping_at = point22.ts;
    applyCanonicalScopeToRecord(session, scope2);
    await kvPutJson(env.FLUXIDI_TRACKING, sessionKey, session, TTL_SESSION);
    await kvPutJson(env.FLUXIDI_TRACKING, scopedPingLastKey(scope2, session_id), point22, TTL_LASTPING);
  }
  const gpsKvWrites = legacyKvPingWriteEnabled(env) ? 2 : 0;
  return withCors(
    json2(
      {
        ok: true,
        session_id,
        ts: point22.ts,
        applied: doResult ? doResult.body?.applied !== false : true,
        ...doResult?.body?.reason ? { reason: doResult.body.reason } : {},
        ops: {
          booking_kv_reads: auth.auth_mode === "driver_session" ? 1 : 0,
          tracking_session_reads: 1,
          do_requests: realtimeDoEnabled(env) ? 1 : 0,
          gps_kv_writes: gpsKvWrites
        }
      },
      { status: 200 }
    ),
    origin
  );
}
__name(handlePing, "handlePing");
async function handleStop(req, url, env, origin) {
  const rawBody = await readJson(req);
  const auth = await requireDriverSessionOrAdminForScope(req, url, env, {
    body: rawBody,
    routeLabel: "TRACK_SESSION_STOP"
  });
  if (!auth.ok) return auth.response;
  const body = applyDriverSessionToBody(rawBody, auth.driver_session);
  const requiredScope = parseRequiredTenantCompanyScope(req, url, body, { returnResponse: true, origin });
  if (requiredScope instanceof Response) return requiredScope;
  const scope2 = requiredScope;
  const actor = resolveTrackingActorFromRequest(req, url, body);
  const session_id = safeStr22(body["session_id"], 128);
  if (!session_id) throw new Error("session_id is required");
  const sessionKey = scopedSessionKey(scope2, session_id);
  const session = await kvGetJson(env.FLUXIDI_TRACKING, sessionKey);
  if (!session) throw new Error("Unknown session_id");
  if (!recordMatchesTenantCompanyScope(session, scope2)) throw new Error("invalid session scope");
  const ownershipBlock = await _assertSessionOwnedByActorOrBlock({
    session,
    session_id,
    actor,
    error: "session_not_assigned_to_driver",
    origin
  });
  if (ownershipBlock) return ownershipBlock;
  session.status = "stopped";
  session.stopped_at = session.stopped_at || nowIso();
  applyCanonicalScopeToRecord(session, scope2);
  await kvPutJson(env.FLUXIDI_TRACKING, sessionKey, session, TTL_INDEX);
  let trackingSync = null;
  let stopStatus = 200;
  if (realtimeDoEnabled(env)) {
    const bookingId = safeStr22(session.booking_id ?? session.bookingId, 96);
    try {
      if (bookingId) {
        if (!(Number(session.assignment_version) > 0)) {
          trackingSync = { confirmed: false, reason: "session_assignment_mismatch" };
          stopStatus = 409;
        } else {
          const grant = await readCustomerGrant(env, scope2, bookingId, session.operational_leg || "primary", "", true);
          if (!grant) {
            trackingSync = { confirmed: false, reason: "customer_tracking_grant_unavailable" };
            stopStatus = 503;
          } else {
            trackingSync = await postCustomerGrant(env, {
              kind: "session_stop",
              tenant_id: scope2.tenant_id,
              company_id: scope2.company_id,
              booking_id: bookingId,
              operational_leg: session.operational_leg || "primary",
              lifecycle_seq: grant.lifecycle_seq,
              assignment_version: Number(session.assignment_version),
              driver_id: session.owner_driver_id || session.driver_id || "",
              session_id
            }, true);
            if (trackingSync.confirmed !== true) stopStatus = 409;
          }
        }
      } else {
        await clearCompanyLocation(env, {
          tenant_id: scope2.tenant_id,
          company_id: scope2.company_id,
          driver_id: session.owner_driver_id || session.driver_id || auth.driver_session?.driver_id,
          publication_owner: driverLocationOwner(auth.driver_session, rawBody).owner || null
        });
      }
    } catch (_) {
      trackingSync = { confirmed: false, reason: "customer_tracking_sync_failed" };
      stopStatus = 503;
    }
  }
  return withCors(json2({
    ok: stopStatus === 200,
    session_id,
    status: "stopped",
    ...stopStatus !== 200 ? { error: stopStatus === 503 ? "tracking_stop_unavailable" : "tracking_stop_rejected", retryable: stopStatus === 503 } : {},
    tracking_sync: trackingSync
  }, { status: stopStatus }), origin);
}
__name(handleStop, "handleStop");
async function resolveSessionByBookingForScope(env, scope2, booking_id) {
  const map22 = await kvGetJson(
    env.FLUXIDI_TRACKING,
    scopedBookingSessionKey(scope2, booking_id)
  );
  if (!map22) return null;
  if (!recordMatchesTenantCompanyScope(map22, scope2)) return null;
  const sessionId = safeStr22(map22?.session_id ?? map22?.sessionId, 128);
  if (!sessionId) return null;
  const session = await kvGetJson(
    env.FLUXIDI_TRACKING,
    scopedSessionKey(scope2, sessionId)
  );
  if (!session) return null;
  if (!recordMatchesTenantCompanyScope(session, scope2)) return null;
  const last = await kvGetJson(
    env.FLUXIDI_TRACKING,
    scopedPingLastKey(scope2, sessionId)
  );
  return { map: map22, session, last, session_id: sessionId };
}
__name(resolveSessionByBookingForScope, "resolveSessionByBookingForScope");
async function handleBookings(req, url, env, origin) {
  const auth = await requireDriverOrCompanyOrAdminForScope(req, url, env, {
    routeLabel: "TRACK_BOOKINGS"
  });
  if (!auth.ok) return auth.response;
  const requiredScope = parseRequiredTenantCompanyScope(req, url, null, { returnResponse: true, origin });
  if (requiredScope instanceof Response) return requiredScope;
  const scope2 = requiredScope;
  const scopedIndex = await kvGetJson(env.FLUXIDI_TRACKING, scopedBookingIndexKey(scope2)) ?? [];
  const idx = Array.isArray(scopedIndex) ? scopedIndex : [];
  const limit2 = Math.min(200, Math.max(1, Number(url.searchParams.get("limit") || 50)));
  const bookings = [];
  const cleanedIndex = [];
  for (const booking_id of idx) {
    const map22 = await kvGetJson(
      env.FLUXIDI_TRACKING,
      scopedBookingSessionKey(scope2, booking_id)
    );
    if (!map22) continue;
    if (!recordMatchesTenantCompanyScope(map22, scope2)) continue;
    const sessionId = safeStr22(map22.session_id ?? map22.sessionId, 128);
    if (!sessionId) continue;
    const session = await kvGetJson(
      env.FLUXIDI_TRACKING,
      scopedSessionKey(scope2, sessionId)
    );
    if (!session || !recordMatchesTenantCompanyScope(session, scope2)) continue;
    cleanedIndex.push(booking_id);
    const last = await kvGetJson(
      env.FLUXIDI_TRACKING,
      scopedPingLastKey(scope2, sessionId)
    );
    bookings.push({
      booking_id,
      session_id: sessionId,
      created_at: map22.created_at,
      pickup: map22.pickup ?? null,
      dropoff: map22.dropoff ?? null,
      public_token: map22.public_token ?? null,
      last_ping: last ?? null
    });
    if (bookings.length >= limit2) break;
  }
  const indexTrimmed = cleanedIndex.slice(0, 200);
  if (cleanedIndex.length !== idx.length || !Array.isArray(scopedIndex) || scopedIndex.length === 0) {
    await kvPutJson(env.FLUXIDI_TRACKING, scopedBookingIndexKey(scope2), indexTrimmed, TTL_INDEX);
  }
  return withCors(json2({ ok: true, count: bookings.length, bookings }, { status: 200 }), origin);
}
__name(handleBookings, "handleBookings");
async function handleBookingDetails(req, url, env, origin) {
  const auth = await requireDriverOrCompanyOrAdminForScope(req, url, env, {
    routeLabel: "TRACK_BOOKING"
  });
  if (!auth.ok) return auth.response;
  const requiredScope = parseRequiredTenantCompanyScope(req, url, null, { returnResponse: true, origin });
  if (requiredScope instanceof Response) return requiredScope;
  const scope2 = requiredScope;
  const booking_id = safeStr22(url.searchParams.get("booking_id"), 64);
  if (!booking_id) throw new Error("booking_id is required");
  const resolved = await resolveSessionByBookingForScope(env, scope2, booking_id);
  if (!resolved) throw new Error("Unknown booking_id");
  const { map: map22, session, last, session_id } = resolved;
  return withCors(
    json2(
      {
        ok: true,
        booking_id,
        session_id,
        created_at: map22.created_at,
        pickup: map22.pickup ?? null,
        dropoff: map22.dropoff ?? null,
        status: session?.status ?? null,
        last_ping: last ?? null,
        points_count: Array.isArray(session?.points) ? session.points.length : 0,
        public_token: map22.public_token ?? session?.public_token ?? null
      },
      { status: 200 }
    ),
    origin
  );
}
__name(handleBookingDetails, "handleBookingDetails");
async function handleLive(req, url, env, origin) {
  const auth = await requireDriverOrCompanyOrAdminForScope(req, url, env, {
    routeLabel: "TRACK_LIVE"
  });
  if (!auth.ok) return auth.response;
  const requiredScope = parseRequiredTenantCompanyScope(req, url, null, { returnResponse: true, origin });
  if (requiredScope instanceof Response) return requiredScope;
  const scope2 = requiredScope;
  const booking_id = safeStr22(url.searchParams.get("booking_id"), 64);
  if (!booking_id) throw new Error("booking_id is required");
  const limit2 = Math.min(1200, Math.max(1, Number(url.searchParams.get("limit") || 300)));
  const resolved = await resolveSessionByBookingForScope(env, scope2, booking_id);
  if (!resolved) throw new Error("Unknown booking_id");
  const { session, last, session_id } = resolved;
  const points = Array.isArray(session?.points) ? session.points : [];
  const sliced = points.slice(Math.max(0, points.length - limit2));
  return withCors(
    json2(
      {
        ok: true,
        booking_id,
        session_id,
        status: session?.status ?? null,
        last_ping: last ?? null,
        points: sliced
      },
      { status: 200 }
    ),
    origin
  );
}
__name(handleLive, "handleLive");
async function handlePublicLive(req, url, env, origin) {
  const reply = /* @__PURE__ */ __name((body, status = 200) => withCors(json2(body, {
    status,
    headers: { "cache-control": "no-store" }
  }), origin), "reply");
  const denied2 = /* @__PURE__ */ __name(() => reply({ ok: false, error: "not_found", tracking_closed: true, last_ping: null, points: [] }, 404), "denied");
  const token = safeStr22(url.searchParams.get("token"), 128);
  if (!token) return denied2();
  const scope2 = parseRequiredTenantCompanyScope(req, url, null, { returnResponse: true, origin });
  if (scope2 instanceof Response) return scope2;
  const link = await kvGetJson(env.FLUXIDI_TRACKING, scopedPublicBookingKey(scope2, token));
  if (!link || !recordMatchesTenantCompanyScope(link, scope2)) return denied2();
  const bookingId = safeStr22(link.booking_id, 96);
  const sessionId = safeStr22(link.session_id ?? link.sessionId, 128);
  if (!bookingId || !sessionId) return denied2();
  const session = await kvGetJson(env.FLUXIDI_TRACKING, scopedSessionKey(scope2, sessionId));
  if (!session || !recordMatchesTenantCompanyScope(session, scope2) || session.session_id !== sessionId || session.booking_id !== bookingId || session.public_token !== token || session.status !== "active") return denied2();
  const leg = safeStr22(session.operational_leg, 200);
  const version = Number(session.assignment_version);
  const driver = safeStr22(session.owner_driver_id || session.driver_id, 96);
  if (!leg || !(version > 0) || !driver || !realtimeDoEnabled(env)) return denied2();
  if (link.operational_leg != null && link.operational_leg !== leg || link.assignment_version != null && Number(link.assignment_version) !== version || link.driver_id != null && link.driver_id !== driver) return denied2();
  for (const [key2, expected] of [
    ["booking_id", bookingId],
    ["session_id", sessionId],
    ["operational_leg", leg],
    ["leg_id", leg],
    ["legId", leg]
  ]) {
    if (url.searchParams.has(key2) && url.searchParams.get(key2) !== expected) return denied2();
  }
  let grant;
  try {
    grant = await readCustomerGrant(env, scope2, bookingId, leg, "", true);
  } catch (_) {
    return reply({ ok: false, error: "tracking_unavailable", tracking_closed: true, last_ping: null, points: [] }, 503);
  }
  if (!grant || !recordMatchesTenantCompanyScope(grant, scope2) || grant.booking_id !== bookingId || grant.operational_leg !== leg || grant.assignment_version !== version || grant.driver_id !== driver || grant.session_id !== sessionId || grant.leg_scope_retired || !["en_route_pickup", "in_progress"].includes(grant.tracking_phase) || !publicLiveMayExposePosition(session, grant, { requireGrant: true })) return denied2();
  const limit2 = Math.min(1200, Math.max(1, Number(url.searchParams.get("limit") || 300)));
  const last = await kvGetJson(env.FLUXIDI_TRACKING, scopedPingLastKey(scope2, sessionId));
  const points = Array.isArray(session.points) ? session.points : [];
  return reply({
    ok: true,
    booking_id: bookingId,
    session_id: sessionId,
    status: session.status,
    tracking_closed: false,
    last_ping: last ?? null,
    points: points.slice(Math.max(0, points.length - limit2))
  });
}
__name(handlePublicLive, "handlePublicLive");
async function handleRoute(req, url, env, origin) {
  return withCors(json2({ ok: false, error: "legacy_provider_route_retired", provider_fallback: false }, { status: 410 }), origin);
}
__name(handleRoute, "handleRoute");
async function handleDeleteBooking(req, url, env, origin) {
  requireAdmin(req, url, env);
  const body = await readJson(req);
  const requiredScope = parseRequiredTenantCompanyScope(req, url, body, { returnResponse: true, origin });
  if (requiredScope instanceof Response) return requiredScope;
  const scope2 = requiredScope;
  const booking_id = safeStr22(body["booking_id"], 64);
  if (!booking_id) throw new Error("booking_id is required");
  const scopedIndexStorageKey = scopedBookingIndexKey(scope2);
  const scopedIndex = await kvGetJson(env.FLUXIDI_TRACKING, scopedIndexStorageKey) ?? [];
  const currentIndex = Array.isArray(scopedIndex) ? scopedIndex : [];
  const mapKey = scopedBookingSessionKey(scope2, booking_id);
  const map22 = await kvGetJson(env.FLUXIDI_TRACKING, mapKey);
  if (map22 && !recordMatchesTenantCompanyScope(map22, scope2)) {
    throw new Error("invalid booking scope");
  }
  if (!map22) {
    const next2 = currentIndex.filter((x) => x !== booking_id);
    if (next2.length !== currentIndex.length || !Array.isArray(scopedIndex)) {
      await kvPutJson(env.FLUXIDI_TRACKING, scopedIndexStorageKey, next2, TTL_INDEX);
    }
    return withCors(
      json2(
        {
          ok: true,
          deleted: false,
          booking_id,
          scope_mode: "scoped",
          note: "No scoped mapping found; removed from scoped index if present."
        },
        { status: 200 }
      ),
      origin
    );
  }
  const session_id = safeStr22(map22.session_id ?? map22.sessionId, 128);
  const public_token = safeStr22(map22.public_token ?? "", 128) || null;
  if (session_id) {
    const session = await kvGetJson(env.FLUXIDI_TRACKING, scopedSessionKey(scope2, session_id));
    if (session && !recordMatchesTenantCompanyScope(session, scope2)) {
      throw new Error("invalid session scope");
    }
  }
  await kvDel(env.FLUXIDI_TRACKING, mapKey);
  if (session_id) {
    await kvDel(env.FLUXIDI_TRACKING, scopedSessionKey(scope2, session_id));
    await kvDel(env.FLUXIDI_TRACKING, scopedPingLastKey(scope2, session_id));
  }
  if (public_token) {
    await kvDel(env.FLUXIDI_TRACKING, scopedPublicBookingKey(scope2, public_token));
  }
  const next = currentIndex.filter((x) => x !== booking_id);
  if (next.length !== currentIndex.length || !Array.isArray(scopedIndex)) {
    await kvPutJson(env.FLUXIDI_TRACKING, scopedIndexStorageKey, next, TTL_INDEX);
  }
  return withCors(
    json2(
      {
        ok: true,
        deleted: true,
        booking_id,
        session_id,
        public_token,
        scope_mode: "scoped"
      },
      { status: 200 }
    ),
    origin
  );
}
__name(handleDeleteBooking, "handleDeleteBooking");
async function handleClearBookings(req, url, env, origin) {
  requireAdmin(req, url, env);
  const body = await readJson(req);
  const requiredScope = parseRequiredTenantCompanyScope(req, url, body, { returnResponse: true, origin });
  if (requiredScope instanceof Response) return requiredScope;
  const scope2 = requiredScope;
  const scopedIndexStorageKey = scopedBookingIndexKey(scope2);
  await kvPutJson(env.FLUXIDI_TRACKING, scopedIndexStorageKey, [], TTL_INDEX);
  return withCors(
    json2({ ok: true, cleared: true, what: "booking_index", scope_mode: "scoped" }, { status: 200 }),
    origin
  );
}
__name(handleClearBookings, "handleClearBookings");
async function handlePurgeOrphans(req, url, env, origin) {
  requireAdmin(req, url, env);
  const body = await readJson(req);
  const requiredScope = parseRequiredTenantCompanyScope(req, url, body, { returnResponse: true, origin });
  if (requiredScope instanceof Response) return requiredScope;
  const scope2 = requiredScope;
  const scopedIndexStorageKey = scopedBookingIndexKey(scope2);
  const idx = await kvGetJson(env.FLUXIDI_TRACKING, scopedIndexStorageKey) ?? [];
  const cleaned = [];
  for (const rawBookingId of idx) {
    const booking_id = safeStr22(rawBookingId, 128);
    if (!booking_id) continue;
    const map22 = await kvGetJson(env.FLUXIDI_TRACKING, scopedBookingSessionKey(scope2, booking_id));
    if (!map22) continue;
    if (!recordMatchesTenantCompanyScope(map22, scope2)) continue;
    const session_id = safeStr22(map22.session_id ?? map22.sessionId, 128);
    if (!session_id) continue;
    const session = await kvGetJson(env.FLUXIDI_TRACKING, scopedSessionKey(scope2, session_id));
    if (!session) continue;
    if (!recordMatchesTenantCompanyScope(session, scope2)) continue;
    cleaned.push(booking_id);
  }
  await kvPutJson(env.FLUXIDI_TRACKING, scopedIndexStorageKey, cleaned, TTL_INDEX);
  return withCors(
    json2(
      {
        ok: true,
        before: Array.isArray(idx) ? idx.length : 0,
        after: cleaned.length,
        removed: (Array.isArray(idx) ? idx.length : 0) - cleaned.length,
        scope_mode: "scoped"
      },
      { status: 200 }
    ),
    origin
  );
}
__name(handlePurgeOrphans, "handlePurgeOrphans");
async function handleCustomerGrantSync(req, url, env, origin) {
  requireAdmin(req, url, env);
  const body = await readJson(req);
  if (!realtimeDoEnabled(env)) {
    return withCors(json2({ ok: false, error: "tracking_unavailable" }, { status: 503 }), origin);
  }
  const result2 = await postCustomerGrant(env, body);
  return withCors(json2(result2, { status: 200 }), origin);
}
__name(handleCustomerGrantSync, "handleCustomerGrantSync");
async function handleCustomerLive(req, url, env, origin) {
  const bookingReadsBefore = env.BOOKING_KV?.ops?.reads ?? 0;
  const headerToken = (req.headers.get("authorization") || "").match(/^Bearer\s+(\S+)/i)?.[1] || "";
  const token = safeStr22(headerToken, 128);
  if (url.searchParams.get("access_token")) {
    return withCors(json2({ ok: false, error: "not_found" }, { status: 404, headers: { "cache-control": "no-store" } }), origin);
  }
  const tenantId = safeStr22(url.searchParams.get("tenant_id"), 80);
  const companyId = safeStr22(url.searchParams.get("company_id"), 80);
  const bookingId = safeStr22(url.searchParams.get("booking_id"), 96);
  if (!token || !tenantId || !companyId || !bookingId) {
    return withCors(json2({ ok: false, error: "not_found" }, { status: 404, headers: { "cache-control": "no-store" } }), origin);
  }
  if (!realtimeDoEnabled(env)) {
    return withCors(json2({ ok: false, error: "tracking_unavailable" }, { status: 503, headers: { "cache-control": "no-store" } }), origin);
  }
  const accessHash = await sha256Hex2(token);
  const liveUrl = new URL("https://company-tracking.internal/customer-live");
  liveUrl.searchParams.set("tenant_id", tenantId);
  liveUrl.searchParams.set("company_id", companyId);
  liveUrl.searchParams.set("booking_id", bookingId);
  liveUrl.searchParams.set("access_token_hash", accessHash);
  const leg = safeStr22(url.searchParams.get("operational_leg"), 200);
  const customerId = safeStr22(url.searchParams.get("customer_id"), 96);
  const sessionId = safeStr22(url.searchParams.get("session_id"), 128);
  const assignmentVersion = url.searchParams.get("assignment_version");
  if (leg) liveUrl.searchParams.set("operational_leg", leg);
  if (customerId) liveUrl.searchParams.set("customer_id", customerId);
  if (sessionId) liveUrl.searchParams.set("session_id", sessionId);
  if (assignmentVersion) liveUrl.searchParams.set("assignment_version", assignmentVersion);
  const freshness = url.searchParams.get("freshness_seconds") || env.TRACKING_LOCATION_FRESHNESS_SECONDS || "";
  if (freshness) liveUrl.searchParams.set("freshness_seconds", String(freshness));
  let snapshot;
  let stub;
  try {
    stub = companyTrackingStub(env, tenantId, companyId);
    const upstream = await stub.fetch(liveUrl.toString(), { method: "GET" });
    if (!upstream.ok) {
      if (upstream.status === 409) {
        const denied22 = await upstream.json();
        if (denied22.error === "assignment_changed") return withCors(json2({ ok: false, error: "assignment_changed" }, { status: 409, headers: { "cache-control": "no-store" } }), origin);
      }
      const denied2 = [401, 403, 404].includes(upstream.status);
      return withCors(json2({ ok: false, error: denied2 ? "not_found" : "tracking_unavailable" }, {
        status: denied2 ? 404 : 503,
        headers: { "cache-control": "no-store" }
      }), origin);
    }
    snapshot = await upstream.json();
  } catch (_) {
    return withCors(json2({ ok: false, error: "tracking_unavailable" }, { status: 503, headers: { "cache-control": "no-store" } }), origin);
  }
  const routeRequested = url.searchParams.get("include_route") === "1";
  snapshot.route = null;
  snapshot.eta = null;
  snapshot.route_refresh_required = false;
  snapshot.route_error = null;
  if (routeRequested && snapshot.position && ["en_route_pickup", "in_progress"].includes(snapshot.tracking_phase)) {
    try {
      const grant = await readCustomerGrant(env, { tenant_id: tenantId, company_id: companyId }, bookingId, leg || "primary");
      const target2 = snapshot.tracking_phase === "in_progress" ? "destination" : "pickup";
      const destination = target2 === "destination" ? grant?.destination : grant?.pickup;
      const seenVersion = snapshot.response_version;
      const enriched = typeof env.__customerEtaFetch === "function" ? await env.__customerEtaFetch({ origin: snapshot.position, destination, target: target2 }) : await _callBookingWorkerJson(env, "/track/internal/customer-route", {
        tenant_id: tenantId,
        company_id: companyId,
        booking_id: bookingId,
        operational_leg: leg || "primary",
        assignment_version: snapshot.assignment_version,
        access_token_hash: accessHash
      }, { timeoutMs: 1e4 });
      if (enriched?.ok !== true) throw Object.assign(Error("route_unavailable"), { rateLimited: enriched?.error === "rate_limited" });
      const again = await stub.fetch(liveUrl.toString(), { method: "GET" });
      if (!again.ok) {
        if (again.status === 409) {
          const denied2 = await again.json();
          if (denied2.error === "assignment_changed") return withCors(json2({ ok: false, error: "assignment_changed" }, { status: 409, headers: { "cache-control": "no-store" } }), origin);
        }
        if (again.status === 404 || again.status === 401 || again.status === 403) {
          return withCors(json2({ ok: false, error: "not_found" }, { status: 404, headers: { "cache-control": "no-store" } }), origin);
        }
        return withCors(json2({ ok: false, error: "tracking_unavailable" }, { status: 503, headers: { "cache-control": "no-store" } }), origin);
      }
      const latest = await again.json();
      if (!again.ok || latest.response_version !== seenVersion || latest.tracking_phase !== snapshot.tracking_phase || latest.position == null) {
        snapshot = latest;
        snapshot.eta = null;
        snapshot.route = null;
        snapshot.position = latest.position || null;
      } else if (enriched.eta?.target === target2 && enriched.assignment_version === latest.assignment_version && enriched.tracking_phase === latest.tracking_phase) {
        snapshot.eta = enriched.eta;
        snapshot.route = enriched.route ?? null;
      }
    } catch (routeError) {
      try {
        const current = await stub.fetch(liveUrl.toString(), { method: "GET" });
        if (!current.ok) {
          if (current.status === 409) {
            const denied3 = await current.json();
            if (denied3.error === "assignment_changed") return withCors(json2({ ok: false, error: "assignment_changed" }, { status: 409, headers: { "cache-control": "no-store" } }), origin);
          }
          const denied2 = [401, 403, 404].includes(current.status);
          return withCors(json2({ ok: false, error: denied2 ? "not_found" : "tracking_unavailable" }, { status: denied2 ? 404 : 503, headers: { "cache-control": "no-store" } }), origin);
        }
        snapshot = await current.json();
        snapshot.eta = null;
        snapshot.route = null;
        snapshot.route_refresh_required = true;
        snapshot.route_error = routeError.rateLimited ? "rate_limited" : "route_unavailable";
      } catch (_) {
        return withCors(json2({ ok: false, error: "tracking_unavailable" }, { status: 503, headers: { "cache-control": "no-store" } }), origin);
      }
    }
  }
  const bookingReadsAfter = env.BOOKING_KV?.ops?.reads ?? 0;
  snapshot.ops = {
    booking_kv_reads: bookingReadsAfter - bookingReadsBefore,
    gps_kv_writes: 0,
    room_reads: routeRequested && snapshot.position && ["en_route_pickup", "in_progress"].includes(snapshot.tracking_phase) ? 3 : 1
  };
  return withCors(json2(snapshot, { status: 200, headers: { "cache-control": "no-store" } }), origin);
}
__name(handleCustomerLive, "handleCustomerLive");
async function handleCompanyLive(req, url, env, origin) {
  const auth = await requireDriverOrCompanyOrAdminForScope(req, url, env, {
    routeLabel: "TRACK_COMPANY_LIVE"
  });
  if (!auth.ok) return auth.response;
  if (auth.auth_mode === "driver_session") {
    return withCors(json2({ ok: false, error: "forbidden" }, { status: 403 }), origin);
  }
  let tenantId = "";
  let companyId = "";
  if (auth.company_session) {
    tenantId = auth.company_session.tenant_id;
    companyId = auth.company_session.company_id;
    const askedTenant = safeStr22(url.searchParams.get("tenant_id"), 80);
    const askedCompany = safeStr22(url.searchParams.get("company_id"), 80);
    if (askedTenant && askedTenant !== tenantId || askedCompany && askedCompany !== companyId) {
      return withCors(json2({ ok: false, error: "forbidden" }, { status: 403 }), origin);
    }
  } else {
    const requiredScope = parseRequiredTenantCompanyScope(req, url, null, { returnResponse: true, origin });
    if (requiredScope instanceof Response) return requiredScope;
    tenantId = requiredScope.tenant_id;
    companyId = requiredScope.company_id;
  }
  if (!realtimeDoEnabled(env)) {
    return withCors(
      json2({
        ok: true,
        tenant_id: tenantId,
        company_id: companyId,
        freshness_seconds: 300,
        realtime_disabled: true,
        drivers: []
      }),
      origin
    );
  }
  let upstream;
  try {
    const stub = companyTrackingStub(env, tenantId, companyId);
    const freshness = url.searchParams.get("freshness_seconds") || env.TRACKING_LOCATION_FRESHNESS_SECONDS || "";
    const liveUrl = new URL("https://company-tracking.internal/live");
    liveUrl.searchParams.set("tenant_id", tenantId);
    liveUrl.searchParams.set("company_id", companyId);
    if (freshness) liveUrl.searchParams.set("freshness_seconds", String(freshness));
    upstream = await stub.fetch(liveUrl.toString(), { method: "GET" });
  } catch (_) {
    return withCors(json2({ ok: false, error: "tracking_unavailable" }, { status: 503 }), origin);
  }
  const payload = await upstream.json();
  return withCors(json2(payload, { status: upstream.status }), origin);
}
__name(handleCompanyLive, "handleCompanyLive");
var fluxidi_tracking_api_worker_V2_1_with_route_index_default = {
  async fetch(req, env, ctx) {
    const origin = getOrigin(req);
    const url = new URL(req.url);
    if (req.method === "OPTIONS") {
      return withCors(new Response(null, { status: 204 }), origin);
    }
    try {
      if (req.method === "GET" && url.pathname === "/health") return await handleHealth(req, env, origin);
      if (req.method === "POST" && url.pathname === "/admin/trips/retire-confirmed-test") {
        requireAdmin(req, url, env);
        const body = await readJson(req);
        const result2 = await retireConfirmedTestTrip(body, {
          booking: /* @__PURE__ */ __name(async (id22, scope2) => {
            const base = env.BOOKING_API_URL || "https://fluxidi-booking-api.fluxidi.workers.dev";
            const target2 = new URL(`/bookings/${encodeURIComponent(id22)}`, base);
            target2.searchParams.set("tenant_id", scope2.tenant_id);
            target2.searchParams.set("company_id", scope2.company_id);
            const request = new Request(target2, { headers: { authorization: `Bearer ${env.ADMIN_TOKEN}` }, signal: AbortSignal.timeout(4e3) });
            const response2 = env.BOOKING_API ? await env.BOOKING_API.fetch(request) : await ownedReleaseFetchV1(request);
            if (!response2.ok) throw Error("test_booking_read_unavailable");
            return (await response2.json()).record;
          }, "booking"),
          trip: /* @__PURE__ */ __name(async (id22, scope2) => getScopedOrLegacyTripForScope(env, scope2, id22), "trip"),
          persist: /* @__PURE__ */ __name(async (key2, trip) => kvPutJson(env.FLUXIDI_TRACKING, key2, trip, TTL_TRIP), "persist"),
          release: /* @__PURE__ */ __name(async (trip) => syncDirectDispatchOccupancy(env, trip, "stop"), "release")
        });
        return withCors(json2(result2, { status: Number.isInteger(result2.status) ? result2.status : result2.ok ? 200 : 409 }), origin);
      }
      if (req.method === "GET" && url.pathname === "/admin/dashboard/trip-kpis") return await handleDashboardTripKpis(req, url, env, origin, ctx);
      if ((req.method === "POST" || req.method === "GET") && url.pathname === "/admin/dashboard/trip-kpis/reconcile") {
        return await handleDashboardTripKpisReconcile(req, url, env, origin);
      }
      if (req.method === "GET" && url.pathname === "/admin/dev/dashboard-kpis/reset/dry-run") {
        return await handleDevDashboardKpisReset(req, url, env, origin, { forceDryRun: true });
      }
      if (req.method === "POST" && url.pathname === "/admin/dev/dashboard-kpis/reset") {
        return await handleDevDashboardKpisReset(req, url, env, origin);
      }
      if (req.method === "GET" && url.pathname === "/trips/history") return await handleTripsHistory(req, url, env, origin, ctx);
      if (req.method === "POST" && url.pathname === "/trips/archive") return await handleArchiveTrip(req, url, env, origin);
      if (req.method === "POST" && url.pathname === "/trip/start-direct") return await handleStartDirectTrip(req, url, env, origin, ctx);
      if (req.method === "POST" && url.pathname === "/trip/record-planned-stop") return await handleRecordPlannedStopTrip(req, url, env, origin, ctx);
      if (req.method === "POST" && url.pathname === "/trip/wait-start") return await handleWaitStartTrip(req, url, env, origin);
      if (req.method === "POST" && url.pathname === "/trip/wait-end") return await handleWaitEndTrip(req, url, env, origin);
      if (req.method === "POST" && url.pathname === "/trip/stop") return await handleStopTrip(req, url, env, origin, ctx);
      if (req.method === "POST" && url.pathname === "/trip/reconcile-direct-booking") return await handleReconcileDirectBooking(req, url, env, origin);
      if (req.method === "POST" && url.pathname === "/trip/reconcile-planned-stop") return await handleReconcilePlannedStop(req, url, env, origin);
      if (req.method === "POST" && url.pathname === "/trip/recover-planned-pending") return await handleRecoverPlannedPending(req, url, env, origin);
      if (req.method === "POST" && url.pathname === "/trip/repair-direct-bookings") return await handleRepairDirectBookings(req, url, env, origin);
      if (req.method === "POST" && url.pathname === "/trip/payment") return await handleTripPayment(req, url, env, origin, ctx);
      if (req.method === "POST" && url.pathname === "/track/session/start") return await handleStart(req, url, env, origin, ctx);
      if (req.method === "POST" && url.pathname === "/track/session/reconcile-start") return await handleReconcilePlannedSessionStart(req, url, env, origin);
      if (req.method === "POST" && url.pathname === "/track/driver/location") {
        return await handleDriverPresenceLocation(req, url, env, origin);
      }
      if (req.method === "POST" && url.pathname === "/track/driver/location/withdraw") {
        return await handleDriverLocationWithdraw(req, url, env, origin);
      }
      if (req.method === "POST" && url.pathname === "/track/ping") return await handlePing(req, url, env, origin);
      if (req.method === "POST" && url.pathname === "/track/session/stop") return await handleStop(req, url, env, origin);
      if (req.method === "GET" && url.pathname === "/track/bookings") return await handleBookings(req, url, env, origin);
      if (req.method === "GET" && url.pathname === "/track/booking") return await handleBookingDetails(req, url, env, origin);
      if (req.method === "GET" && url.pathname === "/track/live") return await handleLive(req, url, env, origin);
      if (req.method === "GET" && url.pathname === "/track/internal/company-live") {
        return await handleCompanyLive(req, url, env, origin);
      }
      if (req.method === "GET" && url.pathname === "/track/public/live") return await handlePublicLive(req, url, env, origin);
      if (req.method === "GET" && url.pathname === "/track/customer/live") {
        return await handleCustomerLive(req, url, env, origin);
      }
      if (req.method === "POST" && url.pathname === "/track/internal/customer-grant") {
        return await handleCustomerGrantSync(req, url, env, origin);
      }
      if (req.method === "POST" && url.pathname === "/track/route") return await handleRoute(req, url, env, origin);
      if (req.method === "POST" && url.pathname === "/track/booking/delete") return await handleDeleteBooking(req, url, env, origin);
      if (req.method === "POST" && url.pathname === "/track/bookings/clear") return await handleClearBookings(req, url, env, origin);
      if (req.method === "POST" && url.pathname === "/track/bookings/purge_orphans") return await handlePurgeOrphans(req, url, env, origin);
      return withCors(json2({ ok: false, error: "Not Found", path: url.pathname }, { status: 404 }), origin);
    } catch (err) {
      const msg = typeof err?.message === "string" ? err.message : "Unknown error";
      const status = msg === "Unauthorized" ? 401 : msg.includes("required") || msg.includes("invalid") || msg.includes("Expected") ? 400 : msg.includes("Unknown") || msg.includes("Not Found") || msg.includes("Invalid") || msg.includes("no result") ? 404 : 500;
      return withCors(json2({ ok: false, error: msg }, { status }), origin);
    }
  }
};
export {
  CompanyTrackingRoom,
  fluxidi_tracking_api_worker_V2_1_with_route_index_default as default,
  loadPublicDriverSessionFromRequest,
  materializeTripDashboardKpisBestEffort
};
