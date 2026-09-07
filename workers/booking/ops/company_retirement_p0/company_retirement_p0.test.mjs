import assert from "node:assert/strict";
import test from "node:test";
import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

import {
  applyRegistryRemove,
  applyRegistryUpsert,
  COMPANY_REGISTRY_MANIFEST_KEY,
  createMemoryRegistryKv,
  emptyRegistryManifest,
  isCompanyRegistryRevoked,
  isHardProtectedCompanyCode,
  publicRegistryFields,
  registryCodeKey,
  registryPageKey,
  registryTombstoneKey,
  upsertCompanyRegistryEntry,
} from "../../modules/company_registry_index.mjs";
import {
  EXECUTE_CONFIRMATION_TEXT,
  EXPLICIT_RETIREMENT_CANDIDATES,
  HARD_PROTECTED_COMPANY_CODES,
  LEGACY_EXECUTE_CONFIRMATION_TEXT,
  LIVE_WORKER_BUNDLE_RETIREMENT_FILES,
  RISK_GROUPS,
  assertExecuteAuthorization,
  assertFullPurgeForbidden,
  looksLikeWildcardSelection,
  selectRetirementCodes,
} from "./company_retirement_policy.mjs";
import { createMemoryKv, parseWranglerJson } from "./company_retirement_stores.mjs";
import { classifyCandidate, inventorySelection } from "./company_retirement_inventory.mjs";
import {
  applyFullPurge,
  applyRegistryRetirementExecute,
  assertUnknownCompaniesPreserved,
  buildRetirementPlan,
  tombstoneRecord,
} from "./company_retirement_plan.mjs";
import { isAllowedPhaseAWriteKey } from "./company_retirement_policy.mjs";
import {
  collectRegistryRawBackup,
  registryStateChecksums,
  restoreRegistryBackup,
  writeRetirementBackup,
} from "./company_retirement_backup.mjs";
import { runRetirementCli } from "./company_retirement_p0.mjs";
import { companyLinkCodeKey } from "./company_retirement_keys.mjs";

const WORKER = readFileSync(fileURLToPath(new URL("../../fluxidi_booking_worker.js", import.meta.url)), "utf8");
const POLICY = readFileSync(fileURLToPath(new URL("./company_retirement_policy.mjs", import.meta.url)), "utf8");
const CLI = readFileSync(fileURLToPath(new URL("./company_retirement_p0.mjs", import.meta.url)), "utf8");
const GUARD = readFileSync(fileURLToPath(new URL("../../modules/company_registry_tombstone_guard.mjs", import.meta.url)), "utf8");
const INDEX = readFileSync(fileURLToPath(new URL("../../modules/company_registry_index.mjs", import.meta.url)), "utf8");

function seedCandidate(kv, code, extras = {}) {
  const tenant = extras.tenant || `tenant_${code.toLowerCase()}`;
  const company = extras.company || `company_${code.toLowerCase()}`;
  kv.map.set(companyLinkCodeKey(code), JSON.stringify({
    tenant_id: tenant,
    company_id: company,
    company_code: code,
    source: "auto_generated",
    linking_enabled: true,
    display_name: extras.display_name || "Test Co",
  }));
  kv.map.set(registryCodeKey(code), JSON.stringify({
    company_code: code,
    lifecycle_status: "active",
    environment_class: "unknown",
  }));
  if (extras.bookings) {
    kv.map.set(`tenant:${tenant}:company:${company}:bookings:list:v1`, JSON.stringify({
      items: extras.bookings.map((row) => ({ booking_id: row.id })),
    }));
    for (const booking of extras.bookings) {
      kv.map.set(`booking:${booking.id}`, JSON.stringify(booking.record));
    }
  }
  return { tenant, company };
}

function seedRegistrySnapshot(kv, codes) {
  const companies = [
    publicRegistryFields({ company_code: "FLX-00001", display_name: "Fluxidi" }),
    publicRegistryFields({ company_code: "FLX-00020", display_name: "Fluxidi Google Review" }),
    ...codes.map((code) => publicRegistryFields({ company_code: code })),
  ];
  const manifest = {
    ...emptyRegistryManifest(),
    page_count: 1,
    total: companies.length,
    membership_generation: 3,
  };
  kv.map.set(COMPANY_REGISTRY_MANIFEST_KEY, JSON.stringify(manifest));
  kv.map.set(registryPageKey(1), JSON.stringify({
    page: 1,
    membership_generation: 3,
    companies,
  }));
}

