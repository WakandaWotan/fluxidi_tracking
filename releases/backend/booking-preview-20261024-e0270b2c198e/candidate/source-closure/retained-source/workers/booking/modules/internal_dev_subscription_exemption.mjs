/**
 * Permanent internal-development subscription exemption.
 *
 * Only an admin grant on an allowlisted company creates the stamp.
 * Customers cannot self-activate. The grant never starts or resumes a paid
 * Fluxidi subscription and never touches ride Mollie payments.
 */

export const INTERNAL_DEV_SUBSCRIPTION_KIND = "internal_dev_account";
export const INTERNAL_DEV_EXEMPTION_KEY_SUFFIX = "internal_dev_subscription_exemption:v1";
export const INTERNAL_DEV_UNLIMITED_CAPACITY = 1_000_000;

export const INTERNAL_DEV_PRESENTATION = Object.freeze({
  account_kind: "Intern ontwikkelaccount",
  price_label: "Gratis — geen abonnementsincasso",
  limits_label: "Onbeperkt voertuigen en chauffeurs",
  ride_payments_note:
    "Ritten blijven via de bestaande Mollie-koppeling betaald. Gratis Fluxidi-gebruik maakt ritten niet automatisch betaald.",
});

export const CLIENT_INTERNAL_DEV_FIELDS = Object.freeze([
  "internal_dev_account",
  "internalDevAccount",
  "subscription_billing_exempt",
  "subscriptionBillingExempt",
  "unlimited_vehicles",
  "unlimitedVehicles",
  "unlimited_drivers",
  "unlimitedDrivers",
]);

const COLLECTIBLE_PROVIDER_STATUSES = new Set(["active", "pending", "suspended"]);

function text(value, max = 80) {
  return String(value == null ? "" : value).trim().slice(0, max);
}

export function parseInternalDevCompanyAllowlist(raw) {
  return String(raw || "")
    .split(/[,\s]+/)
    .map((part) => text(part, 80).toUpperCase())
    .filter(Boolean);
}

export function isInternalDevExemptionCompany(allowlist, ...ids) {
  const allowed = Array.isArray(allowlist)
    ? allowlist
    : parseInternalDevCompanyAllowlist(allowlist);
  if (!allowed.length) return false;
  return ids.some((id) => {
    const token = text(id, 80).toUpperCase();
    return !!token && allowed.includes(token);
  });
}

export function internalDevExemptionKey(tenantId, companyId) {
  const tenant = text(tenantId, 80);
  const company = text(companyId, 80);
  if (!tenant || !company) return "";
  return `tenant:${tenant}:company:${company}:${INTERNAL_DEV_EXEMPTION_KEY_SUFFIX}`;
}

export function stripClientInternalDevFields(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) return body;
  const clean = { ...body };
  for (const key of CLIENT_INTERNAL_DEV_FIELDS) delete clean[key];
  return clean;
}

export function isInternalDevSubscriptionExempt(record) {
  if (!record || typeof record !== "object" || Array.isArray(record)) return false;
  return (
    record.granted === true &&
    (record.kind === INTERNAL_DEV_SUBSCRIPTION_KIND ||
      record.internal_dev_account === true)
  );
}

// Only the canonical, company-scoped grant is an entitlement authority.
// A projected/client profile flag cannot grant Smart or cross tenant scopes.
export function isScopedInternalDevSubscriptionExempt(record, scope = {}) {
  return isInternalDevSubscriptionExempt(record)
    && !!scope.tenant_id && !!scope.company_id
    && record.tenant_id === scope.tenant_id
    && record.company_id === scope.company_id;
}

export function decideInternalDevExemptionGrant({
  actorKind = "none",
  companyAllowed = false,
  existing = null,
} = {}) {
  if (actorKind !== "admin_token") {
    return { ok: false, reason: "admin_required" };
  }
  if (!companyAllowed) {
    return { ok: false, reason: "company_not_allowlisted" };
  }
  if (isInternalDevSubscriptionExempt(existing)) {
    return { ok: true, reason: "already_granted", already: true };
  }
  return { ok: true, reason: "grant", already: false };
}

