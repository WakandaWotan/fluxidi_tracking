// PLANNED-RIDE-FIXED-PRICE-PRESENTATION-AND-DURABILITY-1
//
// Server-side fare resolution for POST /trip/record-planned-stop (and offline
// reconcile repair). Client `total_eur` is never authoritative when a valid
// booking/leg price exists. Never re-rounds an already-canonical booking fare.
//
// Run: node --test workers/tracking/modules/planned_stop_price.test.mjs

function _str(v, max = 200) {
  if (v === null || v === undefined) return "";
  const s = String(v).trim();
  return max > 0 ? s.slice(0, max) : s;
}

function _numOrNull(v) {
  if (v === null || v === undefined || v === "") return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

function _positiveMoney(v) {
  const n = _numOrNull(v);
  if (n == null || n <= 0) return null;
  return n;
}

function _asObject(v) {
  return v && typeof v === "object" && !Array.isArray(v) ? v : null;
}

function _pickFirstPositive(candidates) {
  for (const c of candidates) {
    const n = _positiveMoney(c);
    if (n != null) return n;
  }
  return null;
}

function _legTypeToken(legType) {
  const t = _str(legType, 32).toLowerCase();
  return t === "return" ? "return" : t ? "outbound" : "";
}

/**
 * Resolve the canonical planned fare from a booking record and/or booking_details
 * snapshot for the active leg.
 *
 * Priority:
 *   1. leg_price_incl_vat (matched leg)
 *   2. return/main split price for the active leg type
 *   3. canonical price_incl_vat / booking total
 */
export function resolveCanonicalPlannedBookingFare({
  bookingRecord = null,
  bookingDetails = null,
  legId = null,
  legType = null,
} = {}) {
  const record = _asObject(bookingRecord) || {};
  const details = _asObject(bookingDetails) || {};
  const nestedBooking =
    _asObject(details.booking) ||
    _asObject(details.record) ||
    _asObject(record.booking) ||
    {};
  const sources = [details, nestedBooking, record];

  const wantedLegId = _str(legId, 160);
  const wantedLegType = _legTypeToken(legType || details.leg_type || details.legType);

  // 1) Explicit leg price on the stop payload / operational row.
  for (const src of sources) {
    const legPrice = _pickFirstPositive([
      src.leg_price_incl_vat,
      src.legPriceInclVat,
      src.segment_price_eur,
      src.segmentPriceEur,
    ]);
    if (legPrice != null) {
      return { amount: legPrice, source: "leg_price_incl_vat" };
    }
  }

  // 1b) Operational legs array match.
  for (const src of sources) {
    const legs = Array.isArray(src.operational_legs)
      ? src.operational_legs
      : Array.isArray(src.legs)
        ? src.legs
        : null;
    if (!legs) continue;
    for (const rawLeg of legs) {
      const leg = _asObject(rawLeg);
      if (!leg) continue;
      const entryLegId = _str(leg.leg_id ?? leg.legId, 160);
      const entryType = _legTypeToken(leg.leg_type ?? leg.legType);
      if (wantedLegId && entryLegId && entryLegId !== wantedLegId) continue;
      if (!wantedLegId && wantedLegType && entryType && entryType !== wantedLegType) {
        continue;
      }
      const legPrice = _pickFirstPositive([
        leg.leg_price_incl_vat,
        leg.legPriceInclVat,
        leg.price_incl_vat,
        leg.priceInclVat,
        leg.price,
      ]);
      if (legPrice != null) {
        return { amount: legPrice, source: "operational_leg_price" };
      }
    }
  }

  // 2) Main / return split for the active leg.
  if (wantedLegType === "return") {
    for (const src of sources) {
      const returnPrice = _pickFirstPositive([
        src.price_incl_vat_return,
        src.priceInclVatReturn,
        src.return_price_eur,
        _asObject(src.quote)?.price_incl_vat_return,
        _asObject(_asObject(src.quote)?.pricing_return)?.price_incl_vat,
      ]);
      if (returnPrice != null) {
        return { amount: returnPrice, source: "price_incl_vat_return" };
      }
    }
  } else {
    for (const src of sources) {
      const mainPrice = _pickFirstPositive([
        src.price_incl_vat_main,
        src.priceInclVatMain,
        src.outbound_price_eur,
        _asObject(src.quote)?.price_incl_vat_main,
        _asObject(_asObject(src.quote)?.pricing_main)?.price_incl_vat,
      ]);
      if (mainPrice != null) {
        return { amount: mainPrice, source: "price_incl_vat_main" };
      }
    }
  }

  // 3) Canonical booking total.
  for (const src of sources) {
    const canonical = _pickFirstPositive([
      src.price_incl_vat,
      src.priceInclVat,
      src.total_price_incl_vat,
      src.totalPriceInclVat,
      _asObject(src.quote)?.price_incl_vat,
      _asObject(_asObject(src.quote)?.pricing)?.price_incl_vat,
      src.price,
      src.total_price,
      src.total,
    ]);
    if (canonical != null) {
      return { amount: canonical, source: "price_incl_vat" };
    }
  }

  return { amount: null, source: "missing" };
}

/**
 * Decide the persisted planned-stop `total_eur`.
 *
 * - Client total is never authoritative when a valid booking fare exists.
 * - Client 0 / missing / manipulated meter must not wipe a booking fare.
 * - Existing positive trip total is preserved for idempotency when booking
 *   fare cannot be resolved.
 * - Never writes 0 when a valid booking fare exists.
 * - Does not re-round canonical booking amounts.
 */
export function resolvePlannedStopTotalEur({
  bookingRecord = null,
  bookingDetails = null,
  legId = null,
  legType = null,
  clientTotalEur = null,
  existingTripTotalEur = null,
} = {}) {
  const canonical = resolveCanonicalPlannedBookingFare({
    bookingRecord,
    bookingDetails,
    legId,
    legType,
  });

  if (canonical.amount != null) {
    return {
      total_eur: canonical.amount,
      source: canonical.source,
      ignored_client_total: true,
      repaired_from_zero: _positiveMoney(existingTripTotalEur) == null &&
        (_numOrNull(clientTotalEur) == null || Number(clientTotalEur) <= 0),
    };
  }

  const existing = _positiveMoney(existingTripTotalEur);
  if (existing != null) {
    return {
      total_eur: existing,
      source: "existing_trip",
      ignored_client_total: true,
      repaired_from_zero: false,
    };
  }

  // No booking fare and no existing trip fare: refuse to persist a client
  // meter / zero as if it were the planned price.
  return {
    total_eur: null,
    source: "missing",
    ignored_client_total: true,
    repaired_from_zero: false,
  };
}
