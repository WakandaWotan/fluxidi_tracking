// COMPANY-CUSTOMER-OPS-P0 — local Worker host for the company dashboard.
//
// node local_customer_ops_demo.mjs
// Listens on http://127.0.0.1:8788
// Persist: ./.local-customer-ops-demo/
// No production KV, no real email.

import { createServer } from "node:http";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import worker, {
  BookingReferenceSequenceDO,
  DocumentReferenceSequenceDO,
} from "./fluxidi_booking_worker.js";
import { sha256Hex } from "./modules/crypto_utils.js";
import { createMemoryCompanyCustomerImportCoordinatorBinding } from "./modules/company_customer_import_coordinator.mjs";
import { createMemoryDoStorage } from "./modules/human_booking_id_allocator.mjs";
import {
  LOCAL_DEMO_COMPANIES,
  companyLinkSeedRecord,
  demoDriver,
  demoDriverLoginCode,
  demoVehicle,
  extraDemoDrivers,
  mergeDemoDriverRecord,
  extraDemoVehicles,
  solidLogoPng,
} from "./local_customer_ops_demo_companies.mjs";
import { createCompanyCustomer } from "./modules/company_customers.mjs";
import { createAgendaRide, rescheduleAgendaRide } from "./modules/company_agenda.mjs";

export {
  LOCAL_DEMO_COMPANIES,
  companyLinkSeedRecord,
  demoDriver,
  demoDriverLoginCode,
  demoVehicle,
  solidLogoPng,
  canonicalLocalDemoPartnerId,
  localDemoPublicPartnerSeed,
  ensureLocalDemoPublicPartners,
};

const HERE = dirname(fileURLToPath(import.meta.url));
const DATA_DIR = join(HERE, ".local-customer-ops-demo");
const KV_FILE = join(DATA_DIR, "kv.json");
const MAIL_FILE = join(DATA_DIR, "mail.json");
const MEDIA_FILE = join(DATA_DIR, "public-media.json");
const HOST = "127.0.0.1";
const PORT = Number(process.env.CUSTOMER_OPS_DEMO_PORT || 8788);
const PUBLIC_BASE = `http://${HOST}:${PORT}`;

const CORS = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization,content-type,idempotency-key,x-admin-token",
  "access-control-allow-methods": "GET,POST,PATCH,PUT,OPTIONS",
};

function persistKv(store) {
  const kv = {
    store,
    counts: { get: 0, put: 0, delete: 0, list: 0 },
    async get(key, opts) {
      this.counts.get += 1;
      if (!store.has(key)) return null;
      const raw = store.get(key);
      const asJson = opts === "json" || opts?.type === "json";
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
      this.counts.put += 1;
      store.set(key, val);
    },
    async delete(key) {
      this.counts.delete += 1;
      store.delete(key);
    },
    async list() {
      this.counts.list += 1;
      return { keys: [], list_complete: true };
    },
  };
  return kv;
}

let flushPromise = Promise.resolve();
async function flushNow(store, sink, media) {
  await mkdir(DATA_DIR, { recursive: true });
  await writeFile(KV_FILE, JSON.stringify(Object.fromEntries(store), null, 2));
  await writeFile(MAIL_FILE, JSON.stringify(sink, null, 2));
  if (media) {
    await writeFile(
      MEDIA_FILE,
      JSON.stringify(
        Object.fromEntries(
          [...media.entries()].map(([key, value]) => [
            key,
            {
              body: Buffer.from(value.body).toString("base64"),
              httpMetadata: value.httpMetadata || {},
            },
          ]),
        ),
      ),
    );
  }
}

function scheduleFlush(store, sink, media) {
  flushPromise = flushPromise
    .then(() => flushNow(store, sink, media))
    .catch((err) => {
      console.error("[local-demo] persist failed", err);
    });
  return flushPromise;
}

async function loadLocalMapboxToken() {
  const fromEnv = String(process.env.MAPBOX_TOKEN || "").trim();
  if (fromEnv) return fromEnv;
  const file =
    process.env.FLUXIDI_DEV_ENV_FILE ||
    join(homedir(), ".fluxidi", "fluxidi-dev-env.ps1");
  try {
    const raw = await readFile(file, "utf8");
    const match =
      raw.match(/\$env:MAPBOX_TOKEN\s*=\s*['"]([^'"]+)['"]/i) ||
      raw.match(/(?:^|\n)\s*MAPBOX_TOKEN\s*=\s*['"]([^'"]+)['"]/im);
    return String(match?.[1] || "").trim();
  } catch {
    return "";
  }
}

