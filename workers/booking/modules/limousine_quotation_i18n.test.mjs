// LIMOUSINE-QUOTE-DELIVERY-P3K — four-language quotation renderer contract.
// Run: node --test workers/booking/modules/limousine_quotation_i18n.test.mjs

import test from "node:test";
import assert from "node:assert/strict";

import {
  LIMOUSINE_QUOTATION_FORBIDDEN_PDF_TOKENS,
  LIMOUSINE_QUOTATION_I18N_KEYS,
  LIMOUSINE_QUOTATION_I18N_LOCALES,
  assertLimousineQuotationI18nComplete,
  limousineQuotationCopy,
  normalizeLimousineQuotationLocale,
  renderLimousineConditionSentences,
  translateLimousineJourneyType,
} from "./limousine_quotation_i18n.mjs";
import {
  LIMOUSINE_QUOTATION_RENDERER_VERSION,
  LIMOUSINE_QUOTATION_RENDERER_VERSION_V1,
  buildLimousineQuotationSnapshot,
} from "./limousine_quotation_snapshot.mjs";
import {
  buildLimousineQuotationArtifactKey,
  renderLimousineQuotationHtml,
} from "./limousine_quotation_document.mjs";

const TERMS = {
  terms_revision: 3,
  cancellation_deadline_hours: 24,
  cancellation_penalty_percent: 20,
  waiting_time_included_minutes: 60,
  waiting_time_overage_cents_per_minute: 150,
  no_show_penalty_percent: 100,
  overtime_cents_per_hour: 10000,
  customer_obligations: {
    nl: "5",
    en: "5",
    fr: "5",
    es: "5",
  },
  important_information: {
    nl: "Niet roken. <script>x</script> & \"quotes\" " + "WORD".repeat(80),
    en: "No smoking. <script>x</script> & \"quotes\" " + "WORD".repeat(80),
    fr: "Ne pas fumer. <script>x</script> & \"quotes\" " + "WORD".repeat(80),
    es: "No fumar. <script>x</script> & \"quotes\" " + "WORD".repeat(80),
  },
};

const EXPECTED = {
  nl: {
    title: "Offerte",
    disclaimer: "geen factuur",
    journey: "Punt-tot-punt",
    cancel: "Annuleren kan tot 24 uur",
  },
  en: {
    title: "Quotation",
    disclaimer: "not an invoice",
    journey: "Point-to-point",
    cancel: "Cancellation is possible up to 24 hours",
  },
  fr: {
    title: "Devis",
    disclaimer: "pas une facture",
    journey: "Trajet point à point",
    cancel: "L’annulation est possible jusqu’à 24 heures",
  },
  es: {
    title: "Presupuesto",
    disclaimer: "no es una factura",
    journey: "Trayecto punto a punto",
    cancel: "La cancelación es posible hasta 24 horas",
  },
};

async function snapshotFor(locale, extras = {}) {
  return buildLimousineQuotationSnapshot({
    quoteRequestId: "limq_p3k_html",
    quoteRevision: 3,
    termsRevision: 3,
    issuedAt: "2026-08-22T08:00:00Z",
    expiresAt: "2026-08-24T08:00:00Z",
    locale,
    sellerSnapshot: {
      legal_name: "Coachline BV",
      vat_number: "BE0772931038",
      address_line: "Markt 1",
      city: "Gent",
    },
    requestSnapshot: {
      journey_type: extras.journeyType || "point_to_point",
      from: "Gent",
      to: "Brussel",
      scheduled_pickup_iso: "2026-09-01T10:00:00Z",
      pax: 2,
      bags: 1,
    },
    vehicleSnapshot: { public_name: "Executive sedan" },
    offerSnapshot: {
      total_incl_vat_cents: 18500,
      currency: "EUR",
      vat_rate: 0.06,
      vat_treatment: "incl",
      public_text: {
        nl: "Vaste prijs",
        en: "Fixed price",
        fr: "Prix fixe",
        es: "Precio fijo",
      },
      terms: TERMS,
      terms_revision: 3,
      ...extras.offer,
    },
    rendererVersion: extras.rendererVersion,
  });
}

function assertNoInvoice(html) {
  const lower = html.toLowerCase();
  assert.ok(!lower.includes("factuurnummer"));
  assert.ok(!lower.includes("invoice number"));
  assert.ok(!lower.includes("due date"));
  assert.ok(!lower.includes("billit"));
  assert.ok(!lower.includes("peppol"));
  assert.ok(!html.includes("INV-"));
}

test("translation keys exist in NL EN FR ES", () => {
  const missing = assertLimousineQuotationI18nComplete();
  assert.deepEqual(missing, {});
  for (const locale of LIMOUSINE_QUOTATION_I18N_LOCALES) {
    const copy = limousineQuotationCopy(locale);
    for (const key of LIMOUSINE_QUOTATION_I18N_KEYS) {
      assert.ok(copy[key], `${locale}.${key}`);
      assert.notEqual(copy[key], key);
    }
  }
});

test("locale aliases collapse to one effective language", () => {
  assert.equal(normalizeLimousineQuotationLocale("nl-BE"), "nl");
  assert.equal(normalizeLimousineQuotationLocale("en-GB"), "en");
  assert.equal(normalizeLimousineQuotationLocale("en-US"), "en");
  assert.equal(normalizeLimousineQuotationLocale("fr-BE"), "fr");
  assert.equal(normalizeLimousineQuotationLocale("fr-FR"), "fr");
  assert.equal(normalizeLimousineQuotationLocale("es-ES"), "es");
  assert.equal(normalizeLimousineQuotationLocale("de-DE"), "nl");
});

