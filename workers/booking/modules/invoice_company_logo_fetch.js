// FLUXIDI-INVOICE-COMPANY-LOGO-FETCH-AND-EMBED-P0-2
//
// Bounded, tenant-scoped fetch + validate + embed of the Branding & support
// company logo for invoice PDF generation.
//
// Prefer PUBLIC_MEDIA (R2) reads over network. HTTPS is allowed only for
// approved Fluxidi media origins whose path maps to this tenant's company logo.
// Never enable unrestricted INVOICE_ALLOW_EXTERNAL_LOGO_URL behavior.
//
// Diagnostics are PII-safe: no full URL, token, or customer data.

import { isUsableInvoiceLogoDataUri } from "./invoice_logo_embedded.js";

export const INVOICE_COMPANY_LOGO_MAX_BYTES = 256 * 1024;
export const INVOICE_COMPANY_LOGO_FETCH_TIMEOUT_MS = 4000;
export const INVOICE_COMPANY_LOGO_EMBED_VERSION = 1;
/** Cooldown before a temporary logo-fetch failure may be retried on open/ensure. */
export const INVOICE_COMPANY_LOGO_RETRY_COOLDOWN_MS = 15 * 60 * 1000;
/** Temporary failures — may retry after the cooldown. Permanent ones may not. */
export const INVOICE_COMPANY_LOGO_RETRYABLE_REASONS = new Set([
  "logo_fetch_timeout",
  "public_media_unavailable",
  "logo_not_found",
  "public_media_read_error",
  "public_media_unsupported_body",
  "public_media_body_error",
  "fetch_unavailable",
  "logo_load_failed",
  "https_fetch_failed",
  "redirect_host_not_approved",
]);

const PNG_MAGIC = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
const JPEG_MAGIC = [0xff, 0xd8, 0xff];
const GIF_MAGIC = [0x47, 0x49, 0x46, 0x38];
const WEBP_RIFF = [0x52, 0x49, 0x46, 0x46];

function _norm(value, max = 240) {
  const s = String(value ?? "").trim();
  if (!s) return "";
  return s.length > max ? s.slice(0, max) : s;
}

function _lower(value) {
  return _norm(value).toLowerCase();
}

function _sanitizeMediaSegment(value) {
  const raw = _lower(value, 120).replace(/[^a-z0-9._-]+/g, "-");
  return raw.replace(/^-+|-+$/g, "").slice(0, 80);
}

function _bytesStartWith(bytes, magic) {
  if (!bytes || bytes.length < magic.length) return false;
  for (let i = 0; i < magic.length; i += 1) {
    if ((bytes[i] & 0xff) !== magic[i]) return false;
  }
  return true;
}

function _toBase64(bytes) {
  if (typeof Buffer !== "undefined") {
    return Buffer.from(bytes).toString("base64");
  }
  if (typeof btoa === "function") {
    let binary = "";
    for (let i = 0; i < bytes.length; i += 1) {
      binary += String.fromCharCode(bytes[i] & 0xff);
    }
    return btoa(binary);
  }
  throw new Error("base64_unavailable");
}

function _fnv1aHex(text) {
  const s = String(text || "");
  let hash = 0x811c9dc5;
  for (let i = 0; i < s.length; i += 1) {
    hash ^= s.charCodeAt(i) & 0xff;
    hash = (hash * 0x01000193) >>> 0;
  }
  return hash.toString(16).padStart(8, "0");
}

async function _sha256Hex(bytes) {
  const subtle =
    typeof globalThis !== "undefined" &&
    globalThis.crypto &&
    globalThis.crypto.subtle
      ? globalThis.crypto.subtle
      : null;
  if (subtle && typeof subtle.digest === "function") {
    const digest = await subtle.digest("SHA-256", bytes);
    return [...new Uint8Array(digest)]
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");
  }
  // Deterministic non-crypto fallback for older Node test hosts.
  let hash = 0x811c9dc5;
  for (let i = 0; i < bytes.length; i += 1) {
    hash ^= bytes[i] & 0xff;
    hash = (hash * 0x01000193) >>> 0;
  }
  // Expand to 64 hex chars for a stable fingerprint shape.
  const seed = hash.toString(16).padStart(8, "0");
  return `${seed}${seed}${seed}${seed}${seed}${seed}${seed}${seed}`;
}

