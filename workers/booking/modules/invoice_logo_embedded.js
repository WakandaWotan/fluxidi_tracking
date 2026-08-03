// FLUXIDI-INVOICE-PDF-PAGINATION-LOGO-ADDRESS-AND-ZOOM-P0-1
//
// Compact invoice-safe Fluxidi wordmark packaged as a data URI so PDFShift
// never needs a network fetch for the default seller logo.
//
// Uses path geometry only (no SVG <text>) because PDF HTML→PDF engines often
// drop or fail <text> glyphs and show a broken-image placeholder.
//
// Never log or print the raw data URI in operational summaries.

/**
 * Compact monochrome Fluxidi wordmark (SVG paths only — no <text>).
 * viewBox sized for CSS height ~48px without crowding the seller column.
 */
export const FLUXIDI_INVOICE_LOGO_SVG = `<svg xmlns="http://www.w3.org/2000/svg" width="280" height="56" viewBox="0 0 280 56" role="img" aria-label="Fluxidi"><rect width="280" height="56" fill="none"/><circle cx="24" cy="28" r="16" fill="#111111"/><path fill="#FFFFFF" d="M18.2 20.5h10.6v2.7H21.5v2.2h6.5v2.6H21.5v4.9h-3.3V20.5z"/><path fill="#111111" d="M48 18.2h3.2v19.6H48zm7.4 0h3.1l7.6 12.4V18.2h3.1v19.6h-3.1l-7.6-12.4v12.4h-3.1zm17.8 0h12.2v2.8h-9v5.2h8.2v2.7h-8.2v6.1h9.2v2.8H73.2zm16.6 0h3.2v16.8h8.4v2.8H89.8zm15.2 0h3.2v19.6h-3.2zm7.2 0h3.4l4.6 12.8 4.6-12.8h3.4l-6.6 19.6h-2.8zm16.8 0h3.2v19.6h-3.2zm5.6 9.6c0-6.2 4.4-10 10.2-10 5.8 0 10.2 3.8 10.2 10s-4.4 10-10.2 10c-5.8 0-10.2-3.8-10.2-10zm3.3 0c0 4.4 2.8 7.1 6.9 7.1s6.9-2.7 6.9-7.1-2.8-7.1-6.9-7.1-6.9 2.7-6.9 7.1zm20.1-9.6h3.2l7.2 19.6h-3.3l-1.5-4.2h-8.1l-1.5 4.2h-3.2zm1.6 12.6h5.5l-2.7-7.6z"/></svg>`;

function _toBase64Utf8(text) {
  // Prefer Buffer in Node tests; fall back to btoa for Workers.
  if (typeof Buffer !== "undefined") {
    return Buffer.from(String(text), "utf8").toString("base64");
  }
  if (typeof btoa === "function") {
    const bytes = new TextEncoder().encode(String(text));
    let binary = "";
    for (let i = 0; i < bytes.length; i += 1) binary += String.fromCharCode(bytes[i]);
    return btoa(binary);
  }
  throw new Error("base64_unavailable");
}

function _fromBase64(b64) {
  const cleaned = String(b64 || "").replace(/\s+/g, "");
  if (!cleaned) return null;
  try {
    if (typeof Buffer !== "undefined") {
      return Buffer.from(cleaned, "base64");
    }
    if (typeof atob === "function") {
      const bin = atob(cleaned);
      const out = new Uint8Array(bin.length);
      for (let i = 0; i < bin.length; i += 1) out[i] = bin.charCodeAt(i);
      return out;
    }
  } catch {
    return null;
  }
  return null;
}

function _bytesStartWith(bytes, magic) {
  if (!bytes || bytes.length < magic.length) return false;
  for (let i = 0; i < magic.length; i += 1) {
    if ((bytes[i] & 0xff) !== magic[i]) return false;
  }
  return true;
}

/**
 * True when a data URI looks like a renderer-safe embedded image.
 * Rejects empty/corrupt payloads that would render as a broken-image icon.
 */
