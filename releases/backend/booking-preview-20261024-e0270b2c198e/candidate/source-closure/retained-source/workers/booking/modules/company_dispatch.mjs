// COMPANY-DISPATCH-P0 — assignment eligibility, presence and roster.
// Request-time only. Targeted driver/presence keys. No KV.list, no per-driver cron.

import { safeStr, sanitizeTenantString } from "./parsing_utils.js";

export const DEFAULT_DISPATCH_TIMEZONE = "Europe/Brussels";
export const LIVE_HEARTBEAT_TTL_MS = 3 * 60 * 1000;
export const HEARTBEAT_WRITE_THROTTLE_MS = 45 * 1000;
export const ASSIGNMENT_SAFETY_MARGIN_MIN = 15;
export const DISPATCH_OPERATIONAL_BUFFER_MIN = 5;

export function resolveDispatchOperationalBufferMin(source) {
  const raw = Number(
    source && typeof source === "object"
      ? source.dispatch_operational_buffer_min
      : source,
  );
  if (Number.isFinite(raw) && raw >= 0 && raw <= 60) return raw;
  return DISPATCH_OPERATIONAL_BUFFER_MIN;
}
export const SOON_WINDOW_MIN = 30;
export const DRIVER_PAUSE_MAX_MS = 60 * 60 * 1000;
/** Processing delay for a Nu stamp. Not a substitute for a planned pickup that already elapsed. */
export const NOW_PICKUP_GRACE_MS = 2 * 60 * 1000;
export const PRESENCE_KEY_SUFFIX = ":driver_presence:v1";

export const AVAILABILITY = {
  OFFLINE: "OFFLINE",
  AVAILABLE: "AVAILABLE",
  ON_TRIP: "ON_TRIP",
  PAUSED: "PAUSED",
};

const WEEKDAYS = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"];
const WEEKDAY_KEYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];

const ON_TRIP_BOOKING_STATUSES = new Set([
  "STARTED",
  "IN_PROGRESS",
  "ON_TRIP",
  "PICKED_UP",
  "ARRIVED",
  "EN_ROUTE",
  "DRIVING",
]);

const AVAILABLE_AFTER_BOOKING_STATUSES = new Set([
  "COMPLETED",
  "CANCELLED",
  "CANCELED",
  "NO_SHOW",
  "REJECTED",
  "EXPIRED",
]);

export function companyDriverPresenceKey(scope) {
  const tenantId = sanitizeTenantString(scope?.tenant_id ?? scope?.tenantId, 80);
  const companyId = sanitizeTenantString(scope?.company_id ?? scope?.companyId, 80);
  return `tenant:${tenantId}:company:${companyId}${PRESENCE_KEY_SUFFIX}`;
}

export function companyFleetVehiclesKey(scope) {
  const tenantId = sanitizeTenantString(scope?.tenant_id ?? scope?.tenantId, 80);
  const companyId = sanitizeTenantString(scope?.company_id ?? scope?.companyId, 80);
  return `tenant:${tenantId}:company:${companyId}:fleet:vehicles:v1`;
}

export function normalizeDispatchAvailability(raw) {
  const token = sanitizeTenantString(raw, 40).toLowerCase();
  if (token === "paused" || token === "pause" || token === "unavailable" || token === "not_available") {
    return AVAILABILITY.PAUSED;
  }
  if (token === "offline") return AVAILABILITY.OFFLINE;
  if (
    token === "busy" ||
    token === "on_trip" ||
    token === "on-trip" ||
    token === "on_the_way" ||
    token === "waiting"
  ) {
    return AVAILABILITY.ON_TRIP;
  }
  if (token === "available" || token === "ready" || token === "online") {
    return AVAILABILITY.AVAILABLE;
  }
  return AVAILABILITY.AVAILABLE;
}

export function storedAvailabilityFromDispatch(status) {
  switch (normalizeDispatchAvailability(status)) {
    case AVAILABILITY.PAUSED:
      return "paused";
    case AVAILABILITY.OFFLINE:
      return "offline";
    case AVAILABILITY.ON_TRIP:
      return "busy";
    default:
      return "available";
  }
}

export function bookingStatusSetsOnTrip(status) {
  return ON_TRIP_BOOKING_STATUSES.has(sanitizeTenantString(status, 40).toUpperCase());
}

export function bookingStatusClearsOnTrip(status) {
  return AVAILABLE_AFTER_BOOKING_STATUSES.has(sanitizeTenantString(status, 40).toUpperCase());
}

function parseHm(raw) {
  const text = sanitizeTenantString(raw, 8);
  const match = text.match(/^(\d{1,2}):(\d{2})$/);
  if (!match) return null;
  const hour = Number(match[1]);
  const minute = Number(match[2]);
  if (!Number.isFinite(hour) || !Number.isFinite(minute) || hour > 23 || minute > 59) {
    return null;
  }
  return hour * 60 + minute;
}

function formatHm(minutes) {
  const wrapped = ((minutes % 1440) + 1440) % 1440;
  const hour = String(Math.floor(wrapped / 60)).padStart(2, "0");
  const minute = String(wrapped % 60).padStart(2, "0");
  return `${hour}:${minute}`;
}

