import { readCompanyOperationDecision } from '../../booking/modules/company_operation_guard.mjs';
// Realtime last-location per company. Workers KV is not used here.
// Sleeps between HTTP requests; offers and busy-driver successors arm bounded work.

import { persistVehicleDutyCommand, vehicleDutyCommandReplay, readVehicleDutyHistory, VEHICLE_DUTY_STATE_KEY, VEHICLE_DUTY_PROJECTION_KEY } from './company_vehicle_duty_storage.mjs';
import { vehicleDeviceCommand } from './company_vehicle_device.mjs';
import { dutyForRideExecution } from '../../booking/modules/company_vehicle_duty.mjs';
import { personalDriverExecutionV1 } from './personal_driver_execution_v1.mjs';
import { createPerDriverState } from './per_driver_state.mjs';
import { createActiveSpatialIndex } from '../../booking/modules/active_spatial_index.mjs';
import { createAdaptiveEtaCache } from './customer_adaptive_eta.mjs';
import { mapboxDispatchRouteEta } from '../../booking/modules/company_dispatch_mapbox.mjs';
import { operationalCustomerRouteEtaV1 } from '../../booking/modules/reliable_operational_routes_v1.mjs';
import { emitTenantCostMetric } from '../../booking/modules/tenant_cost_metrics.mjs';
import {
  applyCustomerLifecycle,
  customerAccessAllowed,
  grantKey,
  projectCustomerSnapshot,
} from "./customer_live_snapshot.mjs";
import { readCustomerGrantSnapshot, writeCustomerGrantSnapshot, readStoredCustomerGrant,
  hydrateCustomerGrantEvent } from './customer_grant_storage.mjs';
import { updateDispatchDevice, driverDispatchDevices, projectDispatchDevices } from './dispatch_device_capability.mjs';
import { capacityClaimDecision, capacityBaselineDecision, sameCapacityResource, overdueCapacityHold, unstartedCapacityExpired } from "./company_capacity_ledger.mjs";
import { readCapacitySnapshot, writeCapacitySnapshot, hydrateCapacityRecords, CAPACITY_STORAGE_KEY } from './company_capacity_storage.mjs';
import { boundLocationOwner, sameLocationOwner, retainedLocationOwners, locationOwnerRetired,
  nextRetiredLocationOwners, LOCATION_RETIRED_OWNER_LIMIT } from './driver_location_owner.mjs';
import { dispatchOfferDecision, revalidateDispatchOffers, preemptPrerequisiteOffers, preemptDispatchOffers,
  acknowledgeDispatchEvent, nextDispatchAlarm, dispatchSearchDecision, dispatchOfferResources,
  queueConfirmedSuccessorChecks, preemptOwnerAmendments } from './company_dispatch_offers.mjs';

export const LOCATION_RATE_LIMIT_PER_MINUTE = 12;
export const LOCATION_DEDUPE_METERS = 15;
export const LOCATION_DEDUPE_MS = 20_000;
export const LOCATION_FUTURE_SKEW_MS = 120_000;
export const LOCATION_STALE_DEFAULT_SECONDS = 300;
export const LOCATION_STALE_MIN_SECONDS = 30;
export const LOCATION_STALE_MAX_SECONDS = 3600;
export const LOCATION_MAX_ACCURACY_M = 150;

const STORAGE_KEY = "drivers_v1";
const DIRECT_OCCUPANCY_KEY = "direct_occupancy_active_v1";
const DISPATCH_DEVICES_KEY = "dispatch_devices_v1";

export function companyTrackingObjectName(tenantId, companyId) {
  return `${tenantId}\n${companyId}`;
}

export function clampFreshnessSeconds(value) {
  if (value === undefined || value === null || value === "") return LOCATION_STALE_DEFAULT_SECONDS;
  const n = Number(value);
  if (!Number.isFinite(n)) return LOCATION_STALE_DEFAULT_SECONDS;
  return Math.min(LOCATION_STALE_MAX_SECONDS, Math.max(LOCATION_STALE_MIN_SECONDS, Math.floor(n)));
}

function haversineMeters(lat1, lon1, lat2, lon2) {
  const r = 6371000;
  const p1 = (lat1 * Math.PI) / 180;
  const p2 = (lat2 * Math.PI) / 180;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLon = ((lon2 - lon1) * Math.PI) / 180;
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(p1) * Math.cos(p2) * Math.sin(dLon / 2) ** 2;
  return 2 * r * Math.asin(Math.min(1, Math.sqrt(h)));
}

function finiteCoord(value, min, max) {
  const n = Number(value);
  if (!Number.isFinite(n) || n < min || n > max) return null;
  return n;
}

export function validateLocationSample(input, nowMs) {
  const latitude = finiteCoord(input?.latitude, -90, 90);
  const longitude = finiteCoord(input?.longitude, -180, 180);
  if (latitude === null || longitude === null) {
    return { ok: false, status: 400, error: "location_invalid" };
  }
  if (input?.accuracy !== undefined && input?.accuracy !== null && input?.accuracy !== "") {
    const accuracy = Number(input.accuracy);
    if (!Number.isFinite(accuracy) || accuracy < 0 || accuracy > LOCATION_MAX_ACCURACY_M) {
      return { ok: false, status: 400, error: "location_accuracy_rejected" };
    }
  }
  let capturedMs = nowMs;
  if (input?.captured_at) {
    capturedMs = Date.parse(String(input.captured_at));
    if (!Number.isFinite(capturedMs)) {
      return { ok: false, status: 400, error: "location_captured_at_invalid" };
    }
  }
  if (capturedMs - nowMs > LOCATION_FUTURE_SKEW_MS) {
    return { ok: false, status: 400, error: "location_captured_at_invalid" };
  }
  return { ok: true, latitude, longitude, capturedMs };
}

function pruneHits(hits, nowMs) {
  const cutoff = nowMs - 60_000;
  return (Array.isArray(hits) ? hits : []).filter((ts) => Number(ts) > cutoff);
}

// Customer GPS is a capability-scoped sample, never inferred from driver presence.
function matchesTrackingScope(row, context, grant) {
  return Boolean(row && context && grant && !grant.leg_scope_retired &&
    typeof context.booking_id === "string" && context.booking_id.length > 0 &&
    typeof context.operational_leg === "string" && context.operational_leg.length > 0 &&
    Number.isInteger(context.assignment_version) && context.assignment_version > 0 &&
    row.tenant_id === grant.tenant_id && row.company_id === grant.company_id &&
    row.driver_id === grant.driver_id &&
    context.booking_id === grant.booking_id && context.operational_leg === grant.operational_leg &&
    context.assignment_version === grant.assignment_version);
}

export function applyLocationUpdate(drivers, input, nowMs) {
  const next = { ...drivers };
  const driverId = String(input.driver_id || "");
  const companyId = String(input.company_id || "");
  if (!driverId || !companyId) {
    return { drivers: next, result: { ok: false, status: 400, error: "location_identity_missing" } };
  }
  const checked = validateLocationSample(input, nowMs);
  if (!checked.ok) {
    return { drivers: next, result: checked };
  }
  const current = next[driverId] ? { ...next[driverId] } : null;
  const hits = pruneHits(current?.recent_hits, nowMs);
  if (hits.length >= LOCATION_RATE_LIMIT_PER_MINUTE) {
    const oldest = hits[0];
    const retryAfter = Math.max(1, Math.ceil((oldest + 60_000 - nowMs) / 1000));
    return {
      drivers: next,
      result: {
        ok: false,
        status: 429,
        error: "location_rate_limited",
        retry_after_seconds: retryAfter,
      },
    };
  }
  hits.push(nowMs);
  const staleLimitMs = clampFreshnessSeconds(input.freshness_seconds) * 1000;
  if (nowMs - checked.capturedMs > staleLimitMs) {
    if (current) next[driverId] = { ...current, recent_hits: hits };
    return {
      drivers: next,
      result: { ok: true, applied: false, reason: "captured_at_too_old", driver_id: driverId },
    };
  }
  if (current && Number.isFinite(current.captured_ms)) {
    if (checked.capturedMs < current.captured_ms) {
      next[driverId] = { ...current, recent_hits: hits };
      return {
        drivers: next,
        result: { ok: true, applied: false, reason: "older_captured_at", driver_id: driverId },
      };
    }
    if (checked.capturedMs === current.captured_ms && (sameLocationOwner(input.publication_owner, current.publication_owner)
      || !input.publication_owner && !current.publication_owner)) {
      const trackingStatus = input.tracking_status ? String(input.tracking_status) : "active";
      const contextChanged = JSON.stringify(input.tracking_context || null) !== JSON.stringify(current.tracking_context || null) ||
        trackingStatus !== String(current.tracking_status || "active");
      if (contextChanged) {
        // Native presence and the foreground lifecycle can publish the same
        // device fix. Room has already validated the new context against the
        // current grant in this serialized turn. Bind that metadata without
        // replacing coordinates, ownership, or either GPS/liveness timestamp.
        next[driverId] = { ...current, recent_hits: hits,
          tracking_context: input.tracking_context || null, tracking_status: trackingStatus,
          availability_status: input.availability_status ? String(input.availability_status) : current.availability_status,
        };
        return { drivers: next, result: { ok: true, applied: true, reason: "tracking_context_updated", driver_id: driverId } };
      }
      next[driverId] = { ...current, recent_hits: hits };
      return {
        drivers: next,
        result: { ok: true, applied: false, reason: "duplicate_captured_at", driver_id: driverId },
      };
    }
    const moved = haversineMeters(current.latitude, current.longitude, checked.latitude, checked.longitude);
    const statusChanged = String(input.tracking_status || "") !== String(current.tracking_status || "") ||
      JSON.stringify(input.tracking_context || null) !== JSON.stringify(current.tracking_context || null) ||
      JSON.stringify(input.publication_owner || null) !== JSON.stringify(current.publication_owner || null) || current.location_withdrawn === true;
    if (
      !statusChanged &&
      moved <= LOCATION_DEDUPE_METERS &&
      checked.capturedMs - current.captured_ms <= LOCATION_DEDUPE_MS
    ) {
      next[driverId] = {
        ...current,
        recent_hits: hits,
        last_seen_at: new Date(nowMs).toISOString(),
      };
      return {
        drivers: next,
        result: {
          ok: true,
          applied: false,
          liveness_updated: true,
          reason: "duplicate_location",
          driver_id: driverId,
        },
      };
    }
  }
  const accuracy =
    input.accuracy === undefined || input.accuracy === null || input.accuracy === ""
      ? null
      : Number(input.accuracy);
  next[driverId] = {
    driver_id: driverId,
    tenant_id: input.tenant_id || null,
    company_id: companyId,
    vehicle_id: input.vehicle_id ? String(input.vehicle_id) : null,
    latitude: checked.latitude,
    longitude: checked.longitude,
    accuracy,
    heading: Number.isFinite(Number(input.heading)) ? Number(input.heading) : null,
    speed: Number.isFinite(Number(input.speed)) ? Number(input.speed) : null,
    captured_at: new Date(checked.capturedMs).toISOString(),
    captured_ms: checked.capturedMs,
    position_captured_at: new Date(checked.capturedMs).toISOString(),
    last_seen_at: new Date(nowMs).toISOString(),
    received_at: new Date(nowMs).toISOString(),
    availability_status: input.availability_status ? String(input.availability_status) : null,
    tracking_status: input.tracking_status ? String(input.tracking_status) : "active",
    tracking_context: input.tracking_context || null,
    publication_owner: input.publication_owner || null,
    ...(current?.retired_publications ? { retired_publications: current.retired_publications } : {}),
    recent_hits: hits,
  };
  return {
    drivers: next,
    result: { ok: true, applied: true, driver_id: driverId },
  };
}

