// CHIRON-P0-2A — Compliance-worker direct auth tests for the three
// read-only routes migrated from `ensureAuthorized` to
// `ensureAuthorizedOrInternalProxy`:
//
//   POST /admin/chiron/readiness
//   GET  /admin/chiron/score-summary
//   GET  /compliance/events/recent
//
// The tests hit the compliance worker directly (no booking-worker in the
// middle) and prove every allowed and every rejected path of
// `ensureAuthorizedOrInternalProxy`:
//   - direct admin bearer with correct scope   → 200
//   - direct admin bearer without scope        → 400 (missing_scope)
//   - matching internal-proxy scope headers    → 200
//   - mismatched internal-proxy scope headers  → 403 proxy_scope_mismatch
//   - missing internal-proxy scope headers     → 400 missing_proxy_scope
//   - no auth at all                            → 401
//   - proxy token wrong                         → 401
//   - two-tenant data isolation via KV prefix   → A never sees B events
//
// Run:
//   node --test workers/compliance/chiron_readonly_internal_proxy_auth.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import complianceWorker from "./fluxidi_compliance_worker.js";

const HERE = dirname(fileURLToPath(import.meta.url));
const ADMIN_TOKEN = "backend-admin-token-only-for-internal-tooling";
const PROXY_MODE = "booking_worker_v1";

// ---------------------------------------------------------------------------
// KV mock
// ---------------------------------------------------------------------------
function makeKV(seed = {}) {
  const store = new Map(Object.entries(seed));
  return {
    store,
    async get(key) {
      return store.has(key) ? store.get(key) : null;
    },
    async put(key, val) {
      store.set(key, val);
    },
    async delete(key) {
      store.delete(key);
    },
    async list(opts = {}) {
      const prefix = String(opts.prefix || "");
      const all = [...store.keys()].filter((name) =>
        prefix ? name.startsWith(prefix) : true,
      );
      return { keys: all.map((name) => ({ name })), list_complete: true };
    },
  };
}

function seg(v) {
  return String(v).toLowerCase().replace(/[^a-z0-9._-]/g, "_");
}

function eventKey({ tenantId, companyId, eventId, tsMs }) {
  const t = new Date(tsMs);
  const year = String(t.getUTCFullYear()).padStart(4, "0");
  const month = String(t.getUTCMonth() + 1).padStart(2, "0");
  const day = String(t.getUTCDate()).padStart(2, "0");
  return `compliance_event_v1/tenant/${seg(tenantId)}/company/${seg(companyId)}/${year}/${month}/${day}/${tsMs}_${eventId}`;
}

function makeEvent({ tenantId, companyId, eventId, tsIso }) {
  return {
    event_id: eventId,
    event_type: "ride_stop",
    schema_version: "1",
    tenant_id: tenantId,
    company_id: companyId,
    created_at_utc: tsIso,
    timestamps: { recorded_at_utc: tsIso, event_at_utc: tsIso },
    driver: { driver_id: `${companyId}-driver-1` },
    fare: { total: 10 },
  };
}

function makeTwoTenantEnv() {
  const seed = {};
  const eventsByTenant = { "T1|C1": [], "T2|C2": [] };
  const now = Date.now();
  for (const [tenantId, companyId, bucket] of [
    ["T1", "C1", "T1|C1"],
    ["T2", "C2", "T2|C2"],
  ]) {
    for (let i = 0; i < 2; i++) {
      const tsMs = now - i * 60_000;
      const tsIso = new Date(tsMs).toISOString();
      const eventId = `${companyId}-evt-${i}`;
      seed[eventKey({ tenantId, companyId, eventId, tsMs })] = JSON.stringify(
        makeEvent({ tenantId, companyId, eventId, tsIso }),
      );
      eventsByTenant[bucket].push(eventId);
    }
  }
  const kv = makeKV(seed);
  return {
    env: {
      ADMIN_TOKEN,
      COMPLIANCE_ADMIN_TOKEN: ADMIN_TOKEN,
      COMPLIANCE_KV: kv,
    },
    kv,
    eventsByTenant,
  };
}

function reqDirectAdmin({ path, method = "GET", scope, body = null }) {
  const url = new URL(`https://compliance.internal${path}`);
  if (scope) {
    url.searchParams.set("tenant_id", scope.tenant_id);
    url.searchParams.set("company_id", scope.company_id);
  }
  const headers = { authorization: `Bearer ${ADMIN_TOKEN}` };
  if (method === "POST") headers["content-type"] = "application/json";
  return new Request(url.toString(), {
    method,
    headers,
    body: body !== null ? JSON.stringify(body) : undefined,
  });
}

