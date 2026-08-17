// RATEHAWK-P3A mocked fail-closed booking orchestration
//
// Run:
//   node --test workers/ratehawk-hotels/modules/ratehawk_booking.test.mjs

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";
import assert from "node:assert/strict";

import worker from "../../booking/fluxidi_booking_worker.js";
import {
  bookingWorkerCanConstructRatehawkAuthorization,
  bookingWorkerHasRatehawkCredentials,
  handlePublicRatehawkBookingConfirm,
  handlePublicRatehawkBookingForm,
  handlePublicRatehawkBookingStatus,
  readPublicRatehawkJsonBody,
  runTaxiBookingIsolationProbe,
} from "../../booking/modules/ratehawk_hotels_facade.mjs";
import {
  RATEHAWK_HOTELS_INTERNAL_PROXY,
  handleRatehawkHotelsWorkerFetch,
} from "../fluxidi_ratehawk_hotels_worker.js";
import {
  RATEHAWK_BOOKING_CONFIRM_TRIGGER,
  RATEHAWK_BOOKING_FINISH_PATH,
  RATEHAWK_BOOKING_FORM_PATH,
  RATEHAWK_BOOKING_FORM_TRIGGER,
  RATEHAWK_BOOKING_PRIVACY_OMISSIONS,
  RATEHAWK_BOOKING_READINESS,
  RATEHAWK_BOOKING_SNAPSHOT_KIND,
  RATEHAWK_BOOKING_STATES,
  RATEHAWK_BOOKING_STATUS_TRIGGER,
  RATEHAWK_BOOKING_UNRESOLVED_PROVIDER_FIELDS,
  applyRatehawkBookingTransition,
  assertRatehawkAcceptedBookingClaims,
  evaluateRatehawkBookingCancelContract,
  evaluateRatehawkBookingVoucherContract,
} from "./ratehawk_booking_contract.mjs";
import { createMockRatehawkBookingFormTransport } from "./ratehawk_booking_form_transport.mjs";
import { createMockRatehawkBookingFinishTransport } from "./ratehawk_booking_finish_transport.mjs";
import { createMockRatehawkBookingStatusTransport } from "./ratehawk_booking_status_transport.mjs";
import { createMemoryRatehawkBookingIntentStore } from "./ratehawk_booking_intent_store.mjs";
import {
  handleRatehawkBookingConfirmRequest,
  handleRatehawkBookingFormRequest,
  handleRatehawkBookingStatusRequest,
} from "./ratehawk_booking_worker.mjs";
import { sealRatehawkAcceptedReference } from "./ratehawk_prebook_tokens.mjs";
import { resolveRatehawkBookingQuotaConfig } from "./ratehawk_provider_quota.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const SECRET = "rh_offer_ref_test_secret_not_real";
const BOOK_HASH = "h-booking-secret-hash-do-not-leak";
const MATCH_HASH = "m-booking-secret-hash-do-not-leak";
const NOW = Date.parse("2026-08-17T13:30:00.000Z");
const TERMS = "terms-rev-booking-1";

const DEFAULT_REQUIREMENTS = [
  { kind: "guest_first_name", required: true },
  { kind: "guest_last_name", required: true },
  { kind: "contact_email", required: true },
  { kind: "contact_phone", required: true },
];

function displaySnapshot(overrides = {}) {
  return {
    room_name: "Superior Double",
    meal_plan: "breakfast",
    breakfast_included: true,
    occupancy: { adults: 2 },
    customer_total: { amount_minor: 18000, currency: "EUR", label: "EUR 180.00" },
    included_taxes: [{ name: "vat", included_by_supplier: true }],
    excluded_taxes: [{ name: "city_tax", included_by_supplier: false }],
    payment: { type: "hotel", recipient: "hotel", timing: "at_hotel" },
    card_data_required: false,
    cvc_required: false,
    deposit: {
      disclosed: true,
      amount: { amount_minor: 5000, currency: "EUR" },
      currency: "EUR",
      refundable: true,
    },
    cancellation: {
      refundable: true,
      free_cancellation_before: "2026-09-01T10:00:00",
      penalties: [],
    },
    no_show: {
      disclosed: true,
      amount: { amount_minor: 2500, currency: "USD" },
      currency: "USD",
    },
    important_terms: [],
    ...overrides,
  };
}

function hotelsEnv(overrides = {}) {
  return {
    RATEHAWK_OFFER_REF_SECRET: SECRET,
    RATEHAWK_WORKER_SURFACE: "production",
    RATEHAWK_ENVIRONMENT: "test",
    RATEHAWK_BOOKING_FORM_ENABLED: "1",
    RATEHAWK_BOOKING_FINISH_ENABLED: "1",
    RATEHAWK_BOOKING_STATUS_ENABLED: "1",
    ...overrides,
  };
}

