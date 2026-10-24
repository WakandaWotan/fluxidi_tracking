import { previewCompanyMonthlyInvoice } from './company_monthly_invoice_preview.mjs';
import { reserveCompanyMonthlyInvoice } from './company_monthly_invoice_ledger.mjs';
import { issueReservedCompanyMonthlyInvoice } from './company_monthly_invoice_issue.mjs';
import { buildCompanyMonthlyInvoiceRegistryRecord, projectCompanyMonthlyInvoiceRegistry } from './company_monthly_invoice_registry.mjs';
import { companyInvoiceMonth } from './company_customer_invoicing.mjs';

export async function issueCompanyMonthlyInvoice(state, env, { scope, customerId, month, expectedContentHash }, dependencies) {
  if (env?.COMPANY_MONTHLY_INVOICING_ENABLED !== '1') return { ok: false, status: 409, error: 'monthly_invoicing_disabled' };
  if (env?.BOOKING_RECORD_AUTHORITY_ENABLED !== '1' || !state?.storage?.transaction) return { ok: false, status: 409, error: 'invoice_source_authority_required' };
  if (!/^[A-Za-z0-9_-]{1,160}$/.test(scope?.tenant_id || '') || !/^[A-Za-z0-9_-]{1,160}$/.test(scope?.company_id || '') ||
      !/^[A-Za-z0-9_-]{1,160}$/.test(customerId || '') || !/^\d{4}-(0[1-9]|1[0-2])$/.test(month || '') ||
      !/^[a-f0-9]{64}$/.test(expectedContentHash || '')) return { ok: false, status: 400, error: 'monthly_invoice_request_invalid' };
  const pin = await state.storage.get('canonical-booking-scope');
  if (pin?.tenant_id !== scope.tenant_id || pin?.company_id !== scope.company_id) return { ok: false, status: 409, error: 'invoice_source_scope_unverified' };
  const now = dependencies.now ? dependencies.now() : new Date().toISOString();
  if (month >= companyInvoiceMonth(now)) return { ok: false, status: 409, error: 'invoice_period_not_closed' };
  const prefix = `monthly_invoice:v1:${scope.tenant_id}:${scope.company_id}`;
  const reservation = await state.storage.get(`${prefix}:batch:${customerId}:${month}`);
  const journal = await state.storage.get(`${prefix}:issue:${customerId}:${month}`);
  if(journal?.schema_version===2){const {readPublishedInvoiceJob}=await import('./company_monthly_invoice_job.mjs');const issued=await readPublishedInvoiceJob(state.storage,{scope,customerId,month});return issued.ok&&issued.content_hash!==expectedContentHash?{ok:false,status:409,error:'monthly_invoice_batch_changed'}:issued;}
  if (reservation && reservation.content_hash !== expectedContentHash) return { ok: false, status: 409, error: 'monthly_invoice_batch_changed' };
  let buyer = journal?.buyer, seller = journal?.seller;
  if (!journal?.document) {
    const preview = await previewCompanyMonthlyInvoice(state, env, { scope, customerId, month },
      dependencies.deriveInvoiceContext, reservation?.content_hash || null);
    if (!preview.ok) return preview;
    if (preview.empty) return { ok: false, status: 409, error: 'invoice_lines_empty' };
    if (preview.content_hash !== expectedContentHash) return { ok: false, status: 409, error: 'monthly_invoice_preview_changed' };
    buyer = journal?.buyer || preview.buyer;
    if (!seller) {
      const resolved = await dependencies.resolveSeller(env, scope);
      if (!resolved?.ok) return { ok: false, status: 409, error: resolved?.error || 'seller_identity_incomplete', missing_fields: resolved?.missing_fields || [] };
      seller = resolved.seller_snapshot;
    }
    const reserved = await reserveCompanyMonthlyInvoice(state.storage, { scope, invoice: preview.invoice });
    if (!reserved.ok) return { ...reserved, status: 409 };
  }
  const result = await issueReservedCompanyMonthlyInvoice(state.storage, { scope, customerId, month,
    contentHash: expectedContentHash, seller, buyer, now,
    allocateReference: input => dependencies.allocateReference(env, input.scope, input),
    buildDocument: buildCompanyMonthlyInvoiceRegistryRecord,
    projectDocument: document => projectCompanyMonthlyInvoiceRegistry(env, document, state.storage),
  });
  return { ...result, status: result.ok ? 200 : 409 };
}
