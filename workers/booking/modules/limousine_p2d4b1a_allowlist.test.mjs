// P2D4B1A — fail-closed limousine test-company allowlist.
// Run: node --test workers/booking/modules/limousine_p2d4b1a_allowlist.test.mjs
//
// No deploy, no production KV, no provider call.

import test from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import {
  LIMOUSINE_TEST_COMPANY_ALLOWLIST_ENV,
  LIMOUSINE_TEST_COMPANY_ALLOWLIST_MAX_CHARS,
  LIMOUSINE_TEST_COMPANY_ALLOWLIST_MAX_ENTRIES,
  canonicalizeLimousineTestCompanyId,
  isLimousineTestCompanyAllowlisted,
  isTrustedLimousineTestCompany,
  limousineTestCompanyAllowlistConfigured,
  parseLimousineTestCompanyAllowlist,
} from "./limousine_test_company_allowlist.mjs";
import {
  executeLimousineStatusRead,
} from "./limousine_quote_inbox.mjs";
import {
  LIMOUSINE_ACCEPTANCE_ERRORS,
  unsealLimousineAcceptance,
} from "./limousine_acceptance_token.mjs";
import {
  limousineBookGateEnabled,
} from "./limousine_booking.mjs";
import {
  limousineManualQuoteGateEnabled,
} from "./limousine_manual_quote.mjs";
import {
  limousineQuoteGateEnabled,
} from "./limousine_pricing_resolver.mjs";
import { BILLIT_OUTBOX_DUE_PREFIX } from "./billit_outbox_due_index.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const worker = readFileSync(join(__dirname, "..", "fluxidi_booking_worker.js"), "utf8");
const wrangler = readFileSync(join(__dirname, "..", "wrangler.toml"), "utf8");
const dueIndex = readFileSync(join(__dirname, "billit_outbox_due_index.js"), "utf8");

const ALLOWED = "fluxidi_internal_limo_a";
const OTHER = "fluxidi_internal_limo_b";

function countingKV(seed = {}) {
  const store = new Map();
  const counts = { get: 0, put: 0, delete: 0, list: 0 };
  const reads = [];
  const writes = [];
  const lists = [];
  for (const [k, v] of Object.entries(seed)) {
    store.set(k, typeof v === "string" ? v : JSON.stringify(v));
  }
  return {
    counts,
    reads,
    writes,
    lists,
    store,
    async get(key, opts) {
      counts.get += 1;
      reads.push(key);
      const raw = store.get(key);
      if (raw == null) return null;
      const type = typeof opts === "string" ? opts : opts?.type;
      if (type === "json") {
        try {
          return typeof raw === "string" ? JSON.parse(raw) : raw;
        } catch (_) {
          return null;
        }
      }
      return raw;
    },
    async put(key, value) {
      counts.put += 1;
      writes.push(key);
      store.set(key, typeof value === "string" ? value : JSON.stringify(value));
    },
    async delete(key) {
      counts.delete += 1;
      store.delete(key);
    },
    async list({ prefix = "" } = {}) {
      counts.list += 1;
      lists.push(prefix);
      const keys = [...store.keys()].filter((k) => k.startsWith(prefix));
      return { keys: keys.map((name) => ({ name })), list_complete: true };
    },
  };
}

test("1) undefined allowlist denies every company", () => {
  assert.deepEqual(parseLimousineTestCompanyAllowlist(undefined), []);
  assert.equal(isLimousineTestCompanyAllowlisted(undefined, ALLOWED), false);
  assert.equal(isTrustedLimousineTestCompany({}, ALLOWED), false);
  assert.equal(isTrustedLimousineTestCompany(null, ALLOWED), false);
  assert.equal(limousineTestCompanyAllowlistConfigured(undefined), false);
});

test("2) empty and whitespace allowlists deny", () => {
  assert.deepEqual(parseLimousineTestCompanyAllowlist(""), []);
  assert.deepEqual(parseLimousineTestCompanyAllowlist("   \n\t  "), []);
  assert.equal(isLimousineTestCompanyAllowlisted("   ", ALLOWED), false);
});

