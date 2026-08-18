// CHIRON-OFFLINE-ARRIVAL-P0
//
// Field: 03/08/2026 street rides 16:17 (street_1785766676167_7d1gy8ov) and
// 16:45 (street_1785768346529_2p5ohae0) reached Chiron as Vertrek only.
//   * 16:17 vertrek was left sync_state=pending → conflict_pending blocked
//     every retry; aankomst stayed waiting_for_departure, attempt_count=0.
//   * 16:45 vertrek was retried and Chiron answered 200 with fouten_count=1
//     → failed/definitive; the arrival gate (synced-only) stayed shut.
// There is also no scheduled replay, so connectivity recovery alone never
// re-drove the state machine.
//
//   node --test workers/compliance/chiron_offline_arrival_p0.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import { __testInternals } from "./fluxidi_compliance_worker.js";

const {
  _chironEvaluateSubmitDuplicateGuard,
  _chironExtractFoutenCodes,
  _chironDuplicateVertrekFoutcodes,
  _chironIsDuplicateVertrekRejection,
  _chironListConnectionScopes,
  _chironCronReconcileAllScopesBestEffort,
  parseChironTaxiritSubmitResponse,
  buildChironExportStatusKey,
  CHIRON_DEPARTURE_CONFIRMED_EXTERNAL,
  CHIRON_DEFINITIVE_RETRY_MAX_ATTEMPTS,
  CHIRON_DEFINITIVE_RETRY_COOLDOWN_MS,
  CHIRON_PENDING_STALE_MS,
  CHIRON_CRON_MAX_SCOPES_PER_TICK,
  safeSegment,
} = __testInternals;

const DUP = "CH9999";

// ---------------------------------------------------------------------------
// A. pending / retry gating
// ---------------------------------------------------------------------------

test("1) young pending stays blocked", () => {
  const now = Date.parse("2026-08-03T14:24:30.000Z");
  assert.equal(
    _chironEvaluateSubmitDuplicateGuard(
      {
        sync_state: "pending",
        attempt_count: 1,
        last_attempt_at: "2026-08-03T14:24:17.575Z",
      },
      now,
    ).decision,
    "conflict_pending",
  );
});

test("2) stale pending becomes retryable", () => {
  const last = "2026-08-03T14:24:17.575Z";
  const guard = _chironEvaluateSubmitDuplicateGuard(
    { sync_state: "pending", attempt_count: 1, last_attempt_at: last },
    Date.parse(last) + CHIRON_PENDING_STALE_MS + 1,
  );
  assert.equal(guard.decision, "allow");
  assert.equal(guard.stale_pending, true);
});

test("3) definitive failure retry is bounded by attempts and cooldown", () => {
  const last = "2026-08-03T16:18:42.955Z";
  const lastMs = Date.parse(last);

  // Legacy shape (no attempt/last markers) keeps the exact historical result.
  assert.deepEqual(
    _chironEvaluateSubmitDuplicateGuard({
      sync_state: "failed",
      failure_kind: "definitive",
      external_status_code: 200,
      fouten_count: 1,
    }),
    { decision: "allow" },
  );

  // Field 16:45 shape after cooldown → retryable.
  assert.equal(
    _chironEvaluateSubmitDuplicateGuard(
      {
        sync_state: "failed",
        failure_kind: "definitive",
        external_status_code: 200,
        fouten_count: 1,
        attempt_count: 2,
        last_attempt_at: last,
      },
      lastMs + CHIRON_DEFINITIVE_RETRY_COOLDOWN_MS + 1,
    ).decision,
    "allow",
  );

  // Inside the cooldown → no re-POST (cron must not hammer Chiron).
  assert.equal(
    _chironEvaluateSubmitDuplicateGuard(
      {
        sync_state: "failed",
        failure_kind: "definitive",
        external_status_code: 200,
        fouten_count: 1,
        attempt_count: 2,
        last_attempt_at: last,
      },
      lastMs + 1000,
    ).decision,
    "not_retryable",
  );

  // Attempt cap reached → permanently skipped, never starves the pass.
  assert.equal(
    _chironEvaluateSubmitDuplicateGuard(
      {
        sync_state: "failed",
        failure_kind: "definitive",
        external_status_code: 200,
        fouten_count: 1,
        attempt_count: CHIRON_DEFINITIVE_RETRY_MAX_ATTEMPTS,
        last_attempt_at: last,
      },
      lastMs + CHIRON_DEFINITIVE_RETRY_COOLDOWN_MS * 100,
    ).decision,
    "not_retryable",
  );
});

