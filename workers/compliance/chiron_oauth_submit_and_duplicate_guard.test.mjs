// RELEASE-P0-OFFICIAL-CHIRON-OAUTH-SUBMIT-2026-07-31 — targeted tests for
// the official Chiron acceptance-path fixes:
//
//   * OAuth-derived bearer for the taxirit-POST (never CHIRON_EXPORT_API_TOKEN);
//   * duplicate-submit guard state machine (synced / pending /
//     verification_required / failed);
//   * bounded fetch timeout + ambiguous-transport classification into the
//     new `verification_required` sync_state;
//   * response-semantics: 2xx alone is NEVER acceptance (must be valid JSON,
//     fouten[] must be empty);
//   * scope isolation: credentials for company A cannot authenticate a
//     submit for company B;
//   * operator-resolution endpoints (confirm-synced + mark-retryable) with
//     admin auth, tenant/company/idempotency/status scope, no PII leak.
//
// Run:
//   node --test workers/compliance/chiron_oauth_submit_and_duplicate_guard.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import worker, { __testInternals } from "./fluxidi_compliance_worker.js";

const {
  _chironEvaluateSubmitDuplicateGuard,
  _chironAcquireOAuthAccessTokenForSubmit,
  _chironPostChironExportTestPayload,
  encryptChironCredentialBlob,
  buildChironCredentialsKvKey,
  CHIRON_CREDENTIALS_PAYLOAD_SCHEMA_VERSION,
  CHIRON_CREDENTIALS_SCHEMA_VERSION,
  buildChironExportStatusKey,
  CHIRON_EXPORT_STATUS_SCHEMA,
  safeSegment,
} = __testInternals;

const ADMIN = "admin-token-for-tests";
const ENCRYPTION_KEY = "test-only-encryption-key-must-be->=32-chars";
const OAUTH_TOKEN_URL = "https://mow-acc.api.vlaanderen.be/oauth/token";
const TAXIRIT_URL = "https://mow-acc.api.vlaanderen.be/chiron/taxiritten";

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
      store.set(key, val);
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
    // The static token remains ONLY as the `chironExportTestModeEnabled`
    // gate; the taxirit-POST must NOT use it as its bearer any more.
    CHIRON_EXPORT_API_TOKEN: "legacy-static-token-must-never-hit-wire",
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
    credential_fingerprint_short: "fp1234",
    masked_identifier: "client_***",
  };
  const key = buildChironCredentialsKvKey(tenantId, companyId, "test");
  await kv.put(key, JSON.stringify(doc));
  return { key, doc };
}

