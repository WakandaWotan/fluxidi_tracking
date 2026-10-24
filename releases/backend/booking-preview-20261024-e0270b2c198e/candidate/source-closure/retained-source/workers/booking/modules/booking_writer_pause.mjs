// Operational prerequisite for cutover, not proof of deployment drain or KV
// consistency. No ordinary writer may run while frozen, including GET handlers
// that recover projections. Keep physical claims and recovery jobs intact.
export const bookingWritersPaused = env => env?.BOOKING_WRITER_PAUSE_ENABLED === '1';
export function bookingWriterPauseResponse(headers = {}) {
  return Response.json({ ok: false, error: 'booking_writers_paused', retryable: true }, {
    status: 503, headers: { ...headers, 'retry-after': '60', 'cache-control': 'no-store' },
  });
}
export function allowsPausedBookingRequest(request) {
  return request.method === 'OPTIONS' || request.method === 'POST'
    && ['/admin/company/capacity/baseline', '/admin/company/capacity/reconcile-cancelled-legs', '/admin/dashboard/bookings-kpis/rebuild'].includes(new URL(request.url).pathname)
    || request.method === 'GET'
    && ['/admin/legacy-scope/census', '/admin/company/capacity/inventory'].includes(new URL(request.url).pathname);
}
export function allowsPausedCoordinatorAction(body) {
  // inspect is genuinely read-only. read can adopt legacy records or recover
  // projections, so it must not bypass the pause.
  return body?.action === 'canonical_booking' && body?.operation === 'inspect';
}
export async function deferPausedBookingAlarm(state, env) {
  if (!bookingWritersPaused(env)) return false;
  // Cloudflare consumes a delivered alarm. Rearm it without consuming jobs.
  // Throw on failure so the platform retries rather than losing recovery.
  await state.storage.setAlarm(Date.now() + 60_000);
  return true;
}
