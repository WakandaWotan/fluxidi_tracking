const ALLOWED_EVENT_TYPES = new Set([
  "ride_start",
  "ride_stop",
  "payment_update",
  "booking_status_update",
  "booking_created",
  "booking_confirmed",
  "booking_credit_decision",
  "booking_mollie_refund",
  "correction_event",
  "sync_success",
  "sync_failed",
  "document_issued", // 2G-N activation; voided/provider events stay inert.
]);

/* ===================== DOCUMENT AUDIT EVENT SHAPES (future, inert) =====================
 * Provider-neutral naming + payload shape for FUTURE append-only document audit
 * events recommended by the 2G-D audit (Booking Worker owns registry/numbering;
 * Compliance Worker later receives the audit trail). This block is intentionally
 * inert:
 *   - it is NOT added to ALLOWED_EVENT_TYPES, so append validation is unchanged
 *     and none of these event types can be stored yet;
 *   - no routes / handlers / KV get/put/list/delete / service bindings;
 *   - no event emission and no Billit/Peppol/OAuth implementation.
 * It only reserves stable vocabulary so a later patch can wire append() without
 * renaming. Nothing here changes runtime behavior.
 */
const FUTURE_DOCUMENT_AUDIT_EVENT_TYPES = Object.freeze({
  ISSUED: "document_issued",
  VOIDED: "document_voided",
  PROVIDER_EXPORTED: "document_provider_exported",
  PROVIDER_ACCEPTED: "document_provider_accepted",
  PROVIDER_REJECTED: "document_provider_rejected",
});

// Future document audit event payload shape (DOCUMENTATION ONLY). When wired,
// these events ride on the existing compliance_event_v1 envelope (tenant/company
// scoped, append-only); the fields below describe the event-specific `payload`:
//   {
//     tenant_id: string,
//     company_id: string,
//     document_id: string,                      // backend-allocated UUID
//     document_type: "credit_note" | "refund_proof",
//     document_number: string | null,           // credit_note accounting number
//     proof_reference: string | null,           // refund_proof non-accounting ref
//     document_status: "issued" | "voided" | "exported_to_provider"
//                      | "provider_accepted" | "provider_rejected",
//     source_booking_id: string,
//     source_parent_booking_id: string | null,  // roundtrip parent (context only)
//     source_leg_id: string | null,             // leg-first scope
//     source_leg_type: string | null,           // "outbound" | "return"
//     source_refund_id: string | null,
//     currency: string,                          // hard currency frozen at issue
//     totals: {                                  // frozen snapshot summary
//       total_incl_vat: number | null,
//       subtotal_ex_vat: number | null,
//       vat_amount: number | null,
//       vat_rate_percent: number | null,
//       credited_amount_incl_vat: number | null,
//       refunded_amount_incl_vat: number | null
//     },
//     content_hash: string,                      // SHA-256 of canonical snapshot
//     issue_timestamp: string,                   // backend UTC ISO timestamp
//     created_by_role: string | null,
//     provider_name: string | null,             // generic; no provider impl here
//     provider_document_id: string | null,
//     provider_export_status: string | null,
//     provider_rejected_reason: string | null
//   }

const SCHEMA_VERSION = "compliance_event_v1";
// CHIRON-RELEASE-PRESENTATION-REPAIR-1 C: append default is unknown / not yet
// evaluated — never a synthetic "external export not_configured" fact.
const SYNC_STATE = "unknown";
const RETRY_OUTBOX_STATE_DIRECT = "direct_append_v1";
const APPEND_PATH = "/compliance/events/append";
const RECENT_PATH = "/compliance/events/recent";
const ADMIN_RESET_PATH = "/admin/dev/reset-compliance-events";
const ADMIN_RESET_DRY_RUN_PATH = "/admin/dev/reset-compliance-events/dry-run";

// Chiron-1: backend-only dry-run blueprint preview. Lives alongside the
// existing compliance event store but uses a distinct KV prefix so the
// compliance_event_v1 history is never touched.
const CHIRON_DRYRUN_SCHEMA_VERSION = "chiron_dryrun_v1";
const CHIRON_DRYRUN_BUILD_PATH = "/admin/chiron/dryrun/build-from-event";
const CHIRON_DRYRUN_RECENT_PATH = "/admin/chiron/dryrun/recent";
const CHIRON_SCORE_SUMMARY_PATH = "/admin/chiron/score-summary";

// Chiron-4A: backend-only export dry-run / optional test-mode handover foundation.
const CHIRON_EXPORT_VERSION = "chiron_export_v1";
const CHIRON_EXPORT_SOURCE = "fluxidi_chiron";
const CHIRON_EXPORT_DRY_RUN_PATH = "/admin/chiron/export/dry-run";
const CHIRON_EXPORT_TEST_PATH = "/admin/chiron/export/test";
// Chiron-6B-3D: clean app-facing readiness endpoint.
const CHIRON_READINESS_PATH = "/admin/chiron/readiness";
// Phase 0/1: per-company Chiron connection status contract (Phase 1: KV persistence).
const CHIRON_CONFIG_STATUS_PATH = "/admin/chiron/config/status";
const CHIRON_CONFIG_TEST_CREDENTIALS_PATH = "/admin/chiron/config/test-credentials";
const CHIRON_CONFIG_TEST_CREDENTIALS_CLEAR_PATH =
  "/admin/chiron/config/test-credentials/clear";
const CHIRON_CONNECTION_TEST_PATH = "/admin/chiron/connection/test";
const CHIRON_TESTFLOW_RESET_PATH = "/admin/chiron/testflow/reset";
const CHIRON_TESTFLOW_SUBMIT_ONE_PATH = "/admin/chiron/testflow/submit-one";
// RELEASE-P0-OFFICIAL-CHIRON-OAUTH-SUBMIT-2026-07-31: operator-only
// resolution endpoints for the new `verification_required` sync_state. Both
// require admin auth AND full (tenant/company/idempotency_key) scoping. Used
// exclusively AFTER an operator verified the official Chiron portaal.
const CHIRON_TAXIRIT_VERIFY_CONFIRM_SYNCED_PATH =
  "/admin/chiron/taxirit/verification/confirm-synced";
const CHIRON_TAXIRIT_VERIFY_MARK_RETRYABLE_PATH =
  "/admin/chiron/taxirit/verification/mark-retryable";
// Official Chiron status tokens that a verification-resolution can target.
// Kept as a set so misspellings and unrelated tokens are rejected up front.
const CHIRON_ALLOWED_OFFICIAL_STATUSES_FOR_RESOLUTION = new Set([
  "reservatie",
  "vertrek",
  "aankomst",
]);
const CHIRON_CONNECTION_STATUS_SCHEMA = "chiron_connection_status_v1";
const CHIRON_CONNECTION_KV_SUFFIX = "chiron_connection:v1";
const CHIRON_INTERNAL_PROXY_MODE = "booking_worker_v1";
const CHIRON_CONNECTION_ALLOWED_ENVIRONMENTS = new Set(["test", "production"]);
const CHIRON_CONNECTION_ALLOWED_REGIONS = new Set(["flanders"]);
const CHIRON_CONNECTION_ALLOWED_STATUSES = new Set([
  "never_tested",
  "test_pending",
  "test_passed",
  "test_failed",
]);
const CHIRON_INTERNAL_TEST_ALLOWED_STATUSES = new Set(["passed"]);
const CHIRON_INTERNAL_TEST_STATUS_DOC_KEYS = [
  "internal_test_status",
  "internal_test_passed",
  "last_internal_test_at",
  "last_internal_test_environment",
  "last_internal_test_mock_only",
  "last_internal_test_external_call_performed",
  "last_internal_test_credential_decrypt_ok",
  "last_internal_test_credential_payload_valid",
  "last_internal_test_masked_identifier",
  "last_internal_test_fingerprint_short",
];
const CHIRON_CONFIG_FORBIDDEN_BODY_KEYS = new Set([
  "token",
  "apitoken",
  "api_token",
  "apikey",
  "api_key",
  "clientsecret",
  "client_secret",
  "password",
  "bearer",
  "credentials",
  "secret",
  "accesstoken",
  "access_token",
  "refreshtoken",
  "refresh_token",
]);
// Phase 2A: Chiron credentials encryption/storage foundation (helpers only; no routes).
const CHIRON_CREDENTIALS_SCHEMA_VERSION = "chiron_credentials_v1";
const CHIRON_CREDENTIALS_PAYLOAD_SCHEMA_VERSION = "chiron_credentials_payload_v1";
const CHIRON_CREDENTIALS_ALLOWED_AUTH_SCHEMES = new Set([
  "api_token",
  "oauth_client_credentials",
]);
const CHIRON_OAUTH_CLIENT_ID_MAX_LENGTH = 256;
const CHIRON_OAUTH_CLIENT_SECRET_MAX_LENGTH = 1024;
// Chiron Connect 4B: fixed allowlisted OAuth2 token endpoint per environment.
// We never read this from KV or from request bodies. Production endpoint is
// intentionally absent from this map until the production credentials route
// is introduced in a later phase.
const CHIRON_OAUTH_TOKEN_URL_BY_ENVIRONMENT = {
  test: "https://mow-acc.api.vlaanderen.be/oauth/token",
};
const CHIRON_OAUTH_EXCHANGE_TIMEOUT_MS = 10000;
const CHIRON_OAUTH_DEFAULT_TEST_MESSAGES_REQUIRED = 10;
// Chiron Connect 4C: acceptance testflow requirements. 5 rides x (departure +
// arrival) = 10 status messages, no error codes, correct order, unique rides.
const CHIRON_TESTFLOW_DEFAULT_RIDES_REQUIRED = 5;
const CHIRON_TESTFLOW_DEFAULT_DEPARTURE_REQUIRED = 5;
const CHIRON_TESTFLOW_DEFAULT_ARRIVAL_REQUIRED = 5;
const CHIRON_TESTFLOW_RITNUMMER_HISTORY_MAX = 20;
const CHIRON_TESTFLOW_ALLOWED_STATUSES = new Set([
  "not_started",
  "in_progress",
  "complete",
]);
const CHIRON_CREDENTIALS_ENCRYPTION_KEY_MIN_LENGTH = 32;
const CHIRON_TEST_CREDENTIALS_ALLOWED_TOP_LEVEL_KEYS = new Set([
  "tenant_id",
  "company_id",
  "auth_scheme",
  "credential_fields",
]);
const CHIRON_TEST_CREDENTIALS_CLEAR_ALLOWED_TOP_LEVEL_KEYS = new Set([
  "tenant_id",
  "company_id",
]);
const CHIRON_TEST_CREDENTIALS_FORBIDDEN_TOP_LEVEL_KEYS = new Set([
  "environment",
  "production",
  "productionenabled",
  "production_enabled",
  "officialsubmitenabled",
  "official_submit_enabled",
  "officialsubmissionperformedat",
  "official_submission_performed_at",
  "token",
  "apikey",
  "api_key",
  "secret",
  "password",
  "clientsecret",
  "client_secret",
]);
const CHIRON_CONNECTION_TEST_ALLOWED_TOP_LEVEL_KEYS = new Set([
  "tenant_id",
  "company_id",
  "environment",
]);
const CHIRON_READINESS_DEFAULT_LIMIT = 20;
const CHIRON_READINESS_DEFAULT_EVENT_TYPE = "ride_stop";
const CHIRON_EXPORT_STATUS_SCHEMA = "chiron_export_status_v1";
const CHIRON_EXPORT_MAX_SAMPLE_PAYLOADS = 3;
const CHIRON_EXPORT_LIST_SCAN_CAP = 10000;

// Chiron-6A-light: optional official ride payload draft (additive, opt-in).
const CHIRON_OFFICIAL_DRAFT_SCHEMA_VERSION = "chiron_official_draft_v1";

const CHIRON_OFFICIAL_RESERVATION_EVENT_TYPES = new Set([
  "booking_created",
  "booking_confirmed",
]);

const CHIRON_OFFICIAL_DEPARTURE_EVENT_TYPES = new Set([
  "ride_start",
  "trip_start",
  "planned_ride_start",
  "driver_departure",
]);

const CHIRON_OFFICIAL_ARRIVAL_EVENT_TYPES = new Set([
  "ride_stop",
  "trip_stop",
  "ride_completed",
  "planned_ride_stop",
]);

const CHIRON_OFFICIAL_RESERVATION_BOOKING_STATUSES = new Set([
  "pending",
  "created",
  "confirmed",
  "reserved",
  "planned",
  "booked",
  "scheduled",
  "accepted",
]);

const CHIRON_OFFICIAL_NON_RIDE_STATUS_EVENT_TYPES = new Set([
  "payment_update",
  "booking_credit_decision",
  "booking_mollie_refund",
  "correction_event",
  "sync_success",
  "sync_failed",
]);

const CHIRON_OFFICIAL_REQUIRED_RESERVATIE = [
  "broncreatiedatum",
  "ritnummer",
  "registratie",
  "naam",
  "status",
];

const CHIRON_OFFICIAL_REQUIRED_VERTREK = [
  ...CHIRON_OFFICIAL_REQUIRED_RESERVATIE,
  "kentekenplaat",
  "bestuurderspasnummer",
  "vertrektijdstip",
  "vertrekpunt_lengtegraad",
  "vertrekpunt_breedtegraad",
];

const CHIRON_OFFICIAL_REQUIRED_AANKOMST = [
  ...CHIRON_OFFICIAL_REQUIRED_VERTREK,
  "aankomsttijdstip",
  "aankomstpunt_lengtegraad",
  "aankomstpunt_breedtegraad",
  "afstand",
  "kostprijs",
];

const CHIRON_REGULATOR_READY_TYPES = new Set(["booking_status_update", "ride_stop"]);

const CHIRON_DRIVER_VEHICLE_BLOCKER_EVENT_TYPES = new Set([
  "ride_stop",
  "ride_start",
  "correction_event",
]);

const CHIRON_LOG_ONLY_TYPES = new Set([
  "payment_update",
  "booking_credit_decision",
  "booking_mollie_refund",
  "correction_event",
  "sync_success",
  "sync_failed",
]);

function jsonResponse(payload, status = 200, origin = "*") {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "access-control-allow-origin": origin || "*",
      "access-control-allow-methods": "GET, POST, OPTIONS",
      "access-control-allow-headers": "content-type, authorization, x-admin-token",
      "access-control-max-age": "86400",
    },
  });
}

function nowIso() {
  return new Date().toISOString();
}

function cleanText(value, maxLen = 256) {
  const text = String(value ?? "").trim();
  if (!text) return "";
  return text.slice(0, maxLen);
}

function safeSegment(value, fallback = "unknown") {
  const normalized = cleanText(value, 128).toLowerCase().replace(/[^a-z0-9._-]/g, "_");
  return normalized || fallback;
}

function parseAuthToken(request) {
  const header = request.headers.get("authorization") || "";
  const bearerPrefix = "Bearer ";
  if (header.startsWith(bearerPrefix)) {
    return header.slice(bearerPrefix.length).trim();
  }
  return cleanText(request.headers.get("x-admin-token"), 512);
}

function ensureAuthorized(request, env) {
  const requiredToken = cleanText(
    env?.COMPLIANCE_ADMIN_TOKEN || env?.ADMIN_TOKEN,
    512,
  );
  if (!requiredToken) {
    return jsonResponse(
      { ok: false, error: "compliance_auth_not_configured" },
      503,
    );
  }
  const provided = parseAuthToken(request);
  if (!provided || provided !== requiredToken) {
    return jsonResponse({ ok: false, error: "Unauthorized" }, 401);
  }
  return null;
}

function _requiredComplianceAuthToken(env) {
  return cleanText(env?.COMPLIANCE_ADMIN_TOKEN || env?.ADMIN_TOKEN, 512);
}

function _parseInternalProxyAuth(request, env, scope) {
  const proxyMode = cleanText(request.headers.get("x-fluxidi-internal-proxy"), 64);
  if (proxyMode !== CHIRON_INTERNAL_PROXY_MODE) return null;

  const requiredToken = _requiredComplianceAuthToken(env);
  if (!requiredToken) {
    return { error: "compliance_auth_not_configured", status: 503 };
  }

  const proxyToken = cleanText(request.headers.get("x-fluxidi-proxy-token"), 512);
  if (!proxyToken || proxyToken !== requiredToken) {
    return { error: "Unauthorized", status: 401 };
  }

  const proxyTenant = cleanText(request.headers.get("x-fluxidi-proxy-tenant-id"), 128);
  const proxyCompany = cleanText(request.headers.get("x-fluxidi-proxy-company-id"), 128);
  if (!proxyTenant || !proxyCompany) {
    return { error: "missing_proxy_scope", status: 400 };
  }
  if (proxyTenant !== scope.tenantId || proxyCompany !== scope.companyId) {
    return { error: "proxy_scope_mismatch", status: 403 };
  }

  return { ok: true, auth_mode: "internal_proxy" };
}

function ensureAuthorizedOrInternalProxy(request, env, scope) {
  const adminError = ensureAuthorized(request, env);
  if (!adminError) return null;

  const proxy = _parseInternalProxyAuth(request, env, scope);
  if (proxy?.ok) return null;
  if (proxy?.error) {
    return jsonResponse({ ok: false, error: proxy.error }, proxy.status);
  }
  return adminError;
}

function allowDevResetEndpoints(env) {
  return String(env?.ALLOW_DEV_RESET_ENDPOINTS || "").trim().toLowerCase() === "true";
}

function requireJsonRequest(request) {
  const contentType = (request.headers.get("content-type") || "").toLowerCase();
  return contentType.includes("application/json");
}

async function readJsonBody(request) {
  try {
    return await request.json();
  } catch (_) {
    return null;
  }
}

function normalizeEventEnvelope(input) {
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    return { error: "Invalid JSON body. Expected an object." };
  }

  const eventType = cleanText(input.event_type, 64).toLowerCase();
  const tenantId = cleanText(input.tenant_id, 128);
  const companyId = cleanText(input.company_id, 128);

  if (!eventType) return { error: "Missing required field: event_type" };
  if (!ALLOWED_EVENT_TYPES.has(eventType)) {
    return { error: "Invalid event_type" };
  }
  if (!tenantId) return { error: "Missing required field: tenant_id" };
  if (!companyId) return { error: "Missing required field: company_id" };

  const recordedAtUtc = nowIso();
  const eventId = cleanText(input.event_id, 200) || crypto.randomUUID();

  const baseTimestamps =
    input.timestamps && typeof input.timestamps === "object" && !Array.isArray(input.timestamps)
      ? { ...input.timestamps }
      : {};

  const normalized = {
    ...input,
    event_id: eventId,
    event_type: eventType,
    schema_version: SCHEMA_VERSION,
    tenant_id: tenantId,
    company_id: companyId,
    booking_id: cleanText(input.booking_id, 128) || null,
    trip_id: cleanText(input.trip_id, 128) || null,
    session_id: cleanText(input.session_id, 128) || null,
    receipt_reference: cleanText(input.receipt_reference, 128) || null,
    ride_type: cleanText(input.ride_type, 64) || "unknown",
    lifecycle_status: cleanText(input.lifecycle_status, 64) || "unknown",
    timestamps: {
      ...baseTimestamps,
      recorded_at_utc: recordedAtUtc,
    },
    driver:
      input.driver && typeof input.driver === "object" && !Array.isArray(input.driver)
        ? input.driver
        : {},
    vehicle:
      input.vehicle && typeof input.vehicle === "object" && !Array.isArray(input.vehicle)
        ? input.vehicle
        : {},
    locations:
      input.locations && typeof input.locations === "object" && !Array.isArray(input.locations)
        ? input.locations
        : {},
    fare:
      input.fare && typeof input.fare === "object" && !Array.isArray(input.fare)
        ? input.fare
        : {},
    payment:
      input.payment && typeof input.payment === "object" && !Array.isArray(input.payment)
        ? input.payment
        : {},
    provenance:
      input.provenance && typeof input.provenance === "object" && !Array.isArray(input.provenance)
        ? input.provenance
        : {},
    sync_state: SYNC_STATE,
    retry_outbox_state: RETRY_OUTBOX_STATE_DIRECT,
    retryOutboxState: RETRY_OUTBOX_STATE_DIRECT,
    created_at_utc: recordedAtUtc,
  };

  return { value: normalized };
}

function buildEventStorageKey(event) {
  const when = event.created_at_utc || nowIso();
  const date = new Date(when);
  const year = String(date.getUTCFullYear()).padStart(4, "0");
  const month = String(date.getUTCMonth() + 1).padStart(2, "0");
  const day = String(date.getUTCDate()).padStart(2, "0");
  const ms = String(date.getTime()).padStart(13, "0");

  return [
    "compliance_event_v1",
    "tenant",
    safeSegment(event.tenant_id),
    "company",
    safeSegment(event.company_id),
    year,
    month,
    day,
    `${ms}_${safeSegment(event.event_id, "evt")}`,
  ].join("/");
}

// Deterministic date-indexed key derived from an *arbitrary* ISO timestamp so
// recovery of a missing date entry can rebuild the exact key that would have
// been written on the first successful append.
function buildDateIndexKeyForTimestamp(event, isoTimestamp) {
  const when = cleanText(isoTimestamp, 64) || event.created_at_utc || nowIso();
  const date = new Date(when);
  const year = String(date.getUTCFullYear()).padStart(4, "0");
  const month = String(date.getUTCMonth() + 1).padStart(2, "0");
  const day = String(date.getUTCDate()).padStart(2, "0");
  const ms = String(date.getTime()).padStart(13, "0");
  return [
    "compliance_event_v1",
    "tenant",
    safeSegment(event.tenant_id),
    "company",
    safeSegment(event.company_id),
    year,
    month,
    day,
    `${ms}_${safeSegment(event.event_id, "evt")}`,
  ].join("/");
}

// RELEASE-P0-CLOSE-PLANNED-CHIRON-DURABILITY-GAPS-2026-07-31: deterministic
// canonical event key keyed only by (tenant, company, event_id). This is the
// SOURCE OF TRUTH for idempotency — one KV slot per (tenant, company,
// event_id). Every retry (immediate or startup-recovery) collides on the
// same slot; last-write-wins on identical content; a body is never split
// across two rows. Deliberately uses a distinct top-level namespace
// (`compliance_event_canonical_v1`) so it is not visible to the existing
// date-partitioned recent-listing scan (that scan owns chronological reads;
// this key owns idempotency). See handleAppend for the write/recovery order.
function buildComplianceCanonicalEventKey(event) {
  return [
    "compliance_event_canonical_v1",
    "tenant",
    safeSegment(event.tenant_id),
    "company",
    safeSegment(event.company_id),
    "eid",
    safeSegment(event.event_id, "evt"),
  ].join("/");
}

async function handleAppend(request, env, origin) {
  const authError = ensureAuthorized(request, env);
  if (authError) return authError;

  if (!requireJsonRequest(request)) {
    return jsonResponse(
      { ok: false, error: "Content-Type must be application/json" },
      400,
      origin,
    );
  }

  const payload = await readJsonBody(request);
  if (payload === null) {
    return jsonResponse({ ok: false, error: "Invalid JSON body" }, 400, origin);
  }

  // Capture the client-supplied event_id BEFORE normalization: idempotent
  // storage is only guaranteed when the producer supplied a stable event_id.
  // An empty client id still gets a random UUID from normalizeEventEnvelope
  // (backward-compatible) but takes the legacy single-write path.
  const clientSuppliedEventId =
    payload && typeof payload === "object" && !Array.isArray(payload)
      ? cleanText(payload.event_id, 200)
      : "";

  const normalized = normalizeEventEnvelope(payload);
  if (normalized.error) {
    return jsonResponse({ ok: false, error: normalized.error }, 400, origin);
  }

  if (!env || !env.COMPLIANCE_KV || typeof env.COMPLIANCE_KV.put !== "function") {
    return jsonResponse(
      {
        ok: false,
        error: "Compliance storage is not configured (missing COMPLIANCE_KV binding).",
      },
      500,
      origin,
    );
  }

  const event = normalized.value;

  if (clientSuppliedEventId) {
    // RELEASE-P0-CLOSE-PLANNED-CHIRON-DURABILITY-GAPS-2026-07-31: two-phase
    // recovery-safe idempotent write.
    //
    //   Phase 1: CANONICAL body at the deterministic (tenant, company,
    //            event_id) key. This slot IS the idempotency record; a
    //            dedup response is only valid when this slot exists.
    //   Phase 2: DATE-INDEXED body at the chronological read key. Written
    //            AFTER canonical so a crash between phases leaves canonical
    //            present but date entry missing.
    //
    // Every append re-verifies both phases. When canonical exists but the
    // date entry is missing (partial write from a prior request), the date
    // entry is rebuilt from the canonical body using the canonical's stored
    // `created_at_utc`. This eliminates the pre-fix data-loss window where
    // a pointer-hit could falsely return `deduplicated:true` while the
    // canonical body was still missing.
    const canonicalKey = buildComplianceCanonicalEventKey(event);
    let canonicalExisting = null;
    if (typeof env.COMPLIANCE_KV.get === "function") {
      try {
        canonicalExisting = await env.COMPLIANCE_KV.get(canonicalKey, {
          type: "json",
        });
      } catch (_) {
        // Read failure → fall through to write. Safe: canonical write below is
        // idempotent (deterministic key + identical content).
        canonicalExisting = null;
      }
    }
    if (
      canonicalExisting &&
      typeof canonicalExisting === "object" &&
      !Array.isArray(canonicalExisting)
    ) {
      // Canonical present → the event is authoritatively stored. Verify the
      // date entry too and recover it if a prior request crashed mid-way.
      const storedAt =
        cleanText(canonicalExisting.created_at_utc, 64) || event.created_at_utc;
      const dateKey = buildDateIndexKeyForTimestamp(event, storedAt);
      let dateExisting = null;
      try {
        dateExisting = await env.COMPLIANCE_KV.get(dateKey);
      } catch (_) {
        dateExisting = null;
      }
      let recovered = false;
      if (!dateExisting) {
        // RELEASE-P0-FIX-CHIRON-RECOVERY-INDEX-FALSE-ACK-2026-07-31:
        //
        // Recovery MUST NOT swallow date-index write failures. Under the old
        // (best-effort) behavior a KV.put throw here still returned
        // {ok:true, deduplicated:true, recovered:false} with HTTP 200. The
        // tracking worker derived APPLIED from that ok:true — but the
        // dashboard could never see the event because the date-index entry
        // was still missing, and no retry ever followed.
        //
        // New behavior: propagate the write error. The top-level fetch
        // handler translates any thrown error to HTTP 500 + {ok:false,
        // error:"Internal error"}, so tracking correctly marks the event
        // PENDING and the periodic reconciler will retry until the
        // date-index write succeeds. When it does, this same branch flips
        // `recovered: true` and only THEN returns HTTP 200.
        await env.COMPLIANCE_KV.put(
          dateKey,
          JSON.stringify(canonicalExisting),
        );
        recovered = true;
      }
      console.log(
        `[COMPLIANCE_STORE][${cleanText(event.event_type, 64) || "unknown"}] deduplicated ok=true recovered=${recovered}`,
      );
      return jsonResponse(
        {
          ok: true,
          event_id:
            cleanText(canonicalExisting.event_id, 200) || event.event_id,
          stored_at: storedAt,
          deduplicated: true,
          recovered,
        },
        200,
        origin,
      );
    }

    // Canonical missing → write canonical FIRST, then date index. Both use
    // the same body; a concurrent second writer that also observed
    // canonical-missing will PUT identical content and lose the race on
    // date_index at read time only (see handleRecent read-time dedup by
    // event_id, which enforces exactly-one at the dashboard level).
    await env.COMPLIANCE_KV.put(canonicalKey, JSON.stringify(event));
    const dateKey = buildDateIndexKeyForTimestamp(event, event.created_at_utc);
    await env.COMPLIANCE_KV.put(dateKey, JSON.stringify(event));
    console.log(
      `[COMPLIANCE_STORE][${cleanText(event.event_type, 64) || "unknown"}] ok=true`,
    );

    return jsonResponse(
      {
        ok: true,
        event_id: event.event_id,
        stored_at: event.created_at_utc,
        deduplicated: false,
      },
      200,
      origin,
    );
  }

  // Legacy path (no client-supplied event_id): single date-indexed write.
  const key = buildEventStorageKey(event);
  await env.COMPLIANCE_KV.put(key, JSON.stringify(event));
  console.log(
    `[COMPLIANCE_STORE][${cleanText(event.event_type, 64) || "unknown"}] ok=true`,
  );

  return jsonResponse(
    {
      ok: true,
      event_id: event.event_id,
      stored_at: event.created_at_utc,
    },
    200,
    origin,
  );
}

function parseRecentLimit(url) {
  const raw = cleanText(url.searchParams.get("limit"), 16);
  if (!raw) return { value: 20 };
  const parsed = Number(raw);
  if (!Number.isFinite(parsed) || !Number.isInteger(parsed)) {
    return { error: "Invalid query parameter: limit must be an integer." };
  }
  return { value: Math.min(100, Math.max(1, parsed)) };
}

function parseChironScoreSummaryLimit(url) {
  const raw = cleanText(url.searchParams.get("limit"), 16);
  if (!raw) return { value: 50 };
  const parsed = Number(raw);
  if (!Number.isFinite(parsed) || !Number.isInteger(parsed)) {
    return { error: "Invalid query parameter: limit must be an integer." };
  }
  return { value: Math.min(100, Math.max(1, parsed)) };
}

function parseChironNewestEventsLimit(url) {
  const raw = cleanText(url.searchParams.get("newest_events_limit"), 16);
  if (!raw) return { value: 10 };
  const parsed = Number(raw);
  if (!Number.isFinite(parsed) || !Number.isInteger(parsed)) {
    return { error: "Invalid query parameter: newest_events_limit must be an integer." };
  }
  return { value: Math.min(25, Math.max(0, parsed)) };
}

function parseChironExportLimit(raw) {
  const text = cleanText(raw, 16);
  if (!text) return { value: 10 };
  const parsed = Number(text);
  if (!Number.isFinite(parsed) || !Number.isInteger(parsed)) {
    return { error: "Invalid limit: must be an integer." };
  }
  return { value: Math.min(50, Math.max(1, parsed)) };
}

function parseOptionalIsoBodyMs(body, key) {
  const raw = cleanText(body?.[key], 64);
  if (!raw) return { value: null, raw: null };
  const ms = Date.parse(raw);
  if (!Number.isFinite(ms)) {
    return { error: `Invalid body field: ${key}` };
  }
  return { value: ms, raw };
}

function parseIncludeOfficialDraftFlag(body, url) {
  const queryRaw =
    url?.searchParams?.get("include_official_draft") ??
    url?.searchParams?.get("include_chiron_official_draft");
  if (String(queryRaw ?? "").trim().toLowerCase() === "true") return true;
  if (body?.include_official_draft === true || body?.include_chiron_official_draft === true) {
    return true;
  }
  return false;
}

// Chiron-6B-3C: optional readiness-report flag. Accepts body or query string,
// short and long aliases.
function parseIncludeReadinessReportFlag(body, url) {
  const queryRaw =
    url?.searchParams?.get("include_readiness_report") ??
    url?.searchParams?.get("include_chiron_readiness_report");
  if (String(queryRaw ?? "").trim().toLowerCase() === "true") return true;
  if (
    body?.include_readiness_report === true ||
    body?.include_chiron_readiness_report === true
  ) {
    return true;
  }
  return false;
}

function parseChironExportScopeFromBody(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return { error: "Invalid JSON body" };
  }
  const tenantId = cleanText(body.tenant_id, 128);
  const companyId = cleanText(body.company_id, 128);
  if (!tenantId || !companyId) {
    return { error: "missing_scope" };
  }
  const tenantSegment = safeSegment(tenantId, "");
  const companySegment = safeSegment(companyId, "");
  if (!tenantSegment || !companySegment) {
    return { error: "missing_scope" };
  }
  return { tenantId, companyId, tenantSegment, companySegment, body };
}

function parseOptionalIsoQueryMs(url, key) {
  const raw = cleanText(url.searchParams.get(key), 64);
  if (!raw) return { value: null, raw: null };
  const ms = Date.parse(raw);
  if (!Number.isFinite(ms)) {
    return { error: `Invalid query parameter: ${key}` };
  }
  return { value: ms, raw };
}

function parseRequiredQuerySegment(url, key) {
  const raw = cleanText(url.searchParams.get(key), 128);
  if (!raw) {
    return { error: `Missing required query parameter: ${key}` };
  }
  const segment = safeSegment(raw, "");
  if (!segment) {
    return { error: `Invalid query parameter: ${key}` };
  }
  return { value: segment };
}

function parseRefundAmountCents(value) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return null;
  return Math.max(0, Math.round(parsed));
}

function projectRefundAuditFields(event) {
  const payment =
    event?.payment && typeof event.payment === "object" && !Array.isArray(event.payment)
      ? event.payment
      : {};
  const timestamps =
    event?.timestamps && typeof event.timestamps === "object" && !Array.isArray(event.timestamps)
      ? event.timestamps
      : {};
  const refundId =
    cleanText(event?.refund_id, 120) ||
    cleanText(event?.refundId, 120) ||
    cleanText(payment?.refund_id, 120) ||
    cleanText(payment?.refundId, 120) ||
    cleanText(payment?.mollie_refund_id, 120) ||
    cleanText(payment?.mollieRefundId, 120) ||
    null;
  const refundStatus =
    cleanText(event?.refund_status, 64) ||
    cleanText(event?.refundStatus, 64) ||
    cleanText(payment?.refund_status, 64) ||
    cleanText(payment?.refundStatus, 64) ||
    null;
  const refundProvider =
    cleanText(event?.refund_provider, 64) ||
    cleanText(event?.refundProvider, 64) ||
    cleanText(payment?.refund_provider, 64) ||
    cleanText(payment?.refundProvider, 64) ||
    null;
  const refundAmountCents =
    parseRefundAmountCents(event?.refund_amount_cents ?? event?.refundAmountCents) ??
    parseRefundAmountCents(payment?.refund_amount_cents ?? payment?.refundAmountCents);
  const creditDecision =
    cleanText(event?.credit_decision, 64) ||
    cleanText(event?.creditDecision, 64) ||
    cleanText(payment?.credit_decision, 64) ||
    cleanText(payment?.creditDecision, 64) ||
    null;
  const refundedAt =
    cleanText(event?.refunded_at, 64) ||
    cleanText(event?.refundedAt, 64) ||
    cleanText(timestamps?.refunded_at_utc, 64) ||
    cleanText(timestamps?.event_at_utc, 64) ||
    null;
  return {
    refund_status: refundStatus,
    refundStatus,
    refund_provider: refundProvider,
    refundProvider,
    refund_amount_cents: refundAmountCents,
    refundAmountCents: refundAmountCents,
    refund_id: refundId,
    refundId,
    credit_decision: creditDecision,
    creditDecision,
    refunded_at: refundedAt,
    refundedAt,
  };
}

function projectRecentEvent(key, parsedEvent) {
  const event = parsedEvent && typeof parsedEvent === "object" && !Array.isArray(parsedEvent)
    ? parsedEvent
    : {};
  const refundAudit = projectRefundAuditFields(event);
  // Roundtrip operational-leg projection: the booking worker and tracking
  // worker already stamp leg_id / leg_type / parent_booking_id / parent_status
  // and friends on the persisted event (see booking_status_update assignment
  // context and tracking ride_stop emitters). The recent-events response
  // dropped those scalars on the floor, which made Backendmeldingen unable to
  // tell a leg-scoped ride_stop apart from a full booking completion. Surface
  // the fields at the top of the response object so the Flutter dashboard can
  // render ritdeel / kostprijs / parent status without a second fetch.
  const legMetadata = projectComplianceLegMetadata(event);
  if (legMetadata.has_leg_metadata) {
    const legType =
      legMetadata.leg_type ||
      legMetadata.legType ||
      cleanText(event?.leg_type ?? event?.legType, 64) ||
      "-";
    const legId =
      legMetadata.leg_id ||
      legMetadata.legId ||
      cleanText(event?.leg_id ?? event?.legId, 128) ||
      "-";
    const parentStatus =
      legMetadata.parent_status ||
      legMetadata.parentStatus ||
      cleanText(event?.parent_status ?? event?.parentStatus, 64) ||
      "-";
    const legStatus =
      legMetadata.leg_status ||
      legMetadata.legStatus ||
      cleanText(event?.leg_status ?? event?.legStatus, 64) ||
      "-";
    console.log(
      `[COMPLIANCE_EVENT][LEG_METADATA] event_type=${cleanText(event.event_type, 64) || "-"} booking=${cleanText(event.booking_id, 128) || "-"} leg=${legId} leg_type=${legType} leg_status=${legStatus} parent_status=${parentStatus} source=projectRecentEvent`,
    );
  }
  return {
    key,
    event_id: cleanText(event.event_id, 200) || null,
    event_type: cleanText(event.event_type, 64) || null,
    ride_type: cleanText(event.ride_type, 64) || null,
    lifecycle_status: cleanText(event.lifecycle_status, 64) || null,
    status: cleanText(event.status, 64) || null,
    booking_status: cleanText(event.booking_status, 64) || null,
    ride_status: cleanText(event.ride_status, 64) || null,
    previous_status: cleanText(event.previous_status, 64) || null,
    actor_role: cleanText(event.actor_role, 64) || null,
    source: cleanText(event.source, 64) || null,
    booking_id: cleanText(event.booking_id, 128) || null,
    public_booking_reference: cleanText(event.public_booking_reference, 128) || null,
    publicBookingReference: cleanText(event.publicBookingReference, 128) || null,
    booking_reference: cleanText(event.booking_reference, 128) || null,
    bookingReference: cleanText(event.bookingReference, 128) || null,
    public_reference: cleanText(event.public_reference, 128) || null,
    publicReference: cleanText(event.publicReference, 128) || null,
    receipt_reference: cleanText(event.receipt_reference, 128) || null,
    receiptReference: cleanText(event.receiptReference, 128) || null,
    trip_id: cleanText(event.trip_id, 128) || null,
    sync_state: cleanText(event.sync_state, 64) || null,
    retry_outbox_state:
      cleanText(event.retry_outbox_state ?? event.retryOutboxState, 64) || null,
    created_at_utc: cleanText(event.created_at_utc, 64) || null,
    timestamps:
      event.timestamps && typeof event.timestamps === "object" && !Array.isArray(event.timestamps)
        ? event.timestamps
        : {},
    payment:
      event.payment && typeof event.payment === "object" && !Array.isArray(event.payment)
        ? event.payment
        : {},
    fare:
      event.fare && typeof event.fare === "object" && !Array.isArray(event.fare)
        ? event.fare
        : {},
    provenance:
      event.provenance && typeof event.provenance === "object" && !Array.isArray(event.provenance)
        ? event.provenance
        : {},
    ...legMetadata.projection,
    ...refundAudit,
  };
}

// Roundtrip operational-leg projection: extract leg / parent context from a
// persisted compliance event so the recent-events response carries the same
// fields the booking worker stamped at append time. Returns a small projection
// object plus a presence flag for diagnostics. This MUST NOT alter Chiron
// submission semantics: it only surfaces existing stored data to the client.
function projectComplianceLegMetadata(event) {
  if (!event || typeof event !== "object" || Array.isArray(event)) {
    return { has_leg_metadata: false, projection: {} };
  }
  const provenance =
    event.provenance && typeof event.provenance === "object" && !Array.isArray(event.provenance)
      ? event.provenance
      : {};
  const assignment =
    event.assignment && typeof event.assignment === "object" && !Array.isArray(event.assignment)
      ? event.assignment
      : null;
  const references =
    event.references && typeof event.references === "object" && !Array.isArray(event.references)
      ? event.references
      : null;
  const fare =
    event.fare && typeof event.fare === "object" && !Array.isArray(event.fare)
      ? event.fare
      : {};
  const timestamps =
    event.timestamps && typeof event.timestamps === "object" && !Array.isArray(event.timestamps)
      ? event.timestamps
      : {};

  const pickText = (paths, maxLength) => {
    for (const path of paths) {
      const raw = pathValue(event, path);
      const text = cleanText(raw, maxLength);
      if (text) return text;
    }
    return null;
  };

  const pickNumber = (paths) => {
    for (const path of paths) {
      const raw = pathValue(event, path);
      if (raw === null || raw === undefined || raw === "") continue;
      const num = typeof raw === "number" ? raw : Number(raw);
      if (Number.isFinite(num)) return num;
    }
    return null;
  };

  // Chiron Fase 2A: positive-finite picker for leg-scoped monetary fallbacks.
  // Used so that fare.total_amount / fare_total_amount only contributes to
  // leg_price_incl_vat when it is an actual amount (> 0), never zero or
  // negative, and never NaN.
  const pickPositiveNumber = (paths) => {
    const value = pickNumber(paths);
    if (value === null || !Number.isFinite(value) || value <= 0) return null;
    return value;
  };

  const legId = pickText(
    [
      ["leg_id"],
      ["legId"],
      ["booking", "leg_id"],
      ["booking", "legId"],
      ["assignment", "leg_id"],
      ["assignment", "legId"],
    ],
    128,
  );
  const legTypeRaw = pickText(
    [
      ["leg_type"],
      ["legType"],
      ["booking", "leg_type"],
      ["booking", "legType"],
      ["assignment", "leg_type"],
      ["assignment", "legType"],
    ],
    64,
  );
  const legType = legTypeRaw ? legTypeRaw.toLowerCase() : null;
  // Chiron Fase 2A: an event is "leg-scoped" once we have a leg_id or
  // leg_type stamped on it. Only leg-scoped events are allowed to fall
  // back to lifecycle/ride/status or fare.total_amount when filling in
  // leg_status / leg_price_incl_vat. Parent-scoped status updates keep
  // their own status field exclusively to avoid status/amount poisoning
  // of sibling legs in the Backendmeldingen UI.
  const isLegScoped = Boolean(legId) || Boolean(legType);
  const parentBookingId = pickText(
    [
      ["parent_booking_id"],
      ["parentBookingId"],
      ["booking", "parent_booking_id"],
      ["booking", "parentBookingId"],
    ],
    128,
  );
  const parentStatus = pickText(
    [
      ["parent_status"],
      ["parentStatus"],
      ["booking", "parent_status"],
      ["booking", "parentStatus"],
    ],
    64,
  );
  let legStatus = pickText(
    [
      ["leg_status"],
      ["legStatus"],
      ["booking", "leg_status"],
      ["booking", "legStatus"],
    ],
    64,
  );
  // Leg-scoped fallback: many ride_stop / lifecycle events do not carry an
  // explicit leg_status but still describe a single leg's transition (the
  // status is on lifecycle_status / ride_status / status). Only fall back
  // when the event is itself leg-scoped, never on parent booking updates.
  if (!legStatus && isLegScoped) {
    legStatus = pickText(
      [
        ["lifecycle_status"],
        ["lifecycleStatus"],
        ["ride_status"],
        ["rideStatus"],
        ["status"],
      ],
      64,
    );
  }
  let legPriceInclVat = pickNumber([
    ["leg_price_incl_vat"],
    ["legPriceInclVat"],
    ["booking", "leg_price_incl_vat"],
    ["booking", "legPriceInclVat"],
  ]);
  // Leg-scoped fallback: events stamped by the booking/tracking worker for a
  // single operational leg may emit the amount only via fare.total_amount /
  // fare_total_amount (e.g. ride_stop, lifecycle_progress). For these we
  // promote that amount into leg_price_incl_vat so the Chiron UI shows the
  // correct leg total instead of leaving the field empty. We never do this
  // for parent-scoped events, otherwise a parent booking_status_update could
  // project the full roundtrip total as a leg amount. Only positive finite
  // amounts are allowed via the fallback path.
  if (!Number.isFinite(legPriceInclVat) && isLegScoped) {
    const fareFallback = pickPositiveNumber([
      ["fare_total_amount"],
      ["fareTotalAmount"],
      ["fare", "total_amount"],
      ["fare", "totalAmount"],
    ]);
    if (fareFallback !== null) legPriceInclVat = fareFallback;
  }
  const parentPriceInclVat = pickNumber([
    ["parent_price_incl_vat"],
    ["parentPriceInclVat"],
    ["booking", "parent_price_incl_vat"],
    ["booking", "parentPriceInclVat"],
  ]);
  const waitMin = pickNumber([
    ["wait_min"],
    ["waitMin"],
    ["booking", "wait_min"],
    ["booking", "waitMin"],
  ]);
  const distanceKm = pickNumber([
    ["distance_km"],
    ["distanceKm"],
    ["fare", "distance_km"],
    ["fare", "distanceKm"],
  ]);
  // Chiron Fase 2A: additive duration projection so leg events can render
  // route duration alongside distance_km. Read from top-level, fare.* and
  // route.* without overwriting any existing field.
  const durationMin = pickNumber([
    ["duration_min"],
    ["durationMin"],
    ["fare", "duration_min"],
    ["fare", "durationMin"],
    ["route", "duration_min"],
    ["route", "durationMin"],
  ]);
  const roundtripDispatchMode = pickText(
    [
      ["roundtrip_dispatch_mode"],
      ["roundtripDispatchMode"],
      ["booking", "roundtrip_dispatch_mode"],
      ["booking", "roundtripDispatchMode"],
    ],
    32,
  );
  const parentAssignmentMode = pickText(
    [["parent_assignment_mode"], ["parentAssignmentMode"]],
    32,
  );
  const planningReferenceTop = cleanText(event.planning_reference ?? event.planningReference, 128);
  const planningReference =
    planningReferenceTop ||
    cleanText(references?.planning_reference ?? references?.planningReference, 128) ||
    cleanText(provenance.planning_reference ?? provenance.planningReference, 128) ||
    null;
  const startedAtUtc = cleanText(
    timestamps.started_at_utc ?? event.started_at_utc ?? event.startedAtUtc,
    64,
  );
  const stoppedAtUtc = cleanText(
    timestamps.stopped_at_utc ?? event.stopped_at_utc ?? event.stoppedAtUtc,
    64,
  );

  const projection = {};
  if (legId) {
    projection.leg_id = legId;
    projection.legId = legId;
  }
  if (legType) {
    projection.leg_type = legType;
    projection.legType = legType;
  }
  if (parentBookingId) {
    projection.parent_booking_id = parentBookingId;
    projection.parentBookingId = parentBookingId;
  }
  if (parentStatus) {
    projection.parent_status = parentStatus.toLowerCase();
    projection.parentStatus = parentStatus.toLowerCase();
  }
  if (legStatus) {
    projection.leg_status = legStatus.toLowerCase();
    projection.legStatus = legStatus.toLowerCase();
  }
  if (Number.isFinite(legPriceInclVat)) {
    projection.leg_price_incl_vat = legPriceInclVat;
    projection.legPriceInclVat = legPriceInclVat;
  }
  if (Number.isFinite(parentPriceInclVat)) {
    projection.parent_price_incl_vat = parentPriceInclVat;
    projection.parentPriceInclVat = parentPriceInclVat;
  }
  if (Number.isFinite(waitMin)) {
    projection.wait_min = waitMin;
    projection.waitMin = waitMin;
  }
  if (Number.isFinite(distanceKm)) {
    projection.distance_km = distanceKm;
    projection.distanceKm = distanceKm;
  }
  if (Number.isFinite(durationMin)) {
    projection.duration_min = durationMin;
    projection.durationMin = durationMin;
  }
  if (roundtripDispatchMode) {
    projection.roundtrip_dispatch_mode = roundtripDispatchMode;
    projection.roundtripDispatchMode = roundtripDispatchMode;
  }
  if (parentAssignmentMode) {
    projection.parent_assignment_mode = parentAssignmentMode;
    projection.parentAssignmentMode = parentAssignmentMode;
  }
  if (planningReference) {
    projection.planning_reference = planningReference;
    projection.planningReference = planningReference;
  }
  if (startedAtUtc) {
    projection.started_at_utc = startedAtUtc;
    projection.startedAtUtc = startedAtUtc;
  }
  if (stoppedAtUtc) {
    projection.stopped_at_utc = stoppedAtUtc;
    projection.stoppedAtUtc = stoppedAtUtc;
  }
  if (assignment) {
    projection.assignment = assignment;
  }
  if (references) {
    projection.references = references;
  }
  // Forward stored fare scalars (total_amount, currency, …) — keep a flat
  // copy so the dashboard / score-summary can render the leg fare amount
  // without descending into the fare map again. Chiron Fase 2A also reads
  // top-level fare_total_amount / fareTotalAmount so older events that
  // stamped the amount outside the fare sub-object are still picked up.
  const fareTotal = pickNumber([
    ["fare_total_amount"],
    ["fareTotalAmount"],
    ["fare", "total_amount"],
    ["fare", "totalAmount"],
  ]);
  if (Number.isFinite(fareTotal)) {
    projection.fare_total_amount = fareTotal;
    projection.fareTotalAmount = fareTotal;
  }

  return {
    has_leg_metadata:
      Boolean(legId) ||
      Boolean(legType) ||
      Boolean(parentBookingId) ||
      Boolean(parentStatus) ||
      Boolean(legStatus),
    projection,
    leg_id: legId,
    legId,
    leg_type: legType,
    legType,
    parent_status: projection.parent_status,
    parentStatus: projection.parentStatus,
    leg_status: projection.leg_status,
    legStatus: projection.legStatus,
  };
}

function pathValue(root, path) {
  if (!root || typeof root !== "object" || Array.isArray(path) === false) return undefined;
  let current = root;
  for (const segment of path) {
    if (current === null || current === undefined) return undefined;
    if (typeof current !== "object" || Array.isArray(current)) return undefined;
    current = current[segment];
  }
  return current;
}

// COMPANY-DATA-LATENCY-P0-REPAIR-1 (Part A).
//
// Bounded-parallel fan-out for the per-key `COMPLIANCE_KV.get` phase of
// `handleRecent`. The pre-repair worker awaited 100 KV reads sequentially,
// which pushed the observed 100-event scope past the Flutter 10 s client
// timeout. This limit keeps the fan-out well under Cloudflare's per-worker
// subrequest ceiling (1000) and matches the number the tracking worker's
// `handleTripsHistory` uses so both hot paths behave consistently.
//
// Ordering: the array-of-keys is preserved verbatim (input-order-preserving
// parallel map). Correctness (sorting, limit, malformed skip, event projection
// and tenant/company scope isolation) is unchanged — the only observable
// difference is total latency.
const _COMPLIANCE_RECENT_READ_CONCURRENCY = 16;

/** @internal Bounded-parallel Map(input) => output preserving input order.
 * Never throws for a single item — the mapper is expected to return `null`
 * or a sentinel for malformed rows. */
async function _boundedParallelMap(input, concurrency, mapper) {
  const limit = Math.max(1, Math.min(concurrency, input.length || 1));
  const out = new Array(input.length);
  let next = 0;
  const workers = new Array(limit).fill(0).map(async () => {
    for (;;) {
      const i = next;
      next += 1;
      if (i >= input.length) return;
      out[i] = await mapper(input[i], i);
    }
  });
  await Promise.all(workers);
  return out;
}

async function handleRecent(request, url, env, origin) {
  /* CHIRON-P0-2A: parse tenant/company from the URL BEFORE authenticating so
   * we can accept either a direct compliance admin bearer OR a scoped
   * internal-proxy call from the booking worker. `ensureAuthorizedOrInternalProxy`
   * requires the case-preserved scope (matching the booking-worker's
   * x-fluxidi-proxy-* headers), while KV prefix reads use the lower-cased
   * `safeSegment` value below. */
  const totalStart = Date.now();
  const tenant = parseRequiredQuerySegment(url, "tenant_id");
  if (tenant.error) {
    return jsonResponse({ ok: false, error: tenant.error }, 400, origin);
  }
  const company = parseRequiredQuerySegment(url, "company_id");
  if (company.error) {
    return jsonResponse({ ok: false, error: company.error }, 400, origin);
  }
  const tenantIdForScope = cleanText(url.searchParams.get("tenant_id"), 128);
  const companyIdForScope = cleanText(url.searchParams.get("company_id"), 128);

  const authStart = Date.now();
  const authError = ensureAuthorizedOrInternalProxy(request, env, {
    tenantId: tenantIdForScope,
    companyId: companyIdForScope,
  });
  const authMs = Date.now() - authStart;
  if (authError) return authError;

  if (!env || !env.COMPLIANCE_KV || typeof env.COMPLIANCE_KV.list !== "function") {
    return jsonResponse(
      {
        ok: false,
        error: "Compliance storage is not configured (missing COMPLIANCE_KV binding).",
      },
      500,
      origin,
    );
  }

  const limit = parseRecentLimit(url);
  if (limit.error) {
    return jsonResponse({ ok: false, error: limit.error }, 400, origin);
  }

  const tenantId = tenant.value;
  const companyId = company.value;
  const requestedLimit = limit.value;
  const prefix = [
    "compliance_event_v1",
    "tenant",
    tenantId,
    "company",
    companyId,
    "",
  ].join("/");

  const pageSize = 250;
  const maxScanKeys = 5000;
  const scannedKeyNames = [];
  const seenKeys = new Set();
  let cursor = undefined;
  let listComplete = false;
  let hitScanCap = false;

  const listStart = Date.now();
  while (!listComplete && scannedKeyNames.length < maxScanKeys) {
    let listed;
    try {
      listed = await env.COMPLIANCE_KV.list({
        prefix,
        limit: pageSize,
        ...(cursor ? { cursor } : {}),
      });
    } catch (_) {
      return jsonResponse({ ok: false, error: "Failed to list compliance events." }, 500, origin);
    }

    const keys = Array.isArray(listed?.keys) ? listed.keys : [];
    for (const entry of keys) {
      const keyName = cleanText(entry?.name, 1024);
      if (!keyName || seenKeys.has(keyName)) continue;
      seenKeys.add(keyName);
      scannedKeyNames.push(keyName);
      if (scannedKeyNames.length >= maxScanKeys) break;
    }

    listComplete = listed?.list_complete === true;
    cursor = cleanText(listed?.cursor, 1024) || undefined;
    if (!listComplete && !cursor) {
      // Defensive stop for unexpected KV list response shapes.
      break;
    }
    if (scannedKeyNames.length >= maxScanKeys && !listComplete) {
      hitScanCap = true;
    }
  }
  const listMs = Date.now() - listStart;

  // COMPANY-DATA-LATENCY-P0-REPAIR-1 (Part A): read events with bounded
  // parallelism. The prior sequential `for (const key of scannedKeyNames) {
  // await COMPLIANCE_KV.get(key) }` accumulated N per-request round-trips
  // (~40 ms each), which pushed a 100-event scope past 4 s and, combined
  // with the internal-proxy hop, above the 10 s Flutter timeout. Bounded
  // parallelism preserves malformed-event skipping, tenant/company
  // isolation, event projection and result ordering — only wall-clock time
  // changes.
  const readStart = Date.now();
  const readOutcomes = await _boundedParallelMap(
    scannedKeyNames,
    _COMPLIANCE_RECENT_READ_CONCURRENCY,
    async (key) => {
      let raw;
      try {
        raw = await env.COMPLIANCE_KV.get(key);
      } catch (_) {
        return { ok: false };
      }
      if (!raw) return { ok: false };
      try {
        return { ok: true, key, parsed: JSON.parse(raw) };
      } catch (_) {
        return { ok: false };
      }
    },
  );
  const readMs = Date.now() - readStart;

  const projectStart = Date.now();
  const events = [];
  let malformedCount = 0;
  for (const outcome of readOutcomes) {
    if (!outcome || outcome.ok !== true) {
      malformedCount += 1;
      continue;
    }
    events.push(projectRecentEvent(outcome.key, outcome.parsed));
  }

  const parseMaybeDate = (value) => {
    const text = cleanText(value, 64);
    if (!text) return null;
    const parsed = Date.parse(text);
    if (!Number.isFinite(parsed)) return null;
    return parsed;
  };

  const eventTimestamp = (event) => {
    const ts = event && typeof event.timestamps === "object" && event.timestamps
      ? event.timestamps
      : {};
    return (
      parseMaybeDate(event?.created_at_utc) ??
      parseMaybeDate(ts.recorded_at_utc) ??
      parseMaybeDate(ts.event_at_utc) ??
      parseMaybeDate(ts.paid_at_utc) ??
      parseMaybeDate(ts.stopped_at_utc) ??
      parseMaybeDate(ts.started_at_utc) ??
      null
    );
  };

  const sortedEvents = [...events].sort((a, b) => {
    const aTs = eventTimestamp(a);
    const bTs = eventTimestamp(b);
    if (aTs != null && bTs != null && aTs !== bTs) return bTs - aTs;
    if (aTs != null && bTs == null) return -1;
    if (aTs == null && bTs != null) return 1;
    return cleanText(b?.key, 1024).localeCompare(cleanText(a?.key, 1024));
  });

  // RELEASE-P0-CLOSE-PLANNED-CHIRON-DURABILITY-GAPS-2026-07-31: read-time
  // dedup by `event_id`. Under concurrent first-append races two writers may
  // successfully PUT the DATE-indexed key with slightly different `ms` (their
  // own `created_at_utc`), producing two date rows that resolve to the same
  // canonical event. The canonical event key is deterministic so the *body*
  // is always exactly one row; this dedup ensures the *reader* also sees
  // exactly one row per `(tenant, company, event_id)` on the dashboard.
  // Retains the newest-first entry (sortedEvents is already newest-first).
  // Legacy events without `event_id` are always kept.
  const seenEventIds = new Set();
  const dedupedEvents = [];
  let duplicateCollapsedCount = 0;
  for (const ev of sortedEvents) {
    const evId = cleanText(ev?.event_id, 200);
    if (evId) {
      if (seenEventIds.has(evId)) {
        duplicateCollapsedCount += 1;
        continue;
      }
      seenEventIds.add(evId);
    }
    dedupedEvents.push(ev);
  }

  const limitedEvents = dedupedEvents.slice(0, requestedLimit);
  const hasMoreCandidates = hitScanCap || dedupedEvents.length > requestedLimit;
  const projectMs = Date.now() - projectStart;
  const totalMs = Date.now() - totalStart;

  // PII-free timing diagnostic. Tokens are bounded integers only; no tenant,
  // company, event or payload data is logged.
  console.log(
    `[COMPLIANCE_RECENT] endpoint=recent auth_ms=${authMs} list_ms=${listMs} ` +
      `read_ms=${readMs} project_ms=${projectMs} total_ms=${totalMs} ` +
      `keys=${scannedKeyNames.length} returned=${limitedEvents.length} ` +
      `malformed=${malformedCount} scan_cap=${hitScanCap ? 1 : 0} ` +
      `dedup_collapsed=${duplicateCollapsedCount} ` +
      `concurrency=${_COMPLIANCE_RECENT_READ_CONCURRENCY}`,
  );

  return jsonResponse(
    {
      ok: true,
      tenant_id: tenantId,
      company_id: companyId,
      limit: requestedLimit,
      count: limitedEvents.length,
      malformed_count: malformedCount,
      events: limitedEvents,
      scanned_count: scannedKeyNames.length,
      has_more_candidates: hasMoreCandidates,
    },
    200,
    origin,
  );
}

async function listScopedComplianceEventKeys(env, prefix) {
  const pageSize = 500;
  const maxScanKeys = 10000;
  const keyNames = [];
  const seen = new Set();
  let cursor = undefined;
  let listComplete = false;

  while (!listComplete && keyNames.length < maxScanKeys) {
    const listed = await env.COMPLIANCE_KV.list({
      prefix,
      limit: pageSize,
      ...(cursor ? { cursor } : {}),
    });
    const keys = Array.isArray(listed?.keys) ? listed.keys : [];
    for (const entry of keys) {
      const keyName = cleanText(entry?.name, 1024);
      if (!keyName || seen.has(keyName)) continue;
      seen.add(keyName);
      keyNames.push(keyName);
      if (keyNames.length >= maxScanKeys) break;
    }
    listComplete = listed?.list_complete === true;
    cursor = cleanText(listed?.cursor, 1024) || undefined;
    if (!listComplete && !cursor) break;
  }

  return keyNames;
}

function buildCompliancePrefixForScope(tenantSegment, companySegment) {
  return [
    "compliance_event_v1",
    "tenant",
    tenantSegment,
    "company",
    companySegment,
    "",
  ].join("/");
}

async function handleAdminResetComplianceEvents(request, url, env, origin, dryRun) {
  const authError = ensureAuthorized(request, env);
  if (authError) return authError;

  if (!env || !env.COMPLIANCE_KV || typeof env.COMPLIANCE_KV.list !== "function") {
    return jsonResponse(
      {
        ok: false,
        error: "Compliance storage is not configured (missing COMPLIANCE_KV binding).",
      },
      500,
      origin,
    );
  }

  const tenant = parseRequiredQuerySegment(url, "tenant_id");
  if (tenant.error) {
    return jsonResponse({ ok: false, error: tenant.error }, 400, origin);
  }
  const company = parseRequiredQuerySegment(url, "company_id");
  if (company.error) {
    return jsonResponse({ ok: false, error: company.error }, 400, origin);
  }

  const tenantId = tenant.value;
  const companyId = company.value;
  const prefix = buildCompliancePrefixForScope(tenantId, companyId);

  let keys;
  try {
    keys = await listScopedComplianceEventKeys(env, prefix);
  } catch (_) {
    return jsonResponse(
      { ok: false, error: "Failed to list scoped compliance event keys." },
      500,
      origin,
    );
  }

  const previewLimit = 20;
  const counts = {
    complianceEvents: keys.length,
    indexes: 0,
  };
  const totalCount = counts.complianceEvents + counts.indexes;

  if (dryRun) {
    return jsonResponse(
      {
        ok: true,
        dryRun: true,
        tenant_id: tenantId,
        company_id: companyId,
        counts,
        totalCount,
        keys: {
          preview: keys.slice(0, previewLimit),
          previewCount: Math.min(previewLimit, keys.length),
        },
        message: "Dry-run only. No compliance events were deleted.",
      },
      200,
      origin,
    );
  }

  if (typeof env.COMPLIANCE_KV.delete !== "function") {
    return jsonResponse(
      { ok: false, error: "Compliance storage delete operation is unavailable." },
      500,
      origin,
    );
  }

  let deleted = 0;
  const failedKeys = [];
  for (const key of keys) {
    try {
      await env.COMPLIANCE_KV.delete(key);
      deleted += 1;
    } catch (_) {
      failedKeys.push(key);
    }
  }

  const ok = failedKeys.length === 0;
  return jsonResponse(
    {
      ok,
      dryRun: false,
      tenant_id: tenantId,
      company_id: companyId,
      deleted: {
        complianceEvents: deleted,
        indexes: 0,
      },
      totalDeleted: deleted,
      failedCount: failedKeys.length,
      failedPreview: failedKeys.slice(0, previewLimit),
      message: ok
        ? "Scoped compliance events deleted."
        : "Scoped compliance events deleted with partial failures.",
    },
    ok ? 200 : 207,
    origin,
  );
}

// === Chiron-1: dry-run blueprint builder, lookup and routes ===
// All helpers below are additive and never mutate compliance_event_v1
// records. They only project existing event fields into a Chiron-shaped
// preview and, when requested, persist that preview under a dedicated
// KV prefix.

function _chironMaskScopeId(value) {
  const text = cleanText(value, 256);
  if (!text) return "-";
  if (text.length <= 6) return text;
  return `${text.slice(0, 3)}...${text.slice(-3)}`;
}

function _chironClassifyEventType(eventType) {
  const normalized = cleanText(eventType, 64).toLowerCase();
  if (CHIRON_REGULATOR_READY_TYPES.has(normalized)) return "regulator_ready";
  if (CHIRON_LOG_ONLY_TYPES.has(normalized)) return "log_only";
  return "unknown";
}

function _chironScoreBucket(score, missingCount) {
  const safeScore = Number.isFinite(Number(score)) ? Number(score) : 0;
  const missing = Number.isFinite(Number(missingCount)) ? Math.max(0, Math.trunc(missingCount)) : 0;
  if (safeScore === 100 && missing === 0) return "ready";
  if (safeScore >= 90 && safeScore < 100 && missing === 0) return "warning";
  return "blocker";
}

function _chironEventTimestampMs(event) {
  const parseMaybeDate = (value) => {
    const text = cleanText(value, 64);
    if (!text) return null;
    const parsed = Date.parse(text);
    return Number.isFinite(parsed) ? parsed : null;
  };
  const ts =
    event?.timestamps && typeof event.timestamps === "object" && !Array.isArray(event.timestamps)
      ? event.timestamps
      : {};
  return (
    parseMaybeDate(event?.created_at_utc) ??
    parseMaybeDate(ts.recorded_at_utc) ??
    parseMaybeDate(ts.event_at_utc) ??
    parseMaybeDate(ts.paid_at_utc) ??
    parseMaybeDate(ts.stopped_at_utc) ??
    parseMaybeDate(ts.started_at_utc) ??
    null
  );
}

function _chironPct(count, total) {
  if (!total) return 0;
  return Math.round((count / total) * 1000) / 10;
}

function _chironPickFirstNonEmpty(...values) {
  for (const value of values) {
    const text = cleanText(value, 256);
    if (text) return text;
  }
  return "";
}

function _chironCloneObject(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  return { ...value };
}

function _chironResolveOccurredAtUtc(event) {
  const timestamps =
    event?.timestamps && typeof event.timestamps === "object" && !Array.isArray(event.timestamps)
      ? event.timestamps
      : {};
  return _chironPickFirstNonEmpty(
    timestamps.event_at_utc,
    timestamps.stopped_at_utc,
    timestamps.started_at_utc,
    timestamps.paid_at_utc,
    timestamps.status_updated_at_utc,
    timestamps.refunded_at_utc,
    timestamps.recorded_at_utc,
    event?.created_at_utc,
  );
}

function _chironProjectRide(event) {
  const ride = {
    ride_type: cleanText(event?.ride_type, 64) || null,
    lifecycle_status: cleanText(event?.lifecycle_status, 64) || null,
    session_id: cleanText(event?.session_id, 128) || null,
    leg_id: cleanText(event?.leg_id, 128) || null,
    leg_type: cleanText(event?.leg_type, 64) || null,
    parent_booking_id: cleanText(event?.parent_booking_id, 128) || null,
    row_key: cleanText(event?.row_key, 196) || null,
    public_booking_reference:
      cleanText(
        event?.public_booking_reference ??
          event?.publicBookingReference ??
          event?.booking_reference ??
          event?.bookingReference ??
          event?.public_reference ??
          event?.publicReference,
        128,
      ) || null,
    receipt_reference:
      cleanText(event?.receipt_reference ?? event?.receiptReference, 128) || null,
    booking_status: cleanText(event?.booking_status, 64) || null,
    previous_status: cleanText(event?.previous_status, 64) || null,
    actor_role: cleanText(event?.actor_role, 64) || null,
  };
  return ride;
}

function _chironProjectDriver(event) {
  const source = _chironCloneObject(event?.driver);
  return {
    driver_id: cleanText(source.driver_id ?? source.driverId, 96) || null,
    driver_name: cleanText(source.driver_name ?? source.driverName, 160) || null,
    license_id: cleanText(source.license_id ?? source.licenseId, 96) || null,
    badge_id: cleanText(source.badge_id ?? source.badgeId, 96) || null,
  };
}

function _chironProjectVehicle(event) {
  const source = _chironCloneObject(event?.vehicle);
  return {
    vehicle_id: cleanText(source.vehicle_id ?? source.vehicleId, 96) || null,
    license_plate:
      cleanText(source.license_plate ?? source.licensePlate ?? source.plate, 64) || null,
    make: cleanText(source.make, 80) || null,
    model: cleanText(source.model, 80) || null,
    vehicle_class:
      cleanText(source.vehicle_class ?? source.vehicleClass ?? source.class, 64) || null,
  };
}

function _chironProjectLocationPoint(point) {
  if (!point || typeof point !== "object" || Array.isArray(point)) return null;
  const label = cleanText(point.label ?? point.address ?? point.name, 256);
  const lat = Number(point.lat);
  const lng = Number(point.lng ?? point.lon);
  const projected = {
    label: label || null,
    lat: Number.isFinite(lat) ? lat : null,
    lng: Number.isFinite(lng) ? lng : null,
  };
  if (!projected.label && projected.lat === null && projected.lng === null) {
    return null;
  }
  return projected;
}

function _chironProjectLocations(event) {
  const source = _chironCloneObject(event?.locations);
  return {
    pickup: _chironProjectLocationPoint(source.pickup),
    dropoff: _chironProjectLocationPoint(source.dropoff),
  };
}

function _chironProjectNonNegativeNumber(value) {
  if (value === null || value === undefined || value === "") return null;
  if (typeof value === "string" && !/^\d+(?:\.\d+)?$/.test(value.trim())) return null;
  const num = Number(value);
  return Number.isFinite(num) && num >= 0 ? num : null;
}

function _chironProjectNonNegativeInteger(value) {
  const num = _chironProjectNonNegativeNumber(value);
  return num !== null && Number.isInteger(num) ? num : null;
}

function _chironProjectCurrency(value) {
  const currency = cleanText(value, 8).toUpperCase();
  return /^[A-Z]{3}$/.test(currency) ? currency : null;
}

function _chironProjectFare(event) {
  const source = _chironCloneObject(event?.fare);
  const currency = _chironProjectCurrency(source.currency);
  const totalAmountCents = _chironProjectNonNegativeInteger(
    source.total_amount_cents ?? source.totalAmountCents,
  );
  const vatAmountCents = _chironProjectNonNegativeInteger(
    source.vat_amount_cents ?? source.vatAmountCents,
  );
  const netAmountCents = _chironProjectNonNegativeInteger(
    source.net_amount_cents ?? source.netAmountCents,
  );
  const totalAmount =
    _chironProjectNonNegativeNumber(source.total_amount ?? source.totalAmount) ??
    (totalAmountCents !== null ? totalAmountCents / 100 : null);
  const vatAmount =
    _chironProjectNonNegativeNumber(source.vat_amount ?? source.vatAmount) ??
    (vatAmountCents !== null ? vatAmountCents / 100 : null);
  const netAmount =
    _chironProjectNonNegativeNumber(source.net_amount ?? source.netAmount) ??
    (netAmountCents !== null ? netAmountCents / 100 : null);
  return {
    currency,
    total_amount: totalAmount,
    total_amount_cents: totalAmountCents,
    distance_km: _chironProjectNonNegativeNumber(source.distance_km ?? source.distanceKm),
    wait_seconds_total: _chironProjectNonNegativeNumber(
      source.wait_seconds_total ?? source.waitSecondsTotal,
    ),
    vat_rate: _chironProjectNonNegativeNumber(source.vat_rate ?? source.vatRate),
    vat_amount: vatAmount,
    vat_amount_cents: vatAmountCents,
    net_amount: netAmount,
    net_amount_cents: netAmountCents,
    tariff_code: cleanText(source.tariff_code ?? source.tariffCode, 96) || null,
  };
}

function _chironProjectPayment(event) {
  const source = _chironCloneObject(event?.payment);
  if (!event?.payment || typeof event.payment !== "object") {
    return null;
  }
  const amount = Number(source.amount);
  return {
    status: cleanText(source.status, 64) || null,
    method: cleanText(source.method, 64) || null,
    source: cleanText(source.source, 64) || null,
    provider: cleanText(source.provider, 64) || null,
    payment_id: cleanText(source.payment_id ?? source.paymentId, 160) || null,
    mollie_payment_id:
      cleanText(source.mollie_payment_id ?? source.molliePaymentId, 160) || null,
    refund_status: cleanText(source.refund_status ?? source.refundStatus, 64) || null,
    credit_status: cleanText(source.credit_status ?? source.creditStatus, 64) || null,
    amount: Number.isFinite(amount) ? amount : null,
    currency: cleanText(source.currency, 8).toUpperCase() || null,
  };
}

function _chironProjectProvenance(event) {
  const source = _chironCloneObject(event?.provenance);
  return {
    producer: cleanText(source.producer, 64) || null,
    source_endpoint: cleanText(source.source_endpoint ?? source.sourceEndpoint, 128) || null,
    backend_confirmed: source.backend_confirmed === true,
    validation_state:
      cleanText(source.validation_state ?? source.validationState, 64) || null,
  };
}

function _chironComputeCompleteness(event, blueprint) {
  const missing = [];
  const warnings = [];

  const tenantId = cleanText(event?.tenant_id, 128);
  const companyId = cleanText(event?.company_id, 128);
  const eventId = cleanText(event?.event_id, 200);
  const eventType = cleanText(event?.event_type, 64);
  const occurredAtUtc = cleanText(blueprint?.occurred_at_utc, 64);
  const bookingId = cleanText(event?.booking_id, 128);
  const tripId = cleanText(event?.trip_id, 128);

  if (!tenantId) missing.push("tenant_id");
  if (!companyId) missing.push("company_id");
  if (!eventId) missing.push("event_id");
  if (!eventType) missing.push("event_type");
  if (!occurredAtUtc) missing.push("occurred_at_utc");
  if (!bookingId && !tripId) missing.push("booking_id_or_trip_id");

  const lowerEventType = eventType.toLowerCase();
  const requiresDriverVehicleBlockers =
    CHIRON_DRIVER_VEHICLE_BLOCKER_EVENT_TYPES.has(lowerEventType);

  const vehicle = blueprint?.vehicle || {};
  const missingVehicleIdentity = !vehicle.vehicle_id && !vehicle.license_plate;
  if (missingVehicleIdentity) {
    if (requiresDriverVehicleBlockers) {
      missing.push("vehicle_id_or_license_plate");
    } else if (!warnings.includes("vehicle_id_or_license_plate")) {
      warnings.push("vehicle_id_or_license_plate");
    }
  }
  const driver = blueprint?.driver || {};
  const missingDriverNameOrId = !driver.driver_id && !driver.driver_name;
  if (missingDriverNameOrId) {
    if (requiresDriverVehicleBlockers) {
      missing.push("driver_id_or_driver_name");
    } else if (!warnings.includes("driver_id_or_driver_name")) {
      warnings.push("driver_id_or_driver_name");
    }
  }

  const fare = blueprint?.fare || {};
  if (fare.total_amount !== null && fare.total_amount !== undefined && !fare.currency) {
    missing.push("fare_currency_when_total_amount_present");
  }

  const payment = blueprint?.payment;
  if (payment && typeof payment === "object" && !payment.status) {
    missing.push("payment_status_when_payment_present");
  }

  if (!vehicle.license_plate) {
    warnings.push("missing_vehicle_license_plate");
  }
  if (!driver.driver_id && !driver.driver_name && !driver.license_id && !driver.badge_id) {
    warnings.push("missing_driver_identity");
  }
  if (fare.vat_rate === null && fare.vat_amount === null && fare.vat_amount_cents === null) {
    warnings.push("missing_vat_breakdown");
  }
  const reportingRegion = cleanText(event?.reporting_region ?? event?.reportingRegion, 64);
  if (!reportingRegion) {
    warnings.push("missing_reporting_region");
  }
  const retryOutboxState = cleanText(
    event?.retry_outbox_state ?? event?.retryOutboxState,
    64,
  );
  if (!retryOutboxState) {
    warnings.push("missing_retry_outbox_state");
  }

  if (lowerEventType === "ride_stop") {
    const locations = blueprint?.locations || {};
    if (!locations.pickup || !locations.dropoff) {
      warnings.push("missing_pickup_or_dropoff_for_ride_stop");
    }
  }
  if (lowerEventType === "payment_update") {
    const paymentAmount =
      payment && typeof payment === "object" ? payment.amount : null;
    if (
      (fare.total_amount === null || fare.total_amount === undefined) &&
      (paymentAmount === null || paymentAmount === undefined)
    ) {
      missing.push("payment_amount_when_payment_update");
    }
    if (!fare.currency) {
      missing.push("currency_when_payment_update");
    }
    const paymentMethod =
      payment && typeof payment === "object" ? cleanText(payment.method, 64) : null;
    const paymentProvider =
      payment && typeof payment === "object" ? cleanText(payment.provider, 64) : null;
    if (!paymentMethod && !paymentProvider) {
      if (!warnings.includes("missing_payment_method_or_provider_for_payment_update")) {
        warnings.push("missing_payment_method_or_provider_for_payment_update");
      }
    } else if (!paymentProvider) {
      if (!warnings.includes("missing_payment_provider_for_payment_update")) {
        warnings.push("missing_payment_provider_for_payment_update");
      }
    }
  }

  // Predictable scoring: missing required = -10, warning = -2. Clamped 0..100.
  const requiredPenalty = missing.length * 10;
  const warningPenalty = warnings.length * 2;
  const score = Math.max(0, Math.min(100, 100 - requiredPenalty - warningPenalty));

  return {
    score,
    missing,
    warnings,
  };
}

function buildChironDryRunBlueprint(event) {
  const safeEvent = event && typeof event === "object" && !Array.isArray(event) ? event : {};
  const occurredAtUtc = _chironResolveOccurredAtUtc(safeEvent);
  const blueprint = {
    event_type: cleanText(safeEvent.event_type, 64) || null,
    occurred_at_utc: occurredAtUtc || null,
    ride: _chironProjectRide(safeEvent),
    driver: _chironProjectDriver(safeEvent),
    vehicle: _chironProjectVehicle(safeEvent),
    locations: _chironProjectLocations(safeEvent),
    fare: _chironProjectFare(safeEvent),
    payment: _chironProjectPayment(safeEvent),
    provenance: _chironProjectProvenance(safeEvent),
  };
  const completeness = _chironComputeCompleteness(safeEvent, blueprint);
  return {
    schema_version: CHIRON_DRYRUN_SCHEMA_VERSION,
    source_schema_version: cleanText(safeEvent.schema_version, 64) || null,
    source_event_id: cleanText(safeEvent.event_id, 200) || null,
    source_event_type: cleanText(safeEvent.event_type, 64) || null,
    tenant_id: cleanText(safeEvent.tenant_id, 128) || null,
    company_id: cleanText(safeEvent.company_id, 128) || null,
    booking_id: cleanText(safeEvent.booking_id, 128) || null,
    trip_id: cleanText(safeEvent.trip_id, 128) || null,
    created_at_utc: nowIso(),
    blueprint,
    completeness,
    sync: {
      dry_run: true,
      would_submit: false,
      target: "chiron",
      state: "not_submitted",
    },
  };
}

function buildChironDryRunStorageKey(blueprint) {
  const createdAt = cleanText(blueprint?.created_at_utc, 64) || nowIso();
  const parsed = Date.parse(createdAt);
  const when = new Date(Number.isFinite(parsed) ? parsed : Date.now());
  const year = String(when.getUTCFullYear()).padStart(4, "0");
  const month = String(when.getUTCMonth() + 1).padStart(2, "0");
  const day = String(when.getUTCDate()).padStart(2, "0");
  const ms = String(when.getTime()).padStart(13, "0");
  return [
    CHIRON_DRYRUN_SCHEMA_VERSION,
    "tenant",
    safeSegment(blueprint?.tenant_id),
    "company",
    safeSegment(blueprint?.company_id),
    year,
    month,
    day,
    `${ms}_${safeSegment(blueprint?.source_event_id, "evt")}`,
  ].join("/");
}

function buildChironDryRunPrefixForScope(tenantSegment, companySegment) {
  return [
    CHIRON_DRYRUN_SCHEMA_VERSION,
    "tenant",
    tenantSegment,
    "company",
    companySegment,
    "",
  ].join("/");
}

async function _chironLookupComplianceEventById(env, tenantSegment, companySegment, eventIdRaw) {
  if (!env?.COMPLIANCE_KV || typeof env.COMPLIANCE_KV.list !== "function") {
    return { ok: false, reason: "kv_unavailable" };
  }
  const eventId = cleanText(eventIdRaw, 200);
  if (!eventId) return { ok: false, reason: "missing_event_id" };
  const prefix = [
    SCHEMA_VERSION,
    "tenant",
    tenantSegment,
    "company",
    companySegment,
    "",
  ].join("/");
  const suffixSafe = safeSegment(eventId, "");
  if (!suffixSafe) return { ok: false, reason: "invalid_event_id" };
  const suffix = `_${suffixSafe}`;
  const pageSize = 500;
  const maxScan = 5000;
  let cursor = undefined;
  let listComplete = false;
  let scanned = 0;
  let matchKey = null;
  while (!listComplete && scanned < maxScan && !matchKey) {
    let listed;
    try {
      listed = await env.COMPLIANCE_KV.list({
        prefix,
        limit: pageSize,
        ...(cursor ? { cursor } : {}),
      });
    } catch (_) {
      return { ok: false, reason: "kv_list_failed" };
    }
    const keys = Array.isArray(listed?.keys) ? listed.keys : [];
    for (const entry of keys) {
      scanned += 1;
      const keyName = cleanText(entry?.name, 1024);
      if (!keyName) continue;
      if (keyName.endsWith(suffix)) {
        matchKey = keyName;
        break;
      }
      if (scanned >= maxScan) break;
    }
    listComplete = listed?.list_complete === true;
    cursor = cleanText(listed?.cursor, 1024) || undefined;
    if (!listComplete && !cursor) break;
  }
  if (!matchKey) {
    return { ok: false, reason: scanned >= maxScan ? "scan_cap" : "not_found" };
  }
  let raw;
  try {
    raw = await env.COMPLIANCE_KV.get(matchKey);
  } catch (_) {
    return { ok: false, reason: "kv_get_failed" };
  }
  if (!raw) return { ok: false, reason: "not_found" };
  try {
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      return { ok: false, reason: "malformed" };
    }
    return { ok: true, event: parsed, key: matchKey };
  } catch (_) {
    return { ok: false, reason: "malformed" };
  }
}

async function handleChironDryrunBuildFromEvent(request, env, origin) {
  const authError = ensureAuthorized(request, env);
  if (authError) return authError;

  if (!requireJsonRequest(request)) {
    return jsonResponse(
      { ok: false, error: "Content-Type must be application/json" },
      400,
      origin,
    );
  }

  const body = await readJsonBody(request);
  if (body === null || typeof body !== "object" || Array.isArray(body)) {
    return jsonResponse({ ok: false, error: "Invalid JSON body" }, 400, origin);
  }

  const tenantId = cleanText(body.tenant_id, 128);
  const companyId = cleanText(body.company_id, 128);
  if (!tenantId || !companyId) {
    return jsonResponse({ ok: false, error: "missing_scope" }, 400, origin);
  }
  const tenantSegment = safeSegment(tenantId, "");
  const companySegment = safeSegment(companyId, "");
  if (!tenantSegment || !companySegment) {
    return jsonResponse({ ok: false, error: "missing_scope" }, 400, origin);
  }

  const persist = body.persist === true;
  let event = null;

  if (body.event && typeof body.event === "object" && !Array.isArray(body.event)) {
    event = body.event;
    const eventTenantId = cleanText(event.tenant_id, 128);
    const eventCompanyId = cleanText(event.company_id, 128);
    if (
      (eventTenantId && eventTenantId !== tenantId) ||
      (eventCompanyId && eventCompanyId !== companyId)
    ) {
      return jsonResponse({ ok: false, error: "scope_mismatch" }, 400, origin);
    }
    if (!eventTenantId) event.tenant_id = tenantId;
    if (!eventCompanyId) event.company_id = companyId;
  } else if (cleanText(body.event_id, 200)) {
    const lookup = await _chironLookupComplianceEventById(
      env,
      tenantSegment,
      companySegment,
      body.event_id,
    );
    if (!lookup.ok) {
      const recoverableReasons = new Set(["not_found", "scan_cap", "malformed"]);
      if (recoverableReasons.has(lookup.reason)) {
        return jsonResponse(
          {
            ok: false,
            error: "event_lookup_not_supported_yet",
            reason: lookup.reason,
          },
          404,
          origin,
        );
      }
      return jsonResponse(
        {
          ok: false,
          error: "event_lookup_not_supported_yet",
          reason: lookup.reason,
        },
        400,
        origin,
      );
    }
    event = lookup.event;
    const lookupTenantId = cleanText(event.tenant_id, 128);
    const lookupCompanyId = cleanText(event.company_id, 128);
    if (
      (lookupTenantId && lookupTenantId !== tenantId) ||
      (lookupCompanyId && lookupCompanyId !== companyId)
    ) {
      return jsonResponse({ ok: false, error: "scope_mismatch" }, 400, origin);
    }
  } else {
    return jsonResponse({ ok: false, error: "event_required" }, 400, origin);
  }

  if (!event || typeof event !== "object" || Array.isArray(event)) {
    return jsonResponse({ ok: false, error: "invalid_event" }, 400, origin);
  }

  const blueprint = buildChironDryRunBlueprint(event);
  console.log(
    `[CHIRON_DRYRUN][BUILD] tenant=${_chironMaskScopeId(tenantId)} company=${_chironMaskScopeId(companyId)} source_event_id=${_chironMaskScopeId(blueprint.source_event_id)} source_event_type=${cleanText(blueprint.source_event_type, 64) || "-"} score=${blueprint.completeness.score} missing=${blueprint.completeness.missing.length} warnings=${blueprint.completeness.warnings.length}`,
  );

  let persisted = false;
  if (persist) {
    if (!env?.COMPLIANCE_KV || typeof env.COMPLIANCE_KV.put !== "function") {
      console.log(
        `[CHIRON_DRYRUN][ERROR] reason=missing_kv tenant=${_chironMaskScopeId(tenantId)} company=${_chironMaskScopeId(companyId)}`,
      );
      return jsonResponse(
        { ok: false, error: "chiron_dryrun_persist_failed", reason: "missing_kv" },
        500,
        origin,
      );
    }
    const key = buildChironDryRunStorageKey(blueprint);
    try {
      await env.COMPLIANCE_KV.put(key, JSON.stringify(blueprint));
      persisted = true;
      console.log(
        `[CHIRON_DRYRUN][PERSIST] tenant=${_chironMaskScopeId(tenantId)} company=${_chironMaskScopeId(companyId)} source_event_id=${_chironMaskScopeId(blueprint.source_event_id)} ok=true`,
      );
    } catch (_) {
      console.log(
        `[CHIRON_DRYRUN][ERROR] reason=persist_failed tenant=${_chironMaskScopeId(tenantId)} company=${_chironMaskScopeId(companyId)} source_event_id=${_chironMaskScopeId(blueprint.source_event_id)}`,
      );
      return jsonResponse(
        { ok: false, error: "chiron_dryrun_persist_failed", reason: "kv_put_failed" },
        500,
        origin,
      );
    }
  }

  return jsonResponse(
    {
      ok: true,
      dry_run: true,
      persisted,
      blueprint,
    },
    200,
    origin,
  );
}

async function handleChironDryrunRecent(request, url, env, origin) {
  const authError = ensureAuthorized(request, env);
  if (authError) return authError;

  if (!env?.COMPLIANCE_KV || typeof env.COMPLIANCE_KV.list !== "function") {
    return jsonResponse(
      {
        ok: false,
        error: "Compliance storage is not configured (missing COMPLIANCE_KV binding).",
      },
      500,
      origin,
    );
  }

  const tenant = parseRequiredQuerySegment(url, "tenant_id");
  if (tenant.error) {
    return jsonResponse({ ok: false, error: tenant.error }, 400, origin);
  }
  const company = parseRequiredQuerySegment(url, "company_id");
  if (company.error) {
    return jsonResponse({ ok: false, error: company.error }, 400, origin);
  }

  const limitRaw = cleanText(url.searchParams.get("limit"), 16);
  let requestedLimit = 25;
  if (limitRaw) {
    const parsed = Number(limitRaw);
    if (!Number.isFinite(parsed) || !Number.isInteger(parsed)) {
      return jsonResponse(
        { ok: false, error: "Invalid query parameter: limit must be an integer." },
        400,
        origin,
      );
    }
    requestedLimit = Math.min(100, Math.max(1, parsed));
  }

  const tenantSegment = tenant.value;
  const companySegment = company.value;
  const prefix = buildChironDryRunPrefixForScope(tenantSegment, companySegment);

  const pageSize = 250;
  const maxScanKeys = 5000;
  const keyNames = [];
  const seenKeys = new Set();
  let cursor = undefined;
  let listComplete = false;
  let hitScanCap = false;

  while (!listComplete && keyNames.length < maxScanKeys) {
    let listed;
    try {
      listed = await env.COMPLIANCE_KV.list({
        prefix,
        limit: pageSize,
        ...(cursor ? { cursor } : {}),
      });
    } catch (_) {
      return jsonResponse(
        { ok: false, error: "Failed to list chiron dry-run blueprints." },
        500,
        origin,
      );
    }
    const keys = Array.isArray(listed?.keys) ? listed.keys : [];
    for (const entry of keys) {
      const keyName = cleanText(entry?.name, 1024);
      if (!keyName || seenKeys.has(keyName)) continue;
      seenKeys.add(keyName);
      keyNames.push(keyName);
      if (keyNames.length >= maxScanKeys) break;
    }
    listComplete = listed?.list_complete === true;
    cursor = cleanText(listed?.cursor, 1024) || undefined;
    if (!listComplete && !cursor) break;
    if (keyNames.length >= maxScanKeys && !listComplete) {
      hitScanCap = true;
    }
  }

  const items = [];
  let malformedCount = 0;
  for (const key of keyNames) {
    let raw;
    try {
      raw = await env.COMPLIANCE_KV.get(key);
    } catch (_) {
      malformedCount += 1;
      continue;
    }
    if (!raw) {
      malformedCount += 1;
      continue;
    }
    try {
      const parsed = JSON.parse(raw);
      if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
        malformedCount += 1;
        continue;
      }
      items.push({ key, ...parsed });
    } catch (_) {
      malformedCount += 1;
    }
  }

  const parseMaybeDate = (value) => {
    const text = cleanText(value, 64);
    if (!text) return null;
    const parsed = Date.parse(text);
    if (!Number.isFinite(parsed)) return null;
    return parsed;
  };

  const sorted = [...items].sort((a, b) => {
    const aTs = parseMaybeDate(a?.created_at_utc);
    const bTs = parseMaybeDate(b?.created_at_utc);
    if (aTs != null && bTs != null && aTs !== bTs) return bTs - aTs;
    if (aTs != null && bTs == null) return -1;
    if (aTs == null && bTs != null) return 1;
    return cleanText(b?.key, 1024).localeCompare(cleanText(a?.key, 1024));
  });

  const limitedItems = sorted.slice(0, requestedLimit);

  return jsonResponse(
    {
      ok: true,
      tenant_id: tenantSegment,
      company_id: companySegment,
      limit: requestedLimit,
      count: limitedItems.length,
      malformed_count: malformedCount,
      scanned_count: keyNames.length,
      has_more_candidates: hitScanCap || sorted.length > requestedLimit,
      items: limitedItems,
    },
    200,
    origin,
  );
}

async function handleChironScoreSummary(request, url, env, origin) {
  /* CHIRON-P0-2A: parse tenant/company from the URL BEFORE authenticating so
   * ensureAuthorizedOrInternalProxy can enforce that the internal-proxy
   * scope header matches this handler's exact scope. The auth check uses
   * the case-preserved cleanText values (matching the booking-worker
   * x-fluxidi-proxy-* headers); KV prefix reads below use the lower-cased
   * segment values. */
  const tenant = parseRequiredQuerySegment(url, "tenant_id");
  if (tenant.error) {
    return jsonResponse({ ok: false, error: tenant.error }, 400, origin);
  }
  const company = parseRequiredQuerySegment(url, "company_id");
  if (company.error) {
    return jsonResponse({ ok: false, error: company.error }, 400, origin);
  }
  const tenantIdForScope = cleanText(url.searchParams.get("tenant_id"), 128);
  const companyIdForScope = cleanText(url.searchParams.get("company_id"), 128);

  const authError = ensureAuthorizedOrInternalProxy(request, env, {
    tenantId: tenantIdForScope,
    companyId: companyIdForScope,
  });
  if (authError) return authError;

  if (!env?.COMPLIANCE_KV || typeof env.COMPLIANCE_KV.list !== "function") {
    return jsonResponse(
      {
        ok: false,
        error: "Compliance storage is not configured (missing COMPLIANCE_KV binding).",
      },
      500,
      origin,
    );
  }

  const sinceParsed = parseOptionalIsoQueryMs(url, "since");
  if (sinceParsed.error) {
    return jsonResponse({ ok: false, error: sinceParsed.error }, 400, origin);
  }
  const untilParsed = parseOptionalIsoQueryMs(url, "until");
  if (untilParsed.error) {
    return jsonResponse({ ok: false, error: untilParsed.error }, 400, origin);
  }

  const eventTypeFilterRaw = cleanText(url.searchParams.get("event_type"), 64).toLowerCase();
  if (eventTypeFilterRaw && !ALLOWED_EVENT_TYPES.has(eventTypeFilterRaw)) {
    return jsonResponse({ ok: false, error: "Invalid query parameter: event_type" }, 400, origin);
  }

  const limitParsed = parseChironScoreSummaryLimit(url);
  if (limitParsed.error) {
    return jsonResponse({ ok: false, error: limitParsed.error }, 400, origin);
  }
  const newestLimitParsed = parseChironNewestEventsLimit(url);
  if (newestLimitParsed.error) {
    return jsonResponse({ ok: false, error: newestLimitParsed.error }, 400, origin);
  }

  const tenantSegment = tenant.value;
  const companySegment = company.value;
  const tenantId = cleanText(url.searchParams.get("tenant_id"), 128);
  const companyId = cleanText(url.searchParams.get("company_id"), 128);
  const requestedLimit = limitParsed.value;
  const newestEventsLimit = newestLimitParsed.value;
  const sinceMs = sinceParsed.value;
  const untilMs = untilParsed.value;

  const prefix = buildCompliancePrefixForScope(tenantSegment, companySegment);
  const listScopedMaxScanKeys = 10000;
  let keyNames;
  try {
    keyNames = await listScopedComplianceEventKeys(env, prefix);
  } catch (_) {
    return jsonResponse({ ok: false, error: "Failed to list compliance events." }, 500, origin);
  }

  const hitScanCap = keyNames.length >= listScopedMaxScanKeys;
  let malformedCount = 0;
  const parsedEvents = [];

  for (const key of keyNames) {
    let raw;
    try {
      raw = await env.COMPLIANCE_KV.get(key);
    } catch (_) {
      malformedCount += 1;
      continue;
    }
    if (!raw) {
      malformedCount += 1;
      continue;
    }
    try {
      const parsed = JSON.parse(raw);
      if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
        malformedCount += 1;
        continue;
      }
      parsedEvents.push({ key, event: parsed });
    } catch (_) {
      malformedCount += 1;
    }
  }

  const filtered = [];
  for (const entry of parsedEvents) {
    const event = entry.event;
    const eventType = cleanText(event.event_type, 64).toLowerCase();
    if (eventTypeFilterRaw && eventType !== eventTypeFilterRaw) continue;

    const eventTs = _chironEventTimestampMs(event);
    if (sinceMs != null && (eventTs == null || eventTs < sinceMs)) continue;
    if (untilMs != null && (eventTs == null || eventTs > untilMs)) continue;

    filtered.push({ key: entry.key, event, eventTs });
  }

  const sortedFiltered = [...filtered].sort((a, b) => {
    const aTs = a.eventTs;
    const bTs = b.eventTs;
    if (aTs != null && bTs != null && aTs !== bTs) return bTs - aTs;
    if (aTs != null && bTs == null) return -1;
    if (aTs == null && bTs != null) return 1;
    return cleanText(b?.key, 1024).localeCompare(cleanText(a?.key, 1024));
  });

  const limitedEntries = sortedFiltered.slice(0, requestedLimit);
  const hasMoreCandidates = hitScanCap || sortedFiltered.length > requestedLimit;

  const scoreSummary = {
    ready_count: 0,
    warning_count: 0,
    blocker_count: 0,
    ready_pct: 0,
    warning_pct: 0,
    blocker_pct: 0,
    avg_score: null,
    min_score: null,
    max_score: null,
  };
  const totalsByType = {};
  const scoresByTypeRaw = {};
  const classificationSummary = {
    regulator_ready: { count: 0, ready: 0, warning: 0, blocker: 0 },
    log_only: { count: 0, ready: 0, warning: 0, blocker: 0 },
    unknown: { count: 0, ready: 0, warning: 0, blocker: 0 },
  };
  const missingTally = {};
  const warningTally = {};
  const newestEvents = [];
  let scoreSum = 0;

  for (const entry of limitedEntries) {
    const parsedEvent = entry.event;
    const blueprint = buildChironDryRunBlueprint(parsedEvent);
    const completeness = blueprint?.completeness || {};
    const score = Number.isFinite(Number(completeness.score)) ? Number(completeness.score) : 0;
    const missing = Array.isArray(completeness.missing) ? completeness.missing : [];
    const warnings = Array.isArray(completeness.warnings) ? completeness.warnings : [];
    const eventType = cleanText(parsedEvent.event_type, 64).toLowerCase() || "unknown";
    const classification = _chironClassifyEventType(eventType);
    const bucket = _chironScoreBucket(score, missing.length);

    scoreSum += score;
    if (scoreSummary.min_score === null || score < scoreSummary.min_score) {
      scoreSummary.min_score = score;
    }
    if (scoreSummary.max_score === null || score > scoreSummary.max_score) {
      scoreSummary.max_score = score;
    }

    if (bucket === "ready") scoreSummary.ready_count += 1;
    else if (bucket === "warning") scoreSummary.warning_count += 1;
    else scoreSummary.blocker_count += 1;

    totalsByType[eventType] = (totalsByType[eventType] || 0) + 1;

    if (!scoresByTypeRaw[eventType]) {
      scoresByTypeRaw[eventType] = {
        count: 0,
        sum: 0,
        min: null,
        max: null,
        ready: 0,
        warning: 0,
        blocker: 0,
      };
    }
    const typeStats = scoresByTypeRaw[eventType];
    typeStats.count += 1;
    typeStats.sum += score;
    typeStats.min = typeStats.min === null ? score : Math.min(typeStats.min, score);
    typeStats.max = typeStats.max === null ? score : Math.max(typeStats.max, score);
    typeStats[bucket] += 1;

    const classBucket = classificationSummary[classification];
    if (classBucket) {
      classBucket.count += 1;
      classBucket[bucket] += 1;
    }

    for (const code of missing) {
      const key = cleanText(code, 96);
      if (!key) continue;
      missingTally[key] = (missingTally[key] || 0) + 1;
    }
    for (const code of warnings) {
      const key = cleanText(code, 96);
      if (!key) continue;
      warningTally[key] = (warningTally[key] || 0) + 1;
    }

    if (newestEvents.length < newestEventsLimit) {
      // Chiron Fase 2A: surface leg-first context on each newest event so the
      // dashboard can render leg_id / leg_type / leg_status / parent_status
      // and the per-leg amount/distance/duration without doing a second
      // recent-events fetch. The fields are additive and stay null when not
      // applicable, so existing consumers of newest_events keep working.
      const newestLegMetadata = projectComplianceLegMetadata(parsedEvent);
      const newestLegProjection = newestLegMetadata?.projection || {};
      newestEvents.push({
        event_id: cleanText(parsedEvent.event_id, 200) || null,
        event_type: eventType || null,
        booking_id: cleanText(parsedEvent.booking_id, 128) || null,
        trip_id: cleanText(parsedEvent.trip_id, 128) || null,
        score,
        missing,
        warnings,
        classification,
        bucket,
        created_at_utc: cleanText(parsedEvent.created_at_utc, 64) || null,
        leg_id: newestLegProjection.leg_id || null,
        leg_type: newestLegProjection.leg_type || null,
        leg_status: newestLegProjection.leg_status || null,
        parent_status: newestLegProjection.parent_status || null,
        leg_price_incl_vat: Number.isFinite(newestLegProjection.leg_price_incl_vat)
          ? newestLegProjection.leg_price_incl_vat
          : null,
        fare_total_amount: Number.isFinite(newestLegProjection.fare_total_amount)
          ? newestLegProjection.fare_total_amount
          : null,
        distance_km: Number.isFinite(newestLegProjection.distance_km)
          ? newestLegProjection.distance_km
          : null,
        duration_min: Number.isFinite(newestLegProjection.duration_min)
          ? newestLegProjection.duration_min
          : null,
      });
    }
  }

  const totalEvents = limitedEntries.length;
  if (totalEvents > 0) {
    scoreSummary.avg_score = Math.round((scoreSum / totalEvents) * 10) / 10;
  }
  scoreSummary.ready_pct = _chironPct(scoreSummary.ready_count, totalEvents);
  scoreSummary.warning_pct = _chironPct(scoreSummary.warning_count, totalEvents);
  scoreSummary.blocker_pct = _chironPct(scoreSummary.blocker_count, totalEvents);

  const scoresByType = {};
  for (const [type, stats] of Object.entries(scoresByTypeRaw)) {
    scoresByType[type] = {
      count: stats.count,
      avg: stats.count > 0 ? Math.round((stats.sum / stats.count) * 10) / 10 : null,
      min: stats.min,
      max: stats.max,
      ready: stats.ready,
      warning: stats.warning,
      blocker: stats.blocker,
    };
  }

  const topMissing = Object.entries(missingTally)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 10)
    .map(([code, count]) => ({ code, count }));

  const topWarnings = Object.entries(warningTally)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 10)
    .map(([code, count]) => ({ code, count }));

  console.log(
    `[CHIRON_SCORE_SUMMARY] tenant=${_chironMaskScopeId(tenantId)} company=${_chironMaskScopeId(companyId)} total=${totalEvents} scanned=${keyNames.length} ready=${scoreSummary.ready_count} warning=${scoreSummary.warning_count} blocker=${scoreSummary.blocker_count}`,
  );

  return jsonResponse(
    {
      ok: true,
      tenant_id: tenantId,
      company_id: companyId,
      scope: {
        since: sinceParsed.raw,
        until: untilParsed.raw,
        event_type: eventTypeFilterRaw || null,
      },
      limit: requestedLimit,
      total_events: totalEvents,
      scanned_count: keyNames.length,
      malformed_count: malformedCount,
      has_more_candidates: hasMoreCandidates,
      score_summary: scoreSummary,
      totals_by_type: totalsByType,
      scores_by_type: scoresByType,
      classification_summary: classificationSummary,
      top_missing: topMissing,
      top_warnings: topWarnings,
      newest_events: newestEvents,
    },
    200,
    origin,
  );
}

// RELEASE-P0-CHIRON-TEST-RUNTIME-GATE-2026-07-31: infrastructure enable-marker
// for the Chiron taxirit ACC/test path. Prior versions also required the
// legacy `CHIRON_EXPORT_API_TOKEN` env var, but that dependency has been
// dropped: the official taxirit-POST authenticates exclusively with the
// per-company OAuth-derived access_token (see
// `_chironPostChironExportTestPayload` / `_chironAcquireOAuthAccessTokenForSubmit`),
// so a static bearer is neither required nor consulted here.
//
// This function intentionally stays PROVIDER-side; it is combined at request
// time with the per-company preflight (`_chironTestflowLiveGate`) which
// additionally enforces:
//   - statusPayload.environment === "test"
//   - statusPayload.production_enabled === false
//   - statusPayload.official_submit_enabled === false
//   - statusPayload.test_credentials_stored === true
//   - statusPayload.last_connection_status === "test_passed"
//   - `_chironExportBaseUrlLooksTestOrAcc(env)` (ACC/test URL allowlist).
function chironExportTestModeEnabled(env) {
  return (
    cleanText(env?.CHIRON_EXPORT_MODE, 32).toLowerCase() === "test" &&
    cleanText(env?.CHIRON_EXPORT_BASE_URL, 512).length > 0
  );
}

function buildChironExportIdempotencyKey(tenantId, companyId, eventId, eventType, occurredAtUtc) {
  return cleanText(
    [tenantId, companyId, eventId, eventType, occurredAtUtc].filter(Boolean).join(":"),
    256,
  );
}

function buildChironExportStatusKey(tenantSegment, companySegment, eventId) {
  return [
    CHIRON_EXPORT_STATUS_SCHEMA,
    "tenant",
    tenantSegment,
    "company",
    companySegment,
    "event",
    safeSegment(eventId, "evt"),
  ].join("/");
}

function _chironSanitizeExportError(message) {
  // Chiron Connect 4B: sanitize all forms in which secrets could surface in
  // upstream/downstream error strings. Covers Authorization headers (Bearer
  // and Basic), form-encoded `key=value` fragments and JSON-quoted fields
  // for access_token / refresh_token / client_secret / api_token / password.
  // Keeps the existing api_token redaction behaviour for back-compat.
  const SECRET_FIELD_PATTERN =
    /(access_token|accesstoken|refresh_token|refreshtoken|client_secret|clientsecret|api_token|apitoken|api_key|apikey|password|secret)/i;
  let safe = String(message ?? "")
    .replace(/Bearer\s+\S+/gi, "Bearer [redacted]")
    .replace(/Basic\s+\S+/gi, "Basic [redacted]");
  // JSON-quoted secret fields: "access_token":"..."
  safe = safe.replace(
    new RegExp(
      `"(${SECRET_FIELD_PATTERN.source.slice(1, -1)})"\\s*:\\s*"[^"]*"`,
      "gi",
    ),
    '"$1":"[redacted]"',
  );
  // Form / query secret fields: access_token=... or access_token: ...
  safe = safe.replace(
    new RegExp(
      `(${SECRET_FIELD_PATTERN.source.slice(1, -1)})\\s*[=:]\\s*[^\\s&"']+`,
      "gi",
    ),
    "$1=[redacted]",
  );
  // Generic legacy fallback: token=... / token: ...
  safe = safe.replace(/\btoken\s*[=:]\s*\S+/gi, "token=[redacted]");
  return cleanText(safe, 256);
}

function _chironExtractExternalReference(data) {
  if (!data || typeof data !== "object" || Array.isArray(data)) return null;
  return (
    cleanText(
      data.external_reference ??
        data.externalReference ??
        data.reference ??
        data.id ??
        data.event_id ??
        data.eventId,
      200,
    ) || null
  );
}

// === Chiron Connect 4B: OAuth2 Client Credentials token exchange =============
// Performs an RFC 6749 §4.4 client_credentials grant against the fixed,
// allowlisted Chiron token endpoint for the given environment. The caller is
// responsible for decrypting the per-company credentials. The access_token is
// only kept in memory inside this function: it is NEVER persisted, cached or
// returned to callers / UI. expires_in is normalized to a non-negative number
// of seconds when present.
function _chironCoerceOAuthExpiresInSeconds(value) {
  if (value === null || value === undefined) return null;
  const num = Number(value);
  if (!Number.isFinite(num) || num < 0) return null;
  return Math.floor(num);
}

async function _chironExchangeOAuthClientCredentials(
  env,
  { environment, clientId, clientSecret } = {},
) {
  const envKey = cleanText(environment, 32).toLowerCase();
  if (envKey !== "test") {
    return { ok: false, error: "unsupported_environment", http_status: null };
  }
  const tokenUrl = CHIRON_OAUTH_TOKEN_URL_BY_ENVIRONMENT[envKey];
  if (!tokenUrl) {
    return { ok: false, error: "missing_token_url", http_status: null };
  }
  if (
    typeof clientId !== "string" ||
    typeof clientSecret !== "string" ||
    !clientId.trim() ||
    !clientSecret.trim()
  ) {
    return { ok: false, error: "missing_credentials", http_status: null };
  }

  const basicAuth = btoa(`${clientId}:${clientSecret}`);
  const formBody = "grant_type=client_credentials";

  const controller = new AbortController();
  const timeout = setTimeout(
    () => controller.abort(),
    CHIRON_OAUTH_EXCHANGE_TIMEOUT_MS,
  );

  let response;
  try {
    response = await fetch(tokenUrl, {
      method: "POST",
      headers: {
        accept: "application/json",
        "content-type": "application/x-www-form-urlencoded",
        authorization: `Basic ${basicAuth}`,
      },
      body: formBody,
      signal: controller.signal,
    });
  } catch (err) {
    clearTimeout(timeout);
    const reason =
      err && err.name === "AbortError" ? "oauth_token_timeout" : "oauth_token_network_error";
    return {
      ok: false,
      error: reason,
      http_status: null,
      sanitized_error: _chironSanitizeExportError(err?.message || reason),
    };
  }
  clearTimeout(timeout);

  const httpStatus = response.status;
  const httpOk = httpStatus >= 200 && httpStatus < 300;

  let parsedBody = null;
  const contentType = cleanText(response.headers.get("content-type"), 128).toLowerCase();
  if (contentType.includes("application/json")) {
    try {
      parsedBody = await response.json();
    } catch (_) {
      parsedBody = null;
    }
  }

  if (!httpOk) {
    // Body may legally be JSON {error,error_description}; we do NOT echo raw
    // body because it could contain access_token in some non-conformant
    // servers. Sanitize the canonical RFC 6749 error fields only.
    const errorCode =
      (parsedBody && typeof parsedBody === "object" && cleanText(parsedBody.error, 64)) ||
      `oauth_http_${httpStatus}`;
    const errorDescription =
      (parsedBody &&
        typeof parsedBody === "object" &&
        cleanText(parsedBody.error_description, 256)) ||
      "";
    return {
      ok: false,
      error: errorCode,
      http_status: httpStatus,
      sanitized_error: _chironSanitizeExportError(
        errorDescription || `HTTP ${httpStatus}`,
      ),
    };
  }

  if (!parsedBody || typeof parsedBody !== "object" || Array.isArray(parsedBody)) {
    return {
      ok: false,
      error: "invalid_oauth_response",
      http_status: httpStatus,
      sanitized_error: "invalid_oauth_response",
    };
  }

  const tokenType = cleanText(parsedBody.token_type, 32).toLowerCase();
  const accessToken = typeof parsedBody.access_token === "string"
    ? parsedBody.access_token.trim()
    : "";
  if (!accessToken || tokenType !== "bearer") {
    return {
      ok: false,
      error: "invalid_oauth_response",
      http_status: httpStatus,
      sanitized_error: "invalid_oauth_response",
    };
  }

  const expiresInSeconds = _chironCoerceOAuthExpiresInSeconds(parsedBody.expires_in);

  // RELEASE-P0-OFFICIAL-CHIRON-OAUTH-SUBMIT-2026-07-31:
  //
  // The access_token now surfaces to the caller for in-memory use during a
  // single official Chiron taxirit POST (see
  // _chironAcquireOAuthAccessTokenForSubmit + _chironPostChironExportTestPayload).
  //
  // MUST NEVER be:
  //   - persisted (no KV, no cache);
  //   - logged (see log calls below and the sanitiser in _chironSanitizeExportError);
  //   - returned to Flutter / admin HTTP responses (connection-test handler
  //     continues to expose only {access_token_obtained: true}, never the token);
  //   - included in any error message.
  //
  // Callers that only need connection-test proof continue to read
  // `access_token_obtained` (unchanged contract). Callers that need to sign a
  // single official taxirit-POST read `_access_token_in_memory_only` and MUST
  // discard it immediately after that submit; that field is intentionally
  // absent from anything that ever reaches storage or a response body.
  return {
    ok: true,
    token_type: "Bearer",
    expires_in_seconds: expiresInSeconds,
    access_token_obtained: true,
    http_status: httpStatus,
    _access_token_in_memory_only: accessToken,
  };
}

// RELEASE-P0-OFFICIAL-CHIRON-OAUTH-SUBMIT-2026-07-31: scoped acquisition
// wrapper for the official Chiron taxirit submit. Reads scoped credentials
// (tenant/company/environment), decrypts them, exchanges for an OAuth2
// access_token, and returns it (in-memory only) to the caller. Enforces
// fail-closed behavior: any decrypt / scheme / env / exchange failure blocks
// the taxirit submit and surfaces a coarse, PII-free error code.
//
// Scope isolation invariants:
//   - credentials are read by (tenantId, companyId, environment). A company-A
//     token can never be exchanged for company-B because the KV key
//     (buildChironCredentialsKvKey) already fully scopes the ciphertext.
//   - environment is HARD-PINNED to "test" (the connection-test flow and
//     export test-mode both refuse anything else); production has no OAuth
//     URL in CHIRON_OAUTH_TOKEN_URL_BY_ENVIRONMENT and is rejected upstream.
//   - the api_token legacy scheme is REJECTED for official taxirit submit —
//     legacy static tokens must never be treated as an OAuth-derived bearer.
async function _chironAcquireOAuthAccessTokenForSubmit(
  env,
  tenantId,
  companyId,
  environment,
) {
  const envKey = cleanText(environment, 32).toLowerCase();
  if (envKey !== "test") {
    return { ok: false, error: "unsupported_environment", http_status: null };
  }

  const credentialsRead = await readChironCredentialsRaw(
    env,
    tenantId,
    companyId,
    envKey,
  );
  if (credentialsRead.error) {
    return { ok: false, error: credentialsRead.error, http_status: null };
  }
  if (!credentialsRead.doc) {
    return { ok: false, error: "missing_test_credentials", http_status: null };
  }
  const credentialsDoc = credentialsRead.doc;
  if (!_chironCredentialsDocReadyForMockTest(credentialsDoc)) {
    return { ok: false, error: "invalid_credential_payload", http_status: null };
  }
  const storedScheme = cleanText(credentialsDoc.auth_scheme, 64).toLowerCase();
  if (storedScheme !== "oauth_client_credentials") {
    // Legacy api_token credentials MUST NOT authenticate an official Chiron
    // submit. This closes the door on the previous static-token path.
    return {
      ok: false,
      error: "oauth_client_credentials_required",
      http_status: null,
    };
  }

  let decryptedPlaintext = "";
  try {
    decryptedPlaintext = await decryptChironCredentialBlob(
      credentialsDoc.credential_payload_encrypted,
      env,
    );
  } catch (_) {
    return { ok: false, error: "credential_decrypt_failed", http_status: null };
  }

  let decryptedPayload = null;
  try {
    decryptedPayload = JSON.parse(decryptedPlaintext);
  } catch (_) {
    return { ok: false, error: "invalid_credential_payload", http_status: null };
  }
  if (!_chironDecryptedCredentialPayloadValid(decryptedPayload)) {
    return { ok: false, error: "invalid_credential_payload", http_status: null };
  }
  if (
    cleanText(decryptedPayload.auth_scheme, 64).toLowerCase() !==
    "oauth_client_credentials"
  ) {
    return {
      ok: false,
      error: "oauth_client_credentials_required",
      http_status: null,
    };
  }

  const exchangeResult = await _chironExchangeOAuthClientCredentials(env, {
    environment: envKey,
    clientId: decryptedPayload.client_id,
    clientSecret: decryptedPayload.client_secret,
  });

  // Even on `ok: true` we only propagate the access token in-memory (never
  // stored, never logged, never in a response body — see caller contract).
  if (!exchangeResult.ok) {
    return {
      ok: false,
      error: cleanText(exchangeResult.error, 120) || "oauth_exchange_failed",
      http_status: exchangeResult.http_status ?? null,
      sanitized_error: exchangeResult.sanitized_error ?? null,
    };
  }
  const accessToken = exchangeResult._access_token_in_memory_only;
  if (typeof accessToken !== "string" || !accessToken) {
    return { ok: false, error: "invalid_oauth_response", http_status: exchangeResult.http_status ?? null };
  }
  return {
    ok: true,
    _access_token_in_memory_only: accessToken,
    token_type: exchangeResult.token_type || "Bearer",
    expires_in_seconds: exchangeResult.expires_in_seconds ?? null,
    http_status: exchangeResult.http_status ?? null,
  };
}

// === Chiron-6A-light: official ride payload draft (additive, opt-in) ===

function normalizeChironKboRegistration(value) {
  const text = cleanText(value, 64);
  if (!text) return null;
  if (/^\d{4}\.\d{3}\.\d{3}$/.test(text)) return text;
  const digits = text.replace(/\D/g, "");
  if (digits.length === 10) {
    return `${digits.slice(0, 4)}.${digits.slice(4, 7)}.${digits.slice(7)}`;
  }
  return null;
}

// RELEASE-P0-CHIRON-REGISTRATION-KBO-CANONICAL-2026-07-31:
//
// Chiron ACC requires the official taxirit-JSON field
// `rit.taxibedrijf.aanbieder.registratie` to be byte-identical to the KBO
// subject that authenticated the OAuth call. Chiron's OAuth issuer stores
// KBO as a 10-digit Belgian enterprise number WITHOUT dots, WITHOUT the
// `BE` prefix, and WITHOUT any other separators. Any mismatch (e.g. a
// dotted display form like `0772.931.038`) yields a Chiron `fouten[]`
// rejection ("kbonummers komen niet overeen") — regardless of numeric
// equality.
//
// This helper produces the wire-canonical digits-only form for that ONE
// JSON field, and returns null when the input can't be normalized to
// exactly 10 digits so the serializer can fail-closed instead of shipping
// a malformed body. The internal display form (`0772.931.038`) used for
// idempotency keys, validators and readiness output is intentionally
// UNCHANGED — this transform only runs at the last-hop wire serializer.
function chironOfficialRegistratieWire(value) {
  return normalizeBelgianEnterpriseNumber(value);
}

// RELEASE-P0-CHIRON-LICENSE-PLATE-WIRE-2026-07-31:
//
// Chiron ACC returns fouten `CH1212` ("Kentekenplaat (…) mag enkel
// alfanumerieke tekens bevatten.") when the payload contains any non
// [A-Z0-9] character (spaces, dots, dashes, lowercase). Fluxidi stores
// Belgian taxi plates in a human-readable dashed form (e.g. `T-XAA-674`
// or `TX-ABC-123`); those separators must be stripped on the wire only,
// without touching the internal vehicle profile / app display / event
// records / validators.
//
// Rules:
//   - uppercase;
//   - remove every non-alphanumeric character;
//   - return null if nothing alphanumeric remains, so the serializer can
//     fail-closed and never ship a body Chiron will reject with CH1212.
//
// Idempotency-key generation (`buildChironOfficialIdempotencyKey`) is
// keyed on `registratie` + `ritnummer` + `status` — NOT on the plate — so
// this transform does not shift the export-status storage-key of any
// prior submit and the failed/definitive retry-state is preserved.
function chironOfficialKentekenplaatWire(value) {
  const text = cleanText(value, 32);
  if (!text) return null;
  const alnum = text.toUpperCase().replace(/[^A-Z0-9]/g, "");
  return alnum.length > 0 ? alnum : null;
}

function normalizeChironMoney(value) {
  if (value === null || value === undefined || value === "") return null;
  const num = Number(value);
  if (!Number.isFinite(num) || num < 0) return null;
  return Math.round(num * 100) / 100;
}

function normalizeChironCoordinate(value, kind) {
  const num = Number(value);
  if (!Number.isFinite(num)) return null;
  if (kind === "lat" && (num < -90 || num > 90)) return null;
  if (kind === "lng" && (num < -180 || num > 180)) return null;
  return num;
}

function _chironOfficialRegistratieFieldKeys() {
  return [
    "kbo_number",
    "kboNumber",
    "kbo",
    "enterprise_number",
    "enterpriseNumber",
    "company_registration_number",
    "companyRegistrationNumber",
    "business_identifier",
    "businessIdentifier",
    "tax_or_registration_id",
    "taxOrRegistrationId",
    "registration",
    "registration_number",
    "registrationNumber",
    "registratie",
  ];
}

function _chironOfficialNaamFieldKeys() {
  return [
    "legal_name",
    "legalName",
    "company_name",
    "companyName",
    "business_name",
    "businessName",
    "name",
    "naam",
  ];
}

function _chironNormalizeRegistratieFromProfile(profile) {
  if (!profile || typeof profile !== "object" || Array.isArray(profile)) return null;
  const raw = _chironOfficialPickProfileField({}, profile, ..._chironOfficialRegistratieFieldKeys());
  const kbo = normalizeChironKboRegistration(raw);
  if (kbo) return kbo;
  const vatRaw = cleanText(profile.vat_number ?? profile.vatNumber, 64);
  if (!vatRaw) return null;
  const digits = vatRaw.replace(/^BE/i, "").replace(/\D/g, "");
  if (digits.length === 10) return normalizeChironKboRegistration(digits);
  return null;
}

function _chironNormalizeNaamFromProfile(profile) {
  if (!profile || typeof profile !== "object" || Array.isArray(profile)) return null;
  return (
    cleanText(_chironOfficialPickProfileField({}, profile, ..._chironOfficialNaamFieldKeys()), 256) ||
    null
  );
}

function _chironScopedProfileKv(env) {
  if (env?.BOOKING_KV && typeof env.BOOKING_KV.get === "function") return env.BOOKING_KV;
  return null;
}

function _chironBuildScopedBusinessProfileKey(scope) {
  const tenantId = cleanText(scope?.tenant_id, 128);
  const companyId = cleanText(scope?.company_id, 128);
  if (!tenantId || !companyId) return null;
  return `tenant:${tenantId}:company:${companyId}:business_profile:v1`;
}

function _chironBuildScopedFleetVehiclesKey(scope) {
  const tenantId = cleanText(scope?.tenant_id, 128);
  const companyId = cleanText(scope?.company_id, 128);
  if (!tenantId || !companyId) return null;
  return `tenant:${tenantId}:company:${companyId}:fleet:vehicles:v1`;
}

function _chironBuildScopedDriverIndexKey(scope) {
  const tenantId = cleanText(scope?.tenant_id, 128);
  const companyId = cleanText(scope?.company_id, 128);
  if (!tenantId || !companyId) return null;
  return `tenant:${tenantId}:company:${companyId}:drivers:index:v1`;
}

function _chironParseScopedBusinessProfileRaw(raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  const nested = raw.business_profile ?? raw.businessProfile;
  if (nested && typeof nested === "object" && !Array.isArray(nested)) return nested;
  if (raw.companyName || raw.company_name || raw.legalName || raw.legal_name || raw.kbo_number) {
    return raw;
  }
  return null;
}

function _chironFleetVehiclesFromKvRaw(raw) {
  if (Array.isArray(raw)) return raw;
  if (raw && typeof raw === "object" && Array.isArray(raw.vehicles)) return raw.vehicles;
  return [];
}

function _chironDriverIndexFromKvRaw(raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return {};
  const drivers = raw.drivers;
  if (drivers && typeof drivers === "object" && !Array.isArray(drivers)) return drivers;
  return {};
}

async function readScopedBusinessProfileForChiron(env, scope) {
  const kv = _chironScopedProfileKv(env);
  const key = _chironBuildScopedBusinessProfileKey(scope);
  if (!kv || !key) return { profile: null, lookup: "not_attempted" };
  try {
    const raw = await kv.get(key);
    if (!raw) return { profile: null, lookup: "miss" };
    const parsed = JSON.parse(raw);
    const profile = _chironParseScopedBusinessProfileRaw(parsed);
    if (!profile) return { profile: null, lookup: "miss" };
    return { profile, lookup: "hit" };
  } catch (_) {
    return { profile: null, lookup: "error" };
  }
}

async function readScopedFleetVehiclesForChiron(env, scope) {
  const kv = _chironScopedProfileKv(env);
  const key = _chironBuildScopedFleetVehiclesKey(scope);
  if (!kv || !key) return { vehicles: [], lookup: "not_attempted" };
  try {
    const raw = await kv.get(key);
    if (!raw) return { vehicles: [], lookup: "miss" };
    const parsed = JSON.parse(raw);
    const vehicles = _chironFleetVehiclesFromKvRaw(parsed);
    if (!vehicles.length) return { vehicles: [], lookup: "miss" };
    return { vehicles, lookup: "hit" };
  } catch (_) {
    return { vehicles: [], lookup: "error" };
  }
}

async function readScopedDriverIndexForChiron(env, scope) {
  const kv = _chironScopedProfileKv(env);
  const key = _chironBuildScopedDriverIndexKey(scope);
  if (!kv || !key) return { drivers: {}, lookup: "not_attempted" };
  try {
    const raw = await kv.get(key);
    if (!raw) return { drivers: {}, lookup: "miss" };
    const parsed = JSON.parse(raw);
    const drivers = _chironDriverIndexFromKvRaw(parsed);
    if (!Object.keys(drivers).length) return { drivers: {}, lookup: "miss" };
    return { drivers, lookup: "hit" };
  } catch (_) {
    return { drivers: {}, lookup: "error" };
  }
}

async function _chironLoadScopedHydrationCache(env, scope, includeOfficialDraft = false) {
  const empty = {
    businessProfile: null,
    businessProfileLookup: "not_attempted",
    fleetVehicles: [],
    fleetLookup: "not_attempted",
    driverIndex: {},
    driverIndexLookup: "not_attempted",
  };
  if (!includeOfficialDraft) return empty;
  if (!_chironScopedProfileKv(env)) return empty;

  const [business, fleet, drivers] = await Promise.all([
    readScopedBusinessProfileForChiron(env, scope),
    readScopedFleetVehiclesForChiron(env, scope),
    readScopedDriverIndexForChiron(env, scope),
  ]);

  return {
    businessProfile: business.profile,
    businessProfileLookup: business.lookup,
    fleetVehicles: fleet.vehicles,
    fleetLookup: fleet.lookup,
    driverIndex: drivers.drivers,
    driverIndexLookup: drivers.lookup,
  };
}

function _chironResolveAssignedVehicleId(event, blueprint) {
  const safeEvent = event && typeof event === "object" && !Array.isArray(event) ? event : {};
  const eventVehicle =
    safeEvent.vehicle && typeof safeEvent.vehicle === "object" && !Array.isArray(safeEvent.vehicle)
      ? safeEvent.vehicle
      : {};
  const assignment =
    safeEvent.assignment &&
    typeof safeEvent.assignment === "object" &&
    !Array.isArray(safeEvent.assignment)
      ? safeEvent.assignment
      : {};
  const bpVehicle =
    blueprint?.vehicle && typeof blueprint.vehicle === "object" && !Array.isArray(blueprint.vehicle)
      ? blueprint.vehicle
      : {};
  return (
    cleanText(
      eventVehicle.vehicle_id ??
        eventVehicle.vehicleId ??
        assignment.vehicle_id ??
        assignment.vehicleId ??
        safeEvent.vehicle_id ??
        safeEvent.vehicleId ??
        bpVehicle.vehicle_id,
      96,
    ) || null
  );
}

function _chironResolveAssignedDriverId(event, blueprint) {
  const safeEvent = event && typeof event === "object" && !Array.isArray(event) ? event : {};
  const eventDriver =
    safeEvent.driver && typeof safeEvent.driver === "object" && !Array.isArray(safeEvent.driver)
      ? safeEvent.driver
      : {};
  const assignment =
    safeEvent.assignment &&
    typeof safeEvent.assignment === "object" &&
    !Array.isArray(safeEvent.assignment)
      ? safeEvent.assignment
      : {};
  const bpDriver =
    blueprint?.driver && typeof blueprint.driver === "object" && !Array.isArray(blueprint.driver)
      ? blueprint.driver
      : {};
  return (
    cleanText(
      eventDriver.driver_id ??
        eventDriver.driverId ??
        assignment.driver_id ??
        assignment.driverId ??
        safeEvent.driver_id ??
        safeEvent.driverId ??
        bpDriver.driver_id,
      96,
    ) || null
  );
}

function _chironPlateFromVehicleRecord(vehicle) {
  if (!vehicle || typeof vehicle !== "object" || Array.isArray(vehicle)) return null;
  return (
    cleanText(
      vehicle.license_plate ?? vehicle.licensePlate ?? vehicle.plate,
      64,
    ) || null
  );
}

function _chironPassFromDriverIndexEntry(entry) {
  if (!entry || typeof entry !== "object" || Array.isArray(entry)) return null;
  return (
    cleanText(
      entry.taxi_driver_card_number ??
        entry.taxiDriverCardNumber ??
        entry.badge_id ??
        entry.badgeId ??
        entry.permit_number ??
        entry.permitNumber ??
        entry.driver_pass_number ??
        entry.driverPassNumber ??
        entry.chiron_driver_pass ??
        entry.chironDriverPass ??
        entry.license_id ??
        entry.licenseId,
      96,
    ) || null
  );
}

function _chironResolveVehiclePlateFromFleet(vehicleId, fleetVehicles) {
  if (!vehicleId || !Array.isArray(fleetVehicles) || !fleetVehicles.length) {
    return { plate: null, lookup: "miss" };
  }
  const matches = fleetVehicles.filter((vehicle) => {
    const id = cleanText(vehicle?.vehicle_id ?? vehicle?.vehicleId ?? vehicle?.id, 96);
    return id && id === vehicleId;
  });
  if (matches.length === 1) {
    return { plate: _chironPlateFromVehicleRecord(matches[0]), lookup: "hit" };
  }
  if (matches.length > 1) return { plate: null, lookup: "ambiguous" };
  return { plate: null, lookup: "miss" };
}

// Chiron-6B-3B: return the matched fleet vehicle record (singleton match only).
function _chironLookupFleetVehicleById(vehicleId, fleetVehicles) {
  if (!vehicleId || !Array.isArray(fleetVehicles) || !fleetVehicles.length) return null;
  const matches = fleetVehicles.filter((vehicle) => {
    const id = cleanText(vehicle?.vehicle_id ?? vehicle?.vehicleId ?? vehicle?.id, 96);
    return id && id === vehicleId;
  });
  if (matches.length !== 1) return null;
  const v = matches[0];
  return v && typeof v === "object" && !Array.isArray(v) ? v : null;
}

function _chironResolveDriverPassFromIndex(driverId, driverIndex) {
  if (!driverId || !driverIndex || typeof driverIndex !== "object") {
    return { pass: null, lookup: "miss" };
  }
  const entry = driverIndex[driverId];
  if (!entry) return { pass: null, lookup: "miss" };
  const pass = _chironPassFromDriverIndexEntry(entry);
  if (pass) return { pass, lookup: "hit" };
  return { pass: null, lookup: "miss" };
}

// Chiron-6B-1: stricter readiness validation for official ride payloads.
function isValidChironCoordinate(value, kind) {
  if (value === null || value === undefined || value === "") return false;
  const num = Number(value);
  if (!Number.isFinite(num)) return false;
  if (Math.abs(num) < 1e-9) return false;
  if (kind === "lat" && (num < -90 || num > 90)) return false;
  if (kind === "lng" && (num < -180 || num > 180)) return false;
  return true;
}

function isInvalidZeroCoordinatePair(lng, lat) {
  // Only a genuinely-provided numeric 0/0 pair is an "invalid zero coordinate".
  // Missing values (null / undefined / empty string) are NOT a zero pair: they
  // are absent coordinates handled separately as missing fields. Without this
  // guard Number(null) === 0 makes a null/null arrival point falsely trip
  // invalid_zero_coordinate_pair instead of a plain "missing coordinate".
  if (lng === null || lng === undefined || lng === "") return false;
  if (lat === null || lat === undefined || lat === "") return false;
  const lngNum = Number(lng);
  const latNum = Number(lat);
  if (!Number.isFinite(lngNum) || !Number.isFinite(latNum)) return false;
  return Math.abs(lngNum) < 1e-9 && Math.abs(latNum) < 1e-9;
}

function isValidChironDistance(value) {
  if (value === null || value === undefined || value === "") return false;
  const num = Number(value);
  if (!Number.isFinite(num)) return false;
  return num > 0;
}

// === Chiron-6B-3A: anti-placeholder + format readiness helpers ===

const CHIRON_PLACEHOLDER_KEYWORDS = [
  "demo",
  "test",
  "fake",
  "voorbeeld",
  "placeholder",
  "dummy",
  "sample",
  "example",
  "lorem",
  "n/a",
  "tbd",
  "todo",
];

const CHIRON_PLACEHOLDER_REGISTRATIONS = new Set([
  "0123456789",
  "0000000000",
  "1111111111",
  "1234567890",
  "9999999999",
]);

const CHIRON_PLACEHOLDER_BUSINESS_NAMES = new Set([
  "fluxidi taxi",
  "fluxidi",
  "taxi demo",
  "demo taxi",
  "test taxi",
  "taxi test",
]);

const CHIRON_PLACEHOLDER_LICENSE_PLATES = new Set([
  "aaa000",
  "aaa-000",
  "1-aaa-000",
  "0-aaa-000",
  "1aaa000",
  "0000aaa",
]);

const CHIRON_PLACEHOLDER_DRIVER_PASSES = new Set([
  "0000",
  "00000000",
  "bp-99999",
  "bp99999",
  "bp-00000",
  "bp00000",
]);

function _chironCompactText(value) {
  return cleanText(value, 256).toLowerCase().replace(/\s+/g, " ").trim();
}

function _chironPlaceholderKeywordHit(value) {
  const compact = _chironCompactText(value);
  if (!compact) return false;
  return CHIRON_PLACEHOLDER_KEYWORDS.some((kw) => compact.includes(kw));
}

function isChironPlaceholderValue(value, kind) {
  const text = cleanText(value, 256);
  if (!text) return false;
  const compact = _chironCompactText(text);
  if (!compact) return false;
  if (_chironPlaceholderKeywordHit(compact)) return true;
  if (kind === "registration") {
    const digits = text.replace(/\D/g, "");
    if (digits.length === 10 && CHIRON_PLACEHOLDER_REGISTRATIONS.has(digits)) return true;
    if (digits.length === 10 && /^(\d)\1{9}$/.test(digits)) return true;
    if (digits.length === 10 && digits === "0123456789") return true;
  }
  if (kind === "business_name") {
    if (CHIRON_PLACEHOLDER_BUSINESS_NAMES.has(compact)) return true;
  }
  if (kind === "license_plate") {
    const normalized = compact.replace(/[\s.]/g, "");
    if (CHIRON_PLACEHOLDER_LICENSE_PLATES.has(normalized)) return true;
    if (/^(.)\1{2,}$/.test(normalized.replace(/-/g, ""))) return true;
  }
  if (kind === "driver_pass") {
    const normalized = compact.replace(/[\s.]/g, "");
    if (CHIRON_PLACEHOLDER_DRIVER_PASSES.has(normalized)) return true;
    if (/^0+$/.test(normalized)) return true;
  }
  return false;
}

function normalizeBelgianEnterpriseNumber(value) {
  const text = cleanText(value, 64);
  if (!text) return null;
  const upper = text.toUpperCase();
  const stripped = upper.startsWith("BE") ? upper.slice(2) : upper;
  const digits = stripped.replace(/\D/g, "");
  if (digits.length !== 10) return null;
  return digits;
}

function isLikelyValidBelgianEnterpriseNumberFormat(value) {
  const digits = normalizeBelgianEnterpriseNumber(value);
  if (!digits) return false;
  if (digits[0] !== "0" && digits[0] !== "1") return false;
  return true;
}

function _chironFormatBelgianEnterpriseDotted(digits) {
  if (!digits || digits.length !== 10) return null;
  return `${digits.slice(0, 4)}.${digits.slice(4, 7)}.${digits.slice(7)}`;
}

function _chironNormalizeLicensePlateForCheck(value) {
  return cleanText(value, 64).toUpperCase().replace(/[\s.]/g, "");
}

function _chironLooksLikeFlemishTaxiPlate(value) {
  const normalized = _chironNormalizeLicensePlateForCheck(value);
  if (!normalized) return false;
  // Belgian taxi plates carry a TX prefix (e.g. TXABC123 / TX-ABC-123).
  return /^TX-?[A-Z0-9-]+$/i.test(normalized);
}

function _chironLooksLikeBelgianStandardPlate(value) {
  const normalized = _chironNormalizeLicensePlateForCheck(value);
  if (!normalized) return false;
  return /^[0-9][-]?[A-Z]{3}[-]?[0-9]{3}$/.test(normalized);
}

function _chironLooksLikeAnyPlateFormat(value) {
  const normalized = _chironNormalizeLicensePlateForCheck(value);
  if (!normalized) return false;
  if (normalized.length < 4 || normalized.length > 16) return false;
  if (!/[A-Z0-9]/.test(normalized)) return false;
  return /^[A-Z0-9-]+$/.test(normalized);
}

function _chironContextLooksFlemishTaxi(context = {}) {
  const country = cleanText(
    context?.country ??
      context?.reporting_region ??
      context?.reportingRegion,
    16,
  ).toUpperCase();
  if (country && country !== "BE") return false;
  const region = cleanText(context?.region ?? context?.reporting_region, 32).toLowerCase();
  if (region === "vl" || region === "flanders" || region === "vlaanderen") return true;
  // Even without explicit Flemish marker, BE + taxi service indicates Flemish Chiron flow.
  const service = cleanText(context?.service ?? context?.service_type, 32).toLowerCase();
  if (country === "BE" && (service === "taxi" || service === "" || service === "ride")) {
    return true;
  }
  return false;
}

function verifyChironOfficialRegistration(value, context = {}) {
  const out = {
    status: "missing",
    source: cleanText(context.source, 64) || "missing",
    checks: [],
    warnings: [],
    errors: [],
    document: _chironDefaultDocSummary("business"),
  };
  const raw = cleanText(value, 64);
  if (!raw) return out;
  out.checks.push("present");

  const digits = normalizeBelgianEnterpriseNumber(raw);
  if (digits) {
    out.checks.push("be_enterprise_format");
    const dotted = _chironFormatBelgianEnterpriseDotted(digits);
    if (
      isChironPlaceholderValue(raw, "registration") ||
      isChironPlaceholderValue(digits, "registration") ||
      (dotted && isChironPlaceholderValue(dotted, "registration"))
    ) {
      out.status = "placeholder";
      out.errors.push("placeholder_registration");
      _chironApplyBusinessDocumentMarkers(out, context);
      return out;
    }
    if (!isLikelyValidBelgianEnterpriseNumberFormat(digits)) {
      out.status = "format_invalid";
      out.errors.push("invalid_registration_format");
      _chironApplyBusinessDocumentMarkers(out, context);
      return out;
    }
    out.status = "format_valid";
    _chironApplyBusinessDocumentMarkers(out, context);
    return out;
  }

  if (isChironPlaceholderValue(raw, "registration")) {
    out.status = "placeholder";
    out.errors.push("placeholder_registration");
    _chironApplyBusinessDocumentMarkers(out, context);
    return out;
  }
  out.status = "format_invalid";
  out.errors.push("invalid_registration_format");
  _chironApplyBusinessDocumentMarkers(out, context);
  return out;
}

function verifyChironOfficialBusinessName(value, context = {}) {
  const out = {
    status: "missing",
    source: cleanText(context.source, 64) || "missing",
    checks: [],
    warnings: [],
    errors: [],
    document: _chironDefaultDocSummary("business"),
  };
  const raw = cleanText(value, 256);
  if (!raw) return out;
  out.checks.push("present");

  if (isChironPlaceholderValue(raw, "business_name")) {
    out.status = "placeholder";
    out.errors.push("placeholder_business_name");
    _chironApplyBusinessDocumentMarkers(out, context);
    return out;
  }
  const compact = _chironCompactText(raw);
  if (compact.length < 2 || !/[a-z]/i.test(raw)) {
    out.status = "format_invalid";
    out.errors.push("invalid_business_name");
    _chironApplyBusinessDocumentMarkers(out, context);
    return out;
  }
  out.status = "format_valid";
  _chironApplyBusinessDocumentMarkers(out, context);
  return out;
}

function verifyChironOfficialLicensePlate(value, context = {}) {
  const out = {
    status: "missing",
    source: cleanText(context.source, 64) || "missing",
    checks: [],
    warnings: [],
    errors: [],
    document: _chironDefaultDocSummary("vehicle"),
  };
  const raw = cleanText(value, 64);
  if (!raw) {
    _chironApplyVehicleDocumentMarkers(out, raw, context);
    return out;
  }
  out.checks.push("present");

  if (isChironPlaceholderValue(raw, "license_plate")) {
    out.status = "placeholder";
    out.errors.push("placeholder_license_plate");
    _chironApplyVehicleDocumentMarkers(out, raw, context);
    return out;
  }

  if (!_chironLooksLikeAnyPlateFormat(raw)) {
    out.status = "format_invalid";
    out.errors.push("invalid_license_plate_format");
    _chironApplyVehicleDocumentMarkers(out, raw, context);
    return out;
  }

  const flemishContext = _chironContextLooksFlemishTaxi(context);
  const looksTaxi = _chironLooksLikeFlemishTaxiPlate(raw);
  const looksBeStandard = _chironLooksLikeBelgianStandardPlate(raw);
  const exception = _chironInspectVehicleTaxiPlateException(context.record || null);

  if (flemishContext && !looksTaxi) {
    if (exception.exception) {
      if (exception.verified) {
        out.checks.push("taxi_plate_exception_verified");
      } else {
        out.warnings.push("taxi_plate_exception_requires_review");
      }
      out.status = "format_valid";
    } else if (looksBeStandard) {
      out.status = "format_invalid";
      out.errors.push("invalid_flemish_taxi_plate");
      _chironApplyVehicleDocumentMarkers(out, raw, context);
      return out;
    } else {
      out.warnings.push("taxi_plate_pattern_not_confirmed");
      out.status = "format_valid";
    }
    _chironApplyVehicleDocumentMarkers(out, raw, context);
    return out;
  }

  if (!flemishContext && !looksTaxi) {
    out.warnings.push("taxi_plate_pattern_not_confirmed");
  } else {
    out.checks.push("flemish_taxi_plate_pattern");
  }
  out.status = "format_valid";
  _chironApplyVehicleDocumentMarkers(out, raw, context);
  return out;
}

function verifyChironOfficialDriverPass(value, context = {}) {
  const out = {
    status: "missing",
    source: cleanText(context.source, 64) || "missing",
    checks: [],
    warnings: [],
    errors: [],
    document: _chironDefaultDocSummary("driver_pass"),
  };
  const raw = cleanText(value, 96);
  if (!raw) {
    _chironApplyDriverDocumentMarkers(out, raw, context);
    return out;
  }
  out.checks.push("present");

  if (isChironPlaceholderValue(raw, "driver_pass")) {
    out.status = "placeholder";
    out.errors.push("placeholder_driver_pass");
    _chironApplyDriverDocumentMarkers(out, raw, context);
    return out;
  }

  if (raw.length < 3) {
    out.status = "format_invalid";
    out.errors.push("invalid_driver_pass_format");
    _chironApplyDriverDocumentMarkers(out, raw, context);
    return out;
  }

  // Legacy explicit override (6B-3A) — keep as direct trust hint.
  const explicitDoc = context.documentVerification || null;
  if (explicitDoc && typeof explicitDoc === "object") {
    const docStatus = cleanText(explicitDoc.status, 32).toLowerCase();
    const docNumber = cleanText(explicitDoc.document_number ?? explicitDoc.documentNumber, 96);
    const docExpired = explicitDoc.expired === true;
    const matches = !docNumber || docNumber === raw;
    if (
      matches &&
      !docExpired &&
      (docStatus === "verified" || docStatus === "approved" || docStatus === "active")
    ) {
      out.status = "document_verified";
      out.checks.push("scoped_document_verified");
      out.document = {
        status: "verified",
        source: "scoped_driver",
        matched: !!docNumber,
        expires_at: cleanText(explicitDoc.expires_at, 64) || null,
        checked_at: cleanText(explicitDoc.verified_at ?? explicitDoc.checked_at, 64) || null,
        document_type: _chironDocLabelForKind("driver_pass"),
      };
      return out;
    }
  }

  out.status =
    out.source === "event" || out.source === "blueprint" ? "self_declared" : "format_valid";
  _chironApplyDriverDocumentMarkers(out, raw, context);
  return out;
}

// === Chiron-6B-3B: document/trust-marker inspection helpers ===

const CHIRON_DOC_STATUS_VERIFIED = new Set([
  "verified",
  "approved",
  "active",
  "accepted",
  "valid",
  "complete",
  "completed",
]);
const CHIRON_DOC_STATUS_REVIEW = new Set([
  "pending",
  "uploaded",
  "needs_review",
  "review_required",
  "in_review",
  "submitted",
  "under_review",
  "awaiting_review",
]);
const CHIRON_DOC_STATUS_REJECTED = new Set([
  "rejected",
  "declined",
  "invalid",
  "denied",
  "revoked",
]);

const CHIRON_DOC_BUSINESS_NESTED_KEYS = [
  "registration_document",
  "registrationDocument",
  "kbo_document",
  "kboDocument",
  "company_document",
  "companyDocument",
  "business_document",
  "businessDocument",
];
const CHIRON_DOC_BUSINESS_LIST_KEYS = ["documents", "business_documents", "businessDocuments"];
const CHIRON_DOC_BUSINESS_STATUS_KEYS = [
  "status",
  "verification_status",
  "verificationStatus",
  "document_status",
  "documentStatus",
  "review_status",
  "reviewStatus",
  "kbo_status",
  "kboStatus",
];
const CHIRON_DOC_BUSINESS_BOOL_VERIFIED_KEYS = ["verified", "is_verified", "approved"];

const CHIRON_DOC_VEHICLE_NESTED_KEYS = [
  "license_plate_document",
  "licensePlateDocument",
  "taxi_permit_document",
  "taxiPermitDocument",
  "vehicle_document",
  "vehicleDocument",
  "inspection_document",
  "inspectionDocument",
  "insurance_document",
  "insuranceDocument",
];
const CHIRON_DOC_VEHICLE_LIST_KEYS = ["documents", "vehicle_documents", "vehicleDocuments"];
const CHIRON_DOC_VEHICLE_STATUS_KEYS = [
  "status",
  "document_status",
  "documentStatus",
  "verification_status",
  "verificationStatus",
  "taxi_license_status",
  "taxiLicenseStatus",
  "vehicle_license_status",
  "vehicleLicenseStatus",
  "inspection_status",
  "inspectionStatus",
  "insurance_status",
  "insuranceStatus",
];
const CHIRON_DOC_VEHICLE_BOOL_VERIFIED_KEYS = ["verified", "is_verified", "approved"];

const CHIRON_DOC_DRIVER_NESTED_KEYS = [
  "driver_pass_document",
  "driverPassDocument",
  "taxi_driver_card_document",
  "taxiDriverCardDocument",
  "driver_card_document",
  "driverCardDocument",
  "driver_document",
  "driverDocument",
];
const CHIRON_DOC_DRIVER_LIST_KEYS = ["documents", "driver_documents", "driverDocuments"];
const CHIRON_DOC_DRIVER_STATUS_KEYS = [
  "status",
  "document_status",
  "documentStatus",
  "verification_status",
  "verificationStatus",
  "driver_pass_status",
  "driverPassStatus",
  "taxi_driver_card_status",
  "taxiDriverCardStatus",
];
const CHIRON_DOC_DRIVER_BOOL_VERIFIED_KEYS = ["verified", "is_verified", "approved"];

const CHIRON_DOC_NUMBER_KEYS = [
  "document_number",
  "documentNumber",
  "number",
  "registration_number",
  "registrationNumber",
  "license_plate",
  "licensePlate",
  "plate",
  "license_id",
  "licenseId",
  "kbo_number",
  "kboNumber",
];

const CHIRON_DOC_EXPIRY_KEYS = [
  "expires_at",
  "expiresAt",
  "expiration_at",
  "expirationAt",
  "expiry_at",
  "expiryAt",
  "expire_at",
  "valid_until",
  "validUntil",
  "valid_through",
  "expires_on",
];

const CHIRON_DOC_VERIFIED_AT_KEYS = [
  "verified_at",
  "verifiedAt",
  "approved_at",
  "approvedAt",
  "checked_at",
  "checkedAt",
  "issued_at",
  "issuedAt",
];

const CHIRON_VEHICLE_EXCEPTION_BOOL_KEYS = [
  "taxi_plate_exception",
  "taxiPlateException",
  "replacement_vehicle",
  "replacementVehicle",
  "temporary_replacement",
  "temporaryReplacement",
  "regional_exception_approved",
  "regionalExceptionApproved",
];

const CHIRON_VEHICLE_EXCEPTION_STATUS_KEYS = [
  "exception_document_status",
  "exceptionDocumentStatus",
  "plate_exception_status",
  "plateExceptionStatus",
];

function _chironNormalizeDocStatusString(value) {
  return cleanText(value, 32).toLowerCase().replace(/[\s-]/g, "_");
}

function _chironClassifyDocStatusString(value) {
  const norm = _chironNormalizeDocStatusString(value);
  if (!norm) return null;
  if (CHIRON_DOC_STATUS_VERIFIED.has(norm)) return "verified";
  if (CHIRON_DOC_STATUS_REVIEW.has(norm)) return "review_required";
  if (CHIRON_DOC_STATUS_REJECTED.has(norm)) return "rejected";
  return null;
}

function _chironPickFirstString(record, keys) {
  if (!record || typeof record !== "object" || Array.isArray(record)) return null;
  for (const key of keys) {
    const value = cleanText(record?.[key], 256);
    if (value) return value;
  }
  return null;
}

function _chironPickFirstBoolean(record, keys) {
  if (!record || typeof record !== "object" || Array.isArray(record)) return null;
  for (const key of keys) {
    const value = record?.[key];
    if (value === true) return true;
    if (value === false) return false;
  }
  return null;
}

function _chironPickFirstObject(record, keys) {
  if (!record || typeof record !== "object" || Array.isArray(record)) return null;
  for (const key of keys) {
    const value = record?.[key];
    if (value && typeof value === "object" && !Array.isArray(value)) return value;
  }
  return null;
}

function _chironCollectDocCandidatesFromLists(record, listKeys) {
  if (!record || typeof record !== "object" || Array.isArray(record)) return [];
  const out = [];
  for (const key of listKeys) {
    const value = record?.[key];
    if (Array.isArray(value)) {
      for (const item of value) {
        if (item && typeof item === "object" && !Array.isArray(item)) out.push(item);
      }
    }
  }
  return out;
}

function _chironDocExpiryStatus(doc) {
  const raw = _chironPickFirstString(doc, CHIRON_DOC_EXPIRY_KEYS);
  if (!raw) return { expired: false, expires_at: null };
  const parsed = Date.parse(raw);
  if (!Number.isFinite(parsed)) return { expired: false, expires_at: null };
  const expired = parsed < Date.now();
  return { expired, expires_at: new Date(parsed).toISOString() };
}

function _chironDocNumberMatchesPayload(doc, payloadValue, normalizer) {
  const docNumber = _chironPickFirstString(doc, CHIRON_DOC_NUMBER_KEYS);
  // No payload value means the caller doesn't want a number-match check
  // (e.g. business_name vs registration document_number). Treat as N/A,
  // not as a mismatch.
  if (!payloadValue) return { hasNumber: false, matched: true };
  if (!docNumber) return { hasNumber: false, matched: true };
  const norm = typeof normalizer === "function" ? normalizer : (v) => cleanText(v, 96).toLowerCase();
  const a = norm(docNumber);
  const b = norm(payloadValue);
  if (!a || !b) return { hasNumber: true, matched: false };
  return { hasNumber: true, matched: a === b };
}

function _chironDocLabelForKind(kind) {
  if (kind === "business") return "business_registration";
  if (kind === "vehicle") return "vehicle_taxi_permit";
  if (kind === "driver_pass") return "driver_pass";
  return null;
}

function _chironInspectDocumentMarker(record, kind, payloadValue, normalizer) {
  const empty = {
    status: "not_available",
    source: "none",
    matched: false,
    expires_at: null,
    checked_at: null,
    document_type: _chironDocLabelForKind(kind),
  };
  if (!record || typeof record !== "object" || Array.isArray(record)) return empty;

  const nestedKeys =
    kind === "business"
      ? CHIRON_DOC_BUSINESS_NESTED_KEYS
      : kind === "vehicle"
      ? CHIRON_DOC_VEHICLE_NESTED_KEYS
      : CHIRON_DOC_DRIVER_NESTED_KEYS;
  const listKeys =
    kind === "business"
      ? CHIRON_DOC_BUSINESS_LIST_KEYS
      : kind === "vehicle"
      ? CHIRON_DOC_VEHICLE_LIST_KEYS
      : CHIRON_DOC_DRIVER_LIST_KEYS;
  const statusKeys =
    kind === "business"
      ? CHIRON_DOC_BUSINESS_STATUS_KEYS
      : kind === "vehicle"
      ? CHIRON_DOC_VEHICLE_STATUS_KEYS
      : CHIRON_DOC_DRIVER_STATUS_KEYS;
  const boolKeys =
    kind === "business"
      ? CHIRON_DOC_BUSINESS_BOOL_VERIFIED_KEYS
      : kind === "vehicle"
      ? CHIRON_DOC_VEHICLE_BOOL_VERIFIED_KEYS
      : CHIRON_DOC_DRIVER_BOOL_VERIFIED_KEYS;

  const sourceLabel =
    kind === "business"
      ? "scoped_business_profile"
      : kind === "vehicle"
      ? "scoped_vehicle"
      : "scoped_driver";

  // Collect candidate doc objects: nested doc fields + list entries.
  const candidates = [];
  const nestedDoc = _chironPickFirstObject(record, nestedKeys);
  if (nestedDoc) candidates.push(nestedDoc);
  for (const c of _chironCollectDocCandidatesFromLists(record, listKeys)) candidates.push(c);

  // Evaluate record-level status as a fallback when no nested doc.
  const recordLevelStatusRaw = _chironPickFirstString(record, statusKeys);
  const recordLevelStatus = _chironClassifyDocStatusString(recordLevelStatusRaw);
  const recordLevelBool = _chironPickFirstBoolean(record, boolKeys);
  const recordLevelExpiry = _chironDocExpiryStatus(record);
  const recordLevelVerifiedAt = _chironPickFirstString(record, CHIRON_DOC_VERIFIED_AT_KEYS);
  const recordLevelNumberMatch = _chironDocNumberMatchesPayload(record, payloadValue, normalizer);

  let best = null; // higher severity wins: rejected > expired > mismatch > review_required > verified > not_available

  const severity = (status) => {
    if (status === "rejected") return 5;
    if (status === "expired") return 4;
    if (status === "mismatch") return 3;
    if (status === "review_required") return 2;
    if (status === "verified") return 1;
    return 0;
  };

  const consider = (candidateSummary) => {
    if (!candidateSummary) return;
    if (!best) {
      best = candidateSummary;
      return;
    }
    if (severity(candidateSummary.status) > severity(best.status)) best = candidateSummary;
  };

  for (const doc of candidates) {
    const classified = _chironClassifyDocStatusString(_chironPickFirstString(doc, statusKeys));
    const boolHint = _chironPickFirstBoolean(doc, boolKeys);
    const expiry = _chironDocExpiryStatus(doc);
    const verifiedAt = _chironPickFirstString(doc, CHIRON_DOC_VERIFIED_AT_KEYS);
    const numberCheck = _chironDocNumberMatchesPayload(doc, payloadValue, normalizer);

    if (classified === "rejected") {
      consider({
        status: "rejected",
        source: sourceLabel,
        matched: numberCheck.matched,
        expires_at: expiry.expires_at,
        checked_at: verifiedAt || null,
        document_type: _chironDocLabelForKind(kind),
      });
      continue;
    }
    if (numberCheck.hasNumber && !numberCheck.matched) {
      consider({
        status: "mismatch",
        source: sourceLabel,
        matched: false,
        expires_at: expiry.expires_at,
        checked_at: verifiedAt || null,
        document_type: _chironDocLabelForKind(kind),
      });
      continue;
    }
    if (expiry.expired) {
      consider({
        status: "expired",
        source: sourceLabel,
        matched: numberCheck.matched,
        expires_at: expiry.expires_at,
        checked_at: verifiedAt || null,
        document_type: _chironDocLabelForKind(kind),
      });
      continue;
    }
    if (classified === "verified" || boolHint === true) {
      consider({
        status: "verified",
        source: sourceLabel,
        matched: numberCheck.matched,
        expires_at: expiry.expires_at,
        checked_at: verifiedAt || null,
        document_type: _chironDocLabelForKind(kind),
      });
      continue;
    }
    if (classified === "review_required" || boolHint === false) {
      consider({
        status: "review_required",
        source: sourceLabel,
        matched: numberCheck.matched,
        expires_at: expiry.expires_at,
        checked_at: verifiedAt || null,
        document_type: _chironDocLabelForKind(kind),
      });
      continue;
    }
  }

  // If no nested/list doc told us anything, fall back to record-level signals.
  if (!best && recordLevelStatus) {
    if (recordLevelStatus === "rejected") {
      consider({
        status: "rejected",
        source: sourceLabel,
        matched: recordLevelNumberMatch.matched,
        expires_at: recordLevelExpiry.expires_at,
        checked_at: recordLevelVerifiedAt || null,
        document_type: _chironDocLabelForKind(kind),
      });
    } else if (recordLevelExpiry.expired) {
      consider({
        status: "expired",
        source: sourceLabel,
        matched: recordLevelNumberMatch.matched,
        expires_at: recordLevelExpiry.expires_at,
        checked_at: recordLevelVerifiedAt || null,
        document_type: _chironDocLabelForKind(kind),
      });
    } else if (recordLevelNumberMatch.hasNumber && !recordLevelNumberMatch.matched) {
      consider({
        status: "mismatch",
        source: sourceLabel,
        matched: false,
        expires_at: recordLevelExpiry.expires_at,
        checked_at: recordLevelVerifiedAt || null,
        document_type: _chironDocLabelForKind(kind),
      });
    } else if (recordLevelStatus === "verified") {
      consider({
        status: "verified",
        source: sourceLabel,
        matched: recordLevelNumberMatch.matched,
        expires_at: recordLevelExpiry.expires_at,
        checked_at: recordLevelVerifiedAt || null,
        document_type: _chironDocLabelForKind(kind),
      });
    } else if (recordLevelStatus === "review_required") {
      consider({
        status: "review_required",
        source: sourceLabel,
        matched: recordLevelNumberMatch.matched,
        expires_at: recordLevelExpiry.expires_at,
        checked_at: recordLevelVerifiedAt || null,
        document_type: _chironDocLabelForKind(kind),
      });
    }
  }

  if (!best && recordLevelBool === true) {
    consider({
      status: "verified",
      source: sourceLabel,
      matched: recordLevelNumberMatch.matched,
      expires_at: recordLevelExpiry.expires_at,
      checked_at: recordLevelVerifiedAt || null,
      document_type: _chironDocLabelForKind(kind),
    });
  } else if (!best && recordLevelBool === false) {
    consider({
      status: "review_required",
      source: sourceLabel,
      matched: recordLevelNumberMatch.matched,
      expires_at: recordLevelExpiry.expires_at,
      checked_at: recordLevelVerifiedAt || null,
      document_type: _chironDocLabelForKind(kind),
    });
  }

  return best || empty;
}

function _chironInspectVehicleTaxiPlateException(vehicleRecord) {
  if (!vehicleRecord || typeof vehicleRecord !== "object" || Array.isArray(vehicleRecord)) {
    return { exception: false, verified: false };
  }
  const boolHit = CHIRON_VEHICLE_EXCEPTION_BOOL_KEYS.some((k) => vehicleRecord?.[k] === true);
  const statusRaw = _chironPickFirstString(vehicleRecord, CHIRON_VEHICLE_EXCEPTION_STATUS_KEYS);
  const statusClass = _chironClassifyDocStatusString(statusRaw);
  if (!boolHit && !statusClass) return { exception: false, verified: false };
  return { exception: true, verified: statusClass === "verified" };
}

function _chironDefaultDocSummary(kind) {
  return {
    status: "not_available",
    source: "none",
    matched: false,
    expires_at: null,
    checked_at: null,
    document_type: _chironDocLabelForKind(kind),
  };
}

function _chironNormalizeLicensePlateForDocMatch(value) {
  return cleanText(value, 64).toUpperCase().replace(/[\s.\-]/g, "");
}

function _chironNormalizeRegistrationForDocMatch(value) {
  return cleanText(value, 64).toUpperCase().replace(/[^0-9A-Z]/g, "");
}

function _chironNormalizeDriverPassForDocMatch(value) {
  return cleanText(value, 96).toUpperCase().replace(/[\s.\-_]/g, "");
}

function _chironMergeWarnings(out, codes) {
  for (const code of codes) {
    if (code && !out.warnings.includes(code)) out.warnings.push(code);
  }
}

function _chironMergeErrors(out, codes) {
  for (const code of codes) {
    if (code && !out.errors.includes(code)) out.errors.push(code);
  }
}

function _chironApplyBusinessDocumentMarkers(out, context = {}) {
  const record = context.record || null;
  if (!record) return;
  const docSummary = _chironInspectDocumentMarker(
    record,
    "business",
    context.payloadValue || null,
    _chironNormalizeRegistrationForDocMatch,
  );
  out.document = docSummary;
  if (docSummary.status === "verified" && out.status === "format_valid") {
    out.status = "document_verified";
    if (!out.checks.includes("scoped_document_verified")) out.checks.push("scoped_document_verified");
  }
  if (docSummary.status === "review_required") {
    _chironMergeWarnings(out, ["business_document_review_required"]);
  }
  if (docSummary.status === "expired") {
    _chironMergeErrors(out, ["business_document_expired"]);
  }
  if (docSummary.status === "mismatch") {
    _chironMergeErrors(out, ["business_document_mismatch"]);
  }
  if (docSummary.status === "rejected") {
    _chironMergeErrors(out, ["business_document_rejected"]);
  }
}

function _chironApplyVehicleDocumentMarkers(out, payloadValue, context = {}) {
  const record = context.record || null;
  if (!record) return;
  const docSummary = _chironInspectDocumentMarker(
    record,
    "vehicle",
    payloadValue || null,
    _chironNormalizeLicensePlateForDocMatch,
  );
  out.document = docSummary;
  if (docSummary.status === "verified" && (out.status === "format_valid" || out.status === "missing")) {
    if (out.status === "format_valid") {
      out.status = "document_verified";
      if (!out.checks.includes("scoped_document_verified")) out.checks.push("scoped_document_verified");
    }
  }
  if (docSummary.status === "review_required") {
    _chironMergeWarnings(out, ["vehicle_document_review_required"]);
  }
  if (docSummary.status === "expired") {
    _chironMergeErrors(out, ["vehicle_document_expired"]);
  }
  if (docSummary.status === "mismatch") {
    _chironMergeErrors(out, ["vehicle_document_mismatch"]);
  }
  if (docSummary.status === "rejected") {
    _chironMergeErrors(out, ["vehicle_document_rejected"]);
  }
  // If no document marker AND we already have a format-valid plate, hint at review.
  if (docSummary.status === "not_available" && out.status === "format_valid") {
    _chironMergeWarnings(out, ["vehicle_document_review_required"]);
  }
}

function _chironApplyDriverDocumentMarkers(out, payloadValue, context = {}) {
  const record = context.record || null;
  if (!record) {
    // Without a record we still hint at review for non-blocker driver pass states.
    if (out.status === "self_declared" || out.status === "format_valid") {
      _chironMergeWarnings(out, ["driver_pass_document_review_required"]);
    }
    return;
  }
  const docSummary = _chironInspectDocumentMarker(
    record,
    "driver_pass",
    payloadValue || null,
    _chironNormalizeDriverPassForDocMatch,
  );
  out.document = docSummary;
  if (docSummary.status === "verified" && (out.status === "format_valid" || out.status === "self_declared")) {
    out.status = "document_verified";
    if (!out.checks.includes("scoped_document_verified")) out.checks.push("scoped_document_verified");
  }
  if (docSummary.status === "review_required") {
    _chironMergeWarnings(out, ["driver_pass_document_review_required"]);
  }
  if (docSummary.status === "expired") {
    _chironMergeErrors(out, ["driver_pass_document_expired"]);
  }
  if (docSummary.status === "mismatch") {
    _chironMergeErrors(out, ["driver_pass_document_mismatch"]);
  }
  if (docSummary.status === "rejected") {
    _chironMergeErrors(out, ["driver_pass_document_rejected"]);
  }
  if (
    docSummary.status === "not_available" &&
    (out.status === "self_declared" || out.status === "format_valid")
  ) {
    _chironMergeWarnings(out, ["driver_pass_document_review_required"]);
  }
}

function _chironVerificationLookupStatusMap(hydrated) {
  return {
    kbo: "not_attempted",
    vat: "not_attempted",
    vehicle:
      hydrated?.vehicle?.vehicle_profile_lookup === "ambiguous"
        ? "ambiguous"
        : "not_attempted",
    driver_pass: "not_attempted",
  };
}

function _chironVerificationOverallStatus(perField) {
  const values = Object.values(perField || {});
  if (!values.length) return "missing";
  const hasBlocker = values.some(
    (v) =>
      v.status === "format_invalid" ||
      v.status === "placeholder" ||
      (Array.isArray(v.errors) && v.errors.length > 0),
  );
  if (hasBlocker) return "blocked";
  const hasMissing = values.some((v) => v.status === "missing");
  if (hasMissing) return "missing";
  const allVerified = values.every(
    (v) =>
      v.status === "registry_verified" ||
      v.status === "document_verified" ||
      v.status === "chiron_test_verified",
  );
  if (allVerified) return "verified";
  const anyFormatValid = values.some(
    (v) =>
      v.status === "format_valid" ||
      v.status === "self_declared" ||
      v.status === "document_verified",
  );
  // If any field requires document review or has only format-valid proof, prefer
  // "required_review" over the looser "format_valid" overall label.
  const reviewSignals = values.some(
    (v) =>
      v.status === "self_declared" ||
      (Array.isArray(v.warnings) && v.warnings.some((w) => /review_required$/.test(w))) ||
      (v.document && v.document.status === "review_required"),
  );
  if (reviewSignals) return "required_review";
  if (anyFormatValid) return "format_valid";
  return "required_review";
}

function _chironExtractFlemishContextFromRecord(record) {
  if (!record || typeof record !== "object" || Array.isArray(record)) return {};
  const country = cleanText(
    record.country ?? record.country_code ?? record.countryCode,
    16,
  ).toUpperCase();
  const region = cleanText(record.region ?? record.reporting_region ?? record.reportingRegion, 32);
  const service = cleanText(record.service ?? record.service_type ?? record.serviceType, 32);
  return {
    country: country || null,
    region: region || null,
    service: service || null,
  };
}

function buildChironOfficialVerification(payload, hydrated, context = {}) {
  const safePayload = payload && typeof payload === "object" ? payload : {};
  const safeHydrated = hydrated && typeof hydrated === "object" ? hydrated : {};

  // Derive Flemish context across all available record sources (defensive merge).
  const businessCtx = _chironExtractFlemishContextFromRecord(safeHydrated.business?.record);
  const vehicleCtx = _chironExtractFlemishContextFromRecord(safeHydrated.vehicle?.record);
  const plateContext = {
    country:
      context.country ||
      safePayload.country ||
      vehicleCtx.country ||
      businessCtx.country ||
      null,
    region:
      context.region || vehicleCtx.region || businessCtx.region || null,
    reporting_region: context.reporting_region || null,
    service: context.service || vehicleCtx.service || businessCtx.service || null,
  };

  const perField = {
    registration: verifyChironOfficialRegistration(safePayload.registratie, {
      source: safeHydrated.business?.source || "missing",
      record: safeHydrated.business?.record || null,
      payloadValue: safePayload.registratie || null,
    }),
    business_name: verifyChironOfficialBusinessName(safePayload.naam, {
      source: safeHydrated.business?.source || "missing",
      record: safeHydrated.business?.record || null,
    }),
    license_plate: verifyChironOfficialLicensePlate(safePayload.kentekenplaat, {
      ...plateContext,
      source: safeHydrated.vehicle?.source || "missing",
      record: safeHydrated.vehicle?.record || null,
    }),
    driver_pass: verifyChironOfficialDriverPass(safePayload.bestuurderspasnummer, {
      source: safeHydrated.driver?.source || "missing",
      record: safeHydrated.driver?.record || null,
      documentVerification: context.driverDocumentVerification || null,
    }),
  };

  const documentChecks = {
    business: perField.registration.document?.status || perField.business_name.document?.status || "not_available",
    vehicle: perField.license_plate.document?.status || "not_available",
    driver_pass: perField.driver_pass.document?.status || "not_available",
  };

  return {
    ...perField,
    overall_status: _chironVerificationOverallStatus(perField),
    registry_checks: _chironVerificationLookupStatusMap(safeHydrated),
    document_checks: documentChecks,
  };
}

function _chironCollectVerificationBlockingErrors(verification) {
  if (!verification || typeof verification !== "object") return [];
  const codes = [];
  for (const key of ["registration", "business_name", "license_plate", "driver_pass"]) {
    const field = verification[key];
    if (!field || !Array.isArray(field.errors)) continue;
    for (const code of field.errors) {
      if (code && !codes.includes(code)) codes.push(code);
    }
  }
  return codes;
}

function _chironCollectVerificationWarnings(verification) {
  if (!verification || typeof verification !== "object") return [];
  const codes = [];
  for (const key of ["registration", "business_name", "license_plate", "driver_pass"]) {
    const field = verification[key];
    if (!field || !Array.isArray(field.warnings)) continue;
    for (const code of field.warnings) {
      if (code && !codes.includes(code)) codes.push(code);
    }
  }
  return codes;
}

function _chironOfficialNestedProfile(event) {
  const profile =
    event?.business_profile ??
    event?.businessProfile ??
    event?.company_profile ??
    event?.companyProfile;
  return profile && typeof profile === "object" && !Array.isArray(profile) ? profile : {};
}

function _chironOfficialPickProfileField(event, profile, ...keys) {
  for (const key of keys) {
    const fromEvent = cleanText(event?.[key], 256);
    if (fromEvent) return fromEvent;
    const fromProfile = cleanText(profile?.[key], 256);
    if (fromProfile) return fromProfile;
  }
  return "";
}

function _chironResolveOfficialRitnummer(event, blueprint) {
  const ride = blueprint?.ride || _chironProjectRide(event);
  const base =
    cleanText(event?.booking_id, 128) ||
    cleanText(ride?.public_booking_reference, 128) ||
    cleanText(event?.trip_id, 128) ||
    cleanText(
      event?.public_booking_reference ??
        event?.publicBookingReference ??
        event?.booking_reference ??
        event?.bookingReference,
      128,
    ) ||
    null;
  if (!base) return null;
  // Chiron-3B: roundtrip operational-leg ritnummer scoping. Outbound and
  // return of the same parent booking MUST NOT share the same official
  // Chiron ritnummer because the official sequence (reservatie / vertrek /
  // aankomst) is keyed on ritnummer. When the persisted compliance event
  // carries leg_id / leg_type the booking/tracking workers stamped, append
  // a stable leg suffix so each operational leg gets its own ritnummer in
  // official export, dry-run and readiness aggregation. Non-leg events
  // (booking_created / booking_confirmed, one-way ride_stop, …) keep the
  // existing ritnummer untouched, so backwards compatibility is preserved.
  const legId = cleanText(event?.leg_id ?? event?.legId, 128);
  const legType = cleanText(event?.leg_type ?? event?.legType, 64);
  if (!legId && !legType) return base;
  const legTypeNormalized = legType
    .toLowerCase()
    .replace(/[^a-z0-9_-]/g, "");
  if (legTypeNormalized) return `${base}-${legTypeNormalized}`;
  const legIdNormalized = legId
    .toLowerCase()
    .replace(/[^a-z0-9_-]/g, "");
  if (!legIdNormalized) return base;
  const legIdSuffix =
    legIdNormalized.length > 16 ? legIdNormalized.slice(-16) : legIdNormalized;
  return `${base}-${legIdSuffix}`;
}

function _chironResolveOfficialRegistratie(event, profile = null) {
  const eventProfile = _chironOfficialNestedProfile(event);
  const raw = _chironOfficialPickProfileField(
    event,
    profile || eventProfile,
    ..._chironOfficialRegistratieFieldKeys(),
  );
  const kbo = normalizeChironKboRegistration(raw);
  if (kbo) return kbo;
  if (!profile && eventProfile && Object.keys(eventProfile).length) {
    return _chironNormalizeRegistratieFromProfile(eventProfile);
  }
  return profile ? _chironNormalizeRegistratieFromProfile(profile) : null;
}

function _chironResolveOfficialNaam(event, profile = null) {
  const eventProfile = _chironOfficialNestedProfile(event);
  const fromFields = cleanText(
    _chironOfficialPickProfileField(
      event,
      profile || eventProfile,
      ..._chironOfficialNaamFieldKeys(),
    ),
    256,
  );
  if (fromFields) return fromFields;
  if (!profile && eventProfile && Object.keys(eventProfile).length) {
    return _chironNormalizeNaamFromProfile(eventProfile);
  }
  return profile ? _chironNormalizeNaamFromProfile(profile) : null;
}

function _chironResolveOfficialVertrekTijdstip(event, blueprint) {
  const timestamps =
    event?.timestamps && typeof event.timestamps === "object" && !Array.isArray(event.timestamps)
      ? event.timestamps
      : {};
  return (
    cleanText(
      timestamps.started_at_utc ??
        timestamps.event_at_utc ??
        blueprint?.occurred_at_utc ??
        event?.created_at_utc,
      64,
    ) || null
  );
}

function _chironResolveOfficialAankomstTijdstip(event, blueprint) {
  const timestamps =
    event?.timestamps && typeof event.timestamps === "object" && !Array.isArray(event.timestamps)
      ? event.timestamps
      : {};
  return (
    cleanText(
      timestamps.stopped_at_utc ??
        timestamps.event_at_utc ??
        blueprint?.occurred_at_utc ??
        event?.created_at_utc,
      64,
    ) || null
  );
}

function _chironOfficialHasDepartureStartData(event, blueprint) {
  const vertrektijdstip = _chironResolveOfficialVertrekTijdstip(event, blueprint);
  if (vertrektijdstip) return true;
  const pickup = blueprint?.locations?.pickup;
  if (!pickup) return false;
  return (
    normalizeChironCoordinate(pickup.lat, "lat") !== null &&
    normalizeChironCoordinate(pickup.lng, "lng") !== null
  );
}

function _chironOfficialDraftNotApplicableReason(eventType) {
  const lower = cleanText(eventType, 64).toLowerCase();
  if (
    lower === "payment_update" ||
    lower === "booking_credit_decision" ||
    lower === "booking_mollie_refund"
  ) {
    return "Payment/refund/audit events are not official Chiron ride status messages.";
  }
  return "Event is not an official Chiron ride status message.";
}

function normalizeChironOfficialStatusFromEvent(event, blueprint) {
  const safeEvent = event && typeof event === "object" && !Array.isArray(event) ? event : {};
  const safeBlueprint =
    blueprint && typeof blueprint === "object" && !Array.isArray(blueprint) ? blueprint : {};
  const eventType = cleanText(safeEvent.event_type, 64).toLowerCase();

  if (CHIRON_OFFICIAL_NON_RIDE_STATUS_EVENT_TYPES.has(eventType)) {
    return {
      category: "not_chiron_ride_status",
      status: null,
      mappable: false,
      reason: _chironOfficialDraftNotApplicableReason(eventType),
    };
  }

  if (CHIRON_OFFICIAL_RESERVATION_EVENT_TYPES.has(eventType)) {
    return { category: "ride_payload", status: "reservatie", mappable: true, reason: null };
  }

  if (eventType === "booking_status_update") {
    const ride = safeBlueprint.ride || _chironProjectRide(safeEvent);
    const bookingStatus = cleanText(
      ride.booking_status ??
        safeEvent.booking_status ??
        safeEvent.status ??
        safeEvent.ride_status,
      64,
    ).toLowerCase();
    if (bookingStatus && CHIRON_OFFICIAL_RESERVATION_BOOKING_STATUSES.has(bookingStatus)) {
      return { category: "ride_payload", status: "reservatie", mappable: true, reason: null };
    }
    return {
      category: "not_chiron_ride_status",
      status: null,
      mappable: false,
      reason: _chironOfficialDraftNotApplicableReason(eventType),
    };
  }

  if (CHIRON_OFFICIAL_DEPARTURE_EVENT_TYPES.has(eventType)) {
    if (!_chironOfficialHasDepartureStartData(safeEvent, safeBlueprint)) {
      return {
        category: "not_chiron_ride_status",
        status: null,
        mappable: false,
        reason: "Departure event lacks start timestamp or pickup coordinates.",
      };
    }
    return { category: "ride_payload", status: "vertrek", mappable: true, reason: null };
  }

  if (CHIRON_OFFICIAL_ARRIVAL_EVENT_TYPES.has(eventType)) {
    return { category: "ride_payload", status: "aankomst", mappable: true, reason: null };
  }

  return {
    category: "not_chiron_ride_status",
    status: null,
    mappable: false,
    reason: _chironOfficialDraftNotApplicableReason(eventType),
  };
}

// === Chiron-6B-1: additive identity hydration from event/blueprint ===

function _chironOfficialBlueprintProfile(blueprint) {
  const candidates = [
    blueprint?.business,
    blueprint?.company,
    blueprint?.tenant_profile,
    blueprint?.tenantProfile,
    blueprint?.company_profile,
    blueprint?.companyProfile,
    blueprint?.business_profile,
    blueprint?.businessProfile,
  ];
  for (const candidate of candidates) {
    if (candidate && typeof candidate === "object" && !Array.isArray(candidate)) {
      return candidate;
    }
  }
  return null;
}

function hydrateChironOfficialBusinessIdentity(event, blueprint, scope, context = {}) {
  const safeEvent = event && typeof event === "object" && !Array.isArray(event) ? event : {};
  const safeBlueprint =
    blueprint && typeof blueprint === "object" && !Array.isArray(blueprint) ? blueprint : {};
  const cache = context.scopedHydrationCache || {};

  const eventProfile = _chironOfficialNestedProfile(safeEvent);
  const bpProfile = _chironOfficialBlueprintProfile(safeBlueprint);
  const scopedProfile =
    cache.businessProfile && typeof cache.businessProfile === "object" && !Array.isArray(cache.businessProfile)
      ? cache.businessProfile
      : null;

  let registratie = _chironResolveOfficialRegistratie(safeEvent);
  let naam = _chironResolveOfficialNaam(safeEvent);
  let source = registratie || naam ? "event" : "missing";
  let record = registratie || naam ? eventProfile && Object.keys(eventProfile).length ? eventProfile : null : null;
  let businessProfileLookup = cache.businessProfileLookup || "not_attempted";

  if (!registratie || !naam) {
    if (bpProfile) {
      if (!registratie) {
        const candidate = _chironResolveOfficialRegistratie({}, bpProfile);
        if (candidate) {
          registratie = candidate;
          if (source === "missing") {
            source = "blueprint";
            record = bpProfile;
          }
        }
      }
      if (!naam) {
        const candidate = _chironResolveOfficialNaam({}, bpProfile);
        if (candidate) {
          naam = candidate;
          if (source === "missing") {
            source = "blueprint";
            record = bpProfile;
          }
        }
      }
    }
  }

  if ((!registratie || !naam) && scopedProfile) {
    if (!registratie) {
      const candidate = _chironNormalizeRegistratieFromProfile(scopedProfile);
      if (candidate) {
        registratie = candidate;
        if (source === "missing") {
          source = "scoped_business_profile";
          record = scopedProfile;
        }
      }
    }
    if (!naam) {
      const candidate = _chironNormalizeNaamFromProfile(scopedProfile);
      if (candidate) {
        naam = candidate;
        if (source === "missing") {
          source = "scoped_business_profile";
          record = scopedProfile;
        }
      }
    }
  }

  // Even when identity came from event, scoped business profile may carry
  // trust/document markers we want to expose later.
  if (!record && scopedProfile) record = scopedProfile;

  return {
    registratie: registratie || null,
    naam: naam || null,
    source,
    business_profile_lookup: businessProfileLookup,
    record,
  };
}

function hydrateChironOfficialVehicleIdentity(event, blueprint, context = {}) {
  const safeEvent = event && typeof event === "object" && !Array.isArray(event) ? event : {};
  const safeBlueprint =
    blueprint && typeof blueprint === "object" && !Array.isArray(blueprint) ? blueprint : {};
  const cache = context.scopedHydrationCache || {};
  const eventVehicle =
    safeEvent.vehicle && typeof safeEvent.vehicle === "object" && !Array.isArray(safeEvent.vehicle)
      ? safeEvent.vehicle
      : {};
  const assignment =
    safeEvent.assignment &&
    typeof safeEvent.assignment === "object" &&
    !Array.isArray(safeEvent.assignment)
      ? safeEvent.assignment
      : {};

  let plate =
    cleanText(eventVehicle.license_plate ?? eventVehicle.licensePlate ?? eventVehicle.plate, 64) ||
    cleanText(
      safeEvent.vehicle_license_plate ??
        safeEvent.vehicleLicensePlate ??
        safeEvent.license_plate ??
        safeEvent.licensePlate,
      64,
    ) ||
    cleanText(assignment.license_plate ?? assignment.licensePlate, 64);
  let source = plate ? "event" : "missing";
  let record = plate && Object.keys(eventVehicle).length ? eventVehicle : null;
  let vehicleProfileLookup = cache.fleetLookup || "not_attempted";

  const bpVehicle =
    safeBlueprint.vehicle &&
    typeof safeBlueprint.vehicle === "object" &&
    !Array.isArray(safeBlueprint.vehicle)
      ? safeBlueprint.vehicle
      : {};

  if (!plate) {
    plate = cleanText(bpVehicle.license_plate, 64);
    if (plate) {
      source = "blueprint";
      record = bpVehicle;
    }
  }

  let fleetRecord = null;
  if (Array.isArray(cache.fleetVehicles) && cache.fleetVehicles.length) {
    const vehicleId = _chironResolveAssignedVehicleId(safeEvent, safeBlueprint);
    const fleetMatch = _chironResolveVehiclePlateFromFleet(vehicleId, cache.fleetVehicles);
    if (fleetMatch.plate) {
      fleetRecord = _chironLookupFleetVehicleById(vehicleId, cache.fleetVehicles);
      if (!plate) {
        plate = fleetMatch.plate;
        source = "scoped_vehicle";
        record = fleetRecord;
        vehicleProfileLookup = "hit";
      } else {
        vehicleProfileLookup = "hit";
      }
    } else if (fleetMatch.lookup === "ambiguous") {
      vehicleProfileLookup = "ambiguous";
    } else if (cache.fleetLookup === "hit") {
      vehicleProfileLookup = "miss";
    }
  }

  // Even if plate came from event, expose scoped fleet record for trust markers.
  if (!record && fleetRecord) record = fleetRecord;

  return {
    kentekenplaat: plate || null,
    source,
    vehicle_profile_lookup: vehicleProfileLookup,
    record,
  };
}

function hydrateChironOfficialDriverIdentity(event, blueprint, context = {}) {
  const safeEvent = event && typeof event === "object" && !Array.isArray(event) ? event : {};
  const safeBlueprint =
    blueprint && typeof blueprint === "object" && !Array.isArray(blueprint) ? blueprint : {};
  const cache = context.scopedHydrationCache || {};
  const eventDriver =
    safeEvent.driver && typeof safeEvent.driver === "object" && !Array.isArray(safeEvent.driver)
      ? safeEvent.driver
      : {};

  let pass = cleanText(
    eventDriver.badge_id ??
      eventDriver.badgeId ??
      eventDriver.driver_pass_number ??
      eventDriver.driverPassNumber ??
      eventDriver.permit_number ??
      eventDriver.permitNumber ??
      eventDriver.license_id ??
      eventDriver.licenseId ??
      eventDriver.chiron_driver_pass ??
      eventDriver.chironDriverPass,
    96,
  );
  let source = pass ? "event" : "missing";
  let record = pass && Object.keys(eventDriver).length ? eventDriver : null;
  let driverProfileLookup = cache.driverIndexLookup || "not_attempted";

  const bpDriver =
    safeBlueprint.driver &&
    typeof safeBlueprint.driver === "object" &&
    !Array.isArray(safeBlueprint.driver)
      ? safeBlueprint.driver
      : {};

  if (!pass) {
    pass =
      cleanText(bpDriver.badge_id, 96) ||
      cleanText(bpDriver.license_id, 96) ||
      cleanText(bpDriver.driver_pass_number, 96) ||
      cleanText(bpDriver.permit_number, 96) ||
      cleanText(bpDriver.chiron_driver_pass, 96);
    if (pass) {
      source = "blueprint";
      record = bpDriver;
    }
  }

  let driverIndexEntry = null;
  if (cache.driverIndex && typeof cache.driverIndex === "object") {
    const driverId = _chironResolveAssignedDriverId(safeEvent, safeBlueprint);
    if (driverId) {
      const entry = cache.driverIndex[driverId];
      if (entry && typeof entry === "object" && !Array.isArray(entry)) {
        driverIndexEntry = entry;
      }
    }
    const indexMatch = _chironResolveDriverPassFromIndex(driverId, cache.driverIndex);
    if (indexMatch.pass) {
      if (!pass) {
        pass = indexMatch.pass;
        source = "scoped_driver";
        record = driverIndexEntry || record;
        driverProfileLookup = "hit";
      } else {
        driverProfileLookup = "hit";
      }
    } else if (cache.driverIndexLookup === "hit") {
      driverProfileLookup = driverId ? "miss" : cache.driverIndexLookup;
    }
  }

  // Even if pass came from event, expose scoped driver record for trust markers.
  if (!record && driverIndexEntry) record = driverIndexEntry;

  return {
    bestuurderspasnummer: pass || null,
    source,
    driver_profile_lookup: driverProfileLookup,
    record,
  };
}

function buildChironOfficialPayloadDraft(event, blueprint, scope, officialStatus, hydrated = null) {
  const safeEvent = event && typeof event === "object" && !Array.isArray(event) ? event : {};
  const safeBlueprint =
    blueprint && typeof blueprint === "object" && !Array.isArray(blueprint) ? blueprint : {};
  const fare = safeBlueprint.fare || _chironProjectFare(safeEvent);
  const locations = safeBlueprint.locations || _chironProjectLocations(safeEvent);
  const pickup = locations.pickup || null;
  const dropoff = locations.dropoff || null;

  const business =
    hydrated?.business || hydrateChironOfficialBusinessIdentity(safeEvent, safeBlueprint, scope);
  const vehicle =
    hydrated?.vehicle || hydrateChironOfficialVehicleIdentity(safeEvent, safeBlueprint);
  const driver =
    hydrated?.driver || hydrateChironOfficialDriverIdentity(safeEvent, safeBlueprint);

  const payload = {
    broncreatiedatum: cleanText(safeEvent.created_at_utc, 64) || null,
    ritnummer: _chironResolveOfficialRitnummer(safeEvent, safeBlueprint),
    registratie: business.registratie || null,
    naam: business.naam || null,
    status: officialStatus,
  };

  // Chiron-6B-COORD-HYDRATE: trusted coords/distance pulled from sibling events
  // of the same booking/leg in this batch (see
  // _chironBuildBatchTrustedRideHydrationIndex). Used ONLY to fill values the
  // event itself lacks; never overrides valid event data and never fabricates.
  const trustedRide =
    hydrated?.trustedRide && typeof hydrated.trustedRide === "object"
      ? hydrated.trustedRide
      : _chironEmptyTrustedRideEntry();

  if (officialStatus === "vertrek" || officialStatus === "aankomst") {
    payload.kentekenplaat = vehicle.kentekenplaat || null;
    payload.bestuurderspasnummer = driver.bestuurderspasnummer || null;
    payload.vertrektijdstip = _chironResolveOfficialVertrekTijdstip(safeEvent, safeBlueprint);
    let vLng = normalizeChironCoordinate(pickup?.lng, "lng");
    let vLat = normalizeChironCoordinate(pickup?.lat, "lat");
    if (
      !_chironValidTrustedCoordPair(vLng, vLat) &&
      _chironValidTrustedCoordPair(trustedRide.pickupLng, trustedRide.pickupLat)
    ) {
      vLng = trustedRide.pickupLng;
      vLat = trustedRide.pickupLat;
    }
    // Never emit a 0/0 (or otherwise invalid) coordinate pair: leave the fields
    // null so validation reports them as missing rather than an invalid zero
    // pair. Genuine missing data therefore still blocks.
    if (!_chironValidTrustedCoordPair(vLng, vLat)) {
      vLng = null;
      vLat = null;
    }
    payload.vertrekpunt_lengtegraad = vLng;
    payload.vertrekpunt_breedtegraad = vLat;
  }

  if (officialStatus === "aankomst") {
    payload.aankomsttijdstip = _chironResolveOfficialAankomstTijdstip(safeEvent, safeBlueprint);
    let aLng = normalizeChironCoordinate(dropoff?.lng, "lng");
    let aLat = normalizeChironCoordinate(dropoff?.lat, "lat");
    if (
      !_chironValidTrustedCoordPair(aLng, aLat) &&
      _chironValidTrustedCoordPair(trustedRide.dropoffLng, trustedRide.dropoffLat)
    ) {
      aLng = trustedRide.dropoffLng;
      aLat = trustedRide.dropoffLat;
    }
    if (!_chironValidTrustedCoordPair(aLng, aLat)) {
      aLng = null;
      aLat = null;
    }
    payload.aankomstpunt_lengtegraad = aLng;
    payload.aankomstpunt_breedtegraad = aLat;
    let afstand = normalizeChironMoney(fare.distance_km);
    if (!isValidChironDistance(afstand) && isValidChironDistance(trustedRide.distanceKm)) {
      afstand = normalizeChironMoney(trustedRide.distanceKm);
    }
    payload.afstand = afstand;
    payload.kostprijs = normalizeChironMoney(fare.total_amount);
  }

  return payload;
}

function _chironOfficialPayloadFieldPresent(payload, field) {
  if (!payload || typeof payload !== "object") return false;
  const value = payload[field];
  if (value === null || value === undefined) return false;
  if (typeof value === "string" && !value.trim()) return false;
  return true;
}

function _chironOfficialRequiredFieldsForStatus(officialStatus) {
  if (officialStatus === "reservatie") return [...CHIRON_OFFICIAL_REQUIRED_RESERVATIE];
  if (officialStatus === "vertrek") return [...CHIRON_OFFICIAL_REQUIRED_VERTREK];
  if (officialStatus === "aankomst") return [...CHIRON_OFFICIAL_REQUIRED_AANKOMST];
  return [];
}

function validateChironOfficialPayloadDraft(payload, context = {}) {
  const officialStatus = cleanText(context.officialStatus, 32) || null;
  const category = cleanText(context.category, 64) || "not_chiron_ride_status";

  if (category !== "ride_payload" || !officialStatus) {
    return {
      status: "not_applicable",
      exportable: false,
      missing: [],
      warnings: [],
      errors: [],
      required_fields: [],
    };
  }

  const requiredFields = _chironOfficialRequiredFieldsForStatus(officialStatus);
  const missing = [];
  const warnings = [];
  const errors = [];

  const ensureMissing = (field) => {
    if (!missing.includes(field)) missing.push(field);
  };
  const ensureError = (code) => {
    if (!errors.includes(code)) errors.push(code);
  };

  for (const field of requiredFields) {
    if (!_chironOfficialPayloadFieldPresent(payload, field)) {
      missing.push(field);
    }
  }

  if (!["reservatie", "vertrek", "aankomst"].includes(officialStatus)) {
    errors.push("invalid_official_status");
  }

  // Chiron-6B-1: 0/0 and out-of-range coordinates are not Chiron-ready.
  if (officialStatus === "vertrek" || officialStatus === "aankomst") {
    const vLng = payload?.vertrekpunt_lengtegraad;
    const vLat = payload?.vertrekpunt_breedtegraad;
    if (!isValidChironCoordinate(vLng, "lng")) ensureMissing("vertrekpunt_lengtegraad");
    if (!isValidChironCoordinate(vLat, "lat")) ensureMissing("vertrekpunt_breedtegraad");
    if (isInvalidZeroCoordinatePair(vLng, vLat)) {
      ensureMissing("vertrekpunt_lengtegraad");
      ensureMissing("vertrekpunt_breedtegraad");
      ensureError("invalid_zero_coordinate_pair");
    }
  }

  if (officialStatus === "aankomst") {
    const aLng = payload?.aankomstpunt_lengtegraad;
    const aLat = payload?.aankomstpunt_breedtegraad;
    if (!isValidChironCoordinate(aLng, "lng")) ensureMissing("aankomstpunt_lengtegraad");
    if (!isValidChironCoordinate(aLat, "lat")) ensureMissing("aankomstpunt_breedtegraad");
    if (isInvalidZeroCoordinatePair(aLng, aLat)) {
      ensureMissing("aankomstpunt_lengtegraad");
      ensureMissing("aankomstpunt_breedtegraad");
      ensureError("invalid_zero_coordinate_pair");
    }
    // Distance must be strictly positive for an arrival payload.
    if (!isValidChironDistance(payload?.afstand)) ensureMissing("afstand");
  }

  if (officialStatus === "aankomst" && context.batchRitStatuses && context.ritnummer) {
    const seen = context.batchRitStatuses.get(context.ritnummer);
    if (!seen || (!seen.has("vertrek") && !seen.has("reservatie"))) {
      warnings.push("missing_prior_vertrek_or_reservatie_in_batch");
    }
  }

  // Chiron-6B-3A: surface placeholder/invalid identity errors and pattern warnings.
  const verificationErrors = Array.isArray(context.verificationErrors)
    ? context.verificationErrors
    : [];
  for (const code of verificationErrors) {
    if (!code) continue;
    ensureError(code);
  }
  const verificationWarnings = Array.isArray(context.verificationWarnings)
    ? context.verificationWarnings
    : [];
  for (const code of verificationWarnings) {
    if (!code || warnings.includes(code)) continue;
    warnings.push(code);
  }

  let validationStatus = "ready";
  if (errors.length > 0 || missing.length > 0) {
    validationStatus = "blocker";
  } else if (warnings.length > 0) {
    validationStatus = "warning";
  }

  const validation = {
    status: validationStatus,
    exportable: validationStatus === "ready" || validationStatus === "warning",
    missing,
    warnings,
    errors,
    required_fields: requiredFields,
  };
  if (warnings.includes("missing_prior_vertrek_or_reservatie_in_batch")) {
    validation.sequence_safe = false;
  }
  return validation;
}

function buildChironOfficialIdempotencyKey(scope, registratie, ritnummer, status) {
  return cleanText(
    [
      "chiron_official_v1",
      cleanText(scope?.tenant_id, 128),
      cleanText(scope?.company_id, 128),
      registratie || "-",
      ritnummer || "-",
      status || "-",
    ].join(":"),
    256,
  );
}

function buildChironOfficialDraftEnvelope(event, blueprint, scope, context = {}) {
  const safeEvent = event && typeof event === "object" && !Array.isArray(event) ? event : {};
  const safeBlueprint =
    blueprint && typeof blueprint === "object" && !Array.isArray(blueprint) ? blueprint : {};
  const normalized = normalizeChironOfficialStatusFromEvent(safeEvent, safeBlueprint);

  if (!normalized.mappable || normalized.category !== "ride_payload" || !normalized.status) {
    return {
      schema_version: CHIRON_OFFICIAL_DRAFT_SCHEMA_VERSION,
      category: "not_chiron_ride_status",
      status: null,
      payload: null,
      validation: validateChironOfficialPayloadDraft(null, {
        category: normalized.category,
        officialStatus: null,
      }),
      reason: normalized.reason || _chironOfficialDraftNotApplicableReason(safeEvent.event_type),
    };
  }

  const hydrated = {
    business: hydrateChironOfficialBusinessIdentity(safeEvent, safeBlueprint, scope, context),
    vehicle: hydrateChironOfficialVehicleIdentity(safeEvent, safeBlueprint, context),
    driver: hydrateChironOfficialDriverIdentity(safeEvent, safeBlueprint, context),
    trustedRide: _chironResolveTrustedRideForDraft(
      context.trustedRideHydration || null,
      safeEvent,
      _chironResolveOfficialRitnummer(safeEvent, safeBlueprint),
    ),
  };

  const payload = buildChironOfficialPayloadDraft(
    safeEvent,
    safeBlueprint,
    scope,
    normalized.status,
    hydrated,
  );

  const reportingCountry = cleanText(
    safeEvent?.country ??
      safeEvent?.country_code ??
      safeEvent?.countryCode ??
      safeEvent?.reporting_region ??
      safeEvent?.reportingRegion,
    16,
  );
  const verification = buildChironOfficialVerification(payload, hydrated, {
    country: reportingCountry || null,
    reporting_region: cleanText(safeEvent?.reporting_region ?? safeEvent?.reportingRegion, 32) || null,
    service: cleanText(safeEvent?.service ?? safeEvent?.service_type, 32) || null,
  });
  const verificationErrors = _chironCollectVerificationBlockingErrors(verification);
  const verificationWarnings = _chironCollectVerificationWarnings(verification);

  const validation = validateChironOfficialPayloadDraft(payload, {
    category: normalized.category,
    officialStatus: normalized.status,
    ritnummer: payload.ritnummer,
    batchRitStatuses: context.batchRitStatuses || null,
    verificationErrors,
    verificationWarnings,
  });

  return {
    schema_version: CHIRON_OFFICIAL_DRAFT_SCHEMA_VERSION,
    category: "ride_payload",
    status: normalized.status,
    payload,
    validation,
    hydration: {
      business_identity_source: hydrated.business.source,
      vehicle_identity_source: hydrated.vehicle.source,
      driver_identity_source: hydrated.driver.source,
      business_profile_lookup: hydrated.business.business_profile_lookup || "not_attempted",
      vehicle_profile_lookup: hydrated.vehicle.vehicle_profile_lookup || "not_attempted",
      driver_profile_lookup: hydrated.driver.driver_profile_lookup || "not_attempted",
    },
    verification,
    idempotency_key: buildChironOfficialIdempotencyKey(
      scope,
      payload.registratie,
      payload.ritnummer,
      normalized.status,
    ),
  };
}

function _chironBuildBatchRitStatusIndex(entries) {
  const index = new Map();
  for (const entry of entries) {
    const event = entry?.event;
    if (!event || typeof event !== "object") continue;
    const built = buildChironDryRunBlueprint(event);
    const blueprint = built?.blueprint || {};
    const normalized = normalizeChironOfficialStatusFromEvent(event, blueprint);
    if (!normalized.status) continue;
    const ritnummer = _chironResolveOfficialRitnummer(event, blueprint);
    if (!ritnummer) continue;
    if (!index.has(ritnummer)) {
      index.set(ritnummer, new Map());
    }
    const statusCounts = index.get(ritnummer);
    statusCounts.set(normalized.status, (statusCounts.get(normalized.status) || 0) + 1);
  }
  const simplified = new Map();
  for (const [ritnummer, statusCounts] of index.entries()) {
    simplified.set(ritnummer, new Set(statusCounts.keys()));
  }
  return simplified;
}

// Chiron-6B-COORD-HYDRATE: trusted ride-coordinate / distance index built from
// the SAME scoped compliance event batch the draft is computed against.
//
// Rationale: the aankomst (ride_stop) draft is built from the tracking
// ride_stop event, whose locations/fare come straight from the driver-app
// stop body. When the app posts 0/0 (or no) coordinates and km_total=0 the
// arrival draft gets a 0/0 coordinate pair (invalid_zero_coordinate_pair) and
// afstand 0. The trusted pickup/dropoff coordinates for the same booking are
// already stored on sibling events in this very batch — primarily the
// `booking_confirmed` event, whose locations are projected from the booking
// record's pickup/dropoff coordinates — and the booking distance_km is carried
// on its fare once the booking worker stamps it. This index lets the official
// draft hydrate missing/zero coordinates and distance from those trusted
// siblings WITHOUT inventing data, geocoding, or reaching outside the batch.
//
// Keying:
//   - perRit:     ritnummer (`_chironResolveOfficialRitnummer`, leg-scoped for
//                 roundtrips) -> trusted coords/distance from events sharing the
//                 exact same ritnummer (same leg).
//   - perBooking: raw booking_id -> trusted coords/distance contributed ONLY by
//                 parent/non-leg events (booking_confirmed / booking_created /
//                 one-way ride events). Used as a fallback for OUTBOUND / no-leg
//                 legs only, so a roundtrip RETURN leg never borrows the
//                 parent/outbound coordinates or distance.
function _chironMergeTrustedRideCandidate(target, candidate) {
  if (!target || !candidate) return target;
  if (
    target.pickupLng === null &&
    target.pickupLat === null &&
    candidate.pickupLng !== null &&
    candidate.pickupLat !== null
  ) {
    target.pickupLng = candidate.pickupLng;
    target.pickupLat = candidate.pickupLat;
  }
  if (
    target.dropoffLng === null &&
    target.dropoffLat === null &&
    candidate.dropoffLng !== null &&
    candidate.dropoffLat !== null
  ) {
    target.dropoffLng = candidate.dropoffLng;
    target.dropoffLat = candidate.dropoffLat;
  }
  if (target.distanceKm === null && candidate.distanceKm !== null) {
    target.distanceKm = candidate.distanceKm;
  }
  return target;
}

function _chironEmptyTrustedRideEntry() {
  return {
    pickupLng: null,
    pickupLat: null,
    dropoffLng: null,
    dropoffLat: null,
    distanceKm: null,
  };
}

function _chironTrustedRideCandidateFromEvent(event, blueprint) {
  const locations = blueprint?.locations || _chironProjectLocations(event);
  const fare = blueprint?.fare || _chironProjectFare(event);
  const pickup = locations?.pickup || null;
  const dropoff = locations?.dropoff || null;
  const candidate = _chironEmptyTrustedRideEntry();
  // Only accept coordinates that are individually valid AND not a 0/0 pair.
  if (
    pickup &&
    isValidChironCoordinate(pickup.lng, "lng") &&
    isValidChironCoordinate(pickup.lat, "lat") &&
    !isInvalidZeroCoordinatePair(pickup.lng, pickup.lat)
  ) {
    candidate.pickupLng = normalizeChironCoordinate(pickup.lng, "lng");
    candidate.pickupLat = normalizeChironCoordinate(pickup.lat, "lat");
  }
  if (
    dropoff &&
    isValidChironCoordinate(dropoff.lng, "lng") &&
    isValidChironCoordinate(dropoff.lat, "lat") &&
    !isInvalidZeroCoordinatePair(dropoff.lng, dropoff.lat)
  ) {
    candidate.dropoffLng = normalizeChironCoordinate(dropoff.lng, "lng");
    candidate.dropoffLat = normalizeChironCoordinate(dropoff.lat, "lat");
  }
  if (isValidChironDistance(fare?.distance_km)) {
    candidate.distanceKm = normalizeChironMoney(fare.distance_km);
  }
  return candidate;
}

function _chironEventHasLegScope(event) {
  return !!cleanText(
    event?.leg_id ?? event?.legId ?? event?.leg_type ?? event?.legType,
    64,
  );
}

function _chironBuildBatchTrustedRideHydrationIndex(entries) {
  const perRit = new Map();
  const perBooking = new Map();
  if (!Array.isArray(entries)) return { perRit, perBooking };
  for (const entry of entries) {
    const event = entry?.event;
    if (!event || typeof event !== "object") continue;
    const built = buildChironDryRunBlueprint(event);
    const blueprint = built?.blueprint || {};
    const candidate = _chironTrustedRideCandidateFromEvent(event, blueprint);
    if (
      candidate.pickupLng === null &&
      candidate.dropoffLng === null &&
      candidate.distanceKm === null
    ) {
      continue;
    }
    const ritnummer = _chironResolveOfficialRitnummer(event, blueprint);
    if (ritnummer) {
      if (!perRit.has(ritnummer)) perRit.set(ritnummer, _chironEmptyTrustedRideEntry());
      _chironMergeTrustedRideCandidate(perRit.get(ritnummer), candidate);
    }
    const bookingId = cleanText(event?.booking_id ?? event?.parent_booking_id, 128);
    if (bookingId && !_chironEventHasLegScope(event)) {
      if (!perBooking.has(bookingId)) {
        perBooking.set(bookingId, _chironEmptyTrustedRideEntry());
      }
      _chironMergeTrustedRideCandidate(perBooking.get(bookingId), candidate);
    }
  }
  return { perRit, perBooking };
}

function _chironResolveTrustedRideForDraft(index, event, ritnummer) {
  const resolved = _chironEmptyTrustedRideEntry();
  if (!index || (!index.perRit && !index.perBooking)) return resolved;
  if (ritnummer && index.perRit instanceof Map && index.perRit.has(ritnummer)) {
    _chironMergeTrustedRideCandidate(resolved, index.perRit.get(ritnummer));
  }
  // Parent/booking-level fallback ONLY for outbound or non-leg legs, so a
  // roundtrip RETURN leg never inherits the parent/outbound coords or distance.
  const legType = cleanText(event?.leg_type ?? event?.legType, 64).toLowerCase();
  const allowBookingFallback =
    !legType || legType === "outbound" || legType === "oneway" || legType === "one_way";
  if (allowBookingFallback && index.perBooking instanceof Map) {
    const bookingId = cleanText(event?.booking_id ?? event?.parent_booking_id, 128);
    if (bookingId && index.perBooking.has(bookingId)) {
      _chironMergeTrustedRideCandidate(resolved, index.perBooking.get(bookingId));
    }
  }
  return resolved;
}

function _chironValidTrustedCoordPair(lng, lat) {
  return (
    isValidChironCoordinate(lng, "lng") &&
    isValidChironCoordinate(lat, "lat") &&
    !isInvalidZeroCoordinatePair(lng, lat)
  );
}

// Chiron-3B-LEG-CONSISTENCY: the official Chiron ritnummer is leg-scoped
// (`${bookingId}-${legType}`) via _chironResolveOfficialRitnummer so OUTBOUND
// and RETURN of a roundtrip never share a sequence. Problem: only some events
// carry leg metadata. The tracking ride_stop (aankomst) event is stamped with
// leg_type by the planned-stop pipeline, but the planned ride_start (vertrek)
// event — produced from a tracking session — carries booking_id only, no
// leg_type/leg_id. So departure resolves to `${bookingId}` while arrival
// resolves to `${bookingId}-outbound`, breaking the prior-vertrek sequence
// check (missing_prior_vertrek_or_reservatie_in_batch) and splitting the
// idempotency key.
//
// Fix: resolve the operational-leg type from the booking RECORD and stamp it
// (in-memory only) onto the booking's events that lack any leg metadata, so the
// existing centralized ritnummer / idempotency / batch-status logic all derive
// the SAME leg-scoped ritnummer for departure and arrival.
//
// Safety: we only stamp when the booking is unambiguously single-leg (a booking
// with zero or one operational leg can never be a roundtrip). Multi-leg
// (roundtrip) bookings keep the existing per-event behavior — a legless event
// stays on the base ritnummer rather than risk being attributed to the wrong
// leg — so roundtrips still map strictly per leg with no idempotency drift.
function _chironBookingRecordOperationalLegs(rec) {
  if (!rec || typeof rec !== "object") return [];
  const source = Array.isArray(rec?.operational_legs)
    ? rec.operational_legs
    : Array.isArray(rec?.operationalLegs)
      ? rec.operationalLegs
      : Array.isArray(rec?.booking?.operational_legs)
        ? rec.booking.operational_legs
        : Array.isArray(rec?.booking?.operationalLegs)
          ? rec.booking.operationalLegs
          : [];
  return source.filter((leg) => leg && typeof leg === "object");
}

function _chironBoolStrictTrue(value) {
  return value === true || value === "true" || value === 1 || value === "1";
}

function _chironBoolStrictFalse(value) {
  return value === false || value === "false" || value === 0 || value === "0";
}

// Booking-LEVEL return signal only. We deliberately ignore
// quote.pricing_profile.return_enabled (that is the tenant's *capability*, not
// this booking's intent). A return signal means a legless event can NOT be
// safely attributed to a single leg => no stamping.
function _chironBookingRecordHasReturnSignal(rec) {
  if (!rec || typeof rec !== "object") return false;
  const booking = rec?.booking && typeof rec.booking === "object" ? rec.booking : {};
  const quote = rec?.quote && typeof rec.quote === "object" ? rec.quote : {};
  const quoteReturn = quote?.return && typeof quote.return === "object" ? quote.return : {};
  if (
    _chironBoolStrictTrue(rec?.return_enabled) ||
    _chironBoolStrictTrue(booking?.return_enabled) ||
    _chironBoolStrictTrue(quoteReturn?.enabled)
  ) {
    return true;
  }
  const returnPickup = cleanText(
    rec?.returnPickupIso ??
      rec?.return_pickup_iso ??
      booking?.returnPickupIso ??
      booking?.return_pickup_iso ??
      booking?.return_scheduled_pickup_at ??
      quoteReturn?.pickup_iso,
    64,
  );
  if (returnPickup) return true;
  for (const leg of _chironBookingRecordOperationalLegs(rec)) {
    const t = cleanText(leg.leg_type ?? leg.legType, 64).toLowerCase();
    if (t.includes("return")) return true;
  }
  return false;
}

// Positive one-way assertion: return is explicitly disabled at booking level
// AND there is no return pickup/schedule. Absence of the flag is NOT enough.
function _chironBookingRecordIsExplicitlyOneWay(rec) {
  if (!rec || typeof rec !== "object") return false;
  if (_chironBookingRecordHasReturnSignal(rec)) return false;
  const booking = rec?.booking && typeof rec.booking === "object" ? rec.booking : {};
  const quote = rec?.quote && typeof rec.quote === "object" ? rec.quote : {};
  const quoteReturn = quote?.return && typeof quote.return === "object" ? quote.return : {};
  return (
    _chironBoolStrictFalse(rec?.return_enabled) ||
    _chironBoolStrictFalse(booking?.return_enabled) ||
    _chironBoolStrictFalse(quoteReturn?.enabled)
  );
}

function _chironSingleLegTypeFromBookingRecord(rec) {
  if (!rec || typeof rec !== "object") return null;
  // Any booking-level return signal => potential roundtrip (even if the return
  // leg is not materialized yet) => never attribute a legless event to a leg.
  if (_chironBookingRecordHasReturnSignal(rec)) return null;
  const distinct = new Set();
  for (const leg of _chironBookingRecordOperationalLegs(rec)) {
    const t = cleanText(leg.leg_type ?? leg.legType, 64)
      .toLowerCase()
      .replace(/[^a-z0-9_-]/g, "");
    if (t) distinct.add(t);
  }
  // Exactly one distinct leg type and no return signal => single-leg booking.
  if (distinct.size === 1) return [...distinct][0];
  // More than one distinct type without a return signal is contradictory =>
  // stay safe and fall back to the base ritnummer.
  if (distinct.size > 1) return null;
  // No materialized legs: only default to outbound when the record is
  // EXPLICITLY one-way (return_enabled === false). An incomplete/unknown record
  // (no explicit one-way assertion) keeps the base fallback.
  if (_chironBookingRecordIsExplicitlyOneWay(rec)) return "outbound";
  return null;
}

async function _chironLoadBookingLegTypeMap(env, entries) {
  const map = new Map();
  const kv = _chironScopedProfileKv(env);
  if (!kv || !Array.isArray(entries)) return map;
  const wanted = new Set();
  for (const entry of entries) {
    const event = entry?.event;
    if (!event || typeof event !== "object") continue;
    if (_chironEventHasLegScope(event)) continue;
    const bookingId = cleanText(event?.booking_id ?? event?.parent_booking_id, 128);
    if (bookingId) wanted.add(bookingId);
  }
  if (wanted.size === 0) return map;
  await Promise.all(
    [...wanted].map(async (bookingId) => {
      try {
        const rec = await kv.get(`booking:${bookingId}`, { type: "json" });
        const legType = _chironSingleLegTypeFromBookingRecord(rec);
        if (legType) map.set(bookingId, legType);
      } catch (_) {
        // Best-effort: a KV miss/error simply leaves the event on its base
        // ritnummer fallback (existing behavior).
      }
    }),
  );
  return map;
}

function _chironStampResolvedLegTypeOnEntries(entries, legTypeMap) {
  if (!Array.isArray(entries) || !(legTypeMap instanceof Map) || legTypeMap.size === 0) {
    return;
  }
  for (const entry of entries) {
    const event = entry?.event;
    if (!event || typeof event !== "object") continue;
    if (_chironEventHasLegScope(event)) continue;
    const bookingId = cleanText(event?.booking_id ?? event?.parent_booking_id, 128);
    if (!bookingId) continue;
    const legType = legTypeMap.get(bookingId);
    if (!legType) continue;
    // In-memory only; never persisted back to COMPLIANCE_KV. Stamp both
    // snake/camel so every downstream reader sees the resolved leg.
    event.leg_type = legType;
    event.legType = legType;
  }
}

function buildChironExportPayload(event, eventKey, options = {}) {
  const safeEvent =
    event && typeof event === "object" && !Array.isArray(event) ? event : {};
  const built = buildChironDryRunBlueprint(safeEvent);
  const blueprint = built?.blueprint || {};
  const completeness = built?.completeness || { missing: [], warnings: [], score: 0 };
  const ride = blueprint.ride || _chironProjectRide(safeEvent);
  const driver = blueprint.driver || _chironProjectDriver(safeEvent);
  const vehicle = blueprint.vehicle || _chironProjectVehicle(safeEvent);
  const fare = blueprint.fare || _chironProjectFare(safeEvent);
  const payment = blueprint.payment || _chironProjectPayment(safeEvent);
  const refundAudit = projectRefundAuditFields(safeEvent);

  const tenantId = cleanText(safeEvent.tenant_id, 128);
  const companyId = cleanText(safeEvent.company_id, 128);
  const eventId = cleanText(safeEvent.event_id, 200);
  const eventType = cleanText(safeEvent.event_type, 64);
  const createdAtUtc = cleanText(safeEvent.created_at_utc, 64);
  const occurredAtUtc =
    cleanText(blueprint.occurred_at_utc, 64) || _chironResolveOccurredAtUtc(safeEvent);

  const payload = {
    export_version: CHIRON_EXPORT_VERSION,
    source: CHIRON_EXPORT_SOURCE,
    tenant_id: tenantId || null,
    company_id: companyId || null,
    event_id: eventId || null,
    event_key: cleanText(eventKey, 1024) || null,
    event_type: eventType || null,
    booking_id: cleanText(safeEvent.booking_id, 128) || null,
    trip_id: cleanText(safeEvent.trip_id, 128) || null,
    public_booking_reference: ride.public_booking_reference || null,
    created_at_utc: createdAtUtc || null,
    occurred_at_utc: occurredAtUtc || null,
    driver,
    vehicle,
    ride_status:
      cleanText(safeEvent.ride_status ?? safeEvent.lifecycle_status ?? ride.lifecycle_status, 64) ||
      null,
    lifecycle_status: ride.lifecycle_status || null,
    booking_status: ride.booking_status || null,
    payment_status: payment?.status || null,
    payment_method: payment?.method || null,
    refund_status: refundAudit.refund_status || payment?.refund_status || null,
    credit_status: payment?.credit_status || null,
    amount: fare.total_amount ?? payment?.amount ?? null,
    currency: fare.currency ?? payment?.currency ?? null,
    vat_rate: fare.vat_rate ?? null,
    vat_amount: fare.vat_amount ?? null,
    vat_amount_cents: fare.vat_amount_cents ?? null,
    idempotency_key: buildChironExportIdempotencyKey(
      tenantId,
      companyId,
      eventId,
      eventType,
      occurredAtUtc,
    ),
    exportable: completeness.missing.length === 0,
    completeness_score: completeness.score,
    missing: Array.isArray(completeness.missing) ? completeness.missing : [],
    warnings: Array.isArray(completeness.warnings) ? completeness.warnings : [],
  };

  if (options.includeRaw === true) {
    payload.raw_event = projectRecentEvent(cleanText(eventKey, 1024), safeEvent);
  }

  if (options.includeOfficialDraft === true) {
    const scope = {
      tenant_id: tenantId,
      company_id: companyId,
    };
    payload.chiron_official_draft = buildChironOfficialDraftEnvelope(
      safeEvent,
      blueprint,
      scope,
      {
        batchRitStatuses: options.batchRitStatuses || null,
        scopedHydrationCache: options.scopedHydrationCache || null,
        trustedRideHydration: options.trustedRideHydration || null,
      },
    );
  }

  // Chiron Connect 4A0: optional, opt-in inspection of the nested official
  // Chiron Rit API body. Never attached by default so normal export/dry-run
  // responses keep their existing flat shape.
  if (options.includeChironApiPayload === true) {
    const officialDraft = payload.chiron_official_draft;
    const officialPayload =
      officialDraft && typeof officialDraft === "object" ? officialDraft.payload : null;
    if (
      officialDraft &&
      officialDraft.category === "ride_payload" &&
      officialPayload &&
      typeof officialPayload === "object" &&
      !Array.isArray(officialPayload)
    ) {
      payload.chiron_api_payload = buildChironTaxiritApiPayload(officialPayload);
    }
  }

  return payload;
}

async function _chironCollectScopedComplianceEventsForExport(
  env,
  tenantSegment,
  companySegment,
  options,
) {
  const {
    requestedLimit,
    sinceMs = null,
    untilMs = null,
    eventTypeFilterRaw = "",
  } = options;

  const prefix = buildCompliancePrefixForScope(tenantSegment, companySegment);
  let keyNames;
  try {
    keyNames = await listScopedComplianceEventKeys(env, prefix);
  } catch (_) {
    return { error: "Failed to list compliance events." };
  }

  const hitScanCap = keyNames.length >= CHIRON_EXPORT_LIST_SCAN_CAP;
  let malformedCount = 0;
  const parsedEvents = [];

  for (const key of keyNames) {
    let raw;
    try {
      raw = await env.COMPLIANCE_KV.get(key);
    } catch (_) {
      malformedCount += 1;
      continue;
    }
    if (!raw) {
      malformedCount += 1;
      continue;
    }
    try {
      const parsed = JSON.parse(raw);
      if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
        malformedCount += 1;
        continue;
      }
      parsedEvents.push({ key, event: parsed });
    } catch (_) {
      malformedCount += 1;
    }
  }

  const filtered = [];
  for (const entry of parsedEvents) {
    const event = entry.event;
    const eventType = cleanText(event.event_type, 64).toLowerCase();
    if (eventTypeFilterRaw && eventType !== eventTypeFilterRaw) continue;

    const eventTs = _chironEventTimestampMs(event);
    if (sinceMs != null && (eventTs == null || eventTs < sinceMs)) continue;
    if (untilMs != null && (eventTs == null || eventTs > untilMs)) continue;

    filtered.push({ key: entry.key, event, eventTs });
  }

  const sortedFiltered = [...filtered].sort((a, b) => {
    const aTs = a.eventTs;
    const bTs = b.eventTs;
    if (aTs != null && bTs != null && aTs !== bTs) return bTs - aTs;
    if (aTs != null && bTs == null) return -1;
    if (aTs == null && bTs != null) return 1;
    return cleanText(b?.key, 1024).localeCompare(cleanText(a?.key, 1024));
  });

  const matchingEventCount = sortedFiltered.length;
  const limitedEntries = sortedFiltered.slice(0, requestedLimit);
  const hasMoreCandidates = hitScanCap || matchingEventCount > requestedLimit;

  return {
    limitedEntries,
    malformedCount,
    scannedCount: keyNames.length,
    matchingEventCount,
    hasMoreCandidates,
  };
}

// === Chiron-6B-3C: backend readiness-report builder ===

const CHIRON_READINESS_REPORT_SCHEMA_VERSION = "chiron_readiness_report_v1";
const CHIRON_READINESS_TOP_N = 10;
const CHIRON_READINESS_SAMPLE_ISSUE_CAP = 5;

const CHIRON_READINESS_FIELD_GROUPS = [
  {
    group: "business_identity",
    fields: ["registratie", "naam"],
    verificationKeys: ["registration", "business_name"],
    documentKey: "business",
    blockerCodes: [
      "placeholder_registration",
      "placeholder_business_name",
      "invalid_registration_format",
      "invalid_business_name",
      "business_document_expired",
      "business_document_mismatch",
      "business_document_rejected",
    ],
    warningCodes: ["business_document_review_required"],
  },
  {
    group: "vehicle_identity",
    fields: ["kentekenplaat"],
    verificationKeys: ["license_plate"],
    documentKey: "vehicle",
    blockerCodes: [
      "placeholder_license_plate",
      "invalid_license_plate_format",
      "invalid_flemish_taxi_plate",
      "vehicle_document_expired",
      "vehicle_document_mismatch",
      "vehicle_document_rejected",
    ],
    warningCodes: [
      "vehicle_document_review_required",
      "taxi_plate_pattern_not_confirmed",
      "taxi_plate_exception_requires_review",
    ],
  },
  {
    group: "driver_identity",
    fields: ["bestuurderspasnummer"],
    verificationKeys: ["driver_pass"],
    documentKey: "driver_pass",
    blockerCodes: [
      "placeholder_driver_pass",
      "invalid_driver_pass_format",
      "driver_pass_document_expired",
      "driver_pass_document_mismatch",
      "driver_pass_document_rejected",
    ],
    warningCodes: ["driver_pass_document_review_required"],
  },
  {
    group: "ride_geometry",
    fields: [
      "vertrekpunt_lengtegraad",
      "vertrekpunt_breedtegraad",
      "aankomstpunt_lengtegraad",
      "aankomstpunt_breedtegraad",
      "afstand",
    ],
    verificationKeys: [],
    documentKey: null,
    blockerCodes: ["invalid_zero_coordinate_pair"],
    warningCodes: [],
  },
  {
    group: "sequence",
    fields: ["status"],
    verificationKeys: [],
    documentKey: null,
    blockerCodes: [],
    warningCodes: ["missing_prior_vertrek_or_reservatie_in_batch"],
  },
  {
    group: "registry",
    fields: [],
    verificationKeys: [],
    documentKey: null,
    blockerCodes: [],
    warningCodes: [],
  },
  {
    group: "documents",
    fields: [],
    verificationKeys: [],
    documentKey: null,
    blockerCodes: [],
    warningCodes: [],
  },
];

const CHIRON_READINESS_NEXT_ACTIONS = {
  placeholder_registration:
    "Vervang het test-/demo-ondernemingsnummer door het officiële KBO-nummer van de exploitant.",
  invalid_registration_format:
    "Corrigeer het ondernemingsnummer: het moet een geldig Belgisch KBO-nummer zijn (10 cijfers, beginnend met 0 of 1).",
  placeholder_business_name:
    "Vervang de test-/demo-bedrijfsnaam door de officiële bedrijfsnaam.",
  invalid_business_name:
    "Vul een geldige officiële bedrijfsnaam in.",
  placeholder_license_plate:
    "Vervang het demo-kenteken door het echte nummerplaat van het voertuig.",
  invalid_license_plate_format:
    "Corrigeer het kenteken: gebruik het officiële plaatformaat.",
  invalid_flemish_taxi_plate:
    "Controleer of dit voertuig een geldig Vlaams taxi/T-X kenteken of een goedgekeurde uitzondering heeft.",
  taxi_plate_pattern_not_confirmed:
    "Bevestig of dit voertuig in dit regime een T-X taxi-kenteken hoort te hebben of leg de uitzondering vast.",
  taxi_plate_exception_requires_review:
    "Laat het uitzonderingsdocument voor dit kenteken nakijken en goedkeuren.",
  placeholder_driver_pass:
    "Vul het officiële bestuurderspasnummer in en laat het document controleren.",
  invalid_driver_pass_format:
    "Corrigeer het bestuurderspasnummer: gebruik het officiële formaat.",
  invalid_zero_coordinate_pair:
    "Controleer de GPS/ritregistratie: vertrek- of aankomstcoördinaten zijn 0/0.",
  vertrekpunt_lengtegraad:
    "Controleer de GPS-registratie: vertrekpunt-lengtegraad ontbreekt of is ongeldig.",
  vertrekpunt_breedtegraad:
    "Controleer de GPS-registratie: vertrekpunt-breedtegraad ontbreekt of is ongeldig.",
  aankomstpunt_lengtegraad:
    "Controleer de GPS-registratie: aankomstpunt-lengtegraad ontbreekt of is ongeldig.",
  aankomstpunt_breedtegraad:
    "Controleer de GPS-registratie: aankomstpunt-breedtegraad ontbreekt of is ongeldig.",
  afstand:
    "Controleer de ritafstand: aankomstritten moeten een afstand groter dan 0 hebben.",
  kostprijs:
    "Controleer de ritprijs: de officiële Chiron-prijs ontbreekt.",
  vertrektijdstip:
    "Controleer de vertrek-tijdstempel van de rit.",
  aankomsttijdstip:
    "Controleer de aankomst-tijdstempel van de rit.",
  ritnummer:
    "Controleer of de rit een unieke ritreferentie heeft.",
  broncreatiedatum:
    "Controleer de aanmaakdatum van het bronregistratie-event.",
  driver_pass_document_review_required:
    "Upload of controleer het bestuurderspasdocument.",
  driver_pass_document_expired:
    "Het bestuurderspasdocument is verlopen — vernieuw het document.",
  driver_pass_document_mismatch:
    "Het pasnummer in het bestuurdersdocument komt niet overeen met de geregistreerde rit.",
  driver_pass_document_rejected:
    "Het bestuurderspasdocument is afgewezen — verifieer en upload een geldig document.",
  vehicle_document_review_required:
    "Upload of controleer voertuig-/taxivergunningsdocumenten.",
  vehicle_document_expired:
    "Het voertuig-/taxivergunningsdocument is verlopen — vernieuw het document.",
  vehicle_document_mismatch:
    "Het kenteken op het voertuigdocument komt niet overeen met de geregistreerde rit.",
  vehicle_document_rejected:
    "Het voertuig-/taxivergunningsdocument is afgewezen — verifieer en upload een geldig document.",
  business_document_review_required:
    "Controleer ondernemingsdocumenten of KBO-bewijs.",
  business_document_expired:
    "Het ondernemingsdocument is verlopen — vernieuw het document.",
  business_document_mismatch:
    "Het nummer op het ondernemingsdocument komt niet overeen met de geregistreerde rit.",
  business_document_rejected:
    "Het ondernemingsdocument is afgewezen — verifieer en upload een geldig document.",
  missing_prior_vertrek_or_reservatie_in_batch:
    "Controleer de volgorde: reservatie en vertrek moeten vóór aankomst beschikbaar zijn.",
};

function _chironReadinessNextActionForIssue(code) {
  if (!code) return null;
  if (CHIRON_READINESS_NEXT_ACTIONS[code]) return CHIRON_READINESS_NEXT_ACTIONS[code];
  if (/^placeholder_/.test(code)) {
    return "Vervang test-/demo-data door echte officiële waarde.";
  }
  if (/_document_review_required$/.test(code)) {
    return "Upload of controleer het ondersteunende document.";
  }
  if (/_document_expired$/.test(code)) {
    return "Het document is verlopen — vernieuw het document.";
  }
  if (/_document_mismatch$/.test(code)) {
    return "Document-nummer komt niet overeen met de registratie — verifieer.";
  }
  if (/_document_rejected$/.test(code)) {
    return "Document is afgewezen — verifieer en upload een geldig document.";
  }
  return "Controleer dit veld voor officiële Chiron-rapportering.";
}

function _chironReadinessIsRideGeometryFieldCode(code) {
  return [
    "vertrekpunt_lengtegraad",
    "vertrekpunt_breedtegraad",
    "aankomstpunt_lengtegraad",
    "aankomstpunt_breedtegraad",
    "afstand",
    "kostprijs",
    "vertrektijdstip",
    "aankomsttijdstip",
    "ritnummer",
    "broncreatiedatum",
  ].includes(code);
}

function _chironReadinessGroupForIssue(code) {
  if (!code) return null;
  for (const grp of CHIRON_READINESS_FIELD_GROUPS) {
    if (grp.blockerCodes.includes(code) || grp.warningCodes.includes(code)) return grp.group;
  }
  if (_chironReadinessIsRideGeometryFieldCode(code)) return "ride_geometry";
  return null;
}

function _chironClassifyReadinessBucket(draft) {
  if (!draft || typeof draft !== "object") return "not_applicable";
  if (draft.category === "not_chiron_ride_status") return "not_applicable";
  const validation = draft.validation || {};
  const verification = draft.verification || {};
  if (validation.status === "blocker") return "blocked";
  const warnings = Array.isArray(validation.warnings) ? validation.warnings : [];
  const sequenceUnsafe = validation.sequence_safe === false;
  const overall = cleanText(verification.overall_status, 32);
  if (
    warnings.length > 0 ||
    sequenceUnsafe ||
    overall === "required_review" ||
    overall === "missing" ||
    overall === "blocked"
  ) {
    return "required_review";
  }
  if (overall === "verified" && validation.status === "ready") {
    return "ready_for_chiron_test";
  }
  return "format_valid";
}

function _chironReadinessOverallStatus(summary) {
  if (!summary) return "not_applicable";
  if (summary.blocked_count > 0) return "blocked";
  if (summary.review_required_count > 0) return "required_review";
  if (summary.format_valid_count > 0 && summary.official_ready_count === 0) return "format_valid";
  if (summary.official_ready_count > 0 && summary.blocked_count === 0) return "ready_for_chiron_test";
  return "not_applicable";
}

function _chironReadinessEmptyAccumulator() {
  const acc = {
    bucketCounts: {
      blocked: 0,
      required_review: 0,
      format_valid: 0,
      ready_for_chiron_test: 0,
      not_applicable: 0,
    },
    officialRideCount: 0,
    sequenceUnsafeCount: 0,
    blockerCounts: new Map(),
    warningCounts: new Map(),
    sourceCounts: {},
    verificationStatusCounts: {},
    documentStatusCounts: {},
    sampleIssues: [],
    seenSampleCodes: new Set(),
  };
  for (const grp of CHIRON_READINESS_FIELD_GROUPS) {
    acc.sourceCounts[grp.group] = {};
    acc.verificationStatusCounts[grp.group] = {};
    if (grp.documentKey) {
      acc.documentStatusCounts[grp.group] = {};
    }
  }
  return acc;
}

function _chironReadinessIncCount(map, key) {
  if (!key) return;
  map.set(key, (map.get(key) || 0) + 1);
}

function _chironReadinessIncObj(obj, scope, key) {
  if (!scope || !key) return;
  if (!obj[scope]) obj[scope] = {};
  obj[scope][key] = (obj[scope][key] || 0) + 1;
}

function _chironReadinessAccumulateDraft(acc, payload) {
  const draft = payload?.chiron_official_draft;
  if (!draft) return;
  const bucket = _chironClassifyReadinessBucket(draft);
  acc.bucketCounts[bucket] = (acc.bucketCounts[bucket] || 0) + 1;

  if (bucket === "not_applicable") return;
  acc.officialRideCount += 1;

  const validation = draft.validation || {};
  const verification = draft.verification || {};
  const documentChecks = verification.document_checks || {};

  // Per-group: source, verification status, document status.
  for (const grp of CHIRON_READINESS_FIELD_GROUPS) {
    for (const vkey of grp.verificationKeys) {
      const field = verification?.[vkey];
      if (field && typeof field === "object") {
        _chironReadinessIncObj(
          acc.sourceCounts,
          grp.group,
          cleanText(field.source, 64) || "unknown",
        );
        _chironReadinessIncObj(
          acc.verificationStatusCounts,
          grp.group,
          cleanText(field.status, 64) || "unknown",
        );
      }
    }
    if (grp.documentKey) {
      const docStatus = cleanText(documentChecks?.[grp.documentKey], 64) || "not_available";
      _chironReadinessIncObj(acc.documentStatusCounts, grp.group, docStatus);
    }
  }

  // Sequence-safe accounting.
  if (validation.sequence_safe === false) acc.sequenceUnsafeCount += 1;

  // Blocker and missing codes contribute to blockerCounts.
  const errors = Array.isArray(validation.errors) ? validation.errors : [];
  for (const code of errors) {
    _chironReadinessIncCount(acc.blockerCounts, code);
    _chironMaybeAddSampleIssue(acc, payload, draft, code);
  }
  const missing = Array.isArray(validation.missing) ? validation.missing : [];
  for (const code of missing) {
    _chironReadinessIncCount(acc.blockerCounts, code);
    _chironMaybeAddSampleIssue(acc, payload, draft, code);
  }
  const warnings = Array.isArray(validation.warnings) ? validation.warnings : [];
  for (const code of warnings) {
    _chironReadinessIncCount(acc.warningCounts, code);
  }
}

function _chironMaybeAddSampleIssue(acc, payload, draft, code) {
  if (!code || acc.sampleIssues.length >= CHIRON_READINESS_SAMPLE_ISSUE_CAP) return;
  if (acc.seenSampleCodes.has(code)) return;
  acc.sampleIssues.push({
    issue: code,
    booking_id: cleanText(payload?.booking_id, 128) || null,
    event_type: cleanText(payload?.event_type, 64) || null,
    official_status: cleanText(draft?.status, 32) || null,
  });
  acc.seenSampleCodes.add(code);
}

function _chironReadinessGroupSnapshot(acc, grp) {
  const blockers = [];
  const warnings = [];
  const seenBlockers = new Set();
  const seenWarnings = new Set();
  for (const code of grp.blockerCodes) {
    const count = acc.blockerCounts.get(code);
    if (count && !seenBlockers.has(code)) {
      blockers.push({
        code,
        count,
        next_action: _chironReadinessNextActionForIssue(code),
      });
      seenBlockers.add(code);
    }
  }
  if (grp.group === "ride_geometry") {
    for (const fieldCode of grp.fields) {
      const count = acc.blockerCounts.get(fieldCode);
      if (count && !seenBlockers.has(fieldCode)) {
        blockers.push({
          code: fieldCode,
          count,
          next_action: _chironReadinessNextActionForIssue(fieldCode),
        });
        seenBlockers.add(fieldCode);
      }
    }
  }
  for (const code of grp.warningCodes) {
    const count = acc.warningCounts.get(code);
    if (count && !seenWarnings.has(code)) {
      warnings.push({
        code,
        count,
        next_action: _chironReadinessNextActionForIssue(code),
      });
      seenWarnings.add(code);
    }
  }

  let status = "format_valid";
  if (grp.group === "registry") {
    status = "missing";
  } else if (blockers.length > 0) {
    status = "blocked";
  } else if (warnings.length > 0) {
    status = "required_review";
  } else if (grp.group === "documents") {
    const docCounts = acc.documentStatusCounts || {};
    const allDocStatuses = new Set();
    for (const groupKey of Object.keys(docCounts)) {
      for (const docStatus of Object.keys(docCounts[groupKey] || {})) {
        allDocStatuses.add(docStatus);
      }
    }
    if (
      allDocStatuses.has("rejected") ||
      allDocStatuses.has("expired") ||
      allDocStatuses.has("mismatch")
    ) {
      status = "blocked";
    } else if (allDocStatuses.has("review_required")) {
      status = "required_review";
    } else if (allDocStatuses.size === 0 || (allDocStatuses.size === 1 && allDocStatuses.has("not_available"))) {
      status = "missing";
    } else if (allDocStatuses.has("not_available")) {
      // mix of verified + not_available
      status = "required_review";
    } else if (allDocStatuses.has("verified") && allDocStatuses.size === 1) {
      status = "verified";
    } else {
      status = "required_review";
    }
  } else if (grp.group === "sequence") {
    status = acc.sequenceUnsafeCount > 0 ? "required_review" : "format_valid";
  } else if (grp.verificationKeys.length > 0) {
    // For business/vehicle/driver identity groups: upgrade to "verified" only when
    // every observed verification status is one of the trusted verified labels.
    const statusBag = acc.verificationStatusCounts[grp.group] || {};
    const keys = Object.keys(statusBag);
    const trusted = new Set([
      "document_verified",
      "registry_verified",
      "chiron_test_verified",
    ]);
    if (keys.length > 0 && keys.every((k) => trusted.has(k))) {
      status = "verified";
    }
  }

  const nextActions = [];
  for (const b of blockers) if (b.next_action && !nextActions.includes(b.next_action)) nextActions.push(b.next_action);
  for (const w of warnings) if (w.next_action && !nextActions.includes(w.next_action)) nextActions.push(w.next_action);

  return {
    group: grp.group,
    status,
    fields: [...grp.fields],
    source_counts: acc.sourceCounts[grp.group] || {},
    verification_status_counts: acc.verificationStatusCounts[grp.group] || {},
    document_status_counts: grp.documentKey ? acc.documentStatusCounts[grp.group] || {} : {},
    blockers,
    warnings,
    next_actions: nextActions,
  };
}

function _chironReadinessTopIssues(map, severity, limit) {
  const entries = [];
  for (const [code, count] of map.entries()) {
    entries.push({
      code,
      count,
      severity,
      field_group: _chironReadinessGroupForIssue(code),
      next_action: _chironReadinessNextActionForIssue(code),
    });
  }
  entries.sort((a, b) => b.count - a.count || a.code.localeCompare(b.code));
  return entries.slice(0, limit);
}

function buildChironReadinessReport(
  tenantId,
  companyId,
  payloads,
  scannedCount,
  processedCount,
) {
  const acc = _chironReadinessEmptyAccumulator();
  for (const payload of payloads) {
    _chironReadinessAccumulateDraft(acc, payload);
  }

  const summary = {
    official_ready_count: acc.bucketCounts.ready_for_chiron_test,
    blocked_count: acc.bucketCounts.blocked,
    review_required_count: acc.bucketCounts.required_review,
    format_valid_count: acc.bucketCounts.format_valid,
    not_applicable_count: acc.bucketCounts.not_applicable,
    sequence_unsafe_count: acc.sequenceUnsafeCount,
  };

  const fieldGroups = CHIRON_READINESS_FIELD_GROUPS.map((grp) =>
    _chironReadinessGroupSnapshot(acc, grp),
  );

  const topBlockers = _chironReadinessTopIssues(acc.blockerCounts, "blocker", CHIRON_READINESS_TOP_N);
  const topWarnings = _chironReadinessTopIssues(acc.warningCounts, "warning", CHIRON_READINESS_TOP_N);

  // Aggregate next-actions in priority order (blocker first).
  const nextActions = [];
  for (const issue of topBlockers) {
    if (issue.next_action && !nextActions.includes(issue.next_action)) {
      nextActions.push(issue.next_action);
    }
  }
  for (const issue of topWarnings) {
    if (issue.next_action && !nextActions.includes(issue.next_action)) {
      nextActions.push(issue.next_action);
    }
  }

  const overallStatus = _chironReadinessOverallStatus(summary);

  return {
    schema_version: CHIRON_READINESS_REPORT_SCHEMA_VERSION,
    generated_at_utc: new Date().toISOString(),
    tenant_id: tenantId || null,
    company_id: companyId || null,
    dry_run: true,
    official_submission_performed: false,
    registry_checks_performed: false,
    document_registry_checks_performed: false,
    overall_status: overallStatus,
    processed_count: processedCount,
    scanned_count: scannedCount,
    summary,
    field_groups: fieldGroups,
    top_blockers: topBlockers,
    top_warnings: topWarnings,
    next_actions: nextActions,
    sample_issues: acc.sampleIssues,
    policy_notes: [
      "Geen officiële Chiron-submit uitgevoerd.",
      "KBO/VIES/registry checks niet uitgevoerd.",
      "Velden met document_verified zijn alleen gebaseerd op expliciete interne trust-markers.",
    ],
  };
}

async function _chironBuildExportDryRunPayloadResponse(
  tenantId,
  companyId,
  limit,
  collectResult,
  includeRaw,
  includeOfficialDraft = false,
  env = null,
  options = {},
) {
  const includeReadinessReport = options?.includeReadinessReport === true;
  // Internally enable official-draft generation when readiness report is requested,
  // so we can classify every payload without expanding the visible response shape.
  const effectiveIncludeOfficialDraft = includeOfficialDraft || includeReadinessReport;

  const scope = { tenant_id: tenantId, company_id: companyId };
  const scopedHydrationCache = await _chironLoadScopedHydrationCache(
    env,
    scope,
    effectiveIncludeOfficialDraft,
  );
  if (effectiveIncludeOfficialDraft) {
    // Stamp resolved operational-leg type onto legless events BEFORE building
    // the rit-status / trusted-ride indexes so departure and arrival of the
    // same leg derive the same leg-scoped ritnummer.
    const legTypeMap = await _chironLoadBookingLegTypeMap(env, collectResult.limitedEntries);
    _chironStampResolvedLegTypeOnEntries(collectResult.limitedEntries, legTypeMap);
  }
  const batchRitStatuses = effectiveIncludeOfficialDraft
    ? _chironBuildBatchRitStatusIndex(collectResult.limitedEntries)
    : null;
  const trustedRideHydration = effectiveIncludeOfficialDraft
    ? _chironBuildBatchTrustedRideHydrationIndex(collectResult.limitedEntries)
    : null;
  const payloads = collectResult.limitedEntries.map((entry) =>
    buildChironExportPayload(entry.event, entry.key, {
      includeRaw,
      includeOfficialDraft: effectiveIncludeOfficialDraft,
      batchRitStatuses,
      scopedHydrationCache,
      trustedRideHydration,
    }),
  );
  const exportableCount = payloads.filter((payload) => payload.exportable).length;

  // Build readiness report from the full payload set BEFORE stripping any drafts.
  const readinessReport = includeReadinessReport
    ? buildChironReadinessReport(
        tenantId,
        companyId,
        payloads,
        collectResult.scannedCount,
        payloads.length,
      )
    : null;

  // If the official draft was only enabled internally for the report, strip it from
  // the visible payloads so existing dry-run clients see no shape change.
  const visiblePayloads =
    effectiveIncludeOfficialDraft && !includeOfficialDraft
      ? payloads.map((p) => {
          const { chiron_official_draft, ...rest } = p;
          void chiron_official_draft;
          return rest;
        })
      : payloads;

  const sampleCandidates = [
    ...visiblePayloads.filter((payload) => payload.exportable),
    ...visiblePayloads.filter((payload) => !payload.exportable),
  ];
  const samplePayloads = sampleCandidates.slice(0, CHIRON_EXPORT_MAX_SAMPLE_PAYLOADS);

  const response = {
    ok: true,
    dry_run: true,
    tenant_id: tenantId,
    company_id: companyId,
    limit,
    scanned_count: collectResult.scannedCount,
    processed_count: payloads.length,
    exportable_count: exportableCount,
    non_exportable_count: payloads.length - exportableCount,
    malformed_count: collectResult.malformedCount,
    has_more_candidates: collectResult.hasMoreCandidates,
    sample_payloads: samplePayloads,
  };
  if (readinessReport) response.readiness_report = readinessReport;
  return response;
}

// RELEASE-P0-OFFICIAL-CHIRON-OAUTH-SUBMIT-2026-07-31: duplicate-submit guard.
// Chiron rejects duplicate rides in acceptance; both admin submit endpoints
// must consult previousStatus BEFORE any OAuth or taxirit call. Returns:
//   { decision: "allow" }                — first attempt OR previous was
//                                          definitive failure OK to retry
//   { decision: "already_synced" }       — event was accepted; return an
//                                          idempotent HTTP 200 without
//                                          re-POSTing to Chiron; never
//                                          increment attempt_count
//   { decision: "conflict_pending" }     — an in-flight submit exists; do
//                                          not race a second POST
//   { decision: "verification_required" }— previous attempt hit an ambiguous
//                                          transport failure; operator MUST
//                                          resolve via the portaal first
//   { decision: "not_retryable" }        — a prior failure whose cause is
//                                          unclear; blocks automatic retry
function _chironEvaluateSubmitDuplicateGuard(previousStatus) {
  if (!previousStatus || typeof previousStatus !== "object") {
    return { decision: "allow" };
  }
  const state = cleanText(previousStatus.sync_state, 32).toLowerCase();
  if (state === "synced") {
    return { decision: "already_synced" };
  }
  if (state === "pending") {
    return { decision: "conflict_pending" };
  }
  if (state === "verification_required") {
    return { decision: "verification_required" };
  }
  if (state === "failed") {
    // Retry only for a definitively failed prior attempt:
    //   - explicit definitive marker; OR
    //   - a Chiron HTTP response received (2xx with fouten[] > 0 or non-2xx);
    //     that means we KNOW Chiron rejected/never accepted the message.
    // A prior transport failure without HTTP response is still ambiguous and
    // gets promoted to `verification_required` at write time — but if an
    // older status doc lacks the marker, we conservatively block retries.
    if (previousStatus.failure_kind === "definitive") {
      return { decision: "allow" };
    }
    const httpStatus = Number(previousStatus.external_status_code);
    const foutenCount = Number(previousStatus.fouten_count);
    const gotChironResponse =
      Number.isFinite(httpStatus) && httpStatus > 0 &&
      (httpStatus < 200 || httpStatus >= 300 ||
       (Number.isFinite(foutenCount) && foutenCount > 0));
    if (gotChironResponse) {
      return { decision: "allow" };
    }
    // Ambiguous or unknown-cause prior failure → block automatic retry.
    return { decision: "not_retryable" };
  }
  // Unknown states are treated as blocking (fail-closed).
  return { decision: "not_retryable" };
}

async function _chironReadExportStatus(env, statusKey) {
  if (!env?.COMPLIANCE_KV || typeof env.COMPLIANCE_KV.get !== "function") return null;
  try {
    const raw = await env.COMPLIANCE_KV.get(statusKey);
    if (!raw) return null;
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return null;
    return parsed;
  } catch (_) {
    return null;
  }
}

async function _chironWriteExportStatus(env, statusKey, statusDoc) {
  if (!env?.COMPLIANCE_KV || typeof env.COMPLIANCE_KV.put !== "function") {
    return { ok: false, reason: "missing_kv" };
  }
  try {
    await env.COMPLIANCE_KV.put(statusKey, JSON.stringify(statusDoc));
    return { ok: true };
  } catch (_) {
    return { ok: false, reason: "kv_put_failed" };
  }
}

// Chiron Connect 4A0: numeric coercion helpers for the official Rit API body.
// Coordinates stay raw numbers; afstand/kostprijs are rounded to the decimal
// precision the Chiron technical manual r3.0 expects.
function _chironApiNumber(value) {
  if (value === null || value === undefined || value === "") return null;
  const num = Number(value);
  return Number.isFinite(num) ? num : null;
}

function _chironApiRoundedNumber(value, maxDecimals) {
  const num = _chironApiNumber(value);
  if (num === null) return null;
  const factor = Math.pow(10, maxDecimals);
  return Math.round(num * factor) / factor;
}

// Chiron Connect 4A0: serialize the deliberately flat internal
// officialDraft.payload into the nested official Chiron Rit API JSON body
// (technical manual r3.0). The internal payload stays flat on purpose; this
// is the only place that knows the nested wire shape. Null/undefined fields
// are never emitted. Returns null when the payload is not a serializable
// reservatie/vertrek/aankomst ride status.
function buildChironTaxiritApiPayload(officialPayload) {
  if (
    !officialPayload ||
    typeof officialPayload !== "object" ||
    Array.isArray(officialPayload)
  ) {
    return null;
  }

  const status = cleanText(officialPayload.status, 32);
  if (!["reservatie", "vertrek", "aankomst"].includes(status)) {
    return null;
  }

  const ritnummer = cleanText(officialPayload.ritnummer, 256);
  const registratieDisplay = cleanText(officialPayload.registratie, 64);
  const naam = cleanText(officialPayload.naam, 256);
  const broncreatiedatum = cleanText(officialPayload.broncreatiedatum, 64);

  // RELEASE-P0-CHIRON-REGISTRATION-KBO-CANONICAL-2026-07-31: emit digits-only
  // KBO on the wire to match the OAuth-authenticated subject. Fail-closed
  // when the display form can't be normalized to exactly 10 digits so we
  // never ship a body Chiron will reject with a KBO mismatch fout.
  let registratieWire = null;
  if (registratieDisplay) {
    registratieWire = chironOfficialRegistratieWire(registratieDisplay);
    if (!registratieWire) return null;
  }

  const aanbieder = {};
  if (registratieWire) aanbieder.registratie = registratieWire;
  if (naam) aanbieder.naam = naam;

  const rit = {
    taxibedrijf: {
      aanbieder,
    },
  };

  const body = {};
  if (status) body.status = status;
  if (ritnummer) body.ritnummer = ritnummer;
  body.rit = rit;
  if (broncreatiedatum) body.broncreatiedatum = broncreatiedatum;

  if (status === "vertrek" || status === "aankomst") {
    // RELEASE-P0-CHIRON-LICENSE-PLATE-WIRE-2026-07-31: canonicalize the
    // license plate at the wire-serializer just before the taxirit-POST.
    // Chiron requires `[A-Z0-9]` only; fail-closed when a non-empty
    // display plate can't be stripped to at least one alphanumeric
    // character so we never emit a body Chiron will reject with CH1212.
    const nummerplaatDisplay = cleanText(officialPayload.kentekenplaat, 32);
    let nummerplaat = null;
    if (nummerplaatDisplay) {
      nummerplaat = chironOfficialKentekenplaatWire(nummerplaatDisplay);
      if (!nummerplaat) return null;
    }
    const bestuurderspasnummer = cleanText(officialPayload.bestuurderspasnummer, 64);
    const vertrektijdstip = cleanText(officialPayload.vertrektijdstip, 64);
    const vLng = _chironApiNumber(officialPayload.vertrekpunt_lengtegraad);
    const vLat = _chironApiNumber(officialPayload.vertrekpunt_breedtegraad);

    if (nummerplaat) rit.voertuig = { nummerplaat };
    if (bestuurderspasnummer) rit.uitvoerder = { bestuurderspasnummer };
    if (vertrektijdstip) rit.vertrektijdstip = vertrektijdstip;
    if (vLng !== null || vLat !== null) {
      rit.vertrekpunt = {};
      if (vLng !== null) rit.vertrekpunt.lengtegraad = vLng;
      if (vLat !== null) rit.vertrekpunt.breedtegraad = vLat;
    }

    // Chiron 4A0: kostprijs is optional for vertrek; only attach when present.
    if (status === "vertrek") {
      const kostprijs = _chironApiRoundedNumber(officialPayload.kostprijs, 2);
      if (kostprijs !== null) rit.kostprijs = { waarde: kostprijs };
    }
  }

  if (status === "aankomst") {
    const aankomsttijdstip = cleanText(officialPayload.aankomsttijdstip, 64);
    const aLng = _chironApiNumber(officialPayload.aankomstpunt_lengtegraad);
    const aLat = _chironApiNumber(officialPayload.aankomstpunt_breedtegraad);
    const afstand = _chironApiRoundedNumber(officialPayload.afstand, 3);
    const kostprijs = _chironApiRoundedNumber(officialPayload.kostprijs, 2);

    if (aankomsttijdstip) rit.aankomsttijdstip = aankomsttijdstip;
    if (aLng !== null || aLat !== null) {
      rit.aankomstpunt = {};
      if (aLng !== null) rit.aankomstpunt.lengtegraad = aLng;
      if (aLat !== null) rit.aankomstpunt.breedtegraad = aLat;
    }
    if (afstand !== null) rit.afstand = { waarde: afstand };
    if (kostprijs !== null) rit.kostprijs = { waarde: kostprijs };
  }

  return body;
}

// Chiron Connect 4A0: interpret a submit response. The official Chiron Rit API
// can return HTTP 200 with a `fouten` array; a non-empty array is a rejection,
// not a success. Stays backward compatible with the internal test receiver
// (no `fouten` field) via response_shape. Never surfaces tokens/secrets.
function parseChironTaxiritSubmitResponse(httpStatus, responseBody) {
  const parsedStatus = Number(httpStatus);
  const statusCode = Number.isFinite(parsedStatus) ? parsedStatus : null;
  const httpOk = statusCode !== null && statusCode >= 200 && statusCode < 300;

  const bodyIsObject =
    responseBody && typeof responseBody === "object" && !Array.isArray(responseBody);
  const hasFoutenArray = bodyIsObject && Array.isArray(responseBody.fouten);
  const foutenCount = hasFoutenArray ? responseBody.fouten.length : 0;
  const responseShape = hasFoutenArray
    ? "chiron_taxirit_api_v1"
    : "non_chiron_test_receiver";

  const externalReference = _chironExtractExternalReference(responseBody);
  const bodyMessage = bodyIsObject
    ? cleanText(responseBody.message ?? responseBody.error, 256)
    : "";

  if (!httpOk) {
    return {
      ok: false,
      response_shape: responseShape,
      external_status_code: statusCode,
      external_reference: externalReference,
      fouten_count: foutenCount,
      sanitized_error: _chironSanitizeExportError(
        bodyMessage || `HTTP ${statusCode ?? "error"}`,
      ),
    };
  }

  if (hasFoutenArray && foutenCount > 0) {
    return {
      ok: false,
      response_shape: responseShape,
      external_status_code: statusCode,
      external_reference: externalReference,
      fouten_count: foutenCount,
      sanitized_error: "chiron_response_contains_errors",
    };
  }

  // RELEASE-P0-OFFICIAL-CHIRON-OAUTH-SUBMIT-2026-07-31: 2xx alone is NEVER
  // proof of Chiron acceptance. To be counted as synced the response body
  // MUST parse as a valid JSON object AND MUST carry a `fouten` array (the
  // official Rit API v1 contract). Anything else — no body, non-JSON,
  // unexpected shape — is classified as NOT synced so tracking cannot flip
  // to APPLIED against an unproven acceptance.
  if (!hasFoutenArray) {
    return {
      ok: false,
      response_shape: responseShape,
      external_status_code: statusCode,
      external_reference: externalReference,
      fouten_count: 0,
      sanitized_error: "chiron_response_shape_unexpected",
    };
  }

  return {
    ok: true,
    response_shape: responseShape,
    external_status_code: statusCode,
    external_reference: externalReference,
    fouten_count: foutenCount,
    sanitized_error: null,
  };
}

// RELEASE-P0-OFFICIAL-CHIRON-OAUTH-SUBMIT-2026-07-31:
//
// The official Chiron taxirit POST now REQUIRES a caller-supplied OAuth2
// access_token (via `options.accessToken`). The legacy static
// `CHIRON_EXPORT_API_TOKEN` env var is NO LONGER accepted as the official
// authentication bearer — it exists in this worker only as an infrastructure
// gate (`chironExportTestModeEnabled`) that keeps the taxirit-POST path off
// entirely when unset. The bearer we actually put on the wire is always the
// per-company OAuth-derived token from
// `_chironAcquireOAuthAccessTokenForSubmit`.
//
// The fetch is bounded by `CHIRON_TAXIRIT_SUBMIT_TIMEOUT_MS` via an
// AbortController so a hung Chiron ACC connection can't ride out the
// worker's 30s CPU/wall-clock limit ambiguously. A transport failure
// AFTER the fetch has been initiated is classified as `ambiguous: true`
// (see `sanitized_error === "chiron_transport_ambiguous"`) so the caller
// can flip the local sync_state to "verification_required" instead of
// treating it as a plain retryable failure.
const CHIRON_TAXIRIT_SUBMIT_TIMEOUT_MS = 10000;
async function _chironPostChironExportTestPayload(env, payload, options = {}) {
  const baseUrl = cleanText(env?.CHIRON_EXPORT_BASE_URL, 512).replace(/\/+$/, "");
  if (!baseUrl) {
    return {
      ok: false,
      error: "chiron_export_test_mode_disabled",
      sanitized_error: "chiron_export_test_mode_disabled",
      ambiguous: false,
    };
  }
  const accessToken =
    typeof options.accessToken === "string" ? options.accessToken.trim() : "";
  if (!accessToken) {
    // Pre-fetch failure: no bearer, no request goes out. Safely retryable
    // once OAuth is fixed. NEVER falls back to CHIRON_EXPORT_API_TOKEN.
    return {
      ok: false,
      error: "missing_oauth_access_token",
      sanitized_error: "missing_oauth_access_token",
      ambiguous: false,
    };
  }

  const requestedTimeout = Number(options.timeoutMs);
  const timeoutMs = Number.isFinite(requestedTimeout) && requestedTimeout > 0
    ? Math.min(30000, Math.max(1000, Math.round(requestedTimeout)))
    : CHIRON_TAXIRIT_SUBMIT_TIMEOUT_MS;

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  let response;
  let fetchStarted = true;
  try {
    response = await fetch(baseUrl, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${accessToken}`,
      },
      body: JSON.stringify(payload),
      signal: controller.signal,
    });
  } catch (err) {
    clearTimeout(timer);
    // Transport failure AFTER fetch was initiated: we cannot prove Chiron
    // didn't receive the message. Report `ambiguous: true` so the handler
    // flips sync_state to verification_required and refuses automatic
    // retries until an operator resolves it against the Chiron portaal.
    const isAbort = err && err.name === "AbortError";
    return {
      ok: false,
      response_shape: null,
      external_status_code: null,
      external_reference: null,
      fouten_count: 0,
      sanitized_error: "chiron_transport_ambiguous",
      transport_error_kind: isAbort ? "timeout" : "network",
      ambiguous: fetchStarted,
    };
  }
  clearTimeout(timer);

  let responseBody = null;
  const contentType = cleanText(response.headers.get("content-type"), 128).toLowerCase();
  if (contentType.includes("application/json")) {
    try {
      responseBody = await response.json();
    } catch (_) {
      responseBody = null;
    }
  }

  // Chiron Connect 4A0: ok/error is decided by parseChironTaxiritSubmitResponse
  // so that a HTTP 200 carrying a non-empty `fouten` array is treated as a
  // rejection rather than a successful submit. Ambiguity is only produced by
  // transport failures above; once we have any HTTP response, the outcome is
  // definitive and NOT verification_required.
  const parsed = parseChironTaxiritSubmitResponse(response.status, responseBody);
  return { ...parsed, ambiguous: false };
}

function parseChironTestflowSubmitOneInput(body) {
  const scope = parseChironExportScopeFromBody(body);
  if (scope.error) return { error: scope.error };

  const eventId = cleanText(body?.event_id, 200);
  const complianceEventKey = cleanText(body?.compliance_event_key, 1024);
  if (!eventId && !complianceEventKey) {
    return { error: "missing_event_selector" };
  }
  if (eventId && complianceEventKey) {
    return { error: "ambiguous_event_selector" };
  }

  const messageType = cleanText(body?.message_type, 32).toLowerCase();
  if (messageType !== "departure" && messageType !== "arrival") {
    return { error: "invalid_message_type" };
  }

  return {
    ...scope,
    eventId,
    complianceEventKey,
    messageType,
    dryRun: body?.dry_run !== false,
    includeRaw: body?.include_raw === true,
  };
}

function _chironMessageTypeAllowedForEvent(messageType, eventType) {
  const type = cleanText(eventType, 64).toLowerCase();
  if (messageType === "departure") return CHIRON_OFFICIAL_DEPARTURE_EVENT_TYPES.has(type);
  if (messageType === "arrival") return CHIRON_OFFICIAL_ARRIVAL_EVENT_TYPES.has(type);
  return false;
}

function _chironExpectedOfficialStatusForMessageType(messageType) {
  if (messageType === "departure") return "vertrek";
  if (messageType === "arrival") return "aankomst";
  return "";
}

function _chironExportBaseUrlLooksTestOrAcc(env) {
  if (String(env?.CHIRON_EXPORT_TEST_TARGET_VERIFIED || "").trim().toLowerCase() === "true") {
    return true;
  }
  const targetEnv = cleanText(env?.CHIRON_EXPORT_TARGET_ENV, 32).toLowerCase();
  if (targetEnv === "test" || targetEnv === "acc") return true;
  const raw = cleanText(env?.CHIRON_EXPORT_BASE_URL, 512);
  if (!raw) return false;
  try {
    const parsed = new URL(raw);
    const marker = `${parsed.hostname} ${parsed.pathname}`.toLowerCase();
    return /(^|[.\-_/ ])(acc|test)([.\-_/ ]|$)/.test(marker);
  } catch (_) {
    return false;
  }
}

function _chironTestflowLiveGate(statusPayload, env) {
  if (!statusPayload || typeof statusPayload !== "object") return "missing_connection_status";
  if (statusPayload.enabled !== true) return "chiron_not_enabled";
  if (cleanText(statusPayload.environment, 32).toLowerCase() !== "test") {
    return "chiron_environment_must_be_test";
  }
  if (statusPayload.production_enabled === true) return "production_must_be_disabled";
  if (statusPayload.official_submit_enabled === true) return "official_submit_must_be_disabled";
  if (statusPayload.test_credentials_stored !== true) return "missing_test_credentials";
  if (cleanText(statusPayload.last_connection_status, 64).toLowerCase() !== "test_passed") {
    return "production_requires_test_passed";
  }
  if (cleanText(env?.CHIRON_EXPORT_MODE, 32).toLowerCase() !== "test") {
    return "chiron_export_mode_must_be_test";
  }
  if (!chironExportTestModeEnabled(env)) return "chiron_export_test_mode_disabled";
  if (!_chironExportBaseUrlLooksTestOrAcc(env)) {
    return "chiron_export_target_not_verified_test";
  }
  return null;
}

async function _chironFindSingleScopedComplianceEvent(env, parsedInput) {
  if (!env?.COMPLIANCE_KV || typeof env.COMPLIANCE_KV.list !== "function" || typeof env.COMPLIANCE_KV.get !== "function") {
    return { error: "missing_kv" };
  }

  const prefix = buildCompliancePrefixForScope(parsedInput.tenantSegment, parsedInput.companySegment);
  let keyNames;
  try {
    keyNames = await listScopedComplianceEventKeys(env, prefix);
  } catch (_) {
    return { error: "Failed to list compliance events." };
  }

  const contextEntries = [];
  const matches = [];
  const wantedKey = cleanText(parsedInput.complianceEventKey, 1024);
  const wantedId = cleanText(parsedInput.eventId, 200);

  if (wantedKey && !wantedKey.startsWith(prefix)) {
    return { error: "event_scope_mismatch" };
  }

  for (const key of keyNames) {
    let raw;
    try {
      raw = await env.COMPLIANCE_KV.get(key);
    } catch (_) {
      continue;
    }
    if (!raw) continue;
    let event;
    try {
      event = JSON.parse(raw);
    } catch (_) {
      continue;
    }
    if (!event || typeof event !== "object" || Array.isArray(event)) continue;
    const entry = { key, event };
    contextEntries.push(entry);
    if ((wantedKey && key === wantedKey) || (!wantedKey && cleanText(event.event_id, 200) === wantedId)) {
      matches.push(entry);
    }
  }

  if (matches.length === 0) return { error: "event_not_found", contextEntries };
  if (matches.length > 1) return { error: "ambiguous_event_id", contextEntries };
  return { entry: matches[0], contextEntries };
}

function _chironBuildTestflowCountersResponse(statusPayload) {
  const progress = getChironTestflowProgress(statusPayload);
  return {
    test_messages_required: progress.test_messages_required,
    test_messages_sent_count: progress.test_messages_sent_count,
    test_departure_required: progress.test_departure_required,
    test_departure_sent_count: progress.test_departure_sent_count,
    test_arrival_required: progress.test_arrival_required,
    test_arrival_sent_count: progress.test_arrival_sent_count,
    test_rides_required: progress.test_rides_required,
    test_rides_completed_count: progress.test_rides_completed_count,
    testflow_status: progress.testflow_status,
    testflow_completed_at: progress.testflow_completed_at,
    testflow_updated_at: progress.testflow_updated_at,
    testflow_last_error: progress.testflow_last_error,
  };
}

async function handleChironTestflowSubmitOnePost(request, env, origin) {
  const authError = ensureAuthorized(request, env);
  if (authError) return authError;

  if (!requireJsonRequest(request)) {
    return jsonResponse(
      { ok: false, error: "Content-Type must be application/json" },
      400,
      origin,
    );
  }

  const body = await readJsonBody(request);
  if (body === null) {
    return jsonResponse({ ok: false, error: "Invalid JSON body" }, 400, origin);
  }

  const parsed = parseChironTestflowSubmitOneInput(body);
  if (parsed.error) {
    return jsonResponse({ ok: false, error: parsed.error }, 400, origin);
  }

  const statusRead = await readChironConnectionStatusRaw(env, parsed.tenantId, parsed.companyId);
  const statusPayload = buildChironConnectionStatusResponse(
    parsed.tenantId,
    parsed.companyId,
    statusRead.doc,
  );

  const liveGateError = parsed.dryRun ? null : _chironTestflowLiveGate(statusPayload, env);
  if (liveGateError) {
    return jsonResponse({ ok: false, error: liveGateError }, 403, origin);
  }

  const found = await _chironFindSingleScopedComplianceEvent(env, parsed);
  if (found.error) {
    const status = found.error === "event_not_found" ? 404 : 400;
    return jsonResponse({ ok: false, error: found.error }, status, origin);
  }

  const event = found.entry.event;
  const eventKey = found.entry.key;
  const eventType = cleanText(event.event_type, 64).toLowerCase();
  if (!_chironMessageTypeAllowedForEvent(parsed.messageType, eventType)) {
    return jsonResponse({ ok: false, error: "message_type_event_mismatch" }, 400, origin);
  }

  const scopedHydrationCache = await _chironLoadScopedHydrationCache(
    env,
    { tenant_id: parsed.tenantId, company_id: parsed.companyId },
    true,
  );
  // Stamp resolved operational-leg type onto legless events (incl. the target
  // event, which is a contextEntries member) so departure and arrival of the
  // same leg derive the same leg-scoped ritnummer for the official draft,
  // idempotency key and sequence index.
  const legTypeMap = await _chironLoadBookingLegTypeMap(env, found.contextEntries || []);
  _chironStampResolvedLegTypeOnEntries(found.contextEntries || [], legTypeMap);
  const batchRitStatuses = _chironBuildBatchRitStatusIndex(found.contextEntries || []);
  const trustedRideHydration = _chironBuildBatchTrustedRideHydrationIndex(
    found.contextEntries || [],
  );
  const exportPayload = buildChironExportPayload(event, eventKey, {
    includeRaw: parsed.includeRaw,
    includeOfficialDraft: true,
    includeChironApiPayload: parsed.dryRun,
    batchRitStatuses,
    scopedHydrationCache,
    trustedRideHydration,
  });

  const officialDraft = exportPayload?.chiron_official_draft;
  const officialValidation = officialDraft?.validation || {};
  const officialPayload = officialDraft?.payload;
  const expectedOfficialStatus = _chironExpectedOfficialStatusForMessageType(parsed.messageType);
  const officialStatus = cleanText(officialDraft?.status, 32).toLowerCase();
  const officialIdempotencyKey = cleanText(officialDraft?.idempotency_key, 256);
  const ritnummer = cleanText(officialPayload?.ritnummer, 256);
  const validationStatus = cleanText(officialValidation.status, 64).toLowerCase();
  const validationMissing = Array.isArray(officialValidation.missing)
    ? officialValidation.missing
    : [];
  const validationErrors = Array.isArray(officialValidation.errors)
    ? officialValidation.errors
    : [];
  const validationBlockers = Array.isArray(officialValidation.blockers)
    ? officialValidation.blockers
    : [];
  const officialValidationAcceptable =
    officialValidation.exportable === true &&
    (validationStatus === "ready" || validationStatus === "warning") &&
    validationMissing.length === 0 &&
    validationErrors.length === 0 &&
    validationBlockers.length === 0 &&
    officialValidation.sequence_safe !== false;

  const baseResponse = {
    ok: true,
    dry_run: parsed.dryRun,
    submitted: false,
    message_type: parsed.messageType,
    event_id: cleanText(event.event_id, 200) || null,
    event_type: eventType || null,
    compliance_event_key: eventKey,
    official_status: officialStatus || null,
    official_ritnummer: ritnummer || null,
    idempotency_key: officialIdempotencyKey || null,
    validation_status: validationStatus || null,
    validation_exportable: officialValidation.exportable === true,
    validation_sequence_safe: officialValidation.sequence_safe !== false,
    validation_blockers: validationBlockers.slice(0, 20),
    validation_warnings: Array.isArray(officialValidation.warnings)
      ? officialValidation.warnings.slice(0, 20)
      : [],
    testflow: _chironBuildTestflowCountersResponse(statusPayload),
  };

  if (
    !officialDraft ||
    officialDraft.category !== "ride_payload" ||
    officialStatus !== expectedOfficialStatus ||
    !officialValidationAcceptable ||
    !officialPayload ||
    typeof officialPayload !== "object" ||
    Array.isArray(officialPayload) ||
    !officialIdempotencyKey ||
    !ritnummer
  ) {
    return jsonResponse(
      {
        ...baseResponse,
        ok: false,
        error: "official_payload_not_ready",
      },
      400,
      origin,
    );
  }

  const chironApiPayload = buildChironTaxiritApiPayload(officialPayload);
  if (!chironApiPayload) {
    return jsonResponse(
      {
        ...baseResponse,
        ok: false,
        error: "official_payload_serialization_failed",
      },
      400,
      origin,
    );
  }

  if (parsed.dryRun) {
    return jsonResponse(
      {
        ...baseResponse,
        chiron_api_payload: chironApiPayload,
      },
      200,
      origin,
    );
  }

  const statusKey = buildChironExportStatusKey(
    parsed.tenantSegment,
    parsed.companySegment,
    officialIdempotencyKey,
  );
  const previousStatus = await _chironReadExportStatus(env, statusKey);

  // RELEASE-P0-OFFICIAL-CHIRON-OAUTH-SUBMIT-2026-07-31: duplicate-submit
  // guard. Consulted BEFORE OAuth, BEFORE the Chiron POST, and BEFORE
  // touching attempt_count for idempotency. Ensures Chiron never receives
  // a second departure/arrival message for the same ritnummer via this
  // admin path.
  const guard = _chironEvaluateSubmitDuplicateGuard(previousStatus);
  if (guard.decision === "already_synced") {
    return jsonResponse(
      {
        ...baseResponse,
        ok: true,
        submitted: false,
        already_synced: true,
        sync_state: "synced",
        attempt_count: Number(previousStatus?.attempt_count || 0),
        export_status_stored: true,
        chiron_response_sanitized: {
          ok: true,
          external_status_code: previousStatus?.external_status_code ?? null,
          external_reference: previousStatus?.external_reference ?? null,
          response_shape: previousStatus?.response_shape ?? null,
          fouten_count: previousStatus?.fouten_count ?? 0,
          sanitized_error: null,
        },
      },
      200,
      origin,
    );
  }
  if (guard.decision === "conflict_pending") {
    return jsonResponse(
      { ...baseResponse, ok: false, error: "chiron_submit_in_progress" },
      409,
      origin,
    );
  }
  if (guard.decision === "verification_required") {
    return jsonResponse(
      {
        ...baseResponse,
        ok: false,
        error: "chiron_submit_verification_required",
        sync_state: "verification_required",
        verification_required_reason:
          cleanText(previousStatus?.verification_required_reason, 120) || null,
      },
      409,
      origin,
    );
  }
  if (guard.decision === "not_retryable") {
    return jsonResponse(
      { ...baseResponse, ok: false, error: "chiron_submit_not_retryable" },
      409,
      origin,
    );
  }

  const attemptCount = Number(previousStatus?.attempt_count || 0) + 1;
  const attemptedAt = nowIso();
  const pendingDoc = {
    schema_version: CHIRON_EXPORT_STATUS_SCHEMA,
    tenant_id: parsed.tenantId,
    company_id: parsed.companyId,
    event_id: baseResponse.event_id,
    official_idempotency_key: officialIdempotencyKey,
    official_ritnummer: ritnummer,
    official_status: officialStatus,
    official_payload_shape: "chiron_taxirit_api_v1",
    sync_state: "pending",
    external_status_code: null,
    external_reference: null,
    response_shape: null,
    fouten_count: null,
    last_attempt_at: attemptedAt,
    attempt_count: attemptCount,
    sanitized_error: null,
    testflow_submit_one: true,
  };
  await _chironWriteExportStatus(env, statusKey, pendingDoc);

  // RELEASE-P0-OFFICIAL-CHIRON-OAUTH-SUBMIT-2026-07-31: acquire the
  // per-company OAuth-derived access token in-memory ONLY. The token is
  // never persisted, never logged and never returned; it is consumed by
  // _chironPostChironExportTestPayload for exactly one taxirit-POST.
  const oauthAcquire = await _chironAcquireOAuthAccessTokenForSubmit(
    env,
    parsed.tenantId,
    parsed.companyId,
    "test",
  );
  if (!oauthAcquire.ok) {
    const failedDoc = {
      ...pendingDoc,
      sync_state: "failed",
      failure_kind: "definitive",
      sanitized_error: _chironSanitizeExportError(oauthAcquire.error || "oauth_failure"),
      last_attempt_at: nowIso(),
    };
    await _chironWriteExportStatus(env, statusKey, failedDoc);
    return jsonResponse(
      {
        ...baseResponse,
        ok: false,
        submitted: false,
        sync_state: "failed",
        error: "oauth_acquire_failed",
        attempt_count: failedDoc.attempt_count,
        export_status_stored: true,
        chiron_response_sanitized: {
          ok: false,
          external_status_code: null,
          external_reference: null,
          response_shape: null,
          fouten_count: 0,
          sanitized_error: failedDoc.sanitized_error,
        },
      },
      502,
      origin,
    );
  }

  const postResult = await _chironPostChironExportTestPayload(
    env,
    chironApiPayload,
    { accessToken: oauthAcquire._access_token_in_memory_only },
  );
  // Discard the in-memory token immediately after the single POST attempt.
  oauthAcquire._access_token_in_memory_only = null;
  const foutenCount = Number(postResult.fouten_count ?? 0);
  const hasChironErrors = Number.isFinite(foutenCount) && foutenCount > 0;
  const acceptedByChiron = postResult.ok === true && !hasChironErrors;
  const ambiguousTransport = postResult.ambiguous === true;
  const nextSyncState = acceptedByChiron
    ? "synced"
    : ambiguousTransport
      ? "verification_required"
      : "failed";
  const finalDoc = {
    ...pendingDoc,
    sync_state: nextSyncState,
    failure_kind: acceptedByChiron
      ? null
      : ambiguousTransport
        ? "ambiguous"
        : "definitive",
    verification_required_reason: ambiguousTransport
      ? cleanText(postResult.sanitized_error, 120) || "chiron_transport_ambiguous"
      : null,
    external_status_code: postResult.external_status_code ?? null,
    external_reference: postResult.external_reference ?? null,
    response_shape: postResult.response_shape ?? null,
    fouten_count: postResult.fouten_count ?? null,
    sanitized_error: postResult.sanitized_error ?? null,
    last_attempt_at: nowIso(),
  };
  await _chironWriteExportStatus(env, statusKey, finalDoc);

  let nextStatusPayload = statusPayload;
  if (acceptedByChiron) {
    const nextStatusDoc = recordChironTestflowSubmitResult(statusRead.doc, {
      officialStatus,
      ritnummer,
      ok: true,
      foutenCount: postResult.fouten_count ?? 0,
      sanitizedError: null,
    });
    const writeStatus = await writeChironConnectionStatusRaw(
      env,
      parsed.tenantId,
      parsed.companyId,
      nextStatusDoc,
    );
    if (!writeStatus.ok) {
      return jsonResponse(
        {
          ...baseResponse,
          ok: false,
          submitted: true,
          error: writeStatus.error || "kv_write_failed",
          chiron_response_sanitized: {
            ok: acceptedByChiron,
            external_status_code: postResult.external_status_code ?? null,
            external_reference: postResult.external_reference ?? null,
            response_shape: postResult.response_shape ?? null,
            fouten_count: postResult.fouten_count ?? null,
            sanitized_error: postResult.sanitized_error ?? null,
          },
        },
        500,
        origin,
      );
    }
    nextStatusPayload = buildChironConnectionStatusResponse(
      parsed.tenantId,
      parsed.companyId,
      nextStatusDoc,
    );
  } else {
    const nextStatusDoc = recordChironTestflowSubmitResult(statusRead.doc, {
      officialStatus,
      ritnummer,
      ok: false,
      foutenCount: postResult.fouten_count ?? 0,
      sanitizedError: postResult.sanitized_error || "chiron_testflow_submit_failed",
    });
    const writeStatus = await writeChironConnectionStatusRaw(
      env,
      parsed.tenantId,
      parsed.companyId,
      nextStatusDoc,
    );
    if (writeStatus.ok) {
      nextStatusPayload = buildChironConnectionStatusResponse(
        parsed.tenantId,
        parsed.companyId,
        nextStatusDoc,
      );
    }
  }

  return jsonResponse(
    {
      ...baseResponse,
      ok: acceptedByChiron,
      submitted: true,
      sync_state: finalDoc.sync_state,
      verification_required_reason: finalDoc.verification_required_reason,
      attempt_count: finalDoc.attempt_count,
      export_status_stored: true,
      chiron_response_sanitized: {
        ok: acceptedByChiron,
        external_status_code: postResult.external_status_code ?? null,
        external_reference: postResult.external_reference ?? null,
        response_shape: postResult.response_shape ?? null,
        fouten_count: postResult.fouten_count ?? null,
        sanitized_error: postResult.sanitized_error ?? null,
        ambiguous: ambiguousTransport,
      },
      testflow: _chironBuildTestflowCountersResponse(nextStatusPayload),
    },
    acceptedByChiron ? 200 : ambiguousTransport ? 202 : 502,
    origin,
  );
}

// RELEASE-P0-OFFICIAL-CHIRON-OAUTH-SUBMIT-2026-07-31: parse and validate
// the admin resolution body for verification_required transitions. Full
// (tenant/company/idempotency_key/expected_official_status) scope is
// REQUIRED — an operator resolution can never target another company's
// event, and it can never mutate a status doc whose official_status has
// drifted (e.g. someone resubmitted a different status in the meantime).
function _chironParseVerificationResolutionBody(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return { error: "invalid_body" };
  }
  const tenantId = cleanText(body.tenant_id, 128);
  const companyId = cleanText(body.company_id, 128);
  const idempotencyKey = cleanText(body.official_idempotency_key, 256);
  const officialStatus = cleanText(body.official_status, 32).toLowerCase();
  if (!tenantId || !companyId) return { error: "missing_scope" };
  if (!idempotencyKey) return { error: "missing_official_idempotency_key" };
  if (!officialStatus || !CHIRON_ALLOWED_OFFICIAL_STATUSES_FOR_RESOLUTION.has(officialStatus)) {
    return { error: "invalid_official_status" };
  }
  const tenantSegment = safeSegment(tenantId, "");
  const companySegment = safeSegment(companyId, "");
  if (!tenantSegment || !companySegment) return { error: "invalid_scope" };
  return {
    tenantId,
    companyId,
    tenantSegment,
    companySegment,
    idempotencyKey,
    officialStatus,
  };
}

async function _chironLoadVerificationResolutionTarget(env, parsed) {
  const statusKey = buildChironExportStatusKey(
    parsed.tenantSegment,
    parsed.companySegment,
    parsed.idempotencyKey,
  );
  const doc = await _chironReadExportStatus(env, statusKey);
  if (!doc || typeof doc !== "object") {
    return { statusKey, doc: null, error: "export_status_not_found" };
  }
  if (
    cleanText(doc.tenant_id, 128) !== parsed.tenantId ||
    cleanText(doc.company_id, 128) !== parsed.companyId
  ) {
    return { statusKey, doc: null, error: "export_status_scope_mismatch" };
  }
  if (
    cleanText(doc.official_idempotency_key, 256) !== parsed.idempotencyKey ||
    cleanText(doc.official_status, 32).toLowerCase() !== parsed.officialStatus
  ) {
    return { statusKey, doc: null, error: "export_status_identity_mismatch" };
  }
  if (cleanText(doc.sync_state, 32).toLowerCase() !== "verification_required") {
    return { statusKey, doc, error: "not_in_verification_required" };
  }
  return { statusKey, doc };
}

async function handleChironTaxiritVerificationConfirmSynced(request, env, origin) {
  const authError = ensureAuthorized(request, env);
  if (authError) return authError;
  if (!requireJsonRequest(request)) {
    return jsonResponse(
      { ok: false, error: "Content-Type must be application/json" },
      400,
      origin,
    );
  }
  const body = await readJsonBody(request);
  if (body === null) {
    return jsonResponse({ ok: false, error: "Invalid JSON body" }, 400, origin);
  }
  const parsed = _chironParseVerificationResolutionBody(body);
  if (parsed.error) {
    return jsonResponse({ ok: false, error: parsed.error }, 400, origin);
  }
  const load = await _chironLoadVerificationResolutionTarget(env, parsed);
  if (load.error) {
    const status = load.error === "export_status_not_found" ? 404 : 409;
    return jsonResponse({ ok: false, error: load.error }, status, origin);
  }
  const nowIsoStr = nowIso();
  const nextDoc = {
    ...load.doc,
    sync_state: "synced",
    failure_kind: null,
    verification_required_reason: null,
    sanitized_error: null,
    external_reference:
      load.doc.external_reference ?? "operator_confirmed_via_portaal",
    operator_resolution: "confirmed_synced",
    operator_resolution_at: nowIsoStr,
  };
  const writeRes = await _chironWriteExportStatus(env, load.statusKey, nextDoc);
  if (!writeRes.ok) {
    return jsonResponse(
      { ok: false, error: writeRes.reason || "kv_write_failed" },
      500,
      origin,
    );
  }
  console.log(
    `[CHIRON_TAXIRIT][RESOLVE][CONFIRMED_SYNCED] tenant=${_chironMaskScopeId(
      parsed.tenantId,
    )} company=${_chironMaskScopeId(parsed.companyId)} status=${parsed.officialStatus}`,
  );
  return jsonResponse(
    {
      ok: true,
      resolution: "confirmed_synced",
      tenant_id: parsed.tenantId,
      company_id: parsed.companyId,
      official_status: parsed.officialStatus,
      sync_state: "synced",
      attempt_count: Number(nextDoc.attempt_count || 0),
    },
    200,
    origin,
  );
}

async function handleChironTaxiritVerificationMarkRetryable(request, env, origin) {
  const authError = ensureAuthorized(request, env);
  if (authError) return authError;
  if (!requireJsonRequest(request)) {
    return jsonResponse(
      { ok: false, error: "Content-Type must be application/json" },
      400,
      origin,
    );
  }
  const body = await readJsonBody(request);
  if (body === null) {
    return jsonResponse({ ok: false, error: "Invalid JSON body" }, 400, origin);
  }
  const parsed = _chironParseVerificationResolutionBody(body);
  if (parsed.error) {
    return jsonResponse({ ok: false, error: parsed.error }, 400, origin);
  }
  const load = await _chironLoadVerificationResolutionTarget(env, parsed);
  if (load.error) {
    const status = load.error === "export_status_not_found" ? 404 : 409;
    return jsonResponse({ ok: false, error: load.error }, status, origin);
  }
  const nowIsoStr = nowIso();
  // Flip to a DEFINITIVE failure so the duplicate-guard now permits exactly
  // one controlled retry. The retry itself goes through the normal
  // submit-one path, which re-runs OAuth and re-POSTs the taxirit body.
  const nextDoc = {
    ...load.doc,
    sync_state: "failed",
    failure_kind: "definitive",
    verification_required_reason: null,
    sanitized_error: "operator_marked_not_received",
    operator_resolution: "mark_not_received_retryable",
    operator_resolution_at: nowIsoStr,
  };
  const writeRes = await _chironWriteExportStatus(env, load.statusKey, nextDoc);
  if (!writeRes.ok) {
    return jsonResponse(
      { ok: false, error: writeRes.reason || "kv_write_failed" },
      500,
      origin,
    );
  }
  console.log(
    `[CHIRON_TAXIRIT][RESOLVE][MARK_RETRYABLE] tenant=${_chironMaskScopeId(
      parsed.tenantId,
    )} company=${_chironMaskScopeId(parsed.companyId)} status=${parsed.officialStatus}`,
  );
  return jsonResponse(
    {
      ok: true,
      resolution: "mark_not_received_retryable",
      tenant_id: parsed.tenantId,
      company_id: parsed.companyId,
      official_status: parsed.officialStatus,
      sync_state: "failed",
      retry_allowed: true,
      attempt_count: Number(nextDoc.attempt_count || 0),
    },
    200,
    origin,
  );
}

async function handleChironExportDryRun(request, url, env, origin) {
  const authError = ensureAuthorized(request, env);
  if (authError) return authError;

  if (!requireJsonRequest(request)) {
    return jsonResponse(
      { ok: false, error: "Content-Type must be application/json" },
      400,
      origin,
    );
  }

  if (!env?.COMPLIANCE_KV || typeof env.COMPLIANCE_KV.list !== "function") {
    return jsonResponse(
      {
        ok: false,
        error: "Compliance storage is not configured (missing COMPLIANCE_KV binding).",
      },
      500,
      origin,
    );
  }

  const body = await readJsonBody(request);
  const scope = parseChironExportScopeFromBody(body);
  if (scope.error) {
    const status = scope.error === "missing_scope" ? 400 : 400;
    return jsonResponse({ ok: false, error: scope.error }, status, origin);
  }

  const limitParsed = parseChironExportLimit(body.limit);
  if (limitParsed.error) {
    return jsonResponse({ ok: false, error: limitParsed.error }, 400, origin);
  }

  const sinceParsed = parseOptionalIsoBodyMs(body, "since");
  if (sinceParsed.error) {
    return jsonResponse({ ok: false, error: sinceParsed.error }, 400, origin);
  }
  const untilParsed = parseOptionalIsoBodyMs(body, "until");
  if (untilParsed.error) {
    return jsonResponse({ ok: false, error: untilParsed.error }, 400, origin);
  }

  const eventTypeFilterRaw = cleanText(body.event_type, 64).toLowerCase();
  if (eventTypeFilterRaw && !ALLOWED_EVENT_TYPES.has(eventTypeFilterRaw)) {
    return jsonResponse({ ok: false, error: "Invalid body field: event_type" }, 400, origin);
  }

  const includeRaw = body.include_raw === true;
  const includeOfficialDraft = parseIncludeOfficialDraftFlag(body, url);
  const includeReadinessReport = parseIncludeReadinessReportFlag(body, url);
  const { tenantId, companyId, tenantSegment, companySegment } = scope;

  const collectResult = await _chironCollectScopedComplianceEventsForExport(
    env,
    tenantSegment,
    companySegment,
    {
      requestedLimit: limitParsed.value,
      sinceMs: sinceParsed.value,
      untilMs: untilParsed.value,
      eventTypeFilterRaw,
    },
  );
  if (collectResult.error) {
    return jsonResponse({ ok: false, error: collectResult.error }, 500, origin);
  }

  const responsePayload = await _chironBuildExportDryRunPayloadResponse(
    tenantId,
    companyId,
    limitParsed.value,
    collectResult,
    includeRaw,
    includeOfficialDraft,
    env,
    { includeReadinessReport },
  );

  console.log(
    `[CHIRON_EXPORT][DRY_RUN] tenant=${_chironMaskScopeId(tenantId)} company=${_chironMaskScopeId(companyId)} scanned=${responsePayload.scanned_count} processed=${responsePayload.processed_count} exportable=${responsePayload.exportable_count}`,
  );

  return jsonResponse(responsePayload, 200, origin);
}

async function handleChironExportTest(request, env, origin) {
  const authError = ensureAuthorized(request, env);
  if (authError) return authError;

  if (!chironExportTestModeEnabled(env)) {
    return jsonResponse({ ok: false, error: "chiron_export_test_mode_disabled" }, 403, origin);
  }

  if (!requireJsonRequest(request)) {
    return jsonResponse(
      { ok: false, error: "Content-Type must be application/json" },
      400,
      origin,
    );
  }

  if (!env?.COMPLIANCE_KV || typeof env.COMPLIANCE_KV.list !== "function") {
    return jsonResponse(
      {
        ok: false,
        error: "Compliance storage is not configured (missing COMPLIANCE_KV binding).",
      },
      500,
      origin,
    );
  }

  const body = await readJsonBody(request);
  const scope = parseChironExportScopeFromBody(body);
  if (scope.error) {
    return jsonResponse({ ok: false, error: scope.error }, 400, origin);
  }

  const limitParsed = parseChironExportLimit(body.limit);
  if (limitParsed.error) {
    return jsonResponse({ ok: false, error: limitParsed.error }, 400, origin);
  }

  const sinceParsed = parseOptionalIsoBodyMs(body, "since");
  if (sinceParsed.error) {
    return jsonResponse({ ok: false, error: sinceParsed.error }, 400, origin);
  }
  const untilParsed = parseOptionalIsoBodyMs(body, "until");
  if (untilParsed.error) {
    return jsonResponse({ ok: false, error: untilParsed.error }, 400, origin);
  }

  const eventTypeFilterRaw = cleanText(body.event_type, 64).toLowerCase();
  if (eventTypeFilterRaw && !ALLOWED_EVENT_TYPES.has(eventTypeFilterRaw)) {
    return jsonResponse({ ok: false, error: "Invalid body field: event_type" }, 400, origin);
  }

  const includeRaw = body.include_raw === true;
  const performLiveExport = body.dry_run === false;
  const { tenantId, companyId, tenantSegment, companySegment } = scope;

  const collectResult = await _chironCollectScopedComplianceEventsForExport(
    env,
    tenantSegment,
    companySegment,
    {
      requestedLimit: limitParsed.value,
      sinceMs: sinceParsed.value,
      untilMs: untilParsed.value,
      eventTypeFilterRaw,
    },
  );
  if (collectResult.error) {
    return jsonResponse({ ok: false, error: collectResult.error }, 500, origin);
  }

  const dryRunPayload = await _chironBuildExportDryRunPayloadResponse(
    tenantId,
    companyId,
    limitParsed.value,
    collectResult,
    includeRaw,
    false,
    env,
  );

  if (!performLiveExport) {
    console.log(
      `[CHIRON_EXPORT][TEST][DRY_RUN] tenant=${_chironMaskScopeId(tenantId)} company=${_chironMaskScopeId(companyId)} scanned=${dryRunPayload.scanned_count} exportable=${dryRunPayload.exportable_count}`,
    );
    return jsonResponse(
      {
        ...dryRunPayload,
        test_mode: true,
        live_export: false,
      },
      200,
      origin,
    );
  }

  const exportAttempts = [];
  const nowIso = new Date().toISOString();

  // Chiron Fase 3F: live test-submit MUST use the validated official draft
  // payload (chiron_official_draft.payload), not the older generic
  // buildChironExportPayload wrapper. We hydrate the same scoped
  // business/fleet/driver cache as the dry-run/readiness flow and build a
  // per-batch ritnummer status index so sequence checks match dry-run.
  const liveOfficialScope = { tenant_id: tenantId, company_id: companyId };
  const liveScopedHydrationCache = await _chironLoadScopedHydrationCache(
    env,
    liveOfficialScope,
    true,
  );
  const liveLegTypeMap = await _chironLoadBookingLegTypeMap(
    env,
    collectResult.limitedEntries,
  );
  _chironStampResolvedLegTypeOnEntries(collectResult.limitedEntries, liveLegTypeMap);
  const liveBatchRitStatuses = _chironBuildBatchRitStatusIndex(
    collectResult.limitedEntries,
  );
  const liveTrustedRideHydration = _chironBuildBatchTrustedRideHydrationIndex(
    collectResult.limitedEntries,
  );
  const livePayloads = collectResult.limitedEntries.map((entry) =>
    buildChironExportPayload(entry.event, entry.key, {
      includeRaw: false,
      includeOfficialDraft: true,
      batchRitStatuses: liveBatchRitStatuses,
      scopedHydrationCache: liveScopedHydrationCache,
      trustedRideHydration: liveTrustedRideHydration,
    }),
  );

  // RELEASE-P0-OFFICIAL-CHIRON-OAUTH-SUBMIT-2026-07-31: acquire the
  // per-company OAuth access token lazily and reuse it across all live
  // POSTs in this single batch. The token stays in-memory (never stored /
  // logged / returned) and is nulled at the end of the loop. If OAuth
  // fails we short-circuit without touching Chiron.
  let batchAccessToken = null;
  let batchOAuthError = null;

  for (const payload of livePayloads) {
    // Chiron Fase 3F strict gating. We never submit when the official
    // draft is missing, when the event is not a ride_payload (e.g.
    // payment_update / cancellation), when validation does not allow
    // export, or when validation status is anything other than "ready".
    // Warning / required_review submits are intentionally blocked here
    // and may only be enabled later behind an explicit feature flag.
    const officialDraft = payload?.chiron_official_draft;
    if (!officialDraft || officialDraft.category !== "ride_payload") continue;
    const officialValidation = officialDraft.validation || {};
    if (officialValidation.exportable !== true) continue;
    if (officialValidation.status !== "ready") continue;
    const officialPayload = officialDraft.payload;
    if (!officialPayload || typeof officialPayload !== "object" || Array.isArray(officialPayload)) {
      continue;
    }
    const officialIdempotencyKey = cleanText(officialDraft.idempotency_key, 256);
    if (!officialIdempotencyKey) continue;

    // Chiron Connect 4A0: serialize the flat official draft into the nested
    // official Chiron Rit API body just before submit. If serialization fails
    // (unexpected for a "ready" payload) we never submit a malformed body.
    const chironApiPayload = buildChironTaxiritApiPayload(officialPayload);
    if (!chironApiPayload) continue;

    // Status / dedupe key is keyed on the official idempotency key so
    // outbound and return legs of a roundtrip get distinct entries (3B)
    // and re-runs against the same ritnummer/status combination collapse
    // onto the same status doc.
    const statusKey = buildChironExportStatusKey(
      tenantSegment,
      companySegment,
      officialIdempotencyKey,
    );
    const previousStatus = await _chironReadExportStatus(env, statusKey);

    // RELEASE-P0-OFFICIAL-CHIRON-OAUTH-SUBMIT-2026-07-31: batch export must
    // NEVER re-POST an event whose duplicate-guard forbids resubmission
    // (already synced, still pending, awaiting operator verification, or
    // otherwise not-retryable). Skip and record the reason.
    const guard = _chironEvaluateSubmitDuplicateGuard(previousStatus);
    if (guard.decision !== "allow") {
      exportAttempts.push({
        event_id: payload.event_id,
        idempotency_key: officialIdempotencyKey,
        official_ritnummer: cleanText(officialPayload.ritnummer, 256) || null,
        official_status: cleanText(officialDraft.status, 32) || null,
        official_payload_shape: "chiron_taxirit_api_v1",
        sync_state: cleanText(previousStatus?.sync_state, 32) || null,
        external_status_code: previousStatus?.external_status_code ?? null,
        external_reference: previousStatus?.external_reference ?? null,
        response_shape: previousStatus?.response_shape ?? null,
        fouten_count: previousStatus?.fouten_count ?? null,
        attempt_count: Number(previousStatus?.attempt_count || 0),
        sanitized_error: previousStatus?.sanitized_error ?? null,
        status_key: statusKey,
        skipped: true,
        skip_reason: `duplicate_guard_${guard.decision}`,
      });
      continue;
    }
    const attemptCount = Number(previousStatus?.attempt_count || 0) + 1;

    const pendingDoc = {
      schema_version: CHIRON_EXPORT_STATUS_SCHEMA,
      tenant_id: tenantId,
      company_id: companyId,
      event_id: payload.event_id,
      official_idempotency_key: officialIdempotencyKey,
      official_ritnummer: cleanText(officialPayload.ritnummer, 256) || null,
      official_status: cleanText(officialDraft.status, 32) || null,
      official_payload_shape: "chiron_taxirit_api_v1",
      sync_state: "pending",
      external_status_code: null,
      external_reference: null,
      last_attempt_at: nowIso,
      attempt_count: attemptCount,
      sanitized_error: null,
    };
    await _chironWriteExportStatus(env, statusKey, pendingDoc);

    if (!batchAccessToken && !batchOAuthError) {
      const oauthAcquire = await _chironAcquireOAuthAccessTokenForSubmit(
        env,
        tenantId,
        companyId,
        "test",
      );
      if (oauthAcquire.ok) {
        batchAccessToken = oauthAcquire._access_token_in_memory_only;
        oauthAcquire._access_token_in_memory_only = null;
      } else {
        batchOAuthError = _chironSanitizeExportError(
          oauthAcquire.error || "oauth_failure",
        );
      }
    }

    let postResult;
    if (batchOAuthError) {
      postResult = {
        ok: false,
        sanitized_error: batchOAuthError,
        ambiguous: false,
        external_status_code: null,
        external_reference: null,
        response_shape: null,
        fouten_count: 0,
      };
    } else {
      // Chiron Fase 3F + 4A0: only the nested official Chiron Rit API body is
      // sent externally, signed with the per-company OAuth-derived bearer.
      // No tenant_id, event_id, payment_status, amount, vat_* or other
      // generic wrapper fields leak to the test receiver.
      postResult = await _chironPostChironExportTestPayload(env, chironApiPayload, {
        accessToken: batchAccessToken,
      });
    }
    const foutenCount = Number(postResult.fouten_count ?? 0);
    const acceptedByChiron =
      postResult.ok === true &&
      !(Number.isFinite(foutenCount) && foutenCount > 0);
    const ambiguousTransport = postResult.ambiguous === true;
    const nextSyncState = acceptedByChiron
      ? "synced"
      : ambiguousTransport
        ? "verification_required"
        : "failed";
    const finalDoc = {
      ...pendingDoc,
      sync_state: nextSyncState,
      failure_kind: acceptedByChiron
        ? null
        : ambiguousTransport
          ? "ambiguous"
          : "definitive",
      verification_required_reason: ambiguousTransport
        ? cleanText(postResult.sanitized_error, 120) || "chiron_transport_ambiguous"
        : null,
      external_status_code: postResult.external_status_code ?? null,
      external_reference: postResult.external_reference ?? null,
      response_shape: postResult.response_shape ?? null,
      fouten_count: postResult.fouten_count ?? null,
      sanitized_error: postResult.sanitized_error ?? null,
      last_attempt_at: new Date().toISOString(),
    };
    await _chironWriteExportStatus(env, statusKey, finalDoc);

    exportAttempts.push({
      event_id: payload.event_id,
      idempotency_key: officialIdempotencyKey,
      official_ritnummer: pendingDoc.official_ritnummer,
      official_status: pendingDoc.official_status,
      official_payload_shape: pendingDoc.official_payload_shape,
      sync_state: finalDoc.sync_state,
      verification_required_reason: finalDoc.verification_required_reason,
      external_status_code: finalDoc.external_status_code,
      external_reference: finalDoc.external_reference,
      response_shape: finalDoc.response_shape,
      fouten_count: finalDoc.fouten_count,
      attempt_count: finalDoc.attempt_count,
      sanitized_error: finalDoc.sanitized_error,
      status_key: statusKey,
    });
  }

  batchAccessToken = null;

  console.log(
    `[CHIRON_EXPORT][TEST][LIVE] tenant=${_chironMaskScopeId(tenantId)} company=${_chironMaskScopeId(companyId)} attempts=${exportAttempts.length} synced=${exportAttempts.filter((entry) => entry.sync_state === "synced").length}`,
  );

  return jsonResponse(
    {
      ok: true,
      dry_run: false,
      test_mode: true,
      live_export: true,
      tenant_id: tenantId,
      company_id: companyId,
      limit: limitParsed.value,
      scanned_count: dryRunPayload.scanned_count,
      processed_count: dryRunPayload.processed_count,
      exportable_count: dryRunPayload.exportable_count,
      non_exportable_count: dryRunPayload.non_exportable_count,
      malformed_count: dryRunPayload.malformed_count,
      has_more_candidates: dryRunPayload.has_more_candidates,
      sample_payloads: dryRunPayload.sample_payloads,
      export_attempts: exportAttempts,
    },
    200,
    origin,
  );
}

// Chiron-6B-3D: clean app-facing readiness endpoint that returns only the
// readiness report + minimal metadata. Supports GET (query params) and POST (JSON body).
function _chironExtractReadinessRequestBody(method, parsedBody, url) {
  if (method === "POST") {
    if (parsedBody && typeof parsedBody === "object" && !Array.isArray(parsedBody)) {
      return { ...parsedBody };
    }
    return null;
  }
  const params = url?.searchParams;
  if (!params) return {};
  const body = {};
  const tenantId = cleanText(params.get("tenant_id"), 128);
  const companyId = cleanText(params.get("company_id"), 128);
  if (tenantId) body.tenant_id = tenantId;
  if (companyId) body.company_id = companyId;
  const limitRaw = cleanText(params.get("limit"), 16);
  if (limitRaw) body.limit = limitRaw;
  const eventTypeRaw = cleanText(params.get("event_type"), 64);
  if (eventTypeRaw) body.event_type = eventTypeRaw;
  const sinceRaw = cleanText(params.get("since"), 64);
  if (sinceRaw) body.since = sinceRaw;
  const untilRaw = cleanText(params.get("until"), 64);
  if (untilRaw) body.until = untilRaw;
  return body;
}

async function handleChironReadinessReport(request, url, env, origin) {
  if (request.method !== "GET" && request.method !== "POST") {
    return jsonResponse({ ok: false, error: "Method Not Allowed" }, 405, origin);
  }

  /* CHIRON-P0-2A: parse the request body / URL scope BEFORE authenticating
   * so ensureAuthorizedOrInternalProxy can enforce that the internal-proxy
   * scope header matches. Content-Type + body-shape validation stays where
   * it was; only the auth call is moved. Storage-not-configured is reported
   * only after auth so an unauthenticated caller cannot fingerprint
   * environment health. */
  let parsedBody = null;
  if (request.method === "POST") {
    if (!requireJsonRequest(request)) {
      return jsonResponse(
        { ok: false, error: "Content-Type must be application/json" },
        400,
        origin,
      );
    }
    parsedBody = await readJsonBody(request);
  }

  const body = _chironExtractReadinessRequestBody(request.method, parsedBody, url);
  if (!body) {
    return jsonResponse({ ok: false, error: "Invalid JSON body" }, 400, origin);
  }

  const scope = parseChironExportScopeFromBody(body);
  if (scope.error) {
    return jsonResponse({ ok: false, error: scope.error }, 400, origin);
  }

  const authError = ensureAuthorizedOrInternalProxy(request, env, {
    tenantId: scope.tenantId,
    companyId: scope.companyId,
  });
  if (authError) return authError;

  if (!env?.COMPLIANCE_KV || typeof env.COMPLIANCE_KV.list !== "function") {
    return jsonResponse(
      {
        ok: false,
        error: "Compliance storage is not configured (missing COMPLIANCE_KV binding).",
      },
      500,
      origin,
    );
  }

  const limitParsed = parseChironExportLimit(body.limit);
  if (limitParsed.error) {
    return jsonResponse({ ok: false, error: limitParsed.error }, 400, origin);
  }
  // Default to 20 (vs. 10 used by export dry-run) when no explicit limit is given.
  const effectiveLimit = cleanText(body.limit, 16) ? limitParsed.value : CHIRON_READINESS_DEFAULT_LIMIT;

  const sinceParsed = parseOptionalIsoBodyMs(body, "since");
  if (sinceParsed.error) {
    return jsonResponse({ ok: false, error: sinceParsed.error }, 400, origin);
  }
  const untilParsed = parseOptionalIsoBodyMs(body, "until");
  if (untilParsed.error) {
    return jsonResponse({ ok: false, error: untilParsed.error }, 400, origin);
  }

  const requestedEventType = cleanText(body.event_type, 64).toLowerCase();
  const effectiveEventType = requestedEventType || CHIRON_READINESS_DEFAULT_EVENT_TYPE;
  if (!ALLOWED_EVENT_TYPES.has(effectiveEventType)) {
    return jsonResponse({ ok: false, error: "Invalid body field: event_type" }, 400, origin);
  }

  const { tenantId, companyId, tenantSegment, companySegment } = scope;

  const collectResult = await _chironCollectScopedComplianceEventsForExport(
    env,
    tenantSegment,
    companySegment,
    {
      requestedLimit: effectiveLimit,
      sinceMs: sinceParsed.value,
      untilMs: untilParsed.value,
      eventTypeFilterRaw: effectiveEventType,
    },
  );
  if (collectResult.error) {
    return jsonResponse({ ok: false, error: collectResult.error }, 500, origin);
  }

  // Reuse the dry-run/report path. We do NOT expose chiron_official_draft to
  // the readiness endpoint, so includeOfficialDraft stays false; the report
  // builder auto-enables it internally and the response strips it from samples.
  const dryRunPayload = await _chironBuildExportDryRunPayloadResponse(
    tenantId,
    companyId,
    effectiveLimit,
    collectResult,
    false,
    false,
    env,
    { includeReadinessReport: true },
  );

  console.log(
    `[CHIRON_READINESS] tenant=${_chironMaskScopeId(tenantId)} company=${_chironMaskScopeId(companyId)} scanned=${dryRunPayload.scanned_count} matching=${collectResult.matchingEventCount} processed=${dryRunPayload.processed_count} has_more=${collectResult.hasMoreCandidates} overall=${dryRunPayload.readiness_report?.overall_status || "-"}`,
  );

  return jsonResponse(
    {
      ok: true,
      tenant_id: tenantId,
      company_id: companyId,
      dry_run: true,
      official_submission_performed: false,
      limit: effectiveLimit,
      event_type: effectiveEventType,
      scanned_count: dryRunPayload.scanned_count,
      matching_event_count: collectResult.matchingEventCount,
      processed_count: dryRunPayload.processed_count,
      has_more_candidates: collectResult.hasMoreCandidates,
      readiness_report: dryRunPayload.readiness_report || null,
    },
    200,
    origin,
  );
}

// === Phase 2A: Chiron credentials encryption/storage foundation (helpers only; no routes) ===

function _chironBase64urlEncodeBytes(bytes) {
  const arr = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes || []);
  let binary = "";
  const chunkSize = 0x2000;
  for (let i = 0; i < arr.length; i += chunkSize) {
    const end = Math.min(i + chunkSize, arr.length);
    let chunk = "";
    for (let j = i; j < end; j++) chunk += String.fromCharCode(arr[j]);
    binary += chunk;
  }
  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

function _chironBase64urlDecodeToBytes(str) {
  const raw = String(str || "").trim();
  if (!raw) return new Uint8Array();
  const normalized = raw
    .replace(/-/g, "+")
    .replace(/_/g, "/")
    .padEnd(Math.ceil(raw.length / 4) * 4, "=");
  const bin = atob(normalized);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function buildChironCredentialsKvKey(tenantId, companyId, environment) {
  const tenant = cleanText(tenantId, 128);
  const company = cleanText(companyId, 128);
  const envToken = cleanText(environment, 32).toLowerCase();
  if (!tenant || !company) return null;
  if (!CHIRON_CONNECTION_ALLOWED_ENVIRONMENTS.has(envToken)) return null;
  return `tenant:${tenant}:company:${company}:chiron_credentials:${envToken}:v1`;
}

function validateChironCredentialsAuthScheme(scheme) {
  const normalized = cleanText(scheme, 64).toLowerCase();
  if (!normalized || !CHIRON_CREDENTIALS_ALLOWED_AUTH_SCHEMES.has(normalized)) {
    return "unsupported_auth_scheme";
  }
  return null;
}

async function _importChironCredentialsEncryptionKey(env) {
  const rawSecret = String(env?.CHIRON_CREDENTIALS_ENCRYPTION_KEY || "").trim();
  if (!rawSecret) throw new Error("missing_chiron_credentials_encryption_key");
  if (rawSecret.length < CHIRON_CREDENTIALS_ENCRYPTION_KEY_MIN_LENGTH) {
    throw new Error("chiron_credentials_encryption_key_too_short");
  }
  const keyMaterial = new TextEncoder().encode(rawSecret);
  const digest = await crypto.subtle.digest("SHA-256", keyMaterial);
  return crypto.subtle.importKey(
    "raw",
    digest,
    { name: "AES-GCM", length: 256 },
    false,
    ["encrypt", "decrypt"],
  );
}

async function encryptChironCredentialBlob(plainTextString, env) {
  const plaintext = String(plainTextString ?? "");
  if (!plaintext) throw new Error("missing_credential_plaintext");
  const kid = cleanText(env?.CHIRON_CREDENTIALS_ENCRYPTION_KID, 32) || "v1";
  const key = await _importChironCredentialsEncryptionKey(env);
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const encoded = new TextEncoder().encode(plaintext);
  const encrypted = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, key, encoded);
  return {
    alg: "AES-GCM",
    kid,
    iv: _chironBase64urlEncodeBytes(iv),
    ciphertext: _chironBase64urlEncodeBytes(new Uint8Array(encrypted)),
  };
}

async function decryptChironCredentialBlob(blobObj, env) {
  if (!blobObj || typeof blobObj !== "object" || Array.isArray(blobObj)) {
    throw new Error("invalid_chiron_credential_blob");
  }
  const alg = String(blobObj.alg || "").trim();
  if (alg !== "AES-GCM") throw new Error("unsupported_chiron_credential_blob_alg");
  const kid = cleanText(blobObj.kid, 32);
  if (!kid) throw new Error("invalid_chiron_credential_blob_kid");
  const iv = _chironBase64urlDecodeToBytes(blobObj.iv);
  const ciphertext = _chironBase64urlDecodeToBytes(blobObj.ciphertext);
  if (!iv.length || !ciphertext.length) {
    throw new Error("invalid_chiron_credential_blob_payload");
  }
  const key = await _importChironCredentialsEncryptionKey(env);
  const decrypted = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv },
    key,
    ciphertext,
  );
  return new TextDecoder().decode(new Uint8Array(decrypted));
}

async function chironCredentialFingerprintShort(plainTextString) {
  const plaintext = String(plainTextString ?? "");
  if (!plaintext) return "";
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(plaintext));
  const hex = Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
  return hex.slice(0, 16);
}

function chironMaskTrailingIdentifier(value) {
  const text = cleanText(value, 512);
  if (!text) return "";
  if (text.length <= 4) return "*".repeat(text.length);
  return `${"*".repeat(4)}${text.slice(-4)}`;
}

function _normalizeChironTestCredentialsBodyKey(value) {
  return cleanText(value, 64).toLowerCase().replace(/[\s_-]/g, "");
}

function parseChironTestCredentialsPostInput(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return { error: "invalid_body" };
  }

  for (const key of Object.keys(body)) {
    const normalized = _normalizeChironTestCredentialsBodyKey(key);
    if (CHIRON_TEST_CREDENTIALS_FORBIDDEN_TOP_LEVEL_KEYS.has(normalized)) {
      return { error: "forbidden_fields" };
    }
    if (!CHIRON_TEST_CREDENTIALS_ALLOWED_TOP_LEVEL_KEYS.has(key)) {
      return { error: "forbidden_fields" };
    }
  }

  const tenantId = cleanText(body.tenant_id, 128);
  const companyId = cleanText(body.company_id, 128);
  if (!tenantId || !companyId) {
    return { error: "missing_scope" };
  }

  const authScheme = cleanText(body.auth_scheme, 64).toLowerCase();
  const schemeError = validateChironCredentialsAuthScheme(authScheme);
  if (schemeError) {
    return { error: schemeError };
  }

  const credentialFields = body.credential_fields;
  if (
    !credentialFields ||
    typeof credentialFields !== "object" ||
    Array.isArray(credentialFields)
  ) {
    return { error: "invalid_credential_fields" };
  }

  if (authScheme === "api_token") {
    const fieldKeys = Object.keys(credentialFields);
    if (fieldKeys.length !== 1 || fieldKeys[0] !== "api_token") {
      return { error: "invalid_credential_fields" };
    }
    const rawApiToken = credentialFields.api_token;
    if (typeof rawApiToken !== "string") {
      return { error: "invalid_api_token" };
    }
    const apiToken = rawApiToken.trim();
    if (!apiToken) {
      return { error: "missing_api_token" };
    }
    return { tenantId, companyId, authScheme, apiToken };
  }

  // Chiron Connect 4A: OAuth2 client credentials (test/ACC only). We store the
  // client_id + client_secret encrypted; the actual token exchange and live
  // connection test land in 4B. token_url / scope / production credentials are
  // intentionally not accepted in this patch.
  if (authScheme === "oauth_client_credentials") {
    const fieldKeys = Object.keys(credentialFields);
    if (
      fieldKeys.length !== 2 ||
      !fieldKeys.includes("client_id") ||
      !fieldKeys.includes("client_secret")
    ) {
      return { error: "invalid_credential_fields" };
    }
    const rawClientId = credentialFields.client_id;
    const rawClientSecret = credentialFields.client_secret;
    if (typeof rawClientId !== "string" || typeof rawClientSecret !== "string") {
      return { error: "invalid_credential_fields" };
    }
    const clientId = rawClientId.trim();
    if (!clientId) {
      return { error: "missing_client_id" };
    }
    if (clientId.length > CHIRON_OAUTH_CLIENT_ID_MAX_LENGTH) {
      return { error: "invalid_client_id" };
    }
    const clientSecret = rawClientSecret.trim();
    if (!clientSecret) {
      return { error: "missing_client_secret" };
    }
    if (clientSecret.length > CHIRON_OAUTH_CLIENT_SECRET_MAX_LENGTH) {
      return { error: "invalid_client_secret" };
    }
    return { tenantId, companyId, authScheme, clientId, clientSecret };
  }

  return { error: "unsupported_auth_scheme" };
}

function parseChironTestCredentialsClearInput(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return { error: "invalid_body" };
  }

  for (const key of Object.keys(body)) {
    const normalized = _normalizeChironTestCredentialsBodyKey(key);
    if (CHIRON_TEST_CREDENTIALS_FORBIDDEN_TOP_LEVEL_KEYS.has(normalized)) {
      return { error: "forbidden_fields" };
    }
    if (!CHIRON_TEST_CREDENTIALS_CLEAR_ALLOWED_TOP_LEVEL_KEYS.has(key)) {
      return { error: "forbidden_fields" };
    }
  }

  const tenantId = cleanText(body.tenant_id, 128);
  const companyId = cleanText(body.company_id, 128);
  if (!tenantId || !companyId) {
    return { error: "missing_scope" };
  }

  return { tenantId, companyId };
}

function _normalizeChironConnectionTestBodyKey(value) {
  return cleanText(value, 64).toLowerCase().replace(/[\s_-]/g, "");
}

function parseChironConnectionTestPostInput(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return { error: "invalid_body" };
  }

  for (const key of Object.keys(body)) {
    const normalized = _normalizeChironConnectionTestBodyKey(key);
    if (CHIRON_CONFIG_FORBIDDEN_BODY_KEYS.has(normalized)) {
      return { error: "forbidden_fields" };
    }
    if (normalized === "credentialfields" || normalized === "credential_fields") {
      return { error: "forbidden_fields" };
    }
    if (!CHIRON_CONNECTION_TEST_ALLOWED_TOP_LEVEL_KEYS.has(key)) {
      return { error: "forbidden_fields" };
    }
  }

  const tenantId = cleanText(body.tenant_id, 128);
  const companyId = cleanText(body.company_id, 128);
  if (!tenantId || !companyId) {
    return { error: "missing_scope" };
  }

  const environmentRaw =
    body.environment === undefined || body.environment === null
      ? "test"
      : cleanText(body.environment, 32).toLowerCase();

  if (environmentRaw === "production") {
    return { error: "production_connection_test_not_supported" };
  }
  if (environmentRaw !== "test") {
    return { error: "invalid_environment" };
  }

  return { tenantId, companyId, environment: "test" };
}

function _chironDecryptedCredentialPayloadValid(parsed) {
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    return false;
  }
  if (cleanText(parsed.schema_version, 64) !== CHIRON_CREDENTIALS_PAYLOAD_SCHEMA_VERSION) {
    return false;
  }
  const scheme = cleanText(parsed.auth_scheme, 64).toLowerCase();

  if (scheme === "api_token") {
    const rawApiToken = parsed.api_token;
    if (typeof rawApiToken !== "string") return false;
    if (!rawApiToken.trim()) return false;
    return true;
  }

  // Chiron Connect 4A: OAuth2 client credentials are valid when both
  // client_id and client_secret survived the decrypt roundtrip.
  if (scheme === "oauth_client_credentials") {
    const rawClientId = parsed.client_id;
    const rawClientSecret = parsed.client_secret;
    if (typeof rawClientId !== "string" || typeof rawClientSecret !== "string") {
      return false;
    }
    if (!rawClientId.trim() || !rawClientSecret.trim()) return false;
    return true;
  }

  return false;
}

function _chironCredentialsDocReadyForMockTest(doc) {
  if (!doc || typeof doc !== "object" || Array.isArray(doc)) return false;
  if (cleanText(doc.schema_version, 64) !== CHIRON_CREDENTIALS_SCHEMA_VERSION) return false;
  if (cleanText(doc.environment, 32).toLowerCase() !== "test") return false;
  const scheme = cleanText(doc.auth_scheme, 64).toLowerCase();
  if (!CHIRON_CREDENTIALS_ALLOWED_AUTH_SCHEMES.has(scheme)) return false;
  const encrypted = doc.credential_payload_encrypted;
  return !!(encrypted && typeof encrypted === "object" && !Array.isArray(encrypted));
}

async function readChironCredentialsRaw(env, tenantId, companyId, environment) {
  if (!env?.COMPLIANCE_KV || typeof env.COMPLIANCE_KV.get !== "function") {
    return { doc: null, error: "missing_kv" };
  }
  const key = buildChironCredentialsKvKey(tenantId, companyId, environment);
  if (!key) return { doc: null, error: "missing_scope" };
  try {
    const raw = await env.COMPLIANCE_KV.get(key);
    if (!raw) return { doc: null, key };
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      return { doc: null, key };
    }
    return { doc: parsed, key };
  } catch (_) {
    return { doc: null, key, error: "kv_read_failed" };
  }
}

async function writeChironCredentialsRaw(env, key, doc) {
  if (!env?.COMPLIANCE_KV || typeof env.COMPLIANCE_KV.put !== "function") {
    return { ok: false, error: "missing_kv" };
  }
  if (!key) return { ok: false, error: "missing_scope" };
  try {
    await env.COMPLIANCE_KV.put(key, JSON.stringify(doc));
    return { ok: true, key };
  } catch (_) {
    return { ok: false, error: "kv_write_failed" };
  }
}

async function deleteChironCredentialsRaw(env, tenantId, companyId, environment) {
  if (!env?.COMPLIANCE_KV || typeof env.COMPLIANCE_KV.delete !== "function") {
    return { ok: false, error: "missing_kv" };
  }
  const key = buildChironCredentialsKvKey(tenantId, companyId, environment);
  if (!key) return { ok: false, error: "missing_scope" };
  try {
    await env.COMPLIANCE_KV.delete(key);
    return { ok: true };
  } catch (_) {
    return { ok: false, error: "kv_delete_failed" };
  }
}

function buildChironTestCredentialsStatusDoc(
  existingStored,
  tenantId,
  companyId,
  updatedAt,
  updatedBy,
) {
  const existing = existingStored && typeof existingStored === "object" ? existingStored : {};

  const environmentRaw = cleanText(existing.environment, 32).toLowerCase();
  const environment = CHIRON_CONNECTION_ALLOWED_ENVIRONMENTS.has(environmentRaw)
    ? environmentRaw
    : "test";

  const regionRaw = cleanText(existing.region, 32).toLowerCase();
  const region = CHIRON_CONNECTION_ALLOWED_REGIONS.has(regionRaw)
    ? regionRaw
    : "flanders";

  const testMessagesRequired = Number(existing.test_messages_required);
  const productionCredentialsStored = existing.production_credentials_stored === true;

  return {
    schema_version: CHIRON_CONNECTION_STATUS_SCHEMA,
    tenant_id: tenantId,
    company_id: companyId,
    enabled: existing.enabled === true,
    environment,
    region,
    production_enabled: false,
    test_credentials_stored: true,
    production_credentials_stored: productionCredentialsStored,
    last_connection_status: "never_tested",
    last_connection_test_at: null,
    last_connection_status_message: null,
    official_submission_performed_at:
      cleanText(existing.official_submission_performed_at, 64) || null,
    test_messages_required:
      Number.isFinite(testMessagesRequired) && testMessagesRequired >= 0
        ? Math.floor(testMessagesRequired)
        : 10,
    test_messages_sent_count: 0,
    updated_at: updatedAt,
    updated_by: updatedBy,
  };
}

function buildChironTestCredentialsClearedStatusDoc(
  existingStored,
  tenantId,
  companyId,
  updatedAt,
  updatedBy,
) {
  const existing =
    existingStored && typeof existingStored === "object" && !Array.isArray(existingStored)
      ? { ...existingStored }
      : {};

  for (const key of CHIRON_INTERNAL_TEST_STATUS_DOC_KEYS) {
    delete existing[key];
  }

  const environmentRaw = cleanText(existing.environment, 32).toLowerCase();
  const environment = CHIRON_CONNECTION_ALLOWED_ENVIRONMENTS.has(environmentRaw)
    ? environmentRaw
    : "test";

  const regionRaw = cleanText(existing.region, 32).toLowerCase();
  const region = CHIRON_CONNECTION_ALLOWED_REGIONS.has(regionRaw)
    ? regionRaw
    : "flanders";

  const existingStatusRaw = cleanText(existing.last_connection_status, 64).toLowerCase();
  const lastConnectionStatus = CHIRON_CONNECTION_ALLOWED_STATUSES.has(existingStatusRaw)
    ? existingStatusRaw
    : "never_tested";

  const testMessagesRequired = Number(existing.test_messages_required);
  const testMessagesSent = Number(existing.test_messages_sent_count);

  return {
    ...existing,
    schema_version: CHIRON_CONNECTION_STATUS_SCHEMA,
    tenant_id: tenantId,
    company_id: companyId,
    enabled: existing.enabled === true,
    environment,
    region,
    test_credentials_stored: false,
    production_credentials_stored: existing.production_credentials_stored === true,
    last_connection_status: lastConnectionStatus,
    last_connection_test_at: cleanText(existing.last_connection_test_at, 64) || null,
    last_connection_status_message:
      cleanText(existing.last_connection_status_message, 256) || null,
    official_submission_performed_at:
      cleanText(existing.official_submission_performed_at, 64) || null,
    test_messages_required:
      Number.isFinite(testMessagesRequired) && testMessagesRequired >= 0
        ? Math.floor(testMessagesRequired)
        : 10,
    test_messages_sent_count:
      Number.isFinite(testMessagesSent) && testMessagesSent >= 0
        ? Math.floor(testMessagesSent)
        : 0,
    updated_at: updatedAt,
    updated_by: updatedBy,
  };
}

// === Chiron Connect 4C: acceptance testflow progress model ===================

function _chironTestflowIntOr(value, fallback) {
  const num = Number(value);
  return Number.isFinite(num) && num >= 0 ? Math.floor(num) : fallback;
}

// Normalizes a ritnummer history array: trims, dedupes, caps to the history
// max. Never returns an unbounded array.
function _chironTestflowRitList(value) {
  if (!Array.isArray(value)) return [];
  const out = [];
  for (const item of value) {
    const text = cleanText(item, 256);
    if (text && !out.includes(text)) out.push(text);
    if (out.length >= CHIRON_TESTFLOW_RITNUMMER_HISTORY_MAX) break;
  }
  return out;
}

function _chironTestflowAppendRit(list, rit) {
  const base = Array.isArray(list) ? [...list] : [];
  const text = cleanText(rit, 256);
  if (text && !base.includes(text)) base.push(text);
  if (base.length > CHIRON_TESTFLOW_RITNUMMER_HISTORY_MAX) {
    return base.slice(base.length - CHIRON_TESTFLOW_RITNUMMER_HISTORY_MAX);
  }
  return base;
}

// Pure projection of a connection status doc into normalized testflow progress,
// applying defaults for older docs that predate these fields. testflow_status
// is derived from the counters so it can never claim "complete" unless every
// required count is met.
function getChironTestflowProgress(statusDoc) {
  const doc =
    statusDoc && typeof statusDoc === "object" && !Array.isArray(statusDoc)
      ? statusDoc
      : {};

  const messagesRequired = _chironTestflowIntOr(
    doc.test_messages_required,
    CHIRON_OAUTH_DEFAULT_TEST_MESSAGES_REQUIRED,
  );
  const ridesRequired = _chironTestflowIntOr(
    doc.test_rides_required,
    CHIRON_TESTFLOW_DEFAULT_RIDES_REQUIRED,
  );
  const departureRequired = _chironTestflowIntOr(
    doc.test_departure_required,
    CHIRON_TESTFLOW_DEFAULT_DEPARTURE_REQUIRED,
  );
  const arrivalRequired = _chironTestflowIntOr(
    doc.test_arrival_required,
    CHIRON_TESTFLOW_DEFAULT_ARRIVAL_REQUIRED,
  );

  const messagesSent = _chironTestflowIntOr(doc.test_messages_sent_count, 0);
  const departureSent = _chironTestflowIntOr(doc.test_departure_sent_count, 0);
  const arrivalSent = _chironTestflowIntOr(doc.test_arrival_sent_count, 0);
  const ridesCompleted = _chironTestflowIntOr(doc.test_rides_completed_count, 0);

  const requirementsMet =
    messagesSent >= messagesRequired &&
    departureSent >= departureRequired &&
    arrivalSent >= arrivalRequired &&
    ridesCompleted >= ridesRequired;

  let testflowStatus;
  if (requirementsMet) {
    testflowStatus = "complete";
  } else if (
    messagesSent > 0 ||
    departureSent > 0 ||
    arrivalSent > 0 ||
    ridesCompleted > 0
  ) {
    testflowStatus = "in_progress";
  } else {
    testflowStatus = "not_started";
  }

  return {
    test_messages_required: messagesRequired,
    test_rides_required: ridesRequired,
    test_departure_required: departureRequired,
    test_arrival_required: arrivalRequired,
    test_messages_sent_count: messagesSent,
    test_departure_sent_count: departureSent,
    test_arrival_sent_count: arrivalSent,
    test_rides_completed_count: ridesCompleted,
    testflow_status: testflowStatus,
    testflow_completed_at: cleanText(doc.testflow_completed_at, 64) || null,
    testflow_updated_at: cleanText(doc.testflow_updated_at, 64) || null,
    testflow_last_error: cleanText(doc.testflow_last_error, 256) || null,
    requirements_met: requirementsMet,
  };
}

// Chiron Connect 4C: pure helper that folds one submit result into the testflow
// counters of a status doc. NOT wired to any real submit yet (that is 4D). It is
// idempotent per (ritnummer, status): the same departure/arrival ritnummer can
// never be counted twice. Only successful results (ok === true) advance
// counters; failures only record a sanitized last error.
function recordChironTestflowSubmitResult(
  existingStatusDoc,
  { officialStatus, ritnummer, ok, foutenCount, sanitizedError } = {},
) {
  const existing =
    existingStatusDoc &&
    typeof existingStatusDoc === "object" &&
    !Array.isArray(existingStatusDoc)
      ? existingStatusDoc
      : {};
  const progress = getChironTestflowProgress(existing);
  const updatedAt = nowIso();
  const status = cleanText(officialStatus, 32).toLowerCase();
  const cleanRit = cleanText(ritnummer, 256);

  const departureRits = _chironTestflowRitList(existing.testflow_ritnummers_departure);
  const arrivalRits = _chironTestflowRitList(existing.testflow_ritnummers_arrival);
  const completedRits = _chironTestflowRitList(existing.testflow_ritnummers_completed);

  const base = {
    ...existing,
    test_messages_required: progress.test_messages_required,
    test_rides_required: progress.test_rides_required,
    test_departure_required: progress.test_departure_required,
    test_arrival_required: progress.test_arrival_required,
    test_messages_sent_count: progress.test_messages_sent_count,
    test_departure_sent_count: progress.test_departure_sent_count,
    test_arrival_sent_count: progress.test_arrival_sent_count,
    test_rides_completed_count: progress.test_rides_completed_count,
    testflow_ritnummers_departure: departureRits,
    testflow_ritnummers_arrival: arrivalRits,
    testflow_ritnummers_completed: completedRits,
    testflow_updated_at: updatedAt,
  };

  const safeFoutenCount = Number(foutenCount);
  if (ok !== true || (Number.isFinite(safeFoutenCount) && safeFoutenCount > 0)) {
    base.testflow_last_error =
      cleanText(sanitizedError, 256) || "chiron_testflow_submit_failed";
    const failedProgress = getChironTestflowProgress(base);
    base.testflow_status = failedProgress.testflow_status;
    base.testflow_completed_at =
      failedProgress.testflow_status === "complete"
        ? cleanText(existing.testflow_completed_at, 64) || updatedAt
        : null;
    return base;
  }

  base.testflow_last_error = null;

  if (status === "vertrek" && cleanRit && !departureRits.includes(cleanRit)) {
    base.test_departure_sent_count = progress.test_departure_sent_count + 1;
    base.test_messages_sent_count = progress.test_messages_sent_count + 1;
    base.testflow_ritnummers_departure = _chironTestflowAppendRit(departureRits, cleanRit);
  } else if (status === "aankomst" && cleanRit && !arrivalRits.includes(cleanRit)) {
    base.test_arrival_sent_count = progress.test_arrival_sent_count + 1;
    base.test_messages_sent_count = progress.test_messages_sent_count + 1;
    base.testflow_ritnummers_arrival = _chironTestflowAppendRit(arrivalRits, cleanRit);
    if (!completedRits.includes(cleanRit)) {
      base.test_rides_completed_count = progress.test_rides_completed_count + 1;
      base.testflow_ritnummers_completed = _chironTestflowAppendRit(completedRits, cleanRit);
    }
  }

  const newProgress = getChironTestflowProgress(base);
  base.testflow_status = newProgress.testflow_status;
  base.testflow_completed_at =
    newProgress.testflow_status === "complete"
      ? cleanText(existing.testflow_completed_at, 64) || updatedAt
      : null;
  return base;
}

function buildChironTestflowResetStatusDoc(
  existingStored,
  tenantId,
  companyId,
  updatedAt,
  updatedBy,
) {
  const existing =
    existingStored && typeof existingStored === "object" && !Array.isArray(existingStored)
      ? { ...existingStored }
      : {};

  // Reset only testflow counters/status + ritnummer history. Credentials,
  // last_connection_status and environment are preserved. production_enabled is
  // forced false because a reset invalidates any prior completion (stricter).
  return {
    ...existing,
    schema_version: CHIRON_CONNECTION_STATUS_SCHEMA,
    tenant_id: tenantId,
    company_id: companyId,
    production_enabled: false,
    test_messages_sent_count: 0,
    test_departure_sent_count: 0,
    test_arrival_sent_count: 0,
    test_rides_completed_count: 0,
    testflow_ritnummers_departure: [],
    testflow_ritnummers_arrival: [],
    testflow_ritnummers_completed: [],
    testflow_status: "not_started",
    testflow_completed_at: null,
    testflow_last_error: null,
    testflow_updated_at: updatedAt,
    updated_at: updatedAt,
    updated_by: updatedBy,
  };
}

function defaultChironConnectionStatusDoc(tenantId, companyId) {
  return {
    ok: true,
    schema_version: CHIRON_CONNECTION_STATUS_SCHEMA,
    tenant_id: tenantId,
    company_id: companyId,
    enabled: false,
    environment: "test",
    region: "flanders",
    production_enabled: false,
    test_credentials_stored: false,
    production_credentials_stored: false,
    last_connection_status: "never_tested",
    last_connection_test_at: null,
    last_connection_status_message: "",
    official_submit_enabled: false,
    official_submission_performed_at: null,
    test_messages_required: 10,
    test_messages_sent_count: 0,
    // Chiron Connect 4C: acceptance testflow defaults.
    test_rides_required: CHIRON_TESTFLOW_DEFAULT_RIDES_REQUIRED,
    test_departure_required: CHIRON_TESTFLOW_DEFAULT_DEPARTURE_REQUIRED,
    test_arrival_required: CHIRON_TESTFLOW_DEFAULT_ARRIVAL_REQUIRED,
    test_departure_sent_count: 0,
    test_arrival_sent_count: 0,
    test_rides_completed_count: 0,
    testflow_status: "not_started",
    testflow_completed_at: null,
    testflow_updated_at: null,
    testflow_last_error: null,
    updated_at: null,
  };
}

function buildChironConnectionKvKey(tenantId, companyId) {
  const tenant = cleanText(tenantId, 128);
  const company = cleanText(companyId, 128);
  if (!tenant || !company) return null;
  return `tenant:${tenant}:company:${company}:${CHIRON_CONNECTION_KV_SUFFIX}`;
}

function _normalizeChironConfigBodyKey(value) {
  return cleanText(value, 64).toLowerCase().replace(/[\s_-]/g, "");
}

function chironConfigBodyHasForbiddenKeys(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) return false;
  for (const key of Object.keys(body)) {
    if (CHIRON_CONFIG_FORBIDDEN_BODY_KEYS.has(_normalizeChironConfigBodyKey(key))) {
      return true;
    }
  }
  return false;
}

function parseChironConfigStatusScope(body, url) {
  const tenantId = cleanText(
    body?.tenant_id ?? url?.searchParams?.get("tenant_id"),
    128,
  );
  const companyId = cleanText(
    body?.company_id ?? url?.searchParams?.get("company_id"),
    128,
  );
  if (!tenantId || !companyId) {
    return { error: "missing_scope" };
  }
  return { tenantId, companyId };
}

function _resolveChironConfigUpdatedBy(request) {
  const proxyMode = cleanText(request.headers.get("x-fluxidi-internal-proxy"), 64);
  if (proxyMode === CHIRON_INTERNAL_PROXY_MODE) return "proxy";
  return "admin_or_company_session";
}

function buildChironInternalTestPassedStatusFields({
  testedAt,
  environment,
  maskedIdentifier,
  credentialFingerprintShort,
}) {
  const envRaw = cleanText(environment, 32).toLowerCase();
  const safeEnvironment = CHIRON_CONNECTION_ALLOWED_ENVIRONMENTS.has(envRaw) ? envRaw : "test";
  return {
    internal_test_status: "passed",
    internal_test_passed: true,
    last_internal_test_at: testedAt,
    last_internal_test_environment: safeEnvironment,
    last_internal_test_mock_only: true,
    last_internal_test_external_call_performed: false,
    last_internal_test_credential_decrypt_ok: true,
    last_internal_test_credential_payload_valid: true,
    last_internal_test_masked_identifier: maskedIdentifier,
    last_internal_test_fingerprint_short: credentialFingerprintShort,
  };
}

// Chiron Connect 4B: status-doc fragment written after a successful OAuth2
// client_credentials exchange. last_connection_status flips to "test_passed",
// production stays gated by parseChironConfigStatusPostInput.
function buildChironOAuthLiveTestPassedStatusFields({
  testedAt,
  environment,
  tokenType,
  expiresInSeconds,
}) {
  const envRaw = cleanText(environment, 32).toLowerCase();
  const safeEnvironment = CHIRON_CONNECTION_ALLOWED_ENVIRONMENTS.has(envRaw) ? envRaw : "test";
  return {
    last_connection_status: "test_passed",
    last_connection_test_at: testedAt,
    last_connection_status_message: null,
    last_connection_environment: safeEnvironment,
    last_connection_auth_scheme: "oauth_client_credentials",
    last_connection_external_call_performed: true,
    last_connection_token_type: cleanText(tokenType, 32) || "Bearer",
    last_connection_access_token_obtained: true,
    last_connection_expires_in_seconds:
      Number.isFinite(expiresInSeconds) && expiresInSeconds >= 0
        ? Math.floor(expiresInSeconds)
        : null,
    last_connection_sanitized_error: null,
  };
}

function buildChironOAuthLiveTestFailedStatusFields({
  testedAt,
  environment,
  sanitizedError,
}) {
  const envRaw = cleanText(environment, 32).toLowerCase();
  const safeEnvironment = CHIRON_CONNECTION_ALLOWED_ENVIRONMENTS.has(envRaw) ? envRaw : "test";
  return {
    last_connection_status: "test_failed",
    last_connection_test_at: testedAt,
    last_connection_status_message: cleanText(sanitizedError, 256) || null,
    last_connection_environment: safeEnvironment,
    last_connection_auth_scheme: "oauth_client_credentials",
    last_connection_external_call_performed: true,
    last_connection_token_type: null,
    last_connection_access_token_obtained: false,
    last_connection_expires_in_seconds: null,
    last_connection_sanitized_error: cleanText(sanitizedError, 256) || null,
  };
}

function buildChironInternalTestStatusResponseFields(stored) {
  if (!stored || typeof stored !== "object" || Array.isArray(stored)) {
    return {};
  }
  const statusRaw = cleanText(stored.internal_test_status, 32).toLowerCase();
  if (!CHIRON_INTERNAL_TEST_ALLOWED_STATUSES.has(statusRaw)) {
    return {};
  }
  const envRaw = cleanText(stored.last_internal_test_environment, 32).toLowerCase();
  return {
    internal_test_status: statusRaw,
    internal_test_passed: stored.internal_test_passed === true,
    last_internal_test_at: cleanText(stored.last_internal_test_at, 64) || null,
    last_internal_test_environment: CHIRON_CONNECTION_ALLOWED_ENVIRONMENTS.has(envRaw)
      ? envRaw
      : null,
    last_internal_test_mock_only: stored.last_internal_test_mock_only === true,
    last_internal_test_external_call_performed:
      stored.last_internal_test_external_call_performed === true,
    last_internal_test_credential_decrypt_ok:
      stored.last_internal_test_credential_decrypt_ok === true,
    last_internal_test_credential_payload_valid:
      stored.last_internal_test_credential_payload_valid === true,
    last_internal_test_masked_identifier:
      cleanText(stored.last_internal_test_masked_identifier, 64) || null,
    last_internal_test_fingerprint_short:
      cleanText(stored.last_internal_test_fingerprint_short, 32) || null,
  };
}

function buildChironConnectionStatusResponse(tenantId, companyId, stored) {
  const defaults = defaultChironConnectionStatusDoc(tenantId, companyId);
  if (!stored || typeof stored !== "object" || Array.isArray(stored)) {
    return defaults;
  }

  const rawStatus = cleanText(stored.last_connection_status, 64).toLowerCase();
  const lastConnectionStatus = CHIRON_CONNECTION_ALLOWED_STATUSES.has(rawStatus)
    ? rawStatus
    : defaults.last_connection_status;

  const environmentRaw = cleanText(stored.environment, 32).toLowerCase();
  const environment = CHIRON_CONNECTION_ALLOWED_ENVIRONMENTS.has(environmentRaw)
    ? environmentRaw
    : defaults.environment;

  const regionRaw = cleanText(stored.region, 32).toLowerCase();
  const region = CHIRON_CONNECTION_ALLOWED_REGIONS.has(regionRaw)
    ? regionRaw
    : defaults.region;

  // Chiron Connect 4C: testflow progress (with defaults for older docs).
  const testflow = getChironTestflowProgress(stored);

  // Production stays false unless the OAuth test passed AND the full acceptance
  // testflow is complete. OAuth test_passed alone is never sufficient.
  const productionEnabled =
    stored.production_enabled === true &&
    lastConnectionStatus === "test_passed" &&
    testflow.testflow_status === "complete";

  return {
    ok: true,
    schema_version: CHIRON_CONNECTION_STATUS_SCHEMA,
    tenant_id: tenantId,
    company_id: companyId,
    enabled: stored.enabled === true,
    environment,
    region,
    production_enabled: productionEnabled,
    test_credentials_stored: stored.test_credentials_stored === true,
    production_credentials_stored: stored.production_credentials_stored === true,
    last_connection_status: lastConnectionStatus,
    last_connection_test_at: cleanText(stored.last_connection_test_at, 64) || null,
    last_connection_status_message:
      cleanText(stored.last_connection_status_message, 256) || "",
    official_submit_enabled: false,
    official_submission_performed_at:
      cleanText(stored.official_submission_performed_at, 64) || null,
    test_messages_required: testflow.test_messages_required,
    test_messages_sent_count: testflow.test_messages_sent_count,
    // Chiron Connect 4C: acceptance testflow projection.
    test_rides_required: testflow.test_rides_required,
    test_departure_required: testflow.test_departure_required,
    test_arrival_required: testflow.test_arrival_required,
    test_departure_sent_count: testflow.test_departure_sent_count,
    test_arrival_sent_count: testflow.test_arrival_sent_count,
    test_rides_completed_count: testflow.test_rides_completed_count,
    testflow_status: testflow.testflow_status,
    testflow_completed_at: testflow.testflow_completed_at,
    testflow_updated_at: testflow.testflow_updated_at,
    testflow_last_error: testflow.testflow_last_error,
    updated_at: cleanText(stored.updated_at, 64) || null,
    ...buildChironInternalTestStatusResponseFields(stored),
  };
}

async function readChironConnectionStatusRaw(env, tenantId, companyId) {
  if (!env?.COMPLIANCE_KV || typeof env.COMPLIANCE_KV.get !== "function") {
    return { doc: null, error: "missing_kv" };
  }
  const key = buildChironConnectionKvKey(tenantId, companyId);
  if (!key) return { doc: null, error: "missing_scope" };
  try {
    const raw = await env.COMPLIANCE_KV.get(key);
    if (!raw) return { doc: null, key };
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      return { doc: null, key };
    }
    return { doc: parsed, key };
  } catch (_) {
    return { doc: null, key, error: "kv_read_failed" };
  }
}

async function writeChironConnectionStatusRaw(env, tenantId, companyId, doc) {
  if (!env?.COMPLIANCE_KV || typeof env.COMPLIANCE_KV.put !== "function") {
    return { ok: false, error: "missing_kv" };
  }
  const key = buildChironConnectionKvKey(tenantId, companyId);
  if (!key) return { ok: false, error: "missing_scope" };
  try {
    await env.COMPLIANCE_KV.put(key, JSON.stringify(doc));
    return { ok: true, key };
  } catch (_) {
    return { ok: false, error: "kv_write_failed" };
  }
}

function parseChironConfigStatusPostInput(body, existingStored) {
  const existing = existingStored && typeof existingStored === "object" ? existingStored : {};
  const existingStatusRaw = cleanText(existing.last_connection_status, 64).toLowerCase();
  const existingStatus = CHIRON_CONNECTION_ALLOWED_STATUSES.has(existingStatusRaw)
    ? existingStatusRaw
    : "never_tested";

  const enabled =
    typeof body?.enabled === "boolean" ? body.enabled : existing.enabled === true;

  const environmentRaw = cleanText(
    body?.environment ?? existing.environment ?? "test",
    32,
  ).toLowerCase();
  if (!CHIRON_CONNECTION_ALLOWED_ENVIRONMENTS.has(environmentRaw)) {
    return { error: "invalid_environment" };
  }

  const regionRaw = cleanText(body?.region ?? existing.region ?? "flanders", 32).toLowerCase();
  if (!CHIRON_CONNECTION_ALLOWED_REGIONS.has(regionRaw)) {
    return { error: "invalid_region" };
  }

  const productionEnabledRequested =
    typeof body?.production_enabled === "boolean"
      ? body.production_enabled
      : existing.production_enabled === true;

  if (productionEnabledRequested && existingStatus !== "test_passed") {
    return { error: "production_requires_test_passed" };
  }

  const testMessagesSent = Number(existing.test_messages_sent_count);
  const safeTestMessagesSent =
    Number.isFinite(testMessagesSent) && testMessagesSent >= 0
      ? Math.floor(testMessagesSent)
      : 0;
  const testMessagesRequiredRaw = Number(existing.test_messages_required);
  const safeTestMessagesRequired =
    Number.isFinite(testMessagesRequiredRaw) && testMessagesRequiredRaw >= 0
      ? Math.floor(testMessagesRequiredRaw)
      : CHIRON_OAUTH_DEFAULT_TEST_MESSAGES_REQUIRED;

  // Chiron Connect 4B: tighten production gate. Even with last_connection_status
  // === "test_passed" (now reachable via the live OAuth2 exchange), production
  // remains blocked until the operator has completed the required test message
  // run. Default required count is 10.
  if (
    productionEnabledRequested &&
    safeTestMessagesSent < safeTestMessagesRequired
  ) {
    return { error: "production_requires_test_messages_complete" };
  }

  // Chiron Connect 4C: production also requires the full acceptance testflow
  // (5 departures + 5 arrivals across 5 unique rides) to be complete. This is
  // strictly additive: it can only block, never unlock.
  const testflowProgress = getChironTestflowProgress(existing);
  if (productionEnabledRequested && testflowProgress.testflow_status !== "complete") {
    return { error: "production_requires_testflow_complete" };
  }

  const productionEnabledFinal =
    productionEnabledRequested &&
    existingStatus === "test_passed" &&
    safeTestMessagesSent >= safeTestMessagesRequired &&
    testflowProgress.testflow_status === "complete";

  return {
    value: {
      schema_version: CHIRON_CONNECTION_STATUS_SCHEMA,
      enabled,
      environment: environmentRaw,
      region: regionRaw,
      production_enabled: productionEnabledFinal,
      last_connection_status: existingStatus,
      last_connection_test_at: cleanText(existing.last_connection_test_at, 64) || null,
      last_connection_status_message:
        cleanText(existing.last_connection_status_message, 256) || "",
      test_messages_sent_count: safeTestMessagesSent,
      test_messages_required: safeTestMessagesRequired,
      // Chiron Connect 4C: preserve acceptance testflow progress across config
      // status writes so a toggle save never wipes the counters/history.
      test_rides_required: testflowProgress.test_rides_required,
      test_departure_required: testflowProgress.test_departure_required,
      test_arrival_required: testflowProgress.test_arrival_required,
      test_departure_sent_count: testflowProgress.test_departure_sent_count,
      test_arrival_sent_count: testflowProgress.test_arrival_sent_count,
      test_rides_completed_count: testflowProgress.test_rides_completed_count,
      testflow_status: testflowProgress.testflow_status,
      testflow_completed_at: testflowProgress.testflow_completed_at,
      testflow_updated_at: testflowProgress.testflow_updated_at,
      testflow_last_error: testflowProgress.testflow_last_error,
      testflow_ritnummers_departure: _chironTestflowRitList(
        existing.testflow_ritnummers_departure,
      ),
      testflow_ritnummers_arrival: _chironTestflowRitList(
        existing.testflow_ritnummers_arrival,
      ),
      testflow_ritnummers_completed: _chironTestflowRitList(
        existing.testflow_ritnummers_completed,
      ),
      official_submission_performed_at:
        cleanText(existing.official_submission_performed_at, 64) || null,
    },
  };
}

async function handleChironConfigStatusGet(request, url, env, origin) {
  const tenant = parseRequiredQuerySegment(url, "tenant_id");
  if (tenant.error) {
    return jsonResponse({ ok: false, error: tenant.error }, 400, origin);
  }
  const company = parseRequiredQuerySegment(url, "company_id");
  if (company.error) {
    return jsonResponse({ ok: false, error: company.error }, 400, origin);
  }

  const tenantId = cleanText(url.searchParams.get("tenant_id"), 128);
  const companyId = cleanText(url.searchParams.get("company_id"), 128);

  const authError = ensureAuthorizedOrInternalProxy(request, env, {
    tenantId,
    companyId,
  });
  if (authError) return authError;

  if (!env?.COMPLIANCE_KV || typeof env.COMPLIANCE_KV.get !== "function") {
    return jsonResponse(
      {
        ok: false,
        error: "Compliance storage is not configured (missing COMPLIANCE_KV binding).",
      },
      500,
      origin,
    );
  }

  const readResult = await readChironConnectionStatusRaw(env, tenantId, companyId);
  if (readResult.error === "missing_kv") {
    return jsonResponse(
      {
        ok: false,
        error: "Compliance storage is not configured (missing COMPLIANCE_KV binding).",
      },
      500,
      origin,
    );
  }

  const source = readResult.doc ? "kv" : "default";
  const payload = buildChironConnectionStatusResponse(tenantId, companyId, readResult.doc);
  console.log(
    `[CHIRON_CONFIG_STATUS] tenant=${_chironMaskScopeId(tenantId)} company=${_chironMaskScopeId(companyId)} result=ok source=${source}`,
  );
  return jsonResponse(payload, 200, origin);
}

async function handleChironConfigStatusPost(request, url, env, origin) {
  if (!requireJsonRequest(request)) {
    return jsonResponse(
      { ok: false, error: "Content-Type must be application/json" },
      400,
      origin,
    );
  }

  const body = await readJsonBody(request);
  if (body === null) {
    return jsonResponse({ ok: false, error: "Invalid JSON body" }, 400, origin);
  }
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return jsonResponse({ ok: false, error: "Invalid JSON body" }, 400, origin);
  }

  if (chironConfigBodyHasForbiddenKeys(body)) {
    return jsonResponse({ ok: false, error: "forbidden_fields" }, 400, origin);
  }

  const scope = parseChironConfigStatusScope(body, url);
  if (scope.error) {
    return jsonResponse({ ok: false, error: scope.error }, 400, origin);
  }

  const { tenantId, companyId } = scope;

  const authError = ensureAuthorizedOrInternalProxy(request, env, {
    tenantId,
    companyId,
  });
  if (authError) return authError;

  if (!env?.COMPLIANCE_KV || typeof env.COMPLIANCE_KV.put !== "function") {
    return jsonResponse(
      {
        ok: false,
        error: "Compliance storage is not configured (missing COMPLIANCE_KV binding).",
      },
      500,
      origin,
    );
  }

  const readResult = await readChironConnectionStatusRaw(env, tenantId, companyId);
  const parsed = parseChironConfigStatusPostInput(body, readResult.doc);
  if (parsed.error) {
    const status = parsed.error === "production_requires_test_passed" ? 400 : 400;
    return jsonResponse({ ok: false, error: parsed.error }, status, origin);
  }

  const updatedAt = nowIso();
  const storedDoc = {
    ...parsed.value,
    tenant_id: tenantId,
    company_id: companyId,
    updated_at: updatedAt,
    updated_by: _resolveChironConfigUpdatedBy(request),
  };

  const writeResult = await writeChironConnectionStatusRaw(env, tenantId, companyId, storedDoc);
  if (!writeResult.ok) {
    return jsonResponse({ ok: false, error: writeResult.error || "kv_write_failed" }, 500, origin);
  }

  const payload = buildChironConnectionStatusResponse(tenantId, companyId, storedDoc);
  console.log(
    `[CHIRON_CONFIG_STATUS_WRITE] tenant=${_chironMaskScopeId(tenantId)} company=${_chironMaskScopeId(companyId)} result=ok enabled=${payload.enabled} environment=${payload.environment}`,
  );
  return jsonResponse(payload, 200, origin);
}

async function handleChironConfigStatus(request, url, env, origin) {
  if (request.method === "GET") {
    return handleChironConfigStatusGet(request, url, env, origin);
  }
  if (request.method === "POST") {
    return handleChironConfigStatusPost(request, url, env, origin);
  }
  return jsonResponse({ ok: false, error: "Method Not Allowed" }, 405, origin);
}

async function handleChironConfigTestCredentialsPost(request, url, env, origin) {
  if (!requireJsonRequest(request)) {
    return jsonResponse(
      { ok: false, error: "Content-Type must be application/json" },
      400,
      origin,
    );
  }

  const body = await readJsonBody(request);
  if (body === null) {
    return jsonResponse({ ok: false, error: "Invalid JSON body" }, 400, origin);
  }

  const parsed = parseChironTestCredentialsPostInput(body);
  if (parsed.error) {
    return jsonResponse({ ok: false, error: parsed.error }, 400, origin);
  }

  const { tenantId, companyId, authScheme } = parsed;

  const authError = ensureAuthorizedOrInternalProxy(request, env, {
    tenantId,
    companyId,
  });
  if (authError) return authError;

  if (!env?.COMPLIANCE_KV || typeof env.COMPLIANCE_KV.put !== "function") {
    return jsonResponse({ ok: false, error: "missing_kv" }, 500, origin);
  }

  // Chiron Connect 4A: build the encrypted plaintext envelope, fingerprint seed
  // and masked identifier per auth scheme. The client_secret is only ever used
  // for encryption + fingerprinting; it never appears in a response or log.
  let plaintextEnvelope;
  let fingerprintSeed;
  let maskedSeed;
  if (authScheme === "oauth_client_credentials") {
    plaintextEnvelope = JSON.stringify({
      schema_version: CHIRON_CREDENTIALS_PAYLOAD_SCHEMA_VERSION,
      auth_scheme: authScheme,
      client_id: parsed.clientId,
      client_secret: parsed.clientSecret,
    });
    // Fingerprint must not be derivable from the public client_id alone, so it
    // is seeded with client_id + ":" + client_secret.
    fingerprintSeed = `${parsed.clientId}:${parsed.clientSecret}`;
    // Masked identifier is based on the public client_id, never the secret.
    maskedSeed = parsed.clientId;
  } else {
    plaintextEnvelope = JSON.stringify({
      schema_version: CHIRON_CREDENTIALS_PAYLOAD_SCHEMA_VERSION,
      auth_scheme: authScheme,
      api_token: parsed.apiToken,
    });
    fingerprintSeed = parsed.apiToken;
    maskedSeed = parsed.apiToken;
  }

  let credentialPayloadEncrypted;
  let credentialFingerprintShort;
  let maskedIdentifier;
  try {
    credentialPayloadEncrypted = await encryptChironCredentialBlob(plaintextEnvelope, env);
    credentialFingerprintShort = await chironCredentialFingerprintShort(fingerprintSeed);
    maskedIdentifier = chironMaskTrailingIdentifier(maskedSeed);
  } catch (_) {
    return jsonResponse({ ok: false, error: "credential_encrypt_failed" }, 500, origin);
  }

  const credentialsKey = buildChironCredentialsKvKey(tenantId, companyId, "test");
  if (!credentialsKey) {
    return jsonResponse({ ok: false, error: "missing_scope" }, 400, origin);
  }

  const existingCredentials = await readChironCredentialsRaw(
    env,
    tenantId,
    companyId,
    "test",
  );
  const updatedAt = nowIso();
  const hadExisting =
    existingCredentials.doc &&
    typeof existingCredentials.doc === "object" &&
    !Array.isArray(existingCredentials.doc);
  const preservedCreatedAt = hadExisting
    ? cleanText(existingCredentials.doc.created_at, 64)
    : "";

  const credentialsDoc = {
    schema_version: CHIRON_CREDENTIALS_SCHEMA_VERSION,
    tenant_id: tenantId,
    company_id: companyId,
    environment: "test",
    auth_scheme: authScheme,
    credential_payload_encrypted: credentialPayloadEncrypted,
    credential_fingerprint_short: credentialFingerprintShort,
    masked_identifier: maskedIdentifier,
    created_at: preservedCreatedAt || updatedAt,
    updated_at: updatedAt,
    rotated_at: hadExisting ? updatedAt : null,
  };

  const credentialsWrite = await writeChironCredentialsRaw(
    env,
    credentialsKey,
    credentialsDoc,
  );
  if (!credentialsWrite.ok) {
    return jsonResponse(
      { ok: false, error: credentialsWrite.error || "kv_write_failed" },
      500,
      origin,
    );
  }

  const statusRead = await readChironConnectionStatusRaw(env, tenantId, companyId);
  const statusDoc = buildChironTestCredentialsStatusDoc(
    statusRead.doc,
    tenantId,
    companyId,
    updatedAt,
    _resolveChironConfigUpdatedBy(request),
  );

  const statusWrite = await writeChironConnectionStatusRaw(
    env,
    tenantId,
    companyId,
    statusDoc,
  );
  if (!statusWrite.ok) {
    return jsonResponse(
      { ok: false, error: statusWrite.error || "kv_write_failed" },
      500,
      origin,
    );
  }

  return jsonResponse(
    {
      ok: true,
      schema_version: CHIRON_CREDENTIALS_SCHEMA_VERSION,
      tenant_id: tenantId,
      company_id: companyId,
      environment: "test",
      auth_scheme: authScheme,
      test_credentials_stored: true,
      credential_fingerprint_short: credentialFingerprintShort,
      masked_identifier: maskedIdentifier,
      updated_at: updatedAt,
    },
    200,
    origin,
  );
}

// Chiron Connect 4C: reset only the acceptance testflow counters/status for a
// tenant/company. Credentials, last_connection_status and environment are left
// untouched; production stays locked.
async function handleChironTestflowResetPost(request, url, env, origin) {
  if (!requireJsonRequest(request)) {
    return jsonResponse(
      { ok: false, error: "Content-Type must be application/json" },
      400,
      origin,
    );
  }

  const body = await readJsonBody(request);
  if (body === null) {
    return jsonResponse({ ok: false, error: "Invalid JSON body" }, 400, origin);
  }

  // Reuse the strict clear-input parser: it only accepts tenant_id/company_id
  // and rejects any secret-bearing or forbidden top-level keys.
  const parsed = parseChironTestCredentialsClearInput(body);
  if (parsed.error) {
    return jsonResponse({ ok: false, error: parsed.error }, 400, origin);
  }

  const { tenantId, companyId } = parsed;

  const authError = ensureAuthorizedOrInternalProxy(request, env, {
    tenantId,
    companyId,
  });
  if (authError) return authError;

  if (!env?.COMPLIANCE_KV || typeof env.COMPLIANCE_KV.put !== "function") {
    return jsonResponse({ ok: false, error: "missing_kv" }, 500, origin);
  }

  const updatedAt = nowIso();
  const statusRead = await readChironConnectionStatusRaw(env, tenantId, companyId);
  const statusDoc = buildChironTestflowResetStatusDoc(
    statusRead.doc,
    tenantId,
    companyId,
    updatedAt,
    _resolveChironConfigUpdatedBy(request),
  );

  const statusWrite = await writeChironConnectionStatusRaw(
    env,
    tenantId,
    companyId,
    statusDoc,
  );
  if (!statusWrite.ok) {
    return jsonResponse(
      { ok: false, error: statusWrite.error || "kv_write_failed" },
      500,
      origin,
    );
  }

  const statusPayload = buildChironConnectionStatusResponse(
    tenantId,
    companyId,
    statusDoc,
  );

  console.log(
    `[CHIRON_TESTFLOW_RESET] tenant=${_chironMaskScopeId(
      tenantId,
    )} company=${_chironMaskScopeId(companyId)} result=ok`,
  );

  return jsonResponse(
    {
      ok: true,
      tenant_id: tenantId,
      company_id: companyId,
      testflow_status: statusPayload.testflow_status,
      test_messages_sent_count: statusPayload.test_messages_sent_count,
      test_departure_sent_count: statusPayload.test_departure_sent_count,
      test_arrival_sent_count: statusPayload.test_arrival_sent_count,
      test_rides_completed_count: statusPayload.test_rides_completed_count,
      test_messages_required: statusPayload.test_messages_required,
      test_departure_required: statusPayload.test_departure_required,
      test_arrival_required: statusPayload.test_arrival_required,
      test_rides_required: statusPayload.test_rides_required,
      last_connection_status: statusPayload.last_connection_status,
      production_enabled: statusPayload.production_enabled,
      updated_at: updatedAt,
    },
    200,
    origin,
  );
}

async function handleChironConfigTestCredentialsClearPost(request, url, env, origin) {
  if (!requireJsonRequest(request)) {
    return jsonResponse(
      { ok: false, error: "Content-Type must be application/json" },
      400,
      origin,
    );
  }

  const body = await readJsonBody(request);
  if (body === null) {
    return jsonResponse({ ok: false, error: "Invalid JSON body" }, 400, origin);
  }

  const parsed = parseChironTestCredentialsClearInput(body);
  if (parsed.error) {
    return jsonResponse({ ok: false, error: parsed.error }, 400, origin);
  }

  const { tenantId, companyId } = parsed;

  const authError = ensureAuthorizedOrInternalProxy(request, env, {
    tenantId,
    companyId,
  });
  if (authError) return authError;

  if (
    !env?.COMPLIANCE_KV ||
    typeof env.COMPLIANCE_KV.delete !== "function" ||
    typeof env.COMPLIANCE_KV.put !== "function"
  ) {
    return jsonResponse({ ok: false, error: "missing_kv" }, 500, origin);
  }

  const credentialsDelete = await deleteChironCredentialsRaw(
    env,
    tenantId,
    companyId,
    "test",
  );
  if (!credentialsDelete.ok) {
    return jsonResponse(
      { ok: false, error: credentialsDelete.error || "kv_delete_failed" },
      500,
      origin,
    );
  }

  const updatedAt = nowIso();
  const statusRead = await readChironConnectionStatusRaw(env, tenantId, companyId);
  const statusDoc = buildChironTestCredentialsClearedStatusDoc(
    statusRead.doc,
    tenantId,
    companyId,
    updatedAt,
    _resolveChironConfigUpdatedBy(request),
  );

  const statusWrite = await writeChironConnectionStatusRaw(
    env,
    tenantId,
    companyId,
    statusDoc,
  );
  if (!statusWrite.ok) {
    return jsonResponse(
      { ok: false, error: statusWrite.error || "kv_write_failed" },
      500,
      origin,
    );
  }

  const statusPayload = buildChironConnectionStatusResponse(
    tenantId,
    companyId,
    statusDoc,
  );

  console.log(
    `[CHIRON_CONFIG_TEST_CREDENTIALS_CLEAR] tenant=${_chironMaskScopeId(tenantId)} company=${_chironMaskScopeId(companyId)} result=ok`,
  );

  return jsonResponse(
    {
      ok: true,
      test_credentials_stored: false,
      internal_test_status_cleared: true,
      production_credentials_stored: statusPayload.production_credentials_stored,
      last_connection_status: statusPayload.last_connection_status,
      production_enabled: statusPayload.production_enabled,
      official_submit_enabled: statusPayload.official_submit_enabled,
      updated_at: updatedAt,
    },
    200,
    origin,
  );
}

async function handleChironConnectionTestPost(request, url, env, origin) {
  if (!requireJsonRequest(request)) {
    return jsonResponse(
      { ok: false, error: "Content-Type must be application/json" },
      400,
      origin,
    );
  }

  const body = await readJsonBody(request);
  if (body === null) {
    return jsonResponse({ ok: false, error: "Invalid JSON body" }, 400, origin);
  }

  const parsed = parseChironConnectionTestPostInput(body);
  if (parsed.error) {
    return jsonResponse({ ok: false, error: parsed.error }, 400, origin);
  }

  const { tenantId, companyId, environment } = parsed;

  const authError = ensureAuthorizedOrInternalProxy(request, env, {
    tenantId,
    companyId,
  });
  if (authError) return authError;

  if (!env?.COMPLIANCE_KV || typeof env.COMPLIANCE_KV.get !== "function") {
    return jsonResponse({ ok: false, error: "missing_kv" }, 500, origin);
  }

  const credentialsRead = await readChironCredentialsRaw(
    env,
    tenantId,
    companyId,
    environment,
  );
  if (!credentialsRead.doc) {
    return jsonResponse({ ok: false, error: "missing_test_credentials" }, 404, origin);
  }

  const credentialsDoc = credentialsRead.doc;
  if (!_chironCredentialsDocReadyForMockTest(credentialsDoc)) {
    return jsonResponse({ ok: false, error: "invalid_credential_payload" }, 400, origin);
  }

  let decryptedPlaintext = "";
  try {
    decryptedPlaintext = await decryptChironCredentialBlob(
      credentialsDoc.credential_payload_encrypted,
      env,
    );
  } catch (_) {
    return jsonResponse({ ok: false, error: "credential_decrypt_failed" }, 500, origin);
  }

  let decryptedPayload = null;
  try {
    decryptedPayload = JSON.parse(decryptedPlaintext);
  } catch (_) {
    return jsonResponse({ ok: false, error: "invalid_credential_payload" }, 400, origin);
  }

  if (!_chironDecryptedCredentialPayloadValid(decryptedPayload)) {
    return jsonResponse({ ok: false, error: "invalid_credential_payload" }, 400, origin);
  }

  const credentialFingerprintShort = cleanText(
    credentialsDoc.credential_fingerprint_short,
    32,
  );
  const maskedIdentifier = cleanText(credentialsDoc.masked_identifier, 64);
  const testedAt = nowIso();
  const decryptedAuthScheme =
    cleanText(decryptedPayload.auth_scheme, 64).toLowerCase() ||
    cleanText(credentialsDoc.auth_scheme, 64).toLowerCase() ||
    "api_token";

  const statusRead = await readChironConnectionStatusRaw(env, tenantId, companyId);
  const existingStatusDoc =
    statusRead.doc && typeof statusRead.doc === "object" && !Array.isArray(statusRead.doc)
      ? statusRead.doc
      : {};

  // Chiron Connect 4B: live OAuth2 client_credentials exchange branch. Only
  // engaged when the stored credential is an oauth_client_credentials envelope.
  // Legacy api_token credentials keep the existing mock-only behaviour below.
  if (decryptedAuthScheme === "oauth_client_credentials") {
    const exchangeResult = await _chironExchangeOAuthClientCredentials(env, {
      environment,
      clientId: decryptedPayload.client_id,
      clientSecret: decryptedPayload.client_secret,
    });

    if (exchangeResult.ok) {
      const liveFields = buildChironOAuthLiveTestPassedStatusFields({
        testedAt,
        environment,
        tokenType: exchangeResult.token_type,
        expiresInSeconds: exchangeResult.expires_in_seconds,
      });
      const statusDocToWrite = {
        ...existingStatusDoc,
        ...liveFields,
        updated_at: testedAt,
      };

      const statusWrite = await writeChironConnectionStatusRaw(
        env,
        tenantId,
        companyId,
        statusDocToWrite,
      );
      if (!statusWrite.ok) {
        return jsonResponse(
          { ok: false, error: statusWrite.error || "kv_write_failed" },
          500,
          origin,
        );
      }

      const statusPayload = buildChironConnectionStatusResponse(
        tenantId,
        companyId,
        statusDocToWrite,
      );

      console.log(
        `[CHIRON_CONNECTION_TEST][OAUTH][PASSED] tenant=${_chironMaskScopeId(
          tenantId,
        )} company=${_chironMaskScopeId(companyId)} env=${environment} expires_in=${
          liveFields.last_connection_expires_in_seconds ?? "null"
        }`,
      );

      return jsonResponse(
        {
          ok: true,
          mock_only: false,
          external_call_performed: true,
          tenant_id: tenantId,
          company_id: companyId,
          environment,
          auth_scheme: "oauth_client_credentials",
          test_credentials_stored: true,
          credential_decrypt_ok: true,
          credential_payload_valid: true,
          credential_fingerprint_short: credentialFingerprintShort,
          masked_identifier: maskedIdentifier,
          access_token_obtained: true,
          token_type: "Bearer",
          expires_in_seconds: liveFields.last_connection_expires_in_seconds,
          last_connection_status: statusPayload.last_connection_status,
          production_enabled: false,
          official_submit_enabled: false,
          updated_at: testedAt,
        },
        200,
        origin,
      );
    }

    const sanitizedError =
      cleanText(exchangeResult.sanitized_error, 256) ||
      cleanText(exchangeResult.error, 256) ||
      "oauth_token_exchange_failed";
    const failedFields = buildChironOAuthLiveTestFailedStatusFields({
      testedAt,
      environment,
      sanitizedError,
    });
    const statusDocToWrite = {
      ...existingStatusDoc,
      ...failedFields,
      updated_at: testedAt,
    };

    const statusWrite = await writeChironConnectionStatusRaw(
      env,
      tenantId,
      companyId,
      statusDocToWrite,
    );
    if (!statusWrite.ok) {
      return jsonResponse(
        { ok: false, error: statusWrite.error || "kv_write_failed" },
        500,
        origin,
      );
    }

    const statusPayload = buildChironConnectionStatusResponse(
      tenantId,
      companyId,
      statusDocToWrite,
    );

    console.log(
      `[CHIRON_CONNECTION_TEST][OAUTH][FAILED] tenant=${_chironMaskScopeId(
        tenantId,
      )} company=${_chironMaskScopeId(companyId)} env=${environment} http_status=${
        exchangeResult.http_status ?? "null"
      } error=${cleanText(exchangeResult.error, 64) || "unknown"}`,
    );

    return jsonResponse(
      {
        ok: false,
        external_call_performed: true,
        tenant_id: tenantId,
        company_id: companyId,
        environment,
        auth_scheme: "oauth_client_credentials",
        error: cleanText(exchangeResult.error, 64) || "oauth_token_exchange_failed",
        sanitized_error: sanitizedError,
        last_connection_status: statusPayload.last_connection_status,
        production_enabled: false,
        official_submit_enabled: false,
        updated_at: testedAt,
      },
      400,
      origin,
    );
  }

  // Legacy api_token: existing mock-only behaviour preserved exactly.
  const internalTestFields = buildChironInternalTestPassedStatusFields({
    testedAt,
    environment,
    maskedIdentifier,
    credentialFingerprintShort,
  });

  const statusDocToWrite = {
    ...existingStatusDoc,
    ...internalTestFields,
    updated_at: testedAt,
  };

  const statusWrite = await writeChironConnectionStatusRaw(
    env,
    tenantId,
    companyId,
    statusDocToWrite,
  );
  if (!statusWrite.ok) {
    return jsonResponse(
      { ok: false, error: statusWrite.error || "kv_write_failed" },
      500,
      origin,
    );
  }

  const statusPayload = buildChironConnectionStatusResponse(
    tenantId,
    companyId,
    statusDocToWrite,
  );

  return jsonResponse(
    {
      ok: true,
      mock_only: true,
      external_call_performed: false,
      tenant_id: tenantId,
      company_id: companyId,
      environment,
      auth_scheme: decryptedAuthScheme || "api_token",
      test_credentials_stored: true,
      credential_decrypt_ok: true,
      credential_payload_valid: true,
      credential_fingerprint_short: credentialFingerprintShort,
      masked_identifier: maskedIdentifier,
      ...buildChironInternalTestStatusResponseFields(statusDocToWrite),
      last_connection_status: statusPayload.last_connection_status,
      production_enabled: false,
      official_submit_enabled: false,
      updated_at: testedAt,
    },
    200,
    origin,
  );
}

// RELEASE-P0-OFFICIAL-CHIRON-OAUTH-SUBMIT-2026-07-31: internal helpers
// intentionally exposed for tests only. This surface exists solely so the
// OAuth-derived bearer / duplicate-guard / ambiguous-transport code paths
// can be exercised deterministically without spinning up the full
// event-hydration pipeline. NEVER import these from production code.
export const __testInternals = {
  _chironEvaluateSubmitDuplicateGuard,
  _chironAcquireOAuthAccessTokenForSubmit,
  _chironPostChironExportTestPayload,
  encryptChironCredentialBlob,
  buildChironCredentialsKvKey,
  CHIRON_CREDENTIALS_PAYLOAD_SCHEMA_VERSION,
  CHIRON_CREDENTIALS_SCHEMA_VERSION,
  buildChironExportStatusKey,
  CHIRON_EXPORT_STATUS_SCHEMA,
  safeSegment,
  chironExportTestModeEnabled,
  _chironTestflowLiveGate,
  _chironExportBaseUrlLooksTestOrAcc,
  chironOfficialRegistratieWire,
  chironOfficialKentekenplaatWire,
  buildChironTaxiritApiPayload,
  normalizeChironKboRegistration,
  buildChironOfficialIdempotencyKey,
};

export default {
  async fetch(request, env) {
    const origin = request.headers.get("origin") || "*";
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: {
          "access-control-allow-origin": origin,
          "access-control-allow-methods": "GET, POST, OPTIONS",
          "access-control-allow-headers": "content-type, authorization, x-admin-token",
          "access-control-max-age": "86400",
        },
      });
    }

    if (
      url.pathname !== APPEND_PATH &&
      url.pathname !== RECENT_PATH &&
      url.pathname !== ADMIN_RESET_PATH &&
      url.pathname !== ADMIN_RESET_DRY_RUN_PATH &&
      url.pathname !== CHIRON_DRYRUN_BUILD_PATH &&
      url.pathname !== CHIRON_DRYRUN_RECENT_PATH &&
      url.pathname !== CHIRON_SCORE_SUMMARY_PATH &&
      url.pathname !== CHIRON_EXPORT_DRY_RUN_PATH &&
      url.pathname !== CHIRON_EXPORT_TEST_PATH &&
      url.pathname !== CHIRON_READINESS_PATH &&
      url.pathname !== CHIRON_CONFIG_STATUS_PATH &&
      url.pathname !== CHIRON_CONFIG_TEST_CREDENTIALS_PATH &&
      url.pathname !== CHIRON_CONFIG_TEST_CREDENTIALS_CLEAR_PATH &&
      url.pathname !== CHIRON_CONNECTION_TEST_PATH &&
      url.pathname !== CHIRON_TESTFLOW_RESET_PATH &&
      url.pathname !== CHIRON_TESTFLOW_SUBMIT_ONE_PATH &&
      url.pathname !== CHIRON_TAXIRIT_VERIFY_CONFIRM_SYNCED_PATH &&
      url.pathname !== CHIRON_TAXIRIT_VERIFY_MARK_RETRYABLE_PATH
    ) {
      return jsonResponse(
        { ok: false, error: "Not Found", path: url.pathname },
        404,
        origin,
      );
    }

    try {
      if (url.pathname === APPEND_PATH) {
        if (request.method !== "POST") {
          return jsonResponse({ ok: false, error: "Method Not Allowed" }, 405, origin);
        }
        return await handleAppend(request, env, origin);
      }
      if (url.pathname === ADMIN_RESET_DRY_RUN_PATH) {
        if (request.method !== "GET") {
          return jsonResponse({ ok: false, error: "Method Not Allowed" }, 405, origin);
        }
        if (!allowDevResetEndpoints(env)) {
          return jsonResponse({ ok: false, error: "dev reset endpoints are disabled" }, 403, origin);
        }
        return await handleAdminResetComplianceEvents(request, url, env, origin, true);
      }
      if (url.pathname === ADMIN_RESET_PATH) {
        if (request.method !== "POST") {
          return jsonResponse({ ok: false, error: "Method Not Allowed" }, 405, origin);
        }
        if (!allowDevResetEndpoints(env)) {
          return jsonResponse({ ok: false, error: "dev reset endpoints are disabled" }, 403, origin);
        }
        return await handleAdminResetComplianceEvents(request, url, env, origin, false);
      }
      if (url.pathname === CHIRON_DRYRUN_BUILD_PATH) {
        if (request.method !== "POST") {
          return jsonResponse({ ok: false, error: "Method Not Allowed" }, 405, origin);
        }
        return await handleChironDryrunBuildFromEvent(request, env, origin);
      }
      if (url.pathname === CHIRON_DRYRUN_RECENT_PATH) {
        if (request.method !== "GET") {
          return jsonResponse({ ok: false, error: "Method Not Allowed" }, 405, origin);
        }
        return await handleChironDryrunRecent(request, url, env, origin);
      }
      if (url.pathname === CHIRON_SCORE_SUMMARY_PATH) {
        if (request.method !== "GET") {
          return jsonResponse({ ok: false, error: "Method Not Allowed" }, 405, origin);
        }
        return await handleChironScoreSummary(request, url, env, origin);
      }
      if (url.pathname === CHIRON_EXPORT_DRY_RUN_PATH) {
        if (request.method !== "POST") {
          return jsonResponse({ ok: false, error: "Method Not Allowed" }, 405, origin);
        }
        return await handleChironExportDryRun(request, url, env, origin);
      }
      if (url.pathname === CHIRON_EXPORT_TEST_PATH) {
        if (request.method !== "POST") {
          return jsonResponse({ ok: false, error: "Method Not Allowed" }, 405, origin);
        }
        return await handleChironExportTest(request, env, origin);
      }
      if (url.pathname === CHIRON_READINESS_PATH) {
        return await handleChironReadinessReport(request, url, env, origin);
      }
      if (url.pathname === CHIRON_CONFIG_STATUS_PATH) {
        return await handleChironConfigStatus(request, url, env, origin);
      }
      if (url.pathname === CHIRON_CONFIG_TEST_CREDENTIALS_PATH) {
        if (request.method !== "POST") {
          return jsonResponse({ ok: false, error: "Method Not Allowed" }, 405, origin);
        }
        return await handleChironConfigTestCredentialsPost(request, url, env, origin);
      }
      if (url.pathname === CHIRON_CONFIG_TEST_CREDENTIALS_CLEAR_PATH) {
        if (request.method !== "POST") {
          return jsonResponse({ ok: false, error: "Method Not Allowed" }, 405, origin);
        }
        return await handleChironConfigTestCredentialsClearPost(request, url, env, origin);
      }
      if (url.pathname === CHIRON_CONNECTION_TEST_PATH) {
        if (request.method !== "POST") {
          return jsonResponse({ ok: false, error: "Method Not Allowed" }, 405, origin);
        }
        return await handleChironConnectionTestPost(request, url, env, origin);
      }
      if (url.pathname === CHIRON_TESTFLOW_RESET_PATH) {
        if (request.method !== "POST") {
          return jsonResponse({ ok: false, error: "Method Not Allowed" }, 405, origin);
        }
        return await handleChironTestflowResetPost(request, url, env, origin);
      }
      if (url.pathname === CHIRON_TESTFLOW_SUBMIT_ONE_PATH) {
        if (request.method !== "POST") {
          return jsonResponse({ ok: false, error: "Method Not Allowed" }, 405, origin);
        }
        return await handleChironTestflowSubmitOnePost(request, env, origin);
      }
      if (url.pathname === CHIRON_TAXIRIT_VERIFY_CONFIRM_SYNCED_PATH) {
        if (request.method !== "POST") {
          return jsonResponse({ ok: false, error: "Method Not Allowed" }, 405, origin);
        }
        return await handleChironTaxiritVerificationConfirmSynced(request, env, origin);
      }
      if (url.pathname === CHIRON_TAXIRIT_VERIFY_MARK_RETRYABLE_PATH) {
        if (request.method !== "POST") {
          return jsonResponse({ ok: false, error: "Method Not Allowed" }, 405, origin);
        }
        return await handleChironTaxiritVerificationMarkRetryable(request, env, origin);
      }
      if (request.method !== "GET") {
        return jsonResponse({ ok: false, error: "Method Not Allowed" }, 405, origin);
      }
      return await handleRecent(request, url, env, origin);
    } catch (_) {
      return jsonResponse({ ok: false, error: "Internal error" }, 500, origin);
    }
  },
};
