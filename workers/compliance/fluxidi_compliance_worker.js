const ALLOWED_EVENT_TYPES = new Set([
  "ride_start",
  "ride_stop",
  "payment_update",
  "booking_status_update",
  "booking_credit_decision",
  "booking_mollie_refund",
  "correction_event",
  "sync_success",
  "sync_failed",
]);

const SCHEMA_VERSION = "compliance_event_v1";
const SYNC_STATE = "not_configured";
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
  "ride_start",
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
    ...refundAudit,
  };
}

async function handleRecent(request, url, env, origin) {
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

  const events = [];
  let malformedCount = 0;
  for (const key of scannedKeyNames) {
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
      events.push(projectRecentEvent(key, parsed));
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
  const limitedEvents = sortedEvents.slice(0, requestedLimit);
  const hasMoreCandidates = hitScanCap || sortedEvents.length > requestedLimit;

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

function chironExportTestModeEnabled(env) {
  return (
    cleanText(env?.CHIRON_EXPORT_MODE, 32).toLowerCase() === "test" &&
    cleanText(env?.CHIRON_EXPORT_BASE_URL, 512).length > 0 &&
    cleanText(env?.CHIRON_EXPORT_API_TOKEN, 512).length > 0
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
  return cleanText(
    String(message ?? "")
      .replace(/Bearer\s+\S+/gi, "[redacted]")
      .replace(/token[=:]\s*\S+/gi, "token=[redacted]"),
    256,
  );
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

// Chiron-6B-1: stricter readiness validation for official ride payloads.
function isValidChironCoordinate(value, kind) {
  if (value === null || value === undefined || value === "") return false;
  const num = Number(value);
  if (!Number.isFinite(num)) return false;
  if (kind === "lat" && (num < -90 || num > 90)) return false;
  if (kind === "lng" && (num < -180 || num > 180)) return false;
  return true;
}

function isInvalidZeroCoordinatePair(lng, lat) {
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
  return (
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
    null
  );
}

function _chironResolveOfficialRegistratie(event) {
  const profile = _chironOfficialNestedProfile(event);
  const raw = _chironOfficialPickProfileField(
    event,
    profile,
    "kbo_number",
    "kboNumber",
    "company_registration_number",
    "companyRegistrationNumber",
    "enterprise_number",
    "enterpriseNumber",
    "registratie",
  );
  return normalizeChironKboRegistration(raw);
}

function _chironResolveOfficialNaam(event) {
  const profile = _chironOfficialNestedProfile(event);
  return (
    cleanText(
      _chironOfficialPickProfileField(
        event,
        profile,
        "legal_name",
        "legalName",
        "company_name",
        "companyName",
        "naam",
      ),
      256,
    ) || null
  );
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

  // 1. Event-level (includes nested business/company profile on the event).
  let registratie = _chironResolveOfficialRegistratie(safeEvent);
  let naam = _chironResolveOfficialNaam(safeEvent);
  let source = registratie || naam ? "event" : "missing";

  // 2. Blueprint-level profile fallback, only if present in already-projected data.
  if (!registratie || !naam) {
    const bpProfile = _chironOfficialBlueprintProfile(safeBlueprint);
    if (bpProfile) {
      if (!registratie) {
        const candidate = normalizeChironKboRegistration(
          _chironOfficialPickProfileField(
            {},
            bpProfile,
            "kbo_number",
            "kboNumber",
            "company_registration_number",
            "companyRegistrationNumber",
            "enterprise_number",
            "enterpriseNumber",
            "registratie",
          ),
        );
        if (candidate) {
          registratie = candidate;
          if (source === "missing") source = "blueprint";
        }
      }
      if (!naam) {
        const candidate =
          cleanText(
            _chironOfficialPickProfileField(
              {},
              bpProfile,
              "legal_name",
              "legalName",
              "company_name",
              "companyName",
              "naam",
            ),
            256,
          ) || null;
        if (candidate) {
          naam = candidate;
          if (source === "missing") source = "blueprint";
        }
      }
    }
  }

  return {
    registratie: registratie || null,
    naam: naam || null,
    source,
  };
}

function hydrateChironOfficialVehicleIdentity(event, blueprint, context = {}) {
  const safeEvent = event && typeof event === "object" && !Array.isArray(event) ? event : {};
  const safeBlueprint =
    blueprint && typeof blueprint === "object" && !Array.isArray(blueprint) ? blueprint : {};
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

  if (!plate) {
    const bpVehicle =
      safeBlueprint.vehicle &&
      typeof safeBlueprint.vehicle === "object" &&
      !Array.isArray(safeBlueprint.vehicle)
        ? safeBlueprint.vehicle
        : {};
    plate = cleanText(bpVehicle.license_plate, 64);
    if (plate) source = "blueprint";
  }

  return {
    kentekenplaat: plate || null,
    source,
  };
}

function hydrateChironOfficialDriverIdentity(event, blueprint, context = {}) {
  const safeEvent = event && typeof event === "object" && !Array.isArray(event) ? event : {};
  const safeBlueprint =
    blueprint && typeof blueprint === "object" && !Array.isArray(blueprint) ? blueprint : {};
  const eventDriver =
    safeEvent.driver && typeof safeEvent.driver === "object" && !Array.isArray(safeEvent.driver)
      ? safeEvent.driver
      : {};

  // Official driver permit/pass only — never driver name or generic driver id.
  let pass = cleanText(
    eventDriver.badge_id ??
      eventDriver.badgeId ??
      eventDriver.driver_pass_number ??
      eventDriver.driverPassNumber ??
      eventDriver.permit_number ??
      eventDriver.permitNumber ??
      eventDriver.license_id ??
      eventDriver.licenseId,
    96,
  );
  let source = pass ? "event" : "missing";

  if (!pass) {
    const bpDriver =
      safeBlueprint.driver &&
      typeof safeBlueprint.driver === "object" &&
      !Array.isArray(safeBlueprint.driver)
        ? safeBlueprint.driver
        : {};
    pass =
      cleanText(bpDriver.badge_id, 96) ||
      cleanText(bpDriver.license_id, 96) ||
      cleanText(bpDriver.driver_pass_number, 96) ||
      cleanText(bpDriver.permit_number, 96);
    if (pass) source = "blueprint";
  }

  return {
    bestuurderspasnummer: pass || null,
    source,
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

  if (officialStatus === "vertrek" || officialStatus === "aankomst") {
    payload.kentekenplaat = vehicle.kentekenplaat || null;
    payload.bestuurderspasnummer = driver.bestuurderspasnummer || null;
    payload.vertrektijdstip = _chironResolveOfficialVertrekTijdstip(safeEvent, safeBlueprint);
    payload.vertrekpunt_lengtegraad = normalizeChironCoordinate(pickup?.lng, "lng");
    payload.vertrekpunt_breedtegraad = normalizeChironCoordinate(pickup?.lat, "lat");
  }

  if (officialStatus === "aankomst") {
    payload.aankomsttijdstip = _chironResolveOfficialAankomstTijdstip(safeEvent, safeBlueprint);
    payload.aankomstpunt_lengtegraad = normalizeChironCoordinate(dropoff?.lng, "lng");
    payload.aankomstpunt_breedtegraad = normalizeChironCoordinate(dropoff?.lat, "lat");
    payload.afstand = normalizeChironMoney(fare.distance_km);
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
  };

  const payload = buildChironOfficialPayloadDraft(
    safeEvent,
    safeBlueprint,
    scope,
    normalized.status,
    hydrated,
  );
  const validation = validateChironOfficialPayloadDraft(payload, {
    category: normalized.category,
    officialStatus: normalized.status,
    ritnummer: payload.ritnummer,
    batchRitStatuses: context.batchRitStatuses || null,
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
    },
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
      { batchRitStatuses: options.batchRitStatuses || null },
    );
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

  const limitedEntries = sortedFiltered.slice(0, requestedLimit);
  const hasMoreCandidates = hitScanCap || sortedFiltered.length > requestedLimit;

  return {
    limitedEntries,
    malformedCount,
    scannedCount: keyNames.length,
    hasMoreCandidates,
  };
}

function _chironBuildExportDryRunPayloadResponse(
  tenantId,
  companyId,
  limit,
  collectResult,
  includeRaw,
  includeOfficialDraft = false,
) {
  const batchRitStatuses = includeOfficialDraft
    ? _chironBuildBatchRitStatusIndex(collectResult.limitedEntries)
    : null;
  const payloads = collectResult.limitedEntries.map((entry) =>
    buildChironExportPayload(entry.event, entry.key, {
      includeRaw,
      includeOfficialDraft,
      batchRitStatuses,
    }),
  );
  const exportableCount = payloads.filter((payload) => payload.exportable).length;
  const sampleCandidates = [
    ...payloads.filter((payload) => payload.exportable),
    ...payloads.filter((payload) => !payload.exportable),
  ];
  const samplePayloads = sampleCandidates.slice(0, CHIRON_EXPORT_MAX_SAMPLE_PAYLOADS);

  return {
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

async function _chironPostChironExportTestPayload(env, payload) {
  const baseUrl = cleanText(env?.CHIRON_EXPORT_BASE_URL, 512).replace(/\/+$/, "");
  const token = cleanText(env?.CHIRON_EXPORT_API_TOKEN, 512);
  if (!baseUrl || !token) {
    return { ok: false, error: "chiron_export_test_mode_disabled" };
  }

  let response;
  try {
    response = await fetch(baseUrl, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${token}`,
      },
      body: JSON.stringify(payload),
    });
  } catch (err) {
    return {
      ok: false,
      external_status_code: null,
      sanitized_error: _chironSanitizeExportError(err?.message || "network_error"),
    };
  }

  let responseBody = null;
  const contentType = cleanText(response.headers.get("content-type"), 128).toLowerCase();
  if (contentType.includes("application/json")) {
    try {
      responseBody = await response.json();
    } catch (_) {
      responseBody = null;
    }
  }

  if (!response.ok) {
    const message =
      (responseBody &&
        typeof responseBody === "object" &&
        cleanText(responseBody.error ?? responseBody.message, 256)) ||
      `HTTP ${response.status}`;
    return {
      ok: false,
      external_status_code: response.status,
      sanitized_error: _chironSanitizeExportError(message),
      external_reference: _chironExtractExternalReference(responseBody),
    };
  }

  return {
    ok: true,
    external_status_code: response.status,
    external_reference: _chironExtractExternalReference(responseBody),
    sanitized_error: null,
  };
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

  const responsePayload = _chironBuildExportDryRunPayloadResponse(
    tenantId,
    companyId,
    limitParsed.value,
    collectResult,
    includeRaw,
    includeOfficialDraft,
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

  const dryRunPayload = _chironBuildExportDryRunPayloadResponse(
    tenantId,
    companyId,
    limitParsed.value,
    collectResult,
    includeRaw,
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
  const payloads = collectResult.limitedEntries.map((entry) =>
    buildChironExportPayload(entry.event, entry.key, { includeRaw: false }),
  );

  for (const payload of payloads) {
    if (!payload.exportable || !payload.event_id) continue;

    const statusKey = buildChironExportStatusKey(
      tenantSegment,
      companySegment,
      payload.event_id,
    );
    const previousStatus = await _chironReadExportStatus(env, statusKey);
    const attemptCount = Number(previousStatus?.attempt_count || 0) + 1;

    const pendingDoc = {
      schema_version: CHIRON_EXPORT_STATUS_SCHEMA,
      tenant_id: tenantId,
      company_id: companyId,
      event_id: payload.event_id,
      sync_state: "pending",
      external_status_code: null,
      external_reference: null,
      last_attempt_at: nowIso,
      attempt_count: attemptCount,
      sanitized_error: null,
    };
    await _chironWriteExportStatus(env, statusKey, pendingDoc);

    const postResult = await _chironPostChironExportTestPayload(env, payload);
    const finalDoc = {
      ...pendingDoc,
      sync_state: postResult.ok ? "synced" : "failed",
      external_status_code: postResult.external_status_code ?? null,
      external_reference: postResult.external_reference ?? null,
      sanitized_error: postResult.sanitized_error ?? null,
      last_attempt_at: new Date().toISOString(),
    };
    await _chironWriteExportStatus(env, statusKey, finalDoc);

    exportAttempts.push({
      event_id: payload.event_id,
      idempotency_key: payload.idempotency_key,
      sync_state: finalDoc.sync_state,
      external_status_code: finalDoc.external_status_code,
      external_reference: finalDoc.external_reference,
      attempt_count: finalDoc.attempt_count,
      sanitized_error: finalDoc.sanitized_error,
      status_key: statusKey,
    });
  }

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
      url.pathname !== CHIRON_EXPORT_TEST_PATH
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
      if (request.method !== "GET") {
        return jsonResponse({ ok: false, error: "Method Not Allowed" }, 405, origin);
      }
      return await handleRecent(request, url, env, origin);
    } catch (_) {
      return jsonResponse({ ok: false, error: "Internal error" }, 500, origin);
    }
  },
};
