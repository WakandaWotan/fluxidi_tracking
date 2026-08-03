/* Pure street-invoice PDF projection helpers (source-of-truth fix P1).
 *
 * Side-effect free: no KV / R2 / Billit / Peppol / clocks.
 * Used by ensureStreetBusinessInvoicePdfArtifact and paid PDF refresh.
 */
import { safeStr } from "./parsing_utils.js";
import {
  formatBelgianEnterpriseNumber,
  formatBelgianVatNumber,
  legalFormLabelNl,
  formatSellerIdentityPresentationLines,
} from "./seller_identity.js";
import {
  isLegacyFlxInvoiceNumber,
  isDocumentCoreInvoiceNumber,
  resolveCanonicalInvoiceNumberBinding,
} from "./invoice_number_source_of_truth.js";
import {
  formatPaymentMethodLabelNl,
  normalizePaymentMethodId,
  resolvePaymentMethodTruthFromRecord,
} from "./payment_method_truth.js";
import {
  companyDateTimePartsFromIso,
  resolveCompanyTimezone,
  DEFAULT_COMPANY_TIMEZONE,
} from "./brussels_datetime.js";
import {
  pickCustomerVisibleAddress,
  looksLikeCoordinatePair,
  formatDocumentPhoneDisplay,
} from "./document_phone_format.js";

export const STREET_INVOICE_PDF_PROJECTION_VERSION = "street_pdf_proj_v1";
export { looksLikeCoordinatePair, pickCustomerVisibleAddress, formatDocumentPhoneDisplay };

function _norm(v) {
  return safeStr(v, 400);
}

function _lower(v) {
  return _norm(v).toLowerCase();
}

