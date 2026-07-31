// RELEASE-P0-CHIRON-SELF-SERVICE-2026-07-31
// Step 1 — Chiron test environment credentials for self-service onboarding.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_config.dart';
import '../app_strings.dart';
import '../chiron_company_connection_config.dart';
import 'chiron_self_service_wizard.dart';

typedef ChironTestSave = Future<void> Function(String clientId, String clientSecret);
typedef ChironTestAction = Future<void> Function();

class ChironTestSetupCard extends StatefulWidget {
  const ChironTestSetupCard({
    super.key,
    required this.status,
    required this.language,
    required this.onSave,
    required this.onTestConnection,
    required this.onClear,
    this.backgroundColor,
    this.textColor,
    this.mutedColor,
  });

  final BackendChironConnectionStatus? status;
  final AppLanguage language;
  final ChironTestSave onSave;
  final ChironTestAction onTestConnection;
  final ChironTestAction onClear;
  final Color? backgroundColor;
  final Color? textColor;
  final Color? mutedColor;

  @override
  State<ChironTestSetupCard> createState() => _ChironTestSetupCardState();
}

class _ChironTestSetupCardState extends State<ChironTestSetupCard> {
  final _clientIdCtrl = TextEditingController();
  final _clientSecretCtrl = TextEditingController();
  bool _busy = false;
  bool _replacing = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _clientIdCtrl.dispose();
    _clientSecretCtrl.dispose();
    super.dispose();
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

