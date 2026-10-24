import { hashDocumentSnapshot } from './document_core.js';
import { renderCompanyMonthlyInvoiceHtml } from './company_monthly_invoice_html.mjs';
import { renderPdfFromHtml } from './pdf_render.mjs';

const fail = (error, status = 409) => ({ ok: false, error, status });
const id = value => /^[A-Za-z0-9_-]{1,160}$/.test(value || '');
const base = scope => `monthly_invoice:v1:${scope.tenant_id}:${scope.company_id}`;
const validPdf = bytes => bytes instanceof Uint8Array && bytes.length >= 32 && bytes.length <= 2 * 1024 * 1024 &&
  new TextDecoder().decode(bytes.slice(0, 5)) === '%PDF-' && new TextDecoder().decode(bytes.slice(-64)).includes('%%EOF');
const encoded = bytes => { let out = ''; for (let i = 0; i < bytes.length; i += 4096) out += String.fromCharCode(...bytes.slice(i, i + 4096)); return btoa(out); };
const digestBytes = async bytes => [...new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))].map(value => value.toString(16).padStart(2, '0')).join('');

export async function listCompanyMonthlyInvoices(state, env, { scope, customerId, cursor = '' }) {
  if (env?.COMPANY_MONTHLY_INVOICING_ENABLED !== '1') return fail('monthly_invoicing_disabled');
  if (!id(scope?.tenant_id) || !id(scope?.company_id) || !id(customerId) ||
      cursor !== '' && !/^\d{4}-(0[1-9]|1[0-2])$/.test(cursor)) return fail('monthly_invoice_request_invalid', 400);
  const pin = await state.storage.get('canonical-booking-scope');
  if (pin?.tenant_id !== scope.tenant_id || pin?.company_id !== scope.company_id) return fail('invoice_source_scope_unverified');
  const prefix = `${base(scope)}:issue:${customerId}:`;
  const entries = await state.storage.list({ prefix, ...(cursor ? { startAfter: `${prefix}${cursor}` } : {}), limit: 20 });
  const items = [];
  for (const [key, journal] of entries) {
    const month = key.slice(prefix.length);
    if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(month)) return fail('invoice_document_unverified');
    if (!journal?.document) {
      if (journal?.tenant_id !== scope.tenant_id || journal?.company_id !== scope.company_id ||
          journal?.customer_id !== customerId || journal?.month !== month) return fail('invoice_document_unverified');
      items.push({ month, state: 'preparing' }); continue;
    }
    const read = await readCompanyMonthlyInvoice(state, env, { scope, customerId, month });
    if (!read.ok) return read;
    const doc = read.document;
    const mail = await state.storage.get(`${base(scope)}:mail:${doc.document_id}`);
    if (mail && mail.content_hash !== doc.content_hash) return fail('invoice_email_conflict');
    items.push({ month, state: 'issued', document_number: doc.document_number,
      gross_cents: doc.schema_version===2?doc.totals.gross_cents:doc.immutable_snapshot.monthly_invoice.totals.gross_cents,
      currency: doc.schema_version===2?doc.currency:doc.immutable_snapshot.monthly_invoice.currency,
      delivery_state: mail?.state === 'sent' ? 'sent' : mail ? 'pending' : 'not_sent',
      projection_pending: read.projection_pending });
  }
  return { ok: true, status: 200, items, next_cursor: entries.size === 20 ? items.at(-1).month : null };
}