async function loadStore() {
  try {
    const raw = JSON.parse(await readFile(KV_FILE, "utf8"));
    return new Map(Object.entries(raw || {}));
  } catch {
    return new Map();
  }
}

async function loadSink() {
  try {
    const raw = JSON.parse(await readFile(MAIL_FILE, "utf8"));
    return Array.isArray(raw) ? raw : [];
  } catch {
    return [];
  }
}

async function loadPublicMediaEntries() {
  try {
    const raw = JSON.parse(await readFile(MEDIA_FILE, "utf8"));
    return Object.entries(raw || {}).map(([key, value]) => [
      key,
      {
        body: Buffer.from(value?.body || "", "base64"),
        httpMetadata: value?.httpMetadata || {},
      },
    ]);
  } catch {
    return [];
  }
}

function logoPath(companyId) {
  return `/local/media/${companyId}/logo.png`;
}

function logoUrl(companyId) {
  return `${PUBLIC_BASE}${logoPath(companyId)}`;
}

function createMemoryPublicMedia(initial, onChange) {
  const objects = new Map(initial || []);
  return {
    async put(key, bytes, opts) {
      objects.set(String(key), {
        body: Buffer.from(bytes),
        httpMetadata: opts?.httpMetadata || {},
      });
      await onChange?.(objects);
    },
    async get(key) {
      const obj = objects.get(String(key));
      if (!obj) return null;
      return {
        body: obj.body,
        httpEtag: "",
        writeHttpMetadata(headers) {
          if (obj.httpMetadata.contentType) {
            headers.set("Content-Type", obj.httpMetadata.contentType);
          }
          if (obj.httpMetadata.cacheControl) {
            headers.set("Cache-Control", obj.httpMetadata.cacheControl);
          }
        },
      };
    },
  };
}

const LOCAL_DEMO_PARTNER_POSTCODES = [
  "1000",
  "1020",
  "1030",
  "1853",
  "2000",
  "2018",
  "2060",
  "2800",
  "3000",
  "3500",
  "8000",
  "8400",
  "9000",
  "9688",
];

function canonicalLocalDemoPartnerId(company) {
  return `company:${company.id}:${company.id}`;
}

function localDemoPublicPartnerSeed(company) {
  const partnerId = canonicalLocalDemoPartnerId(company);
  const nowIso = new Date().toISOString();
  return {
    partner_id: partnerId,
    tenant_id: company.id,
    company_id: company.id,
    company_name: company.name,
    is_active: true,
    subscription_status: "active",
    profile_enabled: true,
    published_at: nowIso,
    public_company_code: company.code,
    coverage: {
      region_label: "Belgie",
      city: company.id === "demo_company_p0" ? "Leuven" : "Brussel",
      country_code: "BE",
      primary_postcode: company.id === "demo_company_p0" ? "3000" : "1000",
      postcodes: LOCAL_DEMO_PARTNER_POSTCODES,
      lat: 50.85,
      lng: 4.35,
      service_radius_km: 250,
    },
    services: ["taxi_vvb", "airport_transfer", "business_rides"],
    booking_capabilities: {
      calculator: true,
      airport_transfer: true,
    },
    airport_service_enabled: true,
    airport_transfer_enabled: true,
  };
}

function listFromKvRaw(raw, arrayKey) {
  if (Array.isArray(raw)) return raw;
  if (raw && typeof raw === "object" && Array.isArray(raw[arrayKey])) {
    return raw[arrayKey];
  }
  return [];
}

