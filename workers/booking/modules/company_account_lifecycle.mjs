/**
 * Canonical company account lifecycle.
 *
 * Priority: closed > blocked > paused > active.
 * Missing, unreadable or derived status is never active.
 * Close is final. Older writes cannot overwrite closed.
 */

export const COMPANY_ADMIN_SESSION_PREFIX = "company_admin:session:";
export const PUBLIC_DRIVER_SESSION_PREFIX = "public_driver:session:";
export const COMPANY_LINK_CODE_PREFIX = "company_link:index:code:";
export const COMPANY_LINK_CODE_SUFFIX = ":v1";
export const COMPANY_LINK_SCOPE_PREFIX = "company_link:index:scope:";
export const COMPANY_LINK_SCOPE_SUFFIX = ":v1";
export const REGISTRY_TOMBSTONE_PREFIX = "company_registry:tombstone:";
export const ACCOUNT_TOMBSTONE_SCOPE_PREFIX = "company_account:tombstone:scope:";
export const ACCOUNT_TOMBSTONE_PARTNER_PREFIX = "company_account:tombstone:partner:";
export const ACCOUNT_TOMBSTONE_VAT_PREFIX = "company_account:tombstone:vat:";
export const ACCOUNT_TOMBSTONE_OWNER_PREFIX = "company_account:tombstone:owner:";
export const PUBLIC_VISIBILITY_SCOPE_PREFIX = "company_account:public_visibility:scope:";
export const PUBLIC_VISIBILITY_CODE_PREFIX = "company_account:public_visibility:code:";
export const PUBLIC_VISIBILITY_VALUES = Object.freeze(["listed", "hidden"]);
export const HARD_PROTECTED_COMPANY_CODES = Object.freeze(["FLX-00001", "FLX-00020"]);

export const PUBLIC_PARTNER_DIRECTORY_V1_KEY = "partners:directory:v1";
export const PUBLIC_PARTNER_DIRECTORY_V2_KEY = "public:partners:directory:v2";
export const PUBLIC_PARTNER_PROFILES_V1_KEY = "partners:profiles:v1";
export const PUBLIC_PARTNER_PROFILES_V2_KEY = "public:partners:profiles:v2";
export const PUBLIC_PARTNER_ROUTES_V1_KEY = "partners:booking-routes:v1";
export const PUBLIC_PARTNER_ROUTES_V2_KEY = "public:partners:booking-routes:v2";

export const ACCOUNT_STATES = Object.freeze([
  "unknown",
  "active",
  "paused",
  "blocked",
  "closed",
  "archived",
]);

export const CONFIRMED_ACCOUNT_STATES = Object.freeze([
  "active",
  "paused",
  "blocked",
  "closed",
  "archived",
]);

export const ACCOUNT_STATE_PRIORITY = Object.freeze({
  closed: 50,
  archived: 45,
  blocked: 40,
  paused: 30,
  active: 20,
  unknown: 10,
});

export const ACCOUNT_ACTIONS = Object.freeze([
  "confirm",
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
  public_active_list: "public_active_list",
  public_profile: "public_profile",
  integration_auto: "integration_auto",
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
  unknown: {
    public_login: ALLOW,
    company_login: ALLOW,
    new_booking: ALLOW,
    new_quote: ALLOW,
    in_progress_ride: ALLOW,
    fleet_sync: ALLOW,
    bootstrap: ALLOW,
    company_admin_write: ALLOW,
    public_active_list: REFUSE,
    public_profile: REFUSE,
    integration_auto: ALLOW,
  },
  active: {
    public_login: ALLOW,
    company_login: ALLOW,
    new_booking: ALLOW,
    new_quote: ALLOW,
    in_progress_ride: ALLOW,
    fleet_sync: ALLOW,
    bootstrap: ALLOW,
    company_admin_write: ALLOW,
    public_active_list: ALLOW,
    public_profile: ALLOW,
    integration_auto: ALLOW,
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
    public_active_list: REFUSE,
    public_profile: REFUSE,
    integration_auto: REFUSE,
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
    public_active_list: REFUSE,
    public_profile: REFUSE,
    integration_auto: REFUSE,
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
    public_active_list: REFUSE,
    public_profile: REFUSE,
    integration_auto: REFUSE,
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
    public_active_list: REFUSE,
    public_profile: REFUSE,
    integration_auto: REFUSE,
  },
});

