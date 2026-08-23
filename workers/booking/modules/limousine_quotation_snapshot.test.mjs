// LIMOUSINE-QUOTE-DOCUMENT-P3J — immutable quotation snapshot contract.
// Run: node --test workers/booking/modules/limousine_quotation_snapshot.test.mjs

import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import {
  LIMOUSINE_QUOTATION_SCHEMA_VERSION,
  LIMOUSINE_QUOTATION_RENDERER_VERSION,
  LIMOUSINE_QUOTATION_SNAPSHOT_CONFLICT,
  attachLimousineQuotationSnapshot,
  buildLimousineQuotationSnapshot,
  buildLimousineQuotationSnapshotFromRecord,
  deriveLimousineQuotationTotals,
  freezeLimousineQuotationOfferSnapshot,
  freezeLimousineQuotationRequestSnapshot,
  freezeLimousineQuotationSellerSnapshot,
  freezeLimousineQuotationVehicleSnapshot,
  projectLimousineQuotationAvailability,
  quotationSnapshotContainsForbiddenKey,
  resolveLimousineQuotationCommercialSource,
  resolveLimousineQuotationSnapshot,
} from "./limousine_quotation_snapshot.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));

const TERMS = {
  terms_revision: 3,
  cancellation_deadline_hours: 24,
  cancellation_penalty_percent: 50,
  waiting_time_included_minutes: 15,
  waiting_time_overage_cents_per_minute: 100,
  no_show_penalty_percent: 100,
  overtime_cents_per_hour: 9000,
  customer_obligations: { nl: "Klaarstaan", en: "Be ready" },
  important_information: { en: "No smoking" },
};

function baseInput(overrides = {}) {
  return {
    quoteRequestId: "limq_snap_1",
    quoteRevision: 3,
    offerSourceRevision: 2,
    pricingSectionRevision: 1,
    termsRevision: 3,
    issuedAt: "2026-08-22T08:00:00Z",
    expiresAt: "2026-08-24T08:00:00Z",
    locale: "nl",
    sellerSnapshot: {
      name: "Coachline",
      trading_name: "Coachline",
      legal_name: "Coachline BV",
      vat_number: "BE0772931038",
      enterprise_number: "0772931038",
      address_line: "Markt 1",
      postal_code: "9000",
      city: "Gent",
      country_code: "BE",
      contact_email: "billing@coachline.test",
      logo: { present: false },
    },
    requestSnapshot: {
      journey_type: "point_to_point",
      from: "Gent",
      to: "Brussel",
      stops: ["Aalst"],
      scheduled_pickup_iso: "2026-09-01T10:00:00Z",
      pax: 2,
      bags: 1,
      occasion: "wedding",
      customer_note: "Gate 2",
      selected_extra_ids: ["deco"],
      public_partner_id: "company:t1:c1",
      offer_id: "off_1",
      service_class_id: "executive_sedan",
      vehicle_id: "veh_1",
      itinerary_fingerprint: "fp_1",
      locale: "nl",
    },
    vehicleSnapshot: {
      vehicle_id: "veh_1",
      public_name: "Executive sedan",
      service_class_id: "executive_sedan",
      passenger_capacity: 3,
      luggage_capacity: 2,
    },
    offerSnapshot: {
      total_incl_vat_cents: 45000,
      currency: "EUR",
      vat_treatment: "incl",
      vat_rate: 0.06,
      public_text: { nl: "Vaste prijs", en: "Fixed price" },
      included_services: [{ item_id: "water", label: { nl: "Water" } }],
      separately_priced_extras: [
        { extra_id: "deco", label: { nl: "Decoratie" }, amount_cents: 2500 },
      ],
      mobilisation_disclosure: { nl: "Inbegrepen", en: "Included" },
      terms: TERMS,
      terms_revision: 3,
      quoted_at: "2026-08-22T08:00:00Z",
      expires_at: "2026-08-24T08:00:00Z",
    },
    ...overrides,
  };
}

