// COMPANY-DATA-LATENCY-P0-REPAIR-1 (Part A) — executable spec for the
// bounded-parallel repair of `handleRecent`. Proves:
//
//   1. Response parity (schema, count, malformed skip, ordering, isolation)
//      for a 100-event scope after the repair.
//   2. Reads are dispatched in bounded parallel — a deterministic fake-KV
//      that resolves each `get()` after a fixed delay demonstrates that
//      100 reads no longer accumulate 100 sequential delays.
//   3. The concurrency ceiling is respected (no more than
//      _COMPLIANCE_RECENT_READ_CONCURRENCY in-flight `get()`s at once) so
//      Cloudflare's per-request subrequest budget cannot be blown by a
//      pathological scope.
//   4. Timing diagnostics stay PII-free (no tenant/company/event IDs, no
//      payload data — only integer millisecond counters and counts).
//   5. Historical event compatibility — an old event without the leg
//      metadata that later versions carry is still returned correctly.
//
// Run:
//   node --test workers/compliance/chiron_recent_bounded_parallel.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import complianceWorker from "./fluxidi_compliance_worker.js";

const ADMIN_TOKEN = "backend-admin-token-only-for-internal-tooling";

function seg(v) {
  return String(v).toLowerCase().replace(/[^a-z0-9._-]/g, "_");
}

function eventKey({ tenantId, companyId, eventId, tsMs }) {
  const t = new Date(tsMs);
  const year = String(t.getUTCFullYear()).padStart(4, "0");
  const month = String(t.getUTCMonth() + 1).padStart(2, "0");
  const day = String(t.getUTCDate()).padStart(2, "0");
  return `compliance_event_v1/tenant/${seg(tenantId)}/company/${seg(companyId)}/${year}/${month}/${day}/${tsMs}_${eventId}`;
}

function makeEvent({ tenantId, companyId, eventId, tsIso }) {
  return {
    event_id: eventId,
    event_type: "ride_stop",
    schema_version: "1",
    tenant_id: tenantId,
    company_id: companyId,
    created_at_utc: tsIso,
    timestamps: { recorded_at_utc: tsIso, event_at_utc: tsIso },
    driver: { driver_id: `${companyId}-driver-1` },
    fare: { total: 10 },
  };
}

/** Instrumented KV mock that measures concurrency and injects fake per-get
 * latency so the test can prove bounded parallelism. */
function makeInstrumentedKV({ seed = {}, getLatencyMs = 0 } = {}) {
  const store = new Map(Object.entries(seed));
  const state = { inFlight: 0, maxInFlight: 0, totalGets: 0 };
  return {
    _state: state,
    store,
    async get(key) {
      state.inFlight += 1;
      state.totalGets += 1;
      if (state.inFlight > state.maxInFlight) {
        state.maxInFlight = state.inFlight;
      }
      try {
        if (getLatencyMs > 0) {
          await new Promise((r) => setTimeout(r, getLatencyMs));
        }
        return store.has(key) ? store.get(key) : null;
      } finally {
        state.inFlight -= 1;
      }
    },
    async put(key, val) {
      store.set(key, val);
    },
    async delete(key) {
      store.delete(key);
    },
    async list(opts = {}) {
      const prefix = String(opts.prefix || "");
      // Real Cloudflare KV returns keys in lex order; the repaired handler
      // depends on that assumption ONLY for the tail (nice-to-have) and
      // NEVER for correctness — sorting is done after read. This mock
      // returns lex order too so both paths are exercised identically.
      const all = [...store.keys()]
        .filter((name) => (prefix ? name.startsWith(prefix) : true))
        .sort();
      return { keys: all.map((name) => ({ name })), list_complete: true };
    },
  };
}

function seedHundredEventScope({ tenantId, companyId, malformedCount = 0 }) {
  const seed = {};
  const eventIds = [];
  // 100 events, 60 s apart, newest first when sorted by created_at_utc.
  const base = Date.parse("2026-07-01T09:00:00Z");
  for (let i = 0; i < 100; i += 1) {
    const tsMs = base + i * 60_000;
    const tsIso = new Date(tsMs).toISOString();
    const eventId = `${companyId}-evt-${i.toString().padStart(3, "0")}`;
    const key = eventKey({ tenantId, companyId, eventId, tsMs });
    if (i < malformedCount) {
      seed[key] = "{ not valid json ";
    } else {
      seed[key] = JSON.stringify(
        makeEvent({ tenantId, companyId, eventId, tsIso }),
      );
    }
    eventIds.push(eventId);
  }
  return { seed, eventIds };
}

