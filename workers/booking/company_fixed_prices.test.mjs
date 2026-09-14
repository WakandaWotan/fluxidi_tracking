import test from "node:test";
import assert from "node:assert/strict";
import {
  applyCompanyFixedPriceOverflow,
  companyFixedPriceTotalsDiffer,
  evaluateCompanyFixedPriceWrite,
  haversineKm,
  matchCompanyFixedPricesPath,
  mergeCompanyFixedPricesViewSave,
  mergeLegacyAirportFixedFaresSave,
  normalizeCompanyFixedPriceRule,
  normalizeCompanyFixedPricesDocument,
  publicCompanyFixedPricesFromDocument,
  resolveCompanyFixedPriceFromDocument,
  selectBestCompanyFixedPriceRule,
} from "./modules/company_fixed_prices.mjs";

const leuvenRadius = {
  name: "Leuven-straal naar BRU",
  rule_id: "fx_leuven_bru_radius",
  kind: "airport",
  airport_iata: "BRU",
  direction: "to_airport",
  priority: 10,
  rule_version: 1,
  price_incl_vat: 85,
  currency: "EUR",
  origin: {
    type: "radius",
    label: "Leuven kern",
    lat: 50.8798,
    lng: 4.7005,
    radius_km: 8,
  },
  destination: { type: "airport", airport_iata: "BRU", label: "Brussels Airport" },
  overflow_mode: "extra_km",
  overflow_measure: "radius",
  overflow_from: "boundary",
  extra_per_km: 2.1,
};

function doc(rules, fallback = "calculator") {
  return normalizeCompanyFixedPricesDocument({ fallback, rules });
}

test("legacy airport rule still normalizes without origin object", () => {
  const rule = normalizeCompanyFixedPriceRule({
    rule_id: "legacy_bru",
    airport_iata: "BRU",
    direction: "to_airport",
    zone_type: "city",
    zone_value: "Leuven",
    price_incl_vat: 80,
    currency: "EUR",
  });
  assert.equal(rule.kind, "airport");
  assert.equal(rule.airport_iata, "BRU");
  assert.equal(rule.destination.type, "city");
  assert.equal(rule.destination.value, "leuven");
});

test("city pair and airport IATA are stored as identity, not free text", () => {
  const rule = normalizeCompanyFixedPriceRule({
    name: "Leuven naar CDG",
    kind: "city_pair",
    direction: "one_way",
    origin: { type: "city", value: "Leuven" },
    destination: { type: "airport", airport_iata: "CDG", label: "Paris Charles de Gaulle" },
    price_incl_vat: 240,
  });
  assert.equal(rule.destination.airport_iata, "CDG");
  assert.notEqual(rule.destination.airport_iata, "Paris Charles de Gaulle");
});

test("municipality to Belgian airport uses the base fare inside the city", () => {
  const rules = doc([
    {
      name: "Leuven stad naar BRU",
      rule_id: "fx_leuven_bru_city",
      kind: "city_pair",
      direction: "one_way",
      priority: 20,
      origin: { type: "city", value: "Leuven" },
      destination: { type: "airport", airport_iata: "BRU" },
      price_incl_vat: 85,
    },
    leuvenRadius,
  ]);
  const inside = resolveCompanyFixedPriceFromDocument(rules, {
    from: "Leuven station, Leuven",
    from_city: "Leuven",
    to: "Brussels Airport",
    airport_iata: "BRU",
    airport_direction: "to_airport",
  });
  assert.equal(inside.matched, true);
  assert.equal(inside.fixed_fare_rule_id, "fx_leuven_bru_city");
  assert.equal(inside.snapshot.total_incl_vat, 85);
  assert.equal(inside.snapshot.surcharges.length, 0);
});

function lngAtKm(km) {
  const lat = 50.8798;
  const lng0 = 4.7005;
  let lo = 0;
  let hi = 1;
  for (let i = 0; i < 24; i += 1) {
    const mid = (lo + hi) / 2;
    const dist = haversineKm(lat, lng0, lat, lng0 + mid);
    if (dist < km) lo = mid;
    else hi = mid;
  }
  return { lat, lng: lng0 + (lo + hi) / 2 };
}

