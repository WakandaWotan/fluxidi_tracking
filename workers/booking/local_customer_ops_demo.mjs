// COMPANY-CUSTOMER-OPS-P0 — local Worker host for the company dashboard.
//
// node local_customer_ops_demo.mjs
// Listens on http://127.0.0.1:8788
// Persist: ./.local-customer-ops-demo/
// No production KV, no real email.

import { createServer } from "node:http";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import worker from "./fluxidi_booking_worker.js";
import { sha256Hex } from "./modules/crypto_utils.js";
import { createMemoryCompanyCustomerImportCoordinatorBinding } from "./modules/company_customer_import_coordinator.mjs";
import { LOCAL_DEMO_COMPANIES, solidLogoPng } from "./local_customer_ops_demo_companies.mjs";

export { LOCAL_DEMO_COMPANIES, solidLogoPng };

const HERE = dirname(fileURLToPath(import.meta.url));
const DATA_DIR = join(HERE, ".local-customer-ops-demo");
const KV_FILE = join(DATA_DIR, "kv.json");
const MAIL_FILE = join(DATA_DIR, "mail.json");
const HOST = "127.0.0.1";
const PORT = Number(process.env.CUSTOMER_OPS_DEMO_PORT || 8788);
const PUBLIC_BASE = `http://${HOST}:${PORT}`;

const CORS = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization,content-type,idempotency-key,x-admin-token",
  "access-control-allow-methods": "GET,POST,PATCH,OPTIONS",
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
async function flushNow(store, sink) {
  await mkdir(DATA_DIR, { recursive: true });
  await writeFile(KV_FILE, JSON.stringify(Object.fromEntries(store), null, 2));
  await writeFile(MAIL_FILE, JSON.stringify(sink, null, 2));
}

function scheduleFlush(store, sink) {
  flushPromise = flushPromise.then(() => flushNow(store, sink)).catch((err) => {
    console.error("[local-demo] persist failed", err);
  });
  return flushPromise;
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

function logoPath(companyId) {
  return `/local/media/${companyId}/logo.png`;
}

function logoUrl(companyId) {
  return `${PUBLIC_BASE}${logoPath(companyId)}`;
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
  await kv.put(
    profileKey,
    JSON.stringify({
      business_profile: {
        companyName: company.name,
        trading_name: company.name,
        publicLogoUrl: logoUrl(company.id),
        public_logo_url: logoUrl(company.id),
        country: "BE",
      },
    }),
  );
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
  const flush = () => scheduleFlush(store, sink);
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

  const env = {
    ADMIN_TOKEN: "local-demo-admin",
    BOOKING_KV: kv,
    CUSTOMER_QUOTE_MAIL_SINK: sink,
    CUSTOMER_QUOTE_PUBLIC_BASE: PUBLIC_BASE,
  };
  env.COMPANY_CUSTOMER_IMPORT_COORDINATOR =
    createMemoryCompanyCustomerImportCoordinatorBinding(env);
  for (const company of LOCAL_DEMO_COMPANIES) {
    await seedCompany(kv, company);
  }
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
        res.end(JSON.stringify({ ok: true, public_base: PUBLIC_BASE }));
        return;
      }
      if (url.pathname === "/local/companies") {
        res.writeHead(200, { "content-type": "application/json", ...CORS });
        res.end(
          JSON.stringify({
            ok: true,
            items: LOCAL_DEMO_COMPANIES.map((company) => ({
              company_id: company.id,
              session_token: company.token,
              company_name: company.name,
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
    for (const company of LOCAL_DEMO_COMPANIES) {
      console.log(`[local-demo] company ${company.id} ${company.name} token ${company.token}`);
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
