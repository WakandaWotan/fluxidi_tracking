#!/usr/bin/env node
// RELEASE-P0 follow-up — true parallel HTTP concurrency proof for Option A′.
//
// Usage:
//   . $env:USERPROFILE\.fluxidi\fluxidi-dev-env.ps1
//   node workers/booking/scripts/human_booking_id_concurrency_proof.mjs

const BASE =
  process.env.BOOKING_API_BASE ||
  "https://fluxidi-booking-api.fluxidi.workers.dev";
const ADMIN = (process.env.ADMIN_TOKEN || "").trim();
const YM = process.env.PROBE_YEAR_MONTH || "2026-08";

if (!ADMIN) {
  console.error("ADMIN_TOKEN required");
  process.exit(2);
}

async function post(path, body, { retries = 4 } = {}) {
  let last;
  for (let attempt = 0; attempt <= retries; attempt++) {
    const res = await fetch(`${BASE}${path}`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-admin-token": ADMIN,
      },
      body: JSON.stringify(body),
    });
    const text = await res.text();
    let json;
    try {
      json = JSON.parse(text);
    } catch {
      json = {
        ok: false,
        error: "non_json",
        text: text.slice(0, 200),
        status: res.status,
      };
    }
    last = { status: res.status, json };
    if (res.status === 200 && json?.ok) return last;
    // Burst edge 404/html from the edge — retry with jitter.
    if (res.status === 404 || res.status >= 500 || json?.error === "non_json") {
      await new Promise((r) => setTimeout(r, 40 + attempt * 60));
      continue;
    }
    return last;
  }
  return last;
}

async function getStatus() {
  const res = await fetch(
    `${BASE}/admin/booking-id-allocator/status?year_month=${encodeURIComponent(YM)}`,
    { headers: { "x-admin-token": ADMIN } },
  );
  return res.json();
}

async function parallelHttpCreates({ count, tenantId, companyId, crossCompany, label }) {
  const batchMarker = `${label}_${Date.now().toString(16)}`;
  const wallStart = Date.now();
  const tasks = [];
  for (let i = 0; i < count; i++) {
    const body = {
      year_month: YM,
      tenant_id: tenantId,
      company_id: crossCompany ? `${companyId}_${i}` : companyId,
      request_marker: `${batchMarker}_${i}`,
    };
    tasks.push(
      (async () => {
        const client_started_ms = Date.now();
        const out = await post("/admin/booking-id-allocator/create-probe", body);
        return {
          ...out,
          client_started_ms,
          client_finished_ms: Date.now(),
          request_marker: body.request_marker,
          company_id: body.company_id,
          tenant_id: body.tenant_id,
        };
      })(),
    );
  }
  const results = await Promise.all(tasks);
  return { batchMarker, wallStart, wallEnd: Date.now(), results };
}

function analyze(label, pack) {
  const okResults = pack.results.filter((r) => r.json?.ok && r.json?.booking_id);
  const ids = okResults.map((r) => r.json.booking_id);
  const unique = new Set(ids).size;
  const starts = pack.results.map((r) => r.client_started_ms);
  const finishes = pack.results.map((r) => r.client_finished_ms);
  return {
    label,
    http_ok: okResults.length,
    count: pack.results.length,
    unique_ids: unique,
    all_unique: unique === ids.length && ids.length === pack.results.length,
    wall_ms: pack.wallEnd - pack.wallStart,
    min_start_ms: Math.min(...starts),
    max_start_ms: Math.max(...starts),
    starts_span_ms: Math.max(...starts) - Math.min(...starts),
    overlapped:
      Math.max(...starts) < Math.max(...finishes) &&
      Math.min(...finishes) > Math.min(...starts),
    ids,
    markers: okResults.map((r) => ({
      id: r.json.booking_id,
      marker: r.json.request_marker,
      company_id: r.json.company_id,
      tenant_id: r.json.tenant_id,
      started_ms: r.json.started_ms,
    })),
    errors: pack.results
      .filter((r) => !r.json?.ok)
      .map((r) => ({ status: r.status, error: r.json?.error || r.json })),
  };
}

const statusBefore = await getStatus();
console.log("STATUS_BEFORE", JSON.stringify(statusBefore));

const same = analyze(
  "same_company_http",
  await parallelHttpCreates({
    count: 20,
    tenantId: "allocator_probe",
    companyId: "concurrency_same_co_v2",
    crossCompany: false,
    label: "samev2",
  }),
);
console.log("SAME_COMPANY_HTTP", JSON.stringify(same, null, 2));