test("address on and outside a company radius uses company overflow, never a hardcoded 10 km", () => {
  const rules = doc([leuvenRadius]);
  const onEdge = lngAtKm(8);
  const onBoundary = resolveCompanyFixedPriceFromDocument(rules, {
    airport_iata: "BRU",
    airport_direction: "to_airport",
    pickup_lat: onEdge.lat,
    pickup_lng: onEdge.lng,
  });
  assert.equal(onBoundary.matched, true);
  assert.equal(onBoundary.snapshot.total_incl_vat, 85);

  const beyond = lngAtKm(11);
  const outside = resolveCompanyFixedPriceFromDocument(rules, {
    airport_iata: "BRU",
    airport_direction: "to_airport",
    pickup_lat: beyond.lat,
    pickup_lng: beyond.lng,
  });
  assert.equal(outside.matched, true);
  assert.ok(outside.snapshot.surcharges.length > 0);
  assert.ok(outside.snapshot.surcharges[0].amount_incl_vat > 0);
  assert.match(outside.snapshot.surcharges[0].label, /gebiedsgrens/);
  assert.ok(outside.snapshot.total_incl_vat > 85);
});

test("road overflow never uses haversine as road distance", () => {
  const rule = normalizeCompanyFixedPriceRule({
    ...leuvenRadius,
    overflow_measure: "road",
    included_km: 12,
    extra_per_km: 2.5,
  });
  const far = { distance_km: 20, radius_km: 8, inside: false };
  const missingRoad = applyCompanyFixedPriceOverflow(rule, far, {});
  assert.equal(missingRoad.ok, false);
  assert.equal(missingRoad.reason, "road_distance_required");

  const withRoad = applyCompanyFixedPriceOverflow(rule, far, { road_distance_km: 20 });
  assert.equal(withRoad.ok, true);
  assert.equal(withRoad.measure_used, "road");
  assert.equal(withRoad.paying_km, 8);
  assert.notEqual(withRoad.paying_km, haversineKm(50.88, 4.7, 50.9, 4.8));
});

test("higher company priority wins when two rules match", () => {
  const rules = doc([
    {
      rule_id: "fx_low",
      name: "Stad",
      kind: "city_pair",
      direction: "one_way",
      priority: 5,
      origin: { type: "city", value: "Leuven" },
      destination: { type: "airport", airport_iata: "BRU" },
      price_incl_vat: 85,
    },
    {
      rule_id: "fx_high",
      name: "Postcode 3000",
      kind: "city_pair",
      direction: "one_way",
      priority: 30,
      origin: { type: "postcode", value: "3000" },
      destination: { type: "airport", airport_iata: "BRU" },
      price_incl_vat: 80,
    },
  ]);
  const result = resolveCompanyFixedPriceFromDocument(rules, {
    from_city: "Leuven",
    from_postcode: "3000",
    airport_iata: "BRU",
    airport_direction: "to_airport",
  });
  assert.equal(result.fixed_fare_rule_id, "fx_high");
  assert.equal(result.snapshot.total_incl_vat, 80);
  const selected = result.candidates.filter((row) => row.selected);
  assert.equal(selected[0].rule_id, "fx_high");
});

test("no match uses the company fallback and never invents an amount", () => {
  const calc = resolveCompanyFixedPriceFromDocument(doc([], "calculator"), {
    from_city: "Hasselt",
    to_city: "Oostende",
  });
  assert.equal(calc.matched, false);
  assert.equal(calc.fallback, "calculator");
  assert.equal(calc.request_quote_required, false);

  const quote = resolveCompanyFixedPriceFromDocument(doc([], "request_quote"), {
    from_city: "Hasselt",
    to_city: "Oostende",
  });
  assert.equal(quote.matched, false);
  assert.equal(quote.fallback, "request_quote");
  assert.equal(quote.request_quote_required, true);
  assert.equal(quote.snapshot, null);
});

