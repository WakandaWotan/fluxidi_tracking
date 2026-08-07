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
