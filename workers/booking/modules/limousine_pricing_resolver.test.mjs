// LIMOUSINE-MARKETPLACE-P2B1 — pricing resolution + storage contract tests.
// Run: node --test workers/booking/modules/limousine_pricing_resolver.test.mjs
//
// NOTE: all amounts here are illustrative TEST fixtures in integer cents, never
// production fares.

import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import {
  LIMOUSINE_PRICING_MODES,
  LIMOUSINE_PRICING_REASONS,
  limousineQuoteGateEnabled,
  normalizeLimousinePricingSection,
  resolveLimousineQuote,
} from "./limousine_pricing_resolver.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const R = LIMOUSINE_PRICING_REASONS;

// Illustrative test-only section (NOT production fares).
function section(overrides = {}) {
  return {
    enabled: true,
    currency: "EUR",
    source_revision: 3,
    classes: [
      {
        service_class_id: "executive_sedan",
        enabled: true,
        currency: "EUR",
        manual_quote_fallback: false,
        source_revision: 3,
        fixed_rules: [
          {
            rule_id: "fx_airport_to",
            enabled: true,
            priority: 10,
            journey_type: "airport_transfer",
            direction: "to_airport",
            airport_iata: "BRU",
            zone_type: "none",
            price_incl_vat_cents: 12000,
            vat_rate: 0.06,
            currency: "EUR",
            source_revision: 3,
          },
        ],
        packages: [
          {
            package_id: "pkg_3h",
            enabled: true,
            journey_type: "hourly_package",
            duration_minutes: 180,
            total_incl_vat_cents: 30000,
            vat_rate: 0.06,
            currency: "EUR",
            source_revision: 3,
          },
        ],
        distance_time: {
          enabled: true,
          base_incl_vat_cents: 5000,
          per_km_incl_vat_cents: 200,
          per_minute_incl_vat_cents: 100,
          minimum_incl_vat_cents: 8000,
          vat_rate: 0.06,
          currency: "EUR",
          source_revision: 3,
        },
        ...(overrides.class || {}),
      },
    ],
    ...overrides.section,
  };
}

function req(overrides = {}) {
  return {
    service_category: "limousine",
    service_class_id: "executive_sedan",
    journey_type: "point_to_point",
    currency: "EUR",
    ...overrides,
  };
}

const ROUTE = { distance_km: 20, duration_min: 30 };

function resolve(overrides = {}) {
  return resolveLimousineQuote({
    gateEnabled: true,
    eligible: true,
    section: section(),
    request: req(),
    route: ROUTE,
    ...overrides,
  });
}

test("1) gate off blocks only the limousine quote (no price)", () => {
  const r = resolve({ gateEnabled: false });
  assert.equal(r.resolved, false);
  assert.equal(r.reason, R.GATE_OFF);
  assert.equal(r.price_incl_vat, undefined);
  // gate reader treats missing/"0"/false as OFF
  assert.equal(limousineQuoteGateEnabled("0"), false);
  assert.equal(limousineQuoteGateEnabled(undefined), false);
  assert.equal(limousineQuoteGateEnabled("false"), false);
  assert.equal(limousineQuoteGateEnabled("1"), true);
  assert.equal(limousineQuoteGateEnabled("true"), true);
});

test("22/23) provider eligibility is required", () => {
  const r = resolve({ eligible: false });
  assert.equal(r.resolved, false);
  assert.equal(r.reason, R.NOT_ELIGIBLE);
  assert.equal(r.price_incl_vat, undefined);
});

test("24/6) missing/unknown service class is rejected", () => {
  assert.equal(resolve({ request: req({ service_class_id: "" }) }).reason, R.MISSING_CLASS);
  assert.equal(resolve({ request: req({ service_class_id: "mercedes" }) }).reason, R.MISSING_CLASS);
  assert.equal(resolve({ request: req({ service_class_id: "unknown_class" }) }).reason, R.UNKNOWN_CLASS);
});

test("4) fixed limousine fare wins over package and distance/time", () => {
  const r = resolve({
    request: req({
      journey_type: "airport_transfer",
      airport_iata: "BRU",
      direction: "to_airport",
    }),
  });
  assert.equal(r.resolved, true);
  assert.equal(r.pricing_mode, LIMOUSINE_PRICING_MODES.FIXED);
  assert.equal(r.matched_rule_ref, "fx_airport_to");
  assert.equal(r.currency, "EUR");
  assert.equal(r.price_incl_vat, 120); // 12000 cents, already €0.10-aligned
});

