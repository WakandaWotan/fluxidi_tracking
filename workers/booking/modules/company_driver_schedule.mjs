/* Company driver roster (uurrooster) on the existing driver index.
 *
 * GET  /company/drivers/:driverId/schedule
 * PUT  /company/drivers/:driverId/schedule   (POST accepted too)
 *
 * Storage stays on the driver index (`weekly_roster` + `driver_schedule`).
 * A dedicated schedule key is not used: dispatch already reads weekly_roster
 * from that record, so save and assignment share one truth.
 *
 *   - never set  → fields absent → assignment does not refuse on hours
 *   - saved empty → explicitly_set: true, no blocks → not scheduled
 *   - admin of the company may read and write every driver
 *   - a driver session may only read their own roster
 */

import { sanitizeTenantString } from "./parsing_utils.js";
import { _companyDriverIndexKey } from "./driver_ops.js";
import {
  DEFAULT_DISPATCH_TIMEZONE,
  normalizeRosterExceptions,
  normalizeWeeklyRoster,
} from "./company_dispatch.mjs";

const MAX_BLOCKS_PER_DAY = 8;
const MAX_BREAKS_PER_BLOCK = 4;
const MAX_EXCEPTIONS = 180;
const WEEKDAY_KEYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];

function text(value, max = 80) {
  return String(value ?? "").trim().slice(0, max);
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, PUT, POST, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type, Authorization",
    },
  });
}

function minuteOfDay(value) {
  if (typeof value === "number" && Number.isFinite(value)) {
    const rounded = Math.trunc(value);
    return rounded >= 0 && rounded <= 2880 ? rounded : null;
  }
  const raw = text(value, 8);
  const colon = /^(\d{1,2}):(\d{2})$/.exec(raw);
  if (!colon) return null;
  const h = Number(colon[1]);
  const m = Number(colon[2]);
  if (h > 24 || m > 59) return null;
  return h * 60 + m;
}

function clock(minute) {
  const wrapped = ((minute % 1440) + 1440) % 1440;
  const hh = String(Math.floor(wrapped / 60)).padStart(2, "0");
  const mm = String(wrapped % 60).padStart(2, "0");
  return `${hh}:${mm}`;
}

export function matchCompanyDriverSchedulePath(pathname) {
  const match = String(pathname || "").match(
    /^\/company\/drivers\/([^/]+)\/schedule$/,
  );
  if (!match) return null;
  try {
    return { driverId: decodeURIComponent(match[1]) };
  } catch {
    return { driverId: match[1] };
  }
}

export function driverScheduleAccess({
  isCompanyAdmin = false,
  driverId = "",
  targetDriverId = "",
} = {}) {
  const self = text(driverId, 80);
  const target = text(targetDriverId, 80);
  if (isCompanyAdmin) return { canRead: true, canWrite: true };
  if (self && target && self === target) {
    return { canRead: true, canWrite: false };
  }
  return { canRead: false, canWrite: false };
}

function weekdayNumberToKey(weekday) {
  return WEEKDAY_KEYS[Number(weekday) - 1] || "";
}

function weekdayKeyToNumber(key) {
  const index = WEEKDAY_KEYS.indexOf(String(key || "").toLowerCase());
  return index >= 0 ? index + 1 : 0;
}

function stripInternal(block) {
  const { _startMinute, _endMinute, ...rest } = block;
  return rest;
}

function normalizeBlock(raw, where, errors) {
  const item = raw && typeof raw === "object" ? raw : {};
  const start = minuteOfDay(item.start);
  const end = minuteOfDay(item.end);
  if (start === null || end === null) {
    errors.push(`${where}_invalid_time`);
    return null;
  }
  const endMinute = end <= start ? end + 1440 : end;
  if (endMinute - start > 1440) {
    errors.push(`${where}_block_too_long`);
    return null;
  }
  const breaks = [];
  if (Array.isArray(item.breaks)) {
    if (item.breaks.length > MAX_BREAKS_PER_BLOCK) {
      errors.push(`${where}_too_many_breaks`);
      return null;
    }
    for (const rawBreak of item.breaks) {
      const slot = rawBreak && typeof rawBreak === "object" ? rawBreak : {};
      const bStart = minuteOfDay(slot.start);
      const bEnd = minuteOfDay(slot.end);
      if (bStart === null || bEnd === null) {
        errors.push(`${where}_invalid_break`);
        return null;
      }
      const normalizedStart = bStart < start ? bStart + 1440 : bStart;
      const normalizedEnd = bEnd <= bStart ? bEnd + 1440 : bEnd;
      if (normalizedStart < start || normalizedEnd > endMinute) {
        errors.push(`${where}_break_outside_block`);
        return null;
      }
      breaks.push({ start: clock(normalizedStart), end: clock(normalizedEnd) });
    }
  }
  return {
    start: clock(start),
    end: clock(endMinute),
    ...(breaks.length ? { breaks } : {}),
    _startMinute: start,
    _endMinute: endMinute,
  };
}

