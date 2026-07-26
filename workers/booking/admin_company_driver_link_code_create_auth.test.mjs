// FIELD-RELEASE-BLOCKER-DEVICE-ACTIVATION-AUTH-P0-2
//
// Integration + source-contract tests for
// `POST /admin/company/driver-link-code/create` (the "activation code /
// pairing QR for a new driver device" route).
//
// Same migration as `handleAdminCompanyLinkCodeCreate`: replace the
// throwing legacy `_requireAdmin(...)` with the existing
// `_requireAdminOrCompanySessionForExplicitScope(...)` helper. The driver
// variant additionally requires an ACTIVE driver in the caller's tenant/
// company scope, so we exercise:
//   - unknown driver_id → 404 driver_not_found_or_inactive
//   - inactive driver → 404 driver_not_found_or_inactive
//   - tombstoned/deleted driver id in another shape → rejected
//   - malformed driver_id → 400 invalid_driver_id
// on top of the same auth invariants exercised in
// admin_company_link_code_create_auth.test.mjs.
//
// Run:
//   node --test workers/booking/admin_company_driver_link_code_create_auth.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import worker from "./fluxidi_booking_worker.js";

const ROUTE_PATH = "/admin/company/driver-link-code/create";
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

function seedCompanyLinkRecord({
  tenantId,
  companyId,
  companyCode,
  linkingEnabled = true,
}) {
  const key = `company_link:index:code:${companyCode}:v1`;
  return {
    key,
    record: {
      company_code: companyCode,
      tenant_id: tenantId,
      company_id: companyId,
      linking_enabled: linkingEnabled,
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    },
  };
}

function seedDriverIndex({ tenantId, companyId, drivers = {} }) {
  return {
    key: `tenant:${tenantId}:company:${companyId}:drivers:index:v1`,
    record: {
      drivers,
      deleted_drivers: {},
      updated_at: new Date().toISOString(),
    },
  };
}

async function makeEnv({
  aliceActive = true,
  aliceAssignedVehicle = "V-alice",
} = {}) {
  const operatorA = await seedCompanySession({
    tokenValue: "operator-a-token",
    tenantId: "T1",
    companyId: "C1",
    companyCode: "FLX-A0001",
  });
  const operatorB = await seedCompanySession({
    tokenValue: "operator-b-token",
    tenantId: "T2",
    companyId: "C2",
    companyCode: "FLX-B0001",
  });
  const linkA = seedCompanyLinkRecord({
    tenantId: "T1",
    companyId: "C1",
    companyCode: "FLX-A0001",
  });
  const linkB = seedCompanyLinkRecord({
    tenantId: "T2",
    companyId: "C2",
    companyCode: "FLX-B0001",
  });
  const driverIndexA = seedDriverIndex({
    tenantId: "T1",
    companyId: "C1",
    drivers: {
      "D-alice": {
        driver_id: "D-alice",
        display_name: "Alice Driver",
        employee_number: "E-42",
        is_active: aliceActive,
        assigned_vehicle_id: aliceAssignedVehicle,
      },
      "D-inactive": {
        driver_id: "D-inactive",
        display_name: "Formerly Active",
        is_active: false,
      },
    },
  });
  const driverIndexB = seedDriverIndex({
    tenantId: "T2",
    companyId: "C2",
    drivers: {
      "D-bob": {
        driver_id: "D-bob",
        display_name: "Bob Driver",
        is_active: true,
      },
    },
  });
  const bookingKv = makeKV({
    [operatorA.key]: operatorA.record,
    [operatorB.key]: operatorB.record,
    [linkA.key]: linkA.record,
    [linkB.key]: linkB.record,
    [driverIndexA.key]: driverIndexA.record,
    [driverIndexB.key]: driverIndexB.record,
  });
  return {
    env: {
      ADMIN_TOKEN: "backend-admin-token-only-for-internal-tooling",
      BOOKING_KV: bookingKv,
    },
    bookingKv,
    operatorA,
    operatorB,
  };
}

