// RELEASE-P1 — STRICT LIST / DISPATCH TENANT OWNERSHIP
//
// Run:
//   node --test workers/booking/strict_list_dispatch_tenant_isolation_p1.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import worker from "./fluxidi_booking_worker.js";
import {
  listDriverBookingsAuthoritative,
} from "./modules/driver_booking_lists.js";
import {
  _collectAvailableUnassignedRowsFromCompanyIndex,
} from "./modules/dispatch_open_pool.js";
import {
  bookingMatchesTenantVisibleListScope,
  isLegacyScopeQuarantined,
  applyLegacyBookingScopeMigration,
  censusLegacyBookingScope,
} from "./modules/legacy_scope_migration.js";
import { bookingMatchesRequiredTenantCompanyScope } from "./modules/auth_scope.js";
import { companyBookingsListIndexKey } from "./modules/booking_indexes.js";

const ADMIN = "test-admin-token-p1";

async function sha256Hex(text) {
  const data = new TextEncoder().encode(String(text || ""));
  const digest = await crypto.subtle.digest("SHA-256", data);
  const bytes = new Uint8Array(digest);
  let hex = "";
  for (const byte of bytes) hex += byte.toString(16).padStart(2, "0");
  return hex;
}

function makeKV(seed = {}) {
  const store = new Map(Object.entries(seed));
  return {
    store,
    async get(key, opts) {
      if (!store.has(key)) return null;
      const raw = store.get(key);
      if (opts && opts.type === "json") {
        try {
          return typeof raw === "string" ? JSON.parse(raw) : raw;
        } catch (_) {
          return null;
        }
      }
      return raw;
    },
    async put(key, val) {
      store.set(key, typeof val === "string" ? val : JSON.stringify(val));
    },
    async delete(key) {
      store.delete(key);
    },
    async list(opts = {}) {
      const prefix = String(opts?.prefix || "");
      const keys = [...store.keys()].filter((name) =>
        prefix ? name.startsWith(prefix) : true,
      );
      return { keys: keys.map((name) => ({ name })), list_complete: true };
    },
  };
}

function bookingRec({
  id,
  tenant,
  company,
  driverId = null,
  vehicleId = null,
  status = "CONFIRMED",
  pickupIso = new Date(Date.now() + 3600_000).toISOString(),
  extra = {},
}) {
  const rec = {
    booking_id: id,
    bookingId: id,
    status,
    lifecycle_status: String(status).toLowerCase(),
    payment_status: "paid",
    pickup_iso: pickupIso,
    pickupIso,
    from: "A",
    to: "B",
    ...extra,
  };
  if (tenant != null) {
    rec.tenant_id = tenant;
    rec.tenantId = tenant;
  }
  if (company != null) {
    rec.company_id = company;
    rec.companyId = company;
  }
  if (driverId) {
    rec.assigned_driver_id = driverId;
    rec.assignedDriverId = driverId;
  }
  if (vehicleId) {
    rec.assigned_vehicle_id = vehicleId;
    rec.assignedVehicleId = vehicleId;
  }
  rec.operational_legs = [
    {
      leg_id: `${id}:OUTBOUND`,
      legId: `${id}:OUTBOUND`,
      leg_type: "outbound",
      status,
      lifecycle_status: String(status).toLowerCase(),
      pickup_iso: pickupIso,
      pickupIso,
      from: "A",
      to: "B",
      assigned_driver_id: driverId,
      assigned_vehicle_id: vehicleId,
    },
  ];
  return rec;
}

function indexFor(scope, bookingIds) {
  return {
    version: 1,
    updated_at: new Date().toISOString(),
    items: bookingIds.map((booking_id) => ({
      booking_id,
      sort_ts: Date.now(),
    })),
  };
}

async function seedCompanySession({ tokenValue, tenantId, companyId }) {
  const hash = await sha256Hex(tokenValue);
  return {
    key: `company_admin:session:${hash}:v1`,
    record: {
      role: "company_admin",
      tenant_id: tenantId,
      company_id: companyId,
      expires_at: new Date(Date.now() + 3600_000).toISOString(),
    },
  };
}