async function sealRha1(env, overrides = {}, now = NOW) {
  const sealed = await sealRatehawkAcceptedReference(
    env,
    {
      hid: 8473727,
      checkin: "2026-09-03",
      checkout: "2026-09-04",
      residency: "be",
      currency: "EUR",
      guests: [{ adults: 2, children: [] }],
      book_hash: BOOK_HASH,
      match_hash: MATCH_HASH,
      terms_revision: TERMS,
      display_snapshot: displaySnapshot(overrides.display_snapshot),
      surface: overrides.surface,
      environment: overrides.environment,
      tenant_id: overrides.tenant_id,
      ...overrides.claims,
    },
    { now },
  );
  assert.equal(sealed.ok, true, sealed.reason);
  return sealed.token;
}

function guestBody() {
  return {
    guest: { first_name: "Ada", last_name: "Lovelace" },
    contact: { email: "ada@example.test", phone: "+32000000000" },
  };
}

function assertPrivacy(dto) {
  const text = JSON.stringify(dto);
  assert.equal(text.includes(BOOK_HASH), false);
  assert.equal(text.includes(MATCH_HASH), false);
  assert.equal(text.includes(SECRET), false);
  assert.equal(text.includes("4111111111111111"), false);
  assert.equal(Object.hasOwn(dto, "reconciliation_amount"), false);
  assert.equal(Object.hasOwn(dto, "Authorization"), false);
  assert.equal(Object.hasOwn(dto, "book_hash"), false);
  assert.equal(Object.hasOwn(dto, "card_number"), false);
  assert.equal(Object.hasOwn(dto, "cvc"), false);
  for (const name of RATEHAWK_BOOKING_PRIVACY_OMISSIONS) {
    assert.equal(dto.omitted?.includes(name), true, name);
  }
}

function trackingBookingKv() {
  const state = { gets: 0, puts: 0 };
  return {
    state,
    kv: {
      async get() {
        state.gets += 1;
        return null;
      },
      async put() {
        state.puts += 1;
      },
    },
  };
}

function trackingHotelsBinding() {
  const state = { calls: 0, paths: [] };
  return {
    state,
    binding: {
      async fetch(request) {
        state.calls += 1;
        state.paths.push(new URL(request.url).pathname);
        throw new Error("must_not_call_hotels");
      },
    },
  };
}

async function postPublic(path, { raw, body, env } = {}) {
  const kv = trackingBookingKv();
  const hotels = trackingHotelsBinding();
  const init = {
    method: "POST",
    headers: { "content-type": "application/json" },
  };
  if (raw !== undefined) init.body = raw;
  else init.body = JSON.stringify(body ?? {});
  const res = await worker.fetch(
    new Request(`https://fluxidi-booking-api.internal${path}`, init),
    {
      BOOKING_KV: kv.kv,
      RATEHAWK_HOTELS: hotels.binding,
      RATEHAWK_HOTELS_TEST: {
        async fetch() {
          throw new Error("must_not_use_test_binding");
        },
      },
      ...env,
    },
    {},
  );
  return { res, dto: await res.json(), kv: kv.state, hotels: hotels.state };
}

async function prepareReadyIntent(env, {
  acceptedRef,
  requirements = DEFAULT_REQUIREMENTS,
  paymentRef,
} = {}) {
  const store = createMemoryRatehawkBookingIntentStore();
  const form = createMockRatehawkBookingFormTransport({ requirements });
  const formDto = await handleRatehawkBookingFormRequest({
    env,
    body: {
      trigger: RATEHAWK_BOOKING_FORM_TRIGGER,
      accepted_ref: acceptedRef,
      locale: "nl",
      ...guestBody(),
      provider_payment_ref: paymentRef,
    },
    now: NOW,
    formTransport: form.formTransport,
    intentStore: store,
  });
  return { store, form, formDto };
}