async function upsertNamedList(kv, key, arrayKey, incoming, idField) {
  const raw = await kv.get(key, { type: "json" });
  const current = listFromKvRaw(raw, arrayKey);
  const byId = new Map();
  for (const item of current) {
    const id = item?.[idField];
    if (id) byId.set(id, item);
  }
  let changed = false;
  for (const item of incoming) {
    const id = item?.[idField];
    if (!id) continue;
    if (!byId.has(id)) {
      byId.set(id, item);
      changed = true;
    }
  }
  if (!changed && current.length > 0) return false;
  const next = Array.from(byId.values());
  const envelope = raw && typeof raw === "object" && !Array.isArray(raw)
    ? { ...raw, [arrayKey]: next, updated_at: new Date().toISOString() }
    : { [arrayKey]: next, updated_at: new Date().toISOString() };
  await kv.put(key, JSON.stringify(envelope));
  return true;
}

async function ensureLocalDemoPublicPartners(kv, companies = LOCAL_DEMO_COMPANIES) {
  const directory = [];
  const profiles = [];
  const routes = [];
  for (const company of companies) {
    const seed = localDemoPublicPartnerSeed(company);
    directory.push({
      partner_id: seed.partner_id,
      company_name: seed.company_name,
      is_active: true,
      subscription_status: "active",
      primary_postcode: seed.coverage.primary_postcode,
      supported_postcodes: seed.coverage.postcodes,
    });
    profiles.push({
      partner_id: seed.partner_id,
      company_name: seed.company_name,
      profile_enabled: true,
      is_active: true,
      subscription_status: "active",
      published_at: seed.published_at,
      public_company_code: seed.public_company_code,
      coverage: seed.coverage,
      services: seed.services,
      booking_capabilities: seed.booking_capabilities,
      airport_service_enabled: true,
      airport_transfer_enabled: true,
    });
    routes.push({
      partner_id: seed.partner_id,
      tenant_id: seed.tenant_id,
      company_id: seed.company_id,
      company_name: seed.company_name,
      is_active: true,
      subscription_status: "active",
      updated_at: seed.published_at,
    });
  }
  await upsertNamedList(kv, "partners:directory:v1", "partners", directory, "partner_id");
  await upsertNamedList(kv, "public:partners:directory:v2", "partners", directory, "partner_id");
  await upsertNamedList(kv, "partners:profiles:v1", "profiles", profiles, "partner_id");
  await upsertNamedList(kv, "public:partners:profiles:v2", "profiles", profiles, "partner_id");
  await upsertNamedList(kv, "partners:booking-routes:v1", "routes", routes, "partner_id");
  await upsertNamedList(
    kv,
    "public:partners:booking-routes:v2",
    "routes",
    routes,
    "partner_id",
  );
}

function createMemorySequenceDoBinding(DoClass) {
  const instances = new Map();
  return {
    idFromName(name) {
      return { name: String(name || "") };
    },
    get(id) {
      const name = String(id?.name || "");
      if (!instances.has(name)) {
        const storage = createMemoryDoStorage();
        const dob = new DoClass({ storage }, {});
        let chain = Promise.resolve();
        const originalFetch = dob.fetch.bind(dob);
        dob.fetch = (req, init) => {
          const request = req instanceof Request ? req : new Request(String(req), init);
          const run = chain.then(() => originalFetch(request));
          chain = run.then(
            () => undefined,
            () => undefined,
          );
          return run;
        };
        instances.set(name, dob);
      }
      return instances.get(name);
    },
    _instances: instances,
  };
}

async function putIfAbsent(kv, key, value) {
  const existing = await kv.get(key);
  if (existing != null) return false;
  await kv.put(key, value);
  return true;
}

