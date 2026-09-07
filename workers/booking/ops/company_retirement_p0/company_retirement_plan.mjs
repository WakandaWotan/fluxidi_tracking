import {
  applyRegistryRemove,
  COMPANY_REGISTRY_MANIFEST_KEY,
  codesOf,
  publicRegistryFields,
  registryCodeKey,
  registryPageKey,
  writeRegistrySnapshot,
} from "../../modules/company_registry_index.mjs";
import {
  EXPLICIT_RETIREMENT_CANDIDATES,
  isAllowedPhaseAWriteKey,
} from "./company_retirement_policy.mjs";
import {
  assertProtectedCompanyImmutable,
  HARD_PROTECTED_COMPANY_CODES,
  isHardProtectedCompanyCode,
  registryTombstoneKey,
  tombstoneRecord,
} from "../../modules/company_registry_tombstone_guard.mjs";
import {
  ACTIVE_PHASE,
  FORBIDDEN_PHASE_A_KEY_MARKERS,
  PHASE_B_FULL_PURGE,
  isForbiddenPhaseAKey,
} from "./company_retirement_policy.mjs";
import { companyLinkCodeKey } from "./company_retirement_keys.mjs";

export { tombstoneRecord };

export function applyFullPurge() {
  throw new Error("phase_b_full_purge_disabled");
}

export function remainingCodesAfterRetirement(snapshot, retireCodes) {
  const retire = new Set(retireCodes);
  return [...codesOf(snapshot)].filter((code) => !retire.has(code));
}

export function assertUnknownCompaniesPreserved(beforeSnapshot, afterSnapshot, retireCodes) {
  const before = [...codesOf(beforeSnapshot || {})];
  const after = [...codesOf(afterSnapshot || {})];
  const mustKeep = remainingCodesAfterRetirement(beforeSnapshot || {}, retireCodes);
  const dropped = mustKeep.filter((code) => !after.includes(code));
  if (dropped.length) {
    return { ok: false, error: "unknown_or_non_candidate_company_would_be_dropped", dropped, remaining: after };
  }
  if (before.includes("FLX-00001") && !after.includes("FLX-00001")) {
    return { ok: false, error: "protected_company_dropped", dropped: ["FLX-00001"], remaining: after };
  }
  if (before.includes("FLX-00020") && !after.includes("FLX-00020")) {
    return { ok: false, error: "protected_company_dropped", dropped: ["FLX-00020"], remaining: after };
  }
  return { ok: true, remaining: after, preserved: mustKeep };
}

export function markRegistryCodeRetired(existing, companyCode, nowIso) {
  const blocked = assertProtectedCompanyImmutable(companyCode, "registry_code_retire");
  if (!blocked.ok) return { ok: false, ...blocked };
  const base = existing && typeof existing === "object" && !Array.isArray(existing)
    ? existing
    : { company_code: companyCode };
  return {
    ok: true,
    value: {
      ...publicRegistryFields({
        ...base,
        company_code: companyCode,
        lifecycle_status: "retired",
        updated_at: nowIso,
      }),
      retired: true,
      retired_at: nowIso,
      retired_reason: "ops_company_retirement_p0_phase_a",
    },
  };
}

export function markCompanyLinkRetired(existing, companyCode, nowIso) {
  const blocked = assertProtectedCompanyImmutable(companyCode, "company_link_retire");
  if (!blocked.ok) return { ok: false, ...blocked };
  if (!existing || typeof existing !== "object" || Array.isArray(existing)) {
    return { ok: true, value: null, skipped: "company_link_absent" };
  }
  return {
    ok: true,
    value: {
      ...existing,
      company_code: existing.company_code || companyCode,
      linking_enabled: false,
      linkingEnabled: false,
      lifecycle_status: "retired",
      retired: true,
      retired_at: nowIso,
      retired_reason: "ops_company_retirement_p0_phase_a",
    },
  };
}

function pageKeysFromInventory(inventory) {
  const pages = new Set();
  for (const page of inventory.registry_membership?.pages || []) {
    if (Number.isInteger(page) && page >= 1) pages.add(page);
  }
  if (inventory.identity?.has_registry_code || inventory.identity?.on_registry_page) {
    pages.add(1);
  }
  return [...pages];
}