export function isUsableInvoiceLogoDataUri(raw) {
  const s = String(raw || "").trim();
  const m = /^data:(image\/[a-z0-9.+-]+);base64,([A-Za-z0-9+/=\s]+)$/i.exec(s);
  if (!m) return false;
  const mime = m[1].toLowerCase();
  const bytes = _fromBase64(m[2]);
  if (!bytes || bytes.length < 8) return false;

  if (mime.includes("svg")) {
    const head = new TextDecoder().decode(bytes.slice(0, Math.min(bytes.length, 256)));
    return /<svg[\s>]/i.test(head);
  }
  if (mime.includes("png")) {
    return _bytesStartWith(bytes, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  }
  if (mime.includes("jpeg") || mime.includes("jpg")) {
    return _bytesStartWith(bytes, [0xff, 0xd8, 0xff]);
  }
  if (mime.includes("gif")) {
    return _bytesStartWith(bytes, [0x47, 0x49, 0x46, 0x38]);
  }
  if (mime.includes("webp")) {
    return (
      _bytesStartWith(bytes, [0x52, 0x49, 0x46, 0x46]) &&
      bytes.length > 11 &&
      String.fromCharCode(bytes[8], bytes[9], bytes[10], bytes[11]) === "WEBP"
    );
  }
  // Unknown image/* — accept only if payload is reasonably large.
  return bytes.length >= 32;
}

/** data:image/svg+xml;base64,… — safe for <img src> without network. */
export function buildFluxidiInvoiceLogoDataUri() {
  return `data:image/svg+xml;base64,${_toBase64Utf8(FLUXIDI_INVOICE_LOGO_SVG)}`;
}

/**
 * Resolve the logo URL for invoice HTML.
 * Priority:
 *   1) company/profile/env logo when it is a usable embedded data URI
 *   2) packaged Fluxidi embedded fallback when seller is Fluxidi
 *   3) HTTPS company/env logo only when allowExternalHttpsLogo === true
 *   4) otherwise empty (omit <img>, never broken src)
 */
export function resolveInvoiceLogoSrc({
  profileLogoUrl = "",
  publicLogoUrl = "",
  envLogoUrl = "",
  envLogoDataUri = "",
  dataLogoUrl = "",
  sellerBrand = "",
  allowExternalHttpsLogo = false,
  packagedDataUri = null,
} = {}) {
  const candidates = [
    String(profileLogoUrl || "").trim(),
    String(publicLogoUrl || "").trim(),
    String(envLogoDataUri || "").trim(),
    String(dataLogoUrl || "").trim(),
    String(envLogoUrl || "").trim(),
  ].filter(Boolean);

  for (const c of candidates) {
    if (c.startsWith("data:image/") && isUsableInvoiceLogoDataUri(c)) return c;
  }

  const brand = String(sellerBrand || "").trim().toLowerCase();
  const isFluxidiSeller =
    !brand ||
    brand === "fluxidi" ||
    brand.includes("fluxidi") ||
    brand.includes("vanrokeghem");

  if (isFluxidiSeller) {
    const packaged =
      typeof packagedDataUri === "string" &&
      isUsableInvoiceLogoDataUri(packagedDataUri)
        ? packagedDataUri
        : buildFluxidiInvoiceLogoDataUri();
    if (packaged) return packaged;
  }

  if (allowExternalHttpsLogo) {
    for (const c of candidates) {
      if (c.startsWith("https://") || c.startsWith("http://")) return c;
    }
  }
  return "";
}

/** Approximate UTF-8 byte size of the packaged SVG source (not the data URI). */
export function packagedInvoiceLogoSvgByteLength() {
  return new TextEncoder().encode(FLUXIDI_INVOICE_LOGO_SVG).length;
}

/** True when the packaged mark relies on path geometry (no SVG text nodes). */
export function packagedInvoiceLogoUsesPathWordmark() {
  return (
    /<path[\s>]/i.test(FLUXIDI_INVOICE_LOGO_SVG) &&
    !/<text[\s>]/i.test(FLUXIDI_INVOICE_LOGO_SVG)
  );
}
