// Never-POSTed blocked sequence_unsafe aankomst recovery.
//
// Run:
//   node --test workers/compliance/chiron_sequence_recovery.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import { __testInternals } from "./fluxidi_compliance_worker.js";

const {
  validateChironOfficialPayloadDraft,
  _chironOfficialDepartureSatisfiesSequence,
  _chironNeverPostedBlockedRecoveryEligible,
  _chironEvaluateSubmitDuplicateGuard,
  _chironOfficialDraftReadyForSubmit,
  _chironBuildOfficialDraftForSingleEvent,
  _chironAutoSubmitOneEvent,
  _chironDepartureCanonicalDecision,
  buildChironOfficialIdempotencyKey,
  buildChironExportStatusKey,
  CHIRON_EXPORT_STATUS_SCHEMA,
  CHIRON_DEPARTURE_CONFIRMED_EXTERNAL,
  encryptChironCredentialBlob,
  buildChironCredentialsKvKey,
  CHIRON_CREDENTIALS_PAYLOAD_SCHEMA_VERSION,
  CHIRON_CREDENTIALS_SCHEMA_VERSION,
  safeSegment,
} = __testInternals;

const TENANT = "T1";
const COMPANY = "C1";
const BOOKING = "2026-08-184";
const ACC_URL = "https://mow-acc.api.vlaanderen.be/chiron/taxirit";
const ENCRYPTION_KEY = "test-only-encryption-key-must-be->=32-chars";
const ADMIN = "admin-token-for-tests";

function makeKV({ seed = {} } = {}) {
  const store = new Map(Object.entries(seed));
  return {
    store,
    async get(key, opts) {
      if (!store.has(key)) return null;
      const raw = store.get(key);
      if (opts && opts.type === "json") {
        try {
          return JSON.parse(raw);
        } catch (_) {
          return null;
        }
      }
      return raw;
    },
    async put(key, val) {
      store.set(key, typeof val === "string" ? val : JSON.stringify(val));
    },
    async list({ prefix = "", limit = 1000, cursor } = {}) {
      const names = [...store.keys()].filter((k) => k.startsWith(prefix)).sort();
      const startIdx = cursor ? Number(cursor) : 0;
      const slice = names.slice(startIdx, startIdx + limit);
      const nextCursor = startIdx + slice.length;
      const listComplete = nextCursor >= names.length;
      return {
        keys: slice.map((name) => ({ name })),
        list_complete: listComplete,
        cursor: listComplete ? undefined : String(nextCursor),
      };
    },
  };
}

function rideStop(overrides = {}) {
  return {
    event_type: "ride_stop",
    event_id: `ride_stop:${TENANT}:${COMPANY}:planned_${BOOKING}_${BOOKING}_outbound`,
    tenant_id: TENANT,
    company_id: COMPANY,
    booking_id: BOOKING,
    trip_id: `planned_${BOOKING}_${BOOKING}_outbound`,
    leg_type: "outbound",
    ride_type: "planned",
    created_at_utc: "2026-08-24T10:03:01.888Z",
    timestamps: {
      event_at_utc: "2026-08-24T10:02:59.000Z",
      started_at_utc: "2026-08-24T10:02:57.000Z",
      stopped_at_utc: "2026-08-24T10:02:59.000Z",
    },
    driver: { driver_id: "drv_1" },
    vehicle: { vehicle_id: "vh_1", license_plate: "TXABC123" },
    locations: {
      pickup: { lat: 50.8467, lng: 4.3525, label: "origin" },
      dropoff: { lat: 50.901, lng: 4.484, label: "dest" },
    },
    fare: {
      currency: "EUR",
      distance_km: 12.4,
      wait_seconds_total: 0,
      total_amount: 93.28,
    },
    ...overrides,
  };
}

function taxiDirectStop(overrides = {}) {
  return rideStop({
    booking_id: "street_direct_1",
    trip_id: "trip_direct_1",
    event_id: `ride_stop:${TENANT}:${COMPANY}:trip_direct_1`,
    ride_type: "direct",
    leg_type: undefined,
    fare: { currency: "EUR", distance_km: 8.2, total_amount: 22.5 },
    ...overrides,
  });
}

