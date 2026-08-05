// RELEASE-P0-FINAL-CHIRON-STORAGE-ACK-VERIFICATION-2026-07-31 — end-to-end
// verification test. Wires the *real* tracking worker and the *real*
// compliance worker together (via a KV that can inject targeted PUT
// failures) so the exact chain
//
//   tracking → emitComplianceEventBestEffort → compliance handleAppend →
//   KV.put throws → compliance HTTP 500 → tracking derives PENDING with
//   coarse error code — never APPLIED, never silently swallowed.
//
// The four required guarantees are exercised as a single black-box flow so
// no reader has to compose two disjoint suites in their head.
//
// Run:
//   node --test workers/tracking/planned_chiron_storage_ack_end_to_end.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import trackingWorker from "./fluxidi_tracking_api_worker_V2_1_with_route_index.js";
import complianceWorker from "../compliance/fluxidi_compliance_worker.js";

const ADMIN = "test-admin-token";
const COMPLIANCE_ADMIN = "compliance-admin-token";
const SCOPE = { tenant_id: "T1", company_id: "C1" };
const BOOKING_ID = "planned_ack_verify";
const TRIP_ID = `planned_${BOOKING_ID}`;
const TRIP_KEY = `tenant:T1:company:C1:trip:${TRIP_ID}`;

// ---- Tracking-side KV (in-memory) ---------------------------------------
function makeTrackingKV(seed = {}) {
  const store = new Map(Object.entries(seed));
  return {
    store,
    async get(key) {
      return store.has(key) ? store.get(key) : null;
    },
    async put(key, val) {
      store.set(key, val);
    },
    async delete(key) {
      store.delete(key);
    },
    async list() {
      return {
        keys: [...store.keys()].map((name) => ({ name })),
        list_complete: true,
      };
    },
  };
}

// ---- Compliance-side KV with per-put failure injection -------------------
// `putFilter(key, index)` returns a truthy string to force the Nth put to
// throw with that message; otherwise the put succeeds.
function makeComplianceKV({ seed = {}, putFilter = null } = {}) {
  const store = new Map(Object.entries(seed));
  let putIndex = 0;
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
      putIndex += 1;
      if (putFilter) {
        const failReason = putFilter(key, putIndex);
        if (failReason) throw new Error(failReason);
      }
      store.set(key, val);
    },
    async delete(key) {
      store.delete(key);
    },
    async list({ prefix = "", limit = 1000, cursor } = {}) {
      const names = [...store.keys()].filter((k) => k.startsWith(prefix)).sort();
      const start = cursor ? Number(cursor) : 0;
      const slice = names.slice(start, start + limit);
      const next = start + slice.length;
      const done = next >= names.length;
      return {
        keys: slice.map((name) => ({ name })),
        list_complete: done,
        cursor: done ? undefined : String(next),
      };
    },
  };
}

// Service-binding stub that routes the tracking worker's compliance emit
// to the REAL compliance worker (with the specified compliance-side KV).
function makeComplianceServiceBinding(complianceKV) {
  return {
    async fetch(req) {
      return complianceWorker.fetch(
        req,
        { ADMIN_TOKEN: COMPLIANCE_ADMIN, COMPLIANCE_KV: complianceKV },
        {},
      );
    },
  };
}

function bookingApiStub({ fare = 15.0 } = {}) {
  return {
    calls: [],
    async fetch(request) {
      const url = new URL(request.url);
      const body = await request.json().catch(() => ({}));
      this.calls.push({ path: url.pathname, body });
      if (url.pathname.includes("canonical-fare-for-planned-stop")) {
        return new Response(
          JSON.stringify({
            ok: true,
            booking_id: body.booking_id,
            booking: { booking_id: body.booking_id, price_incl_vat: fare },
          }),
          { status: 200 },
        );
      }
      return new Response(JSON.stringify({ ok: true }), { status: 200 });
    },
  };
}

