/* Canonical Fluxidi payment-method source-of-truth (pure).
 *
 * Single resolver for booking / Mollie / PDF / Billit / Document Core mutable
 * payment metadata. Never invents amounts, VAT, invoice numbers, or status.
 *
 * Precedence when resolving:
 *   1) provider-confirmed concrete method (e.g. Mollie payment.method)
 *   2) existing concrete booking/payment method
 *   3) customer-chosen method
 *   4) generic online_payment + mollie stays category=online (never bank transfer)
 *
 * A less-specific value must never overwrite a more-specific concrete method.
 */

import { safeStr } from "./parsing_utils.js";

export const PAYMENT_METHOD_TRUTH_VERSION = "payment_method_truth_v1";

/** @typedef {"online"|"cash"|"card_in_vehicle"|"bank_transfer"|"qr"|"invoice"|"unknown"} PaymentCategory */
/** @typedef {"mollie"|"manual"|"none"|"unknown"} PaymentProviderId */

export const CANONICAL_PAYMENT_METHOD_IDS = Object.freeze([
  "cash",
  "qr_code",
  "in_vehicle_card",
  "invoice",
  "online_payment",
  "ideal",
  "bancontact",
  "bancontact_qr",
  "kbc_cbc",
  "belfius",
  "card_payment",
  "apple_pay",
  "google_pay",
  "paypal",
  "cartes_bancaires",
  "bank_transfer_bacs",
  "payconiq_wero",
  "bizum",
  "tikkie",
]);

const KNOWN = new Set(CANONICAL_PAYMENT_METHOD_IDS);

const ALIASES = Object.freeze({
  qr: "qr_code",
  epc_qr: "qr_code",
  online: "online_payment",
  online_payments: "online_payment",
  mollie: "online_payment",
  card: "card_payment",
  cards: "card_payment",
  creditcard: "card_payment",
  credit_card: "card_payment",
  debitcard: "card_payment",
  applepay: "apple_pay",
  googlepay: "google_pay",
  carte_bancaire: "cartes_bancaires",
  cartes_bancaire: "cartes_bancaires",
  carte_bancaires: "cartes_bancaires",
  cartesbancaires: "cartes_bancaires",
  cartes_bancaires_cb: "cartes_bancaires",
  cb: "cartes_bancaires",
  payconiq: "payconiq_wero",
  payconiq_by_bancontact: "payconiq_wero",
  wero: "payconiq_wero",
  bancontactqr: "bancontact_qr",
  bancontact_pay_qr: "bancontact_qr",
  payconiq_qr: "bancontact_qr",
  kbc: "kbc_cbc",
  cbc: "kbc_cbc",
  kbc_cbc_payment_button: "kbc_cbc",
  kbc_payment_button: "kbc_cbc",
  cbc_payment_button: "kbc_cbc",
  belfius_pay: "belfius",
  belfius_direct_net: "belfius",
  belfius_pay_button: "belfius",
  bacs: "bank_transfer_bacs",
  bank_transfer: "bank_transfer_bacs",
  bankoverschrijving: "bank_transfer_bacs",
  wire_transfer: "bank_transfer_bacs",
  sepa: "bank_transfer_bacs",
  cash_in_car: "in_vehicle_card",
  in_car: "in_vehicle_card",
  in_vehicle: "in_vehicle_card",
  manual: "in_vehicle_card",
  pay_in_car: "in_vehicle_card",
});

/** Methods that are concrete (more specific than online_payment). */
const CONCRETE_ONLINE = new Set([
  "ideal",
  "bancontact",
  "bancontact_qr",
  "kbc_cbc",
  "belfius",
  "card_payment",
  "apple_pay",
  "google_pay",
  "paypal",
  "cartes_bancaires",
  "payconiq_wero",
  "bizum",
  "tikkie",
]);

const GENERIC_ONLINE = new Set(["online_payment", "online", "mollie"]);