test("wrangler stdout parser keeps JSON when npm notice is glued on", () => {
  const parsed = parseWranglerJson('{"company_code":"FLX-00022","lifecycle_status":"active"}npm notice\n');
  assert.equal(parsed.company_code, "FLX-00022");
  assert.equal(parseWranglerJson(""), null);
});

test("explicit ID selection accepts only the 22 candidates", () => {
  assert.equal(EXPLICIT_RETIREMENT_CANDIDATES.length, 22);
  assert.deepEqual(HARD_PROTECTED_COMPANY_CODES, ["FLX-00001", "FLX-00020"]);
  const ok = selectRetirementCodes(["FLX-00002", "FLX-00022"]);
  assert.equal(ok.ok, true);
  assert.deepEqual(ok.selected, ["FLX-00002", "FLX-00022"]);
  assert.equal(selectRetirementCodes(["FLX-00001"]).ok, false);
  assert.equal(selectRetirementCodes(["FLX-00020"]).ok, false);
  assert.equal(selectRetirementCodes(["FLX-00099"]).ok, false);
  assert.equal(selectRetirementCodes(["FLX-90811"]).ok, true);
  assert.equal(selectRetirementCodes(["FLX-91611"]).ok, false);
  assert.equal(selectRetirementCodes(["FLX-*"]).ok, false);
  assert.equal(looksLikeWildcardSelection("id != FLX-00001"), true);
  assert.equal(looksLikeWildcardSelection("FLX-00002"), false);
});

test("protected company guards are hardcoded and tested", () => {
  assert.equal(isHardProtectedCompanyCode("FLX-00001"), true);
  assert.equal(isHardProtectedCompanyCode("FLX-00020"), true);
  assert.equal(isHardProtectedCompanyCode("FLX-00022"), false);
  const snapshot = {
    manifest: emptyRegistryManifest(),
    pages: [{ page: 1, membership_generation: 1, companies: [
      publicRegistryFields({ company_code: "FLX-00001", display_name: "Fluxidi" }),
      publicRegistryFields({ company_code: "FLX-00022", display_name: "Test" }),
    ] }],
  };
  snapshot.manifest.total = 2;
  snapshot.manifest.page_count = 1;
  const blocked = applyRegistryRemove(snapshot, "FLX-00001");
  assert.equal(blocked.blocked, "protected_company");
  assert.equal(blocked.membershipChanged, false);
  assert.throws(() => tombstoneRecord("FLX-00001", "2026-09-07T00:00:00.000Z"), /protected_company/);
  assert.throws(() => tombstoneRecord("FLX-00020", "2026-09-07T00:00:00.000Z"), /protected_company/);
});

test("dry-run is the default and execute needs exact registry-only confirmation", async () => {
  assert.equal(assertExecuteAuthorization({}).mode, "dry_run");
  assert.equal(assertExecuteAuthorization({
    execute: true,
    confirm: EXECUTE_CONFIRMATION_TEXT,
  }).ok, false);
  const enabled = assertExecuteAuthorization({
    execute: true,
    confirm: EXECUTE_CONFIRMATION_TEXT,
    executeEnabled: true,
  });
  assert.equal(enabled.ok, true);
  assert.equal(enabled.mode, "execute");
  assert.equal(assertExecuteAuthorization({
    execute: true,
    confirm: LEGACY_EXECUTE_CONFIRMATION_TEXT,
    executeEnabled: true,
  }).ok, false);
  const kv = createMemoryKv();
  seedCandidate(kv, "FLX-00022");
  const result = await runRetirementCli(["--codes", "FLX-00022"], {
    stores: { BOOKING_KV: kv, FLUXIDI_TRACKING: createMemoryKv(), INVOICE_KV: createMemoryKv(), PUBLIC_MEDIA: createMemoryKv() },
    writeBackup: false,
  });
  assert.equal(result.ok, true);
  assert.equal(result.mode, "dry_run");
  assert.equal(result.phase, "registry_retirement");
  assert.equal(kv.map.has(registryTombstoneKey("FLX-00022")), false);
});

