// COMPANY-AGENDA-P0 — planned rides on the existing company bookings index.
//
// Run:
//   node --test workers/booking/company_agenda_p0.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import worker from "./fluxidi_booking_worker.js";
import {
  assignAgendaRide,
  checkAssignmentOverlap,
  filterIndexItemsByPeriod,
  intervalsOverlap,
  rescheduleAgendaRide,
  rideWindow,
  unscheduledIndexItems,
} from "./modules/company_agenda.mjs";
import { companyBookingsListIndexKey, driverScopedBookingsIndexKey } from "./modules/booking_indexes.js";

const ADMIN = "p0-agenda-admin";
const TENANT_A = "TA";
const COMPANY_A = "CA";
const TENANT_B = "TB";
const COMPANY_B = "CB";

function countingKV(seed = {}) {
  const store = new Map();
  const meta = new Map();
  const counts = { get: 0, list: 0, put: 0, delete: 0, got: [], listed: [] };
  for (const [key, value] of Object.entries(seed)) {
    store.set(key, typeof value === "string" ? value : JSON.stringify(value));
  }
  return {
    store,
    meta,
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
        } catch {
          return null;
        }
      }
      return raw;
    },
    async put(key, val, opts) {
      counts.put += 1;
      store.set(key, val);
      if (opts?.metadata) meta.set(key, opts.metadata);
    },
    async delete(key) {
      counts.delete += 1;
      store.delete(key);
      meta.delete(key);
    },
    async list({ prefix = "" } = {}) {
      counts.list += 1;
      counts.listed.push(prefix);
      return { keys: [], list_complete: true };
    },
  };
}

function envWith(kv) {
  return { ADMIN_TOKEN: ADMIN, BOOKING_KV: kv };
}

async function adminRequest(env, path, { method = "GET", body, tenant = TENANT_A, company = COMPANY_A, headers = {} } = {}) {
  const url = new URL(`https://example.test${path}`);
  if (method === "GET") {
    url.searchParams.set("tenant_id", tenant);
    url.searchParams.set("company_id", company);
  }
  const payload = body && typeof body === "object"
    ? { tenant_id: tenant, company_id: company, ...body }
    : body;
  return worker.fetch(
    new Request(url, {
      method,
      headers: {
        "x-admin-token": ADMIN,
        "Content-Type": "application/json",
        ...headers,
      },
      body: method === "GET" ? undefined : JSON.stringify(payload || { tenant_id: tenant, company_id: company }),
    }),
    env,
    {},
  );
}

async function createRide(env, body, { idempotencyKey = "ride-1", tenant = TENANT_A, company = COMPANY_A } = {}) {
  const res = await adminRequest(env, "/company/agenda/rides", {
    method: "POST",
    tenant,
    company,
    headers: { "Idempotency-Key": idempotencyKey },
    body,
  });
  const json = await res.json();
  return { res, json };
}

test("period filter and overlap helpers stay honest", () => {
  const items = [
    { booking_id: "in", pickup_iso: "2026-09-11T08:00:00.000Z" },
    { booking_id: "out", pickup_iso: "2026-09-12T08:00:00.000Z" },
    { booking_id: "bad" },
  ];
  const fromMs = Date.parse("2026-09-11T00:00:00.000Z");
  const toMs = Date.parse("2026-09-12T00:00:00.000Z");
  const filtered = filterIndexItemsByPeriod(items, fromMs, toMs);
  assert.deepEqual(filtered.map((item) => item.booking_id), ["in"]);
  const spanning = filterIndexItemsByPeriod(
    [
      ...items,
      {
        booking_id: "overnight",
        pickup_iso: "2026-09-10T22:00:00.000Z",
        duration_min: 240,
      },
    ],
    fromMs,
    toMs,
  );
  assert.deepEqual(spanning.map((item) => item.booking_id), ["in", "overnight"]);
  assert.deepEqual(
    unscheduledIndexItems(items).map((item) => item.booking_id),
    ["bad"],
  );
  assert.equal(intervalsOverlap(0, 60, 59, 120), true);
  assert.equal(intervalsOverlap(0, 60, 60, 120), false);
  const unknown = rideWindow("2026-09-11T08:00:00.000Z", null);
  assert.equal(unknown.durationUnknown, true);
  assert.equal(unknown.end, null);
});

