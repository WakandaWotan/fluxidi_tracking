import { demandLanguage } from './booking_com_locations.mjs';
export function demandPropertyId(value) {
  if (!['string','number'].includes(typeof value) || !/^[1-9]\d*$/.test(String(value))) return null;
  const number = Number(value);
  return Number.isSafeInteger(number) && number > 0 ? number : null;
}
export function demandStayCriteria(criteria = {}, now = Date.now()) {
  if (!criteria || typeof criteria !== 'object' || Array.isArray(criteria)) return null;
  for (const key of ['guests','booker']) if (criteria[key] !== undefined && (!criteria[key] || typeof criteria[key] !== 'object' || Array.isArray(criteria[key]))) return null;
  const { checkin, checkout } = criteria;
  const date = value => typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value) && Number.isFinite(Date.parse(value)) && new Date(value).toISOString().slice(0, 10) === value;
  if (!date(checkin) || !date(checkout)) return null;
  const today = Date.parse(new Date(now).toISOString().slice(0, 10)), start = Date.parse(checkin), end = Date.parse(checkout), day = 86400000;
  if (start < today || end <= start || end - start > 90 * day || end - today > 500 * day) return null;
  const input = criteria.guests ?? {}, adults = Number(input.number_of_adults ?? criteria.adults), rooms = Number(input.number_of_rooms ?? criteria.rooms ?? 1);
  if ([input.number_of_adults ?? criteria.adults, input.number_of_rooms ?? criteria.rooms ?? 1].some(value => !['string','number'].includes(typeof value))) return null;
  let children = input.children ?? criteria.childAges ?? [];
  if (typeof children === 'string') { try { children = JSON.parse(children); } catch { return null; } }
  if (!Number.isInteger(adults) || adults < 1 || adults > 30 || !Number.isInteger(rooms) || rooms < 1 || rooms > adults || rooms > 30 || !Array.isArray(children) || children.length > 30 || children.some(age => !Number.isInteger(age) || age < 0 || age > 17)) return null;
  const guests = { number_of_adults: adults, number_of_rooms: rooms, ...(children.length ? { children: [...children] } : {}) };
  if (input.allocation) {
    if (!Array.isArray(input.allocation) || input.allocation.length !== rooms) return null;
    const allocation = input.allocation.map(room => ({ number_of_adults: room?.number_of_adults, children: room?.children ?? [] }));
    if (allocation.some(room => !Number.isInteger(room.number_of_adults) || room.number_of_adults < 1 || !Array.isArray(room.children) || room.children.some(age => !Number.isInteger(age) || age < 0 || age > 17))) return null;
    if (allocation.reduce((sum, room) => sum + room.number_of_adults, 0) !== adults || JSON.stringify(allocation.flatMap(room => room.children).sort((a,b) => a-b)) !== JSON.stringify([...children].sort((a,b) => a-b))) return null;
    guests.allocation = allocation;
  } else if (children.length && rooms > 1) return null;
  const country = String(criteria.booker?.country ?? criteria.bookerCountry ?? '').toLowerCase(), platform = criteria.booker?.platform ?? criteria.platform;
  const currency = String(criteria.currency ?? 'EUR').toUpperCase(), language = demandLanguage(criteria.language);
  if (!/^[a-z]{2}$/.test(country) || !['android','desktop','ios','mobile','tablet'].includes(platform) || !/^[A-Z]{3}$/.test(currency) || !language) return null;
  const booker = { country, platform };
  if (criteria.booker?.state != null) { if (!/^[a-z]{2}$/.test(criteria.booker.state)) return null; booker.state = criteria.booker.state; }
  return { checkin, checkout, guests, booker, currency, language };
}
