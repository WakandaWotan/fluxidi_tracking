// LIMOUSINE-OPERATIONAL-HANDOFF-P3B — pure helpers + worker seam proofs.
// Run: node --test workers/booking/modules/limousine_operational_handoff.test.mjs

import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import {
  LIMOUSINE_ACCEPTANCE_ALREADY_USED,
  LIMOUSINE_COMPANY_CONFIRMATION_REQUIRED,
  LIMOUSINE_SERVICE_TYPE,
  applyLimousineCompanyConfirmation,
  bookingRecordLimousineServiceType,
  bookingRequiresLimousineCompanyConfirmation,
  companyConfirmationBlockedPaymentResult,
  isLimousineCompanyConfirmRawStatus,
  limousineAcceptanceAlreadyConsumed,
  limousineInvoiceOrChironBlocked,
  limousinePaymentBlockedUntilCompanyConfirm,
  preserveLimousineServiceType,
  projectLimousineOperationalListFields,
} from "./limousine_operational_handoff.mjs";
import {
  computeLimousineHourlyHireSnapshot,
  computeLimousinePackageSnapshot,
} from "./limousine_unified_intent.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const worker = readFileSync(join(__dirname, "..", "fluxidi_booking_worker.js"), "utf8");
const readModel = readFileSync(join(__dirname, "booking_read_model.js"), "utf8");
const intent = readFileSync(join(__dirname, "limousine_unified_intent.mjs"), "utf8");

test("1) service_type limousine is preserved and never rewritten to taxi/airport", () => {
  assert.equal(preserveLimousineServiceType("limousine", "passenger"), LIMOUSINE_SERVICE_TYPE);
  assert.equal(preserveLimousineServiceType("passenger", "airport"), "airport");
  assert.equal(
    bookingRecordLimousineServiceType({
      service_type: "passenger",
      booking: { service_type: "limousine" },
    }),
    LIMOUSINE_SERVICE_TYPE,
  );
  const row = projectLimousineOperationalListFields({
    service_type: "limousine",
    booking: {
      occasion: "wedding",
      pricing_mode: "hourly",
      requested_duration_minutes: 180,
      company_confirmation_required: true,
      limousine_accepted_price: {
        service_type: "limousine",
        published_pricing_mode: "hourly",
        from_price_cents: 12000,
      },
    },
  });
  assert.equal(row.service_type, LIMOUSINE_SERVICE_TYPE);
  assert.equal(row.occasion, "wedding");
  assert.equal(row.pricing_mode, "hourly");
  assert.equal(row.company_confirmation_required, true);
  assert.notEqual(row.service_type, "passenger");
  assert.notEqual(row.service_type, "airport");
  assert.notEqual(row.service_type, "unknown");
});

test("2) existing status POST maps company confirm without a new CONFIRMED lifecycle", () => {
  assert.equal(isLimousineCompanyConfirmRawStatus("confirmed"), true);
  assert.equal(isLimousineCompanyConfirmRawStatus("accepted"), true);
  assert.equal(isLimousineCompanyConfirmRawStatus("CANCELLED"), false);
  const rec = {
    status: "PENDING",
    company_confirmation_required: true,
    booking: { company_confirmation_required: true, service_type: "limousine" },
  };
  applyLimousineCompanyConfirmation(rec, "2026-08-20T12:00:00.000Z");
  assert.equal(rec.company_confirmation_required, false);
  assert.equal(rec.booking.company_confirmation_required, false);
  assert.equal(rec.company_confirmed_at, "2026-08-20T12:00:00.000Z");
  assert.equal(rec.status, "PENDING");
  assert.ok(worker.includes("raw_status: rawRequestedStatus"));
  assert.ok(worker.includes("_isLimousineCompanyConfirmRawStatus"));
  assert.ok(worker.includes("_applyLimousineCompanyConfirmation"));
  assert.ok(!worker.includes("createLimousineStatusMachine"));
  assert.ok(!worker.includes("/limousine/confirm"));
});

