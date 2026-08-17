// RATEHAWK-P2 gated prebook revalidation + acceptance
//
// Run:
//   node --test workers/ratehawk-hotels/modules/ratehawk_prebook.test.mjs

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";
import assert from "node:assert/strict";

import { sha256Hex } from "./crypto_utils.js";
import { normalizeRatehawkRateOffer } from "./ratehawk_affiliate_contract.mjs";
import worker from "../../booking/fluxidi_booking_worker.js";
import {
  handlePublicRatehawkPrebook,
  handlePublicRatehawkPrebookAccept,
  readPublicRatehawkJsonBody,
} from "../../booking/modules/ratehawk_hotels_facade.mjs";
import {
  RATEHAWK_HOTELS_INTERNAL_PROXY,
  handleRatehawkHotelsWorkerFetch,
} from "../fluxidi_ratehawk_hotels_worker.js";
import {
  sealRatehawkOfferReference,
} from "./ratehawk_hotelpage_worker.mjs";
import {
  RATEHAWK_PREBOOK_CHANGE_CODES,
  RATEHAWK_PREBOOK_PATH,
  buildOfferDisplaySnapshot,
  compareRatehawkPrebookTerms,
  fingerprintOfferDisplaySnapshot,
  hasForbiddenPublicPrebookClientControl,
  localizePrebookChanges,
  prebookActionLabels,
} from "./ratehawk_prebook_contract.mjs";
import {
  openRatehawkAcceptedReference,
  openRatehawkPrebookReference,
} from "./ratehawk_prebook_tokens.mjs";
import {
  assertAcceptedRevisionMatches,
  handleRatehawkPrebookAcceptRequest,
  handleRatehawkPrebookRequest,
} from "./ratehawk_prebook_worker.mjs";
import { createRatehawkQuotaBinding } from "./ratehawk_provider_quota.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const TEST_API_KEY = "rh_prebook_secret_do_not_leak_xyz";
const TEST_KEY_ID = "18292";
const BOOK_HASH = "h-prebook-secret-hash-do-not-leak";
const MATCH_HASH = "m-prebook-secret-hash-do-not-leak";
const NOW = Date.parse("2026-08-17T11:00:00.000Z");

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function hotelpageRate(overrides = {}) {
  return {
    book_hash: BOOK_HASH,
    match_hash: MATCH_HASH,
    room_name: "Superior Double",
    room_description: "City view",
    occupancy: { adults: 2 },
    meal: "breakfast",
    meal_data: { value: "breakfast", has_breakfast: true, no_child_meal: false },
    allotment: 2,
    rg_ext: { class: 3, quality: 2, bedding: 2 },
    amenities_data: ["non-smoking"],
    deposit: {
      amount: "50.00",
      currency_code: "EUR",
      is_refundable: true,
    },
    no_show: {
      amount: "25.00",
      currency_code: "USD",
      from_time: "18:00:00",
    },
    payment_options: {
      payment_types: [
        {
          type: "hotel",
          amount: "180.00",
          show_amount: "180.00",
          currency_code: "EUR",
          show_currency_code: "EUR",
          is_need_credit_card_data: true,
          is_need_cvc: true,
          vat_data: { included: true, amount: "30.00", currency_code: "EUR" },
          tax_data: {
            taxes: [
              {
                name: "vat",
                included_by_supplier: true,
                amount: "30.00",
                currency_code: "EUR",
              },
              {
                name: "city_tax",
                included_by_supplier: false,
                amount: "7.50",
                currency_code: "EUR",
              },
            ],
          },
          cancellation_penalties: {
            free_cancellation_before: "2026-09-01T10:00:00",
            policies: [
              {
                start_at: null,
                end_at: "2026-09-01T10:00:00",
                amount_charge: "0.00",
                amount_show: "0.00",
              },
              {
                start_at: "2026-09-01T10:00:00",
                end_at: null,
                amount_charge: "180.00",
                amount_show: "180.00",
              },
            ],
          },
        },
      ],
    },
    ...overrides,
  };
}

function etgOk(rate = hotelpageRate()) {
  return {
    status: "ok",
    data: { hotels: [{ hid: 8473727, rates: [rate] }] },
  };
}

function jsonResponse(body, status = 200) {
  return {
    status,
    json: async () => body,
  };
}

function trackingFetch(impl) {
  const state = { calls: 0, urls: [], methods: [], bodies: [] };
  const fetchImpl = async (url, options) => {
    state.calls += 1;
    state.urls.push(String(url));
    state.methods.push(String(options?.method || "GET"));
    state.bodies.push(options?.body ? JSON.parse(options.body) : null);
    return impl(url, options, state);
  };
  return { state, fetchImpl };
}

function enabledEnv(overrides = {}) {
  return {
    RATEHAWK_KEY_ID: TEST_KEY_ID,
    RATEHAWK_API_KEY: TEST_API_KEY,
    RATEHAWK_BASE_URL: "https://api.ratehawk.com",
    RATEHAWK_ENVIRONMENT: "test",
    RATEHAWK_ENABLED: "1",
    RATEHAWK_HOTELPAGE_ENABLED: "1",
    RATEHAWK_PREBOOK_ENABLED: "1",
    RATEHAWK_OFFER_REF_SECRET: "rh_offer_ref_test_secret_not_real",
    RATEHAWK_PROVIDER_QUOTA: createRatehawkQuotaBinding(),
    ...overrides,
  };
}

async function sealRh1(env, rate = hotelpageRate(), now = NOW) {
  const offer = normalizeRatehawkRateOffer(rate);
  assert.equal(offer.ok, true, offer.reason);
  const display = buildOfferDisplaySnapshot(offer);
  const sealed = await sealRatehawkOfferReference(env, {
    v: 1,
    purpose: "hotelpage_offer",
    hid: 8473727,
    book_hash: offer.book_hash,
    match_hash: offer.match_hash,
    retrieved_at: now,
    expires_at: now + 30 * 60 * 1000,
    checkin: "2026-09-15",
    checkout: "2026-09-16",
    residency: "be",
    currency: "EUR",
    guests: [{ adults: 2, children: [] }],
    display_snapshot: display,
    display_fingerprint: await sha256Hex(fingerprintOfferDisplaySnapshot(display)),
  });
  assert.equal(sealed.ok, true);
  return { token: sealed.offer_ref, offer, display };
}

