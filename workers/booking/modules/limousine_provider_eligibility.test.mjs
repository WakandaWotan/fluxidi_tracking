// LIMOUSINE-MARKETPLACE-P1 — focused eligibility + discovery contract tests.
// Run: node --test workers/booking/modules/limousine_provider_eligibility.test.mjs

import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import {
  LIMOUSINE_ELIGIBILITY_REASONS,
  companyEnabledLimousine,
  evaluateLimousineProviderEligibility,
  filterLimousineEligibleProviders,
  hasEligibleLimousineVehicle,
  isEligibleLimousineProvider,
  isEligibleLimousineVehicle,
  projectLimousineEntitled,
  publicLimousineSignals,
  resolveLimousineAvailabilityTransition,
  resolveLimousineEntitlement,
  resolveNearbyServiceFilter,
  subscriptionPermitsLimousineDiscovery,
} from "./limousine_provider_eligibility.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));

function limousineVehicle(overrides = {}) {
  return {
    name: "Fleet One",
    service_category: "limousine",
    service_class: "executive_sedan",
    is_active: true,
    ...overrides,
  };
}

function eligibleCandidate(overrides = {}) {
  return {
    partner_id: "cmp_x",
    company_name: "Coachline",
    is_active: true,
    availability_status: "active",
    bookable: true,
    profile_enabled: true,
    published_at: "2026-08-17T10:00:00Z",
    subscription_status: "active",
    limousine_entitled: true,
    services: ["limousine"],
    vehicles: [limousineVehicle()],
    ...overrides,
  };
}

const R = LIMOUSINE_ELIGIBILITY_REASONS;

test("1) active entitled published provider with eligible vehicle is returned", () => {
  const result = evaluateLimousineProviderEligibility(eligibleCandidate());
  assert.equal(result.eligible, true);
  assert.equal(result.reason, R.ELIGIBLE);
  assert.equal(isEligibleLimousineProvider(eligibleCandidate()), true);
});

test("2) missing features['limousine'] / projection fails closed", () => {
  assert.equal(resolveLimousineEntitlement({}), false);
  assert.equal(resolveLimousineEntitlement({ features: {} }), false);
  const candidate = eligibleCandidate();
  delete candidate.limousine_entitled;
  assert.equal(evaluateLimousineProviderEligibility(candidate).reason, R.NOT_ENTITLED);
});

test("3) explicit features['limousine'] == false fails closed", () => {
  assert.equal(resolveLimousineEntitlement({ features: { limousine: false } }), false);
  assert.equal(resolveLimousineEntitlement({ limousine_entitled: false }), false);
  const candidate = eligibleCandidate({ limousine_entitled: false });
  assert.equal(evaluateLimousineProviderEligibility(candidate).reason, R.NOT_ENTITLED);
});

test("4) inactive/expired subscription fails closed (existing semantics)", () => {
  assert.equal(subscriptionPermitsLimousineDiscovery("active"), true);
  assert.equal(subscriptionPermitsLimousineDiscovery("valid"), true);
  for (const s of ["trialing", "past_due", "grace_period", "suspended", "cancelled", "expired", ""]) {
    assert.equal(subscriptionPermitsLimousineDiscovery(s), false, s);
  }
  const candidate = eligibleCandidate({ subscription_status: "cancelled" });
  assert.equal(evaluateLimousineProviderEligibility(candidate).reason, R.SUBSCRIPTION_NOT_PERMITTED);
});

test("5) entitled but company-disabled fails closed", () => {
  const candidate = eligibleCandidate({ services: ["taxi_vvb"] });
  assert.equal(evaluateLimousineProviderEligibility(candidate).reason, R.NOT_ENABLED);
  // explicit booking capability false also fails closed
  const explicitOff = eligibleCandidate({
    services: ["limousine"],
    booking_capabilities: { limousine: false },
  });
  assert.equal(companyEnabledLimousine(explicitOff), false);
});

test("6) enabled but unpublished profile fails closed", () => {
  const candidate = eligibleCandidate({ profile_enabled: false, published_at: "" });
  assert.equal(evaluateLimousineProviderEligibility(candidate).reason, R.PROFILE_NOT_PUBLISHED);
});

test("7) public bookings disabled fails closed", () => {
  const candidate = eligibleCandidate({ bookable: false });
  assert.equal(evaluateLimousineProviderEligibility(candidate).reason, R.BOOKINGS_NOT_ACCEPTED);
});

test("8) market not covered fails closed", () => {
  const candidate = eligibleCandidate({
    coverage: { primary_postcode: "9000", postcodes: ["9000"], country: "BE" },
  });
  assert.equal(
    evaluateLimousineProviderEligibility(candidate, { request: { postcode: "9000" } }).eligible,
    true,
  );
  assert.equal(
    evaluateLimousineProviderEligibility(candidate, { request: { postcode: "1000" } }).reason,
    R.MARKET_NOT_COVERED,
  );
});

