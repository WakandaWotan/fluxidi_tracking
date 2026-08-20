/* BILLIT-OAUTH-RECONNECT-PRESERVE-P0
 *
 * Hermetic coverage for OAuth start/callback data preservation.
 * No live Billit, Cloudflare, or production credentials.
 *
 *   node --test workers/booking/billit_oauth_reconnect_preserve_p0.test.mjs
 */

import { test, before, after, beforeEach } from "node:test";
import assert from "node:assert/strict";

import worker from "./fluxidi_booking_worker.js";
import {
  BILLIT_OAUTH_STATE_TTL_SECONDS,
  buildBillitAuthorizationUrl,
  buildBillitOAuthConnectionKey,
  buildBillitOAuthPendingKey,
  buildBillitOAuthStateKey,
  completeBillitOAuthCallback,
  exchangeBillitOAuthCodeForToken,
  resolveBillitOAuthConfig,
  startBillitOAuthForScope,
} from "./modules/billit_provider.js";

const ADMIN = "test-admin-token";
const TENANT_A = "tenant_a";
const COMPANY_A = "company_a";
const TENANT_B = "tenant_b";
const COMPANY_B = "company_b";
const SCOPE_A = { tenant_id: TENANT_A, company_id: COMPANY_A };
const SCOPE_B = { tenant_id: TENANT_B, company_id: COMPANY_B };
const SCOPE_A_OTHER_COMPANY = { tenant_id: TENANT_A, company_id: COMPANY_B };
const REDIRECT_URI =
  "https://fluxidi-booking-api.fluxidi.workers.dev/admin/integrations/billit/oauth/callback";
const CLIENT_ID = "test-client-id";
const CLIENT_SECRET = "test-client-secret";
const ACCESS_TOKEN = "access-token-plain";
const REFRESH_TOKEN = "refresh-token-plain";
const OLD_PARTY_ID = "party-old-111";
const NEW_PARTY_ID = "party-new-222";
const FOREIGN_PARTY_ID = "party-foreign-999";

let originalFetch;
let fetchHandler = null;
let logs = [];
let originalLog;

before(() => {
  originalFetch = global.fetch;
  originalLog = console.log;
  global.fetch = async (input, init) => {
    if (typeof fetchHandler === "function") {
      return fetchHandler(input, init);
    }
    throw new Error("hermetic test: unexpected fetch");
  };
  console.log = (...args) => {
    logs.push(args.map((part) => String(part)).join(" "));
  };
});

after(() => {
  global.fetch = originalFetch;
  console.log = originalLog;
});

beforeEach(() => {
  fetchHandler = null;
  logs = [];
});

function makeKV(seed = {}) {
  const store = new Map();
  const writes = [];
  const deletes = [];
  for (const [key, value] of Object.entries(seed)) {
    store.set(
      key,
      typeof value === "string" ? value : JSON.stringify(value),
    );
  }
  return {
    store,
    writes,
    deletes,
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
    async put(key, val, opts) {
      writes.push({
        key,
        expirationTtl: opts?.expirationTtl ?? null,
      });
      store.set(key, val);
    },
    async delete(key) {
      deletes.push(key);
      store.delete(key);
    },
  };
}

function activeConnection({
  scope = SCOPE_A,
  partyId = OLD_PARTY_ID,
  connectedAt = "2026-01-15T10:00:00.000Z",
} = {}) {
  return {
    provider: "billit",
    tenant_id: scope.tenant_id,
    company_id: scope.company_id,
    environment: "sandbox",
    connected: true,
    status: "connected",
    connected_at: connectedAt,
    updated_at: connectedAt,
    token_type: "Bearer",
    access_token_encrypted: {
      alg: "AES-GCM",
      kid: "v1",
      iv: "old-iv",
      ciphertext: "old-access-ciphertext",
    },
    refresh_token_encrypted: {
      alg: "AES-GCM",
      kid: "v1",
      iv: "old-refresh-iv",
      ciphertext: "old-refresh-ciphertext",
    },
    expires_at: "2027-01-15T10:00:00.000Z",
    scope: null,
    party_id: partyId,
    last_error_code: null,
    last_error_message: null,
  };
}

