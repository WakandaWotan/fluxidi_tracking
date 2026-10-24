import { importHmacKey, jsonBase64urlEncode, jsonBase64urlDecode,
  base64urlEncodeBytes, constantTimeEquals, sha256Hex } from './crypto_utils.js';

export const TEST_CONTENT_READ = 'test_content_read';
export const TEST_CONTENT_IMPORT = 'test_content_import';
export const TEST_CONTENT_AUDIENCE = 'ratehawk-test-content';
export const TEST_CONTENT_TTL_MS = 60_000;
const PURPOSES = [TEST_CONTENT_READ, TEST_CONTENT_IMPORT];
const safe = value => typeof value === 'string' && value.length > 0 &&
  value.length <= 128 && /^[a-zA-Z0-9_.:@-]+$/.test(value);
const enabled = value => value === '1' || value === true;

export function isTestContentPrincipalAllowed(env, identity, purpose) {
  if (!enabled(env.RATEHAWK_TEST_CONTENT_ENABLED) || !PURPOSES.includes(purpose) ||
      !['subject', 'tenant_id', 'company_id'].every(key => safe(identity?.[key]))) return false;
  if (purpose === TEST_CONTENT_IMPORT && !enabled(env.RATEHAWK_TEST_CONTENT_IMPORT_ENABLED)) return false;
  let rows;
  try { rows = JSON.parse(env.RATEHAWK_TEST_CONTENT_PRINCIPALS ?? '[]'); } catch { return false; }
  return Array.isArray(rows) && rows.some(row =>
    ['subject', 'tenant_id', 'company_id'].every(key => row?.[key] === identity[key]) &&
    Array.isArray(row.purposes) && row.purposes.includes(purpose));
}

async function signature(secret, encoded) {
  const key = await importHmacKey(secret);
  return base64urlEncodeBytes(new Uint8Array(await crypto.subtle.sign('HMAC', key,
    new TextEncoder().encode(encoded))));
}

// Gateway MUST obtain identity from its verified session, never a request body.
export async function issueTestContentContext(env, identity, purpose, payload, { now = Date.now() } = {}) {
  const secret = env.RATEHAWK_TEST_CONTENT_CONTEXT_SECRET;
  if (typeof secret !== 'string' || secret.length < 32 || !Number.isSafeInteger(now) ||
      !isTestContentPrincipalAllowed(env, identity, purpose)) return { ok: false, reason: 'test_content_forbidden' };
  const claims = { subject: identity.subject, tenant_id: identity.tenant_id,
    company_id: identity.company_id, purpose, aud: TEST_CONTENT_AUDIENCE,
    surface: 'isolated_test', iat: now, exp: now + TEST_CONTENT_TTL_MS,
    body_sha256: await sha256Hex(JSON.stringify(payload)) };
  const encoded = jsonBase64urlEncode(claims);
  return { ok: true, token: `rhtc1.${encoded}.${await signature(secret, encoded)}` };
}

export async function verifyTestContentContext(env, token, purpose, payload, { now = Date.now() } = {}) {
  const denied = () => ({ ok: false, reason: 'test_content_forbidden' });
  const secret = env.RATEHAWK_TEST_CONTENT_CONTEXT_SECRET;
  if (typeof secret !== 'string' || secret.length < 32 || typeof token !== 'string' ||
      token.length > 4096 || !Number.isSafeInteger(now)) return denied();
  const parts = token.split('.');
  if (parts.length !== 3 || parts[0] !== 'rhtc1') return denied();
  try {
    if (!constantTimeEquals(await signature(secret, parts[1]), parts[2])) return denied();
    const claims = jsonBase64urlDecode(parts[1]);
    if (claims.purpose !== purpose || claims.aud !== TEST_CONTENT_AUDIENCE ||
        claims.surface !== 'isolated_test' || !Number.isSafeInteger(claims.iat) ||
        !Number.isSafeInteger(claims.exp) || claims.iat > now || claims.exp <= now ||
        claims.exp <= claims.iat || claims.exp - claims.iat > TEST_CONTENT_TTL_MS ||
        !isTestContentPrincipalAllowed(env, claims, purpose) ||
        claims.body_sha256 !== await sha256Hex(JSON.stringify(payload))) return denied();
    return { ok: true, claims };
  } catch { return denied(); }
}