test("plan ride rejects a stale fixed-price preview and keeps a locked quote", async () => {
  const kv = countingKV();
  const env = envWith(kv);
  await kv.put(
    `tenant:${TENANT_A}:company:${COMPANY_A}:airport_fixed_fares:v1`,
    JSON.stringify({
      airport_fixed_fares: {
        fallback: "calculator",
        rules: [
          {
            rule_id: "fx_gent_brussel",
            name: "Gent-Brussel",
            kind: "city_pair",
            direction: "one_way",
            origin: { type: "city", value: "Gent" },
            destination: { type: "city", value: "Brussel" },
            price_incl_vat: 99,
            currency: "EUR",
            rule_version: 2,
          },
        ],
      },
    }),
  );
  const stale = await createRide(
    env,
    {
      customer_id: "cus_ada",
      customer_name: "Ada Lovelace",
      from: "Gent",
      to: "Brussel",
      pickup_iso: "2026-09-11T10:00:00.000Z",
      passengers: 2,
      fixed_price_snapshot: {
        fixed_fare_rule_id: "fx_gent_brussel",
        total_incl_vat: 70,
        rule_version: 1,
      },
    },
    { idempotencyKey: "stale-preview" },
  );
  assert.equal(stale.res.status, 409);
  assert.equal(stale.json.error, "price_changed");

  const locked = await createRide(
    env,
    {
      customer_id: "cus_ada",
      customer_name: "Ada Lovelace",
      from: "Gent",
      to: "Brussel",
      pickup_iso: "2026-09-11T11:00:00.000Z",
      passengers: 2,
      accepted_quote_id: "cq_locked",
      quote_price_locked: true,
      fixed_price_snapshot: {
        fixed_fare_rule_id: "fx_gent_brussel",
        total_incl_vat: 70,
        rule_version: 1,
      },
    },
    { idempotencyKey: "locked-quote" },
  );
  assert.equal(locked.res.status, 201);
  assert.equal(locked.json.ok, true);
  const stored = JSON.parse(kv.store.get(`booking:${locked.json.booking_id}`));
  assert.equal(stored.fixed_price_snapshot.total_incl_vat, 70);
});

test("create lists the same booking id and retry is idempotent", async () => {
  const kv = countingKV();
  const env = envWith(kv);
  const body = {
    customer_id: "cus_ada",
    customer_name: "Ada Lovelace",
    from: "Gent",
    to: "Brussel",
    pickup_iso: "2026-09-11T10:00:00.000Z",
    passengers: 2,
  };
  const first = await createRide(env, body, { idempotencyKey: "same-key" });
  assert.equal(first.res.status, 201);
  assert.equal(first.json.ok, true);
  assert.equal(first.json.item.do_not_dispatch, true);
  assert.equal(first.json.item.duration_unknown, true);
  assert.equal(first.json.item.source, "company_agenda");
  const bookingId = first.json.booking_id;
  const second = await createRide(env, body, { idempotencyKey: "same-key" });
  assert.equal(second.json.ok, true);
  assert.equal(second.json.idempotent, true);
  assert.equal(second.json.booking_id, bookingId);

  const listed = await adminRequest(
    env,
    "/company/agenda/rides?from=2026-09-11T00:00:00.000Z&to=2026-09-12T00:00:00.000Z",
  );
  const listJson = await listed.json();
  assert.equal(listed.status, 200);
  assert.equal(listJson.items.length, 1);
  assert.equal(listJson.items[0].booking_id, bookingId);
  assert.equal(listJson.has_more, false);
  assert.equal(kv.counts.list, 0);
  assert.equal(kv.counts.listed.length, 0);
});

