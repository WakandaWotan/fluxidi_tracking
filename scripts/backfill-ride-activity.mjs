/**
 * Controlled company-index backfill for ride_activity:v1.
 * Default is dry-run. --execute writes only complete existing indexes.
 * Missing company indexes are never written as empty summaries.
 */
import { exec } from "node:child_process";
import { writeFileSync } from "node:fs";
import { promisify } from "node:util";
import {
  applyRideActivityObservations,
  markRideActivityHistoryComplete,
  observationFromBookingRecord,
  serializeRideActivitySummary,
  rideActivitySummaryKey,
} from "../workers/booking/modules/ride_activity_summary.mjs";

const execAsync = promisify(exec);
const NS = process.env.BOOKING_KV_NAMESPACE_ID || "6805da1ffefe4a3982b4c419250c59b1";
const WRANGLER = "4.131.2";
const EXECUTE = process.argv.includes("--execute");
const INDEX_CAP = 2000;
const onlyArg = process.argv.find((arg) => arg.startsWith("--only="));
const ONLY = onlyArg ? new Set(onlyArg.slice("--only=".length).split(",").map((code) => code.trim()).filter(Boolean)) : null;

async function kvGet(key) {
  try {
    const command = [
      "npx",
      "--yes",
      `wrangler@${WRANGLER}`,
      "kv",
      "key",
      "get",
      JSON.stringify(key),
      "--namespace-id",
      NS,
      "--remote",
    ].join(" ");
    const { stdout, stderr } = await execAsync(command, {
      windowsHide: true,
      timeout: 90000,
      maxBuffer: 8 * 1024 * 1024,
    });
    const text = String(stdout || "").trim();
    const jsonStart = Math.min(
      ...["{", "["].map((token) => {
        const at = text.indexOf(token);
        return at >= 0 ? at : Number.POSITIVE_INFINITY;
      }),
    );
    const jsonText = Number.isFinite(jsonStart) ? text.slice(jsonStart) : text;
    const combined = `${text}\n${stderr || ""}`;
    if (!jsonText || jsonText === "Value not found" || /404:\s*Not Found/i.test(combined)) {
      return { ok: false, missing: true, key, error: "source_not_found" };
    }
    return { ok: true, key, value: JSON.parse(jsonText) };
  } catch (error) {
    const stdout = String(error?.stdout || "").trim();
    const stderr = String(error?.stderr || error?.message || "");
    if (stdout.includes("Value not found") || /404:\s*Not Found/i.test(`${stdout}\n${stderr}`)) {
      return { ok: false, missing: true, key, error: "source_not_found" };
    }
    return { ok: false, key, error: "kv_get_failed" };
  }
}

async function kvPut(key, value) {
  writeFileSync("._ride_activity_put.json", `${JSON.stringify(value)}\n`);
  const command = [
    "npx",
    "--yes",
    `wrangler@${WRANGLER}`,
    "kv",
    "key",
    "put",
    JSON.stringify(key),
    "--namespace-id",
    NS,
    "--remote",
    "--path",
    "._ride_activity_put.json",
  ].join(" ");
  await execAsync(command, { windowsHide: true, timeout: 90000, maxBuffer: 2 * 1024 * 1024 });
}

async function mapPool(items, limit, worker) {
  const out = [];
  let index = 0;
  async function run() {
    while (index < items.length) {
      const current = index;
      index += 1;
      out[current] = await worker(items[current], current);
    }
  }
  if (!items.length) return out;
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, () => run()));
  return out;
}

const manifest = await kvGet("company_registry:manifest:v1");
if (!manifest.ok) {
  console.log(JSON.stringify({ ok: false, error: "registry_manifest_unreadable", execute: EXECUTE }, null, 2));
  process.exit(1);
}
const pageCount = Number(manifest.value.page_count || 1);
const companies = [];
for (let page = 1; page <= pageCount; page += 1) {
  const got = await kvGet(`company_registry:page:${page}:v1`);
  if (got.ok && Array.isArray(got.value?.companies)) companies.push(...got.value.companies);
}

const plans = [];
for (const company of companies) {
  const code = String(company.company_code || "").trim();
  if (ONLY && !ONLY.has(code)) continue;
  const link = await kvGet(`company_link:index:code:${code}:v1`);
  const tenantId = String(link.value?.tenant_id || link.value?.tenantId || "").trim();
  const companyId = String(link.value?.company_id || link.value?.companyId || "").trim();
  const plan = {
    company_code: code,
    display_name: company.display_name || null,
    would_write: false,
    written: false,
    history_complete: false,
    truncated: false,
    key: tenantId && companyId ? rideActivitySummaryKey(tenantId, companyId) : null,
  };
  if (!tenantId || !companyId) {
    plan.error = "scope_unresolved";
    plans.push(plan);
    continue;
  }
  const list = await kvGet(`tenant:${tenantId}:company:${companyId}:bookings:list:v1`);
  if (!list.ok) {
    plan.error = list.missing ? "company_bookings_list_missing" : "list_unreadable";
    plans.push(plan);
    continue;
  }
  const items = Array.isArray(list.value?.items) ? list.value.items : [];
  plan.truncated = items.length >= INDEX_CAP || list.value?.truncated === true;
  const ids = items.map((item) => String(item.booking_id || item.bookingId || "").trim()).filter(Boolean);
  console.log(JSON.stringify({ phase: "company_bookings", company_code: code, index_items: ids.length }));
  const records = await mapPool(ids, 4, async (bookingId) => {
    const got = await kvGet(`booking:${bookingId}`);
    return got.ok ? observationFromBookingRecord(bookingId, got.value, { tenant_id: tenantId, company_id: companyId }) : null;
  });
  const applied = applyRideActivityObservations(null, records.filter(Boolean));
  const marked = plan.truncated
    ? { summary: applied.summary, changed: applied.changed }
    : markRideActivityHistoryComplete(applied.summary);
  plan.history_complete = marked.summary.history_complete === true;
  plan.first_real_ride_id = marked.summary.first_real_ride_id;
  plan.first_real_ride_at = marked.summary.first_real_ride_at;
  plan.first_completed_ride_id = marked.summary.first_completed_ride_id;
  plan.first_completed_ride_at = marked.summary.first_completed_ride_at;
  plan.total_real_rides = marked.summary.total_real_rides;
  plan.total_completed_rides = marked.summary.total_completed_rides;
  plan.payload = serializeRideActivitySummary(marked.summary);
  plan.would_write = plan.history_complete === true && plan.truncated !== true;
  if (EXECUTE && plan.would_write) {
    await kvPut(plan.key, plan.payload);
    plan.written = true;
  }
  plans.push(plan);
}

console.log(JSON.stringify({
  ok: true,
  execute: EXECUTE,
  dry_run: !EXECUTE,
  companies: plans.length,
  written_keys: plans.filter((row) => row.written).map((row) => row.key),
  plans: plans.map((row) => ({
    company_code: row.company_code,
    display_name: row.display_name,
    key: row.key,
    would_write: row.would_write,
    written: row.written === true,
    history_complete: row.history_complete,
    truncated: row.truncated,
    first_real_ride_id: row.first_real_ride_id || null,
    first_real_ride_at: row.first_real_ride_at || null,
    first_completed_ride_id: row.first_completed_ride_id || null,
    first_completed_ride_at: row.first_completed_ride_at || null,
    total_real_rides: row.total_real_rides ?? null,
    total_completed_rides: row.total_completed_rides ?? null,
    error: row.error || null,
  })),
}, null, 2));
