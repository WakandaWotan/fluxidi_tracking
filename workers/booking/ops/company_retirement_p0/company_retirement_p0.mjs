#!/usr/bin/env node
/**
 * One-shot local Phase A registry-retirement CLI. Dry-run by default.
 * Not a public Worker route. Does not touch Command Centre.
 * Phase B full-purge is hard-disabled.
 */
import {
  EXPLICIT_RETIREMENT_CANDIDATES,
  EXECUTE_CONFIRMATION_TEXT,
  HARD_PROTECTED_COMPANY_CODES,
  LIVE_WORKER_BUNDLE_RETIREMENT_FILES,
  LOCAL_ONLY_RETIREMENT_FILES,
  PHASE_A_REGISTRY_RETIREMENT,
  assertExecuteAuthorization,
  assertFullPurgeForbidden,
  assertPhaseSelection,
  selectRetirementCodes,
} from "./company_retirement_policy.mjs";
import {
  inventorySelection,
  readRegistryPagesAndManifest,
} from "./company_retirement_inventory.mjs";
import {
  applyFullPurge,
  applyRegistryRetirementExecute,
  buildRetirementPlan,
} from "./company_retirement_plan.mjs";
import {
  collectRegistryRawBackup,
  defaultBackupRoot,
  registryStateChecksums,
  restoreRegistryBackup,
  writeRetirementBackup,
} from "./company_retirement_backup.mjs";
import {
  BOOKING_KV_ID,
  INVOICE_KV_ID,
  TRACKING_KV_ID,
  createMemoryKv,
  createWranglerKv,
} from "./company_retirement_stores.mjs";

function parseArgs(argv) {
  const args = {
    execute: false,
    confirm: "",
    codes: [...EXPLICIT_RETIREMENT_CANDIDATES],
    backupDir: defaultBackupRoot(),
    help: false,
    phase: PHASE_A_REGISTRY_RETIREMENT,
    fullPurge: false,
    registryOnly: false,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (token === "--execute") args.execute = true;
    else if (token === "--dry-run") args.execute = false;
    else if (token === "--confirm") args.confirm = String(argv[++i] || "");
    else if (token === "--codes") args.codes = String(argv[++i] || "").split(",").map((v) => v.trim()).filter(Boolean);
    else if (token === "--backup-dir") args.backupDir = String(argv[++i] || args.backupDir);
    else if (token === "--phase") args.phase = String(argv[++i] || args.phase);
    else if (token === "--full-purge" || token === "--purge") args.fullPurge = true;
    else if (token === "--registry-only") args.registryOnly = true;
    else if (token === "--rollback" || token === "--tombstone-delete") {
      throw new Error("production_rollback_forbidden");
    }
    else if (token === "--help" || token === "-h") args.help = true;
    else throw new Error(`unknown_flag:${token}`);
  }
  return args;
}

function printHelp() {
  console.log(`company_retirement_p0
  default: Phase A registry-only dry-run of the 22 explicit candidate IDs
  --codes FLX-00002,FLX-00003   optional subset; each ID must be explicit
  --backup-dir PATH             local registry backup outside git
  --phase registry_retirement   only allowed phase
  --execute --confirm ${EXECUTE_CONFIRMATION_TEXT}
  Execute requires FLUXIDI_RETIREMENT_EXECUTE_ENABLED=1
  --full-purge is hard-disabled.
  --rollback / --tombstone-delete are hard-disabled in production.
  A complete registry rollback also needs the exact tombstone list
  neutralized; page/manifest/code/link PUTs alone are incomplete.
`);
}

function sameCodeList(left = [], right = []) {
  return JSON.stringify([...left].sort()) === JSON.stringify([...right].sort());
}