function taxiDirectStart() {
  return {
    event_type: "ride_start",
    event_id: `ride_start:${TENANT}:${COMPANY}:s_direct_1`,
    tenant_id: TENANT,
    company_id: COMPANY,
    booking_id: "street_direct_1",
    trip_id: "trip_direct_1",
    ride_type: "direct",
    created_at_utc: "2026-08-24T10:00:00.000Z",
    timestamps: {
      event_at_utc: "2026-08-24T09:59:58.000Z",
      started_at_utc: "2026-08-24T09:59:58.000Z",
    },
    driver: { driver_id: "drv_1" },
    vehicle: { vehicle_id: "vh_1", license_plate: "TXABC123" },
    locations: {
      pickup: { lat: 50.8467, lng: 4.3525, label: "origin" },
    },
  };
}

function aankomstPayload(overrides = {}) {
  return {
    status: "aankomst",
    ritnummer: `${BOOKING}-outbound`,
    registratie: "0772931038",
    kentekenplaat: "TXABC123",
    bestuurderspasnummer: "1234567890",
    vertrektijdstip: "2026-08-24T10:02:57.000Z",
    aankomsttijdstip: "2026-08-24T10:02:59.000Z",
    vertrekpunt_lengtegraad: 4.3525,
    vertrekpunt_breedtegraad: 50.8467,
    aankomstpunt_lengtegraad: 4.484,
    aankomstpunt_breedtegraad: 50.901,
    afstand: 12.4,
    kostprijs: 93.28,
    ...overrides,
  };
}

function neverPostedBlocked(overrides = {}) {
  return {
    schema_version: CHIRON_EXPORT_STATUS_SCHEMA,
    sync_state: "blocked",
    reason_code: "sequence_unsafe",
    failure_kind: "retryable",
    attempt_count: 0,
    external_status_code: null,
    outbound_fingerprint: null,
    official_status: "aankomst",
    official_ritnummer: `${BOOKING}-outbound`,
    ...overrides,
  };
}

function installFetchStub(handler) {
  const original = globalThis.fetch;
  const calls = [];
  globalThis.fetch = async (input, init) => {
    calls.push({ url: String(input), init });
    return handler(String(input), init || {});
  };
  return {
    calls,
    restore() {
      globalThis.fetch = original;
    },
  };
}

function hydrationSeed() {
  return {
    [`tenant:${TENANT}:company:${COMPANY}:fleet:vehicles:v1`]: JSON.stringify({
      vehicles: [{ vehicle_id: "vh_1", license_plate: "TXABC123" }],
    }),
    [`tenant:${TENANT}:company:${COMPANY}:business_profile:v1`]: JSON.stringify({
      business_profile: {
        companyName: "Wakanda Wotan BVBA",
        legalName: "Wakanda Wotan BVBA",
        vatNumber: "BE0772931038",
        enterpriseNumber: "0772931038",
      },
    }),
    [`tenant:${TENANT}:company:${COMPANY}:drivers:index:v1`]: JSON.stringify({
      drivers: { drv_1: { taxi_driver_card_number: "1234567890" } },
    }),
    [`tenant:${TENANT}:company:${COMPANY}:chiron_connection:v1`]: JSON.stringify({
      schema_version: "chiron_connection_status_v1",
      enabled: true,
      environment: "test",
      production_enabled: false,
      official_submit_enabled: false,
      test_credentials_stored: true,
      last_connection_status: "test_passed",
      testflow_auto_submit_enabled: true,
      testflow_started_at: "2026-08-01T00:00:00.000Z",
    }),
  };
}

function envWithKv(kv, extra = {}) {
  return {
    ADMIN_TOKEN: ADMIN,
    COMPLIANCE_KV: kv,
    BOOKING_KV: kv,
    CHIRON_EXPORT_MODE: "test",
    CHIRON_EXPORT_BASE_URL: ACC_URL,
    CHIRON_CREDENTIALS_ENCRYPTION_KEY: ENCRYPTION_KEY,
    CHIRON_CREDENTIALS_ENCRYPTION_KID: "v1",
    ...extra,
  };
}

async function seedOAuth(kv, env) {
  const plaintext = JSON.stringify({
    schema_version: CHIRON_CREDENTIALS_PAYLOAD_SCHEMA_VERSION,
    auth_scheme: "oauth_client_credentials",
    client_id: "cid",
    client_secret: "csec",
  });
  const encrypted = await encryptChironCredentialBlob(plaintext, env);
  await kv.put(
    buildChironCredentialsKvKey(TENANT, COMPANY, "test"),
    JSON.stringify({
      schema_version: CHIRON_CREDENTIALS_SCHEMA_VERSION,
      tenant_id: TENANT,
      company_id: COMPANY,
      environment: "test",
      auth_scheme: "oauth_client_credentials",
      credential_payload_encrypted: encrypted,
      credential_fingerprint_short: "fpseq",
      masked_identifier: "client_***",
    }),
  );
}

