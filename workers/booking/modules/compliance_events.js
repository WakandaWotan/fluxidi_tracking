/* Compliance-events helpers: URL builder, best-effort event emitter, and pure
 * text/enum normalizers shared by booking-lifecycle event builders in main.
 * Moved verbatim from fluxidi_booking_worker.js (patch BW-M5), no behavior change.
 *
 * BW-M5 LITE scope: only the pure helpers + the fire-and-forget outbound
 * emitter live here. Event builders / marker persistence / lifecycle
 * orchestrators (buildBooking*ComplianceEvent, _*ComplianceAlreadyEmitted,
 * _persist*ComplianceMarker, _emit*Compliance*IfNeeded, etc.) all read/write
 * booking/payment/document/leg record shapes and STAY in main to avoid a
 * circular import with booking-core helpers.
 */

import { safeStr } from "./parsing_utils.js";

/* Canonical compliance-worker path for the best-effort event emitter. */
export const COMPLIANCE_APPEND_PATH = "/compliance/events/append";

/* Build a validated append URL from the raw COMPLIANCE_API_URL env value.
 * Returns a URL object or null. Rejects any base with a query/hash or a
 * mismatched pathname; only "/" or the canonical append path are accepted. */
export function buildComplianceAppendUrl(baseUrlRaw) {
  const normalized = safeStr(baseUrlRaw);
  if (!normalized) return null;
  try {
    const parsed = new URL(normalized);
    parsed.search = "";
    parsed.hash = "";
    const normalizedPath = parsed.pathname.replace(/\/+$/, "");
    if (normalizedPath === COMPLIANCE_APPEND_PATH) return parsed;
    if (normalizedPath === "" || normalizedPath === "/") {
      parsed.pathname = COMPLIANCE_APPEND_PATH;
      return parsed;
    }
    return null;
  } catch (_) {
    return null;
  }
}

/* Fold provider/lifecycle status strings into the compliance-worker's four
 * canonical values: paid, pending, failed, unpaid, unknown. */
export function normalizeCompliancePaymentStatus(value) {
  const raw = safeStr(value).toLowerCase();
  if (!raw) return "unknown";
  if (raw === "paid" || raw === "confirmed" || raw === "completed" || raw === "success" || raw === "settled") {
    return "paid";
  }
  if (raw === "pending" || raw === "authorized" || raw === "open" || raw === "processing") {
    return "pending";
  }
  if (raw === "failed" || raw === "cancelled" || raw === "canceled" || raw === "declined") {
    return "failed";
  }
  if (raw === "unpaid" || raw === "not_paid") {
    return "unpaid";
  }
  return "unknown";
}

/* Lowercase-normalize a free-text compliance value with a stable fallback. */
export function normalizeComplianceText(value, fallback = "unknown") {
  const text = safeStr(value).toLowerCase();
  return text || fallback;
}

/* Boolean check for "no meaningful value" tokens used by compliance event
 * pickers to skip placeholder inputs. */
export function isUnknownLikeCompliancePaymentValue(value) {
  const raw = String(value ?? "").trim().toLowerCase();
  return (
    raw === "" ||
    raw === "unknown" ||
    raw === "onbekend" ||
    raw === "—" ||
    raw === "-" ||
    raw === "null" ||
    raw === "undefined"
  );
}

/* Return the first candidate that survives safeStr + unknown-like filtering,
 * else null. */
export function pickMeaningfulCompliancePaymentValue(...candidates) {
  for (const candidate of candidates) {
    const text = safeStr(candidate);
    if (!text) continue;
    if (isUnknownLikeCompliancePaymentValue(text)) continue;
    return text;
  }
  return null;
}

/* Detect "online via Mollie" payments based on provider/source hints only.
 * Pure predicate; does not read a booking record shape. */
export function compliancePaymentLooksMollieOnline({ provider, source } = {}) {
  const prov = String(provider ?? "").trim().toLowerCase();
  const src = String(source ?? "").trim().toLowerCase();
  return (
    prov === "mollie" ||
    src === "mollie" ||
    src === "online" ||
    src === "online_payment" ||
    src === "online-payment"
  );
}

/* Best-effort compliance-worker append emitter.
 *
 * Contract:
 *   - Fire-and-forget, single fetch, 1500 ms cap (configurable but clamped).
 *   - Reads env.COMPLIANCE_API_URL + env.COMPLIANCE_ADMIN_TOKEN (falls back to
 *     env.ADMIN_TOKEN). NEVER logs the token.
 *   - Prefers env.COMPLIANCE_WORKER service binding when available (labelled
 *     "service_binding"), falls back to public fetch ("public_fetch").
 *   - Returns { ok, skipped?, status?, error? }; never throws.
 *   - Callers should NOT rely on emit success for correctness.
 */
export async function emitComplianceEventBestEffort(env, event, options = {}) {
  try {
    const baseUrlRaw = safeStr(env?.COMPLIANCE_API_URL);
    const adminToken = safeStr(env?.COMPLIANCE_ADMIN_TOKEN || env?.ADMIN_TOKEN);
    const logLabel = safeStr(options?.logLabel) || "payment_update";
    if (!baseUrlRaw || !adminToken) {
      console.log(`[COMPLIANCE_EMIT][${logLabel}] skipped reason=missing_config`);
      return { ok: false, skipped: "missing_config" };
    }
    if (!event || typeof event !== "object" || Array.isArray(event)) {
      console.log(`[COMPLIANCE_EMIT][${logLabel}] skipped reason=invalid_event`);
      return { ok: false, skipped: "invalid_event" };
    }
    const appendUrl = buildComplianceAppendUrl(baseUrlRaw);
    if (!appendUrl) {
      console.log(`[COMPLIANCE_EMIT][${logLabel}] skipped reason=invalid_url_config`);
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
          `[COMPLIANCE_EMIT][${logLabel}] failed status=${resp.status} transport=${transport} origin=${appendUrl.origin} path=${appendUrl.pathname}`,
        );
        return { ok: false, status: resp.status };
      }
      // TODO: reduce/remove success log after rollout verification.
      console.log(`[COMPLIANCE_EMIT][${logLabel}] ok transport=${transport}`);
      return { ok: true, status: resp.status };
    } catch (err) {
      if (err?.name === "AbortError") {
        console.log(`[COMPLIANCE_EMIT][${logLabel}] failed error=timeout`);
        return { ok: false, error: "timeout" };
      }
      console.log(`[COMPLIANCE_EMIT][${logLabel}] failed error=fetch_failed`);
      return { ok: false, error: "fetch_failed" };
    } finally {
      clearTimeout(timer);
    }
  } catch (_) {
    return { ok: false, error: "internal_error" };
  }
}
