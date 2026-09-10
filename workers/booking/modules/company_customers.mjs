// COMPANY-CUSTOMER-OPS-P0A
//
// Tenant-scoped company customer records + packed list pages.
// GET never scans KV prefixes. Overflow fills the next page; it does not
// copy the booking live/pending dual-generation machinery.

import { sanitizeTenantString, safeStr } from "./parsing_utils.js";
import { jsonBase64urlEncode, jsonBase64urlDecode, sha256Hex } from "./crypto_utils.js";
import { json } from "./http_response.js";

export const CUSTOMER_LIST_PAGE_SIZE = 200;
export const CUSTOMER_HTTP_LIST_LIMIT = 50;
export const CUSTOMER_GET_MAX_READS = 5;
export const CUSTOMER_GET_MAX_LISTS = 0;
export const CUSTOMER_GET_MAX_WRITES = 0;
export const CUSTOMER_MUTATE_MAX_READS = 40;
export const CUSTOMER_MUTATE_MAX_WRITES = 40;
export const CUSTOMER_MUTATE_MAX_DELETES = 8;
export const CUSTOMER_SEARCH_PAGE_READS = 3;

const ADDRESS_TYPES = new Set(["home", "work", "pickup", "billing", "other"]);
const LIST_VIEWS = ["active", "archived", "all"];
const PREFERENCE_KEYS = new Set(["version", "preferred_locale"]);

export function matchCompanyCustomersPath(pathname) {
  const path = String(pathname || "");
  const m = path.match(/^\/company\/customers(?:\/([^/]+))?(?:\/(archive|restore))?$/);
  if (!m) return null;
  return {
    customerId: safeStr(m[1] || ""),
    action: safeStr(m[2] || ""),
  };
}

export function normalizeCustomerScope(scope) {
  const tenant = sanitizeTenantString(scope?.tenant_id ?? scope?.tenantId, 80);
  const company = sanitizeTenantString(scope?.company_id ?? scope?.companyId, 80);
  return {
    tenant_id: tenant,
    company_id: company,
    hasScope: !!(tenant && company),
  };
}

export function companyCustomerRecordKey(scope, customerId) {
  const s = normalizeCustomerScope(scope);
  const id = safeStr(customerId);
  if (!s.hasScope || !id) return "";
  return `tenant:${s.tenant_id}:company:${s.company_id}:customer:v1:${id}`;
}

export function companyCustomerListMarkerKey(scope) {
  const s = normalizeCustomerScope(scope);
  if (!s.hasScope) return "";
  return `tenant:${s.tenant_id}:company:${s.company_id}:customers:list:v1:marker`;
}

export function companyCustomerListPageKey(scope, generation, view, pageId) {
  const s = normalizeCustomerScope(scope);
  const g = String(generation || "");
  const v = safeStr(view);
  const p = safeStr(pageId);
  if (!s.hasScope || !g || !v || !p) return "";
  return `tenant:${s.tenant_id}:company:${s.company_id}:customers:list:v1:g:${g}:${v}:p:${p}`;
}

export function companyCustomerLocatorKey(scope, generation, customerId) {
  const s = normalizeCustomerScope(scope);
  const g = String(generation || "");
  const id = safeStr(customerId);
  if (!s.hasScope || !g || !id) return "";
  return `tenant:${s.tenant_id}:company:${s.company_id}:customers:list:v1:g:${g}:loc:${id}`;
}

export function companyCustomerEmailIndexKey(scope, normalizedEmail) {
  const s = normalizeCustomerScope(scope);
  const email = normalizeCustomerEmail(normalizedEmail);
  if (!s.hasScope || !email) return "";
  return `tenant:${s.tenant_id}:company:${s.company_id}:customers:by_email:v1:${email}`;
}

export function companyCustomerPhoneIndexKey(scope, normalizedPhone) {
  const s = normalizeCustomerScope(scope);
  const phone = indexPhoneKey(normalizedPhone);
  if (!s.hasScope || !phone) return "";
  return `tenant:${s.tenant_id}:company:${s.company_id}:customers:by_phone:v1:${phone}`;
}

export function companyCustomerIdempotencyKey(scope, idempotencyKey) {
  const s = normalizeCustomerScope(scope);
  const raw = safeStr(idempotencyKey);
  if (!s.hasScope || !raw) return "";
  return `tenant:${s.tenant_id}:company:${s.company_id}:customers:idem:v1:${raw}`;
}

export function normalizeCustomerEmail(value) {
  return sanitizeTenantString(value, 320).toLowerCase();
}

export function normalizeCustomerPhone(value, countryCallingCode) {
  const raw = sanitizeTenantString(value, 80);
  if (!raw) {
    return { raw: "", normalized: "", e164: "", country_calling_code: "" };
  }
  const cc = String(countryCallingCode || "").replace(/[^0-9]/g, "").slice(0, 4);
  const keepPlus = raw.startsWith("+");
  const digits = raw.replace(/[^0-9]/g, "");
  if (!digits) {
    return { raw, normalized: "", e164: "", country_calling_code: cc };
  }
  let e164 = "";
  if (keepPlus && digits.length >= 8 && digits.length <= 15) {
    e164 = `+${digits}`;
  } else if (cc && digits.length >= 4 && digits.length <= 15) {
    const national = digits.startsWith(cc) ? digits.slice(cc.length) : digits;
    const combined = `${cc}${national}`;
    if (combined.length >= 8 && combined.length <= 15) e164 = `+${combined}`;
  }
  const normalized = e164 || (keepPlus ? `+${digits}` : digits);
  return { raw, normalized, e164, country_calling_code: cc };
}

