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
    CUSTOMER_QUOTE_MAIL_SINK: sink,
    COMPANY_QUOTE_BRAND: { company_name: "Fluxidi Demo Cars" },
    ...extra,
  };
  env.COMPANY_CUSTOMER_IMPORT_COORDINATOR =
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
  assert.equal(env.CUSTOMER_QUOTE_MAIL_SINK.length, 1);
  assert.equal(env.CUSTOMER_QUOTE_MAIL_SINK[0].to, "guest@p0quote.test");
  const token = sendBody.quote.public_token;
  const view = await worker.fetch(new Request(`https://example.test/public/customer-quotes/${token}`), env, {});
  assert.equal(view.status, 200);
  const html = await view.text();
  assert.match(html, /Fluxidi Demo Cars/);
  assert.match(html, /EUR 80.00/);
  assert.match(html, /id="accept"/);
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

test("conscious accept creates one blocked booking and repeats stay idempotent", async () => {
  const env = envWith(countingKV());
  const customer = await createCustomer(env);
  const created = await adminRequest(env, `/company/customers/${customer.customer_id}/quotes`, {
    method: "POST",
    body: quoteBody(),
  });
  const quoteId = (await created.json()).quote.quote_id;
  const sent = await (await adminRequest(env, `/company/customer-quotes/${quoteId}/send`, { method: "POST" })).json();
  const token = sent.quote.public_token;
  const first = await worker.fetch(
    new Request(`https://example.test/public/customer-quotes/${token}/accept`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ confirm: true }),
    }),
    env,
    {},
  );
  assert.equal(first.status, 200);
  const firstBody = await first.json();
  assert.equal(firstBody.quote.accepted, true);
  assert.match(firstBody.booking_id, /^cqb_[a-f0-9]{32}$/);
  assert.equal(firstBody.booking_dispatch_blocked, true);
  const second = await worker.fetch(
    new Request(`https://example.test/public/customer-quotes/${token}/accept`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ confirm: true }),
    }),
    env,
    {},
  );
  const secondBody = await second.json();
  assert.equal(secondBody.idempotent, true);
  assert.equal(secondBody.booking_id, firstBody.booking_id);
  const company = await (await adminRequest(env, `/company/customer-quotes/${quoteId}`)).json();
  assert.equal(company.quote.state, "accepted");
  assert.equal(company.quote.booking_id, firstBody.booking_id);
  const booking = JSON.parse(env.BOOKING_KV.store.get(`booking:${firstBody.booking_id}`));
  assert.equal(booking.do_not_dispatch, true);
  assert.equal(booking.ride_started, false);
  assert.equal(booking.source, "company_customer_quote");
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