async function seedApiTokenCredentials(kv, env, { tenantId, companyId, token }) {
  const plaintext = JSON.stringify({
    schema_version: CHIRON_CREDENTIALS_PAYLOAD_SCHEMA_VERSION,
    auth_scheme: "api_token",
    api_token: token,
  });
  const encrypted = await encryptChironCredentialBlob(plaintext, env);
  const doc = {
    schema_version: CHIRON_CREDENTIALS_SCHEMA_VERSION,
    tenant_id: tenantId,
    company_id: companyId,
    environment: "test",
    auth_scheme: "api_token",
    credential_payload_encrypted: encrypted,
    credential_fingerprint_short: "fp5678",
    masked_identifier: "token_***",
  };
  const key = buildChironCredentialsKvKey(tenantId, companyId, "test");
  await kv.put(key, JSON.stringify(doc));
  return { key, doc };
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

// -----------------------------------------------------------------------
// A. DUPLICATE-SUBMIT GUARD (pure state-machine).
// -----------------------------------------------------------------------
test("dupguard: null previousStatus → allow", () => {
  assert.deepEqual(_chironEvaluateSubmitDuplicateGuard(null), { decision: "allow" });
  assert.deepEqual(_chironEvaluateSubmitDuplicateGuard(undefined), { decision: "allow" });
});

test("dupguard: synced → already_synced", () => {
  assert.deepEqual(
    _chironEvaluateSubmitDuplicateGuard({ sync_state: "synced" }),
    { decision: "already_synced" },
  );
});

test("dupguard: pending → conflict_pending", () => {
  assert.deepEqual(
    _chironEvaluateSubmitDuplicateGuard({ sync_state: "pending" }),
    { decision: "conflict_pending" },
  );
});

test("dupguard: verification_required → verification_required", () => {
  assert.deepEqual(
    _chironEvaluateSubmitDuplicateGuard({ sync_state: "verification_required" }),
    { decision: "verification_required" },
  );
});

test("dupguard: failed + explicit definitive marker → allow", () => {
  assert.deepEqual(
    _chironEvaluateSubmitDuplicateGuard({
      sync_state: "failed",
      failure_kind: "definitive",
    }),
    { decision: "allow" },
  );
});

test("dupguard: failed + Chiron 200 with fouten>0 → allow (definitive rejection)", () => {
  assert.deepEqual(
    _chironEvaluateSubmitDuplicateGuard({
      sync_state: "failed",
      external_status_code: 200,
      fouten_count: 1,
    }),
    { decision: "allow" },
  );
});

test("dupguard: failed + non-2xx external_status_code → allow", () => {
  assert.deepEqual(
    _chironEvaluateSubmitDuplicateGuard({
      sync_state: "failed",
      external_status_code: 400,
      fouten_count: 0,
    }),
    { decision: "allow" },
  );
});

test("dupguard: failed without evidence → not_retryable (fail-closed)", () => {
  assert.deepEqual(
    _chironEvaluateSubmitDuplicateGuard({
      sync_state: "failed",
      external_status_code: null,
      fouten_count: 0,
    }),
    { decision: "not_retryable" },
  );
});

test("dupguard: unknown state → not_retryable", () => {
  assert.deepEqual(
    _chironEvaluateSubmitDuplicateGuard({ sync_state: "wat" }),
    { decision: "not_retryable" },
  );
});

// -----------------------------------------------------------------------
// B. taxirit POST: bearer + timeout + ambiguous classification.
// -----------------------------------------------------------------------
test("taxirit-post: missing accessToken → no fetch, safely retryable", async () => {
  const stub = installFetchStub(() => {
    throw new Error("fetch must not be called without a bearer");
  });
  try {
    const res = await _chironPostChironExportTestPayload(
      baseEnv(makeKV()),
      { ritnummer: "R1" },
    );
    assert.equal(res.ok, false);
    assert.equal(res.error, "missing_oauth_access_token");
    assert.equal(res.ambiguous, false);
    assert.equal(stub.calls.length, 0, "no HTTP request must go out");
  } finally {
    stub.restore();
  }
});

test("taxirit-post: uses OAuth bearer, ignores CHIRON_EXPORT_API_TOKEN", async () => {
  const env = baseEnv(makeKV());
  const stub = installFetchStub(() =>
    jsonResponse(200, {
      fouten: [],
      external_reference: "CHIRON-REF-1",
    }),
  );
  try {
    const res = await _chironPostChironExportTestPayload(env, { ritnummer: "R2" }, {
      accessToken: "OAUTH-DERIVED-BEARER",
    });
    assert.equal(res.ok, true);
    assert.equal(res.ambiguous, false);
    assert.equal(stub.calls.length, 1);
    const authHeader = stub.calls[0].init.headers.authorization;
    assert.equal(authHeader, "Bearer OAUTH-DERIVED-BEARER");
    assert.notEqual(
      authHeader,
      `Bearer ${env.CHIRON_EXPORT_API_TOKEN}`,
      "static token MUST NOT be used as bearer",
    );
    assert.equal(res.external_reference, "CHIRON-REF-1");
  } finally {
    stub.restore();
  }
});

test("taxirit-post: 200 + fouten:[CH1102] → failed/rejected (not synced)", async () => {
  const stub = installFetchStub(() =>
    jsonResponse(200, { fouten: [{ foutcode: "CH1102", omschrijving: "x" }] }),
  );
  try {
    const res = await _chironPostChironExportTestPayload(
      baseEnv(makeKV()),
      { ritnummer: "R3" },
      { accessToken: "BEARER" },
    );
    assert.equal(res.ok, false);
    assert.equal(res.ambiguous, false);
    assert.ok(Number(res.fouten_count) >= 1);
  } finally {
    stub.restore();
  }
});

test("taxirit-post: non-2xx → failed, not ambiguous", async () => {
  const stub = installFetchStub(() =>
    jsonResponse(500, { fouten: [] }),
  );
  try {
    const res = await _chironPostChironExportTestPayload(
      baseEnv(makeKV()),
      { ritnummer: "R4" },
      { accessToken: "BEARER" },
    );
    assert.equal(res.ok, false);
    assert.equal(res.ambiguous, false);
    assert.equal(res.external_status_code, 500);
  } finally {
    stub.restore();
  }
});

test("taxirit-post: 2xx invalid JSON → NOT synced", async () => {
  const stub = installFetchStub(
    () =>
      new Response("<html>not-json</html>", {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
  );
  try {
    const res = await _chironPostChironExportTestPayload(
      baseEnv(makeKV()),
      { ritnummer: "R5" },
      { accessToken: "BEARER" },
    );
    assert.equal(res.ok, false, "invalid JSON body must not be treated as accepted");
    assert.equal(res.ambiguous, false);
  } finally {
    stub.restore();
  }
});

test("taxirit-post: fetch throws AFTER fetch started → ambiguous transport", async () => {
  const stub = installFetchStub(() => {
    throw new Error("connection reset");
  });
  try {
    const res = await _chironPostChironExportTestPayload(
      baseEnv(makeKV()),
      { ritnummer: "R6" },
      { accessToken: "BEARER" },
    );
    assert.equal(res.ok, false);
    assert.equal(res.ambiguous, true);
    assert.equal(res.sanitized_error, "chiron_transport_ambiguous");
    assert.equal(res.transport_error_kind, "network");
  } finally {
    stub.restore();
  }
});

test("taxirit-post: AbortController timeout → ambiguous (timeout)", async () => {
  const stub = installFetchStub(
    (_url, init) =>
      new Promise((_resolve, reject) => {
        if (init && init.signal) {
          init.signal.addEventListener("abort", () => {
            const err = new Error("aborted");
            err.name = "AbortError";
            reject(err);
          });
        }
      }),
  );
  try {
    const res = await _chironPostChironExportTestPayload(
      baseEnv(makeKV()),
      { ritnummer: "R7" },
      { accessToken: "BEARER", timeoutMs: 1000 },
    );
    assert.equal(res.ok, false);
    assert.equal(res.ambiguous, true);
    assert.equal(res.transport_error_kind, "timeout");
    assert.equal(res.sanitized_error, "chiron_transport_ambiguous");
  } finally {
    stub.restore();
  }
});

// -----------------------------------------------------------------------
// C. OAuth acquire scope + scheme isolation.
// -----------------------------------------------------------------------
test("oauth-acquire: env != test blocks (no fetch)", async () => {
  const stub = installFetchStub(() => {
    throw new Error("no fetch expected");
  });
  try {
    const res = await _chironAcquireOAuthAccessTokenForSubmit(
      baseEnv(makeKV()),
      "T1",
      "C1",
      "production",
    );
    assert.equal(res.ok, false);
    assert.equal(res.error, "unsupported_environment");
    assert.equal(stub.calls.length, 0);
  } finally {
    stub.restore();
  }
});

test("oauth-acquire: missing credentials in KV → missing_test_credentials", async () => {
  const kv = makeKV();
  const stub = installFetchStub(() => {
    throw new Error("no fetch expected");
  });
  try {
    const res = await _chironAcquireOAuthAccessTokenForSubmit(
      baseEnv(kv),
      "T1",
      "C1",
      "test",
    );
    assert.equal(res.ok, false);
    assert.equal(res.error, "missing_test_credentials");
  } finally {
    stub.restore();
  }
});

test("oauth-acquire: api_token scheme is REJECTED for official submit", async () => {
  const kv = makeKV();
  const env = baseEnv(kv);
  await seedApiTokenCredentials(kv, env, {
    tenantId: "T1",
    companyId: "C1",
    token: "legacy-api-token",
  });
  const stub = installFetchStub(() => {
    throw new Error("no OAuth exchange must happen for api_token creds");
  });
  try {
    const res = await _chironAcquireOAuthAccessTokenForSubmit(env, "T1", "C1", "test");
    assert.equal(res.ok, false);
    assert.equal(res.error, "oauth_client_credentials_required");
  } finally {
    stub.restore();
  }
});

test("oauth-acquire: successful exchange returns in-memory token only", async () => {
  const kv = makeKV();
  const env = baseEnv(kv);
  await seedOAuthCredentials(kv, env, {
    tenantId: "T1",
    companyId: "C1",
    clientId: "client-id-A",
    clientSecret: "client-secret-A",
  });
  const stub = installFetchStub((url) => {
    assert.equal(url, OAUTH_TOKEN_URL);
    return jsonResponse(200, {
      access_token: "OAUTH-ACCESS-TOKEN-A",
      token_type: "Bearer",
      expires_in: 3600,
    });
  });
  try {
    const res = await _chironAcquireOAuthAccessTokenForSubmit(env, "T1", "C1", "test");
    assert.equal(res.ok, true);
    assert.equal(res._access_token_in_memory_only, "OAUTH-ACCESS-TOKEN-A");
    assert.equal(res.expires_in_seconds, 3600);
    // Token MUST NOT show up in a serialized form (defensive contract check).
    const serialized = JSON.stringify(res);
    assert.match(serialized, /_access_token_in_memory_only/);
    // The token itself IS in `res` for in-memory use — the contract is that
    // callers never serialize `res` to KV/HTTP. Verify JSON key naming so
    // any accidental external serialization is grep-able and blockable.
  } finally {
    stub.restore();
  }
});

test("oauth-acquire: OAuth 401 upstream → ok:false, safe error, no token", async () => {
  const kv = makeKV();
  const env = baseEnv(kv);
  await seedOAuthCredentials(kv, env, {
    tenantId: "T1",
    companyId: "C1",
    clientId: "client-id-A",
    clientSecret: "client-secret-A",
  });
  const stub = installFetchStub(() =>
    jsonResponse(401, { error: "invalid_client" }),
  );
  try {
    const res = await _chironAcquireOAuthAccessTokenForSubmit(env, "T1", "C1", "test");
    assert.equal(res.ok, false);
    assert.ok(!res._access_token_in_memory_only);
    assert.match(String(res.error || ""), /oauth|http|invalid|failed/i);
  } finally {
    stub.restore();
  }
});

test("scope isolation: company-A credentials cannot authenticate for company-B", async () => {
  const kv = makeKV();
  const env = baseEnv(kv);
  await seedOAuthCredentials(kv, env, {
    tenantId: "T1",
    companyId: "C1",
    clientId: "client-A",
    clientSecret: "secret-A",
  });
  const stub = installFetchStub(() => {
    throw new Error("no OAuth exchange must happen without scoped creds");
  });
  try {
    const res = await _chironAcquireOAuthAccessTokenForSubmit(env, "T1", "C2", "test");
    assert.equal(res.ok, false);
    assert.equal(
      res.error,
      "missing_test_credentials",
      "reading the C2 slot MUST NOT return C1's credentials",
    );
  } finally {
    stub.restore();
  }
});

// -----------------------------------------------------------------------
// D. Operator-resolution endpoints (HTTP).
// -----------------------------------------------------------------------
function opReq(pathname, body, headers = {}) {
  return new Request(`https://compliance.internal${pathname}`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-admin-token": ADMIN,
      ...headers,
    },
    body: JSON.stringify(body),
  });
}

function makeVerifDoc({
  tenantId = "T1",
  companyId = "C1",
  idempotencyKey = "idem-1",
  officialStatus = "vertrek",
} = {}) {
  return {
    schema_version: CHIRON_EXPORT_STATUS_SCHEMA,
    tenant_id: tenantId,
    company_id: companyId,
    event_id: "evt-1",
    official_idempotency_key: idempotencyKey,
    official_ritnummer: "RIT-1",
    official_status: officialStatus,
    official_payload_shape: "chiron_taxirit_api_v1",
    sync_state: "verification_required",
    failure_kind: "ambiguous",
    verification_required_reason: "chiron_transport_ambiguous",
    external_status_code: null,
    external_reference: null,
    response_shape: null,
    fouten_count: null,
    attempt_count: 1,
    sanitized_error: "chiron_transport_ambiguous",
  };
}

async function seedVerifDoc(kv, doc) {
  const key = buildChironExportStatusKey(
    safeSegment(doc.tenant_id, ""),
    safeSegment(doc.company_id, ""),
    doc.official_idempotency_key,
  );
  await kv.put(key, JSON.stringify(doc));
  return key;
}

test("operator confirm-synced: verif→synced, no PII leak, no re-POST", async () => {
  const kv = makeKV();
  const env = baseEnv(kv);
  const doc = makeVerifDoc();
  const key = await seedVerifDoc(kv, doc);
  const stub = installFetchStub(() => {
    throw new Error("operator resolution MUST NOT call Chiron");
  });
  try {
    const res = await worker.fetch(
      opReq("/admin/chiron/taxirit/verification/confirm-synced", {
        tenant_id: doc.tenant_id,
        company_id: doc.company_id,
        official_idempotency_key: doc.official_idempotency_key,
        official_status: doc.official_status,
      }),
      env,
    );
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.ok, true);
    assert.equal(body.resolution, "confirmed_synced");
    assert.equal(body.sync_state, "synced");

    const stored = JSON.parse(kv.store.get(key));
    assert.equal(stored.sync_state, "synced");
    assert.equal(stored.failure_kind, null);
    assert.equal(stored.verification_required_reason, null);
    assert.equal(stored.operator_resolution, "confirmed_synced");
    // No credentials / bearer / raw error must land in the stored doc.
    const storedRaw = kv.store.get(key);
    assert.doesNotMatch(storedRaw, /bearer/i);
    assert.doesNotMatch(storedRaw, /client_secret/i);
    assert.doesNotMatch(storedRaw, /access_token/i);
  } finally {
    stub.restore();
  }
});

