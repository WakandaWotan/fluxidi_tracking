/* Shared low-risk HTTP response helpers (CORS + JSON).
 * Moved verbatim from fluxidi_booking_worker.js (patch BW-M1), no behavior change. */

export function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
  };
}

export function json(obj, status = 200) {
  // Recovery evidence is internal storage metadata, including on nested profile responses.
  return new Response(JSON.stringify(obj, (key, value) =>
    key === 'contract_change_audit_recovery' ? undefined : value), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", ...corsHeaders() },
  });
}

export function html(content, status = 200) {
  return new Response(content, {
    status,
    headers: { "Content-Type": "text/html; charset=utf-8", ...corsHeaders() },
  });
}
