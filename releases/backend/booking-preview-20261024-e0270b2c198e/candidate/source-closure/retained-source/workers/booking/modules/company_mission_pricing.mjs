// Optional server-owned tariff evaluator. No routes/payment changes or I/O.
// Distances/times must come from the backend's verified complete mission route.
const unavailable = reason => ({ ok: false, request_quote: true, reason });
const finite = value => typeof value === 'number' && Number.isFinite(value) && value >= 0;
const cents = value => Math.round((value + Number.EPSILON) * 100);

export function quoteCompanyMission({ tariff, vehicleCategory, missionKm, missionMinutes, pickupLocalDate, billingMode, localRide = false, occupiedKm, waitingMinutes }) {
  if (!tariff || tariff.version !== 1) return unavailable('mission_tariff_missing');
  if (!/^\d{4}-\d{2}-\d{2}$/.test(pickupLocalDate ?? '')) return unavailable('pickup_local_date_required');
  const dateMs = Date.parse(`${pickupLocalDate}T00:00:00Z`);
  if (!Number.isFinite(dateMs) || new Date(dateMs).toISOString().slice(0, 10) !== pickupLocalDate) return unavailable('pickup_local_date_required');
  if ((tariff.quote_only_month_days ?? []).includes(pickupLocalDate.slice(5))) return unavailable('exception_day');
  if (!['immediate', 'business_invoice'].includes(billingMode)) return unavailable('billing_mode_required');
  const category = tariff.categories?.[vehicleCategory];
  if (!category) return unavailable('vehicle_tariff_missing');
  let distancePrice;
  if (localRide) {
    if (typeof tariff.local_minimum_applies !== 'boolean') return unavailable('local_minimum_policy_required');
    if (!finite(occupiedKm) || !finite(waitingMinutes) || !finite(category.local_start_eur)
      || !finite(category.local_per_km_eur) || !finite(tariff.waiting_per_minute_eur)) return unavailable('local_meter_inputs_required');
    distancePrice = category.local_start_eur + occupiedKm * category.local_per_km_eur + waitingMinutes * tariff.waiting_per_minute_eur;
  } else {
    if (!finite(missionKm)) return unavailable('complete_mission_distance_required');
    if (!Array.isArray(category.bands)) return unavailable('distance_bands_required');
    const matches = category.bands.filter(band =>
      (band.min_km === null || (band.min_inclusive ? missionKm >= band.min_km : missionKm > band.min_km))
      && (band.max_km === null || (band.max_inclusive ? missionKm <= band.max_km : missionKm < band.max_km)));
    if (matches.length !== 1) return unavailable(matches.length ? 'ambiguous_distance_boundary' : 'distance_band_missing');
    const band = matches[0];
    if (band.fixed_eur !== undefined) {
      if (!finite(band.fixed_eur)) return unavailable('distance_tariff_invalid');
      distancePrice = band.fixed_eur;
    } else {
      if (!finite(band.start_eur) || !finite(band.per_km_eur)) return unavailable('distance_tariff_invalid');
      distancePrice = band.start_eur + missionKm * band.per_km_eur;
    }
  }
  return finalizeCompanyMissionAmount({ tariff, calculatedTariffEur: distancePrice,
    missionMinutes, billingMode, applyMinimum: !localRide || tariff.local_minimum_applies });
}

// Shared financial floor for a trusted metered/band/fixed tariff and a verified
// full assignment duration. No routing, config changes or provider requests.
// Airport handlers must supply verified assignment evidence before using this.
export function finalizeCompanyMissionAmount({ tariff, calculatedTariffEur: distancePrice,
  missionMinutes, billingMode, applyMinimum = true }) {
  if (!tariff || tariff.version !== 1 || !finite(distancePrice)) return unavailable('mission_tariff_missing');
  if (!['immediate', 'business_invoice'].includes(billingMode)) return unavailable('billing_mode_required');
  if (applyMinimum && (!finite(missionMinutes) || !finite(tariff.minimum_per_minute_eur))) return unavailable('complete_mission_duration_required');
  const minimum = applyMinimum ? missionMinutes * tariff.minimum_per_minute_eur : 0;
  const rawAmount = Math.max(distancePrice, minimum);
  const amount_cents = tariff.price_rounding === 'nearest_euro' ? Math.round(rawAmount) * 100 : cents(rawAmount);
  if (!Number.isSafeInteger(amount_cents) || !Number.isSafeInteger(cents(distancePrice)) || !Number.isSafeInteger(cents(minimum))) {
    return unavailable('mission_amount_invalid');
  }
  return { ok: true, amount_cents, currency: 'EUR', vat_basis: billingMode === 'business_invoice' ? 'exclusive' : 'inclusive',
    distance_amount_cents: cents(distancePrice), minimum_amount_cents: cents(minimum), minimum_applied: minimum > distancePrice };
}
