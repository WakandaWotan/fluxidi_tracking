import { affiliateOperation } from './affiliate_ledger.mjs';
import { subscriptionTaxFields } from './subscription_checkout_tax.mjs';

const text = (value, max = 160) => typeof value === 'string' ? value.trim().slice(0, max) : '';
export function affiliateAmountCents(amount) {
  const value = text(amount, 32);
  if (!/^\d{1,12}\.\d{2}$/.test(value)) return null;
  const [whole, fraction] = value.split('.'), cents = Number(whole) * 100 + Number(fraction);
  return Number.isSafeInteger(cents) && cents >= 0 ? cents : null;
}

// Only private checkout evidence under an explicitly reviewed server policy.
// Historical prices and the current company profile are never VAT evidence.
export function verifiedForwardAffiliateBasis(env, evidence, receipt) {
  let basis = evidence?.affiliate_revenue_basis;
  if (evidence?.subscription_tax_snapshot !== undefined) {
    try {
      const fields = subscriptionTaxFields(evidence), snapshot = fields.subscription_tax_snapshot;
      const paidAt = Date.parse(receipt.paid_at);
      if (!Number.isFinite(paidAt) || paidAt < Date.parse(snapshot.recorded_at) || paidAt >= Date.parse(snapshot.valid_until)) return null;
      basis = fields.affiliate_revenue_basis;
    } catch (_) { return null; }
  }
  const version = text(env?.AFFILIATE_CHECKOUT_BASIS_POLICY_VERSION, 80);
  if (!version || !basis || basis.version !== 'checkout_net_vat_v1' || basis.derivation_version !== version ||
    !text(basis.review_reference) || !text(basis.reference) || basis.tenant_id !== receipt.tenant_id || basis.company_id !== receipt.company_id ||
    basis.kind !== receipt.kind || basis.currency !== receipt.currency || basis.gross_cents !== receipt.gross_cents ||
    !Number.isSafeInteger(basis.ex_vat_cents) || basis.ex_vat_cents < 0 || !Number.isSafeInteger(basis.vat_cents) || basis.vat_cents < 0 ||
    basis.ex_vat_cents + basis.vat_cents !== basis.gross_cents ||
    (receipt.kind === 'subscription_recurring' ? !text(receipt.provider_subscription_id).startsWith('sub_') || basis.provider_subscription_id !== receipt.provider_subscription_id
      : !text(receipt.activation_id) || basis.activation_id !== receipt.activation_id)) return null;
  return { ...basis, reference: text(basis.reference), review_reference: text(basis.review_reference), derivation_version: version };
}

