// COMPANY-DISPATCH-P0 — eligibility, roster, presence and assignment rules.

import { test } from "node:test";
import assert from "node:assert/strict";

import {
  ASSIGNMENT_SAFETY_MARGIN_MIN,
  AVAILABILITY,
  copyRosterDay,
  companyDriverPresenceLabel,
  decorateDriverForDispatch,
  defaultManualOverride,
  evaluateDriverEligibility,
  evaluateVehicleEligibility,
  expandWindowsWithSafetyMargin,
  isLiveConnected,
  mergePresenceHeartbeat,
  nextShiftBoundaryMs,
  normalizeWeeklyRoster,
  resolveAutoVehicle,
  resolveScheduleState,
  rideIsSoon,
  scheduledActiveAt,
  weeklyRosterIsConfigured,
  scheduleConflictAt,
  scheduledSlotAt,
  syncDriverAvailabilityForBookingStatus,
} from "./modules/company_dispatch.mjs";
import {
  assignAgendaRide,
  createAgendaRide,
  listAssignmentChoices,
  unassignAgendaRide,
} from "./modules/company_agenda.mjs";

const TZ = "Europe/Brussels";

function rosterNineToFive() {
  return normalizeWeeklyRoster({
    timezone: TZ,
    days: {
      mon: [{ start: "09:00", end: "17:00" }],
      tue: [{ start: "09:00", end: "17:00" }],
      wed: [{ start: "09:00", end: "17:00" }],
      thu: [{ start: "09:00", end: "17:00" }],
      fri: [{ start: "09:00", end: "17:00" }],
      sat: [],
      sun: [],
    },
  });
}

function nightRoster() {
  return normalizeWeeklyRoster({
    timezone: TZ,
    days: {
      fri: [{ start: "22:00", end: "06:00" }],
    },
  });
}

test("week rooster: weekday block is active, weekend is not", () => {
  const roster = rosterNineToFive();
  assert.equal(scheduledActiveAt(roster, Date.parse("2026-09-14T10:00:00.000Z")), true);
  assert.equal(scheduledActiveAt(roster, Date.parse("2026-09-14T06:00:00.000Z")), false);
  assert.equal(scheduledActiveAt(roster, Date.parse("2026-09-12T10:00:00.000Z")), false);
});

test("multiple blocks on one day cover only those windows", () => {
  const roster = normalizeWeeklyRoster({
    timezone: TZ,
    days: {
      mon: [
        { start: "07:00", end: "11:00" },
        { start: "16:00", end: "20:00" },
      ],
    },
  });
  assert.equal(scheduledActiveAt(roster, Date.parse("2026-09-14T06:30:00.000Z")), true);
  assert.equal(scheduledActiveAt(roster, Date.parse("2026-09-14T11:00:00.000Z")), false);
  assert.equal(scheduledActiveAt(roster, Date.parse("2026-09-14T15:00:00.000Z")), true);
});

test("copy roster day to other days", () => {
  const copied = copyRosterDay(rosterNineToFive(), "mon", ["sat", "sun"]);
  assert.equal(copied.days.sat.length, 1);
  assert.equal(copied.days.sat[0].start, "09:00");
  assert.equal(scheduledActiveAt(copied, Date.parse("2026-09-12T10:00:00.000Z")), true);
});

test("night shift 22:00-06:00 covers after midnight", () => {
  const roster = nightRoster();
  assert.equal(scheduledActiveAt(roster, Date.parse("2026-09-11T20:30:00.000Z")), true);
  assert.equal(scheduledActiveAt(roster, Date.parse("2026-09-12T03:30:00.000Z")), true);
  assert.equal(scheduledActiveAt(roster, Date.parse("2026-09-12T05:00:00.000Z")), false);
});

test("leave exception turns a roster day off", () => {
  const roster = rosterNineToFive();
  assert.equal(
    scheduledActiveAt(roster, Date.parse("2026-09-14T10:00:00.000Z"), [{ date: "2026-09-14", type: "off" }]),
    false,
  );
});