export function projectCompanyLive(drivers, { tenantId, companyId, nowMs, freshnessSeconds, accessSessionForRow }) {
  const freshness = clampFreshnessSeconds(freshnessSeconds);
  const list = [];
  for (const row of Object.values(drivers || {})) {
    if (!row || row.location_withdrawn === true || row.company_id !== companyId || row.tenant_id !== tenantId) continue;
    const positionCapturedAt = row.position_captured_at || row.captured_at || "";
    const lastSeenAt = row.last_seen_at || row.received_at || "";
    const positionAgeMs = nowMs - Date.parse(positionCapturedAt);
    const seenAgeMs = nowMs - Date.parse(lastSeenAt);
    const positionStale = !Number.isFinite(positionAgeMs) || positionAgeMs > freshness * 1000;
    const locationFeedStale = !Number.isFinite(seenAgeMs) || seenAgeMs > freshness * 1000;
    const accuracyOk = row.accuracy == null || (Number(row.accuracy) >= 0 && Number(row.accuracy) <= LOCATION_MAX_ACCURACY_M);
    list.push({
      driver_id: row.driver_id,
      tenant_id: row.tenant_id,
      company_id: row.company_id,
      vehicle_id: row.vehicle_id ?? null,
      latitude: row.latitude,
      longitude: row.longitude,
      accuracy: row.accuracy ?? null,
      heading: row.heading ?? null,
      speed: row.speed ?? null,
      captured_at: positionCapturedAt,
      position_captured_at: positionCapturedAt,
      last_seen_at: lastSeenAt,
      received_at: row.received_at,
      availability_status: row.availability_status ?? null,
      tracking_status: row.tracking_status ?? null,
      tracking_context: row.tracking_context || null,
      ...(accessSessionForRow?{access_session:accessSessionForRow(row,nowMs)}:{}),
      location_feed: locationFeedStale ? "stale" : "live",
      stale: locationFeedStale,
      position_stale: positionStale,
      reliable_for_eta: !positionStale && accuracyOk,
    });
  }
  list.sort((a, b) => String(a.driver_id).localeCompare(String(b.driver_id)));
  return {
    ok: true,
    tenant_id: tenantId,
    company_id: companyId,
    freshness_seconds: freshness,
    drivers: list,
  };
}

export function clearDriver(drivers, driverId) {
  const next = { ...drivers };
  delete next[driverId];
  return next;
}

function persistable(drivers) {
  const out = {};
  for (const [id, row] of Object.entries(drivers || {})) {
    if (!row) continue;
    const copy = { ...row };
    delete copy.recent_hits;
    out[id] = copy;
  }
  return out;
}

export class CompanyTrackingRoom {
  constructor(state, env) {
    this.state = state;
    this.env = env;
    this.drivers = null;
    this.driverRows = createPerDriverState(state.storage, STORAGE_KEY, 'tracking-driver:v2:', {
      onWrite: env.TENANT_COST_METRICS_ENABLED === '1' ? async (row, writes, bytes) => {
        if (!row?.tenant_id || !row?.company_id) return;
        await emitTenantCostMetric(env, row, 'storage_writes', writes);
        await emitTenantCostMetric(env, row, 'storage_bytes', bytes);
      } : undefined,
    });
    this.driversLoaded = null;
    this.grants = null;
    this.grantsLoaded = null;
    this.directOccupancy = null;
    this.directOccupancyLoaded = null;
    this.directOccupancyQueue = Promise.resolve();
    this.capacity = null;
    this.capacityLoaded = null;
    this.dispatchDrain = null;
    this.dispatchDevices = null;
    this.dispatchDevicesLoaded = null;
    this.hits = new Map();
    // Opaque publication labels only, no GPS/history and no storage writes.
    this.accessSessions = new Map();
  }

  accessSessionForRow(row, nowMs) {
    for(const [key,value]of this.accessSessions)if(value.expiresAt<=nowMs)this.accessSessions.delete(key);
    if(!boundLocationOwner(row.publication_owner,nowMs)||row.location_withdrawn===true)return null;
    const key=JSON.stringify([row.tenant_id,row.company_id,row.driver_id]),previous=this.accessSessions.get(key),owner=row.publication_owner;
    if(previous&&sameLocationOwner(previous.owner,owner)&&previous.vehicleId===row.vehicle_id&&previous.availability===row.availability_status){previous.expiresAt=nowMs+15000;return previous.label;}
    if(!previous&&this.accessSessions.size>=512)this.accessSessions.delete(this.accessSessions.keys().next().value);
    const label=crypto.randomUUID();this.accessSessions.set(key,{owner,vehicleId:row.vehicle_id,availability:row.availability_status,label,expiresAt:nowMs+15000});return label;
  }

  async load() {
    if (!this.drivers) {
      const trialReadOnly = this.env?.STAGING_TRIAL_MODE === '1'
        || this.env?.STAGING_TRIAL_ENVIRONMENT === 'staging';
      this.driversLoaded ||= (trialReadOnly ? this.driverRows.loadReadOnly() : this.driverRows.load()).then(stored => {
        this.drivers = stored && typeof stored === "object" ? stored : {};
      }).catch(error => { this.driversLoaded = null; throw error; });
      await this.driversLoaded;
    }
    if (!this.grants) {
      this.grantsLoaded ||= readCustomerGrantSnapshot(this.state.storage).then(stored => {
        this.grants = stored;
      }).catch(error => { this.grantsLoaded = null; throw error; });
      await this.grantsLoaded;
    }
    if (!this.directOccupancy) {
      this.directOccupancyLoaded ||= this.state.storage.get(DIRECT_OCCUPANCY_KEY).then(stored => {
        this.directOccupancy = stored || {};
      }).catch(error => { this.directOccupancyLoaded = null; throw error; });
      await this.directOccupancyLoaded;
    }
    if (!this.capacity) {
      this.capacityLoaded ||= readCapacitySnapshot(this.state.storage).then(stored => {
        this.capacity = stored;
      }).catch(error => { this.capacityLoaded = null; throw error; });
      await this.capacityLoaded;
    }
    if (!this.dispatchDevices) {
      this.dispatchDevicesLoaded ||= this.state.storage.get(DISPATCH_DEVICES_KEY).then(stored => {
        this.dispatchDevices = stored || { devices: {} };
      }).catch(error => { this.dispatchDevicesLoaded = null; throw error; });
      await this.dispatchDevicesLoaded;
    }
    if (this.capacity.direct_holds) this.directOccupancy = this.capacity.direct_holds;
  }

  capacityScopeAllowed(input) {
    const bound = this.capacity.scope || this.capacity.baseline || Object.values(this.capacity.owners)[0]
      || Object.values(this.directOccupancy)[0] || this.dispatchDevices.scope || this.grants.scope
      || Object.values(this.grants.grants || {}).find(row => row?.tenant_id && row?.company_id);
    return !bound || bound.tenant_id === input.tenant_id && bound.company_id === input.company_id;
  }

  async hydrateCapacity(identities, scope) {
    this.capacity = await hydrateCapacityRecords(this.state.storage, this.capacity, identities, scope);
  }

