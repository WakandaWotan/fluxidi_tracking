/** Admin-only legacy review. No ownership guess, raw booking write or index prune. */
import { _scopeText } from './auth_scope.js';
import { canonicalBookingAuthorityEnabled, readLegacyBookingScopeMigrationRecord,
  adoptProvenLegacyBookingScope } from './canonical_booking_authority.mjs';
import { inspectLegacyOwnership, legacyOwnershipAgreesWithScope, validLegacyBookingId,
  checkedLegacyListPage, legacyScopeEvidenceDigest, buildCompanyIndexMembershipMap, unresolvedLegacyScopeTransition } from './legacy_scope_evidence.mjs';
export { buildCompanyIndexMembershipMap } from './legacy_scope_evidence.mjs';

export const LEGACY_SCOPE_QUARANTINE_REASON = 'legacy_scope_ambiguous';
export function legacyScopeMigrationEnabled(env) {
  return ['1', 'true', 'yes', 'on'].includes(String(env?.LEGACY_SCOPE_MIGRATION_ENABLED ?? '0').trim().toLowerCase());
}
export function isLegacyScopeQuarantined(rec) {
  if (!rec || typeof rec !== 'object') return false;
  return rec.legacy_scope_quarantine === true
    || ['ambiguous', LEGACY_SCOPE_QUARANTINE_REASON].includes(_scopeText(rec.legacy_scope_status ?? rec.legacyScopeStatus, 64).toLowerCase());
}
export function bookingMatchesTenantVisibleListScope(rec, requestedScope) {
  if (isLegacyScopeQuarantined(rec)) return false;
  const raw = inspectLegacyOwnership(rec);
  return !raw.invalid && !raw.conflicting && !!raw.tenant_raw && !!raw.company_raw
    && raw.tenant_raw !== 'fluxidi' && raw.company_raw !== 'fluxidi'
    && requestedScope?.tenant_id === raw.tenant_raw && requestedScope?.company_id === raw.company_raw;
}

function classify(bookingId, rec, memberships, directoryScope) {
  const raw = inspectLegacyOwnership(rec);
  const owners = [...new Map(memberships.map(owner => [JSON.stringify([owner.tenant_id, owner.company_id]), owner])).values()];
  const common = { booking_id: bookingId, raw, owners };
  if (isLegacyScopeQuarantined(rec)) return { ...common, category: 'B', action: 'already_quarantined', reason: LEGACY_SCOPE_QUARANTINE_REASON };
  if (raw.invalid || raw.conflicting) return { ...common, category: 'B', action: 'quarantine', reason: 'conflicting_raw_ownership' };
  if (raw.tenant_raw && raw.company_raw && raw.tenant_raw !== 'fluxidi' && raw.company_raw !== 'fluxidi') {
    if (directoryScope && !legacyOwnershipAgreesWithScope(rec, directoryScope)) {
      return { ...common, category: 'B', action: 'quarantine', reason: 'directory_scope_conflict' };
    }
    const foreign = owners.some(owner => !bookingMatchesTenantVisibleListScope(rec, owner));
    return { ...common, category: 'ok', action: foreign ? 'stale_index_prune_candidate' : 'none',
      reason: foreign ? 'index_foreign_vs_canonical' : 'already_scoped' };
  }
  if (owners.length === 1 && legacyOwnershipAgreesWithScope(rec, owners[0])
    && (!directoryScope || directoryScope.tenant_id === owners[0].tenant_id && directoryScope.company_id === owners[0].company_id)) {
    return { ...common, category: 'A', action: 'migrate_from_index', reason: 'single_index_membership',
      proposed_tenant_id: owners[0].tenant_id, proposed_company_id: owners[0].company_id };
  }
  return { ...common, category: 'B', action: 'quarantine', reason: owners.length === 0 ? 'no_index_membership'
    : owners.length > 1 ? 'conflicting_index_membership' : 'conflicting_raw_ownership' };
}

async function reviewPage(env, { cursor = null, limit = 50, maxIndexes = 200, bookingIds } = {}) {
  const inventory = await buildCompanyIndexMembershipMap(env, { maxIndexes });
  let page;
  if (bookingIds !== undefined) {
    if (!Array.isArray(bookingIds) || !bookingIds.length || bookingIds.length > 200
      || bookingIds.some(id => !validLegacyBookingId(id)) || new Set(bookingIds).size !== bookingIds.length || cursor) {
      const error = new Error('legacy_scope_selection_invalid'); error.status = 400; throw error;
    }
    page = { keys: bookingIds.map(id => `booking:${id}`), cursor: null, list_complete: true };
  } else page = checkedLegacyListPage(await env.BOOKING_KV.list({ prefix: 'booking:',
    limit: Math.min(200, Math.max(1, Number(limit) || 50)), ...(cursor ? { cursor } : {}) }), cursor);
  const records = [], seen = new Set();
  for (const key of page.keys) {
    const id = key.startsWith('booking:') ? key.slice(8) : '';
    if (!validLegacyBookingId(id)) throw new Error('legacy_scope_inventory_invalid');
    if (seen.has(id)) continue;
    seen.add(id);
    const read = await readLegacyBookingScopeMigrationRecord(env, id);
    if (!read.record || typeof read.record !== 'object' || Array.isArray(read.record)) {
      const error = new Error('legacy_scope_booking_missing'); error.status = 409; throw error;
    }
    const classified = classify(id, read.record, inventory.membership.get(id) || [], read.scope);
    records.push({ id, record: read.record, canonical: read.canonical, classified,
      record_digest: await legacyScopeEvidenceDigest(read.record) });
  }
  const review_digest = await legacyScopeEvidenceDigest({ cursor, next_cursor: page.cursor,
    inventory_digest: inventory.inventory_digest,
    records: records.map(item => ({ id: item.id, record_digest: item.record_digest, canonical: item.canonical, classified: item.classified })) });
  return { records, inventory, page, review_digest };
}

