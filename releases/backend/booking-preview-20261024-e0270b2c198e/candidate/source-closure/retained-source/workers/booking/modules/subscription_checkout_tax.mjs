import { subscriptionInvoiceParties } from './subscription_invoice_parties.mjs';
// Forward-only, server-reviewed subscription tax decisions. No default rate,
// client-supplied treatment, historical inference, VIES request or activation.
const EU = new Set('AT BE BG HR CY CZ DK EE FI FR DE GR HU IE IT LV LT LU MT NL PL PT RO SK SI ES SE'.split(' '));
const scopePart = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,80}$/.test(value) ? value : null;
const plain = value => value && typeof value === 'object' && !Array.isArray(value);
const string = (value, max = 160) => typeof value === 'string' && value.length > 0 && value.length <= max &&
  value === value.trim() && !/[\u0000-\u001f\u007f-\u009f\u2028\u2029]/.test(value) ? value : null;
const cents = value => Number.isSafeInteger(value) && value >= 0;
const iso = value => typeof value === 'string' && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(value) &&
  Number.isFinite(Date.parse(value)) && new Date(value).toISOString() === value;
const failure = error => ({ ok: false, enabled: true, error: `subscription_tax_${error}` });

export function subscriptionTaxDecisionKey(scope) {
  const tenant = scopePart(scope?.tenant_id), company = scopePart(scope?.company_id);
  return tenant && company ? `tenant:${tenant}:company:${company}:subscription:tax_decision:v1` : null;
}

export function recurringTaxSnapshotKey(subscriptionId, snapshotId) {
  return typeof subscriptionId === 'string' && /^sub_[A-Za-z0-9_]{1,120}$/.test(subscriptionId) &&
    typeof snapshotId === 'string' && /^tax_[a-f0-9]{32}$/.test(snapshotId)
    ? `subscription:tax_snapshot:${subscriptionId}:${snapshotId}:v1` : null;
}

export function validateSubscriptionTaxDecision(env, scope, decision, nowMs = Date.now()) {
  const policy = string(env?.FLUXIDI_SUBSCRIPTION_TAX_POLICY_VERSION, 80);
  if (!policy) return failure('policy_invalid');
  const seller = string(env?.FLUXIDI_SUBSCRIPTION_TAX_SELLER_ID, 80);
  if (!seller) return failure('seller_unconfigured');
  if (!subscriptionTaxDecisionKey(scope)) return failure('scope_invalid');
  if (!plain(decision) || decision.version !== 'reviewed_subscription_tax_v1' ||
    decision.policy_version !== policy || decision.tenant_id !== scope.tenant_id || decision.company_id !== scope.company_id ||
    decision.seller_id !== seller || !Number.isSafeInteger(decision.revision) || decision.revision < 1 ||
    !string(decision.review_reference) || !string(decision.evidence_reference) ||
    !iso(decision.effective_from) || !iso(decision.valid_until) || !Number.isFinite(nowMs) ||
    Date.parse(decision.effective_from) > nowMs || Date.parse(decision.valid_until) <= nowMs ||
    Date.parse(decision.effective_from) >= Date.parse(decision.valid_until)) return failure('decision_unproved');
  if (!EU.has(decision.seller_country) || !EU.has(decision.customer_country) || decision.customer_type !== 'business')
    return failure('country_or_status_unreviewed');
  if (!['exclusive', 'inclusive'].includes(decision.price_basis) ||
    !Number.isSafeInteger(decision.vat_rate_bps) || decision.vat_rate_bps < 0 || decision.vat_rate_bps > 10000)
    return failure('rate_or_price_basis_invalid');
  if (decision.treatment === 'eu_b2b_reverse_charge') {
    if (decision.customer_country === decision.seller_country || decision.vat_rate_bps !== 0 ||
      decision.customer_vat_status !== 'verified_valid' || !string(decision.vat_verification_reference))
      return failure('reverse_charge_unproved');
  } else if (decision.treatment === 'reviewed_taxable') {
    if (decision.vat_rate_bps === 0 || !['verified_valid', 'reviewed_not_registered'].includes(decision.customer_vat_status))
      return failure('taxable_status_unproved');
  } else if (decision.treatment === 'reviewed_zero_rate') {
    if (decision.vat_rate_bps !== 0 || !string(decision.zero_rate_reference) ||
      (decision.customer_vat_status !== undefined && !['verified_valid', 'reviewed_not_registered', 'reviewed_zero_rate'].includes(decision.customer_vat_status)))
      return failure('zero_rate_unproved');
  } else return failure('treatment_unreviewed');
  const parties = subscriptionInvoiceParties(decision);
  if (!parties.ok) return failure('invoice_parties_unproved');
  // Store only the reviewed fiscal decision, never arbitrary profile/bank data.
  return { ok: true, enabled: true, decision: {
    version: decision.version, policy_version: policy, seller_id: seller,
    ...(parties.invoice_parties_json ? { invoice_parties_json: parties.invoice_parties_json } : {}),
    tenant_id: scope.tenant_id, company_id: scope.company_id, revision: decision.revision,
    seller_country: decision.seller_country, customer_country: decision.customer_country, customer_type: 'business',
    price_basis: decision.price_basis, vat_rate_bps: decision.vat_rate_bps, treatment: decision.treatment,
    customer_vat_status: decision.customer_vat_status || 'reviewed_zero_rate',
    review_reference: decision.review_reference, evidence_reference: decision.evidence_reference,
    effective_from: decision.effective_from, valid_until: decision.valid_until,
    ...(decision.treatment === 'eu_b2b_reverse_charge' ? { vat_verification_reference: decision.vat_verification_reference } : {}),
    ...(decision.treatment === 'reviewed_zero_rate' ? { zero_rate_reference: decision.zero_rate_reference } : {}),
  } };
}

