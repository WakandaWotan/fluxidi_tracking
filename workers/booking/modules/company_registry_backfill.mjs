/**
 * One-time existing-company registry backfill.
 * Default is dry-run. Not a Worker endpoint. Not a cron. Not runtime behaviour.
 *
 * Discovery lists only company_link:index:code: (exact prefix), then keyed
 * GETs of those current index records. No dossier/history/invoice/ride reads.
 */
import {
  COMPANY_REGISTRY_MANIFEST_KEY,
  COMPANY_REGISTRY_PAGE_SIZE,
  publicRegistryFields,
  readRegistrySnapshot,
  registryMaintainCost,
  upsertCompanyRegistryEntry,
} from "./company_registry_index.mjs";

export const COMPANY_LINK_CODE_PREFIX = "company_link:index:code:";
export const COMPANY_LINK_CODE_KEY_RE = /^company_link:index:code:(FLX-[0-9]{4,12}):v1$/;
export const PRODUCTION_BOOKING_KV_NAMESPACE_ID = "6805da1ffefe4a3982b4c419250c59b1";
export const PLAY_REVIEW_COMPANY_CODE = "FLX-00020";
export const WRITE_FLAG = "--write-registry";
export const WRITE_CONFIRM_FLAG = "--i-understand-this-writes-production-registry";
export const DEFAULT_LIST_LIMIT = 1000;
export const DEFAULT_BATCH_SIZE = 10;
export const DEFAULT_MAX_LIST_PAGES = 20;

const PROVEN_ENVIRONMENT = Object.freeze(["production", "test", "review", "local_qa"]);

export function parseCompanyLinkCodeKey(name) {
  const match = String(name || "").match(COMPANY_LINK_CODE_KEY_RE);
  return match ? { key: match[0], company_code: match[1] } : null;
}

export function assertExactPrefix(prefix) {
  if (prefix !== COMPANY_LINK_CODE_PREFIX) {
    return { ok: false, error: "prefix_not_exact" };
  }
  return { ok: true };
}

export function assertProductionNamespace(namespaceId) {
  if (String(namespaceId || "") !== PRODUCTION_BOOKING_KV_NAMESPACE_ID) {
    return { ok: false, error: "namespace_not_production_booking_kv" };
  }
  return { ok: true };
}

export function writeModeAllowed(argv = []) {
  return argv.includes(WRITE_FLAG) && argv.includes(WRITE_CONFIRM_FLAG);
}

export function classifyIndexRecord(record, companyCode, {
  playReviewCode = PLAY_REVIEW_COMPANY_CODE,
} = {}) {
  const code = String(companyCode || record?.company_code || record?.companyCode || "").trim();
  if (!/^FLX-[0-9]{4,12}$/.test(code)) {
    return {
      company_code: code || null,
      display_name: null,
      lifecycle_status: null,
      environment_class: null,
      created_at: null,
      updated_at: null,
      eligible: false,
      reason: "invalid_company_code",
    };
  }
  if (!record) {
    return {
      company_code: code,
      display_name: null,
      lifecycle_status: null,
      environment_class: null,
      created_at: null,
      updated_at: null,
      eligible: false,
      reason: "index_missing",
    };
  }
  const display_name = record.display_name || record.displayName || null;
  const linking = record.linking_enabled ?? record.linkingEnabled;
  const lifecycle_status = linking === false ? "inactive" : "active";
  const rawEnvironment = record.environment_class || record.environmentClass || null;
  let environment_class = PROVEN_ENVIRONMENT.includes(rawEnvironment)
    ? rawEnvironment
    : "unknown";
  if (code === playReviewCode) environment_class = "review";
  const created_at = record.created_at || record.createdAt || null;
  const updated_at = record.updated_at || record.updatedAt || null;
  if (environment_class === "local_qa") {
    return {
      company_code: code,
      display_name,
      lifecycle_status,
      environment_class,
      created_at,
      updated_at,
      eligible: false,
      reason: "local_qa_excluded",
    };
  }
  let reason = "environment_unproven";
  if (lifecycle_status === "inactive") reason = "inactive_index_preserved";
  else if (environment_class === "review") reason = "review_index_eligible";
  else if (environment_class === "production") reason = "explicit_production_index";
  else if (environment_class === "test") reason = "explicit_test_index";
  return {
    company_code: code,
    display_name,
    lifecycle_status,
    environment_class,
    created_at,
    updated_at,
    eligible: true,
    reason,
  };
}

