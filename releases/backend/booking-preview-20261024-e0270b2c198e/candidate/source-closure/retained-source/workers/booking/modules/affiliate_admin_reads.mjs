// CEO-only read contracts. Invoked after the ledger's transactional authority check.
// Never decrypt bank material, call a provider, or derive commission from prices.
const decode = value => value ? JSON.parse(value) : null;
const text = value => typeof value === 'string' ? value.trim() : '';
const refusal = code => { throw Object.assign(new Error(code), { code, status: 400 }); };
const checked = value => {
  if (!Number.isSafeInteger(value)) refusal('affiliate_amount_overflow');
  return value;
};
export const AFFILIATE_ADMIN_READS = new Set(['cc_summary', 'cc_directory', 'cc_detail', 'cc_batch', 'cc_snapshot', 'cc_company_receipts']);

function filters(body) {
  const period = text(body.period), currency = text(body.currency), status = text(body.status);
  if (period && !/^\d{4}-(0[1-9]|1[0-2])$/.test(period)) refusal('affiliate_period_invalid');
  if (currency && !/^[A-Z]{3}$/.test(currency)) refusal('affiliate_currency_invalid');
  if (status && !['pending', 'active', 'rejected', 'suspended'].includes(status)) refusal('affiliate_status_invalid');
  const limit = body.limit == null ? 20 : Number(body.limit);
  if (!Number.isInteger(limit) || limit < 1 || limit > 50) refusal('affiliate_limit_invalid');
  return { period, currency, status, limit, q: text(body.q).slice(0, 160) };
}

function page(rows, limit, key = 'id') {
  return { items: rows.slice(0, limit), next_cursor: rows.length > limit ? String(rows[limit - 1][key]) : null };
}

function balances(db, id, f) {
  const person = db.person(id);
  const rows = db.rows(`SELECT currency, SUM(cents) AS balance_cents,
    SUM(CASE WHEN kind='commission' AND (?='' OR period=?) THEN cents ELSE 0 END) AS commission_cents,
    SUM(CASE WHEN kind='correction' AND (?='' OR period=?) THEN cents ELSE 0 END) AS correction_cents
    FROM entries WHERE affiliate_id=? AND (?='' OR period<=?) AND (?='' OR currency=?) GROUP BY currency`,
    f.period, f.period, f.period, f.period, id, f.period, f.period, f.currency, f.currency);
  const held = db.one("SELECT COUNT(*) AS n FROM receipts WHERE affiliate_id=? AND state='held_review'", id).n;
  return rows.map(row => {
    const reserved = db.one("SELECT COALESCE(SUM(cents),0) AS n FROM payouts WHERE affiliate_id=? AND currency=? AND state IN ('approved','exported','failed')", id, row.currency).n;
    const paid = db.one("SELECT COALESCE(SUM(cents),0) AS n FROM payouts WHERE affiliate_id=? AND currency=? AND state='paid' AND (?='' OR period=?)", id, row.currency, f.period, f.period).n;
    const reasons = [];
    if (person.status !== 'active') reasons.push('affiliate_approval_required');
    if (!person.bank || person.bank_verified !== 1) reasons.push('bank_verification_required');
    if (held) reasons.push('unresolved_receipts');
    const available = checked(Math.max(0, checked(row.balance_cents) - checked(reserved)));
    if (!available) reasons.push('no_payable_balance');
    return { currency: row.currency, balance_cents: checked(row.balance_cents),
      commission_cents: checked(row.commission_cents), correction_cents: checked(row.correction_cents),
      reserved_cents: checked(reserved), available_cents: available, paid_cents: checked(paid),
      payable_cents: reasons.length ? 0 : available, payout_blockers: reasons };
  });
}

