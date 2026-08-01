/**
 * RELEASE-P0-MOLLIE-STREET-CHECKOUT-RETURN-1
 * Redirect URL helper + return-page contract (source) tests.
 */
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { buildStreetMollieRedirectUrl } from "./modules/street_mollie_checkout.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

test("buildStreetMollieRedirectUrl uses HTTPS /pay/return with deep-link return_to", () => {
  const url = buildStreetMollieRedirectUrl({
    baseUrl: "https://fluxidi-booking-api.fluxidi.workers.dev",
    paymentBookingId: "pay-uuid-1",
    returnTo: "fluxidi://pay/return",
  });
  assert.equal(
    url,
    "https://fluxidi-booking-api.fluxidi.workers.dev/pay/return?id=pay-uuid-1&return_to=fluxidi%3A%2F%2Fpay%2Freturn",
  );
  assert.ok(url.startsWith("https://"));
  assert.ok(!url.startsWith("fluxidi://"));
});

test("/pay/return page opens app immediately and uses status=pending hint", () => {
  const worker = fs.readFileSync(
    path.join(__dirname, "fluxidi_booking_worker.js"),
    "utf8",
  );
  assert.ok(worker.includes("immediateAppReturn"));
  assert.ok(worker.includes("params.set('status', 'pending')"));
  assert.ok(!worker.includes("params.set('status', 'confirmed')"));
  // Browser must not depend on authenticated /pay/status to open the app.
  assert.ok(
    worker.includes("Do NOT gate app return on that poll") ||
      worker.includes("immediateAppReturn"),
  );
});
