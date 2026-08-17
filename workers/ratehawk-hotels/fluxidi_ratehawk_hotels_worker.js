/**
 * Fluxidi RateHawk Hotels Worker.
 *
 * Private Cloudflare Service Binding only. No public customer route.
 * Deploy this worker before fluxidi-booking-api so RATEHAWK_HOTELS binds.
 *
 * Internal operations:
 *   GET  /internal/status
 *   POST /internal/hotelpage
 *   POST /internal/search
 *   POST /internal/prebook
 *   POST /internal/prebook/accept
 *   POST /internal/test-search
 *   POST /internal/test-hotelpage
 *   POST /internal/test-prebook
 *   POST /internal/test-prebook/accept
 *   POST /internal/content-sync  (admin-internal / scheduled only)
 */

import {
  handleRatehawkHotelpageRequest,
  isRatehawkContentSyncAllowedOnCustomerRequest,
} from "./modules/ratehawk_hotelpage_worker.mjs";
import {
  RATEHAWK_CONTENT_STRATEGIES,
  isRatehawkBatchContentStrategyEnabled,
  resolveRatehawkContentStrategy,
} from "./modules/ratehawk_content_strategy.mjs";
import {
  planScopedContentSync,
  shouldRunRatehawkContentSync,
} from "./modules/ratehawk_content_sync.mjs";
import { executeRatehawkContentJobs } from "./modules/ratehawk_content_transport.mjs";
import {
  isRatehawkHotelsDbConfigured,
  openRatehawkContentStore,
} from "./modules/ratehawk_content_store.mjs";
import { RatehawkProviderQuotaDO } from "./modules/ratehawk_provider_quota.mjs";
import { buildSafeRatehawkProviderStatus } from "./modules/ratehawk_provider.mjs";
import { verifyRatehawkViewStayContext } from "./modules/ratehawk_view_stay_context.mjs";
import {
  isRatehawkIsolatedTestWorker,
  isRatehawkTestHotelpageEnabled,
  isRatehawkTestPrebookEnabled,
  isRatehawkTestSearchEnabled,
  resolveRatehawkWorkerName,
  resolveRatehawkWorkerSurface,
} from "./modules/ratehawk_test_activation.mjs";
import { handleRatehawkTestSearchRequest } from "./modules/ratehawk_test_search.mjs";
import { handleRatehawkTestHotelpageRequest } from "./modules/ratehawk_test_hotelpage.mjs";
import {
  RATEHAWK_HOTELS_TEST_PREBOOK_ACCEPT_PATH,
  RATEHAWK_HOTELS_TEST_PREBOOK_PATH,
  handleRatehawkTestPrebookAcceptRequest,
  handleRatehawkTestPrebookRequest,
} from "./modules/ratehawk_test_prebook.mjs";
import {
  RATEHAWK_HOTELS_SEARCH_PATH,
  handleRatehawkPublicSearchRequest,
} from "./modules/ratehawk_public_search.mjs";
import {
  RATEHAWK_HOTELS_PREBOOK_ACCEPT_PATH,
  RATEHAWK_HOTELS_PREBOOK_PATH,
  handleRatehawkPrebookAcceptRequest,
  handleRatehawkPrebookRequest,
} from "./modules/ratehawk_prebook_worker.mjs";

export { RatehawkProviderQuotaDO };

