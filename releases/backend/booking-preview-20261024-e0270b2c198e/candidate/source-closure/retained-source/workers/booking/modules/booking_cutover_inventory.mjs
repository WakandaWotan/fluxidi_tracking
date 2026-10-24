import { readLegacyBookingScopeMigrationRecord } from './canonical_booking_authority.mjs';
import { buildCompanyIndexMembershipMap, inspectLegacyOwnership, legacyScopeEvidenceDigest } from './legacy_scope_evidence.mjs';

// Company list indexes alone do not prove the full set of record owners.
// This bounded admin scan inspects every booking without adopting/repairing it.
export async function inspectBookingCutoverInventory(env) {
  const index = await buildCompanyIndexMembershipMap(env);
  const names = new Set(), cursors = new Set(); let cursor = null, complete = false;
  for (let pageNumber = 0; pageNumber < 100; pageNumber++) {
    const page = await env.BOOKING_KV.list({ prefix: 'booking:', limit: 1000, ...(cursor ? { cursor } : {}) });
    if (!Array.isArray(page?.keys) || typeof page.list_complete !== 'boolean') throw Error('cutover_inventory_invalid');
    for (const key of page.keys) {
      if (typeof key?.name !== 'string' || !key.name.startsWith('booking:') || key.name.length <= 8 || key.name.length > 168
        || /\s/.test(key.name) || names.has(key.name)) throw Error('cutover_inventory_invalid');
      names.add(key.name);
    }
    if (names.size > 10000) throw Error('cutover_inventory_limit');
    if (page.list_complete) { complete = true; break; }
    if (typeof page.cursor !== 'string' || !page.cursor || cursors.has(page.cursor)) throw Error('cutover_inventory_incomplete');
    cursors.add(page.cursor); cursor = page.cursor;
  }
  if (!complete) throw Error('cutover_inventory_incomplete');
  const scopes = new Map(), unresolved = [], evidence = [];
  function add(scope, indexed = false) {
    const name = JSON.stringify([scope.tenant_id, scope.company_id]);
    if (!scopes.has(name)) scopes.set(name, { ...scope, records: 0, has_company_index: false });
    const value = scopes.get(name); value.has_company_index ||= indexed; return value;
  }
  for (const scope of index.scopes) add(scope, true);
  const sorted = [...names].sort();
  for (let offset = 0; offset < sorted.length; offset += 4) {
    const batch = sorted.slice(offset, offset + 4);
    const records = await Promise.all(batch.map(name => readLegacyBookingScopeMigrationRecord(env, name.slice(8))));
    for (let i = 0; i < batch.length; i++) {
      const id = batch[i].slice(8), record = records[i].record;
      if (!record) throw Error('cutover_inventory_record_missing');
      const owner = inspectLegacyOwnership(record);
      evidence.push([id, await legacyScopeEvidenceDigest(record)]);
      if (owner.invalid || owner.conflicting || !owner.tenant_raw || !owner.company_raw
        || owner.tenant_raw === 'fluxidi' || owner.company_raw === 'fluxidi') {
        unresolved.push({ booking_id: id, error: 'cutover_inventory_owner_unresolved' }); continue;
      }
      const scope = { tenant_id: owner.tenant_raw, company_id: owner.company_raw };
      add(scope).records++;
      if ((index.membership.get(id) || []).some(value => value.tenant_id !== scope.tenant_id || value.company_id !== scope.company_id))
        unresolved.push({ booking_id: id, error: 'cutover_inventory_index_owner_conflict' });
    }
  }
  for (const id of index.membership.keys()) if (!names.has(`booking:${id}`))
    unresolved.push({ booking_id: id, error: 'cutover_inventory_index_record_missing' });
  const ordered = [...scopes.values()].sort((a, b) => JSON.stringify(a).localeCompare(JSON.stringify(b)));
  return { ok: true, dry_run: true, complete: true, scanned: names.size, indexes_scanned: index.indexes_scanned,
    scopes: ordered, unresolved, inventory_digest: await legacyScopeEvidenceDigest({ evidence, index_digest: index.inventory_digest }) };
}
