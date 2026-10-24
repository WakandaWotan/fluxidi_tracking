// Canonical published limousine identity.
// Working drafts never become the public source. Taxi company logo/hero
// are never written into the override or used as a cross-scope fallback.

import {
  looksLikeTaxiCompanyHero,
  looksLikeTaxiCompanyLogo,
} from "./limousine_public_visiting_card.mjs";

const LANGS = ["nl", "en", "fr", "es", "de"];
const ALIGNMENTS = new Set(["center", "top", "bottom", "left", "right"]);
const TITLE_MAX = 120;
const DESCRIPTION_MAX = 4000;
const URL_MAX = 600;

function asObject(raw) {
  return raw && typeof raw === "object" && !Array.isArray(raw) ? raw : {};
}

function httpsOnly(raw) {
  const text = String(raw ?? "").trim();
  return /^https:\/\//i.test(text) ? text.slice(0, URL_MAX) : "";
}

function scopeId(raw) {
  return String(raw ?? "").trim().slice(0, 80);
}

function localizedMap(raw, max) {
  const src = asObject(raw);
  const out = {};
  for (const lang of LANGS) {
    const text = String(src[lang] ?? "");
    const trimmed = text.trim();
    if (!trimmed) continue;
    out[lang] = text.slice(0, max);
  }
  return out;
}

function localizedHasText(map) {
  return Object.values(asObject(map)).some((value) => String(value || "").trim());
}

function sanitizeCoverUrl(url) {
  const href = httpsOnly(url);
  if (!href || looksLikeTaxiCompanyHero(href)) return "";
  return href;
}

function sanitizeLogoOverrideUrl(url) {
  const href = httpsOnly(url);
  if (!href || looksLikeTaxiCompanyHero(href) || looksLikeTaxiCompanyLogo(href)) {
    return "";
  }
  return href;
}

function coverMap(raw) {
  if (typeof raw === "string") {
    const photo_url = sanitizeCoverUrl(raw);
    return {
      photo_url,
      alignment: "center",
      source_kind: photo_url ? "upload" : "",
      media_id: "",
      source_revision: 0,
    };
  }
  const src = asObject(raw);
  const alignment = String(src.alignment ?? "center").trim().toLowerCase();
  return {
    photo_url: sanitizeCoverUrl(src.photo_url ?? src.photoUrl ?? src.url),
    alignment: ALIGNMENTS.has(alignment) ? alignment : "center",
    source_kind: String(src.source_kind ?? src.sourceKind ?? "").trim().slice(0, 32),
    media_id: String(src.media_id ?? src.mediaId ?? "").trim().slice(0, 120),
    source_revision: Number(src.source_revision ?? src.sourceRevision ?? 0) || 0,
  };
}

function logoMap(raw) {
  if (typeof raw === "string") {
    const photo_url = sanitizeLogoOverrideUrl(raw);
    return {
      photo_url,
      explicit_override: Boolean(photo_url),
      media_id: "",
      source_revision: 0,
    };
  }
  const src = asObject(raw);
  const photo_url = sanitizeLogoOverrideUrl(
    src.photo_url ?? src.photoUrl ?? src.url,
  );
  return {
    photo_url,
    explicit_override: photo_url
      ? true
      : src.explicit_override === true || src.explicitOverride === true,
    media_id: String(src.media_id ?? src.mediaId ?? "").trim().slice(0, 120),
    source_revision: Number(src.source_revision ?? src.sourceRevision ?? 0) || 0,
  };
}

function vehicleCopyById(raw) {
  const src = asObject(raw);
  const out = {};
  for (const [id, value] of Object.entries(src)) {
    const key = String(id || "").trim();
    if (!key) continue;
    const localized = localizedMap(value, 600);
    if (Object.keys(localized).length) out[key] = localized;
  }
  return out;
}

function publishedOnly(source, key, aliases = []) {
  const src = asObject(source);
  if (Object.prototype.hasOwnProperty.call(src, key)) return src[key];
  for (const alias of aliases) {
    if (Object.prototype.hasOwnProperty.call(src, alias)) return src[alias];
  }
  return undefined;
}

