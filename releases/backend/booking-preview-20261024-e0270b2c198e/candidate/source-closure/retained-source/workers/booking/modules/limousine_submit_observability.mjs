// Safe submit observability for limousine quote-requests and /book.
// Never logs addresses, customer PII, tokens, secrets, raw bodies, or raw scope IDs.

export const LIMOUSINE_SUBMIT_STAGES = Object.freeze({
  GATE: "gate",
  ALLOWLIST: "allowlist",
  SCOPE: "scope",
  PUBLISHED_PARTNER: "published_partner",
  PUBLISHED_OFFER: "published_offer",
  VEHICLE_SCOPE: "vehicle_scope",
  JOURNEY_SCOPE: "journey_scope",
  ENDPOINT: "endpoint",
  VALIDATION: "validation",
  PERSIST_PRIMARY: "persist_primary",
  PERSIST_INBOX: "persist_inbox",
  STATUS_SIGN: "status_sign",
  AUTHORITATIVE_TOTAL: "authoritative_total",
  RESPONSE: "response",
  PARSE: "parse",
});

const ALLOWED_LOG_KEYS = [
  "request_id",
  "route",
  "service_type",
  "intent_kind",
  "pricing_mode",
  "public_partner_id",
  "offer_id",
  "vehicle_id",
  "journey_type",
  "tenant",
  "company",
  "partner",
  "gate_ok",
  "allowlist_ok",
  "published_partner_ok",
  "published_offer_ok",
  "vehicle_scope_ok",
  "journey_scope_ok",
  "endpoint_ok",
  "validation_ok",
  "persist_primary_ok",
  "persist_inbox_ok",
  "http_status",
  "error",
  "stage",
  "quote_request_id",
  "booking_id",
];

export function createLimousineSubmitRequestId() {
  const raw = globalThis.crypto?.randomUUID?.();
  const hex = raw ? String(raw).replace(/-/g, "") : `${Date.now().toString(16)}deadbeef`;
  return `lsub_${hex.slice(0, 20)}`;
}

export function redactLimousineScopeId(value) {
  const text = String(value ?? "").trim();
  if (!text) return "";
  if (text.length <= 4) return `***${text.length}`;
  return `${text.slice(0, 1)}***${text.slice(-1)}(len=${text.length})`;
}

function clipId(value, max = 96) {
  const text = String(value ?? "").trim();
  if (!text) return "";
  return text.length > max ? text.slice(0, max) : text;
}

export function buildLimousineSubmitLog(fields = {}) {
  const src = fields && typeof fields === "object" ? fields : {};
  const out = { event: "limousine_submit" };
  for (const key of ALLOWED_LOG_KEYS) {
    if (!Object.prototype.hasOwnProperty.call(src, key)) continue;
    const value = src[key];
    if (value === undefined || value === null || value === "") continue;
    if (key === "tenant" || key === "company" || key === "partner" || key === "public_partner_id") {
      out[key] = redactLimousineScopeId(value);
      continue;
    }
    if (typeof value === "boolean" || typeof value === "number") {
      out[key] = value;
      continue;
    }
    out[key] = clipId(value, key === "error" ? 64 : 96);
  }
  return out;
}

export function logLimousineSubmit(fields = {}, sink = console.log) {
  const line = JSON.stringify(buildLimousineSubmitLog(fields));
  const forbidden = /access_token|authorization|bearer |mapbox|@|tel:|\+32/i;
  if (forbidden.test(line)) return { ok: false, reason: "redaction_block" };
  sink(line);
  return { ok: true, line };
}

export function limousineSubmitErrorBody({
  error,
  stage,
  requestId,
  extra = {},
} = {}) {
  const body = {
    ok: false,
    error: clipId(error || "unavailable", 64) || "unavailable",
    stage: clipId(stage || LIMOUSINE_SUBMIT_STAGES.RESPONSE, 40),
    request_id: clipId(requestId, 48),
  };
  const field = clipId(extra.field, 40);
  if (field) body.field = field;
  const reason = clipId(extra.reason, 64);
  if (reason && reason !== body.error) body.reason = reason;
  const substage = clipId(extra.substage, 64);
  if (substage) body.substage = substage;
  return body;
}

export function limousineQuoteSuccessBody({
  quoteRequestId,
  requestId,
  quoteRequest,
  statusRef,
  statusExpiresAt,
  idempotent = false,
} = {}) {
  return {
    ok: true,
    quote_request_id: clipId(quoteRequestId, 120),
    request_id: clipId(requestId, 48),
    quote_request: quoteRequest && typeof quoteRequest === "object" ? quoteRequest : undefined,
    ...(statusRef ? { status_ref: statusRef } : {}),
    ...(statusExpiresAt ? { status_expires_at: statusExpiresAt } : {}),
    ...(idempotent ? { idempotent: true } : {}),
  };
}

export function attachLimousineBookObservability(out, { requestId, isLimousine } = {}) {
  if (!isLimousine || !out || typeof out !== "object") return out;
  if (requestId && !out.request_id) out.request_id = clipId(requestId, 48);
  if (out.ok === true && !out.status) out.status = "pending";
  return out;
}
