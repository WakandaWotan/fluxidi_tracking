import assert from "node:assert/strict";
import test from "node:test";
import {
  COMPANY_ADMIN_SESSION_PREFIX,
  PUBLIC_PARTNER_DIRECTORY_V2_KEY,
  applyAccountAction,
  applyPublicVisibilityOverride,
  assertNotClosedIdentity,
  evaluateAccountRoute,
  filterDriverInboxForAccountState,
  isExistingAssignedOpenRide,
  loadAccountLifecycle,
  loadPublicVisibilityOverride,
  markPublicPartnerInactive,
  normalizeAccountState,
  publicActivePartnerEligibility,
  publicListingEligibility,
  publicProfileEligibility,
  publicPartnerAccountFields,
  publicVisibilityCodeKey,
  publicVisibilityScopeKey,
  removeCompanyFromPublicProjections,
  resolveCanonicalAccountState,
  revokeScopedCompanyAdminSessions,
  revokeScopedDriverSessionsForCompany,
  sessionSurvivesState,
  sourceGatesForState,
} from "./company_account_lifecycle.mjs";

const OPEN_RIDE = {
  tenant_id: "cmp_a",
  company_id: "cmp_a",
  status: "in_progress",
  assigned_driver_id: "drv_1",
};

function memoryKv(records = {}) {
  const store = new Map(Object.entries(records));
  return {
    store,
    async get(key, opts) {
      const raw = store.get(key);
      if (raw == null) return null;
      if (opts?.type === "json") return typeof raw === "string" ? JSON.parse(raw) : raw;
      return raw;
    },
    async put(key, value) {
      store.set(key, typeof value === "string" ? value : JSON.stringify(value));
    },
    async delete(key) {
      store.delete(key);
    },
    async list({ prefix = "", cursor } = {}) {
      const keys = [...store.keys()].filter((name) => name.startsWith(prefix)).map((name) => ({ name }));
      return { keys, list_complete: true, cursor: cursor || null };
    },
  };
}

function rideContext(extra = {}) {
  return {
    booking: OPEN_RIDE,
    scope: { tenant_id: "cmp_a", company_id: "cmp_a" },
    action: "status_existing",
    actor: { driver_id: "drv_1" },
    ...extra,
  };
}

test("missing or derived status is unknown, never active", () => {
  assert.equal(normalizeAccountState(""), "unknown");
  assert.equal(normalizeAccountState("derived"), "unknown");
  assert.equal(resolveCanonicalAccountState([]).state, "unknown");
  assert.equal(resolveCanonicalAccountState([{ linking_enabled: true }]).state, "unknown");
  assert.equal(publicActivePartnerEligibility({ state: "unknown" }).eligible, false);
  assert.equal(publicPartnerAccountFields({ state: "unknown" }).bookable, false);
});

test("status priority keeps closed above blocked, paused and active", () => {
  assert.equal(resolveCanonicalAccountState(["active", "blocked", "closed"]).state, "closed");
  assert.equal(resolveCanonicalAccountState(["paused", "blocked"]).state, "blocked");
});

test("pause refuses new work and login but keeps assigned in-progress rides", () => {
  assert.equal(evaluateAccountRoute("paused", "new_booking").ok, false);
  assert.equal(evaluateAccountRoute("paused", "new_quote").error, "company_paused");
  assert.equal(evaluateAccountRoute("paused", "public_login").ok, false);
  assert.equal(evaluateAccountRoute("paused", "in_progress_ride", rideContext()).ok, true);
  assert.equal(evaluateAccountRoute("paused", "fleet_sync").ok, true);
  assert.equal(sessionSurvivesState("paused"), true);
  assert.equal(publicActivePartnerEligibility({ state: "paused" }).eligible, false);
});

test("driver inbox drops new unassigned work after pause or block", () => {
  const inbox = [
    { booking_id: "open", assigned_driver_id: "drv_1", status: "in_progress" },
    { booking_id: "pool", available_unassigned: true, status: "pending" },
    { booking_id: "other", assigned_driver_id: "drv_2", status: "assigned" },
  ];
  assert.equal(filterDriverInboxForAccountState(inbox, "active", "drv_1").length, 3);
  const paused = filterDriverInboxForAccountState(inbox, "paused", "drv_1");
  assert.deepEqual(paused.map((row) => row.booking_id), ["open"]);
  const blocked = filterDriverInboxForAccountState(inbox, "blocked", "drv_1");
  assert.deepEqual(blocked.map((row) => row.booking_id), ["open"]);
});

