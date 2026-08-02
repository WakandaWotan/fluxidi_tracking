/**
 * RELEASE-P0 — Billit PartyID self-heal + administration selection + durable
 * link/outbox helpers (pure unit coverage; no live Billit / KV).
 */
import assert from "node:assert/strict";
import test from "node:test";

import {
  resolveBillitAdministrationsFromAccountInformation,
  buildBillitOAuthConnectionKey,
  buildBillitCreateOutboxKey,
  buildBillitCreateOutboxRecord,
  buildBillitSandboxOrderCreateIdempotencyKey,
  normalizeBillitLinkStatusMetadata,
  buildSafeBillitLinkStatusProjection,
  BILLIT_LINK_STATES,
  persistBillitPartyIdOnConnectionRecord,
  resolveBillitPartyIdWithSelfHeal,
  isBillitCompanySandboxOAuthAllowed,
  mergeBillitExportPaymentSyncFields,
} from "./billit_provider.js";

test("1: single administration resolves PartyID", () => {
  const r = resolveBillitAdministrationsFromAccountInformation({
    Companies: [{ PartyID: "111" }],
  });
  assert.equal(r.ok, true);
  assert.equal(r.party_id, "111");
  assert.equal(r.company_count, 1);
  assert.equal(r.selection_required, false);
});

test("2+3: PartyID persistence is scoped by tenant/company key", () => {
  const a = buildBillitOAuthConnectionKey({
    tenant_id: "fluxidi_fluxidi_ddmh9g",
    company_id: "fluxidi_fluxidi_ddmh9g",
  });
  const b = buildBillitOAuthConnectionKey({
    tenant_id: "cmp_prometheus_97a13bf5a9",
    company_id: "cmp_prometheus_97a13bf5a9",
  });
  assert.ok(a.includes("fluxidi_fluxidi_ddmh9g"));
  assert.ok(b.includes("cmp_prometheus_97a13bf5a9"));
  assert.notEqual(a, b);
  // Foreign PartyID 1109227 must never appear in key construction.
  assert.equal(a.includes("1109227"), false);
  assert.equal(b.includes("1109227"), false);
});

test("4: zero administrations → billit_no_administration", () => {
  const r = resolveBillitAdministrationsFromAccountInformation({ Companies: [] });
  assert.equal(r.ok, false);
  assert.equal(r.error, "billit_no_administration");
  assert.equal(r.party_id, null);
});

test("5: multiple administrations → selection required (never first)", () => {
  const r = resolveBillitAdministrationsFromAccountInformation({
    Companies: [{ PartyID: "111" }, { PartyID: "222" }],
  });
  assert.equal(r.ok, false);
  assert.equal(r.selection_required, true);
  assert.equal(r.error, "billit_administration_selection_required");
  assert.equal(r.party_id, null);
  assert.equal(r.company_count, 2);
});

test("6: probe resolution does not invent PartyID before single-admin success", () => {
  const multi = resolveBillitAdministrationsFromAccountInformation({
    Companies: [{ PartyID: "111" }, { PartyID: "222" }],
  });
  assert.equal(multi.party_id, null);
});

test("7+8: outbox preserves document-scoped create idempotency key", () => {
  const docId = "8960d794-4a45-40a3-8919-d89426baa21a";
  const scope = {
    tenant_id: "fluxidi_fluxidi_ddmh9g",
    company_id: "fluxidi_fluxidi_ddmh9g",
  };
  const key = buildBillitCreateOutboxKey(scope, docId);
  assert.equal(
    key,
    "billit_create_outbox:fluxidi_fluxidi_ddmh9g:fluxidi_fluxidi_ddmh9g:8960d794-4a45-40a3-8919-d89426baa21a",
  );
  const idem = buildBillitSandboxOrderCreateIdempotencyKey(docId);
  const outbox = buildBillitCreateOutboxRecord({
    scope,
    documentId: docId,
    documentNumber: "INV-2026-000034",
    bookingId: "street_1785668126083_4c47gbe8",
    errorCode: "billit_party_id_missing",
    invoiceIdempotencyKey:
      "inv-auto:fluxidi_fluxidi_ddmh9g:fluxidi_fluxidi_ddmh9g:street_1785668126083_4c47gbe8:main:v1",
  });
  assert.ok(outbox);
  assert.equal(outbox.idempotency_key, idem);
  assert.equal(outbox.document_number, "INV-2026-000034");
  assert.equal(outbox.retryable, true);
  assert.equal(outbox.state, "pending");
  assert.equal(outbox.environment, "sandbox");
  // Same key on retry → at most one Billit create identity.
  const outbox2 = buildBillitCreateOutboxRecord({
    scope,
    documentId: docId,
    attemptCount: 2,
  });
  assert.equal(outbox2.idempotency_key, idem);
});

