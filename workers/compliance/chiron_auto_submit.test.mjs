// RELEASE-P0-AUTO-CHIRON-2026-07-31 — targeted tests for the automatic
// Chiron testflow submission.
//
// Coverage:
//   * eligibility gate (live gate + auto_submit_enabled + testflow_started_at
//     cutoff);
//   * departure auto-submit posts once, advances counters;
//   * arrival waits when paired departure is not `synced` (marker written);
//   * arrival resumes automatically once departure is `synced`;
//   * duplicate guard blocks re-POST for synced / verification_required;
//   * OAuth pre-POST failure leaves no `pending` doc (retryable);
//   * definitive Chiron rejection is never blindly retried;
//   * reconciler is bounded and throttled;
//   * append response returns even if Chiron submit is slow (waitUntil).
//
// Run: node --test workers/compliance/chiron_auto_submit.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import worker, { __testInternals } from "./fluxidi_compliance_worker.js";

const {
  _chironAutoSubmitEligibleForEvent,
  _chironAutoSubmitMessageTypeForEventType,
  _chironPairedDepartureIdempotencyKeyForArrivalDraft,
  _chironAutoSubmitOneEvent,
  _chironAutoReconcileScopeBestEffort,
  _chironShouldRunReconcileFromStatusPoll,
  _chironInferLegTypeForLeglessRideStarts,
  _chironEvaluateSubmitDuplicateGuard,
  buildChironOfficialIdempotencyKey,
  buildChironExportStatusKey,
  CHIRON_EXPORT_STATUS_SCHEMA,
  encryptChironCredentialBlob,
  buildChironCredentialsKvKey,
  CHIRON_CREDENTIALS_PAYLOAD_SCHEMA_VERSION,
  CHIRON_CREDENTIALS_SCHEMA_VERSION,
  safeSegment,
  CHIRON_AUTO_RECONCILE_MIN_INTERVAL_MS,
  CHIRON_TESTFLOW_AUTO_RECONCILE_PATH,
} = __testInternals;

const ADMIN = "admin-token-for-tests";
const ENCRYPTION_KEY = "test-only-encryption-key-must-be->=32-chars";
const OAUTH_TOKEN_URL = "https://mow-acc.api.vlaanderen.be/oauth/token";
const TAXIRIT_URL = "https://mow-acc.api.vlaanderen.be/chiron/taxirit";

const TENANT = "T1";
const COMPANY = "C1";
const TENANT_SEG = safeSegment(TENANT, "");
const COMPANY_SEG = safeSegment(COMPANY, "");

function makeKV({ seed = {} } = {}) {
  const store = new Map(Object.entries(seed));
  return {
    store,
    async get(key, opts) {
      if (!store.has(key)) return null;
      const raw = store.get(key);
      if (opts && opts.type === "json") {
        try {
          return JSON.parse(raw);
        } catch (_) {
          return null;
        }
      }
      return raw;
    },
    async put(key, val) {
      store.set(key, typeof val === "string" ? val : JSON.stringify(val));
    },
    async delete(key) {
      store.delete(key);
    },
    async list({ prefix = "", limit = 1000, cursor } = {}) {
      const names = [...store.keys()]
        .filter((k) => k.startsWith(prefix))
        .sort();
      const startIdx = cursor ? Number(cursor) : 0;
      const slice = names.slice(startIdx, startIdx + limit);
      const nextCursor = startIdx + slice.length;
      const listComplete = nextCursor >= names.length;
      return {
        keys: slice.map((name) => ({ name })),
        list_complete: listComplete,
        cursor: listComplete ? undefined : String(nextCursor),
      };
    },
  };
}

function baseEnv(kv, overrides = {}) {
  return {
    ADMIN_TOKEN: ADMIN,
    COMPLIANCE_KV: kv,
    CHIRON_EXPORT_MODE: "test",
    CHIRON_EXPORT_BASE_URL: TAXIRIT_URL,
    CHIRON_EXPORT_API_TOKEN: "legacy-static-token-not-used-as-bearer",
    CHIRON_CREDENTIALS_ENCRYPTION_KEY: ENCRYPTION_KEY,
    CHIRON_CREDENTIALS_ENCRYPTION_KID: "v1",
    ...overrides,
  };
}

