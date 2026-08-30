import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";
import assert from "node:assert/strict";

import worker, { activateFluxidiAddonFromVerifiedPayment } from "../fluxidi_booking_worker.js";
import {
  authorizeAddonCheckout,
  authorizeAddonWebhookActivation,
  buildAddonPendingBillingEvidence,
  effectiveMollieKeyMode,
  parseAddonTestCompanyAllowlist,
  resolveSubscriptionBillingMode,
  testGrantRevenueAudit,
} from "./subscription_addon_test_mode_gate.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const WORKER = readFileSync(join(HERE, "../fluxidi_booking_worker.js"), "utf8");
const TOML = readFileSync(join(HERE, "../wrangler.toml"), "utf8");
const ADMIN = "addon-gate-admin-token";
const WEBHOOK_SECRET = "addon-gate-webhook-secret";

function memoryKv(seed = {}) {
  const store = new Map();
  for (const [key, value] of Object.entries(seed)) {
    store.set(key, typeof value === "string" ? value : JSON.stringify(value));
  }
  return {
    store,
    async get(key, opts) {
      if (!store.has(key)) return null;
      const raw = store.get(key);
      if (opts === "json" || opts?.type === "json") {
        try {
          return typeof raw === "string" ? JSON.parse(raw) : raw;
        } catch {
          return null;
        }
      }
      return raw;
    },
    async put(key, value) {
      store.set(key, value);
    },
    async delete(key) {
      store.delete(key);
    },
  };
}

function activeProfile(extra = {}) {
  return {
    version: 1,
    subscription_status: "active",
    status: "active",
    market: "BE",
    currency: "EUR",
    billing_email: "ops@example.test",
    included_vehicles: 1,
    max_vehicles: 1,
    extra_vehicle_active_quantity: 0,
    extra_driver_active_quantity: 0,
    provider_customer_id: "cst_gate_test",
    public_company_code: extra.public_company_code || extra.company_code || "",
    ...extra,
  };
}

function seedSubscription(kv, tenantId, companyId, profile) {
  const key = `tenant:${tenantId}:company:${companyId}:subscription:v1`;
  kv.store.set(key, JSON.stringify({
    version: 1,
    subscription_profile: activeProfile(profile),
  }));
}

function envFor({
  kv,
  apiKey = "live_dummy_not_a_real_secret",
  mode = "live",
  allowlist = "",
} = {}) {
  return {
    ADMIN_TOKEN: ADMIN,
    BOOKING_KV: kv,
    FLUXIDI_SUBSCRIPTION_MOLLIE_API_KEY: apiKey,
    FLUXIDI_SUBSCRIPTION_WEBHOOK_SECRET: WEBHOOK_SECRET,
    FLUXIDI_SUBSCRIPTION_MOLLIE_MODE: mode,
    FLUXIDI_SUBSCRIPTION_ADDON_TEST_COMPANY_ALLOWLIST: allowlist,
  };
}

function checkoutRequest(tenantId, companyId, body = {}) {
  return new Request(
    `https://booking.internal/company/subscription/add-ons/checkout/start?tenant_id=${tenantId}&company_id=${companyId}`,
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-admin-token": ADMIN,
      },
      body: JSON.stringify({
        tenant_id: tenantId,
        company_id: companyId,
        addon_code: "extra_vehicle",
        quantity: 1,
        ...body,
      }),
    },
  );
}

function pendingRecord({
  tenantId,
  companyId,
  activationId,
  billingMode,
  authorized = false,
  extras = {},
} = {}) {
  return {
    version: 1,
    kind: "addon_activation",
    activation_id: activationId,
    tenant_id: tenantId,
    company_id: companyId,
    addon_code: "extra_vehicle",
    quantity: 1,
    market: "BE",
    currency: "EUR",
    unit_price_cents: 1900,
    expected_amount_cents: 1900,
    billing_model: "addon_activation_v1",
    provider_payment_id: extras.provider_payment_id || "tr_gate_1",
    status: "pending",
    created_at: "2026-08-30T10:00:00.000Z",
    billing_mode: billingMode,
    effective_billing_mode: billingMode,
    test_company_authorized: authorized,
    company_code: extras.company_code || null,
    counts_as_live_revenue: billingMode === "live",
    contributes_mrr: billingMode === "live",
    ...extras,
  };
}

