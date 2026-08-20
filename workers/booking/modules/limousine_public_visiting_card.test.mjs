import { test } from "node:test";
import assert from "node:assert/strict";
import {
  buildLimousinePublicVisitingCard,
  effectiveLimousineLogoUrl,
  logoFallbackMutatesOverride,
  looksLikeTaxiCompanyHero,
} from "./limousine_public_visiting_card.mjs";

const TAXI_HERO =
  "https://cdn.example/public-media/t1/c1/company/hero.jpg?v=1";
const LIMO_COVER =
  "https://cdn.example/public-media/t1/c1/limousine/profile-cover.jpg";
const COMPANY_LOGO = "https://cdn.example/public-media/t1/c1/company/logo.png";
const LIMO_LOGO =
  "https://cdn.example/public-media/t1/c1/limousine/profile-logo.png";

test("published visiting card is atomic and never uses taxi hero", () => {
  assert.equal(looksLikeTaxiCompanyHero(TAXI_HERO), true);
  const card = buildLimousinePublicVisitingCard({
    public_title: { nl: "Draft" },
    public_description: { nl: "Draft tekst" },
    limousine_hero: { photo_url: "https://cdn.example/draft.jpg" },
    published_public_title: { nl: "Fluxidi" },
    published_public_description: { nl: "Voor elke gelegenheid" },
    published_limousine_profile_cover: { photo_url: LIMO_COVER, alignment: "right" },
    published_limousine_profile_logo: { photo_url: LIMO_LOGO },
    hero_photo_url: TAXI_HERO,
    logo_url: COMPANY_LOGO,
  });
  assert.equal(card.published_public_title.nl, "Fluxidi");
  assert.equal(card.published_public_description.nl, "Voor elke gelegenheid");
  assert.equal(card.published_limousine_profile_cover.photo_url, LIMO_COVER);
  assert.equal(card.limousine_hero_url, LIMO_COVER);
  assert.equal(card.limousine_logo_url, LIMO_LOGO);
  assert.notEqual(card.limousine_hero_url, TAXI_HERO);
});

test("taxi hero is stripped from the published cover", () => {
  const card = buildLimousinePublicVisitingCard({
    published_limousine_hero: { photo_url: TAXI_HERO },
    hero_photo_url: TAXI_HERO,
  });
  assert.equal(card.published_limousine_profile_cover.photo_url, "");
  assert.equal(card.limousine_hero_url, undefined);
});

test("published vehicle copy is keyed by vehicle id and ignores draft", () => {
  const card = buildLimousinePublicVisitingCard({
    published_public_title: { nl: "Fluxidi" },
    published_public_description: { nl: "Voor elke gelegenheid" },
    published_limousine_profile_cover: { photo_url: LIMO_COVER },
    limousine_vehicle_public_copy: { vh_party: { nl: "Concepttekst" } },
    published_limousine_vehicle_public_copy: {
      vh_party: { nl: "Party Limo voor een avond uit.", en: "Party Limo for a night out." },
    },
  });
  assert.equal(
    card.published_limousine_vehicle_public_copy.vh_party.nl,
    "Party Limo voor een avond uit.",
  );
  assert.equal(
    card.published_limousine_vehicle_public_copy.vh_party.en,
    "Party Limo for a night out.",
  );
});

test("logo fallback is read-only and never copied into the override", () => {
  const card = buildLimousinePublicVisitingCard({
    published_limousine_profile_logo: { photo_url: "" },
    logo_url: COMPANY_LOGO,
  });
  assert.equal(card.published_limousine_profile_logo.photo_url, "");
  assert.equal(card.limousine_logo_url, COMPANY_LOGO);
  assert.equal(
    logoFallbackMutatesOverride({ photo_url: "" }, COMPANY_LOGO),
    false,
  );
  assert.equal(effectiveLimousineLogoUrl("", COMPANY_LOGO), COMPANY_LOGO);
  assert.equal(effectiveLimousineLogoUrl(LIMO_LOGO, COMPANY_LOGO), LIMO_LOGO);
});