function officialStatusKey(registratie, ritnummer, status) {
  const idem = buildChironOfficialIdempotencyKey(
    { tenant_id: TENANT, company_id: COMPANY },
    registratie,
    ritnummer,
    status,
  );
  return buildChironExportStatusKey(safeSegment(TENANT, ""), safeSegment(COMPANY, ""), idem);
}

// ---------------------------------------------------------------------------
// Sequence truth
// ---------------------------------------------------------------------------
test("H) no batch prior and no official vertrek => sequence_unsafe", () => {
  const validation = validateChironOfficialPayloadDraft(aankomstPayload(), {
    category: "ride_payload",
    officialStatus: "aankomst",
    ritnummer: `${BOOKING}-outbound`,
    batchRitStatuses: new Map(),
  });
  assert.equal(validation.sequence_safe, false);
  assert.ok(validation.warnings.includes("missing_prior_vertrek_or_reservatie_in_batch"));
});

test("C) batch vertrek still satisfies sequence without official status", () => {
  const batch = new Map([[`${BOOKING}-outbound`, new Set(["vertrek"])]]);
  const validation = validateChironOfficialPayloadDraft(aankomstPayload(), {
    category: "ride_payload",
    officialStatus: "aankomst",
    ritnummer: `${BOOKING}-outbound`,
    batchRitStatuses: batch,
  });
  assert.notEqual(validation.sequence_safe, false);
  assert.equal(
    validation.warnings.includes("missing_prior_vertrek_or_reservatie_in_batch"),
    false,
  );
});

test("B+C) official synced vertrek satisfies sequence when batch is empty", () => {
  const validation = validateChironOfficialPayloadDraft(aankomstPayload(), {
    category: "ride_payload",
    officialStatus: "aankomst",
    ritnummer: `${BOOKING}-outbound`,
    batchRitStatuses: new Map(),
    officialVertrekSyncState: "synced",
  });
  assert.notEqual(validation.sequence_safe, false);
  assert.equal(
    validation.warnings.includes("missing_prior_vertrek_or_reservatie_in_batch"),
    false,
  );
});

test("L) departure_confirmed_external also satisfies prior departure", () => {
  assert.equal(_chironOfficialDepartureSatisfiesSequence("synced"), true);
  assert.equal(
    _chironOfficialDepartureSatisfiesSequence(CHIRON_DEPARTURE_CONFIRMED_EXTERNAL),
    true,
  );
  const validation = validateChironOfficialPayloadDraft(aankomstPayload(), {
    category: "ride_payload",
    officialStatus: "aankomst",
    ritnummer: `${BOOKING}-outbound`,
    batchRitStatuses: new Map(),
    officialVertrekSyncState: CHIRON_DEPARTURE_CONFIRMED_EXTERNAL,
  });
  assert.notEqual(validation.sequence_safe, false);
});

test("official pending/failed/blocked vertrek does not satisfy sequence", () => {
  for (const state of ["pending", "failed", "blocked", "waiting_for_departure", ""]) {
    assert.equal(
      _chironOfficialDepartureSatisfiesSequence(state),
      false,
      state,
    );
    const validation = validateChironOfficialPayloadDraft(aankomstPayload(), {
      category: "ride_payload",
      officialStatus: "aankomst",
      ritnummer: `${BOOKING}-outbound`,
      batchRitStatuses: new Map(),
      officialVertrekSyncState: state,
    });
    assert.equal(validation.sequence_safe, false, state);
  }
});

test("A) stop-only draft is sequence_unsafe until official vertrek is synced", async () => {
  const kv = makeKV({ seed: hydrationSeed() });
  const env = envWithKv(kv);
  const stop = rideStop();
  const stopKey = "compliance_event_v1/tenant/t1/company/c1/stop";
  const builtUnsafe = await _chironBuildOfficialDraftForSingleEvent(env, stop, stopKey, {
    preloadedContextEntries: [{ key: stopKey, event: stop }],
  });
  const unsafeDraft = builtUnsafe.exportPayload?.chiron_official_draft;
  assert.equal(unsafeDraft?.status, "aankomst");
  assert.equal(unsafeDraft?.validation?.sequence_safe, false);

  const registratie = unsafeDraft.payload.registratie;
  const ritnummer = unsafeDraft.payload.ritnummer;
  assert.ok(registratie);
  assert.ok(ritnummer);
  await kv.put(
    officialStatusKey(registratie, ritnummer, "vertrek"),
    JSON.stringify({
      schema_version: CHIRON_EXPORT_STATUS_SCHEMA,
      sync_state: "synced",
      official_status: "vertrek",
      official_ritnummer: ritnummer,
      attempt_count: 1,
      external_status_code: 201,
    }),
  );

  const builtSafe = await _chironBuildOfficialDraftForSingleEvent(env, stop, stopKey, {
    preloadedContextEntries: [{ key: stopKey, event: stop }],
  });
  const safeDraft = builtSafe.exportPayload?.chiron_official_draft;
  assert.notEqual(safeDraft?.validation?.sequence_safe, false);
  const ready = _chironOfficialDraftReadyForSubmit({
    officialDraft: safeDraft,
    expectedOfficialStatus: "aankomst",
    effectiveEnvironment: "test",
  });
  assert.equal(ready.acceptable, true);
});

