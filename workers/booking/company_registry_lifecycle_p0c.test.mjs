import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import worker from "./fluxidi_booking_worker.js";
import {
  COMPANY_REGISTRY_MANIFEST_KEY,
  registryCodeKey,
  registryPageKey,
} from "./modules/company_registry_index.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const WORKER_SRC = readFileSync(join(HERE, "fluxidi_booking_worker.js"), "utf8");
const WRITER_SRC = readFileSync(join(HERE, "modules/company_registry_index.mjs"), "utf8");
const WRANGLER_SRC = readFileSync(join(HERE, "wrangler.toml"), "utf8");
const CHECKOUT_SRC = readFileSync(join(HERE, "modules/street_mollie_checkout.js"), "utf8");
const LIST_SRC = readFileSync(join(HERE, "modules/booking_list_projection.js"), "utf8");
const P0C_SRC = [WORKER_SRC, CHECKOUT_SRC, LIST_SRC].join("\n");

const ADMIN = "test-admin-token";
const TENANT = "tenant_registry_p0c";
const COMPANY = "company_registry_p0c";

async function sha256Hex(text) {
  const data = new TextEncoder().encode(String(text || ""));
  const digest = await crypto.subtle.digest("SHA-256", data);
  const bytes = new Uint8Array(digest);
  let hex = "";
  for (const byte of bytes) hex += byte.toString(16).padStart(2, "0");
  return hex;
}

function makeCountingKv(seed = {}) {
  const store = new Map(Object.entries(seed));
  const ops = { gets: [], puts: [], lists: [], deletes: [] };
  return {
    store,
    ops,
    async get(key, opts) {
      ops.gets.push(key);
      if (!store.has(key)) return null;
      const raw = store.get(key);
      if (opts && opts.type === "json") {
        try {
          return typeof raw === "string" ? JSON.parse(raw) : raw;
        } catch {
          return null;
        }
      }
      return raw;
    },
    async put(key, val) {
      ops.puts.push(key);
      store.set(key, val);
    },
    async delete(key) {
      ops.deletes.push(key);
      store.delete(key);
    },
    async list() {
      ops.lists.push("*");
      return {
        keys: [...store.keys()].map((name) => ({ name })),
        list_complete: true,
      };
    },
  };
}

function envWith(kv, extra = {}) {
  return {
    ADMIN_TOKEN: ADMIN,
    BOOKING_KV: kv,
    PLAY_REVIEW_COMPANY_CODE: "FLX-00020",
    ...extra,
  };
}

function snapshotOps(kv) {
  return {
    gets: kv.ops.gets.length,
    puts: kv.ops.puts.length,
    lists: kv.ops.lists.length,
  };
}

function registryOpsSince(kv, before) {
  const gets = kv.ops.gets.slice(before.gets);
  const puts = kv.ops.puts.slice(before.puts);
  const lists = kv.ops.lists.slice(before.lists);
  return {
    code_gets: gets.filter((key) => key.startsWith("company_registry:code:")).length,
    code_puts: puts.filter((key) => key.startsWith("company_registry:code:")).length,
    page_gets: gets.filter((key) => key.startsWith("company_registry:page:")).length,
    page_puts: puts.filter((key) => key.startsWith("company_registry:page:")).length,
    manifest_gets: gets.filter((key) => key === COMPANY_REGISTRY_MANIFEST_KEY).length,
    manifest_puts: puts.filter((key) => key === COMPANY_REGISTRY_MANIFEST_KEY).length,
    list_ops: lists.length,
    writes:
      puts.filter((key) => String(key).startsWith("company_registry:")).length,
  };
}

function seedCompanyLink({
  tenantId = TENANT,
  companyId = COMPANY,
  companyCode = "FLX-00022",
  displayName = "Orphan Co",
  source = "auto_generated",
} = {}) {
  const record = {
    tenant_id: tenantId,
    company_id: companyId,
    company_code: companyCode,
    companyCode,
    display_name: displayName,
    linking_enabled: true,
    source,
  };
  return {
    codeKey: `company_link:index:code:${companyCode}:v1`,
    scopeKey: `company_link:index:scope:${tenantId}:${companyId}:v1`,
    record,
  };
}

