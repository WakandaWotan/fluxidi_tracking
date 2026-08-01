/**
 * RELEASE-P1 — Legacy scope census / migration / quarantine (admin-only).
 *
 * Category A: ownership proven from exactly one company list index membership
 *   → may write explicit tenant_id/company_id (idempotent).
 * Category B: missing/conflicting ownership evidence
 *   → quarantine from tenant-visible lists; no ownership guess.
 *
 * Dry-run performs no KV writes. Apply requires LEGACY_SCOPE_MIGRATION_ENABLED=1.
 */
import { safeStr } from "./parsing_utils.js";
import {
  _scopeText,
  resolveBookingTenantScopeFromRecord,
  bookingMatchesRequiredTenantCompanyScope,
} from "./auth_scope.js";
import { companyBookingsListIndexKey } from "./booking_indexes.js";

export const LEGACY_SCOPE_QUARANTINE_REASON = "legacy_scope_ambiguous";

export function legacyScopeMigrationEnabled(env) {
  const raw = String(env?.LEGACY_SCOPE_MIGRATION_ENABLED ?? "0")
    .trim()
    .toLowerCase();
  return raw === "1" || raw === "true" || raw === "yes" || raw === "on";
}

function _rawOwnershipFields(rec) {
  const booking = rec?.booking && typeof rec.booking === "object" ? rec.booking : null;
  return {
    tenant_raw: _scopeText(
      rec?.tenant_id ?? rec?.tenantId ?? booking?.tenant_id ?? booking?.tenantId,
    ),
    company_raw: _scopeText(
      rec?.company_id ?? rec?.companyId ?? booking?.company_id ?? booking?.companyId,
    ),
  };
}

export function isLegacyScopeQuarantined(rec) {
  if (!rec || typeof rec !== "object") return false;
  if (rec.legacy_scope_quarantine === true) return true;
  const status = _scopeText(rec.legacy_scope_status ?? rec.legacyScopeStatus, 64).toLowerCase();
  return status === "ambiguous" || status === LEGACY_SCOPE_QUARANTINE_REASON;
}

/**
 * Tenant-visible list gate: raw tenant_id AND company_id must both be present
 * and equal the trusted session scope. Does not use resolveBookingTenantScopeFromRecord
 * cross-fill (tenant←company / company←tenant), which would let a one-sided
 * ownership field pass when tenant_id === company_id in the product model.
 * Quarantined records are always excluded.
 */
export function bookingMatchesTenantVisibleListScope(rec, requestedScope) {
  if (isLegacyScopeQuarantined(rec)) return false;
  const requestedTenant = _scopeText(requestedScope?.tenant_id);
  const requestedCompany = _scopeText(requestedScope?.company_id);
  if (!requestedTenant || !requestedCompany) return false;
  const raw = _rawOwnershipFields(rec);
  if (!raw.tenant_raw || !raw.company_raw) return false;
  if (raw.tenant_raw === "fluxidi" || raw.company_raw === "fluxidi") {
    // Exact legacy sentinel must not appear on tenant-visible lists.
    return false;
  }
  return (
    requestedTenant === raw.tenant_raw && requestedCompany === raw.company_raw
  );
}

function _bookingIdFromKey(name) {
  const key = safeStr(name, 240);
  if (!key.startsWith("booking:")) return "";
  return safeStr(key.slice("booking:".length), 160);
}

async function _listCompanyIndexKeys(env, { cursor = null, limit = 200 } = {}) {
  const page = await env.BOOKING_KV.list({
    prefix: "tenant:",
    limit: Math.min(1000, Math.max(1, Number(limit) || 200)),
    cursor: cursor || undefined,
  });
  const keys = (page?.keys || [])
    .map((k) => safeStr(k?.name, 320))
    .filter((name) => /:bookings:list:v1$/.test(name));
  return {
    keys,
    cursor: page?.list_complete === false ? page?.cursor || null : null,
  };
}

