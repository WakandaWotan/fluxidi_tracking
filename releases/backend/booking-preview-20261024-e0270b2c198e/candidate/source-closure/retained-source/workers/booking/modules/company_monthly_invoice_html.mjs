import { assembleCompanyMonthlyInvoice } from './company_customer_invoicing.mjs';
import { stableDocumentJson } from './document_core.js';

const escape = value => String(value ?? '').replace(/[&<>"']/g, c => ({
  '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
}[c]));
const money = (cents, currency) => `${(cents / 100).toFixed(2).replace('.', ',')} ${escape(currency)}`;
const address = person => [person?.address_line1 || person?.address_line, person?.address_line2,
  [person?.postal_code, person?.city].filter(Boolean).join(' '), person?.country_code]
  .filter(Boolean).map(escape).join('<br>');
const identity = person => `<strong>${escape(person?.legal_name || person?.name)}</strong><br>${address(person)}${person?.vat_number ? `<br>BTW: ${escape(person.vat_number)}` : ''}`;
const dateFormatter = new Intl.DateTimeFormat('nl-BE', { timeZone: 'Europe/Brussels', year: 'numeric', month: '2-digit', day: '2-digit' });

// Pure presentation of a verified frozen monthly bundle. Official numbers
// must originate in Document Core; without one, this is an explicit preview.
// No booking, PDF provider, payment, invoice allocation or email is performed.
export function renderCompanyMonthlyInvoiceHtml({ invoice, seller, buyer, document = null }) {
  const verified = assembleCompanyMonthlyInvoice({ scope: invoice, customerId: invoice?.customer_id,
    month: invoice?.month, lines: invoice?.lines, complete: true });
  if (!verified.ok) throw new Error(verified.error);
  const bundle = verified.invoice;
  if (!seller?.legal_name || !(buyer?.legal_name || buyer?.name)) throw new Error('invoice_identity_required');
  const official = document != null;
  if (official && (!/^INV-[A-Za-z0-9_-]+$/.test(document.document_number || '') ||
      document.lifecycle_state !== 'issued' || document.tenant_id !== bundle.tenant_id ||
      document.company_id !== bundle.company_id || document.customer_id !== bundle.customer_id ||
      document.month !== bundle.month || !document.issue_timestamp)) throw new Error('invoice_document_unverified');
  if (official && (stableDocumentJson(document.immutable_snapshot?.monthly_invoice) !== stableDocumentJson(bundle) ||
      stableDocumentJson(document.immutable_snapshot?.seller_snapshot) !== stableDocumentJson(seller) ||
      stableDocumentJson(document.immutable_snapshot?.buyer_snapshot) !== stableDocumentJson(buyer))) throw new Error('invoice_snapshot_mismatch');
  const rows = bundle.lines.map(line => `<tr><td>${escape(dateFormatter.format(new Date(line.completed_at)))}</td><td>${escape(line.booking_id)}${line.leg_id ? `<br>${escape(line.leg_id)}` : ''}</td><td>${escape(line.from || '')}${line.to ? ` &rarr; ${escape(line.to)}` : ''}</td><td class="amount">${money(line.net_cents, bundle.currency)}</td><td class="amount">${escape(line.vat_rate_percent)}%</td><td class="amount">${money(line.gross_cents, bundle.currency)}</td></tr>`).join('');
  const groups = bundle.tax_groups.map(group => `<tr><td>BTW ${escape(group.vat_rate_percent)}%</td><td class="amount">${money(group.net_cents, bundle.currency)}</td><td class="amount">${money(group.vat_cents, bundle.currency)}</td></tr>`).join('');
  return `<!doctype html><html lang="nl"><head><meta charset="utf-8"><title>${official ? 'Maandfactuur' : 'Voorbeeld maandfactuur'}</title><style>
    @page{size:A4;margin:14mm}body{font:11px Arial,sans-serif;color:#172027}h1{font-size:23px;margin-bottom:5px}h2{font-size:13px}p{line-height:1.5}.parties{display:flex;gap:35px;margin:22px 0}.party{width:48%;line-height:1.5}table{border-collapse:collapse;width:100%;margin:14px 0}thead{display:table-header-group}tr{break-inside:avoid}th,td{border-bottom:1px solid #ccd1d4;padding:8px 5px;text-align:left;vertical-align:top;overflow-wrap:anywhere}.amount{text-align:right;white-space:nowrap}.totals{width:65%;margin-left:auto}.total{font-size:15px;font-weight:bold}.preview{padding:10px;border:1px solid #888}.footer{font-size:10px;color:#555}
  </style></head><body><h1>${official ? 'Maandfactuur' : 'Voorbeeld maandfactuur'}</h1>
  ${official ? `<p>Factuurnummer: <strong>${escape(document.document_number)}</strong><br>Uitgiftedatum: ${escape(document.issue_timestamp.slice(0, 10))}</p>` : '<p class="preview">VOORBEELD — geen uitgegeven factuur en geen betalingsverzoek.</p>'}
  <p>Periode: ${escape(bundle.month)} · ${bundle.lines.length} ritregels</p>
  <div class="parties"><div class="party"><h2>Bedrijf</h2>${identity(seller)}</div><div class="party"><h2>Klant</h2>${identity(buyer)}</div></div>
  <table><thead><tr><th>Datum afgerond</th><th>Rit / traject</th><th>Route</th><th class="amount">Excl. BTW</th><th class="amount">BTW</th><th class="amount">Incl. BTW</th></tr></thead><tbody>${rows}</tbody></table>
  <table class="totals"><thead><tr><th>BTW-overzicht</th><th class="amount">Basis</th><th class="amount">BTW</th></tr></thead><tbody>${groups}</tbody></table>
  <table class="totals"><tbody><tr><td>Totaal excl. BTW</td><td class="amount">${money(bundle.totals.net_cents, bundle.currency)}</td></tr><tr><td>BTW</td><td class="amount">${money(bundle.totals.vat_cents, bundle.currency)}</td></tr><tr class="total"><td>Totaal incl. BTW</td><td class="amount">${money(bundle.totals.gross_cents, bundle.currency)}</td></tr></tbody></table>
  <p class="footer">Deze bundel bevat uitsluitend de hierboven vermelde ritregels. Betaling en factuuruitgifte zijn afzonderlijke handelingen.</p></body></html>`;
}