test("1. all booking gates off perform zero binding or provider calls", async () => {
  const form = createMockRatehawkBookingFormTransport();
  const finish = createMockRatehawkBookingFinishTransport();
  const status = createMockRatehawkBookingStatusTransport();
  const env = hotelsEnv({
    RATEHAWK_BOOKING_FORM_ENABLED: "0",
    RATEHAWK_BOOKING_FINISH_ENABLED: "0",
    RATEHAWK_BOOKING_STATUS_ENABLED: "0",
  });
  const token = await sealRha1(env);
  const formDto = await handleRatehawkBookingFormRequest({
    env,
    body: { trigger: RATEHAWK_BOOKING_FORM_TRIGGER, accepted_ref: token },
    formTransport: form.formTransport,
    now: NOW,
  });
  const confirmDto = await handleRatehawkBookingConfirmRequest({
    env,
    body: {
      trigger: RATEHAWK_BOOKING_CONFIRM_TRIGGER,
      accepted_ref: token,
      confirm: true,
      terms_revision: TERMS,
    },
    finishTransport: finish.finishTransport,
    now: NOW,
  });
  const statusDto = await handleRatehawkBookingStatusRequest({
    env,
    body: { trigger: RATEHAWK_BOOKING_STATUS_TRIGGER, accepted_ref: token },
    statusTransport: status.statusTransport,
    now: NOW,
  });
  assert.equal(form.state.calls, 0);
  assert.equal(finish.state.calls, 0);
  assert.equal(status.state.calls, 0);
  assert.equal(formDto.reason, "booking_form_disabled");
  assert.equal(confirmDto.reason, "booking_finish_disabled");
  assert.equal(statusDto.reason, "booking_status_disabled");

  const publicForm = await handlePublicRatehawkBookingForm({
    env: {
      BOOKING_KV: trackingBookingKv().kv,
      RATEHAWK_HOTELS: trackingHotelsBinding().binding,
      RATEHAWK_BOOKING_FORM_ENABLED: "0",
    },
    request: new Request("https://booking.internal/public/hotels/ratehawk/booking/form"),
    body: {
      trigger: RATEHAWK_BOOKING_FORM_TRIGGER,
      accepted_ref: "rha1.aaa.bbb",
      locale: "nl",
    },
  });
  assert.equal(publicForm.reason, "booking_form_disabled");
  assert.equal(publicForm.binding_called, false);
});

test("2. malformed body fails before KV and bindings", async () => {
  for (const path of [
    "/public/hotels/ratehawk/booking/form",
    "/public/hotels/ratehawk/booking/confirm",
    "/public/hotels/ratehawk/booking/status",
  ]) {
    const parsed = await readPublicRatehawkJsonBody(
      new Request(`https://fluxidi-booking-api.internal${path}`, {
        method: "POST",
        body: "{not-json",
      }),
    );
    assert.equal(parsed.error, "invalid_json_body");
    const { res, dto, kv, hotels } = await postPublic(path, { raw: "{not-json" });
    assert.equal(res.status, 400);
    assert.equal(dto.error, "invalid_json_body");
    assert.equal(kv.puts, 0);
    assert.equal(kv.gets, 0);
    assert.equal(hotels.calls, 0);
  }
});

test("3. bad expired and tampered rha1 are rejected", async () => {
  const env = hotelsEnv();
  const store = createMemoryRatehawkBookingIntentStore();
  const form = createMockRatehawkBookingFormTransport();
  const bad = await handleRatehawkBookingFormRequest({
    env,
    body: {
      trigger: RATEHAWK_BOOKING_FORM_TRIGGER,
      accepted_ref: "rha1.not.real",
    },
    formTransport: form.formTransport,
    intentStore: store,
    now: NOW,
  });
  assert.equal(bad.reason, "rha1_invalid");
  assert.equal(form.state.calls, 0);

  const token = await sealRha1(env);
  const expired = await handleRatehawkBookingFormRequest({
    env,
    body: { trigger: RATEHAWK_BOOKING_FORM_TRIGGER, accepted_ref: token },
    formTransport: form.formTransport,
    intentStore: store,
    now: NOW + 16 * 60 * 1000,
  });
  assert.equal(expired.reason, "rha1_expired");
  assert.equal(form.state.calls, 0);

  const tampered = `${token.slice(0, -2)}ab`;
  const invalid = await handleRatehawkBookingFormRequest({
    env,
    body: { trigger: RATEHAWK_BOOKING_FORM_TRIGGER, accepted_ref: tampered },
    formTransport: form.formTransport,
    intentStore: store,
    now: NOW,
  });
  assert.equal(invalid.reason, "rha1_invalid");
  assert.equal(form.state.calls, 0);
});

test("4. test and production tokens stay isolated", async () => {
  const form = createMockRatehawkBookingFormTransport();
  const store = createMemoryRatehawkBookingIntentStore();
  const testToken = await sealRha1(hotelsEnv(), { surface: "test" });
  const production = await handleRatehawkBookingFormRequest({
    env: hotelsEnv(),
    body: { trigger: RATEHAWK_BOOKING_FORM_TRIGGER, accepted_ref: testToken },
    formTransport: form.formTransport,
    intentStore: store,
    now: NOW,
  });
  assert.equal(production.reason, "test_token_forbidden_on_production");

  const prodToken = await sealRha1(hotelsEnv());
  const testSurface = await handleRatehawkBookingFormRequest({
    env: hotelsEnv({ RATEHAWK_WORKER_SURFACE: "test" }),
    body: { trigger: RATEHAWK_BOOKING_FORM_TRIGGER, accepted_ref: prodToken },
    formTransport: form.formTransport,
    intentStore: store,
    now: NOW,
  });
  assert.equal(testSurface.reason, "production_path_forbidden_on_test_worker");
  const claimsCheck = assertRatehawkAcceptedBookingClaims(
    { purpose: "accepted_prebook", surface: undefined, terms_revision: TERMS, hid: 1, checkin: "2026-09-03", checkout: "2026-09-04", guests: [{}], display_snapshot: displaySnapshot() },
    { env: { RATEHAWK_WORKER_SURFACE: "test" } },
  );
  assert.equal(claimsCheck.reason, "production_token_forbidden_on_test");
  assert.equal(form.state.calls, 0);
});