test("city pair both directions keeps one fare and does not double it", () => {
  const rules = doc([
    {
      rule_id: "fx_leuven_gent",
      name: "Leuven-Gent",
      kind: "city_pair",
      direction: "both",
      price_covers: "ride",
      origin: { type: "city", value: "Leuven" },
      destination: { type: "city", value: "Gent" },
      price_incl_vat: 95,
    },
  ]);
  const outbound = resolveCompanyFixedPriceFromDocument(rules, {
    from_city: "Leuven",
    to_city: "Gent",
  });
  const inbound = resolveCompanyFixedPriceFromDocument(rules, {
    from_city: "Gent",
    to_city: "Leuven",
  });
  assert.equal(outbound.snapshot.total_incl_vat, 95);
  assert.equal(inbound.snapshot.total_incl_vat, 95);
  assert.equal(outbound.snapshot.price_covers, "ride");
});

test("changing the live rule does not mutate a stored snapshot", () => {
  const first = resolveCompanyFixedPriceFromDocument(
    doc([{ ...leuvenRadius, price_incl_vat: 85, rule_version: 1 }]),
    {
      airport_iata: "BRU",
      airport_direction: "to_airport",
      pickup_lat: 50.8798,
      pickup_lng: 4.7005,
    },
  );
  const later = resolveCompanyFixedPriceFromDocument(
    doc([{ ...leuvenRadius, price_incl_vat: 99, rule_version: 2 }]),
    {
      airport_iata: "BRU",
      airport_direction: "to_airport",
      pickup_lat: 50.8798,
      pickup_lng: 4.7005,
    },
  );
  assert.equal(first.snapshot.total_incl_vat, 85);
  assert.equal(first.snapshot.rule_version, 1);
  assert.equal(later.snapshot.total_incl_vat, 99);
  assert.equal(true, companyFixedPriceTotalsDiffer(first.snapshot.total_incl_vat, later.snapshot.total_incl_vat));
});

test("European airport outside Belgium matches on IATA", () => {
  const rules = doc([
    {
      rule_id: "fx_bru_cdg",
      name: "Brussel naar CDG",
      kind: "city_pair",
      direction: "one_way",
      origin: { type: "city", value: "Brussel" },
      destination: { type: "airport", airport_iata: "CDG" },
      price_incl_vat: 240,
    },
  ]);
  const hit = resolveCompanyFixedPriceFromDocument(rules, {
    from_city: "Brussel",
    airport_iata: "CDG",
    airport_direction: "to_airport",
  });
  assert.equal(hit.fixed_fare_rule_id, "fx_bru_cdg");
  assert.equal(hit.snapshot.total_incl_vat, 240);
});

// Maarkedal has several postcodes; 9688 is only one of them. The rule must
// stay on that postcode and say what it still needs.
const maarkedalRonse = {
  name: "Vast tarief van Maarkedal naar Ronse",
  rule_id: "fx_maarkedal_ronse",
  kind: "city_pair",
  direction: "one_way",
  price_incl_vat: 35,
  currency: "EUR",
  pax_max: 4,
  tier: "premium",
  origin: {
    type: "postcode",
    value: "9688",
    label: "9688, Maarkedal, Oost-Vlaanderen, België",
  },
  destination: { type: "zone", value: "Ronse", label: "Ronse, Oost-Vlaanderen, België" },
};

test("postcode rule stays on its postcode and asks for a precise origin", () => {
  const rules = doc([maarkedalRonse]);
  const municipality = resolveCompanyFixedPriceFromDocument(rules, {
    from: "Maarkedal, Oost-Vlaanderen, België",
    to: "Ronse, Oost-Vlaanderen, België",
  });
  assert.equal(municipality.matched, false);
  assert.deepEqual(municipality.needs_more_detail, [
    {
      rule_id: "fx_maarkedal_ronse",
      name: "Vast tarief van Maarkedal naar Ronse",
      role: "origin",
      place_type: "postcode",
      value: "9688",
      label: "9688, Maarkedal, Oost-Vlaanderen, België",
    },
  ]);

  const otherPostcode = resolveCompanyFixedPriceFromDocument(rules, {
    from: "9680, Maarkedal, Oost-Vlaanderen, België",
    to: "Ronse, Oost-Vlaanderen, België",
  });
  assert.equal(otherPostcode.matched, false);
  assert.deepEqual(otherPostcode.needs_more_detail, []);

  const precise = resolveCompanyFixedPriceFromDocument(rules, {
    from: "Kerkplein 1, 9688 Maarkedal, Oost-Vlaanderen, België",
    to: "Ronse, Oost-Vlaanderen, België",
  });
  assert.equal(precise.matched, true);
  assert.equal(precise.snapshot.total_incl_vat, 35);
});