test("3) malformed and oversized allowlists fail closed", () => {
  assert.deepEqual(parseLimousineTestCompanyAllowlist({ company: ALLOWED }), []);
  assert.deepEqual(
    parseLimousineTestCompanyAllowlist("x".repeat(LIMOUSINE_TEST_COMPANY_ALLOWLIST_MAX_CHARS + 1)),
    [],
  );
  const tooMany = Array.from(
    { length: LIMOUSINE_TEST_COMPANY_ALLOWLIST_MAX_ENTRIES + 1 },
    (_, i) => `company_${i}`,
  ).join(",");
  assert.deepEqual(parseLimousineTestCompanyAllowlist(tooMany), []);
});

test("4/5) one allowed company succeeds; a second is denied in the same process", () => {
  const raw = ALLOWED;
  assert.equal(isLimousineTestCompanyAllowlisted(raw, ALLOWED), true);
  assert.equal(isLimousineTestCompanyAllowlisted(raw, OTHER), false);
  assert.equal(
    isTrustedLimousineTestCompany({ [LIMOUSINE_TEST_COMPANY_ALLOWLIST_ENV]: raw }, ALLOWED),
    true,
  );
  assert.equal(
    isTrustedLimousineTestCompany({ [LIMOUSINE_TEST_COMPANY_ALLOWLIST_ENV]: raw }, OTHER),
    false,
  );
});

test("6) comma and whitespace parsing", () => {
  assert.deepEqual(
    parseLimousineTestCompanyAllowlist(` ${ALLOWED},\n${OTHER}  ${ALLOWED} `),
    [ALLOWED, OTHER],
  );
  assert.deepEqual(
    parseLimousineTestCompanyAllowlist(`${ALLOWED} ${OTHER}`),
    [ALLOWED, OTHER],
  );
});

test("7) deduplication", () => {
  assert.deepEqual(
    parseLimousineTestCompanyAllowlist(`${ALLOWED},${ALLOWED} ${ALLOWED}`),
    [ALLOWED],
  );
});

test("8) no wildcard accepted", () => {
  assert.deepEqual(parseLimousineTestCompanyAllowlist("*"), []);
  assert.deepEqual(parseLimousineTestCompanyAllowlist("all"), []);
  assert.deepEqual(parseLimousineTestCompanyAllowlist("true"), []);
  assert.deepEqual(parseLimousineTestCompanyAllowlist(`${ALLOWED},*`), []);
  assert.equal(isLimousineTestCompanyAllowlisted("*", ALLOWED), false);
});

test("9) canonical normalization matches company-ID rules", () => {
  const padded = `  ${ALLOWED}  `;
  assert.equal(canonicalizeLimousineTestCompanyId(padded), ALLOWED);
  assert.equal(isLimousineTestCompanyAllowlisted(padded, ` ${ALLOWED} `), true);
  assert.equal(
    canonicalizeLimousineTestCompanyId("x".repeat(120)).length,
    80,
  );
});

test("10/12) Worker uses resolved public partner or session, never client company alone", () => {
  assert.ok(worker.includes("routedPublicPartner?.ok"));
  assert.ok(worker.includes("routedPublicPartner.company_id"));
  assert.ok(worker.includes("_loadCompanySessionFromRequest(request, env)"));
  assert.ok(worker.includes('tenant_resolution_mode === "trusted_route"'));
  assert.ok(!worker.includes("_limousineTestCompanyAllowlisted(env, body.company_id)"));
  assert.ok(!worker.includes("_limousineTestCompanyAllowlisted(env, payload.company_id)"));
});

test("11) tenant/company mismatch is denied on session-backed create", () => {
  assert.ok(worker.includes("sessionCompany !== sanitizeTenantString(scope.company_id, 80)"));
  assert.ok(worker.includes("sessionTenant !== sanitizeTenantString(scope.tenant_id, 80)"));
});