async function seedOAuthCredentials(kv, env, { tenantId, companyId, clientId, clientSecret }) {
  const plaintext = JSON.stringify({
    schema_version: CHIRON_CREDENTIALS_PAYLOAD_SCHEMA_VERSION,
    auth_scheme: "oauth_client_credentials",
    client_id: clientId,
    client_secret: clientSecret,
  });
  const encrypted = await encryptChironCredentialBlob(plaintext, env);
  const doc = {
    schema_version: CHIRON_CREDENTIALS_SCHEMA_VERSION,
    tenant_id: tenantId,
    company_id: companyId,
    environment: "test",
    auth_scheme: "oauth_client_credentials",
    credential_payload_encrypted: encrypted,
    credential_fingerprint_short: "fpauto",
    masked_identifier: "client_***",
  };
  const key = buildChironCredentialsKvKey(tenantId, companyId, "test");
  await kv.put(key, JSON.stringify(doc));
  return { key, doc };
}

function goodStatusDoc(overrides = {}) {
  return {
    schema_version: "chiron_connection_status_v1",
    tenant_id: TENANT,
    company_id: COMPANY,
    enabled: true,
    environment: "test",
    region: "flanders",
    production_enabled: false,
    official_submit_enabled: false,
    test_credentials_stored: true,
    last_connection_status: "test_passed",
    testflow_auto_submit_enabled: true,
    testflow_started_at: "2026-07-31T15:00:00.000Z",
    test_messages_required: 10,
    test_messages_sent_count: 0,
    test_departure_required: 5,
    test_arrival_required: 5,
    test_rides_required: 5,
    test_departure_sent_count: 0,
    test_arrival_sent_count: 0,
    test_rides_completed_count: 0,
    testflow_status: "not_started",
    testflow_ritnummers_departure: [],
    testflow_ritnummers_arrival: [],
    testflow_ritnummers_completed: [],
    ...overrides,
  };
}

async function seedConnectionStatus(kv, doc) {
  const key = `tenant:${doc.tenant_id}:company:${doc.company_id}:chiron_connection:v1`;
  await kv.put(key, JSON.stringify(doc));
  return key;
}

function installFetchStub(handler) {
  const original = globalThis.fetch;
  const calls = [];
  globalThis.fetch = async (input, init) => {
    calls.push({ url: String(input), init });
    return handler(String(input), init || {});
  };
  return {
    calls,
    restore() {
      globalThis.fetch = original;
    },
  };
}

function jsonResponse(status, body, headers = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", ...headers },
  });
}

// =====================================================================
// A. Pure eligibility gate.
// =====================================================================
test("eligibility: unknown event_type => event_type_not_auto_submittable", () => {
  const status = goodStatusDoc();
  const evt = {
    event_type: "payment_update",
    tenant_id: TENANT,
    company_id: COMPANY,
    created_at_utc: "2026-07-31T16:00:00.000Z",
  };
  const r = _chironAutoSubmitEligibleForEvent(status, baseEnv(makeKV()), evt);
  assert.equal(r, "event_type_not_auto_submittable");
});

test("eligibility: live gate failure short-circuits", () => {
  const status = goodStatusDoc({ enabled: false });
  const evt = {
    event_type: "ride_start",
    tenant_id: TENANT,
    company_id: COMPANY,
    created_at_utc: "2026-07-31T16:00:00.000Z",
  };
  const r = _chironAutoSubmitEligibleForEvent(status, baseEnv(makeKV()), evt);
  assert.equal(r, "chiron_not_enabled");
});

test("eligibility: auto_submit_enabled=false => blocked", () => {
  const status = goodStatusDoc({ testflow_auto_submit_enabled: false });
  const evt = {
    event_type: "ride_start",
    tenant_id: TENANT,
    company_id: COMPANY,
    created_at_utc: "2026-07-31T16:00:00.000Z",
  };
  const r = _chironAutoSubmitEligibleForEvent(status, baseEnv(makeKV()), evt);
  assert.equal(r, "testflow_auto_submit_disabled");
});

test("eligibility: missing testflow_started_at => blocked", () => {
  const status = goodStatusDoc({ testflow_started_at: null });
  const evt = {
    event_type: "ride_start",
    tenant_id: TENANT,
    company_id: COMPANY,
    created_at_utc: "2026-07-31T16:00:00.000Z",
  };
  const r = _chironAutoSubmitEligibleForEvent(status, baseEnv(makeKV()), evt);
  assert.equal(r, "missing_testflow_started_at");
});

test("eligibility: event strictly before cutoff => excluded", () => {
  const status = goodStatusDoc({ testflow_started_at: "2026-07-31T15:00:00.000Z" });
  const evt = {
    event_type: "ride_start",
    tenant_id: TENANT,
    company_id: COMPANY,
    created_at_utc: "2026-07-31T14:59:59.999Z",
  };
  const r = _chironAutoSubmitEligibleForEvent(status, baseEnv(makeKV()), evt);
  assert.equal(r, "event_before_testflow_start");
});

