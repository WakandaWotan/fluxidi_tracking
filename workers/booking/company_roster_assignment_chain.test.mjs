// End-to-end chain against the prepared Worker: roster save → reopen →
// plan ride → assign Christophe → switch to Wotan → reopen agenda.
// Overlap keeps the original assignment. Assigned is not accepted.

import { test } from "node:test";
import assert from "node:assert/strict";

import worker from "./fluxidi_booking_worker.js";
import { createMemoryCompanyCustomerImportCoordinatorBinding } from "./modules/company_customer_import_coordinator.mjs";
import { projectPublicPartnerPaymentForProfile } from "./modules/public_partner_payment_capability.mjs";

const ADMIN = "p0-roster-chain-admin";
const TENANT = "TA";
const COMPANY = "CA";

function memoryKV(seed = {}) {
  const store = new Map();
  for (const [key, value] of Object.entries(seed)) {
    store.set(key, typeof value === "string" ? value : JSON.stringify(value));
  }
  return {
    store,
    async get(key, opts) {
      if (!store.has(key)) return null;
      const raw = store.get(key);
      const asJson = opts === "json" || (opts && opts.type === "json");
      if (!asJson) return raw;
      try {
        return JSON.parse(raw);
      } catch {
        return null;
      }
    },
    async put(key, val) {
      store.set(key, val);
    },
    async delete(key) {
      store.delete(key);
    },
    async list() {
      return { keys: [], list_complete: true };
    },
  };
}

function envWith(kv) {
  const env = {
    ADMIN_TOKEN: ADMIN,
    BOOKING_KV: kv,
  };
  env.COMPANY_CUSTOMER_IMPORT_COORDINATOR =
    createMemoryCompanyCustomerImportCoordinatorBinding(env);
  return env;
}

function seedFleet(kv) {
  kv.store.set(
    "tenant:TA:company:CA:drivers:index:v1",
    JSON.stringify({
      drivers: {
        drv_chris: {
          driver_id: "drv_chris",
          display_name: "Christophe",
          is_active: true,
          availability_status: "available",
          assigned_vehicle_id: "vh_chris",
        },
        drv_wotan: {
          driver_id: "drv_wotan",
          display_name: "Wotan",
          is_active: true,
          availability_status: "available",
          assigned_vehicle_id: "vh_wotan",
        },
      },
    }),
  );
  kv.store.set(
    "tenant:TA:company:CA:fleet:vehicles:v1",
    JSON.stringify({
      vehicles: [
        { vehicle_id: "vh_chris", is_active: true, assigned_driver_id: "drv_chris" },
        { vehicle_id: "vh_wotan", is_active: true, assigned_driver_id: "drv_wotan" },
      ],
    }),
  );
}

async function adminRequest(env, path, { method = "GET", body, headers = {} } = {}) {
  const url = new URL(`https://example.test${path}`);
  if (method === "GET") {
    url.searchParams.set("tenant_id", TENANT);
    url.searchParams.set("company_id", COMPANY);
  }
  const payload =
    body && typeof body === "object"
      ? { tenant_id: TENANT, company_id: COMPANY, ...body }
      : body;
  return worker.fetch(
    new Request(url, {
      method,
      headers: {
        "x-admin-token": ADMIN,
        "Content-Type": "application/json",
        ...headers,
      },
      body:
        method === "GET"
          ? undefined
          : JSON.stringify(payload || { tenant_id: TENANT, company_id: COMPANY }),
    }),
    env,
    {},
  );
}

