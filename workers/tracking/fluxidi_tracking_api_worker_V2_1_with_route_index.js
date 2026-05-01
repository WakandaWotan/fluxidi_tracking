// Fluxidi Tracking API Worker — V2.1 (Cloudflare Dashboard JS)
// ✅ Full replacement file (paste into Cloudflare "index.js").
//
// Includes everything from V2 + housekeeping + NEW /track/route endpoint.
//
// NEW: POST /track/route  { "from": "Gent", "to": "Kortrijk", "profile": "driving" }
// - Uses server-side Mapbox (token stored as Worker secret MAPBOX_TOKEN)
// - Returns polyline geometry (GeoJSON), distance/duration, and resolved coordinates
// - Keeps Mapbox token off the device/app.
//
// Required secrets/bindings in Cloudflare Worker:
// - ADMIN_TOKEN (secret)
// - MAPBOX_TOKEN (secret)  <-- add this!
// - KV binding named: FLUXIDI_TRACKING
//
// -------------------------------
// Helpers
// -------------------------------
function json(data, init = {}) {
  const headers = new Headers(init.headers);
  headers.set("content-type", "application/json; charset=utf-8");
  return new Response(JSON.stringify(data, null, 2), { ...init, headers });
}

function withCors(resp, origin) {
  const headers = new Headers(resp.headers);
  headers.set("access-control-allow-origin", origin);
  headers.set("access-control-allow-methods", "GET,POST,OPTIONS");
  headers.set("access-control-allow-headers", "content-type,x-admin-token,authorization");
  headers.set("access-control-max-age", "86400");
  return new Response(resp.body, {
    status: resp.status,
    statusText: resp.statusText,
    headers,
  });
}

function getOrigin(req) {
  return req.headers.get("origin") ?? "*";
}

function getBearerToken(req) {
  const a = req.headers.get("authorization");
  if (!a) return "";
  const m = a.match(/^Bearer\s+(.+)$/i);
  return m ? (m[1] || "").trim() : "";
}

function getToken(req, url) {
  const h = req.headers.get("x-admin-token")?.trim();
  if (h) return h;

  const b = getBearerToken(req);
  if (b) return b;

  const q = url.searchParams.get("admin_token")?.trim();
  if (q) return q;

  return "";
}

function requireAdmin(req, url, env) {
  const expected = (env.ADMIN_TOKEN || "").trim();
  if (!expected) {
    throw new Error("ADMIN_TOKEN is not configured on the Worker (set as secret).");
  }
  const got = getToken(req, url);
  if (!got || got !== expected) throw new Error("Unauthorized");
}

function requireMapbox(env) {
  const t = (env.MAPBOX_TOKEN || "").trim();
  if (!t) throw new Error("MAPBOX_TOKEN is not configured on the Worker (set as secret).");
  return t;
}

async function readJson(req) {
  const ct = req.headers.get("content-type") || "";
  if (!ct.toLowerCase().includes("application/json")) {
    throw new Error("Expected application/json");
  }
  return await req.json();
}

function nowIso() {
  return new Date().toISOString();
}

function safeNum(v, min, max) {
  const n = typeof v === "number" ? v : Number(v);
  if (!Number.isFinite(n)) return null;
  return Math.min(max, Math.max(min, n));
}

function safeStr(v, maxLen = 2000) {
  if (typeof v !== "string") return null;
  const s = v.trim();
  if (!s) return null;
  return s.length > maxLen ? s.slice(0, maxLen) : s;
}

const COMPLIANCE_APPEND_PATH = "/compliance/events/append";
const TRACKING_FALLBACK_TENANT_ID = "fluxidi";

function normalizeComplianceText(v, fallback = "unknown", maxLen = 64) {
  const text = safeStr(v, maxLen);
  if (!text) return fallback;
  return text.toLowerCase();
}

function buildComplianceAppendUrl(baseUrlRaw) {
  const normalized = safeStr(baseUrlRaw, 512);
  if (!normalized) return null;
  try {
    const parsed = new URL(normalized);
    parsed.search = "";
    parsed.hash = "";
    const normalizedPath = parsed.pathname.replace(/\/+$/, "");
    if (normalizedPath === COMPLIANCE_APPEND_PATH) {
      return parsed;
    }
    if (normalizedPath === "" || normalizedPath === "/") {
      parsed.pathname = COMPLIANCE_APPEND_PATH;
      return parsed;
    }
    return null;
  } catch (_) {
    return null;
  }
}

function buildDirectTripStopComplianceEvent(trip, stopPayload, stoppedAt, totals) {
  const tenantFromTrip = safeStr(
    trip?.tenant_id ?? trip?.tenantId ?? trip?.company_id ?? trip?.companyId,
    96,
  );
  const tenantFromPayload = safeStr(
    stopPayload?.tenant_id ?? stopPayload?.tenantId ?? stopPayload?.company_id ?? stopPayload?.companyId,
    96,
  );
  const tenantId = tenantFromTrip ?? tenantFromPayload ?? TRACKING_FALLBACK_TENANT_ID;

  const companyFromTrip = safeStr(trip?.company_id ?? trip?.companyId, 96);
  const companyFromPayload = safeStr(stopPayload?.company_id ?? stopPayload?.companyId, 96);
  // TODO: tighten tenant/company authority from a single canonical source.
  const companyId = companyFromTrip ?? companyFromPayload ?? tenantId;

  if (!tenantId || !companyId) return null;

  const pickup = trip?.origin && typeof trip.origin === "object"
    ? {
        label: safeStr(trip.origin.label, 256) ?? null,
        lat: Number.isFinite(Number(trip.origin.lat)) ? Number(trip.origin.lat) : null,
        lng: Number.isFinite(Number(trip.origin.lon)) ? Number(trip.origin.lon) : null,
      }
    : null;
  const dropoff = trip?.destination && typeof trip.destination === "object"
    ? {
        label: safeStr(trip.destination.label, 256) ?? null,
        lat: Number.isFinite(Number(trip.destination.lat)) ? Number(trip.destination.lat) : null,
        lng: Number.isFinite(Number(trip.destination.lon)) ? Number(trip.destination.lon) : null,
      }
    : null;

  const paymentAmountRaw = trip?.payment_amount ?? trip?.paymentAmount;
  const paymentAmount = Number.isFinite(Number(paymentAmountRaw))
    ? Number(paymentAmountRaw)
    : null;
  const fareCurrency =
    (safeStr(totals?.currency, 8) ??
      safeStr(trip?.currency, 8) ??
      safeStr(trip?.pricing_snapshot?.currency, 8) ??
      "EUR").toUpperCase();

  return {
    event_type: "ride_stop",
    tenant_id: tenantId,
    company_id: companyId,
    booking_id: safeStr(trip?.booking_id ?? trip?.bookingId, 128) ?? undefined,
    trip_id: safeStr(trip?.trip_id ?? trip?.tripId, 128) ?? undefined,
    session_id: safeStr(trip?.session_id ?? trip?.sessionId, 128) ?? undefined,
    receipt_reference: safeStr(trip?.receipt_reference ?? trip?.receiptReference, 128) ?? undefined,
    ride_type: "direct",
    lifecycle_status: "stopped",
    timestamps: {
      event_at_utc: stoppedAt,
      started_at_utc: safeStr(trip?.started_at ?? trip?.startedAt ?? trip?.created_at, 64) ?? null,
      stopped_at_utc: stoppedAt,
    },
    driver: {
      driver_id: safeStr(trip?.driver_id ?? trip?.driverId, 96) ?? null,
    },
    vehicle: {
      vehicle_id: safeStr(trip?.vehicle_id ?? trip?.vehicleId, 96) ?? null,
      license_plate: safeStr(trip?.license_plate ?? trip?.licensePlate, 64) ?? undefined,
    },
    locations: {
      pickup,
      dropoff,
    },
    fare: {
      currency: fareCurrency,
      distance_km: Number.isFinite(Number(totals?.km_total)) ? Number(totals.km_total) : null,
      wait_seconds_total: Number.isFinite(Number(totals?.wait_seconds_total))
        ? Number(totals.wait_seconds_total)
        : null,
      total_amount: Number.isFinite(Number(totals?.total_eur)) ? Number(totals.total_eur) : null,
    },
    payment: {
      status: normalizeComplianceText(trip?.payment_status ?? trip?.paymentStatus),
      method: normalizeComplianceText(trip?.payment_method ?? trip?.paymentMethod),
      source: normalizeComplianceText(trip?.payment_source ?? trip?.paymentSource),
      provider: normalizeComplianceText(trip?.payment_provider ?? trip?.paymentProvider),
      amount: paymentAmount ?? undefined,
      currency: fareCurrency,
    },
    provenance: {
      producer: "tracking_worker",
      source_endpoint: "/trip/stop",
      backend_confirmed: true,
      validation_state: "exportable",
    },
  };
}