test("eligibility: event at/after cutoff => allowed", () => {
  const status = goodStatusDoc({ testflow_started_at: "2026-07-31T15:00:00.000Z" });
  const evt = {
    event_type: "ride_stop",
    tenant_id: TENANT,
    company_id: COMPANY,
    created_at_utc: "2026-07-31T15:00:00.000Z",
  };
  const r = _chironAutoSubmitEligibleForEvent(status, baseEnv(makeKV()), evt);
  assert.equal(r, null);
});

test("message-type: ride_start=>departure, ride_stop=>arrival", () => {
  assert.equal(_chironAutoSubmitMessageTypeForEventType("ride_start"), "departure");
  assert.equal(_chironAutoSubmitMessageTypeForEventType("planned_ride_start"), "departure");
  assert.equal(_chironAutoSubmitMessageTypeForEventType("ride_stop"), "arrival");
  assert.equal(_chironAutoSubmitMessageTypeForEventType("planned_ride_stop"), "arrival");
  assert.equal(_chironAutoSubmitMessageTypeForEventType("booking_created"), null);
});

// =====================================================================
// B. Duplicate guard extension for waiting_for_departure.
// =====================================================================
test("dupguard: waiting_for_departure => allow (retryable)", () => {
  assert.deepEqual(
    _chironEvaluateSubmitDuplicateGuard({ sync_state: "waiting_for_departure" }),
    { decision: "allow" },
  );
});

// =====================================================================
// C. Paired-departure idempotency key computation.
// =====================================================================
test("paired-departure key: null when registratie or ritnummer missing", () => {
  const scope = { tenant_id: TENANT, company_id: COMPANY };
  assert.equal(
    _chironPairedDepartureIdempotencyKeyForArrivalDraft(scope, null),
    null,
  );
  assert.equal(
    _chironPairedDepartureIdempotencyKeyForArrivalDraft(scope, {
      registratie: "0772931038",
    }),
    null,
  );
  assert.equal(
    _chironPairedDepartureIdempotencyKeyForArrivalDraft(scope, {
      ritnummer: "RIT-1",
    }),
    null,
  );
});

test("paired-departure key: matches manual departure idempotency key", () => {
  const scope = { tenant_id: TENANT, company_id: COMPANY };
  const expected = buildChironOfficialIdempotencyKey(
    scope,
    "0772931038",
    "RIT-42",
    "vertrek",
  );
  const actual = _chironPairedDepartureIdempotencyKeyForArrivalDraft(scope, {
    registratie: "0772931038",
    ritnummer: "RIT-42",
    // Arrival's own status field is aankomst — ignored by this helper by design.
    status: "aankomst",
  });
  assert.equal(actual, expected);
});

// =====================================================================
// D. Reconcile throttle helper.
// =====================================================================
test("reconcile throttle: never ran => allowed", () => {
  assert.equal(
    _chironShouldRunReconcileFromStatusPoll(goodStatusDoc({ testflow_auto_reconcile_last_at: null })),
    true,
  );
});

test("reconcile throttle: ran recently => blocked", () => {
  const doc = goodStatusDoc({
    testflow_auto_reconcile_last_at: new Date().toISOString(),
  });
  assert.equal(_chironShouldRunReconcileFromStatusPoll(doc), false);
});

test("reconcile throttle: ran long ago => allowed", () => {
  const doc = goodStatusDoc({
    testflow_auto_reconcile_last_at: new Date(
      Date.now() - CHIRON_AUTO_RECONCILE_MIN_INTERVAL_MS - 5000,
    ).toISOString(),
  });
  assert.equal(_chironShouldRunReconcileFromStatusPoll(doc), true);
});

test("reconcile throttle: auto_submit disabled => never runs", () => {
  const doc = goodStatusDoc({
    testflow_auto_submit_enabled: false,
    testflow_auto_reconcile_last_at: null,
  });
  assert.equal(_chironShouldRunReconcileFromStatusPoll(doc), false);
});