test("9) missing eligible vehicle/service fails closed", () => {
  assert.equal(evaluateLimousineProviderEligibility(eligibleCandidate({ vehicles: [] })).reason, R.NO_ELIGIBLE_VEHICLE);
  const missingKey = eligibleCandidate();
  delete missingKey.vehicles;
  assert.equal(evaluateLimousineProviderEligibility(missingKey).reason, R.NO_ELIGIBLE_VEHICLE);
});

test("10) text Mercedes/premium/executive/limousine cannot create eligibility", () => {
  // Vehicle qualifies only from authoritative service_category + service_class.
  assert.equal(isEligibleLimousineVehicle({ name: "Mercedes S-Class Limousine", is_active: true }), false);
  assert.equal(isEligibleLimousineVehicle({ category: "Premium", brand_model: "Mercedes", is_active: true }), false);
  // A "class" that is only a marketing word is rejected.
  assert.equal(
    isEligibleLimousineVehicle({ service_category: "limousine", service_class: "premium", is_active: true }),
    false,
  );
  assert.equal(
    isEligibleLimousineVehicle({ service_category: "limousine", service_class: "executive", is_active: true }),
    false,
  );
  // Company-name / historical inference cannot enable the company.
  const nameOnly = eligibleCandidate({
    company_name: "Executive Limousine Mercedes VIP",
    services: ["taxi_vvb"],
    vehicles: [{ name: "Mercedes Limousine", category: "Premium", is_active: true }],
  });
  assert.equal(isEligibleLimousineProvider(nameOnly), false);
});

test("11) deleted/tombstoned/suspended vehicle cannot create eligibility", () => {
  for (const flag of ["deleted", "tombstoned", "suspended", "is_deleted"]) {
    assert.equal(isEligibleLimousineVehicle(limousineVehicle({ [flag]: true })), false, flag);
  }
  assert.equal(isEligibleLimousineVehicle(limousineVehicle({ is_active: false })), false);
  assert.equal(hasEligibleLimousineVehicle(eligibleCandidate({ vehicles: [limousineVehicle({ deleted: true })] })), false);
});

test("12) suspended/deleted/tombstoned company fails closed", () => {
  for (const extra of [{ suspended: true }, { deleted: true }, { tombstoned: true }, { status: "suspended" }]) {
    assert.equal(evaluateLimousineProviderEligibility(eligibleCandidate(extra)).reason, R.COMPANY_DELETED, JSON.stringify(extra));
  }
  assert.equal(evaluateLimousineProviderEligibility(eligibleCandidate({ is_active: false })).reason, R.COMPANY_INACTIVE);
});

test("13) service=limousine returns only eligible providers", () => {
  const providers = [
    eligibleCandidate({ partner_id: "ok" }),
    eligibleCandidate({ partner_id: "no_vehicle", vehicles: [] }),
    eligibleCandidate({ partner_id: "taxi_only", services: ["taxi_vvb"] }),
  ];
  const filtered = filterLimousineEligibleProviders(providers);
  assert.equal(filtered.length, 1);
  assert.equal(filtered[0].partner_id, "ok");
});

test("14) no eligible providers returns empty result", () => {
  const providers = [
    eligibleCandidate({ partner_id: "a", limousine_entitled: false }),
    eligibleCandidate({ partner_id: "b", services: ["taxi_vvb"] }),
  ];
  assert.deepEqual(filterLimousineEligibleProviders(providers), []);
});

test("15) taxi-only company is excluded from limousine", () => {
  const taxiOnly = eligibleCandidate({
    services: ["taxi_vvb", "online_payments"],
    vehicles: [{ name: "Taxi 1", category: "Comfort", is_active: true }],
  });
  assert.equal(isEligibleLimousineProvider(taxiOnly), false);
});

test("16) airport-only company is excluded from limousine", () => {
  const airportOnly = eligibleCandidate({
    services: ["airport_transfer"],
    capabilities: { airport: true },
    booking_capabilities: { airport: true },
    vehicles: [{ name: "Van", category: "Comfort", is_active: true }],
  });
  assert.equal(companyEnabledLimousine(airportOnly), false);
  assert.equal(isEligibleLimousineProvider(airportOnly), false);
});

test("17/18) resolveNearbyServiceFilter leaves taxi/airport discovery unchanged", () => {
  assert.equal(resolveNearbyServiceFilter(undefined), null);
  assert.equal(resolveNearbyServiceFilter(""), null);
  assert.equal(resolveNearbyServiceFilter("airport"), null); // airport stays client-side
  assert.equal(resolveNearbyServiceFilter("taxi"), null);
  assert.equal(resolveNearbyServiceFilter("banana"), null); // unknown never becomes limousine
  assert.equal(resolveNearbyServiceFilter("limousine"), "limousine");
  assert.equal(resolveNearbyServiceFilter("limousine_service"), "limousine");
});

