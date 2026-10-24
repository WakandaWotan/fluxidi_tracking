// Optional company-scoped configuration. Persistence alone never activates pricing.
const keys = (v, allowed) => v && typeof v === 'object' && !Array.isArray(v) && Object.keys(v).every(k => allowed.includes(k));
const money = v => typeof v === 'number' && Number.isFinite(v) && v >= 0 && v <= 100000;
export function parseCompanyMissionTariff(value) {
  if (value == null) return { ok: true, tariff: null };
  const invalid = () => ({ ok: false, error: 'mission_tariff_invalid' });
  if (!keys(value,['version','enabled','depot','local_municipality','local_minimum_applies','default_vehicle_category','quote_only_month_days','minimum_per_minute_eur','waiting_per_minute_eur','categories','route_provider','price_rounding'])
    || value.version !== 1 || typeof value.enabled !== 'boolean'
    || (value.route_provider !== undefined && value.route_provider !== 'mapbox')
    || (value.price_rounding !== undefined && !['cent','nearest_euro'].includes(value.price_rounding))
    || !keys(value.depot,['lat','lng','label']) || !Number.isFinite(value.depot.lat) || Math.abs(value.depot.lat)>90
    || !Number.isFinite(value.depot.lng) || Math.abs(value.depot.lng)>180
    || (value.depot.label !== undefined && (typeof value.depot.label!=='string' || value.depot.label.length>320))
    || typeof value.local_municipality !== 'string' || !value.local_municipality.trim() || value.local_municipality.length>120
    || (value.local_minimum_applies != null && typeof value.local_minimum_applies !== 'boolean')
    || !money(value.minimum_per_minute_eur) || !money(value.waiting_per_minute_eur)
    || !Array.isArray(value.quote_only_month_days) || value.quote_only_month_days.length>366
    || !value.quote_only_month_days.every(d => typeof d === 'string' && /^\d{2}-\d{2}$/.test(d)
      && Number.isFinite(Date.parse(`2000-${d}T00:00:00Z`))
      && new Date(`2000-${d}T00:00:00Z`).toISOString().slice(5,10) === d)
    || !keys(value.categories,['car','minibus']) || !Object.keys(value.categories).length) return invalid();
  for (const category of Object.values(value.categories)) {
    if (!keys(category,['local_start_eur','local_per_km_eur','vehicle_ids','bands']) || !money(category.local_start_eur)
      || !money(category.local_per_km_eur) || !Array.isArray(category.bands) || !category.bands.length || category.bands.length>32) return invalid();
    if (category.vehicle_ids !== undefined && (!Array.isArray(category.vehicle_ids) || category.vehicle_ids.length>1000
      || !category.vehicle_ids.every(id => typeof id==='string' && id.trim()===id && id.length>0 && id.length<=128))) return invalid();
    for (const band of category.bands) {
      if (!keys(band,['min_km','max_km','min_inclusive','max_inclusive','fixed_eur','start_eur','per_km_eur'])
        || !(band.min_km === null || money(band.min_km)) || !(band.max_km === null || money(band.max_km))
        || (band.min_km !== null && band.max_km !== null && band.min_km>band.max_km)
        || typeof band.min_inclusive !== 'boolean' || typeof band.max_inclusive !== 'boolean') return invalid();
      if (band.fixed_eur !== undefined ? (!money(band.fixed_eur) || band.start_eur !== undefined || band.per_km_eur !== undefined)
        : (!money(band.start_eur) || !money(band.per_km_eur))) return invalid();
    }
  }
  if (value.default_vehicle_category !== undefined && !Object.hasOwn(value.categories,value.default_vehicle_category)) return invalid();
  const ids=Object.values(value.categories).flatMap(c=>c.vehicle_ids??[]);
  if (new Set(ids).size!==ids.length) return invalid();
  return { ok: true, tariff: structuredClone(value) };
}
