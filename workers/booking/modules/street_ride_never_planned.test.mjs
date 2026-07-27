// P0-FIELD-REPAIR-1 (A) — a street/direct ride is never returned as planned.
//
// Field defect (3rd recurrence): after STOP, a completed street ride reappeared
// under "Gepland / Planned" in the driver home while ALSO being counted under
// "Voltooid / Completed". Root cause on the read path:
//
//   1. the driver planned/open projection did not exclude street/direct rides;
//   2. a street booking's single synthesized operational leg is a SHADOW of the
//      parent, but a stale leg status (PENDING / SCHEDULED / IN_PROGRESS never
//      cascaded at finalize time) beat the parent's terminal status and the row
//      survived the `status === "COMPLETED"` filter as an open row.
//
// These tests pin the repaired contract AND the behaviour that must not change
// (genuine planned single rides, genuine round-trip legs, history, scoping).
//
// Run: node --test workers/booking/modules/street_ride_never_planned.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import {
  _isStreetDirectRecord,
  _rowIsStreetDirectRide,
  _streetDirectIdentityFieldsForRow,
  _flattenBookingForRidesList,
  _flattenBookingForRidesListWithOperationalLegs,
} from "./booking_read_model.js";
import {
  _excludeStreetDirectFromPlannedProjection,
  listDriverBookingsAuthoritative,
} from "./driver_booking_lists.js";
import { driverScopedBookingsIndexKey } from "./booking_indexes.js";

/* ---- fixtures -------------------------------------------------------- */

const TENANT_A = "tenant_a";
const COMPANY_A = "company_a";
const TENANT_B = "tenant_b";
const COMPANY_B = "company_b";
const DRIVER_A = "driver_a";

const FUTURE_PICKUP = new Date(Date.now() + 60 * 60 * 1000).toISOString();

function streetBooking({
  bookingId = "street_1752863820000_ab12cd34",
  status = "COMPLETED",
  legStatus = null,
  tenantId = TENANT_A,
  companyId = COMPANY_A,
  driverId = DRIVER_A,
  pickupIso = FUTURE_PICKUP,
} = {}) {
  return {
    booking_id: bookingId,
    tenant_id: tenantId,
    company_id: companyId,
    source: "street_ride",
    booking_source: "street_ride",
    ride_type: "direct",
    status,
    assigned_driver_id: driverId,
    ...(legStatus
      ? {
          operational_legs: [
            {
              leg_id: `${bookingId}_outbound`,
              leg_type: "outbound",
              status: legStatus,
              from: "A",
              to: "B",
              pickup_iso: pickupIso,
              assigned_driver_id: driverId,
            },
          ],
        }
      : {}),
    booking: {
      from: "A",
      to: "B",
      pickup_iso: pickupIso,
      status,
      assigned_driver_id: driverId,
    },
    quote: { from: "A", to: "B", pickup_iso: pickupIso, pricing: {} },
  };
}

function plannedBooking({
  bookingId = "BK-2026-000123",
  status = "PENDING",
  tenantId = TENANT_A,
  companyId = COMPANY_A,
  driverId = DRIVER_A,
  pickupIso = FUTURE_PICKUP,
  legs = null,
} = {}) {
  return {
    booking_id: bookingId,
    tenant_id: tenantId,
    company_id: companyId,
    source: "planning",
    booking_source: "planning",
    ride_type: "planned",
    status,
    assigned_driver_id: driverId,
    ...(legs ? { operational_legs: legs } : {}),
    booking: {
      from: "A",
      to: "B",
      pickup_iso: pickupIso,
      status,
      assigned_driver_id: driverId,
    },
    quote: { from: "A", to: "B", pickup_iso: pickupIso, pricing: {} },
  };
}

function roundtripBooking({
  bookingId = "BK-2026-000777",
  parentStatus = "PENDING",
  outboundStatus = "COMPLETED",
  returnStatus = "PENDING",
  driverId = DRIVER_A,
} = {}) {
  return plannedBooking({
    bookingId,
    status: parentStatus,
    driverId,
    legs: [
      {
        leg_id: `${bookingId}_outbound`,
        leg_type: "outbound",
        status: outboundStatus,
        from: "A",
        to: "B",
        pickup_iso: FUTURE_PICKUP,
        assigned_driver_id: driverId,
      },
      {
        leg_id: `${bookingId}_return`,
        leg_type: "return",
        status: returnStatus,
        from: "B",
        to: "A",
        pickup_iso: FUTURE_PICKUP,
        assigned_driver_id: driverId,
      },
    ],
  });
}

