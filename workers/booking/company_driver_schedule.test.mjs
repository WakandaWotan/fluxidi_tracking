// Driver roster persist + ACL on the existing driver index.

import { test } from "node:test";
import assert from "node:assert/strict";

import {
  driverScheduleAccess,
  findDriverInIndex,
  matchCompanyDriverSchedulePath,
  normalizeDriverSchedule,
  readCompanyDriverSchedule,
  scheduleToWeeklyRoster,
  serveCompanyDriverScheduleHttp,
  weeklyRosterToSchedule,
  writeCompanyDriverSchedule,
} from "./modules/company_driver_schedule.mjs";

const SCOPE = { tenant_id: "TA", company_id: "CA" };

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
      const asJson = opts === "json" || (opts && opts.type === "json");
      return asJson ? JSON.parse(raw) : raw;
    },
    async put(key, val) {
      store.set(key, val);
    },
  };
}

function seedDrivers(kv, extras = {}) {
  kv.store.set(
    "tenant:TA:company:CA:drivers:index:v1",
    JSON.stringify({
      drivers: {
        drv_chris: {
          driver_id: "drv_chris",
          display_name: "Christophe",
          is_active: true,
          ...extras.chris,
        },
        drv_wotan: {
          driver_id: "drv_wotan",
          display_name: "Wotan",
          is_active: true,
          ...extras.wotan,
        },
      },
    }),
  );
}

function envWith(kv) {
  return { BOOKING_KV: kv };
}

test("rights follow the existing roles", () => {
  assert.deepEqual(
    driverScheduleAccess({ isCompanyAdmin: true, targetDriverId: "drv_other" }),
    { canRead: true, canWrite: true },
  );
  assert.deepEqual(
    driverScheduleAccess({ driverId: "drv_chris", targetDriverId: "drv_chris" }),
    { canRead: true, canWrite: false },
  );
  assert.deepEqual(
    driverScheduleAccess({ driverId: "drv_chris", targetDriverId: "drv_wotan" }),
    { canRead: false, canWrite: false },
  );
});

test("path matching stays exact", () => {
  assert.deepEqual(matchCompanyDriverSchedulePath("/company/drivers/drv_chris/schedule"), {
    driverId: "drv_chris",
  });
  assert.equal(matchCompanyDriverSchedulePath("/company/drivers/drv_chris/schedules"), null);
});

test("an empty saved roster still carries explicitly_set", () => {
  const normalized = normalizeDriverSchedule(
    { timezone: "Europe/Brussels", weekdays: {} },
    { driverId: "drv_chris" },
  );
  assert.equal(normalized.ok, true);
  assert.equal(normalized.schedule.explicitly_set, true);
  assert.deepEqual(normalized.schedule.weekdays, {});
  const roster = scheduleToWeeklyRoster(normalized.schedule);
  assert.equal(roster.explicitly_set, true);
});

test("weekdays convert to the existing weekly_roster days", () => {
  const normalized = normalizeDriverSchedule(
    {
      timezone: "Europe/Brussels",
      weekdays: {
        1: [{ start: "09:00", end: "17:00", breaks: [{ start: "12:00", end: "12:30" }] }],
      },
    },
    { driverId: "drv_chris" },
  );
  const roster = scheduleToWeeklyRoster(normalized.schedule);
  assert.equal(roster.days.mon[0].start, "09:00");
  assert.equal(roster.days.mon[0].breaks[0].end, "12:30");
  const back = weeklyRosterToSchedule(roster, "drv_chris");
  assert.equal(back.weekdays["1"][0].start, "09:00");
});

test("save and reopen stay on the driver index", async () => {
  const kv = memoryKV();
  seedDrivers(kv);
  const env = envWith(kv);
  const missing = await readCompanyDriverSchedule(env, SCOPE, "drv_chris");
  assert.equal(missing.present, false);
  const written = await writeCompanyDriverSchedule(env, SCOPE, "drv_chris", {
    timezone: "Europe/Brussels",
    weekdays: {
      1: [{ start: "18:00", end: "02:00" }],
    },
    exceptions: [{ date: "2026-09-21", kind: "leave" }],
  });
  assert.equal(written.ok, true);
  assert.equal(written.present, true);
  const reread = await readCompanyDriverSchedule(env, SCOPE, "drv_chris");
  assert.equal(reread.present, true);
  assert.equal(reread.schedule.weekdays["1"][0].start, "18:00");
  assert.equal(reread.schedule.explicitly_set, true);
  const index = JSON.parse(kv.store.get("tenant:TA:company:CA:drivers:index:v1"));
  const found = findDriverInIndex(index, "drv_chris");
  assert.equal(found.driver.weekly_roster.explicitly_set, true);
  assert.equal(found.driver.weekly_roster.days.mon[0].start, "18:00");
});

test("a consciously empty write is still present on reopen", async () => {
  const kv = memoryKV();
  seedDrivers(kv);
  const env = envWith(kv);
  const written = await writeCompanyDriverSchedule(env, SCOPE, "drv_chris", {
    timezone: "Europe/Brussels",
    weekdays: {},
  });
  assert.equal(written.ok, true);
  const reread = await readCompanyDriverSchedule(env, SCOPE, "drv_chris");
  assert.equal(reread.present, true);
  assert.equal(reread.schedule.explicitly_set, true);
  assert.deepEqual(reread.schedule.weekdays, {});
});

test("HTTP ACL: driver may read own roster and never write", async () => {
  const kv = memoryKV();
  seedDrivers(kv);
  const env = envWith(kv);
  await writeCompanyDriverSchedule(env, SCOPE, "drv_chris", {
    timezone: "Europe/Brussels",
    weekdays: { 1: [{ start: "09:00", end: "17:00" }] },
  });
  const ownRead = await serveCompanyDriverScheduleHttp({
    env,
    method: "GET",
    driverId: "drv_chris",
    scope: SCOPE,
    actor: { isCompanyAdmin: false, driverId: "drv_chris" },
  });
  assert.equal(ownRead.status, 200);
  const otherRead = await serveCompanyDriverScheduleHttp({
    env,
    method: "GET",
    driverId: "drv_wotan",
    scope: SCOPE,
    actor: { isCompanyAdmin: false, driverId: "drv_chris" },
  });
  assert.equal(otherRead.status, 403);
  const ownWrite = await serveCompanyDriverScheduleHttp({
    env,
    method: "PUT",
    driverId: "drv_chris",
    scope: SCOPE,
    body: { weekdays: {} },
    actor: { isCompanyAdmin: false, driverId: "drv_chris" },
  });
  assert.equal(ownWrite.status, 403);
});
