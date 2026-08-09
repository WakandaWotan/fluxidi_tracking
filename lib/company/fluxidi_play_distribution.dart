/// GOOGLE-PLAY-SAAS-CONSUMPTION-ONLY-P0
///
/// Build-time gate for Google Play distribution.
///
/// Play release AABs are built with:
///   `--dart-define=FLUXIDI_PLAY_DISTRIBUTION=true`
///
/// When enabled:
///   * company SaaS Mollie checkout / upgrades / paid add-ons are blocked
///   * subscription entitlement + status reads remain available
///   * physical taxi ride payments (Mollie / QR / cash / Tap / invoice) are
///     unaffected
///
/// Field / sideload builds omit the define (default false) so existing
/// company checkout behaviour is preserved outside Play.
library;

/// True for the Google Play–distributed binary only.
const bool kFluxidiPlayDistribution = bool.fromEnvironment(
  'FLUXIDI_PLAY_DISTRIBUTION',
  defaultValue: false,
);

/// Company SaaS subscription / add-on Mollie checkout may start only when this
/// is true. Always the inverse of [kFluxidiPlayDistribution].
const bool kFluxidiCompanySaasCheckoutEnabled = !kFluxidiPlayDistribution;

/// Machine-readable error returned when Play distribution blocks SaaS checkout.
const String kFluxidiCompanySaasCheckoutDisabledError =
    'play_saas_checkout_disabled';

/// Pure helper for tests and UI branching. Prefer this over reading the
/// compile-time constant alone so unit tests can inject both modes.
bool mayStartCompanySaasMollieCheckout({
  required bool playDistribution,
}) {
  return !playDistribution;
}

/// Informational copy shown on the subscription page when purchase is disabled
/// for Play distribution. No URL / checkout link is included.
String fluxidiPlaySaasManagedOutsideMessage({
  required String languageCode,
}) {
  switch (languageCode) {
    case 'en':
      return 'Fluxidi company subscriptions are managed outside the Google '
          'Play app. Plan status and entitlements remain available here.';
    case 'fr':
      return 'Les abonnements entreprise Fluxidi sont gérés en dehors de '
          'l’application Google Play. Le statut et les droits restent '
          'visibles ici.';
    case 'es':
      return 'Las suscripciones de empresa Fluxidi se gestionan fuera de la '
          'aplicación de Google Play. El estado y los derechos siguen '
          'disponibles aquí.';
    case 'nl':
    default:
      return 'Fluxidi bedrijfsabonnementen worden buiten de Google Play-app '
          'beheerd. Status en rechten blijven hier zichtbaar.';
  }
}
