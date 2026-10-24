import { companyInvoiceMonth, validateCompanyCustomerInvoicingPolicy } from './company_customer_invoicing.mjs';

const fail = error => ({ ok: false, error });
const stable = value => JSON.stringify(sort(value));
const sort = value => Array.isArray(value) ? value.map(sort) : value && typeof value === 'object'
  ? Object.fromEntries(Object.keys(value).sort().map(key => [key, sort(value[key])])) : value;
const cents = value => typeof value === 'number' && Number.isFinite(value) && value >= 0 &&
  Number.isSafeInteger(Math.round(value * 100)) && Math.abs(value * 100 - Math.round(value * 100)) < 0.00001 ? Math.round(value * 100) : null;
const routeLabel = value => typeof value === 'string' ? value.trim().slice(0, 240) : '';

// Pure canonical source projection apart from an injected authoritative
// document ownership reader. KV index absence is NOT proof of no invoice.
export async function projectCompanyMonthlyInvoiceRecord({ record, scope, bookingId, customerId, month,
  deriveInvoiceContext, readSourceOwnership }) {
  const policy = record?.company_customer_invoicing_policy;
  const verified = validateCompanyCustomerInvoicingPolicy(policy, scope);
  if (!verified.ok || policy.customer_id !== customerId || policy.invoice_frequency !== 'monthly' ||
      record?.tenant_id !== scope?.tenant_id || record?.company_id !== scope?.company_id ||
      !Number.isSafeInteger(record?._canonical_version) || record._canonical_version < 1) return fail('invoice_source_policy_mismatch');
  if (typeof deriveInvoiceContext !== 'function' || typeof readSourceOwnership !== 'function') return fail('invoice_source_authority_required');
  const containers = [record, record.booking, record.payload].filter(Boolean)
    .flatMap(container => [container.operational_legs, container.operationalLegs]).filter(Array.isArray).filter(list => list.length);
  // Duplicated legacy representations must agree, otherwise choosing the first
  // could hide another completed leg or a different stored price.
  if (containers.some(list => stable(list) !== stable(containers[0]))) return fail('invoice_legs_ambiguous');
  const legs = containers[0] || null;
  const candidates = legs || [record];
  const lines = []; const seen = new Set();
  for (const source of candidates) {
    if ((source.status ?? source.lifecycle_status ?? source.lifecycleStatus) !== 'completed') continue;
    const completedAt = source.completed_at ?? source.completedAt;
    const sourceMonth = companyInvoiceMonth(completedAt);
    if (!sourceMonth) return fail('invoice_completion_time_missing');
    if (sourceMonth !== month) continue;
    const legId = legs ? (source.leg_id ?? source.legId) : null;
    if (legs && !/^[A-Za-z0-9_-]{1,160}$/.test(legId || '')) return fail('invoice_source_id_invalid');
    if (seen.has(legId)) return fail('invoice_source_duplicate');
    seen.add(legId);
    const buyer = policy.buyer_snapshot;
    if (!buyer?.legal_name || !buyer.address_line1 || !buyer.postal_code || !buyer.city || !/^[A-Z]{2}$/.test(buyer.country_code || '')) return fail('invoice_buyer_snapshot_missing');
    let ownership;
    try { ownership = await readSourceOwnership({ scope, bookingId, legId, canonicalVersion: record._canonical_version }); }
    catch { return fail('invoice_source_ownership_unavailable'); }
    if (ownership?.verified !== true || ownership?.state !== 'unclaimed') return fail('invoice_source_ownership_unverified');
    const derived = deriveInvoiceContext(record, { source_leg_id: legId });
    if (!derived?.ok) return fail(derived?.error || 'invoice_amount_unreliable');
    const totals = derived.context?.totals;
    const net = cents(totals?.subtotal_ex_vat), vat = cents(totals?.vat_amount), gross = cents(totals?.total_incl_vat);
    if (net == null || vat == null || gross == null || gross <= 0 || net + vat !== gross ||
        typeof totals?.vat_rate_percent !== 'number' || !Number.isFinite(totals.vat_rate_percent)) return fail('invoice_amount_unreliable');
    const bytes = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(stable(buyer)));
    const buyerKey = [...new Uint8Array(bytes)].map(byte => byte.toString(16).padStart(2, '0')).join('');
    // Multi-leg records must supply their own route. Never label a return leg
    // with the parent's outbound route or stringify a coordinate object.
    const singleSource = !legs || legs.length === 1;
    const from = routeLabel(source.from) || (singleSource ? routeLabel(record.booking?.from ?? record.from) : '');
    const to = routeLabel(source.to) || (singleSource ? routeLabel(record.booking?.to ?? record.to) : '');
    lines.push({ ...scope, booking_id: bookingId, leg_id: legId, canonical_version: record._canonical_version,
      ...(from ? { from } : {}), ...(to ? { to } : {}),
      billing_policy: structuredClone(policy), status: 'completed', completed_at: completedAt, already_invoiced: false,
      currency: derived.context.currency, buyer_identity_key: buyerKey,
      net_cents: net, vat_cents: vat, gross_cents: gross, vat_rate_percent: totals.vat_rate_percent });
  }
  return { ok: true, lines };
}
