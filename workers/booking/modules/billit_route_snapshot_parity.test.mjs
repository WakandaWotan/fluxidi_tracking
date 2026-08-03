// FLUXIDI-BILLIT-ROUTE-SNAPSHOT-PARITY-P0-1
// Prove Billit provider-neutral payload uses the same frozen Document Core
// route_address_snapshot as the Fluxidi business-invoice PDF.

import { test } from "node:test";
import assert from "node:assert/strict";

import {
  buildRouteAddressSnapshot,
  resolveIssuedRouteAddressSnapshot,
  projectInvoiceRouteAddressesForExport,
  formatBillitTaxiritLineDescription,
  enrichProviderNeutralLineItemsWithRoute,
} from "./invoice_route_address.js";
import { resolveInvoiceRideProjection } from "./street_invoice_pdf_projection.js";
import {
  buildDocumentExportPreview,
  buildBillitPayloadPreviewFromProviderNeutralDocument,
  buildBillitOfficialOrderRequestPreview,
} from "../fluxidi_booking_worker.js";

function issuedDoc(from, to, extras = {}) {
  return {
    document_id: "doc_parity_1",
    document_type: "invoice",
    document_number: "INV-2026-000099",
    lifecycle_state: "issued",
    document_status: "issued",
    issue_timestamp: "2026-08-02T17:00:00.000Z",
    currency: "EUR",
    source_booking_id: "street_parity_1",
    source_leg_type: "outbound",
    totals: {
      subtotal_ex_vat: 5.19,
      vat_amount: 0.31,
      vat_rate_percent: 6,
      total_incl_vat: 5.5,
      currency: "EUR",
    },
    buyer_snapshot: {
      name: "ACME BV",
      vat_number: "BE0123456789",
      country_code: "BE",
    },
    seller_snapshot: {
      name: "Fluxidi",
      vat_number: "BE0700123456",
      country_code: "BE",
    },
    route_address_snapshot: buildRouteAddressSnapshot({
      fromAddress: from,
      toAddress: to,
      fromSource: "mapbox_reverse_geocode",
      toSource: "booking_label",
      resolvedAt: "2026-08-02T17:00:00.000Z",
    }),
    ...extras,
  };
}

function classificationFor(doc) {
  return {
    document_id: doc.document_id,
    document_type: doc.document_type,
    document_number: doc.document_number,
    proof_reference: null,
    lifecycle_state: doc.lifecycle_state,
    document_status: doc.document_status,
    issue_timestamp: doc.issue_timestamp,
    currency: doc.currency,
    source_booking_id: doc.source_booking_id,
    source_leg_id: null,
    source_leg_type: doc.source_leg_type || null,
    export_role: "invoice",
    export_target_suggestion: "einvoice",
    exportable_to_accounting: true,
    exportable_to_peppol: false,
    blocking_reasons: ["fields_incomplete_for_peppol"],
    warnings: [],
  };
}

test("issued route snapshot wins over mutable booking values", () => {
  const issued = issuedDoc("Frozen Pickup St", "Frozen Dropoff St");
  const booking = {
    booking: {
      from: "50.1, 3.2",
      to: "Mutated Dest",
      invoice_from_address: "Mutated After Issue",
    },
  };
  const resolved = resolveIssuedRouteAddressSnapshot(issued, booking);
  assert.equal(resolved.from, "Frozen Pickup St");
  assert.equal(resolved.to, "Frozen Dropoff St");
  assert.equal(resolved.source, "document_core_route_address_snapshot");

  const route = projectInvoiceRouteAddressesForExport(issued, booking);
  assert.equal(route.pickup, "Frozen Pickup St");
  assert.equal(route.dropoff, "Frozen Dropoff St");

  const enriched = enrichProviderNeutralLineItemsWithRoute(
    [{ description: "Taxirit", quantity: 1 }],
    issued,
    booking,
  );
  assert.match(enriched.line_items[0].description, /Frozen Pickup St/);
  assert.match(enriched.line_items[0].description, /Frozen Dropoff St/);
  assert.doesNotMatch(enriched.line_items[0].description, /Mutated/);
});

