/* Service word used to open an invoice / credit-note line.
 *
 * The invoice, PDF, Billit and Peppol pipelines are shared by every Fluxidi
 * product. Only the human-readable service word differs, so this is the single
 * place that decides it. Taxi and airport rides keep the historical default,
 * which keeps their exported descriptions byte-for-byte unchanged.
 *
 * Only authoritative display data is used. A raw vehicle id, offer id or
 * service enum must never reach a customer-visible invoice line, so a missing
 * display name degrades to the plain service word instead.
 */

import { safeStr } from "./parsing_utils.js";
import { DEFAULT_INVOICE_SERVICE_LINE_LABEL } from "./invoice_route_address.js";
import { LIMOUSINE_SERVICE_TYPE } from "./limousine_unified_intent.mjs";

const LIMOUSINE_SERVICE_LINE_LABEL = "Limousinevervoer";
const VEHICLE_NAME_SEPARATOR = " \u2013 "; // en dash

/// Reads the immutable accepted-price snapshot the Worker sealed onto a
/// canonical limousine booking. Returns null for taxi/airport records.
function limousineAcceptedSnapshot(rec) {
  if (!rec || typeof rec !== "object") return null;
  const candidates = [
    rec.quote?.limousine_accepted_price,
    rec.quote?.limousineAcceptedPrice,
    rec.limousine_accepted_price,
    rec.limousineAcceptedPrice,
    rec.booking?.limousine_accepted_price,
    rec.booking?.limousineAcceptedPrice,
  ];
  for (const candidate of candidates) {
    if (!candidate || typeof candidate !== "object") continue;
    // Same limousine marker the document projection already requires, so a
    // stub or foreign snapshot never claims the limousine service word.
    if (
      candidate.service_category === LIMOUSINE_SERVICE_TYPE ||
      candidate.service_type === LIMOUSINE_SERVICE_TYPE
    ) {
      return candidate;
    }
  }
  return null;
}

/// Human-readable vehicle name from the sealed snapshot, or "" when the quote
/// carried no published vehicle name.
export function invoiceServiceLineVehicleName(rec) {
  const snapshot = limousineAcceptedSnapshot(rec);
  if (!snapshot) return "";
  return safeStr(snapshot.vehicle_public_name ?? snapshot.vehiclePublicName);
}

/// Service word for a booking record's invoice and credit-note lines.
export function invoiceServiceLineLabel(rec) {
  if (!limousineAcceptedSnapshot(rec)) {
    return DEFAULT_INVOICE_SERVICE_LINE_LABEL;
  }
  const vehicleName = invoiceServiceLineVehicleName(rec);
  return vehicleName
    ? `${LIMOUSINE_SERVICE_LINE_LABEL}${VEHICLE_NAME_SEPARATOR}${vehicleName}`
    : LIMOUSINE_SERVICE_LINE_LABEL;
}
