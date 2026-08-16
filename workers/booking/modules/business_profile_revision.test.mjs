// BUSINESS-PROFILE-SOURCE-REVISION-P0 (unit)
//
// Run:
//   node --test workers/booking/modules/business_profile_revision.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import {
  businessProfileRevisionFloor,
  businessProfileSemanticFingerprint,
  resolveBusinessProfileRevision,
  stampBusinessProfileRecord,
  toMonotonicInt,
} from "./business_profile_revision.mjs";

const NOW = "2026-08-16T12:00:00.000Z";
const LATER = "2026-08-16T13:00:00.000Z";

// Mirrors the proven live FLX-00001 record: source_revision=null, version=1,
// email_revision=2, active primary mail verified.
function legacyRecord(profileOverrides = {}) {
  return {
    version: 1,
    updated_at: "2026-08-16T11:06:34.789Z",
    // no source_revision at all (null in production)
    business_profile: {
      companyName: "Fluxidi",
      email: "cvanrokeghem@outlook.com",
      phone: "+3211223344",
      vat_number: "BE0123456789",
      email_verification_status: "verified",
      email_revision: 2,
      email_verified_at: "2026-08-16T11:05:53.823Z",
      ...profileOverrides,
    },
  };
}

test("toMonotonicInt coerces null/invalid to 0 and keeps positives", () => {
  assert.equal(toMonotonicInt(null), 0);
  assert.equal(toMonotonicInt(undefined), 0);
  assert.equal(toMonotonicInt("nope"), 0);
  assert.equal(toMonotonicInt(-4), 0);
  assert.equal(toMonotonicInt(2.9), 2);
  assert.equal(toMonotonicInt(7), 7);
});

test("floor is strictly above existing source_revision, version and email_revision", () => {
  const record = legacyRecord();
  const profile = record.business_profile;
  // max(source_revision=0, version=1, email_revision=2) = 2
  assert.equal(businessProfileRevisionFloor(record, profile), 2);

  const higher = {
    version: 1,
    source_revision: 9,
    business_profile: { email_revision: 4 },
  };
  assert.equal(businessProfileRevisionFloor(higher, higher.business_profile), 9);
});

test("legacy record's next semantic change yields a revision above email_revision (>2)", () => {
  const record = legacyRecord();
  const existingProfile = record.business_profile;
  const nextProfile = { ...existingProfile, companyName: "Fluxidi Taxi" };
  const result = resolveBusinessProfileRevision({
    existingRecord: record,
    existingProfile,
    nextProfile,
    nowIso: NOW,
  });
  assert.equal(result.changed, true);
  assert.equal(result.source_revision, 3);
  assert.ok(result.source_revision > 2);
  assert.equal(result.updated_at, NOW);
});

test("name / phone / vat changes each advance the same monotone revision", () => {
  let record = stampBusinessProfileRecord({
    profile: legacyRecord().business_profile,
    sourceRevision: 3,
    updatedAt: NOW,
  }).record;

  const nameChange = resolveBusinessProfileRevision({
    existingRecord: record,
    existingProfile: record.business_profile,
    nextProfile: { ...record.business_profile, companyName: "New Name" },
    nowIso: LATER,
  });
  assert.equal(nameChange.source_revision, 4);

  record = stampBusinessProfileRecord({
    profile: { ...record.business_profile, companyName: "New Name" },
    sourceRevision: nameChange.source_revision,
    updatedAt: LATER,
  }).record;
  const phoneChange = resolveBusinessProfileRevision({
    existingRecord: record,
    existingProfile: record.business_profile,
    nextProfile: { ...record.business_profile, phone: "+3299887766" },
    nowIso: LATER,
  });
  assert.equal(phoneChange.source_revision, 5);

  record = stampBusinessProfileRecord({
    profile: { ...record.business_profile, phone: "+3299887766" },
    sourceRevision: phoneChange.source_revision,
    updatedAt: LATER,
  }).record;
  const vatChange = resolveBusinessProfileRevision({
    existingRecord: record,
    existingProfile: record.business_profile,
    nextProfile: { ...record.business_profile, vat_number: "BE0999888777" },
    nowIso: LATER,
  });
  assert.equal(vatChange.source_revision, 6);
});

test("idempotent replay keeps revision and updated_at", () => {
  const stamped = stampBusinessProfileRecord({
    profile: legacyRecord().business_profile,
    sourceRevision: 3,
    updatedAt: NOW,
  });
  const replay = resolveBusinessProfileRevision({
    existingRecord: stamped.record,
    existingProfile: stamped.profile,
    nextProfile: { ...stamped.profile },
    nowIso: LATER,
  });
  assert.equal(replay.changed, false);
  assert.equal(replay.source_revision, 3);
  assert.equal(replay.updated_at, NOW);
});

test("revision markers never count as a semantic change", () => {
  const base = legacyRecord().business_profile;
  const withMarkers = { ...base, source_revision: 99, sourceRevision: 99 };
  assert.equal(
    businessProfileSemanticFingerprint(base),
    businessProfileSemanticFingerprint(withMarkers),
  );
});

test("legacy record with no revision establishes a baseline even on identical content", () => {
  const record = legacyRecord();
  const result = resolveBusinessProfileRevision({
    existingRecord: record,
    existingProfile: record.business_profile,
    nextProfile: { ...record.business_profile },
    nowIso: NOW,
  });
  // No prior source_revision -> baseline must be established (never left null).
  assert.equal(result.changed, true);
  assert.equal(result.source_revision, 3);
});

test("stamp mirrors the revision on wrapper and profile and keeps version=1", () => {
  const stamped = stampBusinessProfileRecord({
    profile: { companyName: "Fluxidi" },
    sourceRevision: 5,
    updatedAt: NOW,
  });
  assert.equal(stamped.record.version, 1);
  assert.equal(stamped.record.source_revision, 5);
  assert.equal(stamped.record.updated_at, NOW);
  assert.equal(stamped.record.business_profile.source_revision, 5);
  assert.equal(stamped.record.business_profile.sourceRevision, 5);
  assert.equal(stamped.profile.source_revision, 5);
});

test("a client-supplied inflated source_revision cannot lower or freeze the series", () => {
  // Even if a prior stored record claims a large source_revision, a real change
  // must still strictly exceed it (monotone, server-owned).
  const record = {
    version: 1,
    source_revision: 40,
    business_profile: { companyName: "Fluxidi", email_revision: 2 },
  };
  const result = resolveBusinessProfileRevision({
    existingRecord: record,
    existingProfile: record.business_profile,
    nextProfile: { ...record.business_profile, companyName: "Changed" },
    nowIso: NOW,
  });
  assert.equal(result.source_revision, 41);
});
