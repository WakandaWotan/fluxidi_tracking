import test from "node:test";
import assert from "node:assert/strict";
import { normalizeCompanyCustomerAddresses } from "./company_customers.mjs";

test("street and house number are composed into line1 and kept", () => {
  const out = normalizeCompanyCustomerAddresses([
    {
      type: "home",
      street: "Koekamerstraat",
      house_number: "48A",
      postal_code: "9688",
      city: "Maarkedal",
      country_code: "BE",
      lat: 50.7964,
      lon: 3.6572,
    },
  ]);
  assert.equal(out[0].line1, "Koekamerstraat 48A");
  assert.equal(out[0].street, "Koekamerstraat");
  assert.equal(out[0].house_number, "48A");
  assert.equal(out[0].lat, 50.7964);
  assert.equal(out[0].lon, 3.6572);
});

test("an existing line1 is not replaced by a later street alias", () => {
  const out = normalizeCompanyCustomerAddresses([
    {
      type: "home",
      line1: "Koekamerstraat 48A",
      street: "Andere straat",
      city: "Maarkedal",
    },
  ]);
  assert.equal(out[0].line1, "Koekamerstraat 48A");
});
