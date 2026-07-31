// RELEASE-P0-CHIRON-RESET-UX-2026-07-31 — end-to-end reset via company session.
//
// The tablet operator triggers the Chiron acceptance-testflow reset from the
// Chiron Compliance page. That call:
//   1. lands on the booking worker at POST /admin/chiron/testflow/reset;
//   2. is authenticated with a company-owner session bearer + strict
//      URL/body scope validation;
//   3. proxies to the compliance worker over the COMPLIANCE_WORKER service
//      binding with the `x-fluxidi-internal-proxy` header + admin token;
//   4. the compliance worker re-validates the proxy scope, wipes counters
//      and ritnummer history, forces production_enabled=false, environment=
//      "test", official_submit_enabled=false, testflow_auto_submit_enabled=
//      true, and stamps a fresh testflow_started_at.
//
// The existing OAuth test credentials + last_connection_status must survive.
//
// Run:
//   node --test workers/booking/chiron_testflow_reset_via_company_session.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import bookingWorker from "./fluxidi_booking_worker.js";
import complianceWorker from "../compliance/fluxidi_compliance_worker.js";

// ---------------------------------------------------------------------------
// KV mock (same shape as chiron_readonly_proxy_isolation.test.mjs)
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
  return {
    key: `company_admin:session:${hash}:v1`,
    record: {
      role: "company_admin",
      tenant_id: tenantId,
      company_id: companyId,
      expires_at: new Date(Date.now() + 3_600_000).toISOString(),
    },
  };
}

function chironConnectionKey(tenantId, companyId) {
  return `tenant:${tenantId}:company:${companyId}:chiron_connection:v1`;
}

// A realistically dirty pre-reset doc: acceptance testflow already ran, the
// operator flipped production_enabled=true after completion, five ritnummers
// were sent. This mirrors the state described in the P0 audit report.
function preResetConnectionDoc(tenantId, companyId) {
  return {
    schema_version: "chiron_connection_status_v1",
    tenant_id: tenantId,
    company_id: companyId,
    enabled: true,
    environment: "test",
    region: "flanders",
    production_enabled: true,
    test_credentials_stored: true,
    production_credentials_stored: false,
    last_connection_status: "test_passed",
    last_connection_test_at: "2026-07-31T17:06:52.132Z",
    last_connection_status_message: null,
    test_messages_sent_count: 10,
    test_messages_required: 10,
    test_rides_required: 5,
    test_departure_required: 5,
    test_arrival_required: 5,
    test_departure_sent_count: 5,
    test_arrival_sent_count: 5,
    test_rides_completed_count: 5,
    testflow_status: "complete",
    testflow_completed_at: "2026-07-31T16:25:23.122Z",
    testflow_updated_at: "2026-07-31T16:47:06.816Z",
    testflow_last_error: "stale_previous_error_that_must_be_cleared",
    testflow_ritnummers_departure: [
      "rit1",
      "rit2",
      "rit3",
      "rit4",
      "rit5",
    ],
    testflow_ritnummers_arrival: ["rit1", "rit2", "rit3", "rit4", "rit5"],
    testflow_ritnummers_completed: ["rit1", "rit2", "rit3", "rit4", "rit5"],
    testflow_auto_submit_enabled: false,
    testflow_started_at: "2026-07-31T14:00:00.000Z",
    testflow_auto_reconcile_last_at: "2026-07-31T16:47:06.898Z",
    official_submission_performed_at: null,
    updated_at: "2026-07-31T17:06:52.132Z",
    updated_by: "proxy",
    last_connection_environment: "test",
    last_connection_auth_scheme: "oauth_client_credentials",
    last_connection_external_call_performed: true,
    last_connection_token_type: "Bearer",
    last_connection_access_token_obtained: true,
    last_connection_expires_in_seconds: 3599,
    last_connection_sanitized_error: null,
  };
}

async function makeTwoTenantEnv() {
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
  const complianceKv = makeKV({
    [chironConnectionKey("T1", "C1")]: JSON.stringify(
      preResetConnectionDoc("T1", "C1"),
    ),
    [chironConnectionKey("T2", "C2")]: JSON.stringify(
      preResetConnectionDoc("T2", "C2"),
    ),
  });

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
  return { bookingEnv, complianceEnv, complianceKv };
}

