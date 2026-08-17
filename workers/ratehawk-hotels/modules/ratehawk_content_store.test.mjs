// RATEHAWK-P2 scoped hotel content D1 storage
//
// Run:
//   node --test workers/ratehawk-hotels/modules/ratehawk_content_store.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { runTaxiBookingIsolationProbe } from "../../booking/modules/ratehawk_hotels_facade.mjs";
import {
  handleRatehawkContentSyncRequest,
} from "../fluxidi_ratehawk_hotels_worker.js";
import {
  normalizeOfflineHotelProjection,
  planScopedContentSync,
  toStoredStaticHotelProjection,
} from "./ratehawk_content_sync.mjs";
import {
  RATEHAWK_AUTHORITATIVE_REMOVAL_REASONS,
  RATEHAWK_PUBLIC_LOCALE_FALLBACK,
  RATEHAWK_TRANSIENT_CONTENT_ERRORS,
  applyRatehawkContentOutcome,
  createRatehawkContentRepository,
  hashRatehawkNormalizedContent,
  openRatehawkContentStore,
  publicLocaleFallbackOrder,
  readPublicRatehawkHotel,
  readPublicRatehawkHotelFromEnv,
} from "./ratehawk_content_store.mjs";
import { executeRatehawkContentJob } from "./ratehawk_content_transport.mjs";
import { createRatehawkQuotaBinding } from "./ratehawk_provider_quota.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));

const HOTEL = Object.freeze({
  hid: 8473727,
  id: "test_hotel_legacy",
  name: "Warwick Brussels",
  address: "Rue Duquesnoy 5",
  latitude: 50.845,
  longitude: 4.3543,
  star_rating: 4,
  description_struct: [{ title: "Location" }, { title: "Rooms" }],
  images: [{ url: "https://img.example/licensed.jpg", category: "hero" }],
  amenity_groups: [{ group_name: "General", amenities: ["Wi-Fi"] }],
  room_groups: [{ name: "Superior", room_amenities: ["Safe"] }],
  check_in_time: "15:00:00",
  check_out_time: "12:00:00",
  metapolicy_extra_info: "City tax may apply.",
  policy_struct: [{ title: "House rules" }],
  metapolicy_struct: {
    children: [{ age_start: 0, age_end: 12 }],
    cot: [{}],
    extra_bed: [{}],
    internet: [{}],
    parking: [{}],
    deposit: [{}],
  },
});

function storedProjection(overrides = {}, locale = "en") {
  return toStoredStaticHotelProjection(
    normalizeOfflineHotelProjection(
      { ...HOTEL, ...overrides },
      { locale, retrieved_at: 1_000, market_key: "BE:brussels" },
    ),
  );
}

function repo() {
  return createRatehawkContentRepository({ memory: true });
}

test("1. first normalized locale insert", async () => {
  const store = repo();
  const projection = storedProjection();
  const applied = await store.applyNormalized({
    projection,
    generation: 1,
    now: 1_000,
    market_key: "BE:brussels",
  });
  assert.equal(applied.written, true);
  assert.equal(applied.status, "applied");
  const row = await store.getLocale(8473727, "en");
  const identity = await store.getIdentity(8473727);
  assert.equal(row.hid, 8473727);
  assert.equal(row.locale, "en");
  assert.equal(row.name, "Warwick Brussels");
  assert.equal(row.schema_version, 1);
  assert.equal(row.sync_generation, 1);
  assert.equal(identity.legacy_id, "test_hotel_legacy");
  assert.equal(identity.market_key, "BE:brussels");
  assert.equal(identity.active, 1);
  assert.equal(identity.first_seen_at, 1_000);
  assert.equal(identity.last_success_at, 1_000);
  assert.equal(typeof applied.content_hash, "string");
  assert.equal(applied.content_hash.length, 64);
});

test("2. identical replay becomes unchanged", async () => {
  const store = repo();
  const projection = storedProjection();
  const first = await store.applyNormalized({ projection, generation: 1, now: 1_000 });
  const replay = await store.applyNormalized({ projection, generation: 2, now: 2_000 });
  assert.equal(first.status, "applied");
  assert.equal(replay.written, false);
  assert.equal(replay.status, "unchanged");
  assert.equal(replay.content_hash, first.content_hash);
  const row = await store.getLocale(8473727, "en");
  assert.equal(row.name, "Warwick Brussels");
  assert.equal(row.retrieved_at, 1_000);
  const identity = await store.getIdentity(8473727);
  assert.equal(identity.last_success_at, 2_000);
  assert.equal(identity.first_seen_at, 1_000);
});

