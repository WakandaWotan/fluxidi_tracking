/* Canonical seller identity for Belgian company invoicing profiles.
 *
 * Pure / side-effect free. Used by business-profile normalization, Document Core
 * seller_snapshot creation, and invoice PDF presentation.
 *
 * Rules:
 *  - Legal entrepreneur/entity name and trading name are separate.
 *  - Never invent "Fluxidi BV", "Fluxidi Taxi", or a legal form.
 *  - Never silently replace a stored legacy legalName with a default.
 *  - Sole proprietorship invoices fail closed without a legal entrepreneur.
 *  - Issued Document Core seller_snapshots are immutable (callers must not rewrite).
 */

import { safeStr, sanitizeTenantString } from "./parsing_utils.js";

export const LEGAL_FORM_EENMANSZAAK = "eenmanszaak";
export const LEGAL_FORM_SOLE_PROPRIETORSHIP = "sole_proprietorship";
export const LEGAL_FORM_BV = "bv";
export const LEGAL_FORM_NV = "nv";
export const LEGAL_FORM_VOF = "vof";
export const LEGAL_FORM_COMMV = "comm_v";

const SOLE_PROP_FORMS = new Set([
  LEGAL_FORM_EENMANSZAAK,
  LEGAL_FORM_SOLE_PROPRIETORSHIP,
  "sole_trader",
  "zelfstandige",
  "eenmanszaak_be",
]);

const COMPANY_FORMS = new Set([
  LEGAL_FORM_BV,
  "bvba",
  "besloten_vennootschap",
  LEGAL_FORM_NV,
  "sa",
  "nv_sa",
  LEGAL_FORM_VOF,
  LEGAL_FORM_COMMV,
  "cv",
  "cvba",
  "vzw",
  "asbl",
]);

function _norm(v, max = 240) {
  return sanitizeTenantString(v, max) || "";
}

function _lower(v) {
  return _norm(v).toLowerCase();
}

/** Normalize legal-form tokens; returns null when absent/unknown — never invents. */
export function normalizeLegalForm(value) {
  const raw = _lower(value).replace(/\s+/g, "_");
  if (!raw) return null;
  if (
    raw === "eenmanszaak" ||
    raw === "eenmanszaak_be" ||
    raw === "sole_proprietorship" ||
    raw === "sole_trader" ||
    raw === "zelfstandige" ||
    raw === "belgian_sole_proprietorship" ||
    raw === "belgian_sole_trader"
  ) {
    return LEGAL_FORM_EENMANSZAAK;
  }
  if (
    raw === "bv" ||
    raw === "bvba" ||
    raw === "besloten_vennootschap" ||
    raw === "besloten_vennootschap_met_beperkte_aansprakelijkheid"
  ) {
    return LEGAL_FORM_BV;
  }
  if (raw === "nv" || raw === "sa" || raw === "nv_sa") return LEGAL_FORM_NV;
  if (raw === "vof") return LEGAL_FORM_VOF;
  if (raw === "comm_v" || raw === "comm.v" || raw === "commv") {
    return LEGAL_FORM_COMMV;
  }
  if (COMPANY_FORMS.has(raw) || SOLE_PROP_FORMS.has(raw)) return raw;
  // Preserve unknown explicit tokens (bounded) rather than inventing.
  return raw.slice(0, 64) || null;
}

export function isSoleProprietorshipLegalForm(legalForm) {
  const form = normalizeLegalForm(legalForm);
  return !!form && SOLE_PROP_FORMS.has(form);
}

export function isCompanyLegalForm(legalForm) {
  const form = normalizeLegalForm(legalForm);
  return !!form && COMPANY_FORMS.has(form);
}

