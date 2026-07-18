// STREET-RIDE-HISTORY-DUPLICATE-ZERO-BOOKING-1 / 1A / 1B — canonical dedupe.
//
// Run: node --test workers/tracking/modules/street_history_canonical.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import {
  STREET_HISTORY_CANONICAL_VERSION,
  dedupeCanonicalStreetHistory,
  isCanonicalStreetPlannedShadow,
  streetHistoryDirectRideKeySet,
  streetHistoryCanonicalRideKey,
  streetHistoryTripShape,
  streetHistoryFingerprint,
  streetRideBookingBlocksShadowWrite,
} from "./street_history_canonical.mjs";

// -- Real runtime shapes: the ids DIFFER between the two records -----------
// €3,20 Completed: direct tracking trip. Its canonical key is its trip_id.
const direct320 = (over = {}) => ({
  trip_id: "trip_DIRECT_9f3a10",
  kind: "direct",
  booking_id: "street_OLD_1752863820000", // booking id at start (may be stale)
  source: "street_ride",
  km_total: 1.4,
  total_eur: 3.2,
  currency: "EUR",
  booking_details: {},
  ...over,
});

// €0,00 Completed + Outbound: the operational-leg shadow. In the failing
// runtime its booking_id / parent_booking_id do NOT equal the direct trip's
// booking_id (reconciled / remapped booking id).
const legacyShadow000 = (over = {}) => ({
  trip_id: "planned_street_NEW_88_street_NEW_88OUTBOUND",
  kind: "planned",
  booking_id: "street_NEW_88",
  km_total: 0,
  total_eur: 0,
  currency: "EUR",
  booking_details: {
    leg_type: "outbound",
    leg_id: "street_NEW_88:OUTBOUND",
    parent_booking_id: "street_NEW_88",
    is_operational_leg: true,
  },
  ...over,
});

// New-format shadow that carries the explicit write-time link.
const linkedShadow000 = (over = {}) =>
  legacyShadow000({
    linked_tracking_trip_id: "trip_DIRECT_9f3a10",
    ...over,
  });

test("FASE version constant is 1B", () => {
  assert.equal(STREET_HISTORY_CANONICAL_VERSION, "1B");
});

test("fingerprint is stable, short and non-reversible-looking", () => {
  const a = streetHistoryFingerprint("street_NEW_88");
  const b = streetHistoryFingerprint("street_NEW_88");
  const c = streetHistoryFingerprint("street_OLD_1752863820000");
  assert.equal(a, b);
  assert.notEqual(a, c);
  assert.ok(a.length <= 8);
  assert.equal(streetHistoryFingerprint(""), "-");
});

test("FASE4/6.2-6.6: differing booking ids, BOOKING_KV link collapses to one €3,20 row", () => {
  const resolvedLinks = new Map([["street_NEW_88", "trip_DIRECT_9f3a10"]]);
  const { trips, dropped } = dedupeCanonicalStreetHistory(
    [direct320(), legacyShadow000()],
    { resolvedLinks },
  );
  assert.equal(trips.length, 1);
  assert.equal(dropped, 1);
  assert.equal(trips[0].kind, "direct");
  assert.equal(trips[0].total_eur, 3.2);
  assert.equal(trips[0].canonical_physical_ride_key, "trip_DIRECT_9f3a10");
});

test("without a resolved link, legacy shadow with differing ids stays (no guessing)", () => {
  // This is precisely why 1A failed: no shared id, no link -> cannot merge.
  const { trips, dropped } = dedupeCanonicalStreetHistory([
    direct320(),
    legacyShadow000(),
  ]);
  assert.equal(dropped, 0);
  assert.equal(trips.length, 2);
});

test("FASE3/6.3: explicit write-time linked_tracking_trip_id collapses regardless of booking id", () => {
  const { trips, dropped } = dedupeCanonicalStreetHistory([
    direct320(),
    linkedShadow000(),
  ]);
  assert.equal(dropped, 1);
  assert.equal(trips.length, 1);
  assert.equal(trips[0].kind, "direct");
});