export async function loadSubscriptionTaxDecision(env, scope, nowMs = Date.now()) {
  // Absence preserves the existing billing contract. A configured but invalid
  // policy never silently falls back to legacy charging.
  if (env?.FLUXIDI_SUBSCRIPTION_TAX_POLICY_VERSION === undefined || env?.FLUXIDI_SUBSCRIPTION_TAX_POLICY_VERSION === '')
    return { ok: true, enabled: false };
  const key = subscriptionTaxDecisionKey(scope);
  if (!key || !env?.BOOKING_KV?.get) return failure('storage_unavailable');
  let decision;
  try {
    const raw = await env.BOOKING_KV.get(key);
    if (typeof raw !== 'string' || raw.length > 8192) return failure('decision_unproved');
    decision = JSON.parse(raw);
  } catch (_) { return failure('storage_unavailable'); }
  return validateSubscriptionTaxDecision(env, scope, decision, nowMs);
}

export function subscriptionCheckoutTax(context, { amount_cents, currency, kind, activation_id,
  provider_subscription_id, snapshot_id, nowMs = Date.now() } = {}) {
  if (context?.ok !== true) return context || failure('decision_unproved');
  if (!context.enabled) return { ok: true, enabled: false, amount_cents };
  const candidate = context.decision;
  if (!cents(amount_cents) || amount_cents === 0 || !/^[A-Z]{3}$/.test(currency || '') || !plain(candidate) ||
    !Number.isFinite(nowMs) || Math.abs(nowMs) > 8640000000000000)
    return failure('amount_or_decision_invalid');
  const reviewed = validateSubscriptionTaxDecision({ FLUXIDI_SUBSCRIPTION_TAX_POLICY_VERSION: candidate.policy_version,
    FLUXIDI_SUBSCRIPTION_TAX_SELLER_ID: candidate.seller_id }, candidate, candidate, nowMs);
  if (!reviewed.ok) return reviewed;
  const decision = reviewed.decision;
  const recurring = kind === 'subscription_recurring';
  if (!['subscription_initial', 'subscription_addon', 'subscription_recurring'].includes(kind) ||
    (recurring ? !recurringTaxSnapshotKey(provider_subscription_id || 'sub_pending', snapshot_id)
      : !string(activation_id, 160) || !/^[A-Za-z0-9_-]{1,160}$/.test(activation_id))) return failure('correlation_invalid');
  const amount = BigInt(amount_cents), rate = BigInt(decision.vat_rate_bps);
  const net = decision.price_basis === 'exclusive' ? amount : (amount * 10000n + (10000n + rate) / 2n) / (10000n + rate);
  const vat = decision.price_basis === 'exclusive' ? (net * rate + 5000n) / 10000n : amount - net;
  const gross = net + vat;
  if ([net, vat, gross].some(value => value > BigInt(Number.MAX_SAFE_INTEGER))) return failure('amount_overflow');
  const reference = recurring ? `subscription-recurring:${snapshot_id}` : `subscription-checkout:${activation_id}`;
  const invoiceSnapshot = { ...decision, version: 'subscription_checkout_tax_v1',
    kind, currency, contract_amount_cents: amount_cents, ex_vat_cents: Number(net), vat_cents: Number(vat),
    gross_cents: Number(gross), recorded_at: new Date(nowMs).toISOString(), reference,
    ...(recurring ? { snapshot_id, ...(provider_subscription_id ? { provider_subscription_id } : {}) } : { activation_id }) };
  const basis = { version: 'checkout_net_vat_v1', derivation_version: decision.policy_version,
    review_reference: decision.review_reference, reference, tenant_id: decision.tenant_id, company_id: decision.company_id,
    kind, currency, gross_cents: Number(gross), ex_vat_cents: Number(net), vat_cents: Number(vat),
    ...(recurring ? { ...(provider_subscription_id ? { provider_subscription_id } : {}) } : { activation_id }) };
  return { ok: true, enabled: true, amount_cents: Number(gross), invoice_snapshot: invoiceSnapshot, affiliate_revenue_basis: basis };
}

