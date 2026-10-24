// Read-only provider discovery. Absence is never permission for another POST.
const paymentId = value => typeof value === 'string' && /^tr_[A-Za-z0-9_-]{1,125}$/.test(value);
const fail = code => { const error = new Error(code); error.code = code; error.status = 503; throw error; };
const hash = async value => Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',
  new TextEncoder().encode(value))), byte => byte.toString(16).padStart(2, '0')).join('');
const validDate = value => typeof value === 'string' && Number.isFinite(Date.parse(value));

function proof(payment, data, apiKey) {
  const request = payment.request, body = request.body, metadata = data?.metadata;
  const original = body.metadata;
  if (original?.bookingId !== payment.paymentId || original?.tenantId !== payment.tenant_id
    || original?.companyId !== payment.company_id) fail('initial_booking_payment_identity_unproven');
  if (!paymentId(data?.id) || !metadata || metadata.bookingId !== payment.paymentId
    || metadata.tenantId !== payment.tenant_id || metadata.companyId !== payment.company_id
    || (metadata.tenant_id !== undefined && metadata.tenant_id !== payment.tenant_id)
    || (metadata.company_id !== undefined && metadata.company_id !== payment.company_id)
    || (original.initialBookingId && metadata.initialBookingId !== payment.bookingId)
    || (original.initialPaymentIntentId && metadata.initialPaymentIntentId !== payment.paymentId)
    || data.amount?.currency !== body.amount?.currency || data.amount?.value !== body.amount?.value
    || (body.profileId && data.profileId !== body.profileId)
    || (body.method && data.method !== body.method)
    || data.sequenceType && data.sequenceType !== 'oneoff'
    || !['open', 'pending', 'authorized', 'paid', 'failed', 'expired', 'canceled'].includes(data.status)
    || !validDate(data.createdAt) || Date.parse(data.createdAt) < request.at - 300_000
    || Date.parse(data.createdAt) > request.at + 55 * 60_000) fail('initial_booking_payment_evidence_mismatch');
  const mode = apiKey.startsWith('test_') || body.testmode === true ? 'test' : 'live';
  if (data.mode !== mode) fail('initial_booking_payment_mode_mismatch');
  // A paid/terminal payment may no longer expose a checkout link. Do not invent one.
  if (['open', 'pending', 'authorized'].includes(data.status)) {
    let link; try { link = new URL(data?._links?.checkout?.href); } catch { fail('initial_booking_payment_checkout_unproven'); }
    if (link.protocol !== 'https:' || !(link.hostname === 'mollie.com' || link.hostname.endsWith('.mollie.com'))
      || link.username || link.password) fail('initial_booking_payment_checkout_unproven');
  }
  return data;
}

async function read(url, apiKey) {
  let response, data;
  try {
    response = await fetch(url, { method: 'GET', headers: { Authorization: `Bearer ${apiKey}` },
      redirect: 'manual', signal: AbortSignal.timeout(5000) });
    if (!response.ok) fail('initial_booking_payment_provider_unavailable');
    const raw = await response.text();
    if (raw.length > 768_000) fail('initial_booking_payment_inventory_limit');
    data = JSON.parse(raw);
  } catch (error) { if (error.code?.startsWith('initial_booking_')) throw error; fail('initial_booking_payment_provider_unavailable'); }
  return data;
}

