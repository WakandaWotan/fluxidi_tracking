// LIMOUSINE-QUOTE-DOCUMENT-P3J — quotation HTML, seller freeze at send, R2 artifact.
//
// Receives only an immutable quotation snapshot for rendering. Does not read the
// live company profile, vehicle catalogue, booking, invoice, Billit, or Peppol.

import { bookingReferenceScopePart, sanitizeTenantString } from "./parsing_utils.js";
import { buildSellerSnapshotFromBusinessProfile } from "./seller_identity.js";
import {
  resolveAndEmbedInvoiceCompanyLogo,
} from "./invoice_company_logo_fetch.js";
import { renderPdfFromHtml as defaultRenderPdfFromHtml } from "./pdf_render.mjs";
import {
  attachLimousineQuotationSnapshot,
  buildLimousineQuotationSnapshotFromRecord,
  freezeLimousineQuotationSellerSnapshot,
  resolveLimousineQuotationSnapshot,
} from "./limousine_quotation_snapshot.mjs";
import {
  formatLimousineQuotationDateTime,
  formatLimousineQuotationInteger,
  formatLimousineQuotationMoney,
  limousineQuotationCopy,
  normalizeLimousineQuotationLocale,
  renderLimousineConditionSentences,
  selectLocalizedQuotationText,
  translateLimousineJourneyType,
} from "./limousine_quotation_i18n.mjs";

export const LIMOUSINE_QUOTATION_STATUS_REF_HEADER = "X-Fluxidi-Status-Ref";
export const LIMOUSINE_QUOTATION_PDF_UNAVAILABLE = "quotation_unavailable";
export const LIMOUSINE_QUOTATION_PDF_REVISION_NOT_FOUND = "quotation_revision_not_found";
export const LIMOUSINE_QUOTATION_PDF_RENDER_FAILED = "quotation_pdf_unavailable";

const COPY_V1 = Object.freeze({
  nl: {
    title: "Offerte",
    not_invoice: "Dit document is een offerte, geen factuur.",
    reference: "Offerteaanvraag",
    revision: "Revisie",
    issued: "Afgiftedatum",
    valid_until: "Geldig tot",
    seller: "Aanbieder",
    journey: "Traject",
    pickup: "Ophaaladres",
    destination: "Bestemming",
    stops: "Tussenstops",
    scheduled: "Gepland tijdstip",
    return_pickup: "Terugrit",
    duration: "Duur (minuten)",
    vehicle: "Voertuig",
    passengers: "Passagiers",
    luggage: "Bagage",
    occasion: "Gelegenheid",
    note: "Opmerking",
    offer: "Aanbod",
    included: "Inbegrepen",
    extras: "Meerprijs extra's",
    mobilisation: "Mobilisatie",
    terms: "Voorwaarden",
    net: "Netto",
    vat: "BTW",
    total: "Totaal incl. BTW",
    footer: "Offerte — geen factuur",
  },
  en: {
    title: "Quotation",
    not_invoice: "This document is a quotation, not an invoice.",
    reference: "Quote request",
    revision: "Revision",
    issued: "Issue date",
    valid_until: "Valid until",
    seller: "Seller",
    journey: "Journey",
    pickup: "Pickup",
    destination: "Destination",
    stops: "Stops",
    scheduled: "Scheduled time",
    return_pickup: "Return journey",
    duration: "Duration (minutes)",
    vehicle: "Vehicle",
    passengers: "Passengers",
    luggage: "Luggage",
    occasion: "Occasion",
    note: "Note",
    offer: "Offer",
    included: "Included",
    extras: "Paid extras",
    mobilisation: "Mobilisation",
    terms: "Terms",
    net: "Net",
    vat: "VAT",
    total: "Total incl. VAT",
    footer: "Quotation — not an invoice",
  },
  fr: {
    title: "Devis",
    not_invoice: "Ce document est un devis, pas une facture.",
    reference: "Demande de devis",
    revision: "Révision",
    issued: "Date d’émission",
    valid_until: "Valable jusqu’au",
    seller: "Prestataire",
    journey: "Trajet",
    pickup: "Prise en charge",
    destination: "Destination",
    stops: "Arrêts",
    scheduled: "Horaire prévu",
    return_pickup: "Retour",
    duration: "Durée (minutes)",
    vehicle: "Véhicule",
    passengers: "Passagers",
    luggage: "Bagages",
    occasion: "Occasion",
    note: "Remarque",
    offer: "Offre",
    included: "Inclus",
    extras: "Suppléments",
    mobilisation: "Mobilisation",
    terms: "Conditions",
    net: "Net",
    vat: "TVA",
    total: "Total TTC",
    footer: "Devis — pas une facture",
  },
  es: {
    title: "Presupuesto",
    not_invoice: "Este documento es un presupuesto, no una factura.",
    reference: "Solicitud de presupuesto",
    revision: "Revisión",
    issued: "Fecha de emisión",
    valid_until: "Válido hasta",
    seller: "Proveedor",
    journey: "Trayecto",
    pickup: "Recogida",
    destination: "Destino",
    stops: "Paradas",
    scheduled: "Hora prevista",
    return_pickup: "Regreso",
    duration: "Duración (minutos)",
    vehicle: "Vehículo",
    passengers: "Pasajeros",
    luggage: "Equipaje",
    occasion: "Ocasión",
    note: "Nota",
    offer: "Oferta",
    included: "Incluido",
    extras: "Extras de pago",
    mobilisation: "Movilización",
    terms: "Condiciones",
    net: "Neto",
    vat: "IVA",
    total: "Total IVA incl.",
    footer: "Presupuesto — no es una factura",
  },
});