export function registryWriteSetForCandidate(inventory, { nowIso = new Date().toISOString() } = {}) {
  const code = inventory.company_code;
  const blocked = assertProtectedCompanyImmutable(code, "registry_retirement");
  if (!blocked.ok) {
    return {
      company_code: code,
      action: "skip_protected",
      writes: [],
      deletes: [],
    };
  }
  const writes = [];
  writes.push({
    store: "BOOKING_KV",
    key: registryTombstoneKey(code),
    kind: "tombstone",
    op: "put",
    value: tombstoneRecord(code, nowIso),
  });
  if (inventory.identity?.has_registry_code || inventory.raw?.registry_code) {
    const marked = markRegistryCodeRetired(inventory.raw?.registry_code || {
      company_code: code,
      lifecycle_status: inventory.identity?.registry?.lifecycle_status || "active",
    }, code, nowIso);
    writes.push({
      store: "BOOKING_KV",
      key: registryCodeKey(code),
      kind: "registry_code_retired",
      op: "put",
      note: "Mark recoverable retired; do not delete the key",
    });
    if (!marked.ok) {
      return { company_code: code, action: "blocked", writes: [], deletes: [], error: marked.error };
    }
  }
  if (inventory.identity?.has_company_link || inventory.raw?.company_link) {
    writes.push({
      store: "BOOKING_KV",
      key: companyLinkCodeKey(code),
      kind: "company_link_retired",
      op: "put",
      note: "Mark linking_enabled=false and retired; never delete the company-link",
    });
  }
  for (const page of pageKeysFromInventory(inventory)) {
    writes.push({
      store: "BOOKING_KV",
      key: registryPageKey(page),
      kind: "registry_page",
      op: "put",
      shared: true,
      note: "Rewrite page without this company_code",
    });
  }
  if (inventory.identity?.has_registry_code || inventory.identity?.on_registry_page) {
    writes.push({
      store: "BOOKING_KV",
      key: COMPANY_REGISTRY_MANIFEST_KEY,
      kind: "registry_manifest",
      op: "put",
      shared: true,
      note: "Rewrite manifest totals after page membership change",
    });
  }
  const illegal = writes.filter((row) => isForbiddenPhaseAKey(row.key));
  if (illegal.length) {
    return {
      company_code: code,
      action: "blocked",
      writes: [],
      deletes: [],
      error: "forbidden_phase_a_key",
    };
  }
  return {
    company_code: code,
    action: "registry_retire",
    risk_group: inventory.classification?.risk_group || null,
    writes,
    deletes: [],
    out_of_scope: [
      "bookings",
      "payments",
      "invoices",
      "drivers",
      "vehicles",
      "customers",
      "sessions",
      "mollie",
      "billit",
      "chiron",
      "r2",
    ],
  };
}

export function buildRetirementPlan(report, { nowIso = new Date().toISOString() } = {}) {
  const companies = [];
  const sharedKeys = new Set();
  for (const inventory of report.companies) {
    const row = registryWriteSetForCandidate(inventory, { nowIso });
    for (const write of row.writes || []) {
      if (write.shared) sharedKeys.add(write.key);
    }
    companies.push(row);
  }
  return {
    mode: "dry_run_plan",
    phase: ACTIVE_PHASE,
    phase_b: PHASE_B_FULL_PURGE,
    phase_b_executable: false,
    now_iso: nowIso,
    protected_untouched: [...HARD_PROTECTED_COMPANY_CODES],
    external_integrations_untouched: ["mollie", "billit", "chiron"],
    operational_data_untouched: true,
    fail_closed: report.fail_closed === true,
    shared_registry_keys: [...sharedKeys],
    companies,
    later_phase_a_execute_would: [
      "Write company_registry:tombstone:{CODE}:v1 for each approved explicit code",
      "Mark company_registry:code:{CODE}:v1 as lifecycle_status=retired (keep key)",
      "Mark company_link:index:code:{CODE}:v1 as linking_enabled=false / retired (keep key)",
      "Rewrite affected company_registry page(s) and manifest:v1",
      "Never mutate FLX-00001 or FLX-00020",
      "Never delete bookings, payments, invoices, drivers, vehicles, sessions, tokens, R2, or integrations",
      "Never call Mollie, Billit or Chiron APIs",
    ],
    later_phase_b_would: [
      "Disabled. Full-purge cannot run in this phase, including with flags.",
    ],
    forbidden_key_markers: [...FORBIDDEN_PHASE_A_KEY_MARKERS],
  };
}

export function plannedPhaseAWrites(report, { nowIso = new Date().toISOString() } = {}) {
  const plan = buildRetirementPlan(report, { nowIso });
  const keys = [];
  for (const company of plan.companies) {
    for (const write of company.writes || []) keys.push(write.key);
  }
  return [...new Set(keys)];
}