test("1-12) snapshot shape, versions, frozen facts and integer-cent totals", async () => {
  const snap = await buildLimousineQuotationSnapshot(baseInput());
  assert.equal(snap.schema_version, LIMOUSINE_QUOTATION_SCHEMA_VERSION);
  assert.equal(snap.renderer_version, LIMOUSINE_QUOTATION_RENDERER_VERSION);
  assert.equal(snap.quote_request_id, "limq_snap_1");
  assert.equal(snap.quote_revision, 3);
  assert.equal(snap.request_snapshot.from, "Gent");
  assert.equal(snap.vehicle_snapshot.public_name, "Executive sedan");
  assert.equal(snap.offer_snapshot.terms.cancellation_deadline_hours, 24);
  assert.equal(snap.seller_snapshot.legal_name, "Coachline BV");
  assert.equal(snap.seller_snapshot.logo.present, false);
  assert.equal(snap.totals_snapshot.total_incl_vat_cents, 45000);
  assert.equal(snap.totals_snapshot.currency, "EUR");
  assert.equal(typeof snap.totals_snapshot.total_ex_vat_cents, "number");
  assert.equal(typeof snap.totals_snapshot.vat_amount_cents, "number");
  assert.equal(
    snap.totals_snapshot.total_ex_vat_cents + snap.totals_snapshot.vat_amount_cents,
    snap.totals_snapshot.total_incl_vat_cents,
  );
  assert.match(snap.content_hash, /^[a-f0-9]{64}$/);
});

test("13-14) same input and irrelevant property order share a stable hash", async () => {
  const a = await buildLimousineQuotationSnapshot(baseInput());
  const b = await buildLimousineQuotationSnapshot(baseInput());
  assert.equal(a.content_hash, b.content_hash);
  const reordered = await buildLimousineQuotationSnapshot(
    baseInput({
      requestSnapshot: {
        to: "Brussel",
        from: "Gent",
        journey_type: "point_to_point",
        stops: ["Aalst"],
        scheduled_pickup_iso: "2026-09-01T10:00:00Z",
        pax: 2,
        bags: 1,
        occasion: "wedding",
        customer_note: "Gate 2",
        selected_extra_ids: ["deco"],
        public_partner_id: "company:t1:c1",
        offer_id: "off_1",
        service_class_id: "executive_sedan",
        vehicle_id: "veh_1",
        itinerary_fingerprint: "fp_1",
      },
    }),
  );
  assert.equal(a.content_hash, reordered.content_hash);
});

test("15-16) same revision+hash is idempotent; different hash conflicts", async () => {
  const snap = await buildLimousineQuotationSnapshot(baseInput());
  const rec = { quote_request_id: "limq_snap_1", revision: 3 };
  const first = attachLimousineQuotationSnapshot(rec, snap);
  assert.equal(first.ok, true);
  const replay = attachLimousineQuotationSnapshot(first.record, snap);
  assert.equal(replay.ok, true);
  assert.equal(replay.idempotent, true);
  const other = await buildLimousineQuotationSnapshot(
    baseInput({ offerSnapshot: { ...baseInput().offerSnapshot, total_incl_vat_cents: 50000 } }),
  );
  other.quote_revision = 3;
  const conflict = attachLimousineQuotationSnapshot(first.record, {
    ...other,
    quote_revision: 3,
  });
  assert.equal(conflict.ok, false);
  assert.equal(conflict.reason, LIMOUSINE_QUOTATION_SNAPSHOT_CONFLICT);
  assert.equal(
    first.record.quotation_snapshots["3"].content_hash,
    snap.content_hash,
  );
});

test("17-21) re-quote preserves old snapshot; later mutations do not rewrite it", async () => {
  const firstSnap = await buildLimousineQuotationSnapshot(baseInput());
  let rec = { quote_request_id: "limq_snap_1", revision: 3, quote: { total_incl_vat_cents: 45000 } };
  rec = attachLimousineQuotationSnapshot(rec, firstSnap).record;
  const secondSnap = await buildLimousineQuotationSnapshot(
    baseInput({
      quoteRevision: 5,
      termsRevision: 4,
      offerSnapshot: {
        ...baseInput().offerSnapshot,
        total_incl_vat_cents: 52000,
        terms_revision: 4,
      },
      sellerSnapshot: {
        ...baseInput().sellerSnapshot,
        legal_name: "New Legal BV",
      },
      vehicleSnapshot: {
        ...baseInput().vehicleSnapshot,
        public_name: "Renamed car",
      },
    }),
  );
  rec = attachLimousineQuotationSnapshot(rec, secondSnap).record;
  assert.equal(rec.quotation_snapshots["3"].content_hash, firstSnap.content_hash);
  assert.equal(rec.quotation_snapshots["3"].seller_snapshot.legal_name, "Coachline BV");
  assert.equal(rec.quotation_snapshots["3"].vehicle_snapshot.public_name, "Executive sedan");
  assert.equal(rec.quotation_snapshots["5"].totals_snapshot.total_incl_vat_cents, 52000);
  rec.quote = { total_incl_vat_cents: 1 };
  assert.equal(rec.quotation_snapshots["3"].totals_snapshot.total_incl_vat_cents, 45000);
});