test("27-42) renderer v2 localizes all four languages without internal keys", async () => {
  for (const locale of LIMOUSINE_QUOTATION_I18N_LOCALES) {
    const snap = await snapshotFor(locale);
    assert.equal(snap.renderer_version, LIMOUSINE_QUOTATION_RENDERER_VERSION);
    assert.equal(snap.locale, locale);
    const html = renderLimousineQuotationHtml(snap);
    const expected = EXPECTED[locale];
    assert.ok(html.includes(expected.title), locale);
    assert.ok(html.toLowerCase().includes(expected.disclaimer), locale);
    assert.ok(html.includes(expected.journey), locale);
    assert.ok(html.includes(expected.cancel), locale);
    for (const token of LIMOUSINE_QUOTATION_FORBIDDEN_PDF_TOKENS) {
      assert.equal(html.includes(token), false, `${locale} leaked ${token}`);
    }
    assert.equal(html.includes("point_to_point"), false, locale);
    assert.ok(html.includes("Klantverplichtingen") || html.includes("Customer obligations") || html.includes("Obligations du client") || html.includes("Obligaciones del cliente"));
    assert.ok(html.includes(">5<") || html.includes(">5</"));
    assert.ok(!html.includes("<h2></h2>"));
    assert.ok(!html.includes("<script>x</script>"));
    assert.ok(html.includes("&lt;script&gt;"));
    assert.ok(html.includes("WORDWORDWORD"));
    assertNoInvoice(html);
    if (locale === "nl") {
      assert.ok(html.includes("€") || html.includes("EUR"));
      assert.ok(!html.includes("Quotation"));
    }
    if (locale === "en") {
      assert.ok(!html.includes("Offerte"));
      assert.ok(!html.includes("Devis"));
    }
    if (locale === "fr") {
      assert.ok(!html.includes("Offerte"));
      assert.ok(!html.includes("Quotation"));
    }
    if (locale === "es") {
      assert.ok(!html.includes("Offerte"));
      assert.ok(!html.includes("Quotation"));
    }
  }
});

test("valid non-NL locale never falls back to Dutch system copy", async () => {
  for (const raw of ["en", "fr", "es", "en-GB", "en-US", "fr-BE", "es-ES"]) {
    const snap = await snapshotFor(raw);
    const loc = normalizeLimousineQuotationLocale(raw);
    assert.equal(snap.locale, loc);
    assert.notEqual(snap.locale, "nl");
    const html = renderLimousineQuotationHtml(snap);
    assert.equal(html.includes("Offerte"), false, raw);
    assert.equal(html.includes("Punt-tot-punt"), false, raw);
    assert.equal(html.toLowerCase().includes("geen factuur"), false, raw);
    assert.ok(html.includes(EXPECTED[loc].title), raw);
  }
});

test("empty sections and unknown enums are omitted", async () => {
  const snap = await snapshotFor("nl", {
    journeyType: "not_a_real_journey",
    offer: {
      included_services: [],
      separately_priced_extras: [],
      mobilisation_disclosure: {},
      terms: {
        ...TERMS,
        customer_obligations: {},
        important_information: {},
      },
    },
  });
  const html = renderLimousineQuotationHtml(snap);
  assert.equal(html.includes("Inbegrepen diensten"), false);
  assert.equal(html.includes("Apart geprijsde extras"), false);
  assert.equal(html.includes("Mobilisatie"), false);
  assert.equal(html.includes("not_a_real_journey"), false);
  assert.equal(html.includes("terms_revision"), false);
});

test("conditions render as localized sentences", () => {
  const nl = renderLimousineConditionSentences(TERMS, { locale: "nl", currency: "EUR" });
  assert.ok(nl.some((line) => line.includes("60 minuten wachttijd")));
  assert.ok(nl.some((line) => line.includes("per minuut")));
  assert.ok(nl.some((line) => line.includes("niet opdagen")));
  assert.equal(translateLimousineJourneyType("point_to_point", "nl"), "Punt-tot-punt");
});

test("43-44) renderer v2 keys differ from frozen v1 identity", async () => {
  const v2 = await snapshotFor("nl");
  const v1 = await snapshotFor("nl", { rendererVersion: LIMOUSINE_QUOTATION_RENDERER_VERSION_V1 });
  assert.equal(v2.renderer_version, 2);
  assert.equal(v1.renderer_version, 1);
  assert.notEqual(v2.content_hash, v1.content_hash);
  const keyV2 = buildLimousineQuotationArtifactKey({
    tenantId: "t",
    companyId: "c",
    quoteRequestId: "limq_p3k_html",
    revision: 3,
    contentHash: v2.content_hash,
    rendererVersion: v2.renderer_version,
  });
  const keyV1 = buildLimousineQuotationArtifactKey({
    tenantId: "t",
    companyId: "c",
    quoteRequestId: "limq_p3k_html",
    revision: 3,
    contentHash: v1.content_hash,
    rendererVersion: v1.renderer_version,
  });
  assert.ok(keyV2.includes("quotation-v2-"));
  assert.ok(keyV1.includes("quotation-v1-"));
  const v1Html = renderLimousineQuotationHtml(v1);
  assert.ok(v1Html.includes("point_to_point"));
  const v2Html = renderLimousineQuotationHtml(v2);
  assert.equal(v2Html.includes("point_to_point"), false);
});