export async function readCompanyMonthlyInvoice(state, env, { scope, customerId, month }) {
  if (env?.COMPANY_MONTHLY_INVOICING_ENABLED !== '1') return fail('monthly_invoicing_disabled');
  if (!id(scope?.tenant_id) || !id(scope?.company_id) || !id(customerId) || !/^\d{4}-(0[1-9]|1[0-2])$/.test(month || '')) return fail('monthly_invoice_request_invalid', 400);
  const pin = await state.storage.get('canonical-booking-scope');
  if (pin?.tenant_id !== scope.tenant_id || pin?.company_id !== scope.company_id) return fail('invoice_source_scope_unverified');
  const journal = await state.storage.get(`${base(scope)}:issue:${customerId}:${month}`);
  const doc = journal?.document;
  if (!doc) return fail('monthly_invoice_not_issued', 404);
  if(journal.schema_version===2){const {readPublishedInvoiceJob}=await import('./company_monthly_invoice_job.mjs');const result=await readPublishedInvoiceJob(state.storage,{scope,customerId,month});return result.ok?{ok:true,status:200,document:result.document,projection_pending:true,annex_available:true}:result;}
  if (doc.tenant_id !== scope.tenant_id || doc.company_id !== scope.company_id || doc.customer_id !== customerId || doc.month !== month ||
      doc.lifecycle_state !== 'issued' || await hashDocumentSnapshot(doc.immutable_snapshot) !== doc.content_hash) return fail('invoice_document_unverified');
  const projection = await state.storage.get(`monthly_invoice_projection:v1:${scope.tenant_id}:${scope.company_id}:${doc.document_id}`);
  return { ok: true, status: 200, document: structuredClone(doc), projection_pending: !projection || projection.offset !== projection.total };
}

async function accountPdfUsage(state, env, input, doc, recordUsage) {
  const key = `${base(input.scope)}:pdf-usage:${doc.document_id}`;
  const claim = await state.storage.transaction(async tx => {
    const existing = await tx.get(key);
    if (existing) return { existing };
    if (typeof recordUsage !== 'function') return { missing: true };
    // Claim BEFORE invoking the legacy counter. Its KV write has no atomic
    // dedup key; an uncertain result must never cause a second consumption.
    await tx.put(key, { content_hash: doc.content_hash, state: 'pending' });
    return { fresh: true };
  });
  if (claim.existing) return { usage_pending: claim.existing.content_hash !== doc.content_hash || claim.existing.state !== 'recorded' };
  if (claim.missing) return { usage_pending: true };
  let result;
  try { result = await recordUsage(env, input.scope); } catch { result = null; }
  if (result?.ok) {
    await state.storage.put(key, { content_hash: doc.content_hash, state: 'recorded' });
    return { usage_pending: false };
  }
  return { usage_pending: true };
}

export async function companyMonthlyInvoicePdf(state, env, input, { prepare = false, render = renderPdfFromHtml, recordUsage = null } = {}) {
  const read = await readCompanyMonthlyInvoice(state, env, input);
  if (!read.ok) return read;
  const doc = read.document;
  if(doc.schema_version===2)return {...fail('invoice_annex_requires_paged_export'),annex_available:true,pdf_status:'not_rendered'};
  const bucket = env.PUBLIC_MEDIA;
  if (!bucket?.get || !bucket?.put) return fail('invoice_artifact_storage_unavailable', 503);
  const key = `private-artifacts/monthly-invoices/${input.scope.tenant_id}/${input.scope.company_id}/${doc.document_id}/${doc.content_hash}.pdf`;
  const stored = await bucket.get(key);
  if (stored) {
    if (stored.size > 2 * 1024 * 1024) return fail('invoice_pdf_unverified');
    const bytes = new Uint8Array(await stored.arrayBuffer());
    if (!validPdf(bytes) || stored.customMetadata?.content_hash !== doc.content_hash ||
        stored.customMetadata?.pdf_hash !== await digestBytes(bytes)) return fail('invoice_pdf_unverified');
    const usage = prepare ? await accountPdfUsage(state, env, input, doc, recordUsage) : {};
    return { ok: true, status: 200, pdf_base64: encoded(bytes), filename: `${doc.document_number}.pdf`, ...usage };
  }
  if (!prepare) return fail('invoice_pdf_not_prepared', 404);
  let bytes;
  try {
    const html = renderCompanyMonthlyInvoiceHtml({ invoice: doc.immutable_snapshot.monthly_invoice,
      seller: doc.immutable_snapshot.seller_snapshot, buyer: doc.immutable_snapshot.buyer_snapshot, document: doc });
    bytes = await render(html, env);
  } catch { return fail('invoice_pdf_render_failed', 503); }
  if (!validPdf(bytes)) return fail('invoice_pdf_unverified');
  await bucket.put(key, bytes, { httpMetadata: { contentType: 'application/pdf', cacheControl: 'private, no-store' },
    customMetadata: { content_hash: doc.content_hash, pdf_hash: await digestBytes(bytes) } });
  const usage = await accountPdfUsage(state, env, input, doc, recordUsage);
  return { ok: true, status: 200, pdf_base64: encoded(bytes), filename: `${doc.document_number}.pdf`, ...usage };
}

