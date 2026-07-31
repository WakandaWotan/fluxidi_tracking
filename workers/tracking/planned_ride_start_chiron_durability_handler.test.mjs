// RELEASE-P0-DURABLE-CHIRON-SYNC-FOR-PLANNED-RIDES-2026-07-31 — handler tests
// for the planned ride_start durable Chiron outbox. Same discipline as the
// planned STOP durability tests but scoped to the SESSION record.
//
// Run: node --test workers/tracking/planned_ride_start_chiron_durability_handler.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import worker from "./fluxidi_tracking_api_worker_V2_1_with_route_index.js";

const ADMIN = "test-admin-token";
const SCOPE = { tenant_id: "T1", company_id: "C1" };
const BOOKING_ID = "planned_booking_xyz";

const COMPLIANCE_ENV_BASE = {
  COMPLIANCE_API_URL: "https://compliance.internal",
  COMPLIANCE_ADMIN_TOKEN: "compliance-admin-token",
};

function makeKV(seed = {}) {
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
      return { keys: [...store.keys()].map((name) => ({ name })), list_complete: true };
    },
  };
}

function complianceWorker(handler) {
  return {
    calls: [],
    async fetch(request) {
      const body = await request.json().catch(() => ({}));
      this.calls.push(body);
      return handler(body, this.calls.length);
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

function sessionStartReq(body) {
  return new Request("https://track.internal/track/session/start", {
    method: "POST",
    headers: { "content-type": "application/json", "x-admin-token": ADMIN },
    body: JSON.stringify(body),
  });
}

function reconcileStartReq(body) {
  return new Request("https://track.internal/track/session/reconcile-start", {
    method: "POST",
    headers: { "content-type": "application/json", "x-admin-token": ADMIN },
    body: JSON.stringify(body),
  });
}

function startBody(over = {}) {
  return {
    ...SCOPE,
    booking_id: BOOKING_ID,
    driver_id: "D1",
    vehicle_id: "V1",
    pickup: "Central Station",
    dropoff: "Airport",
    client_started_at: "2026-07-30T08:00:00.000Z",
    ...over,
  };
}

function envFor({ kv, compliance } = {}) {
  return {
    ...COMPLIANCE_ENV_BASE,
    ADMIN_TOKEN: ADMIN,
    FLUXIDI_TRACKING: kv,
    COMPLIANCE_WORKER: compliance,
  };
}

function findSessionKey(kv) {
  for (const key of kv.store.keys()) {
    if (key.startsWith("tenant:T1:company:C1:session:")) return key;
  }
  return null;
}

test("planned START creates durable pending event and flips to applied after emit succeeds", async () => {
  const kv = makeKV();
  const compliance = complianceWorker(
    () => new Response(JSON.stringify({ ok: true }), { status: 200 }),
  );
  const env = envFor({ kv, compliance });
  const ctx = makeCtx();

  const res = await worker.fetch(sessionStartReq(startBody()), env, ctx);
  const body = await res.json();
  assert.equal(res.status, 200);
  assert.equal(body.ok, true);
  const sessionId = body.session_id;
  assert.ok(sessionId && sessionId.length > 0, "session_id must be returned");
  // RELEASE-P0-CLOSE-PLANNED-CHIRON-DURABILITY-GAPS-2026-07-31: event_id is
  // now scoped to session_id (not booking_id) so distinct legs/sessions of
  // the same booking do not falsely collapse into one Chiron event.
  const expectedEventId = `ride_start:T1:C1:${sessionId}`;
  assert.equal(body.compliance_emit_start_event_id, expectedEventId);

  await ctx.flush();

  // Compliance received exactly one ride_start event with the deterministic id.
  assert.equal(compliance.calls.length, 1);
  assert.equal(compliance.calls[0].event_type, "ride_start");
  assert.equal(compliance.calls[0].ride_type, "planned");
  assert.equal(compliance.calls[0].tenant_id, "T1");
  assert.equal(compliance.calls[0].company_id, "C1");
  assert.equal(compliance.calls[0].booking_id, BOOKING_ID);
  assert.equal(compliance.calls[0].event_id, expectedEventId);

  const sessionKey = findSessionKey(kv);
  assert.ok(sessionKey, "session must be persisted under a scoped key");
  const stored = JSON.parse(kv.store.get(sessionKey));
  assert.equal(stored.status, "active");
  assert.equal(stored.compliance_emit_start_state, "applied");
  assert.equal(stored.compliance_emit_start_event_id, expectedEventId);
  assert.equal(stored.compliance_emit_start_attempt_count, 1);
  assert.equal(stored.compliance_emit_start_last_error_code, null);
});

test("planned START leaves compliance_emit_start_state=pending with error code when emit fails", async () => {
  const kv = makeKV();
  const compliance = complianceWorker(
    () => new Response(JSON.stringify({ ok: false }), { status: 502 }),
  );
  const env = envFor({ kv, compliance });
  const ctx = makeCtx();

  const res = await worker.fetch(sessionStartReq(startBody()), env, ctx);
  const body = await res.json();
  assert.equal(res.status, 200); // start UX never blocked on Chiron
  assert.equal(body.ok, true);
  const sessionId = body.session_id;

  await ctx.flush();

  const sessionKey = findSessionKey(kv);
  const stored = JSON.parse(kv.store.get(sessionKey));
  const expectedEventId = `ride_start:T1:C1:${sessionId}`;
  assert.equal(stored.status, "active");
  assert.equal(stored.compliance_emit_start_state, "pending");
  assert.equal(stored.compliance_emit_start_event_id, expectedEventId);
  assert.equal(stored.compliance_emit_start_attempt_count, 1);
  assert.equal(stored.compliance_emit_start_last_error_code, "http_502");

  // Reconcile succeeds and marks applied.
  const complianceUp = complianceWorker(
    () => new Response(JSON.stringify({ ok: true }), { status: 200 }),
  );
  const res2 = await worker.fetch(
    reconcileStartReq({ ...SCOPE, session_id: sessionId }),
    envFor({ kv, compliance: complianceUp }),
    {},
  );
  const body2 = await res2.json();
  assert.equal(res2.status, 200);
  assert.equal(body2.reconciled, true);
  assert.equal(body2.compliance_emit_start_state, "applied");
  // Reused the deterministic event_id.
  assert.equal(complianceUp.calls.length, 1);
  assert.equal(complianceUp.calls[0].event_id, expectedEventId);
  const storedAfter = JSON.parse(kv.store.get(sessionKey));
  assert.equal(storedAfter.compliance_emit_start_state, "applied");
  assert.equal(storedAfter.compliance_emit_start_attempt_count, 2);
});

test("reconcile-start is idempotent when already applied", async () => {
  const kv = makeKV();
  const compliance = complianceWorker(
    () => new Response(JSON.stringify({ ok: true }), { status: 200 }),
  );
  const ctx = makeCtx();
  const startRes = await worker.fetch(sessionStartReq(startBody()), envFor({ kv, compliance }), ctx);
  const startBodyJson = await startRes.json();
  await ctx.flush();
  assert.equal(compliance.calls.length, 1);

  const res = await worker.fetch(
    reconcileStartReq({ ...SCOPE, session_id: startBodyJson.session_id }),
    envFor({ kv, compliance }),
    {},
  );
  const body = await res.json();
  assert.equal(body.reason, "already_applied");
  assert.equal(compliance.calls.length, 1); // no re-emit
});

test("reconcile-start fails closed when scope mismatches persisted session", async () => {
  const kv = makeKV();
  const compliance = complianceWorker(
    () => new Response(JSON.stringify({ ok: false }), { status: 500 }),
  );
  const ctx = makeCtx();
  const startRes = await worker.fetch(sessionStartReq(startBody()), envFor({ kv, compliance }), ctx);
  const startBodyJson = await startRes.json();
  await ctx.flush();

  // Try to reconcile using a DIFFERENT tenant.
  const cross = complianceWorker(
    () => new Response(JSON.stringify({ ok: true }), { status: 200 }),
  );
  const res = await worker.fetch(
    reconcileStartReq({
      tenant_id: "T2",
      company_id: "C1",
      session_id: startBodyJson.session_id,
    }),
    envFor({ kv, compliance: cross }),
    {},
  );
  // Must not resolve the cross-tenant session, must not emit into T2.
  assert.notEqual(res.status, 200);
  assert.equal(cross.calls.length, 0);
});

// RELEASE-P0-CLOSE-PLANNED-CHIRON-DURABILITY-GAPS-2026-07-31: two distinct
// starts on the SAME booking (roundtrip legs, or a restart after cancel)
// each get their own session_id → distinct deterministic event_ids → two
// Chiron ride_start events. A booking-id-scoped event_id would incorrectly
// collapse them into one.
test("two starts on the same booking allocate distinct session-scoped event_ids", async () => {
  const kv = makeKV();
  const compliance = complianceWorker(
    () => new Response(JSON.stringify({ ok: true }), { status: 200 }),
  );
  const env = envFor({ kv, compliance });
  const ctx1 = makeCtx();

  const r1 = await worker.fetch(sessionStartReq(startBody()), env, ctx1);
  const b1 = await r1.json();
  await ctx1.flush();
  const s1 = b1.session_id;
  const eid1 = b1.compliance_emit_start_event_id;

  const ctx2 = makeCtx();
  const r2 = await worker.fetch(sessionStartReq(startBody()), env, ctx2);
  const b2 = await r2.json();
  await ctx2.flush();
  const s2 = b2.session_id;
  const eid2 = b2.compliance_emit_start_event_id;

  assert.ok(s1 && s2 && s1 !== s2, "each start gets a fresh session_id");
  assert.equal(eid1, `ride_start:T1:C1:${s1}`);
  assert.equal(eid2, `ride_start:T1:C1:${s2}`);
  assert.notEqual(
    eid1,
    eid2,
    "distinct sessions on the same booking MUST have distinct ride_start event_ids",
  );

  // Compliance received TWO distinct ride_start events.
  assert.equal(compliance.calls.length, 2);
  const complianceEventIds = compliance.calls.map((c) => c.event_id).sort();
  assert.deepEqual(complianceEventIds, [eid1, eid2].sort());
});

// Retry of the SAME start (same session_id) MUST reuse the same event_id.
test("reconcile-start of the same session reuses the same deterministic event_id", async () => {
  const kv = makeKV();
  // First call fails so we can reconcile.
  const compliance = complianceWorker(
    () => new Response(JSON.stringify({ ok: false }), { status: 503 }),
  );
  const ctx = makeCtx();
  const startRes = await worker.fetch(sessionStartReq(startBody()), envFor({ kv, compliance }), ctx);
  const startBodyJson = await startRes.json();
  await ctx.flush();
  const sessionId = startBodyJson.session_id;
  const expectedEid = `ride_start:T1:C1:${sessionId}`;
  assert.equal(compliance.calls[0].event_id, expectedEid);

  // Reconcile a few times; the same event_id must be sent every retry.
  const complianceRetry = complianceWorker(
    () => new Response(JSON.stringify({ ok: true }), { status: 200 }),
  );
  for (let i = 0; i < 3; i++) {
    const r = await worker.fetch(
      reconcileStartReq({ ...SCOPE, session_id: sessionId }),
      envFor({ kv, compliance: complianceRetry }),
      {},
    );
    await r.json();
  }
  for (const call of complianceRetry.calls) {
    assert.equal(call.event_id, expectedEid);
  }
});