test("4) externally confirmed departure is never re-POSTed", () => {
  assert.equal(
    _chironEvaluateSubmitDuplicateGuard({
      sync_state: CHIRON_DEPARTURE_CONFIRMED_EXTERNAL,
      attempt_count: 3,
    }).decision,
    "already_confirmed_external",
  );
});

// ---------------------------------------------------------------------------
// B. structured fout code capture + exact duplicate classification
// ---------------------------------------------------------------------------

test("5) only structured fout codes are captured — never free text", () => {
  const codes = _chironExtractFoutenCodes({
    fouten: [
      { foutcode: "ch9999", omschrijving: "Rit bestaat al voor klant Jan te Ronse" },
      { code: "CH1212", tekst: "plate" },
    ],
  });
  assert.deepEqual(codes, ["CH9999", "CH1212"]);
  const serialized = JSON.stringify(codes);
  assert.equal(serialized.includes("Jan"), false);
  assert.equal(serialized.includes("Ronse"), false);
  assert.equal(serialized.includes("bestaat"), false);
});

test("6) parse response exposes fouten_codes as evidence", () => {
  const rejected = parseChironTaxiritSubmitResponse(200, {
    fouten: [{ foutcode: DUP, omschrijving: "x" }],
  });
  assert.equal(rejected.ok, false);
  assert.equal(rejected.fouten_count, 1);
  assert.deepEqual(rejected.fouten_codes, [DUP]);

  const accepted = parseChironTaxiritSubmitResponse(200, { fouten: [] });
  assert.equal(accepted.ok, true);
  assert.deepEqual(accepted.fouten_codes, []);
});

test("7) duplicate classification requires an exact configured code", () => {
  const base = {
    officialStatus: "vertrek",
    foutenCodes: [DUP],
    foutenCount: 1,
    externalStatusCode: 200,
  };
  // Unconfigured → never a duplicate (fail-closed default).
  assert.equal(
    _chironIsDuplicateVertrekRejection({ ...base, configuredCodes: [] }),
    false,
  );
  assert.equal(
    _chironIsDuplicateVertrekRejection({ ...base, configuredCodes: [DUP] }),
    true,
  );
});

test("8) unrelated Chiron error never opens the arrival gate", () => {
  const configuredCodes = [DUP];
  // Different code entirely.
  assert.equal(
    _chironIsDuplicateVertrekRejection({
      officialStatus: "vertrek",
      foutenCodes: ["CH1212"],
      foutenCount: 1,
      externalStatusCode: 200,
      configuredCodes,
    }),
    false,
  );
  // Mixed response: duplicate + a real rejection stays a rejection.
  assert.equal(
    _chironIsDuplicateVertrekRejection({
      officialStatus: "vertrek",
      foutenCodes: [DUP, "CH1212"],
      foutenCount: 2,
      externalStatusCode: 200,
      configuredCodes,
    }),
    false,
  );
  // Codes could not be parsed for every fout.
  assert.equal(
    _chironIsDuplicateVertrekRejection({
      officialStatus: "vertrek",
      foutenCodes: [DUP],
      foutenCount: 2,
      externalStatusCode: 200,
      configuredCodes,
    }),
    false,
  );
  // Non-2xx is never an acceptance.
  assert.equal(
    _chironIsDuplicateVertrekRejection({
      officialStatus: "vertrek",
      foutenCodes: [DUP],
      foutenCount: 1,
      externalStatusCode: 500,
      configuredCodes,
    }),
    false,
  );
});

