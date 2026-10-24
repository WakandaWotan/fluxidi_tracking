// Internal authority, stored in a company-specific instance of the existing
// FounderSlots binding. No public route or TTL-based release of uncertain money.
const clean = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,80}$/.test(value) ? value : '';
const activation = value => typeof value === 'string' && /^act_[A-Za-z0-9_-]{1,100}$/.test(value) ? value : '';
const key = 'base_checkout_claim:v1';

export async function subscriptionCheckoutClaim(storage, body) {
  const tenant = clean(body?.tenant_id), company = clean(body?.company_id);
  const id = activation(body?.activation_id);
  if (!tenant || !company || !id) return { ok: false, error: 'checkout_claim_scope_invalid' };
  return storage.transaction(async txn => {
    const existing = await txn.get(key);
    if (existing && (existing.tenant_id !== tenant || existing.company_id !== company))
      return { ok: false, error: 'checkout_claim_scope_conflict' };
    if (body.action === 'checkout_read') return {ok:true,record:existing||null};
    if (body.action === 'checkout_claim') {
      if (existing) return { ok: true, acquired: false, record: existing };
      const record = { version: 1, tenant_id: tenant, company_id: company, activation_id: id,
        state: 'creating', created_at: new Date().toISOString() };
      await txn.put(key, record);
      return { ok: true, acquired: true, record };
    }
    if (!existing || existing.activation_id !== id)
      return { ok: false, error: 'checkout_claim_owner_changed' };
    if (body.action === 'checkout_prepare') {
      const prepared = body.prepared;
      if (!prepared || prepared.pending?.tenant_id !== tenant || prepared.pending?.company_id !== company ||
          prepared.pending?.activation_id !== id || !Number.isSafeInteger(prepared.pending.expected_amount_cents) ||
          prepared.pending.expected_amount_cents <= 0 || !/^[a-f0-9]{64}$/.test(prepared.credentials_hash || '') ||
          typeof prepared.redirect_url !== 'string' || typeof prepared.base_url !== 'string')
        return { ok: false, error: 'checkout_claim_prepare_invalid' };
      if (existing.prepared) return JSON.stringify(existing.prepared) === JSON.stringify(prepared)
        ? { ok: true, record: existing } : { ok: false, error: 'checkout_claim_prepare_locked' };
      const record = { ...existing, state: 'prepared', prepared_at: new Date().toISOString(), prepared: structuredClone(prepared) };
      await txn.put(key, record);
      return { ok: true, record };
    }
    if (body.action === 'checkout_record') {
      const pending = body.pending;
      if (!pending || pending.tenant_id !== tenant || pending.company_id !== company ||
          pending.activation_id !== id || !/^tr_[A-Za-z0-9]+$/.test(pending.provider_payment_id || '') ||
          !Number.isSafeInteger(pending.expected_amount_cents) || pending.expected_amount_cents <= 0)
        return { ok: false, error: 'checkout_claim_record_invalid' };
      if (!existing.prepared?.pending) return { ok: false, error: 'checkout_claim_prepare_required' };
      // Provider creation may add its payment ID, but cannot change the
      // contract that was durably prepared before that provider request.
      const contractFields=['plan_code','market','currency','normal_price_cents','founder_price_cents',
        'expected_amount_cents','locked_extra_vehicle_unit_cents','locked_extra_driver_unit_cents',
        'provider','provider_customer_id','founder_reserved','founder_slot_number',
        'subscription_tax_snapshot','affiliate_revenue_basis','subscription_paid_contract_snapshot'];
      if(contractFields.some(field=>JSON.stringify(pending[field])!==JSON.stringify(existing.prepared.pending[field])))
        return { ok: false, error: 'checkout_claim_contract_changed' };
      if (existing.pending) return JSON.stringify(existing.pending) === JSON.stringify(pending)
        ? { ok: true, record: existing } : { ok: false, error: 'checkout_claim_record_locked' };
      const record = { ...existing, state: 'pending', pending: structuredClone(pending) };
      await txn.put(key, record);
      return { ok: true, record };
    }
    if (body.action === 'checkout_release_before_payment') {
      if (existing.pending || existing.prepared) return { ok: false, error: 'checkout_claim_payment_exists' };
      await txn.delete(key);
      return { ok: true, released: true };
    }
    if (body.action === 'checkout_release_terminal') {
      if (!existing.pending || existing.pending.provider_payment_id !== body.provider_payment_id ||
          !['canceled', 'expired', 'failed'].includes(body.provider_status))
        return { ok: false, error: 'checkout_claim_terminal_proof_invalid' };
      await txn.delete(key);
      return { ok: true, released: true };
    }
    if (body.action === 'checkout_release_applied') {
      if (!existing.pending || existing.pending.provider_payment_id !== body.provider_payment_id ||
          body.canonical_applied !== true || body.subscription_cancelled !== true)
        return { ok: false, error: 'checkout_claim_applied_proof_invalid' };
      await txn.delete(key);
      return { ok: true, released: true };
    }
    return { ok: false, error: 'checkout_claim_action_invalid' };
  });
}

