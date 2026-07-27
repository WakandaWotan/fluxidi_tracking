// MOLLIE-LIVE-STATUS-DIAGNOSTICS-P0-1
// Prove sanitized stage diagnostics on GET /admin/mollie/connect/status?refresh=live
// without changing fail-soft status / payment / OAuth semantics.
//
// Run:
//   node --test workers/booking/mollie_live_status_diagnostics_p0.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import worker from "./fluxidi_booking_worker.js";
import {
  buildScopedMollieConnectAuthKey,
  encryptMollieConnectTokenPayload,
  createMollieLiveStatusDiag,
  logMollieLiveStatusDiag,
  refreshMollieOnboardingCapabilityStatus,
} from "./modules/mollie_connect.js";

const ADMIN = "test-admin-token";
const ENC_KEY = "test-mollie-connect-encryption-key-please-rotate";

const SECRET_MARKERS = [
  "access-token-abc",
  "refresh-token-abc",
  "Bearer ",
  "Authorization",
  "org_test_1",
  "pfl_test_1",
  "access_token\":",
  "refresh_token\":",
  "test-client-secret",
];

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
      const prefix = String(opts?.prefix || "");
      const keys = [...store.keys()].filter((name) =>
        prefix ? name.startsWith(prefix) : true,
      );
      return { keys: keys.map((name) => ({ name })), list_complete: true };
    },
  };
}

function baseEnv(bookingKv, extra = {}) {
  return {
    ADMIN_TOKEN: ADMIN,
    BOOKING_KV: bookingKv,
    MOLLIE_CONNECT_ENCRYPTION_KEY: ENC_KEY,
    MOLLIE_CONNECT_CLIENT_ID: "test-client-id",
    MOLLIE_CONNECT_CLIENT_SECRET: "test-client-secret",
    ...extra,
  };
}

async function seedMollieConnectRecord(
  bookingKv,
  scope,
  {
    connected = true,
    status = "connected",
    mollieMode = "live",
    onboardingStatus = "completed",
    canReceivePayments = true,
    organizationId = "org_test_1",
    profileId = "pfl_test_1",
    accessToken = "access-token-abc",
    refreshToken = "refresh-token-abc",
    expiresAt = new Date(Date.now() + 3_600_000).toISOString(),
    lastConnectedAt = new Date().toISOString(),
  } = {},
) {
  const key = buildScopedMollieConnectAuthKey(scope);
  const encryptedTokens = accessToken
    ? await encryptMollieConnectTokenPayload(
        { access_token: accessToken, refresh_token: refreshToken },
        { MOLLIE_CONNECT_ENCRYPTION_KEY: ENC_KEY },
      )
    : {};
  const record = {
    version: 1,
    connected,
    status,
    organizationId,
    profileId,
    mollie_mode: mollieMode,
    onboardingStatus,
    canReceivePayments,
    expiresAt,
    expires_at: expiresAt,
    ...encryptedTokens,
    lastConnectedAt,
    updatedAt: lastConnectedAt,
  };
  await bookingKv.put(key, JSON.stringify(record));
  return { key, record };
}

async function seedBusinessProfileMollieConnected(bookingKv, { tenantId, companyId }, connected) {
  const key = `tenant:${tenantId}:company:${companyId}:business_profile:v1`;
  await bookingKv.put(
    key,
    JSON.stringify({
      business_profile: { mollie_connected: connected, mollieConnected: connected },
    }),
  );
}

function statusRequest({ tenantId, companyId, live = true }) {
  const url = new URL("https://booking.internal/admin/mollie/connect/status");
  url.searchParams.set("tenant_id", tenantId);
  url.searchParams.set("company_id", companyId);
  if (live) url.searchParams.set("refresh", "live");
  return new Request(url.toString(), {
    method: "GET",
    headers: { "x-admin-token": ADMIN },
  });
}

