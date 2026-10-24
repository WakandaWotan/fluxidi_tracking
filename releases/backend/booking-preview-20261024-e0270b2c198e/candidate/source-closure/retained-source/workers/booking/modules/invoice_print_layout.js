// FLUXIDI-INVOICE-PDF-PAGINATION-LOGO-ADDRESS-AND-ZOOM-P0-1
//
// Print-layout constants and CSS for customer invoice HTML→PDF.
// Keeps short invoices on one A4 page without shrinking body text.

/** A4 height at 96 CSS dpi (210mm × 297mm). */
export const A4_HEIGHT_CSS_PX = 1123;

/** Default @page margin used with PDFShift / print CSS. */
export const INVOICE_PAGE_MARGIN_MM = 10;

/** Printable A4 height after 10mm top+bottom margins. */
export const A4_PRINTABLE_HEIGHT_CSS_PX = Math.round(
  A4_HEIGHT_CSS_PX - (INVOICE_PAGE_MARGIN_MM * 2 * 96) / 25.4,
);

/**
 * CSS height for the embedded logo. The packaged SVG is 320×72; stretching it
 * to 160px previously forced a ~711px-wide image that crushed the seller
 * column and overflowed onto a near-empty page 2.
 */
export const INVOICE_LOGO_CSS_HEIGHT_PX = 48;

/** Legacy (buggy) logo CSS height — retained for proof tests only. */
export const LEGACY_INVOICE_LOGO_CSS_HEIGHT_PX = 160;

/**
 * Estimate content height for a normal short street invoice (1 line item).
 * Used to prove pagination risk before/after the logo/chrome fix.
 */
export function estimateShortInvoiceContentHeightPx({
  logoCssHeightPx = INVOICE_LOGO_CSS_HEIGHT_PX,
  logoIntrinsicWidth = 320,
  logoIntrinsicHeight = 72,
  contentColumnPx = 730,
  wrapperMarginPx = 0,
  wrapperPaddingPx = 16,
  leadingSpacerPx = 0,
  sellerLines = 6,
  gapPx = 16,
} = {}) {
  const renderedLogoWidth =
    logoIntrinsicHeight > 0
      ? (logoCssHeightPx * logoIntrinsicWidth) / logoIntrinsicHeight
      : logoCssHeightPx;
  // When the scaled logo consumes nearly the full column, flex leaves a
  // razor-thin company column that word-wraps into a tall tower — the field
  // failure that pushed the VAT disclaimer onto an almost-empty page 2.
  const companyColumnWidth = Math.max(
    0,
    contentColumnPx - renderedLogoWidth - gapPx,
  );
  const approxCharPx = 7;
  const charsPerLine = Math.max(1, Math.floor(companyColumnWidth / approxCharPx));
  const avgCharsPerSellerLine = 28;
  const wrappedSellerLines =
    companyColumnWidth < contentColumnPx * 0.35
      ? sellerLines * Math.ceil(avgCharsPerSellerLine / charsPerLine)
      : sellerLines;
  const companyTowerPx = Math.max(
    logoCssHeightPx,
    wrappedSellerLines * 18 + 24,
  );
  const headerPx = companyTowerPx + 16; // border + padding-bottom
  const chrome =
    leadingSpacerPx +
    wrapperMarginPx * 2 +
    wrapperPaddingPx * 2 +
    headerPx +
    22 + // header margin-bottom
    40 + // h1
    200 + // meta blocks
    120 + // table
    90 + // totals
    56; // footer (kept with totals)
  return Math.round(chrome);
}

export function shortInvoiceFitsOneA4Page(opts = {}) {
  return (
    estimateShortInvoiceContentHeightPx(opts) <= A4_PRINTABLE_HEIGHT_CSS_PX
  );
}

/**
 * Total inter-block vertical spacing the compact composition spends between the
 * header and the footer, in CSS px.
 *
 * The one-page fix only removed the oversized logo; the page still read as
 * sparse because these gaps were tuned for a two-page layout. This is asserted
 * by tests so the spacing cannot silently drift back up.
 */
