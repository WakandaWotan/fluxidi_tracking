// RELEASE-P0-CHIRON-SELF-SERVICE-2026-07-31
// Interactive production credentials card for self-service onboarding.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_config.dart';
import '../app_strings.dart';
import 'chiron_self_service_wizard.dart';

typedef ChironProductionSave =
    Future<void> Function(String clientId, String clientSecret);
typedef ChironProductionTest = Future<void> Function();
typedef ChironProductionActivate = Future<void> Function();

class ChironProductionSetupCard extends StatefulWidget {
  const ChironProductionSetupCard({
    super.key,
    required this.status,
    required this.language,
    required this.onSave,
    required this.onTestConnection,
    required this.onActivate,
    this.backgroundColor,
    this.textColor,
    this.mutedColor,
  });

  final BackendChironConnectionStatus? status;
  final AppLanguage language;
  final ChironProductionSave onSave;
  final ChironProductionTest onTestConnection;
  final ChironProductionActivate onActivate;
  final Color? backgroundColor;
  final Color? textColor;
  final Color? mutedColor;

  @override
  State<ChironProductionSetupCard> createState() =>
      _ChironProductionSetupCardState();
}

class _ChironProductionSetupCardState extends State<ChironProductionSetupCard> {
  final _clientIdCtrl = TextEditingController();
  final _clientSecretCtrl = TextEditingController();
  bool _busy = false;
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

  bool get _unlocked =>
      (widget.status?.testflowStatus ?? '').trim().toLowerCase() == 'complete';

  String get _blockReason {
    final s = widget.status;
    if (!_unlocked) {
      return _t(
        nl: 'Voltooi eerst de acceptatietest.',
        en: 'Complete the acceptance test first.',
        fr: 'Terminez d\'abord le test d\'acceptation.',
        es: 'Complete primero la prueba de aceptación.',
        de: 'Schließen Sie zuerst den Akzeptanztest ab.',
      );
    }
    if (s?.productionCredentialsStored != true) {
      return _t(
        nl: 'Voer eerst uw productiegegevens in.',
        en: 'Enter your production credentials first.',
        fr: 'Saisissez d\'abord vos identifiants production.',
        es: 'Introduzca primero sus credenciales de producción.',
        de: 'Geben Sie zuerst Ihre Produktionsdaten ein.',
      );
    }
    if (s?.productionLastConnectionStatus != 'test_passed') {
      return _t(
        nl: 'Controleer eerst de productieverbinding.',
        en: 'Check the production connection first.',
        fr: 'Vérifiez d\'abord la connexion production.',
        es: 'Compruebe primero la conexión de producción.',
        de: 'Prüfen Sie zuerst die Produktionsverbindung.',
      );
    }
    if (s?.productionSubmitActive == true) {
      return _t(
        nl: 'Chiron-productie is actief. Nieuwe ritten worden automatisch en realtime naar de Chiron-productieomgeving verstuurd.',
        en: 'Chiron production is active. New rides are sent automatically and in real time to the Chiron production environment.',
        fr: 'La production Chiron est active. Les nouvelles courses sont envoyées automatiquement et en temps réel vers l\'environnement production Chiron.',
        es: 'La producción Chiron está activa. Los nuevos viajes se envían automática y en tiempo real al entorno de producción Chiron.',
        de: 'Chiron-Produktion ist aktiv. Neue Fahrten werden automatisch und in Echtzeit an die Chiron-Produktionsumgebung gesendet.',
      );
    }
    return _t(
      nl: 'Activeer productie expliciet wanneer u klaar bent.',
      en: 'Activate production explicitly when you are ready.',
      fr: 'Activez explicitement la production lorsque vous êtes prêt.',
      es: 'Active la producción explícitamente cuando esté listo.',
      de: 'Aktivieren Sie die Produktion ausdrücklich, wenn Sie bereit sind.',
    );
  }

  bool get _canActivate =>
      _unlocked &&
      widget.status?.productionCredentialsStored == true &&
      widget.status?.productionLastConnectionStatus == 'test_passed' &&
      widget.status?.productionSubmitActive != true;

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
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll(RegExp(r'(secret|token|bearer)[^\s]*', caseSensitive: false), '***');
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

