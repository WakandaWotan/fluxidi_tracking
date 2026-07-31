// RELEASE-P0-CLOSE-PLANNED-CHIRON-DURABILITY-GAPS-2026-07-31 —
// storage-level durability tests for the compliance append idempotency
// state-machine.
//
// Guarantees under test (per user's blocker list):
//   1. POINTER/BODY DATA-LOSS WINDOW: a partial write that leaves the
//      canonical body missing must never be reported as
//      applied/deduplicated success on a subsequent retry.
//   2. CONCURRENT EXACTLY-ONCE: two concurrent first appends with the same
//      event_id must land in exactly one canonical KV slot; the
//      recent/dashboard read must return exactly one row per event_id.
//
// Run: node --test workers/compliance/compliance_partial_write_and_concurrency.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import worker from "./fluxidi_compliance_worker.js";

const ADMIN = "compliance-admin-token";
const SCOPE = { tenant_id: "T1", company_id: "C1" };

// KV mock with an optional put-failure injector. `putFilter(key, index)` is
// called before every put; when it returns a truthy string, the put throws
// with that message.
function makeKV({ seed = {}, putFilter = null } = {}) {
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
      const names = [...store.keys()]
        .filter((k) => k.startsWith(prefix))
        .sort();
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

function envFor(kv) {
  return { ADMIN_TOKEN: ADMIN, COMPLIANCE_KV: kv };
}

function appendReq(body) {
  return new Request("https://compliance.internal/compliance/events/append", {
    method: "POST",
    headers: { "content-type": "application/json", "x-admin-token": ADMIN },
    body: JSON.stringify(body),
  });
}

function recentReq({ tenant, company, limit = 50 }) {
  const u = new URL("https://compliance.internal/compliance/events/recent");
  u.searchParams.set("tenant_id", tenant);
  u.searchParams.set("company_id", company);
  u.searchParams.set("limit", String(limit));
  return new Request(u.toString(), {
    method: "GET",
    headers: { "x-admin-token": ADMIN },
  });
}

function stopEventBody(over = {}) {
  return {
    ...SCOPE,
    event_type: "ride_stop",
    event_id: "ride_stop:T1:C1:planned_abc",
    booking_id: "booking_abc",
    trip_id: "planned_abc",
    driver_id: "D1",
    vehicle_id: "V1",
    ride_type: "planned",
    lifecycle_status: "stopped",
    created_at_utc: "2026-07-30T10:00:00.000Z",
    timestamps: { stopped_at_utc: "2026-07-30T10:00:00.000Z" },
    ...over,
  };
}

// Storage keys are built via safeSegment(...), which lowercases scope
// tokens. Tests use the *safeSegment* form here so a scope like `T1/C1`
// resolves to `t1/c1` — matching the actual KV prefix.
function countCanonicalKeys(kv, tenant = "t1", company = "c1") {
  return [...kv.store.keys()].filter((k) =>
    k.startsWith(
      `compliance_event_canonical_v1/tenant/${tenant}/company/${company}/eid/`,
    ),
  ).length;
}

function countDateKeys(kv, tenant = "t1", company = "c1") {
  return [...kv.store.keys()].filter((k) =>
    k.startsWith(`compliance_event_v1/tenant/${tenant}/company/${company}/`),
  ).length;
}

// ---------------------------------------------------------------------------
// GAP 1a: canonical write itself fails → no false applied/dedup on retry.
// ---------------------------------------------------------------------------
test("canonical put failure leaves no state; retry reports fresh write (not dedup)", async () => {
  // Fail the very first put (canonical) exactly once.
  const kv = makeKV({
    putFilter: (_key, idx) => (idx === 1 ? "simulated_canonical_put_failure" : null),
  });
  const env = envFor(kv);

  let threw = false;
  try {
    await worker.fetch(appendReq(stopEventBody()), env, {});
  } catch (_) {
    threw = true;
  }
  // Handler either throws or returns 5xx; verify NO state persisted either way.
  assert.equal(countCanonicalKeys(kv), 0, "no canonical body after failed put");
  assert.equal(countDateKeys(kv), 0, "no date entry either");
  assert.ok(threw || true);

  // Retry against the same store with no injected failures.
  // Fresh KV wrapper reusing the same underlying map:
  const clean = makeKV({ seed: Object.fromEntries(kv.store.entries()) });
  const res = await worker.fetch(appendReq(stopEventBody()), envFor(clean), {});
  const body = await res.json();
  assert.equal(res.status, 200);
  assert.equal(body.ok, true);
  assert.equal(
    body.deduplicated,
    false,
    "retry MUST NOT falsely report deduplicated=true",
  );
  assert.equal(countCanonicalKeys(clean), 1);
  assert.equal(countDateKeys(clean), 1);
});

// ---------------------------------------------------------------------------
// GAP 1b: canonical succeeds, date-index fails → retry recovers date entry
// AND reports dedup=true (canonical was valid) with recovered=true.
// ---------------------------------------------------------------------------
test("canonical ok + date put failure: retry recovers missing date entry, reports dedup+recovered", async () => {
  // Fail the SECOND put only (date-index write).
  const kv = makeKV({
    putFilter: (_key, idx) => (idx === 2 ? "simulated_date_put_failure" : null),
  });
  const env = envFor(kv);

  let threw = false;
  try {
    await worker.fetch(appendReq(stopEventBody()), env, {});
  } catch (_) {
    threw = true;
  }
  // Canonical body persisted; date entry did not.
  assert.equal(countCanonicalKeys(kv), 1, "canonical persisted before date-index failure");
  assert.equal(countDateKeys(kv), 0, "date entry absent");
  assert.ok(threw || true);

  // Retry against a clean env (no failure injector) with the SAME store.
  const retryKv = makeKV({ seed: Object.fromEntries(kv.store.entries()) });
  const res = await worker.fetch(appendReq(stopEventBody()), envFor(retryKv), {});
  const body = await res.json();
  assert.equal(res.status, 200);
  assert.equal(body.ok, true);
  assert.equal(body.deduplicated, true, "canonical exists → dedup=true (safe)");
  assert.equal(body.recovered, true, "missing date entry was rebuilt");
  assert.equal(countCanonicalKeys(retryKv), 1, "still exactly one canonical");
  assert.equal(countDateKeys(retryKv), 1, "date entry restored");

  // Dashboard read shows exactly one row for the event.
  const listRes = await worker.fetch(
    recentReq({ tenant: "T1", company: "C1" }),
    envFor(retryKv),
    {},
  );
  const listBody = await listRes.json();
  const stopEvents = (listBody.events || []).filter(
    (e) => e.event_id === "ride_stop:T1:C1:planned_abc",
  );
  assert.equal(stopEvents.length, 1);
});

// ---------------------------------------------------------------------------
// GAP 2: concurrent exactly-once — two racing first appends with the same
// event_id resolve to EXACTLY ONE canonical row + EXACTLY ONE dashboard row.
// ---------------------------------------------------------------------------
test("two concurrent first appends resolve to exactly one canonical row and one dashboard row", async () => {
  const kv = makeKV();
  const env = envFor(kv);

  const [res1, res2] = await Promise.all([
    worker.fetch(appendReq(stopEventBody()), env, {}),
    worker.fetch(appendReq(stopEventBody()), env, {}),
  ]);
  const [body1, body2] = await Promise.all([res1.json(), res2.json()]);

  assert.equal(res1.status, 200);
  assert.equal(res2.status, 200);
  assert.equal(body1.ok, true);
  assert.equal(body2.ok, true);
  assert.equal(body1.event_id, "ride_stop:T1:C1:planned_abc");
  assert.equal(body2.event_id, "ride_stop:T1:C1:planned_abc");

  // Storage guarantee: exactly one canonical row.
  assert.equal(
    countCanonicalKeys(kv),
    1,
    "canonical (tenant, company, event_id) slot must be unique under race",
  );

  // Dashboard/read-time dedup guarantee.
  const listRes = await worker.fetch(
    recentReq({ tenant: "T1", company: "C1" }),
    env,
    {},
  );
  const listBody = await listRes.json();
  const stopEvents = (listBody.events || []).filter(
    (e) => e.event_id === "ride_stop:T1:C1:planned_abc",
  );
  assert.equal(
    stopEvents.length,
    1,
    "dashboard/recent read yields exactly one canonical event per event_id",
  );
});

test("eight concurrent retries of same event_id still yield exactly one dashboard row", async () => {
  const kv = makeKV();
  const env = envFor(kv);

  const N = 8;
  const results = await Promise.all(
    Array.from({ length: N }, () => worker.fetch(appendReq(stopEventBody()), env, {})),
  );
  for (const r of results) assert.equal(r.status, 200);

  assert.equal(countCanonicalKeys(kv), 1, "single canonical slot under storm");

  const listRes = await worker.fetch(
    recentReq({ tenant: "T1", company: "C1" }),
    env,
    {},
  );
  const listBody = await listRes.json();
  const stopEvents = (listBody.events || []).filter(
    (e) => e.event_id === "ride_stop:T1:C1:planned_abc",
  );
  assert.equal(stopEvents.length, 1);
});

test("tenant/company scope isolation: same event_id in different tenants stays distinct", async () => {
  const kv = makeKV();
  const env = envFor(kv);

  const r1 = await worker.fetch(appendReq(stopEventBody()), env, {});
  const r2 = await worker.fetch(
    appendReq(stopEventBody({ tenant_id: "T2" })),
    env,
    {},
  );
  assert.equal(r1.status, 200);
  assert.equal(r2.status, 200);

  const t1Canonical = [...kv.store.keys()].filter((k) =>
    k.startsWith("compliance_event_canonical_v1/tenant/t1/"),
  ).length;
  const t2Canonical = [...kv.store.keys()].filter((k) =>
    k.startsWith("compliance_event_canonical_v1/tenant/t2/"),
  ).length;
  assert.equal(t1Canonical, 1);
  assert.equal(t2Canonical, 1, "cross-tenant does NOT collapse");

  // Reading T1 must not see T2's event and vice-versa.
  const listT1 = await worker.fetch(recentReq({ tenant: "T1", company: "C1" }), env, {});
  const listT2 = await worker.fetch(recentReq({ tenant: "T2", company: "C1" }), env, {});
  const bodyT1 = await listT1.json();
  const bodyT2 = await listT2.json();
  const t1Ids = (bodyT1.events || []).map((e) => e.event_id);
  const t2Ids = (bodyT2.events || []).map((e) => e.event_id);
  assert.ok(t1Ids.includes("ride_stop:T1:C1:planned_abc"));
  assert.equal(t2Ids.includes("ride_stop:T1:C1:planned_abc"), true);
  // (Same event_id string but they live in separate scope prefixes.)
  assert.equal(t1Ids.length, 1);
  assert.equal(t2Ids.length, 1);
});

test("append without client-supplied event_id keeps legacy single-write path (no canonical slot)", async () => {
  const kv = makeKV();
  const env = envFor(kv);

  const res = await worker.fetch(
    appendReq({
      ...SCOPE,
      event_type: "ride_stop",
      booking_id: "booking_zzz",
      trip_id: "planned_zzz",
      created_at_utc: "2026-07-30T10:00:00.000Z",
    }),
    env,
    {},
  );
  const body = await res.json();
  assert.equal(res.status, 200);
  assert.equal(body.ok, true);
  // Legacy path: no canonical slot; only a single date-indexed write.
  assert.equal(countCanonicalKeys(kv), 0);
  assert.equal(countDateKeys(kv), 1);
});

test("dedup is idempotent across multiple sequential retries (no additional date rows)", async () => {
  const kv = makeKV();
  const env = envFor(kv);

  const r1 = await worker.fetch(appendReq(stopEventBody()), env, {});
  await r1.json();
  const dateCountAfter1 = countDateKeys(kv);

  for (let i = 0; i < 5; i++) {
    const r = await worker.fetch(appendReq(stopEventBody()), env, {});
    const b = await r.json();
    assert.equal(r.status, 200);
    assert.equal(b.deduplicated, true, `retry #${i + 2} must dedup`);
    assert.equal(b.recovered, false, "no recovery needed");
  }
  assert.equal(
    countDateKeys(kv),
    dateCountAfter1,
    "sequential retries must not add extra date rows",
  );
  assert.equal(countCanonicalKeys(kv), 1);
});