function indexPhoneKey(value) {
  const digits = String(value || "").replace(/[^0-9]/g, "");
  return digits.length >= 8 && digits.length <= 15 ? digits : "";
}

export function isUsableCustomerEmail(value) {
  const email = normalizeCustomerEmail(value);
  if (!email || email.length > 320) return false;
  const at = email.indexOf("@");
  if (at <= 0 || at !== email.lastIndexOf("@")) return false;
  const local = email.slice(0, at);
  const domain = email.slice(at + 1);
  if (!local || !domain) return false;
  if (domain.startsWith(".") || domain.endsWith(".")) return false;
  if (!domain.includes(".")) return false;
  if (/\s/.test(email)) return false;
  return true;
}

export function isUsableCustomerPhone(normalized) {
  const digits = String(normalized || "").replace(/[^0-9]/g, "");
  return digits.length >= 8 && digits.length <= 15;
}

export function maskCustomerEmail(email) {
  const value = normalizeCustomerEmail(email);
  const at = value.indexOf("@");
  if (at <= 0) return "";
  const domain = value.slice(at);
  return `*${domain}`;
}

export function maskCustomerPhone(phone) {
  const digits = String(phone || "").replace(/[^0-9]/g, "");
  if (digits.length < 2) return "";
  return `***${digits.slice(-2)}`;
}

function clip(value, max) {
  return sanitizeTenantString(value, max);
}

function nowParts(env) {
  const forced = Number(env?.CUSTOMER_NOW_MS);
  const date = Number.isFinite(forced) && forced > 0 ? new Date(forced) : new Date();
  return { ms: date.getTime(), iso: date.toISOString() };
}

function emptyView() {
  return {
    first_page_id: "",
    last_page_id: "",
    next_page_seq: 1,
    page_count: 0,
    row_count: 0,
  };
}

function emptyMarker() {
  return {
    version: 1,
    generation: 1,
    views: {
      active: emptyView(),
      archived: emptyView(),
      all: emptyView(),
    },
  };
}

function compareCustomerRows(a, b) {
  const am = Number(a?.sort_ms || 0);
  const bm = Number(b?.sort_ms || 0);
  if (am !== bm) return bm - am;
  return String(b?.customer_id || "").localeCompare(String(a?.customer_id || ""));
}

function afterCursorPassed(row, after) {
  if (!after?.customer_id) return true;
  const probe = { sort_ms: Number(after.sort_ms || 0), customer_id: String(after.customer_id) };
  return compareCustomerRows(row, probe) > 0;
}

function newCustomerId() {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  let hex = "";
  for (const byte of bytes) hex += byte.toString(16).padStart(2, "0");
  return `cus_${hex}`;
}

function newAddressId() {
  const bytes = new Uint8Array(8);
  crypto.getRandomValues(bytes);
  let hex = "";
  for (const byte of bytes) hex += byte.toString(16).padStart(2, "0");
  return `adr_${hex}`;
}

function audit(event, extra = {}) {
  console.log(
    `[COMPANY_CUSTOMERS] ${event} reason=${safeStr(extra.reason || "")} auth_mode=${safeStr(extra.auth_mode || "")} status=${safeStr(extra.status || "")} id_len=${Number(extra.id_len || 0)}`,
  );
}

async function kvGetJson(kv, key) {
  if (!key) return null;
  const raw = await kv.get(key, "json");
  return raw && typeof raw === "object" ? raw : null;
}

async function kvPutJson(kv, key, value) {
  if (!key) return;
  await kv.put(key, JSON.stringify(value));
}

function publicCustomer(record) {
  return {
    customer_id: record.customer_id,
    tenant_id: record.tenant_id,
    company_id: record.company_id,
    display_name: record.display_name,
    first_name: record.first_name || "",
    last_name: record.last_name || "",
    phone: record.phone || "",
    phone_normalized: record.phone_normalized || "",
    country_calling_code: record.country_calling_code || "",
    email: record.email || "",
    locale: record.locale || "",
    company_name: record.company_name || "",
    vat_number: record.vat_number || "",
    addresses: Array.isArray(record.addresses) ? record.addresses : [],
    internal_notes: record.internal_notes || "",
    preferences: record.preferences && typeof record.preferences === "object" ? record.preferences : { version: 1 },
    source: record.source,
    status: record.status,
    created_at: record.created_at,
    updated_at: record.updated_at,
    archived_at: record.archived_at || null,
    revision: record.revision,
  };
}

function publicListRow(row) {
  return {
    customer_id: row.customer_id,
    display_name: row.display_name || "",
    company_name: row.company_name || "",
    phone_masked: row.phone_masked || "",
    email_masked: row.email_masked || "",
    status: row.status,
    updated_at: row.updated_at,
  };
}

function searchBlob(record) {
  const phoneDigits = String(record.phone_normalized || "").replace(/[^0-9]/g, "");
  return [
    record.display_name,
    record.first_name,
    record.last_name,
    record.company_name,
    record.email,
    phoneDigits,
    record.vat_number,
  ]
    .map((part) => String(part || "").toLowerCase())
    .filter(Boolean)
    .join(" ");
}