/** Minimal in-memory env implementing exactly the KV surface the list reads.
 *
 * Uses the REAL index key builder so the fixture cannot drift from production
 * and silently return an empty list (which would make every exclusion
 * assertion below pass vacuously). */
function makeEnv(records) {
  const kv = new Map();
  for (const rec of records) {
    kv.set(`booking:${rec.booking_id}`, rec);
    const key = driverScopedBookingsIndexKey(
      { tenant_id: rec.tenant_id, company_id: rec.company_id },
      rec.assigned_driver_id,
    );
    if (!key) throw new Error("fixture: driver index key could not be built");
    const existing = kv.get(key) || { items: [] };
    existing.items.push({ booking_id: rec.booking_id });
    existing.updated_at = new Date().toISOString();
    kv.set(key, existing);
  }
  return {
    BOOKING_KV: {
      async get(key, opts) {
        const value = kv.get(key);
        if (value === undefined) return null;
        return opts?.type === "json" ? value : JSON.stringify(value);
      },
      async put(key, value) {
        kv.set(key, typeof value === "string" ? JSON.parse(value) : value);
      },
    },
    __kv: kv,
  };
}

const scopeA = { hasScope: true, tenant_id: TENANT_A, company_id: COMPANY_A };
const sessionA = {
  driver_id: DRIVER_A,
  tenant_id: TENANT_A,
  company_id: COMPANY_A,
};

async function plannedRowsFor(records, { tenantScope = scopeA, driverSession = sessionA } = {}) {
  const env = makeEnv(records);
  const out = await listDriverBookingsAuthoritative(env, {
    limit: 50,
    includeHistory: false,
    tenantScope,
    driverSession,
  });
  assert.equal(out.ok, true, "list must succeed");
  return out.items;
}

const idsOf = (rows) => rows.map((r) => r.booking_id).sort();

/** Control row that MUST always survive the planned projection.
 *
 * Every "street ride is excluded" assertion runs alongside this control so an
 * empty result can never pass vacuously (e.g. if the fixture wiring, the index
 * key or the scope check silently returned nothing). */
const CONTROL_ID = "BK-CONTROL-0001";
const controlBooking = () => plannedBooking({ bookingId: CONTROL_ID });

async function plannedIdsWithControl(records) {
  const rows = await plannedRowsFor([controlBooking(), ...records]);
  const ids = idsOf(rows);
  assert.ok(
    ids.includes(CONTROL_ID),
    "control planned booking must survive — otherwise this assertion is vacuous",
  );
  return ids.filter((id) => id !== CONTROL_ID);
}

/* ---- 1. canonical identity travels with the row ----------------------- */

test("flattened row carries canonical street/direct identity fields", () => {
  const row = _flattenBookingForRidesList(
    "street_1752863820000_ab12cd34",
    streetBooking(),
  );
  assert.equal(row.source, "street_ride");
  assert.equal(row.booking_source, "street_ride");
  assert.equal(row.ride_type, "direct");
  assert.equal(row.is_street_direct, true);
  assert.equal(row.isStreetDirect, true);
});

test("planned row carries a canonical negative hint (never street/direct)", () => {
  const row = _flattenBookingForRidesList("BK-2026-000123", plannedBooking());
  assert.equal(row.is_street_direct, false);
  assert.equal(_rowIsStreetDirectRide(row), false);
});

test("_streetDirectIdentityFieldsForRow never invents values", () => {
  const fields = _streetDirectIdentityFieldsForRow({ booking_id: "BK-1" });
  assert.equal("source" in fields, false);
  assert.equal("ride_type" in fields, false);
  assert.equal(fields.is_street_direct, false);
});

test("_rowIsStreetDirectRide honours hint, then canonical fields, then id", () => {
  assert.equal(_rowIsStreetDirectRide({ is_street_direct: true }), true);
  assert.equal(_rowIsStreetDirectRide({ source: "street_ride" }), true);
  assert.equal(_rowIsStreetDirectRide({ booking_source: "direct_ride" }), true);
  assert.equal(_rowIsStreetDirectRide({ ride_type: "direct" }), true);
  assert.equal(_rowIsStreetDirectRide({ booking_id: "street_abc" }), true);
  assert.equal(_rowIsStreetDirectRide({ booking_id: "BK-1", source: "planning" }), false);
  assert.equal(_rowIsStreetDirectRide(null), false);
});