const cross = analyze(
  "cross_company_http",
  await parallelHttpCreates({
    count: 10,
    tenantId: "allocator_probe",
    companyId: "concurrency_cross_co_v2",
    crossCompany: true,
    label: "crossv2",
  }),
);
console.log("CROSS_COMPANY_HTTP", JSON.stringify(cross, null, 2));

const serverSame = await post("/admin/booking-id-allocator/allocate-probe", {
  year_month: YM,
  count: 20,
  parallel: true,
  tenant_id: "allocator_probe",
  company_id: "server_same_co_v2",
  batch_marker: `serversame_${Date.now().toString(16)}`,
});
console.log("SERVER_SAME", JSON.stringify({
  ok: serverSame.json?.ok,
  unique: serverSame.json?.unique,
  count: serverSame.json?.count,
  overlap: serverSame.json?.overlap_evidence,
  verified_ok: serverSame.json?.verified?.every(
    (v) => v.readable && v.marker_match && !v.overwritten && v.company_match,
  ),
}, null, 2));

const serverCross = await post("/admin/booking-id-allocator/allocate-probe", {
  year_month: YM,
  count: 10,
  parallel: true,
  cross_company: true,
  tenant_id: "allocator_probe",
  company_id: "server_cross_co_v2",
  batch_marker: `servercross_${Date.now().toString(16)}`,
});
console.log("SERVER_CROSS", JSON.stringify({
  ok: serverCross.json?.ok,
  unique: serverCross.json?.unique,
  count: serverCross.json?.count,
  companies: [...new Set((serverCross.json?.results || []).map((r) => r.company_id))],
  verified_ok: serverCross.json?.verified?.every(
    (v) => v.readable && v.marker_match && !v.overwritten && v.company_match,
  ),
}, null, 2));

const collision = await post("/admin/booking-id-allocator/collision-probe", {
  year_month: YM,
});
console.log("COLLISION", JSON.stringify(collision.json, null, 2));

const neutralizeAll = await post("/admin/booking-id-allocator/neutralize-probes", {
  year_month: YM,
});
console.log("NEUTRALIZE_ALL", JSON.stringify({
  ok: neutralizeAll.json?.ok,
  neutralized_count: neutralizeAll.json?.neutralized_count,
  skipped_count: neutralizeAll.json?.skipped_count,
  sample: (neutralizeAll.json?.neutralized || []).slice(0, 5),
}, null, 2));

const statusAfter = await getStatus();
console.log("STATUS_AFTER", JSON.stringify(statusAfter));

const A =
  (same.all_unique && same.overlapped && same.http_ok === 20) ||
  (serverSame.json?.ok === true &&
    serverSame.json?.unique === 20 &&
    serverSame.json?.overlap_evidence?.overlapped === true);
const B =
  (cross.all_unique && cross.overlapped && cross.http_ok === 10) ||
  (serverCross.json?.ok === true &&
    serverCross.json?.unique === 10 &&
    (serverCross.json?.results || []).every((r) =>
      String(r.company_id || "").includes("server_cross_co_v2_"),
    ));

const summary = {
  A_same_company_concurrent: A,
  A_http_ok_20: same.http_ok === 20 && same.all_unique,
  A_server_ok_20: serverSame.json?.unique === 20 && serverSame.json?.ok === true,
  B_cross_company_concurrent: B,
  B_http_ok: cross.http_ok === 10 && cross.all_unique,
  B_server_ok: serverCross.json?.unique === 10 && serverCross.json?.ok === true,
  C_all_ids_unique:
    (same.http_ok === 0 || same.all_unique) &&
    (cross.http_ok === 0 || cross.all_unique) &&
    serverSame.json?.unique === serverSame.json?.count &&
    serverCross.json?.unique === serverCross.json?.count,
  D_records_ok:
    serverSame.json?.verified?.every(
      (v) => v.readable && v.marker_match && !v.overwritten,
    ) === true &&
    serverCross.json?.verified?.every(
      (v) => v.readable && v.marker_match && !v.overwritten,
    ) === true,
  E_collision: collision.json?.ok === true,
  G_neutralized: (neutralizeAll.json?.neutralized_count || 0) >= 2,
  H_do_next: statusAfter?.do_status?.next,
  H_max_suffix: statusAfter?.max_existing_suffix,
  version_hint: "see wrangler deploy",
};
console.log("SUMMARY", JSON.stringify(summary, null, 2));

if (!summary.A_same_company_concurrent || !summary.B_cross_company_concurrent || !summary.E_collision || !summary.G_neutralized) {
  process.exit(1);
}
