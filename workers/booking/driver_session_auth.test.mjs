// SECURITY-REMOVE-CLIENT-ADMIN-TOKEN-P0-1 (Phase B)
//
// Integration tests that prove the booking worker's driver-facing routes
// authenticate with the driver's opaque bearer session and reject
// conflicting caller-supplied scope without ever requiring ADMIN_TOKEN.
//
// The tests focus on the auth surface (401 / 403 / non-4xx) of routes that
// were migrated to `_requireDriverSessionOrAdmin`, so they do not need a
// fully-hydrated booking record to prove the security invariant.
//
// Run:
//   node --test workers/booking/driver_session_auth.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import worker from "./fluxidi_booking_worker.js";

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
  const bookingKv = makeKV({
    [alice.key]: alice.record,
    [bob.key]: bob.record,
  });
  return {
    env: {
      ADMIN_TOKEN: ADMIN,
      BOOKING_KV: bookingKv,
    },
    alice,
    bob,
    bookingKv,
  };
}

function trackingBookingRequest({ token = null, adminToken = null, body }) {
  const headers = { "content-type": "application/json" };
  if (adminToken) headers["x-admin-token"] = adminToken;
  if (token) headers["authorization"] = `Bearer ${token}`;
  return new Request("https://booking.internal/tracking/booking", {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
}

const aliceScope = () => ({
  tenant_id: "T1",
  company_id: "C1",
  booking_id: "b_alice_1",
});

test("no auth → 401 on /tracking/booking", async () => {
  const { env } = await makeEnvWithTwoDrivers();
  const res = await worker.fetch(
    trackingBookingRequest({ body: aliceScope() }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 401);
  assert.equal(j.error, "unauthorized");
});

test("random bearer → 401 on /tracking/booking", async () => {
  const { env } = await makeEnvWithTwoDrivers();
  const res = await worker.fetch(
    trackingBookingRequest({ token: "does-not-exist", body: aliceScope() }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 401);
  assert.equal(j.error, "unauthorized");
});

test("expired driver session → 401 on /tracking/booking", async () => {
  const { env } = await makeEnvWithTwoDrivers({ expireAlice: true });
  const res = await worker.fetch(
    trackingBookingRequest({ token: "alice-token", body: aliceScope() }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 401);
  assert.equal(j.error, "unauthorized");
});

test("driver bearer + foreign tenant in body → 403 on /tracking/booking", async () => {
  const { env } = await makeEnvWithTwoDrivers();
  const res = await worker.fetch(
    trackingBookingRequest({
      token: "alice-token",
      body: { ...aliceScope(), tenant_id: "T2" },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 403);
  assert.equal(j.error, "forbidden");
});

test("driver bearer + foreign company in body → 403 on /tracking/booking", async () => {
  const { env } = await makeEnvWithTwoDrivers();
  const res = await worker.fetch(
    trackingBookingRequest({
      token: "alice-token",
      body: { ...aliceScope(), company_id: "C2" },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 403);
  assert.equal(j.error, "forbidden");
});

test("driver bearer + foreign actor_driver_id in body → 403 on /tracking/booking", async () => {
  const { env } = await makeEnvWithTwoDrivers();
  const res = await worker.fetch(
    trackingBookingRequest({
      token: "alice-token",
      body: { ...aliceScope(), actor_driver_id: "D-bob" },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 403);
  assert.equal(j.error, "forbidden");
});

test("driver bearer with matching scope passes auth (may 404 downstream on unknown booking)", async () => {
  const { env } = await makeEnvWithTwoDrivers();
  const res = await worker.fetch(
    trackingBookingRequest({
      token: "alice-token",
      body: aliceScope(),
    }),
    env,
    {},
  );
  // Must not be an auth error. Downstream may fail on missing booking record,
  // but the auth surface itself must accept the driver bearer.
  assert.notEqual(res.status, 401);
  assert.notEqual(res.status, 403);
});

test("driver B's bearer + Alice's scope in body → 403 (session-derived scope wins)", async () => {
  const { env } = await makeEnvWithTwoDrivers();
  const res = await worker.fetch(
    trackingBookingRequest({
      token: "bob-token",
      body: aliceScope(),
    }),
    env,
    {},
  );
  const j = await res.json();
  // Bob's session is T2/C2; the body carries T1/C1, so the auth layer rejects
  // the request with 403 before any booking lookup happens.
  assert.equal(res.status, 403);
  assert.equal(j.error, "forbidden");
});

test("dual auth: ADMIN_TOKEN alone still authenticates /tracking/booking", async () => {
  const { env } = await makeEnvWithTwoDrivers();
  const res = await worker.fetch(
    trackingBookingRequest({
      adminToken: ADMIN,
      body: aliceScope(),
    }),
    env,
    {},
  );
  // Auth must succeed; downstream may 404 the missing booking, but not 401/403.
  assert.notEqual(res.status, 401);
  assert.notEqual(res.status, 403);
});

test("driver bearer with only session_id-style body (no scope) succeeds past auth", async () => {
  const { env } = await makeEnvWithTwoDrivers();
  const res = await worker.fetch(
    trackingBookingRequest({
      token: "alice-token",
      body: { booking_id: "b_alice_1" },
    }),
    env,
    {},
  );
  // Auth layer derives tenant/company from the session and injects into the
  // body; downstream may fail on the missing booking, but not on auth.
  assert.notEqual(res.status, 401);
  assert.notEqual(res.status, 403);
});
