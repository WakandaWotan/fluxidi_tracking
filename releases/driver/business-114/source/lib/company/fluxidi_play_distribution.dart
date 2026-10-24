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

import 'package:flutter/material.dart';

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

/// Informational Play notice that grows to show the complete localized copy.
/// It has no purchase action and fits both full-width and add-on cards.
class FluxidiPlaySaasManagedOutsideNotice extends StatelessWidget {
  const FluxidiPlaySaasManagedOutsideNotice({
    required this.languageCode,
    required this.backgroundColor,
    required this.borderColor,
    required this.textColor,
    super.key,
  });

  final String languageCode;
  final Color backgroundColor;
  final Color borderColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.info_outline, size: 13, color: textColor),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              fluxidiPlaySaasManagedOutsideMessage(languageCode: languageCode),
              softWrap: true,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w700,
                fontSize: 11.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
