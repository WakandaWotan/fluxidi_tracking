// CHIRON-RELEASE-PRESENTATION-REPAIR-1 B — START compliance event includes
// booking_id when the same start-direct lifecycle already resolved a booking.
//
// Run:
//   node --test workers/tracking/chiron_direct_start_booking_id.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import vm from "node:vm";

const HERE = dirname(fileURLToPath(import.meta.url));
const SRC = readFileSync(
  join(HERE, "fluxidi_tracking_api_worker_V2_1_with_route_index.js"),
  "utf8",
);

function extractFunction(name) {
  const start = SRC.indexOf(`function ${name}(`);
  assert.ok(start >= 0, `missing function ${name}`);
  let i = start;
  let depth = 0;
  let started = false;
  for (; i < SRC.length; i++) {
    const ch = SRC[i];
    if (ch === "{") {
      depth += 1;
      started = true;
    } else if (ch === "}") {
      depth -= 1;
      if (started && depth === 0) {
        i += 1;
        break;
      }
    }
  }
  return SRC.slice(start, i);
}

function loadBuilder() {
  // Minimal sandbox for the pure builder + its local helpers it closes over.
  // We re-implement only the thin helpers the builder needs.
  const prelude = `
    function safeStr(v, max) {
      if (v == null) return null;
      const s = String(v).trim();
      if (!s) return null;
      return typeof max === "number" ? s.slice(0, max) : s;
    }
    function nowIso() { return "2026-07-28T00:00:00.000Z"; }
    function normalizeTenantCompanyScope(scope) {
      if (!scope) return null;
      return {
        tenant_id: safeStr(scope.tenant_id ?? scope.tenantId, 96),
        company_id: safeStr(scope.company_id ?? scope.companyId, 96),
      };
    }
    function _complianceLocationFromPoint(p) {
      if (!p || typeof p !== "object") return null;
      return { label: safeStr(p.label, 256), lat: p.lat ?? null, lng: p.lon ?? p.lng ?? null };
    }
  `;
  const fnSrc = extractFunction("buildDirectTripStartComplianceEvent");
  const context = { console, result: null };
  vm.createContext(context);
  vm.runInContext(
    `${prelude}\n${fnSrc}\nresult = buildDirectTripStartComplianceEvent;`,
    context,
  );
  return context.result;
}

test("7. START includes booking_id when trip already has resolved booking", () => {
  const build = loadBuilder();
  const event = build(
    {
      trip_id: "trip_abc",
      booking_id: "booking_xyz",
      tenant_id: "T1",
      company_id: "C1",
      driver_id: "D1",
      vehicle_id: "V1",
      origin: { label: "A", lat: 1, lon: 2 },
      destination: { label: "B", lat: 3, lon: 4 },
    },
    "2026-07-28T08:00:00.000Z",
    { tenant_id: "T1", company_id: "C1" },
  );
  assert.ok(event);
  assert.equal(event.event_type, "ride_start");
  assert.equal(event.ride_type, "direct");
  assert.equal(event.trip_id, "trip_abc");
  assert.equal(event.booking_id, "booking_xyz");
  assert.equal(event.provenance?.ride_identity?.canonical, "booking:booking_xyz");
  assert.equal(event.provenance?.ride_identity?.trip_id, "trip_abc");
});

test("START without booking_id stays trip-canonical (no invented booking)", () => {
  const build = loadBuilder();
  const event = build(
    {
      trip_id: "trip_only",
      tenant_id: "T1",
      company_id: "C1",
    },
    "2026-07-28T08:00:00.000Z",
    { tenant_id: "T1", company_id: "C1" },
  );
  assert.ok(event);
  assert.equal(event.trip_id, "trip_only");
  assert.equal(event.booking_id, undefined);
  assert.equal(event.provenance?.ride_identity?.canonical, "trip:trip_only");
});

test("append default sync_state is unknown (not not_configured)", () => {
  const complianceSrc = readFileSync(
    join(HERE, "..", "compliance", "fluxidi_compliance_worker.js"),
    "utf8",
  );
  assert.match(complianceSrc, /const SYNC_STATE = "unknown"/);
  assert.doesNotMatch(
    complianceSrc,
    /const SYNC_STATE = "not_configured"/,
  );
});