test("municipality rule follows the chosen place, not the label text", () => {
  const rules = doc([
    { ...maarkedalRonse, origin: { type: "city", value: "Maarkedal", label: "9688, Maarkedal" } },
  ]);
  for (const from of [
    "Maarkedal, Oost-Vlaanderen, België",
    "9680, Maarkedal, Oost-Vlaanderen, België",
    "Kerkplein 1, 9688 Maarkedal",
  ]) {
    const result = resolveCompanyFixedPriceFromDocument(rules, {
      from,
      to: "Ronse, Oost-Vlaanderen, België",
    });
    assert.equal(result.matched, true, from);
    assert.equal(result.snapshot.total_incl_vat, 35);
  }
});

test("a destination postcode never satisfies an origin postcode rule", () => {
  const rules = doc([{ ...maarkedalRonse, destination: { type: "city", value: "Ronse" } }]);
  const result = resolveCompanyFixedPriceFromDocument(rules, {
    from: "Maarkedal, Oost-Vlaanderen, België",
    to: "9688 Ronse, Oost-Vlaanderen, België",
    to_postcode: "9688",
  });
  assert.equal(result.matched, false);
  assert.equal(result.needs_more_detail[0].role, "origin");
});

test("a neighbouring name is not the municipality", () => {
  const rules = doc([
    {
      ...maarkedalRonse,
      rule_id: "fx_gent_ronse",
      origin: { type: "city", value: "Gent" },
      destination: { type: "city", value: "Ronse" },
    },
  ]);
  const result = resolveCompanyFixedPriceFromDocument(rules, {
    from: "Gentbrugge, Oost-Vlaanderen, België",
    to: "Ronse, Oost-Vlaanderen, België",
  });
  assert.equal(result.matched, false);
});

test("priority helper is visible and stable", () => {
  const winner = selectBestCompanyFixedPriceRule([
    { rule: { rule_id: "b", priority: 1 }, match: { specificity: 4 } },
    { rule: { rule_id: "a", priority: 1 }, match: { specificity: 4 } },
  ]);
  assert.equal(winner.rule.rule_id, "a");
});

test("legacy airport save upserts airport rules and never drops city rules", () => {
  const stored = doc([
    {
      rule_id: "fx_leuven_gent",
      name: "Leuven-Gent",
      kind: "city_pair",
      direction: "both",
      origin: { type: "city", value: "Leuven" },
      destination: { type: "city", value: "Gent" },
      price_incl_vat: 95,
    },
    {
      rule_id: "legacy_bru",
      kind: "airport",
      airport_iata: "BRU",
      direction: "to_airport",
      zone_type: "city",
      zone_value: "Leuven",
      price_incl_vat: 80,
    },
  ]);
  const merged = mergeLegacyAirportFixedFaresSave(stored, {
    expected_updated_at: stored.updated_at,
    rules: [
      {
        rule_id: "legacy_bru",
        airport_iata: "BRU",
        direction: "to_airport",
        zone_type: "city",
        zone_value: "Leuven",
        price_incl_vat: 82,
        currency: "EUR",
        tier: "comfort",
        pax_min: 1,
        pax_max: 8,
        bags_max: 4,
      },
    ],
  });
  assert.equal(merged.ok, true);
  const ids = merged.document.rules.map((rule) => rule.rule_id).sort();
  assert.deepEqual(ids, ["fx_leuven_gent", "legacy_bru"]);
  assert.equal(
    merged.document.rules.find((rule) => rule.rule_id === "fx_leuven_gent").price_incl_vat,
    95,
  );
  assert.equal(
    merged.document.rules.find((rule) => rule.rule_id === "legacy_bru").price_incl_vat,
    82,
  );
});

