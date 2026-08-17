-- Future RATEHAWK_HOTELS_DB searchable index. Not applied in this task.
-- Localized policy documents belong in RATEHAWK_CONTENT_KV / later R2.
-- Image binaries are never stored here.

CREATE TABLE IF NOT EXISTS hotel_index (
  hid INTEGER NOT NULL,
  locale TEXT NOT NULL,
  market_key TEXT,
  name TEXT,
  country_code TEXT,
  city_key TEXT,
  lat REAL,
  lng REAL,
  content_revision TEXT,
  retrieved_at INTEGER,
  tombstone INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (hid, locale)
);

CREATE TABLE IF NOT EXISTS sync_job_state (
  job_id TEXT PRIMARY KEY,
  market_key TEXT,
  locale TEXT,
  hid_offset INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER,
  status TEXT
);
