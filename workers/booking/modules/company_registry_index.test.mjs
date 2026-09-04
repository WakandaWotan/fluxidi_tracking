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
  registryPageKey,
  registryReadPlan,
  upsertCompanyRegistryEntry,
} from "./company_registry_index.mjs";

function pageCodes(kv, page = 1) {
  const raw = kv.map.get(registryPageKey(page));
  if (!raw) return [];
  const parsed = typeof raw === "string" ? JSON.parse(raw) : raw;
  return (parsed.companies || []).map((row) => row.company_code);
}

function registryKeyOps(kv) {
  const gets = kv.counts.gets;
  const puts = kv.counts.puts;
  return {
    code_gets: gets.filter((key) => key.startsWith("company_registry:code:")).length,
    code_puts: puts.filter((key) => key.startsWith("company_registry:code:")).length,
    page_gets: gets.filter((key) => key.startsWith("company_registry:page:")).length,
    page_puts: puts.filter((key) => key.startsWith("company_registry:page:")).length,
    manifest_gets: gets.filter((key) => key === COMPANY_REGISTRY_MANIFEST_KEY).length,
    manifest_puts: puts.filter((key) => key === COMPANY_REGISTRY_MANIFEST_KEY).length,
    list_ops: kv.counts.lists.length,
  };
}

test("successful canonical registry insertion writes code + page + manifest", async () => {
  const kv = createMemoryRegistryKv();
  const first = await upsertCompanyRegistryEntry(kv, {
    company_code: "FLX-00022",
    display_name: "Orphan Co",
  }, { nowIso: "2026-09-04T07:00:00.000Z" });
  assert.equal(first.ok, true);
  assert.equal(first.already_indexed, false);
  assert.equal(first.membershipChanged, true);
  assert.equal(first.manifest.total, 1);
  assert.equal(first.ops.code_gets, 1);
  assert.ok(first.ops.writes >= 3);
  assert.equal(pageCodes(kv).filter((code) => code === "FLX-00022").length, 1);
  const stored = JSON.parse(kv.map.get(registryCodeKey("FLX-00022")));
  assert.equal(stored.company_code, "FLX-00022");
  assert.equal(Object.hasOwn(stored, "email"), false);
  assert.equal(Object.hasOwn(stored, "tenant_id"), false);
});

test("already-indexed zero-write fast path", async () => {
  const kv = createMemoryRegistryKv();
  await upsertCompanyRegistryEntry(kv, { company_code: "FLX-00001", display_name: "A" });
  kv.counts.gets.length = 0;
  kv.counts.puts.length = 0;
  const replay = await upsertCompanyRegistryEntry(kv, {
    company_code: "FLX-00001",
    display_name: "A-renamed",
  });
  assert.equal(replay.ok, true);
  assert.equal(replay.already_indexed, true);
  assert.equal(replay.membershipChanged, false);
  assert.deepEqual(replay.ops, {
    code_gets: 1,
    code_puts: 0,
    page_gets: 0,
    page_puts: 0,
    manifest_gets: 0,
    manifest_puts: 0,
    list_ops: 0,
    writes: 0,
  });
  assert.deepEqual(registryKeyOps(kv), {
    code_gets: 1,
    code_puts: 0,
    page_gets: 0,
    page_puts: 0,
    manifest_gets: 0,
    manifest_puts: 0,
    list_ops: 0,
  });
  assert.deepEqual(pageCodes(kv), ["FLX-00001"]);
});

test("duplicate-safe replay keeps exact-once page membership", async () => {
  const kv = createMemoryRegistryKv();
  await upsertCompanyRegistryEntry(kv, { company_code: "FLX-00001", display_name: "A" });
  await upsertCompanyRegistryEntry(kv, { company_code: "FLX-00001", display_name: "A" });
  await upsertCompanyRegistryEntry(kv, { company_code: "FLX-00001", display_name: "A" });
  const manifest = JSON.parse(kv.map.get(COMPANY_REGISTRY_MANIFEST_KEY));
  assert.equal(manifest.total, 1);
  assert.deepEqual(pageCodes(kv), ["FLX-00001"]);
});