test("5. stale terms revision is rejected", async () => {
  const env = hotelsEnv();
  const token = await sealRha1(env);
  const { store, form } = await prepareReadyIntent(env, { acceptedRef: token });
  const finish = createMockRatehawkBookingFinishTransport();
  const dto = await handleRatehawkBookingConfirmRequest({
    env,
    body: {
      trigger: RATEHAWK_BOOKING_CONFIRM_TRIGGER,
      accepted_ref: token,
      confirm: true,
      terms_revision: "stale-revision",
    },
    finishTransport: finish.finishTransport,
    intentStore: store,
    now: NOW,
  });
  assert.equal(dto.reason, "terms_revision_mismatch");
  assert.equal(finish.state.calls, 0);
  assert.equal(form.state.calls, 1);
});

test("6. deposit payment type is rejected", async () => {
  const env = hotelsEnv();
  const token = await sealRha1(env, {
    display_snapshot: displaySnapshot({
      payment: { type: "deposit", recipient: "etg", timing: "at_booking" },
    }),
  });
  const form = createMockRatehawkBookingFormTransport();
  const dto = await handleRatehawkBookingFormRequest({
    env,
    body: { trigger: RATEHAWK_BOOKING_FORM_TRIGGER, accepted_ref: token },
    formTransport: form.formTransport,
    intentStore: createMemoryRatehawkBookingIntentStore(),
    now: NOW,
  });
  assert.equal(dto.reason, "deposit_requires_fluxidi_to_fund_etg");
  assert.equal(form.state.calls, 0);
});

test("7. unknown payment-critical field is rejected", async () => {
  const env = hotelsEnv();
  const token = await sealRha1(env, {
    display_snapshot: displaySnapshot({
      important_terms: ["guarantee_payment_amount"],
    }),
  });
  const form = createMockRatehawkBookingFormTransport();
  const dto = await handleRatehawkBookingFormRequest({
    env,
    body: { trigger: RATEHAWK_BOOKING_FORM_TRIGGER, accepted_ref: token },
    formTransport: form.formTransport,
    intentStore: createMemoryRatehawkBookingIntentStore(),
    now: NOW,
  });
  assert.equal(dto.reason, "unknown_payment_critical_field");
  assert.equal(form.state.calls, 0);
});

test("8. hotel payment never involves Fluxidi money", async () => {
  const env = hotelsEnv();
  const token = await sealRha1(env);
  const { formDto } = await prepareReadyIntent(env, { acceptedRef: token });
  assert.equal(formDto.commercial.customer_pays_fluxidi, false);
  assert.equal(formDto.commercial.mollie_involved, false);
  assert.equal(formDto.commercial.fluxidi_is_merchant_of_record, false);
  assert.equal(formDto.payment.type, "hotel");
  assert.equal(formDto.payment.recipient, "hotel");
});

test("9. now payment requires only an approved opaque provider token seam", async () => {
  const env = hotelsEnv();
  const token = await sealRha1(env, {
    display_snapshot: displaySnapshot({
      payment: { type: "now", recipient: "ratehawk_etg", timing: "at_booking" },
    }),
  });
  const requirements = [
    ...DEFAULT_REQUIREMENTS,
    { kind: "provider_payment_token", required: true },
  ];
  const missing = await prepareReadyIntent(env, { acceptedRef: token, requirements });
  assert.equal(
    missing.formDto.readiness,
    RATEHAWK_BOOKING_READINESS.PROVIDER_PAYMENT_TOKEN_ACTION_REQUIRED,
  );
  const ready = await handleRatehawkBookingFormRequest({
    env,
    body: {
      trigger: RATEHAWK_BOOKING_FORM_TRIGGER,
      accepted_ref: token,
      locale: "nl",
      ...guestBody(),
      provider_payment_ref: "rhpay1.opaque.token",
    },
    formTransport: missing.form.formTransport,
    intentStore: missing.store,
    now: NOW,
  });
  assert.equal(
    ready.readiness,
    RATEHAWK_BOOKING_READINESS.READY_FOR_DELIBERATE_CONFIRMATION,
  );
  assert.equal(ready.commercial.customer_pays_fluxidi, false);
});

