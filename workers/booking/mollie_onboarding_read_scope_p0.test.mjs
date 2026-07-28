// MOLLIE-ONBOARDING-READ-SCOPE-P0-1
//
// Run:
//   node --test workers/booking/mollie_onboarding_read_scope_p0.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import worker from "./fluxidi_booking_worker.js";
import {
  MOLLIE_CONNECT_OAUTH_SCOPES,
  MOLLIE_CONNECT_ONBOARDING_READ_SCOPE,
  buildScopedMollieConnectAuthKey,
  encryptMollieConnectTokenPayload,
  normalizeMollieConnectGrantedScopes,
  mollieConnectGrantedScopesInclude,
  sanitizeMollieConnectStatus,
  createMollieLiveStatusDiag,
  logMollieLiveStatusDiag,
} from "./modules/mollie_connect.js";

const ADMIN = "test-admin-token";
const ENC_KEY = "test-mollie-connect-encryption-key-please-rotate";
const CLIENT_ID = "test-client-id";
const CLIENT_SECRET = "test-client-secret";
const STATE_SECRET = "test-mollie-connect-state-secret-please-rotate";

const PREVIOUS_SCOPES = [
  "organizations.read",
  "profiles.read",
  "payments.read",
  "payments.write",
  "refunds.read",
  "terminals.read",
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
    async list() {
      return { keys: [...store.keys()].map((name) => ({ name })), list_complete: true };
    },
  };
}

function baseEnv(bookingKv) {
  return {
    ADMIN_TOKEN: ADMIN,
    BOOKING_KV: bookingKv,
    MOLLIE_CONNECT_ENCRYPTION_KEY: ENC_KEY,
    MOLLIE_CONNECT_CLIENT_ID: CLIENT_ID,
    MOLLIE_CONNECT_CLIENT_SECRET: CLIENT_SECRET,
    MOLLIE_CONNECT_STATE_SECRET: STATE_SECRET,
  };
}

async function seedMollieConnectRecord(
  bookingKv,
  scope,
  {
    accessToken = "access-token-abc",
    refreshToken = "refresh-token-abc",
    onboardingStatus = "completed",
    canReceivePayments = true,
    oauthScopes = null,
  } = {},
) {
  const key = buildScopedMollieConnectAuthKey(scope);
  const encryptedTokens = await encryptMollieConnectTokenPayload(
    { access_token: accessToken, refresh_token: refreshToken },
    { MOLLIE_CONNECT_ENCRYPTION_KEY: ENC_KEY },
  );
  const record = {
    version: 1,
    connected: true,
    status: "connected",
    organizationId: "org_test_1",
    profileId: "pfl_test_1",
    mollie_mode: "live",
    onboardingStatus,
    canReceivePayments,
    ...(oauthScopes
      ? { oauthScopes, oauth_scopes: oauthScopes }
      : {}),
    ...encryptedTokens,
    lastConnectedAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
  };
  await bookingKv.put(key, JSON.stringify(record));
  return { key, record };
}

async function seedBusinessProfile(bookingKv, { tenantId, companyId }) {
  const key = `tenant:${tenantId}:company:${companyId}:business_profile:v1`;
  await bookingKv.put(
    key,
    JSON.stringify({
      business_profile: { mollie_connected: true, mollieConnected: true },
    }),
  );
}

function statusRequest({ tenantId, companyId, live = false }) {
  const url = new URL("https://booking.internal/admin/mollie/connect/status");
  url.searchParams.set("tenant_id", tenantId);
  url.searchParams.set("company_id", companyId);
  if (live) url.searchParams.set("refresh", "live");
  return new Request(url.toString(), {
    method: "GET",
    headers: { "x-admin-token": ADMIN },
  });
}

