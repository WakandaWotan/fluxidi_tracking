// Only complete, bounded evidence may establish a previously missing owner.
// Shared by the read-only admin review and the serialized canonical adoption.
const fail = (code, status = 409) => { const error = new Error(code); error.code = code; error.status = status; return error; };
const object = value => value && typeof value === 'object' && !Array.isArray(value);
const validText = (value, max) => typeof value === 'string' && value.length > 0
  && value.length <= max && value === value.trim() && !/[\s\x00-\x1f\x7f]/.test(value);
export const validLegacyBookingId = value => validText(value, 160);

export function inspectLegacyOwnership(record) {
  const values = { tenant: [], company: [] }; let invalid = !object(record);
  for (const source of [record, record?.booking]) {
    if (source == null) continue;
    if (!object(source)) { invalid = true; continue; }
    for (const [part, names] of [['tenant', ['tenant_id', 'tenantId']], ['company', ['company_id', 'companyId']]]) {
      for (const name of names) {
        const value = source[name];
        if (value == null || value === '') continue;
        if (!validText(value, 80)) { invalid = true; continue; }
        if (!values[part].includes(value)) values[part].push(value);
      }
    }
  }
  return { tenant_raw: values.tenant[0] || '', company_raw: values.company[0] || '', invalid,
    conflicting: values.tenant.length > 1 || values.company.length > 1, values };
}

export function legacyOwnershipAgreesWithScope(record, scope) {
  const raw = inspectLegacyOwnership(record);
  return !raw.invalid && !raw.conflicting
    && raw.values.tenant.every(value => value === 'fluxidi' || value === scope.tenant_id)
    && raw.values.company.every(value => value === 'fluxidi' || value === scope.company_id);
}

export function unresolvedLegacyScopeTransition(record, bookingId) {
  return Boolean(record.alias_of || record.canonical_booking_id && record.canonical_booking_id !== bookingId
    || record.dispatch_search?.state === 'pending'
    || ['prepared', 'offered', 'received', 'committing'].includes(record.dispatch_offer?.state)
    || record.dispatch_transition || record.dispatch_transition_rollback || record.dispatch_capacity_pending
    || record.dispatch_assignment_revalidation || record.dispatch_offer_revalidation);
}

function stable(value) {
  if (Array.isArray(value)) return value.map(stable);
  if (!object(value)) return value;
  return Object.fromEntries(Object.keys(value).sort().map(key => [key, stable(value[key])]));
}
export async function legacyScopeEvidenceDigest(value) {
  const bytes = new TextEncoder().encode(JSON.stringify(stable(value)));
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return [...new Uint8Array(digest)].map(byte => byte.toString(16).padStart(2, '0')).join('');
}

export function checkedLegacyListPage(page, cursor = null) {
  if (!object(page) || !Array.isArray(page.keys) || typeof page.list_complete !== 'boolean'
    || page.keys.some(key => !object(key) || !validText(key.name, 360))) throw fail('legacy_scope_inventory_invalid');
  if (!page.list_complete && (!validText(page.cursor, 1024) || page.cursor === cursor)) {
    throw fail('legacy_scope_inventory_incomplete');
  }
  return { keys: page.keys.map(key => key.name), cursor: page.list_complete ? null : page.cursor,
    list_complete: page.list_complete };
}

export async function buildCompanyIndexMembershipMap(env, { maxIndexes = 200 } = {}) {
  if (!Number.isSafeInteger(maxIndexes) || maxIndexes < 1 || maxIndexes > 2000) throw fail('legacy_scope_inventory_limit');
  const membership = new Map(), snapshots = [], seenKeys = new Set(), seenCursors = new Set();
  let cursor = null, pages = 0, entries = 0;
  do {
    if (++pages > 100) throw fail('legacy_scope_inventory_limit');
    const page = checkedLegacyListPage(await env.BOOKING_KV.list({ prefix: 'tenant:', limit: 1000,
      ...(cursor ? { cursor } : {}) }), cursor);
    for (const key of page.keys) {
      if (!key.endsWith(':bookings:list:v1') || seenKeys.has(key)) continue;
      const parsed = key.match(/^tenant:([^:]+):company:([^:]+):bookings:list:v1$/);
      if (!parsed || !validText(parsed[1], 80) || !validText(parsed[2], 80)
        || parsed[1] === 'fluxidi' || parsed[2] === 'fluxidi') throw fail('legacy_scope_inventory_invalid');
      if (seenKeys.size >= maxIndexes) throw fail('legacy_scope_inventory_limit');
      seenKeys.add(key);
      const index = await env.BOOKING_KV.get(key, { type: 'json' });
      if (!object(index) || !Array.isArray(index.items)) throw fail('legacy_scope_inventory_invalid');
      snapshots.push({ key, index });
      const seenIds = new Set();
      for (const entry of index.items) {
        if (++entries > 10000) throw fail('legacy_scope_inventory_limit');
        const id = entry?.booking_id ?? entry?.bookingId;
        if (!object(entry) || !validLegacyBookingId(id)
          || (entry.booking_id != null && entry.bookingId != null && entry.booking_id !== entry.bookingId)) {
          throw fail('legacy_scope_inventory_invalid');
        }
        if (seenIds.has(id)) continue;
        seenIds.add(id);
        const owners = membership.get(id) || [];
        owners.push({ tenant_id: parsed[1], company_id: parsed[2], index_key: key });
        membership.set(id, owners);
      }
    }
    cursor = page.cursor;
    if (cursor && seenCursors.has(cursor)) throw fail('legacy_scope_inventory_incomplete');
    if (cursor) seenCursors.add(cursor);
  } while (cursor);
  return { membership, scopes: snapshots.map(({ key }) => {
    const parts = key.match(/^tenant:([^:]+):company:([^:]+):bookings:list:v1$/);
    return { tenant_id: parts[1], company_id: parts[2] };
  }), indexes_scanned: seenKeys.size, complete: true,
    inventory_digest: await legacyScopeEvidenceDigest(snapshots.sort((a, b) => a.key.localeCompare(b.key))) };
}

export function applyProvenLegacyOwnership(record, scope, recordDigest) {
  const next = { ...record, ...scope, tenantId: scope.tenant_id, companyId: scope.company_id };
  if (object(record.booking)) next.booking = { ...record.booking, ...scope, tenantId: scope.tenant_id, companyId: scope.company_id };
  next.legacy_scope_migrated_at = new Date().toISOString();
  next.legacy_scope_migration_source = 'company_list_index';
  next.legacy_scope_migration_record_digest = recordDigest;
  return next;
}