test("19) limousine and airport may coexist for one valid company", () => {
  const both = eligibleCandidate({
    services: ["limousine", "airport_transfer"],
    capabilities: { airport: true, limousine: true },
  });
  assert.equal(isEligibleLimousineProvider(both), true);
  assert.equal(companyEnabledLimousine(both), true);
});

test("20/21) monotonic transitions: older cannot resurrect; newer reactivates", () => {
  const stale = resolveLimousineAvailabilityTransition({
    currentCommand: "suspend",
    currentRevision: 10,
    incomingCommand: "enable",
    incomingRevision: 9,
  });
  assert.equal(stale.applied, false);
  assert.equal(stale.effectiveCommand, "suspend");
  assert.equal(stale.ignoredReason, "stale_revision");

  const replay = resolveLimousineAvailabilityTransition({
    currentCommand: "disable",
    currentRevision: 10,
    incomingCommand: "enable",
    incomingRevision: 10,
  });
  assert.equal(replay.applied, false);
  assert.equal(replay.ignoredReason, "idempotent_replay");

  const reactivate = resolveLimousineAvailabilityTransition({
    currentCommand: "suspend",
    currentRevision: 10,
    incomingCommand: "enable",
    incomingRevision: 11,
  });
  assert.equal(reactivate.applied, true);
  assert.equal(reactivate.effectiveCommand, "enable");
  assert.equal(reactivate.effectiveRevision, 11);
});

test("projectLimousineEntitled combines features + active subscription", () => {
  assert.equal(projectLimousineEntitled({ features: { limousine: true }, subscriptionStatus: "active" }), true);
  assert.equal(projectLimousineEntitled({ features: { limousine: true }, subscriptionStatus: "trialing" }), false);
  assert.equal(projectLimousineEntitled({ features: { limousine: false }, subscriptionStatus: "active" }), false);
  assert.equal(projectLimousineEntitled({ features: {}, subscriptionStatus: "active" }), false);
});

test("25) public signals contain no subscription-private / customer-private fields", () => {
  const signals = publicLimousineSignals(eligibleCandidate());
  assert.deepEqual(Object.keys(signals).sort(), ["limousine_available", "limousine_service_enabled"]);
  assert.equal(signals.limousine_available, true);
  assert.equal(signals.limousine_service_enabled, true);
  for (const key of Object.keys(signals)) {
    assert.ok(!/feature|subscription|plan|billing|email|price|customer/i.test(key), key);
  }
});

test("23) worker adds only the limousine feature — no new plan/SKU/checkout", () => {
  const workerSource = readFileSync(join(__dirname, "..", "fluxidi_booking_worker.js"), "utf8");
  // allowed plans set unchanged
  assert.ok(
    workerSource.includes('const allowedPlans = new Set(["starter", "pro", "business", "enterprise", "fluxidi_pro"]);'),
    "allowedPlans set must be unchanged",
  );
  // add-on SKU set unchanged (no limousine SKU) — scope the check to the Set block
  const addonMatch = workerSource.match(/FLUXIDI_SUPPORTED_ADDON_CODES = new Set\(\[([\s\S]*?)\]\)/);
  assert.ok(addonMatch, "addon codes Set present");
  assert.ok(!/limousine/i.test(addonMatch[1]), "no limousine add-on SKU");
  // limousine feature added to the entitlement map
  assert.ok(/features:\s*\{[\s\S]*?limousine: true/.test(workerSource), "limousine feature default present");
});

test("worker wires the module into discovery, publish projection and normalization", () => {
  const workerSource = readFileSync(join(__dirname, "..", "fluxidi_booking_worker.js"), "utf8");
  // discovery: service param parsed + server-side filter applied
  assert.ok(workerSource.includes('_resolveNearbyServiceFilter(service)'), "listNearbyPartners resolves service filter");
  assert.ok(workerSource.includes('url.searchParams.get("service")'), "route parses service param");
  assert.ok(workerSource.includes("limousineEligibleByPartnerId.get(entry.p.partner_id) !== true"), "limousine filter applied");
  assert.ok(workerSource.includes("_limousineTestCompanyAllowlisted(env, nearbyCompanyId)"), "allowlist applied to nearby filter");
  // publish: server-owned entitlement projection injected (client value overwritten)
  assert.ok(workerSource.includes("_projectLimousineEntitled({"), "publish projects entitlement");
  assert.ok(workerSource.includes("limousine_entitled: _limousineEntitledProjection"), "entitlement stamped on profile");
  // normalization preserves the safe capability + authoritative vehicle class
  assert.ok(/booking_capabilities[\s\S]*?limousine: _safePublicBool/.test(workerSource), "booking cap preserves limousine");
  assert.ok(workerSource.includes("service_category: serviceCategory"), "public vehicle preserves service_category");
  assert.ok(workerSource.includes("service_class: serviceClass"), "public vehicle preserves service_class");
});
