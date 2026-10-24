// Query aliases only. Stored provider city names and provenance stay unchanged.
export const RATEHAWK_CITY_ALIASES = Object.freeze({
  gent: 'ghent', brugge: 'bruges', antwerpen: 'antwerp', brussel: 'brussels',
  ieper: 'ypres', oostende: 'ostend',
});

export const normalizeRatehawkCatalogText = value => String(value ?? '').trim()
  .toLowerCase().normalize('NFD').replace(/\p{Diacritic}/gu, '').replace(/\s+/g, ' ');

export function normalizeRatehawkCityKey(value) {
  const text = normalizeRatehawkCatalogText(value);
  return RATEHAWK_CITY_ALIASES[text] ?? text;
}

export function ratehawkCatalogSearchMatches(row, value) {
  const text = normalizeRatehawkCatalogText(value);
  if (!text) return true;
  const canonical = normalizeRatehawkCityKey(text);
  const terms = new Set([text, canonical]);
  for (const [alias, target] of Object.entries(RATEHAWK_CITY_ALIASES))
    if (target === canonical) terms.add(alias);
  // Preserve property/address substring search; never inspect descriptions.
  const searchable = normalizeRatehawkCatalogText(`${row.name} ${row.address} ${row.city_key}`);
  return [...terms].some(term => searchable.includes(term));
}
