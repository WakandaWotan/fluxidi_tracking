-- wrangler D1 migration for future RATEHAWK_HOTELS_DB.
-- Do not apply or create the database in this task.
-- RATEHAWK_CONTENT_KV is not used.

CREATE TABLE IF NOT EXISTS hotel_identity (
  hid INTEGER PRIMARY KEY,
  legacy_id TEXT,
  country_code TEXT,
  city_key TEXT,
  region_id TEXT,
  market_key TEXT,
  lat REAL,
  lng REAL,
  star_rating INTEGER,
  kind TEXT,
  source TEXT NOT NULL DEFAULT 'ratehawk',
  active INTEGER NOT NULL DEFAULT 1,
  tombstoned INTEGER NOT NULL DEFAULT 0,
  tombstone_reason TEXT,
  tombstoned_at INTEGER,
  tombstone_generation INTEGER,
  sync_generation INTEGER NOT NULL DEFAULT 0,
  content_hash TEXT,
  first_seen_at INTEGER NOT NULL,
  last_success_at INTEGER,
  updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS hotel_content_locale (
  hid INTEGER NOT NULL,
  locale TEXT NOT NULL CHECK (locale IN ('en', 'nl', 'fr', 'es')),
  name TEXT,
  address TEXT,
  lat REAL,
  lng REAL,
  star_rating INTEGER,
  description_struct TEXT,
  image_refs TEXT,
  amenity_groups TEXT,
  room_groups TEXT,
  pets TEXT,
  children_age_ranges TEXT,
  cots_extra_beds TEXT,
  accessibility TEXT,
  parking TEXT,
  internet TEXT,
  check_in_time TEXT,
  check_out_time TEXT,
  hotel_deposits TEXT,
  metapolicy_extra_info TEXT,
  metapolicy_struct TEXT,
  policy_struct TEXT,
  important_hotel_information TEXT,
  categories TEXT,
  schema_version INTEGER NOT NULL,
  content_hash TEXT NOT NULL,
  sync_generation INTEGER NOT NULL,
  retrieved_at INTEGER NOT NULL,
  stored_at INTEGER NOT NULL,
  review_required_fields TEXT,
  active INTEGER NOT NULL DEFAULT 1,
  tombstoned INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (hid, locale)
);

CREATE TABLE IF NOT EXISTS hotel_search_index (
  hid INTEGER NOT NULL,
  locale TEXT NOT NULL,
  name TEXT,
  address TEXT,
  city_key TEXT,
  country_code TEXT,
  lat REAL,
  lng REAL,
  star_rating INTEGER,
  description_indexed INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (hid, locale)
);

CREATE TABLE IF NOT EXISTS sync_generation_state (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  current INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS sync_runs (
  run_id TEXT PRIMARY KEY,
  generation INTEGER NOT NULL UNIQUE,
  market_key TEXT,
  status TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  completed_at INTEGER
);

CREATE TABLE IF NOT EXISTS sync_jobs (
  job_id TEXT PRIMARY KEY,
  run_id TEXT NOT NULL,
  generation INTEGER NOT NULL,
  market_key TEXT,
  hid INTEGER NOT NULL,
  locale TEXT NOT NULL,
  status TEXT NOT NULL,
  attempt_count INTEGER NOT NULL DEFAULT 0,
  error_code TEXT,
  retry_after INTEGER,
  next_attempt_at INTEGER,
  lease_until INTEGER,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  completed_at INTEGER
);

CREATE INDEX IF NOT EXISTS idx_hotel_identity_market
  ON hotel_identity (market_key, active, tombstoned);

CREATE INDEX IF NOT EXISTS idx_hotel_content_locale_generation
  ON hotel_content_locale (hid, locale, sync_generation);

CREATE INDEX IF NOT EXISTS idx_sync_jobs_lease
  ON sync_jobs (status, next_attempt_at, lease_until);
