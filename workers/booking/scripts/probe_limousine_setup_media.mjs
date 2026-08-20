// Live probe of /admin/partners/media/upload. Prints redacted diagnostics only.
// Usage: node --env-file omitted. Reads BOOKING_BASE_URL + ADMIN_TOKEN from env.

import { writeFileSync, unlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const PNG = Buffer.from(
  "89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4" +
    "890000000a49444154789c63000100000500010d0a2db40000000049454e44ae426082",
  "hex",
);

function redact(text) {
  return String(text || "")
    .replace(/Bearer\s+[A-Za-z0-9._\-]+/gi, "Bearer [redacted]")
    .replace(/[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}/g, "[email]")
    .replace(/[A-Za-z]:\\[^\s"]+/g, "[path]");
}

async function probe({ mediaType, entityId }) {
  const base = String(process.env.BOOKING_BASE_URL || "").replace(/\/$/, "");
  const token = String(process.env.ADMIN_TOKEN || "").trim();
  const tenant = process.env.FLUXIDI_TEST_TENANT_ID || "fluxidi_fluxidi_ddmh9g";
  const company = process.env.FLUXIDI_TEST_COMPANY_ID || tenant;
  const filePath = join(tmpdir(), `limo-media-probe-${mediaType}.png`);
  writeFileSync(filePath, PNG);
  const url = new URL(`${base}/admin/partners/media/upload`);
  url.searchParams.set("tenant_id", tenant);
  url.searchParams.set("company_id", company);
  const form = new FormData();
  form.set("tenant_id", tenant);
  form.set("company_id", company);
  form.set("media_type", mediaType);
  if (entityId) form.set("entity_id", entityId);
  form.set(
    "file",
    new Blob([PNG], { type: "image/png" }),
    "probe.png",
  );
  const headers = {};
  if (token) headers.Authorization = `Bearer ${token}`;
  let status = 0;
  let body = "";
  try {
    const res = await fetch(url, { method: "POST", headers, body: form });
    status = res.status;
    body = await res.text();
  } catch (error) {
    try {
      unlinkSync(filePath);
    } catch {}
    return {
      media_type: mediaType,
      phase: "network",
      status: 0,
      error: redact(error?.message || "network"),
    };
  }
  try {
    unlinkSync(filePath);
  } catch {}
  let parsed = {};
  try {
    parsed = JSON.parse(body);
  } catch {
    parsed = { raw: redact(body).slice(0, 180) };
  }
  const urlValue = String(parsed.url || "");
  return {
    media_type: mediaType,
    entity_id: entityId || "",
    phase: status >= 200 && status < 300 ? "ok" : "http",
    status,
    ok: parsed.ok === true,
    error: redact(parsed.error || ""),
    returned_media_type: parsed.media_type || "",
    has_url: urlValue.startsWith("https://"),
    url_host: urlValue ? new URL(urlValue).host : "",
    key_suffix: String(parsed.key || "").split("/").slice(-2).join("/"),
    size: parsed.size ?? PNG.length,
    content_type: parsed.content_type || "",
    auth_present: Boolean(token),
    tenant_present: Boolean(tenant && company),
  };
}

const types = [
  { mediaType: "vehicle_photo", entityId: "probe-vehicle-not-used-if-rejected" },
  { mediaType: "vehicle_photo", entityId: "limousine-profile-cover" },
  { mediaType: "vehicle_photo", entityId: "limousine-profile-logo" },
  { mediaType: "limousine_profile_cover" },
  { mediaType: "limousine_profile_logo" },
];

const results = [];
for (const item of types) {
  results.push(await probe(item));
}
const payload = {
  booking_host: new URL(process.env.BOOKING_BASE_URL).host,
  results,
};
console.log(JSON.stringify(payload, null, 2));

if (process.argv.includes("--assert-fallback")) {
  const reserved = results.filter(
    (item) =>
      item.media_type === "vehicle_photo" &&
      (item.entity_id === "limousine-profile-cover" ||
        item.entity_id === "limousine-profile-logo"),
  );
  const failed = reserved.filter((item) => item.status !== 200 || !item.has_url);
  if (failed.length) {
    console.error(
      JSON.stringify({ assert: "fallback-failed", failed }, null, 2),
    );
    process.exit(1);
  }
}
