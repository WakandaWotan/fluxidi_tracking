/**
 * Canonical company recovery identity for Booking `business_profile:v1`.
 *
 * Only the confirmed (or bounded-legacy) primary `email` may recover a company.
 * Support, billing, invoice, booking, notification, owner and login mails are
 * never recovery candidates. An email change writes `pending_email` first; the
 * previous primary mail stays the recovery identity until the pending address
 * is confirmed through the existing company-recovery challenge.
 */

export const COMPANY_EMAIL_STATUS_VERIFIED = "verified";
export const COMPANY_EMAIL_STATUS_LEGACY_UNVERIFIED = "legacy_unverified";
export const COMPANY_EMAIL_STATUS_PENDING = "pending_confirmation";
export const COMPANY_EMAIL_CHALLENGE_PURPOSE_RECOVERY = "company_recovery";
export const COMPANY_EMAIL_CHALLENGE_PURPOSE_PENDING = "pending_email_confirm";

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export function normalizeCompanyRecoveryEmail(value) {
  const email = String(value == null ? "" : value)
    .replace(/\0/g, "")
    .trim()
    .toLowerCase();
  if (!email || email.length > 240 || !EMAIL_RE.test(email)) return "";
  return email;
}

export function normalizeCompanyEmailVerificationStatus(value) {
  const raw = String(value == null ? "" : value)
    .trim()
    .toLowerCase();
  if (raw === COMPANY_EMAIL_STATUS_VERIFIED) return COMPANY_EMAIL_STATUS_VERIFIED;
  if (raw === COMPANY_EMAIL_STATUS_LEGACY_UNVERIFIED) {
    return COMPANY_EMAIL_STATUS_LEGACY_UNVERIFIED;
  }
  if (raw === COMPANY_EMAIL_STATUS_PENDING) return COMPANY_EMAIL_STATUS_PENDING;
  return "";
}

function readPrimaryEmail(profile) {
  if (!profile || typeof profile !== "object" || Array.isArray(profile)) return "";
  return normalizeCompanyRecoveryEmail(profile.email);
}

function readPendingEmail(profile) {
  if (!profile || typeof profile !== "object" || Array.isArray(profile)) return "";
  return normalizeCompanyRecoveryEmail(
    profile.pending_email ?? profile.pendingEmail,
  );
}

function readStatus(profile) {
  if (!profile || typeof profile !== "object" || Array.isArray(profile)) return "";
  return normalizeCompanyEmailVerificationStatus(
    profile.email_verification_status ?? profile.emailVerificationStatus,
  );
}

function readRevision(profile) {
  if (!profile || typeof profile !== "object" || Array.isArray(profile)) return 0;
  const raw = Number(profile.email_revision ?? profile.emailRevision ?? 0);
  return Number.isFinite(raw) ? Math.max(0, Math.round(raw)) : 0;
}

/**
 * Compatibility: an existing primary mail without verification proof stays
 * recoverable as `legacy_unverified`. It is never auto-promoted to verified.
 */
export function resolveLegacyCompanyEmailStatus(profile) {
  const email = readPrimaryEmail(profile);
  const status = readStatus(profile);
  if (!email) return "";
  if (status === COMPANY_EMAIL_STATUS_VERIFIED) return COMPANY_EMAIL_STATUS_VERIFIED;
  if (status === COMPANY_EMAIL_STATUS_PENDING) return COMPANY_EMAIL_STATUS_PENDING;
  return COMPANY_EMAIL_STATUS_LEGACY_UNVERIFIED;
}

/**
 * Recovery candidates: only the current primary mail when it is verified or
 * bounded-legacy. Pending and every other route are excluded.
 */
export function collectPrimaryCompanyRecoveryEmails(businessProfile) {
  const email = readPrimaryEmail(businessProfile);
  if (!email) return [];
  const status = resolveLegacyCompanyEmailStatus(businessProfile);
  if (
    status === COMPANY_EMAIL_STATUS_VERIFIED ||
    status === COMPANY_EMAIL_STATUS_LEGACY_UNVERIFIED
  ) {
    return [email];
  }
  return [];
}

export function isPrimaryCompanyRecoveryEmail(businessProfile, email) {
  const normalized = normalizeCompanyRecoveryEmail(email);
  if (!normalized) return false;
  return collectPrimaryCompanyRecoveryEmails(businessProfile).includes(normalized);
}

export function isPendingCompanyEmailConfirmTarget(businessProfile, email) {
  const pending = readPendingEmail(businessProfile);
  const normalized = normalizeCompanyRecoveryEmail(email);
  return !!pending && !!normalized && pending === normalized;
}

/**
 * Apply a requested primary-email write. Clients cannot set verification
 * fields; those stay server-owned.
 */
