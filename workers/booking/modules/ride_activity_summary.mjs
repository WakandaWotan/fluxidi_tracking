/**
 * Per-tenant+company ride-activity summary.
 * Incremental upserts never mark history complete. A controlled backfill does.
 * First timestamps may move earlier. Totals never increment twice for one id.
 */
export const RIDE_ACTIVITY_KIND = "ride_activity:v1";

function text(value) {
  return value == null ? "" : String(value).trim();
}

function isoOrNull(value) {
  const raw = text(value);
  if (!raw) return null;
  const ms = Date.parse(raw);
  return Number.isFinite(ms) ? new Date(ms).toISOString() : null;
}

function uniqueIds(values = []) {
  return [...new Set((Array.isArray(values) ? values : []).map((id) => text(id)).filter(Boolean))];
}

export function rideActivitySummaryKey(tenantId, companyId) {
  const tenant = text(tenantId);
  const company = text(companyId);
  if (!tenant || !company) return "";
  return `tenant:${tenant}:company:${company}:ride_activity:v1`;
}

export function isExcludedRide(observation = {}) {
  if (observation?.is_demo === true || observation?.isDemo === true) return true;
  if (observation?.payment_demo_mode === true || observation?.paymentDemoMode === true) return true;
  if (observation?.billing_test_mode === true || observation?.billingTestMode === true) return true;
  if (observation?.allocator_probe === true || observation?.is_allocator_probe === true) return true;
  if (observation?.demo_seed === true || observation?.is_seed === true) return true;
  const type = text(observation?.booking_type || observation?.bookingType || observation?.kind).toLowerCase();
  return type === "test" || type === "demo" || type === "seed";
}

export function isCancelledRide(observation = {}) {
  const status = text(
    observation?.lifecycle_status || observation?.lifecycle || observation?.status,
  ).toLowerCase();
  return ["cancelled", "canceled", "no_show", "noshow", "no-show"].includes(status);
}

export function isAuthoritativeCompleted(observation = {}) {
  const status = text(
    observation?.lifecycle_status || observation?.lifecycle || observation?.status,
  ).toLowerCase();
  const completed = ["completed", "complete", "done", "finished", "finalized", "dropped_off", "dropped-off"]
    .includes(status);
  return completed && Boolean(isoOrNull(observation?.completed_at || observation?.completedAt || observation?.finished_at));
}

function createdAtOf(observation = {}) {
  return isoOrNull(
    observation.created_at
    || observation.createdAt
    || observation.started_at
    || observation.startedAt,
  );
}

function emptySummary(scope = {}) {
  return {
    kind: RIDE_ACTIVITY_KIND,
    tenant_id: text(scope.tenant_id || scope.tenantId) || null,
    company_id: text(scope.company_id || scope.companyId) || null,
    first_real_ride_id: null,
    first_real_ride_at: null,
    first_completed_ride_id: null,
    first_completed_ride_at: null,
    last_real_ride_id: null,
    last_real_ride_at: null,
    total_real_rides: 0,
    total_completed_rides: 0,
    created_ids: [],
    completed_ids: [],
    source_revision: 1,
    updated_at: null,
    history_complete: false,
  };
}

export function normalizeRideActivitySummary(raw = {}, scope = {}) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    return emptySummary(scope);
  }
  const createdIds = uniqueIds(raw.created_ids || raw.createdIds);
  const completedIds = uniqueIds(raw.completed_ids || raw.completedIds);
  const revision = Number(raw.source_revision ?? raw.sourceRevision);
  return {
    kind: RIDE_ACTIVITY_KIND,
    tenant_id: text(raw.tenant_id || raw.tenantId || scope.tenant_id) || null,
    company_id: text(raw.company_id || raw.companyId || scope.company_id) || null,
    first_real_ride_id: text(raw.first_real_ride_id || raw.firstRealRideId) || null,
    first_real_ride_at: isoOrNull(raw.first_real_ride_at || raw.firstRealRideAt),
    first_completed_ride_id: text(raw.first_completed_ride_id || raw.firstCompletedRideId) || null,
    first_completed_ride_at: isoOrNull(raw.first_completed_ride_at || raw.firstCompletedRideAt),
    last_real_ride_id: text(raw.last_real_ride_id || raw.lastRealRideId) || null,
    last_real_ride_at: isoOrNull(raw.last_real_ride_at || raw.lastRealRideAt),
    total_real_rides: createdIds.length,
    total_completed_rides: completedIds.length,
    created_ids: createdIds,
    completed_ids: completedIds,
    source_revision: Number.isInteger(revision) && revision >= 1 ? revision : 1,
    updated_at: isoOrNull(raw.updated_at || raw.updatedAt),
    history_complete: raw.history_complete === true || raw.historyComplete === true,
  };
}

