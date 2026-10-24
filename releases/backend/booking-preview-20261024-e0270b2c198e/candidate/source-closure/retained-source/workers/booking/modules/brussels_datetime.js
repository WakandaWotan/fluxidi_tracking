// FLUXIDI-INVOICE-RECOVERY-ACCEPTANCE-AND-PRESENTATION-P0-1
//
// Authoritative company-local datetime formatting for invoice / receipt
// presentation. Stored timestamps remain UTC ISO strings; customer-visible
// dates and times are rendered in the company IANA timezone (default
// Europe/Brussels) with correct DST handling via Intl.
//
// Never uses getUTC* for customer-visible local time.

export const DEFAULT_COMPANY_TIMEZONE = "Europe/Brussels";

/**
 * Resolve the company display timezone. Accepts business profile-like
 * objects or a bare string. Falls back to Europe/Brussels.
 */
export function resolveCompanyTimezone(input) {
  if (typeof input === "string") {
    const t = input.trim();
    return t || DEFAULT_COMPANY_TIMEZONE;
  }
  const obj = input && typeof input === "object" ? input : null;
  if (!obj) return DEFAULT_COMPANY_TIMEZONE;
  const raw =
    (typeof obj.timezone === "string" && obj.timezone) ||
    (typeof obj.time_zone === "string" && obj.time_zone) ||
    (typeof obj.timeZone === "string" && obj.timeZone) ||
    "";
  const t = String(raw).trim();
  return t || DEFAULT_COMPANY_TIMEZONE;
}

/**
 * Format an ISO timestamp into `{ date: "YYYY-MM-DD", time: "HH:MM" }` in
 * the given IANA timezone. Empty / invalid input yields empty strings.
 * Never uses getUTC* for the returned parts.
 */
export function companyDateTimePartsFromIso(
  isoString,
  timezone = DEFAULT_COMPANY_TIMEZONE,
) {
  const text =
    isoString === undefined || isoString === null ? "" : String(isoString).trim();
  if (!text) return { date: "", time: "" };
  const ms = Date.parse(text);
  if (!Number.isFinite(ms)) {
    const m = text.match(/^(\d{4}-\d{2}-\d{2})[T\s](\d{2}:\d{2})/);
    return m ? { date: m[1], time: m[2] } : { date: "", time: "" };
  }
  const tz = resolveCompanyTimezone(timezone);
  try {
    const d = new Date(ms);
    // sv-SE yields stable YYYY-MM-DD and HH:MM regardless of host locale.
    const date = new Intl.DateTimeFormat("sv-SE", {
      timeZone: tz,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).format(d);
    const time = new Intl.DateTimeFormat("sv-SE", {
      timeZone: tz,
      hour: "2-digit",
      minute: "2-digit",
      hour12: false,
    }).format(d);
    return { date, time };
  } catch (_) {
    return { date: "", time: "" };
  }
}

/** Alias kept for call sites that historically meant Brussels specifically. */
export function brusselsDateTimePartsFromIso(isoString) {
  return companyDateTimePartsFromIso(isoString, DEFAULT_COMPANY_TIMEZONE);
}

/**
 * Today's calendar date in the company timezone as DD/MM/YYYY (nl-BE style).
 * Used for invoice "Factuurdatum" so midnight near UTC does not flip the
 * Belgian local date incorrectly.
 */
export function todayCompanyLocalNl(
  now = new Date(),
  timezone = DEFAULT_COMPANY_TIMEZONE,
) {
  const tz = resolveCompanyTimezone(timezone);
  const d = now instanceof Date ? now : new Date(now);
  try {
    const parts = new Intl.DateTimeFormat("nl-BE", {
      timeZone: tz,
      day: "2-digit",
      month: "2-digit",
      year: "numeric",
    }).formatToParts(d);
    const get = (t) => parts.find((p) => p.type === t)?.value || "";
    return `${get("day")}/${get("month")}/${get("year")}`;
  } catch (_) {
    const pad = (n) => String(n).padStart(2, "0");
    return `${pad(d.getUTCDate())}/${pad(d.getUTCMonth() + 1)}/${d.getUTCFullYear()}`;
  }
}

export function todayNLBrussels(now = new Date()) {
  return todayCompanyLocalNl(now, DEFAULT_COMPANY_TIMEZONE);
}
