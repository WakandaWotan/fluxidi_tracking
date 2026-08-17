/**
 * Production public RateHawk prebook + acceptance on the Hotels Worker.
 *
 * Booking proxies here through RATEHAWK_HOTELS only. The test Worker
 * cannot serve this path. Acceptance makes zero provider calls.
 */

import { sha256Hex } from "./crypto_utils.js";
import { normalizeRatehawkRateOffer } from "./ratehawk_affiliate_contract.mjs";
import { isRatehawkIsolatedTestWorker } from "./ratehawk_test_activation.mjs";
import {
  openRatehawkOfferReference,
  toCustomerHotelpageOffer,
} from "./ratehawk_hotelpage_worker.mjs";
import {
  RATEHAWK_PROVIDER,
  isRatehawkPrebookInvocationAllowed,
  redactRatehawkSecrets,
  resolveRatehawkConfig,
} from "./ratehawk_provider.mjs";
import {
  RATEHAWK_ACCEPTED_REF_PREFIX,
  RATEHAWK_OFFER_REF_PURPOSE,
  RATEHAWK_PREBOOK_ACCEPT_TRIGGER,
  RATEHAWK_PREBOOK_REF_PREFIX,
  RATEHAWK_PREBOOK_TRIGGER,
  buildOfferDisplaySnapshot,
  buildSafePrebookDisputeSnapshot,
  compareRatehawkPrebookTerms,
  fingerprintOfferDisplaySnapshot,
  hasForbiddenPublicPrebookClientControl,
  localizePrebookChanges,
  prebookActionLabels,
} from "./ratehawk_prebook_contract.mjs";
import { fetchRatehawkPrebook } from "./ratehawk_prebook_transport.mjs";
import {
  openRatehawkAcceptedReference,
  openRatehawkPrebookReference,
  sealRatehawkAcceptedReference,
  sealRatehawkPrebookReference,
} from "./ratehawk_prebook_tokens.mjs";

export const RATEHAWK_HOTELS_PREBOOK_PATH = "/internal/prebook";
export const RATEHAWK_HOTELS_PREBOOK_ACCEPT_PATH = "/internal/prebook/accept";

function _text(value, max = 200) {
  const text = String(value ?? "").trim();
  if (!text) return "";
  return text.length > max ? text.slice(0, max) : text;
}

function _locale(value) {
  const raw = _text(value, 8).toLowerCase();
  return ["nl", "en", "fr", "es"].includes(raw) ? raw : "nl";
}

function _guard({ reason, invoked = false, retryAfter = null, extras = {} } = {}) {
  return redactRatehawkSecrets({
    ok: true,
    invoked: invoked === true,
    reason: reason || "prebook_disabled",
    retryable: [
      "timeout",
      "provider_error",
      "provider_fetch_failed",
      "provider_quota_exhausted",
      "production_quota_unconfigured",
    ].includes(reason),
    retry_after:
      retryAfter == null || !Number.isFinite(Number(retryAfter))
        ? null
        : Math.max(1, Math.round(Number(retryAfter))),
    progress_blocked: true,
    acceptance_allowed: false,
    prebook_ref: null,
    accepted_ref: null,
    changes: [],
    current_terms: null,
    dispute_snapshot: null,
    stay22_fallback_retained: true,
    mobility_independent_of_ratehawk: true,
    existing_actions: [
      "saved",
      "nearby_events",
      "taxi_to_this_event",
      "taxi_to_this_stay",
      "airport_transfer",
      "stay22_fallback_availability",
    ],
    commercial: {
      fluxidi_role: "affiliate",
      customer_pays_fluxidi: false,
      mollie_involved: false,
    },
    provider: RATEHAWK_PROVIDER,
    ...extras,
  });
}

function _firstAcceptedRate(rates) {
  if (!Array.isArray(rates)) return { raw: null, offer: null };
  for (const raw of rates) {
    const offer = normalizeRatehawkRateOffer(raw);
    if (offer?.ok === true && offer.hard_stop !== true) {
      return { raw, offer };
    }
    if (offer?.hard_stop === true) {
      return { raw, offer };
    }
  }
  return { raw: null, offer: null };
}