function makeCtx() {
  const pending = [];
  return {
    waitUntil(p) {
      pending.push(Promise.resolve(p).catch(() => {}));
    },
    async flush() {
      while (pending.length) await pending.shift();
    },
  };
}

function trackingEnv({ trackingKV, complianceKV }) {
  return {
    ADMIN_TOKEN: ADMIN,
    COMPLIANCE_API_URL: "https://compliance.internal",
    COMPLIANCE_ADMIN_TOKEN: COMPLIANCE_ADMIN,
    FLUXIDI_TRACKING: trackingKV,
    COMPLIANCE_WORKER: makeComplianceServiceBinding(complianceKV),
    BOOKING_API: bookingApiStub(),
  };
}

function recordPlannedStopReq(body) {
  return new Request("https://track.internal/trip/record-planned-stop", {
    method: "POST",
    headers: { "content-type": "application/json", "x-admin-token": ADMIN },
    body: JSON.stringify(body),
  });
}

function reconcilePlannedStopReq(body) {
  return new Request("https://track.internal/trip/reconcile-planned-stop", {
    method: "POST",
    headers: { "content-type": "application/json", "x-admin-token": ADMIN },
    body: JSON.stringify(body),
  });
}

function plannedStopBody(over = {}) {
  return {
    ...SCOPE,
    booking_id: BOOKING_ID,
    driver_id: "D1",
    vehicle_id: "V1",
    km_total: 5.5,
    wait_seconds_total: 20,
    total_eur: 15.0,
    currency: "EUR",
    ...over,
  };
}

// ---------------------------------------------------------------------------
// GUARANTEE 1 — canonical KV PUT failure in the compliance worker MUST NOT
// produce HTTP 2xx and MUST NOT be reported as ok:true.  The tracking worker
// receives that HTTP non-2xx and keeps the trip PENDING with a coarse error
// code.
// ---------------------------------------------------------------------------
test("canonical KV.put throws → compliance HTTP 500 → tracking trip stays PENDING", async () => {
  const trackingKV = makeTrackingKV();
  // Fail the very first compliance-side KV put (the canonical write).
  const complianceKV = makeComplianceKV({
    putFilter: (_key, idx) => (idx === 1 ? "kv_canonical_put_failure" : null),
  });
  const env = trackingEnv({ trackingKV, complianceKV });
  const ctx = makeCtx();

  const res = await trackingWorker.fetch(
    recordPlannedStopReq(plannedStopBody()),
    env,
    ctx,
  );
  const body = await res.json();

  // The stop UX itself succeeds — Chiron durability is orthogonal.
  assert.equal(res.status, 200);
  assert.equal(body.ok, true);
  assert.equal(body.status, "stopped");

  // Await the fire-and-forget emit.
  await ctx.flush();

  // The compliance worker MUST NOT have persisted any canonical body: the
  // partial-write window is closed.
  const canonicalKeys = [...complianceKV.store.keys()].filter((k) =>
    k.startsWith("compliance_event_canonical_v1/tenant/t1/company/c1/eid/"),
  );
  assert.equal(
    canonicalKeys.length,
    0,
    "canonical body must NOT be present when canonical put threw",
  );
  const dateKeys = [...complianceKV.store.keys()].filter((k) =>
    k.startsWith("compliance_event_v1/tenant/t1/company/c1/"),
  );
  assert.equal(
    dateKeys.length,
    0,
    "date-indexed body must also NOT be present (canonical is written first)",
  );

  // The tracking worker MUST record the emit as PENDING with the coarse
  // error code derived from the compliance worker's HTTP 500 response.
  const stored = JSON.parse(trackingKV.store.get(TRIP_KEY));
  assert.equal(stored.status, "stopped");
  assert.equal(
    stored.compliance_emit_state,
    "pending",
    "tracking MUST NOT report APPLIED when compliance failed",
  );
  assert.equal(
    stored.compliance_emit_last_error_code,
    "http_500",
    "error code MUST reflect the compliance worker's HTTP 500 response",
  );
  assert.equal(
    stored.compliance_emit_event_id,
    `ride_stop:T1:C1:${TRIP_ID}`,
    "deterministic event_id must be persisted so retries reuse it",
  );
});

