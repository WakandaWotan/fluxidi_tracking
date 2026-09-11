// COMPANY-CUSTOMER-OPS-P0 — company customer quotes.
//
// Run:
//   node --test workers/booking/company_customers_p0_quotes.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import worker from "./fluxidi_booking_worker.js";
import { matchCompanyCustomersPath, matchPublicCustomerQuotePath } from "./modules/company_customers.mjs";
import { createMemoryCompanyCustomerImportCoordinatorBinding } from "./modules/company_customer_import_coordinator.mjs";

const ADMIN = "p0-quote-admin";
const TENANT_A = "TA";
const COMPANY_A = "CA";
const TENANT_B = "TB";
const COMPANY_B = "CB";

function countingKV(seed = {}) {
  const store = new Map();
  const counts = { get: 0, list: 0, put: 0 };
  for (const [key, value] of Object.entries(seed)) {
    store.set(key, typeof value === "string" ? value : JSON.stringify(value));
  }
  return {
    store,
    counts,
    async get(key, opts) {
      counts.get += 1;
      if (!store.has(key)) return null;
      const raw = store.get(key);
      const asJson = opts === "json" || (opts && opts.type === "json");
      if (asJson) {
        try {
          return typeof raw === "string" ? JSON.parse(raw) : raw;
        } catch {
          return null;
        }
      }
      return raw;
    },
    async put(key, val) {
      counts.put += 1;
      store.set(key, val);
    },
    async delete(key) {
      store.delete(key);
    },
    async list() {
      counts.list += 1;
      return { keys: [], list_complete: true };
    },
  };
}

function envWith(kv, extra = {}) {
  const sink = [];
  const env = {
    ADMIN_TOKEN: ADMIN,
    BOOKING_KV: kv,
    COMPANY_QUOTE_BRAND: { company_name: "Fluxidi Demo Cars" },
    ...extra,
  };
  if (!("CUSTOMER_QUOTE_MAIL_SINK" in extra) && typeof extra.CUSTOMER_QUOTE_MAIL_SEND !== "function") {
    env.CUSTOMER_QUOTE_MAIL_SINK = sink;
  }
  env.COMPANY_CUSTOMER_IMPORT_COORDINATOR =
    extra.COMPANY_CUSTOMER_IMPORT_COORDINATOR ||
    createMemoryCompanyCustomerImportCoordinatorBinding(env);
  return env;
}

async function adminRequest(env, path, { method = "GET", body, tenant = TENANT_A, company = COMPANY_A } = {}) {
  const url = new URL(`https://example.test${path}`);
  if (method === "GET") {
    url.searchParams.set("tenant_id", tenant);
    url.searchParams.set("company_id", company);
  }
  return worker.fetch(
    new Request(url, {
      method,
      headers: {
        "x-admin-token": ADMIN,
        "Content-Type": "application/json",
      },
      body: method === "GET"
        ? undefined
        : JSON.stringify({ tenant_id: tenant, company_id: company, ...(body || {}) }),
    }),
    env,
    {},
  );
}

async function createCustomer(env, extras = {}) {
  const res = await adminRequest(env, "/company/customers", {
    method: "POST",
    body: {
      display_name: extras.display_name || "No App Guest",
      email: extras.email ?? "guest@p0quote.test",
      phone: extras.phone,
    },
  });
  const json = await res.json();
  return json.customer;
}

function quoteBody(extras = {}) {
  return {
    pickup: extras.pickup || "Station Antwerpen",
    dropoff: extras.dropoff || "Brussel Zuid",
    start_at: extras.start_at || "2026-09-20T09:00:00.000Z",
    passengers: extras.passengers ?? 2,
    description: extras.description || "Airport transfer",
    entered_amount_cents: extras.entered_amount_cents ?? 8000,
    currency: extras.currency || "EUR",
    vat_treatment: extras.vat_treatment || "incl",
    valid_until: extras.valid_until || "2026-09-25T00:00:00.000Z",
    passenger_email: extras.passenger_email,
    issuer_name: extras.issuer_name,
  };
}