function _looksLikeHtml(bytes) {
  const head = new TextDecoder("utf-8", { fatal: false })
    .decode(bytes.slice(0, Math.min(bytes.length, 128)))
    .trim()
    .toLowerCase();
  return (
    head.startsWith("<!doctype html") ||
    head.startsWith("<html") ||
    head.startsWith("<head") ||
    head.startsWith("<body") ||
    (head.startsWith("<") && !head.startsWith("<?xml") && !head.includes("<svg"))
  );
}

/**
 * Detect renderer-supported image MIME from magic bytes.
 * Returns null when unsupported / corrupt / HTML masquerading as an image.
 */
export function classifyInvoiceLogoImageBytes(bytes) {
  if (!bytes || !(bytes instanceof Uint8Array) || bytes.length < 8) return null;
  if (_looksLikeHtml(bytes)) return null;
  if (_bytesStartWith(bytes, PNG_MAGIC)) return "image/png";
  if (_bytesStartWith(bytes, JPEG_MAGIC)) return "image/jpeg";
  if (_bytesStartWith(bytes, GIF_MAGIC)) return "image/gif";
  if (
    _bytesStartWith(bytes, WEBP_RIFF) &&
    bytes.length > 11 &&
    String.fromCharCode(bytes[8], bytes[9], bytes[10], bytes[11]) === "WEBP"
  ) {
    return "image/webp";
  }
  // SVG is not accepted from remote company uploads for invoice embed (path
  // geometry monogram is packaged separately). Reject ambiguous payloads.
  return null;
}

export function bytesToInvoiceLogoDataUri(bytes, mime) {
  const safeMime = _lower(mime);
  if (!safeMime.startsWith("image/")) return "";
  if (!bytes || !bytes.length) return "";
  return `data:${safeMime};base64,${_toBase64(bytes)}`;
}

/** True for IPv4 private / loopback / link-local / metadata ranges. */
export function isBlockedInvoiceLogoIp(hostname) {
  const host = _lower(hostname);
  if (!host) return true;
  if (host === "localhost" || host.endsWith(".localhost")) return true;
  if (host === "metadata.google.internal") return true;
  const m = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(host);
  if (!m) return false;
  const parts = m.slice(1).map((p) => Number(p));
  if (parts.some((n) => !Number.isInteger(n) || n < 0 || n > 255)) return true;
  const [a, b] = parts;
  if (a === 10) return true;
  if (a === 127) return true;
  if (a === 0) return true;
  if (a === 169 && b === 254) return true;
  if (a === 172 && b >= 16 && b <= 31) return true;
  if (a === 192 && b === 168) return true;
  if (a === 100 && b >= 64 && b <= 127) return true; // CGNAT
  return false;
}

/**
 * Approved Fluxidi media hosts only. Never arbitrary CDNs.
 */
export function isApprovedInvoiceLogoMediaHost(hostname, env = null) {
  const host = _lower(hostname);
  if (!host || isBlockedInvoiceLogoIp(host)) return false;
  if (host.endsWith(".fluxidi.workers.dev") || host === "fluxidi.workers.dev") {
    return true;
  }
  if (host === "fluxidi.be" || host.endsWith(".fluxidi.be")) return true;
  const extra = String(env?.INVOICE_MEDIA_APPROVED_HOSTS || "")
    .split(",")
    .map((s) => _lower(s))
    .filter(Boolean);
  return extra.includes(host);
}

/**
 * Parse a company-logo media reference into a tenant-scoped R2 key.
 *
 * Accepts:
 *   - public-media/{tenant}/{company}/company/logo.{ext}
 *   - /public/media/public-media/{tenant}/{company}/company/logo.{ext}
 *   - https://{approved}/public/media/public-media/{tenant}/{company}/company/logo.{ext}
 *
 * Rejects hero/vehicle/driver/gallery paths and cross-tenant keys.
 */
/**
 * Shape-only parse (host/path/key). Optionally enforce issuer tenant/company.
 */