test("agenda list reports has_more when the period has more rides than the page", async () => {
  const kv = countingKV();
  const env = envWith(kv);
  for (let i = 0; i < 3; i += 1) {
    await createRide(env, {
      customer_id: "cus_ada",
      from: "Gent",
      to: "Brussel",
      pickup_iso: `2026-09-11T1${i}:00:00.000Z`,
      duration_min: 30,
    }, { idempotencyKey: `page-${i}` });
  }
  const listed = await adminRequest(
    env,
    "/company/agenda/rides?from=2026-09-11T00:00:00.000Z&to=2026-09-12T00:00:00.000Z&limit=2",
  );
  const json = await listed.json();
  assert.equal(listed.status, 200);
  assert.equal(json.items.length, 2);
  assert.equal(json.count, 2);
  assert.equal(json.has_more, true);
  assert.ok(String(json.next_cursor || "").trim(), "has_more requires a cursor");

  const next = await adminRequest(
    env,
    `/company/agenda/rides?from=2026-09-11T00:00:00.000Z&to=2026-09-12T00:00:00.000Z&limit=2&cursor=${encodeURIComponent(json.next_cursor)}`,
  );
  const nextJson = await next.json();
  assert.equal(next.status, 200);
  assert.equal(nextJson.items.length, 1);
  assert.equal(nextJson.has_more, false);
  assert.equal(nextJson.next_cursor, null);
  const ids = [...json.items, ...nextJson.items].map((item) => item.booking_id);
  assert.equal(new Set(ids).size, 3);
  assert.equal(ids.length, 3);
});

test("invalid agenda cursor is rejected", async () => {
  const kv = countingKV();
  const env = envWith(kv);
  const listed = await adminRequest(
    env,
    "/company/agenda/rides?from=2026-09-11T00:00:00.000Z&to=2026-09-12T00:00:00.000Z&cursor=not-a-cursor",
  );
  const json = await listed.json();
  assert.equal(listed.status, 400);
  assert.equal(json.error, "invalid_cursor");
});

test("later agenda pages do not repeat unscheduled rides", async () => {
  const kv = countingKV();
  const env = envWith(kv);
  for (let i = 0; i < 3; i += 1) {
    await createRide(env, {
      customer_id: "cus_ada",
      from: "Gent",
      to: "Brussel",
      pickup_iso: `2026-09-11T1${i}:00:00.000Z`,
      duration_min: 30,
    }, { idempotencyKey: `unsched-page-${i}` });
  }
  const companyIndexKey = companyBookingsListIndexKey({
    tenant_id: TENANT_A,
    company_id: COMPANY_A,
  });
  const raw = await kv.get(companyIndexKey, { type: "json" });
  const items = Array.isArray(raw?.items) ? raw.items : [];
  items.push({ booking_id: "agb_unscheduled_only", status: "PENDING" });
  await kv.put(companyIndexKey, JSON.stringify({ ...raw, items }));
  const first = await adminRequest(
    env,
    "/company/agenda/rides?from=2026-09-11T00:00:00.000Z&to=2026-09-12T00:00:00.000Z&limit=2",
  );
  const firstJson = await first.json();
  assert.equal(firstJson.unscheduled.some((row) => row.booking_id === "agb_unscheduled_only"), true);
  const second = await adminRequest(
    env,
    `/company/agenda/rides?from=2026-09-11T00:00:00.000Z&to=2026-09-12T00:00:00.000Z&limit=2&cursor=${encodeURIComponent(firstJson.next_cursor)}`,
  );
  const secondJson = await second.json();
  assert.equal(secondJson.unscheduled.length, 0);
  const scheduled = [...firstJson.items, ...secondJson.items].map((row) => row.booking_id);
  assert.equal(new Set(scheduled).size, scheduled.length);
  assert.equal(scheduled.includes("agb_unscheduled_only"), false);
});

