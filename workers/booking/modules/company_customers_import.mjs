// COMPANY-CUSTOMER-OPS-P0B — bounded sequential customer import.
//
// Workers KV cannot atomically unique concurrent writes. This module only
// promises sequential retry safety per import_id + row_key. The client must
// send batches one after another. Parallel same-key creates can still
// duplicate; that is a KV infrastructure limit, not a process lock.

import { safeStr } from "./parsing_utils.js";
import { sha256Hex } from "./crypto_utils.js";
import { json } from "./http_response.js";
import {
  CUSTOMER_IMPORT_BATCH_MAX,
  CUSTOMER_IMPORT_LOOKUP_MAX,
  CUSTOMER_IMPORT_TTL_SECONDS,
  companyCustomerEmailIndexKey,
  companyCustomerPhoneIndexKey,
  companyCustomerRecordKey,
  createCompanyCustomer,
  maskCustomerEmail,
  maskCustomerPhone,
  normalizeCustomerEmail,
  normalizeCustomerPhone,
  normalizeCustomerScope,
  validateCustomerWrite,
} from "./company_customers.mjs";

export function companyCustomerImportKey(scope, importId) {
  const s = normalizeCustomerScope(scope);
  const id = safeStr(importId);
  if (!s.hasScope || !id) return "";
  return `tenant:${s.tenant_id}:company:${s.company_id}:customers:import:v1:${id}`;
}

export function isValidCompanyCustomerImportId(value) {
  return /^imp_[a-f0-9]{32}$/.test(safeStr(value));
}

export function isValidCompanyCustomerImportRowKey(value) {
  return /^[A-Za-z0-9._:-]{1,80}$/.test(safeStr(value));
}

function importCustomerBody(raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return {};
  return {
    display_name: raw.display_name,
    first_name: raw.first_name,
    last_name: raw.last_name,
    email: raw.email,
    phone: raw.phone,
    country_calling_code: raw.country_calling_code,
    locale: raw.locale,
    company_name: raw.company_name,
    vat_number: raw.vat_number,
    addresses: raw.addresses,
    internal_notes: raw.internal_notes,
    preferences: raw.preferences,
  };
}

export async function importRowContentHash(body) {
  const validated = validateCustomerWrite(body || {}, {
    partial: false,
    allowImportSource: true,
  });
  if (!validated.ok) return { ok: false, fields: validated.fields, hash: "" };
  const hash = await sha256Hex(
    JSON.stringify({
      display_name: validated.value.display_name || "",
      email: validated.value.email || "",
      phone_normalized: validated.value.phone_normalized || "",
      company_name: validated.value.company_name || "",
      source: "import",
    }),
  );
  return { ok: true, hash, fields: {} };
}

function emptyImportMeta(importId, nowIso) {
  const expires = new Date(Date.parse(nowIso) + CUSTOMER_IMPORT_TTL_SECONDS * 1000).toISOString();
  return {
    version: 1,
    import_id: importId,
    created_at: nowIso,
    expires_at: expires,
    added: 0,
    skipped: 0,
    failed: 0,
    processed: 0,
    rows: {},
  };
}

function publicImportMeta(meta) {
  return {
    import_id: meta.import_id,
    created_at: meta.created_at,
    expires_at: meta.expires_at,
    added: Number(meta.added || 0),
    skipped: Number(meta.skipped || 0),
    failed: Number(meta.failed || 0),
    processed: Number(meta.processed || 0),
    rows: meta.rows && typeof meta.rows === "object" ? meta.rows : {},
  };
}

function publicRowOutcome(rowKey, rec, extra = {}) {
  const out = {
    row_key: rowKey,
    outcome: rec.outcome,
    ...extra,
  };
  if (rec.customer_id) out.customer_id = rec.customer_id;
  if (rec.error) out.error = rec.error;
  if (rec.fields) out.fields = rec.fields;
  if (rec.idempotent) out.idempotent = true;
  return out;
}

async function loadImportMeta(kv, scope, importId) {
  const key = companyCustomerImportKey(scope, importId);
  if (!key) return null;
  const raw = await kv.get(key, "json");
  return raw && typeof raw === "object" ? raw : null;
}

async function saveImportMeta(kv, scope, meta) {
  const key = companyCustomerImportKey(scope, meta.import_id);
  if (!key) return;
  await kv.put(key, JSON.stringify(meta), { expirationTtl: CUSTOMER_IMPORT_TTL_SECONDS });
}

function nowIso(env) {
  const forced = Number(env?.CUSTOMER_NOW_MS);
  const date = Number.isFinite(forced) && forced > 0 ? new Date(forced) : new Date();
  return date.toISOString();
}

