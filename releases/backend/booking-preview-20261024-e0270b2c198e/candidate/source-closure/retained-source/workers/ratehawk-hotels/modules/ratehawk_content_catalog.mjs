import { openRatehawkContentStore } from './ratehawk_content_store.mjs';
import { isRatehawkIsolatedTestWorker } from './ratehawk_test_activation.mjs';
import { normalizeRatehawkCatalogText as norm, normalizeRatehawkCityKey,
  ratehawkCatalogSearchMatches } from './ratehawk_city_aliases.mjs';
import { ratehawkCatalogCountry } from './ratehawk_catalog_query.mjs';

function matchesCountry(code, requested) {
  if (!requested || norm(code) === norm(requested)) return true;
  if (!/^[A-Z]{2}$/i.test(code ?? '')) return false;
  return ['en', 'nl', 'fr', 'es', 'de'].some(locale =>
    norm(new Intl.DisplayNames([locale], { type: 'region' }).of(code.toUpperCase())) === norm(requested));
}

function stayType(kind) {
  const value = norm(kind).replace(/[\s_-]/g, '');
  if (value === 'apartment' || value === 'apartments' || value === 'aparthotel') return 'aparthotel';
  if (value === 'guesthouse' || value === 'guesthouses') return 'guesthouse';
  if (value === 'bnb' || value === 'bedandbreakfast') return 'b&b';
  return 'hotel';
}

// Only the local, scoped catalog is read. No provider request or sync is started.
export async function readRatehawkContentCatalog({ env = {}, query = {}, store = null } = {}) {
  const empty = reason => ({ ok: true, source: 'ratehawk-catalog', stays: [], count: 0,
    reason, provider_requested: false, content_sync_started: false });
  if (isRatehawkIsolatedTestWorker(env)) return empty('production_path_forbidden_on_test_worker');
  const opened = openRatehawkContentStore(env, store);
  if (!opened.ok) return empty(opened.reason);
  const country = ratehawkCatalogCountry(query.country);
  if (!country.ok) return empty('country_not_in_published_markets');
  if (String(query.city ?? '').length > 120 || String(query.searchText ?? '').length > 120)
    return empty('catalog_query_too_long');
  const city = normalizeRatehawkCityKey(query.city);
  const rows = opened.store.searchCatalogIndex
    ? await opened.store.searchCatalogIndex({ countryCode: country.code, city,
      searchText: query.searchText, limit: 100 })
    : await (opened.store.listCatalogSearchIndex?.() ?? opened.store.listSearchIndex());
  const candidates = [...new Set(rows.filter(row => matchesCountry(row.country_code, country.code)
    && (!city || normalizeRatehawkCityKey(row.city_key) === city)
    && ratehawkCatalogSearchMatches(row, query.searchText)).map(row => row.hid))].slice(0, 100);
  const prefetched = opened.store.readPublicMany
    ? await opened.store.readPublicMany({ hids: candidates, locale: query.language }) : null;
  const stays = [];
  const seen = new Set();
  for (const row of rows) {
    if (seen.has(row.hid) || !matchesCountry(row.country_code, country.code)) continue;
    if (city && normalizeRatehawkCityKey(row.city_key) !== city) continue;
    // Hotel descriptions must never be used for internal search.
    if (!ratehawkCatalogSearchMatches(row, query.searchText)) continue;
    const hotel = prefetched ? prefetched.get(row.hid)
      : await opened.store.readPublic({ hid: row.hid, locale: query.language });
    if (!hotel) continue;
    if (hotel.state !== 'ready') continue;
    const { lat, lng } = hotel.coordinates ?? {};
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) continue;
    seen.add(row.hid);
    const images = [...new Set((hotel.image_refs ?? [])
      .map(item => item.ref)
      .filter(ref => typeof ref === 'string' && /^https:\/\//.test(ref))
      .map(ref => ref.replace('{size}', 'x500')))];
    const description = (hotel.description_struct ?? []).flatMap(section =>
      [section?.title, ...(Array.isArray(section?.paragraphs) ? section.paragraphs : [])])
      .filter(value => typeof value === 'string' && value.trim()).join('\n\n');
    const amenities = (hotel.categories?.amenities ?? []).flatMap(group =>
      typeof group === 'string' ? [group] : Array.isArray(group?.amenities) ? group.amenities : [])
      .filter(value => typeof value === 'string');
    stays.push({ id: `ratehawk:${row.hid}`, hid: row.hid, provider: 'ratehawk', source: 'ratehawk',
      provider_id: String(row.hid), name: hotel.name, address: hotel.address,
      city: row.city_key, country: row.country_code, lat, lng,
      type: stayType(hotel.categories?.property_kind ?? row.kind),
      is_real_approved: true, image_url: images[0] ?? null, image_urls: images,
      description, description_indexed: false,
      static_policies: hotel.static_policies ?? { amenities,
        check_in_time: hotel.categories?.check_in_check_out?.check_in_time ?? null,
        check_out_time: hotel.categories?.check_in_check_out?.check_out_time ?? null,
        important_hotel_information: hotel.categories?.important_hotel_information ?? null },
      retrieved_at: hotel.freshness?.retrieved_at ?? null,
      content_locale: hotel.locale_resolved ?? query.language ?? 'en' });
    if (stays.length >= 100) break;
  }
  return { ...empty(null), stays, count: stays.length };
}