export function parseApprovedCompanyLogoMediaKey(
  rawRef,
  {
    tenantId = "",
    companyId = "",
    env = null,
    requireIssuerScope = true,
  } = {},
) {
  const raw = _norm(rawRef, 2000);
  if (!raw) {
    return { ok: false, reason: "missing_ref" };
  }
  const lower = raw.toLowerCase();
  if (lower.startsWith("data:")) {
    return { ok: false, reason: "data_uri_not_fetchable" };
  }
  if (lower.startsWith("assets/") || lower.includes("fluxidi_logo.png")) {
    return { ok: false, reason: "theme_or_packaged_asset" };
  }
  if (lower.includes("inelivia")) {
    return { ok: false, reason: "rejected_wordmark" };
  }

  let pathPart = "";
  let host = "";
  if (lower.startsWith("https://") || lower.startsWith("http://")) {
    if (!lower.startsWith("https://")) {
      return { ok: false, reason: "https_required" };
    }
    let url;
    try {
      url = new URL(raw);
    } catch {
      return { ok: false, reason: "invalid_url" };
    }
    host = _lower(url.hostname);
    if (!isApprovedInvoiceLogoMediaHost(host, env)) {
      return { ok: false, reason: "host_not_approved" };
    }
    if (isBlockedInvoiceLogoIp(host)) {
      return { ok: false, reason: "blocked_address" };
    }
    if (url.username || url.password) {
      return { ok: false, reason: "credentials_forbidden" };
    }
    pathPart = url.pathname || "";
  } else if (lower.startsWith("/public/media/")) {
    pathPart = raw;
  } else if (lower.startsWith("public-media/")) {
    pathPart = `/public/media/${raw}`;
  } else {
    return { ok: false, reason: "unsupported_ref_shape" };
  }

  const marker = "/public/media/";
  const idx = pathPart.toLowerCase().indexOf(marker);
  if (idx < 0) {
    return { ok: false, reason: "missing_public_media_path" };
  }
  const encodedKey = pathPart.slice(idx + marker.length);
  let key = "";
  try {
    key = encodedKey
      .split("/")
      .filter((s) => s.length > 0)
      .map((s) => decodeURIComponent(s))
      .join("/");
  } catch {
    return { ok: false, reason: "invalid_media_key_encoding" };
  }
  if (!key.startsWith("public-media/")) {
    return { ok: false, reason: "invalid_media_key_prefix" };
  }
  if (key.includes("..") || key.includes("\\") || key.includes("\0")) {
    return { ok: false, reason: "invalid_media_key" };
  }

  // public-media/{tenant}/{company}/company/logo.{ext}
  const parts = key.split("/");
  if (parts.length !== 5) {
    return { ok: false, reason: "unexpected_key_depth" };
  }
  const [, keyTenant, keyCompany, folder, fileName] = parts;
  if (folder !== "company") {
    return { ok: false, reason: "not_company_logo_path" };
  }
  if (!/^logo\.(png|jpe?g|webp|gif)$/i.test(fileName || "")) {
    // Hero / other company media must never become the invoice logo.
    return { ok: false, reason: "not_company_logo_file" };
  }

  const gotTenant = _sanitizeMediaSegment(keyTenant);
  const gotCompany = _sanitizeMediaSegment(keyCompany);
  if (!gotTenant || !gotCompany) {
    return { ok: false, reason: "invalid_key_scope" };
  }

  if (requireIssuerScope) {
    const wantTenant = _sanitizeMediaSegment(tenantId);
    const wantCompany = _sanitizeMediaSegment(companyId);
    if (!wantTenant || !wantCompany) {
      return { ok: false, reason: "missing_issuer_scope" };
    }
    if (gotTenant !== wantTenant || gotCompany !== wantCompany) {
      return { ok: false, reason: "tenant_scope_mismatch" };
    }
  }

  return {
    ok: true,
    key,
    tenantId: gotTenant,
    companyId: gotCompany,
    fileName,
    host: host || null,
    keyFingerprint: `k${_fnv1aHex(key)}`,
  };
}

export function isUsableInvoiceLogoEmbed(embed) {
  if (!embed || typeof embed !== "object") return false;
  if (embed.failed === true || embed.ok === false) return false;
  const uri = _norm(embed.data_uri ?? embed.dataUri, 400000);
  return uri.startsWith("data:image/") && isUsableInvoiceLogoDataUri(uri);
}

export function buildFailedInvoiceLogoEmbedRecord({
  reason = "embed_failed",
  keyFingerprint = null,
  frozenAt = null,
} = {}) {
  return {
    version: INVOICE_COMPANY_LOGO_EMBED_VERSION,
    failed: true,
    reason: _norm(reason, 80) || "embed_failed",
    frozen_at: _norm(frozenAt) || new Date().toISOString(),
    source_key_fp: _norm(keyFingerprint, 20) || null,
  };
}

/**
 * Build a PII-safe immutable logo embed record (no full URL / token).
 */
