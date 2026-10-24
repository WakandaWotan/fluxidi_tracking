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
 * Fluxidi emblem: an "F" monogram inside a filled disc. Geometry only — no
 * <text>, and deliberately no letter-shaped wordmark.
 *
 * FLUXIDI-CANONICAL-COMPANY-LOGO-AND-INVOICE-PRESENTATION-P0-1: the previous
 * version carried a hand-authored "wordmark" whose glyph paths did not spell
 * FLUXIDI. Decoded left to right its sub-paths draw I, N, E, L, I, V, I, O, A,
 * so every invoice rendered the monogram followed by the nonsense string
 * "INELIVIA". Letter shapes are not authored by hand here again: the seller name
 * is real HTML text in the invoice header, which no PDF engine can garble.
 */
export const FLUXIDI_INVOICE_LOGO_SVG = `<svg xmlns="http://www.w3.org/2000/svg" width="56" height="56" viewBox="0 0 56 56" role="img" aria-label="Fluxidi"><rect width="56" height="56" fill="none"/><circle cx="28" cy="28" r="26" fill="#111111"/><path fill="#F0C400" d="M20.5 15.5h17v5.4H26.4v5.1h9.9v5.3H26.4v14.2h-5.9V15.5z"/></svg>`;

/**
 * Sub-path shapes that spelled the bogus "INELIVIA" wordmark.
 *
 * Kept only so a regression test can assert they never come back.
 */
export const REJECTED_INVOICE_LOGO_WORDMARK_MARKERS = Object.freeze([
  "M48 18.2h3.2v19.6H48z",
  "h3.1l7.6 12.4V18.2h3.1v19.6h-3.1l-7.6-12.4v12.4h-3.1z",
  "h12.2v2.8h-9v5.2h8.2v2.7h-8.2v6.1h9.2v2.8H73.2z",
]);

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
 *   2) packaged Fluxidi embedded fallback when no usable company logo exists
 *   3) HTTPS company/env logo only when allowExternalHttpsLogo === true
 *      (legacy escape hatch — prefer server-side fetch+embed instead)
 *   4) otherwise empty (omit <img>, never broken src)
 *
 * FLUXIDI-INVOICE-COMPANY-LOGO-FETCH-AND-EMBED-P0-2: HTTPS company logos must
 * be fetched and converted to a data URI *before* this resolver runs. This
 * function never performs network I/O.
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

  const packaged =
    typeof packagedDataUri === "string" &&
    isUsableInvoiceLogoDataUri(packagedDataUri)
      ? packagedDataUri
      : buildFluxidiInvoiceLogoDataUri();

  // Prefer the packaged Fluxidi monogram over a live HTTPS <img src> so PDF
  // viewing never depends on network. Company HTTPS must be embedded upstream.
  if (packaged) {
    // Only skip packaged fallback when an explicit external HTTPS escape hatch
    // is enabled *and* the seller is not relying on Fluxidi branding defaults.
    const brand = String(sellerBrand || "").trim().toLowerCase();
    const isFluxidiSeller =
      !brand ||
      brand === "fluxidi" ||
      brand.includes("fluxidi") ||
      brand.includes("vanrokeghem");

    if (!allowExternalHttpsLogo || isFluxidiSeller) {
      return packaged;
    }
  }

  if (allowExternalHttpsLogo) {
    for (const c of candidates) {
      if (c.startsWith("https://") || c.startsWith("http://")) return c;
    }
  }
  return packaged || "";
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

/**
 * True when the packaged mark is a geometry-only emblem: no <text> nodes and
 * none of the hand-authored letter paths that rendered as "INELIVIA".
 */
export function packagedInvoiceLogoIsGeometryOnly() {
  if (/<text[\s>]/i.test(FLUXIDI_INVOICE_LOGO_SVG)) return false;
  if (!/<path[\s>]/i.test(FLUXIDI_INVOICE_LOGO_SVG)) return false;
  return !REJECTED_INVOICE_LOGO_WORDMARK_MARKERS.some((marker) =>
    FLUXIDI_INVOICE_LOGO_SVG.includes(marker),
  );
}