/** NL label for known forms only — never invents BV/eenmanszaak when form absent. */
export function legalFormLabelNl(legalForm) {
  const form = normalizeLegalForm(legalForm);
  if (!form) return "";
  if (form === LEGAL_FORM_EENMANSZAAK) return "Eenmanszaak";
  if (form === LEGAL_FORM_BV) return "BV";
  if (form === LEGAL_FORM_NV) return "NV";
  if (form === LEGAL_FORM_VOF) return "VOF";
  if (form === LEGAL_FORM_COMMV) return "Comm.V";
  return "";
}

/** Digits-only Belgian enterprise number (max 10). */
export function normalizeEnterpriseNumberDigits(value) {
  return _norm(value, 32).replace(/\D+/g, "").slice(0, 10);
}

/** Display 0772931038 → 0772.931.038 */
export function formatBelgianEnterpriseNumber(value) {
  const digits = normalizeEnterpriseNumberDigits(value);
  if (digits.length !== 10) return digits || "";
  return `${digits.slice(0, 4)}.${digits.slice(4, 7)}.${digits.slice(7)}`;
}

/** Display BE0772931038 → BE 0772.931.038 */
export function formatBelgianVatNumber(value) {
  const raw = _norm(value, 64).toUpperCase().replace(/\s+/g, "");
  if (!raw) return "";
  const digits = raw.replace(/\D+/g, "").slice(0, 10);
  if (raw.startsWith("BE") && digits.length === 10) {
    return `BE ${formatBelgianEnterpriseNumber(digits)}`;
  }
  if (digits.length === 10 && /^\d+$/.test(raw)) {
    return `BE ${formatBelgianEnterpriseNumber(digits)}`;
  }
  return raw;
}

export function normalizeBelgianVatNumber(value) {
  const raw = _norm(value, 64).toUpperCase().replace(/\s+/g, "");
  if (!raw) return "";
  const digits = raw.replace(/\D+/g, "").slice(0, 10);
  if (digits.length === 10) return `BE${digits}`;
  return raw;
}

/**
 * Extract additive seller-identity fields from a (possibly legacy) profile.
 * Does not invent legal names or legal forms.
 */
export function extractSellerIdentityFieldsFromProfile(profile = null) {
  const p = profile && typeof profile === "object" ? profile : {};
  const tradingName = _norm(
    p.trading_name ??
      p.tradingName ??
      p.companyName ??
      p.company_name,
    160,
  );
  const legalEntrepreneurName = _norm(
    p.legal_entrepreneur_name ??
      p.legalEntrepreneurName ??
      p.entrepreneur_name ??
      p.entrepreneurName ??
      p.owner_name ??
      p.ownerName,
    160,
  );
  const legacyLegalName = _norm(p.legalName ?? p.legal_name, 160);
  const legalForm = normalizeLegalForm(p.legal_form ?? p.legalForm);
  const enterpriseNumber = normalizeEnterpriseNumberDigits(
    p.enterprise_number ??
      p.enterpriseNumber ??
      p.kbo_number ??
      p.kboNumber ??
      p.company_registration_number ??
      p.companyRegistrationNumber,
  );
  const vatNumber = normalizeBelgianVatNumber(
    p.vat_number ?? p.vatNumber,
  );
  const addressIsVisitor = (() => {
    const v =
      p.address_is_visitor ??
      p.addressIsVisitor ??
      p.is_visitor_address ??
      p.isVisitorAddress;
    if (v === true || v === false) return v;
    const s = _lower(v);
    if (s === "true" || s === "1" || s === "yes") return true;
    if (s === "false" || s === "0" || s === "no") return false;
    return null;
  })();

  return {
    trading_name: tradingName,
    legal_entrepreneur_name: legalEntrepreneurName,
    legacy_legal_name: legacyLegalName,
    legal_form: legalForm,
    enterprise_number: enterpriseNumber,
    vat_number: vatNumber,
    address_line: _norm(p.address, 240),
    postal_code: _norm(p.postcode ?? p.postal_code ?? p.postalCode, 32),
    city: _norm(p.city, 120),
    country_code: _norm(p.country ?? p.country_code ?? p.countryCode, 8).toUpperCase(),
    invoice_email: _norm(
      p.invoice_email ??
        p.invoiceEmail ??
        p.billing_email ??
        p.billingEmail,
      240,
    ),
    address_is_visitor: addressIsVisitor,
    // Preserve legacy legalName verbatim for read-back (e.g. VC Construct).
    legal_name_raw: legacyLegalName,
    company_name_raw: _norm(p.companyName ?? p.company_name, 160),
  };
}

