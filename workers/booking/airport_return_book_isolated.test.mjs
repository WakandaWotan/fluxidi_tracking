// AIRPORT-RETURN-ASSIGNMENT-P0 — isolated POST /book for a split airport round trip.
// Real Worker handlers, in-memory KV, mocked Mapbox. No live POST, no mail,
// no calendar, no deploy.
//
// Run:
//   node --test workers/booking/airport_return_book_isolated.test.mjs

import { describe, test } from "node:test";
import assert from "node:assert/strict";

import worker, { FleetAllocatorDO } from "./fluxidi_booking_worker.js";
import { enrichBookingRecordOperationalLegsForReadModel } from "./modules/booking_read_model.js";
import { upsertCompanyRegistryEntry } from "./modules/company_registry_index.mjs";

const ADMIN = "p0-airport-return-admin";
const TENANT = "TA";
const COMPANY = "CA";
const CADILLAC = "vh_cadillac";
const TESLA = "vh_tesla";
const WOTAN = "drv_wotan";
const TESLA_DRIVER = "drv_tesla";
const PUBLIC_PARTNER = `company:${TENANT}:${COMPANY}`;
const DEPOT = {
  lat: 50.8241,
  lng: 3.6408,
  address: "Koekamerstraat 48A, 9688 Schorisse",
};

