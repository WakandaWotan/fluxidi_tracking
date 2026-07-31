// RELEASE-P0-CHIRON-STATE-MACHINE-2026-07-31
//
// Split status labels for the Chiron compliance dashboard. Replaces the
// previously ambiguous "Official submission: off" line with three explicit
// projections of the new backend state machine:
//
//   1. ACC-testinzending: actief / inactief
//   2. Productie-inzending: actief / inactief
//   3. Huidige Chiron-omgeving: Test/ACC | Productie
//
// The widget is fully driven by the new backend fields
// (`effective_chiron_environment`, `acc_test_submit_active`,
// `production_submit_active`, `production_last_connection_status`) so no
// business logic is duplicated on the client side. Localized in NL/EN/FR/ES,
// aligned with the AppLanguage contract already used by the dashboard.
//
// Scope discipline: this file intentionally does NOT touch the reset dialog,
// credential editors, connection-test buttons or any other existing dashboard
// surface. It only renders three lines + an optional gated-production block.

import 'package:flutter/material.dart';

import '../app_config.dart';
import '../app_strings.dart';
import '../chiron_company_connection_config.dart';

class ChironEnvironmentStatusLabels extends StatelessWidget {
  const ChironEnvironmentStatusLabels({
    super.key,
    required this.status,
    required this.language,
    this.textColor,
    this.mutedColor,
  });