// Only server-owned webhook capture or authenticated recovery, after fetching
// from its own provider account, may call this. No public body, current profile
// price, or webhook status is proof.
export async function captureVerifiedAffiliatePayment(env, { payment, providerFetched, configuredMode,
  loadPending, loadAddonPending, loadProviderIndex, requiredScope, recoveryActor } = {}) {
  if (env?.AFFILIATE_PROGRAM_ENABLED !== '1') return { ok: true, skipped: true, reason: 'affiliate_program_not_enabled' };
  if (providerFetched !== true || !payment?.id) return { ok: false, error: 'affiliate_provider_evidence_required' };
  const metadata = payment.metadata && typeof payment.metadata === 'object' && !Array.isArray(payment.metadata) ? payment.metadata : {};
  const purpose = text(metadata.purpose), kind = text(metadata.kind), activationId = text(metadata.activation_id || metadata.activationId);
  let type, evidence;
  if (purpose === 'fluxidi_subscription_recurring' && kind === 'recurring' && text(payment.subscriptionId).startsWith('sub_')) {
    type = 'subscription_recurring';
    // The provider copies subscription metadata to each generated payment.
    // Its immutable snapshot pointer must survive later subscription updates.
    const snapshotId = metadata.fluxidi_tax_snapshot_id;
    const index = await loadProviderIndex(payment.subscriptionId, snapshotId);
    evidence = index?.ok ? index.record : null;
  } else if (purpose === 'fluxidi_subscription' && activationId) {
    type = kind === 'addon' ? 'subscription_addon' : 'subscription_initial';
    evidence = kind === 'addon' ? await loadAddonPending(activationId) : await loadPending(activationId);
  } else return requiredScope ? { ok: false, error: 'affiliate_payment_kind_refused', _http_status: 400 }
    : { ok: true, skipped: true, reason: 'affiliate_payment_kind_excluded' };
  const gross = affiliateAmountCents(payment.amount?.value), currency = text(payment.amount?.currency, 3).toUpperCase();
  const refunded = payment.amountRefunded?.value === undefined ? 0 : affiliateAmountCents(payment.amountRefunded.value);
  const chargedBack = payment.amountChargedBack?.value === undefined ? 0 : affiliateAmountCents(payment.amountChargedBack.value);
  if (gross === null || refunded === null || chargedBack === null || !/^[A-Z]{3}$/.test(currency) || refunded > gross || chargedBack > gross ||
    (payment.amountRefunded?.currency && payment.amountRefunded.currency !== currency) ||
    (payment.amountChargedBack?.currency && payment.amountChargedBack.currency !== currency)) return { ok: false, error: 'affiliate_provider_amount_invalid' };
  const tenant = text(evidence?.tenant_id, 80), company = text(evidence?.company_id, 80);
  const pendingKindMatches = type === 'subscription_recurring' || !evidence?.kind ||
    (type === 'subscription_addon' ? evidence.kind === 'addon_activation' : evidence.kind !== 'addon_activation');
  const scopeVerified = pendingKindMatches && !!tenant && !!company && (!metadata.tenant_id || metadata.tenant_id === tenant) &&
    (!metadata.company_id || metadata.company_id === company) &&
    (!evidence.provider_payment_id || evidence.provider_payment_id === payment.id) &&
    (evidence.expected_amount_cents === undefined || evidence.expected_amount_cents === gross) &&
    (!evidence.currency || evidence.currency === currency);
  if (requiredScope && (!scopeVerified || tenant !== requiredScope.tenant_id || company !== requiredScope.company_id)) {
    return { ok: false, error: 'affiliate_payment_scope_conflict', _http_status: 409 };
  }
  const providerMode = text(payment.mode, 8);
  const mode = providerMode === configuredMode && ['live', 'test'].includes(providerMode) ? providerMode : 'unknown';
  const receipt = { verified: true, provider: 'mollie', payment_id: text(payment.id, 128),
    kind: type, tenant_id: scopeVerified ? tenant : 'unresolved', company_id: scopeVerified ? company : text(payment.id, 128),
    scope_verified: scopeVerified, currency, gross_cents: gross, refunded_gross_cents: refunded, charged_back_gross_cents: chargedBack,
    mode, payment_status: text(payment.status, 40).toLowerCase(),
    paid_at: text(payment.paidAt, 48), captured_at: new Date().toISOString(),
    activation_id: activationId || null, provider_subscription_id: text(payment.subscriptionId, 128) || null };
  if (scopeVerified) receipt.forward_basis = verifiedForwardAffiliateBasis(env, evidence, receipt);
  // Receipt + its held/accrued result are durable in one transaction. Missing
  // invoice net/tax proof remains held_review; caller can still activate billing.
  // Explicit recovery retains its authenticated actor until the SQL mutation;
  // only the existing provider-fetched webhook uses actorless receipt capture.
  return affiliateOperation(env, recoveryActor ? 'recovery_receipt' : 'receipt', receipt, recoveryActor || {});
}

export async function captureAffiliatePaymentSafely(env, input) {
  try { return await captureVerifiedAffiliatePayment(env, input); }
  catch (_) { return { ok: false, error: 'affiliate_receipt_capture_unavailable' }; }
}