test("agenda list follows the period cursor past 200 rides", async () => {
  const kv = countingKV();
  const env = envWith(kv);
  const created = [];
  for (let i = 0; i < 205; i += 1) {
    const pickup = new Date(Date.UTC(2026, 9, 1, 0, 0, 0) + i * 60000).toISOString();
    const result = await createRide(env, {
      customer_id: "cus_ada",
      from: "Gent",
      to: "Brussel",
      pickup_iso: pickup,
      duration_min: 15,
    }, { idempotencyKey: `over-200-${String(i).padStart(3, "0")}` });
    assert.equal(result.json.ok, true, `create ${i} failed`);
    created.push(result.json.booking_id);
  }
  const first = await adminRequest(
    env,
    "/company/agenda/rides?from=2026-10-01T00:00:00.000Z&to=2026-10-02T00:00:00.000Z&limit=200",
  );
  const firstJson = await first.json();
  assert.equal(first.status, 200);
  assert.equal(firstJson.items.length, 200);
  assert.equal(firstJson.has_more, true);
  assert.ok(String(firstJson.next_cursor || "").trim());

  const second = await adminRequest(
    env,
    `/company/agenda/rides?from=2026-10-01T00:00:00.000Z&to=2026-10-02T00:00:00.000Z&limit=200&cursor=${encodeURIComponent(firstJson.next_cursor)}`,
  );
  const secondJson = await second.json();
  assert.equal(second.status, 200);
  assert.equal(secondJson.items.length, 5);
  assert.equal(secondJson.has_more, false);
  assert.equal(secondJson.next_cursor, null);

  const ids = [...firstJson.items, ...secondJson.items].map((item) => item.booking_id);
  assert.equal(ids.length, 205);
  assert.equal(new Set(ids).size, 205);
  assert.deepEqual([...ids].sort(), [...created].sort());
  assert.equal(firstJson.unscheduled.length, 0);
  assert.equal(secondJson.unscheduled.length, 0);
});

test("company B cannot read company A rides", async () => {
  const kv = countingKV();
  const env = envWith(kv);
  await createRide(env, {
    customer_id: "cus_ada",
    from: "Gent",
    to: "Brussel",
    pickup_iso: "2026-09-11T10:00:00.000Z",
  }, { idempotencyKey: "a-only" });
  const listed = await adminRequest(
    env,
    "/company/agenda/rides?from=2026-09-11T00:00:00.000Z&to=2026-09-12T00:00:00.000Z",
    { tenant: TENANT_B, company: COMPANY_B },
  );
  const json = await listed.json();
  assert.equal(json.items.length, 0);
});

test("assignment overlap and unknown duration fail closed", async () => {
  const kv = countingKV();
  const env = envWith(kv);
  const first = await createRide(env, {
    customer_id: "cus_ada",
    from: "Gent",
    to: "Brussel",
    pickup_iso: "2026-09-11T10:00:00.000Z",
    duration_min: 60,
    assigned_driver_id: "drv_1",
  }, { idempotencyKey: "drv-first" });
  assert.equal(first.json.ok, true);
  const overlap = await createRide(env, {
    customer_id: "cus_grace",
    from: "Gent",
    to: "Antwerpen",
    pickup_iso: "2026-09-11T10:30:00.000Z",
    duration_min: 60,
    assigned_driver_id: "drv_1",
  }, { idempotencyKey: "drv-overlap" });
  assert.equal(overlap.res.status, 409);
  assert.equal(overlap.json.error, "assignment_overlap");

  const unknown = await checkAssignmentOverlap(env, {
    scope: { tenant_id: TENANT_A, company_id: COMPANY_A },
    driverId: "drv_1",
    pickupIso: "2026-09-11T18:00:00.000Z",
    durationMin: null,
  });
  assert.equal(unknown.ok, false);
  assert.equal(unknown.error, "assignment_availability_unknown");
});