test("10. PAN and CVC are rejected and never stored or logged", async () => {
  const env = hotelsEnv();
  const token = await sealRha1(env);
  const store = createMemoryRatehawkBookingIntentStore();
  const form = createMockRatehawkBookingFormTransport();
  const dto = await handleRatehawkBookingFormRequest({
    env,
    body: {
      trigger: RATEHAWK_BOOKING_FORM_TRIGGER,
      accepted_ref: token,
      card_number: "4111111111111111",
      cvc: "123",
    },
    formTransport: form.formTransport,
    intentStore: store,
    now: NOW,
  });
  assert.equal(dto.reason, "pan_or_cvc_forbidden");
  assert.equal(form.state.calls, 0);
  assertPrivacy(dto);
  const publicDto = await handlePublicRatehawkBookingForm({
    env: { BOOKING_KV: trackingBookingKv().kv, RATEHAWK_HOTELS: trackingHotelsBinding().binding },
    body: {
      trigger: RATEHAWK_BOOKING_FORM_TRIGGER,
      accepted_ref: "rha1.aaa.bbb",
      cvc: "123",
    },
  });
  assert.equal(publicDto.error, "pan_or_cvc_forbidden");
  assert.equal(publicDto.http_status, 400);
});

test("11. booking form maps required guest and contact fields", async () => {
  const env = hotelsEnv();
  const token = await sealRha1(env);
  const incomplete = await handleRatehawkBookingFormRequest({
    env,
    body: { trigger: RATEHAWK_BOOKING_FORM_TRIGGER, accepted_ref: token },
    formTransport: createMockRatehawkBookingFormTransport({
      requirements: DEFAULT_REQUIREMENTS,
    }).formTransport,
    intentStore: createMemoryRatehawkBookingIntentStore(),
    now: NOW,
  });
  assert.equal(incomplete.state, RATEHAWK_BOOKING_STATES.FORM_REQUIRED);
  assert.equal(incomplete.readiness, RATEHAWK_BOOKING_READINESS.CUSTOMER_INPUT_REQUIRED);
  assert.deepEqual(incomplete.missing_fields, [
    "guest_first_name",
    "guest_last_name",
    "contact_email",
    "contact_phone",
  ]);
  const { formDto } = await prepareReadyIntent(env, { acceptedRef: token });
  assert.equal(formDto.state, RATEHAWK_BOOKING_STATES.CUSTOMER_CONFIRMATION_REQUIRED);
  assert.equal(
    formDto.readiness,
    RATEHAWK_BOOKING_READINESS.READY_FOR_DELIBERATE_CONFIRMATION,
  );
  assert.equal(formDto.hashes_exposed, false);
});

test("12. unknown form requirement fails closed", async () => {
  const env = hotelsEnv();
  const token = await sealRha1(env);
  const form = createMockRatehawkBookingFormTransport({
    requirements: [{ kind: "passport_scan", required: true }],
  });
  const dto = await handleRatehawkBookingFormRequest({
    env,
    body: { trigger: RATEHAWK_BOOKING_FORM_TRIGGER, accepted_ref: token },
    formTransport: form.formTransport,
    intentStore: createMemoryRatehawkBookingIntentStore(),
    now: NOW,
  });
  assert.equal(dto.reason, "unknown_form_requirement");
  assert.equal(form.state.calls, 1);
});

test("13. deliberate confirmation is required", async () => {
  const env = hotelsEnv();
  const token = await sealRha1(env);
  const { store } = await prepareReadyIntent(env, { acceptedRef: token });
  const finish = createMockRatehawkBookingFinishTransport();
  const dto = await handleRatehawkBookingConfirmRequest({
    env,
    body: {
      trigger: RATEHAWK_BOOKING_CONFIRM_TRIGGER,
      accepted_ref: token,
      terms_revision: TERMS,
    },
    finishTransport: finish.finishTransport,
    intentStore: store,
    now: NOW,
  });
  assert.equal(dto.reason, "deliberate_confirmation_required");
  assert.equal(finish.state.calls, 0);
});

test("14-16. exactly one mocked finish, replay is idempotent, timeout stays unknown", async () => {
  const env = hotelsEnv();
  const token = await sealRha1(env);
  const { store } = await prepareReadyIntent(env, { acceptedRef: token });
  const finish = createMockRatehawkBookingFinishTransport({ outcome: "timeout" });
  const first = await handleRatehawkBookingConfirmRequest({
    env,
    body: {
      trigger: RATEHAWK_BOOKING_CONFIRM_TRIGGER,
      accepted_ref: token,
      confirm: true,
      terms_revision: TERMS,
    },
    finishTransport: finish.finishTransport,
    intentStore: store,
    now: NOW,
  });
  assert.equal(first.state, RATEHAWK_BOOKING_STATES.CONFIRMATION_UNKNOWN);
  assert.equal(first.reason, "confirmation_unknown");
  assert.equal(finish.state.calls, 1);
  const replay = await handleRatehawkBookingConfirmRequest({
    env,
    body: {
      trigger: RATEHAWK_BOOKING_CONFIRM_TRIGGER,
      accepted_ref: token,
      confirm: true,
      terms_revision: TERMS,
    },
    finishTransport: finish.finishTransport,
    intentStore: store,
    now: NOW + 1000,
  });
  assert.equal(replay.replayed, true);
  assert.equal(replay.state, RATEHAWK_BOOKING_STATES.CONFIRMATION_UNKNOWN);
  assert.equal(finish.state.calls, 1);
});

