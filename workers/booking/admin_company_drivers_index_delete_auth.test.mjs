// DRIVER-DELETE-AUTH-P0
//
// Integration tests for POST /admin/company/drivers/index/delete after the
// company-session auth migration (same pattern as driver upsert / link-code).
// Soft-delete semantics: remove from drivers{}, write deleted_drivers tombstone,
// revoke scoped public driver sessions, never touch historical ride/payment
// /Billit/Chiron records.
//
// Run:
//   node --test workers/booking/admin_company_drivers_index_delete_auth.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import worker from "./fluxidi_booking_worker.js";
import { PUBLIC_DRIVER_SESSION_KEY_PREFIX } from "./modules/driver_ops.js";

const ROUTE_PATH = "/admin/company/drivers/index/delete";
const HERE = dirname(fileURLToPath(import.meta.url));

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

async function seedCompanySession({
  tokenValue,
  tenantId,
  companyId,
  companyCode = "",
  companyDisplayName = "",
  expiresAt = new Date(Date.now() + 3_600_000).toISOString(),
}) {
  const hash = await sha256Hex(tokenValue);
  const key = `company_admin:session:${hash}:v1`;
  return {
    key,
    record: {
      role: "company_admin",
      tenant_id: tenantId,
      company_id: companyId,
      company_code: companyCode,
      company_display_name: companyDisplayName,
      expires_at: expiresAt,
    },
  };
}

function driverIndexKey(tenantId, companyId) {
  return `tenant:${tenantId}:company:${companyId}:drivers:index:v1`;
}

function seedDriverIndex({ tenantId, companyId, drivers = {}, deletedDrivers = {} }) {
  return {
    key: driverIndexKey(tenantId, companyId),
    record: {
      drivers,
      deleted_drivers: deletedDrivers,
      updated_at: new Date().toISOString(),
    },
  };
}

async function seedDriverSession({
  tokenValue,
  tenantId,
  companyId,
  driverId,
  expiresAt = new Date(Date.now() + 3_600_000).toISOString(),
}) {
  const hash = await sha256Hex(tokenValue);
  const key = `${PUBLIC_DRIVER_SESSION_KEY_PREFIX}${hash}:v1`;
  return {
    key,
    token: tokenValue,
    record: {
      role: "driver",
      tenant_id: tenantId,
      company_id: companyId,
      driver_id: driverId,
      driver_name: "Wotan",
      issued_at: new Date().toISOString(),
      expires_at: expiresAt,
      link_method: "public_driver_login",
    },
  };
}

async function makeEnv() {
  const operatorA = await seedCompanySession({
    tokenValue: "operator-a-token",
    tenantId: "T1",
    companyId: "C1",
    companyCode: "FLX-A0001",
    companyDisplayName: "Company A BV",
  });
  const operatorB = await seedCompanySession({
    tokenValue: "operator-b-token",
    tenantId: "T2",
    companyId: "C2",
    companyCode: "FLX-B0001",
    companyDisplayName: "Company B BV",
  });
  const indexA = seedDriverIndex({
    tenantId: "T1",
    companyId: "C1",
    drivers: {
      "drv_wotan": {
        driver_id: "drv_wotan",
        display_name: "Wotan",
        is_active: false,
        login_code: "WO-1234",
      },
      "drv_keep": {
        driver_id: "drv_keep",
        display_name: "Keep",
        is_active: true,
        login_code: "KP-9999",
      },
    },
  });
  const indexB = seedDriverIndex({
    tenantId: "T2",
    companyId: "C2",
    drivers: {
      "drv_other": {
        driver_id: "drv_other",
        display_name: "Other",
        is_active: true,
        login_code: "OT-1111",
      },
    },
  });
  const driverSession = await seedDriverSession({
    tokenValue: "driver-wotan-session",
    tenantId: "T1",
    companyId: "C1",
    driverId: "drv_wotan",
  });
  const otherDriverSession = await seedDriverSession({
    tokenValue: "driver-other-session",
    tenantId: "T2",
    companyId: "C2",
    driverId: "drv_other",
  });
  const historicalRideKey = "booking:street_hist_wotan_1:v1";
  const historicalRide = {
    booking_id: "street_hist_wotan_1",
    tenant_id: "T1",
    company_id: "C1",
    assigned_driver_id: "drv_wotan",
    assigned_vehicle_id: "vh_1",
    status: "COMPLETED",
    payment_status: "paid",
    billit_document_id: "billit_doc_keep",
    chiron_trip_ref: "chiron_keep",
  };
  const bookingKv = makeKV({
    [operatorA.key]: operatorA.record,
    [operatorB.key]: operatorB.record,
    [indexA.key]: indexA.record,
    [indexB.key]: indexB.record,
    [driverSession.key]: driverSession.record,
    [otherDriverSession.key]: otherDriverSession.record,
    [historicalRideKey]: historicalRide,
  });
  return {
    env: {
      ADMIN_TOKEN: "backend-admin-token-only-for-internal-tooling",
      BOOKING_KV: bookingKv,
    },
    bookingKv,
    operatorA,
    operatorB,
    indexA,
    indexB,
    driverSession,
    otherDriverSession,
    historicalRideKey,
    historicalRide,
  };
}

