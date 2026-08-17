/* Shared low-risk crypto/base64/HMAC primitives.
 * Moved verbatim from fluxidi_booking_worker.js (patch BW-M2), no behavior change.
 * Self-contained: no dependency on any domain logic. */

export function base64urlEncodeBytes(bytes) {
  const arr = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes || []);
  let binary = "";
  const chunkSize = 0x2000;
  for (let i = 0; i < arr.length; i += chunkSize) {
    const end = Math.min(i + chunkSize, arr.length);
    let chunk = "";
    for (let j = i; j < end; j++) chunk += String.fromCharCode(arr[j]);
    binary += chunk;
  }
  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

export function base64urlDecodeToBytes(str) {
  const raw = String(str || "").trim();
  if (!raw) return new Uint8Array();
  const normalized = raw
    .replace(/-/g, "+")
    .replace(/_/g, "/")
    .padEnd(Math.ceil(raw.length / 4) * 4, "=");
  const bin = atob(normalized);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

export function jsonBase64urlEncode(obj) {
  const text = JSON.stringify(obj ?? {});
  const bytes = new TextEncoder().encode(text);
  return base64urlEncodeBytes(bytes);
}

export function jsonBase64urlDecode(str) {
  const bytes = base64urlDecodeToBytes(str);
  const text = new TextDecoder().decode(bytes);
  return JSON.parse(text);
}

export async function importHmacKey(secret) {
  const normalized = String(secret || "").trim();
  if (!normalized) throw new Error("missing_calendar_oauth_state_secret");
  const raw = new TextEncoder().encode(normalized);
  return crypto.subtle.importKey(
    "raw",
    raw,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );
}

// BW-M6: pure SHA-256 hex digest helper. Moved verbatim from
// fluxidi_booking_worker.js (no behavior change). Uses WebCrypto SubtleCrypto.
export async function sha256Hex(input) {
  const bytes = new TextEncoder().encode(String(input || ""));
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

// BW-M7A: pure constant-time string comparison. Byte-identical logic to the
// existing `_constantTimeEquals` in fluxidi_booking_worker.js (which stays
// untouched to keep its 19 in-file callers stable); this shared export lets
// modularized code (driver_ops.js, future modules) do timing-safe comparisons
// without importing back into main.
export function constantTimeEquals(a, b) {
  const left = String(a || "");
  const right = String(b || "");
  const maxLen = Math.max(left.length, right.length);
  let diff = left.length ^ right.length;
  for (let i = 0; i < maxLen; i += 1) {
    const ca = i < left.length ? left.charCodeAt(i) : 0;
    const cb = i < right.length ? right.charCodeAt(i) : 0;
    diff |= (ca ^ cb);
  }
  return diff === 0;
}
