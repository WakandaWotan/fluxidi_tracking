// CONSUMER-BILLIT-SERVER-CONTRACT-1
//
// Pure decision model for registering private/consumer ride revenue in Billit.
// Billit live create only supports OrderType "Invoice" (Income). Fluxidi may
// still present this as "Particuliere verkoop" / "Ontvangstbewijs" with Peppol
// not applicable. Never invent a Billit document type that the API does not
// expose in this codebase.

export const CONSUMER_SALE_KIND = "consumer_sale";
export const CONSUMER_SALE_BILLIT_ORDER_TYPE = "Invoice";
export const CONSUMER_SALE_DOCUMENT_TYPE = "invoice";

function _str(v, max = 160) {
  return String(v ?? "").trim().slice(0, max);
}

function _lower(v, max = 160) {
  return _str(v, max).toLowerCase();
}

function _asObject(v) {
  return v && typeof v === "object" && !Array.isArray(v) ? v : {};
}

function _positiveEuro(raw) {
  if (raw && typeof raw === "object" && !Array.isArray(raw)) {
    if (raw.value != null) return _positiveEuro(raw.value);
    if (raw.amount != null) return _positiveEuro(raw.amount);
  }
  const n = Number(raw);
  if (!Number.isFinite(n) || !(n > 0)) return null;
  return Math.round(n * 100) / 100;
}

function _recordSources(rec) {
  const record = _asObject(rec);
  const booking = _asObject(record.booking);
  const nested = _asObject(record.record);
  return [record, booking, nested];
}

export function isStreetDirectBookingRecord(rec) {
  const record = _asObject(rec);
  const source = _lower(
    record.source ??
      record.booking_source ??
      record.booking?.source ??
      record.booking?.booking_source,
    64,
  );
  const rideType = _lower(record.ride_type ?? record.booking?.ride_type, 64);
  const id = _lower(record.booking_id ?? record.bookingId, 160);
  return source === "street_ride" || rideType === "direct" || id.startsWith("street_");
}

export function isBookingCompletedForConsumerSale(rec) {
  const record = _asObject(rec);
  const status = _lower(
    record.status ?? record.booking_status ?? record.booking?.status,
    40,
  );
  return status === "completed" || status === "complete";
}

export function hasBusinessInvoiceIntent(rec) {
  const record = _asObject(rec);
  const intent = _lower(
    record.invoice_intent ??
      record.invoiceIntent ??
      record.booking?.invoice_intent ??
      record.booking?.invoiceIntent,
    64,
  );
  if (intent === "business_invoice") return true;
  const requested =
    record.invoice_requested === true ||
    record.invoiceRequested === true ||
    record.booking?.invoice_requested === true;
  const customerType = _lower(
    record.billing_customer_snapshot?.customer_type ??
      record.billingCustomerSnapshot?.customer_type ??
      record.booking?.billing_customer_snapshot?.customer_type,
    40,
  );
  if (requested && customerType === "business") return true;
  return false;
}

/**
 * PLANNED-CONSUMER-CASH-DOCUMENT-BILLIT-P0-3:
 * Soft/incomplete business flags (intent=business_invoice without a
 * meaningful billing customer / VAT) must not block private consumer-sale
 * issuance. Field evidence 2026-08-165: business_detected + invoice_intent
 * set, but no billing_customer_snapshot → Document Core skipped with
 * billit_auto_billing_customer_missing and consumer sale skipped forever.
 */
export function hasMeaningfulBusinessBillingCustomer(rec) {
  const record = _asObject(rec);
  const snapshots = [
    record.billing_customer_snapshot,
    record.billingCustomerSnapshot,
    record.booking?.billing_customer_snapshot,
    record.booking?.billingCustomerSnapshot,
  ].filter((v) => v && typeof v === "object" && !Array.isArray(v));
  for (const snap of snapshots) {
    const vat = _str(snap.vat_number ?? snap.vatNumber, 64);
    const legal = _str(snap.legal_name ?? snap.legalName, 240);
    const display = _str(snap.display_name ?? snap.displayName, 240);
    const customerType = _lower(snap.customer_type ?? snap.customerType, 40);
    if (vat) return true;
    if (customerType === "business" && (legal || display)) return true;
  }
  const topVat = _str(
    record.vat_number ??
      record.vatNumber ??
      record.booking?.vat_number ??
      record.booking?.vatNumber ??
      record.business?.vat_number,
    64,
  );
  return !!topVat;
}

