// FLUXIDI-INVOICE-RECOVERY-ACCEPTANCE-AND-PRESENTATION-P0-1
import { test } from "node:test";
import assert from "node:assert/strict";

import {
  companyDateTimePartsFromIso,
  brusselsDateTimePartsFromIso,
  todayCompanyLocalNl,
  resolveCompanyTimezone,
  DEFAULT_COMPANY_TIMEZONE,
} from "./brussels_datetime.js";

test("DEFAULT_COMPANY_TIMEZONE is Europe/Brussels", () => {
  assert.equal(DEFAULT_COMPANY_TIMEZONE, "Europe/Brussels");
  assert.equal(resolveCompanyTimezone(null), "Europe/Brussels");
  assert.equal(resolveCompanyTimezone({}), "Europe/Brussels");
  assert.equal(resolveCompanyTimezone({ timezone: "Europe/Paris" }), "Europe/Paris");
});

test("Europe/Brussels summer DST (CEST = UTC+2)", () => {
  // 2026-08-02T10:30:00.000Z → 12:30 local
  const p = companyDateTimePartsFromIso("2026-08-02T10:30:00.000Z");
  assert.equal(p.date, "2026-08-02");
  assert.equal(p.time, "12:30");
});

test("Europe/Brussels winter (CET = UTC+1)", () => {
  // 2026-01-15T10:30:00.000Z → 11:30 local
  const p = companyDateTimePartsFromIso("2026-01-15T10:30:00.000Z");
  assert.equal(p.date, "2026-01-15");
  assert.equal(p.time, "11:30");
});

test("UTC date crossing into next Belgian local date", () => {
  // 2026-08-02T22:30:00.000Z → 2026-08-03 00:30 CEST
  const p = companyDateTimePartsFromIso("2026-08-02T22:30:00.000Z");
  assert.equal(p.date, "2026-08-03");
  assert.equal(p.time, "00:30");
});

test("UTC date crossing into previous Belgian local date (winter)", () => {
  // 2026-01-15T00:30:00.000Z → 2026-01-15 01:30 CET (same calendar day)
  const p = companyDateTimePartsFromIso("2026-01-15T00:30:00.000Z");
  assert.equal(p.date, "2026-01-15");
  assert.equal(p.time, "01:30");
  // Near midnight UTC that is still previous evening in US but next morning BE:
  // 2026-01-14T23:30:00.000Z → 2026-01-15 00:30 CET
  const p2 = companyDateTimePartsFromIso("2026-01-14T23:30:00.000Z");
  assert.equal(p2.date, "2026-01-15");
  assert.equal(p2.time, "00:30");
});

test("never uses getUTC* for customer-visible parts (alias)", () => {
  const p = brusselsDateTimePartsFromIso("2026-08-02T10:30:00.000Z");
  assert.notEqual(p.time, "10:30"); // would be UTC
  assert.equal(p.time, "12:30");
});

test("todayCompanyLocalNl returns DD/MM/YYYY in company TZ", () => {
  const s = todayCompanyLocalNl(new Date("2026-08-02T22:30:00.000Z"));
  // 03/08/2026 in Brussels
  assert.equal(s, "03/08/2026");
});
