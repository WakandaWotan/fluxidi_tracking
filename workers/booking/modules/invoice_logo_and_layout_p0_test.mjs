/* FLUXIDI-CANONICAL-COMPANY-LOGO-AND-INVOICE-PRESENTATION-P0-1
 *
 * Field failures pinned here:
 *  - invoice PDFs rendered the nonsense wordmark "INELIVIA" instead of FLUXIDI,
 *    because the packaged SVG carried hand-authored letter paths that spelled
 *    I, N, E, L, I, V, I, O, A;
 *  - the company's own uploaded logo never reached invoice generation, so no
 *    logo snapshot existed on issued invoices;
 *  - the one-page layout still read as sparse.
 *
 *   node --test workers/booking/modules/invoice_logo_and_layout_p0_test.mjs
 */

import { test } from "node:test";
import assert from "node:assert/strict";

import {
  FLUXIDI_INVOICE_LOGO_SVG,
  REJECTED_INVOICE_LOGO_WORDMARK_MARKERS,
  buildFluxidiInvoiceLogoDataUri,
  isUsableInvoiceLogoDataUri,
  packagedInvoiceLogoIsGeometryOnly,
  resolveInvoiceLogoSrc,
} from "./invoice_logo_embedded.js";
import {
  buildInvoicePrintCss,
  shortInvoiceFitsOneA4Page,
  INVOICE_COMPACT_BLOCK_SPACING_PX,
  LEGACY_INVOICE_BLOCK_SPACING_PX,
  totalInvoiceBlockSpacingPx,
} from "./invoice_print_layout.js";
import {
  buildStreetInvoicePdfProjectionRevision,
  fingerprintSellerLogoRef,
  STREET_INVOICE_PDF_PROJECTION_VERSION,
} from "./street_invoice_pdf_projection.js";
import {
  buildSellerSnapshotFromBusinessProfile,
  sellerSnapshotLogoRefFromProfile,
} from "./seller_identity.js";

const COMPANY_LOGO_URL =
  "https://fluxidi-booking-api.fluxidi.workers.dev/public/media/public-media/tenant/a/logo.png";
// 1x1 transparent PNG.
const COMPANY_LOGO_DATA_URI =
  "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==";

test("A) the packaged mark no longer carries the INELIVIA wordmark", () => {
  // Each marker below is one of the bogus letter sub-paths from the regression.
  for (const marker of REJECTED_INVOICE_LOGO_WORDMARK_MARKERS) {
    assert.equal(
      FLUXIDI_INVOICE_LOGO_SVG.includes(marker),
      false,
      `packaged mark still contains a bogus wordmark path: ${marker.slice(0, 24)}…`,
    );
  }
  assert.equal(packagedInvoiceLogoIsGeometryOnly(), true);
  assert.match(FLUXIDI_INVOICE_LOGO_SVG, /<svg[\s>]/i);
  assert.doesNotMatch(FLUXIDI_INVOICE_LOGO_SVG, /<text[\s>]/i);
});

test("B) the packaged mark contains no letter glyphs at all", () => {
  // A geometry-only emblem: one disc plus one monogram path. Anything more is a
  // hand-authored wordmark, which is exactly what garbled into "INELIVIA".
  const paths = FLUXIDI_INVOICE_LOGO_SVG.match(/<path\b/gi) || [];
  assert.equal(paths.length, 1, "expected exactly one monogram path");
  assert.doesNotMatch(FLUXIDI_INVOICE_LOGO_SVG, /INELIVIA/i);
  assert.doesNotMatch(FLUXIDI_INVOICE_LOGO_SVG, /<tspan[\s>]/i);
  assert.doesNotMatch(FLUXIDI_INVOICE_LOGO_SVG, /font-family/i);
});

test("C) the packaged data URI stays renderer-safe and bounded", () => {
  const uri = buildFluxidiInvoiceLogoDataUri();
  assert.equal(isUsableInvoiceLogoDataUri(uri), true);
  assert.match(uri, /^data:image\/svg\+xml;base64,/);
  assert.equal(uri.startsWith("http"), false, "no external URL dependency");
  assert.equal(uri.length < 4000, true, "embedded mark must stay compact");
});

