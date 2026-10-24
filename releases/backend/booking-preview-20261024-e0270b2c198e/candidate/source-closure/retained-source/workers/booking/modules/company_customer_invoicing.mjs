// Server-owned billing cadence. This module does not grant deferred-payment
// rights, alter payments, allocate invoice numbers or send PDFs.
import { companyCustomerRecordKey } from './company_customers.mjs';
const identifier = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,160}$/.test(value);
const frequency = value => value === 'per_ride' || value === 'monthly';
const fail = error => ({ ok: false, error });

export async function loadCompanyCustomerInvoicingPolicy(env, scope, customerId) {
  if (env?.COMPANY_MONTHLY_INVOICING_ENABLED !== '1') return { ok: true, policy: null };
  if (!identifier(scope?.tenant_id) || !identifier(scope?.company_id)) return fail('billing_scope_required');
  if (!identifier(customerId)) return fail('billing_customer_unverified');
  const key = companyCustomerRecordKey({ ...scope, hasScope: true }, customerId);
  if (!key || !env?.BOOKING_KV?.get) return fail('billing_customer_unverified');
  try {
    const customer = await env.BOOKING_KV.get(key, 'json');
    if (customer?.customer_id !== customerId) return fail('billing_customer_unverified');
    return snapshotCompanyCustomerInvoicing({ scope, customer, enabled: true });
  } catch {
    return fail('billing_customer_unavailable');
  }
}

export function snapshotCompanyCustomerInvoicing({ scope, customer, enabled = false }) {
  if (!enabled) return { ok: true, policy: null };
  if (!identifier(scope?.tenant_id) || !identifier(scope?.company_id)) return fail('billing_scope_required');
  // Caller supplies the record loaded using the authenticated company's key.
  // Public request preferences/customer IDs are never sufficient evidence.
  if (customer?.tenant_id !== scope.tenant_id || customer?.company_id !== scope.company_id ||
      !identifier(customer?.customer_id) || customer?.status !== 'active' ||
      !Number.isSafeInteger(customer?.revision) || customer.revision < 1) return fail('billing_customer_unverified');
  const cadence = customer.preferences?.invoice_frequency ?? 'per_ride';
  if (!frequency(cadence)) return fail('invoice_frequency_invalid');
  const billingAddresses = (Array.isArray(customer.addresses) ? customer.addresses : []).filter(address => address.type === 'billing');
  const address = billingAddresses.length === 1 ? billingAddresses[0] : null;
  const name = customer.company_name || customer.display_name;
  // Freeze only an explicit billing address. Never guess a pickup/home address
  // or choose between multiple legal recipients. Missing data blocks issuance
  // later, without granting credit or silently rewriting existing bookings.
  const buyer = cadence === 'monthly' && name && address?.line1 && address?.postal_code && address?.city && /^[A-Z]{2}$/.test(address?.country_code || '') ? {
    legal_name: name, name, email: customer.email || '', vat_number: customer.vat_number || '',
    address_line1: address.line1, address_line2: address.line2 || '',
    postal_code: address.postal_code, city: address.city, country_code: address.country_code,
  } : null;
  return { ok: true, policy: {
    schema_version: 1, tenant_id: scope.tenant_id, company_id: scope.company_id,
    customer_id: customer.customer_id, customer_revision: customer.revision,
    invoice_frequency: cadence,
    ...(buyer ? { buyer_snapshot: structuredClone(buyer) } : {}),
  } };
}

export function validateCompanyCustomerInvoicingPolicy(policy, scope) {
  if (!policy || policy.schema_version !== 1 || !frequency(policy.invoice_frequency) ||
      !identifier(policy.customer_id) || !identifier(policy.tenant_id) || !identifier(policy.company_id) ||
      !Number.isSafeInteger(policy.customer_revision) || policy.customer_revision < 1 ||
      policy.tenant_id !== scope?.tenant_id || policy.company_id !== scope?.company_id) {
    return fail('billing_policy_unverified');
  }
  return { ok: true, policy: structuredClone(policy) };
}

export function companyInvoiceDeliveryDecision({ enabled = false, scope, policy }) {
  if (!enabled || policy == null) return { ok: true, delivery: 'per_ride' };
  const verified = validateCompanyCustomerInvoicingPolicy(policy, scope);
  return verified.ok ? { ok: true, delivery: policy.invoice_frequency } : verified;
}

// A persisted cadence remains binding even if the feature is switched off.
// Otherwise rollback could issue per-ride invoices for an already reserved
// monthly source. Legacy records without the additive field pass unchanged.
export function companyPerRideInvoiceDecision(record, scope) {
  const policy = record?.company_customer_invoicing_policy;
  if (policy == null) return { blocked: false };
  const result = validateCompanyCustomerInvoicingPolicy(policy, scope);
  if (!result.ok) return { blocked: true, error: result.error };
  return policy.invoice_frequency === 'monthly'
    ? { blocked: true, error: 'monthly_invoice_required' } : { blocked: false };
}

const monthFormatter = new Intl.DateTimeFormat('en-CA', {
  timeZone: 'Europe/Brussels', year: 'numeric', month: '2-digit',
});

