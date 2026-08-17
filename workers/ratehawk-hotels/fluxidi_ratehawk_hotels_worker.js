/**
 * Fluxidi RateHawk Hotels Worker.
 *
 * Private Cloudflare Service Binding only. No public customer route.
 * Deploy this worker before fluxidi-booking-api so RATEHAWK_HOTELS binds.
 *
 * Internal operations:
 *   GET  /internal/status
 *   POST /internal/hotelpage
 */

import {
  handleRatehawkHotelpageRequest,
  isRatehawkContentSyncAllowedOnCustomerRequest,
} from "./modules/ratehawk_hotelpage_worker.mjs";
import { buildSafeRatehawkProviderStatus } from "./modules/ratehawk_provider.mjs";
import { verifyRatehawkViewStayContext } from "./modules/ratehawk_view_stay_context.mjs";

export const RATEHAWK_HOTELS_WORKER_NAME = "fluxidi-ratehawk-hotels-api";
export const RATEHAWK_HOTELS_INTERNAL_PROXY = "booking_worker_v1";
export const RATEHAWK_HOTELS_STATUS_PATH = "/internal/status";
export const RATEHAWK_HOTELS_HOTELPAGE_PATH = "/internal/hotelpage";

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
    },
  });
}

function _isInternalProxy(request) {
  return (
    String(request?.headers?.get("x-fluxidi-internal-proxy") || "") ===
    RATEHAWK_HOTELS_INTERNAL_PROXY
  );
}

function _notFound() {
  return new Response(null, { status: 404 });
}

function _expectedContextFromBody(body) {
  const stay = body?.stay && typeof body.stay === "object" ? body.stay : {};
  return {
    source: "ratehawk",
    hid: body?.hid ?? stay.provider_id ?? stay.hid,
    checkin: body?.checkin,
    checkout: body?.checkout,
    residency: body?.residency,
    currency: body?.currency,
    guests: body?.guests,
  };
}

function _unavailable(reason) {
  return {
    ok: true,
    invoked: false,
    reason,
    page: "HotelStayDetailPage",
    rendered: false,
    stay22_fallback_retained: true,
    mobility_independent_of_ratehawk: true,
    ratehawk: {
      section: "optional_room_rate",
      state: "unavailable",
      offers: [],
      retryable: false,
    },
    commercial: {
      fluxidi_role: "affiliate",
      customer_pays_fluxidi: false,
      mollie_involved: false,
    },
  };
}

export async function handleRatehawkHotelsWorkerFetch(
  request,
  env,
  { fetchImpl = null, now = Date.now() } = {},
) {
  if (!_isInternalProxy(request)) {
    return _notFound();
  }

  const url = new URL(request.url);
  if (url.pathname === RATEHAWK_HOTELS_STATUS_PATH && request.method === "GET") {
    return json({
      ok: true,
      worker: RATEHAWK_HOTELS_WORKER_NAME,
      public_route: false,
      content_sync_on_customer_request:
        isRatehawkContentSyncAllowedOnCustomerRequest(),
      ratehawk: buildSafeRatehawkProviderStatus(env),
    });
  }

  if (
    url.pathname === RATEHAWK_HOTELS_HOTELPAGE_PATH &&
    request.method === "POST"
  ) {
    let body = {};
    try {
      body = await request.json();
    } catch {
      body = {};
    }
    if (!body || typeof body !== "object" || Array.isArray(body)) {
      body = {};
    }
    const context = await verifyRatehawkViewStayContext(
      env?.RATEHAWK_VIEW_STAY_CONTEXT_SECRET,
      body.view_stay_context ?? body.selected_card_context,
      _expectedContextFromBody(body),
      { now },
    );
    if (context.ok !== true) {
      return json(_unavailable(context.reason));
    }
    const dto = await handleRatehawkHotelpageRequest({
      env,
      body,
      fetchImpl,
      now,
    });
    return json(dto);
  }

  return _notFound();
}

export default {
  async fetch(request, env) {
    return handleRatehawkHotelsWorkerFetch(request, env);
  },
};