test("in-progress exception refuses new rides and general company changes", () => {
  assert.equal(evaluateAccountRoute("blocked", "in_progress_ride").ok, false);
  assert.equal(evaluateAccountRoute("blocked", "in_progress_ride", {
    booking: OPEN_RIDE,
    scope: { tenant_id: "cmp_a", company_id: "cmp_a" },
    action: "create",
  }).ok, false);
  assert.equal(isExistingAssignedOpenRide({
    tenant_id: "cmp_a",
    company_id: "cmp_a",
    status: "pending",
  }, { tenant_id: "cmp_a", company_id: "cmp_a" }, "status_existing"), false);
  assert.equal(evaluateAccountRoute("blocked", "in_progress_ride", rideContext()).ok, true);
});

test("block refuses company environment and sync; current assigned ride stays open", () => {
  assert.equal(evaluateAccountRoute("blocked", "company_login").error, "company_blocked");
  assert.equal(evaluateAccountRoute("blocked", "bootstrap").ok, false);
  assert.equal(evaluateAccountRoute("blocked", "fleet_sync").ok, false);
  assert.equal(evaluateAccountRoute("blocked", "company_admin_write").ok, false);
  assert.equal(sourceGatesForState("blocked").revoke_company_sessions, true);
  assert.equal(sourceGatesForState("blocked").use_subscription_suspension, false);
  assert.equal(publicActivePartnerEligibility({ state: "blocked" }).eligible, false);
  assert.equal(publicProfileEligibility({ state: "blocked" }).visible, true);
  assert.equal(publicProfileEligibility({ state: "blocked" }).bookable, false);
});

test("close is final, not a purge, and not visible publicly", () => {
  const gates = sourceGatesForState("closed");
  assert.equal(gates.linking_enabled, false);
  assert.equal(gates.registry_tombstone, true);
  assert.equal(gates.remove_public_projection, true);
  assert.equal(gates.write_account_enabled_profile, false);
  assert.equal(evaluateAccountRoute("closed", "new_booking").error, "company_unavailable");
  assert.equal(evaluateAccountRoute("closed", "in_progress_ride", rideContext()).ok, true);
  assert.equal(publicProfileEligibility({ state: "closed" }).visible, false);
  assert.equal(publicActivePartnerEligibility({ state: "closed" }).eligible, false);
});

test("company admin session revoke is scoped to one tenant and company", async () => {
  const kv = memoryKv({
    [`${COMPANY_ADMIN_SESSION_PREFIX}aaa:v1`]: {
      role: "company_admin",
      tenant_id: "cmp_jm",
      company_id: "cmp_jm",
    },
    [`${COMPANY_ADMIN_SESSION_PREFIX}bbb:v1`]: {
      role: "company_admin",
      tenant_id: "fluxidi_fluxidi_ddmh9g",
      company_id: "fluxidi_fluxidi_ddmh9g",
    },
    [`${COMPANY_ADMIN_SESSION_PREFIX}ccc:v1`]: {
      role: "company_admin",
      tenant_id: "cmp_jm",
      company_id: "cmp_other",
    },
    "public_driver:session:ddd:v1": {
      role: "driver",
      tenant_id: "cmp_jm",
      company_id: "cmp_jm",
      driver_id: "drv_1",
    },
  });
  const result = await revokeScopedCompanyAdminSessions(kv, {
    tenantId: "cmp_jm",
    companyId: "cmp_jm",
  });
  assert.equal(result.ok, true);
  assert.equal(result.revoked_count, 1);
  assert.equal(kv.store.has(`${COMPANY_ADMIN_SESSION_PREFIX}aaa:v1`), false);
  assert.equal(kv.store.has(`${COMPANY_ADMIN_SESSION_PREFIX}bbb:v1`), true);
  assert.equal(kv.store.has(`${COMPANY_ADMIN_SESSION_PREFIX}ccc:v1`), true);
  assert.equal(kv.store.has("public_driver:session:ddd:v1"), true);
});

