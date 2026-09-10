// COMPANY-CUSTOMER-OPS-P0B — company-scoped import write coordinator.
//
// Workers KV has no compare-and-swap. A process lock or read-check-write is
// not a server guarantee across isolates. This Durable Object is single-threaded
// per tenant+company, so same-key and different-row import batches serialize
// before they touch customer records or packed list pages.
//
// The DO ledger outlives the 72h KV progress document. After expiry the
// coordinator refuses new creates for that import_id instead of silently
// opening a blank meta document.
//
// Production activation requires the wrangler binding + sqlite migration.
// Tests use the in-memory binding. Missing binding fails closed for batches.

import { normalizeCustomerScope } from "./company_customers.mjs";
import {
  getCompanyCustomerImport,
  processImportBatch,
} from "./company_customers_import.mjs";

export const COMPANY_CUSTOMER_IMPORT_DO_BINDING =
  "COMPANY_CUSTOMER_IMPORT_COORDINATOR";

export function companyCustomerImportCoordinatorInstanceName(scope) {
  const s = normalizeCustomerScope(scope);
  if (!s.hasScope) return "";
  return `${s.tenant_id}:${s.company_id}`;
}

export function createMemoryImportCoordinatorStorage(seed = {}) {
  const store = new Map(Object.entries(seed));
  return {
    async get(key) {
      return store.has(key) ? store.get(key) : undefined;
    },
    async put(key, value) {
      store.set(key, value);
    },
    _store: store,
  };
}

export class CompanyCustomerImportCoordinatorDO {
  constructor(stateOrCtx, env) {
    this.state = stateOrCtx;
    this.env = env;
  }

  async fetch(request, init) {
    const req =
      request instanceof Request ? request : new Request(String(request), init);
    let body = {};
    try {
      body = await req.json();
    } catch {
      body = {};
    }
    const action = String(body?.action || "").trim().toLowerCase();
    if (action === "process_batch") return this._processBatch(body);
    if (action === "get_import") return this._getImport(body);
    return this._json({ ok: false, error: "unknown_action" }, 400);
  }

  _ledgerKey(importId) {
    return `import:${String(importId || "").trim()}`;
  }

  async _processBatch(body) {
    const importId = String(body?.importId || body?.import_id || "").trim();
    const ledger = (await this.state.storage.get(this._ledgerKey(importId))) || null;
    const result = await processImportBatch(this.env, {
      scope: body.scope,
      importId,
      rows: body.rows,
      ledger,
    });
    if (result?.ledger?.import_id) {
      await this.state.storage.put(this._ledgerKey(importId), result.ledger);
    }
    return this._json(result, result?.status || 500);
  }

  async _getImport(body) {
    const importId = String(body?.importId || body?.import_id || "").trim();
    const ledger = (await this.state.storage.get(this._ledgerKey(importId))) || null;
    const result = await getCompanyCustomerImport(this.env, {
      scope: body.scope,
      importId,
      ledger,
    });
    return this._json(result, result?.status || 500);
  }

  _json(obj, status = 200) {
    return new Response(JSON.stringify(obj || {}), {
      status,
      headers: { "content-type": "application/json" },
    });
  }
}

/** Test helper: one serialized DO instance per company. */
export function createMemoryCompanyCustomerImportCoordinatorBinding(env = {}) {
  const instances = new Map();
  return {
    idFromName(name) {
      return { name: String(name || "") };
    },
    get(id) {
      const name = String(id?.name || "");
      if (!instances.has(name)) {
        const storage = createMemoryImportCoordinatorStorage();
        const dob = new CompanyCustomerImportCoordinatorDO({ storage }, env);
        let chain = Promise.resolve();
        const originalFetch = dob.fetch.bind(dob);
        dob.fetch = (req, init) => {
          const run = chain.then(() => originalFetch(req, init));
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

export function hasCompanyCustomerImportCoordinator(env) {
  const binding = env?.[COMPANY_CUSTOMER_IMPORT_DO_BINDING];
  return !!(binding?.idFromName && binding?.get);
}

export async function callCompanyCustomerImportCoordinator(env, body) {
  const binding = env?.[COMPANY_CUSTOMER_IMPORT_DO_BINDING];
  if (!binding?.idFromName || !binding?.get) {
    return {
      ok: false,
      status: 503,
      error: "import_coordinator_unavailable",
      next_step: "configure_import_coordinator",
    };
  }
  const name = companyCustomerImportCoordinatorInstanceName(body?.scope);
  if (!name) {
    return { ok: false, status: 400, error: "missing_tenant_scope" };
  }
  const stub = binding.get(binding.idFromName(name));
  stub.env = env;
  const resp = await stub.fetch(
    new Request("https://do/company-customer-import", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    }),
  );
  const json = await resp.json().catch(() => ({}));
  if (json && typeof json === "object") {
    if (json.status == null) json.status = resp.status;
    return json;
  }
  return { ok: false, status: resp.status || 500, error: "import_coordinator_failed" };
}
