/**
 * Public marketplace visibility for Fluxidi companies.
 *
 * Source of truth: the event-maintained company registry, not public
 * directory leftovers and not a hardcoded six-company allowlist.
 * New registry members stay public unless their environment is test/local_qa.
 * Orphaned public-index rows without a live registry membership stay hidden.
 * Company records are never deleted here.
 */

import { codesOf, readRegistrySnapshot } from "./company_registry_index.mjs";

export const COMPANY_LINK_CODE_PREFIX = "company_link:index:code:";
export const COMPANY_LINK_CODE_SUFFIX = ":v1";

export const PUBLIC_MARKETPLACE_ENVIRONMENT_CLASSES = Object.freeze([
  "production",
  "unknown",
  "review",
  "example",
]);

export const HIDDEN_PUBLIC_ENVIRONMENT_CLASSES = Object.freeze([
  "test",
  "local_qa",
]);

export const DEFAULT_EXAMPLE_COMPANY_CODE = "FLX-00001";
export const DEFAULT_REVIEW_COMPANY_CODE = "FLX-00020";

export const EXAMPLE_COMPANY_COPY = Object.freeze({
  badge: Object.freeze({
    nl: "Voorbeeldbedrijf",
    en: "Example company",
    fr: "Entreprise exemple",
    es: "Empresa de ejemplo",
  }),
  notice: Object.freeze({
    nl: "Dit is het voorbeeldbedrijf van Fluxidi. Dit profiel laat zien hoe een taxibedrijf zich op het platform kan presenteren.",
    en: "This is Fluxidi's example company. This profile shows how a taxi company can present itself on the platform.",
    fr: "Ceci est l'entreprise exemple de Fluxidi. Ce profil montre comment une societe de taxi peut se presenter sur la plateforme.",
    es: "Esta es la empresa de ejemplo de Fluxidi. Este perfil muestra como una empresa de taxi puede presentarse en la plataforma.",
  }),
});

export const REVIEW_COMPANY_COPY = Object.freeze({
  badge: Object.freeze({
    nl: "Reviewomgeving",
    en: "Review environment",
    fr: "Environnement de review",
    es: "Entorno de review",
  }),
  notice: Object.freeze({
    nl: "Dit is de Google-reviewomgeving van Fluxidi. Gebruik deze omgeving alleen voor de reviewerflow.",
    en: "This is Fluxidi's Google review environment. Use it only for the reviewer flow.",
    fr: "Ceci est l'environnement Google Review de Fluxidi. Utilisez-le uniquement pour le parcours reviewer.",
    es: "Este es el entorno de Google Review de Fluxidi. Usalo solo para el flujo de reviewer.",
  }),
});

function text(value, max = 120) {
  return String(value ?? "").trim().slice(0, max);
}

export function normalizeFluxidiCompanyCode(value) {
  const code = text(value, 32).toUpperCase();
  return /^FLX-[0-9]{4,12}$/.test(code) ? code : "";
}

export function companyLinkCodeKey(companyCode) {
  const code = normalizeFluxidiCompanyCode(companyCode);
  return code ? `${COMPANY_LINK_CODE_PREFIX}${code}${COMPANY_LINK_CODE_SUFFIX}` : "";
}

export function canonicalPublicPartnerId(tenantId, companyId) {
  const tenant = text(tenantId, 80);
  const company = text(companyId, 80);
  if (!tenant || !company) return "";
  return `company:${tenant}:${company}`;
}

export function configuredExampleCompanyCode(env) {
  const fromEnv = normalizeFluxidiCompanyCode(env?.EXAMPLE_COMPANY_CODE);
  return fromEnv || DEFAULT_EXAMPLE_COMPANY_CODE;
}

export function configuredReviewCompanyCode(env) {
  const fromEnv = normalizeFluxidiCompanyCode(
    env?.PLAY_REVIEW_COMPANY_CODE ?? env?.REVIEW_COMPANY_CODE,
  );
  if (fromEnv) return fromEnv;
  return DEFAULT_REVIEW_COMPANY_CODE;
}