test("payments classify as high risk but do not enable full-purge", async () => {
  const kv = createMemoryKv();
  seedCandidate(kv, "FLX-00021", {
    bookings: [{
      id: "bk_paid",
      record: { booking_id: "bk_paid", payment_status: "paid", created_at: new Date().toISOString() },
    }],
  });
  const report = await inventorySelection({ BOOKING_KV: kv }, ["FLX-00021"]);
  assert.equal(report.companies[0].classification.risk_group, RISK_GROUPS.PAYMENTS_OR_RECENT);
  assert.equal(report.companies[0].classification.phase_a_eligible, true);
  assert.equal(report.companies[0].classification.phase_b_eligible, false);
  assert.ok(report.companies[0].classification.blockers.includes("has_payments"));
  assert.equal(assertFullPurgeForbidden({ fullPurge: true }).ok, false);
  assert.throws(() => applyFullPurge(), /phase_b_full_purge_disabled/);
});

test("partial failure fail-closed and restore checksums stay stable on dry-run", async () => {
  const kv = createMemoryKv();
  seedCandidate(kv, "FLX-00002");
  const throwing = {
    async get(key) {
      if (String(key).includes("bookings:list")) throw new Error("boom");
      return kv.get(key);
    },
    async put(key, value) { return kv.put(key, value); },
    async delete(key) { return kv.delete(key); },
  };
  const report = await inventorySelection({ BOOKING_KV: throwing }, ["FLX-00002"]);
  assert.equal(report.fail_closed, true);
  assert.ok(report.companies[0].classification.phase_a_blockers.includes("partial_failure"));
  const before = report.companies[0].restore_checksums;
  const again = await inventorySelection({ BOOKING_KV: kv }, ["FLX-00002"]);
  assert.equal(again.companies[0].restore_checksums.company_link, before.company_link);
});

test("eligible registry retirement writes tombstone, marks link, and cannot re-upsert", async () => {
  const kv = createMemoryRegistryKv();
  const first = await upsertCompanyRegistryEntry(kv, { company_code: "FLX-00022", display_name: "Orphan" });
  assert.equal(first.ok, true);
  seedCandidate(kv, "FLX-00022");
  const report = {
    fail_closed: false,
    companies: [{
      company_code: "FLX-00022",
      classification: { eligible: true, phase_a_blocked: false, blockers: [] },
      raw: {
        registry_code: { company_code: "FLX-00022", lifecycle_status: "active" },
        company_link: {
          company_code: "FLX-00022",
          tenant_id: "tenant_x",
          company_id: "company_x",
          linking_enabled: true,
        },
      },
    }],
    raw_registry: {
      manifest: JSON.parse(kv.map.get(COMPANY_REGISTRY_MANIFEST_KEY)),
      pages: [JSON.parse(kv.map.get(registryPageKey(1)))],
    },
  };
  const applied = await applyRegistryRetirementExecute(kv, report, {
    nowIso: "2026-09-07T16:00:00.000Z",
  });
  assert.equal(applied.ok, true);
  assert.equal(applied.deletes.length, 0);
  assert.equal(await isCompanyRegistryRevoked(kv, "FLX-00022"), true);
  const retiredCode = JSON.parse(kv.map.get(registryCodeKey("FLX-00022")));
  assert.equal(retiredCode.lifecycle_status, "retired");
  const retiredLink = JSON.parse(kv.map.get(companyLinkCodeKey("FLX-00022")));
  assert.equal(retiredLink.linking_enabled, false);
  assert.equal(retiredLink.retired, true);
  assert.equal(retiredLink.tenant_id, "tenant_x");
  const replay = await upsertCompanyRegistryEntry(kv, { company_code: "FLX-00022", display_name: "Orphan" });
  assert.equal(replay.ok, false);
  assert.equal(replay.error, "registry_revoked");
  assert.equal(await isCompanyRegistryRevoked(kv, "FLX-00001"), false);
  assert.ok(!applied.writes.some((key) => /booking:|invoice|oauth|fleet:|drivers:/.test(key)));
});