function _parseCompanyListIndexKey(name) {
  const m = String(name || "").match(
    /^tenant:([^:]+):company:([^:]+):bookings:list:v1$/,
  );
  if (!m) return null;
  return { tenant_id: m[1], company_id: m[2], key: name };
}

/**
 * Build membership map bookingId → [{tenant_id, company_id, index_key}].
 */
export async function buildCompanyIndexMembershipMap(env, { maxIndexes = 200 } = {}) {
  const membership = new Map();
  let cursor = null;
  let indexesScanned = 0;
  do {
    const page = await _listCompanyIndexKeys(env, { cursor, limit: 200 });
    for (const key of page.keys) {
      if (indexesScanned >= maxIndexes) break;
      const parsed = _parseCompanyListIndexKey(key);
      if (!parsed) continue;
      indexesScanned += 1;
      const idx = await env.BOOKING_KV.get(key, { type: "json" });
      const items = Array.isArray(idx?.items) ? idx.items : [];
      for (const entry of items) {
        const bookingId = safeStr(entry?.booking_id ?? entry?.bookingId, 160);
        if (!bookingId) continue;
        const list = membership.get(bookingId) || [];
        list.push({
          tenant_id: parsed.tenant_id,
          company_id: parsed.company_id,
          index_key: parsed.key,
        });
        membership.set(bookingId, list);
      }
    }
    cursor = page.cursor;
    if (indexesScanned >= maxIndexes) break;
  } while (cursor);
  return { membership, indexes_scanned: indexesScanned };
}

function _classifyBooking(bookingId, rec, memberships) {
  const raw = _rawOwnershipFields(rec);
  const resolved = resolveBookingTenantScopeFromRecord(rec);
  const owners = Array.isArray(memberships) ? memberships : [];
  const uniqueOwners = [];
  const seen = new Set();
  for (const o of owners) {
    const sig = `${o.tenant_id}::${o.company_id}`;
    if (seen.has(sig)) continue;
    seen.add(sig);
    uniqueOwners.push(o);
  }

  const hasBothRaw = !!(raw.tenant_raw && raw.company_raw);
  const exactFluxidi =
    raw.tenant_raw === "fluxidi" || raw.company_raw === "fluxidi";

  if (isLegacyScopeQuarantined(rec)) {
    return {
      booking_id: bookingId,
      category: "B",
      action: "already_quarantined",
      reason: LEGACY_SCOPE_QUARANTINE_REASON,
      raw,
      owners: uniqueOwners,
    };
  }

  if (hasBothRaw && !exactFluxidi) {
    // Already strict-ready. If indexed under a foreign company, flag for prune
    // (list path already discards); do not rewrite ownership.
    const foreignIndex = uniqueOwners.some(
      (o) =>
        !bookingMatchesRequiredTenantCompanyScope(rec, {
          tenant_id: o.tenant_id,
          company_id: o.company_id,
        }),
    );
    return {
      booking_id: bookingId,
      category: "ok",
      action: foreignIndex ? "stale_index_prune_candidate" : "none",
      reason: foreignIndex ? "index_foreign_vs_canonical" : "already_scoped",
      raw,
      owners: uniqueOwners,
    };
  }

  if (uniqueOwners.length === 1 && (!hasBothRaw || exactFluxidi)) {
    return {
      booking_id: bookingId,
      category: "A",
      action: "migrate_from_index",
      reason: "single_index_membership",
      proposed_tenant_id: uniqueOwners[0].tenant_id,
      proposed_company_id: uniqueOwners[0].company_id,
      raw,
      resolved,
      owners: uniqueOwners,
    };
  }

  return {
    booking_id: bookingId,
    category: "B",
    action: "quarantine",
    reason:
      uniqueOwners.length === 0
        ? "no_index_membership"
        : uniqueOwners.length > 1
          ? "conflicting_index_membership"
          : "ambiguous_ownership",
    raw,
    resolved,
    owners: uniqueOwners,
  };
}

/**
 * Read-only census over booking: keys (bounded).
 */
