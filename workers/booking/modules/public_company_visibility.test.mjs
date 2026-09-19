import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import { createMemoryRegistryKv, upsertCompanyRegistryEntry } from "./company_registry_index.mjs";
import { applyPublicVisibilityOverride, publicVisibilityCodeKey } from "./company_account_lifecycle.mjs";
import {
  applyPublicMarketplaceProfileOverlay,
  classifyRegistryPublicVisibility,
  isPublicMarketplaceCompanyCode,
  isPublicMarketplacePartner,
  loadPublicCompanyVisibilityIndex,
  partnerAliasesFromLink,
  EXAMPLE_COMPANY_COPY,
} from "./public_company_visibility.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const WORKER_SRC = readFileSync(join(HERE, "../fluxidi_booking_worker.js"), "utf8");

function linkRecord(code, tenant, company, name) {
  return {
    company_code: code,
    tenant_id: tenant,
    company_id: company,
    display_name: name,
    linking_enabled: true,
  };
}

async function seedIndex() {
  const kv = createMemoryRegistryKv();
  await upsertCompanyRegistryEntry(kv, {
    company_code: "FLX-00001",
    display_name: "Fluxidi",
    environment_class: "unknown",
  });
  await upsertCompanyRegistryEntry(kv, {
    company_code: "FLX-00020",
    display_name: "Fluxidi Google Review",
    environment_class: "review",
  });
  await upsertCompanyRegistryEntry(kv, {
    company_code: "FLX-00024",
    display_name: "Luchthavenvervoer JM",
    environment_class: "unknown",
  });
  kv.map.set("company_link:index:code:FLX-00001:v1", JSON.stringify(linkRecord(
    "FLX-00001",
    "fluxidi_fluxidi_ddmh9g",
    "fluxidi_fluxidi_ddmh9g",
    "Fluxidi",
  )));
  kv.map.set("company_link:index:code:FLX-00020:v1", JSON.stringify(linkRecord(
    "FLX-00020",
    "cmp_fluxidi-google-review_f94c806649",
    "cmp_fluxidi-google-review_f94c806649",
    "Fluxidi Google Review",
  )));
  kv.map.set("company_link:index:code:FLX-00024:v1", JSON.stringify(linkRecord(
    "FLX-00024",
    "cmp_luchthavenvervoer-jm_239993ea75",
    "cmp_luchthavenvervoer-jm_239993ea75",
    "Luchthavenvervoer JM",
  )));
  return kv;
}

test("missing registry lifecycle is never treated as public-active", () => {
  const missing = classifyRegistryPublicVisibility({
    company_code: "FLX-00033",
    environment_class: "unknown",
  });
  assert.equal(missing.public, false);
  assert.equal(missing.reason, "registry_lifecycle_inactive");
});

test("registry membership keeps real and review companies without a six-company hardlist", () => {
  const keepUnknown = classifyRegistryPublicVisibility({
    company_code: "FLX-00033",
    lifecycle_status: "active",
    environment_class: "unknown",
  });
  assert.equal(keepUnknown.public, true);
  assert.equal(keepUnknown.presentation.role, "operator");

  const keepReview = classifyRegistryPublicVisibility({
    company_code: "FLX-00020",
    lifecycle_status: "active",
    environment_class: "review",
  });
  assert.equal(keepReview.public, true);
  assert.equal(keepReview.presentation.role, "review");

  const hideTest = classifyRegistryPublicVisibility({
    company_code: "FLX-00021",
    lifecycle_status: "active",
    environment_class: "test",
  });
  assert.equal(hideTest.public, false);
  assert.equal(hideTest.reason, "environment_hidden");
});

test("few rides or missing integrations are not a test classifier", () => {
  const decision = classifyRegistryPublicVisibility({
    company_code: "FLX-00026",
    lifecycle_status: "active",
    environment_class: "unknown",
    ride_count: 0,
    trial: true,
    mollie_connected: false,
  });
  assert.equal(decision.public, true);
  assert.equal(decision.reason, "registry_public");
});

