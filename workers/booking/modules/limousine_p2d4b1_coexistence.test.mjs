// P2D4B1 — limousine seams on the live Billit-safe Booking Worker.
// Run: node --test workers/booking/modules/limousine_p2d4b1_coexistence.test.mjs
//
// Source + module proofs only. No deploy, no production KV, no provider call.

import test from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import {
  limousineBookGateEnabled,
} from "./limousine_booking.mjs";
import {
  limousineManualQuoteGateEnabled,
} from "./limousine_manual_quote.mjs";
import {
  limousineQuoteGateEnabled,
} from "./limousine_pricing_resolver.mjs";
import {
  LIMOUSINE_ACCEPTANCE_ERRORS,
  unsealLimousineAcceptance,
} from "./limousine_acceptance_token.mjs";
import { BILLIT_OUTBOX_DUE_PREFIX } from "./billit_outbox_due_index.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const worker = readFileSync(join(__dirname, "..", "fluxidi_booking_worker.js"), "utf8");
const wrangler = readFileSync(join(__dirname, "..", "wrangler.toml"), "utf8");
const dueIndex = readFileSync(join(__dirname, "billit_outbox_due_index.js"), "utf8");

const ROUTES = [
  '"/limousine/quote-requests" && request.method === "POST"',
  '"/admin/limousine/quote-requests/respond" && request.method === "POST"',
  '"/limousine/quote-requests/accept" && request.method === "POST"',
  '"/admin/limousine/quote-requests" && request.method === "GET"',
  '"/limousine/quote-requests/status" && request.method === "POST"',
  '"/admin/pricing/limousine" && request.method === "GET"',
  '"/admin/pricing/limousine" && request.method === "POST"',
];

test("1) required limousine routes and seams exist on the Billit-safe Worker", () => {
  for (const route of ROUTES) {
    assert.ok(worker.includes(route), route);
  }
  assert.ok(worker.includes("async function _prepareLimousineBooking"));
  assert.ok(worker.includes("async function _prepareLimousineManualBooking"));
  assert.ok(worker.includes("function _publicLimousineShowroomFieldsFromStoredProfile"));
  assert.ok(worker.includes("limousine_acceptance_reference"));
});

test("2) undefined limousine gates fail closed independently", () => {
  assert.equal(limousineQuoteGateEnabled(undefined), false);
  assert.equal(limousineQuoteGateEnabled("0"), false);
  assert.equal(limousineBookGateEnabled(undefined), false);
  assert.equal(limousineManualQuoteGateEnabled(undefined), false);
  assert.ok(worker.includes('env?.LIMOUSINE_QUOTE_ENABLED ?? "0"'));
  assert.ok(worker.includes('env?.LIMOUSINE_BOOK_ENABLED ?? "0"'));
  assert.ok(worker.includes('env?.LIMOUSINE_MANUAL_QUOTE_ENABLED ?? "0"'));
  assert.ok(!wrangler.includes("LIMOUSINE_QUOTE_ENABLED"));
  assert.ok(!wrangler.includes("LIMOUSINE_BOOK_ENABLED"));
  assert.ok(!wrangler.includes("LIMOUSINE_MANUAL_QUOTE_ENABLED"));
});

test("3) missing LIMOUSINE_ACCEPTANCE_SECRET fails closed", async () => {
  const missing = await unsealLimousineAcceptance({
    secret: undefined,
    reference: "limacc1.abcdefghijklmnop.klmnopqrstuvwxyzabcdef",
  });
  assert.equal(missing.ok, false);
  assert.equal(missing.error, LIMOUSINE_ACCEPTANCE_ERRORS.MISSING_SECRET);
  assert.ok(worker.includes("env.LIMOUSINE_ACCEPTANCE_SECRET"));
  assert.ok(!worker.includes("LIMOUSINE_ACCEPTANCE_SECRET ="));
});

test("4) direct-price booking uses server authority", () => {
  const start = worker.indexOf("async function _prepareLimousineBooking");
  const end = worker.indexOf("/// Shared authoritative Limousine resolution");
  assert.ok(start > 0 && end > start);
  const body = worker.slice(start, end);
  assert.ok(body.includes("_composeLimousineTotal") || worker.includes("await _resolveAuthoritativeLimousineTotal"));
  assert.ok(body.includes("_compareLimousineQuoteForBook"));
  assert.ok(!body.includes("calcPrice("));
  assert.ok(!body.includes("payload.total"));
  assert.ok(!body.includes("payload.price_incl_vat"));
});

test("5) manual acceptance booking uses limousine_acceptance_reference", () => {
  assert.ok(worker.includes("payload?.limousine_acceptance_reference ?? payload?.limousineAcceptanceReference"));
  assert.ok(worker.includes("acceptanceReference: _limousineAcceptanceReference"));
  assert.ok(worker.includes("_unsealLimousineAcceptance({"));
});