function auditImport(event, extra = {}) {
  console.log(
    `[COMPANY_CUSTOMERS][IMPORT] ${event} reason=${safeStr(extra.reason || "")} rows=${Number(extra.rows || 0)} added=${Number(extra.added || 0)} skipped=${Number(extra.skipped || 0)} failed=${Number(extra.failed || 0)}`,
  );
}

export async function getCompanyCustomerImport(env, { scope, importId }) {
  const s = normalizeCustomerScope(scope);
  if (!s.hasScope) return { ok: false, status: 400, error: "missing_tenant_scope" };
  if (!isValidCompanyCustomerImportId(importId)) {
    return { ok: false, status: 400, error: "invalid_import_id" };
  }
  const meta = await loadImportMeta(env.BOOKING_KV, s, importId);
  if (!meta?.import_id) return { ok: false, status: 404, error: "import_not_found" };
  return { ok: true, status: 200, body: { ok: true, import: publicImportMeta(meta) } };
}

export async function lookupImportContacts(env, { scope, importId, contacts }) {
  const s = normalizeCustomerScope(scope);
  if (!s.hasScope) return { ok: false, status: 400, error: "missing_tenant_scope" };
  if (!isValidCompanyCustomerImportId(importId)) {
    return { ok: false, status: 400, error: "invalid_import_id" };
  }
  if (!Array.isArray(contacts)) {
    return { ok: false, status: 400, error: "invalid_lookup" };
  }
  if (contacts.length > CUSTOMER_IMPORT_LOOKUP_MAX) {
    return { ok: false, status: 400, error: "lookup_too_large" };
  }
  const kv = env.BOOKING_KV;
  const matches = [];
  for (const item of contacts) {
    if (!item || typeof item !== "object") continue;
    const rowKey = safeStr(item.row_key);
    if (!isValidCompanyCustomerImportRowKey(rowKey)) continue;
    const seen = new Set();
    const email = normalizeCustomerEmail(item.email);
    if (email) {
      const rec = await kv.get(companyCustomerEmailIndexKey(s, email), "json");
      const ids = Array.isArray(rec?.customer_ids) ? rec.customer_ids : [];
      for (const id of ids.slice(0, 5)) {
        const customerId = safeStr(id);
        if (!customerId || seen.has(`email:${customerId}`)) continue;
        seen.add(`email:${customerId}`);
        const record = await kv.get(companyCustomerRecordKey(s, customerId), "json");
        if (!record?.customer_id) continue;
        matches.push({
          row_key: rowKey,
          customer_id: record.customer_id,
          field: "email",
          display_name: safeStr(record.display_name).slice(0, 120),
          email_masked: maskCustomerEmail(record.email),
          phone_masked: maskCustomerPhone(record.phone_normalized || record.phone),
          status: record.status === "archived" ? "archived" : "active",
        });
      }
    }
    const phone = normalizeCustomerPhone(item.phone, item.country_calling_code);
    if (phone.normalized) {
      const rec = await kv.get(companyCustomerPhoneIndexKey(s, phone.normalized), "json");
      const ids = Array.isArray(rec?.customer_ids) ? rec.customer_ids : [];
      for (const id of ids.slice(0, 5)) {
        const customerId = safeStr(id);
        if (!customerId || seen.has(`phone:${customerId}`)) continue;
        seen.add(`phone:${customerId}`);
        const record = await kv.get(companyCustomerRecordKey(s, customerId), "json");
        if (!record?.customer_id) continue;
        matches.push({
          row_key: rowKey,
          customer_id: record.customer_id,
          field: "phone",
          display_name: safeStr(record.display_name).slice(0, 120),
          email_masked: maskCustomerEmail(record.email),
          phone_masked: maskCustomerPhone(record.phone_normalized || record.phone),
          status: record.status === "archived" ? "archived" : "active",
        });
      }
    }
  }
  return { ok: true, status: 200, body: { ok: true, matches } };
}

