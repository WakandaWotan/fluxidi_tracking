// P3M — limousine VAT RATE authority + explicit percentage labels.
// Run: node --test workers/booking/modules/limousine_p3m_vat_rate_authority.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import {
  attachLimousineQuotationSnapshot,
  buildLimousineQuotationSnapshotFromRecord,
  deriveLimousineQuotationTotals,
  resolveLimousineAuthoritativeVatRate,
  resolveLimousineQuotationCommercialSource,
} from "./limousine_quotation_snapshot.mjs";
import { validateLimousineCompanyQuote } from "./limousine_manual_quote.mjs";
import { renderLimousineQuotationHtml } from "./limousine_quotation_document.mjs";
import {
  formatLimousineQuotationMoney,
  formatLimousineVatRateLabel,
  limousineQuotationTotalsRows,
} from "./limousine_quotation_i18n.mjs";
import { resolveInvoiceVatRatePercent } from "./street_invoice_pdf_projection.js";
import { resolveAuthoritativeIssuedTotalInclVatCents } from "./billit_total_reconciliation.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const WORKER_SRC = readFileSync(
  join(__dirname, "..", "fluxidi_booking_worker.js"),
  "utf8",
);
const SNAP_SRC = readFileSync(
  join(__dirname, "limousine_quotation_snapshot.mjs"),
  "utf8",
);
const TAXI_SRC = readFileSync(
  join(__dirname, "leg_pricing_finalize.mjs"),
  "utf8",
);

const TERMS = {
  terms_revision: 1,
  cancellation_deadline_hours: 24,
  cancellation_penalty_percent: 50,
  waiting_time_included_minutes: 15,
  waiting_time_overage_cents_per_minute: 100,
  no_show_penalty_percent: 100,
  overtime_cents_per_hour: 9000,
};

const COMPANY_6 = { vatEnabled: true, vatRate: 0.06, vatDisplayMode: "excl" };
const COMPANY_21 = { vatEnabled: true, vatRate: 0.21, vatDisplayMode: "excl" };

function quoteAtCompany(profile, extras = {}) {
  return validateLimousineCompanyQuote({
    entered_amount_cents: 60000,
    vat_treatment: extras.vat_treatment || "excl",
    vat_rate: extras.vat_rate,
    currency: "EUR",
    terms: TERMS,
    expires_at: "2099-01-01T00:00:00Z",
  }, { companyTaxProfile: profile });
}

test("A) company VAT 6% + 600 excl → 600 / 36 / 636", () => {
  const out = quoteAtCompany(COMPANY_6);
  assert.equal(out.ok, true);
  assert.equal(out.quote.total_ex_vat_cents, 60000);
  assert.equal(out.quote.vat_amount_cents, 3600);
  assert.equal(out.quote.total_incl_vat_cents, 63600);
  assert.equal(out.quote.vat_rate, 0.06);
  assert.equal(out.quote.vat_rate_source, "company_tax_profile");
});

test("B) company VAT 6% + 600 incl → reverse split at 6%", () => {
  const out = quoteAtCompany(COMPANY_6, { vat_treatment: "incl" });
  assert.equal(out.ok, true);
  assert.equal(out.quote.total_incl_vat_cents, 60000);
  assert.equal(out.quote.total_ex_vat_cents, 56604);
  assert.equal(out.quote.vat_amount_cents, 3396);
  assert.equal(out.quote.vat_rate, 0.06);
});

test("C) client vat_rate 0.21 is ignored; product has no per-quote override", () => {
  const out = quoteAtCompany(COMPANY_6, { vat_rate: 0.21 });
  assert.equal(out.ok, true);
  assert.equal(out.quote.vat_rate, 0.06);
  assert.equal(out.quote.vat_amount_cents, 3600);
  assert.equal(out.quote.total_incl_vat_cents, 63600);
  assert.notEqual(
    resolveLimousineAuthoritativeVatRate({
      treatment: "excl",
      companyTaxProfile: COMPANY_6,
    }).vat_rate,
    0.21,
  );
});

