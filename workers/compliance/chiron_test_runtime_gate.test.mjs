// RELEASE-P0-CHIRON-TEST-RUNTIME-GATE-2026-07-31 — targeted tests for the
// Chiron taxirit ACC/test runtime gate.
//
// After removing the legacy `CHIRON_EXPORT_API_TOKEN` enable-marker, the
// operator-driven testflow submit-one endpoint must:
//
//   * open ONLY when `CHIRON_EXPORT_MODE === "test"` AND
//     `CHIRON_EXPORT_BASE_URL` is set to an ACC/test host AND the per-company
//     preflight (`_chironTestflowLiveGate`) is satisfied;
//   * stay open even when the deprecated `CHIRON_EXPORT_API_TOKEN` env var is
//     absent (test-mode must not require it any more);
//   * refuse to authenticate the taxirit-POST with `CHIRON_EXPORT_API_TOKEN`,
//     even if it happens to be present in the environment.
//
// Run:
//   node --test workers/compliance/chiron_test_runtime_gate.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import { __testInternals } from "./fluxidi_compliance_worker.js";

const {
  chironExportTestModeEnabled,
  _chironTestflowLiveGate,
  _chironExportBaseUrlLooksTestOrAcc,
  _chironPostChironExportTestPayload,
} = __testInternals;

const ACC_TAXIRIT_URL = "https://mow-acc.api.vlaanderen.be/chiron/taxirit";
const PROD_TAXIRIT_URL = "https://mow.api.vlaanderen.be/chiron/taxirit";

function goodStatus(overrides = {}) {
  return {
    enabled: true,
    environment: "test",
    production_enabled: false,
    official_submit_enabled: false,
    test_credentials_stored: true,
    last_connection_status: "test_passed",
    ...overrides,
  };
}

function goodEnv(overrides = {}) {
  return {
    CHIRON_EXPORT_MODE: "test",
    CHIRON_EXPORT_BASE_URL: ACC_TAXIRIT_URL,
    ...overrides,
  };
}

function installFetchStub(handler) {
  const original = globalThis.fetch;
  const calls = [];
  globalThis.fetch = async (input, init) => {
    calls.push({ url: String(input), init });
    return handler(String(input), init || {});
  };
  return {
    calls,
    restore() {
      globalThis.fetch = original;
    },
  };
}

// -----------------------------------------------------------------------
// A. chironExportTestModeEnabled — enable-marker after legacy removal.
// -----------------------------------------------------------------------

test("gate: mode missing → chironExportTestModeEnabled=false", () => {
  assert.equal(
    chironExportTestModeEnabled({ CHIRON_EXPORT_BASE_URL: ACC_TAXIRIT_URL }),
    false,
  );
});

test("gate: mode != test → chironExportTestModeEnabled=false", () => {
  assert.equal(
    chironExportTestModeEnabled({
      CHIRON_EXPORT_MODE: "production",
      CHIRON_EXPORT_BASE_URL: ACC_TAXIRIT_URL,
    }),
    false,
  );
});

test("gate: base URL missing → chironExportTestModeEnabled=false", () => {
  assert.equal(
    chironExportTestModeEnabled({ CHIRON_EXPORT_MODE: "test" }),
    false,
  );
});

test("gate: mode=test + ACC base URL → chironExportTestModeEnabled=true (no API_TOKEN needed)", () => {
  assert.equal(chironExportTestModeEnabled(goodEnv()), true);
});

test("gate: CHIRON_EXPORT_API_TOKEN absent no longer blocks test mode", () => {
  const env = goodEnv();
  assert.equal(Object.prototype.hasOwnProperty.call(env, "CHIRON_EXPORT_API_TOKEN"), false);
  assert.equal(chironExportTestModeEnabled(env), true);
});

test("gate: CHIRON_EXPORT_API_TOKEN present does NOT change enable outcome", () => {
  const without = chironExportTestModeEnabled(goodEnv());
  const withLegacy = chironExportTestModeEnabled(
    goodEnv({ CHIRON_EXPORT_API_TOKEN: "legacy-static-token" }),
  );
  assert.equal(without, true);
  assert.equal(withLegacy, true);
});