export function reconcileDiscoveredCompany(classified, {
  registryByCode = new Map(),
  localShadowCodes = new Set(),
  productionIndexCodes = new Set(),
} = {}) {
  const code = classified.company_code;
  const inRegistry = registryByCode.has(code);
  const inLocalShadow = localShadowCodes.has(code);
  const inProductionIndex = productionIndexCodes.has(code);
  if (!inProductionIndex && inLocalShadow) {
    return {
      ...classified,
      present_in_registry: false,
      present_in_local_shadow: true,
      eligible: false,
      reason: "local_qa_only",
    };
  }
  return {
    ...classified,
    present_in_registry: inRegistry,
    present_in_local_shadow: inLocalShadow,
    eligible: classified.eligible === true,
    reason: classified.eligible
      ? (inRegistry ? "idempotent_refresh" : classified.reason)
      : classified.reason,
  };
}

export function publicDiscoveryRow(row) {
  return {
    company_code: row.company_code,
    display_name: row.display_name,
    lifecycle_status: row.lifecycle_status,
    environment_class: row.environment_class,
    created_at: row.created_at,
    updated_at: row.updated_at,
    present_in_registry: row.present_in_registry === true,
    present_in_local_shadow: row.present_in_local_shadow === true,
    eligible: row.eligible === true,
    reason: row.reason || null,
  };
}

export function emptyCheckpoint() {
  return {
    cursor: null,
    listed_keys: [],
    processed_codes: [],
    ops: { list: 0, get: 0, put: 0 },
  };
}

export function createMemoryBackfillKv(seed = {}) {
  const map = new Map(Object.entries(seed));
  const counts = { get: 0, put: 0, list: 0, got: [], listed: [] };
  return {
    map,
    counts,
    async get(key, opts) {
      counts.get += 1;
      counts.got.push(key);
      const raw = map.get(key);
      if (raw == null) return null;
      if (opts === "json" || opts?.type === "json") {
        return typeof raw === "string" ? JSON.parse(raw) : raw;
      }
      return typeof raw === "string" ? raw : JSON.stringify(raw);
    },
    async put(key, value) {
      counts.put += 1;
      map.set(key, value);
    },
    async list({ prefix = "", limit = DEFAULT_LIST_LIMIT, cursor } = {}) {
      counts.list += 1;
      counts.listed.push(prefix);
      const names = [...map.keys()].filter((key) => key.startsWith(prefix)).sort();
      const start = cursor ? Number(cursor) || 0 : 0;
      const page = names.slice(start, start + Math.max(1, Number(limit) || DEFAULT_LIST_LIMIT));
      const next = start + page.length;
      return {
        keys: page.map((name) => ({ name })),
        list_complete: next >= names.length,
        cursor: next >= names.length ? null : String(next),
      };
    },
  };
}

export async function discoverCompanyLinkCodeKeys(kv, {
  prefix = COMPANY_LINK_CODE_PREFIX,
  limit = DEFAULT_LIST_LIMIT,
  cursor = null,
  maxPages = DEFAULT_MAX_LIST_PAGES,
} = {}) {
  const exact = assertExactPrefix(prefix);
  if (!exact.ok) return exact;
  const keys = [];
  let pages = 0;
  let next = cursor;
  do {
    pages += 1;
    if (pages > maxPages) {
      return { ok: false, error: "list_page_budget_exceeded", keys, pages, list_ops: pages };
    }
    const page = await kv.list({ prefix, limit, cursor: next });
    for (const entry of page.keys || []) {
      const parsed = parseCompanyLinkCodeKey(entry.name);
      if (parsed) keys.push(parsed);
    }
    next = page.list_complete ? null : page.cursor;
  } while (next);
  return { ok: true, keys, pages, list_ops: pages, next_cursor: null };
}