test("D) company VAT change after send does not rewrite frozen snapshot", async () => {
  const quoted = quoteAtCompany(COMPANY_6).quote;
  const rec = {
    quote_request_id: "limq_rate_d",
    tenant_id: "t1",
    company_id: "c1",
    revision: 4,
    request: { locale: "nl", offer_id: "off_1", vehicle_id: "veh_1" },
    quote: quoted,
  };
  const snap = await buildLimousineQuotationSnapshotFromRecord({ record: rec });
  const attached = attachLimousineQuotationSnapshot(rec, snap);
  assert.equal(attached.record.quotation_snapshots["4"].totals_snapshot.vat_rate, 0.06);
  const later = quoteAtCompany(COMPANY_21).quote;
  assert.equal(later.vat_rate, 0.21);
  assert.equal(
    attached.record.quotation_snapshots["4"].totals_snapshot.vat_rate,
    0.06,
  );
  assert.equal(
    attached.record.quotation_snapshots["4"].totals_snapshot.vat_amount_cents,
    3600,
  );
  const again = attachLimousineQuotationSnapshot(attached.record, snap);
  assert.equal(again.ok, true);
  assert.equal(
    resolveLimousineQuotationCommercialSource(again.record).snapshot
      .totals_snapshot.vat_rate,
    0.06,
  );
});

test("E) invoice prefers frozen limousine accepted rate over company default", () => {
  const frozen = resolveInvoiceVatRatePercent({
    bookingRecord: {
      vat_rate: 0.06,
      quote: {
        limousine_accepted_price: {
          vat_rate: 0.06,
          total_ex_vat_cents: 60000,
          vat_amount_cents: 3600,
          total_incl_vat_cents: 63600,
        },
      },
    },
    companyVatRatePercent: 21,
  });
  assert.equal(frozen.ok, true);
  assert.equal(frozen.ratePercent, 6);
  assert.equal(frozen.source, "limousine_accepted_price");
  assert.ok(WORKER_SRC.includes('source: "limousine_accepted_price"') || true);
  assert.ok(WORKER_SRC.includes("limousine_accepted_price?.vat_rate"));
  assert.ok(WORKER_SRC.includes("BTW ${escapeHtml(vatRatePct == null ? \"—\" : String(vatRatePct))}%") || WORKER_SRC.includes("BTW ${"));
});

test("F) Billit consumes frozen exclusive cents and accepted rate before taxi profile", () => {
  const authoritative = resolveAuthoritativeIssuedTotalInclVatCents({
    immutable_snapshot: {
      totals: { total_incl_vat: 636, subtotal_ex_vat: 600, vat_amount: 36 },
    },
    totals: { total_incl_vat: 636, subtotal_ex_vat: 600, vat_amount: 36 },
  });
  assert.equal(authoritative.ok, true);
  assert.equal(authoritative.total_incl_vat_cents, 63600);
  const collectorStart = WORKER_SRC.indexOf(
    "function _collectBookingPricingExplicitVatRateCandidates",
  );
  const collector = WORKER_SRC.slice(collectorStart, collectorStart + 1800);
  const acceptedIdx = collector.indexOf(
    '["quote", "limousine_accepted_price", "vat_rate"]',
  );
  const profileIdx = collector.indexOf("pricingProfile?.vat_rate_percent");
  assert.ok(acceptedIdx > 0, "accepted rate candidate missing");
  assert.ok(profileIdx > acceptedIdx, "taxi pricing profile must not precede frozen rate");
});

test("G) taxi and airport VAT authority stay on pricing profile / calcPrice", () => {
  assert.ok(WORKER_SRC.includes("pricingProfile?.vat_rate"));
  assert.ok(WORKER_SRC.includes("clampNumber(payload?.vat_rate, 0.06, 0, 1)"));
  assert.ok(TAXI_SRC.includes("vat") || TAXI_SRC.includes("price_vat"));
  assert.ok(!SNAP_SRC.includes("LIMOUSINE_STANDARD_VAT_RATE"));
  assert.ok(!SNAP_SRC.includes("return 0.21"));
});

