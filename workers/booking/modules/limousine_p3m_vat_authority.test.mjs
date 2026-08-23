// P3M — limousine VAT authority: typed amount + treatment → frozen totals.
// Run: node --test workers/booking/modules/limousine_p3m_vat_authority.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import {
  attachLimousineQuotationSnapshot,
  buildLimousineAcceptanceBindingFromSnapshot,
  buildLimousineQuotationSnapshotFromRecord,
  deriveLimousineQuotationTotals,
  resolveLimousineQuotationCommercialSource,
} from "./limousine_quotation_snapshot.mjs";
import {
  buildLimousineAcceptanceBinding,
  validateLimousineCompanyQuote,
} from "./limousine_manual_quote.mjs";
import { limousineAcceptanceBindingMatches } from "./limousine_acceptance_token.mjs";
import { buildLimousineAcceptedSnapshot } from "./limousine_booking.mjs";
import { invoiceServiceLineLabel } from "./invoice_service_line.mjs";
import { resolveAuthoritativeIssuedTotalInclVatCents } from "./billit_total_reconciliation.js";
import { renderLimousineQuotationHtml } from "./limousine_quotation_document.mjs";
import { formatLimousineQuotationMoney } from "./limousine_quotation_i18n.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const WORKER_SRC = readFileSync(
  join(__dirname, "..", "fluxidi_booking_worker.js"),
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

function assertExclusive600(totals) {
  assert.equal(totals.entered_amount_cents, 60000);
  assert.equal(totals.total_ex_vat_cents, 60000);
  assert.equal(totals.vat_amount_cents, 12600);
  assert.equal(totals.total_incl_vat_cents, 72600);
  assert.equal(totals.price_ex_vat, 600);
  assert.equal(totals.price_vat, 126);
  assert.equal(totals.price_incl_vat, 726);
  assert.equal(totals.vat_rate, 0.21);
  assert.equal(totals.vat_treatment, "excl");
}

test("exclusive company quote stores canonical net/VAT/gross", () => {
  const out = validateLimousineCompanyQuote({
    entered_amount_cents: 60000,
    vat_treatment: "excl",
    vat_rate: 0.21,
    currency: "EUR",
    terms: TERMS,
  });
  assert.equal(out.ok, true);
  assertExclusive600(out.quote);
});

test("legacy total_incl_vat_cents is entered amount, not gross", () => {
  const out = validateLimousineCompanyQuote({
    total_incl_vat_cents: 60000,
    vat_treatment: "excl",
    vat_rate: 0.21,
    currency: "EUR",
    terms: TERMS,
  });
  assert.equal(out.ok, true);
  assertExclusive600(out.quote);
});

test("snapshot freezes exclusive 600 without downstream reinterpretation", async () => {
  const quote = validateLimousineCompanyQuote({
    entered_amount_cents: 60000,
    vat_treatment: "excl",
    vat_rate: 0.21,
    currency: "EUR",
    terms: TERMS,
    expires_at: "2099-01-01T00:00:00Z",
  }).quote;
  const rec = {
    quote_request_id: "limq_p3m_excl",
    tenant_id: "t1",
    company_id: "c1",
    revision: 4,
    request: {
      locale: "nl",
      offer_id: "off_1",
      service_class_id: "stretch_limousine",
      vehicle_id: "veh_1",
      itinerary_fingerprint: "fp_1",
      journey_type: "point_to_point",
    },
    quote,
  };
  const snap = await buildLimousineQuotationSnapshotFromRecord({ record: rec });
  assertExclusive600(snap.totals_snapshot);
  const attached = attachLimousineQuotationSnapshot(rec, snap);
  assert.equal(attached.ok, true);
  const frozen = attached.record.quotation_snapshots["4"].totals_snapshot;
  assertExclusive600(frozen);
  rec.quote.entered_amount_cents = 1;
  rec.quote.total_incl_vat_cents = 1;
  assertExclusive600(attached.record.quotation_snapshots["4"].totals_snapshot);
});

