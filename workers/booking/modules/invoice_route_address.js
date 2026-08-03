// FLUXIDI-STREET-INVOICE-PICKUP-AND-EMBEDDED-LOGO-P0-1
//
// Pure helpers for authoritative street-ride route address snapshots used by
// invoice PDF projection. Coordinates may be stored for geocoding, but never
// become customer-visible address text. Geocoding itself lives in the worker
// (Mapbox); this module only decides what to persist and what to render.

import {
  looksLikeCoordinatePair,
  pickCustomerVisibleAddress,
} from "./document_phone_format.js";

function _safe(v, max = 400) {
  if (v === undefined || v === null) return "";
  const s = String(v).trim();
  return s.length > max ? s.slice(0, max) : s;
}

function _finite(n) {
  const x = Number(n);
  return Number.isFinite(x) ? x : null;
}

/**
 * Extract pickup/dropoff coordinates from a booking record or origin payload.
 * Supports lat/lon, latitude/longitude, and nested booking / origin objects.
 */
export function extractRouteCoordinates(recordOrOrigin = null, side = "from") {
  const src =
    recordOrOrigin && typeof recordOrOrigin === "object" ? recordOrOrigin : {};
  const booking =
    src.booking && typeof src.booking === "object" ? src.booking : {};
  const isFrom = side === "from" || side === "pickup" || side === "origin";
  const candidates = isFrom
    ? [
        src.from_lat ?? src.fromLat,
        src.pickup_lat ?? src.pickupLat,
        src.origin_lat ?? src.originLat,
        src.lat,
        src.latitude,
        booking.from_lat ?? booking.fromLat,
        booking.pickup_lat ?? booking.pickupLat,
        booking.lat,
        booking.latitude,
      ]
    : [
        src.to_lat ?? src.toLat,
        src.dropoff_lat ?? src.dropoffLat,
        src.destination_lat ?? src.destinationLat,
        src.lat,
        src.latitude,
        booking.to_lat ?? booking.toLat,
        booking.dropoff_lat ?? booking.dropoffLat,
        booking.lat,
        booking.latitude,
      ];
  const lngCandidates = isFrom
    ? [
        src.from_lng ?? src.fromLng ?? src.from_lon ?? src.fromLon,
        src.pickup_lng ?? src.pickupLng ?? src.pickup_lon ?? src.pickupLon,
        src.origin_lng ?? src.originLng ?? src.origin_lon ?? src.originLon,
        src.lng ?? src.lon ?? src.longitude,
        booking.from_lng ?? booking.fromLng ?? booking.from_lon ?? booking.fromLon,
        booking.pickup_lng ?? booking.pickupLng,
        booking.lng ?? booking.lon ?? booking.longitude,
      ]
    : [
        src.to_lng ?? src.toLng ?? src.to_lon ?? src.toLon,
        src.dropoff_lng ?? src.dropoffLng ?? src.dropoff_lon,
        src.destination_lng ?? src.destinationLng,
        src.lng ?? src.lon ?? src.longitude,
        booking.to_lng ?? booking.toLng ?? booking.to_lon ?? booking.toLon,
        booking.dropoff_lng ?? booking.dropoffLng,
        booking.lng ?? booking.lon ?? booking.longitude,
      ];
  let lat = null;
  let lng = null;
  for (const c of candidates) {
    lat = _finite(c);
    if (lat != null) break;
  }
  for (const c of lngCandidates) {
    lng = _finite(c);
    if (lng != null) break;
  }
  // Also parse "lat, lng" or "lng,lat" from a text field when numeric coords missing.
  if (lat == null || lng == null) {
    const text = _safe(
      isFrom
        ? src.from ?? booking.from ?? src.label
        : src.to ?? booking.to ?? src.label,
      80,
    );
    if (looksLikeCoordinatePair(text)) {
      const parts = text.split(",").map((p) => Number(String(p).trim()));
      if (parts.length === 2 && Number.isFinite(parts[0]) && Number.isFinite(parts[1])) {
        const a = parts[0];
        const b = parts[1];
        // Heuristic: the larger absolute value among typical BE pairs is latitude
        // (~50) vs longitude (~3). Also support explicit lon>90 edge cases.
        if (Math.abs(a) > 90) {
          lng = a;
          lat = b;
        } else if (Math.abs(b) > 90) {
          lat = a;
          lng = b;
        } else if (Math.abs(a) >= Math.abs(b)) {
          lat = a;
          lng = b;
        } else {
          lng = a;
          lat = b;
        }
      }
    }
  }
  if (lat == null || lng == null) return null;
  if (Math.abs(lat) > 90 || Math.abs(lng) > 180) return null;
  return { lat, lng };
}

