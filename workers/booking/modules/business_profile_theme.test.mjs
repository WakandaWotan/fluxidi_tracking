import { test } from "node:test";
import assert from "node:assert/strict";
import {
  incomingHasBusinessTheme,
  normalizeBusinessThemeDocument,
  preserveBusinessThemeFields,
  projectBusinessThemeFields,
} from "./business_profile_theme.mjs";

test("omitted theme fields keep the stored company theme", () => {
  const existing = {
    companyName: "Fluxidi Demo Fleet",
    business_theme: {
      variant: "corporateBlue",
      updatedAt: "2026-09-11T10:00:00.000Z",
    },
  };
  const incoming = { companyName: "Fluxidi Demo Fleet", phone: "+3227110000" };
  assert.equal(incomingHasBusinessTheme(incoming), false);
  const preserved = preserveBusinessThemeFields(existing, incoming);
  assert.equal(preserved.business_theme.variant, "corporateBlue");
  assert.equal(preserved.business_theme_variant, "corporateBlue");
});

test("explicit theme write stays authoritative", () => {
  const existing = {
    business_theme: { variant: "executiveGold", updatedAt: "2026-09-10T10:00:00.000Z" },
  };
  const incoming = {
    business_theme: {
      variant: "cleanProfessional",
      updatedAt: "2026-09-11T12:00:00.000Z",
    },
  };
  const preserved = preserveBusinessThemeFields(existing, incoming);
  assert.equal(preserved.business_theme.variant, "cleanProfessional");
  const projected = projectBusinessThemeFields(preserved);
  assert.equal(projected.business_theme_variant, "cleanProfessional");
});

test("custom Brand Signature colors stay on the existing theme document", () => {
  const incoming = {
    business_theme: {
      variant: "brandSignatureGold",
      updatedAt: "2026-09-11T12:00:00.000Z",
      brandSignaturePalette: { argb: 4279834905, hex: "#152044" },
      publishedCustomerTheme: "nightGold",
    },
    business_theme_variant: "brandSignatureGold",
    published_customer_theme: "nightGold",
  };
  const document = normalizeBusinessThemeDocument(incoming);
  assert.equal(document.variant, "brandSignatureGold");
  assert.equal(document.brandSignaturePalette.hex, "#152044");
  assert.equal(document.publishedCustomerTheme, "nightGold");
  const projected = projectBusinessThemeFields(incoming);
  assert.equal(projected.business_theme_variant, "brandSignatureGold");
  assert.equal(projected.business_theme.publishedCustomerTheme, "nightGold");
});

test("empty profile does not invent a default theme", () => {
  assert.equal(normalizeBusinessThemeDocument({ companyName: "Fluxidi" }), null);
  assert.deepEqual(projectBusinessThemeFields({ companyName: "Fluxidi" }), {});
});
