/* Run: node --test workers/booking/modules/invoice_service_line.test.mjs
 *
 * The invoice, PDF, Billit and Peppol pipelines are shared by every Fluxidi
 * product. Only the service word on the line differs. These tests pin that
 * seam: taxi and airport descriptions must stay byte-for-byte what they are
 * today, a limousine line must read like a human wrote it, and no internal
 * identifier may reach a customer document.
 */

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import {
  DEFAULT_INVOICE_SERVICE_LINE_LABEL,
  creditNoteServiceLineLabel,
  creditNoteLineDescription,
  formatBillitTaxiritLineDescription,
  enrichProviderNeutralLineItemsWithRoute,
} from "./invoice_route_address.js";
import {
  invoiceServiceLineLabel,
  invoiceServiceLineVehicleName,
} from "./invoice_service_line.mjs";
import { buildLimousineAcceptedSnapshot } from "./limousine_booking.mjs";
import { LIMOUSINE_SERVICE_TYPE } from "./limousine_unified_intent.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const worker = readFileSync(
  join(__dirname, "..", "fluxidi_booking_worker.js"),
  "utf8",
);

const PICKUP = "Grote Markt 1, 1000 Brussel";
const DROPOFF = "Luchthaven Brussel, 1930 Zaventem";

function limousineBooking(extra = {}) {
  return {
    limousine_accepted_price: {
      service_category: LIMOUSINE_SERVICE_TYPE,
      vehicle_id: "veh_hummer_01",
      ...extra,
    },
  };
}

// ---------------------------------------------------------------------------
// Label derivation
// ---------------------------------------------------------------------------

test("1) taxi and airport bookings keep the historical service word", () => {
  assert.equal(invoiceServiceLineLabel(null), "Taxirit");
  assert.equal(invoiceServiceLineLabel({}), "Taxirit");
  assert.equal(invoiceServiceLineLabel({ service: "taxi" }), "Taxirit");
  assert.equal(invoiceServiceLineLabel({ service: "airport" }), "Taxirit");
  assert.equal(DEFAULT_INVOICE_SERVICE_LINE_LABEL, "Taxirit");
});

test("2) a limousine booking names the accepted car", () => {
  assert.equal(
    invoiceServiceLineLabel(
      limousineBooking({ vehicle_public_name: "Hummer White" }),
    ),
    "Limousinevervoer \u2013 Hummer White",
  );
});

test("3) a limousine booking without a published name degrades, never to an id", () => {
  const label = invoiceServiceLineLabel(limousineBooking());
  assert.equal(label, "Limousinevervoer");
  assert.ok(!label.includes("veh_hummer_01"));
  assert.equal(invoiceServiceLineVehicleName(limousineBooking()), "");
});

test("4) the snapshot is read wherever the booking carries it", () => {
  const name = "Mercedes S-Klasse";
  const expected = `Limousinevervoer \u2013 ${name}`;
  const snapshot = {
    service_category: LIMOUSINE_SERVICE_TYPE,
    vehicle_public_name: name,
  };
  assert.equal(
    invoiceServiceLineLabel({ limousine_accepted_price: snapshot }),
    expected,
  );
  assert.equal(
    invoiceServiceLineLabel({ quote: { limousine_accepted_price: snapshot } }),
    expected,
  );
  assert.equal(
    invoiceServiceLineLabel({ booking: { limousine_accepted_price: snapshot } }),
    expected,
  );
});

test("5) a snapshot without the limousine marker cannot claim the label", () => {
  assert.equal(
    invoiceServiceLineLabel({
      limousine_accepted_price: { vehicle_public_name: "Hummer White" },
    }),
    "Taxirit",
  );
  assert.equal(
    invoiceServiceLineLabel({ limousine_accepted_price: { service_type: "taxi" } }),
    "Taxirit",
  );
});

// ---------------------------------------------------------------------------
// Description formatting — taxi/airport must not move
// ---------------------------------------------------------------------------

test("6) the default description is unchanged, legs included", () => {
  assert.equal(
    formatBillitTaxiritLineDescription({ pickup: PICKUP, dropoff: DROPOFF }),
    `Taxirit: ${PICKUP} \u2192 ${DROPOFF}`,
  );
  assert.equal(
    formatBillitTaxiritLineDescription({
      legSuffix: "return",
      pickup: PICKUP,
      dropoff: DROPOFF,
    }),
    `Taxirit - terugrit: ${PICKUP} \u2192 ${DROPOFF}`,
  );
  assert.equal(
    formatBillitTaxiritLineDescription({
      legSuffix: "outbound",
      pickup: PICKUP,
      dropoff: DROPOFF,
    }),
    `Taxirit - heenrit: ${PICKUP} \u2192 ${DROPOFF}`,
  );
  assert.equal(formatBillitTaxiritLineDescription({}), "Taxirit");
});

