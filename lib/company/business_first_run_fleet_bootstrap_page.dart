/// FIRST-COMPANY-UX-P0 — post-settings-wizard operational bootstrap.
///
/// Sequence after [BusinessFirstRunWizardPage] finishes:
///   first driver → first vehicle (link inside vehicle editor) → ready
/// then host continues to orientation (tablet) or Business Home (phone).
library;

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_fleet_operational.dart';
import 'package:fluxidi_tracking/driver_creator_dialog.dart';
import 'package:fluxidi_tracking/vehicle_management_page.dart';

/// Concise first-company fleet bootstrap shown only on the fresh-company
/// first-run path after the settings wizard completes.
class BusinessFirstRunFleetBootstrapPage extends StatefulWidget {
  const BusinessFirstRunFleetBootstrapPage({
    super.key,
    required this.onFinished,
    this.onSkipped,
  });

  /// Invoked when the operator completes (or already satisfied) fleet setup.
  final VoidCallback onFinished;

  /// Optional soft exit ("Later") — host should land on home/orientation
  /// without forcing fleet creation.
  final VoidCallback? onSkipped;

  @override
  State<BusinessFirstRunFleetBootstrapPage> createState() =>
      _BusinessFirstRunFleetBootstrapPageState();
}

class _BusinessFirstRunFleetBootstrapPageState
    extends State<BusinessFirstRunFleetBootstrapPage> {
  static const Color _bg = Color(0xFF0B1020);
  static const Color _panel = Color(0xFF121A2E);
  static const Color _gold = Color(0xFFE5B641);

  bool _busy = false;
  late FirstRunFleetBootstrapStep _step;

  @override
  void initState() {
    super.initState();
    _step = _resolveStep();
    debugPrint(
      '[FIRST_RUN_FLEET_BOOTSTRAP][OPEN] step=${_step.name} '
      'drivers=${companyOperationalDrivers().length} '
      'vehicles=${companyOperationalVehicles().length}',
    );
    // If fleet already present (resume / re-entry), skip straight to ready.
    if (_step == FirstRunFleetBootstrapStep.readyToStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        debugPrint('[FIRST_RUN_FLEET_BOOTSTRAP][AUTO_READY]');
      });
    }
  }

  FirstRunFleetBootstrapStep _resolveStep() {
    return resolveFirstRunFleetBootstrapStep(
      hasDriver: companyHasOperationalDriver(),
      hasVehicle: companyHasOperationalVehicle(),
    );
  }

  void _refreshStep() {
    if (!mounted) return;
    setState(() => _step = _resolveStep());
  }

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) {
    switch (appLanguageNotifier.value) {
      case AppLanguage.nl:
        return nl;
      case AppLanguage.en:
        return en;
      case AppLanguage.fr:
        return fr;
      case AppLanguage.es:
        return es;
      case AppLanguage.de:
        return en;
    }
  }

  Future<bool> _confirmDriverAddGate() async {
    final scopedCount = companyOperationalDrivers().length;
    int effectiveMax = (includedVehicleLimit > 0 ? includedVehicleLimit : 1) * 3;
    final scopeId = resolveActiveCompanyIdForFleetUi();
    if (scopeId != null && scopeId.trim().isNotEmpty) {
      try {
        final profile = await fetchCompanySubscriptionProfile(
          tenantId: scopeId,
          companyId: scopeId,
        );
        if (profile.maxDrivers > 0) {
          effectiveMax = profile.maxDrivers;
        } else if (profile.includedVehicles > 0 &&
            profile.includedDriversPerVehicle > 0) {
          effectiveMax =
              profile.includedVehicles * profile.includedDriversPerVehicle;
        }
      } catch (_) {
        // Fall back to base-plan limit — never hard-block on fetch failure.
      }
    }
    debugPrint(
      '[FIRST_RUN_FLEET_BOOTSTRAP][DRIVER_GATE] '
      'scoped=$scopedCount max=$effectiveMax',
    );
    if (scopedCount < effectiveMax) return true;
    if (!mounted) return false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _panel,
        title: Text(
          _t(
            nl: 'Chauffeurlimiet bereikt',
            en: 'Driver limit reached',
            fr: 'Limite de chauffeurs atteinte',
            es: 'Límite de conductores alcanzado',
          ),
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          _t(
            nl: 'Je huidige limiet is $effectiveMax chauffeurs.',
            en: 'Your current limit is $effectiveMax drivers.',
            fr: 'Votre limite actuelle est de $effectiveMax chauffeurs.',
            es: 'Tu límite actual es de $effectiveMax conductores.',
          ),
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              _t(nl: 'Sluiten', en: 'Close', fr: 'Fermer', es: 'Cerrar'),
            ),
          ),
        ],
      ),
    );
    return false;
  }

  Future<void> _addFirstDriver() async {
    if (_busy) return;
    if (companyHasOperationalDriver()) {
      _refreshStep();
      return;
    }
    setState(() => _busy = true);
    try {
      final allowed = await _confirmDriverAddGate();
      if (!allowed || !mounted) return;
      debugPrint('[FIRST_RUN_FLEET_BOOTSTRAP][DRIVER_OPEN]');
      final created = await showDriverCreatorDialog(
        context,
        companyId: resolveActiveCompanyIdForFleetUi(),
      );
      if (created != null) {
        debugPrint(
          '[FIRST_RUN_FLEET_BOOTSTRAP][DRIVER_SAVED] id=${created.id}',
        );
      }
      _refreshStep();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addFirstVehicle() async {
    if (_busy) return;
    if (companyHasOperationalVehicle()) {
      _refreshStep();
      return;
    }
    if (!companyHasOperationalDriver()) {
      _refreshStep();
      return;
    }
    setState(() => _busy = true);
    try {
      debugPrint('[FIRST_RUN_FLEET_BOOTSTRAP][VEHICLE_OPEN]');
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => const VehicleManagementPage(
            autoOpenNewVehicleEditor: true,
            popPageAfterSuccessfulNewVehicleSave: true,
          ),
        ),
      );
      debugPrint(
        '[FIRST_RUN_FLEET_BOOTSTRAP][VEHICLE_RETURN] saved=${saved == true}',
      );
      _refreshStep();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _finish() {
    debugPrint('[FIRST_RUN_FLEET_BOOTSTRAP][FINISH] step=${_step.name}');
    widget.onFinished();
  }

  void _skip() {
    debugPrint('[FIRST_RUN_FLEET_BOOTSTRAP][SKIP] step=${_step.name}');
    final cb = widget.onSkipped ?? widget.onFinished;
    cb();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        appLanguageNotifier,
        driversNotifier,
        vehiclesNotifier,
      ]),
      builder: (context, _) {
        // Keep step in sync if fleet changes while page is open.
        final resolved = _resolveStep();
        if (resolved != _step) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _step = resolved);
          });
        }
        return Scaffold(
          backgroundColor: _bg,
          appBar: AppBar(
            backgroundColor: _bg,
            elevation: 0,
            automaticallyImplyLeading: false,
            title: Text(
              _t(
                nl: 'Je bedrijf gebruiksklaar maken',
                en: 'Make your company ready to use',
                fr: 'Rendre votre entreprise opérationnelle',
                es: 'Deja tu empresa lista para usar',
              ),
              style: const TextStyle(color: Colors.white),
            ),
            actions: [
              TextButton(
                onPressed: _busy ? null : _skip,
                child: Text(
                  _t(
                    nl: 'Later',
                    en: 'Later',
                    fr: 'Plus tard',
                    es: 'Más tarde',
                  ),
                  style: const TextStyle(color: Colors.white60),
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _introCard(),
                  const SizedBox(height: 18),
                  if (_step == FirstRunFleetBootstrapStep.firstDriver)
                    _driverStepCard(),
                  if (_step == FirstRunFleetBootstrapStep.firstVehicle)
                    _vehicleStepCard(),
                  if (_step == FirstRunFleetBootstrapStep.readyToStart)
                    _readyCard(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _introCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _gold.withOpacity(0.3)),
      ),
      child: Text(
        _t(
          nl: 'Voeg je eerste chauffeur en voertuig toe zodat je meteen ritten kunt uitvoeren. Je kunt dit later ook doen via Chauffeurs en Voertuigen.',
          en: 'Add your first driver and vehicle so you can start taking rides. You can also do this later from Drivers and Vehicles.',
          fr: 'Ajoutez votre premier chauffeur et véhicule pour commencer les courses. Vous pourrez aussi le faire plus tard via Chauffeurs et Véhicules.',
          es: 'Añade tu primer conductor y vehículo para empezar a hacer viajes. También puedes hacerlo más tarde en Conductores y Vehículos.',
        ),
        style: const TextStyle(color: Colors.white70, height: 1.4, fontSize: 13.5),
      ),
    );
  }

  Widget _driverStepCard() {
    return _stepCard(
      icon: Icons.person_add_alt_1_outlined,
      title: _t(
        nl: 'Voeg je eerste chauffeur toe',
        en: 'Add your first driver',
        fr: 'Ajoutez votre premier chauffeur',
        es: 'Añade tu primer conductor',
      ),
      body: _t(
        nl: 'Een chauffeur kan bestaan zonder voertuig. Koppeling gebeurt bij het voertuig.',
        en: 'A driver can exist without a vehicle. Linking happens in the vehicle editor.',
        fr: 'Un chauffeur peut exister sans véhicule. La liaison se fait dans l’éditeur de véhicule.',
        es: 'Un conductor puede existir sin vehículo. La vinculación se hace en el editor de vehículos.',
      ),
      actionLabel: _t(
        nl: 'Chauffeur toevoegen',
        en: 'Add driver',
        fr: 'Ajouter un chauffeur',
        es: 'Añadir conductor',
      ),
      onAction: _busy ? null : _addFirstDriver,
    );
  }

  Widget _vehicleStepCard() {
    return _stepCard(
      icon: Icons.directions_car_outlined,
      title: _t(
        nl: 'Voeg je eerste voertuig toe',
        en: 'Add your first vehicle',
        fr: 'Ajoutez votre premier véhicule',
        es: 'Añade tu primer vehículo',
      ),
      body: _t(
        nl: 'Kies in het voertuigformulier de gekoppelde chauffeur. Zo is je vloot meteen klaar.',
        en: 'In the vehicle form, select the linked driver. Your fleet will then be ready.',
        fr: 'Dans le formulaire véhicule, sélectionnez le chauffeur lié. Votre flotte sera alors prête.',
        es: 'En el formulario del vehículo, selecciona el conductor vinculado. Así tu flota quedará lista.',
      ),
      actionLabel: _t(
        nl: 'Voertuig toevoegen',
        en: 'Add vehicle',
        fr: 'Ajouter un véhicule',
        es: 'Añadir vehículo',
      ),
      onAction: _busy ? null : _addFirstVehicle,
    );
  }

  Widget _readyCard() {
    return _stepCard(
      icon: Icons.check_circle_outline,
      title: _t(
        nl: 'Klaar om te starten',
        en: 'Ready to start',
        fr: 'Prêt à démarrer',
        es: 'Listo para empezar',
      ),
      body: _t(
        nl: 'Je eerste chauffeur en voertuig staan klaar. Ga verder naar Fluxidi.',
        en: 'Your first driver and vehicle are ready. Continue into Fluxidi.',
        fr: 'Votre premier chauffeur et véhicule sont prêts. Continuez vers Fluxidi.',
        es: 'Tu primer conductor y vehículo están listos. Continúa en Fluxidi.',
      ),
      actionLabel: _t(
        nl: 'Doorgaan',
        en: 'Continue',
        fr: 'Continuer',
        es: 'Continuar',
      ),
      onAction: _busy ? null : _finish,
      primary: true,
    );
  }

  Widget _stepCard({
    required IconData icon,
    required String title,
    required String body,
    required String actionLabel,
    required VoidCallback? onAction,
    bool primary = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _gold.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _gold.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: _gold, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            body,
            style: const TextStyle(
              color: Colors.white70,
              height: 1.4,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: onAction,
            style: FilledButton.styleFrom(
              backgroundColor: _gold,
              foregroundColor: _bg,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: _busy && !primary
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF0B1020),
                    ),
                  )
                : Text(
                    actionLabel,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
          ),
        ],
      ),
    );
  }
}