function toListRow(record) {
  return {
    customer_id: record.customer_id,
    display_name: record.display_name,
    company_name: record.company_name || "",
    phone_masked: maskCustomerPhone(record.phone_normalized || record.phone),
    email_masked: maskCustomerEmail(record.email),
    status: record.status,
    updated_at: record.updated_at,
    sort_ms: Date.parse(record.updated_at) || 0,
    search_blob: searchBlob(record),
  };
}

function normalizeAddresses(raw) {
  if (raw == null) return [];
  if (!Array.isArray(raw)) {
    return { error: "invalid" };
  }
  if (raw.length > 8) return { error: "too_many" };
  const out = [];
  for (const item of raw) {
    if (!item || typeof item !== "object") return { error: "invalid" };
    const type = safeStr(item.type || "other").toLowerCase();
    if (!ADDRESS_TYPES.has(type)) return { error: "invalid_type" };
    const addressId = clip(item.address_id, 40) || newAddressId();
    out.push({
      address_id: addressId,
      type,
      label: clip(item.label, 80),
      line1: clip(item.line1, 160),
      line2: clip(item.line2, 160),
      city: clip(item.city, 80),
      postal_code: clip(item.postal_code, 20),
      country_code: clip(item.country_code, 2).toUpperCase(),
      notes: clip(item.notes, 160),
    });
  }
  return out;
}

function normalizePreferences(raw) {
  if (raw == null || raw === "") return { version: 1 };
  if (typeof raw !== "object" || Array.isArray(raw)) return { error: "invalid" };
  const out = { version: 1 };
  for (const [key, value] of Object.entries(raw)) {
    if (!PREFERENCE_KEYS.has(key)) return { error: "unsupported" };
    if (key === "version") {
      const n = Number(value);
      if (!Number.isInteger(n) || n < 1 || n > 100) return { error: "invalid" };
      out.version = n;
      continue;
    }
    if (key === "preferred_locale") {
      out.preferred_locale = clip(value, 16);
    }
  }
  return out;
}

export function composeCustomerDisplayName(body) {
  const display = clip(body?.display_name, 120);
  if (display) return display;
  return `${clip(body?.first_name, 80)} ${clip(body?.last_name, 80)}`.trim();
}

export function validateCustomerWrite(body, { partial = false } = {}) {
  const fields = {};
  const value = {};
  const source = clip(body?.source, 16).toLowerCase();
  if (source && source !== "manual") fields.source = "manual_only";

  const nameTouched =
    !partial || body?.display_name != null || body?.first_name != null || body?.last_name != null;
  const displayName = composeCustomerDisplayName(body);
  if (nameTouched) {
    if (!displayName) fields.display_name = "required";
    else {
      value.display_name = displayName;
      if (body?.first_name != null) value.first_name = clip(body.first_name, 80);
      if (body?.last_name != null) value.last_name = clip(body.last_name, 80);
      if (!partial) {
        value.first_name = clip(body?.first_name, 80);
        value.last_name = clip(body?.last_name, 80);
      }
    }
  }

  let phone = { raw: "", normalized: "", e164: "", country_calling_code: "" };
  if (!partial || body?.email != null) {
    const rawEmail = body?.email == null ? "" : body.email;
    if (rawEmail) {
      if (!isUsableCustomerEmail(rawEmail)) fields.email = "invalid";
      else value.email = normalizeCustomerEmail(rawEmail);
    } else {
      value.email = "";
    }
  }
  if (!partial || body?.phone != null || body?.country_calling_code != null) {
    phone = normalizeCustomerPhone(body?.phone, body?.country_calling_code);
    if (clip(body?.phone, 80) && !isUsableCustomerPhone(phone.normalized)) {
      fields.phone = "invalid";
    } else {
      value.phone = phone.raw;
      value.phone_normalized = phone.normalized;
      value.country_calling_code = phone.country_calling_code;
    }
  }
  if (!partial) {
    const hasEmail = isUsableCustomerEmail(body?.email);
    const hasPhone = isUsableCustomerPhone(phone.normalized);
    if (!hasEmail && !hasPhone) fields.contact = "required";
  }
  if (body?.locale != null) {
    if (String(body.locale).trim().length > 16) fields.locale = "too_long";
    else value.locale = clip(body.locale, 16);
  } else if (!partial) {
    value.locale = "";
  }
  if (body?.company_name != null || !partial) value.company_name = clip(body?.company_name, 160);
  if (body?.vat_number != null || !partial) value.vat_number = clip(body?.vat_number, 40);
  if (body?.internal_notes != null) {
    if (String(body.internal_notes).length > 2000) fields.internal_notes = "too_long";
    else value.internal_notes = clip(body.internal_notes, 2000);
  } else if (!partial) {
    value.internal_notes = "";
  }
  if (body?.addresses !== undefined) {
    const addresses = normalizeAddresses(body.addresses);
    if (addresses.error) fields.addresses = addresses.error;
    else value.addresses = addresses;
  } else if (!partial) {
    value.addresses = [];
  }
  if (body?.preferences !== undefined) {
    const preferences = normalizePreferences(body.preferences);
    if (preferences.error) fields.preferences = preferences.error;
    else value.preferences = preferences;
  } else if (!partial) {
    value.preferences = { version: 1 };
  }
  if (Object.keys(fields).length) return { ok: false, fields };
  return { ok: true, value };
}

