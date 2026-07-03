/* Chiron admin-config bridge to the Compliance worker.
 * Moved verbatim from fluxidi_booking_worker.js (patch BW-M5), no behavior change.
 *
 * BW-M5 LITE scope: only the read-only path constants + the config/connection
 * proxy live here. Compliance event builders, marker persistence, and lifecycle
 * orchestrators all read/write booking/payment record shapes and STAY in main
 * to avoid a circular import with booking-core helpers.
 *
 * The Booking→Compliance service binding (env.COMPLIANCE_WORKER) is the only
 * transport used here; the proxy path list is closed and validated per call.
 * Admin token is read from env at call time; NEVER logged/returned.
 */

import { safeStr, sanitizeTenantString } from "./parsing_utils.js";
import { json } from "./http_response.js";
import { missingTenantScopeError } from "./auth_scope.js";

/* Closed allowlist of admin Chiron paths that the booking worker will proxy to
 * the compliance worker. Kept as constants so the proxy validator can enforce
 * exact matches. Any other path is rejected with 400 invalid_compliance_proxy_path. */
export const CHIRON_CONFIG_STATUS_PATH = "/admin/chiron/config/status";
export const CHIRON_CONFIG_TEST_CREDENTIALS_PATH = "/admin/chiron/config/test-credentials";
export const CHIRON_CONFIG_TEST_CREDENTIALS_CLEAR_PATH =
  "/admin/chiron/config/test-credentials/clear";
export const CHIRON_CONNECTION_TEST_PATH = "/admin/chiron/connection/test";

/* Marker header value so the compliance worker knows this request came via the
 * booking worker's internal proxy (as opposed to a direct admin call). */
export const CHIRON_INTERNAL_PROXY_MODE = "booking_worker_v1";

/* Proxy a Chiron admin-config request to the compliance worker over the
 * COMPLIANCE_WORKER service binding. GET status + POST config/test-credentials/
 * connection-test/clear are the only allowed paths. Explicit tenant/company
 * scope is required and is forwarded as both query params and x-fluxidi-proxy-*
 * headers. The compliance admin token is forwarded only via the internal
 * x-fluxidi-proxy-token header; it is NEVER logged or returned in the response.
 * Returns a Response with the compliance worker's status + content-type and a
 * no-store cache-control header. Any error surfaces as a safe json() envelope. */
export async function _proxyChironConfigStatusToComplianceWorker(env, explicitScope, options = {}) {
  const adminToken = safeStr(env?.COMPLIANCE_ADMIN_TOKEN || env?.ADMIN_TOKEN);
  if (!adminToken) {
    return json({ ok: false, error: "compliance_auth_not_configured" }, 503);
  }
  if (!env?.COMPLIANCE_WORKER || typeof env.COMPLIANCE_WORKER.fetch !== "function") {
    return json({ ok: false, error: "compliance_worker_binding_missing" }, 500);
  }

  const tenantId = sanitizeTenantString(explicitScope?.tenant_id, 80);
  const companyId = sanitizeTenantString(explicitScope?.company_id, 80);
  if (!tenantId || !companyId) {
    return json(missingTenantScopeError(), 400);
  }

  const method = safeStr(options?.method) || "GET";
  const body = options?.body ?? null;
  const requestedCompliancePath =
    safeStr(options?.compliancePath, 256) || CHIRON_CONFIG_STATUS_PATH;
  const compliancePath = requestedCompliancePath;
  if (
    compliancePath !== CHIRON_CONFIG_STATUS_PATH &&
    compliancePath !== CHIRON_CONFIG_TEST_CREDENTIALS_PATH &&
    compliancePath !== CHIRON_CONNECTION_TEST_PATH &&
    compliancePath !== CHIRON_CONFIG_TEST_CREDENTIALS_CLEAR_PATH
  ) {
    return json({ ok: false, error: "invalid_compliance_proxy_path" }, 400);
  }

  const proxyUrl = new URL(`https://fluxidi-compliance-api.internal${compliancePath}`);
  proxyUrl.searchParams.set("tenant_id", tenantId);
  proxyUrl.searchParams.set("company_id", companyId);

  const headers = {
    accept: "application/json",
    "x-fluxidi-internal-proxy": CHIRON_INTERNAL_PROXY_MODE,
    "x-fluxidi-proxy-token": adminToken,
    "x-fluxidi-proxy-tenant-id": tenantId,
    "x-fluxidi-proxy-company-id": companyId,
  };
  if (method === "POST") {
    headers["content-type"] = "application/json";
  }

  const proxyReq = new Request(proxyUrl.toString(), {
    method,
    headers,
    body:
      method === "POST" && body && typeof body === "object" && !Array.isArray(body)
        ? JSON.stringify(body)
        : undefined,
  });

  try {
    const resp = await env.COMPLIANCE_WORKER.fetch(proxyReq);
    const responseBody = await resp.text();
    return new Response(responseBody, {
      status: resp.status,
      headers: {
        "content-type": resp.headers.get("content-type") || "application/json; charset=utf-8",
        "cache-control": "no-store",
      },
    });
  } catch (_) {
    return json({ ok: false, error: "compliance_proxy_failed" }, 502);
  }
}
