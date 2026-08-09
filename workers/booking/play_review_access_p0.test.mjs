// GOOGLE-PLAY-REVIEW-ACCESS-P0
//
// Fail-closed FLX-00020-only Google Play review access credential.
//
// Run:
//   node --test workers/booking/play_review_access_p0.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import worker from "./fluxidi_booking_worker.js";

const ROUTE_PATH = "/public/company/review-access/verify";
const HERE = dirname(fileURLToPath(import.meta.url));
const WORKER_SRC = readFileSync(join(HERE, "fluxidi_booking_worker.js"), "utf8");

const REVIEW_PLAINTEXT =
  "play-review-test-access-code-32b!"; // tests only; never a production secret
const OTHER_TENANT_CODE = "FLX-00099";

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
    async put(key, val, _opts) {
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

function seedCompanyLinkRecord({
  tenantId,
  companyId,
  companyCode,
  displayName = "Test Co",
  linkingEnabled = true,
}) {
  const key = `company_link:index:code:${companyCode}:v1`;
  return {
    key,
    record: {
      company_code: companyCode,
      companyCode,
      tenant_id: tenantId,
      company_id: companyId,
      display_name: displayName,
      country: "BE",
      linking_enabled: linkingEnabled,
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    },
  };
}

async function makeEnv({
  includeHash = true,
  companyCodeVar = "FLX-00020",
  hashOverride = null,
} = {}) {
  const reviewLink = seedCompanyLinkRecord({
    tenantId: "cmp_fluxidi-google-review_f94c806649",
    companyId: "cmp_fluxidi-google-review_f94c806649",
    companyCode: "FLX-00020",
    displayName: "Fluxidi Google Review",
  });
  const otherLink = seedCompanyLinkRecord({
    tenantId: "T_OTHER",
    companyId: "C_OTHER",
    companyCode: OTHER_TENANT_CODE,
    displayName: "Other Co",
  });
  const bookingKv = makeKV({
    [reviewLink.key]: reviewLink.record,
    [otherLink.key]: otherLink.record,
  });
  const hash = includeHash
    ? hashOverride || (await sha256Hex(REVIEW_PLAINTEXT))
    : "";
  const env = {
    BOOKING_KV: bookingKv,
    PLAY_REVIEW_COMPANY_CODE: companyCodeVar,
  };
  if (includeHash) env.PLAY_REVIEW_ACCESS_CODE_HASH = hash;
  return { env, bookingKv, reviewLink, otherLink, hash };
}

function createRequest(body, { headers = {} } = {}) {
  return new Request(`https://booking.internal${ROUTE_PATH}`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "cf-connecting-ip": "203.0.113.10",
      "user-agent": "play-review-access-test",
      ...headers,
    },
    body: JSON.stringify(body),
  });
}

function sessionKeys(bookingKv) {
  return [...bookingKv.store.keys()].filter((k) =>
    String(k).startsWith("company_admin:session:"),
  );
}

test("source contracts: review route + recovery routes preserved; no plaintext secret", () => {
  assert.match(WORKER_SRC, /\/public\/company\/review-access\/verify/);
  assert.match(WORKER_SRC, /handlePublicCompanyReviewAccessVerify/);
  assert.match(WORKER_SRC, /\/public\/company\/recovery\/start/);
  assert.match(WORKER_SRC, /\/public\/company\/recovery\/verify/);
  assert.match(WORKER_SRC, /public_company_review_access/);
  assert.match(WORKER_SRC, /PLAY_REVIEW_ACCESS_CODE_HASH/);
  assert.equal(WORKER_SRC.includes(REVIEW_PLAINTEXT), false);
  assert.equal(WORKER_SRC.includes("play-review-test-access-code"), false);
});