test("roster save, plan, assign Christophe, switch to Wotan, reopen", async () => {
  const kv = memoryKV();
  seedFleet(kv);
  const env = envWith(kv);

  const unset = await adminRequest(env, "/company/drivers/drv_chris/schedule");
  const unsetJson = await unset.json();
  assert.equal(unset.status, 200, JSON.stringify(unsetJson));
  assert.equal(unsetJson.present, false);

  const saved = await adminRequest(env, "/company/drivers/drv_chris/schedule", {
    method: "PUT",
    body: {
      timezone: "Europe/Brussels",
      weekdays: {
        1: [{ start: "07:00", end: "23:00" }],
        2: [{ start: "07:00", end: "23:00" }],
        3: [{ start: "07:00", end: "23:00" }],
        4: [{ start: "07:00", end: "23:00" }],
        5: [{ start: "07:00", end: "23:00" }],
      },
    },
  });
  const savedJson = await saved.json();
  assert.equal(saved.status, 200, JSON.stringify(savedJson));
  assert.equal(savedJson.present, true);
  assert.equal(savedJson.schedule.explicitly_set, true);

  const reopened = await adminRequest(env, "/company/drivers/drv_chris/schedule");
  const reopenedJson = await reopened.json();
  assert.equal(reopenedJson.present, true);
  assert.equal(reopenedJson.schedule.weekdays["3"][0].start, "07:00");

  const emptyWotan = await adminRequest(env, "/company/drivers/drv_wotan/schedule", {
    method: "PUT",
    body: { timezone: "Europe/Brussels", weekdays: {} },
  });
  assert.equal((await emptyWotan.json()).present, true);
  const wotanReopen = await adminRequest(env, "/company/drivers/drv_wotan/schedule");
  assert.equal((await wotanReopen.json()).present, true);

  const quote = await adminRequest(env, "/company/agenda/quote", {
    method: "POST",
    body: {
      from: "Korte Meer 12, 9000 Gent",
      to: "Stationsplein 1, 9600 Ronse",
      pickup_iso: "2026-09-16T18:00:00.000Z",
      from_lat: 51.0543,
      from_lng: 3.7174,
      to_lat: 50.747,
      to_lng: 3.6,
      passengers: 2,
    },
  });
  const quoteJson = await quote.json();
  assert.ok(
    quote.status === 200 || quoteJson.error,
    `quote must answer, got ${quote.status} ${JSON.stringify(quoteJson)}`,
  );

  const created = await adminRequest(env, "/company/agenda/rides", {
    method: "POST",
    headers: { "Idempotency-Key": "chain-ride-1" },
    body: {
      customer_id: "cus_chain",
      customer_name: "Ada",
      from: "Korte Meer 12, 9000 Gent",
      to: "Stationsplein 1, 9600 Ronse",
      pickup_iso: "2026-09-16T18:00:00.000Z",
      duration_min: 40,
      from_lat: 51.0543,
      from_lng: 3.7174,
      to_lat: 50.747,
      to_lng: 3.6,
      price_ex_vat: 44.06,
      price_incl_vat: 53.31,
      currency: "EUR",
    },
  });
  const createdJson = await created.json();
  assert.equal(created.status, 201, JSON.stringify(createdJson));
  const bookingId = createdJson.booking_id;
  assert.ok(bookingId);
  assert.equal(createdJson.item.assignment_accepted, false);

  const assignChris = await adminRequest(
    env,
    `/company/agenda/rides/${bookingId}/assign`,
    {
      method: "POST",
      body: { assigned_driver_id: "drv_chris", revision: createdJson.item.revision },
    },
  );
  const chrisJson = await assignChris.json();
  assert.equal(assignChris.status, 200, JSON.stringify(chrisJson));
  assert.equal(chrisJson.item.assigned_driver_id, "drv_chris");
  assert.equal(chrisJson.item.assignment_accepted, false);
  assert.equal(chrisJson.item.assignment_state, "assigned");

  const listedAfterChris = await adminRequest(
    env,
    "/company/agenda/rides?from=2026-09-16T00:00:00.000Z&to=2026-09-17T00:00:00.000Z",
  );
  const listedChrisJson = await listedAfterChris.json();
  assert.equal(listedChrisJson.items[0].assigned_driver_id, "drv_chris");

  const switchWotan = await adminRequest(
    env,
    `/company/agenda/rides/${bookingId}/assign`,
    {
      method: "POST",
      body: { assigned_driver_id: "drv_wotan", revision: chrisJson.item.revision },
    },
  );
  const switchJson = await switchWotan.json();
  assert.equal(switchWotan.status, 409, JSON.stringify(switchJson));
  assert.equal(switchJson.error, "assignment_driver_not_scheduled");

  const rereadAfterReject = await adminRequest(
    env,
    "/company/agenda/rides?from=2026-09-16T00:00:00.000Z&to=2026-09-17T00:00:00.000Z",
  );
  const rereadRejectJson = await rereadAfterReject.json();
  assert.equal(rereadRejectJson.items[0].assigned_driver_id, "drv_chris");
  assert.equal(rereadRejectJson.items[0].assignment_accepted, false);

  const hoursForWotan = await adminRequest(env, "/company/drivers/drv_wotan/schedule", {
    method: "PUT",
    body: {
      timezone: "Europe/Brussels",
      weekdays: {
        3: [{ start: "07:00", end: "23:00" }],
      },
    },
  });
  assert.equal(hoursForWotan.status, 200);

  const switched = await adminRequest(
    env,
    `/company/agenda/rides/${bookingId}/assign`,
    {
      method: "POST",
      body: { assigned_driver_id: "drv_wotan", revision: chrisJson.item.revision },
    },
  );
  const switchedJson = await switched.json();
  assert.equal(switched.status, 200, JSON.stringify(switchedJson));
  assert.equal(switchedJson.item.assigned_driver_id, "drv_wotan");
  assert.equal(switchedJson.item.assignment_accepted, false);

  const other = await adminRequest(env, "/company/agenda/rides", {
    method: "POST",
    headers: { "Idempotency-Key": "chain-ride-2" },
    body: {
      customer_id: "cus_chain_2",
      from: "Korte Meer 12, 9000 Gent",
      to: "Oudenaarde",
      pickup_iso: "2026-09-16T18:10:00.000Z",
      duration_min: 40,
    },
  });
  const otherJson = await other.json();
  const overlap = await adminRequest(
    env,
    `/company/agenda/rides/${otherJson.booking_id}/assign`,
    {
      method: "POST",
      body: { assigned_driver_id: "drv_wotan" },
    },
  );
  const overlapJson = await overlap.json();
  assert.equal(overlap.status, 409, JSON.stringify(overlapJson));
  assert.equal(overlapJson.error, "assignment_overlap");

  const reopenedAgenda = await adminRequest(
    env,
    "/company/agenda/rides?from=2026-09-16T00:00:00.000Z&to=2026-09-17T00:00:00.000Z",
  );
  const agendaJson = await reopenedAgenda.json();
  const first = agendaJson.items.find((item) => item.booking_id === bookingId);
  assert.equal(first.assigned_driver_id, "drv_wotan");
  assert.equal(first.assignment_accepted, false);
  assert.equal(first.assignment_state, "assigned");
});

