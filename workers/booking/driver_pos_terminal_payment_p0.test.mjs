// TAP-TO-PAY-SERVER-CONTRACT-1 — route-level driver POS tests
// Run: node --test workers/booking/driver_pos_terminal_payment_p0.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import worker from "./fluxidi_booking_worker.js";
import {
  buildScopedMollieConnectAuthKey,
  buildScopedMollieTerminalsSnapshotKey,
  encryptMollieConnectTokenPayload,
} from "./modules/mollie_connect.js";

const ADMIN = "test-admin-token";
const ENC_KEY = "test-mollie-connect-encryption-key-please-rotate";
const TENANT = "T1";
const COMPANY = "C1";
const BOOKING = "bk_planned_pos_1";
const DRIVER = "D1";

async function sha256Hex(text) {
  const data = new TextEncoder().encode(String(text || ""));
  const digest = await crypto.subtle.digest("SHA-256", data);
  const bytes = new Uint8Array(digest);
  let hex = "";
  for (const byte of bytes) hex += byte.toString(16).padStart(2, "0");
  return hex;
}

function makeKV(seed = {}) {
  const store = new Map(Object.entries(seed));
  return {
    store,
    async get(key, opts) {
      if (!store.has(key)) return null;
      const raw = store.get(key);
      if (opts && opts.type === "json") {
        try {
          return typeof raw === "string" ? JSON.parse(raw) : raw;
        } catch (_) {
          return null;
        }
      }
      return typeof raw === "string" ? raw : JSON.stringify(raw);
    },
    async put(key, val) {
      store.set(key, val);
    },
    async delete(key) {
      store.delete(key);
    },
    async list() {
      return {
        keys: [...store.keys()].map((name) => ({ name })),
        list_complete: true,
      };
    },
  };
}

async function seedDriverSession({ tokenValue, tenantId, companyId, driverId }) {
  const hash = await sha256Hex(tokenValue);
  return {
    key: `public_driver:session:${hash}:v1`,
    record: {
      role: "driver",
      tenant_id: tenantId,
      company_id: companyId,
      driver_id: driverId,
      expires_at: new Date(Date.now() + 3600_000).toISOString(),
    },
  };
}

async function seedMollieCredentials(kv, { tenantId, companyId }) {
  const encEnv = { MOLLIE_CONNECT_ENCRYPTION_KEY: ENC_KEY };
  const encrypted = await encryptMollieConnectTokenPayload(
    {
      access_token: "access_live_test",
      refresh_token: "refresh_live_test",
    },
    encEnv,
  );
  const key = buildScopedMollieConnectAuthKey({
    tenant_id: tenantId,
    company_id: companyId,
  });
  await kv.put(
    key,
    JSON.stringify({
      version: 1,
      connected: true,
      status: "connected",
      organizationId: "org_1",
      profileId: "pfl_1",
      mollie_profile_id: "pfl_1",
      mollie_mode: "live",
      onboardingStatus: "completed",
      canReceivePayments: true,
      payment_owner_mode: "company_mollie",
      ...encrypted,
      expiresAt: new Date(Date.now() + 3600_000).toISOString(),
      lastConnectedAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    }),
  );
}

async function seedTerminalSnapshot(kv, { tenantId, companyId, terminals }) {
  const key = buildScopedMollieTerminalsSnapshotKey({
    tenant_id: tenantId,
    company_id: companyId,
    testmode: false,
  });
  await kv.put(
    key,
    JSON.stringify({
      version: 1,
      testmode: false,
      mollie_mode: "live",
      terminals,
      synced_at: new Date().toISOString(),
    }),
  );
}

function plannedBooking(over = {}) {
  return {
    booking_id: BOOKING,
    tenant_id: TENANT,
    company_id: COMPANY,
    owner_tenant_id: TENANT,
    owner_company_id: COMPANY,
    source: "customer_app",
    ride_type: "planned",
    status: "COMPLETED",
    payment_status: "unpaid",
    price_incl_vat: 42.5,
    currency: "EUR",
    assigned_driver_id: DRIVER,
    ...over,
  };
}