/**
 * Resolve the legal seller name without inventing defaults.
 * Sole prop: entrepreneur wins; legacy legalName used only when entrepreneur absent.
 * Trading name alone is never sufficient.
 */
export function resolveLegalSellerName(fields) {
  const f = fields && typeof fields === "object" ? fields : {};
  const entrepreneur = _norm(f.legal_entrepreneur_name, 160);
  const legacyLegal = _norm(f.legacy_legal_name || f.legal_name_raw, 160);
  const trading = _norm(f.trading_name || f.company_name_raw, 160);
  const form = normalizeLegalForm(f.legal_form);

  if (isSoleProprietorshipLegalForm(form)) {
    if (entrepreneur) return entrepreneur;
    // Legacy sole-prop profiles often only had legalName (person). Preserve it.
    if (legacyLegal && legacyLegal !== trading) return legacyLegal;
    if (legacyLegal) return legacyLegal;
    return "";
  }

  if (entrepreneur) return entrepreneur;
  if (legacyLegal) return legacyLegal;
  return "";
}

/**
 * Full canonical seller identity resolution + issuance readiness.
 */
export function resolveCanonicalSellerIdentity(profile = null, options = {}) {
  const fields = extractSellerIdentityFieldsFromProfile(profile);
  const legalSellerName = resolveLegalSellerName(fields);
  const tradingName = fields.trading_name;
  const form = fields.legal_form;
  const missing = [];

  if (!legalSellerName) missing.push("legal_entrepreneur_or_legal_name_missing");
  if (
    isSoleProprietorshipLegalForm(form) &&
    !fields.legal_entrepreneur_name &&
    !fields.legacy_legal_name
  ) {
    if (!missing.includes("legal_entrepreneur_or_legal_name_missing")) {
      missing.push("legal_entrepreneur_missing");
    }
  }
  // Trading name alone is never enough.
  if (!legalSellerName && tradingName) {
    if (!missing.includes("legal_entrepreneur_or_legal_name_missing")) {
      missing.push("trading_name_insufficient_as_legal_seller");
    }
  }
  if (!fields.vat_number && !fields.enterprise_number) {
    missing.push("vat_or_enterprise_number_missing");
  }

  const requireForIssue = options.requireForIssue === true;
  const ok = requireForIssue ? missing.length === 0 : true;

  return {
    ok: requireForIssue ? missing.length === 0 : true,
    ready_for_issue: missing.length === 0,
    error: requireForIssue && missing.length
      ? "seller_identity_incomplete"
      : null,
    missing_fields: missing,
    legal_entrepreneur_name:
      fields.legal_entrepreneur_name ||
      (isSoleProprietorshipLegalForm(form) ? legalSellerName : fields.legal_entrepreneur_name) ||
      "",
    trading_name: tradingName,
    legal_form: form,
    legal_form_label_nl: legalFormLabelNl(form),
    is_sole_proprietorship: isSoleProprietorshipLegalForm(form),
    is_company_form: isCompanyLegalForm(form),
    legal_seller_name: legalSellerName,
    enterprise_number: fields.enterprise_number,
    enterprise_number_display: formatBelgianEnterpriseNumber(fields.enterprise_number),
    vat_number: fields.vat_number,
    vat_number_display: formatBelgianVatNumber(fields.vat_number),
    address_line: fields.address_line,
    postal_code: fields.postal_code,
    city: fields.city,
    country_code: fields.country_code,
    address_is_visitor: fields.address_is_visitor,
    invoice_email: fields.invoice_email,
    // Legacy read-back (never overwritten by defaults in this helper).
    legacy_legal_name: fields.legacy_legal_name,
    company_name: fields.company_name_raw,
  };
}

