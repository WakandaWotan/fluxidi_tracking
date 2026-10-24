import { driverManagementPage, prepareDriverManagementIndex } from './driver_management_page.mjs';
import { readBoundedJson, writeBoundedJson, deleteBoundedJson } from './bounded_json_storage.mjs';
import { verifyBookingCutoverRequest } from './booking_cutover_maintenance.mjs';
import { presenceOperation } from './company_presence_authority.mjs';
import { readStagingFrozenDriverStateV1 } from './staging_frozen_driver_state_v1.mjs';
import { bookingWritersPaused, bookingWriterPauseResponse, deferPausedBookingAlarm } from './booking_writer_pause.mjs';
// Authoritative company driver-index mutation.
//
// Workers KV has no compare-and-swap. Several routes used to read the whole
// drivers:index:v1 document and write it back. Two isolates could both read
// the same snapshot, both return HTTP 200, and the slower put dropped the
// other change (vehicle, roster, profile, or login hash).
//
// Every writer now sends a small patch. The patch is applied to the freshest
// stored document inside one queue per tenant+company:
//   - production: DriverIndexCoordinatorDO (single-threaded per company);
//   - tests without that binding: an in-process queue for the same key.
// The DO saves a scope-bound pending generation before publishing to KV.
// Alarm recovery and the next read/patch finish that exact generation first.
// Readers use the same queue and copy; stale KV cannot roll it backwards.
// HTTP success follows publication, durable completion and pending cleanup.

import { sha256Hex } from "./crypto_utils.js";
import { sanitizeTenantString } from "./parsing_utils.js";
import {
  _companyDriverIndexKey,
  _generateDriverLoginSalt,
  _normalizeDriverAvailabilityStatus,
  _normalizeDriverEmployeeNumber,
  _normalizeDriverLoginCode,
} from "./driver_ops.js";
import { checkSharedVehicleRoster } from "./driver_vehicle_schedule_guard.mjs";
import {
  defaultManualOverride,
  normalizeManualOverride,
  normalizeRosterExceptions,
  normalizeWeeklyRoster,
  resolveDriverPauseFields,
  linkedVehicleIds,
} from "./company_dispatch.mjs";
import { findDriverInIndex } from "./company_driver_schedule.mjs";

export const DRIVER_INDEX_COORDINATOR_BINDING = "DRIVER_INDEX_COORDINATOR";
const STORAGE_KEY = "drivers-index-v1";
const PENDING_KEY = "driver-index-pending-v1";
const SCOPE_KEY = "driver-index-scope-v1";
const RECOVERY_MS = 60_000;

function coerceBoolean(value, fallback = true) {
  if (value == null) return fallback;
  if (typeof value === "boolean") return value;
  const text = sanitizeTenantString(value, 16).toLowerCase();
  if (!text) return fallback;
  if (text === "false" || text === "0" || text === "no") return false;
  if (text === "true" || text === "1" || text === "yes") return true;
  return fallback;
}

function agendaColor(entry) {
  const raw = String(entry?.agenda_color ?? entry?.agendaColor ?? "").trim();
  if (/^#?[0-9a-fA-F]{3,8}$/.test(raw)) {
    return raw.startsWith("#") ? raw : `#${raw}`;
  }
  return "";
}

function generationOf(record) {
  const value = Number(record?.driver_index_generation);
  return Number.isFinite(value) && value > 0 ? Math.floor(value) : 0;
}

function deletedMapOf(record) {
  const primary = record?.deleted_drivers;
  const alias = record?.deletedDrivers;
  const source = primary && typeof primary === "object" && !Array.isArray(primary)
    ? primary
    : (alias && typeof alias === "object" && !Array.isArray(alias) ? alias : {});
  return { ...source };
}

function driversOf(record) {
  const drivers = record?.drivers;
  if (!drivers || typeof drivers !== "object" || Array.isArray(drivers)) return {};
  return { ...drivers };
}

export function normalizeDriverIndexRecord(raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    return {
      drivers: {},
      deleted_drivers: {},
      deletedDrivers: {},
      driver_index_generation: 0,
    };
  }
  const deleted = deletedMapOf(raw);
  return {
    ...raw,
    drivers: driversOf(raw),
    deleted_drivers: deleted,
    deletedDrivers: { ...deleted },
    driver_index_generation: generationOf(raw),
  };
}

function vehicleIdOf(driver) {
  return sanitizeTenantString(driver?.assigned_vehicle_id ?? driver?.assignedVehicleId, 96);
}

function cloneJson(value) {
  return JSON.parse(JSON.stringify(value));
}

function failure(status, error, extra = {}) {
  return { ok: false, changed: false, status, error, ...extra };
}

function unchanged(record, extra = {}) {
  return { ok: true, changed: false, status: 200, record, ...extra };
}

function changed(record, extra = {}) {
  return { ok: true, changed: true, status: 200, record, ...extra };
}

function withDriver(record, key, driver, nowIso) {
  const drivers = driversOf(record);
  drivers[key] = driver;
  const deleted = deletedMapOf(record);
  return {
    ...record,
    drivers,
    deleted_drivers: deleted,
    deletedDrivers: { ...deleted },
    updated_at: nowIso,
  };
}

