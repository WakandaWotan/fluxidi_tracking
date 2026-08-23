// LIMOUSINE-QUOTE-DOCUMENT-P3J — immutable, revision-bound quotation snapshot.
//
// Pure allowlist builder. Never clones the live quote record. Never issues a
// Document Core type, invoice number, Billit order, or Peppol document.
// Snapshots are created only when a company offer revision is sent.

import { sha256Hex } from "./crypto_utils.js";
import { sanitizeTenantString } from "./parsing_utils.js";
import { normalizeLimousineQuotationLocale } from "./limousine_quotation_i18n.mjs";

export const LIMOUSINE_QUOTATION_SCHEMA_VERSION = 1;
export const LIMOUSINE_QUOTATION_RENDERER_VERSION_V1 = 1;
export const LIMOUSINE_QUOTATION_RENDERER_VERSION = 2;

export const LIMOUSINE_QUOTATION_SNAPSHOT_CONFLICT = "quotation_snapshot_conflict";
export const LIMOUSINE_QUOTATION_SNAPSHOT_MISSING = "quotation_snapshot_missing";

export const LIMOUSINE_QUOTATION_LOCALES = Object.freeze(["nl", "en", "fr", "es"]);

export const LIMOUSINE_STANDARD_VAT_RATE = 0.21;
export const LIMOUSINE_VAT_TREATMENT_INCL = "incl";
export const LIMOUSINE_VAT_TREATMENT_EXCL = "excl";
export const LIMOUSINE_VAT_TREATMENT_NONE = "none";
export const LIMOUSINE_VAT_TREATMENTS = Object.freeze([
  LIMOUSINE_VAT_TREATMENT_INCL,
  LIMOUSINE_VAT_TREATMENT_EXCL,
  LIMOUSINE_VAT_TREATMENT_NONE,
]);

export const LIMOUSINE_QUOTATION_FORBIDDEN_SOURCE_KEYS = Object.freeze([
  "status_ref",
  "statusRef",
  "acceptance_reference",
  "acceptanceReference",
  "authorization",
  "headers",
  "cookie",
  "bearer",
  "company_session",
  "customer_session",
  "api_key",
  "secret",
  "token",
  "encryption",
  "card",
  "cvc",
  "pan",
  "payment_capability",
  "billing_customer",
  "billing_identity",
  "invoice_intent",
  "invoice_email",
  "invoice_number",
  "invoice_document_id",
  "document_id",
  "source_booking_id",
  "billit",
  "peppol",
  "customer_fingerprint",
  "customer_email",
  "customer_phone",
  "customer_name",
  "email",
  "phone",
  "r2",
  "audit",
]);

const ISO_CURRENCY = /^[A-Z]{3}$/;

