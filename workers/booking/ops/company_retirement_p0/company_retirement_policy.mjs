/**
 * Explicit-ID company retirement policy.
 * Phase A (registry-only) is the only prepared mode.
 * Phase B (full purge) is hard-disabled and cannot be enabled by flags.
 * No wildcards, no "all except".
 */

export {
  HARD_PROTECTED_COMPANY_CODES,
  isHardProtectedCompanyCode,
} from "../../modules/company_registry_tombstone_guard.mjs";

export const EXPLICIT_RETIREMENT_CANDIDATES = Object.freeze([
  "FLX-00002",
  "FLX-00003",
  "FLX-00004",
  "FLX-00005",
  "FLX-00006",
  "FLX-00007",
  "FLX-00008",
  "FLX-00009",
  "FLX-00010",
  "FLX-00011",
  "FLX-00012",
  "FLX-00013",
  "FLX-00014",
  "FLX-00015",
  "FLX-00016",
  "FLX-00017",
  "FLX-00018",
  "FLX-00019",
  "FLX-00021",
  "FLX-00022",
  "FLX-4821",
  "FLX-90811",
]);

export const PHASE_A_REGISTRY_RETIREMENT = "registry_retirement";
export const PHASE_B_FULL_PURGE = "full_purge";
export const ACTIVE_PHASE = PHASE_A_REGISTRY_RETIREMENT;
export const PHASE_B_ENABLED = false;

export const EXECUTE_CONFIRMATION_TEXT = "RETIRE-REGISTRY-ONLY-P0";
export const LEGACY_EXECUTE_CONFIRMATION_TEXT = "RETIRE-EXPLICIT-TEST-COMPANIES-P0";

export const OBSERVED_ID_MISMATCH_CODES = Object.freeze([]);

const COMPANY_CODE_RE = /^FLX-[0-9]{4,12}$/;

export const RISK_GROUPS = Object.freeze({
  EMPTY_LOW: "empty_or_low_risk",
  DATA_PRESENT: "data_present",
  PAYMENTS_OR_RECENT: "payments_or_recent_usage",
  MISSING_OR_MISMATCH: "missing_or_id_mismatch",
  PROTECTED: "protected",
});

export const REGISTRY_ONLY_KEY_KINDS = Object.freeze([
  "tombstone",
  "registry_code_retired",
  "registry_page",
  "registry_manifest",
  "company_link_retired",
]);

export const FORBIDDEN_PHASE_A_KEY_MARKERS = Object.freeze([
  "booking:",
  "bookings:list",
  "invoice",
  "fiscal",
  "drivers:",
  "fleet:",
  "customer",
  "session",
  "mollie",
  "billit",
  "chiron",
  "oauth",
  "token",
  "public-media",
  "r2",
  "company_driver_link",
]);

export function isHardDisabledPhaseB() {
  return PHASE_B_ENABLED !== true;
}

export function assertPhaseSelection(phase = ACTIVE_PHASE) {
  const requested = String(phase || "").trim() || ACTIVE_PHASE;
  if (requested === PHASE_B_FULL_PURGE || requested === "purge" || requested === "full-purge") {
    return { ok: false, error: "phase_b_full_purge_disabled", phase: requested };
  }
  if (requested !== PHASE_A_REGISTRY_RETIREMENT && requested !== "registry" && requested !== "phase_a") {
    return { ok: false, error: "unknown_phase", phase: requested };
  }
  return { ok: true, phase: PHASE_A_REGISTRY_RETIREMENT };
}

export function normalizeCompanyCode(code) {
  return String(code || "").trim().toUpperCase();
}

export function isExplicitRetirementCandidate(code) {
  return EXPLICIT_RETIREMENT_CANDIDATES.includes(String(code || "").trim());
}

