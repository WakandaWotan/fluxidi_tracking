/// Shared Fluxidi event-market list for website, Worker and app.
///
/// Event search is independent of taxi-company registration, billing and
/// phone countries. Those lists do not limit the catalog.
///
/// Selectable countries are the Ticketmaster-proven set plus FR and PT
/// (open research). Eighteen countries is not full European coverage.
/// UK stays the UI key for Ticketmaster GB.
///
/// Event coverage and taxi availability are tracked separately.
const List<String> kFluxidiEventMarketKeys = <String>[
  'be',
  'nl',
  'fr',
  'uk',
  'de',
  'lu',
  'es',
  'pt',
  'it',
  'at',
  'ie',
  'ch',
  'dk',
  'se',
  'no',
  'fi',
  'pl',
  'cz',
];

const String kFluxidiEventMarketsSource =
    'event-catalog independent of company/billing/phone; TM-proven + FR/PT research; not full Europe';

String fluxidiEventCatalogCoverageNote([String language = 'nl']) {
  final String lang = language.trim().toLowerCase();
  switch (lang) {
    case 'fr':
      return 'Dix-huit pays sont sélectionnables. Ce n’est pas une couverture européenne complète. Un événement n’implique pas un taxi Fluxidi.';
    case 'en':
      return 'Eighteen countries are selectable. That is not full European coverage. An event does not imply a Fluxidi taxi.';
    case 'de':
      return 'Achtzehn Länder sind wählbar. Das ist keine vollständige europäische Abdeckung. Ein Event bedeutet nicht automatisch ein Fluxidi-Taxi.';
    case 'es':
      return 'Hay dieciocho países seleccionables. No es una cobertura europea completa. Un evento no implica un taxi Fluxidi.';
    case 'ca':
      return 'Hi ha divuit països seleccionables. No és una cobertura europea completa. Un esdeveniment no implica un taxi Fluxidi.';
    default:
      return 'Achttien landen zijn selecteerbaar. Dat is geen volledige Europese dekking. Een evenement betekent niet automatisch een Fluxidi-taxi.';
  }
}

String fluxidiEventNoCarriersLabel([String language = 'nl']) {
  final String lang = language.trim().toLowerCase();
  switch (lang) {
    case 'fr':
      return 'Aucune entreprise de taxi disponible pour cette course, cette date et cette heure. Aucune réservation n’est promise.';
    case 'en':
      return 'No taxi companies are available for this trip, date and time. No booking is promised.';
    case 'de':
      return 'Keine Taxiunternehmen für diese Fahrt, dieses Datum und diese Uhrzeit verfügbar. Es wird keine Buchung zugesagt.';
    case 'es':
      return 'No hay empresas de taxi disponibles para este viaje, fecha y hora. No se promete ninguna reserva.';
    case 'ca':
      return 'No hi ha empreses de taxi disponibles per a aquest viatge, data i hora. No es promet cap reserva.';
    default:
      return 'Geen beschikbare taxibedrijven voor deze rit, datum en tijd. Er wordt geen boeking beloofd.';
  }
}

