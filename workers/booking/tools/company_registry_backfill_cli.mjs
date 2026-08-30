#!/usr/bin/env node
/**
 * One-time company registry backfill CLI. Default is dry-run.
 * Not a Worker endpoint. Does not deploy. Does not start a cron.
 *
 * Dry-run:
 *   node workers/booking/tools/company_registry_backfill_cli.mjs --dry-run
 *
 * Write mode (do not run unless Christophe explicitly approves):
 *   node workers/booking/tools/company_registry_backfill_cli.mjs --write-registry --i-understand-this-writes-production-registry
 */
import { spawnSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import {
  COMPANY_LINK_CODE_PREFIX,
  PRODUCTION_BOOKING_KV_NAMESPACE_ID,
  WRITE_CONFIRM_FLAG,
  WRITE_FLAG,
  applyBackfillBatch,
  assertProductionNamespace,
  discoverExistingCompanies,
  emptyCheckpoint,
  estimateBackfillCost,
  writeModeAllowed,
} from "../modules/company_registry_backfill.mjs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const REPORT_DIR = join(dirname(fileURLToPath(import.meta.url)), ".backfill-reports");

function argValue(argv, name, fallback = null) {
  const index = argv.indexOf(name);
  if (index < 0 || !argv[index + 1]) return fallback;
  return argv[index + 1];
}

function wranglerBin() {
  return process.env.WRANGLER_BIN
    || join("C:", "_flutter_work", "fluxidi_command_center_premium_billit_live_p0", "node_modules", "wrangler", "bin", "wrangler.js");
}

function runWrangler(args) {
  const result = spawnSync(process.execPath, [wranglerBin(), ...args], {
    encoding: "utf8",
    cwd: ROOT,
    env: process.env,
  });
  if (result.status !== 0) {
    const err = new Error(result.stderr || result.stdout || "wrangler_failed");
    err.code = "wrangler_failed";
    err.detail = (result.stderr || "").slice(0, 400);
    throw err;
  }
  return result.stdout || "";
}

function createWranglerKv({
  namespaceId,
  allowPut = false,
  binding = "BOOKING_KV",
  configPath = join(ROOT, "workers", "booking", "wrangler.toml"),
} = {}) {
  const counts = { get: 0, put: 0, list: 0, got: [], listed: [] };
  const remoteArgs = ["--binding", binding, "--remote", "--config", configPath];
  return {
    counts,
    namespaceId,
    async list({ prefix = COMPANY_LINK_CODE_PREFIX, cursor } = {}) {
      counts.list += 1;
      counts.listed.push(prefix);
      const args = [
        "kv", "key", "list",
        "--prefix", prefix,
        ...remoteArgs,
      ];
      if (cursor) args.push("--cursor", String(cursor));
      const stdout = runWrangler(args);
      const jsonStart = stdout.indexOf("[") >= 0 && (stdout.indexOf("{") < 0 || stdout.indexOf("[") < stdout.indexOf("{"))
        ? stdout.indexOf("[")
        : stdout.indexOf("{");
      const parsed = JSON.parse(jsonStart >= 0 ? stdout.slice(jsonStart) : stdout);
      const keys = Array.isArray(parsed) ? parsed : (parsed.keys || []);
      return {
        keys: keys.map((row) => ({ name: row.name || row })),
        list_complete: !parsed.cursor,
        cursor: parsed.cursor || null,
      };
    },
    async get(key, opts) {
      counts.get += 1;
      counts.got.push(key);
      const result = spawnSync(process.execPath, [
        wranglerBin(),
        "kv", "key", "get",
        key,
        ...remoteArgs,
      ], {
        encoding: "utf8",
        cwd: ROOT,
        env: process.env,
      });
      const stdout = result.stdout || "";
      const stderr = result.stderr || "";
      if (result.status !== 0) {
        if (/not found|does not exist|404|key not found/i.test(`${stdout}\n${stderr}`) || !stdout.trim()) {
          return null;
        }
        const err = new Error(stderr || stdout || "wrangler_get_failed");
        err.code = "wrangler_failed";
        throw err;
      }
      if (!stdout.trim()) return null;
      if (opts === "json" || opts?.type === "json") {
        try {
          return JSON.parse(stdout);
        } catch {
          return null;
        }
      }
      return stdout;
    },
    async put(key, value) {
      if (!allowPut) {
        throw new Error("write_blocked_dry_run");
      }
      counts.put += 1;
      runWrangler([
        "kv", "key", "put",
        key,
        value,
        ...remoteArgs,
      ]);
    },
  };
}

function redactReport(report) {
  return {
    ...report,
    rows: (report.rows || []).map((row) => ({
      company_code: row.company_code,
      display_name: row.display_name,
      lifecycle_status: row.lifecycle_status,
      environment_class: row.environment_class,
      created_at: row.created_at,
      updated_at: row.updated_at,
      present_in_registry: row.present_in_registry,
      present_in_local_shadow: row.present_in_local_shadow,
      eligible: row.eligible,
      reason: row.reason,
      action: row.action || null,
    })),
  };
}

async function main(argv = process.argv.slice(2)) {
  const namespaceId = argValue(argv, "--namespace-id", PRODUCTION_BOOKING_KV_NAMESPACE_ID);
  const ns = assertProductionNamespace(namespaceId);
  if (!ns.ok) {
    console.error(JSON.stringify({ ok: false, error: ns.error }));
    process.exit(2);
  }
  const dryRun = !writeModeAllowed(argv);
  if (!dryRun && !argv.includes("--i-have-christophe-approval")) {
    console.error(JSON.stringify({
      ok: false,
      error: "write_mode_requires_explicit_approval",
      hint: "default is dry-run; do not write production data from this continuation",
    }));
    process.exit(2);
  }
  const shadowCodes = String(argValue(argv, "--shadow-codes", ""))
    .split(",")
    .map((value) => value.trim())
    .filter((value) => /^FLX-[0-9]{4,12}$/.test(value));
  const kv = createWranglerKv({ namespaceId, allowPut: !dryRun });
  const discovered = await discoverExistingCompanies(kv, {
    localShadowCodes: shadowCodes,
  });
  if (!discovered.ok) {
    console.error(JSON.stringify({ ok: false, error: discovered.error }));
    process.exit(2);
  }
  let checkpoint = emptyCheckpoint();
  let applied = { report: [], checkpoint, interrupted: true };
  const batchSize = Number(argValue(argv, "--batch-size", "1000")) || 1000;
  while (applied.interrupted) {
    applied = await applyBackfillBatch(kv, discovered.rows, {
      dryRun,
      batchSize,
      checkpoint,
    });
    checkpoint = applied.checkpoint;
    if (!applied.ok) break;
  }
  const payload = redactReport({
    ok: true,
    dry_run: dryRun,
    namespace_id: namespaceId,
    prefix: COMPANY_LINK_CODE_PREFIX,
    pages: discovered.pages,
    candidate_codes: discovered.candidate_codes,
    rows: discovered.rows.map((row) => {
      const action = applied.report.find((item) => item.company_code === row.company_code);
      return { ...row, action: action?.action || (row.eligible ? "would_upsert" : "skipped_ineligible") };
    }),
    ops: {
      discovery: discovered.ops,
      apply: applied.checkpoint.ops,
    },
    cost: estimateBackfillCost(discovered.candidate_codes.length),
    write_executed: dryRun ? false : true,
  });
  mkdirSync(REPORT_DIR, { recursive: true });
  const out = join(REPORT_DIR, dryRun ? "dry-run.json" : "write-report.json");
  writeFileSync(out, `${JSON.stringify(payload, null, 2)}\n`);
  console.log(JSON.stringify({
    ok: true,
    dry_run: dryRun,
    pages: payload.pages,
    candidate_count: payload.candidate_codes.length,
    eligible: payload.rows.filter((row) => row.eligible).length,
    report: out,
    write_executed: payload.write_executed,
  }, null, 2));
}

if (import.meta.url === `file://${process.argv[1].replace(/\\/g, "/")}` || process.argv[1]?.endsWith("company_registry_backfill_cli.mjs")) {
  main().catch((error) => {
    console.error(JSON.stringify({
      ok: false,
      error: error.code || error.message || "backfill_cli_failed",
    }));
    process.exit(1);
  });
}

export { createWranglerKv, main };