  bool get _stored => widget.status?.testCredentialsStored == true;
  bool get _showFields => !_stored || _replacing;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    try {
      await action();
      if (!mounted) return;
      setState(() {
        _success = _t(
          nl: 'Opgeslagen. Status wordt vernieuwd.',
          en: 'Saved. Status is refreshing.',
          fr: 'Enregistré. Statut en cours d’actualisation.',
          es: 'Guardado. El estado se está actualizando.',
          de: 'Gespeichert. Status wird aktualisiert.',
        );
        _clientSecretCtrl.clear();
        _replacing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll(
          RegExp(r'(secret|token|bearer)[^\s]*', caseSensitive: false),
          '***',
        );
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = widget.backgroundColor ?? theme.colorScheme.surface;
    final text = widget.textColor ?? theme.colorScheme.onSurface;
    final muted = widget.mutedColor ?? theme.colorScheme.onSurfaceVariant;
    final passed =
        widget.status?.lastConnectionStatus == ChironConnectionStatus.testPassed;
    final failed =
        widget.status?.lastConnectionStatus == ChironConnectionStatus.testFailed;

    return Container(
      key: const ValueKey('chiron_test_setup_card'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: muted.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t(
              nl: '1. Chiron-testomgeving',
              en: '1. Chiron test environment',
              fr: '1. Environnement Chiron test',
              es: '1. Entorno Chiron de prueba',
              de: '1. Chiron-Testumgebung',
            ),
            style: TextStyle(
              color: text,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _t(
              nl: 'Haal uw testgegevens op via het officiële Chiron-testportaal. Voer ze hieronder in en controleer daarna de verbinding.',
              en: 'Get your test credentials from the official Chiron test portal. Enter them below and then check the connection.',
              fr: 'Récupérez vos identifiants de test via le portail test Chiron officiel. Saisissez-les ci-dessous puis vérifiez la connexion.',
              es: 'Obtenga sus credenciales de prueba en el portal oficial de prueba Chiron. Introdúzcalas abajo y compruebe la conexión.',
              de: 'Holen Sie Ihre Testdaten über das offizielle Chiron-Testportal. Geben Sie sie unten ein und prüfen Sie danach die Verbindung.',
            ),
            style: TextStyle(color: muted, fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 44,
            child: OutlinedButton.icon(
              key: const ValueKey('chiron_open_test_portal'),
              onPressed: () async {
                final uri = Uri.parse(kChironTestPortalUrl);
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text(
                _t(
                  nl: 'Open Chiron-testportaal',
                  en: 'Open Chiron test portal',
                  fr: 'Ouvrir le portail test Chiron',
                  es: 'Abrir portal de prueba Chiron',
                  de: 'Chiron-Testportal öffnen',
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_showFields) ...[
            TextField(
              controller: _clientIdCtrl,
              enabled: !_busy,
              decoration: InputDecoration(
                labelText: _t(
                  nl: 'Test Client ID',
                  en: 'Test Client ID',
                  fr: 'Client ID de test',
                  es: 'Client ID de prueba',
                  de: 'Test-Client-ID',
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _clientSecretCtrl,
              enabled: !_busy,
              obscureText: true,
              decoration: InputDecoration(
                labelText: _t(
                  nl: 'Test Client Secret',
                  en: 'Test Client Secret',
                  fr: 'Client Secret de test',
                  es: 'Client Secret de prueba',
                  de: 'Test-Client-Secret',
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 44,
              child: FilledButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                          () => widget.onSave(
                            _clientIdCtrl.text.trim(),
                            _clientSecretCtrl.text,
                          ),
                        ),
                child: Text(
                  _t(
                    nl: 'Testgegevens opslaan',
                    en: 'Save test credentials',
                    fr: 'Enregistrer les identifiants de test',
                    es: 'Guardar credenciales de prueba',
                    de: 'Testdaten speichern',
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SizedBox(
                height: 44,
                child: OutlinedButton(
                  onPressed: !_stored || _busy
                      ? null
                      : () => _run(widget.onTestConnection),
                  child: Text(
                    _t(
                      nl: 'Testverbinding controleren',
                      en: 'Check test connection',
                      fr: 'Vérifier la connexion test',
                      es: 'Comprobar conexión de prueba',
                      de: 'Testverbindung prüfen',
                    ),
                  ),
                ),
              ),
              if (_stored)
                SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _replacing = true;
                              _clientIdCtrl.clear();
                              _clientSecretCtrl.clear();
                            }),
                    child: Text(
                      _t(
                        nl: 'Testgegevens vervangen',
                        en: 'Replace test credentials',
                        fr: 'Remplacer les identifiants de test',
                        es: 'Reemplazar credenciales de prueba',
                        de: 'Testdaten ersetzen',
                      ),
                    ),
                  ),
                ),
              if (_stored)
                SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => _run(widget.onClear),
                    child: Text(
                      _t(
                        nl: 'Testgegevens verwijderen',
                        en: 'Remove test credentials',
                        fr: 'Supprimer les identifiants de test',
                        es: 'Eliminar credenciales de prueba',
                        de: 'Testdaten entfernen',
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${_t(nl: 'Testgegevens opgeslagen', en: 'Test credentials stored', fr: 'Identifiants de test enregistrés', es: 'Credenciales de prueba guardadas', de: 'Testdaten gespeichert')}: ${_stored ? _t(nl: 'ja', en: 'yes', fr: 'oui', es: 'sí', de: 'ja') : _t(nl: 'nee', en: 'no', fr: 'non', es: 'no', de: 'nein')}',
            style: TextStyle(color: muted, fontSize: 12),
          ),
          Text(
            '${_t(nl: 'Testverbinding', en: 'Test connection', fr: 'Connexion test', es: 'Conexión de prueba', de: 'Testverbindung')}: ${passed ? _t(nl: 'geslaagd', en: 'passed', fr: 'réussi', es: 'correcto', de: 'erfolgreich') : failed ? _t(nl: 'fout', en: 'error', fr: 'erreur', es: 'error', de: 'Fehler') : _t(nl: 'niet getest', en: 'not tested', fr: 'non testé', es: 'no probado', de: 'nicht getestet')}',
            style: TextStyle(color: muted, fontSize: 12),
          ),
          Text(
            '${_t(nl: 'ACC-testinzending', en: 'ACC test submission', fr: 'Envoi test ACC', es: 'Envío de prueba ACC', de: 'ACC-Testübermittlung')}: ${widget.status?.accTestSubmitActive == true ? _t(nl: 'actief', en: 'active', fr: 'actif', es: 'activo', de: 'aktiv') : _t(nl: 'inactief', en: 'inactive', fr: 'inactif', es: 'inactivo', de: 'inaktiv')}',
            style: TextStyle(color: muted, fontSize: 12),
          ),
          if (_stored && passed) ...[
            const SizedBox(height: 8),
            Text(
              _t(
                nl: 'Fluxidi verstuurt uw ritten automatisch naar de Chiron-testomgeving.',
                en: 'Fluxidi automatically sends your rides to the Chiron test environment.',
                fr: 'Fluxidi envoie automatiquement vos courses vers l’environnement de test Chiron.',
                es: 'Fluxidi envía automáticamente sus viajes al entorno de prueba Chiron.',
                de: 'Fluxidi sendet Ihre Fahrten automatisch an die Chiron-Testumgebung.',
              ),
              style: TextStyle(color: text, fontSize: 12, height: 1.35),
            ),
          ],
          if (_busy) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(minHeight: 3),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 12)),
          ],
          if (_success != null) ...[
            const SizedBox(height: 8),
            Text(
              _success!,
              style: const TextStyle(color: Color(0xFF1F7A4A), fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