test("6) client total is ignored", () => {
  const manual = worker.slice(
    worker.indexOf("async function _prepareLimousineManualBooking"),
    worker.indexOf("/// LIMOUSINE-MARKETPLACE-P2C1: /book pre-flight"),
  );
  assert.ok(manual.includes("quote.total_incl_vat_cents"));
  assert.ok(!manual.includes("payload.total"));
  assert.ok(!manual.includes("payload.price_incl_vat"));
  assert.ok(worker.includes("Client totals are ignored entirely.") || worker.includes("A client total is never read"));
});

test("7) no taxi fallback on limousine book/quote", () => {
  assert.ok(worker.includes("const mainPricing = _limousineAccepted"));
  assert.ok(worker.includes("!_limousineAccepted &&"));
  assert.ok(worker.includes("if (_limousineAccepted) {\n      ret.enabled = false;\n    }"));
  const quoteBranch = worker.slice(
    worker.indexOf("if (_isLimousineQuoteRequest) {"),
    worker.indexOf("return { status: 200, out: limoOut };"),
  );
  assert.ok(!quoteBranch.includes("calcPrice("));
  assert.ok(!quoteBranch.includes("resolveAirportFixedFare("));
});

test("8) create path does not mark a new paid collection", () => {
  const preflight = worker.slice(
    worker.indexOf("if (_isLimousineServiceRequest(payload) || _limousineAcceptanceReference)"),
    worker.indexOf("const bookingIntent = buildBookingIntentDescriptor({"),
  );
  assert.ok(!preflight.includes('payment_status: "paid"'));
  assert.ok(!preflight.includes("__mollie_paid = true"));
  assert.ok(!worker.includes("LIMOUSINE_ACCEPTANCE_SECRET ="));
});

test("9) quote / book / manual-quote gates remain independent", () => {
  assert.ok(worker.includes("function _limousineQuoteGateEnabled(env)"));
  assert.ok(worker.includes("function _limousineBookGateEnabled(env)"));
  assert.ok(worker.includes("function _limousineManualQuoteGateEnabled(env)"));
  assert.equal(limousineQuoteGateEnabled("1"), true);
  assert.equal(limousineBookGateEnabled("0"), false);
  assert.equal(limousineManualQuoteGateEnabled("1"), true);
  assert.ok(worker.includes('return { ok: false, error: "limousine_book_disabled" };'));
  assert.ok(worker.includes('return json({ ok: false, error: "manual_quote_gate_off" }, 404);'));
});

test("10) showroom GET exposes only committed public fields", () => {
  const start = worker.indexOf("function _publicLimousineShowroomFieldsFromStoredProfile");
  const end = worker.indexOf("async function getPublicPartnerProfileById");
  const fn = worker.slice(start, end);
  assert.ok(fn.includes("limousine_projection"));
  assert.ok(fn.includes("limousine_offers"));
  assert.ok(!fn.includes("limousine_entitled"));
  assert.ok(!fn.includes("LIMOUSINE_ACCEPTANCE_SECRET"));
  assert.ok(!fn.includes("operating_base_address"));
  assert.ok(worker.includes("_publicLimousineShowroomFieldsFromStoredProfile(profile)"));
  assert.ok(worker.includes("_limousineTestCompanyAllowlisted"));
});

test("11) Billit due-index imports and scheduled callsites remain live", () => {
  assert.ok(worker.includes("./modules/billit_outbox_due_index.js"));
  assert.ok(worker.includes("async function processBillitDueOutboxIndex"));
  assert.ok(worker.includes("runBillitOutboxDueMigrationStep"));
  assert.ok(worker.includes("nudgeBillitDueOutboxForBooking"));
  assert.ok(worker.includes("sweepBillitDurableRecoveryOutbox"));
  const scheduled = worker.slice(
    worker.indexOf("async scheduled(event, env, ctx)"),
    worker.indexOf("async fetch(request, env, ctx)"),
  );
  assert.ok(scheduled.includes("runBillitDurableRecoveryScheduledPass"));
  assert.equal(BILLIT_OUTBOX_DUE_PREFIX, "billit_outbox_due:v1:");
});

test("12) old Billit full-scan path is not reactivated", () => {
  assert.ok(worker.includes("DO NOT wire this into the cron"));
  const scheduled = worker.slice(
    worker.indexOf("async scheduled(event, env, ctx)"),
    worker.indexOf("async fetch(request, env, ctx)"),
  );
  assert.ok(!scheduled.includes("billit_create_outbox:"));
  assert.ok(!scheduled.includes("list + get every"));
});

test("13) Billit read-count bounds remain unchanged", () => {
  assert.ok(dueIndex.includes("BILLIT_OUTBOX_DUE_PREFIX"));
  assert.ok(worker.includes("limit: 20"));
  assert.ok(worker.includes("runBillitOutboxDueMigrationStep") || worker.includes("BILLIT_OUTBOX_DUE_MIGRATION"));
});

