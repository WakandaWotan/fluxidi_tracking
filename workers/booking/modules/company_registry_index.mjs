/**
 * Event-maintained company registry. Manifest + fixed-size pages.
 * No cron, no KV.list, no rebuild sweep, no silent truncation.
 *
 * Concurrency: write-ahead per-code record, then optimistic membership
 * pages with a write_token. applyUpsert never drops codes from the snapshot
 * it read. Post-write confirm retries when the token mismatches or any
 * previously observed code is missing. Residual last-write races on two
 * brand-new codes are retried; readers fail closed if total !== membership.
 */

export const COMPANY_REGISTRY_SCHEMA = 1;
export const COMPANY_REGISTRY_PAGE_SIZE = 100;
export const COMPANY_REGISTRY_MANIFEST_KEY = "company_registry:manifest:v1";
export const REGISTRY_LIFECYCLE = Object.freeze(["active", "inactive", "deleted"]);
export const REGISTRY_ENVIRONMENT = Object.freeze([
  "production",
  "test",
  "review",
  "local_qa",
  "unknown",
]);

export function registryPageKey(page) {
  const n = Number(page);
  if (!Number.isInteger(n) || n < 1) return null;
  return `company_registry:page:${n}:v1`;
}

export function registryCodeKey(companyCode) {
  return `company_registry:code:${companyCode}:v1`;
}

export function emptyRegistryManifest() {
  return {
    schema_version: COMPANY_REGISTRY_SCHEMA,
    membership_generation: 0,
    page_count: 0,
    page_size: COMPANY_REGISTRY_PAGE_SIZE,
    total: 0,
    updated_at: null,
    write_token: null,
  };
}

export function publicRegistryFields(input = {}) {
  const lifecycle = REGISTRY_LIFECYCLE.includes(input.lifecycle_status)
    ? input.lifecycle_status
    : "active";
  const environment = REGISTRY_ENVIRONMENT.includes(input.environment_class)
    ? input.environment_class
    : "unknown";
  return {
    company_code: input.company_code,
    display_name: input.display_name || null,
    lifecycle_status: lifecycle,
    environment_class: environment,
    created_at: input.created_at || null,
    updated_at: input.updated_at || null,
  };
}

export function registryReadPlan(registeredCount, pageSize = COMPANY_REGISTRY_PAGE_SIZE) {
  const n = Number(registeredCount);
  const size = Number(pageSize) > 0 ? Number(pageSize) : COMPANY_REGISTRY_PAGE_SIZE;
  if (!Number.isFinite(n) || n < 0) {
    return { manifest_gets: 1, page_gets: 0, total_gets: 1 };
  }
  const pages = n === 0 ? 0 : Math.ceil(n / size);
  return { manifest_gets: 1, page_gets: pages, total_gets: 1 + pages };
}

export function registryMaintainCost(registeredCount, pageSize = COMPANY_REGISTRY_PAGE_SIZE) {
  const pages = registeredCount === 0 ? 0 : Math.ceil(registeredCount / pageSize);
  const pageGets = pages;
  return {
    code_put: 1,
    manifest_gets: 2,
    page_gets: pageGets * 2,
    page_puts: 1,
    manifest_puts: 1,
    total_kv: 1 + 2 + (pageGets * 2) + 1 + 1,
    list_ops: 0,
    scheduled_rebuild: false,
  };
}

function cloneSnapshot(snapshot = {}) {
  return {
    manifest: { ...(snapshot.manifest || emptyRegistryManifest()) },
    pages: (snapshot.pages || []).map((page) => ({
      page: page.page,
      membership_generation: page.membership_generation,
      companies: (page.companies || []).map((row) => ({ ...row })),
    })),
  };
}

export function codesOf(snapshot) {
  const codes = new Set();
  for (const page of snapshot.pages || []) {
    for (const row of page.companies || []) {
      if (row?.company_code) codes.add(row.company_code);
    }
  }
  return codes;
}