function envFor(kv) {
  return {
    ADMIN_TOKEN: ADMIN,
    BOOKING_KV: kv,
    MOLLIE_CONNECT_ENCRYPTION_KEY: ENC_KEY,
    MOLLIE_COMPANY_PAYMENTS_ENABLED: "true",
    MOLLIE_COMPANY_LIVE_PAYMENTS_ENABLED: "true",
  };
}

function startReq(body, token) {
  return new Request(
    "https://booking.internal/driver/mollie/terminal-payment/start",
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${token}`,
      },
      body: JSON.stringify(body),
    },
  );
}

function statusReq(body, token) {
  return new Request(
    "https://booking.internal/driver/mollie/terminal-payment/status",
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${token}`,
      },
      body: JSON.stringify(body),
    },
  );
}

test("driver POS start: planned booking uses server fixed price; client amount ignored", async () => {
  const kv = makeKV();
  const session = await seedDriverSession({
    tokenValue: "drv-pos-1",
    tenantId: TENANT,
    companyId: COMPANY,
    driverId: DRIVER,
  });
  await kv.put(session.key, JSON.stringify(session.record));
  await kv.put(`booking:${BOOKING}`, JSON.stringify(plannedBooking()));
  await seedMollieCredentials(kv, { tenantId: TENANT, companyId: COMPANY });
  await seedTerminalSnapshot(kv, {
    tenantId: TENANT,
    companyId: COMPANY,
    terminals: [{ id: "term_1", status: "active", profile_id: "pfl_1" }],
  });

  const prevFetch = globalThis.fetch;
  let createCalls = 0;
  globalThis.fetch = async (url, init) => {
    const u = String(url);
    if (u.includes("api.mollie.com") && init?.method === "POST") {
      createCalls += 1;
      const body = JSON.parse(init.body);
      assert.equal(body.amount.value, "42.50");
      assert.equal(body.method, "pointofsale");
      assert.equal(body.terminalId, "term_1");
      assert.ok(String(body.redirectUrl || "").includes("/pay/return"));
      assert.ok(String(body.webhookUrl || "").includes("/webhook/mollie"));
      assert.equal(body.profileId, "pfl_1");
      return new Response(
        JSON.stringify({ id: "tr_pos_1", status: "open" }),
        { status: 201 },
      );
    }
    return new Response(JSON.stringify({ ok: false }), { status: 404 });
  };

  try {
    const res = await worker.fetch(
      startReq(
        {
          booking_id: BOOKING,
          tenant_id: TENANT,
          company_id: COMPANY,
          amount: { currency: "EUR", value: "999.99" },
        },
        "drv-pos-1",
      ),
      envFor(kv),
    );
    const body = await res.json();
    assert.equal(res.status, 200);
    assert.equal(body.ok, true);
    assert.equal(body.amount.value, "42.50");
    assert.equal(body.payment_id, "tr_pos_1");
    assert.equal(createCalls, 1);
    const routeRaw = await kv.get("mollie_payment_route:tr_pos_1:v1");
    assert.ok(routeRaw);
    const route = JSON.parse(routeRaw);
    assert.equal(route.tenant_id, TENANT);
    assert.equal(route.company_id, COMPANY);
    assert.equal(route.booking_id, BOOKING);
    assert.equal(route.channel, "pos_terminal");
  } finally {
    globalThis.fetch = prevFetch;
  }
});

test("driver POS start: already paid rejected; foreign tenant opaque", async () => {
  const kv = makeKV();
  const session = await seedDriverSession({
    tokenValue: "drv-pos-2",
    tenantId: TENANT,
    companyId: COMPANY,
    driverId: DRIVER,
  });
  await kv.put(session.key, JSON.stringify(session.record));
  await kv.put(
    `booking:${BOOKING}`,
    JSON.stringify(plannedBooking({ payment_status: "paid" })),
  );
  await seedMollieCredentials(kv, { tenantId: TENANT, companyId: COMPANY });
  await seedTerminalSnapshot(kv, {
    tenantId: TENANT,
    companyId: COMPANY,
    terminals: [{ id: "term_1", status: "active", profile_id: "pfl_1" }],
  });

  const resPaid = await worker.fetch(
    startReq({ booking_id: BOOKING }, "drv-pos-2"),
    envFor(kv),
  );
  assert.equal(resPaid.status, 409);
  const paidBody = await resPaid.json();
  assert.equal(paidBody.error, "payment_already_paid");

  await kv.put(
    `booking:bk_other`,
    JSON.stringify(
      plannedBooking({
        booking_id: "bk_other",
        tenant_id: "T2",
        company_id: "C2",
        owner_tenant_id: "T2",
        owner_company_id: "C2",
        payment_status: "unpaid",
      }),
    ),
  );
  const resForeign = await worker.fetch(
    startReq({ booking_id: "bk_other" }, "drv-pos-2"),
    envFor(kv),
  );
  assert.ok(resForeign.status === 404 || resForeign.status === 403);
});