function upcomingBrusselsFridayYmd() {
  for (let dayOffset = 1; dayOffset <= 21; dayOffset += 1) {
    const instant = new Date(Date.now() + dayOffset * 86400000);
    const parts = new Intl.DateTimeFormat("en-US", {
      timeZone: "Europe/Brussels",
      weekday: "short",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).formatToParts(instant);
    const value = (type) => parts.find((part) => part.type === type)?.value;
    if (value("weekday") === "Fri") {
      return `${value("year")}-${value("month")}-${value("day")}`;
    }
  }
  throw new Error("no upcoming Brussels Friday");
}

// Same conversion handleBooking uses (brusselsIsoFromDateTime). Isolated
// tests run on the developer clock; the Worker in Cloudflare is UTC.
function workerBrusselsIso(ymd, hm) {
  const [year, month, day] = ymd.split("-").map(Number);
  const [hour, minute] = hm.split(":").map(Number);
  const dt = new Date(year, month - 1, day, hour || 0, minute || 0, 0, 0);
  const fmt = new Intl.DateTimeFormat("en-US", {
    timeZone: "Europe/Brussels",
    hour12: false,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  });
  const parts = fmt.formatToParts(dt).reduce((acc, part) => {
    acc[part.type] = part.value;
    return acc;
  }, {});
  const asIfUtc = Date.UTC(
    Number(parts.year),
    Number(parts.month) - 1,
    Number(parts.day),
    Number(parts.hour),
    Number(parts.minute),
    Number(parts.second),
  );
  return new Date(dt.getTime() - (asIfUtc - dt.getTime())).toISOString();
}

// Next Friday in Brussels. Outbound 11:00 and return 15:00 sit inside both
// rosters; 19:00 is past the Tesla office roster.
const BOOKING_YMD = upcomingBrusselsFridayYmd();
const OUTBOUND_ISO = workerBrusselsIso(BOOKING_YMD, "11:00");
const RETURN_ISO = workerBrusselsIso(BOOKING_YMD, "15:00");
const LATE_RETURN_ISO = workerBrusselsIso(BOOKING_YMD, "19:00");

function memoryKV(seed = {}) {
  const store = new Map();
  for (const [key, value] of Object.entries(seed)) {
    store.set(key, typeof value === "string" ? value : JSON.stringify(value));
  }
  return {
    store,
    async get(key, opts) {
      if (!store.has(key)) return null;
      const raw = store.get(key);
      const asJson = opts === "json" || (opts && opts.type === "json");
      if (!asJson) return raw;
      try {
        return JSON.parse(raw);
      } catch {
        return null;
      }
    },
    async put(key, val) {
      store.set(key, val);
    },
    async delete(key) {
      store.delete(key);
    },
    async list({ prefix = "" } = {}) {
      const keys = [...store.keys()]
        .filter((name) => (prefix ? name.startsWith(prefix) : true))
        .map((name) => ({ name }));
      return { keys, list_complete: true };
    },
  };
}

function wideRoster() {
  const day = [{ start: "07:00", end: "22:00" }];
  return {
    timezone: "Europe/Brussels",
    explicitly_set: true,
    days: { mon: day, tue: day, wed: day, thu: day, fri: day, sat: [], sun: [] },
  };
}

function officeRoster() {
  const day = [{ start: "09:00", end: "17:00" }];
  return {
    timezone: "Europe/Brussels",
    explicitly_set: true,
    days: { mon: day, tue: day, wed: day, thu: day, fri: day, sat: [], sun: [] },
  };
}

/** Two active vehicles, each with its own on-duty driver. */
function seedFleet(kv) {
  kv.store.set(
    `tenant:${TENANT}:company:${COMPANY}:drivers:index:v1`,
    JSON.stringify({
      drivers: {
        [WOTAN]: {
          driver_id: WOTAN,
          display_name: "Wotan",
          public_display_name: "Wotan",
          public_profile_enabled: true,
          is_active: true,
          availability_status: "available",
          assigned_vehicle_id: CADILLAC,
          weekly_roster: wideRoster(),
        },
        [TESLA_DRIVER]: {
          driver_id: TESLA_DRIVER,
          display_name: "Christophe",
          public_display_name: "Christophe",
          public_profile_enabled: true,
          is_active: true,
          availability_status: "available",
          assigned_vehicle_id: TESLA,
          weekly_roster: officeRoster(),
        },
      },
    }),
  );
  kv.store.set(
    `tenant:${TENANT}:company:${COMPANY}:fleet:vehicles:v1`,
    JSON.stringify({
      vehicles: [
        {
          vehicle_id: CADILLAC,
          name: "Cadillac",
          is_active: true,
          assigned_driver_id: WOTAN,
          assigned_driver: { driver_id: WOTAN, name: "Wotan" },
          passenger_capacity: 4,
          luggage_capacity: 4,
          base_lat: DEPOT.lat,
          base_lng: DEPOT.lng,
          base_address: DEPOT.address,
          current_lat: DEPOT.lat,
          current_lng: DEPOT.lng,
        },
        {
          vehicle_id: TESLA,
          name: "Tesla",
          is_active: true,
          assigned_driver_id: TESLA_DRIVER,
          assigned_driver: { driver_id: TESLA_DRIVER, name: "Christophe" },
          passenger_capacity: 4,
          luggage_capacity: 4,
          base_lat: DEPOT.lat,
          base_lng: DEPOT.lng,
          base_address: DEPOT.address,
          current_lat: DEPOT.lat,
          current_lng: DEPOT.lng,
        },
      ],
    }),
  );
}

async function seedPublicPartner(kv) {
  kv.store.set(
    "public:partners:booking-routes:v2",
    JSON.stringify({
      routes: [
        {
          partner_id: PUBLIC_PARTNER,
          tenant_id: TENANT,
          company_id: COMPANY,
          company_name: "Fluxidi Isolated",
          is_active: true,
          subscription_status: "active",
        },
      ],
    }),
  );
  kv.store.set(
    "public:partners:profiles:v2",
    JSON.stringify({
      profiles: [
        {
          partner_id: PUBLIC_PARTNER,
          company_id: COMPANY,
          tenant_id: TENANT,
          company_name: "Fluxidi Isolated",
          profile_enabled: true,
          is_active: true,
          published_at: "2026-09-01T00:00:00.000Z",
        },
      ],
    }),
  );
  await upsertCompanyRegistryEntry(kv, {
    company_code: "FLX-00099",
    display_name: "Fluxidi Isolated",
    environment_class: "unknown",
    lifecycle_status: "active",
  });
  kv.store.set(
    "company_link:index:code:FLX-00099:v1",
    JSON.stringify({
      company_code: "FLX-00099",
      tenant_id: TENANT,
      company_id: COMPANY,
      display_name: "Fluxidi Isolated",
      linking_enabled: true,
    }),
  );
  const now = new Date().toISOString();
  kv.store.set(
    `tenant:${TENANT}:company:${COMPANY}:booking:demand:index:v1`,
    JSON.stringify({
      tenant_id: TENANT,
      company_id: COMPANY,
      updated_at: now,
      index_updated_at: now,
      count: 0,
      active_count: 0,
      empty: true,
      demand_index_empty: true,
      demand_index_marker_version: 1,
      items: [],
    }),
  );
}

/** In-memory Durable Object storage, enough for the real FleetAllocatorDO. */
function memoryDurableState() {
  const store = new Map();
  return {
    storage: {
      async get(key) {
        if (Array.isArray(key)) {
          const out = new Map();
          for (const name of key) if (store.has(name)) out.set(name, store.get(name));
          return out;
        }
        return store.has(key) ? store.get(key) : undefined;
      },
      async put(key, value) {
        if (key && typeof key === "object" && value === undefined) {
          for (const [name, val] of Object.entries(key)) store.set(name, val);
          return;
        }
        store.set(key, value);
      },
      async delete(key) {
        if (Array.isArray(key)) {
          let count = 0;
          for (const name of key) if (store.delete(name)) count += 1;
          return count;
        }
        return store.delete(key);
      },
      async list({ prefix = "" } = {}) {
        const out = new Map();
        for (const [name, value] of store.entries()) {
          if (!prefix || name.startsWith(prefix)) out.set(name, value);
        }
        return out;
      },
      async deleteAll() {
        store.clear();
      },
    },
    async blockConcurrencyWhile(fn) {
      return fn();
    },
  };
}

/** The real allocator Durable Object, held in memory per scope key. */
function fleetAllocatorNamespace(envRef) {
  const instances = new Map();
  const calls = [];
  return {
    calls,
    idFromName: (name) => name,
    get(name) {
      if (!instances.has(name)) {
        instances.set(name, new FleetAllocatorDO(memoryDurableState(), envRef.current));
      }
      const instance = instances.get(name);
      return {
        // Cloudflare's DO stub accepts fetch(url, init) and delivers a Request.
        fetch: async (input, init) => {
          const request = input instanceof Request ? input : new Request(input, init);
          const body = await request.clone().json().catch(() => ({}));
          calls.push({
            scope: String(name),
            action: String(body?.action || ""),
            booking_id: String(body?.booking_id || ""),
            required_vehicle_id: String(body?.required_vehicle_id || ""),
            pickup_iso: String(body?.pickup_iso || ""),
            pickup_ms: Number(body?.pickup_ms),
            pax: Number(body?.pax),
            bags: Number(body?.bags),
            tenant_id: String(body?.tenant_id || body?.tenantScope?.tenant_id || ""),
            company_id: String(body?.company_id || body?.tenantScope?.company_id || ""),
          });
          return instance.fetch(request);
        },
      };
    },
  };
}

function envWith(kv) {
  let seq = 0;
  const sequence = (label) => ({
    idFromName: (name) => name,
    get() {
      return {
        fetch: async () => {
          seq += 1;
          const value = `${label}-${String(seq).padStart(3, "0")}`;
          return new Response(
            JSON.stringify({
              ok: true,
              public_booking_reference: value,
              document_reference: value,
            }),
            { status: 200 },
          );
        },
      };
    },
  });
  const envRef = { current: null };
  const env = {
    ADMIN_TOKEN: ADMIN,
    BOOKING_KV: kv,
    MAPBOX_TOKEN: "test-mapbox",
    // Same fleet mode as the production release config.
    FLEET_AVAILABILITY_MODE: "multi_vehicle",
    FLEET_ALLOCATOR: fleetAllocatorNamespace(envRef),
    BOOKING_REFERENCE_SEQUENCE: sequence("FLX-ISO"),
    DOCUMENT_REFERENCE_SEQUENCE: sequence("DOC-ISO"),
  };
  envRef.current = env;
  return env;
}

/** Mapbox only. Every other outbound call is recorded and refused. */
function isolatedFetch() {
  const calls = { geocode: 0, geocodeQueries: [], directions: 0, other: [] };
  const fn = async (input, init) => {
    const url = String(input && input.url ? input.url : input);
    if (url.includes("/geocoding/")) {
      calls.geocode += 1;
      // Echo the asked address so the worker's own street/house-number guard
      // accepts the stub, exactly like a real Mapbox answer would.
      const query = decodeURIComponent(
        String(url).split("/mapbox.places/")[1]?.split(".json")[0] || "",
      );
      calls.geocodeQueries.push(query);
      const center = /airport|zaventem/i.test(query)
        ? [4.4844, 50.9014]
        : [3.6408, 50.8241];
      return new Response(
        JSON.stringify({
          features: [
            {
              center,
              place_name: query,
              text: query.split(",")[0],
              relevance: 1,
              place_type: ["address"],
            },
          ],
        }),
        { status: 200 },
      );
    }
    if (url.includes("/directions/")) {
      calls.directions += 1;
      return new Response(
        JSON.stringify({
          code: "Ok",
          routes: [
            { distance: 40600, duration: 2460, legs: [{ distance: 40600, duration: 2460 }] },
          ],
        }),
        { status: 200 },
      );
    }
    calls.other.push({ url, method: String((init && init.method) || "GET").toUpperCase() });
    return new Response("unmocked", { status: 500 });
  };
  fn.calls = calls;
  return fn;
}

function airportRoundTripBody(overrides = {}) {
  return {
    public_partner_id: PUBLIC_PARTNER,
    tenant_id: TENANT,
    company_id: COMPANY,
    service: "airport",
    airport_iata: "BRU",
    airport_direction: "to_airport",
    from: "Koekamerstraat 48A, 9688 Schorisse",
    to: "Brussels Airport, Zaventem",
    from_lat: 50.8241,
    from_lng: 3.6408,
    to_lat: 50.9014,
    to_lng: 4.4844,
    pickup_lat: 50.8241,
    pickup_lon: 3.6408,
    dropoff_lat: 50.9014,
    dropoff_lon: 4.4844,
    date: BOOKING_YMD,
    time: "11:00",
    pickup_iso: OUTBOUND_ISO,
    pax: 2,
    bags: 1,
    wait_min: 0,
    name: "Isolated Probe",
    phone: "+32470000000",
    // Outbound choice
    vehicle_id: CADILLAC,
    preferred_vehicle_id: CADILLAC,
    assigned_driver_id: WOTAN,
    // Return choice: another car and another driver
    return_enabled: true,
    return_kind: "noWait",
    return_from: "Brussels Airport, Zaventem",
    return_to: "Koekamerstraat 48A, 9688 Schorisse",
    return_from_lat: 50.9014,
    return_from_lng: 4.4844,
    return_to_lat: 50.8241,
    return_to_lng: 3.6408,
    return_date: BOOKING_YMD,
    return_time: "15:00",
    return_pickup_iso: RETURN_ISO,
    return_vehicle_id: TESLA,
    preferred_return_vehicle_id: TESLA,
    return_assigned_driver_id: TESLA_DRIVER,
    payment_method: "cash",
    payment_mode: "in_vehicle",
    idempotency_key: "iso-airport-return-20260918-1100",
    ...overrides,
  };
}

let bookGate = Promise.resolve();

async function bookOnce(body) {
  let release;
  const previous = bookGate;
  bookGate = new Promise((resolve) => {
    release = resolve;
  });
  await previous;
  const kv = memoryKV();
  seedFleet(kv);
  await seedPublicPartner(kv);
  const env = envWith(kv);
  const stub = isolatedFetch();
  const original = globalThis.fetch;
  globalThis.fetch = stub;
  try {
    const res = await worker.fetch(
      new Request("https://example.test/book", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      }),
      env,
      {},
    );
    const json = await res.json();
    const bookingKeys = [...kv.store.keys()].filter((key) => /^booking:/.test(key));
    return { res, json, kv, stub, bookingKeys, allocatorCalls: env.FLEET_ALLOCATOR.calls };
  } finally {
    globalThis.fetch = original;
    release();
  }
}