const BANK_TRANSFER = new Set([
  "bank_transfer_bacs",
  "bank_transfer",
  "sepa",
  "wire_transfer",
]);

const LABEL_NL = Object.freeze({
  cash: "Contant",
  qr_code: "QR-betaling",
  in_vehicle_card: "Betaling in de wagen",
  invoice: "Factuur",
  online_payment: "Online betaling",
  ideal: "iDEAL",
  bancontact: "Bancontact",
  bancontact_qr: "Bancontact",
  kbc_cbc: "KBC/CBC",
  belfius: "Belfius",
  card_payment: "Kaart",
  apple_pay: "Apple Pay",
  google_pay: "Google Pay",
  paypal: "PayPal",
  cartes_bancaires: "Cartes Bancaires",
  bank_transfer_bacs: "Bankoverschrijving",
  payconiq_wero: "Payconiq/Wero",
  bizum: "Bizum",
  tikkie: "Tikkie",
});

function _norm(value, max = 80) {
  return safeStr(value, max);
}

function _token(raw, max = 80) {
  let token = _norm(raw, max).toLowerCase().replace(/-/g, "_");
  if (!token) return "";
  token = token.replace(/[^a-z0-9_]/g, "");
  return token.slice(0, max);
}

export function normalizePaymentMethodId(raw) {
  const token = _token(raw, 80);
  if (!token) return "";
  if (ALIASES[token]) return ALIASES[token];
  if (KNOWN.has(token)) return token;
  // Bounded unknown future token — keep sanitized form.
  return token.slice(0, 40);
}

export function isKnownPaymentMethodId(methodId) {
  return KNOWN.has(_norm(methodId, 40));
}

export function isConcretePaymentMethodId(methodId) {
  const id = normalizePaymentMethodId(methodId);
  if (!id) return false;
  if (GENERIC_ONLINE.has(id) || id === "online_payment") return false;
  if (CONCRETE_ONLINE.has(id)) return true;
  if (id === "cash" || id === "qr_code" || id === "in_vehicle_card") return true;
  if (id === "invoice" || BANK_TRANSFER.has(id) || id === "bank_transfer_bacs") {
    return true;
  }
  // Unknown future tokens are treated as concrete-enough to not be wiped by
  // a generic online_payment retry.
  return !GENERIC_ONLINE.has(id) && id !== "online_payment";
}

export function isGenericOnlinePaymentMethodId(methodId) {
  const id = normalizePaymentMethodId(methodId);
  return id === "online_payment" || GENERIC_ONLINE.has(id);
}

export function isBankTransferPaymentMethodId(methodId) {
  const id = normalizePaymentMethodId(methodId);
  return id === "bank_transfer_bacs" || BANK_TRANSFER.has(id);
}

export function paymentMethodCategoryFor(methodId, provider = "") {
  const id = normalizePaymentMethodId(methodId);
  const prov = _token(provider, 40);
  if (!id && prov === "mollie") return "online";
  if (id === "cash") return "cash";
  if (id === "in_vehicle_card") return "card_in_vehicle";
  if (id === "qr_code") return "qr";
  if (id === "invoice") return "invoice";
  if (isBankTransferPaymentMethodId(id)) return "bank_transfer";
  if (
    id === "online_payment" ||
    CONCRETE_ONLINE.has(id) ||
    prov === "mollie"
  ) {
    return "online";
  }
  if (!id) return "unknown";
  // Unknown future methods: if provider is mollie → online, else unknown.
  if (prov === "mollie") return "online";
  return "unknown";
}

