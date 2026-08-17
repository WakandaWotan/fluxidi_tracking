import '../app_strings.dart';
import 'limousine_service_capability.dart';

/// Customer-entry CTA (NL/EN/FR/ES). German falls back to English.
const LocalizedText kLimousineBookLabel = LocalizedText(
  nl: 'Boek een limousine',
  en: 'Book a limousine',
  fr: 'Réserver une limousine',
  es: 'Reservar una limusina',
);

/// Public-profile / business-settings service chip.
const LocalizedText kLimousinePublicServiceLabel = LocalizedText(
  nl: 'Limousine',
  en: 'Limousine',
  fr: 'Limousine',
  es: 'Limusina',
);

String limousineBookLabelFor(AppLanguage language) =>
    kLimousineBookLabel.of(language);

String limousinePublicServiceLabelFor(AppLanguage language) =>
    kLimousinePublicServiceLabel.of(language);

String limousineBookLabelForCode(String languageCode) {
  switch (languageCode.trim().toLowerCase()) {
    case 'en':
      return kLimousineBookLabel.en;
    case 'fr':
      return kLimousineBookLabel.fr;
    case 'es':
      return kLimousineBookLabel.es;
    case 'nl':
    default:
      return kLimousineBookLabel.nl;
  }
}

/// Resolves the catalog chip for a public service id. Unknown ids return null
/// so existing taxi / airport label switches stay authoritative.
String? limousineCatalogLabelOrNull(String id, AppLanguage language) {
  if (!isLimousineServiceToken(id)) return null;
  return limousinePublicServiceLabelFor(language);
}
