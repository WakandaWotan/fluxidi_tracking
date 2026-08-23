// P3P — mobile-first guest quotation page. Served by the booking Worker.
// Locale copy is selected once from the quotation/request locale.

import { normalizeLimousineQuotationLocale } from "./limousine_quotation_i18n.mjs";

const COPY = Object.freeze({
  nl: {
    title: "Offerte",
    seller: "Aanbieder",
    vehicle: "Voertuig",
    trip: "Traject",
    pickup: "Ophalen",
    destination: "Bestemming",
    stops: "Stops",
    when: "Datum en tijd",
    returnTrip: "Heen en terug",
    yes: "Ja",
    no: "Nee",
    pax: "Passagiers",
    bags: "Bagage",
    occasion: "Gelegenheid",
    offer: "Offerte",
    net: "Bedrag excl. btw",
    vat: "BTW",
    gross: "Totaal incl. btw",
    vatRate: "BTW-tarief",
    terms: "Voorwaarden",
    deadline: "Annuleringstermijn (uren)",
    cancelPct: "Annuleringsboete (%)",
    noShow: "No-showboete (%)",
    waiting: "Inbegrepen wachttijd (minuten)",
    overtime: "Overuren",
    pdf: "Offerte als PDF openen",
    accept: "Offerte accepteren",
    accepted: "Offerte geaccepteerd",
    book: "Boeking afronden",
    payment: "Betaalmethode",
    confirm: "Bevestig boeking",
    billing: "Bedrijfsfactuur nodig",
    legalName: "Juridische naam",
    vatNumber: "BTW-nummer",
    appCta: "Open later in de Fluxidi-app",
    accountCta: "Maak later een account",
    sessionMissing: "Deze link is ongeldig of verlopen.",
    loading: "Laden…",
    error: "Deze offerte kan nu niet worden getoond.",
  },
  en: {
    title: "Quotation",
    seller: "Company",
    vehicle: "Vehicle",
    trip: "Journey",
    pickup: "Pickup",
    destination: "Destination",
    stops: "Stops",
    when: "Date and time",
    returnTrip: "Return trip",
    yes: "Yes",
    no: "No",
    pax: "Passengers",
    bags: "Bags",
    occasion: "Occasion",
    offer: "Quotation",
    net: "Amount excl. VAT",
    vat: "VAT",
    gross: "Total incl. VAT",
    vatRate: "VAT rate",
    terms: "Terms",
    deadline: "Cancellation deadline (hours)",
    cancelPct: "Cancellation penalty (%)",
    noShow: "No-show penalty (%)",
    waiting: "Included waiting time (minutes)",
    overtime: "Overtime",
    pdf: "Open quotation PDF",
    accept: "Accept quotation",
    accepted: "Quotation accepted",
    book: "Complete booking",
    payment: "Payment method",
    confirm: "Confirm booking",
    billing: "I need a company invoice",
    legalName: "Legal name",
    vatNumber: "VAT number",
    appCta: "Open later in the Fluxidi app",
    accountCta: "Create an account later",
    sessionMissing: "This link is invalid or expired.",
    loading: "Loading…",
    error: "This quotation cannot be shown right now.",
  },
  fr: {
    title: "Devis",
    seller: "Prestataire",
    vehicle: "Véhicule",
    trip: "Trajet",
    pickup: "Prise en charge",
    destination: "Destination",
    stops: "Arrêts",
    when: "Date et heure",
    returnTrip: "Aller-retour",
    yes: "Oui",
    no: "Non",
    pax: "Passagers",
    bags: "Bagages",
    occasion: "Occasion",
    offer: "Devis",
    net: "Montant hors TVA",
    vat: "TVA",
    gross: "Total TTC",
    vatRate: "Taux de TVA",
    terms: "Conditions",
    deadline: "Délai d’annulation (heures)",
    cancelPct: "Pénalité d’annulation (%)",
    noShow: "Pénalité no-show (%)",
    waiting: "Temps d’attente inclus (minutes)",
    overtime: "Heures supplémentaires",
    pdf: "Ouvrir le PDF du devis",
    accept: "Accepter le devis",
    accepted: "Devis accepté",
    book: "Finaliser la réservation",
    payment: "Moyen de paiement",
    confirm: "Confirmer la réservation",
    billing: "J’ai besoin d’une facture entreprise",
    legalName: "Raison sociale",
    vatNumber: "Numéro de TVA",
    appCta: "Ouvrir plus tard dans l’app Fluxidi",
    accountCta: "Créer un compte plus tard",
    sessionMissing: "Ce lien est invalide ou expiré.",
    loading: "Chargement…",
    error: "Ce devis ne peut pas être affiché maintenant.",
  },
  es: {
    title: "Presupuesto",
    seller: "Empresa",
    vehicle: "Vehículo",
    trip: "Trayecto",
    pickup: "Recogida",
    destination: "Destino",
    stops: "Paradas",
    when: "Fecha y hora",
    returnTrip: "Ida y vuelta",
    yes: "Sí",
    no: "No",
    pax: "Pasajeros",
    bags: "Equipaje",
    occasion: "Ocasión",
    offer: "Presupuesto",
    net: "Importe sin IVA",
    vat: "IVA",
    gross: "Total con IVA",
    vatRate: "Tipo de IVA",
    terms: "Condiciones",
    deadline: "Plazo de cancelación (horas)",
    cancelPct: "Penalización por cancelación (%)",
    noShow: "Penalización no-show (%)",
    waiting: "Espera incluida (minutos)",
    overtime: "Horas extra",
    pdf: "Abrir PDF del presupuesto",
    accept: "Aceptar presupuesto",
    accepted: "Presupuesto aceptado",
    book: "Completar reserva",
    payment: "Método de pago",
    confirm: "Confirmar reserva",
    billing: "Necesito factura de empresa",
    legalName: "Razón social",
    vatNumber: "NIF/IVA",
    appCta: "Abrir más tarde en la app Fluxidi",
    accountCta: "Crear una cuenta más tarde",
    sessionMissing: "Este enlace no es válido o ha caducado.",
    loading: "Cargando…",
    error: "Este presupuesto no se puede mostrar ahora.",
  },
});

