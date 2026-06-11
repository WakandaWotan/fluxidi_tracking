import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/business_settings_page.dart';

/// Setup-choice page shown right after [CompanyOnboardingPage] succeeds,
/// before any settings flow starts. Lets the freshly-onboarded operator
/// pick between the deterministic step wizard, the full settings cockpit,
/// or deferring setup. The page is intentionally stateless and passes all
/// three intents back to the host (`role_entry_page.dart`) so navigation
/// (and existing token/bootstrap checks) stays in one place.
///
/// Existing companies do NOT see this page; only the freshly-onboarded
/// branch in `_openBusinessOnboarding` pushes it.
class BusinessFirstRunSetupChoicePage extends StatelessWidget {
  const BusinessFirstRunSetupChoicePage({
    super.key,
    required this.onStartStepWizard,
    required this.onOpenFullSettings,
    required this.onSkip,
  });

  /// User picked "Stap voor stap instellen" / "Set up step by step".
  /// The host should pushReplacement to [BusinessFirstRunWizardPage].
  final VoidCallback onStartStepWizard;

  /// User picked "Volledige instellingen openen" / "Open full settings".
  /// The host should navigate to BusinessHomePage AND push the normal
  /// [BusinessSettingsPage] on top so back goes to BusinessHomePage.
  final VoidCallback onOpenFullSettings;

  /// User picked "Later instellen" / "Set up later". The host should
  /// navigate straight to BusinessHomePage with a clear reason tag.
  final VoidCallback onSkip;

