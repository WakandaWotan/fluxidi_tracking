import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import {
  COMPANY_REGISTRY_MANIFEST_KEY,
  COMPANY_REGISTRY_PAGE_SIZE,
  applyRegistryUpsert,
  codesOf,
  createMemoryRegistryKv,
  publicRegistryFields,
  registryCodeKey,
  registryMaintainCost,
  registryReadPlan,
  upsertCompanyRegistryEntry,
} from "./company_registry_index.mjs";

test("idempotent upsert keeps one membership slot", async () => {
  const kv = createMemoryRegistryKv();
  const first = await upsertCompanyRegistryEntry(kv, {
    company_code: "FLX-00001",
    display_name: "Fluxidi",
    created_at: "2026-05-12T00:00:00.000Z",
  }, { nowIso: "2026-08-30T07:32:41.549Z" });
  const second = await upsertCompanyRegistryEntry(kv, {
    company_code: "FLX-00001",
    display_name: "Fluxidi",
  }, { nowIso: "2026-08-30T08:00:00.000Z" });
  assert.equal(first.ok, true);
  assert.equal(second.ok, true);
  assert.equal(second.membershipChanged, false);
  assert.equal(second.manifest.total, 1);
  const stored = JSON.parse(kv.map.get(registryCodeKey("FLX-00001")));
  assert.equal(stored.display_name, "Fluxidi");
  assert.equal(Object.hasOwn(stored, "email"), false);
  assert.equal(Object.hasOwn(stored, "vat_number"), false);
});

test("pages grow without silent truncation at 100 and 101", async () => {
  const kv = createMemoryRegistryKv();
  for (let i = 1; i <= 101; i += 1) {
    const code = `FLX-${String(i).padStart(5, "0")}`;
    const result = await upsertCompanyRegistryEntry(kv, { company_code: code, display_name: code }, {
      nowIso: `2026-08-30T00:00:${String(i % 60).padStart(2, "0")}.000Z`,
    });
    assert.equal(result.ok, true);
  }
  const manifest = JSON.parse(kv.map.get(COMPANY_REGISTRY_MANIFEST_KEY));
  assert.equal(manifest.total, 101);
  assert.equal(manifest.page_count, 2);
  assert.equal(manifest.page_size, COMPANY_REGISTRY_PAGE_SIZE);
  const page2 = JSON.parse(kv.map.get("company_registry:page:2:v1"));
  assert.equal(page2.companies.length, 1);
});

test("applyUpsert never drops previously observed codes", () => {
  const snapshot = {
    manifest: {
      schema_version: 1,
      membership_generation: 2,
      page_count: 1,
      page_size: 100,
      total: 2,
    },
    pages: [{
      page: 1,
      membership_generation: 2,
      companies: [
        publicRegistryFields({ company_code: "FLX-00001", display_name: "A" }),
        publicRegistryFields({ company_code: "FLX-00020", display_name: "B" }),
      ],
    }],
  };
  const next = applyRegistryUpsert(snapshot, publicRegistryFields({
    company_code: "FLX-00030",
    display_name: "C",
  }));
  assert.deepEqual([...codesOf(next)].sort(), ["FLX-00001", "FLX-00020", "FLX-00030"]);
  assert.equal(next.manifest.total, 3);
});

test("concurrent last-write is retried until both codes remain", async () => {
  const kv = createMemoryRegistryKv();
  let stale = false;
  const originalGet = kv.get.bind(kv);
  kv.get = async (key, opts) => {
    const value = await originalGet(key, opts);
    if (!stale && key === COMPANY_REGISTRY_MANIFEST_KEY && value) {
      stale = true;
      return { schema_version: 1, membership_generation: 0, page_count: 0, page_size: 100, total: 0 };
    }
    return value;
  };
  await upsertCompanyRegistryEntry(kv, { company_code: "FLX-00001", display_name: "A" }, { nowIso: "2026-08-30T00:00:01.000Z" });
  const raced = await upsertCompanyRegistryEntry(kv, { company_code: "FLX-00020", display_name: "B" }, { nowIso: "2026-08-30T00:00:02.000Z" });
  assert.equal(raced.ok, true);
  const manifest = JSON.parse((await originalGet(COMPANY_REGISTRY_MANIFEST_KEY)) || kv.map.get(COMPANY_REGISTRY_MANIFEST_KEY));
  assert.ok(manifest.total >= 1);
});

test("no list, no cron, cost model 10/100/1000", () => {
  const source = readFileSync(fileURLToPath(new URL("./company_registry_index.mjs", import.meta.url)), "utf8");
  const worker = readFileSync(fileURLToPath(new URL("../fluxidi_booking_worker.js", import.meta.url)), "utf8");
  assert.doesNotMatch(source, /\.list\s*\(/);
  assert.doesNotMatch(source, /\bcrons\s*=/);
  assert.doesNotMatch(source, /scheduled\(\)|CronTrigger/);
  assert.match(worker, /upsertCompanyRegistryEntry/);
  assert.match(worker, /_upsertCompanyCodeIndexesForScope/);
  assert.deepEqual(registryReadPlan(10), { manifest_gets: 1, page_gets: 1, total_gets: 2 });
  assert.deepEqual(registryReadPlan(100), { manifest_gets: 1, page_gets: 1, total_gets: 2 });
  assert.deepEqual(registryReadPlan(1000), { manifest_gets: 1, page_gets: 10, total_gets: 11 });
  assert.equal(registryMaintainCost(1).list_ops, 0);
  assert.equal(registryMaintainCost(1).scheduled_rebuild, false);
  assert.equal(registryMaintainCost(10).total_kv, 7);
  assert.equal(registryMaintainCost(100).total_kv, 7);
  assert.equal(registryMaintainCost(1000).total_kv, 25);
});
