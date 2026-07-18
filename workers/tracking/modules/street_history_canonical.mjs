// STREET-RIDE-HISTORY-DUPLICATE-ZERO-BOOKING-1 / 1A / 1B
//
// Canonical de-duplication of driver ride history at the /trips/history source.
//
// One physical street ride can be stored as TWO trip records in tracking KV:
//
//  1. a `direct` trip (handleStartDirectTrip + handleStopTrip) — the ride
//     source: real finalized fare (e.g. 3.20), distance, wait, start/stop.
//  2. a `planned` operational-leg shadow (handleRecordPlannedStopTrip) — a
//     projection of the SAME physical ride via the linked direct booking's
//     synthesized OUTBOUND leg. km 0, total_eur 0, leg_type "outbound".
//
// WHY 1A FAILED AT RUNTIME
// ------------------------
// 1A assumed both records share the SAME booking_id (and that the shadow trip
// id is planned_<bookingId>). Runtime proof (rowsBefore==rowsAfter) showed the
// visible €0,00 Outbound shadow's booking_id / parent_booking_id do NOT equal
// the direct trip's booking_id — the ids genuinely differ (pending booking link
// at start, later reconciliation, or a canonical booking-id remap). So a
// booking-id / name-convention match can never see the relation.
//
// CANONICAL CONTRACT (1B)
// -----------------------
// The reliable relation is the TRACKING TRIP ID:
//   * every direct booking record (BOOKING_KV `booking:<id>`) stores
//     `tracking_trip_id` = the direct trip id;
//   * new operational shadows are written with an explicit top-level
//     `linked_tracking_trip_id` (+ canonical_physical_ride_key, source);
//   * legacy shadows are resolved at read time from BOOKING_KV
//     (parent_booking_id/booking_id -> booking.tracking_trip_id).
//
// canonical_physical_ride_key:
//   * direct  -> its own trip_id (the real tracking trip id);
//   * planned -> linked_tracking_trip_id (explicit or resolved), else the
//     legacy parent_booking_id/booking_id.
//
// A `planned` record is an is_operational_shadow (countContribution=0) when its
// resolved tracking-trip link (or, legacy, its booking key) is OWNED by a
// direct trip. It NEVER inspects time / amount / address, so real planned
// outbound/return legs (no direct trip for that key) and real free €0 street
// rides (surviving row is the direct trip) are preserved. Unresolved legacy
// shadows are kept (keep_separate) — never guessed.

export const STREET_HISTORY_CANONICAL_VERSION = "1B";

function _kind(kind) {
  return String(kind ?? "").trim().toLowerCase();
}
function _id(id) {
  return String(id ?? "").trim();
}
function _details(trip) {
  const d = trip?.booking_details;
  return d && typeof d === "object" && !Array.isArray(d) ? d : {};
}

/// Non-reversible short fingerprint (FNV-1a 32-bit -> base36). For SAFE
/// relational comparison in logs only. Never reverse-engineerable to an id.
export function streetHistoryFingerprint(value) {
  const s = _id(value);
  if (!s) return "-";
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i += 1) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return (h >>> 0).toString(36).padStart(7, "0").slice(0, 8);
}

export function streetHistoryTripIsDirect(kind) {
  return _kind(kind) === "direct";
}

export function streetHistoryTripId(trip) {
  return _id(trip?.trip_id ?? trip?.tripId);
}

export function streetHistoryBookingId(trip) {
  return _id(trip?.booking_id ?? trip?.bookingId);
}

export function streetHistoryParentBookingId(trip) {
  const details = _details(trip);
  return _id(
    trip?.parent_booking_id ??
      trip?.parentBookingId ??
      details.parent_booking_id ??
      details.parentBookingId,
  );
}

export function streetHistoryLinkedTrackingTripId(trip) {
  const details = _details(trip);
  return _id(
    trip?.linked_tracking_trip_id ??
      trip?.linkedTrackingTripId ??
      details.linked_tracking_trip_id ??
      details.linkedTrackingTripId,
  );
}

export function streetHistoryIsOperationalLeg(trip) {
  const details = _details(trip);
  if (details.is_operational_leg === true || details.isOperationalLeg === true) {
    return true;
  }
  if (trip?.is_operational_leg === true || trip?.isOperationalLeg === true) {
    return true;
  }
  const legId = _id(
    trip?.leg_id ?? trip?.legId ?? details.leg_id ?? details.legId,
  );
  const legType = _id(
    trip?.leg_type ?? trip?.legType ?? details.leg_type ?? details.legType,
  );
  return legId !== "" || legType !== "";
}

