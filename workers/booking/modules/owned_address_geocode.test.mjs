import test from "node:test";
import assert from "node:assert/strict";
import {
  localitiesCompatible,
  pickGeocodeFeature,
  queryPostcode,
} from "./owned_address_geocode.mjs";

const maarkedal48 = {
  place_name: "Koekamerstraat 48, 9688 Maarkedal, België",
  center: [3.66942, 50.77205],
  context: [{ id: "postcode.9688", text: "9688" }],
};

const maarkedal48a = {
  place_name: "Koekamerstraat 48A, 9688 Maarkedal, België",
  center: [3.66942, 50.77205],
  context: [{ id: "postcode.9688", text: "9688" }],
};

const ronse = {
  place_name: "Koekamerstraat - Rue Cocambre 48a, 9600 Ronse, België",
  center: [3.672568, 50.770403],
  context: [{ id: "postcode.9600", text: "9600" }],
};

test("owned 9688 Schorisse does not take the competing Ronse feature", () => {
  const query = "Koekamerstraat 48A, 9688 Schorisse, BE";
  assert.equal(queryPostcode(query), "9688");
  const picked = pickGeocodeFeature([ronse, maarkedal48], query);
  assert.equal(picked, null);
});

test("a proven 48A match at 9688 is accepted", () => {
  const picked = pickGeocodeFeature(
    [ronse, maarkedal48a],
    "Koekamerstraat 48A, 9688 Schorisse, BE",
  );
  assert.equal(picked, maarkedal48a);
  assert.deepEqual(picked.center, [3.66942, 50.77205]);
});

test("query postcode without an agreeing feature refuses the first guess", () => {
  const picked = pickGeocodeFeature(
    [ronse],
    "Koekamerstraat 48A, 9688 Schorisse, BE",
  );
  assert.equal(picked, null);
});

test("competing postcodes without a query postcode refuse the first guess", () => {
  const picked = pickGeocodeFeature([ronse, maarkedal48], "Koekamerstraat 48A");
  assert.equal(picked, null);
});

test("Schorisse and Maarkedal are equivalent localities", () => {
  assert.equal(localitiesCompatible("Schorisse", "Maarkedal"), true);
  assert.equal(localitiesCompatible("Schorisse", "Ronse"), false);
});