function startRequest({ tenantId, companyId }) {
  const url = new URL("https://booking.internal/admin/mollie/connect/start");
  return new Request(url.toString(), {
    method: "POST",
    headers: {
      "x-admin-token": ADMIN,
      "content-type": "application/json",
    },
    body: JSON.stringify({ tenant_id: tenantId, company_id: companyId }),
  });
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

function captureLogs() {
  const lines = [];
  const original = console.log;
  console.log = (...args) => {
    lines.push(args.map((a) => String(a)).join(" "));
  };
  return {
    lines,
    restore() {
      console.log = original;
    },
  };
}

test("OAuth authorize scopes include onboarding.read exactly once and keep prior payment scopes", async () => {
  const bookingKv = makeKV();
  const env = baseEnv(bookingKv);
  const res = await worker.fetch(
    startRequest({ tenantId: "T1", companyId: "C1" }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 200);
  assert.equal(j.ok, true);
  const authUrl = new URL(j.auth_url);
  const scope = authUrl.searchParams.get("scope") || "";
  const parts = scope.split(/\s+/).filter(Boolean);
  assert.equal(scope, MOLLIE_CONNECT_OAUTH_SCOPES);
  assert.equal(
    parts.filter((p) => p === MOLLIE_CONNECT_ONBOARDING_READ_SCOPE).length,
    1,
  );
  for (const prev of PREVIOUS_SCOPES) {
    assert.ok(parts.includes(prev), `missing prior scope ${prev}`);
  }
});

test("normalizeMollieConnectGrantedScopes is deterministic and secret-free", () => {
  const normalized = normalizeMollieConnectGrantedScopes(
    "payments.write  onboarding.read organizations.read payments.write",
  );
  assert.equal(
    normalized,
    "organizations.read payments.write onboarding.read",
  );
  assert.equal(
    mollieConnectGrantedScopesInclude(normalized, "onboarding.read"),
    true,
  );
  assert.equal(
    mollieConnectGrantedScopesInclude("", "onboarding.read"),
    false,
  );
});

test("sanitize exposes oauth_scopes / onboarding_read_granted; legacy nulls remain null", () => {
  const legacy = sanitizeMollieConnectStatus(
    {
      connected: true,
      status: "connected",
      canReceivePayments: true,
      accessTokenEncrypted: { v: 1 },
      refreshTokenEncrypted: { v: 1 },
    },
    { mollie_connected: true },
  );
  assert.equal(legacy.oauth_scopes, null);
  assert.equal(legacy.onboarding_read_granted, null);
  assert.equal(legacy.can_receive_payments, true);

  const withScopes = sanitizeMollieConnectStatus(
    {
      connected: true,
      status: "connected",
      oauthScopes: "payments.read onboarding.read",
      accessTokenEncrypted: { v: 1 },
      refreshTokenEncrypted: { v: 1 },
    },
    { mollie_connected: true },
  );
  assert.equal(withScopes.onboarding_read_granted, true);
  assert.ok(withScopes.oauth_scopes.includes("onboarding.read"));
  assert.equal(withScopes.oauth_scopes.includes("access-token"), false);
});

test("HTTP 403 from onboarding/me maps to mollie_onboarding_permission_missing and preserves confirmed status", async () => {
  const bookingKv = makeKV();
  const env = baseEnv(bookingKv);
  const seeded = await seedMollieConnectRecord(
    bookingKv,
    { tenant_id: "T1", company_id: "C1" },
    { onboardingStatus: "completed", canReceivePayments: true },
  );
  await seedBusinessProfile(bookingKv, { tenantId: "T1", companyId: "C1" });
  const restore = mockFetchRouter([
    [
      "api.mollie.com/v2/onboarding/me",
      async () =>
        new Response(
          JSON.stringify({
            status: 403,
            title: "Forbidden",
            type: "https://docs.mollie.com/error-messages/forbidden",
            detail: "Access token SECRET must never appear",
          }),
          { status: 403, headers: { "content-type": "application/json" } },
        ),
    ],
  ]);
  const logs = captureLogs();
  try {
    const res = await worker.fetch(
      statusRequest({ tenantId: "T1", companyId: "C1", live: true }),
      env,
      {},
    );
    const j = await res.json();
    assert.equal(res.status, 200);
    assert.equal(j.status_check, "failed");
    assert.equal(j.status_check_error, "mollie_onboarding_permission_missing");
    assert.equal(j.connected, true);
    assert.equal(j.onboarding_status, "completed");
    assert.equal(j.can_receive_payments, true);

    const stored = JSON.parse(bookingKv.store.get(seeded.key));
    assert.equal(stored.onboardingStatus, "completed");
    assert.equal(stored.canReceivePayments, true);
    assert.equal(stored.last_status_check_error, "mollie_onboarding_permission_missing");
    assert.deepEqual(stored.accessTokenEncrypted, seeded.record.accessTokenEncrypted);

    const joined = logs.lines.join("\n");
    assert.equal(joined.includes("access-token-abc"), false);
    assert.equal(joined.includes("SECRET"), false);
    assert.equal(joined.includes("org_test_1"), false);
    assert.equal(joined.includes("pfl_test_1"), false);
  } finally {
    logs.restore();
    restore();
  }
});

test("failed reconnect preserves existing credentials (error path does not wipe tokens)", async () => {
  const bookingKv = makeKV();
  const env = baseEnv(bookingKv);
  const seeded = await seedMollieConnectRecord(
    bookingKv,
    { tenant_id: "T1", company_id: "C1" },
  );
  await seedBusinessProfile(bookingKv, { tenantId: "T1", companyId: "C1" });

  // Cancelled OAuth (error=access_denied) must not touch KV credentials.
  const cancelUrl = new URL("https://booking.internal/mollie/connect/callback");
  cancelUrl.searchParams.set("error", "access_denied");
  const cancelRes = await worker.fetch(new Request(cancelUrl.toString()), env, {});
  assert.equal(cancelRes.status, 400);
  const afterCancel = JSON.parse(bookingKv.store.get(seeded.key));
  assert.deepEqual(afterCancel.accessTokenEncrypted, seeded.record.accessTokenEncrypted);
  assert.deepEqual(afterCancel.refreshTokenEncrypted, seeded.record.refreshTokenEncrypted);
  assert.equal(afterCancel.connected, true);
});

test("successful reconnect atomically replaces credentials and persists granted scopes", async () => {
  const bookingKv = makeKV();
  const env = baseEnv(bookingKv);
  const seeded = await seedMollieConnectRecord(
    bookingKv,
    { tenant_id: "T1", company_id: "C1" },
    { accessToken: "old-access", refreshToken: "old-refresh" },
  );
  await seedBusinessProfile(bookingKv, { tenantId: "T1", companyId: "C1" });

  // Start to create a valid nonce/state, then simulate callback with code.
  const startRes = await worker.fetch(
    startRequest({ tenantId: "T1", companyId: "C1" }),
    env,
    {},
  );
  const startJson = await startRes.json();
  const authUrl = new URL(startJson.auth_url);
  const state = authUrl.searchParams.get("state");
  assert.ok(state);

  const restore = mockFetchRouter([
    [
      "api.mollie.com/oauth2/tokens",
      async () =>
        new Response(
          JSON.stringify({
            access_token: "new-access-token",
            refresh_token: "new-refresh-token",
            expires_in: 3600,
            scope: MOLLIE_CONNECT_OAUTH_SCOPES,
            token_type: "bearer",
          }),
          { status: 200, headers: { "content-type": "application/json" } },
        ),
    ],
    [
      "api.mollie.com/v2/organizations/me",
      async () =>
        new Response(JSON.stringify({ id: "org_new" }), {
          status: 200,
          headers: { "content-type": "application/json" },
        }),
    ],
    [
      "api.mollie.com/v2/profiles",
      async () =>
        new Response(
          JSON.stringify({
            _embedded: { profiles: [{ id: "pfl_new", mode: "live", status: "verified" }] },
          }),
          { status: 200, headers: { "content-type": "application/json" } },
        ),
    ],
    [
      "api.mollie.com/v2/onboarding/me",
      async () =>
        new Response(
          JSON.stringify({ status: "completed", canReceivePayments: true }),
          { status: 200, headers: { "content-type": "application/json" } },
        ),
    ],
  ]);
  const logs = captureLogs();
  try {
    const cbUrl = new URL("https://booking.internal/mollie/connect/callback");
    cbUrl.searchParams.set("code", "auth-code-xyz");
    cbUrl.searchParams.set("state", state);
    const cbRes = await worker.fetch(new Request(cbUrl.toString()), env, {});
    assert.equal(cbRes.status, 200);

    const stored = JSON.parse(bookingKv.store.get(seeded.key));
    assert.equal(stored.connected, true);
    assert.notDeepEqual(stored.accessTokenEncrypted, seeded.record.accessTokenEncrypted);
    assert.ok(String(stored.oauthScopes || "").includes("onboarding.read"));
    assert.equal(stored.last_status_check_error, null);

    const joined = logs.lines.join("\n");
    assert.equal(joined.includes("new-access-token"), false);
    assert.equal(joined.includes("new-refresh-token"), false);
    assert.equal(joined.includes("auth-code-xyz"), false);
  } finally {
    logs.restore();
    restore();
  }
});

test("records without stored scope remain readable; payment status fields unchanged", async () => {
  const bookingKv = makeKV();
  const env = baseEnv(bookingKv);
  await seedMollieConnectRecord(bookingKv, { tenant_id: "T1", company_id: "C1" });
  await seedBusinessProfile(bookingKv, { tenantId: "T1", companyId: "C1" });
  const res = await worker.fetch(
    statusRequest({ tenantId: "T1", companyId: "C1", live: false }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 200);
  assert.equal(j.connected, true);
  assert.equal(j.can_receive_payments, true);
  assert.equal(j.oauth_scopes, null);
  assert.equal(j.onboarding_read_granted, null);
});

test("diag logger still strips secrets when emitting permission-missing stage", () => {
  const logs = captureLogs();
  try {
    logMollieLiveStatusDiag({
      stage: "live_status_failed",
      mollie_error_code: "mollie_onboarding_permission_missing",
      access_token: "access-token-abc",
      company_id: "C1",
      organization_id: "org_test_1",
    });
    assert.equal(logs.lines.length, 1);
    assert.equal(logs.lines[0].includes("access-token-abc"), false);
    assert.equal(logs.lines[0].includes("org_test_1"), false);
    assert.equal(logs.lines[0].includes("company_id"), false);
    const diag = createMollieLiveStatusDiag({ authMode: "company_session" });
    diag.emit("live_status_failed", {
      mollie_error_code: "mollie_onboarding_permission_missing",
      status_check: "failed",
      upstream_http_status: 403,
    });
    assert.ok(logs.lines.some((l) => l.includes("mollie_onboarding_permission_missing")));
  } finally {
    logs.restore();
  }
});