function deleteRequest({ token = null, adminToken = null, body }) {
  const headers = { "content-type": "application/json" };
  if (adminToken) headers["x-admin-token"] = adminToken;
  if (token) headers["authorization"] = `Bearer ${token}`;
  return new Request(`https://example.test${ROUTE_PATH}`, {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
}

test("source contract: delete handler uses admin-or-company-session helper", () => {
  const src = readFileSync(join(HERE, "fluxidi_booking_worker.js"), "utf8");
  const start = src.indexOf("async function handleAdminCompanyDriversIndexDelete");
  assert.ok(start > 0);
  const chunk = src.slice(start, start + 3500);
  assert.match(chunk, /_requireAdminOrCompanySessionForExplicitScope/);
  assert.doesNotMatch(chunk, /^\s*_requireAdmin\(request, url, env\);/m);
  assert.match(chunk, /_revokeScopedDriverSessionsInKv/);
  assert.match(chunk, /deleted_drivers/);
});

test("company session can soft-delete its own driver", async () => {
  const { env, bookingKv, indexA, historicalRideKey, historicalRide, driverSession } =
    await makeEnv();
  const beforeRide = bookingKv.store.get(historicalRideKey);
  assert.ok(beforeRide);

  const res = await worker.fetch(
    deleteRequest({
      token: "operator-a-token",
      body: { tenant_id: "T1", company_id: "C1", driver_id: "drv_wotan" },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 200);
  assert.equal(j.ok, true);
  assert.equal(j.deleted, true);
  assert.equal(j.driver_id, "drv_wotan");
  assert.ok(Number(j.revoked_count) >= 1);

  const indexRaw = bookingKv.store.get(indexA.key);
  const index =
    typeof indexRaw === "string" ? JSON.parse(indexRaw) : indexRaw;
  assert.equal(Object.prototype.hasOwnProperty.call(index.drivers, "drv_wotan"), false);
  assert.ok(index.drivers.drv_keep);
  assert.ok(index.deleted_drivers.drv_wotan);

  // Historical ride / payment / Billit / Chiron refs untouched.
  const afterRide = bookingKv.store.get(historicalRideKey);
  const ride =
    typeof afterRide === "string" ? JSON.parse(afterRide) : afterRide;
  assert.deepEqual(ride, historicalRide);
  assert.equal(ride.assigned_driver_id, "drv_wotan");
  assert.equal(ride.billit_document_id, "billit_doc_keep");
  assert.equal(ride.chiron_trip_ref, "chiron_keep");

  // Existing driver session revoked.
  assert.equal(bookingKv.store.has(driverSession.key), false);
});

test("admin token path remains supported", async () => {
  const { env, bookingKv, indexA } = await makeEnv();
  const res = await worker.fetch(
    deleteRequest({
      adminToken: "backend-admin-token-only-for-internal-tooling",
      body: { tenant_id: "T1", company_id: "C1", driver_id: "drv_wotan" },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 200);
  assert.equal(j.ok, true);
  assert.equal(j.deleted, true);
  const indexRaw = bookingKv.store.get(indexA.key);
  const index =
    typeof indexRaw === "string" ? JSON.parse(indexRaw) : indexRaw;
  assert.ok(index.deleted_drivers.drv_wotan);
});

test("no auth → 401 unauthorized", async () => {
  const { env } = await makeEnv();
  const res = await worker.fetch(
    deleteRequest({
      body: { tenant_id: "T1", company_id: "C1", driver_id: "drv_wotan" },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 401);
  assert.equal(j.ok, false);
  assert.equal(j.error, "unauthorized");
});

test("company A cannot delete company B driver (cross-company)", async () => {
  const { env, bookingKv, indexB, otherDriverSession } = await makeEnv();
  const res = await worker.fetch(
    deleteRequest({
      token: "operator-a-token",
      body: { tenant_id: "T2", company_id: "C2", driver_id: "drv_other" },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 403);
  assert.equal(j.error, "forbidden");

  const indexRaw = bookingKv.store.get(indexB.key);
  const index =
    typeof indexRaw === "string" ? JSON.parse(indexRaw) : indexRaw;
  assert.ok(index.drivers.drv_other);
  assert.equal(bookingKv.store.has(otherDriverSession.key), true);
});

test("tenant A cannot delete tenant B driver via mismatched scope", async () => {
  const { env, bookingKv, indexB } = await makeEnv();
  const res = await worker.fetch(
    deleteRequest({
      token: "operator-a-token",
      body: { tenant_id: "T1", company_id: "C1", driver_id: "drv_other" },
    }),
    env,
    {},
  );
  // Own-scope delete of unknown id still tombstones the id (idempotent soft
  // delete) but must never mutate tenant B's index.
  assert.equal(res.status, 200);
  const indexRaw = bookingKv.store.get(indexB.key);
  const index =
    typeof indexRaw === "string" ? JSON.parse(indexRaw) : indexRaw;
  assert.ok(index.drivers.drv_other);
  assert.equal(
    Object.prototype.hasOwnProperty.call(index.deleted_drivers || {}, "drv_other"),
    false,
  );
});

test("tombstoned driver cannot re-login via public driver login index", async () => {
  const { env, bookingKv, indexA } = await makeEnv();
  await worker.fetch(
    deleteRequest({
      token: "operator-a-token",
      body: { tenant_id: "T1", company_id: "C1", driver_id: "drv_wotan" },
    }),
    env,
    {},
  );
  const indexRaw = bookingKv.store.get(indexA.key);
  const index =
    typeof indexRaw === "string" ? JSON.parse(indexRaw) : indexRaw;
  // Login scans active drivers{} only — tombstoned id is gone.
  assert.equal(Object.prototype.hasOwnProperty.call(index.drivers, "drv_wotan"), false);
  assert.ok(index.deleted_drivers.drv_wotan);
});

test("idempotent delete of already-absent driver still writes tombstone", async () => {
  const { env, bookingKv, indexA } = await makeEnv();
  const res = await worker.fetch(
    deleteRequest({
      token: "operator-a-token",
      body: { tenant_id: "T1", company_id: "C1", driver_id: "drv_never_existed" },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 200);
  assert.equal(j.deleted, false);
  const indexRaw = bookingKv.store.get(indexA.key);
  const index =
    typeof indexRaw === "string" ? JSON.parse(indexRaw) : indexRaw;
  assert.ok(index.deleted_drivers.drv_never_existed);
  assert.ok(index.drivers.drv_wotan);
});
