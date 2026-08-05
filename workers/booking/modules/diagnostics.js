/* Low-risk diagnostics helpers.
 * Moved verbatim from fluxidi_booking_worker.js (patch BW-M3), no behavior change.
 *
 * BW-M3 LITE scope only: the build-tag "/" homepage response and the generic
 * KV name-listing helper. The KPI/rebuild/backfill/repair endpoints are NOT
 * moved here because they still call booking/dispatch/KPI/rating core helpers.
 */

import { corsHeaders } from "./http_response.js";

export function buildBuildTagResponse(buildTag) {
  return new Response(
    `Fluxidi Booking API ✅

Build: ${buildTag}

POST /quote
POST /lead
POST /availability (calendar)
POST /book (calendar + email + invoice)

Payments (Mollie):
POST /pay/create
POST /webhook/mollie
GET  /pay/status?id=
GET  /pay/return?id=

Invoice:
POST /invoice/preview
POST /invoice/pdf

OAuth:
GET /oauth/start
GET /oauth/callback

Mollie Connect:
POST /admin/mollie/connect/start
GET  /mollie/connect/callback
GET  /admin/mollie/connect/status
GET  /admin/mollie/connect/readiness
POST /admin/mollie/connect/test-payment
GET  /admin/mollie/connect/test-payment/status
GET  /admin/mollie/terminals (?testmode=true for test snapshot)
POST /admin/mollie/terminals/sync (body/query testmode=true for test sync)
POST /admin/mollie/terminal-payment/start
POST /driver/mollie/terminal-payment/start
POST /driver/mollie/terminal-payment/status
POST /admin/mollie/connect/disconnect
`,
    { headers: { "Content-Type": "text/plain; charset=utf-8", ...corsHeaders() } }
  );
}

export async function listKvKeyNames(namespace, prefix) {
  if (!namespace) return [];
  const out = [];
  let cursor = undefined;
  do {
    const page = await namespace.list({ prefix, limit: 1000, cursor });
    for (const item of page?.keys || []) {
      if (item?.name) out.push(item.name);
    }
    cursor = page?.cursor;
    if (page?.list_complete !== false) break;
  } while (cursor);
  return out;
}
