// LIMOUSINE-MARKETPLACE-P2C2B — AES-GCM capability references.
// Run: node --test workers/booking/modules/limousine_aead_token.test.mjs
//
// Intentional pre-activation break: the HMAC form
//   limqs1|limacc1.{base64url JSON}.{HMAC}
// is rejected. No dual-format downgrade exists.

import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import {
  LIMOUSINE_ACCEPTANCE_KEY_PURPOSE,
  LIMOUSINE_STATUS_KEY_PURPOSE,
  inspectLimousineTokenSecret,
  looksLikeLimousineAeadToken,
  tokenSegmentLooksLikeJson,
} from "./limousine_aead_token.mjs";
import {
  LIMOUSINE_ACCEPTANCE_ERRORS,
  LIMOUSINE_ACCEPTANCE_TOKEN_VERSION,
  limousineAcceptanceBindingMatches,
  sealLimousineAcceptance,
  unsealLimousineAcceptance,
} from "./limousine_acceptance_token.mjs";
import {
  LIMOUSINE_STATUS_ERRORS,
  LIMOUSINE_STATUS_TOKEN_VERSION,
  sealLimousineStatusRef,
  unsealLimousineStatusRef,
} from "./limousine_status_token.mjs";
import {
  buildLimousineAcceptanceBinding,
  buildLimousineCustomerFingerprint,
  validateLimousineCompanyQuote,
  validateLimousineQuoteRequest,
} from "./limousine_manual_quote.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const SECRET = "test-only-secret-not-production";
const OTHER = "other-secret-value-16";

const TERMS = {
  terms_revision: 3,
  cancellation_deadline_hours: 24,
  cancellation_penalty_percent: 50,
  waiting_time_included_minutes: 15,
  waiting_time_overage_cents_per_minute: 100,
  no_show_penalty_percent: 100,
  overtime_cents_per_hour: 9000,
  mobilisation_disclosure: { en: "Mobilisation included" },
};

function quotedRecord(overrides = {}) {
  const validated = validateLimousineQuoteRequest(
    {
      offer_id: "off_1",
      journey_type: "point_to_point",
      from: "Gent",
      to: "Brussel",
      scheduled_pickup_iso: "2026-09-01T10:00:00Z",
      pax: 2,
      bags: 1,
      selected_extra_ids: ["deco"],
    },
    {
      eligible: true,
      offer: {
        offer_id: "off_1",
        enabled: true,
        published: true,
        service_class_id: "executive_sedan",
        paid_extras: [{ extra_id: "deco", active: true, public: true, quote_required: true }],
      },
      gateEnabled: true,
    },
  );
  const quote = validateLimousineCompanyQuote(
    { total_incl_vat_cents: 45000, currency: "EUR", terms: TERMS, expires_at: "2099-01-01T00:00:00Z" },
    { nowIso: "2026-08-17T10:00:00Z" },
  );
  return {
    quote_request_id: "limq_1",
    tenant_id: "t1",
    company_id: "c1",
    revision: 3,
    request: validated.request,
    quote: quote.quote,
    offer_source_revision: 7,
    pricing_section_revision: 5,
    ...overrides,
  };
}

function statusBinding(overrides = {}) {
  const rec = quotedRecord();
  return {
    purpose: "customer_status",
    tenant_id: "t1",
    company_id: "c1",
    quote_request_id: "limq_1",
    customer_fingerprint: buildLimousineCustomerFingerprint({
      tenantId: "t1",
      companyId: "c1",
      customerRef: "cust_1",
      quoteRequestId: "limq_1",
      itineraryFingerprint: rec.request.itinerary_fingerprint,
    }),
    created_revision: 1,
    ...overrides,
  };
}

function oldHmacToken(version, payload) {
  const body = Buffer.from(JSON.stringify(payload)).toString("base64url");
  const sig = Buffer.from("fake-hmac-signature-bytes-here!!").toString("base64url");
  return `${version}.${body}.${sig}`;
}

function assertSafeFailure(result, token) {
  const rendered = JSON.stringify(result);
  assert.equal(result.ok, false);
  assert.ok(result.error);
  assert.ok(!rendered.includes(token), "error must not echo the token");
  assert.ok(!rendered.includes("total_incl_vat_cents"));
  assert.ok(!rendered.includes("customer_fingerprint"));
  assert.ok(!rendered.includes("issued_at"));
  const parts = String(token).split(".");
  if (parts[1]) assert.ok(!rendered.includes(parts[1]));
  if (parts[2]) assert.ok(!rendered.includes(parts[2]));
}

