import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import {
  COMPANY_REGISTRY_MANIFEST_KEY,
  codesOf,
  readRegistrySnapshot,
  upsertCompanyRegistryEntry,
} from "./company_registry_index.mjs";
import {
  COMPANY_LINK_CODE_PREFIX,
  PLAY_REVIEW_COMPANY_CODE,
  PRODUCTION_BOOKING_KV_NAMESPACE_ID,
  WRITE_CONFIRM_FLAG,
  WRITE_FLAG,
  applyBackfillBatch,
  assertExactPrefix,
  assertProductionNamespace,
  classifyIndexRecord,
  createMemoryBackfillKv,
  discoverExistingCompanies,
  emptyCheckpoint,
  estimateBackfillCost,
  indexRecordSeed,
  parseCompanyLinkCodeKey,
  writeModeAllowed,
} from "./company_registry_backfill.mjs";

function seedIndex(kv, code, extras = {}) {
  kv.map.set(`company_link:index:code:${code}:v1`, indexRecordSeed(code, extras));
}

test("exact prefix and production namespace are required", () => {
  assert.equal(assertExactPrefix(COMPANY_LINK_CODE_PREFIX).ok, true);
  assert.equal(assertExactPrefix("company_link:index:").ok, false);
  assert.equal(assertProductionNamespace(PRODUCTION_BOOKING_KV_NAMESPACE_ID).ok, true);
  assert.equal(assertProductionNamespace("other").ok, false);
  assert.equal(writeModeAllowed(["--dry-run"]), false);
  assert.equal(writeModeAllowed([WRITE_FLAG]), false);
  assert.equal(writeModeAllowed([WRITE_FLAG, WRITE_CONFIRM_FLAG]), true);
  assert.equal(parseCompanyLinkCodeKey("company_link:index:code:FLX-00001:v1")?.company_code, "FLX-00001");
  assert.equal(parseCompanyLinkCodeKey("company_link:index:scope:x:v1"), null);
  assert.equal(parseCompanyLinkCodeKey("company_link:index:code:FLX-00001:history:v1"), null);
});

test("pre-existing companies are discovered and eligible; local-QA is excluded", async () => {
  const kv = createMemoryBackfillKv();
  seedIndex(kv, "FLX-00001", { display_name: "Fluxidi" });
  seedIndex(kv, "FLX-00020", { display_name: "Fluxidi Google Review" });
  seedIndex(kv, "FLX-00008", { display_name: "Review Taxi", source: "play_review" });
  seedIndex(kv, "FLX-00999", { display_name: "Inactive Co", linking_enabled: false });
  kv.map.set("unrelated:history:1", "{}");
  const found = await discoverExistingCompanies(kv, {
    localShadowCodes: ["FLX-00001", "FLX-00020", "FLX-88888"],
  });
  assert.equal(found.ok, true);
  assert.equal(found.pages, 1);
  assert.deepEqual(found.candidate_codes, ["FLX-00001", "FLX-00008", "FLX-00020", "FLX-00999"]);
  const byCode = Object.fromEntries(found.rows.map((row) => [row.company_code, row]));
  assert.equal(byCode["FLX-00001"].eligible, true);
  assert.equal(byCode["FLX-00001"].present_in_registry, false);
  assert.equal(byCode["FLX-00001"].present_in_local_shadow, true);
  assert.equal(byCode["FLX-00001"].environment_class, "unknown");
  assert.equal(byCode["FLX-00001"].reason, "environment_unproven");
  assert.equal(byCode["FLX-00020"].environment_class, "review");
  assert.equal(byCode["FLX-00020"].eligible, true);
  assert.equal(byCode["FLX-00008"].environment_class, "unknown");
  assert.equal(byCode["FLX-00999"].lifecycle_status, "inactive");
  assert.equal(byCode["FLX-00999"].eligible, true);
  assert.equal(byCode["FLX-88888"].eligible, false);
  assert.equal(byCode["FLX-88888"].reason, "local_qa_only");
  assert.equal(byCode["FLX-88888"].environment_class, "local_qa");
  assert.ok(!found.candidate_codes.includes("FLX-88888"));
  assert.equal(found.ops.list, 1);
  assert.equal(kv.counts.listed.every((prefix) => prefix === COMPANY_LINK_CODE_PREFIX), true);
});