export function classifyRegistryPublicVisibility(entry, options = {}) {
  const code = normalizeFluxidiCompanyCode(entry?.company_code ?? entry?.companyCode);
  const lifecycle = text(entry?.lifecycle_status ?? entry?.lifecycleStatus, 24).toLowerCase() || "active";
  const environment = text(entry?.environment_class ?? entry?.environmentClass, 24).toLowerCase() || "unknown";
  const exampleCode = normalizeFluxidiCompanyCode(options.exampleCompanyCode) || DEFAULT_EXAMPLE_COMPANY_CODE;
  const reviewCode = normalizeFluxidiCompanyCode(options.reviewCompanyCode) || DEFAULT_REVIEW_COMPANY_CODE;

  if (!code) {
    return { public: false, reason: "missing_company_code", presentation: null };
  }
  if (lifecycle !== "active") {
    return { public: false, reason: "registry_lifecycle_inactive", presentation: null };
  }
  if (HIDDEN_PUBLIC_ENVIRONMENT_CLASSES.includes(environment)) {
    return { public: false, reason: "environment_hidden", presentation: null };
  }
  if (!PUBLIC_MARKETPLACE_ENVIRONMENT_CLASSES.includes(environment)) {
    return { public: false, reason: "environment_not_public", presentation: null };
  }

  let role = "operator";
  if (code === exampleCode || environment === "example") role = "example";
  else if (code === reviewCode || environment === "review") role = "review";

  return {
    public: true,
    reason: "registry_public",
    presentation: { role, company_code: code },
  };
}

export function emptyPublicCompanyVisibilityIndex(reason = "empty") {
  return {
    ok: reason === "empty",
    reason,
    public_company_codes: new Set(),
    public_partner_ids: new Set(),
    presentation_by_code: new Map(),
    presentation_by_partner: new Map(),
    classified: [],
  };
}

function addPartnerAlias(set, value) {
  const id = text(value, 160);
  if (id) set.add(id);
}

function unwrapLinkRecord(raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  if (raw.record && typeof raw.record === "object" && !Array.isArray(raw.record)) {
    return raw.record;
  }
  return raw;
}

export function partnerAliasesFromLink(record, companyCode = "") {
  const source = unwrapLinkRecord(record) || {};
  const tenant = text(source.tenant_id ?? source.tenantId, 80);
  const company = text(source.company_id ?? source.companyId, 80);
  const aliases = [];
  const canonical = canonicalPublicPartnerId(tenant, company);
  if (canonical) aliases.push(canonical);
  if (company) aliases.push(company);
  if (tenant && tenant !== company) aliases.push(tenant);
  const code = normalizeFluxidiCompanyCode(companyCode || source.company_code || source.companyCode);
  if (code) aliases.push(code);
  return aliases;
}

export function localizedPublicPresentationCopy(presentation, lang = "nl") {
  const role = text(presentation?.role, 24);
  const code = ["nl", "en", "fr", "es"].includes(String(lang || "").toLowerCase())
    ? String(lang).toLowerCase()
    : "nl";
  const pack = role === "example"
    ? EXAMPLE_COMPANY_COPY
    : role === "review"
      ? REVIEW_COMPANY_COPY
      : null;
  if (!pack) return null;
  return {
    role,
    company_code: normalizeFluxidiCompanyCode(presentation?.company_code),
    badge: pack.badge[code] || pack.badge.nl,
    notice: pack.notice[code] || pack.notice.nl,
    badge_i18n: pack.badge,
    notice_i18n: pack.notice,
  };
}

export function applyPublicMarketplaceProfileOverlay(profile, presentation, lang = "nl") {
  if (!profile || typeof profile !== "object" || Array.isArray(profile)) return profile;
  const copy = localizedPublicPresentationCopy(presentation, lang);
  if (!copy) {
    return presentation?.role
      ? { ...profile, public_presentation: { role: presentation.role } }
      : profile;
  }
  const next = {
    ...profile,
    example_company: copy.role === "example",
    review_environment: copy.role === "review",
    public_presentation: {
      role: copy.role,
      company_code: copy.company_code || null,
      badge: copy.badge_i18n,
      notice: copy.notice_i18n,
    },
  };
  if (copy.role === "example" || copy.role === "review") {
    next.tagline = copy.badge;
    next.about_short = copy.notice;
  }
  return next;
}

export function isPublicMarketplaceCompanyCode(index, companyCode) {
  const code = normalizeFluxidiCompanyCode(companyCode);
  return !!code && index?.public_company_codes instanceof Set && index.public_company_codes.has(code);
}