test("manual inactive wins during a shift until the next boundary", () => {
  const roster = rosterNineToFive();
  const at = Date.parse("2026-09-14T10:00:00.000Z");
  const override = defaultManualOverride("inactive", at, roster, []);
  const driver = {
    driver_id: "drv_1",
    is_active: true,
    weekly_roster: roster,
    manual_override: override,
    availability_status: "available",
    assigned_vehicle_id: "vh_1",
  };
  const result = evaluateDriverEligibility({
    driver,
    presence: { last_seen_at: new Date(at).toISOString() },
    vehicles: [{ vehicle_id: "vh_1", is_active: true, assigned_driver_id: "drv_1" }],
    atMs: at,
    pickupIso: new Date(at + 2 * 60 * 60 * 1000).toISOString(),
    soon: false,
  });
  assert.equal(result.ok, false);
  assert.equal(result.error, "assignment_driver_not_scheduled");
  assert.ok(Date.parse(override.until) > at);
});

test("manual active outside the roster remains possible", () => {
  const roster = rosterNineToFive();
  const at = Date.parse("2026-09-12T10:00:00.000Z");
  const driver = {
    driver_id: "drv_1",
    is_active: true,
    weekly_roster: roster,
    manual_override: defaultManualOverride("active", at, roster, []),
    availability_status: "available",
    assigned_vehicle_id: "vh_1",
  };
  const result = evaluateDriverEligibility({
    driver,
    vehicles: [{ vehicle_id: "vh_1", is_active: true }],
    atMs: at,
    pickupIso: new Date(at + 24 * 60 * 60 * 1000).toISOString(),
    soon: false,
  });
  assert.equal(result.ok, true, JSON.stringify(result));
});

test("DST spring-forward keeps Brussels hour math honest", () => {
  const roster = normalizeWeeklyRoster({
    timezone: TZ,
    days: { sun: [{ start: "02:30", end: "06:00" }] },
  });
  assert.equal(scheduledActiveAt(roster, Date.parse("2026-03-29T01:00:00.000Z")), true);
  assert.equal(scheduledActiveAt(roster, Date.parse("2026-03-29T00:15:00.000Z")), false);
});

test("expired heartbeat is never live", () => {
  const now = Date.parse("2026-09-14T12:00:00.000Z");
  assert.equal(isLiveConnected({ last_seen_at: "2026-09-14T11:59:00.000Z" }, now), true);
  assert.equal(isLiveConnected({ last_seen_at: "2026-09-14T11:56:00.000Z" }, now), false);
  assert.equal(isLiveConnected({}, now), false);
});

test("presence labels keep account, shift, availability and live separate", () => {
  const working = { account_active: true, blocked: false, scheduled_active: true, working: true };
  assert.equal(
    companyDriverPresenceLabel({ work: working, availability: AVAILABILITY.AVAILABLE, live: true }),
    "available",
  );
  assert.equal(
    companyDriverPresenceLabel({ work: working, availability: AVAILABILITY.ON_TRIP, live: true }),
    "on_trip",
  );
  assert.equal(
    companyDriverPresenceLabel({ work: working, availability: AVAILABILITY.AVAILABLE, live: false }),
    "scheduled_no_live",
  );
  assert.equal(
    companyDriverPresenceLabel({ work: working, availability: AVAILABILITY.PAUSED, live: true }),
    "paused",
  );
  assert.equal(
    companyDriverPresenceLabel({
      work: { ...working, scheduled_active: false, working: false },
      availability: AVAILABILITY.OFFLINE,
      live: false,
    }),
    "offline_work",
  );
  assert.equal(
    companyDriverPresenceLabel({
      work: { ...working, scheduled_active: false, working: true },
      availability: AVAILABILITY.AVAILABLE,
      live: false,
    }),
    "connection_lost",
  );
});

test("heartbeat writes are throttled", () => {
  const first = mergePresenceHeartbeat({}, "drv_1", Date.parse("2026-09-14T12:00:00.000Z"));
  assert.equal(first.changed, true);
  const second = mergePresenceHeartbeat(first.record, "drv_1", Date.parse("2026-09-14T12:00:20.000Z"));
  assert.equal(second.changed, false);
  const third = mergePresenceHeartbeat(first.record, "drv_1", Date.parse("2026-09-14T12:01:00.000Z"));
  assert.equal(third.changed, true);
});