function captureLiveStatusLogs() {
  const lines = [];
  const original = console.log;
  console.log = (...args) => {
    const text = args.map((a) => String(a)).join(" ");
    if (text.includes("[MOLLIE_LIVE_STATUS]")) lines.push(text);
    // Keep other logs quiet during these tests.
  };
  return {
    lines,
    events() {
      return lines.map((line) => {
        const idx = line.indexOf("{");
        assert.ok(idx >= 0, `expected JSON payload in ${line}`);
        return JSON.parse(line.slice(idx));
      });
    },
    restore() {
      console.log = original;
    },
  };
}

function assertNoSecrets(lines) {
  const joined = lines.join("\n");
  for (const marker of SECRET_MARKERS) {
    assert.equal(
      joined.includes(marker),
      false,
      `log must not contain secret/id marker ${marker}`,
    );
  }
  assert.equal(joined.includes("fluxidi_fluxidi_"), false);
  assert.equal(/\borg_[A-Za-z0-9]+\b/.test(joined), false);
  assert.equal(/\bpfl_[A-Za-z0-9]+\b/.test(joined), false);
  assert.equal(/"company_id"\s*:/.test(joined), false);
  assert.equal(/"tenant_id"\s*:/.test(joined), false);
  assert.equal(/"access_token"\s*:/.test(joined), false);
  assert.equal(/"refresh_token"\s*:/.test(joined), false);
  // Boolean presence flags are allowed; raw token values are not.
  assert.equal(/access-token-[A-Za-z0-9]+/.test(joined), false);
  assert.equal(/refresh-token-[A-Za-z0-9]+/.test(joined), false);
}

function stagesOf(events) {
  return events.map((e) => e.stage);
}

function mockFetchRouter(handlers) {
  const original = global.fetch;
  global.fetch = async (input, init) => {
    const href = String(typeof input === "string" ? input : input?.url || "");
    for (const [needle, handler] of handlers) {
      if (href.includes(needle)) return handler(input, init, href);
    }
    return original
      ? original(input, init)
      : new Response("{}", { status: 200, headers: { "content-type": "application/json" } });
  };
  return () => {
    global.fetch = original;
  };
}

test("logger allowlists fields and strips secrets/ids", () => {
  const cap = captureLiveStatusLogs();
  try {
    logMollieLiveStatusDiag({
      stage: "live_status_failed",
      auth_mode: "company_session",
      correlation_id: "corr-1",
      mollie_error_code: "mollie_onboarding_lookup_failed",
      access_token: "access-token-abc",
      refresh_token: "refresh-token-abc",
      Authorization: "Bearer secret",
      company_id: "C1",
      organization_id: "org_test_1",
      profile_id: "pfl_test_1",
      body: { detail: "should never appear" },
    });
    assert.equal(cap.lines.length, 1);
    const event = cap.events()[0];
    assert.equal(event.stage, "live_status_failed");
    assert.equal(event.mollie_error_code, "mollie_onboarding_lookup_failed");
    assert.equal(event.access_token, undefined);
    assert.equal(event.company_id, undefined);
    assert.equal(event.body, undefined);
    assertNoSecrets(cap.lines);
  } finally {
    cap.restore();
  }
});

test("response_mapping_failed stage is accepted by sanitized logger", () => {
  const diag = createMollieLiveStatusDiag({
    authMode: "admin_token",
    correlationId: "corr-map",
  });
  const cap = captureLiveStatusLogs();
  try {
    diag.emit("response_mapping_failed", {
      mollie_error_code: "mollie_onboarding_status_persist_failed",
      status_check: "failed",
    });
    const events = cap.events();
    assert.deepEqual(stagesOf(events), ["response_mapping_failed"]);
    assert.equal(events[0].correlation_id, "corr-map");
    assertNoSecrets(cap.lines);
  } finally {
    cap.restore();
  }
});

