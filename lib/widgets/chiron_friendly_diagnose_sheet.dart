// RELEASE-P0-CHIRON-SELF-SERVICE-2026-07-31
// Friendly diagnose bottom sheet: opens on first tap, then refreshes status.

import 'package:flutter/material.dart';

import '../app_config.dart';
import '../app_strings.dart';
import '../chiron_company_connection_config.dart';
import '../company_session_store.dart';
import 'chiron_self_service_wizard.dart';

/// Opens the diagnose panel immediately. Network refresh happens inside the
/// sheet so the first tap always shows visual feedback.
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
  Future<BackendChironConnectionStatus> Function()? refreshStatus,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: panelColor,
    builder: (_) => ChironFriendlyDiagnoseSheet(
      language: language,
      initialStatus: status,
      panelColor: panelColor,
      cardColor: cardColor,
      borderColor: borderColor,
      textPrimary: textPrimary,
      textSecondary: textSecondary,
      onOpenAdvanced: onOpenAdvanced,
      refreshStatus: refreshStatus ?? _defaultDiagnoseRefresh,
    ),
  );
}

Future<BackendChironConnectionStatus> _defaultDiagnoseRefresh() async {
  final companyId = companyProfileNotifier.value?.companyId.trim().isNotEmpty ==
          true
      ? companyProfileNotifier.value!.companyId.trim()
      : (activeCompanySessionNotifier.value?.companyId.trim() ?? '');
  if (companyId.isEmpty) {
    throw BackendChironConnectionApiException(
      error: 'missing_scope',
      statusCode: 400,
    );
  }
  return fetchBackendChironConnectionStatus(
    tenantId: companyId,
    companyId: companyId,
  );
}

class ChironFriendlyDiagnoseSheet extends StatefulWidget {
  const ChironFriendlyDiagnoseSheet({
    super.key,
    required this.language,
    required this.initialStatus,
    required this.panelColor,
    required this.cardColor,
    required this.borderColor,
    required this.textPrimary,
    required this.textSecondary,
    required this.onOpenAdvanced,
    this.refreshStatus,
  });

  final AppLanguage language;
  final BackendChironConnectionStatus? initialStatus;
  final Color panelColor;
  final Color cardColor;
  final Color borderColor;
  final Color textPrimary;
  final Color textSecondary;
  final VoidCallback onOpenAdvanced;
  final Future<BackendChironConnectionStatus> Function()? refreshStatus;

  @override
  State<ChironFriendlyDiagnoseSheet> createState() =>
      _ChironFriendlyDiagnoseSheetState();
}

