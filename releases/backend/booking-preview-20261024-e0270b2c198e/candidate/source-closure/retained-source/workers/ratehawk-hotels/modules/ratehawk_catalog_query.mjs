import { RATEHAWK_CITY_ALIASES, normalizeRatehawkCatalogText as norm,
  normalizeRatehawkCityKey } from './ratehawk_city_aliases.mjs';

// Verified against the ordinary Business app's Play production availability on
// 2026-10-05. This scopes content; it grants no provider booking/payment access.
export const RATEHAWK_CATALOG_COUNTRIES = Object.freeze(
  'AT BE CH CY CZ DE DK EE ES FI FR GR HR HU IE IT LI LT LV MC MD MK MT NL NO PL PT RO RS SE SI SK SM UA VA'.split(' '));

export function ratehawkCatalogCountry(value) {
  const text = norm(value);
  if (!text) return { ok: true, code: null };
  for (const code of RATEHAWK_CATALOG_COUNTRIES) {
    if (norm(code) === text || ['en', 'nl', 'fr', 'es', 'de'].some(locale =>
      norm(new Intl.DisplayNames([locale], { type: 'region' }).of(code)) === text))
      return { ok: true, code };
  }
  return { ok: false, code: null };
}

export function ratehawkCatalogSearchTerms(value) {
  const text = norm(value);
  if (!text) return [];
  const canonical = normalizeRatehawkCityKey(text);
  return [...new Set([text, canonical, ...Object.entries(RATEHAWK_CITY_ALIASES)
    .filter(([, target]) => target === canonical).map(([alias]) => alias)])];
}

export function ratehawkCatalogIndexRecord(row) {
  return { hid: row.hid, city_normalized: normalizeRatehawkCityKey(row.city_key),
    search_normalized: norm(`${row.name ?? ''} ${row.address ?? ''} ${row.city_key ?? ''}`) };
}

export function ratehawkCatalogSqlQuery({ countryCode = null, city = '', searchText = '', limit = 100 } = {}) {
  const conditions = ["s.locale = 'en'", 'i.active = 1', 'i.tombstoned = 0',
    'c.active = 1', 'c.tombstoned = 0'];
  const params = [];
  if (countryCode) { conditions.push('s.country_code = ?'); params.push(countryCode); }
  if (city) { conditions.push('n.city_normalized = ?'); params.push(normalizeRatehawkCityKey(city)); }
  const terms = ratehawkCatalogSearchTerms(searchText);
  if (terms.length) {
    // LIKE wildcards are literal customer input, never an expansion of scope.
    conditions.push(`(${terms.map(() => "n.search_normalized LIKE ? ESCAPE '\\'").join(' OR ')})`);
    params.push(...terms.map(term => `%${term.replace(/[\\%_]/g, '\\$&')}%`));
  }
  params.push(Math.min(100, Math.max(1, Math.trunc(Number(limit)) || 100)));
  return { sql: `SELECT s.*, i.kind FROM hotel_search_index s
    JOIN hotel_catalog_index n ON n.hid = s.hid
    JOIN hotel_identity i ON i.hid = s.hid
    JOIN hotel_content_locale c ON c.hid = s.hid AND c.locale = 'en'
    WHERE ${conditions.join(' AND ')} ORDER BY s.hid LIMIT ?`, params };
}