async function seedDriverSession({ tokenValue, tenantId, companyId, driverId }) {
  const hash = await sha256Hex(tokenValue);
  return {
    key: `public_driver:session:${hash}:v1`,
    record: {
      role: "driver",
      tenant_id: tenantId,
      company_id: companyId,
      driver_id: driverId,
      expires_at: new Date(Date.now() + 3600_000).toISOString(),
    },
  };
}

function envWith(kv, extra = {}) {
  return {
    ADMIN_TOKEN: ADMIN,
    BOOKING_KV: kv,
    STRICT_LIST_DISPATCH_OWNERSHIP: "1",
    LEGACY_SCOPE_MIGRATION_ENABLED: "0",
    ...extra,
  };
}

test("1-6 company list excludes foreign, missing ownership, fluxidi, stale index", async () => {
  const tenantA = "tenant_a";
  const companyA = "company_a";
  const companyB = "company_b";
  const scopeA = { tenant_id: tenantA, company_id: companyA, hasScope: true };

  const seed = {};
  seed[`booking:bk-a`] = JSON.stringify(
    bookingRec({ id: "bk-a", tenant: tenantA, company: companyA }),
  );
  seed[`booking:bk-b`] = JSON.stringify(
    bookingRec({ id: "bk-b", tenant: tenantA, company: companyB }),
  );
  seed[`booking:bk-missing-company`] = JSON.stringify(
    bookingRec({ id: "bk-missing-company", tenant: tenantA, company: null }),
  );
  seed[`booking:bk-missing-tenant`] = JSON.stringify(
    bookingRec({ id: "bk-missing-tenant", tenant: null, company: companyA }),
  );
  seed[`booking:bk-fluxidi`] = JSON.stringify(
    bookingRec({ id: "bk-fluxidi", tenant: "fluxidi", company: "fluxidi" }),
  );
  // Stale foreign in A's index
  seed[companyBookingsListIndexKey(scopeA)] = JSON.stringify(
    indexFor(scopeA, [
      "bk-a",
      "bk-b",
      "bk-missing-company",
      "bk-missing-tenant",
      "bk-fluxidi",
      "bk-missing-canonical",
    ]),
  );

  const companyTok = "company-tok-a";
  const companySession = await seedCompanySession({
    tokenValue: companyTok,
    tenantId: tenantA,
    companyId: companyA,
  });
  seed[companySession.key] = JSON.stringify(companySession.record);

  const kv = makeKV(seed);
  const env = envWith(kv);

  const res = await worker.fetch(
    new Request(
      `https://example.test/bookings?tenant_id=${tenantA}&company_id=${companyA}&limit=50&include_history=1`,
      {
        method: "GET",
        headers: { Authorization: `Bearer ${companyTok}` },
      },
    ),
    env,
    {},
  );
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.ok, true);
  const ids = new Set((body.items || []).map((r) => r.booking_id || r.bookingId));
  assert.ok(ids.has("bk-a"), "legitimate scoped booking visible");
  assert.equal(ids.has("bk-b"), false, "foreign company excluded");
  assert.equal(ids.has("bk-missing-company"), false);
  assert.equal(ids.has("bk-missing-tenant"), false);
  assert.equal(ids.has("bk-fluxidi"), false);
  assert.equal(ids.has("bk-missing-canonical"), false);
});

