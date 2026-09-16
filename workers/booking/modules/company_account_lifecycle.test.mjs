import assert from "node:assert/strict";
import test from "node:test";
import {
  COMPANY_ADMIN_SESSION_PREFIX,
  applyAccountAction,
  evaluateAccountRoute,
  filterDriverInboxForAccountState,
  isExistingAssignedOpenRide,
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

test("pause refuses new work and login but keeps assigned in-progress rides", () => {
  assert.equal(evaluateAccountRoute("paused", "new_booking").ok, false);
  assert.equal(evaluateAccountRoute("paused", "new_quote").error, "company_paused");
  assert.equal(evaluateAccountRoute("paused", "public_login").ok, false);
  assert.equal(evaluateAccountRoute("paused", "in_progress_ride", rideContext()).ok, true);
  assert.equal(evaluateAccountRoute("paused", "fleet_sync").ok, true);
  assert.equal(sessionSurvivesState("paused"), true);
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
});

test("close is not a purge and does not use billing suspension", () => {
  const gates = sourceGatesForState("closed");
  assert.equal(gates.linking_enabled, false);
  assert.equal(gates.registry_tombstone, true);
  assert.equal(gates.write_account_enabled_profile, false);
  assert.equal(gates.use_subscription_suspension, false);
  assert.equal(evaluateAccountRoute("closed", "new_booking").error, "company_unavailable");
  assert.equal(evaluateAccountRoute("closed", "in_progress_ride", rideContext()).ok, true);
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
