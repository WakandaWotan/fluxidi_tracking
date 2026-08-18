// LIMOUSINE-MARKETPLACE-P2A — projection + monotonic revision contract tests.
// Run: node --test workers/booking/modules/limousine_projection.test.mjs

import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import {
  buildLimousineProjection,
  limousineProjectionFingerprint,
  resolveLimousineProjectionRevision,
  stampLimousineProjectionOnProfile,
} from "./limousine_projection.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));

function readyProfile(overrides = {}) {
  return {
    partner_id: "cmp_x",
    company_name: "Coachline",
    is_active: true,
    availability_status: "active",
    bookable: true,
    profile_enabled: true,
    published_at: "2026-08-17T10:00:00Z",
    subscription_status: "active",
    limousine_entitled: true,
    services: ["limousine"],
    vehicles: [
      { service_category: "limousine", service_class: "executive_sedan", is_active: true },
    ],
    ...overrides,
  };
}

test("projection reports safe readiness fields only", () => {
  const projection = buildLimousineProjection(readyProfile());
  assert.deepEqual(Object.keys(projection).sort(), [
    "eligible_vehicle_count",
    "limousine_available",
    "limousine_service_enabled",
    "reason",
  ]);
  assert.equal(projection.limousine_available, true);
  assert.equal(projection.limousine_service_enabled, true);
  assert.equal(projection.eligible_vehicle_count, 1);
  assert.equal(projection.reason, "eligible");
});

test("21) projection has no subscription-private / customer-private fields", () => {
  const projection = buildLimousineProjection(readyProfile());
  const json = JSON.stringify(projection);
  for (const forbidden of ["price", "plan", "billing", "email", "customer", "driver", "vat", "features"]) {
    assert.ok(!new RegExp(forbidden, "i").test(json), forbidden);
  }
});

test("revocation flips availability off in the projection", () => {
  const revoked = buildLimousineProjection(readyProfile({ limousine_entitled: false }));
  assert.equal(revoked.limousine_available, false);
  assert.equal(revoked.reason, "not_entitled");
});

test("16/17) monotonic: unchanged fingerprint => idempotent replay (no bump)", () => {
  const profile = readyProfile();
  const projection = buildLimousineProjection(profile);
  const stamped = stampLimousineProjectionOnProfile({
    profile,
    entitled: true,
    projection,
    sourceRevision: 5,
  });
  const record = { source_revision: 5, partner_profile: stamped };
  const again = resolveLimousineProjectionRevision({
    existingRecord: record,
    existingProfile: stamped,
    nextProjection: buildLimousineProjection(stamped),
    entitled: true,
  });
  assert.equal(again.changed, false);
  assert.equal(again.source_revision, 5);
});

test("19) newer valid change bumps revision strictly above the floor", () => {
  const profile = readyProfile();
  const stamped = stampLimousineProjectionOnProfile({
    profile,
    entitled: true,
    projection: buildLimousineProjection(profile),
    sourceRevision: 5,
  });
  const record = { source_revision: 5, partner_profile: stamped };
  // entitlement revoked => projection changes => bump
  const revokedProjection = buildLimousineProjection(
    readyProfile({ limousine_entitled: false }),
  );
  const bumped = resolveLimousineProjectionRevision({
    existingRecord: record,
    existingProfile: stamped,
    nextProjection: revokedProjection,
    entitled: false,
  });
  assert.equal(bumped.changed, true);
  assert.equal(bumped.source_revision, 6);
});

test("18) contradictory equal revision cannot escalate (floor strictly exceeded)", () => {
  // A stale record claiming revision 10 but a newer real change must jump to 11,
  // never reuse 10; an equal-revision contradictory write can never overwrite.
  const profile = readyProfile();
  const stampedHigh = stampLimousineProjectionOnProfile({
    profile,
    entitled: true,
    projection: buildLimousineProjection(profile),
    sourceRevision: 10,
  });
  const record = { source_revision: 10, partner_profile: stampedHigh };
  const changed = resolveLimousineProjectionRevision({
    existingRecord: record,
    existingProfile: stampedHigh,
    nextProjection: buildLimousineProjection(readyProfile({ services: ["taxi_vvb"] })),
    entitled: true,
  });
  assert.equal(changed.changed, true);
  assert.ok(changed.source_revision > 10, "must strictly exceed the floor");
});

test("fingerprint distinguishes entitlement and availability", () => {
  const a = limousineProjectionFingerprint(
    { limousine_service_enabled: true, limousine_available: true, eligible_vehicle_count: 1, reason: "eligible" },
    true,
  );
  const b = limousineProjectionFingerprint(
    { limousine_service_enabled: true, limousine_available: false, eligible_vehicle_count: 0, reason: "not_entitled" },
    false,
  );
  assert.notEqual(a, b);
});

test("stamp mirrors revision on record + projection, never mutates input", () => {
  const profile = readyProfile();
  const stamped = stampLimousineProjectionOnProfile({
    profile,
    entitled: true,
    projection: buildLimousineProjection(profile),
    sourceRevision: 7,
  });
  assert.equal(stamped.source_revision, 7);
  assert.equal(stamped.limousine_projection.source_revision, 7);
  assert.equal(stamped.limousine_entitled, true);
  assert.equal(profile.source_revision, undefined, "input not mutated");
});

test("12/13/14/15) worker wires refresh into subscription + fleet, stamps publish", () => {
  const workerSource = readFileSync(join(__dirname, "..", "fluxidi_booking_worker.js"), "utf8");
  assert.ok(workerSource.includes("async function refreshPartnerLimousineProjection"), "refresh helper defined");
  // subscription writer triggers refresh (revoke/restore/suspend/cancel)
  assert.ok(/saveSubscriptionProfile[\s\S]*?refreshPartnerLimousineProjection\(env, scope\)/.test(workerSource), "subscription save refreshes");
  // fleet POST triggers refresh
  assert.ok(/\/admin\/fleet\/vehicles[\s\S]*?refreshPartnerLimousineProjection\(env, scope\)/.test(workerSource), "fleet POST refreshes");
  // publish stamps monotonic projection revision
  assert.ok(workerSource.includes("_resolveLimousineProjectionRevision({"), "publish resolves projection revision");
  assert.ok(workerSource.includes("_stampLimousineProjectionOnProfile({"), "publish stamps projection");
  // normalization preserves the projection + revision through re-reads
  assert.ok(workerSource.includes("limousine_projection: {"), "normalization preserves projection");
});