export async function runOfflineRestoreTest(report, backup) {
  const raw = backup?.raw_backup || collectRegistryRawBackup(report);
  const memory = createMemoryKv();
  for (const record of raw.records || []) {
    memory.map.set(record.key, record.raw);
  }
  const codes = [
    ...EXPLICIT_RETIREMENT_CANDIDATES,
    ...HARD_PROTECTED_COMPANY_CODES,
  ];
  const before = registryStateChecksums(memory.map, codes, report.registry_snapshot?.page_count || 1);
  const applied = await applyRegistryRetirementExecute(memory, report, {
    nowIso: "2026-09-07T17:00:00.000Z",
  });
  const restored = await restoreRegistryBackup(memory, raw);
  const after = registryStateChecksums(memory.map, codes, report.registry_snapshot?.page_count || 1);
  return {
    apply_ok: applied.ok === true,
    apply_error: applied.error || null,
    restore_ok: restored.ok === true,
    checksums_match: JSON.stringify(before) === JSON.stringify(after),
    remaining_after_apply: applied.snapshot ? [...new Set((applied.snapshot.pages || []).flatMap((page) => (page.companies || []).map((row) => row.company_code)))] : [],
  };
}

export async function runRetirementCli(argv = process.argv.slice(2), {
  stores = null,
  cwd = process.cwd(),
  writeBackup = true,
  registryOnly = false,
  priorCounts = null,
  concurrency = null,
} = {}) {
  const args = parseArgs(argv);
  if (args.help) {
    printHelp();
    return { ok: true, help: true };
  }
  const phaseCheck = assertPhaseSelection(args.phase);
  if (!phaseCheck.ok) {
    return { ok: false, error: phaseCheck.error };
  }
  const purgeCheck = assertFullPurgeForbidden(args);
  if (args.fullPurge || args.phase === "full_purge") {
    try {
      applyFullPurge();
    } catch {
      return { ok: false, error: "phase_b_full_purge_disabled" };
    }
    return { ok: false, error: purgeCheck.error };
  }
  const selected = selectRetirementCodes(args.codes);
  if (!selected.ok) {
    return { ok: false, error: "selection_rejected", details: selected.errors };
  }
  const auth = assertExecuteAuthorization({
    execute: args.execute,
    confirm: args.confirm,
    executeEnabled: process.env.FLUXIDI_RETIREMENT_EXECUTE_ENABLED === "1",
    phase: args.phase,
    fullPurge: args.fullPurge,
  });
  if (!auth.ok) {
    return { ok: false, error: auth.error };
  }
  const resolvedStores = stores || {
    BOOKING_KV: createWranglerKv({
      namespaceId: BOOKING_KV_ID,
      cwd,
      allowWrites: auth.mode === "execute",
      allowedCodes: selected.selected,
    }),
    FLUXIDI_TRACKING: createWranglerKv({ namespaceId: TRACKING_KV_ID, cwd }),
    INVOICE_KV: createWranglerKv({ namespaceId: INVOICE_KV_ID, cwd }),
    PUBLIC_MEDIA: { async get() { return null; }, async head() { return null; } },
  };
  const report = await inventorySelection(resolvedStores, selected.selected, {
    compact: !stores,
    concurrency: concurrency || (stores ? 1 : 3),
    registryOnly: registryOnly === true || args.registryOnly === true,
    priorCounts,
  });
  const plan = buildRetirementPlan(report);
  plan.mode = auth.mode;
  let backup = null;
  if (writeBackup) {
    backup = writeRetirementBackup(args.backupDir, report, plan);
  }
  const restore = report.raw_registry
    ? await runOfflineRestoreTest(report, backup)
    : { apply_ok: false, restore_ok: false, checksums_match: false };
  if (auth.mode === "execute") {
    if (!restore.apply_ok || !restore.restore_ok || !restore.checksums_match) {
      return { ok: false, error: "offline_restore_failed_before_execute", restore, report, plan, backup };
    }
    const liveAgain = await readRegistryPagesAndManifest(resolvedStores.BOOKING_KV);
    const liveCodes = (liveAgain.pages || []).flatMap((page) => (page.companies || []).map((row) => row.company_code));
    const backupCodes = (report.raw_registry?.pages || []).flatMap((page) => (page.companies || []).map((row) => row.company_code));
    const liveChecksum = liveAgain.checksums || {};
    const backupChecksum = report.registry_snapshot?.checksums || {};
    const liveManifest = liveAgain.manifest || {};
    const backupManifest = report.raw_registry?.manifest || {};
    const livePage = liveAgain.pages?.[0] || {};
    const backupPage = report.raw_registry?.pages?.[0] || {};
    if (
      liveChecksum.registry_manifest !== backupChecksum.registry_manifest
      || liveChecksum.registry_page !== backupChecksum.registry_page
      || !sameCodeList(liveCodes, backupCodes)
      || liveManifest.total !== backupManifest.total
      || liveManifest.membership_generation !== backupManifest.membership_generation
      || livePage.membership_generation !== backupPage.membership_generation
      || (livePage.companies || []).length !== (backupPage.companies || []).length
    ) {
      return {
        ok: false,
        error: "state_drift_stop_before_write",
        live_codes: liveCodes,
        backup_codes: backupCodes,
        report,
        plan,
        backup,
        restore,
      };
    }
    const applied = await applyRegistryRetirementExecute(resolvedStores.BOOKING_KV, {
      ...report,
      raw_registry: {
        manifest: liveAgain.manifest,
        pages: liveAgain.pages.map((page) => ({
          page: page.page,
          membership_generation: page.membership_generation,
          companies: page.companies,
        })),
      },
    });
    return {
      ok: applied.ok === true,
      mode: "execute",
      phase: PHASE_A_REGISTRY_RETIREMENT,
      error: applied.ok ? null : applied.error,
      applied,
      report,
      plan,
      backup,
      restore,
      live_worker_bundle_files: [...LIVE_WORKER_BUNDLE_RETIREMENT_FILES],
    };
  }
  return {
    ok: true,
    mode: "dry_run",
    phase: PHASE_A_REGISTRY_RETIREMENT,
    report,
    plan,
    backup,
    restore,
    live_worker_bundle_files: [...LIVE_WORKER_BUNDLE_RETIREMENT_FILES],
    local_only_files: [...LOCAL_ONLY_RETIREMENT_FILES],
  };
}

