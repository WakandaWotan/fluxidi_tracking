// Prepaid PDF credits — purchased packs never expire and are never recurring.
// Source of truth: pdf_purchased_credits_remaining (+ grant totals / last granted).
// pdf_monthly_allowance is ONLY a derived legacy projection for old clients.

export const INCLUDED_PDF_PER_VEHICLE_MONTH = 200;

const PACK_CREDITS = {
  pdf_500: 500,
  pdf_1000: 1000,
  pdf_5000: 5000,
};

function _qty(v) {
  const n = Math.trunc(Number(v) || 0);
  return Number.isFinite(n) && n > 0 ? n : 0;
}

function _nonNeg(v) {
  const n = Math.trunc(Number(v) || 0);
  return Number.isFinite(n) && n > 0 ? n : 0;
}

function _str(v, max = 48) {
  if (v == null) return "";
  return String(v).trim().slice(0, max);
}

export function pdfPackCreditsForCode(addonCode) {
  const code = _str(addonCode, 64).toLowerCase();
  return PACK_CREDITS[code] || 0;
}

export function includedPdfCap(profile, {
  perVehicle = INCLUDED_PDF_PER_VEHICLE_MONTH,
} = {}) {
  const maxVehicles = Math.max(0, Math.trunc(Number(profile?.max_vehicles) || 0));
  return maxVehicles * Math.max(0, Math.trunc(Number(perVehicle) || 0));
}

/** Legacy field must always equal purchased remaining — never a second balance. */
export function projectLegacyPdfMonthlyAllowance(profile) {
  return _nonNeg(profile?.pdf_purchased_credits_remaining);
}

/**
 * Apply legacy projection onto profile (single write shape for saves/responses).
 */
export function withLegacyPdfAllowanceProjection(profile) {
  if (!profile || typeof profile !== "object") return profile;
  const remaining = _nonNeg(profile.pdf_purchased_credits_remaining);
  return {
    ...profile,
    pdf_purchased_credits_remaining: remaining,
    pdf_monthly_allowance: remaining,
  };
}

/**
 * Grant purchased credits once for a verified pack activation.
 * Caller must enforce activation_id / applied-marker idempotency before calling.
 */
export function grantPurchasedPdfCredits(profile, {
  credits,
  grantedAt,
  quantity = 1,
} = {}) {
  if (!profile || typeof profile !== "object") {
    return { ok: false, error: "missing_profile" };
  }
  const unit = Math.max(0, Math.trunc(Number(credits) || 0));
  const qty = Math.max(1, Math.trunc(Number(quantity) || 1));
  const add = unit * qty;
  if (add <= 0) return { ok: false, error: "invalid_credits" };
  const prevRemaining = _nonNeg(profile.pdf_purchased_credits_remaining);
  const prevGranted = _nonNeg(profile.pdf_purchased_credits_granted_total);
  const at = _str(grantedAt, 48) || new Date().toISOString();
  const next = withLegacyPdfAllowanceProjection({
    ...profile,
    pdf_purchased_credits_remaining: prevRemaining + add,
    pdf_purchased_credits_granted_total: prevGranted + add,
    pdf_purchased_last_granted_at: at,
  });
  return { ok: true, granted: add, profile: next };
}

/**
 * Consume one successful PDF creation.
 * Burns included monthly usage first, then purchased remaining.
 * Failed generation must not call this.
 */