export function normalizeDriverSchedule(raw, { driverId, timezone } = {}) {
  const source = raw && typeof raw === "object" ? raw : {};
  const weekdaysIn =
    source.weekdays && typeof source.weekdays === "object"
      ? source.weekdays
      : {};
  const weekdays = {};
  const errors = [];

  for (let weekday = 1; weekday <= 7; weekday += 1) {
    const list = Array.isArray(weekdaysIn[String(weekday)])
      ? weekdaysIn[String(weekday)]
      : Array.isArray(weekdaysIn[weekday])
        ? weekdaysIn[weekday]
        : [];
    if (list.length > MAX_BLOCKS_PER_DAY) {
      errors.push(`weekday_${weekday}_too_many_blocks`);
      continue;
    }
    const blocks = [];
    for (const item of list) {
      const block = normalizeBlock(item, `weekday_${weekday}`, errors);
      if (block) blocks.push(block);
    }
    blocks.sort((a, b) => a._startMinute - b._startMinute);
    for (let i = 1; i < blocks.length; i += 1) {
      if (blocks[i]._startMinute < blocks[i - 1]._endMinute) {
        errors.push(`weekday_${weekday}_overlapping_blocks`);
        break;
      }
    }
    if (blocks.length > 0) {
      weekdays[String(weekday)] = blocks.map(stripInternal);
    }
  }

  const exceptionsIn = Array.isArray(source.exceptions) ? source.exceptions : [];
  if (exceptionsIn.length > MAX_EXCEPTIONS) errors.push("too_many_exceptions");
  const exceptions = [];
  for (const item of exceptionsIn.slice(0, MAX_EXCEPTIONS)) {
    const entry = item && typeof item === "object" ? item : {};
    const date = text(entry.date, 10);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
      errors.push("exception_invalid_date");
      continue;
    }
    const kind = text(entry.kind, 24).toLowerCase() || "absent";
    const blocks = [];
    if (Array.isArray(entry.blocks)) {
      for (const rawBlock of entry.blocks.slice(0, MAX_BLOCKS_PER_DAY)) {
        const block = normalizeBlock(rawBlock, `exception_${date}`, errors);
        if (block) blocks.push(stripInternal(block));
      }
    }
    exceptions.push({ date, kind, ...(blocks.length ? { blocks } : {}) });
  }

  return {
    ok: errors.length === 0,
    errors,
    schedule: {
      driver_id: text(driverId, 80),
      timezone:
        text(timezone || source.timezone, 64) || DEFAULT_DISPATCH_TIMEZONE,
      weekdays,
      exceptions,
      explicitly_set: true,
    },
  };
}

export function scheduleToWeeklyRoster(schedule) {
  const source = schedule && typeof schedule === "object" ? schedule : {};
  const weekdays =
    source.weekdays && typeof source.weekdays === "object"
      ? source.weekdays
      : {};
  const days = {};
  for (let weekday = 1; weekday <= 7; weekday += 1) {
    const key = weekdayNumberToKey(weekday);
    const rows = Array.isArray(weekdays[String(weekday)])
      ? weekdays[String(weekday)]
      : [];
    days[key] = rows.map((row) => ({
      start: row.start,
      end: row.end,
      ...(Array.isArray(row.breaks) && row.breaks.length
        ? { breaks: row.breaks }
        : {}),
    }));
  }
  return {
    timezone: text(source.timezone, 64) || DEFAULT_DISPATCH_TIMEZONE,
    explicitly_set: true,
    days,
  };
}

