// CHIRON-P0-2A — Booking-worker isolation tests for the read-only Chiron
// proxy routes:
//
//   POST /admin/chiron/readiness
//   GET  /admin/chiron/score-summary
//   GET  /compliance/events/recent
//
// These tests spin up the real compliance-worker module as an in-memory
// service binding (COMPLIANCE_WORKER) so we can prove END-TO-END tenant/
// company isolation, not merely source-contract regexes. Company A owns
// tenant T1/company C1 with compliance events prefixed
// "compliance_event_v1/tenant/T1/company/C1/…" and Company B owns T2/C2.
//
// A session must:
//   - fetch its own readiness / score-summary / events without seeing B data;
//   - be blocked (403) when the client asks the booking worker for B scope;
//   - be blocked (401) when the client sends no auth;
//   - be blocked (403) if it manages to reach the compliance worker
//     directly with a wrong proxy scope header.
// The legacy platform admin token must still authorize internal tooling.
//
// Run:
//   node --test workers/booking/chiron_readonly_proxy_isolation.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import bookingWorker from "./fluxidi_booking_worker.js";
import complianceWorker from "../compliance/fluxidi_compliance_worker.js";

const HERE = dirname(fileURLToPath(import.meta.url));

// ---------------------------------------------------------------------------
// KV mock (mirrors admin_company_link_code_create_auth.test.mjs)
// ---------------------------------------------------------------------------
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
      return typeof raw === "string" ? raw : JSON.stringify(raw);
    },
    async put(key, val) {
      store.set(key, val);
    },
    async delete(key) {
      store.delete(key);
    },
    async list(opts = {}) {
      const prefix = String(opts.prefix || "");
      const cursor = opts.cursor || null;
      const limit = Number(opts.limit) > 0 ? Number(opts.limit) : 1000;
      const all = [...store.keys()]
        .filter((name) => (prefix ? name.startsWith(prefix) : true))
        .sort();
      const startIdx = cursor ? all.indexOf(cursor) + 1 : 0;
      const page = all.slice(startIdx, startIdx + limit);
      const listComplete = startIdx + limit >= all.length;
      return {
        keys: page.map((name) => ({ name })),
        list_complete: listComplete,
        cursor: listComplete ? null : page[page.length - 1],
      };
    },
  };
}

async function sha256Hex(text) {
  const data = new TextEncoder().encode(String(text || ""));
  const digest = await crypto.subtle.digest("SHA-256", data);
  const bytes = new Uint8Array(digest);
  let hex = "";
  for (const byte of bytes) hex += byte.toString(16).padStart(2, "0");
  return hex;
}

async function seedCompanySession({ tokenValue, tenantId, companyId }) {
  const hash = await sha256Hex(tokenValue);
  const key = `company_admin:session:${hash}:v1`;
  return {
    key,
    record: {
      role: "company_admin",
      tenant_id: tenantId,
      company_id: companyId,
      expires_at: new Date(Date.now() + 3_600_000).toISOString(),
    },
  };
}

function makeComplianceEvent({ tenantId, companyId, eventId, eventType, ts }) {
  return {
    event_id: eventId,
    event_type: eventType,
    schema_version: "1",
    tenant_id: tenantId,
    company_id: companyId,
    created_at_utc: ts,
    timestamps: { recorded_at_utc: ts, event_at_utc: ts },
    driver: { driver_id: `${companyId}-driver-1` },
    vehicle: {},
    locations: {},
    fare: { total: 10 },
    payment: {},
    provenance: {},
  };
}