export async function censusLegacyBookingScope(env, {
  cursor = null,
  limit = 100,
  membership = null,
} = {}) {
  if (!env?.BOOKING_KV) {
    return { ok: false, error: "Missing BOOKING_KV binding" };
  }
  const membershipState =
    membership ||
    (await buildCompanyIndexMembershipMap(env)).membership;

  const page = await env.BOOKING_KV.list({
    prefix: "booking:",
    limit: Math.min(500, Math.max(1, Number(limit) || 100)),
    cursor: cursor || undefined,
  });

  const counts = {
    scanned: 0,
    missing_tenant_raw: 0,
    missing_company_raw: 0,
    missing_both_raw: 0,
    tenant_exact_fluxidi: 0,
    company_exact_fluxidi: 0,
    category_ok: 0,
    category_a: 0,
    category_b: 0,
    missing_canonical: 0,
  };
  const samples = { category_a: [], category_b: [], ok_foreign_index: [] };

  for (const item of page?.keys || []) {
    const bookingId = _bookingIdFromKey(item?.name);
    if (!bookingId) continue;
    counts.scanned += 1;
    const rec = await env.BOOKING_KV.get(`booking:${bookingId}`, { type: "json" });
    if (!rec || typeof rec !== "object") {
      counts.missing_canonical += 1;
      continue;
    }
    const raw = _rawOwnershipFields(rec);
    if (!raw.tenant_raw) counts.missing_tenant_raw += 1;
    if (!raw.company_raw) counts.missing_company_raw += 1;
    if (!raw.tenant_raw && !raw.company_raw) counts.missing_both_raw += 1;
    if (raw.tenant_raw === "fluxidi") counts.tenant_exact_fluxidi += 1;
    if (raw.company_raw === "fluxidi") counts.company_exact_fluxidi += 1;

    const classified = _classifyBooking(
      bookingId,
      rec,
      membershipState.get(bookingId) || [],
    );
    if (classified.category === "A") {
      counts.category_a += 1;
      if (samples.category_a.length < 20) samples.category_a.push(classified);
    } else if (classified.category === "B") {
      counts.category_b += 1;
      if (samples.category_b.length < 20) samples.category_b.push(classified);
    } else {
      counts.category_ok += 1;
      if (
        classified.action === "stale_index_prune_candidate" &&
        samples.ok_foreign_index.length < 20
      ) {
        samples.ok_foreign_index.push(classified);
      }
    }
  }

  return {
    ok: true,
    dry_run: true,
    counts,
    samples,
    next_cursor: page?.list_complete === false ? page?.cursor || null : null,
    list_complete: page?.list_complete !== false,
  };
}

function _applyOwnershipFields(rec, tenantId, companyId) {
  const next = { ...rec };
  next.tenant_id = tenantId;
  next.company_id = companyId;
  next.tenantId = tenantId;
  next.companyId = companyId;
  if (next.booking && typeof next.booking === "object") {
    next.booking = {
      ...next.booking,
      tenant_id: tenantId,
      company_id: companyId,
      tenantId,
      companyId,
    };
  }
  next.legacy_scope_migrated_at = new Date().toISOString();
  next.legacy_scope_migration_source = "company_list_index";
  delete next.legacy_scope_quarantine;
  if (next.legacy_scope_status === LEGACY_SCOPE_QUARANTINE_REASON) {
    delete next.legacy_scope_status;
  }
  return next;
}

function _applyQuarantine(rec, reason) {
  return {
    ...rec,
    legacy_scope_quarantine: true,
    legacy_scope_status: LEGACY_SCOPE_QUARANTINE_REASON,
    legacy_scope_quarantine_reason: reason || LEGACY_SCOPE_QUARANTINE_REASON,
    legacy_scope_quarantined_at: new Date().toISOString(),
  };
}

/**
 * Apply one page of migration/quarantine. Idempotent.
 */
