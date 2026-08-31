import { test } from "node:test";
import assert from "node:assert/strict";

import {
  compareCompanyListSort,
  decodeListCursor,
  encodeListCursor,
  isCompanyActiveListRow,
  projectBookingListRows,
  seedProjectedCompanyPages,
  tryListCompanyBookingsProjected,
} from "./booking_list_projection.js";

function countingKV(seed = {}) {
  const store = new Map();
  const counts = { get: 0, list: 0, put: 0, delete: 0, got: [] };
  for (const [key, value] of Object.entries(seed)) {
    store.set(key, typeof value === "string" ? value : JSON.stringify(value));
  }
  return {
    store,
    counts,
    async get(key, opts) {
      counts.get += 1;
      counts.got.push(key);
      if (!store.has(key)) return null;
      const raw = store.get(key);
      const asJson = opts === "json" || (opts && opts.type === "json");
      if (asJson) {
        try {
          return typeof raw === "string" ? JSON.parse(raw) : raw;
        } catch (_) {
          return null;
        }
      }
      return raw;
    },
    async put(key, val) {
      counts.put += 1;
      store.set(key, val);
    },
    async delete(key) {
      counts.delete += 1;
      store.delete(key);
    },
    async list() {
      counts.list += 1;
      return { keys: [], list_complete: true };
    },
  };
}

const SCOPE = { tenant_id: "t1", company_id: "c1", hasScope: true };

function row(id, extras = {}) {
  const created = extras.created_at || `2026-08-01T00:00:${String(id).padStart(2, "0")}.000Z`;
  return {
    booking_id: id,
    created_at: created,
    createdAt: created,
    pickup_iso: extras.pickup_iso || "2026-08-31T12:00:00.000Z",
    from: "A",
    to: "B",
    status: extras.status || "CONFIRMED",
    customer_name: extras.customer_name || "Pat",
  };
}

test("stable newest-first sort uses created_at then booking_id then leg_id", () => {
  const a = {
    _proj: { sort_ms: 100, booking_id: "2026-08-002", leg_id: "L1" },
  };
  const b = {
    _proj: { sort_ms: 100, booking_id: "2026-08-002", leg_id: "L2" },
  };
  const c = {
    _proj: { sort_ms: 200, booking_id: "2026-08-001", leg_id: "" },
  };
  const rows = [a, b, c].sort(compareCompanyListSort);
  assert.equal(rows[0]._proj.booking_id, "2026-08-001");
  assert.equal(rows[1]._proj.leg_id, "L2");
  assert.equal(rows[2]._proj.leg_id, "L1");
});

test("cursor encode/decode is opaque and stable", () => {
  const encoded = encodeListCursor({
    v: 1,
    g: 3,
    view: "all",
    after: { sort_ms: 9, booking_id: "2026-08-010", leg_id: "" },
  });
  assert.ok(encoded);
  assert.equal(encoded.includes("2026-08-010"), false);
  const parsed = decodeListCursor(encoded);
  assert.equal(parsed.g, 3);
  assert.equal(parsed.after.booking_id, "2026-08-010");
});

test("active-only drops completed and stale pickups", () => {
  const now = Date.parse("2026-08-31T12:00:00.000Z");
  assert.equal(
    isCompanyActiveListRow({ status: "COMPLETED", pickup_iso: "2026-09-01T12:00:00.000Z" }, now),
    false,
  );
  assert.equal(
    isCompanyActiveListRow({ status: "CONFIRMED", pickup_iso: "2026-08-30T00:00:00.000Z" }, now),
    false,
  );
  assert.equal(
    isCompanyActiveListRow({ status: "CONFIRMED", pickup_iso: "2026-08-31T10:00:00.000Z" }, now),
    true,
  );
});

test("projectBookingListRows keeps list fields and strips secrets", () => {
  const rows = projectBookingListRows("2026-08-100", {
    tenant_id: "t1",
    company_id: "c1",
    status: "CONFIRMED",
    created_at: "2026-08-01T00:00:00.000Z",
    booking: {
      from: "Brussels",
      to: "Antwerp",
      pickup_iso: "2026-08-31T15:00:00.000Z",
      customer_name: "Pat",
      customer_phone: "0032",
      token: "secret-token",
      access_token: "nope",
    },
  });
  assert.equal(rows.length, 1);
  assert.equal(rows[0].from, "Brussels");
  assert.equal(rows[0].customer_name, "Pat");
  assert.equal(rows[0].token, undefined);
  assert.equal(rows[0].access_token, undefined);
});

test("seeded company first/next pages stay within two page reads", async () => {
  const rows = [];
  for (let i = 0; i < 83; i += 1) {
    rows.push(row(`2026-08-${String(100 + i).padStart(3, "0")}`));
  }
  const seed = seedProjectedCompanyPages(SCOPE, rows, { includeHistory: true });
  const kv = countingKV(seed);
  const first = await tryListCompanyBookingsProjected(
    { BOOKING_KV: kv },
    { limit: 50, includeHistory: true, tenantScope: SCOPE },
  );
  assert.equal(first.ok, true);
  assert.equal(first.items.length, 50);
  assert.equal(first.has_more, true);
  assert.ok(first.next_cursor);
  const next = await tryListCompanyBookingsProjected(
    { BOOKING_KV: kv },
    { limit: 50, includeHistory: true, cursor: first.next_cursor, tenantScope: SCOPE },
  );
  assert.equal(next.ok, true);
  assert.equal(next.items.length, 33);
  assert.equal(next.has_more, false);
  assert.equal(
    kv.counts.got.some((key) => String(key).startsWith("booking:")),
    false,
  );
});
