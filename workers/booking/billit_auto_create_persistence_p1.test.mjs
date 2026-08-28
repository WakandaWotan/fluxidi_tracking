// BILLIT-AUTO-CREATE-PERSISTENCE-P1 (HTTP integration)
//
// Proves the Billit "auto-create after paid business invoice" preference
// survives an unrelated general business-profile save. Root cause of the
// reported "toggle reverts to OFF after navigation" bug: the Flutter general
// profile save (POST /admin/business/profile) sends BackendBusinessProfile.
// toJson(), which omits billit_auto_create_after_paid_business_invoice. Before
// the fix, normalizeBusinessProfile defaulted the absent flag back to OFF and
// clobbered the dedicated toggle. preserveServerOwnedBusinessProfilePaymentFields
// now preserves the persisted value whenever the incoming payload omits it,
// while the dedicated toggle route stays authoritative when it includes it.
//
// Hermetic: no live Billit / Cloudflare / production credentials.
//
// Run:
//   node --test workers/booking/billit_auto_create_persistence_p1.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import worker from "./fluxidi_booking_worker.js";

const TENANT = "fluxidi_fluxidi_ddmh9g";
const COMPANY = "fluxidi_fluxidi_ddmh9g";
const CODE = "FLX-00001";
const TOKEN = "cst_auto_create_owner";
const PRIMARY = "cvanrokeghem@outlook.com";
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

function baseProfileRecord(overrides = {}) {
  return {
    version: 1,
    updated_at: "2026-08-16T11:06:34.789Z",
    business_profile: {
      companyName: "Fluxidi",
      legalName: "Fluxidi BV",
      email: PRIMARY,
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
    [PROFILE_KEY]: baseProfileRecord(profileOverrides),
    [`company_admin:session:${sessionHash}:v1`]: {
      role: "company_admin",
      tenant_id: TENANT,
      company_id: COMPANY,
      company_code: CODE,
      expires_at: new Date(Date.now() + 3_600_000).toISOString(),
    },
  });
  return {
    env: { BOOKING_KV: kv, ENVIRONMENT: "test" },
    kv,
  };
}

function post(path, body) {
  return new Request(`https://booking.internal${path}`, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${TOKEN}` },
    body: JSON.stringify(body),
  });
}

function get(path) {
  return new Request(`https://booking.internal${path}`, {
    method: "GET",
    headers: { authorization: `Bearer ${TOKEN}` },
  });
}

function scopeQuery() {
  return `tenant_id=${encodeURIComponent(TENANT)}&company_id=${encodeURIComponent(COMPANY)}`;
}

async function setAutoCreate(env, enabled) {
  const res = await worker.fetch(
    post("/company/billit-auto-create-settings", {
      tenant_id: TENANT,
      company_id: COMPANY,
      billit_auto_create_after_paid_business_invoice: enabled,
    }),
    env,
  );
  return { res, body: await res.json() };
}

async function readAutoCreate(env) {
  const res = await worker.fetch(
    get(`/company/billit-auto-create-settings?${scopeQuery()}`),
    env,
  );
  return { res, body: await res.json() };
}

// Mirrors Flutter BackendBusinessProfile.toJson(): a general profile save that
// carries the everyday company fields but NOT the Billit auto-create flag.
async function saveGeneralProfile(env, businessProfile) {
  const res = await worker.fetch(
    post("/admin/business/profile", {
      tenant_id: TENANT,
      company_id: COMPANY,
      business_profile: businessProfile,
    }),
    env,
  );
  return { res, body: await res.json() };
}

function readStoredFlag(kv) {
  const raw = kv.store.get(PROFILE_KEY);
  const record = typeof raw === "string" ? JSON.parse(raw) : raw;
  return record?.business_profile?.billit_auto_create_after_paid_business_invoice;
}

test("auto-create ON survives an unrelated general business-profile save", async () => {
  const { env, kv } = await makeEnv();

  const enabled = await setAutoCreate(env, true);
  assert.equal(enabled.res.status, 200);
  assert.equal(enabled.body.billit_auto_create_after_paid_business_invoice, true);
  assert.equal(readStoredFlag(kv), true);

  // General profile save that OMITS the Billit flag (Flutter toJson shape).
  const saved = await saveGeneralProfile(env, {
    companyName: "Fluxidi Taxi",
    email: PRIMARY,
    phone: "+3211223344",
  });
  assert.equal(saved.res.status, 200);

  // Regression assertion: the flag must NOT have been clobbered to OFF.
  assert.equal(readStoredFlag(kv), true);
  const reread = await readAutoCreate(env);
  assert.equal(reread.res.status, 200);
  assert.equal(reread.body.billit_auto_create_after_paid_business_invoice, true);
});

test("auto-create OFF survives an unrelated general business-profile save", async () => {
  const { env, kv } = await makeEnv({
    billit_auto_create_after_paid_business_invoice: true,
  });

  const disabled = await setAutoCreate(env, false);
  assert.equal(disabled.res.status, 200);
  assert.equal(disabled.body.billit_auto_create_after_paid_business_invoice, false);
  assert.equal(readStoredFlag(kv), false);

  const saved = await saveGeneralProfile(env, {
    companyName: "Fluxidi Taxi",
    email: PRIMARY,
  });
  assert.equal(saved.res.status, 200);

  assert.equal(readStoredFlag(kv), false);
  const reread = await readAutoCreate(env);
  assert.equal(reread.body.billit_auto_create_after_paid_business_invoice, false);
});

test("the dedicated toggle route stays authoritative (explicit value wins)", async () => {
  const { env, kv } = await makeEnv();

  // Turn ON, then a general save, then explicitly turn OFF: OFF must persist.
  await setAutoCreate(env, true);
  await saveGeneralProfile(env, { companyName: "Fluxidi", email: PRIMARY });
  const off = await setAutoCreate(env, false);
  assert.equal(off.body.billit_auto_create_after_paid_business_invoice, false);
  assert.equal(readStoredFlag(kv), false);

  // Turn back ON explicitly: ON must persist.
  const on = await setAutoCreate(env, true);
  assert.equal(on.body.billit_auto_create_after_paid_business_invoice, true);
  assert.equal(readStoredFlag(kv), true);
});
