// Public limousine visiting-card projection.
// Title, description, profile cover and optional logo override only.
// Never copies the taxi hero or writes the company logo into the override.

const TAXI_HERO_PATH = /\/company\/hero(?:\.|$)/i;
const TAXI_LOGO_PATH = /\/company\/logo(?:\.|$)/i;

function asObject(raw) {
  return raw && typeof raw === "object" && !Array.isArray(raw) ? raw : {};
}

function httpsOnly(raw) {
  const text = String(raw ?? "").trim();
  return /^https:\/\//i.test(text) ? text.slice(0, 600) : "";
}

function mediaPath(url) {
  try {
    const parsed = new URL(url);
    return decodeURIComponent(parsed.pathname || "").toLowerCase();
  } catch (_) {
    return String(url || "").toLowerCase();
  }
}

export function looksLikeTaxiCompanyHero(url) {
  const path = mediaPath(url);
  return TAXI_HERO_PATH.test(path);
}

export function looksLikeTaxiCompanyLogo(url) {
  const path = mediaPath(url);
  return TAXI_LOGO_PATH.test(path);
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

function localizedMap(raw, max = 400) {
  const src = asObject(raw);
  const out = {};
  for (const lang of ["nl", "en", "fr", "es", "de"]) {
    const text = String(src[lang] ?? "").trim();
    if (text) out[lang] = text.slice(0, max);
  }
  return out;
}

function coverMap(raw) {
  if (typeof raw === "string") {
    const photo_url = sanitizeCoverUrl(raw);
    return { photo_url, alignment: "center" };
  }
  const src = asObject(raw);
  return {
    photo_url: sanitizeCoverUrl(src.photo_url ?? src.photoUrl),
    source_kind: String(src.source_kind ?? src.sourceKind ?? "").trim().slice(0, 32),
    alignment: String(src.alignment ?? "center").trim().slice(0, 16) || "center",
    source_revision: Number(src.source_revision ?? src.sourceRevision ?? 0) || 0,
  };
}

function logoMap(raw) {
  if (typeof raw === "string") {
    const photo_url = sanitizeLogoOverrideUrl(raw);
    return { photo_url, explicit_override: Boolean(photo_url) };
  }
  const src = asObject(raw);
  const photo_url = sanitizeLogoOverrideUrl(src.photo_url ?? src.photoUrl ?? src.url);
  return {
    photo_url,
    source_revision: Number(src.source_revision ?? src.sourceRevision ?? 0) || 0,
    explicit_override: Boolean(photo_url),
  };
}

function pickPublished(source, publishedKey, liveKey) {
  const src = asObject(source);
  if (Object.prototype.hasOwnProperty.call(src, publishedKey)) return src[publishedKey];
  return src[liveKey];
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

export function publishedLimousineVehiclePublicCopy(source) {
  const src = asObject(source);
  const visiting = asObject(
    src.published_limousine_visiting_card ?? src.publishedLimousineVisitingCard,
  );
  return vehicleCopyById(
    visiting.vehicle_public_copy ??
      src.published_limousine_vehicle_public_copy ??
      src.publishedLimousineVehiclePublicCopy,
  );
}

export function effectiveLimousineLogoUrl(overrideUrl, companyLogoUrl) {
  const override = sanitizeLogoOverrideUrl(overrideUrl);
  if (override) return override;
  const company = httpsOnly(companyLogoUrl);
  if (!company || looksLikeTaxiCompanyHero(company)) return "";
  return company;
}

/// Atomic published snapshot for nearby / public profile.
/// Draft working copies are ignored when published_* keys exist.
export function buildLimousinePublicVisitingCard(source, { companyLogoUrl = "" } = {}) {
  const src = asObject(source);
  const visiting = asObject(
    src.published_limousine_visiting_card ?? src.publishedLimousineVisitingCard,
  );
  const title = localizedMap(
    visiting.public_title ?? pickPublished(src, "published_public_title", "public_title"),
    120,
  );
  const description = localizedMap(
    visiting.public_description ??
      pickPublished(src, "published_public_description", "public_description"),
    400,
  );
  const cover = coverMap(
    visiting.cover ??
      src.published_limousine_profile_cover ??
      src.published_limousine_hero ??
      src.limousine_profile_cover ??
      src.limousine_hero ??
      src.limousine_hero_url,
  );
  const logo = logoMap(
    visiting.logo ??
      src.published_limousine_profile_logo ??
      src.published_limousine_logo ??
      src.limousine_profile_logo,
  );
  const companyLogo = httpsOnly(
    companyLogoUrl || src.logo_url || src.logoUrl || asObject(src.media).logo_url,
  );
  const effectiveLogo = effectiveLimousineLogoUrl(logo.photo_url, companyLogo);
  const out = {
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
    },
  };
  if (cover.photo_url) {
    out.limousine_hero_url = cover.photo_url;
    out.limousine_hero_alignment = cover.alignment;
  }
  if (effectiveLogo) out.limousine_logo_url = effectiveLogo;
  const publishedCopy = publishedLimousineVehiclePublicCopy(src);
  if (Object.keys(publishedCopy).length) {
    out.published_limousine_vehicle_public_copy = publishedCopy;
  }
  return out;
}

export function logoFallbackMutatesOverride(workingLogo, companyLogoUrl) {
  const stored = sanitizeLogoOverrideUrl(asObject(workingLogo).photo_url);
  const company = httpsOnly(companyLogoUrl);
  if (!stored || !company) return false;
  return mediaPath(stored) === mediaPath(company);
}
