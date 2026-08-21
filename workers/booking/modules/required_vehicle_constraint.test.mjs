// LIMOUSINE-CANONICAL-ENGINE-LINK-P3I — server-authoritative required vehicle.
// Run: node --test workers/booking/modules/required_vehicle_constraint.test.mjs

import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import {
  requiredVehicleIdFromBookingRecord,
  requiredVehicleIdFromRequest,
  vehicleMatchesRequiredVehicle,
} from "./required_vehicle_constraint.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const worker = readFileSync(join(__dirname, "..", "fluxidi_booking_worker.js"), "utf8");

const HUMMER = { vehicle_id: "veh_hummer_white", is_active: true };
const SEDAN = { vehicle_id: "veh_sedan_grey", is_active: true };

// ---------------------------------------------------------------------------
// Constraint semantics
// ---------------------------------------------------------------------------

test("1) an unpinned request accepts every vehicle (taxi/airport unchanged)", () => {
  for (const vehicle of [HUMMER, SEDAN]) {
    assert.equal(vehicleMatchesRequiredVehicle(vehicle, ""), true);
    assert.equal(vehicleMatchesRequiredVehicle(vehicle, null), true);
    assert.equal(vehicleMatchesRequiredVehicle(vehicle, undefined), true);
  }
  assert.equal(requiredVehicleIdFromRequest({ pax: 3, bags: 2 }), "");
  assert.equal(requiredVehicleIdFromRequest(null), "");
});

test("2) a pinned request accepts only the exact vehicle, never a substitute", () => {
  assert.equal(vehicleMatchesRequiredVehicle(HUMMER, "veh_hummer_white"), true);
  assert.equal(vehicleMatchesRequiredVehicle(SEDAN, "veh_hummer_white"), false);
  // An available alternative stays unsuitable: the pool empties instead of
  // silently substituting another car.
  const pool = [SEDAN, HUMMER].filter((v) =>
    vehicleMatchesRequiredVehicle(v, "veh_hummer_white"),
  );
  assert.deepEqual(pool, [HUMMER]);
  const emptyPool = [SEDAN].filter((v) =>
    vehicleMatchesRequiredVehicle(v, "veh_hummer_white"),
  );
  assert.deepEqual(emptyPool, []);
});

test("3) the constraint is read from either spelling and is trimmed", () => {
  assert.equal(
    requiredVehicleIdFromRequest({ required_vehicle_id: " veh_hummer_white " }),
    "veh_hummer_white",
  );
  assert.equal(
    requiredVehicleIdFromRequest({ requiredVehicleId: "veh_hummer_white" }),
    "veh_hummer_white",
  );
  assert.equal(requiredVehicleIdFromRequest({ required_vehicle_id: "" }), "");
});

// ---------------------------------------------------------------------------
// Where the authority comes from
// ---------------------------------------------------------------------------

test("4) the pin is recovered from the sealed accepted-price snapshot", () => {
  const persisted = {
    quote: { limousine_accepted_price: { vehicle_id: "veh_hummer_white" } },
  };
  assert.equal(requiredVehicleIdFromBookingRecord(persisted), "veh_hummer_white");
  assert.equal(
    requiredVehicleIdFromBookingRecord({
      limousine_accepted_price: { vehicle_id: "veh_hummer_white" },
    }),
    "veh_hummer_white",
  );
  assert.equal(
    requiredVehicleIdFromBookingRecord({
      booking: { limousineAcceptedPrice: { vehicleId: "veh_hummer_white" } },
    }),
    "veh_hummer_white",
  );
});

test("5) a client-supplied vehicle_id can never become the pin", () => {
  // Everything below is client-influenced request/booking data. None of it is
  // an acceptance snapshot, so no constraint may be derived from it.
  const clientInjected = {
    payload: { vehicle_id: "veh_attacker_choice" },
    booking: { vehicle_id: "veh_attacker_choice" },
    vehicle_id: "veh_attacker_choice",
    assigned_vehicle_id: "veh_attacker_choice",
  };
  assert.equal(requiredVehicleIdFromBookingRecord(clientInjected), "");
  // A sealed snapshot wins over any client-provided vehicle on the same record.
  assert.equal(
    requiredVehicleIdFromBookingRecord({
      ...clientInjected,
      quote: { limousine_accepted_price: { vehicle_id: "veh_hummer_white" } },
    }),
    "veh_hummer_white",
  );
});

test("6) taxi and airport records yield no constraint at all", () => {
  assert.equal(requiredVehicleIdFromBookingRecord({ quote: { ok: true } }), "");
  assert.equal(requiredVehicleIdFromBookingRecord({}), "");
  assert.equal(requiredVehicleIdFromBookingRecord(null), "");
  assert.equal(
    requiredVehicleIdFromBookingRecord({
      quote: { limousine_accepted_price: { offer_id: "off_1" } },
    }),
    "",
  );
});

// ---------------------------------------------------------------------------
// Worker wiring: one shared predicate, three dispatch paths
// ---------------------------------------------------------------------------

test("7) the constraint is enforced in the single shared candidate-pool predicate", () => {
  assert.ok(
    worker.includes(
      "if (!_vehicleMatchesRequiredVehicle(vehicle, _requiredVehicleIdFromRequest(req))) {",
    ),
  );
  // Every candidate pool in the Worker is built with that one predicate, so
  // the pin cannot be bypassed by a pool that forgot about it.
  const poolBuilds =
    worker.match(/vehicles\.filter\(\(v\) => _vehicleSupportsRequest\(v, req\)\)/g) || [];
  assert.ok(poolBuilds.length >= 3, `expected >=3 pool builds, got ${poolBuilds.length}`);
  // The allocator itself carries no limousine branching.
  assert.ok(!worker.includes("if (isLimousine) {"));
});