/// canonical_physical_ride_key. `resolvedLink` is a BOOKING_KV-resolved
/// tracking_trip_id for legacy shadows (optional).
export function streetHistoryCanonicalRideKey(trip, resolvedLink = "") {
  if (_kind(trip?.kind) === "direct") {
    return streetHistoryTripId(trip) || streetHistoryBookingId(trip);
  }
  const linked = streetHistoryLinkedTrackingTripId(trip) || _id(resolvedLink);
  if (linked) return linked;
  return streetHistoryParentBookingId(trip) || streetHistoryBookingId(trip);
}

/// Set of keys owned by direct trips: each direct trip's trip_id AND booking_id
/// so a shadow can match by either the tracking-trip relation or the legacy
/// booking relation.
export function streetHistoryDirectRideKeySet(trips) {
  const keys = new Set();
  for (const trip of trips ?? []) {
    if (!streetHistoryTripIsDirect(trip?.kind)) continue;
    const tripId = streetHistoryTripId(trip);
    const bookingId = streetHistoryBookingId(trip);
    if (tripId) keys.add(tripId);
    if (bookingId) keys.add(bookingId);
  }
  return keys;
}

export function isCanonicalStreetPlannedShadow(trip, directKeys, resolvedLink = "") {
  if (_kind(trip?.kind) !== "planned") return false;
  const owns =
    directKeys instanceof Set
      ? (k) => directKeys.has(k)
      : Array.isArray(directKeys)
        ? (k) => directKeys.includes(k)
        : () => false;
  // 1) Explicit write-time / BOOKING_KV-resolved tracking-trip link.
  const linked = streetHistoryLinkedTrackingTripId(trip) || _id(resolvedLink);
  if (linked && owns(linked)) return true;
  // 2) Legacy relational fallback: booking key owned by a direct trip + proof
  //    this is an operational leg (or the deterministic planned_<key> name).
  const parent = streetHistoryParentBookingId(trip);
  const bookingId = streetHistoryBookingId(trip);
  const ownedKey = [parent, bookingId].find((k) => k && owns(k));
  if (!ownedKey) return false;
  if (streetHistoryIsOperationalLeg(trip)) return true;
  const tripId = streetHistoryTripId(trip);
  return (
    tripId === `planned_${ownedKey}` ||
    tripId.startsWith(`planned_${ownedKey}_`) ||
    tripId === `planned_${bookingId}` ||
    tripId.startsWith(`planned_${bookingId}_`)
  );
}

/// FASE 2 server guard predicate (pure). A redundant street-ride operational
/// shadow write must be refused when the booking is a street-ride / direct ride
/// whose physical ride is already stored as a direct trip.
export function streetRideBookingBlocksShadowWrite({
  source = "",
  rideType = "",
  trackingTripId = "",
  directTripExists = false,
} = {}) {
  const isStreetDirect =
    _id(source).toLowerCase() === "street_ride" ||
    _id(rideType).toLowerCase() === "direct";
  return Boolean(isStreetDirect && _id(trackingTripId) && directTripExists);
}

/// Bounded structural descriptor (PII-free) with non-reversible fingerprints.
export function streetHistoryTripShape(trip, resolvedLink = "") {
  const kind = _kind(trip?.kind) || "unknown";
  const details = _details(trip);
  const bookingId = streetHistoryBookingId(trip);
  const parentBookingId = streetHistoryParentBookingId(trip);
  const tripId = streetHistoryTripId(trip);
  const linked = streetHistoryLinkedTrackingTripId(trip) || _id(resolvedLink);
  const canonicalKey = streetHistoryCanonicalRideKey(trip, resolvedLink);
  const legTypeRaw = _id(
    trip?.leg_type ?? trip?.legType ?? details.leg_type ?? details.legType,
  ).toLowerCase();
  const legType =
    legTypeRaw === "outbound" || legTypeRaw === "return" ? legTypeRaw : "none";
  let tripIdShape = "other";
  if (kind === "direct") {
    tripIdShape = "direct";
  } else if (
    (bookingId && tripId === `planned_${bookingId}`) ||
    (parentBookingId && tripId === `planned_${parentBookingId}`)
  ) {
    tripIdShape = "planned_exact";
  } else if (
    (bookingId && tripId.startsWith(`planned_${bookingId}_`)) ||
    (parentBookingId && tripId.startsWith(`planned_${parentBookingId}_`))
  ) {
    tripIdShape = "planned_suffix";
  } else if (tripId.startsWith("planned_")) {
    tripIdShape = "planned_other";
  }
  const amount = Number(trip?.total_eur);
  const amountBucket = !Number.isFinite(amount)
    ? "missing"
    : amount > 0
      ? "positive"
      : "zero";
  const distance = Number(trip?.km_total);
  const sourceType =
    _id(trip?.source).toLowerCase() === "street_ride"
      ? "streetRide"
      : kind === "planned"
        ? "planned"
        : kind === "direct"
          ? "streetRide"
          : "unknown";
  return {
    kind,
    tripIdShape,
    hasBookingId: bookingId !== "",
    hasParentBookingId: parentBookingId !== "",
    hasTrackingTripId: tripId !== "",
    hasLinkedTrackingTripId: linked !== "",
    hasCanonicalKey: canonicalKey !== "",
    isOperationalLeg: streetHistoryIsOperationalLeg(trip),
    legType,
    sourceType,
    amountBucket,
    hasAmount: Number.isFinite(amount) && amount > 0,
    hasDistance: Number.isFinite(distance) && distance > 0,
    bookingKeyHash: streetHistoryFingerprint(bookingId),
    parentKeyHash: streetHistoryFingerprint(parentBookingId),
    trackingKeyHash: streetHistoryFingerprint(tripId),
    canonicalKeyHash: streetHistoryFingerprint(canonicalKey),
  };
}