/**
 * Prefer already-known human-readable address fields. Never returns coords.
 */
export function resolveHumanRouteAddress(record = null, side = "from") {
  const src = record && typeof record === "object" ? record : {};
  const booking =
    src.booking && typeof src.booking === "object" ? src.booking : {};
  const issued =
    src.route_address_snapshot && typeof src.route_address_snapshot === "object"
      ? src.route_address_snapshot
      : src.issuedDocument?.route_address_snapshot;
  if (side === "from" || side === "pickup") {
    return pickCustomerVisibleAddress(
      issued?.from_address,
      issued?.invoice_from_address,
      src.invoice_from_address,
      booking.invoice_from_address,
      src.from_full_address,
      booking.from_full_address,
      src.from_label,
      booking.from_label,
      src.pickup_address,
      booking.pickup_address,
      booking.pickupAddress,
      // last: booking.from only if not coords / Straatrit
      booking.from,
      src.from,
    );
  }
  return pickCustomerVisibleAddress(
    issued?.to_address,
    issued?.invoice_to_address,
    src.invoice_to_address,
    booking.invoice_to_address,
    src.to_full_address,
    booking.to_full_address,
    src.to_label,
    booking.to_label,
    src.destination_address,
    booking.destination_address,
    booking.dropoff_address,
    booking.to,
    src.to,
  );
}

/**
 * Build the envelope-only route address snapshot (NOT part of content_hash).
 */
export function buildRouteAddressSnapshot({
  fromAddress = "",
  toAddress = "",
  fromLat = null,
  fromLng = null,
  toLat = null,
  toLng = null,
  fromSource = null,
  toSource = null,
  resolvedAt = null,
} = {}) {
  const nowIso =
    typeof resolvedAt === "string" && resolvedAt
      ? resolvedAt
      : new Date().toISOString();
  const from = _safe(fromAddress, 400);
  const to = _safe(toAddress, 400);
  return {
    version: "route_address_snapshot_v1",
    from_address: from || null,
    to_address: to || null,
    invoice_from_address: from || null,
    invoice_to_address: to || null,
    from_coordinates:
      _finite(fromLat) != null && _finite(fromLng) != null
        ? { lat: _finite(fromLat), lng: _finite(fromLng) }
        : null,
    to_coordinates:
      _finite(toLat) != null && _finite(toLng) != null
        ? { lat: _finite(toLat), lng: _finite(toLng) }
        : null,
    from_source: _safe(fromSource, 64) || null,
    to_source: _safe(toSource, 64) || null,
    resolved_at: nowIso,
  };
}

/**
 * True when we should attempt Mapbox reverse geocode for this side.
 * Human-readable address already present → false (no geocoder call).
 */
export function needsReverseGeocode(record, side = "from") {
  if (resolveHumanRouteAddress(record, side)) return false;
  return extractRouteCoordinates(record, side) != null;
}

/**
 * Merge a newly resolved address into booking fields without wiping existing
 * frozen values. Returns a shallow-cloned record (or the same ref if unchanged).
 */