function affiliate(db, row, f) {
  const profile = decode(row.profile) || {};
  return { affiliate_id: row.id, display_name: text(profile.display_name), applicant_type: profile.applicant_type,
    status: row.status, referral_code: row.status === 'active' ? row.code : null,
    revision: row.revision, terms_version: row.terms_version, bank_verified: row.bank_verified === 1,
    bank_revision: row.bank_revision, created_at: row.created_at, updated_at: row.updated_at,
    referred_companies: db.one('SELECT COUNT(*) AS n FROM attributions WHERE affiliate_id=?', row.id).n,
    held_receipts: db.one("SELECT COUNT(*) AS n FROM receipts WHERE affiliate_id=? AND state='held_review'", row.id).n,
    balances: balances(db, row.id, f) };
}

export function affiliateAdminRead(db, action, body = {}) {
  const f = filters(body);
  if(action==='cc_company_receipts'){
    const tenant=text(body.tenant_id),company=text(body.company_id),cursor=text(body.cursor);
    if([tenant,company].some(value=>!value||value.length>80||! /^[A-Za-z0-9._-]+$/.test(value)||value.includes('..')||value==='global'))refusal('receipt_scope_invalid');
    if(cursor.length>200)refusal('receipt_cursor_invalid');
    const rows=db.rows('SELECT id,payment_id,receipt,basis,state,reason,revision,created_at,updated_at FROM receipts WHERE scope=? AND id>? ORDER BY id LIMIT ?',JSON.stringify([tenant,company]),cursor,f.limit+1);
    const pick=(row,keys)=>Object.fromEntries(keys.filter(key=>Object.hasOwn(row,key)).map(key=>[key,row[key]]));
    const result=page(rows,f.limit);
    return{schema_version:'command_center_company_receipts_v1',provenance:'verified_receipt_ledger',coverage:'captured_receipts_only',complete_provider_history:false,generated_at:new Date().toISOString(),...result,
      items:result.items.map(row=>({id:row.id,payment_id:row.payment_id,state:row.state,reason:row.reason,revision:row.revision,created_at:row.created_at,updated_at:row.updated_at,
        receipt:pick(decode(row.receipt)||{},['verified','scope_verified','provider','kind','currency','gross_cents','refunded_gross_cents','charged_back_gross_cents','mode','payment_status','paid_at','captured_at']),
        basis:row.basis?pick(decode(row.basis),['source','reference','currency','ex_vat_cents','vat_cents']):null}))};
  }
  const metadata = { schema_version: 'affiliate_command_center_v1', generated_at: new Date().toISOString(),
    period: f.period || null, currency: f.currency || null, commission_rate_bps: 500,
    revenue_basis: 'verified_paid_ex_vat_subscriptions_and_addons', automatic_bank_transfers: false };
  if (action === 'cc_snapshot') {
    // Called inside the existing single SQLite read transaction: summary,
    // directory and the requested dossier share one consistent ledger state.
    return { ...metadata, provenance: 'affiliate_ledger',
      summary: affiliateAdminRead(db, 'cc_summary', body),
      directory: affiliateAdminRead(db, 'cc_directory', body),
      details: text(body.affiliate_id) ? [affiliateAdminRead(db, 'cc_detail', body)] : [] };
  }
  if (action === 'cc_summary') {
    // Group totals in SQLite, keeping currencies separate. This is not MRR.
    const currencies = db.rows(`SELECT currency,
      SUM(CASE WHEN kind='commission' THEN cents ELSE 0 END) AS commission_cents,
      SUM(CASE WHEN kind='correction' THEN cents ELSE 0 END) AS correction_cents
      FROM entries WHERE (?='' OR period=?) AND (?='' OR currency=?) GROUP BY currency`,
      f.period, f.period, f.currency, f.currency).map(row => ({ ...row,
        commission_cents: checked(row.commission_cents), correction_cents: checked(row.correction_cents) }));
    const payout_totals = db.rows(`SELECT currency,state,SUM(cents) AS cents,COUNT(*) AS count FROM payouts
      WHERE (?='' OR period=?) AND (?='' OR currency=?) GROUP BY currency,state`,
      f.period, f.period, f.currency, f.currency).map(row => ({ ...row, cents: checked(row.cents) }));
    return { ...metadata, status_counts: db.rows('SELECT status,COUNT(*) AS count FROM affiliates GROUP BY status'),
      referral_counts: db.rows('SELECT state,COUNT(*) AS count FROM attributions GROUP BY state'),
      receipt_counts: db.rows('SELECT state,COUNT(*) AS count FROM receipts GROUP BY state'),
      held_claims: db.one("SELECT COUNT(*) AS n FROM referral_claims c WHERE c.state='held_owner_review' AND NOT EXISTS(SELECT 1 FROM attributions a WHERE a.scope=c.scope)").n,
      incomplete_registrations: db.one("SELECT COUNT(*) AS n FROM registrations WHERE state='writing'").n,
      currencies, payout_totals };
  }
  if (action === 'cc_directory') {
    const pattern = '%' + f.q.replace(/[\\%_]/g, '\\$&') + '%';
    const rows = db.rows(`SELECT * FROM affiliates WHERE id>? AND (?='' OR status=?)
      AND (?='' OR code LIKE ? ESCAPE '\\' OR json_extract(profile,'$.display_name') LIKE ? ESCAPE '\\')
      ORDER BY id LIMIT ?`, text(body.cursor), f.status, f.status, f.q, pattern, pattern, f.limit + 1);
    const paged = page(rows, f.limit);
    return { ...metadata, ...paged, items: paged.items.map(row => affiliate(db, row, f)) };
  }
  if (action === 'cc_detail') {
    const id = text(body.affiliate_id), person = db.person(id);
    const entryCursor = Number(body.entries_cursor || 0);
    if (!Number.isSafeInteger(entryCursor) || entryCursor < 0) refusal('affiliate_cursor_invalid');
    const entries = db.rows(`SELECT e.id,e.currency,e.cents,e.kind,e.period,e.created_at,e.receipt_id,e.receipt_revision,
      r.scope,r.payment_id,r.state AS receipt_state FROM entries e LEFT JOIN receipts r ON r.id=e.receipt_id
      WHERE e.affiliate_id=? AND e.id>? AND (?='' OR e.period=?) AND (?='' OR e.currency=?) ORDER BY e.id LIMIT ?`,
      id, entryCursor, f.period, f.period, f.currency, f.currency, f.limit + 1);
    const referrals = db.page('referrals', id, { limit: f.limit, cursor: text(body.referrals_cursor) });
    const payouts = db.rows(`SELECT id,batch_id,period,currency,cents,state,execution_reference,updated_at FROM payouts
      WHERE affiliate_id=? AND id>? AND (?='' OR period=?) AND (?='' OR currency=?) ORDER BY id LIMIT ?`,
      id, text(body.payouts_cursor), f.period, f.period, f.currency, f.currency, f.limit + 1);
    const receipts = db.rows(`SELECT id,scope,payment_id,receipt,basis,state,reason,target,revision,created_at,updated_at
      FROM receipts WHERE affiliate_id=? AND id>? ORDER BY id LIMIT ?`, id, text(body.receipts_cursor), f.limit + 1);
    return { ...metadata, affiliate: affiliate(db, person, f), referrals,
      entries: page(entries, f.limit), payouts: page(payouts, f.limit),
      receipts: { ...page(receipts, f.limit), items: receipts.slice(0, f.limit).map(row => ({ ...row,
        receipt: decode(row.receipt), basis: decode(row.basis) })) } };
  }
  if (action === 'cc_batch') {
    const batch = db.one('SELECT id,period,currency,manifest_hash,created_at FROM batches WHERE id=?', text(body.batch_id));
    if (!batch) throw Object.assign(new Error('affiliate_batch_not_found'), { code: 'affiliate_batch_not_found', status: 404 });
    const rows = db.rows(`SELECT id,affiliate_id,period,currency,cents,state,execution_reference,updated_at
      FROM payouts WHERE batch_id=? AND id>? ORDER BY id LIMIT ?`, batch.id, text(body.cursor), f.limit + 1);
    return { ...metadata, batch, ...page(rows, f.limit) };
  }
  refusal('affiliate_read_action_invalid');
}