class _ChironFriendlyDiagnoseSheetState
    extends State<ChironFriendlyDiagnoseSheet> {
  late BackendChironConnectionStatus? _status;
  bool _loading = false;
  String? _error;
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _status = widget.initialStatus;
    // Panel is already visible; refresh after the first frame so the first
    // tap never waits on the network before feedback appears.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshOnce();
    });
  }

  Future<void> _refreshOnce() async {
    final refresh = widget.refreshStatus;
    if (refresh == null || _loading) return;
    final gen = ++_requestGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final next = await refresh();
      if (!mounted || gen != _requestGeneration) return;
      setState(() {
        _status = next;
        backendChironConnectionStatusNotifier.value = next;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || gen != _requestGeneration) return;
      final msg = e is BackendChironConnectionApiException
          ? e.error
          : 'network_error';
      setState(() {
        _loading = false;
        _error = _sanitize(msg);
      });
    }
  }

  String _sanitize(String raw) {
    return raw
        .replaceAll(
          RegExp(r'(secret|token|bearer)[^\s]*', caseSensitive: false),
          '***',
        )
        .trim();
  }

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
    String? de,
  }) {
    switch (widget.language) {
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
    final s = _status;
    if (s == null || !s.testCredentialsStored) {
      return _t(
        nl: 'Test Client Secret ontbreekt — voer uw testgegevens opnieuw in.',
        en: 'Test Client Secret is missing — enter your test credentials again.',
        fr: 'Le Client Secret de test manque — saisissez à nouveau vos identifiants de test.',
        es: 'Falta el Client Secret de prueba: vuelva a introducir sus credenciales de prueba.',
        de: 'Test-Client-Secret fehlt — geben Sie Ihre Testdaten erneut ein.',
      );
    }
    if (s.lastConnectionStatus != ChironConnectionStatus.testPassed) {
      return _t(
        nl: 'Testverbinding nog niet geslaagd — controleer de testverbinding.',
        en: 'Test connection not passed yet — check the test connection.',
        fr: 'Connexion test non réussie — vérifiez la connexion test.',
        es: 'La conexión de prueba aún no se superó: compruebe la conexión de prueba.',
        de: 'Testverbindung noch nicht erfolgreich — prüfen Sie die Testverbindung.',
      );
    }
    if (s.testflowStatus != 'complete') {
      return _t(
        nl: 'Rijd vijf volledige testritten. Fluxidi stuurt START/STOP automatisch naar ACC.',
        en: 'Drive five complete test rides. Fluxidi sends START/STOP to ACC automatically.',
        fr: 'Effectuez cinq courses de test complètes. Fluxidi envoie START/STOP automatiquement vers ACC.',
        es: 'Realice cinco viajes de prueba completos. Fluxidi envía START/STOP automáticamente a ACC.',
        de: 'Fahren Sie fünf vollständige Testfahrten. Fluxidi sendet START/STOP automatisch an ACC.',
      );
    }
    if (!s.productionCredentialsStored) {
      return _t(
        nl: 'De acceptatietest is geslaagd — open nu het Chiron-productieportaal.',
        en: 'Acceptance test passed — open the Chiron production portal now.',
        fr: 'Le test d’acceptation est réussi — ouvrez maintenant le portail production Chiron.',
        es: 'La prueba de aceptación se superó: abra ahora el portal de producción Chiron.',
        de: 'Akzeptanztest erfolgreich — öffnen Sie jetzt das Chiron-Produktionsportal.',
      );
    }
    if (s.productionLastConnectionStatus != ChironConnectionStatus.testPassed) {
      return _t(
        nl: 'Productiegegevens zijn opgeslagen maar nog niet getest — controleer de productieverbinding.',
        en: 'Production credentials are saved but not tested yet — check the production connection.',
        fr: 'Identifiants production enregistrés mais non testés — vérifiez la connexion production.',
        es: 'Credenciales de producción guardadas pero no probadas: compruebe la conexión de producción.',
        de: 'Produktionsdaten gespeichert, aber noch nicht getestet — prüfen Sie die Produktionsverbindung.',
      );
    }
    if (s.productionEnabled && !s.productionSubmitActive) {
      return _t(
        nl: 'Automatische productie-inzending is onderbroken — controleer de productieverbinding.',
        en: 'Automatic production submission is interrupted — check the production connection.',
        fr: 'L’envoi production automatique est interrompu — vérifiez la connexion production.',
        es: 'El envío automático de producción está interrumpido: compruebe la conexión de producción.',
        de: 'Automatische Produktionsübermittlung unterbrochen — prüfen Sie die Produktionsverbindung.',
      );
    }
    if (!s.productionSubmitActive) {
      return _t(
        nl: 'Activeer productie expliciet wanneer u klaar bent.',
        en: 'Activate production explicitly when you are ready.',
        fr: 'Activez explicitement la production lorsque vous êtes prêt.',
        es: 'Active la producción explícitamente cuando esté listo.',
        de: 'Aktivieren Sie die Produktion ausdrücklich, wenn Sie bereit sind.',
      );
    }
    return _t(
      nl: 'Chiron-productie is actief. Nieuwe ritten gaan naar productie.',
      en: 'Chiron production is active. New rides go to production.',
      fr: 'La production Chiron est active. Les nouvelles courses vont en production.',
      es: 'La producción Chiron está activa. Los nuevos viajes van a producción.',
      de: 'Chiron-Produktion ist aktiv. Neue Fahrten gehen in die Produktion.',
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: widget.textSecondary, fontSize: 13),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                color: widget.textPrimary,
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
    final s = _status;
    final envLabel = s?.effectiveChironEnvironment ==
            ChironConnectionEnvironment.production
        ? _t(
            nl: 'Productie',
            en: 'Production',
            fr: 'Production',
            es: 'Producción',
            de: 'Produktion',
          )
        : _t(
            nl: 'Test/ACC',
            en: 'Test/ACC',
            fr: 'Test/ACC',
            es: 'Test/ACC',
            de: 'Test/ACC',
          );
    final active = _t(
      nl: 'actief',
      en: 'active',
      fr: 'actif',
      es: 'activo',
      de: 'aktiv',
    );
    final inactive = _t(
      nl: 'inactief',
      en: 'inactive',
      fr: 'inactif',
      es: 'inactivo',
      de: 'inaktiv',
    );
    final dep = s?.testDepartureSentCount ?? 0;
    final arr = s?.testArrivalSentCount ?? 0;
    final rides = s?.testRidesCompletedCount ?? 0;
    final msgs = s?.testMessagesSentCount ?? 0;

    return SafeArea(
      key: const ValueKey('chiron_friendly_diagnose_sheet'),
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
                  color: widget.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 8),
              if (_loading) ...[
                Row(
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _t(
                          nl: 'Diagnose wordt uitgevoerd…',
                          en: 'Running diagnostics…',
                          fr: 'Diagnostic en cours…',
                          es: 'Ejecutando diagnóstico…',
                          de: 'Diagnose wird ausgeführt…',
                        ),
                        style: TextStyle(
                          color: widget.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              if (_error != null) ...[
                Container(
                  key: const ValueKey('chiron_diagnose_error'),
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFB42318).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_t(
                      nl: 'Diagnose kon status niet vernieuwen. De laatst bekende status blijft zichtbaar.',
                      en: 'Diagnose could not refresh status. The last known status stays visible.',
                      fr: 'Le diagnostic n’a pas pu actualiser le statut. Le dernier statut connu reste visible.',
                      es: 'El diagnóstico no pudo actualizar el estado. Se mantiene el último estado conocido.',
                      de: 'Diagnose konnte den Status nicht aktualisieren. Der zuletzt bekannte Status bleibt sichtbar.',
                    )} (${_error!})',
                    style: TextStyle(
                      color: const Color(0xFFB42318),
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: widget.cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: widget.borderColor),
                ),
                child: Column(
                  children: [
                    _row(
                      _t(
                        nl: 'Testgegevens opgeslagen',
                        en: 'Test credentials stored',
                        fr: 'Identifiants de test enregistrés',
                        es: 'Credenciales de prueba guardadas',
                        de: 'Testdaten gespeichert',
                      ),
                      _yesNo(s?.testCredentialsStored == true),
                    ),
                    _row(
                      _t(
                        nl: 'Testverbinding',
                        en: 'Test connection',
                        fr: 'Connexion test',
                        es: 'Conexión de prueba',
                        de: 'Testverbindung',
                      ),
                      _connLabel(s?.lastConnectionStatus ?? ''),
                    ),
                    _row(
                      _t(
                        nl: 'Acceptatietest',
                        en: 'Acceptance test',
                        fr: 'Test d’acceptation',
                        es: 'Prueba de aceptación',
                        de: 'Akzeptanztest',
                      ),
                      '$rides/5 ${_t(nl: 'ritten', en: 'rides', fr: 'courses', es: 'viajes', de: 'Fahrten')} · $msgs/10 ${_t(nl: 'berichten', en: 'messages', fr: 'messages', es: 'mensajes', de: 'Nachrichten')} ($dep/5+$arr/5)',
                    ),
                    _row(
                      _t(
                        nl: 'Productiegegevens opgeslagen',
                        en: 'Production credentials stored',
                        fr: 'Identifiants production enregistrés',
                        es: 'Credenciales de producción guardadas',
                        de: 'Produktionsdaten gespeichert',
                      ),
                      _yesNo(s?.productionCredentialsStored == true),
                    ),
                    _row(
                      _t(
                        nl: 'Productieverbinding',
                        en: 'Production connection',
                        fr: 'Connexion production',
                        es: 'Conexión de producción',
                        de: 'Produktionsverbindung',
                      ),
                      _connLabel(s?.productionLastConnectionStatus ?? ''),
                    ),
                    _row(
                      _t(
                        nl: 'Huidige Chiron-omgeving',
                        en: 'Current Chiron environment',
                        fr: 'Environnement Chiron actuel',
                        es: 'Entorno Chiron actual',
                        de: 'Aktuelle Chiron-Umgebung',
                      ),
                      envLabel,
                    ),
                    _row(
                      _t(
                        nl: 'ACC-testinzending',
                        en: 'ACC test submission',
                        fr: 'Envoi test ACC',
                        es: 'Envío de prueba ACC',
                        de: 'ACC-Testübermittlung',
                      ),
                      s?.accTestSubmitActive == true ? active : inactive,
                    ),
                    _row(
                      _t(
                        nl: 'Productie-inzending',
                        en: 'Production submission',
                        fr: 'Envoi production',
                        es: 'Envío de producción',
                        de: 'Produktionsübermittlung',
                      ),
                      s?.productionSubmitActive == true ? active : inactive,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _t(
                  nl: 'Wat nu doen',
                  en: 'What to do next',
                  fr: 'Que faire maintenant',
                  es: 'Qué hacer ahora',
                  de: 'Nächster Schritt',
                ),
                style: TextStyle(
                  color: widget.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _actionHint(),
                style: TextStyle(
                  color: widget.textSecondary,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.of(context).maybePop();
                    widget.onOpenAdvanced();
                  },
                  child: Text(
                    _t(
                      nl: 'Technische details',
                      en: 'Technical details',
                      fr: 'Détails techniques',
                      es: 'Detalles técnicos',
                      de: 'Technische Details',
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