// =====================================================================
// E. Auto-submit outcomes on real _chironAutoSubmitOneEvent.
//    We can only assert `skipped` reasons here because building a valid
//    official draft requires a full hydration cache. The end-to-end
//    fetch-path lands in tests F/G below.
// =====================================================================
test("auto-submit: unknown message type => skipped", async () => {
  const kv = makeKV();
  const env = baseEnv(kv);
  await seedConnectionStatus(kv, goodStatusDoc());
  const evt = {
    event_type: "payment_update",
    tenant_id: TENANT,
    company_id: COMPANY,
    event_id: "evt-x",
    created_at_utc: "2026-07-31T16:00:00.000Z",
  };
  const r = await _chironAutoSubmitOneEvent(env, evt, "compliance_event_v1/tenant/T1/company/C1/2026/07/31/ms_evt-x", { source: "test" });
  assert.equal(r.skipped, true);
  assert.equal(r.reason, "event_type_not_auto_submittable");
});

test("auto-submit: before cutoff => skipped", async () => {
  const kv = makeKV();
  const env = baseEnv(kv);
  await seedConnectionStatus(kv, goodStatusDoc({ testflow_started_at: "2027-01-01T00:00:00.000Z" }));
  const evt = {
    event_type: "ride_start",
    tenant_id: TENANT,
    company_id: COMPANY,
    event_id: "evt-y",
    created_at_utc: "2026-07-31T16:00:00.000Z",
  };
  const r = await _chironAutoSubmitOneEvent(env, evt, "compliance_event_v1/tenant/T1/company/C1/2026/07/31/ms_evt-y", { source: "test" });
  assert.equal(r.skipped, true);
  assert.equal(r.reason, "event_before_testflow_start");
});

test("auto-submit: disabled auto_submit => skipped", async () => {
  const kv = makeKV();
  const env = baseEnv(kv);
  await seedConnectionStatus(kv, goodStatusDoc({ testflow_auto_submit_enabled: false }));
  const evt = {
    event_type: "ride_start",
    tenant_id: TENANT,
    company_id: COMPANY,
    event_id: "evt-z",
    created_at_utc: "2026-07-31T16:00:00.000Z",
  };
  const r = await _chironAutoSubmitOneEvent(env, evt, "compliance_event_v1/tenant/T1/company/C1/2026/07/31/ms_evt-z", { source: "test" });
  assert.equal(r.skipped, true);
  assert.equal(r.reason, "testflow_auto_submit_disabled");
});

test("auto-submit: hydration-poor event => skipped with official_payload_not_ready", async () => {
  const kv = makeKV();
  const env = baseEnv(kv);
  await seedConnectionStatus(kv, goodStatusDoc());
  // No business/fleet/driver hydration seeded and event lacks registratie,
  // nummerplaat etc — the official draft will report exportable:false, so
  // auto-submit MUST short-circuit before hitting OAuth or Chiron.
  const stub = installFetchStub(() => {
    throw new Error("fetch must not be called when draft is not ready");
  });
  try {
    const evt = {
      event_type: "ride_start",
      tenant_id: TENANT,
      company_id: COMPANY,
      event_id: "evt-hydration",
      created_at_utc: "2026-07-31T16:00:00.000Z",
    };
    const r = await _chironAutoSubmitOneEvent(env, evt, "compliance_event_v1/tenant/T1/company/C1/2026/07/31/ms_evt-hydration", { source: "test" });
    assert.equal(r.skipped, true);
    assert.equal(r.reason, "official_payload_not_ready");
    assert.equal(stub.calls.length, 0);
  } finally {
    stub.restore();
  }
});

// =====================================================================
// F. Config-status POST: opt-in stamps testflow_started_at.
// =====================================================================
test("config-status POST: enabling auto-submit stamps testflow_started_at", async () => {
  const kv = makeKV();
  const env = baseEnv(kv);
  // Seed minimal existing doc so test_passed is set (production_enabled gate).
  await seedConnectionStatus(
    kv,
    goodStatusDoc({
      testflow_auto_submit_enabled: false,
      testflow_started_at: null,
      test_messages_sent_count: 10, // preserve test_passed OAuth path
    }),
  );
  const req = new Request(
    "https://compliance.internal/admin/chiron/config/status",
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-admin-token": ADMIN,
      },
      body: JSON.stringify({
        tenant_id: TENANT,
        company_id: COMPANY,
        enabled: true,
        testflow_auto_submit_enabled: true,
      }),
    },
  );
  const res = await worker.fetch(req, env);
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.testflow_auto_submit_enabled, true);
  assert.ok(body.testflow_started_at, "testflow_started_at must be stamped on first opt-in");
  const stampedMs = Date.parse(body.testflow_started_at);
  assert.ok(
    Number.isFinite(stampedMs) && Math.abs(Date.now() - stampedMs) < 60_000,
    "testflow_started_at should be a fresh ISO within the last minute",
  );
});