async function applyAssignVehicle(record, mutation) {
  const driverId = sanitizeTenantString(mutation?.driver_id, 96);
  const vehicleId = sanitizeTenantString(mutation?.vehicle_id, 96);
  const expectedVehicleId = sanitizeTenantString(mutation?.expected_vehicle_id, 96);
  const nowIso = sanitizeTenantString(mutation?.now_iso, 40) || new Date().toISOString();
  const drivers = driversOf(record);
  const deleted = deletedMapOf(record);
  const current = drivers[driverId];
  if (!driverId || !current || typeof current !== "object" ||
      Object.prototype.hasOwnProperty.call(deleted, driverId)) {
    return failure(404, "driver_not_found");
  }
  const currentVehicleId = vehicleIdOf(current);
  if (currentVehicleId !== expectedVehicleId) {
    return failure(409, "assignment_changed");
  }
  if (currentVehicleId === vehicleId) {
    return unchanged(record, { assigned_vehicle_id: currentVehicleId });
  }
  const others = Object.entries(drivers)
    .filter(([id, entry]) => id !== driverId && vehicleIdOf(entry) === vehicleId &&
      !Object.prototype.hasOwnProperty.call(deleted, id))
    .map(([, entry]) => entry);
  const rosterCheck = mutation.vehicle_duty_assignment === true
    ? { ok: true } : checkSharedVehicleRoster(current, others);
  if (!rosterCheck.ok) return failure(409, rosterCheck.reason || "roster_overlap");
  const next = {
    ...current,
    assigned_vehicle_id: vehicleId,
    assignedVehicleId: vehicleId,
    vehicle_ids: [vehicleId],
    updated_at: nowIso,
  };
  return changed(withDriver(record, driverId, next, nowIso), {
    driver_id: driverId,
    assigned_vehicle_id: vehicleId,
  });
}

async function applyUpsert(record, mutation) {
  const driverId = sanitizeTenantString(mutation?.driver_id, 96);
  const nowIso = sanitizeTenantString(mutation?.now_iso, 40) || new Date().toISOString();
  if (!driverId) return failure(400, "invalid_driver_id");
  const deleted = deletedMapOf(record);
  const tombstoned = Object.prototype.hasOwnProperty.call(deleted, driverId);
  if (tombstoned && mutation?.restore !== true) {
    return failure(409, "driver_deleted_conflict");
  }
  const drivers = driversOf(record);
  const existing = drivers[driverId] && typeof drivers[driverId] === "object"
    ? drivers[driverId]
    : {};
  const isNew = !Object.prototype.hasOwnProperty.call(drivers, driverId);
  const loginCodeInput = _normalizeDriverEmployeeNumber(mutation?.login_code_input);
  const employeeNumberInput = _normalizeDriverEmployeeNumber(mutation?.employee_number_input);
  const resolvedLoginCode = _normalizeDriverEmployeeNumber(
    loginCodeInput || existing.driver_code || existing.driverCode ||
      existing.login_code || existing.loginCode || employeeNumberInput,
  );
  const resolvedEmployeeNumber = _normalizeDriverEmployeeNumber(
    employeeNumberInput || resolvedLoginCode || existing.employee_number || existing.employeeNumber,
  );
  const existingHash = sanitizeTenantString(
    existing.driver_code_hash ?? existing.driverCodeHash, 200,
  ).toLowerCase();
  const existingSalt = sanitizeTenantString(
    existing.driver_code_salt ?? existing.driverCodeSalt, 120,
  );
  let nextHash = existingHash;
  let nextSalt = existingSalt;
  if (resolvedLoginCode && (loginCodeInput || !existingHash || !existingSalt)) {
    nextSalt = _generateDriverLoginSalt();
    nextHash = (await sha256Hex(
      `${nextSalt}:${_normalizeDriverLoginCode(resolvedLoginCode)}`,
    )).toLowerCase();
  }
  const roster = mutation?.has_weekly_roster === true
    ? normalizeWeeklyRoster(mutation.weekly_roster)
    : (existing.weekly_roster ?? existing.weeklyRoster ?? null);
  const exceptions = mutation?.has_roster_exceptions === true
    ? normalizeRosterExceptions(mutation.roster_exceptions)
    : (existing.roster_exceptions ?? existing.rosterExceptions ?? []);
  let manual = mutation?.has_manual_override === true
    ? normalizeManualOverride(mutation.manual_override)
    : (existing.manual_override ?? existing.manualOverride ?? null);
  const nowMs = Date.parse(nowIso);
  if (mutation?.manual_active === true) {
    manual = defaultManualOverride("active", Number.isFinite(nowMs) ? nowMs : Date.now(), roster, exceptions);
  }
  if (mutation?.manual_inactive === true) {
    manual = defaultManualOverride("inactive", Number.isFinite(nowMs) ? nowMs : Date.now(), roster, exceptions);
  }
  if (mutation?.clear_manual_override === true) manual = null;
  const availability = _normalizeDriverAvailabilityStatus(
    mutation?.has_availability_input === true
      ? mutation.availability_status
      : (existing.availability_status ?? existing.availabilityStatus ?? existing.driver_status),
    "available",
  );
  const pause = mutation?.has_availability_input === true
    ? resolveDriverPauseFields({
      existing,
      desiredStatus: availability,
      nowMs: Number.isFinite(nowMs) ? nowMs : Date.now(),
    })
    : {
      paused_at: existing.paused_at || existing.pausedAt || "",
      paused_until: existing.paused_until || existing.pausedUntil || "",
      kept_existing: true,
    };
  const photoInput = sanitizeTenantString(mutation?.driver_photo_url, 500);
  const assignedVehicleId = isNew
    ? sanitizeTenantString(mutation?.assigned_vehicle_id_input, 96)
    : vehicleIdOf(existing);
  const vehicleIds = isNew
    ? (Array.isArray(mutation?.vehicle_ids_input)
      ? mutation.vehicle_ids_input.map((id) => sanitizeTenantString(id, 128)).filter(Boolean)
      : [])
    : (Array.isArray(existing.vehicle_ids) ? existing.vehicle_ids : []);
  const next = {
    ...existing,
    driver_id: driverId,
    display_name: sanitizeTenantString(mutation?.display_name, 160),
    employee_number: resolvedEmployeeNumber,
    employeeNumber: resolvedEmployeeNumber,
    driver_code: resolvedLoginCode,
    login_code: resolvedLoginCode,
    driver_code_hash: nextHash,
    driver_code_salt: nextSalt,
    phone: sanitizeTenantString(mutation?.phone, 40),
    is_active: coerceBoolean(mutation?.is_active, true),
    availability_status: availability,
    availabilityStatus: availability,
    driver_status: availability,
    paused_at: pause.paused_at,
    pausedAt: pause.paused_at,
    paused_until: pause.paused_until,
    pausedUntil: pause.paused_until,
    assigned_vehicle_id: assignedVehicleId,
    vehicle_ids: vehicleIds,
    weekly_roster: roster,
    weeklyRoster: roster,
    roster_exceptions: exceptions,
    rosterExceptions: exceptions,
    manual_override: manual,
    manualOverride: manual,
    agenda_color: mutation?.has_agenda_color === true
      ? agendaColor({ agenda_color: mutation.agenda_color })
      : agendaColor(existing),
    taxi_driver_card_number: sanitizeTenantString(
      mutation?.taxi_driver_card_number || existing.taxi_driver_card_number || existing.taxiDriverCardNumber,
      120,
    ),
    taxi_driver_card_expiry: sanitizeTenantString(
      mutation?.taxi_driver_card_expiry || existing.taxi_driver_card_expiry || existing.taxiDriverCardExpiry,
      80,
    ),
    public_bio: sanitizeTenantString(
      mutation?.has_public_bio === true ? mutation.public_bio : existing.public_bio ?? existing.publicBio,
      2000,
    ),
    public_display_name: sanitizeTenantString(
      mutation?.public_display_name || existing.public_display_name || existing.publicDisplayName,
      160,
    ),
    private_chauffeur_enabled: mutation?.has_private_chauffeur_enabled === true
      ? coerceBoolean(mutation.private_chauffeur_enabled, false)
      : coerceBoolean(existing.private_chauffeur_enabled ?? existing.privateChauffeurEnabled, false),
    public_profile_enabled: mutation?.has_public_profile_enabled === true
      ? coerceBoolean(mutation.public_profile_enabled, false)
      : coerceBoolean(existing.public_profile_enabled ?? existing.publicProfileEnabled, false),
    public_photo_enabled: mutation?.has_public_photo_enabled === true
      ? coerceBoolean(mutation.public_photo_enabled, false)
      : coerceBoolean(existing.public_photo_enabled ?? existing.publicPhotoEnabled, false),
    updated_at: nowIso,
  };
  if (photoInput) {
    next.driver_photo_url = photoInput;
    next.driverPhotoUrl = photoInput;
    next.public_portrait_url = photoInput;
    next.publicPortraitUrl = photoInput;
  }
  next.agendaColor = next.agenda_color;
  next.taxiDriverCardNumber = next.taxi_driver_card_number;
  next.taxiDriverCardExpiry = next.taxi_driver_card_expiry;
  next.publicBio = next.public_bio;
  next.publicDisplayName = next.public_display_name;
  next.publicProfileEnabled = next.public_profile_enabled;
  next.privateChauffeurEnabled = next.private_chauffeur_enabled;
  next.publicPhotoEnabled = next.public_photo_enabled;
  if (mutation?.restore === true) delete deleted[driverId];
  const nextRecord = {
    ...record,
    drivers: { ...drivers, [driverId]: next },
    deleted_drivers: deleted,
    deletedDrivers: { ...deleted },
    updated_at: nowIso,
  };
  return changed(nextRecord, {
    driver_id: driverId,
    is_active: next.is_active,
    availability_status: availability,
  });
}

