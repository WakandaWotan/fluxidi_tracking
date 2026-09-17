// Isolated reproduction of the 17 Sep customer /book and planner date paths.
// No live POST. Uses the real Worker handlers and in-memory KV.
//
// Run:
//   node --test workers/booking/taxi_cadillac_book_isolated.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import worker from "./fluxidi_booking_worker.js";
import {
  NOW_PICKUP_GRACE_MS,
  rideIsSoon,
} from "./modules/company_dispatch.mjs";
import { checkAssignmentOverlap } from "./modules/company_agenda.mjs";
import {
  projectBookableVehicleOffers,
  publicBookableVehicleRows,
} from "./modules/fleet_roster_availability.mjs";
import { taxiRequestedVehicleIdFromPayload } from "./modules/required_vehicle_constraint.mjs";
import { resolveCompanyAgendaPickupIso } from "./modules/company_plan_when.mjs";
import { upsertCompanyRegistryEntry } from "./modules/company_registry_index.mjs";

const ADMIN = "p0-isolated-book-admin";
const TENANT = "TA";
const COMPANY = "CA";
const CADILLAC = "vh_cadillac";
const TESLA = "vh_tesla";
const WOTAN = "drv_wotan";
const PUBLIC_PARTNER = `company:${TENANT}:${COMPANY}`;

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

function fridayRoster() {
  return {
    timezone: "Europe/Brussels",
    explicitly_set: true,
    days: {
      mon: [{ start: "07:00", end: "22:00" }],
      tue: [{ start: "07:00", end: "22:00" }],
      wed: [{ start: "07:00", end: "22:00" }],
      thu: [{ start: "07:00", end: "22:00" }],
      fri: [{ start: "07:00", end: "22:00" }],
      sat: [],
      sun: [],
    },
  };
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
}

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
          public_photo_enabled: false,
          is_active: true,
          availability_status: "available",
          assigned_vehicle_id: CADILLAC,
          weekly_roster: fridayRoster(),
        },
        drv_tesla: {
          driver_id: "drv_tesla",
          display_name: "Tesla chauffeur",
          is_active: true,
          availability_status: "available",
          assigned_vehicle_id: TESLA,
          weekly_roster: {
            timezone: "Europe/Brussels",
            explicitly_set: true,
            days: {
              mon: [{ start: "09:00", end: "17:00" }],
              tue: [{ start: "09:00", end: "17:00" }],
              wed: [{ start: "09:00", end: "17:00" }],
              thu: [{ start: "09:00", end: "17:00" }],
              fri: [{ start: "09:00", end: "17:00" }],
              sat: [],
              sun: [],
            },
          },
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
          passenger_capacity: 3,
        },
        {
          vehicle_id: TESLA,
          name: "Tesla",
          is_active: true,
          assigned_driver_id: "drv_tesla",
          passenger_capacity: 3,
        },
      ],
    }),
  );
}

function envWith(kv) {
  let seq = 0;
  return {
    ADMIN_TOKEN: ADMIN,
    BOOKING_KV: kv,
    MAPBOX_TOKEN: "test-mapbox",
    BOOKING_REFERENCE_SEQUENCE: {
      idFromName: (name) => name,
      get() {
        return {
          fetch: async () => {
            seq += 1;
            return new Response(
              JSON.stringify({
                ok: true,
                public_booking_reference: `FLX-ISO-${String(seq).padStart(3, "0")}`,
              }),
              { status: 200 },
            );
          },
        };
      },
    },
    DOCUMENT_REFERENCE_SEQUENCE: {
      idFromName: (name) => name,
      get() {
        return {
          fetch: async () => {
            seq += 1;
            return new Response(
              JSON.stringify({
                ok: true,
                document_reference: `DOC-ISO-${String(seq).padStart(3, "0")}`,
              }),
              { status: 200 },
            );
          },
        };
      },
    },
  };
}

function mapboxFetch() {
  return async (input) => {
    const url = String(input);
    if (url.includes("/geocoding/")) {
      return new Response(
        JSON.stringify({
          features: [{ center: [3.64, 50.85], place_name: "Schorisse" }],
        }),
        { status: 200 },
      );
    }
    if (url.includes("/directions/")) {
      return new Response(
        JSON.stringify({
          code: "Ok",
          routes: [{ distance: 40600, duration: 2460, legs: [{ distance: 40600, duration: 2460 }] }],
        }),
        { status: 200 },
      );
    }
    return new Response("unmocked", { status: 500 });
  };
}