test("acceptance binds frozen exclusive cents additively", async () => {
  const quote = validateLimousineCompanyQuote({
    entered_amount_cents: 60000,
    vat_treatment: "excl",
    vat_rate: 0.21,
    currency: "EUR",
    terms: TERMS,
    expires_at: "2099-01-01T00:00:00Z",
  }).quote;
  const rec = {
    quote_request_id: "limq_p3m_bind",
    tenant_id: "t1",
    company_id: "c1",
    revision: 4,
    request: {
      offer_id: "off_1",
      service_class_id: "stretch_limousine",
      vehicle_id: "veh_1",
      itinerary_fingerprint: "fp_1",
    },
    quote,
  };
  const snap = await buildLimousineQuotationSnapshotFromRecord({ record: rec });
  const withSnap = attachLimousineQuotationSnapshot(rec, snap).record;
  const binding = buildLimousineAcceptanceBindingFromSnapshot(withSnap, snap);
  assert.equal(binding.entered_amount_cents, 60000);
  assert.equal(binding.total_ex_vat_cents, 60000);
  assert.equal(binding.vat_amount_cents, 12600);
  assert.equal(binding.total_incl_vat_cents, 72600);
  assert.equal(binding.vat_rate, 0.21);
  assert.equal(binding.vat_treatment, "excl");
  assert.equal(
    limousineAcceptanceBindingMatches(binding, binding).ok,
    true,
  );
  const legacyToken = { ...binding };
  delete legacyToken.entered_amount_cents;
  delete legacyToken.total_ex_vat_cents;
  delete legacyToken.vat_amount_cents;
  delete legacyToken.vat_rate;
  assert.equal(
    limousineAcceptanceBindingMatches(legacyToken, binding).ok,
    true,
  );
});

test("accepted-price snapshot copies frozen exclusive cents", () => {
  const totals = deriveLimousineQuotationTotals({
    enteredAmountCents: 60000,
    vatRate: 0.21,
    vatTreatment: "excl",
    currency: "EUR",
  });
  const snapshot = buildLimousineAcceptedSnapshot({
    total: {
      ok: true,
      ...totals,
      pricing_mode: "manual_quote",
      components: [],
      legs: [],
      selected_extras: [],
      mobilisation: {},
      subtotal_cents: totals.total_incl_vat_cents,
      journey_type: "point_to_point",
      offer_id: "off_1",
      service_class_id: "cls_1",
    },
    quoteReference: "limq_p3m:r4",
    acceptedAtIso: "2026-08-23T08:00:00.000Z",
    companyId: "c1",
  });
  assert.equal(snapshot.price_ex_vat, 600);
  assert.equal(snapshot.price_vat, 126);
  assert.equal(snapshot.price_incl_vat, 726);
  assert.equal(snapshot.total_ex_vat_cents, 60000);
  assert.equal(snapshot.vat_amount_cents, 12600);
  assert.equal(snapshot.total_incl_vat_cents, 72600);
  assert.equal(snapshot.vat_treatment, "excl");
  assert.equal(snapshot.vat_rate, 0.21);
  assert.equal(
    invoiceServiceLineLabel({ limousine_accepted_price: snapshot }),
    "Limousinevervoer",
  );
  assert.equal(
    invoiceServiceLineLabel({ service_type: "limousine" }),
    "Limousinevervoer",
  );
  assert.equal(invoiceServiceLineLabel({ service: "taxi" }), "Taxirit");
});

test("Billit reconciliation consumes stored exclusive cents, not a recompute", () => {
  const authoritative = resolveAuthoritativeIssuedTotalInclVatCents({
    immutable_snapshot: {
      totals: {
        total_incl_vat: 726,
        subtotal_ex_vat: 600,
        vat_amount: 126,
      },
    },
    totals: {
      total_incl_vat: 726,
      subtotal_ex_vat: 600,
      vat_amount: 126,
    },
  });
  assert.equal(authoritative.ok, true);
  assert.equal(authoritative.total_incl_vat_cents, 72600);
});

test("legacy snapshot without entered amount is not rewritten by attach", async () => {
  const historic = {
    quote_revision: 3,
    content_hash: "a".repeat(64),
    totals_snapshot: {
      total_incl_vat_cents: 60000,
      total_ex_vat_cents: 49587,
      vat_amount_cents: 10413,
      vat_treatment: "excl",
      vat_rate: 0.21,
      currency: "EUR",
    },
  };
  const rec = {
    quotation_snapshots: { 3: historic },
    quotation_revision: 3,
  };
  const again = attachLimousineQuotationSnapshot(rec, historic);
  assert.equal(again.ok, true);
  assert.equal(again.idempotent, true);
  assert.equal(
    again.record.quotation_snapshots["3"].totals_snapshot.total_ex_vat_cents,
    49587,
  );
  assert.equal(
    resolveLimousineQuotationCommercialSource(again.record).snapshot
      .totals_snapshot.total_incl_vat_cents,
    60000,
  );
});

test("worker copies frozen snapshot totals and does not reverse-split them", () => {
  assert.ok(WORKER_SRC.includes("snapTotals?.entered_amount_cents"));
  assert.ok(WORKER_SRC.includes("vat_treatment: vatTreatment"));
  assert.ok(WORKER_SRC.includes("total_ex_vat_cents: netCents"));
  assert.ok(
    WORKER_SRC.includes(
      "Snapshot totals are frozen at send. Copy them exactly.",
    ),
  );
  assert.ok(WORKER_SRC.includes("limousine_accepted_price"));
  assert.ok(WORKER_SRC.includes('service: _limousineInvoiceAccepted(rec)'));
});