test("17-20. bounded status polling and evidence-only outcomes", async () => {
  const env = hotelsEnv();
  const token = await sealRha1(env);
  const { store } = await prepareReadyIntent(env, { acceptedRef: token });
  const finish = createMockRatehawkBookingFinishTransport({ outcome: "pending" });
  const submitted = await handleRatehawkBookingConfirmRequest({
    env,
    body: {
      trigger: RATEHAWK_BOOKING_CONFIRM_TRIGGER,
      accepted_ref: token,
      confirm: true,
      terms_revision: TERMS,
    },
    finishTransport: finish.finishTransport,
    intentStore: store,
    now: NOW,
  });
  assert.equal(submitted.state, RATEHAWK_BOOKING_STATES.PROVIDER_PENDING);
  assert.equal(finish.state.calls, 1);

  const pendingStatus = createMockRatehawkBookingStatusTransport({
    sequence: [{ status: "pending" }, { status: "pending" }, { status: "pending" }],
  });
  const pending = await handleRatehawkBookingStatusRequest({
    env,
    body: { trigger: RATEHAWK_BOOKING_STATUS_TRIGGER, accepted_ref: token },
    statusTransport: pendingStatus.statusTransport,
    intentStore: store,
    now: NOW,
  });
  assert.equal(pending.state, RATEHAWK_BOOKING_STATES.PROVIDER_PENDING);
  assert.equal(pending.pending, true);
  assert.equal(pending.finish_resubmitted, false);
  assert.equal(pending.polls, 3);
  assert.equal(pending.confirmation.confirmed, false);

  const confirmedStatus = createMockRatehawkBookingStatusTransport({
    sequence: [
      {
        status: "confirmed",
        provider_order_id: "RH-ORDER-88",
        provider_evidence_kind: "finish_status",
      },
    ],
  });
  const confirmed = await handleRatehawkBookingStatusRequest({
    env,
    body: { trigger: RATEHAWK_BOOKING_STATUS_TRIGGER, accepted_ref: token },
    statusTransport: confirmedStatus.statusTransport,
    intentStore: store,
    now: NOW + 2000,
  });
  assert.equal(confirmed.state, RATEHAWK_BOOKING_STATES.CONFIRMED);
  assert.equal(confirmed.confirmation.confirmed, true);
  assert.equal(confirmed.confirmation.provider_order_id, "RH-ORDER-88");
  assert.equal(confirmed.dispute_snapshot.ok, true);

  const declinedEnv = hotelsEnv();
  const declinedToken = await sealRha1(declinedEnv);
  const declinedReady = await prepareReadyIntent(declinedEnv, {
    acceptedRef: declinedToken,
  });
  await handleRatehawkBookingConfirmRequest({
    env: declinedEnv,
    body: {
      trigger: RATEHAWK_BOOKING_CONFIRM_TRIGGER,
      accepted_ref: declinedToken,
      confirm: true,
      terms_revision: TERMS,
    },
    finishTransport: createMockRatehawkBookingFinishTransport({
      outcome: "pending",
    }).finishTransport,
    intentStore: declinedReady.store,
    now: NOW,
  });
  const declined = await handleRatehawkBookingStatusRequest({
    env: declinedEnv,
    body: { trigger: RATEHAWK_BOOKING_STATUS_TRIGGER, accepted_ref: declinedToken },
    statusTransport: createMockRatehawkBookingStatusTransport({
      sequence: [{ status: "declined", provider_evidence_kind: "finish_status" }],
    }).statusTransport,
    intentStore: declinedReady.store,
    now: NOW,
  });
  assert.equal(declined.state, RATEHAWK_BOOKING_STATES.PROVIDER_DECLINED);
  assert.equal(declined.confirmation.confirmed, false);
});