test("tombstone does not revoke protected companies", async () => {
  const kv = createMemoryRegistryKv({
    [registryTombstoneKey("FLX-00001")]: JSON.stringify({
      company_code: "FLX-00001",
      revoked: true,
    }),
  });
  assert.equal(await isCompanyRegistryRevoked(kv, "FLX-00001"), false);
  const upsert = await upsertCompanyRegistryEntry(kv, { company_code: "FLX-00001", display_name: "Fluxidi" });
  assert.equal(upsert.ok, true);
});

test("registry backup is raw and restore returns the exact original state", async () => {
  const kv = createMemoryKv();
  seedRegistrySnapshot(kv, ["FLX-00022"]);
  seedCandidate(kv, "FLX-00022");
  const report = await inventorySelection({ BOOKING_KV: kv }, ["FLX-00022"]);
  const before = registryStateChecksums(kv.map, ["FLX-00022", "FLX-00001", "FLX-00020"]);
  const dir = mkdtempSync(join(tmpdir(), "retire-registry-"));
  const plan = buildRetirementPlan(report);
  const backup = writeRetirementBackup(dir, report, plan);
  const raw = collectRegistryRawBackup(report);
  assert.ok(raw.records.some((row) => row.key === COMPANY_REGISTRY_MANIFEST_KEY));
  assert.ok(raw.records.some((row) => row.key === registryPageKey(1)));
  assert.ok(raw.records.some((row) => row.key === registryCodeKey("FLX-00022")));
  assert.ok(raw.records.some((row) => row.key === companyLinkCodeKey("FLX-00022")));
  const applied = await applyRegistryRetirementExecute(kv, report, {
    nowIso: "2026-09-07T16:10:00.000Z",
  });
  assert.equal(applied.ok, true);
  const mid = registryStateChecksums(kv.map, ["FLX-00022", "FLX-00001", "FLX-00020"]);
  assert.notEqual(mid[registryTombstoneKey("FLX-00022")], before[registryTombstoneKey("FLX-00022")]);
  const restored = await restoreRegistryBackup(kv, backup.raw_backup);
  assert.equal(restored.ok, true);
  const after = registryStateChecksums(kv.map, ["FLX-00022", "FLX-00001", "FLX-00020"]);
  assert.deepEqual(after, before);
  const manifest = JSON.parse(readFileSync(backup.files[0], "utf8"));
  assert.equal(manifest.secrets, "omitted");
  assert.equal(manifest.git, false);
  assert.doesNotMatch(JSON.stringify(manifest), /access_token|refresh_token|Bearer /);
});

test("phase A write-set contains only registry and company-link keys", () => {
  const report = {
    generated_at: "2026-09-07T12:00:00.000Z",
    fail_closed: false,
    companies: [{
      company_code: "FLX-00022",
      identity: {
        has_company_link: true,
        has_registry_code: true,
        on_registry_page: true,
      },
      registry_membership: { pages: [1] },
      classification: { eligible: true, risk_group: RISK_GROUPS.EMPTY_LOW, phase_a_blocked: false },
      raw: {
        registry_code: { company_code: "FLX-00022", lifecycle_status: "active" },
        company_link: { company_code: "FLX-00022", linking_enabled: true },
      },
    }],
  };
  const plan = buildRetirementPlan(report);
  const keys = plan.companies[0].writes.map((row) => row.key);
  assert.ok(keys.includes(registryTombstoneKey("FLX-00022")));
  assert.ok(keys.includes(registryCodeKey("FLX-00022")));
  assert.ok(keys.includes(companyLinkCodeKey("FLX-00022")));
  assert.ok(keys.includes(registryPageKey(1)));
  assert.ok(keys.includes(COMPANY_REGISTRY_MANIFEST_KEY));
  assert.equal(plan.companies[0].deletes.length, 0);
  assert.equal(plan.phase_b_executable, false);
  for (const key of keys) {
    assert.match(key, /^(company_registry:|company_link:index:code:)/);
  }
});

