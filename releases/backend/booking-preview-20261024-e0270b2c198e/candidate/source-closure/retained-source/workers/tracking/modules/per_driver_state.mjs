// A single DO owns this store. Its request queue supplies ordering; the
// transaction makes a driver row and the lightweight revision durable together.
// Minimal get/put adapters retain the legacy format for backwards compatibility.
export function createPerDriverState(storage, legacyKey, prefix, { extract = value => value, wrap = value => value, onWrite } = {}) {
  const partitioned = typeof storage.list === 'function' && typeof storage.transaction === 'function';
  let rows, metadata, loading;
  const key = id => prefix + encodeURIComponent(id);
  async function load() {
    if (rows) return rows;
    loading ||= (async () => {
      const raw = await storage.get(legacyKey);
      if (!partitioned) { rows = extract(raw || {}) || {}; metadata = { updated_at: raw?.updated_at }; return rows; }
      if (raw?.format === 'per-driver-v2') {
        const recovered = {}; let startAfter = '';
        for (;;) {
          const page = await storage.list({ prefix, startAfter, limit: 1000 });
          for (const [recordKey, row] of page) recovered[decodeURIComponent(recordKey.slice(prefix.length))] = row;
          if (page.size < 1000) break;
          startAfter = [...page.keys()].at(-1);
        }
        rows = recovered; metadata = raw; return rows;
      }
      const legacy = extract(raw && typeof raw === 'object' ? raw : {}) || {};
      // Adopt in bounded batches while the legacy blob remains authoritative.
      // Restart retries the same copy; only the final pointer activates rows.
      const marker = { format: 'per-driver-v2', revision: 1, ...(raw?.updated_at ? { updated_at: raw.updated_at } : {}) };
      const records = Object.entries(legacy);
      // Reading an untouched empty Room must stay read-only, especially when
      // a capacity-initialization request is rejected. First valid row write
      // persists its row and marker atomically instead of adopting nothing.
      if (raw == null && !records.length) { rows = {}; metadata = marker; return rows; }
      const progressKey = legacyKey + ':adoption-v2';
      const digestBytes = await crypto.subtle.digest('SHA-256',new TextEncoder().encode(JSON.stringify(legacy)));
      const digest = [...new Uint8Array(digestBytes)].map(byte=>byte.toString(16).padStart(2,'0')).join('');
      const progress = await storage.get(progressKey);
      if(progress && (progress.digest!==digest || !Number.isSafeInteger(progress.offset) || progress.offset<0 || progress.offset>records.length))throw Error('driver_state_adoption_generation_changed');
      for (let offset = progress?.offset || 0; offset < records.length; offset += 126) {
        await storage.transaction(async tx => {
          for (const [id, row] of records.slice(offset, offset + 126)) await tx.put(key(id), row);
          await tx.put(progressKey,{digest,offset:Math.min(records.length,offset+126)});
        });
      }
      await storage.transaction(async tx => {await tx.put(legacyKey,marker);await tx.delete(progressKey);});
      rows = legacy; metadata = marker; return rows;
    })().catch(error => { loading = null; throw error; });
    return loading;
  }
  // A staging availability snapshot may inspect legacy rows but may not
  // perform the normal adoption transaction as a side effect of a GET.
  async function loadReadOnly() {
    if (rows) return rows;
    const raw = await storage.get(legacyKey);
    if (!partitioned || raw?.format !== 'per-driver-v2') {
      return extract(raw && typeof raw === 'object' ? raw : {}) || {};
    }
    const recovered = {};
    let startAfter = '';
    for (;;) {
      const page = await storage.list({prefix,startAfter,limit:1000});
      for (const [recordKey,row] of page) recovered[decodeURIComponent(recordKey.slice(prefix.length))] = row;
      if (page.size < 1000) break;
      startAfter = [...page.keys()].at(-1);
    }
    return recovered;
  }
  return {
    load,
    loadReadOnly,
    get revision() { return metadata?.revision || 0; },
    get partitioned() { return partitioned; },
    get metadata() { return metadata; },
    async prune(predicate, limit = 127) {
      if (!Number.isInteger(limit) || limit < 1 || limit > 127) throw Error('driver_prune_limit_invalid');
      await load();
      const ids = [];
      for (const [id, row] of Object.entries(rows)) {
        if (predicate(row, id)) ids.push(id);
        if (ids.length >= limit) break;
      }
      if (!ids.length) return { removed: 0, deleted: [], rows };
      const next = { ...metadata, revision: (metadata.revision || 0) + 1 };
      if (partitioned) await storage.transaction(async tx => {
        for (const id of ids) await tx.delete(key(id));
        await tx.put(legacyKey, next);
      });
      else {
        const remaining = { ...rows }; for (const id of ids) delete remaining[id];
        await storage.put(legacyKey, wrap(remaining, next));
      }
      for (const id of ids) delete rows[id]; metadata = next;
      return { removed: ids.length, deleted: ids, rows };
    },
    async clear(fields = {}) {
      await load();
      const next = { ...metadata, ...fields, revision: (metadata.revision || 0) + 1 };
      if (partitioned) {
        const ids = Object.keys(rows);
        for (let offset = 0; offset < ids.length; offset += 127) await storage.transaction(async tx => {
          for (const id of ids.slice(offset, offset + 127)) await tx.delete(key(id));
        });
        await storage.transaction(tx => tx.put(legacyKey, next));
      } else await storage.put(legacyKey, wrap({}, next));
      rows = {}; metadata = next; return rows;
    },
    async write(id, row, fields = {}) {
      await load();
      if (!partitioned) {
        const next = { ...rows }; if (row == null) delete next[id]; else next[id] = row;
        await storage.put(legacyKey, wrap(next, { ...metadata, ...fields })); rows = next; metadata = { ...metadata, ...fields }; return rows;
      }
      const next = { ...metadata, ...fields, revision: metadata.revision + 1 };
      // SQLite's synchronous KV API shares the same durable keyspace. Keep
      // row + revision atomic without one asynchronous commit/input gate per
      // ping. The runtime output gate still waits for durable disk commit;
      // no allowUnconfirmed, changed authority, or per-company blob is used.
      // Legacy KV-backed DOs and adapters retain their existing transaction.
      if (typeof storage.transactionSync === 'function' && storage.kv &&
          typeof storage.kv.put === 'function' && typeof storage.kv.delete === 'function') {
        storage.transactionSync(() => {
          if (row == null) storage.kv.delete(key(id)); else storage.kv.put(key(id), row);
          storage.kv.put(legacyKey, next);
        });
      } else await storage.transaction(async tx => {
        if (row == null) await tx.delete(key(id)); else await tx.put(key(id), row);
        await tx.put(legacyKey, next);
      });
      if (row == null) delete rows[id]; else rows[id] = row;
      metadata = next;
      if (onWrite) await onWrite(row, row == null ? 1 : 2,
        new TextEncoder().encode(JSON.stringify(next)).byteLength + (row == null ? 0 : new TextEncoder().encode(JSON.stringify(row)).byteLength));
      return rows;
    },
  };
}