test("22-27) forbidden PII, tokens, payment and invoice fields cannot enter the snapshot", async () => {
  const snap = await buildLimousineQuotationSnapshot(
    baseInput({
      requestSnapshot: {
        ...baseInput().requestSnapshot,
        status_ref: "limqs1.secret",
        acceptance_reference: "limacc1.secret",
        customer_email: "ada@example.com",
        customer_phone: "+320000",
        customer_name: "Ada",
        billing_customer: { vat_number: "BE000" },
        invoice_intent: true,
        invoice_number: "INV-1",
        source_booking_id: "bk_1",
        billit: { id: "x" },
        peppol: { ready: true },
        payment_capability: { online: true },
        email: "hidden@example.com",
        phone: "+32999",
      },
      sellerSnapshot: {
        ...baseInput().sellerSnapshot,
        status_ref: "should-not-copy",
        invoice_document_id: "doc_1",
      },
    }),
  );
  const json = JSON.stringify(snap);
  assert.equal(snap.request_snapshot.status_ref, undefined);
  assert.equal(snap.request_snapshot.acceptance_reference, undefined);
  assert.equal(snap.request_snapshot.customer_email, undefined);
  assert.equal(snap.request_snapshot.billing_customer, undefined);
  assert.equal(snap.request_snapshot.invoice_number, undefined);
  assert.equal(snap.request_snapshot.source_booking_id, undefined);
  assert.ok(!json.includes("limqs1.secret"));
  assert.ok(!json.includes("limacc1.secret"));
  assert.ok(!json.includes("ada@example.com"));
  assert.ok(!json.includes("INV-1"));
  assert.ok(!json.includes("bk_1"));
  assert.equal(snap.seller_snapshot.invoice_document_id, undefined);
  assert.equal(snap.seller_snapshot.contact_email, "billing@coachline.test");
  assert.deepEqual(quotationSnapshotContainsForbiddenKey(snap.request_snapshot), []);
});

test("derive totals match the manual-book VAT split", () => {
  const totals = deriveLimousineQuotationTotals({
    totalInclVatCents: 18500,
    vatRate: 0.06,
    vatTreatment: "incl",
    currency: "EUR",
  });
  const inclVat = 18500 / 100;
  const exVat = Math.round((inclVat / 1.06) * 100) / 100;
  assert.equal(totals.price_incl_vat, inclVat);
  assert.equal(totals.price_ex_vat, exVat);
  assert.equal(totals.price_vat, Math.round((inclVat - exVat) * 100) / 100);
});

test("exclusive 600 at 21% stores net 600 / VAT 126 / gross 726", () => {
  const totals = deriveLimousineQuotationTotals({
    enteredAmountCents: 60000,
    vatRate: 0.21,
    vatTreatment: "excl",
    currency: "EUR",
  });
  assert.equal(totals.entered_amount_cents, 60000);
  assert.equal(totals.total_ex_vat_cents, 60000);
  assert.equal(totals.vat_amount_cents, 12600);
  assert.equal(totals.total_incl_vat_cents, 72600);
  assert.equal(totals.price_ex_vat, 600);
  assert.equal(totals.price_vat, 126);
  assert.equal(totals.price_incl_vat, 726);
  assert.equal(totals.vat_treatment, "excl");
  assert.equal(totals.vat_rate, 0.21);
});

test("inclusive 600 at 21% keeps the historical reverse split", () => {
  const totals = deriveLimousineQuotationTotals({
    enteredAmountCents: 60000,
    vatRate: 0.21,
    vatTreatment: "incl",
    currency: "EUR",
  });
  assert.equal(totals.total_incl_vat_cents, 60000);
  assert.equal(totals.total_ex_vat_cents, 49587);
  assert.equal(totals.vat_amount_cents, 10413);
  assert.equal(totals.vat_treatment, "incl");
});

test("no VAT and zero rate keep net equal to gross", () => {
  const none = deriveLimousineQuotationTotals({
    enteredAmountCents: 60000,
    vatRate: 0.21,
    vatTreatment: "none",
    currency: "EUR",
  });
  assert.equal(none.total_ex_vat_cents, 60000);
  assert.equal(none.vat_amount_cents, 0);
  assert.equal(none.total_incl_vat_cents, 60000);
  assert.equal(none.vat_rate, 0);
  const zero = deriveLimousineQuotationTotals({
    enteredAmountCents: 60000,
    vatRate: 0,
    vatTreatment: "excl",
    currency: "EUR",
  });
  assert.equal(zero.total_ex_vat_cents, 60000);
  assert.equal(zero.vat_amount_cents, 0);
  assert.equal(zero.total_incl_vat_cents, 60000);
});

