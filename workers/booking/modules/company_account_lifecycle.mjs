/**
 * Company account lifecycle gates. Does not reuse billing suspension
 * (`subscription_status`) for operational pause/block, and does not invent
 * `account_enabled` on business_profile.
 *
 * Ride safety: the in-progress exception is only for an already existing,
 * assigned, open ride (status / payment / complete / cancel). It never
 * authorizes new rides or general company writes.
 */

export const COMPANY_ADMIN_SESSION_PREFIX = "company_admin:session:";
export const PUBLIC_DRIVER_SESSION_PREFIX = "public_driver:session:";
export const COMPANY_LINK_CODE_PREFIX = "company_link:index:code:";
export const COMPANY_LINK_CODE_SUFFIX = ":v1";
export const REGISTRY_TOMBSTONE_PREFIX = "company_registry:tombstone:";
export const HARD_PROTECTED_COMPANY_CODES = Object.freeze(["FLX-00001", "FLX-00020"]);

export const ACCOUNT_STATES = Object.freeze([
  "active",
  "paused",
  "blocked",
  "closed",
  "archived",
]);

export const ACCOUNT_ACTIONS = Object.freeze([
  "pause",
  "resume",
  "block",
  "unblock",
  "close",
  "archive",
]);

export const ROUTE_CLASSES = Object.freeze({
  public_login: "public_login",
  company_login: "company_login",
  new_booking: "new_booking",
  new_quote: "new_quote",
  in_progress_ride: "in_progress_ride",
  fleet_sync: "fleet_sync",
  bootstrap: "bootstrap",
  company_admin_write: "company_admin_write",
});

export const IN_PROGRESS_ACTIONS = Object.freeze([
  "status_existing",
  "payment_existing",
  "complete_existing",
  "cancel_existing",
]);

const OPEN_RIDE_STATUSES = new Set([
  "pending",
  "planned",
  "open",
  "scheduled",
  "confirmed",
  "assigned",
  "in_progress",
  "booked",
  "accepted",
  "awaiting_pickup",
  "active",
]);

const REFUSE = "refuse";
const ALLOW = "allow";

const MATRIX = Object.freeze({
  active: {
    public_login: ALLOW,
    company_login: ALLOW,
    new_booking: ALLOW,
    new_quote: ALLOW,
    in_progress_ride: ALLOW,
    fleet_sync: ALLOW,
    bootstrap: ALLOW,
    company_admin_write: ALLOW,
  },
  paused: {
    public_login: REFUSE,
    company_login: REFUSE,
    new_booking: REFUSE,
    new_quote: REFUSE,
    in_progress_ride: ALLOW,
    fleet_sync: ALLOW,
    bootstrap: ALLOW,
    company_admin_write: ALLOW,
  },
  blocked: {
    public_login: REFUSE,
    company_login: REFUSE,
    new_booking: REFUSE,
    new_quote: REFUSE,
    in_progress_ride: ALLOW,
    fleet_sync: REFUSE,
    bootstrap: REFUSE,
    company_admin_write: REFUSE,
  },
  closed: {
    public_login: REFUSE,
    company_login: REFUSE,
    new_booking: REFUSE,
    new_quote: REFUSE,
    in_progress_ride: ALLOW,
    fleet_sync: REFUSE,
    bootstrap: REFUSE,
    company_admin_write: REFUSE,
  },
  archived: {
    public_login: REFUSE,
    company_login: REFUSE,
    new_booking: REFUSE,
    new_quote: REFUSE,
    in_progress_ride: ALLOW,
    fleet_sync: REFUSE,
    bootstrap: REFUSE,
    company_admin_write: REFUSE,
  },
});

const TRANSITIONS = Object.freeze({
  pause: { active: "paused", paused: "paused" },
  resume: { paused: "active" },
  block: { active: "blocked", paused: "blocked", blocked: "blocked" },
  unblock: { blocked: "active" },
  close: { active: "closed", paused: "closed", blocked: "closed", closed: "closed" },
  archive: { closed: "archived", archived: "archived" },
});

function text(value) {
  return String(value ?? "").trim();
}