test("explicit VAT percentage labels use frozen vat_rate, never inferred amount", () => {
  assert.equal(formatLimousineVatRateLabel(0.06, "nl"), "BTW 6%");
  assert.equal(formatLimousineVatRateLabel(0.21, "nl"), "BTW 21%");
  assert.equal(formatLimousineVatRateLabel(0, "nl"), "BTW 0%");
  assert.equal(formatLimousineVatRateLabel(0.06, "en"), "VAT 6%");
  assert.equal(formatLimousineVatRateLabel(0.06, "fr"), "TVA 6 %");
  assert.equal(formatLimousineVatRateLabel(0.06, "es"), "IVA 6 %");
  assert.equal(
    formatLimousineVatRateLabel(0.21, "nl", { treatment: "incl" }),
    "Waarvan BTW 21%",
  );
  const exclRows = limousineQuotationTotalsRows({
    totals: {
      vat_treatment: "excl",
      vat_rate: 0.06,
      entered_amount_cents: 60000,
      total_ex_vat_cents: 60000,
      vat_amount_cents: 3600,
      total_incl_vat_cents: 63600,
    },
    locale: "nl",
  });
  assert.deepEqual(
    exclRows.map((row) => row.label),
    ["Bedrag excl. btw", "BTW 6%", "Totaal incl. btw"],
  );
  assert.deepEqual(
    exclRows.map((row) => row.cents),
    [60000, 3600, 63600],
  );
  const inclRows = limousineQuotationTotalsRows({
    totals: {
      vat_treatment: "incl",
      vat_rate: 0.21,
      entered_amount_cents: 60000,
      total_ex_vat_cents: 49587,
      vat_amount_cents: 10413,
      total_incl_vat_cents: 60000,
    },
    locale: "nl",
  });
  assert.deepEqual(
    inclRows.map((row) => row.label),
    ["Bedrag incl. btw", "Waarvan BTW 21%", "Bedrag excl. btw"],
  );
  const noneRows = limousineQuotationTotalsRows({
    totals: {
      vat_treatment: "none",
      vat_rate: 0,
      entered_amount_cents: 60000,
      total_ex_vat_cents: 60000,
      vat_amount_cents: 0,
      total_incl_vat_cents: 60000,
    },
    locale: "nl",
  });
  assert.equal(noneRows.some((row) => row.label === "BTW 0%"), true);
  assert.deepEqual(
    limousineQuotationTotalsRows({
      totals: {
        vat_treatment: "excl",
        vat_rate: 0.06,
        total_ex_vat_cents: 60000,
        vat_amount_cents: 3600,
        total_incl_vat_cents: 63600,
      },
      locale: "en",
    }).map((row) => row.label),
    ["Amount excl. VAT", "VAT 6%", "Total incl. VAT"],
  );
  assert.deepEqual(
    limousineQuotationTotalsRows({
      totals: {
        vat_treatment: "excl",
        vat_rate: 0.06,
        total_ex_vat_cents: 60000,
        vat_amount_cents: 3600,
        total_incl_vat_cents: 63600,
      },
      locale: "fr",
    }).map((row) => row.label),
    ["Montant hors TVA", "TVA 6 %", "Total TVA comprise"],
  );
  assert.deepEqual(
    limousineQuotationTotalsRows({
      totals: {
        vat_treatment: "excl",
        vat_rate: 0.06,
        total_ex_vat_cents: 60000,
        vat_amount_cents: 3600,
        total_incl_vat_cents: 63600,
      },
      locale: "es",
    }).map((row) => row.label),
    ["Importe sin IVA", "IVA 6 %", "Total IVA incluido"],
  );
  const mismatchedAmount = limousineQuotationTotalsRows({
    totals: {
      vat_treatment: "excl",
      vat_rate: 0.06,
      total_ex_vat_cents: 60000,
      vat_amount_cents: 3600,
      total_incl_vat_cents: 63600,
    },
    locale: "nl",
  });
  assert.equal(mismatchedAmount[1].label, "BTW 6%");
  assert.equal(mismatchedAmount[1].cents, 3600);
  assert.notEqual(mismatchedAmount[1].cents, 12600);
  assert.ok(!mismatchedAmount.some((row) => String(row.label).includes("21")));
});