test("overlap past the first 24 index items is not treated as available", async () => {
  const kv = countingKV();
  const env = envWith(kv);
  const items = [];
  for (let i = 0; i < 24; i += 1) {
    const id = `agb_old_${String(i).padStart(2, "0")}`;
    const pickupIso = `2026-08-01T${String(8 + (i % 8)).padStart(2, "0")}:00:00.000Z`;
    items.push({ booking_id: id, pickup_iso: pickupIso, duration_min: 30 });
    kv.store.set(
      `booking:${id}`,
      JSON.stringify({
        booking_id: id,
        status: "PENDING",
        pickup_iso: pickupIso,
        duration_min: 30,
      }),
    );
  }
  items.push({
    booking_id: "agb_conflict_25",
    pickup_iso: "2026-09-11T10:00:00.000Z",
    duration_min: 60,
  });
  kv.store.set(
    "booking:agb_conflict_25",
    JSON.stringify({
      booking_id: "agb_conflict_25",
      status: "PENDING",
      pickup_iso: "2026-09-11T10:00:00.000Z",
      duration_min: 60,
    }),
  );
  kv.store.set(
    driverScopedBookingsIndexKey(
      { tenant_id: TENANT_A, company_id: COMPANY_A },
      "drv_1",
    ),
    JSON.stringify({ items }),
  );
  const result = await checkAssignmentOverlap(env, {
    scope: { tenant_id: TENANT_A, company_id: COMPANY_A },
    driverId: "drv_1",
    pickupIso: "2026-09-11T10:15:00.000Z",
    durationMin: 45,
  });
  assert.equal(result.ok, false);
  assert.equal(result.error, "assignment_overlap");
  assert.equal(result.booking_id, "agb_conflict_25");
});

test("concurrent assign with a stale revision is rejected", async () => {
  const kv = countingKV();
  const env = envWith(kv);
  const created = await createRide(env, {
    customer_id: "cus_ada",
    from: "Gent",
    to: "Brussel",
    pickup_iso: "2026-09-11T16:00:00.000Z",
    duration_min: 45,
  }, { idempotencyKey: "rev-base" });
  assert.equal(created.json.ok, true);
  const bookingId = created.json.booking_id;
  const first = await assignAgendaRide(env, {
    scope: { tenant_id: TENANT_A, company_id: COMPANY_A },
    bookingId,
    body: { assigned_driver_id: "drv_1", revision: 1 },
  });
  assert.equal(first.ok, true, JSON.stringify(first));
  const stale = await assignAgendaRide(env, {
    scope: { tenant_id: TENANT_A, company_id: COMPANY_A },
    bookingId,
    body: { assigned_driver_id: "drv_2", revision: 1 },
  });
  assert.equal(stale.ok, false);
  assert.equal(stale.error, "revision_conflict");
});

test("planned ride keeps service bags wait and flight", async () => {
  const kv = countingKV();
  const env = envWith(kv);
  const created = await createRide(env, {
    customer_id: "cus_ada",
    customer_name: "Ada Lovelace",
    from: "Gent",
    to: "Brussel Airport",
    pickup_iso: "2026-09-11T10:00:00.000Z",
    passengers: 2,
    note: "Publieke ritopmerking",
    ride_options: {
      service: "airport",
      tier: "premium",
      bags: 2,
      wait_min: 20,
      flight_number: "sn204",
      airport_direction: "to_airport",
      meet_and_greet: true,
      name_board: "ADA",
    },
  }, { idempotencyKey: "ride-options" });
  assert.equal(created.res.status, 201, JSON.stringify(created.json));
  assert.equal(created.json.item.tier, "premium");
  assert.equal(created.json.item.bags, 2);
  assert.equal(created.json.item.wait_min, 20);
  assert.equal(created.json.item.flight_number, "SN204");
  assert.equal(created.json.item.meet_and_greet, true);
  assert.equal(created.json.item.name_board, "ADA");
  const booking = JSON.parse(kv.store.get(`booking:${created.json.booking_id}`));
  assert.equal(booking.booking.tier, "premium");
  assert.equal(booking.booking.bags, 2);
  assert.equal(booking.booking.note, "Publieke ritopmerking");
  assert.equal(booking.booking.inputs.flight_number, "SN204");
});