  async writeCapacity(next, scope) {
    const bound = this.capacity.scope || scope;
    const stored = { ...next, ...(bound ? { scope: { tenant_id: bound.tenant_id, company_id: bound.company_id } } : {}) };
    const expiry = nextDispatchAlarm(stored, this.drivers, this.dispatchDevices);
    const pendingEvents = Object.values(stored.dispatch_events || {}).some(event => event.state === 'pending');
    const delivery = pendingEvents ? Date.now() + 1000 : null;
    const deadlines = [expiry, delivery].filter(value => value != null);
    const deadline = deadlines.length ? Math.min(...deadlines) : null;
    // Schedule before the durable decision. If persistence fails the alarm is
    // harmless; if it succeeds there is already a wakeup even after restart.
    if (deadline != null) await this.state.storage.setAlarm(deadline);
    this.capacity = await writeCapacitySnapshot(this.state.storage, stored, this.capacity, Date.now());
    if (stored.direct_holds) this.directOccupancy = stored.direct_holds;
    if (pendingEvents && this.env.BOOKING_API && this.env.ADMIN_TOKEN && this.state.waitUntil) {
      this.state.waitUntil(Promise.resolve().then(() => this.drainDispatchEvents()));
    }
  }

  async drainDispatchEvents() {
    if (this.dispatchDrain) return this.dispatchDrain;
    const run = async () => {
      let events = [];
      const choose = this.directOccupancyQueue.then(async () => {
        const pending = Object.values(this.capacity.dispatch_events || {}).filter(event => event.state === 'pending')
          .sort((a, b) => a.created_at_ms - b.created_at_ms || a.event_id.localeCompare(b.event_id));
        const last = pending.findIndex(event => event.event_id === this.capacity.dispatch_delivery_cursor);
        events = [...pending.slice(last + 1), ...pending.slice(0, last + 1)].slice(0, 8);
        if (events.length && this.env.BOOKING_API && this.env.ADMIN_TOKEN) await this.writeCapacity({ ...this.capacity,
          dispatch_delivery_cursor: events.at(-1).event_id });
      });
      this.directOccupancyQueue = choose.catch(() => {});
      await choose;
      for (const event of events) {
        if (!this.env.BOOKING_API || !this.env.ADMIN_TOKEN) break;
        try {
          // Outside the occupancy queue: Booking calls back here to confirm
          // capacity and acknowledge the event. Holding that queue deadlocks.
          const response = await this.env.BOOKING_API.fetch(new Request('https://booking/track/dispatch/event', {
            method: 'POST', headers: { 'content-type': 'application/json', 'x-admin-token': this.env.ADMIN_TOKEN },
            body: JSON.stringify({ tenant_id: event.tenant_id, company_id: event.company_id, event_id: event.event_id }),
            signal: AbortSignal.timeout(8000),
          }));
          const result = await response.json();
          if (!response.ok || result.ok !== true) continue;
        } catch (_) { continue; }
      }
      const reschedule = this.directOccupancyQueue.then(async () => {
        const pending = Object.values(this.capacity.dispatch_events || {}).some(event => event.state === 'pending');
        const expiry = nextDispatchAlarm(this.capacity, this.drivers, this.dispatchDevices);
        const delivery = pending ? Date.now() + 60_000 : null;
        const deadlines = [expiry, delivery].filter(value => value != null);
        if (deadlines.length) await this.state.storage.setAlarm(Math.min(...deadlines));
        else if (this.state.storage.deleteAlarm) await this.state.storage.deleteAlarm();
      });
      this.directOccupancyQueue = reschedule.catch(() => {});
      await reschedule;
    };
    this.dispatchDrain = run().finally(() => { this.dispatchDrain = null; });
    return this.dispatchDrain;
  }

  async expireOffers(nowMs) {
    const next = queueConfirmedSuccessorChecks(
      revalidateDispatchOffers(this.capacity, this.drivers, nowMs, this.dispatchDevices), nowMs);
    if (next !== this.capacity) await this.writeCapacity(next);
  }

  async alarm() {
    // The isolated staging trial must not advance offers or dispatch delivery
    // through an old alarm while the read-only availability path is assessed.
    if (this.env?.STAGING_TRIAL_MODE === '1' ||
        this.env?.STAGING_TRIAL_ENVIRONMENT === 'staging') return;
    await this.load();
    const operation = this.directOccupancyQueue.then(async () => {
      await this.expireOffers(Date.now());
      // A fresh ping can move the GPS expiry beyond the alarm that woke us.
      // Preserve the original ACK deadline even when no capacity changed.
      const next = nextDispatchAlarm(this.capacity, this.drivers, this.dispatchDevices);
      if (next != null) await this.state.storage.setAlarm(next);
    });
    this.directOccupancyQueue = operation.catch(() => {});
    await operation;
    await this.drainDispatchEvents();
  }