function earlier(currentAt, currentId, nextAt, nextId) {
  if (!nextAt) return { at: currentAt || null, id: currentId || null };
  if (!currentAt || nextAt < currentAt) return { at: nextAt, id: nextId || null };
  return { at: currentAt, id: currentId || null };
}

function later(currentAt, currentId, nextAt, nextId) {
  if (!nextAt) return { at: currentAt || null, id: currentId || null };
  if (!currentAt || nextAt > currentAt) return { at: nextAt, id: nextId || null };
  return { at: currentAt, id: currentId || null };
}

export function applyRideActivityObservation(current, observation = {}, now = new Date()) {
  const scope = {
    tenant_id: observation.tenant_id || observation.tenantId || current?.tenant_id,
    company_id: observation.company_id || observation.companyId || current?.company_id,
  };
  const next = normalizeRideActivitySummary(current, scope);
  const bookingId = text(observation.booking_id || observation.bookingId || observation.id);
  const excludeReason = isExcludedRide(observation)
    ? "demo_or_test_booking"
    : (!bookingId ? "missing_booking_id" : null);
  if (excludeReason) {
    return { summary: next, changed: false, skipped: excludeReason };
  }
  const createdAt = createdAtOf(observation);
  const completedAt = isoOrNull(observation.completed_at || observation.completedAt || observation.finished_at);
  const cancelled = isCancelledRide(observation);
  const completed = isAuthoritativeCompleted(observation);
  let changed = false;

  if (createdAt && !cancelled) {
    if (!next.created_ids.includes(bookingId)) {
      next.created_ids.push(bookingId);
      changed = true;
    }
    const first = earlier(next.first_real_ride_at, next.first_real_ride_id, createdAt, bookingId);
    const last = later(next.last_real_ride_at, next.last_real_ride_id, createdAt, bookingId);
    if (first.at !== next.first_real_ride_at || first.id !== next.first_real_ride_id) {
      next.first_real_ride_at = first.at;
      next.first_real_ride_id = first.id;
      changed = true;
    }
    if (last.at !== next.last_real_ride_at || last.id !== next.last_real_ride_id) {
      next.last_real_ride_at = last.at;
      next.last_real_ride_id = last.id;
      changed = true;
    }
  }

  if (completed && completedAt) {
    if (!next.completed_ids.includes(bookingId)) {
      next.completed_ids.push(bookingId);
      changed = true;
    }
    const firstCompleted = earlier(
      next.first_completed_ride_at,
      next.first_completed_ride_id,
      completedAt,
      bookingId,
    );
    if (
      firstCompleted.at !== next.first_completed_ride_at
      || firstCompleted.id !== next.first_completed_ride_id
    ) {
      next.first_completed_ride_at = firstCompleted.at;
      next.first_completed_ride_id = firstCompleted.id;
      changed = true;
    }
  }

  next.total_real_rides = next.created_ids.length;
  next.total_completed_rides = next.completed_ids.length;
  next.kind = RIDE_ACTIVITY_KIND;
  if (changed) {
    next.source_revision = Math.max(1, Number(next.source_revision) || 1) + 1;
    next.updated_at = now instanceof Date ? now.toISOString() : isoOrNull(now) || new Date().toISOString();
  }
  return { summary: next, changed, skipped: null };
}

export function applyRideActivityObservations(current, observations = [], now = new Date()) {
  let summary = normalizeRideActivitySummary(current);
  let changed = false;
  const skipped = [];
  for (const observation of observations) {
    const result = applyRideActivityObservation(summary, observation, now);
    summary = result.summary;
    if (result.changed) changed = true;
    if (result.skipped) skipped.push({ booking_id: text(observation?.booking_id), reason: result.skipped });
  }
  return { summary, changed, skipped };
}

