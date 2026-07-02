/* Dev-reset guard constants + pure env-flag check.
 * Moved verbatim from fluxidi_booking_worker.js (patch BW-M3), no behavior change.
 *
 * BW-M3 LITE scope only: this module intentionally holds ONLY the pure guard
 * primitives. The actual dev_reset handlers (handleScopedBookingTestReset*
 * and their helpers 28546..30298) still live in the main worker because they
 * transitively call booking/dispatch/KPI/rating core helpers. A future patch
 * (after the booking/dispatch/KPI core modules exist) can move them here.
 */

export const BOOKING_TEST_RESET_CONFIRM_PHRASE = "RESET_TEST_BOOKINGS";

export function allowDevResetEndpoints(env) {
  return String(env?.ALLOW_DEV_RESET_ENDPOINTS || "").trim().toLowerCase() === "true";
}
