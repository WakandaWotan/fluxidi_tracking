/* Shared low-risk parsing helpers.
 * Moved verbatim from fluxidi_booking_worker.js (patch BW-M1), no behavior change. */

export function safeStr(v) {
  if (v === null || v === undefined) return "";
  return String(v).trim();
}

export function money2(value) {
  // Robust euro number parsing: accepts numbers, "143.24", "143,24", "€ 143,24"
  if (value == null) return "0.00";
  let s = String(value).trim();
  // keep digits, dot, comma, minus
  s = s.replace(/[^0-9,\.\-]/g, "");
  // If we have both comma and dot, assume dot is thousands sep and comma is decimal (e.g. 1.234,56)
  if (s.includes(",") && s.includes(".")) {
    // remove dots (thousands), then replace comma with dot
    s = s.replace(/\./g, "").replace(/,/g, ".");
  } else {
    // otherwise just replace comma with dot
    s = s.replace(/,/g, ".");
  }
  const n = Number(s);
  if (!Number.isFinite(n)) return "0.00";
  return (Math.round(n * 100) / 100).toFixed(2);
}

export function envFlag(value) {
  return ["1", "true", "yes", "on"].includes(String(value ?? "").trim().toLowerCase());
}

export function to2(n) { return (Math.round(Number(n || 0) * 100) / 100).toFixed(2); }

export function round2(n) {
  // keep monetary rounding consistent
  return to2(n);
}

export function sanitizeTenantString(value, maxLength = 240) {
  const text = String(value == null ? "" : value).replace(/\0/g, "").trim();
  return text.length > maxLength ? text.slice(0, maxLength) : text;
}

export function getBaseUrl(request) {
  const u = new URL(request.url);
  return `${u.protocol}//${u.host}`;
}

export function boolish(value) {
  if (value === true) return true;
  if (value === false || value == null) return false;
  const s = String(value).trim().toLowerCase();
  return s === "true" || s === "1" || s === "yes" || s === "y" || s === "on";
}
