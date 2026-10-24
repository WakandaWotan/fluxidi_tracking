/**
 * Isolated admin test-only RateHawk prebook + acceptance.
 *
 * Separate from /internal/prebook. Requires RATEHAWK_TEST_PREBOOK_ENABLED
 * and the test Worker surface. Reuses the production normalizer and
 * comparison contract. Acceptance makes zero provider calls.
 */

import { sha256Hex } from "./crypto_utils.js";
import { normalizeRatehawkRateOffer } from "./ratehawk_affiliate_contract.mjs";
import {
  openRatehawkOfferReference,
  toCustomerHotelpageOffer,
} from "./ratehawk_hotelpage_worker.mjs";
import {
  RATEHAWK_PREBOOK_PATH,
  RATEHAWK_PROVIDER,
  ratehawkProviderAuthHeader,
  redactRatehawkSecrets,
} from "./ratehawk_provider.mjs";
import {
  RATEHAWK_QUOTA_ENDPOINTS,
  reserveRatehawkProviderQuota,
} from "./ratehawk_provider_quota.mjs";
import {
  RATEHAWK_PREBOOK_TIMEOUT_MS,
  buildOfferDisplaySnapshot,
  buildSafePrebookDisputeSnapshot,
  compareRatehawkPrebookTerms,
  fingerprintOfferDisplaySnapshot,
  hasForbiddenPublicPrebookClientControl,
  localizePrebookChanges,
  prebookActionLabels,
} from "./ratehawk_prebook_contract.mjs";
import {
  openRatehawkAcceptedReference,
  openRatehawkPrebookReference,
  sealRatehawkAcceptedReference,
  sealRatehawkPrebookReference,
} from "./ratehawk_prebook_tokens.mjs";
import {
  RATEHAWK_TEST_HID,
  RATEHAWK_TEST_OPERATION_PREBOOK,
  RATEHAWK_TEST_PREBOOK_ACCEPT_TRIGGER,
  RATEHAWK_TEST_PREBOOK_TRIGGER,
  RATEHAWK_TEST_TIMEOUT_MS,
  RATEHAWK_TEST_TOKEN_SURFACE,
  assertRatehawkTestOfferClaims,
  assertRatehawkTestProviderConfig,
  evaluateRatehawkTestPrebookGate,
  hasForbiddenRatehawkTestClientControl,
} from "./ratehawk_test_activation.mjs";

export const RATEHAWK_HOTELS_TEST_PREBOOK_PATH = "/internal/test-prebook";
export const RATEHAWK_HOTELS_TEST_PREBOOK_ACCEPT_PATH =
  "/internal/test-prebook/accept";

function _text(value, max = 200) {
  const text = String(value ?? "").trim();
  if (!text) return "";
  return text.length > max ? text.slice(0, max) : text;
}

function _locale(value) {
  const raw = _text(value, 8).toLowerCase();
  return ["nl", "en", "fr", "es"].includes(raw) ? raw : "nl";
}

function _isAbortError(err) {
  const name = String(err?.name || "");
  const message = String(err?.message || "").toLowerCase();
  return name === "AbortError" || message.includes("abort");
}