export function canIssueBusinessInvoiceFromRecord(rec) {
  return hasBusinessInvoiceIntent(rec) && hasMeaningfulBusinessBillingCustomer(rec);
}

export function isConsumerSaleEligibleRecord(rec) {
  if (!rec || typeof rec !== "object") return false;
  // Only a real, issuable business invoice owns the revenue document.
  if (canIssueBusinessInvoiceFromRecord(rec)) return false;
  if (!isBookingCompletedForConsumerSale(rec)) return false;
  return true;
}

export function resolveConsumerSaleAmount(rec, { legId = null, legType = null } = {}) {
  const record = _asObject(rec);
  const currency = (
    _str(record.currency ?? record.booking?.currency, 8) || "EUR"
  ).toUpperCase();
  if (currency !== "EUR") {
    return { ok: false, error: "unsupported_currency", currency };
  }

  if (isStreetDirectBookingRecord(record)) {
    if (
      record.street_ride_fare_finalized !== true &&
      record.streetRideFareFinalized !== true
    ) {
      return { ok: false, error: "street_fare_not_finalized", currency };
    }
    const euro = _positiveEuro(
      record.price_incl_vat ??
        record.priceInclVat ??
        record.booking?.price_incl_vat,
    );
    if (euro == null) {
      return { ok: false, error: "amount_unavailable", currency };
    }
    return {
      ok: true,
      currency,
      cents: Math.round(euro * 100),
      value: euro.toFixed(2),
      source: "street_finalized",
    };
  }

  const wantedLeg = _lower(legType, 32);
  const wantLegId = _str(legId, 200);
  const sources = _recordSources(record);
  let euro = null;
  let source = null;

  for (const src of sources) {
    const legPrice = _positiveEuro(src.leg_price_incl_vat ?? src.legPriceInclVat);
    if (legPrice != null) {
      euro = legPrice;
      source = "leg_price_incl_vat";
      break;
    }
  }
  // Planned bookings often only stamp price on operational_legs / quote.
  if (euro == null) {
    const legs = [
      ...(Array.isArray(record.operational_legs) ? record.operational_legs : []),
      ...(Array.isArray(record.operationalLegs) ? record.operationalLegs : []),
      ...(Array.isArray(record.booking?.operational_legs)
        ? record.booking.operational_legs
        : []),
    ].filter((entry) => entry && typeof entry === "object");
    const match =
      (wantLegId
        ? legs.find(
            (entry) => _str(entry.leg_id ?? entry.legId, 200) === wantLegId,
          )
        : null) ||
      (wantedLeg
        ? legs.find(
            (entry) => _lower(entry.leg_type ?? entry.legType, 32) === wantedLeg,
          )
        : null) ||
      legs[0] ||
      null;
    const legEuro = _positiveEuro(
      match?.price_incl_vat ?? match?.priceInclVat ?? match?.leg_price_incl_vat,
    );
    if (legEuro != null) {
      euro = legEuro;
      source = "operational_leg_price";
    }
  }
  if (euro == null && wantedLeg === "return") {
    for (const src of sources) {
      const p = _positiveEuro(src.price_incl_vat_return ?? src.priceInclVatReturn);
      if (p != null) {
        euro = p;
        source = "price_incl_vat_return";
        break;
      }
    }
  }
  if (euro == null && wantedLeg !== "return") {
    for (const src of sources) {
      const p = _positiveEuro(src.price_incl_vat_main ?? src.priceInclVatMain);
      if (p != null) {
        euro = p;
        source = "price_incl_vat_main";
        break;
      }
    }
  }
  if (euro == null) {
    for (const src of sources) {
      const p = _positiveEuro(src.price_incl_vat ?? src.priceInclVat);
      if (p != null) {
        euro = p;
        source = "price_incl_vat";
        break;
      }
    }
  }
  if (euro == null) {
    const quote = _asObject(record.quote);
    const quoteEuro = _positiveEuro(
      quote.pricing_main?.price_incl_vat ??
        quote.pricing?.price_incl_vat ??
        quote.price_incl_vat,
    );
    if (quoteEuro != null) {
      euro = quoteEuro;
      source = "quote_price_incl_vat";
    }
  }
  if (euro == null) {
    const paidToken = _lower(
      record.payment_status ?? record.paymentStatus ?? record.booking?.payment_status,
      40,
    );
    if (paidToken === "paid") {
      const paidEuro = _positiveEuro(
        record.payment_amount ??
          record.paymentAmount ??
          record.booking?.payment_amount,
      );
      if (paidEuro != null) {
        euro = paidEuro;
        source = "payment_amount_paid";
      }
    }
  }
  if (euro == null) {
    return { ok: false, error: "amount_unavailable", currency };
  }
  return {
    ok: true,
    currency,
    cents: Math.round(euro * 100),
    value: euro.toFixed(2),
    source,
  };
}