test("live refresh success logs request/credential/mollie/mapping/success stages", async () => {
  const bookingKv = makeKV();
  const env = baseEnv(bookingKv);
  const seeded = await seedMollieConnectRecord(
    bookingKv,
    { tenant_id: "T1", company_id: "C1" },
    { onboardingStatus: "in-review", canReceivePayments: false },
  );
  await seedBusinessProfileMollieConnected(bookingKv, { tenantId: "T1", companyId: "C1" }, true);
  const restoreFetch = mockFetchRouter([
    [
      "api.mollie.com/v2/onboarding/me",
      async () =>
        new Response(
          JSON.stringify({ status: "completed", canReceivePayments: true }),
          { status: 200, headers: { "content-type": "application/json" } },
        ),
    ],
  ]);
  const cap = captureLiveStatusLogs();
  try {
    const res = await worker.fetch(
      statusRequest({ tenantId: "T1", companyId: "C1", live: true }),
      env,
      {},
    );
    const j = await res.json();
    assert.equal(res.status, 200);
    assert.equal(j.status_check, "ok");
    assert.equal(j.can_receive_payments, true);

    const stages = stagesOf(cap.events());
    assert.ok(stages.includes("request_received"));
    assert.ok(stages.includes("credential_resolve_started"));
    assert.ok(stages.includes("credential_resolve_completed"));
    assert.ok(stages.includes("mollie_status_request_started"));
    assert.ok(stages.includes("mollie_status_response_received"));
    assert.ok(stages.includes("response_mapping_started"));
    assert.ok(stages.includes("response_mapping_completed"));
    assert.ok(stages.includes("live_status_succeeded"));
    assert.equal(stages.includes("live_status_failed"), false);
    assertNoSecrets(cap.lines);

    const success = cap.events().find((e) => e.stage === "live_status_succeeded");
    assert.equal(success.status_check, "ok");
    assert.equal(success.upstream_endpoint_name, "onboarding_me");
    assert.equal(success.can_receive_payments, true);
    assert.equal(typeof success.correlation_id, "string");
    assert.ok(success.correlation_id.length > 0);
    assert.equal(typeof success.duration_ms, "number");

    // OAuth material unchanged on successful capability refresh.
    const stored = JSON.parse(bookingKv.store.get(seeded.key));
    assert.deepEqual(stored.accessTokenEncrypted, seeded.record.accessTokenEncrypted);
    assert.deepEqual(stored.refreshTokenEncrypted, seeded.record.refreshTokenEncrypted);
  } finally {
    cap.restore();
    restoreFetch();
  }
});

test("mollie upstream failure logs failed stages, preserves confirmed status, no OAuth mutation", async () => {
  const bookingKv = makeKV();
  const env = baseEnv(bookingKv);
  const seeded = await seedMollieConnectRecord(
    bookingKv,
    { tenant_id: "T1", company_id: "C1" },
    { onboardingStatus: "completed", canReceivePayments: true },
  );
  await seedBusinessProfileMollieConnected(bookingKv, { tenantId: "T1", companyId: "C1" }, true);
  const restoreFetch = mockFetchRouter([
    [
      "api.mollie.com/v2/onboarding/me",
      async () =>
        new Response(
          JSON.stringify({
            status: 401,
            title: "Unauthorized Request",
            type: "https://docs.mollie.com/error-messages/unauthorized-request",
            detail: "Access token ABC should never be logged",
          }),
          { status: 401, headers: { "content-type": "application/json" } },
        ),
    ],
  ]);
  const cap = captureLiveStatusLogs();
  try {
    const res = await worker.fetch(
      statusRequest({ tenantId: "T1", companyId: "C1", live: true }),
      env,
      {},
    );
    const j = await res.json();
    assert.equal(res.status, 200);
    assert.equal(j.status_check, "failed");
    assert.equal(j.status_check_error, "mollie_onboarding_lookup_failed");
    assert.equal(j.onboarding_status, "completed");
    assert.equal(j.can_receive_payments, true);

    const stages = stagesOf(cap.events());
    assert.ok(stages.includes("request_received"));
    assert.ok(stages.includes("credential_resolve_completed"));
    assert.ok(stages.includes("mollie_status_request_started"));
    assert.ok(stages.includes("mollie_status_request_failed"));
    assert.ok(stages.includes("live_status_failed"));
    assert.equal(stages.includes("live_status_succeeded"), false);

    const failed = cap.events().find((e) => e.stage === "mollie_status_request_failed");
    assert.equal(failed.upstream_endpoint_name, "onboarding_me");
    assert.equal(failed.upstream_http_status, 401);
    assert.equal(failed.mollie_error_type, "unauthorized-request");
    assert.equal(failed.mollie_error_code, "401");
    assertNoSecrets(cap.lines);
    assert.equal(cap.lines.join("\n").includes("Access token ABC"), false);
    assert.equal(cap.lines.join("\n").includes("should never be logged"), false);

    const stored = JSON.parse(bookingKv.store.get(seeded.key));
    assert.equal(stored.onboardingStatus, "completed");
    assert.equal(stored.canReceivePayments, true);
    assert.deepEqual(stored.accessTokenEncrypted, seeded.record.accessTokenEncrypted);
    assert.deepEqual(stored.refreshTokenEncrypted, seeded.record.refreshTokenEncrypted);
  } finally {
    cap.restore();
    restoreFetch();
  }
});