function makeEnv(seed = {}) {
  const bookingKv = makeKV(seed);
  return {
    env: {
      BOOKING_KV: bookingKv,
      ADMIN_TOKEN: ADMIN,
      BILLIT_ENVIRONMENT: "sandbox",
      BILLIT_CLIENT_ID: CLIENT_ID,
      BILLIT_CLIENT_SECRET: CLIENT_SECRET,
      BILLIT_REDIRECT_URI: REDIRECT_URI,
      BILLIT_TOKEN_ENCRYPTION_KEY: "test-billit-token-encryption-key",
    },
    bookingKv,
  };
}

function snapshotConnection(kv, scope) {
  const raw = kv.store.get(buildBillitOAuthConnectionKey(scope));
  return raw == null ? null : String(raw);
}

function parseConnection(kv, scope) {
  const raw = snapshotConnection(kv, scope);
  return raw ? JSON.parse(raw) : null;
}

function assertConnectionUntouched(beforeRaw, kv, scope) {
  assert.equal(snapshotConnection(kv, scope), beforeRaw);
  const writes = kv.writes.filter(
    (entry) => entry.key === buildBillitOAuthConnectionKey(scope),
  );
  assert.equal(writes.length, 0);
}

function findStateWrite(kv) {
  return kv.writes.find((entry) =>
    String(entry.key).startsWith("integration:billit:oauth_state:"),
  );
}

function findPendingWrite(kv, scope) {
  const pendingKey = buildBillitOAuthPendingKey(scope);
  return kv.writes.find((entry) => entry.key === pendingKey);
}

function parseAuthorizationUrl(url) {
  return new URL(url);
}