export const INVOICE_COMPACT_BLOCK_SPACING_PX = Object.freeze({
  headerPaddingBottom: 8,
  headerMarginBottom: 12,
  titleMarginBottom: 10,
  metaMarginBottom: 10,
  tableMarginTop: 6,
  totalsMarginTop: 10,
  footerMarginTop: 12,
});

/** Legacy (sparse) spacing, retained for before/after proof tests only. */
export const LEGACY_INVOICE_BLOCK_SPACING_PX = Object.freeze({
  headerPaddingBottom: 10,
  headerMarginBottom: 16,
  titleMarginBottom: 12,
  metaMarginBottom: 14,
  tableMarginTop: 12,
  totalsMarginTop: 14,
  footerMarginTop: 18,
});

export function totalInvoiceBlockSpacingPx(spacing) {
  return Object.values(spacing).reduce((sum, v) => sum + Number(v || 0), 0);
}

/** Shared invoice print CSS injected into renderInvoiceHtml. */
export function buildInvoicePrintCss({
  logoHeightPx = INVOICE_LOGO_CSS_HEIGHT_PX,
  pageMarginMm = INVOICE_PAGE_MARGIN_MM,
} = {}) {
  const logoH = Math.max(32, Math.min(72, Number(logoHeightPx) || 48));
  const margin = Number.isFinite(Number(pageMarginMm))
    ? Number(pageMarginMm)
    : 10;
  return `
  @page {
    size: A4;
    margin: ${margin}mm;
  }

  body {
    font-family: Arial, Helvetica, sans-serif;
    background: #ffffff;
    margin: 0;
    padding: 0;
    color: #111;
  }

  .invoice-wrapper {
    max-width: 100%;
    margin: 0 auto;
    padding: 12px 8px;
    border: none;
    box-sizing: border-box;
  }

  .header {
    display: flex;
    justify-content: space-between;
    align-items: flex-start;
    border-bottom: 2px solid #f0c400;
    padding-bottom: 8px;
    margin-bottom: 12px;
    gap: 12px;
  }

  .logo {
    flex: 0 1 auto;
    max-width: 42%;
  }

  .logo img {
    height: ${logoH}px;
    max-width: 100%;
    width: auto;
    object-fit: contain;
    display: block;
  }

  .company-info {
    flex: 1 1 auto;
    text-align: right;
    font-size: 12px;
    line-height: 1.45;
    min-width: 0;
  }

  h1 { font-size: 21px; margin: 0 0 10px 0; }

  .meta {
    display: flex;
    justify-content: space-between;
    margin-bottom: 10px;
    font-size: 13px;
    gap: 14px;
  }

  .box { width: 48%; }
  .box strong { display: block; margin-bottom: 6px; }
  .meta small { color: #444; display:block; margin-top:6px; line-height:1.45; }

  .pill {
    display: inline-block;
    padding: 3px 8px;
    border-radius: 999px;
    background: #fff6cc;
    border: 1px solid #f0c400;
    font-size: 11px;
    margin-left: 6px;
  }

  /* Compact composition: the order line follows the metadata directly instead
     of leaving a large empty band in the middle of the page. */
  table { width: 100%; border-collapse: collapse; margin-top: 6px; }

  table th {
    background: #f5f5f5;
    text-align: left;
    padding: 8px;
    font-size: 13px;
    border-bottom: 2px solid #ddd;
  }

  table td {
    padding: 8px;
    font-size: 13px;
    border-bottom: 1px solid #eee;
    vertical-align: top;
  }

  .muted { color: #555; }
  .right { text-align:right; }
  .mono { font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace; }

  .totals {
    margin-top: 10px;
    width: 100%;
    max-width: 340px;
    margin-left: auto;
    page-break-inside: avoid;
    break-inside: avoid;
  }

  .totals td { padding: 5px 8px; }
  .totals tr:last-child td {
    font-weight: bold;
    font-size: 15px;
    border-top: 2px solid #000;
  }

  .closing {
    page-break-inside: avoid;
    break-inside: avoid;
  }

  .footer {
    margin-top: 12px;
    font-size: 11px;
    color: #555;
    text-align: center;
    line-height: 1.5;
    page-break-inside: avoid;
    break-inside: avoid;
  }

  thead { display: table-header-group; }
  tr { page-break-inside: avoid; break-inside: avoid; }
`.trim();
}