export function normalizePublishedLimousineIdentity(raw, options = {}) {
  const src = asObject(raw);
  const visiting = asObject(
    publishedOnly(src, "published_limousine_visiting_card", [
      "publishedLimousineVisitingCard",
    ]),
  );
  const title = localizedMap(
    publishedOnly(src, "published_public_title", ["publishedPublicTitle"]) ??
      visiting.public_title,
    TITLE_MAX,
  );
  const description = localizedMap(
    publishedOnly(src, "published_public_description", [
      "publishedPublicDescription",
    ]) ?? visiting.public_description,
    DESCRIPTION_MAX,
  );
  const cover = coverMap(
    publishedOnly(src, "published_limousine_profile_cover", [
      "publishedLimousineProfileCover",
      "published_limousine_hero",
      "publishedLimousineHero",
    ]) ?? visiting.cover,
  );
  const logo = logoMap(
    publishedOnly(src, "published_limousine_profile_logo", [
      "publishedLimousineProfileLogo",
      "published_limousine_logo",
      "publishedLimousineLogo",
    ]) ?? visiting.logo,
  );
  const vehicleCopy = vehicleCopyById(
    visiting.vehicle_public_copy ??
      publishedOnly(src, "published_limousine_vehicle_public_copy", [
        "publishedLimousineVehiclePublicCopy",
      ]),
  );
  const scope = asObject(options.scope);
  const tenantId = scopeId(options.tenant_id ?? src.tenant_id ?? scope.tenant_id);
  const companyId = scopeId(
    options.company_id ?? src.company_id ?? scope.company_id,
  );
  const partnerId = scopeId(
    options.partner_id ??
      src.partner_id ??
      scope.partner_id ??
      (tenantId && companyId ? `company:${tenantId}:${companyId}` : ""),
  );
  const hasContent =
    localizedHasText(title) ||
    localizedHasText(description) ||
    Boolean(cover.photo_url) ||
    Boolean(logo.photo_url) ||
    Object.keys(vehicleCopy).length > 0;
  const publishedAt = String(
    options.published_at ??
      src.limousine_published_at ??
      src.limousinePublishedAt ??
      "",
  ).trim() || (hasContent ? String(src.published_at ?? src.publishedAt ?? "").trim() : "");
  return {
    published_public_title: title,
    published_public_description: description,
    published_limousine_profile_cover: cover,
    published_limousine_hero: cover,
    published_limousine_profile_logo: logo,
    published_limousine_logo: logo,
    published_limousine_visiting_card: {
      public_title: title,
      public_description: description,
      cover,
      logo,
      ...(Object.keys(vehicleCopy).length
        ? { vehicle_public_copy: vehicleCopy }
        : {}),
    },
    ...(Object.keys(vehicleCopy).length
      ? { published_limousine_vehicle_public_copy: vehicleCopy }
      : {}),
    published_at: publishedAt,
    limousine_profile_cover_schema:
      Number(src.limousine_profile_cover_schema ?? 1) || 1,
    limousine_profile_logo_schema:
      Number(src.limousine_profile_logo_schema ?? 1) || 1,
    tenant_id: tenantId,
    company_id: companyId,
    partner_id: partnerId,
    has_published_content: hasContent,
  };
}

export function publishedLimousineIdentityHasContent(identity) {
  const src = asObject(identity);
  return (
    src.has_published_content === true ||
    localizedHasText(src.published_public_title) ||
    localizedHasText(src.published_public_description) ||
    Boolean(asObject(src.published_limousine_profile_cover).photo_url) ||
    Boolean(asObject(src.published_limousine_profile_logo).photo_url)
  );
}