test("coordinate-only booking never leaks coordinates to Billit", () => {
  const issued = {
    document_id: "doc_coords",
    document_type: "invoice",
    // Snapshot deliberately stores only coords (bad historical) — must not leak.
    route_address_snapshot: buildRouteAddressSnapshot({
      fromAddress: "50.772006, 3.669447",
      toAddress: "3.669447,50.772006",
      resolvedAt: "2026-08-02T17:00:00.000Z",
    }),
    totals: {
      subtotal_ex_vat: 5.19,
      vat_amount: 0.31,
      vat_rate_percent: 6,
      total_incl_vat: 5.5,
    },
  };
  const booking = {
    booking: { from: "50.772006, 3.669447", to: "3.2, 50.1" },
  };
  const desc = formatBillitTaxiritLineDescription({
    pickup: resolveIssuedRouteAddressSnapshot(issued, booking).from,
    dropoff: resolveIssuedRouteAddressSnapshot(issued, booking).to,
  });
  assert.equal(desc, "Taxirit");
  assert.doesNotMatch(desc, /\d+\.\d+\s*,\s*\d+\.\d+/);

  const preview = buildDocumentExportPreview(
    issued,
    classificationFor(issued),
  );
  const billit = buildBillitPayloadPreviewFromProviderNeutralDocument(preview, {
    billit_environment: "sandbox",
  });
  const official = buildBillitOfficialOrderRequestPreview(billit, {
    party_id: "party-1",
    payment_terms_days: 0,
  });
  const lineDesc = official.body?.OrderLines?.[0]?.Description || "";
  assert.doesNotMatch(lineDesc, /\d+\.\d+\s*,\s*\d+\.\d+/);
  assert.doesNotMatch(
    JSON.stringify(billit.route_addresses || {}),
    /\d+\.\d+\s*,\s*\d+\.\d+/,
  );
});

test("historical issued snapshot remains stable after booking mutation", () => {
  const issued = issuedDoc("Hist From", "Hist To");
  const bookingBefore = {
    booking: { from: "Hist From", to: "Hist To" },
  };
  const bookingAfter = {
    booking: {
      from: "99.9, 1.1",
      to: "Completely Different Street 9",
      invoice_from_address: "Post-issue edit",
    },
  };
  const a = projectInvoiceRouteAddressesForExport(issued, bookingBefore);
  const b = projectInvoiceRouteAddressesForExport(issued, bookingAfter);
  assert.deepEqual(
    { pickup: a.pickup, dropoff: a.dropoff, source: a.source },
    { pickup: b.pickup, dropoff: b.dropoff, source: b.source },
  );
  assert.equal(b.pickup, "Hist From");
  assert.equal(b.dropoff, "Hist To");
});