// -----------------------------------------------------------------------
// B. _chironTestflowLiveGate — per-company + infra preflight.
// -----------------------------------------------------------------------

test("live-gate: missing status payload → missing_connection_status", () => {
  assert.equal(_chironTestflowLiveGate(null, goodEnv()), "missing_connection_status");
  assert.equal(_chironTestflowLiveGate(undefined, goodEnv()), "missing_connection_status");
});

test("live-gate: enabled=false → chiron_not_enabled", () => {
  assert.equal(
    _chironTestflowLiveGate(goodStatus({ enabled: false }), goodEnv()),
    "chiron_not_enabled",
  );
});

test("live-gate: advisory environment=production + production off → ACC stays OPEN", () => {
  // FLUXIDI-CHIRON-TEST-CAPTURE-AFTER-FIVE-SUCCESSES-P0-1: after 5/5 the
  // company may enter production setup (advisory environment=production)
  // while production_enabled stays false. ACC capture must continue.
  assert.equal(
    _chironTestflowLiveGate(
      goodStatus({ environment: "production", production_enabled: false }),
      goodEnv(),
    ),
    null,
  );
});

test("live-gate: production_enabled=true → production_must_be_disabled", () => {
  assert.equal(
    _chironTestflowLiveGate(goodStatus({ production_enabled: true }), goodEnv()),
    "production_must_be_disabled",
  );
});

test("live-gate: official_submit_enabled=true → official_submit_must_be_disabled", () => {
  assert.equal(
    _chironTestflowLiveGate(
      goodStatus({ official_submit_enabled: true }),
      goodEnv(),
    ),
    "official_submit_must_be_disabled",
  );
});

test("live-gate: test_credentials_stored=false → missing_test_credentials", () => {
  assert.equal(
    _chironTestflowLiveGate(
      goodStatus({ test_credentials_stored: false }),
      goodEnv(),
    ),
    "missing_test_credentials",
  );
});

test("live-gate: last_connection_status != test_passed → production_requires_test_passed", () => {
  assert.equal(
    _chironTestflowLiveGate(
      goodStatus({ last_connection_status: "test_failed" }),
      goodEnv(),
    ),
    "production_requires_test_passed",
  );
});

test("live-gate: CHIRON_EXPORT_MODE missing → chiron_export_mode_must_be_test", () => {
  const env = goodEnv();
  delete env.CHIRON_EXPORT_MODE;
  assert.equal(
    _chironTestflowLiveGate(goodStatus(), env),
    "chiron_export_mode_must_be_test",
  );
});

test("live-gate: CHIRON_EXPORT_MODE=production → chiron_export_mode_must_be_test", () => {
  assert.equal(
    _chironTestflowLiveGate(
      goodStatus(),
      goodEnv({ CHIRON_EXPORT_MODE: "production" }),
    ),
    "chiron_export_mode_must_be_test",
  );
});

test("live-gate: CHIRON_EXPORT_BASE_URL missing → chiron_export_test_mode_disabled", () => {
  const env = goodEnv();
  delete env.CHIRON_EXPORT_BASE_URL;
  assert.equal(
    _chironTestflowLiveGate(goodStatus(), env),
    "chiron_export_test_mode_disabled",
  );
});

test("live-gate: production taxirit URL → chiron_export_target_not_verified_test", () => {
  assert.equal(
    _chironTestflowLiveGate(
      goodStatus(),
      goodEnv({ CHIRON_EXPORT_BASE_URL: PROD_TAXIRIT_URL }),
    ),
    "chiron_export_target_not_verified_test",
  );
});

test("live-gate: ACC taxirit URL + mode=test + valid status → null (gate OPEN)", () => {
  assert.equal(_chironTestflowLiveGate(goodStatus(), goodEnv()), null);
});