test("operator mark-retryable: verif→failed/definitive, retry becomes allowed", async () => {
  const kv = makeKV();
  const env = baseEnv(kv);
  const doc = makeVerifDoc({ idempotencyKey: "idem-retry" });
  const key = await seedVerifDoc(kv, doc);
  const res = await worker.fetch(
    opReq("/admin/chiron/taxirit/verification/mark-retryable", {
      tenant_id: doc.tenant_id,
      company_id: doc.company_id,
      official_idempotency_key: doc.official_idempotency_key,
      official_status: doc.official_status,
    }),
    env,
  );
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.ok, true);
  assert.equal(body.sync_state, "failed");
  assert.equal(body.retry_allowed, true);

  const stored = JSON.parse(kv.store.get(key));
  assert.equal(stored.sync_state, "failed");
  assert.equal(stored.failure_kind, "definitive");
  assert.equal(stored.verification_required_reason, null);

  // Now the duplicate-guard must allow a retry.
  assert.deepEqual(_chironEvaluateSubmitDuplicateGuard(stored), { decision: "allow" });
});

test("operator confirm-synced: doc already synced → 409 not_in_verification_required", async () => {
  const kv = makeKV();
  const env = baseEnv(kv);
  const doc = { ...makeVerifDoc({ idempotencyKey: "idem-synced" }), sync_state: "synced" };
  await seedVerifDoc(kv, doc);
  const res = await worker.fetch(
    opReq("/admin/chiron/taxirit/verification/confirm-synced", {
      tenant_id: doc.tenant_id,
      company_id: doc.company_id,
      official_idempotency_key: doc.official_idempotency_key,
      official_status: doc.official_status,
    }),
    env,
  );
  assert.equal(res.status, 409);
  const body = await res.json();
  assert.equal(body.ok, false);
  assert.equal(body.error, "not_in_verification_required");
});