test("quote paths do not collide with customer ids", () => {
  const list = matchCompanyCustomersPath("/company/customers/cus_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/quotes");
  assert.equal(list.kind, "customer_quotes");
  const one = matchCompanyCustomersPath("/company/customer-quotes/cqq_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/send");
  assert.equal(one.kind, "customer_quote");
  assert.equal(one.action, "send");
  const pub = matchPublicCustomerQuotePath("/public/customer-quotes/tok/accept");
  assert.equal(pub.action, "accept");
});

test("draft can be saved without email and reopened", async () => {
  const env = envWith(countingKV());
  const customer = await createCustomer(env, { email: "" , phone: "+32470000080" });
  const created = await adminRequest(env, `/company/customers/${customer.customer_id}/quotes`, {
    method: "POST",
    body: quoteBody({ passenger_email: "", entered_amount_cents: 8000 }),
  });
  assert.equal(created.status, 201, await created.clone().text());
  const body = await created.json();
  assert.equal(body.quote.state, "draft");
  assert.equal(body.quote.entered_amount_cents, 8000);
  assert.equal(body.quote.issuer_name, "Fluxidi Demo Cars");
  const got = await adminRequest(env, `/company/customer-quotes/${body.quote.quote_id}`);
  assert.equal(got.status, 200);
  const reopened = (await got.json()).quote;
  assert.equal(reopened.pickup, "Station Antwerpen");
  assert.equal(reopened.entered_amount_cents, 8000);
});

test("send requires email, uses the test adapter, and GET does not accept", async () => {
  const env = envWith(countingKV());
  const customer = await createCustomer(env, { email: "" , phone: "+32470000081" });
  const created = await adminRequest(env, `/company/customers/${customer.customer_id}/quotes`, {
    method: "POST",
    body: quoteBody({ passenger_email: "" }),
  });
  const quoteId = (await created.json()).quote.quote_id;
  const refused = await adminRequest(env, `/company/customer-quotes/${quoteId}/send`, { method: "POST" });
  assert.equal(refused.status, 400);
  const patched = await adminRequest(env, `/company/customer-quotes/${quoteId}`, {
    method: "PATCH",
    body: { ...quoteBody({ passenger_email: "guest@p0quote.test" }), revision: 1 },
  });
  assert.equal(patched.status, 200);
  const sent = await adminRequest(env, `/company/customer-quotes/${quoteId}/send`, { method: "POST" });
  assert.equal(sent.status, 200);
  const sendBody = await sent.json();
  assert.equal(sendBody.delivery, "test_adapter");
  assert.equal(sendBody.delivery_proven, false);
  assert.equal(sendBody.test_send, true);
  assert.equal(sendBody.quote.test_send, true);
  assert.equal(env.CUSTOMER_QUOTE_MAIL_SINK.length, 1);
  assert.equal(env.CUSTOMER_QUOTE_MAIL_SINK[0].to, "guest@p0quote.test");
  assert.equal(env.CUSTOMER_QUOTE_MAIL_SINK[0].test_send, true);
  assert.equal(env.CUSTOMER_QUOTE_MAIL_SINK[0].delivery, "test_adapter");
  const token = sendBody.quote.public_token;
  const view = await worker.fetch(new Request(`https://example.test/public/customer-quotes/${token}`), env, {});
  assert.equal(view.status, 200);
  const html = await view.text();
  assert.match(html, /Fluxidi Demo Cars/);
  assert.match(html, /EUR 80.00/);
  assert.match(html, /id="accept"/);
  assert.match(html, /new URL\("accept"/);
  const company = await adminRequest(env, `/company/customer-quotes/${quoteId}`);
  assert.equal((await company.json()).quote.state, "viewed");
  const getAccept = await worker.fetch(
    new Request(`https://example.test/public/customer-quotes/${token}/accept`),
    env,
    {},
  );
  assert.equal(getAccept.status, 405);
  const noConfirm = await worker.fetch(
    new Request(`https://example.test/public/customer-quotes/${token}/accept`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({}),
    }),
    env,
    {},
  );
  assert.equal(noConfirm.status, 400);
});

async function acceptQuote(env, token) {
  return worker.fetch(
    new Request(`https://example.test/public/customer-quotes/${token}/accept`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ confirm: true }),
    }),
    env,
    {},
  );
}