function _normalizeVatRatePercent(raw) {
  const n = Number(raw);
  if (!Number.isFinite(n) || n < 0) return null;
  // Quote breakdowns often store 0.06; snapshots store 6.
  if (n > 0 && n <= 1) return Math.round(n * 10000) / 100;
  return n;
}

export function resolveConsumerSaleVatFromSnapshot(rec, companyTaxSnapshot = null) {
  const record = _asObject(rec);
  const tax = _asObject(companyTaxSnapshot);
  const quote = _asObject(record.quote);
  const candidates = [
    record.vat_rate_percent,
    record.vatRatePercent,
    record.booking?.vat_rate_percent,
    quote.pricing_main?.breakdown?.vat_rate,
    quote.pricing?.vat_rate,
    quote.pricing_profile?.vat_rate,
    tax.vat_rate_percent,
    tax.default_vat_rate_percent,
    tax.standard_vat_rate_percent,
  ];
  let rate = null;
  let source = "company_tax_snapshot";
  for (let i = 0; i < candidates.length; i += 1) {
    const normalized = _normalizeVatRatePercent(candidates[i]);
    if (normalized == null) continue;
    rate = normalized;
    if (i <= 2) source = "booking_snapshot";
    else if (i <= 5) source = "quote_vat_snapshot";
    else source = "company_tax_snapshot";
    break;
  }
  if (rate == null) {
    return { ok: false, error: "vat_rate_unavailable" };
  }
  // Never invent 21 — only accept a finite rate from an existing snapshot.
  return {
    ok: true,
    vat_rate_percent: rate,
    source,
  };
}

export function buildConsumerSaleIdempotencyKey({
  tenantId,
  companyId,
  bookingId,
  legId = null,
} = {}) {
  const t = _str(tenantId, 96);
  const c = _str(companyId, 96);
  const b = _str(bookingId, 160);
  if (!t || !c || !b) return null;
  const leg = _str(legId, 160) || "main";
  return `inv-consumer:${t}:${c}:${b}:${leg}:${CONSUMER_SALE_KIND}:v1`;
}

export function consumerSalePeppolPolicy() {
  return {
    peppol_applicable: false,
    peppol_required: false,
    peppol_sent: false,
    label_key: "peppolNotApplicable",
    suppress_missing_endpoint_warning: true,
    suppress_settings_required_warning: true,
    suppress_send_action: true,
  };
}

export function consumerSalePresentation() {
  return {
    sale_kind: CONSUMER_SALE_KIND,
    document_label_key: "consumerSale",
    document_label_nl: "Particuliere verkoop",
    receipt_label_nl: "Ontvangstbewijs",
    status_key: "registeredInBillit",
    status_nl: "Geregistreerd in Billit",
    // Internal Billit OrderType remains Invoice; UI must never say "Factuur".
    billit_order_type: CONSUMER_SALE_BILLIT_ORDER_TYPE,
    document_type: CONSUMER_SALE_DOCUMENT_TYPE,
    forbid_invoice_label: true,
    peppol: consumerSalePeppolPolicy(),
  };
}

/**
 * Gate for creating/registering a consumer Billit sale after completion.
 */