test("block revokes this company's driver sessions and leaves the other company alone", async () => {
  const kv = memoryKv({
    "company_link:index:code:FLX-00991:v1": {
      tenant_id: "cmp_a",
      company_id: "cmp_a",
      company_code: "FLX-00991",
      linking_enabled: true,
    },
    [`${COMPANY_ADMIN_SESSION_PREFIX}aaa:v1`]: {
      role: "company_admin",
      tenant_id: "cmp_a",
      company_id: "cmp_a",
    },
    "public_driver:session:drv-a:v1": {
      role: "driver",
      tenant_id: "cmp_a",
      company_id: "cmp_a",
      driver_id: "drv_a",
    },
    "public_driver:session:drv-b:v1": {
      role: "driver",
      tenant_id: "cmp_b",
      company_id: "cmp_b",
      driver_id: "drv_b",
    },
    [PUBLIC_PARTNER_DIRECTORY_V2_KEY]: {
      partners: [{
        partner_id: "company:cmp_a:cmp_a",
        company_name: "Blocked Co",
        is_active: true,
        subscription_status: "active",
      }],
    },
  });
  const applied = await applyAccountAction(kv, {
    tenantId: "cmp_a",
    companyId: "cmp_a",
    companyCode: "FLX-00991",
    action: "block",
    actorId: "platform_admin",
    reason: "test",
  });
  assert.equal(applied.ok, true);
  assert.equal(applied.gates.use_subscription_suspension, false);
  assert.equal(applied.revoked.company_admin, 1);
  assert.equal(applied.revoked.drivers, 1);
  const directory = JSON.parse(kv.store.get(PUBLIC_PARTNER_DIRECTORY_V2_KEY));
  assert.equal(directory.partners[0].is_active, false);
  assert.equal(directory.partners[0].bookable, false);
  const drivers = await revokeScopedDriverSessionsForCompany(kv, { tenantId: "cmp_a", companyId: "cmp_a" });
  assert.equal(drivers.revoked_count, 0);
  assert.equal(kv.store.has("public_driver:session:drv-b:v1"), true);
});

test("an old fleet POST cannot use a blocked company session after revoke", async () => {
  const kv = memoryKv({
    [`${COMPANY_ADMIN_SESSION_PREFIX}oldapp:v1`]: {
      role: "company_admin",
      tenant_id: "cmp_jm",
      company_id: "cmp_jm",
    },
  });
  assert.equal(evaluateAccountRoute("blocked", "fleet_sync").ok, false);
  await revokeScopedCompanyAdminSessions(kv, { tenantId: "cmp_jm", companyId: "cmp_jm" });
  assert.equal(kv.store.size, 0);
});

test("close removes the public projection and refuses later resume or unblock", async () => {
  const kv = memoryKv({
    "company_link:index:code:FLX-00025:v1": {
      tenant_id: "cmp_flex",
      company_id: "cmp_flex",
      company_code: "FLX-00025",
      linking_enabled: true,
    },
    "company_link:index:scope:cmp_flex:cmp_flex:v1": {
      tenant_id: "cmp_flex",
      company_id: "cmp_flex",
      company_code: "FLX-00025",
      linking_enabled: true,
    },
    [PUBLIC_PARTNER_DIRECTORY_V2_KEY]: {
      version: 2,
      partners: [
        { partner_id: "company:cmp_flex:cmp_flex", company_name: "Flex-Project SRL", is_active: true, subscription_status: "active" },
        { partner_id: "company:other:other", company_name: "Other", is_active: true, subscription_status: "active" },
      ],
    },
  });
  const closed = await applyAccountAction(kv, {
    tenantId: "cmp_flex",
    companyId: "cmp_flex",
    companyCode: "FLX-00025",
    action: "close",
    actorId: "christophe",
    confirmation: { company_code: "FLX-00025", display_name: "Flex-Project SRL" },
  });
  assert.equal(closed.ok, true);
  assert.equal(closed.state, "closed");
  const directory = JSON.parse(kv.store.get(PUBLIC_PARTNER_DIRECTORY_V2_KEY));
  assert.equal(directory.partners.length, 1);
  assert.equal(directory.partners[0].company_name, "Other");
  const codeLink = JSON.parse(kv.store.get("company_link:index:code:FLX-00025:v1"));
  const scopeLink = JSON.parse(kv.store.get("company_link:index:scope:cmp_flex:cmp_flex:v1"));
  assert.equal(codeLink.linking_enabled, false);
  assert.equal(scopeLink.linking_enabled, false);
  const resume = await applyAccountAction(kv, {
    tenantId: "cmp_flex",
    companyId: "cmp_flex",
    companyCode: "FLX-00025",
    action: "resume",
  });
  assert.equal(resume.ok, false);
  assert.equal(resume.error, "closed_is_final");
  const unblock = await applyAccountAction(kv, {
    tenantId: "cmp_flex",
    companyId: "cmp_flex",
    companyCode: "FLX-00025",
    action: "unblock",
  });
  assert.equal(unblock.ok, false);
  assert.equal(unblock.error, "closed_is_final");
  const loaded = await loadAccountLifecycle(kv, { tenantId: "cmp_flex", companyId: "cmp_flex", companyCode: "FLX-00025" });
  assert.equal(loaded.state, "closed");
  const identity = await assertNotClosedIdentity(kv, { companyCode: "FLX-00025", tenantId: "cmp_flex", companyId: "cmp_flex" });
  assert.equal(identity.ok, false);
});