async function emitComplianceEventBestEffort(env, event, options = {}) {
  try {
    const baseUrlRaw = safeStr(env?.COMPLIANCE_API_URL, 512);
    const adminToken = safeStr(env?.COMPLIANCE_ADMIN_TOKEN, 512);
    if (!baseUrlRaw || !adminToken) {
      return { ok: false, skipped: "missing_config" };
    }
    if (!event || typeof event !== "object" || Array.isArray(event)) {
      return { ok: false, skipped: "invalid_event" };
    }
    const appendUrl = buildComplianceAppendUrl(baseUrlRaw);
    if (!appendUrl) {
      return { ok: false, skipped: "invalid_url_config" };
    }

    const requestedTimeout = Number(options?.timeoutMs);
    const timeoutMs = Number.isFinite(requestedTimeout)
      ? Math.max(1, Math.min(1500, Math.round(requestedTimeout)))
      : 1500;
    const controller = new AbortController();
    const timer = setTimeout(() => {
      controller.abort();
    }, timeoutMs);

    try {
      const req = new Request(appendUrl.toString(), {
        method: "POST",
        headers: {
          "content-type": "application/json",
          authorization: `Bearer ${adminToken}`,
        },
        body: JSON.stringify(event),
        signal: controller.signal,
      });
      const hasServiceBinding = !!(env?.COMPLIANCE_WORKER && typeof env.COMPLIANCE_WORKER.fetch === "function");
      const transport = hasServiceBinding ? "service_binding" : "public_fetch";
      const resp = hasServiceBinding
        ? await env.COMPLIANCE_WORKER.fetch(req)
        : await fetch(req);

      if (!resp.ok) {
        console.log(
          `[COMPLIANCE_EMIT][ride_stop] failed status=${resp.status} transport=${transport} origin=${appendUrl.origin} path=${appendUrl.pathname}`,
        );
        return { ok: false, status: resp.status };
      }
      return { ok: true, status: resp.status };
    } catch (err) {
      if (err?.name === "AbortError") {
        console.log("[COMPLIANCE_EMIT][ride_stop] failed error=timeout");
        return { ok: false, error: "timeout" };
      }
      console.log("[COMPLIANCE_EMIT][ride_stop] failed error=fetch_failed");
      return { ok: false, error: "fetch_failed" };
    } finally {
      clearTimeout(timer);
    }
  } catch (_) {
    return { ok: false, error: "internal_error" };
  }
}

function randToken(len = 20) {
  const alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
  let out = "";
  for (let i = 0; i < len; i++) {
    out += alphabet[Math.floor(Math.random() * alphabet.length)];
  }
  return out;
}

async function kvPutJson(kv, key, value, ttlSeconds) {
  const opts = {};
  if (ttlSeconds && Number.isFinite(ttlSeconds)) {
    opts.expirationTtl = Math.floor(ttlSeconds);
  }
  await kv.put(key, JSON.stringify(value), opts);
}

