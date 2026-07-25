// SECURITY-REMOVE-CLIENT-ADMIN-TOKEN-P0-1 (Field Failure Fix, Commit 1)
//
// Integration tests for `POST /driver/session/mint-for-operator`. Proves:
//   - the route is authenticated with the company-session bearer only (no
//     ADMIN_TOKEN path, no client-supplied scope is authoritative),
//   - the target driver must belong to the caller's own tenant/company and
//     must be active + non-tombstoned,
//   - conflicting client-supplied tenant/company fail 403 (never masked as
//     404 or 200),
//   - a successful mint stores a KV record byte-compatible with the normal
//     public driver-session shape so downstream handlers can consume it,
//   - the record carries the `operator_mint` origin so audit trails can
//     distinguish operator mints from organic driver logins,
//   - the TTL is bounded by env `OPERATOR_MINT_TTL_SECONDS` (default 1h,
//     hard-capped at 24h, hard-floored at 5m),
//   - two mints produce distinct tokens (no reuse).
//
// Run:
//   node --test workers/booking/operator_driver_session_mint.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import worker from "./fluxidi_booking_worker.js";

const MINT_PATH = "/driver/session/mint-for-operator";

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
    async list() {
      return {
        keys: [...store.keys()].map((name) => ({ name })),
        list_complete: true,
      };
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

function seedDriverIndex({
  tenantId,
  companyId,
  drivers = {},
  deletedDrivers = {},
}) {
  return {
    key: driverIndexKey(tenantId, companyId),
    record: {
      drivers,
      deleted_drivers: deletedDrivers,
      updated_at: new Date().toISOString(),
    },
  };
}

async function makeTwoTenantEnv({
  expireOperatorA = false,
  driverAliceActive = true,
  aliceTombstoned = false,
  bobActive = true,
  aliceAssignedVehicle = "V-alice",
} = {}) {
  const operatorA = await seedCompanySession({
    tokenValue: "operator-a-token",
    tenantId: "T1",
    companyId: "C1",
    companyCode: "COMP-A",
    companyDisplayName: "Company A BV",
    ...(expireOperatorA
      ? { expiresAt: new Date(Date.now() - 60_000).toISOString() }
      : {}),
  });
  const operatorB = await seedCompanySession({
    tokenValue: "operator-b-token",
    tenantId: "T2",
    companyId: "C2",
    companyCode: "COMP-B",
    companyDisplayName: "Company B BV",
  });
  const driverIndexA = seedDriverIndex({
    tenantId: "T1",
    companyId: "C1",
    drivers: {
      "D-alice": {
        driver_id: "D-alice",
        display_name: "Alice Driver",
        is_active: driverAliceActive,
        assigned_vehicle_id: aliceAssignedVehicle,
      },
    },
    deletedDrivers: aliceTombstoned
      ? { "D-alice": new Date().toISOString() }
      : {},
  });
  const driverIndexB = seedDriverIndex({
    tenantId: "T2",
    companyId: "C2",
    drivers: {
      "D-bob": {
        driver_id: "D-bob",
        display_name: "Bob Driver",
        is_active: bobActive,
      },
    },
  });
  const bookingKv = makeKV({
    [operatorA.key]: operatorA.record,
    [operatorB.key]: operatorB.record,
    [driverIndexA.key]: driverIndexA.record,
    [driverIndexB.key]: driverIndexB.record,
  });
  return {
    env: {
      ADMIN_TOKEN: "unused-admin-token",
      BOOKING_KV: bookingKv,
    },
    bookingKv,
    operatorA,
    operatorB,
  };
}

function mintRequest({ token = null, adminToken = null, body }) {
  const headers = { "content-type": "application/json" };
  if (adminToken) headers["x-admin-token"] = adminToken;
  if (token) headers["authorization"] = `Bearer ${token}`;
  return new Request(`https://booking.internal${MINT_PATH}`, {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
}

test("no auth → 401", async () => {
  const { env } = await makeTwoTenantEnv();
  const res = await worker.fetch(
    mintRequest({ body: { target_driver_id: "D-alice" } }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 401);
  assert.equal(j.error, "unauthorized");
});

test("random bearer → 401", async () => {
  const { env } = await makeTwoTenantEnv();
  const res = await worker.fetch(
    mintRequest({
      token: "does-not-exist",
      body: { target_driver_id: "D-alice" },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 401);
  assert.equal(j.error, "unauthorized");
});

test("ADMIN_TOKEN header does not authorize this route (defense in depth)", async () => {
  const { env } = await makeTwoTenantEnv();
  const res = await worker.fetch(
    mintRequest({
      adminToken: "unused-admin-token",
      body: { target_driver_id: "D-alice" },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 401);
  assert.equal(j.error, "unauthorized");
});

test("expired company session → 401", async () => {
  const { env } = await makeTwoTenantEnv({ expireOperatorA: true });
  const res = await worker.fetch(
    mintRequest({
      token: "operator-a-token",
      body: { target_driver_id: "D-alice" },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 401);
  assert.equal(j.error, "unauthorized");
});

test("company owner in T1/C1 mints for own driver Alice → 200 + KV record shape", async () => {
  const { env, bookingKv } = await makeTwoTenantEnv();
  const res = await worker.fetch(
    mintRequest({
      token: "operator-a-token",
      body: { target_driver_id: "D-alice" },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 200);
  assert.equal(j.ok, true);
  assert.equal(j.origin, "operator_mint");
  assert.equal(j.link_method, "operator_mint");
  assert.equal(j.role, "driver");
  assert.equal(j.tenant_id, "T1");
  assert.equal(j.company_id, "C1");
  assert.equal(typeof j.driver_session_token, "string");
  assert.ok(j.driver_session_token.startsWith("dst_op_"));
  assert.equal(j.driver_session_token, j.driverSessionToken);
  assert.equal(typeof j.expires_at, "string");
  assert.equal(j.expires_at, j.driver_session_expires_at);
  assert.equal(j.expires_at, j.driverSessionExpiresAtUtc);
  assert.equal(typeof j.expires_in, "number");
  assert.equal(j.expires_in, j.expiresIn);
  assert.equal(j.expires_in, 60 * 60);
  assert.equal(j.driver.driver_id, "D-alice");
  assert.equal(j.driver.driver_name, "Alice Driver");
  assert.equal(j.driver.assigned_vehicle_id, "V-alice");

  const tokenHash = await sha256Hex(j.driver_session_token);
  const kvKey = `public_driver:session:${tokenHash}:v1`;
  const rawStored = bookingKv.store.get(kvKey);
  assert.ok(rawStored, "operator mint must write a KV record");
  const stored = typeof rawStored === "string" ? JSON.parse(rawStored) : rawStored;
  assert.equal(stored.role, "driver");
  assert.equal(stored.tenant_id, "T1");
  assert.equal(stored.company_id, "C1");
  assert.equal(stored.driver_id, "D-alice");
  assert.equal(stored.driver_name, "Alice Driver");
  assert.equal(stored.assigned_vehicle_id, "V-alice");
  assert.equal(stored.link_method, "operator_mint");
  assert.equal(stored.origin, "operator_mint");
  assert.equal(typeof stored.minted_by_company_session_hash, "string");
  assert.ok(stored.minted_by_company_session_hash.length >= 32);
});

test("company owner in T1/C1 with client-supplied tenant=T2 in body → 403", async () => {
  const { env, bookingKv } = await makeTwoTenantEnv();
  const before = bookingKv.store.size;
  const res = await worker.fetch(
    mintRequest({
      token: "operator-a-token",
      body: { target_driver_id: "D-alice", tenant_id: "T2" },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 403);
  assert.equal(j.error, "forbidden");
  assert.equal(bookingKv.store.size, before, "403 must not write any KV records");
});

test("company owner in T1/C1 with client-supplied company=C2 in body → 403", async () => {
  const { env, bookingKv } = await makeTwoTenantEnv();
  const before = bookingKv.store.size;
  const res = await worker.fetch(
    mintRequest({
      token: "operator-a-token",
      body: { target_driver_id: "D-alice", company_id: "C2" },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 403);
  assert.equal(j.error, "forbidden");
  assert.equal(bookingKv.store.size, before, "403 must not write any KV records");
});

test("company owner in T1/C1 mints for driver in C2 (Bob) → 404, not 403 (avoids info leak)", async () => {
  const { env, bookingKv } = await makeTwoTenantEnv();
  const before = bookingKv.store.size;
  const res = await worker.fetch(
    mintRequest({
      token: "operator-a-token",
      body: { target_driver_id: "D-bob" },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 404);
  assert.equal(j.error, "driver_not_found");
  assert.equal(bookingKv.store.size, before, "404 must not write any KV records");
});

test("missing target_driver_id → 400", async () => {
  const { env } = await makeTwoTenantEnv();
  const res = await worker.fetch(
    mintRequest({ token: "operator-a-token", body: {} }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 400);
  assert.equal(j.error, "invalid_driver_id");
});

test("tombstoned driver → 404 (not 403, matches non-existent driver behavior)", async () => {
  const { env } = await makeTwoTenantEnv({ aliceTombstoned: true });
  const res = await worker.fetch(
    mintRequest({
      token: "operator-a-token",
      body: { target_driver_id: "D-alice" },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 404);
  assert.equal(j.error, "driver_not_found");
});

test("inactive driver → 403 driver_inactive", async () => {
  const { env } = await makeTwoTenantEnv({ driverAliceActive: false });
  const res = await worker.fetch(
    mintRequest({
      token: "operator-a-token",
      body: { target_driver_id: "D-alice" },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 403);
  assert.equal(j.error, "driver_inactive");
});

test("two mints for the same driver yield distinct tokens", async () => {
  const { env, bookingKv } = await makeTwoTenantEnv();
  const first = await worker.fetch(
    mintRequest({
      token: "operator-a-token",
      body: { target_driver_id: "D-alice" },
    }),
    env,
    {},
  );
  const second = await worker.fetch(
    mintRequest({
      token: "operator-a-token",
      body: { target_driver_id: "D-alice" },
    }),
    env,
    {},
  );
  assert.equal(first.status, 200);
  assert.equal(second.status, 200);
  const j1 = await first.json();
  const j2 = await second.json();
  assert.notEqual(j1.driver_session_token, j2.driver_session_token);
  const h1 = await sha256Hex(j1.driver_session_token);
  const h2 = await sha256Hex(j2.driver_session_token);
  assert.ok(
    bookingKv.store.has(`public_driver:session:${h1}:v1`),
    "first token record present",
  );
  assert.ok(
    bookingKv.store.has(`public_driver:session:${h2}:v1`),
    "second token record present",
  );
});

test("body without tenant/company keys → derives scope from company session (200)", async () => {
  const { env } = await makeTwoTenantEnv();
  const res = await worker.fetch(
    mintRequest({
      token: "operator-a-token",
      body: { target_driver_id: "D-alice" },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 200);
  assert.equal(j.tenant_id, "T1");
  assert.equal(j.company_id, "C1");
});

test("env OPERATOR_MINT_TTL_SECONDS override respected within bounds", async () => {
  const { env } = await makeTwoTenantEnv();
  env.OPERATOR_MINT_TTL_SECONDS = 30 * 60;
  const res = await worker.fetch(
    mintRequest({
      token: "operator-a-token",
      body: { target_driver_id: "D-alice" },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 200);
  assert.equal(j.expires_in, 30 * 60);
});

test("env OPERATOR_MINT_TTL_SECONDS above 24h is clamped to 24h", async () => {
  const { env } = await makeTwoTenantEnv();
  env.OPERATOR_MINT_TTL_SECONDS = 999_999;
  const res = await worker.fetch(
    mintRequest({
      token: "operator-a-token",
      body: { target_driver_id: "D-alice" },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 200);
  assert.equal(j.expires_in, 24 * 60 * 60);
});

test("env OPERATOR_MINT_TTL_SECONDS below 5 minutes is clamped to 5 minutes", async () => {
  const { env } = await makeTwoTenantEnv();
  env.OPERATOR_MINT_TTL_SECONDS = 1;
  const res = await worker.fetch(
    mintRequest({
      token: "operator-a-token",
      body: { target_driver_id: "D-alice" },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 200);
  assert.equal(j.expires_in, 5 * 60);
});

test("GET on the mint route → 405", async () => {
  const { env } = await makeTwoTenantEnv();
  const req = new Request(`https://booking.internal${MINT_PATH}`, {
    method: "GET",
    headers: { authorization: "Bearer operator-a-token" },
  });
  const res = await worker.fetch(req, env, {});
  const j = await res.json();
  assert.equal(res.status, 405);
  assert.equal(j.error, "method_not_allowed");
});
