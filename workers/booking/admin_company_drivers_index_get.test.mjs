import assert from "node:assert/strict";
import test from "node:test";

import worker from "./fluxidi_booking_worker.js";
import { sha256Hex } from "./modules/crypto_utils.js";

function makeKV(seed = {}) {
  const store = new Map(Object.entries(seed));
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
    async put(key, val) {
      store.set(key, val);
    },
    async delete(key) {
      store.delete(key);
    },
    async list() {
      return { keys: [], list_complete: true };
    },
  };
}

test("GET /admin/company/drivers/index lists scoped drivers without secrets", async () => {
  const token = "cst_drivers_get";
  const hash = await sha256Hex(token);
  const kv = makeKV({
    [`company_admin:session:${hash}:v1`]: JSON.stringify({
      role: "company_admin",
      tenant_id: "demo_company_p0",
      company_id: "demo_company_p0",
      expires_at: new Date(Date.now() + 3600_000).toISOString(),
    }),
    "tenant:demo_company_p0:company:demo_company_p0:drivers:index:v1": JSON.stringify({
      drivers: {
        drv_demo_company_p0_1: {
          driver_id: "drv_demo_company_p0_1",
          display_name: "Karel Peeters",
          phone: "+32470000011",
          is_active: true,
          driver_code_hash: "secret-hash",
          driver_code_salt: "secret-salt",
          login_code: "123456",
        },
      },
    }),
  });
  const res = await worker.fetch(
    new Request("http://127.0.0.1/admin/company/drivers/index?tenant_id=demo_company_p0&company_id=demo_company_p0", {
      headers: { authorization: `Bearer ${token}` },
    }),
    { BOOKING_KV: kv },
    {},
  );
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.ok, true);
  assert.equal(body.count, 1);
  assert.equal(body.drivers[0].display_name, "Karel Peeters");
  assert.equal(body.drivers[0].driver_code_hash, undefined);
  assert.equal(body.drivers[0].login_code, undefined);
});
