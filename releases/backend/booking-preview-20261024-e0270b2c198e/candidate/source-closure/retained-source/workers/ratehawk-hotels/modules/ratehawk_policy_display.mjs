// Display every supplied policy field. Missing values never imply permission,
// inclusion, zero price, or refundable deposits. Plain text only, no HTML.
const labels = {
  pets_type: ['Huisdiertype / gewicht', 'Pet type / weight', 'Type / poids animal', 'Tipo / peso mascota', 'Haustierart / Gewicht'],
  age_start: ['Vanaf leeftijd', 'Minimum age', 'Âge minimum', 'Edad mínima', 'Mindestalter'],
  age_end: ['Tot leeftijd', 'Maximum age', 'Âge maximum', 'Edad máxima', 'Höchstalter'],
  extra_bed: ['Extra bed', 'Extra bed', 'Lit supplémentaire', 'Cama extra', 'Zusatzbett'],
  amount: ['Aantal', 'Quantity', 'Nombre', 'Cantidad', 'Anzahl'],
  inclusion: ['Inbegrepen', 'Inclusion', 'Inclusion', 'Inclusión', 'Inbegriffen'],
  price: ['Bedrag', 'Amount', 'Montant', 'Importe', 'Betrag'],
  currency: ['Valuta', 'Currency', 'Devise', 'Moneda', 'Währung'],
  price_unit: ['Tariefbasis', 'Price basis', 'Base tarifaire', 'Base de precio', 'Preisgrundlage'],
  availability: ['Beschikbaarheid', 'Availability', 'Disponibilité', 'Disponibilidad', 'Verfügbarkeit'],
  payment_type: ['Betaalwijze', 'Payment method', 'Mode de paiement', 'Método de pago', 'Zahlungsart'],
  deposit_type: ['Soort borg', 'Deposit type', 'Type de caution', 'Tipo de depósito', 'Kautionsart'],
  pricing_method: ['Berekening', 'Calculation', 'Calcul', 'Cálculo', 'Berechnung'],
  type: ['Type', 'Type', 'Type', 'Tipo', 'Art'],
  meal_type: ['Maaltijd', 'Meal', 'Repas', 'Comida', 'Mahlzeit'],
  work_area: ['Locatie', 'Location', 'Emplacement', 'Ubicación', 'Ort'],
  territory_type: ['Locatie', 'Location', 'Emplacement', 'Ubicación', 'Ort'],
  fee_type: ['Soort toeslag', 'Fee type', 'Type de frais', 'Tipo de cargo', 'Gebührenart'],
  check_in_check_out_type: ['In-/uitcheckoptie', 'Check-in/out option', 'Option arrivée/départ', 'Opción entrada/salida', 'Check-in/out-Option'],
  day_period: ['Periode', 'Period', 'Période', 'Periodo', 'Zeitraum'],
  time: ['Tijd', 'Time', 'Heure', 'Hora', 'Zeit'],
};
const values = {
  unspecified: ['Niet opgegeven', 'Not specified', 'Non précisé', 'No especificado', 'Nicht angegeben'],
  included: ['Inbegrepen', 'Included', 'Inclus', 'Incluido', 'Inbegriffen'],
  not_included: ['Niet inbegrepen', 'Not included', 'Non inclus', 'No incluido', 'Nicht inbegriffen'],
  available: ['Beschikbaar', 'Available', 'Disponible', 'Disponible', 'Verfügbar'],
  unavailable: ['Niet beschikbaar', 'Unavailable', 'Indisponible', 'No disponible', 'Nicht verfügbar'],
  allowed: ['Toegestaan', 'Allowed', 'Autorisé', 'Permitido', 'Erlaubt'],
  not_allowed: ['Niet toegestaan', 'Not allowed', 'Non autorisé', 'No permitido', 'Nicht erlaubt'],
  cash: ['Contant', 'Cash', 'Espèces', 'Efectivo', 'Bar'],
  card: ['Kaart', 'Card', 'Carte', 'Tarjeta', 'Karte'],
  percent: ['Percentage', 'Percentage', 'Pourcentage', 'Porcentaje', 'Prozentsatz'],
  fixed: ['Vast bedrag', 'Fixed amount', 'Montant fixe', 'Importe fijo', 'Fester Betrag'],
  lt_5kg: ['Minder dan 5 kg', 'Under 5 kg', 'Moins de 5 kg', 'Menos de 5 kg', 'Unter 5 kg'],
  gt_5kg: ['Meer dan 5 kg', 'Over 5 kg', 'Plus de 5 kg', 'Más de 5 kg', 'Über 5 kg'],
  per_car_per_night: ['Per auto per nacht', 'Per car per night', 'Par voiture par nuit', 'Por coche por noche', 'Pro Auto und Nacht'],
  per_car_per_stay: ['Per auto per verblijf', 'Per car per stay', 'Par voiture par séjour', 'Por coche por estancia', 'Pro Auto und Aufenthalt'],
  per_guest_per_night: ['Per gast per nacht', 'Per guest per night', 'Par personne par nuit', 'Por huésped por noche', 'Pro Gast und Nacht'],
  per_guest_per_stay: ['Per gast per verblijf', 'Per guest per stay', 'Par personne par séjour', 'Por huésped por estancia', 'Pro Gast und Aufenthalt'],
  per_room_per_night: ['Per kamer per nacht', 'Per room per night', 'Par chambre par nuit', 'Por habitación por noche', 'Pro Zimmer und Nacht'],
  per_room_per_stay: ['Per kamer per verblijf', 'Per room per stay', 'Par chambre par séjour', 'Por habitación por estancia', 'Pro Zimmer und Aufenthalt'],
  per_hour: ['Per uur', 'Per hour', 'Par heure', 'Por hora', 'Pro Stunde'],
  per_week: ['Per week', 'Per week', 'Par semaine', 'Por semana', 'Pro Woche'],
};

