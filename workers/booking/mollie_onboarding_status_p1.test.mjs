// MOLLIE-ONBOARDING-STATUS-P1 — Regression tests proving the authoritative
// Mollie onboarding/capability status calculation:
//   - connected LIVE + active method -> can_receive_payments: true
//   - connected LIVE + no active method -> can_receive_payments: false,
//     onboarding_status not genuinely pending
//   - genuinely pending verification -> can_receive_payments: false,
//     onboarding_status in-review (Activation pending)
//   - needs-data -> Action required (merchant must supply data)
//   - disconnected -> connected: false
//   - a LIVE refresh (?refresh=live) that fails against Mollie must NOT
//     downgrade an already-confirmed authoritative status, and must report a
//     truthful status_check_error
//   - company A's status/refresh can never affect company B
//   - live refresh uses the existing scoped company-session contract
//     (own-company ok, cross-company 403, no-auth 401, expired rejected;
//     admin token remains only as an operator/server fallback)
//
// Run:
//   node --test workers/booking/mollie_onboarding_status_p1.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import worker from "./fluxidi_booking_worker.js";
import {
  buildScopedMollieConnectAuthKey,
  encryptMollieConnectTokenPayload,
} from "./modules/mollie_connect.js";

const ADMIN = "test-admin-token";
const ENC_KEY = "test-mollie-connect-encryption-key-please-rotate";

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

function baseEnv(bookingKv) {
  return {
    ADMIN_TOKEN: ADMIN,
    BOOKING_KV: bookingKv,
    MOLLIE_CONNECT_ENCRYPTION_KEY: ENC_KEY,
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
    ...encryptedTokens,
    lastConnectedAt,
    updatedAt: lastConnectedAt,
  };
  await bookingKv.put(key, JSON.stringify(record));
  return { key, record };
}

// `sanitizeMollieConnectStatus` requires BOTH the scoped connect-auth record
// AND the scoped business profile's `mollie_connected` flag to agree before
// reporting `connected: true` — mirrors what the real OAuth callback writes
// via updateBusinessProfileMollieMetadata.
async function seedBusinessProfileMollieConnected(bookingKv, { tenantId, companyId }, connected) {
  const key = `tenant:${tenantId}:company:${companyId}:business_profile:v1`;
  await bookingKv.put(
    key,
    JSON.stringify({
      business_profile: { mollie_connected: connected, mollieConnected: connected },
    }),
  );
}

async function sha256Hex(text) {
  const data = new TextEncoder().encode(String(text || ""));
  const digest = await crypto.subtle.digest("SHA-256", data);
  const bytes = new Uint8Array(digest);
  let hex = "";
  for (const byte of bytes) hex += byte.toString(16).padStart(2, "0");
  return hex;
}

async function seedCompanySession(bookingKv, {
  tokenValue,
  tenantId,
  companyId,
  expiresAt = new Date(Date.now() + 3_600_000).toISOString(),
}) {
  const hash = await sha256Hex(tokenValue);
  const key = `company_admin:session:${hash}:v1`;
  const record = {
    role: "company_admin",
    tenant_id: tenantId,
    company_id: companyId,
    expires_at: expiresAt,
  };
  await bookingKv.put(key, JSON.stringify(record));
  return { key, record, tokenValue };
}

function statusRequest({
  tenantId,
  companyId,
  adminToken = ADMIN,
  bearerToken = null,
  live = false,
}) {
  const url = new URL("https://booking.internal/admin/mollie/connect/status");
  url.searchParams.set("tenant_id", tenantId);
  url.searchParams.set("company_id", companyId);
  if (live) url.searchParams.set("refresh", "live");
  const headers = {};
  if (adminToken) headers["x-admin-token"] = adminToken;
  if (bearerToken) headers["authorization"] = `Bearer ${bearerToken}`;
  return new Request(url.toString(), { method: "GET", headers });
}

function mockMollieOnboardingFetch({ ok, status = "completed", canReceivePayments = true }) {
  const original = global.fetch;
  global.fetch = async (input) => {
    const href = typeof input === "string" ? input : input?.url;
    if (String(href).includes("api.mollie.com/v2/onboarding/me")) {
      if (!ok) {
        return new Response("mollie unavailable", { status: 503 });
      }
      return new Response(
        JSON.stringify({ status, canReceivePayments }),
        { status: 200, headers: { "content-type": "application/json" } },
      );
    }
    if (String(href).includes("api.mollie.com")) {
      // Organizations/profiles best-effort calls made by other helpers.
      return new Response(JSON.stringify({}), { status: 200 });
    }
    return original ? original(input) : new Response("{}", { status: 200 });
  };
  return () => {
    global.fetch = original;
  };
}