export async function handleRatehawkPrebookRequest({
  env = {},
  body = {},
  fetchImpl = null,
  now = Date.now(),
} = {}) {
  if (isRatehawkIsolatedTestWorker(env)) {
    return _guard({ reason: "production_path_forbidden_on_test_worker" });
  }
  const requestBody =
    body && typeof body === "object" && !Array.isArray(body) ? body : {};
  if (hasForbiddenPublicPrebookClientControl(requestBody)) {
    return _guard({ reason: "client_control_forbidden" });
  }
  const trigger = _text(requestBody.trigger, 40) || RATEHAWK_PREBOOK_TRIGGER;
  if (trigger !== RATEHAWK_PREBOOK_TRIGGER) {
    return _guard({ reason: "unsupported_trigger" });
  }
  if (!isRatehawkPrebookInvocationAllowed(env)) {
    return _guard({ reason: "prebook_disabled" });
  }
  const config = resolveRatehawkConfig(env);
  if (config.invocation_allowed !== true || !config.has_key_id || !config.has_api_key) {
    return _guard({ reason: config.reasons[0] || "missing_configuration" });
  }
  if (!_text(env?.RATEHAWK_OFFER_REF_SECRET, 800)) {
    return _guard({ reason: "offer_ref_secret_missing" });
  }

  const opened = await openRatehawkOfferReference(env, requestBody.offer_ref, {
    now,
  });
  if (opened.ok !== true) {
    return _guard({ reason: opened.reason || "offer_ref_invalid" });
  }
  const claims = opened.claims || {};
  if (claims.purpose && claims.purpose !== RATEHAWK_OFFER_REF_PURPOSE) {
    return _guard({ reason: "offer_ref_purpose_mismatch" });
  }
  if (!claims.book_hash || !claims.hid || !claims.display_snapshot) {
    return _guard({ reason: "offer_ref_incomplete" });
  }

  const locale = _locale(requestBody.locale);
  const transport = await fetchRatehawkPrebook({
    env,
    bookHash: claims.book_hash,
    fetchImpl,
    now,
  });
  if (transport.invoked !== true) {
    return _guard({
      reason: transport.reason || "prebook_disabled",
      retryAfter: transport.retry_after,
    });
  }
  if (transport.ok !== true) {
    return _guard({
      reason: transport.reason || "provider_error",
      invoked: true,
      retryAfter: transport.retry_after,
    });
  }

  const hotel = Array.isArray(transport.hotels) ? transport.hotels[0] : null;
  if (!hotel || Number(hotel.hid) !== Number(claims.hid)) {
    return _guard({
      reason: "availability_lost",
      invoked: true,
    });
  }
  const accepted = _firstAcceptedRate(hotel.rates);
  if (accepted.offer?.hard_stop === true) {
    return _guard({
      reason: accepted.offer.reason || "unmapped_critical_field",
      invoked: true,
    });
  }
  if (!accepted.offer) {
    return _guard({
      reason: "availability_lost",
      invoked: true,
    });
  }

  const afterSnapshot = buildOfferDisplaySnapshot(accepted.offer);
  const comparison = compareRatehawkPrebookTerms(
    claims.display_snapshot,
    afterSnapshot,
  );
  if (comparison.ok !== true) {
    return _guard({
      reason: comparison.reason || "comparison_incomplete",
      invoked: true,
    });
  }

  const termsRevision = await sha256Hex(fingerprintOfferDisplaySnapshot(afterSnapshot));
  const selectedFingerprint =
    claims.display_fingerprint ||
    (await sha256Hex(fingerprintOfferDisplaySnapshot(claims.display_snapshot)));
  const sealed = await sealRatehawkPrebookReference(
    env,
    {
      hid: Number(claims.hid),
      checkin: claims.checkin,
      checkout: claims.checkout,
      residency: claims.residency,
      currency: claims.currency,
      guests: claims.guests,
      book_hash: accepted.offer.book_hash || claims.book_hash,
      match_hash: accepted.offer.match_hash || claims.match_hash || null,
      selected_fingerprint: selectedFingerprint,
      terms_revision: termsRevision,
      display_snapshot: afterSnapshot,
      changes_disclosed: comparison.changed === true,
      change_codes: comparison.changes.map((row) => row.code),
    },
    { now },
  );
  if (sealed.ok !== true) {
    return _guard({
      reason: sealed.reason || "offer_ref_secret_unavailable",
      invoked: true,
    });
  }

  const currentTerms = toCustomerHotelpageOffer({
    ...accepted.offer,
    offer_ref: requestBody.offer_ref,
    freshness: {
      bookable: comparison.progress_blocked !== true,
      retrieved_at: Number(now),
      expires_at: sealed.expires_at,
    },
  });

  return redactRatehawkSecrets(
    {
      ok: true,
      invoked: true,
      reason: comparison.progress_blocked ? comparison.reason : null,
      retryable: false,
      progress_blocked: comparison.progress_blocked === true,
      acceptance_allowed: comparison.acceptance_allowed === true,
      changed: comparison.changed === true,
      changes: localizePrebookChanges(comparison.changes, locale),
      flags: comparison.flags,
      current_terms: currentTerms,
      selected_terms: claims.display_snapshot,
      prebook_ref: comparison.acceptance_allowed ? sealed.token : null,
      prebook_ref_expires_at: comparison.acceptance_allowed
        ? sealed.expires_at
        : null,
      terms_revision: termsRevision,
      accepted_ref: null,
      dispute_snapshot: null,
      labels: prebookActionLabels(locale),
      stay22_fallback_retained: true,
      mobility_independent_of_ratehawk: true,
      existing_actions: [
        "saved",
        "nearby_events",
        "taxi_to_this_event",
        "taxi_to_this_stay",
        "airport_transfer",
        "stay22_fallback_availability",
      ],
      retrieved_at: Number(now),
      expires_at: sealed.expires_at,
      commercial: {
        fluxidi_role: "affiliate",
        customer_pays_fluxidi: false,
        mollie_involved: false,
      },
      provider: RATEHAWK_PROVIDER,
    },
    env,
  );
}