async function seedCompany(kv, company) {
  const hash = await sha256Hex(company.token);
  const expires = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString();
  await kv.put(
    `company_admin:session:${hash}:v1`,
    JSON.stringify({
      role: "company_admin",
      tenant_id: company.id,
      company_id: company.id,
      company_code: company.code,
      company_display_name: company.name,
      expires_at: expires,
    }),
  );
  const profileKey = `tenant:${company.id}:company:${company.id}:business_profile:v1`;
  await putIfAbsent(
    kv,
    profileKey,
    JSON.stringify({
      business_profile: {
        companyName: company.name,
        trading_name: company.name,
        publicLogoUrl: logoUrl(company.id),
        public_logo_url: logoUrl(company.id),
        country: "BE",
        phone: "+3227110000",
        email: `ops@${company.id.split("_").join("-")}.local`,
        company_code: company.code,
        public_company_code: company.code,
        publicCompanyCode: company.code,
      },
    }),
  );
  const existingProfileRaw = await kv.get(profileKey);
  if (existingProfileRaw) {
    try {
      const parsed =
        typeof existingProfileRaw === "string"
          ? JSON.parse(existingProfileRaw)
          : existingProfileRaw;
      const profile = parsed?.business_profile && typeof parsed.business_profile === "object"
        ? parsed.business_profile
        : parsed;
      if (profile && typeof profile === "object" && !profile.public_company_code && !profile.publicCompanyCode) {
        profile.company_code = profile.company_code || company.code;
        profile.public_company_code = company.code;
        profile.publicCompanyCode = company.code;
        await kv.put(
          profileKey,
          JSON.stringify(
            parsed?.business_profile
              ? { ...parsed, business_profile: profile }
              : { business_profile: profile },
          ),
        );
      }
    } catch {
      // Keep the stored profile if it cannot be repaired.
    }
  }
  const nowIso = new Date().toISOString();
  const vehicle = demoVehicle(company);
  await putIfAbsent(
    kv,
    `tenant:${company.id}:company:${company.id}:fleet:vehicles:v1`,
    JSON.stringify({
      version: 1,
      updated_at: nowIso,
      source_revision: 1,
      vehicles: [vehicle],
      deleted_vehicle_ids: {},
    }),
  );
  const driver = demoDriver(company);
  const extras = extraDemoDrivers(company);
  const driverKey = `tenant:${company.id}:company:${company.id}:drivers:index:v1`;
  await putIfAbsent(
    kv,
    driverKey,
    JSON.stringify({
      drivers: { [driver.driver_id]: driver },
      updated_at: nowIso,
    }),
  );
  await mergeDemoDrivers(kv, company, [driver, ...extras]);
  await ensureDemoDriverLogin(kv, company, driver);
  await mergeDemoVehicles(kv, company, extraDemoVehicles(company));
  const linkRecord = companyLinkSeedRecord(company);
  await putIfAbsent(
    kv,
    `company_link:index:code:${company.code}:v1`,
    JSON.stringify(linkRecord),
  );
  await putIfAbsent(
    kv,
    `company_link:index:scope:${company.id}:${company.id}:v1`,
    JSON.stringify(linkRecord),
  );
  if (company.id === "demo_company_p0") {
    const env = { BOOKING_KV: kv };
    const scope = { tenant_id: company.id, company_id: company.id, hasScope: true };
    const ada = await createCompanyCustomer(env, {
      scope,
      idempotencyKey: "seed-ada-lovelace",
      body: {
        display_name: "Ada Lovelace",
        first_name: "Ada",
        last_name: "Lovelace",
        email: "ada@demo.local",
        phone: "+3227110101",
        addresses: [
          {
            type: "home",
            label: "Thuis",
            line1: "Korenmarkt 1",
            city: "Gent",
            postal_code: "9000",
            country_code: "BE",
          },
        ],
      },
    });
    const grace = await createCompanyCustomer(env, {
      scope,
      idempotencyKey: "seed-grace-hopper",
      body: {
        display_name: "Grace Hopper",
        first_name: "Grace",
        last_name: "Hopper",
        email: "grace@demo.local",
        phone: "+3227110102",
        addresses: [
          {
            type: "work",
            label: "Kantoor",
            line1: "Kunstlaan 44",
            city: "Brussel",
            postal_code: "1000",
            country_code: "BE",
          },
        ],
      },
    });
    await seedDemoAgendaWeek(env, {
      scope,
      adaId: ada?.body?.customer?.customer_id || ada?.customer?.customer_id,
      graceId: grace?.body?.customer?.customer_id || grace?.customer?.customer_id,
    });
  }
}

async function mergeDemoDrivers(kv, company, drivers) {
  const key = `tenant:${company.id}:company:${company.id}:drivers:index:v1`;
  const raw = await kv.get(key);
  let parsed = { drivers: {} };
  if (raw) {
    try {
      parsed = typeof raw === "string" ? JSON.parse(raw) : raw;
    } catch {
      parsed = { drivers: {} };
    }
  }
  const map = parsed?.drivers && typeof parsed.drivers === "object" ? parsed.drivers : {};
  for (const driver of drivers) {
    if (!driver?.driver_id) continue;
    map[driver.driver_id] = mergeDemoDriverRecord(map[driver.driver_id], driver);
  }
  await kv.put(
    key,
    JSON.stringify({ ...parsed, drivers: map, updated_at: new Date().toISOString() }),
  );
}