test("authorized registry execute retires only selected codes and keeps unknowns", async () => {
  const kv = createMemoryKv();
  seedRegistrySnapshot(kv, ["FLX-00022", "FLX-90811"]);
  seedCandidate(kv, "FLX-00022");
  seedCandidate(kv, "FLX-90811");
  kv.map.set(registryPageKey(1), JSON.stringify({
    page: 1,
    membership_generation: 3,
    companies: [
      publicRegistryFields({ company_code: "FLX-00001" }),
      publicRegistryFields({ company_code: "FLX-00020" }),
      publicRegistryFields({ company_code: "FLX-00022" }),
      publicRegistryFields({ company_code: "FLX-90811" }),
      publicRegistryFields({ company_code: "FLX-99999" }),
    ],
  }));
  const prev = process.env.FLUXIDI_RETIREMENT_EXECUTE_ENABLED;
  process.env.FLUXIDI_RETIREMENT_EXECUTE_ENABLED = "1";
  try {
    const result = await runRetirementCli(
      ["--execute", "--confirm", EXECUTE_CONFIRMATION_TEXT, "--codes", "FLX-00022,FLX-90811"],
      {
        stores: { BOOKING_KV: kv, FLUXIDI_TRACKING: createMemoryKv(), INVOICE_KV: createMemoryKv(), PUBLIC_MEDIA: createMemoryKv() },
        writeBackup: false,
      },
    );
    assert.equal(result.ok, true);
    assert.equal(result.mode, "execute");
    assert.equal(kv.map.has(registryTombstoneKey("FLX-00022")), true);
    assert.equal(kv.map.has(registryTombstoneKey("FLX-90811")), true);
    assert.equal(kv.map.has(registryTombstoneKey("FLX-91611")), false);
    const page = JSON.parse(kv.map.get(registryPageKey(1)));
    const codes = page.companies.map((row) => row.company_code);
    assert.ok(codes.includes("FLX-00001"));
    assert.ok(codes.includes("FLX-00020"));
    assert.ok(codes.includes("FLX-99999"));
    assert.equal(codes.includes("FLX-00022"), false);
    assert.equal(codes.includes("FLX-90811"), false);
    assert.equal(JSON.parse(kv.map.get(companyLinkCodeKey("FLX-00022"))).linking_enabled, false);
  } finally {
    if (prev == null) delete process.env.FLUXIDI_RETIREMENT_EXECUTE_ENABLED;
    else process.env.FLUXIDI_RETIREMENT_EXECUTE_ENABLED = prev;
  }
});

test("full-purge flags cannot execute", async () => {
  const result = await runRetirementCli(["--full-purge", "--execute", "--confirm", EXECUTE_CONFIRMATION_TEXT], {
    stores: { BOOKING_KV: createMemoryKv() },
    writeBackup: false,
  });
  assert.equal(result.ok, false);
  assert.equal(result.error, "phase_b_full_purge_disabled");
  const phase = await runRetirementCli(["--phase", "full_purge"], {
    stores: { BOOKING_KV: createMemoryKv() },
    writeBackup: false,
  });
  assert.equal(phase.ok, false);
  assert.equal(phase.error, "phase_b_full_purge_disabled");
});