function paidPayment({
  mode,
  activationId,
  tenantId,
  companyId,
  amount = "19.00",
} = {}) {
  return {
    id: "tr_gate_1",
    status: "paid",
    mode,
    amount: { currency: "EUR", value: amount },
    metadata: {
      purpose: "fluxidi_subscription",
      kind: "addon",
      activation_id: activationId,
      tenant_id: tenantId,
      company_id: companyId,
      addon_code: "extra_vehicle",
      quantity: "1",
    },
  };
}

test("test key + ordinary company is denied at checkout", async () => {
  const denied = authorizeAddonCheckout({
    apiKey: "test_dummy_not_a_real_secret",
    declaredMode: "test",
    companyCode: "FLX-00001",
    companyId: "fluxidi_fluxidi_ddmh9g",
    allowlistRaw: "",
    profile: { billing_test_authorized: false },
    displayName: "Fluxidi Wizard Test",
  });
  assert.equal(denied.ok, false);
  assert.equal(denied.error, "addon_test_mode_not_authorized");

  const kv = memoryKv();
  seedSubscription(kv, "t_ord", "c_ord", { public_company_code: "FLX-00001" });
  const res = await worker.fetch(
    checkoutRequest("t_ord", "c_ord"),
    envFor({ kv, apiKey: "test_dummy_not_a_real_secret", mode: "test", allowlist: "" }),
  );
  assert.equal(res.status, 403);
  const body = await res.json();
  assert.equal(body.error, "addon_test_mode_not_authorized");
});

test("test key + explicitly authorized test company is allowed and marked test", async () => {
  const allowed = authorizeAddonCheckout({
    apiKey: "test_dummy_not_a_real_secret",
    declaredMode: "test",
    companyCode: "FLX-88999",
    companyId: "qa_internal",
    allowlistRaw: "FLX-88999",
    profile: {},
  });
  assert.equal(allowed.ok, true);
  assert.equal(allowed.billing_mode, "test");
  assert.equal(allowed.test_company_authorized, true);
  assert.equal(allowed.counts_as_live_revenue, false);
  assert.equal(allowed.contributes_mrr, false);
  const evidence = buildAddonPendingBillingEvidence({
    authorization: allowed,
    companyId: "qa_internal",
    companyCode: "FLX-88999",
    addonCode: "extra_vehicle",
    quantity: 1,
    createdAt: "2026-08-30T12:00:00.000Z",
    activationId: "addon_auth_1",
    providerPaymentId: "tr_auth",
  });
  assert.equal(evidence.billing_mode, "test");
  assert.equal(evidence.counts_as_live_revenue, false);
  assert.equal(Object.hasOwn(evidence, "api_key"), false);
  assert.equal(Object.hasOwn(evidence, "webhook_secret"), false);
  assert.doesNotMatch(JSON.stringify(evidence), /"test_[a-z0-9]{8,}"|"live_[a-z0-9]{8,}"/);

  const kv = memoryKv();
  seedSubscription(kv, "t_qa", "c_qa", { public_company_code: "FLX-88999" });
  const previousFetch = globalThis.fetch;
  globalThis.fetch = async (url) => {
    const href = String(url);
    if (href.includes("/v2/payments") && !href.includes("tr_")) {
      return {
        ok: true,
        status: 201,
        json: async () => ({
          id: "tr_auth_ok",
          mode: "test",
          status: "open",
          _links: { checkout: { href: "https://www.mollie.com/checkout/test" } },
        }),
      };
    }
    throw new Error(`unexpected_fetch:${href}`);
  };
  try {
    const res = await worker.fetch(
      checkoutRequest("t_qa", "c_qa"),
      envFor({
        kv,
        apiKey: "test_dummy_not_a_real_secret",
        mode: "test",
        allowlist: "FLX-88999,c_qa",
      }),
    );
    assert.equal(res.status, 200);
    const pendingRaw = [...kv.store.entries()].find(([key]) =>
      key.startsWith("subscription:addon:pending_activation:"));
    assert.ok(pendingRaw);
    const pending = JSON.parse(pendingRaw[1]);
    assert.equal(pending.billing_mode, "test");
    assert.equal(pending.test_company_authorized, true);
    assert.equal(pending.counts_as_live_revenue, false);
    assert.equal(pending.contributes_mrr, false);
  } finally {
    globalThis.fetch = previousFetch;
  }
});