export function buildInvoiceLogoEmbedRecord({
  dataUri,
  sha256,
  mime,
  sourceKind,
  keyFingerprint,
  frozenAt = null,
} = {}) {
  const uri = _norm(dataUri, 400000);
  if (!isUsableInvoiceLogoDataUri(uri)) return null;
  return {
    version: INVOICE_COMPANY_LOGO_EMBED_VERSION,
    sha256: _norm(sha256, 80),
    mime: _norm(mime, 40),
    data_uri: uri,
    frozen_at: _norm(frozenAt) || new Date().toISOString(),
    source_kind: _norm(sourceKind, 40) || "unknown",
    source_key_fp: _norm(keyFingerprint, 20) || null,
  };
}

/**
 * Read a previously frozen embed from booking / Document Core envelopes.
 * Existing freeze always wins (idempotent history).
 */
export function readFrozenInvoiceLogoEmbed({
  bookingRecord = null,
  issuedDocument = null,
} = {}) {
  const doc =
    issuedDocument && typeof issuedDocument === "object" ? issuedDocument : {};
  const rec =
    bookingRecord && typeof bookingRecord === "object" ? bookingRecord : {};
  const candidates = [
    doc.seller_logo_embed,
    doc.sellerLogoEmbed,
    rec.invoice_logo_embed,
    rec.invoiceLogoEmbed,
    rec.booking?.invoice_logo_embed,
    rec.booking?.invoiceLogoEmbed,
  ];
  for (const c of candidates) {
    if (isUsableInvoiceLogoEmbed(c)) return c;
  }
  return null;
}

/**
 * Read any logo-embed attempt record (success or failed) for refresh gating.
 */
export function readInvoiceLogoEmbedAttempt({
  bookingRecord = null,
  issuedDocument = null,
} = {}) {
  const frozen = readFrozenInvoiceLogoEmbed({ bookingRecord, issuedDocument });
  if (frozen) return frozen;
  const doc =
    issuedDocument && typeof issuedDocument === "object" ? issuedDocument : {};
  const rec =
    bookingRecord && typeof bookingRecord === "object" ? bookingRecord : {};
  const candidates = [
    doc.seller_logo_embed,
    doc.sellerLogoEmbed,
    rec.invoice_logo_embed,
    rec.invoiceLogoEmbed,
    rec.booking?.invoice_logo_embed,
    rec.booking?.invoiceLogoEmbed,
  ];
  for (const c of candidates) {
    if (c && typeof c === "object" && (c.failed === true || c.attempted === true)) {
      return c;
    }
  }
  return null;
}

function _fail(reason, extra = {}) {
  return {
    ok: false,
    embedded: false,
    fetched: false,
    reason: _norm(reason, 80) || "embed_failed",
    data_uri: "",
    embed: null,
    diagnostic: {
      reason: _norm(reason, 80) || "embed_failed",
      ...extra,
    },
  };
}

async function _readPublicMediaObject(env, key, maxBytes) {
  if (!env?.PUBLIC_MEDIA || typeof env.PUBLIC_MEDIA.get !== "function") {
    return { ok: false, reason: "public_media_unavailable" };
  }
  let object;
  try {
    object = await env.PUBLIC_MEDIA.get(key);
  } catch {
    return { ok: false, reason: "public_media_read_error" };
  }
  if (!object) return { ok: false, reason: "logo_not_found" };

  let bytes;
  try {
    if (typeof object.arrayBuffer === "function") {
      const buf = await object.arrayBuffer();
      bytes = new Uint8Array(buf);
    } else if (object.body && typeof object.body.getReader === "function") {
      const reader = object.body.getReader();
      const chunks = [];
      let total = 0;
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        if (!value) continue;
        total += value.length;
        if (total > maxBytes) {
          try {
            reader.cancel();
          } catch {
            /* ignore */
          }
          return { ok: false, reason: "logo_too_large" };
        }
        chunks.push(value);
      }
      bytes = new Uint8Array(total);
      let offset = 0;
      for (const chunk of chunks) {
        bytes.set(chunk, offset);
        offset += chunk.length;
      }
    } else {
      return { ok: false, reason: "public_media_unsupported_body" };
    }
  } catch {
    return { ok: false, reason: "public_media_body_error" };
  }

  if (!bytes || bytes.length < 8) {
    return { ok: false, reason: "logo_empty" };
  }
  if (bytes.length > maxBytes) {
    return { ok: false, reason: "logo_too_large" };
  }
  const headerType = _lower(
    object.httpMetadata?.contentType ||
      object.httpMetadata?.content_type ||
      "",
    80,
  );
  return { ok: true, bytes, headerType, sourceKind: "public_media_r2" };
}