export function paymentProviderFor(methodId, explicitProvider = "") {
  const prov = _token(explicitProvider, 40);
  if (prov === "mollie" || prov === "manual" || prov === "none") return prov;
  const id = normalizePaymentMethodId(methodId);
  if (
    CONCRETE_ONLINE.has(id) ||
    id === "online_payment" ||
    id === "bancontact" ||
    id === "ideal"
  ) {
    // online_payment may be manual bucket in catalog, but when paired with
    // mollie elsewhere we keep explicit provider. Default for pure online PSP
    // ids is mollie.
    if (CONCRETE_ONLINE.has(id)) return "mollie";
  }
  if (
    id === "cash" ||
    id === "qr_code" ||
    id === "in_vehicle_card" ||
    id === "invoice" ||
    id === "bank_transfer_bacs" ||
    id === "online_payment"
  ) {
    return prov || "manual";
  }
  return prov || "unknown";
}

export function formatPaymentMethodLabelNl(methodId) {
  const id = normalizePaymentMethodId(methodId);
  if (!id) return "";
  if (LABEL_NL[id]) return LABEL_NL[id];
  return id.replace(/_/g, " ");
}

/**
 * Map Mollie API method tokens onto Fluxidi canonical method_id.
 */
export function mapMollieProviderMethodToCanonical(providerMethod) {
  const raw = _token(providerMethod, 40);
  if (!raw) return "";
  const mapped = normalizePaymentMethodId(raw);
  // Mollie uses creditcard / applepay / googlepay / kbc
  if (raw === "creditcard") return "card_payment";
  if (raw === "applepay") return "apple_pay";
  if (raw === "googlepay") return "google_pay";
  if (raw === "kbc") return "kbc_cbc";
  return mapped;
}

/**
 * Specificity rank: higher wins. Generic online is lowest among online.
 */
export function paymentMethodSpecificity(methodId) {
  const id = normalizePaymentMethodId(methodId);
  if (!id) return 0;
  if (isGenericOnlinePaymentMethodId(id)) return 1;
  if (id === "invoice") return 2;
  if (isConcretePaymentMethodId(id)) return 5;
  return 3; // unknown bounded token
}

/**
 * Merge candidate into existing without letting generic overwrite concrete.
 */
export function mergePaymentMethodIds(existingMethodId, candidateMethodId) {
  const existing = normalizePaymentMethodId(existingMethodId);
  const candidate = normalizePaymentMethodId(candidateMethodId);
  if (!candidate) return existing || "";
  if (!existing) return candidate;
  if (existing === candidate) return existing;
  const eRank = paymentMethodSpecificity(existing);
  const cRank = paymentMethodSpecificity(candidate);
  if (cRank > eRank) return candidate;
  // Equal rank: prefer concrete over generic; otherwise keep existing (idempotent).
  if (
    isGenericOnlinePaymentMethodId(existing) &&
    isConcretePaymentMethodId(candidate)
  ) {
    return candidate;
  }
  return existing;
}

/**
 * Build the canonical payment method record.
 */
export function buildPaymentMethodTruthRecord({
  methodId = "",
  category = "",
  provider = "",
  providerMethod = "",
  status = "",
  paidAt = "",
  providerRef = "",
  labelNl = "",
} = {}) {
  const normalizedMethod = normalizePaymentMethodId(methodId);
  const provMethod = _token(providerMethod, 40);
  const resolvedFromProvider = provMethod
    ? mapMollieProviderMethodToCanonical(provMethod)
    : "";
  const method_id =
    mergePaymentMethodIds(normalizedMethod, resolvedFromProvider) ||
    normalizedMethod ||
    resolvedFromProvider ||
    "";
  const provider_id = paymentProviderFor(method_id, provider);
  const category_id =
    _token(category, 40) ||
    paymentMethodCategoryFor(method_id, provider_id);
  const status_id = _token(status, 40);
  const paid_at = _norm(paidAt, 40) || null;
  const provider_ref = _norm(providerRef, 128) || null;
  return {
    method_id: method_id || null,
    category: category_id || "unknown",
    provider: provider_id || "unknown",
    provider_method: provMethod || null,
    status: status_id || null,
    paid_at,
    provider_ref,
    label_nl:
      _norm(labelNl, 80) ||
      formatPaymentMethodLabelNl(method_id) ||
      "",
    version: PAYMENT_METHOD_TRUTH_VERSION,
  };
}

