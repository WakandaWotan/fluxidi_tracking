// P3D — fail-closed limousine transaction gate resolver.
// Run: node --test workers/booking/modules/limousine_transaction_gate.test.mjs

import test from "node:test";
import assert from "node:assert/strict";

import { LIMOUSINE_DISCOVERY_LISTING_MODE_TEST_PREVIEW } from "./limousine_discovery_preview.mjs";
import {
  LIMOUSINE_TRANSACTION_GATE_KIND,
  LIMOUSINE_TRANSACTION_GATE_REASON,
  limousineTransactionGateErrorFor,
  resolveLimousineTransactionGate,
} from "./limousine_transaction_gate.mjs";

const COMPANY = "fluxidi_fluxidi_ddmh9g";

function decide(overrides = {}) {
  return resolveLimousineTransactionGate({
    kind: LIMOUSINE_TRANSACTION_GATE_KIND.QUOTE,
    globalGateEnabled: true,
    companyId: COMPANY,
    allowlisted: true,
    allowlistConfigured: true,
    listingMode: LIMOUSINE_DISCOVERY_LISTING_MODE_TEST_PREVIEW,
    publishedLimousine: true,
    ...overrides,
  });
}

test("1) global gate off wins with the existing error codes", () => {
  assert.equal(
    decide({
      kind: LIMOUSINE_TRANSACTION_GATE_KIND.QUOTE,
      globalGateEnabled: false,
    }).error,
    "gate_off",
  );
  assert.equal(
    decide({
      kind: LIMOUSINE_TRANSACTION_GATE_KIND.BOOK,
      globalGateEnabled: false,
    }).error,
    "limousine_book_disabled",
  );
  assert.equal(
    decide({
      kind: LIMOUSINE_TRANSACTION_GATE_KIND.MANUAL_QUOTE,
      globalGateEnabled: false,
    }).error,
    "manual_quote_gate_off",
  );
});

test("2) missing or client-untrusted company is deny-all", () => {
  assert.equal(decide({ companyId: "" }).reason, LIMOUSINE_TRANSACTION_GATE_REASON.COMPANY_UNTRUSTED);
  assert.equal(decide({ companyId: "   " }).reason, LIMOUSINE_TRANSACTION_GATE_REASON.COMPANY_UNTRUSTED);
  assert.equal(decide({ companyId: undefined }).reason, LIMOUSINE_TRANSACTION_GATE_REASON.COMPANY_UNTRUSTED);
});

test("3) test-preview requires the existing allowlist", () => {
  const denied = decide({ allowlisted: false });
  assert.equal(denied.ok, false);
  assert.equal(denied.reason, LIMOUSINE_TRANSACTION_GATE_REASON.NOT_ALLOWLISTED);
  assert.equal(denied.error, "unavailable");
  assert.equal(
    decide({
      kind: LIMOUSINE_TRANSACTION_GATE_KIND.BOOK,
      allowlisted: false,
    }).error,
    "limousine_unavailable",
  );
  assert.equal(
    decide({
      kind: LIMOUSINE_TRANSACTION_GATE_KIND.MANUAL_QUOTE,
      allowlisted: false,
    }).error,
    "not_found",
  );
});

test("4) empty allowlist stays deny-all even when a company id is present", () => {
  const denied = decide({
    allowlisted: false,
    allowlistConfigured: false,
  });
  assert.equal(denied.ok, false);
  assert.equal(denied.reason, LIMOUSINE_TRANSACTION_GATE_REASON.NOT_ALLOWLISTED);
});

test("5) unpublished providers are denied when the caller already knows", () => {
  const denied = decide({ publishedLimousine: false });
  assert.equal(denied.ok, false);
  assert.equal(denied.reason, LIMOUSINE_TRANSACTION_GATE_REASON.NOT_PUBLISHED);
});

test("6) unknown published state is left to later eligibility, not invented", () => {
  const allowed = decide({ publishedLimousine: undefined });
  assert.equal(allowed.ok, true);
  assert.equal(allowed.company_id, COMPANY);
});

test("7) production listing is not a bypass of the allowlist", () => {
  const denied = decide({
    listingMode: "public",
    allowlisted: false,
    allowlistConfigured: false,
  });
  assert.equal(denied.ok, false);
  assert.equal(denied.reason, LIMOUSINE_TRANSACTION_GATE_REASON.NOT_ALLOWLISTED);
});

test("8) allowlisted + published + gate on is the only pass", () => {
  const allowed = decide();
  assert.deepEqual(allowed, { ok: true, company_id: COMPANY });
  assert.equal(
    limousineTransactionGateErrorFor({
      kind: LIMOUSINE_TRANSACTION_GATE_KIND.QUOTE,
      reason: LIMOUSINE_TRANSACTION_GATE_REASON.GATE_OFF,
    }),
    "gate_off",
  );
});