export async function handleRatehawkPrebookAcceptRequest({
  env = {},
  body = {},
  now = Date.now(),
} = {}) {
  if (isRatehawkIsolatedTestWorker(env)) {
    return _guard({ reason: "production_path_forbidden_on_test_worker" });
  }
  const requestBody =
    body && typeof body === "object" && !Array.isArray(body) ? body : {};
  if (hasForbiddenPublicPrebookClientControl(requestBody)) {
    return _guard({ reason: "client_control_forbidden" });
  }
  const trigger =
    _text(requestBody.trigger, 40) || RATEHAWK_PREBOOK_ACCEPT_TRIGGER;
  if (trigger !== RATEHAWK_PREBOOK_ACCEPT_TRIGGER) {
    return _guard({ reason: "unsupported_trigger" });
  }
  if (!isRatehawkPrebookInvocationAllowed(env)) {
    return _guard({ reason: "prebook_disabled" });
  }
  if (!_text(env?.RATEHAWK_OFFER_REF_SECRET, 800)) {
    return _guard({ reason: "offer_ref_secret_missing" });
  }

  const opened = await openRatehawkPrebookReference(env, requestBody.prebook_ref, {
    now,
  });
  if (opened.ok !== true) {
    return _guard({ reason: opened.reason || `${RATEHAWK_PREBOOK_REF_PREFIX}_invalid` });
  }
  const claims = opened.claims || {};
  const expectedRevision = _text(requestBody.terms_revision, 120);
  if (expectedRevision && expectedRevision !== claims.terms_revision) {
    return _guard({ reason: "terms_revision_mismatch" });
  }

  const locale = _locale(requestBody.locale);
  const accepted = await sealRatehawkAcceptedReference(
    env,
    {
      hid: claims.hid,
      checkin: claims.checkin,
      checkout: claims.checkout,
      residency: claims.residency,
      currency: claims.currency,
      guests: claims.guests,
      book_hash: claims.book_hash,
      match_hash: claims.match_hash || null,
      terms_revision: claims.terms_revision,
      display_snapshot: claims.display_snapshot,
      changes_disclosed: claims.changes_disclosed === true,
      change_codes: claims.change_codes || [],
      prebook_ref_purpose: claims.purpose,
    },
    { now },
  );
  if (accepted.ok !== true) {
    return _guard({ reason: accepted.reason || "offer_ref_secret_unavailable" });
  }

  const snapshot = buildSafePrebookDisputeSnapshot({
    hid: claims.hid,
    snapshot: claims.display_snapshot,
    comparison: {
      changes: (claims.change_codes || []).map((code) => ({
        code,
        labels: null,
        before: null,
        after: null,
      })),
    },
    locale,
    termsRevision: claims.terms_revision,
    acceptedAt: Number(now),
  });

  return redactRatehawkSecrets(
    {
      ok: true,
      invoked: false,
      reason: null,
      retryable: false,
      progress_blocked: false,
      acceptance_allowed: false,
      accepted: true,
      prebook_ref: requestBody.prebook_ref,
      accepted_ref: accepted.token,
      accepted_ref_expires_at: accepted.expires_at,
      terms_revision: claims.terms_revision,
      dispute_snapshot: snapshot,
      stay22_fallback_retained: true,
      mobility_independent_of_ratehawk: true,
      existing_actions: [
        "saved",
        "nearby_events",
        "taxi_to_this_event",
        "taxi_to_this_stay",
        "airport_transfer",
        "stay22_fallback_availability",
      ],
      commercial: {
        fluxidi_role: "affiliate",
        customer_pays_fluxidi: false,
        mollie_involved: false,
      },
      provider: RATEHAWK_PROVIDER,
    },
    env,
  );
}

export function assertAcceptedRevisionMatches(acceptedClaims, prebookClaims) {
  if (!acceptedClaims?.terms_revision || !prebookClaims?.terms_revision) {
    return { ok: false, reason: "terms_revision_mismatch" };
  }
  if (acceptedClaims.terms_revision !== prebookClaims.terms_revision) {
    return { ok: false, reason: "stale_acceptance" };
  }
  return { ok: true, reason: null };
}

export {
  openRatehawkAcceptedReference,
  RATEHAWK_ACCEPTED_REF_PREFIX,
};
