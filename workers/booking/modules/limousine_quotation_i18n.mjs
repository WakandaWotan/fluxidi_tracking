// LIMOUSINE-QUOTE-DELIVERY-P3K — centralized quotation PDF localization.
//
// One effective locale per document. Never print raw internal keys or enums.
// Missing translations fail closed (empty string), never the key name.

export const LIMOUSINE_QUOTATION_I18N_LOCALES = Object.freeze(["nl", "en", "fr", "es"]);

export const LIMOUSINE_QUOTATION_I18N_KEYS = Object.freeze([
  "title",
  "not_invoice",
  "quotation_request",
  "revision",
  "issue_date",
  "valid_until",
  "provider",
  "journey",
  "journey_type",
  "pickup",
  "destination",
  "stops",
  "planned_datetime",
  "passengers",
  "luggage",
  "vehicle",
  "offer",
  "included_services",
  "separately_priced_extras",
  "mobilisation",
  "customer_obligations",
  "important_information",
  "conditions",
  "cancellation",
  "waiting_time",
  "no_show",
  "overtime",
  "net",
  "vat",
  "total_incl_vat",
  "currency",
  "footer",
  "return_pickup",
  "duration_minutes",
  "occasion",
  "note",
  "unknown_journey",
]);

export const LIMOUSINE_QUOTATION_JOURNEY_TYPE_KEYS = Object.freeze([
  "point_to_point",
  "roundtrip",
  "hourly",
  "hourly_package",
  "package",
  "airport",
  "airport_transfer",
  "hotel_transfer",
  "event_transfer",
]);

export const LIMOUSINE_QUOTATION_FORBIDDEN_PDF_TOKENS = Object.freeze([
  "point_to_point",
  "terms_revision",
  "cancellation_deadline_hours",
  "cancellation_penalty_percent",
  "waiting_time_included_minutes",
  "waiting_time_overage_cents_per_minute",
  "no_show_penalty_percent",
  "overtime_cents_per_hour",
]);