// ---------------------------------------------------------------------------
// connected LIVE + active method -> can_receive_payments true (maps to
// "Complete/Active" on the client).
// ---------------------------------------------------------------------------

test("connected LIVE + active method -> can_receive_payments true, onboarding completed", async () => {
  const bookingKv = makeKV();
  const env = baseEnv(bookingKv);
  await seedMollieConnectRecord(bookingKv, { tenant_id: "T1", company_id: "C1" }, {
    onboardingStatus: "completed",
    canReceivePayments: true,
  });
  await seedBusinessProfileMollieConnected(bookingKv, { tenantId: "T1", companyId: "C1" }, true);
  const res = await worker.fetch(
    statusRequest({ tenantId: "T1", companyId: "C1" }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 200);
  assert.equal(j.connected, true);
  assert.equal(j.mollie_mode, "live");
  assert.equal(j.onboarding_status, "completed");
  assert.equal(j.can_receive_payments, true);
});

// ---------------------------------------------------------------------------
// connected LIVE + no active methods -> can_receive_payments false, onboarding
// NOT genuinely pending (maps to "Action required" on the client).
// ---------------------------------------------------------------------------

test("connected LIVE + no active methods -> can_receive_payments false, onboarding completed (not pending)", async () => {
  const bookingKv = makeKV();
  const env = baseEnv(bookingKv);
  await seedMollieConnectRecord(bookingKv, { tenant_id: "T1", company_id: "C1" }, {
    onboardingStatus: "completed",
    canReceivePayments: false,
  });
  await seedBusinessProfileMollieConnected(bookingKv, { tenantId: "T1", companyId: "C1" }, true);
  const res = await worker.fetch(
    statusRequest({ tenantId: "T1", companyId: "C1" }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 200);
  assert.equal(j.connected, true);
  assert.equal(j.can_receive_payments, false);
  assert.equal(j.onboarding_status, "completed");
});

// ---------------------------------------------------------------------------
// Genuinely pending verification -> can_receive_payments false + onboarding
// still in-review (maps to "Activation pending"). needs-data is Action
// required and is covered by the Flutter resolver tests.
// ---------------------------------------------------------------------------

test("genuinely pending verification -> can_receive_payments false, onboarding in-review", async () => {
  const bookingKv = makeKV();
  const env = baseEnv(bookingKv);
  await seedMollieConnectRecord(bookingKv, { tenant_id: "T1", company_id: "C1" }, {
    onboardingStatus: "in-review",
    canReceivePayments: false,
  });
  await seedBusinessProfileMollieConnected(bookingKv, { tenantId: "T1", companyId: "C1" }, true);
  const res = await worker.fetch(
    statusRequest({ tenantId: "T1", companyId: "C1" }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 200);
  assert.equal(j.connected, true);
  assert.equal(j.can_receive_payments, false);
  assert.equal(j.onboarding_status, "in-review");
});

// ---------------------------------------------------------------------------
// Disconnected -> connected: false ("Not connected").
// ---------------------------------------------------------------------------

test("disconnected company -> connected false regardless of stale onboarding fields", async () => {
  const bookingKv = makeKV();
  const env = baseEnv(bookingKv);
  await seedMollieConnectRecord(bookingKv, { tenant_id: "T1", company_id: "C1" }, {
    connected: false,
    status: "disconnected",
    onboardingStatus: "completed",
    canReceivePayments: true,
    accessToken: null,
  });
  const res = await worker.fetch(
    statusRequest({ tenantId: "T1", companyId: "C1" }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 200);
  assert.equal(j.connected, false);
  assert.equal(j.status, "disconnected");
});

test("no record at all -> connected false, source none", async () => {
  const bookingKv = makeKV();
  const env = baseEnv(bookingKv);
  const res = await worker.fetch(
    statusRequest({ tenantId: "T-none", companyId: "C-none" }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 200);
  assert.equal(j.connected, false);
  assert.equal(j.source, "none");
});

// ---------------------------------------------------------------------------
// Live refresh success updates the stored record and the response
// immediately.
// ---------------------------------------------------------------------------

test("?refresh=live success updates onboarding_status/can_receive_payments immediately", async () => {
  const bookingKv = makeKV();
  const env = baseEnv(bookingKv);
  const { key } = await seedMollieConnectRecord(bookingKv, { tenant_id: "T1", company_id: "C1" }, {
    onboardingStatus: "in-review",
    canReceivePayments: false,
  });
  await seedBusinessProfileMollieConnected(bookingKv, { tenantId: "T1", companyId: "C1" }, true);
  const restore = mockMollieOnboardingFetch({
    ok: true,
    status: "completed",
    canReceivePayments: true,
  });
  try {
    const res = await worker.fetch(
      statusRequest({ tenantId: "T1", companyId: "C1", live: true }),
      env,
      {},
    );
    const j = await res.json();
    assert.equal(res.status, 200);
    assert.equal(j.status_check, "ok");
    assert.equal(j.onboarding_status, "completed");
    assert.equal(j.can_receive_payments, true);

    const stored = JSON.parse(bookingKv.store.get(key));
    assert.equal(stored.onboardingStatus, "completed");
    assert.equal(stored.canReceivePayments, true);
  } finally {
    restore();
  }
});

// ---------------------------------------------------------------------------
// A temporary live-refresh failure must NOT downgrade an already-confirmed
// active account, and must surface a truthful error.
// ---------------------------------------------------------------------------

test("?refresh=live failure preserves last authoritative status and reports a truthful error", async () => {
  const bookingKv = makeKV();
  const env = baseEnv(bookingKv);
  const { key } = await seedMollieConnectRecord(bookingKv, { tenant_id: "T1", company_id: "C1" }, {
    onboardingStatus: "completed",
    canReceivePayments: true,
  });
  await seedBusinessProfileMollieConnected(bookingKv, { tenantId: "T1", companyId: "C1" }, true);
  const restore = mockMollieOnboardingFetch({ ok: false });
  try {
    const res = await worker.fetch(
      statusRequest({ tenantId: "T1", companyId: "C1", live: true }),
      env,
      {},
    );
    const j = await res.json();
    assert.equal(res.status, 200);
    // Never downgraded: still shows the last-known-good authoritative state.
    assert.equal(j.connected, true);
    assert.equal(j.onboarding_status, "completed");
    assert.equal(j.can_receive_payments, true);
    // But the failure is reported truthfully.
    assert.equal(j.status_check, "failed");
    assert.equal(typeof j.status_check_error, "string");
    assert.ok(j.status_check_error.length > 0);

    // The stored record itself was not downgraded either.
    const stored = JSON.parse(bookingKv.store.get(key));
    assert.equal(stored.onboardingStatus, "completed");
    assert.equal(stored.canReceivePayments, true);
    assert.equal(typeof stored.lastStatusCheckError, "string");
  } finally {
    restore();
  }
});

test("a normal (non-live) status read never triggers a Mollie API call", async () => {
  const bookingKv = makeKV();
  const env = baseEnv(bookingKv);
  await seedMollieConnectRecord(bookingKv, { tenant_id: "T1", company_id: "C1" }, {
    onboardingStatus: "completed",
    canReceivePayments: true,
  });
  let called = false;
  const original = global.fetch;
  global.fetch = async (input) => {
    called = true;
    return original(input);
  };
  try {
    const res = await worker.fetch(
      statusRequest({ tenantId: "T1", companyId: "C1", live: false }),
      env,
      {},
    );
    assert.equal(res.status, 200);
    assert.equal(called, false);
  } finally {
    global.fetch = original;
  }
});

// ---------------------------------------------------------------------------
// Tenant/company scoping: company A's status and refresh can never affect
// company B.
// ---------------------------------------------------------------------------

test("company A status/refresh never affects company B", async () => {
  const bookingKv = makeKV();
  const env = baseEnv(bookingKv);
  const a = await seedMollieConnectRecord(bookingKv, { tenant_id: "T1", company_id: "C1" }, {
    onboardingStatus: "completed",
    canReceivePayments: true,
  });
  await seedBusinessProfileMollieConnected(bookingKv, { tenantId: "T1", companyId: "C1" }, true);
  const b = await seedMollieConnectRecord(bookingKv, { tenant_id: "T1", company_id: "C2" }, {
    connected: false,
    status: "disconnected",
    onboardingStatus: null,
    canReceivePayments: null,
    accessToken: null,
  });

  const restore = mockMollieOnboardingFetch({
    ok: true,
    status: "needs-data",
    canReceivePayments: false,
  });
  try {
    // Live-refresh company A only.
    const resA = await worker.fetch(
      statusRequest({ tenantId: "T1", companyId: "C1", live: true }),
      env,
      {},
    );
    const jA = await resA.json();
    assert.equal(jA.status_check, "ok");
    assert.equal(jA.onboarding_status, "needs-data");

    // Company B's stored record and status response must be untouched.
    const storedB = JSON.parse(bookingKv.store.get(b.key));
    assert.equal(storedB.connected, false);
    assert.equal(storedB.onboardingStatus ?? null, null);

    const resB = await worker.fetch(
      statusRequest({ tenantId: "T1", companyId: "C2" }),
      env,
      {},
    );
    const jB = await resB.json();
    assert.equal(jB.connected, false);
    assert.equal(jB.tenant_id, "T1");
    assert.equal(jB.company_id, "C2");
  } finally {
    restore();
  }

  // Sanity: company A's own record really did change (proves the refresh in
  // this test was exercising real isolation, not two no-ops).
  const storedA = JSON.parse(bookingKv.store.get(a.key));
  assert.equal(storedA.onboardingStatus, "needs-data");
  assert.equal(storedA.canReceivePayments, false);
});

// ---------------------------------------------------------------------------
// Authorization: live refresh uses the existing scoped company-session
// contract (admin token remains only as an operator/server fallback).
// ---------------------------------------------------------------------------

test("company-owner session can live-refresh Mollie status for its own company", async () => {
  const bookingKv = makeKV();
  const env = baseEnv(bookingKv);
  await seedMollieConnectRecord(bookingKv, { tenant_id: "T1", company_id: "C1" }, {
    onboardingStatus: "in-review",
    canReceivePayments: false,
  });
  await seedBusinessProfileMollieConnected(bookingKv, { tenantId: "T1", companyId: "C1" }, true);
  await seedCompanySession(bookingKv, {
    tokenValue: "owner-a-token",
    tenantId: "T1",
    companyId: "C1",
  });
  const restore = mockMollieOnboardingFetch({
    ok: true,
    status: "completed",
    canReceivePayments: true,
  });
  try {
    const res = await worker.fetch(
      statusRequest({
        tenantId: "T1",
        companyId: "C1",
        adminToken: null,
        bearerToken: "owner-a-token",
        live: true,
      }),
      env,
      {},
    );
    const j = await res.json();
    assert.equal(res.status, 200);
    assert.equal(j.ok, true);
    assert.equal(j.tenant_id, "T1");
    assert.equal(j.company_id, "C1");
    assert.equal(j.status_check, "ok");
    assert.equal(j.can_receive_payments, true);
    assert.equal(j.onboarding_status, "completed");
  } finally {
    restore();
  }
});

test("company A session cannot refresh/read company B Mollie status", async () => {
  const bookingKv = makeKV();
  const env = baseEnv(bookingKv);
  await seedMollieConnectRecord(bookingKv, { tenant_id: "T1", company_id: "C1" }, {
    onboardingStatus: "completed",
    canReceivePayments: true,
  });
  await seedMollieConnectRecord(bookingKv, { tenant_id: "T1", company_id: "C2" }, {
    onboardingStatus: "completed",
    canReceivePayments: true,
  });
  await seedBusinessProfileMollieConnected(bookingKv, { tenantId: "T1", companyId: "C1" }, true);
  await seedBusinessProfileMollieConnected(bookingKv, { tenantId: "T1", companyId: "C2" }, true);
  await seedCompanySession(bookingKv, {
    tokenValue: "owner-a-token",
    tenantId: "T1",
    companyId: "C1",
  });
  const res = await worker.fetch(
    statusRequest({
      tenantId: "T1",
      companyId: "C2",
      adminToken: null,
      bearerToken: "owner-a-token",
      live: true,
    }),
    env,
    {},
  );
  assert.equal(res.status, 403);
  const j = await res.json();
  assert.equal(j.ok, false);
  assert.equal(j.error, "forbidden");
});

test("no-auth live refresh returns structured JSON 401", async () => {
  const bookingKv = makeKV();
  const env = baseEnv(bookingKv);
  await seedMollieConnectRecord(bookingKv, { tenant_id: "T1", company_id: "C1" });
  const res = await worker.fetch(
    statusRequest({
      tenantId: "T1",
      companyId: "C1",
      adminToken: null,
      bearerToken: null,
      live: true,
    }),
    env,
    {},
  );
  assert.equal(res.status, 401);
  assert.match(
    String(res.headers.get("content-type") || ""),
    /^application\/json\b/,
  );
  const j = await res.json();
  assert.equal(j.ok, false);
  assert.equal(j.error, "unauthorized");
});

test("expired company session is rejected on Mollie status/refresh", async () => {
  const bookingKv = makeKV();
  const env = baseEnv(bookingKv);
  await seedMollieConnectRecord(bookingKv, { tenant_id: "T1", company_id: "C1" });
  await seedCompanySession(bookingKv, {
    tokenValue: "expired-owner-token",
    tenantId: "T1",
    companyId: "C1",
    expiresAt: new Date(Date.now() - 60_000).toISOString(),
  });
  const res = await worker.fetch(
    statusRequest({
      tenantId: "T1",
      companyId: "C1",
      adminToken: null,
      bearerToken: "expired-owner-token",
      live: true,
    }),
    env,
    {},
  );
  assert.equal(res.status, 401);
  const j = await res.json();
  assert.equal(j.ok, false);
  assert.equal(j.error, "unauthorized");
});

test("malformed company session bearer is rejected on Mollie status/refresh", async () => {
  const bookingKv = makeKV();
  const env = baseEnv(bookingKv);
  await seedMollieConnectRecord(bookingKv, { tenant_id: "T1", company_id: "C1" });
  const res = await worker.fetch(
    statusRequest({
      tenantId: "T1",
      companyId: "C1",
      adminToken: null,
      bearerToken: "not-a-real-session",
      live: true,
    }),
    env,
    {},
  );
  assert.equal(res.status, 401);
  const j = await res.json();
  assert.equal(j.ok, false);
  assert.equal(j.error, "unauthorized");
});

test("admin token remains as operator/server fallback for Mollie status/refresh", async () => {
  const bookingKv = makeKV();
  const env = baseEnv(bookingKv);
  await seedMollieConnectRecord(bookingKv, { tenant_id: "T1", company_id: "C1" }, {
    onboardingStatus: "completed",
    canReceivePayments: true,
  });
  await seedBusinessProfileMollieConnected(bookingKv, { tenantId: "T1", companyId: "C1" }, true);
  const res = await worker.fetch(
    statusRequest({
      tenantId: "T1",
      companyId: "C1",
      adminToken: ADMIN,
      bearerToken: null,
      live: false,
    }),
    env,
    {},
  );
  assert.equal(res.status, 200);
  const j = await res.json();
  assert.equal(j.ok, true);
  assert.equal(j.connected, true);
  assert.equal(j.can_receive_payments, true);
});

test("company-owner live-refresh failure preserves last authoritative active status", async () => {
  const bookingKv = makeKV();
  const env = baseEnv(bookingKv);
  const { key } = await seedMollieConnectRecord(
    bookingKv,
    { tenant_id: "T1", company_id: "C1" },
    {
      onboardingStatus: "completed",
      canReceivePayments: true,
    },
  );
  await seedBusinessProfileMollieConnected(bookingKv, { tenantId: "T1", companyId: "C1" }, true);
  await seedCompanySession(bookingKv, {
    tokenValue: "owner-a-token",
    tenantId: "T1",
    companyId: "C1",
  });
  const restore = mockMollieOnboardingFetch({ ok: false });
  try {
    const res = await worker.fetch(
      statusRequest({
        tenantId: "T1",
        companyId: "C1",
        adminToken: null,
        bearerToken: "owner-a-token",
        live: true,
      }),
      env,
      {},
    );
    const j = await res.json();
    assert.equal(res.status, 200);
    assert.equal(j.connected, true);
    assert.equal(j.onboarding_status, "completed");
    assert.equal(j.can_receive_payments, true);
    assert.equal(j.status_check, "failed");
    assert.ok(String(j.status_check_error || "").length > 0);
    const stored = JSON.parse(bookingKv.store.get(key));
    assert.equal(stored.onboardingStatus, "completed");
    assert.equal(stored.canReceivePayments, true);
  } finally {
    restore();
  }
});