/**
 * Resolve from layered inputs with documented precedence.
 */
export function resolvePaymentMethodTruth({
  providerConfirmedMethod = "",
  providerMethod = "",
  bookingMethod = "",
  chosenMethod = "",
  provider = "",
  status = "",
  paidAt = "",
  providerRef = "",
} = {}) {
  const fromProviderConfirmed = normalizePaymentMethodId(
    providerConfirmedMethod || mapMollieProviderMethodToCanonical(providerMethod),
  );
  const fromBooking = normalizePaymentMethodId(bookingMethod);
  const fromChosen = normalizePaymentMethodId(chosenMethod);

  let method_id = "";
  // 1) provider-confirmed concrete wins
  if (fromProviderConfirmed && isConcretePaymentMethodId(fromProviderConfirmed)) {
    method_id = fromProviderConfirmed;
  } else if (fromBooking && isConcretePaymentMethodId(fromBooking)) {
    method_id = fromBooking;
  } else if (fromChosen && isConcretePaymentMethodId(fromChosen)) {
    method_id = fromChosen;
  } else {
    method_id =
      mergePaymentMethodIds(
        mergePaymentMethodIds(fromBooking, fromChosen),
        fromProviderConfirmed,
      ) ||
      fromProviderConfirmed ||
      fromBooking ||
      fromChosen ||
      "";
  }

  // Historical online_payment + mollie stays online category, never bank transfer.
  const prov = _token(provider, 40) || paymentProviderFor(method_id, provider);
  if (
    (!method_id || isGenericOnlinePaymentMethodId(method_id)) &&
    prov === "mollie"
  ) {
    method_id = method_id || "online_payment";
  }

  return buildPaymentMethodTruthRecord({
    methodId: method_id,
    provider: prov,
    providerMethod: providerMethod || providerConfirmedMethod,
    status,
    paidAt,
    providerRef,
  });
}

/**
 * Extract resolver inputs from a booking/payment-shaped object.
 */
export function resolvePaymentMethodTruthFromRecord(
  rec,
  { molliePayment = null, chosenMethod = "" } = {},
) {
  const record = rec && typeof rec === "object" ? rec : {};
  const booking =
    record.booking && typeof record.booking === "object" ? record.booking : {};
  const mollieBlock =
    (molliePayment && typeof molliePayment === "object" && molliePayment) ||
    (record.mollie && typeof record.mollie === "object" ? record.mollie : null) ||
    (booking.mollie && typeof booking.mollie === "object" ? booking.mollie : null);

  const bookingMethod =
    record.payment_method ??
    record.paymentMethod ??
    booking.payment_method ??
    booking.paymentMethod ??
    "";
  const provider =
    record.payment_provider ??
    record.paymentProvider ??
    booking.payment_provider ??
    booking.paymentProvider ??
    record.payment_mode ??
    record.paymentMode ??
    "";
  const providerMethod =
    mollieBlock?.method ??
    mollieBlock?.payment_method ??
    record.mollie_method ??
    record.mollieMethod ??
    booking.mollie_method ??
    "";
  const status =
    record.payment_status ??
    record.paymentStatus ??
    booking.payment_status ??
    mollieBlock?.status ??
    "";
  const paidAt =
    record.paid_at ?? record.paidAt ?? booking.paid_at ?? booking.paidAt ?? "";
  const providerRef =
    record.payment_id ??
    record.paymentId ??
    mollieBlock?.payment_id ??
    mollieBlock?.id ??
    mollieBlock?.paymentId ??
    "";

  return resolvePaymentMethodTruth({
    providerConfirmedMethod: mapMollieProviderMethodToCanonical(providerMethod),
    providerMethod,
    bookingMethod,
    chosenMethod,
    provider,
    status,
    paidAt,
    providerRef,
  });
}