function reqProxy({
  path,
  method = "GET",
  scope,
  proxyScope = null,
  body = null,
  omitProxyTenant = false,
  omitProxyCompany = false,
  overrideProxyToken = null,
  omitProxyToken = false,
}) {
  const url = new URL(`https://compliance.internal${path}`);
  if (scope) {
    url.searchParams.set("tenant_id", scope.tenant_id);
    url.searchParams.set("company_id", scope.company_id);
  }
  const proxy = proxyScope || scope;
  const headers = {
    "x-fluxidi-internal-proxy": PROXY_MODE,
  };
  if (!omitProxyToken) {
    headers["x-fluxidi-proxy-token"] =
      overrideProxyToken != null ? overrideProxyToken : ADMIN_TOKEN;
  }
  if (proxy && !omitProxyTenant) {
    headers["x-fluxidi-proxy-tenant-id"] = proxy.tenant_id;
  }
  if (proxy && !omitProxyCompany) {
    headers["x-fluxidi-proxy-company-id"] = proxy.company_id;
  }
  if (method === "POST") headers["content-type"] = "application/json";
  return new Request(url.toString(), {
    method,
    headers,
    body: body !== null ? JSON.stringify(body) : undefined,
  });
}

// ---------------------------------------------------------------------------
// score-summary (GET)
// ---------------------------------------------------------------------------

test("score-summary: direct admin + T1 scope → 200", async () => {
  const { env } = makeTwoTenantEnv();
  const res = await complianceWorker.fetch(
    reqDirectAdmin({
      path: "/admin/chiron/score-summary",
      scope: { tenant_id: "T1", company_id: "C1" },
    }),
    env,
  );
  assert.equal(res.status, 200);
});

test("score-summary: internal proxy with matching T1 scope → 200 and only T1 data", async () => {
  const { env, eventsByTenant } = makeTwoTenantEnv();
  const res = await complianceWorker.fetch(
    reqProxy({
      path: "/admin/chiron/score-summary",
      scope: { tenant_id: "T1", company_id: "C1" },
    }),
    env,
  );
  assert.equal(res.status, 200);
  const j = await res.json();
  const seenIds = new Set(
    (j.newest_events || []).map((e) => String(e.event_id || "")),
  );
  const aIds = new Set(eventsByTenant["T1|C1"]);
  const bIds = new Set(eventsByTenant["T2|C2"]);
  for (const id of seenIds) {
    assert.ok(aIds.has(id), `unexpected non-A event surfaced: ${id}`);
    assert.equal(bIds.has(id), false);
  }
});

test("score-summary: internal proxy scope mismatch (URL T1 vs header T2) → 403", async () => {
  const { env } = makeTwoTenantEnv();
  const res = await complianceWorker.fetch(
    reqProxy({
      path: "/admin/chiron/score-summary",
      scope: { tenant_id: "T1", company_id: "C1" },
      proxyScope: { tenant_id: "T2", company_id: "C2" },
    }),
    env,
  );
  assert.equal(res.status, 403);
  const j = await res.json();
  assert.equal(j.error, "proxy_scope_mismatch");
});

test("score-summary: internal proxy missing scope headers → 400 missing_proxy_scope", async () => {
  const { env } = makeTwoTenantEnv();
  const res = await complianceWorker.fetch(
    reqProxy({
      path: "/admin/chiron/score-summary",
      scope: { tenant_id: "T1", company_id: "C1" },
      omitProxyTenant: true,
    }),
    env,
  );
  assert.equal(res.status, 400);
  const j = await res.json();
  assert.equal(j.error, "missing_proxy_scope");
});

test("score-summary: no auth → 401 Unauthorized", async () => {
  const { env } = makeTwoTenantEnv();
  const req = new Request(
    "https://compliance.internal/admin/chiron/score-summary?tenant_id=T1&company_id=C1",
  );
  const res = await complianceWorker.fetch(req, env);
  assert.equal(res.status, 401);
});

test("score-summary: internal proxy with wrong proxy token → 401 Unauthorized", async () => {
  const { env } = makeTwoTenantEnv();
  const res = await complianceWorker.fetch(
    reqProxy({
      path: "/admin/chiron/score-summary",
      scope: { tenant_id: "T1", company_id: "C1" },
      overrideProxyToken: "totally-wrong-token",
    }),
    env,
  );
  assert.equal(res.status, 401);
});