test("D) a usable company logo data URI outranks the Fluxidi fallback", () => {
  const src = resolveInvoiceLogoSrc({
    profileLogoUrl: COMPANY_LOGO_DATA_URI,
    sellerBrand: "Wakanda Wotan BVBA",
    packagedDataUri: buildFluxidiInvoiceLogoDataUri(),
  });
  assert.equal(src, COMPANY_LOGO_DATA_URI);
});

test("E) a corrupt company logo falls back safely, never to a broken src", () => {
  const src = resolveInvoiceLogoSrc({
    profileLogoUrl: "data:image/png;base64,####not-base64####",
    sellerBrand: "Fluxidi",
    packagedDataUri: buildFluxidiInvoiceLogoDataUri(),
  });
  assert.equal(isUsableInvoiceLogoDataUri(src), true);
  assert.equal(src.startsWith("data:image/"), true);
});

test("F) an external https logo is never used as a live <img src> by default", () => {
  const src = resolveInvoiceLogoSrc({
    profileLogoUrl: COMPANY_LOGO_URL,
    sellerBrand: "Some Other Company BVBA",
  });
  // Without server-side embed, fall back to the packaged monogram — never a
  // network-dependent https src that can render a broken image.
  assert.equal(src.startsWith("data:image/"), true);
  assert.equal(src.includes("https://"), false);

  const allowed = resolveInvoiceLogoSrc({
    profileLogoUrl: COMPANY_LOGO_URL,
    sellerBrand: "Some Other Company BVBA",
    allowExternalHttpsLogo: true,
  });
  assert.equal(allowed, COMPANY_LOGO_URL);
});

test("G) theme artwork can never become an invoice logo", () => {
  for (const artwork of [
    "assets/🥇 Fluxidi Neon Rush/company_settings_neon_rush.png",
    "assets/Corporate BLEU Compagny/company_bookings_corporate_blue.png",
    "assets/Emerald_Ivory_Company/company_header_emerald_ivory.png",
  ]) {
    const src = resolveInvoiceLogoSrc({
      profileLogoUrl: artwork,
      sellerBrand: "Some Other Company BVBA",
    });
    // Theme paths are not usable data URIs — resolver falls back to monogram,
    // never treats artwork as a company logo source.
    assert.equal(src.includes(artwork), false, `theme artwork leaked: ${artwork}`);
    assert.equal(isUsableInvoiceLogoDataUri(src), true);
    assert.equal(sellerSnapshotLogoRefFromProfile({ logoUrl: artwork }), null);
  }
});

test("H) the seller snapshot freezes the company logo at issue time", () => {
  const snapshot = buildSellerSnapshotFromBusinessProfile({
    companyName: "Wakanda Wotan BVBA",
    tradingName: "Wakanda Wotan",
    legalName: "Wakanda Wotan BVBA",
    vatNumber: "BE0123456789",
    enterpriseNumber: "0123456789",
    addressLine: "Kortrijksesteenweg 12",
    postalCode: "9800",
    city: "Deinze",
    countryCode: "BE",
    publicLogoUrl: COMPANY_LOGO_URL,
  });
  assert.equal(snapshot.logo_url, COMPANY_LOGO_URL);

  // A packaged Fluxidi asset means "no company logo", never a snapshot value.
  assert.equal(
    sellerSnapshotLogoRefFromProfile({
      publicLogoUrl: "assets/fluxidi/fluxidi_logo.png",
    }),
    null,
  );
  assert.equal(sellerSnapshotLogoRefFromProfile({}), null);
  assert.equal(sellerSnapshotLogoRefFromProfile(null), null);
  assert.equal(
    sellerSnapshotLogoRefFromProfile({ publicLogoUrl: COMPANY_LOGO_DATA_URI }),
    COMPANY_LOGO_DATA_URI,
  );
});