function applyDelete(record, mutation) {
  const driverId = sanitizeTenantString(mutation?.driver_id, 96);
  const nowIso = sanitizeTenantString(mutation?.now_iso, 40) || new Date().toISOString();
  if (!driverId) return failure(400, "invalid_driver_id");
  const drivers = driversOf(record);
  const deleted = deletedMapOf(record);
  const removed = Object.prototype.hasOwnProperty.call(drivers, driverId);
  if (removed) delete drivers[driverId];
  deleted[driverId] = nowIso;
  return changed({
    ...record,
    drivers,
    deleted_drivers: deleted,
    deletedDrivers: { ...deleted },
    updated_at: nowIso,
  }, { driver_id: driverId, deleted: removed });
}

function applyRotateLogin(record, mutation) {
  const driverId = sanitizeTenantString(mutation?.driver_id, 96);
  const nowIso = sanitizeTenantString(mutation?.now_iso, 40) || new Date().toISOString();
  const drivers = driversOf(record);
  const existing = drivers[driverId];
  if (!driverId || !existing || typeof existing !== "object") {
    return failure(404, "driver_not_found");
  }
  const nextHash = sanitizeTenantString(mutation?.driver_code_hash, 200).toLowerCase();
  const nextSalt = sanitizeTenantString(mutation?.driver_code_salt, 120);
  const last4 = sanitizeTenantString(mutation?.driver_code_last4, 8);
  if (!nextHash || !nextSalt) return failure(500, "driver_login_code_generation_failed");
  const next = {
    ...existing,
    driver_id: driverId,
    driverId,
    driver_code: "",
    driverCode: "",
    login_code: "",
    loginCode: "",
    employee_number: "",
    employeeNumber: "",
    driver_code_hash: nextHash,
    driverCodeHash: nextHash,
    driver_code_salt: nextSalt,
    driverCodeSalt: nextSalt,
    has_login_code: true,
    hasLoginCode: true,
    driver_code_last4: last4,
    driverCodeLast4: last4,
    login_code_last4: last4,
    loginCodeLast4: last4,
    rotated_at: nowIso,
    rotatedAt: nowIso,
    login_code_rotated_at: nowIso,
    loginCodeRotatedAt: nowIso,
    updated_at: nowIso,
    updatedAt: nowIso,
  };
  return changed(withDriver(record, driverId, next, nowIso), { driver_id: driverId });
}

