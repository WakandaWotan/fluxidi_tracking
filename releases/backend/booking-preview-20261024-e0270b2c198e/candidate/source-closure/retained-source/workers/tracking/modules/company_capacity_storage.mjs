// Private per-company storage. Cold records retain replay/version evidence;
// compaction never derives availability from time or missing booking data.
export const CAPACITY_STORAGE_KEY = 'company_capacity_ledger_v1';
export const CAPACITY_ARCHIVE_AFTER_MS = 24 * 60 * 60_000;
export const CAPACITY_SNAPSHOT_MAX_BYTES = 8 * 1024 * 1024;
const INLINE_BYTES = 80 * 1024;
const PAGE_CHARS = 24 * 1024;
const ARCHIVE_BATCH = 96;
const FORMAT = 'company-capacity-pages-v2';
const encoder = new TextEncoder();
const tables = { owner: 'owners', offer: 'offers', event: 'dispatch_events' };
const validMap = value => value && typeof value === 'object' && !Array.isArray(value);
const bytes = value => encoder.encode(value);
async function digest(text) {
  return [...new Uint8Array(await crypto.subtle.digest('SHA-256', bytes(text)))]
    .map(value => value.toString(16).padStart(2, '0')).join('');
}
export async function capacityArchiveKey(kind, id) {
  if (!tables[kind] || typeof id !== 'string' || !id || id.length > 500) throw Error('capacity_archive_identity_invalid');
  return `capacity_archive_v1:${kind}:${await digest(id)}`;
}
function validateLedger(ledger) {
  if (!validMap(ledger) || !validMap(ledger.claims) || !validMap(ledger.owners)) throw Error('capacity_storage_invalid');
  return ledger;
}
function manifestPages(root) {
  if (!Array.isArray(root.pages) || !root.pages.length || root.pages.length > 1024
    || typeof root.generation !== 'string' || !/^[a-f\d-]{36}$/.test(root.generation)
    || !Number.isSafeInteger(root.bytes) || root.bytes < 1 || root.bytes > CAPACITY_SNAPSHOT_MAX_BYTES
    || !/^[a-f\d]{64}$/.test(root.sha256 || '')
    || root.pages.some((key, i) => key !== `capacity_page_v2:${root.generation}:${i}`)) throw Error('capacity_snapshot_manifest_invalid');
  return root.pages;
}

export async function readCapacitySnapshot(storage) {
  const root = await storage.get(CAPACITY_STORAGE_KEY);
  if (root == null) return { claims: {}, owners: {} };
  if (root.format !== FORMAT) return validateLedger(root);
  manifestPages(root);
  const parts = [];
  for (let i = 0; i < root.pages.length; i++) {
    const key = `capacity_page_v2:${root.generation}:${i}`;
    const part = await storage.get(key);
    if (typeof part !== 'string' || part.length > PAGE_CHARS) throw Error('capacity_snapshot_page_missing');
    parts.push(part);
  }
  const text = parts.join('');
  if (bytes(text).length !== root.bytes || await digest(text) !== root.sha256) throw Error('capacity_snapshot_checksum_invalid');
  return validateLedger(JSON.parse(text));
}

// All reads happen inside the Room mutation queue. A failed cold read refuses
// the mutation; it can never substitute an empty owner/version/offer.
export async function hydrateCapacityRecords(storage, ledger, identities, scope) {
  let next = ledger;
  const pending = Object.entries(identities).flatMap(([kind, ids]) => ids.map(id => [kind, id]));
  const seen = new Set();
  for (let i = 0; i < pending.length; i++) {
    const [kind, id] = pending[i], table = tables[kind];
    if (!table || typeof id !== 'string' || !id || id.length > 500 || seen.has(`${kind}:${id}`)) continue;
    seen.add(`${kind}:${id}`);
    let row = next[table]?.[id];
    if (!Object.hasOwn(next[table] || {}, id)) {
      const archived = await storage.get(await capacityArchiveKey(kind, id));
      if (archived == null) continue;
      row = archived.record;
      if (archived.kind !== kind || archived.id !== id || !validMap(row)
        || row.tenant_id !== scope.tenant_id || row.company_id !== scope.company_id
        || kind === 'owner' && (!Number.isSafeInteger(row.version) || row.version < 1 || row.pending || !row.released)
        || kind === 'offer' && row.offer_id !== id || kind === 'event' && row.event_id !== id) {
        throw Error('capacity_archive_record_invalid');
      }
      next = { ...next, [table]: { ...next[table], [id]: row } };
    }
    if (row.owner_id) pending.push(['owner', row.owner_id]);
    if (kind === 'event' && row.offer_id && row.type !== 'dispatch_search') pending.push(['offer', row.offer_id]);
  }
  return next;
}