export function consumePdfCreation(profile, {
  count = 1,
  perVehicle = INCLUDED_PDF_PER_VEHICLE_MONTH,
} = {}) {
  if (!profile || typeof profile !== "object") {
    return { ok: false, error: "missing_profile" };
  }
  let left = Math.max(0, Math.trunc(Number(count) || 0));
  if (left <= 0) {
    return { ok: true, consumed_included: 0, consumed_purchased: 0, profile };
  }
  const cap = includedPdfCap(profile, { perVehicle });
  let used = _nonNeg(profile.pdf_monthly_used);
  let purchased = _nonNeg(profile.pdf_purchased_credits_remaining);
  let consumedIncluded = 0;
  let consumedPurchased = 0;

  const includedLeft = Math.max(0, cap - used);
  const takeIncluded = Math.min(left, includedLeft);
  used += takeIncluded;
  consumedIncluded += takeIncluded;
  left -= takeIncluded;

  const takePurchased = Math.min(left, purchased);
  purchased -= takePurchased;
  consumedPurchased += takePurchased;
  left -= takePurchased;

  if (left > 0) {
    return {
      ok: false,
      error: "insufficient_pdf_credits",
      shortfall: left,
      profile,
    };
  }

  return {
    ok: true,
    consumed_included: consumedIncluded,
    consumed_purchased: consumedPurchased,
    profile: withLegacyPdfAllowanceProjection({
      ...profile,
      pdf_monthly_used: used,
      pdf_purchased_credits_remaining: purchased,
    }),
  };
}

/** Period rollover: reset included usage only; purchased untouched. */
export function resetIncludedPdfUsageForNewPeriod(profile) {
  if (!profile || typeof profile !== "object") return profile;
  return withLegacyPdfAllowanceProjection({
    ...profile,
    pdf_monthly_used: 0,
  });
}

/**
 * Rebuild purchased remaining from verified paid history entries.
 * Does not invent credits for non-pdf codes. Idempotent sum of pack sizes × qty.
 */
export function sumPurchasedCreditsFromHistoryEntries(entries = []) {
  let total = 0;
  let lastGrantedAt = "";
  let lastMs = 0;
  const seen = new Set();
  for (const e of Array.isArray(entries) ? entries : []) {
    const act = _str(e?.activation_id, 80);
    if (act) {
      if (seen.has(act)) continue;
      seen.add(act);
    }
    const credits = pdfPackCreditsForCode(e?.addon_code);
    if (credits <= 0) continue;
    const qty = Math.max(1, Math.trunc(Number(e?.quantity) || 1));
    total += credits * qty;
    const at = _str(e?.applied_at || e?.paid_at || e?.granted_at, 48);
    const ms = at ? Date.parse(at) : NaN;
    if (at && Number.isFinite(ms) && ms >= lastMs) {
      lastMs = ms;
      lastGrantedAt = at;
    }
  }
  return { granted_total: total, remaining: total, last_granted_at: lastGrantedAt };
}

/** Clear PDF cancel-schedule fields (packs are prepaid; cancel is unsupported). */
export function clearPdfCancellationSchedules(profile) {
  if (!profile || typeof profile !== "object") return profile;
  return {
    ...profile,
    pdf500_cancel_at_period_end_quantity: 0,
    pdf500_cancel_requested_at: "",
    pdf500_cancellation_effective_at: "",
    pdf1000_cancel_at_period_end_quantity: 0,
    pdf1000_cancel_requested_at: "",
    pdf1000_cancellation_effective_at: "",
    pdf5000_cancel_at_period_end_quantity: 0,
    pdf5000_cancel_requested_at: "",
    pdf5000_cancellation_effective_at: "",
  };
}

export function packQtyFieldsFromHistory(entries = []) {
  let pdf500 = 0;
  let pdf1000 = 0;
  let pdf5000 = 0;
  const seen = new Set();
  for (const e of Array.isArray(entries) ? entries : []) {
    const act = _str(e?.activation_id, 80);
    if (act) {
      if (seen.has(act)) continue;
      seen.add(act);
    }
    const code = _str(e?.addon_code, 64).toLowerCase();
    const qty = Math.max(1, Math.trunc(Number(e?.quantity) || 1));
    if (code === "pdf_500") pdf500 += qty;
    else if (code === "pdf_1000") pdf1000 += qty;
    else if (code === "pdf_5000") pdf5000 += qty;
  }
  return {
    pdf500_active_quantity: pdf500,
    pdf1000_active_quantity: pdf1000,
    pdf5000_active_quantity: pdf5000,
  };
}

// silence unused in some bundlers
void _qty;