async function seedCompanySession(kv, {
  tokenValue,
  tenantId = TENANT,
  companyId = COMPANY,
  companyCode = "",
} = {}) {
  const hash = await sha256Hex(tokenValue);
  const key = `company_admin:session:${hash}:v1`;
  kv.store.set(key, JSON.stringify({
    role: "company_admin",
    tenant_id: tenantId,
    company_id: companyId,
    company_code: companyCode,
    expires_at: new Date(Date.now() + 3600_000).toISOString(),
  }));
  return key;
}

function pageMembership(kv, code) {
  const raw = kv.store.get(registryPageKey(1));
  if (!raw) return [];
  const parsed = typeof raw === "string" ? JSON.parse(raw) : raw;
  return (parsed.companies || []).filter((row) => row.company_code === code);
}

function manifestTotal(kv) {
  const raw = kv.store.get(COMPANY_REGISTRY_MANIFEST_KEY);
  if (!raw) return 0;
  const parsed = typeof raw === "string" ? JSON.parse(raw) : raw;
  return Number(parsed.total || 0);
}

async function jsonFetch(path, {
  method = "GET",
  env,
  body = null,
  headers = {},
} = {}) {
  const request = new Request(`https://booking.test${path}`, {
    method,
    headers: {
      ...(body ? { "content-type": "application/json" } : {}),
      ...headers,
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const response = await worker.fetch(request, env, {});
  const text = await response.text();
  let parsed = null;
  try {
    parsed = JSON.parse(text);
  } catch {
    parsed = { raw: text };
  }
  return { status: response.status, body: parsed };
}

test("auto_generated creation via admin profile gets canonical registry membership", async () => {
  const kv = makeCountingKv();
  const env = envWith(kv);
  const before = snapshotOps(kv);
  const result = await jsonFetch(
    `/admin/business/profile?tenant_id=${TENANT}&company_id=${COMPANY}`,
    {
      env,
      headers: { "x-admin-token": ADMIN },
    },
  );
  assert.equal(result.status, 200);
  assert.equal(result.body.ok, true);
  assert.equal(result.body.registry_sync_pending, false);
  const code = result.body.company_code;
  assert.match(code, /^FLX-\d+$/);
  assert.equal(kv.store.has(registryCodeKey(code)), true);
  assert.equal(pageMembership(kv, code).length, 1);
  assert.equal(manifestTotal(kv), 1);
  const ops = registryOpsSince(kv, before);
  assert.equal(ops.list_ops, 0);
  assert.ok(ops.code_puts >= 1);
});

test("public registration immediately receives canonical registry membership", async () => {
  const kv = makeCountingKv();
  const env = envWith(kv);
  const result = await jsonFetch("/public/company/register", {
    method: "POST",
    env,
    body: { company_name: "Public Registry Co", country: "BE" },
  });
  assert.equal(result.status, 200, JSON.stringify(result.body));
  assert.equal(result.body.ok, true);
  assert.equal(result.body.registry_sync_pending, false);
  const code = result.body.company_code;
  assert.match(code, /^FLX-\d+$/);
  assert.equal(pageMembership(kv, code).length, 1);
  assert.equal(kv.store.has(registryCodeKey(code)), true);
});

test("bootstrap with a new code writes registry membership", async () => {
  const kv = makeCountingKv();
  await seedCompanySession(kv, { tokenValue: "cst_new_code", companyCode: "" });
  const result = await jsonFetch("/company/bootstrap", {
    env: envWith(kv),
    headers: { authorization: "Bearer cst_new_code" },
  });
  assert.equal(result.status, 200, JSON.stringify(result.body));
  assert.equal(result.body.ok, true);
  assert.equal(result.body.registry_sync_pending, false);
  const code = result.body.company_code;
  assert.match(code, /^FLX-\d+$/);
  assert.equal(pageMembership(kv, code).length, 1);
});

test("bootstrap SKIP_PRESENT repairs an orphan without creating a second page slot", async () => {
  const kv = makeCountingKv();
  const link = seedCompanyLink({ companyCode: "FLX-00022", source: "auto_generated" });
  kv.store.set(link.codeKey, JSON.stringify(link.record));
  kv.store.set(link.scopeKey, JSON.stringify(link.record));
  await seedCompanySession(kv, {
    tokenValue: "cst_skip_present",
    companyCode: "FLX-00022",
  });
  const first = await jsonFetch("/company/bootstrap", {
    env: envWith(kv),
    headers: { authorization: "Bearer cst_skip_present" },
  });
  assert.equal(first.status, 200, JSON.stringify(first.body));
  assert.equal(first.body.registry_sync_pending, false);
  assert.equal(first.body.company_code, "FLX-00022");
  assert.equal(kv.store.has(registryCodeKey("FLX-00022")), true);
  assert.equal(pageMembership(kv, "FLX-00022").length, 1);
  assert.equal(manifestTotal(kv), 1);
  const beforeReplay = snapshotOps(kv);
  const replay = await jsonFetch("/company/bootstrap", {
    env: envWith(kv),
    headers: { authorization: "Bearer cst_skip_present" },
  });
  assert.equal(replay.body.registry_sync_pending, false);
  const ops = registryOpsSince(kv, beforeReplay);
  assert.equal(ops.code_gets, 1);
  assert.equal(ops.writes, 0);
  assert.equal(ops.page_gets, 0);
  assert.equal(ops.manifest_gets, 0);
  assert.equal(pageMembership(kv, "FLX-00022").length, 1);
  assert.equal(manifestTotal(kv), 1);
});

test("link verification repairs an orphan exactly once", async () => {
  const kv = makeCountingKv();
  const code = "FLX-00022";
  const pairing = "123456";
  const challengeId = "linkchal001";
  const link = seedCompanyLink({ companyCode: code });
  kv.store.set(link.codeKey, JSON.stringify(link.record));
  kv.store.set(link.scopeKey, JSON.stringify(link.record));
  const pairingHash = await sha256Hex(`${code}:${pairing}`);
  kv.store.set(
    `company_link:admin_pairing:challenge:${challengeId}:v1`,
    JSON.stringify({
      challenge_id: challengeId,
      company_code: code,
      tenant_id: TENANT,
      company_id: COMPANY,
      pairing_code_hash: pairingHash,
      attempts: 0,
      max_attempts: 5,
      expires_at: new Date(Date.now() + 600_000).toISOString(),
    }),
  );
  kv.store.set(
    `company_link:admin_pairing:active:${code}:v1`,
    JSON.stringify({ challenge_id: challengeId }),
  );
  const result = await jsonFetch("/public/company/link/verify", {
    method: "POST",
    env: envWith(kv),
    body: { company_code: code, pairing_code: pairing },
  });
  assert.equal(result.status, 200, JSON.stringify(result.body));
  assert.equal(result.body.registry_sync_pending, false);
  assert.equal(pageMembership(kv, code).length, 1);
  assert.equal(kv.store.has(registryCodeKey(code)), true);
});

test("recovery verification repairs an orphan exactly once", async () => {
  const kv = makeCountingKv();
  const code = "FLX-00022";
  const email = "owner@example.com";
  const otp = "654321";
  const challengeId = "recvchal001";
  const link = seedCompanyLink({ companyCode: code });
  kv.store.set(link.codeKey, JSON.stringify(link.record));
  kv.store.set(link.scopeKey, JSON.stringify(link.record));
  kv.store.set(
    `tenant:${TENANT}:company:${COMPANY}:business_profile:v1`,
    JSON.stringify({
      companyName: "Orphan Co",
      email,
      companyEmail: email,
    }),
  );
  const emailHash = await sha256Hex(email);
  const otpHash = await sha256Hex(`${challengeId}:${code}:${email}:${otp}`);
  kv.store.set(
    `company_recovery:challenge:${challengeId}:v1`,
    JSON.stringify({
      challenge_id: challengeId,
      company_code: code,
      tenant_id: TENANT,
      company_id: COMPANY,
      email_hash: emailHash,
      otp_hash: otpHash,
      attempts: 0,
      max_attempts: 5,
      expires_at: new Date(Date.now() + 600_000).toISOString(),
    }),
  );
  const result = await jsonFetch("/public/company/recovery/verify", {
    method: "POST",
    env: envWith(kv),
    body: {
      challenge_id: challengeId,
      company_code: code,
      email,
      otp,
    },
  });
  assert.equal(result.status, 200, JSON.stringify(result.body));
  assert.equal(result.body.registry_sync_pending, false);
  assert.equal(pageMembership(kv, code).length, 1);
});

test("admin profile repairs an existing orphan", async () => {
  const kv = makeCountingKv();
  const link = seedCompanyLink({ companyCode: "FLX-00022" });
  kv.store.set(link.codeKey, JSON.stringify(link.record));
  kv.store.set(link.scopeKey, JSON.stringify(link.record));
  const result = await jsonFetch(
    `/admin/business/profile?tenant_id=${TENANT}&company_id=${COMPANY}`,
    {
      env: envWith(kv),
      headers: { "x-admin-token": ADMIN },
    },
  );
  assert.equal(result.status, 200, JSON.stringify(result.body));
  assert.equal(result.body.company_code, "FLX-00022");
  assert.equal(result.body.registry_sync_pending, false);
  assert.equal(pageMembership(kv, "FLX-00022").length, 1);
});

test("ok:false leaves registry_sync_pending and the next action retries only that company", async () => {
  const kv = makeCountingKv();
  const link = seedCompanyLink({ companyCode: "FLX-00022" });
  kv.store.set(link.codeKey, JSON.stringify(link.record));
  kv.store.set(link.scopeKey, JSON.stringify(link.record));
  await seedCompanySession(kv, {
    tokenValue: "cst_pending",
    companyCode: "FLX-00022",
  });
  const originalGet = kv.get.bind(kv);
  let poison = true;
  kv.get = async (key, opts) => {
    if (poison && key === COMPANY_REGISTRY_MANIFEST_KEY) {
      return {
        schema_version: 1,
        membership_generation: 0,
        page_count: 0,
        page_size: 100,
        total: 0,
        write_token: "stale",
      };
    }
    return originalGet(key, opts);
  };
  const failed = await jsonFetch("/company/bootstrap", {
    env: envWith(kv),
    headers: { authorization: "Bearer cst_pending" },
  });
  assert.equal(failed.status, 200);
  assert.equal(failed.body.ok, true);
  assert.equal(failed.body.company_code, "FLX-00022");
  assert.equal(failed.body.registry_sync_pending, true);
  assert.equal(kv.store.has(registryCodeKey("FLX-00022")), false);
  poison = false;
  const retried = await jsonFetch("/company/bootstrap", {
    env: envWith(kv),
    headers: { authorization: "Bearer cst_pending" },
  });
  assert.equal(retried.body.registry_sync_pending, false);
  assert.equal(pageMembership(kv, "FLX-00022").length, 1);
  assert.equal(manifestTotal(kv), 1);
});

test("thrown registry write is pending and retries that company only", async () => {
  const kv = makeCountingKv();
  const link = seedCompanyLink({ companyCode: "FLX-00022" });
  kv.store.set(link.codeKey, JSON.stringify(link.record));
  kv.store.set(link.scopeKey, JSON.stringify(link.record));
  await seedCompanySession(kv, {
    tokenValue: "cst_throw",
    companyCode: "FLX-00022",
  });
  const originalPut = kv.put.bind(kv);
  let throwOnce = true;
  kv.put = async (key, val) => {
    if (throwOnce && String(key).startsWith("company_registry:page:")) {
      throwOnce = false;
      throw new Error("simulated_page_write_failure");
    }
    return originalPut(key, val);
  };
  const failed = await jsonFetch("/company/bootstrap", {
    env: envWith(kv),
    headers: { authorization: "Bearer cst_throw" },
  });
  assert.equal(failed.body.ok, true);
  assert.equal(failed.body.registry_sync_pending, true);
  assert.equal(failed.body.registry_sync_error, "registry_sync_threw");
  const retried = await jsonFetch("/company/bootstrap", {
    env: envWith(kv),
    headers: { authorization: "Bearer cst_throw" },
  });
  assert.equal(retried.body.registry_sync_pending, false);
  assert.equal(pageMembership(kv, "FLX-00022").length, 1);
});

test("sanitized logging never includes tenant ids, emails, tokens or complete KV values", () => {
  const syncFn = WORKER_SRC.slice(
    WORKER_SRC.indexOf("async function _syncCompanyRegistryMembership"),
    WORKER_SRC.indexOf("function _normalizeCompanyLinkIndexSource"),
  );
  assert.match(syncFn, /COMPANY_REGISTRY\]\[SYNC\]\[PENDING\]/);
  assert.match(syncFn, /_maskPublicDriverLoginValue/);
  assert.doesNotMatch(syncFn, /tenant_id\}|company_id\}/);
  assert.doesNotMatch(syncFn, /JSON\.stringify\(entry\)|complete KV|BOOKING_KV\.get/);
  assert.doesNotMatch(syncFn, /email|token|Bearer/);
});

