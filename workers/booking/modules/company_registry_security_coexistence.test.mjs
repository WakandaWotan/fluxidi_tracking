import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";
import assert from "node:assert/strict";

import worker from "../fluxidi_booking_worker.js";
import { authorizeAddonCheckout } from "./subscription_addon_test_mode_gate.mjs";
import { upsertCompanyRegistryEntry, registryCodeKey } from "./company_registry_index.mjs";
import {
  applyBackfillBatch,
  createMemoryBackfillKv,
  discoverExistingCompanies,
  indexRecordSeed,
  writeModeAllowed,
} from "./company_registry_backfill.mjs";
import { createWranglerKv } from "../tools/company_registry_backfill_cli.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const WORKER = readFileSync(join(HERE, "../fluxidi_booking_worker.js"), "utf8");
const TOML = readFileSync(join(HERE, "../wrangler.toml"), "utf8");
const INDEX = readFileSync(join(HERE, "./company_registry_index.mjs"), "utf8");
const GATE = readFileSync(join(HERE, "./subscription_addon_test_mode_gate.mjs"), "utf8");
const CLI = readFileSync(join(HERE, "../tools/company_registry_backfill_cli.mjs"), "utf8");
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

function seedSubscription(kv, tenantId, companyId, extra = {}) {
  kv.store.set(`tenant:${tenantId}:company:${companyId}:subscription:v1`, JSON.stringify({
    version: 1,
    subscription_profile: {
      version: 1,
      subscription_status: "active",
      status: "active",
      market: "BE",
      currency: "EUR",
      billing_email: "ops@example.test",
      included_vehicles: 1,
      max_vehicles: 1,
      extra_vehicle_active_quantity: extra.extra_vehicle_active_quantity ?? 3,
      extra_driver_active_quantity: 0,
      provider_customer_id: "cst_coexist",
      public_company_code: extra.public_company_code || "FLX-00001",
    },
  }));
}

function envFor({ kv, apiKey, mode, allowlist = "" }) {
  return {
    ADMIN_TOKEN: ADMIN,
    BOOKING_KV: kv,
    FLUXIDI_SUBSCRIPTION_MOLLIE_API_KEY: apiKey,
    FLUXIDI_SUBSCRIPTION_WEBHOOK_SECRET: WEBHOOK_SECRET,
    FLUXIDI_SUBSCRIPTION_MOLLIE_MODE: mode,
    FLUXIDI_SUBSCRIPTION_ADDON_TEST_COMPANY_ALLOWLIST: allowlist,
  };
}

function checkoutRequest(tenantId, companyId) {
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
      }),
    },
  );
}