const COPY = Object.freeze({
  nl: {
    title: "Offerte",
    not_invoice: "Dit document is een offerte, geen factuur.",
    quotation_request: "Offerteaanvraag",
    revision: "Revisie",
    issue_date: "Afgiftedatum",
    valid_until: "Geldig tot",
    provider: "Aanbieder",
    journey: "Traject",
    journey_type: "Trajecttype",
    pickup: "Ophaaladres",
    destination: "Bestemming",
    stops: "Tussenstops",
    planned_datetime: "Gepland tijdstip",
    passengers: "Passagiers",
    luggage: "Bagage",
    vehicle: "Voertuig",
    offer: "Aanbod",
    included_services: "Inbegrepen diensten",
    separately_priced_extras: "Apart geprijsde extras",
    mobilisation: "Mobilisatie",
    customer_obligations: "Klantverplichtingen",
    important_information: "Belangrijke informatie",
    conditions: "Voorwaarden",
    cancellation: "Annulering",
    waiting_time: "Wachttijd",
    no_show: "Niet opdagen",
    overtime: "Overuren",
    net: "Netto",
    vat: "BTW",
    total_incl_vat: "Totaal incl. BTW",
    currency: "Valuta",
    footer: "Offerte — geen factuur",
    return_pickup: "Terugrit",
    duration_minutes: "Duur (minuten)",
    occasion: "Gelegenheid",
    note: "Opmerking",
    unknown_journey: "Traject",
  },
  en: {
    title: "Quotation",
    not_invoice: "This document is a quotation, not an invoice.",
    quotation_request: "Quotation request",
    revision: "Revision",
    issue_date: "Issue date",
    valid_until: "Valid until",
    provider: "Provider",
    journey: "Journey",
    journey_type: "Journey type",
    pickup: "Pickup",
    destination: "Destination",
    stops: "Stops",
    planned_datetime: "Planned date/time",
    passengers: "Passengers",
    luggage: "Luggage",
    vehicle: "Vehicle",
    offer: "Offer",
    included_services: "Included services",
    separately_priced_extras: "Separately priced extras",
    mobilisation: "Mobilisation",
    customer_obligations: "Customer obligations",
    important_information: "Important information",
    conditions: "Conditions",
    cancellation: "Cancellation",
    waiting_time: "Waiting time",
    no_show: "No-show",
    overtime: "Overtime",
    net: "Net",
    vat: "VAT",
    total_incl_vat: "Total including VAT",
    currency: "Currency",
    footer: "Quotation — not an invoice",
    return_pickup: "Return journey",
    duration_minutes: "Duration (minutes)",
    occasion: "Occasion",
    note: "Note",
    unknown_journey: "Journey",
  },
  fr: {
    title: "Devis",
    not_invoice: "Ce document est un devis, pas une facture.",
    quotation_request: "Demande de devis",
    revision: "Révision",
    issue_date: "Date d’émission",
    valid_until: "Valable jusqu’au",
    provider: "Prestataire",
    journey: "Trajet",
    journey_type: "Type de trajet",
    pickup: "Prise en charge",
    destination: "Destination",
    stops: "Arrêts",
    planned_datetime: "Date et heure prévues",
    passengers: "Passagers",
    luggage: "Bagages",
    vehicle: "Véhicule",
    offer: "Offre",
    included_services: "Services inclus",
    separately_priced_extras: "Extras facturés séparément",
    mobilisation: "Mobilisation",
    customer_obligations: "Obligations du client",
    important_information: "Informations importantes",
    conditions: "Conditions",
    cancellation: "Annulation",
    waiting_time: "Temps d’attente",
    no_show: "Non-présentation",
    overtime: "Heures supplémentaires",
    net: "Net",
    vat: "TVA",
    total_incl_vat: "Total TTC",
    currency: "Devise",
    footer: "Devis — pas une facture",
    return_pickup: "Retour",
    duration_minutes: "Durée (minutes)",
    occasion: "Occasion",
    note: "Remarque",
    unknown_journey: "Trajet",
  },
  es: {
    title: "Presupuesto",
    not_invoice: "Este documento es un presupuesto, no una factura.",
    quotation_request: "Solicitud de presupuesto",
    revision: "Revisión",
    issue_date: "Fecha de emisión",
    valid_until: "Válido hasta",
    provider: "Proveedor",
    journey: "Trayecto",
    journey_type: "Tipo de trayecto",
    pickup: "Recogida",
    destination: "Destino",
    stops: "Paradas",
    planned_datetime: "Fecha y hora previstas",
    passengers: "Pasajeros",
    luggage: "Equipaje",
    vehicle: "Vehículo",
    offer: "Oferta",
    included_services: "Servicios incluidos",
    separately_priced_extras: "Extras con precio aparte",
    mobilisation: "Movilización",
    customer_obligations: "Obligaciones del cliente",
    important_information: "Información importante",
    conditions: "Condiciones",
    cancellation: "Cancelación",
    waiting_time: "Tiempo de espera",
    no_show: "No presentación",
    overtime: "Horas extra",
    net: "Neto",
    vat: "IVA",
    total_incl_vat: "Total IVA incluido",
    currency: "Moneda",
    footer: "Presupuesto — no es una factura",
    return_pickup: "Regreso",
    duration_minutes: "Duración (minutos)",
    occasion: "Ocasión",
    note: "Nota",
    unknown_journey: "Trayecto",
  },
});

const JOURNEY_TYPES = Object.freeze({
  point_to_point: {
    nl: "Punt-tot-punt",
    en: "Point-to-point",
    fr: "Trajet point à point",
    es: "Trayecto punto a punto",
  },
  roundtrip: {
    nl: "Heen en terug",
    en: "Round trip",
    fr: "Aller-retour",
    es: "Ida y vuelta",
  },
  hourly: {
    nl: "Uurhuur",
    en: "Hourly",
    fr: "À l’heure",
    es: "Por horas",
  },
  hourly_package: {
    nl: "Uurpakket",
    en: "Hourly package",
    fr: "Forfait horaire",
    es: "Paquete por horas",
  },
  package: {
    nl: "Pakket",
    en: "Package",
    fr: "Forfait",
    es: "Paquete",
  },
  airport: {
    nl: "Luchthaven",
    en: "Airport",
    fr: "Aéroport",
    es: "Aeropuerto",
  },
  airport_transfer: {
    nl: "Luchthaventransfer",
    en: "Airport transfer",
    fr: "Transfert aéroport",
    es: "Traslado al aeropuerto",
  },
  hotel_transfer: {
    nl: "Hoteltransfer",
    en: "Hotel transfer",
    fr: "Transfert hôtel",
    es: "Traslado de hotel",
  },
  event_transfer: {
    nl: "Eventtransfer",
    en: "Event transfer",
    fr: "Transfert événement",
    es: "Traslado de evento",
  },
});