// ---------------------------------------------------------------------------
// Guard recovery
// ---------------------------------------------------------------------------
test("D) never-POSTed blocked+retryable recovers only with currentRebuildAcceptable", () => {
  const blocked = neverPostedBlocked();
  assert.equal(_chironNeverPostedBlockedRecoveryEligible(blocked), true);
  assert.equal(
    _chironEvaluateSubmitDuplicateGuard(blocked).decision,
    "not_retryable",
  );
  assert.deepEqual(
    _chironEvaluateSubmitDuplicateGuard(blocked, Date.now(), {
      currentRebuildAcceptable: true,
    }),
    { decision: "allow", recovered_blocked: true },
  );
});

test("M) blocked that already reached Chiron cannot use recovery", () => {
  const withStatus = neverPostedBlocked({ external_status_code: 400 });
  const withFp = neverPostedBlocked({ outbound_fingerprint: "abc123" });
  const attempted = neverPostedBlocked({ attempt_count: 1 });
  for (const doc of [withStatus, withFp, attempted]) {
    assert.equal(_chironNeverPostedBlockedRecoveryEligible(doc), false);
    assert.equal(
      _chironEvaluateSubmitDuplicateGuard(doc, Date.now(), {
        currentRebuildAcceptable: true,
      }).decision,
      "not_retryable",
    );
  }
});

test("I) verification_required behavior unchanged", () => {
  assert.deepEqual(
    _chironEvaluateSubmitDuplicateGuard({ sync_state: "verification_required" }),
    { decision: "verification_required" },
  );
  assert.deepEqual(
    _chironEvaluateSubmitDuplicateGuard(
      { sync_state: "verification_required", failure_kind: "retryable", attempt_count: 0 },
      Date.now(),
      { currentRebuildAcceptable: true },
    ),
    { decision: "verification_required" },
  );
});

test("J) failed+definitive behavior unchanged", () => {
  assert.deepEqual(
    _chironEvaluateSubmitDuplicateGuard({
      sync_state: "failed",
      failure_kind: "definitive",
    }),
    { decision: "allow" },
  );
  assert.equal(
    _chironEvaluateSubmitDuplicateGuard({
      sync_state: "failed",
      external_status_code: null,
      fouten_count: 0,
    }).decision,
    "not_retryable",
  );
});

test("synced stays already_synced even with recovery options", () => {
  assert.deepEqual(
    _chironEvaluateSubmitDuplicateGuard(
      { sync_state: "synced", attempt_count: 1 },
      Date.now(),
      { currentRebuildAcceptable: true },
    ),
    { decision: "already_synced" },
  );
});