function assertNoSecrets(value) {
  const text = JSON.stringify(value);
  assert.equal(text.includes(TEST_API_KEY), false);
  assert.equal(text.includes(BOOK_HASH), false);
  assert.equal(text.includes(MATCH_HASH), false);
  assert.equal(text.includes("reconciliation_amount"), false);
  assert.equal(text.includes("fluxidi_affiliate_remuneration"), false);
  assert.equal(/Basic\s+[A-Za-z0-9+/=_-]{8,}/i.test(text), false);
  assert.equal(text.includes("book_hash"), false);
  assert.equal(text.includes("match_hash"), false);
}

function memoryKv(initial = {}) {
  const data = new Map(Object.entries(initial));
  return {
    async get(key) {
      return data.has(key) ? data.get(key) : null;
    },
    async put(key, value) {
      data.set(key, typeof value === "string" ? JSON.parse(value) : value);
    },
  };
}

test("1. gate off performs zero provider calls", async () => {
  const env = enabledEnv({ RATEHAWK_PREBOOK_ENABLED: "0" });
  const { token } = await sealRh1(env);
  const { state, fetchImpl } = trackingFetch(async () => {
    throw new Error("must_not_call_ratehawk");
  });
  const dto = await handleRatehawkPrebookRequest({
    env,
    body: { trigger: "prebook_revalidation", offer_ref: token, locale: "nl" },
    fetchImpl,
    now: NOW,
  });
  assert.equal(state.calls, 0);
  assert.equal(dto.invoked, false);
  assert.equal(dto.reason, "prebook_disabled");
  assert.equal(dto.prebook_ref, null);
});

test("2. missing config secret or binding performs zero provider calls", async () => {
  const { state, fetchImpl } = trackingFetch(async () => {
    throw new Error("must_not_call_ratehawk");
  });
  const missingSecret = enabledEnv({ RATEHAWK_OFFER_REF_SECRET: "" });
  const sealedEnv = enabledEnv();
  const { token } = await sealRh1(sealedEnv);
  const secretDto = await handleRatehawkPrebookRequest({
    env: missingSecret,
    body: { trigger: "prebook_revalidation", offer_ref: token, locale: "nl" },
    fetchImpl,
    now: NOW,
  });
  assert.equal(secretDto.invoked, false);
  assert.equal(secretDto.reason, "offer_ref_secret_missing");

  const missingKey = enabledEnv({ RATEHAWK_API_KEY: "" });
  const keyDto = await handleRatehawkPrebookRequest({
    env: missingKey,
    body: { trigger: "prebook_revalidation", offer_ref: token, locale: "nl" },
    fetchImpl,
    now: NOW,
  });
  assert.equal(keyDto.invoked, false);
  assert.ok(
    ["missing_configuration", "prebook_disabled"].includes(keyDto.reason),
  );
  assert.equal(state.calls, 0);
});

test("3. invalid expired or tampered rh1 performs zero provider calls", async () => {
  const env = enabledEnv();
  const { token } = await sealRh1(env);
  const { state, fetchImpl } = trackingFetch(async () => {
    throw new Error("must_not_call_ratehawk");
  });
  const invalid = await handleRatehawkPrebookRequest({
    env,
    body: { trigger: "prebook_revalidation", offer_ref: "rh1.not.real", locale: "nl" },
    fetchImpl,
    now: NOW,
  });
  assert.equal(invalid.reason, "offer_ref_invalid");
  const expired = await handleRatehawkPrebookRequest({
    env,
    body: { trigger: "prebook_revalidation", offer_ref: token, locale: "nl" },
    fetchImpl,
    now: NOW + 40 * 60 * 1000,
  });
  assert.equal(expired.reason, "offer_expired");
  const tampered = await handleRatehawkPrebookRequest({
    env,
    body: {
      trigger: "prebook_revalidation",
      offer_ref: `${token.slice(0, -2)}aa`,
      locale: "nl",
    },
    fetchImpl,
    now: NOW,
  });
  assert.ok(["rh1_invalid", "offer_ref_invalid"].includes(tampered.reason));
  assert.equal(state.calls, 0);
});

test("4. client hash host endpoint or price override is rejected", async () => {
  const env = enabledEnv();
  const { token } = await sealRh1(env);
  const { state, fetchImpl } = trackingFetch(async () => {
    throw new Error("must_not_call_ratehawk");
  });
  for (const extra of [
    { book_hash: BOOK_HASH },
    { host: "api.ratehawk.com" },
    { endpoint: RATEHAWK_PREBOOK_PATH },
    { price: "1.00" },
    { hid: 8473727 },
  ]) {
    const dto = await handleRatehawkPrebookRequest({
      env,
      body: {
        trigger: "prebook_revalidation",
        offer_ref: token,
        locale: "nl",
        ...extra,
      },
      fetchImpl,
      now: NOW,
    });
    assert.equal(dto.reason, "client_control_forbidden", JSON.stringify(extra));
    assert.equal(dto.invoked, false);
  }
  assert.equal(hasForbiddenPublicPrebookClientControl({ price_override: "9" }), true);
  assert.equal(state.calls, 0);
});

test("5. abuse denial performs zero Hotels or provider calls", async () => {
  let hotelsCalls = 0;
  const dto = await handlePublicRatehawkPrebook({
    env: {
      BOOKING_KV: {
        async get() {
          return { count: 20 };
        },
        async put() {
          throw new Error("must_not_write_after_limit");
        },
      },
      RATEHAWK_HOTELS: {
        async fetch() {
          hotelsCalls += 1;
          throw new Error("must_not_call_hotels");
        },
      },
    },
    request: new Request("https://booking.internal/public/hotels/ratehawk/prebook", {
      method: "POST",
      headers: { "cf-connecting-ip": "203.0.113.9" },
    }),
    body: { trigger: "prebook_revalidation", offer_ref: "rh1.aaa.bbb", locale: "nl" },
  });
  assert.equal(hotelsCalls, 0);
  assert.equal(dto.invoked, false);
  assert.equal(dto.reason, "rate_limited");
});