async function sendQuoteForCustomer(env, extras = {}) {
  const customer = await createCustomer(env, {
    email: extras.email,
    phone: extras.phone,
    display_name: extras.display_name,
  });
  const created = await adminRequest(env, `/company/customers/${customer.customer_id}/quotes`, {
    method: "POST",
    body: quoteBody({
      passenger_email: extras.email || "guest@p0quote.test",
      start_at: extras.start_at,
      pickup: extras.pickup,
    }),
  });
  const quoteId = (await created.json()).quote.quote_id;
  const sent = await (await adminRequest(env, `/company/customer-quotes/${quoteId}/send`, { method: "POST" })).json();
  return { customer, quoteId, token: sent.quote.public_token };
}

test("conscious accept creates one blocked booking and repeats stay idempotent", async () => {
  const env = envWith(countingKV());
  const { quoteId, token } = await sendQuoteForCustomer(env);
  const first = await acceptQuote(env, token);
  assert.equal(first.status, 200);
  const firstBody = await first.json();
  assert.equal(firstBody.quote.accepted, true);
  assert.match(firstBody.booking_id, /^cqb_[a-f0-9]{32}$/);
  assert.equal(firstBody.booking_dispatch_blocked, true);
  assert.equal(firstBody.booking_list_ready, true);
  const listed = await (await adminRequest(env, "/bookings?limit=50")).json();
  assert.equal(listed.ok, true);
  assert.equal(listed.items.length, 1);
  assert.equal(listed.items[0].booking_id, firstBody.booking_id);
  assert.equal(listed.items[0].from, "Station Antwerpen");
  assert.equal(listed.items[0].to, "Brussel Zuid");
  assert.equal(listed.items[0].pax, 2);
  assert.equal(listed.items[0].price, 80);
  assert.equal(listed.items[0].currency, "EUR");
  assert.equal(listed.items[0].customer_name, "No App Guest");
  assert.equal(listed.items[0].status, "PENDING");
  assert.equal(listed.items[0].quote_id, quoteId);
  assert.equal(listed.items[0].assigned_driver_id ?? null, null);
  assert.equal(listed.items[0].assigned_vehicle_id ?? null, null);
  const foreign = await (await adminRequest(env, "/bookings?limit=50", {
    tenant: TENANT_B,
    company: COMPANY_B,
  })).json();
  assert.equal(foreign.ok, true);
  assert.equal(foreign.items.length, 0);
  const second = await acceptQuote(env, token);
  const secondBody = await second.json();
  assert.equal(second.status, 200);
  assert.equal(secondBody.idempotent, true);
  assert.equal(secondBody.booking_id, firstBody.booking_id);
  const again = await (await adminRequest(env, "/bookings?limit=50")).json();
  assert.equal(again.items.length, 1);
  assert.equal(again.items[0].booking_id, firstBody.booking_id);
  const company = await (await adminRequest(env, `/company/customer-quotes/${quoteId}`)).json();
  assert.equal(company.quote.state, "accepted");
  assert.equal(company.quote.booking_id, firstBody.booking_id);
  assert.equal(company.quote.booking_list_ready, true);
  const booking = JSON.parse(env.BOOKING_KV.store.get(`booking:${firstBody.booking_id}`));
  assert.equal(booking.do_not_dispatch, true);
  assert.equal(booking.ride_started, false);
  assert.equal(booking.source, "company_customer_quote");
  assert.equal(booking.status, "PENDING");
  const bookingKeys = [...env.BOOKING_KV.store.keys()].filter((key) => key.startsWith("booking:"));
  assert.equal(bookingKeys.length, 1);
});

