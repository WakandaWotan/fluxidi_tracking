// Run: node --test workers/booking/modules/limousine_submit_observability.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import {
  LIMOUSINE_SUBMIT_STAGES,
  attachLimousineBookObservability,
  buildLimousineSubmitLog,
  createLimousineSubmitRequestId,
  limousineQuoteSuccessBody,
  limousineSubmitErrorBody,
  logLimousineSubmit,
  redactLimousineScopeId,
} from "./limousine_submit_observability.mjs";

test("request_id is stable-shaped and scope IDs stay redacted", () => {
  const id = createLimousineSubmitRequestId();
  assert.match(id, /^lsub_[a-f0-9]{16,}$/);
  assert.match(redactLimousineScopeId("fluxidi_limo_p3g"), /^f\*\*\*g\(len=16\)$/);
  const log = buildLimousineSubmitLog({
    request_id: id,
    route: "/limousine/quote-requests",
    service_type: "limousine",
    tenant: "fluxidi_limo_p3g",
    company: "company_limo_p3g",
    public_partner_id: "company:fluxidi_limo_p3g:company_limo_p3g",
    offer_id: "off_party_hummer",
    vehicle_id: "veh_hummer",
    stage: LIMOUSINE_SUBMIT_STAGES.VALIDATION,
    http_status: 400,
    error: "vehicle_scope_mismatch",
  });
  assert.equal(log.event, "limousine_submit");
  assert.equal(log.tenant.includes("fluxidi"), false);
  assert.equal(log.company.includes("company_limo"), false);
  assert.equal(String(log.public_partner_id).includes("fluxidi_limo"), false);
  assert.equal(log.offer_id, "off_party_hummer");
  assert.equal(log.http_status, 400);
});

test("error and success bodies carry public correlation fields", () => {
  const error = limousineSubmitErrorBody({
    error: "invalid_request",
    stage: LIMOUSINE_SUBMIT_STAGES.ENDPOINT,
    requestId: "lsub_abc",
    extra: { field: "to_endpoint" },
  });
  assert.deepEqual(error, {
    ok: false,
    error: "invalid_request",
    stage: "endpoint",
    request_id: "lsub_abc",
    field: "to_endpoint",
  });
  const success = limousineQuoteSuccessBody({
    quoteRequestId: "limq_1",
    requestId: "lsub_abc",
    quoteRequest: { quote_request_id: "limq_1", state: "requested" },
    idempotent: true,
  });
  assert.equal(success.ok, true);
  assert.equal(success.quote_request_id, "limq_1");
  assert.equal(success.request_id, "lsub_abc");
  assert.equal(success.idempotent, true);
});

test("book observability is additive and taxi-shaped objects stay untouched", () => {
  const taxi = { ok: true, booking_id: "2026-08-301" };
  assert.equal(attachLimousineBookObservability(taxi, { isLimousine: false }), taxi);
  assert.equal(taxi.request_id, undefined);
  const limo = { ok: true, booking_id: "2026-08-399" };
  attachLimousineBookObservability(limo, {
    requestId: "lsub_book",
    isLimousine: true,
  });
  assert.equal(limo.request_id, "lsub_book");
  assert.equal(limo.status, "pending");
});

test("logger refuses token-like or contact-like lines", () => {
  const lines = [];
  const blocked = logLimousineSubmit(
    { error: "bearer secret-token", request_id: "lsub_1" },
    (line) => lines.push(line),
  );
  assert.equal(blocked.ok, false);
  assert.deepEqual(lines, []);
  const ok = logLimousineSubmit(
    { request_id: "lsub_1", route: "/book", stage: "gate", http_status: 400 },
    (line) => lines.push(line),
  );
  assert.equal(ok.ok, true);
  assert.equal(lines.length, 1);
  assert.equal(lines[0].includes("lsub_1"), true);
});

test("worker quote and book routes keep the existing seams", () => {
  const here = dirname(fileURLToPath(import.meta.url));
  const worker = readFileSync(join(here, "../fluxidi_booking_worker.js"), "utf8");
  assert.ok(worker.includes('"/limousine/quote-requests" && request.method === "POST"'));
  assert.ok(worker.includes('url.pathname === "/book" && request.method === "POST"'));
  assert.ok(worker.includes("_createLimousineSubmitRequestId"));
  assert.ok(worker.includes("_limousineSubmitErrorBody"));
  assert.ok(worker.includes("attachLimousineBookObservability"));
  const quoteStart = worker.indexOf('"/limousine/quote-requests" && request.method === "POST"');
  const quoteEnd = worker.indexOf('"/admin/limousine/quote-requests/respond"');
  const slice = worker.slice(quoteStart, quoteEnd);
  assert.ok(!slice.includes("mollie"));
  assert.ok(!slice.includes("billit"));
  assert.ok(!slice.includes("chiron"));
});