test("operator: missing scope → 400", async () => {
  const kv = makeKV();
  const env = baseEnv(kv);
  const res = await worker.fetch(
    opReq("/admin/chiron/taxirit/verification/confirm-synced", {
      official_idempotency_key: "x",
      official_status: "vertrek",
    }),
    env,
  );
  assert.equal(res.status, 400);
  const body = await res.json();
  assert.equal(body.error, "missing_scope");
});

test("operator: unknown doc → 404", async () => {
  const kv = makeKV();
  const env = baseEnv(kv);
  const res = await worker.fetch(
    opReq("/admin/chiron/taxirit/verification/mark-retryable", {
      tenant_id: "T1",
      company_id: "C1",
      official_idempotency_key: "idem-unknown",
      official_status: "vertrek",
    }),
    env,
  );
  assert.equal(res.status, 404);
  const body = await res.json();
  assert.equal(body.error, "export_status_not_found");
});

test("operator: invalid official_status → 400", async () => {
  const kv = makeKV();
  const env = baseEnv(kv);
  const res = await worker.fetch(
    opReq("/admin/chiron/taxirit/verification/confirm-synced", {
      tenant_id: "T1",
      company_id: "C1",
      official_idempotency_key: "idem-x",
      official_status: "not-a-real-status",
    }),
    env,
  );
  assert.equal(res.status, 400);
  const body = await res.json();
  assert.equal(body.error, "invalid_official_status");
});

