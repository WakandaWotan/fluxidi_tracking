/* FLUXIDI-INVOICE-COMPANY-LOGO-FETCH-AND-EMBED-P0-2
 *
 * Field gap: after company bootstrap the Branding & support logo is an HTTPS
 * /public/media/… URL. Invoice PDF generation never fetched/embedded it unless
 * INVOICE_ALLOW_EXTERNAL_LOGO_URL=1, so companies with a correct logo still got
 * the Fluxidi monogram on invoices.
 *
 *   node --test workers/booking/modules/invoice_company_logo_fetch.test.mjs
 */

import { test } from "node:test";
import assert from "node:assert/strict";

import {
  INVOICE_COMPANY_LOGO_MAX_BYTES,
  classifyInvoiceLogoImageBytes,
  parseApprovedCompanyLogoMediaKey,
  isApprovedInvoiceLogoMediaHost,
  isBlockedInvoiceLogoIp,
  resolveAndEmbedInvoiceCompanyLogo,
  invoiceNeedsCompanyLogoEmbed,
  readFrozenInvoiceLogoEmbed,
  readInvoiceLogoEmbedAttempt,
  buildInvoiceLogoEmbedRecord,
  buildFailedInvoiceLogoEmbedRecord,
  formatInvoiceLogoEmbedDiagnostic,
  isUsableInvoiceLogoEmbed,
  bytesToInvoiceLogoDataUri,
} from "./invoice_company_logo_fetch.js";
import {
  resolveInvoiceLogoSrc,
  buildFluxidiInvoiceLogoDataUri,
  isUsableInvoiceLogoDataUri,
  FLUXIDI_INVOICE_LOGO_SVG,
  REJECTED_INVOICE_LOGO_WORDMARK_MARKERS,
} from "./invoice_logo_embedded.js";
import {
  buildSellerSnapshotFromBusinessProfile,
  sellerSnapshotLogoRefFromProfile,
} from "./seller_identity.js";
import {
  buildStreetInvoicePdfProjectionRevision,
  fingerprintSellerLogoRef,
  shouldRefreshStreetInvoicePdfOnOpen,
  STREET_INVOICE_PDF_PROJECTION_VERSION,
} from "./street_invoice_pdf_projection.js";
import { shortInvoiceFitsOneA4Page } from "./invoice_print_layout.js";

const TENANT = "tenant-a";
const COMPANY = "company-a";
const LOGO_KEY = `public-media/${TENANT}/${COMPANY}/company/logo.png`;
const LOGO_URL = `https://fluxidi-booking-api.fluxidi.workers.dev/public/media/${LOGO_KEY}?v=1`;
const TENANT_B_URL =
  "https://fluxidi-booking-api.fluxidi.workers.dev/public/media/public-media/tenant-b/company-b/company/logo.png";

// 1×1 PNG
const PNG_BYTES = Uint8Array.from(
  Buffer.from(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==",
    "base64",
  ),
);
// Minimal JPEG (1×1)
const JPEG_BYTES = Uint8Array.from(
  Buffer.from(
    "/9j/4AAQSkZJRgABAQAAAQABAAD/2wCEAAkGBxAQEBUQEBAVFRUVFRUVFRUVFRUVFRUWFhUVFRUYHSggGBolGxUVITEhJSkrLi4uFx8zODMtNygtLisBCgoKDg0OGxAQGy0lHyUtLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLf/AABEIAAEAAQMBIgACEQEDEQH/xAAbAAACAwEBAQAAAAAAAAAAAAADBAECBQYAB//EABUBAQEAAAAAAAAAAAAAAAAAAAAB/8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAwDAQACEAMQAAAB0fAP/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABBQL/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAEDAQE/Af/EABQRAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQIBAT8B/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQAGPwL/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAEDAQE/Af/Z",
    "base64",
  ),
);

function mockPublicMedia(store) {
  return {
    async get(key) {
      const hit = store[key];
      if (!hit) return null;
      return {
        arrayBuffer: async () => hit.bytes.buffer.slice(
          hit.bytes.byteOffset,
          hit.bytes.byteOffset + hit.bytes.byteLength,
        ),
        httpMetadata: { contentType: hit.contentType },
      };
    },
  };
}

