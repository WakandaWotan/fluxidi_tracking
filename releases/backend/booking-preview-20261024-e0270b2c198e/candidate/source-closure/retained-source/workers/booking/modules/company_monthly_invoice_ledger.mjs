import { assembleCompanyMonthlyInvoice } from './company_customer_invoicing.mjs';

// Durable Object storage transaction required: KV read/put and process locks
// cannot provide invoice ownership across requests, isolates or restarts.
// Reservation survives uncertain issuance. Never release/reassign on timeout.
const fail = error => ({ ok: false, error });
const canonical = value => Array.isArray(value) ? value.map(canonical) :
  value && typeof value === 'object' ? Object.fromEntries(Object.keys(value).sort().map(k => [k, canonical(value[k])])) : value;
async function digest(value) {
  const bytes = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(JSON.stringify(canonical(value))));
  return [...new Uint8Array(bytes)].map(b => b.toString(16).padStart(2, '0')).join('');
}
const prefix = scope => `monthly_invoice:v1:${scope.tenant_id}:${scope.company_id}`;
const batchKey = (scope, customerId, month) => `${prefix(scope)}:batch:${customerId}:${month}`;
const sourceKey = (scope, bookingId) => `${prefix(scope)}:source:${bookingId}`;

export async function reserveCompanyMonthlyInvoice(storage, { scope, invoice }) {
  if (typeof storage?.transaction !== 'function') return fail('invoice_transaction_required');
  if (invoice?.tenant_id !== scope?.tenant_id || invoice?.company_id !== scope?.company_id) return fail('invoice_source_scope_mismatch');
  const rebuilt = assembleCompanyMonthlyInvoice({ scope, customerId: invoice?.customer_id,
    month: invoice?.month, lines: invoice?.lines, complete: true });
  if (!rebuilt.ok) return rebuilt;
  const frozen = rebuilt.invoice;
  const hash = await digest(frozen);
  const key = batchKey(scope, frozen.customer_id, frozen.month);
  return storage.transaction(async tx => {
    const existing = await tx.get(key);
    if (existing) {
      if (existing.content_hash !== hash) return fail('monthly_invoice_batch_changed');
      return { ok: true, reservation: structuredClone(existing), replay: true };
    }
    const byBooking = new Map();
    for (const line of frozen.lines) {
      const claims = byBooking.get(line.booking_id) ?? [];
      claims.push(line.leg_id ?? '');
      byBooking.set(line.booking_id, claims);
    }
    // Validate ALL ownership before writes. Parent-vs-leg conflicts also span
    // different batches/months. An uncertain pending owner blocks a new owner.
    const changes = [];
    for (const [bookingId, legs] of byBooking) {
      const source = sourceKey(scope, bookingId);
      const claims = (await tx.get(source)) ?? {};
      if (legs.some(leg => claims[leg] || claims[''] || (leg === '' && Object.keys(claims).length))) return fail('invoice_source_already_claimed');
      for (const leg of legs) claims[leg] = { batch_key: key, content_hash: hash };
      changes.push([source, claims]);
    }
    const reservation = { schema_version: 1, state: 'reserved', batch_key: key,
      content_hash: hash, invoice: frozen, document: null };
    for (const [source, claims] of changes) await tx.put(source, claims);
    await tx.put(key, reservation);
    return { ok: true, reservation: structuredClone(reservation), replay: false };
  });
}

export async function finalizeCompanyMonthlyInvoice(storage, { scope, customerId, month, contentHash, document }) {
  if (typeof storage?.transaction !== 'function') return fail('invoice_transaction_required');
  if (!/^[A-Za-z0-9_-]{1,160}$/.test(scope?.tenant_id || '') || !/^[A-Za-z0-9_-]{1,160}$/.test(scope?.company_id || '') ||
      !/^[A-Za-z0-9_-]{1,160}$/.test(customerId || '') || !/^\d{4}-(0[1-9]|1[0-2])$/.test(month || '')) return fail('billing_scope_required');
  // Called ONLY with verified canonical registry metadata, never a public body.
  if (!document || !/^[A-Za-z0-9_-]{1,160}$/.test(document.document_id || '') ||
      !/^INV-[A-Za-z0-9_-]+$/.test(document.document_number || '') ||
      document.lifecycle_state !== 'issued' || document.tenant_id !== scope.tenant_id ||
      document.company_id !== scope.company_id || document.monthly_content_hash !== contentHash) return fail('invoice_document_unverified');
  const key = batchKey(scope, customerId, month);
  return storage.transaction(async tx => {
    const reservation = await tx.get(key);
    if (!reservation || reservation.content_hash !== contentHash) return fail('invoice_reservation_mismatch');
    if (reservation.state === 'issued') {
      if (reservation.document.document_id !== document.document_id || reservation.document.document_number !== document.document_number) return fail('invoice_document_conflict');
      return { ok: true, reservation: structuredClone(reservation), replay: true };
    }
    const finished = { ...reservation, state: 'issued', document: {
      document_id: document.document_id, document_number: document.document_number,
    } };
    await tx.put(key, finished);
    return { ok: true, reservation: structuredClone(finished), replay: false };
  });
}