test("5) taxi and limousine fixed fares coexist (resolver only reads limousine)", () => {
  // The resolver never consults the airport/taxi fixed-fare store; a limousine
  // rule for BRU/to_airport is separate from any taxi BRU rule.
  const r = resolve({
    request: req({ journey_type: "airport_transfer", airport_iata: "BRU", direction: "to_airport" }),
  });
  assert.equal(r.service_category, "limousine");
  assert.equal(r.matched_rule_ref, "fx_airport_to");
  // A taxi request would never enter this resolver at all (category check).
  assert.equal(resolve({ request: req({ service_category: "taxi" }) }).reason, R.UNAVAILABLE);
});

test("7) hourly package applies only to hourlyPackage journey", () => {
  // point_to_point: package must NOT apply; falls to distance/time here.
  const p2p = resolve({ request: req({ journey_type: "point_to_point" }) });
  assert.equal(p2p.pricing_mode, LIMOUSINE_PRICING_MODES.DISTANCE_TIME);
  // hourly_package: package applies.
  const hourly = resolve({ request: req({ journey_type: "hourly_package" }) });
  assert.equal(hourly.pricing_mode, LIMOUSINE_PRICING_MODES.PACKAGE);
  assert.equal(hourly.matched_rule_ref, "pkg_3h");
});

test("8/9) distance/time applies after no fixed/package and uses server route", () => {
  const r = resolve({ request: req({ journey_type: "point_to_point" }) });
  assert.equal(r.pricing_mode, LIMOUSINE_PRICING_MODES.DISTANCE_TIME);
  // 5000 + 20*200 + 30*100 = 5000+4000+3000 = 12000c => €120.00
  assert.equal(r.price_incl_vat, 120);
  // A different server route changes the price (route is authoritative).
  const longer = resolve({
    request: req({ journey_type: "point_to_point" }),
    route: { distance_km: 40, duration_min: 60 },
  });
  // 5000 + 40*200 + 60*100 = 5000+8000+6000 = 19000c => €190.00
  assert.equal(longer.price_incl_vat, 190);
});

test("17) integer arithmetic honors the €0.10 rounding policy", () => {
  const r = resolve({
    request: req({ journey_type: "point_to_point" }),
    route: { distance_km: 10.5, duration_min: 15 }, // 5000 + 2100 + 1500 = 8600c
  });
  assert.equal(r.price_incl_vat, 86); // €86.00, already dime-aligned
  // ex + vat === incl (finalizer invariant)
  assert.equal(
    Math.round((r.price_ex_vat + r.price_vat) * 100),
    Math.round(r.price_incl_vat * 100),
  );
});

test("11/12) missing pricing => manual or unavailable, never taxi", () => {
  const bare = section({
    class: {
      fixed_rules: [],
      packages: [],
      distance_time: null,
      manual_quote_fallback: false,
    },
  });
  const r = resolveLimousineQuote({
    gateEnabled: true,
    eligible: true,
    section: bare,
    request: req(),
    route: ROUTE,
  });
  assert.equal(r.resolved, false);
  assert.equal(r.reason, R.UNAVAILABLE);
  assert.equal(r.price_incl_vat, undefined);

  const manual = section({
    class: {
      fixed_rules: [],
      packages: [],
      distance_time: null,
      manual_quote_fallback: true,
    },
  });
  const m = resolveLimousineQuote({
    gateEnabled: true,
    eligible: true,
    section: manual,
    request: req(),
    route: ROUTE,
  });
  assert.equal(m.manual_quote_required, true);
  assert.equal(m.reason, R.MANUAL_QUOTE);
  assert.equal(m.price_incl_vat, undefined);
});

test("14) currency mismatch fails closed", () => {
  const r = resolve({ request: req({ currency: "USD" }) });
  assert.equal(r.resolved, false);
  assert.equal(
    [R.CURRENCY_MISMATCH, R.UNAVAILABLE].includes(r.reason),
    true,
    r.reason,
  );
  // Explicit conflicting fixed-rule currency also fails closed.
  const conflict = section({
    class: {
      fixed_rules: [
        {
          rule_id: "usd_rule",
          enabled: true,
          journey_type: "point_to_point",
          zone_type: "none",
          price_incl_vat_cents: 10000,
          currency: "USD",
          vat_rate: 0,
        },
      ],
      packages: [],
      distance_time: null,
    },
  });
  const c = resolveLimousineQuote({
    gateEnabled: true,
    eligible: true,
    section: conflict,
    request: req({ journey_type: "point_to_point", currency: "EUR" }),
    route: ROUTE,
  });
  assert.equal(c.reason, R.CURRENCY_MISMATCH);
});

test("15) stale/contradictory revision fails closed", () => {
  const r = resolve({ request: req({ expected_source_revision: 99 }) });
  assert.equal(r.resolved, false);
  assert.equal(r.reason, R.STALE_REVISION);
});

