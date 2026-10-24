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
  brusselsWallClockToUtcMs,
  resolveCompanyFixedPriceFromDocument,
  resolveReturnPackageFromDocument,
  selectBestCompanyFixedPriceRule,
  airportAutoCalcOutsideFixedFaresEnabled,
  airportFixedFareMinLeadHours,
  airportBookingAdvanceRefusal,
  profileDeclaresAirportFixedFareMinLeadHours,
  refuseAirportBookingWithoutAllowedFare,
  AIRPORT_NO_FIXED_FARE_REASON,
  AIRPORT_NO_FIXED_FARE_PRICE_LABEL,
} from "../../candidate/source-closure/retained-source/workers/booking/modules/company_fixed_prices.mjs";
import { assessPassengerSeatCapacity } from "../../candidate/source-closure/retained-source/workers/booking/modules/passenger_seat_capacity.mjs";

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

function airportRule(partial) {
  return {
    kind: "airport",
    airport_iata: "BRU",
    tier: "comfort",
    enabled: true,
    public_visible: false,
    pax_min: 1,
    pax_max: 3,
    zone_type: "city",
    currency: "EUR",
    price_covers: "ride",
    ...partial,
  };
}

test('selected airport customer postcode excludes contradictory hints from fixed-rule matching', () => {
  for (const direction of ['to_airport', 'from_airport']) {
    const priced = doc(['9100', '9688'].map((postcode) => airportRule({
      rule_id: `fixture_${postcode}_${direction}`, direction, zone_type: 'postcode', zone_value: postcode,
      // Both fixtures reuse the existing test amount; identity, not money, is
      // under test. Stale hint deliberately has the otherwise winning priority.
      price_incl_vat: 115, priority: postcode === '9688' ? 100 : 10,
    })));
    const returning = direction === 'from_airport';
    const result = resolveCompanyFixedPriceFromDocument(priced, {
      service: 'airport', tier: 'comfort', airport_iata: 'BRU', airport_direction: direction,
      from: returning ? 'Brussels Airport, 1930 Zaventem, BE' : 'Grote Markt 1, 9100 Sint-Niklaas, BE',
      to: returning ? 'Grote Markt 1, 9100 Sint-Niklaas, BE' : 'Brussels Airport, 1930 Zaventem, BE',
      ...(returning ? { to_postcode: '9688' } : { from_postcode: '9688' }),
      postcode: '9688', pax: 1,
    });
    assert.equal(result.fixed_fare_rule_id, `fixture_9100_${direction}`);
  }
});

test('selected Dutch postcode retains its full suffix in either airport direction and label format', () => {
  for (const direction of ['to_airport', 'from_airport']) {
    for (const label of ['1012 AB', '1012AB']) {
      const priced = doc(['1012AB', '2011CD'].map((postcode) => airportRule({
        rule_id: `fixture_${postcode}_${direction}`, airport_iata: 'AMS', direction,
        zone_type: 'postcode', zone_value: postcode, price_incl_vat: 115,
        priority: postcode === '2011CD' ? 100 : 10,
      })));
      const returning = direction === 'from_airport';
      const selected = `Dam 1, ${label} Amsterdam, NL`;
      const result = resolveCompanyFixedPriceFromDocument(priced, {
        service: 'airport', tier: 'comfort', airport_iata: 'AMS', airport_direction: direction,
        from: returning ? 'Schiphol Airport (AMS)' : selected,
        to: returning ? selected : 'Schiphol Airport (AMS)',
        ...(returning ? { to_postcode: '2011CD' } : { from_postcode: '2011CD' }),
        postcode: '2011CD', pax: 1,
      });
      assert.equal(result.fixed_fare_rule_id, `fixture_1012AB_${direction}`, `${direction}/${label}`);
    }
  }
});

test("return package is not charged on a one-way and replaces the sum on a return", () => {
  const rules = doc([
    airportRule({
      rule_id: "sn_to",
      direction: "to_airport",
      zone_value: "Sint-Niklaas",
      price_incl_vat: 115,
      outside_pax: "no_price",
    }),
    airportRule({
      rule_id: "sn_from",
      direction: "from_airport",
      zone_value: "Sint-Niklaas",
      price_incl_vat: 120,
      outside_pax: "no_price",
    }),
    airportRule({
      rule_id: "sn_return",
      direction: "return_package",
      zone_value: "Sint-Niklaas",
      price_incl_vat: 215,
      price_covers: "return_package",
      outside_pax: "no_price",
    }),
  ]);
  const oneWay = resolveCompanyFixedPriceFromDocument(rules, {
    from: "Grote Markt 1, 9100 Sint-Niklaas, Belgium",
    to: "Brussels Airport, Zaventem, Belgium",
    airport_iata: "BRU",
    airport_direction: "to_airport",
    pax: 2,
    tier: "comfort",
  });
  assert.equal(oneWay.fixed_fare_rule_id, "sn_to");
  assert.equal(oneWay.snapshot.total_incl_vat, 115);
  assert.equal(oneWay.snapshot.price_covers, "ride");
  const oneWayPackage = resolveReturnPackageFromDocument(rules, {
    from: "Grote Markt 1, 9100 Sint-Niklaas, Belgium",
    to: "Brussels Airport, Zaventem, Belgium",
    airport_iata: "BRU",
    airport_direction: "to_airport",
    pax: 2,
  });
  assert.equal(oneWayPackage.matched, false);

  const roundTrip = resolveReturnPackageFromDocument(rules, {
    from: "Grote Markt 1, 9100 Sint-Niklaas, Belgium",
    to: "Brussels Airport, Zaventem, Belgium",
    airport_iata: "BRU",
    airport_direction: "to_airport",
    return_enabled: true,
    pax: 2,
    tier: "comfort",
  });
  assert.equal(roundTrip.matched, true);
  assert.equal(roundTrip.fixed_fare_rule_id, "sn_return");
  assert.equal(roundTrip.pricing.price_incl_vat, 215);
  assert.equal(roundTrip.price_covers, "return_package");
  assert.notEqual(roundTrip.pricing.price_incl_vat, 115 + 120);
});

test("shared postcode keeps De Klinge and Sint-Gillis-Waas on different fares", () => {
  const rules = doc([
    airportRule({
      rule_id: "klinge_to",
      direction: "to_airport",
      zone_value: "De Klinge",
      price_incl_vat: 125,
    }),
    airportRule({
      rule_id: "sgw_to",
      direction: "to_airport",
      zone_value: "Sint-Gillis-Waas",
      price_incl_vat: 115,
    }),
  ]);
  const klinge = resolveCompanyFixedPriceFromDocument(rules, {
    from: "Dorp 2, 9170 De Klinge, Belgium",
    to: "Brussels Airport",
    airport_iata: "BRU",
    airport_direction: "to_airport",
    pax: 2,
    tier: "comfort",
  });
  const sgw = resolveCompanyFixedPriceFromDocument(rules, {
    from: "Kerkstraat 3, 9170 Sint-Gillis-Waas, Belgium",
    to: "Brussels Airport",
    airport_iata: "BRU",
    airport_direction: "to_airport",
    pax: 2,
    tier: "comfort",
  });
  assert.equal(klinge.fixed_fare_rule_id, "klinge_to");
  assert.equal(klinge.snapshot.total_incl_vat, 125);
  assert.equal(sgw.fixed_fare_rule_id, "sgw_to");
  assert.equal(sgw.snapshot.total_incl_vat, 115);
});