export function applyResolvedRouteAddressToBooking(
  record,
  {
    fromAddress = null,
    toAddress = null,
    fromSource = null,
    toSource = null,
    fromLat = null,
    fromLng = null,
    toLat = null,
    toLng = null,
    resolvedAt = null,
  } = {},
) {
  const src = record && typeof record === "object" ? record : null;
  if (!src) return record;
  const booking =
    src.booking && typeof src.booking === "object" ? { ...src.booking } : null;
  let changed = false;
  const next = { ...src };
  const nowIso =
    typeof resolvedAt === "string" && resolvedAt
      ? resolvedAt
      : new Date().toISOString();

  if (fromAddress && !resolveHumanRouteAddress(src, "from")) {
    next.invoice_from_address = _safe(fromAddress, 400);
    next.invoice_from_address_source = _safe(fromSource, 64) || "reverse_geocode";
    next.invoice_from_address_resolved_at = nowIso;
    if (booking) {
      booking.invoice_from_address = next.invoice_from_address;
      booking.invoice_from_address_source = next.invoice_from_address_source;
      booking.invoice_from_address_resolved_at = nowIso;
    }
    changed = true;
  }
  if (toAddress && !resolveHumanRouteAddress(src, "to")) {
    next.invoice_to_address = _safe(toAddress, 400);
    next.invoice_to_address_source = _safe(toSource, 64) || "reverse_geocode";
    next.invoice_to_address_resolved_at = nowIso;
    if (booking) {
      booking.invoice_to_address = next.invoice_to_address;
      booking.invoice_to_address_source = next.invoice_to_address_source;
      booking.invoice_to_address_resolved_at = nowIso;
    }
    changed = true;
  }
  // Persist supporting coordinates separately when provided.
  if (_finite(fromLat) != null && _finite(fromLng) != null) {
    if (next.from_lat == null) {
      next.from_lat = _finite(fromLat);
      next.from_lng = _finite(fromLng);
      if (booking) {
        booking.from_lat = next.from_lat;
        booking.from_lng = next.from_lng;
      }
      changed = true;
    }
  }
  if (_finite(toLat) != null && _finite(toLng) != null) {
    if (next.to_lat == null) {
      next.to_lat = _finite(toLat);
      next.to_lng = _finite(toLng);
      if (booking) {
        booking.to_lat = next.to_lat;
        booking.to_lng = next.to_lng;
      }
      changed = true;
    }
  }
  if (!changed) return src;
  if (booking) next.booking = booking;
  next.route_address_snapshot = buildRouteAddressSnapshot({
    fromAddress:
      next.invoice_from_address || resolveHumanRouteAddress(next, "from"),
    toAddress: next.invoice_to_address || resolveHumanRouteAddress(next, "to"),
    fromLat: next.from_lat ?? fromLat,
    fromLng: next.from_lng ?? fromLng,
    toLat: next.to_lat ?? toLat,
    toLng: next.to_lng ?? toLng,
    fromSource: next.invoice_from_address_source || fromSource,
    toSource: next.invoice_to_address_source || toSource,
    resolvedAt: nowIso,
  });
  return next;
}

/**
 * Prefer Document Core envelope `route_address_snapshot` over mutable booking.
 * Never returns raw coordinate pairs as customer-visible text.
 */
export function resolveIssuedRouteAddressSnapshot(
  issuedDocument = null,
  bookingRecord = null,
) {
  const doc =
    issuedDocument && typeof issuedDocument === "object" ? issuedDocument : null;
  const snap =
    doc?.route_address_snapshot &&
    typeof doc.route_address_snapshot === "object"
      ? doc.route_address_snapshot
      : null;
  if (snap && (snap.from_address || snap.to_address || snap.invoice_from_address || snap.invoice_to_address)) {
    const from = pickCustomerVisibleAddress(
      snap.from_address,
      snap.invoice_from_address,
    );
    const to = pickCustomerVisibleAddress(
      snap.to_address,
      snap.invoice_to_address,
    );
    // Snapshot present (even if both sides omit after coord filter) still wins
    // over mutable booking so post-issue edits cannot change the export.
    return {
      from,
      to,
      source: "document_core_route_address_snapshot",
      snapshot: snap,
    };
  }
  const from = resolveHumanRouteAddress(bookingRecord, "from");
  const to = resolveHumanRouteAddress(bookingRecord, "to");
  return {
    from,
    to,
    source: from || to ? "booking_envelope" : "missing",
    snapshot: bookingRecord?.route_address_snapshot || null,
  };
}

