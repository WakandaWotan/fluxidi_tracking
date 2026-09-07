import { mkdirSync, writeFileSync, readFileSync } from "node:fs";
import { join } from "node:path";
import {
  COMPANY_REGISTRY_MANIFEST_KEY,
  registryCodeKey,
  registryPageKey,
} from "../../modules/company_registry_index.mjs";
import { registryTombstoneKey } from "../../modules/company_registry_tombstone_guard.mjs";
import { sha256Hex } from "./company_retirement_inventory.mjs";
import { companyLinkCodeKey } from "./company_retirement_keys.mjs";
import { isSecretBearingKey } from "./company_retirement_policy.mjs";

export function defaultBackupRoot() {
  return "C:\\_flutter_work\\_local_backups\\fluxidi_company_registry_retirement_p0";
}

function stableJson(value) {
  return JSON.stringify(value);
}

const REGISTRY_BACKUP_ALLOWED_TOKEN_FIELDS = new Set(["write_token"]);

function assertNoSecrets(value, path = "root") {
  if (!value || typeof value !== "object") return;
  if (Array.isArray(value)) {
    value.forEach((item, idx) => assertNoSecrets(item, `${path}[${idx}]`));
    return;
  }
  for (const [key, child] of Object.entries(value)) {
    if (isSecretBearingKey(key) && !REGISTRY_BACKUP_ALLOWED_TOKEN_FIELDS.has(key)) {
      throw new Error(`secret_field_forbidden_in_registry_backup:${path}.${key}`);
    }
    assertNoSecrets(child, `${path}.${key}`);
  }
}

function rawText(value, fallbackObject) {
  if (typeof value === "string" && value.length) return value;
  if (fallbackObject == null) return null;
  return stableJson(fallbackObject);
}

export function collectRegistryRawBackup(report) {
  const records = [];
  const manifest = report.raw_registry?.manifest || null;
  const pages = report.raw_registry?.pages || [];
  if (manifest) {
    assertNoSecrets(manifest, "manifest");
    const text = rawText(report.raw_registry.manifest_text, manifest);
    records.push({
      key: COMPANY_REGISTRY_MANIFEST_KEY,
      kind: "registry_manifest",
      value: manifest,
      raw: text,
      sha256: sha256Hex(text),
    });
  }
  for (const page of pages) {
    const value = {
      page: page.page,
      membership_generation: page.membership_generation,
      companies: page.companies,
    };
    assertNoSecrets(value, `page.${page.page}`);
    const text = rawText(page.text, value);
    records.push({
      key: registryPageKey(page.page),
      kind: "registry_page",
      value,
      raw: text,
      sha256: sha256Hex(text),
    });
  }
  for (const company of report.companies || []) {
    if (company.raw?.registry_code) {
      assertNoSecrets(company.raw.registry_code, `registry_code.${company.company_code}`);
      const text = rawText(company.raw.registry_code_text, company.raw.registry_code);
      records.push({
        key: registryCodeKey(company.company_code),
        kind: "registry_code",
        company_code: company.company_code,
        value: company.raw.registry_code,
        raw: text,
        sha256: sha256Hex(text),
      });
    }
    if (company.raw?.company_link) {
      assertNoSecrets(company.raw.company_link, `company_link.${company.company_code}`);
      const text = rawText(company.raw.company_link_text, company.raw.company_link);
      records.push({
        key: companyLinkCodeKey(company.company_code),
        kind: "company_link",
        company_code: company.company_code,
        value: company.raw.company_link,
        raw: text,
        sha256: sha256Hex(text),
      });
    }
  }
  return {
    schema_version: 1,
    generated_at: report.generated_at,
    phase: "registry_retirement",
    records,
    tombstone_keys_not_present: (report.companies || [])
      .filter((row) => !row.identity?.has_tombstone)
      .map((row) => registryTombstoneKey(row.company_code)),
  };
}