async function mergeDemoVehicles(kv, company, vehicles) {
  if (!vehicles.length) return;
  const key = `tenant:${company.id}:company:${company.id}:fleet:vehicles:v1`;
  const raw = await kv.get(key);
  let parsed = { vehicles: [] };
  if (raw) {
    try {
      parsed = typeof raw === "string" ? JSON.parse(raw) : raw;
    } catch {
      parsed = { vehicles: [] };
    }
  }
  const list = Array.isArray(parsed.vehicles) ? parsed.vehicles.slice() : [];
  for (const vehicle of vehicles) {
    if (list.some((row) => (row.vehicle_id || row.vehicleId) === vehicle.vehicle_id)) {
      continue;
    }
    list.push(vehicle);
  }
  await kv.put(
    key,
    JSON.stringify({ ...parsed, vehicles: list, updated_at: new Date().toISOString() }),
  );
}

function localMonday(now = new Date()) {
  const local = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  local.setDate(local.getDate() - ((local.getDay() + 6) % 7));
  return local;
}

function localIso(day, hour, minute = 0) {
  return new Date(
    day.getFullYear(),
    day.getMonth(),
    day.getDate(),
    hour,
    minute,
  ).toISOString();
}

async function ensureDemoAgendaRide(env, { scope, key, idempotencyKey, body }) {
  const demoKey = key || idempotencyKey;
  const created = await createAgendaRide(env, {
    scope,
    idempotencyKey: demoKey,
    body,
  });
  const bookingId = created?.booking_id;
  const current = created?.item?.pickup_iso || "";
  const wanted = body?.pickup_iso || "";
  if (
    bookingId &&
    wanted &&
    Date.parse(current) !== Date.parse(wanted)
  ) {
    await rescheduleAgendaRide(env, {
      scope,
      bookingId,
      body: { pickup_iso: wanted },
    });
  }
  return created;
}

async function seedDemoAgendaWeek(env, { scope, adaId, graceId }) {
  if (!adaId || !graceId) return;
  const monday = localMonday();
  const rides = [
    {
      key: "demo-week-assigned-karel",
      customer_id: adaId,
      customer_name: "Ada Lovelace",
      from: "Korenmarkt 1, Gent",
      to: "Brussels Airport",
      pickup_iso: localIso(monday, 10, 0),
      duration_min: 90,
      assigned_driver_id: "drv_demo_company_p0_1",
      assigned_vehicle_id: "vh_demo_company_p0_1",
    },
    {
      key: "demo-week-unassigned-grace",
      customer_id: graceId,
      customer_name: "Grace Hopper",
      from: "Kunstlaan 44, Brussel",
      to: "Antwerpen Centraal",
      pickup_iso: localIso(new Date(monday.getTime() + 86400000), 14, 0),
      duration_min: 75,
    },
    {
      key: "demo-week-karel-morning",
      customer_id: adaId,
      customer_name: "Ada Lovelace",
      from: "Gent-Sint-Pieters",
      to: "Brugge",
      pickup_iso: localIso(new Date(monday.getTime() + 2 * 86400000), 9, 0),
      duration_min: 120,
      assigned_driver_id: "drv_demo_company_p0_1",
      assigned_vehicle_id: "vh_demo_company_p0_1",
    },
    {
      key: "demo-week-overlap-candidate",
      customer_id: graceId,
      customer_name: "Grace Hopper",
      from: "Brussel Zuid",
      to: "Charleroi Airport",
      pickup_iso: localIso(new Date(monday.getTime() + 2 * 86400000), 10, 0),
      duration_min: 90,
    },
    {
      key: "demo-week-unknown-duration",
      customer_id: adaId,
      customer_name: "Ada Lovelace",
      from: "Leuven",
      to: "Luik",
      pickup_iso: localIso(new Date(monday.getTime() + 3 * 86400000), 20, 0),
    },
    {
      key: "demo-week-midnight",
      customer_id: graceId,
      customer_name: "Grace Hopper",
      from: "Brussels Airport",
      to: "Gent",
      pickup_iso: localIso(new Date(monday.getTime() + 4 * 86400000), 23, 0),
      duration_min: 180,
      assigned_driver_id: "drv_demo_company_p0_3",
      assigned_vehicle_id: "vh_demo_company_p0_2",
    },
  ];
  for (const ride of rides) {
    const { key, ...body } = ride;
    await ensureDemoAgendaRide(env, { scope, key, body });
  }
  const cancelled = await ensureDemoAgendaRide(env, {
    scope,
    idempotencyKey: "demo-week-cancelled",
    body: {
      customer_id: adaId,
      customer_name: "Ada Lovelace",
      from: "Oostende",
      to: "Gent",
      pickup_iso: localIso(new Date(monday.getTime() + 5 * 86400000), 11, 0),
      duration_min: 60,
      assigned_driver_id: "drv_demo_company_p0_1",
    },
  });
  const cancelledId = cancelled?.booking_id;
  if (cancelledId && env.BOOKING_KV) {
    const raw = await env.BOOKING_KV.get(`booking:${cancelledId}`);
    if (raw) {
      const record = typeof raw === "string" ? JSON.parse(raw) : raw;
      record.status = "CANCELLED";
      record.lifecycle = "cancelled";
      if (record.booking) record.booking.status = "CANCELLED";
      await env.BOOKING_KV.put(`booking:${cancelledId}`, JSON.stringify(record));
    }
  }
}