test("linked shadow collapses even when it appears BEFORE its direct trip", () => {
  const { trips, dropped } = dedupeCanonicalStreetHistory([
    linkedShadow000(),
    direct320(),
  ]);
  assert.equal(dropped, 1);
  assert.equal(trips.length, 1);
  assert.equal(trips[0].kind, "direct");
});

test("annotation contract exposed on rows", () => {
  const { trips } = dedupeCanonicalStreetHistory([direct320(), linkedShadow000()]);
  assert.equal(trips[0].canonical_trip_kind, "direct");
  assert.equal(trips[0].is_operational_shadow, false);
  assert.equal(trips[0].canonical_physical_ride_key, "trip_DIRECT_9f3a10");
});

test("legacy 1A shape (shared booking id) still collapses", () => {
  const d = direct320({ booking_id: "street_SAME" });
  const s = legacyShadow000({
    trip_id: "planned_street_SAME_OUTBOUND",
    booking_id: "street_SAME",
    booking_details: {
      leg_type: "outbound",
      parent_booking_id: "street_SAME",
      is_operational_leg: true,
    },
  });
  const { trips, dropped } = dedupeCanonicalStreetHistory([d, s]);
  assert.equal(dropped, 1);
  assert.equal(trips.length, 1);
});

test("FASE6.7/6.8 guard predicate refuses redundant street-ride shadow write", () => {
  assert.equal(
    streetRideBookingBlocksShadowWrite({
      source: "street_ride",
      rideType: "direct",
      trackingTripId: "trip_DIRECT_9f3a10",
      directTripExists: true,
    }),
    true,
  );
  // No direct trip yet -> do not block (nothing to dedupe against).
  assert.equal(
    streetRideBookingBlocksShadowWrite({
      source: "street_ride",
      rideType: "direct",
      trackingTripId: "trip_DIRECT_9f3a10",
      directTripExists: false,
    }),
    false,
  );
  // Real planned booking -> never blocked.
  assert.equal(
    streetRideBookingBlocksShadowWrite({
      source: "planned",
      rideType: "planned",
      trackingTripId: "",
      directTripExists: false,
    }),
    false,
  );
});

test("FASE6.9/6.10 real planned outbound + return (no direct, no link) stay", () => {
  const outbound = {
    trip_id: "planned_P9",
    kind: "planned",
    booking_id: "P9",
    total_eur: 20,
    booking_details: { leg_type: "outbound", parent_booking_id: "P9", is_operational_leg: true },
  };
  const ret = {
    trip_id: "planned_P9_RETURN",
    kind: "planned",
    booking_id: "P9",
    total_eur: 20,
    booking_details: { leg_type: "return", parent_booking_id: "P9", is_operational_leg: true },
  };
  const { trips, dropped } = dedupeCanonicalStreetHistory([outbound, ret]);
  assert.equal(dropped, 0);
  assert.equal(trips.length, 2);
});

test("FASE6.11 real free €0 direct ride stays visible", () => {
  const { trips, dropped } = dedupeCanonicalStreetHistory([
    direct320({ trip_id: "trip_free", booking_id: "street_free", total_eur: 0, km_total: 0 }),
  ]);
  assert.equal(dropped, 0);
  assert.equal(trips.length, 1);
  assert.equal(trips[0].total_eur, 0);
});

test("FASE6.12 unresolved legacy record stays safely visible", () => {
  const { trips, dropped } = dedupeCanonicalStreetHistory([legacyShadow000()]);
  assert.equal(dropped, 0);
  assert.equal(trips.length, 1);
});