test("live key + ordinary company + verified paid payment activates normally", async () => {
  const kv = memoryKv();
  seedSubscription(kv, "t_live", "c_live", { public_company_code: "FLX-00003" });
  const activationId = "addon_live_1";
  await kv.put(
    `subscription:addon:pending_activation:${activationId}:v1`,
    JSON.stringify(pendingRecord({
      tenantId: "t_live",
      companyId: "c_live",
      activationId,
      billingMode: "live",
      extras: { company_code: "FLX-00003" },
    })),
  );
  const result = await activateFluxidiAddonFromVerifiedPayment(
    envFor({ kv, apiKey: "live_dummy_not_a_real_secret", mode: "live" }),
    {
      activationId,
      payment: paidPayment({
        mode: "live",
        activationId,
        tenantId: "t_live",
        companyId: "c_live",
      }),
    },
  );
  assert.equal(result.ok, true);
  assert.equal(result.activated, true);
  assert.equal(result.billing_mode, "live");
  assert.equal(result.counts_as_live_revenue, true);
  assert.equal(result.contributes_mrr, true);
  const profile = await kv.get("tenant:t_live:company:c_live:subscription:v1", { type: "json" });
  assert.equal(profile.subscription_profile.extra_vehicle_active_quantity, 1);
});

test("configured and effective mode mismatch fails closed", () => {
  const mismatch = resolveSubscriptionBillingMode({
    apiKey: "live_dummy_not_a_real_secret",
    declaredMode: "test",
  });
  assert.equal(mismatch.ok, false);
  assert.equal(mismatch.error, "mollie_mode_mismatch");
});

test("missing or unrecognized key fails closed", () => {
  assert.equal(effectiveMollieKeyMode("").ok, false);
  assert.equal(effectiveMollieKeyMode("sk_unknown").error, "unrecognized_mollie_key_mode");
  assert.equal(resolveSubscriptionBillingMode({
    apiKey: "",
    declaredMode: "live",
  }).error, "missing_mollie_api_key");
});

test("crafted webhook cannot bypass the checkout gate", async () => {
  const kv = memoryKv();
  seedSubscription(kv, "t_ord", "c_ord", {
    public_company_code: "FLX-00001",
    extra_vehicle_active_quantity: 3,
  });
  const previousFetch = globalThis.fetch;
  globalThis.fetch = async () => ({
    ok: true,
    status: 200,
    json: async () => paidPayment({
      mode: "test",
      activationId: "addon_forged_1",
      tenantId: "t_ord",
      companyId: "c_ord",
    }),
  });
  try {
    const res = await worker.fetch(
      new Request(`https://booking.internal/webhooks/subscription/mollie/${WEBHOOK_SECRET}`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ id: "tr_forged" }),
      }),
      envFor({
        kv,
        apiKey: "test_dummy_not_a_real_secret",
        mode: "test",
        allowlist: "",
      }),
    );
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.ignored, true);
    const profile = await kv.get("tenant:t_ord:company:c_ord:subscription:v1", { type: "json" });
    assert.equal(profile.subscription_profile.extra_vehicle_active_quantity, 3);
  } finally {
    globalThis.fetch = previousFetch;
  }
});

test("legacy test pending for an ordinary company does not activate", async () => {
  const kv = memoryKv();
  seedSubscription(kv, "t_ord", "c_ord", {
    public_company_code: "FLX-00001",
    extra_vehicle_active_quantity: 3,
  });
  const activationId = "addon_legacy_1";
  await kv.put(
    `subscription:addon:pending_activation:${activationId}:v1`,
    JSON.stringify(pendingRecord({
      tenantId: "t_ord",
      companyId: "c_ord",
      activationId,
      billingMode: "",
      extras: { billing_mode: undefined, effective_billing_mode: undefined },
    })),
  );
  const result = await activateFluxidiAddonFromVerifiedPayment(
    envFor({ kv, apiKey: "test_dummy_not_a_real_secret", mode: "test" }),
    {
      activationId,
      payment: paidPayment({
        mode: "test",
        activationId,
        tenantId: "t_ord",
        companyId: "c_ord",
      }),
    },
  );
  assert.equal(result.activated, undefined);
  assert.equal(result.ignored, true);
  assert.equal(result.reason, "legacy_pending_billing_mode_unproven");
  const profile = await kv.get("tenant:t_ord:company:c_ord:subscription:v1", { type: "json" });
  assert.equal(profile.subscription_profile.extra_vehicle_active_quantity, 3);
});

