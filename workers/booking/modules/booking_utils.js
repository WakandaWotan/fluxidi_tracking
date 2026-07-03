/* Fluxidi widely-used pure utilities (BW-M8a).
 *
 * Verbatim extraction from workers/booking/fluxidi_booking_worker.js — no
 * behavior change. This module hosts the tiny, dependency-light helpers
 * that are used across dozens of call sites in main and are needed by
 * future read-model / booking-core module extractions (BW-M8b, BW-M8c).
 *
 * Scope:
 *   - `_pick`                             — deep-object accessor with
 *                                            null-safe path traversal.
 *   - `_bookingIntentMask`                — PII-safe short mask for log
 *                                            lines emitted around booking
 *                                            identifiers.
 *   - `_normLifecycleStatus`              — canonical lifecycle-status
 *                                            token normalizer.
 *   - `isTerminalLifecycleStatus`         — terminal-status predicate,
 *                                            backed by the private
 *                                            `TERMINAL_BOOKING_LIFECYCLE_STATUSES`
 *                                            set (also moved).
 *
 * Explicitly NOT moved (STOP rule — payment/dispatch/booking mutations,
 * KV writers, or booking-core coupling):
 *   - payment classification (`_bookingRecordIsPaidForCredit`,
 *     `_bookingPaymentStatusTokens`, …) — belongs to BW-M8b.
 *   - flatten / read-model pipeline — belongs to BW-M8c.
 *   - any helper that mutates state, calls KV, or reaches into
 *     dispatch / driver / document / Billit / Chiron code paths.
 *
 * Acyclic import graph:
 *   parsing_utils.js  ─►  booking_utils.js
 *   booking_utils.js does NOT import back into main.
 */

import { safeStr } from "./parsing_utils.js";

/* ---- Deep-object accessor -------------------------------------------- */

// Byte-identical to `_pick` in fluxidi_booking_worker.js.
export function _pick(obj, path, fb = null) {
  let cur = obj;
  for (const key of path) {
    if (!cur || typeof cur !== "object" || !(key in cur)) return fb;
    cur = cur[key];
  }
  return cur == null ? fb : cur;
}

/* ---- PII-safe log mask for booking identifiers ----------------------- */

// Byte-identical to `_bookingIntentMask` in fluxidi_booking_worker.js.
// Uses `safeStr` from parsing_utils.js (identical to main's call).
export function _bookingIntentMask(value) {
  const raw = safeStr(value, 128);
  if (!raw) return "";
  if (raw.length <= 6) return raw;
  return `${raw.slice(0, 3)}...${raw.slice(-3)}`;
}

/* ---- Lifecycle-status normalization ---------------------------------- */

// Byte-identical to `_normLifecycleStatus` in fluxidi_booking_worker.js.
export function _normLifecycleStatus(v) {
  const raw = String(v || "").toUpperCase().trim();
  if (raw === "COMPLETED" || raw === "COMPLETE" || raw === "DONE" || raw === "CLOSED") {
    return "COMPLETED";
  }
  if (
    raw === "CANCELLED" ||
    raw === "CANCELED" ||
    raw === "DELETED" ||
    raw === "ARCHIVED" ||
    raw === "DECLINED" ||
    raw === "FAILED" ||
    raw === "EXPIRED"
  ) {
    return "CANCELLED";
  }
  if (raw === "BOOKED" || raw === "CONFIRMED" || raw === "PENDING" || raw === "ACTIVE" || raw === "OPEN") {
    return "PENDING";
  }
  return "PENDING";
}

// Byte-identical to `TERMINAL_BOOKING_LIFECYCLE_STATUSES` in
// fluxidi_booking_worker.js. Kept as a module-private constant because
// only `isTerminalLifecycleStatus` reads it in main (grep-verified). If a
// future consumer needs it, export it separately without changing shape.
const TERMINAL_BOOKING_LIFECYCLE_STATUSES = new Set([
  "COMPLETED",
  "CANCELLED",
  "CANCELED",
  "DELETED",
  "DECLINED",
  "FAILED",
  "EXPIRED",
]);

// Byte-identical to `isTerminalLifecycleStatus` in fluxidi_booking_worker.js.
export function isTerminalLifecycleStatus(value) {
  const raw = String(value || "").toUpperCase().trim();
  if (TERMINAL_BOOKING_LIFECYCLE_STATUSES.has(raw)) return true;
  const normalized = _normLifecycleStatus(raw);
  return normalized === "COMPLETED" || normalized === "CANCELLED";
}