export function buildInternalDevExemptionRecord({
  tenantId = "",
  companyId = "",
  companyCode = "",
  actorKind = "admin_token",
  reason = "",
  nowIso = "",
  existing = null,
} = {}) {
  const grantedAt =
    (isInternalDevSubscriptionExempt(existing) && text(existing.granted_at, 48)) ||
    text(nowIso, 48) ||
    new Date().toISOString();
  return {
    version: 1,
    kind: INTERNAL_DEV_SUBSCRIPTION_KIND,
    granted: true,
    internal_dev_account: true,
    billing_exempt: true,
    unlimited_vehicles: true,
    unlimited_drivers: true,
    no_expiry: true,
    ride_payments_unchanged: true,
    does_not_start_paid_subscription: true,
    does_not_undo_cancellation: true,
    tenant_id: text(tenantId, 80),
    company_id: text(companyId, 80),
    company_code: text(companyCode, 32) || null,
    actor_kind: text(actorKind, 40) || "admin_token",
    reason: text(reason, 240) || "internal_development_exemption",
    granted_at: grantedAt,
    updated_at: text(nowIso, 48) || new Date().toISOString(),
    presentation: { ...INTERNAL_DEV_PRESENTATION },
  };
}

export function projectInternalDevExemptionOntoProfile(profile, record) {
  const src = profile && typeof profile === "object" && !Array.isArray(profile) ? profile : {};
  if (!isInternalDevSubscriptionExempt(record)) return { ...src };
  return {
    ...src,
    internal_dev_account: true,
    internalDevAccount: true,
    subscription_billing_exempt: true,
    subscriptionBillingExempt: true,
    subscription_billing_exempt_kind: INTERNAL_DEV_SUBSCRIPTION_KIND,
    unlimited_vehicles: true,
    unlimitedVehicles: true,
    unlimited_drivers: true,
    unlimitedDrivers: true,
    ride_payments_unchanged: true,
    ridePaymentsUnchanged: true,
    billing_presentation: { ...INTERNAL_DEV_PRESENTATION },
    billingPresentation: { ...INTERNAL_DEV_PRESENTATION },
  };
}

export function resolveExemptVehicleCapacity(profile, record) {
  if (isInternalDevSubscriptionExempt(record)) return INTERNAL_DEV_UNLIMITED_CAPACITY;
  return null;
}

export function resolveExemptDriverCapacity(profile, record) {
  if (isInternalDevSubscriptionExempt(record)) return INTERNAL_DEV_UNLIMITED_CAPACITY;
  return null;
}

export function shouldBypassSubscriptionAccessGuard(record) {
  return isInternalDevSubscriptionExempt(record);
}

export function shouldRejectPaidSubscriptionCheckout(record) {
  return isInternalDevSubscriptionExempt(record);
}

export function shouldSkipSubscriptionRecurringCharge(record) {
  return isInternalDevSubscriptionExempt(record);
}

export function summarizeMollieSubscription(entry = null) {
  const src = entry && typeof entry === "object" ? entry : {};
  const status = text(src.status, 40).toLowerCase();
  return {
    id: text(src.id, 64),
    status,
    interval: text(src.interval, 40),
    next_payment_date: text(src.nextPaymentDate ?? src.next_payment_date, 48) || null,
    canceled_at: text(src.canceledAt ?? src.canceled_at, 48) || null,
    amount: src.amount && typeof src.amount === "object" ? {
      value: text(src.amount.value, 24),
      currency: text(src.amount.currency, 8),
    } : null,
    collectible: COLLECTIBLE_PROVIDER_STATUSES.has(status),
  };
}

export function summarizeMollieSubscriptionList(payload = null) {
  const src = payload && typeof payload === "object" ? payload : {};
  const embedded = src._embedded && typeof src._embedded === "object" ? src._embedded : {};
  const rows = Array.isArray(embedded.subscriptions)
    ? embedded.subscriptions
    : (Array.isArray(src.subscriptions) ? src.subscriptions : []);
  const subscriptions = rows.map((row) => summarizeMollieSubscription(row));
  return {
    count: subscriptions.length,
    subscriptions,
    collectible_count: subscriptions.filter((row) => row.collectible).length,
    future_collection_scheduled: subscriptions.some(
      (row) => row.collectible && !!row.next_payment_date,
    ),
  };
}

export function providerCollectionStopped(summary) {
  if (!summary || typeof summary !== "object") return false;
  return Number(summary.collectible_count || 0) === 0 && summary.future_collection_scheduled !== true;
}

export async function loadInternalDevSubscriptionExemption(kv, { tenantId = "", companyId = "" } = {}) {
  const key = internalDevExemptionKey(tenantId, companyId);
  if (!kv || !key) return null;
  const raw = await kv.get(key, { type: "json" });
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  return raw;
}

export async function saveInternalDevSubscriptionExemption(kv, record) {
  const key = internalDevExemptionKey(record?.tenant_id, record?.company_id);
  if (!kv || !key) return { ok: false, error: "kv_unavailable" };
  await kv.put(key, JSON.stringify(record));
  return { ok: true, record, key };
}
