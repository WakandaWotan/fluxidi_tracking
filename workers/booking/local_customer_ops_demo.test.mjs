import assert from "node:assert/strict";
import test from "node:test";

import {
  LOCAL_DEMO_COMPANIES,
  companyLinkSeedRecord,
  demoDriver,
  demoDriverLoginCode,
  demoVehicle,
  extraDemoDrivers,
  mergeDemoDriverRecord,
  solidLogoPng,
} from "./local_customer_ops_demo_companies.mjs";
import {
  canonicalLocalDemoPartnerId,
  ensureLocalDemoPublicPartners,
} from "./local_customer_ops_demo.mjs";

test("local demo seeds two companies with distinct names and logos", () => {
  assert.equal(LOCAL_DEMO_COMPANIES.length, 2);
  assert.equal(LOCAL_DEMO_COMPANIES[0].name, "Fluxidi Demo Cars");
  assert.equal(LOCAL_DEMO_COMPANIES[1].name, "Nocturne Limousines");
  assert.notEqual(LOCAL_DEMO_COMPANIES[0].id, LOCAL_DEMO_COMPANIES[1].id);
  assert.notEqual(LOCAL_DEMO_COMPANIES[0].token, LOCAL_DEMO_COMPANIES[1].token);
  const a = solidLogoPng(LOCAL_DEMO_COMPANIES[0].logo);
  const b = solidLogoPng(LOCAL_DEMO_COMPANIES[1].logo);
  assert.notEqual(a.equals(b), true);
  assert.equal(a[0], 137);
  assert.equal(a[1], 80);
  assert.equal(a[2], 78);
  assert.equal(a[3], 71);
});

test("demo fleet and drivers stay company-scoped and skip the Tesla placeholder", () => {
  const cars = demoVehicle(LOCAL_DEMO_COMPANIES[0]);
  const limo = demoVehicle(LOCAL_DEMO_COMPANIES[1]);
  assert.notEqual(cars.license_plate, limo.license_plate);
  assert.notEqual(cars.license_plate, "1-ABC-123");
  assert.notEqual(
    demoDriver(LOCAL_DEMO_COMPANIES[0]).driver_id,
    demoDriver(LOCAL_DEMO_COMPANIES[1]).driver_id,
  );
});

test("Fluxidi local demo seeds twenty chauffeurs and keeps saved agenda colors", () => {
  const cars = LOCAL_DEMO_COMPANIES[0];
  const extras = extraDemoDrivers(cars);
  const all = [demoDriver(cars), ...extras];
  assert.equal(all.length, 20);
  assert.equal(extras[0].display_name, "Amira Benali");
  assert.equal(extras[0].agenda_color, "#2F6B4F");
  assert.equal(extras[1].display_name, "Tom Janssen");
  assert.equal(extras[1].agenda_color, "#3D5A80");
  assert.equal(demoDriver(cars).agenda_color, "#C9A227");
  assert.equal(
    all.filter((driver) => driver.agenda_color === "#C9A227").length,
    2,
  );
  assert.equal(extraDemoDrivers(LOCAL_DEMO_COMPANIES[1]).length, 0);
  const kept = mergeDemoDriverRecord(
    { driver_id: "drv_demo_company_p0_1", agenda_color: "#3D5A80" },
    { driver_id: "drv_demo_company_p0_1", agenda_color: "#C9A227" },
  );
  assert.equal(kept.agenda_color, "#3D5A80");
});

test("local demo companies expose link records and distinct driver login codes", () => {
  const cars = LOCAL_DEMO_COMPANIES[0];
  const limo = LOCAL_DEMO_COMPANIES[1];
  const link = companyLinkSeedRecord(cars);
  assert.equal(link.company_code, cars.code);
  assert.equal(link.linking_enabled, true);
  assert.equal(link.company_id, cars.id);
  assert.notEqual(demoDriverLoginCode(cars), demoDriverLoginCode(limo));
  assert.equal(demoDriver(cars).login_code, demoDriverLoginCode(cars));
});

test("local demo companies appear as bookable public partners without dropping existing rows", async () => {
  const store = new Map();
  store.set(
    "partners:directory:v1",
    JSON.stringify({
      partners: [
        {
          partner_id: "partner_keep_me",
          company_name: "Existing Partner",
          is_active: true,
          subscription_status: "active",
          supported_postcodes: ["1000"],
        },
      ],
    }),
  );
  const kv = {
    async get(key, opts) {
      const raw = store.get(key);
      if (raw == null) return null;
      if (opts === "json" || opts?.type === "json") return JSON.parse(raw);
      return raw;
    },
    async put(key, val) {
      store.set(key, val);
    },
  };
  await ensureLocalDemoPublicPartners(kv);
  const directory = JSON.parse(store.get("partners:directory:v1"));
  const ids = directory.partners.map((row) => row.partner_id).sort();
  assert.equal(ids.includes("partner_keep_me"), true);
  assert.equal(ids.includes(canonicalLocalDemoPartnerId(LOCAL_DEMO_COMPANIES[0])), true);
  const routes = JSON.parse(store.get("public:partners:booking-routes:v2"));
  const demoRoute = routes.routes.find(
    (row) => row.partner_id === canonicalLocalDemoPartnerId(LOCAL_DEMO_COMPANIES[0]),
  );
  assert.equal(demoRoute.tenant_id, "demo_company_p0");
  assert.equal(demoRoute.company_id, "demo_company_p0");
  assert.equal(demoRoute.is_active, true);
});
