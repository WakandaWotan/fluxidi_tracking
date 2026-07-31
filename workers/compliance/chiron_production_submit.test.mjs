// RELEASE-P0-CHIRON-PROD-SUBMIT-2026-07-31
// Proves the real automatic production submit path uses production OAuth +
// production taxirit URLs with mocked external endpoints. Never ACC fallback.
//
// Run: node --test workers/compliance/chiron_production_submit.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import { __testInternals } from "./fluxidi_compliance_worker.js";

const {
  _chironAcquireOAuthAccessTokenForSubmit,
  _chironPostChironExportTestPayload,
  _chironAutoSubmitEligibleForEvent,
  _chironShouldRunReconcileFromStatusPoll,
  _chironCredentialsDocReadyForMockTest,
  _chironProductionLiveGate,
  _chironDeriveEffectiveChironEnvironment,
  encryptChironCredentialBlob,
  buildChironCredentialsKvKey,
  CHIRON_CREDENTIALS_PAYLOAD_SCHEMA_VERSION,
  CHIRON_CREDENTIALS_SCHEMA_VERSION,
  CHIRON_OAUTH_TOKEN_URL_BY_ENVIRONMENT,
  CHIRON_TAXIRIT_URL_BY_ENVIRONMENT,
} = __testInternals;

const ENCRYPTION_KEY = "test-only-encryption-key-must-be->=32-chars";
const PROD_OAUTH = "https://mow.api.vlaanderen.be/oauth/token";
const PROD_TAXIRIT = "https://mow.api.vlaanderen.be/chiron/taxirit";
const ACC_OAUTH = "https://mow-acc.api.vlaanderen.be/oauth/token";
const ACC_TAXIRIT = "https://mow-acc.api.vlaanderen.be/chiron/taxirit";

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
      const names = [...store.keys()].filter((k) => k.startsWith(prefix)).sort();
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
    ADMIN_TOKEN: "admin",
    COMPLIANCE_KV: kv,
    CHIRON_EXPORT_MODE: "test",
    CHIRON_EXPORT_BASE_URL: ACC_TAXIRIT,
    CHIRON_EXPORT_API_TOKEN: "legacy-static-token-must-never-hit-wire",
    CHIRON_CREDENTIALS_ENCRYPTION_KEY: ENCRYPTION_KEY,
    CHIRON_CREDENTIALS_ENCRYPTION_KID: "v1",
    ...overrides,
  };
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

function jsonResponse(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

async function seedProductionOAuthCredentials(
  kv,
  env,
  { tenantId, companyId, clientId, clientSecret },
) {
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
    environment: "production",
    auth_scheme: "oauth_client_credentials",
    credential_payload_encrypted: encrypted,
    credential_fingerprint_short: "fpprod",
    masked_identifier: "prod_***",
  };
  const key = buildChironCredentialsKvKey(tenantId, companyId, "production");
  await kv.put(key, JSON.stringify(doc));
  return { key, doc };
}

function productionStatus(overrides = {}) {
  return {
    enabled: true,
    environment: "production",
    production_enabled: true,
    production_credentials_stored: true,
    production_last_connection_status: "test_passed",
    test_credentials_stored: true,
    last_connection_status: "test_passed",
    testflow_auto_submit_enabled: false,
    test_departure_sent_count: 5,
    test_arrival_sent_count: 5,
    test_messages_sent_count: 10,
    test_rides_completed_count: 5,
    testflow_status: "complete",
    ...overrides,
  };
}

test("maps: production OAuth + taxirit URLs are official production hosts", () => {
  assert.equal(CHIRON_OAUTH_TOKEN_URL_BY_ENVIRONMENT.production, PROD_OAUTH);
  assert.equal(CHIRON_TAXIRIT_URL_BY_ENVIRONMENT.production, PROD_TAXIRIT);
  assert.equal(CHIRON_OAUTH_TOKEN_URL_BY_ENVIRONMENT.test, ACC_OAUTH);
  assert.equal(CHIRON_TAXIRIT_URL_BY_ENVIRONMENT.test, ACC_TAXIRIT);
});

test("credentials readiness: production doc is valid (not rejected as non-test)", () => {
  assert.equal(
    _chironCredentialsDocReadyForMockTest({
      schema_version: CHIRON_CREDENTIALS_SCHEMA_VERSION,
      environment: "production",
      auth_scheme: "oauth_client_credentials",
      credential_payload_encrypted: { ciphertext: "x", iv: "y", tag: "z" },
    }),
    true,
  );
});

