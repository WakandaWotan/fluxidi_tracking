import { agendaCapacityClaims } from './company_agenda.mjs';
import { companyBookingsListIndexKey } from './booking_indexes.js';
import { companyTrackingObjectName } from '../../tracking/modules/company_tracking_room.mjs';
import { operationalLegsOf, isCapacityBlockingLeg } from './company_roundtrip.mjs';
import { readCompanyBookingInventoryRecord } from './canonical_booking_authority.mjs';
import { sameCheckpointClaims } from './company_capacity_checkpoint.mjs';

const TERMINAL = new Set(['COMPLETED', 'CANCELLED', 'CANCELED', 'NO_SHOW', 'REJECTED', 'EXPIRED']);

// One-time, bounded migration, never on availability polling. A complete key
// inventory plus the company index avoids relying on a truncated UI page.
export async function prepareCompanyCapacityBaseline(env, scope) {
  if (!env.BOOKING_KV?.list || !scope.tenant_id || !scope.company_id) throw Error('capacity_inventory_unavailable');
  const names = new Set();
  let cursor;
  const cursors = new Set();
  for (let pageNumber = 0; pageNumber < 100; pageNumber++) {
    const page = await env.BOOKING_KV.list({ prefix: 'booking:', limit: 1000, ...(cursor ? { cursor } : {}) });
    if (!Array.isArray(page.keys)) throw Error('capacity_inventory_invalid');
    for (const key of page.keys) {
      if (typeof key.name !== 'string' || !key.name.startsWith('booking:')) throw Error('capacity_inventory_invalid');
      names.add(key.name);
    }
    if (names.size > 10000) throw Error('capacity_inventory_limit');
    if (page.list_complete === true) { cursor = null; break; }
    if (!page.cursor || cursors.has(page.cursor)) throw Error('capacity_inventory_incomplete');
    cursors.add(page.cursor); cursor = page.cursor;
  }
  if (cursor !== null) throw Error('capacity_inventory_incomplete');
  const index = await env.BOOKING_KV.get(companyBookingsListIndexKey(scope), { type: 'json' });
  if (index && !Array.isArray(index.items)) throw Error('capacity_inventory_invalid');
  const indexed = new Set();
  for (const item of index?.items || []) {
    const id = item.booking_id || item.bookingId;
    if (!id || typeof id !== 'string') throw Error('capacity_inventory_invalid');
    names.add(`booking:${id}`);
    indexed.add(id);
  }
  if (names.size > 10000) throw Error('capacity_inventory_limit');
  const bookings = [], records = [], unresolved = [];
  const keys = [...names].sort();
  const aliases = new Map(), foreign = new Set();
  // Bounded fan-out; no 10,000 simultaneous KV requests.
  for (let offset = 0; offset < keys.length;) {
    const batch = keys.slice(offset, offset + 8);
    const values = await Promise.all(batch.map(key => readCompanyBookingInventoryRecord(env, scope, key.slice('booking:'.length))));
    for (let index = 0; index < batch.length; index++) {
      const id = batch[index].slice('booking:'.length);
      if (values[index].foreign) {
        foreign.add(id);
        if (indexed.has(id)) throw Error('capacity_inventory_index_scope_conflict');
        continue;
      }
      const record = values[index].record;
      if (!record) throw Error('capacity_inventory_record_missing');
      if (record.tenant_id !== scope.tenant_id || record.company_id !== scope.company_id) throw Error('capacity_inventory_scope_unresolved');
      records.push([id, record]);
      if (record.cancelled_leg_reconciliation?.state && record.cancelled_leg_reconciliation.state !== 'completed') {
        unresolved.push({ booking_id: id, error: 'cancelled_leg_publication_pending' });
        continue;
      }
      const targets = [record.alias_of, record.canonical_booking_id !== id ? record.canonical_booking_id : null]
        .filter(value => value != null && value !== '');
      if (targets.length) {
        if (targets.some(target => typeof target !== 'string' || !target || target.length > 160 || /\s/.test(target))
          || new Set(targets).size !== 1) throw Error('capacity_inventory_alias_invalid');
        const target = targets[0];
        aliases.set(id, target);
        const key = `booking:${target}`;
        if (!names.has(key)) {
          names.add(key);
          if (names.size > 10000) throw Error('capacity_inventory_limit');
          keys.push(key);
        }
        continue;
      }
      if (TERMINAL.has(String(record.status || record.booking?.status || '').toUpperCase())) {
        if (operationalLegsOf(record).some(isCapacityBlockingLeg)) {
          unresolved.push({ booking_id: id, error: 'capacity_parent_leg_lifecycle_conflict' });
        }
        if (record.dispatch_capacity_checkpoint?.claims?.length) {
          unresolved.push({ booking_id: id, error: 'capacity_checkpoint_conflict' });
        }
        continue;
      }
      const built = agendaCapacityClaims(record, id);
      if (!built.ok) { unresolved.push({ booking_id: id, error: built.error }); continue; }
      const checkpoint = record.dispatch_capacity_checkpoint;
      if (checkpoint && (!Number.isSafeInteger(checkpoint.version) || checkpoint.version < 1
        || checkpoint.version > (Number(record.revision) || 1) + 1
        || !sameCheckpointClaims(checkpoint.claims, built.claims))) {
        unresolved.push({ booking_id: id, error: 'capacity_checkpoint_conflict' });
        continue;
      }
      if (!built.claims.length) continue;
      // Metadata/dispatch revisions can advance without changing the physical
      // hold. Bootstrap must preserve its positively persisted generation.
      bookings.push({ owner_id: id, version: checkpoint?.version || (Number(record.revision) || 1) + 1, claims: built.claims });
    }
    offset += batch.length;
  }
  const resolvedAliases = new Map();
  for (const id of aliases.keys()) {
    const chain = new Set(); let target = id;
    while (aliases.has(target) && !resolvedAliases.has(target)) {
      if (chain.has(target)) throw Error('capacity_inventory_alias_cycle');
      chain.add(target); target = aliases.get(target);
    }
    target = resolvedAliases.get(target) || target;
    if (foreign.has(target)) throw Error('capacity_inventory_alias_scope_conflict');
    for (const alias of chain) resolvedAliases.set(alias, target);
  }
  records.sort((a, b) => a[0].localeCompare(b[0]));
  const bytes = new TextEncoder().encode(JSON.stringify(records));
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  const inventory_digest = [...new Uint8Array(digest)].map(n => n.toString(16).padStart(2, '0')).join('');
  return { inventory_digest, bookings, unresolved, scanned: keys.length, scoped_records: records.length };
}