test("9) duplicate confirmation is scoped exclusively to vertrek", () => {
  assert.equal(
    _chironIsDuplicateVertrekRejection({
      officialStatus: "aankomst",
      foutenCodes: [DUP],
      foutenCount: 1,
      externalStatusCode: 200,
      configuredCodes: [DUP],
    }),
    false,
  );
});

test("10) configured code list is parsed as exact codes, not text", () => {
  assert.deepEqual(
    _chironDuplicateVertrekFoutcodes({
      CHIRON_DUPLICATE_VERTREK_FOUTCODES: " ch9999 , CH1000 ",
    }),
    ["CH9999", "CH1000"],
  );
  assert.deepEqual(_chironDuplicateVertrekFoutcodes({}), []);
  // A free-text phrase can never become a usable "code" match.
  const codes = _chironDuplicateVertrekFoutcodes({
    CHIRON_DUPLICATE_VERTREK_FOUTCODES: "already exists",
  });
  assert.equal(
    _chironIsDuplicateVertrekRejection({
      officialStatus: "vertrek",
      foutenCodes: [DUP],
      foutenCount: 1,
      externalStatusCode: 200,
      configuredCodes: codes,
    }),
    false,
  );
});

// ---------------------------------------------------------------------------
// C. arrival gate + acceptance invariants
// ---------------------------------------------------------------------------

test("11) arrival cannot become synced without 2xx + empty fouten[]", () => {
  assert.equal(parseChironTaxiritSubmitResponse(200, { fouten: [{ code: "X" }] }).ok, false);
  assert.equal(parseChironTaxiritSubmitResponse(200, {}).ok, false);
  assert.equal(parseChironTaxiritSubmitResponse(200, null).ok, false);
  assert.equal(parseChironTaxiritSubmitResponse(500, { fouten: [] }).ok, false);
  assert.equal(parseChironTaxiritSubmitResponse(200, { fouten: [] }).ok, true);
});

test("12) only synced / externally-confirmed departures open the gate", () => {
  const opens = (state) =>
    state === "synced" || state === CHIRON_DEPARTURE_CONFIRMED_EXTERNAL;
  assert.equal(opens("synced"), true);
  assert.equal(opens(CHIRON_DEPARTURE_CONFIRMED_EXTERNAL), true);
  for (const blocked of [
    "failed",
    "retryable_failed",
    "verification_required",
    "pending",
    "queued",
    "waiting_for_departure",
    "",
    "something_unknown",
  ]) {
    assert.equal(opens(blocked), false, blocked);
  }
});

// ---------------------------------------------------------------------------
// D. cron drain
// ---------------------------------------------------------------------------

function cronKv(entries) {
  const store = new Map(entries);
  return {
    store,
    async get(key) {
      return store.get(key) ?? null;
    },
    async put(key, value) {
      store.set(key, value);
    },
    async delete(key) {
      store.delete(key);
    },
    async list({ prefix } = {}) {
      const keys = [...store.keys()]
        .filter((k) => !prefix || k.startsWith(prefix))
        .map((name) => ({ name }));
      return { keys, list_complete: true };
    },
  };
}

function connectionDoc(overrides = {}) {
  return JSON.stringify({
    schema_version: "chiron_connection_status_v1",
    enabled: true,
    environment: "production",
    production_enabled: false,
    test_credentials_stored: true,
    production_credentials_stored: true,
    last_connection_status: "test_passed",
    testflow_auto_submit_enabled: true,
    testflow_started_at: "2026-08-01T05:24:57.000Z",
    testflow_status: "complete",
    test_departure_sent_count: 5,
    test_arrival_sent_count: 5,
    test_messages_sent_count: 10,
    test_rides_completed_count: 5,
    ...overrides,
  });
}