test("16) ambiguous fixed rules fail closed", () => {
  const ambiguous = section({
    class: {
      fixed_rules: [
        {
          rule_id: "same",
          enabled: true,
          priority: 5,
          journey_type: "point_to_point",
          zone_type: "none",
          price_incl_vat_cents: 10000,
          currency: "EUR",
          vat_rate: 0,
        },
        {
          rule_id: "same",
          enabled: true,
          priority: 5,
          journey_type: "point_to_point",
          zone_type: "none",
          price_incl_vat_cents: 11000,
          currency: "EUR",
          vat_rate: 0,
        },
      ],
      packages: [],
      distance_time: null,
    },
  });
  const r = resolveLimousineQuote({
    gateEnabled: true,
    eligible: true,
    section: ambiguous,
    request: req({ journey_type: "point_to_point" }),
    route: ROUTE,
  });
  assert.equal(r.reason, R.AMBIGUOUS_FIXED_RULE);
});

test("18) resolved result contains complete pricing provenance", () => {
  const r = resolve({
    request: req({ journey_type: "airport_transfer", airport_iata: "BRU", direction: "to_airport" }),
  });
  for (const key of [
    "service_category",
    "journey_type",
    "service_class_id",
    "pricing_mode",
    "matched_rule_ref",
    "source_revision",
    "distance_km",
    "duration_min",
    "price_incl_vat",
    "price_ex_vat",
    "price_vat",
    "currency",
    "vat_mode",
    "included_options",
    "separately_disclosed_charges",
  ]) {
    assert.ok(r[key] !== undefined, `missing ${key}`);
  }
});

test("19) manual/unavailable contains no numeric customer price", () => {
  const r = resolve({ gateEnabled: false });
  assert.equal(r.price_incl_vat, undefined);
  assert.equal(r.price_ex_vat, undefined);
  assert.equal(r.price_vat, undefined);
});

test("unsupported journey type fails closed", () => {
  const r = resolve({ request: req({ journey_type: "spaceflight" }) });
  assert.equal(r.reason, R.UNSUPPORTED_JOURNEY_TYPE);
});

test("storage normalizer: absent section is disabled, no taxi impact", () => {
  const s = normalizeLimousinePricingSection(null);
  assert.equal(s.enabled, false);
  assert.deepEqual(s.classes, []);
});

test("10/26) /quote wiring: gated, eligibility, no taxi fallback, no booking", () => {
  const workerSource = readFileSync(join(__dirname, "..", "fluxidi_booking_worker.js"), "utf8");
  // limousine branch is guarded by the request category AND returns early
  assert.ok(workerSource.includes("const _isLimousineQuoteRequest ="), "limousine branch guard present");
  assert.ok(workerSource.includes("_limousineQuoteGateEnabled(env)"), "server gate checked");
  assert.ok(
    workerSource.includes("_resolveLimousineProviderEligibility(env, quoteScope)"),
    "eligibility required",
  );
  assert.ok(
    workerSource.includes("return _isEligibleLimousineProvider(profile);"),
    "eligibility resolved from the authoritative partner profile",
  );
  assert.ok(workerSource.includes("_resolveLimousineQuote({"), "resolver invoked");
  // the branch returns before the airport/taxi pricing branch (no fallback)
  const branchIdx = workerSource.indexOf("if (_isLimousineQuoteRequest) {");
  const returnIdx = workerSource.indexOf("return { status: 200, out: limoOut };");
  const airportIdx = workerSource.indexOf("_hasExplicitAirportFixedFareScope(body, quoteScope)");
  assert.ok(branchIdx > 0 && returnIdx > branchIdx, "branch returns early");
  assert.ok(returnIdx < airportIdx, "limousine returns before taxi/airport branch (no fallback)");
  // taxi profile is not consulted for limousine pricing
  const branchWindow = workerSource.slice(branchIdx, returnIdx);
  assert.ok(!branchWindow.includes("calcPrice("), "no taxi calcPrice in limousine branch");
  assert.ok(!branchWindow.includes("resolveAirportFixedFare("), "no airport fallback in branch");
  for (const bookingToken of [
    "putBookingCreateIfAbsent",
    "persistBooking",
    "createBooking",
    "payment",
    "checkout",
    "reserveHumanBookingId",
  ]) {
    assert.ok(!branchWindow.includes(bookingToken), `no ${bookingToken} in branch`);
  }
  // server gate default OFF in wrangler
  const wrangler = readFileSync(join(__dirname, "..", "wrangler.toml"), "utf8");
  assert.ok(wrangler.includes('LIMOUSINE_QUOTE_ENABLED = "0"'), "gate committed OFF");
});
