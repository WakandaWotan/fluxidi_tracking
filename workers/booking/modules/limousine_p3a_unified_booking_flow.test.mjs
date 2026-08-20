// LIMOUSINE-UNIFIED-BOOKING-P3A — worker wiring onto existing Fluxidi chains.
// Run: node --test workers/booking/modules/limousine_p3a_unified_booking_flow.test.mjs

import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const worker = readFileSync(join(__dirname, "..", "fluxidi_booking_worker.js"), "utf8");
const quote = readFileSync(join(__dirname, "limousine_manual_quote.mjs"), "utf8");
const booking = readFileSync(join(__dirname, "limousine_booking.mjs"), "utf8");
const intent = readFileSync(join(__dirname, "limousine_unified_intent.mjs"), "utf8");

test("1) existing quote and /book seams are reused", () => {
  assert.ok(worker.includes('"/limousine/quote-requests" && request.method === "POST"'));
  assert.ok(worker.includes('url.pathname === "/book" && request.method === "POST"'));
  assert.ok(worker.includes("async function handleBooking"));
  assert.ok(worker.includes("async function _prepareLimousineBooking"));
  assert.ok(worker.includes("async function _prepareLimousineManualBooking"));
  assert.ok(!intent.includes("app.post(\"/limousine/book\""));
  assert.ok(!intent.includes("new BookingAggregate"));
});

test("2) limousine booking requests wait for company confirmation", () => {
  assert.ok(worker.includes("limousinePendingCompanyConfirm"));
  assert.ok(worker.includes("if (!requiresPayment && !limousinePendingCompanyConfirm)"));
  assert.ok(worker.includes("company_confirmation_required:"));
  assert.ok(worker.includes("requireQuoteReference: Boolean(clientQuoteReference)"));
});

test("3) quote create stores an immutable pricing snapshot and no payment hooks", () => {
  assert.ok(worker.includes("pricing_snapshot: validated.snapshot || null"));
  assert.ok(!quote.toLowerCase().includes("mollie"));
  assert.ok(!quote.toLowerCase().includes("billit"));
  assert.ok(!quote.toLowerCase().includes("chiron"));
});

test("4) accepted snapshot and service_type stay on the existing booking record", () => {
  assert.ok(worker.includes("limousine_accepted_price: _limousineAccepted.snapshot"));
  assert.ok(worker.includes("service_type: _LIMOUSINE_SERVICE_TYPE"));
  assert.ok(booking.includes("buildLimousineAcceptedSnapshot"));
  assert.ok(worker.includes("_limousineDocumentLinesFromSnapshot"));
});

test("5) taxi/airport normalizeService is unchanged and gates stay fail-closed", () => {
  assert.match(worker, /if \(s === "airport"\) return "airport";/);
  assert.ok(worker.includes('env?.LIMOUSINE_BOOK_ENABLED ?? "0"'));
  assert.ok(worker.includes('env?.LIMOUSINE_MANUAL_QUOTE_ENABLED ?? "0"'));
  assert.ok(worker.includes('env?.LIMOUSINE_QUOTE_ENABLED ?? "0"'));
});

test("6) no second inbox, driver list or status machine", () => {
  assert.ok(!worker.includes("/limousine/driver-inbox"));
  assert.ok(!worker.includes("limousine_bookings:"));
  assert.ok(!worker.includes("createLimousineStatusMachine"));
  assert.ok((worker.match(/async function handleBooking\(/g) || []).length >= 1);
  assert.ok(!worker.includes("async function handleLimousineBooking"));
});

test("7) confirmed bookings stay on existing planning/driver/history/read-model seams", () => {
  const readModel = readFileSync(join(__dirname, "booking_read_model.js"), "utf8");
  assert.ok(readModel.includes("service_type: normalizedServiceType"));
  assert.ok(worker.includes("serviceType: _limousineAccepted"));
  assert.ok(worker.includes('url.pathname === "/bookings" && request.method === "GET"'));
  assert.ok(worker.includes('url.pathname === "/driver/bookings"'));
  assert.ok(!worker.includes("/limousine/planning"));
  assert.ok(!worker.includes("/limousine/history"));
  assert.ok(!worker.includes("limousine_command_center"));
  assert.ok(worker.includes("upsertDashboardBookingsKpiProjectionBestEffort"));
});

test("8) quote requests stay off Mollie/Billit/Chiron; /book keeps existing side-effect names", () => {
  assert.ok(!quote.toLowerCase().includes("createMollie"));
  assert.ok(!quote.toLowerCase().includes("enqueueBillit"));
  assert.ok(!quote.toLowerCase().includes("enqueueChiron"));
  assert.ok(worker.includes("createMolliePayment") || worker.includes("mollie"));
  assert.ok(worker.includes("chiron"));
  assert.ok(worker.includes("billit"));
});

test("9) Billit OAuth reconnect-preservation is not rewritten", () => {
  const reconnect = readFileSync(
    join(__dirname, "..", "billit_oauth_reconnect_preserve_p0.test.mjs"),
    "utf8",
  );
  assert.ok(reconnect.includes("reconnect"));
  assert.ok(!intent.includes("billit_oauth"));
  assert.ok(!quote.includes("billit_oauth"));
});