export function accountLifecycleKey(tenantId, companyId) {
  const tenant = text(tenantId);
  const company = text(companyId);
  if (!tenant || !company) return "";
  return `tenant:${tenant}:company:${company}:account_lifecycle:v1`;
}

export function companyLinkIndexKey(companyCode) {
  const code = text(companyCode);
  if (!/^FLX-[0-9]{4,12}$/.test(code)) return "";
  return `${COMPANY_LINK_CODE_PREFIX}${code}${COMPANY_LINK_CODE_SUFFIX}`;
}

export function registryTombstoneKey(companyCode) {
  const code = text(companyCode);
  if (!/^FLX-[0-9]{4,12}$/.test(code)) return "";
  return `${REGISTRY_TOMBSTONE_PREFIX}${code}:v1`;
}

export function isHardProtectedCompanyCode(companyCode) {
  return HARD_PROTECTED_COMPANY_CODES.includes(text(companyCode));
}

export function normalizeAccountState(value) {
  const next = text(value).toLowerCase();
  return ACCOUNT_STATES.includes(next) ? next : "active";
}

export function nextAccountState(current, action) {
  const state = ACCOUNT_STATES.includes(current) ? current : "active";
  const next = TRANSITIONS[action]?.[state];
  if (!next) return { ok: false, error: "action_not_available", current: state, action };
  return { ok: true, current: state, next, action };
}

export function sourceGatesForState(state) {
  const next = normalizeAccountState(state);
  return {
    state: next,
    linking_enabled: next === "active",
    revoke_company_sessions: next === "blocked" || next === "closed" || next === "archived",
    revoke_driver_sessions: next === "blocked" || next === "closed" || next === "archived",
    registry_tombstone: next === "closed" || next === "archived",
    use_subscription_suspension: false,
    write_account_enabled_profile: false,
  };
}

export function isExistingAssignedOpenRide(booking, scope = {}, action = "", actor = {}) {
  if (!IN_PROGRESS_ACTIONS.includes(action)) return false;
  if (!booking || typeof booking !== "object" || Array.isArray(booking)) return false;
  const tenant = text(booking.tenant_id ?? booking.tenantId);
  const company = text(booking.company_id ?? booking.companyId);
  if (!tenant || !company) return false;
  if (tenant !== text(scope.tenant_id) || company !== text(scope.company_id)) return false;
  const status = text(
    booking.status ?? booking.lifecycle_status ?? booking.booking_status ?? booking.stage,
  ).toLowerCase();
  if (!OPEN_RIDE_STATUSES.has(status)) return false;
  const assigned = text(
    booking.assigned_driver_id ?? booking.assignedDriverId ?? booking.driver_id ?? booking.driverId,
  );
  if (!assigned) return false;
  const actorDriver = text(actor.driver_id ?? actor.driverId);
  if (actorDriver && actorDriver !== assigned) return false;
  return true;
}

function refuseDecision(state, routeClass) {
  return {
    ok: false,
    error: state === "paused" ? "company_paused" : (state === "blocked" ? "company_blocked" : "company_unavailable"),
    state,
    route_class: routeClass,
  };
}

export function evaluateAccountRoute(state, routeClass, context = {}) {
  const next = normalizeAccountState(state);
  const klass = ROUTE_CLASSES[routeClass] || routeClass;
  if (klass === ROUTE_CLASSES.in_progress_ride) {
    const allowed = isExistingAssignedOpenRide(
      context.booking,
      context.scope || {},
      context.action,
      context.actor || {},
    );
    if (!allowed) {
      if (next === "active") {
        return { ok: true, state: next, route_class: klass, exception: false };
      }
      return { ...refuseDecision(next, klass), exception: false };
    }
    return { ok: true, state: next, route_class: klass, exception: true };
  }
  const decision = MATRIX[next]?.[klass];
  if (decision !== ALLOW && decision !== REFUSE) {
    return { ok: false, error: "unknown_route_class", state: next, route_class: klass };
  }
  if (decision === REFUSE) return refuseDecision(next, klass);
  return { ok: true, state: next, route_class: klass };
}

