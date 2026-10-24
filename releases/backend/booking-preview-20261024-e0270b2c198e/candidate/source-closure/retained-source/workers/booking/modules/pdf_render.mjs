// Shared HTML→PDF conversion. One provider client: PDFShift, then PDF_RENDER_URL.
// Extracted from fluxidi_booking_worker.js so invoice and quotation paths share
// the same adapter. Tests must never call a real PDF provider.

import { safeStr } from "./parsing_utils.js";

export async function renderPdfFromHtml(htmlString, env) {
  const pdfShiftKey = safeStr(env?.PDFSHIFT_API_KEY);
  if (pdfShiftKey) {
    const r = await fetch("https://api.pdfshift.io/v3/convert/pdf", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-API-Key": pdfShiftKey,
      },
      body: JSON.stringify({
        source: String(htmlString || ""),
        landscape: false,
        use_print: true,
        sandbox: false,
        margin: "10mm",
        format: "A4",
      }),
    });

    if (!r.ok) {
      const t = await r.text().catch(() => "");
      throw new Error(`PDFShift render failed: ${r.status} ${t}`.slice(0, 300));
    }

    const buf = await r.arrayBuffer();
    return new Uint8Array(buf);
  }

  const url = safeStr(env?.PDF_RENDER_URL);
  if (!url) return null;

  const key = safeStr(env?.PDF_RENDER_KEY);
  const headers = { "Content-Type": "application/json" };
  if (key) headers.Authorization = `Bearer ${key}`;

  const r = await fetch(url, {
    method: "POST",
    headers,
    body: JSON.stringify({ html: String(htmlString || "") }),
  });

  if (!r.ok) {
    const t = await r.text().catch(() => "");
    throw new Error(`PDF render failed: ${r.status} ${t}`.slice(0, 300));
  }

  const buf = await r.arrayBuffer();
  return new Uint8Array(buf);
}