test("passengers outside 1-3 do not fall through to a calculator price", () => {
  const rules = doc([
    airportRule({
      rule_id: "sn_to",
      direction: "to_airport",
      zone_value: "Sint-Niklaas",
      price_incl_vat: 115,
      outside_pax: "no_price",
    }),
  ]);
  const six = resolveCompanyFixedPriceFromDocument(rules, {
    from: "Grote Markt 1, 9100 Sint-Niklaas, Belgium",
    to: "Brussels Airport",
    airport_iata: "BRU",
    airport_direction: "to_airport",
    pax: 6,
    tier: "comfort",
  });
  assert.equal(six.matched, false);
  assert.equal(six.block_calculator, true);
  assert.equal(six.reason, "pax_not_covered");
  assert.equal(six.snapshot, null);
  assert.equal(six.pricing, null);

  const elsewhere = resolveCompanyFixedPriceFromDocument(rules, {
    from: "Korenmarkt 1, 9000 Gent, Belgium",
    to: "Brussels Airport",
    airport_iata: "BRU",
    airport_direction: "to_airport",
    pax: 2,
    tier: "comfort",
  });
  assert.equal(elsewhere.matched, false);
  assert.equal(elsewhere.block_calculator, undefined);
  assert.equal(elsewhere.pricing_source, "route_calc");
});

test("a company without a return package still prices one way only", () => {
  const rules = doc([
    airportRule({
      rule_id: "other_to",
      direction: "to_airport",
      zone_value: "Leuven",
      price_incl_vat: 80,
    }),
    airportRule({
      rule_id: "other_from",
      direction: "from_airport",
      zone_value: "Leuven",
      price_incl_vat: 90,
    }),
  ]);
  const outbound = resolveCompanyFixedPriceFromDocument(rules, {
    from: "Bondgenotenlaan 1, Leuven, Belgium",
    to: "Brussels Airport",
    airport_iata: "BRU",
    airport_direction: "to_airport",
    return_enabled: true,
    pax: 2,
    tier: "comfort",
  });
  const packagePrice = resolveReturnPackageFromDocument(rules, {
    from: "Bondgenotenlaan 1, Leuven, Belgium",
    to: "Brussels Airport",
    airport_iata: "BRU",
    airport_direction: "to_airport",
    return_enabled: true,
    pax: 2,
    tier: "comfort",
  });
  assert.equal(outbound.fixed_fare_rule_id, "other_to");
  assert.equal(outbound.snapshot.total_incl_vat, 80);
  assert.equal(outbound.snapshot.price_covers, "ride");
  assert.equal(packagePrice.matched, false);
});

test("eight passengers are not reduced to the largest vehicle", () => {
  const seat = assessPassengerSeatCapacity([
    { vehicle_id: "vito", is_active: true, passenger_capacity: 7 },
    { vehicle_id: "car", is_active: true, passenger_capacity: 4 },
    { vehicle_id: "default_company_vehicle", is_active: true, passenger_capacity: 99 },
  ], 8);
  assert.equal(seat.exceeded, true);
  assert.equal(seat.requested_pax, 8);
  assert.equal(seat.passenger_count_adjusted, false);
  assert.equal(seat.max_passenger_capacity, 7);
  const six = assessPassengerSeatCapacity([
    { vehicle_id: "vito", is_active: true, passenger_capacity: 7 },
  ], 6);
  assert.equal(six.exceeded, false);
  assert.equal(six.requested_pax, 6);
});

test("postcode only does not become the Sint-Niklaas city rule", () => {
  const priced = normalizeCompanyFixedPricesDocument({
    fallback: "route_calc",
    pending_price_conditions: {
      lead_time_hours: 48,
      invoice_terms_missing: true,
    },
    rules: [
      airportRule({
        rule_id: "sn_to",
        direction: "to_airport",
        zone_value: "Sint-Niklaas",
        price_incl_vat: 115,
        outside_pax: "no_price",
      }),
      airportRule({
        rule_id: "sn_return",
        direction: "return_package",
        zone_value: "Sint-Niklaas",
        price_incl_vat: 215,
        price_covers: "return_package",
        outside_pax: "no_price",
      }),
    ],
  });
  const nowMs = Date.parse("2026-09-23T15:33:00.000Z");
  const shared = {
    service: "airport",
    tier: "comfort",
    airport_iata: "BRU",
    airport_direction: "to_airport",
    to: "Brussels Airport (BRU)",
    from_postcode: "9100",
    fixed_fare_zone_type: "postcode",
    fixed_fare_zone_value: "9100",
    passengers: 1,
    bags: 0,
    date: "2026-09-25",
    time: "18:32",
  };
  const bare = resolveCompanyFixedPriceFromDocument(priced, {
    ...shared,
    from: "9100",
  }, { nowMs });
  assert.equal(bare.matched, false);
  assert.equal(bare.reason, "pickup_address_required");
  assert.equal(bare.block_calculator, true);
  assert.equal(bare.pricing, null);
  assert.equal(bare.fixed_fare_rule_id, null);
  assert.equal(bare.request_quote_required, true);

  const full = resolveCompanyFixedPriceFromDocument(priced, {
    ...shared,
    from: "Grote Markt 1, 9100 Sint-Niklaas",
  }, { nowMs });
  assert.equal(full.matched, true);
  assert.equal(full.fixed_fare_rule_id, "sn_to");
  assert.equal(full.pricing_source, "airport_fixed_fare");
  assert.equal(full.pricing.price_incl_vat, 115);

  const gent = resolveCompanyFixedPriceFromDocument(priced, {
    ...shared,
    from: "Korenmarkt 1, 9000 Gent",
    from_postcode: "9000",
    fixed_fare_zone_value: "9000",
  }, { nowMs });
  assert.equal(gent.matched, false);
  assert.equal(gent.pricing_source, "route_calc");
  assert.notEqual(gent.reason, "pickup_address_required");

  const six = resolveCompanyFixedPriceFromDocument(priced, {
    ...shared,
    from: "Grote Markt 1, 9100 Sint-Niklaas",
    passengers: 6,
  }, { nowMs });
  assert.equal(six.reason, "pax_not_covered");
  assert.equal(six.pricing, null);
});

