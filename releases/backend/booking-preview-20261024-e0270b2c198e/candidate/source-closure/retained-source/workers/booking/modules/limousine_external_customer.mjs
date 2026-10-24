// P3P — company-originated external customer quotations.
// Adapter only: protected contact + invitation/session. Quote, accept, book,
// invoice, Billit and Peppol stay on the existing engines.

import { sha256Hex } from "./crypto_utils.js";
import {
  LIMOUSINE_PUBLIC_FORBIDDEN_KEYS,
  LIMOUSINE_QUOTE_STATES,
  publicLimousineQuoteView,
} from "./limousine_manual_quote.mjs";
import { normalizeLimousineQuotationLocale } from "./limousine_quotation_i18n.mjs";
import {
  looksLikeLimousineAeadToken,
  sealLimousineAead,
  unsealLimousineAead,
} from "./limousine_aead_token.mjs";

export const LIMOUSINE_EXTERNAL_ORIGIN = "company_external";
export const LIMOUSINE_EXTERNAL_CONTACT_KEY_PREFIX = "limousine_external_contact:";
export const LIMOUSINE_EXTERNAL_INVITE_KEY_PREFIX = "limousine_external_invite:";
export const LIMOUSINE_EXTERNAL_SESSION_KEY_PREFIX = "limousine_external_session:";

export const LIMOUSINE_INVITE_TOKEN_VERSION = "liminv1";
export const LIMOUSINE_SESSION_TOKEN_VERSION = "limxss1";
export const LIMOUSINE_INVITE_KEY_PURPOSE = "limousine_external_invitation_v1";
export const LIMOUSINE_SESSION_KEY_PURPOSE = "limousine_external_session_v1";
export const LIMOUSINE_INVITE_PURPOSE = "external_invitation";
export const LIMOUSINE_SESSION_PURPOSE = "external_session";

export const LIMOUSINE_INVITE_TTL_MINUTES = 14 * 24 * 60;
export const LIMOUSINE_SESSION_TTL_MINUTES = 14 * 24 * 60;
export const LIMOUSINE_EXTERNAL_COOKIE = "fx_lxs";
export const LIMOUSINE_EXTERNAL_COOKIE_PATH = "/l";

export const LIMOUSINE_EXTERNAL_INVITE_RATE_MAX = 20;
export const LIMOUSINE_EXTERNAL_SESSION_RATE_MAX = 80;
export const LIMOUSINE_EXTERNAL_RATE_WINDOW_SECONDS = 15 * 60;

export const LIMOUSINE_EXTERNAL_CONTACT_FIELDS = Object.freeze([
  "display_name",
  "mail",
  "mobile",
  "locale",
  "company_label",
]);

export const LIMOUSINE_EXTERNAL_DELIVERY_STATES = Object.freeze({
  LINK_CREATED: "link_created",
  INVITATION_SHARED: "invitation_shared",
  CUSTOMER_OPENED: "customer_opened",
  QUOTATION_ACCEPTED: "quotation_accepted",
  BOOKING_CREATED: "booking_created",
});

export const LIMOUSINE_EXTERNAL_ERRORS = Object.freeze({
  INVALID_CONTACT: "invalid_contact",
  INVALID_INVITATION: "invalid_invitation",
  EXPIRED_INVITATION: "invalid_invitation",
  WRONG_SCOPE: "invalid_invitation",
  SESSION_REQUIRED: "session_required",
  QUOTE_ID_INSUFFICIENT: "quote_id_insufficient",
});

export const LIMOUSINE_EXTERNAL_PUBLIC_FORBIDDEN_KEYS = Object.freeze([
  ...LIMOUSINE_PUBLIC_FORBIDDEN_KEYS,
  "invitation_token",
  "invite_token",
  "session_token",
  "external_contact",
  "contact_mail",
  "contact_mobile",
  "display_name",
  "mail",
  "mobile",
]);

function asObject(raw) {
  return raw && typeof raw === "object" && !Array.isArray(raw) ? raw : {};
}

