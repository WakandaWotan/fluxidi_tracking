// Large authoritative snapshots use bounded values and a sealed root pointer.
// The caller must serialize operations for this root (the company DO does so).
// Small records retain the original storage representation.
import { sha256Hex } from './crypto_utils.js';
const MARK = '__fluxidi_chunked_json_v1__';
const INLINE_BYTES = 96 * 1024;
const CHARS = 16 * 1024;
const GROUP = 64;
const bytes = text => new TextEncoder().encode(text).length;
function isManifest(value) { return value?.[MARK] === true; }
function validate(value) {
  if (!isManifest(value) || !/^[a-f0-9]{64}$/.test(value.digest)
    || !Number.isSafeInteger(value.parts) || value.parts < 1 || value.parts > 65536
    || !Number.isSafeInteger(value.bytes) || value.bytes < 1) throw Error('snapshot_manifest_invalid');
  return value;
}
function partKey(root, value, index) { return root + ':chunk:' + value.digest + ':' + index; }
async function removeParts(storage, root, value, protectedDigest = null) {
  if (!isManifest(value)) return;
  validate(value);
  if (value.digest === protectedDigest) return;
  for (let offset = 0; offset < value.parts; offset += GROUP) {
    for (let i = offset; i < Math.min(offset + GROUP, value.parts); i++) await storage.delete(partKey(root, value, i));
  }
}
async function cleanIntent(storage, root, current) {
  const intent = await storage.get(root + ':chunk-intent');
  if (!intent) return;
  await removeParts(storage, root, intent, isManifest(current) ? current.digest : null);
  await storage.delete(root + ':chunk-intent');
}
export async function readBoundedJson(storage, root) {
  const value = await storage.get(root);
  if (!isManifest(value)) return value;
  validate(value);
  const parts = [];
  for (let i = 0; i < value.parts; i++) {
    const part = await storage.get(partKey(root, value, i));
    if (typeof part !== 'string') throw Error('snapshot_chunk_missing');
    parts.push(part);
  }
  const text = parts.join('');
  if (bytes(text) !== value.bytes || await sha256Hex(text) !== value.digest) throw Error('snapshot_integrity_failed');
  return JSON.parse(text);
}
export async function writeBoundedJson(storage, root, value) {
  const text = JSON.stringify(value), size = bytes(text);
  const old = await storage.get(root);
  await cleanIntent(storage, root, old);
  if (size <= INLINE_BYTES) {
    await storage.put(root, value);
    await removeParts(storage, root, old);
    return;
  }
  const chunks = [];
  for (let start = 0; start < text.length;) {
    let end = Math.min(start + CHARS, text.length);
    // Keep a UTF-16 surrogate pair together so digest and byte length survive storage.
    if (end < text.length && /[\uD800-\uDBFF]/.test(text[end - 1])) end--;
    chunks.push(text.slice(start, end)); start = end;
  }
  const next = { [MARK]: true, digest: await sha256Hex(text), parts: chunks.length, bytes: size };
  validate(next);
  await storage.put(root + ':chunk-intent', next);
  for (let offset = 0; offset < chunks.length; offset += GROUP) {
    const store = async target => {
      for (let i = offset; i < Math.min(offset + GROUP, chunks.length); i++) await target.put(partKey(root, next, i), chunks[i]);
    };
    if (storage.transaction) await storage.transaction(store); else await store(storage);
  }
  // This is the only visibility/authority commit. A failed chunk write leaves old intact.
  await storage.put(root, next);
  await storage.delete(root + ':chunk-intent');
  await removeParts(storage, root, old, next.digest);
}
export async function deleteBoundedJson(storage, root) {
  const old = await storage.get(root);
  // Remove the authority pointer before deleting chunks; interrupted cleanup is harmless.
  if (isManifest(old)) await storage.put(root + ':chunk-intent', old);
  await storage.delete(root);
  await cleanIntent(storage, root, null);
}