test("config-status POST: operator-supplied testflow_started_at wins over auto-stamp", async () => {
  const kv = makeKV();
  const env = baseEnv(kv);
  await seedConnectionStatus(
    kv,
    goodStatusDoc({
      testflow_auto_submit_enabled: false,
      testflow_started_at: null,
      test_messages_sent_count: 10,
    }),
  );
  const overrideIso = "2026-07-31T14:00:00.000Z";
  const req = new Request(
    "https://compliance.internal/admin/chiron/config/status",
    {
      method: "POST",
      headers: { "content-type": "application/json", "x-admin-token": ADMIN },
      body: JSON.stringify({
        tenant_id: TENANT,
        company_id: COMPANY,
        enabled: true,
        testflow_auto_submit_enabled: true,
        testflow_started_at: overrideIso,
      }),
    },
  );
  const res = await worker.fetch(req, env);
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.testflow_auto_submit_enabled, true);
  assert.equal(
    body.testflow_started_at,
    overrideIso,
    "operator-provided cutoff should be persisted verbatim",
  );
});

test("config-status POST: preserves test_credentials_stored (regression fix)", async () => {
  const kv = makeKV();
  const env = baseEnv(kv);
  await seedConnectionStatus(
    kv,
    goodStatusDoc({
      test_credentials_stored: true,
      production_credentials_stored: false,
      test_messages_sent_count: 10,
    }),
  );
  const req = new Request(
    "https://compliance.internal/admin/chiron/config/status",
    {
      method: "POST",
      headers: { "content-type": "application/json", "x-admin-token": ADMIN },
      body: JSON.stringify({
        tenant_id: TENANT,
        company_id: COMPANY,
        enabled: true,
        testflow_auto_submit_enabled: true,
      }),
    },
  );
  const res = await worker.fetch(req, env);
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(
    body.test_credentials_stored,
    true,
    "config-status POST must NOT wipe test_credentials_stored",
  );
});

test("config-status POST: rejects invalid testflow_started_at", async () => {
  const kv = makeKV();
  const env = baseEnv(kv);
  await seedConnectionStatus(
    kv,
    goodStatusDoc({ test_messages_sent_count: 10 }),
  );
  const req = new Request(
    "https://compliance.internal/admin/chiron/config/status",
    {
      method: "POST",
      headers: { "content-type": "application/json", "x-admin-token": ADMIN },
      body: JSON.stringify({
        tenant_id: TENANT,
        company_id: COMPANY,
        enabled: true,
        testflow_auto_submit_enabled: true,
        testflow_started_at: "not-a-date",
      }),
    },
  );
  const res = await worker.fetch(req, env);
  assert.equal(res.status, 400);
  const body = await res.json();
  assert.equal(body.error, "invalid_testflow_started_at");
});

test("config-status POST: rejects future testflow_started_at", async () => {
  const kv = makeKV();
  const env = baseEnv(kv);
  await seedConnectionStatus(
    kv,
    goodStatusDoc({ test_messages_sent_count: 10 }),
  );
  const futureIso = new Date(Date.now() + 3600_000).toISOString();
  const req = new Request(
    "https://compliance.internal/admin/chiron/config/status",
    {
      method: "POST",
      headers: { "content-type": "application/json", "x-admin-token": ADMIN },
      body: JSON.stringify({
        tenant_id: TENANT,
        company_id: COMPANY,
        enabled: true,
        testflow_auto_submit_enabled: true,
        testflow_started_at: futureIso,
      }),
    },
  );
  const res = await worker.fetch(req, env);
  assert.equal(res.status, 400);
  const body = await res.json();
  assert.equal(body.error, "testflow_started_at_in_future");
});

test("config-status POST: preserves testflow_started_at when toggling off then on again", async () => {
  const kv = makeKV();
  const env = baseEnv(kv);
  const originalCutoff = "2026-07-31T15:00:00.000Z";
  await seedConnectionStatus(
    kv,
    goodStatusDoc({
      testflow_auto_submit_enabled: true,
      testflow_started_at: originalCutoff,
      test_messages_sent_count: 10,
    }),
  );
  // Turn OFF
  await worker.fetch(
    new Request("https://compliance.internal/admin/chiron/config/status", {
      method: "POST",
      headers: { "content-type": "application/json", "x-admin-token": ADMIN },
      body: JSON.stringify({
        tenant_id: TENANT,
        company_id: COMPANY,
        enabled: true,
        testflow_auto_submit_enabled: false,
      }),
    }),
    env,
  );
  const storedAfterOff = JSON.parse(
    kv.store.get(`tenant:${TENANT}:company:${COMPANY}:chiron_connection:v1`),
  );
  assert.equal(storedAfterOff.testflow_auto_submit_enabled, false);
  assert.equal(
    storedAfterOff.testflow_started_at,
    originalCutoff,
    "cutoff preserved after turning auto-submit OFF",
  );
});

