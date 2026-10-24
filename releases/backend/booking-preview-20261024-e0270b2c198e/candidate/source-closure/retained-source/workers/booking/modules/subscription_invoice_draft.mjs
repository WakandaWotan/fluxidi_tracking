import { subscriptionTaxFields } from './subscription_checkout_tax.mjs';
import { FLUXIDI_SELLER_ID } from './subscription_invoice_parties.mjs';
const fail = reason => ({ ok: false, error: `subscription_invoice_${reason}` });
const iso = value => typeof value === 'string' && Number.isFinite(Date.parse(value)) && new Date(value).toISOString() === value;
const scopePart = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,80}$/.test(value);
// Private draft only: no invoice number, invoice issuance, provider call or Peppol send.
export function buildSubscriptionInvoiceDraft(payment, evidence, { providerFetched, configuredMode } = {}) {
  if (providerFetched !== true || !/^tr_[A-Za-z0-9_]{1,120}$/.test(payment?.id || '') || payment.status !== 'paid' ||
      !['live', 'test'].includes(configuredMode) || payment.mode !== configuredMode || !iso(payment.paidAt)) return fail('payment_unproved');
  let fields;
  try { fields = subscriptionTaxFields(evidence); } catch (_) { return fail('fiscal_evidence_unproved'); }
  const snapshot = fields.subscription_tax_snapshot;
  if (!snapshot || snapshot.seller_id !== FLUXIDI_SELLER_ID || !snapshot.invoice_parties_json ||
      !scopePart(evidence.tenant_id) || !scopePart(evidence.company_id)) return fail('parties_unproved');
  const meta = payment.metadata;
  if (!meta || meta.tenant_id !== evidence.tenant_id || meta.company_id !== evidence.company_id ||
      payment.customerId !== evidence.provider_customer_id || !/^cst_[A-Za-z0-9_]+$/.test(evidence.provider_customer_id || '') ||
      (snapshot.kind === 'subscription_recurring'
        ? meta.purpose !== 'fluxidi_subscription_recurring' || meta.kind !== 'recurring' ||
          payment.subscriptionId !== evidence.provider_subscription_id || meta.fluxidi_tax_snapshot_id !== snapshot.snapshot_id
        : meta.purpose !== 'fluxidi_subscription' || meta.activation_id !== evidence.activation_id ||
          evidence.provider_payment_id !== payment.id || (snapshot.kind === 'subscription_addon') !== (meta.kind === 'addon')))
    return fail('payment_scope_conflict');
  const raw = payment.amount?.value;
  if (typeof raw !== 'string' || !/^\d{1,12}\.\d{2}$/.test(raw) || payment.amount.currency !== snapshot.currency) return fail('amount_conflict');
  const [whole, fraction] = raw.split('.');
  if (BigInt(whole) * 100n + BigInt(fraction) !== BigInt(snapshot.gross_cents)) return fail('amount_conflict');
  if (Date.parse(payment.paidAt) < Date.parse(snapshot.recorded_at) || Date.parse(payment.paidAt) >= Date.parse(snapshot.valid_until))
    return fail('payment_outside_review');
  const parties = JSON.parse(snapshot.invoice_parties_json);
  return { ok: true, draft: { version: 'subscription_invoice_draft_v1', state: 'awaiting_issue',
    tenant_id: evidence.tenant_id, company_id: evidence.company_id, seller_id: snapshot.seller_id,
    payment_id: payment.id, provider_customer_id: payment.customerId, provider: 'mollie', mode: configuredMode,
    paid_at: payment.paidAt, fiscal_reference: snapshot.reference, currency: snapshot.currency,
    ex_vat_cents: snapshot.ex_vat_cents, vat_cents: snapshot.vat_cents, gross_cents: snapshot.gross_cents,
    treatment: snapshot.treatment, vat_rate_bps: snapshot.vat_rate_bps, parties,
    review_reference: snapshot.review_reference, invoice_number: null } };
}
export async function storeSubscriptionInvoiceDraft(storage, draft) {
  if (draft?.version !== 'subscription_invoice_draft_v1' || draft.state !== 'awaiting_issue' || draft.invoice_number !== null ||
      !scopePart(draft.tenant_id) || !scopePart(draft.company_id) || !/^tr_[A-Za-z0-9_]{1,120}$/.test(draft.payment_id || '')) return fail('draft_invalid');
  return storage.transaction(async txn => {
    const owner = await txn.get('invoice_draft_scope:v1');
    const scope = JSON.stringify([draft.tenant_id, draft.company_id]);
    if (owner && owner !== scope) return fail('draft_scope_conflict');
    const key = `invoice_draft:${draft.payment_id}:v1`, value = JSON.stringify(draft), old = await txn.get(key);
    if (old && old !== value) return fail('draft_locked');
    if (old) return { ok: true, replay: true };
    await txn.put('invoice_draft_scope:v1', scope); await txn.put(key, value);
    return { ok: true, replay: false };
  });
}
export async function captureSubscriptionInvoiceDraftSafely(env, { payment, providerFetched, configuredMode, loadPending, loadAddonPending, loadProviderIndex } = {}) {
  if (!env?.FLUXIDI_SUBSCRIPTION_TAX_POLICY_VERSION) return { ok: true, skipped: true };
  if (payment?.status !== 'paid') return { ok: true, skipped: true };
  try {
    const meta = payment.metadata || {};
    let evidence;
    if (meta.purpose === 'fluxidi_subscription_recurring' && meta.kind === 'recurring') {
      const index = await loadProviderIndex(payment.subscriptionId, meta.fluxidi_tax_snapshot_id); evidence = index?.ok ? index.record : null;
    } else if (meta.purpose === 'fluxidi_subscription' && meta.activation_id) {
      evidence = await (meta.kind === 'addon' ? loadAddonPending : loadPending)(meta.activation_id);
    } else return { ok: true, skipped: true };
    const built = buildSubscriptionInvoiceDraft(payment, evidence, { providerFetched, configuredMode });
    if (!built.ok) return { ok: true, held_review: true, reason: built.error };
    const binding = env.FLUXIDI_SUBSCRIPTION_FOUNDER_SLOTS;
    if (!binding?.idFromName || !binding?.get) return fail('draft_storage_unavailable');
    const id = binding.idFromName(`subscription:invoice-drafts:${JSON.stringify([built.draft.tenant_id, built.draft.company_id])}`);
    const reply = await binding.get(id).fetch('https://subscription-internal/invoice-draft', {
      method: 'POST', body: JSON.stringify({ action: 'invoice_draft_capture', draft: built.draft }) });
    const result = await reply.json(); return result?.ok ? result : fail('draft_storage_unavailable');
  } catch (_) { return fail('draft_storage_unavailable'); }
}