export function writeRetirementBackup(backupRoot, report, plan) {
  const stamp = String(report.generated_at || new Date().toISOString()).replace(/[:.]/g, "-");
  const dir = join(backupRoot, stamp);
  mkdirSync(dir, { recursive: true });
  const rawBackup = collectRegistryRawBackup(report);
  const publicReport = {
    generated_at: report.generated_at,
    phase: report.phase,
    eligible_count: report.eligible_count,
    blocked_count: report.blocked_count,
    fail_closed: report.fail_closed,
    fail_closed_codes: report.fail_closed_codes,
    risk_groups: report.risk_groups,
    reconciliation: report.reconciliation,
    registry_snapshot: report.registry_snapshot,
    companies: (report.companies || []).map((row) => ({
      company_code: row.company_code,
      identity: {
        has_company_link: row.identity?.has_company_link,
        has_registry_code: row.identity?.has_registry_code,
        has_tombstone: row.identity?.has_tombstone,
        on_registry_page: row.identity?.on_registry_page,
        registry_pages: row.identity?.registry_pages,
        source: row.identity?.source,
        linking_enabled: row.identity?.linking_enabled,
        registry: row.identity?.registry,
      },
      counts: row.counts,
      integrations: row.integrations,
      classification: row.classification,
      restore_checksums: row.restore_checksums,
    })),
  };
  const manifest = {
    schema_version: 1,
    generated_at: report.generated_at,
    phase: "registry_retirement",
    company_count: report.companies.length,
    eligible_count: report.eligible_count,
    blocked_count: report.blocked_count,
    fail_closed: report.fail_closed,
    codes: report.companies.map((row) => row.company_code),
    record_count: rawBackup.records.length,
    checksums: rawBackup.records.map((row) => ({
      key: row.key,
      kind: row.kind,
      company_code: row.company_code || null,
      sha256: row.sha256,
    })),
    contents: [
      "manifest.json",
      "sanitized_inventory.json",
      "retirement_plan.json",
      "raw_registry_backup.json",
    ],
    secrets: "omitted",
    git: false,
    restore: "offline_put_of_raw_registry_backup_records",
  };
  const inventoryPath = join(dir, "sanitized_inventory.json");
  const planPath = join(dir, "retirement_plan.json");
  const rawPath = join(dir, "raw_registry_backup.json");
  const manifestPath = join(dir, "manifest.json");
  writeFileSync(inventoryPath, JSON.stringify(publicReport, null, 2));
  writeFileSync(planPath, JSON.stringify(plan, null, 2));
  writeFileSync(rawPath, JSON.stringify(rawBackup, null, 2));
  manifest.inventory_sha256 = sha256Hex(JSON.stringify(publicReport));
  manifest.plan_sha256 = sha256Hex(JSON.stringify(plan));
  manifest.raw_backup_sha256 = sha256Hex(JSON.stringify(rawBackup));
  writeFileSync(manifestPath, JSON.stringify(manifest, null, 2));
  return {
    dir,
    files: [manifestPath, inventoryPath, planPath, rawPath],
    manifest,
    raw_backup: rawBackup,
  };
}

export function readRegistryRawBackup(dir) {
  return JSON.parse(readFileSync(join(dir, "raw_registry_backup.json"), "utf8"));
}

export async function restoreRegistryBackup(kv, rawBackup) {
  const restored = [];
  for (const record of rawBackup.records || []) {
    const text = typeof record.raw === "string" ? record.raw : JSON.stringify(record.value);
    await kv.put(record.key, text);
    restored.push({
      key: record.key,
      sha256: sha256Hex(text),
      expected: record.sha256,
    });
  }
  for (const tombstoneKey of rawBackup.tombstone_keys_not_present || []) {
    if (typeof kv.delete === "function") {
      await kv.delete(tombstoneKey);
    }
  }
  const mismatches = restored.filter((row) => row.sha256 !== row.expected);
  return {
    ok: mismatches.length === 0,
    restored_count: restored.length,
    mismatches,
  };
}

export function registryStateChecksums(kvMap, codes, pageCount = 1) {
  const keys = [
    COMPANY_REGISTRY_MANIFEST_KEY,
    ...Array.from({ length: pageCount }, (_, i) => registryPageKey(i + 1)),
    ...codes.flatMap((code) => [
      registryCodeKey(code),
      companyLinkCodeKey(code),
      registryTombstoneKey(code),
    ]),
  ];
  const checksums = {};
  for (const key of keys) {
    const raw = kvMap.get(key);
    checksums[key] = raw == null ? null : sha256Hex(typeof raw === "string" ? raw : JSON.stringify(raw));
  }
  return checksums;
}
