// Provider-returned links only. Encrypted tickets keep affiliate IDs out of JSON.
export function validateDemandRedirect(raw, id, criteria, affiliateId, { app = false } = {}) {
  if (typeof raw !== 'string' || raw.length > 8192 || /[\r\n\\]/.test(raw)) return null;
  try {
    const url = new URL(raw);
    if (url.username || url.password || url.hash || url.port) return null;
    for (const key of url.searchParams.keys()) if (/^(authorization|api[_-]?key|access[_-]?token|secret|password)$/i.test(key)) return null;
    if (app) {
      if (url.protocol !== 'booking:' || url.hostname !== 'hotel' || url.pathname !== `/${id}`) return null;
    } else if (url.protocol !== 'https:' || !['booking.com', 'www.booking.com'].includes(url.hostname) || !/^\/(hotel|property)\/[a-z]{2}\/[^/]+\.html$/.test(url.pathname)) return null;
    const affiliate = url.searchParams.getAll('aid').concat(url.searchParams.getAll('affiliate_id'));
    if (affiliate.length !== 1 || affiliate[0] !== String(affiliateId)) return null;
    for (const [key, value] of [['checkin', criteria.checkin], ['checkout', criteria.checkout]]) {
      if (url.searchParams.getAll(key).length !== 1 || url.searchParams.get(key) !== value) return null;
    }
    for (const [key, value] of [['group_adults', criteria.guests.number_of_adults], ['no_rooms', criteria.guests.number_of_rooms]]) {
      if (url.searchParams.getAll(key).length !== 1 || url.searchParams.get(key) !== String(value)) return null;
    }
    if (criteria.guests.children?.length) {
      if (url.searchParams.getAll('group_children').length !== 1 || url.searchParams.get('group_children') !== String(criteria.guests.children.length) || JSON.stringify(url.searchParams.getAll('age').map(Number).sort((a,b)=>a-b)) !== JSON.stringify([...criteria.guests.children].sort((a,b)=>a-b))) return null;
    }
    if (!criteria.guests.children?.length && (url.searchParams.getAll('age').length || url.searchParams.getAll('group_children').length > 1 || (url.searchParams.has('group_children') && url.searchParams.get('group_children') !== '0'))) return null;
    if (url.searchParams.has('hotel_id') && url.searchParams.get('hotel_id') !== String(id)) return null;
    return url.toString();
  } catch { return null; }
}
const encode = bytes => btoa(String.fromCharCode(...bytes)).replaceAll('+','-').replaceAll('/','_').replaceAll('=','');
const decode = value => Uint8Array.from(atob(value.replaceAll('-','+').replaceAll('_','/')), ch => ch.charCodeAt(0));
async function ticketKey(secret) {
  const hash = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(`fluxidi-demand-redirect-v1:${secret}`));
  return crypto.subtle.importKey('raw', hash, 'AES-GCM', false, ['encrypt','decrypt']);
}
export async function issueDemandRedirectTicket({ url, appUrl, id, criteria, env, now }) {
  const nonce = crypto.getRandomValues(new Uint8Array(12));
  const plain = new TextEncoder().encode(JSON.stringify({ url, appUrl, id, criteria, expires: now + 300000, environment: 'sandbox' }));
  const encrypted = await crypto.subtle.encrypt({ name: 'AES-GCM', iv: nonce }, await ticketKey(env.BOOKING_DEMAND_API_KEY), plain);
  return `${encode(nonce)}.${encode(new Uint8Array(encrypted))}`;
}
export async function openDemandRedirectTicket(token, env, now, app = false) {
  try {
    if (typeof token !== 'string' || token.length > 16000 || !/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(token)) return null;
    const [nonce, ciphertext] = token.split('.');
    const plain = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: decode(nonce) }, await ticketKey(env.BOOKING_DEMAND_API_KEY), decode(ciphertext));
    const value = JSON.parse(new TextDecoder().decode(plain));
    if (value.environment !== 'sandbox' || !Number.isFinite(value.expires) || value.expires <= now || value.expires > now + 300000) return null;
    const web = validateDemandRedirect(value.url, value.id, value.criteria, env.BOOKING_DEMAND_AFFILIATE_ID);
    if (!web) return null;
    return app ? validateDemandRedirect(value.appUrl, value.id, value.criteria, env.BOOKING_DEMAND_AFFILIATE_ID, { app: true }) ?? web : web;
  } catch { return null; }
}
