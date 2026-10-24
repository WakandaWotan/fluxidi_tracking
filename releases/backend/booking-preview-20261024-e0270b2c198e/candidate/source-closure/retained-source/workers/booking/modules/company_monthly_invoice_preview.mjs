import {hydrateCanonicalFinancialEvidence} from './financial_quote_lifecycle.mjs';
import { collectCompanyMonthlyInvoiceSources } from './company_monthly_invoice_sources.mjs';
import { projectCompanyMonthlyInvoiceRecord } from './company_monthly_invoice_projection.mjs';
import { hashDocumentSnapshot } from './document_core.js';

// Runs inside the company coordinator's existing serialized queue. A public
// caller cannot provide records, prices, buyer snapshots or ownership evidence.
export async function previewCompanyMonthlyInvoice(state, env, { scope, customerId, month }, deriveInvoiceContext, reservedContentHash = null) {
  if (env?.COMPANY_MONTHLY_INVOICING_ENABLED !== '1') return { ok: false, status: 409, error: 'monthly_invoicing_disabled' };
  if (env?.BOOKING_RECORD_AUTHORITY_ENABLED !== '1') return { ok: false, status: 409, error: 'invoice_source_authority_required' };
  const storage = state?.storage;
  const result = await collectCompanyMonthlyInvoiceSources(storage, { scope, customerId, month,
    projectRecord: async input => projectCompanyMonthlyInvoiceRecord({ ...input, record:await hydrateCanonicalFinancialEvidence(env,input.record,input.bookingId), deriveInvoiceContext,
      readSourceOwnership: async ({ bookingId, legId }) => {
        const claims = await storage.get(`monthly_invoice:v1:${scope.tenant_id}:${scope.company_id}:source:${bookingId}`);
        const relevantClaims = claims ? (legId == null ? Object.values(claims) : [claims[''], claims[legId]].filter(Boolean)) : [];
        if (relevantClaims.length && !(reservedContentHash && relevantClaims.every(claim =>
          claim.content_hash === reservedContentHash && claim.batch_key === `monthly_invoice:v1:${scope.tenant_id}:${scope.company_id}:batch:${customerId}:${month}`))) return { verified: true, state: 'claimed' };
        // These sources carry the server policy frozen on initial creation.
        // A persisted monthly policy blocks all per-ride invoice paths even
        // after flag rollback. Legacy sources without that policy are ignored.
        const source = input.record;
        if (source.invoice_document_id || source.invoice_number || source.document_core_invoice ||
            source.booking?.invoice_document_id || source.booking?.invoice_number) return { verified: false };
        return { verified: true, state: 'unclaimed' };
      },
    }),
  });
  if (!result.ok) return { ...result, status: 409 };
  if (result.empty) return { ...result, status: 200 };
  return { ...result, status: 200, content_hash: await hashDocumentSnapshot(result.invoice),
    buyer: structuredClone(result.invoice.lines[0].billing_policy.buyer_snapshot), preview_only: true };
}