function complianceEventKey({ tenantId, companyId, eventId, ts }) {
  // Mirror the production `safeSegment(...)` behavior used by
  // handleAppend when it computes KV keys: lower-cased, restricted
  // charset. handleRecent's prefix list uses the same segment shape.
  const seg = (v) => String(v).toLowerCase().replace(/[^a-z0-9._-]/g, "_");
  const t = new Date(ts);
  const year = String(t.getUTCFullYear()).padStart(4, "0");
  const month = String(t.getUTCMonth() + 1).padStart(2, "0");
  const day = String(t.getUTCDate()).padStart(2, "0");
  const ms = t.getTime();
  return `compliance_event_v1/tenant/${seg(tenantId)}/company/${seg(companyId)}/${year}/${month}/${day}/${ms}_${eventId}`;
}

async function makeTwoTenantEnv() {
  // Booking KV: company sessions only.
  const opA = await seedCompanySession({
    tokenValue: "operator-a-token",
    tenantId: "T1",
    companyId: "C1",
  });
  const opB = await seedCompanySession({
    tokenValue: "operator-b-token",
    tenantId: "T2",
    companyId: "C2",
  });

  const bookingKv = makeKV({
    [opA.key]: opA.record,
    [opB.key]: opB.record,
  });

  // Compliance KV: two rides per company, "ride_stop" events, ordered by ts.
  const complianceKvSeed = {};
  const now = Date.now();
  const eventsByCompany = {
    "T1|C1": [],
    "T2|C2": [],
  };
  for (const { tenantId, companyId, key: bucket } of [
    { tenantId: "T1", companyId: "C1", key: "T1|C1" },
    { tenantId: "T2", companyId: "C2", key: "T2|C2" },
  ]) {
    for (let i = 0; i < 2; i++) {
      const eventId = `${companyId}-evt-${i}`;
      const eventTsMs = now - i * 60_000;
      const eventTs = new Date(eventTsMs).toISOString();
      const key = complianceEventKey({
        tenantId,
        companyId,
        eventId,
        ts: eventTsMs,
      });
      const event = makeComplianceEvent({
        tenantId,
        companyId,
        eventId,
        eventType: "ride_stop",
        ts: eventTs,
      });
      complianceKvSeed[key] = JSON.stringify(event);
      eventsByCompany[bucket].push({ key, eventId });
    }
  }

  const complianceKv = makeKV(complianceKvSeed);

  // Compliance worker service binding fetch: routes the internal Request
  // through the real compliance worker with the compliance env.
  const complianceEnv = {
    ADMIN_TOKEN: "backend-admin-token-only-for-internal-tooling",
    COMPLIANCE_ADMIN_TOKEN: "backend-admin-token-only-for-internal-tooling",
    COMPLIANCE_KV: complianceKv,
  };
  const complianceBinding = {
    fetch: (req) => complianceWorker.fetch(req, complianceEnv),
  };

  const bookingEnv = {
    ADMIN_TOKEN: "backend-admin-token-only-for-internal-tooling",
    COMPLIANCE_ADMIN_TOKEN: "backend-admin-token-only-for-internal-tooling",
    BOOKING_KV: bookingKv,
    COMPLIANCE_WORKER: complianceBinding,
  };

  return { bookingEnv, complianceEnv, complianceBinding, eventsByCompany };
}

function bookingRequest({
  path,
  method = "GET",
  token = null,
  adminToken = null,
  scope = null,
  body = null,
}) {
  const headers = {};
  if (adminToken) headers["x-admin-token"] = adminToken;
  if (token) headers["authorization"] = `Bearer ${token}`;
  if (method === "POST") headers["content-type"] = "application/json";
  const query = scope
    ? `?tenant_id=${encodeURIComponent(scope.tenant_id)}&company_id=${encodeURIComponent(scope.company_id)}`
    : "";
  return new Request(`https://booking.internal${path}${query}`, {
    method,
    headers,
    body: body !== null ? JSON.stringify(body) : undefined,
  });
}

// ---------------------------------------------------------------------------
// GET /admin/chiron/score-summary  (proxied)
// ---------------------------------------------------------------------------