test("7) an explicit service label replaces only the service word", () => {
  const label = "Limousinevervoer \u2013 Hummer White";
  assert.equal(
    formatBillitTaxiritLineDescription({
      pickup: PICKUP,
      dropoff: DROPOFF,
      serviceLabel: label,
    }),
    `${label}: ${PICKUP} \u2192 ${DROPOFF}`,
  );
  assert.equal(
    formatBillitTaxiritLineDescription({
      legSuffix: "return",
      pickup: PICKUP,
      dropoff: DROPOFF,
      serviceLabel: label,
    }),
    `${label} - terugrit: ${PICKUP} \u2192 ${DROPOFF}`,
  );
});

test("8) an empty or blank label falls back to the default", () => {
  for (const serviceLabel of ["", "   ", null, undefined]) {
    assert.equal(
      formatBillitTaxiritLineDescription({
        pickup: PICKUP,
        dropoff: DROPOFF,
        serviceLabel,
      }),
      `Taxirit: ${PICKUP} \u2192 ${DROPOFF}`,
    );
  }
});

test("9) the 240-char Billit cap still holds for a long service label", () => {
  const desc = formatBillitTaxiritLineDescription({
    pickup: "A".repeat(200),
    dropoff: "B".repeat(200),
    serviceLabel: "Limousinevervoer \u2013 " + "C".repeat(100),
  });
  assert.ok(desc.length <= 240);
});

// ---------------------------------------------------------------------------
// Credit notes
// ---------------------------------------------------------------------------

test("10) the taxi credit-note wording is byte-for-byte unchanged", () => {
  assert.equal(creditNoteServiceLineLabel("Taxirit"), "Creditnota taxirit");
  const invoiceDesc = `Taxirit: ${PICKUP} \u2192 ${DROPOFF}`;
  assert.equal(
    creditNoteLineDescription(invoiceDesc, "Taxirit"),
    `Creditnota taxirit: ${PICKUP} \u2192 ${DROPOFF}`,
  );
});

test("11) a limousine credit note follows the same service-aware wording", () => {
  const label = "Limousinevervoer \u2013 Hummer White";
  assert.equal(
    creditNoteLineDescription(`${label}: ${PICKUP} \u2192 ${DROPOFF}`, label),
    `Creditnota limousinevervoer \u2013 Hummer White: ${PICKUP} \u2192 ${DROPOFF}`,
  );
  assert.equal(
    creditNoteLineDescription(`${label} - terugrit`, label),
    "Creditnota limousinevervoer \u2013 Hummer White - terugrit",
  );
});

// ---------------------------------------------------------------------------
// Stored line-item enrichment
// ---------------------------------------------------------------------------

test("12) stored taxi lines enrich exactly as before", () => {
  const doc = {
    route_address_snapshot: { from_address: PICKUP, to_address: DROPOFF },
  };
  const out = enrichProviderNeutralLineItemsWithRoute(
    [{ description: "Taxirit", line_total_incl_vat: 100 }],
    doc,
    null,
  );
  assert.equal(
    out.line_items[0].description,
    `Taxirit: ${PICKUP} \u2192 ${DROPOFF}`,
  );
  assert.equal(out.line_items[0].line_total_incl_vat, 100);
});

test("13) stored limousine lines enrich with the frozen service word", () => {
  const label = "Limousinevervoer \u2013 Hummer White";
  const doc = {
    route_address_snapshot: { from_address: PICKUP, to_address: DROPOFF },
  };
  const out = enrichProviderNeutralLineItemsWithRoute(
    [{ description: label }],
    doc,
    null,
    { serviceLabel: label },
  );
  assert.equal(out.line_items[0].description, `${label}: ${PICKUP} \u2192 ${DROPOFF}`);

  // A legacy row stored before the label existed still enriches, so historical
  // limousine documents are not stranded with a taxi word.
  const legacy = enrichProviderNeutralLineItemsWithRoute(
    [{ description: "Taxirit" }],
    doc,
    null,
    { serviceLabel: label },
  );
  assert.equal(
    legacy.line_items[0].description,
    `${label}: ${PICKUP} \u2192 ${DROPOFF}`,
  );
});

test("14) a genuinely custom description is still left alone", () => {
  const doc = {
    route_address_snapshot: { from_address: PICKUP, to_address: DROPOFF },
  };
  const custom = "Wachttijd 30 min";
  for (const serviceLabel of [undefined, "Limousinevervoer \u2013 Hummer White"]) {
    const out = enrichProviderNeutralLineItemsWithRoute(
      [{ description: custom }],
      doc,
      null,
      serviceLabel ? { serviceLabel } : {},
    );
    assert.equal(out.line_items[0].description, custom);
  }
});