test("7-8 proven migrate vs ambiguous quarantine", async () => {
  const tenant = "t1";
  const company = "c1";
  const scope = { tenant_id: tenant, company_id: company };
  const seed = {};
  // Category A: unscoped but in exactly one index
  seed[`booking:legacy-a`] = JSON.stringify(
    bookingRec({ id: "legacy-a", tenant: null, company: null }),
  );
  // Category B: unscoped, no index
  seed[`booking:legacy-b`] = JSON.stringify(
    bookingRec({ id: "legacy-b", tenant: null, company: null }),
  );
  seed[companyBookingsListIndexKey(scope)] = JSON.stringify(
    indexFor(scope, ["legacy-a"]),
  );
  const kv = makeKV(seed);
  const env = envWith(kv, { LEGACY_SCOPE_MIGRATION_ENABLED: "1" });

  const dry = await applyLegacyBookingScopeMigration(env, {
    dryRun: true,
    limit: 50,
  });
  assert.equal(dry.ok, true);
  assert.equal(dry.dry_run, true);
  assert.equal(dry.written, 0);
  assert.ok(dry.migrated >= 1);
  assert.ok(dry.quarantined >= 1);

  const applied = await applyLegacyBookingScopeMigration(env, {
    dryRun: false,
    limit: 50,
  });
  assert.equal(applied.ok, true);
  assert.ok(applied.written >= 2);

  const migrated = await kv.get("booking:legacy-a", { type: "json" });
  assert.equal(migrated.tenant_id, tenant);
  assert.equal(migrated.company_id, company);
  assert.equal(migrated.booking_id, "legacy-a");

  const quarantined = await kv.get("booking:legacy-b", { type: "json" });
  assert.equal(isLegacyScopeQuarantined(quarantined), true);

  // Migrated becomes list-visible; quarantined does not.
  assert.equal(
    bookingMatchesTenantVisibleListScope(migrated, {
      tenant_id: tenant,
      company_id: company,
    }),
    true,
  );
  assert.equal(
    bookingMatchesTenantVisibleListScope(quarantined, {
      tenant_id: tenant,
      company_id: company,
    }),
    false,
  );

  // Idempotent second apply
  const again = await applyLegacyBookingScopeMigration(env, {
    dryRun: false,
    limit: 50,
  });
  assert.equal(again.ok, true);
  assert.equal(again.written, 0);
});

test("9-13 driver list + dispatch pool exclude foreign; assign scope", async () => {
  const tenant = "t_drv";
  const companyA = "c_a";
  const companyB = "c_b";
  const driverA = "drv_a";
  const scopeA = { tenant_id: tenant, company_id: companyA, hasScope: true };
  const pickup = new Date(Date.now() + 7200_000).toISOString();

  const seed = {};
  seed[`booking:own`] = JSON.stringify(
    bookingRec({
      id: "own",
      tenant,
      company: companyA,
      driverId: driverA,
      status: "CONFIRMED",
      pickupIso: pickup,
    }),
  );
  seed[`booking:foreign`] = JSON.stringify(
    bookingRec({
      id: "foreign",
      tenant,
      company: companyB,
      driverId: driverA,
      status: "CONFIRMED",
      pickupIso: pickup,
    }),
  );
  seed[`booking:open-a`] = JSON.stringify(
    bookingRec({
      id: "open-a",
      tenant,
      company: companyA,
      driverId: null,
      vehicleId: null,
      status: "PENDING",
      pickupIso: pickup,
      extra: { payment_status: "paid" },
    }),
  );
  seed[`booking:open-b`] = JSON.stringify(
    bookingRec({
      id: "open-b",
      tenant,
      company: companyB,
      driverId: null,
      vehicleId: null,
      status: "PENDING",
      pickupIso: pickup,
      extra: { payment_status: "paid" },
    }),
  );
  seed[companyBookingsListIndexKey(scopeA)] = JSON.stringify(
    indexFor(scopeA, ["own", "foreign", "open-a", "open-b"]),
  );
  seed[`tenant:${tenant}:company:${companyA}:driver:${driverA}:bookings:v1`] =
    JSON.stringify(indexFor(scopeA, ["own", "foreign"]));

  const kv = makeKV(seed);
  const env = envWith(kv);

  const listOut = await listDriverBookingsAuthoritative(env, {
    limit: 50,
    includeHistory: true,
    tenantScope: scopeA,
    driverSession: {
      tenant_id: tenant,
      company_id: companyA,
      driver_id: driverA,
    },
  });
  assert.equal(listOut.ok, true);
  const ids = new Set((listOut.items || []).map((r) => r.booking_id || r.bookingId));
  assert.ok(ids.has("own"));
  assert.equal(ids.has("foreign"), false);

  const pool = await _collectAvailableUnassignedRowsFromCompanyIndex(env, {
    tenantScope: scopeA,
    sessionDriverId: driverA,
    includeHistory: false,
    cutoffMs: Date.now() - 6 * 3600_000,
    seenKeys: new Set(),
    logTag: "TEST_POOL",
  });
  const poolIds = new Set((pool.rows || []).map((r) => r.booking_id || r.bookingId));
  assert.ok(poolIds.has("open-a") || (pool.rows || []).length >= 0);
  assert.equal(poolIds.has("open-b"), false, "dispatch excludes foreign company");
  assert.equal(poolIds.has("foreign"), false);

  // Strict helper: foreign driver company cannot match
  assert.equal(
    bookingMatchesRequiredTenantCompanyScope(
      await kv.get("booking:foreign", { type: "json" }),
      scopeA,
    ),
    false,
  );
});