test("update without duplicate when code key is missing but page already has the company", async () => {
  const kv = createMemoryRegistryKv();
  await upsertCompanyRegistryEntry(kv, { company_code: "FLX-00001", display_name: "A" });
  kv.map.delete(registryCodeKey("FLX-00001"));
  const updated = await upsertCompanyRegistryEntry(kv, {
    company_code: "FLX-00001",
    display_name: "A-updated",
  }, { nowIso: "2026-09-04T08:00:00.000Z" });
  assert.equal(updated.ok, true);
  assert.equal(updated.membershipChanged, false);
  assert.equal(updated.manifest.total, 1);
  assert.deepEqual(pageCodes(kv), ["FLX-00001"]);
  const stored = JSON.parse(kv.map.get(registryCodeKey("FLX-00001")));
  assert.equal(stored.display_name, "A-updated");
});

test("ok: false is returned and does not write the code membership key", async () => {
  const kv = createMemoryRegistryKv();
  const originalGet = kv.get.bind(kv);
  kv.get = async (key, opts) => {
    const value = await originalGet(key, opts);
    if (key === COMPANY_REGISTRY_MANIFEST_KEY) {
      return {
        schema_version: 1,
        membership_generation: 0,
        page_count: 0,
        page_size: 100,
        total: 0,
        write_token: "never-confirm",
      };
    }
    return value;
  };
  const failed = await upsertCompanyRegistryEntry(kv, {
    company_code: "FLX-00022",
    display_name: "Pending",
  }, { maxAttempts: 2 });
  assert.equal(failed.ok, false);
  assert.equal(failed.error, "registry_concurrent_update");
  assert.equal(kv.map.has(registryCodeKey("FLX-00022")), false);
});

test("thrown write is not treated as resolved; retry inserts exactly once", async () => {
  const kv = createMemoryRegistryKv();
  let pagePuts = 0;
  const originalPut = kv.put.bind(kv);
  kv.put = async (key, value) => {
    if (String(key).startsWith("company_registry:page:") && pagePuts === 0) {
      pagePuts += 1;
      throw new Error("simulated_page_write_failure");
    }
    return originalPut(key, value);
  };
  await assert.rejects(
    () => upsertCompanyRegistryEntry(kv, { company_code: "FLX-00022", display_name: "Retry" }),
    /simulated_page_write_failure/,
  );
  assert.equal(kv.map.has(registryCodeKey("FLX-00022")), false);
  const retried = await upsertCompanyRegistryEntry(kv, {
    company_code: "FLX-00022",
    display_name: "Retry",
  });
  assert.equal(retried.ok, true);
  assert.deepEqual(pageCodes(kv), ["FLX-00022"]);
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

test("no list, no cron, and cost helpers stay list-free", () => {
  const source = readFileSync(fileURLToPath(new URL("./company_registry_index.mjs", import.meta.url)), "utf8");
  const worker = readFileSync(fileURLToPath(new URL("../fluxidi_booking_worker.js", import.meta.url)), "utf8");
  assert.doesNotMatch(source, /\.list\s*\(/);
  assert.doesNotMatch(source, /\bcrons\s*=/);
  assert.doesNotMatch(source, /scheduled\(\)|CronTrigger/);
  assert.doesNotMatch(source, /discoverExistingCompanies|applyBackfillBatch|census/);
  assert.match(worker, /upsertCompanyRegistryEntry/);
  assert.match(worker, /_upsertCompanyCodeIndexesForScope/);
  assert.match(worker, /_syncCompanyRegistryMembership/);
  assert.deepEqual(registryReadPlan(10), { manifest_gets: 1, page_gets: 1, total_gets: 2 });
  assert.equal(registryMaintainCost(1).list_ops, 0);
  assert.equal(registryMaintainCost(1).scheduled_rebuild, false);
  assert.equal(COMPANY_REGISTRY_PAGE_SIZE, 100);
});
