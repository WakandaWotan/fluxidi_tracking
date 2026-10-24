import { grantKey, TERMINAL_PHASES } from './customer_live_snapshot.mjs';

export const CUSTOMER_GRANT_STORAGE_KEY = 'customer_grants_v1';
export const CUSTOMER_GRANT_ARCHIVE_AFTER_MS = 24 * 60 * 60_000;
export const CUSTOMER_GRANT_SNAPSHOT_MAX_BYTES = 8 * 1024 * 1024;
const FORMAT = 'customer-grant-pages-v2';
const INLINE_BYTES = 80 * 1024, PAGE_CHARS = 24 * 1024, ARCHIVE_BATCH = 96;
const encoder = new TextEncoder();
const bytes = text => encoder.encode(text);
const map = value => value && typeof value === 'object' && !Array.isArray(value);
const sameScope = (a, b) => a?.tenant_id === b?.tenant_id && a?.company_id === b?.company_id;
async function digest(text) {
  return [...new Uint8Array(await crypto.subtle.digest('SHA-256', bytes(text)))]
    .map(value => value.toString(16).padStart(2, '0')).join('');
}
export async function customerGrantArchiveKey(key) {
  if (typeof key !== 'string' || !key || key.length > 300) throw Error('customer_grant_identity_invalid');
  return 'customer_grant_archive_v1:' + await digest(key);
}
function validateStore(store) {
  if (!map(store) || !map(store.grants)) throw Error('customer_grant_storage_invalid');
  return store;
}
function manifestPages(root) {
  if (!Array.isArray(root.pages) || !root.pages.length || root.pages.length > 1024
    || !/^[a-f\d-]{36}$/.test(root.generation || '')
    || !Number.isSafeInteger(root.bytes) || root.bytes < 1 || root.bytes > CUSTOMER_GRANT_SNAPSHOT_MAX_BYTES
    || !/^[a-f\d]{64}$/.test(root.sha256 || '')
    || root.pages.some((key, i) => key !== `customer_grant_page_v2:${root.generation}:${i}`)) {
    throw Error('customer_grant_manifest_invalid');
  }
  return root.pages;
}
export async function readCustomerGrantSnapshot(storage) {
  const root = await storage.get(CUSTOMER_GRANT_STORAGE_KEY);
  if (root == null) return { grants: {} };
  if (root.format !== FORMAT) return validateStore(root);
  const parts = [];
  for (const key of manifestPages(root)) {
    const part = await storage.get(key);
    if (typeof part !== 'string' || part.length > PAGE_CHARS) throw Error('customer_grant_page_missing');
    parts.push(part);
  }
  const text = parts.join('');
  if (bytes(text).length !== root.bytes || await digest(text) !== root.sha256) throw Error('customer_grant_checksum_invalid');
  return validateStore(JSON.parse(text));
}

// Cold state is read for exactly the requested booking/leg. Retired aliases and
// closed assignment clocks must survive eviction, expiry and delayed messages.
export async function readStoredCustomerGrant(storage, store, key, scope) {
  if (Object.hasOwn(store.grants, key)) return store.grants[key];
  const cold = await storage.get(await customerGrantArchiveKey(key));
  if (cold == null) return null;
  const row = cold.record;
  if (cold.key !== key || !sameScope(cold.scope, scope) || !map(row)
    || !/^[a-f\d]{64}$/.test(cold.sha256 || '') || await digest(JSON.stringify(row)) !== cold.sha256
    || row.position_allowed === true || !(row.leg_scope_retired || TERMINAL_PHASES.has(row.tracking_phase))
    || row.tenant_id && row.tenant_id !== scope.tenant_id || row.company_id && row.company_id !== scope.company_id
    || !row.leg_scope_retired && (!sameScope(row, scope) || grantKey(row.booking_id, row.operational_leg) !== key
      || !Number.isFinite(row.lifecycle_seq) || !Number.isFinite(row.assignment_version))) {
    throw Error('customer_grant_archive_invalid');
  }
  return row;
}

export async function hydrateCustomerGrantEvent(storage, store, event, scope) {
  const keys = [grantKey(event.booking_id, event.operational_leg)];
  if (event.disable_primary === true && event.operational_leg && event.operational_leg !== 'primary') {
    keys.push(grantKey(event.booking_id, 'primary'));
  }
  let next = store;
  for (const key of keys) {
    if (Object.hasOwn(next.grants, key)) continue;
    const row = await readStoredCustomerGrant(storage, next, key, scope);
    if (row) next = { ...next, grants: { ...next.grants, [key]: row } };
  }
  return next;
}

export async function writeCustomerGrantSnapshot(storage, store, nowMs) {
  validateStore(store);
  const next = { ...store, grants: { ...store.grants } }, archive = [];
  for (const [key, original] of Object.entries(next.grants)) {
    if (!map(original)) throw Error('customer_grant_storage_invalid');
    let row = original;
    const closed = row.position_allowed !== true && (row.leg_scope_retired || TERMINAL_PHASES.has(row.tracking_phase));
    let updated = Date.parse(row.updated_at || '');
    // Legacy alias tombstones without a timestamp get a full grace period.
    if (closed && !Number.isFinite(updated)) {
      row = { ...row, updated_at: new Date(nowMs).toISOString() }; next.grants[key] = row; updated = nowMs;
    }
    if (closed && updated <= nowMs - CUSTOMER_GRANT_ARCHIVE_AFTER_MS && archive.length < ARCHIVE_BATCH) {
      if (!store.scope?.tenant_id || !store.scope?.company_id) throw Error('customer_grant_archive_scope_required');
      const text = JSON.stringify(row);
      if (bytes(text).length > INLINE_BYTES) throw Error('customer_grant_archive_too_large');
      archive.push([await customerGrantArchiveKey(key), { key, scope: store.scope, record: row, sha256: await digest(text) }]);
      delete next.grants[key];
    }
  }
  const text = JSON.stringify(next), length = bytes(text).length;
  if (length > CUSTOMER_GRANT_SNAPSHOT_MAX_BYTES) throw Error('customer_grant_snapshot_too_large');
  const previous = await storage.get(CUSTOMER_GRANT_STORAGE_KEY);
  const oldPages = previous?.format === FORMAT ? manifestPages(previous) : [];
  const entries = [...archive]; let root = next;
  if (length > INLINE_BYTES) {
    const generation = crypto.randomUUID(), pages = [];
    for (let at = 0; at < text.length; at += PAGE_CHARS) {
      const key = `customer_grant_page_v2:${generation}:${pages.length}`;
      entries.push([key, text.slice(at, at + PAGE_CHARS)]); pages.push(key);
    }
    root = { format: FORMAT, generation, pages, bytes: length, sha256: await digest(text) };
  }
  const commit = async txn => {
    for (const [key, value] of entries) await txn.put(key, value);
    // Publish the complete state only after pages and revoked-access evidence.
    await txn.put(CUSTOMER_GRANT_STORAGE_KEY, root);
    for (const key of oldPages) await txn.delete(key);
  };
  if (typeof storage.transaction === 'function') await storage.transaction(commit);
  else {
    // Small old test adapters retain their existing single-value contract.
    if (entries.length || oldPages.length) throw Error('customer_grant_transaction_required');
    await storage.put(CUSTOMER_GRANT_STORAGE_KEY, root);
  }
  return next;
}
