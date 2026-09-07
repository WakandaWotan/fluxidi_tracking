import {
  COMPANY_REGISTRY_MANIFEST_KEY,
  registryCodeKey,
  registryPageKey,
  registryTombstoneKey,
} from "../../modules/company_registry_index.mjs";

export function companyLinkCodeKey(companyCode) {
  return `company_link:index:code:${companyCode}:v1`;
}

export function companyLinkScopeKey(tenantId, companyId) {
  if (!tenantId || !companyId) return null;
  return `company_link:index:scope:${tenantId}:${companyId}:v1`;
}

export function companyDriverActiveLinkKey(companyCode) {
  return `company_driver_link:active:${companyCode}:v1`;
}

export function scopedKeys(tenantId, companyId) {
  if (!tenantId || !companyId) return [];
  const p = `tenant:${tenantId}:company:${companyId}`;
  return [
    `${p}:business_profile:v1`,
    `${p}:tax_profile:v1`,
    `${p}:pricing:v1`,
    `${p}:subscription:v1`,
    `${p}:cancellation_policy:v1`,
    `${p}:airport_fixed_fares:v1`,
    `${p}:communication_templates:v1`,
    `${p}:partner:profile:v1`,
    `${p}:partner:directory_projection:v1`,
    `${p}:partner:booking_route:v1`,
    `${p}:drivers:index:v1`,
    `${p}:fleet:vehicles:v1`,
    `${p}:bookings:list:v1`,
    `${p}:booking_index`,
    `${p}:chiron_connection:v1`,
    `${p}:mollie_connect_auth:v1`,
    `${p}:integration:mollie:status:v1`,
    `${p}:mollie_terminals:v1`,
    `${p}:mollie_terminals:test:v1`,
    `${p}:google_calendar_auth:v1`,
    `${p}:ratings:company:v1`,
    `${p}:dashboard:bookings_kpis:v1`,
    `${p}:dashboard:trip_kpis:v1`,
    `${p}:booking:demand:index:v1`,
    `${p}:booking:demand:repair_marker:v1`,
  ];
}

export function billitOauthKey(tenantId, companyId) {
  if (!tenantId || !companyId) return null;
  return `integration:billit:oauth:${tenantId}:${companyId}`;
}

export function registryKeysForCode(companyCode) {
  return {
    code: registryCodeKey(companyCode),
    tombstone: registryTombstoneKey(companyCode),
    manifest: COMPANY_REGISTRY_MANIFEST_KEY,
    page1: registryPageKey(1),
  };
}

export function bookingRecordKey(bookingId) {
  return `booking:${bookingId}`;
}

export function companyLogoR2Key(tenantId, companyId) {
  if (!tenantId || !companyId) return null;
  return `public-media/${tenantId}/${companyId}/company/logo.png`;
}

export {
  COMPANY_REGISTRY_MANIFEST_KEY,
  registryCodeKey,
  registryPageKey,
  registryTombstoneKey,
};