export function subscriptionTaxFields(record) {
  const invoice = record?.subscription_tax_snapshot, basis = record?.affiliate_revenue_basis;
  if (invoice === undefined && basis === undefined) return {};
  if (!plain(invoice) || invoice.version !== 'subscription_checkout_tax_v1' || !plain(basis) || basis.version !== 'checkout_net_vat_v1' ||
    !iso(invoice.recorded_at) || !subscriptionTaxDecisionKey(record) || !/^[A-Z]{3}$/.test(record.currency || '') ||
    !cents(invoice.ex_vat_cents) || !cents(invoice.vat_cents) || !cents(invoice.gross_cents) ||
    invoice.ex_vat_cents + invoice.vat_cents !== invoice.gross_cents ||
    invoice.tenant_id !== record.tenant_id || invoice.company_id !== record.company_id ||
    invoice.currency !== record.currency || invoice.gross_cents !== record.expected_amount_cents ||
    basis.tenant_id !== invoice.tenant_id || basis.company_id !== invoice.company_id || basis.currency !== invoice.currency ||
    basis.kind !== invoice.kind || basis.reference !== invoice.reference || basis.derivation_version !== invoice.policy_version ||
    basis.review_reference !== invoice.review_reference || basis.ex_vat_cents !== invoice.ex_vat_cents ||
    basis.vat_cents !== invoice.vat_cents || basis.gross_cents !== invoice.gross_cents ||
    (invoice.kind === 'subscription_recurring' ? basis.provider_subscription_id !== record.provider_subscription_id ||
      invoice.provider_subscription_id !== record.provider_subscription_id || !recurringTaxSnapshotKey(record.provider_subscription_id, invoice.snapshot_id)
      : invoice.activation_id !== record.activation_id || basis.activation_id !== record.activation_id))
    throw Error('subscription_tax_snapshot_conflict');
  // Re-derive at the historical recording time, not today's mutable decision.
  // Corrupt stored rates/totals and arbitrary extra personal fields cannot pass.
  const decision = { ...invoice, version: 'reviewed_subscription_tax_v1' };
  const regenerated = subscriptionCheckoutTax({ ok: true, enabled: true, decision }, {
    amount_cents: invoice.contract_amount_cents, currency: invoice.currency, kind: invoice.kind,
    activation_id: invoice.activation_id, provider_subscription_id: invoice.provider_subscription_id,
    snapshot_id: invoice.snapshot_id, nowMs: Date.parse(invoice.recorded_at),
  });
  if (!regenerated.ok || Object.entries(regenerated.invoice_snapshot).some(([key, value]) => invoice[key] !== value) ||
    Object.entries(regenerated.affiliate_revenue_basis).some(([key, value]) => basis[key] !== value))
    throw Error('subscription_tax_snapshot_conflict');
  return { subscription_tax_snapshot: regenerated.invoice_snapshot, affiliate_revenue_basis: regenerated.affiliate_revenue_basis };
}

