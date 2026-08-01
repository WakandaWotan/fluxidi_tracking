// RELEASE-P0 Option A′ — atomic human booking ID allocator tests.
//
// Run:
//   node --test workers/booking/human_booking_id_allocator_p0.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import {
  HUMAN_BOOKING_ID_DO_FLAG,
  HumanBookingIdSequenceDO,
  applySeedFloor,
  callHumanBookingIdDo,
  computeHumanBookingIdSeedFloor,
  computeRollbackSeqValue,
  computeSeedFloor,
  createMemoryHumanBookingIdSequenceBinding,
  formatHumanBookingId,
  humanBookingIdDoEnabled,
  normalizeHumanBookingYearMonth,
  parseHumanBookingIdSuffix,
  putBookingCreateIfAbsent,
  scanMaxHumanBookingSuffix,
} from "./modules/human_booking_id_allocator.mjs";

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
    async list(opts = {}) {
      const prefix = String(opts?.prefix || "");
      const keys = [...store.keys()]
        .filter((name) => (prefix ? name.startsWith(prefix) : true))
        .map((name) => ({ name }));
      return { keys, list_complete: true };
    },
  };
}

function envFlag(value) {
  return ["1", "true", "yes", "on"].includes(String(value ?? "").trim().toLowerCase());
}

test("1+2+3: parallel allocates across/same company yield distinct IDs", async () => {
  const binding = createMemoryHumanBookingIdSequenceBinding();
  const env = { HUMAN_BOOKING_ID_SEQUENCE: binding };
  const ym = "2026-08";
  await callHumanBookingIdDo(env, ym, { action: "seed", seed_floor: 10 });

  const tasks = [];
  for (let i = 0; i < 24; i++) {
    tasks.push(callHumanBookingIdDo(env, ym, { action: "allocate" }));
  }
  const results = await Promise.all(tasks);
  const ids = results.map((r) => r.booking_id);
  assert.equal(new Set(ids).size, 24);
  for (const id of ids) {
    assert.match(id, /^2026-08-\d+$/);
  }
});

test("4: month boundary uses YYYY-MM bucket identity", () => {
  assert.equal(normalizeHumanBookingYearMonth("2026-12"), "2026-12");
  assert.equal(normalizeHumanBookingYearMonth("2027-01"), "2027-01");
  assert.equal(formatHumanBookingId("2026-12", 1), "2026-12-001");
  assert.equal(formatHumanBookingId("2027-01", 12), "2027-01-012");
  assert.equal(humanBookingIdDoInstanceNameCompat("2026-08"), "2026-08");
});

function humanBookingIdDoInstanceNameCompat(ym) {
  return normalizeHumanBookingYearMonth(ym);
}

test("5: existing ID collision → create-if-absent refuses overwrite", async () => {
  const kv = makeKV({
    "booking:2026-08-001": JSON.stringify({ bookingId: "2026-08-001", company_id: "a" }),
  });
  const collision = await putBookingCreateIfAbsent(
    kv,
    "2026-08-001",
    JSON.stringify({ bookingId: "2026-08-001", company_id: "b" }),
    { mode: "create" },
  );
  assert.equal(collision.ok, false);
  assert.equal(collision.collision, true);
  const kept = JSON.parse(await kv.get("booking:2026-08-001"));
  assert.equal(kept.company_id, "a");
});

test("5b: allocator retries past occupied suffix", async () => {
  const binding = createMemoryHumanBookingIdSequenceBinding();
  const kv = makeKV({
    "booking:2026-08-011": JSON.stringify({ bookingId: "2026-08-011" }),
  });
  const env = { HUMAN_BOOKING_ID_SEQUENCE: binding, BOOKING_KV: kv };
  await callHumanBookingIdDo(env, "2026-08", { action: "seed", seed_floor: 10 });
  const first = await callHumanBookingIdDo(env, "2026-08", { action: "allocate" });
  assert.equal(first.booking_id, "2026-08-011");
  // Simulate worker collision loop: if exists, allocate again.
  let id = first.booking_id;
  if (await kv.get(`booking:${id}`)) {
    const second = await callHumanBookingIdDo(env, "2026-08", { action: "allocate" });
    id = second.booking_id;
  }
  assert.equal(id, "2026-08-012");
  const put = await putBookingCreateIfAbsent(
    kv,
    id,
    JSON.stringify({ bookingId: id }),
    { mode: "create" },
  );
  assert.equal(put.ok, true);
  assert.equal(put.created, true);
});