async function loadMarker(kv, scope) {
  const key = companyCustomerListMarkerKey(scope);
  const existing = await kvGetJson(kv, key);
  if (existing?.version === 1 && existing.views) return existing;
  return emptyMarker();
}

async function loadPage(kv, scope, marker, view, pageId) {
  if (!pageId) return null;
  return kvGetJson(kv, companyCustomerListPageKey(scope, marker.generation, view, pageId));
}

async function saveMarker(kv, scope, marker) {
  await kvPutJson(kv, companyCustomerListMarkerKey(scope), marker);
}

function allocPageId(viewState) {
  const id = String(viewState.next_page_seq++);
  return id;
}

async function writePage(kv, scope, marker, view, page) {
  await kvPutJson(kv, companyCustomerListPageKey(scope, marker.generation, view, page.page_id), page);
}

async function deletePage(kv, scope, marker, view, pageId) {
  const key = companyCustomerListPageKey(scope, marker.generation, view, pageId);
  if (key) await kv.delete(key);
}

async function loadLocator(kv, scope, marker, customerId) {
  return kvGetJson(kv, companyCustomerLocatorKey(scope, marker.generation, customerId));
}

async function saveLocator(kv, scope, marker, customerId, locator) {
  await kvPutJson(kv, companyCustomerLocatorKey(scope, marker.generation, customerId), locator);
}

async function deleteLocator(kv, scope, marker, customerId) {
  const key = companyCustomerLocatorKey(scope, marker.generation, customerId);
  if (key) await kv.delete(key);
}

function recountView(viewState, deltaPages, deltaRows) {
  viewState.page_count = Math.max(0, Number(viewState.page_count || 0) + deltaPages);
  viewState.row_count = Math.max(0, Number(viewState.row_count || 0) + deltaRows);
}

async function spillOlderRows(kv, scope, marker, view, viewState, fromPage, overflow) {
  let remaining = [...overflow];
  let current = fromPage;
  while (remaining.length) {
    if (current.next_page_id) {
      const next = await loadPage(kv, scope, marker, view, current.next_page_id);
      if (!next) break;
      next.rows = [...remaining, ...(Array.isArray(next.rows) ? next.rows : [])];
      next.rows.sort(compareCustomerRows);
      if (next.rows.length <= CUSTOMER_LIST_PAGE_SIZE) {
        remaining = [];
        await writePage(kv, scope, marker, view, next);
        break;
      }
      remaining = next.rows.splice(CUSTOMER_LIST_PAGE_SIZE);
      await writePage(kv, scope, marker, view, next);
      current = next;
      continue;
    }
    const chunk = remaining.slice(0, CUSTOMER_LIST_PAGE_SIZE);
    remaining = remaining.slice(CUSTOMER_LIST_PAGE_SIZE);
    const pageId = allocPageId(viewState);
    const newPage = {
      version: 1,
      view,
      page_id: pageId,
      prev_page_id: current.page_id,
      next_page_id: "",
      rows: chunk,
    };
    current.next_page_id = pageId;
    await writePage(kv, scope, marker, view, current);
    await writePage(kv, scope, marker, view, newPage);
    viewState.last_page_id = pageId;
    recountView(viewState, 1, 0);
    current = newPage;
  }
}

async function insertRowIntoView(kv, scope, marker, view, row) {
  const viewState = marker.views[view] || emptyView();
  marker.views[view] = viewState;
  let page;
  if (!viewState.first_page_id) {
    const pageId = allocPageId(viewState);
    page = {
      version: 1,
      view,
      page_id: pageId,
      prev_page_id: "",
      next_page_id: "",
      rows: [row],
    };
    viewState.first_page_id = pageId;
    viewState.last_page_id = pageId;
    recountView(viewState, 1, 1);
    await writePage(kv, scope, marker, view, page);
    return pageId;
  }
  page = await loadPage(kv, scope, marker, view, viewState.first_page_id);
  if (!page) {
    const pageId = allocPageId(viewState);
    page = {
      version: 1,
      view,
      page_id: pageId,
      prev_page_id: "",
      next_page_id: "",
      rows: [row],
    };
    viewState.first_page_id = pageId;
    viewState.last_page_id = pageId;
    recountView(viewState, 1, 1);
    await writePage(kv, scope, marker, view, page);
    return pageId;
  }
  page.rows = (Array.isArray(page.rows) ? page.rows : []).filter((existing) => existing.customer_id !== row.customer_id);
  page.rows.push(row);
  page.rows.sort(compareCustomerRows);
  recountView(viewState, 0, 1);
  if (page.rows.length > CUSTOMER_LIST_PAGE_SIZE) {
    const overflow = page.rows.splice(CUSTOMER_LIST_PAGE_SIZE);
    await writePage(kv, scope, marker, view, page);
    await spillOlderRows(kv, scope, marker, view, viewState, page, overflow);
  } else {
    await writePage(kv, scope, marker, view, page);
  }
  return page.page_id;
}