test("soon rides require live AVAILABLE driver with a linked vehicle", () => {
  const at = Date.parse("2026-09-14T12:00:00.000Z");
  const driver = {
    driver_id: "drv_1",
    is_active: true,
    weekly_roster: rosterNineToFive(),
    availability_status: "available",
    assigned_vehicle_id: "vh_1",
  };
  const vehicles = [{ vehicle_id: "vh_1", is_active: true, assigned_driver_id: "drv_1" }];
  const pickupIso = new Date(at + 10 * 60 * 1000).toISOString();
  assert.equal(rideIsSoon(pickupIso, at), true);
  const missingLive = evaluateDriverEligibility({
    driver,
    vehicles,
    atMs: at,
    pickupIso,
  });
  assert.equal(missingLive.ok, false);
  assert.equal(missingLive.error, "assignment_driver_not_live");
  const ok = evaluateDriverEligibility({
    driver,
    presence: { last_seen_at: new Date(at).toISOString() },
    vehicles,
    atMs: at,
    pickupIso,
  });
  assert.equal(ok.ok, true, JSON.stringify(ok));
});

test("future rides do not require a live connection", () => {
  const at = Date.parse("2026-09-14T12:00:00.000Z");
  const pickupIso = "2026-09-16T08:00:00.000Z";
  const result = evaluateDriverEligibility({
    driver: {
      driver_id: "drv_1",
      is_active: true,
      weekly_roster: rosterNineToFive(),
      availability_status: "paused",
      assigned_vehicle_id: "vh_1",
    },
    vehicles: [{ vehicle_id: "vh_1", is_active: true }],
    atMs: at,
    pickupIso,
    soon: false,
  });
  assert.equal(result.ok, false);
  assert.equal(result.error, "assignment_driver_paused");
  const futureOk = evaluateDriverEligibility({
    driver: {
      driver_id: "drv_1",
      is_active: true,
      weekly_roster: rosterNineToFive(),
      availability_status: "offline",
      assigned_vehicle_id: "vh_1",
    },
    vehicles: [{ vehicle_id: "vh_1", is_active: true }],
    atMs: at,
    pickupIso,
    soon: false,
  });
  assert.equal(futureOk.ok, true, JSON.stringify(futureOk));
});

test("unique linked vehicle is auto-selected; multiple stay choosable", () => {
  const driver = { driver_id: "drv_1", assigned_vehicle_id: "vh_1", vehicle_ids: ["vh_1", "vh_2"] };
  const one = resolveAutoVehicle({
    driver: { driver_id: "drv_1", assigned_vehicle_id: "vh_1" },
    vehicles: [{ vehicle_id: "vh_1", is_active: true }],
    drivers: [driver],
    atMs: Date.now(),
  });
  assert.equal(one.ok, true);
  assert.equal(one.auto, true);
  assert.equal(one.vehicleId, "vh_1");

  const many = resolveAutoVehicle({
    driver,
    vehicles: [
      { vehicle_id: "vh_1", is_active: true },
      { vehicle_id: "vh_2", is_active: true },
    ],
    drivers: [driver],
    atMs: Date.now(),
  });
  assert.equal(many.ok, false);
  assert.equal(many.error, "assignment_vehicle_choice_required");
  assert.equal(many.choices.length, 2);
});

test("vehicle on another active shift is rejected", () => {
  const at = Date.parse("2026-09-14T10:00:00.000Z");
  const other = {
    driver_id: "drv_other",
    assigned_vehicle_id: "vh_1",
    is_active: true,
    weekly_roster: rosterNineToFive(),
    availability_status: "available",
  };
  const check = evaluateVehicleEligibility({
    vehicle: { vehicle_id: "vh_1", is_active: true },
    drivers: [other],
    driver: { driver_id: "drv_1" },
    atMs: at,
  });
  assert.equal(check.ok, false);
  assert.equal(check.error, "assignment_vehicle_busy");
});

test("safety margin extends the occupancy window by 15 minutes", () => {
  const start = Date.parse("2026-09-14T08:00:00.000Z");
  const end = Date.parse("2026-09-14T08:40:00.000Z");
  const expanded = expandWindowsWithSafetyMargin([{ start, end }], ASSIGNMENT_SAFETY_MARGIN_MIN);
  assert.equal(expanded[0].end - expanded[0].start, 70 * 60000);
});