export async function applyLegacyBookingScopeMigration(env, {
  cursor = null,
  limit = 50,
  dryRun = true,
  membership = null,
} = {}) {
  if (!env?.BOOKING_KV) {
    return { ok: false, error: "Missing BOOKING_KV binding" };
  }
  if (!dryRun && !legacyScopeMigrationEnabled(env)) {
    return {
      ok: false,
      error: "legacy_scope_migration_disabled",
      hint: "Set LEGACY_SCOPE_MIGRATION_ENABLED=1 for apply",
    };
  }

  const membershipState =
    membership ||
    (await buildCompanyIndexMembershipMap(env)).membership;

  const page = await env.BOOKING_KV.list({
    prefix: "booking:",
    limit: Math.min(200, Math.max(1, Number(limit) || 50)),
    cursor: cursor || undefined,
  });

  const results = {
    ok: true,
    dry_run: !!dryRun,
    scanned: 0,
    migrated: 0,
    quarantined: 0,
    skipped: 0,
    written: 0,
    items: [],
  };

  for (const item of page?.keys || []) {
    const bookingId = _bookingIdFromKey(item?.name);
    if (!bookingId) continue;
    results.scanned += 1;
    const key = `booking:${bookingId}`;
    const rec = await env.BOOKING_KV.get(key, { type: "json" });
    if (!rec || typeof rec !== "object") {
      results.skipped += 1;
      continue;
    }
    const classified = _classifyBooking(
      bookingId,
      rec,
      membershipState.get(bookingId) || [],
    );

    if (classified.category === "A" && classified.action === "migrate_from_index") {
      const next = _applyOwnershipFields(
        rec,
        classified.proposed_tenant_id,
        classified.proposed_company_id,
      );
      // Idempotent: already matching proposed → skip write.
      const already = bookingMatchesRequiredTenantCompanyScope(rec, {
        tenant_id: classified.proposed_tenant_id,
        company_id: classified.proposed_company_id,
      });
      if (already && !isLegacyScopeQuarantined(rec)) {
        results.skipped += 1;
        results.items.push({
          booking_id: bookingId,
          action: "skip_already_migrated",
          category: "A",
        });
        continue;
      }
      results.migrated += 1;
      results.items.push({
        booking_id: bookingId,
        action: dryRun ? "would_migrate" : "migrated",
        category: "A",
        proposed_tenant_id: classified.proposed_tenant_id,
        proposed_company_id: classified.proposed_company_id,
      });
      if (!dryRun) {
        await env.BOOKING_KV.put(key, JSON.stringify(next));
        results.written += 1;
      }
      continue;
    }

    if (classified.category === "B" && classified.action === "quarantine") {
      if (isLegacyScopeQuarantined(rec)) {
        results.skipped += 1;
        results.items.push({
          booking_id: bookingId,
          action: "skip_already_quarantined",
          category: "B",
        });
        continue;
      }
      results.quarantined += 1;
      results.items.push({
        booking_id: bookingId,
        action: dryRun ? "would_quarantine" : "quarantined",
        category: "B",
        reason: classified.reason,
      });
      if (!dryRun) {
        await env.BOOKING_KV.put(
          key,
          JSON.stringify(_applyQuarantine(rec, classified.reason)),
        );
        results.written += 1;
        // Best-effort: drop from any company indexes that listed it.
        for (const owner of classified.owners || []) {
          try {
            const indexKey =
              owner.index_key ||
              companyBookingsListIndexKey({
                tenant_id: owner.tenant_id,
                company_id: owner.company_id,
              });
            if (!indexKey) continue;
            const idx = await env.BOOKING_KV.get(indexKey, { type: "json" });
            if (!idx || !Array.isArray(idx.items)) continue;
            const nextItems = idx.items.filter((entry) => {
              const id = safeStr(entry?.booking_id ?? entry?.bookingId, 160);
              return id && id !== bookingId;
            });
            if (nextItems.length !== idx.items.length) {
              await env.BOOKING_KV.put(
                indexKey,
                JSON.stringify({ ...idx, items: nextItems }),
              );
            }
          } catch (_) {
            // Best-effort index prune only.
          }
        }
      }
      continue;
    }

    results.skipped += 1;
  }

  results.next_cursor =
    page?.list_complete === false ? page?.cursor || null : null;
  results.list_complete = page?.list_complete !== false;
  return results;
}
