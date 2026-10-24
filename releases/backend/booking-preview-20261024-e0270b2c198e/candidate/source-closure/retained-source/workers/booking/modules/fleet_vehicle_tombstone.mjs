/**
 * Server-owned vehicle deletion tombstones for the scoped fleet inventory
 * record (`tenant:{t}:company:{c}:fleet:vehicles:v1`).
 *
 * This mirrors the driver index `deleted_drivers` tombstone map (a
 * `vehicleId -> ISO deletedAt` map): the active `vehicles` list keeps only
 * non-tombstoned vehicles, exactly like `drivers{}` keeps only non-tombstoned
 * drivers. There is no second, divergent delete mechanism (no per-vehicle
 * status flag). A deleted vehicle can therefore never be resurrected by a
 * stale full vehicle-list POST, a bootstrap re-import, or an inventory
 * backfill.
 *
 * Historical rides, documents, invoices and Chiron references are never
 * mutated by a tombstone; only the active fleet list drops the vehicle, and
 * the tombstone id stays internally available for those references.
 */

/** Coerce to a monotone-safe non-negative integer (0 for null/invalid). */
export function toMonotonicRevision(value) {
  const n = Number(value);
  if (!Number.isFinite(n)) return 0;
  const i = Math.trunc(n);
  return i > 0 ? i : 0;
}

/** Bounded, separator-free vehicle id usable as a tombstone map key. */
export function sanitizeVehicleTombstoneId(raw) {
  const text =
    typeof raw === "string" ? raw.trim() : raw == null ? "" : String(raw).trim();
  if (!text || text.length > 96) return "";
  if (/[\s/\\:*?"<>|]/.test(text) || text.includes("..")) return "";
  return text;
}

function coerceDeletedAt(value, fallbackIso) {
  const text = typeof value === "string" ? value.trim() : "";
  if (text && text.length >= 4 && text.length <= 40) return text;
  return fallbackIso;
}

/**
 * Parse a `deleted_vehicle_ids` tombstone map from a raw record. Accepts the
 * canonical `{ id: deletedAtIso }` map (snake/camel) and tolerates a legacy
 * array of ids. Unsafe ids are dropped. Returns a fresh plain object.
 */
export function normalizeDeletedVehicleMap(rawSource, { nowIso } = {}) {
  const fallback = coerceDeletedAt(nowIso, new Date().toISOString());
  const out = {};
  if (Array.isArray(rawSource)) {
    for (const idRaw of rawSource) {
      const id = sanitizeVehicleTombstoneId(idRaw);
      if (id) out[id] = fallback;
    }
    return out;
  }
  if (!rawSource || typeof rawSource !== "object") return out;
  for (const [idRaw, atRaw] of Object.entries(rawSource)) {
    const id = sanitizeVehicleTombstoneId(idRaw);
    if (!id) continue;
    out[id] = coerceDeletedAt(atRaw, fallback);
  }
  return out;
}

/**
 * Union server tombstones with client-supplied tombstones. Existing server
 * entries are ALWAYS preserved — an older full list can never remove a newer
 * tombstone — and client entries only ADD. Returns `{ map, changed }`.
 */
export function mergeVehicleTombstones(existingMap, incomingMap) {
  const merged = {
    ...(existingMap && typeof existingMap === "object" ? existingMap : {}),
  };
  const incoming =
    incomingMap && typeof incomingMap === "object" ? incomingMap : {};
  let changed = false;
  for (const [id, at] of Object.entries(incoming)) {
    if (!Object.prototype.hasOwnProperty.call(merged, id)) {
      merged[id] = at;
      changed = true;
    }
  }
  return { map: merged, changed };
}

/** Sorted ids of tombstoned vehicles (stable, identifier-only output). */
export function deletedVehicleIdList(deletedMap) {
  const map = deletedMap && typeof deletedMap === "object" ? deletedMap : {};
  return Object.keys(map).sort();
}

/**
 * Drop any vehicle whose id is tombstoned. `vehicleIdOf` extracts the id from
 * a (normalized) vehicle entry. Returns the active list only.
 */
export function filterActiveVehicles(vehicles, deletedMap, vehicleIdOf) {
  const list = Array.isArray(vehicles) ? vehicles : [];
  const deleted = deletedMap && typeof deletedMap === "object" ? deletedMap : {};
  const readId =
    typeof vehicleIdOf === "function"
      ? vehicleIdOf
      : (entry) => entry?.vehicle_id ?? entry?.vehicleId ?? entry?.id;
  return list.filter((entry) => {
    const id = sanitizeVehicleTombstoneId(readId(entry));
    return !!id && !Object.prototype.hasOwnProperty.call(deleted, id);
  });
}

/**
 * Monotone fleet source revision. Bumps by one on a real change; otherwise
 * keeps the established revision (or seeds a baseline of 1 for a legacy record
 * that had none) so a repeated identical delete / list-write never inflates
 * the revision.
 */
export function resolveFleetRevision({ existingRevision, changed } = {}) {
  const prev = toMonotonicRevision(existingRevision);
  if (changed) return prev + 1;
  return prev > 0 ? prev : 1;
}