export function limousineExternalPageCopy(locale) {
  const lang = normalizeLimousineQuotationLocale(locale);
  return COPY[lang] || COPY.en;
}

export function renderLimousineExternalQuotationPage({
  locale = "nl",
  missingSession = false,
} = {}) {
  const lang = normalizeLimousineQuotationLocale(locale);
  const t = limousineExternalPageCopy(lang);
  const boot = missingSession ? "missing" : "load";
  return `<!doctype html>
<html lang="${lang}">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
  <meta name="robots" content="noindex,nofollow">
  <title>${t.title}</title>
  <style>
    :root { color-scheme: light dark; --bg:#0f1218; --card:#171c26; --ink:#f4f1ea; --muted:#b7b1a4; --line:#2b3240; --accent:#d4b36a; }
    * { box-sizing: border-box; }
    body { margin:0; font-family: system-ui, -apple-system, Segoe UI, sans-serif; background:var(--bg); color:var(--ink); }
    main { width:min(720px,100%); margin:0 auto; padding:16px 16px 48px; }
    h1,h2 { margin:0 0 8px; }
    h1 { font-size:1.45rem; }
    h2 { font-size:1.05rem; color:var(--accent); }
    section { background:var(--card); border:1px solid var(--line); border-radius:16px; padding:16px; margin:12px 0; }
    .row { display:flex; justify-content:space-between; gap:12px; padding:6px 0; }
    .muted { color:var(--muted); }
    button, .btn { width:100%; min-height:48px; border:0; border-radius:12px; font-weight:700; font-size:1rem; }
    button.primary, .btn.primary { background:var(--accent); color:#1b1408; }
    button.ghost, .btn.ghost { background:transparent; color:var(--ink); border:1px solid var(--line); }
    select, input, textarea { width:100%; min-height:44px; border-radius:10px; border:1px solid var(--line); background:#10151e; color:var(--ink); padding:8px 10px; }
    .stack { display:grid; gap:10px; }
    .err { color:#ffb4b4; }
    @media (min-width:360px) { main { padding:18px 16px 56px; } }
    @media (min-width:390px) { h1 { font-size:1.55rem; } }
    @media (min-width:430px) { section { padding:18px; } }
    @media (min-width:768px) { main { width:min(860px,100%); padding:24px 24px 72px; } .two { display:grid; grid-template-columns:1fr 1fr; gap:12px; } }
    @media (min-width:1100px) { main { width:min(960px,100%); } }
  </style>
</head>
<body>
  <main data-boot="${boot}">
    <h1>${t.title}</h1>
    <p id="status" class="muted">${missingSession ? t.sessionMissing : t.loading}</p>
    <div id="app"></div>
  </main>
  <script>
    const T = ${JSON.stringify(t)};
    const missing = ${missingSession ? "true" : "false"};
    const euro = (cents) => {
      const n = Number(cents || 0) / 100;
      return new Intl.NumberFormat("${lang}", { style: "currency", currency: "EUR" }).format(n);
    };
    const pct = (rate) => {
      const n = Number(rate || 0);
      return (n <= 1 ? (n * 100) : n).toFixed(0) + "%";
    };
    const text = (value) => String(value || "").trim();
    const el = (html) => { const d = document.createElement("div"); d.innerHTML = html; return d; };
    async function api(path, opts) {
      const res = await fetch(path, { credentials: "same-origin", ...opts });
      const type = res.headers.get("content-type") || "";
      if (type.includes("application/pdf")) return res;
      const body = await res.json().catch(() => ({}));
      if (!res.ok || body.ok === false) throw new Error(body.error || "error");
      return body;
    }
    function row(label, value) {
      if (!text(value)) return "";
      return '<div class="row"><span class="muted">' + label + '</span><strong>' + value + '</strong></div>';
    }
    function renderQuote(data) {
      const q = data.quote_request || {};
      const quote = q.quote || {};
      const terms = quote.terms || {};
      const seller = data.seller || {};
      const vehicle = q.vehicle_snapshot || {};
      const trip = data.trip || {};
      const accepted = q.state === "accepted" || q.state === "booking_created";
      const booked = q.state === "booking_created";
      const methods = ((data.payment_capability || {}).public_payment_options || []).map((item) => {
        const id = item.id || item.method || item.payment_method;
        const label = item.label || item.name || id;
        return '<option value="' + id + '">' + label + '</option>';
      }).join("");
      document.getElementById("status").textContent = accepted ? T.accepted : "";
      document.getElementById("app").innerHTML = [
        '<section><h2>' + T.seller + '</h2>' + row(T.seller, seller.trading_name || seller.name) + '</section>',
        '<section><h2>' + T.vehicle + '</h2>' + row(T.vehicle, vehicle.public_name || vehicle.name) + '</section>',
        '<section><h2>' + T.trip + '</h2>' +
          row(T.pickup, trip.from) + row(T.destination, trip.to) +
          row(T.stops, (trip.stops || []).join(" · ")) +
          row(T.when, q.scheduled_pickup_iso) +
          row(T.returnTrip, q.roundtrip ? T.yes : T.no) +
          row(T.pax, q.pax) + row(T.bags, q.bags) + row(T.occasion, q.occasion) +
        '</section>',
        '<section><h2>' + T.offer + '</h2>' +
          row(T.net, euro(quote.total_ex_vat_cents)) +
          row(T.vat, euro(quote.vat_amount_cents)) +
          row(T.gross, euro(quote.total_incl_vat_cents)) +
          row(T.vatRate, pct(quote.vat_rate)) +
          (quote.public_text && (quote.public_text.${lang} || quote.public_text.nl || quote.public_text.en)
            ? '<p>' + (quote.public_text.${lang} || quote.public_text.nl || quote.public_text.en) + '</p>' : '') +
        '</section>',
        '<section><h2>' + T.terms + '</h2>' +
          row(T.deadline, terms.cancellation_deadline_hours) +
          row(T.cancelPct, terms.cancellation_penalty_percent) +
          row(T.noShow, terms.no_show_penalty_percent) +
          row(T.waiting, terms.waiting_time_included_minutes) +
        '</section>',
        '<section class="stack"><button class="ghost" id="pdf">' + T.pdf + '</button>' +
          (accepted ? '' : '<button class="primary" id="accept">' + T.accept + '</button>') +
        '</section>',
        (accepted && !booked ? '<section class="stack" id="book"><h2>' + T.book + '</h2>' +
          '<label>' + T.payment + '</label><select id="pay">' + methods + '</select>' +
          '<label><input type="checkbox" id="bill"> ' + T.billing + '</label>' +
          '<div id="billfields" class="stack" hidden><input id="legal" placeholder="' + T.legalName + '"><input id="vatn" placeholder="' + T.vatNumber + '"></div>' +
          '<button class="primary" id="confirm">' + T.confirm + '</button></section>' : ''),
        (accepted ? '<section class="stack"><button class="ghost" id="appcta">' + T.appCta + '</button><button class="ghost" id="acct">' + T.accountCta + '</button></section>' : '')
      ].join("");
      document.getElementById("pdf")?.addEventListener("click", async () => {
        const res = await api("/l/api/quotation.pdf");
        const blob = await res.blob();
        window.open(URL.createObjectURL(blob), "_blank");
      });
      document.getElementById("accept")?.addEventListener("click", async () => {
        await api("/l/api/accept", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ expected_revision: q.revision }) });
        await load();
      });
      document.getElementById("bill")?.addEventListener("change", (ev) => {
        document.getElementById("billfields").hidden = !ev.target.checked;
      });
      document.getElementById("confirm")?.addEventListener("click", async () => {
        const body = { payment_method: document.getElementById("pay")?.value };
        if (document.getElementById("bill")?.checked) {
          body.billing_customer = { legal_name: document.getElementById("legal").value, vat_number: document.getElementById("vatn").value };
        }
        const bookedRes = await api("/l/api/book", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });
        if (bookedRes.checkout_url) { location.href = bookedRes.checkout_url; return; }
        await load();
      });
    }
    async function load() {
      if (missing) return;
      try {
        const data = await api("/l/api/quotation");
        renderQuote(data);
      } catch (err) {
        document.getElementById("status").textContent = T.error;
      }
    }
    load();
  </script>
</body>
</html>`;
}