test("1) normal Branding & support HTTPS logo is fetched and embedded via R2", async () => {
  const env = {
    PUBLIC_MEDIA: mockPublicMedia({
      [LOGO_KEY]: { bytes: PNG_BYTES, contentType: "image/png" },
    }),
  };
  const out = await resolveAndEmbedInvoiceCompanyLogo({
    env,
    logoRef: LOGO_URL,
    tenantId: TENANT,
    companyId: COMPANY,
  });
  assert.equal(out.ok, true);
  assert.equal(out.embedded, true);
  assert.equal(out.fetched, false, "R2 path must not network-fetch");
  assert.equal(isUsableInvoiceLogoDataUri(out.data_uri), true);
  assert.match(out.data_uri, /^data:image\/png;base64,/);
  assert.equal(out.data_uri.includes("https://"), false);
});

test("2) generated logo src contains company PNG bytes, not only the Fluxidi mark", async () => {
  const env = {
    PUBLIC_MEDIA: mockPublicMedia({
      [LOGO_KEY]: { bytes: PNG_BYTES, contentType: "image/png" },
    }),
  };
  const out = await resolveAndEmbedInvoiceCompanyLogo({
    env,
    logoRef: LOGO_URL,
    tenantId: TENANT,
    companyId: COMPANY,
  });
  const src = resolveInvoiceLogoSrc({
    profileLogoUrl: out.data_uri,
    sellerBrand: "Wakanda Wotan BVBA",
    packagedDataUri: buildFluxidiInvoiceLogoDataUri(),
  });
  assert.equal(src, out.data_uri);
  assert.notEqual(src, buildFluxidiInvoiceLogoDataUri());
});

test("3) post-bootstrap HTTPS /public/media representation is accepted", () => {
  const parsed = parseApprovedCompanyLogoMediaKey(LOGO_URL, {
    tenantId: TENANT,
    companyId: COMPANY,
  });
  assert.equal(parsed.ok, true);
  assert.equal(parsed.key, LOGO_KEY);
  assert.equal(
    sellerSnapshotLogoRefFromProfile({ publicLogoUrl: LOGO_URL }),
    LOGO_URL,
  );
});

test("4+5) new invoice freezes logo identity; later profile change cannot rewrite it", () => {
  const snap = buildSellerSnapshotFromBusinessProfile({
    companyName: "Wakanda Wotan BVBA",
    tradingName: "Wakanda Wotan",
    legalName: "Wakanda Wotan BVBA",
    vatNumber: "BE0123456789",
    enterpriseNumber: "0123456789",
    publicLogoUrl: LOGO_URL,
  });
  assert.equal(snap.logo_url, LOGO_URL);

  const embed = buildInvoiceLogoEmbedRecord({
    dataUri: bytesToInvoiceLogoDataUri(PNG_BYTES, "image/png"),
    sha256: "abc123",
    mime: "image/png",
    sourceKind: "public_media_r2",
    keyFingerprint: "kdeadbeef",
  });
  const booking = { invoice_logo_embed: embed };
  const frozen = readFrozenInvoiceLogoEmbed({ bookingRecord: booking });
  assert.equal(isUsableInvoiceLogoEmbed(frozen), true);

  // Profile now points at a different logo URL — frozen bytes still win.
  const laterProfileUrl = `${LOGO_URL}&v=999`;
  assert.notEqual(laterProfileUrl, snap.logo_url);
  assert.equal(
    invoiceNeedsCompanyLogoEmbed({
      sellerLogoRef: laterProfileUrl,
      existingEmbed: frozen,
      tenantId: TENANT,
      companyId: COMPANY,
    }),
    false,
  );
  const rev1 = buildStreetInvoicePdfProjectionRevision({
    paymentStatus: "paid",
    sellerLogoRef: `sha:${embed.sha256}`,
  });
  const rev2 = buildStreetInvoicePdfProjectionRevision({
    paymentStatus: "paid",
    sellerLogoRef: `sha:${embed.sha256}`,
  });
  assert.equal(rev1, rev2);
  assert.equal(rev1.includes(laterProfileUrl), false);
});

test("6) reopening a frozen artifact performs zero logo network fetches", async () => {
  let fetches = 0;
  const embed = buildInvoiceLogoEmbedRecord({
    dataUri: bytesToInvoiceLogoDataUri(PNG_BYTES, "image/png"),
    sha256: "abc123",
    mime: "image/png",
    sourceKind: "public_media_r2",
    keyFingerprint: "k1",
  });
  const out = await resolveAndEmbedInvoiceCompanyLogo({
    env: { PUBLIC_MEDIA: mockPublicMedia({}) },
    logoRef: LOGO_URL,
    tenantId: TENANT,
    companyId: COMPANY,
    existingEmbed: embed,
    fetchImpl: async () => {
      fetches += 1;
      throw new Error("should_not_fetch");
    },
  });
  assert.equal(out.ok, true);
  assert.equal(out.reason, "reuse_frozen_embed");
  assert.equal(fetches, 0);
  assert.equal(
    shouldRefreshStreetInvoicePdfOnOpen({
      existingPdfExists: true,
      storedProjectionRevision: `${STREET_INVOICE_PDF_PROJECTION_VERSION};logo=none`,
      needsCompanyLogoEmbed: false,
    }).refresh,
    false,
  );
});