test("live-gate: CHIRON_EXPORT_API_TOKEN absent still opens gate", () => {
  const env = goodEnv();
  assert.equal(Object.prototype.hasOwnProperty.call(env, "CHIRON_EXPORT_API_TOKEN"), false);
  assert.equal(_chironTestflowLiveGate(goodStatus(), env), null);
});

test("live-gate: CHIRON_EXPORT_API_TOKEN present does NOT change outcome", () => {
  const withoutLegacy = _chironTestflowLiveGate(goodStatus(), goodEnv());
  const withLegacy = _chironTestflowLiveGate(
    goodStatus(),
    goodEnv({ CHIRON_EXPORT_API_TOKEN: "legacy-static-token" }),
  );
  assert.equal(withoutLegacy, null);
  assert.equal(withLegacy, null);
});

// -----------------------------------------------------------------------
// C. ACC/test URL allowlist — cross-check with the live gate.
// -----------------------------------------------------------------------

test("url-allowlist: ACC hostname matches", () => {
  assert.equal(
    _chironExportBaseUrlLooksTestOrAcc({ CHIRON_EXPORT_BASE_URL: ACC_TAXIRIT_URL }),
    true,
  );
});

test("url-allowlist: production hostname does NOT match", () => {
  assert.equal(
    _chironExportBaseUrlLooksTestOrAcc({ CHIRON_EXPORT_BASE_URL: PROD_TAXIRIT_URL }),
    false,
  );
});

test("url-allowlist: empty base URL → false", () => {
  assert.equal(_chironExportBaseUrlLooksTestOrAcc({}), false);
  assert.equal(_chironExportBaseUrlLooksTestOrAcc({ CHIRON_EXPORT_BASE_URL: "" }), false);
});

// -----------------------------------------------------------------------
// D. taxirit POST — legacy static token never used, OAuth bearer required.
// -----------------------------------------------------------------------

test("taxirit-post: no OAuth access_token → no fetch, no CHIRON_EXPORT_API_TOKEN fallback", async () => {
  const stub = installFetchStub(() => {
    throw new Error("fetch must not be called without an OAuth access_token");
  });
  try {
    const res = await _chironPostChironExportTestPayload(
      goodEnv({ CHIRON_EXPORT_API_TOKEN: "legacy-static-token" }),
      { ritnummer: "R-OAUTH-1" },
    );
    assert.equal(res.ok, false);
    assert.equal(res.error, "missing_oauth_access_token");
    assert.equal(res.ambiguous, false);
    assert.equal(stub.calls.length, 0, "no HTTP request must go out");
  } finally {
    stub.restore();
  }
});

test("taxirit-post: OAuth bearer used, CHIRON_EXPORT_API_TOKEN never on wire", async () => {
  const env = goodEnv({ CHIRON_EXPORT_API_TOKEN: "legacy-static-token-should-never-hit-wire" });
  const stub = installFetchStub(() =>
    new Response(
      JSON.stringify({ fouten: [], external_reference: "CHIRON-REF-2" }),
      { status: 200, headers: { "content-type": "application/json" } },
    ),
  );
  try {
    const res = await _chironPostChironExportTestPayload(
      env,
      { ritnummer: "R-OAUTH-2" },
      { accessToken: "OAUTH-DERIVED-BEARER-XYZ" },
    );
    assert.equal(res.ok, true);
    assert.equal(res.ambiguous, false);
    assert.equal(stub.calls.length, 1);
    const authHeader = stub.calls[0].init.headers.authorization;
    assert.equal(authHeader, "Bearer OAUTH-DERIVED-BEARER-XYZ");
    assert.notEqual(
      authHeader,
      `Bearer ${env.CHIRON_EXPORT_API_TOKEN}`,
      "legacy static token MUST NOT be used as bearer",
    );
    assert.ok(
      !JSON.stringify(stub.calls[0].init).includes(env.CHIRON_EXPORT_API_TOKEN),
      "legacy static token MUST NOT appear anywhere in the outbound request",
    );
  } finally {
    stub.restore();
  }
});
