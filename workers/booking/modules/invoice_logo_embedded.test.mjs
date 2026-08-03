// FLUXIDI-STREET-INVOICE-PICKUP-AND-EMBEDDED-LOGO-P0-1
import { test } from "node:test";
import assert from "node:assert/strict";

import {
  FLUXIDI_INVOICE_LOGO_SVG,
  buildFluxidiInvoiceLogoDataUri,
  resolveInvoiceLogoSrc,
  packagedInvoiceLogoSvgByteLength,
} from "./invoice_logo_embedded.js";

test("packaged logo is a data URI (no network)", () => {
  const uri = buildFluxidiInvoiceLogoDataUri();
  assert.ok(uri.startsWith("data:image/svg+xml;base64,"));
  assert.ok(FLUXIDI_INVOICE_LOGO_SVG.includes("Fluxidi"));
  assert.ok(packagedInvoiceLogoSvgByteLength() < 2048);
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

test("company data URI wins over packaged fallback", () => {
  const company = "data:image/png;base64,AAAA";
  const src = resolveInvoiceLogoSrc({
    profileLogoUrl: company,
    sellerBrand: "Fluxidi",
  });
  assert.equal(src, company);
});

test("invalid external URL is not used when HTTPS disallowed; Fluxidi still embeds", () => {
  const src = resolveInvoiceLogoSrc({
    publicLogoUrl: "https://cdn.broken.example/missing.png",
    sellerBrand: "Christophe Vanrokeghem",
    allowExternalHttpsLogo: false,
  });
  assert.ok(src.startsWith("data:image/"));
});

test("non-Fluxidi seller without embedded logo omits (no broken src)", () => {
  const src = resolveInvoiceLogoSrc({
    publicLogoUrl: "https://other-tenant.example/logo.png",
    sellerBrand: "Other Taxi BV",
    allowExternalHttpsLogo: false,
  });
  assert.equal(src, "");
});

test("HTTPS allowed only when intentionally enabled", () => {
  const src = resolveInvoiceLogoSrc({
    publicLogoUrl: "https://other-tenant.example/logo.png",
    sellerBrand: "Other Taxi",
    allowExternalHttpsLogo: true,
  });
  assert.equal(src, "https://other-tenant.example/logo.png");
});
