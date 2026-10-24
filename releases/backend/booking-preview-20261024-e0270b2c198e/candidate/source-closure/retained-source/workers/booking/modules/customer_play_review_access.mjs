// A single reserved review identity. No normal phone/email identity is looked up
// or linked, and neither OTP delivery nor ordinary authentication is changed.
export const CUSTOMER_PLAY_REVIEW_PHONE = '+12025550199';
export const CUSTOMER_PLAY_REVIEW_ID = 'cust_fluxidi_google_play_review_v1';
const EMAIL = 'google-play-review@fluxidi.invalid';
const METHOD = 'play_review_phone';
const PREFIX = 'customer_play_review:challenge:';
const TTL = 600;
const SESSION_TTL = 86400;

export function customerPlayReviewHash(env) {
  const hash = String(env?.CUSTOMER_PLAY_REVIEW_CODE_HASH || '').trim().toLowerCase();
  return /^[a-f0-9]{64}$/.test(hash) ? hash : '';
}

export function customerPlayReviewSessionAllowed(record, env) {
  if (record?.recovery_method !== METHOD) return true;
  return record.customer_id === CUSTOMER_PLAY_REVIEW_ID &&
    record.tenant_id === 'global' && record.company_id === 'global' &&
    !!customerPlayReviewHash(env) &&
    record.review_credential_revision === customerPlayReviewHash(env);
}

export async function handleCustomerPlayReview(stage, body, env, request, deps) {
  const { constantTimeEquals, opaqueToken, clientHash,
    rateLimit, identityKey, sessionKey } = deps;
  const sha256 = async value => {
    const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
    return [...new Uint8Array(digest)].map(byte => byte.toString(16).padStart(2, '0')).join('');
  };
  const json = (value, status) => Response.json(value, {
    status, headers: { 'Cache-Control': 'private, no-store',
      'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization' },
  });
  const fail = (status = 403, error = 'verification_failed') =>
    json({ ok: false, error }, status);
  const hash = customerPlayReviewHash(env);
  if (!env?.BOOKING_KV || !hash) return fail(503, 'recovery_unavailable');
  if (body?.phone_e164 !== CUSTOMER_PLAY_REVIEW_PHONE &&
      body?.phoneE164 !== CUSTOMER_PLAY_REVIEW_PHONE) return fail();
  const rate = await rateLimit({ env,
    rateKey: `customer_play_review:rate:${stage}:${await clientHash(request)}`,
    maxCount: 10, windowSeconds: 900 });
  if (rate.limited) return fail(429, 'rate_limited');
  const now = Date.now();
  const nowIso = new Date(now).toISOString();
  if (stage === 'start') {
    const challenge = opaqueToken(24, 'review_');
    await env.BOOKING_KV.put(PREFIX + challenge, JSON.stringify({
      purpose: METHOD, customer_id: CUSTOMER_PLAY_REVIEW_ID,
      credential_revision: hash, expires_at: now + TTL * 1000,
      attempts: 0, consumed: false,
    }), { expirationTtl: TTL });
    return json({ ok: true, challenge_id: challenge,
      verification_channel: 'sms_otp', expires_in_seconds: TTL,
      masked_phone: '+1***0199', sms_sent: false, debug_otp: null }, 200);
  }
  if (stage !== 'verify') return fail();
  const challenge = String(body?.challenge_id || body?.challengeId || '');
  if (!/^review_[A-Za-z0-9_-]{16,100}$/.test(challenge)) return fail();
  const key = PREFIX + challenge;
  const row = await env.BOOKING_KV.get(key, { type: 'json' });
  if (!row || row.purpose !== METHOD || row.customer_id !== CUSTOMER_PLAY_REVIEW_ID ||
      row.credential_revision !== hash || row.consumed ||
      !Number.isFinite(row.expires_at) || row.expires_at <= now ||
      !Number.isInteger(row.attempts) || row.attempts < 0 || row.attempts >= 5) return fail();
  const otp = String(body?.otp || '').trim();
  const candidate = /^\d{8}$/.test(otp) ? await sha256(otp) : '';
  if (!constantTimeEquals(hash, candidate)) {
    await env.BOOKING_KV.put(key, JSON.stringify({ ...row, attempts: row.attempts + 1 }),
      { expirationTtl: Math.max(1, Math.ceil((row.expires_at - now) / 1000)) });
    return fail();
  }
  const emailHash = await sha256(EMAIL);
  const target = identityKey(CUSTOMER_PLAY_REVIEW_ID);
  const previous = await env.BOOKING_KV.get(target, { type: 'json' });
  // Refuse an unexpected pre-existing identity rather than replacing it.
  if (previous && (previous.customer_id !== CUSTOMER_PLAY_REVIEW_ID ||
      previous.recovery_method !== METHOD || previous.email_hash !== emailHash)) return fail();
  await env.BOOKING_KV.put(target, JSON.stringify({
    version: 1, purpose: 'customer_global_identity',
    customer_id: CUSTOMER_PLAY_REVIEW_ID, email_hash: emailHash, phone_hash: '',
    created_at: previous?.created_at || nowIso, updated_at: nowIso,
    recovery_method: METHOD,
  }));
  await env.BOOKING_KV.put(key, JSON.stringify({ ...row, consumed: true }),
    { expirationTtl: Math.max(1, Math.ceil((row.expires_at - now) / 1000)) });
  const token = opaqueToken(32, 'cus_');
  await env.BOOKING_KV.put(sessionKey(await sha256(token)), JSON.stringify({
    role: 'customer', purpose: 'customer_session', tenant_id: 'global', company_id: 'global',
    customer_id: CUSTOMER_PLAY_REVIEW_ID, email_hash: emailHash, phone_hash: '',
    created_at: nowIso, issued_at: nowIso,
    expires_at: new Date(now + SESSION_TTL * 1000).toISOString(),
    recovery_method: METHOD, review_credential_revision: hash,
  }), { expirationTtl: SESSION_TTL });
  return json({ ok: true, customer_session_token: token,
    customer_id: CUSTOMER_PLAY_REVIEW_ID, expires_in_seconds: SESSION_TTL }, 200);
}