async function ensureDemoDriverLogin(kv, company, seededDriver) {
  const key = `tenant:${company.id}:company:${company.id}:drivers:index:v1`;
  const raw = await kv.get(key);
  if (!raw) return;
  let parsed;
  try {
    parsed = typeof raw === "string" ? JSON.parse(raw) : raw;
  } catch {
    return;
  }
  const drivers = parsed?.drivers && typeof parsed.drivers === "object" ? parsed.drivers : null;
  if (!drivers) return;
  const driverId = seededDriver.driver_id;
  const entry = drivers[driverId];
  if (!entry || typeof entry !== "object") return;
  if (entry.login_code || entry.loginCode || entry.driver_code || entry.driverCode) {
    return;
  }
  const login = demoDriverLoginCode(company);
  entry.login_code = login;
  entry.loginCode = login;
  entry.driver_code = login;
  entry.driverCode = login;
  if (!entry.employee_number && !entry.employeeNumber) {
    entry.employee_number = login;
    entry.employeeNumber = login;
  }
  drivers[driverId] = entry;
  await kv.put(key, JSON.stringify({ ...parsed, drivers }));
}

function toRequest(req, body) {
  const url = new URL(req.url || "/", PUBLIC_BASE);
  const headers = new Headers();
  for (const [name, value] of Object.entries(req.headers || {})) {
    if (value == null) continue;
    headers.set(name, Array.isArray(value) ? value.join(",") : String(value));
  }
  const method = req.method || "GET";
  if (method === "GET" || method === "HEAD") {
    return new Request(url, { method, headers });
  }
  return new Request(url, { method, headers, body });
}

async function readBody(req) {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  return Buffer.concat(chunks);
}