test("stale legacy airport save is rejected", () => {
  const stored = doc([
    {
      rule_id: "fx_leuven_gent",
      kind: "city_pair",
      origin: { type: "city", value: "Leuven" },
      destination: { type: "city", value: "Gent" },
      price_incl_vat: 95,
    },
  ]);
  const stale = mergeLegacyAirportFixedFaresSave(stored, {
    expected_updated_at: "2020-01-01T00:00:00.000Z",
    rules: [],
  });
  assert.equal(stale.ok, false);
  assert.equal(stale.error, "stale_fixed_prices");
  assert.equal(stale.document.rules[0].rule_id, "fx_leuven_gent");
});

test("city view save keeps airport rules and airport view keeps city rules", () => {
  const stored = doc([
    {
      rule_id: "fx_leuven_gent",
      name: "Leuven-Gent",
      kind: "city_pair",
      direction: "both",
      origin: { type: "city", value: "Leuven" },
      destination: { type: "city", value: "Gent" },
      price_incl_vat: 95,
    },
    {
      rule_id: "fx_leuven_bru",
      name: "Leuven-BRU",
      kind: "airport",
      airport_iata: "BRU",
      direction: "to_airport",
      origin: { type: "city", value: "Leuven" },
      destination: { type: "airport", airport_iata: "BRU" },
      price_incl_vat: 85,
    },
  ]);
  const cityOnly = mergeCompanyFixedPricesViewSave(
    stored,
    {
      expected_updated_at: stored.updated_at,
      rules: [
        {
          rule_id: "fx_ruien_oudenaarde",
          name: "Ruien-Oudenaarde",
          kind: "city_pair",
          direction: "both",
          origin: { type: "city", value: "Ruien" },
          destination: { type: "city", value: "Oudenaarde" },
          price_incl_vat: 47,
        },
      ],
    },
    "city",
  );
  assert.equal(cityOnly.ok, true);
  assert.deepEqual(
    cityOnly.document.rules.map((rule) => rule.rule_id).sort(),
    ["fx_leuven_bru", "fx_ruien_oudenaarde"],
  );
  const airportStaleForm = mergeCompanyFixedPricesViewSave(
    stored,
    {
      expected_updated_at: stored.updated_at,
      rules: [
        {
          rule_id: "fx_leuven_bru",
          name: "Leuven-BRU",
          kind: "airport",
          airport_iata: "BRU",
          direction: "to_airport",
          origin: { type: "city", value: "Leuven" },
          destination: { type: "airport", airport_iata: "BRU" },
          price_incl_vat: 85,
        },
      ],
    },
    "airport",
  );
  assert.equal(airportStaleForm.ok, true);
  assert.ok(
    airportStaleForm.document.rules.some((rule) => rule.rule_id === "fx_leuven_gent"),
  );
  const stale = mergeCompanyFixedPricesViewSave(
    stored,
    { expected_updated_at: "2020-01-01T00:00:00.000Z", rules: [] },
    "city",
  );
  assert.equal(stale.ok, false);
  assert.equal(stale.error, "stale_fixed_prices");
});

test("plan-ride write revalidates a preview and keeps a locked quote", () => {
  const live = resolveCompanyFixedPriceFromDocument(
    doc([{ ...leuvenRadius, price_incl_vat: 99, rule_version: 2 }]),
    {
      airport_iata: "BRU",
      airport_direction: "to_airport",
      pickup_lat: 50.8798,
      pickup_lng: 4.7005,
    },
  );
  const changed = evaluateCompanyFixedPriceWrite({
    live,
    quotedSnapshot: { fixed_fare_rule_id: "fx_leuven_bru_radius", total_incl_vat: 85 },
  });
  assert.equal(changed.ok, false);
  assert.equal(changed.error, "price_changed");
  const locked = evaluateCompanyFixedPriceWrite({
    live,
    quotedSnapshot: { fixed_fare_rule_id: "fx_leuven_bru_radius", total_incl_vat: 85 },
    lockedQuotePrice: true,
  });
  assert.equal(locked.ok, true);
  assert.equal(locked.apply.total_incl_vat, 85);
});