test("split_no_wait lists two linked rides and keeps the gap free", async () => {
  const kv = countingKV();
  const env = envWith(kv);
  const created = await createRide(env, {
    customer_id: "cus_ada",
    from: "Gent",
    to: "Antwerpen",
    pickup_iso: "2026-09-18T08:00:00.000Z",
    duration_min: 40,
    return_enabled: true,
    roundtrip_dispatch_mode: "split_no_wait",
    return_pickup_iso: "2026-09-18T14:00:00.000Z",
    return_from: "Antwerpen",
    return_to: "Gent",
    return_duration_min: 40,
    assigned_driver_id: "drv_1",
  }, { idempotencyKey: "split-same" });
  assert.equal(created.res.status, 201, JSON.stringify(created.json));
  assert.equal(created.json.items.length, 2);
  const listed = await adminRequest(
    env,
    "/company/agenda/rides?from=2026-09-18T00:00:00.000Z&to=2026-09-19T00:00:00.000Z",
  );
  const json = await listed.json();
  const split = json.items.filter((row) => row.booking_id === created.json.booking_id);
  assert.equal(split.length, 2);
  assert.equal(split.some((row) => row.leg_type === "outbound"), true);
  assert.equal(split.some((row) => row.leg_type === "return"), true);
  const between = await createRide(env, {
    customer_id: "cus_grace",
    from: "Brussel",
    to: "Leuven",
    pickup_iso: "2026-09-18T10:30:00.000Z",
    duration_min: 40,
    assigned_driver_id: "drv_1",
  }, { idempotencyKey: "split-gap" });
  assert.equal(between.res.status, 201, JSON.stringify(between.json));
});

test("continuous_wait rejects a conflicting assignment in the wait gap", async () => {
  const kv = countingKV();
  const env = envWith(kv);
  const created = await createRide(env, {
    customer_id: "cus_ada",
    from: "Gent",
    to: "Brussel",
    pickup_iso: "2026-09-19T08:00:00.000Z",
    duration_min: 45,
    return_enabled: true,
    roundtrip_dispatch_mode: "continuous_wait",
    return_pickup_iso: "2026-09-19T11:00:00.000Z",
    return_from: "Brussel",
    return_to: "Gent",
    return_duration_min: 40,
    assigned_driver_id: "drv_wait",
  }, { idempotencyKey: "cont-wait" });
  assert.equal(created.res.status, 201, JSON.stringify(created.json));
  assert.equal(created.json.items.length, 1);
  const conflict = await createRide(env, {
    customer_id: "cus_grace",
    from: "Leuven",
    to: "Mechelen",
    pickup_iso: "2026-09-19T09:30:00.000Z",
    duration_min: 30,
    assigned_driver_id: "drv_wait",
  }, { idempotencyKey: "cont-conflict" });
  assert.equal(conflict.res.status, 409);
  assert.equal(conflict.json.error, "assignment_overlap");
});

test("return on another day appears on that date only", async () => {
  const kv = countingKV();
  const env = envWith(kv);
  const created = await createRide(env, {
    customer_id: "cus_ada",
    from: "Gent",
    to: "Antwerpen",
    pickup_iso: "2026-09-19T16:00:00.000Z",
    duration_min: 50,
    return_enabled: true,
    roundtrip_dispatch_mode: "split_no_wait",
    return_pickup_iso: "2026-09-20T08:00:00.000Z",
    return_from: "Antwerpen",
    return_to: "Gent",
    return_duration_min: 50,
  }, { idempotencyKey: "other-day" });
  assert.equal(created.res.status, 201, JSON.stringify(created.json));
  const saturday = await adminRequest(
    env,
    "/company/agenda/rides?from=2026-09-19T00:00:00.000Z&to=2026-09-20T00:00:00.000Z",
  );
  const sunday = await adminRequest(
    env,
    "/company/agenda/rides?from=2026-09-20T00:00:00.000Z&to=2026-09-21T00:00:00.000Z",
  );
  const sat = (await saturday.json()).items.filter((row) => row.booking_id === created.json.booking_id);
  const sun = (await sunday.json()).items.filter((row) => row.booking_id === created.json.booking_id);
  assert.equal(sat.length, 1);
  assert.equal(sat[0].leg_type, "outbound");
  assert.equal(sun.length, 1);
  assert.equal(sun[0].leg_type, "return");
});