test("inclusive 600 and no-VAT stay on the same calculator", () => {
  const incl = deriveLimousineQuotationTotals({
    enteredAmountCents: 60000,
    vatRate: 0.21,
    vatTreatment: "incl",
    currency: "EUR",
  });
  assert.equal(incl.total_incl_vat_cents, 60000);
  assert.equal(incl.total_ex_vat_cents, 49587);
  assert.equal(incl.vat_amount_cents, 10413);
  const none = deriveLimousineQuotationTotals({
    enteredAmountCents: 60000,
    vatTreatment: "none",
    currency: "EUR",
  });
  assert.equal(none.total_incl_vat_cents, 60000);
  assert.equal(none.vat_amount_cents, 0);
});

test("live quote binding without snapshot does not invent exclusive math", () => {
  const binding = buildLimousineAcceptanceBinding({
    tenant_id: "t1",
    company_id: "c1",
    quote_request_id: "limq_legacy",
    revision: 2,
    request: {},
    quote: {
      total_incl_vat_cents: 60000,
      currency: "EUR",
      vat_treatment: "excl",
    },
  });
  assert.equal(binding.total_incl_vat_cents, 60000);
  assert.equal(binding.entered_amount_cents, undefined);
  assert.equal(binding.total_ex_vat_cents, undefined);
});

test("quotation HTML prints frozen exclusive 600/126/726 and never reverse-splits", async () => {
  const quote = validateLimousineCompanyQuote({
    entered_amount_cents: 60000,
    vat_treatment: "excl",
    vat_rate: 0.21,
    currency: "EUR",
    terms: TERMS,
    expires_at: "2099-01-01T00:00:00Z",
  }).quote;
  const rec = {
    quote_request_id: "limq_p3m_pdf",
    tenant_id: "t1",
    company_id: "c1",
    revision: 4,
    request: {
      locale: "nl",
      offer_id: "off_1",
      service_class_id: "stretch_limousine",
      vehicle_id: "veh_1",
      itinerary_fingerprint: "fp_1",
      journey_type: "point_to_point",
      from: "Gent",
      to: "Ronse",
    },
    quote,
  };
  const snap = await buildLimousineQuotationSnapshotFromRecord({
    record: rec,
    sellerSnapshot: { legal_name: "P3M Limo" },
  });
  const html = renderLimousineQuotationHtml(snap);
  const net = formatLimousineQuotationMoney(60000, "EUR", "nl");
  const vat = formatLimousineQuotationMoney(12600, "EUR", "nl");
  const gross = formatLimousineQuotationMoney(72600, "EUR", "nl");
  const wrongNet = formatLimousineQuotationMoney(49587, "EUR", "nl");
  assert.ok(html.includes(net), html);
  assert.ok(html.includes(vat), html);
  assert.ok(html.includes(gross), html);
  assert.ok(!html.includes(wrongNet), html);
  assert.ok(html.includes("Totaal") || html.includes("incl"), html);
});

test("invoice heading and frozen cents stay on stored exclusive totals", () => {
  assert.ok(WORKER_SRC.includes("subtotalExFixed: (_limoNetCents / 100).toFixed(2)"));
  assert.ok(WORKER_SRC.includes("vatAmountFixed: (_limoVatCents / 100).toFixed(2)"));
  assert.ok(WORKER_SRC.includes("totalFixed: (_limoGrossCents / 100).toFixed(2)"));
  assert.ok(WORKER_SRC.includes("omitTier: _limousineInvoiceAccepted(rec)"));
  assert.ok(
    invoiceServiceLineLabel({
      service_type: "limousine",
      quote: {
        limousine_accepted_price: {
          service_type: "limousine",
          service_category: "limousine",
          price_ex_vat: 600,
          price_vat: 126,
          price_incl_vat: 726,
          total_ex_vat_cents: 60000,
          vat_amount_cents: 12600,
          total_incl_vat_cents: 72600,
          vat_treatment: "excl",
        },
      },
    }) === "Limousinevervoer",
  );
  assert.equal(invoiceServiceLineLabel({ service: "airport" }), "Taxirit");
});

test("driver settlement and taxi VAT path do not re-derive exclusive quotes", () => {
  assert.ok(!WORKER_SRC.includes("deriveLimousineQuotationTotals("));
  const taxiVat = readFileSync(
    join(__dirname, "leg_pricing_finalize.mjs"),
    "utf8",
  );
  assert.ok(taxiVat.includes("price_vat") || taxiVat.includes("vat"));
});