test("Nu processing delay stays soon; elapsed Later does not", () => {
  assert.ok(NOW_PICKUP_GRACE_MS >= 60 * 1000);
  const now = Date.parse("2026-09-17T17:03:08.000Z");
  assert.equal(rideIsSoon("2026-09-17T17:03:00.000Z", now), true);
  assert.equal(rideIsSoon("2026-09-17T16:00:00.000Z", now), false);
});

test("explicit Cadillac is a required taxi pin, never a Tesla substitute", () => {
  assert.equal(
    taxiRequestedVehicleIdFromPayload({
      preferred_vehicle_id: CADILLAC,
      vehicle_id: CADILLAC,
    }),
    CADILLAC,
  );
  assert.equal(taxiRequestedVehicleIdFromPayload({ pax: 2 }), "");
});

test("availability occupancy refuses Cadillac when it is already busy", async () => {
  const kv = memoryKV();
  seedFleet(kv);
  const env = envWith(kv);
  const bookingId = "agb_busy_cadillac";
  const pickupIso = "2026-09-17T20:00:00.000Z";
  await kv.put(
    `booking:${bookingId}`,
    JSON.stringify({
      booking_id: bookingId,
      pickup_iso: pickupIso,
      duration_min: 44,
      assigned_vehicle_id: CADILLAC,
      assigned_driver_id: WOTAN,
      tenant_id: TENANT,
      company_id: COMPANY,
      status: "PENDING",
      occupancy_wait_min: 45,
      return_pickup_iso: "2026-09-17T21:29:00.000Z",
      return_duration_min: 44,
      roundtrip_dispatch_mode: "continuous_wait",
    }),
  );
  await kv.put(
    `tenant:${TENANT}:company:${COMPANY}:vehicle:${CADILLAC}:bookings:v1`,
    JSON.stringify({
      items: [
        {
          booking_id: bookingId,
          pickup_iso: pickupIso,
          occupancy_end_iso: "2026-09-17T22:14:00.000Z",
        },
      ],
    }),
  );
  const overlap = await checkAssignmentOverlap(env, {
    scope: { tenant_id: TENANT, company_id: COMPANY, hasScope: true },
    driverId: WOTAN,
    vehicleId: CADILLAC,
    pickupIso: "2026-09-17T20:10:00.000Z",
    durationMin: 41,
  });
  assert.equal(overlap.ok, false);
  assert.ok(
    overlap.error === "assignment_overlap" || overlap.error === "assignment_vehicle_busy",
    JSON.stringify(overlap),
  );
});

test("GET /partners/availability applies roster and occupancy", async () => {
  const kv = memoryKV();
  seedFleet(kv);
  await seedPublicPartner(kv);
  const env = envWith(kv);
  const pickupIso = "2026-09-18T16:00:00.000Z";
  const res = await worker.fetch(
    new Request(
      `https://example.test/partners/availability?partner_id=${encodeURIComponent(PUBLIC_PARTNER)}&pickup_iso=${encodeURIComponent(pickupIso)}&pax=2&duration_min=41`,
    ),
    env,
    {},
  );
  const json = await res.json();
  assert.equal(res.status, 200, JSON.stringify(json));
  assert.equal(json.ok, true);
  const cadillac = (json.vehicles || []).find((row) => row.vehicle_id === CADILLAC);
  const tesla = (json.vehicles || []).find((row) => row.vehicle_id === TESLA);
  assert.ok(cadillac, JSON.stringify(json));
  if (tesla) {
    assert.equal(tesla.available, false);
    assert.equal(tesla.reason, "assignment_driver_outside_hours");
  }
});

test("planner Later ISO is stored as the client Friday 22:00 Brussels instant", () => {
  const iso = resolveCompanyAgendaPickupIso({
    pickup_iso: "2026-09-18T20:00:00.000Z",
  });
  assert.equal(iso, "2026-09-18T20:00:00.000Z");
  assert.notEqual(iso, "2026-09-17T20:00:00.000Z");
});

