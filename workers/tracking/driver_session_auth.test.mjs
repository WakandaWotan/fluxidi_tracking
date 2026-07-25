// SECURITY-REMOVE-CLIENT-ADMIN-TOKEN-P0-1 (Phase A)
//
// Two-tenant / two-driver integration tests that prove:
//   1. driver bearer authenticates driver-lifecycle routes on the tracking
//      worker without ADMIN_TOKEN;
//   2. tenant/company/driver derived from the session are authoritative;
//   3. conflicting caller-supplied scope fails closed with 403;
//   4. missing/expired/random sessions fail closed with 401;
//   5. ADMIN_TOKEN remains accepted as a dual-auth fallback for internal
//      callers (Flutter no longer sends it after this task).
//
// Run:
//   node --test workers/tracking/driver_session_auth.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import worker from "./fluxidi_tracking_api_worker_V2_1_with_route_index.js";

const ADMIN = "test-admin-token";

async function sha256Hex(text) {
  const data = new TextEncoder().encode(String(text || ""));
  const digest = await crypto.subtle.digest("SHA-256", data);
  const bytes = new Uint8Array(digest);
  let hex = "";
  for (const byte of bytes) hex += byte.toString(16).padStart(2, "0");
  return hex;
}

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

async function seedDriverSession({
  tokenValue,
  tenantId,
  companyId,
  driverId,
  role = "driver",
  expiresAt = new Date(Date.now() + 3600_000).toISOString(),
}) {
  const hash = await sha256Hex(tokenValue);
  const key = `public_driver:session:${hash}:v1`;
  return {
    key,
    record: {
      role,
      tenant_id: tenantId,
      company_id: companyId,
      driver_id: driverId,
      expires_at: expiresAt,
    },
  };
}

async function makeEnvWithTwoDrivers({ expireAlice = false } = {}) {
  const aliceExpires = expireAlice
    ? new Date(Date.now() - 60_000).toISOString()
    : undefined;
  const alice = await seedDriverSession({
    tokenValue: "alice-token",
    tenantId: "T1",
    companyId: "C1",
    driverId: "D-alice",
    ...(aliceExpires ? { expiresAt: aliceExpires } : {}),
  });
  const bob = await seedDriverSession({
    tokenValue: "bob-token",
    tenantId: "T2",
    companyId: "C2",
    driverId: "D-bob",
  });
  // Seed a tracking session owned by Alice (T1/C1) so /track/ping can hit it.
  const sessionKey = "tenant:T1:company:C1:session:s_alice";
  const trackingSession = {
    session_id: "s_alice",
    tenant_id: "T1",
    company_id: "C1",
    tenantId: "T1",
    companyId: "C1",
    driver_id: "D-alice",
    owner_driver_id: "D-alice",
    booking_id: "b_1",
    status: "active",
    started_at: "2026-07-20T09:00:00.000Z",
    points: [],
  };
  const bookingKv = makeKV({
    [alice.key]: alice.record,
    [bob.key]: bob.record,
  });
  const trackingKv = makeKV({
    [sessionKey]: JSON.stringify(trackingSession),
  });
  return {
    env: {
      ADMIN_TOKEN: ADMIN,
      BOOKING_KV: bookingKv,
      FLUXIDI_TRACKING: trackingKv,
    },
    alice,
    bob,
    trackingKv,
    bookingKv,
  };
}

