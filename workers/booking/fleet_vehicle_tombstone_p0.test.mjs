// FLEET-VEHICLE-TOMBSTONE-P0 (integration)
//
// Server-owned vehicle deletion tombstones on POST /admin/fleet/vehicles and
// GET /company/bootstrap. Mirrors the driver deleted_drivers tombstone pattern:
// a deleted vehicle can never be resurrected by a stale full list, and
// historical ride/document/Chiron records are never mutated.
//
// Run:
//   node --test workers/booking/fleet_vehicle_tombstone_p0.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import worker from "./fluxidi_booking_worker.js";

const HERE = dirname(fileURLToPath(import.meta.url));
const FLEET_ROUTE = "/admin/fleet/vehicles";
const BOOTSTRAP_ROUTE = "/company/bootstrap";

async function sha256Hex(text) {
  const data = new TextEncoder().encode(String(text || ""));
  const digest = await crypto.subtle.digest("SHA-256", data);
  const bytes = new Uint8Array(digest);
  let hex = "";
  for (const byte of bytes) hex += byte.toString(16).padStart(2, "0");
  return hex;
}

function makeKV(seed = {}) {
  const store = new Map(Object.entries(seed));
  return {
    store,
    async get(key, opts) {
      if (!store.has(key)) return null;
      const raw = store.get(key);
      if (opts && opts.type === "json") {
        try {
          return typeof raw === "string" ? JSON.parse(raw) : raw;
        } catch (_) {
          return null;
        }
      }
      return raw;
    },
    async put(key, val) {
      store.set(key, val);
    },
    async delete(key) {
      store.delete(key);
    },
    async list(opts = {}) {
      const prefix = typeof opts.prefix === "string" ? opts.prefix : "";
      const keys = [...store.keys()]
        .filter((name) => !prefix || name.startsWith(prefix))
        .map((name) => ({ name }));
      return { keys, list_complete: true };
    },
  };
}

const TENANT = "T1";
const COMPANY = "C1";

function fleetKey(tenantId = TENANT, companyId = COMPANY) {
  return `tenant:${tenantId}:company:${companyId}:fleet:vehicles:v1`;
}

function vehicle(id, name, plate) {
  return {
    vehicle_id: id,
    vehicle_name: name,
    license_plate: plate,
    is_active: true,
    tenant_id: TENANT,
    company_id: COMPANY,
  };
}

async function makeEnv({ fleet } = {}) {
  const tokenValue = "operator-a-token";
  const hash = await sha256Hex(tokenValue);
  const sessionKey = `company_admin:session:${hash}:v1`;
  const historicalRideKey = "booking:street_hist_ferrari_1:v1";
  const historicalRide = {
    booking_id: "street_hist_ferrari_1",
    tenant_id: TENANT,
    company_id: COMPANY,
    assigned_vehicle_id: "vh_ferrari",
    status: "COMPLETED",
    payment_status: "paid",
    billit_document_id: "billit_doc_keep",
    chiron_trip_ref: "chiron_keep",
  };
  const seed = {
    [sessionKey]: {
      role: "company_admin",
      tenant_id: TENANT,
      company_id: COMPANY,
      company_code: "FLX-00001",
      company_display_name: "Fluxidi",
      expires_at: new Date(Date.now() + 3_600_000).toISOString(),
    },
    [historicalRideKey]: historicalRide,
  };
  if (fleet) seed[fleetKey()] = fleet;
  const bookingKv = makeKV(seed);
  return {
    env: { BOOKING_KV: bookingKv },
    bookingKv,
    tokenValue,
    historicalRideKey,
    historicalRide,
  };
}

function postFleet({ token, body }) {
  return new Request(`https://example.test${FLEET_ROUTE}`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${token}`,
    },
    body: JSON.stringify(body),
  });
}

function getBootstrap({ token }) {
  return new Request(`https://example.test${BOOTSTRAP_ROUTE}`, {
    method: "GET",
    headers: { authorization: `Bearer ${token}` },
  });
}

function readFleet(bookingKv) {
  const raw = bookingKv.store.get(fleetKey());
  return typeof raw === "string" ? JSON.parse(raw) : raw;
}