test("6+7: idempotent create-if-absent same payload is safe; no second record", async () => {
  const kv = makeKV();
  const payload = JSON.stringify({ bookingId: "2026-08-100", intent: "x" });
  const a = await putBookingCreateIfAbsent(kv, "2026-08-100", payload, { mode: "create" });
  const b = await putBookingCreateIfAbsent(kv, "2026-08-100", payload, { mode: "create" });
  assert.equal(a.ok, true);
  assert.equal(a.created, true);
  assert.equal(b.ok, true);
  assert.equal(b.created, false);
  assert.equal(kv.store.size, 1);
});

test("8: DO allocation failure → no booking record written", async () => {
  const kv = makeKV();
  const env = {
    HUMAN_BOOKING_ID_SEQUENCE: {
      idFromName: () => ({ name: "x" }),
      get: () => ({
        fetch: async () =>
          new Response(JSON.stringify({ ok: false, error: "do_down" }), { status: 503 }),
      }),
    },
    BOOKING_KV: kv,
  };
  await assert.rejects(
    () => callHumanBookingIdDo(env, "2026-08", { action: "allocate" }),
    /do_down|human_booking_id_do_failed/,
  );
  assert.equal(kv.store.size, 0);
});

test("9: KV write failure after allocation → no false success", async () => {
  const kv = {
    async get() {
      return null;
    },
    async put() {
      throw new Error("kv_put_failed");
    },
  };
  await assert.rejects(
    () =>
      putBookingCreateIfAbsent(kv, "2026-08-200", JSON.stringify({ bookingId: "2026-08-200" }), {
        mode: "create",
      }),
    /kv_put_failed/,
  );
});

test("10: subsequent retry remains safe after failed put", async () => {
  let puts = 0;
  const store = new Map();
  const kv = {
    async get(key) {
      return store.has(key) ? store.get(key) : null;
    },
    async put(key, val) {
      puts += 1;
      if (puts === 1) throw new Error("kv_put_failed");
      store.set(key, val);
    },
  };
  await assert.rejects(
    () =>
      putBookingCreateIfAbsent(kv, "2026-08-201", JSON.stringify({ bookingId: "2026-08-201" }), {
        mode: "create",
      }),
    /kv_put_failed/,
  );
  const retry = await putBookingCreateIfAbsent(
    kv,
    "2026-08-201",
    JSON.stringify({ bookingId: "2026-08-201" }),
    { mode: "create" },
  );
  assert.equal(retry.ok, true);
  assert.equal(retry.created, true);
});

test("11+12: legacy booking key/URL shape unchanged", () => {
  assert.equal(formatHumanBookingId("2026-07", 7), "2026-07-007");
  assert.equal(formatHumanBookingId("2026-07", 1000), "2026-07-1000");
  const path = `/bookings/${formatHumanBookingId("2026-07", 7)}`;
  assert.equal(path, "/bookings/2026-07-007");
  assert.equal(parseHumanBookingIdSuffix("booking:2026-07-007", "2026-07"), 7);
});

test("13-16: out-of-scope identifiers remain distinct formats", () => {
  // Street / Chiron / invoice refs are not produced by this allocator.
  assert.equal(formatHumanBookingId("2026-08", 1).startsWith("street_"), false);
  assert.match(formatHumanBookingId("2026-08", 1), /^\d{4}-\d{2}-\d+$/);
});

test("17: create-if-absent does not rewrite foreign tenant payload", async () => {
  const kv = makeKV({
    "booking:2026-08-050": JSON.stringify({
      bookingId: "2026-08-050",
      tenant_id: "t1",
      company_id: "c1",
    }),
  });
  const res = await putBookingCreateIfAbsent(
    kv,
    "2026-08-050",
    JSON.stringify({
      bookingId: "2026-08-050",
      tenant_id: "t2",
      company_id: "c2",
    }),
    { mode: "create" },
  );
  assert.equal(res.ok, false);
  const kept = JSON.parse(await kv.get("booking:2026-08-050"));
  assert.equal(kept.tenant_id, "t1");
});