/* ---- 2. stale shadow leg must not resurrect a terminal street ride ---- */

for (const staleLegStatus of ["PENDING", "SCHEDULED", "IN_PROGRESS"]) {
  test(`completed street parent + stale ${staleLegStatus} shadow leg projects COMPLETED`, () => {
    const rec = streetBooking({ status: "COMPLETED", legStatus: staleLegStatus });
    const rows = _flattenBookingForRidesListWithOperationalLegs(rec.booking_id, rec);
    assert.equal(rows.length, 1, "street ride must project exactly one row");
    assert.equal(
      rows[0].status,
      "COMPLETED",
      `stale ${staleLegStatus} leg must not beat the terminal parent`,
    );
  });

  test(`completed street parent + stale ${staleLegStatus} shadow leg is excluded from planned`, async () => {
    const rec = streetBooking({ status: "COMPLETED", legStatus: staleLegStatus });
    const ids = await plannedIdsWithControl([rec]);
    assert.deepEqual(ids, [], "ghost planned row must not be returned");
  });
}

test("cancelled street parent + stale PENDING shadow leg projects CANCELLED", () => {
  const rec = streetBooking({ status: "CANCELLED", legStatus: "PENDING" });
  const rows = _flattenBookingForRidesListWithOperationalLegs(rec.booking_id, rec);
  assert.equal(rows[0].status, "CANCELLED");
});

/* ---- 3. street/direct never enters planned, in ANY state -------------- */

for (const status of ["PENDING", "IN_PROGRESS", "ACTIVE", "COMPLETED", "CANCELLED"]) {
  test(`street/direct record with status ${status} never enters planned`, async () => {
    const ids = await plannedIdsWithControl([streetBooking({ status })]);
    assert.deepEqual(ids, [], `street ride in ${status} must not be planned`);
  });
}

test("street ride identified by ride_type=direct alone is excluded", async () => {
  const rec = plannedBooking({ bookingId: "BK-2026-000900" });
  rec.ride_type = "direct";
  rec.source = "driver_app";
  rec.booking_source = "driver_app";
  const ids = await plannedIdsWithControl([rec]);
  assert.deepEqual(ids, []);
});

test("street ride identified by street_ id alone is excluded", async () => {
  const rec = plannedBooking({ bookingId: "street_legacy_no_source_fields" });
  delete rec.source;
  delete rec.booking_source;
  delete rec.ride_type;
  const ids = await plannedIdsWithControl([rec]);
  assert.deepEqual(ids, []);
});

/* ---- 4. genuine planned behaviour is preserved ------------------------ */

test("planned single ride remains visible in planned", async () => {
  const rows = await plannedRowsFor([plannedBooking()]);
  assert.deepEqual(idsOf(rows), ["BK-2026-000123"]);
});

test("planned round-trip keeps its open return leg visible", async () => {
  const rec = roundtripBooking({
    outboundStatus: "COMPLETED",
    returnStatus: "PENDING",
  });
  const rows = await plannedRowsFor([rec]);
  assert.equal(rows.length, 1, "only the still-open return leg stays planned");
  assert.equal(rows[0].leg_type, "return");
  assert.equal(rows[0].status, "PENDING");
});

test("round-trip parent COMPLETED still does not overwrite an open return leg", () => {
  const rec = roundtripBooking({
    parentStatus: "COMPLETED",
    outboundStatus: "COMPLETED",
    returnStatus: "PENDING",
  });
  const rows = _flattenBookingForRidesListWithOperationalLegs(rec.booking_id, rec);
  const ret = rows.find((r) => r.leg_type === "return");
  assert.equal(ret.status, "PENDING", "round-trip leg ownership must be unchanged");
});

test("mixed list keeps planned rides and drops only the street ghost", async () => {
  const rows = await plannedRowsFor([
    plannedBooking({ bookingId: "BK-2026-000123" }),
    streetBooking({ status: "COMPLETED", legStatus: "PENDING" }),
    plannedBooking({ bookingId: "BK-2026-000456" }),
  ]);
  assert.deepEqual(idsOf(rows), ["BK-2026-000123", "BK-2026-000456"]);
});