function applyAvailability(record, mutation) {
  const driverId = sanitizeTenantString(mutation?.driver_id, 96);
  const nowIso = sanitizeTenantString(mutation?.now_iso, 40) || new Date().toISOString();
  const drivers = driversOf(record);
  const existing = drivers[driverId];
  if (!driverId || !existing || typeof existing !== "object") {
    return failure(404, "driver_not_found");
  }
  const desired = _normalizeDriverAvailabilityStatus(mutation?.availability_status, "available");
  const isActive = coerceBoolean(existing.is_active ?? existing.isActive, true);
  if (!isActive && desired === "available") return failure(409, "driver_inactive");
  const nowMs = Date.parse(nowIso);
  const pause = resolveDriverPauseFields({
    existing,
    desiredStatus: desired,
    nowMs: Number.isFinite(nowMs) ? nowMs : Date.now(),
  });
  const next = {
    ...existing,
    driver_id: driverId,
    is_active: isActive,
    availability_status: desired,
    availabilityStatus: desired,
    driver_status: desired,
    paused_at: pause.paused_at,
    pausedAt: pause.paused_at,
    paused_until: pause.paused_until,
    pausedUntil: pause.paused_until,
    updated_at: nowIso,
  };
  return changed(withDriver(record, driverId, next, nowIso), {
    driver_id: driverId,
    availability_status: desired,
    is_active: isActive,
    paused_at: pause.paused_at,
    paused_until: pause.paused_until,
    pause_kept_existing: pause.kept_existing === true,
  });
}

function applySchedule(record, mutation) {
  const driverId = sanitizeTenantString(mutation?.driver_id, 96);
  const nowIso = sanitizeTenantString(mutation?.now_iso, 40) || new Date().toISOString();
  const found = findDriverInIndex(record, driverId);
  if (!found) return failure(404, "driver_not_found");
  const schedule = mutation?.schedule && typeof mutation.schedule === "object"
    ? { ...mutation.schedule, driver_id: driverId, explicitly_set: true, updated_at: nowIso }
    : null;
  if (!schedule) return failure(400, "invalid_schedule");
  const roster = mutation?.weekly_roster ?? null;
  const exceptions = Array.isArray(mutation?.roster_exceptions) ? mutation.roster_exceptions : [];
  const next = {
    ...found.driver,
    driver_id: found.driver.driver_id || found.driver.driverId || driverId,
    weekly_roster: roster,
    weeklyRoster: roster,
    roster_exceptions: exceptions,
    rosterExceptions: exceptions,
    driver_schedule: schedule,
    weekly_roster_status: "ok",
    updated_at: nowIso,
  };
  return changed(withDriver(record, found.key, next, nowIso), {
    driver_id: driverId,
    schedule,
  });
}

function applyDispatchAvailability(record, mutation) {
  const driverId = sanitizeTenantString(mutation?.driver_id, 96);
  const nowIso = sanitizeTenantString(mutation?.now_iso, 40) || new Date().toISOString();
  const desired = sanitizeTenantString(mutation?.availability_status, 40).toLowerCase();
  if (!driverId || (desired !== "busy" && desired !== "available")) {
    return unchanged(record);
  }
  const drivers = driversOf(record);
  const existing = drivers[driverId];
  if (!existing || typeof existing !== "object") return unchanged(record);
  const current = sanitizeTenantString(
    existing.availability_status ?? existing.availabilityStatus, 40,
  ).toLowerCase();
  const bookingId = sanitizeTenantString(mutation?.booking_id, 200);
  const leg = sanitizeTenantString(mutation?.operational_leg, 200);
  const activity = existing.dispatch_activity;
  // A reviewed repair is conditional on the exact dispatch owner read before
  // the patch. A newer START or a manual pause/offline change wins this race.
  if (mutation.expected_activity && (current !== (mutation.expected_availability_status || 'busy')
    || activity?.booking_id !== mutation.expected_activity.booking_id
    || (activity?.operational_leg || '') !== (mutation.expected_activity.operational_leg || ''))) {
    return unchanged(record, { availability_status: current, activity_retained: true });
  }
  // This comparison is inside the driver-index queue. A late STOP/no-show for
  // ride 1 must not clear a newer ride 2, including on a different return leg.
  if (desired === 'available' && activity?.booking_id
    && (activity.booking_id !== bookingId || leg && activity.operational_leg !== leg)) {
    return unchanged(record, { availability_status: current, activity_retained: true });
  }
  if (desired === 'available' && ['paused', 'offline'].includes(current)) {
    // Terminal publication removes only its own activity, retaining manual duty.
    if (!activity || activity.booking_id !== bookingId) return unchanged(record, { availability_status: current });
    return changed(withDriver(record, driverId, { ...existing, dispatch_activity: null, updated_at: nowIso }, nowIso),
      { availability_status: current });
  }
  const nextActivity = desired === 'busy' && bookingId
    ? { booking_id: bookingId, operational_leg: leg } : desired === 'available' ? null : activity || null;
  if (current === desired && JSON.stringify(activity || null) === JSON.stringify(nextActivity)) {
    return unchanged(record, { availability_status: desired });
  }
  const next = {
    ...existing,
    availability_status: desired,
    availabilityStatus: desired,
    driver_status: desired,
    dispatch_activity: nextActivity,
    updated_at: nowIso,
  };
  return changed(withDriver(record, driverId, next, nowIso), { availability_status: desired });
}