test("credential resolve failure logs sanitized stage/code and preserves status", async () => {
  const bookingKv = makeKV();
  const env = baseEnv(bookingKv);
  // Gate uses hasSuccessfulMollieConnectRecord (lenient), resolve requires
  // connected===true && status==="connected". Seed a successful-looking but
  // disconnected-status record so live refresh runs and credential resolve fails.
  const seeded = await seedMollieConnectRecord(
    bookingKv,
    { tenant_id: "T1", company_id: "C1" },
    {
      connected: false,
      status: "pending",
      onboardingStatus: "completed",
      canReceivePayments: true,
      lastConnectedAt: new Date().toISOString(),
    },
  );
  await seedBusinessProfileMollieConnected(bookingKv, { tenantId: "T1", companyId: "C1" }, true);
  const cap = captureLiveStatusLogs();
  try {
    const res = await worker.fetch(
      statusRequest({ tenantId: "T1", companyId: "C1", live: true }),
      env,
      {},
    );
    const j = await res.json();
    assert.equal(res.status, 200);
    assert.equal(j.status_check, "failed");
    assert.equal(j.status_check_error, "company_mollie_not_connected");
    assert.equal(j.can_receive_payments, true);
    assert.equal(j.onboarding_status, "completed");

    const stages = stagesOf(cap.events());
    assert.ok(stages.includes("credential_resolve_started"));
    assert.ok(stages.includes("credential_resolve_failed"));
    assert.ok(stages.includes("live_status_failed"));
    const failed = cap.events().find((e) => e.stage === "credential_resolve_failed");
    assert.equal(failed.mollie_error_code, "company_mollie_not_connected");
    assertNoSecrets(cap.lines);

    const stored = JSON.parse(bookingKv.store.get(seeded.key));
    assert.equal(stored.onboardingStatus, "completed");
    assert.equal(stored.canReceivePayments, true);
    assert.deepEqual(stored.accessTokenEncrypted, seeded.record.accessTokenEncrypted);
  } finally {
    cap.restore();
  }
});

