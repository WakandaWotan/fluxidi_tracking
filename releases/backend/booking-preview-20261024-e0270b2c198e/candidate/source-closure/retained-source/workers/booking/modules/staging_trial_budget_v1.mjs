// Candidate for an isolated staging trial. This module is not wired to a Worker.
// Admission is consumed before the associated write or provider request. Failed
// work deliberately does not refund a slot, so retries and timeouts stay bounded.
export const STAGING_TRIAL_BUDGET_SCHEMA_V1 = `CREATE TABLE IF NOT EXISTS staging_trial_budget_v1 (
  trial_id TEXT NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('financial_quote', 'mapbox_directions')),
  used INTEGER NOT NULL DEFAULT 0 CHECK (used >= 0),
  hard_limit INTEGER NOT NULL CHECK (
    (kind = 'financial_quote' AND hard_limit = 16) OR
    (kind = 'mapbox_directions' AND hard_limit = 120)
  ),
  expires_at_ms INTEGER NOT NULL,
  PRIMARY KEY (trial_id, kind),
  CHECK (used <= hard_limit)
)`;

const KINDS = new Set(['financial_quote', 'mapbox_directions']);

export function stagingTrialModeV1(env) {
  return env?.STAGING_TRIAL_MODE === '1';
}

export async function reserveStagingTrialForEnvV1(env, kind, nowMs = Date.now()) {
  if (!stagingTrialModeV1(env)) {
    if (env?.STAGING_TRIAL_ENVIRONMENT === 'staging') throw new Error('staging_trial_mode_required');
    return true; // Existing production path is untouched.
  }
  if (env?.STAGING_TRIAL_ENVIRONMENT !== 'staging') {
    throw new Error('staging_trial_environment_required');
  }
  const db = env?.FINANCIAL_EVIDENCE_DB;
  const primary = typeof db?.withSession === 'function' ? db.withSession('first-primary') : db;
  return reserveStagingTrialUnitV1(primary, {trialId: env?.STAGING_TRIAL_ID, kind, nowMs});
}

export async function reserveStagingTrialUnitV1(db, {trialId, kind, nowMs = Date.now()}) {
  if (typeof db?.prepare !== 'function') throw new Error('staging_trial_budget_database_required');
  if (!/^[A-Za-z0-9_-]{8,64}$/.test(trialId ?? '') || !KINDS.has(kind) ||
      !Number.isSafeInteger(nowMs) || nowMs < 0) {
    throw new Error('staging_trial_budget_invalid_input');
  }
  // A single conditional write is the admission point. No read-then-write
  // counter or isolate-local state can exceed the persisted hard limit.
  const result = await db.prepare(`UPDATE staging_trial_budget_v1
    SET used = used + 1
    WHERE trial_id = ? AND kind = ? AND expires_at_ms > ? AND used < hard_limit`)
    .bind(trialId, kind, nowMs).run();
  if (result?.success !== true || result.meta?.changes !== 1) {
    throw new Error('staging_trial_budget_exhausted_or_unavailable');
  }
  return true;
}