test("only fares the company published reach the public profile", () => {
  const published = publicCompanyFixedPricesFromDocument(
    doc([
      { ...leuvenRadius, public_visible: true },
      {
        ...leuvenRadius,
        rule_id: "fx_private_airport",
        name: "Niet gepubliceerd",
        public_visible: false,
      },
      {
        ...leuvenRadius,
        rule_id: "fx_public_but_off",
        name: "Publiek maar uitgeschakeld",
        public_visible: true,
        enabled: false,
      },
      {
        rule_id: "fx_maarkedal_ronse",
        name: "Vast tarief van Maarkedal naar Ronse",
        kind: "city_pair",
        direction: "one_way",
        price_incl_vat: 35,
        currency: "EUR",
        tier: "premium",
        pax_min: 1,
        pax_max: 4,
        public_visible: true,
        origin: { type: "postcode", value: "9688", label: "9688, Maarkedal" },
        destination: { type: "zone", value: "Ronse", label: "Ronse" },
      },
      {
        rule_id: "fx_expired_city",
        name: "Verlopen",
        kind: "city_pair",
        direction: "one_way",
        price_incl_vat: 30,
        currency: "EUR",
        public_visible: true,
        active_until: "2020-01-01T00:00:00.000Z",
        origin: { type: "city", value: "Gent" },
        destination: { type: "city", value: "Brugge" },
      },
    ]),
  );
  assert.deepEqual(
    published.airport.map((entry) => entry.rule_id),
    ["fx_leuven_bru_radius"],
  );
  assert.deepEqual(
    published.city.map((entry) => entry.rule_id),
    ["fx_maarkedal_ronse"],
  );
  assert.equal(published.total, 2);
  assert.equal(published.fallback, "calculator");
});

test("a published fare carries amount, conditions and area surcharge", () => {
  const published = publicCompanyFixedPricesFromDocument(
    doc([
      {
        rule_id: "fx_maarkedal_ronse",
        name: "Vast tarief van Maarkedal naar Ronse",
        kind: "city_pair",
        direction: "one_way",
        price_incl_vat: 35,
        currency: "EUR",
        tier: "premium",
        pax_min: 1,
        pax_max: 4,
        bags_max: 3,
        public_visible: true,
        price_covers: "ride",
        overflow_mode: "zone_surcharge",
        overflow_surcharge: 10,
        includes: { wait: true, bags: false, extras: false, note: "" },
        origin: { type: "postcode", value: "9688", label: "9688, Maarkedal" },
        destination: { type: "zone", value: "Ronse", label: "Ronse" },
      },
    ]),
  );
  const [entry] = published.city;
  assert.equal(entry.origin.label, "9688, Maarkedal");
  assert.equal(entry.destination.label, "Ronse");
  assert.equal(entry.price_incl_vat, 35);
  assert.equal(entry.vat_rate, 0.06);
  assert.equal(entry.price_ex_vat, 33.02);
  assert.equal(entry.price_vat, 1.98);
  assert.equal(entry.price_covers, "ride");
  assert.equal(entry.direction, "one_way");
  assert.equal(entry.tier, "premium");
  assert.equal(entry.pax_max, 4);
  assert.equal(entry.bags_max, 3);
  assert.equal(entry.includes.wait, true);
  assert.equal(entry.zone_surcharge, 10);
  assert.equal(entry.rule_version, 1);
  // Area fares have no pin; 0,0 would drop a customer in the ocean.
  assert.equal(entry.origin.lat, null);
  assert.equal(entry.origin.lng, null);
});

test("company routes stay on the existing company path", () => {
  assert.equal(matchCompanyFixedPricesPath("/company/fixed-prices")?.kind, "list");
  assert.equal(matchCompanyFixedPricesPath("/company/fixed-prices/preview")?.kind, "preview");
  assert.equal(matchCompanyFixedPricesPath("/company/customers"), null);
});