test("driver POS start: no active terminal fails clearly; double start reuses intent", async () => {
  const kv = makeKV();
  const session = await seedDriverSession({
    tokenValue: "drv-pos-3",
    tenantId: TENANT,
    companyId: COMPANY,
    driverId: DRIVER,
  });
  await kv.put(session.key, JSON.stringify(session.record));
  await kv.put(`booking:${BOOKING}`, JSON.stringify(plannedBooking()));
  await seedMollieCredentials(kv, { tenantId: TENANT, companyId: COMPANY });
  await seedTerminalSnapshot(kv, {
    tenantId: TENANT,
    companyId: COMPANY,
    terminals: [{ id: "term_inactive", status: "inactive", profile_id: "pfl_1" }],
  });

  const resNoTerm = await worker.fetch(
    startReq({ booking_id: BOOKING }, "drv-pos-3"),
    envFor(kv),
  );
  const noTermBody = await resNoTerm.json();
  assert.equal(resNoTerm.status, 400);
  assert.equal(noTermBody.error, "terminal_not_configured");

  await seedTerminalSnapshot(kv, {
    tenantId: TENANT,
    companyId: COMPANY,
    terminals: [{ id: "term_1", status: "active", profile_id: "pfl_1" }],
  });

  let createCalls = 0;
  const prevFetch = globalThis.fetch;
  globalThis.fetch = async (url, init) => {
    if (String(url).includes("api.mollie.com") && init?.method === "POST") {
      createCalls += 1;
      return new Response(
        JSON.stringify({ id: "tr_reuse", status: "open" }),
        { status: 201 },
      );
    }
    return new Response("{}", { status: 404 });
  };
  try {
    const first = await worker.fetch(
      startReq({ booking_id: BOOKING }, "drv-pos-3"),
      envFor(kv),
    );
    const firstBody = await first.json();
    assert.equal(first.status, 200);
    assert.equal(firstBody.status, "created");

    const second = await worker.fetch(
      startReq({ booking_id: BOOKING }, "drv-pos-3"),
      envFor(kv),
    );
    const secondBody = await second.json();
    assert.equal(second.status, 200);
    assert.equal(secondBody.status, "existing_open");
    assert.equal(secondBody.payment_id, "tr_reuse");
    assert.equal(createCalls, 1);
  } finally {
    globalThis.fetch = prevFetch;
  }
});

