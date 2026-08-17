/**
 * RateHawk affiliate product contract (P1, mocked only).
 *
 * Fluxidi already has a hotel page. RateHawk is the inventory / rate /
 * booking provider behind that page — not a parallel hotel product.
 *
 * Commercial invariants:
 *   - Affiliate remuneration is 5% and is settled by RateHawk to Fluxidi.
 *   - Fluxidi never collects the customer hotel payment (no Mollie, no
 *     subscription, no tenant payout, no Fluxidi hotel invoice).
 *   - Customer-facing amount is RateHawk's amount unchanged.
 *   - Allowed payment types: affiliate `now` (ETG charges) and `hotel`
 *     (customer pays the hotel). payment_types[].type == "deposit" is a
 *     hard stop (Fluxidi would have to fund ETG). That is not the same
 *     as rate-level `deposit`, which is a hotel/security deposit and
 *     must be displayed when valid.
 *
 * This module is fixture/mapping only. It must not call RateHawk, Mollie,
 * or any booking/search/prebook/cancel endpoint.
 */

export const RATEHAWK_PROVIDER = "ratehawk";
export const RATEHAWK_AFFILIATE_REMUNERATION_PERCENT = 5;

export const RATEHAWK_ALLOWED_AFFILIATE_PAYMENT_TYPES = Object.freeze([
  "now",
  "hotel",
]);

export const RATEHAWK_REJECTED_PAYMENT_TYPES = Object.freeze(["deposit"]);

export const RATEHAWK_STAY_CARD_SOURCE = "ratehawk";

/** Existing public hotel-card keys produced by `_mapPublicHotelStayToResponse`. */
export const FLUXIDI_HOTEL_CARD_FIELDS = Object.freeze([
  "id",
  "provider",
  "provider_id",
  "name",
  "type",
  "address",
  "city",
  "region",
  "country",
  "lat",
  "lng",
  "image_url",
  "image_ref",
  "rating_label",
  "price_label",
  "availability_label",
  "external_url",
  "provider_label",
  "photo_attribution",
  "source",
  "is_real_approved",
]);

/** Existing HotelsPage / HotelStayDetailPage actions that must remain. */
export const EXISTING_HOTEL_PAGE_ACTIONS = Object.freeze([
  "discover_city_region",
  "filter_country_city_region_type",
  "native_hotel_cards_and_images",
  "saved",
  "nearby_events",
  "taxi_to_this_event",
  "taxi_to_this_stay",
  "airport_transfer",
  "view_stay",
  "stay22_fallback_availability",
]);

const KNOWN_RATE_KEYS = Object.freeze([
  "book_hash",
  "match_hash",
  "search_hash",
  "room_name",
  "room_name_info",
  "room_description",
  "room_data_trans",
  "rg_ext",
  "occupancy",
  "bed_type",
  "meal",
  "meal_data",
  "daily_prices",
  "payment_options",
  "cancellation_penalties",
  "allotment",
  "amenities",
  "amenities_data",
  "serp_filters",
  "sell_price_limits",
  "any_residency",
  "is_package",
  "legal_info",
  "deposit",
  "no_show",
]);

const KNOWN_RATE_DEPOSIT_KEYS = Object.freeze([
  "amount",
  "currency_code",
  "is_refundable",
]);

const KNOWN_RATE_NO_SHOW_KEYS = Object.freeze([
  "amount",
  "currency_code",
  "from_time",
]);

const KNOWN_CANCELLATION_KEYS = Object.freeze([
  "free_cancellation_before",
  "policies",
  "commission_info",
]);

const KNOWN_CANCELLATION_POLICY_KEYS = Object.freeze([
  "start_at",
  "end_at",
  "amount_charge",
  "amount_show",
  "commission_info",
]);

const HOTEL_LOCAL_TIME_RE = /^([01]\d|2[0-3]):[0-5]\d:[0-5]\d$/;

