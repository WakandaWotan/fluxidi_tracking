import { assembleCompanyMonthlyInvoice } from './company_customer_invoicing.mjs';
import { buildDocumentRegistryKey, buildDocumentNumberIndexKey, buildDocumentsByBookingKey,
  buildDocumentsByLegKey, hashDocumentSnapshot, stableDocumentJson } from './document_core.js';

// Separate builder: legacy per-ride documents and their hashes stay unchanged.
export async function buildCompanyMonthlyInvoiceRegistryRecord(journal) {
  const scope = { tenant_id: journal.tenant_id, company_id: journal.company_id };
  const assembled = assembleCompanyMonthlyInvoice({ scope, customerId: journal.customer_id,
    month: journal.month, lines: journal.invoice?.lines, complete: true });
  if (!assembled.ok || stableDocumentJson(assembled.invoice) !== stableDocumentJson(journal.invoice) ||
      await hashDocumentSnapshot(assembled.invoice) !== journal.content_hash ||
      journal.document_id !== `monthly_${journal.content_hash}` || !/^INV-[A-Za-z0-9_-]+$/.test(journal.reference || '') ||
      !Number.isFinite(Date.parse(journal.issued_at))) throw new Error('monthly_registry_source_unverified');
  const invoice = assembled.invoice;
  const sources = [...new Set(invoice.lines.map(line => line.booking_id))].sort();
  const totals = { subtotal_ex_vat: invoice.totals.net_cents / 100, vat_amount: invoice.totals.vat_cents / 100,
    total_incl_vat: invoice.totals.gross_cents / 100,
    vat_rate_percent: invoice.tax_groups.length === 1 ? invoice.tax_groups[0].vat_rate_percent : null };
  const snapshot = { ...scope, document_id: journal.document_id, document_type: 'invoice',
    document_number: journal.reference, issue_timestamp: journal.issued_at,
    source_booking_id: sources[0], source_booking_ids: sources, currency: invoice.currency, totals,
    seller_snapshot: structuredClone(journal.seller), buyer_snapshot: structuredClone(journal.buyer),
    monthly_invoice: structuredClone(invoice) };
  return { ...snapshot, issued_at: journal.issued_at, lifecycle_state: 'issued', document_status: 'issued',
    invoice_frequency: 'monthly', customer_id: journal.customer_id, month: journal.month,
    monthly_content_hash: journal.content_hash, content_hash: await hashDocumentSnapshot(snapshot),
    immutable_snapshot: snapshot, provider_name: null, provider_export_status: null };
}

export async function projectCompanyMonthlyInvoiceRegistry(env, document, storage = null) {
  if (!env?.BOOKING_KV?.get || !env?.BOOKING_KV?.put) return { ok: false, error: 'missing_binding' };
  const snapshot = document?.immutable_snapshot;
  if (!snapshot?.monthly_invoice || document.invoice_frequency !== 'monthly' ||
      await hashDocumentSnapshot(snapshot) !== document.content_hash ||
      document.tenant_id !== snapshot.tenant_id || document.company_id !== snapshot.company_id ||
      document.document_id !== snapshot.document_id || document.document_number !== snapshot.document_number ||
      stableDocumentJson(document.source_booking_ids) !== stableDocumentJson(snapshot.source_booking_ids)) {
    return { ok: false, error: 'invoice_document_unverified' };
  }
  const scope = { tenant_id: document.tenant_id, company_id: document.company_id };
  const registryKey = buildDocumentRegistryKey(scope, document.document_id);
  const existing = await env.BOOKING_KV.get(registryKey, 'json');
  if (existing && existing.content_hash !== document.content_hash) return { ok: false, error: 'invoice_document_conflict' };
  const numberKey = buildDocumentNumberIndexKey(scope, 'invoice', document.document_number);
  const numberOwner = await env.BOOKING_KV.get(numberKey);
  if (numberOwner && numberOwner !== document.document_id) return { ok: false, error: 'invoice_number_conflict' };
  // Canonical DO journal already owns this document. KV is a repairable read
  // projection; an interrupted write never releases or reallocates its number.
  const writes = [[registryKey, JSON.stringify(document)], [numberKey, document.document_id]];
  for (const bookingId of snapshot.source_booking_ids) {
    writes.push([buildDocumentsByBookingKey(scope, bookingId, 'invoice', document.document_id), document.document_id]);
  }
  for (const line of snapshot.monthly_invoice.lines) {
    if (line.leg_id) writes.push([buildDocumentsByLegKey(scope, line.booking_id, line.leg_id, 'invoice', document.document_id), document.document_id]);
  }
  const cursorKey = `monthly_invoice_projection:v1:${scope.tenant_id}:${scope.company_id}:${document.document_id}`;
  const cursor = storage ? await storage.get(cursorKey) : null;
  if (cursor && (cursor.content_hash !== document.content_hash || !Number.isSafeInteger(cursor.offset) || cursor.offset < 0 || cursor.offset > writes.length)) return { ok: false, error: 'invoice_projection_cursor_unverified' };
  const offset = cursor?.offset || 0;
  // Bounded pages avoid exceeding Worker subrequest budgets for a large month.
  // A failed page repeats only idempotent projections, never invoice issuance.
  const end = storage ? Math.min(offset + 20, writes.length) : writes.length;
  for (let index = offset; index < end; index++) {
    if (index === 0 && existing) continue;
    await env.BOOKING_KV.put(...writes[index]);
  }
  if (storage) await storage.put(cursorKey, { content_hash: document.content_hash, offset: end, total: writes.length });
  if (end < writes.length) return { ok: false, pending: true, error: 'invoice_projection_pending' };
  return { ok: true };
}