test("security gate and registry maintenance coexist in the Worker", () => {
  assert.match(WORKER, /authorizeAddonCheckout/);
  assert.match(WORKER, /authorizeAddonWebhookActivation/);
  assert.match(WORKER, /upsertCompanyRegistryEntry/);
  assert.doesNotMatch(WORKER, /discoverExistingCompanies|company_registry_backfill/);
  assert.doesNotMatch(WORKER, /\/admin\/company-registry\/backfill|\/public\/.*backfill/);
  assert.doesNotMatch(INDEX, /\.list\s*\(/);
  assert.doesNotMatch(GATE, /upsertCompanyRegistryEntry/);
  assert.match(TOML, /crons\s*=\s*\[\s*\]/);
  assert.match(TOML, /BILLIT_RECOVERY_CRON_ENABLED\s*=\s*"0"/);
  assert.match(TOML, /FLUXIDI_SUBSCRIPTION_ADDON_TEST_COMPANY_ALLOWLIST\s*=\s*""/);
  assert.doesNotMatch(TOML, /^\s*FLUXIDI_SUBSCRIPTION_MOLLIE_MODE\s*=/m);
});

test("live-key checkout remains allowed while registry upsert does not grant extras", async () => {
  const live = authorizeAddonCheckout({
    apiKey: "live_dummy_not_a_real_secret",
    declaredMode: "live",
    companyCode: "FLX-00003",
    companyId: "c_live",
    allowlistRaw: "",
  });
  assert.equal(live.ok, true);
  assert.equal(live.billing_mode, "live");

  const kv = memoryKv();
  seedSubscription(kv, "t_live", "c_live", {
    public_company_code: "FLX-00003",
    extra_vehicle_active_quantity: 3,
  });
  await upsertCompanyRegistryEntry(kv, {
    company_code: "FLX-00003",
    display_name: "Ordinary Co",
    environment_class: "unknown",
  }, { nowIso: "2026-08-30T12:00:00.000Z" });
  const profile = await kv.get("tenant:t_live:company:c_live:subscription:v1", { type: "json" });
  assert.equal(profile.subscription_profile.extra_vehicle_active_quantity, 3);
  assert.ok(kv.store.has(registryCodeKey("FLX-00003")));
});

test("test-key ordinary companies stay denied after a registry event upsert", async () => {
  const kv = memoryKv();
  seedSubscription(kv, "t_ord", "c_ord", { extra_vehicle_active_quantity: 3 });
  await upsertCompanyRegistryEntry(kv, {
    company_code: "FLX-00001",
    display_name: "Fluxidi",
    environment_class: "unknown",
  }, { nowIso: "2026-08-30T12:00:00.000Z" });
  const denied = authorizeAddonCheckout({
    apiKey: "test_dummy_not_a_real_secret",
    declaredMode: "test",
    companyCode: "FLX-00001",
    companyId: "c_ord",
    allowlistRaw: "",
    displayName: "Fluxidi",
  });
  assert.equal(denied.ok, false);
  assert.equal(denied.error, "addon_test_mode_not_authorized");
  const res = await worker.fetch(
    checkoutRequest("t_ord", "c_ord"),
    envFor({
      kv,
      apiKey: "test_dummy_not_a_real_secret",
      mode: "test",
      allowlist: "",
    }),
  );
  assert.equal(res.status, 403);
  const body = await res.json();
  assert.equal(body.error, "addon_test_mode_not_authorized");
  const profile = await kv.get("tenant:t_ord:company:c_ord:subscription:v1", { type: "json" });
  assert.equal(profile.subscription_profile.extra_vehicle_active_quantity, 3);
});

test("pre-registry companies stay backfillable; local-QA stays excluded; resume stays idempotent", async () => {
  const kv = createMemoryBackfillKv();
  kv.map.set("company_link:index:code:FLX-00001:v1", indexRecordSeed("FLX-00001", {
    display_name: "Fluxidi",
  }));
  kv.map.set("company_link:index:code:FLX-88888:v1", indexRecordSeed("FLX-88888", {
    display_name: "Fixture",
    environment_class: "local_qa",
  }));
  const found = await discoverExistingCompanies(kv, {
    localShadowCodes: ["FLX-88888"],
  });
  assert.equal(found.rows.find((row) => row.company_code === "FLX-00001")?.eligible, true);
  assert.equal(found.rows.find((row) => row.company_code === "FLX-88888")?.eligible, false);
  const first = await applyBackfillBatch(kv, found.rows, {
    dryRun: false,
    batchSize: 1,
    nowIso: "2026-08-30T12:00:00.000Z",
  });
  const resumed = await applyBackfillBatch(kv, found.rows, {
    dryRun: false,
    batchSize: 10,
    checkpoint: first.checkpoint,
    nowIso: "2026-08-30T12:01:00.000Z",
  });
  assert.equal(resumed.ok, true);
  const again = await applyBackfillBatch(kv, found.rows, {
    dryRun: false,
    nowIso: "2026-08-30T12:02:00.000Z",
  });
  assert.equal(again.ok, true);
  assert.ok(kv.map.has(registryCodeKey("FLX-00001")));
  assert.equal(kv.map.has(registryCodeKey("FLX-88888")), false);
});

test("backfill CLI defaults to dry-run and cannot put through the wrangler adapter", async () => {
  assert.equal(writeModeAllowed([]), false);
  assert.equal(writeModeAllowed(["--dry-run"]), false);
  assert.match(CLI, /const dryRun = !writeModeAllowed\(argv\)/);
  assert.match(CLI, /write_blocked_dry_run/);
  const kv = createWranglerKv({ allowPut: false });
  await assert.rejects(() => kv.put("company_registry:code:FLX-00001:v1", "{}"), /write_blocked_dry_run/);
  assert.equal(kv.counts.put, 0);
});