const CRITICAL_UNMAPPED_HINTS = Object.freeze([
  "payment",
  "amount",
  "currency",
  "tax",
  "vat",
  "cancel",
  "penalty",
  "no_show",
  "deposit",
  "occupancy",
  "meal",
  "book_hash",
  "credit_card",
  "cvc",
]);

export const RATEHAWK_GEO_MATCH_MAX_METERS = 75;
const GEO_MATCH_MAX_METERS = RATEHAWK_GEO_MATCH_MAX_METERS;

function _text(value, max = 400) {
  const text = String(value ?? "").trim();
  if (!text) return "";
  return text.length > max ? text.slice(0, max) : text;
}

function _lower(value) {
  return _text(value, 200).toLowerCase();
}

function _finiteNumber(value) {
  const n = typeof value === "number" ? value : Number(value);
  return Number.isFinite(n) ? n : null;
}

function _normalizeAddress(value) {
  return _lower(value)
    .replace(/[.,/#-]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function _haversineMeters(aLat, aLng, bLat, bLng) {
  const toRad = (deg) => (deg * Math.PI) / 180;
  const dLat = toRad(bLat - aLat);
  const dLng = toRad(bLng - aLng);
  const sinLat = Math.sin(dLat / 2);
  const sinLng = Math.sin(dLng / 2);
  const h =
    sinLat * sinLat +
    Math.cos(toRad(aLat)) * Math.cos(toRad(bLat)) * sinLng * sinLng;
  return 6371000 * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
}

function _pushUnique(list, value) {
  if (!value || list.includes(value)) return;
  list.push(value);
}

/**
 * Convert a RateHawk decimal amount + currency into integer minor units.
 * Currency is required. Never assume EUR.
 */
export function moneyFromRatehawkAmount(amountRaw, currencyRaw) {
  const currency = _text(currencyRaw, 8).toUpperCase();
  if (!/^[A-Z]{3}$/.test(currency)) {
    return {
      ok: false,
      reason: "currency_required",
      amount_minor: null,
      currency: null,
    };
  }
  const text = _text(amountRaw, 32).replace(",", ".");
  if (!text) {
    return { ok: false, reason: "amount_required", amount_minor: null, currency };
  }
  if (!/^-?\d+(\.\d{1,4})?$/.test(text)) {
    return { ok: false, reason: "amount_unparseable", amount_minor: null, currency };
  }
  const major = Number(text);
  if (!Number.isFinite(major)) {
    return { ok: false, reason: "amount_unparseable", amount_minor: null, currency };
  }
  return {
    ok: true,
    reason: null,
    amount_minor: Math.round(major * 100),
    currency,
  };
}

export function formatCustomerFacingMoney(money) {
  if (!money || money.ok !== true) return null;
  const major = (money.amount_minor / 100).toFixed(2);
  return `${money.currency} ${major}`;
}

/**
 * Affiliate payment-type gate. Hard-stops payment_types[].type == "deposit"
 * and any type that would make Fluxidi collect customer funds or fund an
 * ETG partner deposit. Rate-level `deposit` is handled separately.
 */
export function classifyRatehawkPaymentType(paymentTypeRaw) {
  const type = _lower(paymentTypeRaw);
  if (type === "now") {
    return {
      ok: true,
      allowed: true,
      hard_stop: false,
      payment_type: "now",
      payment_recipient: "ratehawk_etg",
      payment_timing: "at_booking",
      fluxidi_collects_customer_funds: false,
      customer_pays: "RateHawk / Emerging Travel Group at booking",
      fluxidi_role: "affiliate_only",
    };
  }
  if (type === "hotel") {
    return {
      ok: true,
      allowed: true,
      hard_stop: false,
      payment_type: "hotel",
      payment_recipient: "hotel",
      payment_timing: "at_hotel",
      fluxidi_collects_customer_funds: false,
      customer_pays: "the hotel at stay",
      fluxidi_role: "affiliate_only",
    };
  }
  if (type === "deposit" || type === "") {
    return {
      ok: false,
      allowed: false,
      hard_stop: true,
      payment_type: type || null,
      payment_recipient: null,
      payment_timing: null,
      fluxidi_collects_customer_funds: type === "deposit",
      customer_pays: null,
      fluxidi_role: "rejected",
      reason:
        type === "deposit"
          ? "deposit_requires_fluxidi_to_fund_etg"
          : "payment_type_required",
    };
  }
  return {
    ok: false,
    allowed: false,
    hard_stop: true,
    payment_type: type,
    payment_recipient: null,
    payment_timing: null,
    fluxidi_collects_customer_funds: true,
    customer_pays: null,
    fluxidi_role: "rejected",
    reason: "unsupported_payment_type",
  };
}

export function assertAffiliatePaymentSafe(paymentType) {
  const classified = classifyRatehawkPaymentType(paymentType);
  if (classified.hard_stop === true || classified.allowed !== true) {
    return classified;
  }
  return classified;
}

/**
 * Identity match. Never name-only. hid is authoritative; otherwise require
 * both normalized address and coordinates within 75m.
 */
export function resolveRatehawkHotelMatch({
  ratehawkHid = null,
  catalogHid = null,
  ratehawkAddress = "",
  catalogAddress = "",
  ratehawkLat = null,
  ratehawkLng = null,
  catalogLat = null,
  catalogLng = null,
  ratehawkName = "",
  catalogName = "",
} = {}) {
  const hid = _text(ratehawkHid, 40);
  const catalog = _text(catalogHid, 40);
  if (hid && catalog && hid === catalog) {
    return {
      matched: true,
      method: "hid",
      reason: null,
      stay22_only: false,
    };
  }

  const aLat = _finiteNumber(ratehawkLat);
  const aLng = _finiteNumber(ratehawkLng);
  const bLat = _finiteNumber(catalogLat);
  const bLng = _finiteNumber(catalogLng);
  const addrA = _normalizeAddress(ratehawkAddress);
  const addrB = _normalizeAddress(catalogAddress);
  const addressEqual = Boolean(addrA && addrB && addrA === addrB);
  const haveGeo =
    aLat != null && aLng != null && bLat != null && bLng != null;
  const meters = haveGeo ? _haversineMeters(aLat, aLng, bLat, bLng) : null;
  const geoClose = meters != null && meters <= GEO_MATCH_MAX_METERS;

  if (addressEqual && geoClose) {
    return {
      matched: true,
      method: "address_geo",
      reason: null,
      stay22_only: false,
      distance_meters: Math.round(meters),
    };
  }

  const nameEqual =
    Boolean(_lower(ratehawkName)) &&
    _lower(ratehawkName) === _lower(catalogName);
  if (nameEqual && !(addressEqual && geoClose)) {
    return {
      matched: false,
      method: "name_only_rejected",
      reason: "never_match_on_name_alone",
      stay22_only: true,
    };
  }

  return {
    matched: false,
    method: "unmatched",
    reason: "no_authoritative_ratehawk_match",
    stay22_only: true,
  };
}

export function collectUnmappedFields(raw, knownKeys = KNOWN_RATE_KEYS) {
  const obj = raw && typeof raw === "object" && !Array.isArray(raw) ? raw : {};
  const unmapped = [];
  const critical = [];
  for (const key of Object.keys(obj)) {
    if (knownKeys.includes(key)) continue;
    unmapped.push(key);
    const hint = _lower(key);
    if (CRITICAL_UNMAPPED_HINTS.some((part) => hint.includes(part))) {
      critical.push(key);
    }
  }
  return {
    unmapped_field_names: unmapped,
    unmapped_critical_field_names: critical,
    fail_closed: critical.length > 0,
  };
}

function _unknownKeys(obj, knownKeys) {
  return Object.keys(obj || {}).filter((key) => !knownKeys.includes(key));
}

function _failClosed(reason, extra = {}) {
  return {
    ok: false,
    hard_stop: true,
    reason,
    ...extra,
  };
}

function _taxLine(tax) {
  const included = tax?.included_by_supplier === true;
  const money = moneyFromRatehawkAmount(tax?.amount, tax?.currency_code);
  return {
    name: _text(tax?.name, 80) || "tax",
    included_by_supplier: included,
    payable_where: included ? "included_in_rate" : "shown_separately",
    amount: money.ok ? money : null,
    mapping_ok: money.ok === true,
  };
}

function _penaltyLine(policy, chargeCurrency, showCurrency) {
  if (!policy || typeof policy !== "object" || Array.isArray(policy)) {
    return { mapping_ok: false, reason: "cancellation_policy_malformed" };
  }
  const unknown = _unknownKeys(policy, KNOWN_CANCELLATION_POLICY_KEYS);
  if (unknown.length > 0) {
    return {
      mapping_ok: false,
      reason: "cancellation_policy_unknown_field",
      unknown_field_names: unknown,
    };
  }
  const hasCharge = Object.prototype.hasOwnProperty.call(policy, "amount_charge");
  const hasShow = Object.prototype.hasOwnProperty.call(policy, "amount_show");
  const charge = hasCharge
    ? moneyFromRatehawkAmount(policy.amount_charge, chargeCurrency)
    : null;
  const show = hasShow
    ? moneyFromRatehawkAmount(policy.amount_show, showCurrency)
    : null;
  if (hasCharge && !charge.ok) {
    return { mapping_ok: false, reason: "cancellation_charge_unmapped" };
  }
  if (hasShow && !show.ok) {
    return { mapping_ok: false, reason: "cancellation_show_unmapped" };
  }
  return {
    start_at: policy.start_at ?? null,
    end_at: policy.end_at ?? null,
    charge_amount: charge?.ok ? charge : null,
    show_amount: show?.ok ? show : null,
    mapping_ok: true,
  };
}

function selectAffiliatePaymentOption(paymentTypes) {
  if (!Array.isArray(paymentTypes) || paymentTypes.length === 0) {
    const payment = assertAffiliatePaymentSafe("");
    return _failClosed(payment.reason, { payment });
  }
  for (const option of paymentTypes) {
    const classified = classifyRatehawkPaymentType(option?.type);
    if (classified.payment_type === "deposit") {
      return _failClosed(classified.reason, { payment: classified });
    }
  }
  for (const option of paymentTypes) {
    const classified = classifyRatehawkPaymentType(option?.type);
    if (classified.allowed === true) {
      return { ok: true, hard_stop: false, option, payment: classified };
    }
  }
  const payment = assertAffiliatePaymentSafe(paymentTypes[0]?.type);
  return _failClosed(payment.reason, { payment });
}

/**
 * Official ETG rate.deposit: hotel/security deposit on a rate.
 * null = not disclosed. Non-null objects must be complete and known.
 * Never treat this as payment_types[].type == "deposit".
 */
export function normalizeRatehawkRateDeposit(
  deposit,
  { chargeCurrency = null, paymentType = null } = {},
) {
  if (deposit == null) {
    return {
      ok: true,
      disclosed: false,
      amount: null,
      currency: null,
      refundable: null,
      payment_timing: null,
      payment_recipient: null,
      customer_disclosure_required: false,
    };
  }
  if (typeof deposit !== "object" || Array.isArray(deposit)) {
    return _failClosed("deposit_malformed");
  }
  const unknown = _unknownKeys(deposit, KNOWN_RATE_DEPOSIT_KEYS);
  if (unknown.length > 0) {
    return _failClosed("deposit_unknown_field", {
      unknown_field_names: unknown,
    });
  }
  if (
    !Object.prototype.hasOwnProperty.call(deposit, "amount") ||
    !Object.prototype.hasOwnProperty.call(deposit, "currency_code") ||
    !Object.prototype.hasOwnProperty.call(deposit, "is_refundable")
  ) {
    return _failClosed("deposit_incomplete");
  }
  if (typeof deposit.is_refundable !== "boolean") {
    return _failClosed("deposit_refundable_unmapped");
  }
  const money = moneyFromRatehawkAmount(deposit.amount, deposit.currency_code);
  if (!money.ok) {
    return _failClosed(
      money.reason === "currency_required"
        ? "deposit_currency_required"
        : "deposit_amount_unmapped",
    );
  }
  if (chargeCurrency && money.currency !== chargeCurrency) {
    return _failClosed("deposit_currency_mismatch");
  }
  return {
    ok: true,
    disclosed: true,
    amount: money,
    currency: money.currency,
    refundable: deposit.is_refundable,
    payment_recipient: "hotel",
    payment_timing: paymentType === "hotel" ? "at_hotel" : null,
    customer_disclosure_required: true,
  };
}

/**
 * Official ETG rate.no_show: separate no-show penalty in hotel local time.
 * null = no separate no-show data at this stage.
 */
export function normalizeRatehawkRateNoShow(
  noShow,
  { chargeCurrency = null } = {},
) {
  if (noShow == null) {
    return {
      ok: true,
      disclosed: false,
      amount: null,
      currency: null,
      from_time: null,
      timezone_context: null,
      customer_disclosure_required: false,
    };
  }
  if (typeof noShow !== "object" || Array.isArray(noShow)) {
    return _failClosed("no_show_malformed");
  }
  const unknown = _unknownKeys(noShow, KNOWN_RATE_NO_SHOW_KEYS);
  if (unknown.length > 0) {
    return _failClosed("no_show_unknown_field", {
      unknown_field_names: unknown,
    });
  }
  if (
    !Object.prototype.hasOwnProperty.call(noShow, "amount") ||
    !Object.prototype.hasOwnProperty.call(noShow, "currency_code") ||
    !Object.prototype.hasOwnProperty.call(noShow, "from_time")
  ) {
    return _failClosed("no_show_incomplete");
  }
  const money = moneyFromRatehawkAmount(noShow.amount, noShow.currency_code);
  if (!money.ok) {
    return _failClosed(
      money.reason === "currency_required"
        ? "no_show_currency_required"
        : "no_show_amount_unmapped",
    );
  }
  if (chargeCurrency && money.currency !== chargeCurrency) {
    return _failClosed("no_show_currency_mismatch");
  }
  const fromTime = _text(noShow.from_time, 8);
  if (!HOTEL_LOCAL_TIME_RE.test(fromTime)) {
    return _failClosed("no_show_from_time_unmapped");
  }
  return {
    ok: true,
    disclosed: true,
    amount: money,
    currency: money.currency,
    from_time: fromTime,
    timezone_context: "hotel_local_time",
    customer_disclosure_required: true,
  };
}

function normalizeCancellationPenalties(
  block,
  chargeCurrency,
  showCurrency,
) {
  if (block == null) {
    return {
      ok: true,
      refundable: false,
      free_cancellation_before: null,
      policies: [],
      source: null,
    };
  }
  if (typeof block !== "object" || Array.isArray(block)) {
    return _failClosed("cancellation_penalties_malformed");
  }
  const unknown = _unknownKeys(block, KNOWN_CANCELLATION_KEYS);
  if (unknown.length > 0) {
    return _failClosed("cancellation_penalties_unknown_field", {
      unknown_field_names: unknown,
    });
  }
  const before = Object.prototype.hasOwnProperty.call(
    block,
    "free_cancellation_before",
  )
    ? block.free_cancellation_before
    : null;
  if (before != null && typeof before !== "string") {
    return _failClosed("free_cancellation_before_malformed");
  }
  const freeBefore = typeof before === "string" && before.trim() ? before : null;
  const policiesRaw = Object.prototype.hasOwnProperty.call(block, "policies")
    ? block.policies
    : [];
  if (policiesRaw == null) {
    return {
      ok: true,
      refundable: Boolean(freeBefore),
      free_cancellation_before: freeBefore,
      policies: [],
    };
  }
  if (!Array.isArray(policiesRaw)) {
    return _failClosed("cancellation_policies_malformed");
  }
  const policies = [];
  for (const policy of policiesRaw) {
    const line = _penaltyLine(policy, chargeCurrency, showCurrency);
    if (line.mapping_ok !== true) {
      return _failClosed(line.reason || "cancellation_penalty_unmapped", {
        unknown_field_names: line.unknown_field_names,
      });
    }
    policies.push(line);
  }
  return {
    ok: true,
    refundable: Boolean(freeBefore),
    free_cancellation_before: freeBefore,
    policies,
  };
}

function resolveCancellationPenalties(rate, selectedOption, chargeCurrency, showCurrency) {
  const nested = selectedOption?.cancellation_penalties;
  const top = rate?.cancellation_penalties;
  if (nested !== undefined) {
    const normalized = normalizeCancellationPenalties(
      nested,
      chargeCurrency,
      showCurrency,
    );
    return { ...normalized, source: nested == null ? "payment_type_null" : "payment_type" };
  }
  if (top !== undefined) {
    const normalized = normalizeCancellationPenalties(
      top,
      chargeCurrency,
      showCurrency,
    );
    return { ...normalized, source: top == null ? "rate_null" : "rate" };
  }
  return {
    ok: true,
    refundable: false,
    free_cancellation_before: null,
    policies: [],
    source: null,
  };
}

/**
 * Normalize one RateHawk rate into the Fluxidi stay-detail contract.
 * Fail closed on payment-type deposit / unknown payment / unmapped
 * critical fields. Rate-level deposit and no_show are mapped terms.
 */
export function normalizeRatehawkRateOffer(rate = {}, { locale = "en" } = {}) {
  const paymentTypes = Array.isArray(rate?.payment_options?.payment_types)
    ? rate.payment_options.payment_types
    : [];
  const selected = selectAffiliatePaymentOption(paymentTypes);
  if (selected.ok !== true) {
    return selected;
  }
  const primary = selected.option;
  const payment = selected.payment;

  if (
    !Object.prototype.hasOwnProperty.call(primary, "show_amount") ||
    !Object.prototype.hasOwnProperty.call(primary, "show_currency_code")
  ) {
    return _failClosed("show_amount_required", { payment });
  }
  if (
    !Object.prototype.hasOwnProperty.call(primary, "amount") ||
    !Object.prototype.hasOwnProperty.call(primary, "currency_code")
  ) {
    return _failClosed("charge_amount_required", { payment });
  }

  const showMoney = moneyFromRatehawkAmount(
    primary.show_amount,
    primary.show_currency_code,
  );
  const chargeMoney = moneyFromRatehawkAmount(
    primary.amount,
    primary.currency_code,
  );
  if (!showMoney.ok) {
    return _failClosed(showMoney.reason || "show_amount_unmapped", { payment });
  }
  if (!chargeMoney.ok) {
    return _failClosed(chargeMoney.reason || "charge_amount_unmapped", {
      payment,
    });
  }

  const taxes = Array.isArray(primary.tax_data?.taxes)
    ? primary.tax_data.taxes.map(_taxLine)
    : [];
  if (taxes.some((tax) => tax.mapping_ok !== true)) {
    return _failClosed("tax_unmapped", { payment });
  }

  const deposit = normalizeRatehawkRateDeposit(rate.deposit, {
    chargeCurrency: chargeMoney.currency,
    paymentType: payment.payment_type,
  });
  if (deposit.ok !== true) {
    return { ...deposit, payment };
  }

  const noShow = normalizeRatehawkRateNoShow(rate.no_show, {
    chargeCurrency: chargeMoney.currency,
  });
  if (noShow.ok !== true) {
    return { ...noShow, payment };
  }

  const cancellation = resolveCancellationPenalties(
    rate,
    primary,
    chargeMoney.currency,
    showMoney.currency,
  );
  if (cancellation.ok !== true) {
    return { ...cancellation, payment };
  }

  const unmapped = collectUnmappedFields(rate);
  if (unmapped.fail_closed) {
    return _failClosed("unmapped_critical_field", {
      unmapped_critical_field_names: unmapped.unmapped_critical_field_names,
      payment,
    });
  }

  const mealValue = _text(rate?.meal_data?.value ?? rate?.meal, 40);
  const remaining =
    _finiteNumber(rate?.allotment) ?? _finiteNumber(rate?.rooms_available);

  return {
    ok: true,
    hard_stop: false,
    locale,
    book_hash: _text(rate?.book_hash, 256) || null,
    match_hash: _text(rate?.match_hash, 256) || null,
    room_name: _text(rate?.room_name, 200) || null,
    room_description: _text(rate?.room_description, 800) || null,
    occupancy: rate?.occupancy ?? null,
    bed_information: rate?.rg_ext ?? rate?.bed_type ?? null,
    meal_plan: mealValue || null,
    breakfast_included: rate?.meal_data?.has_breakfast === true,
    customer_total: showMoney,
    customer_total_label: formatCustomerFacingMoney(showMoney),
    reconciliation_amount: chargeMoney,
    included_taxes: taxes.filter((tax) => tax.included_by_supplier),
    excluded_taxes: taxes.filter((tax) => !tax.included_by_supplier),
    vat: primary.vat_data ?? null,
    payment,
    card_data_required: primary.is_need_credit_card_data === true,
    cvc_required: primary.is_need_cvc === true,
    refundable: cancellation.refundable === true,
    free_cancellation_before: cancellation.free_cancellation_before,
    cancellation_penalties: cancellation.policies,
    cancellation_source: cancellation.source,
    deposit,
    no_show: noShow,
    remaining_availability: remaining,
    unmapped_field_names: unmapped.unmapped_field_names,
    fluxidi_affiliate_remuneration_percent:
      RATEHAWK_AFFILIATE_REMUNERATION_PERCENT,
    fluxidi_adds_booking_fee: false,
    fluxidi_is_merchant_of_record: false,
    payment_rail_forbidden: Object.freeze([
      "mollie",
      "fluxidi_subscription",
      "tenant_mollie",
      "fluxidi_hotel_invoice",
    ]),
  };
}

/**
 * Map a RateHawk hotel (offline static content + optional live rate) onto
 * the existing public hotel-card DTO used by HotelsPage.
 *
 * Live price/availability labels are attached only when a current provider
 * rate is supplied. Stay22 remains the external fallback URL. hid is the
 * only provider_id.
 */
export function mapRatehawkHotelToExistingStayCard({
  hotel = {},
  liveRate = null,
  stay22FallbackUrl = null,
  fluxidiStayId = null,
} = {}) {
  const hid = _text(hotel.hid ?? hotel.id, 40);
  if (!hid) {
    return { ok: false, reason: "ratehawk_hid_required", stay: null };
  }

  let rateOffer = null;
  if (liveRate) {
    rateOffer = normalizeRatehawkRateOffer(liveRate);
    if (rateOffer.hard_stop) {
      return {
        ok: false,
        reason: rateOffer.reason,
        hard_stop: true,
        stay: null,
      };
    }
  }

  const lat = _finiteNumber(hotel.lat ?? hotel.latitude);
  const lng = _finiteNumber(hotel.lng ?? hotel.longitude);
  if (lat == null || lng == null) {
    return { ok: false, reason: "coordinates_required", stay: null };
  }

  const stay = {
    id: _text(fluxidiStayId, 80) || `ratehawk:${hid}`,
    provider: RATEHAWK_STAY_CARD_SOURCE,
    provider_id: hid,
    name: _text(hotel.name, 200),
    type: _text(hotel.type, 40) || "hotel",
    address: _text(hotel.address, 300),
    city: _text(hotel.city, 80),
    region: _text(hotel.region, 80),
    country: _text(hotel.country, 80),
    lat,
    lng,
    image_url: _text(hotel.image_url, 500) || null,
    image_ref: _text(hotel.image_ref, 200) || null,
    rating_label:
      hotel.star_rating != null ? String(hotel.star_rating) : null,
    price_label: rateOffer?.customer_total_label ?? null,
    availability_label:
      rateOffer?.remaining_availability != null
        ? `remaining:${rateOffer.remaining_availability}`
        : null,
    external_url: _text(stay22FallbackUrl, 500) || null,
    provider_label: "RateHawk",
    photo_attribution: hotel.photo_attribution ?? null,
    source: RATEHAWK_STAY_CARD_SOURCE,
    is_real_approved: hotel.content_source === "offline_sync",
  };

  if (!stay.name) {
    return { ok: false, reason: "hotel_name_required", stay: null };
  }

  return {
    ok: true,
    stay,
    ratehawk_hid: hid,
    has_live_ratehawk_availability: Boolean(rateOffer),
    stay22_fallback: Boolean(stay.external_url),
    existing_page_actions_preserved: EXISTING_HOTEL_PAGE_ACTIONS,
    content_source: hotel.content_source || null,
  };
}

export function evaluateRatehawkPrebookChange(beforeOffer, afterOffer) {
  if (!beforeOffer?.ok || !afterOffer?.ok) {
    return {
      ok: false,
      hard_stop: true,
      reason: "prebook_offers_incomplete",
    };
  }
  const before = beforeOffer.customer_total;
  const after = afterOffer.customer_total;
  const currencyChanged = before.currency !== after.currency;
  const amountChanged = before.amount_minor !== after.amount_minor;
  return {
    ok: true,
    price_changed: amountChanged || currencyChanged,
    currency_changed: currencyChanged,
    previous_total: before,
    new_total: after,
    must_redisplay_to_customer: amountChanged || currencyChanged,
    auto_finish_forbidden: true,
  };
}

/**
 * Privacy-minimized acceptance snapshot. No card data, CVC, API keys,
 * or extra guest PII.
 */
export function buildRatehawkAcceptanceSnapshot({
  hid,
  bookHash,
  roomName,
  offer,
  prebook,
  locale = "en",
  providerBookingReference = null,
  termsRevision = null,
  acceptedAt = null,
} = {}) {
  if (!offer?.ok) {
    return { ok: false, reason: "offer_required" };
  }
  return {
    ok: true,
    snapshot_kind: "ratehawk_acceptance_v1",
    accepted_at: acceptedAt,
    locale,
    hotel: { provider: RATEHAWK_PROVIDER, hid: _text(hid, 40) || null },
    room_rate: {
      book_hash: _text(bookHash, 256) || offer.book_hash,
      room_name: _text(roomName, 200) || offer.room_name,
      meal_plan: offer.meal_plan,
      breakfast_included: offer.breakfast_included === true,
    },
    customer_total: offer.customer_total,
    included_taxes: offer.included_taxes,
    excluded_taxes: offer.excluded_taxes,
    payment: {
      type: offer.payment.payment_type,
      recipient: offer.payment.payment_recipient,
      timing: offer.payment.payment_timing,
      customer_pays: offer.payment.customer_pays,
    },
    cancellation: {
      refundable: offer.refundable === true,
      free_cancellation_before: offer.free_cancellation_before,
      penalties: offer.cancellation_penalties,
      no_show: offer.no_show,
    },
    prebook: prebook
      ? {
          price_changed: prebook.price_changed === true,
          previous_total: prebook.previous_total ?? null,
          new_total: prebook.new_total ?? null,
        }
      : null,
    provider_booking_reference: _text(providerBookingReference, 80) || null,
    terms_revision: _text(termsRevision, 120) || null,
    fluxidi_affiliate_remuneration_percent:
      RATEHAWK_AFFILIATE_REMUNERATION_PERCENT,
    omitted: Object.freeze([
      "card_data",
      "cvc",
      "api_credentials",
      "guest_document_numbers",
      "raw_provider_payload",
    ]),
  };
}

export function assertOfflineContentNotUsedDuringLiveRender(context) {
  const mode = _lower(context);
  if (mode === "live_card_render" || mode === "live_search") {
    return {
      ok: false,
      reason: "static_content_forbidden_during_live_render",
    };
  }
  if (mode === "offline_sync") {
    return { ok: true, reason: null };
  }
  return { ok: false, reason: "content_sync_context_required" };
}