export async function processImportBatch(env, { scope, importId, rows }) {
  const s = normalizeCustomerScope(scope);
  if (!s.hasScope) return { ok: false, status: 400, error: "missing_tenant_scope" };
  if (!isValidCompanyCustomerImportId(importId)) {
    return { ok: false, status: 400, error: "invalid_import_id" };
  }
  if (!Array.isArray(rows) || !rows.length) {
    return { ok: false, status: 400, error: "empty_batch" };
  }
  if (rows.length > CUSTOMER_IMPORT_BATCH_MAX) {
    return { ok: false, status: 400, error: "batch_too_large" };
  }
  const kv = env.BOOKING_KV;
  const now = nowIso(env);
  let meta = await loadImportMeta(kv, s, importId);
  if (!meta?.import_id) meta = emptyImportMeta(importId, now);
  if (!meta.rows || typeof meta.rows !== "object") meta.rows = {};

  const results = [];
  for (const raw of rows) {
    if (!raw || typeof raw !== "object") {
      results.push({ row_key: "", outcome: "failed", error: "invalid_row" });
      meta.failed += 1;
      meta.processed += 1;
      continue;
    }
    const rowKey = safeStr(raw.row_key);
    if (!isValidCompanyCustomerImportRowKey(rowKey)) {
      results.push({ row_key: rowKey, outcome: "failed", error: "invalid_row_key" });
      meta.failed += 1;
      meta.processed += 1;
      continue;
    }
    const decision = safeStr(raw.decision || "create").toLowerCase();
    const existing = meta.rows[rowKey];
    if (existing?.outcome) {
      if (decision === "create" && existing.content_hash) {
        const body = importCustomerBody(raw.customer);
        const hashed = await importRowContentHash(body);
        if (hashed.ok && hashed.hash && hashed.hash !== existing.content_hash) {
          results.push({
            row_key: rowKey,
            outcome: "conflict",
            error: "idempotency_payload_conflict",
          });
          continue;
        }
      }
      results.push(publicRowOutcome(rowKey, existing, { replayed: true }));
      continue;
    }
    if (decision === "skip") {
      const rec = { outcome: "skipped" };
      meta.rows[rowKey] = rec;
      meta.skipped += 1;
      meta.processed += 1;
      results.push(publicRowOutcome(rowKey, rec));
      continue;
    }
    if (decision !== "create") {
      const rec = { outcome: "failed", error: "invalid_decision" };
      meta.rows[rowKey] = rec;
      meta.failed += 1;
      meta.processed += 1;
      results.push(publicRowOutcome(rowKey, rec));
      continue;
    }
    const body = importCustomerBody(raw.customer);
    const hashed = await importRowContentHash(body);
    const created = await createCompanyCustomer(env, {
      scope: s,
      body,
      idempotencyKey: `imp:${importId}:${rowKey}`,
      source: "import",
      allowImportSource: true,
    });
    if (!created.ok) {
      const rec = {
        outcome: created.error === "idempotency_payload_conflict" ? "conflict" : "failed",
        error: created.error || "invalid_customer",
      };
      if (created.fields) rec.fields = created.fields;
      if (rec.outcome === "failed") {
        meta.rows[rowKey] = rec;
        meta.failed += 1;
        meta.processed += 1;
      }
      results.push(publicRowOutcome(rowKey, rec));
      continue;
    }
    const customer = created.body?.customer;
    const rec = {
      outcome: "created",
      customer_id: customer?.customer_id || "",
      content_hash: hashed.hash || "",
    };
    if (created.body?.idempotent) rec.idempotent = true;
    meta.rows[rowKey] = rec;
    meta.added += 1;
    meta.processed += 1;
    results.push(publicRowOutcome(rowKey, rec));
  }

  await saveImportMeta(kv, s, meta);
  auditImport("batch", {
    reason: "sequential",
    rows: results.length,
    added: meta.added,
    skipped: meta.skipped,
    failed: meta.failed,
  });
  return {
    ok: true,
    status: 200,
    body: {
      ok: true,
      import_id: importId,
      added: meta.added,
      skipped: meta.skipped,
      failed: meta.failed,
      processed: meta.processed,
      rows: results,
    },
  };
}

function errorBody(result) {
  const body = { ok: false, error: result.error || "invalid_import" };
  if (result.fields) body.fields = result.fields;
  return body;
}

export async function serveCompanyCustomerImportHttp({
  env,
  method,
  importId,
  action,
  body,
  scope,
}) {
  if (method === "GET" && !action) {
    const result = await getCompanyCustomerImport(env, { scope, importId });
    if (!result.ok) return json(errorBody(result), result.status);
    return json(result.body, 200);
  }
  if (method === "POST" && action === "lookups") {
    const result = await lookupImportContacts(env, {
      scope,
      importId,
      contacts: body?.contacts,
    });
    if (!result.ok) return json(errorBody(result), result.status);
    return json(result.body, 200);
  }
  if (method === "POST" && action === "batches") {
    const result = await processImportBatch(env, {
      scope,
      importId,
      rows: body?.rows,
    });
    if (!result.ok) return json(errorBody(result), result.status);
    return json(result.body, 200);
  }
  return json({ ok: false, error: "method_not_allowed" }, 405);
}