function asObject(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function safeText(value, max = 240) {
  return sanitizeTenantString(value, max);
}

function toInt(value) {
  if (value == null || value === "") return null;
  const n = Number(value);
  if (!Number.isFinite(n) || !Number.isInteger(n)) {
    const parsed = parseInt(String(value), 10);
    if (!Number.isFinite(parsed)) return null;
    return parsed;
  }
  return n;
}

function normalizeCurrency(value) {
  const c = String(value ?? "").trim().toUpperCase();
  return ISO_CURRENCY.test(c) ? c : "";
}

function localizedMap(raw, max = 1200) {
  const src = asObject(raw);
  const out = {};
  for (const lang of LIMOUSINE_QUOTATION_LOCALES) {
    const text = safeText(src[lang], max);
    if (text) out[lang] = text;
  }
  return out;
}

function cloneStringList(value, { maxItems = 32, maxLen = 96 } = {}) {
  if (!Array.isArray(value)) return [];
  const out = [];
  for (const item of value.slice(0, maxItems)) {
    const text = safeText(item, maxLen);
    if (text) out.push(text);
  }
  return out;
}

export function canonicalizeLimousineQuotationValue(value) {
  if (value === null) return null;
  if (Array.isArray(value)) {
    return value.map((item) =>
      item === undefined ? null : canonicalizeLimousineQuotationValue(item),
    );
  }
  if (typeof value === "object") {
    const out = {};
    for (const key of Object.keys(value).sort()) {
      const child = canonicalizeLimousineQuotationValue(value[key]);
      if (child !== undefined) out[key] = child;
    }
    return out;
  }
  return value;
}

export function stableLimousineQuotationJson(value) {
  return JSON.stringify(canonicalizeLimousineQuotationValue(value));
}

export async function hashLimousineQuotationSnapshotBody(body) {
  return sha256Hex(stableLimousineQuotationJson(body));
}

export function normalizeLimousineVatTreatment(value) {
  const token = safeText(value, 16).toLowerCase();
  if (token === LIMOUSINE_VAT_TREATMENT_EXCL) return LIMOUSINE_VAT_TREATMENT_EXCL;
  if (token === LIMOUSINE_VAT_TREATMENT_NONE) return LIMOUSINE_VAT_TREATMENT_NONE;
  return LIMOUSINE_VAT_TREATMENT_INCL;
}

export function resolveLimousineEnteredAmountCents(input = {}) {
  const src = asObject(input);
  return toInt(
    src.entered_amount_cents ??
      src.enteredAmountCents ??
      src.quoted_amount_cents ??
      src.quotedAmountCents ??
      src.total_incl_vat_cents ??
      src.totalInclVatCents,
  );
}

function resolveLimousineVatRate(treatment, rawRate) {
  if (treatment === LIMOUSINE_VAT_TREATMENT_NONE) return 0;
  if (rawRate == null || rawRate === "") return LIMOUSINE_STANDARD_VAT_RATE;
  const rate = Number(rawRate);
  if (!Number.isFinite(rate) || rate < 0) return LIMOUSINE_STANDARD_VAT_RATE;
  return rate;
}

function majorFromCents(cents) {
  return Math.round(Number(cents) || 0) / 100;
}

function splitInclusiveEnteredCents(grossCents, rate) {
  if (!(rate > 0)) {
    return { netCents: grossCents, vatCents: 0, grossCents };
  }
  // Preserve the existing inclusive rounding: euro-major then back to cents.
  const inclVat = grossCents / 100;
  const exVat = Math.round((inclVat / (1 + rate)) * 100) / 100;
  const vatAmount = Math.round((inclVat - exVat) * 100) / 100;
  return {
    netCents: Math.round(exVat * 100),
    vatCents: Math.round(vatAmount * 100),
    grossCents,
  };
}

function splitExclusiveEnteredCents(netCents, rate) {
  if (!(rate > 0)) {
    return { netCents, vatCents: 0, grossCents: netCents };
  }
  const vatCents = Math.round(netCents * rate);
  return {
    netCents,
    vatCents,
    grossCents: netCents + vatCents,
  };
}

export function deriveLimousineQuotationTotals({
  enteredAmountCents,
  totalInclVatCents,
  vatRate,
  vatTreatment,
  currency,
} = {}) {
  const entered =
    toInt(enteredAmountCents) ?? toInt(totalInclVatCents) ?? 0;
  const treatment = normalizeLimousineVatTreatment(vatTreatment);
  const rate = resolveLimousineVatRate(treatment, vatRate);
  const cur = normalizeCurrency(currency);
  const split =
    treatment === LIMOUSINE_VAT_TREATMENT_EXCL
      ? splitExclusiveEnteredCents(entered, rate)
      : treatment === LIMOUSINE_VAT_TREATMENT_NONE || !(rate > 0)
        ? { netCents: entered, vatCents: 0, grossCents: entered }
        : splitInclusiveEnteredCents(entered, rate);
  return {
    entered_amount_cents: entered,
    total_ex_vat_cents: split.netCents,
    vat_amount_cents: split.vatCents,
    total_incl_vat_cents: split.grossCents,
    price_ex_vat: majorFromCents(split.netCents),
    price_vat: majorFromCents(split.vatCents),
    price_incl_vat: majorFromCents(split.grossCents),
    vat_rate: rate,
    vat_treatment: treatment,
    currency: cur,
  };
}

function freezeLabeledMoneyItems(raw, { idKey, max = 24 } = {}) {
  if (!Array.isArray(raw)) return [];
  const out = [];
  for (const item of raw.slice(0, max)) {
    const src = asObject(item);
    const id = safeText(src[idKey] ?? src.item_id ?? src.extra_id ?? src.id, 64);
    if (!id) continue;
    const amount = toInt(src.amount_cents ?? src.amountCents);
    out.push({
      [idKey]: id,
      ...(Object.keys(localizedMap(src.label ?? src.public_text, 240)).length
        ? { label: localizedMap(src.label ?? src.public_text, 240) }
        : {}),
      ...(amount != null ? { amount_cents: amount } : {}),
    });
  }
  return out;
}

function freezeTerms(raw) {
  const src = asObject(raw);
  const keys = [
    "terms_revision",
    "cancellation_deadline_hours",
    "cancellation_penalty_percent",
    "waiting_time_included_minutes",
    "waiting_time_overage_cents_per_minute",
    "no_show_penalty_percent",
    "overtime_cents_per_hour",
  ];
  const out = {};
  for (const key of keys) {
    const n = toInt(src[key]);
    if (n != null) out[key] = n;
  }
  const obligations = localizedMap(src.customer_obligations, 1200);
  const important = localizedMap(src.important_information, 1200);
  if (Object.keys(obligations).length) out.customer_obligations = obligations;
  if (Object.keys(important).length) out.important_information = important;
  return out;
}

export function freezeLimousineQuotationSellerSnapshot(input = {}) {
  const src = asObject(input);
  const logo = asObject(src.logo);
  const present = logo.present === true && safeText(logo.data_uri, 400000);
  return {
    name: safeText(src.name ?? src.trading_name, 160) || null,
    trading_name: safeText(src.trading_name ?? src.name, 160) || null,
    legal_name: safeText(src.legal_name ?? src.legal_entrepreneur_name, 160) || null,
    legal_entrepreneur_name:
      safeText(src.legal_entrepreneur_name ?? src.legal_name, 160) || null,
    legal_form: safeText(src.legal_form, 64) || null,
    legal_form_label_nl: safeText(src.legal_form_label_nl, 80) || null,
    vat_number: safeText(src.vat_number, 64) || null,
    registration_number:
      safeText(src.registration_number ?? src.enterprise_number, 32) || null,
    enterprise_number:
      safeText(src.enterprise_number ?? src.registration_number, 32) || null,
    contact_email: safeText(src.contact_email ?? src.email, 240) || null,
    address_line: safeText(src.address_line, 240) || null,
    postal_code: safeText(src.postal_code, 32) || null,
    city: safeText(src.city, 120) || null,
    country_code: safeText(src.country_code, 8).toUpperCase() || null,
    logo: present
      ? {
          present: true,
          mime: safeText(logo.mime, 40) || null,
          sha256: safeText(logo.sha256, 80) || null,
          data_uri: safeText(logo.data_uri, 400000),
        }
      : { present: false },
  };
}

export function freezeLimousineQuotationRequestSnapshot(input = {}) {
  const src = asObject(input);
  return {
    journey_type: safeText(src.journey_type, 32),
    service_type: safeText(src.service_type, 32) || "limousine",
    pricing_mode: safeText(src.pricing_mode, 32),
    direction: safeText(src.direction, 32),
    from: safeText(src.from, 240),
    to: safeText(src.to, 240),
    stops: cloneStringList(src.stops, { maxItems: 8, maxLen: 240 }),
    scheduled_pickup_iso: safeText(src.scheduled_pickup_iso, 40),
    roundtrip: src.roundtrip === true,
    return_pickup_iso: safeText(src.return_pickup_iso, 40),
    requested_duration_minutes: toInt(src.requested_duration_minutes),
    pax: toInt(src.pax),
    bags: toInt(src.bags),
    occasion: safeText(src.occasion, 80),
    customer_note: safeText(src.customer_note, 500),
    selected_extra_ids: cloneStringList(src.selected_extra_ids, {
      maxItems: 32,
      maxLen: 64,
    }).sort(),
    public_partner_id: safeText(src.public_partner_id, 120),
    offer_id: safeText(src.offer_id, 64),
    service_class_id: safeText(src.service_class_id, 64),
    vehicle_id: safeText(src.vehicle_id, 96),
    itinerary_fingerprint: safeText(src.itinerary_fingerprint, 64),
  };
}

export function freezeLimousineQuotationVehicleSnapshot(input = {}) {
  const src = asObject(input);
  return {
    vehicle_id: safeText(src.vehicle_id, 96),
    public_name: safeText(src.public_name, 120),
    service_class_id: safeText(src.service_class_id, 64),
    photo_url: safeText(src.photo_url, 500),
    passenger_capacity: toInt(src.passenger_capacity),
    luggage_capacity: toInt(src.luggage_capacity),
  };
}

export function freezeLimousineQuotationOfferSnapshot(input = {}) {
  const src = asObject(input);
  const terms = freezeTerms(src.terms);
  return {
    public_text: localizedMap(src.public_text, 1200),
    included_services: freezeLabeledMoneyItems(src.included_services, {
      idKey: "item_id",
    }),
    separately_priced_extras: freezeLabeledMoneyItems(
      src.separately_priced_extras ?? src.paid_extras,
      { idKey: "extra_id" },
    ),
    mobilisation_disclosure: localizedMap(src.mobilisation_disclosure, 1200),
    terms,
    terms_revision: toInt(src.terms_revision ?? terms.terms_revision) ?? 0,
    quoted_at: safeText(src.quoted_at, 40),
    expires_at: safeText(src.expires_at, 40),
    vat_treatment: normalizeLimousineVatTreatment(src.vat_treatment),
    vat_rate: Number(src.vat_rate) || 0,
    currency: normalizeCurrency(src.currency),
    ...(toInt(src.entered_amount_cents ?? src.enteredAmountCents) != null
      ? {
          entered_amount_cents: toInt(
            src.entered_amount_cents ?? src.enteredAmountCents,
          ),
        }
      : {}),
    total_incl_vat_cents: toInt(src.total_incl_vat_cents) ?? 0,
  };
}

export async function buildLimousineQuotationSnapshot({
  quoteRequestId,
  quoteRevision,
  offerSourceRevision = 0,
  pricingSectionRevision = 0,
  termsRevision = 0,
  issuedAt,
  expiresAt,
  locale,
  sellerSnapshot,
  requestSnapshot,
  vehicleSnapshot,
  offerSnapshot,
  totalsSnapshot,
  schemaVersion = LIMOUSINE_QUOTATION_SCHEMA_VERSION,
  rendererVersion = LIMOUSINE_QUOTATION_RENDERER_VERSION,
} = {}) {
  const request = freezeLimousineQuotationRequestSnapshot(requestSnapshot);
  const vehicle = freezeLimousineQuotationVehicleSnapshot(vehicleSnapshot);
  const offer = freezeLimousineQuotationOfferSnapshot(offerSnapshot);
  const seller = freezeLimousineQuotationSellerSnapshot(sellerSnapshot);
  const totalsInput = asObject(totalsSnapshot);
  const enteredFromTotals = toInt(
    totalsInput.entered_amount_cents ?? totalsInput.enteredAmountCents,
  );
  const enteredFromOffer = toInt(offer.entered_amount_cents);
  const enteredAmountCents =
    (enteredFromTotals != null && enteredFromTotals > 0
      ? enteredFromTotals
      : null) ??
    (enteredFromOffer != null && enteredFromOffer > 0 ? enteredFromOffer : null) ??
    toInt(totalsInput.total_incl_vat_cents) ??
    toInt(offer.total_incl_vat_cents);
  const totals = deriveLimousineQuotationTotals({
    enteredAmountCents,
    vatRate: totalsInput.vat_rate ?? offer.vat_rate,
    vatTreatment: totalsInput.vat_treatment ?? offer.vat_treatment,
    currency: totalsInput.currency ?? offer.currency,
  });
  offer.entered_amount_cents = totals.entered_amount_cents;
  offer.total_incl_vat_cents = totals.total_incl_vat_cents;
  offer.vat_rate = totals.vat_rate;
  offer.vat_treatment = totals.vat_treatment;
  const loc = normalizeLimousineQuotationLocale(locale);
  const body = {
    schema_version: Number(schemaVersion) || LIMOUSINE_QUOTATION_SCHEMA_VERSION,
    renderer_version: Number(rendererVersion) || LIMOUSINE_QUOTATION_RENDERER_VERSION,
    quote_request_id: safeText(quoteRequestId, 120),
    quote_revision: toInt(quoteRevision) ?? 0,
    offer_source_revision: toInt(offerSourceRevision) ?? 0,
    pricing_section_revision: toInt(pricingSectionRevision) ?? 0,
    terms_revision: toInt(termsRevision) ?? offer.terms_revision ?? 0,
    issued_at: safeText(issuedAt, 40),
    expires_at: safeText(expiresAt ?? offer.expires_at, 40),
    locale: loc,
    seller_snapshot: seller,
    request_snapshot: request,
    vehicle_snapshot: vehicle,
    offer_snapshot: offer,
    totals_snapshot: totals,
  };
  const contentHash = await hashLimousineQuotationSnapshotBody(body);
  return { ...body, content_hash: contentHash };
}

export async function buildLimousineQuotationSnapshotFromRecord({
  record,
  sellerSnapshot = null,
  issuedAt = null,
} = {}) {
  const rec = asObject(record);
  const request = asObject(rec.request);
  const quote = asObject(rec.quote);
  return buildLimousineQuotationSnapshot({
    quoteRequestId: rec.quote_request_id,
    quoteRevision: rec.revision,
    offerSourceRevision: rec.offer_source_revision,
    pricingSectionRevision: rec.pricing_section_revision,
    termsRevision: quote.terms_revision,
    issuedAt: issuedAt || quote.quoted_at,
    expiresAt: quote.expires_at,
    locale: request.locale,
    sellerSnapshot,
    requestSnapshot: request,
    vehicleSnapshot: request.vehicle_snapshot,
    offerSnapshot: quote,
  });
}

export function quotationSnapshotsMap(record) {
  const rec = asObject(record);
  const raw = rec.quotation_snapshots;
  return raw && typeof raw === "object" && !Array.isArray(raw) ? raw : {};
}

export function resolveLimousineQuotationSnapshot(record, revision = null) {
  const snapshots = quotationSnapshotsMap(record);
  const rec = asObject(record);
  const requested = revision != null ? toInt(revision) : toInt(rec.quotation_revision);
  if (requested == null) return null;
  const snap = snapshots[String(requested)];
  return snap && typeof snap === "object" && !Array.isArray(snap) ? snap : null;
}

export function recordHasLimousineQuotationSnapshots(record) {
  return Object.keys(quotationSnapshotsMap(record)).length > 0;
}

export function resolveLimousineQuotationCommercialSource(record) {
  const rec = asObject(record);
  const hasAny = recordHasLimousineQuotationSnapshots(rec);
  const snapshot = resolveLimousineQuotationSnapshot(rec);
  if (snapshot) return { mode: "snapshot", snapshot };
  if (!hasAny) return { mode: "legacy", snapshot: null };
  return {
    mode: "missing",
    snapshot: null,
    reason: LIMOUSINE_QUOTATION_SNAPSHOT_MISSING,
  };
}

export function projectLimousineQuotationAvailability(record) {
  const snapshot = resolveLimousineQuotationSnapshot(record);
  if (!snapshot) {
    return { quotation_available: false };
  }
  const totals = asObject(snapshot.totals_snapshot);
  const out = {
    quotation_available: true,
    quotation_revision: toInt(snapshot.quote_revision) ?? 0,
  };
  const sentAt = safeText(snapshot.issued_at, 40);
  const expiresAt = safeText(snapshot.expires_at, 40);
  if (sentAt) out.quotation_sent_at = sentAt;
  if (expiresAt) out.quotation_expires_at = expiresAt;
  const total = toInt(totals.total_incl_vat_cents);
  if (total != null) out.quotation_total_incl_vat_cents = total;
  const net = toInt(totals.total_ex_vat_cents);
  if (net != null) out.quotation_total_ex_vat_cents = net;
  const vat = toInt(totals.vat_amount_cents);
  if (vat != null) out.quotation_vat_amount_cents = vat;
  const entered = toInt(totals.entered_amount_cents);
  if (entered != null) out.quotation_entered_amount_cents = entered;
  if (totals.vat_rate != null) out.quotation_vat_rate = totals.vat_rate;
  const treatment = safeText(totals.vat_treatment, 16);
  if (treatment) out.quotation_vat_treatment = treatment;
  const currency = normalizeCurrency(totals.currency);
  if (currency) out.quotation_currency = currency;
  return out;
}

export function attachLimousineQuotationSnapshot(record, snapshot) {
  const rec = asObject(record);
  const snap = asObject(snapshot);
  const revision = toInt(snap.quote_revision);
  const hash = safeText(snap.content_hash, 80);
  if (revision == null || !hash) {
    return { ok: false, reason: LIMOUSINE_QUOTATION_SNAPSHOT_CONFLICT };
  }
  const key = String(revision);
  const existingMap = quotationSnapshotsMap(rec);
  const existing = existingMap[key];
  if (existing && typeof existing === "object") {
    if (safeText(existing.content_hash, 80) === hash) {
      return {
        ok: true,
        idempotent: true,
        record: {
          ...rec,
          quotation_snapshots: existingMap,
          quotation_revision: revision,
        },
      };
    }
    return { ok: false, reason: LIMOUSINE_QUOTATION_SNAPSHOT_CONFLICT };
  }
  return {
    ok: true,
    idempotent: false,
    record: {
      ...rec,
      quotation_snapshots: { ...existingMap, [key]: snap },
      quotation_revision: revision,
    },
  };
}

export function buildLimousineAcceptanceBindingFromSnapshot(record, snapshot) {
  const rec = asObject(record);
  const snap = asObject(snapshot);
  const request = asObject(snap.request_snapshot);
  const vehicle = asObject(snap.vehicle_snapshot);
  const offer = asObject(snap.offer_snapshot);
  const totals = asObject(snap.totals_snapshot);
  return {
    tenant_id: safeText(rec.tenant_id, 96),
    company_id: safeText(rec.company_id, 96),
    quote_request_id: safeText(rec.quote_request_id, 120),
    quote_revision: toInt(rec.revision) ?? 0,
    ...(toInt(totals.entered_amount_cents) != null
      ? { entered_amount_cents: toInt(totals.entered_amount_cents) }
      : {}),
    ...(toInt(totals.total_ex_vat_cents) != null
      ? { total_ex_vat_cents: toInt(totals.total_ex_vat_cents) }
      : {}),
    ...(toInt(totals.vat_amount_cents) != null
      ? { vat_amount_cents: toInt(totals.vat_amount_cents) }
      : {}),
    total_incl_vat_cents: toInt(totals.total_incl_vat_cents) ?? 0,
    currency: normalizeCurrency(totals.currency),
    ...(totals.vat_rate != null && totals.vat_rate !== ""
      ? { vat_rate: Number(totals.vat_rate) || 0 }
      : {}),
    vat_treatment: safeText(totals.vat_treatment, 16),
    offer_id: safeText(request.offer_id, 64),
    offer_source_revision: toInt(snap.offer_source_revision) ?? 0,
    pricing_section_revision: toInt(snap.pricing_section_revision) ?? 0,
    itinerary_fingerprint: safeText(request.itinerary_fingerprint, 64),
    service_class_id: safeText(request.service_class_id, 64),
    vehicle_id: safeText(vehicle.vehicle_id || request.vehicle_id, 96),
    selected_extra_ids: Array.isArray(request.selected_extra_ids)
      ? [...request.selected_extra_ids].sort()
      : [],
    mobilisation_disclosure: asObject(offer.mobilisation_disclosure),
    terms_revision: toInt(snap.terms_revision ?? offer.terms_revision) ?? 0,
    expires_at: safeText(snap.expires_at ?? offer.expires_at, 40),
    quotation_revision: toInt(snap.quote_revision) ?? 0,
    quotation_content_hash: safeText(snap.content_hash, 80),
  };
}

export function quotationSnapshotContainsForbiddenKey(value) {
  const hits = [];
  const walk = (node, path) => {
    if (!node || typeof node !== "object") return;
    if (Array.isArray(node)) {
      node.forEach((item, i) => walk(item, `${path}[${i}]`));
      return;
    }
    for (const [key, child] of Object.entries(node)) {
      const token = String(key || "").trim();
      if (LIMOUSINE_QUOTATION_FORBIDDEN_SOURCE_KEYS.includes(token)) {
        if (token === "email" && path.includes("seller_snapshot")) {
          // Seller contact_email is stored under contact_email, not email.
          hits.push(`${path}.${token}`);
        } else if (token !== "email" && token !== "phone") {
          hits.push(`${path}.${token}`);
        } else if (token === "email" || token === "phone") {
          if (!path.includes("seller_snapshot")) hits.push(`${path}.${token}`);
        }
      }
      walk(child, path ? `${path}.${token}` : token);
    }
  };
  walk(value, "");
  return hits;
}

export function assertLimousineQuotationSnapshotAllowlisted(snapshot) {
  const snap = asObject(snapshot);
  const hits = quotationSnapshotContainsForbiddenKey(snap);
  const forbiddenTop = [
    "status_ref",
    "acceptance_reference",
    "billing_customer",
    "invoice_intent",
    "invoice_number",
    "source_booking_id",
    "customer_fingerprint",
  ];
  for (const key of forbiddenTop) {
    if (Object.prototype.hasOwnProperty.call(snap, key)) hits.push(key);
  }
  return hits;
}
