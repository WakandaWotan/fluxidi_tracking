import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const worker = readFileSync(join(__dirname, "../fluxidi_booking_worker.js"), "utf8");

test("pricing persist stamps published identity onto the tenant-scoped section", () => {
  assert.match(worker, /url\.pathname === "\/admin\/pricing\/limousine" && request\.method === "POST"/);
  assert.match(worker, /_applyPublishedLimousineIdentityToProfile/);
  assert.match(worker, /\{ scope, publicSurface: true \}/);
  assert.match(worker, /nextSection\.published_at = nowIso/);
  assert.match(worker, /nextSection\.tenant_id = explicitScope\.tenant_id/);
  assert.match(worker, /nextSection\.company_id = explicitScope\.company_id/);
});

test("discovery and profile project the same published identity fields", () => {
  assert.match(worker, /_publicPublishedLimousineIdentityFields\(profile, \{ publicSurface: true \}\)/);
  assert.match(worker, /_publicPublishedLimousineIdentityFields\(raw, \{ publicSurface: true \}\)/);
  assert.match(worker, /publishedIdentity: pricingSection/);
});

test("live listing contract stays present", () => {
  assert.match(worker, /limousine_listing_mode/);
  assert.match(worker, /_buildLimousineNearbyCardProjection/);
  assert.match(worker, /url\.pathname === "\/admin\/pricing\/limousine" && request\.method === "GET"/);
});