test("oauth-acquire production: hits production OAuth URL with production client creds", async () => {
  const kv = makeKV();
  const env = baseEnv(kv);
  await seedProductionOAuthCredentials(kv, env, {
    tenantId: "T1",
    companyId: "C1",
    clientId: "prod-client",
    clientSecret: "prod-secret",
  });
  const stub = installFetchStub((url, init) => {
    assert.equal(url, PROD_OAUTH);
    assert.notEqual(url, ACC_OAUTH);
    assert.equal(String(init.body || ""), "grant_type=client_credentials");
    const auth = String(init.headers?.authorization || "");
    assert.match(auth, /^Basic /);
    // Client id+secret travel only in Basic auth — never as query/log fields.
    assert.doesNotMatch(String(init.body || ""), /prod-secret/);
    return jsonResponse(200, {
      access_token: "PROD-ACCESS-TOKEN",
      token_type: "Bearer",
      expires_in: 3600,
    });
  });
  try {
    const res = await _chironAcquireOAuthAccessTokenForSubmit(
      env,
      "T1",
      "C1",
      "production",
    );
    assert.equal(res.ok, true);
    assert.equal(res._access_token_in_memory_only, "PROD-ACCESS-TOKEN");
    assert.equal(stub.calls.length, 1);
    assert.equal(stub.calls[0].url, PROD_OAUTH);
  } finally {
    stub.restore();
  }
});

test("taxirit-post production: posts to mow.api production taxirit with bearer", async () => {
  const stub = installFetchStub((url, init) => {
    assert.equal(url, PROD_TAXIRIT);
    assert.notEqual(url, ACC_TAXIRIT);
    assert.equal(init.headers.authorization, "Bearer PROD-ACCESS-TOKEN");
    return jsonResponse(200, { fouten: [] });
  });
  try {
    const res = await _chironPostChironExportTestPayload(
      baseEnv(makeKV()),
      { ritnummer: "REG-PROD-1", status: "vertrek" },
      { accessToken: "PROD-ACCESS-TOKEN", baseUrl: PROD_TAXIRIT },
    );
    assert.equal(res.ok, true);
    assert.equal(res.fouten_count, 0);
    assert.equal(stub.calls.length, 1);
    assert.equal(stub.calls[0].url, PROD_TAXIRIT);
  } finally {
    stub.restore();
  }
});

test("taxirit-post production: fouten[] non-empty is NOT synced", async () => {
  const stub = installFetchStub(() =>
    jsonResponse(200, { fouten: [{ code: "X", tekst: "afgewezen" }] }),
  );
  try {
    const res = await _chironPostChironExportTestPayload(
      baseEnv(makeKV()),
      { ritnummer: "REG-PROD-2", status: "aankomst" },
      { accessToken: "PROD-ACCESS-TOKEN", baseUrl: PROD_TAXIRIT },
    );
    assert.equal(res.ok, false);
    assert.ok(Number(res.fouten_count) >= 1);
  } finally {
    stub.restore();
  }
});

test("eligibility: production effective env does not require ACC auto-submit opt-in", () => {
  const status = productionStatus();
  assert.equal(_chironDeriveEffectiveChironEnvironment(status), "production");
  assert.equal(_chironProductionLiveGate(status), null);
  const evt = {
    event_type: "ride_start",
    tenant_id: "T1",
    company_id: "C1",
    created_at_utc: "2026-07-31T21:00:00.000Z",
  };
  assert.equal(
    _chironAutoSubmitEligibleForEvent(status, baseEnv(makeKV()), evt),
    null,
  );
});

test("reconcile throttle: production effective env runs even when ACC auto-submit off", () => {
  const doc = productionStatus({ testflow_auto_reconcile_last_at: null });
  assert.equal(_chironShouldRunReconcileFromStatusPoll(doc), true);
});

test("production oauth failure must not hit ACC URL", async () => {
  const kv = makeKV();
  const env = baseEnv(kv);
  await seedProductionOAuthCredentials(kv, env, {
    tenantId: "T1",
    companyId: "C1",
    clientId: "prod-client",
    clientSecret: "prod-secret",
  });
  const stub = installFetchStub((url) => {
    assert.equal(url, PROD_OAUTH);
    return jsonResponse(401, { error: "invalid_client" });
  });
  try {
    const res = await _chironAcquireOAuthAccessTokenForSubmit(
      env,
      "T1",
      "C1",
      "production",
    );
    assert.equal(res.ok, false);
    assert.ok(stub.calls.every((c) => c.url !== ACC_OAUTH));
  } finally {
    stub.restore();
  }
});
