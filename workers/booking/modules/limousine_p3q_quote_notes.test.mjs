// P3Q — own-customer quote notes survive snapshot, guest page and PDF.
// Run: node --test workers/booking/modules/limousine_p3q_quote_notes.test.mjs

import test from "node:test";
import assert from "node:assert/strict";

import {
  limousineExternalPageCopy,
  limousineExternalQuoteNoteSections,
  renderLimousineExternalQuotationPage,
} from "./limousine_external_customer_page.mjs";
import { publicLimousineQuoteView, validateLimousineCompanyQuote } from "./limousine_manual_quote.mjs";
import { renderLimousineQuotationHtml } from "./limousine_quotation_document.mjs";
import { selectLocalizedQuotationText } from "./limousine_quotation_i18n.mjs";
import {
  buildLimousineQuotationSnapshot,
  freezeLimousineQuotationOfferSnapshot,
} from "./limousine_quotation_snapshot.mjs";

const CHAMPAGNE = "2 flessen champagne";
const TERMS = {
  terms_revision: 1,
  cancellation_deadline_hours: 24,
  cancellation_penalty_percent: 25,
  waiting_time_included_minutes: 15,
  waiting_time_overage_cents_per_minute: 0,
  no_show_penalty_percent: 100,
  overtime_cents_per_hour: 0,
  included_services: [
    {
      item_id: "included_1",
      label: { nl: CHAMPAGNE, en: CHAMPAGNE, fr: CHAMPAGNE, es: CHAMPAGNE },
    },
  ],
  mobilisation_disclosure: { nl: "Vanuit depot" },
  customer_obligations: { nl: "Klaarstaan op de ophaallocatie" },
  important_information: { nl: "Niet roken" },
};

const COMPANY_VAT_6 = { vatEnabled: true, vatRate: 0.06, vatDisplayMode: "excl" };

test("guest page labels stay localized", () => {
  assert.equal(limousineExternalPageCopy("nl").included, "Inbegrepen diensten");
  assert.equal(limousineExternalPageCopy("en").included, "Included services");
  assert.equal(limousineExternalPageCopy("fr").included, "Services inclus");
  assert.equal(limousineExternalPageCopy("es").included, "Servicios incluidos");
  assert.equal(limousineExternalPageCopy("nl").mobilisation, "Mobilisatie");
  assert.equal(limousineExternalPageCopy("en").mobilisation, "Mobilisation");
  assert.equal(limousineExternalPageCopy("fr").mobilisation, "Mobilisation");
  assert.equal(limousineExternalPageCopy("es").mobilisation, "Movilización");
  assert.equal(limousineExternalPageCopy("nl").obligations, "Klantverplichtingen");
  assert.equal(limousineExternalPageCopy("en").obligations, "Customer obligations");
  assert.equal(limousineExternalPageCopy("fr").obligations, "Obligations du client");
  assert.equal(limousineExternalPageCopy("es").obligations, "Obligaciones del cliente");
  assert.equal(limousineExternalPageCopy("nl").important, "Belangrijke informatie");
  assert.equal(limousineExternalPageCopy("en").important, "Important information");
  assert.equal(limousineExternalPageCopy("fr").important, "Informations importantes");
  assert.equal(limousineExternalPageCopy("es").important, "Información importante");
});

test("entered free text is not translated when locale changes", () => {
  const onlyNl = { nl: CHAMPAGNE };
  assert.equal(selectLocalizedQuotationText(onlyNl, "en"), CHAMPAGNE);
  assert.equal(selectLocalizedQuotationText(onlyNl, "fr"), CHAMPAGNE);
  assert.equal(selectLocalizedQuotationText(onlyNl, "es"), CHAMPAGNE);
  assert.equal(selectLocalizedQuotationText(onlyNl, "en").includes("bottles"), false);
});