test("FASE6.13/6.14 dedupe before counts: total/completed drop by exactly one", () => {
  const resolvedLinks = new Map([["street_NEW_88", "trip_DIRECT_9f3a10"]]);
  const input = [direct320(), legacyShadow000()];
  const before = input.length;
  const { trips } = dedupeCanonicalStreetHistory(input, { resolvedLinks });
  const completed = trips.length;
  assert.equal(before, 2);
  assert.equal(completed, 1);
});

test("FASE7 pagination cannot separate the relation (gap between shadow and direct)", () => {
  const resolvedLinks = new Map([["street_NEW_88", "trip_DIRECT_9f3a10"]]);
  const filler = Array.from({ length: 5 }, (_, i) =>
    direct320({ trip_id: `other_${i}`, booking_id: `street_other_${i}` }),
  );
  const input = [legacyShadow000(), ...filler, direct320()];
  const { trips, dropped } = dedupeCanonicalStreetHistory(input, { resolvedLinks });
  assert.equal(dropped, 1);
  assert.equal(trips.filter((t) => t.kind === "planned").length, 0);
  assert.equal(trips.length, 6);
});

test("idempotent: re-running dedupe does not re-add the shadow", () => {
  const resolvedLinks = new Map([["street_NEW_88", "trip_DIRECT_9f3a10"]]);
  const once = dedupeCanonicalStreetHistory([direct320(), legacyShadow000()], {
    resolvedLinks,
  }).trips;
  const twice = dedupeCanonicalStreetHistory(once, { resolvedLinks }).trips;
  assert.equal(twice.length, 1);
});

test("helpers: direct ride key set holds trip_id AND booking_id", () => {
  const keys = streetHistoryDirectRideKeySet([direct320()]);
  assert.equal(keys.has("trip_DIRECT_9f3a10"), true);
  assert.equal(keys.has("street_OLD_1752863820000"), true);
});

test("isCanonicalStreetPlannedShadow honours explicit link and resolvedLink arg", () => {
  const keys = streetHistoryDirectRideKeySet([direct320()]);
  assert.equal(isCanonicalStreetPlannedShadow(linkedShadow000(), keys), true);
  assert.equal(isCanonicalStreetPlannedShadow(legacyShadow000(), keys), false);
  assert.equal(
    isCanonicalStreetPlannedShadow(legacyShadow000(), keys, "trip_DIRECT_9f3a10"),
    true,
  );
});

test("canonical ride key: planned prefers linked/resolved tracking id", () => {
  assert.equal(streetHistoryCanonicalRideKey(linkedShadow000()), "trip_DIRECT_9f3a10");
  assert.equal(
    streetHistoryCanonicalRideKey(legacyShadow000(), "trip_DIRECT_9f3a10"),
    "trip_DIRECT_9f3a10",
  );
  assert.equal(streetHistoryCanonicalRideKey(legacyShadow000()), "street_NEW_88");
  assert.equal(streetHistoryCanonicalRideKey(direct320()), "trip_DIRECT_9f3a10");
});

test("FASE1 live shape: fingerprints prove the ids differ between the two rows", () => {
  const d = streetHistoryTripShape(direct320());
  const s = streetHistoryTripShape(legacyShadow000());
  assert.equal(d.kind, "direct");
  assert.equal(d.tripIdShape, "direct");
  assert.equal(d.amountBucket, "positive");
  assert.equal(s.kind, "planned");
  assert.equal(s.legType, "outbound");
  assert.equal(s.amountBucket, "zero");
  assert.equal(s.isOperationalLeg, true);
  // The whole point: canonical key hashes differ without a resolved link.
  assert.notEqual(d.canonicalKeyHash, s.canonicalKeyHash);
  // With the resolved link the planned row's canonical key matches the direct.
  const sLinked = streetHistoryTripShape(legacyShadow000(), "trip_DIRECT_9f3a10");
  assert.equal(sLinked.canonicalKeyHash, d.canonicalKeyHash);
  assert.equal(sLinked.hasLinkedTrackingTripId, true);
});