test("reschedule of one split leg leaves the other pickup unchanged", async () => {
  const kv = countingKV();
  const env = envWith(kv);
  const created = await createRide(env, {
    customer_id: "cus_ada",
    from: "Gent",
    to: "Brussel",
    pickup_iso: "2026-09-18T08:00:00.000Z",
    duration_min: 40,
    return_enabled: true,
    roundtrip_dispatch_mode: "split_no_wait",
    return_pickup_iso: "2026-09-18T14:00:00.000Z",
    return_duration_min: 40,
  }, { idempotencyKey: "resched-leg" });
  const moved = await rescheduleAgendaRide(env, {
    scope: { tenant_id: TENANT_A, company_id: COMPANY_A },
    bookingId: created.json.booking_id,
    body: {
      pickup_iso: "2026-09-18T09:00:00.000Z",
      leg_type: "outbound",
      revision: 1,
    },
  });
  assert.equal(moved.ok, true, JSON.stringify(moved));
  const record = JSON.parse(kv.store.get(`booking:${created.json.booking_id}`));
  assert.equal(record.pickup_iso, "2026-09-18T09:00:00.000Z");
  assert.equal(record.return_pickup_iso, "2026-09-18T14:00:00.000Z");
});

test("cancelling one split leg keeps the other ride and frees that occupancy", async () => {
  const kv = countingKV();
  const env = envWith(kv);
  const created = await createRide(env, {
    customer_id: "cus_ada",
    from: "Gent",
    to: "Brussel",
    pickup_iso: "2026-09-17T08:00:00.000Z",
    duration_min: 40,
    return_enabled: true,
    roundtrip_dispatch_mode: "split_no_wait",
    return_pickup_iso: "2026-09-17T14:00:00.000Z",
    return_from: "Brussel",
    return_to: "Gent",
    return_duration_min: 40,
    assigned_driver_id: "drv_1",
  }, { idempotencyKey: "cancel-one-leg" });
  assert.equal(created.res.status, 201, JSON.stringify(created.json));
  const bookingId = created.json.booking_id;
  const stored = JSON.parse(kv.store.get(`booking:${bookingId}`));
  stored.progress_state = "partially_cancelled";
  stored.progressState = "partially_cancelled";
  stored.operational_legs = stored.operational_legs.map((leg) =>
    String(leg.leg_type) === "return"
      ? { ...leg, status: "CANCELLED", lifecycle: "cancelled" }
      : leg,
  );
  kv.store.set(`booking:${bookingId}`, JSON.stringify(stored));
  const listed = await adminRequest(
    env,
    "/company/agenda/rides?from=2026-09-17T00:00:00.000Z&to=2026-09-18T00:00:00.000Z",
  );
  const json = await listed.json();
  const remaining = json.items.filter((row) => row.booking_id === bookingId);
  assert.equal(remaining.length, 1);
  assert.equal(remaining[0].leg_type, "outbound");
  const freed = await createRide(env, {
    customer_id: "cus_grace",
    from: "Leuven",
    to: "Mechelen",
    pickup_iso: "2026-09-17T14:00:00.000Z",
    duration_min: 40,
    assigned_driver_id: "drv_1",
  }, { idempotencyKey: "cancel-one-leg-gap" });
  assert.equal(freed.res.status, 201, JSON.stringify(freed.json));
});