test("1) FLX-00020 + correct credential → session for that tenant only", async () => {
  const { env, bookingKv, reviewLink } = await makeEnv();
  const res = await worker.fetch(
    createRequest({
      company_code: "FLX-00020",
      access_code: REVIEW_PLAINTEXT,
      device_label: "Review device",
      device_type: "tablet",
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 200);
  assert.equal(j.ok, true);
  assert.equal(j.role, "companyAdmin");
  assert.equal(j.company_code, "FLX-00020");
  assert.equal(j.tenant_id, reviewLink.record.tenant_id);
  assert.equal(j.company_id, reviewLink.record.company_id);
  assert.equal(j.link_method, "public_company_review_access");
  assert.match(String(j.company_session_token || ""), /^cst_/);
  assert.equal(String(j.company?.display_name || ""), "Fluxidi Google Review");
  const keys = sessionKeys(bookingKv);
  assert.equal(keys.length, 1);
  const stored = await bookingKv.get(keys[0], { type: "json" });
  assert.equal(stored.tenant_id, reviewLink.record.tenant_id);
  assert.equal(stored.company_id, reviewLink.record.company_id);
  assert.equal(stored.company_code, "FLX-00020");
  assert.equal(stored.link_method, "public_company_review_access");
});

test("2) FLX-00020 + incorrect credential → denied, no session", async () => {
  const { env, bookingKv } = await makeEnv();
  const res = await worker.fetch(
    createRequest({
      company_code: "FLX-00020",
      access_code: "definitely-wrong-access-code!!",
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 403);
  assert.equal(j.ok, false);
  assert.equal(j.error, "verification_failed");
  assert.equal(sessionKeys(bookingKv).length, 0);
});

test("3) FLX-00020 + empty credential → denied", async () => {
  const { env, bookingKv } = await makeEnv();
  const res = await worker.fetch(
    createRequest({
      company_code: "FLX-00020",
      access_code: "",
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 403);
  assert.equal(j.ok, false);
  assert.equal(j.error, "verification_failed");
  assert.equal(sessionKeys(bookingKv).length, 0);
});

test("4) other tenant + correct review credential → denied / no bypass", async () => {
  const { env, bookingKv } = await makeEnv();
  const res = await worker.fetch(
    createRequest({
      company_code: OTHER_TENANT_CODE,
      access_code: REVIEW_PLAINTEXT,
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 403);
  assert.equal(j.ok, false);
  assert.equal(j.error, "verification_failed");
  assert.equal(sessionKeys(bookingKv).length, 0);
});

test("5) ordinary recovery routes still registered (source + method guard)", async () => {
  const { env } = await makeEnv();
  const startGet = await worker.fetch(
    new Request("https://booking.internal/public/company/recovery/start", {
      method: "GET",
    }),
    env,
    {},
  );
  assert.equal(startGet.status, 405);
  const verifyGet = await worker.fetch(
    new Request("https://booking.internal/public/company/recovery/verify", {
      method: "GET",
    }),
    env,
    {},
  );
  assert.equal(verifyGet.status, 405);
});

test("6) success response never contains access code or hash secret", async () => {
  const { env, hash } = await makeEnv();
  const res = await worker.fetch(
    createRequest({
      company_code: "FLX-00020",
      access_code: REVIEW_PLAINTEXT,
    }),
    env,
    {},
  );
  const raw = await res.text();
  assert.equal(res.status, 200);
  assert.equal(raw.includes(REVIEW_PLAINTEXT), false);
  assert.equal(raw.includes(hash), false);
  assert.equal(raw.toLowerCase().includes("play_review_access_code_hash"), false);
});

test("7) missing PLAY_REVIEW_ACCESS_CODE_HASH → fail closed", async () => {
  const { env, bookingKv } = await makeEnv({ includeHash: false });
  const res = await worker.fetch(
    createRequest({
      company_code: "FLX-00020",
      access_code: REVIEW_PLAINTEXT,
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 403);
  assert.equal(j.ok, false);
  assert.equal(sessionKeys(bookingKv).length, 0);
});

test("8) repeated invalid attempts eventually rate-limit", async () => {
  const { env, bookingKv } = await makeEnv();
  let lastStatus = 0;
  for (let i = 0; i < 12; i++) {
    const res = await worker.fetch(
      createRequest({
        company_code: "FLX-00020",
        access_code: `wrong-access-code-xxxxx-${i}`,
      }),
      env,
      {},
    );
    lastStatus = res.status;
    const j = await res.json();
    assert.equal(j.ok, false);
    assert.equal(j.error, "verification_failed");
  }
  assert.equal(lastStatus, 403);
  assert.equal(sessionKeys(bookingKv).length, 0);
  const rateKeys = [...bookingKv.store.keys()].filter((k) =>
    String(k).startsWith("company_review_access:rate:"),
  );
  assert.ok(rateKeys.length >= 1);
  // After max failures, even the correct credential must stay denied in-window.
  const blocked = await worker.fetch(
    createRequest({
      company_code: "FLX-00020",
      access_code: REVIEW_PLAINTEXT,
    }),
    env,
    {},
  );
  const blockedJson = await blocked.json();
  assert.equal(blocked.status, 403);
  assert.equal(blockedJson.ok, false);
  assert.equal(sessionKeys(bookingKv).length, 0);
});

test("9) malformed body / invalid company code fail safely", async () => {
  const { env, bookingKv } = await makeEnv();
  const cases = [
    null,
    {},
    { company_code: "NOT-A-CODE", access_code: REVIEW_PLAINTEXT },
    { company_code: "FLX-00020", access_code: "short" },
    { company_code: "FLX-00020", access_code: "has whitespace code!!" },
  ];
  for (const body of cases) {
    const res = await worker.fetch(
      body === null
        ? new Request(`https://booking.internal${ROUTE_PATH}`, {
            method: "POST",
            headers: { "content-type": "application/json" },
            body: "null",
          })
        : createRequest(body),
      env,
      {},
    );
    const j = await res.json();
    assert.equal(res.status, 403);
    assert.equal(j.ok, false);
    assert.equal(j.error, "verification_failed");
  }
  assert.equal(sessionKeys(bookingKv).length, 0);
});

test("misconfigured PLAY_REVIEW_COMPANY_CODE fails closed", async () => {
  const { env, bookingKv } = await makeEnv({ companyCodeVar: "FLX-00021" });
  const res = await worker.fetch(
    createRequest({
      company_code: "FLX-00020",
      access_code: REVIEW_PLAINTEXT,
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 403);
  assert.equal(j.ok, false);
  assert.equal(sessionKeys(bookingKv).length, 0);
});

test("GET review-access/verify → 405", async () => {
  const { env } = await makeEnv();
  const res = await worker.fetch(
    new Request(`https://booking.internal${ROUTE_PATH}`, { method: "GET" }),
    env,
    {},
  );
  assert.equal(res.status, 405);
});
