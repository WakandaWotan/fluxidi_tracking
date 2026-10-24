import {indexedInvoiceSources} from './company_invoice_source_index.mjs';
import { assembleCompanyMonthlyInvoice, validateCompanyCustomerInvoicingPolicy } from './company_customer_invoicing.mjs';

const fail = error => ({ ok: false, error });
const sameScope = (a, b) => a?.tenant_id === b?.tenant_id && a?.company_id === b?.company_id;
const identifier = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,160}$/.test(value);
const PREFIX = 'canonical-booking:';

// Reads the company Durable Object's full canonical inventory, never the
// bounded agenda list or a KV projection. Only new rides stamped with the
// server-verified monthly policy can be selected; no historical conversion.
// The projector must derive completed booking/leg prices from server records.
export async function collectCompanyMonthlyInvoiceSources(storage, {
  scope, customerId, month, projectRecord, maxRecords = null,
}) {
  if (!identifier(scope?.tenant_id) || !identifier(scope?.company_id) || !identifier(customerId)) return fail('billing_scope_required');
  if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(month || '')) return fail('invoice_month_invalid');
  if (!storage?.get || !storage?.list || typeof projectRecord !== 'function') return fail('invoice_source_authority_required');
  if (maxRecords != null && (!Number.isSafeInteger(maxRecords) || maxRecords < 1 || maxRecords > 10000)) return fail('invoice_inventory_limit_invalid');
  const pin = await storage.get('canonical-booking-scope');
  if (!sameScope(pin, scope)) return fail('invoice_source_scope_unverified');
  let indexed=null;
  if(maxRecords==null){try{indexed=await indexedInvoiceSources(storage,{scope,customerId,month});}catch(error){return fail(error.message||'invoice_inventory_unverified');}}
  if(indexed&&!indexed.ok)return indexed;
  let cursor = ''; let scanned = 0;let indexedRead=false;
  const lines = [];
  while (true) {
    const page = indexed ? new Map(indexedRead?[]:indexed.entries)
      : await storage.list({ prefix: PREFIX, limit: 20, ...(cursor ? { startAfter: cursor } : {}) });
    indexedRead=true;
    if (!(page instanceof Map)) return fail('invoice_inventory_unverified');
    if (!page.size) break;
    const entries = [...page.entries()].sort(([a], [b]) => a.localeCompare(b));
    for (const [key, envelope] of entries) {
      if (!key.startsWith(PREFIX) || key <= cursor || !identifier(key.slice(PREFIX.length))) return fail('invoice_inventory_cursor_invalid');
      cursor = key;
      if (++scanned > (maxRecords ?? Infinity)) return fail('invoice_inventory_limit_exceeded');
      if (!sameScope(envelope, scope) || !sameScope(envelope?.record, scope) || envelope.schema !== 1 ||
          !Number.isSafeInteger(envelope.version) || envelope.version < 1 || envelope.record._canonical_version !== envelope.version) return fail('invoice_source_scope_unverified');
      const policy = envelope.record.company_customer_invoicing_policy;
      if (policy == null) continue;
      const verified = validateCompanyCustomerInvoicingPolicy(policy, scope);
      if (!verified.ok) return verified;
      if (policy.customer_id !== customerId || policy.invoice_frequency !== 'monthly') continue;
      const projected = await projectRecord({ record: structuredClone(envelope.record),
        bookingId: key.slice(PREFIX.length), scope, customerId, month });
      if (!projected?.ok || !Array.isArray(projected.lines)) return fail(projected?.error || 'invoice_source_projection_failed');
      for (const line of projected.lines) {
        // Ignore no caller-supplied scope, policy, source or revision overrides.
        if (!sameScope(line, scope) || line.booking_id !== key.slice(PREFIX.length) ||
            line.canonical_version !== envelope.version || JSON.stringify(line.billing_policy) !== JSON.stringify(policy)) return fail('invoice_source_projection_unverified');
        lines.push(structuredClone(line));
      }
      if (lines.length > 1000) return fail('invoice_line_limit_exceeded');
    }
    // Do not infer completion from a short page: consult the next cursor even
    // if the storage adapter returns fewer than its requested limit.
  }
  if (!lines.length) return { ok: true, empty: true, scanned, coverage: 'verified_monthly_policy_only' };
  const assembled = assembleCompanyMonthlyInvoice({ scope, customerId, month, lines, complete: true });
  return assembled.ok ? { ...assembled, empty: false, scanned, coverage: 'verified_monthly_policy_only' } : assembled;
}
