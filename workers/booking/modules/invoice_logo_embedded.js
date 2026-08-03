// FLUXIDI-STREET-INVOICE-PICKUP-AND-EMBEDDED-LOGO-P0-1
//
// Compact invoice-safe Fluxidi wordmark packaged as a data URI so PDFShift
// never needs a network fetch for the default seller logo. This is NOT the
// 2.3MB Flutter asset — it is a tiny SVG (~1KB) suitable for worker bundling.
//
// Never log or print the raw data URI in operational summaries.

/** Compact monochrome Fluxidi wordmark (SVG) for invoice PDF embedding. */
export const FLUXIDI_INVOICE_LOGO_SVG = `<svg xmlns="http://www.w3.org/2000/svg" width="320" height="72" viewBox="0 0 320 72" role="img" aria-label="Fluxidi"><rect width="320" height="72" fill="none"/><circle cx="28" cy="36" r="18" fill="#111111"/><path d="M22 28h12v3.2H25.6V34H33v3.1H25.6v5.7H22V28z" fill="#FFFFFF"/><text x="58" y="46" font-family="Arial, Helvetica, sans-serif" font-size="34" font-weight="700" fill="#111111" letter-spacing="0.5">Fluxidi</text></svg>`;

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

/** data:image/svg+xml;base64,… — safe for <img src> without network. */
export function buildFluxidiInvoiceLogoDataUri() {
  return `data:image/svg+xml;base64,${_toBase64Utf8(FLUXIDI_INVOICE_LOGO_SVG)}`;
}

/**
 * Resolve the logo URL for invoice HTML.
 * Priority:
 *   1) company/profile/env logo when it is already a data URI (embedded)
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
    if (c.startsWith("data:image/")) return c;
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
      packagedDataUri.startsWith("data:image/")
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