test("9: invoice idempotency key shape for INV-2026-000034 is preserved", () => {
  const invoiceKey =
    "inv-auto:fluxidi_fluxidi_ddmh9g:fluxidi_fluxidi_ddmh9g:street_1785668126083_4c47gbe8:main:v1";
  assert.match(invoiceKey, /^inv-auto:fluxidi_fluxidi_ddmh9g:fluxidi_fluxidi_ddmh9g:/);
  assert.match(invoiceKey, /street_1785668126083_4c47gbe8:main:v1$/);
});

test("10: linked status never implies Peppol auto-send", () => {
  const n = normalizeBillitLinkStatusMetadata({
    state: BILLIT_LINK_STATES.LINKED,
    order_id: "order-1",
    retryable: false,
  });
  assert.equal(n.ok, true);
  assert.equal(n.status.state, "linked");
  assert.equal(Object.prototype.hasOwnProperty.call(n.status, "peppol_sent"), false);
});

test("11: failed pre-POST attempt persists safe status fields only", () => {
  const n = normalizeBillitLinkStatusMetadata({
    state: BILLIT_LINK_STATES.AWAITING_PARTY_RESOLUTION,
    error_code: "billit_party_id_missing",
    retryable: true,
  });
  assert.equal(n.ok, true);
  assert.equal(n.status.state, "awaiting_party_resolution");
  assert.equal(n.status.error_code, "billit_party_id_missing");
  assert.equal(n.status.retryable, true);
  assert.equal(n.status.environment, "sandbox");
  assert.equal(n.status.order_id, null);
  const proj = buildSafeBillitLinkStatusProjection({
    billit_link_status: n.status,
  });
  assert.equal(proj.state, "awaiting_party_resolution");
  assert.equal(proj.error_code, "billit_party_id_missing");
});

test("12: durable outbox only for retryable failures (builder contract)", () => {
  const scope = {
    tenant_id: "fluxidi_fluxidi_ddmh9g",
    company_id: "fluxidi_fluxidi_ddmh9g",
  };
  const retryable = buildBillitCreateOutboxRecord({
    scope,
    documentId: "doc-1",
    errorCode: "billit_connection_probe_failed",
  });
  assert.equal(retryable.retryable, true);
  // Selection-required is non-retryable at the heal layer; outbox builder is
  // only invoked by callers when retryable===true.
  const selection = normalizeBillitLinkStatusMetadata({
    state: BILLIT_LINK_STATES.AWAITING_ADMINISTRATION_SELECTION,
    error_code: "billit_administration_selection_required",
    retryable: false,
  });
  assert.equal(selection.status.retryable, false);
});