test("token refresh failure logs token_refresh_failed with sanitized code", async () => {
  const bookingKv = makeKV();
  const env = baseEnv(bookingKv);
  const seeded = await seedMollieConnectRecord(
    bookingKv,
    { tenant_id: "T1", company_id: "C1" },
    {
      onboardingStatus: "completed",
      canReceivePayments: true,
      expiresAt: new Date(Date.now() - 60_000).toISOString(),
    },
  );
  await seedBusinessProfileMollieConnected(bookingKv, { tenantId: "T1", companyId: "C1" }, true);
  const restoreFetch = mockFetchRouter([
    [
      "api.mollie.com/oauth2/tokens",
      async () =>
        new Response(JSON.stringify({ error: "invalid_grant" }), {
          status: 400,
          headers: { "content-type": "application/json" },
        }),
    ],
  ]);
  const cap = captureLiveStatusLogs();
  try {
    const res = await worker.fetch(
      statusRequest({ tenantId: "T1", companyId: "C1", live: true }),
      env,
      {},
    );
    const j = await res.json();
    assert.equal(res.status, 200);
    assert.equal(j.status_check, "failed");
    assert.equal(j.status_check_error, "company_mollie_token_refresh_failed");
    assert.equal(j.can_receive_payments, true);

    const stages = stagesOf(cap.events());
    assert.ok(stages.includes("token_refresh_started"));
    assert.ok(stages.includes("token_refresh_failed"));
    assert.ok(stages.includes("credential_resolve_failed"));
    assert.ok(stages.includes("live_status_failed"));
    const tokFail = cap.events().find((e) => e.stage === "token_refresh_failed");
    assert.equal(tokFail.mollie_error_code, "company_mollie_token_refresh_failed");
    assert.equal(tokFail.upstream_endpoint_name, "oauth2_tokens");
    assert.equal(tokFail.token_refresh_attempted, true);
    assertNoSecrets(cap.lines);

    const stored = JSON.parse(bookingKv.store.get(seeded.key));
    assert.equal(stored.onboardingStatus, "completed");
    assert.equal(stored.canReceivePayments, true);
    assert.deepEqual(stored.accessTokenEncrypted, seeded.record.accessTokenEncrypted);
    assert.deepEqual(stored.refreshTokenEncrypted, seeded.record.refreshTokenEncrypted);
  } finally {
    cap.restore();
    restoreFetch();
  }
});

test("direct refresh helper does not mutate payment/OAuth state on upstream failure", async () => {
  const bookingKv = makeKV();
  const env = baseEnv(bookingKv);
  const seeded = await seedMollieConnectRecord(
    bookingKv,
    { tenant_id: "T1", company_id: "C1" },
    { onboardingStatus: "completed", canReceivePayments: true },
  );
  const beforeKeys = [...bookingKv.store.keys()].sort();
  const restoreFetch = mockFetchRouter([
    [
      "api.mollie.com/v2/onboarding/me",
      async () => new Response("nope", { status: 503 }),
    ],
  ]);
  const diag = createMollieLiveStatusDiag({ authMode: "admin_token" });
  const cap = captureLiveStatusLogs();
  try {
    const result = await refreshMollieOnboardingCapabilityStatus(
      env,
      { tenant_id: "T1", company_id: "C1" },
      { diag },
    );
    assert.equal(result.ok, false);
    assert.equal(result.code, "mollie_onboarding_lookup_failed");
    const stages = stagesOf(cap.events());
    assert.ok(stages.includes("mollie_status_request_failed"));
    assert.ok(stages.includes("live_status_failed"));
    assertNoSecrets(cap.lines);

    const afterKeys = [...bookingKv.store.keys()].sort();
    assert.deepEqual(afterKeys, beforeKeys);
    const stored = JSON.parse(bookingKv.store.get(seeded.key));
    assert.equal(stored.onboardingStatus, "completed");
    assert.equal(stored.canReceivePayments, true);
    assert.deepEqual(stored.accessTokenEncrypted, seeded.record.accessTokenEncrypted);
  } finally {
    cap.restore();
    restoreFetch();
  }
});

test("non-live status read emits no MOLLIE_LIVE_STATUS diagnostics", async () => {
  const bookingKv = makeKV();
  const env = baseEnv(bookingKv);
  await seedMollieConnectRecord(bookingKv, { tenant_id: "T1", company_id: "C1" });
  await seedBusinessProfileMollieConnected(bookingKv, { tenantId: "T1", companyId: "C1" }, true);
  const cap = captureLiveStatusLogs();
  try {
    const res = await worker.fetch(
      statusRequest({ tenantId: "T1", companyId: "C1", live: false }),
      env,
      {},
    );
    assert.equal(res.status, 200);
    assert.equal(cap.lines.length, 0);
  } finally {
    cap.restore();
  }
});