test("13) token binding mismatch denied before record hydration when hook is set", async () => {
  const kv = countingKV();
  const result = await executeLimousineStatusRead({
    body: { status_ref: "limqs1.aaaaaaaaaaaaaaa.bbbbbbbbbbbbbbbbbbbb" },
    secret: "x".repeat(32),
    bookingKvPresent: true,
    rateLimit: async () => ({ limited: false }),
    loadRecord: async (id) => {
      kv.counts.get += 1;
      return { quote_request_id: id, company_id: OTHER, tenant_id: "t" };
    },
    persistExpired: async () => {
      kv.counts.put += 1;
    },
    isCompanyAllowlisted: () => false,
  });
  assert.equal(result.body.ok, false);
  assert.equal(result.loaded_record, false);
  assert.equal(kv.counts.get, 0);
  assert.equal(kv.counts.put, 0);
});

test("14) quote/book/manual gates remain independent", () => {
  assert.equal(limousineQuoteGateEnabled("1"), true);
  assert.equal(limousineBookGateEnabled("0"), false);
  assert.equal(limousineManualQuoteGateEnabled(undefined), false);
  assert.ok(worker.includes("function _limousineQuoteGateEnabled(env)"));
  assert.ok(worker.includes("function _limousineBookGateEnabled(env)"));
  assert.ok(worker.includes("function _limousineManualQuoteGateEnabled(env)"));
});

test("15) global gate OFF still wins with the exact existing responses", () => {
  assert.ok(worker.includes('reason: "gate_off"'));
  assert.ok(worker.includes('return { ok: false, error: "limousine_book_disabled" };'));
  assert.ok(worker.includes('error: "manual_quote_gate_off"'));
  const quoteGate = worker.slice(
    worker.indexOf("if (!gateEnabled) {"),
    worker.indexOf("reason: \"gate_off\""),
  );
  assert.ok(!quoteGate.includes("_limousineTestCompanyAllowlisted"));
});

test("16) missing secret still fails closed", async () => {
  const missing = await unsealLimousineAcceptance({
    secret: undefined,
    reference: "limacc1.abcdefghijklmnop.klmnopqrstuvwxyzabcdef",
  });
  assert.equal(missing.ok, false);
  assert.equal(missing.error, LIMOUSINE_ACCEPTANCE_ERRORS.MISSING_SECRET);
  assert.ok(worker.includes("if (!unsealed.ok) return fail(unsealed.error);"));
  assert.ok(worker.includes("secret: env.LIMOUSINE_ACCEPTANCE_SECRET"));
});

test("17/18) showroom fields require allowlist; non-limousine profile fields stay", () => {
  const start = worker.indexOf("booking_capabilities: profile.booking_capabilities,");
  const chunk = worker.slice(start, start + 700);
  assert.ok(chunk.includes("_limousineTestCompanyAllowlisted"));
  assert.ok(chunk.includes("_publicLimousineShowroomFieldsFromStoredProfile(profile)"));
  assert.ok(chunk.includes("_scopeFromCanonicalPublicPartnerId(profile.partner_id)"));
  assert.ok(worker.includes("company_name: profile.company_name"));
  assert.ok(worker.includes("public_contact: profile.public_contact"));
});

test("19) nearby does not advertise non-allowlisted limousine", () => {
  assert.ok(worker.includes("return _limousineTestCompanyAllowlisted(env, nearbyCompanyId);"));
  assert.ok(worker.includes("_limousineTestCompanyAllowlisted(env, nearbySignalCompanyId)"));
});

test("20) admin pricing/offer/fleet mutations denied outside allowlist", () => {
  assert.ok(worker.includes("ADMIN_PRICING_LIMOUSINE_GET"));
  assert.ok(worker.includes("ADMIN_PRICING_LIMOUSINE_POST"));
  const pricingGet = worker.slice(
    worker.indexOf("routeLabel: \"ADMIN_PRICING_LIMOUSINE_GET\""),
    worker.indexOf("routeLabel: \"ADMIN_PRICING_LIMOUSINE_POST\""),
  );
  assert.ok(pricingGet.includes("return _limousineAllowlistDenied()"));
  const pricingPost = worker.slice(
    worker.indexOf("routeLabel: \"ADMIN_PRICING_LIMOUSINE_POST\""),
    worker.indexOf("limousine object is required"),
  );
  assert.ok(pricingPost.includes("return _limousineAllowlistDenied()"));
  assert.ok(worker.includes("if (_limousineTestCompanyAllowlisted(env, scope.company_id)) {\n          try {\n            await refreshPartnerLimousineProjection(env, scope);"));
  assert.ok(worker.includes("const _limousinePublishAllowlisted = _limousineTestCompanyAllowlisted"));
});