test("6. quota denial performs zero provider calls", async () => {
  const env = enabledEnv({
    RATEHAWK_QUOTA_PREBOOK_LIMIT: "1",
    RATEHAWK_QUOTA_PREBOOK_WINDOW_SECONDS: "60",
  });
  const { token } = await sealRh1(env);
  const { state, fetchImpl } = trackingFetch(async () => jsonResponse(etgOk()));
  const first = await handleRatehawkPrebookRequest({
    env,
    body: { trigger: "prebook_revalidation", offer_ref: token, locale: "nl" },
    fetchImpl,
    now: NOW,
  });
  assert.equal(first.invoked, true);
  const denied = await handleRatehawkPrebookRequest({
    env,
    body: { trigger: "prebook_revalidation", offer_ref: token, locale: "nl" },
    fetchImpl,
    now: NOW + 1,
  });
  assert.equal(denied.invoked, false);
  assert.equal(denied.reason, "provider_quota_exhausted");
  assert.equal(state.calls, 1);
});

test("7. valid mocked request performs exactly one prebook call and no retry", async () => {
  const env = enabledEnv();
  const { token } = await sealRh1(env);
  const { state, fetchImpl } = trackingFetch(async () => jsonResponse(etgOk()));
  const dto = await handleRatehawkPrebookRequest({
    env,
    body: { trigger: "prebook_revalidation", offer_ref: token, locale: "nl" },
    fetchImpl,
    now: NOW,
  });
  assert.equal(state.calls, 1);
  assert.equal(state.methods[0], "POST");
  assert.equal(state.urls[0], `https://api.ratehawk.com${RATEHAWK_PREBOOK_PATH}`);
  assert.deepEqual(state.bodies[0], { hash: BOOK_HASH });
  assert.equal(dto.invoked, true);
  assert.equal(dto.acceptance_allowed, true);
  assert.equal(dto.changed, false);
  assert.equal(dto.changes.length, 0);
  assert.equal(typeof dto.prebook_ref, "string");
  assert.equal(dto.prebook_ref.startsWith("rhp1."), true);
  assertNoSecrets(dto);
});

test("8. timeout and provider error are redacted and retryable", async () => {
  const env = enabledEnv();
  const { token } = await sealRh1(env);
  const timeout = await handleRatehawkPrebookRequest({
    env,
    body: { trigger: "prebook_revalidation", offer_ref: token, locale: "nl" },
    fetchImpl: async () => {
      const err = new Error("aborted");
      err.name = "AbortError";
      throw err;
    },
    now: NOW,
  });
  assert.equal(timeout.invoked, true);
  assert.equal(timeout.retryable, true);
  assert.equal(timeout.reason, "timeout");
  assertNoSecrets(timeout);

  const provider = await handleRatehawkPrebookRequest({
    env,
    body: { trigger: "prebook_revalidation", offer_ref: token, locale: "nl" },
    fetchImpl: async () => jsonResponse({ status: "error" }, 500),
    now: NOW,
  });
  assert.equal(provider.reason, "provider_error");
  assert.equal(provider.retryable, true);
  assertNoSecrets(provider);
});

async function compareCase(mutate, expectedCode, { block = false } = {}) {
  const env = enabledEnv();
  const { token } = await sealRh1(env);
  const after = clone(hotelpageRate());
  mutate(after);
  const dto = await handleRatehawkPrebookRequest({
    env,
    body: { trigger: "prebook_revalidation", offer_ref: token, locale: "en" },
    fetchImpl: async () => jsonResponse(etgOk(after)),
    now: NOW,
  });
  assert.equal(dto.invoked, true, dto.reason);
  if (!dto.flags && expectedCode !== "comparison_incomplete") {
    assert.fail(`missing flags (${dto.reason})`);
  }
  if (expectedCode === "comparison_incomplete") {
    assert.equal(dto.reason, "comparison_incomplete");
    assert.equal(dto.acceptance_allowed, false);
    return dto;
  }
  assert.equal(dto.flags[expectedCode], true, JSON.stringify(dto.flags));
  assert.equal(dto.changed, true);
  if (block) {
    assert.equal(dto.progress_blocked, true);
    assert.equal(dto.acceptance_allowed, false);
    assert.equal(dto.prebook_ref, null);
  } else {
    assert.equal(dto.acceptance_allowed, true);
    assert.equal(dto.must_redisplay_to_customer == null || dto.changed, true);
  }
  return dto;
}

test("9. same terms produce no change list", async () => {
  const env = enabledEnv();
  const { token } = await sealRh1(env);
  const dto = await handleRatehawkPrebookRequest({
    env,
    body: { trigger: "prebook_revalidation", offer_ref: token, locale: "nl" },
    fetchImpl: async () => jsonResponse(etgOk()),
    now: NOW,
  });
  assert.equal(dto.changed, false);
  assert.equal(dto.changes.length, 0);
  assert.equal(dto.acceptance_allowed, true);
});

test("10. price change requires redisplay", async () => {
  const dto = await compareCase((rate) => {
    rate.payment_options.payment_types[0].show_amount = "195.00";
    rate.payment_options.payment_types[0].amount = "195.00";
  }, "price_changed");
  assert.ok(dto.changes.some((row) => row.code === "price_changed"));
});

test("11. currency change blocks automatic progress", async () => {
  const dto = await compareCase((rate) => {
    rate.payment_options.payment_types[0].show_currency_code = "USD";
  }, "currency_changed", { block: true });
  assert.equal(dto.reason, "currency_changed");
});

test("12. tax and additional fee changes require redisplay", async () => {
  await compareCase((rate) => {
    rate.payment_options.payment_types[0].tax_data.taxes[0].amount = "40.00";
  }, "taxes_changed");
  await compareCase((rate) => {
    rate.payment_options.payment_types[0].tax_data.taxes[1].amount = "12.00";
  }, "additional_fees_changed");
});

test("13. room meal occupancy and bed changes require redisplay", async () => {
  await compareCase((rate) => {
    rate.room_name = "Deluxe Suite";
  }, "room_changed");
  await compareCase((rate) => {
    rate.meal_data.value = "nomeal";
    rate.meal_data.has_breakfast = false;
    rate.meal = "nomeal";
  }, "meal_changed");
  await compareCase((rate) => {
    rate.occupancy = { adults: 1 };
  }, "occupancy_changed");
  await compareCase((rate) => {
    rate.rg_ext = { class: 4, quality: 3, bedding: 1 };
  }, "beds_changed");
});

