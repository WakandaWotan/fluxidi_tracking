// Public limousine vehicle media. Additive fields only.
// photo_url stays for taxi/airport compatibility. Gallery is HTTPS-only.

export const LIMOUSINE_PUBLIC_GALLERY_MAX = 10;
export const LIMOUSINE_PUBLIC_GALLERY_RECOMMENDED = 5;

export const LIMOUSINE_PUBLIC_MEDIA_FORBIDDEN = Object.freeze([
  "tenant_id",
  "company_id",
  "license_plate",
  "vin",
  "operating_base",
  "upload_token",
  "r2_key",
  "object_key",
  "file://",
  "content://",
]);

function httpsOnly(raw, safeHttpsUrl) {
  if (typeof safeHttpsUrl === "function") {
    return String(safeHttpsUrl(raw) || "").trim();
  }
  const text = String(raw || "").trim();
  return text.toLowerCase().startsWith("https://") ? text : "";
}

function collectGalleryCandidates(row) {
  const out = [];
  for (const key of ["gallery_photo_urls", "galleryPhotoUrls", "gallery", "photos"]) {
    const raw = row?.[key];
    if (!Array.isArray(raw)) continue;
    for (const item of raw) out.push(item);
  }
  return out;
}

export function normalizePublicVehicleGallery(row, safeHttpsUrl) {
  const src = row && typeof row === "object" ? row : {};
  const primary = httpsOnly(
    src.primary_photo_url ??
      src.primaryPhotoUrl ??
      src.photo_url ??
      src.photoUrl ??
      src.public_photo_url ??
      src.publicPhotoUrl,
    safeHttpsUrl,
  );
  const urls = [];
  const seen = new Set();
  const push = (value) => {
    const url = httpsOnly(value, safeHttpsUrl);
    if (!url || seen.has(url) || urls.length >= LIMOUSINE_PUBLIC_GALLERY_MAX) {
      return;
    }
    seen.add(url);
    urls.push(url);
  };
  push(primary);
  for (const item of collectGalleryCandidates(src)) push(item);
  const first = urls[0] || "";
  return {
    photo_url: first,
    primary_photo_url: first,
    gallery_photo_urls: urls,
  };
}

export function publicVehicleMediaLeaksPrivate(value) {
  const text = JSON.stringify(value || {}).toLowerCase();
  return LIMOUSINE_PUBLIC_MEDIA_FORBIDDEN.some((token) => text.includes(token));
}

export function attachPublicVehicleMediaFields({
  serviceCategory,
  media,
  fallbackPhotoUrl = "",
}) {
  const isLimousine = String(serviceCategory || "").trim().toLowerCase() === "limousine";
  if (!isLimousine) {
    return { photo_url: fallbackPhotoUrl || "" };
  }
  return {
    photo_url: media?.photo_url || "",
    ...(media?.primary_photo_url ? { primary_photo_url: media.primary_photo_url } : {}),
    ...(Array.isArray(media?.gallery_photo_urls) && media.gallery_photo_urls.length
      ? { gallery_photo_urls: media.gallery_photo_urls }
      : {}),
  };
}