test("3. newer generation updates", async () => {
  const store = repo();
  await store.applyNormalized({
    projection: storedProjection({ name: "Old name" }),
    generation: 1,
    now: 1_000,
  });
  const updated = await store.applyNormalized({
    projection: storedProjection({ name: "New name" }),
    generation: 2,
    now: 2_000,
  });
  assert.equal(updated.written, true);
  assert.equal(updated.status, "applied");
  assert.equal((await store.getLocale(8473727, "en")).name, "New name");
  assert.equal((await store.getIdentity(8473727)).sync_generation, 2);
});

test("4. older generation cannot overwrite", async () => {
  const store = repo();
  await store.applyNormalized({
    projection: storedProjection({ name: "Newest" }),
    generation: 5,
    now: 5_000,
  });
  const older = await store.applyNormalized({
    projection: storedProjection({ name: "Stale" }),
    generation: 4,
    now: 9_000,
  });
  assert.equal(older.written, false);
  assert.equal(older.reason, "older_generation_rejected");
  assert.equal((await store.getLocale(8473727, "en")).name, "Newest");
});

test("5. locale rows do not overwrite one another", async () => {
  const store = repo();
  await store.applyNormalized({
    projection: storedProjection({ name: "English" }, "en"),
    generation: 1,
    now: 1_000,
  });
  await store.applyNormalized({
    projection: storedProjection({ name: "Nederlands" }, "nl"),
    generation: 1,
    now: 1_000,
  });
  assert.equal((await store.getLocale(8473727, "en")).name, "English");
  assert.equal((await store.getLocale(8473727, "nl")).name, "Nederlands");
});

test("6. invalid locale and hid are rejected", async () => {
  const store = repo();
  const badHid = await store.applyNormalized({
    projection: { ...storedProjection(), hid: "not-a-hid" },
    generation: 1,
  });
  const badLocale = await store.applyNormalized({
    projection: { ...storedProjection(), locale: "de" },
    generation: 1,
  });
  assert.equal(badHid.written, false);
  assert.equal(badHid.reason, "invalid_hid");
  assert.equal(badLocale.written, false);
  assert.equal(badLocale.reason, "locale_unsupported");
});

test("7. live-price fields are rejected", async () => {
  const store = repo();
  const leaked = {
    ...storedProjection(),
    rates: [{ show_amount: "180.00", book_hash: "secret" }],
  };
  const result = await store.applyNormalized({ projection: leaked, generation: 1 });
  assert.equal(result.written, false);
  assert.equal(result.reason, "live_price_forbidden_in_static_content");
  assert.equal(await store.getLocale(8473727, "en"), null);
});

test("8. credentials and contact values are rejected", async () => {
  const store = repo();
  const email = await store.applyNormalized({
    projection: { ...storedProjection(), email: "restricted@example.test" },
    generation: 1,
  });
  const phone = await store.applyNormalized({
    projection: { ...storedProjection(), phone: "+32000000000" },
    generation: 1,
  });
  const auth = await store.applyNormalized({
    projection: { ...storedProjection(), Authorization: "Basic abc" },
    generation: 1,
  });
  assert.equal(email.reason, "restricted_contact_forbidden");
  assert.equal(phone.reason, "restricted_contact_forbidden");
  assert.equal(auth.reason, "forbidden_secret_or_live_field");
  assert.equal(await store.getLocale(8473727, "en"), null);
});

test("9. description is stored but not indexed", async () => {
  const store = repo();
  const projection = storedProjection();
  await store.applyNormalized({ projection, generation: 1, now: 1_000 });
  const row = await store.getLocale(8473727, "en");
  const index = await store.listSearchIndex();
  assert.equal(row.description_struct.length, 2);
  assert.equal(projection.description_indexed, false);
  assert.equal(index[0].description_indexed, false);
  assert.equal("description_struct" in index[0], false);
  assert.equal(JSON.stringify(index).includes("Location"), false);
});

test("10. transient errors never tombstone", async () => {
  const store = repo();
  await store.applyNormalized({
    projection: storedProjection(),
    generation: 1,
    now: 1_000,
  });
  for (const error_code of RATEHAWK_TRANSIENT_CONTENT_ERRORS) {
    const result = await applyRatehawkContentOutcome(store, {
      hid: 8473727,
      locale: "en",
      generation: 2,
      outcome: error_code,
    });
    assert.equal(result.tombstoned, false, error_code);
    assert.equal(result.status, "retryable", error_code);
  }
  const identity = await store.getIdentity(8473727);
  const row = await store.getLocale(8473727, "en");
  assert.equal(identity.active, 1);
  assert.equal(identity.tombstoned, 0);
  assert.equal(row.active, 1);
  assert.equal(row.tombstoned, 0);
});