/* ---- 5. history/company projection keeps the canonical street row ----- */

test("include_history=1 still returns the completed street ride", async () => {
  const rec = streetBooking({ status: "COMPLETED", legStatus: "PENDING" });
  const env = makeEnv([rec]);
  const out = await listDriverBookingsAuthoritative(env, {
    limit: 50,
    includeHistory: true,
    tenantScope: scopeA,
    driverSession: sessionA,
  });
  assert.equal(out.ok, true);
  assert.deepEqual(idsOf(out.items), [rec.booking_id]);
});

test("planned exclusion never deletes the canonical record from KV", async () => {
  const rec = streetBooking({ status: "COMPLETED", legStatus: "PENDING" });
  const env = makeEnv([rec]);
  await listDriverBookingsAuthoritative(env, {
    limit: 50,
    includeHistory: false,
    tenantScope: scopeA,
    driverSession: sessionA,
  });
  const stored = await env.BOOKING_KV.get(`booking:${rec.booking_id}`, { type: "json" });
  assert.ok(stored, "canonical street booking must survive in KV");
  assert.equal(stored.source, "street_ride");
  assert.equal(stored.ride_type, "direct");
  assert.equal(stored.status, "COMPLETED");
});

/* ---- 6. tenant/company/driver scoping is preserved -------------------- */

test("tenant A rows never appear for tenant B", async () => {
  const recA = plannedBooking({ bookingId: "BK-A-1" });
  const recB = plannedBooking({
    bookingId: "BK-B-1",
    tenantId: TENANT_B,
    companyId: COMPANY_B,
  });
  const rowsForB = await plannedRowsFor([recA, recB], {
    tenantScope: { hasScope: true, tenant_id: TENANT_B, company_id: COMPANY_B },
    driverSession: { driver_id: DRIVER_A, tenant_id: TENANT_B, company_id: COMPANY_B },
  });
  assert.deepEqual(idsOf(rowsForB), ["BK-B-1"]);
});

test("street exclusion does not leak another tenant's rows into planned", async () => {
  const streetB = streetBooking({
    bookingId: "street_tenant_b",
    tenantId: TENANT_B,
    companyId: COMPANY_B,
  });
  const rows = await plannedRowsFor([plannedBooking(), streetB]);
  assert.deepEqual(idsOf(rows), ["BK-2026-000123"]);
});

/* ---- 7. determinism across refresh / restart -------------------------- */

test("repeated refreshes produce the identical deterministic result", async () => {
  const records = [
    plannedBooking({ bookingId: "BK-2026-000123" }),
    streetBooking({ status: "COMPLETED", legStatus: "IN_PROGRESS" }),
    roundtripBooking(),
  ];
  const env = makeEnv(records);
  const runs = [];
  for (let i = 0; i < 3; i++) {
    const out = await listDriverBookingsAuthoritative(env, {
      limit: 50,
      includeHistory: false,
      tenantScope: scopeA,
      driverSession: sessionA,
    });
    runs.push(idsOf(out.items));
  }
  assert.deepEqual(runs[0], runs[1]);
  assert.deepEqual(runs[1], runs[2]);
  assert.equal(runs[0].includes("street_1752863820000_ab12cd34"), false);
});

/* ---- 8. pure exclusion helper ----------------------------------------- */

test("_excludeStreetDirectFromPlannedProjection preserves order and input", () => {
  const rows = [
    { booking_id: "BK-1", source: "planning" },
    { booking_id: "street_x", source: "street_ride" },
    { booking_id: "BK-2", source: "planning" },
  ];
  const kept = _excludeStreetDirectFromPlannedProjection(rows);
  assert.deepEqual(
    kept.map((r) => r.booking_id),
    ["BK-1", "BK-2"],
  );
  assert.equal(rows.length, 3, "input array must not be mutated");
});

test("_excludeStreetDirectFromPlannedProjection tolerates non-array input", () => {
  assert.deepEqual(_excludeStreetDirectFromPlannedProjection(null), []);
  assert.deepEqual(_excludeStreetDirectFromPlannedProjection(undefined), []);
});

test("_isStreetDirectRecord contract is unchanged", () => {
  assert.equal(_isStreetDirectRecord(streetBooking()), true);
  assert.equal(_isStreetDirectRecord(plannedBooking()), false);
});