test("14. payment recipient timing and type changes require redisplay", async () => {
  await compareCase((rate) => {
    rate.payment_options.payment_types[0].type = "now";
  }, "payment_type_changed");
});

test("15. deposit change requires redisplay", async () => {
  await compareCase((rate) => {
    rate.deposit.amount = "80.00";
  }, "deposit_changed");
});

test("16. cancellation and free-deadline changes require redisplay", async () => {
  await compareCase((rate) => {
    rate.payment_options.payment_types[0].cancellation_penalties.free_cancellation_before =
      "2026-09-02T10:00:00";
  }, "free_cancellation_deadline_changed");
});

test("17. no-show amount currency or time change requires redisplay", async () => {
  await compareCase((rate) => {
    rate.no_show.amount = "40.00";
  }, "no_show_changed");
});

test("18. availability loss blocks progress", async () => {
  const env = enabledEnv();
  const { token } = await sealRh1(env);
  const empty = await handleRatehawkPrebookRequest({
    env,
    body: { trigger: "prebook_revalidation", offer_ref: token, locale: "nl" },
    fetchImpl: async () => jsonResponse({ status: "ok", data: { hotels: [] } }),
    now: NOW,
  });
  assert.equal(empty.reason, "availability_lost");
  assert.equal(empty.progress_blocked, true);
  assert.equal(empty.prebook_ref, null);
});

test("19. unknown critical field fails closed", async () => {
  const env = enabledEnv();
  const { token } = await sealRh1(env);
  const dto = await handleRatehawkPrebookRequest({
    env,
    body: { trigger: "prebook_revalidation", offer_ref: token, locale: "nl" },
    fetchImpl: async () =>
      jsonResponse(etgOk(hotelpageRate({ guarantee_deposit_policy: { amount: "10" } }))),
    now: NOW,
  });
  assert.equal(dto.reason, "unmapped_critical_field");
  assert.equal(dto.acceptance_allowed, false);
});

test("20. payment type deposit remains rejected", async () => {
  const env = enabledEnv();
  const { token } = await sealRh1(env);
  const rate = clone(hotelpageRate());
  rate.payment_options.payment_types[0].type = "deposit";
  const dto = await handleRatehawkPrebookRequest({
    env,
    body: { trigger: "prebook_revalidation", offer_ref: token, locale: "nl" },
    fetchImpl: async () => jsonResponse(etgOk(rate)),
    now: NOW,
  });
  assert.equal(dto.reason, "deposit_requires_fluxidi_to_fund_etg");
  assert.equal(dto.acceptance_allowed, false);
});

test("21. no-show currency remains separate and unconverted", async () => {
  const env = enabledEnv();
  const { token, display } = await sealRh1(env);
  assert.equal(display.no_show.currency, "USD");
  assert.equal(display.customer_total.currency, "EUR");
  const dto = await handleRatehawkPrebookRequest({
    env,
    body: { trigger: "prebook_revalidation", offer_ref: token, locale: "nl" },
    fetchImpl: async () => jsonResponse(etgOk()),
    now: NOW,
  });
  assert.equal(dto.current_terms.no_show.currency, "USD");
  assert.equal(dto.current_terms.no_show.converted, false);
  assert.equal(dto.current_terms.customer_total.currency, "EUR");
});

test("22. public DTO contains no hashes reconciliation commission or credentials", async () => {
  const env = enabledEnv();
  const { token } = await sealRh1(env);
  const dto = await handleRatehawkPrebookRequest({
    env,
    body: { trigger: "prebook_revalidation", offer_ref: token, locale: "nl" },
    fetchImpl: async () => jsonResponse(etgOk()),
    now: NOW,
  });
  assertNoSecrets(dto);
});

test("23. rhp1 is opaque context-bound and expiring", async () => {
  const env = enabledEnv();
  const { token } = await sealRh1(env);
  const dto = await handleRatehawkPrebookRequest({
    env,
    body: { trigger: "prebook_revalidation", offer_ref: token, locale: "nl" },
    fetchImpl: async () => jsonResponse(etgOk()),
    now: NOW,
  });
  const opened = await openRatehawkPrebookReference(env, dto.prebook_ref, { now: NOW });
  assert.equal(opened.ok, true);
  assert.equal(opened.claims.purpose, "prebook");
  assert.equal(opened.claims.hid, 8473727);
  assert.equal(opened.claims.book_hash, BOOK_HASH);
  assert.ok(Number(opened.claims.expires_at) > NOW);
  const expired = await openRatehawkPrebookReference(env, dto.prebook_ref, {
    now: NOW + 16 * 60 * 1000,
  });
  assert.equal(expired.ok, false);
  assert.equal(expired.reason, "rhp1_expired");
});

test("24-26. acceptance is revision-bound, performs zero provider calls, and rejects stale terms", async () => {
  const env = enabledEnv();
  const { token } = await sealRh1(env);
  const { state, fetchImpl } = trackingFetch(async () => jsonResponse(etgOk()));
  const prebook = await handleRatehawkPrebookRequest({
    env,
    body: { trigger: "prebook_revalidation", offer_ref: token, locale: "nl" },
    fetchImpl,
    now: NOW,
  });
  assert.equal(state.calls, 1);
  const accepted = await handleRatehawkPrebookAcceptRequest({
    env,
    body: {
      trigger: "accept_prebook_terms",
      prebook_ref: prebook.prebook_ref,
      terms_revision: prebook.terms_revision,
      locale: "nl",
    },
    now: NOW + 1000,
  });
  assert.equal(state.calls, 1);
  assert.equal(accepted.invoked, false);
  assert.equal(accepted.accepted, true);
  assert.equal(accepted.accepted_ref.startsWith("rha1."), true);
  assert.equal(accepted.terms_revision, prebook.terms_revision);
  const opened = await openRatehawkAcceptedReference(env, accepted.accepted_ref, {
    now: NOW + 1000,
  });
  assert.equal(opened.ok, true);
  assert.equal(opened.claims.terms_revision, prebook.terms_revision);

  const mismatch = await handleRatehawkPrebookAcceptRequest({
    env,
    body: {
      trigger: "accept_prebook_terms",
      prebook_ref: prebook.prebook_ref,
      terms_revision: "different-revision",
      locale: "nl",
    },
    now: NOW + 1000,
  });
  assert.equal(mismatch.reason, "terms_revision_mismatch");
  assert.equal(mismatch.accepted_ref, null);
  assert.equal(
    assertAcceptedRevisionMatches(
      { terms_revision: "old" },
      { terms_revision: prebook.terms_revision },
    ).reason,
    "stale_acceptance",
  );
});