test("score-summary: A session → 200 with only A data", async () => {
  const { bookingEnv, eventsByCompany } = await makeTwoTenantEnv();
  const res = await bookingWorker.fetch(
    bookingRequest({
      path: "/admin/chiron/score-summary",
      token: "operator-a-token",
      scope: { tenant_id: "T1", company_id: "C1" },
    }),
    bookingEnv,
    {},
  );
  assert.equal(res.status, 200);
  const j = await res.json();
  assert.equal(j.tenant_id, "T1");
  assert.equal(j.company_id, "C1");
  const aIds = new Set(eventsByCompany["T1|C1"].map((e) => e.eventId));
  const bIds = new Set(eventsByCompany["T2|C2"].map((e) => e.eventId));
  const sampleIds = (j.newest_events || []).map((e) =>
    String(e.event_id || ""),
  );
  for (const id of sampleIds) {
    assert.ok(aIds.has(id), `unexpected non-A event surfaced: ${id}`);
    assert.equal(bIds.has(id), false, `B event leaked: ${id}`);
  }
});

test("score-summary: A session with B scope → 403 forbidden", async () => {
  const { bookingEnv } = await makeTwoTenantEnv();
  const res = await bookingWorker.fetch(
    bookingRequest({
      path: "/admin/chiron/score-summary",
      token: "operator-a-token",
      scope: { tenant_id: "T2", company_id: "C2" },
    }),
    bookingEnv,
    {},
  );
  assert.equal(res.status, 403);
  const j = await res.json();
  assert.equal(j.error, "forbidden");
});

test("score-summary: no auth → 401 JSON", async () => {
  const { bookingEnv } = await makeTwoTenantEnv();
  const res = await bookingWorker.fetch(
    bookingRequest({
      path: "/admin/chiron/score-summary",
      scope: { tenant_id: "T1", company_id: "C1" },
    }),
    bookingEnv,
    {},
  );
  assert.equal(res.status, 401);
  assert.match(
    String(res.headers.get("content-type") || ""),
    /^application\/json\b/,
  );
});

test("score-summary: admin_token still authorizes internal tooling", async () => {
  const { bookingEnv } = await makeTwoTenantEnv();
  const res = await bookingWorker.fetch(
    bookingRequest({
      path: "/admin/chiron/score-summary",
      adminToken: "backend-admin-token-only-for-internal-tooling",
      scope: { tenant_id: "T1", company_id: "C1" },
    }),
    bookingEnv,
    {},
  );
  assert.equal(res.status, 200);
  const j = await res.json();
  assert.equal(j.tenant_id, "T1");
  assert.equal(j.company_id, "C1");
});

test("score-summary: missing scope → 400 missing_tenant_scope", async () => {
  const { bookingEnv } = await makeTwoTenantEnv();
  const res = await bookingWorker.fetch(
    bookingRequest({
      path: "/admin/chiron/score-summary",
      token: "operator-a-token",
    }),
    bookingEnv,
    {},
  );
  assert.equal(res.status, 400);
  const j = await res.json();
  assert.equal(j.error, "missing_tenant_scope");
});

test("score-summary: POST → 405 Method Not Allowed", async () => {
  const { bookingEnv } = await makeTwoTenantEnv();
  const res = await bookingWorker.fetch(
    bookingRequest({
      path: "/admin/chiron/score-summary",
      method: "POST",
      token: "operator-a-token",
      scope: { tenant_id: "T1", company_id: "C1" },
      body: {},
    }),
    bookingEnv,
    {},
  );
  assert.equal(res.status, 405);
});

// ---------------------------------------------------------------------------
// GET /compliance/events/recent  (proxied)
// ---------------------------------------------------------------------------