export async function loadRegistryMembership(kv) {
  const snapshot = await readRegistrySnapshot(kv);
  const byCode = new Map();
  for (const page of snapshot.pages || []) {
    for (const row of page.companies || []) {
      if (row?.company_code) byCode.set(row.company_code, publicRegistryFields(row));
    }
  }
  return {
    available: Boolean(snapshot.manifest?.page_count || snapshot.manifest?.total),
    manifest: snapshot.manifest,
    byCode,
  };
}

export async function discoverExistingCompanies(kv, {
  prefix = COMPANY_LINK_CODE_PREFIX,
  limit = DEFAULT_LIST_LIMIT,
  maxPages = DEFAULT_MAX_LIST_PAGES,
  localShadowCodes = [],
  playReviewCode = PLAY_REVIEW_COMPANY_CODE,
  checkpoint = emptyCheckpoint(),
} = {}) {
  const listed = await discoverCompanyLinkCodeKeys(kv, { prefix, limit, maxPages });
  if (!listed.ok) return listed;
  const productionIndexCodes = new Set(listed.keys.map((row) => row.company_code));
  const registry = await loadRegistryMembership(kv);
  const shadow = new Set(localShadowCodes);
  const rows = [];
  const ops = {
    list: listed.list_ops,
    get: 0,
    put: 0,
  };
  for (const entry of listed.keys) {
    const record = await kv.get(entry.key, { type: "json" });
    ops.get += 1;
    const classified = classifyIndexRecord(record, entry.company_code, { playReviewCode });
    rows.push(reconcileDiscoveredCompany(classified, {
      registryByCode: registry.byCode,
      localShadowCodes: shadow,
      productionIndexCodes,
    }));
  }
  for (const code of shadow) {
    if (productionIndexCodes.has(code)) continue;
    rows.push(reconcileDiscoveredCompany({
      company_code: code,
      display_name: null,
      lifecycle_status: null,
      environment_class: "local_qa",
      created_at: null,
      updated_at: null,
      eligible: false,
      reason: "local_qa_only",
    }, {
      registryByCode: registry.byCode,
      localShadowCodes: shadow,
      productionIndexCodes,
    }));
  }
  rows.sort((a, b) => String(a.company_code).localeCompare(String(b.company_code)));
  return {
    ok: true,
    pages: listed.pages,
    candidate_codes: listed.keys.map((row) => row.company_code),
    rows: rows.map(publicDiscoveryRow),
    registry_available: registry.available,
    registry_count: registry.byCode.size,
    ops: {
      ...ops,
      get: ops.get + 1 + (Number(registry.manifest?.page_count) || 0),
    },
    checkpoint: {
      ...checkpoint,
      cursor: null,
      listed_keys: listed.keys.map((row) => row.key),
      ops: { ...ops, get: ops.get + 1 + (Number(registry.manifest?.page_count) || 0) },
    },
  };
}