export function companyInvoiceMonth(instant) {
  if (typeof instant !== 'string' || !/^\d{4}-\d{2}-\d{2}T.*(?:Z|[+-]\d{2}:\d{2})$/.test(instant)) return null;
  const date = new Date(instant);
  if (!Number.isFinite(date.getTime())) return null;
  const day = instant.slice(0, 10);
  const calendar = new Date(`${day}T00:00:00Z`);
  if (!Number.isFinite(calendar.getTime()) || calendar.toISOString().slice(0, 10) !== day) return null;
  const parts = Object.fromEntries(monthFormatter.formatToParts(date).map(p => [p.type, p.value]));
  return `${parts.year}-${parts.month}`;
}

// Input lines must be derived from canonical completed booking/leg records by
// the server. A caller must prove complete pagination before issuing a batch.
// No rounding from floating point euros and no client-supplied invoice totals.
export function assembleCompanyMonthlyInvoice({ scope, customerId, month, lines, complete = false }) {
  if (!identifier(scope?.tenant_id) || !identifier(scope?.company_id) || !identifier(customerId)) return fail('billing_scope_required');
  if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(month || '')) return fail('invoice_month_invalid');
  if (complete !== true) return fail('invoice_sources_incomplete');
  if (!Array.isArray(lines) || lines.length === 0 || lines.length > 1000) return fail('invoice_lines_invalid');
  const sources = new Set();
  const sourceBookings = new Set();
  const taxGroups = new Map();
  const accepted = [];
  let currency;
  let buyerIdentityKey;
  let net = 0, vat = 0, gross = 0;
  for (const line of lines) {
    if (!line || line.tenant_id !== scope.tenant_id || line.company_id !== scope.company_id) return fail('invoice_source_scope_mismatch');
    const verified = validateCompanyCustomerInvoicingPolicy(line.billing_policy, scope);
    if (!verified.ok || line.billing_policy.customer_id !== customerId || line.billing_policy.invoice_frequency !== 'monthly') return fail('invoice_source_policy_mismatch');
    if (line.status !== 'completed' || line.already_invoiced !== false) return fail('invoice_source_not_billable');
    if (companyInvoiceMonth(line.completed_at) !== month) return fail('invoice_source_month_mismatch');
    if (!identifier(line.booking_id) || (line.leg_id != null && !identifier(line.leg_id))) return fail('invoice_source_id_invalid');
    // Parent totals and individual legs of the same booking cannot coexist.
    const source = `${line.booking_id}:${line.leg_id ?? ''}`;
    if (sources.has(source) || (line.leg_id != null && sources.has(`${line.booking_id}:`)) ||
        (line.leg_id == null && sourceBookings.has(line.booking_id))) return fail('invoice_source_duplicate');
    sources.add(source);
    sourceBookings.add(line.booking_id);
    if (!/^[A-Z]{3}$/.test(line.currency || '')) return fail('invoice_currency_invalid');
    if (currency && currency !== line.currency) return fail('invoice_currency_mismatch');
    currency = line.currency;
    // Legal buyer snapshot fingerprint is derived server-side, not merely email.
    if (typeof line.buyer_identity_key !== 'string' || !/^[a-f0-9]{64}$/.test(line.buyer_identity_key)) return fail('invoice_buyer_identity_required');
    if (buyerIdentityKey && buyerIdentityKey !== line.buyer_identity_key) return fail('invoice_buyer_identity_mismatch');
    buyerIdentityKey = line.buyer_identity_key;
    if (![line.net_cents, line.vat_cents, line.gross_cents].every(n => Number.isSafeInteger(n) && n >= 0) ||
        line.net_cents + line.vat_cents !== line.gross_cents || line.gross_cents === 0 ||
        typeof line.vat_rate_percent !== 'number' || !Number.isFinite(line.vat_rate_percent) ||
        line.vat_rate_percent < 0 || line.vat_rate_percent > 100 ||
        Math.abs(Math.round(line.net_cents * line.vat_rate_percent / 100) - line.vat_cents) > 1) return fail('invoice_totals_invalid');
    net += line.net_cents; vat += line.vat_cents; gross += line.gross_cents;
    if (![net, vat, gross].every(Number.isSafeInteger)) return fail('invoice_totals_overflow');
    const group = taxGroups.get(line.vat_rate_percent) ?? { vat_rate_percent: line.vat_rate_percent, net_cents: 0, vat_cents: 0, gross_cents: 0 };
    group.net_cents += line.net_cents; group.vat_cents += line.vat_cents; group.gross_cents += line.gross_cents;
    taxGroups.set(line.vat_rate_percent, group);
    accepted.push(structuredClone(line));
  }
  accepted.sort((a, b) => a.completed_at.localeCompare(b.completed_at) || a.booking_id.localeCompare(b.booking_id) || (a.leg_id ?? '').localeCompare(b.leg_id ?? ''));
  return { ok: true, invoice: {
    schema_version: 1, tenant_id: scope.tenant_id, company_id: scope.company_id,
    customer_id: customerId, month, currency, buyer_identity_key: buyerIdentityKey,
    totals: { net_cents: net, vat_cents: vat, gross_cents: gross },
    tax_groups: [...taxGroups.values()].sort((a, b) => a.vat_rate_percent - b.vat_rate_percent),
    lines: accepted,
  } };
}