test("11. authoritative not-found tombstones", async () => {
  const store = repo();
  await store.applyNormalized({
    projection: storedProjection(),
    generation: 1,
    now: 1_000,
  });
  const stone = await store.tombstoneAuthoritative({
    hid: 8473727,
    locale: "en",
    generation: 2,
    now: 2_000,
    reason: "hotel_not_found",
  });
  assert.equal(stone.written, true);
  assert.equal(stone.status, "tombstoned");
  assert.equal((await store.getIdentity(8473727)).tombstoned, 1);
  assert.equal((await store.getIdentity(8473727)).active, 0);
  assert.equal((await store.getLocale(8473727, "en")).tombstoned, 1);
  const timeoutStone = await store.tombstoneAuthoritative({
    hid: 8473727,
    locale: "en",
    generation: 3,
    reason: "timeout",
  });
  assert.equal(timeoutStone.written, false);
  assert.equal(timeoutStone.reason, "tombstone_not_authoritative");
  assert.deepEqual(RATEHAWK_AUTHORITATIVE_REMOVAL_REASONS, [
    "hotel_not_found",
    "content_removed",
  ]);
});

test("12. later success restores a tombstone", async () => {
  const store = repo();
  await store.applyNormalized({
    projection: storedProjection({ name: "Before" }),
    generation: 1,
    now: 1_000,
  });
  await store.tombstoneAuthoritative({
    hid: 8473727,
    locale: "en",
    generation: 2,
    now: 2_000,
    reason: "hotel_not_found",
  });
  const restored = await store.applyNormalized({
    projection: storedProjection({ name: "Restored" }),
    generation: 3,
    now: 3_000,
  });
  assert.equal(restored.written, true);
  const identity = await store.getIdentity(8473727);
  const row = await store.getLocale(8473727, "en");
  assert.equal(identity.active, 1);
  assert.equal(identity.tombstoned, 0);
  assert.equal(row.active, 1);
  assert.equal(row.tombstoned, 0);
  assert.equal(row.name, "Restored");
});

test("13. missing D1 fails closed", async () => {
  const opened = openRatehawkContentStore({});
  assert.equal(opened.ok, false);
  assert.equal(opened.reason, "storage_not_configured");
  assert.equal(opened.store, null);
  let calls = 0;
  const executed = await executeRatehawkContentJob({
    env: {
      RATEHAWK_KEY_ID: "test-key",
      RATEHAWK_API_KEY: "test-api-secret-do-not-leak",
      RATEHAWK_BASE_URL: "https://api.ratehawk.com",
      RATEHAWK_ENVIRONMENT: "test",
      RATEHAWK_ENABLED: "1",
      RATEHAWK_CONTENT_SYNC_ENABLED: "1",
      RATEHAWK_PROVIDER_QUOTA: createRatehawkQuotaBinding(),
    },
    job: { hid: 8473727, locale: "en", strategy: "single_hid_info" },
    fetchImpl: async () => {
      calls += 1;
      throw new Error("provider_must_not_run");
    },
  });
  assert.equal(executed.invoked, false);
  assert.equal(executed.reason, "storage_not_configured");
  assert.equal(calls, 0);
  const scheduled = await handleRatehawkContentSyncRequest({
    env: { RATEHAWK_CONTENT_SYNC_ENABLED: "1" },
    trigger: "scheduled",
    body: {
      markets: [
        {
          country_code: "BE",
          city_key: "brussels",
          region_id: "test-region-example-not-production",
        },
      ],
      hid_lists: { "BE:brussels": [8473727] },
      locales: ["en"],
    },
    fetchImpl: async () => {
      calls += 1;
      throw new Error("provider_must_not_run");
    },
  });
  assert.equal(scheduled.executed, false);
  assert.equal(scheduled.provider_requested, false);
  assert.equal(scheduled.reason, "storage_not_configured");
  assert.equal(calls, 0);
});

test("14. public adapter returns a safe DTO", async () => {
  const store = repo();
  await store.applyNormalized({
    projection: storedProjection(),
    generation: 1,
    now: 1_000,
  });
  const dto = await readPublicRatehawkHotel(store, { hid: 8473727, locale: "en" });
  assert.equal(dto.ok, true);
  assert.equal(dto.state, "ready");
  assert.equal(dto.hid, 8473727);
  assert.equal(dto.locale_resolved, "en");
  assert.equal(dto.name, "Warwick Brussels");
  assert.equal(dto.description_indexed, false);
  assert.equal(dto.image_refs[0].ref.includes("licensed"), true);
  assert.equal(dto.freshness.source, "ratehawk_offline_static");
  assert.equal(dto.transport_invoked, false);
  assert.equal(dto.stay22_fallback_retained, true);
  assert.equal(dto.mobility_independent_of_ratehawk, true);
  assert.equal(dto.restricted_contact_excluded, true);
  const text = JSON.stringify(dto);
  assert.equal(text.includes("email"), false);
  assert.equal(text.includes("phone"), false);
  assert.equal(text.includes("review_required"), false);
  assert.equal(text.includes("lease_until"), false);
  assert.equal(text.includes("job_id"), false);
  assert.equal(text.includes("RATEHAWK_API_KEY"), false);
});