test("27. complete safe dispute snapshot is produced", async () => {
  const env = enabledEnv();
  const { token } = await sealRh1(env);
  const prebook = await handleRatehawkPrebookRequest({
    env,
    body: { trigger: "prebook_revalidation", offer_ref: token, locale: "nl" },
    fetchImpl: async () => jsonResponse(etgOk()),
    now: NOW,
  });
  const accepted = await handleRatehawkPrebookAcceptRequest({
    env,
    body: {
      trigger: "accept_prebook_terms",
      prebook_ref: prebook.prebook_ref,
      terms_revision: prebook.terms_revision,
      locale: "nl",
    },
    now: NOW + 2000,
  });
  const snap = accepted.dispute_snapshot;
  assert.equal(snap.ok, true);
  assert.equal(snap.hid, 8473727);
  assert.equal(snap.room_name, "Superior Double");
  assert.equal(snap.customer_total.currency, "EUR");
  assert.ok(Array.isArray(snap.included_taxes));
  assert.ok(snap.payment);
  assert.ok(snap.cancellation);
  assert.ok(snap.no_show);
  assert.ok(snap.deposit);
  assert.equal(snap.locale, "nl");
  assert.equal(snap.terms_revision, prebook.terms_revision);
  assert.ok(snap.omitted.includes("book_hash"));
  assert.ok(snap.omitted.includes("commission"));
  const snapText = JSON.stringify(snap);
  assert.equal(snapText.includes(TEST_API_KEY), false);
  assert.equal(snapText.includes(BOOK_HASH), false);
  assert.equal(snapText.includes(MATCH_HASH), false);
});

test("28. saved taxi airport and Stay22 remain usable", async () => {
  const env = enabledEnv();
  const { token } = await sealRh1(env);
  const dto = await handleRatehawkPrebookRequest({
    env,
    body: { trigger: "prebook_revalidation", offer_ref: token, locale: "nl" },
    fetchImpl: async () => jsonResponse(etgOk()),
    now: NOW,
  });
  assert.equal(dto.stay22_fallback_retained, true);
  assert.equal(dto.mobility_independent_of_ratehawk, true);
  for (const action of [
    "saved",
    "taxi_to_this_stay",
    "airport_transfer",
    "stay22_fallback_availability",
  ]) {
    assert.ok(dto.existing_actions.includes(action), action);
  }
});

test("29. NL EN FR ES labels and change descriptions exist", () => {
  for (const locale of ["nl", "en", "fr", "es"]) {
    const labels = prebookActionLabels(locale);
    assert.ok(labels.check);
    assert.ok(labels.confirm);
    assert.ok(labels.accept_changes);
    assert.ok(labels.refresh);
    assert.ok(labels.other_rooms);
  }
  assert.equal(prebookActionLabels("nl").check, "Prijs en voorwaarden controleren");
  assert.equal(prebookActionLabels("en").check, "Check price and conditions");
  assert.equal(prebookActionLabels("fr").check, "Vérifier le prix et les conditions");
  assert.equal(prebookActionLabels("es").check, "Comprobar precio y condiciones");
  const localized = localizePrebookChanges(
    [{ code: "price_changed", labels: { nl: "Prijs", en: "Price", fr: "Prix", es: "Precio" } }],
    "fr",
  );
  assert.equal(localized[0].label, "Prix");
  assert.equal(RATEHAWK_PREBOOK_CHANGE_CODES.includes("no_show_changed"), true);
});

test("30. public route cannot use the test binding", () => {
  const facade = readFileSync(
    join(HERE, "../../booking/modules/ratehawk_hotels_facade.mjs"),
    "utf8",
  );
  const publicFn = facade.slice(
    facade.indexOf("export async function handlePublicRatehawkPrebook"),
    facade.indexOf("function _safeTestUnavailable"),
  );
  assert.match(publicFn, /RATEHAWK_HOTELS/);
  assert.equal(publicFn.includes("RATEHAWK_HOTELS_TEST"), false);
  assert.equal(publicFn.includes("8473727"), false);
});

test("31. no booking finish cancel or voucher path exists", () => {
  const files = [
    "ratehawk_prebook_contract.mjs",
    "ratehawk_prebook_tokens.mjs",
    "ratehawk_prebook_transport.mjs",
    "ratehawk_prebook_worker.mjs",
  ];
  const source = files.map((name) => readFileSync(join(HERE, name), "utf8")).join("\n");
  assert.equal(source.includes("/public/hotels/ratehawk/book"), false);
  assert.equal(source.includes("/public/hotels/ratehawk/finish"), false);
  assert.equal(source.includes("/public/hotels/ratehawk/cancel"), false);
  assert.equal(source.includes("/public/hotels/ratehawk/voucher"), false);
  assert.equal(source.includes("/api/b2b/v3/hotel/order/booking/form/"), false);
});

test("32. production and test prebook gates remain off", () => {
  const wrangler = readFileSync(join(HERE, "../wrangler.toml"), "utf8");
  assert.match(wrangler, /RATEHAWK_PREBOOK_ENABLED = "0"/);
  const top = wrangler.slice(0, wrangler.indexOf("[env.test]"));
  const testEnv = wrangler.slice(wrangler.indexOf("[env.test]"));
  assert.match(top, /RATEHAWK_PREBOOK_ENABLED = "0"/);
  assert.match(testEnv, /RATEHAWK_PREBOOK_ENABLED = "0"/);
  assert.equal(/RATEHAWK_PREBOOK_ENABLED\s*=\s*"1"/.test(wrangler), false);
});