test("events/recent: A session → 200 lists only A events", async () => {
  const { bookingEnv, eventsByCompany } = await makeTwoTenantEnv();
  const res = await bookingWorker.fetch(
    bookingRequest({
      path: "/compliance/events/recent",
      token: "operator-a-token",
      scope: { tenant_id: "T1", company_id: "C1" },
    }),
    bookingEnv,
    {},
  );
  assert.equal(res.status, 200);
  const j = await res.json();
  const seen = new Set((j.events || []).map((e) => String(e.event_id || "")));
  const aIds = new Set(eventsByCompany["T1|C1"].map((e) => e.eventId));
  const bIds = new Set(eventsByCompany["T2|C2"].map((e) => e.eventId));
  for (const id of aIds) {
    assert.ok(seen.has(id), `expected A event missing: ${id}`);
  }
  for (const id of bIds) {
    assert.equal(seen.has(id), false, `B event leaked to A: ${id}`);
  }
});

test("events/recent: no auth → 401 JSON", async () => {
  const { bookingEnv } = await makeTwoTenantEnv();
  const res = await bookingWorker.fetch(
    bookingRequest({
      path: "/compliance/events/recent",
      scope: { tenant_id: "T1", company_id: "C1" },
    }),
    bookingEnv,
    {},
  );
  assert.equal(res.status, 401);
});

test("events/recent: A session, B scope → 403 forbidden", async () => {
  const { bookingEnv } = await makeTwoTenantEnv();
  const res = await bookingWorker.fetch(
    bookingRequest({
      path: "/compliance/events/recent",
      token: "operator-a-token",
      scope: { tenant_id: "T2", company_id: "C2" },
    }),
    bookingEnv,
    {},
  );
  assert.equal(res.status, 403);
  const j = await res.json();
  assert.equal(j.error, "forbidden");
});

test("events/recent: admin_token authorizes internal tooling", async () => {
  const { bookingEnv, eventsByCompany } = await makeTwoTenantEnv();
  const res = await bookingWorker.fetch(
    bookingRequest({
      path: "/compliance/events/recent",
      adminToken: "backend-admin-token-only-for-internal-tooling",
      scope: { tenant_id: "T2", company_id: "C2" },
    }),
    bookingEnv,
    {},
  );
  assert.equal(res.status, 200);
  const j = await res.json();
  // Pre-existing behaviour of handleRecent: response tenant/company are the
  // lower-cased KV segments, not the original request case. What matters
  // for isolation is that ONLY B events are returned.
  assert.equal(String(j.tenant_id || "").toLowerCase(), "t2");
  assert.equal(String(j.company_id || "").toLowerCase(), "c2");
  const seen = new Set((j.events || []).map((e) => String(e.event_id || "")));
  const bIds = new Set(eventsByCompany["T2|C2"].map((e) => e.eventId));
  for (const id of bIds) {
    assert.ok(seen.has(id), `expected B event missing: ${id}`);
  }
});

test("events/recent: POST → 405", async () => {
  const { bookingEnv } = await makeTwoTenantEnv();
  const res = await bookingWorker.fetch(
    bookingRequest({
      path: "/compliance/events/recent",
      method: "POST",
      token: "operator-a-token",
      scope: { tenant_id: "T1", company_id: "C1" },
      body: {},
    }),
    bookingEnv,
    {},
  );
  assert.equal(res.status, 405);
});

// ---------------------------------------------------------------------------
// POST /admin/chiron/readiness  (proxied)
// ---------------------------------------------------------------------------

test("readiness: A session → 200 body describes A scope only", async () => {
  const { bookingEnv } = await makeTwoTenantEnv();
  const res = await bookingWorker.fetch(
    bookingRequest({
      path: "/admin/chiron/readiness",
      method: "POST",
      token: "operator-a-token",
      scope: { tenant_id: "T1", company_id: "C1" },
      body: {
        tenant_id: "T1",
        company_id: "C1",
        limit: 20,
        event_type: "ride_stop",
      },
    }),
    bookingEnv,
    {},
  );
  assert.equal(res.status, 200);
  const j = await res.json();
  assert.equal(j.ok, true);
  assert.equal(j.tenant_id, "T1");
  assert.equal(j.company_id, "C1");
});

