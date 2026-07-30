/// GOOGLE-PLAY-PRIVACY-READINESS-P0
///
/// Shared "My data & privacy" / "Privacy & account" surface for customer,
/// business and driver. Opens the canonical privacy policy and a confirmed
/// deletion-request path (not an unsafe hard delete).
///
/// PRIVACY-LOCALE-PARITY-P0-1
/// The privacy UI binds to Fluxidi's own `appLanguageNotifier` — the same
/// source of truth every other Fluxidi surface uses — so that the language
/// selected inside the app (NL/EN/FR/ES) is honored here regardless of the
/// device system locale. Previously this page read the Flutter Localizations
/// widget locale (driven by device / MaterialApp), causing an NL-configured
/// app to render in EN on many phones.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_config.dart';
import 'fluxidi_background_location_disclosure.dart';
import 'fluxidi_legal_urls.dart';
import 'fluxidi_privacy_account.dart';

/// PRIVACY-LOCALE-PARITY-P0-1: single authoritative language read.
String _fluxidiLangCode() => currentLanguageCode;

String _t({
  required String nl,
  required String en,
  required String fr,
  required String es,
}) {
  switch (_fluxidiLangCode()) {
    case 'en':
      return en;
    case 'fr':
      return fr;
    case 'es':
      return es;
    case 'nl':
    default:
      return nl;
  }
}