export function formatStreetHistoryLiveShapeLog(shape) {
  return (
    "[STREET_HISTORY_LIVE_SHAPE] " +
    `kind=${shape.kind} tripIdShape=${shape.tripIdShape} ` +
    `hasBookingId=${shape.hasBookingId} hasParentBookingId=${shape.hasParentBookingId} ` +
    `hasTrackingTripId=${shape.hasTrackingTripId} ` +
    `hasLinkedTrackingTripId=${shape.hasLinkedTrackingTripId} ` +
    `hasCanonicalKey=${shape.hasCanonicalKey} ` +
    `isOperationalLeg=${shape.isOperationalLeg} legType=${shape.legType} ` +
    `sourceType=${shape.sourceType} amountBucket=${shape.amountBucket} ` +
    `bookingKeyHash=${shape.bookingKeyHash} parentKeyHash=${shape.parentKeyHash} ` +
    `trackingKeyHash=${shape.trackingKeyHash} canonicalKeyHash=${shape.canonicalKeyHash}`
  );
}

/// Annotates each trip with the 1B canonical contract fields, drops operational
/// shadows, returns { trips, dropped }. `resolvedLinks` is an optional
/// Map<bookingId|parentBookingId, trackingTripId> from BOOKING_KV enrichment.
/// Call BEFORE counts and pagination.
export function dedupeCanonicalStreetHistory(
  trips,
  { resolvedLinks, onLog, onShape } = {},
) {
  const list = Array.isArray(trips) ? trips : [];
  const directKeys = streetHistoryDirectRideKeySet(list);
  const links = resolvedLinks instanceof Map ? resolvedLinks : new Map();
  const linkFor = (trip) => {
    const parent = streetHistoryParentBookingId(trip);
    const bookingId = streetHistoryBookingId(trip);
    return _id(links.get(parent) || links.get(bookingId) || "");
  };
  const kept = [];
  let dropped = 0;
  for (const trip of list) {
    const kind = _kind(trip?.kind);
    const resolvedLink = kind === "planned" ? linkFor(trip) : "";
    const rideKey = streetHistoryCanonicalRideKey(trip, resolvedLink);
    const shadow = isCanonicalStreetPlannedShadow(trip, directKeys, resolvedLink);
    if (typeof onShape === "function") {
      onShape(streetHistoryTripShape(trip, resolvedLink));
    }
    if (trip && typeof trip === "object") {
      trip.canonical_physical_ride_key = rideKey || null;
      trip.canonical_trip_kind =
        kind === "direct" ? "direct" : shadow ? "operational_shadow" : "planned";
      trip.is_operational_shadow = shadow;
      const linked = streetHistoryLinkedTrackingTripId(trip) || resolvedLink;
      if (linked) trip.linked_tracking_trip_id = linked;
    }
    if (shadow) {
      dropped += 1;
      if (typeof onLog === "function") {
        onLog({
          phase: "dedupe",
          source: "tracking",
          hasLinkedTrip: true,
          hasLinkedBooking: true,
          countContribution: 0,
          reason: "street_planned_leg_shadow_of_direct_trip",
        });
      }
      continue;
    }
    if (typeof onLog === "function") {
      onLog({
        phase: kind === "planned" ? "keep_separate" : "project",
        source: "tracking",
        hasLinkedTrip: kind === "direct",
        hasLinkedBooking: !!rideKey,
        countContribution: 1,
        reason:
          kind === "planned"
            ? "planned_leg_without_direct_trip_kept"
            : "canonical_ride_kept",
      });
    }
    kept.push(trip);
  }
  return { trips: kept, dropped };
}

export function formatStreetHistoryCanonicalLog(log) {
  return (
    "[STREET_HISTORY_CANONICAL] " +
    `phase=${log.phase} source=${log.source} ` +
    `hasLinkedTrip=${log.hasLinkedTrip} hasLinkedBooking=${log.hasLinkedBooking} ` +
    `countContribution=${log.countContribution} reason=${log.reason}`
  );
}