String fluxidiEventMarketLabel(String key, [String language = 'nl']) {
  final String lang = language.trim().toLowerCase();
  switch (key.trim().toLowerCase()) {
    case 'be':
      return lang == 'fr'
          ? 'Belgique'
          : lang == 'en'
          ? 'Belgium'
          : lang == 'de'
          ? 'Belgien'
          : lang == 'es'
          ? 'Bélgica'
          : lang == 'ca'
          ? 'Bèlgica'
          : 'België';
    case 'nl':
      return lang == 'fr'
          ? 'Pays-Bas'
          : lang == 'en'
          ? 'Netherlands'
          : lang == 'de'
          ? 'Niederlande'
          : lang == 'es'
          ? 'Países Bajos'
          : lang == 'ca'
          ? 'Països Baixos'
          : 'Nederland';
    case 'fr':
      return lang == 'en'
          ? 'France'
          : lang == 'de'
          ? 'Frankreich'
          : lang == 'es'
          ? 'Francia'
          : lang == 'ca'
          ? 'França'
          : lang == 'fr'
          ? 'France'
          : 'Frankrijk';
    case 'uk':
    case 'gb':
      return lang == 'fr'
          ? 'Royaume-Uni'
          : lang == 'en'
          ? 'United Kingdom'
          : lang == 'de'
          ? 'Vereinigtes Königreich'
          : lang == 'es'
          ? 'Reino Unido'
          : lang == 'ca'
          ? 'Regne Unit'
          : 'Verenigd Koninkrijk';
    case 'de':
      return lang == 'fr'
          ? 'Allemagne'
          : lang == 'en'
          ? 'Germany'
          : lang == 'de'
          ? 'Deutschland'
          : lang == 'es'
          ? 'Alemania'
          : lang == 'ca'
          ? 'Alemanya'
          : 'Duitsland';
    case 'lu':
      return lang == 'fr'
          ? 'Luxembourg'
          : lang == 'en'
          ? 'Luxembourg'
          : lang == 'de'
          ? 'Luxemburg'
          : lang == 'es'
          ? 'Luxemburgo'
          : lang == 'ca'
          ? 'Luxemburg'
          : 'Luxemburg';
    case 'es':
      return lang == 'fr'
          ? 'Espagne'
          : lang == 'en'
          ? 'Spain'
          : lang == 'de'
          ? 'Spanien'
          : lang == 'es'
          ? 'España'
          : lang == 'ca'
          ? 'Espanya'
          : 'Spanje';
    case 'pt':
      return 'Portugal';
    case 'it':
      return lang == 'fr'
          ? 'Italie'
          : lang == 'en'
          ? 'Italy'
          : lang == 'de'
          ? 'Italien'
          : lang == 'es'
          ? 'Italia'
          : lang == 'ca'
          ? 'Itàlia'
          : 'Italië';
    case 'at':
      return lang == 'fr'
          ? 'Autriche'
          : lang == 'en'
          ? 'Austria'
          : lang == 'de'
          ? 'Österreich'
          : lang == 'es'
          ? 'Austria'
          : lang == 'ca'
          ? 'Àustria'
          : 'Oostenrijk';
    case 'ie':
      return lang == 'fr'
          ? 'Irlande'
          : lang == 'en'
          ? 'Ireland'
          : lang == 'de'
          ? 'Irland'
          : lang == 'es'
          ? 'Irlanda'
          : lang == 'ca'
          ? 'Irlanda'
          : 'Ierland';
    case 'ch':
      return lang == 'fr'
          ? 'Suisse'
          : lang == 'en'
          ? 'Switzerland'
          : lang == 'de'
          ? 'Schweiz'
          : lang == 'es'
          ? 'Suiza'
          : lang == 'ca'
          ? 'Suïssa'
          : 'Zwitserland';
    case 'dk':
      return lang == 'fr'
          ? 'Danemark'
          : lang == 'en'
          ? 'Denmark'
          : lang == 'de'
          ? 'Dänemark'
          : lang == 'es'
          ? 'Dinamarca'
          : lang == 'ca'
          ? 'Dinamarca'
          : 'Denemarken';
    case 'se':
      return lang == 'fr'
          ? 'Suède'
          : lang == 'en'
          ? 'Sweden'
          : lang == 'de'
          ? 'Schweden'
          : lang == 'es'
          ? 'Suecia'
          : lang == 'ca'
          ? 'Suècia'
          : 'Zweden';
    case 'no':
      return lang == 'fr'
          ? 'Norvège'
          : lang == 'en'
          ? 'Norway'
          : lang == 'de'
          ? 'Norwegen'
          : lang == 'es'
          ? 'Noruega'
          : lang == 'ca'
          ? 'Noruega'
          : 'Noorwegen';
    case 'fi':
      return lang == 'fr'
          ? 'Finlande'
          : lang == 'en'
          ? 'Finland'
          : lang == 'de'
          ? 'Finnland'
          : lang == 'es'
          ? 'Finlandia'
          : lang == 'ca'
          ? 'Finlàndia'
          : 'Finland';
    case 'pl':
      return lang == 'fr'
          ? 'Pologne'
          : lang == 'en'
          ? 'Poland'
          : lang == 'de'
          ? 'Polen'
          : lang == 'es'
          ? 'Polonia'
          : lang == 'ca'
          ? 'Polònia'
          : 'Polen';
    case 'cz':
      return lang == 'fr'
          ? 'Tchéquie'
          : lang == 'en'
          ? 'Czechia'
          : lang == 'de'
          ? 'Tschechien'
          : lang == 'es'
          ? 'Chequia'
          : lang == 'ca'
          ? 'Txèquia'
          : 'Tsjechië';
    default:
      return key.toUpperCase();
  }
}

String fluxidiEventCountryCode(String marketKey) {
  switch (marketKey.trim().toLowerCase()) {
    case 'uk':
    case 'gb':
      return 'GB';
    default:
      return marketKey.trim().toUpperCase();
  }
}

String fluxidiEventMarketCode(String marketKey) {
  switch (marketKey.trim().toLowerCase()) {
    case 'uk':
    case 'gb':
      return 'gb';
    default:
      return marketKey.trim().toLowerCase();
  }
}
