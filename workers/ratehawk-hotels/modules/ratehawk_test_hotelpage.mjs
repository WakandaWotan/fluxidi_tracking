/**
 * Hotels Worker test-only Hotelpage activation.
 *
 * Separate from /internal/hotelpage. Requires RATEHAWK_TEST_HOTELPAGE_ENABLED
 * and a verified rhctx1. Never uses the production Hotelpage gates.
 */

import {
  EXISTING_HOTEL_PAGE_ACTIONS,
  RATEHAWK_STAY_CARD_SOURCE,
} from "./ratehawk_affiliate_contract.mjs";
import {
  RATEHAWK_HOTELPAGE_PATH,
  RATEHAWK_HOTELPAGE_TTL_MS,
  buildHotelStayDetailAdapter,
  normalizeRatehawkHotelpageResponse,
} from "./ratehawk_hotelpage_contract.mjs";
import {
  sealRatehawkOfferReference,
  toCustomerHotelpageOffer,
} from "./ratehawk_hotelpage_worker.mjs";
import { sha256Hex } from "./crypto_utils.js";
import {
  RATEHAWK_OFFER_REF_PURPOSE,
  buildOfferDisplaySnapshot,
  fingerprintOfferDisplaySnapshot,
} from "./ratehawk_prebook_contract.mjs";
import { redactRatehawkSecrets } from "./ratehawk_provider.mjs";
import {
  RATEHAWK_QUOTA_ENDPOINTS,
  reserveRatehawkProviderQuota,
} from "./ratehawk_provider_quota.mjs";
import {
  RATEHAWK_TEST_HID,
  RATEHAWK_TEST_OPERATION_HOTELPAGE,
  RATEHAWK_TEST_TOKEN_SURFACE,
  RATEHAWK_TEST_TIMEOUT_MS,
  assertRatehawkTestProviderConfig,
  assertRatehawkTestStay,
  buildRatehawkTestHotelpageRequest,
  evaluateRatehawkTestHotelpageGate,
  hasForbiddenRatehawkTestClientControl,
} from "./ratehawk_test_activation.mjs";
import { postRatehawkTestOnce } from "./ratehawk_test_transport.mjs";
import { openRatehawkViewStayContext } from "./ratehawk_view_stay_context.mjs";

const _testHotelpageInflight = new Map();

function _singleFlight(key, fn) {
  const existing = _testHotelpageInflight.get(key);
  if (existing) return existing;
  const pending = Promise.resolve()
    .then(fn)
    .finally(() => {
      _testHotelpageInflight.delete(key);
    });
  _testHotelpageInflight.set(key, pending);
  return pending;
}

function _safeDto({
  stay = {},
  state = "unavailable",
  reason = null,
  invoked = false,
  offers = [],
  hotelpage = null,
  locale = "nl",
  refreshFailed = false,
  retryAfter = null,
}) {
  const adapter = buildHotelStayDetailAdapter({
    stay,
    hotelpage,
    state,
    locale,
    refresh_failed: refreshFailed,
  });
  const customerOffers = offers.map(toCustomerHotelpageOffer);
  const retrievedAt = hotelpage?.retrieved_at ?? null;
  const expiresAt =
    retrievedAt != null ? retrievedAt + RATEHAWK_HOTELPAGE_TTL_MS : null;
  return {
    ...adapter,
    invoked: invoked === true,
    reason,
    ratehawk: {
      ...adapter.ratehawk,
      offers: state === "ready" ? customerOffers : [],
      retrieved_at: retrievedAt,
      expires_at: expiresAt,
      path: RATEHAWK_HOTELPAGE_PATH,
      retry_after: retryAfter,
    },
    commercial: {
      fluxidi_role: "affiliate",
      customer_pays_fluxidi: false,
      mollie_involved: false,
    },
    existing_page_actions_preserved: EXISTING_HOTEL_PAGE_ACTIONS,
    mobility_independent_of_ratehawk: true,
  };
}

export async function handleRatehawkTestHotelpageRequest({
  env,
  body = {},
  fetchImpl = null,
  now = Date.now(),
  timeoutMs = RATEHAWK_TEST_TIMEOUT_MS,
} = {}) {
  const requestBody =
    body && typeof body === "object" && !Array.isArray(body) ? body : {};
  const locale = String(requestBody.locale || "nl").trim() || "nl";

  if (hasForbiddenRatehawkTestClientControl(requestBody)) {
    return redactRatehawkSecrets(
      _safeDto({ reason: "client_control_forbidden", locale }),
      env,
    );
  }

  const gate = evaluateRatehawkTestHotelpageGate(env);
  if (gate.ok !== true) {
    return redactRatehawkSecrets(
      _safeDto({ reason: gate.reason, locale }),
      env,
    );
  }

  const opened = await openRatehawkViewStayContext(
    env?.RATEHAWK_VIEW_STAY_CONTEXT_SECRET,
    requestBody.view_stay_context ?? requestBody.selected_card_context,
    { now },
  );
  if (opened.ok !== true) {
    return redactRatehawkSecrets(
      _safeDto({ reason: opened.reason, locale }),
      env,
    );
  }

  const stayCheck = assertRatehawkTestStay(opened.claims, now);
  if (stayCheck.ok !== true) {
    return redactRatehawkSecrets(
      _safeDto({ reason: stayCheck.reason, locale }),
      env,
    );
  }

  const configCheck = assertRatehawkTestProviderConfig(env);
  if (configCheck.ok !== true) {
    return redactRatehawkSecrets(
      _safeDto({ reason: configCheck.reason, locale }),
      env,
    );
  }

  if (!String(env?.RATEHAWK_OFFER_REF_SECRET || "").trim()) {
    return redactRatehawkSecrets(
      _safeDto({ reason: "offer_ref_secret_missing", locale }),
      env,
    );
  }

  const request = buildRatehawkTestHotelpageRequest(stayCheck.stay, now);
  if (request.ok !== true) {
    return redactRatehawkSecrets(
      _safeDto({ reason: request.reason, locale }),
      env,
    );
  }

  const stay = {
    provider: RATEHAWK_STAY_CARD_SOURCE,
    source: RATEHAWK_STAY_CARD_SOURCE,
    provider_id: String(RATEHAWK_TEST_HID),
    hid: RATEHAWK_TEST_HID,
    ...stayCheck.stay,
  };

  return _singleFlight(JSON.stringify(request.body), () =>
    _execute({
      env,
      stay,
      locale,
      request,
      fetchImpl,
      timeoutMs,
      now,
    }),
  );
}

