/**
 * Durable scoped RateHawk hotel-content store (future RATEHAWK_HOTELS_DB).
 *
 * Server-owned monotonic generations + deterministic content hashes.
 * No production in-memory fallback. Missing D1 fails closed.
 * This module does not call RateHawk.
 */

import { RATEHAWK_DISCLOSURE_LOCALES } from "./ratehawk_content_freshness_contract.mjs";
import {
  livePriceKeysPresent,
  toStoredStaticHotelProjection,
} from "./ratehawk_content_sync.mjs";

export const RATEHAWK_HOTELS_DB_BINDING = "RATEHAWK_HOTELS_DB";
export const RATEHAWK_CONTENT_SCHEMA_VERSION = 1;
export const RATEHAWK_PUBLIC_LOCALE_FALLBACK = Object.freeze(["en", "nl", "fr", "es"]);
export const RATEHAWK_CONTENT_JOB_STATES = Object.freeze({
  PLANNED: "planned",
  RUNNING: "running",
  APPLIED: "applied",
  UNCHANGED: "unchanged",
  RETRYABLE: "retryable",
  FAILED: "failed",
  TOMBSTONED: "tombstoned",
});
export const RATEHAWK_AUTHORITATIVE_REMOVAL_REASONS = Object.freeze([
  "hotel_not_found",
  "content_removed",
]);
export const RATEHAWK_TRANSIENT_CONTENT_ERRORS = Object.freeze([
  "timeout",
  "endpoint_exceeded_limit",
  "provider_error",
  "provider_malformed_response",
  "provider_fetch_failed",
  "hotel_unwrap_failed",
]);

const FORBIDDEN_PERSIST_RE =
  /authorization|RATEHAWK_API_KEY|book_hash|match_hash|search_hash|reconciliation|affiliate_remuneration|payment_options|"rates"|show_amount/i;

function _text(value, max = 400) {
  const text = String(value ?? "").trim();
  if (!text) return "";
  return text.length > max ? text.slice(0, max) : text;
}

function _hid(value) {
  const text = _text(value, 16);
  if (!/^\d{1,10}$/.test(text)) return null;
  return Number(text);
}

function _locale(value) {
  const locale = _text(value, 8).toLowerCase();
  return RATEHAWK_DISCLOSURE_LOCALES.includes(locale) ? locale : null;
}

function _int(value, fallback = 0) {
  const n = Number(value);
  if (!Number.isFinite(n)) return fallback;
  return Math.trunc(n);
}

function _json(value, fallback) {
  if (value == null || value === "") return fallback;
  if (typeof value !== "string") return value;
  try {
    return JSON.parse(value);
  } catch {
    return fallback;
  }
}

