// TAP-TO-PAY-SERVER-CONTRACT-1 — pure helpers for driver Mollie POS terminal payments.
//
// Run: node --test workers/booking/modules/pos_terminal_payment.test.mjs
//
// SAFETY CONTRACT
// ---------------
//  * Terminal charge amount is derived SERVER-SIDE from the canonical booking
//    record. A client-supplied amount is never trusted.
//  * A card-terminal payment is only "paid" when Mollie reports `paid`.
//    Every other status keeps the ride unpaid.

import {
  filterSelectablePosTerminals,
  isTerminalExcluded,
} from "./mollie_terminal_exclusion.mjs";

function _asObject(v) {
  return v && typeof v === "object" && !Array.isArray(v) ? v : {};
}

function _str(v, max = 200) {
  if (v === null || v === undefined) return "";
  const s = String(v).trim();
  return max > 0 ? s.slice(0, max) : s;
}

function _numOrNull(v) {
  if (v === null || v === undefined || v === "") return null;
  const n = typeof v === "string" ? Number(v.trim()) : Number(v);
  return Number.isFinite(n) ? n : null;
}

function _positiveEuro(v) {
  const n = _numOrNull(v);
  if (n == null || n <= 0) return null;
  return n;
}

function _eurToCents(value) {
  const n = _positiveEuro(value);
  if (n == null) return null;
  return Math.round(n * 100);
}

function _asIntCents(value) {
  if (value == null || value === "") return null;
  const n = typeof value === "string" ? Number(value.trim()) : Number(value);
  if (!Number.isFinite(n)) return null;
  const c = Math.round(n);
  return c > 0 ? c : null;
}

function _pickFirstPositive(candidates) {
  for (const c of candidates) {
    const n = _positiveEuro(c);
    if (n != null) return n;
  }
  return null;
}

function _legTypeToken(legType) {
  const t = _str(legType, 32).toLowerCase();
  return t === "return" ? "return" : t ? "outbound" : "";
}

function _recordSources(rec) {
  const record = _asObject(rec);
  const booking = _asObject(record.booking);
  const nested = _asObject(record.record);
  const quote = _asObject(record.quote) || _asObject(booking.quote) || _asObject(nested.quote);
  const pricing = _asObject(quote.pricing);
  const pricingMain = _asObject(quote.pricing_main) || _asObject(quote.pricingMain);
  const pricingReturn = _asObject(quote.pricing_return) || _asObject(quote.pricingReturn);
  return [record, booking, nested, quote, pricing, pricingMain, pricingReturn];
}

function _resolveCurrency(rec) {
  const sources = _recordSources(rec);
  for (const src of sources) {
    const c = _str(src.currency, 8).toUpperCase();
    if (c) return c;
  }
  return "EUR";
}

function _finalizeAmountResult({
  euro,
  source,
  currency,
  maxCents,
  clientAmountRaw,
}) {
  if (currency !== "EUR") {
    return { ok: false, error: "unsupported_currency", currency };
  }
  const cents = _eurToCents(euro);
  if (cents == null || !Number.isInteger(cents) || cents <= 0) {
    return { ok: false, error: "amount_unavailable", currency };
  }
  if (cents > maxCents) {
    return { ok: false, error: "amount_out_of_range", currency };
  }

  // Client amount is never authoritative: ignore it and keep the server amount.
  let ignored_client = false;
  if (clientAmountRaw !== undefined && clientAmountRaw !== null && String(clientAmountRaw).trim() !== "") {
    ignored_client = true;
  }

  return {
    ok: true,
    currency,
    cents,
    value: (cents / 100).toFixed(2),
    source,
    ignored_client,
  };
}

/**
 * True when the record is a driver-started street / direct ride.
 */
export function isStreetDirectBookingRecord(rec) {
  if (!rec || typeof rec !== "object") return false;
  const source = _str(
    rec.source ??
      rec.booking_source ??
      rec.booking?.source ??
      rec.booking?.booking_source,
    64,
  ).toLowerCase();
  const rideType = _str(rec.ride_type ?? rec.booking?.ride_type, 64).toLowerCase();
  const id = _str(rec.booking_id ?? rec.bookingId, 160).toLowerCase();
  return source === "street_ride" || rideType === "direct" || id.startsWith("street_");
}