test("21/22/23) denied status traffic performs zero limousine KV writes, fetch, or list", async () => {
  const outbound = [];
  const originalFetch = global.fetch;
  global.fetch = async (input) => {
    outbound.push(String(input?.url || input));
    throw new Error("blocked");
  };
  try {
    const kv = countingKV();
    const result = await executeLimousineStatusRead({
      body: { status_ref: "limqs1.aaaaaaaaaaaaaaa.bbbbbbbbbbbbbbbbbbbb" },
      secret: "x".repeat(32),
      bookingKvPresent: true,
      rateLimit: async () => ({ limited: false }),
      loadRecord: async () => {
        kv.counts.get += 1;
        return { quote_request_id: "q", company_id: OTHER };
      },
      persistExpired: async () => {
        kv.counts.put += 1;
      },
      isCompanyAllowlisted: (companyId) => isLimousineTestCompanyAllowlisted(ALLOWED, companyId),
    });
    assert.equal(result.body.ok, false);
    assert.equal(result.wrote, false);
    assert.equal(result.loaded_record, false);
    assert.equal(kv.counts.put, 0);
    assert.equal(kv.counts.list, 0);
    assert.deepEqual(outbound, []);
  } finally {
    global.fetch = originalFetch;
  }
});

test("24) no scheduled work added", () => {
  const scheduled = worker.slice(
    worker.indexOf("async scheduled(event, env, ctx)"),
    worker.indexOf("async fetch(request, env, ctx)"),
  );
  assert.ok(!scheduled.includes("LIMOUSINE_TEST_COMPANY_ALLOWLIST"));
  assert.ok(!scheduled.includes("limousine_quote_record"));
  assert.ok(!scheduled.includes("_limousineTestCompanyAllowlisted"));
});

test("25) no taxi fallback introduced", () => {
  const quoteEarly = worker.slice(
    worker.indexOf("_isLimousineQuoteRequestEarly"),
    worker.indexOf("const pricingProfile = await _loadTenantPricingProfile(env, quoteScope);"),
  );
  assert.ok(!quoteEarly.includes("calcPrice("));
  assert.ok(worker.includes("if (_limousineAccepted) {\n      ret.enabled = false;\n    }"));
});

test("26) nothing marked paid by the allowlist path", () => {
  assert.ok(!worker.includes("payment_status: \"paid\"") || worker.includes("if (!requiresPayment) payload.__mollie_paid = true;"));
  const allowFn = worker.slice(
    worker.indexOf("function _limousineTestCompanyAllowlisted"),
    worker.indexOf("function _limousineQuoteRecordKey"),
  );
  assert.ok(!allowFn.includes("paid"));
  assert.ok(!allowFn.includes("mollie"));
});

test("27) companies cannot observe each other's inbox/status (scoped + allowlist)", () => {
  assert.ok(worker.includes("if (!_limousineQuoteScopeMatches(record, scope))"));
  assert.ok(worker.includes("isCompanyAllowlisted: (companyId) => _limousineTestCompanyAllowlisted(env, companyId)"));
  assert.ok(worker.includes("if (!_limousineTestCompanyAllowlisted(env, record.company_id))"));
});

test("28) Billit and RateHawk coexistence unchanged", () => {
  assert.equal(BILLIT_OUTBOX_DUE_PREFIX, "billit_outbox_due:v1:");
  assert.ok(worker.includes("processBillitDueOutboxIndex"));
  assert.ok(worker.includes("runBillitOutboxDueMigrationStep"));
  assert.ok(wrangler.includes('binding = "RATEHAWK_HOTELS"'));
  assert.ok(wrangler.includes('RATEHAWK_TEST_PREBOOK_ENABLED = "0"'));
  assert.ok(!wrangler.includes("LIMOUSINE_TEST_COMPANY_ALLOWLIST"));
  assert.ok(!wrangler.includes("LIMOUSINE_QUOTE_ENABLED"));
  assert.equal(
    createHash("sha256").update(wrangler, "utf8").digest("hex").toUpperCase(),
    "4EDD8061662826214286A0A3F537EE19A07C248A18F3691252DA9B54DD219DA9",
  );
  assert.equal(
    createHash("sha256").update(dueIndex, "utf8").digest("hex").toUpperCase(),
    "1BB6B1C45268525627D0971AC956B3E30A733229580146459D6454DED735CF17",
  );
});

