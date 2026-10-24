// Isolated customer-app header display mode.
//
// MERGE (one agent, after tariffs + header are both ready):
// 1. In normalizeBusinessProfile, spread projectCustomerAppHeaderFields(source).
// 2. Add GET/POST /admin/business/customer-app-header using
//    applyCustomerAppHeaderMode(existing, mode) then saveBusinessProfile.
//    Do not accept or rewrite a full business_profile body.
// 3. In handlePublicCompanyResolve, add projectPublicCustomerAppHeader(profile).
// 4. Do not publish the public partner profile from this write.
// 5. Do not use FLX-00028 as a bookable partner id.
//
// Do not edit fluxidi_booking_worker.js while the tariffs agent is writing it.

export const CUSTOMER_APP_HEADER_MODE_LOGO = "logo";
export const CUSTOMER_APP_HEADER_MODE_COVER = "header_image";
export const CUSTOMER_APP_HEADER_MODE_BOTH = "header_and_logo";
export const CUSTOMER_APP_HEADER_MODE_FIELD = "customer_app_header_mode";
export const CUSTOMER_APP_HEADER_LOGO_POS_LEFT = "top_left";
export const CUSTOMER_APP_HEADER_LOGO_POS_RIGHT = "top_right";
export const CUSTOMER_APP_HEADER_LOGO_POS_FIELD =
  "customer_app_header_logo_position";
export const CUSTOMER_APP_HEADER_MEDIA_REVISION_FIELD =
  "customer_app_header_media_revision";
export const DRIVER_APP_USE_COMPANY_HEADER_FIELD =
  "driver_app_use_company_header";
export const BUSINESS_APP_USE_COMPANY_HEADER_FIELD =
  "business_app_use_company_header";

export function readBusinessAppUseCompanyHeader(source = {}) {
  const src = source && typeof source === "object" ? source : {};
  const has =
    Object.prototype.hasOwnProperty.call(src, BUSINESS_APP_USE_COMPANY_HEADER_FIELD) ||
    Object.prototype.hasOwnProperty.call(src, "businessAppUseCompanyHeader");
  if (!has) return undefined;
  const raw = src[BUSINESS_APP_USE_COMPANY_HEADER_FIELD] ?? src.businessAppUseCompanyHeader;
  return raw === true || raw === "true" || raw === 1 || raw === "1";
}

export function readDriverAppUseCompanyHeader(source = {}) {
  const src = source && typeof source === "object" ? source : {};
  const has =
    Object.prototype.hasOwnProperty.call(src, "driver_app_use_company_header") ||
    Object.prototype.hasOwnProperty.call(src, "driverAppUseCompanyHeader");
  if (!has) return undefined;
  const raw = src.driver_app_use_company_header ?? src.driverAppUseCompanyHeader;
  return raw === true || raw === "true" || raw === 1 || raw === "1";
}

export function normalizeCustomerAppHeaderMode(raw) {
  const value = String(raw ?? "")
    .trim()
    .toLowerCase()
    .replace(/-/g, "_");
  if (
    value === CUSTOMER_APP_HEADER_MODE_COVER ||
    value === "cover" ||
    value === "cover_only" ||
    value === "header" ||
    value === "header_only" ||
    value === "headerimage"
  ) {
    return CUSTOMER_APP_HEADER_MODE_COVER;
  }
  if (
    value === CUSTOMER_APP_HEADER_MODE_BOTH ||
    value === "cover_and_logo" ||
    value === "header+logo" ||
    value === "header_logo" ||
    value === "both"
  ) {
    return CUSTOMER_APP_HEADER_MODE_BOTH;
  }
  return CUSTOMER_APP_HEADER_MODE_LOGO;
}

export function normalizeCustomerAppHeaderLogoPosition(raw) {
  const value = String(raw ?? "")
    .trim()
    .toLowerCase()
    .replace(/-/g, "_");
  if (
    value === CUSTOMER_APP_HEADER_LOGO_POS_RIGHT ||
    value === "right" ||
    value === "topright" ||
    value === "rechtsboven"
  ) {
    return CUSTOMER_APP_HEADER_LOGO_POS_RIGHT;
  }
  return CUSTOMER_APP_HEADER_LOGO_POS_LEFT;
}

export function projectCustomerAppHeaderFields(source = {}) {
  const src = source && typeof source === "object" ? source : {};
  const mode = normalizeCustomerAppHeaderMode(
    src.customer_app_header_mode ?? src.customerAppHeaderMode,
  );
  const logoPosition = normalizeCustomerAppHeaderLogoPosition(
    src.customer_app_header_logo_position ?? src.customerAppHeaderLogoPosition,
  );
  const revision = String(
    src.customer_app_header_media_revision ??
      src.customerAppHeaderMediaRevision ??
      "",
  ).trim();
  const projected = {
    customer_app_header_mode: mode,
    customerAppHeaderMode: mode,
    customer_app_header_logo_position: logoPosition,
    customerAppHeaderLogoPosition: logoPosition,
    customer_app_header_media_revision: revision,
    customerAppHeaderMediaRevision: revision,
  };
  const useOnDriver = readDriverAppUseCompanyHeader(src);
  if (useOnDriver !== undefined) {
    projected.driver_app_use_company_header = useOnDriver;
    projected.driverAppUseCompanyHeader = useOnDriver;
  }
  const useOnBusiness = readBusinessAppUseCompanyHeader(src);
  if (useOnBusiness !== undefined) {
    projected.business_app_use_company_header = useOnBusiness;
    projected.businessAppUseCompanyHeader = useOnBusiness;
  }
  return projected;
}