// Only explicit authenticated company send. Never automatically send on issue.
// Payload and first-attempt time freeze before the provider request. Resend's
// 24h dedup window is bounded to 23h here; unknown older attempts require review.
export async function sendCompanyMonthlyInvoice(state, env, input, { send = fetch, now = () => new Date().toISOString() } = {}) {
  if (env.COMPANY_MONTHLY_INVOICE_EMAIL_ENABLED !== '1') return fail('monthly_invoice_email_disabled');
  if (!env.RESEND_API_KEY || !env.EMAIL_FROM) return fail('invoice_email_not_configured');
  const read = await readCompanyMonthlyInvoice(state, env, input);
  if (!read.ok) return read;
  const doc = read.document;
  if(doc.schema_version===2)return {...fail('invoice_annex_requires_paged_export'),annex_available:true,pdf_status:'not_rendered'};
  const recipient = doc.immutable_snapshot.buyer_snapshot?.email;
  if (typeof recipient !== 'string' || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(recipient)) return fail('invoice_email_recipient_missing');
  const pdf = await companyMonthlyInvoicePdf(state, env, input);
  if (!pdf.ok) return pdf;
  const key = `${base(input.scope)}:mail:${doc.document_id}`;
  const prepared = await state.storage.transaction(async tx => {
    const existing = await tx.get(key);
    if (existing) {
      if (existing.content_hash !== doc.content_hash) return fail('invoice_email_conflict');
      if (existing.state === 'sent') return { ok: true, sent: true, replay: true };
      const age = Date.parse(now()) - Date.parse(existing.first_attempt_at);
      if (!Number.isFinite(age) || age < 0 || age >= 23 * 60 * 60 * 1000) return fail('invoice_email_delivery_needs_review');
      return { ok: true, claim: existing };
    }
    const claim = { state: 'pending', content_hash: doc.content_hash, first_attempt_at: now(),
      from: env.EMAIL_FROM, recipient, subject: `Maandfactuur ${doc.document_number}`,
      text: `In bijlage vindt u uw maandfactuur ${doc.document_number} voor ${doc.month}.`,
      filename: pdf.filename, pdf_hash: await hashDocumentSnapshot(pdf.pdf_base64) };
    await tx.put(key, claim); return { ok: true, claim };
  });
  if (!prepared.ok || prepared.sent) return { ...prepared, status: prepared.ok ? 200 : prepared.status };
  const claim = prepared.claim;
  if (await hashDocumentSnapshot(pdf.pdf_base64) !== claim.pdf_hash) return fail('invoice_email_attachment_changed');
  let response, result;
  try {
    response = await send('https://api.resend.com/emails', { method: 'POST', headers: {
      Authorization: `Bearer ${env.RESEND_API_KEY}`, 'Content-Type': 'application/json', 'Idempotency-Key': `monthly-${doc.content_hash}` },
      body: JSON.stringify({ from: claim.from, to: [claim.recipient], subject: claim.subject, text: claim.text,
        attachments: [{ filename: claim.filename, content: pdf.pdf_base64 }] }) });
    result = await response.json();
  } catch { return fail('invoice_email_delivery_pending', 503); }
  if (!response.ok || typeof result?.id !== 'string' || !result.id) return fail('invoice_email_delivery_pending', 503);
  await state.storage.put(key, { ...claim, state: 'sent', provider_id: result.id, sent_at: now() });
  return { ok: true, sent: true, status: 200 };
}