function applyVehicleDutyAvailability(record, mutation) {
  const driverId = sanitizeTenantString(mutation?.driver_id, 96);
  const driver = driversOf(record)[driverId];
  if (!driver) return failure(404, 'driver_not_found');
  const projection = mutation.projection;
  if (!projection || projection.driver_id !== driverId
    || !Number.isSafeInteger(projection.version) || projection.version < 1
    || !['start', 'pause', 'resume', 'end'].includes(projection.action)
    || !projection.duty_id || !projection.vehicle_id
    || !Number.isSafeInteger(projection.at_ms) || projection.at_ms < 0
    || !Number.isFinite(new Date(projection.at_ms).getTime())) return failure(400, 'duty_projection_invalid');
  const previous = driver.operating_duty;
  if (previous?.version > projection.version) return failure(409, 'duty_projection_stale');
  if (previous?.version === projection.version) return JSON.stringify(previous) === JSON.stringify(projection)
    ? unchanged(record, { replay: true }) : failure(409, 'duty_projection_conflict');
  if (!coerceBoolean(driver.is_active ?? driver.isActive, true) && projection.action !== 'end') return failure(409, 'driver_inactive');
  if (driver.dispatch_activity?.booking_id) return failure(409, 'active_ride_blocks_duty_change');
  const desired = projection.action === 'end' ? 'offline' : projection.action === 'pause' ? 'paused' : 'available';
  const nowIso = new Date(projection.at_ms).toISOString();
  return changed(withDriver(record, driverId, { ...driver, operating_duty: projection,
    availability_status: desired, availabilityStatus: desired, driver_status: desired,
    paused_at: desired === 'paused' ? nowIso : null, pausedAt: desired === 'paused' ? nowIso : null,
    paused_until: null, pausedUntil: null, updated_at: nowIso }, nowIso), { availability_status: desired });
}

export async function applyDriverIndexMutation(record, mutation) {
  const op = sanitizeTenantString(mutation?.op, 40);
  if (op === "assign_vehicle") return applyAssignVehicle(record, mutation);
  if (op === "upsert_driver") return applyUpsert(record, mutation);
  if (op === "delete_driver") return applyDelete(record, mutation);
  if (op === "rotate_login") return applyRotateLogin(record, mutation);
  if (op === "set_availability") return applyAvailability(record, mutation);
  if (op === "write_schedule") return applySchedule(record, mutation);
  if (op === "sync_dispatch_availability") return applyDispatchAvailability(record, mutation);
  if (op === 'sync_vehicle_duty') return applyVehicleDutyAvailability(record, mutation);
  return failure(400, "unknown_driver_index_mutation");
}

async function readKvRecord(kv, key) {
  const raw = await kv.get(key, { type: "json" });
  if (raw == null) return null;
  if (typeof raw !== "object" || Array.isArray(raw)) throw Error('driver_index_load_failed');
  return normalizeDriverIndexRecord(raw);
}

function normalizedScope(scope) {
  const tenant_id = sanitizeTenantString(scope?.tenant_id ?? scope?.tenantId, 80);
  const company_id = sanitizeTenantString(scope?.company_id ?? scope?.companyId, 80);
  if (!tenant_id || !company_id) throw Error('invalid_tenant_or_company_scope');
  return { tenant_id, company_id };
}
function sameScope(a, b) { return a?.tenant_id === b.tenant_id && a?.company_id === b.company_id; }
async function bindScope(storage, scope) {
  if (!storage) return;
  // Native SQLite synchronous reads use the exact same durable keyspace.
  // This does not cache scope, skip recovery or change the serialized queue.
  const bound = typeof storage.kv?.get === 'function' ? storage.kv.get(SCOPE_KEY) : await storage.get(SCOPE_KEY);
  if (bound && !sameScope(bound, scope)) throw Error('driver_index_scope_conflict');
  if (!bound) await storage.put(SCOPE_KEY, scope);
}
async function armRecovery(storage) {
  if (typeof storage?.setAlarm !== 'function' || typeof storage?.delete !== 'function') {
    throw Error('driver_index_recovery_contract_unavailable');
  }
  await storage.setAlarm(Date.now() + RECOVERY_MS);
}
async function completeProjection(env, scope, storage, pending) {
  if (!sameScope(pending.scope, scope) || !pending.record?.drivers
    || !Number.isSafeInteger(pending.record.driver_index_generation) || pending.record.driver_index_generation < 1) {
    throw Error('driver_index_pending_invalid');
  }
  // A durable intent precedes KV. Never acknowledge or accept the next patch
  // until the exact generation has been published and stored as completed.
  await env.BOOKING_KV.put(_companyDriverIndexKey(scope), JSON.stringify(pending.record));
  await writeBoundedJson(storage, STORAGE_KEY, pending.record);
  await deleteBoundedJson(storage, PENDING_KEY);
  if (storage.deleteAlarm) await storage.deleteAlarm();
}
async function recoverProjection(env, scope, storage) {
  if (!storage) return;
  const pending = await readBoundedJson(storage, PENDING_KEY);
  if (!pending) return;
  await armRecovery(storage);
  await completeProjection(env, scope, storage, pending);
}

async function loadAuthoritative(kv, key, storage) {
  const kvRecord = await readKvRecord(kv, key);
  let stored = null;
  if (storage?.get) {
    const raw = await readBoundedJson(storage, STORAGE_KEY);
    if (raw && typeof raw === "object" && !Array.isArray(raw)) {
      stored = normalizeDriverIndexRecord(raw);
    }
  }
  const kvGen = generationOf(kvRecord);
  const storedGen = generationOf(stored);
  if (stored && storedGen >= kvGen) return stored;
  if (kvRecord) return kvRecord;
  return normalizeDriverIndexRecord(null);
}

function quotaError(err) {
  const text = sanitizeTenantString(err?.message ?? err, 180).toLowerCase();
  if (text.includes("kv put() limit exceeded") || text.includes("limit exceeded for the day")) {
    return "kv_quota_exceeded";
  }
  return "";
}

