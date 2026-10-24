// RELEASE-P0-CHIRON-SELF-SERVICE-2026-07-31
// Step 2 — Acceptance test progress for self-service onboarding.

import 'package:flutter/material.dart';

import '../app_config.dart';
import '../app_strings.dart';

class ChironAcceptanceStepCard extends StatelessWidget {
  const ChironAcceptanceStepCard({
    super.key,
    required this.status,
    required this.language,
    required this.onReset,
    this.resetBusy = false,
    this.backgroundColor,
    this.textColor,
    this.mutedColor,
  });

  final BackendChironConnectionStatus? status;
  final AppLanguage language;
  final VoidCallback? onReset;
  final bool resetBusy;
  final Color? backgroundColor;
  final Color? textColor;
  final Color? mutedColor;

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = backgroundColor ?? theme.colorScheme.surface;
    final text = textColor ?? theme.colorScheme.onSurface;
    final muted = mutedColor ?? theme.colorScheme.onSurfaceVariant;
    final dep = status?.testDepartureSentCount ?? 0;
    final arr = status?.testArrivalSentCount ?? 0;
    final rides = status?.testRidesCompletedCount ?? 0;
    final msgs = status?.testMessagesSentCount ?? 0;
    final depReq = status?.testDepartureRequired ?? 5;
    final arrReq = status?.testArrivalRequired ?? 5;
    final ridesReq = status?.testRidesRequired ?? 5;
    final msgsReq = status?.testMessagesRequired ?? 10;
    final complete = (status?.testflowStatus ?? '') == 'complete';

    return Container(
      key: const ValueKey('chiron_acceptance_step_card'),
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
              nl: '2. Acceptatietest',
              en: '2. Acceptance test',
              fr: '2. Test d’acceptation',
              es: '2. Prueba de aceptación',
              de: '2. Akzeptanztest',
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
              nl: 'Rijd vijf volledige ritten. Fluxidi verstuurt bij START automatisch het vertrekbericht en bij STOP automatisch het aankomstbericht met afstand en ritprijs.',
              en: 'Drive five complete rides. At START Fluxidi automatically sends the departure message; at STOP it sends the arrival message with distance and fare.',
              fr: 'Effectuez cinq courses complètes. Au START, Fluxidi envoie automatiquement le départ ; au STOP, l’arrivée avec distance et prix.',
              es: 'Realice cinco viajes completos. En START, Fluxidi envía automáticamente la salida; en STOP, la llegada con distancia y precio.',
              de: 'Fahren Sie fünf vollständige Fahrten. Bei START sendet Fluxidi automatisch die Abfahrt; bei STOP die Ankunft mit Distanz und Preis.',
            ),
            style: TextStyle(color: muted, fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 12),
          Text(
            '${_t(nl: 'Voortgang', en: 'Progress', fr: 'Progression', es: 'Progreso', de: 'Fortschritt')}: $msgs/$msgsReq',
            style: TextStyle(color: text, fontWeight: FontWeight.w700),
          ),
          Text(
            '${_t(nl: 'Vertrek', en: 'Departure', fr: 'Départ', es: 'Salida', de: 'Abfahrt')}: $dep/$depReq',
            style: TextStyle(color: muted, fontSize: 13),
          ),
          Text(
            '${_t(nl: 'Aankomst', en: 'Arrival', fr: 'Arrivée', es: 'Llegada', de: 'Ankunft')}: $arr/$arrReq',
            style: TextStyle(color: muted, fontSize: 13),
          ),
          Text(
            '${_t(nl: 'Ritten afgerond', en: 'Rides completed', fr: 'Courses terminées', es: 'Viajes completados', de: 'Fahrten abgeschlossen')}: $rides/$ridesReq',
            style: TextStyle(color: muted, fontSize: 13),
          ),
          const SizedBox(height: 10),
          Text(
            complete
                ? _t(
                    nl: 'Acceptatietest geslaagd.',
                    en: 'Acceptance test passed.',
                    fr: 'Test d’acceptation réussi.',
                    es: 'Prueba de aceptación superada.',
                    de: 'Akzeptanztest erfolgreich.',
                  )
                : _t(
                    nl: 'Uw ritten worden momenteel automatisch naar de Chiron-testomgeving verstuurd.',
                    en: 'Your rides are currently sent automatically to the Chiron test environment.',
                    fr: 'Vos courses sont actuellement envoyées automatiquement vers l’environnement de test Chiron.',
                    es: 'Sus viajes se envían actualmente de forma automática al entorno de prueba Chiron.',
                    de: 'Ihre Fahrten werden derzeit automatisch an die Chiron-Testumgebung gesendet.',
                  ),
            style: TextStyle(color: text, fontSize: 13, height: 1.35),
          ),
          if (complete) ...[
            const SizedBox(height: 8),
            Text(
              _t(
                nl: 'Fluxidi blijft uw ritten naar de Chiron-testomgeving sturen totdat u aparte productiegegevens invoert, de productieverbinding controleert en productie expliciet activeert.\n\nRitten in de testomgeving gelden niet als wettelijke productieregistratie.',
                en: 'Fluxidi keeps sending rides to the Chiron test environment until you enter separate production credentials, check the production connection and explicitly activate production.\n\nRides in the test environment do not count as legal production registration.',
                fr: 'Fluxidi continue d’envoyer vos courses vers l’environnement de test Chiron jusqu’à ce que vous saisissiez des identifiants production distincts, vérifiez la connexion production et activiez explicitement la production.\n\nLes courses en test ne valent pas comme enregistrement légal de production.',
                es: 'Fluxidi sigue enviando viajes al entorno de prueba Chiron hasta que introduzca credenciales de producción separadas, compruebe la conexión de producción y active la producción explícitamente.\n\nLos viajes en prueba no cuentan como registro legal de producción.',
                de: 'Fluxidi sendet Ihre Fahrten weiter an die Chiron-Testumgebung, bis Sie separate Produktionsdaten eingeben, die Produktionsverbindung prüfen und die Produktion ausdrücklich aktivieren.\n\nFahrten in der Testumgebung gelten nicht als gesetzliche Produktionsregistrierung.',
              ),
              style: TextStyle(color: muted, fontSize: 12, height: 1.4),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            height: 44,
            child: OutlinedButton(
              key: const ValueKey('chiron_reset_testflow_button'),
              onPressed: resetBusy ? null : onReset,
              child: resetBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      _t(
                        nl: 'Testflow resetten',
                        en: 'Reset test flow',
                        fr: 'Réinitialiser le flux de test',
                        es: 'Restablecer flujo de prueba',
                        de: 'Testflow zurücksetzen',
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