test("14) RateHawk bindings and routing remain unchanged", () => {
  assert.ok(wrangler.includes('binding = "RATEHAWK_HOTELS"'));
  assert.ok(wrangler.includes('service = "fluxidi-ratehawk-hotels-api"'));
  assert.ok(wrangler.includes('binding = "RATEHAWK_HOTELS_TEST"'));
  assert.ok(wrangler.includes('RATEHAWK_TEST_PREBOOK_ENABLED = "0"'));
  assert.ok(worker.includes("./modules/ratehawk_hotels_facade.mjs"));
  assert.ok(worker.includes('url.pathname === "/public/hotels/ratehawk/hotelpage"'));
});

test("15) cron and binding matrix remain unchanged", () => {
  assert.ok(wrangler.includes('crons = ["*/2 * * * *"]') || wrangler.includes("*/2 * * * *"));
  assert.ok(wrangler.includes('binding = "BOOKING_KV"'));
  assert.ok(wrangler.includes("FLUXIDI_TRACKING"));
  assert.ok(wrangler.includes("INVOICE_KV"));
  assert.ok(wrangler.includes("PUBLIC_MEDIA"));
  assert.ok(wrangler.includes("COMPLIANCE_WORKER"));
  assert.ok(wrangler.includes('name = "fluxidi-booking-api"'));
  assert.ok(wrangler.includes('main = "fluxidi_booking_worker.js"'));
});

test("16) no secret or token logging", () => {
  const accept = worker.slice(
    worker.indexOf('"/limousine/quote-requests/accept"'),
    worker.indexOf("company inbox list"),
  );
  assert.ok(!/console\.log\([^\)]*reference/.test(accept));
  const status = worker.slice(
    worker.indexOf("customer status poll via opaque ref"),
    worker.indexOf("GET /partners/nearby"),
  );
  assert.ok(!status.includes("console.log"));
  assert.ok(!worker.includes("console.log(env.LIMOUSINE_ACCEPTANCE_SECRET"));
});

test("17) no limousine route succeeds while gates are OFF", () => {
  const manual = worker.slice(
    worker.indexOf("LIMOUSINE-MARKETPLACE-P2C2 — manual quote lifecycle"),
    worker.indexOf("GET /partners/nearby?postcode="),
  );
  const gateHits = manual.split("_limousineManualQuoteGateEnabled(env)").length - 1;
  assert.ok(gateHits >= 6, `expected a gate check on each manual route, found ${gateHits}`);
  assert.ok(manual.includes('error: "manual_quote_gate_off"'));
  assert.ok(worker.includes('error: "limousine_book_disabled"'));
  assert.ok(worker.includes('reason: "gate_off"'));
});

test("18) no new Worker global mutable request state", () => {
  assert.ok(!worker.includes("let limousineRequest"));
  assert.ok(!worker.includes("globalThis.limousine"));
  assert.ok(!worker.includes("module.exports.limousineState"));
  const helpers = worker.slice(
    worker.indexOf("/// LIMOUSINE-MARKETPLACE-P2B1: server-owned quote gate."),
    worker.indexOf("/* -------- Google API helpers"),
  );
  assert.ok(!helpers.includes("let currentRequest"));
  assert.ok(!helpers.includes("var limousineCache"));
});

test("19) asynchronous side effects stay awaited or on the existing ctx pattern", () => {
  assert.ok(worker.includes("await _prepareLimousineBooking"));
  assert.ok(worker.includes("await _prepareLimousineManualBooking"));
  assert.ok(worker.includes("await _saveLimousineQuoteRecord"));
  assert.ok(worker.includes("await refreshPartnerLimousineProjection"));
  const scheduled = worker.slice(
    worker.indexOf("async scheduled(event, env, ctx)"),
    worker.indexOf("async fetch(request, env, ctx)"),
  );
  assert.ok(scheduled.includes("ctx.waitUntil"));
  assert.ok(!scheduled.includes("refreshPartnerLimousineProjection"));
});

test("20) limousine request traffic adds no scheduled KV reads while gates are OFF", () => {
  const scheduled = worker.slice(
    worker.indexOf("async scheduled(event, env, ctx)"),
    worker.indexOf("async fetch(request, env, ctx)"),
  );
  assert.ok(!scheduled.includes("limousine_quote_record"));
  assert.ok(!scheduled.includes("_loadLimousineInboxIndex"));
  assert.ok(!scheduled.includes("_loadLimousineQuoteRecord"));
  assert.ok(!scheduled.includes("LIMOUSINE_"));
  assert.equal(createHash("sha256").update(wrangler, "utf8").digest("hex").toUpperCase(),
    "4EDD8061662826214286A0A3F537EE19A07C248A18F3691252DA9B54DD219DA9");
});