export async function saveRecurringTaxSnapshot(env, subscriptionId, tax) {
  if (!tax?.enabled) return;
  const key = recurringTaxSnapshotKey(subscriptionId, tax.invoice_snapshot?.snapshot_id);
  if (!key || !env?.BOOKING_KV?.get || !env?.BOOKING_KV?.put) throw Error('subscription_tax_storage_unavailable');
  if (tax.provider_customer_id !== undefined && !/^cst_[A-Za-z0-9_]+$/.test(tax.provider_customer_id || ''))
    throw Error('subscription_tax_customer_invalid');
  const record = { ...(tax.provider_customer_id ? { provider_customer_id: tax.provider_customer_id } : {}),
    tenant_id: tax.invoice_snapshot.tenant_id, company_id: tax.invoice_snapshot.company_id,
    currency: tax.invoice_snapshot.currency, expected_amount_cents: tax.amount_cents, provider_subscription_id: subscriptionId,
    subscription_tax_snapshot: { ...tax.invoice_snapshot, provider_subscription_id: subscriptionId },
    affiliate_revenue_basis: { ...tax.affiliate_revenue_basis, provider_subscription_id: subscriptionId } };
  const fields = subscriptionTaxFields(record), serialized = JSON.stringify({ ...record, ...fields });
  const existing = await env.BOOKING_KV.get(key);
  if (existing !== null && existing !== undefined && existing !== serialized) throw Error('subscription_tax_snapshot_locked');
  if (existing === null || existing === undefined) await env.BOOKING_KV.put(key, serialized);
}

export async function loadRecurringTaxSnapshot(env, index, subscriptionId, snapshotId) {
  const key = recurringTaxSnapshotKey(subscriptionId, snapshotId);
  if (!key) return null;
  try {
    const raw = await env.BOOKING_KV.get(key);
    if (typeof raw !== 'string' || raw.length > 8192) return null;
    const record = JSON.parse(raw);
    if (record.tenant_id !== index?.tenant_id || record.company_id !== index?.company_id || record.provider_subscription_id !== subscriptionId) return null;
    return { ...record, ...subscriptionTaxFields(record) };
  } catch (_) { return null; }
}

// Public checkout display evidence. Private decision/review/seller identifiers
// remain in server storage. Input is the validated producer or stored snapshot.
export function publicSubscriptionPaymentConfirmation(snapshot, { provider_payment_id, product_code, quantity } = {}) {
  if (!plain(snapshot) || snapshot.version !== 'subscription_checkout_tax_v1' ||
    !['subscription_initial', 'subscription_addon'].includes(snapshot.kind) ||
    !string(provider_payment_id) || !/^tr_[A-Za-z0-9_]+$/.test(provider_payment_id) ||
    !['fluxidi_pro', 'standard', 'smart', 'extra_vehicle', 'extra_driver', 'pdf_500', 'pdf_1000', 'pdf_5000'].includes(product_code) ||
    quantity !== 1 || (snapshot.kind === 'subscription_initial') !== (['fluxidi_pro','standard','smart'].includes(product_code)))
    throw Error('subscription_payment_confirmation_invalid');
  return { version: 'subscription_payment_confirmation_v1', tenant_id: snapshot.tenant_id,
    company_id: snapshot.company_id, activation_id: snapshot.activation_id, provider_payment_id,
    product_code, quantity, currency: snapshot.currency, ex_vat_cents: snapshot.ex_vat_cents,
    vat_cents: snapshot.vat_cents, gross_cents: snapshot.gross_cents, treatment: snapshot.treatment,
    recorded_at: snapshot.recorded_at, valid_until: snapshot.valid_until };
}