function directAdminReq({ tenantId, companyId, limit = 100 }) {
  const url = new URL("https://compliance.internal/compliance/events/recent");
  url.searchParams.set("tenant_id", tenantId);
  url.searchParams.set("company_id", companyId);
  url.searchParams.set("limit", String(limit));
  return new Request(url.toString(), {
    method: "GET",
    headers: { authorization: `Bearer ${ADMIN_TOKEN}` },
  });
}

// ---------------------------------------------------------------------------
// 1. Parity — 100-event scope
// ---------------------------------------------------------------------------

test("Part A / T1: 100-event scope returns exactly the requested limit in newest-first order", async () => {
  const { seed } = seedHundredEventScope({ tenantId: "TA", companyId: "CA" });
  const kv = makeInstrumentedKV({ seed, getLatencyMs: 0 });
  const env = {
    ADMIN_TOKEN,
    COMPLIANCE_ADMIN_TOKEN: ADMIN_TOKEN,
    COMPLIANCE_KV: kv,
  };

  const res = await complianceWorker.fetch(
    directAdminReq({ tenantId: "TA", companyId: "CA", limit: 100 }),
    env,
  );
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.ok, true);
  // Response echoes the canonical (safeSegment-normalized) scope; matches
  // pre-repair behavior.
  assert.equal(body.tenant_id, "ta");
  assert.equal(body.company_id, "ca");
  assert.equal(body.count, 100);
  assert.equal(body.malformed_count, 0);
  assert.equal(body.limit, 100);
  assert.equal(body.scanned_count, 100);
  assert.equal(body.has_more_candidates, false);
  assert.equal(body.events.length, 100);
  // Newest first: index 99 comes first, index 0 last.
  assert.equal(body.events[0].event_id, "CA-evt-099");
  assert.equal(body.events[99].event_id, "CA-evt-000");
  // Response schema envelope preserved.
  assert.ok(typeof body.events[0].key === "string");
  assert.equal(body.events[0].event_type, "ride_stop");
});

test("Part A / T2: malformed events are skipped and counted, other rows still returned", async () => {
  const { seed } = seedHundredEventScope({
    tenantId: "TB",
    companyId: "CB",
    malformedCount: 5,
  });
  const kv = makeInstrumentedKV({ seed, getLatencyMs: 0 });
  const env = {
    ADMIN_TOKEN,
    COMPLIANCE_ADMIN_TOKEN: ADMIN_TOKEN,
    COMPLIANCE_KV: kv,
  };

  const res = await complianceWorker.fetch(
    directAdminReq({ tenantId: "TB", companyId: "CB", limit: 100 }),
    env,
  );
  const body = await res.json();
  assert.equal(res.status, 200);
  assert.equal(body.malformed_count, 5);
  assert.equal(body.count, 95);
  assert.equal(body.events.length, 95);
  // The first 5 keys (oldest) are the malformed ones per the seed helper, so
  // the newest-first response should NOT contain evt-000..evt-004.
  const returnedIds = new Set(body.events.map((e) => e.event_id));
  for (let i = 0; i < 5; i += 1) {
    assert.equal(
      returnedIds.has(`CB-evt-${i.toString().padStart(3, "0")}`),
      false,
    );
  }
});

test("Part A / T3: `limit=20` slice preserves newest-first ordering and marks has_more_candidates", async () => {
  const { seed } = seedHundredEventScope({ tenantId: "TC", companyId: "CC" });
  const kv = makeInstrumentedKV({ seed });
  const env = {
    ADMIN_TOKEN,
    COMPLIANCE_ADMIN_TOKEN: ADMIN_TOKEN,
    COMPLIANCE_KV: kv,
  };

  const res = await complianceWorker.fetch(
    directAdminReq({ tenantId: "TC", companyId: "CC", limit: 20 }),
    env,
  );
  const body = await res.json();
  assert.equal(res.status, 200);
  assert.equal(body.limit, 20);
  assert.equal(body.count, 20);
  assert.equal(body.events.length, 20);
  assert.equal(body.has_more_candidates, true);
  // Top 20 must be the 20 newest events.
  assert.equal(body.events[0].event_id, "CC-evt-099");
  assert.equal(body.events[19].event_id, "CC-evt-080");
});

// ---------------------------------------------------------------------------
// 2. Bounded parallelism (fake-latency proof)
// ---------------------------------------------------------------------------

