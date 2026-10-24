/**
 * Injectable RateHawk finish/status polling (P3A).
 *
 * Server-side and attempt-specific. Never resubmits finish. Live
 * finish/status and order/info calls are not authorized.
 */

import {
  RATEHAWK_BOOKING_FINISH_STATUS_PATH,
  RATEHAWK_BOOKING_STATUS_MAX_DURATION_MS,
  RATEHAWK_BOOKING_STATUS_MAX_POLLS,
  RATEHAWK_BOOKING_STATUS_MIN_INTERVAL_MS,
  RATEHAWK_BOOKING_UNRESOLVED_PROVIDER_FIELDS,
  RATEHAWK_ORDER_INFO_PATH,
} from "./ratehawk_booking_contract.mjs";

export function createMockRatehawkBookingStatusTransport({
  sequence = [{ status: "pending" }],
} = {}) {
  const state = { calls: 0, statuses: [] };
  return {
    state,
    statusTransport: async () => {
      const index = Math.min(state.calls, sequence.length - 1);
      state.calls += 1;
      const row = sequence[index] || { status: "pending" };
      state.statuses.push(row.status);
      return {
        ok: true,
        invoked: true,
        status: row.status,
        provider_order_id: row.provider_order_id || null,
        provider_evidence_kind: row.provider_evidence_kind || "finish_status",
        retry_after: row.retry_after ?? null,
        path: RATEHAWK_BOOKING_FINISH_STATUS_PATH,
      };
    },
  };
}

export async function fetchRatehawkBookingStatus({
  statusTransport = null,
} = {}) {
  if (typeof statusTransport !== "function") {
    return {
      ok: false,
      invoked: false,
      reason: "live_booking_transport_forbidden",
      path: RATEHAWK_BOOKING_FINISH_STATUS_PATH,
      unresolved_provider_fields:
        RATEHAWK_BOOKING_UNRESOLVED_PROVIDER_FIELDS.finish_status_request,
    };
  }
  const raw = await statusTransport({
    path: RATEHAWK_BOOKING_FINISH_STATUS_PATH,
  });
  return {
    ok: raw?.ok === true,
    invoked: raw?.invoked === true,
    status: raw?.status || "pending",
    provider_order_id: raw?.provider_order_id || null,
    provider_evidence_kind: raw?.provider_evidence_kind || "finish_status",
    retry_after: raw?.retry_after ?? null,
    reason: raw?.reason || null,
    path: RATEHAWK_BOOKING_FINISH_STATUS_PATH,
  };
}

export async function pollRatehawkBookingFinishStatus({
  statusTransport = null,
  now = Date.now(),
  maxPolls = RATEHAWK_BOOKING_STATUS_MAX_POLLS,
  maxDurationMs = RATEHAWK_BOOKING_STATUS_MAX_DURATION_MS,
  sleepImpl = null,
} = {}) {
  if (typeof statusTransport !== "function") {
    return {
      ok: false,
      invoked: false,
      polls: 0,
      reason: "live_booking_transport_forbidden",
      status: "confirmation_unknown",
    };
  }
  const started = Number(now);
  let polls = 0;
  let last = null;
  while (polls < maxPolls) {
    if (Number(now) - started > maxDurationMs) break;
    last = await fetchRatehawkBookingStatus({ statusTransport });
    polls += 1;
    if (last.status === "confirmed" || last.status === "declined") {
      return { ...last, polls, timed_out: false };
    }
    const waitMs = Math.max(
      RATEHAWK_BOOKING_STATUS_MIN_INTERVAL_MS,
      Number(last.retry_after || 0) * 1000,
    );
    if (typeof sleepImpl === "function") {
      await sleepImpl(waitMs);
      now = Number(now) + waitMs;
    } else {
      now = Number(now) + waitMs;
    }
  }
  return {
    ok: true,
    invoked: last?.invoked === true,
    status: last?.status === "pending" ? "pending" : "confirmation_unknown",
    provider_order_id: last?.provider_order_id || null,
    provider_evidence_kind: last?.provider_evidence_kind || null,
    polls,
    timed_out: last?.status !== "pending",
    reason: last?.status === "pending" ? null : "status_poll_timeout",
    path: RATEHAWK_BOOKING_FINISH_STATUS_PATH,
    order_info_path: RATEHAWK_ORDER_INFO_PATH,
  };
}