async function _fetchApprovedHttpsLogo({
  url,
  env,
  maxBytes,
  timeoutMs,
  fetchImpl,
}) {
  const fetchFn =
    typeof fetchImpl === "function"
      ? fetchImpl
      : typeof fetch === "function"
        ? fetch
        : null;
  if (!fetchFn) return { ok: false, reason: "fetch_unavailable" };

  let current = _norm(url, 2000);
  for (let hop = 0; hop < 3; hop += 1) {
    const shape = parseApprovedCompanyLogoMediaKey(current, {
      env,
      requireIssuerScope: false,
    });
    if (!shape.ok && hop === 0) {
      // First hop must already be an approved company-logo media URL.
      return { ok: false, reason: shape.reason || "ref_rejected" };
    }
    let urlObj;
    try {
      urlObj = new URL(current);
    } catch {
      return { ok: false, reason: "invalid_url" };
    }
    if (urlObj.protocol !== "https:") {
      return { ok: false, reason: "https_required" };
    }
    if (!isApprovedInvoiceLogoMediaHost(urlObj.hostname, env)) {
      return { ok: false, reason: "redirect_host_not_approved" };
    }
    if (isBlockedInvoiceLogoIp(urlObj.hostname)) {
      return { ok: false, reason: "blocked_address" };
    }
    if (hop > 0 && !shape.ok) {
      return { ok: false, reason: shape.reason || "redirect_path_rejected" };
    }

    const controller =
      typeof AbortController === "function" ? new AbortController() : null;
    const timer =
      controller && typeof setTimeout === "function"
        ? setTimeout(() => controller.abort(), timeoutMs)
        : null;
    let response;
    try {
      response = await fetchFn(current, {
        method: "GET",
        redirect: "manual",
        signal: controller?.signal,
        headers: { Accept: "image/png,image/jpeg,image/webp,image/gif" },
      });
    } catch (err) {
      const name = _lower(err?.name || err?.message);
      if (name.includes("abort")) {
        return { ok: false, reason: "logo_fetch_timeout" };
      }
      return { ok: false, reason: "logo_fetch_error" };
    } finally {
      if (timer) clearTimeout(timer);
    }

    const status = Number(response?.status || 0);
    if (status >= 300 && status < 400) {
      const location = _norm(response.headers?.get?.("location"), 2000);
      if (!location) return { ok: false, reason: "redirect_missing_location" };
      try {
        current = new URL(location, current).toString();
      } catch {
        return { ok: false, reason: "redirect_invalid" };
      }
      continue;
    }
    if (status !== 200) {
      return { ok: false, reason: `logo_http_${status || "error"}` };
    }

    const contentType = _lower(response.headers?.get?.("content-type"), 80);
    if (contentType.includes("text/html") || contentType.includes("application/json")) {
      return { ok: false, reason: "logo_wrong_mime" };
    }

    let bytes;
    try {
      const buf = await response.arrayBuffer();
      bytes = new Uint8Array(buf);
    } catch {
      return { ok: false, reason: "logo_body_error" };
    }
    if (!bytes || bytes.length < 8) return { ok: false, reason: "logo_empty" };
    if (bytes.length > maxBytes) return { ok: false, reason: "logo_too_large" };

    return {
      ok: true,
      bytes,
      headerType: contentType,
      sourceKind: "https_approved",
      finalUrl: current,
    };
  }
  return { ok: false, reason: "redirect_limit" };
}

/**
 * Resolve the canonical company logo into a renderer-safe data URI.
 *
 * Priority:
 *   1) already-frozen embed (zero network / R2)
 *   2) usable data URI already on the seller profile
 *   3) PUBLIC_MEDIA get for approved company logo key
 *   4) bounded HTTPS fetch of the same approved media URL
 *
 * Failures never throw — callers fall back to company-name + Fluxidi monogram.
 */