test("driver POS start: Mollie Idempotency-Key is compact and stable across timeout retry", async () => {
  const kv = makeKV();
  const session = await seedDriverSession({
    tokenValue: "drv-pos-idem",
    tenantId: TENANT,
    companyId: COMPANY,
    driverId: DRIVER,
  });
  await kv.put(session.key, JSON.stringify(session.record));
  await kv.put(`booking:${BOOKING}`, JSON.stringify(plannedBooking()));
  await seedMollieCredentials(kv, { tenantId: TENANT, companyId: COMPANY });
  await seedTerminalSnapshot(kv, {
    tenantId: TENANT,
    companyId: COMPANY,
    terminals: [{ id: "term_1", status: "active", profile_id: "pfl_1" }],
  });

  const seenKeys = [];
  let createCalls = 0;
  const prevFetch = globalThis.fetch;
  globalThis.fetch = async (url, init) => {
    if (String(url).includes("api.mollie.com") && init?.method === "POST") {
      createCalls += 1;
      const idem = init.headers?.["Idempotency-Key"] || init.headers?.["idempotency-key"];
      seenKeys.push(String(idem || ""));
      assert.ok(String(idem).length <= 100, `idempotency key too long: ${String(idem).length}`);
      assert.match(String(idem), /^fluxidi-pos-v1:[0-9a-f]{64}$/);
      // Field regression: legacy sanitized intent key was 133 chars.
      assert.ok(!String(idem).includes("mollie_driver_pos_intent"));
      if (createCalls === 1) {
        throw new Error("network timeout");
      }
      const body = JSON.parse(init.body);
      assert.equal(body.method, "pointofsale");
      assert.equal(body.terminalId, "term_1");
      assert.equal(body.amount.value, "42.50");
      return new Response(
        JSON.stringify({ id: "tr_idem_1", status: "open" }),
        { status: 201 },
      );
    }
    return new Response("{}", { status: 404 });
  };

  try {
    const failRes = await worker.fetch(
      startReq({ booking_id: BOOKING }, "drv-pos-idem"),
      envFor(kv),
    );
    const failBody = await failRes.json();
    assert.equal(failBody.ok, false);
    assert.equal(failBody.error, "mollie_terminal_payment_create_failed");

    const okRes = await worker.fetch(
      startReq({ booking_id: BOOKING }, "drv-pos-idem"),
      envFor(kv),
    );
    const okBody = await okRes.json();
    assert.equal(okRes.status, 200);
    assert.equal(okBody.ok, true);
    assert.equal(okBody.payment_id, "tr_idem_1");
    assert.equal(createCalls, 2);
    assert.equal(seenKeys.length, 2);
    assert.equal(seenKeys[0], seenKeys[1]);

    // No duplicate create on third start — reuses open intent.
    const reuseRes = await worker.fetch(
      startReq({ booking_id: BOOKING }, "drv-pos-idem"),
      envFor(kv),
    );
    const reuseBody = await reuseRes.json();
    assert.equal(reuseBody.status, "existing_open");
    assert.equal(reuseBody.payment_id, "tr_idem_1");
    assert.equal(createCalls, 2);
  } finally {
    globalThis.fetch = prevFetch;
  }
});

test("driver POS start: Mollie 4xx persists status/title/detail; no intent/shadow", async () => {
  const kv = makeKV();
  const session = await seedDriverSession({
    tokenValue: "drv-pos-fail4",
    tenantId: TENANT,
    companyId: COMPANY,
    driverId: DRIVER,
  });
  await kv.put(session.key, JSON.stringify(session.record));
  await kv.put(`booking:${BOOKING}`, JSON.stringify(plannedBooking()));
  await seedMollieCredentials(kv, { tenantId: TENANT, companyId: COMPANY });
  await seedTerminalSnapshot(kv, {
    tenantId: TENANT,
    companyId: COMPANY,
    terminals: [{ id: "term_1", status: "active", profile_id: "pfl_1" }],
  });

  const prevFetch = globalThis.fetch;
  globalThis.fetch = async (url, init) => {
    if (String(url).includes("api.mollie.com") && init?.method === "POST") {
      const body = JSON.parse(init.body);
      assert.equal(body.method, "pointofsale");
      assert.equal(body.terminalId, "term_1");
      assert.equal(body.amount.currency, "EUR");
      assert.equal(body.amount.value, "42.50");
      assert.ok(!String(init.body).includes("access_token"));
      return new Response(
        JSON.stringify({
          status: 422,
          title: "Unprocessable Entity",
          detail: "The terminal is not enabled for this profile",
          field: "terminalId",
        }),
        {
          status: 422,
          headers: { "request-id": "req_4xx_pos" },
        },
      );
    }
    return new Response("{}", { status: 404 });
  };

  try {
    const res = await worker.fetch(
      startReq({ booking_id: BOOKING }, "drv-pos-fail4"),
      envFor(kv),
    );
    const body = await res.json();
    assert.equal(body.ok, false);
    assert.equal(body.error, "mollie_terminal_payment_create_failed");
    assert.equal(body.provider_category, "mollie_http_4xx");
    // Generic contract: no raw Mollie title/detail on response.
    assert.equal(body.mollie_title, undefined);
    assert.equal(body.detail, undefined);

    const intentKey = `tenant:${TENANT}:company:${COMPANY}:mollie_driver_pos_intent:${BOOKING}:main:v1`;
    assert.equal(await kv.get(intentKey), null);

    const latestKey = `tenant:${TENANT}:company:${COMPANY}:mollie_driver_pos_start_fail:${BOOKING}:latest:v1`;
    const diag = JSON.parse(await kv.get(latestKey));
    assert.equal(diag.mollie_http_status, 422);
    assert.equal(diag.mollie_title, "Unprocessable Entity");
    assert.match(diag.mollie_detail, /terminal is not enabled/);
    assert.equal(diag.mollie_field, "terminalId");
    assert.equal(diag.mollie_request_id, "req_4xx_pos");
    assert.equal(diag.request_method, "pointofsale");
    assert.equal(diag.amount.value, "42.50");
    assert.equal(diag.request_contract.method, "pointofsale");
    assert.ok(!JSON.stringify(diag).includes("Bearer"));
    assert.ok(!JSON.stringify(diag).includes("access_live_test"));
  } finally {
    globalThis.fetch = prevFetch;
  }
});