test("ride start and end flip stored availability", async () => {
  const store = new Map();
  const key = "tenant:TA:company:CA:drivers:index:v1";
  store.set(key, JSON.stringify({
    drivers: {
      drv_1: { driver_id: "drv_1", availability_status: "available" },
    },
  }));
  const env = {
    BOOKING_KV: {
      async get(name, opts) {
        const raw = store.get(name);
        if (!raw) return null;
        return opts?.type === "json" ? JSON.parse(raw) : raw;
      },
      async put(name, value) {
        store.set(name, value);
      },
    },
  };
  const started = await syncDriverAvailabilityForBookingStatus(env, {
    scope: { tenant_id: "TA", company_id: "CA" },
    driverId: "drv_1",
    status: "IN_PROGRESS",
  });
  assert.equal(started.changed, true);
  assert.equal(JSON.parse(store.get(key)).drivers.drv_1.availability_status, "busy");
  const ended = await syncDriverAvailabilityForBookingStatus(env, {
    scope: { tenant_id: "TA", company_id: "CA" },
    driverId: "drv_1",
    status: "COMPLETED",
  });
  assert.equal(ended.changed, true);
  assert.equal(JSON.parse(store.get(key)).drivers.drv_1.availability_status, "available");
});

function memoryKV(seed = {}) {
  const store = new Map();
  for (const [key, value] of Object.entries(seed)) {
    store.set(key, typeof value === "string" ? value : JSON.stringify(value));
  }
  return {
    store,
    async get(key, opts) {
      if (!store.has(key)) return null;
      const raw = store.get(key);
      return opts?.type === "json" ? JSON.parse(raw) : raw;
    },
    async put(key, value) {
      store.set(key, value);
    },
    async delete(key) {
      store.delete(key);
    },
    async list() {
      return { keys: [], list_complete: true };
    },
  };
}

function seedEligibleDriver(kv, extra = {}) {
  const roster = rosterNineToFive();
  kv.store.set("tenant:TA:company:CA:drivers:index:v1", JSON.stringify({
    drivers: {
      drv_eli: {
        driver_id: "drv_eli",
        display_name: "Eli",
        is_active: true,
        availability_status: "available",
        assigned_vehicle_id: "vh_eli",
        weekly_roster: roster,
        ...extra,
      },
      drv_other: {
        driver_id: "drv_other",
        display_name: "Other",
        is_active: true,
        availability_status: "available",
        assigned_vehicle_id: "vh_other",
        weekly_roster: roster,
      },
    },
  }));
  kv.store.set("tenant:TA:company:CA:fleet:vehicles:v1", JSON.stringify({
    vehicles: [
      { vehicle_id: "vh_eli", is_active: true, assigned_driver_id: "drv_eli" },
      { vehicle_id: "vh_other", is_active: true, assigned_driver_id: "drv_other" },
    ],
  }));
}

test("future assignment auto-selects the unique vehicle and unassign stays separate", async () => {
  const kv = memoryKV();
  seedEligibleDriver(kv);
  const env = { BOOKING_KV: kv };
  const created = await createAgendaRide(env, {
    scope: { tenant_id: "TA", company_id: "CA" },
    body: {
      customer_id: "cus_1",
      from: "Gent",
      to: "Ronse",
      pickup_iso: "2026-09-16T08:00:00.000Z",
      duration_min: 40,
    },
    idempotencyKey: "assign-future",
  });
  assert.equal(created.ok, true, JSON.stringify(created));
  const assigned = await assignAgendaRide(env, {
    scope: { tenant_id: "TA", company_id: "CA" },
    bookingId: created.booking_id,
    body: { assigned_driver_id: "drv_eli", revision: 1 },
  });
  assert.equal(assigned.ok, true, JSON.stringify(assigned));
  assert.equal(assigned.item.assigned_driver_id, "drv_eli");
  assert.equal(assigned.item.assigned_vehicle_id, "vh_eli");
  const choices = await listAssignmentChoices(env, {
    scope: { tenant_id: "TA", company_id: "CA" },
    pickupIso: "2026-09-16T08:00:00.000Z",
    durationMin: 40,
    currentDriverId: "drv_eli",
    now: "2026-09-14T10:00:00.000Z",
  });
  assert.equal(choices.current_driver.driver_id, "drv_eli");
  assert.equal(choices.drivers.some((row) => row.driver_id === "drv_eli"), false);
  const freed = await unassignAgendaRide(env, {
    scope: { tenant_id: "TA", company_id: "CA" },
    bookingId: created.booking_id,
    body: { revision: 2 },
  });
  assert.equal(freed.ok, true, JSON.stringify(freed));
  assert.equal(freed.item.assigned_driver_id || "", "");
});