/**
 * Shared pickup/dropoff projection for Fluxidi PDF and Billit export.
 * Pure: never reverse-geocodes; never invents addresses.
 *
 * @param {object|null} issuedDocument Document Core record (preferred SoT)
 * @param {object|null} bookingRecord Mutable booking fallback only when snapshot absent
 * @param {{ missingLabel?: string }} [opts] When set (e.g. "Niet opgegeven"),
 *   missing sides use that label; otherwise empty string (omit).
 */
export function projectInvoiceRouteAddressesForExport(
  issuedDocument = null,
  bookingRecord = null,
  opts = {},
) {
  const missingLabel =
    opts && typeof opts.missingLabel === "string" ? opts.missingLabel : "";
  const resolved = resolveIssuedRouteAddressSnapshot(
    issuedDocument,
    bookingRecord,
  );
  const pickup = resolved.from || "";
  const dropoff = resolved.to || "";
  return {
    pickup,
    dropoff,
    pickup_display: pickup || missingLabel || "",
    dropoff_display: dropoff || missingLabel || "",
    source: resolved.source,
    snapshot: resolved.snapshot,
  };
}

/**
 * Billit / provider-neutral Taxirit line description with frozen route text.
 * Never embeds raw coordinate pairs. Caps at 240 chars (Billit Description).
 */
export function formatBillitTaxiritLineDescription({
  legSuffix = null,
  pickup = "",
  dropoff = "",
  missingLabel = "Niet opgegeven",
  maxLen = 240,
} = {}) {
  const base =
    legSuffix === "return"
      ? "Taxirit - terugrit"
      : legSuffix === "outbound" || legSuffix === "heenrit"
        ? "Taxirit - heenrit"
        : legSuffix
          ? `Taxirit - ${String(legSuffix).slice(0, 40)}`
          : "Taxirit";
  const from = pickCustomerVisibleAddress(pickup);
  const to = pickCustomerVisibleAddress(dropoff);
  if (!from && !to) return base.slice(0, maxLen);
  const left = from || missingLabel || "Niet opgegeven";
  const right = to || missingLabel || "Niet opgegeven";
  const full = `${base}: ${left} → ${right}`;
  if (full.length <= maxLen) return full;
  return full.slice(0, maxLen);
}

/**
 * Enrich provider-neutral line items so Taxirit descriptions carry the same
 * frozen route as the Fluxidi invoice PDF. Custom non-Taxirit descriptions are
 * left untouched; route_addresses is still returned for structured parity.
 */
export function enrichProviderNeutralLineItemsWithRoute(
  lineItems,
  issuedDocument = null,
  bookingRecord = null,
  { legType = null } = {},
) {
  const route = projectInvoiceRouteAddressesForExport(
    issuedDocument,
    bookingRecord,
  );
  const items = Array.isArray(lineItems) ? lineItems : [];
  const enriched = items.map((li) => {
    if (!li || typeof li !== "object" || Array.isArray(li)) return li;
    const desc = String(li.description || "").trim();
    const isTaxirit =
      !desc ||
      /^Taxirit(\b|$)/i.test(desc) ||
      /^Creditnota taxirit(\b|$)/i.test(desc);
    if (!isTaxirit) return { ...li };
    const isCredit = /^Creditnota/i.test(desc);
    const baseDesc = formatBillitTaxiritLineDescription({
      legSuffix: legType,
      pickup: route.pickup,
      dropoff: route.dropoff,
    });
    return {
      ...li,
      description: isCredit
        ? baseDesc.replace(/^Taxirit/, "Creditnota taxirit")
        : baseDesc,
    };
  });
  return {
    line_items: enriched,
    route_addresses: {
      pickup: route.pickup || null,
      dropoff: route.dropoff || null,
      pickup_display: route.pickup_display || null,
      dropoff_display: route.dropoff_display || null,
      source: route.source,
    },
  };
}