function _guard({ reason, invoked = false, retryAfter = null, extras = {} } = {}) {
  return redactRatehawkSecrets({
    ok: true,
    invoked: invoked === true,
    reason: reason || "test_prebook_disabled",
    retryable: [
      "timeout",
      "provider_error",
      "provider_fetch_failed",
      "provider_quota_exhausted",
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
    test_surface: true,
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

function _extractHotels(payload) {
  const data = payload?.data;
  if (Array.isArray(data?.hotels)) return data.hotels;
  if (Array.isArray(data)) return data;
  return [];
}

export async function fetchRatehawkTestPrebook({
  env,
  bookHash,
  fetchImpl = null,
  timeoutMs = RATEHAWK_PREBOOK_TIMEOUT_MS,
  now = Date.now(),
} = {}) {
  const gate = evaluateRatehawkTestPrebookGate(env);
  if (gate.ok !== true) {
    return { ok: false, invoked: false, reason: gate.reason, hotels: [] };
  }
  const configCheck = assertRatehawkTestProviderConfig(env);
  if (configCheck.ok !== true) {
    return {
      ok: false,
      invoked: false,
      reason: configCheck.reason,
      hotels: [],
    };
  }
  const hash = String(bookHash || "").trim();
  if (!hash) {
    return { ok: false, invoked: false, reason: "offer_ref_invalid", hotels: [] };
  }

  const fetchFn =
    typeof fetchImpl === "function"
      ? fetchImpl
      : typeof fetch === "function"
        ? fetch
        : null;
  if (!fetchFn) {
    return {
      ok: false,
      invoked: false,
      reason: "transport_unavailable",
      hotels: [],
    };
  }
  const authorization = ratehawkProviderAuthHeader(env);
  if (!authorization) {
    return {
      ok: false,
      invoked: false,
      reason: "missing_configuration",
      hotels: [],
    };
  }

  const quota = await reserveRatehawkProviderQuota({
    env,
    endpoint: RATEHAWK_QUOTA_ENDPOINTS.PREBOOK,
    now,
  });
  if (quota.allowed !== true) {
    return {
      ok: false,
      invoked: false,
      reason: quota.reason || "provider_quota_exhausted",
      retry_after: quota.retry_after,
      hotels: [],
    };
  }

  const url = `${configCheck.config.base_url}${RATEHAWK_PREBOOK_PATH}`;
  const controller =
    typeof AbortController === "function" ? new AbortController() : null;
  const timer =
    controller && typeof setTimeout === "function"
      ? setTimeout(
          () => controller.abort(),
          Number(timeoutMs) || RATEHAWK_TEST_TIMEOUT_MS,
        )
      : null;

  try {
    const response = await fetchFn(url, {
      method: "POST",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
        Authorization: authorization,
      },
      body: JSON.stringify({ hash }),
      signal: controller?.signal,
    });
    const httpStatus = Number(response?.status || 0);
    if (httpStatus < 200 || httpStatus >= 300) {
      return {
        ok: false,
        invoked: true,
        reason: httpStatus === 429 ? "endpoint_exceeded_limit" : "provider_error",
        hotels: [],
      };
    }
    let payload = null;
    try {
      payload = await response.json();
    } catch {
      return {
        ok: false,
        invoked: true,
        reason: "provider_malformed_response",
        hotels: [],
      };
    }
    if (String(payload?.status || "").trim().toLowerCase() !== "ok") {
      return { ok: false, invoked: true, reason: "provider_error", hotels: [] };
    }
    const hotels = _extractHotels(payload);
    return {
      ok: true,
      invoked: true,
      reason: null,
      operation: RATEHAWK_TEST_OPERATION_PREBOOK,
      hotels,
      hotel_count: hotels.length,
    };
  } catch (err) {
    return {
      ok: false,
      invoked: true,
      reason: _isAbortError(err) ? "timeout" : "provider_fetch_failed",
      hotels: [],
    };
  } finally {
    if (timer) clearTimeout(timer);
  }
}

export async function handleRatehawkTestPrebookRequest({
  env = {},
  body = {},
  fetchImpl = null,
  now = Date.now(),
} = {}) {
  const requestBody =
    body && typeof body === "object" && !Array.isArray(body) ? body : {};
  if (
    hasForbiddenRatehawkTestClientControl(requestBody) ||
    hasForbiddenPublicPrebookClientControl(requestBody)
  ) {
    return _guard({ reason: "client_control_forbidden" });
  }
  const trigger = _text(requestBody.trigger, 40) || RATEHAWK_TEST_PREBOOK_TRIGGER;
  if (trigger !== RATEHAWK_TEST_PREBOOK_TRIGGER) {
    return _guard({ reason: "unsupported_trigger" });
  }
  const gate = evaluateRatehawkTestPrebookGate(env);
  if (gate.ok !== true) {
    return _guard({ reason: gate.reason });
  }
  const configCheck = assertRatehawkTestProviderConfig(env);
  if (configCheck.ok !== true) {
    return _guard({ reason: configCheck.reason });
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
  const stayCheck = assertRatehawkTestOfferClaims(opened.claims, now);
  if (stayCheck.ok !== true) {
    return _guard({ reason: stayCheck.reason });
  }

  const locale = _locale(requestBody.locale);
  const transport = await fetchRatehawkTestPrebook({
    env,
    bookHash: opened.claims.book_hash,
    fetchImpl,
    now,
  });
  if (transport.invoked !== true) {
    return _guard({
      reason: transport.reason || "test_prebook_disabled",
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
  if (!hotel || Number(hotel.hid) !== RATEHAWK_TEST_HID) {
    return _guard({ reason: "availability_lost", invoked: true });
  }
  const accepted = _firstAcceptedRate(hotel.rates);
  if (accepted.offer?.hard_stop === true) {
    return _guard({
      reason: accepted.offer.reason || "unmapped_critical_field",
      invoked: true,
    });
  }
  if (!accepted.offer) {
    return _guard({ reason: "availability_lost", invoked: true });
  }

  const afterSnapshot = buildOfferDisplaySnapshot(accepted.offer);
  const comparison = compareRatehawkPrebookTerms(
    opened.claims.display_snapshot,
    afterSnapshot,
  );
  if (comparison.ok !== true) {
    return _guard({
      reason: comparison.reason || "comparison_incomplete",
      invoked: true,
    });
  }

  const termsRevision = await sha256Hex(
    fingerprintOfferDisplaySnapshot(afterSnapshot),
  );
  const selectedFingerprint =
    opened.claims.display_fingerprint ||
    (await sha256Hex(
      fingerprintOfferDisplaySnapshot(opened.claims.display_snapshot),
    ));
  const sealed = await sealRatehawkPrebookReference(
    env,
    {
      hid: RATEHAWK_TEST_HID,
      checkin: stayCheck.stay.checkin,
      checkout: stayCheck.stay.checkout,
      residency: stayCheck.stay.residency,
      currency: stayCheck.stay.currency,
      guests: stayCheck.stay.guests,
      book_hash: accepted.offer.book_hash || opened.claims.book_hash,
      match_hash: accepted.offer.match_hash || opened.claims.match_hash || null,
      selected_fingerprint: selectedFingerprint,
      terms_revision: termsRevision,
      display_snapshot: afterSnapshot,
      changes_disclosed: comparison.changed === true,
      change_codes: comparison.changes.map((row) => row.code),
      surface: RATEHAWK_TEST_TOKEN_SURFACE,
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
      selected_terms: opened.claims.display_snapshot,
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
      test_surface: true,
    },
    env,
  );
}

export async function handleRatehawkTestPrebookAcceptRequest({
  env = {},
  body = {},
  now = Date.now(),
} = {}) {
  const requestBody =
    body && typeof body === "object" && !Array.isArray(body) ? body : {};
  if (
    hasForbiddenRatehawkTestClientControl(requestBody) ||
    hasForbiddenPublicPrebookClientControl(requestBody)
  ) {
    return _guard({ reason: "client_control_forbidden" });
  }
  const trigger =
    _text(requestBody.trigger, 40) || RATEHAWK_TEST_PREBOOK_ACCEPT_TRIGGER;
  if (trigger !== RATEHAWK_TEST_PREBOOK_ACCEPT_TRIGGER) {
    return _guard({ reason: "unsupported_trigger" });
  }
  const gate = evaluateRatehawkTestPrebookGate(env);
  if (gate.ok !== true) {
    return _guard({ reason: gate.reason });
  }
  if (!_text(env?.RATEHAWK_OFFER_REF_SECRET, 800)) {
    return _guard({ reason: "offer_ref_secret_missing" });
  }

  const opened = await openRatehawkPrebookReference(env, requestBody.prebook_ref, {
    now,
  });
  if (opened.ok !== true) {
    return _guard({ reason: opened.reason || "rhp1_invalid" });
  }
  if (opened.claims.surface !== RATEHAWK_TEST_TOKEN_SURFACE) {
    return _guard({ reason: "production_prebook_ref_forbidden" });
  }
  if (Number(opened.claims.hid) !== RATEHAWK_TEST_HID) {
    return _guard({ reason: "test_hid_not_allowlisted" });
  }
  const expectedRevision = _text(requestBody.terms_revision, 120);
  if (!expectedRevision || expectedRevision !== opened.claims.terms_revision) {
    return _guard({ reason: "terms_revision_mismatch" });
  }

  const locale = _locale(requestBody.locale);
  const accepted = await sealRatehawkAcceptedReference(
    env,
    {
      hid: RATEHAWK_TEST_HID,
      checkin: opened.claims.checkin,
      checkout: opened.claims.checkout,
      residency: opened.claims.residency,
      currency: opened.claims.currency,
      guests: opened.claims.guests,
      book_hash: opened.claims.book_hash,
      match_hash: opened.claims.match_hash || null,
      terms_revision: opened.claims.terms_revision,
      display_snapshot: opened.claims.display_snapshot,
      changes_disclosed: opened.claims.changes_disclosed === true,
      change_codes: opened.claims.change_codes || [],
      surface: RATEHAWK_TEST_TOKEN_SURFACE,
    },
    { now },
  );
  if (accepted.ok !== true) {
    return _guard({ reason: accepted.reason || "offer_ref_secret_unavailable" });
  }

  const snapshot = buildSafePrebookDisputeSnapshot({
    hid: RATEHAWK_TEST_HID,
    snapshot: opened.claims.display_snapshot,
    comparison: {
      changes: (opened.claims.change_codes || []).map((code) => ({
        code,
        labels: null,
        before: null,
        after: null,
      })),
    },
    locale,
    termsRevision: opened.claims.terms_revision,
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
      terms_revision: opened.claims.terms_revision,
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
      test_surface: true,
    },
    env,
  );
}

export { openRatehawkAcceptedReference };