test("overlapping driver and vehicle assignments are rejected", async () => {
  const kv = memoryKV();
  seedEligibleDriver(kv);
  const env = { BOOKING_KV: kv };
  const first = await createAgendaRide(env, {
    scope: { tenant_id: "TA", company_id: "CA" },
    body: {
      customer_id: "cus_1",
      from: "Gent",
      to: "Ronse",
      pickup_iso: "2026-09-16T08:00:00.000Z",
      duration_min: 60,
      assigned_driver_id: "drv_eli",
      assigned_vehicle_id: "vh_eli",
    },
    idempotencyKey: "ov-1",
  });
  assert.equal(first.ok, true);
  const second = await createAgendaRide(env, {
    scope: { tenant_id: "TA", company_id: "CA" },
    body: {
      customer_id: "cus_2",
      from: "Gent",
      to: "Oudenaarde",
      pickup_iso: "2026-09-16T08:20:00.000Z",
      duration_min: 40,
    },
    idempotencyKey: "ov-2",
  });
  const overlapDriver = await assignAgendaRide(env, {
    scope: { tenant_id: "TA", company_id: "CA" },
    bookingId: second.booking_id,
    body: { assigned_driver_id: "drv_eli" },
  });
  assert.equal(overlapDriver.ok, false);
  assert.equal(overlapDriver.error, "assignment_overlap");
  const overlapVehicle = await assignAgendaRide(env, {
    scope: { tenant_id: "TA", company_id: "CA" },
    bookingId: second.booking_id,
    body: { assigned_driver_id: "drv_other", assigned_vehicle_id: "vh_eli" },
  });
  assert.equal(overlapVehicle.ok, false);
  assert.match(String(overlapVehicle.error), /assignment_vehicle|assignment_overlap/);
});

test("empty roster is not configured and does not refuse assignment", () => {
  assert.equal(weeklyRosterIsConfigured(null), false);
  assert.equal(weeklyRosterIsConfigured({ timezone: TZ, days: {} }), false);
  const at = Date.parse("2026-09-14T12:00:00.000Z");
  const pickupIso = "2026-09-16T08:00:00.000Z";
  const result = evaluateDriverEligibility({
    driver: {
      driver_id: "drv_1",
      is_active: true,
      weekly_roster: null,
      availability_status: "available",
      assigned_vehicle_id: "vh_1",
    },
    vehicles: [{ vehicle_id: "vh_1", is_active: true }],
    atMs: at,
    pickupIso,
    soon: false,
  });
  assert.equal(result.ok, true, JSON.stringify(result));
  assert.equal(result.reasons.includes("assignment_driver_not_scheduled"), false);
});

test("a consciously empty saved roster is not the same as never set", () => {
  const emptySaved = { timezone: TZ, days: {}, explicitly_set: true };
  assert.equal(weeklyRosterIsConfigured(emptySaved), true);
  assert.equal(weeklyRosterIsConfigured({ timezone: TZ, days: {} }), false);
  const at = Date.parse("2026-09-14T12:00:00.000Z");
  const refused = evaluateDriverEligibility({
    driver: {
      driver_id: "drv_1",
      is_active: true,
      weekly_roster: emptySaved,
      availability_status: "available",
      assigned_vehicle_id: "vh_1",
    },
    vehicles: [{ vehicle_id: "vh_1", is_active: true }],
    atMs: at,
    pickupIso: "2026-09-16T08:00:00.000Z",
    soon: false,
  });
  assert.equal(refused.ok, false);
  assert.equal(refused.error, "assignment_driver_not_scheduled");
});

test("a planned break is named separately from off-hours", () => {
  const roster = {
    timezone: TZ,
    days: {
      mon: [{ start: "09:00", end: "17:00", breaks: [{ start: "12:00", end: "12:30" }] }],
    },
  };
  const breakAt = Date.parse("2026-09-14T10:15:00.000Z");
  const slot = scheduledSlotAt(roster, breakAt);
  assert.equal(slot.inBreak, true);
  assert.equal(scheduleConflictAt(roster, breakAt), "assignment_driver_planned_break");
  const result = evaluateDriverEligibility({
    driver: {
      driver_id: "drv_1",
      is_active: true,
      weekly_roster: roster,
      availability_status: "available",
      assigned_vehicle_id: "vh_1",
    },
    vehicles: [{ vehicle_id: "vh_1", is_active: true }],
    atMs: Date.parse("2026-09-14T08:00:00.000Z"),
    pickupIso: "2026-09-14T10:15:00.000Z",
    soon: false,
  });
  assert.equal(result.error, "assignment_driver_planned_break");
});

