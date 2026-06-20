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

  const vehicle = blueprint?.vehicle || {};
  if (!vehicle.vehicle_id && !vehicle.license_plate) {
    missing.push("vehicle_id_or_license_plate");
  }
  const driver = blueprint?.driver || {};
  if (!driver.driver_id && !driver.driver_name) {
    missing.push("driver_id_or_driver_name");
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
  const syncState = cleanText(event?.sync_state, 64) || SYNC_STATE;
  if (syncState === SYNC_STATE) {
    warnings.push("missing_retry_outbox_state");
  }

  const lowerEventType = eventType.toLowerCase();
  if (lowerEventType === "ride_stop") {
    const locations = blueprint?.locations || {};
    if (!locations.pickup || !locations.dropoff) {
      warnings.push("missing_pickup_or_dropoff_for_ride_stop");
    }
  }
  if (lowerEventType === "payment_update") {
    const provider = payment && typeof payment === "object" ? payment.provider : null;
    if (!provider) {
      warnings.push("missing_payment_provider_for_payment_update");
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
      url.pathname !== CHIRON_DRYRUN_RECENT_PATH
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
      if (request.method !== "GET") {
        return jsonResponse({ ok: false, error: "Method Not Allowed" }, 405, origin);
      }
      return await handleRecent(request, url, env, origin);
    } catch (_) {
      return jsonResponse({ ok: false, error: "Internal error" }, 500, origin);
    }
  },
};
