/**
 * READ-ONLY Phase-1 census: company list indexes vs strict ownership.
 * Does not write to KV. Writes aggregate JSON only (ids + scope fields).
 */
import { execSync } from "child_process";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");
const NS = "6805da1ffefe4a3982b4c419250c59b1";

function getJson(key) {
  const out = execSync(
    `npx wrangler kv key get "${key}" --namespace-id=${NS} --remote`,
    {
      encoding: "utf8",
      maxBuffer: 12 * 1024 * 1024,
      windowsHide: true,
      cwd: ROOT,
    },
  );
  const j = out.indexOf("{");
  if (j < 0) throw new Error(`nojson ${key}`);
  return JSON.parse(out.slice(j));
}

function scopeText(v) {
  return v == null ? "" : String(v).trim().slice(0, 120);
}

function rawFields(rec) {
  const b = rec?.booking && typeof rec.booking === "object" ? rec.booking : null;
  return {
    tenant_raw: scopeText(
      rec?.tenant_id ?? rec?.tenantId ?? b?.tenant_id ?? b?.tenantId,
    ),
    company_raw: scopeText(
      rec?.company_id ?? rec?.companyId ?? b?.company_id ?? b?.companyId,
    ),
  };
}

function resolvedScope(rec) {
  const b = rec?.booking && typeof rec.booking === "object" ? rec.booking : null;
  const tenantId = scopeText(
    rec?.tenant_id ??
      rec?.tenantId ??
      b?.tenant_id ??
      b?.tenantId ??
      rec?.company_id ??
      rec?.companyId ??
      b?.company_id ??
      b?.companyId,
  );
  const companyId = scopeText(
    rec?.company_id ??
      rec?.companyId ??
      b?.company_id ??
      b?.companyId ??
      rec?.tenant_id ??
      rec?.tenantId ??
      b?.tenant_id ??
      b?.tenantId,
  );
  return {
    tenant_id: tenantId,
    company_id: companyId,
    hasScope: !!(tenantId || companyId),
  };
}

function strictMatch(rec, tenant, company) {
  const r = resolvedScope(rec);
  if (!tenant || !company || !r.tenant_id || !r.company_id) return false;
  return tenant === r.tenant_id && company === r.company_id;
}

function softMatch(rec, tenant, company) {
  const r = resolvedScope(rec);
  if (!r.hasScope) return tenant === "fluxidi" || company === "fluxidi";
  if (tenant && r.tenant_id && tenant !== r.tenant_id) return false;
  if (company && r.company_id && company !== r.company_id) return false;
  return true;
}

const indexes = [
  "tenant:cmp_patch32-test-20260628160_cba2a2b660:company:cmp_patch32-test-20260628160_cba2a2b660:bookings:list:v1",
  "tenant:cmp_prometheus_97a13bf5a9:company:cmp_prometheus_97a13bf5a9:bookings:list:v1",
  "tenant:fluxidi_fluxidi_ddmh9g:company:fluxidi_fluxidi_ddmh9g:bookings:list:v1",
  "tenant:fluxidi_fluxidi_ddmh9g:company:flx-00001:bookings:list:v1",
];

const summary = [];
const global = {
  index_entries: 0,
  missing_canonical: 0,
  soft_pass_strict_fail: 0,
  missing_tenant_raw: 0,
  missing_company_raw: 0,
  missing_both_raw: 0,
  exact_fluxidi: 0,
  strict_ok: 0,
  neither_match: 0,
};
const softOnlySamples = [];
const missingSamples = [];
const ambiguousSamples = [];

