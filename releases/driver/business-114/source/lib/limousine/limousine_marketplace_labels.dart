import '../app_strings.dart';
import 'limousine_service_capability.dart';
import 'limousine_state_composition.dart';

/// Customer-entry CTA (NL/EN/FR/ES). German falls back to English.
const LocalizedText kLimousineBookLabel = LocalizedText(
  nl: 'Limousine',
  en: 'Limousine',
  fr: 'Limousine',
  es: 'Limusina',
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

/// Business-settings labels for the six distinguishable availability states.
const Map<LimousinePublicAvailabilityState, LocalizedText>
kLimousineAvailabilityStateLabels =
    <LimousinePublicAvailabilityState, LocalizedText>{
      LimousinePublicAvailabilityState.suspendedOrBlocked: LocalizedText(
        nl: 'Geschorst of geblokkeerd',
        en: 'Suspended or blocked',
        fr: 'Suspendu ou bloqué',
        es: 'Suspendido o bloqueado',
      ),
      LimousinePublicAvailabilityState.unavailableUnderSubscription:
          LocalizedText(
            nl: 'Niet beschikbaar in huidig abonnement',
            en: 'Unavailable under current subscription',
            fr: 'Indisponible avec l’abonnement actuel',
            es: 'No disponible con la suscripción actual',
          ),
      LimousinePublicAvailabilityState.entitledButDisabledByCompany:
          LocalizedText(
            nl: 'Beschikbaar maar uitgeschakeld door bedrijf',
            en: 'Entitled but disabled by company',
            fr: 'Autorisé mais désactivé par l’entreprise',
            es: 'Con derecho pero desactivado por la empresa',
          ),
      LimousinePublicAvailabilityState.enabledButProfileNotPublished:
          LocalizedText(
            nl: 'Ingeschakeld maar profiel niet gepubliceerd',
            en: 'Enabled but public profile not published',
            fr: 'Activé mais profil public non publié',
            es: 'Activado pero perfil público no publicado',
          ),
      LimousinePublicAvailabilityState.publishedButTemporarilyUnavailable:
          LocalizedText(
            nl: 'Gepubliceerd maar tijdelijk niet beschikbaar',
            en: 'Published but temporarily unavailable',
            fr: 'Publié mais temporairement indisponible',
            es: 'Publicado pero temporalmente no disponible',
          ),
      LimousinePublicAvailabilityState.publiclyAvailable: LocalizedText(
        nl: 'Gepubliceerd en zichtbaar',
        en: 'Published and visible',
        fr: 'Publié et visible',
        es: 'Publicado y visible',
      ),
    };

String limousineAvailabilityStateLabelFor(
  LimousinePublicAvailabilityState state,
  AppLanguage language,
) {
  return (kLimousineAvailabilityStateLabels[state] ??
          kLimousinePublicServiceLabel)
      .of(language);
}