test("worker wiring covers required lifecycle holes and forbids global repair", () => {
  assert.match(WORKER_SRC, /_syncCompanyRegistryMembership/);
  assert.match(WORKER_SRC, /\[COMPANY_CODE_ENSURE\]\[SKIP_PRESENT\][\s\S]{0,400}_syncCompanyRegistryMembership/);
  assert.match(WORKER_SRC, /handlePublicCompanyLinkVerify[\s\S]*_syncCompanyRegistryMembership/);
  assert.match(WORKER_SRC, /handlePublicCompanyRecoveryVerify[\s\S]*_syncCompanyRegistryMembership/);
  assert.match(WORKER_SRC, /_upsertCompanyCodeIndexesForScope[\s\S]*_syncCompanyRegistryMembership/);
  assert.doesNotMatch(WORKER_SRC, /discoverExistingCompanies|applyBackfillBatch/);
  assert.doesNotMatch(WRITER_SRC, /\.list\s*\(/);
  assert.doesNotMatch(WRANGLER_SRC, /crons\s*=\s*\[[^\]\n]*\*\/\d/);
  assert.match(WRANGLER_SRC, /crons\s*=\s*\[\s*\]/);
  assert.match(P0C_SRC, /isPlannedConsumerCheckoutRecord/);
  assert.match(P0C_SRC, /next_cursor/);
  assert.match(P0C_SRC, /pageCache|cache\.pages|pageStoreKey/);
  assert.match(P0C_SRC, /billit/i);
  assert.match(P0C_SRC, /chiron/i);
  assert.match(P0C_SRC, /mollie/i);
  assert.match(P0C_SRC, /company_session/);
});

test("current P0C payment, document and auth surfaces remain present", () => {
  assert.match(P0C_SRC, /planning_reference/);
  assert.match(P0C_SRC, /planningReference/);
  assert.match(P0C_SRC, /ride_kind/);
  assert.match(P0C_SRC, /isPlannedConsumerCheckoutRecord/);
  assert.match(P0C_SRC, /street_mollie|createStreetMollie|mollie/i);
  assert.match(P0C_SRC, /invoice_pdf|PDFSHIFT|pdf_pending/);
  assert.match(WORKER_SRC, /\/company\/bootstrap/);
  assert.match(WORKER_SRC, /\/public\/company\/register/);
  assert.doesNotMatch(WORKER_SRC, /european account deletion|deleteEuropeanAccount/i);
});