test("refreshPartnerLimousineProjection is local and skips KV when not allowlisted", () => {
  const start = worker.indexOf("async function refreshPartnerLimousineProjection");
  const body = worker.slice(start, start + 500);
  assert.ok(body.includes("if (!_limousineTestCompanyAllowlisted(env, scope?.company_id"));
  assert.ok(body.indexOf("_limousineTestCompanyAllowlisted") < body.indexOf("if (!env?.BOOKING_KV)"));
});

test("wrangler remains free of limousine gates and secrets", () => {
  assert.ok(!wrangler.includes("LIMOUSINE_"));
  assert.ok(!worker.includes("LIMOUSINE_TEST_COMPANY_ALLOWLIST ="));
  assert.ok(!worker.includes("LIMOUSINE_ACCEPTANCE_SECRET ="));
});

function quoteEnv(env) {
  return {
    fetch: async (input) => {
      throw new Error(`blocked outbound ${input?.url || input}`);
    },
    ...env,
  };
}

test("fetch: gate ON + undefined allowlist denies /quote with zero fetch and zero writes", async () => {
  const { default: bookingWorker } = await import("../fluxidi_booking_worker.js");
  const kv = countingKV();
  const outbound = [];
  const originalFetch = global.fetch;
  global.fetch = async (input) => {
    outbound.push(String(input?.url || input));
    throw new Error("blocked");
  };
  try {
    const res = await bookingWorker.fetch(
      new Request("https://booking.internal/quote", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          from: "Gent",
          to: "Brussel",
          date: "2026-09-01",
          time: "10:00",
          service_category: "limousine",
          tenant_id: "tenant_a",
          company_id: ALLOWED,
        }),
      }),
      quoteEnv({
        BOOKING_KV: kv,
        LIMOUSINE_QUOTE_ENABLED: "1",
      }),
      {},
    );
    const json = await res.json();
    assert.equal(json.ok, true);
    assert.equal(json.service_category, "limousine");
    assert.equal(json.limousine?.unavailable, true);
    assert.equal(json.limousine?.reason, "unavailable");
    assert.notEqual(json.limousine?.reason, "gate_off");
    assert.equal(kv.counts.put, 0);
    assert.equal(kv.counts.list, 0);
    assert.deepEqual(outbound, []);
  } finally {
    global.fetch = originalFetch;
  }
});

test("fetch: client-supplied allowed company cannot authorize a different public partner", async () => {
  const { default: bookingWorker } = await import("../fluxidi_booking_worker.js");
  const partnerId = `company:tenant_a:${OTHER}`;
  const kv = countingKV({
    "public:partners:booking-routes:v2": {
      routes: [
        {
          partner_id: partnerId,
          tenant_id: "tenant_a",
          company_id: OTHER,
          is_active: true,
          subscription_status: "active",
        },
      ],
    },
  });
  const outbound = [];
  const originalFetch = global.fetch;
  global.fetch = async (input) => {
    outbound.push(String(input?.url || input));
    throw new Error("blocked");
  };
  try {
    const res = await bookingWorker.fetch(
      new Request("https://booking.internal/quote", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          from: "Gent",
          to: "Brussel",
          date: "2026-09-01",
          time: "10:00",
          service_category: "limousine",
          public_partner_id: partnerId,
          tenant_id: "tenant_a",
          company_id: ALLOWED,
        }),
      }),
      quoteEnv({
        BOOKING_KV: kv,
        LIMOUSINE_QUOTE_ENABLED: "1",
        LIMOUSINE_TEST_COMPANY_ALLOWLIST: ALLOWED,
      }),
      {},
    );
    const json = await res.json();
    assert.equal(json.limousine?.unavailable, true);
    assert.equal(json.limousine?.reason, "unavailable");
    assert.equal(kv.counts.put, 0);
    assert.deepEqual(outbound, []);
  } finally {
    global.fetch = originalFetch;
  }
});