test("21-23. safe confirmation DTO, immutable snapshot and privacy exclusions", async () => {
  const env = hotelsEnv();
  const token = await sealRha1(env);
  const { store } = await prepareReadyIntent(env, { acceptedRef: token });
  const finish = createMockRatehawkBookingFinishTransport({
    outcome: "confirmed",
    providerOrderId: "RH-ORDER-21",
    evidenceKind: "finish_status",
  });
  const dto = await handleRatehawkBookingConfirmRequest({
    env,
    body: {
      trigger: RATEHAWK_BOOKING_CONFIRM_TRIGGER,
      accepted_ref: token,
      confirm: true,
      terms_revision: TERMS,
    },
    finishTransport: finish.finishTransport,
    intentStore: store,
    now: NOW,
  });
  assert.equal(dto.state, RATEHAWK_BOOKING_STATES.CONFIRMED);
  assert.equal(dto.confirmation.confirmed, true);
  assert.equal(dto.confirmation.provider_order_id, "RH-ORDER-21");
  assert.equal(dto.confirmation.hid, 8473727);
  assert.equal(dto.confirmation.customer_total.currency, "EUR");
  assert.equal(dto.confirmation.voucher_available, false);
  assert.equal(dto.dispute_snapshot.snapshot_kind, RATEHAWK_BOOKING_SNAPSHOT_KIND);
  assert.equal(dto.dispute_snapshot.immutable, true);
  assert.equal(dto.dispute_snapshot.provider_order_id, "RH-ORDER-21");
  assert.equal(dto.dispute_snapshot.terms_revision, TERMS);
  assertPrivacy(dto);
  assert.equal(JSON.stringify(dto).includes("Ada"), false);
});

test("24. cancellation and voucher remain unavailable and gated", () => {
  const cancel = evaluateRatehawkBookingCancelContract();
  const voucher = evaluateRatehawkBookingVoucherContract();
  assert.equal(cancel.available, false);
  assert.equal(cancel.live_endpoint_authorized, false);
  assert.equal(voucher.available, false);
  assert.equal(voucher.public_unauthenticated_url, false);
  assert.equal(
    RATEHAWK_BOOKING_UNRESOLVED_PROVIDER_FIELDS.form_request.includes("hash"),
    true,
  );
  assert.equal(RATEHAWK_BOOKING_FORM_PATH.endsWith("booking/form/"), true);
  assert.equal(RATEHAWK_BOOKING_FINISH_PATH.endsWith("booking/finish/"), true);
});

test("25. public route cannot use the test binding", async () => {
  const facade = readFileSync(
    join(HERE, "../../booking/modules/ratehawk_hotels_facade.mjs"),
    "utf8",
  );
  const publicFn = facade.slice(
    facade.indexOf("export async function handlePublicRatehawkBookingForm"),
    facade.indexOf("function _safeTestUnavailable"),
  );
  assert.match(publicFn, /RATEHAWK_HOTELS/);
  assert.equal(publicFn.includes("RATEHAWK_HOTELS_TEST"), false);
  const { hotels } = await postPublic("/public/hotels/ratehawk/booking/form", {
    body: {
      trigger: RATEHAWK_BOOKING_FORM_TRIGGER,
      accepted_ref: "rha1.aaa.bbb",
      locale: "nl",
    },
    env: { RATEHAWK_BOOKING_FORM_ENABLED: "0" },
  });
  assert.equal(hotels.calls, 0);
});

test("26. Booking holds no RateHawk credentials", () => {
  assert.equal(bookingWorkerHasRatehawkCredentials({}), false);
  assert.equal(bookingWorkerCanConstructRatehawkAuthorization({}), false);
  const wrangler = readFileSync(join(HERE, "../../booking/wrangler.toml"), "utf8");
  assert.equal(/RATEHAWK_API_KEY\s*=/.test(wrangler), false);
  assert.equal(/RATEHAWK_KEY_ID\s*=/.test(wrangler), false);
  assert.equal(/RATEHAWK_OFFER_REF_SECRET\s*=/.test(wrangler), false);
});

test("27. taxi payment Billit and Limousine stay isolated", () => {
  const taxi = runTaxiBookingIsolationProbe({ distance_km: 6 });
  assert.equal(taxi.invoked_ratehawk, false);
  assert.equal(taxi.kind, "taxi_quote");
  const street = readFileSync(
    join(HERE, "../../booking/modules/street_ride_never_planned.test.mjs"),
    "utf8",
  );
  const fleet = readFileSync(
    join(HERE, "../../booking/modules/fleet_vehicle_tombstone.mjs"),
    "utf8",
  );
  assert.equal(street.includes("/public/hotels/ratehawk/booking"), false);
  assert.equal(fleet.includes("RATEHAWK_BOOKING"), false);
});

test("28. existing Search Hotelpage and Prebook suites stay gated off in wrangler", () => {
  const hotels = readFileSync(join(HERE, "../wrangler.toml"), "utf8");
  const booking = readFileSync(join(HERE, "../../booking/wrangler.toml"), "utf8");
  const top = hotels.slice(0, hotels.indexOf("[env.test]"));
  assert.match(top, /RATEHAWK_PREBOOK_ENABLED = "0"/);
  assert.match(top, /RATEHAWK_BOOKING_FORM_ENABLED = "0"/);
  assert.match(top, /RATEHAWK_BOOKING_FINISH_ENABLED = "0"/);
  assert.match(top, /RATEHAWK_BOOKING_STATUS_ENABLED = "0"/);
  assert.match(booking, /RATEHAWK_BOOKING_FORM_ENABLED = "0"/);
  assert.equal(/RATEHAWK_BOOKING_FORM_ENABLED\s*=\s*"1"/.test(hotels), false);
  assert.equal(/RATEHAWK_BOOKING_FINISH_ENABLED\s*=\s*"1"/.test(booking), false);
});

