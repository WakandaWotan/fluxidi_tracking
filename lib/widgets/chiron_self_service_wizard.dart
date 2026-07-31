// RELEASE-P0-CHIRON-SELF-SERVICE-2026-07-31
//
// Compact 3-step Chiron onboarding for non-technical taxi operators.
// Replaces the previous 8-paragraph ExpansionTile wall of text.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_config.dart';
import '../app_strings.dart';
import '../chiron_company_connection_config.dart';

/// Official Chiron portal URLs (never from operator input).
const String kChironTestPortalUrl =
    'https://chiron-acc.vlaanderen.be/chiron/registratie/toegang';
const String kChironProductionPortalUrl =
    'https://chiron.vlaanderen.be/chiron/registratie/toegang';

enum ChironWizardStepState {
  notStarted,
  actionRequired,
  inProgress,
  succeeded,
  error,
}

class ChironSelfServiceWizard extends StatelessWidget {
  const ChironSelfServiceWizard({
    super.key,
    required this.status,
    required this.language,
    required this.textPrimary,
    required this.textSecondary,
    required this.panelColor,
    required this.borderColor,
    required this.accentColor,
    this.onOpenTestPortal,
    this.onOpenProductionPortal,
  });

  final BackendChironConnectionStatus? status;
  final AppLanguage language;
  final Color textPrimary;
  final Color textSecondary;
  final Color panelColor;
  final Color borderColor;
  final Color accentColor;
  final VoidCallback? onOpenTestPortal;
  final VoidCallback? onOpenProductionPortal;

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
    String? de,
  }) {
    switch (language) {
      case AppLanguage.nl:
        return nl;
      case AppLanguage.en:
        return en;
      case AppLanguage.fr:
        return fr;
      case AppLanguage.es:
        return es;
      case AppLanguage.de:
        return de ?? en;
    }
  }

  ChironWizardStepState get _step1 {
    final s = status;
    if (s == null) return ChironWizardStepState.notStarted;
    if (!s.testCredentialsStored) return ChironWizardStepState.actionRequired;
    if (s.lastConnectionStatus == ChironConnectionStatus.testFailed) {
      return ChironWizardStepState.error;
    }
    if (s.lastConnectionStatus == ChironConnectionStatus.testPassed) {
      return ChironWizardStepState.succeeded;
    }
    return ChironWizardStepState.actionRequired;
  }

  ChironWizardStepState get _step2 {
    final s = status;
    if (s == null || _step1 != ChironWizardStepState.succeeded) {
      return ChironWizardStepState.notStarted;
    }
    final tf = s.testflowStatus.trim().toLowerCase();
    if (tf == 'complete') return ChironWizardStepState.succeeded;
    if (tf == 'in_progress') return ChironWizardStepState.inProgress;
    return ChironWizardStepState.actionRequired;
  }

  ChironWizardStepState get _step3 {
    final s = status;
    if (_step2 != ChironWizardStepState.succeeded) {
      return ChironWizardStepState.notStarted;
    }
    if (s?.productionSubmitActive == true) {
      return ChironWizardStepState.succeeded;
    }
    if (s?.productionCredentialsStored == true &&
        s?.productionLastConnectionStatus ==
            ChironConnectionStatus.testFailed) {
      return ChironWizardStepState.error;
    }
    return ChironWizardStepState.actionRequired;
  }

  String _stateLabel(ChironWizardStepState state) {
    switch (state) {
      case ChironWizardStepState.notStarted:
        return _t(
          nl: 'Niet gestart',
          en: 'Not started',
          fr: 'Non commencé',
          es: 'No iniciado',
          de: 'Nicht gestartet',
        );
      case ChironWizardStepState.actionRequired:
        return _t(
          nl: 'Actie vereist',
          en: 'Action required',
          fr: 'Action requise',
          es: 'Acción requerida',
          de: 'Aktion erforderlich',
        );
      case ChironWizardStepState.inProgress:
        return _t(
          nl: 'Bezig',
          en: 'In progress',
          fr: 'En cours',
          es: 'En curso',
          de: 'In Bearbeitung',
        );
      case ChironWizardStepState.succeeded:
        return _t(
          nl: 'Geslaagd',
          en: 'Succeeded',
          fr: 'Réussi',
          es: 'Correcto',
          de: 'Erfolgreich',
        );
      case ChironWizardStepState.error:
        return _t(
          nl: 'Fout',
          en: 'Error',
          fr: 'Erreur',
          es: 'Error',
          de: 'Fehler',
        );
    }
  }

  Color _stateColor(ChironWizardStepState state) {
    switch (state) {
      case ChironWizardStepState.succeeded:
        return const Color(0xFF1F7A4A);
      case ChironWizardStepState.error:
        return const Color(0xFFB42318);
      case ChironWizardStepState.inProgress:
        return accentColor;
      case ChironWizardStepState.actionRequired:
        return const Color(0xFFB54708);
      case ChironWizardStepState.notStarted:
        return textSecondary;
    }
  }

  Future<void> _openUrl(String url, BuildContext context) async {
    final uri = Uri.parse(url);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t(
                nl: 'Kon het portaal niet openen. Kopieer de link handmatig.',
                en: 'Could not open the portal. Copy the link manually.',
                fr: 'Impossible d’ouvrir le portail. Copiez le lien manuellement.',
                es: 'No se pudo abrir el portal. Copie el enlace manualmente.',
                de: 'Portal konnte nicht geöffnet werden. Link manuell kopieren.',
              ),
            ),
          ),
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Kon het portaal niet openen. Kopieer de link handmatig.',
              en: 'Could not open the portal. Copy the link manually.',
              fr: 'Impossible d’ouvrir le portail. Copiez le lien manuellement.',
              es: 'No se pudo abrir el portal. Copie el enlace manualmente.',
              de: 'Portal konnte nicht geöffnet werden. Link manuell kopieren.',
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = <({String title, ChironWizardStepState state})>[
      (
        title: _t(
          nl: 'Testverbinding',
          en: 'Test connection',
          fr: 'Connexion test',
          es: 'Conexión de prueba',
          de: 'Testverbindung',
        ),
        state: _step1,
      ),
      (
        title: _t(
          nl: 'Acceptatietest',
          en: 'Acceptance test',
          fr: 'Test d’acceptation',
          es: 'Prueba de aceptación',
          de: 'Akzeptanztest',
        ),
        state: _step2,
      ),
      (
        title: _t(
          nl: 'Productieverbinding',
          en: 'Production connection',
          fr: 'Connexion production',
          es: 'Conexión de producción',
          de: 'Produktionsverbindung',
        ),
        state: _step3,
      ),
    ];

    return Container(
      key: const ValueKey('chiron_self_service_wizard'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t(
              nl: 'Chiron instellen',
              en: 'Set up Chiron',
              fr: 'Configurer Chiron',
              es: 'Configurar Chiron',
              de: 'Chiron einrichten',
            ),
            style: TextStyle(
              color: textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _t(
              nl:
                  'Fluxidi registreert uw ritten automatisch bij Chiron. De koppeling gebeurt in drie eenvoudige stappen: eerst de testverbinding, daarna vijf testritten en ten slotte de productieverbinding voor uw echte ritten.',
              en:
                  'Fluxidi registers your rides with Chiron automatically. Setup has three simple steps: test connection, five test rides, then the production connection for real rides.',
              fr:
                  'Fluxidi enregistre automatiquement vos courses auprès de Chiron. La connexion se fait en trois étapes simples : connexion test, cinq courses de test, puis la connexion production pour vos courses réelles.',
              es:
                  'Fluxidi registra automáticamente sus viajes en Chiron. La conexión tiene tres pasos sencillos: conexión de prueba, cinco viajes de prueba y, por último, la conexión de producción para sus viajes reales.',
              de:
                  'Fluxidi meldet Ihre Fahrten automatisch bei Chiron. Die Einrichtung erfolgt in drei einfachen Schritten: Testverbindung, fünf Testfahrten und danach die Produktionsverbindung für echte Fahrten.',
            ),
            style: TextStyle(
              color: textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _stepRow(
              index: i + 1,
              title: steps[i].title,
              state: steps[i].state,
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _portalButton(
                context,
                label: _t(
                  nl: 'Open Chiron-testportaal',
                  en: 'Open Chiron test portal',
                  fr: 'Ouvrir le portail test Chiron',
                  es: 'Abrir portal de prueba Chiron',
                  de: 'Chiron-Testportal öffnen',
                ),
                url: kChironTestPortalUrl,
                onPressed: onOpenTestPortal,
              ),
              if (_step2 == ChironWizardStepState.succeeded)
                _portalButton(
                  context,
                  label: _t(
                    nl: 'Open Chiron-productieportaal',
                    en: 'Open Chiron production portal',
                    fr: 'Ouvrir le portail production Chiron',
                    es: 'Abrir portal de producción Chiron',
                    de: 'Chiron-Produktionsportal öffnen',
                  ),
                  url: kChironProductionPortalUrl,
                  onPressed: onOpenProductionPortal,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepRow({
    required int index,
    required String title,
    required ChironWizardStepState state,
  }) {
    final color = _stateColor(state);
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withOpacity(0.16),
            shape: BoxShape.circle,
            border: Border.all(color: color.withOpacity(0.5)),
          ),
          child: Text(
            '$index',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.14),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            _stateLabel(state),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }

  Widget _portalButton(
    BuildContext context, {
    required String label,
    required String url,
    VoidCallback? onPressed,
  }) {
    return SizedBox(
      height: 44,
      child: OutlinedButton.icon(
        key: ValueKey('chiron_portal_$url'),
        onPressed: onPressed ?? () => _openUrl(url, context),
        icon: const Icon(Icons.open_in_new, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: BorderSide(color: borderColor),
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
      ),
    );
  }
}

/// Honest high-level setup status for Business Settings / hub chips.
String chironHonestSetupStatusLabel({
  required BackendChironConnectionStatus? status,
  required AppLanguage language,
  required bool enabled,
}) {
  String t({
    required String nl,
    required String en,
    required String fr,
    required String es,
    String? de,
  }) {
    switch (language) {
      case AppLanguage.nl:
        return nl;
      case AppLanguage.en:
        return en;
      case AppLanguage.fr:
        return fr;
      case AppLanguage.es:
        return es;
      case AppLanguage.de:
        return de ?? en;
    }
  }

  if (!enabled) {
    return t(
      nl: 'Niet ingesteld',
      en: 'Not set up',
      fr: 'Non configuré',
      es: 'No configurado',
      de: 'Nicht eingerichtet',
    );
  }
  final s = status;
  if (s == null || !s.testCredentialsStored) {
    return t(
      nl: 'Test instellen',
      en: 'Set up test',
      fr: 'Configurer le test',
      es: 'Configurar prueba',
      de: 'Test einrichten',
    );
  }
  if (s.lastConnectionStatus != ChironConnectionStatus.testPassed) {
    return t(
      nl: 'Test instellen',
      en: 'Set up test',
      fr: 'Configurer le test',
      es: 'Configurar prueba',
      de: 'Test einrichten',
    );
  }
  if (s.testflowStatus.trim().toLowerCase() != 'complete') {
    return t(
      nl: 'Acceptatietest bezig',
      en: 'Acceptance test in progress',
      fr: 'Test d’acceptation en cours',
      es: 'Prueba de aceptación en curso',
      de: 'Akzeptanztest läuft',
    );
  }
  if (s.productionSubmitActive) {
    return t(
      nl: 'Productie actief',
      en: 'Production active',
      fr: 'Production active',
      es: 'Producción activa',
      de: 'Produktion aktiv',
    );
  }
  if (s.productionLastConnectionStatus == ChironConnectionStatus.testFailed) {
    return t(
      nl: 'Aandacht vereist',
      en: 'Attention required',
      fr: 'Attention requise',
      es: 'Atención requerida',
      de: 'Aufmerksamkeit erforderlich',
    );
  }
  return t(
    nl: 'Productie instellen',
    en: 'Set up production',
    fr: 'Configurer la production',
    es: 'Configurar producción',
    de: 'Produktion einrichten',
  );
}

String chironHonestNextStepLabel({
  required BackendChironConnectionStatus? status,
  required AppLanguage language,
  required bool enabled,
}) {
  String t({
    required String nl,
    required String en,
    required String fr,
    required String es,
    String? de,
  }) {
    switch (language) {
      case AppLanguage.nl:
        return nl;
      case AppLanguage.en:
        return en;
      case AppLanguage.fr:
        return fr;
      case AppLanguage.es:
        return es;
      case AppLanguage.de:
        return de ?? en;
    }
  }

  if (!enabled) {
    return t(
      nl: 'Schakel Chiron in en open daarna de testomgeving.',
      en: 'Enable Chiron, then open the test environment.',
      fr: 'Activez Chiron, puis ouvrez l’environnement de test.',
      es: 'Active Chiron y abra el entorno de prueba.',
      de: 'Aktivieren Sie Chiron und öffnen Sie danach die Testumgebung.',
    );
  }
  final s = status;
  if (s == null || !s.testCredentialsStored) {
    return t(
      nl: 'Open het Chiron-testportaal, voer Test Client ID en Secret in en sla op.',
      en: 'Open the Chiron test portal, enter Test Client ID and Secret, then save.',
      fr: 'Ouvrez le portail test Chiron, saisissez Client ID et Secret test, puis enregistrez.',
      es: 'Abra el portal de prueba Chiron, introduzca Client ID y Secret de prueba y guarde.',
      de: 'Öffnen Sie das Chiron-Testportal, geben Sie Test-Client-ID und Secret ein und speichern Sie.',
    );
  }
  if (s.lastConnectionStatus != ChironConnectionStatus.testPassed) {
    return t(
      nl: 'Controleer de testverbinding.',
      en: 'Check the test connection.',
      fr: 'Vérifiez la connexion test.',
      es: 'Compruebe la conexión de prueba.',
      de: 'Prüfen Sie die Testverbindung.',
    );
  }
  if (s.testflowStatus.trim().toLowerCase() != 'complete') {
    return t(
      nl: 'Rijd vijf volledige testritten. Fluxidi verstuurt START en STOP automatisch.',
      en: 'Drive five complete test rides. Fluxidi sends START and STOP automatically.',
      fr: 'Effectuez cinq courses de test complètes. Fluxidi envoie START et STOP automatiquement.',
      es: 'Realice cinco viajes de prueba completos. Fluxidi envía START y STOP automáticamente.',
      de: 'Fahren Sie fünf vollständige Testfahrten. Fluxidi sendet START und STOP automatisch.',
    );
  }
  if (!s.productionCredentialsStored) {
    return t(
      nl: 'Open het Chiron-productieportaal en voer uw aparte productiegegevens in.',
      en: 'Open the Chiron production portal and enter your separate production credentials.',
      fr: 'Ouvrez le portail production Chiron et saisissez vos identifiants production distincts.',
      es: 'Abra el portal de producción Chiron e introduzca sus credenciales de producción separadas.',
      de: 'Öffnen Sie das Chiron-Produktionsportal und geben Sie Ihre separaten Produktionsdaten ein.',
    );
  }
  if (s.productionLastConnectionStatus != ChironConnectionStatus.testPassed) {
    return t(
      nl: 'Controleer eerst de productieverbinding.',
      en: 'Check the production connection first.',
      fr: 'Vérifiez d’abord la connexion production.',
      es: 'Compruebe primero la conexión de producción.',
      de: 'Prüfen Sie zuerst die Produktionsverbindung.',
    );
  }
  if (!s.productionSubmitActive) {
    return t(
      nl: 'Activeer productie expliciet wanneer u klaar bent.',
      en: 'Activate production explicitly when you are ready.',
      fr: 'Activez explicitement la production lorsque vous êtes prêt.',
      es: 'Active la producción explícitamente cuando esté listo.',
      de: 'Aktivieren Sie die Produktion ausdrücklich, wenn Sie bereit sind.',
    );
  }
  return t(
    nl: 'Chiron-productie is actief. Nieuwe ritten gaan automatisch naar productie.',
    en: 'Chiron production is active. New rides go to production automatically.',
    fr: 'La production Chiron est active. Les nouvelles courses partent automatiquement en production.',
    es: 'La producción Chiron está activa. Los nuevos viajes van automáticamente a producción.',
    de: 'Chiron-Produktion ist aktiv. Neue Fahrten gehen automatisch in die Produktion.',
  );
}