function legOf(legs, type) {
  return (legs || []).find(
    (leg) => String(leg?.leg_type ?? leg?.legType ?? "").toLowerCase() === type,
  );
}

function outboundCallsOtherThanMapbox(stub) {
  return stub.calls.other;
}

describe("airport return book isolated", { concurrency: 1 }, () => {
// ---------------------------------------------------------------------------
// Positive: two legs, two cars, two drivers
// ---------------------------------------------------------------------------

test("split airport round trip books once and assigns each leg its own car and driver", async () => {
  const { res, json, kv, stub, bookingKeys, allocatorCalls } = await bookOnce(
    airportRoundTripBody(),
  );

  // 1) accepted
  assert.equal(res.status, 200, JSON.stringify(json));
  assert.equal(json.ok, true, JSON.stringify(json));
  const bookingId = json.booking_id;
  assert.ok(bookingId, "a booking id is returned");

  const allocateCalls = (allocatorCalls || []).filter((call) => call.action === "allocate");
  assert.equal(
    allocateCalls.length,
    2,
    `allocator saw two allocate actions: ${JSON.stringify(allocatorCalls)}`,
  );
  assert.equal(allocateCalls[0].required_vehicle_id, CADILLAC);
  assert.equal(allocateCalls[1].required_vehicle_id, TESLA);
  assert.notEqual(
    allocateCalls[0].required_vehicle_id,
    allocateCalls[1].required_vehicle_id,
    "the return pin is not a copy of the outbound pin",
  );
  assert.equal(safeIso(allocateCalls[0].pickup_iso), OUTBOUND_ISO);
  assert.equal(safeIso(allocateCalls[1].pickup_iso), RETURN_ISO);
  assert.equal(allocateCalls[0].tenant_id, TENANT);
  assert.equal(allocateCalls[0].company_id, COMPANY);

  // 2 & 12) exactly one parent booking record, no surprise extra record
  const parentKeys = bookingKeys.filter((key) => !/:/.test(key.slice("booking:".length)));
  assert.equal(
    parentKeys.length,
    1,
    `exactly one parent booking record: ${JSON.stringify(bookingKeys)}`,
  );
  const record = JSON.parse(kv.store.get(parentKeys[0]));
  assert.equal(
    parentKeys[0],
    `booking:${bookingId}`,
    "the persisted record is the returned booking",
  );

  // 3) two operational legs
  const legs = record.operational_legs || record.booking?.operational_legs || [];
  assert.equal(legs.length, 2, `two legs: ${JSON.stringify(legs.map((l) => l.leg_type))}`);
  const outbound = legOf(legs, "outbound");
  const inbound = legOf(legs, "return");
  assert.ok(outbound && inbound, "both an outbound and a return leg exist");

  // 4) outbound holds only the chosen outbound car and driver
  assert.equal(outbound.assigned_vehicle_id, CADILLAC);
  assert.equal(outbound.assigned_driver_id, WOTAN);

  // 5) return holds only the chosen return car and driver
  assert.equal(inbound.assigned_vehicle_id, TESLA);
  assert.equal(inbound.assigned_driver_id, TESLA_DRIVER);

  // 6) no copy of the outbound assignment onto the return leg
  assert.notEqual(inbound.assigned_vehicle_id, outbound.assigned_vehicle_id);
  assert.notEqual(inbound.assigned_driver_id, outbound.assigned_driver_id);

  // 7) the return leg carries the return moment
  assert.equal(
    safeIso(inbound.pickup_iso ?? inbound.pickupIso),
    RETURN_ISO,
    JSON.stringify({ pickup: inbound.pickup_iso, expected: RETURN_ISO }),
  );
  assert.equal(safeIso(outbound.pickup_iso ?? outbound.pickupIso), OUTBOUND_ISO);

  // 8) canonical return fields on the parent booking
  const parent = record.booking && typeof record.booking === "object" ? record.booking : record;
  assert.equal(parent.return_enabled, true);
  assert.equal(parent.return_vehicle_id ?? record.return_vehicle_id, TESLA);
  assert.equal(parent.return_assigned_driver_id ?? record.return_assigned_driver_id, TESLA_DRIVER);
  assert.equal(
    safeIso(parent.return_pickup_iso ?? parent.returnPickupIso ?? record.return_pickup_iso),
    RETURN_ISO,
  );
  assert.equal(
    parent.customer_requested_return_vehicle_id ?? record.customer_requested_return_vehicle_id,
    TESLA,
    "the requested return choice is stored next to the confirmed one",
  );

  // 9) assignment_by_leg in the /book response
  assert.ok(json.assignment_by_leg, JSON.stringify(json).slice(0, 400));
  assert.deepEqual(json.assignment_by_leg.outbound, {
    vehicle_id: CADILLAC,
    driver_id: WOTAN,
  });
  assert.deepEqual(json.assignment_by_leg.return, {
    vehicle_id: TESLA,
    driver_id: TESLA_DRIVER,
  });

  // 10) dispatch mode
  assert.equal(json.roundtrip_dispatch_mode, "split_no_wait");
  assert.equal(
    record.roundtrip_dispatch_mode ?? record.booking?.roundtrip_dispatch_mode,
    "split_no_wait",
  );

  // 11) the read model returns both legs with their own assignment
  const readModel = JSON.parse(JSON.stringify(record));
  enrichBookingRecordOperationalLegsForReadModel(readModel, bookingId);
  const readLegs = readModel.operational_legs || [];
  assert.equal(readLegs.length, 2, JSON.stringify(readLegs.map((l) => l.leg_type)));
  assert.equal(legOf(readLegs, "outbound").assigned_vehicle_id, CADILLAC);
  assert.equal(legOf(readLegs, "outbound").assigned_driver_id, WOTAN);
  assert.equal(legOf(readLegs, "return").assigned_vehicle_id, TESLA);
  assert.equal(legOf(readLegs, "return").assigned_driver_id, TESLA_DRIVER);

  // 13) mail and calendar follow the existing round-trip behaviour: no calendar
  // is configured here, and nothing is sent twice.
  const other = outboundCallsOtherThanMapbox(stub);
  const calendarCalls = other.filter((call) => /googleapis|calendar/i.test(call.url));
  assert.equal(calendarCalls.length, 0, JSON.stringify(calendarCalls));
  const mailCalls = other.filter((call) => /mail|resend|sendgrid|postmark|smtp/i.test(call.url));
  assert.ok(mailCalls.length <= 1, `owner mail is attempted at most once: ${JSON.stringify(mailCalls)}`);
  assert.equal(stub.calls.directions >= 2, true, "each leg was routed");
});

function safeIso(value) {
  const text = String(value || "");
  const ms = Date.parse(text);
  return Number.isFinite(ms) ? new Date(ms).toISOString() : text;
}

// ---------------------------------------------------------------------------
// Negative: an unusable return leg cancels the whole booking
// ---------------------------------------------------------------------------

test("an unavailable return driver fails the whole booking and stores nothing", async () => {
  // The chosen return car stays pinned, but its driver is off duty at 19:00.
  const { res, json, kv, stub, bookingKeys } = await bookOnce(
    airportRoundTripBody({
      return_time: "19:00",
      return_pickup_iso: LATE_RETURN_ISO,
      idempotency_key: "iso-airport-return-20260918-1900",
    }),
  );

  // The booking fails as a whole.
  assert.equal(json.ok === true, false, JSON.stringify(json).slice(0, 400));
  assert.notEqual(res.status, 200);

  // Zero booking persistence, so the valid outbound leg is not stored on its own.
  assert.deepEqual(bookingKeys, [], `no booking record: ${JSON.stringify(bookingKeys)}`);
  const legKeys = [...kv.store.keys()].filter((key) => /operational_leg|:legs:/.test(key));
  assert.deepEqual(legKeys, [], JSON.stringify(legKeys));

  // Zero leftover fleet reservations or vehicle occupancy for either car.
  const leftovers = [];
  for (const [key, value] of kv.store.entries()) {
    if (!/reserv|occupanc|bookings:v1|dispatch/i.test(key)) continue;
    const text = typeof value === "string" ? value : JSON.stringify(value);
    if (/iso-airport-return|FLX-ISO/.test(text)) leftovers.push(key);
  }
  assert.deepEqual(leftovers, [], `no reservation survives: ${JSON.stringify(leftovers)}`);

  // Zero owner mail, zero calendar event.
  const other = outboundCallsOtherThanMapbox(stub);
  const mailCalls = other.filter((call) => /mail|resend|sendgrid|postmark|smtp/i.test(call.url));
  const calendarCalls = other.filter((call) => /googleapis|calendar/i.test(call.url));
  assert.deepEqual(mailCalls, [], JSON.stringify(mailCalls));
  assert.deepEqual(calendarCalls, [], JSON.stringify(calendarCalls));
});
});