function safeText(value, max) {
  return String(value ?? "").trim().slice(0, max);
}

function toInt(value) {
  const n = Number(value);
  return Number.isFinite(n) ? Math.trunc(n) : null;
}

function isIsoDate(value) {
  const ms = Date.parse(String(value || ""));
  return Number.isFinite(ms);
}

function looksLikeMail(value) {
  const text = safeText(value, 160);
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(text);
}

function looksLikeMobile(value) {
  const text = safeText(value, 32).replace(/[()\s-]/g, "");
  return /^\+?[0-9]{8,15}$/.test(text);
}

export function newLimousineExternalId(prefix) {
  return `${prefix}${crypto.randomUUID().replace(/-/g, "").slice(0, 24)}`;
}

export function limousineExternalContactKey(contactId) {
  const id = safeText(contactId, 64);
  return id ? `${LIMOUSINE_EXTERNAL_CONTACT_KEY_PREFIX}${id}` : "";
}

export function limousineExternalInviteKey(invitationId) {
  const id = safeText(invitationId, 64);
  return id ? `${LIMOUSINE_EXTERNAL_INVITE_KEY_PREFIX}${id}` : "";
}

export function limousineExternalSessionKey(sessionId) {
  const id = safeText(sessionId, 64);
  return id ? `${LIMOUSINE_EXTERNAL_SESSION_KEY_PREFIX}${id}` : "";
}

export function validateLimousineExternalContact(input) {
  const src = asObject(input);
  const displayName = safeText(src.display_name ?? src.name ?? src.customer_name, 80);
  const mail = safeText(src.mail ?? src.email, 160).toLowerCase();
  const mobile = safeText(src.mobile ?? src.phone, 32).replace(/[()\s-]/g, "");
  const companyLabel = safeText(src.company_label ?? src.company_name, 80);
  const locale = normalizeLimousineQuotationLocale(src.locale);
  if (!displayName) {
    return { ok: false, reason: LIMOUSINE_EXTERNAL_ERRORS.INVALID_CONTACT, field: "display_name" };
  }
  if (!mail && !mobile) {
    return { ok: false, reason: LIMOUSINE_EXTERNAL_ERRORS.INVALID_CONTACT, field: "mail" };
  }
  if (mail && !looksLikeMail(mail)) {
    return { ok: false, reason: LIMOUSINE_EXTERNAL_ERRORS.INVALID_CONTACT, field: "mail" };
  }
  if (mobile && !looksLikeMobile(mobile)) {
    return { ok: false, reason: LIMOUSINE_EXTERNAL_ERRORS.INVALID_CONTACT, field: "mobile" };
  }
  return {
    ok: true,
    contact: {
      display_name: displayName,
      ...(mail ? { mail } : {}),
      ...(mobile ? { mobile } : {}),
      locale,
      ...(companyLabel ? { company_label: companyLabel } : {}),
    },
  };
}

export function buildLimousineExternalContactRecord({
  contactId,
  quoteRequestId,
  tenantId,
  companyId,
  contact,
  nowIso,
} = {}) {
  const checked = validateLimousineExternalContact(contact);
  if (!checked.ok) return checked;
  return {
    ok: true,
    record: {
      contact_id: safeText(contactId, 64),
      quote_request_id: safeText(quoteRequestId, 120),
      tenant_id: safeText(tenantId, 96),
      company_id: safeText(companyId, 96),
      created_at: nowIso || new Date().toISOString(),
      ...checked.contact,
    },
  };
}

export function projectLimousineCompanyContactSummary(record) {
  const src = asObject(record);
  const out = {};
  for (const key of LIMOUSINE_EXTERNAL_CONTACT_FIELDS) {
    const value = safeText(src[key], key === "mail" ? 160 : 80);
    if (value) out[key] = value;
  }
  return out;
}