export async function reconcileInitialPayment(state, scope, bookingId, apiKey, options = {}) {
  const key = `initial-booking-payment:${bookingId}`, payment = await state.storage.get(key);
  if (!payment || payment.bookingId !== bookingId || payment.tenant_id !== scope?.tenant_id
    || payment.company_id !== scope?.company_id || !payment.request || typeof apiKey !== 'string' || !apiKey) {
    fail('initial_booking_payment_identity_unproven');
  }
  let originalUrl;
  try { originalUrl = new URL(payment.request.url); } catch { fail('initial_booking_payment_identity_unproven'); }
  if (originalUrl.origin !== 'https://api.mollie.com' || originalUrl.pathname !== '/v2/payments'
    || originalUrl.username || originalUrl.password || !Number.isFinite(payment.request.at)) fail('initial_booking_payment_identity_unproven');
  const body = payment.request.body;
  if (!body || body.metadata?.bookingId !== payment.paymentId || body.metadata?.tenantId !== scope.tenant_id
    || body.metadata?.companyId !== scope.company_id || !body.amount?.currency || !body.amount?.value) {
    fail('initial_booking_payment_identity_unproven');
  }
  // OAuth rotation is safe for GET only when the original profile remains explicit.
  if (!body.profileId && payment.request.credentialHash !== await hash(apiKey)) fail('initial_booking_payment_credentials_unproven');
  const known = options.providerPaymentId || payment.response?.body?.id;
  if (known && !paymentId(known)) fail('initial_booking_payment_identity_unproven');
  if (payment.response && known !== payment.response.body.id) fail('initial_booking_payment_identity_conflict');
  if (options.automatic === true) {
    const last = payment.reconciliation_attempt?.at;
    if (Number.isFinite(last) && Date.now() - last < 60_000) fail('initial_booking_payment_reconciliation_pending');
    // Persist backoff before a provider read, including when its answer is lost.
    payment.reconciliation_attempt = { at: Date.now() };
    await state.storage.put(key, payment);
  }
  const url = new URL('https://api.mollie.com/v2/payments');
  if (body.profileId) url.searchParams.set('profileId', body.profileId);
  if (body.testmode === true && !apiKey.startsWith('test_')) url.searchParams.set('testmode', 'true');
  let candidate = known;
  if (!candidate) {
    url.searchParams.set('limit', '100'); url.searchParams.set('sort', 'desc');
    const cursors = new Set(), ids = new Map(), candidates = new Set(); let complete = false;
    for (let page = 0; page < 5; page++) {
      const list = await read(url.href, apiKey), values = list?._embedded?.payments;
      if (!Array.isArray(values) || values.length > 100 || list.count !== values.length
        || !list._links || !Object.hasOwn(list._links, 'next')) fail('initial_booking_payment_inventory_incomplete');
      for (const value of values) {
        if (!paymentId(value?.id)) fail('initial_booking_payment_inventory_incomplete');
        const encoded = JSON.stringify(value);
        if (ids.has(value.id) && ids.get(value.id) !== encoded) fail('initial_booking_payment_inventory_incomplete');
        ids.set(value.id, encoded);
        if (value.metadata?.bookingId === payment.paymentId || value.metadata?.initialPaymentIntentId === payment.paymentId) {
          proof(payment, value, apiKey); candidates.add(value.id);
        }
      }
      if (candidates.size > 1) fail('initial_booking_payment_identity_conflict');
      if (list._links.next === null) { complete = true; break; }
      let next;
      try { next = new URL(list._links.next?.href); } catch { fail('initial_booking_payment_inventory_incomplete'); }
      const cursor = next.searchParams.get('from');
      if (next.origin !== url.origin || next.pathname !== url.pathname || next.username || next.password
        || !paymentId(cursor) || cursors.has(cursor)
        || [...next.searchParams.keys()].some(key => !['from', 'limit', 'sort', 'profileId', 'testmode'].includes(key))
        || ['profileId', 'testmode', 'sort'].some(key => next.searchParams.has(key)
          && next.searchParams.get(key) !== url.searchParams.get(key))) fail('initial_booking_payment_inventory_incomplete');
      cursors.add(cursor); url.searchParams.set('from', cursor);
    }
    if (!complete) fail('initial_booking_payment_inventory_limit');
    candidate = [...candidates][0];
    if (!candidate) fail('initial_booking_payment_reconciliation_required');
  }
  // List metadata is a discovery hint; the exact payment is read again before adoption.
  const detail = new URL(url); detail.pathname += `/${candidate}`;
  for (const query of ['from', 'sort', 'limit']) detail.searchParams.delete(query);
  if (originalUrl.searchParams.get('include') === 'details.qrCode') detail.searchParams.set('include', 'details.qrCode');
  const data = proof(payment, await read(detail.href, apiKey), apiKey);
  if (data.id !== candidate) fail('initial_booking_payment_identity_conflict');
  if (payment.response?.body?.status === 'paid' && data.status !== 'paid') fail('initial_booking_payment_identity_conflict');
  if (options.dryRun !== true) {
    await state.storage.put(key, { ...payment, response: { status: 200, body: data },
      reconciliation: { providerPaymentId: candidate, at: Date.now(), source: known ? 'exact_payment_get' : 'complete_payment_list_get' } });
  }
  return { ok: true, providerPaymentId: candidate, paymentStatus: data.status, dryRun: options.dryRun === true, data };
}
