import { companyCustomerEmailIndexKey, companyCustomerRecordKey, normalizeCustomerEmail } from './company_customers.mjs';
import { snapshotCompanyCustomerInvoicing, validateCompanyCustomerInvoicingPolicy } from './company_customer_invoicing.mjs';

// session is supplied only by the server's authenticated session loader.
// The public booking body cannot select a CRM identity or billing cadence.
export async function loadPublicCompanyCustomerInvoicing(env, { scope, bookingId, email, loadSession }) {
  if (env?.COMPANY_MONTHLY_INVOICING_ENABLED !== '1') return { ok: true, policy: null };
  if (!/^[A-Za-z0-9_-]{1,160}$/.test(bookingId || '') ||
      !/^[A-Za-z0-9_-]{1,160}$/.test(scope?.tenant_id || '') ||
      !/^[A-Za-z0-9_-]{1,160}$/.test(scope?.company_id || '')) return { ok: false, error: 'billing_scope_required' };
  try {
    const existing = await env.BOOKING_KV.get(`booking:${bookingId}`, 'json');
    if (existing) {
      if (existing.tenant_id !== scope.tenant_id || existing.company_id !== scope.company_id) return { ok: false, error: 'billing_scope_mismatch' };
      // Retries and payment finalization never retrofit a historical booking.
      const policy = existing.company_customer_invoicing_policy;
      return policy == null ? { ok: true, policy: null } : validateCompanyCustomerInvoicingPolicy(policy, scope);
    }
    const normalized = normalizeCustomerEmail(email);
    if (!normalized) return { ok: true, policy: null };
    const session = await loadSession();
    if (!session || session.purpose !== 'customer_session' ||
        !(session.tenant_id === 'global' && session.company_id === 'global') &&
        !(session.tenant_id === scope.tenant_id && session.company_id === scope.company_id)) return { ok: true, policy: null };
    const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(normalized));
    const hash = [...new Uint8Array(digest)].map(byte => byte.toString(16).padStart(2, '0')).join('');
    if (session.email_hash !== hash) return { ok: true, policy: null };
    const scoped = { ...scope, hasScope: true };
    const index = await env.BOOKING_KV.get(companyCustomerEmailIndexKey(scoped, normalized), 'json');
    const ids = [...new Set(Array.isArray(index?.customer_ids) ? index.customer_ids : [])];
    if (!ids.length) return { ok: true, policy: null };
    if (ids.length !== 1 || !/^[A-Za-z0-9_-]{1,160}$/.test(ids[0])) return { ok: false, error: 'billing_customer_ambiguous' };
    const customer = await env.BOOKING_KV.get(companyCustomerRecordKey(scoped, ids[0]), 'json');
    if (customer?.customer_id !== ids[0] || normalizeCustomerEmail(customer?.email) !== normalized) return { ok: false, error: 'billing_customer_unverified' };
    return snapshotCompanyCustomerInvoicing({ scope, customer, enabled: true });
  } catch {
    return { ok: false, error: 'billing_customer_unavailable' };
  }
}