// Formatters contain no company or roster state. Bound the cache even for
// arbitrary tenant timezone strings; every schedule is still evaluated anew.
const dispatchTimezoneFormatters = new Map();
function dispatchTimezoneFormatter(zone) {
  if (dispatchTimezoneFormatters.has(zone)) return dispatchTimezoneFormatters.get(zone);
  let formatter = null;
  try {
    formatter = new Intl.DateTimeFormat("en-GB", { timeZone: zone, weekday: "short", year: "numeric",
      month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit", hourCycle: "h23" });
  } catch { /* Unsupported zones still fail closed. */ }
  if (dispatchTimezoneFormatters.size >= 64) dispatchTimezoneFormatters.delete(dispatchTimezoneFormatters.keys().next().value);
  dispatchTimezoneFormatters.set(zone, formatter);
  return formatter;
}

export function dispatchTimezoneIsSupported(timeZone) {
  const zone = sanitizeTenantString(timeZone, 64) || DEFAULT_DISPATCH_TIMEZONE;
  try {
    return dispatchTimezoneFormatter(zone) !== null;
  } catch {
    return false;
  }
}

export function weeklyRosterHasConfiguredBlocks(raw) {
  if (raw == null || typeof raw !== "object" || Array.isArray(raw)) return false;
  const roster = normalizeWeeklyRoster(raw);
  return WEEKDAY_KEYS.some((key) => (roster.days[key] || []).length > 0);
}

export function weeklyRosterIsConfigured(raw, exceptionsRaw = []) {
  if (raw != null && typeof raw === "object" && !Array.isArray(raw)) {
    if (
      raw.explicitly_set === true ||
      raw.explicitlySet === true ||
      raw.configured === true
    ) {
      return true;
    }
  }
  if (weeklyRosterHasConfiguredBlocks(raw)) return true;
  return normalizeRosterExceptions(exceptionsRaw).length > 0;
}

export function driverRosterLoadFailed(driver) {
  if (!driver || typeof driver !== "object") return false;
  if (driver.weekly_roster_load_failed === true || driver.weeklyRosterLoadFailed === true) {
    return true;
  }
  const status = sanitizeTenantString(
    driver.weekly_roster_status || driver.weeklyRosterStatus || driver.roster_status,
    40,
  ).toLowerCase();
  return status === "load_failed" || status === "error" || status === "unavailable";
}

export function resolveScheduleState(rosterRaw, atMs, exceptionsRaw = []) {
  const configured = weeklyRosterIsConfigured(rosterRaw, exceptionsRaw);
  if (!configured) {
    return { configured: false, active: false, undeterminable: false };
  }
  const roster = normalizeWeeklyRoster(rosterRaw);
  if (!dispatchTimezoneIsSupported(roster.timezone)) {
    return {
      configured: true,
      active: false,
      undeterminable: true,
      error: "unsupported_timezone",
    };
  }
  try {
    return {
      configured: true,
      active: scheduledActiveAt(rosterRaw, atMs, exceptionsRaw) === true,
      undeterminable: false,
    };
  } catch {
    return {
      configured: true,
      active: false,
      undeterminable: true,
      error: "schedule_eval_failed",
    };
  }
}

export function zonedParts(atMs, timeZone = DEFAULT_DISPATCH_TIMEZONE) {
  const ms = Number(atMs);
  if (!Number.isFinite(ms)) return null;
  const zone = sanitizeTenantString(timeZone, 64) || DEFAULT_DISPATCH_TIMEZONE;
  if (!dispatchTimezoneIsSupported(zone)) return null;
  try {
    const parts = dispatchTimezoneFormatter(zone).formatToParts(new Date(ms));
    const get = (type) => parts.find((part) => part.type === type)?.value || "";
    const weekdayRaw = get("weekday").slice(0, 3).toLowerCase();
    const weekdayMap = {
      mon: "mon",
      tue: "tue",
      wed: "wed",
      thu: "thu",
      fri: "fri",
      sat: "sat",
      sun: "sun",
    };
    return {
      timeZone: zone,
      weekday: weekdayMap[weekdayRaw] || "mon",
      year: get("year"),
      month: get("month"),
      day: get("day"),
      date: `${get("year")}-${get("month")}-${get("day")}`,
      hour: Number(get("hour")),
      minute: Number(get("minute")),
      second: Number(get("second")),
      minutes: Number(get("hour")) * 60 + Number(get("minute")),
    };
  } catch {
    return null;
  }
}

export function normalizeRosterBlock(raw) {
  const start = parseHm(raw?.start ?? raw?.from ?? raw?.begin);
  const end = parseHm(raw?.end ?? raw?.to);
  if (start == null || end == null || start === end) return null;
  const breaks = [];
  if (Array.isArray(raw?.breaks)) {
    for (const slot of raw.breaks) {
      const bStart = parseHm(slot?.start ?? slot?.from);
      const bEnd = parseHm(slot?.end ?? slot?.to);
      if (bStart == null || bEnd == null || bStart === bEnd) continue;
      breaks.push({ start: formatHm(bStart), end: formatHm(bEnd) });
    }
  }
  return {
    start: formatHm(start),
    end: formatHm(end),
    overnight: start > end,
    ...(breaks.length ? { breaks } : {}),
  };
}

export function normalizeWeeklyRoster(raw) {
  const source = raw && typeof raw === "object" && !Array.isArray(raw) ? raw : {};
  const daysSource = source.days && typeof source.days === "object" ? source.days : source;
  const days = {};
  for (const key of WEEKDAY_KEYS) {
    const rows = Array.isArray(daysSource[key]) ? daysSource[key] : [];
    days[key] = rows.map(normalizeRosterBlock).filter(Boolean);
  }
  const explicitlySet =
    source.explicitly_set === true ||
    source.explicitlySet === true ||
    source.configured === true;
  return {
    timezone: sanitizeTenantString(source.timezone || source.time_zone, 64) || DEFAULT_DISPATCH_TIMEZONE,
    days,
    ...(explicitlySet ? { explicitly_set: true } : {}),
  };
}

export function normalizeRosterExceptions(raw) {
  if (!Array.isArray(raw)) return [];
  return raw
    .map((row) => {
      const date = sanitizeTenantString(row?.date || row?.day, 16);
      if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return null;
      const type = sanitizeTenantString(row?.type || row?.kind, 24).toLowerCase() || "off";
      if (type === "off" || type === "leave" || type === "absent") {
        return { date, type: "off" };
      }
      const blocks = Array.isArray(row?.blocks) ? row.blocks.map(normalizeRosterBlock).filter(Boolean) : [];
      return { date, type: "blocks", blocks };
    })
    .filter(Boolean);
}

export function copyRosterDay(roster, fromDay, toDays) {
  const normalized = normalizeWeeklyRoster(roster);
  const source = WEEKDAY_KEYS.includes(fromDay) ? fromDay : "";
  if (!source) return normalized;
  const blocks = normalized.days[source].map((block) => ({ ...block }));
  for (const day of Array.isArray(toDays) ? toDays : []) {
    if (!WEEKDAY_KEYS.includes(day) || day === source) continue;
    normalized.days[day] = blocks.map((block) => ({ ...block }));
  }
  return normalized;
}

function blocksForDate(roster, parts, exceptions) {
  const exception = (exceptions || []).find((row) => row.date === parts.date);
  if (exception?.type === "off") return [];
  if (exception?.type === "blocks") return exception.blocks;
  return roster.days[parts.weekday] || [];
}

function previousDateParts(parts) {
  const noonUtc = Date.parse(`${parts.date}T12:00:00.000Z`);
  const prev = zonedParts(noonUtc - 24 * 60 * 60 * 1000, parts.timeZone);
  return prev;
}

function blockContainsMinutes(block, minutes, { overnightTail = false } = {}) {
  const start = parseHm(block.start);
  const end = parseHm(block.end);
  if (start == null || end == null) return false;
  if (overnightTail) {
    return start > end && minutes < end;
  }
  if (start < end) return minutes >= start && minutes < end;
  return minutes >= start;
}

function breakContainsMinutes(block, minutes, { overnightTail = false } = {}) {
  const blockStart = parseHm(block.start);
  if (blockStart == null || !Array.isArray(block.breaks)) return false;
  for (const slot of block.breaks) {
    let start = parseHm(slot.start);
    let end = parseHm(slot.end);
    if (start == null || end == null) continue;
    if (start < blockStart) start += 1440;
    if (end <= start) end += 1440;
    const probe = overnightTail ? minutes + 1440 : minutes;
    if (probe >= start && probe < end) return true;
  }
  return false;
}

function dateIsAbsent(parts, exceptions) {
  return (exceptions || []).some((row) => row.date === parts?.date && row.type === "off");
}

export function scheduledSlotAt(rosterRaw, atMs, exceptionsRaw = []) {
  const roster = normalizeWeeklyRoster(rosterRaw);
  const parts = zonedParts(atMs, roster.timezone);
  if (!parts) {
    return { active: false, inBreak: false, absent: false, undeterminable: true };
  }
  const exceptions = normalizeRosterExceptions(exceptionsRaw);
  if (dateIsAbsent(parts, exceptions)) {
    return { active: false, inBreak: false, absent: true, undeterminable: false };
  }
  const today = blocksForDate(roster, parts, exceptions);
  for (const block of today) {
    if (!blockContainsMinutes(block, parts.minutes)) continue;
    if (breakContainsMinutes(block, parts.minutes)) {
      return { active: false, inBreak: true, absent: false, undeterminable: false };
    }
    return { active: true, inBreak: false, absent: false, undeterminable: false };
  }
  const prevParts = previousDateParts(parts);
  if (prevParts) {
    const yesterday = blocksForDate(roster, prevParts, exceptions);
    for (const block of yesterday) {
      if (!blockContainsMinutes(block, parts.minutes, { overnightTail: true })) continue;
      if (breakContainsMinutes(block, parts.minutes, { overnightTail: true })) {
        return { active: false, inBreak: true, absent: false, undeterminable: false };
      }
      return { active: true, inBreak: false, absent: false, undeterminable: false };
    }
  }
  return { active: false, inBreak: false, absent: false, undeterminable: false };
}

export function scheduledActiveAt(rosterRaw, atMs, exceptionsRaw = []) {
  return scheduledSlotAt(rosterRaw, atMs, exceptionsRaw).active === true;
}

export function scheduleConflictAt(rosterRaw, atMs, exceptionsRaw = []) {
  const configured = weeklyRosterIsConfigured(rosterRaw, exceptionsRaw);
  if (!configured) return "";
  const roster = normalizeWeeklyRoster(rosterRaw);
  if (!dispatchTimezoneIsSupported(roster.timezone)) {
    return "assignment_schedule_undeterminable";
  }
  let slot;
  try {
    slot = scheduledSlotAt(rosterRaw, atMs, exceptionsRaw);
  } catch {
    return "assignment_schedule_undeterminable";
  }
  if (slot.undeterminable) return "assignment_schedule_undeterminable";
  if (slot.inBreak) return "assignment_driver_planned_break";
  if (slot.absent) return "assignment_driver_absent";
  if (slot.active) return "";
  if (!weeklyRosterHasConfiguredBlocks(rosterRaw) && normalizeRosterExceptions(exceptionsRaw).length === 0) {
    return "assignment_driver_not_scheduled";
  }
  return "assignment_driver_outside_hours";
}

export function scheduleConflictForWindow(rosterRaw, pickupMs, durationMin, exceptionsRaw = [], manualOverrideRaw = null) {
  const startMs = Number(pickupMs);
  const duration = Number(durationMin);
  const override = normalizeManualOverride(manualOverrideRaw);
  const overrideUntil = Date.parse(override?.until || "");
  const conflictAt = (atMs) => {
    // Retain an explicitly active override only until its resolved expiry.
    if (override?.kind === "active" && Number.isFinite(overrideUntil) && atMs < overrideUntil) return "";
    return scheduleConflictAt(rosterRaw, atMs, exceptionsRaw);
  };
  const startConflict = conflictAt(startMs);
  if (startConflict) return startConflict;
  // Legacy callers without a duration retain their instant-only contract.
  // Actual proposed occupancy still requires a known positive duration upstream.
  if (durationMin == null) return "";
  const endMs = startMs + duration * 60000;
  if (!Number.isFinite(startMs) || !Number.isFinite(duration) || duration <= 0 ||
      !Number.isFinite(endMs) || endMs <= startMs || duration > 8 * 24 * 60) {
    return "assignment_schedule_undeterminable";
  }
  const classify = (conflict) => {
    if (conflict === "assignment_driver_planned_break" || conflict === "assignment_schedule_undeterminable") return conflict;
    return conflict ? "assignment_ride_after_hours" : "";
  };
  // HH:mm roster blocks/exceptions change on minute boundaries, not every 15m.
  // Probe every boundary, including a short pause and DST transitions. The
  // occupied interval is [pickup,end): an exact shift-end arrival is allowed.
  for (let t = Math.floor(startMs / 60000) * 60000 + 60000; t < endMs; t += 60000) {
    const conflict = classify(conflictAt(t));
    if (conflict) return conflict;
  }
  // An override can expire at an arbitrary second between minute boundaries.
  if (Number.isFinite(overrideUntil) && overrideUntil > startMs && overrideUntil < endMs) {
    const conflict = classify(conflictAt(overrideUntil));
    if (conflict) return conflict;
  }
  return classify(conflictAt(Math.max(startMs, endMs - 1)));
}
function addMinutesInZone(atMs, minutes, timeZone) {
  return Number(atMs) + minutes * 60000;
}

export function nextShiftBoundaryMs(rosterRaw, atMs, exceptionsRaw = []) {
  const roster = normalizeWeeklyRoster(rosterRaw);
  const startActive = scheduledActiveAt(roster, atMs, exceptionsRaw);
  for (let step = 15; step <= 8 * 24 * 60; step += 15) {
    const probe = addMinutesInZone(atMs, step, roster.timezone);
    if (scheduledActiveAt(roster, probe, exceptionsRaw) !== startActive) {
      return probe;
    }
  }
  return addMinutesInZone(atMs, 8 * 24 * 60, roster.timezone);
}

export function normalizeManualOverride(raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  const kind = sanitizeTenantString(raw.kind || raw.type || raw.status, 24).toLowerCase();
  if (kind !== "active" && kind !== "inactive" && kind !== "paused") return null;
  const untilMs = Date.parse(String(raw.until || raw.until_iso || raw.untilIso || ""));
  return {
    kind,
    until: Number.isFinite(untilMs) ? new Date(untilMs).toISOString() : "",
    set_at: safeStr(raw.set_at || raw.setAt, 80),
  };
}

export function resolveManualOverride(overrideRaw, { atMs, roster, exceptions } = {}) {
  const override = normalizeManualOverride(overrideRaw);
  if (!override) return { active: false, kind: "", until: "" };
  const untilMs = Date.parse(override.until);
  if (Number.isFinite(untilMs) && untilMs <= Number(atMs)) {
    return { active: false, kind: "", until: override.until, expired: true };
  }
  if (!Number.isFinite(untilMs) && roster) {
    override.until = new Date(nextShiftBoundaryMs(roster, atMs, exceptions)).toISOString();
  }
  return { active: true, kind: override.kind, until: override.until };
}

export function effectiveWorkState({
  driver,
  atMs,
  roster,
  exceptions,
  override,
  scheduleCache,
} = {}) {
  const isActive = driver?.is_active !== false && driver?.isActive !== false;
  const blocked = driver?.blocked === true || driver?.is_blocked === true;
  const rosterRaw = roster || driver?.weekly_roster || driver?.weeklyRoster;
  const exceptionsRaw = exceptions || driver?.roster_exceptions || driver?.rosterExceptions;
  const loadFailed = driverRosterLoadFailed(driver);
  const schedule = loadFailed
    ? {
        configured: true,
        active: false,
        undeterminable: true,
        error: "roster_load_failed",
      }
    : scheduleCache ? scheduleCache.resolve(rosterRaw, atMs, exceptionsRaw,
      () => resolveScheduleState(rosterRaw, atMs, exceptionsRaw)) : resolveScheduleState(rosterRaw, atMs, exceptionsRaw);
  const scheduled = schedule.active === true;
  const manual = resolveManualOverride(override || driver?.manual_override, {
    atMs,
    roster: rosterRaw,
    exceptions: exceptionsRaw,
  });
  // No stored roster keeps the agreed pre-roster behaviour: the schedule does
  // not refuse. A configured roster still gates working hours. A failed load
  // is never treated as "no roster".
  let working = schedule.undeterminable ? false : schedule.configured ? scheduled : true;
  if (manual.active && manual.kind === "inactive") working = false;
  if (manual.active && manual.kind === "active") working = true;
  return {
    account_active: isActive,
    blocked,
    scheduled_active: scheduled,
    roster_configured: schedule.configured === true,
    schedule_undeterminable: schedule.undeterminable === true,
    manual_override: manual,
    working: isActive && !blocked && working,
  };
}

export function isLiveConnected(presence, atMs, ttlMs = LIVE_HEARTBEAT_TTL_MS) {
  const seen = Date.parse(String(presence?.last_seen_at || presence?.lastSeenAt || ""));
  if (!Number.isFinite(seen)) return false;
  const age = Number(atMs) - seen;
  return Number.isFinite(age) && age >= -120_000 && age <= ttlMs;
}

export function companyDriverPresenceLabel({
  work,
  availability,
  live,
} = {}) {
  const status = normalizeDispatchAvailability(availability);
  if (!work?.account_active || work?.blocked) return "offline_work";
  if (status === AVAILABILITY.ON_TRIP) return "on_trip";
  if (status === AVAILABILITY.PAUSED || work?.manual_override?.kind === "paused") return "paused";
  if (!work?.working) return "offline_work";
  if (!live && work.scheduled_active) return "scheduled_no_live";
  if (!live) return "connection_lost";
  if (status === AVAILABILITY.AVAILABLE) return "available";
  if (status === AVAILABILITY.OFFLINE) return "connection_lost";
  return "connection_lost";
}

export function expandWindowsWithSafetyMargin(windows, marginMin = ASSIGNMENT_SAFETY_MARGIN_MIN) {
  const extra = Math.max(0, Number(marginMin) || 0) * 60000;
  return (Array.isArray(windows) ? windows : [])
    .filter((window) => window && Number.isFinite(window.start) && Number.isFinite(window.end))
    .map((window) => ({
      ...window,
      start: window.start - extra,
      end: window.end + extra,
    }));
}

export function rideIsSoon(pickupIso, atMs, soonWindowMin = SOON_WINDOW_MIN) {
  const start = Date.parse(String(pickupIso || ""));
  if (!Number.isFinite(start)) return true;
  const now = Number(atMs);
  // A Nu stamp that is a few seconds old is still "soon". A planned pickup
  // that already elapsed beyond the grace window is not.
  if (start < now - NOW_PICKUP_GRACE_MS) return false;
  return start <= now + soonWindowMin * 60000;
}

export function linkedVehicleIds(driver) {
  const ids = [];
  const push = (value) => {
    const id = sanitizeTenantString(value, 128);
    if (id && !ids.includes(id)) ids.push(id);
  };
  push(driver?.assigned_vehicle_id || driver?.assignedVehicleId);
  const list = driver?.vehicle_ids || driver?.vehicleIds || driver?.linked_vehicle_ids;
  if (Array.isArray(list)) {
    for (const row of list) push(row);
  }
  return ids;
}

export function vehiclesLinkedToDriver(driver, vehicles) {
  const linked = new Set(linkedVehicleIds(driver));
  const driverId = sanitizeTenantString(driver?.driver_id || driver?.driverId, 96);
  return (Array.isArray(vehicles) ? vehicles : []).filter((vehicle) => {
    const id = sanitizeTenantString(vehicle?.vehicle_id || vehicle?.vehicleId || vehicle?.id, 128);
    if (!id) return false;
    if (linked.has(id)) return true;
    const owner = sanitizeTenantString(
      vehicle?.assigned_driver_id || vehicle?.assignedDriverId || vehicle?.driver_id,
      96,
    );
    return owner && owner === driverId;
  });
}

function vehicleIsActive(vehicle) {
  if (vehicle?.is_active === false || vehicle?.isActive === false || vehicle?.active === false) {
    return false;
  }
  return true;
}

export function readDriverPause(driver) {
  const pausedAt = Date.parse(String(driver?.paused_at || driver?.pausedAt || ""));
  const pausedUntil = Date.parse(String(driver?.paused_until || driver?.pausedUntil || ""));
  if (!Number.isFinite(pausedAt) || !Number.isFinite(pausedUntil) || pausedUntil <= pausedAt) {
    return null;
  }
  return {
    pausedAt,
    pausedUntil: Math.min(pausedUntil, pausedAt + DRIVER_PAUSE_MAX_MS),
  };
}

export function pauseBlocksInstant(driver, atMs) {
  const pause = readDriverPause(driver);
  const at = Number(atMs);
  if (!pause || !Number.isFinite(at)) return false;
  return at < pause.pausedUntil;
}

export function resolveDriverPauseFields({ existing, desiredStatus, nowMs } = {}) {
  const desired = String(desiredStatus || "").trim().toLowerCase();
  const now = Number(nowMs);
  const start = Number.isFinite(now) ? now : Date.now();
  if (desired !== "paused") {
    return { paused_at: "", paused_until: "", kept_existing: false };
  }
  const current = readDriverPause(existing);
  if (current && start < current.pausedUntil) {
    return {
      paused_at: new Date(current.pausedAt).toISOString(),
      paused_until: new Date(current.pausedUntil).toISOString(),
      kept_existing: true,
    };
  }
  return {
    paused_at: new Date(start).toISOString(),
    paused_until: new Date(start + DRIVER_PAUSE_MAX_MS).toISOString(),
    kept_existing: false,
  };
}

export function evaluateDriverEligibility({
  driver,
  presence,
  vehicles,
  drivers,
  atMs,
  pickupIso,
  durationMin,
  soon,
  overlap,
  scheduleCache,
  observeDecision,
  evaluationStage,
} = {}) {
  const reasons = [];
  const pickupMs = Date.parse(String(pickupIso || "")) || Number(atMs);
  const work = effectiveWorkState({ driver, atMs: pickupMs, scheduleCache });
  const nowWork = effectiveWorkState({ driver, atMs, scheduleCache });
  let availability = normalizeDispatchAvailability(driver?.availability_status ?? driver?.availabilityStatus);
  if (availability === AVAILABILITY.PAUSED && !pauseBlocksInstant(driver, pickupMs)) {
    availability = AVAILABILITY.AVAILABLE;
  }
  const live = isLiveConnected(presence, atMs);
  const soonRide = soon ?? rideIsSoon(pickupIso, atMs);
  if (!work.account_active) reasons.push("assignment_driver_inactive");
  if (work.blocked) reasons.push("assignment_driver_blocked");
  if (work.schedule_undeterminable) {
    reasons.push("assignment_schedule_undeterminable");
  } else if (!work.working) {
    if (work.manual_override?.kind === "inactive") {
      reasons.push("assignment_driver_not_scheduled");
    } else if (work.roster_configured) {
      const conflict = scheduleConflictForWindow(
        driver?.weekly_roster || driver?.weeklyRoster,
        pickupMs,
        durationMin,
        driver?.roster_exceptions || driver?.rosterExceptions,
      );
      reasons.push(conflict || "assignment_driver_not_scheduled");
    }
  } else if (work.roster_configured) {
    // A valid departure alone does not prove that the complete ride is covered.
    const conflict = scheduleConflictForWindow(
      driver?.weekly_roster || driver?.weeklyRoster,
      pickupMs,
      durationMin,
      driver?.roster_exceptions || driver?.rosterExceptions,
      work.manual_override,
    );
    if (conflict) reasons.push(conflict);
  }
  if (pauseBlocksInstant(driver, pickupMs)) reasons.push("assignment_driver_paused");
  if (availability === AVAILABILITY.ON_TRIP && soonRide) reasons.push("assignment_driver_on_trip");
  if (soonRide && availability !== AVAILABILITY.AVAILABLE && availability !== AVAILABILITY.ON_TRIP) {
    if (availability === AVAILABILITY.OFFLINE) reasons.push("assignment_driver_offline");
  }
  if (soonRide && availability !== AVAILABILITY.AVAILABLE) {
    if (availability !== AVAILABILITY.ON_TRIP) {
      // already recorded
    }
  }
  if (soonRide && availability !== AVAILABILITY.AVAILABLE) {
    if (!reasons.includes("assignment_driver_paused") &&
        !reasons.includes("assignment_driver_on_trip") &&
        !reasons.includes("assignment_driver_offline") &&
        availability !== AVAILABILITY.AVAILABLE) {
      reasons.push("assignment_driver_offline");
    }
  }
  if (soonRide && !live) reasons.push("assignment_driver_not_live");
  const linked = vehiclesLinkedToDriver(driver, vehicles).filter(vehicleIsActive);
  if(observeDecision)try{observeDecision({candidate_id:vehicles?.[0]?.vehicle_id??vehicles?.[0]?.vehicleId??vehicles?.[0]?.id,
    driver_id:driver?.driver_id??driver?.driverId??driver?.id,phase:'active_vehicle_link',
    reason:linked.length?'driver_active_vehicle_ready':'assignment_driver_no_vehicle',
    linked_vehicle_ids:linked.map(v=>v.vehicle_id??v.vehicleId??v.id),evaluation_stage:evaluationStage,
    ...(linked.length?{}:{producer:'no_active_vehicle'})});}catch{}
  if (!linked.length) reasons.push("assignment_driver_no_vehicle");
  if (overlap?.ok === false && overlap.error === "assignment_overlap") {
    reasons.push("assignment_overlap");
  }
  if (overlap?.ok === false && overlap.error === "assignment_availability_unknown") {
    reasons.push("assignment_availability_unknown");
  }
  if (overlap?.ok === false && overlap.error === "active_ride_end_unknown") {
    reasons.push("assignment_availability_unknown");
  }
  const unique = [...new Set(reasons)];
  return {
    ok: unique.length === 0,
    error: unique[0] || "",
    reasons: unique,
    soon: soonRide,
    live,
    work,
    availability,
    now_working: nowWork.working,
    linked_vehicle_ids: linked.map((vehicle) =>
      sanitizeTenantString(vehicle.vehicle_id || vehicle.vehicleId || vehicle.id, 128),
    ),
    label: companyDriverPresenceLabel({
      work: nowWork,
      availability,
      live,
    }),
  };
}

export function evaluateVehicleEligibility({
  vehicle,
  drivers,
  driver,
  atMs,
  overlap,
} = {}) {
  if (!vehicle || !sanitizeTenantString(vehicle.vehicle_id || vehicle.vehicleId || vehicle.id, 128)) {
    return { ok: false, error: "assignment_vehicle_unavailable" };
  }
  if (!vehicleIsActive(vehicle)) {
    return { ok: false, error: "assignment_vehicle_unavailable" };
  }
  if (overlap?.ok === false && overlap.error === "assignment_overlap") {
    return { ok: false, error: "assignment_vehicle_overlap" };
  }
  if (overlap?.ok === false && overlap.error === "assignment_availability_unknown") {
    return { ok: false, error: "assignment_availability_unknown" };
  }
  if (overlap?.ok === false && overlap.error === "active_ride_end_unknown") {
    return { ok: false, error: "assignment_availability_unknown" };
  }
  return { ok: true, error: "" };
}

export function resolveAutoVehicle({
  driver,
  vehicles,
  drivers,
  atMs,
  requestedVehicleId,
  overlapByVehicle,
} = {}) {
  const linked = vehiclesLinkedToDriver(driver, vehicles).filter(vehicleIsActive);
  const suitable = linked.filter((vehicle) => {
    const check = evaluateVehicleEligibility({
      vehicle,
      drivers,
      driver,
      atMs,
      overlap: overlapByVehicle?.[sanitizeTenantString(vehicle.vehicle_id || vehicle.vehicleId || vehicle.id, 128)],
    });
    return check.ok;
  });
  const requested = sanitizeTenantString(requestedVehicleId, 128);
  if (requested) {
    const match = suitable.find((vehicle) =>
      sanitizeTenantString(vehicle.vehicle_id || vehicle.vehicleId || vehicle.id, 128) === requested,
    );
    if (!match) {
      const raw = linked.find((vehicle) =>
        sanitizeTenantString(vehicle.vehicle_id || vehicle.vehicleId || vehicle.id, 128) === requested,
      );
      if (!raw) return { ok: false, error: "assignment_vehicle_unavailable", vehicleId: "", choices: suitable };
      return {
        ok: false,
        error: evaluateVehicleEligibility({ vehicle: raw, drivers, driver, atMs }).error ||
          "assignment_vehicle_unavailable",
        vehicleId: "",
        choices: suitable,
      };
    }
    return { ok: true, vehicleId: requested, auto: false, choices: suitable };
  }
  if (suitable.length === 1) {
    const id = sanitizeTenantString(
      suitable[0].vehicle_id || suitable[0].vehicleId || suitable[0].id,
      128,
    );
    return { ok: true, vehicleId: id, auto: true, choices: suitable };
  }
  if (suitable.length > 1) {
    return { ok: false, error: "assignment_vehicle_choice_required", vehicleId: "", choices: suitable };
  }
  return { ok: false, error: "assignment_vehicle_unavailable", vehicleId: "", choices: [] };
}

export function publicAssignmentChoice(driver, evaluation) {
  return {
    driver_id: sanitizeTenantString(driver?.driver_id || driver?.driverId, 96),
    display_name: safeStr(driver?.display_name || driver?.displayName, 160),
    eligible: evaluation?.ok === true,
    reasons: evaluation?.reasons || [],
    error: evaluation?.error || "",
    live: evaluation?.live === true,
    scheduled_active: evaluation?.work?.scheduled_active === true,
    availability: evaluation?.availability || "",
    presence_label: evaluation?.label || "",
    linked_vehicle_ids: evaluation?.linked_vehicle_ids || [],
  };
}

export function mergePresenceHeartbeat(existing, driverId, nowMs) {
  const id = sanitizeTenantString(driverId, 96);
  const nowIso = new Date(nowMs).toISOString();
  const drivers = existing?.drivers && typeof existing.drivers === "object" ? { ...existing.drivers } : {};
  const prev = drivers[id] && typeof drivers[id] === "object" ? drivers[id] : {};
  const lastSeen = Date.parse(String(prev.last_seen_at || prev.lastSeenAt || ""));
  if (Number.isFinite(lastSeen) && nowMs <= lastSeen) {
    return { changed: false, record: existing };
  }
  const lastWrite = Date.parse(String(prev.last_write_at || prev.lastWriteAt || ""));
  if (Number.isFinite(lastWrite) && nowMs - lastWrite < HEARTBEAT_WRITE_THROTTLE_MS) {
    return { changed: false, record: existing || { drivers, updated_at: nowIso } };
  }
  drivers[id] = {
    ...prev,
    last_seen_at: nowIso,
    last_write_at: nowIso,
    source: "heartbeat",
  };
  return {
    changed: true,
    record: {
      ...existing,
      drivers,
      updated_at: nowIso,
    },
  };
}

export async function loadDispatchFleet(env, scope) {
  const tenantId = sanitizeTenantString(scope?.tenant_id ?? scope?.tenantId, 80);
  const companyId = sanitizeTenantString(scope?.company_id ?? scope?.companyId, 80);
  const scoped = { tenant_id: tenantId, company_id: companyId };
  try {
    const { readCompanyDriverIndex, readCompanyDriverPresence } = await import("./driver_index_mutation.mjs");
    const [indexRaw, presenceRaw, vehiclesRaw] = await Promise.all([
      readCompanyDriverIndex(env, scoped),
      readCompanyDriverPresence(env, scoped),
      env?.BOOKING_KV?.get(companyFleetVehiclesKey(scoped), { type: "json" }),
    ]);
    const driversMap = indexRaw?.drivers && typeof indexRaw.drivers === "object" ? indexRaw.drivers : {};
    const drivers = Object.values(driversMap).filter((row) => row && typeof row === "object");
    const presenceMap = presenceRaw?.drivers && typeof presenceRaw.drivers === "object" ? presenceRaw.drivers : {};
    const vehicles = Array.isArray(vehiclesRaw)
      ? vehiclesRaw
      : Array.isArray(vehiclesRaw?.vehicles)
        ? vehiclesRaw.vehicles
        : [];
    return { drivers, presenceMap, vehicles, indexRaw, presenceRaw, load_failed: false };
  } catch (error) {
    return {
      drivers: [],
      presenceMap: {},
      vehicles: [],
      indexRaw: null,
      presenceRaw: null,
      load_failed: true,
      load_error: String(error?.message || error || "fleet_load_failed"),
    };
  }
}

export function driverFromFleet(fleet, driverId) {
  const id = sanitizeTenantString(driverId, 96);
  if (!id) return null;
  return (fleet?.drivers || []).find((row) =>
    sanitizeTenantString(row?.driver_id || row?.driverId, 96) === id,
  ) || null;
}

export function vehicleFromFleet(fleet, vehicleId) {
  const id = sanitizeTenantString(vehicleId, 128);
  if (!id) return null;
  return (fleet?.vehicles || []).find((row) =>
    sanitizeTenantString(row?.vehicle_id || row?.vehicleId || row?.id, 128) === id,
  ) || null;
}

export async function persistDriverPresence(env, scope, driverId, nowMs = Date.now()) {
  const { commitCompanyPresenceHeartbeat } = await import('./driver_index_mutation.mjs');
  return commitCompanyPresenceHeartbeat(env, scope, driverId, nowMs);
}

export function decorateDriverForDispatch(driver, presence, atMs) {
  const work = effectiveWorkState({ driver, atMs });
  const availability = normalizeDispatchAvailability(driver?.availability_status ?? driver?.availabilityStatus);
  const live = isLiveConnected(presence, atMs);
  return {
    ...driver,
    scheduled_active: work.scheduled_active,
    working: work.working,
    live_connected: live,
    last_seen_at: presence?.last_seen_at || "",
    availability_status: storedAvailabilityFromDispatch(availability),
    presence_label: companyDriverPresenceLabel({ work, availability, live }),
    weekly_roster: driver?.weekly_roster || driver?.weeklyRoster || null,
    roster_exceptions: driver?.roster_exceptions || driver?.rosterExceptions || [],
    manual_override: driver?.manual_override || driver?.manualOverride || null,
  };
}

export async function syncDriverAvailabilityForBookingStatus(env, {
  scope,
  driverId,
  status,
  bookingId,
  operationalLeg,
} = {}) {
  const id = sanitizeTenantString(driverId, 96);
  if (!id || !env?.BOOKING_KV) return { ok: true, changed: false };
  const onTrip = bookingStatusSetsOnTrip(status);
  const clear = bookingStatusClearsOnTrip(status);
  if (!onTrip && !clear) return { ok: true, changed: false };
  // Replayed START/status requests cannot reoccupy a canonically closed trip.
  // At company mutation boundaries BOOKING_KV is the local authority facade;
  // reading here avoids a driver-queue -> company-queue dependency cycle.
  if (onTrip && env.BOOKING_RECORD_AUTHORITY_ENABLED === '1') {
    try {
      const rec = await env.BOOKING_KV.get(`booking:${bookingId}`, { type: 'json' });
      if (!rec || (rec.tenant_id || rec.booking?.tenant_id) !== scope?.tenant_id
        || (rec.company_id || rec.booking?.company_id) !== scope?.company_id) {
        return { ok: false, changed: false, error: 'dispatch_booking_scope_unverified' };
      }
      const legs = rec.operational_legs || rec.operationalLegs || rec.booking?.operational_legs || rec.booking?.operationalLegs || [];
      const leg = operationalLeg && legs.find(row => (row.leg_id || row.legId) === operationalLeg);
      if ([rec, rec.booking, leg, leg?.booking].filter(Boolean).some(row =>
        [row.status, row.stage, row.lifecycle_status, row.lifecycleStatus].some(bookingStatusClearsOnTrip))) {
        return { ok: true, changed: false, terminal_activity_ignored: true };
      }
    } catch { return { ok: false, changed: false, error: 'dispatch_booking_read_failed' }; }
  }
  const { commitDriverIndexMutation } = await import("./driver_index_mutation.mjs");
  const result = await commitDriverIndexMutation(env, scope, {
    op: "sync_dispatch_availability",
    driver_id: id,
    availability_status: onTrip ? "busy" : "available",
    booking_id: sanitizeTenantString(bookingId, 200),
    operational_leg: sanitizeTenantString(operationalLeg, 200),
    now_iso: new Date().toISOString(),
  });
  if (!result?.ok) return { ok: false, changed: false, error: result?.error || "driver_index_commit_failed" };
  return {
    ok: true,
    changed: result.changed === true,
    availability_status: result.availability_status || (onTrip ? "busy" : "available"),
  };
}

export function defaultManualOverride(kind, atMs, roster, exceptions) {
  const until = nextShiftBoundaryMs(roster, atMs, exceptions);
  return {
    kind,
    until: new Date(until).toISOString(),
    set_at: new Date(atMs).toISOString(),
  };
}