test("I) the logo is fingerprinted into the projection revision", () => {
  const base = {
    paymentStatus: "paid",
    vatRatePercent: 6,
    totalInclCents: 500,
    vatCents: 30,
    subtotalExCents: 470,
    sellerSource: "document_core_seller_snapshot",
    paymentMethodLabel: "PayPal",
    tripDate: "2026-07-20",
    pickupTime: "12:00",
    tier: "comfort",
    service: "private",
    from: "Kortrijksesteenweg 12, Deinze",
    to: "Sint-Pietersplein 1, Gent",
  };
  const withoutLogo = buildStreetInvoicePdfProjectionRevision(base);
  const withLogo = buildStreetInvoicePdfProjectionRevision({
    ...base,
    sellerLogoRef: COMPANY_LOGO_URL,
  });
  const withOtherLogo = buildStreetInvoicePdfProjectionRevision({
    ...base,
    sellerLogoRef: `${COMPANY_LOGO_URL}?v=2`,
  });

  assert.match(withoutLogo, /;logo=none;/);
  assert.notEqual(withLogo, withoutLogo, "a new logo must change the revision");
  assert.notEqual(withLogo, withOtherLogo);
  assert.equal(
    withLogo.startsWith(STREET_INVOICE_PDF_PROJECTION_VERSION),
    true,
  );
  // Deterministic, and the reference itself never lands in the revision.
  assert.equal(
    withLogo,
    buildStreetInvoicePdfProjectionRevision({
      ...base,
      sellerLogoRef: COMPANY_LOGO_URL,
    }),
  );
  assert.equal(withLogo.includes(COMPANY_LOGO_URL), false);
  assert.equal(withLogo.length < 400, true, "revision must stay compact");
});

test("J) the logo fingerprint is stable, distinct and never leaks the value", () => {
  assert.equal(fingerprintSellerLogoRef(""), "none");
  assert.equal(fingerprintSellerLogoRef(null), "none");
  assert.equal(
    fingerprintSellerLogoRef(COMPANY_LOGO_URL),
    fingerprintSellerLogoRef(COMPANY_LOGO_URL),
  );
  assert.notEqual(
    fingerprintSellerLogoRef(COMPANY_LOGO_URL),
    fingerprintSellerLogoRef(`${COMPANY_LOGO_URL}?v=2`),
  );
  const dataPrint = fingerprintSellerLogoRef(COMPANY_LOGO_DATA_URI);
  assert.match(dataPrint, /^d[0-9a-f]{8}$/);
  assert.match(fingerprintSellerLogoRef(COMPANY_LOGO_URL), /^u[0-9a-f]{8}$/);
  assert.equal(dataPrint.includes("base64"), false);
});

test("K) the compact layout removes the sparse vertical gap", () => {
  const compact = totalInvoiceBlockSpacingPx(INVOICE_COMPACT_BLOCK_SPACING_PX);
  const legacy = totalInvoiceBlockSpacingPx(LEGACY_INVOICE_BLOCK_SPACING_PX);
  assert.equal(compact < legacy, true, "spacing must be tighter than before");
  assert.equal(legacy - compact >= 20, true, "expected a visible reduction");
  // Still readable: never collapsed to a cramped block.
  assert.equal(compact >= 50, true);

  const css = buildInvoicePrintCss();
  assert.match(css, /margin-top:\s*6px/, "table follows the metadata closely");
  assert.doesNotMatch(css, /margin-top:\s*18px/);
  assert.match(css, /@page\s*\{\s*size:\s*A4/);
  assert.match(css, /margin:\s*10mm/);
});

test("L) short invoices still fit one A4 page and the logo is not distorted", () => {
  assert.equal(shortInvoiceFitsOneA4Page(), true);
  const css = buildInvoicePrintCss();
  // Height-only sizing plus contain keeps the aspect ratio intact. `max-width`
  // is fine (it only prevents overflow); a bare `width` would stretch the mark.
  assert.match(css, /object-fit:\s*contain/);
  assert.match(css, /width:\s*auto/);
  assert.doesNotMatch(css, /\.logo img\s*\{[^}]*(?<!max-)width:\s*100%/);
  assert.doesNotMatch(css, /object-fit:\s*(fill|cover)/);
});

test("M) long invoices still paginate and repeat the table header", () => {
  const css = buildInvoicePrintCss();
  assert.match(css, /thead\s*\{\s*display:\s*table-header-group/);
  assert.match(css, /tr\s*\{\s*page-break-inside:\s*avoid/);
  assert.match(css, /\.totals\s*\{[^}]*page-break-inside:\s*avoid/);
  assert.match(css, /\.closing\s*\{[^}]*page-break-inside:\s*avoid/);
  // A tall invoice must be allowed to overflow onto real pages.
  assert.equal(
    shortInvoiceFitsOneA4Page({ sellerLines: 120 }),
    false,
    "genuinely long content must not be forced onto one page",
  );
});