test("15) stored credit-note lines keep their credit wording", () => {
  const doc = {
    route_address_snapshot: { from_address: PICKUP, to_address: DROPOFF },
  };
  const taxi = enrichProviderNeutralLineItemsWithRoute(
    [{ description: "Creditnota taxirit" }],
    doc,
    null,
  );
  assert.equal(
    taxi.line_items[0].description,
    `Creditnota taxirit: ${PICKUP} \u2192 ${DROPOFF}`,
  );

  const label = "Limousinevervoer \u2013 Hummer White";
  const limo = enrichProviderNeutralLineItemsWithRoute(
    [{ description: `Creditnota limousinevervoer \u2013 Hummer White` }],
    doc,
    null,
    { serviceLabel: label },
  );
  assert.equal(
    limo.line_items[0].description,
    `Creditnota limousinevervoer \u2013 Hummer White: ${PICKUP} \u2192 ${DROPOFF}`,
  );
});

// ---------------------------------------------------------------------------
// The accepted snapshot carries the display name
// ---------------------------------------------------------------------------

test("16) the accepted snapshot carries the published vehicle name", () => {
  const total = {
    ok: true,
    offer_id: "off_1",
    service_class_id: "cls_1",
    vehicle_id: "veh_hummer_01",
    vehicle_public_name: "Hummer White",
    journey_type: "point_to_point",
    currency: "EUR",
    total_incl_vat_cents: 45000,
  };
  const snapshot = buildLimousineAcceptedSnapshot({
    total,
    quoteReference: "qr_1",
    acceptedAtIso: "2026-08-21T10:00:00.000Z",
    companyId: "cmp_1",
  });
  assert.equal(snapshot.vehicle_public_name, "Hummer White");
  assert.equal(
    invoiceServiceLineLabel({ limousine_accepted_price: snapshot }),
    "Limousinevervoer \u2013 Hummer White",
  );
});

test("17) a snapshot without a name omits the field entirely", () => {
  const snapshot = buildLimousineAcceptedSnapshot({
    total: {
      ok: true,
      offer_id: "off_1",
      service_class_id: "cls_1",
      vehicle_id: "veh_hummer_01",
      journey_type: "point_to_point",
      currency: "EUR",
      total_incl_vat_cents: 45000,
    },
    quoteReference: "qr_1",
    acceptedAtIso: "2026-08-21T10:00:00.000Z",
    companyId: "cmp_1",
  });
  assert.ok(!("vehicle_public_name" in snapshot));
});

// ---------------------------------------------------------------------------
// Worker wiring
// ---------------------------------------------------------------------------

test("18) the name is taken from the authoritative quote record, not the client", () => {
  assert.ok(
    worker.includes(
      "vehicle_public_name: sanitizeTenantString(\n      record?.request?.vehicle_snapshot?.public_name,",
    ),
  );
  // No client-supplied vehicle name is ever read into the snapshot.
  assert.ok(!/vehicle_public_name:\s*(body|payload|req)\./.test(worker));
});

test("19) the label is frozen onto the issued document, non-default only", () => {
  assert.ok(worker.includes("const serviceLineLabel = invoiceServiceLineLabel(bookingRecord);"));
  assert.ok(
    worker.includes(
      "serviceLineLabel !== DEFAULT_INVOICE_SERVICE_LINE_LABEL &&\n    !safeStr(doc.service_line_label)",
    ),
  );
  assert.ok(
    worker.includes(
      "...(shouldFreezeServiceLineLabel\n      ? { service_line_label: serviceLineLabel }\n      : {}),",
    ),
  );
});

test("20) the export preview reads the frozen label and defaults to taxi", () => {
  assert.ok(
    worker.includes(
      "safeStr(rec.service_line_label) || DEFAULT_INVOICE_SERVICE_LINE_LABEL",
    ),
  );
  assert.ok(
    worker.includes("{ legType: sourceLegType, serviceLabel: serviceLineLabel }"),
  );
  assert.ok(worker.includes("creditNoteLineDescription(\n        serviceDescription,"));
});

test("21) the invoice PDF heading uses the same service word", () => {
  assert.ok(
    worker.includes(
      "const serviceLineLabel = invoiceServiceLineLabel({\n    limousine_accepted_price: limousineSnapshot,\n  });",
    ),
  );
  // Taxi/airport keep the historical heading including the ride-tier suffix.
  assert.ok(worker.includes("`<strong>Taxidienst</strong> <span class=\"muted\">"));
});

test("22) no parallel limousine invoice, Billit or Peppol pipeline appears", () => {
  // The seam only decides a word. It must not talk to a provider, the network
  // or storage, which is what would make it a second pipeline.
  const module = readFileSync(join(__dirname, "invoice_service_line.mjs"), "utf8");
  const code = module
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/^\s*\/\/.*$/gm, "")
    .replace(/^\s*\/\/\/.*$/gm, "");
  for (const forbidden of ["billit", "peppol", "fetch(", "BOOKING_KV", "await "]) {
    assert.ok(
      !code.toLowerCase().includes(forbidden.toLowerCase()),
      `service-line module must not reach for ${forbidden}`,
    );
  }
  assert.ok(!worker.includes("formatLimousineLineDescription"));
  assert.ok(!worker.includes("ensureLimousineInvoice"));
  assert.ok(!worker.includes("performLimousinePeppolSend"));
});