/**
 * Apply resolved truth onto a booking record in-memory.
 * Never changes amounts/VAT. Never downgrades concrete method to generic.
 * Does not change payment_status unless status is provided and currently empty
 * — callers should pass status only for refine paths that already own status.
 */
export function applyPaymentMethodTruthToBookingRecord(
  rec,
  truth,
  { refineOnly = true } = {},
) {
  if (!rec || typeof rec !== "object" || Array.isArray(rec)) {
    return { ok: false, mutated: false, error: "missing_record" };
  }
  if (!truth || typeof truth !== "object") {
    return { ok: false, mutated: false, error: "missing_truth" };
  }
  const nextMethod = normalizePaymentMethodId(truth.method_id);
  if (!nextMethod) {
    return { ok: true, mutated: false, reason: "no_method" };
  }
  const existing = normalizePaymentMethodId(
    rec.payment_method ?? rec.paymentMethod,
  );
  const merged = mergePaymentMethodIds(existing, nextMethod);
  if (refineOnly && existing && merged === existing && existing === nextMethod) {
    // Still allow provider_method / mollie.method enrichment below.
  } else if (refineOnly && existing && paymentMethodSpecificity(existing) > paymentMethodSpecificity(nextMethod)) {
    // Keep existing concrete; still may enrich provider_method.
  }

  let mutated = false;
  if (merged && merged !== existing) {
    rec.payment_method = merged;
    rec.paymentMethod = merged;
    mutated = true;
  } else if (merged && (rec.payment_method !== merged || rec.paymentMethod !== merged)) {
    rec.payment_method = merged;
    rec.paymentMethod = merged;
    mutated = true;
  }

  const prov = _token(truth.provider, 40);
  if (prov && prov !== "unknown") {
    if (rec.payment_provider !== prov || rec.paymentProvider !== prov) {
      // Do not demote mollie → manual on refine.
      const cur = _token(rec.payment_provider ?? rec.paymentProvider, 40);
      if (!(cur === "mollie" && prov === "manual")) {
        rec.payment_provider = prov;
        rec.paymentProvider = prov;
        mutated = true;
      }
    }
  }

  const provMethod = _token(truth.provider_method, 40);
  if (provMethod) {
    if (rec.mollie_method !== provMethod || rec.mollieMethod !== provMethod) {
      rec.mollie_method = provMethod;
      rec.mollieMethod = provMethod;
      mutated = true;
    }
    if (!rec.mollie || typeof rec.mollie !== "object") {
      rec.mollie = {};
    }
    if (rec.mollie.method !== provMethod) {
      rec.mollie.method = provMethod;
      mutated = true;
    }
  }

  if (rec.booking && typeof rec.booking === "object") {
    if (merged) {
      if (
        rec.booking.payment_method !== merged ||
        rec.booking.paymentMethod !== merged
      ) {
        rec.booking.payment_method = merged;
        rec.booking.paymentMethod = merged;
        mutated = true;
      }
    }
  }

  return {
    ok: true,
    mutated,
    method_id: merged || existing || null,
    truth: buildPaymentMethodTruthRecord({
      methodId: merged || existing,
      provider: rec.payment_provider,
      providerMethod: provMethod || truth.provider_method,
      status: truth.status || rec.payment_status,
      paidAt: truth.paid_at || rec.paid_at,
      providerRef: truth.provider_ref || rec.payment_id,
    }),
  };
}

/**
 * Billit PaymentMethod mapping.
 * Wired ONLY for real bank transfers. Online PSP → omit (null).
 * No specific non-Wired Billit enums are confirmed in this integration.
 */