const TRANSITIONS = Object.freeze({
  confirm: { unknown: "active" },
  pause: { active: "paused", paused: "paused" },
  resume: { paused: "active" },
  block: { active: "blocked", paused: "blocked", unknown: "blocked", blocked: "blocked" },
  unblock: { blocked: "active" },
  close: {
    active: "closed",
    paused: "closed",
    blocked: "closed",
    unknown: "closed",
    closed: "closed",
  },
  archive: { closed: "archived", archived: "archived" },
});

function text(value, max = 240) {
  const raw = String(value ?? "").trim();
  if (!raw) return "";
  return max > 0 && raw.length > max ? raw.slice(0, max) : raw;
}

export function preferAccountState(left, right) {
  const a = normalizeAccountState(left);
  const b = normalizeAccountState(right);
  return (ACCOUNT_STATE_PRIORITY[a] || 0) >= (ACCOUNT_STATE_PRIORITY[b] || 0) ? a : b;
}

export function accountLifecycleKey(tenantId, companyId) {
  const tenant = text(tenantId, 80);
  const company = text(companyId, 80);
  if (!tenant || !company) return "";
  return `tenant:${tenant}:company:${company}:account_lifecycle:v1`;
}

export function companyLinkIndexKey(companyCode) {
  const code = text(companyCode, 32);
  if (!/^FLX-[0-9]{4,12}$/.test(code)) return "";
  return `${COMPANY_LINK_CODE_PREFIX}${code}${COMPANY_LINK_CODE_SUFFIX}`;
}

export function companyLinkScopeKey(tenantId, companyId) {
  const tenant = text(tenantId, 80);
  const company = text(companyId, 80);
  if (!tenant || !company) return "";
  return `${COMPANY_LINK_SCOPE_PREFIX}${tenant}:${company}${COMPANY_LINK_SCOPE_SUFFIX}`;
}

export function registryTombstoneKey(companyCode) {
  const code = text(companyCode, 32);
  if (!/^FLX-[0-9]{4,12}$/.test(code)) return "";
  return `${REGISTRY_TOMBSTONE_PREFIX}${code}:v1`;
}

export function scopeTombstoneKey(tenantId, companyId) {
  const tenant = text(tenantId, 80);
  const company = text(companyId, 80);
  if (!tenant || !company) return "";
  return `${ACCOUNT_TOMBSTONE_SCOPE_PREFIX}${tenant}:${company}:v1`;
}

export function partnerTombstoneKey(publicPartnerId) {
  const id = text(publicPartnerId, 160);
  if (!id) return "";
  return `${ACCOUNT_TOMBSTONE_PARTNER_PREFIX}${id}:v1`;
}

export function vatTombstoneKey(vatOrEnterprise) {
  const vat = text(vatOrEnterprise, 96).toUpperCase().replace(/[\s./-]+/g, "");
  if (vat.length < 8) return "";
  return `${ACCOUNT_TOMBSTONE_VAT_PREFIX}${vat}:v1`;
}

export function ownerTombstoneKey(ownerAccountId) {
  const owner = text(ownerAccountId, 120);
  if (!owner) return "";
  return `${ACCOUNT_TOMBSTONE_OWNER_PREFIX}${owner}:v1`;
}

export function publicVisibilityScopeKey(tenantId, companyId) {
  const tenant = text(tenantId, 80);
  const company = text(companyId, 80);
  if (!tenant || !company) return "";
  return `${PUBLIC_VISIBILITY_SCOPE_PREFIX}${tenant}:${company}:v1`;
}

export function publicVisibilityCodeKey(companyCode) {
  const code = text(companyCode, 32);
  if (!/^FLX-[0-9]{4,12}$/.test(code)) return "";
  return `${PUBLIC_VISIBILITY_CODE_PREFIX}${code}:v1`;
}