test("a configured roster outside hours still refuses", () => {
  const at = Date.parse("2026-09-14T12:00:00.000Z");
  const result = evaluateDriverEligibility({
    driver: {
      driver_id: "drv_1",
      is_active: true,
      weekly_roster: rosterNineToFive(),
      availability_status: "available",
      assigned_vehicle_id: "vh_1",
    },
    vehicles: [{ vehicle_id: "vh_1", is_active: true }],
    atMs: at,
    pickupIso: "2026-09-14T20:00:00.000Z",
    soon: false,
  });
  assert.equal(result.ok, false);
  assert.equal(result.error, "assignment_driver_outside_hours");
});

test("failed roster load is undeterminable, not empty", () => {
  const at = Date.parse("2026-09-14T12:00:00.000Z");
  const result = evaluateDriverEligibility({
    driver: {
      driver_id: "drv_1",
      is_active: true,
      weekly_roster: null,
      weekly_roster_load_failed: true,
      availability_status: "available",
      assigned_vehicle_id: "vh_1",
    },
    vehicles: [{ vehicle_id: "vh_1", is_active: true }],
    atMs: at,
    pickupIso: "2026-09-16T08:00:00.000Z",
    soon: false,
  });
  assert.equal(result.ok, false);
  assert.equal(result.error, "assignment_schedule_undeterminable");
  assert.equal(result.reasons.includes("assignment_driver_not_scheduled"), false);
});

test("unsupported timezone is undeterminable", () => {
  const state = resolveScheduleState(
    {
      timezone: "Not/AZone",
      days: { mon: [{ start: "09:00", end: "17:00" }] },
    },
    Date.parse("2026-09-14T10:00:00.000Z"),
  );
  assert.equal(state.undeterminable, true);
  const result = evaluateDriverEligibility({
    driver: {
      driver_id: "drv_1",
      is_active: true,
      weekly_roster: {
        timezone: "Not/AZone",
        days: { mon: [{ start: "09:00", end: "17:00" }] },
      },
      availability_status: "available",
      assigned_vehicle_id: "vh_1",
    },
    vehicles: [{ vehicle_id: "vh_1", is_active: true }],
    atMs: Date.parse("2026-09-14T12:00:00.000Z"),
    pickupIso: "2026-09-16T08:00:00.000Z",
    soon: false,
  });
  assert.equal(result.error, "assignment_schedule_undeterminable");
});

test("a pickup that already started is not soon", () => {
  const pickup = Date.parse("2026-09-16T18:00:00.000Z");
  const attempt = Date.parse("2026-09-16T18:29:00.000Z");
  assert.equal(rideIsSoon(new Date(pickup).toISOString(), attempt), false);
  assert.equal(rideIsSoon(new Date(attempt + 10 * 60 * 1000).toISOString(), attempt), true);
});

test("a Nu stamp a few seconds in the past stays soon", () => {
  const now = Date.parse("2026-09-18T16:00:08.000Z");
  const stamped = Date.parse("2026-09-18T16:00:00.000Z");
  assert.equal(rideIsSoon(new Date(stamped).toISOString(), now), true);
  assert.equal(
    rideIsSoon(new Date(now - 5 * 60 * 1000).toISOString(), now),
    false,
  );
});

test("past pickup without a roster is not blocked as unscheduled or not-live", () => {
  const pickupIso = "2026-09-16T18:00:00.000Z";
  const at = Date.parse("2026-09-16T18:29:00.000Z");
  const result = evaluateDriverEligibility({
    driver: {
      driver_id: "drv_1",
      is_active: true,
      weekly_roster: null,
      availability_status: "available",
      assigned_vehicle_id: "vh_1",
    },
    vehicles: [{ vehicle_id: "vh_1", is_active: true }],
    atMs: at,
    pickupIso,
  });
  assert.equal(result.soon, false);
  assert.equal(result.reasons.includes("assignment_driver_not_scheduled"), false);
  assert.equal(result.reasons.includes("assignment_driver_not_live"), false);
  assert.equal(result.ok, true, JSON.stringify(result));
});