export async function resolveAndEmbedInvoiceCompanyLogo({
  env = null,
  logoRef = "",
  tenantId = "",
  companyId = "",
  existingEmbed = null,
  fetchImpl = null,
  maxBytes = INVOICE_COMPANY_LOGO_MAX_BYTES,
  timeoutMs = INVOICE_COMPANY_LOGO_FETCH_TIMEOUT_MS,
  nowIso = null,
} = {}) {
  if (isUsableInvoiceLogoEmbed(existingEmbed)) {
    return {
      ok: true,
      embedded: true,
      fetched: false,
      reason: "reuse_frozen_embed",
      data_uri: existingEmbed.data_uri || existingEmbed.dataUri,
      embed: existingEmbed,
      diagnostic: { reason: "reuse_frozen_embed" },
    };
  }

  const ref = _norm(logoRef, 2000);
  if (!ref) return _fail("missing_logo_ref");

  if (ref.toLowerCase().startsWith("data:image/")) {
    if (!isUsableInvoiceLogoDataUri(ref)) {
      return _fail("corrupt_data_uri");
    }
    // Decode for sha fingerprint without re-fetch.
    const m = /^data:(image\/[a-z0-9.+-]+);base64,([A-Za-z0-9+/=\s]+)$/i.exec(
      ref,
    );
    let bytes = null;
    try {
      if (typeof Buffer !== "undefined") {
        bytes = new Uint8Array(Buffer.from(m[2].replace(/\s+/g, ""), "base64"));
      }
    } catch {
      bytes = null;
    }
    const mime = classifyInvoiceLogoImageBytes(bytes) || _lower(m?.[1]);
    if (!mime || !bytes) {
      // Still usable per isUsableInvoiceLogoDataUri — keep as-is.
      const embed = buildInvoiceLogoEmbedRecord({
        dataUri: ref,
        sha256: `uri${_fnv1aHex(ref)}`,
        mime: _lower(m?.[1]) || "image/*",
        sourceKind: "data_uri",
        keyFingerprint: null,
        frozenAt: nowIso,
      });
      return {
        ok: true,
        embedded: true,
        fetched: false,
        reason: "data_uri_ready",
        data_uri: ref,
        embed,
        diagnostic: { reason: "data_uri_ready" },
      };
    }
    const sha256 = await _sha256Hex(bytes);
    const embed = buildInvoiceLogoEmbedRecord({
      dataUri: ref,
      sha256,
      mime,
      sourceKind: "data_uri",
      keyFingerprint: null,
      frozenAt: nowIso,
    });
    return {
      ok: true,
      embedded: true,
      fetched: false,
      reason: "data_uri_ready",
      data_uri: ref,
      embed,
      diagnostic: { reason: "data_uri_ready" },
    };
  }

  const parsed = parseApprovedCompanyLogoMediaKey(ref, {
    tenantId,
    companyId,
    env,
  });
  if (!parsed.ok) {
    return _fail(parsed.reason || "ref_rejected", {
      key_fp: parsed.keyFingerprint || null,
    });
  }

  let loaded = await _readPublicMediaObject(env, parsed.key, maxBytes);
  if (!loaded.ok) {
    const retryable =
      loaded.reason === "public_media_unavailable" ||
      loaded.reason === "logo_not_found" ||
      loaded.reason === "public_media_read_error" ||
      loaded.reason === "public_media_unsupported_body" ||
      loaded.reason === "public_media_body_error";
    if (retryable && ref.toLowerCase().startsWith("https://")) {
      // Scope-safe HTTPS fallback (tests / missing binding). Re-validate final URL.
      loaded = await _fetchApprovedHttpsLogo({
        url: ref,
        env,
        maxBytes,
        timeoutMs,
        fetchImpl,
      });
      if (loaded.ok && loaded.finalUrl) {
        const finalParsed = parseApprovedCompanyLogoMediaKey(loaded.finalUrl, {
          tenantId,
          companyId,
          env,
        });
        if (!finalParsed.ok) {
          return _fail(finalParsed.reason || "redirect_scope_rejected");
        }
      }
    }
  }
  if (!loaded.ok) {
    return _fail(loaded.reason || "logo_load_failed", {
      key_fp: parsed.keyFingerprint,
    });
  }

  const magicMime = classifyInvoiceLogoImageBytes(loaded.bytes);
  if (!magicMime) {
    return _fail("logo_magic_mismatch", { key_fp: parsed.keyFingerprint });
  }
  const header = _lower(loaded.headerType);
  if (
    header &&
    !header.includes("octet-stream") &&
    !header.includes(magicMime) &&
    !(magicMime === "image/jpeg" && header.includes("image/jpg"))
  ) {
    // Header claims a different family than magic bytes.
    if (header.startsWith("image/") && !header.includes(magicMime.split("/")[1])) {
      return _fail("logo_mime_mismatch", { key_fp: parsed.keyFingerprint });
    }
  }

  const dataUri = bytesToInvoiceLogoDataUri(loaded.bytes, magicMime);
  if (!isUsableInvoiceLogoDataUri(dataUri)) {
    return _fail("logo_unusable_after_embed", { key_fp: parsed.keyFingerprint });
  }
  const sha256 = await _sha256Hex(loaded.bytes);
  const embed = buildInvoiceLogoEmbedRecord({
    dataUri,
    sha256,
    mime: magicMime,
    sourceKind: loaded.sourceKind,
    keyFingerprint: parsed.keyFingerprint,
    frozenAt: nowIso,
  });
  return {
    ok: true,
    embedded: true,
    fetched: loaded.sourceKind === "https_approved",
    reason: "embedded",
    data_uri: dataUri,
    embed,
    diagnostic: {
      reason: "embedded",
      key_fp: parsed.keyFingerprint,
      mime: magicMime,
      bytes: loaded.bytes.length,
      source_kind: loaded.sourceKind,
    },
  };
}