test("unconfirmed lead time and invoice terms stay on request instead of a bookable price", () => {
  const base = doc([
    airportRule({
      rule_id: "sn_to",
      direction: "to_airport",
      zone_value: "Sint-Niklaas",
      price_incl_vat: 115,
      outside_pax: "no_price",
    }),
    airportRule({
      rule_id: "sn_return",
      direction: "return_package",
      zone_value: "Sint-Niklaas",
      price_incl_vat: 215,
      price_covers: "return_package",
      outside_pax: "no_price",
    }),
  ]);
  const priced = normalizeCompanyFixedPricesDocument({
    ...base,
    pending_price_conditions: {
      lead_time_hours: 48,
      invoice_terms_missing: true,
    },
  });
  const ride = {
    from: "Grote Markt 1, 9100 Sint-Niklaas, Belgium",
    to: "Brussels Airport",
    airport_iata: "BRU",
    airport_direction: "to_airport",
    pax: 2,
    tier: "comfort",
    date: "2026-09-24",
    time: "10:00",
  };
  const pickupMs = brusselsWallClockToUtcMs(ride.date, ride.time);
  const soon = resolveCompanyFixedPriceFromDocument(priced, ride, {
    nowMs: pickupMs - (47 * 60 * 60 * 1000),
  });
  assert.equal(soon.block_calculator, true);
  assert.equal(soon.request_quote_required, true);
  assert.equal(soon.message, "Prijs op aanvraag");
  assert.equal(soon.pricing, null);
  assert.equal(soon.snapshot, null);
  assert.ok(soon.conditions.includes("lead_time"));

  const onTime = resolveCompanyFixedPriceFromDocument(priced, ride, {
    nowMs: pickupMs - (48 * 60 * 60 * 1000),
  });
  assert.equal(onTime.fixed_fare_rule_id, "sn_to");
  assert.equal(onTime.snapshot.total_incl_vat, 115);

  const invoice = resolveCompanyFixedPriceFromDocument(priced, {
    ...ride,
    invoice_requested: true,
  }, {
    nowMs: pickupMs - (72 * 60 * 60 * 1000),
  });
  assert.equal(invoice.message, "Prijs op aanvraag");
  assert.equal(invoice.pricing, null);
  assert.deepEqual(invoice.conditions, ["invoice"]);

  const six = resolveCompanyFixedPriceFromDocument(priced, {
    ...ride,
    pax: 6,
  }, {
    nowMs: pickupMs - (2 * 60 * 60 * 1000),
  });
  assert.equal(six.reason, "pax_not_covered");
  assert.equal(six.pricing, null);

  const untouched = resolveCompanyFixedPriceFromDocument(base, ride, {
    nowMs: pickupMs - (2 * 60 * 60 * 1000),
  });
  assert.equal(untouched.snapshot.total_incl_vat, 115);

  const soonReturn = resolveReturnPackageFromDocument(priced, {
    ...ride,
    return_enabled: true,
  }, {
    nowMs: pickupMs - (2 * 60 * 60 * 1000),
  });
  assert.equal(soonReturn.matched, false);
  assert.equal(soonReturn.message, "Prijs op aanvraag");
  assert.equal(soonReturn.pricing, null);

  const kept = mergeLegacyAirportFixedFaresSave(priced, { rules: [] });
  assert.equal(kept.ok, true);
  assert.equal(kept.document.pending_price_conditions.lead_time_hours, 48);
  assert.equal(kept.document.pending_price_conditions.invoice_terms_missing, true);
  assert.equal(kept.document.rules.length, 2);
});

test("East Flanders Beveren uses the Beveren-Waas rules and other Beverens do not", () => {
  const rules = doc([
    airportRule({ rule_id: "bw_to", direction: "to_airport", zone_value: "Beveren-Waas", price_incl_vat: 115 }),
    airportRule({ rule_id: "bw_from", direction: "from_airport", zone_value: "Beveren-Waas", price_incl_vat: 120 }),
    airportRule({
      rule_id: "bw_return",
      direction: "return_package",
      zone_value: "Beveren-Waas",
      price_incl_vat: 230,
      price_covers: "return_package",
    }),
    airportRule({ rule_id: "haasdonk_to", direction: "to_airport", zone_value: "Haasdonk", price_incl_vat: 115 }),
    airportRule({ rule_id: "vrasene_to", direction: "to_airport", zone_value: "Vrasene", price_incl_vat: 115 }),
  ]);
  const street = {
    from: "Grote Markt, 9120 Beveren, Oost-Vlaanderen, België",
    to: "Brussels Airport, Zaventem, Belgium",
    airport_iata: "BRU",
    airport_direction: "to_airport",
    from_lat: 51.213426,
    from_lng: 4.256442,
    pax: 1,
    tier: "comfort",
  };
  const toAirport = resolveCompanyFixedPriceFromDocument(rules, street);
  assert.equal(toAirport.fixed_fare_rule_id, "bw_to");
  assert.equal(toAirport.snapshot.total_incl_vat, 115);
  const fromAirport = resolveCompanyFixedPriceFromDocument(rules, {
    from: "Brussels Airport, Zaventem, Belgium",
    to: street.from,
    airport_iata: "BRU",
    airport_direction: "from_airport",
    to_lat: 51.213426,
    to_lng: 4.256442,
    pax: 1,
    tier: "comfort",
  });
  assert.equal(fromAirport.fixed_fare_rule_id, "bw_from");
  assert.equal(fromAirport.snapshot.total_incl_vat, 120);
  const roundTrip = resolveReturnPackageFromDocument(rules, {
    ...street,
    return_enabled: true,
  });
  assert.equal(roundTrip.fixed_fare_rule_id, "bw_return");
  assert.equal(roundTrip.pricing.price_incl_vat, 230);
  const place = resolveCompanyFixedPriceFromDocument(rules, {
    ...street,
    from: "Beveren, Oost-Vlaanderen, België",
    from_lat: 51.212611,
    from_lng: 4.257781,
  });
  assert.equal(place.fixed_fare_rule_id, "bw_to");
  const haasdonk = resolveCompanyFixedPriceFromDocument(rules, {
    ...street,
    from: "Haasdonk, Beveren, Oost-Vlaanderen, België",
    from_lat: 51.18103,
    from_lng: 4.237839,
  });
  assert.equal(haasdonk.fixed_fare_rule_id, "haasdonk_to");
  const vrasene = resolveCompanyFixedPriceFromDocument(rules, {
    ...street,
    from: "Vrasene, Beveren, Oost-Vlaanderen, België",
    from_lat: 51.219315,
    from_lng: 4.194562,
  });
  assert.equal(vrasene.fixed_fare_rule_id, "vrasene_to");
  const waregem = resolveCompanyFixedPriceFromDocument(rules, {
    ...street,
    from: "Beveren, Waregem, West-Vlaanderen, België",
    from_lat: 50.874905,
    from_lng: 3.345463,
  });
  assert.equal(waregem.matched, false);
  const ijzer = resolveCompanyFixedPriceFromDocument(rules, {
    ...street,
    from: "Beveren-aan-de-IJzer, Alveringem, West-Vlaanderen, België",
    from_lat: 50.939198,
    from_lng: 2.639811,
  });
  assert.equal(ijzer.matched, false);
  const bare = resolveCompanyFixedPriceFromDocument(rules, {
    ...street,
    from: "Beveren",
    from_lat: null,
    from_lng: null,
  });
  assert.equal(bare.matched, false);
});