test("legacy records project quotation_available false", () => {
  const view = projectLimousineQuotationAvailability({ revision: 3, quote: {} });
  assert.deepEqual(view, { quotation_available: false });
  assert.equal(resolveLimousineQuotationSnapshot({ revision: 3 }), null);
  assert.equal(resolveLimousineQuotationCommercialSource({ revision: 3 }).mode, "legacy");
});

test("new snapshots project availability for the sent revision", async () => {
  const snap = await buildLimousineQuotationSnapshot(baseInput());
  const rec = attachLimousineQuotationSnapshot({ revision: 3 }, snap).record;
  const view = projectLimousineQuotationAvailability(rec);
  assert.equal(view.quotation_available, true);
  assert.equal(view.quotation_revision, 3);
  assert.equal(resolveLimousineQuotationCommercialSource(rec).mode, "snapshot");
});

test("allowlist freeze helpers drop unknown keys", () => {
  const request = freezeLimousineQuotationRequestSnapshot({
    from: "Gent",
    status_ref: "limqs1.x",
    extra: "nope",
  });
  assert.equal(request.from, "Gent");
  assert.equal(request.status_ref, undefined);
  assert.equal(request.extra, undefined);
  const vehicle = freezeLimousineQuotationVehicleSnapshot({
    public_name: "Car",
    catalog_cost: 9,
  });
  assert.equal(vehicle.public_name, "Car");
  assert.equal(vehicle.catalog_cost, undefined);
  const offer = freezeLimousineQuotationOfferSnapshot({
    total_incl_vat_cents: 100,
    currency: "EUR",
    invoice_number: "INV",
  });
  assert.equal(offer.invoice_number, undefined);
  const seller = freezeLimousineQuotationSellerSnapshot({
    legal_name: "A",
    raw_profile: { secret: true },
  });
  assert.equal(seller.raw_profile, undefined);
});

test("snapshot module does not import Document Core, Billit, Peppol or pdf credits", () => {
  const src = readFileSync(join(__dirname, "limousine_quotation_snapshot.mjs"), "utf8");
  assert.ok(!src.includes("document_core"));
  assert.ok(!src.includes("pdf_credits"));
  assert.ok(!src.includes("DOCUMENT_REFERENCE_SEQUENCE"));
  assert.ok(!/from ["'].*billit/i.test(src));
  assert.ok(!/from ["'].*peppol/i.test(src));
  assert.ok(!/import .*billit/i.test(src));
  assert.ok(!/import .*peppol/i.test(src));
  assert.ok(!/import .*document_core/i.test(src));
});

test("build from record uses the committed revision", async () => {
  const snap = await buildLimousineQuotationSnapshotFromRecord({
    record: {
      quote_request_id: "limq_snap_1",
      revision: 7,
      offer_source_revision: 2,
      request: baseInput().requestSnapshot,
      quote: baseInput().offerSnapshot,
    },
    sellerSnapshot: baseInput().sellerSnapshot,
    issuedAt: "2026-08-22T08:00:00Z",
  });
  assert.equal(snap.quote_revision, 7);
});

test("frozen logo present is bounded; later absence cannot rewrite an attached snapshot", async () => {
  const withLogo = await buildLimousineQuotationSnapshot(
    baseInput({
      sellerSnapshot: {
        ...baseInput().sellerSnapshot,
        logo: {
          present: true,
          mime: "image/png",
          sha256: "abc",
          data_uri: "data:image/png;base64,AAAA",
        },
      },
    }),
  );
  assert.equal(withLogo.seller_snapshot.logo.present, true);
  assert.ok(withLogo.seller_snapshot.logo.data_uri.startsWith("data:image/png"));
  const rec = attachLimousineQuotationSnapshot({ revision: 3 }, withLogo).record;
  rec.seller_snapshot = { logo: { present: false } };
  assert.equal(rec.quotation_snapshots["3"].seller_snapshot.logo.present, true);
});

test("sorted extra ids keep the hash stable", async () => {
  const a = await buildLimousineQuotationSnapshot(
    baseInput({
      requestSnapshot: {
        ...baseInput().requestSnapshot,
        selected_extra_ids: ["deco", "water"],
      },
    }),
  );
  const b = await buildLimousineQuotationSnapshot(
    baseInput({
      requestSnapshot: {
        ...baseInput().requestSnapshot,
        selected_extra_ids: ["water", "deco"],
      },
    }),
  );
  assert.equal(a.content_hash, b.content_hash);
});