function _finiteNumber(value) {
  if (value === null || value === undefined || value === "") return null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

/** Convert a stored euro amount (number or decimal string) to integer cents. */
export function euroAmountToCents(value) {
  if (value === null || value === undefined || value === "") return null;
  if (typeof value === "number") {
    if (!Number.isFinite(value)) return null;
    return Math.round(value * 100);
  }
  const text = String(value).trim().replace(",", ".");
  if (!text) return null;
  const match = text.match(/^(-?)(\d+)(?:\.(\d{0,2}))?$/);
  if (!match) {
    const n = Number(text);
    if (!Number.isFinite(n)) return null;
    return Math.round(n * 100);
  }
  const sign = match[1] === "-" ? -1 : 1;
  const whole = Number(match[2] || "0");
  const frac = (match[3] || "").padEnd(2, "0").slice(0, 2);
  return sign * (whole * 100 + Number(frac || "0"));
}

export function centsToEuroNumber(cents) {
  if (!Number.isFinite(Number(cents))) return null;
  return Math.trunc(Number(cents)) / 100;
}

export function centsToEuroFixed(cents) {
  const n = centsToEuroNumber(cents);
  if (n == null) return null;
  return n.toFixed(2);
}

/** Normalize VAT rate inputs to percent (e.g. 6 or 0.06 → 6). */
export function normalizeVatRatePercent(value) {
  const n = _finiteNumber(value);
  if (n == null || n < 0) return null;
  const percent = n > 0 && n <= 1 ? n * 100 : n;
  if (!Number.isFinite(percent) || percent < 0 || percent > 100) return null;
  return Math.round(percent * 100) / 100;
}

function _issuedTotals(issuedDocument) {
  const doc =
    issuedDocument && typeof issuedDocument === "object" ? issuedDocument : {};
  const snap =
    doc.immutable_snapshot && typeof doc.immutable_snapshot === "object"
      ? doc.immutable_snapshot
      : {};
  const totals =
    (doc.totals && typeof doc.totals === "object" ? doc.totals : null) ||
    (snap.totals && typeof snap.totals === "object" ? snap.totals : null) ||
    {};
  return totals;
}

function _issuedSellerSnapshot(issuedDocument) {
  const doc =
    issuedDocument && typeof issuedDocument === "object" ? issuedDocument : {};
  const snap =
    doc.immutable_snapshot && typeof doc.immutable_snapshot === "object"
      ? doc.immutable_snapshot
      : {};
  const seller =
    (doc.seller_snapshot && typeof doc.seller_snapshot === "object"
      ? doc.seller_snapshot
      : null) ||
    (snap.seller_snapshot && typeof snap.seller_snapshot === "object"
      ? snap.seller_snapshot
      : null);
  return seller;
}

/**
 * VAT source-of-truth for PDF projection.
 * 1) issued Document Core totals.vat_rate_percent
 * 2) booking fare/invoice VAT snapshot
 * 3) tenant/company VAT configuration (percent)
 * Fail closed when none valid — never invent 21/6.
 */
export function resolveInvoiceVatRatePercent({
  issuedDocument = null,
  bookingRecord = null,
  companyVatRatePercent = null,
} = {}) {
  const totals = _issuedTotals(issuedDocument);
  const issuedRate = normalizeVatRatePercent(totals.vat_rate_percent);
  if (issuedRate != null) {
    return {
      ok: true,
      ratePercent: issuedRate,
      source: "document_core_issued",
    };
  }

  const rec =
    bookingRecord && typeof bookingRecord === "object" ? bookingRecord : {};
  const booking =
    rec.booking && typeof rec.booking === "object" ? rec.booking : {};
  const bookingRate = normalizeVatRatePercent(
    booking.vat_rate_percent ??
      rec.vat_rate_percent ??
      booking.vat_rate ??
      rec.vat_rate ??
      booking.vatRate ??
      rec.vatRate,
  );
  if (bookingRate != null) {
    return {
      ok: true,
      ratePercent: bookingRate,
      source: "booking_snapshot",
    };
  }

  const companyRate = normalizeVatRatePercent(companyVatRatePercent);
  if (companyRate != null) {
    return {
      ok: true,
      ratePercent: companyRate,
      source: "company_vat_config",
    };
  }

  return { ok: false, error: "missing_vat_rate", ratePercent: null, source: null };
}

/**
 * Financial cents from issued document first, then booking fare snapshot.
 * Does not recompute VAT from rate × base.
 */
export function resolveInvoiceFinancialCents({
  issuedDocument = null,
  bookingRecord = null,
} = {}) {
  const totals = _issuedTotals(issuedDocument);
  const issuedIncl =
    _finiteNumber(totals.total_incl_vat_cents) != null
      ? Math.trunc(Number(totals.total_incl_vat_cents))
      : euroAmountToCents(totals.total_incl_vat);
  const issuedVat =
    _finiteNumber(totals.vat_amount_cents) != null
      ? Math.trunc(Number(totals.vat_amount_cents))
      : euroAmountToCents(totals.vat_amount);
  const issuedEx =
    _finiteNumber(totals.subtotal_ex_vat_cents) != null
      ? Math.trunc(Number(totals.subtotal_ex_vat_cents))
      : euroAmountToCents(totals.subtotal_ex_vat);

  if (issuedIncl != null && issuedVat != null && issuedEx != null) {
    return {
      ok: true,
      source: "document_core_issued",
      totalInclCents: issuedIncl,
      vatCents: issuedVat,
      subtotalExCents: issuedEx,
    };
  }

  const rec =
    bookingRecord && typeof bookingRecord === "object" ? bookingRecord : {};
  const booking =
    rec.booking && typeof rec.booking === "object" ? rec.booking : {};
  const bookingIncl =
    _finiteNumber(rec.price_incl_vat_cents ?? booking.price_incl_vat_cents) !=
    null
      ? Math.trunc(
          Number(rec.price_incl_vat_cents ?? booking.price_incl_vat_cents),
        )
      : euroAmountToCents(
          booking.price_incl_vat ?? rec.price_incl_vat ?? booking.price,
        );
  const bookingVat =
    _finiteNumber(rec.price_vat_cents ?? booking.price_vat_cents) != null
      ? Math.trunc(Number(rec.price_vat_cents ?? booking.price_vat_cents))
      : euroAmountToCents(booking.price_vat ?? rec.price_vat);
  const bookingEx =
    _finiteNumber(rec.price_ex_vat_cents ?? booking.price_ex_vat_cents) != null
      ? Math.trunc(Number(rec.price_ex_vat_cents ?? booking.price_ex_vat_cents))
      : euroAmountToCents(
          booking.price_ex_vat ??
            rec.price_ex_vat ??
            booking.subtotal_ex_vat ??
            rec.subtotal_ex_vat,
        );

  if (bookingIncl != null && bookingVat != null && bookingEx != null) {
    return {
      ok: true,
      source: "booking_snapshot",
      totalInclCents: bookingIncl,
      vatCents: bookingVat,
      subtotalExCents: bookingEx,
    };
  }

  return {
    ok: false,
    error: "missing_financial_totals",
    source: null,
    totalInclCents: null,
    vatCents: null,
    subtotalExCents: null,
  };
}

function _composeSellerAddress(seller) {
  if (!seller || typeof seller !== "object") return "";
  const direct = _norm(
    seller.address ?? seller.full_address ?? seller.fullAddress,
  );
  if (direct) return direct;
  const street = _norm(
    seller.street ??
      seller.address_line ??
      seller.addressLine ??
      seller.address_line1 ??
      seller.addressLine1,
  );
  const postal = _norm(seller.postal_code ?? seller.postalCode ?? seller.zip);
  const city = _norm(seller.city);
  const country = _norm(
    seller.country_code ?? seller.countryCode ?? seller.country,
  );
  const line2 = [postal, city].filter(Boolean).join(" ");
  return [street, line2, country].filter(Boolean).join("\n");
}

/**
 * Seller for PDF: issued seller_snapshot wins over live communication profile.
 * Preserves legal entrepreneur vs trading name when present on the snapshot.
 */
export function resolveInvoiceSellerCommProfile({
  issuedDocument = null,
  communicationProfile = null,
} = {}) {
  const seller = _issuedSellerSnapshot(issuedDocument);
  const trading = _norm(
    seller?.trading_name ??
      seller?.tradingName ??
      seller?.name ??
      seller?.company_name ??
      seller?.companyName,
  );
  const legal = _norm(
    seller?.legal_entrepreneur_name ??
      seller?.legalEntrepreneurName ??
      seller?.legal_name ??
      seller?.legalName,
  );
  const vat = _norm(seller?.vat_number ?? seller?.vatNumber);
  const enterprise = _norm(
    seller?.enterprise_number ??
      seller?.registration_number ??
      seller?.registrationNumber,
  );
  const legalForm = _norm(seller?.legal_form ?? seller?.legalForm);
  const phone = _norm(seller?.phone ?? seller?.telephone);
  const email = _norm(seller?.email ?? seller?.invoice_email);
  const address = _composeSellerAddress(seller);
  if (seller && (trading || legal || vat || address)) {
    const presentationLines = formatSellerIdentityPresentationLines({
      legal_seller_name: legal,
      legal_entrepreneur_name: legal,
      trading_name: trading,
      legal_form: legalForm,
      legal_form_label_nl:
        _norm(seller?.legal_form_label_nl) || legalFormLabelNl(legalForm),
      enterprise_number: enterprise,
      enterprise_number_display: formatBelgianEnterpriseNumber(enterprise),
      vat_number: vat,
      vat_number_display: formatBelgianVatNumber(vat),
    });
    return {
      source: "document_core_seller_snapshot",
      brandName: trading || legal,
      legalName: legal || trading,
      legalEntrepreneurName: legal,
      tradingName: trading,
      legalForm: legalForm || null,
      legalFormLabelNl:
        _norm(seller?.legal_form_label_nl) || legalFormLabelNl(legalForm),
      enterpriseNumber: enterprise,
      enterpriseNumberDisplay: formatBelgianEnterpriseNumber(enterprise),
      vatNumber: vat,
      vatNumberDisplay: formatBelgianVatNumber(vat),
      sellerPresentationLines: presentationLines,
      address,
      phone,
      invoiceEmail: email,
      logoUrl: _norm(seller?.logo_url ?? seller?.logoUrl),
      invoiceFooter: _norm(seller?.invoice_footer ?? seller?.invoiceFooter),
      addressIsVisitor:
        seller?.address_is_visitor === true ||
        seller?.addressIsVisitor === true
          ? true
          : seller?.address_is_visitor === false ||
              seller?.addressIsVisitor === false
            ? false
            : null,
    };
  }

  const profile =
    communicationProfile && typeof communicationProfile === "object"
      ? communicationProfile
      : {};
  const profileLegal = _norm(
    profile.legalEntrepreneurName ??
      profile.legal_entrepreneur_name ??
      profile.legalName ??
      profile.legal_name,
  );
  const profileTrading = _norm(
    profile.tradingName ??
      profile.trading_name ??
      profile.brandName ??
      profile.brand_name,
  );
  const profileForm = _norm(profile.legalForm ?? profile.legal_form);
  const profileEnterprise = _norm(
    profile.enterpriseNumber ?? profile.enterprise_number,
  );
  const profileVat = _norm(profile.vatNumber ?? profile.vat_number);
  return {
    source: "company_communication_profile",
    brandName: profileTrading,
    legalName: profileLegal,
    legalEntrepreneurName: profileLegal,
    tradingName: profileTrading,
    legalForm: profileForm || null,
    legalFormLabelNl:
      _norm(profile.legalFormLabelNl) || legalFormLabelNl(profileForm),
    enterpriseNumber: profileEnterprise,
    enterpriseNumberDisplay:
      _norm(profile.enterpriseNumberDisplay) ||
      formatBelgianEnterpriseNumber(profileEnterprise),
    vatNumber: profileVat,
    vatNumberDisplay:
      _norm(profile.vatNumberDisplay) || formatBelgianVatNumber(profileVat),
    sellerPresentationLines: formatSellerIdentityPresentationLines({
      legal_seller_name: profileLegal,
      trading_name: profileTrading,
      legal_form: profileForm,
      legal_form_label_nl:
        _norm(profile.legalFormLabelNl) || legalFormLabelNl(profileForm),
      enterprise_number: profileEnterprise,
      vat_number: profileVat,
    }),
    address: _norm(profile.address),
    phone: _norm(profile.phone),
    invoiceEmail: _norm(profile.invoiceEmail ?? profile.invoice_email),
    logoUrl: _norm(profile.logoUrl ?? profile.logo_url),
    invoiceFooter: _norm(profile.invoiceFooter ?? profile.invoice_footer),
    addressIsVisitor:
      profile.addressIsVisitor === true || profile.address_is_visitor === true
        ? true
        : profile.addressIsVisitor === false ||
            profile.address_is_visitor === false
          ? false
          : null,
  };
}

function _formatIsoLocalParts(iso, timezone = DEFAULT_COMPANY_TIMEZONE) {
  // Customer-visible local parts in the company IANA timezone (DST-aware).
  // Stored timestamps remain UTC ISO; never use getUTC* for display.
  return companyDateTimePartsFromIso(iso, resolveCompanyTimezone(timezone));
}

/** Ride / service fields from canonical booking record. */
export function resolveInvoiceRideProjection(
  bookingRecord = null,
  { timezone = DEFAULT_COMPANY_TIMEZONE } = {},
) {
  const rec =
    bookingRecord && typeof bookingRecord === "object" ? bookingRecord : {};
  const booking =
    rec.booking && typeof rec.booking === "object" ? rec.booking : {};
  const tz = resolveCompanyTimezone(timezone);
  const pickupIso = _norm(
    booking.pickupStartIso ||
      booking.pickup_iso ||
      booking.pickupIso ||
      rec.pickupStartIso ||
      rec.pickup_iso ||
      rec.scheduled_pickup_at,
  );
  const startedIso = _norm(
    rec.ride_started_at ||
      rec.rideStartedAt ||
      rec.started_at ||
      rec.startedAt ||
      booking.ride_started_at ||
      booking.started_at ||
      rec.trip_started_at,
  );
  const pickupParts = _formatIsoLocalParts(pickupIso, tz);
  const startParts = _formatIsoLocalParts(startedIso, tz);
  const tier = _norm(
    booking.tier ?? rec.tier ?? booking.ride_tier ?? rec.ride_tier,
  );
  const service = _norm(
    booking.service ??
      rec.service ??
      booking.service_type ??
      rec.service_type ??
      booking.serviceType,
  );
  // Authoritative route snapshot wins over mutable booking.from/to.
  // Coordinates are never customer-visible; missing → empty (omit / "Niet opgegeven").
  const from = pickCustomerVisibleAddress(
    booking.invoice_from_address,
    rec.invoice_from_address,
    booking.from_full_address,
    rec.from_full_address,
    booking.from_label,
    rec.from_label,
    booking.pickup_address,
    booking.pickupAddress,
    booking.from,
    rec.from,
  );
  const to = pickCustomerVisibleAddress(
    booking.invoice_to_address,
    rec.invoice_to_address,
    booking.to_full_address,
    rec.to_full_address,
    booking.to_label,
    rec.to_label,
    booking.destination_address,
    booking.dropoff_address,
    booking.to,
    rec.to,
  );
  return {
    pickupStartIso: pickupIso,
    tripDate: pickupParts.date || startParts.date || "",
    pickupTime: pickupParts.time || "",
    rideStartTime: startParts.time || "",
    rideStartIso: startedIso,
    timezone: tz,
    tier,
    service,
    from,
    to,
    fromMissing: !from,
    toMissing: !to,
    stops: Array.isArray(booking.stops)
      ? booking.stops
      : Array.isArray(rec.stops)
        ? rec.stops
        : [],
    pax: _finiteNumber(booking.pax ?? rec.pax),
    bags: _finiteNumber(booking.bags ?? rec.bags),
    paxKnown: _finiteNumber(booking.pax ?? rec.pax) !== null,
    bagsKnown: _finiteNumber(booking.bags ?? rec.bags) !== null,
    rideStatus: _norm(rec.status ?? rec.lifecycle_status ?? booking.status),
  };
}

/**
 * Human-readable Fluxidi payment method labels (central source-of-truth).
 * Never copies Billit Wired / Overschrijving.
 */
export function formatFluxidiPaymentMethodLabel(paymentMethod) {
  const id = normalizePaymentMethodId(paymentMethod);
  if (!id) return "";
  return formatPaymentMethodLabelNl(id);
}

export function buildStreetInvoicePdfProjectionRevision({
  paymentStatus = "",
  vatRatePercent = null,
  totalInclCents = null,
  vatCents = null,
  subtotalExCents = null,
  sellerSource = "",
  paymentMethodLabel = "",
  tripDate = "",
  pickupTime = "",
  tier = "",
  service = "",
} = {}) {
  return [
    STREET_INVOICE_PDF_PROJECTION_VERSION,
    `pay=${_lower(paymentStatus) || "unpaid"}`,
    `vat=${vatRatePercent == null ? "-" : String(vatRatePercent)}`,
    `incl=${totalInclCents == null ? "-" : String(totalInclCents)}`,
    `tax=${vatCents == null ? "-" : String(vatCents)}`,
    `ex=${subtotalExCents == null ? "-" : String(subtotalExCents)}`,
    `seller=${_norm(sellerSource) || "-"}`,
    `method=${_norm(paymentMethodLabel) || "-"}`,
    `trip=${_norm(tripDate)}|${_norm(pickupTime)}`,
    `tier=${_norm(tier)}`,
    `svc=${_norm(service)}`,
  ].join(";");
}

/**
 * Whether an existing PDF should be rebuilt for payment/projection convergence.
 * Ordinary ensure skips when key exists and revision matches.
 */
export function shouldRefreshStreetInvoicePdfArtifact({
  existingPdfExists = false,
  forceRefresh = false,
  storedProjectionRevision = "",
  nextProjectionRevision = "",
  reason = "ensure",
} = {}) {
  if (forceRefresh === true) {
    return { refresh: true, reason: "force_refresh" };
  }
  if (!existingPdfExists) {
    return { refresh: true, reason: "missing_artifact" };
  }
  const stored = _norm(storedProjectionRevision);
  const next = _norm(nextProjectionRevision);
  if (stored && next && stored === next) {
    return { refresh: false, reason: "projection_unchanged" };
  }
  if (reason === "paid_refresh" || reason === "ensure") {
    if (!stored || stored !== next) {
      return { refresh: true, reason: "projection_changed" };
    }
  }
  return { refresh: false, reason: "already_persisted" };
}

/**
 * Ownership guard for controlled regeneration.
 */
export function assertStreetInvoicePdfOwnership({
  scope = null,
  bookingRecord = null,
  issuedDocument = null,
  bookingId = "",
  documentId = "",
  invoiceNumber = "",
} = {}) {
  const tenant = _norm(scope?.tenant_id ?? scope?.tenantId);
  const company = _norm(scope?.company_id ?? scope?.companyId);
  if (!tenant || !company) {
    return { ok: false, error: "missing_tenant_scope" };
  }
  const rec =
    bookingRecord && typeof bookingRecord === "object" ? bookingRecord : {};
  const bookingTenant = _norm(rec.tenant_id ?? rec.tenantId);
  const bookingCompany = _norm(rec.company_id ?? rec.companyId);
  if (bookingTenant && bookingTenant !== tenant) {
    return { ok: false, error: "booking_tenant_mismatch" };
  }
  if (bookingCompany && bookingCompany !== company) {
    return { ok: false, error: "booking_company_mismatch" };
  }
  const safeBookingId = _norm(bookingId);
  const recBookingId = _norm(
    rec.booking_id ?? rec.bookingId ?? rec.booking?.booking_id,
  );
  if (safeBookingId && recBookingId && safeBookingId !== recBookingId) {
    return { ok: false, error: "booking_id_mismatch" };
  }

  if (issuedDocument && typeof issuedDocument === "object") {
    const docTenant = _norm(
      issuedDocument.tenant_id ?? issuedDocument.tenantId,
    );
    const docCompany = _norm(
      issuedDocument.company_id ?? issuedDocument.companyId,
    );
    if (docTenant && docTenant !== tenant) {
      return { ok: false, error: "document_tenant_mismatch" };
    }
    if (docCompany && docCompany !== company) {
      return { ok: false, error: "document_company_mismatch" };
    }
    const sourceBooking = _norm(
      issuedDocument.source_booking_id ?? issuedDocument.sourceBookingId,
    );
    if (safeBookingId && sourceBooking && safeBookingId !== sourceBooking) {
      return { ok: false, error: "document_booking_mismatch" };
    }
    const docId = _norm(
      issuedDocument.document_id ?? issuedDocument.documentId,
    );
    const expectedDocId = _norm(documentId);
    if (expectedDocId && docId && expectedDocId !== docId) {
      return { ok: false, error: "document_id_mismatch" };
    }
    const docNumber = _norm(
      issuedDocument.document_number ?? issuedDocument.documentNumber,
    );
    const expectedNumber = _norm(invoiceNumber);
    if (expectedNumber && docNumber && expectedNumber !== docNumber) {
      // Stale booking FLX vs Document Core INV is expected during migration;
      // Document Core wins in buildStreetInvoicePdfProjection. Hard-fail only
      // on conflicting non-upgrade numbers (e.g. two different INV values).
      const flxVsInv =
        isLegacyFlxInvoiceNumber(expectedNumber) &&
        isDocumentCoreInvoiceNumber(docNumber);
      if (!flxVsInv) {
        return { ok: false, error: "invoice_number_mismatch" };
      }
    }
  }
  return { ok: true };
}

/**
 * Build the full street invoice PDF projection input (pure).
 */
export function buildStreetInvoicePdfProjection({
  scope = null,
  bookingId = "",
  bookingRecord = null,
  issuedDocument = null,
  invoiceNumber = "",
  documentId = "",
  companyVatRatePercent = null,
  communicationProfile = null,
  paymentStatusResolver = null,
} = {}) {
  // Document Core document_number is canonical when an issued invoice is linked.
  let canonicalInvoiceNumber = _norm(invoiceNumber);
  let invoiceNumberMismatch = false;
  if (issuedDocument && typeof issuedDocument === "object") {
    const binding = resolveCanonicalInvoiceNumberBinding({
      scope,
      bookingId,
      bookingRecord,
      issuedDocument,
      invoiceReference: invoiceNumber,
      documentId,
    });
    if (!binding.ok) {
      return { ok: false, error: binding.error || "document_link_invalid" };
    }
    canonicalInvoiceNumber = _norm(binding.invoice_number);
    invoiceNumberMismatch = binding.mismatch === true;
  }

  const ownership = assertStreetInvoicePdfOwnership({
    scope,
    bookingRecord,
    issuedDocument,
    bookingId,
    documentId,
    invoiceNumber: canonicalInvoiceNumber,
  });
  if (!ownership.ok) {
    return { ok: false, error: ownership.error };
  }

  const vat = resolveInvoiceVatRatePercent({
    issuedDocument,
    bookingRecord,
    companyVatRatePercent,
  });
  if (!vat.ok) {
    return { ok: false, error: vat.error || "missing_vat_rate" };
  }

  const money = resolveInvoiceFinancialCents({
    issuedDocument,
    bookingRecord,
  });
  if (!money.ok) {
    return { ok: false, error: money.error || "missing_financial_totals" };
  }

  const seller = resolveInvoiceSellerCommProfile({
    issuedDocument,
    communicationProfile,
  });
  const companyTimezone = resolveCompanyTimezone(
    communicationProfile?.timezone ||
      communicationProfile?.time_zone ||
      DEFAULT_COMPANY_TIMEZONE,
  );
  const ride = resolveInvoiceRideProjection(bookingRecord, {
    timezone: companyTimezone,
  });
  // Format seller phone for display without mutating stored identity.
  if (seller && typeof seller === "object") {
    const rawPhone = _norm(seller.phone);
    seller.phone = formatDocumentPhoneDisplay(rawPhone) || rawPhone;
  }
  const paymentStatus =
    typeof paymentStatusResolver === "function"
      ? _lower(paymentStatusResolver(bookingRecord)) || "unpaid"
      : _lower(
          bookingRecord?.payment_status ??
            bookingRecord?.paymentStatus ??
            bookingRecord?.booking?.payment_status,
        ) === "paid"
        ? "paid"
        : "unpaid";

  const rec =
    bookingRecord && typeof bookingRecord === "object" ? bookingRecord : {};
  const booking =
    rec.booking && typeof rec.booking === "object" ? rec.booking : {};
  const paymentTruth = resolvePaymentMethodTruthFromRecord(rec);
  const rawMethod = _norm(
    paymentTruth.method_id ||
      rec.payment_method ||
      booking.payment_method ||
      rec.paymentMethod,
  );
  const paymentMethodLabel =
    paymentTruth.label_nl || formatFluxidiPaymentMethodLabel(rawMethod);
  const paymentSource = _norm(
    rec.payment_source ?? booking.payment_source ?? rec.paymentSource,
  );

  const resolvedInvoiceNumber =
    _norm(canonicalInvoiceNumber) ||
    _norm(
      issuedDocument?.document_number ??
        issuedDocument?.documentNumber ??
        rec.invoice_number ??
        rec.invoiceNumber,
    );
  if (!resolvedInvoiceNumber) {
    return { ok: false, error: "missing_invoice_number" };
  }

  const resolvedDocumentId =
    _norm(documentId) ||
    _norm(
      issuedDocument?.document_id ??
        issuedDocument?.documentId ??
        rec.invoice_document_id ??
        rec.document_id,
    );

  const revision = buildStreetInvoicePdfProjectionRevision({
    paymentStatus,
    vatRatePercent: vat.ratePercent,
    totalInclCents: money.totalInclCents,
    vatCents: money.vatCents,
    subtotalExCents: money.subtotalExCents,
    sellerSource: seller.source,
    paymentMethodLabel,
    tripDate: ride.tripDate,
    pickupTime: ride.pickupTime,
    tier: ride.tier,
    service: ride.service,
  });

  return {
    ok: true,
    invoiceNumber: resolvedInvoiceNumber,
    documentId: resolvedDocumentId || null,
    invoiceNumberMismatch,
    projectionRevision: revision,
    vatRatePercent: vat.ratePercent,
    vatRateFraction: vat.ratePercent / 100,
    vatSource: vat.source,
    financialSource: money.source,
    sellerSource: seller.source,
    sellerCommProfile: seller,
    totalInclCents: money.totalInclCents,
    vatCents: money.vatCents,
    subtotalExCents: money.subtotalExCents,
    total: centsToEuroNumber(money.totalInclCents),
    vatAmount: centsToEuroNumber(money.vatCents),
    subtotalEx: centsToEuroNumber(money.subtotalExCents),
    paymentStatus,
    paymentMethod: rawMethod,
    paymentMethodLabel,
    paymentSource,
    ride,
    invoiceInput: {
      invoice_number: resolvedInvoiceNumber,
      invoiceNumber: resolvedInvoiceNumber,
      bookingPublicId: _norm(bookingId),
      bookingId: _norm(bookingId),
      tenant_id: _norm(scope?.tenant_id ?? scope?.tenantId ?? rec.tenant_id),
      company_id: _norm(scope?.company_id ?? scope?.companyId ?? rec.company_id),
      pickupStartIso: ride.pickupStartIso,
      tripDate: ride.tripDate,
      pickupTime: ride.pickupTime || ride.rideStartTime,
      from: ride.from,
      to: ride.to,
      fromMissing: ride.fromMissing === true,
      toMissing: ride.toMissing === true,
      stops: ride.stops,
      tier: ride.tier,
      service: ride.service,
      // Keep null when unknown — renderer must not invent 0/0 or "—".
      pax: ride.pax,
      bags: ride.bags,
      paxKnown: ride.paxKnown === true,
      bagsKnown: ride.bagsKnown === true,
      omitTier: !ride.tier,
      omitService: !ride.service,
      omitPaxBags: ride.paxKnown !== true && ride.bagsKnown !== true,
      timezone: ride.timezone || companyTimezone,
      rideStatus: ride.rideStatus,
      paymentStatus,
      paymentMethod: paymentMethodLabel || rawMethod,
      paymentMethodRaw: rawMethod,
      paymentSource,
      vat_rate: vat.ratePercent / 100,
      vat_rate_percent: vat.ratePercent,
      require_explicit_vat: true,
      subtotalEx: centsToEuroNumber(money.subtotalExCents),
      vatAmount: centsToEuroNumber(money.vatCents),
      total: centsToEuroNumber(money.totalInclCents),
      // Preserve cent-exact fixed strings for generators that stringify amounts.
      subtotalExFixed: centsToEuroFixed(money.subtotalExCents),
      vatAmountFixed: centsToEuroFixed(money.vatCents),
      totalFixed: centsToEuroFixed(money.totalInclCents),
      customerName: _norm(
        booking.customer_name || booking.custName || rec.customer_name,
      ),
      customerEmail: _norm(
        booking.customer_email || booking.custEmail || rec.customer_email,
      ),
      customerPhone: _norm(
        booking.customer_phone || booking.custPhone || rec.customer_phone,
      ),
      customerVat: _norm(booking.vat_number || rec.vat_number),
      customerCompany: _norm(booking.company_name || rec.company_name),
      invoiceAddress: _norm(booking.invoice_address || rec.invoice_address),
      billing_customer_snapshot:
        rec.billing_customer_snapshot || booking.billing_customer_snapshot || null,
      street_pdf_projection_revision: revision,
      document_id: resolvedDocumentId || null,
      seller_source: seller.source,
    },
  };
}

/** Read stored projection revision from a booking record. */
export function readStoredStreetInvoicePdfProjectionRevision(bookingRecord) {
  const rec =
    bookingRecord && typeof bookingRecord === "object" ? bookingRecord : {};
  return _norm(
    rec.invoice_pdf_projection_revision ??
      rec.invoicePdfProjectionRevision ??
      rec.booking?.invoice_pdf_projection_revision ??
      rec.booking?.invoicePdfProjectionRevision,
  );
}