test("a deelgemeente outranks its parent municipality at the same priority", () => {
  const rules = doc([
    airportRule({ rule_id: "tm_bru_sint_gillis_waas_to", direction: "to_airport", zone_value: "Sint-Gillis-Waas", price_incl_vat: 115 }),
    airportRule({ rule_id: "tm_bru_sint_pauwels_to", direction: "to_airport", zone_value: "Sint-Pauwels", price_incl_vat: 115 }),
    airportRule({ rule_id: "tm_bru_sint_gillis_waas_from", direction: "from_airport", zone_value: "Sint-Gillis-Waas", price_incl_vat: 120 }),
    airportRule({ rule_id: "tm_bru_sint_pauwels_from", direction: "from_airport", zone_value: "Sint-Pauwels", price_incl_vat: 120 }),
    airportRule({
      rule_id: "tm_bru_sint_gillis_waas_return",
      direction: "return_package",
      zone_value: "Sint-Gillis-Waas",
      price_incl_vat: 230,
      price_covers: "return_package",
    }),
    airportRule({
      rule_id: "tm_bru_sint_pauwels_return",
      direction: "return_package",
      zone_value: "Sint-Pauwels",
      price_incl_vat: 230,
      price_covers: "return_package",
    }),
    airportRule({ rule_id: "tm_bru_sint_niklaas_to", direction: "to_airport", zone_value: "Sint-Niklaas", price_incl_vat: 115 }),
  ]);
  const pauwels = {
    from: "Sint-Pauwels, Sint-Gillis-Waas, Oost-Vlaanderen, België",
    to: "Brussels Airport, Zaventem, Belgium",
    airport_iata: "BRU",
    airport_direction: "to_airport",
    from_lat: 51.193905,
    from_lng: 4.095881,
    pax: 1,
    tier: "comfort",
  };
  assert.equal(resolveCompanyFixedPriceFromDocument(rules, pauwels).fixed_fare_rule_id, "tm_bru_sint_pauwels_to");
  assert.equal(resolveCompanyFixedPriceFromDocument(rules, {
    from: "Brussels Airport, Zaventem, Belgium",
    to: pauwels.from,
    airport_iata: "BRU",
    airport_direction: "from_airport",
    to_lat: 51.193905,
    to_lng: 4.095881,
    pax: 1,
    tier: "comfort",
  }).fixed_fare_rule_id, "tm_bru_sint_pauwels_from");
  assert.equal(resolveReturnPackageFromDocument(rules, {
    ...pauwels,
    return_enabled: true,
  }).fixed_fare_rule_id, "tm_bru_sint_pauwels_return");
  assert.equal(resolveCompanyFixedPriceFromDocument(rules, {
    ...pauwels,
    from: "Sint-Gillis-Waas, Oost-Vlaanderen, België",
    from_lat: 51.21799,
    from_lng: 4.12861,
  }).fixed_fare_rule_id, "tm_bru_sint_gillis_waas_to");
  const hamlet = resolveCompanyFixedPriceFromDocument(rules, {
    ...pauwels,
    from: "Sint Niklaaswijk, 1880 Kapelle-op-den-Bos, Vlaams-Brabant, België",
    from_lat: 51.007126,
    from_lng: 4.35422,
  });
  assert.equal(hamlet.matched, false);
  assert.notEqual(hamlet.fixed_fare_rule_id, "tm_bru_sint_niklaas_to");
});

