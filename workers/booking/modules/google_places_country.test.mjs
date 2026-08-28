// Stay22 Europe P1B — Google Places country identity.
//
// Run:
//   node --test workers/booking/modules/google_places_country.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import {
  resolveGooglePlacesCountry,
  buildGooglePlacesTextQuery,
  mapGooglePlacesAddressParts,
  formatGooglePlacesLocationParts,
} from "./google_places_country.mjs";

test("explicit ISO takes precedence over a conflicting localized label", () => {
  const resolved = resolveGooglePlacesCountry({
    country_code: "es",
    country: "Duitsland",
  });
  assert.equal(resolved.iso, "ES");
  assert.equal(resolved.englishName, "Spain");
  assert.equal(resolved.source, "explicit_iso");
});

test("invalid ISO is ignored and legacy localized names still map", () => {
  const cases = [
    [{ country_code: "SP", country: "Spanje" }, "ES", "Spain"],
    [{ country_code: "GE", country: "Germany" }, "DE", "Germany"],
    [{ country_code: "DU", country: "Duitsland" }, "DE", "Germany"],
    [{ country_code: "NE", country: "Netherlands" }, "NL", "Netherlands"],
    [{ country_code: "VE", country: "Verenigd Koninkrijk" }, "GB", "United Kingdom"],
    [{ country_code: "PO", country: "Portugal" }, "PT", "Portugal"],
    [{ country_code: "XX", country: "Denmark" }, "DK", "Denmark"],
    [{ country_code: "ESP", country: "Espagne" }, "ES", "Spain"],
    [{ country_code: "d", country: "Belgique" }, "BE", "Belgium"],
  ];
  for (const [query, iso, english] of cases) {
    const resolved = resolveGooglePlacesCountry(query);
    assert.equal(resolved.iso, iso, JSON.stringify(query));
    assert.equal(resolved.englishName, english, JSON.stringify(query));
    assert.equal(resolved.source, "legacy_label", JSON.stringify(query));
  }
});

test("legacy localized names map to the correct ISO and never slice two letters", () => {
  const cases = [
    [["Belgium", "België", "Belgique", "Bélgica"], "BE", "Belgium"],
    [["Netherlands", "Nederland", "Pays-Bas", "Países Bajos"], "NL", "Netherlands"],
    [["Spain", "Spanje", "Espagne", "España"], "ES", "Spain"],
    [["Germany", "Duitsland", "Allemagne", "Alemania"], "DE", "Germany"],
    [["Denmark", "Denemarken", "Danemark", "Dinamarca"], "DK", "Denmark"],
    [["Portugal"], "PT", "Portugal"],
    [["United Kingdom", "Verenigd Koninkrijk", "Royaume-Uni", "Reino Unido"], "GB", "United Kingdom"],
    [["France", "Frankrijk", "Francia"], "FR", "France"],
    [["Luxembourg", "Luxemburg", "Luxemburgo"], "LU", "Luxembourg"],
  ];
  for (const [labels, iso, english] of cases) {
    for (const country of labels) {
      const resolved = resolveGooglePlacesCountry({ country });
      assert.equal(resolved.iso, iso, country);
      assert.equal(resolved.englishName, english, country);
    }
  }
});

test("sliced two-letter mistakes never become the resolved ISO", () => {
  assert.equal(resolveGooglePlacesCountry({ country: "Denmark" }).iso, "DK");
  assert.notEqual(resolveGooglePlacesCountry({ country: "Denmark" }).iso, "DE");
  assert.equal(resolveGooglePlacesCountry({ country: "Spain" }).iso, "ES");
  assert.notEqual(resolveGooglePlacesCountry({ country: "Spain" }).iso, "SP");
  assert.equal(resolveGooglePlacesCountry({ country: "Germany" }).iso, "DE");
  assert.notEqual(resolveGooglePlacesCountry({ country: "Germany" }).iso, "GE");
  assert.equal(resolveGooglePlacesCountry({ country: "Duitsland" }).iso, "DE");
  assert.notEqual(resolveGooglePlacesCountry({ country: "Duitsland" }).iso, "DU");
  assert.equal(resolveGooglePlacesCountry({ country: "Netherlands" }).iso, "NL");
  assert.notEqual(resolveGooglePlacesCountry({ country: "Netherlands" }).iso, "NE");
  assert.equal(resolveGooglePlacesCountry({ country: "Verenigd Koninkrijk" }).iso, "GB");
  assert.notEqual(resolveGooglePlacesCountry({ country: "Verenigd Koninkrijk" }).iso, "VE");
  assert.equal(resolveGooglePlacesCountry({ country: "Portugal" }).iso, "PT");
  assert.notEqual(resolveGooglePlacesCountry({ country: "Portugal" }).iso, "PO");
});

