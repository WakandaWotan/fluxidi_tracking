// FIELD-RELEASE-BLOCKER-DEVICE-ACTIVATION-AUTH-P0-2
//
// Integration + source-contract tests for
// `POST /admin/company/link-code/create` (the "activation code for a new
// company-owner device" route).
//
// Before this blocker patch the handler called the throwing legacy
// `_requireAdmin(...)` which, absent a compiled-in `ADMIN_TOKEN`, produced
// an unhandled worker exception surfaced by Cloudflare as generic
// Error 1101 HTML — the Flutter client parsed that as a generic
// "Could not generate activation code" failure.
//
// The migrated handler must:
//   - accept a valid company-owner session bearer whose tenant/company
//     match the explicit tenant_id/company_id supplied by the client;
//   - keep backend admin-token compatibility for trusted tooling;
//   - never throw — always return structured JSON 400/401/403;
//   - preserve every existing scope / linking / TTL / single-use invariant;
//   - never log the raw bearer or the full pairing/activation code.
//
// Run:
//   node --test workers/booking/admin_company_link_code_create_auth.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import worker from "./fluxidi_booking_worker.js";

const ROUTE_PATH = "/admin/company/link-code/create";
const HERE = dirname(fileURLToPath(import.meta.url));

// ---------------------------------------------------------------------------
// Shared helpers (kept intentionally close to
// operator_driver_session_mint.test.mjs so future contributors have exactly
// one seeding pattern to follow).
// ---------------------------------------------------------------------------

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