Future<void> _launchExternal(Uri uri) async {
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Opens the privacy / account hub for [audience].
class FluxidiPrivacyAccountPage extends StatelessWidget {
  const FluxidiPrivacyAccountPage({
    super.key,
    required this.audience,
    this.isCompanyOwnerOrAdmin = false,
    this.sessionDriverId,
  });

  final FluxidiPrivacyAudience audience;
  final bool isCompanyOwnerOrAdmin;
  final String? sessionDriverId;

  @override
  Widget build(BuildContext context) {
    // PRIVACY-LOCALE-PARITY-P0-1: rebuild live when the Fluxidi language
    // changes anywhere in the app, matching the behavior of the rest of the
    // shell (`appLanguageNotifier`).
    return AnimatedBuilder(
      animation: appLanguageNotifier,
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final lang = _fluxidiLangCode();
    final title = fluxidiPrivacySectionTitle(
      audience: audience,
      languageCode: lang,
    );
    final canDeleteBusiness = audience == FluxidiPrivacyAudience.business &&
        mayRequestBusinessAccountDeletion(
          isCompanyOwnerOrAdmin: isCompanyOwnerOrAdmin,
        );
    final canDeleteOwn = mayRequestOwnAccountDeletion(audience: audience);
    final showDelete = audience == FluxidiPrivacyAudience.business
        ? canDeleteBusiness
        : canDeleteOwn;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          ListTile(
            leading: const Icon(Icons.policy_outlined),
            title: Text(
              _t(
                nl: 'Privacybeleid openen',
                en: 'Open privacy policy',
                fr: 'Ouvrir la politique de confidentialité',
                es: 'Abrir política de privacidad',
              ),
            ),
            subtitle: Text(kFluxidiPrivacyPolicyUrl),
            onTap: () => _launchExternal(fluxidiPrivacyPolicyUri()),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.mail_outline),
            title: Text(
              _t(
                nl: 'Inzage of correctie aanvragen',
                en: 'Request access or correction',
                fr: 'Demander l’accès ou une correction',
                es: 'Solicitar acceso o corrección',
              ),
            ),
            subtitle: Text(kFluxidiPrivacyContactEmail),
            onTap: () => _launchExternal(
              fluxidiPrivacyMailtoUri(
                subject: _t(
                  nl: 'Fluxidi — verzoek inzage/correctie (${fluxidiPrivacyAudienceLabel(audience)})',
                  en: 'Fluxidi — access/correction request (${fluxidiPrivacyAudienceLabel(audience)})',
                  fr: 'Fluxidi — demande d’accès/correction (${fluxidiPrivacyAudienceLabel(audience)})',
                  es: 'Fluxidi — solicitud de acceso/corrección (${fluxidiPrivacyAudienceLabel(audience)})',
                ),
              ),
            ),
          ),
          const Divider(),
          if (showDelete)
            ListTile(
              leading: Icon(Icons.delete_outline, color: Colors.red.shade700),
              title: Text(
                audience == FluxidiPrivacyAudience.business
                    ? _t(
                        nl: 'Verwijdering bedrijfaccount aanvragen',
                        en: 'Request business account deletion',
                        fr: 'Demander la suppression du compte entreprise',
                        es: 'Solicitar eliminación de la cuenta empresarial',
                      )
                    : _t(
                        nl: 'Verwijdering account en gegevens aanvragen',
                        en: 'Request account and data deletion',
                        fr: 'Demander la suppression du compte et des données',
                        es: 'Solicitar eliminación de cuenta y datos',
                      ),
              ),
              onTap: () => _confirmAndOpenDeletion(context),
            )
          else if (audience == FluxidiPrivacyAudience.business)
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: Text(
                _t(
                  nl: 'Alleen de geverifieerde bedrijfseigenaar/admin kan een bedrijfsverwijdering starten.',
                  en: 'Only a verified company owner/admin may start a business deletion request.',
                  fr: 'Seul un propriétaire/admin d’entreprise vérifié peut démarrer une suppression.',
                  es: 'Solo un propietario/admin verificado puede iniciar la eliminación empresarial.',
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            _t(
              nl: 'Fallback: $kFluxidiPrivacyContactEmail',
              en: 'Fallback: $kFluxidiPrivacyContactEmail',
              fr: 'Alternative: $kFluxidiPrivacyContactEmail',
              es: 'Alternativa: $kFluxidiPrivacyContactEmail',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (audience == FluxidiPrivacyAudience.driver) ...[
            const SizedBox(height: 24),
            // GOOGLE-PLAY-PRIVACY-READINESS-P0: foreground / active-trip
            // location explanation. The release manifest does NOT declare
            // ACCESS_BACKGROUND_LOCATION and the app never requests "Always"
            // location, so this text intentionally does not claim background
            // or screen-locked use.
            Text(
              fluxidiBackgroundLocationDisclosureTitle(languageCode: lang),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Text(
              fluxidiBackgroundLocationDisclosureBody(languageCode: lang),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmAndOpenDeletion(BuildContext context) async {
    if (audience == FluxidiPrivacyAudience.business &&
        !mayRequestBusinessAccountDeletion(
          isCompanyOwnerOrAdmin: isCompanyOwnerOrAdmin,
        )) {
      return;
    }
    // Driver surface may only request the session driver's own deletion.
    if (audience == FluxidiPrivacyAudience.driver &&
        driverDeletionTargetsCompanyOrOtherDriver(
          requestedAudience: audience,
          targetDriverId: sessionDriverId,
          sessionDriverId: sessionDriverId,
        )) {
      return;
    }
    // Customer surface must never open a company deletion request.
    if (audience == FluxidiPrivacyAudience.customer &&
        customerDeletionTargetsCompany(requestedAudience: audience)) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        // PRIVACY-LOCALE-PARITY-P0-1: dialog also rebinds to
        // `appLanguageNotifier` so an in-app language change while the dialog
        // is open still updates its copy.
        return AnimatedBuilder(
          animation: appLanguageNotifier,
          builder: (ctx, _) {
            final lang = _fluxidiLangCode();
            final retention =
                fluxidiDeletionRetentionExplanation(languageCode: lang);
            return AlertDialog(
              title: Text(
                _t(
                  nl: 'Verwijderingsverzoek bevestigen',
                  en: 'Confirm deletion request',
                  fr: 'Confirmer la demande de suppression',
                  es: 'Confirmar solicitud de eliminación',
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _t(
                        nl: 'Dit verzoek betreft: ${fluxidiPrivacyAudienceLabel(audience)}.',
                        en: 'This request concerns: ${fluxidiPrivacyAudienceLabel(audience)}.',
                        fr: 'Cette demande concerne: ${fluxidiPrivacyAudienceLabel(audience)}.',
                        es: 'Esta solicitud corresponde a: ${fluxidiPrivacyAudienceLabel(audience)}.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(retention),
                    const SizedBox(height: 12),
                    Text(
                      _t(
                        nl: 'U wordt doorgestuurd naar de openbare verwijderingspagina. Alternatief: $kFluxidiPrivacyContactEmail.',
                        en: 'You will be taken to the public deletion page. Fallback: $kFluxidiPrivacyContactEmail.',
                        fr: 'Vous serez redirigé vers la page publique de suppression. Alternative: $kFluxidiPrivacyContactEmail.',
                        es: 'Se le redirigirá a la página pública de eliminación. Alternativa: $kFluxidiPrivacyContactEmail.',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(
                    _t(
                      nl: 'Annuleren',
                      en: 'Cancel',
                      fr: 'Annuler',
                      es: 'Cancelar',
                    ),
                  ),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(
                    _t(
                      nl: 'Doorgaan',
                      en: 'Continue',
                      fr: 'Continuer',
                      es: 'Continuar',
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    if (confirmed != true) return;
    final uri = buildFluxidiAccountDeletionRequestUri(audience: audience);
    assert(isSafeFluxidiAccountDeletionUri(uri));
    await _launchExternal(uri);
  }
}

/// Convenience opener used by customer / business / driver entry points.
void openFluxidiPrivacyAccountPage(
  BuildContext context, {
  required FluxidiPrivacyAudience audience,
  bool isCompanyOwnerOrAdmin = false,
  String? sessionDriverId,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => FluxidiPrivacyAccountPage(
        audience: audience,
        isCompanyOwnerOrAdmin: isCompanyOwnerOrAdmin,
        sessionDriverId: sessionDriverId,
      ),
    ),
  );
}