    return Container(
      key: ValueKey(
        _unlocked
            ? 'chiron_production_block_unlocked'
            : 'chiron_production_block_locked',
      ),
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
              nl: '3. Chiron-productieomgeving',
              en: '3. Chiron production environment',
              fr: '3. Environnement Chiron production',
              es: '3. Entorno Chiron producción',
              de: '3. Chiron-Produktionsumgebung',
            ),
            style: TextStyle(
              color: text,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _unlocked
                ? _t(
                    nl: 'Uw acceptatietest is geslaagd. Meld u aan bij het officiële Chiron-productieportaal en haal daar uw aparte productie Client ID en Productie Client Secret op.',
                    en: 'Your acceptance test passed. Sign in to the official Chiron production portal and obtain your separate production Client ID and Client Secret.',
                    fr: 'Votre test d’acceptation est réussi. Connectez-vous au portail production Chiron officiel et récupérez vos Client ID et Client Secret production distincts.',
                    es: 'Su prueba de aceptación se superó. Inicie sesión en el portal oficial de producción Chiron y obtenga su Client ID y Client Secret de producción separados.',
                    de: 'Ihr Akzeptanztest war erfolgreich. Melden Sie sich im offiziellen Chiron-Produktionsportal an und holen Sie Ihre separate Produktions-Client-ID und das Client-Secret ab.',
                  )
                : _t(
                    nl: 'Deze stap wordt beschikbaar nadat de acceptatietest geslaagd is.',
                    en: 'This step becomes available after the acceptance test succeeds.',
                    fr: 'Cette étape devient disponible après la réussite du test d’acceptation.',
                    es: 'Este paso estará disponible cuando la prueba de aceptación se haya superado.',
                    de: 'Dieser Schritt wird verfügbar, nachdem der Akzeptanztest erfolgreich war.',
                  ),
            style: TextStyle(color: muted, fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 44,
            child: OutlinedButton.icon(
              onPressed: !_unlocked
                  ? null
                  : () async {
                      final uri = Uri.parse(kChironProductionPortalUrl);
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    },
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text(
                _t(
                  nl: 'Open Chiron-productieportaal',
                  en: 'Open Chiron production portal',
                  fr: 'Ouvrir le portail production Chiron',
                  es: 'Abrir portal de producción Chiron',
                  de: 'Chiron-Produktionsportal öffnen',
                ),
              ),
            ),
          ),
          if (_unlocked) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _clientIdCtrl,
              enabled: !_busy,
              decoration: InputDecoration(
                labelText: _t(
                  nl: 'Productie Client ID',
                  en: 'Production Client ID',
                  fr: 'Client ID production',
                  es: 'Client ID de producción',
                  de: 'Produktions-Client-ID',
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
                  nl: 'Productie Client Secret',
                  en: 'Production Client Secret',
                  fr: 'Client Secret production',
                  es: 'Client Secret de producción',
                  de: 'Produktions-Client-Secret',
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
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
                        nl: 'Productiegegevens opslaan',
                        en: 'Save production credentials',
                        fr: 'Enregistrer les identifiants',
                        es: 'Guardar credenciales',
                        de: 'Produktionsdaten speichern',
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _run(widget.onTestConnection),
                    child: Text(
                      _t(
                        nl: 'Productieverbinding controleren',
                        en: 'Check production connection',
                        fr: 'Vérifier la connexion',
                        es: 'Verificar conexión',
                        de: 'Produktionsverbindung prüfen',
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  height: 44,
                  child: FilledButton.tonal(
                    onPressed: !_canActivate || _busy
                        ? null
                        : () => _run(widget.onActivate),
                    child: Text(
                      _t(
                        nl: 'Productie activeren',
                        en: 'Activate production',
                        fr: 'Activer la production',
                        es: 'Activar producción',
                        de: 'Produktion aktivieren',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Text(
            _blockReason,
            style: TextStyle(
              color: muted,
              fontSize: 12,
              fontStyle: FontStyle.italic,
              height: 1.35,
            ),
          ),
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
            Text(_success!, style: TextStyle(color: const Color(0xFF1F7A4A), fontSize: 12)),
          ],
        ],
      ),
    );
  }
}
