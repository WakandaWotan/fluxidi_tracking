// COMPANY-PRIMARY-EMAIL-RECOVERY-P0 — Booking recovery identity.
//
// Run:
//   node --test workers/booking/company_primary_email_recovery_p0.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import worker from "./fluxidi_booking_worker.js";

const TENANT = "fluxidi_fluxidi_ddmh9g";
const COMPANY = "fluxidi_fluxidi_ddmh9g";
const CODE = "FLX-00001";
const TOKEN = "cst_recovery_owner";
const PRIMARY = "contact@fluxidi.com";
const SUPPORT = "info@fluxidi.com";
const BILLING = "billing@fluxidi.com";
const BOOKING = "fluxidi.booking@gmail.com";

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
      return {
        keys: [...store.keys()].map((name) => ({ name })),
        list_complete: true,
      };
    },
  };
}

function profileRecord(overrides = {}) {
  return {
    version: 1,
    updated_at: "2026-08-16T08:00:00.000Z",
    business_profile: {
      companyName: "Fluxidi",
      legalName: "Fluxidi BV",
      email: PRIMARY,
      companyEmail: "route@fluxidi.com",
      supportEmail: SUPPORT,
      billingEmail: BILLING,
      invoiceEmail: BILLING,
      bookingEmail: BOOKING,
      notificationEmail: "notify@fluxidi.com",
      country: "BE",
      public_company_code: CODE,
      company_code: CODE,
      ...overrides,
    },
  };
}

async function makeEnv(profileOverrides = {}) {
  const sessionHash = await sha256Hex(TOKEN);
  const kv = makeKV({
    [`company_link:index:code:${CODE}:v1`]: {
      company_code: CODE,
      tenant_id: TENANT,
      company_id: COMPANY,
      linking_enabled: true,
      display_name: "Fluxidi",
    },
    [`tenant:${TENANT}:company:${COMPANY}:business_profile:v1`]:
      profileRecord(profileOverrides),
    [`company_admin:session:${sessionHash}:v1`]: {
      role: "company_admin",
      tenant_id: TENANT,
      company_id: COMPANY,
      company_code: CODE,
      expires_at: new Date(Date.now() + 3_600_000).toISOString(),
    },
  });
  return {
    env: {
      BOOKING_KV: kv,
      COMPANY_RECOVERY_DEBUG_OTP: "1",
      FLUXIDI_ALLOW_DEBUG_OTP_ECHO: "1",
      ENVIRONMENT: "test",
    },
    kv,
  };
}

function post(path, body, { token } = {}) {
  const headers = { "content-type": "application/json" };
  if (token) headers.authorization = `Bearer ${token}`;
  return new Request(`https://booking.internal${path}`, {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
}

async function startRecovery(env, email) {
  const res = await worker.fetch(
    post("/public/company/recovery/start", {
      company_code: CODE,
      email,
    }),
    env,
  );
  return { res, body: await res.json() };
}

async function verifyRecovery(env, { email, challengeId, otp }) {
  const res = await worker.fetch(
    post("/public/company/recovery/verify", {
      company_code: CODE,
      email,
      challenge_id: challengeId,
      otp,
    }),
    env,
  );
  return { res, body: await res.json() };
}

test("only the primary mail starts a real recovery challenge", async () => {
  const { env } = await makeEnv();
  const primary = await startRecovery(env, PRIMARY);
  assert.equal(primary.res.status, 200);
  assert.equal(primary.body.ok, true);
  assert.equal(typeof primary.body.recovery_code, "string");
  assert.match(primary.body.recovery_code, /^\d{6}$/);

  for (const other of [SUPPORT, BILLING, BOOKING, "owner@fluxidi.com"]) {
    const rejected = await startRecovery(env, other);
    assert.equal(rejected.res.status, 200);
    assert.equal(rejected.body.ok, true);
    assert.equal(rejected.body.recovery_code, undefined);
    assert.equal(rejected.body.message, primary.body.message);
  }
});

test("old mail stays recovery identity while a new mail is pending", async () => {
  const { env } = await makeEnv();
  const save = await worker.fetch(
    post(
      "/admin/business/profile",
      {
        tenant_id: TENANT,
        company_id: COMPANY,
        business_profile: {
          companyName: "Fluxidi",
          legalName: "Fluxidi BV",
          email: "new-contact@fluxidi.com",
          supportEmail: SUPPORT,
          invoiceEmail: BILLING,
          bookingEmail: BOOKING,
          country: "BE",
        },
      },
      { token: TOKEN },
    ),
    env,
  );
  const saved = await save.json();
  assert.equal(save.status, 200);
  assert.equal(saved.business_profile.email, PRIMARY);
  assert.equal(saved.business_profile.pending_email, "new-contact@fluxidi.com");
  assert.equal(saved.confirmation_required, true);
  assert.ok(saved.challenge_id);

  const oldStart = await startRecovery(env, PRIMARY);
  assert.equal(typeof oldStart.body.recovery_code, "string");
  const newStart = await startRecovery(env, "new-contact@fluxidi.com");
  assert.equal(newStart.body.recovery_code, undefined);
});

test("pending mail becomes active only after the existing verify primitive", async () => {
  const { env } = await makeEnv();
  const save = await worker.fetch(
    post(
      "/admin/business/profile",
      {
        tenant_id: TENANT,
        company_id: COMPANY,
        business_profile: {
          companyName: "Fluxidi",
          email: "new-contact@fluxidi.com",
          country: "BE",
        },
      },
      { token: TOKEN },
    ),
    env,
  );
  const saved = await save.json();
  const confirmed = await verifyRecovery(env, {
    email: "new-contact@fluxidi.com",
    challengeId: saved.challenge_id,
    otp: saved.recovery_code,
  });
  assert.equal(confirmed.res.status, 200);
  assert.equal(confirmed.body.ok, true);

  const replay = await verifyRecovery(env, {
    email: "new-contact@fluxidi.com",
    challengeId: saved.challenge_id,
    otp: saved.recovery_code,
  });
  assert.equal(replay.res.status, 403);
  assert.equal(replay.body.ok, false);

  const after = await startRecovery(env, "new-contact@fluxidi.com");
  assert.equal(typeof after.body.recovery_code, "string");
  const stale = await startRecovery(env, PRIMARY);
  assert.equal(stale.body.recovery_code, undefined);
});

test("expired and reused challenges fail generically", async () => {
  const { env, kv } = await makeEnv();
  const started = await startRecovery(env, PRIMARY);
  const challengeKey = [...kv.store.keys()].find((key) =>
    String(key).startsWith("company_recovery:challenge:"),
  );
  const raw = JSON.parse(kv.store.get(challengeKey));
  raw.expires_at = "2020-01-01T00:00:00.000Z";
  kv.store.set(challengeKey, JSON.stringify(raw));
  const expired = await verifyRecovery(env, {
    email: PRIMARY,
    challengeId: started.body.challenge_id,
    otp: started.body.recovery_code,
  });
  assert.equal(expired.res.status, 403);
  assert.equal(expired.body.error, "verification_failed");
});

test("legacy primary mail remains recoverable and promotes after success", async () => {
  const { env } = await makeEnv();
  const started = await startRecovery(env, PRIMARY);
  const verified = await verifyRecovery(env, {
    email: PRIMARY,
    challengeId: started.body.challenge_id,
    otp: started.body.recovery_code,
  });
  assert.equal(verified.res.status, 200);
  assert.equal(verified.body.ok, true);
  const again = await startRecovery(env, PRIMARY);
  assert.equal(typeof again.body.recovery_code, "string");
});
