// MOLLIE-HOSTED-CANCEL-WIRE-EVIDENCE-P0
//
// Safe structured observability for street hosted Mollie cancel.
// Logging only — never changes cancel decisions or KV/provider side effects.

const _FORBIDDEN_FIELD_RE =
  /token|authorization|secret|password|bearer|refresh|encrypt|checkout_url|checkoutUrl|email|phone|name|address|iban|customer/i;

export const MOLLIE_HOSTED_CANCEL_LOG_TAGS = Object.freeze({
  PRE_GET: "[MOLLIE_HOSTED_CANCEL][PRE_GET]",
  DECISION: "[MOLLIE_HOSTED_CANCEL][DECISION]",
  DELETE_SEND: "[MOLLIE_HOSTED_CANCEL][DELETE_SEND]",
  DELETE_RESULT: "[MOLLIE_HOSTED_CANCEL][DELETE_RESULT]",
  POST_GET: "[MOLLIE_HOSTED_CANCEL][POST_GET]",
  FINAL: "[MOLLIE_HOSTED_CANCEL][FINAL]",
});

function _str(v, max = 160) {
  return String(v ?? "").trim().slice(0, max);
}

function _lower(v, max = 160) {
  return _str(v, max).toLowerCase();
}

/** Read only safe cancel-wire fields from a raw Mollie payment object. */
export function readSafeMollieCancelWireFields(payment) {
  const p = payment && typeof payment === "object" ? payment : null;
  if (!p) {
    return {
      provider_status: "",
      is_cancelable: null,
    };
  }
  const status = _lower(p.status, 40);
  let isCancelable = null;
  if (Object.prototype.hasOwnProperty.call(p, "isCancelable")) {
    if (typeof p.isCancelable === "boolean") isCancelable = p.isCancelable;
    else if (typeof p.isCancelable === "string") {
      const t = p.isCancelable.trim().toLowerCase();
      if (t === "true") isCancelable = true;
      else if (t === "false") isCancelable = false;
    }
  }
  return {
    provider_status: status,
    is_cancelable: isCancelable,
  };
}

/** Extract Mollie error code/title only — never raw body / detail dumps. */
export function sanitizeMollieCancelProviderError(body) {
  const b = body && typeof body === "object" ? body : null;
  if (!b) {
    return { error_code: null, error_title: null };
  }
  const code = _str(b.status ?? b.code ?? b.error ?? b.type, 80) || null;
  const title = _str(b.title ?? b.message ?? b.detail, 120) || null;
  // Drop titles that look like they contain tokens/URLs.
  const safeTitle =
    title && !_FORBIDDEN_FIELD_RE.test(title) && !title.includes("http")
      ? title
      : title && !_FORBIDDEN_FIELD_RE.test(title)
        ? _str(title, 80)
        : null;
  return {
    error_code: code && !_FORBIDDEN_FIELD_RE.test(code) ? code : null,
    error_title: safeTitle,
  };
}

export function readMollieCredentialWireFields(credentials) {
  const c = credentials && typeof credentials === "object" ? credentials : {};
  const credentialSource =
    _str(
      c.payment_credential_source ??
        c.paymentCredentialSource ??
        c.credential_source ??
        c.credentialSource,
      40,
    ) || null;
  const mode =
    _lower(c.mode ?? c.mollie_mode ?? c.mollieMode, 16) ||
    _lower(c.keyKind ?? c.key_kind, 16) ||
    null;
  return {
    credential_source: credentialSource,
    mode: mode === "oauth" ? null : mode,
  };
}

const _ALLOWED_KEYS = new Set([
  "booking_id",
  "payment_id",
  "provider_status",
  "is_cancelable",
  "credential_source",
  "mode",
  "decision",
  "http_status",
  "ok",
  "error_code",
  "error_title",
  "result",
  "error",
  "release_owner",
  "fallback_allowed",
  "presentation_state",
  "cancel_http_ok",
]);

function _formatValue(v) {
  if (v === null || v === undefined) return "";
  if (typeof v === "boolean") return v ? "true" : "false";
  if (typeof v === "number" && Number.isFinite(v)) return String(v);
  return _str(v, 160);
}

/**
 * Build a single console line. Unknown / forbidden keys are dropped.
 */
export function formatMollieHostedCancelWireLog(tag, fields = {}) {
  const tagToken = _str(tag, 80);
  const src = fields && typeof fields === "object" ? fields : {};
  const parts = [tagToken];
  for (const key of Object.keys(src)) {
    if (!_ALLOWED_KEYS.has(key)) continue;
    if (_FORBIDDEN_FIELD_RE.test(key)) continue;
    const raw = src[key];
    if (raw === undefined) continue;
    if (typeof raw === "string" && _FORBIDDEN_FIELD_RE.test(raw) && key !== "booking_id") {
      // Never echo token-looking values outside booking/payment ids.
      if (key !== "payment_id") continue;
    }
    parts.push(`${key}=${_formatValue(raw)}`);
  }
  return parts.join(" ");
}

export function emitMollieHostedCancelWireLog(
  tag,
  fields = {},
  { log = console.log } = {},
) {
  const line = formatMollieHostedCancelWireLog(tag, fields);
  if (typeof log === "function") log(line);
  return line;
}

/** True when a formatted line appears free of secret/PII markers. */
export function assertMollieHostedCancelLogSafe(line) {
  const s = _str(line, 4000);
  if (!s.startsWith("[MOLLIE_HOSTED_CANCEL]")) return false;
  if (/authorization\s*[:=]/i.test(s)) return false;
  if (/bearer\s+[a-z0-9._-]+/i.test(s)) return false;
  if (/access_token|refresh_token|accessTokenEncrypted/i.test(s)) return false;
  if (/https?:\/\/www\.mollie\.com\/checkout/i.test(s)) return false;
  return true;
}