function compact(ledger, previous, nowMs) {
  const owners = { ...ledger.owners }, events = { ...ledger.dispatch_events }, offers = { ...ledger.offers };
  // Give legacy rows a full grace period. Changed owners and newly delivered
  // events start a fresh grace period, rather than inheriting their creation.
  for (const [id, owner] of Object.entries(owners)) {
    if (!Number.isFinite(owner.storage_updated_at_ms) || JSON.stringify(owner) !== JSON.stringify(previous.owners[id])) {
      owners[id] = { ...owner, storage_updated_at_ms: nowMs };
    }
  }
  for (const [id, event] of Object.entries(events)) {
    if (event.state === 'delivered' && (!Number.isFinite(event.storage_delivered_at_ms)
      || previous.dispatch_events?.[id]?.state !== 'delivered')) events[id] = { ...event, storage_delivered_at_ms: nowMs };
  }
  const hot = new Set(Object.values(ledger.claims).map(claim => claim.owner_id));
  for (const offer of Object.values(offers)) {
    if (['offered', 'received', 'committing'].includes(offer.state)) hot.add(offer.owner_id);
  }
  for (const event of Object.values(events)) if (event.state !== 'delivered') hot.add(event.owner_id);
  const cutoff = nowMs - CAPACITY_ARCHIVE_AFTER_MS;
  const cold = new Set(Object.entries(owners).filter(([id, owner]) => !hot.has(id)
    && owner.released === true && owner.pending === false && owner.storage_updated_at_ms <= cutoff).map(([id]) => id));
  const archive = [];
  const retire = (kind, table, id) => { archive.push({ kind, id, record: table[id] }); delete table[id]; };
  for (const [id, offer] of Object.entries(offers)) {
    if (archive.length >= ARCHIVE_BATCH) break;
    if (cold.has(offer.owner_id)) retire('offer', offers, id);
  }
  for (const [id, event] of Object.entries(events)) {
    if (archive.length >= ARCHIVE_BATCH) break;
    if (event.state === 'delivered' && (cold.has(event.owner_id)
      || event.type === 'dispatch_search' && !hot.has(event.owner_id) && event.storage_delivered_at_ms <= cutoff)) retire('event', events, id);
  }
  // Retain each owner's high-water mark in hot state until all its archived
  // references have moved. A single heavily retried booking cannot create an
  // unbounded archival transaction or permanently block compaction progress.
  const referenced = new Set([...Object.values(offers), ...Object.values(events)].map(row => row.owner_id));
  for (const id of cold) {
    if (archive.length >= ARCHIVE_BATCH) break;
    if (!referenced.has(id)) retire('owner', owners, id);
  }
  return { ledger: { ...ledger, owners, ...(ledger.offers ? { offers } : {}),
    ...(ledger.dispatch_events ? { dispatch_events: events } : {}) }, archive };
}

export async function writeCapacitySnapshot(storage, ledger, previous, nowMs) {
  const planned = compact(validateLedger(ledger), previous, nowMs);
  const text = JSON.stringify(planned.ledger), length = bytes(text).length;
  if (length > CAPACITY_SNAPSHOT_MAX_BYTES) throw Error('capacity_snapshot_too_large');
  const existing = await storage.get(CAPACITY_STORAGE_KEY);
  const oldPages = existing?.format === FORMAT ? manifestPages(existing) : [];
  const entries = [];
  for (const row of planned.archive) {
    if (bytes(JSON.stringify(row)).length > INLINE_BYTES) throw Error('capacity_archive_record_too_large');
    entries.push([await capacityArchiveKey(row.kind, row.id), row]);
  }
  let root = planned.ledger;
  if (length > INLINE_BYTES) {
    const generation = crypto.randomUUID(), pages = [];
    for (let at = 0; at < text.length; at += PAGE_CHARS) {
      const key = `capacity_page_v2:${generation}:${pages.length}`;
      entries.push([key, text.slice(at, at + PAGE_CHARS)]); pages.push(key);
    }
    root = { format: FORMAT, generation, pages, bytes: length, sha256: await digest(text) };
  }
  const commit = async txn => {
    for (const [key, value] of entries) await txn.put(key, value);
    // The pointer is published last. A read sees either the previous complete
    // snapshot or this complete snapshot, never a partially replaced page set.
    await txn.put(CAPACITY_STORAGE_KEY, root);
    for (const key of oldPages) await txn.delete(key);
  };
  if (typeof storage.transaction === 'function') await storage.transaction(commit);
  else {
    // Compatibility for old small in-memory test storage adapters. Production
    // paging/archival requires the real Durable Object transaction API.
    if (entries.length || oldPages.length) throw Error('capacity_storage_transaction_required');
    await storage.put(CAPACITY_STORAGE_KEY, root);
  }
  return planned.ledger;
}