export function scheduleToRosterExceptions(schedule) {
  const exceptions = Array.isArray(schedule?.exceptions)
    ? schedule.exceptions
    : [];
  return exceptions.map((entry) => {
    const kind = text(entry.kind, 24).toLowerCase();
    if (kind === "custom_hours" || kind === "hours" || kind === "blocks") {
      return {
        date: text(entry.date, 10),
        type: "blocks",
        blocks: Array.isArray(entry.blocks) ? entry.blocks : [],
      };
    }
    return { date: text(entry.date, 10), type: "off", kind };
  });
}

export function weeklyRosterToSchedule(rosterRaw, driverId, exceptionsRaw = []) {
  const roster = normalizeWeeklyRoster(rosterRaw || {});
  const weekdays = {};
  for (const key of WEEKDAY_KEYS) {
    const weekday = weekdayKeyToNumber(key);
    const rows = Array.isArray(roster.days[key]) ? roster.days[key] : [];
    if (!weekday || !rows.length) continue;
    weekdays[String(weekday)] = rows.map((row) => ({
      start: row.start,
      end: row.end,
      ...(Array.isArray(row.breaks) && row.breaks.length
        ? { breaks: row.breaks }
        : {}),
    }));
  }
  const exceptions = normalizeRosterExceptions(exceptionsRaw).map((entry) => ({
    date: entry.date,
    kind: entry.type === "blocks" ? "custom_hours" : "absent",
    ...(entry.type === "blocks" && entry.blocks?.length
      ? { blocks: entry.blocks }
      : {}),
  }));
  return {
    driver_id: text(driverId, 80),
    timezone: roster.timezone,
    weekdays,
    exceptions,
    explicitly_set: true,
  };
}

function driverMap(index) {
  return index?.drivers && typeof index.drivers === "object" && !Array.isArray(index.drivers)
    ? index.drivers
    : {};
}

export function findDriverInIndex(index, driverId) {
  const id = sanitizeTenantString(driverId, 96);
  if (!id) return null;
  const drivers = driverMap(index);
  if (drivers[id] && typeof drivers[id] === "object") {
    return { key: id, driver: drivers[id] };
  }
  for (const [key, row] of Object.entries(drivers)) {
    if (!row || typeof row !== "object") continue;
    if (sanitizeTenantString(row.driver_id || row.driverId, 96) === id) {
      return { key, driver: row };
    }
  }
  return null;
}

function storedSchedulePresent(driver) {
  const stored = driver?.driver_schedule;
  if (stored && typeof stored === "object" && stored.explicitly_set === true) {
    return true;
  }
  const roster = driver?.weekly_roster ?? driver?.weeklyRoster;
  if (!roster || typeof roster !== "object") return false;
  if (roster.explicitly_set === true || roster.explicitlySet === true || roster.configured === true) {
    return true;
  }
  const normalized = normalizeWeeklyRoster(roster);
  return WEEKDAY_KEYS.some((key) => (normalized.days[key] || []).length > 0);
}

export async function readCompanyDriverSchedule(env, scope, driverId) {
  const tenantId = sanitizeTenantString(scope?.tenant_id ?? scope?.tenantId, 80);
  const companyId = sanitizeTenantString(scope?.company_id ?? scope?.companyId, 80);
  const id = sanitizeTenantString(driverId, 96);
  if (!tenantId || !companyId || !id) {
    return { ok: false, error: "invalid_scope" };
  }
  let index;
  try {
    index = await env.BOOKING_KV.get(
      _companyDriverIndexKey({ tenant_id: tenantId, company_id: companyId }),
      { type: "json" },
    );
  } catch {
    return { ok: false, error: "schedule_load_failed" };
  }
  const found = findDriverInIndex(index, id);
  if (!found) return { ok: false, error: "driver_not_found" };
  if (!storedSchedulePresent(found.driver)) {
    return {
      ok: true,
      present: false,
      schedule: null,
      driver_id: id,
    };
  }
  const stored = found.driver.driver_schedule;
  const schedule =
    stored && typeof stored === "object"
      ? {
          ...stored,
          driver_id: id,
          explicitly_set: true,
        }
      : weeklyRosterToSchedule(
          found.driver.weekly_roster ?? found.driver.weeklyRoster,
          id,
          found.driver.roster_exceptions ?? found.driver.rosterExceptions,
        );
  return { ok: true, present: true, schedule, driver_id: id };
}