export function accountBlockedHttp(decision, { audience = "company" } = {}) {
  if (!decision || decision.ok === true) return null;
  if (audience === "public") {
    return { status: 503, body: { ok: false, error: "company_unavailable" } };
  }
  return {
    status: 403,
    body: {
      ok: false,
      error: decision.error || "company_unavailable",
      account_state: decision.state || null,
    },
  };
}

export async function loadAccountLifecycle(kv, { tenantId = "", companyId = "" } = {}) {
  const key = accountLifecycleKey(tenantId, companyId);
  if (!kv || !key) {
    return { state: "active", source: "default", tenant_id: text(tenantId), company_id: text(companyId) };
  }
  const raw = await kv.get(key, { type: "json" });
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    return { state: "active", source: "default", tenant_id: text(tenantId), company_id: text(companyId) };
  }
  return {
    ...raw,
    state: normalizeAccountState(raw.state),
    source: "record",
    tenant_id: text(raw.tenant_id || tenantId),
    company_id: text(raw.company_id || companyId),
  };
}

async function setLinkingEnabled(kv, companyCode, linkingEnabled) {
  const key = companyLinkIndexKey(companyCode);
  if (!kv || !key) return { ok: false, error: "link_key_missing" };
  const existing = await kv.get(key, { type: "json" });
  if (!existing || typeof existing !== "object" || Array.isArray(existing)) {
    return { ok: true, skipped: "link_record_absent" };
  }
  const record = existing.record && typeof existing.record === "object" ? existing.record : existing;
  record.linking_enabled = linkingEnabled === true;
  record.updated_at = new Date().toISOString();
  if (existing.record && typeof existing.record === "object") {
    existing.record = record;
    await kv.put(key, JSON.stringify(existing));
  } else {
    await kv.put(key, JSON.stringify(record));
  }
  return { ok: true, linking_enabled: record.linking_enabled };
}

function sameScope(record, tenantId, companyId) {
  return text(record?.tenant_id ?? record?.tenantId) === tenantId
    && text(record?.company_id ?? record?.companyId) === companyId;
}

async function revokePrefixedSessions(kv, prefix, { tenantId, companyId, role, driverId = "" } = {}) {
  if (!kv || typeof kv.list !== "function") {
    return { ok: false, error: "kv_binding_required", revoked_count: 0, skipped_count: 0 };
  }
  const tenant = text(tenantId);
  const company = text(companyId);
  if (!tenant || !company) {
    return { ok: true, revoked_count: 0, skipped_count: 0, scanned_count: 0 };
  }
  let cursor;
  let scanned = 0;
  let revoked = 0;
  let skipped = 0;
  do {
    const listed = await kv.list({ prefix, limit: 1000, cursor });
    for (const item of listed?.keys || []) {
      const key = text(item?.name);
      if (!key.startsWith(prefix)) continue;
      scanned += 1;
      const record = await kv.get(key, { type: "json" });
      if (!record || typeof record !== "object") {
        skipped += 1;
        continue;
      }
      const recRole = text(record.role).toLowerCase();
      if (role && recRole !== role) {
        skipped += 1;
        continue;
      }
      if (!sameScope(record, tenant, company)) {
        skipped += 1;
        continue;
      }
      if (driverId && text(record.driver_id ?? record.driverId) !== driverId) {
        skipped += 1;
        continue;
      }
      await kv.delete(key);
      revoked += 1;
    }
    cursor = listed?.list_complete === false ? listed?.cursor : undefined;
  } while (cursor);
  return { ok: true, scanned_count: scanned, revoked_count: revoked, skipped_count: skipped };
}

export async function revokeScopedCompanyAdminSessions(kv, scope) {
  return revokePrefixedSessions(kv, COMPANY_ADMIN_SESSION_PREFIX, {
    ...scope,
    role: "company_admin",
  });
}

export async function revokeScopedDriverSessionsForCompany(kv, scope) {
  return revokePrefixedSessions(kv, PUBLIC_DRIVER_SESSION_PREFIX, {
    ...scope,
    role: "driver",
    driverId: scope.driverId || "",
  });
}