test("3) payment/invoice/Chiron stay blocked until existing confirmation", () => {
  const pending = { company_confirmation_required: true, status: "PENDING" };
  const confirmed = { company_confirmation_required: false, status: "PENDING" };
  const cancelled = { company_confirmation_required: false, status: "CANCELLED" };
  assert.equal(limousinePaymentBlockedUntilCompanyConfirm(pending), true);
  assert.equal(limousinePaymentBlockedUntilCompanyConfirm(confirmed), false);
  assert.equal(limousineInvoiceOrChironBlocked(pending), false);
  assert.equal(
    limousineInvoiceOrChironBlocked({ ...pending, service_type: "limousine" }),
    true,
  );
  assert.equal(
    limousineInvoiceOrChironBlocked({ ...cancelled, service_type: "limousine" }),
    true,
  );
  assert.equal(
    limousineInvoiceOrChironBlocked({ ...confirmed, service_type: "limousine" }),
    false,
  );
  assert.equal(
    limousineInvoiceOrChironBlocked({ ...cancelled, service_type: "airport" }),
    false,
  );
  assert.equal(
    companyConfirmationBlockedPaymentResult().error,
    LIMOUSINE_COMPANY_CONFIRMATION_REQUIRED,
  );
  assert.ok(worker.includes("limousinePaymentBlockedUntilCompanyConfirm"));
  assert.ok(worker.includes("limousineInvoiceOrChironBlocked"));
  assert.ok(worker.includes("company_confirmation_required"));
});

test("4) acceptance consume-once uses the existing quote transition", () => {
  assert.equal(limousineAcceptanceAlreadyConsumed({ state: "accepted" }), false);
  assert.equal(limousineAcceptanceAlreadyConsumed({ state: "booking_created" }), true);
  assert.equal(
    limousineAcceptanceAlreadyConsumed({ state: "accepted", booking_reference: "2026-08-000001" }),
    true,
  );
  assert.equal(LIMOUSINE_ACCEPTANCE_ALREADY_USED, "acceptance_reference_already_used");
  assert.ok(worker.includes("_markLimousineAcceptedQuoteConsumed"));
  assert.ok(worker.includes("limousineAcceptanceAlreadyConsumed"));
  assert.ok(worker.includes("_LIMOUSINE_QUOTE_STATES.BOOKING_CREATED"));
});

test("5) hourly and package snapshots stay integer cents and fail closed", () => {
  const hourly = {
    enabled: true,
    first_hour_cents: 10000,
    additional_hour_cents: 8000,
    minimum_duration_minutes: 120,
    currency: "EUR",
  };
  const below = computeLimousineHourlyHireSnapshot(hourly, 60);
  const above = computeLimousineHourlyHireSnapshot(hourly, 180);
  assert.equal(below.ok, true);
  assert.equal(below.billable_duration_minutes, 120);
  assert.equal(Number.isInteger(below.amount_cents), true);
  assert.equal(above.billable_duration_minutes, 180);
  const missingOverage = computeLimousinePackageSnapshot(
    {
      offer_id: "off_pkg",
      hourly: {
        enabled: true,
        package_amount_cents: 45000,
        package_duration_minutes: 180,
      },
    },
    240,
  );
  assert.equal(missingOverage.ok, false);
});

test("6) existing aggregates are reused; no second platform", () => {
  assert.ok(worker.includes('url.pathname === "/bookings" && request.method === "GET"'));
  assert.ok(worker.includes('url.pathname === "/driver/bookings"'));
  assert.ok(worker.includes('pathParts[2] === "status"'));
  assert.ok(worker.includes('pathParts[2] === "assign"'));
  assert.ok(worker.includes('pathParts[2] === "checkout-resume"'));
  assert.ok(worker.includes("upsertDashboardBookingsKpiProjectionBestEffort"));
  assert.ok(readModel.includes("projectLimousineOperationalListFields"));
  assert.ok(!intent.includes("new BookingAggregate"));
  assert.ok(!worker.includes("/limousine/planning"));
  assert.ok(!worker.includes("/limousine/driver-inbox"));
  assert.ok(!worker.includes("limousine_command_center"));
});