function stableStringify(value) {
  if (value == null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map((item) => stableStringify(item)).join(",")}]`;
  const keys = Object.keys(value).sort();
  return `{${keys.map((key) => `${JSON.stringify(key)}:${stableStringify(value[key])}`).join(",")}}`;
}

export function canonicalNormalizedContent(projection = {}) {
  return {
    hid: projection.hid ?? null,
    locale: projection.locale ?? null,
    name: projection.name ?? null,
    address: projection.address ?? null,
    coordinates: projection.coordinates ?? null,
    star_rating: projection.star_rating ?? null,
    description_struct: projection.description_struct ?? [],
    image_refs: projection.image_refs ?? [],
    categories: {
      pets: projection.categories?.pets ?? [],
      children_age_ranges: projection.categories?.children_age_ranges ?? [],
      cots_extra_beds: projection.categories?.cots_extra_beds ?? [],
      accessibility: projection.categories?.accessibility ?? [],
      amenities: projection.categories?.amenities ?? [],
      check_in_check_out: projection.categories?.check_in_check_out ?? null,
      internet_parking: projection.categories?.internet_parking ?? null,
      hotel_deposits: projection.categories?.hotel_deposits ?? [],
      important_hotel_information: projection.categories?.important_hotel_information ?? null,
      room_type_beds_occupancy: projection.categories?.room_type_beds_occupancy ?? [],
    },
    metapolicy_extra_info: projection.metapolicy_extra_info ?? null,
    metapolicy_struct: projection.metapolicy_struct ?? null,
    policy_struct: projection.policy_struct ?? [],
  };
}

export async function hashRatehawkNormalizedContent(projection) {
  const encoded = new TextEncoder().encode(stableStringify(canonicalNormalizedContent(projection)));
  const digest = await crypto.subtle.digest("SHA-256", encoded);
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

export function isRatehawkHotelsDbConfigured(env = {}) {
  return Boolean(env?.[RATEHAWK_HOTELS_DB_BINDING]?.prepare);
}

export function publicLocaleFallbackOrder(requested) {
  const locale = _locale(requested);
  const first = locale || RATEHAWK_PUBLIC_LOCALE_FALLBACK[0];
  return [first, ...RATEHAWK_PUBLIC_LOCALE_FALLBACK.filter((item) => item !== first)];
}

export function assertPersistableHotelContent(projection = {}) {
  const hid = _hid(projection.hid);
  const locale = _locale(projection.locale);
  if (hid == null) return { ok: false, reason: "invalid_hid" };
  if (!locale) return { ok: false, reason: "locale_unsupported" };
  if (livePriceKeysPresent(projection) || livePriceKeysPresent(projection.categories)) {
    return { ok: false, reason: "live_price_forbidden_in_static_content" };
  }
  if (projection.email || projection.phone) {
    return { ok: false, reason: "restricted_contact_forbidden" };
  }
  const serialized = JSON.stringify(projection);
  if (FORBIDDEN_PERSIST_RE.test(serialized)) {
    return { ok: false, reason: "forbidden_secret_or_live_field" };
  }
  if (/[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}/i.test(serialized) || /\+\d{8,}/.test(serialized)) {
    return { ok: false, reason: "restricted_contact_forbidden" };
  }
  return { ok: true, hid, locale };
}

function _emptyPublic({ hid, locale, state, reason = null }) {
  return {
    ok: true,
    state,
    reason,
    hid,
    locale,
    locale_resolved: null,
    locale_fallback_used: false,
    transport_invoked: false,
    stay22_fallback_retained: true,
    mobility_independent_of_ratehawk: true,
    restricted_contact_excluded: true,
    description_indexed: false,
    live_price_excluded: true,
  };
}

function _hydrateLocale(row) {
  if (!row) return null;
  return {
    ...row,
    description_struct: _json(row.description_struct, []),
    image_refs: _json(row.image_refs, []),
    amenity_groups: _json(row.amenity_groups, []),
    room_groups: _json(row.room_groups, []),
    pets: _json(row.pets, []),
    children_age_ranges: _json(row.children_age_ranges, []),
    cots_extra_beds: _json(row.cots_extra_beds, []),
    accessibility: _json(row.accessibility, []),
    parking: _json(row.parking, []),
    internet: _json(row.internet, []),
    hotel_deposits: _json(row.hotel_deposits, []),
    metapolicy_struct: _json(row.metapolicy_struct, null),
    policy_struct: _json(row.policy_struct, []),
    categories: _json(row.categories, {}),
    review_required_fields: _json(row.review_required_fields, []),
    coordinates:
      row.lat != null && row.lng != null ? { lat: row.lat, lng: row.lng } : row.coordinates ?? null,
  };
}

function _toPublicDto(row, requestedLocale) {
  const hydrated = _hydrateLocale(row);
  return {
    ok: true,
    state: "ready",
    hid: hydrated.hid,
    locale: requestedLocale,
    locale_resolved: hydrated.locale,
    locale_fallback_used: hydrated.locale !== requestedLocale,
    name: hydrated.name,
    address: hydrated.address,
    coordinates: hydrated.coordinates,
    star_rating: hydrated.star_rating ?? null,
    image_refs: hydrated.image_refs ?? [],
    description_struct: hydrated.description_struct ?? [],
    description_indexed: false,
    categories: hydrated.categories ?? {},
    freshness: {
      source: "ratehawk_offline_static",
      retrieved_at: hydrated.retrieved_at,
      stored_at: hydrated.stored_at,
    },
    transport_invoked: false,
    stay22_fallback_retained: true,
    mobility_independent_of_ratehawk: true,
    restricted_contact_excluded: true,
    live_price_excluded: true,
  };
}

function _localeRecord(projection, hash, generation, now) {
  const categories = projection.categories || {};
  return {
    hid: projection.hid,
    locale: projection.locale,
    name: projection.name ?? null,
    address: projection.address ?? null,
    lat: projection.coordinates?.lat ?? null,
    lng: projection.coordinates?.lng ?? null,
    star_rating: projection.star_rating ?? null,
    description_struct: projection.description_struct ?? [],
    image_refs: projection.image_refs ?? [],
    amenity_groups: categories.amenities ?? [],
    room_groups: categories.room_type_beds_occupancy ?? [],
    pets: categories.pets ?? [],
    children_age_ranges: categories.children_age_ranges ?? [],
    cots_extra_beds: categories.cots_extra_beds ?? [],
    accessibility: categories.accessibility ?? [],
    parking: categories.internet_parking?.parking ?? [],
    internet: categories.internet_parking?.internet ?? [],
    check_in_time: categories.check_in_check_out?.check_in_time ?? null,
    check_out_time: categories.check_in_check_out?.check_out_time ?? null,
    hotel_deposits: categories.hotel_deposits ?? [],
    metapolicy_extra_info: projection.metapolicy_extra_info ?? null,
    metapolicy_struct: projection.metapolicy_struct ?? null,
    policy_struct: projection.policy_struct ?? [],
    important_hotel_information: categories.important_hotel_information ?? null,
    categories,
    schema_version: RATEHAWK_CONTENT_SCHEMA_VERSION,
    content_hash: hash,
    sync_generation: generation,
    retrieved_at: now,
    stored_at: now,
    review_required_fields: projection.unmapped_critical_field_names ?? [],
    active: 1,
    tombstoned: 0,
  };
}

function _marketParts(marketKey) {
  const text = _text(marketKey, 80);
  if (!text.includes(":")) return { country_code: null, city_key: null };
  const [country_code, city_key] = text.split(":");
  return { country_code: country_code || null, city_key: city_key || null };
}

async function _prepareWrite(projection, incomingGeneration) {
  const persistable = assertPersistableHotelContent(projection);
  if (persistable.ok !== true) {
    return { ok: false, ...persistable, status: RATEHAWK_CONTENT_JOB_STATES.FAILED };
  }
  const stored = toStoredStaticHotelProjection(projection);
  if (!stored || stored.ok !== true) {
    return {
      ok: false,
      reason: stored?.reason || "projection_unavailable",
      status: RATEHAWK_CONTENT_JOB_STATES.FAILED,
    };
  }
  const generation = _int(incomingGeneration, 0);
  if (generation < 1) {
    return { ok: false, reason: "generation_required", status: RATEHAWK_CONTENT_JOB_STATES.FAILED };
  }
  return {
    ok: true,
    persistable,
    stored,
    generation,
    hash: await hashRatehawkNormalizedContent(stored),
  };
}

export function createRatehawkContentRepository({ memory = true } = {}) {
  if (memory !== true) {
    throw new Error("d1_backend_requires_openRatehawkContentStore");
  }
  const identity = new Map();
  const locales = new Map();
  const index = new Map();
  const jobs = new Map();
  const runs = new Map();
  let generation = 0;
  const localeKey = (hid, locale) => `${hid}:${locale}`;

  const repo = {
    kind: "memory_test_repository",
    async allocateRun({ market_key = null, now = Date.now() } = {}) {
      generation += 1;
      const run_id = `rhcs_${generation}`;
      runs.set(run_id, {
        run_id,
        generation,
        market_key,
        status: RATEHAWK_CONTENT_JOB_STATES.PLANNED,
        created_at: now,
        updated_at: now,
        completed_at: null,
      });
      return { run_id, generation };
    },
    async planJob(job, now = Date.now()) {
      const job_id = job.job_id || `job_${job.run_id || "local"}_${job.hid}_${job.locale}`;
      jobs.set(job_id, {
        job_id,
        run_id: job.run_id ?? null,
        generation: _int(job.generation, 0),
        market_key: job.market_key ?? null,
        hid: job.hid,
        locale: job.locale,
        status: RATEHAWK_CONTENT_JOB_STATES.PLANNED,
        attempt_count: 0,
        error_code: null,
        retry_after: null,
        next_attempt_at: null,
        lease_until: now + 60_000,
        created_at: now,
        updated_at: now,
        completed_at: null,
      });
      return { ok: true, job_id };
    },
    async getJob(job_id) {
      return jobs.get(job_id) || null;
    },
    async getLocale(hid, locale) {
      return locales.get(localeKey(hid, locale)) || null;
    },
    async getIdentity(hid) {
      return identity.get(hid) || null;
    },
    async listSearchIndex() {
      return [...index.values()];
    },
    async applyNormalized({
      projection,
      generation: incomingGeneration,
      now = Date.now(),
      market_key = null,
      job_id = null,
    } = {}) {
      const prepared = await _prepareWrite(projection, incomingGeneration);
      if (prepared.ok !== true) {
        if (job_id) {
          await repo._setJob(job_id, {
            status: RATEHAWK_CONTENT_JOB_STATES.FAILED,
            error_code: prepared.reason,
            now,
          });
        }
        return { written: false, ...prepared };
      }
      const { persistable, stored, generation: gen, hash } = prepared;
      const key = localeKey(persistable.hid, persistable.locale);
      const existing = locales.get(key);
      if (existing && gen < existing.sync_generation) {
        if (job_id) {
          await repo._setJob(job_id, {
            status: RATEHAWK_CONTENT_JOB_STATES.FAILED,
            error_code: "older_generation_rejected",
            now,
          });
        }
        return {
          written: false,
          reason: "older_generation_rejected",
          status: RATEHAWK_CONTENT_JOB_STATES.FAILED,
        };
      }
      const currentIdentity = identity.get(persistable.hid);
      if (existing && existing.content_hash === hash && existing.tombstoned !== 1) {
        locales.set(key, {
          ...existing,
          sync_generation: Math.max(_int(existing.sync_generation, 0), gen),
        });
        identity.set(persistable.hid, {
          ...currentIdentity,
          hid: persistable.hid,
          last_success_at: now,
          updated_at: now,
          sync_generation: Math.max(_int(currentIdentity?.sync_generation, 0), gen),
          content_hash: hash,
        });
        if (job_id) {
          await repo._setJob(job_id, {
            status: RATEHAWK_CONTENT_JOB_STATES.UNCHANGED,
            now,
            completed: true,
          });
        }
        return {
          written: false,
          reason: "unchanged",
          status: RATEHAWK_CONTENT_JOB_STATES.UNCHANGED,
          content_hash: hash,
          generation: gen,
        };
      }
      const row = _localeRecord(stored, hash, gen, now);
      locales.set(key, row);
      const parts = _marketParts(stored.market_key ?? market_key ?? currentIdentity?.market_key);
      index.set(key, {
        hid: row.hid,
        locale: row.locale,
        name: row.name,
        address: row.address,
        city_key: parts.city_key,
        country_code: parts.country_code,
        lat: row.lat,
        lng: row.lng,
        star_rating: row.star_rating,
        description_indexed: false,
      });
      identity.set(persistable.hid, {
        hid: persistable.hid,
        legacy_id: stored.legacy_id ?? currentIdentity?.legacy_id ?? null,
        country_code: parts.country_code,
        city_key: parts.city_key,
        region_id: currentIdentity?.region_id ?? null,
        market_key: stored.market_key ?? market_key ?? currentIdentity?.market_key ?? null,
        lat: row.lat,
        lng: row.lng,
        star_rating: row.star_rating,
        kind: stored.kind ?? currentIdentity?.kind ?? null,
        source: "ratehawk",
        active: 1,
        tombstoned: 0,
        tombstone_reason: null,
        tombstoned_at: null,
        tombstone_generation: null,
        sync_generation: gen,
        content_hash: hash,
        first_seen_at: currentIdentity?.first_seen_at ?? now,
        last_success_at: now,
        updated_at: now,
      });
      if (job_id) {
        await repo._setJob(job_id, {
          status: RATEHAWK_CONTENT_JOB_STATES.APPLIED,
          now,
          completed: true,
        });
      }
      return {
        written: true,
        reason: null,
        status: RATEHAWK_CONTENT_JOB_STATES.APPLIED,
        content_hash: hash,
        generation: gen,
      };
    },
    async tombstoneAuthoritative({
      hid,
      locale,
      generation: incomingGeneration,
      now = Date.now(),
      reason,
      job_id = null,
    } = {}) {
      if (!RATEHAWK_AUTHORITATIVE_REMOVAL_REASONS.includes(reason)) {
        return { written: false, reason: "tombstone_not_authoritative" };
      }
      const resolvedHid = _hid(hid);
      const resolvedLocale = _locale(locale);
      if (resolvedHid == null || !resolvedLocale) {
        return { written: false, reason: resolvedHid == null ? "invalid_hid" : "locale_unsupported" };
      }
      const gen = _int(incomingGeneration, 0);
      const key = localeKey(resolvedHid, resolvedLocale);
      const existing = locales.get(key);
      if (existing && gen < existing.sync_generation) {
        return { written: false, reason: "older_generation_rejected" };
      }
      const currentIdentity = identity.get(resolvedHid) || {
        hid: resolvedHid,
        first_seen_at: now,
        source: "ratehawk",
      };
      identity.set(resolvedHid, {
        ...currentIdentity,
        active: 0,
        tombstoned: 1,
        tombstone_reason: reason,
        tombstoned_at: now,
        tombstone_generation: gen,
        sync_generation: Math.max(_int(currentIdentity.sync_generation, 0), gen),
        updated_at: now,
      });
      locales.set(key, {
        ...(existing || { hid: resolvedHid, locale: resolvedLocale }),
        active: 0,
        tombstoned: 1,
        sync_generation: Math.max(_int(existing?.sync_generation, 0), gen),
        stored_at: now,
      });
      if (job_id) {
        await repo._setJob(job_id, {
          status: RATEHAWK_CONTENT_JOB_STATES.TOMBSTONED,
          now,
          completed: true,
          error_code: reason,
        });
      }
      return { written: true, reason: null, status: RATEHAWK_CONTENT_JOB_STATES.TOMBSTONED };
    },
    async recordTransientFailure({
      hid,
      locale,
      job_id = null,
      error_code,
      retry_after = null,
      now = Date.now(),
    } = {}) {
      if (RATEHAWK_AUTHORITATIVE_REMOVAL_REASONS.includes(error_code)) {
        return { written: false, reason: "not_transient" };
      }
      if (job_id) {
        await repo._setJob(job_id, {
          status: RATEHAWK_CONTENT_JOB_STATES.RETRYABLE,
          error_code,
          retry_after,
          next_attempt_at: retry_after ? now + retry_after * 1000 : now + 60_000,
          now,
        });
      }
      return {
        written: false,
        tombstoned: false,
        reason: error_code,
        status: RATEHAWK_CONTENT_JOB_STATES.RETRYABLE,
        hid,
        locale,
      };
    },
    async readPublic({ hid, locale } = {}) {
      const resolvedHid = _hid(hid);
      if (resolvedHid == null) {
        return _emptyPublic({ hid: null, locale: locale || null, state: "missing", reason: "invalid_hid" });
      }
      const order = publicLocaleFallbackOrder(locale);
      const requested = _locale(locale) || order[0];
      for (const candidate of order) {
        const row = locales.get(localeKey(resolvedHid, candidate));
        if (!row || row.active !== 1 || row.tombstoned === 1) continue;
        return _toPublicDto(row, requested);
      }
      const ident = identity.get(resolvedHid);
      if (ident?.tombstoned === 1) {
        return _emptyPublic({
          hid: resolvedHid,
          locale: requested,
          state: "stale",
          reason: "tombstoned",
        });
      }
      return _emptyPublic({
        hid: resolvedHid,
        locale: requested,
        state: "missing",
        reason: "not_found",
      });
    },
    async _setJob(job_id, {
      status,
      error_code = null,
      retry_after = null,
      next_attempt_at = null,
      now,
      completed = false,
    }) {
      const current = jobs.get(job_id) || { job_id, attempt_count: 0, created_at: now };
      jobs.set(job_id, {
        ...current,
        status,
        error_code,
        retry_after,
        next_attempt_at,
        attempt_count: _int(current.attempt_count, 0) + 1,
        updated_at: now,
        completed_at: completed ? now : null,
      });
    },
  };
  return repo;
}

function _d1Stmt(db, sql) {
  return db.prepare(sql);
}

export function createRatehawkD1ContentRepository(db) {
  const repo = {
    kind: "d1",
    db,
    async allocateRun({ market_key = null, now = Date.now() } = {}) {
      const current = await _d1Stmt(db, "SELECT current FROM sync_generation_state WHERE id = 1").first();
      const generation = _int(current?.current, 0) + 1;
      await _d1Stmt(
        db,
        "INSERT INTO sync_generation_state (id, current) VALUES (1, ?) ON CONFLICT(id) DO UPDATE SET current = excluded.current",
      ).bind(generation).run();
      const run_id = `rhcs_${generation}`;
      await _d1Stmt(
        db,
        "INSERT INTO sync_runs (run_id, generation, market_key, status, created_at, updated_at, completed_at) VALUES (?, ?, ?, ?, ?, ?, NULL)",
      ).bind(run_id, generation, market_key, RATEHAWK_CONTENT_JOB_STATES.PLANNED, now, now).run();
      return { run_id, generation };
    },
    async planJob(job, now = Date.now()) {
      const job_id = job.job_id || `job_${job.run_id || "local"}_${job.hid}_${job.locale}`;
      await _d1Stmt(
        db,
        `INSERT INTO sync_jobs (
          job_id, run_id, generation, market_key, hid, locale, status, attempt_count,
          error_code, retry_after, next_attempt_at, lease_until, created_at, updated_at, completed_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, 0, NULL, NULL, NULL, ?, ?, ?, NULL)
        ON CONFLICT(job_id) DO UPDATE SET
          status = excluded.status, updated_at = excluded.updated_at, lease_until = excluded.lease_until`,
      ).bind(
        job_id,
        job.run_id ?? "local",
        _int(job.generation, 0),
        job.market_key ?? null,
        job.hid,
        job.locale,
        RATEHAWK_CONTENT_JOB_STATES.PLANNED,
        now + 60_000,
        now,
        now,
      ).run();
      return { ok: true, job_id };
    },
    async getJob(job_id) {
      return _d1Stmt(db, "SELECT * FROM sync_jobs WHERE job_id = ?").bind(job_id).first();
    },
    async getLocale(hid, locale) {
      const row = await _d1Stmt(
        db,
        "SELECT * FROM hotel_content_locale WHERE hid = ? AND locale = ?",
      ).bind(hid, locale).first();
      return _hydrateLocale(row);
    },
    async getIdentity(hid) {
      return _d1Stmt(db, "SELECT * FROM hotel_identity WHERE hid = ?").bind(hid).first();
    },
    async listSearchIndex() {
      const result = await _d1Stmt(db, "SELECT * FROM hotel_search_index").all();
      return result?.results || [];
    },
    async applyNormalized({
      projection,
      generation: incomingGeneration,
      now = Date.now(),
      market_key = null,
      job_id = null,
    } = {}) {
      const prepared = await _prepareWrite(projection, incomingGeneration);
      if (prepared.ok !== true) {
        if (job_id) await repo._setJob(job_id, { status: RATEHAWK_CONTENT_JOB_STATES.FAILED, error_code: prepared.reason, now });
        return { written: false, ...prepared };
      }
      const { persistable, stored, generation: gen, hash } = prepared;
      const existing = await repo.getLocale(persistable.hid, persistable.locale);
      if (existing && gen < existing.sync_generation) {
        if (job_id) {
          await repo._setJob(job_id, {
            status: RATEHAWK_CONTENT_JOB_STATES.FAILED,
            error_code: "older_generation_rejected",
            now,
          });
        }
        return {
          written: false,
          reason: "older_generation_rejected",
          status: RATEHAWK_CONTENT_JOB_STATES.FAILED,
        };
      }
      const currentIdentity = await repo.getIdentity(persistable.hid);
      if (existing && existing.content_hash === hash && existing.tombstoned !== 1) {
        await _d1Stmt(
          db,
          "UPDATE hotel_content_locale SET sync_generation = CASE WHEN sync_generation > ? THEN sync_generation ELSE ? END WHERE hid = ? AND locale = ?",
        ).bind(gen, gen, persistable.hid, persistable.locale).run();
        await _d1Stmt(
          db,
          "UPDATE hotel_identity SET last_success_at = ?, updated_at = ?, sync_generation = CASE WHEN sync_generation > ? THEN sync_generation ELSE ? END, content_hash = ? WHERE hid = ?",
        ).bind(now, now, gen, gen, hash, persistable.hid).run();
        if (job_id) {
          await repo._setJob(job_id, { status: RATEHAWK_CONTENT_JOB_STATES.UNCHANGED, now, completed: true });
        }
        return {
          written: false,
          reason: "unchanged",
          status: RATEHAWK_CONTENT_JOB_STATES.UNCHANGED,
          content_hash: hash,
          generation: gen,
        };
      }
      const row = _localeRecord(stored, hash, gen, now);
      const parts = _marketParts(stored.market_key ?? market_key ?? currentIdentity?.market_key);
      await _d1Stmt(
        db,
        `INSERT INTO hotel_content_locale (
          hid, locale, name, address, lat, lng, star_rating, description_struct, image_refs,
          amenity_groups, room_groups, pets, children_age_ranges, cots_extra_beds, accessibility,
          parking, internet, check_in_time, check_out_time, hotel_deposits, metapolicy_extra_info,
          metapolicy_struct, policy_struct, important_hotel_information, categories, schema_version,
          content_hash, sync_generation, retrieved_at, stored_at, review_required_fields, active, tombstoned
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, 0)
        ON CONFLICT(hid, locale) DO UPDATE SET
          name = excluded.name, address = excluded.address, lat = excluded.lat, lng = excluded.lng,
          star_rating = excluded.star_rating, description_struct = excluded.description_struct,
          image_refs = excluded.image_refs, amenity_groups = excluded.amenity_groups,
          room_groups = excluded.room_groups, pets = excluded.pets,
          children_age_ranges = excluded.children_age_ranges, cots_extra_beds = excluded.cots_extra_beds,
          accessibility = excluded.accessibility, parking = excluded.parking, internet = excluded.internet,
          check_in_time = excluded.check_in_time, check_out_time = excluded.check_out_time,
          hotel_deposits = excluded.hotel_deposits, metapolicy_extra_info = excluded.metapolicy_extra_info,
          metapolicy_struct = excluded.metapolicy_struct, policy_struct = excluded.policy_struct,
          important_hotel_information = excluded.important_hotel_information, categories = excluded.categories,
          schema_version = excluded.schema_version, content_hash = excluded.content_hash,
          sync_generation = excluded.sync_generation, retrieved_at = excluded.retrieved_at,
          stored_at = excluded.stored_at, review_required_fields = excluded.review_required_fields,
          active = 1, tombstoned = 0`,
      ).bind(
        row.hid,
        row.locale,
        row.name,
        row.address,
        row.lat,
        row.lng,
        row.star_rating,
        JSON.stringify(row.description_struct),
        JSON.stringify(row.image_refs),
        JSON.stringify(row.amenity_groups),
        JSON.stringify(row.room_groups),
        JSON.stringify(row.pets),
        JSON.stringify(row.children_age_ranges),
        JSON.stringify(row.cots_extra_beds),
        JSON.stringify(row.accessibility),
        JSON.stringify(row.parking),
        JSON.stringify(row.internet),
        row.check_in_time,
        row.check_out_time,
        JSON.stringify(row.hotel_deposits),
        row.metapolicy_extra_info,
        JSON.stringify(row.metapolicy_struct),
        JSON.stringify(row.policy_struct),
        row.important_hotel_information,
        JSON.stringify(row.categories),
        row.schema_version,
        row.content_hash,
        row.sync_generation,
        row.retrieved_at,
        row.stored_at,
        JSON.stringify(row.review_required_fields),
      ).run();
      await _d1Stmt(
        db,
        `INSERT INTO hotel_identity (
          hid, legacy_id, country_code, city_key, region_id, market_key, lat, lng, star_rating, kind,
          source, active, tombstoned, tombstone_reason, tombstoned_at, tombstone_generation,
          sync_generation, content_hash, first_seen_at, last_success_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'ratehawk', 1, 0, NULL, NULL, NULL, ?, ?, ?, ?, ?)
        ON CONFLICT(hid) DO UPDATE SET
          legacy_id = excluded.legacy_id, country_code = excluded.country_code, city_key = excluded.city_key,
          market_key = excluded.market_key, lat = excluded.lat, lng = excluded.lng,
          star_rating = excluded.star_rating, kind = excluded.kind, active = 1, tombstoned = 0,
          tombstone_reason = NULL, tombstoned_at = NULL, tombstone_generation = NULL,
          sync_generation = excluded.sync_generation, content_hash = excluded.content_hash,
          last_success_at = excluded.last_success_at, updated_at = excluded.updated_at`,
      ).bind(
        persistable.hid,
        stored.legacy_id ?? currentIdentity?.legacy_id ?? null,
        parts.country_code,
        parts.city_key,
        currentIdentity?.region_id ?? null,
        stored.market_key ?? market_key ?? currentIdentity?.market_key ?? null,
        row.lat,
        row.lng,
        row.star_rating,
        stored.kind ?? currentIdentity?.kind ?? null,
        gen,
        hash,
        currentIdentity?.first_seen_at ?? now,
        now,
        now,
      ).run();
      await _d1Stmt(
        db,
        `INSERT INTO hotel_search_index (
          hid, locale, name, address, city_key, country_code, lat, lng, star_rating, description_indexed
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
        ON CONFLICT(hid, locale) DO UPDATE SET
          name = excluded.name, address = excluded.address, city_key = excluded.city_key,
          country_code = excluded.country_code, lat = excluded.lat, lng = excluded.lng,
          star_rating = excluded.star_rating, description_indexed = 0`,
      ).bind(
        row.hid,
        row.locale,
        row.name,
        row.address,
        parts.city_key,
        parts.country_code,
        row.lat,
        row.lng,
        row.star_rating,
      ).run();
      if (job_id) {
        await repo._setJob(job_id, { status: RATEHAWK_CONTENT_JOB_STATES.APPLIED, now, completed: true });
      }
      return {
        written: true,
        reason: null,
        status: RATEHAWK_CONTENT_JOB_STATES.APPLIED,
        content_hash: hash,
        generation: gen,
      };
    },
    async tombstoneAuthoritative({
      hid,
      locale,
      generation: incomingGeneration,
      now = Date.now(),
      reason,
      job_id = null,
    } = {}) {
      if (!RATEHAWK_AUTHORITATIVE_REMOVAL_REASONS.includes(reason)) {
        return { written: false, reason: "tombstone_not_authoritative" };
      }
      const resolvedHid = _hid(hid);
      const resolvedLocale = _locale(locale);
      if (resolvedHid == null || !resolvedLocale) {
        return { written: false, reason: resolvedHid == null ? "invalid_hid" : "locale_unsupported" };
      }
      const gen = _int(incomingGeneration, 0);
      const existing = await repo.getLocale(resolvedHid, resolvedLocale);
      if (existing && gen < existing.sync_generation) {
        return { written: false, reason: "older_generation_rejected" };
      }
      const currentIdentity = await repo.getIdentity(resolvedHid);
      await _d1Stmt(
        db,
        `INSERT INTO hotel_identity (
          hid, source, active, tombstoned, tombstone_reason, tombstoned_at, tombstone_generation,
          sync_generation, first_seen_at, updated_at
        ) VALUES (?, 'ratehawk', 0, 1, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(hid) DO UPDATE SET
          active = 0, tombstoned = 1, tombstone_reason = excluded.tombstone_reason,
          tombstoned_at = excluded.tombstoned_at, tombstone_generation = excluded.tombstone_generation,
          sync_generation = CASE WHEN hotel_identity.sync_generation > excluded.sync_generation
            THEN hotel_identity.sync_generation ELSE excluded.sync_generation END,
          updated_at = excluded.updated_at`,
      ).bind(
        resolvedHid,
        reason,
        now,
        gen,
        Math.max(_int(currentIdentity?.sync_generation, 0), gen),
        currentIdentity?.first_seen_at ?? now,
        now,
      ).run();
      await _d1Stmt(
        db,
        `INSERT INTO hotel_content_locale (
          hid, locale, schema_version, content_hash, sync_generation, retrieved_at, stored_at, active, tombstoned
        ) VALUES (?, ?, ?, '', ?, ?, ?, 0, 1)
        ON CONFLICT(hid, locale) DO UPDATE SET
          active = 0, tombstoned = 1, stored_at = excluded.stored_at,
          sync_generation = CASE WHEN hotel_content_locale.sync_generation > excluded.sync_generation
            THEN hotel_content_locale.sync_generation ELSE excluded.sync_generation END`,
      ).bind(
        resolvedHid,
        resolvedLocale,
        RATEHAWK_CONTENT_SCHEMA_VERSION,
        Math.max(_int(existing?.sync_generation, 0), gen),
        existing?.retrieved_at ?? now,
        now,
      ).run();
      if (job_id) {
        await repo._setJob(job_id, {
          status: RATEHAWK_CONTENT_JOB_STATES.TOMBSTONED,
          now,
          completed: true,
          error_code: reason,
        });
      }
      return { written: true, reason: null, status: RATEHAWK_CONTENT_JOB_STATES.TOMBSTONED };
    },
    async recordTransientFailure({
      hid,
      locale,
      job_id = null,
      error_code,
      retry_after = null,
      now = Date.now(),
    } = {}) {
      if (RATEHAWK_AUTHORITATIVE_REMOVAL_REASONS.includes(error_code)) {
        return { written: false, reason: "not_transient" };
      }
      if (job_id) {
        await repo._setJob(job_id, {
          status: RATEHAWK_CONTENT_JOB_STATES.RETRYABLE,
          error_code,
          retry_after,
          next_attempt_at: retry_after ? now + retry_after * 1000 : now + 60_000,
          now,
        });
      }
      return {
        written: false,
        tombstoned: false,
        reason: error_code,
        status: RATEHAWK_CONTENT_JOB_STATES.RETRYABLE,
        hid,
        locale,
      };
    },
    async readPublic({ hid, locale } = {}) {
      const resolvedHid = _hid(hid);
      if (resolvedHid == null) {
        return _emptyPublic({ hid: null, locale: locale || null, state: "missing", reason: "invalid_hid" });
      }
      const order = publicLocaleFallbackOrder(locale);
      const requested = _locale(locale) || order[0];
      for (const candidate of order) {
        const row = await repo.getLocale(resolvedHid, candidate);
        if (!row || row.active !== 1 || row.tombstoned === 1) continue;
        return _toPublicDto(row, requested);
      }
      const ident = await repo.getIdentity(resolvedHid);
      if (ident?.tombstoned === 1) {
        return _emptyPublic({
          hid: resolvedHid,
          locale: requested,
          state: "stale",
          reason: "tombstoned",
        });
      }
      return _emptyPublic({
        hid: resolvedHid,
        locale: requested,
        state: "missing",
        reason: "not_found",
      });
    },
    async _setJob(job_id, {
      status,
      error_code = null,
      retry_after = null,
      next_attempt_at = null,
      now,
      completed = false,
    }) {
      const current = await repo.getJob(job_id);
      await _d1Stmt(
        db,
        `INSERT INTO sync_jobs (
          job_id, run_id, generation, hid, locale, status, attempt_count, error_code,
          retry_after, next_attempt_at, created_at, updated_at, completed_at
        ) VALUES (?, ?, 0, 0, 'en', ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(job_id) DO UPDATE SET
          status = excluded.status, attempt_count = excluded.attempt_count,
          error_code = excluded.error_code, retry_after = excluded.retry_after,
          next_attempt_at = excluded.next_attempt_at, updated_at = excluded.updated_at,
          completed_at = excluded.completed_at`,
      ).bind(
        job_id,
        current?.run_id ?? "local",
        status,
        _int(current?.attempt_count, 0) + 1,
        error_code,
        retry_after,
        next_attempt_at,
        current?.created_at ?? now,
        now,
        completed ? now : null,
      ).run();
    },
  };
  return repo;
}

export function openRatehawkContentStore(env = {}, injected = null) {
  if (injected && typeof injected.applyNormalized === "function") {
    return { ok: true, store: injected, kind: injected.kind || "injected" };
  }
  if (isRatehawkHotelsDbConfigured(env)) {
    return {
      ok: true,
      store: createRatehawkD1ContentRepository(env[RATEHAWK_HOTELS_DB_BINDING]),
      kind: "d1",
    };
  }
  return { ok: false, reason: "storage_not_configured", store: null };
}

export async function applyRatehawkContentOutcome(store, {
  projection = null,
  generation,
  now = Date.now(),
  hid,
  locale,
  job_id = null,
  market_key = null,
  outcome,
  retry_after = null,
} = {}) {
  if (RATEHAWK_AUTHORITATIVE_REMOVAL_REASONS.includes(outcome)) {
    return store.tombstoneAuthoritative({ hid, locale, generation, now, reason: outcome, job_id });
  }
  if (RATEHAWK_TRANSIENT_CONTENT_ERRORS.includes(outcome)) {
    return store.recordTransientFailure({ hid, locale, job_id, error_code: outcome, retry_after, now });
  }
  if (outcome === "ok" || outcome === "applied") {
    return store.applyNormalized({ projection, generation, now, market_key, job_id });
  }
  return { written: false, reason: outcome || "unknown_outcome", tombstoned: false };
}

export async function readPublicRatehawkHotel(store, { hid, locale } = {}) {
  if (!store || typeof store.readPublic !== "function") {
    return _emptyPublic({
      hid: hid ?? null,
      locale: locale ?? null,
      state: "missing",
      reason: "storage_not_configured",
    });
  }
  return store.readPublic({ hid, locale });
}

export async function readPublicRatehawkHotelFromEnv(env = {}, query = {}, injected = null) {
  const opened = openRatehawkContentStore(env, injected);
  if (opened.ok !== true) {
    return _emptyPublic({
      hid: query.hid ?? null,
      locale: query.locale ?? null,
      state: "missing",
      reason: "storage_not_configured",
    });
  }
  return opened.store.readPublic(query);
}