export function mergePublishedLimousineIdentity(existingRaw, incomingRaw) {
  const existing = normalizePublishedLimousineIdentity(existingRaw);
  const incoming =
    incomingRaw && typeof incomingRaw === "object" && !Array.isArray(incomingRaw)
      ? incomingRaw
      : {};
  const keys = [
    ["published_public_title", "publishedPublicTitle"],
    ["published_public_description", "publishedPublicDescription"],
    [
      "published_limousine_profile_cover",
      "publishedLimousineProfileCover",
      "published_limousine_hero",
      "publishedLimousineHero",
    ],
    [
      "published_limousine_profile_logo",
      "publishedLimousineProfileLogo",
      "published_limousine_logo",
      "publishedLimousineLogo",
    ],
    ["published_limousine_visiting_card", "publishedLimousineVisitingCard"],
    [
      "published_limousine_vehicle_public_copy",
      "publishedLimousineVehiclePublicCopy",
    ],
    ["published_at", "publishedAt"],
  ];
  const merged = { ...incoming };
  for (const group of keys) {
    if (!group.some((key) => Object.prototype.hasOwnProperty.call(incoming, key))) {
      const keep = existing[group[0]];
      if (keep !== undefined) merged[group[0]] = keep;
    }
  }
  return normalizePublishedLimousineIdentity(merged, {
    tenant_id: existing.tenant_id,
    company_id: existing.company_id,
    partner_id: existing.partner_id,
    published_at: existing.published_at,
  });
}

export function publicPublishedLimousineIdentityFields(raw, options = {}) {
  const identity = normalizePublishedLimousineIdentity(raw, options);
  if (!publishedLimousineIdentityHasContent(identity)) {
    return {};
  }
  const out = {
    published_public_title: identity.published_public_title,
    published_public_description: identity.published_public_description,
    published_limousine_profile_cover: identity.published_limousine_profile_cover,
    published_limousine_hero: identity.published_limousine_hero,
    published_limousine_profile_logo: identity.published_limousine_profile_logo,
    published_limousine_logo: identity.published_limousine_logo,
    published_limousine_visiting_card: identity.published_limousine_visiting_card,
    limousine_profile_cover_schema: identity.limousine_profile_cover_schema,
    limousine_profile_logo_schema: identity.limousine_profile_logo_schema,
  };
  if (identity.published_at) out.published_at = identity.published_at;
  if (!options.publicSurface) {
    if (identity.tenant_id) out.tenant_id = identity.tenant_id;
    if (identity.company_id) out.company_id = identity.company_id;
    if (identity.partner_id) out.partner_id = identity.partner_id;
  }
  if (identity.published_limousine_vehicle_public_copy) {
    out.published_limousine_vehicle_public_copy =
      identity.published_limousine_vehicle_public_copy;
  }
  const coverUrl = identity.published_limousine_profile_cover.photo_url;
  if (coverUrl) {
    out.limousine_hero_url = coverUrl;
    out.limousine_hero_alignment = identity.published_limousine_profile_cover.alignment;
  }
  const logoUrl = identity.published_limousine_profile_logo.photo_url;
  if (logoUrl) out.limousine_logo_url = logoUrl;
  return out;
}

export function applyPublishedLimousineIdentityToProfile(profile, section, options = {}) {
  const base = profile && typeof profile === "object" ? { ...profile } : {};
  const publicFields = publicPublishedLimousineIdentityFields(section, {
    scope: options.scope,
    tenant_id: options.tenant_id ?? base.tenant_id,
    company_id: options.company_id ?? base.company_id,
    partner_id: options.partner_id ?? base.partner_id,
    published_at: options.published_at,
    publicSurface: options.publicSurface === true,
  });
  const media = asObject(base.media);
  const next = {
    ...base,
    ...publicFields,
  };
  if (Object.keys(media).length) {
    next.media = { ...media };
  }
  if (!publicFields.limousine_hero_url) {
    delete next.limousine_hero_url;
    delete next.limousine_hero_source;
    delete next.limousine_hero_alignment;
    delete next.limousine_hero_revision;
  }
  return next;
}

export function publishedLimousineIdentityDigest(raw) {
  const identity = normalizePublishedLimousineIdentity(raw);
  return JSON.stringify({
    title: identity.published_public_title,
    description: identity.published_public_description,
    cover: identity.published_limousine_profile_cover,
    logo: identity.published_limousine_profile_logo,
    published_at: identity.published_at,
    tenant_id: identity.tenant_id,
    company_id: identity.company_id,
    partner_id: identity.partner_id,
  });
}

export function identityScopeMatches(identity, scope) {
  const src = normalizePublishedLimousineIdentity(identity, { scope });
  const expected = asObject(scope);
  const tenant = scopeId(expected.tenant_id);
  const company = scopeId(expected.company_id);
  if (tenant && src.tenant_id && src.tenant_id !== tenant) return false;
  if (company && src.company_id && src.company_id !== company) return false;
  return true;
}
