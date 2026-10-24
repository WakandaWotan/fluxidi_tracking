// The caller must load the canonical index for its authenticated company scope.
// Legacy rows may omit scope tags; explicit tags must never contradict that key.
const object = value => value && typeof value === 'object' && !Array.isArray(value);
const text = value => String(value ?? '').trim();
const safeId = value => /^[a-zA-Z0-9_.-]{1,96}$/.test(value);

function scopeMatches(row, scope) {
  return ['tenant_id', 'tenantId'].every(key => !text(row[key]) || text(row[key]) === scope.tenant_id)
    && ['company_id', 'companyId'].every(key => !text(row[key]) || text(row[key]) === scope.company_id);
}

export function scopedDriverDirectoryRecord(record, scope) {
  const scoped = { tenant_id: text(scope?.tenant_id), company_id: text(scope?.company_id) };
  if (!object(record) || !safeId(scoped.tenant_id) || !safeId(scoped.company_id)
    || !scopeMatches(record, scoped)) return { drivers: {}, registered_count: 0 };
  const source = object(record.drivers) ? record.drivers : {};
  const deleted = object(record.deleted_drivers) ? record.deleted_drivers
    : object(record.deletedDrivers) ? record.deletedDrivers : {};
  const entries = Object.entries(source).filter(([id, row]) => safeId(id) && object(row)
    && !deleted[id] && scopeMatches(row, scoped)
    && ['driver_id', 'driverId'].every(key => !text(row[key]) || text(row[key]) === id));
  if (entries.length === Object.keys(source).length) return record;
  return { ...record, drivers: Object.fromEntries(entries), registered_count: entries.length };
}