export function mapPaymentMethodTruthToBillitPaymentMethod(truthOrMethodId) {
  const truth =
    truthOrMethodId && typeof truthOrMethodId === "object"
      ? truthOrMethodId
      : buildPaymentMethodTruthRecord({ methodId: truthOrMethodId });
  const id = normalizePaymentMethodId(truth.method_id);
  const category = truth.category || paymentMethodCategoryFor(id, truth.provider);

  if (category === "bank_transfer" || isBankTransferPaymentMethodId(id)) {
    return "Wired";
  }
  // Explicitly never Wired for online / cash / qr / in-vehicle / invoice / unknown.
  return null;
}

export function buildBillitPaymentInternalInfoFromTruth(truth) {
  if (!truth || typeof truth !== "object") return null;
  const provider = _norm(truth.provider, 40) || "unknown";
  const method = _norm(truth.method_id, 80) || "unknown";
  const ref = _norm(truth.provider_ref, 128);
  const refPreview = ref
    ? ref.length <= 8
      ? ref
      : `${ref.slice(0, 4)}…${ref.slice(-2)}`
    : null;
  const category = _norm(truth.category, 40) || "unknown";
  return refPreview
    ? `Fluxidi paid ${provider}/${method} cat=${category} ref=${refPreview}`
    : `Fluxidi paid ${provider}/${method} cat=${category}`;
}

/**
 * Mutable Document Core payment/reconciliation metadata (never hashed).
 */
export function buildDocumentPaymentMethodMetadata(truth, { updatedAt = null } = {}) {
  if (!truth || typeof truth !== "object") return null;
  const method_id = normalizePaymentMethodId(truth.method_id);
  if (!method_id && !truth.provider) return null;
  return {
    version: PAYMENT_METHOD_TRUTH_VERSION,
    method_id: method_id || null,
    category: truth.category || paymentMethodCategoryFor(method_id, truth.provider),
    provider: truth.provider || null,
    provider_method: _token(truth.provider_method, 40) || null,
    status: _token(truth.status, 40) || null,
    paid_at: _norm(truth.paid_at, 40) || null,
    provider_ref: _norm(truth.provider_ref, 128) || null,
    label_nl: _norm(truth.label_nl, 80) || formatPaymentMethodLabelNl(method_id),
    updated_at: _norm(updatedAt, 40) || null,
  };
}

/**
 * Merge mutable payment metadata onto a document registry-shaped object.
 * Never touches immutable_snapshot / content_hash / totals / numbers.
 */
export function mergeDocumentPaymentMethodMetadata(existingRecord, truth) {
  const meta = buildDocumentPaymentMethodMetadata(truth, {
    updatedAt: new Date().toISOString(),
  });
  if (!meta) {
    return {
      ok: false,
      error: "missing_payment_truth",
      record: existingRecord,
    };
  }
  const base =
    existingRecord && typeof existingRecord === "object" && !Array.isArray(existingRecord)
      ? { ...existingRecord }
      : {};
  const prev =
    base.payment_method_truth && typeof base.payment_method_truth === "object"
      ? base.payment_method_truth
      : {};
  const mergedMethod = mergePaymentMethodIds(prev.method_id, meta.method_id);
  base.payment_method_truth = {
    ...prev,
    ...meta,
    method_id: mergedMethod || meta.method_id,
    label_nl: formatPaymentMethodLabelNl(mergedMethod || meta.method_id),
    // Preserve earlier paid_at if new is empty.
    paid_at: meta.paid_at || prev.paid_at || null,
    provider_ref: meta.provider_ref || prev.provider_ref || null,
    provider_method: meta.provider_method || prev.provider_method || null,
  };
  // Never rewrite immutable fields — they ride along via spread only.
  return { ok: true, record: base, payment_method_truth: base.payment_method_truth };
}

/** Fixture helper matching street_1785684244820_97ofs7tm shape. */
export function fixtureOnlinePaymentMollieBookingTruth() {
  return resolvePaymentMethodTruth({
    bookingMethod: "online_payment",
    provider: "mollie",
    status: "paid",
    paidAt: "2026-08-02T15:25:37.740Z",
    providerRef: "tr_owcLVpyhvpKqoTx2RipUJ",
  });
}