export async function applyAndPersistDriverIndex(env, scope, mutation, storage = null) {
  scope = normalizedScope(scope);
  const key = _companyDriverIndexKey(scope);
  await bindScope(storage, scope);
  try { await recoverProjection(env, scope, storage); }
  catch { return failure(503, 'driver_index_recovery_pending'); }
  let current;
  try { current = await loadAuthoritative(env.BOOKING_KV, key, storage); }
  catch { return failure(503, 'driver_index_load_failed'); }
  const applied = await applyDriverIndexMutation(current, mutation);
  if (!applied.ok || applied.changed !== true) {
    return { ...applied, key };
  }
  const next = {
    ...applied.record,
    driver_index_generation: generationOf(current) + 1,
  };
  const payload = JSON.stringify(next);
  if (storage) {
    try {
      // Schedule before writing: a process termination between either write
      // and publication must leave recovery work that wakes after restart.
      await armRecovery(storage);
      await writeBoundedJson(storage, PENDING_KEY, { scope, record: next });
    } catch { return failure(503, 'driver_index_authority_persist_failed'); }
    try { await completeProjection(env, scope, storage, { scope, record: next }); }
    catch (err) {
      const quota = quotaError(err);
      return failure(quota ? 429 : 503, quota || 'driver_index_recovery_pending');
    }
    return { ...applied, record: next, key, status: 200 };
  }
  try {
    await env.BOOKING_KV.put(key, payload);
  } catch (err) {
    const quota = quotaError(err);
    if (quota) return failure(429, quota);
    return failure(500, "driver_index_save_failed");
  }
  return { ...applied, record: next, key, status: 200 };
}

const localQueues = new Map();

function enqueueLocal(key, run) {
  const previous = localQueues.get(key) || Promise.resolve();
  const execution = previous.then(run, run);
  localQueues.set(key, execution.then(() => undefined, () => undefined));
  return execution;
}

export function hasDriverIndexCoordinator(env) {
  const binding = env?.[DRIVER_INDEX_COORDINATOR_BINDING];
  return !!(binding?.idFromName && binding?.get);
}

function stagingFrozenReadRequested(env) {
  return env?.STAGING_TRIAL_MODE === '1' || env?.STAGING_TRIAL_ENVIRONMENT === 'staging'
    || String(env?.ENVIRONMENT ?? '').trim().toLowerCase() === 'staging';
}

async function readStagingFrozenCoordinatorState(env,scope) {
  if (env?.STAGING_TRIAL_MODE !== '1' || env?.STAGING_TRIAL_ENVIRONMENT !== 'staging'
    || !hasDriverIndexCoordinator(env)) throw Error('staging_frozen_coordinator_required');
  const result=await callDriverIndexCoordinator(env,scope,undefined,'read_frozen_availability');
  if (!result?.ok || !result.index || !result.presence)
    throw Error(result?.error || 'staging_frozen_state_unavailable');
  return result;
}

export function driverIndexCoordinatorName(scope) {
  const tenantId = sanitizeTenantString(scope?.tenant_id ?? scope?.tenantId, 80);
  const companyId = sanitizeTenantString(scope?.company_id ?? scope?.companyId, 80);
  if (!tenantId || !companyId) return "";
  return `${tenantId}\n${companyId}`;
}

async function callDriverIndexCoordinator(env, scope, mutation, action = 'mutate') {
  const binding = env[DRIVER_INDEX_COORDINATOR_BINDING];
  const name = driverIndexCoordinatorName(scope);
  if (!name) return failure(400, "invalid_tenant_or_company_scope");
  const stub = binding.get(binding.idFromName(name));
  stub.env = env;
  let response;
  try { response = await stub.fetch(new Request("https://do/driver-index", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ action, scope, mutation }),
  })); } catch { return failure(503, 'driver_index_coordinator_failed'); }
  const body = await response.json().catch(() => null);
  if (!body || typeof body !== "object") {
    return failure(response.status || 503, "driver_index_coordinator_failed");
  }
  if (body.status == null) body.status = response.status;
  return body;
}

export async function readCompanyDriverIndex(env, scope) {
  const scoped = normalizedScope(scope);
  if (stagingFrozenReadRequested(env))
    return (await readStagingFrozenCoordinatorState(env,scoped)).index;
  if (hasDriverIndexCoordinator(env)) {
    const result = await callDriverIndexCoordinator(env, scoped, undefined, 'read');
    if (!result?.ok || !result.record) throw Error(result?.error || 'driver_index_coordinator_failed');
    return result.record;
  }
  return normalizeDriverIndexRecord(await readKvRecord(env.BOOKING_KV, _companyDriverIndexKey(scoped)));
}

// Internal hot-index contract. The coordinator rebuilds this derived index
// from its authoritative record after restart/recovery and every valid patch.
export async function readCompanyDriverSubset(env, scope, { driver_ids = [], vehicle_ids = [] } = {}) {
  if (!hasDriverIndexCoordinator(env)) return readCompanyDriverIndex(env, scope);
  const result = await callDriverIndexCoordinator(env, normalizedScope(scope), { driver_ids, vehicle_ids }, 'read_subset');
  if (result?.error === 'unknown_action') return readCompanyDriverIndex(env, scope);
  if (!result?.ok || !result.record) throw Error(result?.error || 'driver_index_coordinator_failed');
  return result.record;
}

export async function readCompanyDriverPage(env, scope, options = {}) {
 if (hasDriverIndexCoordinator(env)) return callDriverIndexCoordinator(env, normalizedScope(scope), options, 'read_page');
 const record=await readCompanyDriverIndex(env,scope);
 const presence=options.online!=null&&options.online!==''?await readCompanyDriverPresence(env,scope):{};
 return driverManagementPage(record, normalizedScope(scope), options, presence);
}

export async function readCompanyDriverPresence(env, scope, driverIds) {
  const scoped = normalizedScope(scope);
  if (stagingFrozenReadRequested(env)) {
    const presence=(await readStagingFrozenCoordinatorState(env,scoped)).presence;
    return driverIds ? {...presence,drivers:Object.fromEntries(driverIds
      .filter(id=>typeof id==='string'&&Object.hasOwn(presence.drivers,id))
      .map(id=>[id,presence.drivers[id]]))} : presence;
  }
  if (!hasDriverIndexCoordinator(env)) {
    // Read-only legacy compatibility; heartbeat writers never use this fallback.
    const { companyDriverPresenceKey } = await import('./company_dispatch.mjs');
    return await env.BOOKING_KV.get(companyDriverPresenceKey(scoped), { type: 'json' });
  }
  const result = await callDriverIndexCoordinator(env, scoped, driverIds ? { driver_ids: driverIds } : undefined, 'presence_read');
  if (!result?.ok || !result.record) throw Error(result?.error || 'presence_coordinator_failed');
  return result.record;
}