export function resolveConsumerSaleRegistrationGate({
  completed = false,
  businessInvoiceIntent = false,
  businessInvoiceExists = false,
  businessInvoiceInFlight = false,
  amountCents = 0,
  existingConsumerDocumentId = "",
  existingConsumerBillitOrderId = "",
  consumerSaleSuperseded = false,
} = {}) {
  if (businessInvoiceIntent || businessInvoiceExists || businessInvoiceInFlight) {
    return { action: "none", reason: "business_invoice_active" };
  }
  if (consumerSaleSuperseded) {
    return { action: "none", reason: "consumer_sale_superseded" };
  }
  if (!completed) {
    return { action: "none", reason: "not_completed" };
  }
  if (!Number.isInteger(amountCents) || !(amountCents > 0)) {
    return { action: "none", reason: "invalid_or_zero_amount" };
  }
  if (_str(existingConsumerBillitOrderId, 120)) {
    return {
      action: "reuse",
      reason: "existing_billit_order",
      document_id: _str(existingConsumerDocumentId, 200) || null,
      billit_order_id: _str(existingConsumerBillitOrderId, 120),
    };
  }
  if (_str(existingConsumerDocumentId, 200)) {
    return {
      action: "ensure_billit_order",
      reason: "existing_document_missing_order",
      document_id: _str(existingConsumerDocumentId, 200),
    };
  }
  return { action: "create", reason: "eligible_consumer_sale" };
}

/**
 * Payment sync against an existing consumer Billit document/order.
 * Create is never a side-effect of payment sync failure.
 */
export function resolveConsumerSalePaymentSyncGate({
  ridePaid = false,
  hasConsumerDocument = false,
  hasConsumerBillitOrder = false,
  billitPaid = null,
  billitPaymentSyncStatus = "",
  paymentMethod = "",
  paymentProvider = "",
} = {}) {
  void paymentMethod;
  void paymentProvider;
  if (!ridePaid) {
    return { action: "none", reason: "ride_unpaid" };
  }
  if (!hasConsumerDocument && !hasConsumerBillitOrder) {
    return { action: "none", reason: "no_consumer_sale" };
  }
  const sync = _lower(billitPaymentSyncStatus, 40);
  if (billitPaid === true || sync === "synced") {
    return { action: "already_synced", reason: "already_paid" };
  }
  if (!hasConsumerBillitOrder) {
    // Payment sync must not invent a second sale document.
    return {
      action: "ensure_order_then_sync",
      reason: "missing_billit_order_reuse_document",
      creates_new_sale_document: false,
    };
  }
  return {
    action: "sync_paid",
    reason: "ride_paid_billit_pending",
    creates_new_sale_document: false,
  };
}

/**
 * Conversion from consumer sale → business invoice via Income CreditNote.
 *
 * Pipeline (idempotent resume):
 *   1. issue Document Core credit_note + Billit OrderType CreditNote
 *      matching the consumer invoice ground/VAT/totals exactly
 *   2. only then mark consumer sale credited/superseded
 *   3. issue exactly one business invoice (Peppol only there)
 *
 * If credit fails: do not supersede and do not create a business invoice.
 * If credit succeeded and business failed: resume business only.
 */
export function resolveConsumerToBusinessConversionDecision({
  hasConsumerSale = false,
  consumerSaleSuperseded = false,
  hasActiveBusinessInvoice = false,
  consumerBillitOrderId = "",
  businessBillitOrderId = "",
  hasCreditNoteDocument = false,
  hasCreditNoteBillitOrder = false,
  creditFailed = false,
} = {}) {
  if (hasActiveBusinessInvoice && _str(businessBillitOrderId, 120)) {
    return {
      action: "reuse_business",
      reason: "business_invoice_already_active",
      double_revenue_risk: false,
      step: "done",
      requires_credit_note: false,
      requires_consumer_supersede: false,
      allow_business_invoice: true,
      peppol_on_business_only: true,
    };
  }
  if (!hasConsumerSale && !_str(consumerBillitOrderId, 120)) {
    return {
      action: "create_business",
      reason: "no_consumer_sale",
      double_revenue_risk: false,
      step: "create_business_only",
      requires_credit_note: false,
      requires_consumer_supersede: false,
      allow_business_invoice: true,
      peppol_on_business_only: true,
    };
  }

  // Credit already on Billit (or consumer already credited): resume business.
  if (
    hasCreditNoteBillitOrder ||
    (consumerSaleSuperseded && hasCreditNoteDocument)
  ) {
    return {
      action: "resume_business_after_credit",
      reason: "credit_note_already_registered",
      double_revenue_risk: false,
      step: "issue_business_invoice",
      requires_credit_note: false,
      requires_consumer_supersede: !consumerSaleSuperseded,
      allow_business_invoice: true,
      previous_consumer_order_id: _str(consumerBillitOrderId, 120) || null,
      peppol_on_business_only: true,
    };
  }

  if (creditFailed && !hasCreditNoteBillitOrder) {
    return {
      action: "block_until_credit_succeeds",
      reason: "credit_note_failed",
      double_revenue_risk: false,
      step: "issue_credit_note",
      requires_credit_note: true,
      requires_consumer_supersede: false,
      allow_business_invoice: false,
      previous_consumer_order_id: _str(consumerBillitOrderId, 120) || null,
      peppol_on_business_only: true,
    };
  }

  if (hasCreditNoteDocument && !hasCreditNoteBillitOrder) {
    return {
      action: "ensure_credit_billit_order",
      reason: "credit_document_missing_billit_order",
      double_revenue_risk: false,
      step: "ensure_credit_billit_order",
      requires_credit_note: true,
      requires_consumer_supersede: false,
      allow_business_invoice: false,
      previous_consumer_order_id: _str(consumerBillitOrderId, 120) || null,
      peppol_on_business_only: true,
    };
  }

  return {
    action: "credit_then_business",
    reason: "convert_consumer_via_credit_note",
    double_revenue_risk: false,
    step: "issue_credit_note",
    requires_credit_note: true,
    requires_consumer_supersede: true,
    allow_business_invoice: false, // only after credit succeeds
    previous_consumer_order_id: _str(consumerBillitOrderId, 120) || null,
    peppol_on_business_only: true,
    accounting_note:
      "Consumer Billit Invoice is reversed with an Income CreditNote for the same VAT/totals, then a distinct business invoice is issued. Peppol applies only to the business invoice.",
  };
}

