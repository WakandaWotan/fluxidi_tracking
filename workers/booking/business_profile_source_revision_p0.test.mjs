// BUSINESS-PROFILE-SOURCE-REVISION-P0 (HTTP integration)
//
// Proves every semantic business_profile:v1 write advances a monotone
// source_revision so Command Center can re-project name/email/phone/vat/status.
//
// Run:
//   node --test workers/booking/business_profile_source_revision_p0.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import worker from "./fluxidi_booking_worker.js";

const TENANT = "fluxidi_fluxidi_ddmh9g";
const COMPANY = "fluxidi_fluxidi_ddmh9g";
const CODE = "FLX-00001";
const TOKEN = "cst_revision_owner";
const PRIMARY = "cvanrokeghem@outlook.com";
const SUPPORT = "info@fluxidi.com";
const BILLING = "billing@fluxidi.com";
const BOOKING = "fluxidi.booking@gmail.com";
const PROFILE_KEY = `tenant:${TENANT}:company:${COMPANY}:business_profile:v1`;

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

// Proven live FLX-00001 shape: source_revision absent (null), version 1,
// email_revision 2, active primary mail verified.
function legacyProfileRecord(overrides = {}) {
  return {
    version: 1,
    updated_at: "2026-08-16T11:06:34.789Z",
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
      phone: "+3211223344",
      vat_number: "BE0123456789",
      country: "BE",
      public_company_code: CODE,
      company_code: CODE,
      email_verification_status: "verified",
      email_revision: 2,
      email_verified_at: "2026-08-16T11:05:53.823Z",
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
    [PROFILE_KEY]: legacyProfileRecord(profileOverrides),
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

function readRecord(kv) {
  const raw = kv.store.get(PROFILE_KEY);
  if (raw == null) return null;
  return typeof raw === "string" ? JSON.parse(raw) : raw;
}

async function saveProfile(env, businessProfile) {
  const res = await worker.fetch(
    post(
      "/admin/business/profile",
      { tenant_id: TENANT, company_id: COMPANY, business_profile: businessProfile },
      { token: TOKEN },
    ),
    env,
  );
  return { res, body: await res.json() };
}

async function startRecovery(env, email) {
  const res = await worker.fetch(
    post("/public/company/recovery/start", { company_code: CODE, email }),
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

test("legacy profile: next semantic change jumps source_revision above email_revision (>2)", async () => {
  const { env, kv } = await makeEnv();
  const before = readRecord(kv);
  assert.equal(before.source_revision, undefined);
  assert.equal(before.business_profile.email_revision, 2);

  const { res } = await saveProfile(env, {
    companyName: "Fluxidi Taxi",
    email: PRIMARY,
  });
  assert.equal(res.status, 200);

  const after = readRecord(kv);
  assert.equal(after.version, 1); // backwards compatible
  assert.equal(after.source_revision, 3);
  assert.ok(after.source_revision > 2);
  assert.equal(after.business_profile.source_revision, 3);
  // A name change must never reset the proven verified recovery identity.
  assert.equal(after.business_profile.email, PRIMARY);
  assert.equal(after.business_profile.email_verification_status, "verified");
  assert.equal(after.business_profile.email_verified_at, before.business_profile.email_verified_at);
});

test("confirmed mail change advances the profile revision twice (pending then promote)", async () => {
  const { env, kv } = await makeEnv();

  const pendingSave = await saveProfile(env, {
    companyName: "Fluxidi",
    email: "new-contact@fluxidi.com",
  });
  assert.equal(pendingSave.body.confirmation_required, true);
  assert.ok(pendingSave.body.challenge_id);
  const afterPending = readRecord(kv);
  assert.equal(afterPending.business_profile.email, PRIMARY); // old mail stays active
  assert.equal(afterPending.business_profile.pending_email, "new-contact@fluxidi.com");
  const revAfterPending = afterPending.source_revision;
  assert.ok(revAfterPending > 2);

  const confirmed = await verifyRecovery(env, {
    email: "new-contact@fluxidi.com",
    challengeId: pendingSave.body.challenge_id,
    otp: pendingSave.body.recovery_code,
  });
  assert.equal(confirmed.res.status, 200);
  assert.equal(confirmed.body.ok, true);

  const afterPromote = readRecord(kv);
  assert.equal(afterPromote.business_profile.email, "new-contact@fluxidi.com");
  assert.equal(afterPromote.business_profile.pending_email, "");
  assert.equal(afterPromote.business_profile.email_verification_status, "verified");
  assert.ok(afterPromote.source_revision > revAfterPending);
});

test("name, phone and vat changes each advance the same monotone revision", async () => {
  const { env, kv } = await makeEnv();

  await saveProfile(env, { companyName: "Alpha", email: PRIMARY });
  const r1 = readRecord(kv).source_revision;

  await saveProfile(env, { companyName: "Alpha", email: PRIMARY, phone: "+3299887766" });
  const r2 = readRecord(kv).source_revision;

  await saveProfile(env, {
    companyName: "Alpha",
    email: PRIMARY,
    phone: "+3299887766",
    vatNumber: "BE0999888777",
  });
  const r3 = readRecord(kv).source_revision;

  assert.ok(r2 > r1);
  assert.ok(r3 > r2);
});

test("idempotent replay does not advance revision or updated_at", async () => {
  const { env, kv } = await makeEnv();
  const body = { companyName: "Fluxidi Taxi", email: PRIMARY, phone: "+3211223344" };

  await saveProfile(env, body);
  const first = readRecord(kv);

  await saveProfile(env, body);
  const second = readRecord(kv);

  assert.equal(second.source_revision, first.source_revision);
  assert.equal(second.updated_at, first.updated_at);
});

test("a client cannot force source_revision or verified status", async () => {
  const { env, kv } = await makeEnv({
    email_verification_status: "legacy_unverified",
    email_verified_at: "",
  });

  const { res } = await saveProfile(env, {
    companyName: "Fluxidi",
    email: PRIMARY,
    source_revision: 999,
    sourceRevision: 999,
    email_verification_status: "verified",
    email_verified_at: "2026-08-16T11:05:53.823Z",
  });
  assert.equal(res.status, 200);

  const after = readRecord(kv);
  assert.notEqual(after.source_revision, 999);
  assert.ok(after.source_revision >= 1 && after.source_revision <= 5);
  // Verified may only come from a successful recovery challenge, never a POST.
  assert.equal(after.business_profile.email_verification_status, "legacy_unverified");
  assert.equal(after.business_profile.email_verified_at, "");
});

test("support/billing/booking/login mail are never a recovery identity", async () => {
  const { env } = await makeEnv();
  const primary = await startRecovery(env, PRIMARY);
  assert.match(String(primary.body.recovery_code || ""), /^\d{6}$/);

  for (const other of [SUPPORT, BILLING, BOOKING, "owner@fluxidi.com", "login@fluxidi.com"]) {
    const rejected = await startRecovery(env, other);
    assert.equal(rejected.res.status, 200);
    assert.equal(rejected.body.ok, true);
    assert.equal(rejected.body.recovery_code, undefined);
  }
});

test("wrong and reused challenge stay failing without touching the revision", async () => {
  const { env, kv } = await makeEnv();
  const started = await startRecovery(env, PRIMARY);
  const revBefore = readRecord(kv).source_revision ?? null;

  const wrong = await verifyRecovery(env, {
    email: PRIMARY,
    challengeId: started.body.challenge_id,
    otp: "000000",
  });
  assert.equal(wrong.res.status, 403);
  assert.equal(wrong.body.ok, false);

  const ok = await verifyRecovery(env, {
    email: PRIMARY,
    challengeId: started.body.challenge_id,
    otp: started.body.recovery_code,
  });
  assert.equal(ok.res.status, 200);
  const revAfter = readRecord(kv).source_revision;
  assert.ok(revAfter >= 1);

  const reused = await verifyRecovery(env, {
    email: PRIMARY,
    challengeId: started.body.challenge_id,
    otp: started.body.recovery_code,
  });
  assert.equal(reused.res.status, 403);
  assert.equal(reused.body.ok, false);
  assert.equal(readRecord(kv).source_revision, revAfter);
  assert.notEqual(revBefore, undefined);
});

test("stored revision markers never leak provider tokens or references", async () => {
  const { env, kv } = await makeEnv();
  await saveProfile(env, { companyName: "Fluxidi Taxi", email: PRIMARY });
  const after = readRecord(kv);
  // Provider references stay empty for a non-connected fixture; assert we never
  // fabricated or exposed a token/ref value while stamping the revision.
  assert.equal(after.business_profile.mollie_token_ref ?? "", "");
  assert.equal(after.business_profile.mollieTokenRef ?? "", "");
  assert.equal(after.business_profile.mollie_organization_id ?? "", "");
  assert.equal(after.business_profile.mollie_profile_id ?? "", "");
});
