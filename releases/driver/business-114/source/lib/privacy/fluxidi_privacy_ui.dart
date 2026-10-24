/// GOOGLE-PLAY-PRIVACY-READINESS-P0 /
/// PRIVACY-LOCALE-THEME-EMAIL-AND-CUSTOMER-WIDE-TILE-P0-4
///
/// Shared "My data & privacy" / "Privacy & account" surface for customer,
/// business and driver. Opens the canonical privacy policy and a confirmed
/// deletion-request path (never an unsafe hard delete).
///
/// This surface must:
///   * bind to Fluxidi's own `appLanguageNotifier` — the single source of
///     truth every other Fluxidi surface uses — so an NL / FR / EN / ES app
///     renders in that language regardless of the device system locale, and
///     rebuilds live when the language changes anywhere in the app.
///     The device Localizations locale is intentionally not read here.
///   * follow the active Fluxidi theme via `Theme.of(context)`. No hardcoded
///     dark / light Scaffold, AppBar, dialog, text, divider or icon colors.
///     The deletion action is semantically red via
///     `Theme.of(context).colorScheme.error`.
///   * use only the single canonical privacy contact mailbox
///     `kFluxidiPrivacyContactEmail` (info@fluxidi.com); no other privacy
///     address is allowed in `lib/privacy/`.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_config.dart';
import 'fluxidi_background_location_disclosure.dart';
import 'fluxidi_legal_urls.dart';
import 'fluxidi_privacy_account.dart';

/// PRIVACY-LOCALE-PARITY-P0-1 / P0-4: single authoritative language read.
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

String _fallbackLabel(String lang) {
  switch (lang) {
    case 'en':
      return 'Fallback';
    case 'fr':
      return 'Solution de secours';
    case 'es':
      return 'Alternativa';
    case 'nl':
    default:
      return 'Terugval';
  }
}

/// PRIVACY-LOCALE-THEME-EMAIL-AND-CUSTOMER-WIDE-TILE-P0-4:
/// Colon glyph for the fallback / audience sentences. FR follows the
/// typographic convention "espace insécable + deux-points". Other languages
/// use a plain colon.
String _colon(String lang) => lang == 'fr' ? ' : ' : ': ';

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
    // PRIVACY-LOCALE-PARITY-P0-1 / P0-4: rebuild live when the Fluxidi
    // language changes anywhere in the app, matching the behavior of the
    // rest of the shell (`appLanguageNotifier`).
    return AnimatedBuilder(
      animation: appLanguageNotifier,
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context);
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
      // PRIVACY-LOCALE-THEME-EMAIL-AND-CUSTOMER-WIDE-TILE-P0-4:
      // Do not force a background color — inherit from the active theme.
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
                es: 'Abrir la política de privacidad',
              ),
            ),
            // RELEASE-P0-PRIVACY-WEB-LOCALE: subtitle + launch URI follow
            // Fluxidi's selected language via the central helper. Until
            // Shopify publishes proven EN/FR/ES Fluxidi translations, the
            // helper safely falls back to the canonical NL route.
            subtitle: Text(
              fluxidiPrivacyPolicyUriForLanguage(lang).toString(),
            ),
            onTap: () => _launchExternal(
              fluxidiPrivacyPolicyUriForLanguage(lang),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.mail_outline),
            title: Text(
              _t(
                nl: 'Inzage of correctie aanvragen',
                en: 'Request access or correction',
                fr: 'Demander l’accès ou la rectification',
                es: 'Solicitar acceso o rectificación',
              ),
            ),
            subtitle: Text(kFluxidiPrivacyContactEmail),
            onTap: () {
              final audienceKeyword = fluxidiPrivacyAudienceLabel(audience);
              _launchExternal(
                fluxidiPrivacyMailtoUri(
                  subject: _t(
                    nl: 'Fluxidi — verzoek inzage/correctie ($audienceKeyword)',
                    en: 'Fluxidi — access/correction request ($audienceKeyword)',
                    fr: 'Fluxidi — demande d’accès/correction ($audienceKeyword)',
                    es: 'Fluxidi — solicitud de acceso/corrección ($audienceKeyword)',
                  ),
                ),
              );
            },
          ),
          const Divider(),
          if (showDelete)
            ListTile(
              // PRIVACY-LOCALE-THEME-EMAIL-AND-CUSTOMER-WIDE-TILE-P0-4:
              // Semantic error color from the active theme, never a hardcoded
              // red. In dark and light Fluxidi themes this stays consistent.
              leading: Icon(
                Icons.delete_outline,
                color: theme.colorScheme.error,
              ),
              title: Text(
                audience == FluxidiPrivacyAudience.business
                    ? _t(
                        nl: 'Verwijdering bedrijfsaccount aanvragen',
                        en: 'Request business account deletion',
                        fr: 'Demander la suppression du compte d’entreprise',
                        es: 'Solicitar la eliminación de la cuenta de empresa',
                      )
                    : _t(
                        nl: 'Verwijdering account en gegevens aanvragen',
                        en: 'Request account and data deletion',
                        fr: 'Demander la suppression du compte et des données',
                        es: 'Solicitar la eliminación de la cuenta y los datos',
                      ),
                style: TextStyle(color: theme.colorScheme.error),
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
            '${_fallbackLabel(lang)}${_colon(lang)}$kFluxidiPrivacyContactEmail',
            style: theme.textTheme.bodySmall,
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
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Text(
              fluxidiBackgroundLocationDisclosureBody(languageCode: lang),
              style: theme.textTheme.bodyMedium,
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
        // PRIVACY-LOCALE-PARITY-P0-1 / P0-4: dialog also rebinds to
        // `appLanguageNotifier` so an in-app language change while the dialog
        // is open still updates its copy.
        return AnimatedBuilder(
          animation: appLanguageNotifier,
          builder: (ctx, _) {
            final lang = _fluxidiLangCode();
            final retention =
                fluxidiDeletionRetentionExplanation(languageCode: lang);
            final displayAudience = fluxidiPrivacyAudienceDisplayLabel(
              audience: audience,
              languageCode: lang,
            );
            final colon = _colon(lang);
            final fallback = _fallbackLabel(lang);
            return AlertDialog(
              // PRIVACY-LOCALE-THEME-EMAIL-AND-CUSTOMER-WIDE-TILE-P0-4:
              // No hardcoded background / text colors — inherits from
              // Theme.of(ctx).dialogTheme via the AlertDialog defaults.
              title: Text(
                _t(
                  nl: 'Verwijderingsverzoek bevestigen',
                  en: 'Confirm deletion request',
                  fr: 'Confirmer la demande de suppression',
                  es: 'Confirmar la solicitud de eliminación',
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _t(
                        nl: 'Dit verzoek betreft$colon$displayAudience.',
                        en: 'This request concerns$colon$displayAudience.',
                        fr: 'Cette demande concerne$colon$displayAudience.',
                        es: 'Esta solicitud corresponde a$colon$displayAudience.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(retention),
                    const SizedBox(height: 12),
                    Text(
                      _t(
                        nl: 'U wordt doorgestuurd naar de openbare verwijderingspagina. $fallback$colon$kFluxidiPrivacyContactEmail.',
                        en: 'You will be taken to the public deletion page. $fallback$colon$kFluxidiPrivacyContactEmail.',
                        fr: 'Vous serez redirigé vers la page publique de suppression. $fallback$colon$kFluxidiPrivacyContactEmail.',
                        es: 'Se le redirigirá a la página pública de eliminación. $fallback$colon$kFluxidiPrivacyContactEmail.',
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