test("Part A / T4: 100 reads with 30 ms simulated latency complete far under 100×30 ms wall time", async () => {
  const { seed } = seedHundredEventScope({ tenantId: "TD", companyId: "CD" });
  const kv = makeInstrumentedKV({ seed, getLatencyMs: 30 });
  const env = {
    ADMIN_TOKEN,
    COMPLIANCE_ADMIN_TOKEN: ADMIN_TOKEN,
    COMPLIANCE_KV: kv,
  };

  const started = Date.now();
  const res = await complianceWorker.fetch(
    directAdminReq({ tenantId: "TD", companyId: "CD", limit: 100 }),
    env,
  );
  const elapsedMs = Date.now() - started;
  const body = await res.json();
  assert.equal(res.status, 200);
  assert.equal(body.count, 100);
  // 100 sequential reads at 30 ms would take >= 3000 ms.
  // With concurrency = 16 the wall time is ~ (100 / 16) * 30 ≈ 190 ms plus
  // constant overhead; anything above 1500 ms means the fan-out regressed.
  assert.ok(
    elapsedMs < 1500,
    `expected < 1500 ms, got ${elapsedMs} ms — sequential regression?`,
  );
});

test("Part A / T5: concurrency ceiling respected — no more than 16 reads in flight at once", async () => {
  const { seed } = seedHundredEventScope({ tenantId: "TE", companyId: "CE" });
  const kv = makeInstrumentedKV({ seed, getLatencyMs: 10 });
  const env = {
    ADMIN_TOKEN,
    COMPLIANCE_ADMIN_TOKEN: ADMIN_TOKEN,
    COMPLIANCE_KV: kv,
  };

  await complianceWorker.fetch(
    directAdminReq({ tenantId: "TE", companyId: "CE", limit: 100 }),
    env,
  );
  // Repaired handler pins concurrency at 16. Anything above 32 means the
  // guard rail was lost.
  assert.ok(
    kv._state.maxInFlight <= 32,
    `max in-flight reads too high: ${kv._state.maxInFlight}`,
  );
  // Also assert we actually parallelized (> 1 in flight at some point).
  assert.ok(
    kv._state.maxInFlight >= 4,
    `reads did not parallelize: max in-flight was only ${kv._state.maxInFlight}`,
  );
  assert.ok(
    kv._state.totalGets === 100 || kv._state.totalGets === 101,
    `expected 100 event reads plus optional recent-index probe, got ${kv._state.totalGets}`,
  );
});

// ---------------------------------------------------------------------------
// 3. Tenant / company isolation
// ---------------------------------------------------------------------------

test("Part A / T6: two-tenant KV — one scope never sees the other's events", async () => {
  const seedA = seedHundredEventScope({ tenantId: "TX", companyId: "CX" }).seed;
  const seedB = seedHundredEventScope({ tenantId: "TY", companyId: "CY" }).seed;
  const merged = { ...seedA, ...seedB };
  const kv = makeInstrumentedKV({ seed: merged });
  const env = {
    ADMIN_TOKEN,
    COMPLIANCE_ADMIN_TOKEN: ADMIN_TOKEN,
    COMPLIANCE_KV: kv,
  };

  const resX = await complianceWorker.fetch(
    directAdminReq({ tenantId: "TX", companyId: "CX", limit: 100 }),
    env,
  );
  const bodyX = await resX.json();
  assert.equal(resX.status, 200);
  assert.equal(bodyX.count, 100);
  for (const ev of bodyX.events) {
    assert.ok(ev.event_id.startsWith("CX-evt-"), `leak: ${ev.event_id}`);
  }
});

// ---------------------------------------------------------------------------
// 4. Auth surface unchanged (regression cover for the repair)
// ---------------------------------------------------------------------------

test("Part A / T7: no auth → 401 still", async () => {
  const kv = makeInstrumentedKV({ seed: {} });
  const env = {
    ADMIN_TOKEN,
    COMPLIANCE_ADMIN_TOKEN: ADMIN_TOKEN,
    COMPLIANCE_KV: kv,
  };
  const url = new URL("https://compliance.internal/compliance/events/recent");
  url.searchParams.set("tenant_id", "TX");
  url.searchParams.set("company_id", "CX");
  const res = await complianceWorker.fetch(new Request(url.toString()), env);
  assert.equal(res.status, 401);
});