// ---------------------------------------------------------------------------
// GUARANTEE 2 — date-index KV PUT failure AFTER a successful canonical PUT
// MUST NOT produce a silent applied.  Compliance returns HTTP 500 for the
// failed put; tracking stays PENDING.  A subsequent retry hits the recovery
// branch (canonical present → date entry rebuilt) and only then flips to
// APPLIED.
// ---------------------------------------------------------------------------
test("date-index KV.put throws after canonical ok → no silent applied; retry recovers and flips APPLIED", async () => {
  const trackingKV = makeTrackingKV();
  // Fail the SECOND compliance-side put (the date-indexed write). Canonical
  // put (idx=1) succeeds so canonical is orphaned mid-request.
  const complianceKV = makeComplianceKV({
    putFilter: (_key, idx) => (idx === 2 ? "kv_date_put_failure" : null),
  });
  const env = trackingEnv({ trackingKV, complianceKV });
  const ctx = makeCtx();

  const res = await trackingWorker.fetch(
    recordPlannedStopReq(plannedStopBody()),
    env,
    ctx,
  );
  const body = await res.json();
  assert.equal(res.status, 200);
  assert.equal(body.status, "stopped");
  await ctx.flush();

  // Compliance worker state after the partial failure:
  //   canonical present, date-index absent.
  const canonicalKeys = [...complianceKV.store.keys()].filter((k) =>
    k.startsWith("compliance_event_canonical_v1/tenant/t1/company/c1/eid/"),
  );
  const dateKeys = [...complianceKV.store.keys()].filter((k) =>
    k.startsWith("compliance_event_v1/tenant/t1/company/c1/"),
  );
  assert.equal(canonicalKeys.length, 1, "canonical persisted before date failure");
  assert.equal(dateKeys.length, 0, "date entry absent — partial write");

  // Tracking MUST NOT record APPLIED — the compliance worker returned HTTP
  // 500 because the date PUT threw uncaught.
  const stored = JSON.parse(trackingKV.store.get(TRIP_KEY));
  assert.equal(
    stored.compliance_emit_state,
    "pending",
    "tracking MUST stay PENDING when compliance partial-write returned HTTP 500",
  );
  assert.equal(stored.compliance_emit_last_error_code, "http_500");
  assert.equal(stored.compliance_emit_attempt_count, 1);

  // Retry via /trip/reconcile-planned-stop against a healthy KV (no failure
  // injector). Same trip_id → same deterministic event_id → recovery path in
  // the compliance worker recreates the missing date entry and returns
  // deduplicated=true recovered=true (HTTP 200 with ok:true).
  const healthyComplianceKV = makeComplianceKV({
    seed: Object.fromEntries(complianceKV.store.entries()),
  });
  const retryEnv = trackingEnv({
    trackingKV,
    complianceKV: healthyComplianceKV,
  });
  const retryRes = await trackingWorker.fetch(
    reconcilePlannedStopReq({ ...SCOPE, trip_id: TRIP_ID }),
    retryEnv,
    {},
  );
  const retryBody = await retryRes.json();
  assert.equal(retryRes.status, 200);
  assert.equal(retryBody.ok, true);
  assert.equal(retryBody.reconciled, true);
  assert.equal(retryBody.compliance_emit_state, "applied");

  // Compliance now has both artefacts.
  const dateKeysAfter = [...healthyComplianceKV.store.keys()].filter((k) =>
    k.startsWith("compliance_event_v1/tenant/t1/company/c1/"),
  );
  const canonicalKeysAfter = [...healthyComplianceKV.store.keys()].filter((k) =>
    k.startsWith("compliance_event_canonical_v1/tenant/t1/company/c1/eid/"),
  );
  assert.equal(canonicalKeysAfter.length, 1);
  assert.equal(dateKeysAfter.length, 1, "date-index rebuilt from canonical body");

  const storedAfter = JSON.parse(trackingKV.store.get(TRIP_KEY));
  assert.equal(storedAfter.compliance_emit_state, "applied");
  assert.equal(storedAfter.compliance_emit_last_error_code, null);
  assert.equal(storedAfter.compliance_emit_attempt_count, 2);
});