function _resolveStreetFinalizedAmount(rec) {
  const record = _asObject(rec);
  if (
    record.street_ride_fare_finalized !== true &&
    record.streetRideFareFinalized !== true
  ) {
    return { ok: false, error: "street_fare_not_finalized", currency: _resolveCurrency(rec) };
  }
  const booking = _asObject(record.booking);
  const euro = _pickFirstPositive([
    record.price_incl_vat,
    record.priceInclVat,
    booking.price_incl_vat,
    booking.priceInclVat,
  ]);
  if (euro == null) {
    return { ok: false, error: "amount_unavailable", currency: _resolveCurrency(rec) };
  }
  return { euro, source: "street_finalized" };
}

function _resolvePlannedAmount(rec, { legId, legType } = {}) {
  const sources = _recordSources(rec);
  const wantedLegType = _legTypeToken(legType);

  for (const src of sources) {
    const legPrice = _pickFirstPositive([src.leg_price_incl_vat, src.legPriceInclVat]);
    if (legPrice != null) {
      return { euro: legPrice, source: "leg_price_incl_vat" };
    }
  }

  if (wantedLegType === "return") {
    for (const src of sources) {
      const returnPrice = _pickFirstPositive([
        src.price_incl_vat_return,
        src.priceInclVatReturn,
      ]);
      if (returnPrice != null) {
        return { euro: returnPrice, source: "price_incl_vat_return" };
      }
    }
  } else {
    for (const src of sources) {
      const mainPrice = _pickFirstPositive([
        src.price_incl_vat_main,
        src.priceInclVatMain,
      ]);
      if (mainPrice != null) {
        return { euro: mainPrice, source: "price_incl_vat_main" };
      }
    }
  }

  for (const src of sources) {
    const canonical = _pickFirstPositive([
      src.price_incl_vat,
      src.priceInclVat,
      src.total_price_incl_vat,
      src.totalPriceInclVat,
    ]);
    if (canonical != null) {
      return { euro: canonical, source: "price_incl_vat" };
    }
  }

  for (const src of sources) {
    const cents = _asIntCents(src.price_incl_vat_cents ?? src.total_price_incl_vat_cents);
    if (cents != null) {
      return { euro: cents / 100, source: "price_incl_vat" };
    }
  }

  return null;
}

/**
 * Server-side canonical terminal amount for a driver-initiated POS payment.
 */
export function resolveDriverPosTerminalAmount(rec, options = {}) {
  const maxCents = Number.isFinite(options.maxCents) ? options.maxCents : 100000;
  const record = _asObject(rec);
  const currency = _resolveCurrency(record);
  const clientAmountRaw = options.clientAmountRaw;

  let resolved;
  if (isStreetDirectBookingRecord(record)) {
    resolved = _resolveStreetFinalizedAmount(record);
    if ("error" in resolved) return resolved;
    return _finalizeAmountResult({
      euro: resolved.euro,
      source: resolved.source,
      currency,
      maxCents,
      clientAmountRaw,
    });
  }

  const planned = _resolvePlannedAmount(record, {
    legId: options.legId,
    legType: options.legType,
  });
  if (planned == null) {
    return { ok: false, error: "amount_unavailable", currency };
  }
  return _finalizeAmountResult({
    euro: planned.euro,
    source: planned.source,
    currency,
    maxCents,
    clientAmountRaw,
  });
}

/**
 * Backward-compatible wrapper without client amount input.
 */
export function normalizeDriverPosTerminalAmountFromRecord(rec, options = {}) {
  const { clientAmountRaw: _ignored, ...rest } = options;
  const out = resolveDriverPosTerminalAmount(rec, rest);
  if (!out.ok) return out;
  return {
    ok: true,
    currency: out.currency,
    cents: out.cents,
    value: out.value,
  };
}

export function classifyMolliePosStatus(status) {
  const s = String(status ?? "")
    .trim()
    .toLowerCase();
  if (s === "paid") return "paid";
  if (s === "failed" || s === "canceled" || s === "cancelled" || s === "expired") {
    return "failed";
  }
  if (
    s === "open" ||
    s === "pending" ||
    s === "authorized" ||
    s === "created" ||
    s === "settled"
  ) {
    return "pending";
  }
  return "unknown";
}

export function molliePosStatusIsPaid(status) {
  return classifyMolliePosStatus(status) === "paid";
}