async function removeRowFromExactPage(kv, scope, marker, view, customerId, pageId) {
  const viewState = marker.views[view] || emptyView();
  marker.views[view] = viewState;
  if (!pageId) return { removed: false, page: null };
  const page = await loadPage(kv, scope, marker, view, pageId);
  if (!page) return { removed: false, page: null };
  const before = Array.isArray(page.rows) ? page.rows.length : 0;
  page.rows = (Array.isArray(page.rows) ? page.rows : []).filter((row) => row.customer_id !== customerId);
  if (page.rows.length === before) return { removed: false, page };
  recountView(viewState, 0, -1);
  if (page.rows.length === 0) {
    if (page.prev_page_id) {
      const prev = await loadPage(kv, scope, marker, view, page.prev_page_id);
      if (prev) {
        prev.next_page_id = page.next_page_id || "";
        await writePage(kv, scope, marker, view, prev);
      }
    } else {
      viewState.first_page_id = page.next_page_id || "";
    }
    if (page.next_page_id) {
      const next = await loadPage(kv, scope, marker, view, page.next_page_id);
      if (next) {
        next.prev_page_id = page.prev_page_id || "";
        await writePage(kv, scope, marker, view, next);
      }
    } else {
      viewState.last_page_id = page.prev_page_id || "";
    }
    await deletePage(kv, scope, marker, view, page.page_id);
    recountView(viewState, -1, 0);
    return { removed: true, page: null };
  }
  await writePage(kv, scope, marker, view, page);
  return { removed: true, page };
}

async function removeRowFromView(kv, scope, marker, view, customerId, knownPageId) {
  if (knownPageId) {
    const hinted = await removeRowFromExactPage(kv, scope, marker, view, customerId, knownPageId);
    if (hinted.removed) return true;
  }
  let pageId = marker.views[view]?.first_page_id || "";
  let hops = 0;
  while (pageId && hops < 8) {
    hops += 1;
    const result = await removeRowFromExactPage(kv, scope, marker, view, customerId, pageId);
    if (result.removed) return true;
    pageId = result.page?.next_page_id || "";
  }
  return false;
}

async function replaceCustomerInViews(kv, scope, record, previous) {
  const marker = await loadMarker(kv, scope);
  const locator = (await loadLocator(kv, scope, marker, record.customer_id)) || { views: {} };
  const row = toListRow(record);
  const prevStatus = previous?.status || "";
  if (previous) {
    if (prevStatus === "active" || prevStatus === "archived") {
      await removeRowFromView(kv, scope, marker, prevStatus, record.customer_id, locator.views?.[prevStatus]);
    }
    await removeRowFromView(kv, scope, marker, "all", record.customer_id, locator.views?.all);
  }
  const nextLocator = { views: {} };
  nextLocator.views[record.status] = await insertRowIntoView(kv, scope, marker, record.status, row);
  nextLocator.views.all = await insertRowIntoView(kv, scope, marker, "all", row);
  await saveLocator(kv, scope, marker, record.customer_id, nextLocator);
  await saveMarker(kv, scope, marker);
  return marker;
}

async function readIndexIds(kv, key) {
  const rec = await kvGetJson(kv, key);
  const ids = Array.isArray(rec?.customer_ids) ? rec.customer_ids.map((id) => safeStr(id)).filter(Boolean) : [];
  return { rec: rec || { customer_ids: [] }, ids };
}

async function writeIndexIds(kv, key, ids) {
  const unique = [...new Set(ids.filter(Boolean))];
  if (!unique.length) {
    if (key) await kv.delete(key);
    return;
  }
  await kvPutJson(kv, key, { customer_ids: unique });
}

async function collectDuplicateWarnings(kv, scope, { email, phone, customerId }) {
  const matches = [];
  if (email) {
    const key = companyCustomerEmailIndexKey(scope, email);
    const { ids } = await readIndexIds(kv, key);
    for (const id of ids) {
      if (id && id !== customerId) matches.push({ customer_id: id, field: "email" });
    }
  }
  if (phone) {
    const key = companyCustomerPhoneIndexKey(scope, phone);
    const { ids } = await readIndexIds(kv, key);
    for (const id of ids) {
      if (id && id !== customerId) matches.push({ customer_id: id, field: "phone" });
    }
  }
  return matches;
}

async function updateContactIndexes(kv, scope, record, previous) {
  const prevEmail = previous?.email ? normalizeCustomerEmail(previous.email) : "";
  const nextEmail = record.email ? normalizeCustomerEmail(record.email) : "";
  if (prevEmail && prevEmail !== nextEmail) {
    const key = companyCustomerEmailIndexKey(scope, prevEmail);
    const { ids } = await readIndexIds(kv, key);
    await writeIndexIds(kv, key, ids.filter((id) => id !== record.customer_id));
  }
  if (nextEmail) {
    const key = companyCustomerEmailIndexKey(scope, nextEmail);
    const { ids } = await readIndexIds(kv, key);
    if (!ids.includes(record.customer_id)) ids.push(record.customer_id);
    await writeIndexIds(kv, key, ids);
  }
  const prevPhone = indexPhoneKey(previous?.phone_normalized || previous?.phone);
  const nextPhone = indexPhoneKey(record.phone_normalized || record.phone);
  if (prevPhone && prevPhone !== nextPhone) {
    const key = companyCustomerPhoneIndexKey(scope, prevPhone);
    const { ids } = await readIndexIds(kv, key);
    await writeIndexIds(kv, key, ids.filter((id) => id !== record.customer_id));
  }
  if (nextPhone) {
    const key = companyCustomerPhoneIndexKey(scope, nextPhone);
    const { ids } = await readIndexIds(kv, key);
    if (!ids.includes(record.customer_id)) ids.push(record.customer_id);
    await writeIndexIds(kv, key, ids);
  }
}