// ---------------------------------------------------------------------------
// GUARANTEE 3 — a subsequent retry after a full-failure attempt (canonical
// never persisted) MUST persist BOTH canonical and date entry AND flip
// tracking to APPLIED.
// ---------------------------------------------------------------------------
test("retry after canonical failure recovers cleanly → tracking APPLIED", async () => {
  const trackingKV = makeTrackingKV();
  const failingComplianceKV = makeComplianceKV({
    putFilter: (_key, idx) => (idx === 1 ? "kv_canonical_put_failure" : null),
  });
  const env = trackingEnv({ trackingKV, complianceKV: failingComplianceKV });
  const ctx = makeCtx();

  await trackingWorker.fetch(recordPlannedStopReq(plannedStopBody()), env, ctx);
  await ctx.flush();
  // Sanity: tracking is PENDING.
  assert.equal(
    JSON.parse(trackingKV.store.get(TRIP_KEY)).compliance_emit_state,
    "pending",
  );

  // Retry against a healthy compliance-side KV.
  const healthyComplianceKV = makeComplianceKV();
  const retryEnv = trackingEnv({ trackingKV, complianceKV: healthyComplianceKV });
  const retryRes = await trackingWorker.fetch(
    reconcilePlannedStopReq({ ...SCOPE, trip_id: TRIP_ID }),
    retryEnv,
    {},
  );
  const retryBody = await retryRes.json();
  assert.equal(retryRes.status, 200);
  assert.equal(retryBody.reconciled, true);
  assert.equal(retryBody.compliance_emit_state, "applied");

  const canonicalKeys = [...healthyComplianceKV.store.keys()].filter((k) =>
    k.startsWith("compliance_event_canonical_v1/tenant/t1/company/c1/eid/"),
  );
  const dateKeys = [...healthyComplianceKV.store.keys()].filter((k) =>
    k.startsWith("compliance_event_v1/tenant/t1/company/c1/"),
  );
  assert.equal(canonicalKeys.length, 1, "canonical persisted on retry");
  assert.equal(dateKeys.length, 1, "date entry persisted on retry");

  const storedAfter = JSON.parse(trackingKV.store.get(TRIP_KEY));
  assert.equal(storedAfter.compliance_emit_state, "applied");
  assert.equal(storedAfter.compliance_emit_attempt_count, 2);
});