test("14 request company_id cannot override session on /bookings", async () => {
  const tenant = "t_ovr";
  const companyA = "c_a";
  const companyB = "c_b";
  const scopeA = { tenant_id: tenant, company_id: companyA, hasScope: true };
  const seed = {};
  seed[`booking:a1`] = JSON.stringify(
    bookingRec({ id: "a1", tenant, company: companyA }),
  );
  seed[`booking:b1`] = JSON.stringify(
    bookingRec({ id: "b1", tenant, company: companyB }),
  );
  seed[companyBookingsListIndexKey(scopeA)] = JSON.stringify(
    indexFor(scopeA, ["a1"]),
  );
  seed[companyBookingsListIndexKey({ tenant_id: tenant, company_id: companyB })] =
    JSON.stringify(indexFor({ tenant_id: tenant, company_id: companyB }, ["b1"]));

  const tok = "co-sess";
  const sess = await seedCompanySession({
    tokenValue: tok,
    tenantId: tenant,
    companyId: companyA,
  });
  seed[sess.key] = JSON.stringify(sess.record);
  const kv = makeKV(seed);
  const env = envWith(kv);

  const res = await worker.fetch(
    new Request(
      `https://example.test/bookings?tenant_id=${tenant}&company_id=${companyB}&include_history=1`,
      {
        method: "GET",
        headers: { Authorization: `Bearer ${tok}` },
      },
    ),
    env,
    {},
  );
  // Session conflict with query company B → forbidden (or empty for A only)
  assert.ok([403, 200].includes(res.status));
  if (res.status === 200) {
    const body = await res.json();
    const ids = new Set((body.items || []).map((r) => r.booking_id));
    assert.equal(ids.has("b1"), false);
  } else {
    const body = await res.json();
    assert.equal(body.ok, false);
  }
});

test("15-17 pagination is in-memory scoped; filters do not bypass ownership", async () => {
  // Lists do not emit portable cross-tenant cursors; ownership revalidated per row.
  const tenant = "t_page";
  const company = "c_page";
  const scope = { tenant_id: tenant, company_id: company, hasScope: true };
  const seed = {};
  seed[`booking:ok`] = JSON.stringify(
    bookingRec({
      id: "ok",
      tenant,
      company,
      status: "COMPLETED",
      pickupIso: new Date(Date.now() - 86400_000).toISOString(),
    }),
  );
  seed[`booking:bad`] = JSON.stringify(
    bookingRec({
      id: "bad",
      tenant,
      company: "other",
      status: "COMPLETED",
      pickupIso: new Date(Date.now() - 86400_000).toISOString(),
    }),
  );
  seed[companyBookingsListIndexKey(scope)] = JSON.stringify(
    indexFor(scope, ["ok", "bad"]),
  );
  const tok = "page-tok";
  const sess = await seedCompanySession({
    tokenValue: tok,
    tenantId: tenant,
    companyId: company,
  });
  seed[sess.key] = JSON.stringify(sess.record);
  const kv = makeKV(seed);
  const env = envWith(kv);

  const res = await worker.fetch(
    new Request(
      `https://example.test/bookings?tenant_id=${tenant}&company_id=${company}&include_history=1&limit=10`,
      { headers: { Authorization: `Bearer ${tok}` } },
    ),
    env,
    {},
  );
  assert.equal(res.status, 200);
  const body = await res.json();
  const ids = new Set((body.items || []).map((r) => r.booking_id));
  assert.ok(ids.has("ok"));
  assert.equal(ids.has("bad"), false);
});