export function normalizePublicVisibility(value) {
  const next = text(value, 24).toLowerCase();
  return PUBLIC_VISIBILITY_VALUES.includes(next) ? next : "";
}

function hiddenByPlatformVisibility(extras = {}) {
  return normalizePublicVisibility(extras.public_visibility ?? extras.publicVisibility) === "hidden";
}

export function canonicalPublicPartnerId(tenantId, companyId) {
  const tenant = text(tenantId, 80);
  const company = text(companyId, 80);
  if (!tenant || !company) return "";
  return `company:${tenant}:${company}`;
}

export function isHardProtectedCompanyCode(companyCode) {
  return HARD_PROTECTED_COMPANY_CODES.includes(text(companyCode, 32));
}

export function normalizeAccountState(value) {
  const next = text(value, 24).toLowerCase();
  return ACCOUNT_STATES.includes(next) ? next : "unknown";
}

export function resolveCanonicalAccountState(sources = []) {
  const list = Array.isArray(sources) ? sources : [sources];
  let resolved = "unknown";
  let source = "missing";
  for (const item of list) {
    if (item == null) continue;
    if (typeof item === "string") {
      resolved = preferAccountState(resolved, item);
      if (CONFIRMED_ACCOUNT_STATES.includes(normalizeAccountState(item))) source = "record";
      continue;
    }
    if (typeof item !== "object" || Array.isArray(item)) continue;
    const candidate = normalizeAccountState(
      item.state ?? item.account_state ?? item.accountState ?? item.lifecycle_status,
    );
    if (item.tombstone === true || item.revoked === true || item.closed === true) {
      return { state: "closed", source: "tombstone" };
    }
    resolved = preferAccountState(resolved, candidate);
    if (CONFIRMED_ACCOUNT_STATES.includes(candidate)) {
      source = text(item.source, 40) || "record";
    }
  }
  return { state: resolved, source: resolved === "unknown" ? "missing" : source };
}

export function nextAccountState(current, action) {
  const state = normalizeAccountState(current);
  if (state === "closed" && action !== "close") {
    return { ok: false, error: "closed_is_final", current: state, action };
  }
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
    remove_public_projection: next === "closed" || next === "archived",
    mark_public_inactive: next === "blocked" || next === "paused",
    use_subscription_suspension: false,
    write_account_enabled_profile: false,
  };
}

export function isExistingAssignedOpenRide(booking, scope = {}, action = "", actor = {}) {
  if (!IN_PROGRESS_ACTIONS.includes(action)) return false;
  if (!booking || typeof booking !== "object" || Array.isArray(booking)) return false;
  const tenant = text(booking.tenant_id ?? booking.tenantId, 80);
  const company = text(booking.company_id ?? booking.companyId, 80);
  if (!tenant || !company) return false;
  if (tenant !== text(scope.tenant_id, 80) || company !== text(scope.company_id, 80)) return false;
  const status = text(
    booking.status ?? booking.lifecycle_status ?? booking.booking_status ?? booking.stage,
    40,
  ).toLowerCase();
  if (!OPEN_RIDE_STATUSES.has(status)) return false;
  const assigned = text(
    booking.assigned_driver_id ?? booking.assignedDriverId ?? booking.driver_id ?? booking.driverId,
    96,
  );
  if (!assigned) return false;
  const actorDriver = text(actor.driver_id ?? actor.driverId, 96);
  if (actorDriver && actorDriver !== assigned) return false;
  return true;
}