export function buildConsumerConversionCreditIdempotencyKey({
  tenantId,
  companyId,
  bookingId,
  legId = null,
} = {}) {
  const t = _str(tenantId, 96);
  const c = _str(companyId, 96);
  const b = _str(bookingId, 160);
  if (!t || !c || !b) return null;
  const leg = _str(legId, 160) || "main";
  return `cn-consumer-convert:${t}:${c}:${b}:${leg}:v1`;
}

export function creditNoteTotalsMatchConsumerSale({
  consumerCents = null,
  consumerVatRatePercent = null,
  consumerCurrency = "EUR",
  creditCents = null,
  creditVatRatePercent = null,
  creditCurrency = "EUR",
} = {}) {
  if (!Number.isInteger(consumerCents) || !(consumerCents > 0)) {
    return { ok: false, error: "consumer_amount_invalid" };
  }
  if (!Number.isInteger(creditCents) || creditCents !== consumerCents) {
    return { ok: false, error: "credit_amount_mismatch" };
  }
  const cCur = _str(consumerCurrency, 8).toUpperCase() || "EUR";
  const nCur = _str(creditCurrency, 8).toUpperCase() || "EUR";
  if (cCur !== nCur) {
    return { ok: false, error: "credit_currency_mismatch" };
  }
  const cVat = Number(consumerVatRatePercent);
  const nVat = Number(creditVatRatePercent);
  if (!Number.isFinite(cVat) || !Number.isFinite(nVat) || cVat !== nVat) {
    return { ok: false, error: "credit_vat_mismatch" };
  }
  return { ok: true };
}

export function buildConsumerConversionLinkTrail({
  bookingId,
  legId = null,
  consumerDocumentId = null,
  consumerBillitOrderId = null,
  creditDocumentId = null,
  creditBillitOrderId = null,
  businessDocumentId = null,
  businessBillitOrderId = null,
  paymentMethod = null,
  paymentProvider = null,
  paymentStatus = null,
} = {}) {
  return {
    booking_id: _str(bookingId, 160) || null,
    leg_id: _str(legId, 160) || null,
    consumer_document_id: _str(consumerDocumentId, 200) || null,
    consumer_billit_order_id: _str(consumerBillitOrderId, 120) || null,
    credit_document_id: _str(creditDocumentId, 200) || null,
    credit_billit_order_id: _str(creditBillitOrderId, 120) || null,
    business_document_id: _str(businessDocumentId, 200) || null,
    business_billit_order_id: _str(businessBillitOrderId, 120) || null,
    payment_method: _lower(paymentMethod, 40) || null,
    payment_provider: _lower(paymentProvider, 40) || null,
    payment_status: _lower(paymentStatus, 40) || null,
    second_cashflow: false,
    peppol_on: "business_invoice_only",
  };
}