test("notes survive company quote → snapshot → PDF and guest copy", async () => {
  const built = validateLimousineCompanyQuote(
    {
      entered_amount_cents: 100000,
      currency: "EUR",
      vat_treatment: "excl",
      expires_at: "2099-01-01T00:00:00Z",
      terms: TERMS,
    },
    { companyTaxProfile: COMPANY_VAT_6 },
  );
  assert.equal(built.ok, true);
  assert.equal(built.quote.included_services[0].label.nl, CHAMPAGNE);
  assert.equal(built.quote.terms.included_services[0].label.nl, CHAMPAGNE);
  assert.equal(built.quote.mobilisation_disclosure.nl, "Vanuit depot");
  assert.equal(built.quote.terms.customer_obligations.nl, "Klaarstaan op de ophaallocatie");
  assert.equal(built.quote.terms.important_information.nl, "Niet roken");

  const frozen = freezeLimousineQuotationOfferSnapshot(built.quote);
  assert.equal(frozen.included_services[0].label.nl, CHAMPAGNE);
  assert.equal(frozen.mobilisation_disclosure.nl, "Vanuit depot");
  assert.equal(frozen.terms.customer_obligations.nl, "Klaarstaan op de ophaallocatie");
  assert.equal(frozen.terms.important_information.nl, "Niet roken");

  const snap = await buildLimousineQuotationSnapshot({
    quoteRequestId: "limq_notes",
    quoteRevision: 1,
    termsRevision: 1,
    issuedAt: "2026-08-24T08:00:00Z",
    expiresAt: "2099-01-01T00:00:00Z",
    locale: "en",
    sellerSnapshot: { legal_name: "Coachline BV" },
    requestSnapshot: { journey_type: "point_to_point", from: "Gent", to: "Brussel" },
    vehicleSnapshot: { public_name: "Party Limo" },
    offerSnapshot: frozen,
  });
  const html = renderLimousineQuotationHtml(snap);
  assert.equal(html.includes(CHAMPAGNE), true);
  assert.equal(html.includes("Included services"), true);
  assert.equal(html.includes("2 bottles of champagne"), false);
  assert.equal(html.includes("Vanuit depot"), true);
  assert.equal(html.includes("Klaarstaan op de ophaallocatie"), true);
  assert.equal(html.includes("Niet roken"), true);

  const empty = await buildLimousineQuotationSnapshot({
    quoteRequestId: "limq_empty",
    quoteRevision: 1,
    termsRevision: 1,
    issuedAt: "2026-08-24T08:00:00Z",
    expiresAt: "2099-01-01T00:00:00Z",
    locale: "nl",
    sellerSnapshot: { legal_name: "Coachline BV" },
    requestSnapshot: { journey_type: "point_to_point", from: "Gent", to: "Brussel" },
    offerSnapshot: {
      total_incl_vat_cents: 100000,
      currency: "EUR",
      included_services: [],
      mobilisation_disclosure: {},
      terms: {
        terms_revision: 1,
        cancellation_deadline_hours: 0,
        cancellation_penalty_percent: 0,
        waiting_time_included_minutes: 0,
        waiting_time_overage_cents_per_minute: 0,
        no_show_penalty_percent: 0,
        overtime_cents_per_hour: 0,
      },
    },
  });
  const emptyHtml = renderLimousineQuotationHtml(empty);
  assert.equal(emptyHtml.includes("Inbegrepen diensten"), false);
  assert.equal(emptyHtml.includes("Mobilisatie"), false);
  assert.equal(emptyHtml.includes("Klantverplichtingen"), false);
  assert.equal(emptyHtml.includes("Belangrijke informatie"), false);

  const guest = renderLimousineExternalQuotationPage({ locale: "en" });
  assert.equal(guest.includes("Included services"), true);
  assert.equal(guest.includes("quote.included_services"), true);
  assert.equal(guest.includes("terms.customer_obligations"), true);
  assert.equal(guest.includes("terms.important_information"), true);
  assert.equal(guest.includes("noteSection"), true);

  const guestNotes = limousineExternalQuoteNoteSections(frozen, "en");
  assert.deepEqual(
    guestNotes.map((row) => row.title),
    [
      "Included services",
      "Mobilisation",
      "Customer obligations",
      "Important information",
    ],
  );
  assert.equal(guestNotes[0].value, CHAMPAGNE);
  assert.equal(guestNotes[1].value, "Vanuit depot");
  assert.equal(guestNotes.some((row) => row.value.includes("bottles")), false);
  assert.deepEqual(limousineExternalQuoteNoteSections({ terms: {} }, "nl"), []);

  const view = publicLimousineQuoteView({
    quote_request_id: "limq_notes",
    tenant_id: "t1",
    company_id: "c1",
    state: "customer_acceptance_required",
    revision: 1,
    request: { journey_type: "point_to_point", from: "Gent", to: "Brussel", locale: "en" },
    quote: built.quote,
  });
  assert.equal(view.quote.included_services[0].label.nl, CHAMPAGNE);
  assert.equal(view.quote.terms.customer_obligations.nl, "Klaarstaan op de ophaallocatie");
  assert.equal(view.quote.terms.important_information.nl, "Niet roken");
});