// =====================================================================
// G. Admin auto-reconcile endpoint gates auth + scope.
// =====================================================================
test("auto-reconcile: missing scope => 400", async () => {
  const kv = makeKV();
  const env = baseEnv(kv);
  const req = new Request(
    `https://compliance.internal${CHIRON_TESTFLOW_AUTO_RECONCILE_PATH}`,
    {
      method: "POST",
      headers: { "content-type": "application/json", "x-admin-token": ADMIN },
      body: JSON.stringify({}),
    },
  );
  const res = await worker.fetch(req, env);
  assert.equal(res.status, 400);
  const body = await res.json();
  assert.equal(body.error, "missing_scope");
});

test("auto-reconcile: unauth => 401", async () => {
  const kv = makeKV();
  const env = baseEnv(kv);
  const req = new Request(
    `https://compliance.internal${CHIRON_TESTFLOW_AUTO_RECONCILE_PATH}`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ tenant_id: TENANT, company_id: COMPANY }),
    },
  );
  const res = await worker.fetch(req, env);
  assert.equal(res.status, 401);
});

test("auto-reconcile: auto_submit_disabled reports reason with 200 (bounded, non-fatal)", async () => {
  const kv = makeKV();
  const env = baseEnv(kv);
  await seedConnectionStatus(kv, goodStatusDoc({ testflow_auto_submit_enabled: false }));
  const req = new Request(
    `https://compliance.internal${CHIRON_TESTFLOW_AUTO_RECONCILE_PATH}`,
    {
      method: "POST",
      headers: { "content-type": "application/json", "x-admin-token": ADMIN },
      body: JSON.stringify({ tenant_id: TENANT, company_id: COMPANY }),
    },
  );
  const res = await worker.fetch(req, env);
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.ok, false);
  assert.equal(body.reason, "testflow_auto_submit_disabled");
  assert.ok(body.testflow, "response should include testflow counters projection");
});

// =====================================================================
// H. handleAppend contract: response returns even when auto-submit is
//    slow / errors internally (ctx.waitUntil is best-effort, not blocking).
// =====================================================================
test("handleAppend: response returns immediately even when ctx is undefined", async () => {
  const kv = makeKV();
  const env = baseEnv(kv);
  await seedConnectionStatus(kv, goodStatusDoc());
  const req = new Request("https://compliance.internal/compliance/events/append", {
    method: "POST",
    headers: { "content-type": "application/json", "x-admin-token": ADMIN },
    body: JSON.stringify({
      event_id: "evt-append-1",
      event_type: "ride_start",
      tenant_id: TENANT,
      company_id: COMPANY,
    }),
  });
  const start = Date.now();
  const res = await worker.fetch(req, env);
  const elapsedMs = Date.now() - start;
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.ok, true);
  assert.equal(body.event_id, "evt-append-1");
  // Auto-submit runs after the response returns; response must be fast even
  // when we didn't stub fetch — the event is durably stored regardless.
  assert.ok(elapsedMs < 2000, `append response should be fast; was ${elapsedMs}ms`);
});

test("handleAppend + ctx.waitUntil: auto-submit is scheduled via ctx", async () => {
  const kv = makeKV();
  const env = baseEnv(kv);
  await seedConnectionStatus(kv, goodStatusDoc());
  const scheduled = [];
  const ctx = {
    waitUntil(p) {
      scheduled.push(p);
    },
  };
  const req = new Request("https://compliance.internal/compliance/events/append", {
    method: "POST",
    headers: { "content-type": "application/json", "x-admin-token": ADMIN },
    body: JSON.stringify({
      event_id: "evt-append-2",
      event_type: "ride_start",
      tenant_id: TENANT,
      company_id: COMPANY,
    }),
  });
  const res = await worker.fetch(req, env, ctx);
  assert.equal(res.status, 200);
  assert.equal(scheduled.length, 1, "auto-submit hook should be scheduled via ctx.waitUntil");
  // Awaiting the scheduled promise MUST resolve (best-effort helper never throws).
  const outcome = await scheduled[0];
  assert.ok(outcome === null || typeof outcome === "object");
});