export function activeRevenueDocumentsAfterConversion({
  consumerSuperseded = false,
  creditNotePresent = false,
  businessInvoicePresent = false,
} = {}) {
  const active = [];
  if (!consumerSuperseded) active.push("consumer_sale");
  // Credit notes reverse revenue; they are not an additional active sale.
  void creditNotePresent;
  if (businessInvoicePresent) active.push("business_invoice");
  return {
    active,
    ok: active.length <= 1,
    double_active_sales: active.length > 1,
  };
}

export function isActiveRevenueDocument({
  saleKind = "",
  superseded = false,
  lifecycleState = "",
} = {}) {
  if (superseded === true) return false;
  const life = _lower(lifecycleState, 40);
  if (life === "superseded" || life === "void" || life === "cancelled" || life === "canceled") {
    return false;
  }
  const kind = _lower(saleKind, 40);
  if (kind === CONSUMER_SALE_KIND || kind === "business_invoice" || kind === "" || kind === "invoice") {
    return true;
  }
  return true;
}

export function buildConsumerSaleDocumentMetadata({
  bookingId,
  legId = null,
  amount,
  paymentStatus = "unpaid",
  paymentMethod = "",
  paymentProvider = "",
  billitOrderId = null,
} = {}) {
  const presentation = consumerSalePresentation();
  const peppol = consumerSalePeppolPolicy();
  return {
    fluxidi_sale_kind: CONSUMER_SALE_KIND,
    document_type: CONSUMER_SALE_DOCUMENT_TYPE,
    presentation_label_key: presentation.document_label_key,
    status_label_key: presentation.status_key,
    peppol_applicable: peppol.peppol_applicable,
    peppol_required: peppol.peppol_required,
    peppol_sent: peppol.peppol_sent,
    source_booking_id: _str(bookingId, 160) || null,
    source_leg_id: _str(legId, 160) || null,
    amount: amount || null,
    payment_status: _lower(paymentStatus, 40) || "unpaid",
    payment_method: _lower(paymentMethod, 40) || null,
    payment_provider: _lower(paymentProvider, 40) || null,
    billit_order_id: _str(billitOrderId, 120) || null,
    active_revenue: true,
    superseded: false,
  };
}

export function mapConsumerSalePaymentMethodLabel({
  paymentMethod = "",
  paymentProvider = "",
  paymentSource = "",
} = {}) {
  const method = _lower(paymentMethod, 40);
  const provider = _lower(paymentProvider, 40);
  const source = _lower(paymentSource, 40);
  if (
    method === "pointofsale" ||
    method === "tap_to_pay" ||
    source === "tap_to_pay" ||
    method === "in_vehicle_card"
  ) {
    return {
      key: "tapToPay",
      provider_confirmed: provider === "mollie",
      manual: provider !== "mollie",
    };
  }
  if (method === "bancontact") {
    return {
      key: "bancontactManual",
      provider_confirmed: false,
      manual: true,
    };
  }
  if (method === "cash") {
    return { key: "cash", provider_confirmed: false, manual: true };
  }
  if (method === "qr_code" || method === "qr") {
    return { key: "qr", provider_confirmed: false, manual: true };
  }
  if (provider === "mollie" || method === "ideal" || method === "creditcard") {
    return {
      key: "onlineMollie",
      provider_confirmed: true,
      manual: false,
    };
  }
  if (method === "bank_transfer" || method === "bank_transfer_bacs") {
    return { key: "bankTransfer", provider_confirmed: false, manual: true };
  }
  return { key: "unknown", provider_confirmed: false, manual: false };
}

export function shouldWarnMissingPeppolEndpointForSale({
  saleKind = "",
  peppolApplicable = null,
} = {}) {
  if (_lower(saleKind, 40) === CONSUMER_SALE_KIND) return false;
  if (peppolApplicable === false) return false;
  return true;
}

export function roundtripAvoidsDoubleRevenue({
  registerParentTotal = false,
  registerOutboundLeg = false,
  registerReturnLeg = false,
} = {}) {
  // Canonical strategy: register per operational leg OR parent-only, never both.
  const legCount =
    (registerOutboundLeg ? 1 : 0) + (registerReturnLeg ? 1 : 0);
  if (registerParentTotal && legCount > 0) {
    return {
      ok: false,
      error: "double_revenue_parent_and_legs",
      strategy: "reject",
    };
  }
  return {
    ok: true,
    strategy: legCount > 0 ? "per_leg" : "parent_only",
  };
}
