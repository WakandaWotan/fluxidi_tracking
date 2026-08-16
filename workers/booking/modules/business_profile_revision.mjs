/**
 * Central monotonic revisioning for the Booking `business_profile:v1` record.
 *
 * Command Center projects company name, primary contact email, phone, VAT and
 * verification status off this KV record. It needs a single freshness signal
 * that increases on every real semantic change. Historically the record only
 * carried a literal `version: 1` and a per-field `email_revision`, so a name or
 * phone change never advanced a record-level revision and downstream projectors
 * kept re-reading stale data.
 *
 * `source_revision` is that record-level signal:
 *   - a positive, monotone integer;
 *   - seeded strictly above any pre-existing `source_revision`, `version` and
 *     `email_revision` so legacy records (source_revision=null, version=1,
 *     email_revision=N) jump past N on their next semantic write;
 *   - incremented exactly once per real semantic change;
 *   - preserved (never re-incremented) on an idempotent replay whose normalized
 *     content is byte-identical;
 *   - written in the same mutation as `updated_at`.
 *
 * `version` and `email_revision` are preserved verbatim for backwards
 * compatibility, but they are no longer the freshness source of truth.
 */

/** Coerce to a monotone-safe non-negative integer (0 for null/invalid). */
export function toMonotonicInt(value) {
  const n = Number(value);
  if (!Number.isFinite(n)) return 0;
  const i = Math.trunc(n);
  return i > 0 ? i : 0;
}

function readRecordSourceRevision(record) {
  const rec = record && typeof record === "object" ? record : {};
  const nested =
    rec.business_profile && typeof rec.business_profile === "object"
      ? rec.business_profile
      : {};
  return Math.max(
    toMonotonicInt(rec.source_revision),
    toMonotonicInt(rec.sourceRevision),
    toMonotonicInt(nested.source_revision),
    toMonotonicInt(nested.sourceRevision),
  );
}

/**
 * Floor that any freshly bumped revision must strictly exceed: the max of the
 * existing `source_revision`, the wrapper `version` and the `email_revision`.
 */
export function businessProfileRevisionFloor(existingRecord, existingProfile) {
  const rec = existingRecord && typeof existingRecord === "object" ? existingRecord : {};
  const nested =
    rec.business_profile && typeof rec.business_profile === "object"
      ? rec.business_profile
      : {};
  const prof = existingProfile && typeof existingProfile === "object" ? existingProfile : {};
  return Math.max(
    readRecordSourceRevision(rec),
    toMonotonicInt(rec.version),
    toMonotonicInt(nested.version),
    toMonotonicInt(prof.version),
    toMonotonicInt(nested.email_revision),
    toMonotonicInt(nested.emailRevision),
    toMonotonicInt(prof.email_revision),
    toMonotonicInt(prof.emailRevision),
  );
}

// Fields that never participate in the semantic-change fingerprint: the
// revision markers themselves. Everything else in the normalized profile
// (name, email, phone, vat, verification status, audit, etc.) is significant.
const REVISION_MARKER_KEYS = ["source_revision", "sourceRevision"];

function stableCanonicalJson(value) {
  if (Array.isArray(value)) {
    return `[${value.map(stableCanonicalJson).join(",")}]`;
  }
  if (value && typeof value === "object") {
    const keys = Object.keys(value).sort();
    return `{${keys
      .map((key) => `${JSON.stringify(key)}:${stableCanonicalJson(value[key])}`)
      .join(",")}}`;
  }
  return JSON.stringify(value === undefined ? null : value);
}

/**
 * Deterministic fingerprint of the semantic profile content. Order-independent
 * and revision-marker-free so an idempotent replay of identical content yields
 * an identical fingerprint.
 */
export function businessProfileSemanticFingerprint(profile) {
  const source = profile && typeof profile === "object" ? profile : {};
  const clone = { ...source };
  for (const key of REVISION_MARKER_KEYS) delete clone[key];
  return stableCanonicalJson(clone);
}

/**
 * Decide the `source_revision` + `updated_at` for the next persisted record.
 *
 * @param {object}  args
 * @param {object=} args.existingRecord   Raw stored wrapper (may be null).
 * @param {object=} args.existingProfile  Normalized existing business_profile.
 * @param {object}  args.nextProfile      Normalized business_profile to persist.
 * @param {string=} args.nowIso           ISO timestamp for a real mutation.
 * @returns {{ source_revision: number, updated_at: string, changed: boolean }}
 */
export function resolveBusinessProfileRevision({
  existingRecord = null,
  existingProfile = null,
  nextProfile = null,
  nowIso = null,
} = {}) {
  const now = String(nowIso || new Date().toISOString());
  const prevRevision = readRecordSourceRevision(existingRecord);
  const contentUnchanged =
    businessProfileSemanticFingerprint(existingProfile) ===
    businessProfileSemanticFingerprint(nextProfile);

  // Idempotent replay: identical content AND an already-established revision.
  // Keep both the revision and the timestamp so replays never advance freshness.
  if (contentUnchanged && prevRevision >= 1) {
    const previousUpdatedAt =
      typeof existingRecord?.updated_at === "string" && existingRecord.updated_at.trim()
        ? existingRecord.updated_at
        : now;
    return { source_revision: prevRevision, updated_at: previousUpdatedAt, changed: false };
  }

  // Either the content changed, or this is the first write that establishes a
  // record-level revision for a legacy (source_revision=null) profile. Both are
  // real freshness events for downstream projectors.
  const floor = businessProfileRevisionFloor(existingRecord, existingProfile);
  return { source_revision: floor + 1, updated_at: now, changed: true };
}

/**
 * Build the persisted wrapper and the stamped profile. `source_revision` lives
 * on the wrapper (authoritative) and is mirrored inside the profile so a
 * projector reading either level finds the same monotone integer. `version` is
 * kept at 1 for backwards compatibility.
 */
export function stampBusinessProfileRecord({ profile, sourceRevision, updatedAt }) {
  const revision = toMonotonicInt(sourceRevision) || 1;
  const updated_at = String(updatedAt || new Date().toISOString());
  const stampedProfile = {
    ...(profile && typeof profile === "object" ? profile : {}),
    source_revision: revision,
    sourceRevision: revision,
  };
  return {
    record: {
      version: 1,
      updated_at,
      source_revision: revision,
      business_profile: stampedProfile,
    },
    profile: stampedProfile,
  };
}
