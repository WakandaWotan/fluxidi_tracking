import { test } from "node:test";
import assert from "node:assert/strict";
import {
  buildScopedMollieConnectStatusKey,
  publicMollieConnectStatusSnapshot,
  saveScopedMollieConnectAuthRecord,
} from "./modules/mollie_connect.js";

function makeKV(seed = {}) {
  const store = new Map(Object.entries(seed));
  return {
    store,
    async get(key, opts) {
      if (!store.has(key)) return null;
      const raw = store.get(key);
      if (opts && opts.type === "json") {
        return typeof raw === "string" ? JSON.parse(raw) : raw;
      }
      return typeof raw === "string" ? raw : JSON.stringify(raw);
    },
    async put(key, value) {
      store.set(key, value);
    },
  };
}

const SCOPE = { tenant_id: "tenant_fixture_mollie", company_id: "company_fixture_mollie" };

test("auth save writes a public Mollie status snapshot without tokens", async () => {
  const kv = makeKV();
  await saveScopedMollieConnectAuthRecord({ BOOKING_KV: kv }, SCOPE, {
    connected: true,
    status: "connected",
    mollie_mode: "live",
    payment_demo_mode: false,
    updated_at: "2026-08-16T07:00:00.000Z",
    accessTokenEncrypted: { k: "secret" },
    refreshTokenEncrypted: { k: "secret" },
    organizationId: "org_should_not_leak",
    profileId: "pfl_should_not_leak",
  });
  const key = buildScopedMollieConnectStatusKey(SCOPE);
  const snapshot = await kv.get(key, { type: "json" });
  assert.equal(snapshot.status, "connected");
  assert.equal(snapshot.mollie_mode, "live");
  assert.equal(snapshot.payment_demo_mode, false);
  assert.equal(snapshot.source_revision, 1);
  assert.doesNotMatch(JSON.stringify(snapshot), /secret|org_|pfl_|accessToken|refreshToken|apiKey/i);
});

test("public snapshot follows LIVE to TEST without a manual KV edit of the auth shape", async () => {
  const kv = makeKV();
  const env = { BOOKING_KV: kv };
  await saveScopedMollieConnectAuthRecord(env, SCOPE, {
    connected: true,
    status: "connected",
    mollie_mode: "live",
    updated_at: "2026-08-16T07:00:00.000Z",
  });
  await saveScopedMollieConnectAuthRecord(env, SCOPE, {
    connected: true,
    status: "connected",
    mollie_mode: "test",
    payment_demo_mode: true,
    updated_at: "2026-08-16T08:00:00.000Z",
  });
  const snapshot = await kv.get(buildScopedMollieConnectStatusKey(SCOPE), { type: "json" });
  assert.equal(snapshot.mollie_mode, "test");
  assert.equal(snapshot.payment_demo_mode, true);
  assert.equal(snapshot.source_revision, 2);
  const derived = publicMollieConnectStatusSnapshot({
    connected: false,
    status: "disconnected",
    mollie_mode: "live",
  }, snapshot, SCOPE);
  assert.equal(derived.status, "disconnected");
  assert.equal(derived.source_revision, 3);
});