export function isPublicMarketplacePartner(index, ref = {}) {
  if (!index || index.ok !== true) return false;
  const ids = [
    ref.partner_id,
    ref.partnerId,
    canonicalPublicPartnerId(ref.tenant_id ?? ref.tenantId, ref.company_id ?? ref.companyId),
    ref.company_id,
    ref.companyId,
    ref.tenant_id,
    ref.tenantId,
    ref.company_code,
    ref.companyCode,
  ];
  for (const id of ids) {
    const value = text(id, 160);
    if (value && index.public_partner_ids.has(value)) return true;
    if (isPublicMarketplaceCompanyCode(index, value)) return true;
  }
  return false;
}

export function publicPresentationForCompanyCode(index, companyCode) {
  const code = normalizeFluxidiCompanyCode(companyCode);
  if (!code || !(index?.presentation_by_code instanceof Map)) return null;
  return index.presentation_by_code.get(code) || null;
}

export function publicPresentationForPartner(index, ref = {}) {
  const ids = [
    ref.partner_id,
    ref.partnerId,
    canonicalPublicPartnerId(ref.tenant_id ?? ref.tenantId, ref.company_id ?? ref.companyId),
    ref.company_id,
    ref.companyId,
    normalizeFluxidiCompanyCode(ref.company_code ?? ref.companyCode),
  ];
  for (const id of ids) {
    const value = text(id, 160);
    if (value && index?.presentation_by_partner instanceof Map && index.presentation_by_partner.has(value)) {
      return index.presentation_by_partner.get(value);
    }
  }
  return publicPresentationForCompanyCode(index, ref.company_code ?? ref.companyCode);
}

export async function loadPublicCompanyVisibilityIndex(env, options = {}) {
  const kv = env?.BOOKING_KV;
  if (!kv || typeof kv.get !== "function") {
    return emptyPublicCompanyVisibilityIndex("kv_unbound");
  }
  let snapshot;
  try {
    snapshot = await readRegistrySnapshot(kv);
  } catch {
    return emptyPublicCompanyVisibilityIndex("registry_unreadable");
  }
  const codes = [...codesOf(snapshot || {})];
  const byCode = new Map();
  for (const page of snapshot?.pages || []) {
    for (const row of page.companies || []) {
      const code = normalizeFluxidiCompanyCode(row?.company_code);
      if (code) byCode.set(code, row);
    }
  }
  const exampleCompanyCode = configuredExampleCompanyCode(env);
  const reviewCompanyCode = configuredReviewCompanyCode(env);
  const index = emptyPublicCompanyVisibilityIndex(codes.length ? "registry" : "empty");
  index.ok = true;
  for (const code of codes) {
    const entry = byCode.get(code) || { company_code: code };
    const decision = classifyRegistryPublicVisibility(entry, {
      exampleCompanyCode,
      reviewCompanyCode,
    });
    const classified = {
      company_code: code,
      display_name: text(entry.display_name ?? entry.displayName, 160),
      environment_class: text(entry.environment_class, 24) || "unknown",
      lifecycle_status: text(entry.lifecycle_status, 24) || "active",
      public: decision.public === true,
      reason: decision.reason,
      presentation_role: decision.presentation?.role || null,
    };
    index.classified.push(classified);
    if (!decision.public) continue;
    index.public_company_codes.add(code);
    index.presentation_by_code.set(code, decision.presentation);
    const key = companyLinkCodeKey(code);
    let link = null;
    if (key) {
      try {
        link = await kv.get(key, { type: "json" });
      } catch {
        link = null;
      }
    }
    const aliases = partnerAliasesFromLink(link, code);
    for (const alias of aliases) {
      addPartnerAlias(index.public_partner_ids, alias);
      index.presentation_by_partner.set(alias, decision.presentation);
    }
  }
  if (typeof options.nowIso === "string") index.loaded_at = options.nowIso;
  return index;
}

const visibilityMemo = new WeakMap();

export async function loadPublicCompanyVisibilityIndexCached(env) {
  if (!env || typeof env !== "object") {
    return emptyPublicCompanyVisibilityIndex("kv_unbound");
  }
  if (visibilityMemo.has(env)) return visibilityMemo.get(env);
  const pending = loadPublicCompanyVisibilityIndex(env);
  visibilityMemo.set(env, pending);
  return pending;
}