const isMain = process.argv[1] && process.argv[1].endsWith("company_retirement_p0.mjs");
if (isMain) {
  runRetirementCli().then((result) => {
    console.log(JSON.stringify({
      ok: result.ok,
      mode: result.mode || null,
      phase: result.phase || null,
      error: result.error || null,
      selection_errors: result.details || null,
      eligible_count: result.report?.eligible_count ?? null,
      blocked_count: result.report?.blocked_count ?? null,
      fail_closed: result.report?.fail_closed ?? null,
      fail_closed_codes: result.report?.fail_closed_codes ?? null,
      risk_groups: result.report?.risk_groups ?? null,
      reconciliation: result.report?.reconciliation ?? null,
      restore: result.restore || null,
      applied_writes: result.applied?.writes || null,
      companies: (result.report?.companies || []).map((row) => ({
        company_code: row.company_code,
        risk_group: row.classification.risk_group,
        phase_a_eligible: row.classification.phase_a_eligible,
        phase_a_blockers: row.classification.phase_a_blockers,
        blockers: row.classification.blockers,
        risks: row.classification.risks,
        counts: row.counts,
        has_registry: row.identity.has_registry_code,
        has_link: row.identity.has_company_link,
        on_registry_page: row.identity.on_registry_page,
      })),
      registry_write_set: (result.plan?.companies || []).map((row) => ({
        company_code: row.company_code,
        action: row.action,
        keys: (row.writes || []).map((write) => ({ key: write.key, kind: write.kind, op: write.op })),
      })),
      backup_dir: result.backup?.dir || null,
      protected_untouched: result.plan?.protected_untouched || [...HARD_PROTECTED_COMPANY_CODES],
      live_worker_bundle_files: result.live_worker_bundle_files || LIVE_WORKER_BUNDLE_RETIREMENT_FILES,
    }, null, 2));
    if (!result.ok && !result.help) process.exitCode = 2;
  }).catch((err) => {
    console.log(JSON.stringify({ ok: false, error: String(err?.message || err) }));
    process.exitCode = 1;
  });
}