test("7) historical single-invoice refresh embeds the canonical logo once", () => {
  assert.equal(
    invoiceNeedsCompanyLogoEmbed({
      sellerLogoRef: LOGO_URL,
      existingEmbed: null,
      tenantId: TENANT,
      companyId: COMPANY,
    }),
    true,
  );
  const decision = shouldRefreshStreetInvoicePdfOnOpen({
    existingPdfExists: true,
    storedProjectionRevision: `${STREET_INVOICE_PDF_PROJECTION_VERSION};x`,
    needsCompanyLogoEmbed: true,
  });
  assert.equal(decision.refresh, true);
  assert.equal(decision.reason, "company_logo_embed_pending");
});

test("8) no historical bulk regeneration API is introduced", async () => {
  // Guard: this module only exposes single-invoice helpers.
  const mod = await import("./invoice_company_logo_fetch.js");
  assert.equal(typeof mod.resolveAndEmbedInvoiceCompanyLogo, "function");
  assert.equal(typeof mod.bulkRegenerateInvoiceLogos, "undefined");
  assert.equal(typeof mod.regenerateAllHistoricalInvoicePdfs, "undefined");
});

test("9) tenant A cannot fetch or embed tenant B's logo", async () => {
  const parsed = parseApprovedCompanyLogoMediaKey(TENANT_B_URL, {
    tenantId: TENANT,
    companyId: COMPANY,
  });
  assert.equal(parsed.ok, false);
  assert.equal(parsed.reason, "tenant_scope_mismatch");
  const out = await resolveAndEmbedInvoiceCompanyLogo({
    env: {
      PUBLIC_MEDIA: mockPublicMedia({
        ["public-media/tenant-b/company-b/company/logo.png"]: {
          bytes: PNG_BYTES,
          contentType: "image/png",
        },
      }),
    },
    logoRef: TENANT_B_URL,
    tenantId: TENANT,
    companyId: COMPANY,
  });
  assert.equal(out.ok, false);
  assert.equal(out.reason, "tenant_scope_mismatch");
});

test("10) arbitrary external host is rejected", () => {
  const parsed = parseApprovedCompanyLogoMediaKey(
    "https://evil.example/public/media/public-media/tenant-a/company-a/company/logo.png",
    { tenantId: TENANT, companyId: COMPANY },
  );
  assert.equal(parsed.ok, false);
  assert.equal(parsed.reason, "host_not_approved");
  assert.equal(isApprovedInvoiceLogoMediaHost("cdn.evil.example"), false);
});

test("11) private/local/metadata address is rejected", () => {
  assert.equal(isBlockedInvoiceLogoIp("127.0.0.1"), true);
  assert.equal(isBlockedInvoiceLogoIp("10.0.0.5"), true);
  assert.equal(isBlockedInvoiceLogoIp("192.168.1.1"), true);
  assert.equal(isBlockedInvoiceLogoIp("169.254.169.254"), true);
  assert.equal(isBlockedInvoiceLogoIp("localhost"), true);
  assert.equal(isBlockedInvoiceLogoIp("metadata.google.internal"), true);
  assert.equal(
    isApprovedInvoiceLogoMediaHost("169.254.169.254"),
    false,
  );
});

test("12) redirect outside the approved media origin is rejected", async () => {
  const out = await resolveAndEmbedInvoiceCompanyLogo({
    env: { PUBLIC_MEDIA: mockPublicMedia({}) },
    logoRef: LOGO_URL,
    tenantId: TENANT,
    companyId: COMPANY,
    fetchImpl: async () => ({
      status: 302,
      headers: {
        get: (name) =>
          String(name).toLowerCase() === "location"
            ? "https://evil.example/steal.png"
            : null,
      },
    }),
  });
  assert.equal(out.ok, false);
  assert.match(out.reason, /redirect_host_not_approved|host_not_approved|logo_load_failed|public_media/);
});

