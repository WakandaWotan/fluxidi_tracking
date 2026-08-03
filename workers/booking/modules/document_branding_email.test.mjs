// FLUXIDI-CANONICAL-DOCUMENT-AND-EMAIL-BRANDING-SOURCE-OF-TRUTH-P0-1
//
//   node --test workers/booking/modules/document_branding_email.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import {
  buildDocumentEmailInlineLogo,
  buildInvoiceEmailBodies,
  buildDocumentBrandingSnapshotSummary,
  decodeInvoiceLogoDataUriToBytes,
  DOCUMENT_BRANDING_EMAIL_LOGO_CID,
} from "./document_branding_email.js";
import { buildFluxidiInvoiceLogoDataUri } from "./invoice_logo_embedded.js";

const PNG_1X1 =
  "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==";

test("19) email HTML contains frozen company logo as CID part", () => {
  const built = buildDocumentEmailInlineLogo({
    logoDataUri: PNG_1X1,
    companyName: "Taxi Demo",
  });
  assert.equal(built.ok, true);
  assert.match(built.htmlImg, new RegExp(`cid:${DOCUMENT_BRANDING_EMAIL_LOGO_CID}`));
  assert.equal(built.attachment.content_id, DOCUMENT_BRANDING_EMAIL_LOGO_CID);
  assert.ok(built.attachment.content.length > 20);
  assert.equal(built.source, "frozen_embed");
});

test("20) HTML references the correct CID", () => {
  const built = buildDocumentEmailInlineLogo({
    logoDataUri: PNG_1X1,
    companyName: "Taxi Demo",
  });
  assert.match(built.htmlImg, /src="cid:fluxidi-company-logo"/);
  assert.match(built.htmlImg, /alt="Taxi Demo"/);
});

test("21) text fallback contains the correct company identity", () => {
  const bodies = buildInvoiceEmailBodies({
    invoiceNumber: "INV-2026-000099",
    brandName: "Taxi Demo",
    legalName: "Taxi Demo BV",
    footerLine: "Taxi Demo BV — BTW BE0123",
    hasAttachment: true,
    logoHtml: "",
  });
  assert.match(bodies.textBody, /Taxi Demo/);
  assert.match(bodies.textBody, /INV-2026-000099/);
  assert.match(bodies.htmlBody, /Factuur INV-2026-000099/);
});

test("27) logo failure does not prevent invoice email delivery body", () => {
  const built = buildDocumentEmailInlineLogo({
    logoDataUri: "not-a-data-uri",
    companyName: "Taxi Demo",
  });
  // Falls back to packaged Fluxidi monogram — still ok for delivery.
  assert.equal(built.ok, true);
  assert.equal(built.source, "fluxidi_fallback");
  const bodies = buildInvoiceEmailBodies({
    invoiceNumber: "INV-1",
    brandName: "Taxi Demo",
    legalName: "Taxi Demo",
    hasAttachment: true,
    logoHtml: built.htmlImg,
  });
  assert.match(bodies.htmlBody, /Taxi Demo/);
  assert.match(bodies.textBody, /Taxi Demo/);
});

test("28+29) email branding has no theme/gallery remote URL dependency", () => {
  const built = buildDocumentEmailInlineLogo({
    logoDataUri: PNG_1X1,
    companyName: "Taxi Demo",
  });
  assert.equal(built.htmlImg.includes("http://"), false);
  assert.equal(built.htmlImg.includes("https://"), false);
  assert.equal(JSON.stringify(built.attachment).includes("http"), false);
});

test("30) snapshot summary has no secrets or raw media URLs", () => {
  const summary = buildDocumentBrandingSnapshotSummary({
    tenantId: "t1",
    companyId: "c1",
    companyName: "Taxi Demo",
    logoEmbed: {
      sha256: "abc123",
      mime: "image/png",
      data_uri: PNG_1X1,
      source_kind: "https_approved",
    },
  });
  assert.equal(summary.logo_usable, true);
  assert.equal(summary.logo_sha256, "abc123");
  const raw = JSON.stringify(summary);
  assert.equal(raw.includes("data:image"), false);
  assert.equal(raw.includes("Bearer"), false);
  assert.equal(raw.includes("RESEND"), false);
});

test("31) Billit is not the delivery owner in Fluxidi email helpers", () => {
  // Documented contract: these helpers only build Fluxidi/Resend payloads.
  const bodies = buildInvoiceEmailBodies({
    invoiceNumber: "INV-1",
    brandName: "Taxi Demo",
    hasAttachment: true,
  });
  assert.equal(bodies.htmlBody.toLowerCase().includes("billit"), false);
  assert.equal(bodies.textBody.toLowerCase().includes("billit"), false);
});

test("decode rejects corrupt data URIs", () => {
  assert.equal(decodeInvoiceLogoDataUriToBytes(""), null);
  assert.equal(decodeInvoiceLogoDataUriToBytes("data:text/html;base64,PGh0bWw+"), null);
  assert.ok(decodeInvoiceLogoDataUriToBytes(buildFluxidiInvoiceLogoDataUri()));
});

test("no INELIVIA in fallback email logo path", () => {
  const built = buildDocumentEmailInlineLogo({
    logoDataUri: "",
    companyName: "Taxi Demo",
  });
  assert.equal(built.ok, true);
  assert.equal(JSON.stringify(built).toLowerCase().includes("inelivia"), false);
});