test("repeated webhook increments entitlements exactly once", async () => {
  const kv = memoryKv();
  seedSubscription(kv, "t_live", "c_once", { extra_vehicle_active_quantity: 0 });
  const activationId = "addon_once_1";
  await kv.put(
    `subscription:addon:pending_activation:${activationId}:v1`,
    JSON.stringify(pendingRecord({
      tenantId: "t_live",
      companyId: "c_once",
      activationId,
      billingMode: "live",
    })),
  );
  const env = envFor({ kv, apiKey: "live_dummy_not_a_real_secret", mode: "live" });
  const payment = paidPayment({
    mode: "live",
    activationId,
    tenantId: "t_live",
    companyId: "c_once",
  });
  const first = await activateFluxidiAddonFromVerifiedPayment(env, { activationId, payment });
  const second = await activateFluxidiAddonFromVerifiedPayment(env, { activationId, payment });
  assert.equal(first.activated, true);
  assert.equal(second.idempotent, true);
  const profile = await kv.get("tenant:t_live:company:c_once:subscription:v1", { type: "json" });
  assert.equal(profile.subscription_profile.extra_vehicle_active_quantity, 1);
});

test("test grant never contributes to live revenue or MRR", () => {
  const audit = testGrantRevenueAudit({
    billing_mode: "test",
    counts_as_live_revenue: false,
    contributes_mrr: false,
  });
  assert.equal(audit.counts_as_live_revenue, false);
  assert.equal(audit.contributes_mrr, false);
  const named = authorizeAddonCheckout({
    apiKey: "test_dummy_not_a_real_secret",
    declaredMode: "test",
    companyCode: "FLX-00004",
    companyId: "c_named",
    allowlistRaw: "",
    displayName: "Fluxidi Wizard Test",
  });
  assert.equal(named.ok, false);
  assert.deepEqual(parseAddonTestCompanyAllowlist("Fluxidi Wizard Test, Review Taxi"), []);
});

test("allowlist is empty by default and does not infer names", () => {
  assert.deepEqual(parseAddonTestCompanyAllowlist(""), []);
  assert.deepEqual(parseAddonTestCompanyAllowlist("FLX-88999, qa_internal"), ["FLX-88999", "qa_internal"]);
  const flagged = authorizeAddonCheckout({
    apiKey: "test_dummy_not_a_real_secret",
    declaredMode: "test",
    companyCode: "FLX-00020",
    companyId: "review_co",
    allowlistRaw: "",
    profile: { billing_test_authorized: true },
  });
  assert.equal(flagged.ok, true);
  assert.equal(flagged.test_company_authorized, true);
});

test("webhook mode mismatch and test payment against live pending fail closed", () => {
  const pending = pendingRecord({
    tenantId: "t_live",
    companyId: "c_live",
    activationId: "addon_mix_1",
    billingMode: "live",
  });
  const mixed = authorizeAddonWebhookActivation({
    apiKey: "live_dummy_not_a_real_secret",
    declaredMode: "live",
    pending,
    payment: paidPayment({
      mode: "test",
      activationId: "addon_mix_1",
      tenantId: "t_live",
      companyId: "c_live",
    }),
    companyCode: "FLX-00003",
    companyId: "c_live",
    allowlistRaw: "",
  });
  assert.equal(mixed.ok, false);
  assert.equal(mixed.error, "pending_payment_mode_mismatch");
});

test("checkout and webhook call the add-on test-mode gate", () => {
  assert.match(WORKER, /authorizeAddonCheckout/);
  assert.match(WORKER, /authorizeAddonWebhookActivation/);
  assert.match(WORKER, /buildAddonPendingBillingEvidence/);
  assert.match(WORKER, /legacy_pending_billing_mode_unproven/);
  assert.match(WORKER, /addon_test_mode_not_authorized/);
  assert.doesNotMatch(WORKER, /console\.log\([^\)]*FLUXIDI_SUBSCRIPTION_MOLLIE_API_KEY/);
});

test("crons stay empty and recovery cron stays disabled", () => {
  assert.match(TOML, /crons\s*=\s*\[\s*\]/);
  assert.match(TOML, /BILLIT_RECOVERY_CRON_ENABLED\s*=\s*"0"/);
  assert.match(TOML, /FLUXIDI_SUBSCRIPTION_ADDON_TEST_COMPANY_ALLOWLIST\s*=\s*""/);
});
