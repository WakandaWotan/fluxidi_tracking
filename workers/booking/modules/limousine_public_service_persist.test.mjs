// Persist/merge contract for the public Limousine service toggle.
// Run: node --test workers/booking/modules/limousine_public_service_persist.test.mjs

import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import {
  companyEnabledLimousine,
  evaluateLimousineProviderEligibility,
  isEligibleLimousineProvider,
} from "./limousine_provider_eligibility.mjs";
import {
  isLimousineDiscoveryListable,
} from "./limousine_discovery_preview.mjs";
import {
  limousineBookGateEnabled,
} from "./limousine_booking.mjs";
import {
  limousineManualQuoteGateEnabled,
} from "./limousine_manual_quote.mjs";
import {
  limousineQuoteGateEnabled,
} from "./limousine_pricing_resolver.mjs";
import {
  isStalePartnerPublish,
  mergeBusinessProfilePublicServices,
  mergePublicPartnerProfilePreserveOmitted,
  publicServicesIncludeLimousine,
} from "./limousine_public_service_persist.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const worker = readFileSync(join(__dirname, "..", "fluxidi_booking_worker.js"), "utf8");

function eligibleProfile(overrides = {}) {
  return {
    partner_id: "pub_cmp_a",
    company_name: "Maison Noire",
    is_active: true,
    profile_enabled: true,
    published_at: "2026-08-19T06:00:00Z",
    subscription_status: "active",
    limousine_entitled: true,
    services: ["limousine", "taxi_vvb"],
    booking_capabilities: { limousine: true },
    vehicles: [
      {
        name: "Stretch",
        service_category: "limousine",
        service_class: "stretch_limousine",
        is_active: true,
      },
    ],
    limousine_offers: [
      {
        offer_id: "off_1",
        enabled: true,
        published: true,
        price_presentation: "from_price",
        display_amount_cents: 45000,
        currency: "EUR",
      },
    ],
    ...overrides,
  };
}

test("omitted business-profile fields keep an existing limousine=true", () => {
  const merged = mergeBusinessProfilePublicServices(
    {
      publicServiceIds: ["taxi_vvb", "limousine"],
      publicServicesConfigured: true,
    },
    { companyName: "Maison Noire" },
  );
  assert.deepEqual(merged.publicServiceIds, ["taxi_vvb", "limousine"]);
  assert.equal(merged.publicServicesConfigured, true);
  assert.equal(publicServicesIncludeLimousine(merged.publicServiceIds), true);
});

test("explicit uncheck persists limousine=false", () => {
  const merged = mergeBusinessProfilePublicServices(
    {
      publicServiceIds: ["taxi_vvb", "limousine"],
      publicServicesConfigured: true,
    },
    {
      publicServiceIds: ["taxi_vvb"],
      publicServicesConfigured: true,
    },
  );
  assert.deepEqual(merged.publicServiceIds, ["taxi_vvb"]);
  assert.equal(publicServicesIncludeLimousine(merged.publicServiceIds), false);
});

test("omitted partner publish keeps services and does not default limousine off", () => {
  const existing = eligibleProfile();
  const merged = mergePublicPartnerProfilePreserveOmitted(existing, {
    company_name: "Maison Noire",
    tagline: "Updated",
  });
  assert.deepEqual(merged.services, ["limousine", "taxi_vvb"]);
  assert.equal(merged.booking_capabilities.limousine, true);
  assert.equal(companyEnabledLimousine(merged), true);
  assert.equal(evaluateLimousineProviderEligibility(merged).eligible, true);
});

test("explicit partner publish can turn limousine off", () => {
  const merged = mergePublicPartnerProfilePreserveOmitted(eligibleProfile(), {
    services: ["taxi_vvb"],
    booking_capabilities: { limousine: false },
  });
  assert.equal(publicServicesIncludeLimousine(merged.services), false);
  assert.equal(merged.booking_capabilities.limousine, false);
  assert.equal(companyEnabledLimousine(merged), false);
});