test("orphaned public-index partners stay hidden when they are not in the registry", async () => {
  const kv = await seedIndex();
  const index = await loadPublicCompanyVisibilityIndex({ BOOKING_KV: kv });
  assert.equal(index.ok, true);
  assert.equal(isPublicMarketplaceCompanyCode(index, "FLX-00001"), true);
  assert.equal(isPublicMarketplaceCompanyCode(index, "FLX-00020"), true);
  assert.equal(isPublicMarketplaceCompanyCode(index, "FLX-00024"), true);
  assert.equal(isPublicMarketplaceCompanyCode(index, "FLX-00017"), false);
  assert.equal(isPublicMarketplaceCompanyCode(index, "FLX-00021"), false);
  assert.equal(isPublicMarketplacePartner(index, {
    partner_id: "company:cmp_wotans-taxi-bedrijf_14881b0cb6:cmp_wotans-taxi-bedrijf_14881b0cb6",
    company_id: "cmp_wotans-taxi-bedrijf_14881b0cb6",
  }), false);
  assert.equal(isPublicMarketplacePartner(index, {
    partner_id: "company:cmp_prometheus_97a13bf5a9:cmp_prometheus_97a13bf5a9",
  }), false);
  assert.equal(isPublicMarketplacePartner(index, {
    partner_id: "company:fluxidi_fluxidi_ddmh9g:fluxidi_fluxidi_ddmh9g",
    company_id: "fluxidi_fluxidi_ddmh9g",
  }), true);
  assert.equal(isPublicMarketplacePartner(index, {
    partner_id: "company:cmp_fluxidi-google-review_f94c806649:cmp_fluxidi-google-review_f94c806649",
  }), true);
});

test("example overlay keeps the legal display name and reuses existing profile fields", () => {
  const overlaid = applyPublicMarketplaceProfileOverlay({
    company_name: "Fluxidi",
    tagline: "Premium mobility in your area",
    about_short: "Reliable rides for private and business customers.",
  }, { role: "example", company_code: "FLX-00001" }, "nl");
  assert.equal(overlaid.company_name, "Fluxidi");
  assert.equal(overlaid.example_company, true);
  assert.equal(overlaid.tagline, EXAMPLE_COMPANY_COPY.badge.nl);
  assert.equal(overlaid.about_short, EXAMPLE_COMPANY_COPY.notice.nl);
  assert.equal(overlaid.public_presentation.role, "example");
});

test("link aliases include canonical partner id and scoped company id", () => {
  const aliases = partnerAliasesFromLink(linkRecord(
    "FLX-00001",
    "fluxidi_fluxidi_ddmh9g",
    "fluxidi_fluxidi_ddmh9g",
    "Fluxidi",
  ), "FLX-00001");
  assert.ok(aliases.includes("company:fluxidi_fluxidi_ddmh9g:fluxidi_fluxidi_ddmh9g"));
  assert.ok(aliases.includes("fluxidi_fluxidi_ddmh9g"));
  assert.ok(aliases.includes("FLX-00001"));
});

test("platform public visibility override hides an otherwise public review company", async () => {
  const hiddenByField = classifyRegistryPublicVisibility({
    company_code: "FLX-00020",
    lifecycle_status: "active",
    environment_class: "review",
    public_visibility: "hidden",
  });
  assert.equal(hiddenByField.public, false);
  assert.equal(hiddenByField.reason, "public_visibility_hidden");

  const kv = await seedIndex();
  await applyPublicVisibilityOverride(kv, {
    tenantId: "cmp_fluxidi-google-review_f94c806649",
    companyId: "cmp_fluxidi-google-review_f94c806649",
    companyCode: "FLX-00020",
    visibility: "hidden",
  });
  const beforeUpsert = kv.map.get(publicVisibilityCodeKey("FLX-00020"));
  await upsertCompanyRegistryEntry(kv, {
    company_code: "FLX-00020",
    display_name: "Fluxidi Google Review",
    environment_class: "review",
    lifecycle_status: "active",
  });
  assert.equal(kv.map.get(publicVisibilityCodeKey("FLX-00020")), beforeUpsert);
  const index = await loadPublicCompanyVisibilityIndex({ BOOKING_KV: kv });
  assert.equal(isPublicMarketplaceCompanyCode(index, "FLX-00020"), false);
  assert.equal(isPublicMarketplaceCompanyCode(index, "FLX-00001"), true);
  assert.equal(isPublicMarketplacePartner(index, {
    partner_id: "company:cmp_fluxidi-google-review_f94c806649:cmp_fluxidi-google-review_f94c806649",
  }), false);
});

test("worker public surfaces call the registry visibility gate", () => {
  const moduleSrc = readFileSync(join(HERE, "public_company_visibility.mjs"), "utf8");
  assert.match(WORKER_SRC, /loadPublicCompanyVisibilityIndexCached/);
  assert.match(WORKER_SRC, /isPublicMarketplacePartner/);
  assert.match(WORKER_SRC, /isPublicMarketplaceCompanyCode/);
  assert.match(WORKER_SRC, /applyPublicMarketplaceProfileOverlay/);
  assert.match(WORKER_SRC, /loadPublicVisibilityOverride/);
  assert.match(WORKER_SRC, /applyPublicVisibilityOverride/);
  assert.match(WORKER_SRC, /fx-example-badge/);
  assert.match(moduleSrc, /Voorbeeldbedrijf/);
});