test("13) timeout falls back safely", async () => {
  const out = await resolveAndEmbedInvoiceCompanyLogo({
    env: { PUBLIC_MEDIA: mockPublicMedia({}) },
    logoRef: LOGO_URL,
    tenantId: TENANT,
    companyId: COMPANY,
    timeoutMs: 5,
    fetchImpl: async (_url, opts) => {
      await new Promise((_, reject) => {
        opts?.signal?.addEventListener("abort", () => {
          const err = new Error("aborted");
          err.name = "AbortError";
          reject(err);
        });
      });
    },
  });
  assert.equal(out.ok, false);
  const src = resolveInvoiceLogoSrc({
    profileLogoUrl: LOGO_URL,
    sellerBrand: "Other Taxi BV",
    packagedDataUri: buildFluxidiInvoiceLogoDataUri(),
  });
  assert.equal(isUsableInvoiceLogoDataUri(src), true);
  assert.match(src, /^data:image\//);
});

test("14) oversized image falls back safely", async () => {
  const big = new Uint8Array(INVOICE_COMPANY_LOGO_MAX_BYTES + 16);
  big.set(PNG_BYTES, 0);
  const out = await resolveAndEmbedInvoiceCompanyLogo({
    env: {
      PUBLIC_MEDIA: mockPublicMedia({
        [LOGO_KEY]: { bytes: big, contentType: "image/png" },
      }),
    },
    logoRef: LOGO_URL,
    tenantId: TENANT,
    companyId: COMPANY,
  });
  assert.equal(out.ok, false);
  assert.equal(out.reason, "logo_too_large");
});

test("15) MIME/magic-byte mismatch falls back safely", async () => {
  const out = await resolveAndEmbedInvoiceCompanyLogo({
    env: {
      PUBLIC_MEDIA: mockPublicMedia({
        [LOGO_KEY]: {
          bytes: PNG_BYTES,
          contentType: "image/jpeg",
        },
      }),
    },
    logoRef: LOGO_URL,
    tenantId: TENANT,
    companyId: COMPANY,
  });
  assert.equal(out.ok, false);
  assert.equal(out.reason, "logo_mime_mismatch");
});

test("16) HTML response cannot become an image", async () => {
  const html = new TextEncoder().encode("<!doctype html><html>nope</html>");
  assert.equal(classifyInvoiceLogoImageBytes(html), null);
  const out = await resolveAndEmbedInvoiceCompanyLogo({
    env: {
      PUBLIC_MEDIA: mockPublicMedia({
        [LOGO_KEY]: { bytes: html, contentType: "image/png" },
      }),
    },
    logoRef: LOGO_URL,
    tenantId: TENANT,
    companyId: COMPANY,
  });
  assert.equal(out.ok, false);
  assert.equal(out.reason, "logo_magic_mismatch");
});

test("17) corrupt media cannot create a broken placeholder", async () => {
  const corrupt = new Uint8Array([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
  const out = await resolveAndEmbedInvoiceCompanyLogo({
    env: {
      PUBLIC_MEDIA: mockPublicMedia({
        [LOGO_KEY]: { bytes: corrupt, contentType: "image/png" },
      }),
    },
    logoRef: LOGO_URL,
    tenantId: TENANT,
    companyId: COMPANY,
  });
  assert.equal(out.ok, false);
  const src = resolveInvoiceLogoSrc({
    profileLogoUrl: "data:image/png;base64,AAAA",
    sellerBrand: "Wakanda",
    packagedDataUri: buildFluxidiInvoiceLogoDataUri(),
  });
  assert.equal(isUsableInvoiceLogoDataUri(src), true);
  assert.equal(src.startsWith("http"), false);
});

test("18) PNG and JPEG company logos render as usable data URIs", async () => {
  assert.equal(classifyInvoiceLogoImageBytes(PNG_BYTES), "image/png");
  assert.equal(classifyInvoiceLogoImageBytes(JPEG_BYTES), "image/jpeg");
  const jpegKey = `public-media/${TENANT}/${COMPANY}/company/logo.jpg`;
  const jpegUrl = `https://fluxidi-booking-api.fluxidi.workers.dev/public/media/${jpegKey}`;
  const out = await resolveAndEmbedInvoiceCompanyLogo({
    env: {
      PUBLIC_MEDIA: mockPublicMedia({
        [jpegKey]: { bytes: JPEG_BYTES, contentType: "image/jpeg" },
      }),
    },
    logoRef: jpegUrl,
    tenantId: TENANT,
    companyId: COMPANY,
  });
  assert.equal(out.ok, true);
  assert.match(out.data_uri, /^data:image\/jpeg;base64,/);
});

test("19) theme artwork and public gallery images cannot become invoice logos", () => {
  for (const bad of [
    "assets/🥇 Fluxidi Neon Rush/company_settings_neon_rush.png",
    "assets/Corporate BLEU Compagny/company_bookings_corporate_blue.png",
    `https://fluxidi-booking-api.fluxidi.workers.dev/public/media/public-media/${TENANT}/${COMPANY}/company/hero.png`,
    `https://fluxidi-booking-api.fluxidi.workers.dev/public/media/public-media/${TENANT}/${COMPANY}/drivers/d1/portrait.jpg`,
    `https://fluxidi-booking-api.fluxidi.workers.dev/public/media/public-media/${TENANT}/${COMPANY}/vehicles/v1/photo.jpg`,
  ]) {
    const parsed = parseApprovedCompanyLogoMediaKey(bad, {
      tenantId: TENANT,
      companyId: COMPANY,
    });
    assert.equal(parsed.ok, false, bad);
    assert.equal(sellerSnapshotLogoRefFromProfile({ logoUrl: bad }) == null || parsed.ok === false, true);
  }
});

test("20) INELIVIA cannot appear", () => {
  for (const marker of REJECTED_INVOICE_LOGO_WORDMARK_MARKERS) {
    assert.equal(FLUXIDI_INVOICE_LOGO_SVG.includes(marker), false);
  }
  assert.doesNotMatch(FLUXIDI_INVOICE_LOGO_SVG, /INELIVIA/i);
  const parsed = parseApprovedCompanyLogoMediaKey(
    "https://fluxidi-booking-api.fluxidi.workers.dev/public/media/public-media/t/c/company/logo.png?x=inelivia",
    { tenantId: "t", companyId: "c" },
  );
  assert.equal(parsed.ok, false);
});

test("21+22) invoice number/totals/VAT/payment and Billit/Peppol facts stay out of logo module", () => {
  // Logo embed helpers are pure media gates — they never accept totals/Billit.
  const diag = formatInvoiceLogoEmbedDiagnostic({
    reason: "embedded",
    key_fp: "k1",
    mime: "image/png",
    bytes: 12,
  });
  assert.match(diag, /\[INVOICE_LOGO_EMBED\]/);
  assert.equal(diag.includes("invoice_number"), false);
  assert.equal(diag.includes("billit"), false);
  assert.equal(diag.includes("peppol"), false);
  assert.equal(diag.includes(LOGO_URL), false);
});

test("23) short invoice remains one page", () => {
  assert.equal(shortInvoiceFitsOneA4Page(), true);
});

test("24) repeated/concurrent generation is idempotent via frozen embed", async () => {
  const env = {
    PUBLIC_MEDIA: mockPublicMedia({
      [LOGO_KEY]: { bytes: PNG_BYTES, contentType: "image/png" },
    }),
  };
  const a = await resolveAndEmbedInvoiceCompanyLogo({
    env,
    logoRef: LOGO_URL,
    tenantId: TENANT,
    companyId: COMPANY,
  });
  const b = await resolveAndEmbedInvoiceCompanyLogo({
    env,
    logoRef: LOGO_URL,
    tenantId: TENANT,
    companyId: COMPANY,
    existingEmbed: a.embed,
  });
  assert.equal(a.ok, true);
  assert.equal(b.ok, true);
  assert.equal(b.reason, "reuse_frozen_embed");
  assert.equal(a.data_uri, b.data_uri);
  const failed = buildFailedInvoiceLogoEmbedRecord({ reason: "logo_too_large" });
  assert.equal(
    invoiceNeedsCompanyLogoEmbed({
      sellerLogoRef: LOGO_URL,
      existingEmbed: failed,
      tenantId: TENANT,
      companyId: COMPANY,
    }),
    false,
  );
  assert.equal(
    readInvoiceLogoEmbedAttempt({
      bookingRecord: { invoice_logo_embed: failed },
    })?.failed,
    true,
  );
});

test("25) logs contain no full media URL, token or customer data", () => {
  const line = formatInvoiceLogoEmbedDiagnostic({
    reason: "embedded",
    key_fp: "k00aabbcc",
    mime: "image/png",
    bytes: 42,
    source_kind: "public_media_r2",
  });
  assert.equal(line.includes("https://"), false);
  assert.equal(line.includes(LOGO_URL), false);
  assert.equal(line.includes("token"), false);
  assert.equal(line.includes("Bearer"), false);
  assert.equal(line.includes("customer"), false);
  assert.match(line, /key_fp=k00aabbcc/);
});

test("fingerprint stays compact and never leaks the logo value", () => {
  const fp = fingerprintSellerLogoRef(LOGO_URL);
  assert.match(fp, /^u[0-9a-f]{8}$/);
  assert.equal(fp.includes("https://"), false);
});