test("driver POS start: Mollie 5xx persists status/title; timeout has no invented body", async () => {
  const kv = makeKV();
  const session = await seedDriverSession({
    tokenValue: "drv-pos-fail5",
    tenantId: TENANT,
    companyId: COMPANY,
    driverId: DRIVER,
  });
  await kv.put(session.key, JSON.stringify(session.record));
  await kv.put(`booking:${BOOKING}`, JSON.stringify(plannedBooking()));
  await seedMollieCredentials(kv, { tenantId: TENANT, companyId: COMPANY });
  await seedTerminalSnapshot(kv, {
    tenantId: TENANT,
    companyId: COMPANY,
    terminals: [{ id: "term_1", status: "active", profile_id: "pfl_1" }],
  });

  const prevFetch = globalThis.fetch;
  globalThis.fetch = async (url, init) => {
    if (String(url).includes("api.mollie.com") && init?.method === "POST") {
      return new Response(JSON.stringify({ title: "Bad Gateway" }), {
        status: 502,
      });
    }
    return new Response("{}", { status: 404 });
  };
  try {
    const res = await worker.fetch(
      startReq({ booking_id: BOOKING }, "drv-pos-fail5"),
      envFor(kv),
    );
    const body = await res.json();
    assert.equal(body.error, "mollie_terminal_payment_create_failed");
    assert.equal(body.provider_category, "mollie_http_5xx");
    const latestKey = `tenant:${TENANT}:company:${COMPANY}:mollie_driver_pos_start_fail:${BOOKING}:latest:v1`;
    const diag = JSON.parse(await kv.get(latestKey));
    assert.equal(diag.mollie_http_status, 502);
    assert.equal(diag.mollie_title, "Bad Gateway");
    assert.equal(diag.mollie_detail, null);
  } finally {
    globalThis.fetch = prevFetch;
  }

  globalThis.fetch = async () => {
    throw new Error("network timeout");
  };
  try {
    const res = await worker.fetch(
      startReq({ booking_id: BOOKING }, "drv-pos-fail5"),
      envFor(kv),
    );
    const body = await res.json();
    assert.equal(body.error, "mollie_terminal_payment_create_failed");
    assert.equal(body.provider_category, "mollie_network_error");
    const latestKey = `tenant:${TENANT}:company:${COMPANY}:mollie_driver_pos_start_fail:${BOOKING}:latest:v1`;
    const diag = JSON.parse(await kv.get(latestKey));
    assert.equal(diag.provider_category, "mollie_network_error");
    assert.equal(diag.mollie_http_status, null);
    assert.equal(diag.mollie_title, null);
    assert.equal(diag.mollie_detail, null);
    const intentKey = `tenant:${TENANT}:company:${COMPANY}:mollie_driver_pos_intent:${BOOKING}:main:v1`;
    assert.equal(await kv.get(intentKey), null);
  } finally {
    globalThis.fetch = prevFetch;
  }
});