test("1) same payload sealed twice produces different tokens", async () => {
  const binding = buildLimousineAcceptanceBinding(quotedRecord());
  const a = await sealLimousineAcceptance({
    secret: SECRET,
    binding,
    acceptedAtIso: "2026-08-17T10:00:00Z",
    ttlMinutes: 60,
  });
  const b = await sealLimousineAcceptance({
    secret: SECRET,
    binding,
    acceptedAtIso: "2026-08-17T10:00:00Z",
    ttlMinutes: 60,
  });
  assert.equal(a.ok, true);
  assert.equal(b.ok, true);
  assert.notEqual(a.reference, b.reference);
  const statusA = await sealLimousineStatusRef({
    secret: SECRET,
    binding: statusBinding(),
    issuedAtIso: "2026-08-17T10:00:00Z",
    ttlMinutes: 60,
  });
  const statusB = await sealLimousineStatusRef({
    secret: SECRET,
    binding: statusBinding(),
    issuedAtIso: "2026-08-17T10:00:00Z",
    ttlMinutes: 60,
  });
  assert.notEqual(statusA.reference, statusB.reference);
});

test("2) both valid tokens unseal correctly", async () => {
  const binding = buildLimousineAcceptanceBinding(quotedRecord());
  const acc = await sealLimousineAcceptance({
    secret: SECRET,
    binding,
    acceptedAtIso: "2026-08-17T10:00:00Z",
    ttlMinutes: 60,
  });
  const openedAcc = await unsealLimousineAcceptance({
    secret: SECRET,
    reference: acc.reference,
    nowIso: "2026-08-17T10:30:00Z",
  });
  assert.equal(openedAcc.ok, true);
  assert.equal(openedAcc.binding.total_incl_vat_cents, 45000);
  assert.equal(openedAcc.binding.quote_revision, 3);
  assert.equal(openedAcc.accepted_at, "2026-08-17T10:00:00Z");

  const st = await sealLimousineStatusRef({
    secret: SECRET,
    binding: statusBinding(),
    issuedAtIso: "2026-08-17T10:00:00Z",
    ttlMinutes: 60,
  });
  const openedSt = await unsealLimousineStatusRef({
    secret: SECRET,
    reference: st.reference,
    nowIso: "2026-08-17T10:30:00Z",
  });
  assert.equal(openedSt.ok, true);
  assert.equal(openedSt.binding.quote_request_id, "limq_1");
  assert.equal(openedSt.binding.purpose, "customer_status");
  assert.ok(acc.reference.startsWith(`${LIMOUSINE_ACCEPTANCE_TOKEN_VERSION}.`));
  assert.ok(st.reference.startsWith(`${LIMOUSINE_STATUS_TOKEN_VERSION}.`));
});

test("3) token body cannot be base64-decoded into readable JSON", async () => {
  const acc = await sealLimousineAcceptance({
    secret: SECRET,
    binding: buildLimousineAcceptanceBinding(quotedRecord()),
    acceptedAtIso: "2026-08-17T10:00:00Z",
  });
  const st = await sealLimousineStatusRef({
    secret: SECRET,
    binding: statusBinding(),
    issuedAtIso: "2026-08-17T10:00:00Z",
  });
  for (const ref of [acc.reference, st.reference]) {
    const [, iv, ct] = ref.split(".");
    assert.equal(tokenSegmentLooksLikeJson(iv), false);
    assert.equal(tokenSegmentLooksLikeJson(ct), false);
    assert.ok(!ref.includes("total_incl_vat_cents"));
    assert.ok(!ref.includes("customer_fingerprint"));
    assert.ok(!ref.includes("tenant_id"));
  }
});