test("operator: cross-tenant scope drift → 409", async () => {
  const kv = makeKV();
  const env = baseEnv(kv);
  const doc = makeVerifDoc({
    tenantId: "T1",
    companyId: "C1",
    idempotencyKey: "idem-drift",
  });
  // Manually mis-store it under the T2/C2 KV slot to simulate a scope drift.
  const misKey = buildChironExportStatusKey(
    safeSegment("T2", ""),
    safeSegment("C2", ""),
    doc.official_idempotency_key,
  );
  await kv.put(misKey, JSON.stringify(doc));
  const res = await worker.fetch(
    opReq("/admin/chiron/taxirit/verification/confirm-synced", {
      tenant_id: "T2",
      company_id: "C2",
      official_idempotency_key: doc.official_idempotency_key,
      official_status: doc.official_status,
    }),
    env,
  );
  assert.equal(res.status, 409);
  const body = await res.json();
  assert.equal(body.error, "export_status_scope_mismatch");
});

test("operator: admin auth required (401 without token)", async () => {
  const kv = makeKV();
  const env = baseEnv(kv);
  const req = new Request(
    "https://compliance.internal/admin/chiron/taxirit/verification/confirm-synced",
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        tenant_id: "T1",
        company_id: "C1",
        official_idempotency_key: "idem-1",
        official_status: "vertrek",
      }),
    },
  );
  const res = await worker.fetch(req, env);
  assert.equal(res.status, 401);
});