test("stale revision cannot roll a true toggle back", () => {
  assert.equal(
    isStalePartnerPublish({ existingRevision: 12, incomingRevision: 7 }),
    true,
  );
  assert.equal(
    isStalePartnerPublish({ existingRevision: 12, incomingRevision: 12 }),
    false,
  );
  assert.equal(
    isStalePartnerPublish({ existingRevision: 12 }),
    false,
  );
});

test("hero-only incoming does not drop services or offers", () => {
  const merged = mergePublicPartnerProfilePreserveOmitted(eligibleProfile(), {
    limousine_hero_url: "https://cdn.example/hero.jpg",
    limousine_hero_source: "upload",
  });
  assert.deepEqual(merged.services, ["limousine", "taxi_vvb"]);
  assert.equal(merged.limousine_offers[0].offer_id, "off_1");
  assert.equal(companyEnabledLimousine(merged), true);
});

test("fleet-only incoming keeps service toggle and offer bindings", () => {
  const incomingVehicles = [
    {
      name: "Hummer",
      service_category: "limousine",
      service_class: "stretch_suv",
      is_active: true,
    },
  ];
  const merged = mergePublicPartnerProfilePreserveOmitted(eligibleProfile(), {
    vehicles: incomingVehicles,
  });
  assert.deepEqual(merged.services, ["limousine", "taxi_vvb"]);
  assert.equal(merged.limousine_offers[0].offer_id, "off_1");
  assert.equal(merged.vehicles[0].name, "Hummer");
});

test("offer-only incoming keeps the public service toggle", () => {
  const merged = mergePublicPartnerProfilePreserveOmitted(eligibleProfile(), {
    limousine_offers: [
      {
        offer_id: "off_2",
        enabled: true,
        published: true,
        price_presentation: "hourly",
        display_amount_cents: 18000,
        currency: "EUR",
      },
    ],
  });
  assert.equal(publicServicesIncludeLimousine(merged.services), true);
  assert.equal(merged.limousine_offers[0].offer_id, "off_2");
});

test("general profile publish without services keeps limousine projection inputs", () => {
  const merged = mergePublicPartnerProfilePreserveOmitted(eligibleProfile(), {
    about_short: "New public text",
    media: { logo_url: "https://cdn.example/logo.png" },
  });
  assert.equal(isEligibleLimousineProvider(merged), true);
  assert.equal(isLimousineDiscoveryListable(merged), true);
});

test("transaction gates stay off and do not change discovery eligibility", () => {
  const env = {
    LIMOUSINE_QUOTE_ENABLED: "false",
    LIMOUSINE_MANUAL_QUOTE_ENABLED: "false",
    LIMOUSINE_BOOK_ENABLED: "false",
  };
  assert.equal(limousineQuoteGateEnabled(env), false);
  assert.equal(limousineManualQuoteGateEnabled(env), false);
  assert.equal(limousineBookGateEnabled(env), false);
  const gated = eligibleProfile({ bookable: false, public_bookings_accepted: false });
  assert.equal(evaluateLimousineProviderEligibility(gated).eligible, true);
  assert.equal(isLimousineDiscoveryListable(gated), true);
});

test("taxi and airport stay independent of the limousine token", () => {
  const taxiOnly = mergePublicPartnerProfilePreserveOmitted(
    { services: ["taxi_vvb", "airport_transfer"], booking_capabilities: { limousine: false } },
    { services: ["taxi_vvb", "airport_transfer"] },
  );
  assert.deepEqual(taxiOnly.services, ["taxi_vvb", "airport_transfer"]);
  assert.equal(companyEnabledLimousine(taxiOnly), false);
  assert.equal(
    companyEnabledLimousine({
      services: ["limousine"],
      booking_capabilities: { limousine: false },
    }),
    true,
  );
});

test("worker publish/save paths use omit-merge helpers", () => {
  assert.match(worker, /mergeBusinessProfilePublicServices/);
  assert.match(worker, /mergePublicPartnerProfilePreserveOmitted/);
  assert.match(worker, /isStalePartnerPublish/);
  assert.match(worker, /publicServiceIds/);
  assert.match(worker, /publicServicesConfigured/);
});
