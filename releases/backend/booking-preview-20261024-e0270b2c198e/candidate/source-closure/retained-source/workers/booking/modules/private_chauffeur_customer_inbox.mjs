import { buildLimousineCustomerFingerprint } from './limousine_manual_quote.mjs';

export function privateQuoteOwnedBy(record, customerId) {
  if (!customerId || record?.origin_channel === 'company_external' || record?.origin === 'company_external') return false;
  if (record.customer_id) return record.customer_id === customerId;
  // Older requests already bind their status capability to this customer.
  return record.status_access?.customer_fingerprint === buildLimousineCustomerFingerprint({
    tenantId: record.tenant_id, companyId: record.company_id, customerRef: customerId,
    quoteRequestId: record.quote_request_id,
    itineraryFingerprint: record.request?.itinerary_fingerprint,
  });
}

export async function readPrivateCustomerQuotePage({ customerId, candidates, offset = 0,
  loadRecord, project, seal, isPrivate, scopeAllowed }) {
  const ids = [...new Set(candidates)].filter(Boolean);
  const end = Math.min(ids.length, offset + 50);
  const items = [];
  for (const id of ids.slice(offset, end)) {
    const record = await loadRecord(id);
    if (!record || !isPrivate(record) || !scopeAllowed(record) || !privateQuoteOwnedBy(record, customerId)) continue;
    const reference = await seal(record);
    if (!reference?.reference) continue;
    items.push({ quote_request: project(record), status_ref: reference.reference });
  }
  return { ok: true, items, next_cursor: end < ids.length ? String(end) : null };
}
