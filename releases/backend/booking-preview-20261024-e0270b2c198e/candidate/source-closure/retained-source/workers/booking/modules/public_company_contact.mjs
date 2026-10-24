/**
 * Public company contact is opt-in.
 *
 * The primary `email` is the recovery login. It must not be shown on
 * /public/bootstrap, /public/book or /book unless a separate public address
 * was stored, or an already published partner profile carries an explicit
 * booking email.
 */

import { normalizeCompanyRecoveryEmail } from "./company_primary_email_recovery.mjs";

export function profileDeclaresPublicContactEmail(source) {
  if (!source || typeof source !== "object" || Array.isArray(source)) return false;
  return (
    Object.prototype.hasOwnProperty.call(source, "public_contact_email") ||
    Object.prototype.hasOwnProperty.call(source, "publicContactEmail")
  );
}

export function readExplicitPublicCompanyContactEmail(profile) {
  if (!profile || typeof profile !== "object" || Array.isArray(profile)) return "";
  return normalizeCompanyRecoveryEmail(
    profile.public_contact_email ?? profile.publicContactEmail,
  );
}

function publishedProfileIsVisible(profile) {
  if (!profile || typeof profile !== "object" || Array.isArray(profile)) return false;
  if (profile.profile_enabled !== true && profile.profileEnabled !== true) return false;
  if (profile.is_active !== true && profile.isActive !== true) return false;
  const subscription = String(
    profile.subscription_status ?? profile.subscriptionStatus ?? "",
  )
    .trim()
    .toLowerCase();
  return subscription === "active" || subscription === "valid";
}

/// Explicit booking email on a published partner profile. Never the recovery mail.
export function readPublishedPublicCompanyContactEmail(record) {
  const wrapped =
    record?.partner_profile && typeof record.partner_profile === "object"
      ? record.partner_profile
      : record;
  if (!publishedProfileIsVisible(wrapped)) return "";
  const contact = wrapped.public_contact ?? wrapped.publicContact;
  if (!contact || typeof contact !== "object" || Array.isArray(contact)) return "";
  return normalizeCompanyRecoveryEmail(contact.booking_email ?? contact.bookingEmail);
}

/**
 * Prefer the separate public address. Fall back only to a published profile's
 * own booking email. Recovery, company, support and notification mails are ignored.
 */
export function resolvePublicFacingCompanyEmail(businessProfile, publishedRecord) {
  const explicit = readExplicitPublicCompanyContactEmail(businessProfile);
  if (explicit) return explicit;
  return readPublishedPublicCompanyContactEmail(publishedRecord);
}

/// The recovery login must not be copied onto a public booking address.
/// An explicit public contact email is kept. A booking email that is only
/// the recovery address is cleared.
export function stripRecoveryEmailFromPublicContact(contact, recoveryEmail, publicEmail = "") {
  const source = contact && typeof contact === "object" && !Array.isArray(contact) ? contact : {};
  const recovery = normalizeCompanyRecoveryEmail(recoveryEmail);
  const booking = normalizeCompanyRecoveryEmail(source.booking_email ?? source.bookingEmail);
  const explicit = normalizeCompanyRecoveryEmail(publicEmail);
  if (!recovery || !booking || booking !== recovery) {
    return { ...source };
  }
  const replacement = explicit && explicit !== recovery ? explicit : "";
  return {
    ...source,
    booking_email: replacement,
    bookingEmail: replacement,
  };
}