test("4/5/6) modified IV, modified ciphertext and truncated tokens are rejected", async () => {
  const acc = await sealLimousineAcceptance({
    secret: SECRET,
    binding: buildLimousineAcceptanceBinding(quotedRecord()),
    acceptedAtIso: "2026-08-17T10:00:00Z",
  });
  const [v, iv, ct] = acc.reference.split(".");
  const flip = (segment) => `${segment[0] === "A" ? "B" : "A"}${segment.slice(1)}`;
  const badIv = await unsealLimousineAcceptance({
    secret: SECRET,
    reference: `${v}.${flip(iv)}.${ct}`,
    nowIso: "2026-08-17T10:30:00Z",
  });
  assertSafeFailure(badIv, acc.reference);
  assert.equal(badIv.error, LIMOUSINE_ACCEPTANCE_ERRORS.BAD_SIGNATURE);

  const badCt = await unsealLimousineAcceptance({
    secret: SECRET,
    reference: `${v}.${iv}.${flip(ct)}`,
    nowIso: "2026-08-17T10:30:00Z",
  });
  assertSafeFailure(badCt, acc.reference);
  assert.equal(badCt.error, LIMOUSINE_ACCEPTANCE_ERRORS.BAD_SIGNATURE);

  const truncated = await unsealLimousineAcceptance({
    secret: SECRET,
    reference: `${v}.${iv}.${ct.slice(0, 10)}`,
    nowIso: "2026-08-17T10:30:00Z",
  });
  assert.equal(truncated.ok, false);
  assert.equal(truncated.error, LIMOUSINE_ACCEPTANCE_ERRORS.MALFORMED);
});

test("7) wrong prefix/version is rejected", async () => {
  const acc = await sealLimousineAcceptance({
    secret: SECRET,
    binding: buildLimousineAcceptanceBinding(quotedRecord()),
    acceptedAtIso: "2026-08-17T10:00:00Z",
  });
  const [, iv, ct] = acc.reference.split(".");
  const wrong = await unsealLimousineAcceptance({
    secret: SECRET,
    reference: `limacc2.${iv}.${ct}`,
    nowIso: "2026-08-17T10:30:00Z",
  });
  assert.equal(wrong.ok, false);
  assert.equal(wrong.error, LIMOUSINE_ACCEPTANCE_ERRORS.VERSION_MISMATCH);
  assert.equal(looksLikeLimousineAeadToken(`limacc2.${iv}.${ct}`, LIMOUSINE_ACCEPTANCE_TOKEN_VERSION), false);
});

test("8/9) status and acceptance verifiers reject each other's tokens", async () => {
  const acc = await sealLimousineAcceptance({
    secret: SECRET,
    binding: buildLimousineAcceptanceBinding(quotedRecord()),
    acceptedAtIso: "2026-08-17T10:00:00Z",
  });
  const st = await sealLimousineStatusRef({
    secret: SECRET,
    binding: statusBinding(),
    issuedAtIso: "2026-08-17T10:00:00Z",
  });
  const statusAsAcc = await unsealLimousineAcceptance({
    secret: SECRET,
    reference: st.reference,
    nowIso: "2026-08-17T10:30:00Z",
  });
  assert.equal(statusAsAcc.ok, false);
  const accAsStatus = await unsealLimousineStatusRef({
    secret: SECRET,
    reference: acc.reference,
    nowIso: "2026-08-17T10:30:00Z",
  });
  assert.equal(accAsStatus.ok, false);
  assert.equal(accAsStatus.error, LIMOUSINE_STATUS_ERRORS.MALFORMED);
  assert.notEqual(LIMOUSINE_STATUS_KEY_PURPOSE, LIMOUSINE_ACCEPTANCE_KEY_PURPOSE);
});

test("10) wrong secret is rejected", async () => {
  const acc = await sealLimousineAcceptance({
    secret: SECRET,
    binding: buildLimousineAcceptanceBinding(quotedRecord()),
    acceptedAtIso: "2026-08-17T10:00:00Z",
  });
  const wrong = await unsealLimousineAcceptance({
    secret: OTHER,
    reference: acc.reference,
    nowIso: "2026-08-17T10:30:00Z",
  });
  assertSafeFailure(wrong, acc.reference);
  assert.equal(wrong.error, LIMOUSINE_ACCEPTANCE_ERRORS.BAD_SIGNATURE);
});

test("11) expired token is rejected", async () => {
  const acc = await sealLimousineAcceptance({
    secret: SECRET,
    binding: buildLimousineAcceptanceBinding(quotedRecord()),
    acceptedAtIso: "2026-08-17T10:00:00Z",
    ttlMinutes: 60,
  });
  const expired = await unsealLimousineAcceptance({
    secret: SECRET,
    reference: acc.reference,
    nowIso: "2026-08-17T12:00:00Z",
  });
  assert.equal(expired.error, LIMOUSINE_ACCEPTANCE_ERRORS.EXPIRED);
  const st = await sealLimousineStatusRef({
    secret: SECRET,
    binding: statusBinding(),
    issuedAtIso: "2026-08-17T10:00:00Z",
    ttlMinutes: 30,
  });
  const stExpired = await unsealLimousineStatusRef({
    secret: SECRET,
    reference: st.reference,
    nowIso: "2026-08-17T11:00:00Z",
  });
  assert.equal(stExpired.ok, false);
  assert.equal(stExpired.error, LIMOUSINE_STATUS_ERRORS.EXPIRED);
});