test("driver POS status: only paid marks booking paid; failed keeps unpaid", async () => {
  const kv = makeKV();
  const session = await seedDriverSession({
    tokenValue: "drv-pos-4",
    tenantId: TENANT,
    companyId: COMPANY,
    driverId: DRIVER,
  });
  await kv.put(session.key, JSON.stringify(session.record));
  await kv.put(`booking:${BOOKING}`, JSON.stringify(plannedBooking()));
  await seedMollieCredentials(kv, { tenantId: TENANT, companyId: COMPANY });
  await seedTerminalSnapshot(kv, {
    tenantId: TENANT,
    companyId: COMPANY,
    terminals: [{ id: "term_1", status: "active", profile_id: "pfl_1" }],
  });

  // Seed open intent as if start already ran.
  const intentKey = `tenant:${TENANT}:company:${COMPANY}:mollie_driver_pos_intent:${BOOKING}:main:v1`;
  await kv.put(
    intentKey,
    JSON.stringify({
      payment_id: "tr_status_1",
      mollie_status: "open",
      amount: { currency: "EUR", value: "42.50" },
      billit_sync_triggered: false,
    }),
  );

  const prevFetch = globalThis.fetch;
  globalThis.fetch = async (url) => {
    const u = String(url);
    if (u.includes("tr_status_1") && u.includes("api.mollie.com")) {
      return new Response(JSON.stringify({ id: "tr_status_1", status: "failed" }), {
        status: 200,
      });
    }
    return new Response("{}", { status: 404 });
  };
  try {
    const failedRes = await worker.fetch(
      statusReq({ booking_id: BOOKING, payment_id: "tr_status_1" }, "drv-pos-4"),
      envFor(kv),
    );
    const failedBody = await failedRes.json();
    assert.equal(failedRes.status, 200);
    assert.equal(failedBody.paid, false);
    assert.equal(failedBody.payment_written, false);
    const still = JSON.parse(await kv.get(`booking:${BOOKING}`));
    assert.notEqual(String(still.payment_status).toLowerCase(), "paid");
  } finally {
    globalThis.fetch = prevFetch;
  }

  globalThis.fetch = async (url) => {
    if (String(url).includes("tr_status_1") && String(url).includes("api.mollie.com")) {
      return new Response(
        JSON.stringify({ id: "tr_status_1", status: "paid", method: "pointofsale" }),
        { status: 200 },
      );
    }
    return new Response("{}", { status: 404 });
  };
  try {
    const paidRes = await worker.fetch(
      statusReq({ booking_id: BOOKING, payment_id: "tr_status_1" }, "drv-pos-4"),
      envFor(kv),
    );
    const paidBody = await paidRes.json();
    assert.equal(paidRes.status, 200);
    assert.equal(paidBody.paid, true);
    assert.equal(paidBody.payment_written, true);
    const updated = JSON.parse(await kv.get(`booking:${BOOKING}`));
    assert.equal(String(updated.payment_status).toLowerCase(), "paid");
    assert.equal(String(updated.payment_provider).toLowerCase(), "mollie");
    assert.equal(String(updated.payment_id || updated.mollie_payment_id), "tr_status_1");
    assert.ok(
      String(updated.payment_method || "").toLowerCase().includes("pointofsale") ||
        String(updated.payment_method || "").toLowerCase().includes("in_vehicle") ||
        String(updated.payment_source || "").toLowerCase().includes("tap"),
    );

    // Second status poll must not re-write / re-trigger as a new paid transition.
    const again = await worker.fetch(
      statusReq({ booking_id: BOOKING, payment_id: "tr_status_1" }, "drv-pos-4"),
      envFor(kv),
    );
    const againBody = await again.json();
    assert.equal(againBody.already_paid, true);
    assert.equal(againBody.payment_written, false);
  } finally {
    globalThis.fetch = prevFetch;
  }
});

