/**
 * Live Worker tombstone / revocation guard.
 *
 * This module is the only retirement-related surface that belongs in the
 * fluxidi-booking-api bundle. It never deletes companies, never writes
 * tombstones by itself, and must not import local ops retirement tooling.
 *
 * Hard-protected production companies can never be treated as revoked.
 */

export const HARD_PROTECTED_COMPANY_CODES = Object.freeze(["FLX-00001", "FLX-00020"]);

export const COMPANY_REGISTRY_TOMBSTONE_PREFIX = "company_registry:tombstone:";

export function isHardProtectedCompanyCode(companyCode) {
  return HARD_PROTECTED_COMPANY_CODES.includes(String(companyCode || "").trim());
}

export function registryTombstoneKey(companyCode) {
  const code = String(companyCode || "").trim();
  if (!/^FLX-[0-9]{4,12}$/.test(code)) return null;
  return `${COMPANY_REGISTRY_TOMBSTONE_PREFIX}${code}:v1`;
}

async function kvGetJson(kv, key) {
  if (!kv || !key) return null;
  const raw = await kv.get(key, { type: "json" });
  if (raw != null) return raw;
  const text = await kv.get(key);
  if (!text) return null;
  if (typeof text === "object") return text;
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

export async function readRegistryTombstone(kv, companyCode) {
  const key = registryTombstoneKey(companyCode);
  if (!key || !kv) return null;
  return kvGetJson(kv, key);
}

export async function isCompanyRegistryRevoked(kv, companyCode) {
  if (isHardProtectedCompanyCode(companyCode)) return false;
  const tombstone = await readRegistryTombstone(kv, companyCode);
  if (!tombstone || typeof tombstone !== "object" || Array.isArray(tombstone)) return false;
  return String(tombstone.company_code || "").trim() === String(companyCode || "").trim()
    && tombstone.revoked === true;
}

export function assertProtectedCompanyImmutable(companyCode, action = "registry_mutation") {
  const code = String(companyCode || "").trim();
  if (!isHardProtectedCompanyCode(code)) return { ok: true, code };
  return {
    ok: false,
    code,
    error: "protected_company",
    action,
    message: "FLX-00001 and FLX-00020 cannot receive a tombstone, retirement, or purge",
  };
}

export function tombstoneRecord(companyCode, nowIso) {
  const blocked = assertProtectedCompanyImmutable(companyCode, "tombstone");
  if (!blocked.ok) {
    throw new Error("protected_company");
  }
  return {
    schema_version: 1,
    company_code: String(companyCode || "").trim(),
    revoked: true,
    revoked_at: nowIso,
    reason: "ops_company_retirement_p0_phase_a",
    phase: "registry_retirement",
  };
}