async function _execute({
  env,
  stay,
  locale,
  request,
  fetchImpl,
  timeoutMs,
  now,
}) {
  const quota = await reserveRatehawkProviderQuota({
    env,
    endpoint: RATEHAWK_QUOTA_ENDPOINTS.HOTELPAGE,
    now,
  });
  if (quota.allowed !== true) {
    return redactRatehawkSecrets(
      _safeDto({
        stay,
        state: "retryable",
        reason: quota.reason || "provider_quota_exhausted",
        locale,
        refreshFailed: true,
        retryAfter: quota.retry_after,
      }),
      env,
    );
  }

  const transport = await postRatehawkTestOnce({
    env,
    operation: RATEHAWK_TEST_OPERATION_HOTELPAGE,
    path: request.path,
    body: request.body,
    fetchImpl,
    timeoutMs,
  });

  if (transport.invoked !== true) {
    return redactRatehawkSecrets(
      _safeDto({
        stay,
        reason: transport.reason || "test_hotelpage_disabled",
        locale,
      }),
      env,
    );
  }
  if (transport.ok !== true) {
    return redactRatehawkSecrets(
      _safeDto({
        stay,
        state: "retryable",
        reason: transport.reason || "provider_error",
        invoked: true,
        locale,
        refreshFailed: true,
      }),
      env,
    );
  }

  const retrievedAt = Number(now);
  const hotels = Array.isArray(transport.hotels)
    ? transport.hotels.filter((hotel) => Number(hotel?.hid) === RATEHAWK_TEST_HID)
    : [];
  const page = normalizeRatehawkHotelpageResponse({
    requestedHid: request.body.hid,
    retrieved_at: retrievedAt,
    hotels,
    now: retrievedAt,
  });
  if (page.ok !== true && (!Array.isArray(page.offers) || page.offers.length === 0)) {
    return redactRatehawkSecrets(
      _safeDto({
        stay,
        state: "retryable",
        reason: page.reason || "hotelpage_unavailable",
        invoked: true,
        locale,
        refreshFailed: true,
        hotelpage: page.ok === true ? page : null,
      }),
      env,
    );
  }

  const sealedOffers = [];
  for (const offer of page.offers || []) {
    if (offer?.freshness?.bookable !== true) continue;
    const displaySnapshot = buildOfferDisplaySnapshot(offer);
    const displayFingerprint = await sha256Hex(
      fingerprintOfferDisplaySnapshot(displaySnapshot),
    );
    const sealed = await sealRatehawkOfferReference(env, {
      v: 1,
      purpose: RATEHAWK_OFFER_REF_PURPOSE,
      surface: RATEHAWK_TEST_TOKEN_SURFACE,
      hid: page.hid,
      book_hash: offer.book_hash,
      match_hash: offer.match_hash,
      retrieved_at: retrievedAt,
      expires_at: retrievedAt + RATEHAWK_HOTELPAGE_TTL_MS,
      checkin: request.body.checkin,
      checkout: request.body.checkout,
      residency: request.body.residency,
      currency: request.body.currency,
      guests: request.body.guests,
      display_snapshot: displaySnapshot,
      display_fingerprint: displayFingerprint,
    });
    if (sealed.ok !== true) continue;
    sealedOffers.push({ ...offer, offer_ref: sealed.offer_ref });
  }

  if (sealedOffers.length === 0) {
    return redactRatehawkSecrets(
      _safeDto({
        stay,
        state: "retryable",
        reason: page.reason || "hotelpage_unavailable",
        invoked: true,
        locale,
        refreshFailed: true,
        hotelpage: page,
      }),
      env,
    );
  }

  return redactRatehawkSecrets(
    _safeDto({
      stay,
      state: "ready",
      reason: null,
      invoked: true,
      offers: sealedOffers,
      hotelpage: {
        ...page,
        ok: true,
        offers: sealedOffers,
        bookable_count: sealedOffers.length,
        stale: false,
      },
      locale,
    }),
    env,
  );
}