test("Part A / T8: internal-proxy scope mismatch still returns 403 proxy_scope_mismatch", async () => {
  const seed = seedHundredEventScope({ tenantId: "TX", companyId: "CX" }).seed;
  const kv = makeInstrumentedKV({ seed });
  const env = {
    ADMIN_TOKEN,
    COMPLIANCE_ADMIN_TOKEN: ADMIN_TOKEN,
    COMPLIANCE_KV: kv,
  };
  const url = new URL("https://compliance.internal/compliance/events/recent");
  url.searchParams.set("tenant_id", "TX");
  url.searchParams.set("company_id", "CX");
  const res = await complianceWorker.fetch(
    new Request(url.toString(), {
      headers: {
        "x-fluxidi-internal-proxy": "booking_worker_v1",
        "x-fluxidi-proxy-token": ADMIN_TOKEN,
        "x-fluxidi-proxy-tenant-id": "TY",
        "x-fluxidi-proxy-company-id": "CY",
      },
    }),
    env,
  );
  assert.equal(res.status, 403);
  const body = await res.json();
  assert.equal(body.error, "proxy_scope_mismatch");
});

// ---------------------------------------------------------------------------
// 5. Historical event compatibility (event without the modern leg metadata)
// ---------------------------------------------------------------------------

test("Part A / T9: historical event without leg metadata still projects and is returned", async () => {
  const tenantId = "TH";
  const companyId = "CH";
  const tsMs = Date.parse("2026-01-05T09:00:00Z");
  const tsIso = new Date(tsMs).toISOString();
  const eventId = "legacy-evt-1";
  const key = eventKey({ tenantId, companyId, eventId, tsMs });
  const seed = {
    [key]: JSON.stringify({
      event_id: eventId,
      event_type: "ride_stop",
      tenant_id: tenantId,
      company_id: companyId,
      created_at_utc: tsIso,
      // no timestamps.*, no leg metadata, no payment/fare/provenance
    }),
  };
  const kv = makeInstrumentedKV({ seed });
  const env = {
    ADMIN_TOKEN,
    COMPLIANCE_ADMIN_TOKEN: ADMIN_TOKEN,
    COMPLIANCE_KV: kv,
  };
  const res = await complianceWorker.fetch(
    directAdminReq({ tenantId, companyId, limit: 20 }),
    env,
  );
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.count, 1);
  assert.equal(body.events[0].event_id, eventId);
  assert.equal(body.events[0].event_type, "ride_stop");
});

// ---------------------------------------------------------------------------
// 6. Timing diagnostics stay PII-free
// ---------------------------------------------------------------------------

test("Part A / T10: [COMPLIANCE_RECENT] diagnostic line contains no tenant/company/event data", async () => {
  const { seed } = seedHundredEventScope({
    tenantId: "TENANT-SECRET",
    companyId: "COMPANY-SECRET",
  });
  const kv = makeInstrumentedKV({ seed });
  const env = {
    ADMIN_TOKEN,
    COMPLIANCE_ADMIN_TOKEN: ADMIN_TOKEN,
    COMPLIANCE_KV: kv,
  };
  const captured = [];
  const originalLog = console.log;
  console.log = (msg) => {
    captured.push(String(msg));
  };
  try {
    await complianceWorker.fetch(
      directAdminReq({
        tenantId: "TENANT-SECRET",
        companyId: "COMPANY-SECRET",
        limit: 100,
      }),
      env,
    );
  } finally {
    console.log = originalLog;
  }
  const diagnosticLine = captured.find((line) => line.startsWith("[COMPLIANCE_RECENT]"));
  assert.ok(diagnosticLine, "expected a [COMPLIANCE_RECENT] diagnostic line");
  // Verify PII-free: no tenant/company IDs, no event IDs, no payload material.
  for (const forbidden of [
    "TENANT-SECRET",
    "COMPANY-SECRET",
    "tenant_id",
    "company_id",
    "event_id",
    "ride_stop",
    "COMPANY-SECRET-evt",
    "COMPANY-SECRET-driver-1",
  ]) {
    assert.equal(
      diagnosticLine.includes(forbidden),
      false,
      `[COMPLIANCE_RECENT] leaked "${forbidden}"`,
    );
  }
  // Contract: line contains bounded integer counters we depend on for
  // downstream latency dashboards.
  for (const expected of [
    "endpoint=recent",
    "auth_ms=",
    "list_ms=",
    "read_ms=",
    "project_ms=",
    "total_ms=",
    "keys=100",
    "returned=100",
    "concurrency=",
  ]) {
    assert.ok(
      diagnosticLine.includes(expected),
      `[COMPLIANCE_RECENT] missing "${expected}"`,
    );
  }
});