test("future companies enter via event maintenance, not the backfill list", async () => {
  const kv = createMemoryBackfillKv();
  seedIndex(kv, "FLX-00001", { display_name: "Fluxidi" });
  const found = await discoverExistingCompanies(kv);
  assert.deepEqual(found.candidate_codes, ["FLX-00001"]);
  const created = await upsertCompanyRegistryEntry(kv, {
    company_code: "FLX-00030",
    display_name: "Future Co",
    environment_class: "production",
  }, { nowIso: "2026-08-30T12:00:00.000Z" });
  assert.equal(created.ok, true);
  const snapshot = await readRegistrySnapshot(kv);
  assert.deepEqual([...codesOf(snapshot)].sort(), ["FLX-00030"]);
});

test("re-running backfill write produces no duplicate registry entries", async () => {
  const kv = createMemoryBackfillKv();
  seedIndex(kv, "FLX-00001", { display_name: "Fluxidi" });
  seedIndex(kv, PLAY_REVIEW_COMPANY_CODE, { display_name: "Fluxidi Google Review" });
  const found = await discoverExistingCompanies(kv);
  const first = await applyBackfillBatch(kv, found.rows, {
    dryRun: false,
    batchSize: 10,
    nowIso: "2026-08-30T12:00:00.000Z",
  });
  assert.equal(first.ok, true);
  const again = await applyBackfillBatch(kv, found.rows, {
    dryRun: false,
    batchSize: 10,
    nowIso: "2026-08-30T12:05:00.000Z",
  });
  assert.equal(again.ok, true);
  const snapshot = await readRegistrySnapshot(kv);
  assert.equal(snapshot.manifest.total, 2);
  assert.deepEqual([...codesOf(snapshot)].sort(), ["FLX-00001", "FLX-00020"]);
  const stored = JSON.parse(kv.map.get("company_registry:code:FLX-00001:v1"));
  assert.equal(stored.environment_class, "unknown");
  const review = JSON.parse(kv.map.get("company_registry:code:FLX-00020:v1"));
  assert.equal(review.environment_class, "review");
});

test("interrupted backfill resumes from checkpoint without rewriting processed codes", async () => {
  const kv = createMemoryBackfillKv();
  seedIndex(kv, "FLX-00001", { display_name: "A" });
  seedIndex(kv, "FLX-00020", { display_name: "B" });
  seedIndex(kv, "FLX-00021", { display_name: "C" });
  const found = await discoverExistingCompanies(kv);
  const first = await applyBackfillBatch(kv, found.rows, {
    dryRun: false,
    batchSize: 1,
    nowIso: "2026-08-30T12:00:00.000Z",
  });
  assert.equal(first.interrupted, true);
  assert.equal(first.checkpoint.processed_codes.length, 1);
  const resumed = await applyBackfillBatch(kv, found.rows, {
    dryRun: false,
    batchSize: 10,
    checkpoint: first.checkpoint,
    nowIso: "2026-08-30T12:01:00.000Z",
  });
  assert.equal(resumed.ok, true);
  assert.equal(resumed.interrupted, false);
  assert.ok(resumed.report.some((row) => row.action === "skipped_already_processed"));
  const snapshot = await readRegistrySnapshot(kv);
  assert.equal(snapshot.manifest.total, 3);
});