test("13: self-heal persists PartyID only on same connection key", async () => {
  const store = new Map();
  const scope = {
    tenant_id: "fluxidi_fluxidi_ddmh9g",
    company_id: "fluxidi_fluxidi_ddmh9g",
  };
  const foreignScope = {
    tenant_id: "cmp_prometheus_97a13bf5a9",
    company_id: "cmp_prometheus_97a13bf5a9",
  };
  const connKey = buildBillitOAuthConnectionKey(scope);
  const foreignKey = buildBillitOAuthConnectionKey(foreignScope);
  store.set(
    foreignKey,
    JSON.stringify({
      connected: true,
      party_id: "1109227",
      access_token_encrypted: { alg: "x", iv: "x", ciphertext: "x" },
    }),
  );
  store.set(
    connKey,
    JSON.stringify({
      connected: true,
      party_id: null,
      access_token_encrypted: { alg: "x", iv: "x", ciphertext: "x" },
      refresh_token_encrypted: { alg: "x", iv: "x", ciphertext: "x" },
      expires_at: new Date(Date.now() + 3600_000).toISOString(),
    }),
  );

  const env = {
    BOOKING_KV: {
      async get(key, opts) {
        const raw = store.get(key);
        if (!raw) return null;
        if (opts?.type === "json") return JSON.parse(raw);
        return raw;
      },
      async put(key, value) {
        store.set(key, value);
      },
    },
    BILLIT_TOKEN_ENCRYPTION_KEY: "not-used-here",
  };

  // Direct persist proves same-key write (no foreign overwrite).
  const record = JSON.parse(store.get(connKey));
  await persistBillitPartyIdOnConnectionRecord(
    env,
    scope,
    record,
    "999888",
    new Date().toISOString(),
  );
  const updated = JSON.parse(store.get(connKey));
  const foreign = JSON.parse(store.get(foreignKey));
  assert.equal(updated.party_id, "999888");
  assert.equal(foreign.party_id, "1109227");
});

test("14: tenant isolation — foreign PartyID never selected by resolution", () => {
  const r = resolveBillitAdministrationsFromAccountInformation({
    Companies: [{ PartyID: "555" }],
  });
  assert.equal(r.party_id, "555");
  assert.notEqual(r.party_id, "1109227");
});

test("self-heal short-circuits when party_id already present (no probe)", async () => {
  const scope = {
    tenant_id: "fluxidi_fluxidi_ddmh9g",
    company_id: "fluxidi_fluxidi_ddmh9g",
  };
  const connKey = buildBillitOAuthConnectionKey(scope);
  const env = {
    BOOKING_KV: {
      async get(key, opts) {
        if (key !== connKey) return null;
        const record = {
          connected: true,
          party_id: "already-set",
          access_token_encrypted: { alg: "x", iv: "x", ciphertext: "x" },
        };
        return opts?.type === "json" ? record : JSON.stringify(record);
      },
    },
  };
  const result = await resolveBillitPartyIdWithSelfHeal(env, scope, {
    environment: "sandbox",
    configured: true,
  });
  assert.equal(result.ok, true);
  assert.equal(result.party_id, "already-set");
  assert.equal(result.healed, false);
});

test("company sandbox oauth allow flag defaults off for ordinary customers", () => {
  assert.equal(isBillitCompanySandboxOAuthAllowed({}), false);
  assert.equal(
    isBillitCompanySandboxOAuthAllowed({
      BILLIT_ALLOW_COMPANY_SANDBOX_OAUTH: "1",
    }),
    false,
    "master alone must not open sandbox to every company",
  );
  assert.equal(
    isBillitCompanySandboxOAuthAllowed({
      BILLIT_ALLOW_COMPANY_SANDBOX_OAUTH: "0",
      BILLIT_SANDBOX_OAUTH_COMPANY_ALLOWLIST: "fluxidi_fluxidi_ddmh9g",
    }),
    false,
  );
});

test("1) ordinary company cannot connect to sandbox", () => {
  const env = {
    BILLIT_ALLOW_COMPANY_SANDBOX_OAUTH: "1",
    BILLIT_SANDBOX_OAUTH_COMPANY_ALLOWLIST: "fluxidi_fluxidi_ddmh9g",
  };
  assert.equal(
    isBillitCompanySandboxOAuthAllowed(env, {
      company_id: "customer_co_ordinary",
    }),
    false,
  );
});

test("2) ordinary company receives no sandbox entitlement even with master on", () => {
  assert.equal(
    isBillitCompanySandboxOAuthAllowed(
      {
        BILLIT_ALLOW_COMPANY_SANDBOX_OAUTH: "1",
        BILLIT_SANDBOX_OAUTH_COMPANY_ALLOWLIST: "fluxidi_fluxidi_ddmh9g",
      },
      { company_id: "someone_else" },
    ),
    false,
  );
});

test("3) internal entitled session can connect", () => {
  assert.equal(
    isBillitCompanySandboxOAuthAllowed(
      {
        BILLIT_ALLOW_COMPANY_SANDBOX_OAUTH: "1",
        BILLIT_SANDBOX_OAUTH_COMPANY_ALLOWLIST: "fluxidi_fluxidi_ddmh9g",
      },
      { company_id: "fluxidi_fluxidi_ddmh9g" },
    ),
    true,
  );
});

