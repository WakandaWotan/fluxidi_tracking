// RELEASE-P0-CHIRON-SELF-SERVICE-2026-07-31
// Friendly diagnose bottom sheet opened on a single Diagnose tap.

import 'package:flutter/material.dart';

import '../app_config.dart';
import '../app_strings.dart';
import '../chiron_company_connection_config.dart';
import 'chiron_self_service_wizard.dart';

Future<void> showChironFriendlyDiagnoseSheet({
  required BuildContext context,
  required AppLanguage language,
  required BackendChironConnectionStatus? status,
  required Color panelColor,
  required Color cardColor,
  required Color borderColor,
  required Color textPrimary,
  required Color textSecondary,
  required VoidCallback onOpenAdvanced,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: panelColor,
    builder: (_) => ChironFriendlyDiagnoseSheet(
      language: language,
      status: status,
      panelColor: panelColor,
      cardColor: cardColor,
      borderColor: borderColor,
      textPrimary: textPrimary,
      textSecondary: textSecondary,
      onOpenAdvanced: onOpenAdvanced,
    ),
  );
}

class ChironFriendlyDiagnoseSheet extends StatelessWidget {
  const ChironFriendlyDiagnoseSheet({
    super.key,
    required this.language,
    required this.status,
    required this.panelColor,
    required this.cardColor,
    required this.borderColor,
    required this.textPrimary,
    required this.textSecondary,
    required this.onOpenAdvanced,
  });

  final AppLanguage language;
  final BackendChironConnectionStatus? status;
  final Color panelColor;
  final Color cardColor;
  final Color borderColor;
  final Color textPrimary;
  final Color textSecondary;
  final VoidCallback onOpenAdvanced;

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

  String _yesNo(bool v) => v
      ? _t(nl: 'ja', en: 'yes', fr: 'oui', es: 'sí', de: 'ja')
      : _t(nl: 'nee', en: 'no', fr: 'non', es: 'no', de: 'nein');

