// Shared company-DO cache of public bootstrap revisions. A missing/evicted
// revision or a restart returns a full reset, never an incomplete delta.
export function createCompanyFleetDelta({ maxRevisions = 8, maxBytes = 8 * 1024 * 1024 } = {}) {
  if (!Number.isInteger(maxRevisions) || maxRevisions < 1 || !Number.isFinite(maxBytes) || maxBytes < 1)
    throw Error('fleet_delta_limits_invalid');
  const revisions = new Map(); let storedBytes = 0, scopeKey = null;
  return {
    diagnostics: () => ({ revisions: revisions.size, bytes: storedBytes }),
    async resolve(scope, payload, since = '') {
      const key = JSON.stringify([scope?.tenant_id, scope?.company_id]);
      if (!scope?.tenant_id || !scope?.company_id || scopeKey && scopeKey !== key) throw Error('fleet_delta_scope_conflict');
      scopeKey = key;
      const json = JSON.stringify({ scope, drivers: payload.drivers || [], vehicles: payload.vehicles || [] });
      const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(json));
      const revision = [...new Uint8Array(digest)].map(value => value.toString(16).padStart(2, '0')).join('');
      if (since === revision) return { ok: true, sync_contract_version: 1, mode: 'unchanged', revision };
      const old = revisions.get(since), size = new TextEncoder().encode(json).byteLength;
      if (!revisions.has(revision) && size <= maxBytes) {
        while (revisions.size >= maxRevisions || storedBytes + size > maxBytes) {
          const first = revisions.keys().next().value; storedBytes -= revisions.get(first).size; revisions.delete(first);
        }
        revisions.set(revision, { json, size }); storedBytes += size;
      }
      const result = { ok: true, sync_contract_version: 1, revision, base_revision: since || null };
      if (!old) return { ...result, mode: 'full', reset: Boolean(since), drivers: payload.drivers || [], vehicles: payload.vehicles || [], deleted_drivers: [], deleted_vehicles: [] };
      const previous = JSON.parse(old.json);
      const delta = (current, prior, id) => {
        const before = new Map(prior.map(row => [row[id], JSON.stringify(row)])), after = new Set(current.map(row => row[id]));
        return { changed: current.filter(row => before.get(row[id]) !== JSON.stringify(row)), deleted: prior.filter(row => !after.has(row[id])).map(row => row[id]) };
      };
      const drivers = delta(payload.drivers || [], previous.drivers, 'driver_id'), vehicles = delta(payload.vehicles || [], previous.vehicles, 'vehicle_id');
      return { ...result, mode: 'delta', drivers: drivers.changed, vehicles: vehicles.changed,
        deleted_drivers: drivers.deleted, deleted_vehicles: vehicles.deleted };
    },
  };
}