test("source contract: worker wires vehicle tombstones into POST + bootstrap", () => {
  const src = readFileSync(join(HERE, "fluxidi_booking_worker.js"), "utf8");
  assert.match(src, /from "\.\/modules\/fleet_vehicle_tombstone\.mjs"/);
  assert.match(src, /mergeVehicleTombstones\(/);
  assert.match(src, /filterActiveVehicles\(/);
  assert.match(src, /resolveFleetRevision\(/);
  assert.match(src, /deleted_vehicle_ids: mergedDeleted/);
  assert.match(src, /deleted_vehicle_ids: deletedVehicleIds/);
});

test("delete persists a vehicle tombstone and drops it from the active list", async () => {
  const { env, bookingKv, tokenValue } = await makeEnv({
    fleet: {
      version: 1,
      updated_at: new Date().toISOString(),
      vehicles: [
        vehicle("vh_tesla", "Hoofdwagen", "T-XAA-674"),
        vehicle("vh_cadillac", "Cadillac", "Tax002"),
        vehicle("vh_ferrari", "Ferrari EV", "T-XAA-673"),
      ],
    },
  });
  const res = await worker.fetch(
    postFleet({
      token: tokenValue,
      body: {
        tenant_id: TENANT,
        company_id: COMPANY,
        vehicles: [
          vehicle("vh_tesla", "Hoofdwagen", "T-XAA-674"),
          vehicle("vh_cadillac", "Cadillac", "Tax002"),
        ],
        deleted_vehicle_ids: { vh_ferrari: "2026-08-16T15:40:00.000Z" },
      },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 200);
  assert.equal(j.ok, true);
  assert.equal(j.changed, true);
  assert.deepEqual(
    j.vehicles.map((v) => v.vehicle_id).sort(),
    ["vh_cadillac", "vh_tesla"],
  );
  assert.deepEqual(j.deleted_vehicle_ids, ["vh_ferrari"]);
  assert.ok(Number.isInteger(j.source_revision) && j.source_revision >= 1);

  const stored = readFleet(bookingKv);
  assert.ok(stored.deleted_vehicle_ids.vh_ferrari);
  assert.equal(
    stored.vehicles.some((v) => v.vehicle_id === "vh_ferrari"),
    false,
  );
  assert.ok(Number.isInteger(stored.source_revision));
});

test("a stale full list can never resurrect a tombstoned vehicle", async () => {
  const { env, bookingKv, tokenValue } = await makeEnv({
    fleet: {
      version: 1,
      source_revision: 4,
      updated_at: new Date().toISOString(),
      vehicles: [vehicle("vh_tesla", "Hoofdwagen", "T-XAA-674")],
      deleted_vehicle_ids: { vh_ferrari: "2026-08-16T15:40:00.000Z" },
    },
  });
  // Old client POSTs the full list with Ferrari back and no tombstones.
  const res = await worker.fetch(
    postFleet({
      token: tokenValue,
      body: {
        tenant_id: TENANT,
        company_id: COMPANY,
        vehicles: [
          vehicle("vh_tesla", "Hoofdwagen", "T-XAA-674"),
          vehicle("vh_ferrari", "Ferrari EV", "T-XAA-673"),
        ],
      },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 200);
  assert.equal(
    j.vehicles.some((v) => v.vehicle_id === "vh_ferrari"),
    false,
    "stale Ferrari must not resurrect",
  );
  assert.deepEqual(j.deleted_vehicle_ids, ["vh_ferrari"]);
  const stored = readFleet(bookingKv);
  assert.ok(stored.deleted_vehicle_ids.vh_ferrari);
  assert.equal(
    stored.vehicles.some((v) => v.vehicle_id === "vh_ferrari"),
    false,
  );
});

test("repeated identical delete is idempotent and does not bump the revision", async () => {
  const { env, bookingKv, tokenValue } = await makeEnv({
    fleet: {
      version: 1,
      source_revision: 7,
      updated_at: new Date().toISOString(),
      vehicles: [vehicle("vh_tesla", "Hoofdwagen", "T-XAA-674")],
      deleted_vehicle_ids: { vh_ferrari: "2026-08-16T15:40:00.000Z" },
    },
  });
  const body = {
    tenant_id: TENANT,
    company_id: COMPANY,
    vehicles: [vehicle("vh_tesla", "Hoofdwagen", "T-XAA-674")],
    deleted_vehicle_ids: { vh_ferrari: "2026-08-16T18:00:00.000Z" },
  };
  const res = await worker.fetch(postFleet({ token: tokenValue, body }), env, {});
  const j = await res.json();
  assert.equal(res.status, 200);
  assert.equal(j.changed, false);
  assert.equal(j.source_revision, 7, "idempotent delete keeps the revision");
  const stored = readFleet(bookingKv);
  // Original tombstone timestamp is preserved (union never overwrites).
  assert.equal(stored.deleted_vehicle_ids.vh_ferrari, "2026-08-16T15:40:00.000Z");
});

test("client cannot force the server-owned source_revision", async () => {
  const { env, bookingKv, tokenValue } = await makeEnv({
    fleet: {
      version: 1,
      source_revision: 3,
      updated_at: new Date().toISOString(),
      vehicles: [vehicle("vh_tesla", "Hoofdwagen", "T-XAA-674")],
      deleted_vehicle_ids: {},
    },
  });
  const res = await worker.fetch(
    postFleet({
      token: tokenValue,
      body: {
        tenant_id: TENANT,
        company_id: COMPANY,
        source_revision: 9999,
        vehicles: [
          vehicle("vh_tesla", "Hoofdwagen", "T-XAA-674"),
          vehicle("vh_cadillac", "Cadillac", "Tax002"),
        ],
      },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 200);
  assert.equal(j.changed, true);
  assert.equal(j.source_revision, 4, "revision is server-computed (3 -> 4)");
  const stored = readFleet(bookingKv);
  assert.equal(stored.source_revision, 4);
});

test("bootstrap returns active vehicles separately from deleted_vehicle_ids", async () => {
  const { env, tokenValue } = await makeEnv({
    fleet: {
      version: 1,
      source_revision: 5,
      updated_at: new Date().toISOString(),
      vehicles: [
        vehicle("vh_tesla", "Hoofdwagen", "T-XAA-674"),
        vehicle("vh_cadillac", "Cadillac", "Tax002"),
      ],
      deleted_vehicle_ids: { vh_ferrari: "2026-08-16T15:40:00.000Z" },
    },
  });
  const res = await worker.fetch(getBootstrap({ token: tokenValue }), env, {});
  const j = await res.json();
  assert.equal(res.status, 200);
  const vehicleIds = (j.vehicles || []).map((v) => v.vehicle_id ?? v.id).sort();
  assert.deepEqual(vehicleIds, ["vh_cadillac", "vh_tesla"]);
  assert.deepEqual(j.deleted_vehicle_ids, ["vh_ferrari"]);
  assert.equal(
    (j.vehicles || []).some((v) => (v.vehicle_id ?? v.id) === "vh_ferrari"),
    false,
  );
});

test("bootstrap defense-in-depth: a tombstoned vehicle in a legacy stored list is not returned active", async () => {
  const { env, tokenValue } = await makeEnv({
    fleet: {
      version: 1,
      updated_at: new Date().toISOString(),
      // Legacy record where the tombstoned vehicle is still in the array.
      vehicles: [
        vehicle("vh_tesla", "Hoofdwagen", "T-XAA-674"),
        vehicle("vh_ferrari", "Ferrari EV", "T-XAA-673"),
      ],
      deleted_vehicle_ids: { vh_ferrari: "2026-08-16T15:40:00.000Z" },
    },
  });
  const res = await worker.fetch(getBootstrap({ token: tokenValue }), env, {});
  const j = await res.json();
  assert.equal(res.status, 200);
  assert.equal(
    (j.vehicles || []).some((v) => (v.vehicle_id ?? v.id) === "vh_ferrari"),
    false,
  );
  assert.deepEqual(j.deleted_vehicle_ids, ["vh_ferrari"]);
});

test("vehicle delete leaves historical ride/document/Chiron refs untouched", async () => {
  const { env, bookingKv, tokenValue, historicalRideKey, historicalRide } =
    await makeEnv({
      fleet: {
        version: 1,
        updated_at: new Date().toISOString(),
        vehicles: [
          vehicle("vh_tesla", "Hoofdwagen", "T-XAA-674"),
          vehicle("vh_ferrari", "Ferrari EV", "T-XAA-673"),
        ],
      },
    });
  await worker.fetch(
    postFleet({
      token: tokenValue,
      body: {
        tenant_id: TENANT,
        company_id: COMPANY,
        vehicles: [vehicle("vh_tesla", "Hoofdwagen", "T-XAA-674")],
        deleted_vehicle_ids: { vh_ferrari: "2026-08-16T15:40:00.000Z" },
      },
    }),
    env,
    {},
  );
  const afterRaw = bookingKv.store.get(historicalRideKey);
  const after = typeof afterRaw === "string" ? JSON.parse(afterRaw) : afterRaw;
  assert.deepEqual(after, historicalRide);
  assert.equal(after.assigned_vehicle_id, "vh_ferrari");
  assert.equal(after.billit_document_id, "billit_doc_keep");
  assert.equal(after.chiron_trip_ref, "chiron_keep");
});