// ---------------------------------------------------------------------------
// compliance/events/recent (GET)
// ---------------------------------------------------------------------------

test("events/recent: direct admin + T2 scope → 200 T2 events only", async () => {
  const { env, eventsByTenant } = makeTwoTenantEnv();
  const res = await complianceWorker.fetch(
    reqDirectAdmin({
      path: "/compliance/events/recent",
      scope: { tenant_id: "T2", company_id: "C2" },
    }),
    env,
  );
  assert.equal(res.status, 200);
  const j = await res.json();
  const seenIds = new Set((j.events || []).map((e) => String(e.event_id || "")));
  const bIds = new Set(eventsByTenant["T2|C2"]);
  const aIds = new Set(eventsByTenant["T1|C1"]);
  for (const id of bIds) assert.ok(seenIds.has(id));
  for (const id of aIds) assert.equal(seenIds.has(id), false, `A leaked: ${id}`);
});

test("events/recent: internal proxy matching scope → 200 only A events", async () => {
  const { env, eventsByTenant } = makeTwoTenantEnv();
  const res = await complianceWorker.fetch(
    reqProxy({
      path: "/compliance/events/recent",
      scope: { tenant_id: "T1", company_id: "C1" },
    }),
    env,
  );
  assert.equal(res.status, 200);
  const j = await res.json();
  const seenIds = new Set((j.events || []).map((e) => String(e.event_id || "")));
  const aIds = new Set(eventsByTenant["T1|C1"]);
  const bIds = new Set(eventsByTenant["T2|C2"]);
  for (const id of aIds) assert.ok(seenIds.has(id));
  for (const id of bIds) assert.equal(seenIds.has(id), false);
});

test("events/recent: internal proxy scope mismatch (URL T2 vs header T1) → 403", async () => {
  const { env } = makeTwoTenantEnv();
  const res = await complianceWorker.fetch(
    reqProxy({
      path: "/compliance/events/recent",
      scope: { tenant_id: "T2", company_id: "C2" },
      proxyScope: { tenant_id: "T1", company_id: "C1" },
    }),
    env,
  );
  assert.equal(res.status, 403);
});

test("events/recent: no auth → 401", async () => {
  const { env } = makeTwoTenantEnv();
  const req = new Request(
    "https://compliance.internal/compliance/events/recent?tenant_id=T1&company_id=C1",
  );
  const res = await complianceWorker.fetch(req, env);
  assert.equal(res.status, 401);
});

// ---------------------------------------------------------------------------
// admin/chiron/readiness (POST)
// ---------------------------------------------------------------------------

test("readiness: direct admin + T1 body scope → 200", async () => {
  const { env } = makeTwoTenantEnv();
  const req = new Request(
    "https://compliance.internal/admin/chiron/readiness",
    {
      method: "POST",
      headers: {
        authorization: `Bearer ${ADMIN_TOKEN}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        tenant_id: "T1",
        company_id: "C1",
        limit: 20,
        event_type: "ride_stop",
      }),
    },
  );
  const res = await complianceWorker.fetch(req, env);
  assert.equal(res.status, 200);
  const j = await res.json();
  assert.equal(j.tenant_id, "T1");
  assert.equal(j.company_id, "C1");
});

test("readiness: internal proxy matching T1 → 200", async () => {
  const { env } = makeTwoTenantEnv();
  const req = new Request(
    "https://compliance.internal/admin/chiron/readiness?tenant_id=T1&company_id=C1",
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-fluxidi-internal-proxy": PROXY_MODE,
        "x-fluxidi-proxy-token": ADMIN_TOKEN,
        "x-fluxidi-proxy-tenant-id": "T1",
        "x-fluxidi-proxy-company-id": "C1",
      },
      body: JSON.stringify({
        tenant_id: "T1",
        company_id: "C1",
        limit: 20,
        event_type: "ride_stop",
      }),
    },
  );
  const res = await complianceWorker.fetch(req, env);
  assert.equal(res.status, 200);
  const j = await res.json();
  assert.equal(j.tenant_id, "T1");
});

test("readiness: internal proxy scope mismatch (body T1 vs proxy T2) → 403", async () => {
  const { env } = makeTwoTenantEnv();
  const req = new Request(
    "https://compliance.internal/admin/chiron/readiness?tenant_id=T1&company_id=C1",
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-fluxidi-internal-proxy": PROXY_MODE,
        "x-fluxidi-proxy-token": ADMIN_TOKEN,
        "x-fluxidi-proxy-tenant-id": "T2",
        "x-fluxidi-proxy-company-id": "C2",
      },
      body: JSON.stringify({
        tenant_id: "T1",
        company_id: "C1",
        limit: 20,
        event_type: "ride_stop",
      }),
    },
  );
  const res = await complianceWorker.fetch(req, env);
  assert.equal(res.status, 403);
  const j = await res.json();
  assert.equal(j.error, "proxy_scope_mismatch");
});

test("readiness: no auth → 401", async () => {
  const { env } = makeTwoTenantEnv();
  const req = new Request(
    "https://compliance.internal/admin/chiron/readiness",
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        tenant_id: "T1",
        company_id: "C1",
      }),
    },
  );
  const res = await complianceWorker.fetch(req, env);
  assert.equal(res.status, 401);
});

test("readiness: missing body scope → 400 missing_scope", async () => {
  const { env } = makeTwoTenantEnv();
  const req = new Request(
    "https://compliance.internal/admin/chiron/readiness",
    {
      method: "POST",
      headers: {
        authorization: `Bearer ${ADMIN_TOKEN}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ limit: 20 }),
    },
  );
  const res = await complianceWorker.fetch(req, env);
  assert.equal(res.status, 400);
  const j = await res.json();
  assert.equal(j.error, "missing_scope");
});

