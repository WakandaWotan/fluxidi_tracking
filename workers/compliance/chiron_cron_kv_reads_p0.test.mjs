// CHIRON-CRON-KV-READS-P0
//
// Contract for the two changes this branch makes to the scheduled Chiron drain:
//
//   1. the pass-scoped leg-type map is filled ON DEMAND (one BOOKING_KV read per
//      booking that actually reaches a draft build, at most once per pass)
//      instead of pre-reading every legless booking in the 14-day window;
//   2. `CHIRON_CRON_ENABLED` is an explicit operator switch, default enabled.
//
// What must NOT change: candidate selection, ordering, the process budget, the
// already-synced budget exemption, retries, cooldowns, the duplicate guard and
// the resulting official draft. Those are asserted here as equivalence against
// the unrestricted build, and by the pre-existing compliance suites which run
// unmodified against this worker.
//
// Hermetic: in-memory KV, outbound fetch trapped. No Chiron submission.
//
//   node --test workers/compliance/chiron_cron_kv_reads_p0.test.mjs

import { test, before, after, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { __testInternals } from "./fluxidi_compliance_worker.js";

const {
  _chironAutoReconcileScopeBestEffort,
  _chironCronReconcileAllScopesBestEffort,
  _chironBuildOfficialDraftForSingleEvent,
  _chironBuildScopePreload,
  _chironEnsureBookingLegTypeForEvent,
  _chironLoadBookingLegTypeMap,
  _chironLoadScopedHydrationCache,
  chironCronEnabled,
  CHIRON_AUTO_RECONCILE_MAX_PROCESS,
  safeSegment,
} = __testInternals;

const ACC_URL = "https://mow-acc.api.vlaanderen.be/chiron/taxirit";
const TENANT_A = "T_cronreads_a";
const COMPANY_A = "C_cronreads_a";
const TENANT_B = "T_cronreads_b";
const COMPANY_B = "C_cronreads_b";

let originalFetch;
let outbound = [];

before(() => {
  originalFetch = global.fetch;
  global.fetch = async (input) => {
    const href = typeof input === "string" ? input : input?.url || String(input);
    outbound.push(href);
    throw new Error(`hermetic test: blocked outbound fetch to ${href}`);
  };
});

after(() => {
  global.fetch = originalFetch;
});

beforeEach(() => {
  outbound = [];
});

/* ===================== fixtures ===================== */

const NOW_MS = Date.now();
const EVENT_BASE_MS = NOW_MS - 3 * 60 * 60 * 1000;
const TESTFLOW_STARTED_AT = new Date(NOW_MS - 7 * 24 * 60 * 60 * 1000).toISOString();

const eventIso = (seq, offsetSeconds = 0) =>
  new Date(EVENT_BASE_MS + seq * 60_000 + offsetSeconds * 1000).toISOString();

const armedStatusDoc = () => ({
  schema_version: "chiron_connection_status_v1",
  enabled: true,
  environment: "production",
  region: "flanders",
  production_enabled: false,
  test_credentials_stored: true,
  production_credentials_stored: true,
  last_connection_status: "test_passed",
  last_connection_test_at: "2026-08-03T07:00:00.000Z",
  testflow_auto_submit_enabled: true,
  testflow_started_at: TESTFLOW_STARTED_AT,
  test_departure_sent_count: 5,
  test_arrival_sent_count: 5,
  test_messages_sent_count: 10,
  test_rides_completed_count: 5,
  testflow_status: "complete",
});

function rideEvent(kind, tenantId, companyId, bookingId, seq) {
  const isStop = kind === "ride_stop";
  return {
    event_type: kind,
    event_id: `${kind}:${tenantId}:${companyId}:${bookingId}`,
    tenant_id: tenantId,
    company_id: companyId,
    booking_id: bookingId,
    trip_id: `trip_${bookingId}`,
    ride_type: "direct",
    created_at_utc: eventIso(seq, isStop ? 30 : 0),
    timestamps: {
      event_at_utc: eventIso(seq, isStop ? 30 : 0),
      started_at_utc: eventIso(seq, 0),
      ...(isStop ? { stopped_at_utc: eventIso(seq, 30) } : {}),
    },
    driver: { driver_id: "drv_1" },
    vehicle: { vehicle_id: "vh_1", license_plate: "TXABC123" },
    locations: {
      pickup: { lat: 50.7720114, lng: 3.6695565, label: "origin" },
      dropoff: { lat: 50.850504, lng: 3.482422, label: "dest" },
    },
    fare: { currency: "EUR", distance_km: 12.5, total_amount: 20 },
  };
}

/**
 * `bookingRecords: true` makes BOOKING_KV answer every `booking:` get with an
 * explicitly one-way record, so `_chironSingleLegTypeFromBookingRecord` really
 * resolves a leg type and stamping actually changes the derived ritnummer. That
 * is the case where a narrowed fetch could silently alter a payload, so the
 * equivalence tests below use it.
 */
function makeHarness({
  scopes,
  bookingsPerScope,
  eventsPerBooking,
  bookingRecords = false,
}) {
  const complianceStore = new Map();
  const bookingReads = [];
  const complianceReads = [];
  let complianceLists = 0;

  const eventKeyFor = (tenantId, companyId, seq, label) =>
    `compliance_event_v1/tenant/${safeSegment(tenantId, "")}/company/${safeSegment(
      companyId,
      "",
    )}/2026/08/03/${1000 + seq}_${label}`;

  for (const { tenantId, companyId } of scopes) {
    complianceStore.set(
      `tenant:${tenantId}:company:${companyId}:chiron_connection:v1`,
      JSON.stringify(armedStatusDoc()),
    );
    let seq = 0;
    for (let b = 0; b < bookingsPerScope; b += 1) {
      const bookingId = `street_${tenantId}_${String(b).padStart(3, "0")}`;
      const kinds = eventsPerBooking === 1 ? ["ride_stop"] : ["ride_start", "ride_stop"];
      for (const kind of kinds) {
        seq += 1;
        complianceStore.set(
          eventKeyFor(tenantId, companyId, seq, `${kind}_${b}`),
          JSON.stringify(rideEvent(kind, tenantId, companyId, bookingId, seq)),
        );
      }
    }
  }

  const env = {
    CHIRON_EXPORT_MODE: "test",
    CHIRON_EXPORT_BASE_URL: ACC_URL,
    COMPLIANCE_KV: {
      async get(key) {
        complianceReads.push(key);
        return complianceStore.get(key) ?? null;
      },
      async put(key, value) {
        complianceStore.set(key, value);
      },
      async list({ prefix = "", limit = 1000, cursor } = {}) {
        complianceLists += 1;
        const all = [...complianceStore.keys()].filter((k) => k.startsWith(prefix)).sort();
        const start = cursor
          ? Number(Buffer.from(String(cursor), "base64").toString("utf8")) || 0
          : 0;
        const slice = all.slice(start, start + limit);
        const next = start + slice.length;
        const complete = next >= all.length;
        return {
          keys: slice.map((name) => ({ name })),
          list_complete: complete,
          cursor: complete ? undefined : Buffer.from(String(next), "utf8").toString("base64"),
        };
      },
    },
    BOOKING_KV: {
      async get(key) {
        bookingReads.push(key);
        if (!bookingRecords || !key.startsWith("booking:")) return null;
        // Explicitly one-way => resolves leg type "outbound".
        return { return_enabled: false, legs: [] };
      },
    },
  };

  return {
    env,
    bookingReads,
    complianceReads,
    complianceListCount: () => complianceLists,
    complianceStore,
    bookingKeyReads: () => bookingReads.filter((k) => k.startsWith("booking:")),
    hydrationReads: () => bookingReads.filter((k) => !k.startsWith("booking:")),
    countOf: (key) => bookingReads.filter((k) => k === key).length,
    contextEntriesFor: (tenantId, companyId) => {
      const prefix = `compliance_event_v1/tenant/${safeSegment(
        tenantId,
        "",
      )}/company/${safeSegment(companyId, "")}/`;
      return [...complianceStore.keys()]
        .filter((k) => k.startsWith(prefix))
        .sort()
        .map((key) => ({ key, event: JSON.parse(complianceStore.get(key)) }));
    },
    reset: () => {
      bookingReads.length = 0;
      complianceReads.length = 0;
      complianceLists = 0;
    },
  };
}

const SCOPE_A = { tenantId: TENANT_A, companyId: COMPANY_A };
const SCOPE_B = { tenantId: TENANT_B, companyId: COMPANY_B };

/* ===================== 1. on-demand read count ===================== */

test("1. BOOKING_KV reads follow the processed events, not the size of the window", async () => {
  // 120 bookings x 2 events = 240 candidates, far beyond the process budget.
  const bookings = 120;
  const h = makeHarness({
    scopes: [SCOPE_A],
    bookingsPerScope: bookings,
    eventsPerBooking: 2,
  });

  const outcome = await _chironAutoReconcileScopeBestEffort(h.env, TENANT_A, COMPANY_A, {
    source: "test",
  });

  assert.equal(outcome.ok, true);
  assert.equal(outcome.scanned, bookings * 2, "the scan itself is unchanged");
  assert.equal(outcome.processed, CHIRON_AUTO_RECONCILE_MAX_PROCESS);

  assert.equal(h.hydrationReads().length, 3, "hydration triple read once per pass");

  const distinctBookingsTouched = new Set(h.bookingKeyReads()).size;
  assert.ok(
    distinctBookingsTouched <= CHIRON_AUTO_RECONCILE_MAX_PROCESS,
    `booking reads bounded by the process budget, got ${distinctBookingsTouched}`,
  );
  assert.ok(
    distinctBookingsTouched < bookings,
    "the 14-day window is NOT pre-read",
  );
  assert.equal(
    h.bookingKeyReads().length,
    distinctBookingsTouched,
    "each booking read at most once per pass",
  );
  assert.deepEqual(outbound, [], "no provider call");
});

test("2. a booking miss is not re-read for its sibling events in the same pass", async () => {
  // Two events per booking: the second must hit the memo, including the miss.
  const h = makeHarness({ scopes: [SCOPE_A], bookingsPerScope: 4, eventsPerBooking: 2 });

  await _chironAutoReconcileScopeBestEffort(h.env, TENANT_A, COMPANY_A, { source: "test" });

  for (const key of new Set(h.bookingKeyReads())) {
    assert.equal(h.countOf(key), 1, `read once despite sibling events: ${key}`);
  }
});

test("3. nothing is memoized across passes", async () => {
  const h = makeHarness({ scopes: [SCOPE_A], bookingsPerScope: 4, eventsPerBooking: 1 });

  await _chironAutoReconcileScopeBestEffort(h.env, TENANT_A, COMPANY_A, { source: "test" });
  const first = h.bookingReads.length;
  h.reset();
  await _chironAutoReconcileScopeBestEffort(h.env, TENANT_A, COMPANY_A, { source: "test" });

  assert.equal(h.bookingReads.length, first, "a fresh pass re-reads from KV");
});

/* ===================== 2. equivalence with real leg records ============ */

test("4. official draft is identical to the unrestricted build when leg types really resolve", async () => {
  const h = makeHarness({
    scopes: [SCOPE_A],
    bookingsPerScope: 6,
    eventsPerBooking: 2,
    bookingRecords: true,
  });
  const scope = { tenant_id: TENANT_A, company_id: COMPANY_A };

  for (const target of h.contextEntriesFor(TENANT_A, COMPANY_A)) {
    // Fresh entry arrays per build so stamping cannot leak between the two runs.
    const entriesOnDemand = h.contextEntriesFor(TENANT_A, COMPANY_A);
    const entriesFull = h.contextEntriesFor(TENANT_A, COMPANY_A);

    const hydrationCache = await _chironLoadScopedHydrationCache(h.env, scope, true);

    // On-demand memo, exactly as the reconcile pass builds it.
    const onDemandPreload = _chironBuildScopePreload(scope, {
      hydrationCache,
      bookingLegTypeMap: new Map(),
      contextEntries: entriesOnDemand,
      legTypeFetched: new Set(),
    });
    const targetOnDemand = entriesOnDemand.find((e) => e.key === target.key);
    const onDemand = await _chironBuildOfficialDraftForSingleEvent(
      h.env,
      targetOnDemand.event,
      targetOnDemand.key,
      { preloadedContextEntries: entriesOnDemand, scopePreload: onDemandPreload },
    );

    // Unrestricted whole-window map, the previous behavior.
    const fullMap = await _chironLoadBookingLegTypeMap(h.env, entriesFull);
    const fullPreload = _chironBuildScopePreload(scope, {
      hydrationCache,
      bookingLegTypeMap: fullMap,
      contextEntries: entriesFull,
    });
    const targetFull = entriesFull.find((e) => e.key === target.key);
    const full = await _chironBuildOfficialDraftForSingleEvent(
      h.env,
      targetFull.event,
      targetFull.key,
      { preloadedContextEntries: entriesFull, scopePreload: fullPreload },
    );

    assert.deepEqual(
      JSON.parse(JSON.stringify(onDemand)),
      JSON.parse(JSON.stringify(full)),
      `draft must be byte-equivalent for ${target.key}`,
    );
  }
});

test("5. the memo resolves the same leg type the unrestricted map does", async () => {
  const h = makeHarness({
    scopes: [SCOPE_A],
    bookingsPerScope: 3,
    eventsPerBooking: 2,
    bookingRecords: true,
  });
  const scope = { tenant_id: TENANT_A, company_id: COMPANY_A };
  const entries = h.contextEntriesFor(TENANT_A, COMPANY_A);

  const fullMap = await _chironLoadBookingLegTypeMap(h.env, entries);
  assert.ok(fullMap.size > 0, "fixture must resolve real leg types");

  const preload = _chironBuildScopePreload(scope, {
    hydrationCache: null,
    bookingLegTypeMap: new Map(),
    contextEntries: entries,
    legTypeFetched: new Set(),
  });

  for (const { event } of entries) {
    await _chironEnsureBookingLegTypeForEvent(h.env, preload, event);
  }
  assert.deepEqual(
    [...preload.bookingLegTypeMap.entries()].sort(),
    [...fullMap.entries()].sort(),
    "topping up every event yields exactly the unrestricted map",
  );
});

/* ===================== 3. scope isolation ===================== */

test("6. two scopes in one tick never read each other's bookings", async () => {
  const h = makeHarness({
    scopes: [SCOPE_A, SCOPE_B],
    bookingsPerScope: 30,
    eventsPerBooking: 2,
    bookingRecords: true,
  });

  const summary = await _chironCronReconcileAllScopesBestEffort(h.env, { source: "cron" });
  assert.equal(summary.ok, true);
  assert.equal(summary.scopes, 2);
  assert.equal(summary.ran, 2);

  const keys = h.bookingKeyReads();
  const inA = keys.filter((k) => k.includes(TENANT_A)).length;
  const inB = keys.filter((k) => k.includes(TENANT_B)).length;
  assert.equal(inA + inB, keys.length, "every booking read belongs to exactly one scope");
  assert.ok(inA > 0 && inB > 0, "both scopes made progress");

  for (const { tenantId, companyId } of [SCOPE_A, SCOPE_B]) {
    assert.equal(
      h.countOf(`tenant:${tenantId}:company:${companyId}:business_profile:v1`),
      1,
      "each scope loads its own profile exactly once",
    );
  }
});

test("7. a preload never leaks into a foreign-scope event", async () => {
  const h = makeHarness({
    scopes: [SCOPE_A, SCOPE_B],
    bookingsPerScope: 2,
    eventsPerBooking: 1,
    bookingRecords: true,
  });
  const preloadA = _chironBuildScopePreload(
    { tenant_id: TENANT_A, company_id: COMPANY_A },
    {
      hydrationCache: await _chironLoadScopedHydrationCache(
        h.env,
        { tenant_id: TENANT_A, company_id: COMPANY_A },
        true,
      ),
      bookingLegTypeMap: new Map(),
      contextEntries: h.contextEntriesFor(TENANT_A, COMPANY_A),
      legTypeFetched: new Set(),
    },
  );
  const foreign = h.contextEntriesFor(TENANT_B, COMPANY_B)[0];

  h.reset();
  const built = await _chironBuildOfficialDraftForSingleEvent(
    h.env,
    foreign.event,
    foreign.key,
    { preloadedContextEntries: [foreign], scopePreload: preloadA },
  );

  assert.equal(built.scope.tenant_id, TENANT_B);
  assert.equal(
    h.countOf(`tenant:${TENANT_B}:company:${COMPANY_B}:business_profile:v1`),
    1,
    "the foreign event loads its OWN hydration",
  );
  assert.equal(
    h.bookingKeyReads().filter((k) => k.includes(TENANT_A)).length,
    0,
    "scope A bookings are never read for a scope B event",
  );
  assert.equal(
    preloadA.bookingLegTypeMap.size,
    0,
    "the foreign event never writes into scope A's memo",
  );
});

/* ===================== 4. candidate coverage ===================== */

test("8. candidate selection, ordering and the process budget are untouched", async () => {
  const bookings = 60;
  const withRecords = makeHarness({
    scopes: [SCOPE_A],
    bookingsPerScope: bookings,
    eventsPerBooking: 2,
    bookingRecords: true,
  });
  const withoutRecords = makeHarness({
    scopes: [SCOPE_A],
    bookingsPerScope: bookings,
    eventsPerBooking: 2,
  });

  const a = await _chironAutoReconcileScopeBestEffort(withRecords.env, TENANT_A, COMPANY_A, {
    source: "test",
  });
  const b = await _chironAutoReconcileScopeBestEffort(
    withoutRecords.env,
    TENANT_A,
    COMPANY_A,
    { source: "test" },
  );

  // Same scan, same budget, same per-event classification regardless of whether
  // booking records resolve a leg type.
  assert.equal(a.scanned, bookings * 2);
  assert.equal(b.scanned, bookings * 2);
  assert.equal(a.considered, b.considered);
  assert.equal(a.processed, b.processed);
  assert.equal(a.processed, CHIRON_AUTO_RECONCILE_MAX_PROCESS);

  // Identical selection AND identical order, whether or not a booking record
  // resolves a leg type. The memo cannot influence which candidates run.
  assert.deepEqual(
    a.events.map((e) => e.key),
    b.events.map((e) => e.key),
    "same candidates in the same order",
  );
  assert.equal(new Set(a.events.map((e) => e.key)).size, a.events.length, "no event twice");

  // The deployed ordering contract is newest-booking-first (so a long
  // already-synced history cannot starve recent rides), with departure before
  // arrival inside one booking. Both must survive this change.
  const seenBookings = [];
  for (const e of a.events) {
    const last = seenBookings[seenBookings.length - 1];
    if (!last || last.booking_id !== e.booking_id) {
      seenBookings.push({ booking_id: e.booking_id, first_at: e.created_at_utc });
      continue;
    }
    assert.ok(
      last.first_at <= e.created_at_utc,
      "within one booking the pass runs oldest-first (departure before arrival)",
    );
  }
  for (let i = 1; i < seenBookings.length; i += 1) {
    assert.ok(
      seenBookings[i - 1].first_at >= seenBookings[i].first_at,
      `newer bookings must be attempted first: ${seenBookings[i - 1].first_at} then ${seenBookings[i].first_at}`,
    );
  }
  assert.ok(seenBookings.length > 1, "fixture must span several bookings");
});

test("9. candidates beyond the budget stay available for the next tick", async () => {
  const h = makeHarness({
    scopes: [SCOPE_A],
    bookingsPerScope: 40,
    eventsPerBooking: 2,
    bookingRecords: true,
  });

  const first = await _chironAutoReconcileScopeBestEffort(h.env, TENANT_A, COMPANY_A, {
    source: "test",
  });
  const second = await _chironAutoReconcileScopeBestEffort(h.env, TENANT_A, COMPANY_A, {
    source: "test",
  });

  assert.equal(first.processed, CHIRON_AUTO_RECONCILE_MAX_PROCESS);
  assert.equal(
    second.scanned,
    first.scanned,
    "the next tick still sees the whole batch, so nothing is permanently excluded",
  );
  assert.ok(second.considered > 0, "the next tick still has candidates to work on");
});

/* ===================== 5. explicit on/off gate ===================== */

test("10. the gate defaults to enabled and only an explicit off value disables it", () => {
  assert.equal(chironCronEnabled({}), true, "unset => enabled (current live behavior)");
  assert.equal(chironCronEnabled({ CHIRON_CRON_ENABLED: "" }), true, "empty => enabled");
  assert.equal(chironCronEnabled({ CHIRON_CRON_ENABLED: "1" }), true);
  assert.equal(chironCronEnabled({ CHIRON_CRON_ENABLED: "true" }), true);
  assert.equal(chironCronEnabled({ CHIRON_CRON_ENABLED: "anything" }), true);

  for (const off of ["0", "false", "off", "no", "FALSE", " Off "]) {
    assert.equal(
      chironCronEnabled({ CHIRON_CRON_ENABLED: off }),
      false,
      `explicit off value disables: ${JSON.stringify(off)}`,
    );
  }
});

test("11. a disabled cron costs zero KV operations and reports itself", async () => {
  const h = makeHarness({ scopes: [SCOPE_A], bookingsPerScope: 20, eventsPerBooking: 2 });
  h.env.CHIRON_CRON_ENABLED = "0";

  const summary = await _chironCronReconcileAllScopesBestEffort(h.env, { source: "cron" });

  assert.equal(summary.ok, true, "a disabled tick is not an error");
  assert.equal(summary.disabled, true);
  assert.equal(summary.scopes, 0);
  assert.equal(summary.ran, 0);
  assert.equal(h.complianceListCount(), 0, "no COMPLIANCE_KV list");
  assert.equal(h.complianceReads.length, 0, "no COMPLIANCE_KV read");
  assert.equal(h.bookingReads.length, 0, "no BOOKING_KV read");
  assert.deepEqual(outbound, [], "no provider call");
});

test("12. the gate does not block the status-poll / admin reconcile path", async () => {
  const h = makeHarness({ scopes: [SCOPE_A], bookingsPerScope: 3, eventsPerBooking: 2 });
  h.env.CHIRON_CRON_ENABLED = "0";

  // Same entry point the status poll and the admin route use.
  const outcome = await _chironAutoReconcileScopeBestEffort(h.env, TENANT_A, COMPANY_A, {
    source: "admin_manual",
  });

  assert.equal(outcome.ok, true, "operator-driven reconcile still runs when the cron is off");
  assert.ok(outcome.considered > 0, "and still processes candidates");
});

test("13. an enabled tick still drains every armed scope", async () => {
  const h = makeHarness({ scopes: [SCOPE_A, SCOPE_B], bookingsPerScope: 2, eventsPerBooking: 1 });
  // Deliberately left unset: this is the live configuration.
  const summary = await _chironCronReconcileAllScopesBestEffort(h.env, { source: "cron" });

  assert.notEqual(summary.disabled, true);
  assert.equal(summary.scopes, 2);
  assert.equal(summary.ran, 2);
  assert.equal(summary.failed, 0);
});