/** Census is read-only even when canonical projection recovery is pending. */
export async function censusLegacyBookingScope(env, options = {}) {
  if (!env?.BOOKING_KV) return { ok: false, error: 'Missing BOOKING_KV binding' };
  try {
    const reviewed = await reviewPage(env, options);
    const counts = { scanned: 0, missing_tenant_raw: 0, missing_company_raw: 0, missing_both_raw: 0,
      tenant_exact_fluxidi: 0, company_exact_fluxidi: 0, category_ok: 0, category_a: 0, category_b: 0, missing_canonical: 0 };
    const samples = { category_a: [], category_b: [], ok_foreign_index: [] };
    for (const { classified: item } of reviewed.records) {
      counts.scanned++;
      if (!item.raw.tenant_raw) counts.missing_tenant_raw++;
      if (!item.raw.company_raw) counts.missing_company_raw++;
      if (!item.raw.tenant_raw && !item.raw.company_raw) counts.missing_both_raw++;
      if (item.raw.tenant_raw === 'fluxidi') counts.tenant_exact_fluxidi++;
      if (item.raw.company_raw === 'fluxidi') counts.company_exact_fluxidi++;
      const group = item.category === 'A' ? 'category_a' : item.category === 'B' ? 'category_b' : 'category_ok';
      counts[group]++;
      const sample = samples[group] || (item.action === 'stale_index_prune_candidate' ? samples.ok_foreign_index : null);
      if (sample && sample.length < 20) sample.push(item);
    }
    return { ok: true, dry_run: true, counts, samples, review_digest: reviewed.review_digest,
      inventory_digest: reviewed.inventory.inventory_digest, indexes_scanned: reviewed.inventory.indexes_scanned,
      next_cursor: reviewed.page.cursor, list_complete: reviewed.page.list_complete };
  } catch (error) { return { ok: false, error: error.code || error.message, status: error.status || 409 }; }
}

/** Apply requires the exact review and uses immutable directory ownership + CAS. */
export async function applyLegacyBookingScopeMigration(env, { dryRun = true, reviewDigest, ...options } = {}) {
  if (!env?.BOOKING_KV) return { ok: false, error: 'Missing BOOKING_KV binding' };
  if (!dryRun && !legacyScopeMigrationEnabled(env)) return { ok: false, error: 'legacy_scope_migration_disabled', status: 403 };
  const result = { ok: true, dry_run: !!dryRun, scanned: 0, migrated: 0, quarantined: 0, skipped: 0, written: 0, items: [] };
  try {
    const reviewed = await reviewPage(env, options);
    Object.assign(result, { review_digest: reviewed.review_digest, inventory_digest: reviewed.inventory.inventory_digest,
      next_cursor: reviewed.page.cursor, list_complete: reviewed.page.list_complete });
    result.scanned = reviewed.records.length;
    if (!dryRun && !canonicalBookingAuthorityEnabled(env)) throw new Error('legacy_scope_canonical_authority_required');
    if (!dryRun && reviewDigest !== reviewed.review_digest) throw new Error('legacy_scope_review_conflict');
    // Validate the whole page before adopting any booking. Ambiguity cannot be
    // resolved by hiding records or rewriting a shared index outside its owner.
    if (!dryRun && reviewed.records.some(item => item.classified.category === 'B')) throw new Error('legacy_scope_ownership_unresolved');
    if (!dryRun && reviewed.records.some(item => item.classified.category === 'A' && unresolvedLegacyScopeTransition(item.record, item.id))) throw new Error('legacy_scope_transition_unresolved');
    for (const item of reviewed.records) {
      const classified = item.classified;
      if (classified.category === 'A') {
        if (!dryRun) await adoptProvenLegacyBookingScope(env, { bookingId: item.id,
          scope: { tenant_id: classified.proposed_tenant_id, company_id: classified.proposed_company_id },
          recordDigest: item.record_digest, inventoryDigest: reviewed.inventory.inventory_digest,
          maxIndexes: options.maxIndexes || 200 });
        result.migrated++;
        if (!dryRun) result.written++;
        result.items.push({ booking_id: item.id, action: dryRun ? 'would_migrate' : 'migrated', category: 'A',
          transition_unresolved: unresolvedLegacyScopeTransition(item.record, item.id),
          proposed_tenant_id: classified.proposed_tenant_id, proposed_company_id: classified.proposed_company_id });
      } else if (classified.category === 'B') {
        result.quarantined++;
        result.items.push({ booking_id: item.id, category: 'B', action: 'requires_ownership_resolution', reason: classified.reason });
      } else result.skipped++;
    }
  } catch (error) { Object.assign(result, { ok: false, error: error.code || error.message, status: error.status || 409 }); }
  return result;
}