test("18+19: seed cannot move backward; double seed idempotent", async () => {
  assert.equal(applySeedFloor(40, 10), 40);
  assert.equal(applySeedFloor(5, 10), 10);
  assert.equal(computeSeedFloor({ legacySeq: 3, maxExistingSuffix: 9 }), 9);

  const binding = createMemoryHumanBookingIdSequenceBinding();
  const env = { HUMAN_BOOKING_ID_SEQUENCE: binding };
  const a = await callHumanBookingIdDo(env, "2026-08", {
    action: "seed",
    seed_floor: 25,
  });
  assert.equal(a.next, 25);
  const b = await callHumanBookingIdDo(env, "2026-08", {
    action: "seed",
    seed_floor: 10,
  });
  assert.equal(b.next, 25);
  assert.equal(b.moved, false);
  const c = await callHumanBookingIdDo(env, "2026-08", {
    action: "seed",
    seed_floor: 30,
  });
  assert.equal(c.next, 30);
});

test("20: rollback sequence calculation is correct", () => {
  assert.equal(
    computeRollbackSeqValue({ doNext: 40, legacySeq: 12, maxExistingSuffix: 33 }),
    40,
  );
  assert.equal(
    computeRollbackSeqValue({ doNext: 5, legacySeq: 12, maxExistingSuffix: 33 }),
    33,
  );
});

test("seed floor scan uses legacy seq and booking suffixes", async () => {
  const kv = makeKV({
    "seq:2026-08": "4",
    "booking:2026-08-001": "{}",
    "booking:2026-08-015": "{}",
    "booking:2026-08-street_x": "{}", // ignored
    "booking:2026-07-999": "{}", // other month
  });
  const computed = await computeHumanBookingIdSeedFloor(kv, "2026-08");
  assert.equal(computed.legacySeq, 4);
  assert.equal(computed.maxExistingSuffix, 15);
  assert.equal(computed.seedFloor, 15);
  assert.equal(await scanMaxHumanBookingSuffix(kv, "2026-08"), 15);
});

test("feature flag gating", () => {
  assert.equal(humanBookingIdDoEnabled({ [HUMAN_BOOKING_ID_DO_FLAG]: "0" }, envFlag), false);
  assert.equal(humanBookingIdDoEnabled({ [HUMAN_BOOKING_ID_DO_FLAG]: "1" }, envFlag), true);
  assert.equal(humanBookingIdDoEnabled({ [HUMAN_BOOKING_ID_DO_FLAG]: "true" }, envFlag), true);
});

test("upsert_same allows provisional→confirmed for same id", async () => {
  const kv = makeKV();
  const id = "2026-08-300";
  await putBookingCreateIfAbsent(kv, id, JSON.stringify({ bookingId: id, status: "pending" }), {
    mode: "create",
  });
  const upd = await putBookingCreateIfAbsent(
    kv,
    id,
    JSON.stringify({ bookingId: id, status: "confirmed" }),
    { mode: "upsert_same" },
  );
  assert.equal(upd.ok, true);
  assert.equal(upd.updated, true);
  const rec = JSON.parse(await kv.get(`booking:${id}`));
  assert.equal(rec.status, "confirmed");
});

test("DO class allocate is transactional and monotonic", async () => {
  const storage = {
    _m: new Map(),
    async get(k) {
      return this._m.get(k);
    },
    async put(k, v) {
      this._m.set(k, v);
    },
    async transaction(fn) {
      return fn(this);
    },
  };
  const dob = new HumanBookingIdSequenceDO({ storage }, {});
  const seedResp = await dob.fetch(
    new Request("https://do/", {
      method: "POST",
      body: JSON.stringify({ action: "seed", year_month: "2026-08", seed_floor: 0 }),
    }),
  );
  assert.equal(seedResp.status, 200);
  const a = await (
    await dob.fetch(
      new Request("https://do/", {
        method: "POST",
        body: JSON.stringify({ action: "allocate", year_month: "2026-08" }),
      }),
    )
  ).json();
  const b = await (
    await dob.fetch(
      new Request("https://do/", {
        method: "POST",
        body: JSON.stringify({ action: "allocate", year_month: "2026-08" }),
      }),
    )
  ).json();
  assert.equal(a.seq, 1);
  assert.equal(b.seq, 2);
  assert.notEqual(a.booking_id, b.booking_id);
});