  async fetch(request) {
    if (request.method === 'POST' && new URL(request.url).pathname === '/navigation-authority') {
      const run = this.directOccupancyQueue.then(async () => {
        const {readRoomNavigationAuthorityV1} = await import('../../booking/modules/national_navigation_authorization_v1.mjs');
        const body = await request.clone().json().catch(() => null);
        return readRoomNavigationAuthorityV1(this.state, this.env, request, body);
      });
      this.directOccupancyQueue = run.then(() => undefined, () => undefined);
      return run;
    }
    if (request.method === 'POST' && new URL(request.url).pathname === '/canonical-inspection') {
      const {inspectCapacityWithoutMutation} = await import('../../booking/modules/canonical_booking_inspection.mjs');
      const body = await request.clone().json().catch(() => null);
      return inspectCapacityWithoutMutation(this.state, this.env, request, body);
    }
    await this.load();
    const url = new URL(request.url);
    const nowMs = Date.now();
    if (request.method === 'POST' && url.pathname === '/customer-route') {
      if (this.env.CUSTOMER_ETA_SHARED_ROOM_ENABLED !== '1') return Response.json({ ok: false, error: 'shared_eta_disabled' }, { status: 503 });
      const input = await request.json();
      const liveUrl = new URL(url); liveUrl.pathname = '/customer-live';
      const read = () => this.fetch(new Request(liveUrl, { method: 'GET' }));
      const initial = await read();
      if (!initial.ok) return initial;
      const snapshot = await initial.json();
      if (!snapshot.position || !['en_route_pickup','in_progress'].includes(snapshot.tracking_phase)) return Response.json({ ok: true, eta: null });
      if (input.response_version !== snapshot.response_version) return Response.json({ ok: false, error: 'assignment_changed' }, { status: 409 });
      const grant = await readStoredCustomerGrant(this.state.storage, this.grants,
        grantKey(url.searchParams.get('booking_id'), url.searchParams.get('operational_leg')), this.grants.scope);
      const target = snapshot.tracking_phase === 'in_progress' ? 'destination' : 'pickup';
      this.sharedEta ||= createAdaptiveEtaCache(args => typeof this.env.__customerEtaFetch === 'function'
        ? this.env.__customerEtaFetch(args) : mapboxDispatchRouteEta(this.env, { ...args, includeGeometry: true }));
      const routeInput = { origin: snapshot.position,
        destination: target === 'destination' ? grant.destination : grant.pickup, target,
        context: { tenant_id: grant.tenant_id, company_id: grant.company_id, booking_id: grant.booking_id,
          operational_leg: grant.operational_leg || 'primary', session_id: grant.session_id,
          assignment_version: grant.assignment_version, lifecycle_seq: grant.lifecycle_seq },
        observability: { scope: { tenant_id: grant.tenant_id, company_id: grant.company_id }, operation: 'customer_live_eta' } };
      // The legacy adaptive cache labels and retains provider evidence. An
      // operational local route must not reuse it across traffic revisions.
      // Unknown local access yields no ETA, never a commercial fallback.
      const eta = this.env.RELIABLE_CHOICE_ENABLED==='1'
        ? await operationalCustomerRouteEtaV1(this.env,routeInput).catch(()=>null)
        : await this.sharedEta.resolve(routeInput);
      const final = await read(); if (!final.ok) return final;
      const latest = await final.json();
      if (!latest.position || latest.response_version !== snapshot.response_version || latest.tracking_phase !== snapshot.tracking_phase)
        return Response.json({ ok: false, error: 'assignment_changed' }, { status: 409 });
      return Response.json({ ok: true, eta });
    }
    if (request.method === 'POST' && url.pathname === '/vehicle-device') {
      if (this.env?.COMPANY_VEHICLE_OPERATIONS_ENABLED !== '1') return Response.json({ ok: false, error: 'vehicle_operations_disabled' }, { status: 503 });
      const input = await request.json();
      const operation = this.directOccupancyQueue.then(async () => {
        if (!this.capacityScopeAllowed(input)) return Response.json({ ok: false, error: 'vehicle_device_scope_mismatch' }, { status: 403 });
        if (input.action === 'transition') {
          const device = await this.state.storage.get(`vehicle_device_v1:${input.device_id}`);
          if (device && !device.revoked && Object.values(this.drivers || {}).some(row =>
            [device.vehicle_id,input.operation === 'switch' ? input.vehicle_id : null].includes(row.vehicle_id) && row.location_withdrawn !== true
            && boundLocationOwner(row.publication_owner, Date.now())))
            return Response.json({ok:false,error:'gps_publication_blocks_device_change'},{status:409});
        }
        const result = await vehicleDeviceCommand(this.state.storage, input, Date.now());
        if (result.ok && input.action === 'transition') {
          this.dispatchDevicesLoaded = null;
          this.dispatchDevices = await this.state.storage.get(DISPATCH_DEVICES_KEY) || {devices:{}};
        }
        if (result.ok && input.action === 'revoke') {
          this.dispatchDevices = null;
          this.dispatchDevicesLoaded = null;
          this.dispatchDevices = await this.state.storage.get(DISPATCH_DEVICES_KEY) || { devices: {} };
          await this.expireOffers(Date.now());
        }
        return Response.json(result, { status: result.ok ? 200 : 403 });
      });
      this.directOccupancyQueue = operation.catch(() => {});
      return operation;
    }
    if (request.method === 'POST' && url.pathname === '/vehicle-duty-projection') {
      if (this.env?.COMPANY_VEHICLE_OPERATIONS_ENABLED !== '1') return Response.json({ ok: false, error: 'vehicle_operations_disabled' }, { status: 503 });
      const input = await request.json();
      const operation = this.directOccupancyQueue.then(async () => {
        if (!this.capacityScopeAllowed(input)) return Response.json({ ok: false, error: 'duty_scope_mismatch' }, { status: 403 });
        const pending = await this.state.storage.get(VEHICLE_DUTY_PROJECTION_KEY);
        if (pending && (pending.tenant_id !== input.tenant_id || pending.company_id !== input.company_id)) return Response.json({ ok: false, error: 'duty_scope_mismatch' }, { status: 403 });
        if (input.confirm_version != null) {
          if (pending && pending.version !== input.confirm_version) return Response.json({ ok: false, error: 'duty_projection_conflict' }, { status: 409 });
          if (pending) await this.state.storage.delete(VEHICLE_DUTY_PROJECTION_KEY);
          return Response.json({ ok: true });
        }
        return Response.json({ ok: true, pending: pending ?? null });
      });
      this.directOccupancyQueue = operation.catch(() => {});
      return operation;
    }
    if (request.method === 'POST' && url.pathname === '/vehicle-duty-admin-state') {
      if (this.env?.COMPANY_VEHICLE_OPERATIONS_ENABLED !== '1') return Response.json({ ok: false, error: 'vehicle_operations_disabled' }, { status: 503 });
      const input = await request.json();
      const operation = this.directOccupancyQueue.then(async () => {
        if (input.role !== 'company_admin' || !this.capacityScopeAllowed(input)) return Response.json({ ok: false, error: 'duty_scope_mismatch' }, { status: 403 });
        const stored = await this.state.storage.get(VEHICLE_DUTY_STATE_KEY);
        if (stored && (stored.tenant_id !== input.tenant_id || stored.company_id !== input.company_id)) return Response.json({ ok: false, error: 'duty_scope_mismatch' }, { status: 403 });
        return Response.json({ ok: true, version: stored?.version ?? 0, vehicle_id: input.vehicle_id,
          duties: (stored?.duties || []).filter(row => row.vehicle_id === input.vehicle_id) });
      });
      this.directOccupancyQueue = operation.catch(() => {});
      return operation;
    }
    if (request.method === 'POST' && url.pathname === '/vehicle-duty-recover') {
      if (this.env?.COMPANY_VEHICLE_OPERATIONS_ENABLED !== '1') return Response.json({ ok: false, error: 'vehicle_operations_disabled' }, { status: 503 });
      const input = await request.json();
      const operation = this.directOccupancyQueue.then(async () => {
        if (input.role !== 'company_admin' || !this.capacityScopeAllowed(input)
          || !['device_lost', 'device_replaced'].includes(input.reason)) return Response.json({ ok: false, error: 'duty_recovery_invalid' }, { status: 403 });
        const actor = { tenant_id: input.tenant_id, company_id: input.company_id, driver_id: input.driver_id };
        if (!/^[a-zA-Z0-9_.-]{1,96}$/.test(input.device_id || '')) return Response.json({ ok: false, error: 'duty_recovery_invalid' }, { status: 400 });
        const device = await this.state.storage.get(`vehicle_device_v1:${input.device_id}`);
        if (!device || device.vehicle_id !== input.vehicle_id || !device.revoked && device.expires_at_ms > Date.now()) {
          return Response.json({ ok: false, error: 'device_must_be_unpaired_for_recovery' }, { status: 409 });
        }
        const audit = { role: 'company_admin', company_id: input.company_id, reason: input.reason, device_id: input.device_id };
        const command = { ...input, action: 'end' };
        const replay = await vehicleDutyCommandReplay(this.state.storage, command, actor, { recoveryAudit: audit });
        if (replay) return Response.json(replay, { status: replay.ok ? 200 : 409 });
        const dutyState = await this.state.storage.get(VEHICLE_DUTY_STATE_KEY);
        const targetDuty = dutyState?.duties?.find(row => row.duty_id === input.duty_id && row.driver_id === input.driver_id && row.vehicle_id === input.vehicle_id);
        if (targetDuty?.vehicle_device_id && targetDuty.vehicle_device_id !== input.device_id) {
          return Response.json({ ok: false, error: 'duty_recovery_device_mismatch' }, { status: 409 });
        }
        if (this.capacity.baseline?.tenant_id !== input.tenant_id || this.capacity.baseline?.company_id !== input.company_id) {
          return Response.json({ ok: false, error: 'capacity_baseline_required' }, { status: 409 });
        }
        const now = Date.now();
        const matches = row => row.driver_id === input.driver_id || row.vehicle_id === input.vehicle_id;
        const busy = Object.values(this.directOccupancy).some(matches)
          || Object.values(this.capacity.claims || {}).some(row => matches(row)
            && (row.active === true || row.end_ms > now || overdueCapacityHold(row, now, this.capacity.owners?.[row.owner_id])));
        if (busy) return Response.json({ ok: false, error: 'active_ride_blocks_duty_change' }, { status: 409 });
        // Active delivery sessions must be revoked or naturally expire first.
        if (Object.values(this.dispatchDevices?.devices || {}).some(row => row.driver_id === input.driver_id && row.valid_until_ms > now)) {
          return Response.json({ ok: false, error: 'connected_device_blocks_duty_recovery' }, { status: 409 });
        }
        const result = await persistVehicleDutyCommand(this.state.storage, command, actor, { projectAvailability: true, recoveryAudit: audit });
        return Response.json(result, { status: result.ok ? 200 : 409 });
      });
      this.directOccupancyQueue = operation.catch(() => {});
      return operation;
    }
    if (request.method === 'POST' && url.pathname === '/vehicle-duty-state') {
      if (this.env?.COMPANY_VEHICLE_OPERATIONS_ENABLED !== '1') return Response.json({ ok: false, error: 'vehicle_operations_disabled' }, { status: 503 });
      const input = await request.json();
      const operation = this.directOccupancyQueue.then(async () => {
        if (!this.capacityScopeAllowed(input)) return Response.json({ ok: false, error: 'duty_scope_mismatch' }, { status: 403 });
        const stored = await this.state.storage.get(VEHICLE_DUTY_STATE_KEY);
        if (stored && (stored.tenant_id !== input.tenant_id || stored.company_id !== input.company_id)) return Response.json({ ok: false, error: 'duty_scope_mismatch' }, { status: 403 });
        return Response.json({ ok: true, version: stored?.version ?? 0, duties: (stored?.duties || []).filter(row => row.driver_id === input.driver_id) });
      });
      this.directOccupancyQueue = operation.catch(() => {});
      return operation;
    }
    if (request.method === 'POST' && url.pathname === '/vehicle-duty') {
      if (this.env?.COMPANY_VEHICLE_OPERATIONS_ENABLED !== '1') return Response.json({ ok: false, error: 'vehicle_operations_disabled' }, { status: 503 });
      const input = await request.json();
      const operation = this.directOccupancyQueue.then(async () => {
        if (!this.capacityScopeAllowed(input)) return Response.json({ ok: false, error: 'duty_scope_mismatch' }, { status: 403 });
        if (['end', 'pause'].includes(input.action)) {
          const matchesDuty = row => row.driver_id === input.actor?.driver_id || row.vehicle_id === input.vehicle_id;
          // Direct holds exist until STOP and do not carry an `active` field.
          // Reservation claims also block handover while reserved or overdue.
          const busy = Object.values(this.directOccupancy).some(matchesDuty)
            || Object.values(this.capacity.claims || {}).some(row => matchesDuty(row)
              && (row.active === true || row.end_ms > nowMs
                || overdueCapacityHold(row, nowMs, this.capacity.owners?.[row.owner_id])));
          if (busy) return Response.json({ ok: false, error: 'active_ride_blocks_duty_change' }, { status: 409 });
        }
        const result = await persistVehicleDutyCommand(this.state.storage, input, input.actor, { projectAvailability: true });
        return Response.json(result, { status: result.ok ? 200 : 409 });
      });
      this.directOccupancyQueue = operation.catch(() => {});
      return operation;
    }
    if (request.method === 'POST' && url.pathname === '/vehicle-duty-history') {
      if (this.env?.COMPANY_VEHICLE_OPERATIONS_ENABLED !== '1') return Response.json({ ok: false, error: 'vehicle_operations_disabled' }, { status: 503 });
      const input = await request.json();
      const operation = this.directOccupancyQueue.then(async () => {
        if (!this.capacityScopeAllowed(input)) return Response.json({ ok: false, error: 'duty_scope_mismatch' }, { status: 403 });
        const result = await readVehicleDutyHistory(this.state.storage, input, input.driver_id, { limit: input.limit, cursor: input.cursor });
        return Response.json(result, { status: result.ok ? 200 : 409 });
      });
      this.directOccupancyQueue = operation.catch(() => {});
      return operation;
    }
    if (request.method === 'POST' && url.pathname === '/capacity') {
      const input = await request.json();
      const operation = this.directOccupancyQueue.then(async () => {
        if (!this.capacityScopeAllowed(input)) return Response.json({ ok: false, error: 'capacity_scope_conflict' }, { status: 409 });
        await this.hydrateCapacity({ owner: [input.owner_id] }, input);
        await this.expireOffers(Date.now());
        if (String(this.env?.CAPACITY_BASELINE_REQUIRED) === '1' && !this.capacity.baseline
          && ['reserve', 'activate'].includes(input.action)) {
          return Response.json({ ok: false, error: 'capacity_baseline_required' }, { status: 503 });
        }
        const amended = preemptOwnerAmendments(this.capacity, input, Date.now());
        const offer = Object.values(amended.offers || {}).find(row => row.owner_id === input.owner_id
          && ['offered', 'received', 'committing', ...(input.action === 'release' ? ['committed'] : [])].includes(row.state));
        if (offer && ['reserve', 'activate'].includes(input.action)) {
          return Response.json({ ok: false, error: 'dispatch_offer_pending' }, { status: 409 });
        }
        if (offer && input.action === 'confirm' && (offer.state !== 'committing' || !Array.isArray(input.canonical_claims))) {
          return Response.json({ ok: false, error: 'dispatch_commit_unconfirmed' }, { status: 409 });
        }
        const prepared = preemptPrerequisiteOffers(amended, input, Date.now());
        const decision = capacityClaimDecision(prepared, input, Object.values(this.directOccupancy));
        if (!decision.ok) return Response.json({ ok: false, error: decision.error,
          ...(decision.pending_version ? { pending_version: decision.pending_version } : {}) }, { status: decision.status });
        let next = { ...prepared, ...decision.ledger };
        if (input.action === 'confirm' && prepared.owners[input.owner_id]?.pending) {
          const resources = Object.values(prepared.claims).filter(claim => claim.owner_id === input.owner_id && claim.active);
          if (resources.length) next = queueConfirmedSuccessorChecks(next, Date.now(), { owner_id: input.owner_id, resources });
        }
        if (offer && input.action === 'confirm') next.offers = { ...next.offers,
          [offer.offer_id]: { ...offer, state: 'committed' } };
        if (offer && input.action === 'release') {
          const remains = Object.values(next.claims).some(claim => claim.owner_id === offer.owner_id && claim.offer_id === offer.offer_id);
          if (!remains) next.offers = { ...next.offers,
            [offer.offer_id]: { ...offer, state: 'cancelled', reason: 'canonical_release', ended_at_ms: Date.now() } };
        }
        await this.writeCapacity(next, input);
        return Response.json({ ok: true, committed: true });
      });
      this.directOccupancyQueue = operation.catch(() => {});
      return operation;
    }
    if (request.method === 'POST' && url.pathname === '/capacity-baseline') {
      const input = await request.json();
      const operation = this.directOccupancyQueue.then(async () => {
        if (!this.capacityScopeAllowed(input)) return Response.json({ ok: false, error: 'capacity_scope_conflict' }, { status: 409 });
        const registrationId = input.new_company_registration;
        if (registrationId !== undefined) {
          if (typeof registrationId !== 'string' || !/^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/.test(registrationId)
            || input.inventory_verified !== true || !Array.isArray(input.bookings) || input.bookings.length) {
            return Response.json({ ok: false, error: 'new_company_capacity_identity_invalid' }, { status: 400 });
          }
          if (this.capacity.baseline?.registration_id !== registrationId) {
            if (this.capacity.baseline || await this.state.storage.get(CAPACITY_STORAGE_KEY)
              || Object.keys(this.directOccupancy).length || !this.state.storage.list
              || (await this.state.storage.list({ prefix: 'capacity_archive_v1:', limit: 1 })).size) {
              return Response.json({ ok: false, error: 'new_company_capacity_existing_history' }, { status: 409 });
            }
          }
        }
        if (this.capacity.baseline) {
          if (this.capacity.baseline.tenant_id !== input.tenant_id || this.capacity.baseline.company_id !== input.company_id) {
            return Response.json({ ok: false, error: 'capacity_scope_conflict' }, { status: 409 });
          }
          // Exact new-company registration retries certify the original empty
          // initialization only; they must not replay or clear later bookings.
          if (registrationId !== undefined) return Response.json({ ok: true, committed: true, already_initialized: true });
        }
        await this.hydrateCapacity({ owner: (Array.isArray(input.bookings) ? input.bookings.slice(0, 5000) : []).map(row => row?.owner_id) }, input);
        const decision = capacityBaselineDecision(this.capacity, input);
        if (!decision.ok) return Response.json({ ok: false, error: decision.error }, { status: decision.status });
        const initialized = Boolean(this.capacity.baseline);
        if (initialized && JSON.stringify(decision.ledger) === JSON.stringify(this.capacity)) {
          return Response.json({ ok: true, committed: true, already_initialized: true, revalidated: true });
        }
        const next = { ...this.capacity, ...decision.ledger, baseline: this.capacity.baseline || {
          tenant_id: input.tenant_id, company_id: input.company_id,
          initialized_at: new Date(nowMs).toISOString(), inventory_digest: input.inventory_digest || null,
          ...(registrationId ? { registration_id: registrationId, source: 'new_company_registration' } : {}) } };
        await this.writeCapacity(next, input);
        return Response.json({ ok: true, committed: true, ...(initialized ? { already_initialized: true, revalidated: true } : {}) });
      });
      this.directOccupancyQueue = operation.catch(() => {});
      return operation;
    }
    if (request.method === 'POST' && url.pathname === '/dispatch-search') {
      const input = await request.json();
      const operation = this.directOccupancyQueue.then(async () => {
        if (!this.capacityScopeAllowed(input)) return Response.json({ ok: false, error: 'capacity_scope_conflict' }, { status: 409 });
        await this.hydrateCapacity({ owner: [input.owner_id], event: [`search:${input.owner_id}:${input.version}`] }, input);
        if (!this.capacity.baseline || this.capacity.baseline.tenant_id !== input.tenant_id
          || this.capacity.baseline.company_id !== input.company_id) {
          return Response.json({ ok: false, error: 'capacity_baseline_required' }, { status: 503 });
        }
        const decision = dispatchSearchDecision(this.capacity, {
          tenant_id: input.tenant_id, company_id: input.company_id, owner_id: input.owner_id, version: input.version,
          ...(input.amendment ? { amendment: true, base_version: input.base_version, retained_claims: input.retained_claims } : {}),
        }, Date.now());
        if (!decision.ok) return Response.json({ ok: false, error: decision.error }, { status: decision.status });
        await this.writeCapacity(decision.ledger, input);
        return Response.json({ ok: true, committed: true, search_id: decision.event.event_id });
      });
      this.directOccupancyQueue = operation.catch(() => {});
      return operation;
    }
    if (request.method === 'POST' && url.pathname === '/dispatch-device') {
      const input = await request.json();
      const operation = this.directOccupancyQueue.then(async () => {
        if (!this.capacityScopeAllowed(input)) return Response.json({ ok: false, error: 'capacity_scope_conflict' }, { status: 409 });
        if (input.vehicle_device_id) {
          if (this.env?.COMPANY_VEHICLE_OPERATIONS_ENABLED !== '1'
            || !/^[a-zA-Z0-9_.-]{1,96}$/.test(input.vehicle_device_id)) return Response.json({ ok: false, error: 'vehicle_device_auth_required' }, { status: 403 });
          const device = await this.state.storage.get(`vehicle_device_v1:${input.vehicle_device_id}`);
          if (!device || device.revoked || device.expires_at_ms <= Date.now()) return Response.json({ ok: false, error: 'vehicle_device_auth_required' }, { status: 403 });
        }
        const changed = updateDispatchDevice(this.dispatchDevices, input, Date.now());
        if (!changed.ok) return Response.json(changed, { status: changed.status });
        await this.state.storage.put(DISPATCH_DEVICES_KEY, changed.store);
        this.dispatchDevices = changed.store;
        await this.expireOffers(Date.now());
        return Response.json({ ok: true, dispatch_device_contract_version: 1 });
      });
      this.directOccupancyQueue = operation.catch(() => {});
      return operation;
    }
    if (request.method === 'POST' && url.pathname === '/dispatch-offer') {
      const input = await request.json();
      const operation = this.directOccupancyQueue.then(async () => {
        if (!this.capacityScopeAllowed(input)) return Response.json({ ok: false, error: 'capacity_scope_conflict' }, { status: 409 });
        await this.hydrateCapacity({ owner: [input.owner_id], offer: [input.offer_id] }, input);
        if (String(this.env?.CAPACITY_BASELINE_REQUIRED) === '1' && !this.capacity.baseline) {
          return Response.json({ ok: false, error: 'capacity_baseline_required' }, { status: 503 });
        }
        await this.expireOffers(Date.now());
        if (input.human_acceptance_required === true && this.env?.COMPANY_VEHICLE_OPERATIONS_ENABLED !== '1') return Response.json({ ok: false, error: 'vehicle_operations_disabled' }, { status: 503 });
        if (input.action === 'accept') {
          if (this.env?.COMPANY_VEHICLE_OPERATIONS_ENABLED !== '1') return Response.json({ ok: false, error: 'vehicle_operations_disabled' }, { status: 503 });
          const duty = await this.state.storage.get(VEHICLE_DUTY_STATE_KEY);
          const owned = dutyForRideExecution(duty, input, input.vehicle_id);
          if (await this.state.storage.get(VEHICLE_DUTY_PROJECTION_KEY)) return Response.json({ ok: false, error: 'active_duty_required' }, { status: 409 });
          const personal = !owned.ok && personalDriverExecutionV1({input,devices:this.dispatchDevices,duty,
            offer:this.capacity.offers?.[input.offer_id],nowMs:Date.now()});
          if (!owned.ok && !personal) return Response.json({ ok: false, error: 'active_duty_required' }, { status: 409 });
          input.execution_identity = owned.ok ? owned.execution_identity : personal;
        }
        const decision = dispatchOfferDecision(this.capacity, input, { nowMs: Date.now(),
          directRides: Object.values(this.directOccupancy), driverPosition: this.drivers[input.driver_id],
          dispatchDevices: this.dispatchDevices, drivers: this.drivers });
        if (!decision.ok) return Response.json({ ok: false, error: decision.error }, { status: decision.status });
        await this.writeCapacity(decision.ledger, input);
        return Response.json({ ok: true, committed: true, offer: decision.offer });
      });
      this.directOccupancyQueue = operation.catch(() => {});
      return operation;
    }
    if (request.method === 'GET' && url.pathname === '/driver-offers') {
      const input = { tenant_id: url.searchParams.get('tenant_id'), company_id: url.searchParams.get('company_id') };
      const operation = this.directOccupancyQueue.then(async () => {
        if (!this.capacityScopeAllowed(input)) return Response.json({ ok: false, error: 'capacity_scope_conflict' }, { status: 409 });
        await this.expireOffers(Date.now());
        const driverId = url.searchParams.get('driver_id');
        const deviceKey = url.searchParams.get('device_key');
        if (!deviceKey || !driverDispatchDevices(this.dispatchDevices, input, driverId, Date.now(), deviceKey).length) {
          return Response.json({ ok: false, error: 'dispatch_device_unavailable' }, { status: 409 });
        }
        const offers = Object.values(this.capacity.offers || {}).filter(offer => dispatchOfferResources(offer).some(resource => resource.driver_id === driverId)
          && offer.tenant_id === input.tenant_id && offer.company_id === input.company_id
          && ['offered', 'received', 'committing'].includes(offer.state)).slice(0, 8).map(offer => ({
          offer_id: offer.offer_id, owner_id: offer.owner_id, version: offer.version,
          vehicle_id: dispatchOfferResources(offer).find(resource => resource.driver_id === driverId).vehicle_id, ack_deadline_ms: offer.ack_deadline_ms, state: offer.state,
          ...(offer.human_acceptance_required === true ? { human_acceptance_required: true,
            ...(offer.response_starts_on_display === true ? { response_starts_on_display: true,
              response_timeout_ms: offer.ack_timeout_ms,
              displayed_at_ms: offer.receipts?.[driverId]?.displayed_at_ms ?? null } : {}),
            human_accepted: offer.receipts?.[driverId]?.accepted === true } : {}),
        }));
        return Response.json({ ok: true, offers });
      });
      this.directOccupancyQueue = operation.catch(() => {});
      return operation;
    }
    if (url.pathname === '/dispatch-events') {
      if (request.method === 'GET') {
        await this.directOccupancyQueue;
        const input = { tenant_id: url.searchParams.get('tenant_id'), company_id: url.searchParams.get('company_id') };
        if (!this.capacityScopeAllowed(input)) return Response.json({ ok: false, error: 'capacity_scope_conflict' }, { status: 409 });
        return Response.json({ ok: true, events: Object.values(this.capacity.dispatch_events || {})
          .filter(event => event.state === 'pending' && event.tenant_id === input.tenant_id && event.company_id === input.company_id)
          .map(event => ({ ...event, offer_state: this.capacity.offers?.[event.offer_id]?.state })) });
      }
      if (request.method === 'POST') {
        const input = await request.json();
        const operation = this.directOccupancyQueue.then(async () => {
          if (!this.capacityScopeAllowed(input)) return Response.json({ ok: false, error: 'capacity_scope_conflict' }, { status: 409 });
          await this.hydrateCapacity({ event: [input.event_id] }, input);
          const decision = acknowledgeDispatchEvent(this.capacity, input);
          if (!decision.ok) return Response.json({ ok: false, error: decision.error }, { status: decision.status });
          await this.writeCapacity(decision.ledger, input);
          return Response.json({ ok: true, committed: true });
        });
        this.directOccupancyQueue = operation.catch(() => {});
        return operation;
      }
    }
    if (request.method === "POST" && url.pathname === "/direct-occupancy") {
      const event = await request.json();
      const operation = this.directOccupancyQueue.then(async () => {
      if (!this.capacityScopeAllowed(event)) return Response.json({ ok: false, error: 'capacity_scope_conflict' }, { status: 409 });
      await this.expireOffers(Date.now());
      const key = String(event.direct_ride_key || event.trip_id || "").trim();
      if (!key || key.length > 200 || !event.tenant_id || !event.company_id
        || !event.driver_id || !event.vehicle_id || !["start", "stop"].includes(event.phase)) {
        return Response.json({ ok: false, error: "direct_occupancy_invalid" }, { status: 400 });
      }
      const existing = this.directOccupancy[key];
      if (existing && ["tenant_id", "company_id", "driver_id", "vehicle_id"].some(field =>
        existing[field] !== event[field])) {
        return Response.json({ ok: false, error: "direct_occupancy_conflict" }, { status: 409 });
      }
      const stoppedKey = `direct_occupancy_stopped:${key}`;
      const next = { ...this.directOccupancy };
      if (event.phase === "start") {
        if (String(this.env?.CAPACITY_BASELINE_REQUIRED) === '1' && !this.capacity.baseline) {
          return Response.json({ ok: false, error: 'capacity_baseline_required' }, { status: 503 });
        }
        // STOP wins over a delayed/replayed START, including after Room restart.
        if (await this.state.storage.get(stoppedKey)) {
          return Response.json({ ok: true, applied: false, reason: "already_stopped" });
        }
        const preempted = preemptDispatchOffers(this.capacity, event, Date.now());
        if (!existing && (Object.values(this.directOccupancy).some(ride => ride.tenant_id === event.tenant_id
          && ride.company_id === event.company_id && sameCapacityResource(ride, event))
          || Object.values(preempted.claims).some(claim => claim.tenant_id === event.tenant_id
            && claim.company_id === event.company_id && (claim.active || claim.end_ms > nowMs || overdueCapacityHold(claim, nowMs, preempted.owners[claim.owner_id])) && sameCapacityResource(claim, event)))) {
          return Response.json({ ok: false, error: 'capacity_conflict' }, { status: 409 });
        }
        next[key] = existing || { tenant_id: event.tenant_id, company_id: event.company_id,
          driver_id: event.driver_id, vehicle_id: event.vehicle_id, direct_ride_key: key,
          trip_id: event.trip_id || null, started_at: new Date(nowMs).toISOString() };
        // Capacity revocation, durable redispatch events and physical street
        // occupancy are committed in one key, including on Room restart.
        await this.writeCapacity({ ...preempted, direct_holds: next }, event);
        return Response.json({ ok: true, applied: true });
      } else {
        await this.state.storage.put(stoppedKey, { stopped_at: new Date(nowMs).toISOString() });
        delete next[key];
      }
      // Publish in memory only after durable confirmation; a failed write retries.
      await this.writeCapacity({ ...this.capacity, direct_holds: next }, event);
      return Response.json({ ok: true, applied: true });
      });
      this.directOccupancyQueue = operation.catch(() => {});
      return operation;
    }
    if (request.method === "POST" && url.pathname === "/location") {
      const input = await request.json();
      const operation = this.directOccupancyQueue.then(async () => {
      const nowMs = Date.now();
      if (!this.capacityScopeAllowed(input) || this.drivers[input.driver_id] &&
        (this.drivers[input.driver_id].tenant_id !== input.tenant_id || this.drivers[input.driver_id].company_id !== input.company_id)) {
        return Response.json({ ok: false, error: 'location_scope_conflict' }, { status: 409 });
      }
      // Internal presence proof comes only from the authenticated session in
      // handleDriverPresenceLocation. Fence duty changes in this same Room turn.
      if (input.vehicle_device_presence != null) {
        const proof = input.vehicle_device_presence;
        const device = await vehicleDeviceCommand(this.state.storage, {
          tenant_id: input.tenant_id, company_id: input.company_id,
          action: "authenticate", device_id: proof.device_id,
          device_token_hash: proof.device_token_hash
        }, nowMs);
        if (!device.ok || device.vehicle_id !== input.vehicle_id)
          return Response.json({ ok: false, error: "vehicle_device_auth_required" }, { status: 403 });
        const duty = await this.state.storage.get(VEHICLE_DUTY_STATE_KEY);
        const owned = dutyForRideExecution(duty, input, device.vehicle_id);
        const activeDuty = duty?.duties?.find(row => row.duty_id === owned.execution_identity?.duty_id);
        if (await this.state.storage.get(VEHICLE_DUTY_PROJECTION_KEY) || !owned.ok
          || activeDuty?.vehicle_device_id !== device.device_id)
          return Response.json({ ok: false, error: "active_duty_required" }, { status: 409 });
      }
      const previous = this.drivers[input.driver_id];
      if (locationOwnerRetired(previous, input.publication_owner, nowMs)) {
        return Response.json({ ok: false, error: 'location_owner_retired' }, { status: 409 });
      }
      if (boundLocationOwner(previous?.publication_owner, nowMs) && !boundLocationOwner(input.publication_owner, nowMs)) {
        return Response.json({ ok: false, error: 'location_owner_unbound' }, { status: 409 });
      }
      // Validate in the same Room turn as the hot-state update. A prior Worker
      // lookup would race reassignment/START. Never infer another leg here.
      if (input.tracking_context == null && previous?.tracking_context && boundLocationOwner(input.publication_owner, nowMs) &&
        sameLocationOwner(previous.publication_owner, input.publication_owner)) {
        const storedContext = previous.tracking_context;
        const grant = await readStoredCustomerGrant(this.state.storage, this.grants,
          grantKey(storedContext.booking_id, storedContext.operational_leg), this.grants.scope || input);
        const valid = matchesTrackingScope(input, storedContext, grant) && grant.position_allowed === true &&
          (storedContext.phase === 'en_route_pickup'
            ? ['en_route_pickup', 'arrived_pickup'].includes(grant.tracking_phase)
            : storedContext.phase === 'in_progress' && grant.tracking_phase === 'in_progress' &&
              storedContext.session_id && storedContext.session_id === grant.session_id);
        // Booking START can precede the first foreground paid ping. Advance
        // only the prior exact-owner pickup binding to its authoritative paid
        // session; another assignment, vehicle or session cannot borrow it.
        const startedPickup = matchesTrackingScope(input, storedContext, grant) && grant.position_allowed === true &&
          storedContext.phase === 'en_route_pickup' && grant.tracking_phase === 'in_progress' &&
          typeof grant.session_id === 'string' && grant.session_id.length > 0 &&
          (!storedContext.session_id || storedContext.session_id === grant.session_id) &&
          grant.vehicle?.vehicle_id && previous.vehicle_id === grant.vehicle.vehicle_id &&
          input.vehicle_id === grant.vehicle.vehicle_id;
        if (valid || startedPickup) {
          input.tracking_context = startedPickup
            ? { ...storedContext, phase: 'in_progress', session_id: grant.session_id } : storedContext;
          input.tracking_status = input.tracking_context.phase === 'in_progress' ? 'active' : 'en_route_pickup';
          input.availability_status = 'on_trip';
        }
      }
      const context = input.tracking_context;
      if (input.presence_restricted_reason && !context) {
        return Response.json({ ok: true, applied: false, reason: input.presence_restricted_reason });
      }
      if (context != null && !["en_route_pickup", "in_progress"].includes(context.phase)) {
        return Response.json({ok: false, error: "location_context_invalid"}, {status: 409});
      }
      if (context?.phase === "en_route_pickup") {
        const grant = await readStoredCustomerGrant(this.state.storage, this.grants,
          grantKey(context.booking_id, context.operational_leg), this.grants.scope || input);
        const valid = matchesTrackingScope(input, context, grant) &&
          grant.position_allowed === true && ["en_route_pickup", "arrived_pickup"].includes(grant.tracking_phase);
        if (!valid) return Response.json({ok: false, error: "presence_context_invalid"}, {status: 409});
        const otherTrip = Object.values(this.grants.grants || {}).some(g =>
          g.driver_id === input.driver_id && g.tracking_phase === "in_progress" &&
          !g.leg_scope_retired && g.position_allowed === true);
        if (otherTrip) return Response.json({ok: false, error: "presence_context_invalid"}, {status: 409});
      }
      // Bound trip GPS uses the same authoritative grant as pre-START GPS.
      // Reject revoked scope before any hot-state/legacy GPS write, allowing
      // the existing Driver ping caller to release its location service.
      if (context?.phase === "in_progress") {
        const grant = await readStoredCustomerGrant(this.state.storage, this.grants,
          grantKey(context.booking_id, context.operational_leg), this.grants.scope || input);
        const valid = matchesTrackingScope(input, context, grant) &&
          grant.session_id === context.session_id && context.session_id &&
          ["assigned", "en_route_pickup", "arrived_pickup", "in_progress"].includes(grant.tracking_phase);
        if (!valid) return Response.json({ok: false, error: "trip_context_invalid"}, {status: 409});
      }
      // The update function only touches this driver. Avoid copying/encoding
      // the entire company for one GPS sample; snapshots still use all rows.
      const mergedHits = previous ? { [input.driver_id]: { ...previous,
        ...(this.hits.has(input.driver_id) ? { recent_hits: this.hits.get(input.driver_id) } : {}) } } : {};
      const applied = applyLocationUpdate(mergedHits, input, nowMs);
      if (applied.result.applied) {
        const retired = nextRetiredLocationOwners(previous, input.publication_owner, nowMs);
        if (!retired) return Response.json({ ok: false, error: 'location_owner_limit' }, { status: 429 });
        if (retired.length) applied.drivers[input.driver_id].retired_publications = retired;
        else delete applied.drivers[input.driver_id].retired_publications;
      }
      const nextDrivers = persistable(applied.drivers);
      for (const [id, row] of Object.entries(applied.drivers)) {
        if (row?.recent_hits) this.hits.set(id, row.recent_hits);
      }
      if (applied.result.applied || applied.result.liveness_updated) {
        this.drivers = await this.driverRows.write(input.driver_id, nextDrivers[input.driver_id]);
        if (this.spatialIndex) this.spatialIndex.update(nextDrivers[input.driver_id], nowMs);
      }
      await this.expireOffers(nowMs);
      const status = applied.result.status || 200;
      return Response.json(applied.result, { status });
      });
      this.directOccupancyQueue = operation.catch(() => {});
      return operation;
    }
    if (request.method === "POST" && url.pathname === "/location-withdraw") {
      const input = await request.json();
      const operation = this.directOccupancyQueue.then(async () => {
        const nowMs = Date.now();
        if (!input.driver_id || !input.tenant_id || !input.company_id || !boundLocationOwner(input.publication_owner, nowMs)) {
          return Response.json({ ok: false, error: 'location_owner_invalid' }, { status: 400 });
        }
        const previous = this.drivers[input.driver_id];
        if (!this.capacityScopeAllowed(input) || previous &&
          (previous.tenant_id !== input.tenant_id || previous.company_id !== input.company_id)) {
          return Response.json({ ok: false, error: 'location_scope_conflict' }, { status: 409 });
        }
        if (previous && !boundLocationOwner(previous.publication_owner, nowMs)) {
          return Response.json({ ok: true, cleared: false, reason: 'owner_unbound' });
        }
        if (locationOwnerRetired(previous, input.publication_owner, nowMs)) {
          return Response.json({ ok: true, cleared: false, reason: 'already_withdrawn' });
        }
        const matches = sameLocationOwner(previous?.publication_owner, input.publication_owner);
        const retired = retainedLocationOwners(previous, nowMs);
        if (previous && !matches) {
          if (retired.length >= LOCATION_RETIRED_OWNER_LIMIT) {
            return Response.json({ ok: false, error: 'location_owner_limit' }, { status: 429 });
          }
          retired.push(input.publication_owner);
        }
        // One atomic DO storage write retains the withdrawal fence and removes
        // visibility. No GPS KV write, separate capacity/assignment/ride deletion.
        let row = previous ? { ...previous, retired_publications: retired } : {
          tenant_id: input.tenant_id, company_id: input.company_id, driver_id: input.driver_id,
          publication_owner: input.publication_owner, retired_publications: [],
        };
        if (!previous || matches) row = {
          tenant_id: input.tenant_id, company_id: input.company_id, driver_id: input.driver_id,
          publication_owner: input.publication_owner, retired_publications: retired, location_withdrawn: true,
        };
        this.drivers = await this.driverRows.write(input.driver_id, persistable({ [input.driver_id]: row })[input.driver_id]);
        if (this.spatialIndex) this.spatialIndex.update(row, nowMs);
        if (matches) this.hits.delete(input.driver_id);
        await this.expireOffers(nowMs);
        return Response.json({ ok: true, cleared: Boolean(matches),
          reason: matches ? 'withdrawn' : previous ? 'owner_mismatch' : 'location_absent' });
      });
      this.directOccupancyQueue = operation.catch(() => {});
      return operation;
    }
    if (request.method === "POST" && url.pathname === "/clear") {
      const input = await request.json();
      const operation = this.directOccupancyQueue.then(async () => {
      const previous = this.drivers[input.driver_id];
      if (input.publication_owner && (!previous?.publication_owner || !sameLocationOwner(previous.publication_owner, input.publication_owner))
        || previous?.publication_owner && !input.publication_owner) {
        return Response.json({ ok: true, cleared: false, reason: previous?.publication_owner ? 'owner_mismatch' : 'owner_unbound' });
      }
      if (previous && input.tenant_id && (previous.tenant_id !== input.tenant_id || previous.company_id !== input.company_id)) {
        return Response.json({ ok: false, error: 'location_scope_conflict' }, { status: 409 });
      }
      if (boundLocationOwner(previous?.publication_owner, Date.now())) {
        // Bound publications are retired only by /location-withdraw. An older
        // tracking-session STOP has no right to remove a newer activation.
        return Response.json({ ok: true, cleared: false, reason: 'owner_unbound' });
      }
      this.drivers = await this.driverRows.write(String(input.driver_id || ""), null);
      if (this.spatialIndex) this.spatialIndex.remove(String(input.driver_id || ''));
      this.hits.delete(String(input.driver_id || ""));
      await this.expireOffers(Date.now());
      return Response.json({ ok: true, cleared: true });
      });
      this.directOccupancyQueue = operation.catch(() => {});
      return operation;
    }
    if (request.method === "POST" && url.pathname === "/customer-grant") {
      const event = await request.json();
      const operation = this.directOccupancyQueue.then(async () => {
      if (!this.capacityScopeAllowed(event)) return Response.json({ ok: false, error: 'customer_grant_scope_conflict' }, { status: 409 });
      const previous = await hydrateCustomerGrantEvent(this.state.storage, this.grants, event, this.grants.scope || event);
      const applied = applyCustomerLifecycle(previous, event, Date.now());
      // A failed write must not become an in-memory confirmation on retry.
      if (applied.applied) {
        const stored = { ...applied.store, scope: this.grants.scope || {
          tenant_id: applied.grant.tenant_id, company_id: applied.grant.company_id } };
        this.grants = await writeCustomerGrantSnapshot(this.state.storage, stored, Date.now());
      }
      const grant = applied.grant || null;
      return Response.json({
        ok: true,
        applied: applied.applied,
        confirmed: applied.confirmed === true,
        reason: applied.reason,
        // Renewal cannot manufacture access when no usable token survived.
        ...(event.kind === "renew" ? { renewal_access_retained: Boolean(grant &&
          [grant.access_token_hash, ...(grant.access_token_hashes || [])].some(hash => hash &&
            customerAccessAllowed(grant, { tenant_id: grant.tenant_id, company_id: grant.company_id,
              booking_id: grant.booking_id, operational_leg: grant.operational_leg,
              customer_id: grant.customer_id, access_token_hash: hash }).ok)) } : {}),
        lifecycle_seq: grant?.lifecycle_seq ?? null,
        assignment_version: grant?.assignment_version ?? null,
        tracking_phase: grant?.tracking_phase ?? null,
        position_allowed: grant?.position_allowed === true,
      });
      });
      this.directOccupancyQueue = operation.catch(() => {});
      return operation;
    }
    if (request.method === "GET" && url.pathname === "/customer-live") {
      const operation = this.directOccupancyQueue.then(async () => {
      const snapshotNowMs = Date.now();
      const key = grantKey(url.searchParams.get("booking_id"), url.searchParams.get("operational_leg"));
      const grant = await readStoredCustomerGrant(this.state.storage, this.grants, key, this.grants.scope || {
        tenant_id: url.searchParams.get("tenant_id"), company_id: url.searchParams.get("company_id") });
      const access = customerAccessAllowed(grant, {
        tenant_id: url.searchParams.get("tenant_id"),
        company_id: url.searchParams.get("company_id"),
        booking_id: url.searchParams.get("booking_id"),
        operational_leg: url.searchParams.get("operational_leg"),
        customer_id: url.searchParams.get("customer_id"),
        access_token_hash: url.searchParams.get("access_token_hash"),
        assignment_version: url.searchParams.get("assignment_version"),
        session_id: url.searchParams.get("session_id"),
      });
      if (!access.ok) return Response.json({ ok: false, error: access.error }, { status: access.status });
      if(this.env.RELIABLE_CHOICE_ENABLED==='1'){
        const rights=await readCompanyOperationDecision(this.env,{tenant_id:grant.tenant_id,company_id:grant.company_id},{operation:'customer_live_tracking'});
        if(rights.applicable!==true||rights.ok!==true)return Response.json({ok:false,error:'customer_tracking_not_allowed'},{status:403});
      }
      const live = projectCompanyLive(this.drivers[grant.driver_id] ? { [grant.driver_id]: this.drivers[grant.driver_id] } : {}, {
        tenantId: grant.tenant_id,
        companyId: grant.company_id,
        nowMs: snapshotNowMs,
        freshnessSeconds: url.searchParams.get("freshness_seconds"),
      });
      const driver = (live.drivers || []).find((row) => row.driver_id === grant.driver_id) || null;
      const stored = this.drivers[grant.driver_id];
      const context = stored?.tracking_context;
      // Generic fleet presence remains usable by company dispatch, but cannot
      // authorize customer GPS, even when exactly one leg happens to be active.
      const matches = matchesTrackingScope(stored, context, grant) &&
        grant.position_allowed === true &&
        ["en_route_pickup", "in_progress"].includes(context.phase) &&
        (context.phase === grant.tracking_phase || context.phase === "en_route_pickup" && grant.tracking_phase === "arrived_pickup") &&
        (context.phase === "in_progress"
          ? Boolean(context.session_id && context.session_id === grant.session_id)
          : !context.session_id || context.session_id === grant.session_id);
      const snapshot = projectCustomerSnapshot({ grant, driver: matches ? driver : null, nowMs: snapshotNowMs, eta: null, route: null });
      return Response.json(snapshot);
      });
      this.directOccupancyQueue = operation.catch(() => {});
      return operation;
    }
    if (request.method === "GET" && url.pathname === "/customer-grant") {
      const operation = this.directOccupancyQueue.then(async () => {
      const key = grantKey(url.searchParams.get("booking_id"), url.searchParams.get("operational_leg"));
      let grant = await readStoredCustomerGrant(this.state.storage, this.grants, key, this.grants.scope);
      // Legacy session starts omit a leg ID. Resolve only one live grant for
      // this booking and authenticated driver; never guess between siblings.
      const driverId = url.searchParams.get("active_driver_id");
      if (grant?.leg_scope_retired && driverId && !url.searchParams.get("operational_leg")) {
        const candidates = Object.values(this.grants.grants || {}).filter(row =>
          row.booking_id === url.searchParams.get("booking_id") && row.driver_id === driverId &&
          row.position_allowed === true && ["en_route_pickup", "in_progress"].includes(row.tracking_phase));
        grant = candidates.length === 1 ? candidates[0] : null;
      }
      if (!grant) return Response.json({ ok: false, error: "not_found" }, { status: 404 });
      return Response.json({ ok: true, grant });
      });
      this.directOccupancyQueue = operation.catch(() => {});
      return operation;
    }
    if (request.method === "GET" && url.pathname === "/live") {
      const trialMode = this.env?.STAGING_TRIAL_MODE === '1';
      const trialEnvironment = this.env?.STAGING_TRIAL_ENVIRONMENT === 'staging';
      if (trialMode !== trialEnvironment) {
        return Response.json({ok:false,error:'staging_trial_configuration_required'}, {status:503});
      }
      const expiry = this.directOccupancyQueue.then(async () => {
        if (trialMode) {
          const readAtMs = Date.now();
          const projected = queueConfirmedSuccessorChecks(
            revalidateDispatchOffers(this.capacity, this.drivers, readAtMs, this.dispatchDevices), readAtMs);
          if (projected !== this.capacity) {
            return {ok:false,error:'staging_trial_live_state_requires_maintenance'};
          }
          return {ok:true};
        }
        await this.expireOffers(Date.now());
        // Retention runs on company discovery, never on a driver's GPS write.
        // Session-bound publication fences survive until their expiry.
        if (this.env.ENTERPRISE_DRIVER_STATE_RETENTION_ENABLED === '1' && nowMs - (this.driverGcAt || 0) >= 3600000) {
          const pruned = await this.driverRows.prune(row => {
            const seen = Date.parse(row?.last_seen_at || row?.received_at || '');
            return Number.isFinite(seen) && nowMs - seen >= 86400000
              && !boundLocationOwner(row?.publication_owner, nowMs) && retainedLocationOwners(row, nowMs).length === 0;
          });
          this.drivers = pruned.rows;
          for (const driverId of pruned.deleted) { this.hits.delete(driverId); if (this.spatialIndex) this.spatialIndex.remove(driverId); }
          if (pruned.removed < 127) this.driverGcAt = nowMs;
        }
      });
      this.directOccupancyQueue = expiry.catch(() => {});
      const liveRead = await expiry;
      if (liveRead?.ok === false) return Response.json(liveRead, {status:503});
      const snapshotNowMs = trialMode ? Date.now() : nowMs;
      const freshness = url.searchParams.get("freshness_seconds");
      const body = projectCompanyLive(this.drivers, {
        tenantId: url.searchParams.get("tenant_id") || "",
        companyId: url.searchParams.get("company_id") || "",
        nowMs: snapshotNowMs,
        freshnessSeconds: freshness,
        ...(url.searchParams.get('include_access_context')==='1'?{accessSessionForRow:(row,at)=>this.accessSessionForRow(row,at)}:{}),
      });
      let spatial = null;
      if (this.env.ENTERPRISE_SAFE_SEARCH_ENABLED === '1' && url.searchParams.has('spatial_lat')
        && this.capacityScopeAllowed({ tenant_id: body.tenant_id, company_id: body.company_id })) {
        if (!this.spatialIndex) {
          this.spatialIndex = createActiveSpatialIndex(body);
          this.spatialIndex.rebuild(Object.values(this.drivers), snapshotNowMs);
        }
        const ordered = this.spatialIndex.ordered({ latitude: Number(url.searchParams.get('spatial_lat')),
          longitude: Number(url.searchParams.get('spatial_lon')) }, snapshotNowMs);
        spatial = { complete: ordered.complete, cells_visited: ordered.cells_visited,
          rows: ordered.rows.map(row => ({ driver_id: row.driver_id, vehicle_id: row.vehicle_id })) };
      }
      return Response.json({ ...body, dispatch_offer_contract_version: 1,
        ...(spatial ? { dispatch_spatial_order: spatial } : {}),
        dispatch_device_contract_version: 1,
        dispatch_devices: projectDispatchDevices(this.dispatchDevices, { tenant_id: body.tenant_id, company_id: body.company_id }, Date.now()),
        dispatch_offers: Object.values(this.capacity.offers || {}).filter(row => row.tenant_id === url.searchParams.get('tenant_id')
          && row.company_id === url.searchParams.get('company_id') && ['offered', 'received', 'committing'].includes(row.state)),
        capacity_contract_version: 1, capacity_baseline: this.capacity.baseline || null,
        capacity_reservations: Object.values(this.capacity.claims).filter(row => row.tenant_id === url.searchParams.get('tenant_id')
          && row.company_id === url.searchParams.get('company_id')).map(row => ({ ...row,
            capacity_version: this.capacity.owners[row.owner_id]?.version,
            completion_unconfirmed: overdueCapacityHold(row, snapshotNowMs, this.capacity.owners[row.owner_id]),
            reservation_expired: unstartedCapacityExpired(row, snapshotNowMs, this.capacity.owners[row.owner_id]),
          ...(row.offer_id ? { capacity_offer_state: this.capacity.offers?.[row.offer_id]?.owner_id === row.owner_id
            && this.capacity.offers[row.offer_id].tenant_id === row.tenant_id
            && this.capacity.offers[row.offer_id].company_id === row.company_id
            ? this.capacity.offers[row.offer_id].state : 'unresolved' } : {}),
            capacity_pending: this.capacity.owners[row.owner_id]?.pending === true })),
        active_direct_rides: Object.values(this.directOccupancy)
        .filter(row => row.tenant_id === url.searchParams.get("tenant_id")
          && row.company_id === url.searchParams.get("company_id")) });
    }
    return Response.json({ ok: false, error: "not_found" }, { status: 404 });
  }
}
