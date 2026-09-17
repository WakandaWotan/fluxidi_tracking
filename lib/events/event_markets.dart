/// Shared Fluxidi event-market list for website, Worker and app.
///
/// Company countries: `lib/business_settings_page.dart` `_kBusinessCountryCodes`
/// (BE, NL, LU, FR, DE, ES, PT, GB).
/// Extra European customer countries already in Fluxidi billing/phone maps:
/// `lib/main_parts/ride_receipt_body_state.dart` (IT, AT, IE, CH).
/// UK stays the UI key for Ticketmaster GB.
///
/// Selectable ≠ proven coverage. Ticketmaster also returns DK/SE/NO/FI/PL/CZ;
/// those stay out of the UI until Fluxidi offers them.
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
];

const String kFluxidiEventMarketsSource =
    'company:_kBusinessCountryCodes + billing/phone Europe IT/AT/IE/CH';

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