function bookingRequest({
  path,
  method = "POST",
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
// Happy path: A session resets A scope → 200 + fresh clean testflow.
// ---------------------------------------------------------------------------

test("reset: A session → 200 + counters and ritnummer sets wiped", async () => {
  const { bookingEnv, complianceKv } = await makeTwoTenantEnv();
  const before = Date.now();
  const res = await bookingWorker.fetch(
    bookingRequest({
      path: "/admin/chiron/testflow/reset",
      token: "operator-a-token",
      scope: { tenant_id: "T1", company_id: "C1" },
      body: { tenant_id: "T1", company_id: "C1" },
    }),
    bookingEnv,
    {},
  );
  const after = Date.now();
  assert.equal(res.status, 200);
  const j = await res.json();
  assert.equal(j.ok, true);
  assert.equal(j.tenant_id, "T1");
  assert.equal(j.company_id, "C1");
  assert.equal(j.testflow_status, "not_started");
  assert.equal(j.test_messages_sent_count, 0);
  assert.equal(j.test_departure_sent_count, 0);
  assert.equal(j.test_arrival_sent_count, 0);
  assert.equal(j.test_rides_completed_count, 0);
  assert.equal(j.test_messages_required, 10);
  assert.equal(j.test_departure_required, 5);
  assert.equal(j.test_arrival_required, 5);
  assert.equal(j.test_rides_required, 5);
  assert.equal(j.production_enabled, false);
  assert.equal(j.last_connection_status, "test_passed");
  // Stored doc: verify the atomic move to the fresh testflow state.
  const rawStored = await complianceKv.get(chironConnectionKey("T1", "C1"));
  const stored = JSON.parse(rawStored);
  assert.equal(stored.production_enabled, false);
  assert.equal(stored.environment, "test");
  assert.equal(stored.official_submit_enabled, false);
  assert.equal(stored.testflow_auto_submit_enabled, true);
  assert.equal(stored.testflow_status, "not_started");
  assert.equal(stored.testflow_completed_at, null);
  assert.equal(stored.testflow_last_error, null);
  assert.equal(stored.testflow_auto_reconcile_last_at, null);
  assert.deepEqual(stored.testflow_ritnummers_departure, []);
  assert.deepEqual(stored.testflow_ritnummers_arrival, []);
  assert.deepEqual(stored.testflow_ritnummers_completed, []);
  const startedMs = Date.parse(stored.testflow_started_at || "");
  assert.ok(
    Number.isFinite(startedMs) &&
      startedMs >= before - 1000 &&
      startedMs <= after + 1000,
    `testflow_started_at must be a fresh UTC ISO within [before, after]; got ${stored.testflow_started_at}`,
  );
  // Preserved: OAuth credentials + last_connection_status + enabled.
  assert.equal(stored.enabled, true);
  assert.equal(stored.test_credentials_stored, true);
  assert.equal(stored.last_connection_status, "test_passed");
  assert.equal(
    stored.last_connection_test_at,
    "2026-07-31T17:06:52.132Z",
    "OAuth test-passed timestamp must survive reset",
  );
});

// ---------------------------------------------------------------------------
// Precondition: reset forces production off even when starting from production.
// ---------------------------------------------------------------------------

test("reset: production_enabled=true → forced false after reset", async () => {
  const { bookingEnv, complianceKv } = await makeTwoTenantEnv();
  // Sanity: precondition doc has production_enabled=true.
  const preRaw = await complianceKv.get(chironConnectionKey("T1", "C1"));
  const pre = JSON.parse(preRaw);
  assert.equal(pre.production_enabled, true, "pre-reset must be prod on");
  const res = await bookingWorker.fetch(
    bookingRequest({
      path: "/admin/chiron/testflow/reset",
      token: "operator-a-token",
      scope: { tenant_id: "T1", company_id: "C1" },
      body: { tenant_id: "T1", company_id: "C1" },
    }),
    bookingEnv,
    {},
  );
  assert.equal(res.status, 200);
  const j = await res.json();
  assert.equal(j.production_enabled, false);
  const postRaw = await complianceKv.get(chironConnectionKey("T1", "C1"));
  const post = JSON.parse(postRaw);
  assert.equal(post.production_enabled, false);
});

// ---------------------------------------------------------------------------
// Idempotency: two consecutive resets → clean state both times.
// ---------------------------------------------------------------------------

test("reset: double reset is idempotent and does not corrupt state", async () => {
  const { bookingEnv, complianceKv } = await makeTwoTenantEnv();
  const first = await bookingWorker.fetch(
    bookingRequest({
      path: "/admin/chiron/testflow/reset",
      token: "operator-a-token",
      scope: { tenant_id: "T1", company_id: "C1" },
      body: { tenant_id: "T1", company_id: "C1" },
    }),
    bookingEnv,
    {},
  );
  assert.equal(first.status, 200);
  const firstStored = JSON.parse(
    await complianceKv.get(chironConnectionKey("T1", "C1")),
  );
  const firstStartedAt = firstStored.testflow_started_at;
  // Ensure clock advances so the second reset can produce a strictly later
  // testflow_started_at value.
  await new Promise((r) => setTimeout(r, 15));
  const second = await bookingWorker.fetch(
    bookingRequest({
      path: "/admin/chiron/testflow/reset",
      token: "operator-a-token",
      scope: { tenant_id: "T1", company_id: "C1" },
      body: { tenant_id: "T1", company_id: "C1" },
    }),
    bookingEnv,
    {},
  );
  assert.equal(second.status, 200);
  const secondStored = JSON.parse(
    await complianceKv.get(chironConnectionKey("T1", "C1")),
  );
  // Both resets produce a fresh clean state.
  assert.equal(secondStored.production_enabled, false);
  assert.equal(secondStored.environment, "test");
  assert.equal(secondStored.testflow_status, "not_started");
  assert.equal(secondStored.test_messages_sent_count, 0);
  assert.equal(secondStored.test_departure_sent_count, 0);
  assert.equal(secondStored.test_arrival_sent_count, 0);
  assert.equal(secondStored.test_rides_completed_count, 0);
  assert.equal(secondStored.testflow_auto_submit_enabled, true);
  assert.deepEqual(secondStored.testflow_ritnummers_departure, []);
  assert.deepEqual(secondStored.testflow_ritnummers_arrival, []);
  assert.deepEqual(secondStored.testflow_ritnummers_completed, []);
  // testflow_started_at moves forward (or stays equal within clock resolution)
  // but never regresses.
  const firstMs = Date.parse(firstStartedAt);
  const secondMs = Date.parse(secondStored.testflow_started_at);
  assert.ok(
    Number.isFinite(firstMs) && Number.isFinite(secondMs) && secondMs >= firstMs,
    `second reset testflow_started_at ${secondStored.testflow_started_at} must be >= first ${firstStartedAt}`,
  );
  // OAuth credentials still preserved after two resets.
  assert.equal(secondStored.test_credentials_stored, true);
  assert.equal(secondStored.last_connection_status, "test_passed");
});

// ---------------------------------------------------------------------------
// Scope isolation: A session cannot reset B tenant.
// ---------------------------------------------------------------------------

test("reset: A session with B scope → 403 forbidden, B doc untouched", async () => {
  const { bookingEnv, complianceKv } = await makeTwoTenantEnv();
  const res = await bookingWorker.fetch(
    bookingRequest({
      path: "/admin/chiron/testflow/reset",
      token: "operator-a-token",
      scope: { tenant_id: "T2", company_id: "C2" },
      body: { tenant_id: "T2", company_id: "C2" },
    }),
    bookingEnv,
    {},
  );
  assert.equal(res.status, 403);
  const j = await res.json();
  assert.equal(j.error, "forbidden");
  // B doc must remain untouched by the failed cross-tenant attempt.
  const bStored = JSON.parse(
    await complianceKv.get(chironConnectionKey("T2", "C2")),
  );
  assert.equal(bStored.testflow_status, "complete");
  assert.equal(bStored.test_messages_sent_count, 10);
  assert.equal(bStored.production_enabled, true);
});

test(
  "reset: A session, mismatched body scope → 400 (booking-worker rejects body scope)",
  async () => {
    const { bookingEnv, complianceKv } = await makeTwoTenantEnv();
    const res = await bookingWorker.fetch(
      bookingRequest({
        path: "/admin/chiron/testflow/reset",
        token: "operator-a-token",
        scope: { tenant_id: "T1", company_id: "C1" },
        body: { tenant_id: "T2", company_id: "C2" },
      }),
      bookingEnv,
      {},
    );
    assert.equal(res.status, 400);
    // A's doc untouched.
    const aStored = JSON.parse(
      await complianceKv.get(chironConnectionKey("T1", "C1")),
    );
    assert.equal(aStored.testflow_status, "complete");
  },
);

// ---------------------------------------------------------------------------
// Auth negative paths.
// ---------------------------------------------------------------------------

test("reset: no auth → 401", async () => {
  const { bookingEnv } = await makeTwoTenantEnv();
  const res = await bookingWorker.fetch(
    bookingRequest({
      path: "/admin/chiron/testflow/reset",
      scope: { tenant_id: "T1", company_id: "C1" },
      body: { tenant_id: "T1", company_id: "C1" },
    }),
    bookingEnv,
    {},
  );
  assert.equal(res.status, 401);
});

test("reset: missing scope → 400", async () => {
  const { bookingEnv } = await makeTwoTenantEnv();
  const res = await bookingWorker.fetch(
    bookingRequest({
      path: "/admin/chiron/testflow/reset",
      token: "operator-a-token",
      body: {},
    }),
    bookingEnv,
    {},
  );
  assert.equal(res.status, 400);
  const j = await res.json();
  assert.equal(j.error, "missing_tenant_scope");
});

test("reset: GET → 405", async () => {
  const { bookingEnv } = await makeTwoTenantEnv();
  const res = await bookingWorker.fetch(
    bookingRequest({
      path: "/admin/chiron/testflow/reset",
      method: "GET",
      token: "operator-a-token",
      scope: { tenant_id: "T1", company_id: "C1" },
    }),
    bookingEnv,
    {},
  );
  assert.equal(res.status, 405);
});

// ---------------------------------------------------------------------------
// Admin-token still works (internal tooling).
// ---------------------------------------------------------------------------

test("reset: admin_token internal tooling → 200", async () => {
  const { bookingEnv, complianceKv } = await makeTwoTenantEnv();
  const res = await bookingWorker.fetch(
    bookingRequest({
      path: "/admin/chiron/testflow/reset",
      adminToken: "backend-admin-token-only-for-internal-tooling",
      scope: { tenant_id: "T1", company_id: "C1" },
      body: { tenant_id: "T1", company_id: "C1" },
    }),
    bookingEnv,
    {},
  );
  assert.equal(res.status, 200);
  const stored = JSON.parse(
    await complianceKv.get(chironConnectionKey("T1", "C1")),
  );
  assert.equal(stored.production_enabled, false);
  assert.equal(stored.testflow_status, "not_started");
});

// ---------------------------------------------------------------------------
// Cutoff semantics: after reset the fresh `testflow_started_at` fences off
// pre-reset compliance events (documented for the auto-reconciler).
// ---------------------------------------------------------------------------

test(
  "reset: fresh testflow_started_at excludes events created before reset",
  async () => {
    const { bookingEnv, complianceKv } = await makeTwoTenantEnv();
    const beforeMs = Date.now();
    const res = await bookingWorker.fetch(
      bookingRequest({
        path: "/admin/chiron/testflow/reset",
        token: "operator-a-token",
        scope: { tenant_id: "T1", company_id: "C1" },
        body: { tenant_id: "T1", company_id: "C1" },
      }),
      bookingEnv,
      {},
    );
    assert.equal(res.status, 200);
    const stored = JSON.parse(
      await complianceKv.get(chironConnectionKey("T1", "C1")),
    );
    const cutoffMs = Date.parse(stored.testflow_started_at);
    assert.ok(
      cutoffMs >= beforeMs,
      "cutoff must be >= reset invocation time (fresh, not the pre-reset 14:00 UTC)",
    );
    // The previous cutoff (14:00 UTC in the pre-reset seed) is strictly before
    // the new cutoff → any event stored with an old created_at_utc is filtered
    // out by `_chironAutoSubmitEligibleForEvent`.
    const oldCutoff = Date.parse("2026-07-31T14:00:00.000Z");
    assert.ok(
      cutoffMs > oldCutoff,
      "new cutoff must be strictly later than the pre-reset cutoff",
    );
  },
);