export async function writeCompanyDriverSchedule(env, scope, driverId, raw) {
  const tenantId = sanitizeTenantString(scope?.tenant_id ?? scope?.tenantId, 80);
  const companyId = sanitizeTenantString(scope?.company_id ?? scope?.companyId, 80);
  const id = sanitizeTenantString(driverId, 96);
  if (!tenantId || !companyId || !id) {
    return { ok: false, error: "invalid_scope" };
  }
  const normalized = normalizeDriverSchedule(raw, { driverId: id });
  if (!normalized.ok) {
    return { ok: false, error: "invalid_schedule", errors: normalized.errors };
  }
  const key = _companyDriverIndexKey({ tenant_id: tenantId, company_id: companyId });
  let index;
  try {
    index = await env.BOOKING_KV.get(key, { type: "json" });
  } catch {
    return { ok: false, error: "schedule_load_failed" };
  }
  const found = findDriverInIndex(index, id);
  if (!found) return { ok: false, error: "driver_not_found" };
  const nowIso = new Date().toISOString();
  const schedule = {
    ...normalized.schedule,
    tenant_id: tenantId,
    company_id: companyId,
    driver_id: id,
    explicitly_set: true,
    updated_at: nowIso,
  };
  const weeklyRoster = scheduleToWeeklyRoster(schedule);
  const exceptions = scheduleToRosterExceptions(schedule);
  const drivers = { ...driverMap(index) };
  drivers[found.key] = {
    ...found.driver,
    driver_id: found.driver.driver_id || found.driver.driverId || id,
    weekly_roster: weeklyRoster,
    weeklyRoster,
    roster_exceptions: exceptions,
    rosterExceptions: exceptions,
    driver_schedule: schedule,
    weekly_roster_status: "ok",
    updated_at: nowIso,
  };
  try {
    await env.BOOKING_KV.put(
      key,
      JSON.stringify({
        ...(index && typeof index === "object" ? index : {}),
        drivers,
        updated_at: nowIso,
      }),
    );
  } catch {
    return { ok: false, error: "schedule_save_failed" };
  }
  return { ok: true, present: true, schedule, driver_id: id };
}

export async function serveCompanyDriverScheduleHttp({
  env,
  method,
  driverId,
  url,
  body,
  actor,
  scope,
} = {}) {
  const resolvedScope = {
    tenant_id:
      sanitizeTenantString(scope?.tenant_id ?? url?.searchParams?.get?.("tenant_id"), 80) ||
      sanitizeTenantString(body?.tenant_id, 80),
    company_id:
      sanitizeTenantString(scope?.company_id ?? url?.searchParams?.get?.("company_id"), 80) ||
      sanitizeTenantString(body?.company_id, 80),
  };
  const id = sanitizeTenantString(driverId, 96);
  const access = driverScheduleAccess({
    isCompanyAdmin: actor?.isCompanyAdmin === true,
    driverId: actor?.driverId || "",
    targetDriverId: id,
  });
  const verb = String(method || "GET").toUpperCase();
  if (verb === "GET") {
    if (!access.canRead) return json({ ok: false, error: "forbidden" }, 403);
    const read = await readCompanyDriverSchedule(env, resolvedScope, id);
    if (!read.ok) {
      const status = read.error === "driver_not_found" ? 404 : read.error === "schedule_load_failed" ? 503 : 400;
      return json(read, status);
    }
    return json(read, 200);
  }
  if (verb === "PUT" || verb === "POST" || verb === "PATCH") {
    if (!access.canWrite) return json({ ok: false, error: "forbidden" }, 403);
    const written = await writeCompanyDriverSchedule(env, resolvedScope, id, body || {});
    if (!written.ok) {
      const status =
        written.error === "driver_not_found"
          ? 404
          : written.error === "schedule_load_failed" || written.error === "schedule_save_failed"
            ? 503
            : 400;
      return json(written, status);
    }
    return json(written, 200);
  }
  return json({ ok: false, error: "method_not_allowed" }, 405);
}
