import { test } from "node:test";
import assert from "node:assert/strict";
import {
  normalizePaymentMethodId,
  resolvePaymentMethodTruth,
  resolvePaymentMethodTruthFromRecord,
  mergePaymentMethodIds,
  mapPaymentMethodTruthToBillitPaymentMethod,
  formatPaymentMethodLabelNl,
  applyPaymentMethodTruthToBookingRecord,
  buildBillitPaymentInternalInfoFromTruth,
  mergeDocumentPaymentMethodMetadata,
  fixtureOnlinePaymentMollieBookingTruth,
  buildPaymentMethodTruthRecord,
} from "./payment_method_truth.js";
import { mapFluxidiPaymentMethodToBillitPaymentMethod } from "./billit_provider.js";
import {
  formatFluxidiPaymentMethodLabel,
  buildStreetInvoicePdfProjection,
} from "./street_invoice_pdf_projection.js";

test("matrix: ideal + mollie → online, iDEAL, Billit not Wired", () => {
  const t = resolvePaymentMethodTruth({
    bookingMethod: "ideal",
    provider: "mollie",
    providerMethod: "ideal",
    status: "paid",
  });
  assert.equal(t.method_id, "ideal");
  assert.equal(t.category, "online");
  assert.equal(t.label_nl, "iDEAL");
  assert.equal(mapPaymentMethodTruthToBillitPaymentMethod(t), null);
  assert.equal(mapFluxidiPaymentMethodToBillitPaymentMethod("ideal", "mollie", ""), null);
});

test("matrix: bancontact → not Wired", () => {
  const t = resolvePaymentMethodTruth({ bookingMethod: "bancontact", provider: "mollie" });
  assert.equal(t.label_nl, "Bancontact");
  assert.equal(mapPaymentMethodTruthToBillitPaymentMethod(t), null);
  assert.equal(mapFluxidiPaymentMethodToBillitPaymentMethod("bancontact", "mollie", ""), null);
});

test("matrix: card_payment → not Wired", () => {
  const t = resolvePaymentMethodTruth({
    bookingMethod: "card_payment",
    providerMethod: "creditcard",
    provider: "mollie",
  });
  assert.equal(t.method_id, "card_payment");
  assert.equal(t.label_nl, "Kaart");
  assert.equal(mapPaymentMethodTruthToBillitPaymentMethod(t), null);
});

test("matrix: paypal → not Wired", () => {
  const t = resolvePaymentMethodTruth({ bookingMethod: "paypal", provider: "mollie" });
  assert.equal(t.label_nl, "PayPal");
  assert.equal(mapPaymentMethodTruthToBillitPaymentMethod(t), null);
});

test("matrix: online_payment + mollie → Online betaling, not Wired", () => {
  const t = resolvePaymentMethodTruth({
    bookingMethod: "online_payment",
    provider: "mollie",
    status: "paid",
  });
  assert.equal(t.method_id, "online_payment");
  assert.equal(t.category, "online");
  assert.equal(t.label_nl, "Online betaling");
  assert.equal(mapPaymentMethodTruthToBillitPaymentMethod(t), null);
  assert.equal(
    mapFluxidiPaymentMethodToBillitPaymentMethod("online_payment", "mollie", ""),
    null,
  );
});

test("matrix: qr_code → QR-betaling, not Wired", () => {
  const t = resolvePaymentMethodTruth({ bookingMethod: "qr_code", provider: "manual" });
  assert.equal(t.category, "qr");
  assert.equal(t.label_nl, "QR-betaling");
  assert.equal(mapPaymentMethodTruthToBillitPaymentMethod(t), null);
  assert.equal(mapFluxidiPaymentMethodToBillitPaymentMethod("qr_code", "manual", "qr"), null);
});