test("POST /book against isolated handlers records HTTP status and server code", async () => {
  const kv = memoryKV();
  seedFleet(kv);
  await seedPublicPartner(kv);
  const env = envWith(kv);
  const original = globalThis.fetch;
  globalThis.fetch = mapboxFetch();
  try {
    const res = await worker.fetch(
      new Request("https://example.test/book", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          public_partner_id: PUBLIC_PARTNER,
          tenant_id: TENANT,
          company_id: COMPANY,
          from: "Koekamerstraat 48A, 9688 Schorisse",
          to: "Gent",
          from_lat: 50.8241,
          from_lng: 3.6408,
          to_lat: 51.0543,
          to_lng: 3.7174,
          pickup_lat: 50.8241,
          pickup_lon: 3.6408,
          dropoff_lat: 51.0543,
          dropoff_lon: 3.7174,
          date: "2026-09-18",
          time: "18:00",
          pickup_iso: "2026-09-18T16:00:00.000Z",
          name: "Isolated Probe",
          phone: "+32470000000",
          pax: 2,
          preferred_vehicle_id: CADILLAC,
          vehicle_id: CADILLAC,
          payment_method: "cash",
          payment_mode: "in_vehicle",
          idempotency_key: "iso-cadillac-20260918-1800",
        }),
      }),
      env,
      {},
    );
    const json = await res.json();
    const stored = [...kv.store.keys()].filter((key) => key.startsWith("booking:"));
    const proof = {
      status: res.status,
      ok: json.ok === true,
      error: json.error || "",
      allocator_reason: json.availability?.allocator_reason || json.allocator_reason || "",
      persisted: stored.length,
    };
    assert.equal(res.status, 200, JSON.stringify({ ...proof, json }));
    assert.equal(json.ok, true, JSON.stringify(proof));
    assert.ok(stored.length >= 1, "successful book must persist a ride");
    const record = JSON.parse(kv.store.get(stored[0]));
    assert.equal(record.customer_requested_vehicle_id, CADILLAC);
    assert.equal(record.assigned_vehicle_id || record.vehicle_id, CADILLAC);
  } finally {
    globalThis.fetch = original;
  }
});

test("public rows keep driver_id and only already-published name/photo", () => {
  const rows = publicBookableVehicleRows(
    projectBookableVehicleOffers({
      vehicles: [
        { vehicle_id: CADILLAC, is_active: true, assigned_driver_id: WOTAN, passenger_capacity: 3 },
      ],
      drivers: [
        {
          driver_id: WOTAN,
          display_name: "Internal Wotan",
          public_display_name: "Wotan",
          public_profile_enabled: true,
          public_photo_enabled: false,
          driver_photo_url: "https://internal.example/passport.jpg",
          is_active: true,
          assigned_vehicle_id: CADILLAC,
          weekly_roster: fridayRoster(),
        },
      ],
      pickupMs: Date.parse("2026-09-18T16:00:00.000Z"),
      durationMin: 41,
      nowMs: Date.parse("2026-09-17T17:00:00.000Z"),
    }),
  );
  assert.equal(rows[0].driver_id, WOTAN);
  assert.equal(rows[0].public_display_name, "Wotan");
  assert.equal(rows[0].public_photo_url, undefined);
});

function taxiBookBody(overrides = {}) {
  return {
    public_partner_id: PUBLIC_PARTNER,
    tenant_id: TENANT,
    company_id: COMPANY,
    from: "Koekamerstraat 48A, 9688 Schorisse",
    to: "Gent",
    from_lat: 50.8241,
    from_lng: 3.6408,
    to_lat: 51.0543,
    to_lng: 3.7174,
    pickup_lat: 50.8241,
    pickup_lon: 3.6408,
    dropoff_lat: 51.0543,
    dropoff_lon: 3.7174,
    date: "2026-09-18",
    time: "18:00",
    pickup_iso: "2026-09-18T16:00:00.000Z",
    name: "Isolated Probe",
    phone: "+32470000000",
    pax: 2,
    preferred_vehicle_id: CADILLAC,
    vehicle_id: CADILLAC,
    payment_method: "cash",
    payment_mode: "in_vehicle",
    idempotency_key: "iso-cadillac-20260918-1800",
    ...overrides,
  };
}

async function postBook(env, body) {
  return worker.fetch(
    new Request("https://example.test/book", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    }),
    env,
    {},
  );
}

test("airport /book keeps the chosen Friday pickup and Cadillac", async () => {
  const kv = memoryKV();
  seedFleet(kv);
  await seedPublicPartner(kv);
  const env = envWith(kv);
  const original = globalThis.fetch;
  globalThis.fetch = mapboxFetch();
  try {
    const res = await postBook(
      env,
      taxiBookBody({
        to: "Brussels Airport, Zaventem",
        to_lat: 50.9014,
        to_lng: 4.4844,
        dropoff_lat: 50.9014,
        dropoff_lon: 4.4844,
        service: "airport",
        airport_iata: "BRU",
        airport_direction: "to_airport",
        date: "2026-09-18",
        time: "18:00",
        pickup_iso: "2026-09-18T16:00:00.000Z",
        idempotency_key: "iso-airport-20260918-1800",
      }),
    );
    const json = await res.json();
    assert.equal(res.status, 200, JSON.stringify(json));
    assert.equal(json.ok, true);
    const stored = [...kv.store.keys()].filter((key) => key.startsWith("booking:"));
    const record = JSON.parse(kv.store.get(stored[0]));
    assert.equal(record.pickup_iso || record.booking?.pickup_iso, "2026-09-18T16:00:00.000Z");
    assert.equal(record.customer_requested_vehicle_id, CADILLAC);
  } finally {
    globalThis.fetch = original;
  }
});

