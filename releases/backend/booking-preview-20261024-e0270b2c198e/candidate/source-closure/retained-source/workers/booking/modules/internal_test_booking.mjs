/**
 * Internally authorized Mollie test bookings.
 *
 * A customer body flag never activates test mode. Activation is server-side
 * only: allowlisted company + (admin header or consumed company grant).
 * Once stamped, create / resume / webhook / status reuse that stamp.
 */

export const INTERNAL_TEST_BOOKING_KIND = "internal_test_booking";
export const INTERNAL_TEST_BOOKING_HEADER = "x-fluxidi-internal-test-booking";
export const CUSTOMER_HOSTED_CHECKOUT_ROUTE_CHANNEL = "customer_hosted_checkout";
export const CUSTOMER_HOSTED_CHECKOUT_ROUTE_SOURCE = "customer_book";
export const INTERNAL_TEST_BOOKING_GRANT_PREFIX = "internal_test_booking_grant:v1:";

export const CLIENT_TEST_MODE_FIELDS = Object.freeze([
  "testmode",
  "testMode",
  "payment_test_mode",
  "paymentTestMode",
  "mollie_testmode",
  "mollieTestmode",
  "mollie_mode",
  "mollieMode",
  "internal_test_booking",
  "internalTestBooking",
  "__internal_test_booking",
]);

export function parseInternalTestCompanyAllowlist(raw) {
  return String(raw || "")
    .split(/[,\s]+/)
    .map((part) => String(part || "").trim().toUpperCase())
    .filter(Boolean);
}

export function isInternalTestPaymentCompany(allowlist, ...ids) {
  const allowed = Array.isArray(allowlist) ? allowlist : parseInternalTestCompanyAllowlist(allowlist);
  if (!allowed.length) return false;
  return ids.some((id) => {
    const token = String(id || "").trim().toUpperCase();
    return !!token && allowed.includes(token);
  });
}

export function stripClientTestModeFields(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) return body;
  const clean = { ...body };
  for (const key of CLIENT_TEST_MODE_FIELDS) {
    delete clean[key];
  }
  if (clean.mollie && typeof clean.mollie === "object" && !Array.isArray(clean.mollie)) {
    clean.mollie = { ...clean.mollie };
    delete clean.mollie.testmode;
    delete clean.mollie.testMode;
  }
  return clean;
}

export function readInternalTestBookingStamp(source = null) {
  const src = source && typeof source === "object" ? source : {};
  const nested = src.booking && typeof src.booking === "object" ? src.booking : {};
  const payload = src.payload && typeof src.payload === "object" ? src.payload : {};
  const kind = String(
    src.internal_test_booking_kind ??
      src.internalTestBookingKind ??
      nested.internal_test_booking_kind ??
      "",
  ).trim();
  const flagged =
    src.internal_test_booking === true ||
    src.internalTestBooking === true ||
    nested.internal_test_booking === true ||
    payload.internal_test_booking === true ||
    kind === INTERNAL_TEST_BOOKING_KIND;
  const explicit =
    src.payment_test_mode ??
    src.paymentTestMode ??
    src.mollie_testmode ??
    src.mollieTestmode ??
    nested.payment_test_mode ??
    payload.payment_test_mode;
  let explicitTest = null;
  if (typeof explicit === "boolean") explicitTest = explicit;
  else if (explicit != null && String(explicit).trim()) {
    const token = String(explicit).trim().toLowerCase();
    if (token === "true" || token === "1" || token === "test") explicitTest = true;
    if (token === "false" || token === "0" || token === "live") explicitTest = false;
  }
  const mode = String(src.mollie_mode ?? src.mollieMode ?? src.mollie?.mode ?? "")
    .trim()
    .toLowerCase();
  if (flagged || explicitTest === true || mode === "test") {
    return { known: true, isTest: true, isLive: false };
  }
  if (explicitTest === false || mode === "live") {
    return { known: true, isTest: false, isLive: true };
  }
  return { known: false, isTest: false, isLive: false };
}

export function isInternalTestBooking(source) {
  return readInternalTestBookingStamp(source).isTest === true;
}