export async function initializeCompanyCapacityBaseline(env, scope, { inventoryDigest } = {}) {
  if (!env.COMPANY_TRACKING) return { ok: false, error: 'capacity_commit_unavailable' };
  const snapshot = await prepareCompanyCapacityBaseline(env, scope);
  if (snapshot.unresolved.length) return { ok: false, error: 'capacity_inventory_unresolved', unresolved: snapshot.unresolved };
  if (!inventoryDigest || inventoryDigest !== snapshot.inventory_digest) return { ok: false, error: 'capacity_inventory_changed' };
  const room = env.COMPANY_TRACKING.get(env.COMPANY_TRACKING.idFromName(companyTrackingObjectName(scope.tenant_id, scope.company_id)));
  const response = await room.fetch('https://room/capacity-baseline', { method: 'POST',
    headers: { 'content-type': 'application/json' }, body: JSON.stringify({ ...scope,
      inventory_verified: true, inventory_digest: snapshot.inventory_digest, bookings: snapshot.bookings }) });
  const result = await response.json();
  return response.ok && result.ok === true && result.committed === true ? { ok: true, inventory_digest: snapshot.inventory_digest,
    initialized_bookings: snapshot.bookings.length, already_initialized: result.already_initialized === true }
    : { ok: false, error: result.error || 'capacity_commit_unavailable' };
}