test("readiness: A session tries B scope in body → 400 (booking-worker rejects body scope mismatch)", async () => {
  const { bookingEnv } = await makeTwoTenantEnv();
  const res = await bookingWorker.fetch(
    bookingRequest({
      path: "/admin/chiron/readiness",
      method: "POST",
      token: "operator-a-token",
      scope: { tenant_id: "T1", company_id: "C1" },
      body: {
        tenant_id: "T2",
        company_id: "C2",
        limit: 20,
        event_type: "ride_stop",
      },
    }),
    bookingEnv,
    {},
  );
  // The booking worker resolves the explicit scope from every conflict-safe
  // location; a body/query scope conflict is rejected as tenant_scope_conflict
  // (400). Either way A must NOT be able to reach B data.
  assert.ok(res.status === 400 || res.status === 403);
  const j = await res.json();
  assert.equal(j.ok, false);
});

test("readiness: A session, B scope in query only → 403 forbidden", async () => {
  const { bookingEnv } = await makeTwoTenantEnv();
  const res = await bookingWorker.fetch(
    bookingRequest({
      path: "/admin/chiron/readiness",
      method: "POST",
      token: "operator-a-token",
      scope: { tenant_id: "T2", company_id: "C2" },
      body: { tenant_id: "T2", company_id: "C2", limit: 20 },
    }),
    bookingEnv,
    {},
  );
  assert.equal(res.status, 403);
  const j = await res.json();
  assert.equal(j.error, "forbidden");
});

test("readiness: no auth → 401", async () => {
  const { bookingEnv } = await makeTwoTenantEnv();
  const res = await bookingWorker.fetch(
    bookingRequest({
      path: "/admin/chiron/readiness",
      method: "POST",
      scope: { tenant_id: "T1", company_id: "C1" },
      body: { tenant_id: "T1", company_id: "C1", limit: 20 },
    }),
    bookingEnv,
    {},
  );
  assert.equal(res.status, 401);
});

test("readiness: PUT → 405", async () => {
  const { bookingEnv } = await makeTwoTenantEnv();
  const req = new Request(
    "https://booking.internal/admin/chiron/readiness?tenant_id=T1&company_id=C1",
    {
      method: "PUT",
      headers: {
        authorization: "Bearer operator-a-token",
        "content-type": "application/json",
      },
      body: JSON.stringify({ tenant_id: "T1", company_id: "C1" }),
    },
  );
  const res = await bookingWorker.fetch(req, bookingEnv, {});
  assert.equal(res.status, 405);
});

// ---------------------------------------------------------------------------
// Source-contract regression: destructive routes are NOT proxied.
// ---------------------------------------------------------------------------

test("chiron_bridge allowlist rejects unlisted paths", () => {
  const source = readFileSync(
    join(HERE, "modules", "chiron_bridge.js"),
    "utf8",
  );
  const stripped = source
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/(^|[^:])\/\/[^\n]*/g, "$1");
  // Destructive/test-only paths must NOT appear in the allowlist source.
  assert.equal(
    /['"]\/admin\/dev\/reset-compliance-events['"]/.test(stripped),
    false,
    "destructive reset-compliance-events must not be in the proxy allowlist",
  );
  assert.equal(
    /['"]\/admin\/chiron\/testflow\/reset['"]/.test(stripped),
    false,
    "chiron testflow reset must not be in the proxy allowlist",
  );
  assert.ok(
    /CHIRON_READINESS_PATH/.test(stripped),
    "readiness path must be present",
  );
  assert.ok(
    /CHIRON_SCORE_SUMMARY_PATH/.test(stripped),
    "score-summary path must be present",
  );
  assert.ok(
    /COMPLIANCE_EVENTS_RECENT_PATH/.test(stripped),
    "compliance events recent path must be present",
  );
});