test("tombstone keeps a company closed even if the lifecycle key is missing", async () => {
  const kv = memoryKv({
    "company_registry:tombstone:FLX-00025:v1": {
      revoked: true,
      reason: "account_close",
      company_code: "FLX-00025",
    },
  });
  const loaded = await loadAccountLifecycle(kv, {
    tenantId: "cmp_flex",
    companyId: "cmp_flex",
    companyCode: "FLX-00025",
  });
  assert.equal(loaded.state, "closed");
  assert.equal(loaded.source, "tombstone");
});

test("missing lifecycle loads as unknown, not active", async () => {
  const loaded = await loadAccountLifecycle(memoryKv(), { tenantId: "cmp_x", companyId: "cmp_x" });
  assert.equal(loaded.state, "unknown");
  assert.equal(loaded.source, "missing");
});

test("public projection helpers drop or inactivate the matching partner only", async () => {
  const kv = memoryKv({
    [PUBLIC_PARTNER_DIRECTORY_V2_KEY]: {
      partners: [
        { partner_id: "company:a:a", company_name: "A", is_active: true },
        { partner_id: "company:b:b", company_name: "B", is_active: true },
      ],
    },
  });
  await markPublicPartnerInactive(kv, { tenantId: "a", companyId: "a" });
  let directory = JSON.parse(kv.store.get(PUBLIC_PARTNER_DIRECTORY_V2_KEY));
  assert.equal(directory.partners.find((row) => row.partner_id === "company:a:a").is_active, false);
  assert.equal(directory.partners.find((row) => row.partner_id === "company:b:b").is_active, true);
  await removeCompanyFromPublicProjections(kv, { tenantId: "a", companyId: "a" });
  directory = JSON.parse(kv.store.get(PUBLIC_PARTNER_DIRECTORY_V2_KEY));
  assert.deepEqual(directory.partners.map((row) => row.partner_id), ["company:b:b"]);
});

test("platform public visibility hide does not change account state", async () => {
  const lifecycleKey = "tenant:cmp_review:company:cmp_review:account_lifecycle:v1";
  const kv = memoryKv({
    [lifecycleKey]: {
      state: "active",
      revision: 3,
      tenant_id: "cmp_review",
      company_id: "cmp_review",
      company_code: "FLX-00920",
    },
    [PUBLIC_PARTNER_DIRECTORY_V2_KEY]: {
      partners: [
        { partner_id: "company:cmp_review:cmp_review", company_name: "Review Co", is_active: true },
        { partner_id: "company:keep:keep", company_name: "Keep", is_active: true },
      ],
    },
  });
  const hidden = await applyPublicVisibilityOverride(kv, {
    tenantId: "cmp_review",
    companyId: "cmp_review",
    companyCode: "FLX-00920",
    visibility: "hidden",
    actorId: "platform_admin",
    reason: "internal_review_environment",
  });
  assert.equal(hidden.ok, true);
  assert.equal(hidden.public_visibility, "hidden");
  assert.equal(hidden.account_state_unchanged, true);
  const account = await loadAccountLifecycle(kv, {
    tenantId: "cmp_review",
    companyId: "cmp_review",
    companyCode: "FLX-00920",
  });
  assert.equal(account.state, "active");
  assert.equal(account.revision, 3);
  const override = await loadPublicVisibilityOverride(kv, {
    tenantId: "cmp_review",
    companyId: "cmp_review",
    companyCode: "FLX-00920",
  });
  assert.equal(override.visibility, "hidden");
  assert.equal(kv.store.has(publicVisibilityScopeKey("cmp_review", "cmp_review")), true);
  assert.equal(kv.store.has(publicVisibilityCodeKey("FLX-00920")), true);
  const directory = JSON.parse(kv.store.get(PUBLIC_PARTNER_DIRECTORY_V2_KEY));
  assert.deepEqual(directory.partners.map((row) => row.partner_id), ["company:keep:keep"]);
  assert.equal(publicListingEligibility(account, { public_visibility: "hidden" }).list, false);
  assert.equal(publicProfileEligibility(account, { public_visibility: "hidden" }).visible, false);
  assert.equal(publicActivePartnerEligibility(account, { public_visibility: "hidden" }).eligible, false);
  assert.equal(publicListingEligibility(account).list, true);
});