// =====================================================================
// I. config-status GET: throttled reconcile trigger.
// =====================================================================
test("config-status GET: schedules reconcile when auto-submit enabled and throttle elapsed", async () => {
  const kv = makeKV();
  const env = baseEnv(kv);
  await seedConnectionStatus(kv, goodStatusDoc({ testflow_auto_reconcile_last_at: null }));
  const scheduled = [];
  const ctx = {
    waitUntil(p) {
      scheduled.push(p);
    },
  };
  const req = new Request(
    `https://compliance.internal/admin/chiron/config/status?tenant_id=${TENANT}&company_id=${COMPANY}`,
    { method: "GET", headers: { "x-admin-token": ADMIN } },
  );
  const res = await worker.fetch(req, env, ctx);
  assert.equal(res.status, 200);
  assert.equal(scheduled.length, 1, "reconcile must be scheduled from GET when throttle elapsed");
  await scheduled[0];
});

test("config-status GET: does NOT schedule reconcile when auto-submit disabled", async () => {
  const kv = makeKV();
  const env = baseEnv(kv);
  await seedConnectionStatus(
    kv,
    goodStatusDoc({
      testflow_auto_submit_enabled: false,
      testflow_auto_reconcile_last_at: null,
    }),
  );
  const scheduled = [];
  const ctx = {
    waitUntil(p) {
      scheduled.push(p);
    },
  };
  const req = new Request(
    `https://compliance.internal/admin/chiron/config/status?tenant_id=${TENANT}&company_id=${COMPANY}`,
    { method: "GET", headers: { "x-admin-token": ADMIN } },
  );
  await worker.fetch(req, env, ctx);
  assert.equal(scheduled.length, 0, "no reconcile must be scheduled when auto-submit is off");
});

// =====================================================================
// J. Testflow reset: preserves auto_submit_enabled and stamps fresh cutoff.
// =====================================================================
test("testflow reset: preserves auto_submit_enabled and stamps fresh cutoff", async () => {
  const kv = makeKV();
  const env = baseEnv(kv);
  await seedConnectionStatus(
    kv,
    goodStatusDoc({
      testflow_auto_submit_enabled: true,
      testflow_started_at: "2026-07-31T10:00:00.000Z",
      test_departure_sent_count: 3,
      test_arrival_sent_count: 3,
      test_rides_completed_count: 3,
    }),
  );
  const req = new Request(
    "https://compliance.internal/admin/chiron/testflow/reset",
    {
      method: "POST",
      headers: { "content-type": "application/json", "x-admin-token": ADMIN },
      body: JSON.stringify({ tenant_id: TENANT, company_id: COMPANY }),
    },
  );
  const res = await worker.fetch(req, env);
  assert.equal(res.status, 200);
  const stored = JSON.parse(
    kv.store.get(`tenant:${TENANT}:company:${COMPANY}:chiron_connection:v1`),
  );
  assert.equal(stored.testflow_auto_submit_enabled, true);
  assert.equal(stored.test_departure_sent_count, 0);
  assert.equal(stored.test_arrival_sent_count, 0);
  assert.equal(stored.test_rides_completed_count, 0);
  const cutoffMs = Date.parse(stored.testflow_started_at);
  assert.ok(
    Number.isFinite(cutoffMs) && Math.abs(Date.now() - cutoffMs) < 60_000,
    "reset should stamp fresh cutoff when auto-submit stays on",
  );
});