export function selectServerSidePosTerminal(terminals, opts = {}) {
  // MOLLIE-TERMINAL-UNLINK-AND-EXCLUSION-P1: never select excluded/unlinked.
  const list = filterSelectablePosTerminals(
    Array.isArray(terminals) ? terminals : [],
    opts.excludedMap ?? opts.excluded_terminals,
  );
  const wantProfile = String(opts.profileId ?? "").trim();
  const candidates = list.filter((t) => {
    if (!t || typeof t !== "object") return false;
    if (!String(t.id ?? "").trim()) return false;
    if (String(t.status ?? "").trim().toLowerCase() !== "active") return false;
    if (isTerminalExcluded(t, opts.excludedMap ?? opts.excluded_terminals)) {
      return false;
    }
    const tProfile = String(t.profile_id ?? t.profileId ?? "").trim();
    if (wantProfile) {
      if (!tProfile || tProfile !== wantProfile) return false;
    }
    return true;
  });
  if (candidates.length === 0) {
    return { ok: false, error: "terminal_not_configured" };
  }
  if (candidates.length === 1) {
    return { ok: true, terminal: candidates[0], selection: "single" };
  }
  const wantDefault = String(opts.defaultTerminalId ?? "").trim();
  if (wantDefault) {
    const match = candidates.find((t) => String(t.id).trim() === wantDefault);
    if (match) return { ok: true, terminal: match, selection: "default" };
  }
  return { ok: false, error: "terminal_selection_required" };
}

export function validatePosDefaultTerminalCandidate(terminals, terminalId, opts = {}) {
  const wantId = String(terminalId ?? "").trim();
  if (!wantId) return { ok: false, error: "terminal_id_required" };
  const excludedMap = opts.excludedMap ?? opts.excluded_terminals;
  const list = filterSelectablePosTerminals(
    Array.isArray(terminals) ? terminals : [],
    excludedMap,
  );
  const match = list.find(
    (t) => t && typeof t === "object" && String(t.id ?? "").trim() === wantId,
  );
  if (!match) {
    if (isTerminalExcluded(wantId, excludedMap)) {
      return { ok: false, error: "terminal_excluded" };
    }
    return { ok: false, error: "terminal_not_found" };
  }
  if (String(match.status ?? "").trim().toLowerCase() !== "active") {
    return { ok: false, error: "terminal_inactive" };
  }
  if (isTerminalExcluded(match, excludedMap)) {
    return { ok: false, error: "terminal_excluded" };
  }
  const wantProfile = String(opts.profileId ?? "").trim();
  if (wantProfile) {
    const tProfile = String(match.profile_id ?? match.profileId ?? "").trim();
    if (!tProfile || tProfile !== wantProfile) {
      return { ok: false, error: "terminal_profile_mismatch" };
    }
  }
  return { ok: true, terminal: match };
}

export function resolveEffectiveDefaultTerminalId(terminals, storedDefaultId, opts = {}) {
  const wantProfile = String(opts.profileId ?? "").trim();
  const excludedMap = opts.excludedMap ?? opts.excluded_terminals;
  const list = filterSelectablePosTerminals(
    Array.isArray(terminals) ? terminals : [],
    excludedMap,
  );
  const activeCandidates = list.filter((t) => {
    if (!t || typeof t !== "object") return false;
    if (!String(t.id ?? "").trim()) return false;
    if (String(t.status ?? "").trim().toLowerCase() !== "active") return false;
    if (isTerminalExcluded(t, excludedMap)) return false;
    if (wantProfile) {
      const tp = String(t.profile_id ?? t.profileId ?? "").trim();
      if (!tp || tp !== wantProfile) return false;
    }
    return true;
  });
  const activeCount = activeCandidates.length;
  if (activeCount === 1) {
    return {
      defaultTerminalId: String(activeCandidates[0].id).trim(),
      autoSingle: true,
      cleared: false,
      activeCount,
    };
  }
  const stored = String(storedDefaultId ?? "").trim();
  if (stored) {
    const match = activeCandidates.find((t) => String(t.id).trim() === stored);
    if (match) {
      return { defaultTerminalId: stored, autoSingle: false, cleared: false, activeCount };
    }
    return { defaultTerminalId: null, autoSingle: false, cleared: true, activeCount };
  }
  return { defaultTerminalId: null, autoSingle: false, cleared: false, activeCount };
}

export function posTerminalSnapshotModeMatches(snapshot, { expectTestmode = false } = {}) {
  const snap = _asObject(snapshot);
  const snapTest =
    snap.testmode === true || String(snap.mollie_mode ?? "").toLowerCase() === "test";
  return snapTest === (expectTestmode === true);
}