test("airport calculator switch keeps fixed fares and only blocks airport fallback", () => {
  const rates = [
    ["Bazel", 115, 120, 230],
    ["Belsele", 115, 120, 230],
    ["Beveren-Waas", 115, 120, 230],
    ["Bornem", 115, 120, 230],
    ["Burcht", 115, 120, 230],
    ["De Klinge", 125, 130, 250],
    ["Haasdonk", 115, 120, 230],
    ["Hamme", 125, 130, 250],
    ["Kallo", 125, 130, 250],
    ["Kemzeke", 125, 130, 250],
    ["Kieldrecht", 125, 130, 250],
    ["Kruibeke", 115, 120, 230],
    ["Meerdonk", 125, 130, 250],
    ["Melsele", 115, 120, 230],
    ["Sint-Gillis-Waas", 115, 120, 230],
    ["Sint-Niklaas", 115, 120, 215],
    ["Temse", 115, 120, 215],
    ["Sint-Pauwels", 115, 120, 230],
    ["Steendorp", 115, 120, 230],
    ["Stekene", 125, 130, 250],
    ["Verrebroek", 125, 130, 250],
    ["Waasmunster", 115, 120, 230],
    ["Sinaai", 125, 130, 250],
    ["Vrasene", 115, 120, 230],
  ];
  const places = {
    Bazel: ["Bazel, Kruibeke, Oost-Vlaanderen, België", 51.147526, 4.298447],
    Belsele: ["Belsele, Sint-Niklaas, Oost-Vlaanderen, België", 51.14633, 4.088415],
    "Beveren-Waas": ["Grote Markt, 9120 Beveren, Oost-Vlaanderen, België", 51.213426, 4.256442],
    Bornem: ["Bornem, Provincie Antwerpen, België", 51.095301, 4.234131],
    Burcht: ["Burcht, Zwijndrecht, Provincie Antwerpen, België", 51.202145, 4.341332],
    "De Klinge": ["De Klinge, Sint-Gillis-Waas, Oost-Vlaanderen, België", 51.256207, 4.090007],
    Haasdonk: ["Haasdonk, Beveren, Oost-Vlaanderen, België", 51.18103, 4.237839],
    Hamme: ["Hamme, Oost-Vlaanderen, België", 51.097764, 4.137723],
    Kallo: ["Kallo, Beveren, Oost-Vlaanderen, België", 51.2521, 4.278845],
    Kemzeke: ["Kemzeke, Stekene, Oost-Vlaanderen, België", 51.206093, 4.075717],
    Kieldrecht: ["Kieldrecht, Beveren, Oost-Vlaanderen, België", 51.289455, 4.175515],
    Kruibeke: ["Kruibeke, Oost-Vlaanderen, België", 51.171228, 4.309111],
    Meerdonk: ["Meerdonk, Sint-Gillis-Waas, Oost-Vlaanderen, België", 51.257114, 4.150548],
    Melsele: ["Melsele, Beveren, Oost-Vlaanderen, België", 51.22144, 4.28146],
    "Sint-Gillis-Waas": ["Sint-Gillis-Waas, Oost-Vlaanderen, België", 51.21799, 4.12861],
    "Sint-Niklaas": ["Sint-Niklaas, Oost-Vlaanderen, België", 51.164669, 4.139512],
    Temse: ["Temse, Oost-Vlaanderen, België", 51.124622, 4.214097],
    "Sint-Pauwels": ["Sint-Pauwels, Sint-Gillis-Waas, Oost-Vlaanderen, België", 51.193905, 4.095881],
    Steendorp: ["Steendorp, Temse, Oost-Vlaanderen, België", 51.12802, 4.270191],
    Stekene: ["Stekene, Oost-Vlaanderen, België", 51.206227, 4.039693],
    Verrebroek: ["Verrebroek, Beveren, Oost-Vlaanderen, België", 51.25559, 4.188836],
    Waasmunster: ["Waasmunster, Oost-Vlaanderen, België", 51.109715, 4.084216],
    Sinaai: ["Sinaai, Sint-Niklaas, Oost-Vlaanderen, België", 51.15713, 4.040784],
    Vrasene: ["Vrasene, Beveren, Oost-Vlaanderen, België", 51.219315, 4.194562],
  };
  const rules = [];
  for (const [city, dep, arr, pack] of rates) {
    const slug = city.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/[^a-z0-9]+/g, "_").replace(/^_|_$/g, "");
    rules.push(airportRule({ rule_id: `tm_bru_${slug}_to`, direction: "to_airport", zone_value: city, price_incl_vat: dep, outside_pax: "no_price" }));
    rules.push(airportRule({ rule_id: `tm_bru_${slug}_from`, direction: "from_airport", zone_value: city, price_incl_vat: arr, outside_pax: "no_price" }));
    rules.push(airportRule({
      rule_id: `tm_bru_${slug}_return`,
      direction: "return_package",
      zone_value: city,
      price_incl_vat: pack,
      price_covers: "return_package",
      outside_pax: "no_price",
    }));
  }
  const priced = doc(rules);
  const vans = ["vh_test_vito_1", "vh_test_vito_2"];
  for (const auto of [true, false]) {
    for (const vehicleId of vans) {
      for (const [city, dep, arr, pack] of rates) {
        const slug = city.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/[^a-z0-9]+/g, "_").replace(/^_|_$/g, "");
        const [label, lat, lng] = places[city];
        const toAirport = resolveCompanyFixedPriceFromDocument(priced, {
          from: label,
          to: "Brussels Airport, Zaventem, Belgium",
          from_lat: lat,
          from_lng: lng,
          airport_iata: "BRU",
          airport_direction: "to_airport",
          service: "airport",
          pax: 1,
          tier: "comfort",
          vehicle_id: vehicleId,
        }, { airportAutoCalcOutsideFixedFares: auto });
        assert.equal(toAirport.fixed_fare_rule_id, `tm_bru_${slug}_to`);
        assert.equal(toAirport.snapshot.total_incl_vat, dep);
        assert.equal(refuseAirportBookingWithoutAllowedFare(toAirport), null);
        const fromAirport = resolveCompanyFixedPriceFromDocument(priced, {
          from: "Brussels Airport, Zaventem, Belgium",
          to: label,
          to_lat: lat,
          to_lng: lng,
          airport_iata: "BRU",
          airport_direction: "from_airport",
          service: "airport",
          pax: 1,
          tier: "comfort",
          vehicle_id: vehicleId,
        }, { airportAutoCalcOutsideFixedFares: auto });
        assert.equal(fromAirport.fixed_fare_rule_id, `tm_bru_${slug}_from`);
        assert.equal(fromAirport.snapshot.total_incl_vat, arr);
        const roundTrip = resolveReturnPackageFromDocument(priced, {
          from: label,
          to: "Brussels Airport, Zaventem, Belgium",
          from_lat: lat,
          from_lng: lng,
          airport_iata: "BRU",
          airport_direction: "to_airport",
          service: "airport",
          return_enabled: true,
          pax: 1,
          tier: "comfort",
          vehicle_id: vehicleId,
        });
        assert.equal(roundTrip.fixed_fare_rule_id, `tm_bru_${slug}_return`);
        assert.equal(roundTrip.pricing.price_incl_vat, pack);
        assert.notEqual(roundTrip.pricing.price_incl_vat, dep + arr);
      }
    }
  }

  const kapelle = {
    from: "Brussels Airport, Zaventem, Belgium",
    to: "Sint Niklaaswijk, 1880 Kapelle-op-den-Bos, Vlaams-Brabant, België",
    to_lat: 51.007126,
    to_lng: 4.35422,
    airport_iata: "BRU",
    airport_direction: "from_airport",
    service: "airport",
    pax: 1,
    tier: "comfort",
  };
  const kapelleOff = resolveCompanyFixedPriceFromDocument(priced, kapelle, {
    airportAutoCalcOutsideFixedFares: false,
  });
  assert.equal(kapelleOff.matched, false);
  assert.equal(kapelleOff.reason, AIRPORT_NO_FIXED_FARE_REASON);
  assert.equal(kapelleOff.price_label, AIRPORT_NO_FIXED_FARE_PRICE_LABEL);
  assert.equal(kapelleOff.pricing, null);
  assert.equal(kapelleOff.snapshot, null);
  assert.equal(kapelleOff.request_quote_required, true);
  assert.equal(kapelleOff.block_calculator, true);
  const stale = refuseAirportBookingWithoutAllowedFare(kapelleOff);
  assert.equal(stale.ok, false);
  assert.equal(stale.reason, AIRPORT_NO_FIXED_FARE_REASON);
  assert.equal(stale.customer_action, "contact_company");
  assert.equal(Object.hasOwn(stale, "price_incl_vat"), false);
  const kapelleOn = resolveCompanyFixedPriceFromDocument(priced, kapelle, {
    airportAutoCalcOutsideFixedFares: true,
  });
  assert.equal(kapelleOn.request_quote_required, false);
  assert.equal(kapelleOn.pricing_source, "route_calc");
  assert.equal(kapelleOn.block_calculator, undefined);
  const kapelleMissing = resolveCompanyFixedPriceFromDocument(priced, kapelle);
  assert.equal(kapelleMissing.pricing_source, "route_calc");
  assert.equal(kapelleMissing.request_quote_required, false);
  assert.equal(airportAutoCalcOutsideFixedFaresEnabled({}), true);
  assert.equal(airportAutoCalcOutsideFixedFaresEnabled({ airport_auto_calc_outside_fixed_fares: false }), false);
  assert.equal(airportAutoCalcOutsideFixedFaresEnabled({ airportAutoCalcOutsideFixedFares: true }), true);

  const otherCompany = doc([
    airportRule({ rule_id: "other_gent_to", direction: "to_airport", zone_value: "Gent", price_incl_vat: 80 }),
  ]);
  const otherOpen = resolveCompanyFixedPriceFromDocument(otherCompany, kapelle);
  assert.equal(otherOpen.pricing_source, "route_calc");
  assert.notEqual(otherOpen.reason, AIRPORT_NO_FIXED_FARE_REASON);
  const marioClosedDoesNotLeak = resolveCompanyFixedPriceFromDocument(priced, {
    from: "Sint-Niklaas, Oost-Vlaanderen, België",
    to: "Brussels Airport, Zaventem, Belgium",
    from_lat: 51.164669,
    from_lng: 4.139512,
    airport_iata: "BRU",
    airport_direction: "to_airport",
    service: "airport",
    pax: 1,
    tier: "comfort",
  }, { airportAutoCalcOutsideFixedFares: false });
  assert.equal(marioClosedDoesNotLeak.fixed_fare_rule_id, "tm_bru_sint_niklaas_to");

  const taxi = doc([{
    rule_id: "gent_ronse",
    kind: "city_pair",
    direction: "both",
    origin: { type: "city", value: "Gent" },
    destination: { type: "city", value: "Ronse" },
    price_incl_vat: 95,
  }]);
  for (const auto of [undefined, true, false]) {
    const options = auto === undefined ? {} : { airportAutoCalcOutsideFixedFares: auto };
    const ride = resolveCompanyFixedPriceFromDocument(taxi, {
      from: "Gent, Oost-Vlaanderen, België",
      to: "Ronse, Oost-Vlaanderen, België",
      service: "taxi",
      pax: 1,
    }, options);
    assert.equal(ride.fixed_fare_rule_id, "gent_ronse");
    assert.equal(ride.snapshot.total_incl_vat, 95);
    const openTaxi = resolveCompanyFixedPriceFromDocument(taxi, {
      from: "Brugge, West-Vlaanderen, België",
      to: "Oostende, West-Vlaanderen, België",
      service: "taxi",
      pax: 1,
    }, options);
    assert.equal(openTaxi.pricing_source, "route_calc");
    assert.notEqual(openTaxi.reason, AIRPORT_NO_FIXED_FARE_REASON);
  }

  const tooMany = resolveCompanyFixedPriceFromDocument(priced, {
    from: "Sint-Niklaas, Oost-Vlaanderen, België",
    to: "Brussels Airport, Zaventem, Belgium",
    from_lat: 51.164669,
    from_lng: 4.139512,
    airport_iata: "BRU",
    airport_direction: "to_airport",
    service: "airport",
    pax: 6,
    tier: "comfort",
  }, { airportAutoCalcOutsideFixedFares: true });
  assert.equal(tooMany.reason, "pax_not_covered");
  assert.equal(tooMany.pricing, null);
  assert.equal(tooMany.block_calculator, true);
  const barePostcode = resolveCompanyFixedPriceFromDocument(priced, {
    from: "9100",
    to: "Brussels Airport, Zaventem, Belgium",
    airport_iata: "BRU",
    airport_direction: "to_airport",
    service: "airport",
    pax: 1,
    tier: "comfort",
  }, { airportAutoCalcOutsideFixedFares: false });
  assert.equal(barePostcode.reason, "pickup_address_required");
  assert.notEqual(barePostcode.reason, AIRPORT_NO_FIXED_FARE_REASON);
  assert.equal(refuseAirportBookingWithoutAllowedFare(kapelleOn), null);

  const held = normalizeCompanyFixedPricesDocument({
    fallback: "calculator",
    pending_price_conditions: { lead_time_hours: 48 },
    rules: [airportRule({
      rule_id: "tm_bru_sint_niklaas_to",
      direction: "to_airport",
      zone_value: "Sint-Niklaas",
      price_incl_vat: 115,
      outside_pax: "no_price",
    })],
  });
  const tooSoon = resolveCompanyFixedPriceFromDocument(held, {
    from: "Sint-Niklaas, Oost-Vlaanderen, België",
    to: "Brussels Airport, Zaventem, Belgium",
    airport_iata: "BRU",
    airport_direction: "to_airport",
    service: "airport",
    pax: 1,
    tier: "comfort",
    pickup_iso: new Date(Date.now() + 2 * 3600 * 1000).toISOString(),
  }, { airportAutoCalcOutsideFixedFares: true, nowMs: Date.now() });
  assert.equal(tooSoon.reason, "unconfirmed_price_conditions");
  assert.equal(tooSoon.pricing, null);
  assert.equal(tooSoon.block_calculator, true);
  assert.equal(refuseAirportBookingWithoutAllowedFare(tooSoon).ok, false);
});