function pingRequest({ token = null, adminToken = null, body }) {
  const headers = { "content-type": "application/json" };
  if (adminToken) headers["x-admin-token"] = adminToken;
  if (token) headers["authorization"] = `Bearer ${token}`;
  return new Request("https://track.internal/track/ping", {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
}

const alicePing = () => ({
  session_id: "s_alice",
  lat: 51.1,
  lon: 4.4,
  tenant_id: "T1",
  company_id: "C1",
  driver_id: "D-alice",
});

test("driver bearer authenticates /track/ping without admin token", async () => {
  const { env } = await makeEnvWithTwoDrivers();
  const res = await worker.fetch(
    pingRequest({ token: "alice-token", body: alicePing() }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 200);
  assert.equal(j.ok, true);
  assert.equal(j.session_id, "s_alice");
});

test("driver bearer with omitted scope derives tenant/company/driver from session", async () => {
  const { env } = await makeEnvWithTwoDrivers();
  const res = await worker.fetch(
    pingRequest({
      token: "alice-token",
      body: { session_id: "s_alice", lat: 51.1, lon: 4.4 },
    }),
    env,
    {},
  );
  assert.equal(res.status, 200);
});

test("driver bearer + foreign tenant in body fails closed with 403", async () => {
  const { env } = await makeEnvWithTwoDrivers();
  const res = await worker.fetch(
    pingRequest({
      token: "alice-token",
      body: { ...alicePing(), tenant_id: "T2" },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 403);
  assert.equal(j.ok, false);
  assert.equal(j.error, "forbidden");
});

test("driver bearer + foreign company in body fails closed with 403", async () => {
  const { env } = await makeEnvWithTwoDrivers();
  const res = await worker.fetch(
    pingRequest({
      token: "alice-token",
      body: { ...alicePing(), company_id: "C2" },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 403);
  assert.equal(j.error, "forbidden");
});

test("driver bearer + foreign driver_id in body fails closed with 403", async () => {
  const { env } = await makeEnvWithTwoDrivers();
  const res = await worker.fetch(
    pingRequest({
      token: "alice-token",
      body: { ...alicePing(), driver_id: "D-bob" },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 403);
  assert.equal(j.error, "forbidden");
});

test("driver B's bearer cannot ping driver A's tracking session (403 via forbidden or owner block)", async () => {
  const { env } = await makeEnvWithTwoDrivers();
  const res = await worker.fetch(
    pingRequest({
      token: "bob-token",
      body: alicePing(),
    }),
    env,
    {},
  );
  const j = await res.json();
  // Bob's session has tenant T2/company C2/driver D-bob; alicePing() carries
  // T1/C1/D-alice, which conflicts with Bob's session scope → 403.
  assert.equal(res.status, 403);
  assert.equal(j.error, "forbidden");
});

test("driver B's bearer with only body.session_id fails on session scope (not admin)", async () => {
  const { env } = await makeEnvWithTwoDrivers();
  const res = await worker.fetch(
    pingRequest({
      token: "bob-token",
      body: { session_id: "s_alice", lat: 51.1, lon: 4.4 },
    }),
    env,
    {},
  );
  // Bob's session derives T2/C2, so the tracking session lookup key becomes
  // tenant:T2:company:C2:session:s_alice which does not exist → 500-style error.
  // We assert it does not succeed (never a 200).
  assert.notEqual(res.status, 200);
});

test("expired driver session fails closed with 401 (session evicted)", async () => {
  const { env } = await makeEnvWithTwoDrivers({ expireAlice: true });
  const res = await worker.fetch(
    pingRequest({ token: "alice-token", body: alicePing() }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 401);
  assert.equal(j.error, "unauthorized");
});

test("random bearer fails closed with 401", async () => {
  const { env } = await makeEnvWithTwoDrivers();
  const res = await worker.fetch(
    pingRequest({ token: "does-not-exist", body: alicePing() }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 401);
  assert.equal(j.error, "unauthorized");
});

test("no auth at all fails closed with 401", async () => {
  const { env } = await makeEnvWithTwoDrivers();
  const res = await worker.fetch(pingRequest({ body: alicePing() }), env, {});
  const j = await res.json();
  assert.equal(res.status, 401);
  assert.equal(j.error, "unauthorized");
});

test("dual auth: ADMIN_TOKEN alone still authenticates (retained for platform callers)", async () => {
  const { env } = await makeEnvWithTwoDrivers();
  const res = await worker.fetch(
    pingRequest({ adminToken: ADMIN, body: alicePing() }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 200);
  assert.equal(j.ok, true);
});

test("/track/session/start accepts driver bearer", async () => {
  const { env } = await makeEnvWithTwoDrivers();
  const req = new Request("https://track.internal/track/session/start", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: "Bearer alice-token",
    },
    body: JSON.stringify({
      tenant_id: "T1",
      company_id: "C1",
      booking_id: "b_new",
      pickup: "Ghent",
      dropoff: "Kortrijk",
      driver_id: "D-alice",
      actor_role: "driver",
      actor_driver_id: "D-alice",
    }),
  });
  const res = await worker.fetch(req, env, {});
  // Must not fail on auth. Business logic may still return various shapes; we
  // only assert this is not a 401/403.
  assert.notEqual(res.status, 401);
  assert.notEqual(res.status, 403);
});

test("/track/session/start rejects foreign tenant in body with 403", async () => {
  const { env } = await makeEnvWithTwoDrivers();
  const req = new Request("https://track.internal/track/session/start", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: "Bearer alice-token",
    },
    body: JSON.stringify({
      tenant_id: "T2",
      company_id: "C2",
      booking_id: "b_new",
      driver_id: "D-alice",
      actor_role: "driver",
      actor_driver_id: "D-alice",
    }),
  });
  const res = await worker.fetch(req, env, {});
  const j = await res.json();
  assert.equal(res.status, 403);
  assert.equal(j.error, "forbidden");
});
