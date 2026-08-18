// P2D4B1A — fail-closed, undefined-by-default limousine test-company allowlist.
//
// Pure helper. No KV, no fetch, no module-level request cache, no logs of the
// complete allowlist. Exact canonical membership only. Wildcards deny the
// entire list.

import { sanitizeTenantString } from "./parsing_utils.js";

export const LIMOUSINE_TEST_COMPANY_ALLOWLIST_ENV =
  "LIMOUSINE_TEST_COMPANY_ALLOWLIST";
export const LIMOUSINE_TEST_COMPANY_ALLOWLIST_MAX_CHARS = 2000;
export const LIMOUSINE_TEST_COMPANY_ALLOWLIST_MAX_ENTRIES = 32;
export const LIMOUSINE_TEST_COMPANY_ID_MAX = 80;

const WILDCARD_TOKENS = new Set(["*", "all", "true"]);

export function canonicalizeLimousineTestCompanyId(value) {
  return sanitizeTenantString(value, LIMOUSINE_TEST_COMPANY_ID_MAX);
}

function isWildcardToken(part) {
  return WILDCARD_TOKENS.has(String(part || "").trim().toLowerCase());
}

/// Parse `env.LIMOUSINE_TEST_COMPANY_ALLOWLIST`.
/// Undefined / empty / whitespace / oversized / wildcard / too many entries
/// all yield an empty set (deny every company).
export function parseLimousineTestCompanyAllowlist(raw) {
  if (raw == null) return [];
  if (typeof raw !== "string" && typeof raw !== "number" && typeof raw !== "boolean") {
    return [];
  }
  const text = String(raw);
  if (!text.trim()) return [];
  if (text.length > LIMOUSINE_TEST_COMPANY_ALLOWLIST_MAX_CHARS) return [];

  const parts = text.split(/[,\s]+/).map((part) => part.trim()).filter(Boolean);
  if (parts.length === 0) return [];
  if (parts.length > LIMOUSINE_TEST_COMPANY_ALLOWLIST_MAX_ENTRIES) return [];
  if (parts.some(isWildcardToken)) return [];

  const seen = new Set();
  const out = [];
  for (const part of parts) {
    const id = canonicalizeLimousineTestCompanyId(part);
    if (!id) continue;
    if (isWildcardToken(id)) return [];
    if (seen.has(id)) continue;
    seen.add(id);
    out.push(id);
  }
  return out;
}

export function limousineTestCompanyAllowlistConfigured(raw) {
  return parseLimousineTestCompanyAllowlist(raw).length > 0;
}

export function isLimousineTestCompanyAllowlisted(raw, companyId) {
  const canonical = canonicalizeLimousineTestCompanyId(companyId);
  if (!canonical) return false;
  const allowed = parseLimousineTestCompanyAllowlist(raw);
  if (allowed.length === 0) return false;
  return allowed.includes(canonical);
}

export function isTrustedLimousineTestCompany(env, companyId) {
  return isLimousineTestCompanyAllowlisted(
    env?.[LIMOUSINE_TEST_COMPANY_ALLOWLIST_ENV],
    companyId,
  );
}

export function limousineTestCompanyAllowlistFromEnv(env) {
  return parseLimousineTestCompanyAllowlist(
    env?.[LIMOUSINE_TEST_COMPANY_ALLOWLIST_ENV],
  );
}