test("production quota missing for prebook fails closed without transport", async () => {
  const env = enabledEnv({
    RATEHAWK_ENVIRONMENT: "production",
    RATEHAWK_PRODUCTION_ENABLED: "1",
    RATEHAWK_QUOTA_HOTELPAGE_LIMIT: "5",
    RATEHAWK_QUOTA_HOTELPAGE_WINDOW_SECONDS: "60",
    RATEHAWK_QUOTA_SERP_LIMIT: "15",
    RATEHAWK_QUOTA_SERP_WINDOW_SECONDS: "60",
    RATEHAWK_QUOTA_HOTEL_CONTENT_LIMIT: "30",
    RATEHAWK_QUOTA_HOTEL_CONTENT_WINDOW_SECONDS: "60",
  });
  const { token } = await sealRh1(env);
  const { state, fetchImpl } = trackingFetch(async () => {
    throw new Error("must_not_call_ratehawk");
  });
  const dto = await handleRatehawkPrebookRequest({
    env,
    body: { trigger: "prebook_revalidation", offer_ref: token, locale: "nl" },
    fetchImpl,
    now: NOW,
  });
  assert.equal(state.calls, 0);
  assert.equal(dto.reason, "production_quota_unconfigured");
});

test("Booking facade proxies only production Hotels and never mentions test binding in handler", async () => {
  let path = null;
  const dto = await handlePublicRatehawkPrebook({
    env: {
      BOOKING_KV: memoryKv(),
      RATEHAWK_HOTELS: {
        async fetch(request) {
          path = new URL(request.url).pathname;
          return {
            async json() {
              return { ok: true, invoked: false, reason: "prebook_disabled" };
            },
          };
        },
      },
      RATEHAWK_HOTELS_TEST: {
        async fetch() {
          throw new Error("must_not_use_test_binding");
        },
      },
    },
    request: new Request("https://booking.internal/public/hotels/ratehawk/prebook"),
    body: { trigger: "prebook_revalidation", offer_ref: "rh1.aaa.bbb", locale: "nl" },
  });
  assert.equal(path, "/internal/prebook");
  assert.equal(dto.reason, "prebook_disabled");
});

test("Booking accept facade performs zero provider reconstruction", async () => {
  const dto = await handlePublicRatehawkPrebookAccept({
    env: {
      BOOKING_KV: memoryKv(),
      RATEHAWK_HOTELS: {
        async fetch(request) {
          assert.equal(new URL(request.url).pathname, "/internal/prebook/accept");
          return {
            async json() {
              return { ok: true, invoked: false, accepted: true };
            },
          };
        },
      },
    },
    request: new Request("https://booking.internal/public/hotels/ratehawk/prebook/accept"),
    body: {
      trigger: "accept_prebook_terms",
      prebook_ref: "rhp1.aaa.bbb",
      terms_revision: "terms-rev-test",
      locale: "nl",
    },
  });
  assert.equal(dto.accepted, true);
});

test("incomplete comparison blocks progress", () => {
  const result = compareRatehawkPrebookTerms(
    { customer_total: { amount_minor: null, currency: "EUR" } },
    { customer_total: { amount_minor: 18000, currency: "EUR" } },
  );
  assert.equal(result.reason, "comparison_incomplete");
  assert.equal(result.progress_blocked, true);
});

test("test worker fetch rejects public prebook surface", async () => {
  const resp = await handleRatehawkHotelsWorkerFetch(
    new Request("https://fluxidi-ratehawk-hotels-api-test.internal/internal/prebook", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-fluxidi-internal-proxy": RATEHAWK_HOTELS_INTERNAL_PROXY,
      },
      body: JSON.stringify({ trigger: "prebook_revalidation", offer_ref: "rh1.a.b" }),
    }),
    { RATEHAWK_WORKER_SURFACE: "test", RATEHAWK_PREBOOK_ENABLED: "1" },
  );
  const dto = await resp.json();
  assert.equal(dto.reason, "production_path_forbidden_on_test_worker");
  assert.equal(dto.invoked, false);
});

const PUBLIC_PREBOOK_PATH = "/public/hotels/ratehawk/prebook";
const PUBLIC_ACCEPT_PATH = "/public/hotels/ratehawk/prebook/accept";

function trackingBookingKv(seed = null) {
  const state = { gets: 0, puts: 0 };
  return {
    state,
    kv: {
      async get() {
        state.gets += 1;
        return seed;
      },
      async put() {
        state.puts += 1;
      },
    },
  };
}

function trackingHotelsBinding() {
  const state = { calls: 0 };
  return {
    state,
    binding: {
      async fetch() {
        state.calls += 1;
        throw new Error("must_not_call_hotels");
      },
    },
  };
}

function assertPrivacySafeClientError(dto, error) {
  assert.equal(dto.ok, false);
  assert.equal(dto.error, error);
  assert.equal(dto.http_status, 400);
  const text = JSON.stringify(dto);
  assert.equal(text.includes("rh1."), false);
  assert.equal(text.includes("rhp1."), false);
  assert.equal(text.includes("{not"), false);
  assert.equal(text.includes("book_hash"), false);
}

async function postPublicPrebookRoute(path, { raw, body } = {}) {
  const kv = trackingBookingKv();
  const hotels = trackingHotelsBinding();
  const init = {
    method: "POST",
    headers: { "content-type": "application/json" },
  };
  if (raw !== undefined) init.body = raw;
  else if (body !== undefined) {
    init.body = typeof body === "string" ? body : JSON.stringify(body);
  }
  const res = await worker.fetch(
    new Request(`https://fluxidi-booking-api.internal${path}`, init),
    {
      BOOKING_KV: kv.kv,
      RATEHAWK_HOTELS: hotels.binding,
    },
    {},
  );
  const dto = await res.json();
  return { res, dto, kv: kv.state, hotels: hotels.state };
}