/**
 * Build Document Core seller_snapshot from a business profile.
 * Call only for NEW issues — never rewrite an existing issued snapshot.
 */
export function buildSellerSnapshotFromBusinessProfile(profile = null) {
  const identity = resolveCanonicalSellerIdentity(profile, {
    requireForIssue: false,
  });
  return {
    name: identity.trading_name || null,
    trading_name: identity.trading_name || null,
    legal_name: identity.legal_seller_name || null,
    legal_entrepreneur_name:
      identity.legal_entrepreneur_name || identity.legal_seller_name || null,
    legal_form: identity.legal_form || null,
    legal_form_label_nl: identity.legal_form_label_nl || null,
    vat_number: identity.vat_number || null,
    registration_number: identity.enterprise_number || null,
    enterprise_number: identity.enterprise_number || null,
    email: identity.invoice_email || null,
    address_line: identity.address_line || null,
    postal_code: identity.postal_code || null,
    city: identity.city || null,
    country_code: identity.country_code || null,
    address_is_visitor:
      identity.address_is_visitor === null ? null : identity.address_is_visitor,
    // FLUXIDI-CANONICAL-COMPANY-LOGO-AND-INVOICE-PRESENTATION-P0-1:
    // freeze the company's own logo with the issued seller identity so a later
    // profile logo change never rewrites an already issued invoice.
    logo_url: sellerSnapshotLogoRefFromProfile(profile),
  };
}

/**
 * Canonical company logo reference for a seller snapshot.
 *
 * Only a company-owned reference is captured: a packaged Fluxidi asset means the
 * company has not set a logo, and theme artwork is never branding.
 */
export function sellerSnapshotLogoRefFromProfile(profile = null) {
  const p = profile && typeof profile === "object" ? profile : {};
  const raw = String(
    p.publicLogoUrl ??
      p.public_logo_url ??
      p.logoUrl ??
      p.logo_url ??
      "",
  ).trim();
  if (!raw) return null;
  const lower = raw.toLowerCase();
  if (lower.includes("fluxidi_logo.png")) return null;
  if (lower.startsWith("assets/")) return null;
  const usable =
    lower.startsWith("https://") ||
    lower.startsWith("http://") ||
    lower.startsWith("data:image/") ||
    lower.startsWith("/public/media/") ||
    lower.startsWith("public-media/");
  return usable ? raw.slice(0, 2000) : null;
}

export function validateSellerIdentityForInvoiceIssuance(profile = null) {
  const identity = resolveCanonicalSellerIdentity(profile, {
    requireForIssue: true,
  });
  if (identity.ready_for_issue) {
    return { ok: true, identity, error: null, missing_fields: [] };
  }
  return {
    ok: false,
    identity,
    error: "seller_identity_incomplete",
    missing_fields: identity.missing_fields,
    message:
      "Company invoicing profile is missing a required legal seller identity. Configure the legal entrepreneur (or legal entity name), VAT/enterprise number, and do not rely on a trading name alone.",
  };
}

/**
 * Tenant isolation guard when a profile embeds scope markers.
 */
export function assertSellerProfileScopeMatch(scope = null, profile = null) {
  const tenant = _norm(scope?.tenant_id ?? scope?.tenantId, 80);
  const company = _norm(scope?.company_id ?? scope?.companyId, 80);
  if (!tenant || !company) {
    return { ok: false, error: "missing_tenant_scope" };
  }
  const p = profile && typeof profile === "object" ? profile : {};
  const pTenant = _norm(p.tenant_id ?? p.tenantId, 80);
  const pCompany = _norm(p.company_id ?? p.companyId, 80);
  if (pTenant && pTenant !== tenant) {
    return { ok: false, error: "seller_profile_tenant_mismatch" };
  }
  if (pCompany && pCompany !== company) {
    return { ok: false, error: "seller_profile_company_mismatch" };
  }
  return { ok: true };
}