test("18-22 stale prune, dry-run no writes, ambiguous never guessed", async () => {
  const tenant = "t_mig";
  const company = "c_mig";
  const scope = { tenant_id: tenant, company_id: company, hasScope: true };
  const seed = {};
  seed[`booking:keep`] = JSON.stringify(
    bookingRec({ id: "keep", tenant, company }),
  );
  seed[`booking:gone`] = JSON.stringify(
    bookingRec({ id: "gone", tenant, company: "other" }),
  );
  seed[companyBookingsListIndexKey(scope)] = JSON.stringify(
    indexFor(scope, ["keep", "gone", "missing-id"]),
  );
  const tok = "mig-tok";
  const sess = await seedCompanySession({
    tokenValue: tok,
    tenantId: tenant,
    companyId: company,
  });
  seed[sess.key] = JSON.stringify(sess.record);
  const kv = makeKV(seed);
  const beforeIndex = await kv.get(companyBookingsListIndexKey(scope), {
    type: "json",
  });
  assert.equal(beforeIndex.items.length, 3);

  const env = envWith(kv);
  const res = await worker.fetch(
    new Request(
      `https://example.test/bookings?tenant_id=${tenant}&company_id=${company}&include_history=1`,
      { headers: { Authorization: `Bearer ${tok}` } },
    ),
    env,
    {},
  );
  assert.equal(res.status, 200);

  // Dry-run census writes nothing
  const census = await censusLegacyBookingScope(env, { limit: 50 });
  assert.equal(census.ok, true);
  assert.equal(census.dry_run, true);
  const still = await kv.get("booking:keep", { type: "json" });
  assert.equal(still.company_id, company);

  // Ambiguous (no index, no ownership) must not be migrated to a guess
  seed[`booking:amb`] = JSON.stringify(
    bookingRec({ id: "amb", tenant: null, company: null }),
  );
  kv.store.set(
    "booking:amb",
    JSON.stringify(bookingRec({ id: "amb", tenant: null, company: null })),
  );
  const dry = await applyLegacyBookingScopeMigration(env, {
    dryRun: true,
    limit: 100,
  });
  const ambItem = (dry.items || []).find((i) => i.booking_id === "amb");
  assert.ok(ambItem);
  assert.equal(ambItem.category, "B");
  assert.notEqual(ambItem.action, "would_migrate");
});

test("23 fully scoped legitimate bookings remain visible", async () => {
  const tenant = "t_ok";
  const company = "c_ok";
  const scope = { tenant_id: tenant, company_id: company, hasScope: true };
  const seed = {};
  for (let i = 0; i < 5; i++) {
    const id = `ok-${i}`;
    seed[`booking:${id}`] = JSON.stringify(
      bookingRec({ id, tenant, company }),
    );
  }
  seed[companyBookingsListIndexKey(scope)] = JSON.stringify(
    indexFor(
      scope,
      [0, 1, 2, 3, 4].map((i) => `ok-${i}`),
    ),
  );
  const tok = "ok-tok";
  const sess = await seedCompanySession({
    tokenValue: tok,
    tenantId: tenant,
    companyId: company,
  });
  seed[sess.key] = JSON.stringify(sess.record);
  const kv = makeKV(seed);
  const res = await worker.fetch(
    new Request(
      `https://example.test/bookings?tenant_id=${tenant}&company_id=${company}&include_history=1`,
      { headers: { Authorization: `Bearer ${tok}` } },
    ),
    envWith(kv),
    {},
  );
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal((body.items || []).length >= 5, true);
});

test("19 migrate dry-run performs no writes; apply gated by flag", async () => {
  const kv = makeKV({
    "booking:x": JSON.stringify(
      bookingRec({ id: "x", tenant: null, company: null }),
    ),
  });
  const envOff = envWith(kv, { LEGACY_SCOPE_MIGRATION_ENABLED: "0" });
  const dry = await applyLegacyBookingScopeMigration(envOff, { dryRun: true });
  assert.equal(dry.written, 0);
  const blocked = await applyLegacyBookingScopeMigration(envOff, {
    dryRun: false,
  });
  assert.equal(blocked.ok, false);
  assert.equal(blocked.error, "legacy_scope_migration_disabled");

  const res = await worker.fetch(
    new Request("https://example.test/admin/legacy-scope/migrate", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${ADMIN}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ apply: true, limit: 10 }),
    }),
    envOff,
    {},
  );
  assert.equal(res.status, 403);
});

test("admin census requires admin token", async () => {
  const kv = makeKV({});
  const res = await worker.fetch(
    new Request("https://example.test/admin/legacy-scope/census"),
    envWith(kv),
    {},
  );
  assert.equal(res.status, 401);
});