export function publicProjectionContainsExternalPii(value) {
  const rendered = JSON.stringify(value ?? {});
  return LIMOUSINE_EXTERNAL_PUBLIC_FORBIDDEN_KEYS.filter((key) => {
    const token = String(key || "").trim();
    if (!token) return false;
    const escaped = token.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    return new RegExp(`(^|[^A-Za-z])${escaped}([^A-Za-z]|$)`, "i").test(rendered);
  });
}

export function sanitizeLimousineExternalLog(entry) {
  const src = asObject(entry);
  const out = {};
  for (const [key, value] of Object.entries(src)) {
    const token = key.toLowerCase();
    if (
      token.includes("token") ||
      token.includes("secret") ||
      token.includes("mail") ||
      token.includes("email") ||
      token.includes("phone") ||
      token.includes("mobile") ||
      token.includes("name") ||
      token.includes("cookie")
    ) {
      continue;
    }
    if (typeof value === "string" || typeof value === "number" || typeof value === "boolean") {
      out[key] = value;
    }
  }
  return out;
}

export function resolveLimousineExternalDeliveryState({ invitation, record } = {}) {
  const rec = asObject(record);
  const invite = asObject(invitation);
  const state = safeText(rec.state, 40);
  if (state === LIMOUSINE_QUOTE_STATES.BOOKING_CREATED || rec.booking_reference) {
    return LIMOUSINE_EXTERNAL_DELIVERY_STATES.BOOKING_CREATED;
  }
  if (state === LIMOUSINE_QUOTE_STATES.ACCEPTED || rec.accepted_at) {
    return LIMOUSINE_EXTERNAL_DELIVERY_STATES.QUOTATION_ACCEPTED;
  }
  if (invite.opened_at) return LIMOUSINE_EXTERNAL_DELIVERY_STATES.CUSTOMER_OPENED;
  if (invite.shared_at) return LIMOUSINE_EXTERNAL_DELIVERY_STATES.INVITATION_SHARED;
  if (invite.created_at) return LIMOUSINE_EXTERNAL_DELIVERY_STATES.LINK_CREATED;
  return "";
}

export function projectLimousineExternalDelivery(invitation, record) {
  const invite = asObject(invitation);
  const rec = asObject(record);
  if (safeText(rec.origin?.channel, 40) !== LIMOUSINE_EXTERNAL_ORIGIN && !invite.invitation_id) {
    return null;
  }
  return {
    origin: LIMOUSINE_EXTERNAL_ORIGIN,
    invitation_state: resolveLimousineExternalDeliveryState({ invitation: invite, record: rec }),
    ...(invite.created_at ? { link_created_at: safeText(invite.created_at, 40) } : {}),
    ...(invite.shared_at ? { shared_at: safeText(invite.shared_at, 40) } : {}),
    ...(invite.opened_at ? { opened_at: safeText(invite.opened_at, 40) } : {}),
    ...(rec.accepted_at ? { accepted_at: safeText(rec.accepted_at, 40) } : {}),
    ...(rec.booking_reference
      ? { booking_created_at: safeText(rec.updated_at || rec.accepted_at, 40) }
      : {}),
  };
}

export function withLimousineExternalDeliveryView(inboxView, invitation, record) {
  const delivery = projectLimousineExternalDelivery(invitation, record);
  if (!delivery) return inboxView;
  return {
    ...asObject(inboxView),
    origin_channel: LIMOUSINE_EXTERNAL_ORIGIN,
    external_delivery: delivery,
  };
}

export function publicLimousineExternalCustomerView(record, extras = {}) {
  const view = {
    ...publicLimousineQuoteView(record),
    ...(extras.seller ? { seller: extras.seller } : {}),
    ...(extras.payment_capability
      ? { payment_capability: extras.payment_capability }
      : {}),
  };
  return view;
}

export function looksLikeLimousineInviteToken(value) {
  return looksLikeLimousineAeadToken(value, LIMOUSINE_INVITE_TOKEN_VERSION);
}

export function looksLikeLimousineSessionToken(value) {
  return looksLikeLimousineAeadToken(value, LIMOUSINE_SESSION_TOKEN_VERSION);
}