export function applyCustomerAppHeaderSettings(
  existing,
  { mode, logoPosition, useOnDriverApp, useOnBusinessApp } = {},
) {
  const current = existing && typeof existing === "object" ? existing : {};
  const projected = projectCustomerAppHeaderFields({
    ...current,
    ...(mode != null ? { customer_app_header_mode: mode } : {}),
    ...(logoPosition != null
      ? { customer_app_header_logo_position: logoPosition }
      : {}),
  });
  if (useOnDriverApp === undefined) {
    const kept = readDriverAppUseCompanyHeader(current);
    if (kept !== undefined) {
      projected.driver_app_use_company_header = kept;
      projected.driverAppUseCompanyHeader = kept;
    } else {
      delete projected.driver_app_use_company_header;
      delete projected.driverAppUseCompanyHeader;
    }
  } else {
    const enabled = useOnDriverApp === true;
    projected.driver_app_use_company_header = enabled;
    projected.driverAppUseCompanyHeader = enabled;
  }
  if (useOnBusinessApp === undefined) {
    const kept = readBusinessAppUseCompanyHeader(current);
    if (kept !== undefined) {
      projected.business_app_use_company_header = kept;
      projected.businessAppUseCompanyHeader = kept;
    } else {
      delete projected.business_app_use_company_header;
      delete projected.businessAppUseCompanyHeader;
    }
  } else {
    const enabled = useOnBusinessApp === true;
    projected.business_app_use_company_header = enabled;
    projected.businessAppUseCompanyHeader = enabled;
  }
  return {
    ...current,
    ...projected,
  };
}

export function applyCustomerAppHeaderMode(existing, rawMode) {
  return applyCustomerAppHeaderSettings(existing, { mode: rawMode });
}

export function incrementCustomerAppHeaderMediaRevision(existing) {
  const current = existing && typeof existing === "object" ? existing : {};
  const prev = parseInt(
    String(
      current.customer_app_header_media_revision ??
        current.customerAppHeaderMediaRevision ??
        "0",
    ).trim(),
    10,
  );
  const next = Number.isFinite(prev) && prev > 0 ? prev + 1 : 1;
  return {
    ...current,
    customer_app_header_media_revision: String(next),
    customerAppHeaderMediaRevision: String(next),
  };
}

function _https(value) {
  const text = String(value ?? "").trim();
  if (!text.toLowerCase().startsWith("https://")) return "";
  if (text.toLowerCase().includes("fluxidi_logo")) return "";
  return text.slice(0, 600);
}

export function projectPublicCustomerAppHeader(profile = {}) {
  const src = profile && typeof profile === "object" ? profile : {};
  const fields = projectCustomerAppHeaderFields(src);
  const logo = _https(src.publicLogoUrl ?? src.public_logo_url ?? src.logo_url);
  const cover = _https(
    src.publicHeroPhotoUrl ??
      src.public_hero_photo_url ??
      src.cover_url ??
      src.hero_photo_url,
  );
  return {
    customer_app_header_mode: fields.customer_app_header_mode,
    customer_app_header_logo_position: fields.customer_app_header_logo_position,
    customer_app_header_media_revision: fields.customer_app_header_media_revision,
    driver_app_use_company_header: readDriverAppUseCompanyHeader(src) === true,
    business_app_use_company_header: readBusinessAppUseCompanyHeader(src) === true,
    logo_url: logo,
    public_logo_url: logo,
    cover_url: cover,
    public_hero_photo_url: cover,
  };
}

export function parseCustomerAppHeaderSettingsBody(body) {
  const src = body && typeof body === "object" ? body : {};
  if (
    src.business_profile &&
    typeof src.business_profile === "object" &&
    Object.keys(src.business_profile).length > 2
  ) {
    return { ok: false, error: "full_business_profile_not_allowed" };
  }
  const raw = src.customer_app_header_mode ?? src.customerAppHeaderMode;
  if (raw == null || String(raw).trim() === "") {
    return { ok: false, error: "customer_app_header_mode_required" };
  }
  const parsed = {
    ok: true,
    mode: normalizeCustomerAppHeaderMode(raw),
    logoPosition: normalizeCustomerAppHeaderLogoPosition(
      src.customer_app_header_logo_position ?? src.customerAppHeaderLogoPosition,
    ),
  };
  const useOnDriver = readDriverAppUseCompanyHeader(src);
  if (useOnDriver !== undefined) parsed.useOnDriverApp = useOnDriver;
  const useOnBusiness = readBusinessAppUseCompanyHeader(src);
  if (useOnBusiness !== undefined) parsed.useOnBusinessApp = useOnBusiness;
  return parsed;
}