// ---------------------------------------------------------------------------
// Auto-submit recovery + taxi direct
// ---------------------------------------------------------------------------
test("E/F/G) never-POSTed blocked arrival recovers, POSTs once, second submit already_synced", async () => {
  const kv = makeKV({ seed: hydrationSeed() });
  const env = envWithKv(kv);
  await seedOAuth(kv, env);
  const stop = rideStop();
  const stopKey = `compliance_event_v1/tenant/${safeSegment(TENANT, "")}/company/${safeSegment(COMPANY, "")}/2026/08/24/stop184`;
  await kv.put(stopKey, JSON.stringify(stop));

  const probe = await _chironBuildOfficialDraftForSingleEvent(env, stop, stopKey, {
    preloadedContextEntries: [{ key: stopKey, event: stop }],
  });
  const probeDraft = probe.exportPayload?.chiron_official_draft;
  assert.equal(probeDraft?.validation?.sequence_safe, false);
  const registratie = probeDraft.payload.registratie;
  const ritnummer = probeDraft.payload.ritnummer;
  const vertrekKey = officialStatusKey(registratie, ritnummer, "vertrek");
  const aankomstKey = officialStatusKey(registratie, ritnummer, "aankomst");
  await kv.put(
    vertrekKey,
    JSON.stringify({
      schema_version: CHIRON_EXPORT_STATUS_SCHEMA,
      sync_state: "synced",
      official_status: "vertrek",
      official_ritnummer: ritnummer,
      official_idempotency_key: buildChironOfficialIdempotencyKey(
        { tenant_id: TENANT, company_id: COMPANY },
        registratie,
        ritnummer,
        "vertrek",
      ),
      attempt_count: 1,
      external_status_code: 201,
    }),
  );
  await kv.put(
    aankomstKey,
    JSON.stringify({
      ...neverPostedBlocked(),
      official_idempotency_key: buildChironOfficialIdempotencyKey(
        { tenant_id: TENANT, company_id: COMPANY },
        registratie,
        ritnummer,
        "aankomst",
      ),
      tenant_id: TENANT,
      company_id: COMPANY,
    }),
  );

  const stub = installFetchStub((url) => {
    if (String(url).includes("/oauth/token")) {
      return new Response(
        JSON.stringify({
          access_token: "tok",
          token_type: "Bearer",
          expires_in: 3600,
        }),
        {
          status: 200,
          headers: { "content-type": "application/json" },
        },
      );
    }
    return new Response(JSON.stringify({ fouten: [] }), {
      status: 201,
      headers: { "content-type": "application/json" },
    });
  });
  try {
    const first = await _chironAutoSubmitOneEvent(env, stop, stopKey, {
      source: "test",
      preloadedContextEntries: [{ key: stopKey, event: stop }],
    });
    assert.equal(first.ok, true, JSON.stringify(first));
    assert.equal(first.skipped, false);
    assert.equal(first.sync_state, "synced");
    const taxiritPosts = stub.calls.filter((c) => String(c.url).includes("/chiron/taxirit"));
    assert.equal(taxiritPosts.length, 1);
    const stored = JSON.parse(await kv.get(aankomstKey));
    assert.equal(stored.sync_state, "synced");

    const second = await _chironAutoSubmitOneEvent(env, stop, stopKey, {
      source: "test",
      preloadedContextEntries: [{ key: stopKey, event: stop }],
    });
    assert.equal(second.skipped, true);
    assert.ok(
      second.reason === "already_synced" ||
        second.reason === "duplicate_guard_already_synced",
      JSON.stringify(second),
    );
    const taxiritPostsAfter = stub.calls.filter((c) =>
      String(c.url).includes("/chiron/taxirit"),
    );
    assert.equal(taxiritPostsAfter.length, 1, "second submit must not POST again");
  } finally {
    stub.restore();
  }
});

test("H) no prior vertrek anywhere remains blocked and does not POST", async () => {
  const kv = makeKV({ seed: hydrationSeed() });
  const env = envWithKv(kv);
  await seedOAuth(kv, env);
  const stop = rideStop();
  const stopKey = "stop-only";
  const stub = installFetchStub(() => {
    throw new Error("Chiron must not be contacted when sequence is unsafe");
  });
  try {
    const outcome = await _chironAutoSubmitOneEvent(env, stop, stopKey, {
      source: "test",
      preloadedContextEntries: [{ key: stopKey, event: stop }],
    });
    assert.equal(outcome.skipped, true);
    assert.ok(
      outcome.reason === "official_payload_not_ready" ||
        outcome.sync_state === "blocked",
    );
    assert.equal(stub.calls.length, 0);
  } finally {
    stub.restore();
  }
});

test("K) taxi direct arrival still uses in-batch vertrek and extra start stays unpaired", async () => {
  const kv = makeKV({ seed: hydrationSeed() });
  const env = envWithKv(kv);
  const start = taxiDirectStart();
  const stop = taxiDirectStop();
  const extraStart = {
    ...start,
    event_id: "ride_start:T1:C1:extra",
    trip_id: "trip_extra",
  };
  const built = await _chironBuildOfficialDraftForSingleEvent(env, stop, "stop-direct", {
    preloadedContextEntries: [
      { key: "start-direct", event: start },
      { key: "stop-direct", event: stop },
    ],
  });
  const draft = built.exportPayload?.chiron_official_draft;
  assert.equal(draft?.status, "aankomst");
  assert.notEqual(draft?.validation?.sequence_safe, false);
  const extra = _chironDepartureCanonicalDecision(extraStart, [
    { event: start },
    { event: extraStart },
    { event: stop },
  ]);
  assert.equal(extra.allow, false);
  assert.equal(extra.reason, "extra_start_not_canonical_trip");
});
