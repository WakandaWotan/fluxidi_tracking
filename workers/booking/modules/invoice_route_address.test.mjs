// FLUXIDI-STREET-INVOICE-PICKUP-AND-EMBEDDED-LOGO-P0-1
import { test } from "node:test";
import assert from "node:assert/strict";

import {
  extractRouteCoordinates,
  resolveHumanRouteAddress,
  needsReverseGeocode,
  applyResolvedRouteAddressToBooking,
  buildRouteAddressSnapshot,
  resolveIssuedRouteAddressSnapshot,
} from "./invoice_route_address.js";

test("existing human-readable pickup wins; no geocode needed", () => {
  const rec = {
    booking: {
      from: "50.772006, 3.669447",
      invoice_from_address: "Koekamerstraat 48A, 9688 Schorisse",
      to: "Scheldestraat 5, 9690 Kluisbergen",
    },
  };
  assert.equal(
    resolveHumanRouteAddress(rec, "from"),
    "Koekamerstraat 48A, 9688 Schorisse",
  );
  assert.equal(needsReverseGeocode(rec, "from"), false);
});

test("coordinate-only pickup extracts coords and needs geocode", () => {
  const rec = { booking: { from: "3.669447,50.772006" } };
  const coords = extractRouteCoordinates(rec, "from");
  assert.ok(coords);
  assert.equal(Math.round(coords.lat * 1000) / 1000, 50.772);
  assert.equal(needsReverseGeocode(rec, "from"), true);
  assert.equal(resolveHumanRouteAddress(rec, "from"), "");
});

test("applyResolvedRouteAddressToBooking is idempotent and persists provenance", () => {
  const base = {
    booking: { from: "3.669447,50.772006", to: "Scheldestraat 5, 9690 Kluisbergen" },
    from_lat: 50.772006,
    from_lng: 3.669447,
  };
  const once = applyResolvedRouteAddressToBooking(base, {
    fromAddress: "Koekamerstraat 48A, 9688 Schorisse",
    fromSource: "mapbox_reverse_geocode",
    fromLat: 50.772006,
    fromLng: 3.669447,
    resolvedAt: "2026-08-03T05:00:00.000Z",
  });
  assert.equal(once.invoice_from_address, "Koekamerstraat 48A, 9688 Schorisse");
  assert.equal(once.invoice_from_address_source, "mapbox_reverse_geocode");
  assert.equal(once.route_address_snapshot.from_source, "mapbox_reverse_geocode");
  const twice = applyResolvedRouteAddressToBooking(once, {
    fromAddress: "SHOULD_NOT_OVERWRITE",
    fromSource: "mapbox_reverse_geocode",
  });
  assert.equal(twice.invoice_from_address, "Koekamerstraat 48A, 9688 Schorisse");
});

test("issued Document Core snapshot wins over mutable booking edits", () => {
  const issued = {
    route_address_snapshot: buildRouteAddressSnapshot({
      fromAddress: "Frozen Pickup 1",
      toAddress: "Frozen Dropoff 1",
      fromSource: "mapbox_reverse_geocode",
      resolvedAt: "2026-08-02T17:00:00.000Z",
    }),
  };
  const booking = {
    booking: {
      from: "99.0, 1.0",
      invoice_from_address: "Mutated after issue",
      to: "Mutated To",
    },
  };
  const resolved = resolveIssuedRouteAddressSnapshot(issued, booking);
  assert.equal(resolved.from, "Frozen Pickup 1");
  assert.equal(resolved.to, "Frozen Dropoff 1");
  assert.equal(resolved.source, "document_core_route_address_snapshot");
});

test("raw coordinates never returned as human address", () => {
  assert.equal(
    resolveHumanRouteAddress({ booking: { from: "50.1, 3.2", to: "3.2,50.1" } }, "from"),
    "",
  );
  assert.equal(
    resolveHumanRouteAddress({ booking: { from: "Straatrit" } }, "from"),
    "",
  );
});