test("matrix: cash → Contant, Billit omit", () => {
  const t = resolvePaymentMethodTruth({ bookingMethod: "cash", provider: "manual" });
  assert.equal(t.label_nl, "Contant");
  assert.equal(mapPaymentMethodTruthToBillitPaymentMethod(t), null);
  assert.equal(mapFluxidiPaymentMethodToBillitPaymentMethod("cash", "manual", "in_car"), null);
});

test("matrix: in_vehicle_card → label + omit", () => {
  const t = resolvePaymentMethodTruth({
    bookingMethod: "in_car",
    provider: "manual",
  });
  assert.equal(t.method_id, "in_vehicle_card");
  assert.equal(t.label_nl, "Betaling in de wagen");
  assert.equal(mapPaymentMethodTruthToBillitPaymentMethod(t), null);
});

test("matrix: bank_transfer_bacs → Wired", () => {
  const t = resolvePaymentMethodTruth({ bookingMethod: "bank_transfer_bacs" });
  assert.equal(t.category, "bank_transfer");
  assert.equal(t.label_nl, "Bankoverschrijving");
  assert.equal(mapPaymentMethodTruthToBillitPaymentMethod(t), "Wired");
  assert.equal(
    mapFluxidiPaymentMethodToBillitPaymentMethod("bank_transfer_bacs", "manual", ""),
    "Wired",
  );
});

test("matrix: sepa / wire_transfer aliases → Wired", () => {
  assert.equal(normalizePaymentMethodId("sepa"), "bank_transfer_bacs");
  assert.equal(normalizePaymentMethodId("wire_transfer"), "bank_transfer_bacs");
  assert.equal(
    mapPaymentMethodTruthToBillitPaymentMethod(
      resolvePaymentMethodTruth({ bookingMethod: "sepa" }),
    ),
    "Wired",
  );
  assert.equal(
    mapFluxidiPaymentMethodToBillitPaymentMethod("sepa", "manual", ""),
    "Wired",
  );
});

test("matrix: unknown future online method retained, not Wired", () => {
  const t = resolvePaymentMethodTruth({
    bookingMethod: "future_psp_xyz",
    provider: "mollie",
  });
  assert.equal(t.method_id, "future_psp_xyz");
  assert.equal(t.category, "online");
  assert.equal(mapPaymentMethodTruthToBillitPaymentMethod(t), null);
});

test("provider-confirmed method wins over generic booking value", () => {
  const t = resolvePaymentMethodTruth({
    bookingMethod: "online_payment",
    providerConfirmedMethod: "ideal",
    providerMethod: "ideal",
    provider: "mollie",
  });
  assert.equal(t.method_id, "ideal");
  assert.equal(t.label_nl, "iDEAL");
});

test("generic retry does not overwrite concrete method", () => {
  assert.equal(mergePaymentMethodIds("ideal", "online_payment"), "ideal");
  const rec = {
    payment_method: "ideal",
    payment_provider: "mollie",
    payment_status: "paid",
  };
  const applied = applyPaymentMethodTruthToBookingRecord(
    rec,
    buildPaymentMethodTruthRecord({
      methodId: "online_payment",
      provider: "mollie",
    }),
  );
  assert.equal(applied.ok, true);
  assert.equal(rec.payment_method, "ideal");
});

test("fixture street_1785684244820_97ofs7tm shape", () => {
  const t = fixtureOnlinePaymentMollieBookingTruth();
  assert.equal(t.method_id, "online_payment");
  assert.equal(t.category, "online");
  assert.equal(t.provider, "mollie");
  assert.equal(t.label_nl, "Online betaling");
  assert.equal(mapPaymentMethodTruthToBillitPaymentMethod(t), null);
  const info = buildBillitPaymentInternalInfoFromTruth(t);
  assert.match(info, /online_payment/);
  assert.match(info, /mollie/);
  assert.doesNotMatch(info, /Wired/i);

  const fromRec = resolvePaymentMethodTruthFromRecord({
    payment_status: "paid",
    payment_method: "online_payment",
    payment_provider: "mollie",
    payment_id: "tr_owcLVpyhvpKqoTx2RipUJ",
    paid_at: "2026-08-02T15:25:37.740Z",
    mollie: { id: "tr_owcLVpyhvpKqoTx2RipUJ", status: "paid" },
  });
  assert.equal(fromRec.method_id, "online_payment");
  assert.equal(fromRec.label_nl, "Online betaling");
});