test("worker tombstone guard is split from ops tooling and Command Centre is not modified", () => {
  assert.match(WORKER, /company_registry_tombstone_guard\.mjs/);
  assert.match(WORKER, /isCompanyRegistryRevoked/);
  assert.match(WORKER, /registry_revoked/);
  assert.match(WORKER, /\[COMPANY_REGISTRY\]\[SYNC\]\[REVOKED\]/);
  assert.match(WORKER, /_syncCompanyRegistryMembership/);
  assert.match(WORKER, /_upsertCompanyCodeIndexesForScope/);
  assert.doesNotMatch(WORKER, /ops\/company_retirement_p0/);
  assert.doesNotMatch(GUARD, /from ["'].*ops\/company_retirement/);
  assert.match(INDEX, /company_registry_tombstone_guard\.mjs/);
  assert.doesNotMatch(CLI, /fluxidi-command-center/);
  assert.doesNotMatch(POLICY, /id\s*!=/);
  assert.match(CLI, /dry-run/);
  assert.match(CLI, /phase_b_full_purge_disabled/);
  assert.deepEqual(LIVE_WORKER_BUNDLE_RETIREMENT_FILES, [
    "workers/booking/fluxidi_booking_worker.js",
    "workers/booking/modules/company_registry_index.mjs",
    "workers/booking/modules/company_registry_tombstone_guard.mjs",
  ]);
});

test("applyRegistryRemove does not duplicate and keeps protected rows", () => {
  let snapshot = {
    manifest: emptyRegistryManifest(),
    pages: [{ page: 1, membership_generation: 2, companies: [
      publicRegistryFields({ company_code: "FLX-00001" }),
      publicRegistryFields({ company_code: "FLX-00022" }),
    ] }],
  };
  snapshot.manifest.total = 2;
  snapshot.manifest.page_count = 1;
  snapshot = applyRegistryUpsert(snapshot, publicRegistryFields({ company_code: "FLX-00022", display_name: "X" }));
  assert.equal(snapshot.pages[0].companies.filter((row) => row.company_code === "FLX-00022").length, 1);
  const removed = applyRegistryRemove(snapshot, "FLX-00022");
  assert.equal(removed.membershipChanged, true);
  assert.equal([...removed.pages.flatMap((page) => page.companies.map((row) => row.company_code))].includes("FLX-00001"), true);
  assert.equal([...removed.pages.flatMap((page) => page.companies.map((row) => row.company_code))].includes("FLX-00022"), false);
});

test("unknown page members are kept and FLX-91611 cannot be selected or written", () => {
  assert.equal(selectRetirementCodes(["FLX-91611"]).ok, false);
  assert.equal(isAllowedPhaseAWriteKey("company_registry:tombstone:FLX-91611:v1"), false);
  assert.equal(isAllowedPhaseAWriteKey("company_registry:tombstone:FLX-90811:v1"), true);
  assert.equal(isAllowedPhaseAWriteKey("company_registry:tombstone:FLX-00001:v1"), false);
  const before = {
    manifest: emptyRegistryManifest(),
    pages: [{ page: 1, membership_generation: 4, companies: [
      publicRegistryFields({ company_code: "FLX-00001" }),
      publicRegistryFields({ company_code: "FLX-00020" }),
      publicRegistryFields({ company_code: "FLX-00022" }),
      publicRegistryFields({ company_code: "FLX-99999" }),
    ] }],
  };
  let next = applyRegistryRemove(before, "FLX-00022");
  const preserved = assertUnknownCompaniesPreserved(before, next, ["FLX-00022"]);
  assert.equal(preserved.ok, true);
  assert.ok(preserved.remaining.includes("FLX-99999"));
  assert.ok(preserved.remaining.includes("FLX-00001"));
  assert.ok(preserved.remaining.includes("FLX-00020"));
  assert.equal(preserved.remaining.includes("FLX-00022"), false);
  const dropped = assertUnknownCompaniesPreserved(before, {
    pages: [{ page: 1, companies: [
      publicRegistryFields({ company_code: "FLX-00001" }),
      publicRegistryFields({ company_code: "FLX-00020" }),
    ] }],
  }, ["FLX-00022"]);
  assert.equal(dropped.ok, false);
  assert.equal(dropped.error, "unknown_or_non_candidate_company_would_be_dropped");
});

test("risk groups split empty, data, payments, and missing codes", () => {
  const empty = classifyCandidate({
    protected: false,
    identity: { has_company_link: true, has_registry_code: true, on_registry_page: true },
    counts: { payments: 0, invoices: 0, bookings: 0, recent_bookings: 0, drivers: 0, vehicles: 0, customers: 0, r2_logo: 0 },
    integrations: {},
    read_errors: [],
  });
  assert.equal(empty.risk_group, RISK_GROUPS.EMPTY_LOW);
  const data = classifyCandidate({
    protected: false,
    identity: { has_company_link: true, has_registry_code: true, on_registry_page: true },
    counts: { payments: 0, invoices: 0, bookings: 0, recent_bookings: 0, drivers: 1, vehicles: 1, customers: 0, r2_logo: 0 },
    integrations: {},
    read_errors: [],
  });
  assert.equal(data.risk_group, RISK_GROUPS.DATA_PRESENT);
  const missing = classifyCandidate({
    protected: false,
    identity: { has_company_link: false, has_registry_code: false, on_registry_page: false },
    counts: { payments: 0, invoices: 0, bookings: 0, recent_bookings: 0, drivers: 0, vehicles: 0, customers: 0, r2_logo: 0 },
    integrations: {},
    read_errors: [],
  });
  assert.equal(missing.risk_group, RISK_GROUPS.MISSING_OR_MISMATCH);
});