export function looksLikeWildcardSelection(raw) {
  const text = String(raw || "");
  return /[*?]|id\s*!=|alles behalve|all except|prefix:|startsWith\(|FLX-000(?!\d)/i.test(text)
    || text.includes("!")
    || text.endsWith("-")
    || text.includes("FLX-*");
}

export function selectRetirementCodes(requested = EXPLICIT_RETIREMENT_CANDIDATES) {
  const source = Array.isArray(requested) ? requested : [requested];
  const selected = [];
  const errors = [];
  for (const raw of source) {
    if (looksLikeWildcardSelection(raw)) {
      errors.push({ code: String(raw), error: "wildcard_or_exclusion_forbidden" });
      continue;
    }
    const code = normalizeCompanyCode(raw);
    if (!COMPANY_CODE_RE.test(code)) {
      errors.push({ code, error: "invalid_company_code" });
      continue;
    }
    if (code === "FLX-00001" || code === "FLX-00020") {
      errors.push({ code, error: "protected_company" });
      continue;
    }
    if (!isExplicitRetirementCandidate(code)) {
      errors.push({ code, error: "not_an_explicit_candidate" });
      continue;
    }
    if (!selected.includes(code)) selected.push(code);
  }
  if (errors.length) {
    return { ok: false, selected: [], errors };
  }
  if (!selected.length) {
    return { ok: false, selected: [], errors: [{ code: null, error: "empty_selection" }] };
  }
  return { ok: true, selected, errors: [] };
}

export function assertExecuteAuthorization({
  execute = false,
  confirm = "",
  executeEnabled = false,
  phase = ACTIVE_PHASE,
  fullPurge = false,
} = {}) {
  const phaseCheck = assertPhaseSelection(phase);
  if (!phaseCheck.ok) return phaseCheck;
  if (fullPurge === true || phase === PHASE_B_FULL_PURGE) {
    return { ok: false, error: "phase_b_full_purge_disabled", mode: "forbidden" };
  }
  if (!execute) {
    return { ok: true, mode: "dry_run", phase: PHASE_A_REGISTRY_RETIREMENT };
  }
  if (executeEnabled !== true) {
    return { ok: false, error: "execute_disabled_until_explicit_approval" };
  }
  if (String(confirm || "") === LEGACY_EXECUTE_CONFIRMATION_TEXT) {
    return { ok: false, error: "legacy_full_purge_confirmation_rejected" };
  }
  if (String(confirm || "") !== EXECUTE_CONFIRMATION_TEXT) {
    return { ok: false, error: "confirmation_text_mismatch" };
  }
  return { ok: true, mode: "execute", phase: PHASE_A_REGISTRY_RETIREMENT };
}

export function assertFullPurgeForbidden(flags = {}) {
  const requested = flags.fullPurge === true
    || flags.purge === true
    || flags.phase === PHASE_B_FULL_PURGE
    || String(flags.confirm || "").includes("PURGE")
    || process.env.FLUXIDI_RETIREMENT_FULL_PURGE === "1";
  if (requested || PHASE_B_ENABLED !== true) {
    return {
      ok: false,
      error: "phase_b_full_purge_disabled",
      executable: false,
    };
  }
  return { ok: false, error: "phase_b_full_purge_disabled", executable: false };
}

export const SECRET_KEY_MARKERS = Object.freeze([
  "oauth",
  "token",
  "secret",
  "refresh",
  "encryption",
  "password",
  "session",
  "nonce",
  "mollie_connect_auth",
  "billit:oauth",
  "google_calendar_auth",
]);

export function isSecretBearingKey(key) {
  const text = String(key || "").toLowerCase();
  return SECRET_KEY_MARKERS.some((marker) => text.includes(marker));
}

export function isForbiddenPhaseAKey(key) {
  const text = String(key || "").toLowerCase();
  if (text.startsWith("company_registry:")) return false;
  if (text.startsWith("company_link:index:code:")) return false;
  return FORBIDDEN_PHASE_A_KEY_MARKERS.some((marker) => text.includes(marker));
}

export function isAllowedPhaseAWriteKey(key, selectedCodes = EXPLICIT_RETIREMENT_CANDIDATES) {
  const text = String(key || "");
  if (!text || isForbiddenPhaseAKey(text)) return false;
  if (text === "company_registry:manifest:v1") return true;
  if (/^company_registry:page:\d+:v1$/.test(text)) return true;
  const tombstone = text.match(/^company_registry:tombstone:(FLX-[0-9]{4,12}):v1$/);
  const code = text.match(/^company_registry:code:(FLX-[0-9]{4,12}):v1$/);
  const link = text.match(/^company_link:index:code:(FLX-[0-9]{4,12}):v1$/);
  const companyCode = (tombstone || code || link)?.[1];
  if (!companyCode) return false;
  if (companyCode === "FLX-00001" || companyCode === "FLX-00020") return false;
  return selectedCodes.includes(companyCode);
}

export const LIVE_WORKER_BUNDLE_RETIREMENT_FILES = Object.freeze([
  "workers/booking/fluxidi_booking_worker.js",
  "workers/booking/modules/company_registry_index.mjs",
  "workers/booking/modules/company_registry_tombstone_guard.mjs",
]);

export const LOCAL_ONLY_RETIREMENT_FILES = Object.freeze([
  "workers/booking/ops/company_retirement_p0/",
]);