async function hashIdempotency(scope, op, rawKey) {
  const s = normalizeCustomerScope(scope);
  const material = `${s.tenant_id}|${s.company_id}|${op}|${safeStr(rawKey)}`;
  return sha256Hex(material);
}

async function loadIdempotency(kv, scope, hashed) {
  return kvGetJson(kv, companyCustomerIdempotencyKey(scope, hashed));
}

async function saveIdempotency(kv, scope, hashed, payload) {
  await kvPutJson(kv, companyCustomerIdempotencyKey(scope, hashed), payload);
}

function encodeCursor(payload) {
  return jsonBase64urlEncode(payload);
}

function decodeCursor(raw, scope, view, q) {
  const text = safeStr(raw);
  if (!text) return { ok: true, cursor: null };
  try {
    const parsed = jsonBase64urlDecode(text);
    const s = normalizeCustomerScope(scope);
    if (!parsed || typeof parsed !== "object") return { ok: false };
    if (parsed.v !== 1) return { ok: false };
    if (parsed.t !== s.tenant_id || parsed.c !== s.company_id) return { ok: false };
    if (parsed.view !== view) return { ok: false };
    if (String(parsed.q || "") !== String(q || "")) return { ok: false };
    if (!parsed.page_id || !parsed.after?.customer_id) return { ok: false };
    return { ok: true, cursor: parsed };
  } catch {
    return { ok: false };
  }
}

function matchesQuery(row, q) {
  const query = safeStr(q).toLowerCase();
  if (!query) return true;
  const tokens = query.split(/\s+/).filter(Boolean).slice(0, 6);
  const blob = String(row.search_blob || "");
  return tokens.every((token) => blob.includes(token));
}

export async function listCompanyCustomers(env, { scope, status = "active", q = "", cursor = "", limit = CUSTOMER_HTTP_LIST_LIMIT } = {}) {
  const s = normalizeCustomerScope(scope);
  if (!s.hasScope) return { ok: false, status: 400, error: "missing_tenant_scope" };
  const view = ["active", "archived", "all"].includes(status) ? status : "";
  if (!view) return { ok: false, status: 400, error: "invalid_status_filter" };
  const pageLimit = Math.min(CUSTOMER_HTTP_LIST_LIMIT, Math.max(1, Number(limit) || CUSTOMER_HTTP_LIST_LIMIT));
  const query = clip(q, 80);
  const decoded = decodeCursor(cursor, s, view, query);
  if (!decoded.ok) return { ok: false, status: 400, error: "invalid_cursor" };
  const kv = env.BOOKING_KV;
  const marker = await loadMarker(kv, s);
  if (decoded.cursor && Number(decoded.cursor.g) !== Number(marker.generation)) {
    return { ok: false, status: 400, error: "invalid_cursor" };
  }
  const items = [];
  let pageId = decoded.cursor?.page_id || marker.views[view]?.first_page_id || "";
  let after = decoded.cursor?.after || null;
  let reads = 0;
  let lastEmitted = null;
  let lastPageId = "";
  let lastScanned = null;
  let lastScannedPageId = "";
  let moreKnown = false;
  const maxPages = query ? CUSTOMER_SEARCH_PAGE_READS : 2;
  while (pageId && reads < maxPages && items.length < pageLimit) {
    const page = await loadPage(kv, s, marker, view, pageId);
    reads += 1;
    if (!page) break;
    const rows = Array.isArray(page.rows) ? page.rows : [];
    for (let i = 0; i < rows.length; i += 1) {
      const row = rows[i];
      if (!afterCursorPassed(row, after)) continue;
      lastScanned = row;
      lastScannedPageId = page.page_id;
      if (!matchesQuery(row, query)) continue;
      items.push(publicListRow(row));
      lastEmitted = row;
      lastPageId = page.page_id;
      if (items.length >= pageLimit) {
        moreKnown = i < rows.length - 1 || !!page.next_page_id;
        break;
      }
    }
    if (items.length >= pageLimit) break;
    pageId = page.next_page_id || "";
    after = null;
    moreKnown = !!pageId;
  }
  if (items.length < pageLimit && pageId && reads >= maxPages) moreKnown = true;
  const cursorRow = lastEmitted || lastScanned;
  const cursorPage = lastEmitted ? lastPageId : lastScannedPageId;
  const hasMore = !!moreKnown && !!cursorRow;
  const nextCursor = hasMore
    ? encodeCursor({
        v: 1,
        t: s.tenant_id,
        c: s.company_id,
        g: marker.generation,
        view,
        q: query,
        page_id: cursorPage,
        after: { sort_ms: cursorRow.sort_ms, customer_id: cursorRow.customer_id },
      })
    : null;
  const body = {
    ok: true,
    items,
    count: items.length,
    has_more: !!hasMore,
    next_cursor: nextCursor,
  };
  if (!query) body.total_count = Number(marker.views[view]?.row_count || 0);
  return { ok: true, status: 200, body };
}