test("8) path A: the postponed-reserve capacity gate checks the exact vehicle", () => {
  const start = worker.indexOf("async function _vehicleCapacityGateForRoundtripDispatch");
  assert.ok(start > 0);
  const gate = worker.slice(start, start + 2600);
  assert.ok(gate.includes("requiredVehicleId = \"\""));
  assert.ok(gate.includes("_requiredVehicleIdFromBookingRecord(rec)"));
  assert.ok(gate.includes("...(pinnedVehicleId ? { required_vehicle_id: pinnedVehicleId } : {})"));
  // `common` is spread into both the single-leg and the split-leg gate calls.
  assert.ok(gate.includes("...common,"));
});

test("9) path B: booking creation reserves the exact vehicle via the allocator", () => {
  const start = worker.indexOf("async function _runBookingCreationFleetDispatch");
  assert.ok(start > 0);
  const dispatch = worker.slice(start, start + 3200);
  assert.ok(dispatch.includes("requiredVehicleId = \"\""));
  assert.ok(dispatch.includes("requiredVehicleId,"));
  // The allocator request itself carries the constraint.
  assert.ok(
    worker.includes("{ required_vehicle_id: safeStr(requiredVehicleId, 128) }"),
  );
  assert.ok(worker.includes("...(pinnedVehicleId ? { required_vehicle_id: pinnedVehicleId } : {}),"));
});

test("10) path C: post-payment auto dispatch recovers the same pin from the record", () => {
  // ensurePaidOpenBookingAutoDispatched hands the persisted record to the
  // shared dispatcher, which re-derives the constraint from the sealed
  // snapshot rather than from a lost local variable.
  const start = worker.indexOf("async function _dispatchFleetAssignmentForBooking");
  assert.ok(start > 0);
  const dispatcher = worker.slice(start, start + 1800);
  assert.ok(dispatcher.includes("requiredVehicleId = \"\""));
  assert.ok(
    dispatcher.includes(
      "safeStr(requiredVehicleId, 128) || _requiredVehicleIdFromBookingRecord(rec)",
    ),
  );
  const autoStart = worker.indexOf("async function ensurePaidOpenBookingAutoDispatched");
  assert.ok(autoStart > start);
  const auto = worker.slice(autoStart, autoStart + 12000);
  assert.ok(auto.includes("_dispatchFleetAssignmentForBooking(env, {"));
  assert.ok(auto.includes("rec,"));
});

test("11) the allocator honours the pin and refuses a mismatched reservation", () => {
  assert.ok(worker.includes("body?.required_vehicle_id ?? body?.requiredVehicleId"));
  assert.ok(
    worker.includes("...(requiredVehicleId ? { required_vehicle_id: requiredVehicleId } : {}),"),
  );
  // A retried allocation must never report a pinned booking as allocated
  // against a different car.
  assert.ok(worker.includes("if (requiredVehicleId && reservedVehicleId !== requiredVehicleId) {"));
  assert.ok(worker.includes("[FLEET_ALLOCATOR][REQUIRED_VEHICLE_MISMATCH]"));
  // Fail-closed reason, distinct from a generic capacity rejection.
  const reasons = worker.match(/"required_vehicle_unavailable"/g) || [];
  assert.ok(reasons.length >= 4, `expected >=4 fail-closed reasons, got ${reasons.length}`);
});

test("12) handleBooking derives the pin from the snapshot, not from the payload", () => {
  const marker = "const _limousineRequiredVehicleId = safeStr(";
  const at = worker.indexOf(marker);
  assert.ok(at > 0);
  const assignment = worker.slice(at, at + 200);
  assert.ok(assignment.includes("_limousineAccepted?.snapshot?.vehicle_id"));
  assert.ok(!assignment.includes("payload"));
  // All four canonical dispatch entry points receive it.
  const wired = worker.match(/requiredVehicleId: _limousineRequiredVehicleId,/g) || [];
  assert.equal(wired.length, 4);
});

// ---------------------------------------------------------------------------
// Idempotency hardening
// ---------------------------------------------------------------------------

test("13) accepted-quote bookings are keyed on the stable quote request id", () => {
  assert.ok(worker.includes("const _limousineAcceptedQuoteRequestId = sanitizeTenantString("));
  assert.ok(worker.includes("_limousineManualQuoteRecord?.quote_request_id"));
  assert.ok(
    worker.includes("...(_limousineAcceptedQuoteRequestId\n              ? [_limousineAcceptedQuoteRequestId]\n              : []),"),
  );
  // Appended conditionally, so unrelated bookings keep their intent hash.
  const intentStart = worker.indexOf("extra_intent_parts: _limousineAccepted");
  assert.ok(intentStart > 0);
  assert.ok(worker.slice(intentStart, intentStart + 1400).includes(": [],"));
});

test("14) no parallel limousine dispatch engine was introduced", () => {
  assert.ok(!worker.includes("/limousine/book"));
  assert.ok(!worker.includes("LimousineFleetAllocator"));
  assert.ok(!worker.includes("async function _dispatchLimousineVehicle"));
  const constraintModule = readFileSync(
    join(__dirname, "required_vehicle_constraint.mjs"),
    "utf8",
  );
  // The constraint is a product-neutral concept: it names no service and
  // branches on none. It only knows which field holds a sealed snapshot.
  const exported = constraintModule.match(/export function (\w+)/g) || [];
  assert.deepEqual(exported, [
    "export function requiredVehicleIdFromRequest",
    "export function vehicleMatchesRequiredVehicle",
    "export function requiredVehicleIdFromBookingRecord",
  ]);
  assert.ok(!constraintModule.includes("service_category"));
  assert.ok(!constraintModule.includes("service_type"));
  assert.ok(!constraintModule.includes("isLimousine"));
});