export const RATEHAWK_HOTELS_WORKER_NAME = "fluxidi-ratehawk-hotels-api";
export const RATEHAWK_HOTELS_INTERNAL_PROXY = "booking_worker_v1";
export const RATEHAWK_HOTELS_STATUS_PATH = "/internal/status";
export const RATEHAWK_HOTELS_HOTELPAGE_PATH = "/internal/hotelpage";
export { RATEHAWK_HOTELS_SEARCH_PATH };
export const RATEHAWK_HOTELS_TEST_SEARCH_PATH = "/internal/test-search";
export const RATEHAWK_HOTELS_TEST_HOTELPAGE_PATH = "/internal/test-hotelpage";
export { RATEHAWK_HOTELS_TEST_PREBOOK_PATH, RATEHAWK_HOTELS_TEST_PREBOOK_ACCEPT_PATH };
export const RATEHAWK_HOTELS_CONTENT_SYNC_PATH = "/internal/content-sync";

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
      worker: resolveRatehawkWorkerName(env),
      worker_surface: resolveRatehawkWorkerSurface(env),
      public_route: false,
      content_sync_on_customer_request:
        isRatehawkContentSyncAllowedOnCustomerRequest(),
      content_strategy: {
        single_hid_info: resolveRatehawkContentStrategy(
          RATEHAWK_CONTENT_STRATEGIES.SINGLE_HID_INFO,
        ).strategy,
        batch_content_by_ids: isRatehawkBatchContentStrategyEnabled(),
      },
      hotels_db_configured: isRatehawkHotelsDbConfigured(env),
      content_storage: isRatehawkHotelsDbConfigured(env) ? "d1" : "not_configured",
      test_search_enabled: isRatehawkTestSearchEnabled(env),
      test_hotelpage_enabled: isRatehawkTestHotelpageEnabled(env),
      test_prebook_enabled: isRatehawkTestPrebookEnabled(env),
      ratehawk: buildSafeRatehawkProviderStatus(env),
    });
  }

  if (
    url.pathname === RATEHAWK_HOTELS_HOTELPAGE_PATH &&
    request.method === "POST"
  ) {
    if (isRatehawkIsolatedTestWorker(env)) {
      return json(_unavailable("production_path_forbidden_on_test_worker"));
    }
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

  if (
    url.pathname === RATEHAWK_HOTELS_SEARCH_PATH &&
    request.method === "POST"
  ) {
    if (isRatehawkIsolatedTestWorker(env)) {
      return json(
        await handleRatehawkPublicSearchRequest({
          env,
          body: {},
        }),
      );
    }
    let body = {};
    try {
      body = await request.json();
    } catch {
      body = {};
    }
    if (!body || typeof body !== "object" || Array.isArray(body)) {
      body = {};
    }
    return json(
      await handleRatehawkPublicSearchRequest({
        env,
        body,
        fetchImpl,
        now,
      }),
    );
  }

  if (
    url.pathname === RATEHAWK_HOTELS_PREBOOK_PATH &&
    request.method === "POST"
  ) {
    if (isRatehawkIsolatedTestWorker(env)) {
      return json(
        await handleRatehawkPrebookRequest({
          env,
          body: {},
        }),
      );
    }
    let body = {};
    try {
      body = await request.json();
    } catch {
      body = {};
    }
    if (!body || typeof body !== "object" || Array.isArray(body)) {
      body = {};
    }
    return json(
      await handleRatehawkPrebookRequest({
        env,
        body,
        fetchImpl,
        now,
      }),
    );
  }

  if (
    url.pathname === RATEHAWK_HOTELS_PREBOOK_ACCEPT_PATH &&
    request.method === "POST"
  ) {
    if (isRatehawkIsolatedTestWorker(env)) {
      return json(
        await handleRatehawkPrebookAcceptRequest({
          env,
          body: {},
        }),
      );
    }
    let body = {};
    try {
      body = await request.json();
    } catch {
      body = {};
    }
    if (!body || typeof body !== "object" || Array.isArray(body)) {
      body = {};
    }
    return json(
      await handleRatehawkPrebookAcceptRequest({
        env,
        body,
        now,
      }),
    );
  }

  if (
    url.pathname === RATEHAWK_HOTELS_TEST_SEARCH_PATH &&
    request.method === "POST"
  ) {
    if (!isRatehawkIsolatedTestWorker(env)) {
      return json({
        ok: false,
        invoked: false,
        reason: "test_worker_required",
        view_stay_context: null,
      });
    }
    let body = {};
    try {
      body = await request.json();
    } catch {
      body = {};
    }
    if (!body || typeof body !== "object" || Array.isArray(body)) {
      body = {};
    }
    return json(
      await handleRatehawkTestSearchRequest({
        env,
        body,
        fetchImpl,
        now,
      }),
    );
  }

  if (
    url.pathname === RATEHAWK_HOTELS_TEST_HOTELPAGE_PATH &&
    request.method === "POST"
  ) {
    if (!isRatehawkIsolatedTestWorker(env)) {
      return json(_unavailable("test_worker_required"));
    }
    let body = {};
    try {
      body = await request.json();
    } catch {
      body = {};
    }
    if (!body || typeof body !== "object" || Array.isArray(body)) {
      body = {};
    }
    return json(
      await handleRatehawkTestHotelpageRequest({
        env,
        body,
        fetchImpl,
        now,
      }),
    );
  }

  if (
    url.pathname === RATEHAWK_HOTELS_TEST_PREBOOK_PATH &&
    request.method === "POST"
  ) {
    if (!isRatehawkIsolatedTestWorker(env)) {
      return json({
        ok: true,
        invoked: false,
        reason: "test_worker_required",
        progress_blocked: true,
        acceptance_allowed: false,
      });
    }
    let body = {};
    try {
      body = await request.json();
    } catch {
      body = {};
    }
    if (!body || typeof body !== "object" || Array.isArray(body)) {
      body = {};
    }
    return json(
      await handleRatehawkTestPrebookRequest({
        env,
        body,
        fetchImpl,
        now,
      }),
    );
  }

  if (
    url.pathname === RATEHAWK_HOTELS_TEST_PREBOOK_ACCEPT_PATH &&
    request.method === "POST"
  ) {
    if (!isRatehawkIsolatedTestWorker(env)) {
      return json({
        ok: true,
        invoked: false,
        reason: "test_worker_required",
        progress_blocked: true,
        acceptance_allowed: false,
      });
    }
    let body = {};
    try {
      body = await request.json();
    } catch {
      body = {};
    }
    if (!body || typeof body !== "object" || Array.isArray(body)) {
      body = {};
    }
    return json(
      await handleRatehawkTestPrebookAcceptRequest({
        env,
        body,
        now,
      }),
    );
  }

  if (
    url.pathname === RATEHAWK_HOTELS_CONTENT_SYNC_PATH &&
    request.method === "POST"
  ) {
    if (isRatehawkIsolatedTestWorker(env)) {
      return json({
        ok: true,
        executed: false,
        provider_requested: false,
        reason: "production_path_forbidden_on_test_worker",
        jobs: [],
      });
    }
    let body = {};
    try {
      body = await request.json();
    } catch {
      body = {};
    }
    return json(
      await handleRatehawkContentSyncRequest({
        env,
        body,
        trigger: "admin_internal",
        fetchImpl,
        now,
      }),
    );
  }

  return _notFound();
}