test("planner agenda create stores Friday 22:00 Brussels, not Thursday", async () => {
  const kv = memoryKV();
  seedFleet(kv);
  const env = envWith(kv);
  const res = await worker.fetch(
    new Request("https://example.test/company/agenda/rides", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-admin-token": ADMIN,
        "Idempotency-Key": "iso-planner-fri-2200",
      },
      body: JSON.stringify({
        tenant_id: TENANT,
        company_id: COMPANY,
        customer_id: "cus_iso_planner",
        customer_name: "Planner Isolated",
        from: "Koekamerstraat 48A, 9688 Maarkedal",
        to: "Kuurne",
        pickup_iso: "2026-09-18T20:00:00.000Z",
        duration_min: 44,
        wait_min: 45,
        return_enabled: true,
        roundtrip_dispatch_mode: "continuous_wait",
        return_pickup_iso: "2026-09-18T21:29:00.000Z",
        return_duration_min: 44,
        assigned_driver_id: WOTAN,
        assigned_vehicle_id: CADILLAC,
      }),
    }),
    env,
    {},
  );
  const json = await res.json();
  assert.equal(res.status, 201, JSON.stringify(json));
  const pickup = json.item?.pickup_iso || json.items?.[0]?.pickup_iso;
  assert.equal(pickup, "2026-09-18T20:00:00.000Z");
  assert.notEqual(pickup, "2026-09-17T20:00:00.000Z");
  const listed = await worker.fetch(
    new Request(
      `https://example.test/company/agenda/rides?tenant_id=${TENANT}&company_id=${COMPANY}&from=2026-09-18T00:00:00.000Z&to=2026-09-19T00:00:00.000Z`,
      { headers: { "x-admin-token": ADMIN } },
    ),
    env,
    {},
  );
  const listJson = await listed.json();
  const found = (listJson.items || []).find((row) => row.pickup_iso === "2026-09-18T20:00:00.000Z");
  assert.ok(found, JSON.stringify(listJson));
});

test("identical /book replay does not create a second ride", async () => {
  const kv = memoryKV();
  seedFleet(kv);
  await seedPublicPartner(kv);
  const env = envWith(kv);
  const original = globalThis.fetch;
  globalThis.fetch = mapboxFetch();
  try {
    const first = await postBook(env, taxiBookBody());
    const firstJson = await first.json();
    assert.equal(first.status, 200, JSON.stringify(firstJson));
    const second = await postBook(env, taxiBookBody());
    const secondJson = await second.json();
    assert.equal(second.ok !== false, true, JSON.stringify(secondJson));
    const stored = [...kv.store.keys()].filter((key) => key.startsWith("booking:"));
    assert.equal(stored.length, 1, stored.join(","));
  } finally {
    globalThis.fetch = original;
  }
});

test("book without coordinates returns a concrete geocode status, not a silent persist", async () => {
  const kv = memoryKV();
  seedFleet(kv);
  await seedPublicPartner(kv);
  const env = envWith(kv);
  const original = globalThis.fetch;
  globalThis.fetch = async () =>
    new Response(JSON.stringify({ features: [] }), { status: 200 });
  try {
    const res = await postBook(
      env,
      taxiBookBody({
        from_lat: undefined,
        from_lng: undefined,
        to_lat: undefined,
        to_lng: undefined,
        pickup_lat: undefined,
        pickup_lon: undefined,
        dropoff_lat: undefined,
        dropoff_lon: undefined,
        idempotency_key: "iso-geocode-miss",
      }),
    );
    const json = await res.json();
    const stored = [...kv.store.keys()].filter((key) => key.startsWith("booking:"));
    assert.ok(res.status >= 400, JSON.stringify({ status: res.status, json }));
    assert.equal(stored.length, 0);
    assert.match(String(json.error || json.code || ""), /geocode|route|mapbox/i);
  } finally {
    globalThis.fetch = original;
  }
});
