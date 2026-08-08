// MOLLIE-HOSTED-CANCEL-WIRE-EVIDENCE-P0
// Run: node --test workers/booking/modules/mollie_hosted_cancel_wire_evidence.test.mjs

import assert from "node:assert/strict";
import test from "node:test";

import {
  MOLLIE_HOSTED_CANCEL_LOG_TAGS,
  assertMollieHostedCancelLogSafe,
  emitMollieHostedCancelWireLog,
  formatMollieHostedCancelWireLog,
  readMollieCredentialWireFields,
  readSafeMollieCancelWireFields,
  sanitizeMollieCancelProviderError,
} from "./mollie_hosted_cancel_wire_evidence.mjs";

test("wire fields: status + isCancelable only from raw Mollie payment", () => {
  const wire = readSafeMollieCancelWireFields({
    id: "tr_x",
    status: "open",
    isCancelable: false,
    _links: { checkout: { href: "https://www.mollie.com/checkout/secret" } },
    metadata: { email: "p@example.com" },
  });
  assert.equal(wire.provider_status, "open");
  assert.equal(wire.is_cancelable, false);
  assert.equal(Object.keys(wire).includes("checkout"), false);
});

test("sanitize DELETE error keeps code/title only", () => {
  const err = sanitizeMollieCancelProviderError({
    status: 422,
    title: "Unprocessable Entity",
    detail: "Authorization: Bearer super-secret",
    _links: { documentation: { href: "https://docs.mollie.com" } },
  });
  assert.equal(err.error_code, "422");
  assert.equal(err.error_title, "Unprocessable Entity");
});

test("formatter drops forbidden keys and stays secret-safe", () => {
  const line = formatMollieHostedCancelWireLog(
    MOLLIE_HOSTED_CANCEL_LOG_TAGS.DELETE_RESULT,
    {
      booking_id: "street_1786194637526_7opdus7g",
      payment_id: "tr_pAuqfY7F44RUvxvNC27VJ",
      http_status: 422,
      ok: false,
      error_code: "422",
      error_title: "Unprocessable Entity",
      authorization: "Bearer SHOULD_NOT_APPEAR",
      access_token: "SHOULD_NOT_APPEAR",
      checkout_url: "https://www.mollie.com/checkout/select-method/x",
    },
  );
  assert.match(line, /^\[MOLLIE_HOSTED_CANCEL\]\[DELETE_RESULT\]/);
  assert.match(line, /http_status=422/);
  assert.equal(line.includes("Bearer"), false);
  assert.equal(line.includes("SHOULD_NOT_APPEAR"), false);
  assert.equal(line.includes("checkout"), false);
  assert.equal(assertMollieHostedCancelLogSafe(line), true);
});

test("credential wire fields never include apiKey", () => {
  const c = readMollieCredentialWireFields({
    ok: true,
    apiKey: "live_secret_should_never_log",
    payment_credential_source: "company_mollie",
    mode: "live",
    keyKind: "oauth",
  });
  assert.equal(c.credential_source, "company_mollie");
  assert.equal(c.mode, "live");
  const line = emitMollieHostedCancelWireLog(
    MOLLIE_HOSTED_CANCEL_LOG_TAGS.PRE_GET,
    {
      booking_id: "b1",
      payment_id: "tr_1",
      provider_status: "open",
      is_cancelable: true,
      credential_source: c.credential_source,
      mode: c.mode,
    },
    { log: () => {} },
  );
  assert.equal(line.includes("live_secret"), false);
  assert.equal(assertMollieHostedCancelLogSafe(line), true);
});

test("all required cancel wire tags are defined", () => {
  for (const key of [
    "PRE_GET",
    "DECISION",
    "DELETE_SEND",
    "DELETE_RESULT",
    "POST_GET",
    "FINAL",
  ]) {
    assert.match(
      MOLLIE_HOSTED_CANCEL_LOG_TAGS[key],
      /^\[MOLLIE_HOSTED_CANCEL\]\[[A-Z_]+\]$/,
    );
  }
});