  String _connLabel(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'test_passed':
        return _t(
          nl: 'geslaagd',
          en: 'passed',
          fr: 'réussi',
          es: 'correcto',
          de: 'erfolgreich',
        );
      case 'test_failed':
        return _t(
          nl: 'fout',
          en: 'error',
          fr: 'erreur',
          es: 'error',
          de: 'Fehler',
        );
      default:
        return _t(
          nl: 'niet getest',
          en: 'not tested',
          fr: 'non testé',
          es: 'no probado',
          de: 'nicht getestet',
        );
    }
  }

  String _actionHint() {
    final s = status;
    if (s == null || !s.testCredentialsStored) {
      return _t(
        nl: 'Test Client Secret ontbreekt — voer uw testgegevens opnieuw in.',
        en: 'Test Client Secret is missing — enter your test credentials again.',
        fr: 'Le Client Secret test manque — saisissez à nouveau vos identifiants test.',
        es: 'Falta el Client Secret de prueba — vuelva a introducir sus credenciales.',
        de: 'Test-Client-Secret fehlt — geben Sie Ihre Testdaten erneut ein.',
      );
    }
    if (s.lastConnectionStatus != 'test_passed') {
      return _t(
        nl: 'Controleer eerst de testverbinding.',
        en: 'Check the test connection first.',
        fr: 'Vérifiez d’abord la connexion test.',
        es: 'Compruebe primero la conexión de prueba.',
        de: 'Prüfen Sie zuerst die Testverbindung.',
      );
    }
    if (s.testflowStatus.trim().toLowerCase() == 'complete' &&
        !s.productionCredentialsStored) {
      return _t(
        nl: 'De acceptatietest is geslaagd — open nu het Chiron-productieportaal.',
        en: 'Acceptance test passed — open the Chiron production portal now.',
        fr: 'Le test d’acceptation est réussi — ouvrez maintenant le portail production Chiron.',
        es: 'La prueba de aceptación se superó — abra ahora el portal de producción Chiron.',
        de: 'Akzeptanztest bestanden — öffnen Sie jetzt das Chiron-Produktionsportal.',
      );
    }
    if (s.productionCredentialsStored &&
        s.productionLastConnectionStatus != 'test_passed') {
      return _t(
        nl: 'Productiegegevens zijn opgeslagen maar nog niet getest — controleer de productieverbinding.',
        en: 'Production credentials are stored but not tested — check the production connection.',
        fr: 'Les identifiants production sont enregistrés mais pas encore testés — vérifiez la connexion production.',
        es: 'Las credenciales de producción están guardadas pero aún no probadas — compruebe la conexión.',
        de: 'Produktionsdaten sind gespeichert, aber noch nicht getestet — prüfen Sie die Produktionsverbindung.',
      );
    }
    if (s.productionEnabled && !s.productionSubmitActive) {
      return _t(
        nl: 'Automatische productie-inzending is onderbroken — controleer de productieverbinding.',
        en: 'Automatic production submission is interrupted — check the production connection.',
        fr: 'L’envoi production automatique est interrompu — vérifiez la connexion production.',
        es: 'El envío automático de producción está interrumpido — compruebe la conexión.',
        de: 'Automatische Produktionsübermittlung ist unterbrochen — prüfen Sie die Produktionsverbindung.',
      );
    }
    return chironHonestNextStepLabel(
      status: s,
      language: language,
      enabled: s.enabled,
    );
  }

  Widget _line(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label, style: TextStyle(color: textSecondary, fontSize: 13)),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                color: textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = status;
    final env =
        s?.effectiveChironEnvironment == ChironConnectionEnvironment.production
            ? _t(
                nl: 'Productie',
                en: 'Production',
                fr: 'Production',
                es: 'Producción',
                de: 'Produktion',
              )
            : 'Test/ACC';
    final active =
        _t(nl: 'actief', en: 'active', fr: 'actif', es: 'activo', de: 'aktiv');
    final inactive = _t(
      nl: 'inactief',
      en: 'inactive',
      fr: 'inactif',
      es: 'inactivo',
      de: 'inaktiv',
    );

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _t(
                  nl: 'Diagnose',
                  en: 'Diagnose',
                  fr: 'Diagnostic',
                  es: 'Diagnóstico',
                  de: 'Diagnose',
                ),
                style: TextStyle(
                  color: textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 12),
              _line(
                _t(
                  nl: 'Testgegevens opgeslagen',
                  en: 'Test credentials stored',
                  fr: 'Identifiants test enregistrés',
                  es: 'Credenciales de prueba guardadas',
                  de: 'Testdaten gespeichert',
                ),
                _yesNo(s?.testCredentialsStored == true),
              ),
              _line(
                _t(
                  nl: 'Testverbinding',
                  en: 'Test connection',
                  fr: 'Connexion test',
                  es: 'Conexión de prueba',
                  de: 'Testverbindung',
                ),
                _connLabel(s?.lastConnectionStatus ?? ''),
              ),
              _line(
                _t(
                  nl: 'Acceptatietest',
                  en: 'Acceptance test',
                  fr: 'Test d’acceptation',
                  es: 'Prueba de aceptación',
                  de: 'Akzeptanztest',
                ),
                '${s?.testMessagesSentCount ?? 0}/${s?.testMessagesRequired ?? 10}',
              ),
              _line(
                _t(
                  nl: 'Productiegegevens opgeslagen',
                  en: 'Production credentials stored',
                  fr: 'Identifiants production enregistrés',
                  es: 'Credenciales de producción guardadas',
                  de: 'Produktionsdaten gespeichert',
                ),
                _yesNo(s?.productionCredentialsStored == true),
              ),
              _line(
                _t(
                  nl: 'Productieverbinding',
                  en: 'Production connection',
                  fr: 'Connexion production',
                  es: 'Conexión de producción',
                  de: 'Produktionsverbindung',
                ),
                _connLabel(s?.productionLastConnectionStatus ?? ''),
              ),
              _line(
                _t(
                  nl: 'Huidige Chiron-omgeving',
                  en: 'Current Chiron environment',
                  fr: 'Environnement Chiron actuel',
                  es: 'Entorno Chiron actual',
                  de: 'Aktuelle Chiron-Umgebung',
                ),
                env,
              ),
              _line(
                _t(
                  nl: 'ACC-testinzending',
                  en: 'ACC test submission',
                  fr: 'Envoi test ACC',
                  es: 'Envío test ACC',
                  de: 'ACC-Testübermittlung',
                ),
                s?.accTestSubmitActive == true ? active : inactive,
              ),
              _line(
                _t(
                  nl: 'Productie-inzending',
                  en: 'Production submission',
                  fr: 'Envoi production',
                  es: 'Envío producción',
                  de: 'Produktionsübermittlung',
                ),
                s?.productionSubmitActive == true ? active : inactive,
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: borderColor),
                ),
                child: Text(
                  _actionHint(),
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.of(context).maybePop();
                    onOpenAdvanced();
                  },
                  child: Text(
                    _t(
                      nl: 'Geavanceerde ritcontrole',
                      en: 'Advanced ride check',
                      fr: 'Contrôle avancé des courses',
                      es: 'Comprobación avanzada de viajes',
                      de: 'Erweiterte Fahrtprüfung',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: Text(
                    _t(
                      nl: 'Sluiten',
                      en: 'Close',
                      fr: 'Fermer',
                      es: 'Cerrar',
                      de: 'Schließen',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
