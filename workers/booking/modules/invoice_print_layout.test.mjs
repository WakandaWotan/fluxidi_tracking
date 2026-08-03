// FLUXIDI-INVOICE-PDF-PAGINATION-LOGO-ADDRESS-AND-ZOOM-P0-1
import { test } from "node:test";
import assert from "node:assert/strict";

import {
  A4_PRINTABLE_HEIGHT_CSS_PX,
  LEGACY_INVOICE_LOGO_CSS_HEIGHT_PX,
  INVOICE_LOGO_CSS_HEIGHT_PX,
  buildInvoicePrintCss,
  estimateShortInvoiceContentHeightPx,
  shortInvoiceFitsOneA4Page,
} from "./invoice_print_layout.js";

test("PROOF: legacy 160px logo overflows A4 printable height (two-page root cause)", () => {
  const legacyH = estimateShortInvoiceContentHeightPx({
    logoCssHeightPx: LEGACY_INVOICE_LOGO_CSS_HEIGHT_PX,
    wrapperMarginPx: 36,
    wrapperPaddingPx: 32,
    leadingSpacerPx: 18,
  });
  assert.ok(
    legacyH > A4_PRINTABLE_HEIGHT_CSS_PX,
    `legacy height ${legacyH}px should exceed printable ${A4_PRINTABLE_HEIGHT_CSS_PX}px`,
  );
  assert.equal(
    shortInvoiceFitsOneA4Page({
      logoCssHeightPx: LEGACY_INVOICE_LOGO_CSS_HEIGHT_PX,
      wrapperMarginPx: 36,
      wrapperPaddingPx: 32,
      leadingSpacerPx: 18,
    }),
    false,
  );
});

test("fixed 48px logo + tight chrome fits one A4 page", () => {
  const h = estimateShortInvoiceContentHeightPx({
    logoCssHeightPx: INVOICE_LOGO_CSS_HEIGHT_PX,
    wrapperMarginPx: 0,
    wrapperPaddingPx: 16,
    leadingSpacerPx: 0,
  });
  assert.ok(
    h <= A4_PRINTABLE_HEIGHT_CSS_PX,
    `fixed height ${h}px must fit printable ${A4_PRINTABLE_HEIGHT_CSS_PX}px`,
  );
  assert.equal(shortInvoiceFitsOneA4Page(), true);
});

test("print CSS keeps logo bounded, @page A4, and footer with totals", () => {
  const css = buildInvoicePrintCss();
  assert.match(css, /@page\s*\{[^}]*size:\s*A4/i);
  assert.match(css, /\.logo img\s*\{[^}]*height:\s*48px/i);
  assert.match(css, /\.closing\s*\{[^}]*page-break-inside:\s*avoid/i);
  assert.match(css, /\.footer\s*\{[^}]*page-break-inside:\s*avoid/i);
  assert.match(css, /\.totals\s*\{[^}]*page-break-inside:\s*avoid/i);
  assert.doesNotMatch(css, /height:\s*160px/);
});