test("accept retries a missing company list index without a second booking", async () => {
  const kv = countingKV();
  const originalPut = kv.put.bind(kv);
  let failIndex = true;
  kv.put = async (key, val) => {
    if (failIndex && String(key).includes(":bookings:list:v1")) {
      throw new Error("simulated_index_fail");
    }
    return originalPut(key, val);
  };
  const env = envWith(kv);
  const { quoteId, token } = await sendQuoteForCustomer(env, {
    email: "retry@p0quote.test",
    phone: "+32470000094",
  });
  const interrupted = await acceptQuote(env, token);
  assert.equal(interrupted.status, 503);
  const interruptedBody = await interrupted.json();
  assert.equal(interruptedBody.error, "booking_list_index_failed");
  assert.match(interruptedBody.booking_id, /^cqb_[a-f0-9]{32}$/);
  assert.equal(interruptedBody.booking_list_ready, false);
  const companyAfterFail = await (await adminRequest(env, `/company/customer-quotes/${quoteId}`)).json();
  assert.notEqual(companyAfterFail.quote.state, "accepted");
  assert.ok(["sent", "viewed"].includes(companyAfterFail.quote.state));
  assert.equal(companyAfterFail.quote.booking_id, null);
  assert.equal(companyAfterFail.quote.booking_list_ready, false);
  const emptyList = await (await adminRequest(env, "/bookings?limit=50")).json();
  assert.equal(emptyList.items?.length || 0, 0);
  const retryPage = await worker.fetch(
    new Request(`https://example.test/public/customer-quotes/${token}`),
    env,
    {},
  );
  assert.match(await retryPage.text(), /id="accept"/);
  failIndex = false;
  const repaired = await acceptQuote(env, token);
  assert.equal(repaired.status, 200);
  const repairedBody = await repaired.json();
  assert.equal(repairedBody.booking_id, interruptedBody.booking_id);
  assert.equal(repairedBody.booking_list_ready, true);
  assert.equal(repairedBody.idempotent, undefined);
  const listed = await (await adminRequest(env, "/bookings?limit=50")).json();
  assert.equal(listed.items.length, 1);
  assert.equal(listed.items[0].booking_id, interruptedBody.booking_id);
  const bookingKeys = [...env.BOOKING_KV.store.keys()].filter((key) => key.startsWith("booking:"));
  assert.equal(bookingKeys.length, 1);
});

test("accepted quotes honour existing company booking-list pagination", async () => {
  const env = envWith(countingKV());
  const first = await sendQuoteForCustomer(env, {
    email: "one@p0quote.test",
    phone: "+32470000091",
    start_at: "2026-09-21T09:00:00.000Z",
  });
  const second = await sendQuoteForCustomer(env, {
    email: "two@p0quote.test",
    phone: "+32470000092",
    start_at: "2026-09-22T09:00:00.000Z",
  });
  const third = await sendQuoteForCustomer(env, {
    email: "three@p0quote.test",
    phone: "+32470000093",
    start_at: "2026-09-23T09:00:00.000Z",
  });
  const a = await (await acceptQuote(env, first.token)).json();
  const b = await (await acceptQuote(env, second.token)).json();
  const c = await (await acceptQuote(env, third.token)).json();
  const page = await (await adminRequest(env, "/bookings?limit=2")).json();
  assert.equal(page.ok, true);
  assert.equal(page.items.length, 2);
  const all = await (await adminRequest(env, "/bookings?limit=50")).json();
  assert.equal(all.items.length, 3);
  const ids = all.items.map((item) => item.booking_id).sort();
  assert.deepEqual(ids, [a.booking_id, b.booking_id, c.booking_id].sort());
});

test("expired and foreign tokens stay closed", async () => {
  const env = envWith(countingKV(), { CUSTOMER_NOW_MS: Date.parse("2026-09-10T00:00:00.000Z") });
  const customer = await createCustomer(env);
  const created = await adminRequest(env, `/company/customers/${customer.customer_id}/quotes`, {
    method: "POST",
    body: quoteBody({ valid_until: "2026-09-11T00:00:00.000Z" }),
  });
  const quoteId = (await created.json()).quote.quote_id;
  const sent = await (await adminRequest(env, `/company/customer-quotes/${quoteId}/send`, { method: "POST" })).json();
  env.CUSTOMER_NOW_MS = Date.parse("2026-09-12T00:00:00.000Z");
  const view = await worker.fetch(
    new Request(`https://example.test/public/customer-quotes/${sent.quote.public_token}`),
    env,
    {},
  );
  assert.equal(view.status, 410);
  const accept = await worker.fetch(
    new Request(`https://example.test/public/customer-quotes/${sent.quote.public_token}/accept`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ confirm: true }),
    }),
    env,
    {},
  );
  assert.equal(accept.status, 410);
  const miss = await worker.fetch(
    new Request("https://example.test/public/customer-quotes/not-a-real-token"),
    env,
    {},
  );
  assert.equal(miss.status, 404);
  const cross = await adminRequest(env, `/company/customer-quotes/${quoteId}`, {
    tenant: TENANT_B,
    company: COMPANY_B,
  });
  assert.equal(cross.status, 404);
});

