// COMPANY-AGENDA-P0 — Nu stamps backend server time and ignores client pickup.

import { safeStr } from "./parsing_utils.js";

export function companyAgendaWhenIsNow(body) {
  if (body == null || typeof body !== "object") return false;
  if (body.when_now === true || body.whenNow === true) return true;
  const flag = String(body.when_now ?? body.whenNow ?? "")
    .trim()
    .toLowerCase();
  if (flag === "true" || flag === "1" || flag === "yes") return true;
  const when = safeStr(body.when, 16).toLowerCase();
  return when === "now";
}

export function companyAgendaPickupIsEpoch(iso) {
  const ms = Date.parse(String(iso || ""));
  return Number.isFinite(ms) && ms < Date.UTC(1970, 0, 2);
}

export function resolveCompanyAgendaPickupIso(body, now = new Date()) {
  if (companyAgendaWhenIsNow(body)) {
    const clock = now instanceof Date ? now : new Date(now);
    const ms = clock.getTime();
    const stamped = Number.isFinite(ms) ? new Date(ms).toISOString() : new Date().toISOString();
    return companyAgendaPickupIsEpoch(stamped) ? new Date().toISOString() : stamped;
  }
  const iso = safeStr(body?.pickup_iso || body?.pickupIso, 80);
  if (!iso || companyAgendaPickupIsEpoch(iso)) return "";
  return Number.isFinite(Date.parse(iso)) ? iso : "";
}
