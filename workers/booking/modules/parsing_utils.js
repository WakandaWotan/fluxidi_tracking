/* Shared low-risk parsing helpers.
 * Moved verbatim from fluxidi_booking_worker.js (patch BW-M1), no behavior change. */

export function safeStr(v) {
  if (v === null || v === undefined) return "";
  return String(v).trim();
}