test("inactive, deleted, test and review classifications survive", () => {
  const inactive = classifyIndexRecord({
    company_code: "FLX-00999",
    display_name: "Old",
    linking_enabled: false,
    source: "admin",
  }, "FLX-00999");
  assert.equal(inactive.lifecycle_status, "inactive");
  assert.equal(inactive.environment_class, "unknown");
  assert.equal(inactive.eligible, true);
  const review = classifyIndexRecord({
    company_code: "FLX-00020",
    display_name: "Review",
    linking_enabled: true,
  }, "FLX-00020");
  assert.equal(review.environment_class, "review");
  const namedTest = classifyIndexRecord({
    company_code: "FLX-00008",
    display_name: "Fluxidi Wizard Test",
    source: "play_review",
  }, "FLX-00008");
  assert.equal(namedTest.environment_class, "unknown");
  const explicitLocal = classifyIndexRecord({
    company_code: "FLX-88888",
    display_name: "Fixture",
    environment_class: "local_qa",
  }, "FLX-88888");
  assert.equal(explicitLocal.eligible, false);
  assert.equal(explicitLocal.environment_class, "local_qa");
  const explicitProd = classifyIndexRecord({
    company_code: "FLX-00003",
    display_name: "Prometheus",
    environment_class: "production",
  }, "FLX-00003");
  assert.equal(explicitProd.environment_class, "production");
  const sourceOnly = classifyIndexRecord({
    company_code: "FLX-88887",
    display_name: "Fixture",
    source: "local_qa",
  }, "FLX-88887");
  assert.equal(sourceOnly.environment_class, "unknown");
  assert.equal(sourceOnly.eligible, true);
});

test("Command Centre can show the authoritative registered count after population", async () => {
  const kv = createMemoryBackfillKv();
  seedIndex(kv, "FLX-00001", { display_name: "Fluxidi" });
  seedIndex(kv, "FLX-00020", { display_name: "Fluxidi Google Review" });
  const found = await discoverExistingCompanies(kv);
  await applyBackfillBatch(kv, found.rows, { dryRun: false, nowIso: "2026-08-30T12:00:00.000Z" });
  const snapshot = await readRegistrySnapshot(kv);
  assert.equal(snapshot.manifest.total, 2);
  assert.equal(JSON.parse(kv.map.get(COMPANY_REGISTRY_MANIFEST_KEY)).total, 2);
});

test("idle recurring production operations remain zero", () => {
  const cost = estimateBackfillCost(4);
  assert.equal(cost.idle_after.list_ops, 0);
  assert.equal(cost.idle_after.total_kv, 0);
  assert.equal(cost.idle_after.cron, false);
  assert.equal(cost.idle_after.recurring, false);
  assert.equal(cost.projected[10].dry_run.list_ops, 1);
  assert.equal(cost.projected[10].dry_run.index_gets, 10);
  assert.equal(cost.projected[100].dry_run.index_gets, 100);
  assert.equal(cost.projected[1000].dry_run.list_ops, 1);
  assert.equal(cost.projected[1000].dry_run.index_gets, 1000);
  assert.equal(cost.projected[1000].one_time_write_upper_bound.registry_kv_per_company, 25);
});

test("backfill tool is CLI-only and booking worker does not list at runtime", () => {
  const worker = readFileSync(fileURLToPath(new URL("../fluxidi_booking_worker.js", import.meta.url)), "utf8");
  const cli = readFileSync(fileURLToPath(new URL("../tools/company_registry_backfill_cli.mjs", import.meta.url)), "utf8");
  const moduleSource = readFileSync(fileURLToPath(new URL("./company_registry_index.mjs", import.meta.url)), "utf8");
  assert.match(cli, /dry-run/);
  assert.match(cli, /write-registry/);
  assert.doesNotMatch(cli, /export default|scheduled\(|CronTrigger/);
  assert.doesNotMatch(moduleSource, /\.list\s*\(/);
  assert.doesNotMatch(worker, /discoverExistingCompanies|company_registry_backfill/);
  assert.match(worker, /upsertCompanyRegistryEntry/);
  assert.match(worker, /write_token/);
  assert.match(worker, /_applyDashboardBookingsKpiContributionDelta/);
});
