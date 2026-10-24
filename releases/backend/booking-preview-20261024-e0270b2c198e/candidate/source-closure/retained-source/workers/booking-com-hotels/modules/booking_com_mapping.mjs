import { hotelPropertyIdentity } from "../../booking/modules/hotels/hotel_provider_contract.mjs";
import { translated } from './booking_com_locations.mjs';

/** Explicit Demand identity, independent of RateHawk. */
export function bookingComPropertyIdentity(providerId) {
  return hotelPropertyIdentity({ provider: "booking-demand", provider_id: providerId }, "booking-demand");
}

const amount = value => typeof value === 'number' && Number.isFinite(value) && value >= 0 ? value : null;
const text = value => typeof value === 'string' ? value.slice(0, 16000) : null;
const code = value => typeof value === 'string' && /^[A-Z]{3}$/.test(value) ? value : null;
export function mapDemandPrice(price, currencies, requestedCurrency) {
  const booker = code(currencies?.booker), accommodation = code(currencies?.accommodation);
  const currency = booker ?? accommodation;
  const slot = booker ? 'booker_currency' : 'accommodation_currency';
  const valid = currency !== null && (!requestedCurrency || currency === requestedCurrency);
  const get = value => valid ? amount(value?.[slot]) : null;
  return { currency, total_price: get(price?.total), base_price: get(price?.base), display_price: get(price?.display),
    charges: valid && Array.isArray(price?.charges) ? price.charges.map(charge => ({
      charge_id: Number.isSafeInteger(charge?.charge) ? charge.charge : null,
      condition_id: Number.isSafeInteger(charge?.condition) ? charge.condition : null,
      total_amount: get(charge?.total_amount), unit_amount: get(charge?.unit_amount), currency,
      included_in_display: typeof charge?.included_in?.display === 'boolean' ? charge.included_in.display : null,
      mode: text(charge?.mode), percentage: amount(charge?.percentage),
    })) : [] };
}
function mapCancellation(policy) {
  if (!policy || typeof policy !== 'object') return null;
  return { type: text(policy.type), free_cancellation_until: text(policy.free_cancellation_until),
    schedule: Array.isArray(policy.schedule) ? policy.schedule.slice(0, 30).map(entry => ({ from: text(entry?.from),
      price: { accommodation_currency: amount(entry?.price?.accommodation_currency), booker_currency: amount(entry?.price?.booker_currency) } })) : [] };
}
function photoUrl(raw) {
  try {
    const url = new URL(raw);
    return url.protocol === 'https:' && !url.username && !url.password && !url.port &&
      (url.hostname === 'bstatic.com' || url.hostname.endsWith('.bstatic.com')) ? url.toString() : null;
  } catch { return null; }
}
export function mapDemandProperty(detail, { language = 'en-gb', cityName = '', retrievedAt, sandbox = true } = {}) {
  const identity = bookingComPropertyIdentity(detail?.id);
  if (!identity) return null;
  const location = detail.location ?? {}, latitude = location.coordinates?.latitude, longitude = location.coordinates?.longitude;
  if (typeof latitude !== 'number' || typeof longitude !== 'number' || !Number.isFinite(latitude) || !Number.isFinite(longitude) || Math.abs(latitude) > 90 || Math.abs(longitude) > 180) return null;
  const photos = Array.isArray(detail.photos) ? [...detail.photos].sort((a,b) => Number(b?.main_photo === true)-Number(a?.main_photo === true)) : [];
  const imageUrls = [...new Set(photos.map(photo => photoUrl(photo?.url?.large ?? photo?.url?.standard)).filter(Boolean))].slice(0, 50);
  const name = translated(detail.name, language);
  if (!name) return null;
  const rating = detail.rating ?? {}, policies = detail.policies ?? {}, times = detail.checkin_checkout_times ?? {};
  // Demand numeric type IDs are retained. No guessing labels from another provider.
  return { ...identity, source: 'booking-demand', name, type: 'accommodation', accommodation_type_id: detail.accommodation_type ?? null,
    address: translated(location.address, language), postal_code: text(location.postal_code), city: cityName,
    city_provider_id: Number.isSafeInteger(location.city) ? String(location.city) : null,
    region: '', region_provider_ids: Array.isArray(location.regions) ? location.regions.filter(Number.isSafeInteger).map(String) : [],
    country: typeof location.country === 'string' && /^[a-z]{2}$/.test(location.country) ? location.country.toUpperCase() : '',
    latitude, longitude, image_url: imageUrls[0] ?? null, image_urls: imageUrls,
    description: translated(detail.description?.text, language),
    important_information: translated(detail.description?.important_information, language),
    facilities: Array.isArray(detail.facilities) ? detail.facilities.filter(x => Number.isSafeInteger(x?.id)).map(x => ({ id: x.id })) : [],
    review_score: typeof rating.review_score === 'number' && rating.review_score >= 0 && rating.review_score <= 10 ? rating.review_score : null,
    review_count: Number.isSafeInteger(rating.number_of_reviews) ? rating.number_of_reviews : null,
    stars: typeof rating.stars === 'number' && rating.stars >= 1 && rating.stars <= 5 ? rating.stars : null,
    stars_type: ['official','estimated_by_accommodation','estimated_by_booking'].includes(rating.stars_type) ? rating.stars_type : null,
    policies: { minimum_checkin_age: amount(policies.minimum_checkin_age), maximum_checkin_age: amount(policies.maximum_checkin_age),
      minimum_guest_age: amount(policies.minimum_guest_age), pets: { allowed: text(policies.pets?.allowed), charge_mode: text(policies.pets?.charge_mode) } },
    checkin_checkout: { checkin_from: text(times.checkin_from), checkin_to: text(times.checkin_to), checkout_from: text(times.checkout_from), checkout_to: text(times.checkout_to) },
    currency: code(detail.currency), accommodation_status: text(detail.accommodation_status), retrieved_at: retrievedAt,
    sandbox, is_real_approved: !sandbox && detail.accommodation_status === 'open', external_availability_url: null };
}
export function mapDemandAvailability(row, criteria, retrievedAt) {
  const identity = bookingComPropertyIdentity(row?.id);
  if (!identity) return null;
  const products = Array.isArray(row.products) ? row.products.filter(p => p && typeof p === 'object' && p.number_available !== 0) : [];
  const pricing = mapDemandPrice(row.recommendation?.price ?? row.price, row.currency, criteria.currency);
  const offers = products.map(product => ({ provider: 'booking-demand', provider_id: identity.provider_id,
    rate_id: text(product.id), room_id: text(product.room), number_available: amount(product.number_available),
    number_of_adults: amount(product.number_of_adults), ...mapDemandPrice(product.price, row.currency, criteria.currency),
    cancellation: mapCancellation(product.policies?.cancellation), meal_plan: text(product.policies?.meal_plan?.plan) }));
  return { ...identity, available: products.length > 0, ...pricing, offers, retrieved_at: retrievedAt,
    external_availability_url: null, checkin: criteria.checkin, checkout: criteria.checkout, guests: criteria.guests };
}
export function mapDemandSearchStay(detail, search, criteria, options) {
  const property = mapDemandProperty(detail, options);
  if (!property || String(search.id) !== property.provider_id || property.accommodation_status !== 'open') return null;
  const pricing = mapDemandPrice(search.price, search.currency, criteria.currency);
  return { ...property, ...pricing, price_label: pricing.display_price === null ? null : `${pricing.currency} ${pricing.display_price.toFixed(2)}`,
    availability_label: 'available_for_requested_stay', checkin: criteria.checkin, checkout: criteria.checkout, guests: criteria.guests };
}