  String _t(_Tr tr) {
    switch (appLanguageNotifier.value) {
      case AppLanguage.nl:
        return tr.nl;
      case AppLanguage.en:
        return tr.en;
      case AppLanguage.fr:
        return tr.fr;
      case AppLanguage.es:
        return tr.es;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appLanguageNotifier,
      builder: (context, _) {
        // Match the dark-navy/gold styling already used by
        // CompanyOnboardingPage so the freshly-onboarded operator sees a
        // single coherent registration flow before they enter the
        // (theme-aware) BusinessSettingsPage.
        const bgColor = Color(0xFF0B1020);
        const panelColor = Color(0xFF121A2E);
        const goldColor = Color(0xFFE5B641);
        return Scaffold(
          backgroundColor: bgColor,
          appBar: AppBar(
            backgroundColor: bgColor,
            elevation: 0,
            automaticallyImplyLeading: false,
            title: Text(
              _t(
                const _Tr(
                  nl: 'Volgende stap',
                  en: 'Next step',
                  fr: 'Étape suivante',
                  es: 'Siguiente paso',
                ),
              ),
              style: const TextStyle(color: Colors.white),
            ),
          ),
          body: SafeArea(
            top: false,
            minimum: const EdgeInsets.only(bottom: 16),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: panelColor,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: goldColor.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: goldColor.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.celebration_outlined,
                                color: goldColor,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _t(
                                  const _Tr(
                                    nl: 'Je bedrijf is aangemaakt',
                                    en: 'Your company is ready',
                                    fr: 'Votre entreprise est prête',
                                    es: 'Tu empresa está lista',
                                  ),
                                ),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _t(
                            const _Tr(
                              nl: 'Fluxidi kan u stap voor stap door de belangrijkste instellingen leiden, of u kunt direct de volledige instellingen openen.',
                              en: 'Fluxidi can walk you step by step through the most important settings, or you can jump straight into the full settings page.',
                              fr: 'Fluxidi peut vous guider étape par étape parmi les paramètres essentiels, ou vous pouvez ouvrir directement la page complète des paramètres.',
                              es: 'Fluxidi puede guiarte paso a paso por los ajustes esenciales, o puedes abrir directamente la página completa de configuración.',
                            ),
                          ),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13.5,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    onPressed: onStartStepWizard,
                    style: FilledButton.styleFrom(
                      backgroundColor: goldColor,
                      foregroundColor: const Color(0xFF0B1020),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.checklist_rounded),
                    label: Text(
                      _t(
                        const _Tr(
                          nl: 'Stap voor stap instellen',
                          en: 'Set up step by step',
                          fr: 'Configurer étape par étape',
                          es: 'Configurar paso a paso',
                        ),
                      ),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: onOpenFullSettings,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.tune_outlined),
                    label: Text(
                      _t(
                        const _Tr(
                          nl: 'Volledige instellingen openen',
                          en: 'Open full settings',
                          fr: 'Ouvrir tous les paramètres',
                          es: 'Abrir configuración completa',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: TextButton(
                      onPressed: onSkip,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white60,
                      ),
                      child: Text(
                        _t(
                          const _Tr(
                            nl: 'Later instellen',
                            en: 'Set up later',
                            fr: 'Configurer plus tard',
                            es: 'Configurar más tarde',
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// First-run business setup wizard.
///
/// Pushed in place of [BusinessFirstRunSetupChoicePage] only when the user
/// explicitly picked "Stap voor stap instellen". Walks the operator through
/// a fixed deterministic sequence of focused [BusinessSettingsPage] steps.
/// Persistence is delegated end to end to the existing settings save
/// orchestrator (`_BusinessSettingsPageState._save`) via
/// `BusinessSettingsPage.stepMode` + `BusinessSettingsPage.onStepSaved`.
/// This wizard host:
///
/// * does NOT declare any `TextEditingController`s,
/// * does NOT replicate `_backendCompanyNameCtrl`, `_baseFareCtrl`,
///   `_perKmCtrl`, `_supportEmailCtrl`, `_logoPathCtrl`, etc.,
/// * does NOT call backend workers (`saveBackendBusinessProfile`,
///   `_saveBackendTaxProfile`, `_saveCancellationPolicyProfile`,
///   `_saveAirportFixedFareRules`, `updateBusinessSettings`),
/// * does NOT touch `CompanySessionStore` or any data model,
/// * does NOT recompute completion status — it just advances when
///   `BusinessSettingsPage` reports a saved step.
///
/// Existing companies that already have a valid session navigate directly
/// to BusinessHomePage and never see this page.
class BusinessFirstRunWizardPage extends StatefulWidget {
  const BusinessFirstRunWizardPage({
    super.key,
    required this.onFinished,
    this.onSkipped,
  });

  /// Invoked after the user completes (saves) the last step. The host is
  /// responsible for navigating onwards (typically to BusinessHomePage via
  /// `_navigateToBusinessHomeWithBootstrapHydration`).
  final VoidCallback onFinished;

  /// Invoked when the user explicitly defers setup via the AppBar
  /// overflow menu's "Finish setup later" action (after a confirm
  /// dialog). When null, the action falls back to [onFinished] so the
  /// user always lands on BusinessHomePage rather than getting stuck
  /// on the wizard. NOTE: this is distinct from per-step skip — see
  /// `_handleSkipCurrentStep` — which never invokes this callback.
  final VoidCallback? onSkipped;

  @override
  State<BusinessFirstRunWizardPage> createState() =>
      _BusinessFirstRunWizardPageState();
}

class _BusinessFirstRunWizardPageState
    extends State<BusinessFirstRunWizardPage> {
  /// Deterministic step list. Section ids MUST be members of
  /// `_kStepFocusableSectionIds` declared in `business_settings_page.dart`
  /// for `BusinessSettingsPage(stepMode: true)` to render the focused
  /// section. The wizard never invents new settings sections; it only
  /// navigates between existing ones.
  ///
  /// Order is verified by the runtime `[FIRST_RUN_WIZARD][STEP]` log:
  ///   1. official_company_details
  ///   2. vat_settings
  ///   3. service_setup
  ///   4. pricing_engine
  ///   5. branding_support
  ///   6. google_calendar        ← optional, skippable, OAuth-driven
  ///   7. airport_fixed_fares    ← optional, skippable, airport-only
  ///   8. public_booking_link    ← final summary step
  ///
  /// The `optional` flag is metadata used for log clarity. The top-right
  /// AppBar action skips ONE step on every step (required or optional)
  /// so users cannot accidentally abandon the whole wizard by tapping a
  /// per-step skip label. Whole-wizard exit lives behind a separate
  /// overflow menu ("Finish setup later") wired via `onExitWizard`.
  /// Optional integration steps (Google Calendar, Airport fixed fares)
  /// never block the operator from reaching BusinessHomePage and never
  /// add new backend calls — they render the existing
  /// `_googleCalendarCard()` / `_airportFixedFareCard()` from
  /// BusinessSettingsPage so OAuth, rules, and save logic stay in one
  /// place.
  static const List<_BusinessFirstRunStep> _steps = <_BusinessFirstRunStep>[
    _BusinessFirstRunStep(
      sectionId: 'official_company_details',
      title: _Tr(
        nl: 'Bedrijfsgegevens',
        en: 'Company details',
        fr: "Informations de l'entreprise",
        es: 'Datos de la empresa',
      ),
      subtitle: _Tr(
        nl: 'Bevestig juridische naam, btw en adres.',
        en: 'Confirm legal name, VAT, and address.',
        fr: "Confirmez la raison sociale, la TVA et l'adresse.",
        es: 'Confirma razón social, IVA y dirección.',
      ),
    ),
    _BusinessFirstRunStep(
      sectionId: 'vat_settings',
      title: _Tr(
        nl: 'Btw & facturatie',
        en: 'VAT & invoicing',
        fr: 'TVA et facturation',
        es: 'IVA y facturación',
      ),
      subtitle: _Tr(
        nl: 'Stel het btw-tarief en factuurtekst in.',
        en: 'Set the VAT rate and invoice text.',
        fr: 'Définissez le taux de TVA et le texte de facture.',
        es: 'Configura la tasa de IVA y el texto de factura.',
      ),
    ),
    _BusinessFirstRunStep(
      sectionId: 'service_setup',
      title: _Tr(
        nl: 'Diensten',
        en: 'Services',
        fr: 'Services',
        es: 'Servicios',
      ),
      subtitle: _Tr(
        nl: 'Selecteer welke diensten u aanbiedt.',
        en: 'Select which services you offer.',
        fr: 'Sélectionnez les services proposés.',
        es: 'Selecciona qué servicios ofreces.',
      ),
    ),
    _BusinessFirstRunStep(
      sectionId: 'pricing_engine',
      title: _Tr(
        nl: 'Prijzen',
        en: 'Pricing',
        fr: 'Tarification',
        es: 'Precios',
      ),
      subtitle: _Tr(
        nl: 'Basisprijs, kilometertarief en toeslagen.',
        en: 'Base fare, per-km rate, and surcharges.',
        fr: 'Prix de base, tarif au km et suppléments.',
        es: 'Tarifa base, por km y recargos.',
      ),
    ),
    _BusinessFirstRunStep(
      sectionId: 'branding_support',
      title: _Tr(
        nl: 'Branding & support',
        en: 'Branding & support',
        fr: 'Branding et support',
        es: 'Marca y soporte',
      ),
      subtitle: _Tr(
        nl: 'Logo, support-e-mail en contactgegevens.',
        en: 'Logo, support email, and contact details.',
        fr: 'Logo, e-mail de support et coordonnées.',
        es: 'Logo, correo de soporte y contacto.',
      ),
    ),
    _BusinessFirstRunStep(
      sectionId: 'google_calendar',
      optional: true,
      title: _Tr(
        nl: 'Google Calendar',
        en: 'Google Calendar',
        fr: 'Google Agenda',
        es: 'Google Calendar',
      ),
      subtitle: _Tr(
        nl: 'Optioneel: koppel uw Google-agenda. Sla over indien gewenst.',
        en: 'Optional: connect your Google calendar. Skip if not needed.',
        fr: 'Optionnel : connectez votre agenda Google. Ignorez si non nécessaire.',
        es: 'Opcional: conecta tu calendario de Google. Omite si no lo necesitas.',
      ),
    ),
    _BusinessFirstRunStep(
      sectionId: 'airport_fixed_fares',
      optional: true,
      title: _Tr(
        nl: 'Luchthaven vaste tarieven',
        en: 'Airport fixed fares',
        fr: 'Tarifs fixes aéroport',
        es: 'Tarifas fijas aeropuerto',
      ),
      subtitle: _Tr(
        nl: 'Optioneel: vaste prijzen per luchthaven. Sla over als niet relevant.',
        en: 'Optional: fixed prices per airport. Skip if not relevant.',
        fr: 'Optionnel : prix fixes par aéroport. Ignorez si non pertinent.',
        es: 'Opcional: precios fijos por aeropuerto. Omite si no aplica.',
      ),
    ),
    _BusinessFirstRunStep(
      sectionId: 'public_booking_link',
      title: _Tr(
        nl: 'Boekingslink',
        en: 'Booking link',
        fr: 'Lien de réservation',
        es: 'Enlace de reserva',
      ),
      subtitle: _Tr(
        nl: 'Controleer uw publieke boekingslink.',
        en: 'Review your public booking link.',
        fr: 'Vérifiez votre lien de réservation public.',
        es: 'Revisa tu enlace público de reserva.',
      ),
    ),
  ];

  int _index = 0;

  @override
  void initState() {
    super.initState();
    debugPrint('[FIRST_RUN_WIZARD][OPEN] totalSteps=${_steps.length}');
    _logCurrentStep();
  }

  void _logCurrentStep() {
    final step = _steps[_index];
    // 1-based index for human-friendly logs that match the AppBar strip
    // ("Stap 1 van 8") so QA can correlate with the on-screen progress.
    debugPrint(
      '[FIRST_RUN_WIZARD][STEP] index=${_index + 1}/${_steps.length} '
      'section=${step.sectionId}'
      '${step.optional ? ' optional=true' : ''}',
    );
    // Targeted logs so QA can grep for the optional integration steps
    // regardless of where they sit in the deterministic sequence.
    if (step.sectionId == 'google_calendar') {
      debugPrint('[FIRST_RUN_WIZARD][OPEN_GOOGLE_CALENDAR]');
    } else if (step.sectionId == 'airport_fixed_fares') {
      debugPrint('[FIRST_RUN_WIZARD][OPEN_AIRPORT_FIXED_FARES]');
    }
  }

  String _t(_Tr tr) {
    switch (appLanguageNotifier.value) {
      case AppLanguage.nl:
        return tr.nl;
      case AppLanguage.en:
        return tr.en;
      case AppLanguage.fr:
        return tr.fr;
      case AppLanguage.es:
        return tr.es;
    }
  }

  /// Called by [BusinessSettingsPage] after its existing `_save()` returns
  /// in step mode. We never inspect save success/failure here —
  /// `BusinessSettingsPage` already shows per-part snackbars on error and
  /// the user can re-tap "Save and continue" to retry. This keeps the
  /// wizard from second-guessing the save architecture.
  void _handleStepSaved() {
    if (!mounted) return;
    final fromSection = _steps[_index].sectionId;
    debugPrint(
      '[FIRST_RUN_WIZARD][SAVE_NEXT] from=$fromSection '
      'index=${_index + 1}/${_steps.length}',
    );
    if (_index >= _steps.length - 1) {
      debugPrint('[FIRST_RUN_WIZARD][FINISH] last_section=$fromSection');
      widget.onFinished();
      return;
    }
    setState(() => _index += 1);
    _logCurrentStep();
  }

  /// Per-step skip wired to the AppBar's primary top-right action on
  /// EVERY wizard step (required and optional). Advances the wizard
  /// one step without terminating the whole flow and without showing
  /// a confirmation dialog — the user remains in the wizard and
  /// continues to the next step. Reuses [_handleStepSaved] so the
  /// advance/finish logic stays in one place. Whole-wizard exit lives
  /// in [_handleSkipPressed], wired separately via the AppBar overflow
  /// menu ("Finish setup later").
  void _handleSkipCurrentStep() {
    if (!mounted) return;
    final fromSection = _steps[_index].sectionId;
    // Always emit the generic per-step skip log so QA can see EVERY
    // skip event regardless of section.
    debugPrint(
      '[FIRST_RUN_WIZARD][SKIP_STEP] section=$fromSection '
      'from_index=${_index + 1}/${_steps.length}',
    );
    // Targeted logs for the optional integration steps so QA can grep
    // for them quickly without scanning all SKIP_STEP lines.
    if (fromSection == 'google_calendar') {
      debugPrint(
        '[FIRST_RUN_WIZARD][SKIP_GOOGLE_CALENDAR] '
        'from_index=${_index + 1}/${_steps.length}',
      );
    } else if (fromSection == 'airport_fixed_fares') {
      debugPrint(
        '[FIRST_RUN_WIZARD][SKIP_AIRPORT_FIXED_FARES] '
        'from_index=${_index + 1}/${_steps.length}',
      );
    }
    _handleStepSaved();
  }

  Future<void> _handleSkipPressed() async {
    final shouldSkip = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(
          _t(
            const _Tr(
              nl: 'Setup later afmaken?',
              en: 'Finish setup later?',
              fr: 'Terminer la configuration plus tard ?',
              es: '¿Terminar la configuración más tarde?',
            ),
          ),
        ),
        content: Text(
          _t(
            const _Tr(
              nl: 'U kunt deze stappen later afronden via Bedrijfsinstellingen.',
              en: 'You can complete these steps later from Business settings.',
              fr: 'Vous pourrez compléter ces étapes plus tard depuis les paramètres entreprise.',
              es: 'Puedes completar estos pasos más tarde desde la configuración de empresa.',
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(
              _t(
                const _Tr(
                  nl: 'Doorgaan',
                  en: 'Continue',
                  fr: 'Continuer',
                  es: 'Continuar',
                ),
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(
              _t(
                const _Tr(
                  nl: 'Later',
                  en: 'Later',
                  fr: 'Plus tard',
                  es: 'Más tarde',
                ),
              ),
            ),
          ),
        ],
      ),
    );
    if (shouldSkip != true) return;
    if (!mounted) return;
    debugPrint(
      '[FIRST_RUN_WIZARD][SKIP] '
      'from_index=${_index + 1}/${_steps.length} '
      'section=${_steps[_index].sectionId}',
    );
    final cb = widget.onSkipped ?? widget.onFinished;
    cb();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appLanguageNotifier,
      builder: (context, _) {
        final step = _steps[_index];
        // The top-right AppBar action skips ONE step on every step
        // (required and optional). This prevents users from accidentally
        // abandoning the entire wizard by tapping a per-step skip
        // label. Whole-wizard exit ("Finish setup later") is wired as a
        // separate overflow-menu item via [onExitWizard] below — it
        // still shows the existing confirm dialog before navigating to
        // BusinessHomePage, so an explicit two-tap gesture is required.
        final String stepSkipLabel = _t(
          const _Tr(
            nl: 'Deze stap overslaan',
            en: 'Skip this step',
            fr: 'Ignorer cette étape',
            es: 'Omitir este paso',
          ),
        );
        final String exitWizardLabel = _t(
          const _Tr(
            nl: 'Setup later afmaken',
            en: 'Finish setup later',
            fr: 'Terminer plus tard',
            es: 'Terminar más tarde',
          ),
        );
        return BusinessSettingsPage(
          // Distinct key per section forces _BusinessSettingsPageState to
          // rebuild from scratch when advancing, which guarantees the new
          // focused section is opened (via initState's
          // _expandedSections.add(focus)) and that the previous step's
          // controllers/notifier listeners are torn down cleanly.
          key: ValueKey<String>('first_run_wizard:${step.sectionId}'),
          initialFocus: step.sectionId,
          stepMode: true,
          stepTitle: _t(step.title),
          stepSubtitle: _t(step.subtitle),
          stepIndex: _index + 1,
          stepTotal: _steps.length,
          onStepSaved: _handleStepSaved,
          onSkipStep: _handleSkipCurrentStep,
          skipStepLabel: stepSkipLabel,
          onExitWizard: _handleSkipPressed,
          exitWizardLabel: exitWizardLabel,
        );
      },
    );
  }
}

class _BusinessFirstRunStep {
  const _BusinessFirstRunStep({
    required this.sectionId,
    required this.title,
    required this.subtitle,
    this.optional = false,
  });

  final String sectionId;
  final _Tr title;
  final _Tr subtitle;

  /// Metadata flag set on integration steps (e.g. Google Calendar,
  /// Airport fixed fares) that the operator may legitimately not need.
  /// All steps — required AND optional — share the same per-step skip
  /// action in the AppBar; this flag only annotates the
  /// `[FIRST_RUN_WIZARD][STEP] ... optional=true` log so QA can spot
  /// optional sections at a glance. Skip routing is uniform and lives
  /// in `_handleSkipCurrentStep`; whole-wizard exit lives in
  /// `_handleSkipPressed` (overflow menu only).
  final bool optional;
}

class _Tr {
  const _Tr({
    required this.nl,
    required this.en,
    required this.fr,
    required this.es,
  });

  final String nl;
  final String en;
  final String fr;
  final String es;
}