test("empty-roster assign persists; overlap and self-exclude stay enforced", async () => {
  const kv = memoryKV();
  kv.store.set("tenant:TA:company:CA:drivers:index:v1", JSON.stringify({
    drivers: {
      drv_chris: {
        driver_id: "drv_chris",
        display_name: "Christophe",
        is_active: true,
        availability_status: "available",
        assigned_vehicle_id: "vh_chris",
      },
      drv_wotan: {
        driver_id: "drv_wotan",
        display_name: "Wotan",
        is_active: true,
        availability_status: "available",
        assigned_vehicle_id: "vh_wotan",
      },
    },
  }));
  kv.store.set("tenant:TA:company:CA:fleet:vehicles:v1", JSON.stringify({
    vehicles: [
      { vehicle_id: "vh_chris", is_active: true, assigned_driver_id: "drv_chris" },
      { vehicle_id: "vh_wotan", is_active: true, assigned_driver_id: "drv_wotan" },
    ],
  }));
  const env = { BOOKING_KV: kv };
  const created = await createAgendaRide(env, {
    scope: { tenant_id: "TA", company_id: "CA" },
    body: {
      customer_id: "cus_1",
      from: "Gent",
      to: "Ronse",
      pickup_iso: "2026-09-16T18:00:00.000Z",
      duration_min: 40,
    },
    idempotencyKey: "empty-roster-assign",
  });
  assert.equal(created.ok, true, JSON.stringify(created));
  const first = await assignAgendaRide(env, {
    scope: { tenant_id: "TA", company_id: "CA" },
    bookingId: created.booking_id,
    body: { assigned_driver_id: "drv_chris", revision: 1 },
  });
  assert.equal(first.ok, true, JSON.stringify(first));
  assert.equal(first.item.assigned_driver_id, "drv_chris");
  const switched = await assignAgendaRide(env, {
    scope: { tenant_id: "TA", company_id: "CA" },
    bookingId: created.booking_id,
    body: { assigned_driver_id: "drv_wotan", revision: 2 },
  });
  assert.equal(switched.ok, true, JSON.stringify(switched));
  assert.equal(switched.item.assigned_driver_id, "drv_wotan");
  const other = await createAgendaRide(env, {
    scope: { tenant_id: "TA", company_id: "CA" },
    body: {
      customer_id: "cus_2",
      from: "Gent",
      to: "Oudenaarde",
      pickup_iso: "2026-09-16T18:10:00.000Z",
      duration_min: 40,
    },
    idempotencyKey: "empty-roster-overlap",
  });
  const overlap = await assignAgendaRide(env, {
    scope: { tenant_id: "TA", company_id: "CA" },
    bookingId: other.booking_id,
    body: { assigned_driver_id: "drv_wotan" },
  });
  assert.equal(overlap.ok, false);
  assert.equal(overlap.error, "assignment_overlap");
});

test("fleet load failure refuses instead of looking like no roster", async () => {
  const booking = {
    booking_id: "agb_load",
    tenant_id: "TA",
    company_id: "CA",
    customer_id: "cus_1",
    from: "Gent",
    to: "Ronse",
    pickup_iso: "2026-09-16T18:00:00.000Z",
    status: "PENDING",
    revision: 1,
    duration_min: 40,
  };
  const env = {
    BOOKING_KV: {
      async get(key, opts) {
        if (String(key).startsWith("booking:")) {
          return opts?.type === "json" ? booking : JSON.stringify(booking);
        }
        throw new Error("kv_unavailable");
      },
      async put() {},
      async delete() {},
    },
  };
  const assigned = await assignAgendaRide(env, {
    scope: { tenant_id: "TA", company_id: "CA" },
    bookingId: "agb_load",
    body: { assigned_driver_id: "drv_1" },
  });
  assert.equal(assigned.ok, false);
  assert.equal(assigned.error, "assignment_availability_unknown");
});

test("decorateDriverForDispatch never keeps an expired heartbeat green", () => {
  const at = Date.parse("2026-09-14T12:00:00.000Z");
  const row = decorateDriverForDispatch(
    {
      driver_id: "drv_1",
      is_active: true,
      availability_status: "available",
      weekly_roster: rosterNineToFive(),
    },
    { last_seen_at: "2026-09-14T11:50:00.000Z" },
    at,
  );
  assert.equal(row.live_connected, false);
  assert.equal(row.presence_label, "scheduled_no_live");
});