function refuseDecision(state, routeClass) {
  return {
    ok: false,
    error: state === "paused"
      ? "company_paused"
      : (state === "blocked" ? "company_blocked" : (state === "unknown" ? "company_unconfirmed" : "company_unavailable")),
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

export function publicActivePartnerEligibility(account = {}, extras = {}) {
  const state = normalizeAccountState(account.state ?? account);
  if (hiddenByPlatformVisibility(extras)) {
    return { ok: false, eligible: false, state, reason: "public_visibility_hidden" };
  }
  if (state !== "active") {
    return { ok: false, eligible: false, state, reason: state === "unknown" ? "account_unconfirmed" : `account_${state}` };
  }
  if (extras.published === false || extras.profile_enabled === false) {
    return { ok: false, eligible: false, state, reason: "profile_not_published" };
  }
  return { ok: true, eligible: true, state, reason: "active_published" };
}

export function publicProfileEligibility(account = {}, extras = {}) {
  const state = normalizeAccountState(account.state ?? account);
  if (hiddenByPlatformVisibility(extras)) {
    return { ok: false, visible: false, bookable: false, state, reason: "public_visibility_hidden" };
  }
  if (state === "closed" || state === "archived") {
    return { ok: false, visible: false, bookable: false, state, reason: "closed" };
  }
  if (state === "blocked") {
    return { ok: true, visible: true, bookable: false, inactive: true, state, reason: "blocked_inactive" };
  }
  if (state === "paused") {
    return { ok: true, visible: true, bookable: false, inactive: true, state, reason: "paused" };
  }
  if (state === "unknown") {
    return { ok: true, visible: true, bookable: false, inactive: true, state, reason: "unconfirmed" };
  }
  return { ok: true, visible: true, bookable: true, state, reason: "active" };
}

export function publicListingEligibility(account = {}, extras = {}) {
  const state = normalizeAccountState(account.state ?? account);
  if (hiddenByPlatformVisibility(extras)) {
    return { ok: false, list: false, bookable: false, state, reason: "public_visibility_hidden" };
  }
  if (state === "closed" || state === "archived") {
    return { ok: false, list: false, bookable: false, state, reason: "closed" };
  }
  if (state === "blocked" || state === "paused") {
    return { ok: false, list: false, bookable: false, state, reason: `account_${state}` };
  }
  if (state === "unknown") {
    return { ok: true, list: true, bookable: false, state, reason: "unconfirmed" };
  }
  return { ok: true, list: true, bookable: true, state, reason: "active" };
}

export function operationalAccessEligibility(account = {}, routeClass, context = {}) {
  return evaluateAccountRoute(account.state ?? account, routeClass, context);
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

function isClosureTombstone(raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return false;
  return raw.revoked === true
    || raw.tombstone === true
    || raw.state === "closed"
    || raw.reason === "account_close"
    || raw.phase === "account_close";
}

export async function findClosureTombstone(kv, identity = {}) {
  if (!kv) return null;
  const keys = [
    registryTombstoneKey(identity.companyCode || identity.company_code),
    scopeTombstoneKey(identity.tenantId || identity.tenant_id, identity.companyId || identity.company_id),
    partnerTombstoneKey(identity.publicPartnerId || identity.public_partner_id
      || canonicalPublicPartnerId(identity.tenantId || identity.tenant_id, identity.companyId || identity.company_id)),
    vatTombstoneKey(identity.vatNumber || identity.vat_number || identity.enterprise_number),
    ownerTombstoneKey(identity.ownerAccountId || identity.owner_account_id || identity.account_id),
  ].filter(Boolean);
  for (const key of keys) {
    const raw = await kv.get(key, { type: "json" });
    if (isClosureTombstone(raw)) return { key, record: raw };
  }
  return null;
}

export async function assertNotClosedIdentity(kv, identity = {}) {
  const hit = await findClosureTombstone(kv, identity);
  if (!hit) return { ok: true };
  return { ok: false, error: "company_closed", state: "closed", tombstone_key: hit.key };
}

export async function loadPublicVisibilityOverride(kv, identity = {}) {
  if (!kv) {
    return { visibility: "", source: "missing", record: null, immutable_from_sync: true };
  }
  const keys = [
    publicVisibilityScopeKey(identity.tenantId || identity.tenant_id, identity.companyId || identity.company_id),
    publicVisibilityCodeKey(identity.companyCode || identity.company_code),
  ].filter(Boolean);
  let listed = null;
  for (const key of keys) {
    const raw = await kv.get(key, { type: "json" });
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) continue;
    const visibility = normalizePublicVisibility(raw.public_visibility ?? raw.visibility);
    if (!visibility) continue;
    const loaded = {
      visibility,
      source: "platform_admin",
      key,
      record: raw,
      immutable_from_sync: true,
    };
    if (visibility === "hidden") return loaded;
    listed = loaded;
  }
  return listed || { visibility: "", source: "missing", record: null, immutable_from_sync: true };
}

export async function applyPublicVisibilityOverride(kv, {
  tenantId = "",
  companyId = "",
  companyCode = "",
  visibility,
  actorId = "platform_admin",
  reason = "",
  now = "",
} = {}) {
  const next = normalizePublicVisibility(visibility);
  if (!kv || !next) return { ok: false, error: "invalid_public_visibility" };
  const tenant = text(tenantId, 80);
  const company = text(companyId, 80);
  const code = text(companyCode, 32);
  if (!tenant || !company) return { ok: false, error: "scope_required" };
  const at = text(now, 48) || new Date().toISOString();
  const payload = {
    schema_version: 1,
    public_visibility: next,
    source: "platform_admin",
    immutable_from_sync: true,
    tenant_id: tenant,
    company_id: company,
    company_code: code || null,
    actor_id: text(actorId, 80) || "platform_admin",
    reason: text(reason, 240) || null,
    at,
  };
  const keys = [
    publicVisibilityScopeKey(tenant, company),
    publicVisibilityCodeKey(code),
  ].filter(Boolean);
  for (const key of keys) {
    await kv.put(key, JSON.stringify(payload));
  }
  let public_index = null;
  if (next === "hidden") {
    public_index = await removeCompanyFromPublicProjections(kv, {
      tenantId: tenant,
      companyId: company,
      companyCode: code,
    });
  }
  return {
    ok: true,
    public_visibility: next,
    account_state_unchanged: true,
    keys,
    public_index,
    not_purge: true,
  };
}

export async function loadAccountLifecycle(kv, {
  tenantId = "",
  companyId = "",
  companyCode = "",
  publicPartnerId = "",
  vatNumber = "",
  ownerAccountId = "",
} = {}) {
  const tenant = text(tenantId, 80);
  const company = text(companyId, 80);
  const empty = {
    state: "unknown",
    source: "missing",
    tenant_id: tenant,
    company_id: company,
    company_code: text(companyCode, 32) || null,
    revision: 0,
  };
  if (!kv) return empty;
  const tombstone = await findClosureTombstone(kv, {
    tenantId: tenant,
    companyId: company,
    companyCode,
    publicPartnerId,
    vatNumber,
    ownerAccountId,
  });
  if (tombstone) {
    return {
      ...empty,
      state: "closed",
      source: "tombstone",
      tombstone: true,
      at: tombstone.record?.revoked_at || tombstone.record?.at || null,
    };
  }
  const key = accountLifecycleKey(tenant, company);
  if (!key) return empty;
  const raw = await kv.get(key, { type: "json" });
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return empty;
  const resolved = resolveCanonicalAccountState(raw);
  return {
    ...raw,
    state: resolved.state,
    source: resolved.source,
    tenant_id: text(raw.tenant_id || tenant, 80),
    company_id: text(raw.company_id || company, 80),
    company_code: text(raw.company_code || companyCode, 32) || null,
    revision: Number(raw.revision || 0) || 0,
  };
}

async function writeLinkingEnabled(kv, key, linkingEnabled) {
  if (!kv || !key) return { ok: false, error: "link_key_missing" };
  const existing = await kv.get(key, { type: "json" });
  if (!existing || typeof existing !== "object" || Array.isArray(existing)) {
    return { ok: true, skipped: "link_record_absent" };
  }
  const wrapped = existing.record && typeof existing.record === "object";
  const record = wrapped ? existing.record : existing;
  record.linking_enabled = linkingEnabled === true;
  record.updated_at = new Date().toISOString();
  if (wrapped) {
    existing.record = record;
    await kv.put(key, JSON.stringify(existing));
  } else {
    await kv.put(key, JSON.stringify(record));
  }
  return { ok: true, linking_enabled: record.linking_enabled };
}

async function setLinkingEnabled(kv, { companyCode, tenantId, companyId }, linkingEnabled) {
  const codeResult = text(companyCode, 32)
    ? await writeLinkingEnabled(kv, companyLinkIndexKey(companyCode), linkingEnabled)
    : { ok: true, skipped: "company_code_absent" };
  const scopeResult = await writeLinkingEnabled(kv, companyLinkScopeKey(tenantId, companyId), linkingEnabled);
  return { ok: true, code: codeResult, scope: scopeResult };
}

function sameScope(record, tenantId, companyId) {
  return text(record?.tenant_id ?? record?.tenantId, 80) === tenantId
    && text(record?.company_id ?? record?.companyId, 80) === companyId;
}

async function revokePrefixedSessions(kv, prefix, { tenantId, companyId, role, driverId = "" } = {}) {
  if (!kv || typeof kv.list !== "function") {
    return { ok: false, error: "kv_binding_required", revoked_count: 0, skipped_count: 0 };
  }
  const tenant = text(tenantId, 80);
  const company = text(companyId, 80);
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
      const key = text(item?.name, 240);
      if (!key.startsWith(prefix)) continue;
      scanned += 1;
      const record = await kv.get(key, { type: "json" });
      if (!record || typeof record !== "object") {
        skipped += 1;
        continue;
      }
      const recRole = text(record.role, 40).toLowerCase();
      if (role && recRole !== role) {
        skipped += 1;
        continue;
      }
      if (!sameScope(record, tenant, company)) {
        skipped += 1;
        continue;
      }
      if (driverId && text(record.driver_id ?? record.driverId, 96) !== driverId) {
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

function listFromProjection(raw, names) {
  if (Array.isArray(raw)) return { wrapper: "array", items: raw };
  if (!raw || typeof raw !== "object") return { wrapper: "missing", items: [] };
  for (const name of names) {
    if (Array.isArray(raw[name])) return { wrapper: name, items: raw[name], rest: raw };
  }
  return { wrapper: "object", items: [], rest: raw };
}

function partnerIdsForIdentity(identity = {}) {
  const ids = new Set();
  const canonical = canonicalPublicPartnerId(identity.tenantId || identity.tenant_id, identity.companyId || identity.company_id);
  if (canonical) ids.add(canonical);
  const explicit = text(identity.publicPartnerId || identity.public_partner_id, 160);
  if (explicit) ids.add(explicit);
  const company = text(identity.companyId || identity.company_id, 80);
  if (company) ids.add(company);
  return ids;
}

function rowPartnerId(row) {
  return text(row?.partner_id ?? row?.partnerId ?? row?.id, 160);
}

async function mutateProjectionList(kv, key, names, mutate) {
  if (!kv || !key) return { ok: false, changed: false };
  const raw = await kv.get(key, { type: "json" });
  const parsed = listFromProjection(raw, names);
  const nextItems = mutate(parsed.items.slice());
  const changed = JSON.stringify(parsed.items) !== JSON.stringify(nextItems);
  if (!changed) return { ok: true, changed: false, count: nextItems.length };
  const updatedAt = new Date().toISOString();
  let payload;
  if (parsed.wrapper === "array") payload = nextItems;
  else if (parsed.wrapper === "missing") payload = { version: 2, updated_at: updatedAt, [names[0]]: nextItems };
  else payload = { ...(parsed.rest || {}), [parsed.wrapper]: nextItems, updated_at: updatedAt };
  await kv.put(key, JSON.stringify(payload));
  return { ok: true, changed: true, count: nextItems.length };
}

export async function removeCompanyFromPublicProjections(kv, identity = {}) {
  const ids = partnerIdsForIdentity(identity);
  if (!kv || !ids.size) return { ok: true, removed: 0 };
  const drop = (items) => items.filter((row) => !ids.has(rowPartnerId(row)));
  const results = await Promise.all([
    mutateProjectionList(kv, PUBLIC_PARTNER_DIRECTORY_V1_KEY, ["partners"], drop),
    mutateProjectionList(kv, PUBLIC_PARTNER_DIRECTORY_V2_KEY, ["partners"], drop),
    mutateProjectionList(kv, PUBLIC_PARTNER_PROFILES_V1_KEY, ["profiles"], drop),
    mutateProjectionList(kv, PUBLIC_PARTNER_PROFILES_V2_KEY, ["profiles"], drop),
    mutateProjectionList(kv, PUBLIC_PARTNER_ROUTES_V1_KEY, ["routes"], drop),
    mutateProjectionList(kv, PUBLIC_PARTNER_ROUTES_V2_KEY, ["routes"], drop),
  ]);
  return { ok: true, removed: results.filter((row) => row.changed).length };
}

export async function markPublicPartnerInactive(kv, identity = {}) {
  const ids = partnerIdsForIdentity(identity);
  if (!kv || !ids.size) return { ok: true, updated: 0 };
  const mark = (items) => items.map((row) => {
    if (!ids.has(rowPartnerId(row))) return row;
    return { ...row, is_active: false, bookable: false, availability_status: "inactive" };
  });
  const results = await Promise.all([
    mutateProjectionList(kv, PUBLIC_PARTNER_DIRECTORY_V1_KEY, ["partners"], mark),
    mutateProjectionList(kv, PUBLIC_PARTNER_DIRECTORY_V2_KEY, ["partners"], mark),
    mutateProjectionList(kv, PUBLIC_PARTNER_PROFILES_V1_KEY, ["profiles"], mark),
    mutateProjectionList(kv, PUBLIC_PARTNER_PROFILES_V2_KEY, ["profiles"], mark),
    mutateProjectionList(kv, PUBLIC_PARTNER_ROUTES_V1_KEY, ["routes"], mark),
    mutateProjectionList(kv, PUBLIC_PARTNER_ROUTES_V2_KEY, ["routes"], mark),
  ]);
  return { ok: true, updated: results.filter((row) => row.changed).length };
}

async function writeClosureTombstones(kv, record) {
  const payload = {
    schema_version: 2,
    state: "closed",
    revoked: true,
    tombstone: true,
    immutable: true,
    company_code: record.company_code || null,
    tenant_id: record.tenant_id,
    company_id: record.company_id,
    public_partner_id: canonicalPublicPartnerId(record.tenant_id, record.company_id),
    owner_account_id: record.owner_account_id || null,
    vat_or_enterprise: record.vat_or_enterprise || null,
    revoked_at: record.at,
    reason: "account_close",
    phase: "account_close",
    actor_id: record.actor_id,
  };
  const keys = [
    registryTombstoneKey(record.company_code),
    scopeTombstoneKey(record.tenant_id, record.company_id),
    partnerTombstoneKey(payload.public_partner_id),
    vatTombstoneKey(record.vat_or_enterprise),
    ownerTombstoneKey(record.owner_account_id),
  ].filter(Boolean);
  for (const key of keys) {
    await kv.put(key, JSON.stringify(payload));
  }
  return { written: true, keys };
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
  vatNumber = "",
  ownerAccountId = "",
  removeFromRegistry = null,
} = {}) {
  const tenant = text(tenantId, 80);
  const company = text(companyId, 80);
  if (!kv || !tenant || !company) return { ok: false, error: "scope_required" };
  if (!ACCOUNT_ACTIONS.includes(action)) return { ok: false, error: "invalid_action" };
  const current = await loadAccountLifecycle(kv, {
    tenantId: tenant,
    companyId: company,
    companyCode,
    vatNumber,
    ownerAccountId,
  });
  if (current.state === "closed" && action !== "close") {
    return { ok: false, error: "closed_is_final", current: "closed", action, state: "closed" };
  }
  const transition = nextAccountState(current.state, action);
  if (!transition.ok) return transition;
  if (action === "close") {
    if (isHardProtectedCompanyCode(companyCode)) {
      return { ok: false, error: "hard_protected_company", company_code: text(companyCode, 32) };
    }
    const expectedCode = text(confirmation?.company_code || confirmation?.companyCode, 32);
    const expectedName = text(confirmation?.display_name || confirmation?.displayName, 160);
    if (current.state !== "closed" && (!expectedCode || expectedCode !== text(companyCode, 32) || !expectedName)) {
      return { ok: false, error: "close_confirmation_required" };
    }
  }
  const at = text(now, 48) || new Date().toISOString();
  if (current.state === "closed") {
    const identity = {
      tenantId: tenant,
      companyId: company,
      companyCode: text(companyCode, 32) || current.company_code,
      vatNumber: text(vatNumber, 96) || current.vat_or_enterprise,
      ownerAccountId: text(ownerAccountId, 120) || current.owner_account_id,
    };
    const tombstone = await writeClosureTombstones(kv, {
      ...current,
      company_code: identity.companyCode,
      vat_or_enterprise: identity.vatNumber,
      owner_account_id: identity.ownerAccountId,
      at: current.at || at,
    });
    await setLinkingEnabled(kv, {
      companyCode: identity.companyCode,
      tenantId: tenant,
      companyId: company,
    }, false);
    const publicIndex = await removeCompanyFromPublicProjections(kv, identity);
    const registry = typeof removeFromRegistry === "function"
      ? await removeFromRegistry({
        companyCode: identity.companyCode,
        tenantId: tenant,
        companyId: company,
      })
      : null;
    return {
      ok: true,
      execute: true,
      ...current,
      action: "close",
      idempotent: true,
      tombstone,
      public_index: publicIndex,
      registry,
      not_purge: true,
    };
  }
  const gates = sourceGatesForState(transition.next);
  const record = {
    state: transition.next,
    previous_state: current.state,
    action,
    actor_id: text(actorId, 80) || "platform_admin",
    reason: text(reason, 240) || null,
    at,
    revision: (Number(current.revision || 0) || 0) + 1,
    company_code: text(companyCode, 32) || current.company_code || null,
    tenant_id: tenant,
    company_id: company,
    owner_account_id: text(ownerAccountId, 120) || current.owner_account_id || null,
    vat_or_enterprise: text(vatNumber, 96) || current.vat_or_enterprise || null,
    subscription_status_untouched: true,
  };
  await kv.put(accountLifecycleKey(tenant, company), JSON.stringify(record));
  const linking = await setLinkingEnabled(kv, {
    companyCode,
    tenantId: tenant,
    companyId: company,
  }, gates.linking_enabled);
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
  if (gates.registry_tombstone && !isHardProtectedCompanyCode(companyCode)) {
    tombstone = await writeClosureTombstones(kv, record);
  }
  let public_index = null;
  if (gates.remove_public_projection) {
    public_index = await removeCompanyFromPublicProjections(kv, {
      tenantId: tenant,
      companyId: company,
      companyCode,
    });
  } else if (gates.mark_public_inactive) {
    public_index = await markPublicPartnerInactive(kv, {
      tenantId: tenant,
      companyId: company,
      companyCode,
    });
  }
  let registry = null;
  if (gates.registry_tombstone && typeof removeFromRegistry === "function") {
    registry = await removeFromRegistry({
      companyCode: text(companyCode, 32),
      tenantId: tenant,
      companyId: company,
    });
  }
  return {
    ok: true,
    execute: true,
    ...record,
    gates,
    linking,
    revoked,
    tombstone,
    public_index,
    registry,
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
  const driver = text(driverId, 96);
  return list.filter((item) => {
    if (!item || typeof item !== "object" || Array.isArray(item)) return false;
    if (item.available_unassigned === true || item.availableUnassigned === true) return false;
    const assigned = text(
      item.assigned_driver_id ?? item.assignedDriverId ?? item.driver_id ?? item.driverId,
      96,
    );
    if (!assigned) return false;
    if (driver && assigned !== driver) return false;
    return true;
  });
}

export function publicPartnerAccountFields(account = {}, extras = {}) {
  const list = publicActivePartnerEligibility(account, extras);
  const profile = publicProfileEligibility(account, extras);
  return {
    account_state: normalizeAccountState(account.state ?? account),
    bookable: list.eligible === true && profile.bookable === true,
    is_active: list.eligible === true,
    availability_status: list.eligible === true ? "active" : "inactive",
  };
}