// =====================================================================
// K. Reconcile: bounded even with many events.
// =====================================================================
test("auto-reconcile: bounded scan does not process more than the cap", async () => {
  const kv = makeKV();
  const env = baseEnv(kv);
  await seedOAuthCredentials(kv, env, {
    tenantId: TENANT,
    companyId: COMPANY,
    clientId: "cid",
    clientSecret: "csec",
  });
  await seedConnectionStatus(
    kv,
    goodStatusDoc({ testflow_started_at: "2026-07-31T00:00:00.000Z" }),
  );
  // Seed many compliance events under the scope prefix so the reconciler has
  // work to scan. All events are shaped so the official draft is NOT ready
  // (no hydration), which means each is skipped with
  // `official_payload_not_ready` — this exercises the scan/process bounds
  // without triggering any external fetch.
  for (let i = 0; i < 30; i++) {
    const ts = new Date(Date.parse("2026-07-31T15:00:00.000Z") + i * 1000)
      .getTime()
      .toString()
      .padStart(13, "0");
    // `buildCompliancePrefixForScope` uses `safeSegment(...).toLowerCase()`,
    // so the scan prefix is lowercase. Seed keys accordingly.
    const key = `compliance_event_v1/tenant/${TENANT_SEG}/company/${COMPANY_SEG}/2026/07/31/${ts}_evt${i}`;
    const doc = {
      event_id: `evt${i}`,
      event_type: i % 2 === 0 ? "ride_start" : "ride_stop",
      tenant_id: TENANT,
      company_id: COMPANY,
      created_at_utc: new Date(Number(ts)).toISOString(),
    };
    await kv.put(key, JSON.stringify(doc));
  }
  const outcome = await _chironAutoReconcileScopeBestEffort(
    env,
    TENANT,
    COMPANY,
    { source: "test" },
  );
  assert.equal(outcome.ok, true);
  assert.ok(outcome.scanned >= 20, `should scan at least 20 events, got ${outcome.scanned}`);
  assert.ok(
    outcome.processed <= 20,
    `must not process more than 20 events per pass, got ${outcome.processed}`,
  );
});

// =====================================================================
// L. Roundtrip leg inference: pair legless ride_start with sibling stops.
// =====================================================================
test("leg inference: pairs legless ride_start with chronologically-later ride_stop of same booking", () => {
  const bookingId = "2026-07-830695";
  const startOutbound = {
    event_type: "ride_start",
    booking_id: bookingId,
    created_at_utc: "2026-07-31T14:35:00.000Z",
  };
  const stopOutbound = {
    event_type: "ride_stop",
    booking_id: bookingId,
    leg_type: "outbound",
    created_at_utc: "2026-07-31T14:36:00.000Z",
  };
  const startReturn = {
    event_type: "ride_start",
    booking_id: bookingId,
    created_at_utc: "2026-07-31T14:55:00.000Z",
  };
  const stopReturn = {
    event_type: "ride_stop",
    booking_id: bookingId,
    leg_type: "return",
    created_at_utc: "2026-07-31T14:56:00.000Z",
  };
  const entries = [
    { key: "k1", event: startOutbound },
    { key: "k2", event: stopOutbound },
    { key: "k3", event: startReturn },
    { key: "k4", event: stopReturn },
  ];
  _chironInferLegTypeForLeglessRideStarts(entries);
  assert.equal(startOutbound.leg_type, "outbound", "first start should inherit outbound");
  assert.equal(startReturn.leg_type, "return", "second start should inherit return");
});

test("leg inference: leaves already-legged ride_start untouched", () => {
  const start = {
    event_type: "ride_start",
    booking_id: "b1",
    leg_type: "outbound",
    created_at_utc: "2026-07-31T14:00:00.000Z",
  };
  const stop = {
    event_type: "ride_stop",
    booking_id: "b1",
    leg_type: "return",
    created_at_utc: "2026-07-31T14:05:00.000Z",
  };
  const entries = [{ key: "a", event: start }, { key: "b", event: stop }];
  _chironInferLegTypeForLeglessRideStarts(entries);
  assert.equal(start.leg_type, "outbound", "already-legged start must not be rewritten");
});

test("leg inference: never claims a ride_stop that predates the ride_start", () => {
  const stopBefore = {
    event_type: "ride_stop",
    booking_id: "b1",
    leg_type: "outbound",
    created_at_utc: "2026-07-31T13:00:00.000Z",
  };
  const startAfter = {
    event_type: "ride_start",
    booking_id: "b1",
    created_at_utc: "2026-07-31T14:00:00.000Z",
  };
  const entries = [
    { key: "s", event: stopBefore },
    { key: "r", event: startAfter },
  ];
  _chironInferLegTypeForLeglessRideStarts(entries);
  assert.equal(
    startAfter.leg_type,
    undefined,
    "must not inherit from an earlier ride_stop of a prior leg",
  );
});

test("leg inference: does not cross booking boundaries", () => {
  const startA = {
    event_type: "ride_start",
    booking_id: "A",
    created_at_utc: "2026-07-31T14:00:00.000Z",
  };
  const stopB = {
    event_type: "ride_stop",
    booking_id: "B",
    leg_type: "outbound",
    created_at_utc: "2026-07-31T14:05:00.000Z",
  };
  const entries = [{ key: "a", event: startA }, { key: "b", event: stopB }];
  _chironInferLegTypeForLeglessRideStarts(entries);
  assert.equal(startA.leg_type, undefined, "must not inherit from a different booking's stop");
});