export function applyPrimaryCompanyEmailChange(existingProfile, incomingProfile, nowIso) {
  const existing = existingProfile && typeof existingProfile === "object"
    ? existingProfile
    : {};
  const incoming = incomingProfile && typeof incomingProfile === "object"
    ? incomingProfile
    : {};
  const now = String(nowIso || new Date().toISOString());
  const existingEmail = readPrimaryEmail(existing);
  const requestedEmail = normalizeCompanyRecoveryEmail(incoming.email);
  const existingPending = readPendingEmail(existing);
  const existingStatus = resolveLegacyCompanyEmailStatus(existing);
  const existingVerifiedAt = String(
    existing.email_verified_at ?? existing.emailVerifiedAt ?? "",
  ).trim();
  let revision = readRevision(existing);

  let email = existingEmail;
  let pending = existingPending;
  let status = existingEmail
    ? existingStatus || COMPANY_EMAIL_STATUS_LEGACY_UNVERIFIED
    : "";
  let verifiedAt = existingVerifiedAt;
  let pendingRequestedAt = String(
    existing.pending_email_requested_at ?? existing.pendingEmailRequestedAt ?? "",
  ).trim();
  let audit = existing.email_audit ?? existing.emailAudit ?? null;
  let issuePendingChallenge = false;

  if (!existingEmail && requestedEmail) {
    email = requestedEmail;
    status = COMPANY_EMAIL_STATUS_LEGACY_UNVERIFIED;
    pending = "";
    pendingRequestedAt = "";
    revision += 1;
    audit = {
      event: "legacy_primary_seeded",
      at: now,
      email,
    };
  } else if (existingEmail && requestedEmail && requestedEmail !== existingEmail) {
    email = existingEmail;
    status = existingStatus || COMPANY_EMAIL_STATUS_LEGACY_UNVERIFIED;
    if (requestedEmail !== existingPending) {
      pending = requestedEmail;
      pendingRequestedAt = now;
      revision += 1;
      audit = {
        event: "pending_email_requested",
        at: now,
        from: existingEmail,
        to: requestedEmail,
      };
    }
    issuePendingChallenge = true;
  }

  const out = { ...incoming };
  out.email = email;
  out.pending_email = pending;
  out.pendingEmail = pending;
  out.email_verification_status = status;
  out.emailVerificationStatus = status;
  out.email_verified_at = verifiedAt;
  out.emailVerifiedAt = verifiedAt;
  out.pending_email_requested_at = pendingRequestedAt;
  out.pendingEmailRequestedAt = pendingRequestedAt;
  out.email_revision = revision;
  out.emailRevision = revision;
  out.email_audit = audit;
  out.emailAudit = audit;
  return {
    profile: out,
    issuePendingChallenge,
    pendingEmail: pending,
    email,
  };
}

export function promotePendingCompanyEmail(existingProfile, confirmedEmail, nowIso) {
  const existing = existingProfile && typeof existingProfile === "object"
    ? existingProfile
    : {};
  const now = String(nowIso || new Date().toISOString());
  const pending = readPendingEmail(existing);
  const confirmed = normalizeCompanyRecoveryEmail(confirmedEmail);
  if (!pending || !confirmed || pending !== confirmed) {
    return { ok: false, profile: existing, reason: "pending_mismatch" };
  }
  const revision = readRevision(existing) + 1;
  const audit = {
    event: "pending_email_verified",
    at: now,
    from: readPrimaryEmail(existing),
    to: confirmed,
  };
  const out = { ...existing };
  out.email = confirmed;
  out.pending_email = "";
  out.pendingEmail = "";
  out.email_verification_status = COMPANY_EMAIL_STATUS_VERIFIED;
  out.emailVerificationStatus = COMPANY_EMAIL_STATUS_VERIFIED;
  out.email_verified_at = now;
  out.emailVerifiedAt = now;
  out.pending_email_requested_at = "";
  out.pendingEmailRequestedAt = "";
  out.email_revision = revision;
  out.emailRevision = revision;
  out.email_audit = audit;
  out.emailAudit = audit;
  return { ok: true, profile: out };
}

export function markPrimaryCompanyEmailVerified(existingProfile, confirmedEmail, nowIso) {
  const existing = existingProfile && typeof existingProfile === "object"
    ? existingProfile
    : {};
  const now = String(nowIso || new Date().toISOString());
  const current = readPrimaryEmail(existing);
  const confirmed = normalizeCompanyRecoveryEmail(confirmedEmail);
  if (!current || !confirmed || current !== confirmed) {
    return { ok: false, profile: existing, reason: "email_mismatch" };
  }
  const revision = readRevision(existing) + 1;
  const audit = {
    event: "legacy_primary_verified",
    at: now,
    email: confirmed,
  };
  const out = { ...existing };
  out.email = current;
  out.email_verification_status = COMPANY_EMAIL_STATUS_VERIFIED;
  out.emailVerificationStatus = COMPANY_EMAIL_STATUS_VERIFIED;
  out.email_verified_at = now;
  out.emailVerifiedAt = now;
  out.email_revision = revision;
  out.emailRevision = revision;
  out.email_audit = audit;
  out.emailAudit = audit;
  return { ok: true, profile: out };
}

export function projectCompanyEmailIdentityFields(source = {}) {
  const email = readPrimaryEmail(source);
  const pending = readPendingEmail(source);
  const status = email
    ? resolveLegacyCompanyEmailStatus(source)
    : normalizeCompanyEmailVerificationStatus(
        source.email_verification_status ?? source.emailVerificationStatus,
      );
  const verifiedAt = String(
    source.email_verified_at ?? source.emailVerifiedAt ?? "",
  ).trim();
  const pendingRequestedAt = String(
    source.pending_email_requested_at ?? source.pendingEmailRequestedAt ?? "",
  ).trim();
  const revision = readRevision(source);
  const audit = source.email_audit ?? source.emailAudit ?? null;
  return {
    pending_email: pending,
    pendingEmail: pending,
    email_verification_status: status,
    emailVerificationStatus: status,
    email_verified_at: verifiedAt,
    emailVerifiedAt: verifiedAt,
    pending_email_requested_at: pendingRequestedAt,
    pendingEmailRequestedAt: pendingRequestedAt,
    email_revision: revision,
    emailRevision: revision,
    email_audit: audit,
    emailAudit: audit,
  };
}