test("12) tenant/company/customer mismatch is rejected without field leakage", async () => {
  const binding = statusBinding();
  const st = await sealLimousineStatusRef({
    secret: SECRET,
    binding,
    issuedAtIso: "2026-08-17T10:00:00Z",
  });
  const opened = await unsealLimousineStatusRef({
    secret: SECRET,
    reference: st.reference,
    nowIso: "2026-08-17T10:30:00Z",
  });
  const { limousineStatusBindingMatches } = await import("./limousine_status_token.mjs");
  const mismatch = limousineStatusBindingMatches(opened.binding, {
    ...binding,
    company_id: "other-company",
  });
  assert.equal(mismatch.ok, false);
  const rendered = JSON.stringify(mismatch);
  assert.ok(!rendered.includes(st.reference));
  assert.ok(!rendered.includes(binding.customer_fingerprint) || mismatch.mismatched_field);
});

test("13) quote revision/terms mismatch is rejected at the consuming seam", () => {
  const record = quotedRecord();
  const binding = buildLimousineAcceptanceBinding(record);
  assert.equal(limousineAcceptanceBindingMatches(binding, binding).ok, true);
  assert.equal(
    limousineAcceptanceBindingMatches(binding, { ...binding, quote_revision: 99 }).ok,
    false,
  );
  assert.equal(
    limousineAcceptanceBindingMatches(binding, { ...binding, terms_revision: 1 }).mismatched_field,
    "terms_revision",
  );
});

test("14) old HMAC format is rejected (no dual-format downgrade)", async () => {
  const hmacAcc = oldHmacToken(LIMOUSINE_ACCEPTANCE_TOKEN_VERSION, {
    v: LIMOUSINE_ACCEPTANCE_TOKEN_VERSION,
    binding: { total_incl_vat_cents: 1 },
    accepted_at: "2026-08-17T10:00:00Z",
    expires_at: "2099-01-01T00:00:00Z",
  });
  const hmacSt = oldHmacToken(LIMOUSINE_STATUS_TOKEN_VERSION, {
    v: LIMOUSINE_STATUS_TOKEN_VERSION,
    purpose: "customer_status",
    binding: { quote_request_id: "limq_1" },
    issued_at: "2026-08-17T10:00:00Z",
    expires_at: "2099-01-01T00:00:00Z",
  });
  assert.equal(tokenSegmentLooksLikeJson(hmacAcc.split(".")[1]), true);
  const acc = await unsealLimousineAcceptance({
    secret: SECRET,
    reference: hmacAcc,
    nowIso: "2026-08-17T10:30:00Z",
  });
  assert.equal(acc.ok, false);
  assert.equal(acc.error, LIMOUSINE_ACCEPTANCE_ERRORS.MALFORMED);
  const st = await unsealLimousineStatusRef({
    secret: SECRET,
    reference: hmacSt,
    nowIso: "2026-08-17T10:30:00Z",
  });
  assert.equal(st.ok, false);
  assert.equal(st.error, LIMOUSINE_STATUS_ERRORS.MALFORMED);
});

test("15) missing, blank, short and placeholder secrets fail closed", async () => {
  const binding = buildLimousineAcceptanceBinding(quotedRecord());
  for (const secret of [undefined, "", "   ", "short", "secret", "changeme", "placeholder"]) {
    const sealed = await sealLimousineAcceptance({
      secret,
      binding,
      acceptedAtIso: "2026-08-17T10:00:00Z",
    });
    assert.equal(sealed.ok, false, `seal must reject ${JSON.stringify(secret)}`);
    assert.equal(sealed.error, LIMOUSINE_ACCEPTANCE_ERRORS.MISSING_SECRET);
    assert.equal(sealed.secret, undefined);
    assert.equal(sealed.reference, undefined);
  }
  assert.equal(inspectLimousineTokenSecret("secret").ok, false);
  assert.equal(inspectLimousineTokenSecret(SECRET).ok, true);
  const live = await sealLimousineAcceptance({
    secret: SECRET,
    binding,
    acceptedAtIso: "2026-08-17T10:00:00Z",
  });
  const unsealed = await unsealLimousineAcceptance({
    secret: "changeme",
    reference: live.reference,
    nowIso: "2026-08-17T10:30:00Z",
  });
  assert.equal(unsealed.error, LIMOUSINE_ACCEPTANCE_ERRORS.MISSING_SECRET);
});

