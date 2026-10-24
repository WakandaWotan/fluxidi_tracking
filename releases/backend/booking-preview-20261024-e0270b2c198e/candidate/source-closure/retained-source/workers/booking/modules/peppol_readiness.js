/* Peppol readiness helpers.
 * Moved verbatim from fluxidi_booking_worker.js (patch BW-M4B), no behavior change.
 *
 * Currently a very small helper surface (Peppol identifier from BE enterprise
 * number). Kept as its own module so future Peppol readiness helpers can be
 * co-located here without cross-contaminating billit_provider.js.
 */

import { sanitizeTenantString } from "./parsing_utils.js";

/* Build a Peppol Participant Identifier for a Belgian company from its
 * enterprise number. Only 10-digit sanitized inputs are accepted; any other
 * length returns an empty string so the caller can fall back cleanly. Uses
 * scheme 0208 (Belgian CBE / KBO). Pure helper; no I/O. */
export function peppolIdentifierFromBelgianEnterpriseNumber(value) {
  const digits = sanitizeTenantString(value, 40).replace(/\D+/g, "");
  if (digits.length !== 10) return "";
  return `0208:${digits}`;
}