function ttlMinutesFromRange(issuedAtIso, expiresAtIso, fallback) {
  const issued = Date.parse(String(issuedAtIso || ""));
  const expires = Date.parse(String(expiresAtIso || ""));
  if (!Number.isFinite(issued) || !Number.isFinite(expires) || expires <= issued) {
    return fallback;
  }
  return Math.max(1, Math.round((expires - issued) / 60000));
}

export async function sealLimousineExternalInvitation({
  secret,
  binding,
  issuedAtIso = null,
  ttlMinutes = LIMOUSINE_INVITE_TTL_MINUTES,
} = {}) {
  const issuedAt = issuedAtIso || new Date().toISOString();
  const expiresAt = new Date(
    Date.parse(issuedAt) + Math.max(1, Number(ttlMinutes) || LIMOUSINE_INVITE_TTL_MINUTES) * 60000,
  ).toISOString();
  const src = asObject(binding);
  const payload = {
    v: LIMOUSINE_INVITE_TOKEN_VERSION,
    purpose: LIMOUSINE_INVITE_PURPOSE,
    binding: {
      purpose: LIMOUSINE_INVITE_PURPOSE,
      tenant_id: safeText(src.tenant_id, 96),
      company_id: safeText(src.company_id, 96),
      quote_request_id: safeText(src.quote_request_id, 120),
      invitation_id: safeText(src.invitation_id, 64),
      contact_id: safeText(src.contact_id, 64),
    },
    issued_at: issuedAt,
    expires_at: expiresAt,
  };
  const sealed = await sealLimousineAead({
    secret,
    version: LIMOUSINE_INVITE_TOKEN_VERSION,
    purpose: LIMOUSINE_INVITE_KEY_PURPOSE,
    payload,
  });
  if (!sealed.ok) return { ok: false, error: LIMOUSINE_EXTERNAL_ERRORS.INVALID_INVITATION };
  return { ok: true, reference: sealed.reference, issued_at: issuedAt, expires_at: expiresAt };
}

export async function unsealLimousineExternalInvitation({ secret, reference, nowIso = null } = {}) {
  if (!looksLikeLimousineInviteToken(reference)) {
    return { ok: false, error: LIMOUSINE_EXTERNAL_ERRORS.INVALID_INVITATION };
  }
  const opened = await unsealLimousineAead({
    secret,
    version: LIMOUSINE_INVITE_TOKEN_VERSION,
    purpose: LIMOUSINE_INVITE_KEY_PURPOSE,
    reference,
  });
  if (!opened.ok) return { ok: false, error: LIMOUSINE_EXTERNAL_ERRORS.INVALID_INVITATION };
  const payload = asObject(opened.payload);
  const binding = asObject(payload.binding);
  if (payload.purpose !== LIMOUSINE_INVITE_PURPOSE || binding.purpose !== LIMOUSINE_INVITE_PURPOSE) {
    return { ok: false, error: LIMOUSINE_EXTERNAL_ERRORS.INVALID_INVITATION };
  }
  const now = Date.parse(nowIso || new Date().toISOString());
  const expires = Date.parse(payload.expires_at || "");
  if (!Number.isFinite(expires) || expires <= now) {
    return { ok: false, error: LIMOUSINE_EXTERNAL_ERRORS.EXPIRED_INVITATION };
  }
  return { ok: true, binding, issued_at: payload.issued_at, expires_at: payload.expires_at };
}

