const ALLOWED_EVENT_TYPES = new Set([
  "ride_start",
  "ride_stop",
  "payment_update",
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

function projectRecentEvent(key, parsedEvent) {
  const event = parsedEvent && typeof parsedEvent === "object" && !Array.isArray(parsedEvent)
    ? parsedEvent
    : {};
  return {
    key,
    event_id: cleanText(event.event_id, 200) || null,
    event_type: cleanText(event.event_type, 64) || null,
    ride_type: cleanText(event.ride_type, 64) || null,
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
      url.pathname !== ADMIN_RESET_DRY_RUN_PATH
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
        return await handleAdminResetComplianceEvents(request, url, env, origin, true);
      }
      if (url.pathname === ADMIN_RESET_PATH) {
        if (request.method !== "POST") {
          return jsonResponse({ ok: false, error: "Method Not Allowed" }, 405, origin);
        }
        return await handleAdminResetComplianceEvents(request, url, env, origin, false);
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