export async function applyRegistryRetirementExecute(kv, report, {
  nowIso = new Date().toISOString(),
  snapshot = null,
} = {}) {
  if (report.fail_closed) {
    return { ok: false, error: "fail_closed", restored: false };
  }
  const writes = [];
  const retireCodes = (report.companies || []).map((row) => row.company_code);
  if (retireCodes.some((code) => isHardProtectedCompanyCode(code) || code === "FLX-91611")) {
    return { ok: false, error: "forbidden_or_unknown_company_in_execute_set" };
  }
  const planned = plannedPhaseAWrites(report, { nowIso });
  if (planned.some((key) => !isAllowedPhaseAWriteKey(key, retireCodes))) {
    return { ok: false, error: "forbidden_phase_a_key" };
  }
  const beforeSnapshot = snapshot || (report.raw_registry
    ? {
      manifest: report.raw_registry.manifest,
      pages: report.raw_registry.pages,
    }
    : null);
  let nextSnapshot = beforeSnapshot
    ? {
      manifest: beforeSnapshot.manifest,
      pages: beforeSnapshot.pages,
    }
    : null;
  if (nextSnapshot) {
    for (const inventory of report.companies) {
      nextSnapshot = applyRegistryRemove(nextSnapshot, inventory.company_code);
      if (nextSnapshot.blocked === "protected_company") {
        return { ok: false, error: "protected_company" };
      }
    }
    const preserved = assertUnknownCompaniesPreserved(beforeSnapshot, nextSnapshot, retireCodes);
    if (!preserved.ok) return preserved;
  }
  for (const inventory of report.companies) {
    if (isHardProtectedCompanyCode(inventory.company_code)) {
      return { ok: false, error: "protected_company", company_code: inventory.company_code };
    }
    if (inventory.classification?.phase_a_blocked) {
      return { ok: false, error: "phase_a_blocked", company_code: inventory.company_code };
    }
    const tombstoneKey = registryTombstoneKey(inventory.company_code);
    await kv.put(tombstoneKey, JSON.stringify(tombstoneRecord(inventory.company_code, nowIso)));
    writes.push(tombstoneKey);

    const codeKey = registryCodeKey(inventory.company_code);
    const existingCode = inventory.raw?.registry_code
      || (typeof kv.get === "function" ? await kv.get(codeKey) : null);
    const parsedCode = typeof existingCode === "string"
      ? JSON.parse(existingCode)
      : existingCode;
    if (parsedCode) {
      const marked = markRegistryCodeRetired(parsedCode, inventory.company_code, nowIso);
      if (!marked.ok) return { ok: false, error: marked.error };
      await kv.put(codeKey, JSON.stringify(marked.value));
      writes.push(codeKey);
    }

    const linkKey = companyLinkCodeKey(inventory.company_code);
    const existingLink = inventory.raw?.company_link
      || (typeof kv.get === "function" ? await kv.get(linkKey) : null);
    const parsedLink = typeof existingLink === "string"
      ? JSON.parse(existingLink)
      : existingLink;
    if (parsedLink) {
      const markedLink = markCompanyLinkRetired(parsedLink, inventory.company_code, nowIso);
      if (!markedLink.ok) return { ok: false, error: markedLink.error };
      if (markedLink.value) {
        await kv.put(linkKey, JSON.stringify(markedLink.value));
        writes.push(linkKey);
      }
    }
  }
  if (nextSnapshot && typeof kv.put === "function") {
    const written = await writeRegistrySnapshot(
      kv,
      nextSnapshot,
      `retire-registry-${nowIso}`,
    );
    writes.push(COMPANY_REGISTRY_MANIFEST_KEY);
    for (const page of nextSnapshot.pages || []) {
      writes.push(registryPageKey(page.page));
    }
    nextSnapshot = { ...nextSnapshot, manifest: written };
  }
  return {
    ok: true,
    phase: ACTIVE_PHASE,
    writes,
    snapshot: nextSnapshot,
    deletes: [],
  };
}

export async function applyRetirementExecute(kv, report, options = {}) {
  if (options.phase === PHASE_B_FULL_PURGE || options.fullPurge === true) {
    return applyFullPurge();
  }
  return applyRegistryRetirementExecute(kv, report, options);
}

export function restoreChecksumsMatch(before, after) {
  const left = before?.restore_checksums || {};
  const right = after?.restore_checksums || {};
  return left.company_link === right.company_link
    && left.registry_code === right.registry_code
    && left.registry_page === right.registry_page
    && left.registry_manifest === right.registry_manifest;
}