test("driver session cannot write another driver's roster through the Worker", async () => {
  const kv = memoryKV();
  seedFleet(kv);
  const env = envWith(kv);
  const res = await worker.fetch(
    new Request("https://example.test/company/drivers/drv_wotan/schedule?tenant_id=TA&company_id=CA", {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        tenant_id: TENANT,
        company_id: COMPANY,
        weekdays: { 1: [{ start: "09:00", end: "17:00" }] },
      }),
    }),
    env,
    {},
  );
  assert.ok(res.status === 401 || res.status === 403);
});

test("public payment projection distinguishes load / missing / not offered", async () => {
  const scopeFromPartnerId = () => ({ tenant_id: TENANT, company_id: COMPANY });
  const failed = await projectPublicPartnerPaymentForProfile({
    partnerId: "company:TA:CA",
    scopeFromPartnerId,
    loadBusinessProfile: async () => {
      throw new Error("kv");
    },
  });
  assert.equal(failed.status, "load_failed");

  const missing = await projectPublicPartnerPaymentForProfile({
    partnerId: "company:TA:CA",
    scopeFromPartnerId,
    loadBusinessProfile: async () => null,
  });
  assert.equal(missing.status, "missing");

  const notOffered = await projectPublicPartnerPaymentForProfile({
    partnerId: "company:TA:CA",
    scopeFromPartnerId,
    loadBusinessProfile: async () => ({ payment_owner_mode: "manual_only" }),
  });
  assert.equal(notOffered.status, "not_offered");
  assert.equal(notOffered.payment_capability.payment_owner_mode, "manual_only");

  const ok = await projectPublicPartnerPaymentForProfile({
    partnerId: "company:TA:CA",
    scopeFromPartnerId,
    loadBusinessProfile: async () => ({
      payment_owner_mode: "company_mollie",
      mollie_connected: true,
      public_payment_options: ["bancontact"],
      iban: "BE68539007547034",
      country: "BE",
    }),
  });
  assert.equal(ok.status, "ok");
  assert.equal(ok.payment_capability.qr_transfer_available, true);
  assert.equal(ok.payment_capability.iban, undefined);
});
