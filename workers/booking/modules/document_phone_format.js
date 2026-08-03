// FLUXIDI-INVOICE-RECOVERY-ACCEPTANCE-AND-PRESENTATION-P0-1
//
// Safe document-facing phone display helpers. Does not mutate stored identity
// values — callers pass the stored string and render the returned display
// form. Fixes the common Belgian E.164 typo `+3204…` → `+324…` for display
// and formats BE mobiles as `+32 4XX XX XX XX`.

function _digits(s) {
  return String(s || "").replace(/\D+/g, "");
}

/**
 * Normalize a phone string for *display* only.
 * - Collapses whitespace
 * - Rewrites `+3204XXXXXXXX` → `+324XXXXXXXX` (and `003204…`)
 * - Formats Belgian mobiles as `+32 4XX XX XX XX`
 * - Returns empty string for empty/whitespace input
 * - Returns a lightly cleaned original for unrecognized formats
 */
export function formatDocumentPhoneDisplay(raw) {
  if (raw === undefined || raw === null) return "";
  let s = String(raw).trim();
  if (!s) return "";

  // Strip common separators for analysis but keep leading +.
  let compact = s.replace(/[\s().-]/g, "");
  if (compact.startsWith("00")) compact = `+${compact.slice(2)}`;

  // Fix +3204… / 3204… Belgian mobile typo (extra 0 after country code).
  if (/^\+3204\d{8}$/.test(compact)) {
    compact = `+324${compact.slice(5)}`;
  } else if (/^3204\d{8}$/.test(compact)) {
    compact = `+324${compact.slice(4)}`;
  } else if (/^04\d{8}$/.test(compact)) {
    compact = `+32${compact.slice(1)}`;
  }

  // Format BE mobile +324XXXXXXXX
  if (/^\+324\d{8}$/.test(compact)) {
    const n = compact.slice(3); // 4XXXXXXXX
    return `+32 ${n.slice(0, 3)} ${n.slice(3, 5)} ${n.slice(5, 7)} ${n.slice(7, 9)}`;
  }

  // Format BE landline +32X XXX XX XX (8 digits after country code, not starting with 4)
  if (/^\+32[1-9]\d{7}$/.test(compact) && !compact.startsWith("+324")) {
    const n = compact.slice(3);
    return `+32 ${n.slice(0, 1)} ${n.slice(1, 4)} ${n.slice(4, 6)} ${n.slice(6, 8)}`;
  }

  // Generic +E.164: keep + and group remaining digits lightly.
  if (/^\+[1-9]\d{6,14}$/.test(compact)) {
    return compact;
  }

  // Fallback: collapse internal whitespace only.
  return s.replace(/\s+/g, " ").trim();
}

/**
 * True when the string looks like a raw lon,lat / lat,lon coordinate pair
 * that must never be shown as a customer-visible address.
 */
export function looksLikeCoordinatePair(raw) {
  const s = String(raw || "").trim();
  if (!s) return false;
  // Match "50.772006, 3.669447" or "3.669447,50.772006" with optional spaces.
  return /^-?\d{1,3}\.\d+\s*,\s*-?\d{1,3}\.\d+$/.test(s);
}

/**
 * Choose a customer-visible address from candidates. Skips coordinate pairs
 * and empty values. Returns "" when nothing authoritative is available
 * (callers should omit the field or show "Niet opgegeven").
 */
export function pickCustomerVisibleAddress(...candidates) {
  for (const c of candidates) {
    const s = c === undefined || c === null ? "" : String(c).trim();
    if (!s) continue;
    if (looksLikeCoordinatePair(s)) continue;
    // Reject lone placeholders that are not real addresses.
    const lower = s.toLowerCase();
    if (lower === "straatrit" || lower === "street ride" || lower === "—") {
      continue;
    }
    return s;
  }
  return "";
}