test("fixed airport prices use one advance-booking term and the calculator switch", () => {
  const hour = 60 * 60 * 1000;
  const rules = doc([
    airportRule({
      rule_id: "tm_bru_sint_niklaas_to",
      direction: "to_airport",
      zone_value: "Sint-Niklaas",
      price_incl_vat: 115,
      outside_pax: "no_price",
    }),
    airportRule({
      rule_id: "tm_bru_sint_niklaas_from",
      direction: "from_airport",
      zone_value: "Sint-Niklaas",
      price_incl_vat: 120,
      outside_pax: "no_price",
    }),
    airportRule({
      rule_id: "tm_bru_sint_niklaas_return",
      direction: "return_package",
      zone_value: "Sint-Niklaas",
      price_incl_vat: 215,
      price_covers: "return_package",
      outside_pax: "no_price",
    }),
    airportRule({
      rule_id: "tm_bru_temse_return",
      direction: "return_package",
      zone_value: "Temse",
      price_incl_vat: 215,
      price_covers: "return_package",
      outside_pax: "no_price",
    }),
  ]);
  const storedHold = normalizeCompanyFixedPricesDocument({
    ...rules,
    pending_price_conditions: { lead_time_hours: 48, invoice_terms_missing: true },
  });
  const toAirport = {
    from: "Sint-Niklaas, Oost-Vlaanderen, België",
    to: "Brussels Airport, Zaventem, Belgium",
    airport_iata: "BRU",
    airport_direction: "to_airport",
    service: "airport",
    pax: 1,
    tier: "comfort",
    pickup_iso: "2026-10-23T16:00:00.000Z",
  };
  const fromAirport = {
    ...toAirport,
    from: "Brussels Airport, Zaventem, Belgium",
    to: "Sint-Niklaas, Oost-Vlaanderen, België",
    airport_direction: "from_airport",
  };
  const pickupMs = Date.parse(toAirport.pickup_iso);
  const beforeTerm = pickupMs - (48 * hour) + 1;
  const exactly = pickupMs - (48 * hour);
  const afterTerm = pickupMs - (49 * hour);

  assert.equal(profileDeclaresAirportFixedFareMinLeadHours({}), false);
  assert.equal(airportFixedFareMinLeadHours({}), undefined);
  assert.equal(airportFixedFareMinLeadHours({ airport_fixed_fare_min_lead_hours: 48 }), 48);
  assert.equal(airportFixedFareMinLeadHours({ airportFixedFareMinLeadHours: "48" }), 48);
  assert.equal(airportFixedFareMinLeadHours({ airport_fixed_fare_min_lead_hours: 0 }), null);
  assert.equal(airportFixedFareMinLeadHours({ airport_fixed_fare_min_lead_hours: null }), null);

  const legacySoon = resolveCompanyFixedPriceFromDocument(storedHold, toAirport, {
    nowMs: beforeTerm,
    airportAutoCalcOutsideFixedFares: true,
  });
  assert.equal(legacySoon.reason, "unconfirmed_price_conditions");
  assert.equal(legacySoon.block_calculator, true);
  assert.equal(legacySoon.pricing, null);
  assert.ok(legacySoon.conditions.includes("lead_time"));

  for (const ride of [toAirport, fromAirport]) {
    const expectedRule = ride.airport_direction === "to_airport"
      ? "tm_bru_sint_niklaas_to"
      : "tm_bru_sint_niklaas_from";
    const expectedAmount = ride.airport_direction === "to_airport" ? 115 : 120;
    const tooSoonOff = resolveCompanyFixedPriceFromDocument(storedHold, ride, {
      nowMs: beforeTerm,
      airportAutoCalcOutsideFixedFares: false,
      airportFixedFareMinLeadHours: 48,
    });
    assert.equal(tooSoonOff.reason, AIRPORT_NO_FIXED_FARE_REASON);
    assert.equal(tooSoonOff.price_label, AIRPORT_NO_FIXED_FARE_PRICE_LABEL);
    assert.equal(tooSoonOff.pricing, null);
    assert.equal(tooSoonOff.snapshot, null);
    assert.deepEqual(tooSoonOff.conditions, ["lead_time"]);
    const refused = refuseAirportBookingWithoutAllowedFare(tooSoonOff);
    assert.equal(refused.ok, false);
    assert.equal(refused.reason, AIRPORT_NO_FIXED_FARE_REASON);
    assert.equal(Object.hasOwn(refused, "price_incl_vat"), false);
    assert.deepEqual(refused.conditions, ["lead_time"]);

    const tooSoonOn = resolveCompanyFixedPriceFromDocument(rules, ride, {
      nowMs: beforeTerm,
      airportAutoCalcOutsideFixedFares: true,
      airportFixedFareMinLeadHours: 48,
    });
    assert.equal(tooSoonOn.pricing_source, "route_calc");
    assert.equal(tooSoonOn.fixed_fare_rule_id, undefined);
    assert.equal(refuseAirportBookingWithoutAllowedFare(tooSoonOn), null);

    for (const nowMs of [exactly, afterTerm]) {
      for (const auto of [true, false]) {
        const priced = resolveCompanyFixedPriceFromDocument(rules, ride, {
          nowMs,
          airportAutoCalcOutsideFixedFares: auto,
          airportFixedFareMinLeadHours: 48,
        });
        assert.equal(priced.fixed_fare_rule_id, expectedRule);
        assert.equal(priced.snapshot.total_incl_vat, expectedAmount);
      }
    }
  }

  const cleared = resolveCompanyFixedPriceFromDocument(storedHold, toAirport, {
    nowMs: beforeTerm,
    airportAutoCalcOutsideFixedFares: true,
    airportFixedFareMinLeadHours: null,
  });
  assert.equal(cleared.fixed_fare_rule_id, "tm_bru_sint_niklaas_to");
  assert.equal(cleared.snapshot.total_incl_vat, 115);

  const unset = resolveCompanyFixedPriceFromDocument(rules, toAirport, {
    nowMs: beforeTerm,
    airportAutoCalcOutsideFixedFares: false,
  });
  assert.equal(unset.fixed_fare_rule_id, "tm_bru_sint_niklaas_to");

  const taxi = doc([{
    rule_id: "gent_ronse",
    kind: "city_pair",
    direction: "both",
    origin: { type: "city", value: "Gent" },
    destination: { type: "city", value: "Ronse" },
    price_incl_vat: 95,
  }]);
  const taxiSoon = resolveCompanyFixedPriceFromDocument(taxi, {
    from: "Gent, Oost-Vlaanderen, België",
    to: "Ronse, Oost-Vlaanderen, België",
    service: "taxi",
    pax: 1,
    pickup_iso: toAirport.pickup_iso,
  }, {
    nowMs: beforeTerm,
    airportAutoCalcOutsideFixedFares: false,
    airportFixedFareMinLeadHours: 48,
  });
  assert.equal(taxiSoon.fixed_fare_rule_id, "gent_ronse");
  assert.equal(taxiSoon.snapshot.total_incl_vat, 95);

  const roundTrip = {
    ...toAirport,
    return_enabled: true,
  };
  const packageOnTime = resolveReturnPackageFromDocument(rules, roundTrip, {
    nowMs: exactly,
    airportFixedFareMinLeadHours: 48,
  });
  assert.equal(packageOnTime.fixed_fare_rule_id, "tm_bru_sint_niklaas_return");
  assert.equal(packageOnTime.pricing.price_incl_vat, 215);
  const packageEarlyOff = resolveReturnPackageFromDocument(rules, roundTrip, {
    nowMs: beforeTerm,
    airportAutoCalcOutsideFixedFares: false,
    airportFixedFareMinLeadHours: 48,
  });
  assert.equal(packageEarlyOff.matched, false);
  assert.equal(packageEarlyOff.pricing, null);
  const packageEarlyOn = resolveReturnPackageFromDocument(rules, roundTrip, {
    nowMs: beforeTerm,
    airportAutoCalcOutsideFixedFares: true,
    airportFixedFareMinLeadHours: 48,
  });
  assert.equal(packageEarlyOn.matched, false);
  assert.equal(packageEarlyOn.pricing, null);
  const temse = resolveReturnPackageFromDocument(rules, {
    ...roundTrip,
    from: "Temse, Oost-Vlaanderen, België",
  }, {
    nowMs: afterTerm,
    airportFixedFareMinLeadHours: 48,
  });
  assert.equal(temse.fixed_fare_rule_id, "tm_bru_temse_return");
  assert.equal(temse.pricing.price_incl_vat, 215);

  const invoice = resolveCompanyFixedPriceFromDocument(storedHold, {
    ...toAirport,
    invoice_requested: true,
  }, {
    nowMs: afterTerm,
    airportAutoCalcOutsideFixedFares: true,
    airportFixedFareMinLeadHours: 48,
  });
  assert.equal(invoice.reason, "unconfirmed_price_conditions");
  assert.deepEqual(invoice.conditions, ["invoice"]);
  assert.equal(invoice.pricing, null);
  assert.equal(invoice.block_calculator, true);

  const tooMany = resolveCompanyFixedPriceFromDocument(rules, {
    ...toAirport,
    pax: 6,
  }, {
    nowMs: beforeTerm,
    airportAutoCalcOutsideFixedFares: true,
    airportFixedFareMinLeadHours: 48,
  });
  assert.equal(tooMany.reason, "pax_not_covered");
  assert.equal(tooMany.pricing, null);
});
test('verified inside-area airport rule remains displayable while its booking conditions stay blocked', () => {
  const rules = doc([airportRule({ rule_id: 'display_sn_bru', direction: 'to_airport',
    zone_value: 'Sint-Niklaas', price_incl_vat: 115, outside_pax: 'no_price' })]);
  const held = { ...rules, pending_price_conditions: { lead_time_hours: 48, invoice_terms_missing: true } };
  const pickupMs = Date.parse('2026-10-05T05:00:00Z');
  const ride = { from: 'Grote Markt 1, 9100 Sint-Niklaas, BE', to: 'Brussels Airport, Zaventem, BE',
    service: 'airport', airport_iata: 'BRU', airport_direction: 'to_airport', pax: 1,
    pickup_iso: new Date(pickupMs).toISOString() };
  const verified = { configured: true, checked: true, inside: true };
  for (const options of [
    { nowMs: pickupMs - 3600000 },
    { nowMs: pickupMs - 3600000, airportFixedFareMinLeadHours: 48, airportAutoCalcOutsideFixedFares: true },
    { nowMs: pickupMs - 72 * 3600000, invoice: true },
  ]) {
    const result = resolveCompanyFixedPriceFromDocument(held, { ...ride,
      ...(options.invoice ? { invoice_requested: true } : {}) }, { ...options, fixedFareDisplayWorkArea: verified });
    assert.equal(result.matched, false);
    assert.equal(result.pricing ?? null, null);
    assert.equal(result.snapshot ?? null, null);
    assert.equal(result.booking_allowed, false);
    assert.equal(result.fixed_fare_display.price_incl_vat, 115);
    assert.equal(result.fixed_fare_display.currency, 'EUR');
    assert.equal(result.fixed_fare_display.display_only, true);
    assert.equal(result.booking_restriction.conditions.includes(options.invoice ? 'invoice' : 'lead_time'), true);
  }
  for (const area of [undefined, {}, { configured: true, checked: false },
    { configured: true, checked: true, inside: false }]) {
    const result = resolveCompanyFixedPriceFromDocument(held, ride,
      { nowMs: pickupMs - 3600000, fixedFareDisplayWorkArea: area });
    assert.equal(result.fixed_fare_display ?? null, null);
  }
  for (const body of [{ ...ride, from: '9100' }, { ...ride, airport_iata: 'AMS' }, { ...ride, pax: 6 }]) {
    const result = resolveCompanyFixedPriceFromDocument(held, body,
      { nowMs: pickupMs - 3600000, fixedFareDisplayWorkArea: verified });
    assert.equal(result.fixed_fare_display ?? null, null);
  }
});