export async function handleRatehawkContentSyncRequest({
  env,
  body = {},
  trigger = "admin_internal",
  fetchImpl = null,
  now = Date.now(),
} = {}) {
  const gate = shouldRunRatehawkContentSync({ trigger, env });
  if (gate.run !== true) {
    return {
      ok: true,
      executed: false,
      provider_requested: false,
      reason: gate.reason,
      jobs: [],
    };
  }
  if (
    body.batch === true ||
    body.strategy === RATEHAWK_CONTENT_STRATEGIES.BATCH_CONTENT_BY_IDS
  ) {
    return {
      ok: false,
      executed: false,
      provider_requested: false,
      reason: "batch_content_by_ids_unavailable",
      fallback_used: false,
      jobs: [],
    };
  }
  const planned = planScopedContentSync({
    env,
    markets: body.markets ?? null,
    hidLists: body.hid_lists ?? {},
    locales: body.locales,
    strategy: body.strategy,
  });
  const shouldExecute =
    body.execute === true || trigger === "scheduled" || trigger === "queue";
  if (!shouldExecute || !planned.jobs?.length) {
    return planned;
  }
  const storage = openRatehawkContentStore(env, body.store ?? null);
  if (storage.ok !== true) {
    return {
      ...planned,
      executed: false,
      provider_requested: false,
      reason: storage.reason || "storage_not_configured",
    };
  }
  const allocated = await storage.store.allocateRun({ now });
  const jobs = planned.jobs.map((job) => ({
    ...job,
    run_id: allocated.run_id,
    generation: allocated.generation,
    job_id: `job_${allocated.run_id}_${job.hid}_${job.locale}`,
  }));
  for (const job of jobs) {
    await storage.store.planJob(job, now);
  }
  const results = await executeRatehawkContentJobs({
    env,
    jobs,
    fetchImpl,
    store: storage.store,
    now,
    trigger,
  });
  return {
    ...planned,
    executed: true,
    provider_requested: results.some((row) => row.invoked === true),
    run_id: allocated.run_id,
    generation: allocated.generation,
    results,
  };
}

export async function handleRatehawkHotelsScheduled(event, env) {
  if (isRatehawkIsolatedTestWorker(env)) {
    return {
      ok: true,
      executed: false,
      provider_requested: false,
      reason: "production_path_forbidden_on_test_worker",
      jobs: [],
    };
  }
  return handleRatehawkContentSyncRequest({
    env,
    body: {},
    trigger: "scheduled",
  });
}

export default {
  async fetch(request, env) {
    return handleRatehawkHotelsWorkerFetch(request, env);
  },
  async scheduled(event, env) {
    return handleRatehawkHotelsScheduled(event, env);
  },
};