async function kvGetJson(kv, key) {
  const raw = await kv.get(key);
  if (!raw) return null;
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

async function kvDel(kv, key) {
  try {
    await kv.delete(key);
  } catch {
    // ignore
  }
}

// -------------------------------
// TTLs
// -------------------------------
const TTL_SESSION = 60 * 60 * 24 * 14;      // 14 days
const TTL_LASTPING = 60 * 60 * 24 * 14;     // 14 days
const TTL_INDEX = 60 * 60 * 24 * 30;        // 30 days
const TTL_PUBLIC_TOKEN = 60 * 60 * 24 * 14; // 14 days
const TTL_TRIP = 60 * 60 * 24 * 30;         // 30 days

// -------------------------------
// Mapbox helpers (server-side)
// -------------------------------
async function mapboxGeocode(token, q) {
  const query = encodeURIComponent(q);
  // limit=1 is fine for our driver UI; you can raise later.
  const url =
    `https://api.mapbox.com/geocoding/v5/mapbox.places/${query}.json` +
    `?limit=1&language=nl&country=BE&access_token=${encodeURIComponent(token)}`;

  const r = await fetch(url, { method: "GET" });
  if (!r.ok) throw new Error(`Mapbox geocode failed (${r.status})`);
  const j = await r.json();
  const f = Array.isArray(j.features) ? j.features[0] : null;
  if (!f || !Array.isArray(f.center) || f.center.length < 2) {
    throw new Error("Mapbox geocode: no result");
  }
  const lon = Number(f.center[0]);
  const lat = Number(f.center[1]);
  if (!Number.isFinite(lat) || !Number.isFinite(lon)) {
    throw new Error("Mapbox geocode: invalid coordinates");
  }
  return { lat, lon, place_name: f.place_name || q };
}

async function mapboxDirections(token, from, to, profile = "driving") {
  const prof = (profile || "driving").toString().trim().toLowerCase();
  const allowed = new Set(["driving", "driving-traffic", "walking", "cycling"]);
  const p = allowed.has(prof) ? prof : "driving";

  // Mapbox expects lon,lat;lon,lat
  const coords = `${from.lon},${from.lat};${to.lon},${to.lat}`;
  const url =
    `https://api.mapbox.com/directions/v5/mapbox/${p}/${coords}` +
    `?geometries=geojson&overview=full&steps=false&access_token=${encodeURIComponent(token)}`;

  const r = await fetch(url, { method: "GET" });
  if (!r.ok) throw new Error(`Mapbox directions failed (${r.status})`);
  const j = await r.json();
  const route = Array.isArray(j.routes) ? j.routes[0] : null;
  if (!route || !route.geometry) throw new Error("Mapbox directions: no route");
  return {
    distance_m: Number(route.distance) || 0,
    duration_s: Number(route.duration) || 0,
    geometry: route.geometry, // GeoJSON LineString
  };
}

// -------------------------------
// Direct trip helpers
// -------------------------------
function makeTripId() {
  if (globalThis.crypto && typeof globalThis.crypto.randomUUID === "function") {
    return `trip_${globalThis.crypto.randomUUID()}`;
  }
  return `trip_${Date.now().toString(36)}_${randToken(12)}`;
}

function tripKey(tripId) {
  return `trip:${tripId}`;
}

function money2Num(value) {
  return Math.round((Number(value) || 0) * 100) / 100;
}

function normalizeDestination(v) {
  if (!v || typeof v !== "object") return null;
  const label = safeStr(v.label ?? v.address ?? v.text ?? "", 256);
  const lat = safeNum(v.lat, -90, 90);
  const lon = safeNum(v.lon ?? v.lng, -180, 180);
  const out = {};
  if (label) out.label = label;
  if (lat !== null && lon !== null) {
    out.lat = lat;
    out.lon = lon;
  }
  return Object.keys(out).length ? out : null;
}

function normalizePricingSnapshot(v) {
  if (!v || typeof v !== "object") throw new Error("pricing_snapshot is required");
  const start_fee = safeNum(v.start_fee, 0, 10000);
  const per_km = safeNum(v.per_km, 0, 1000);
  const wait_per_min = safeNum(v.wait_per_min, 0, 1000);
  if (start_fee === null) throw new Error("pricing_snapshot.start_fee is required");
  if (per_km === null) throw new Error("pricing_snapshot.per_km is required");
  if (wait_per_min === null) throw new Error("pricing_snapshot.wait_per_min is required");
  return {
    start_fee,
    per_km,
    wait_per_min,
    currency: safeStr(v.currency ?? "EUR", 8) ?? "EUR",
  };
}

function normalizeBookingDetails(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const allowed = [
    "pickup_address",
    "destination_address",
    "scheduled_pickup_at",
    "subtype",
    "customer_name",
    "customer_phone",
    "customer_email",
    "customerName",
    "customerPhone",
    "customerEmail",
    "name",
    "phone",
    "tel",
    "mobile",
    "email",
    "customer_country",
    "customerCountry",
    "country",
    "countryCode",
    "country_iso",
    "countryIso",
    "locale",
    "language",
    "phone_country_code",
    "phoneCountryCode",
    "dial_code",
    "dialCode",
    "service_type",
    "tier",
    "passengers",
    "luggage_count",
    "booked_wait_minutes",
    "booking_status",
    "booking_total_eur",
    "segment_price_eur",
    "outbound_price_eur",
    "return_price_eur",
    "return_scheduled_pickup_at",
    "return_route",
    "route_segments",
    "stops",
    "extras",
    "notes",
    "currency",
  ];
  const out = {};
  for (const key of allowed) {
    if (!(key in value)) continue;
    const v = value[key];
    if (v === null || v === undefined) continue;
    if (typeof v === "string") {
      const s = safeStr(v, key === "route_segments" ? 4096 : 1024);
      if (s) out[key] = s;
      continue;
    }
    if (typeof v === "number") {
      if (Number.isFinite(v)) out[key] = v;
      continue;
    }
    if (typeof v === "boolean") {
      out[key] = v;
      continue;
    }
    if (key === "route_segments" && Array.isArray(v)) {
      out[key] = v.slice(0, 12).map((segment) => {
        if (!segment || typeof segment !== "object") return null;
        return {
          from: safeStr(segment.from, 1024) ?? null,
          to: safeStr(segment.to, 1024) ?? null,
          distance_km: safeNum(segment.distance_km, 0, 100000),
          duration_min: safeNum(segment.duration_min, 0, 100000),
          kind: safeStr(segment.kind, 32) ?? null,
        };
      }).filter(Boolean);
      continue;
    }
    if (Array.isArray(v)) {
      out[key] = v.slice(0, 20).map((x) => safeStr(x, 512)).filter(Boolean);
    }
  }
  return Object.keys(out).length ? out : null;
}

async function prependIndex(kv, key, value, maxItems) {
  const existing = (await kvGetJson(kv, key)) ?? [];
  const arr = Array.isArray(existing) ? existing : [];
  const next = [value, ...arr.filter((x) => x !== value)].slice(0, maxItems);
  await kvPutJson(kv, key, next, TTL_TRIP);
}

function directTripTotals(trip, kmTotal, waitSecondsTotal) {
  const pricing = trip?.pricing_snapshot || {};
  const startFee = Number(pricing.start_fee) || 0;
  const perKm = Number(pricing.per_km) || 0;
  const waitPerMin = Number(pricing.wait_per_min) || 0;
  const waitMinutes = waitSecondsTotal / 60;
  const total = startFee + (kmTotal * perKm) + (waitMinutes * waitPerMin);
  return {
    km_total: kmTotal,
    wait_seconds_total: waitSecondsTotal,
    wait_minutes: money2Num(waitMinutes),
    total_eur: money2Num(total),
    currency: safeStr(pricing.currency ?? "EUR", 8) ?? "EUR",
  };
}

function summarizeTrip(trip) {
  const origin =
    trip?.origin && typeof trip.origin === "object"
      ? trip.origin
      : null;
  const destination =
    trip?.destination && typeof trip.destination === "object"
      ? trip.destination
      : null;
  const bookingDetails = normalizeBookingDetails(trip?.booking_details);
  return {
    trip_id: trip?.trip_id ?? null,
    kind: trip?.kind ?? null,
    booking_id: trip?.booking_id ?? null,
    tenant_id: trip?.tenant_id ?? null,
    driver_id: trip?.driver_id ?? null,
    vehicle_id: trip?.vehicle_id ?? null,
    status: trip?.status ?? null,
    started_at: trip?.started_at ?? trip?.created_at ?? null,
    stopped_at: trip?.stopped_at ?? null,
    origin: origin
      ? {
          label: origin.label ?? null,
          lat: origin.lat ?? null,
          lon: origin.lon ?? null,
        }
      : null,
    destination: destination
      ? {
          label: destination.label ?? null,
          lat: destination.lat ?? null,
          lon: destination.lon ?? null,
        }
      : null,
    km_total: Number.isFinite(Number(trip?.km_total)) ? Number(trip.km_total) : null,
    wait_seconds_total: Number.isFinite(Number(trip?.wait_seconds_total))
      ? Number(trip.wait_seconds_total)
      : 0,
    total_eur: Number.isFinite(Number(trip?.total_eur)) ? Number(trip.total_eur) : null,
    currency: safeStr(trip?.currency ?? trip?.pricing_snapshot?.currency ?? "EUR", 8) ?? "EUR",
    payment_status: safeStr(trip?.payment_status ?? trip?.paymentStatus ?? "", 32) ?? null,
    paymentStatus: safeStr(trip?.paymentStatus ?? trip?.payment_status ?? "", 32) ?? null,
    payment_method: safeStr(trip?.payment_method ?? trip?.paymentMethod ?? "", 32) ?? null,
    paymentMethod: safeStr(trip?.paymentMethod ?? trip?.payment_method ?? "", 32) ?? null,
    payment_source: safeStr(trip?.payment_source ?? trip?.paymentSource ?? "", 32) ?? null,
    paymentSource: safeStr(trip?.paymentSource ?? trip?.payment_source ?? "", 32) ?? null,
    paid_at: safeStr(trip?.paid_at ?? trip?.paidAt ?? "", 64) ?? null,
    paidAt: safeStr(trip?.paidAt ?? trip?.paid_at ?? "", 64) ?? null,
    paid_by_driver_id: safeStr(trip?.paid_by_driver_id ?? trip?.paidByDriverId ?? "", 96) ?? null,
    paidByDriverId: safeStr(trip?.paidByDriverId ?? trip?.paid_by_driver_id ?? "", 96) ?? null,
    payment_amount: Number.isFinite(Number(trip?.payment_amount))
      ? Number(trip.payment_amount)
      : Number.isFinite(Number(trip?.paymentAmount))
      ? Number(trip.paymentAmount)
      : null,
    paymentAmount: Number.isFinite(Number(trip?.paymentAmount))
      ? Number(trip.paymentAmount)
      : Number.isFinite(Number(trip?.payment_amount))
      ? Number(trip.payment_amount)
      : null,
    booking_details: bookingDetails,
  };
}

// -------------------------------
// Handlers
// -------------------------------
async function handleHealth(req, env, origin) {
  return withCors(
    json({ ok: true, service: "fluxidi-tracking-api", time: nowIso() }, { status: 200 }),
    origin
  );
}

async function handleTripsHistory(req, url, env, origin) {
  requireAdmin(req, url, env);

  const tenant_id = safeStr(url.searchParams.get("tenant_id") ?? url.searchParams.get("company_id") ?? "fluxidi", 96) ?? "fluxidi";
  const driver_id = safeStr(url.searchParams.get("driver_id"), 96);
  const limit = Math.min(200, Math.max(1, Number(url.searchParams.get("limit") || 50)));
  const includeActive = (url.searchParams.get("include_active") || "").toLowerCase() === "1";
  const includeArchived = (url.searchParams.get("include_archived") || "").toLowerCase() === "1";
  const indexKey = driver_id ? `trips_index:${tenant_id}:${driver_id}` : `trips_index:${tenant_id}`;
  const ids = (await kvGetJson(env.FLUXIDI_TRACKING, indexKey)) ?? [];
  const tripIds = Array.isArray(ids) ? ids : [];
  const trips = [];
  const cleaned = [];

  for (const trip_id of tripIds) {
    const safeTripId = safeStr(trip_id, 128);
    if (!safeTripId) continue;
    const trip = await kvGetJson(env.FLUXIDI_TRACKING, tripKey(safeTripId));
    if (!trip) continue;
    cleaned.push(safeTripId);
    if (!includeActive && trip.status === "active") continue;
    if (!includeArchived && trip.archived === true) continue;
    trips.push(summarizeTrip(trip));
    if (trips.length >= limit) break;
  }

  if (cleaned.length !== tripIds.length) {
    await kvPutJson(env.FLUXIDI_TRACKING, indexKey, cleaned.slice(0, driver_id ? 200 : 500), TTL_TRIP);
  }

  return withCors(
    json({ ok: true, tenant_id, driver_id: driver_id ?? null, count: trips.length, trips }, { status: 200 }),
    origin
  );
}

async function handleArchiveTrip(req, url, env, origin) {
  requireAdmin(req, url, env);

  const body = await readJson(req);
  const tenant_id = safeStr(body["tenant_id"] ?? body["company_id"] ?? "fluxidi", 96) ?? "fluxidi";
  const driver_id = safeStr(body["driver_id"], 96);
  const trip_id = safeStr(body["trip_id"], 128);
  if (!trip_id) throw new Error("trip_id is required");

  const key = tripKey(trip_id);
  const trip = await kvGetJson(env.FLUXIDI_TRACKING, key);
  if (!trip) throw new Error("Unknown trip_id");

  const tripTenant = safeStr(trip.tenant_id ?? trip.company_id ?? "fluxidi", 96) ?? "fluxidi";
  if (tripTenant !== tenant_id) throw new Error("Trip tenant mismatch");

  const tripDriver = safeStr(trip.driver_id, 96);
  if (driver_id && tripDriver && tripDriver !== driver_id) {
    throw new Error("Trip driver mismatch");
  }

  const archived = body["archived"] !== false;
  trip.archived = archived;
  if (archived) {
    trip.archived_at = nowIso();
    trip.archived_by = driver_id || "admin";
  } else {
    trip.archived_at = null;
    trip.archived_by = driver_id || "admin";
  }

  await kvPutJson(env.FLUXIDI_TRACKING, key, trip, TTL_TRIP);

  return withCors(
    json({ ok: true, archived, trip_id }, { status: 200 }),
    origin
  );
}

async function handleStartDirectTrip(req, url, env, origin) {
  requireAdmin(req, url, env);

  const body = await readJson(req);
  const tenant_id = safeStr(body["tenant_id"] ?? body["company_id"] ?? "fluxidi", 96) ?? "fluxidi";
  const driver_id = safeStr(body["driver_id"], 96);
  if (!driver_id) throw new Error("driver_id is required");

  const vehicle_id = safeStr(body["vehicle_id"], 96) ?? null;
  const originData = normalizeDestination(body["origin"]);
  const destination = normalizeDestination(body["destination"]);
  const pricing_snapshot = normalizePricingSnapshot(body["pricing_snapshot"]);
  const createdAt = nowIso();
  const startedAt = safeStr(body["client_started_at"], 64) ?? createdAt;
  const trip_id = makeTripId();

  const startEvent = {
    type: "start",
    ts: startedAt,
    source: "driver_app",
  };

  const trip = {
    trip_id,
    kind: "direct",
    tenant_id,
    driver_id,
    vehicle_id,
    origin: originData,
    destination,
    pricing_snapshot,
    status: "active",
    timeline: [startEvent],
    created_at: createdAt,
    started_at: startedAt,
    stopped_at: null,
    wait_started_at: null,
    km_total: null,
    wait_seconds_total: 0,
    total_eur: null,
  };

  await kvPutJson(env.FLUXIDI_TRACKING, tripKey(trip_id), trip, TTL_TRIP);
  await prependIndex(env.FLUXIDI_TRACKING, `trips_index:${tenant_id}`, trip_id, 500);
  await prependIndex(env.FLUXIDI_TRACKING, `trips_index:${tenant_id}:${driver_id}`, trip_id, 200);

  return withCors(
    json(
      {
        ok: true,
        trip_id,
        kind: "direct",
        tenant_id,
        driver_id,
        vehicle_id,
        status: "active",
        created_at: createdAt,
        started_at: startedAt,
      },
      { status: 200 }
    ),
    origin
  );
}

async function handleRecordPlannedStopTrip(req, url, env, origin) {
  requireAdmin(req, url, env);

  const body = await readJson(req);
  const booking_id = safeStr(body["booking_id"], 96);
  if (!booking_id) throw new Error("booking_id is required");

  const tenant_id = safeStr(body["tenant_id"] ?? body["company_id"] ?? "fluxidi", 96) ?? "fluxidi";
  const driver_id = safeStr(body["driver_id"], 96);
  if (!driver_id) throw new Error("driver_id is required");

  const vehicle_id = safeStr(body["vehicle_id"], 96) ?? null;
  const originData = normalizeDestination(body["origin"]);
  const destination = normalizeDestination(body["destination"]);
  const booking_details = normalizeBookingDetails(body["booking_details"]);
  const startedAt = safeStr(body["started_at"] ?? body["client_started_at"], 64) ?? null;
  const stoppedAt = safeStr(body["stopped_at"] ?? body["client_stopped_at"], 64) ?? nowIso();
  const km_total = safeNum(body["km_total"], 0, 100000);
  const wait_seconds_total = safeNum(body["wait_seconds_total"] ?? 0, 0, 60 * 60 * 24 * 7) ?? 0;
  const total_eur = safeNum(body["total_eur"], 0, 1000000);
  const currency = safeStr(body["currency"] ?? "EUR", 8) ?? "EUR";
  const trip_id = `planned_${booking_id}`;

  const trip = {
    trip_id,
    kind: "planned",
    booking_id,
    tenant_id,
    driver_id,
    vehicle_id,
    origin: originData,
    destination,
    booking_details,
    status: "stopped",
    timeline: [
      {
        type: "planned_stop",
        ts: stoppedAt,
        source: "driver_app",
        booking_id,
        km_total,
        wait_seconds_total,
        total_eur,
      },
    ],
    created_at: startedAt ?? stoppedAt,
    started_at: startedAt,
    stopped_at: stoppedAt,
    wait_started_at: null,
    km_total,
    wait_seconds_total,
    total_eur,
    currency,
  };

  await kvPutJson(env.FLUXIDI_TRACKING, tripKey(trip_id), trip, TTL_TRIP);
  await prependIndex(env.FLUXIDI_TRACKING, `trips_index:${tenant_id}`, trip_id, 500);
  await prependIndex(env.FLUXIDI_TRACKING, `trips_index:${tenant_id}:${driver_id}`, trip_id, 200);

  return withCors(
    json(
      {
        ok: true,
        trip_id,
        kind: "planned",
        booking_id,
        status: "stopped",
        stopped_at: stoppedAt,
      },
      { status: 200 }
    ),
    origin
  );
}

async function handleWaitStartTrip(req, url, env, origin) {
  requireAdmin(req, url, env);

  const body = await readJson(req);
  const trip_id = safeStr(body["trip_id"], 128);
  if (!trip_id) throw new Error("trip_id is required");

  const key = tripKey(trip_id);
  const trip = await kvGetJson(env.FLUXIDI_TRACKING, key);
  if (!trip) throw new Error("Unknown trip_id");
  if (trip.status !== "active") throw new Error("Trip is not active");
  if (trip.wait_started_at) {
    return withCors(
      json({ ok: false, error: "Wait already active", trip_id, wait_started_at: trip.wait_started_at }, { status: 409 }),
      origin
    );
  }

  const waitStartedAt = safeStr(body["client_wait_started_at"], 64) ?? nowIso();
  const timeline = Array.isArray(trip.timeline) ? trip.timeline : [];
  timeline.push({
    type: "wait_start",
    ts: waitStartedAt,
    source: "driver_app",
  });

  trip.wait_started_at = waitStartedAt;
  trip.timeline = timeline;
  trip.wait_seconds_total = Number.isFinite(Number(trip.wait_seconds_total))
    ? Number(trip.wait_seconds_total)
    : 0;

  await kvPutJson(env.FLUXIDI_TRACKING, key, trip, TTL_TRIP);

  return withCors(
    json({ ok: true, trip_id, status: "active", wait_started_at: waitStartedAt }, { status: 200 }),
    origin
  );
}

async function handleWaitEndTrip(req, url, env, origin) {
  requireAdmin(req, url, env);

  const body = await readJson(req);
  const trip_id = safeStr(body["trip_id"], 128);
  if (!trip_id) throw new Error("trip_id is required");

  const key = tripKey(trip_id);
  const trip = await kvGetJson(env.FLUXIDI_TRACKING, key);
  if (!trip) throw new Error("Unknown trip_id");
  if (trip.status !== "active") throw new Error("Trip is not active");
  if (!trip.wait_started_at) {
    return withCors(
      json({ ok: false, error: "No active wait", trip_id }, { status: 409 }),
      origin
    );
  }

  const waitEndedAt = safeStr(body["client_wait_ended_at"], 64) ?? nowIso();
  const startedMs = Date.parse(trip.wait_started_at);
  const endedMs = Date.parse(waitEndedAt);
  const addedWaitSeconds =
    Number.isFinite(startedMs) && Number.isFinite(endedMs)
      ? Math.max(0, Math.round((endedMs - startedMs) / 1000))
      : 0;
  const currentWaitSeconds = Number.isFinite(Number(trip.wait_seconds_total))
    ? Number(trip.wait_seconds_total)
    : 0;
  const nextWaitSeconds = currentWaitSeconds + addedWaitSeconds;

  const timeline = Array.isArray(trip.timeline) ? trip.timeline : [];
  timeline.push({
    type: "wait_end",
    ts: waitEndedAt,
    source: "driver_app",
    wait_seconds_added: addedWaitSeconds,
    wait_seconds_total: nextWaitSeconds,
  });

  trip.wait_started_at = null;
  trip.wait_seconds_total = nextWaitSeconds;
  trip.timeline = timeline;

  await kvPutJson(env.FLUXIDI_TRACKING, key, trip, TTL_TRIP);

  return withCors(
    json(
      {
        ok: true,
        trip_id,
        status: "active",
        wait_ended_at: waitEndedAt,
        wait_seconds_added: addedWaitSeconds,
        wait_seconds_total: nextWaitSeconds,
      },
      { status: 200 }
    ),
    origin
  );
}

async function handleStopTrip(req, url, env, origin, ctx) {
  requireAdmin(req, url, env);

  const body = await readJson(req);
  const trip_id = safeStr(body["trip_id"], 128);
  if (!trip_id) throw new Error("trip_id is required");

  const key = tripKey(trip_id);
  const trip = await kvGetJson(env.FLUXIDI_TRACKING, key);
  if (!trip) throw new Error("Unknown trip_id");
  if (trip.status !== "active") throw new Error("Trip is not active");

  const km_total = safeNum(body["km_total"], 0, 100000);
  if (km_total === null) throw new Error("km_total is required");

  const wait_seconds_total = safeNum(body["wait_seconds_total"] ?? 0, 0, 60 * 60 * 24 * 7);
  if (wait_seconds_total === null) throw new Error("wait_seconds_total is invalid");

  const stoppedAt = safeStr(body["client_stopped_at"], 64) ?? nowIso();
  const totals = directTripTotals(trip, km_total, wait_seconds_total);
  const timeline = Array.isArray(trip.timeline) ? trip.timeline : [];
  timeline.push({
    type: "stop",
    ts: stoppedAt,
    source: "driver_app",
    km_total: totals.km_total,
    wait_seconds_total: totals.wait_seconds_total,
    total_eur: totals.total_eur,
  });

  trip.status = "stopped";
  trip.stopped_at = stoppedAt;
  trip.km_total = totals.km_total;
  trip.wait_seconds_total = totals.wait_seconds_total;
  trip.total_eur = totals.total_eur;
  trip.timeline = timeline;

  await kvPutJson(env.FLUXIDI_TRACKING, key, trip, TTL_TRIP);

  const complianceEvent = buildDirectTripStopComplianceEvent(trip, body, stoppedAt, totals);
  if (complianceEvent) {
    const emitTask = emitComplianceEventBestEffort(env, complianceEvent, { timeoutMs: 1500 });
    if (ctx && typeof ctx.waitUntil === "function") {
      ctx.waitUntil(emitTask);
    } else {
      await emitTask;
    }
  }

  return withCors(
    json(
      {
        ok: true,
        trip_id,
        status: "stopped",
        stopped_at: stoppedAt,
        totals,
      },
      { status: 200 }
    ),
    origin
  );
}

async function handleTripPayment(req, url, env, origin) {
  requireAdmin(req, url, env);

  const body = await readJson(req);
  const trip_id = safeStr(body["trip_id"], 128);
  if (!trip_id) throw new Error("trip_id is required");

  const key = tripKey(trip_id);
  const trip = await kvGetJson(env.FLUXIDI_TRACKING, key);
  if (!trip) throw new Error("Unknown trip_id");

  const rawStatus = String(body["payment_status"] ?? body["paymentStatus"] ?? "")
    .trim()
    .toLowerCase();
  const payment_status =
    rawStatus === "paid" ||
    rawStatus === "confirmed" ||
    rawStatus === "completed" ||
    rawStatus === "success" ||
    rawStatus === "settled"
      ? "paid"
      : rawStatus === "pending" || rawStatus === "authorized" || rawStatus === "open"
      ? "pending"
      : rawStatus === "failed" || rawStatus === "cancelled" || rawStatus === "canceled"
      ? "failed"
      : "paid";

  const payment_method = safeStr(
    String(body["payment_method"] ?? body["paymentMethod"] ?? "").toLowerCase(),
    32,
  );
  const payment_source =
    safeStr(
      String(body["payment_source"] ?? body["paymentSource"] ?? "in_car").toLowerCase(),
      32,
    ) ?? "in_car";
  const paid_at = safeStr(body["paid_at"] ?? body["paidAt"], 64) ?? nowIso();
  const currency =
    (safeStr(body["currency"], 8) ??
      safeStr(trip?.currency, 8) ??
      safeStr(trip?.pricing_snapshot?.currency, 8) ??
      "EUR").toUpperCase();
  const amountRaw = body["amount"] ?? body["price"] ?? body["total"];
  const amountNum = Number(amountRaw);
  const amount = Number.isFinite(amountNum) ? amountNum : null;
  const paid_by_driver_id = safeStr(
    body["paid_by_driver_id"] ?? body["paidByDriverId"],
    96,
  );

  trip.payment_status = payment_status;
  trip.paymentStatus = payment_status;
  trip.payment_source = payment_source;
  trip.paymentSource = payment_source;
  trip.paid_at = paid_at;
  trip.paidAt = paid_at;
  trip.currency = currency;
  if (payment_method) {
    trip.payment_method = payment_method;
    trip.paymentMethod = payment_method;
  }
  if (amount !== null) {
    trip.payment_amount = amount;
    trip.paymentAmount = amount;
  }
  if (paid_by_driver_id) {
    trip.paid_by_driver_id = paid_by_driver_id;
    trip.paidByDriverId = paid_by_driver_id;
  }

  const timeline = Array.isArray(trip.timeline) ? trip.timeline : [];
  timeline.push({
    type: "payment_marked",
    ts: paid_at,
    source: "driver_app",
    payment_status,
    payment_method: payment_method ?? null,
    payment_source,
    currency,
    amount,
    paid_by_driver_id: paid_by_driver_id ?? null,
  });
  trip.timeline = timeline;

  await kvPutJson(env.FLUXIDI_TRACKING, key, trip, TTL_TRIP);

  return withCors(
    json(
      {
        ok: true,
        trip_id,
        payment: {
          payment_status,
          payment_method: payment_method ?? null,
          payment_source,
          paid_at,
          currency,
          amount,
          paid_by_driver_id: paid_by_driver_id ?? null,
        },
        trip: summarizeTrip(trip),
      },
      { status: 200 },
    ),
    origin,
  );
}

async function handleStart(req, url, env, origin) {
  requireAdmin(req, url, env);

  const body = await readJson(req);
  const booking_id = safeStr(body["booking_id"], 64);
  if (!booking_id) throw new Error("booking_id is required");

  const pickup = safeStr(body["pickup"], 200) ?? null;
  const dropoff = safeStr(body["dropoff"], 200) ?? null;

  const sessionId = `s_${booking_id}_${Date.now().toString(36)}_${Math.random()
    .toString(36)
    .slice(2, 8)}`;

  const public_token = `p_${randToken(24)}`;

  const session = {
    session_id: sessionId,
    booking_id,
    pickup,
    dropoff,
    status: "active",
    created_at: nowIso(),
    last_ping_at: null,
    points: [],
    public_token,
  };

  await kvPutJson(env.FLUXIDI_TRACKING, `session:${sessionId}`, session, TTL_SESSION);

  const bookingMap = {
    session_id: sessionId,
    created_at: session.created_at,
    pickup,
    dropoff,
    public_token,
  };
  await kvPutJson(env.FLUXIDI_TRACKING, `booking:${booking_id}:session`, bookingMap, TTL_SESSION);

  await kvPutJson(
    env.FLUXIDI_TRACKING,
    `public:${public_token}:booking`,
    { booking_id, session_id: sessionId, created_at: session.created_at },
    TTL_PUBLIC_TOKEN
  );

  const idx = (await kvGetJson(env.FLUXIDI_TRACKING, "booking_index")) ?? [];
  const next = [booking_id, ...idx.filter((x) => x !== booking_id)].slice(0, 200);
  await kvPutJson(env.FLUXIDI_TRACKING, "booking_index", next, TTL_INDEX);

  return withCors(
    json({ ok: true, session_id: sessionId, booking_id, created_at: session.created_at, public_token }, { status: 200 }),
    origin
  );
}

async function handlePing(req, url, env, origin) {
  requireAdmin(req, url, env);

  const body = await readJson(req);
  const session_id = safeStr(body["session_id"], 128);
  if (!session_id) throw new Error("session_id is required");

  const lat = safeNum(body["lat"], -90, 90);
  const lon = safeNum(body["lon"], -180, 180);
  if (lat === null || lon === null) throw new Error("lat/lon invalid");

  const speed = safeNum(body["speed"], 0, 200) ?? null;
  const heading = safeNum(body["heading"], 0, 360) ?? null;

  const sessionKey = `session:${session_id}`;
  const session = await kvGetJson(env.FLUXIDI_TRACKING, sessionKey);
  if (!session) throw new Error("Unknown session_id");

  if (session.status === "stopped") {
    return withCors(json({ ok: false, error: "Session stopped" }, { status: 409 }), origin);
  }

  const point = { lat, lon, ts: nowIso(), speed, heading };

  const points = Array.isArray(session.points) ? session.points : [];
  points.push(point);
  if (points.length > 1200) points.splice(0, points.length - 1200);

  session.points = points;
  session.last_ping_at = point.ts;

  await kvPutJson(env.FLUXIDI_TRACKING, sessionKey, session, TTL_SESSION);
  await kvPutJson(env.FLUXIDI_TRACKING, `ping:${session_id}:last`, point, TTL_LASTPING);

  return withCors(json({ ok: true, session_id, ts: point.ts }, { status: 200 }), origin);
}

async function handleStop(req, url, env, origin) {
  requireAdmin(req, url, env);

  const body = await readJson(req);
  const session_id = safeStr(body["session_id"], 128);
  if (!session_id) throw new Error("session_id is required");

  const sessionKey = `session:${session_id}`;
  const session = await kvGetJson(env.FLUXIDI_TRACKING, sessionKey);
  if (!session) throw new Error("Unknown session_id");

  session.status = "stopped";
  session.stopped_at = nowIso();

  await kvPutJson(env.FLUXIDI_TRACKING, sessionKey, session, TTL_INDEX);

  return withCors(json({ ok: true, session_id, status: "stopped" }, { status: 200 }), origin);
}

// Resolve booking -> map + session + last ping
async function resolveSessionByBooking(env, booking_id) {
  const map = await kvGetJson(env.FLUXIDI_TRACKING, `booking:${booking_id}:session`);
  if (!map || !map.session_id) return null;

  const session = await kvGetJson(env.FLUXIDI_TRACKING, `session:${map.session_id}`);
  const last = await kvGetJson(env.FLUXIDI_TRACKING, `ping:${map.session_id}:last`);
  return { map, session, last };
}

// GET /track/bookings (auto-cleans orphans)
async function handleBookings(req, url, env, origin) {
  requireAdmin(req, url, env);

  const idx = (await kvGetJson(env.FLUXIDI_TRACKING, "booking_index")) ?? [];
  const limit = Math.min(200, Math.max(1, Number(url.searchParams.get("limit") || 50)));

  const bookings = [];
  const cleanedIndex = [];

  for (const booking_id of idx) {
    const map = await kvGetJson(env.FLUXIDI_TRACKING, `booking:${booking_id}:session`);
    if (!map) continue; // orphan index entry: drop it

    cleanedIndex.push(booking_id);

    const last = await kvGetJson(env.FLUXIDI_TRACKING, `ping:${map.session_id}:last`);
    bookings.push({
      booking_id,
      session_id: map.session_id,
      created_at: map.created_at,
      pickup: map.pickup ?? null,
      dropoff: map.dropoff ?? null,
      public_token: map.public_token ?? null,
      last_ping: last ?? null,
    });

    if (bookings.length >= limit) break;
  }

  if (cleanedIndex.length !== idx.length) {
    await kvPutJson(env.FLUXIDI_TRACKING, "booking_index", cleanedIndex, TTL_INDEX);
  }

  return withCors(json({ ok: true, count: bookings.length, bookings }, { status: 200 }), origin);
}

// GET /track/booking?booking_id=...
async function handleBookingDetails(req, url, env, origin) {
  requireAdmin(req, url, env);

  const booking_id = safeStr(url.searchParams.get("booking_id"), 64);
  if (!booking_id) throw new Error("booking_id is required");

  const resolved = await resolveSessionByBooking(env, booking_id);
  if (!resolved) throw new Error("Unknown booking_id");

  const { map, session, last } = resolved;

  return withCors(
    json(
      {
        ok: true,
        booking_id,
        session_id: map.session_id,
        created_at: map.created_at,
        pickup: map.pickup ?? null,
        dropoff: map.dropoff ?? null,
        status: session?.status ?? null,
        last_ping: last ?? null,
        points_count: Array.isArray(session?.points) ? session.points.length : 0,
        public_token: map.public_token ?? session?.public_token ?? null,
      },
      { status: 200 }
    ),
    origin
  );
}

// GET /track/live?booking_id=...&limit=...
async function handleLive(req, url, env, origin) {
  requireAdmin(req, url, env);

  const booking_id = safeStr(url.searchParams.get("booking_id"), 64);
  if (!booking_id) throw new Error("booking_id is required");

  const limit = Math.min(1200, Math.max(1, Number(url.searchParams.get("limit") || 300)));

  const resolved = await resolveSessionByBooking(env, booking_id);
  if (!resolved) throw new Error("Unknown booking_id");

  const { map, session, last } = resolved;

  const points = Array.isArray(session?.points) ? session.points : [];
  const sliced = points.slice(Math.max(0, points.length - limit));

  return withCors(
    json(
      {
        ok: true,
        booking_id,
        session_id: map.session_id,
        status: session?.status ?? null,
        last_ping: last ?? null,
        points: sliced,
      },
      { status: 200 }
    ),
    origin
  );
}

// GET /track/public/live?token=...&limit=...
async function handlePublicLive(req, url, env, origin) {
  const token = safeStr(url.searchParams.get("token"), 128);
  if (!token) throw new Error("token is required");

  const link = await kvGetJson(env.FLUXIDI_TRACKING, `public:${token}:booking`);
  if (!link || !link.booking_id) throw new Error("Invalid token");

  const booking_id = link.booking_id;

  const limit = Math.min(1200, Math.max(1, Number(url.searchParams.get("limit") || 300)));

  const resolved = await resolveSessionByBooking(env, booking_id);
  if (!resolved) throw new Error("Unknown booking_id");

  const { map, session, last } = resolved;
  const points = Array.isArray(session?.points) ? session.points : [];
  const sliced = points.slice(Math.max(0, points.length - limit));

  return withCors(
    json(
      {
        ok: true,
        booking_id,
        session_id: map.session_id,
        status: session?.status ?? null,
        last_ping: last ?? null,
        points: sliced,
      },
      { status: 200 }
    ),
    origin
  );
}

// POST /track/route  { from, to, profile? }
async function handleRoute(req, url, env, origin) {
  requireAdmin(req, url, env);

  const token = requireMapbox(env);

  const body = await readJson(req);
  const fromQ = safeStr(body["from"], 256);
  const toQ = safeStr(body["to"], 256);
  const profile = safeStr(body["profile"], 32) ?? "driving";

  if (!fromQ || !toQ) throw new Error("from/to are required");

  // Geocode both sides
  const from = await mapboxGeocode(token, fromQ);
  const to = await mapboxGeocode(token, toQ);

  // Directions
  const dir = await mapboxDirections(token, from, to, profile);

  return withCors(
    json(
      {
        ok: true,
        from: { query: fromQ, ...from },
        to: { query: toQ, ...to },
        profile,
        distance_m: dir.distance_m,
        duration_s: dir.duration_s,
        geometry: dir.geometry,
      },
      { status: 200 }
    ),
    origin
  );
}

// -------------------------------
// Housekeeping endpoints
// -------------------------------
async function handleDeleteBooking(req, url, env, origin) {
  requireAdmin(req, url, env);

  const body = await readJson(req);
  const booking_id = safeStr(body["booking_id"], 64);
  if (!booking_id) throw new Error("booking_id is required");

  const mapKey = `booking:${booking_id}:session`;
  const map = await kvGetJson(env.FLUXIDI_TRACKING, mapKey);

  if (!map || !map.session_id) {
    const idx = (await kvGetJson(env.FLUXIDI_TRACKING, "booking_index")) ?? [];
    const next = idx.filter((x) => x !== booking_id);
    if (next.length !== idx.length) await kvPutJson(env.FLUXIDI_TRACKING, "booking_index", next, TTL_INDEX);

    return withCors(
      json({ ok: true, deleted: false, booking_id, note: "No map found; removed from index if present." }, { status: 200 }),
      origin
    );
  }

  const session_id = safeStr(map.session_id, 128);
  const public_token = safeStr(map.public_token ?? "", 128) || null;

  await kvDel(env.FLUXIDI_TRACKING, mapKey);
  await kvDel(env.FLUXIDI_TRACKING, `session:${session_id}`);
  await kvDel(env.FLUXIDI_TRACKING, `ping:${session_id}:last`);
  if (public_token) await kvDel(env.FLUXIDI_TRACKING, `public:${public_token}:booking`);

  const idx = (await kvGetJson(env.FLUXIDI_TRACKING, "booking_index")) ?? [];
  const next = idx.filter((x) => x !== booking_id);
  if (next.length !== idx.length) await kvPutJson(env.FLUXIDI_TRACKING, "booking_index", next, TTL_INDEX);

  return withCors(json({ ok: true, deleted: true, booking_id, session_id, public_token }, { status: 200 }), origin);
}

async function handleClearBookings(req, url, env, origin) {
  requireAdmin(req, url, env);
  await kvPutJson(env.FLUXIDI_TRACKING, "booking_index", [], TTL_INDEX);
  return withCors(json({ ok: true, cleared: true, what: "booking_index" }, { status: 200 }), origin);
}

async function handlePurgeOrphans(req, url, env, origin) {
  requireAdmin(req, url, env);

  const idx = (await kvGetJson(env.FLUXIDI_TRACKING, "booking_index")) ?? [];
  const cleaned = [];

  for (const booking_id of idx) {
    const map = await kvGetJson(env.FLUXIDI_TRACKING, `booking:${booking_id}:session`);
    if (!map) continue;
    cleaned.push(booking_id);
  }

  await kvPutJson(env.FLUXIDI_TRACKING, "booking_index", cleaned, TTL_INDEX);

  return withCors(json({ ok: true, before: idx.length, after: cleaned.length, removed: idx.length - cleaned.length }, { status: 200 }), origin);
}

// -------------------------------
// Router
// -------------------------------
export default {
  async fetch(req, env, ctx) {
    const origin = getOrigin(req);
    const url = new URL(req.url);

    if (req.method === "OPTIONS") {
      return withCors(new Response(null, { status: 204 }), origin);
    }

    try {
      if (req.method === "GET" && url.pathname === "/health") return await handleHealth(req, env, origin);

      // direct trips
      if (req.method === "GET" && url.pathname === "/trips/history") return await handleTripsHistory(req, url, env, origin);
      if (req.method === "POST" && url.pathname === "/trips/archive") return await handleArchiveTrip(req, url, env, origin);
      if (req.method === "POST" && url.pathname === "/trip/start-direct") return await handleStartDirectTrip(req, url, env, origin);
      if (req.method === "POST" && url.pathname === "/trip/record-planned-stop") return await handleRecordPlannedStopTrip(req, url, env, origin);
      if (req.method === "POST" && url.pathname === "/trip/wait-start") return await handleWaitStartTrip(req, url, env, origin);
      if (req.method === "POST" && url.pathname === "/trip/wait-end") return await handleWaitEndTrip(req, url, env, origin);
      if (req.method === "POST" && url.pathname === "/trip/stop") return await handleStopTrip(req, url, env, origin, ctx);
      if (req.method === "POST" && url.pathname === "/trip/payment") return await handleTripPayment(req, url, env, origin);

      // core
      if (req.method === "POST" && url.pathname === "/track/session/start") return await handleStart(req, url, env, origin);
      if (req.method === "POST" && url.pathname === "/track/ping") return await handlePing(req, url, env, origin);
      if (req.method === "POST" && url.pathname === "/track/session/stop") return await handleStop(req, url, env, origin);

      if (req.method === "GET" && url.pathname === "/track/bookings") return await handleBookings(req, url, env, origin);
      if (req.method === "GET" && url.pathname === "/track/booking") return await handleBookingDetails(req, url, env, origin);
      if (req.method === "GET" && url.pathname === "/track/live") return await handleLive(req, url, env, origin);
      if (req.method === "GET" && url.pathname === "/track/public/live") return await handlePublicLive(req, url, env, origin);

      // NEW: route
      if (req.method === "POST" && url.pathname === "/track/route") return await handleRoute(req, url, env, origin);

      // housekeeping
      if (req.method === "POST" && url.pathname === "/track/booking/delete") return await handleDeleteBooking(req, url, env, origin);
      if (req.method === "POST" && url.pathname === "/track/bookings/clear") return await handleClearBookings(req, url, env, origin);
      if (req.method === "POST" && url.pathname === "/track/bookings/purge_orphans") return await handlePurgeOrphans(req, url, env, origin);

      return withCors(json({ ok: false, error: "Not Found", path: url.pathname }, { status: 404 }), origin);
    } catch (err) {
      const msg = typeof err?.message === "string" ? err.message : "Unknown error";
      const status =
        msg === "Unauthorized"
          ? 401
          : msg.includes("required") || msg.includes("invalid") || msg.includes("Expected")
          ? 400
          : msg.includes("Unknown") || msg.includes("Not Found") || msg.includes("Invalid") || msg.includes("no result")
          ? 404
          : 500;
      return withCors(json({ ok: false, error: msg }, { status }), origin);
    }
  },
};