export async function commitCompanyPresenceHeartbeat(env, scope, driverId, nowMs) {
  if (stagingFrozenReadRequested(env)) throw Error('staging_driver_index_operation_closed');
  if (!hasDriverIndexCoordinator(env)) throw Error('presence_coordinator_required');
  const result = await callDriverIndexCoordinator(env, normalizedScope(scope),
    { driver_id: driverId, now_ms: nowMs }, 'presence_heartbeat');
  if (!result?.ok) throw Error(result?.error || 'presence_coordinator_failed');
  // Preserve the existing heartbeat response shape.
  return { ok: true, wrote: result.wrote === true, last_seen_at: result.last_seen_at || '' };
}

export async function commitDriverIndexMutation(env, scope, mutation) {
  if (stagingFrozenReadRequested(env)) return failure(403,'staging_driver_index_operation_closed');
  const tenantId = sanitizeTenantString(scope?.tenant_id ?? scope?.tenantId, 80);
  const companyId = sanitizeTenantString(scope?.company_id ?? scope?.companyId, 80);
  if (!tenantId || !companyId) return failure(400, "invalid_tenant_or_company_scope");
  if (!env?.BOOKING_KV?.get || !env?.BOOKING_KV?.put) {
    return failure(500, "missing_booking_kv");
  }
  const scoped = { tenant_id: tenantId, company_id: companyId };
  if (hasDriverIndexCoordinator(env)) {
    return callDriverIndexCoordinator(env, scoped, mutation);
  }
  return enqueueLocal(
    driverIndexCoordinatorName(scoped),
    () => applyAndPersistDriverIndex(env, scoped, mutation, null),
  );
}

export function createMemoryDriverIndexCoordinatorStorage() {
  const store = new Map();
  return {
    async get(key) {
      return store.has(key) ? store.get(key) : undefined;
    },
    async put(key, value) {
      store.set(key, cloneJson(value));
    },
    async delete(key) { return store.delete(key); },
    async setAlarm(at) { this.alarmAt = at; },
    async deleteAlarm() { this.alarmAt = null; },
    _store: store,
  };
}

export class DriverIndexCoordinatorDO {
  constructor(state, env) {
    this.state = state;
    this.env = env;
    this.hotRecord = null;
    this.hotVehicles = null;
  }

  _index(record) {
    this.hotRecord = record;
    this.hotManagementIndex = prepareDriverManagementIndex(record);
    this.hotRegisteredCount = Object.keys(record.drivers || {}).length;
    this.hotVehicles = new Map();
    for (const [id, driver] of Object.entries(record.drivers || {})) for (const vehicle of linkedVehicleIds(driver)) {
      if (!this.hotVehicles.has(vehicle)) this.hotVehicles.set(vehicle, []);
      this.hotVehicles.get(vehicle).push(id);
    }
  }

  async fetch(request) {
    this._gate = this._gate || Promise.resolve();
    // Start only pure body parsing outside authority. Reserve the same FIFO
    // ticket before any await; original body remains usable by pause/cutover
    // verification. Scope/recovery/reads/mutations all remain inside the gate.
    let preparedBody;
    // Eager clone parsing is an optional generic runtime experiment. Native
    // end-to-end 1500-burst measurements did not improve, so default is OFF.
    if (this.env.ENTERPRISE_DRIVER_INPUT_PREPARE_ENABLED === '1' && typeof request.clone === 'function') {
      try { preparedBody = request.clone().json().catch(() => ({})); }
      catch { preparedBody = Promise.resolve({}); }
    }
    const run = this._gate.then(async () => {
      if (stagingFrozenReadRequested(this.env)) {
        const trialBody=await request.clone().json().catch(()=>null);
        if (trialBody?.action !== 'read_frozen_availability')
          return Response.json({ok:false,error:'staging_driver_index_operation_closed'},
            {status:403,headers:{'cache-control':'private, no-store'}});
      }
      if(bookingWritersPaused(this.env)){
        const body=await request.clone().json().catch(()=>null);
        if(body?.action==='read_frozen_bootstrap'){
          const scope=normalizedScope(body.scope),bound=await this.state.storage.get(SCOPE_KEY);
          if(!bound||!sameScope(bound,scope))return Response.json({ok:false,error:'driver_index_scope_conflict'},{status:409});
          if(await readBoundedJson(this.state.storage,PENDING_KEY))return Response.json({ok:false,error:'driver_index_recovery_pending'},{status:503});
          const record=await loadAuthoritative(this.env.BOOKING_KV,_companyDriverIndexKey(scope),this.state.storage);
          return Response.json({ok:true,record},{headers:{'cache-control':'private, no-store'}});
        }
        if(!await verifyBookingCutoverRequest(this.env,request,'driver'))return bookingWriterPauseResponse();
      }
      return this._handle(request,preparedBody?await preparedBody:undefined);
    }).catch(error => new Response(JSON.stringify({
      ok: false, status: error.message === 'driver_index_scope_conflict' ? 409 : 503, error: error.message,
    }), { status: error.message === 'driver_index_scope_conflict' ? 409 : 503,
      headers: { 'content-type': 'application/json' } }));
    this._gate = run.then(() => undefined, () => undefined);
    return run;
  }