for (const idxKey of indexes) {
  const m = idxKey.match(/^tenant:([^:]+):company:([^:]+):bookings:list:v1$/);
  const tenant = m[1];
  const company = m[2];
  const idx = getJson(idxKey);
  const items = Array.isArray(idx?.items) ? idx.items : [];
  const row = {
    index: idxKey,
    tenant,
    company,
    items: items.length,
    missing: 0,
    strict_ok: 0,
    soft_only: 0,
    neither: 0,
    missing_tenant: 0,
    missing_company: 0,
    missing_both: 0,
    exact_fluxidi: 0,
  };
  console.error(`index ${company} items=${items.length}`);
  for (const entry of items) {
    global.index_entries += 1;
    const bookingId = scopeText(entry?.booking_id ?? entry?.bookingId);
    if (!bookingId) continue;
    let rec;
    try {
      rec = getJson(`booking:${bookingId}`);
    } catch {
      row.missing += 1;
      global.missing_canonical += 1;
      if (missingSamples.length < 8) {
        missingSamples.push({ bookingId, indexCompany: company });
      }
      continue;
    }
    const raw = rawFields(rec);
    if (!raw.tenant_raw) {
      row.missing_tenant += 1;
      global.missing_tenant_raw += 1;
    }
    if (!raw.company_raw) {
      row.missing_company += 1;
      global.missing_company_raw += 1;
    }
    if (!raw.tenant_raw && !raw.company_raw) {
      row.missing_both += 1;
      global.missing_both_raw += 1;
      if (ambiguousSamples.length < 8) {
        ambiguousSamples.push({ bookingId, reason: "missing_both" });
      }
    }
    if (raw.tenant_raw === "fluxidi" || raw.company_raw === "fluxidi") {
      row.exact_fluxidi += 1;
      global.exact_fluxidi += 1;
    }
    const soft = softMatch(rec, tenant, company);
    const strict = strictMatch(rec, tenant, company);
    if (strict) {
      row.strict_ok += 1;
      global.strict_ok += 1;
    } else if (soft) {
      row.soft_only += 1;
      global.soft_pass_strict_fail += 1;
      if (softOnlySamples.length < 12) {
        softOnlySamples.push({ bookingId, indexCompany: company, ...raw });
      }
    } else {
      row.neither += 1;
      global.neither_match += 1;
      if (softOnlySamples.length < 12) {
        softOnlySamples.push({
          bookingId,
          indexCompany: company,
          note: "neither_soft_nor_strict",
          ...raw,
        });
      }
    }
  }
  summary.push(row);
}

// Also sample booking keys not necessarily in indexes (every 10th key).
const keyNames = JSON.parse(
  fs.readFileSync(path.join(ROOT, "_audit_booking_keynames_p1.json"), "utf8"),
);
const sampleStats = {
  sampled: 0,
  missing_tenant_raw: 0,
  missing_company_raw: 0,
  missing_both_raw: 0,
  exact_fluxidi: 0,
  strict_ready_raw_both: 0,
  get_errors: 0,
};
const sampleAmbiguous = [];
for (let i = 0; i < keyNames.length; i += 10) {
  const key = keyNames[i];
  try {
    const rec = getJson(key);
    sampleStats.sampled += 1;
    const raw = rawFields(rec);
    if (!raw.tenant_raw) sampleStats.missing_tenant_raw += 1;
    if (!raw.company_raw) sampleStats.missing_company_raw += 1;
    if (!raw.tenant_raw && !raw.company_raw) {
      sampleStats.missing_both_raw += 1;
      if (sampleAmbiguous.length < 10) sampleAmbiguous.push(key);
    }
    if (raw.tenant_raw === "fluxidi" || raw.company_raw === "fluxidi") {
      sampleStats.exact_fluxidi += 1;
    }
    if (raw.tenant_raw && raw.company_raw) sampleStats.strict_ready_raw_both += 1;
  } catch {
    sampleStats.get_errors += 1;
  }
  if (sampleStats.sampled % 5 === 0) {
    console.error(`sample progress ${sampleStats.sampled}`);
  }
}

const report = {
  source: "company_list_indexes + every_10th_booking_sample",
  booking_key_total: keyNames.length,
  indexes: summary,
  global,
  softOnlySamples,
  missingSamples,
  ambiguousSamples,
  every_10th_sample: sampleStats,
  sampleAmbiguous,
  generated_at: new Date().toISOString(),
};

const outPath = path.join(ROOT, "_audit_index_strict_gap_p1.json");
fs.writeFileSync(outPath, JSON.stringify(report, null, 2));
console.log(JSON.stringify(report, null, 2));
console.error(`wrote ${outPath}`);
