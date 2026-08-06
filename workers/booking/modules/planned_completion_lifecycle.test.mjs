// NAV-PIP-PLANNED-COMPLETION-EVIDENCE-FIX-P0 — planned parent lifecycle.
//
// Run: node --test workers/booking/modules/planned_completion_lifecycle.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import {
  _projectionLifecycleStatusFromRecord,
  syncCanonicalParentLifecycleAliasesFromProjection,
  _flattenBookingForRidesList,
  _flattenBookingForRidesListWithOperationalLegs,
} from "./booking_read_model.js";

function oneWayCompletedLegsDisagreeStage() {
  return {
    booking_id: "2026-08-166",
    source: "planning",
    ride_type: "planned",
    status: "PENDING",
    stage: "PENDING",
    booking: {
      from: "A",
      to: "B",
      status: "PENDING",
      stage: "PENDING",
    },
    quote: { from: "A", to: "B", pricing: {} },
    operational_legs: [
      {
        leg_id: "2026-08-166:OUTBOUND",
        leg_type: "outbound",
        status: "COMPLETED",
        lifecycle_status: "completed",
        from: "A",
        to: "B",
      },
    ],
  };
}

function roundTripOutboundDoneReturnPending() {
  return {
    booking_id: "2026-08-200",
    source: "planning",
    ride_type: "planned",
    status: "PENDING",
    stage: "PENDING",
    booking: {
      from: "A",
      to: "B",
      status: "PENDING",
      stage: "PENDING",
      return_enabled: true,
    },
    quote: { from: "A", to: "B", pricing: {} },
    operational_legs: [
      {
        leg_id: "2026-08-200:OUTBOUND",
        leg_type: "outbound",
        status: "COMPLETED",
        lifecycle_status: "completed",
        from: "A",
        to: "B",
      },
      {
        leg_id: "2026-08-200:RETURN",
        leg_type: "return",
        status: "PENDING",
        lifecycle_status: "pending",
        from: "B",
        to: "A",
      },
    ],
  };
}

test("one-way outbound complete + zero open legs => projected COMPLETED", () => {
  const rec = oneWayCompletedLegsDisagreeStage();
  assert.equal(_projectionLifecycleStatusFromRecord(rec, "2026-08-166"), "COMPLETED");
});

test("one-way alias heal makes status and stage agree with projection", () => {
  const rec = oneWayCompletedLegsDisagreeStage();
  const first = syncCanonicalParentLifecycleAliasesFromProjection(rec, "2026-08-166");
  assert.equal(first.changed, true);
  assert.equal(first.projected, "COMPLETED");
  assert.equal(rec.status, "COMPLETED");
  assert.equal(rec.stage, "COMPLETED");
  assert.equal(rec.booking.status, "COMPLETED");
  assert.equal(rec.booking.stage, "COMPLETED");
  assert.ok(rec.completed_at);

  const second = syncCanonicalParentLifecycleAliasesFromProjection(rec, "2026-08-166");
  assert.equal(second.changed, false);
  assert.equal(_projectionLifecycleStatusFromRecord(rec, "2026-08-166"), "COMPLETED");
});

test("projected status and record.stage cannot disagree after heal", () => {
  const rec = oneWayCompletedLegsDisagreeStage();
  syncCanonicalParentLifecycleAliasesFromProjection(rec, "2026-08-166");
  const projected = _projectionLifecycleStatusFromRecord(rec, "2026-08-166");
  assert.equal(projected, "COMPLETED");
  assert.equal(rec.stage, projected);
  assert.equal(rec.status, projected);
});

test("one-way completed parent is absent from upcoming flatten rows", () => {
  const rec = oneWayCompletedLegsDisagreeStage();
  syncCanonicalParentLifecycleAliasesFromProjection(rec, "2026-08-166");
  const row = _flattenBookingForRidesList("2026-08-166", rec);
  assert.equal(row.status, "COMPLETED");
  const isUpcoming = row.status !== "COMPLETED" && row.status !== "CANCELLED";
  assert.equal(isUpcoming, false);
});

test("round trip outbound complete + return pending => parent remains upcoming for return only", () => {
  const rec = roundTripOutboundDoneReturnPending();
  assert.equal(_projectionLifecycleStatusFromRecord(rec, "2026-08-200"), "PENDING");
  const heal = syncCanonicalParentLifecycleAliasesFromProjection(rec, "2026-08-200");
  assert.equal(heal.changed, false);
  assert.equal(rec.stage, "PENDING");
  const rows = _flattenBookingForRidesListWithOperationalLegs("2026-08-200", rec);
  const openRows = rows.filter(
    (r) => r.status !== "COMPLETED" && r.status !== "CANCELLED",
  );
  assert.ok(openRows.length >= 1, "return leg must remain visible/upcoming");
  assert.ok(
    openRows.some(
      (r) =>
        String(r.leg_type || r.legType || "").toLowerCase() === "return" ||
        String(r.leg_id || r.legId || "").includes("RETURN"),
    ),
    "open row must be the return leg",
  );
});

test("repeated STOP/reconcile alias heal remains idempotent", () => {
  const rec = oneWayCompletedLegsDisagreeStage();
  const a = syncCanonicalParentLifecycleAliasesFromProjection(rec, "2026-08-166");
  const b = syncCanonicalParentLifecycleAliasesFromProjection(rec, "2026-08-166");
  const c = syncCanonicalParentLifecycleAliasesFromProjection(rec, "2026-08-166");
  assert.equal(a.changed, true);
  assert.equal(b.changed, false);
  assert.equal(c.changed, false);
  assert.equal(rec.completed_at, a.projected === "COMPLETED" ? rec.completed_at : null);
  const completedAt = rec.completed_at;
  syncCanonicalParentLifecycleAliasesFromProjection(rec, "2026-08-166");
  assert.equal(rec.completed_at, completedAt);
});

test("dashboard next-ride open check cannot select a completed parent after heal", () => {
  const rec = oneWayCompletedLegsDisagreeStage();
  // Before heal: projection already COMPLETED even while stage is PENDING.
  assert.equal(_projectionLifecycleStatusFromRecord(rec, "2026-08-166"), "COMPLETED");
  syncCanonicalParentLifecycleAliasesFromProjection(rec, "2026-08-166");
  const projected = _projectionLifecycleStatusFromRecord(rec, "2026-08-166");
  const openCandidate =
    projected !== "COMPLETED" && projected !== "CANCELLED";
  assert.equal(openCandidate, false);
});