export function applyInternalTestBookingStamp(target, {
  actorKind = "",
  companyId = "",
  nowIso = "",
} = {}) {
  if (!target || typeof target !== "object" || Array.isArray(target)) return target;
  const stampedAt = String(nowIso || "").trim() || new Date().toISOString();
  target.internal_test_booking = true;
  target.internalTestBooking = true;
  target.internal_test_booking_kind = INTERNAL_TEST_BOOKING_KIND;
  target.internalTestBookingKind = INTERNAL_TEST_BOOKING_KIND;
  target.payment_test_mode = true;
  target.paymentTestMode = true;
  target.mollie_testmode = true;
  target.mollieTestmode = true;
  target.mollie_mode = "test";
  target.mollieMode = "test";
  target.financial_processing = "suppressed_internal_test";
  target.financialProcessing = "suppressed_internal_test";
  target.internal_test_booking_stamped_at = stampedAt;
  if (actorKind) target.internal_test_booking_actor = String(actorKind).slice(0, 40);
  if (companyId) target.internal_test_booking_company_id = String(companyId).slice(0, 80);
  if (target.booking && typeof target.booking === "object") {
    applyInternalTestBookingStamp(target.booking, { actorKind, companyId, nowIso: stampedAt });
  }
  return target;
}

export function decideInternalTestModeActivation({
  actorKind = "none",
  companyAllowed = false,
  adminHeaderRequested = false,
  grantAvailable = false,
  existingStamp = null,
} = {}) {
  if (existingStamp?.isTest === true) {
    return { activate: true, reason: "existing_test_stamp", immutable: true };
  }
  if (existingStamp?.isLive === true || existingStamp?.known === true) {
    return { activate: false, reason: "existing_live_locked", immutable: true };
  }
  if (!companyAllowed) {
    return { activate: false, reason: "company_not_allowlisted", immutable: false };
  }
  if (actorKind === "admin_token" && adminHeaderRequested) {
    return { activate: true, reason: "admin_authorized", immutable: false };
  }
  if ((actorKind === "company_session" || actorKind === "admin_token") && grantAvailable) {
    return { activate: true, reason: "internal_grant", immutable: false };
  }
  return { activate: false, reason: "actor_cannot_activate", immutable: false };
}

export function readMolliePaymentIsTest(payment = null) {
  const src = payment && typeof payment === "object" ? payment : {};
  const mode = String(src.mode ?? src.mollie_mode ?? "").trim().toLowerCase();
  if (mode === "test") return true;
  if (mode === "live") return false;
  if (src.testmode === true || src.testMode === true) return true;
  return false;
}

export function testPaymentMaySettleBooking({ bookingIsTest = false, paymentIsTest = false } = {}) {
  return Boolean(bookingIsTest) === Boolean(paymentIsTest);
}

export function shouldSkipRealFinancialProcessing(source) {
  return isInternalTestBooking(source);
}

export function resolveCreatePaymentTestMode({
  existingStamp = null,
  activation = false,
  companyWideTestMode = false,
} = {}) {
  if (existingStamp?.isTest === true) return true;
  if (existingStamp?.isLive === true || existingStamp?.known === true) return false;
  if (activation === true) return true;
  return companyWideTestMode === true;
}

export function internalTestBookingGrantKey(tenantId, companyId) {
  const tenant = String(tenantId || "").trim();
  const company = String(companyId || "").trim();
  if (!tenant || !company) return "";
  return `${INTERNAL_TEST_BOOKING_GRANT_PREFIX}${tenant}:${company}`;
}

export function buildInternalTestBookingGrant({
  uses = 3,
  ttlSeconds = 1800,
  actorKind = "",
  companyId = "",
  nowMs = Date.now(),
} = {}) {
  const remaining = Math.max(1, Math.min(10, Number(uses) || 3));
  const ttl = Math.max(60, Math.min(6 * 60 * 60, Number(ttlSeconds) || 1800));
  return {
    version: 1,
    remaining,
    expires_at: nowMs + ttl * 1000,
    ttl_seconds: ttl,
    actor_kind: String(actorKind || "").slice(0, 40),
    company_id: String(companyId || "").slice(0, 80),
    created_at: new Date(nowMs).toISOString(),
  };
}

export function consumeInternalTestBookingGrantRecord(grant, nowMs = Date.now()) {
  if (!grant || typeof grant !== "object") {
    return { ok: false, reason: "missing" };
  }
  const expiresAt = Number(grant.expires_at);
  if (!Number.isFinite(expiresAt) || expiresAt <= nowMs) {
    return { ok: false, reason: "expired" };
  }
  const remaining = Number(grant.remaining);
  if (!Number.isFinite(remaining) || remaining < 1) {
    return { ok: false, reason: "exhausted" };
  }
  const next = { ...grant, remaining: remaining - 1 };
  const ttlSeconds = Math.max(1, Math.ceil((expiresAt - nowMs) / 1000));
  return { ok: true, grant: next, remaining: next.remaining, ttlSeconds };
}

export function headerRequestsInternalTestBooking(request) {
  const headers = request?.headers;
  if (!headers || typeof headers.get !== "function") return false;
  const raw = String(headers.get(INTERNAL_TEST_BOOKING_HEADER) || "").trim().toLowerCase();
  return raw === "1" || raw === "true" || raw === "yes";
}