test("draft without price stays empty and send never invents 80 euro", async () => {
  const env = envWith(countingKV());
  const customer = await createCustomer(env, { email: "price@p0quote.test" });
  const body = quoteBody({ passenger_email: "price@p0quote.test" });
  delete body.entered_amount_cents;
  const created = await adminRequest(env, `/company/customers/${customer.customer_id}/quotes`, {
    method: "POST",
    body,
  });
  assert.equal(created.status, 201, await created.clone().text());
  const quote = (await created.json()).quote;
  assert.equal(quote.entered_amount_cents, null);
  assert.notEqual(quote.entered_amount_cents, 8000);
  const refused = await adminRequest(env, `/company/customer-quotes/${quote.quote_id}/send`, { method: "POST" });
  assert.equal(refused.status, 400);
  const refusedBody = await refused.json();
  assert.equal(refusedBody.error, "invalid_quote");
  assert.equal(refusedBody.fields.entered_amount_cents, "required");
  const reopened = await (await adminRequest(env, `/company/customer-quotes/${quote.quote_id}`)).json();
  assert.equal(reopened.quote.state, "draft");
  assert.equal(reopened.quote.entered_amount_cents, null);
});

test("send without adapter stays draft and does not claim customer delivery", async () => {
  const env = envWith(countingKV(), { CUSTOMER_QUOTE_MAIL_SINK: null });
  const customer = await createCustomer(env);
  const created = await adminRequest(env, `/company/customers/${customer.customer_id}/quotes`, {
    method: "POST",
    body: quoteBody(),
  });
  const quoteId = (await created.json()).quote.quote_id;
  const sent = await adminRequest(env, `/company/customer-quotes/${quoteId}/send`, { method: "POST" });
  assert.equal(sent.status, 503);
  const sentBody = await sent.json();
  assert.equal(sentBody.error, "mail_not_configured");
  assert.equal(sentBody.delivery, "mail_not_configured");
  assert.equal(sentBody.delivery_proven, false);
  const reopened = await (await adminRequest(env, `/company/customer-quotes/${quoteId}`)).json();
  assert.equal(reopened.quote.state, "draft");
  assert.equal(reopened.quote.delivery, "");
});

test("adapter failure keeps draft; adapter accept is not proven delivery", async () => {
  const failing = envWith(countingKV(), {
    CUSTOMER_QUOTE_MAIL_SEND: async () => ({ ok: false, error: "smtp_down" }),
  });
  const customer = await createCustomer(failing, { email: "fail@p0quote.test" });
  const created = await adminRequest(failing, `/company/customers/${customer.customer_id}/quotes`, {
    method: "POST",
    body: quoteBody({ passenger_email: "fail@p0quote.test" }),
  });
  const quoteId = (await created.json()).quote.quote_id;
  const failed = await adminRequest(failing, `/company/customer-quotes/${quoteId}/send`, { method: "POST" });
  assert.equal(failed.status, 502);
  assert.equal((await failed.json()).error, "smtp_down");
  assert.equal((await (await adminRequest(failing, `/company/customer-quotes/${quoteId}`)).json()).quote.state, "draft");

  const accepting = envWith(countingKV(), {
    CUSTOMER_QUOTE_MAIL_SEND: async () => ({ ok: true, delivery: "resend" }),
  });
  const other = await createCustomer(accepting, { email: "ok@p0quote.test" });
  const ready = await adminRequest(accepting, `/company/customers/${other.customer_id}/quotes`, {
    method: "POST",
    body: quoteBody({ passenger_email: "ok@p0quote.test" }),
  });
  const acceptedId = (await ready.json()).quote.quote_id;
  const sent = await adminRequest(accepting, `/company/customer-quotes/${acceptedId}/send`, { method: "POST" });
  assert.equal(sent.status, 200);
  const sentBody = await sent.json();
  assert.equal(sentBody.delivery, "adapter_accepted");
  assert.equal(sentBody.delivery_proven, false);
  assert.equal(sentBody.test_send, false);
  assert.equal(sentBody.quote.delivery, "adapter_accepted");
  assert.notEqual(sentBody.delivery, "delivered");
});