test("canonical English name enters the Google query", () => {
  assert.equal(
    buildGooglePlacesTextQuery({ country_code: "ES" }),
    "hotels in Spain",
  );
  assert.equal(
    buildGooglePlacesTextQuery({ country: "Spanje" }),
    "hotels in Spain",
  );
  assert.equal(
    buildGooglePlacesTextQuery({ country: "Denemarken" }),
    "hotels in Denmark",
  );
  assert.equal(
    buildGooglePlacesTextQuery({
      country_code: "PT",
      destination: "Lisbon",
    }),
    "hotels in Lisbon, Portugal",
  );
  assert.equal(
    buildGooglePlacesTextQuery({
      country_code: "ES",
      city: "Barcelona",
      region: "Catalonia",
    }),
    "hotels in Barcelona, Catalonia, Spain",
  );
  assert.equal(
    buildGooglePlacesTextQuery({
      country_code: "DE",
      region: "Bavaria",
    }),
    "hotels in Bavaria, Germany",
  );
  assert.match(buildGooglePlacesTextQuery({ country: "Spanje" }), /Spain/);
  assert.doesNotMatch(buildGooglePlacesTextQuery({ country: "Spanje" }), /Spanje/);
});

test("response mapping uses validated ISO and does not invent a country city", () => {
  const denmark = mapGooglePlacesAddressParts(
    "Nørrebrogade 1, 2200 København, Denmark",
    { country: "Denemarken" },
  );
  assert.equal(denmark.country, "DK");
  assert.equal(denmark.city, "København");
  assert.notEqual(denmark.city, "Denmark");
  assert.notEqual(denmark.country, "DE");

  const countryOnly = mapGooglePlacesAddressParts("Denmark", {
    country_code: "DK",
  });
  assert.equal(countryOnly.country, "DK");
  assert.equal(countryOnly.city, "");

  const portugal = mapGooglePlacesAddressParts(
    "Rua Augusta 1, 1100-053 Lisboa, Portugal",
    { country: "Portugal" },
  );
  assert.equal(portugal.country, "PT");
  assert.equal(portugal.city, "Lisboa");
});

test("empty address components do not create malformed comma strings", () => {
  assert.equal(
    formatGooglePlacesLocationParts({
      city: "",
      region: "",
      country: "DK",
    }),
    "DK",
  );
  assert.equal(
    formatGooglePlacesLocationParts({
      city: "Lisboa",
      region: "  ",
      country: "PT",
    }),
    "Lisboa, PT",
  );
  assert.doesNotMatch(
    formatGooglePlacesLocationParts({
      city: "Denmark",
      region: "",
      country: "DE",
    }).replace("Denmark, DE", "ok"),
    /,\s*,/,
  );
});

test("worker helpers never perform a live Google request", () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => {
    throw new Error("live_google_must_not_run");
  };
  try {
    resolveGooglePlacesCountry({ country: "Spain" });
    buildGooglePlacesTextQuery({ country_code: "DE", destination: "Berlin" });
    mapGooglePlacesAddressParts("Berlin, Germany", { country_code: "DE" });
    formatGooglePlacesLocationParts({ city: "Berlin", country: "DE" });
  } finally {
    globalThis.fetch = originalFetch;
  }
});