test('restricted airport displays preserve reverse direction and return coverage without snapshots', () => {
  const pickupMs = Date.parse('2026-10-05T05:00:00Z');
  const options = {nowMs: pickupMs - 3600000, fixedFareDisplayWorkArea: {configured: true, checked: true, inside: true}};
  const rules = doc([
    airportRule({rule_id: 'reverse_display', direction: 'from_airport', zone_value: 'Sint-Niklaas', price_incl_vat: 120}),
    airportRule({rule_id: 'return_display', direction: 'return_package', zone_value: 'Sint-Niklaas',
      price_incl_vat: 215, price_covers: 'return_package'}),
  ]);
  const held = {...rules, pending_price_conditions: {lead_time_hours: 48}};
  const reverse = {from: 'Brussels Airport, Zaventem, BE', to: 'Grote Markt 1, 9100 Sint-Niklaas, BE',
    service: 'airport', airport_iata: 'BRU', airport_direction: 'from_airport', pax: 1,
    pickup_iso: new Date(pickupMs).toISOString()};
  const result = resolveCompanyFixedPriceFromDocument(held, reverse, options);
  assert.equal(result.fixed_fare_display.price_incl_vat, 120);
  assert.equal(result.fixed_fare_display.price_covers, 'one_way');
  assert.equal(result.matched, false);
  assert.equal(result.snapshot, null);
  const outbound = {...reverse, from: reverse.to, to: reverse.from, airport_direction: 'to_airport', return_enabled: true};
  const pack = resolveReturnPackageFromDocument(held, outbound, options);
  assert.equal(pack.fixed_fare_display.price_incl_vat, 215);
  assert.equal(pack.fixed_fare_display.price_covers, 'return_package');
  assert.equal(pack.return_package_applied, false);
  assert.equal(pack.snapshot, null);
  assert.equal(pack.pricing, null);
  const precision = doc([airportRule({rule_id: 'precision_display', direction: 'from_airport', zone_value: 'Sint-Niklaas', price_incl_vat: 120.03})]);
  const future = resolveCompanyFixedPriceFromDocument(precision, reverse, {vatRate: 0.06, vatMode: 'excl'});
  const preview = resolveCompanyFixedPriceFromDocument({...precision, pending_price_conditions: {lead_time_hours: 48}}, reverse,
    {...options, vatRate: 0.06, vatMode: 'excl'});
  assert.equal(preview.fixed_fare_display.price_incl_vat, future.pricing.price_incl_vat);
});