export async function getCompanyCustomer(env, { scope, customerId }) {
  const s = normalizeCustomerScope(scope);
  const id = safeStr(customerId);
  if (!s.hasScope) return { ok: false, status: 400, error: "missing_tenant_scope" };
  if (!id) return { ok: false, status: 404, error: "not_found" };
  const record = await kvGetJson(env.BOOKING_KV, companyCustomerRecordKey(s, id));
  if (!record?.customer_id) return { ok: false, status: 404, error: "not_found" };
  return { ok: true, status: 200, body: { ok: true, customer: publicCustomer(record) } };
}

export async function createCompanyCustomer(env, { scope, body, idempotencyKey }) {
  const s = normalizeCustomerScope(scope);
  if (!s.hasScope) return { ok: false, status: 400, error: "missing_tenant_scope" };
  const kv = env.BOOKING_KV;
  const rawIdem = clip(idempotencyKey, 120);
  let hashed = "";
  if (rawIdem) {
    hashed = await hashIdempotency(s, "create", rawIdem);
    const existing = await loadIdempotency(kv, s, hashed);
    if (existing?.customer_id) {
      const record = await kvGetJson(kv, companyCustomerRecordKey(s, existing.customer_id));
      if (record?.customer_id) {
        return {
          ok: true,
          status: 200,
          body: { ok: true, customer: publicCustomer(record), idempotent: true },
        };
      }
    }
  }
  const validated = validateCustomerWrite(body || {}, { partial: false });
  if (!validated.ok) {
    return { ok: false, status: 400, error: "invalid_customer", fields: validated.fields };
  }
  const clock = nowParts(env);
  const customerId = newCustomerId();
  const record = {
    customer_id: customerId,
    tenant_id: s.tenant_id,
    company_id: s.company_id,
    ...validated.value,
    addresses: validated.value.addresses || [],
    preferences: validated.value.preferences || { version: 1 },
    source: "manual",
    status: "active",
    created_at: clock.iso,
    updated_at: clock.iso,
    archived_at: null,
    revision: 1,
  };
  const matches = await collectDuplicateWarnings(kv, s, {
    email: record.email,
    phone: record.phone_normalized,
    customerId,
  });
  await kvPutJson(kv, companyCustomerRecordKey(s, customerId), record);
  await updateContactIndexes(kv, s, record, null);
  await replaceCustomerInViews(kv, s, record, null);
  if (hashed) {
    await saveIdempotency(kv, s, hashed, { op: "create", customer_id: customerId });
  }
  audit("create", { reason: "manual", status: "active", id_len: customerId.length });
  const response = { ok: true, customer: publicCustomer(record) };
  if (matches.length) response.duplicate_warning = { matches };
  return { ok: true, status: 201, body: response };
}

export async function updateCompanyCustomer(env, { scope, customerId, body }) {
  const s = normalizeCustomerScope(scope);
  const id = safeStr(customerId);
  if (!s.hasScope) return { ok: false, status: 400, error: "missing_tenant_scope" };
  if (!id) return { ok: false, status: 404, error: "not_found" };
  const kv = env.BOOKING_KV;
  const current = await kvGetJson(kv, companyCustomerRecordKey(s, id));
  if (!current?.customer_id) return { ok: false, status: 404, error: "not_found" };
  const incomingRevision = Number(body?.revision);
  if (!Number.isInteger(incomingRevision)) {
    return { ok: false, status: 400, error: "invalid_customer", fields: { revision: "required" } };
  }
  if (incomingRevision !== Number(current.revision)) {
    return { ok: false, status: 409, error: "revision_conflict", revision: current.revision };
  }
  if (body?.source != null && clip(body.source, 16).toLowerCase() && clip(body.source, 16).toLowerCase() !== "manual") {
    return { ok: false, status: 400, error: "invalid_customer", fields: { source: "manual_only" } };
  }
  const validated = validateCustomerWrite(body || {}, { partial: true });
  if (!validated.ok) {
    return { ok: false, status: 400, error: "invalid_customer", fields: validated.fields };
  }
  const next = { ...current };
  const patch = validated.value;
  for (const [key, value] of Object.entries(patch)) {
    if (value !== undefined) next[key] = value;
  }
  if (body?.display_name != null || body?.first_name != null || body?.last_name != null) {
    next.display_name = composeCustomerDisplayName({ ...current, ...body, display_name: body.display_name ?? next.display_name });
  }
  if (body?.email != null) next.email = patch.email;
  if (body?.phone != null || body?.country_calling_code != null) {
    next.phone = patch.phone;
    next.phone_normalized = patch.phone_normalized;
    next.country_calling_code = patch.country_calling_code;
  }
  if (body?.addresses !== undefined) next.addresses = patch.addresses || [];
  if (body?.preferences !== undefined) next.preferences = patch.preferences || { version: 1 };
  const hasEmail = isUsableCustomerEmail(next.email);
  const hasPhone = isUsableCustomerPhone(next.phone_normalized);
  if (!next.display_name) {
    return { ok: false, status: 400, error: "invalid_customer", fields: { display_name: "required" } };
  }
  if (!hasEmail && !hasPhone) {
    return { ok: false, status: 400, error: "invalid_customer", fields: { contact: "required" } };
  }
  const clock = nowParts(env);
  next.updated_at = clock.iso;
  next.revision = Number(current.revision) + 1;
  next.tenant_id = s.tenant_id;
  next.company_id = s.company_id;
  next.customer_id = current.customer_id;
  next.source = current.source || "manual";
  await kvPutJson(kv, companyCustomerRecordKey(s, id), next);
  await updateContactIndexes(kv, s, next, current);
  await replaceCustomerInViews(kv, s, next, current);
  audit("update", { reason: "patch", status: next.status, id_len: id.length });
  return { ok: true, status: 200, body: { ok: true, customer: publicCustomer(next) } };
}