test("webhook POS route uses company Connect GET (not central demo) and marks paid once", async () => {
  const kv = makeKV();
  await kv.put(`booking:${BOOKING}`, JSON.stringify(plannedBooking()));
  await seedMollieCredentials(kv, { tenantId: TENANT, companyId: COMPANY });
  await kv.put(
    "mollie_payment_route:tr_wh_pos:v1",
    JSON.stringify({
      version: 1,
      payment_id: "tr_wh_pos",
      tenant_id: TENANT,
      company_id: COMPANY,
      booking_id: BOOKING,
      channel: "pos_terminal",
      profile_id: "pfl_1",
    }),
  );
  await kv.put(
    `tenant:${TENANT}:company:${COMPANY}:mollie_driver_pos_intent:${BOOKING}:main:v1`,
    JSON.stringify({
      payment_id: "tr_wh_pos",
      mollie_status: "open",
      amount: { currency: "EUR", value: "42.50" },
      billit_sync_triggered: false,
    }),
  );

  const prevFetch = globalThis.fetch;
  let sawBearer = false;
  let centralDemoTried = false;
  globalThis.fetch = async (url, init) => {
    const u = String(url);
    const auth = String(init?.headers?.Authorization || init?.headers?.authorization || "");
    if (auth.includes("test_") || auth.includes("live_") && !auth.includes("access_live_test")) {
      centralDemoTried = true;
    }
    if (u.includes("tr_wh_pos") && u.includes("api.mollie.com")) {
      if (auth.includes("access_live_test")) sawBearer = true;
      return new Response(
        JSON.stringify({
          id: "tr_wh_pos",
          status: "paid",
          method: "pointofsale",
          profileId: "pfl_1",
          amount: { currency: "EUR", value: "42.50" },
          metadata: {
            bookingId: BOOKING,
            tenantId: TENANT,
            companyId: COMPANY,
            payment_channel: "pos_terminal",
          },
        }),
        { status: 200 },
      );
    }
    return new Response("{}", { status: 404 });
  };

  try {
    const res = await worker.fetch(
      new Request("https://booking.internal/webhook/mollie", {
        method: "POST",
        headers: { "content-type": "application/x-www-form-urlencoded" },
        body: "id=tr_wh_pos",
      }),
      envFor(kv),
    );
    const body = await res.json();
    assert.equal(res.status, 200);
    assert.equal(body.received, true);
    assert.equal(body.processed, true);
    assert.equal(body.paid, true);
    assert.equal(sawBearer, true);
    assert.equal(centralDemoTried, false);
    const updated = JSON.parse(await kv.get(`booking:${BOOKING}`));
    assert.equal(String(updated.payment_status).toLowerCase(), "paid");

    // Duplicate webhook is idempotent.
    const again = await worker.fetch(
      new Request("https://booking.internal/webhook/mollie", {
        method: "POST",
        headers: { "content-type": "application/x-www-form-urlencoded" },
        body: "id=tr_wh_pos",
      }),
      envFor(kv),
    );
    const againBody = await again.json();
    assert.equal(againBody.paid, true);
    assert.equal(againBody.processed, true);
  } finally {
    globalThis.fetch = prevFetch;
  }
});

test("webhook without route does not use central-demo as company POS authority", async () => {
  const kv = makeKV();
  // No route, no central demo success → processed false (company POS cannot be fetched centrally).
  const prevFetch = globalThis.fetch;
  globalThis.fetch = async () => new Response("{}", { status: 401 });
  try {
    const res = await worker.fetch(
      new Request("https://booking.internal/webhook/mollie", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ id: "tr_orphan_pos" }),
      }),
      envFor(kv),
    );
    const body = await res.json();
    assert.equal(res.status, 200);
    assert.equal(body.received, true);
    assert.equal(body.processed, false);
  } finally {
    globalThis.fetch = prevFetch;
  }
});

test("driver POS start: inactive terminal rejected", async () => {
  const kv = makeKV();
  const session = await seedDriverSession({
    tokenValue: "drv-pos-inactive",
    tenantId: TENANT,
    companyId: COMPANY,
    driverId: DRIVER,
  });
  await kv.put(session.key, JSON.stringify(session.record));
  await kv.put(`booking:${BOOKING}`, JSON.stringify(plannedBooking()));
  await seedMollieCredentials(kv, { tenantId: TENANT, companyId: COMPANY });
  await seedTerminalSnapshot(kv, {
    tenantId: TENANT,
    companyId: COMPANY,
    terminals: [{ id: "term_dead", status: "inactive", profile_id: "pfl_1" }],
  });
  const res = await worker.fetch(
    startReq({ booking_id: BOOKING }, "drv-pos-inactive"),
    envFor(kv),
  );
  const body = await res.json();
  assert.equal(body.ok, false);
  assert.ok(
    body.error === "terminal_not_configured" || body.error === "terminal_inactive",
  );
});