test('company airport minimum applies at exact elapsed-hour boundary and never to ordinary taxis', () => {
 const now=Date.parse('2026-10-02T06:00:00Z');
 const airport={service:'airport',pickup_iso:'2026-10-04T05:59:59Z'};
 assert.equal(airportBookingAdvanceRefusal(airport,48,now)?.minimum_advance_hours,48);
 assert.equal(airportBookingAdvanceRefusal({...airport,pickup_iso:'2026-10-04T06:00:00Z'},48,now),null);
 assert.equal(airportBookingAdvanceRefusal(airport,24,now),null);
 assert.equal(airportBookingAdvanceRefusal(airport,0,now),null);
 assert.equal(airportBookingAdvanceRefusal(airport,undefined,now),null);
 assert.equal(airportBookingAdvanceRefusal({service:'taxi',pickup_iso:'2026-10-02T07:00:00Z'},48,now),null);
 const dstNow=Date.parse('2026-10-24T06:00:00Z');
 assert.equal(airportBookingAdvanceRefusal({service:'airport',pickup_iso:'2026-10-26T06:00:00Z'},48,dstNow),null);
});

test('district tariff is scoped to its configured parent municipality',()=>{
 const document={rules:[{rule_id:'hamme-sint-anna',kind:'airport',airport_iata:'BRU',direction:'to_airport',origin:{type:'airport',value:'BRU',airport_iata:'BRU'},destination:{type:'city',value:'sint anna',parent_city:'hamme'},price_incl_vat:120}]};
 const options={};const payload={airport_iata:'BRU',airport_direction:'to_airport',pax:1};
 assert.equal(normalizeCompanyFixedPricesDocument(document).rules[0].destination.parent_city,'hamme');
 assert.equal(resolveCompanyFixedPriceFromDocument(document,{...payload,from:'Sint-Anna, Hamme, België'},options).matched,true);
 assert.equal(resolveCompanyFixedPriceFromDocument(document,{...payload,from:'Sint-Anna, Gent, België'},options).matched,false);
 assert.equal(resolveCompanyFixedPriceFromDocument(document,{...payload,from:'Hamme, België'},options).matched,false);
});