export async function applyBackfillBatch(kv, rows, {
  dryRun = true,
  batchSize = DEFAULT_BATCH_SIZE,
  checkpoint = emptyCheckpoint(),
  nowIso = new Date().toISOString(),
} = {}) {
  const processed = new Set(checkpoint.processed_codes || []);
  const report = [];
  const ops = { ...(checkpoint.ops || { list: 0, get: 0, put: 0 }) };
  let handled = 0;
  for (const row of rows || []) {
    if (processed.has(row.company_code)) {
      report.push({ ...publicDiscoveryRow(row), action: "skipped_already_processed" });
      continue;
    }
    if (row.eligible !== true) {
      processed.add(row.company_code);
      report.push({ ...publicDiscoveryRow(row), action: "skipped_ineligible" });
      continue;
    }
    if (handled >= batchSize) {
      return {
        ok: true,
        dryRun,
        interrupted: true,
        report,
        checkpoint: {
          cursor: checkpoint.cursor || null,
          listed_keys: checkpoint.listed_keys || [],
          processed_codes: [...processed],
          ops,
        },
      };
    }
    handled += 1;
    if (dryRun) {
      processed.add(row.company_code);
      report.push({ ...publicDiscoveryRow(row), action: "would_upsert" });
      continue;
    }
    const beforePuts = kv.counts?.put ?? 0;
    const result = await upsertCompanyRegistryEntry(kv, {
      company_code: row.company_code,
      display_name: row.display_name,
      lifecycle_status: row.lifecycle_status,
      environment_class: row.environment_class,
      created_at: row.created_at,
      updated_at: row.updated_at,
    }, { nowIso });
    if (kv.counts) ops.put += Math.max(0, kv.counts.put - beforePuts);
    if (!result.ok) {
      return {
        ok: false,
        error: result.error || "registry_upsert_failed",
        dryRun,
        interrupted: true,
        report,
        checkpoint: {
          cursor: checkpoint.cursor || null,
          listed_keys: checkpoint.listed_keys || [],
          processed_codes: [...processed],
          ops,
        },
      };
    }
    processed.add(row.company_code);
    report.push({ ...publicDiscoveryRow(row), action: "upserted", attempts: result.attempts });
  }
  return {
    ok: true,
    dryRun,
    interrupted: false,
    report,
    checkpoint: {
      cursor: null,
      listed_keys: checkpoint.listed_keys || [],
      processed_codes: [...processed],
      ops,
    },
  };
}

function costForCount(n, { registryAlreadyPopulated = false } = {}) {
  const companies = Math.max(0, Number(n) || 0);
  const listPages = companies === 0 ? 1 : Math.ceil(companies / DEFAULT_LIST_LIMIT);
  const registryPages = companies === 0 ? 0 : Math.ceil(companies / COMPANY_REGISTRY_PAGE_SIZE);
  const dryGets = companies + 1 + (registryAlreadyPopulated ? registryPages : 0);
  const maintain = registryMaintainCost(Math.max(companies, 1));
  return {
    companies,
    dry_run: {
      list_ops: listPages,
      index_gets: companies,
      registry_manifest_gets: 1,
      registry_page_gets: registryAlreadyPopulated ? registryPages : 0,
      puts: 0,
      total_kv: listPages + dryGets,
    },
    one_time_write_upper_bound: {
      list_ops: listPages,
      index_gets: companies,
      registry_kv_per_company: maintain.total_kv,
      registry_kv_total: companies * maintain.total_kv,
      total_kv: listPages + companies + (companies * maintain.total_kv),
      note: "upper bound: every company pays the full confirm-all-pages maintain cost at final size",
    },
    idle_after: {
      list_ops: 0,
      keyed_gets: 0,
      puts: 0,
      cron: false,
      recurring: false,
      total_kv: 0,
    },
  };
}

export function estimateBackfillCost(actualCount) {
  return {
    actual: costForCount(actualCount),
    projected: {
      10: costForCount(10),
      100: costForCount(100),
      1000: costForCount(1000),
    },
    idle_after: costForCount(actualCount).idle_after,
  };
}

export function indexRecordSeed(code, extras = {}) {
  return JSON.stringify({
    company_code: code,
    display_name: extras.display_name || code,
    linking_enabled: extras.linking_enabled !== false,
    source: extras.source || "admin",
    created_at: extras.created_at || "2026-05-12T00:00:00.000Z",
    updated_at: extras.updated_at || "2026-08-19T05:58:32.000Z",
    environment_class: extras.environment_class || undefined,
  });
}