export function maskPosTerminalId(terminalId) {
  const id = String(terminalId ?? "").trim();
  if (!id) return "-";
  if (id.length <= 4) return "****";
  return `${id.slice(0, 2)}***${id.slice(-2)}`;
}

export function posTerminalIdempotencyDecision(existingIntent) {
  const rec = _asObject(existingIntent);
  const paymentId = String(rec.payment_id ?? rec.paymentId ?? "").trim();
  const status = String(rec.mollie_status ?? rec.status ?? "")
    .trim()
    .toLowerCase();
  if (paymentId && ["open", "pending", "authorized", "created"].includes(status)) {
    return { action: "reuse", paymentId, status };
  }
  return { action: "create", paymentId: paymentId || null, status: status || null };
}

export function posTerminalDiagnosticsLine({
  phase,
  amountCents = 0,
  currency = "EUR",
  providerStatus = null,
  providerCode = null,
  referencePresent = false,
  callbackPresent = false,
  paymentWritten = false,
  reason = "",
  schemaVersion = "POS-DRV-1",
}) {
  const status = String(providerStatus ?? "").trim();
  const code = String(providerCode ?? "").trim();
  return (
    "[CARD_TERMINAL_PAYMENT] " +
    `phase=${phase} ` +
    `schemaVersion=${schemaVersion} ` +
    `amountCents=${amountCents} ` +
    `currency=${currency} ` +
    `providerStatus=${status || "-"} ` +
    `providerCode=${code || "-"} ` +
    `referencePresent=${referencePresent} ` +
    `callbackPresent=${callbackPresent} ` +
    `paymentWritten=${paymentWritten} ` +
    `reason=${reason || "-"}`
  );
}

export function buildScopedDriverPosPaymentIntentKey(scope, bookingId, legId) {
  const s = _asObject(scope);
  const tenant = _str(s.tenantId ?? s.tenant_id ?? s.tenant, 120);
  const company = _str(s.companyId ?? s.company_id ?? s.company, 120);
  const booking = _str(bookingId, 160);
  const legOrMain = _str(legId, 160) || "main";
  return `tenant:${tenant}:company:${company}:mollie_driver_pos_intent:${booking}:${legOrMain}:v1`;
}

/** Mollie Idempotency-Key hard limit (documented + field-proven). */
export const MOLLIE_POS_IDEMPOTENCY_KEY_MAX_LEN = 100;

/**
 * Canonical source string hashed into the Mollie Idempotency-Key.
 * Includes intent key + live/test so environments cannot collide.
 */
export function buildMolliePosIdempotencyCanonicalSource(
  intentKey,
  mollieMode = "live",
) {
  const intent = _str(intentKey, 400);
  const mode =
    String(mollieMode ?? "").trim().toLowerCase() === "test" ? "test" : "live";
  return `${intent}:${mode}:v1`;
}

async function _sha256Hex(text) {
  const data = new TextEncoder().encode(String(text ?? ""));
  const digest = await crypto.subtle.digest("SHA-256", data);
  const bytes = new Uint8Array(digest);
  let hex = "";
  for (const byte of bytes) hex += byte.toString(16).padStart(2, "0");
  return hex;
}

/**
 * Deterministic Mollie Idempotency-Key for POS create.
 * Always <= 100 chars. Never random. Same intent+mode => same key.
 *
 * Format: fluxidi-pos-v1:<64-char-sha256-hex>  (79 chars)
 */
export async function buildMolliePosIdempotencyKey(
  intentKey,
  mollieMode = "live",
) {
  const source = buildMolliePosIdempotencyCanonicalSource(intentKey, mollieMode);
  if (!_str(intentKey, 400)) return "";
  const hex = await _sha256Hex(source);
  const key = `fluxidi-pos-v1:${hex}`;
  if (key.length > MOLLIE_POS_IDEMPOTENCY_KEY_MAX_LEN) {
    // Defensive: format is fixed-length; fail closed rather than send oversize.
    return key.slice(0, MOLLIE_POS_IDEMPOTENCY_KEY_MAX_LEN);
  }
  return key;
}

/**
 * Legacy oversize key form that Mollie rejected in field evidence
 * (raw intent key with non [A-Za-z0-9_-] replaced by `_`).
 * Exported only for regression tests / length proof.
 */
