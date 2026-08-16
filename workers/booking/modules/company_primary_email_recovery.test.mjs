// COMPANY-PRIMARY-EMAIL-RECOVERY-P0
//
// Run:
//   node --test workers/booking/modules/company_primary_email_recovery.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import {
  applyPrimaryCompanyEmailChange,
  collectPrimaryCompanyRecoveryEmails,
  isPendingCompanyEmailConfirmTarget,
  isPrimaryCompanyRecoveryEmail,
  markPrimaryCompanyEmailVerified,
  promotePendingCompanyEmail,
  resolveLegacyCompanyEmailStatus,
} from "./company_primary_email_recovery.mjs";

const NOW = "2026-08-16T09:00:00.000Z";

function profile(overrides = {}) {
  return {
    email: "contact@fluxidi.com",
    companyEmail: "route@fluxidi.com",
    supportEmail: "info@fluxidi.com",
    billingEmail: "billing@fluxidi.com",
    invoiceEmail: "invoice@fluxidi.com",
    bookingEmail: "fluxidi.booking@gmail.com",
    notificationEmail: "notify@fluxidi.com",
    ownerEmail: "owner@fluxidi.com",
    ...overrides,
  };
}

test("only the primary confirmed/legacy mail is a recovery candidate", () => {
  const legacy = profile();
  assert.deepEqual(collectPrimaryCompanyRecoveryEmails(legacy), [
    "contact@fluxidi.com",
  ]);
  assert.equal(resolveLegacyCompanyEmailStatus(legacy), "legacy_unverified");
  assert.equal(isPrimaryCompanyRecoveryEmail(legacy, "contact@fluxidi.com"), true);
  assert.equal(isPrimaryCompanyRecoveryEmail(legacy, "info@fluxidi.com"), false);
  assert.equal(isPrimaryCompanyRecoveryEmail(legacy, "billing@fluxidi.com"), false);
  assert.equal(isPrimaryCompanyRecoveryEmail(legacy, "invoice@fluxidi.com"), false);
  assert.equal(
    isPrimaryCompanyRecoveryEmail(legacy, "fluxidi.booking@gmail.com"),
    false,
  );
  assert.equal(isPrimaryCompanyRecoveryEmail(legacy, "notify@fluxidi.com"), false);
  assert.equal(isPrimaryCompanyRecoveryEmail(legacy, "owner@fluxidi.com"), false);
  assert.equal(isPrimaryCompanyRecoveryEmail(legacy, "route@fluxidi.com"), false);
});

test("email change writes pending and keeps the old recovery mail", () => {
  const existing = profile({
    email_verification_status: "legacy_unverified",
  });
  const applied = applyPrimaryCompanyEmailChange(
    existing,
    { ...existing, email: "new-contact@fluxidi.com" },
    NOW,
  );
  assert.equal(applied.email, "contact@fluxidi.com");
  assert.equal(applied.pendingEmail, "new-contact@fluxidi.com");
  assert.equal(applied.issuePendingChallenge, true);
  assert.deepEqual(collectPrimaryCompanyRecoveryEmails(applied.profile), [
    "contact@fluxidi.com",
  ]);
  assert.equal(
    isPendingCompanyEmailConfirmTarget(applied.profile, "new-contact@fluxidi.com"),
    true,
  );
  assert.equal(
    isPrimaryCompanyRecoveryEmail(applied.profile, "new-contact@fluxidi.com"),
    false,
  );
});

test("pending mail becomes primary only after confirmation", () => {
  const pending = applyPrimaryCompanyEmailChange(
    profile({ email_verification_status: "legacy_unverified" }),
    profile({ email: "new-contact@fluxidi.com" }),
    NOW,
  ).profile;
  const promoted = promotePendingCompanyEmail(
    pending,
    "new-contact@fluxidi.com",
    NOW,
  );
  assert.equal(promoted.ok, true);
  assert.equal(promoted.profile.email, "new-contact@fluxidi.com");
  assert.equal(promoted.profile.pending_email, "");
  assert.equal(promoted.profile.email_verification_status, "verified");
  assert.equal(promoted.profile.email_verified_at, NOW);
  assert.equal(promoted.profile.email_revision > 0, true);
  assert.deepEqual(collectPrimaryCompanyRecoveryEmails(promoted.profile), [
    "new-contact@fluxidi.com",
  ]);
});

test("legacy account stays recoverable until a successful challenge", () => {
  const legacy = profile();
  assert.equal(resolveLegacyCompanyEmailStatus(legacy), "legacy_unverified");
  assert.equal(isPrimaryCompanyRecoveryEmail(legacy, "contact@fluxidi.com"), true);
  const verified = markPrimaryCompanyEmailVerified(
    legacy,
    "contact@fluxidi.com",
    NOW,
  );
  assert.equal(verified.ok, true);
  assert.equal(verified.profile.email_verification_status, "verified");
  assert.equal(verified.profile.email, "contact@fluxidi.com");
});

test("clients cannot self-verify by posting verified status", () => {
  const existing = profile({ email_verification_status: "legacy_unverified" });
  const applied = applyPrimaryCompanyEmailChange(
    existing,
    {
      ...existing,
      email: "contact@fluxidi.com",
      email_verification_status: "verified",
      email_verified_at: NOW,
    },
    NOW,
  );
  assert.equal(applied.profile.email_verification_status, "legacy_unverified");
  assert.equal(applied.profile.email_verified_at, "");
});
