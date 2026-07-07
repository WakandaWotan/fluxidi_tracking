-- Fluxidi Learning API — CLOUD-LEARN-2 D1 schema (fluxidi-learning-db)
-- Anonymized operational ride lessons only. No customer/booking/payment/
-- document data, no seed data. Matches the schema comment in
-- fluxidi_learning_worker.js.

CREATE TABLE IF NOT EXISTS ride_lessons (
  id TEXT PRIMARY KEY,
  created_at TEXT NOT NULL,
  tenant_scope_hash TEXT NOT NULL,
  company_scope_hash TEXT NOT NULL,
  country TEXT NOT NULL,
  ride_type TEXT NOT NULL,
  airport_code TEXT,
  weekday INTEGER,
  hour_bucket INTEGER,
  planned_duration_seconds INTEGER,
  actual_duration_seconds INTEGER,
  eta_delta_seconds INTEGER,
  planned_distance_m INTEGER,
  actual_distance_m INTEGER,
  pickup_wait_seconds INTEGER,
  driver_arrival_delta_seconds INTEGER,
  route_confidence_avg REAL,
  gps_confidence_avg REAL,
  reroute_count INTEGER,
  off_route_events INTEGER,
  prediction_events INTEGER,
  completed INTEGER,
  cancelled INTEGER,
  outcome TEXT,
  sample_source TEXT
);

CREATE INDEX IF NOT EXISTS idx_ride_lessons_scope_lookup
  ON ride_lessons (tenant_scope_hash, company_scope_hash, country,
                   ride_type, airport_code, weekday, hour_bucket);

-- NAV-AI-3: sanitized navigation complexity events (admin dry-run ingest only).
-- Advisory/learning data only — no coordinates, addresses, or identity.
CREATE TABLE IF NOT EXISTS nav_complexity_events (
  id TEXT PRIMARY KEY,
  created_at TEXT NOT NULL,
  reason_code TEXT NOT NULL,
  severity TEXT NOT NULL,
  confidence_bucket TEXT NOT NULL,
  snap_dist_bucket TEXT NOT NULL,
  speed_bucket TEXT NOT NULL,
  maneuver_type TEXT NOT NULL,
  maneuver_modifier TEXT NOT NULL,
  prediction_repeated INTEGER NOT NULL,
  trust_bearing INTEGER NOT NULL,
  trust_instruction INTEGER NOT NULL,
  dry_run INTEGER NOT NULL DEFAULT 1,
  source TEXT NOT NULL,
  raw_json TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_nav_complexity_events_created
  ON nav_complexity_events (created_at DESC);

CREATE INDEX IF NOT EXISTS idx_nav_complexity_events_test_cleanup
  ON nav_complexity_events (source, dry_run);
