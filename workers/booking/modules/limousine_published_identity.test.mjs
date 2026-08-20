import { test } from "node:test";
import assert from "node:assert/strict";
import {
  applyPublishedLimousineIdentityToProfile,
  identityScopeMatches,
  mergePublishedLimousineIdentity,
  normalizePublishedLimousineIdentity,
  publicPublishedLimousineIdentityFields,
} from "./limousine_published_identity.mjs";
import {
  mergeLimousinePricingSection,
  normalizeLimousinePricingSection,
} from "./limousine_pricing_resolver.mjs";
import { buildLimousineNearbyCardProjection } from "./limousine_discovery_preview.mjs";
import { applyLimousinePublicFieldsToProfileEntry } from "./limousine_projection.mjs";

const LIMO_LOGO = "https://cdn.example/public-media/t1/c1/limousine/profile-logo.png";
const LIMO_COVER = "https://cdn.example/public-media/t1/c1/limousine/profile-cover.jpg";
const COMPANY_LOGO = "https://cdn.example/public-media/t1/c1/company/logo.png";
const TAXI_HERO = "https://cdn.example/public-media/t1/c1/company/hero.jpg";
const DRAFT_COVER = "https://cdn.example/public-media/t1/c1/limousine/draft-cover.jpg";

const publishedSection = {
  enabled: true,
  currency: "EUR",
  public_title: { nl: "Draft" },
  public_description: { nl: "Draft tekst" },
  limousine_hero: { photo_url: DRAFT_COVER, alignment: "left" },
  published_public_title: { nl: "Party Ride" },
  published_public_description: {
    nl: "Volledige tekst\nmet regeleinden.",
  },
  published_limousine_profile_cover: {
    photo_url: LIMO_COVER,
    alignment: "right",
  },
  published_limousine_profile_logo: { photo_url: LIMO_LOGO },
  tenant_id: "tenant_a",
  company_id: "company_a",
};

test("normalize persists published identity and ignores working drafts", () => {
  const identity = normalizePublishedLimousineIdentity(publishedSection);
  assert.equal(identity.published_public_title.nl, "Party Ride");
  assert.equal(
    identity.published_public_description.nl,
    "Volledige tekst\nmet regeleinden.",
  );
  assert.equal(identity.published_limousine_profile_cover.photo_url, LIMO_COVER);
  assert.equal(identity.published_limousine_profile_cover.alignment, "right");
  assert.equal(identity.published_limousine_profile_logo.photo_url, LIMO_LOGO);
  assert.equal(identity.published_limousine_visiting_card.public_title.nl, "Party Ride");
  assert.notEqual(identity.published_public_title.nl, "Draft");
});

test("pricing section keep-list no longer strips published identity", () => {
  const section = normalizeLimousinePricingSection(publishedSection);
  assert.equal(section.published_public_title.nl, "Party Ride");
  assert.equal(section.published_limousine_profile_logo.photo_url, LIMO_LOGO);
  assert.equal(section.published_limousine_profile_cover.photo_url, LIMO_COVER);
  assert.equal(section.public_title.nl, "Draft");
});

test("working draft never becomes public identity", () => {
  const fields = publicPublishedLimousineIdentityFields({
    public_title: { nl: "Draft" },
    public_description: { nl: "Draft tekst" },
    limousine_hero: { photo_url: DRAFT_COVER },
    limousine_profile_logo: { photo_url: LIMO_LOGO },
  });
  assert.deepEqual(fields, {});
});

test("taxi company media is never stored as the published override", () => {
  const identity = normalizePublishedLimousineIdentity({
    published_limousine_profile_cover: { photo_url: TAXI_HERO },
    published_limousine_profile_logo: { photo_url: COMPANY_LOGO },
    published_public_title: { nl: "Party Ride" },
  });
  assert.equal(identity.published_limousine_profile_cover.photo_url, "");
  assert.equal(identity.published_limousine_profile_logo.photo_url, "");
});

test("profile apply never overwrites taxi media", () => {
  const next = applyPublishedLimousineIdentityToProfile(
    {
      partner_id: "company:tenant_a:company_a",
      company_name: "Fluxidi",
      media: { logo_url: COMPANY_LOGO, hero_photo_url: TAXI_HERO },
      limousine_hero_url: DRAFT_COVER,
    },
    publishedSection,
    { scope: { tenant_id: "tenant_a", company_id: "company_a" } },
  );
  assert.equal(next.media.logo_url, COMPANY_LOGO);
  assert.equal(next.media.hero_photo_url, TAXI_HERO);
  assert.equal(next.published_public_title.nl, "Party Ride");
  assert.equal(next.published_limousine_profile_logo.photo_url, LIMO_LOGO);
  assert.equal(next.limousine_hero_url, LIMO_COVER);
  assert.notEqual(next.limousine_hero_url, DRAFT_COVER);
});

test("nearby card returns the same published identity", () => {
  const profile = applyPublishedLimousineIdentityToProfile(
    {
      partner_id: "company:tenant_a:company_a",
      company_name: "Fluxidi",
      is_active: true,
      bookable: true,
      profile_enabled: true,
      published_at: "2026-08-20T08:00:00Z",
      subscription_status: "active",
      services: ["limousine"],
      limousine_service_enabled: true,
      limousine_available: true,
      limousine_entitled: true,
      vehicles: [
        {
          service_category: "limousine",
          service_class: "stretch_limousine",
          is_active: true,
        },
      ],
      limousine_offers: [
        {
          offer_id: "o1",
          published: true,
          enabled: true,
          price_presentation: "from_price",
          display_amount_cents: 25000,
          currency: "EUR",
        },
      ],
      media: { logo_url: COMPANY_LOGO },
    },
    publishedSection,
  );
  const synced = applyLimousinePublicFieldsToProfileEntry(profile, profile);
  const card = buildLimousineNearbyCardProjection(synced);
  assert.equal(card.published_public_title.nl, "Party Ride");
  assert.equal(card.published_limousine_profile_logo.photo_url, LIMO_LOGO);
  assert.equal(card.published_limousine_profile_cover.photo_url, LIMO_COVER);
  assert.equal(card.logo_url, COMPANY_LOGO);
  assert.equal(card.tenant_id, undefined);
  assert.equal(card.company_id, undefined);
});

test("tenant and company isolation rejects a foreign scope", () => {
  const identity = normalizePublishedLimousineIdentity(publishedSection);
  assert.equal(
    identityScopeMatches(identity, { tenant_id: "tenant_a", company_id: "company_a" }),
    true,
  );
  assert.equal(
    identityScopeMatches(identity, { tenant_id: "other", company_id: "company_a" }),
    false,
  );
});

test("merge keeps stored published identity when the incoming patch omits it", () => {
  const merged = mergeLimousinePricingSection(publishedSection, {
    enabled: true,
    currency: "EUR",
    offers: [],
  });
  assert.equal(merged.published_public_title.nl, "Party Ride");
  assert.equal(merged.published_limousine_profile_logo.photo_url, LIMO_LOGO);
});

test("clearing the published logo restores only the company-logo fallback", () => {
  const cleared = mergePublishedLimousineIdentity(publishedSection, {
    published_limousine_profile_logo: { photo_url: "" },
    published_public_title: { nl: "Party Ride" },
  });
  assert.equal(cleared.published_limousine_profile_logo.photo_url, "");
  const fields = publicPublishedLimousineIdentityFields(cleared);
  assert.equal(fields.limousine_logo_url, undefined);
});