export function formatRatehawkPolicyRows(raw, locale = 'en') {
  const language = ['nl', 'en', 'fr', 'es', 'de'].indexOf(locale);
  const index = language < 0 ? 1 : language;
  const human = value => String(value).replace(/_/g, ' ');
  const scalar = value => values[String(value)]?.[index] ?? human(value);
  const rows = Array.isArray(raw) ? raw : raw == null ? [] : [raw];
  return rows.flatMap(row => {
    if (typeof row === 'string') return row.trim() ? [row.trim()] : [];
    if (!row || typeof row !== 'object') return [];
    // Supplier text is displayed along with numeric restrictions, never instead.
    const fields = Object.entries(row).flatMap(([key, value]) => {
      if (value == null || value === '') return [];
      if (['paragraphs', 'amenities'].includes(key) && Array.isArray(value))
        return value.filter(item => typeof item === 'string');
      const name = labels[key]?.[index] ?? human(key);
      if (typeof value === 'object')
        return formatRatehawkPolicyRows(value, locale).map(line => `${name}: ${line}`);
      return [`${name}: ${scalar(value)}`];
    });
    return fields.length ? [fields.join(' · ')] : [];
  });
}

export function formatRatehawkStaticPolicyDisplay(hotel, locale = 'en') {
  const meta = hotel.metapolicy_struct ?? {};
  const category = hotel.categories ?? {};
  const rows = raw => formatRatehawkPolicyRows(raw, locale);
  return {
    pets: rows(meta.pets ?? category.pets), children: rows(meta.children ?? category.children_age_ranges),
    cots: rows(meta.cot ?? category.cots_extra_beds), extra_beds: rows(meta.extra_bed),
    parking: rows(meta.parking ?? category.internet_parking?.parking),
    internet: rows(meta.internet ?? category.internet_parking?.internet),
    accessibility: rows(category.accessibility), amenities: rows(category.amenities),
    early_late_check_in: rows(meta.check_in_check_out ?? category.early_late_check_in),
    hotel_deposits: rows(meta.deposit ?? category.hotel_deposits),
    additional_fees: rows(meta.add_fee ?? category.taxes_additional_fees),
    children_meals: rows(meta.children_meal), meals: rows(meta.meal),
    no_show: rows(meta.no_show),
    check_in_time: category.check_in_check_out?.check_in_time ?? null,
    check_out_time: category.check_in_check_out?.check_out_time ?? null,
    important_hotel_information: hotel.metapolicy_extra_info ?? category.important_hotel_information ?? null,
    important_policies: rows(hotel.policy_struct),
    additional_conditions: Object.entries(meta).filter(([key]) => ![
      'pets', 'children', 'cot', 'extra_bed', 'parking', 'internet', 'check_in_check_out',
      'deposit', 'add_fee', 'children_meal', 'meal', 'no_show',
    ].includes(key)).flatMap(([key, value]) => rows(value).map(line => `${key.replace(/_/g, ' ')}: ${line}`)),
  };
}