export function legacyOversizedMolliePosIdempotencyKey(intentKey) {
  return _str(intentKey, 400).replace(/[^a-zA-Z0-9_-]+/g, "_");
}

/** TTL for Tap-to-Pay create-failure diagnostics (14 days). */
export const DRIVER_POS_START_FAIL_DIAG_TTL_SECONDS = 60 * 60 * 24 * 14;

/**
 * Latest failure for a booking (Agent read path).
 * tenant + company + booking scoped.
 */
export function buildScopedDriverPosStartFailLatestKey(scope, bookingId) {
  const s = _asObject(scope);
  const tenant = _str(s.tenantId ?? s.tenant_id ?? s.tenant, 120);
  const company = _str(s.companyId ?? s.company_id ?? s.company, 120);
  const booking = _str(bookingId, 160);
  if (!tenant || !company || !booking) return "";
  return `tenant:${tenant}:company:${company}:mollie_driver_pos_start_fail:${booking}:latest:v1`;
}

/**
 * Per-attempt failure key (tenant + company + booking + attempt).
 */
export function buildScopedDriverPosStartFailAttemptKey(scope, bookingId, attemptId) {
  const s = _asObject(scope);
  const tenant = _str(s.tenantId ?? s.tenant_id ?? s.tenant, 120);
  const company = _str(s.companyId ?? s.company_id ?? s.company, 120);
  const booking = _str(bookingId, 160);
  const attempt = _str(attemptId, 80).replace(/[^a-zA-Z0-9_-]+/g, "_");
  if (!tenant || !company || !booking || !attempt) return "";
  return `tenant:${tenant}:company:${company}:mollie_driver_pos_start_fail:${booking}:${attempt}:v1`;
}

export function newDriverPosStartFailAttemptId(nowMs = Date.now()) {
  const rand = Math.floor(Math.random() * 1e9).toString(36);
  return `att_${Number(nowMs).toString(36)}_${rand}`;
}

function _safeUrlPresence(url) {
  const raw = _str(url, 500);
  if (!raw) {
    return { present: false, host: null };
  }
  try {
    const u = new URL(raw);
    return { present: true, host: _str(u.host, 120) || null };
  } catch (_) {
    return { present: true, host: null };
  }
}

/**
 * Sanitized contract proof for the Mollie Create Payment call about to be sent.
 * Never includes Authorization / OAuth tokens.
 */
export function buildDriverPosCreateRequestContract({
  terminalId,
  amount,
  profileId,
  webhookUrl,
  redirectUrl,
  testmode = false,
  apiPath = "/v2/payments",
} = {}) {
  const amountObj = _asObject(amount);
  const webhook = _safeUrlPresence(webhookUrl);
  const redirect = _safeUrlPresence(redirectUrl);
  return {
    api: `POST ${_str(apiPath, 80) || "/v2/payments"}`,
    method: "pointofsale",
    terminalId: _str(terminalId, 120) || null,
    amount: {
      currency: _str(amountObj.currency, 8).toUpperCase() || null,
      value: _str(amountObj.value, 32) || null,
    },
    profileId: _str(profileId, 80) || null,
    profileId_present: !!_str(profileId, 80),
    webhookUrl_present: webhook.present,
    webhookUrl_host: webhook.host,
    redirectUrl_present: redirect.present,
    redirectUrl_host: redirect.host,
    testmode: testmode === true,
    mollie_mode: testmode === true ? "test" : "live",
  };
}

/**
 * Extract sanitized Mollie rejection fields from a Create Payment response body.
 * Does not invent title/detail when the provider never answered (timeout).
 */
export function sanitizeMollieCreateRejection({
  httpStatus = null,
  body = null,
  requestId = null,
  networkError = false,
} = {}) {
  if (networkError === true) {
    return {
      category: "mollie_network_error",
      http_status: null,
      title: null,
      detail: null,
      code: null,
      field: null,
      request_id: _str(requestId, 120) || null,
    };
  }
  const obj = _asObject(body);
  const statusNum = Number(httpStatus);
  const http =
    Number.isFinite(statusNum) && statusNum > 0 ? Math.trunc(statusNum) : null;
  let category = "mollie_create_rejected";
  if (http != null && http >= 500) category = "mollie_http_5xx";
  else if (http != null && http >= 400) category = "mollie_http_4xx";
  return {
    category,
    http_status: http,
    title: _str(obj.title, 160) || null,
    detail: _str(obj.detail, 400) || null,
    code: _str(obj.code ?? obj.error ?? obj.name, 80) || null,
    field: _str(obj.field, 80) || null,
    // Prefer HTTP request-id header; never treat Mollie payment id as correlation.
    request_id:
      _str(requestId, 120) ||
      _str(obj.request_id ?? obj.requestId, 120) ||
      null,
  };
}