export function markRideActivityHistoryComplete(current, now = new Date()) {
  const next = normalizeRideActivitySummary(current);
  if (next.history_complete === true) {
    return { summary: next, changed: false };
  }
  next.history_complete = true;
  next.kind = RIDE_ACTIVITY_KIND;
  next.source_revision = Math.max(1, Number(next.source_revision) || 1) + 1;
  next.updated_at = now instanceof Date ? now.toISOString() : isoOrNull(now) || new Date().toISOString();
  return { summary: next, changed: true };
}

export function serializeRideActivitySummary(summary = {}) {
  const normalized = normalizeRideActivitySummary(summary);
  return {
    kind: RIDE_ACTIVITY_KIND,
    tenant_id: normalized.tenant_id,
    company_id: normalized.company_id,
    first_real_ride_id: normalized.first_real_ride_id,
    first_real_ride_at: normalized.first_real_ride_at,
    first_completed_ride_id: normalized.first_completed_ride_id,
    first_completed_ride_at: normalized.first_completed_ride_at,
    last_real_ride_id: normalized.last_real_ride_id,
    last_real_ride_at: normalized.last_real_ride_at,
    total_real_rides: normalized.total_real_rides,
    total_completed_rides: normalized.total_completed_rides,
    created_ids: normalized.created_ids,
    completed_ids: normalized.completed_ids,
    source_revision: normalized.source_revision,
    updated_at: normalized.updated_at,
    history_complete: normalized.history_complete === true,
  };
}

export function observationFromBookingRecord(bookingId, rec = {}, scope = {}) {
  const booking = rec?.booking && typeof rec.booking === "object" ? rec.booking : {};
  return {
    tenant_id: scope.tenant_id || rec.tenant_id || rec.tenantId || booking.tenant_id,
    company_id: scope.company_id || rec.company_id || rec.companyId || booking.company_id,
    booking_id: text(bookingId || rec.booking_id || rec.bookingId || rec.id || booking.id),
    created_at: rec.created_at || rec.createdAt || booking.created_at || booking.createdAt,
    started_at: rec.started_at || rec.startedAt || booking.started_at,
    completed_at:
      rec.completed_at
      || rec.completedAt
      || rec.finished_at
      || rec.finishedAt
      || rec.dropped_off_at
      || booking.completed_at
      || booking.finished_at,
    lifecycle_status: rec.lifecycle_status || rec.lifecycle || rec.status || rec.stage || booking.status,
    booking_type: rec.booking_type || rec.bookingType || rec.kind || booking.booking_type,
    is_demo: rec.is_demo === true || rec.isDemo === true || booking.is_demo === true,
    payment_demo_mode: rec.payment_demo_mode === true || rec.paymentDemoMode === true,
    billing_test_mode: rec.billing_test_mode === true || rec.billingTestMode === true,
    allocator_probe: rec.allocator_probe === true || rec.is_allocator_probe === true,
    demo_seed: rec.demo_seed === true || rec.is_seed === true,
  };
}

export async function upsertRideActivitySummaryBestEffort(env, bookingId, rec, scope = {}) {
  try {
    if (!env?.BOOKING_KV) return { ok: false, reason: "missing_kv" };
    const tenantId = text(scope.tenant_id || scope.tenantId);
    const companyId = text(scope.company_id || scope.companyId);
    const key = rideActivitySummaryKey(tenantId, companyId);
    if (!key) return { ok: false, skipped: true, reason: "missing_scope" };
    const observation = observationFromBookingRecord(bookingId, rec, {
      tenant_id: tenantId,
      company_id: companyId,
    });
    const current = await env.BOOKING_KV.get(key, { type: "json" });
    const applied = applyRideActivityObservation(current, observation);
    if (!applied.changed) {
      return { ok: true, skipped: true, reason: applied.skipped || "unchanged", key };
    }
    await env.BOOKING_KV.put(key, JSON.stringify(serializeRideActivitySummary(applied.summary)));
    return { ok: true, key, changed: true, source_revision: applied.summary.source_revision };
  } catch (_) {
    return { ok: false, reason: "exception" };
  }
}