test("public prebook routes reject malformed JSON before KV and Hotels", async () => {
  for (const path of [PUBLIC_PREBOOK_PATH, PUBLIC_ACCEPT_PATH]) {
    const parsed = await readPublicRatehawkJsonBody(
      new Request(`https://fluxidi-booking-api.internal${path}`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: "{not-json",
      }),
    );
    assert.equal(parsed.ok, false);
    assert.equal(parsed.error, "invalid_json_body");
    const { res, dto, kv, hotels } = await postPublicPrebookRoute(path, {
      raw: "{not-json",
    });
    assert.equal(res.status, 400);
    assert.equal(dto.ok, false);
    assert.equal(dto.error, "invalid_json_body");
    assert.equal(kv.puts, 0);
    assert.equal(kv.gets, 0);
    assert.equal(hotels.calls, 0);
    assert.equal(JSON.stringify(dto).includes("{not-json"), false);
  }
});

test("public prebook routes reject empty bodies before KV and Hotels", async () => {
  for (const path of [PUBLIC_PREBOOK_PATH, PUBLIC_ACCEPT_PATH]) {
    for (const raw of ["", "   "]) {
      const { res, dto, kv, hotels } = await postPublicPrebookRoute(path, { raw });
      assert.equal(res.status, 400, path);
      assert.equal(dto.error, "invalid_json_body");
      assert.equal(kv.puts, 0);
      assert.equal(hotels.calls, 0);
    }
  }
});

test("public prebook routes reject JSON array/string/null before KV and Hotels", async () => {
  for (const path of [PUBLIC_PREBOOK_PATH, PUBLIC_ACCEPT_PATH]) {
    for (const raw of ["[]", "\"hello\"", "null"]) {
      const { res, dto, kv, hotels } = await postPublicPrebookRoute(path, { raw });
      assert.equal(res.status, 400, `${path} ${raw}`);
      assert.equal(dto.error, "invalid_request_body");
      assert.equal(kv.puts, 0);
      assert.equal(hotels.calls, 0);
    }
    const handler =
      path === PUBLIC_PREBOOK_PATH
        ? handlePublicRatehawkPrebook
        : handlePublicRatehawkPrebookAccept;
    for (const body of [[], "hello", null]) {
      const kv = trackingBookingKv();
      const hotels = trackingHotelsBinding();
      const dto = await handler({
        env: { BOOKING_KV: kv.kv, RATEHAWK_HOTELS: hotels.binding },
        body,
      });
      assertPrivacySafeClientError(dto, "invalid_request_body");
      assert.equal(kv.state.puts, 0);
      assert.equal(hotels.state.calls, 0);
    }
  }
});

test("public prebook routes reject missing required fields before KV and Hotels", async () => {
  const prebookKv = trackingBookingKv();
  const prebookHotels = trackingHotelsBinding();
  const missingTrigger = await handlePublicRatehawkPrebook({
    env: { BOOKING_KV: prebookKv.kv, RATEHAWK_HOTELS: prebookHotels.binding },
    body: { offer_ref: "rh1.aaa.bbb", locale: "nl" },
  });
  assertPrivacySafeClientError(missingTrigger, "invalid_request_body");
  const missingOffer = await handlePublicRatehawkPrebook({
    env: { BOOKING_KV: prebookKv.kv, RATEHAWK_HOTELS: prebookHotels.binding },
    body: { trigger: "prebook_revalidation", locale: "nl" },
  });
  assertPrivacySafeClientError(missingOffer, "missing_offer_ref");
  const invalidOffer = await handlePublicRatehawkPrebook({
    env: { BOOKING_KV: prebookKv.kv, RATEHAWK_HOTELS: prebookHotels.binding },
    body: { trigger: "prebook_revalidation", offer_ref: "not-opaque", locale: "nl" },
  });
  assertPrivacySafeClientError(invalidOffer, "missing_offer_ref");
  assert.equal(prebookKv.state.puts, 0);
  assert.equal(prebookHotels.state.calls, 0);

  const acceptKv = trackingBookingKv();
  const acceptHotels = trackingHotelsBinding();
  const missingAcceptTrigger = await handlePublicRatehawkPrebookAccept({
    env: { BOOKING_KV: acceptKv.kv, RATEHAWK_HOTELS: acceptHotels.binding },
    body: { prebook_ref: "rhp1.aaa.bbb", terms_revision: "rev", locale: "nl" },
  });
  assertPrivacySafeClientError(missingAcceptTrigger, "invalid_request_body");
  const missingPrebookRef = await handlePublicRatehawkPrebookAccept({
    env: { BOOKING_KV: acceptKv.kv, RATEHAWK_HOTELS: acceptHotels.binding },
    body: { trigger: "accept_prebook_terms", terms_revision: "rev", locale: "nl" },
  });
  assertPrivacySafeClientError(missingPrebookRef, "missing_prebook_ref");
  const missingRevision = await handlePublicRatehawkPrebookAccept({
    env: { BOOKING_KV: acceptKv.kv, RATEHAWK_HOTELS: acceptHotels.binding },
    body: { trigger: "accept_prebook_terms", prebook_ref: "rhp1.aaa.bbb", locale: "nl" },
  });
  assertPrivacySafeClientError(missingRevision, "missing_terms_revision");
  assert.equal(acceptKv.state.puts, 0);
  assert.equal(acceptHotels.state.calls, 0);

  const offerHttp = await postPublicPrebookRoute(PUBLIC_PREBOOK_PATH, {
    body: { trigger: "prebook_revalidation", locale: "nl" },
  });
  assert.equal(offerHttp.res.status, 400);
  assert.equal(offerHttp.dto.error, "missing_offer_ref");
  assert.equal(offerHttp.kv.puts, 0);
  assert.equal(offerHttp.hotels.calls, 0);
  const revisionHttp = await postPublicPrebookRoute(PUBLIC_ACCEPT_PATH, {
    body: { trigger: "accept_prebook_terms", prebook_ref: "rhp1.aaa.bbb" },
  });
  assert.equal(revisionHttp.res.status, 400);
  assert.equal(revisionHttp.dto.error, "missing_terms_revision");
  assert.equal(revisionHttp.kv.puts, 0);
  assert.equal(revisionHttp.hotels.calls, 0);
});