// ---------------------------------------------------------------------------
// Source-contract regression: unchanged routes still use ensureAuthorized.
// ---------------------------------------------------------------------------

test("compliance-worker: unchanged operator-only routes still gate on ensureAuthorized", () => {
  const source = readFileSync(
    join(HERE, "fluxidi_compliance_worker.js"),
    "utf8",
  );

  function bodyOf(name) {
    const re = new RegExp(`async function ${name}\\s*\\(`);
    const m = re.exec(source);
    assert.ok(m, `${name} not found`);
    let idx = source.indexOf("{", m.index);
    let depth = 0;
    for (let i = idx; i < source.length; i++) {
      const ch = source[i];
      if (ch === "{") depth++;
      else if (ch === "}") {
        depth--;
        if (depth === 0) return source.slice(idx, i + 1);
      }
    }
    throw new Error(`${name} body not found`);
  }

  // These handlers must STILL be admin-only (no internal-proxy).
  for (const name of [
    "handleAppend",
    "handleAdminResetComplianceEvents",
    "handleChironTestflowSubmitOnePost",
  ]) {
    const body = bodyOf(name);
    const stripped = body
      .replace(/\/\*[\s\S]*?\*\//g, "")
      .replace(/(^|[^:])\/\/[^\n]*/g, "$1");
    assert.ok(
      /ensureAuthorized\s*\(/.test(stripped),
      `${name} must still call ensureAuthorized()`,
    );
    assert.equal(
      /ensureAuthorizedOrInternalProxy\s*\(/.test(stripped),
      false,
      `${name} must NOT switch to ensureAuthorizedOrInternalProxy`,
    );
  }

  // These migrated handlers must now use ensureAuthorizedOrInternalProxy.
  for (const name of [
    "handleRecent",
    "handleChironScoreSummary",
    "handleChironReadinessReport",
  ]) {
    const body = bodyOf(name);
    const stripped = body
      .replace(/\/\*[\s\S]*?\*\//g, "")
      .replace(/(^|[^:])\/\/[^\n]*/g, "$1");
    assert.ok(
      /ensureAuthorizedOrInternalProxy\s*\(/.test(stripped),
      `${name} must call ensureAuthorizedOrInternalProxy()`,
    );
    // The handler body must not call the strict-only variant directly.
    // A bare `ensureAuthorized(` cannot appear inside
    // `ensureAuthorizedOrInternalProxy(` because after `ensureAuthorized`
    // the next non-whitespace char is `O`, not `(`. So this regex only
    // catches actual direct calls.
    const strictBare = /(?<![A-Za-z_])ensureAuthorized\s*\(/g;
    // Drop occurrences that are actually part of the "OrInternalProxy"
    // spelling by searching the raw text left of each hit for the
    // "ensureAuthorizedOrInternalProxy" prefix. Match objects give a
    // position via `matchAll`.
    let directCount = 0;
    for (const m of stripped.matchAll(strictBare)) {
      const start = m.index;
      const window = stripped.slice(
        start,
        start + "ensureAuthorizedOrInternalProxy".length,
      );
      if (window === "ensureAuthorizedOrInternalProxy") continue;
      directCount += 1;
    }
    assert.equal(
      directCount,
      0,
      `${name} must not call bare ensureAuthorized() directly (found ${directCount})`,
    );
  }
});