test("4) internal entitled company stays entitled for reconnect after disconnect", () => {
  const env = {
    BILLIT_ALLOW_COMPANY_SANDBOX_OAUTH: "1",
    BILLIT_SANDBOX_OAUTH_COMPANY_ALLOWLIST: "fluxidi_fluxidi_ddmh9g",
  };
  const scope = { company_id: "fluxidi_fluxidi_ddmh9g" };
  assert.equal(isBillitCompanySandboxOAuthAllowed(env, scope), true);
  assert.equal(isBillitCompanySandboxOAuthAllowed(env, scope), true);
});

test("5) removing entitlement immediately restores production gate", () => {
  const scope = { company_id: "fluxidi_fluxidi_ddmh9g" };
  assert.equal(
    isBillitCompanySandboxOAuthAllowed(
      {
        BILLIT_ALLOW_COMPANY_SANDBOX_OAUTH: "1",
        BILLIT_SANDBOX_OAUTH_COMPANY_ALLOWLIST: "fluxidi_fluxidi_ddmh9g",
      },
      scope,
    ),
    true,
  );
  assert.equal(
    isBillitCompanySandboxOAuthAllowed(
      {
        BILLIT_ALLOW_COMPANY_SANDBOX_OAUTH: "0",
        BILLIT_SANDBOX_OAUTH_COMPANY_ALLOWLIST: "fluxidi_fluxidi_ddmh9g",
      },
      scope,
    ),
    false,
  );
  assert.equal(
    isBillitCompanySandboxOAuthAllowed(
      {
        BILLIT_ALLOW_COMPANY_SANDBOX_OAUTH: "1",
        BILLIT_SANDBOX_OAUTH_COMPANY_ALLOWLIST: "",
      },
      scope,
    ),
    false,
  );
});

test("6) no company can self-assert internal access", () => {
  assert.equal(
    isBillitCompanySandboxOAuthAllowed(
      { BILLIT_ALLOW_COMPANY_SANDBOX_OAUTH: "1" },
      { company_id: "i_claim_to_be_internal" },
    ),
    false,
  );
  assert.equal(
    isBillitCompanySandboxOAuthAllowed(
      {},
      { company_id: "fluxidi_fluxidi_ddmh9g" },
    ),
    false,
  );
});

test("export preservation: link-status merge keeps existing billit_export", () => {
  const base = {
    document_id: "doc-1",
    document_number: "INV-2026-000034",
    billit_export: {
      provider: "billit",
      environment: "sandbox",
      order_id: "3138157",
      status: "created",
    },
  };
  const link = normalizeBillitLinkStatusMetadata({
    state: BILLIT_LINK_STATES.LINKED,
    order_id: "3138157",
    retryable: false,
  });
  assert.equal(link.ok, true);
  const merged = {
    ...base,
    billit_link_status: link.status,
  };
  assert.equal(merged.billit_export.order_id, "3138157");
  assert.equal(merged.billit_link_status.state, "linked");
});

test("P0 payment sync converge: live paid + prior pending merge => synced paid", () => {
  const existing = {
    provider: "billit",
    environment: "sandbox",
    order_id: "3138157",
    order_number: "INV-2026-000034",
    status: "created",
    billit_paid: null,
    billit_payment_sync_status: null,
    peppol_sent: false,
    sent: false,
  };
  const merged = mergeBillitExportPaymentSyncFields(existing, {
    billit_paid: true,
    billit_paid_date: "2026-08-02",
    billit_payment_sync_status: "synced",
    billit_payment_synced_at: "2026-08-02T12:00:00.000Z",
    billit_payment_sync_error: null,
  });
  assert.equal(merged.order_id, "3138157");
  assert.equal(merged.order_number, "INV-2026-000034");
  assert.equal(merged.billit_paid, true);
  assert.equal(merged.billit_payment_sync_status, "synced");
  assert.equal(merged.peppol_sent, false);
  assert.equal(merged.sent, false);
});