export async function applyAccountAction(kv, {
  tenantId = "",
  companyId = "",
  companyCode = "",
  action,
  actorId = "platform_admin",
  reason = "",
  now = "",
  confirmation = null,
} = {}) {
  const tenant = text(tenantId);
  const company = text(companyId);
  if (!kv || !tenant || !company) return { ok: false, error: "scope_required" };
  if (!ACCOUNT_ACTIONS.includes(action)) return { ok: false, error: "invalid_action" };
  const current = await loadAccountLifecycle(kv, { tenantId: tenant, companyId: company });
  const transition = nextAccountState(current.state, action);
  if (!transition.ok) return transition;
  if (action === "close") {
    if (isHardProtectedCompanyCode(companyCode)) {
      return { ok: false, error: "hard_protected_company", company_code: text(companyCode) };
    }
    const expectedCode = text(confirmation?.company_code || confirmation?.companyCode);
    const expectedName = text(confirmation?.display_name || confirmation?.displayName);
    if (!expectedCode || expectedCode !== text(companyCode) || !expectedName) {
      return { ok: false, error: "close_confirmation_required" };
    }
  }
  const at = text(now) || new Date().toISOString();
  const gates = sourceGatesForState(transition.next);
  const record = {
    state: transition.next,
    previous_state: current.state,
    action,
    actor_id: text(actorId) || "platform_admin",
    reason: text(reason) || null,
    at,
    company_code: text(companyCode) || current.company_code || null,
    tenant_id: tenant,
    company_id: company,
    subscription_status_untouched: true,
  };
  await kv.put(accountLifecycleKey(tenant, company), JSON.stringify(record));
  const linking = text(companyCode)
    ? await setLinkingEnabled(kv, companyCode, gates.linking_enabled)
    : { ok: true, skipped: "company_code_absent" };
  let revoked = { company_admin: 0, drivers: 0 };
  if (gates.revoke_company_sessions || gates.revoke_driver_sessions) {
    const adminRevoke = gates.revoke_company_sessions
      ? await revokeScopedCompanyAdminSessions(kv, { tenantId: tenant, companyId: company })
      : { revoked_count: 0 };
    const driverRevoke = gates.revoke_driver_sessions
      ? await revokeScopedDriverSessionsForCompany(kv, { tenantId: tenant, companyId: company })
      : { revoked_count: 0 };
    revoked = {
      company_admin: Number(adminRevoke.revoked_count || 0),
      drivers: Number(driverRevoke.revoked_count || 0),
    };
  }
  let tombstone = null;
  if (gates.registry_tombstone && text(companyCode) && !isHardProtectedCompanyCode(companyCode)) {
    const tombKey = registryTombstoneKey(companyCode);
    await kv.put(tombKey, JSON.stringify({
      schema_version: 1,
      company_code: text(companyCode),
      revoked: true,
      revoked_at: at,
      reason: "account_close",
      phase: "account_close",
    }));
    tombstone = { written: true, key: tombKey };
  }
  return {
    ok: true,
    execute: true,
    ...record,
    gates,
    linking,
    revoked,
    tombstone,
    not_purge: true,
  };
}

export function sessionSurvivesState(state, routeClass = ROUTE_CLASSES.bootstrap, context = {}) {
  return evaluateAccountRoute(state, routeClass, context).ok === true;
}

export function accountAllowsNewDriverInbox(state) {
  return normalizeAccountState(state) === "active";
}

export function filterDriverInboxForAccountState(items, state, driverId = "") {
  const list = Array.isArray(items) ? items : [];
  if (accountAllowsNewDriverInbox(state)) return list;
  const driver = text(driverId);
  return list.filter((item) => {
    if (!item || typeof item !== "object" || Array.isArray(item)) return false;
    if (item.available_unassigned === true || item.availableUnassigned === true) return false;
    const assigned = text(
      item.assigned_driver_id ?? item.assignedDriverId ?? item.driver_id ?? item.driverId,
    );
    if (!assigned) return false;
    if (driver && assigned !== driver) return false;
    return true;
  });
}