function asObject(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function copyV1(locale) {
  const loc = normalizeLimousineQuotationLocale(locale);
  return COPY_V1[loc] || COPY_V1.nl;
}

export function resolveLimousineQuotationLocale(raw) {
  return normalizeLimousineQuotationLocale(raw);
}

export { limousineQuotationCopy };

export function localizedLimousineQuotationText(map, locale, max = 4000) {
  return selectLocalizedQuotationText(map, locale, max);
}

function localizedLimousineQuotationTextV1(map, locale, max = 4000) {
  const src = asObject(map);
  const loc = normalizeLimousineQuotationLocale(locale);
  const order = [loc, "nl", "en", "fr", "es"];
  for (const lang of order) {
    const text = String(src[lang] || "").trim();
    if (text) return text.length > max ? text.slice(0, max) : text;
  }
  return "";
}

export function escapeLimousineQuotationHtml(str) {
  return String(str || "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function safeMultilineHtml(str) {
  return escapeLimousineQuotationHtml(str).replace(/\r\n|\r|\n/g, "<br>");
}

function formatIsoDate(iso, locale) {
  const text = String(iso || "").trim();
  if (!text) return "";
  const ms = Date.parse(text);
  if (!Number.isFinite(ms)) return escapeLimousineQuotationHtml(text);
  try {
    return escapeLimousineQuotationHtml(
      new Intl.DateTimeFormat(locale === "en" ? "en-GB" : locale, {
        dateStyle: "medium",
        timeStyle: "short",
        timeZone: "Europe/Brussels",
      }).format(new Date(ms)),
    );
  } catch (_) {
    return escapeLimousineQuotationHtml(text);
  }
}

function formatMoney(cents, currency, locale) {
  const amount = (Number(cents) || 0) / 100;
  const cur = String(currency || "EUR").toUpperCase();
  try {
    return escapeLimousineQuotationHtml(
      new Intl.NumberFormat(locale === "en" ? "en-GB" : locale, {
        style: "currency",
        currency: cur || "EUR",
      }).format(amount),
    );
  } catch (_) {
    return escapeLimousineQuotationHtml(`${cur} ${amount.toFixed(2)}`);
  }
}

function formatVatRate(rate, locale) {
  const n = Number(rate) || 0;
  const pct = Math.round(n * 10000) / 100;
  const label = limousineQuotationCopy(locale).vat || copyV1(locale).vat;
  return `${escapeLimousineQuotationHtml(label)} ${escapeLimousineQuotationHtml(String(pct))}%`;
}

function row(label, valueHtml) {
  if (!valueHtml) return "";
  return `<tr><th>${escapeLimousineQuotationHtml(label)}</th><td>${valueHtml}</td></tr>`;
}

function listItemsV1(items, locale) {
  if (!Array.isArray(items) || !items.length) return "";
  const parts = [];
  for (const item of items) {
    const src = asObject(item);
    const label =
      localizedLimousineQuotationTextV1(src.label, locale) ||
      src.item_id ||
      src.extra_id ||
      "";
    if (!label) continue;
    const amount =
      src.amount_cents != null
        ? ` (${formatMoney(src.amount_cents, "EUR", locale)})`
        : "";
    parts.push(`<li>${escapeLimousineQuotationHtml(label)}${amount}</li>`);
  }
  return parts.length ? `<ul>${parts.join("")}</ul>` : "";
}

export function buildLimousineQuotationPrintCss() {
  return `
  @page {
    size: A4;
    margin: 12mm 10mm 16mm 10mm;
    @bottom-center {
      content: counter(page) " / " counter(pages);
      font-family: Arial, Helvetica, sans-serif;
      font-size: 9px;
      color: #555;
    }
  }
  body {
    font-family: Arial, Helvetica, sans-serif;
    background: #ffffff;
    margin: 0;
    padding: 0;
    color: #111;
  }
  .quotation-wrapper {
    max-width: 100%;
    margin: 0 auto;
    padding: 8px 4px 16px;
    box-sizing: border-box;
  }
  .quotation-header {
    display: flex;
    justify-content: space-between;
    align-items: flex-start;
    gap: 12px;
    border-bottom: 2px solid #f0c400;
    padding-bottom: 10px;
    margin-bottom: 14px;
  }
  .quotation-logo img {
    max-height: 48px;
    max-width: 220px;
    height: auto;
  }
  h1 {
    font-size: 22px;
    margin: 0 0 6px;
  }
  .disclaimer {
    font-size: 12px;
    color: #333;
    margin: 0 0 12px;
  }
  table.meta, table.journey, table.totals {
    width: 100%;
    border-collapse: collapse;
    margin-bottom: 12px;
  }
  th, td {
    text-align: left;
    vertical-align: top;
    padding: 4px 6px;
    font-size: 12px;
  }
  th { width: 34%; color: #444; font-weight: 600; }
  .section { margin: 14px 0; page-break-inside: avoid; }
  .section h2 {
    font-size: 14px;
    margin: 0 0 8px;
  }
  .terms, .note, .offer-text, .conditions {
    white-space: normal;
    overflow-wrap: anywhere;
    word-break: break-word;
    font-size: 12px;
    line-height: 1.45;
  }
  .conditions {
    margin: 0;
    padding-left: 18px;
  }
  .totals {
    page-break-inside: avoid;
    margin-top: 16px;
  }
  .totals td, .totals th { font-size: 13px; }
  .totals .grand { font-weight: 700; font-size: 15px; }
  .quotation-footer {
    margin-top: 18px;
    padding-top: 8px;
    border-top: 1px solid #ddd;
    font-size: 11px;
    color: #444;
    page-break-inside: avoid;
  }
  `;
}

export function renderLimousineQuotationHtml(snapshot) {
  const snap = asObject(snapshot);
  const rendererVersion = Number(snap.renderer_version) || 1;
  if (rendererVersion < 2) return renderLimousineQuotationHtmlV1(snap);
  return renderLimousineQuotationHtmlV2(snap);
}

function renderLimousineQuotationHtmlV1(snapshot) {
  const snap = asObject(snapshot);
  const locale = resolveLimousineQuotationLocale(snap.locale);
  const copy = copyV1(locale);
  const seller = asObject(snap.seller_snapshot);
  const request = asObject(snap.request_snapshot);
  const vehicle = asObject(snap.vehicle_snapshot);
  const offer = asObject(snap.offer_snapshot);
  const totals = asObject(snap.totals_snapshot);
  const terms = asObject(offer.terms);
  const logo = asObject(seller.logo);
  const sellerName =
    seller.legal_name || seller.trading_name || seller.name || "";
  const sellerLines = [
    seller.legal_name,
    seller.trading_name && seller.trading_name !== seller.legal_name
      ? seller.trading_name
      : "",
    seller.legal_form_label_nl,
    seller.enterprise_number,
    seller.vat_number,
    [seller.address_line, seller.postal_code, seller.city]
      .filter(Boolean)
      .join(" "),
    seller.contact_email,
  ].filter(Boolean);

  const logoHtml =
    logo.present === true && logo.data_uri
      ? `<div class="quotation-logo"><img src="${escapeLimousineQuotationHtml(logo.data_uri)}" alt="${escapeLimousineQuotationHtml(sellerName || copy.seller)}" /></div>`
      : "";

  const termsRows = [
    row("terms_revision", terms.terms_revision != null ? String(terms.terms_revision) : ""),
    row(
      "cancellation_deadline_hours",
      terms.cancellation_deadline_hours != null
        ? String(terms.cancellation_deadline_hours)
        : "",
    ),
    row(
      "cancellation_penalty_percent",
      terms.cancellation_penalty_percent != null
        ? `${terms.cancellation_penalty_percent}%`
        : "",
    ),
    row(
      "waiting_time_included_minutes",
      terms.waiting_time_included_minutes != null
        ? String(terms.waiting_time_included_minutes)
        : "",
    ),
    row(
      "waiting_time_overage_cents_per_minute",
      terms.waiting_time_overage_cents_per_minute != null
        ? formatMoney(terms.waiting_time_overage_cents_per_minute, totals.currency, locale)
        : "",
    ),
    row(
      "no_show_penalty_percent",
      terms.no_show_penalty_percent != null ? `${terms.no_show_penalty_percent}%` : "",
    ),
    row(
      "overtime_cents_per_hour",
      terms.overtime_cents_per_hour != null
        ? formatMoney(terms.overtime_cents_per_hour, totals.currency, locale)
        : "",
    ),
  ].join("");

  const legalBlocks = [
    localizedLimousineQuotationTextV1(terms.customer_obligations, locale),
    localizedLimousineQuotationTextV1(terms.important_information, locale),
  ]
    .filter(Boolean)
    .map((text) => `<p class="terms">${safeMultilineHtml(text)}</p>`)
    .join("");

  return `<!DOCTYPE html>
<html lang="${escapeLimousineQuotationHtml(locale)}">
<head>
  <meta charset="utf-8" />
  <title>${escapeLimousineQuotationHtml(copy.title)}</title>
  <style>${buildLimousineQuotationPrintCss()}</style>
</head>
<body>
  <div class="quotation-wrapper">
    <header class="quotation-header">
      <div>
        <h1>${escapeLimousineQuotationHtml(copy.title)}</h1>
        <p class="disclaimer">${escapeLimousineQuotationHtml(copy.not_invoice)}</p>
      </div>
      ${logoHtml}
    </header>
    <table class="meta">
      ${row(copy.reference, escapeLimousineQuotationHtml(snap.quote_request_id))}
      ${row(copy.revision, escapeLimousineQuotationHtml(String(snap.quote_revision ?? "")))}
      ${row(copy.issued, formatIsoDate(snap.issued_at, locale))}
      ${row(copy.valid_until, formatIsoDate(snap.expires_at, locale))}
    </table>
    <section class="section">
      <h2>${escapeLimousineQuotationHtml(copy.seller)}</h2>
      ${sellerLines.map((line) => `<div>${escapeLimousineQuotationHtml(line)}</div>`).join("")}
    </section>
    <section class="section">
      <h2>${escapeLimousineQuotationHtml(copy.journey)}</h2>
      <table class="journey">
        ${row(copy.journey, escapeLimousineQuotationHtml(request.journey_type))}
        ${row(copy.pickup, escapeLimousineQuotationHtml(request.from))}
        ${row(copy.destination, escapeLimousineQuotationHtml(request.to))}
        ${row(
          copy.stops,
          Array.isArray(request.stops) && request.stops.length
            ? escapeLimousineQuotationHtml(request.stops.join(" · "))
            : "",
        )}
        ${row(copy.scheduled, formatIsoDate(request.scheduled_pickup_iso, locale))}
        ${row(copy.return_pickup, formatIsoDate(request.return_pickup_iso, locale))}
        ${row(
          copy.duration,
          request.requested_duration_minutes != null
            ? escapeLimousineQuotationHtml(String(request.requested_duration_minutes))
            : "",
        )}
        ${row(copy.passengers, request.pax != null ? escapeLimousineQuotationHtml(String(request.pax)) : "")}
        ${row(copy.luggage, request.bags != null ? escapeLimousineQuotationHtml(String(request.bags)) : "")}
        ${row(copy.occasion, escapeLimousineQuotationHtml(request.occasion))}
        ${row(copy.vehicle, escapeLimousineQuotationHtml(vehicle.public_name || vehicle.vehicle_id || ""))}
        ${row(copy.note, request.customer_note ? safeMultilineHtml(request.customer_note) : "")}
      </table>
    </section>
    <section class="section">
      <h2>${escapeLimousineQuotationHtml(copy.offer)}</h2>
      <div class="offer-text">${safeMultilineHtml(localizedLimousineQuotationTextV1(offer.public_text, locale))}</div>
      <h2>${escapeLimousineQuotationHtml(copy.included)}</h2>
      ${listItemsV1(offer.included_services, locale)}
      <h2>${escapeLimousineQuotationHtml(copy.extras)}</h2>
      ${listItemsV1(offer.separately_priced_extras, locale)}
      <h2>${escapeLimousineQuotationHtml(copy.mobilisation)}</h2>
      <div class="note">${safeMultilineHtml(localizedLimousineQuotationTextV1(offer.mobilisation_disclosure, locale))}</div>
    </section>
    <section class="section">
      <h2>${escapeLimousineQuotationHtml(copy.terms)}</h2>
      <table>${termsRows}</table>
      ${legalBlocks}
    </section>
    <table class="totals">
      ${row(copy.net, formatMoney(totals.total_ex_vat_cents, totals.currency, locale))}
      ${row(formatVatRate(totals.vat_rate, locale), formatMoney(totals.vat_amount_cents, totals.currency, locale))}
      <tr class="grand"><th>${escapeLimousineQuotationHtml(copy.total)}</th><td>${formatMoney(totals.total_incl_vat_cents, totals.currency, locale)}</td></tr>
    </table>
    <footer class="quotation-footer">${escapeLimousineQuotationHtml(copy.footer)} · ${escapeLimousineQuotationHtml(copy.not_invoice)}</footer>
  </div>
</body>
</html>`;
}

function sectionHtml(title, inner) {
  const body = String(inner || "").trim();
  if (!title || !body) return "";
  return `<section class="section"><h2>${escapeLimousineQuotationHtml(title)}</h2>${body}</section>`;
}

function listItemsV2(items, locale, currency) {
  if (!Array.isArray(items) || !items.length) return "";
  const parts = [];
  for (const item of items) {
    const src = asObject(item);
    const label = selectLocalizedQuotationText(src.label, locale);
    if (!label) continue;
    const amount =
      src.amount_cents != null
        ? ` (${escapeLimousineQuotationHtml(formatLimousineQuotationMoney(src.amount_cents, src.currency || currency || "EUR", locale))})`
        : "";
    parts.push(`<li>${escapeLimousineQuotationHtml(label)}${amount}</li>`);
  }
  return parts.length ? `<ul>${parts.join("")}</ul>` : "";
}

function renderLimousineQuotationHtmlV2(snapshot) {
  const snap = asObject(snapshot);
  const locale = resolveLimousineQuotationLocale(snap.locale);
  const copy = limousineQuotationCopy(locale);
  const seller = asObject(snap.seller_snapshot);
  const request = asObject(snap.request_snapshot);
  const vehicle = asObject(snap.vehicle_snapshot);
  const offer = asObject(snap.offer_snapshot);
  const totals = asObject(snap.totals_snapshot);
  const terms = asObject(offer.terms);
  const logo = asObject(seller.logo);
  const currency = totals.currency || "EUR";
  const sellerName =
    seller.legal_name || seller.trading_name || seller.name || "";
  const sellerLines = [
    seller.legal_name,
    seller.trading_name && seller.trading_name !== seller.legal_name
      ? seller.trading_name
      : "",
    seller.legal_form_label_nl,
    seller.enterprise_number,
    seller.vat_number,
    [seller.address_line, seller.postal_code, seller.city]
      .filter(Boolean)
      .join(" "),
    seller.contact_email,
  ].filter(Boolean);

  const logoHtml =
    logo.present === true && logo.data_uri
      ? `<div class="quotation-logo"><img src="${escapeLimousineQuotationHtml(logo.data_uri)}" alt="${escapeLimousineQuotationHtml(sellerName || copy.provider)}" /></div>`
      : "";

  const journeyType = translateLimousineJourneyType(request.journey_type, locale);
  const offerText = selectLocalizedQuotationText(offer.public_text, locale);
  const included = listItemsV2(offer.included_services, locale, currency);
  const extras = listItemsV2(offer.separately_priced_extras, locale, currency);
  const mobilisation = selectLocalizedQuotationText(offer.mobilisation_disclosure, locale);
  const obligations = selectLocalizedQuotationText(
    terms.customer_obligations,
    locale,
  );
  const important = selectLocalizedQuotationText(
    terms.important_information,
    locale,
  );
  const conditionSentences = renderLimousineConditionSentences(terms, {
    locale,
    currency,
  });
  const conditionsHtml = conditionSentences.length
    ? `<ul class="conditions">${conditionSentences
        .map((sentence) => `<li class="terms">${escapeLimousineQuotationHtml(sentence)}</li>`)
        .join("")}</ul>`
    : "";

  const journeyRows = [
    row(copy.journey_type, journeyType ? escapeLimousineQuotationHtml(journeyType) : ""),
    row(copy.pickup, escapeLimousineQuotationHtml(request.from)),
    row(copy.destination, escapeLimousineQuotationHtml(request.to)),
    row(
      copy.stops,
      Array.isArray(request.stops) && request.stops.length
        ? escapeLimousineQuotationHtml(request.stops.join(" · "))
        : "",
    ),
    row(
      copy.planned_datetime,
      escapeLimousineQuotationHtml(
        formatLimousineQuotationDateTime(request.scheduled_pickup_iso, locale),
      ),
    ),
    row(
      copy.return_pickup,
      escapeLimousineQuotationHtml(
        formatLimousineQuotationDateTime(request.return_pickup_iso, locale),
      ),
    ),
    row(
      copy.duration_minutes,
      request.requested_duration_minutes != null
        ? escapeLimousineQuotationHtml(
            formatLimousineQuotationInteger(request.requested_duration_minutes),
          )
        : "",
    ),
    row(
      copy.passengers,
      request.pax != null
        ? escapeLimousineQuotationHtml(formatLimousineQuotationInteger(request.pax))
        : "",
    ),
    row(
      copy.luggage,
      request.bags != null
        ? escapeLimousineQuotationHtml(formatLimousineQuotationInteger(request.bags))
        : "",
    ),
    row(copy.occasion, escapeLimousineQuotationHtml(request.occasion)),
    row(
      copy.vehicle,
      escapeLimousineQuotationHtml(vehicle.public_name || ""),
    ),
    row(
      copy.note,
      request.customer_note ? safeMultilineHtml(request.customer_note) : "",
    ),
  ].join("");

  return `<!DOCTYPE html>
<html lang="${escapeLimousineQuotationHtml(locale)}">
<head>
  <meta charset="utf-8" />
  <title>${escapeLimousineQuotationHtml(copy.title)}</title>
  <style>${buildLimousineQuotationPrintCss()}</style>
</head>
<body>
  <div class="quotation-wrapper">
    <header class="quotation-header">
      <div>
        <h1>${escapeLimousineQuotationHtml(copy.title)}</h1>
        <p class="disclaimer">${escapeLimousineQuotationHtml(copy.not_invoice)}</p>
      </div>
      ${logoHtml}
    </header>
    <table class="meta">
      ${row(copy.quotation_request, escapeLimousineQuotationHtml(snap.quote_request_id))}
      ${row(copy.revision, escapeLimousineQuotationHtml(String(snap.quote_revision ?? "")))}
      ${row(
        copy.issue_date,
        escapeLimousineQuotationHtml(formatLimousineQuotationDateTime(snap.issued_at, locale)),
      )}
      ${row(
        copy.valid_until,
        escapeLimousineQuotationHtml(formatLimousineQuotationDateTime(snap.expires_at, locale)),
      )}
    </table>
    ${sectionHtml(
      copy.provider,
      sellerLines.map((line) => `<div>${escapeLimousineQuotationHtml(line)}</div>`).join(""),
    )}
    ${sectionHtml(copy.journey, `<table class="journey">${journeyRows}</table>`)}
    ${sectionHtml(
      copy.offer,
      offerText ? `<div class="offer-text">${safeMultilineHtml(offerText)}</div>` : "",
    )}
    ${sectionHtml(copy.included_services, included)}
    ${sectionHtml(copy.separately_priced_extras, extras)}
    ${sectionHtml(
      copy.mobilisation,
      mobilisation ? `<div class="note">${safeMultilineHtml(mobilisation)}</div>` : "",
    )}
    ${sectionHtml(
      copy.customer_obligations,
      obligations ? `<div class="note">${safeMultilineHtml(obligations)}</div>` : "",
    )}
    ${sectionHtml(
      copy.important_information,
      important ? `<div class="note">${safeMultilineHtml(important)}</div>` : "",
    )}
    ${sectionHtml(copy.conditions, conditionsHtml)}
    <table class="totals">
      ${row(
        copy.net,
        escapeLimousineQuotationHtml(
          formatLimousineQuotationMoney(totals.total_ex_vat_cents, currency, locale),
        ),
      )}
      ${row(
        formatVatRate(totals.vat_rate, locale),
        escapeLimousineQuotationHtml(
          formatLimousineQuotationMoney(totals.vat_amount_cents, currency, locale),
        ),
      )}
      <tr class="grand"><th>${escapeLimousineQuotationHtml(copy.total_incl_vat)}</th><td>${escapeLimousineQuotationHtml(
        formatLimousineQuotationMoney(totals.total_incl_vat_cents, currency, locale),
      )}</td></tr>
    </table>
    <footer class="quotation-footer">${escapeLimousineQuotationHtml(copy.footer)} · ${escapeLimousineQuotationHtml(copy.not_invoice)}</footer>
  </div>
</body>
</html>`;
}

export async function freezeLimousineQuotationSellerAtSend({
  env,
  tenantId,
  companyId,
  profile,
  nowIso = null,
} = {}) {
  const built = buildSellerSnapshotFromBusinessProfile(profile);
  let logoEmbed = null;
  try {
    const logoRef = built?.logo_url || "";
    if (logoRef) {
      const resolved = await resolveAndEmbedInvoiceCompanyLogo({
        env,
        logoRef,
        tenantId,
        companyId,
        nowIso,
      });
      if (resolved?.ok && resolved.data_uri) {
        logoEmbed = {
          present: true,
          mime: resolved.embed?.mime || null,
          sha256: resolved.embed?.sha256 || null,
          data_uri: resolved.data_uri,
        };
      }
    }
  } catch (_) {
    logoEmbed = null;
  }
  return freezeLimousineQuotationSellerSnapshot({
    ...built,
    contact_email: built?.email || null,
    logo: logoEmbed || { present: false },
  });
}

export async function attachLimousineQuotationSnapshotAtSend({
  env,
  record,
  profile,
  nowIso = null,
} = {}) {
  const sellerSnapshot = await freezeLimousineQuotationSellerAtSend({
    env,
    tenantId: record?.tenant_id,
    companyId: record?.company_id,
    profile,
    nowIso,
  });
  const snapshot = await buildLimousineQuotationSnapshotFromRecord({
    record,
    sellerSnapshot,
    issuedAt: nowIso,
  });
  return attachLimousineQuotationSnapshot(record, snapshot);
}

export function buildLimousineQuotationArtifactKey({
  tenantId,
  companyId,
  quoteRequestId,
  revision,
  contentHash,
  rendererVersion,
} = {}) {
  const tenant = bookingReferenceScopePart(tenantId, "unknown");
  const company = bookingReferenceScopePart(companyId, "unknown");
  const quote = bookingReferenceScopePart(quoteRequestId, "quote");
  const rev = Math.max(0, Number(revision) || 0);
  const hash = sanitizeTenantString(contentHash, 80).toLowerCase().replace(/[^a-f0-9]/g, "");
  const version = Math.max(1, Number(rendererVersion) || 1);
  return `private-artifacts/tenant/${tenant}/company/${company}/limousine-quotes/${quote}/revision-${rev}/quotation-v${version}-${hash}.pdf`;
}

export function limousineQuotationPdfFilename(quoteRequestId, revision) {
  const id = bookingReferenceScopePart(quoteRequestId, "quote");
  const rev = Math.max(0, Number(revision) || 0);
  return `quotation-${id}-r${rev}.pdf`;
}

function asPdfBytes(value) {
  if (value instanceof Uint8Array) return value;
  if (value == null) return new Uint8Array();
  return new Uint8Array(value);
}

export async function ensureLimousineQuotationPdfArtifact({
  env,
  record,
  snapshot,
  renderPdfFromHtml = defaultRenderPdfFromHtml,
} = {}) {
  const rec = asObject(record);
  const snap = asObject(snapshot);
  const key = buildLimousineQuotationArtifactKey({
    tenantId: rec.tenant_id,
    companyId: rec.company_id,
    quoteRequestId: rec.quote_request_id || snap.quote_request_id,
    revision: snap.quote_revision,
    contentHash: snap.content_hash,
    rendererVersion: snap.renderer_version,
  });
  const storage = env?.PUBLIC_MEDIA;
  if (!storage || typeof storage.get !== "function" || typeof storage.put !== "function") {
    return { ok: false, error: LIMOUSINE_QUOTATION_PDF_RENDER_FAILED, reason: "missing_public_media" };
  }
  try {
    const existing = await storage.get(key);
    if (existing) {
      const buf = await existing.arrayBuffer();
      return {
        ok: true,
        reused: true,
        key,
        bytes: new Uint8Array(buf),
      };
    }
  } catch (_) {
    return { ok: false, error: LIMOUSINE_QUOTATION_PDF_RENDER_FAILED, reason: "r2_read_failed" };
  }

  let html;
  try {
    html = renderLimousineQuotationHtml(snap);
  } catch (_) {
    return { ok: false, error: LIMOUSINE_QUOTATION_PDF_RENDER_FAILED, reason: "html_failed" };
  }

  let pdfBytes;
  try {
    pdfBytes = asPdfBytes(await renderPdfFromHtml(html, env));
  } catch (err) {
    return {
      ok: false,
      error: LIMOUSINE_QUOTATION_PDF_RENDER_FAILED,
      reason: "render_failed",
      error_class: String(err?.name || "Error"),
    };
  }
  if (!pdfBytes.length) {
    return { ok: false, error: LIMOUSINE_QUOTATION_PDF_RENDER_FAILED, reason: "empty_pdf" };
  }

  try {
    await storage.put(key, pdfBytes, {
      httpMetadata: {
        contentType: "application/pdf",
        cacheControl: "private, no-store, max-age=0",
      },
      customMetadata: {
        artifact_type: "limousine_quotation_pdf",
        tenant_id: String(rec.tenant_id || ""),
        company_id: String(rec.company_id || ""),
        quote_request_id: String(rec.quote_request_id || snap.quote_request_id || ""),
        quote_revision: String(snap.quote_revision ?? ""),
      },
    });
  } catch (_) {
    return { ok: false, error: LIMOUSINE_QUOTATION_PDF_RENDER_FAILED, reason: "r2_write_failed" };
  }

  return { ok: true, reused: false, key, bytes: pdfBytes };
}

export function readLimousineStatusRefHeader(request) {
  if (!request?.headers || typeof request.headers.get !== "function") return "";
  return String(
    request.headers.get(LIMOUSINE_QUOTATION_STATUS_REF_HEADER) ||
      request.headers.get("x-fluxidi-status-ref") ||
      "",
  ).trim();
}

export function parseLimousineQuotationRevisionParam(url, fallbackRevision = null) {
  const raw = url?.searchParams?.get?.("revision");
  if (raw == null || String(raw).trim() === "") return fallbackRevision;
  const n = Number(raw);
  if (!Number.isInteger(n) || n < 1) return null;
  return n;
}

export async function serveLimousineQuotationPdf({
  env,
  record,
  revision = null,
  renderPdfFromHtml = defaultRenderPdfFromHtml,
} = {}) {
  const snap = resolveLimousineQuotationSnapshot(record, revision);
  if (!snap) {
    const requested = revision != null;
    return {
      ok: false,
      status: 404,
      error: requested
        ? LIMOUSINE_QUOTATION_PDF_REVISION_NOT_FOUND
        : LIMOUSINE_QUOTATION_PDF_UNAVAILABLE,
    };
  }
  const artifact = await ensureLimousineQuotationPdfArtifact({
    env,
    record,
    snapshot: snap,
    renderPdfFromHtml,
  });
  if (!artifact.ok) {
    try {
      console.log(
        `[LIMOUSINE_QUOTATION_PDF] error=${artifact.reason || artifact.error} quote_request_id=${sanitizeTenantString(record?.quote_request_id, 120)} revision=${snap.quote_revision}`,
      );
    } catch (_) {}
    return {
      ok: false,
      status: 503,
      error: LIMOUSINE_QUOTATION_PDF_RENDER_FAILED,
    };
  }
  return {
    ok: true,
    status: 200,
    bytes: artifact.bytes,
    filename: limousineQuotationPdfFilename(
      record?.quote_request_id || snap.quote_request_id,
      snap.quote_revision,
    ),
    reused: artifact.reused === true,
  };
}