  final BackendChironConnectionStatus? status;
  final AppLanguage language;
  final Color? textColor;
  final Color? mutedColor;

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
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
    }
  }

  String _actief() =>
      _t(nl: 'actief', en: 'active', fr: 'actif', es: 'activo');
  String _inactief() =>
      _t(nl: 'inactief', en: 'inactive', fr: 'inactif', es: 'inactivo');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedText = textColor ?? theme.colorScheme.onSurface;
    final resolvedMuted = mutedColor ?? theme.colorScheme.onSurfaceVariant;
    final s = status;

    final accActive = s?.accTestSubmitActive ?? false;
    final prodActive = s?.productionSubmitActive ?? false;
    final effectiveEnv =
        (s?.effectiveChironEnvironment ?? ChironConnectionEnvironment.test);

    final envLabel = effectiveEnv == ChironConnectionEnvironment.production
        ? _t(nl: 'Productie', en: 'Production', fr: 'Production', es: 'Producción')
        : _t(nl: 'Test/ACC', en: 'Test/ACC', fr: 'Test/ACC', es: 'Test/ACC');

    Widget line(String label, String value, bool positive) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(color: resolvedMuted, fontSize: 13),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: positive
                    ? const Color(0xFF1F7A4A).withOpacity(0.18)
                    : resolvedMuted.withOpacity(0.16),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                value,
                style: TextStyle(
                  color: positive ? const Color(0xFF1F7A4A) : resolvedText,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      key: const ValueKey('chiron_environment_status_labels'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        line(
          _t(
            nl: 'ACC-testinzending',
            en: 'ACC test submission',
            fr: 'Envoi test ACC',
            es: 'Envío test ACC',
          ),
          accActive ? _actief() : _inactief(),
          accActive,
        ),
        line(
          _t(
            nl: 'Productie-inzending',
            en: 'Production submission',
            fr: 'Envoi production',
            es: 'Envío producción',
          ),
          prodActive ? _actief() : _inactief(),
          prodActive,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _t(
                    nl: 'Huidige Chiron-omgeving',
                    en: 'Current Chiron environment',
                    fr: 'Environnement Chiron actuel',
                    es: 'Entorno Chiron actual',
                  ),
                  style: TextStyle(color: resolvedMuted, fontSize: 13),
                ),
              ),
              Text(
                envLabel,
                style: TextStyle(
                  color: resolvedText,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Gated production block. Rendered inside the "Chiron Productieomgeving"
/// section. Locked until the acceptance test is complete
/// (`testflow_status == "complete"`); once unlocked, shows a compact
/// production-onboarding placeholder with the official Chiron production
/// registration link. The actual "save production credentials / test
/// production connection / enable production" write endpoints are wired in a
/// later phase — this widget only exposes the UI contract.
class ChironProductionBlockGated extends StatelessWidget {
  const ChironProductionBlockGated({
    super.key,
    required this.status,
    required this.testflowStatus,
    required this.language,
    this.backgroundColor,
    this.textColor,
    this.mutedColor,
  });

  final BackendChironConnectionStatus? status;
  final String testflowStatus;
  final AppLanguage language;
  final Color? backgroundColor;
  final Color? textColor;
  final Color? mutedColor;

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
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
    }
  }

  bool get _unlocked =>
      testflowStatus.trim().toLowerCase() == 'complete';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = backgroundColor ?? theme.colorScheme.surface;
    final text = textColor ?? theme.colorScheme.onSurface;
    final muted = mutedColor ?? theme.colorScheme.onSurfaceVariant;

    final title = _t(
      nl: 'Chiron productieomgeving',
      en: 'Chiron production environment',
      fr: 'Environnement Chiron production',
      es: 'Entorno Chiron producción',
    );

    if (!_unlocked) {
      return Container(
        key: const ValueKey('chiron_production_block_locked'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: muted.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lock_outline, size: 18, color: muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: text,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _t(
                nl:
                    'Vergrendeld. Voltooi eerst de acceptatietest (5/5 vertrek + 5/5 aankomst) in de testomgeving.',
                en:
                    'Locked. Complete the acceptance test (5/5 departure + 5/5 arrival) in the test environment first.',
                fr:
                    'Verrouillé. Terminez d\'abord le test d\'acceptation (5/5 départ + 5/5 arrivée) dans l\'environnement de test.',
                es:
                    'Bloqueado. Complete primero la prueba de aceptación (5/5 salida + 5/5 llegada) en el entorno de prueba.',
              ),
              style: TextStyle(color: muted, fontSize: 13, height: 1.35),
            ),
          ],
        ),
      );
    }

    return Container(
      key: const ValueKey('chiron_production_block_unlocked'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: muted.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.workspace_premium_outlined, size: 18, color: text),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: text,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            'https://chiron.vlaanderen.be/chiron/registratie/toegang',
            style: TextStyle(color: text, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Text(
            _t(
              nl:
                  'Meld u aan in het Chiron-productieportaal en haal daar uw aparte productie Client ID en Client Secret op.',
              en:
                  'Sign in to the Chiron production portal to obtain your separate production Client ID and Client Secret.',
              fr:
                  'Connectez-vous au portail Chiron production pour obtenir vos Client ID et Client Secret production distincts.',
              es:
                  'Inicie sesión en el portal Chiron de producción para obtener sus Client ID y Client Secret de producción separados.',
            ),
            style: TextStyle(color: muted, fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _actionChip(_t(
                nl: 'Productiegegevens opslaan',
                en: 'Save production credentials',
                fr: 'Enregistrer les identifiants',
                es: 'Guardar credenciales',
              ), muted),
              _actionChip(_t(
                nl: 'Productieverbinding controleren',
                en: 'Check production connection',
                fr: 'Vérifier la connexion',
                es: 'Verificar conexión',
              ), muted),
              _actionChip(_t(
                nl: 'Productie activeren',
                en: 'Activate production',
                fr: 'Activer la production',
                es: 'Activar producción',
              ), muted),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _t(
              nl:
                  'Productie activeren blijft geblokkeerd zolang productiecredentials of productie-OAuth-test ontbreken.',
              en:
                  'Activation stays blocked until production credentials and the production OAuth test are in place.',
              fr:
                  'L\'activation reste bloquée tant que les identifiants et le test OAuth production sont manquants.',
              es:
                  'La activación permanece bloqueada mientras falten las credenciales o la prueba OAuth de producción.',
            ),
            style: TextStyle(
              color: muted,
              fontSize: 12,
              fontStyle: FontStyle.italic,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionChip(String label, Color muted) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: muted.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: muted.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(color: muted, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