const BCP47 = Object.freeze({
  nl: "nl-BE",
  en: "en-GB",
  fr: "fr-BE",
  es: "es-ES",
});

function asObject(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

export function normalizeLimousineQuotationLocale(raw) {
  const token = String(raw || "")
    .trim()
    .toLowerCase()
    .replace(/_/g, "-");
  if (!token) return "nl";
  const primary = token.split("-")[0];
  if (LIMOUSINE_QUOTATION_I18N_LOCALES.includes(primary)) return primary;
  return "nl";
}

export function limousineQuotationBcp47(locale) {
  const loc = normalizeLimousineQuotationLocale(locale);
  return BCP47[loc] || BCP47.nl;
}

export function missingLimousineQuotationI18nKeys(locale) {
  const loc = normalizeLimousineQuotationLocale(locale);
  const table = COPY[loc] || {};
  return LIMOUSINE_QUOTATION_I18N_KEYS.filter((key) => !String(table[key] || "").trim());
}

export function assertLimousineQuotationI18nComplete() {
  const missing = {};
  for (const locale of LIMOUSINE_QUOTATION_I18N_LOCALES) {
    const keys = missingLimousineQuotationI18nKeys(locale);
    if (keys.length) missing[locale] = keys;
    const journeys = JOURNEY_TYPES;
    for (const journey of LIMOUSINE_QUOTATION_JOURNEY_TYPE_KEYS) {
      if (!String(journeys[journey]?.[locale] || "").trim()) {
        missing[locale] = [...(missing[locale] || []), `journey:${journey}`];
      }
    }
  }
  return missing;
}

export function limousineQuotationCopy(locale) {
  const loc = normalizeLimousineQuotationLocale(locale);
  const table = COPY[loc] || COPY.nl;
  const out = {};
  for (const key of LIMOUSINE_QUOTATION_I18N_KEYS) {
    out[key] = String(table[key] || "").trim();
  }
  return out;
}

export function limousineQuotationLabel(locale, key) {
  const copy = limousineQuotationCopy(locale);
  return copy[key] || "";
}

export function translateLimousineJourneyType(raw, locale) {
  const token = String(raw || "").trim();
  if (!token) return "";
  const loc = normalizeLimousineQuotationLocale(locale);
  const mapped = JOURNEY_TYPES[token];
  if (mapped && mapped[loc]) return mapped[loc];
  try {
    console.warn("[limousine_quotation] unknown_enum category=journey_type");
  } catch (_) {
    // Logging must never throw during render.
  }
  return limousineQuotationLabel(loc, "unknown_journey");
}

export function selectLocalizedQuotationText(value, locale, max = 4000) {
  if (value == null) return "";
  if (typeof value === "string" || typeof value === "number") {
    const text = String(value).trim();
    if (!text) return "";
    return text.length > max ? text.slice(0, max) : text;
  }
  const src = asObject(value);
  const loc = normalizeLimousineQuotationLocale(locale);
  const text = String(src[loc] || "").trim();
  if (!text) return "";
  return text.length > max ? text.slice(0, max) : text;
}

export function formatLimousineQuotationDateTime(iso, locale) {
  const text = String(iso || "").trim();
  if (!text) return "";
  const ms = Date.parse(text);
  if (!Number.isFinite(ms)) return text;
  try {
    return new Intl.DateTimeFormat(limousineQuotationBcp47(locale), {
      dateStyle: "medium",
      timeStyle: "short",
      timeZone: "Europe/Brussels",
    }).format(new Date(ms));
  } catch (_) {
    return text;
  }
}

export function formatLimousineQuotationMoney(cents, currency, locale) {
  const amount = (Number(cents) || 0) / 100;
  const cur = String(currency || "EUR").trim().toUpperCase() || "EUR";
  try {
    return new Intl.NumberFormat(limousineQuotationBcp47(locale), {
      style: "currency",
      currency: cur,
    }).format(amount);
  } catch (_) {
    const loc = normalizeLimousineQuotationLocale(locale);
    const formatted =
      loc === "en" ? amount.toFixed(2) : amount.toFixed(2).replace(".", ",");
    return `${cur} ${formatted}`;
  }
}

export function formatLimousineQuotationPercent(value, locale) {
  const n = Number(value);
  if (!Number.isFinite(n)) return "";
  const loc = normalizeLimousineQuotationLocale(locale);
  const body = Number.isInteger(n)
    ? String(n)
    : loc === "en"
      ? String(n)
      : String(n).replace(".", ",");
  return `${body}%`;
}

export function formatLimousineQuotationInteger(value) {
  const n = Number(value);
  if (!Number.isFinite(n)) return "";
  return String(Math.trunc(n));
}

export function renderLimousineConditionSentences(terms, { locale, currency } = {}) {
  const src = asObject(terms);
  const loc = normalizeLimousineQuotationLocale(locale);
  const cur = String(currency || "EUR").trim().toUpperCase() || "EUR";
  const sentences = [];

  const hours = src.cancellation_deadline_hours;
  if (hours != null && hours !== "" && Number.isFinite(Number(hours))) {
    const n = formatLimousineQuotationInteger(hours);
    sentences.push(
      loc === "en"
        ? `Cancellation is possible up to ${n} hours before the planned departure.`
        : loc === "fr"
          ? `L’annulation est possible jusqu’à ${n} heures avant le départ prévu.`
          : loc === "es"
            ? `La cancelación es posible hasta ${n} horas antes de la salida prevista.`
            : `Annuleren kan tot ${n} uur vóór het geplande vertrek.`,
    );
  }

  const cancelPct = src.cancellation_penalty_percent;
  if (cancelPct != null && cancelPct !== "" && Number.isFinite(Number(cancelPct))) {
    const pct = formatLimousineQuotationPercent(cancelPct, loc);
    sentences.push(
      loc === "en"
        ? `A later cancellation may be charged at ${pct} of the quotation amount.`
        : loc === "fr"
          ? `Une annulation plus tardive peut être facturée à ${pct} du montant du devis.`
          : loc === "es"
            ? `Una cancelación posterior puede facturarse al ${pct} del importe del presupuesto.`
            : `Bij een latere annulering kan ${pct} van het offertebedrag worden aangerekend.`,
    );
  }

  const waitMin = src.waiting_time_included_minutes;
  if (waitMin != null && waitMin !== "" && Number.isFinite(Number(waitMin))) {
    const n = formatLimousineQuotationInteger(waitMin);
    sentences.push(
      loc === "en"
        ? `${n} minutes of waiting time included.`
        : loc === "fr"
          ? `${n} minutes de temps d’attente incluses.`
          : loc === "es"
            ? `${n} minutos de espera incluidos.`
            : `${n} minuten wachttijd inbegrepen.`,
    );
  }

  const waitOver = src.waiting_time_overage_cents_per_minute;
  if (waitOver != null && waitOver !== "" && Number.isFinite(Number(waitOver))) {
    const money = formatLimousineQuotationMoney(waitOver, cur, loc);
    sentences.push(
      loc === "en"
        ? `Additional waiting time: ${money} per minute.`
        : loc === "fr"
          ? `Temps d’attente supplémentaire : ${money} par minute.`
          : loc === "es"
            ? `Tiempo de espera adicional: ${money} por minuto.`
            : `Extra wachttijd: ${money} per minuut.`,
    );
  }

  const noShow = src.no_show_penalty_percent;
  if (noShow != null && noShow !== "" && Number.isFinite(Number(noShow))) {
    const pct = formatLimousineQuotationPercent(noShow, loc);
    sentences.push(
      loc === "en"
        ? `A no-show may be charged at ${pct} of the quotation amount.`
        : loc === "fr"
          ? `Une non-présentation peut être facturée à ${pct} du montant du devis.`
          : loc === "es"
            ? `La no presentación puede facturarse al ${pct} del importe del presupuesto.`
            : `Bij niet opdagen kan ${pct} van het offertebedrag worden aangerekend.`,
    );
  }

  const overtime = src.overtime_cents_per_hour;
  if (overtime != null && overtime !== "" && Number.isFinite(Number(overtime))) {
    const money = formatLimousineQuotationMoney(overtime, cur, loc);
    sentences.push(
      loc === "en"
        ? `Overtime: ${money} per hour.`
        : loc === "fr"
          ? `Heures supplémentaires : ${money} par heure.`
          : loc === "es"
            ? `Horas extra: ${money} por hora.`
            : `Overuren: ${money} per uur.`,
    );
  }

  return sentences;
}