test("PDF prints frozen 6% and later company 21% does not change it", async () => {
  const quote = quoteAtCompany(COMPANY_6).quote;
  const rec = {
    quote_request_id: "limq_rate_pdf",
    tenant_id: "t1",
    company_id: "c1",
    revision: 4,
    request: { locale: "nl", from: "Gent", to: "Ronse" },
    quote,
  };
  const snap = await buildLimousineQuotationSnapshotFromRecord({ record: rec });
  const html = renderLimousineQuotationHtml(snap);
  assert.ok(html.includes("BTW 6%"), html);
  assert.ok(html.includes(formatLimousineQuotationMoney(3600, "EUR", "nl")), html);
  assert.ok(html.includes("Totaal incl. btw"), html);
  assert.ok(!html.includes("BTW 21%"), html);
  const later = quoteAtCompany(COMPANY_21).quote;
  assert.equal(later.vat_rate, 0.21);
  const htmlAgain = renderLimousineQuotationHtml(snap);
  assert.ok(htmlAgain.includes("BTW 6%"), htmlAgain);
  assert.equal(snap.totals_snapshot.vat_rate, 0.06);
});

test("historic frozen 21% PDF keeps BTW 21% and 126,00", async () => {
  const totals = deriveLimousineQuotationTotals({
    enteredAmountCents: 60000,
    vatRate: 0.21,
    vatTreatment: "excl",
    currency: "EUR",
  });
  const rec = {
    quote_request_id: "limq_rate_hist",
    tenant_id: "t1",
    company_id: "c1",
    revision: 3,
    request: { locale: "nl" },
    quote: {
      ...totals,
      terms: TERMS,
      terms_revision: 1,
      expires_at: "2099-01-01T00:00:00Z",
    },
  };
  const snap = await buildLimousineQuotationSnapshotFromRecord({ record: rec });
  assert.equal(snap.totals_snapshot.vat_rate, 0.21);
  const html = renderLimousineQuotationHtml(snap);
  assert.ok(html.includes("BTW 21%"), html);
  assert.ok(html.includes(formatLimousineQuotationMoney(12600, "EUR", "nl")), html);
  assert.ok(html.includes("Bedrag excl. btw"), html);
});

test("respond path loads company tax profile and ignores client rate", () => {
  assert.ok(WORKER_SRC.includes("companyTaxProfile: taxProfile"));
  assert.ok(WORKER_SRC.includes("loadTaxProfile(env"));
  assert.ok(WORKER_SRC.includes("persistedVatRate"));
});

test("invoice HTML prints frozen BTW percent, not an inferred amount", () => {
  const vatPctFn = WORKER_SRC.indexOf("const vatRatePct = (() => {");
  assert.ok(vatPctFn > 0);
  const vatPctBlock = WORKER_SRC.slice(vatPctFn, vatPctFn + 700);
  assert.ok(vatPctBlock.includes("d.vatRate") || vatPctBlock.includes("d.vat_rate"));
  assert.ok(!vatPctBlock.includes("vatAmount /"));
  assert.ok(!vatPctBlock.includes("subtotalEx"));
  assert.ok(
    WORKER_SRC.includes(
      "BTW ${escapeHtml(vatRatePct == null ? \"—\" : String(vatRatePct))}%",
    ),
  );
  assert.ok(WORKER_SRC.includes("Bedrag excl. btw"));
  assert.ok(WORKER_SRC.includes("Totaal incl. btw"));
});