async function setCustomerStatus(env, { scope, customerId, status, idempotencyKey, op }) {
  const s = normalizeCustomerScope(scope);
  const id = safeStr(customerId);
  if (!s.hasScope) return { ok: false, status: 400, error: "missing_tenant_scope" };
  if (!id) return { ok: false, status: 404, error: "not_found" };
  const kv = env.BOOKING_KV;
  const rawIdem = clip(idempotencyKey, 120);
  let hashed = "";
  if (rawIdem) {
    hashed = await hashIdempotency(s, op, rawIdem);
    const existing = await loadIdempotency(kv, s, hashed);
    if (existing?.customer_id) {
      const record = await kvGetJson(kv, companyCustomerRecordKey(s, existing.customer_id));
      if (record?.customer_id) {
        return { ok: true, status: 200, body: { ok: true, customer: publicCustomer(record), idempotent: true } };
      }
    }
  }
  const current = await kvGetJson(kv, companyCustomerRecordKey(s, id));
  if (!current?.customer_id) return { ok: false, status: 404, error: "not_found" };
  if (current.status === status) {
    if (hashed) await saveIdempotency(kv, s, hashed, { op, customer_id: id });
    return { ok: true, status: 200, body: { ok: true, customer: publicCustomer(current), idempotent: true } };
  }
  const clock = nowParts(env);
  const next = {
    ...current,
    status,
    archived_at: status === "archived" ? clock.iso : null,
    updated_at: clock.iso,
    revision: Number(current.revision || 1) + 1,
  };
  await kvPutJson(kv, companyCustomerRecordKey(s, id), next);
  await replaceCustomerInViews(kv, s, next, current);
  if (hashed) await saveIdempotency(kv, s, hashed, { op, customer_id: id });
  audit(op, { reason: status, status, id_len: id.length });
  return { ok: true, status: 200, body: { ok: true, customer: publicCustomer(next) } };
}

export async function archiveCompanyCustomer(env, args) {
  return setCustomerStatus(env, { ...args, status: "archived", op: "archive" });
}

export async function restoreCompanyCustomer(env, args) {
  return setCustomerStatus(env, { ...args, status: "active", op: "restore" });
}

function errorBody(result) {
  const body = { ok: false, error: result.error || "invalid_customer" };
  if (result.fields) body.fields = result.fields;
  if (result.revision != null) body.revision = result.revision;
  return body;
}

function readIdempotencyKey(request, body) {
  const header = safeStr(request?.headers?.get?.("Idempotency-Key") || request?.headers?.get?.("idempotency-key"));
  if (header) return header;
  return clip(body?.idempotency_key, 120);
}

export async function serveCompanyCustomersHttp({
  env,
  method,
  customerId,
  action,
  url,
  body,
  request,
  scope,
}) {
  const statusFilter = safeStr(url.searchParams.get("status") || "active").toLowerCase();
  const q = url.searchParams.get("q") || "";
  const cursor = url.searchParams.get("cursor") || url.searchParams.get("next_cursor") || "";
  const limit = Number(url.searchParams.get("limit") || CUSTOMER_HTTP_LIST_LIMIT);
  const idem = readIdempotencyKey(request, body);

  if (!customerId && method === "GET") {
    const result = await listCompanyCustomers(env, { scope, status: statusFilter, q, cursor, limit });
    if (!result.ok) return json(errorBody(result), result.status);
    return json(result.body, 200);
  }
  if (!customerId && method === "POST") {
    const result = await createCompanyCustomer(env, { scope, body: body || {}, idempotencyKey: idem });
    if (!result.ok) return json(errorBody(result), result.status);
    return json(result.body, result.status);
  }
  if (customerId && !action && method === "GET") {
    const result = await getCompanyCustomer(env, { scope, customerId });
    if (!result.ok) return json(errorBody(result), result.status);
    return json(result.body, 200);
  }
  if (customerId && !action && method === "PATCH") {
    const result = await updateCompanyCustomer(env, { scope, customerId, body: body || {} });
    if (!result.ok) return json(errorBody(result), result.status);
    return json(result.body, 200);
  }
  if (customerId && action === "archive" && method === "POST") {
    const result = await archiveCompanyCustomer(env, { scope, customerId, idempotencyKey: idem });
    if (!result.ok) return json(errorBody(result), result.status);
    return json(result.body, 200);
  }
  if (customerId && action === "restore" && method === "POST") {
    const result = await restoreCompanyCustomer(env, { scope, customerId, idempotencyKey: idem });
    if (!result.ok) return json(errorBody(result), result.status);
    return json(result.body, 200);
  }
  return json({ ok: false, error: "method_not_allowed" }, 405);
}

export const COMPANY_CUSTOMER_LIST_VIEWS = LIST_VIEWS;