test("16) errors never include the token or decrypted content", async () => {
  const acc = await sealLimousineAcceptance({
    secret: SECRET,
    binding: buildLimousineAcceptanceBinding(quotedRecord()),
    acceptedAtIso: "2026-08-17T10:00:00Z",
  });
  const failures = [
    await unsealLimousineAcceptance({ secret: OTHER, reference: acc.reference, nowIso: "2026-08-17T10:30:00Z" }),
    await unsealLimousineAcceptance({ secret: SECRET, reference: "garbage", nowIso: "2026-08-17T10:30:00Z" }),
    await unsealLimousineStatusRef({ secret: SECRET, reference: acc.reference, nowIso: "2026-08-17T10:30:00Z" }),
  ];
  for (const failure of failures) {
    assertSafeFailure(failure, acc.reference);
  }
  const worker = readFileSync(join(__dirname, "..", "fluxidi_booking_worker.js"), "utf8");
  const statusBlock = worker.slice(
    worker.indexOf("customer status poll via opaque ref"),
    worker.indexOf("GET /partners/nearby"),
  );
  assert.ok(!statusBlock.includes("console.log"));
  const acceptBlock = worker.slice(
    worker.indexOf('"/limousine/quote-requests/accept"'),
    worker.indexOf("company inbox list"),
  );
  assert.ok(!/console\.log\([^\)]*reference/.test(acceptBlock));
});

test("17/18) status polling and request/respond/accept/inbox wiring stay in place", () => {
  const worker = readFileSync(join(__dirname, "..", "fluxidi_booking_worker.js"), "utf8");
  for (const route of [
    '"/limousine/quote-requests" && request.method === "POST"',
    '"/admin/limousine/quote-requests/respond" && request.method === "POST"',
    '"/limousine/quote-requests/accept" && request.method === "POST"',
    '"/limousine/quote-requests/status" && request.method === "POST"',
    '"/admin/limousine/quote-requests" && request.method === "GET"',
  ]) {
    assert.ok(worker.includes(route), route);
  }
  assert.ok(worker.includes("_unsealLimousineAcceptance({"));
  assert.ok(worker.includes("_executeLimousineStatusRead"));
  assert.ok(worker.includes("_prepareLimousineManualBooking"));
  assert.ok(worker.includes("await _limousineStatusRateKey(statusRef)"));
});

test("19) taxi and airport paths stay free of token crypto", () => {
  const worker = readFileSync(join(__dirname, "..", "fluxidi_booking_worker.js"), "utf8");
  const calcStart = worker.indexOf("function calcPrice({");
  const calcEnd = worker.indexOf("function buildNote(");
  if (calcStart > 0 && calcEnd > calcStart) {
    const slice = worker.slice(calcStart, calcEnd);
    assert.ok(!slice.includes("limacc1"));
    assert.ok(!slice.includes("limqs1"));
    assert.ok(!slice.includes("AES-GCM"));
  }
});

test("20) every limousine gate remains OFF", () => {
  const wrangler = readFileSync(join(__dirname, "..", "wrangler.toml"), "utf8");
  assert.ok(!wrangler.includes("LIMOUSINE_QUOTE_ENABLED"));
  assert.ok(!wrangler.includes("LIMOUSINE_BOOK_ENABLED"));
  assert.ok(!wrangler.includes("LIMOUSINE_MANUAL_QUOTE_ENABLED"));
  const worker = readFileSync(join(__dirname, "..", "fluxidi_booking_worker.js"), "utf8");
  assert.ok(worker.includes('env?.LIMOUSINE_QUOTE_ENABLED ?? "0"'));
  assert.ok(worker.includes('env?.LIMOUSINE_BOOK_ENABLED ?? "0"'));
  assert.ok(worker.includes('env?.LIMOUSINE_MANUAL_QUOTE_ENABLED ?? "0"'));
  assert.ok(!worker.includes("LIMOUSINE_ACCEPTANCE_SECRET ="));
  const aead = readFileSync(join(__dirname, "limousine_aead_token.mjs"), "utf8");
  assert.ok(aead.includes("AES-GCM"));
  assert.ok(aead.includes("the previous HMAC form"));
  assert.ok(aead.includes("is intentionally NOT accepted"));
});
