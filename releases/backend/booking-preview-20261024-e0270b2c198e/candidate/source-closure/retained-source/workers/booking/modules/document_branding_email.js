// FLUXIDI-CANONICAL-DOCUMENT-AND-EMAIL-BRANDING-SOURCE-OF-TRUTH-P0-1
//
// Pure helpers for invoice/document email branding. Fluxidi owns delivery via
// Resend; Billit does not render customer invoice emails.
//
// Logo in HTML uses an inline CID MIME part built from the frozen invoice logo
// embed (or the packaged Fluxidi monogram). Never depends on a live remote URL.

import {
  buildFluxidiInvoiceLogoDataUri,
  isUsableInvoiceLogoDataUri,
} from "./invoice_logo_embedded.js";

export const DOCUMENT_BRANDING_EMAIL_LOGO_CID = "fluxidi-company-logo";
export const DOCUMENT_BRANDING_SNAPSHOT_VERSION = "document_branding_v1";

function _norm(v, max = 500) {
  return String(v ?? "").trim().slice(0, max);
}

/**
 * Decode a usable `data:image/...;base64,...` into raw bytes + mime.
 * Returns null when the URI is missing/corrupt (callers fall back).
 */
export function decodeInvoiceLogoDataUriToBytes(dataUri) {
  const raw = _norm(dataUri, 6_000_000);
  if (!isUsableInvoiceLogoDataUri(raw)) return null;
  const m = /^data:(image\/[a-z0-9.+-]+);base64,([A-Za-z0-9+/=\s]+)$/i.exec(raw);
  if (!m) return null;
  const mime = String(m[1] || "").toLowerCase();
  const b64 = String(m[2] || "").replace(/\s+/g, "");
  try {
    if (typeof Buffer !== "undefined") {
      const buf = Buffer.from(b64, "base64");
      if (!buf.length) return null;
      return { bytes: new Uint8Array(buf), mime, base64: b64 };
    }
  } catch {
    return null;
  }
  return null;
}

function _mimeToExt(mime) {
  const m = _norm(mime, 64).toLowerCase();
  if (m.includes("png")) return "png";
  if (m.includes("jpeg") || m.includes("jpg")) return "jpg";
  if (m.includes("webp")) return "webp";
  if (m.includes("gif")) return "gif";
  if (m.includes("svg")) return "svg";
  return "png";
}

/**
 * Build a Resend-compatible inline logo attachment + HTML img tag.
 *
 * Priority:
 *   1) frozen invoice logo embed data URI
 *   2) packaged Fluxidi monogram
 *
 * Logo failure returns htmlImg="" and attachment=null so email still sends
 * with company name in the text body.
 */
export function buildDocumentEmailInlineLogo({
  logoDataUri = "",
  companyName = "",
  contentId = DOCUMENT_BRANDING_EMAIL_LOGO_CID,
} = {}) {
  const cid = _norm(contentId, 120) || DOCUMENT_BRANDING_EMAIL_LOGO_CID;
  const alt = _norm(companyName, 160) || "Company";
  let decoded = decodeInvoiceLogoDataUriToBytes(logoDataUri);
  let source = "frozen_embed";
  if (!decoded) {
    decoded = decodeInvoiceLogoDataUriToBytes(buildFluxidiInvoiceLogoDataUri());
    source = "fluxidi_fallback";
  }
  if (!decoded) {
    return {
      ok: false,
      htmlImg: "",
      attachment: null,
      source: "none",
      contentId: cid,
    };
  }
  const ext = _mimeToExt(decoded.mime);
  return {
    ok: true,
    htmlImg: `<img src="cid:${cid}" alt="${_escapeHtml(alt)}" width="160" style="max-width:160px;height:auto;display:block;margin:0 0 12px 0;border:0" />`,
    attachment: {
      filename: `company-logo.${ext}`,
      content: decoded.base64,
      content_id: cid,
      content_type: decoded.mime,
    },
    source,
    contentId: cid,
  };
}

/**
 * Canonical document-branding snapshot projection for emails / diagnostics.
 * Never includes raw media URLs or secrets.
 */
export function buildDocumentBrandingSnapshotSummary({
  tenantId = "",
  companyId = "",
  companyName = "",
  logoEmbed = null,
  snapshotVersion = DOCUMENT_BRANDING_SNAPSHOT_VERSION,
} = {}) {
  const embed =
    logoEmbed && typeof logoEmbed === "object" && !Array.isArray(logoEmbed)
      ? logoEmbed
      : null;
  const sha = _norm(embed?.sha256 || embed?.sha || "", 128);
  const mime = _norm(embed?.mime || embed?.content_type || "", 64);
  const hasUsable =
    !!sha &&
    isUsableInvoiceLogoDataUri(
      _norm(embed?.data_uri || embed?.dataUri || "", 6_000_000),
    );
  return {
    schema_version: snapshotVersion,
    tenant_id: _norm(tenantId, 128) || null,
    company_id: _norm(companyId, 128) || null,
    company_name: _norm(companyName, 160) || null,
    logo_sha256: sha || null,
    logo_mime: mime || null,
    logo_usable: hasUsable,
    source_kind: _norm(embed?.source_kind || embed?.sourceKind || "", 64) || null,
  };
}

/**
 * Build HTML + text bodies for a Fluxidi-sent invoice email.
 */
export function buildInvoiceEmailBodies({
  invoiceNumber = "",
  brandName = "",
  legalName = "",
  footerLine = "",
  hasAttachment = true,
  logoHtml = "",
} = {}) {
  const inv = _norm(invoiceNumber, 120) || "—";
  const brand = _norm(brandName, 160) || "Fluxidi";
  const legal = _norm(legalName, 160) || brand;
  const footer = _norm(footerLine, 500) || legal;
  const invoiceMessage = hasAttachment
    ? `In bijlage vindt u uw factuur van ${_escapeHtml(brand)}.`
    : "Uw betaling werd ontvangen, maar de factuur-PDF kon niet automatisch als bijlage worden toegevoegd. Neem contact op indien u de PDF nodig heeft.";
  const htmlBody = `
    <div style="font-family:system-ui,-apple-system,Segoe UI,Roboto,Arial;line-height:1.6">
      ${logoHtml || ""}
      <h2 style="margin:0 0 10px">Factuur ${_escapeHtml(inv)}</h2>
      <p style="margin:0 0 12px;color:#444">
        ${invoiceMessage}
      </p>
      <p style="margin:12px 0 0;color:#666;font-size:12px">
        ${_escapeHtml(footer)}
      </p>
    </div>
  `.trim();
  const textBody = [
    `${brand}`,
    ``,
    `Factuur ${inv}`,
    ``,
    hasAttachment
      ? `In bijlage vindt u uw factuur van ${brand}.`
      : `Uw betaling werd ontvangen, maar de factuur-PDF kon niet automatisch als bijlage worden toegevoegd.`,
    ``,
    footer,
  ].join("\n");
  return { htmlBody, textBody };
}

function _escapeHtml(value) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}
