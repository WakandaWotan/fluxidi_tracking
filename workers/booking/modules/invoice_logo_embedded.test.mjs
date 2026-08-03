// FLUXIDI-STREET-INVOICE-PICKUP-AND-EMBEDDED-LOGO-P0-1
// FLUXIDI-INVOICE-PDF-PAGINATION-LOGO-ADDRESS-AND-ZOOM-P0-1
import { test } from "node:test";
import assert from "node:assert/strict";

import {
  FLUXIDI_INVOICE_LOGO_SVG,
  buildFluxidiInvoiceLogoDataUri,
  resolveInvoiceLogoSrc,
  packagedInvoiceLogoSvgByteLength,
  packagedInvoiceLogoUsesPathWordmark,
  isUsableInvoiceLogoDataUri,
} from "./invoice_logo_embedded.js";

test("packaged logo is a data URI (no network)", () => {
  const uri = buildFluxidiInvoiceLogoDataUri();
  assert.ok(uri.startsWith("data:image/svg+xml;base64,"));
  assert.ok(FLUXIDI_INVOICE_LOGO_SVG.toLowerCase().includes("fluxidi") || FLUXIDI_INVOICE_LOGO_SVG.includes("aria-label=\"Fluxidi\""));
  assert.ok(packagedInvoiceLogoSvgByteLength() < 4096);
  assert.equal(uri.includes("https://"), false);
  assert.equal(uri.includes("http://"), false);
});

test("packaged logo uses path wordmark (no SVG text — PDF-safe)", () => {
  assert.equal(packagedInvoiceLogoUsesPathWordmark(), true);
  assert.equal(/<text[\s>]/i.test(FLUXIDI_INVOICE_LOGO_SVG), false);
  assert.ok(isUsableInvoiceLogoDataUri(buildFluxidiInvoiceLogoDataUri()));
});

test("Fluxidi seller uses packaged embedded logo when only HTTPS is configured", () => {
  const src = resolveInvoiceLogoSrc({
    publicLogoUrl: "https://example.com/logo.png",
    sellerBrand: "Fluxidi",
    allowExternalHttpsLogo: false,
  });
  assert.ok(src.startsWith("data:image/svg+xml;base64,"));
  assert.equal(src.includes("https://"), false);
});

test("usable company data URI wins over packaged fallback", () => {
  // Minimal valid 1×1 PNG
  const company =
    "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==";
  assert.equal(isUsableInvoiceLogoDataUri(company), true);
  const src = resolveInvoiceLogoSrc({
    profileLogoUrl: company,
    sellerBrand: "Fluxidi",
  });
  assert.equal(src, company);
});

test("corrupt company data URI is skipped — Fluxidi packaged fallback used", () => {
  const src = resolveInvoiceLogoSrc({
    profileLogoUrl: "data:image/png;base64,AAAA",
    sellerBrand: "Fluxidi",
  });
  assert.ok(src.startsWith("data:image/svg+xml;base64,"));
  assert.equal(isUsableInvoiceLogoDataUri("data:image/png;base64,AAAA"), false);
});

test("invalid external URL is not used when HTTPS disallowed; Fluxidi still embeds", () => {
  const src = resolveInvoiceLogoSrc({
    publicLogoUrl: "https://cdn.broken.example/missing.png",
    sellerBrand: "Christophe Vanrokeghem",
    allowExternalHttpsLogo: false,
  });
  assert.ok(src.startsWith("data:image/"));
});

test("non-Fluxidi seller without embedded logo uses Fluxidi monogram (never broken src)", () => {
  const src = resolveInvoiceLogoSrc({
    publicLogoUrl: "https://other-tenant.example/logo.png",
    sellerBrand: "Other Taxi BV",
    allowExternalHttpsLogo: false,
  });
  assert.ok(src.startsWith("data:image/"));
  assert.equal(isUsableInvoiceLogoDataUri(src), true);
});

test("HTTPS allowed only when intentionally enabled", () => {
  const src = resolveInvoiceLogoSrc({
    publicLogoUrl: "https://other-tenant.example/logo.png",
    sellerBrand: "Other Taxi",
    allowExternalHttpsLogo: true,
  });
  assert.equal(src, "https://other-tenant.example/logo.png");
});