function createRequest({
  token = null,
  adminToken = null,
  body,
  scopeQuery = null,
}) {
  const headers = { "content-type": "application/json" };
  if (adminToken) headers["x-admin-token"] = adminToken;
  if (token) headers["authorization"] = `Bearer ${token}`;
  const query = scopeQuery
    ? `?tenant_id=${encodeURIComponent(scopeQuery.tenant_id)}&company_id=${encodeURIComponent(scopeQuery.company_id)}`
    : "";
  return new Request(`https://booking.internal${ROUTE_PATH}${query}`, {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
}

// ---------------------------------------------------------------------------
// Integration tests
// ---------------------------------------------------------------------------

test("company owner + matching scope + active driver → 200 with pairing_code + challenge_id", async () => {
  const { env } = await makeEnv();
  const res = await worker.fetch(
    createRequest({
      token: "operator-a-token",
      scopeQuery: { tenant_id: "T1", company_id: "C1" },
      body: {
        tenant_id: "T1",
        company_id: "C1",
        company_code: "FLX-A0001",
        driver_id: "D-alice",
      },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 200);
  assert.equal(j.ok, true);
  assert.equal(j.company_code, "FLX-A0001");
  assert.equal(j.driver_id, "D-alice");
  assert.match(String(j.pairing_code || ""), /^[A-Z0-9]{4,10}$/);
  assert.equal(typeof j.challenge_id, "string");
  assert.ok(j.challenge_id.length > 8);
  assert.equal(typeof j.expires_at, "string");
  assert.equal(typeof j.expires_in_seconds, "number");
  assert.ok(j.expires_in_seconds > 0);
});

test("no auth headers → 401 JSON, no throw, no Cloudflare 1101", async () => {
  const { env } = await makeEnv();
  const res = await worker.fetch(
    createRequest({
      scopeQuery: { tenant_id: "T1", company_id: "C1" },
      body: {
        tenant_id: "T1",
        company_id: "C1",
        company_code: "FLX-A0001",
        driver_id: "D-alice",
      },
    }),
    env,
    {},
  );
  assert.equal(res.status, 401);
  assert.match(String(res.headers.get("content-type") || ""), /^application\/json\b/);
  const j = await res.json();
  assert.equal(j.ok, false);
  assert.equal(j.error, "unauthorized");
});

test("tenant mismatch → 403 JSON", async () => {
  const { env } = await makeEnv();
  const res = await worker.fetch(
    createRequest({
      token: "operator-a-token",
      scopeQuery: { tenant_id: "T2", company_id: "C1" },
      body: {
        tenant_id: "T2",
        company_id: "C1",
        company_code: "FLX-A0001",
        driver_id: "D-alice",
      },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 403);
  assert.equal(j.error, "forbidden");
});

test("company mismatch → 403 JSON", async () => {
  const { env } = await makeEnv();
  const res = await worker.fetch(
    createRequest({
      token: "operator-a-token",
      scopeQuery: { tenant_id: "T1", company_id: "C2" },
      body: {
        tenant_id: "T1",
        company_id: "C2",
        company_code: "FLX-A0001",
        driver_id: "D-alice",
      },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 403);
  assert.equal(j.error, "forbidden");
});

test("inactive driver → 404 driver_not_found_or_inactive", async () => {
  const { env } = await makeEnv();
  const res = await worker.fetch(
    createRequest({
      token: "operator-a-token",
      scopeQuery: { tenant_id: "T1", company_id: "C1" },
      body: {
        tenant_id: "T1",
        company_id: "C1",
        company_code: "FLX-A0001",
        driver_id: "D-inactive",
      },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 404);
  assert.equal(j.error, "driver_not_found_or_inactive");
});

test("unknown driver_id → 404 driver_not_found_or_inactive", async () => {
  const { env } = await makeEnv();
  const res = await worker.fetch(
    createRequest({
      token: "operator-a-token",
      scopeQuery: { tenant_id: "T1", company_id: "C1" },
      body: {
        tenant_id: "T1",
        company_id: "C1",
        company_code: "FLX-A0001",
        driver_id: "D-does-not-exist",
      },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 404);
  assert.equal(j.error, "driver_not_found_or_inactive");
});

test("malformed driver_id (unsafe chars) → 400 invalid_driver_id", async () => {
  const { env } = await makeEnv();
  const res = await worker.fetch(
    createRequest({
      token: "operator-a-token",
      scopeQuery: { tenant_id: "T1", company_id: "C1" },
      body: {
        tenant_id: "T1",
        company_id: "C1",
        company_code: "FLX-A0001",
        driver_id: "D bob; drop table drivers",
      },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 400);
  assert.equal(j.error, "invalid_driver_id");
});

test("two-tenant isolation: operator B session cannot mint a driver code for tenant A", async () => {
  const { env } = await makeEnv();
  const res = await worker.fetch(
    createRequest({
      token: "operator-b-token",
      scopeQuery: { tenant_id: "T1", company_id: "C1" },
      body: {
        tenant_id: "T1",
        company_id: "C1",
        company_code: "FLX-A0001",
        driver_id: "D-alice",
      },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 403);
  assert.equal(j.error, "forbidden");
});

test("two-tenant isolation: operator A cannot mint for driver D-bob living in tenant B", async () => {
  const { env } = await makeEnv();
  const res = await worker.fetch(
    createRequest({
      token: "operator-a-token",
      scopeQuery: { tenant_id: "T1", company_id: "C1" },
      body: {
        tenant_id: "T1",
        company_id: "C1",
        company_code: "FLX-A0001",
        driver_id: "D-bob",
      },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 404);
  assert.equal(j.error, "driver_not_found_or_inactive");
});

test("backend admin-token path still authorizes internal tooling → 200", async () => {
  const { env } = await makeEnv();
  const res = await worker.fetch(
    createRequest({
      adminToken: "backend-admin-token-only-for-internal-tooling",
      scopeQuery: { tenant_id: "T1", company_id: "C1" },
      body: {
        tenant_id: "T1",
        company_id: "C1",
        company_code: "FLX-A0001",
        driver_id: "D-alice",
      },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 200);
  assert.equal(j.ok, true);
  assert.equal(j.driver_id, "D-alice");
});

test("response is always JSON with application/json content-type on every failure branch", async () => {
  const { env } = await makeEnv();
  const cases = [
    { name: "no_auth", req: createRequest({ body: {} }) },
    {
      name: "cross_tenant",
      req: createRequest({
        token: "operator-b-token",
        scopeQuery: { tenant_id: "T1", company_id: "C1" },
        body: {
          tenant_id: "T1",
          company_id: "C1",
          company_code: "FLX-A0001",
          driver_id: "D-alice",
        },
      }),
    },
    {
      name: "missing_scope",
      req: createRequest({
        token: "operator-a-token",
        body: {
          company_code: "FLX-A0001",
          driver_id: "D-alice",
        },
      }),
    },
    {
      name: "unknown_driver",
      req: createRequest({
        token: "operator-a-token",
        scopeQuery: { tenant_id: "T1", company_id: "C1" },
        body: {
          tenant_id: "T1",
          company_id: "C1",
          company_code: "FLX-A0001",
          driver_id: "D-nope",
        },
      }),
    },
  ];
  for (const c of cases) {
    const res = await worker.fetch(c.req, env, {});
    assert.match(
      String(res.headers.get("content-type") || ""),
      /^application\/json\b/,
      `${c.name}: content-type must be application/json (never HTML)`,
    );
    const j = await res.json();
    assert.equal(j.ok, false, `${c.name}: ok must be false`);
    assert.ok(res.status >= 400 && res.status < 500, `${c.name}: status ${res.status}`);
  }
});

// ---------------------------------------------------------------------------
// Source-contract regression guard
// ---------------------------------------------------------------------------

function extractHandlerBody(source, handlerName) {
  const openRe = new RegExp(`async function ${handlerName}\\s*\\(`);
  const openMatch = openRe.exec(source);
  assert.ok(openMatch, `handler ${handlerName} not found`);
  let idx = source.indexOf("{", openMatch.index);
  assert.ok(idx > 0, `handler ${handlerName} opening brace not found`);
  let depth = 0;
  for (let i = idx; i < source.length; i++) {
    const ch = source[i];
    if (ch === "{") depth++;
    else if (ch === "}") {
      depth--;
      if (depth === 0) {
        return source.slice(idx, i + 1);
      }
    }
  }
  throw new Error(`handler ${handlerName} closing brace not found`);
}

test("handleAdminCompanyDriverLinkCodeCreate no longer calls the throwing _requireAdmin(...) guard", () => {
  const source = readFileSync(
    join(HERE, "fluxidi_booking_worker.js"),
    "utf8",
  );
  const body = extractHandlerBody(
    source,
    "handleAdminCompanyDriverLinkCodeCreate",
  );
  const stripped = body
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/(^|[^:])\/\/[^\n]*/g, "$1");
  assert.equal(
    /\b_requireAdmin\s*\(/.test(stripped),
    false,
    "handler must not call the throwing _requireAdmin(...) in executable code",
  );
  assert.ok(
    /_requireAdminOrCompanySessionForExplicitScope\s*\(/.test(stripped),
    "handler must call _requireAdminOrCompanySessionForExplicitScope",
  );
  assert.equal(
    /['"]x-admin-token['"]/.test(stripped),
    false,
    "handler must not reintroduce x-admin-token literal in shipped code",
  );
});
