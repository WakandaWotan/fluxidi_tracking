#!/usr/bin/env node
/**
 * Read-only Phase A registry snapshot. No production writes.
 */
import { readFileSync } from "node:fs";
import { createMemoryKv, createWranglerKv, BOOKING_KV_ID } from "./company_retirement_stores.mjs";
import { runRetirementCli } from "./company_retirement_p0.mjs";
import {
  applyRegistryRetirementExecute,
} from "./company_retirement_plan.mjs";
import {
  collectRegistryRawBackup,
  defaultBackupRoot,
  registryStateChecksums,
  restoreRegistryBackup,
} from "./company_retirement_backup.mjs";
import {
  COMPANY_REGISTRY_MANIFEST_KEY,
  registryCodeKey,
  registryPageKey,
} from "../../modules/company_registry_index.mjs";
import { registryTombstoneKey } from "../../modules/company_registry_tombstone_guard.mjs";
import { companyLinkCodeKey } from "./company_retirement_keys.mjs";
import { EXPLICIT_RETIREMENT_CANDIDATES } from "./company_retirement_policy.mjs";

function loadPriorCounts(path) {
  const previous = JSON.parse(readFileSync(path, "utf8"));
  const priorCounts = {};
  for (const row of previous.companies || []) {
    priorCounts[row.company_code] = {
      ...(row.counts || {}),
      billit_oauth_present: row.integrations?.billit_oauth_present === true,
      mollie_status_present: row.integrations?.mollie_status_present === true,
      chiron_present: row.integrations?.chiron_present === true,
      driver_link_present: row.integrations?.driver_link_present === true,
    };
  }
  return priorCounts;
}

function presence(value) {
  return {
    present: Boolean(value),
    lifecycle_status: value && typeof value === "object" ? (value.lifecycle_status || null) : null,
    linking_enabled: value && typeof value === "object"
      ? (value.linking_enabled ?? value.linkingEnabled ?? null)
      : null,
    environment_class: value && typeof value === "object" ? (value.environment_class || null) : null,
  };
}

async function main() {
  const cwd = process.cwd();
  const priorCounts = loadPriorCounts(
    "C:\\_flutter_work\\_local_backups\\fluxidi_company_retirement_p0\\2026-09-07T14-26-08-250Z\\sanitized_inventory.json",
  );
  const kv = createWranglerKv({ namespaceId: BOOKING_KV_ID, cwd });
  const result = await runRetirementCli(["--registry-only", "--backup-dir", defaultBackupRoot()], {
    stores: {
      BOOKING_KV: kv,
      FLUXIDI_TRACKING: { async get() { return null; } },
      INVOICE_KV: { async get() { return null; } },
      PUBLIC_MEDIA: { async get() { return null; }, async head() { return null; } },
    },
    writeBackup: true,
    registryOnly: true,
    priorCounts,
    concurrency: 3,
    cwd,
  });

  const extraCodes = ["FLX-00001", "FLX-00020", "FLX-00023"];
  const extra = {};
  for (const code of extraCodes) {
    extra[code] = {
      registry: presence(await kv.get(registryCodeKey(code))),
      link: presence(await kv.get(companyLinkCodeKey(code))),
      tombstone: presence(await kv.get(registryTombstoneKey(code))),
    };
  }

  const raw = result.backup?.raw_backup || collectRegistryRawBackup(result.report);
  const memory = createMemoryKv();
  for (const record of raw.records) {
    memory.map.set(record.key, record.raw);
  }
  const codes = [...EXPLICIT_RETIREMENT_CANDIDATES, "FLX-00001", "FLX-00020", "FLX-00023"];
  const before = registryStateChecksums(memory.map, codes, result.report?.registry_snapshot?.page_count || 1);
  const applied = await applyRegistryRetirementExecute(memory, result.report, {
    nowIso: "2026-09-07T16:30:00.000Z",
  });
  const mid = registryStateChecksums(memory.map, codes, result.report?.registry_snapshot?.page_count || 1);
  const restored = await restoreRegistryBackup(memory, raw);
  const after = registryStateChecksums(memory.map, codes, result.report?.registry_snapshot?.page_count || 1);

  const page1 = result.report?.raw_registry?.pages?.[0];
  const observed = (page1?.companies || []).map((row) => row.company_code);

  console.log(JSON.stringify({
    ok: result.ok,
    mode: result.mode,
    phase: result.phase,
    error: result.error || null,
    backup_dir: result.backup?.dir || null,
    record_count: raw.records.length,
    risk_groups: result.report?.risk_groups || null,
    reconciliation: result.report?.reconciliation || null,
    observed_on_page1: observed,
    observed_has_91611: observed.includes("FLX-91611"),
    observed_has_90811: observed.includes("FLX-90811"),
    extra_identity: extra,
    registry_write_set: (result.plan?.companies || []).map((row) => ({
      company_code: row.company_code,
      action: row.action,
      keys: (row.writes || []).map((write) => ({ key: write.key, kind: write.kind })),
    })),
    protected_in_write_set: (result.plan?.companies || []).some((row) => (
      row.company_code === "FLX-00001" || row.company_code === "FLX-00020" || row.company_code === "FLX-00023"
    )),
    offline_restore: {
      apply_ok: applied.ok === true,
      apply_error: applied.error || null,
      restore_ok: restored.ok === true,
      checksums_match: JSON.stringify(before) === JSON.stringify(after),
      tombstone_appeared_after_apply: Boolean(mid[registryTombstoneKey("FLX-00022")]),
      protected_registry_unchanged:
        before[registryCodeKey("FLX-00001")] === after[registryCodeKey("FLX-00001")]
        && before[registryCodeKey("FLX-00020")] === after[registryCodeKey("FLX-00020")]
        && before[registryCodeKey("FLX-00023")] === after[registryCodeKey("FLX-00023")],
    },
    live_worker_bundle_files: result.live_worker_bundle_files,
  }, null, 2));
}

main().catch((err) => {
  console.log(JSON.stringify({ ok: false, error: String(err?.message || err) }));
  process.exitCode = 1;
});