/**
 * Full durable diagnostic record for a failed driver Tap create.
 * Must never include secrets / Authorization / OAuth tokens.
 */
export function buildDriverPosStartFailureDiagnostic({
  scope,
  bookingId,
  terminalId,
  profileId,
  amount,
  testmode = false,
  requestContract = null,
  rejection = null,
  attemptId = null,
  nowIso = null,
} = {}) {
  const s = _asObject(scope);
  const tenant = _str(s.tenantId ?? s.tenant_id ?? s.tenant, 120);
  const company = _str(s.companyId ?? s.company_id ?? s.company, 120);
  const booking = _str(bookingId, 160);
  const attempt = _str(attemptId, 80) || newDriverPosStartFailAttemptId();
  const ts = _str(nowIso, 40) || new Date().toISOString();
  const amountObj = _asObject(amount);
  const rej = _asObject(rejection);
  const contract = _asObject(requestContract);

  const record = {
    version: 1,
    kind: "mollie_driver_pos_start_fail",
    timestamp: ts,
    attempt_id: attempt,
    tenant_id: tenant || null,
    company_id: company || null,
    booking_id: booking || null,
    terminal_id: _str(terminalId, 120) || null,
    profile_id: _str(profileId, 80) || null,
    testmode: testmode === true,
    mollie_mode: testmode === true ? "test" : "live",
    amount: {
      currency: _str(amountObj.currency, 8).toUpperCase() || null,
      value: _str(amountObj.value, 32) || null,
    },
    request_method: "pointofsale",
    request_contract: Object.keys(contract).length ? contract : null,
    mollie_http_status: rej.http_status ?? null,
    mollie_title: rej.title ?? null,
    mollie_detail: rej.detail ?? null,
    mollie_error_code: rej.code ?? null,
    mollie_field: rej.field ?? null,
    mollie_request_id: rej.request_id ?? null,
    provider_category: _str(rej.category, 60) || "mollie_create_rejected",
    fluxidi_error: "mollie_terminal_payment_create_failed",
  };

  return {
    attempt_id: attempt,
    keys: {
      latest: buildScopedDriverPosStartFailLatestKey(
        { tenant_id: tenant, company_id: company },
        booking,
      ),
      attempt: buildScopedDriverPosStartFailAttemptKey(
        { tenant_id: tenant, company_id: company },
        booking,
        attempt,
      ),
    },
    record,
    ttl_seconds: DRIVER_POS_START_FAIL_DIAG_TTL_SECONDS,
  };
}

/**
 * True when a diagnostic JSON/string contains forbidden secret material.
 * Used by tests; also a last-line guard before KV put.
 */
export function driverPosStartFailDiagContainsSecrets(value) {
  const text =
    typeof value === "string"
      ? value
      : value == null
        ? ""
        : JSON.stringify(value);
  if (!text) return false;
  if (/access[_-]?token/i.test(text)) return true;
  if (/refresh[_-]?token/i.test(text)) return true;
  if (/authorization/i.test(text)) return true;
  if (/Bearer\s+[A-Za-z0-9._\-]+/i.test(text)) return true;
  if (/live_[A-Za-z0-9]{10,}/.test(text)) return true;
  if (/test_[A-Za-z0-9]{10,}/.test(text)) return true;
  return false;
}

export function isBookingAlreadyPaid(rec) {
  const record = _asObject(rec);
  const booking = _asObject(record.booking);
  for (const status of [
    record.payment_status,
    record.paymentStatus,
    booking.payment_status,
    booking.paymentStatus,
  ]) {
    if (String(status ?? "").trim().toLowerCase() === "paid") return true;
  }
  return false;
}

export function shouldMarkBookingPaidFromPosStatus(status) {
  return molliePosStatusIsPaid(status);
}

export function shouldTriggerBillitSyncOnPosPaid({ wasAlreadyPaid, newlyPaid } = {}) {
  return newlyPaid === true && wasAlreadyPaid !== true;
}
