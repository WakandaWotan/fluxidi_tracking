// Fail-closed public RateHawk Search seam.
//
// Run:
//   node --test workers/booking/modules/ratehawk_public_search_seam.test.mjs

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";
import assert from "node:assert/strict";

import {
  handlePublicRatehawkSearch,
} from "./ratehawk_hotels_facade.mjs";
import {
  handleRatehawkHotelsWorkerFetch,
  RATEHAWK_HOTELS_INTERNAL_PROXY,
} from "../../ratehawk-hotels/fluxidi_ratehawk_hotels_worker.js";
import { handleRatehawkPublicSearchRequest } from "../../ratehawk-hotels/modules/ratehawk_public_search.mjs";
import { createRatehawkQuotaBinding } from "../../ratehawk-hotels/modules/ratehawk_provider_quota.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));

function productionHotelsEnv(overrides = {}) {
  return {
    RATEHAWK_WORKER_SURFACE: "production",
    RATEHAWK_ENABLED: "0",
    RATEHAWK_SEARCH_ENABLED: "0",
    RATEHAWK_HOTELPAGE_ENABLED: "0",
    RATEHAWK_PROVIDER_QUOTA: createRatehawkQuotaBinding(),
    ...overrides,
  };
}

function hotelsBinding(env, handler) {
  const state = { calls: 0, paths: [] };
  return {
    state,
    binding: {
      fetch: async (request) => {
        state.calls += 1;
        state.paths.push(new URL(request.url).pathname);
        return handleRatehawkHotelsWorkerFetch(request, env, {
          fetchImpl: handler,
        });
      },
    },
  };
}

test("public search uses only RATEHAWK_HOTELS and stays fail-closed", async () => {
  const hotels = hotelsBinding(productionHotelsEnv(), async () => {
    throw new Error("must_not_call_ratehawk");
  });
  const dto = await handlePublicRatehawkSearch({
    env: {
      RATEHAWK_HOTELS: hotels.binding,
      RATEHAWK_HOTELS_TEST: {
        fetch: async () => {
          throw new Error("test_binding_must_not_be_used");
        },
      },
    },
    query: {
      source: "ratehawk",
      city: "Brussel",
      country: "Belgium",
      checkin: "2026-09-03",
      checkout: "2026-09-04",
      rooms: "1",
      adults: "2",
    },
  });
  assert.equal(hotels.state.calls, 1);
  assert.deepEqual(hotels.state.paths, ["/internal/search"]);
  assert.equal(dto.ok, true);
  assert.equal(dto.invoked, false);
  assert.equal(dto.count, 0);
  assert.deepEqual(dto.stays, []);
  assert.equal(dto.warnings.includes("ratehawk_invocation_blocked"), true);
  assert.equal(dto.ratehawk.invocation_allowed, false);
});

test("missing production binding does not use the test binding", async () => {
  let testCalls = 0;
  const dto = await handlePublicRatehawkSearch({
    env: {
      RATEHAWK_HOTELS_TEST: {
        fetch: async () => {
          testCalls += 1;
          throw new Error("test_binding_must_not_be_used");
        },
      },
    },
    query: { source: "ratehawk" },
  });
  assert.equal(testCalls, 0);
  assert.equal(dto.count, 0);
  assert.equal(dto.warnings.includes("ratehawk_invocation_blocked"), true);
  assert.equal(dto.warnings.includes("hotels_worker_binding_missing"), true);
});

test("page-open and incomplete criteria issue zero provider transport", () => {
  const pageOpen = handleRatehawkPublicSearchRequest({
    env: productionHotelsEnv({
      RATEHAWK_ENABLED: "1",
      RATEHAWK_SEARCH_ENABLED: "1",
    }),
    body: { trigger: "page_open" },
  });
  const incomplete = handleRatehawkPublicSearchRequest({
    env: productionHotelsEnv({
      RATEHAWK_ENABLED: "1",
      RATEHAWK_SEARCH_ENABLED: "1",
    }),
    body: { trigger: "live_search", city: "Brussel" },
  });
  assert.equal(pageOpen.invoked, false);
  assert.equal(pageOpen.reason, "page_open_no_request");
  assert.equal(incomplete.invoked, false);
  assert.equal(incomplete.reason, "live_search_incomplete");
  assert.equal(pageOpen.count, 0);
  assert.equal(incomplete.count, 0);
});

test("enabled search gates still do not call RateHawk in this seam", () => {
  const dto = handleRatehawkPublicSearchRequest({
    env: productionHotelsEnv({
      RATEHAWK_ENABLED: "1",
      RATEHAWK_SEARCH_ENABLED: "1",
      RATEHAWK_PRODUCTION_ENABLED: "1",
      RATEHAWK_ENVIRONMENT: "production",
      RATEHAWK_BASE_URL: "https://api.ratehawk.com",
      RATEHAWK_KEY_ID: "18292",
      RATEHAWK_API_KEY: "must-not-be-used",
    }),
    body: {
      trigger: "live_search",
      city: "Brussel",
      country: "BE",
      checkin: "2026-09-03",
      checkout: "2026-09-04",
      guests: [{ adults: 2, children: [] }],
    },
  });
  assert.equal(dto.invoked, false);
  assert.equal(dto.count, 0);
  assert.equal(dto.reason, "ratehawk_search_not_implemented");
  assert.equal(dto.warnings.includes("ratehawk_invocation_blocked"), true);
});

test("Flutter-facing source does not mention admin or test routes", () => {
  const facade = readFileSync(join(HERE, "ratehawk_hotels_facade.mjs"), "utf8");
  const publicSearchFn = facade.slice(
    facade.indexOf("export async function handlePublicRatehawkSearch"),
    facade.indexOf("export async function handlePublicRatehawkHotelpage"),
  );
  assert.equal(publicSearchFn.includes("RATEHAWK_HOTELS_TEST"), false);
  assert.equal(publicSearchFn.includes("/admin/hotels/ratehawk/test"), false);
  assert.equal(publicSearchFn.includes("x-admin-token"), false);
  const flutter = [
    readFileSync(join(HERE, "../../../lib/hotels/ratehawk_search.dart"), "utf8"),
    readFileSync(join(HERE, "../../../lib/hotels/ratehawk_search_panel.dart"), "utf8"),
    readFileSync(join(HERE, "../../../lib/hotels/hotels_page.dart"), "utf8"),
  ].join("\n");
  assert.equal(flutter.includes("RATEHAWK_HOTELS_TEST"), false);
  assert.equal(flutter.includes("/admin/hotels/ratehawk/test"), false);
  assert.equal(flutter.includes("x-admin-token"), false);
});