function installHappyBillitFetch({
  partyId = NEW_PARTY_ID,
  tokenOk = true,
  probeOk = true,
  companies = null,
} = {}) {
  const captured = { tokenRedirectUri: null, authorizeUsed: false };
  fetchHandler = async (input, init) => {
    const href = typeof input === "string" ? input : input?.url || String(input);
    if (href.includes("/OAuth2/token")) {
      const body = JSON.parse(String(init?.body || "{}"));
      captured.tokenRedirectUri = body.redirect_uri || null;
      if (!tokenOk) {
        return new Response(JSON.stringify({ error: "invalid_grant" }), {
          status: 400,
          headers: { "content-type": "application/json" },
        });
      }
      return new Response(
        JSON.stringify({
          token_type: "Bearer",
          access_token: ACCESS_TOKEN,
          refresh_token: REFRESH_TOKEN,
          expires_in: 3600,
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      );
    }
    if (href.includes("/v1/account/accountInformation")) {
      if (!probeOk) {
        return new Response(JSON.stringify({ error: "probe_failed" }), {
          status: 500,
          headers: { "content-type": "application/json" },
        });
      }
      return new Response(
        JSON.stringify({
          Companies: companies || [{ PartyID: partyId }],
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      );
    }
    throw new Error(`hermetic test: unexpected fetch ${href}`);
  };
  return captured;
}

function assertNoSecretLeak(haystacks, extraSecrets = []) {
  const secrets = [
    CLIENT_SECRET,
    ACCESS_TOKEN,
    REFRESH_TOKEN,
    "old-access-ciphertext",
    "old-refresh-ciphertext",
    ...extraSecrets,
  ];
  for (const haystack of haystacks) {
    const text = String(haystack || "");
    for (const secret of secrets) {
      assert.equal(
        text.includes(secret),
        false,
        "logs/errors must not leak secrets",
      );
    }
  }
}

test("1+2: OAuth start keeps an active connection field-equivalent, including tokens and Party ID", async () => {
  const existing = activeConnection();
  const { env, bookingKv } = makeEnv({
    [buildBillitOAuthConnectionKey(SCOPE_A)]: existing,
  });
  const before = snapshotConnection(bookingKv, SCOPE_A);
  const result = await startBillitOAuthForScope(env, SCOPE_A);
  assert.equal(result.status, 200);
  assert.equal(result.body.ok, true);
  assertConnectionUntouched(before, bookingKv, SCOPE_A);
  const kept = parseConnection(bookingKv, SCOPE_A);
  assert.equal(kept.connected, true);
  assert.equal(kept.status, "connected");
  assert.equal(kept.party_id, OLD_PARTY_ID);
  assert.equal(kept.connected_at, existing.connected_at);
  assert.deepEqual(kept.access_token_encrypted, existing.access_token_encrypted);
  assert.deepEqual(
    kept.refresh_token_encrypted,
    existing.refresh_token_encrypted,
  );
});

test("3: start stores tenant-scoped pending/state with TTL 600 and no secrets", async () => {
  const existing = activeConnection();
  const { env, bookingKv } = makeEnv({
    [buildBillitOAuthConnectionKey(SCOPE_A)]: existing,
  });
  const result = await startBillitOAuthForScope(env, SCOPE_A);
  assert.equal(result.body.state_expires_in_seconds, 600);
  assert.equal(BILLIT_OAUTH_STATE_TTL_SECONDS, 600);
  const stateWrite = findStateWrite(bookingKv);
  const pendingWrite = findPendingWrite(bookingKv, SCOPE_A);
  assert.ok(stateWrite);
  assert.ok(pendingWrite);
  assert.equal(stateWrite.expirationTtl, 600);
  assert.equal(pendingWrite.expirationTtl, 600);
  const stateRaw = bookingKv.store.get(stateWrite.key);
  const pendingRaw = bookingKv.store.get(pendingWrite.key);
  const stateRecord = JSON.parse(stateRaw);
  const pendingRecord = JSON.parse(pendingRaw);
  assert.equal(stateRecord.tenant_id, TENANT_A);
  assert.equal(stateRecord.company_id, COMPANY_A);
  assert.equal(pendingRecord.tenant_id, TENANT_A);
  assert.equal(pendingRecord.company_id, COMPANY_A);
  assert.equal(pendingRecord.status, "authorization_pending");
  for (const raw of [stateRaw, pendingRaw]) {
    assert.equal(raw.includes(ACCESS_TOKEN), false);
    assert.equal(raw.includes(REFRESH_TOKEN), false);
    assert.equal(raw.includes(CLIENT_SECRET), false);
    assert.equal(raw.includes("old-access-ciphertext"), false);
  }
  assert.equal(Object.hasOwn(stateRecord, "access_token"), false);
  assert.equal(Object.hasOwn(stateRecord, "refresh_token"), false);
  assert.equal(Object.hasOwn(pendingRecord, "state"), false);
});

test("4: successful callback replaces the connection only after full validation", async () => {
  const existing = activeConnection();
  const { env, bookingKv } = makeEnv({
    [buildBillitOAuthConnectionKey(SCOPE_A)]: existing,
  });
  const started = await startBillitOAuthForScope(env, SCOPE_A);
  const authUrl = parseAuthorizationUrl(started.body.authorization_url);
  const captured = installHappyBillitFetch({ partyId: NEW_PARTY_ID });
  const result = await completeBillitOAuthCallback(env, {
    code: "auth-code-1",
    state: authUrl.searchParams.get("state"),
  });
  assert.equal(result.outcome, "connected");
  assert.equal(result.status, 200);
  const next = parseConnection(bookingKv, SCOPE_A);
  assert.equal(next.connected, true);
  assert.equal(next.party_id, NEW_PARTY_ID);
  assert.notEqual(next.connected_at, existing.connected_at);
  assert.notEqual(
    next.access_token_encrypted.ciphertext,
    existing.access_token_encrypted.ciphertext,
  );
  assert.equal(captured.tokenRedirectUri, REDIRECT_URI);
  assert.equal(
    bookingKv.store.has(buildBillitOAuthPendingKey(SCOPE_A)),
    false,
  );
});

test("5: denied consent keeps the previous connection", async () => {
  const existing = activeConnection();
  const { env, bookingKv } = makeEnv({
    [buildBillitOAuthConnectionKey(SCOPE_A)]: existing,
  });
  const before = snapshotConnection(bookingKv, SCOPE_A);
  const started = await startBillitOAuthForScope(env, SCOPE_A);
  const authUrl = parseAuthorizationUrl(started.body.authorization_url);
  const result = await completeBillitOAuthCallback(env, {
    oauthError: "access_denied",
    state: authUrl.searchParams.get("state"),
  });
  assert.equal(result.outcome, "provider_error");
  assert.equal(snapshotConnection(bookingKv, SCOPE_A), before);
  const kept = parseConnection(bookingKv, SCOPE_A);
  assert.equal(kept.connected, true);
  assert.equal(kept.party_id, OLD_PARTY_ID);
  assert.equal(kept.status, "connected");
  assert.equal(kept.connected_at, existing.connected_at);
});

test("6: invalid or expired state keeps the previous connection", async () => {
  const existing = activeConnection();
  const { env, bookingKv } = makeEnv({
    [buildBillitOAuthConnectionKey(SCOPE_A)]: existing,
  });
  const before = snapshotConnection(bookingKv, SCOPE_A);
  const invalid = await completeBillitOAuthCallback(env, {
    code: "auth-code-1",
    state: "not-a-real-state",
  });
  assert.equal(invalid.outcome, "expired_or_invalid_state");
  assert.equal(snapshotConnection(bookingKv, SCOPE_A), before);

  const started = await startBillitOAuthForScope(env, SCOPE_A);
  const authUrl = parseAuthorizationUrl(started.body.authorization_url);
  const stateKey = buildBillitOAuthStateKey(authUrl.searchParams.get("state"));
  await bookingKv.delete(stateKey);
  const expired = await completeBillitOAuthCallback(env, {
    code: "auth-code-1",
    state: authUrl.searchParams.get("state"),
  });
  assert.equal(expired.outcome, "expired_or_invalid_state");
  assert.equal(snapshotConnection(bookingKv, SCOPE_A), before);
});

test("7: failed token exchange keeps the previous connection", async () => {
  const existing = activeConnection();
  const { env, bookingKv } = makeEnv({
    [buildBillitOAuthConnectionKey(SCOPE_A)]: existing,
  });
  const before = snapshotConnection(bookingKv, SCOPE_A);
  const started = await startBillitOAuthForScope(env, SCOPE_A);
  const authUrl = parseAuthorizationUrl(started.body.authorization_url);
  installHappyBillitFetch({ tokenOk: false });
  const result = await completeBillitOAuthCallback(env, {
    code: "bad-code",
    state: authUrl.searchParams.get("state"),
  });
  assert.equal(result.outcome, "token_exchange_failed");
  assert.equal(snapshotConnection(bookingKv, SCOPE_A), before);
  const kept = parseConnection(bookingKv, SCOPE_A);
  assert.equal(kept.party_id, OLD_PARTY_ID);
  assert.deepEqual(
    kept.access_token_encrypted,
    existing.access_token_encrypted,
  );
});

test("8: failed Party ID / account validation keeps the previous connection", async () => {
  const existing = activeConnection();
  const { env, bookingKv } = makeEnv({
    [buildBillitOAuthConnectionKey(SCOPE_A)]: existing,
  });
  const before = snapshotConnection(bookingKv, SCOPE_A);
  const started = await startBillitOAuthForScope(env, SCOPE_A);
  const authUrl = parseAuthorizationUrl(started.body.authorization_url);
  installHappyBillitFetch({ probeOk: false });
  const probeFail = await completeBillitOAuthCallback(env, {
    code: "auth-code-1",
    state: authUrl.searchParams.get("state"),
  });
  assert.equal(probeFail.outcome, "account_validation_failed");
  assert.equal(snapshotConnection(bookingKv, SCOPE_A), before);

  const startedAgain = await startBillitOAuthForScope(env, SCOPE_A);
  const authUrl2 = parseAuthorizationUrl(startedAgain.body.authorization_url);
  installHappyBillitFetch({
    companies: [{ PartyID: "111" }, { PartyID: "222" }],
  });
  const partyFail = await completeBillitOAuthCallback(env, {
    code: "auth-code-2",
    state: authUrl2.searchParams.get("state"),
  });
  assert.equal(partyFail.outcome, "party_selection_required");
  assert.equal(snapshotConnection(bookingKv, SCOPE_A), before);
});

test("9: first connection without an existing record still works", async () => {
  const { env, bookingKv } = makeEnv();
  const started = await startBillitOAuthForScope(env, SCOPE_A);
  assert.equal(started.status, 200);
  assert.equal(parseConnection(bookingKv, SCOPE_A), null);
  const authUrl = parseAuthorizationUrl(started.body.authorization_url);
  installHappyBillitFetch({ partyId: NEW_PARTY_ID });
  const result = await completeBillitOAuthCallback(env, {
    code: "auth-code-first",
    state: authUrl.searchParams.get("state"),
  });
  assert.equal(result.outcome, "connected");
  const created = parseConnection(bookingKv, SCOPE_A);
  assert.equal(created.connected, true);
  assert.equal(created.status, "connected");
  assert.equal(created.party_id, NEW_PARTY_ID);
  assert.equal(created.tenant_id, TENANT_A);
  assert.equal(created.company_id, COMPANY_A);
  assert.ok(created.access_token_encrypted);
  assert.ok(created.connected_at);
});

test("10: tenant A cannot affect tenant B", async () => {
  const existingA = activeConnection({ scope: SCOPE_A, partyId: OLD_PARTY_ID });
  const existingB = activeConnection({
    scope: SCOPE_B,
    partyId: FOREIGN_PARTY_ID,
    connectedAt: "2026-02-01T08:00:00.000Z",
  });
  const { env, bookingKv } = makeEnv({
    [buildBillitOAuthConnectionKey(SCOPE_A)]: existingA,
    [buildBillitOAuthConnectionKey(SCOPE_B)]: existingB,
  });
  const beforeB = snapshotConnection(bookingKv, SCOPE_B);
  const started = await startBillitOAuthForScope(env, SCOPE_A);
  assert.equal(snapshotConnection(bookingKv, SCOPE_B), beforeB);
  const authUrl = parseAuthorizationUrl(started.body.authorization_url);
  installHappyBillitFetch({ partyId: NEW_PARTY_ID });
  await completeBillitOAuthCallback(env, {
    code: "auth-code-a",
    state: authUrl.searchParams.get("state"),
  });
  assert.equal(snapshotConnection(bookingKv, SCOPE_B), beforeB);
  assert.equal(parseConnection(bookingKv, SCOPE_B).party_id, FOREIGN_PARTY_ID);
  assert.equal(parseConnection(bookingKv, SCOPE_A).party_id, NEW_PARTY_ID);
});

test("11: company A cannot affect company B", async () => {
  const existingA = activeConnection({
    scope: SCOPE_A,
    partyId: OLD_PARTY_ID,
  });
  const existingOther = activeConnection({
    scope: SCOPE_A_OTHER_COMPANY,
    partyId: FOREIGN_PARTY_ID,
    connectedAt: "2026-03-01T08:00:00.000Z",
  });
  const { env, bookingKv } = makeEnv({
    [buildBillitOAuthConnectionKey(SCOPE_A)]: existingA,
    [buildBillitOAuthConnectionKey(SCOPE_A_OTHER_COMPANY)]: existingOther,
  });
  const beforeOther = snapshotConnection(bookingKv, SCOPE_A_OTHER_COMPANY);
  const started = await startBillitOAuthForScope(env, SCOPE_A);
  const authUrl = parseAuthorizationUrl(started.body.authorization_url);
  installHappyBillitFetch({ partyId: NEW_PARTY_ID });
  await completeBillitOAuthCallback(env, {
    code: "auth-code-company-a",
    state: authUrl.searchParams.get("state"),
  });
  assert.equal(
    snapshotConnection(bookingKv, SCOPE_A_OTHER_COMPANY),
    beforeOther,
  );
  assert.equal(
    parseConnection(bookingKv, SCOPE_A_OTHER_COMPANY).party_id,
    FOREIGN_PARTY_ID,
  );
});

test("12: authorize and token exchange use the exact same Redirect URI", async () => {
  const { env } = makeEnv();
  const config = resolveBillitOAuthConfig(env);
  const started = await startBillitOAuthForScope(env, SCOPE_A);
  const authUrl = parseAuthorizationUrl(started.body.authorization_url);
  assert.equal(authUrl.searchParams.get("redirect_uri"), REDIRECT_URI);
  assert.equal(started.body.redirect_uri, REDIRECT_URI);
  assert.equal(config.redirect_uri, REDIRECT_URI);
  const built = buildBillitAuthorizationUrl(config, "state-for-uri-check");
  assert.equal(new URL(built).searchParams.get("redirect_uri"), REDIRECT_URI);
  let tokenBody = null;
  fetchHandler = async (input, init) => {
    tokenBody = JSON.parse(String(init?.body || "{}"));
    return new Response(
      JSON.stringify({
        access_token: ACCESS_TOKEN,
        token_type: "Bearer",
        expires_in: 60,
      }),
      { status: 200, headers: { "content-type": "application/json" } },
    );
  };
  const token = await exchangeBillitOAuthCodeForToken(config, "code-uri-check");
  assert.equal(token.ok, true);
  assert.equal(tokenBody.redirect_uri, REDIRECT_URI);
  assert.equal(tokenBody.redirect_uri, authUrl.searchParams.get("redirect_uri"));
});

test("13: logs and error messages never leak tokens, state, client secret, or credentials", async () => {
  const existing = activeConnection();
  const { env, bookingKv } = makeEnv({
    [buildBillitOAuthConnectionKey(SCOPE_A)]: existing,
  });
  const started = await startBillitOAuthForScope(env, SCOPE_A);
  const authUrl = parseAuthorizationUrl(started.body.authorization_url);
  const stateValue = authUrl.searchParams.get("state");
  installHappyBillitFetch({ tokenOk: false });
  const failed = await completeBillitOAuthCallback(env, {
    code: "secret-code-value",
    state: stateValue,
  });
  const denied = await completeBillitOAuthCallback(env, {
    oauthError: "access_denied",
    state: "missing-state-value",
  });
  assertNoSecretLeak(
    [...logs, failed.message, denied.message, JSON.stringify(failed)],
    [stateValue, "secret-code-value"],
  );
  assert.equal(JSON.stringify(failed).includes(CLIENT_SECRET), false);
  assert.equal(snapshotConnection(bookingKv, SCOPE_A).includes(ACCESS_TOKEN), false);
});

test("admin start route uses the same preserve-on-start helper", async () => {
  const existing = activeConnection();
  const { env, bookingKv } = makeEnv({
    [buildBillitOAuthConnectionKey(SCOPE_A)]: existing,
  });
  const before = snapshotConnection(bookingKv, SCOPE_A);
  const req = new Request(
    `https://booking.internal/admin/integrations/billit/oauth/start?tenant_id=${TENANT_A}&company_id=${COMPANY_A}`,
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-admin-token": ADMIN,
      },
      body: JSON.stringify(SCOPE_A),
    },
  );
  const res = await worker.fetch(req, env, {});
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.ok, true);
  assert.equal(body.redirect_uri, REDIRECT_URI);
  assertConnectionUntouched(before, bookingKv, SCOPE_A);
});

test("admin callback route preserves the active connection on denial", async () => {
  const existing = activeConnection();
  const { env, bookingKv } = makeEnv({
    [buildBillitOAuthConnectionKey(SCOPE_A)]: existing,
  });
  const started = await startBillitOAuthForScope(env, SCOPE_A);
  const authUrl = parseAuthorizationUrl(started.body.authorization_url);
  const before = snapshotConnection(bookingKv, SCOPE_A);
  const req = new Request(
    `https://booking.internal/admin/integrations/billit/oauth/callback?error=access_denied&state=${encodeURIComponent(authUrl.searchParams.get("state"))}`,
  );
  const res = await worker.fetch(req, env, {});
  assert.equal(res.status, 200);
  const html = await res.text();
  assert.match(html, /geweigerd of mislukt/);
  assert.equal(snapshotConnection(bookingKv, SCOPE_A), before);
  assertNoSecretLeak([html, ...logs], [authUrl.searchParams.get("state")]);
});