export function applyRegistryUpsert(snapshot, entry) {
  const next = cloneSnapshot(snapshot);
  const { manifest, pages } = next;
  if (!manifest.page_size) manifest.page_size = COMPANY_REGISTRY_PAGE_SIZE;
  let found = null;
  for (const page of pages) {
    const idx = page.companies.findIndex((row) => row.company_code === entry.company_code);
    if (idx >= 0) {
      page.companies[idx] = { ...page.companies[idx], ...entry };
      found = page;
      break;
    }
  }
  if (found) {
    manifest.updated_at = entry.updated_at;
    manifest.total = [...codesOf(next)].length;
    return { ...next, membershipChanged: false };
  }
  const last = pages[pages.length - 1];
  if (!last || last.companies.length >= manifest.page_size) {
    pages.push({
      page: pages.length + 1,
      membership_generation: manifest.membership_generation + 1,
      companies: [entry],
    });
    manifest.page_count = pages.length;
  } else {
    last.companies.push(entry);
  }
  manifest.membership_generation += 1;
  for (const page of pages) page.membership_generation = manifest.membership_generation;
  manifest.total = [...codesOf(next)].length;
  manifest.updated_at = entry.updated_at;
  return { ...next, membershipChanged: true };
}

async function kvGetJson(kv, key) {
  const raw = await kv.get(key, { type: "json" });
  if (raw != null) return raw;
  const text = await kv.get(key);
  if (!text) return null;
  if (typeof text === "object") return text;
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

export async function readRegistrySnapshot(kv) {
  const manifest = (await kvGetJson(kv, COMPANY_REGISTRY_MANIFEST_KEY)) || emptyRegistryManifest();
  const pages = [];
  for (let i = 1; i <= (Number(manifest.page_count) || 0); i += 1) {
    const page = await kvGetJson(kv, registryPageKey(i));
    if (page) pages.push(page);
  }
  return { manifest, pages };
}

export async function writeRegistrySnapshot(kv, snapshot, writeToken) {
  const manifest = { ...snapshot.manifest, write_token: writeToken };
  for (const page of snapshot.pages || []) {
    await kv.put(registryPageKey(page.page), JSON.stringify({
      page: page.page,
      membership_generation: manifest.membership_generation,
      companies: page.companies,
    }));
  }
  await kv.put(COMPANY_REGISTRY_MANIFEST_KEY, JSON.stringify(manifest));
  return manifest;
}

function confirmOk(before, intended, confirm, entry, token) {
  if (confirm.manifest.write_token !== token) return false;
  const confirmCodes = codesOf(confirm);
  if (!confirmCodes.has(entry.company_code)) return false;
  for (const code of codesOf(before)) {
    if (!confirmCodes.has(code)) return false;
  }
  for (const code of codesOf(intended)) {
    if (!confirmCodes.has(code)) return false;
  }
  if (confirmCodes.size !== Number(confirm.manifest.total || 0)) return false;
  return true;
}

export async function upsertCompanyRegistryEntry(kv, input, {
  nowIso = new Date().toISOString(),
  maxAttempts = 8,
  randomToken = () => (globalThis.crypto?.randomUUID ? crypto.randomUUID() : `tok_${Date.now()}_${Math.random()}`),
} = {}) {
  if (!kv || typeof kv.get !== "function" || typeof kv.put !== "function") {
    return { ok: false, error: "kv_unbound" };
  }
  const code = String(input?.company_code || "").trim();
  if (!/^FLX-[0-9]{4,12}$/.test(code)) return { ok: false, error: "invalid_company_code" };
  const entry = publicRegistryFields({
    ...input,
    company_code: code,
    created_at: input.created_at || nowIso,
    updated_at: input.updated_at || nowIso,
  });
  await kv.put(registryCodeKey(code), JSON.stringify(entry));
  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    const before = await readRegistrySnapshot(kv);
    const intended = applyRegistryUpsert(before, entry);
    const token = randomToken();
    await writeRegistrySnapshot(kv, intended, token);
    const confirm = await readRegistrySnapshot(kv);
    if (confirmOk(before, intended, confirm, entry, token)) {
      return {
        ok: true,
        attempts: attempt,
        membershipChanged: intended.membershipChanged === true,
        manifest: confirm.manifest,
      };
    }
  }
  return { ok: false, error: "registry_concurrent_update" };
}

export function createMemoryRegistryKv(seed = {}) {
  const map = new Map(Object.entries(seed));
  return {
    map,
    async get(key, opts) {
      const raw = map.get(key);
      if (raw == null) return null;
      if (opts === "json" || opts?.type === "json") {
        return typeof raw === "string" ? JSON.parse(raw) : raw;
      }
      return typeof raw === "string" ? raw : JSON.stringify(raw);
    },
    async put(key, value) {
      map.set(key, value);
    },
  };
}