test("illegal and stale state transitions fail closed", () => {
  const stale = applyRatehawkBookingTransition("form_ready", "confirmed", {
    revision: 4,
    nextRevision: 3,
  });
  assert.equal(stale.reason, "stale_revision");
  const illegal = applyRatehawkBookingTransition("accepted_prebook", "confirmed", {
    revision: 0,
    nextRevision: 1,
  });
  assert.equal(illegal.reason, "illegal_transition");
  const replay = applyRatehawkBookingTransition("form_ready", "form_ready", {
    revision: 2,
    nextRevision: 2,
  });
  assert.equal(replay.idempotent, true);
  const unknown = applyRatehawkBookingTransition(
    RATEHAWK_BOOKING_STATES.CONFIRMATION_UNKNOWN,
    RATEHAWK_BOOKING_STATES.FINISH_SUBMITTED,
    { revision: 5, nextRevision: 6 },
  );
  assert.equal(unknown.reason, "illegal_transition");
});

test("production booking quota is required before any later live call", () => {
  const missing = resolveRatehawkBookingQuotaConfig({
    RATEHAWK_ENVIRONMENT: "production",
  });
  assert.equal(missing.ok, false);
  assert.equal(missing.reason, "production_quota_unconfigured");
});

test("missing intent store fails only hotel booking", async () => {
  const env = hotelsEnv();
  const token = await sealRha1(env);
  const form = createMockRatehawkBookingFormTransport();
  const dto = await handleRatehawkBookingFormRequest({
    env,
    body: { trigger: RATEHAWK_BOOKING_FORM_TRIGGER, accepted_ref: token },
    formTransport: form.formTransport,
    now: NOW,
  });
  assert.equal(dto.reason, "booking_intent_store_unconfigured");
  assert.equal(form.state.calls, 0);
});

test("test Hotels worker rejects public booking paths", async () => {
  const resp = await handleRatehawkHotelsWorkerFetch(
    new Request("https://fluxidi-ratehawk-hotels-api-test.internal/internal/booking/form", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-fluxidi-internal-proxy": RATEHAWK_HOTELS_INTERNAL_PROXY,
      },
      body: JSON.stringify({
        trigger: RATEHAWK_BOOKING_FORM_TRIGGER,
        accepted_ref: "rha1.a.b",
      }),
    }),
    { RATEHAWK_WORKER_SURFACE: "test", RATEHAWK_BOOKING_FORM_ENABLED: "1" },
  );
  const dto = await resp.json();
  assert.equal(dto.reason, "production_path_forbidden_on_test_worker");
});

test("public booking facade proxies only production Hotels when gated on", async () => {
  let path = null;
  const dto = await handlePublicRatehawkBookingForm({
    env: {
      BOOKING_KV: trackingBookingKv().kv,
      RATEHAWK_BOOKING_FORM_ENABLED: "1",
      RATEHAWK_HOTELS: {
        async fetch(request) {
          path = new URL(request.url).pathname;
          return {
            async json() {
              return { ok: true, reason: "booking_form_disabled" };
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
    request: new Request("https://booking.internal/public/hotels/ratehawk/booking/form"),
    body: {
      trigger: RATEHAWK_BOOKING_FORM_TRIGGER,
      accepted_ref: "rha1.aaa.bbb",
      locale: "nl",
    },
  });
  assert.equal(path, "/internal/booking/form");
  assert.equal(dto.reason, "booking_form_disabled");
});

test("structurally valid public booking still uses BOOKING_KV", async () => {
  const kv = trackingBookingKv();
  const hotels = trackingHotelsBinding();
  await handlePublicRatehawkBookingStatus({
    env: {
      BOOKING_KV: kv.kv,
      RATEHAWK_HOTELS: hotels.binding,
      RATEHAWK_BOOKING_STATUS_ENABLED: "0",
    },
    request: new Request("https://booking.internal/public/hotels/ratehawk/booking/status", {
      headers: { "cf-connecting-ip": "203.0.113.40" },
    }),
    body: {
      trigger: RATEHAWK_BOOKING_STATUS_TRIGGER,
      accepted_ref: "rha1.aaa.bbb",
      locale: "nl",
    },
  });
  assert.equal(kv.state.puts, 1);
  assert.equal(hotels.state.calls, 0);
});

test("local configuration alone cannot mark a booking confirmed", async () => {
  const env = hotelsEnv();
  const token = await sealRha1(env);
  const { formDto } = await prepareReadyIntent(env, { acceptedRef: token });
  assert.equal(formDto.confirmation == null, true);
  assert.notEqual(formDto.booking_attempt_id, "confirmed");
});
