import { finalizeCompanyMonthlyInvoice } from './company_monthly_invoice_ledger.mjs';
import { companyInvoiceMonth } from './company_customer_invoicing.mjs';

const fail = error => ({ ok: false, error });
const sameScope = (a, b) => a?.tenant_id === b?.tenant_id && a?.company_id === b?.company_id;
const stable = value => JSON.stringify(sort(value));
const sort = value => Array.isArray(value) ? value.map(sort) : value && typeof value === 'object'
  ? Object.fromEntries(Object.keys(value).sort().map(key => [key, sort(value[key])])) : value;
const id = value => /^[A-Za-z0-9_-]{1,160}$/.test(value || '');

// Called by the authenticated company coordinator with server-owned parties.
// External allocation is idempotent by content hash. The full issued document
// is durable BEFORE projection; failed indexes never cause a second invoice.
// This helper performs no PDF, payment, Billit or email operation.
export async function issueReservedCompanyMonthlyInvoice(storage, {
  scope, customerId, month, contentHash, seller, buyer, now,
  allocateReference, buildDocument, projectDocument,
}) {
  if (!storage?.transaction || !storage?.get) return fail('invoice_transaction_required');
  if (!id(scope?.tenant_id) || !id(scope?.company_id) || !id(customerId) ||
      !/^\d{4}-(0[1-9]|1[0-2])$/.test(month || '') || !/^[a-f0-9]{64}$/.test(contentHash || '')) return fail('billing_scope_required');
  const currentMonth = companyInvoiceMonth(now);
  if (!currentMonth || month >= currentMonth) return fail('invoice_period_not_closed');
  if (!seller || !buyer || typeof allocateReference !== 'function' || typeof buildDocument !== 'function' ||
      typeof projectDocument !== 'function') return fail('invoice_issue_dependencies_required');
  const prefix = `monthly_invoice:v1:${scope.tenant_id}:${scope.company_id}`;
  const key = `${prefix}:batch:${customerId}:${month}`;
  const journalKey = `${prefix}:issue:${customerId}:${month}`;
  const prepared = await storage.transaction(async tx => {
    const reservation = await tx.get(key);
    if (!reservation || reservation.content_hash !== contentHash || !sameScope(reservation.invoice, scope)) return fail('invoice_reservation_mismatch');
    const existing = await tx.get(journalKey);
    if (existing) {
      if (existing.content_hash !== contentHash || !sameScope(existing, scope)) return fail('invoice_issue_conflict');
      // Resume with frozen identities, even if the CRM/profile changed later.
      return { ok: true, journal: existing };
    }
    if (reservation.state !== 'reserved') return fail('invoice_issue_journal_missing');
    if (!(seller.legal_name || seller.name) || reservation.invoice.lines.some(line =>
      stable(line.billing_policy?.buyer_snapshot) !== stable(buyer))) return fail('invoice_party_snapshot_unverified');
    const bytes = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(stable(buyer)));
    const buyerKey = [...new Uint8Array(bytes)].map(byte => byte.toString(16).padStart(2, '0')).join('');
    if (reservation.invoice.buyer_identity_key !== buyerKey) return fail('invoice_party_snapshot_unverified');
    const journal = { schema_version: 1, ...scope, content_hash: contentHash,
      customer_id: customerId, month, state: 'prepared', issued_at: now,
      document_id: `monthly_${contentHash}`, invoice: structuredClone(reservation.invoice),
      seller: structuredClone(seller), buyer: structuredClone(buyer), document: null };
    await tx.put(journalKey, journal);
    return { ok: true, journal };
  });
  if (!prepared.ok) return prepared;
  let journal = prepared.journal;
  if (!journal.document) {
    let reference, document;
    try {
      reference = await allocateReference({ scope, contentHash, issueTimestamp: journal.issued_at });
      if (typeof reference !== 'string' || !/^INV-[A-Za-z0-9_-]+$/.test(reference)) return fail('invoice_allocation_pending');
      document = await buildDocument({ ...structuredClone(journal), reference: structuredClone(reference) });
    } catch { return fail('invoice_issue_pending'); }
    if (!document || !sameScope(document, scope) || document.document_id !== journal.document_id ||
        document.customer_id !== customerId || document.month !== month || document.monthly_content_hash !== contentHash ||
        document.lifecycle_state !== 'issued' || document.document_number !== reference ||
        document.issued_at !== journal.issued_at || stable(document.immutable_snapshot?.monthly_invoice) !== stable(journal.invoice) ||
        stable(document.immutable_snapshot?.seller_snapshot) !== stable(journal.seller) ||
        stable(document.immutable_snapshot?.buyer_snapshot) !== stable(journal.buyer)) return fail('invoice_document_unverified');
    const saved = await storage.transaction(async tx => {
      const latest = await tx.get(journalKey);
      if (!latest || latest.content_hash !== contentHash) return fail('invoice_issue_conflict');
      if (latest.document) {
        if (stable(latest.document) !== stable(document)) return fail('invoice_document_conflict');
        return { ok: true, journal: latest };
      }
      const issued = { ...latest, state: 'issued', document: structuredClone(document) };
      await tx.put(journalKey, issued);
      return { ok: true, journal: issued };
    });
    if (!saved.ok) return saved;
    journal = saved.journal;
  }
  const finalized = await finalizeCompanyMonthlyInvoice(storage, {
    scope, customerId, month, contentHash, document: journal.document,
  });
  if (!finalized.ok) return finalized;
  // Retried projections must upsert the SAME immutable document and indexes.
  // Never release the source claim on an uncertain projection response.
  try {
    const projection = await projectDocument(structuredClone(journal.document));
    if (!projection?.ok) return { ok: true, issued: true, projection_pending: true, document: structuredClone(journal.document) };
  } catch {
    return { ok: true, issued: true, projection_pending: true, document: structuredClone(journal.document) };
  }
  return { ok: true, issued: true, projection_pending: false, document: structuredClone(journal.document) };
}