test("public prebook forbidden client-control still fails closed before KV and Hotels", async () => {
  for (const [handler, body] of [
    [
      handlePublicRatehawkPrebook,
      {
        trigger: "prebook_revalidation",
        offer_ref: "rh1.aaa.bbb",
        hash: "client-hash",
        locale: "nl",
      },
    ],
    [
      handlePublicRatehawkPrebookAccept,
      {
        trigger: "accept_prebook_terms",
        prebook_ref: "rhp1.aaa.bbb",
        terms_revision: "rev",
        price: "1.00",
        locale: "nl",
      },
    ],
  ]) {
    const kv = trackingBookingKv();
    const hotels = trackingHotelsBinding();
    const dto = await handler({
      env: { BOOKING_KV: kv.kv, RATEHAWK_HOTELS: hotels.binding },
      body,
    });
    assert.equal(dto.ok, true);
    assert.equal(dto.invoked, false);
    assert.equal(dto.reason, "client_control_forbidden");
    assert.equal(kv.state.puts, 0);
    assert.equal(hotels.state.calls, 0);
  }
});

test("structurally valid public prebook and accept still reach the limiter", async () => {
  const prebookKv = trackingBookingKv();
  const prebookHotels = trackingHotelsBinding();
  const prebook = await handlePublicRatehawkPrebook({
    env: { BOOKING_KV: prebookKv.kv, RATEHAWK_HOTELS: prebookHotels.binding },
    request: new Request("https://booking.internal/public/hotels/ratehawk/prebook", {
      headers: { "cf-connecting-ip": "203.0.113.21" },
    }),
    body: { trigger: "prebook_revalidation", offer_ref: "rh1.aaa.bbb", locale: "nl" },
  });
  assert.equal(prebookKv.state.puts, 1);
  assert.equal(prebookHotels.state.calls, 1);
  assert.equal(prebook.reason, "hotels_worker_unavailable");

  const acceptKv = trackingBookingKv();
  const acceptHotels = trackingHotelsBinding();
  const accepted = await handlePublicRatehawkPrebookAccept({
    env: { BOOKING_KV: acceptKv.kv, RATEHAWK_HOTELS: acceptHotels.binding },
    request: new Request("https://booking.internal/public/hotels/ratehawk/prebook/accept", {
      headers: { "cf-connecting-ip": "203.0.113.22" },
    }),
    body: {
      trigger: "accept_prebook_terms",
      prebook_ref: "rhp1.aaa.bbb",
      terms_revision: "terms-rev-test",
      locale: "nl",
    },
  });
  assert.equal(acceptKv.state.puts, 1);
  assert.equal(acceptHotels.state.calls, 1);
  assert.equal(accepted.reason, "hotels_worker_unavailable");
});

test("public accept limiter denial makes zero Hotels calls", async () => {
  let hotelsCalls = 0;
  const dto = await handlePublicRatehawkPrebookAccept({
    env: {
      BOOKING_KV: {
        async get() {
          return { count: 20 };
        },
        async put() {
          throw new Error("must_not_write_after_limit");
        },
      },
      RATEHAWK_HOTELS: {
        async fetch() {
          hotelsCalls += 1;
          throw new Error("must_not_call_hotels");
        },
      },
    },
    request: new Request("https://booking.internal/public/hotels/ratehawk/prebook/accept", {
      method: "POST",
      headers: { "cf-connecting-ip": "203.0.113.9" },
    }),
    body: {
      trigger: "accept_prebook_terms",
      prebook_ref: "rhp1.aaa.bbb",
      terms_revision: "terms-rev-test",
      locale: "nl",
    },
  });
  assert.equal(hotelsCalls, 0);
  assert.equal(dto.invoked, false);
  assert.equal(dto.reason, "rate_limited");
});

test("public prebook route order rejects before limiter and Hotels binding", () => {
  const workerSource = readFileSync(
    join(HERE, "../../booking/fluxidi_booking_worker.js"),
    "utf8",
  );
  const facade = readFileSync(
    join(HERE, "../../booking/modules/ratehawk_hotels_facade.mjs"),
    "utf8",
  );
  const prebookRoute = workerSource.slice(
    workerSource.indexOf('url.pathname === "/public/hotels/ratehawk/prebook"'),
    workerSource.indexOf('url.pathname === "/public/hotels/ratehawk/prebook/accept"'),
  );
  const acceptRoute = workerSource.slice(
    workerSource.indexOf('url.pathname === "/public/hotels/ratehawk/prebook/accept"'),
    workerSource.indexOf('url.pathname === "/public/hotels/google-place-photo"'),
  );
  for (const route of [prebookRoute, acceptRoute]) {
    assert.match(route, /readPublicRatehawkJsonBody/);
    assert.equal(route.includes("safeJson"), false);
    assert.ok(route.indexOf("readPublicRatehawkJsonBody") < route.indexOf("handlePublicRatehawk"));
    assert.ok(route.indexOf("parsed") < route.indexOf("handlePublicRatehawk"));
    assert.match(route, /http_status === 400/);
  }
  const prebookFn = facade.slice(
    facade.indexOf("export async function handlePublicRatehawkPrebook"),
    facade.indexOf("export async function handlePublicRatehawkPrebookAccept"),
  );
  const acceptFn = facade.slice(
    facade.indexOf("export async function handlePublicRatehawkPrebookAccept"),
    facade.indexOf("function _safeTestUnavailable"),
  );
  assert.ok(
    prebookFn.indexOf("hasForbiddenPublicPrebookClientControl") <
      prebookFn.indexOf("_incrementPrebookRateLimit"),
  );
  assert.ok(prebookFn.indexOf("missing_offer_ref") < prebookFn.indexOf("_incrementPrebookRateLimit"));
  assert.ok(
    prebookFn.indexOf("_incrementPrebookRateLimit") <
      prebookFn.indexOf("_proxyProductionHotelsPath"),
  );
  assert.ok(
    acceptFn.indexOf("hasForbiddenPublicPrebookClientControl") <
      acceptFn.indexOf("_incrementPrebookRateLimit"),
  );
  assert.ok(acceptFn.indexOf("missing_prebook_ref") < acceptFn.indexOf("_incrementPrebookRateLimit"));
  assert.ok(
    acceptFn.indexOf("missing_terms_revision") < acceptFn.indexOf("_incrementPrebookRateLimit"),
  );
  assert.ok(
    acceptFn.indexOf("_incrementPrebookRateLimit") <
      acceptFn.indexOf("_proxyProductionHotelsPath"),
  );
});