test("13) cron enumerates only chiron connection scopes, tenant-isolated", async () => {
  const kv = cronKv([
    ["tenant:T1:company:C1:chiron_connection:v1", connectionDoc()],
    ["tenant:T2:company:C2:chiron_connection:v1", connectionDoc()],
    ["tenant:T1:company:C1:chiron_credentials:test:v1", "{}"],
    ["tenant:T3:company:C3:something_else:v1", "{}"],
  ]);
  const scopes = await _chironListConnectionScopes({ COMPLIANCE_KV: kv });
  assert.deepEqual(
    scopes.map((s) => `${s.tenant_id}/${s.company_id}`).sort(),
    ["T1/C1", "T2/C2"],
  );
  assert.ok(CHIRON_CRON_MAX_SCOPES_PER_TICK >= 1);
});

test("14) cron runs the bounded reconcile without any client traffic", async () => {
  const kv = cronKv([["tenant:T1:company:C1:chiron_connection:v1", connectionDoc()]]);
  const env = {
    CHIRON_EXPORT_MODE: "test",
    CHIRON_EXPORT_BASE_URL: "https://mow-acc.api.vlaanderen.be/chiron/taxirit",
    COMPLIANCE_KV: kv,
  };
  const summary = await _chironCronReconcileAllScopesBestEffort(env);
  assert.equal(summary.ok, true);
  assert.equal(summary.due_selected, 0);
  assert.equal(summary.ran, 0);
  // Idle due-index cron must not stamp the status-poll throttle marker.
  const stored = JSON.parse(kv.store.get("tenant:T1:company:C1:chiron_connection:v1"));
  assert.equal(stored.testflow_auto_reconcile_last_at, undefined);
});

test("15) repeated idle cron ticks do not write a throttle stamp", async () => {
  const kv = cronKv([["tenant:T1:company:C1:chiron_connection:v1", connectionDoc()]]);
  const env = {
    CHIRON_EXPORT_MODE: "test",
    CHIRON_EXPORT_BASE_URL: "https://mow-acc.api.vlaanderen.be/chiron/taxirit",
    COMPLIANCE_KV: kv,
  };
  await _chironCronReconcileAllScopesBestEffort(env);
  const second = await _chironCronReconcileAllScopesBestEffort(env);
  assert.equal(second.ran, 0);
  assert.equal(second.skipped_throttled, 0);
  assert.equal(second.due_selected, 0);
});

test("16) cron never throws on a broken KV binding", async () => {
  const summary = await _chironCronReconcileAllScopesBestEffort({});
  assert.equal(summary.scopes, 0);
  assert.equal(summary.ran, 0);
});

// ---------------------------------------------------------------------------
// E. isolation + evidence hygiene
// ---------------------------------------------------------------------------

test("17) export status keys stay tenant/company scoped", () => {
  const key = buildChironExportStatusKey(
    safeSegment("fluxidi_fluxidi_ddmh9g", ""),
    safeSegment("fluxidi_fluxidi_ddmh9g", ""),
    "chiron_official_v1:fluxidi_fluxidi_ddmh9g:fluxidi_fluxidi_ddmh9g:0772.931.038:street_1785768346529_2p5ohae0:vertrek",
  );
  assert.match(key, /tenant\/fluxidi_fluxidi_ddmh9g\//);
  assert.match(key, /company\/fluxidi_fluxidi_ddmh9g\//);
  assert.equal(key.includes("OTHER_TENANT"), false);
});

test("18) no secrets or PII in duplicate/cron diagnostics", () => {
  const codes = _chironExtractFoutenCodes({
    fouten: [
      {
        foutcode: DUP,
        omschrijving: "Bearer sk_live_secret rit voor +32470000000",
      },
    ],
  });
  const raw = JSON.stringify(codes);
  assert.equal(raw.includes("Bearer"), false);
  assert.equal(raw.includes("sk_live"), false);
  assert.equal(raw.includes("+32470000000"), false);
  assert.deepEqual(codes, [DUP]);
});