// ---------------------------------------------------------------------------
// GUARANTEE 4 — a successful dedup-hit REQUIRES the canonical body to
// actually exist.  Verified end-to-end: after a canonical-only failed
// request there is NO ghost pointer that would let a later append claim
// deduplicated=true without a body.
// ---------------------------------------------------------------------------
test("successful dedup-hit requires canonical body — retry after canonical failure never returns dedup", async () => {
  const trackingKV = makeTrackingKV();
  const failingKV = makeComplianceKV({
    putFilter: (_key, idx) => (idx === 1 ? "kv_canonical_put_failure" : null),
  });
  const env = trackingEnv({ trackingKV, complianceKV: failingKV });
  const ctx = makeCtx();

  await trackingWorker.fetch(recordPlannedStopReq(plannedStopBody()), env, ctx);
  await ctx.flush();

  // Now issue a direct compliance append with the SAME event_id and a
  // healthy KV: since the canonical body never persisted, the compliance
  // worker MUST NOT report dedup — it MUST write fresh.
  const complianceKV = makeComplianceKV({
    // Seed with whatever the failing KV managed to persist (nothing for the
    // canonical-fail case; but this simulates the "same compliance KV" case
    // where the earlier attempt left partial state).
    seed: Object.fromEntries(failingKV.store.entries()),
  });
  const stored = JSON.parse(trackingKV.store.get(TRIP_KEY));
  const eventBody = {
    ...SCOPE,
    event_type: "ride_stop",
    event_id: stored.compliance_emit_event_id, // reuse deterministic id
    booking_id: BOOKING_ID,
    trip_id: TRIP_ID,
    ride_type: "planned",
    lifecycle_status: "stopped",
    created_at_utc: "2026-07-31T09:00:00.000Z",
  };
  const appendRes = await complianceWorker.fetch(
    new Request("https://compliance.internal/compliance/events/append", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-admin-token": COMPLIANCE_ADMIN,
      },
      body: JSON.stringify(eventBody),
    }),
    { ADMIN_TOKEN: COMPLIANCE_ADMIN, COMPLIANCE_KV: complianceKV },
    {},
  );
  const appendBody = await appendRes.json();
  assert.equal(appendRes.status, 200);
  assert.equal(appendBody.ok, true);
  assert.equal(
    appendBody.deduplicated,
    false,
    "MUST NOT report deduplicated=true when canonical body is missing",
  );
  const canonicalKeys = [...complianceKV.store.keys()].filter((k) =>
    k.startsWith("compliance_event_canonical_v1/tenant/t1/company/c1/eid/"),
  );
  const dateKeys = [...complianceKV.store.keys()].filter((k) =>
    k.startsWith("compliance_event_v1/tenant/t1/company/c1/"),
  );
  assert.equal(canonicalKeys.length, 1);
  assert.equal(dateKeys.length, 1);
});

