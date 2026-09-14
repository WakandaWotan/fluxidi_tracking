// Shared business-theme document on business_profile:v1.
// Same variant names as lib/business_theme_palette.dart.

const THEME_KEYS = [
  "business_theme",
  "business_theme_variant",
  "business_theme_updated_at",
  "published_customer_theme",
];

export function incomingHasBusinessTheme(incoming = {}) {
  const source = incoming && typeof incoming === "object" ? incoming : {};
  return THEME_KEYS.some((key) =>
    Object.prototype.hasOwnProperty.call(source, key),
  );
}

export function normalizeBusinessThemeDocument(input) {
  const source = input && typeof input === "object" ? input : {};
  const nested =
    source.business_theme && typeof source.business_theme === "object"
      ? source.business_theme
      : source;
  const variant = String(
    nested.variant ??
      nested.business_theme_variant ??
      source.business_theme_variant ??
      "",
  ).trim();
  const updatedAt = String(
    nested.updatedAt ??
      nested.updated_at ??
      source.business_theme_updated_at ??
      "",
  ).trim();
  const palette =
    nested.brandSignaturePalette &&
    typeof nested.brandSignaturePalette === "object"
      ? nested.brandSignaturePalette
      : nested.brand_signature_palette &&
          typeof nested.brand_signature_palette === "object"
        ? nested.brand_signature_palette
        : null;
  const publishedCustomerTheme = String(
    nested.publishedCustomerTheme ??
      nested.published_customer_theme ??
      source.published_customer_theme ??
      "",
  ).trim();
  if (!variant && !updatedAt && !palette && !publishedCustomerTheme) return null;
  return {
    variant,
    updatedAt,
    brandSignaturePalette: palette,
    publishedCustomerTheme,
  };
}

export function projectBusinessThemeFields(input) {
  const document = normalizeBusinessThemeDocument(input);
  if (!document) return {};
  return {
    business_theme: document,
    business_theme_variant: document.variant,
    business_theme_updated_at: document.updatedAt,
  };
}

export function preserveBusinessThemeFields(existingProfile, incomingProfile) {
  const existing =
    existingProfile && typeof existingProfile === "object" ? existingProfile : {};
  const incoming =
    incomingProfile && typeof incomingProfile === "object" ? incomingProfile : {};
  if (incomingHasBusinessTheme(incoming)) return incoming;
  const preserved = projectBusinessThemeFields(existing);
  if (!Object.keys(preserved).length) return incoming;
  return { ...incoming, ...preserved };
}
