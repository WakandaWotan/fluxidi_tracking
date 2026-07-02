/* Shared admin-auth + booking tenant/company scope helpers.
 * Moved verbatim from fluxidi_booking_worker.js (patch BW-M1), no behavior change.
 * Depends only on the pure safeStr helper to stay acyclic. */

import { safeStr } from "./parsing_utils.js";

export function _adminTokenFromRequest(request, url) {
  const h = (request.headers.get("x-admin-token") || "").trim();
  if (h) return h;
  const auth = request.headers.get("authorization") || "";
  const m = auth.match(/^Bearer\s+(.+)$/i);
  if (m && (m[1] || "").trim()) return m[1].trim();
  return "";
}

export function _requireAdmin(request, url, env) {
  const expected = (env.ADMIN_TOKEN || "").trim();
  if (!expected) throw new Error("ADMIN_TOKEN is not configured");
  const got = _adminTokenFromRequest(request, url);
  if (!got || got !== expected) throw new Error("Unauthorized");
}

export function _scopeText(value, maxLen = 80) {
  return safeStr(value, maxLen) || "";
}

export function missingTenantScopeError() {
  return { ok: false, error: "missing_tenant_scope" };
}

export function scopeConflictError() {
  return { ok: false, error: "tenant_scope_conflict" };
}

export function _scopeDistinctNonEmpty(...values) {
  const out = [];
  const seen = new Set();
  for (const value of values) {
    const text = _scopeText(value);
    if (!text || seen.has(text)) continue;
    seen.add(text);
    out.push(text);
  }
  return out;
}

export function resolveExplicitBookingRequestScope({ request, url, body = null, allowLegacyFallback = false } = {}) {
  const search = url?.searchParams;
  const tenantBodySnake = _scopeText(body?.tenant_id);
  const tenantBodyCamel = _scopeText(body?.tenantId);
  const companyBodySnake = _scopeText(body?.company_id);
  const companyBodyCamel = _scopeText(body?.companyId);
  const tenantQuerySnake = _scopeText(search?.get("tenant_id"));
  const tenantQueryCamel = _scopeText(search?.get("tenantId"));
  const companyQuerySnake = _scopeText(search?.get("company_id"));
  const companyQueryCamel = _scopeText(search?.get("companyId"));
  const tenantHeaderPrimary = _scopeText(request?.headers?.get?.("x-tenant-id"));
  const tenantHeaderAlias = _scopeText(request?.headers?.get?.("x-tenant"));
  const companyHeaderPrimary = _scopeText(request?.headers?.get?.("x-company-id"));
  const companyHeaderAlias = _scopeText(request?.headers?.get?.("x-company"));

  if (tenantBodySnake && tenantBodyCamel && tenantBodySnake !== tenantBodyCamel) return scopeConflictError();
  if (companyBodySnake && companyBodyCamel && companyBodySnake !== companyBodyCamel) return scopeConflictError();
  if (tenantQuerySnake && tenantQueryCamel && tenantQuerySnake !== tenantQueryCamel) return scopeConflictError();
  if (companyQuerySnake && companyQueryCamel && companyQuerySnake !== companyQueryCamel) return scopeConflictError();
  if (tenantHeaderPrimary && tenantHeaderAlias && tenantHeaderPrimary !== tenantHeaderAlias) return scopeConflictError();
  if (companyHeaderPrimary && companyHeaderAlias && companyHeaderPrimary !== companyHeaderAlias) return scopeConflictError();

  const tenantValues = _scopeDistinctNonEmpty(
    tenantBodySnake,
    tenantBodyCamel,
    tenantQuerySnake,
    tenantQueryCamel,
    tenantHeaderPrimary,
    tenantHeaderAlias,
  );
  const companyValues = _scopeDistinctNonEmpty(
    companyBodySnake,
    companyBodyCamel,
    companyQuerySnake,
    companyQueryCamel,
    companyHeaderPrimary,
    companyHeaderAlias,
  );
  if (tenantValues.length > 1 || companyValues.length > 1) {
    return scopeConflictError();
  }

  const tenantId = tenantValues[0] || "";
  const companyId = companyValues[0] || "";

  if (!tenantId && !companyId) {
    if (allowLegacyFallback) {
      return {
        tenant_id: "fluxidi",
        company_id: "fluxidi",
        hasScope: true,
        legacy_fallback: true,
      };
    }
    return missingTenantScopeError();
  }
  if (!tenantId || !companyId) return missingTenantScopeError();

  return {
    tenant_id: tenantId,
    company_id: companyId,
    hasScope: true,
  };
}

export function resolveBookingTenantScopeFromRecord(rec) {
  const booking = rec?.booking && typeof rec.booking === "object" ? rec.booking : null;
  const tenantId = _scopeText(
    rec?.tenant_id ??
      rec?.tenantId ??
      booking?.tenant_id ??
      booking?.tenantId ??
      rec?.company_id ??
      rec?.companyId ??
      booking?.company_id ??
      booking?.companyId,
  );
  const companyId = _scopeText(
    rec?.company_id ??
      rec?.companyId ??
      booking?.company_id ??
      booking?.companyId ??
      rec?.tenant_id ??
      rec?.tenantId ??
      booking?.tenant_id ??
      booking?.tenantId,
  );
  return {
    tenant_id: tenantId,
    company_id: companyId,
    hasScope: !!(tenantId || companyId),
  };
}

export function bookingMatchesRequiredTenantCompanyScope(rec, requestedScope) {
  const requestedTenant = _scopeText(requestedScope?.tenant_id);
  const requestedCompany = _scopeText(requestedScope?.company_id);
  if (!requestedTenant || !requestedCompany) return false;
  const recordScope = resolveBookingTenantScopeFromRecord(rec);
  const recordTenant = _scopeText(recordScope?.tenant_id);
  const recordCompany = _scopeText(recordScope?.company_id);
  if (!recordTenant || !recordCompany) return false;
  return requestedTenant === recordTenant && requestedCompany === recordCompany;
}