test("Fluxidi PDF projection and Billit payload use identical pickup/drop-off source values", () => {
  const from = "Koekamerstraat 48A, 9688 Schorisse";
  const to = "Scheldestraat 5, 9690 Kluisbergen";
  const issued = issuedDoc(from, to);
  const booking = {
    booking: {
      from: "50.772006, 3.669447",
      to: "Edited Destination",
      invoice_from_address: "Should Not Win",
      pickup_iso: "2026-08-02T16:30:00.000Z",
    },
    status: "completed",
  };

  const ride = resolveInvoiceRideProjection(booking, {
    issuedDocument: issued,
  });
  assert.equal(ride.from, from);
  assert.equal(ride.to, to);
  assert.equal(ride.routeAddressSource, "document_core_route_address_snapshot");

  const route = projectInvoiceRouteAddressesForExport(issued, booking);
  assert.equal(route.pickup, ride.from);
  assert.equal(route.dropoff, ride.to);
  assert.equal(route.source, ride.routeAddressSource);

  const docPreview = buildDocumentExportPreview(
    issued,
    classificationFor(issued),
  );
  const pnp = docPreview.provider_neutral_preview;
  assert.equal(pnp.route_addresses.pickup, from);
  assert.equal(pnp.route_addresses.dropoff, to);
  assert.equal(pnp.route_addresses.source, "document_core_route_address_snapshot");

  const billit = buildBillitPayloadPreviewFromProviderNeutralDocument(
    docPreview,
    { billit_environment: "sandbox" },
  );
  assert.equal(billit.route_addresses.pickup, from);
  assert.equal(billit.route_addresses.dropoff, to);
  assert.match(billit.lines[0].description, new RegExp(from.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
  assert.match(billit.lines[0].description, new RegExp(to.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));

  const official = buildBillitOfficialOrderRequestPreview(billit, {
    party_id: "party-1",
    payment_terms_days: 0,
  });
  assert.match(official.body.OrderLines[0].Description, /Koekamerstraat/);
  assert.match(official.body.OrderLines[0].Description, /Scheldestraat/);
});

test("amounts, VAT, invoice number and payment truth unchanged by route enrichment", () => {
  const issued = issuedDoc("A Street 1", "B Street 2", {
    payment_method_truth: {
      method_id: "paypal",
      provider: "paypal",
      status: "paid",
      category: "online",
    },
  });
  const cls = classificationFor(issued);
  const preview = buildDocumentExportPreview(issued, cls);
  const totals = preview.provider_neutral_preview.totals;
  assert.equal(totals.subtotal_ex_vat, 5.19);
  assert.equal(totals.vat_amount, 0.31);
  assert.equal(totals.vat_rate_percent, 6);
  assert.equal(totals.total_incl_vat, 5.5);
  assert.equal(preview.document_number, "INV-2026-000099");

  const billit = buildBillitPayloadPreviewFromProviderNeutralDocument(preview, {
    billit_environment: "sandbox",
  });
  assert.equal(billit.document_number, "INV-2026-000099");
  assert.equal(billit.totals.subtotal_ex_vat, 5.19);
  assert.equal(billit.totals.vat_amount, 0.31);
  assert.equal(billit.totals.vat_rate_percent, 6);
  assert.equal(billit.totals.total_incl_vat, 5.5);
  assert.equal(billit.lines[0].unit_price_ex_vat, 5.19);
  assert.equal(billit.lines[0].vat_rate_percent, 6);
  assert.equal(billit.lines[0].line_total_incl_vat, 5.5);

  const official = buildBillitOfficialOrderRequestPreview(billit, {
    party_id: "party-1",
    payment_terms_days: 0,
  });
  assert.equal(official.body.OrderNumber, "INV-2026-000099");
  assert.equal(official.body.OrderLines[0].UnitPriceExcl, 5.19);
  assert.equal(official.body.OrderLines[0].VATPercentage, 6);
  assert.equal(official.body.Currency, "EUR");
  // No Peppol auto-send flags.
  assert.equal(official.send_enabled, false);
  assert.equal(official.create_enabled, false);
  assert.equal(official.post_enabled, false);
});

test("missing addresses omit or use Niet opgegeven; never invent coords", () => {
  const issued = issuedDoc("", "");
  // Clear snapshot addresses explicitly.
  issued.route_address_snapshot.from_address = null;
  issued.route_address_snapshot.to_address = null;
  issued.route_address_snapshot.invoice_from_address = null;
  issued.route_address_snapshot.invoice_to_address = null;

  const withLabel = projectInvoiceRouteAddressesForExport(issued, null, {
    missingLabel: "Niet opgegeven",
  });
  assert.equal(withLabel.pickup_display, "Niet opgegeven");
  assert.equal(withLabel.dropoff_display, "Niet opgegeven");

  const descOneSide = formatBillitTaxiritLineDescription({
    pickup: "Only Pickup 1",
    dropoff: "",
  });
  assert.match(descOneSide, /Only Pickup 1 → Niet opgegeven/);

  const descNone = formatBillitTaxiritLineDescription({
    pickup: "",
    dropoff: "",
  });
  assert.equal(descNone, "Taxirit");
});