test("15. locale fallback is deterministic", async () => {
  assert.deepEqual(publicLocaleFallbackOrder("fr"), ["fr", "en", "nl", "es"]);
  assert.deepEqual(publicLocaleFallbackOrder("en"), ["en", "nl", "fr", "es"]);
  assert.deepEqual(RATEHAWK_PUBLIC_LOCALE_FALLBACK, ["en", "nl", "fr", "es"]);
  const store = repo();
  await store.applyNormalized({
    projection: storedProjection({ name: "Nederlands" }, "nl"),
    generation: 1,
    now: 1_000,
  });
  const dto = await readPublicRatehawkHotel(store, { hid: 8473727, locale: "fr" });
  assert.equal(dto.state, "ready");
  assert.equal(dto.locale, "fr");
  assert.equal(dto.locale_resolved, "nl");
  assert.equal(dto.locale_fallback_used, true);
  assert.equal(dto.name, "Nederlands");
});

test("16. stale or missing content never triggers provider transport", async () => {
  let calls = 0;
  const missing = await readPublicRatehawkHotelFromEnv({}, { hid: 8473727, locale: "en" });
  assert.equal(missing.state, "missing");
  assert.equal(missing.transport_invoked, false);
  assert.equal(missing.reason, "storage_not_configured");
  const store = repo();
  const empty = await readPublicRatehawkHotel(store, { hid: 8473727, locale: "en" });
  assert.equal(empty.state, "missing");
  assert.equal(empty.transport_invoked, false);
  await store.tombstoneAuthoritative({
    hid: 8473727,
    locale: "en",
    generation: 1,
    reason: "content_removed",
    now: 1,
  });
  const stale = await readPublicRatehawkHotel(store, { hid: 8473727, locale: "en" });
  assert.equal(stale.state, "stale");
  assert.equal(stale.reason, "tombstoned");
  assert.equal(stale.transport_invoked, false);
  assert.equal(calls, 0);
});

test("17. market and hotel caps remain enforced", () => {
  const many = Array.from({ length: 40 }, (_, i) => i + 1);
  const planned = planScopedContentSync({
    env: {
      RATEHAWK_SEARCH_INITIAL_LIMIT: "3",
      RATEHAWK_SEARCH_ABSOLUTE_MAX: "3",
    },
    markets: [
      {
        country_code: "BE",
        city_key: "brussels",
        region_id: "test-region-example-not-production",
      },
    ],
    hidLists: { "BE:brussels": many },
    locales: ["en", "nl"],
  });
  assert.equal(planned.jobs.length, 6);
  assert.ok(planned.jobs.every((job) => job.hids.length === 1));
  assert.equal(planned.jobs[0].truncated, true);
  assert.equal(planned.storage, "not_configured");
  assert.equal(planned.provider_requested, false);
});

test("18. RateHawk storage stays isolated from taxi", async () => {
  const taxi = runTaxiBookingIsolationProbe({ distance_km: 6 });
  assert.equal(taxi.ok, true);
  assert.equal(taxi.invoked_ratehawk, false);
  assert.equal(taxi.amount_minor, 1500);
  const wrangler = readFileSync(join(HERE, "../wrangler.toml"), "utf8");
  const schema = readFileSync(join(HERE, "../schema.sql"), "utf8");
  assert.match(wrangler, /# \[\[d1_databases\]\]/);
  assert.match(wrangler, /binding = "RATEHAWK_HOTELS_DB"/);
  assert.equal(/^\s*\[\[d1_databases\]\]/m.test(wrangler), false);
  assert.equal(/^\s*\[\[kv_namespaces\]\]/m.test(wrangler), false);
  assert.match(schema, /RATEHAWK_CONTENT_KV is not used/);
  assert.match(schema, /CREATE TABLE IF NOT EXISTS hotel_identity/);
  assert.match(schema, /CREATE TABLE IF NOT EXISTS hotel_content_locale/);
  assert.match(schema, /CREATE TABLE IF NOT EXISTS sync_jobs/);
  const hashA = await hashRatehawkNormalizedContent(storedProjection());
  const hashB = await hashRatehawkNormalizedContent(storedProjection());
  assert.equal(hashA, hashB);
});