async function makeTwoTenantEnv({ linkingEnabledA = true } = {}) {
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
  const linkA = seedCompanyLinkRecord({
    tenantId: "T1",
    companyId: "C1",
    companyCode: "FLX-A0001",
    linkingEnabled: linkingEnabledA,
  });
  const linkB = seedCompanyLinkRecord({
    tenantId: "T2",
    companyId: "C2",
    companyCode: "FLX-B0001",
  });
  const bookingKv = makeKV({
    [operatorA.key]: operatorA.record,
    [operatorB.key]: operatorB.record,
    [linkA.key]: linkA.record,
    [linkB.key]: linkB.record,
  });
  return {
    env: {
      ADMIN_TOKEN: "backend-admin-token-only-for-internal-tooling",
      BOOKING_KV: bookingKv,
    },
    bookingKv,
    operatorA,
    operatorB,
    linkA,
    linkB,
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

test("company owner in T1/C1 + matching scope → 200 with structured payload", async () => {
  const { env } = await makeTwoTenantEnv();
  const res = await worker.fetch(
    createRequest({
      token: "operator-a-token",
      scopeQuery: { tenant_id: "T1", company_id: "C1" },
      body: {
        tenant_id: "T1",
        company_id: "C1",
        company_code: "FLX-A0001",
      },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 200);
  assert.equal(j.ok, true);
  assert.equal(j.company_code, "FLX-A0001");
  assert.match(String(j.pairing_code || ""), /^\d{6}$/);
  assert.equal(typeof j.challenge_id, "string");
  assert.ok(j.challenge_id.length > 8);
  assert.equal(typeof j.expires_at, "string");
  assert.equal(typeof j.expires_in_seconds, "number");
  assert.ok(j.expires_in_seconds > 0);
});

test("no auth headers → 401 JSON, no throw, no Cloudflare 1101", async () => {
  const { env } = await makeTwoTenantEnv();
  const res = await worker.fetch(
    createRequest({
      scopeQuery: { tenant_id: "T1", company_id: "C1" },
      body: {
        tenant_id: "T1",
        company_id: "C1",
        company_code: "FLX-A0001",
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

test("company owner in T1/C1 with mismatched tenant in scope → 403 JSON", async () => {
  const { env } = await makeTwoTenantEnv();
  const res = await worker.fetch(
    createRequest({
      token: "operator-a-token",
      scopeQuery: { tenant_id: "T2", company_id: "C1" },
      body: {
        tenant_id: "T2",
        company_id: "C1",
        company_code: "FLX-A0001",
      },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 403);
  assert.equal(j.ok, false);
  assert.equal(j.error, "forbidden");
});

test("company owner in T1/C1 with mismatched company in scope → 403 JSON", async () => {
  const { env } = await makeTwoTenantEnv();
  const res = await worker.fetch(
    createRequest({
      token: "operator-a-token",
      scopeQuery: { tenant_id: "T1", company_id: "C2" },
      body: {
        tenant_id: "T1",
        company_id: "C2",
        company_code: "FLX-A0001",
      },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 403);
  assert.equal(j.ok, false);
  assert.equal(j.error, "forbidden");
});

test("company owner in T1/C1 cannot mint using T2/C2 company code → 403 invalid_company_scope_for_code", async () => {
  const { env } = await makeTwoTenantEnv();
  // T1/C1 operator cannot reach the T2/C2 company link record via scope,
  // and even if it could, the record's tenant/company must match the
  // resolved scope.
  const res = await worker.fetch(
    createRequest({
      token: "operator-a-token",
      scopeQuery: { tenant_id: "T1", company_id: "C1" },
      body: {
        tenant_id: "T1",
        company_id: "C1",
        company_code: "FLX-B0001",
      },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 403);
  assert.equal(j.error, "invalid_company_scope_for_code");
});

test("company owner in T1/C1 with linking_enabled=false → 403 invalid_company_scope_for_code (no throw)", async () => {
  const { env } = await makeTwoTenantEnv({ linkingEnabledA: false });
  const res = await worker.fetch(
    createRequest({
      token: "operator-a-token",
      scopeQuery: { tenant_id: "T1", company_id: "C1" },
      body: {
        tenant_id: "T1",
        company_id: "C1",
        company_code: "FLX-A0001",
      },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 403);
  assert.equal(j.error, "invalid_company_scope_for_code");
});

test("backend admin-token path still authorizes internal tooling → 200", async () => {
  const { env } = await makeTwoTenantEnv();
  const res = await worker.fetch(
    createRequest({
      adminToken: "backend-admin-token-only-for-internal-tooling",
      scopeQuery: { tenant_id: "T1", company_id: "C1" },
      body: {
        tenant_id: "T1",
        company_id: "C1",
        company_code: "FLX-A0001",
      },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 200);
  assert.equal(j.ok, true);
  assert.equal(j.company_code, "FLX-A0001");
});

test("company owner in T1/C1 without explicit scope in query or body → 400 missing_tenant_scope", async () => {
  const { env } = await makeTwoTenantEnv();
  const res = await worker.fetch(
    createRequest({
      token: "operator-a-token",
      body: { company_code: "FLX-A0001" },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 400);
  assert.equal(j.error, "missing_tenant_scope");
});

test("two-tenant isolation: operator B session cannot mint for tenant A", async () => {
  const { env } = await makeTwoTenantEnv();
  const res = await worker.fetch(
    createRequest({
      token: "operator-b-token",
      scopeQuery: { tenant_id: "T1", company_id: "C1" },
      body: {
        tenant_id: "T1",
        company_id: "C1",
        company_code: "FLX-A0001",
      },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 403);
  assert.equal(j.error, "forbidden");
});

test("response is always JSON with application/json content-type on every failure branch", async () => {
  const { env } = await makeTwoTenantEnv();
  const cases = [
    { name: "no_auth", req: createRequest({ body: {} }) },
    {
      name: "bad_bearer",
      req: createRequest({ token: "does-not-exist", body: {} }),
    },
    {
      name: "cross_tenant",
      req: createRequest({
        token: "operator-b-token",
        scopeQuery: { tenant_id: "T1", company_id: "C1" },
        body: { tenant_id: "T1", company_id: "C1", company_code: "FLX-A0001" },
      }),
    },
    {
      name: "missing_scope",
      req: createRequest({
        token: "operator-a-token",
        body: { company_code: "FLX-A0001" },
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
// Source-contract regression guards
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

test("handleAdminCompanyLinkCodeCreate no longer calls the throwing _requireAdmin(...) guard", () => {
  const source = readFileSync(
    join(HERE, "fluxidi_booking_worker.js"),
    "utf8",
  );
  const body = extractHandlerBody(source, "handleAdminCompanyLinkCodeCreate");
  // Strip block/line comments so a documenting comment mentioning the
  // deprecated identifier cannot false-positive.
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
  // No literal ADMIN_TOKEN / x-admin-token echoed back in body/log side.
  assert.equal(
    /['"]x-admin-token['"]/.test(stripped),
    false,
    "handler must not reintroduce x-admin-token literal in shipped code",
  );
});