/**
 * Whether a prior failed embed attempt may be retried (bounded).
 * Permanent invalid-logo failures stay suppressed; temporary ones cool down.
 */
export function invoiceLogoEmbedAllowsRetry(existingEmbed, nowMs = Date.now()) {
  if (!existingEmbed || typeof existingEmbed !== "object") return true;
  if (isUsableInvoiceLogoEmbed(existingEmbed)) return false;
  if (existingEmbed.failed !== true && existingEmbed.attempted !== true) {
    return true;
  }
  const reason = _norm(existingEmbed.reason, 80);
  if (!INVOICE_COMPANY_LOGO_RETRYABLE_REASONS.has(reason)) {
    return false;
  }
  const frozenAt = Date.parse(String(existingEmbed.frozen_at || ""));
  if (!Number.isFinite(frozenAt)) return true;
  return nowMs - frozenAt >= INVOICE_COMPANY_LOGO_RETRY_COOLDOWN_MS;
}

/**
 * True when projection still needs a one-shot company-logo embed.
 * Used by the authenticated single-invoice open/ensure path — never bulk.
 */
export function invoiceNeedsCompanyLogoEmbed({
  sellerLogoRef = "",
  existingEmbed = null,
  tenantId = "",
  companyId = "",
  env = null,
  nowMs = Date.now(),
} = {}) {
  if (isUsableInvoiceLogoEmbed(existingEmbed)) return false;
  // Prior failed attempts: permanent failures stay suppressed; temporary ones
  // may retry after INVOICE_COMPANY_LOGO_RETRY_COOLDOWN_MS (never every open).
  if (
    existingEmbed &&
    typeof existingEmbed === "object" &&
    (existingEmbed.failed === true || existingEmbed.attempted === true) &&
    !invoiceLogoEmbedAllowsRetry(existingEmbed, nowMs)
  ) {
    return false;
  }
  const ref = _norm(sellerLogoRef, 2000);
  if (!ref) return false;
  if (ref.toLowerCase().startsWith("data:image/")) {
    return !isUsableInvoiceLogoDataUri(ref);
  }
  const parsed = parseApprovedCompanyLogoMediaKey(ref, {
    tenantId,
    companyId,
    env,
  });
  return parsed.ok === true;
}

/** Compact PII-safe log line for logo embed outcomes. */
export function formatInvoiceLogoEmbedDiagnostic(diag = null) {
  const d = diag && typeof diag === "object" ? diag : {};
  const reason = _norm(d.reason, 80) || "unknown";
  const keyFp = _norm(d.key_fp ?? d.keyFingerprint, 20);
  const mime = _norm(d.mime, 40);
  const bytes = Number.isFinite(Number(d.bytes)) ? String(Math.trunc(d.bytes)) : "";
  const source = _norm(d.source_kind, 40);
  return [
    "[INVOICE_LOGO_EMBED]",
    `reason=${reason}`,
    keyFp ? `key_fp=${keyFp}` : null,
    mime ? `mime=${mime}` : null,
    bytes ? `bytes=${bytes}` : null,
    source ? `source=${source}` : null,
  ]
    .filter(Boolean)
    .join(" ");
}