export async function sealLimousineExternalSession({
  secret,
  binding,
  issuedAtIso = null,
  ttlMinutes = LIMOUSINE_SESSION_TTL_MINUTES,
} = {}) {
  const issuedAt = issuedAtIso || new Date().toISOString();
  const expiresAt = new Date(
    Date.parse(issuedAt) + Math.max(1, Number(ttlMinutes) || LIMOUSINE_SESSION_TTL_MINUTES) * 60000,
  ).toISOString();
  const src = asObject(binding);
  const payload = {
    v: LIMOUSINE_SESSION_TOKEN_VERSION,
    purpose: LIMOUSINE_SESSION_PURPOSE,
    binding: {
      purpose: LIMOUSINE_SESSION_PURPOSE,
      tenant_id: safeText(src.tenant_id, 96),
      company_id: safeText(src.company_id, 96),
      quote_request_id: safeText(src.quote_request_id, 120),
      invitation_id: safeText(src.invitation_id, 64),
      contact_id: safeText(src.contact_id, 64),
      session_id: safeText(src.session_id, 64),
    },
    issued_at: issuedAt,
    expires_at: expiresAt,
  };
  const sealed = await sealLimousineAead({
    secret,
    version: LIMOUSINE_SESSION_TOKEN_VERSION,
    purpose: LIMOUSINE_SESSION_KEY_PURPOSE,
    payload,
  });
  if (!sealed.ok) return { ok: false, error: LIMOUSINE_EXTERNAL_ERRORS.SESSION_REQUIRED };
  return { ok: true, reference: sealed.reference, issued_at: issuedAt, expires_at: expiresAt };
}

export async function unsealLimousineExternalSession({ secret, reference, nowIso = null } = {}) {
  if (!looksLikeLimousineSessionToken(reference)) {
    return { ok: false, error: LIMOUSINE_EXTERNAL_ERRORS.SESSION_REQUIRED };
  }
  const opened = await unsealLimousineAead({
    secret,
    version: LIMOUSINE_SESSION_TOKEN_VERSION,
    purpose: LIMOUSINE_SESSION_KEY_PURPOSE,
    reference,
  });
  if (!opened.ok) return { ok: false, error: LIMOUSINE_EXTERNAL_ERRORS.SESSION_REQUIRED };
  const payload = asObject(opened.payload);
  const binding = asObject(payload.binding);
  if (payload.purpose !== LIMOUSINE_SESSION_PURPOSE || binding.purpose !== LIMOUSINE_SESSION_PURPOSE) {
    return { ok: false, error: LIMOUSINE_EXTERNAL_ERRORS.SESSION_REQUIRED };
  }
  const now = Date.parse(nowIso || new Date().toISOString());
  const expires = Date.parse(payload.expires_at || "");
  if (!Number.isFinite(expires) || expires <= now) {
    return { ok: false, error: LIMOUSINE_EXTERNAL_ERRORS.SESSION_REQUIRED };
  }
  return { ok: true, binding, issued_at: payload.issued_at, expires_at: payload.expires_at };
}

export function limousineExternalInvitationBindingMatches(binding, expected) {
  const left = asObject(binding);
  const right = asObject(expected);
  return (
    safeText(left.tenant_id, 96) === safeText(right.tenant_id, 96) &&
    safeText(left.company_id, 96) === safeText(right.company_id, 96) &&
    safeText(left.quote_request_id, 120) === safeText(right.quote_request_id, 120) &&
    safeText(left.invitation_id, 64) === safeText(right.invitation_id, 64) &&
    safeText(left.contact_id, 64) === safeText(right.contact_id, 64)
  );
}

export function buildLimousineExternalInvitationUrl(origin, token) {
  const base = safeText(origin, 240).replace(/\/$/, "");
  const ref = safeText(token, 800);
  if (!base || !ref) return "";
  return `${base}/l/i/${encodeURIComponent(ref)}`;
}

export function buildLimousineExternalCleanUrl(origin) {
  const base = safeText(origin, 240).replace(/\/$/, "");
  return base ? `${base}/l/q` : "/l/q";
}

export function readLimousineExternalSessionCookie(header) {
  const raw = String(header || "");
  const parts = raw.split(";");
  for (const part of parts) {
    const [name, ...rest] = part.split("=");
    if (safeText(name, 40) === LIMOUSINE_EXTERNAL_COOKIE) {
      return decodeURIComponent(rest.join("=").trim());
    }
  }
  return "";
}

