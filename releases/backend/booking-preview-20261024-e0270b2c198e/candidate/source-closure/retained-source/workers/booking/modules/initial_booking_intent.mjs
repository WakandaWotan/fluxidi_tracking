import { reconcileInitialPayment } from './initial_payment_reconciliation.mjs';
// Private company-coordinator context; never populated by an HTTP payload.
const context = Symbol('initialBookingIntent');
const fail = code => { const error = new Error(code); error.code = code; error.status = 503; throw error; };
const same = (a, b) => a?.tenant_id === b?.tenant_id && a?.company_id === b?.company_id;
const digest = async value => Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',
  new TextEncoder().encode(value))), byte => byte.toString(16).padStart(2, '0')).join('');

export function withInitialBookingIntentState(env, state, scope) {
  return { ...env, [context]: { state, scope } };
}

export async function reserveInitialBookingIntent(env, scope, intentKey, allocate, providedId = '') {
  const current = env[context];
  if (!current || !same(current.scope, scope)) fail('initial_booking_coordinator_required');
  const key = `initial-booking-intent:${await digest(intentKey)}`;
  const previous = await current.state.storage.get(key);
  if (previous) {
    if (!same(previous, scope) || (providedId && providedId !== previous.bookingId)) fail('initial_booking_intent_conflict');
    return previous.bookingId;
  }
  const bookingId = providedId || await allocate();
  // Durable identity precedes provider calls, projections, offers and receipts.
  await current.state.storage.put(key, { schema: 1, ...scope, bookingId });
  return bookingId;
}

export async function initialPaymentIdentity(env, bookingId) {
  const current = env[context];
  if (!current) fail('initial_booking_coordinator_required');
  const key = `initial-booking-payment:${bookingId}`;
  let payment = await current.state.storage.get(key);
  if (!payment) {
    payment = { schema: 1, ...current.scope, bookingId, paymentId: crypto.randomUUID() };
    await current.state.storage.put(key, payment);
  }
  if (!same(payment, current.scope) || payment.bookingId !== bookingId) fail('initial_booking_payment_conflict');
  return payment.paymentId;
}

// Mollie deduplicates for only one hour, and keys are credential-specific.
// Persist the exact request/response; an ambiguous old attempt needs reconciliation.
export async function initialMollieRequest(env, bookingId, paymentId, url, body, apiKey) {
  const current = env[context];
  if (!current) fail('initial_booking_coordinator_required');
  const key = `initial-booking-payment:${bookingId}`;
  const payment = await current.state.storage.get(key);
  if (!same(payment, current.scope) || payment?.paymentId !== paymentId) fail('initial_booking_payment_conflict');
  const credentialHash = await digest(apiKey);
  const previous = payment.request;
  if (previous && (previous.url !== url
    || JSON.stringify(previous.body.amount) !== JSON.stringify(body.amount)
    || previous.body.profileId !== body.profileId || previous.body.method !== body.method
    || previous.body.testmode !== body.testmode)) {
    fail('initial_booking_payment_reconciliation_required');
  }
  if (payment.response) return Response.json(payment.response.body, { status: payment.response.status });
  if (previous?.credentialHash !== undefined && previous.credentialHash !== credentialHash && !previous.body.profileId) {
    fail('initial_booking_payment_reconciliation_required');
  }
  if (previous && (Date.now() - previous.at >= 55 * 60_000 || previous.credentialHash !== credentialHash)) {
    const recovered = await reconcileInitialPayment(current.state, current.scope, bookingId, apiKey, { automatic: true });
    return Response.json(recovered.data);
  }
  const prepared = { ...payment, request: previous || { url, body: { ...body, metadata: {
    ...body.metadata, initialBookingId: bookingId, initialPaymentIntentId: paymentId,
  } }, credentialHash, at: Date.now() } };
  if (!previous) await current.state.storage.put(key, prepared);
  const response = await fetch(prepared.request.url, { method: 'POST', headers: {
    Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json', 'Idempotency-Key': paymentId,
  }, body: JSON.stringify(prepared.request.body) });
  const data = await response.json();
  // Keep successful provider evidence before updating either booking record.
  // 409/5xx are ambiguous and may be retried with the same frozen request.
  if (response.ok && data?.id && data?._links?.checkout?.href) {
    await current.state.storage.put(key, { ...prepared, response: { status: response.status, body: data } });
  }
  return Response.json(data, { status: response.status });
}

export async function reconcileInitialMolliePayment(env, bookingId, apiKey, options = {}) {
  const current = env[context];
  if (!current) fail('initial_booking_coordinator_required');
  return reconcileInitialPayment(current.state, current.scope, bookingId, apiKey, options);
}

export async function readInitialPaymentReconciliationRecords(env, bookingId) {
  const current = env[context];
  if (!current) fail('initial_booking_coordinator_required');
  const { canonicalBookingOperation } = await import('./canonical_booking_authority.mjs');
  const inspected = await canonicalBookingOperation(current.state, env,
    { operation: 'inspect', scope: current.scope, bookingId });
  if (!inspected.ok || !inspected.record) return null;
  const payment = await current.state.storage.get(`initial-booking-payment:${bookingId}`);
  if (!payment || !same(payment, current.scope) || payment.bookingId !== bookingId || !payment.paymentId) return null;
  const shadow = await canonicalBookingOperation(current.state, env,
    { operation: 'inspect', scope: current.scope, bookingId: payment.paymentId });
  if (!shadow.ok || !shadow.record) return null;
  return { record: inspected.record, shadow: shadow.record };
}