// ---------------------------------------------------------------------------
// GUARANTEE 5 — RELEASE-P0-FIX-CHIRON-RECOVERY-INDEX-FALSE-ACK-2026-07-31
//
// Bug: when canonical exists but the date-index is missing, the recovery
// branch of the compliance worker used to swallow a date-index KV.put
// failure and still return HTTP 200 with {ok:true, deduplicated:true,
// recovered:false}. Tracking derived APPLIED from that ok:true, but the
// dashboard could never see the event (date-index still missing) and no
// retry ever followed → false ACK.
//
// Contract after fix:
//   1. Recovery date-index KV.put failure MUST propagate (no swallow).
//   2. Compliance MUST return non-2xx (HTTP 500 via top-level catch).
//   3. Tracking MUST stay PENDING with http_500 error code.
//   4. Dashboard MUST show ZERO copies of the event while recovery has not
//      completed.
//   5. A subsequent retry against a healthy KV MUST succeed with
//      deduplicated:true recovered:true, tracking flips to APPLIED, and
//      the dashboard shows EXACTLY one event.
// ---------------------------------------------------------------------------
test(
  "recovery date-index KV.put throws → compliance non-2xx → tracking PENDING → healthy retry flips APPLIED",
  async () => {
    const trackingKV = makeTrackingKV();

    // ------------------------------------------------------------------
    // Step 1 — create the partial-write state (canonical present, date
    // entry missing). This mirrors GUARANTEE 2's setup so we begin from a
    // realistic post-partial-failure server state.
    // ------------------------------------------------------------------
    const initialComplianceKV = makeComplianceKV({
      putFilter: (_key, idx) => (idx === 2 ? "kv_date_put_failure" : null),
    });
    const initialEnv = trackingEnv({
      trackingKV,
      complianceKV: initialComplianceKV,
    });
    const initialCtx = makeCtx();
    await trackingWorker.fetch(
      recordPlannedStopReq(plannedStopBody()),
      initialEnv,
      initialCtx,
    );
    await initialCtx.flush();

    const canonicalAfterInitial = [...initialComplianceKV.store.keys()].filter(
      (k) => k.startsWith("compliance_event_canonical_v1/tenant/t1/company/c1/eid/"),
    );
    const dateAfterInitial = [...initialComplianceKV.store.keys()].filter((k) =>
      k.startsWith("compliance_event_v1/tenant/t1/company/c1/"),
    );
    assert.equal(canonicalAfterInitial.length, 1, "canonical persisted");
    assert.equal(dateAfterInitial.length, 0, "date entry absent (partial)");
    assert.equal(
      JSON.parse(trackingKV.store.get(TRIP_KEY)).compliance_emit_state,
      "pending",
      "tracking PENDING after initial partial failure",
    );

    // ------------------------------------------------------------------
    // Step 2 — RETRY with a compliance KV that ALSO fails the recovery
    // date-index put. This is the exact release-blocker scenario.
    //   * canonical exists → recovery branch runs
    //   * date-index put throws
    //   * old (buggy) behavior: HTTP 200 {ok:true, recovered:false} —
    //     tracking wrongly APPLIED, dashboard invisible.
    //   * new behavior: put throws → top-level catch → HTTP 500 → tracking
    //     stays PENDING → next retry will try again.
    // ------------------------------------------------------------------
    const failingRecoveryKV = makeComplianceKV({
      seed: Object.fromEntries(initialComplianceKV.store.entries()),
      // Very next put (the recovery date-index write) must throw.
      putFilter: (_key, idx) => (idx === 1 ? "kv_recovery_date_put_failure" : null),
    });
    const failingRecoveryEnv = trackingEnv({
      trackingKV,
      complianceKV: failingRecoveryKV,
    });
    const failingRetryRes = await trackingWorker.fetch(
      reconcilePlannedStopReq({ ...SCOPE, trip_id: TRIP_ID }),
      failingRecoveryEnv,
      {},
    );
    const failingRetryBody = await failingRetryRes.json();

    // Direct compliance response was non-2xx (surfaced as pending state).
    // Tracking's reconcile endpoint returns HTTP 200 but MUST report the
    // pending state and MUST NOT report reconciled=true.
    assert.equal(failingRetryRes.status, 200);
    assert.equal(
      failingRetryBody.ok,
      false,
      "reconcile MUST NOT report ok:true when compliance recovery failed",
    );
    assert.equal(
      failingRetryBody.compliance_emit_state,
      "pending",
      "recovery-put failure MUST leave tracking PENDING (no false APPLIED)",
    );
    assert.equal(
      failingRetryBody.reconciled,
      false,
      "reconcile MUST NOT claim success when compliance recovery failed",
    );
    assert.equal(
      failingRetryBody.reason,
      "http_500",
      "reason MUST reflect the compliance worker's HTTP 500 response",
    );

    // Storage state after the failing recovery: canonical still there,
    // date entry still absent, NO ghost row.
    const canonicalAfterFailingRetry = [
      ...failingRecoveryKV.store.keys(),
    ].filter((k) =>
      k.startsWith("compliance_event_canonical_v1/tenant/t1/company/c1/eid/"),
    );
    const dateAfterFailingRetry = [...failingRecoveryKV.store.keys()].filter(
      (k) => k.startsWith("compliance_event_v1/tenant/t1/company/c1/"),
    );
    assert.equal(canonicalAfterFailingRetry.length, 1);
    assert.equal(
      dateAfterFailingRetry.length,
      0,
      "date entry MUST remain absent when recovery put failed",
    );

    // Dashboard MUST see ZERO copies of the event: without a date-index
    // entry the recent-list surface cannot return this event.
    const failingListRes = await complianceWorker.fetch(
      new Request(
        "https://compliance.internal/compliance/events/recent?tenant_id=T1&company_id=C1&limit=50",
        { method: "GET", headers: { "x-admin-token": COMPLIANCE_ADMIN } },
      ),
      { ADMIN_TOKEN: COMPLIANCE_ADMIN, COMPLIANCE_KV: failingRecoveryKV },
      {},
    );
    const failingListBody = await failingListRes.json();
    const failingRows = (failingListBody.events || []).filter(
      (e) => e.event_id === `ride_stop:T1:C1:${TRIP_ID}`,
    );
    assert.equal(
      failingRows.length,
      0,
      "dashboard MUST show 0 rows while recovery has not completed",
    );

    // Tracking state after failing retry: still PENDING, attempt count
    // incremented by 1 (2 in total: initial + failing retry).
    const trackingAfterFailingRetry = JSON.parse(
      trackingKV.store.get(TRIP_KEY),
    );
    assert.equal(trackingAfterFailingRetry.compliance_emit_state, "pending");
    assert.equal(trackingAfterFailingRetry.compliance_emit_last_error_code, "http_500");
    assert.equal(trackingAfterFailingRetry.compliance_emit_attempt_count, 2);

    // ------------------------------------------------------------------
    // Step 3 — HEALTHY retry: the recovery path now succeeds. Compliance
    // returns HTTP 200 {deduplicated:true, recovered:true}. Tracking
    // flips to APPLIED, and the dashboard shows exactly one row.
    // ------------------------------------------------------------------
    const healthyRecoveryKV = makeComplianceKV({
      seed: Object.fromEntries(failingRecoveryKV.store.entries()),
    });
    const healthyEnv = trackingEnv({
      trackingKV,
      complianceKV: healthyRecoveryKV,
    });
    const healthyRetryRes = await trackingWorker.fetch(
      reconcilePlannedStopReq({ ...SCOPE, trip_id: TRIP_ID }),
      healthyEnv,
      {},
    );
    const healthyRetryBody = await healthyRetryRes.json();

    assert.equal(healthyRetryRes.status, 200);
    assert.equal(healthyRetryBody.ok, true);
    assert.equal(healthyRetryBody.reconciled, true);
    assert.equal(
      healthyRetryBody.compliance_emit_state,
      "applied",
      "healthy recovery MUST flip tracking to APPLIED",
    );

    // Compliance storage: canonical AND date-index both present exactly
    // once (no duplicates from the earlier failed attempts).
    const canonicalAfterHealthy = [...healthyRecoveryKV.store.keys()].filter(
      (k) => k.startsWith("compliance_event_canonical_v1/tenant/t1/company/c1/eid/"),
    );
    const dateAfterHealthy = [...healthyRecoveryKV.store.keys()].filter((k) =>
      k.startsWith("compliance_event_v1/tenant/t1/company/c1/"),
    );
    assert.equal(canonicalAfterHealthy.length, 1);
    assert.equal(dateAfterHealthy.length, 1, "date entry recovered exactly once");

    // Dashboard MUST show EXACTLY one row.
    const healthyListRes = await complianceWorker.fetch(
      new Request(
        "https://compliance.internal/compliance/events/recent?tenant_id=T1&company_id=C1&limit=50",
        { method: "GET", headers: { "x-admin-token": COMPLIANCE_ADMIN } },
      ),
      { ADMIN_TOKEN: COMPLIANCE_ADMIN, COMPLIANCE_KV: healthyRecoveryKV },
      {},
    );
    const healthyListBody = await healthyListRes.json();
    const healthyRows = (healthyListBody.events || []).filter(
      (e) => e.event_id === `ride_stop:T1:C1:${TRIP_ID}`,
    );
    assert.equal(
      healthyRows.length,
      1,
      "dashboard MUST show EXACTLY one event after successful recovery",
    );

    // Tracking state: APPLIED, attempt count = 3 (initial + failing retry
    // + healthy retry), error code cleared.
    const trackingFinal = JSON.parse(trackingKV.store.get(TRIP_KEY));
    assert.equal(trackingFinal.compliance_emit_state, "applied");
    assert.equal(trackingFinal.compliance_emit_last_error_code, null);
    assert.equal(trackingFinal.compliance_emit_attempt_count, 3);
  },
);