export function limousineExternalSessionCookieHeader(token, { expiresAtIso, secure = true } = {}) {
  const ref = safeText(token, 800);
  if (!ref) return "";
  const expiresMs = Date.parse(expiresAtIso || "");
  const maxAge = Number.isFinite(expiresMs)
    ? Math.max(1, Math.round((expiresMs - Date.now()) / 1000))
    : LIMOUSINE_SESSION_TTL_MINUTES * 60;
  return [
    `${LIMOUSINE_EXTERNAL_COOKIE}=${encodeURIComponent(ref)}`,
    `Path=${LIMOUSINE_EXTERNAL_COOKIE_PATH}`,
    "HttpOnly",
    secure ? "Secure" : "",
    "SameSite=Lax",
    `Max-Age=${maxAge}`,
  ]
    .filter(Boolean)
    .join("; ");
}

export async function limousineExternalInviteRateKey(token) {
  const digest = await sha256Hex(safeText(token, 800));
  return `limousine_ext_invite_rl:v1:${digest.slice(0, 32)}`;
}

export async function limousineExternalSessionRateKey(token) {
  const digest = await sha256Hex(safeText(token, 800));
  return `limousine_ext_session_rl:v1:${digest.slice(0, 32)}`;
}

export function buildLimousineExternalInvitationRecord({
  invitationId,
  quoteRequestId,
  tenantId,
  companyId,
  contactId,
  nowIso,
  expiresAt,
} = {}) {
  const created = nowIso || new Date().toISOString();
  return {
    invitation_id: safeText(invitationId, 64),
    quote_request_id: safeText(quoteRequestId, 120),
    tenant_id: safeText(tenantId, 96),
    company_id: safeText(companyId, 96),
    contact_id: safeText(contactId, 64),
    created_at: created,
    expires_at: expiresAt || created,
  };
}

export function markLimousineExternalInvitationShared(invitation, nowIso) {
  const src = asObject(invitation);
  if (src.shared_at) return src;
  return { ...src, shared_at: nowIso || new Date().toISOString() };
}

export function markLimousineExternalInvitationOpened(invitation, nowIso) {
  const src = asObject(invitation);
  if (src.opened_at) return src;
  return { ...src, opened_at: nowIso || new Date().toISOString() };
}

export function buildLimousineExternalSessionRecord({
  sessionId,
  invitation,
  nowIso,
  expiresAt,
} = {}) {
  const invite = asObject(invitation);
  return {
    session_id: safeText(sessionId, 64),
    tenant_id: safeText(invite.tenant_id, 96),
    company_id: safeText(invite.company_id, 96),
    quote_request_id: safeText(invite.quote_request_id, 120),
    invitation_id: safeText(invite.invitation_id, 64),
    contact_id: safeText(invite.contact_id, 64),
    created_at: nowIso || new Date().toISOString(),
    expires_at: expiresAt || invite.expires_at,
  };
}

export function guestCustomerFromExternalContact(contact) {
  const src = asObject(contact);
  return {
    name: safeText(src.display_name, 80),
    ...(src.mobile ? { phone: safeText(src.mobile, 32) } : {}),
    ...(src.mail ? { email: safeText(src.mail, 160) } : {}),
  };
}

export function invitationTtlMinutes(issuedAt, expiresAt) {
  return ttlMinutesFromRange(issuedAt, expiresAt, LIMOUSINE_INVITE_TTL_MINUTES);
}

export function isExternalCompanyQuote(record) {
  return safeText(asObject(record).origin?.channel, 40) === LIMOUSINE_EXTERNAL_ORIGIN;
}

export function parseLimousineInvitePathToken(pathname) {
  const match = String(pathname || "").match(/^\/l\/i\/([^/]+)$/);
  if (!match) return "";
  try {
    return decodeURIComponent(match[1]);
  } catch (_) {
    return match[1];
  }
}

export function isLimousineExternalApiPath(pathname) {
  return String(pathname || "").startsWith("/l/api/");
}

export { isIsoDate, toInt };