test("PDF labels use central resolver table", () => {
  assert.equal(formatFluxidiPaymentMethodLabel("ideal"), "iDEAL");
  assert.equal(formatFluxidiPaymentMethodLabel("online_payment"), "Online betaling");
  assert.equal(formatFluxidiPaymentMethodLabel("qr_code"), "QR-betaling");
  assert.equal(formatPaymentMethodLabelNl("ideal"), formatFluxidiPaymentMethodLabel("ideal"));

  const projection = buildStreetInvoicePdfProjection({
    scope: { tenant_id: "t1", company_id: "c1" },
    bookingId: "b1",
    bookingRecord: {
      tenant_id: "t1",
      company_id: "c1",
      payment_status: "paid",
      payment_method: "ideal",
      price_incl_vat: 5.3,
      price_vat: 0.3,
      price_ex_vat: 5.0,
      vat_rate_percent: 6,
      booking: {
        from: "A",
        to: "B",
        payment_status: "paid",
        payment_method: "ideal",
      },
    },
    invoiceNumber: "INV-2026-000099",
    companyVatRatePercent: 6,
    communicationProfile: {
      brandName: "Fluxidi",
      legalName: "Test",
      vatNumber: "BE0772931038",
    },
  });
  assert.equal(projection.ok, true, projection.error || "projection_failed");
  assert.equal(projection.paymentMethodLabel, "iDEAL");
  assert.equal(projection.invoiceInput.paymentMethod, "iDEAL");
});

test("no amount/VAT/status regression helpers; document metadata merge safe", () => {
  const truth = resolvePaymentMethodTruth({
    bookingMethod: "ideal",
    provider: "mollie",
    status: "paid",
    paidAt: "2026-08-02T15:25:37.740Z",
    providerRef: "tr_abc",
  });
  const issued = {
    document_id: "doc-1",
    document_number: "INV-2026-000035",
    immutable_snapshot: { totals: { total_incl_vat: 5.3 }, seller_snapshot: { x: 1 } },
    content_hash: "abc",
    totals: { total_incl_vat: 5.3, vat_amount: 0.3, vat_rate_percent: 6 },
  };
  const merged = mergeDocumentPaymentMethodMetadata(issued, truth);
  assert.equal(merged.ok, true);
  assert.equal(merged.record.document_number, "INV-2026-000035");
  assert.equal(merged.record.content_hash, "abc");
  assert.equal(merged.record.totals.total_incl_vat, 5.3);
  assert.deepEqual(merged.record.immutable_snapshot.totals, { total_incl_vat: 5.3 });
  assert.equal(merged.payment_method_truth.method_id, "ideal");
  // Refine with generic must not wipe ideal
  const again = mergeDocumentPaymentMethodMetadata(
    merged.record,
    resolvePaymentMethodTruth({ bookingMethod: "online_payment", provider: "mollie" }),
  );
  assert.equal(again.payment_method_truth.method_id, "ideal");
});

test("cross-tenant: resolver is scope-agnostic pure; ids stay bounded", () => {
  const a = resolvePaymentMethodTruth({ bookingMethod: "ideal", provider: "mollie" });
  const b = resolvePaymentMethodTruth({ bookingMethod: "ideal", provider: "mollie" });
  assert.deepEqual(
    { method_id: a.method_id, category: a.category, label_nl: a.label_nl },
    { method_id: b.method_id, category: b.category, label_nl: b.label_nl },
  );
  assert.equal(normalizePaymentMethodId("IDEAL!!!"), "ideal");
});