export async function subscriptionCheckoutClaimOperation(env, scope, action, activationId, fields = {}) {
  const binding = env?.FLUXIDI_SUBSCRIPTION_FOUNDER_SLOTS;
  if (!binding || !clean(scope?.tenant_id) || !clean(scope?.company_id))
    throw new Error('checkout_claim_authority_missing');
  const name = `subscription:checkout:${JSON.stringify([scope.tenant_id, scope.company_id])}`;
  const response = await binding.get(binding.idFromName(name)).fetch('https://founder-slots/checkout', {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ ...fields, action, ...scope, activation_id: activationId }),
  });
  const result = await response.json();
  if (!response.ok || result.ok !== true) throw new Error(result.error || 'checkout_claim_failed');
  return result;
}

// Strict provider identity checks before issuing a saved URL or clearing a claim.
export function verifiedBaseCheckoutPayment(pending, payment, scope, nowMs = Date.now()) {
  const meta = payment?.metadata;
  if (!pending || pending.tenant_id !== scope.tenant_id || pending.company_id !== scope.company_id ||
      payment?.id !== pending.provider_payment_id || payment?.customerId !== pending.provider_customer_id ||
      meta?.purpose !== 'fluxidi_subscription' || meta?.activation_id !== pending.activation_id ||
      meta?.tenant_id !== scope.tenant_id || meta?.company_id !== scope.company_id ||
      meta?.plan_code !== pending.plan_code || meta?.market !== pending.market ||
      payment?.amount?.currency !== pending.currency ||
      !/^\d+\.\d{2}$/.test(payment?.amount?.value || '') ||
      !Number.isSafeInteger(pending.expected_amount_cents) ||
      BigInt(payment.amount.value.replace('.', '')) !== BigInt(pending.expected_amount_cents))
    return { ok: false, error: 'checkout_pending_payment_conflict' };
  const status = payment.status;
  if (status === 'paid') return { ok: true, paid: true, status };
  if (['canceled', 'expired', 'failed'].includes(status)) return { ok: true, terminal: true, status };
  if (!['open', 'pending'].includes(status)) return { ok: false, error: 'checkout_pending_payment_not_open' };
  if (pending.status !== 'pending' || !Number.isFinite(nowMs) ||
      !Number.isFinite(Date.parse(pending.expires_at)) || Date.parse(pending.expires_at) <= nowMs ||
      !pending.subscription_tax_snapshot || Date.parse(pending.subscription_tax_snapshot.valid_until) <= nowMs ||
      !Number.isFinite(Date.parse(pending.subscription_tax_snapshot.valid_until)))
    return { ok: false, error: 'checkout_pending_proof_expired' };
  try {
    const url = new URL(payment?._links?.checkout?.href);
    if (url.protocol !== 'https:' || !url.hostname || url.username || url.password) throw Error();
    return { ok: true, terminal: false, checkout_url: url.href };
  } catch { return { ok: false, error: 'checkout_pending_url_invalid' }; }
}