  async alarm() {
    // A staging read trial must never recover a pending generation in the
    // background. Frozen reads refuse that state until it is resolved outside
    // the trial.
    if (stagingFrozenReadRequested(this.env)) return;
    this._gate ||= Promise.resolve();
    const run = this._gate.then(async () => {
      if (await deferPausedBookingAlarm(this.state, this.env)) return;
      const scope = await this.state.storage.get(SCOPE_KEY);
      if (!scope) return;
      try { await recoverProjection(this.env, scope, this.state.storage); }
      catch { await armRecovery(this.state.storage); }
      this.hotRecord = null; this.hotVehicles = null;
    });
    this._gate = run.then(() => undefined, () => undefined);
    return run;
  }

  async _handle(request, preparedBody = undefined) {
    let body = preparedBody;
    if (preparedBody === undefined) {
      try { body = await request.json(); } catch { body = {}; }
    }
    if (body?.action === 'read_frozen_availability') {
      const scope = normalizedScope(body.scope);
      const result = await readStagingFrozenDriverStateV1({env:this.env,storage:this.state.storage,scope});
      return Response.json(result,{status:result.ok?200:result.status??503,
        headers:{'cache-control':'private, no-store'}});
    }
    if (!['mutate', 'read', 'read_subset', 'read_page', 'read_metadata', 'read_sync_metadata', 'presence_read', 'presence_heartbeat'].includes(body?.action)) {
      return new Response(JSON.stringify({ ok: false, status: 400, error: "unknown_action" }), {
        status: 400,
        headers: { "content-type": "application/json" },
      });
    }
    if (body.action === 'presence_read' || body.action === 'presence_heartbeat') {
      const scope = normalizedScope(body.scope);
      await bindScope(this.state.storage, scope);
      return Response.json(await presenceOperation(this.env, this.state.storage, scope,
        body.mutation));
    }
    if (['read_subset', 'read_page', 'read_metadata', 'read_sync_metadata'].includes(body.action)) {
      const scope = normalizedScope(body.scope);
      await bindScope(this.state.storage, scope);
      // Absence is checked on every request. Existing inline/chunked pending
      // generations still take the complete verified recovery path.
      const noPending = typeof this.state.storage.kv?.get === 'function' && this.state.storage.kv.get(PENDING_KEY) == null;
      const pending = noPending ? null : await readBoundedJson(this.state.storage, PENDING_KEY);
      if (pending) { await recoverProjection(this.env, scope, this.state.storage); this.hotRecord = null; }
      if (!this.hotRecord) this._index(await loadAuthoritative(this.env.BOOKING_KV, _companyDriverIndexKey(scope), this.state.storage));
      if(body.action==='read_sync_metadata'){
        const presence=await presenceOperation(this.env,this.state.storage,scope,{metadata_only:true});
        return Response.json({ok:true,generation:generationOf(this.hotRecord),presence_revision:presence.revision});
      }
      if (body.action === 'read_metadata') return Response.json({ ok: true, generation: generationOf(this.hotRecord), registered_count: this.hotRegisteredCount });
      if (body.action === 'read_page') {
        const presence = body.mutation?.online != null && body.mutation.online !== ''
          ? (await presenceOperation(this.env, this.state.storage, scope, { driver_ids: Object.keys(this.hotRecord.drivers) })).record : {};
        return Response.json(driverManagementPage(this.hotRecord, scope, body.mutation, presence, this.hotManagementIndex));
      }
      const ids = new Set((body.mutation?.driver_ids || []).map(id => sanitizeTenantString(id, 96)));
      for (const vehicle of body.mutation?.vehicle_ids || []) for (const id of this.hotVehicles.get(sanitizeTenantString(vehicle, 128)) || []) ids.add(id);
      const drivers = {};
      for (const id of ids) if (this.hotRecord.drivers[id] && !this.hotRecord.deleted_drivers?.[id]) drivers[id] = this.hotRecord.drivers[id];
      return Response.json({ ok: true, record: { drivers, driver_index_generation: generationOf(this.hotRecord),
        updated_at: this.hotRecord.updated_at, registered_count: this.hotRegisteredCount } });
    }
    if (body.action === 'read') {
      const scope = normalizedScope(body.scope);
      await bindScope(this.state.storage, scope);
      await recoverProjection(this.env, scope, this.state.storage);
      const record = await loadAuthoritative(this.env.BOOKING_KV, _companyDriverIndexKey(scope), this.state.storage);
      this._index(record);
      return Response.json({ ok: true, record });
    }
    const result = await applyAndPersistDriverIndex(
      this.env,
      body.scope,
      body.mutation,
      this.state?.storage,
    );
    const status = Number.isInteger(result?.status) ? result.status : 500;
    if (result?.ok && result.record) this._index(result.record);
    else { this.hotRecord = null; this.hotVehicles = null; }
    return new Response(JSON.stringify(result || { ok: false, status: 500, error: "driver_index_coordinator_failed" }), {
      status,
      headers: { "content-type": "application/json" },
    });
  }
}

export function createMemoryDriverIndexCoordinatorBinding(env = {}) {
  const instances = new Map();
  return {
    idFromName(name) {
      return { name: String(name || "") };
    },
    get(id) {
      const name = String(id?.name || "");
      if (!instances.has(name)) {
        const storage = createMemoryDriverIndexCoordinatorStorage();
        const dob = new DriverIndexCoordinatorDO({ storage }, env);
        instances.set(name, dob);
      }
      const dob = instances.get(name);
      dob.env = env;
      return dob;
    },
    _instances: instances,
  };
}

export async function readCompanyFleetSyncMetadata(env,scope){if(!hasDriverIndexCoordinator(env))return null;const result=await callDriverIndexCoordinator(env,normalizedScope(scope),undefined,'read_sync_metadata');if(!result?.ok)throw Error(result?.error||'fleet_metadata_unavailable');return result;}

export async function readCompanyDriverMetadata(env,scope){
 if(!hasDriverIndexCoordinator(env))return null;
 const result=await callDriverIndexCoordinator(env,normalizedScope(scope),undefined,'read_metadata');
 if(!result?.ok)throw Error(result?.error||'driver_metadata_unavailable');
 return result;
}