async function main() {
  await mkdir(DATA_DIR, { recursive: true });
  const store = await loadStore();
  const sink = await loadSink();
  let mediaEntries = new Map(await loadPublicMediaEntries());
  const flush = () => scheduleFlush(store, sink, mediaEntries);
  const kv = persistKv(store);
  const originalPut = kv.put.bind(kv);
  const originalDelete = kv.delete.bind(kv);
  kv.put = async (key, val) => {
    await originalPut(key, val);
    await flush();
  };
  kv.delete = async (key) => {
    await originalDelete(key);
    await flush();
  };

  const mapboxToken = await loadLocalMapboxToken();
  const env = {
    ADMIN_TOKEN: "local-demo-admin",
    APP_ENV: "local",
    CUSTOMER_PHONE_AUTH_DEBUG_OTP: "true",
    MAPBOX_TOKEN: mapboxToken,
    BOOKING_KV: kv,
    PUBLIC_MEDIA: createMemoryPublicMedia(mediaEntries, async (next) => {
      mediaEntries = next;
      await flush();
    }),
    CUSTOMER_QUOTE_MAIL_SINK: sink,
    CUSTOMER_QUOTE_PUBLIC_BASE: PUBLIC_BASE,
  };
  env.COMPANY_CUSTOMER_IMPORT_COORDINATOR =
    createMemoryCompanyCustomerImportCoordinatorBinding(env);
  env.BOOKING_REFERENCE_SEQUENCE = createMemorySequenceDoBinding(
    BookingReferenceSequenceDO,
  );
  env.DOCUMENT_REFERENCE_SEQUENCE = createMemorySequenceDoBinding(
    DocumentReferenceSequenceDO,
  );
  for (const company of LOCAL_DEMO_COMPANIES) {
    await seedCompany(kv, company);
  }
  await ensureLocalDemoPublicPartners(kv);
  await flush();

  const logos = new Map(
    LOCAL_DEMO_COMPANIES.map((company) => [company.id, solidLogoPng(company.logo)]),
  );

  const server = createServer(async (req, res) => {
    try {
      if (req.method === "OPTIONS") {
        res.writeHead(204, CORS);
        res.end();
        return;
      }
      const url = new URL(req.url || "/", PUBLIC_BASE);
      if (url.pathname === "/local/health") {
        res.writeHead(200, { "content-type": "application/json", ...CORS });
        res.end(JSON.stringify({
          ok: true,
          public_base: PUBLIC_BASE,
          mapbox_configured: Boolean(mapboxToken),
        }));
        return;
      }
      if (url.pathname === "/local/companies") {
        res.writeHead(200, { "content-type": "application/json", ...CORS });
        res.end(
          JSON.stringify({
            ok: true,
            items: LOCAL_DEMO_COMPANIES.map((company) => ({
              company_id: company.id,
              id: company.id,
              company_name: company.name,
              name: company.name,
              code: company.code,
              company_code: company.code,
              public_logo_url: logoUrl(company.id),
            })),
          }),
        );
        return;
      }
      const logoMatch = url.pathname.match(/^\/local\/media\/([^/]+)\/logo\.png$/);
      if (logoMatch) {
        const png = logos.get(logoMatch[1]);
        if (!png) {
          res.writeHead(404, { "content-type": "application/json", ...CORS });
          res.end(JSON.stringify({ ok: false, error: "logo_not_found" }));
          return;
        }
        res.writeHead(200, {
          "content-type": "image/png",
          "cache-control": "no-store",
          ...CORS,
        });
        res.end(png);
        return;
      }
      if (url.pathname === "/local/contacts_demo.csv") {
        const csv = await readFile(join(DATA_DIR, "contacts_demo.csv"));
        res.writeHead(200, {
          "content-type": "text/csv; charset=utf-8",
          "content-disposition": "attachment; filename=contacts_demo.csv",
          ...CORS,
        });
        res.end(csv);
        return;
      }
      if (url.pathname === "/local/customer-quote-mail") {
        res.writeHead(200, { "content-type": "application/json", ...CORS });
        res.end(JSON.stringify({ ok: true, test_send: true, items: sink }));
        return;
      }
      const body = await readBody(req);
      const request = toRequest(req, body.length ? body : undefined);
      const response = await worker.fetch(request, env, {});
      const headers = { ...CORS };
      response.headers.forEach((value, name) => {
        headers[name] = value;
      });
      const buf = Buffer.from(await response.arrayBuffer());
      res.writeHead(response.status, headers);
      res.end(buf);
      await flush();
    } catch (err) {
      console.error("[local-demo]", err);
      res.writeHead(500, { "content-type": "application/json", ...CORS });
      res.end(JSON.stringify({ ok: false, error: "local_demo_failed" }));
    }
  });

  server.listen(PORT, HOST, () => {
    console.log(`[local-demo] worker ${PUBLIC_BASE}`);
    console.log(`[local-demo] mail sink ${PUBLIC_BASE}/local/customer-quote-mail`);
    console.log(`[local-demo] persist ${DATA_DIR}`);
    console.log(`[local-demo] mapbox_configured=${mapboxToken ? "true" : "false"}`);
    for (const company of LOCAL_DEMO_COMPANIES) {
      console.log(`[local-demo] company ${company.id} ${company.name} token=cst_local_*`);
    }
  });
}

const isDirect = process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1];
if (isDirect) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