/**
 * Presentation lines for invoice HTML (NL). Never invents BV/form.
 */
export function formatSellerIdentityPresentationLines(identityOrSnapshot = null, {
  locale = "nl",
} = {}) {
  const s =
    identityOrSnapshot && typeof identityOrSnapshot === "object"
      ? identityOrSnapshot
      : {};
  const legal =
    _norm(
      s.legal_seller_name ??
        s.legal_entrepreneur_name ??
        s.legal_name ??
        s.legalName,
      160,
    );
  const trading = _norm(
    s.trading_name ?? s.tradingName ?? s.name ?? s.brandName,
    160,
  );
  const formLabel =
    _norm(s.legal_form_label_nl, 80) ||
    legalFormLabelNl(s.legal_form ?? s.legalForm);
  const enterpriseDisplay =
    _norm(s.enterprise_number_display, 40) ||
    formatBelgianEnterpriseNumber(
      s.enterprise_number ?? s.registration_number ?? s.registrationNumber,
    );
  const vatDisplay =
    _norm(s.vat_number_display, 48) ||
    formatBelgianVatNumber(s.vat_number ?? s.vatNumber);

  const lines = [];
  if (legal) lines.push(legal);
  if (trading && trading !== legal) {
    if (locale === "nl") {
      lines.push(`handelend onder de naam ${trading}`);
    } else {
      lines.push(`trading as ${trading}`);
    }
  } else if (trading && !legal) {
    // Should not happen for valid issues; still do not invent legal name.
    lines.push(trading);
  }
  if (formLabel) lines.push(formLabel);
  if (enterpriseDisplay) {
    lines.push(
      locale === "nl"
        ? `Ondernemingsnummer: ${enterpriseDisplay}`
        : `Enterprise number: ${enterpriseDisplay}`,
    );
  }
  if (vatDisplay) {
    lines.push(locale === "nl" ? `BTW: ${vatDisplay}` : `VAT: ${vatDisplay}`);
  }
  return lines;
}

/** Map canonical identity into communication-profile shaped seller fields. */
export function sellerIdentityToCommProfileFields(identity = null) {
  const id = identity && typeof identity === "object" ? identity : {};
  const addressParts = [
    _norm(id.address_line, 240),
    [_norm(id.postal_code, 32), _norm(id.city, 120)].filter(Boolean).join(" "),
    _norm(id.country_code, 8),
  ].filter(Boolean);
  return {
    brandName: _norm(id.trading_name, 160),
    legalName: _norm(id.legal_seller_name || id.legal_entrepreneur_name, 160),
    legalEntrepreneurName: _norm(
      id.legal_entrepreneur_name || id.legal_seller_name,
      160,
    ),
    tradingName: _norm(id.trading_name, 160),
    legalForm: id.legal_form || null,
    legalFormLabelNl: id.legal_form_label_nl || "",
    enterpriseNumber: _norm(id.enterprise_number, 32),
    enterpriseNumberDisplay: _norm(id.enterprise_number_display, 40),
    vatNumber: _norm(id.vat_number, 64),
    vatNumberDisplay: _norm(id.vat_number_display, 48),
    address: addressParts.join("\n"),
    invoiceEmail: _norm(id.invoice_email, 240),
    addressIsVisitor: id.address_is_visitor,
  };
}

/**
 * Detect unsafe invented identity tokens (for tests / guards).
 * Does not mutate profiles.
 */
export function isUnsafeInventedSellerLegalName(name) {
  const n = _lower(name);
  if (!n) return false;
  if (n === "fluxidi taxi") return true;
  if (n === "fluxidi bv") return true;
  if (n === "fluxidi besloten vennootschap") return true;
  return false;
}
