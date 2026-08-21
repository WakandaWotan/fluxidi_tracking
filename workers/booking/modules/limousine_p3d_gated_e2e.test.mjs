// P3D — worker wiring for allowlist-scoped limousine transaction gates.
// Run: node --test workers/booking/modules/limousine_p3d_gated_e2e.test.mjs

import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const worker = readFileSync(join(__dirname, "..", "fluxidi_booking_worker.js"), "utf8");
const wrangler = readFileSync(join(__dirname, "..", "wrangler.toml"), "utf8");
const quote = readFileSync(join(__dirname, "limousine_manual_quote.mjs"), "utf8");
const booking = readFileSync(join(__dirname, "limousine_booking.mjs"), "utf8");
const intent = readFileSync(join(__dirname, "limousine_unified_intent.mjs"), "utf8");
const gate = readFileSync(join(__dirname, "limousine_transaction_gate.mjs"), "utf8");

test("1) resolver is imported and used on quote, book and quote-request create", () => {
  assert.ok(worker.includes("resolveLimousineTransactionGate as _resolveLimousineTransactionGateRaw"));
  assert.ok(worker.includes("function _resolveLimousineTransactionGate(env"));
  assert.ok(worker.includes("_limousineTestCompanyAllowlisted(env, companyId)"));
  const quoteEarly = worker.slice(
    worker.indexOf("const _isLimousineQuoteRequestEarly"),
    worker.indexOf("const pricingProfile = await _loadTenantPricingProfile"),
  );
  assert.ok(quoteEarly.includes('_resolveLimousineTransactionGate(env, {\n      kind: "quote"'));
  assert.ok(!quoteEarly.includes("body.company_id"));
  assert.ok(!quoteEarly.includes("body.tenant_id"));
  const book = worker.slice(
    worker.indexOf("if (_isLimousineServiceRequest(payload) || _limousineAcceptanceReference)"),
    worker.indexOf("const _limousineLegAllocation"),
  );
  assert.ok(book.includes('_resolveLimousineTransactionGate(env, {\n        kind: "book"'));
  assert.ok(!book.includes("payload.company_id"));
  const create = worker.slice(
    worker.indexOf('"/limousine/quote-requests" && request.method === "POST"'),
    worker.indexOf('"/admin/limousine/quote-requests/respond"'),
  );
  assert.ok(create.includes('_resolveLimousineTransactionGate(env, {\n          kind: "manual_quote"'));
  assert.ok(!create.includes("body.company_id"));
});

test("2) global gate-off still wins before allowlist work", () => {
  const quoteGate = worker.slice(
    worker.indexOf("if (_isLimousineQuoteRequest) {"),
    worker.indexOf('reason: "gate_off"'),
  );
  assert.ok(quoteGate.includes("const gateEnabled = _limousineQuoteGateEnabled(env)"));
  assert.ok(!quoteGate.includes("_resolveLimousineTransactionGate"));
  assert.ok(worker.includes("if (!_limousineBookGateEnabled(env)) {\n        return { ok: false, error: \"limousine_book_disabled\" };"));
  assert.ok(worker.includes("if (!_limousineManualQuoteGateEnabled(env)) {\n          return json({ ok: false, error: \"manual_quote_gate_off\" }, 404);"));
});

test("3) client cannot self-authorize tenant/company/partner", () => {
  assert.ok(!worker.includes("_limousineTestCompanyAllowlisted(env, body.company_id)"));
  assert.ok(!worker.includes("_limousineTestCompanyAllowlisted(env, payload.company_id)"));
  assert.ok(worker.includes("routedPublicPartner?.ok"));
  assert.ok(worker.includes("tenant_resolution_mode === \"trusted_route\""));
  assert.ok(gate.includes("never from a client tenant/company/partner claim"));
});

test("4) no second booking flow or datastore", () => {
  assert.ok(!intent.includes("app.post(\"/limousine/book\""));
  assert.ok(!intent.includes("new BookingAggregate"));
  assert.ok(!worker.includes("/limousine/driver-inbox"));
  assert.ok(!worker.includes("createLimousineStatusMachine"));
  assert.ok(!gate.includes("BOOKING_KV"));
  assert.ok(!gate.includes("fetch("));
});

test("5) taxi, airport, street, Mollie, Billit and Chiron stay on existing seams", () => {
  assert.match(worker, /if \(s === "airport"\) return "airport";/);
  assert.ok(worker.includes("normalizeService"));
  assert.ok(!quote.toLowerCase().includes("mollie"));
  assert.ok(!quote.toLowerCase().includes("billit"));
  assert.ok(!quote.toLowerCase().includes("chiron"));
  assert.ok(booking.includes("buildLimousineAcceptedSnapshot"));
  assert.ok(worker.includes("limousinePendingCompanyConfirm"));
  assert.ok(!wrangler.includes("LIMOUSINE_QUOTE_ENABLED"));
  assert.ok(!wrangler.includes("LIMOUSINE_BOOK_ENABLED"));
  assert.ok(!wrangler.includes("LIMOUSINE_MANUAL_QUOTE_ENABLED"));
  assert.ok(!wrangler.includes("LIMOUSINE_TEST_COMPANY_ALLOWLIST"));
});

test("6) default env reads stay fail-closed", () => {
  assert.ok(worker.includes('env?.LIMOUSINE_QUOTE_ENABLED ?? "0"'));
  assert.ok(worker.includes('env?.LIMOUSINE_BOOK_ENABLED ?? "0"'));
  assert.ok(worker.includes('env?.LIMOUSINE_MANUAL_QUOTE_ENABLED ?? "0"'));
});

test("7) from-price is not guaranteed; hourly and package keep published scope", () => {
  assert.ok(intent.includes("shown_from_price_guaranteed: false"));
  assert.ok(intent.includes("billable = Math.max(requested, minimum)"));
  assert.ok(intent.includes("minimum_duration_minutes: minimum"));
  assert.ok(intent.includes("computeLimousinePackageSnapshot"));
  assert.ok(intent.includes("package_duration_minutes"));
  assert.ok(intent.includes("assertLimousineOfferStillPublished"));
});

test("8) company confirm and chauffeur stay on existing planned routes", () => {
  assert.ok(worker.includes("limousinePendingCompanyConfirm"));
  assert.ok(worker.includes('url.pathname === "/driver/bookings"'));
  assert.ok(worker.includes("company_confirmation_required:"));
  assert.ok(!worker.includes("source: \"street_ride\"") || booking.includes("never uses the street meter"));
  assert.ok(booking.includes("never uses the street meter"));
  assert.ok(worker.includes("service_type: _LIMOUSINE_SERVICE_TYPE"));
});
