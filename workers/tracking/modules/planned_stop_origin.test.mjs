import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import {
  hasTrustedOriginCoords,
  resolvePlannedStopOrigin,
} from "./planned_stop_origin.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const trackingWorker = readFileSync(
  join(__dirname, "..", "fluxidi_tracking_api_worker_V2_1_with_route_index.js"),
  "utf8",
);

test("label-only planned origin is filled from synced session departure GPS", () => {
  const resolved = resolvePlannedStopOrigin({
    payloadOrigin: { label: "Grote Markt 1" },
    existingTripOrigin: { label: "stale" },
    sessionOrigin: { label: "start", lat: 50.8467, lon: 4.3525 },
  });
  assert.equal(resolved.label, "Grote Markt 1");
  assert.equal(resolved.lat, 50.8467);
  assert.equal(resolved.lon, 4.3525);
  assert.equal(hasTrustedOriginCoords(resolved), true);
});

test("does not invent or replace exact payload departure GPS", () => {
  const resolved = resolvePlannedStopOrigin({
    payloadOrigin: { label: "A", lat: 51.05, lon: 3.72 },
    sessionOrigin: { lat: 50.0, lon: 4.0 },
  });
  assert.equal(resolved.lat, 51.05);
  assert.equal(resolved.lon, 3.72);
});

test("zero / missing coordinates stay absent", () => {
  assert.equal(hasTrustedOriginCoords({ lat: 0, lon: 0 }), false);
  assert.equal(
    resolvePlannedStopOrigin({
      payloadOrigin: { label: "A" },
      sessionOrigin: { lat: 0, lng: 0 },
    }).lat,
    undefined,
  );
});

test("planned ride_stop pickup mapping uses origin lon as lng", () => {
  const origin = resolvePlannedStopOrigin({
    payloadOrigin: { label: "A" },
    sessionOrigin: { lat: 50.8467, lng: 4.3525 },
  });
  const pickup = {
    label: origin.label,
    lat: origin.lat,
    lng: origin.lon,
  };
  assert.equal(pickup.lat, 50.8467);
  assert.equal(pickup.lng, 4.3525);
});

test("taxi direct stop path is unchanged", () => {
  const plannedStart = trackingWorker.indexOf(
    "async function handleRecordPlannedStopTrip",
  );
  const plannedEnd = trackingWorker.indexOf(
    "async function handleWaitStartTrip",
    plannedStart,
  );
  const plannedBlock = trackingWorker.slice(plannedStart, plannedEnd);
  assert.match(plannedBlock, /resolvePlannedStopOrigin\(/);
  const directStart = trackingWorker.indexOf("async function handleStopTrip");
  const directEnd = trackingWorker.indexOf(
    "async function handleReconcileDirectBooking",
    directStart,
  );
  const directStop = trackingWorker.slice(directStart, directEnd);
  assert.doesNotMatch(directStop, /resolvePlannedStopOrigin\(/);
});
