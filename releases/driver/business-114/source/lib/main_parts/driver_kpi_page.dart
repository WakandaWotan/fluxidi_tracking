import 'dart:async';

import 'package:flutter/material.dart';

import '../app_config.dart';
import '../app_strings.dart';
import '../fluxidi_responsive.dart';
import 'driver_kpi_model.dart';

/// FASE 12 — Driver KPI ("My performance") page + controller.
///
/// The controller is UI-free and fully testable. It owns:
/// - a generation guard so a late response from a previous driver/period is
///   ignored (never shown);
/// - a per-(driver, period) in-memory cache that is shown instantly on open but
///   always refreshed;
/// - immediate clearing of the previous driver's data when the effective driver
///   changes.
enum DriverKpiViewState { idle, loading, loaded, empty, error }

typedef DriverKpiRidesFetcher =
    Future<List<DriverKpiRideRecord>> Function(DriverKpiPeriod period);

/// Canonical route name for the chauffeur performance/KPI page.
///
/// Driver-home ("Mijn prestaties") and company Drivers → Rapporten must push
/// the same [DriverKpiPage] under this name so both entry points converge.
const String kDriverKpiRouteName = 'driver_kpi';

/// Navigation contract for opening [DriverKpiPage].
///
/// Carries the selected chauffeur's canonical `driver_id` plus the active
/// tenant/company scope. Auth mode is diagnostic/context only — KPI numbers
/// always come from the same `/trips/history` pipeline for [driverKey].
class DriverKpiRouteArgs {
  const DriverKpiRouteArgs({
    required this.driverKey,
    required this.authMode,
    required this.tenantId,
    required this.companyId,
  });

  final String driverKey;
  final DriverKpiAuthMode authMode;
  final String tenantId;
  final String companyId;

  bool get hasDriver => driverKey.trim().isNotEmpty;

  bool get hasCompanyScope =>
      tenantId.trim().isNotEmpty && companyId.trim().isNotEmpty;
}

/// Company Drivers / Chauffeurs beheren → Rapporten / Prestaties.
DriverKpiRouteArgs driverKpiRouteArgsForCompanyDriver({
  required String driverId,
  required String tenantId,
  required String companyId,
}) {
  return DriverKpiRouteArgs(
    driverKey: driverId.trim(),
    authMode: DriverKpiAuthMode.companyAdmin,
    tenantId: tenantId.trim(),
    companyId: companyId.trim(),
  );
}

/// Driver-home / business-preview → Mijn prestaties.
DriverKpiRouteArgs driverKpiRouteArgsForDriverHome({
  required String driverId,
  required bool companyAdminPreview,
  required String tenantId,
  required String companyId,
}) {
  return DriverKpiRouteArgs(
    driverKey: driverId.trim(),
    authMode: companyAdminPreview
        ? DriverKpiAuthMode.companyAdmin
        : DriverKpiAuthMode.driver,
    tenantId: tenantId.trim(),
    companyId: companyId.trim(),
  );
}

/// Builds the single Material route used by every KPI entry point.
MaterialPageRoute<void> buildDriverKpiPageRoute({
  required DriverKpiRouteArgs args,
  required DriverKpiRidesFetcher fetchRides,
  Color accentColor = const Color(0xFFF5C400),
  DateTime Function()? clock,
  void Function(String message)? logger,
}) {
  return MaterialPageRoute<void>(
    settings: RouteSettings(name: kDriverKpiRouteName, arguments: args),
    builder: (_) => DriverKpiPage(
      fetchRides: fetchRides,
      authMode: args.authMode,
      driverKey: args.driverKey,
      hasDriver: args.hasDriver,
      accentColor: accentColor,
      clock: clock,
      logger: logger,
    ),
  );
}

/// Pushes the canonical [DriverKpiPage]. Returns when the page is popped.
Future<void> pushDriverKpiPage(
  BuildContext context, {
  required DriverKpiRouteArgs args,
  required DriverKpiRidesFetcher fetchRides,
  Color accentColor = const Color(0xFFF5C400),
  DateTime Function()? clock,
  void Function(String message)? logger,
}) {
  return Navigator.of(context).push<void>(
    buildDriverKpiPageRoute(
      args: args,
      fetchRides: fetchRides,
      accentColor: accentColor,
      clock: clock,
      logger: logger,
    ),
  );
}

class DriverKpiController extends ChangeNotifier {
  DriverKpiController({
    required DriverKpiRidesFetcher fetchRides,
    required this.authMode,
    required String driverKey,
    required this.hasDriver,
    DateTime Function()? clock,
    void Function(String message)? logger,
    DriverKpiPeriod initialPeriod = DriverKpiPeriod.today,
  }) : _fetchRides = fetchRides,
       _driverKey = driverKey.trim(),
       _clock = clock ?? DateTime.now,
       _logger = logger ?? _defaultLogger,
       _period = initialPeriod;

  final DriverKpiRidesFetcher _fetchRides;
  final DateTime Function() _clock;
  final void Function(String message) _logger;

  DriverKpiAuthMode authMode;
  bool hasDriver;
  String _driverKey;

  DriverKpiPeriod _period;
  DriverKpiViewState _state = DriverKpiViewState.idle;
  DriverKpiSnapshot? _snapshot;
  String? _errorReason;
  int _generation = 0;

  /// Raw canonical rides per "driverKey|period", so switching periods (or back
  /// to a previous driver) can render instantly, then refresh.
  final Map<String, List<DriverKpiRideRecord>> _cache = {};

  DriverKpiPeriod get period => _period;
  DriverKpiViewState get state => _state;
  DriverKpiSnapshot? get snapshot => _snapshot;
  String? get errorReason => _errorReason;
  String get driverKey => _driverKey;

  static void _defaultLogger(String message) => debugPrint(message);

  String _cacheKey(String driverKey, DriverKpiPeriod period) =>
      '$driverKey|${driverKpiPeriodToken(period)}';

  void _log({
    required String phase,
    String? reason,
    int? ridesCount,
    String paymentMix = '-',
  }) {
    _logger(
      '[DRIVER_KPI] phase=$phase '
      'authMode=${driverKpiAuthModeToken(authMode)} '
      'period=${driverKpiPeriodToken(_period)} '
      'hasDriver=$hasDriver '
      'ridesCount=${ridesCount ?? '-'} '
      'paymentState=$paymentMix '
      'reason=${reason ?? '-'}',
    );
  }

  /// Called when the page opens. Shows cache instantly (if any) then refreshes.
  Future<void> open() => _load(reason: 'open', allowCache: true);

  Future<void> refresh() => _load(reason: 'manual_refresh', allowCache: false);

  Future<void> setPeriod(DriverKpiPeriod period) {
    if (period == _period && _state != DriverKpiViewState.error) {
      return Future<void>.value();
    }
    _period = period;
    return _load(reason: 'period_change', allowCache: true);
  }

  /// Switches to a different effective driver. Old data is cleared immediately
  /// so numbers from the previous driver can never linger on screen.
  Future<void> setDriver({
    required String driverKey,
    required bool hasDriver,
    DriverKpiAuthMode? authMode,
  }) {
    final normalized = driverKey.trim();
    if (normalized == _driverKey && hasDriver == this.hasDriver) {
      return Future<void>.value();
    }
    _driverKey = normalized;
    this.hasDriver = hasDriver;
    if (authMode != null) this.authMode = authMode;
    // Invalidate any in-flight fetch and wipe visible data at once.
    _generation++;
    _snapshot = null;
    _errorReason = null;
    _state = DriverKpiViewState.loading;
    notifyListeners();
    return _load(reason: 'driver_change', allowCache: true);
  }

  Future<void> _load({required String reason, required bool allowCache}) async {
    if (!hasDriver || _driverKey.isEmpty) {
      _snapshot = DriverKpiSnapshot.emptyToday;
      _state = DriverKpiViewState.empty;
      _errorReason = 'no_driver';
      _log(phase: 'loaded', reason: 'no_driver', ridesCount: 0);
      notifyListeners();
      return;
    }

    final gen = ++_generation;
    final driverAtStart = _driverKey;
    final periodAtStart = _period;

    final cached = allowCache ? _cache[_cacheKey(driverAtStart, periodAtStart)] : null;
    if (cached != null) {
      _applyRides(cached, periodAtStart);
    } else if (_state != DriverKpiViewState.loaded) {
      _state = DriverKpiViewState.loading;
      _snapshot = null;
      _errorReason = null;
      notifyListeners();
    }

    _log(phase: 'load', reason: reason);

    List<DriverKpiRideRecord> rides;
    try {
      rides = await _fetchRides(periodAtStart);
    } catch (error) {
      if (gen != _generation || driverAtStart != _driverKey) {
        _log(phase: 'stale_ignored', reason: 'error_after_switch');
        return;
      }
      _state = DriverKpiViewState.error;
      _errorReason = 'network';
      notifyListeners();
      _log(phase: 'error', reason: 'fetch_failed');
      return;
    }

    if (gen != _generation || driverAtStart != _driverKey) {
      _log(phase: 'stale_ignored', reason: 'loaded_after_switch');
      return;
    }

    _cache[_cacheKey(driverAtStart, periodAtStart)] = rides;
    _applyRides(rides, periodAtStart);
    final snap = _snapshot;
    _log(
      phase: 'loaded',
      reason: reason,
      ridesCount: snap?.ridesCount ?? 0,
      paymentMix: snap != null ? driverKpiPaymentMixToken(snap) : '-',
    );
  }

  void _applyRides(List<DriverKpiRideRecord> rides, DriverKpiPeriod period) {
    if (rides.isEmpty) {
      _snapshot = aggregateDriverKpi(
        rides: const [],
        period: period,
        now: _clock(),
      );
      _state = DriverKpiViewState.empty;
      _errorReason = null;
      notifyListeners();
      return;
    }
    _snapshot = aggregateDriverKpi(rides: rides, period: period, now: _clock());
    _state = DriverKpiViewState.loaded;
    _errorReason = null;
    notifyListeners();
  }
}

class DriverKpiPage extends StatefulWidget {
  const DriverKpiPage({
    super.key,
    required this.fetchRides,
    required this.authMode,
    required this.driverKey,
    required this.hasDriver,
    this.accentColor = const Color(0xFFF5C400),
    this.clock,
    this.logger,
  });

  final DriverKpiRidesFetcher fetchRides;
  final DriverKpiAuthMode authMode;
  final String driverKey;
  final bool hasDriver;
  final Color accentColor;
  final DateTime Function()? clock;
  final void Function(String message)? logger;

  @override
  State<DriverKpiPage> createState() => _DriverKpiPageState();
}

class _DriverKpiPageState extends State<DriverKpiPage> {
  late final DriverKpiController _controller;

  static const Color _bg = Color(0xFF0D0E11);
  static const Color _surface = Color(0xFF17181C);
  static const Color _border = Color(0x1FFFFFFF);
  static const Color _textPrimary = Colors.white;
  static const Color _textMuted = Color(0xB3FFFFFF);

  @override
  void initState() {
    super.initState();
    _controller = DriverKpiController(
      fetchRides: widget.fetchRides,
      authMode: widget.authMode,
      driverKey: widget.driverKey,
      hasDriver: widget.hasDriver,
      clock: widget.clock,
      logger: widget.logger,
    );
    _controller.open();
  }

  @override
  void didUpdateWidget(covariant DriverKpiPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.driverKey != widget.driverKey ||
        oldWidget.hasDriver != widget.hasDriver) {
      _controller.setDriver(
        driverKey: widget.driverKey,
        hasDriver: widget.hasDriver,
        authMode: widget.authMode,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _tr({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) {
    switch (appConfig.currentLanguage) {
      case AppLanguage.en:
        return en;
      case AppLanguage.fr:
        return fr;
      case AppLanguage.es:
        return es;
      case AppLanguage.nl:
        return nl;
    case AppLanguage.de:
      return en;
    }
  }

  String _title() => _tr(
    nl: 'Mijn prestaties',
    en: 'My performance',
    fr: 'Mes performances',
    es: 'Mi rendimiento',
  );

  String _periodLabel(DriverKpiPeriod period) {
    switch (period) {
      case DriverKpiPeriod.today:
        return _tr(nl: 'Vandaag', en: 'Today', fr: "Aujourd'hui", es: 'Hoy');
      case DriverKpiPeriod.week:
        return _tr(
          nl: 'Deze week',
          en: 'This week',
          fr: 'Cette semaine',
          es: 'Esta semana',
        );
      case DriverKpiPeriod.month:
        return _tr(
          nl: 'Deze maand',
          en: 'This month',
          fr: 'Ce mois',
          es: 'Este mes',
        );
    }
  }

  String _euro(double amount) => '€ ${amount.toStringAsFixed(2)}';

  String _km(double km) => '${km.toStringAsFixed(1)} km';

  String _duration(Duration? duration) {
    if (duration == null) return '—';
    final totalMinutes = duration.inMinutes;
    if (totalMinutes < 60) {
      return _tr(
        nl: '$totalMinutes min',
        en: '$totalMinutes min',
        fr: '$totalMinutes min',
        es: '$totalMinutes min',
      );
    }
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    return '${hours}h ${minutes.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) {
        return Scaffold(
          backgroundColor: _bg,
          appBar: AppBar(
            backgroundColor: _bg,
            elevation: 0,
            iconTheme: const IconThemeData(color: _textPrimary),
            title: Text(
              _title(),
              style: const TextStyle(
                color: _textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            actions: [
              AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final busy = _controller.state == DriverKpiViewState.loading;
                  return IconButton(
                    tooltip: _tr(
                      nl: 'Vernieuwen',
                      en: 'Refresh',
                      fr: 'Actualiser',
                      es: 'Actualizar',
                    ),
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: busy ? null : () => _controller.refresh(),
                  );
                },
              ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => _buildBody(context),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context) {
    return Column(
      children: [
        _buildPeriodSelector(),
        Expanded(child: _buildContent(context)),
      ],
    );
  }

  Widget _buildPeriodSelector() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: [
          for (final period in DriverKpiPeriod.values) ...[
            Expanded(child: _periodChip(period)),
            if (period != DriverKpiPeriod.values.last)
              const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _periodChip(DriverKpiPeriod period) {
    final selected = _controller.period == period;
    return Semantics(
      button: true,
      selected: selected,
      label: _periodLabel(period),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _controller.setPeriod(period),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? widget.accentColor.withOpacity(0.18)
                : _surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? widget.accentColor : _border,
              width: selected ? 1.4 : 1.0,
            ),
          ),
          child: Text(
            _periodLabel(period),
            style: TextStyle(
              color: selected ? widget.accentColor : _textMuted,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    switch (_controller.state) {
      case DriverKpiViewState.idle:
      case DriverKpiViewState.loading:
        return _buildLoading();
      case DriverKpiViewState.error:
        return _buildError();
      case DriverKpiViewState.empty:
        if (_controller.errorReason == 'no_driver') return _buildNoDriver();
        return _buildEmpty();
      case DriverKpiViewState.loaded:
        return _buildLoaded(context, _controller.snapshot!);
    }
  }

  Widget _buildLoading() {
    return Center(
      child: CircularProgressIndicator(color: widget.accentColor),
    );
  }

  Widget _buildCenteredCard({
    required IconData icon,
    required String title,
    String? message,
    Widget? action,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: _textMuted, size: 48),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _textMuted, fontSize: 13),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 20), action],
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return _buildCenteredCard(
      icon: Icons.cloud_off_rounded,
      title: _tr(
        nl: 'Kon prestaties niet laden',
        en: 'Could not load performance',
        fr: 'Impossible de charger les performances',
        es: 'No se pudieron cargar los datos',
      ),
      message: _tr(
        nl: 'Controleer je verbinding en probeer opnieuw.',
        en: 'Check your connection and try again.',
        fr: 'Vérifiez votre connexion et réessayez.',
        es: 'Comprueba tu conexión e inténtalo de nuevo.',
      ),
      action: OutlinedButton.icon(
        onPressed: () => _controller.refresh(),
        icon: const Icon(Icons.refresh_rounded),
        label: Text(
          _tr(nl: 'Opnieuw', en: 'Retry', fr: 'Réessayer', es: 'Reintentar'),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: widget.accentColor,
          side: BorderSide(color: widget.accentColor),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return _buildCenteredCard(
      icon: Icons.insights_rounded,
      title: _tr(
        nl: 'Nog geen ritten',
        en: 'No rides yet',
        fr: 'Aucune course',
        es: 'Sin viajes aún',
      ),
      message: _tr(
        nl: 'Zodra je ritten rijdt, verschijnen je prestaties hier.',
        en: 'Once you complete rides, your performance appears here.',
        fr: 'Dès que vous effectuez des courses, vos performances apparaîtront ici.',
        es: 'Cuando completes viajes, tu rendimiento aparecerá aquí.',
      ),
    );
  }

  Widget _buildNoDriver() {
    return _buildCenteredCard(
      icon: Icons.person_off_rounded,
      title: _tr(
        nl: 'Geen chauffeur geselecteerd',
        en: 'No driver selected',
        fr: 'Aucun chauffeur sélectionné',
        es: 'Ningún conductor seleccionado',
      ),
      message: _tr(
        nl: 'Selecteer eerst een chauffeur om prestaties te tonen.',
        en: 'Select a driver first to show performance.',
        fr: "Sélectionnez d'abord un chauffeur.",
        es: 'Selecciona primero un conductor.',
      ),
    );
  }

  Widget _buildLoaded(BuildContext context, DriverKpiSnapshot snapshot) {
    final info = FluxidiResponsiveInfo.of(context);
    final columns = info.isTabletUp ? (info.isLandscape ? 4 : 3) : 2;

    return RefreshIndicator(
      color: widget.accentColor,
      backgroundColor: _surface,
      onRefresh: () => _controller.refresh(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          _sectionTitle(
            _tr(nl: 'Ritten', en: 'Rides', fr: 'Courses', es: 'Viajes'),
          ),
          _kpiGrid(columns, [
            _KpiTileData(
              label: _tr(
                nl: 'Ritten',
                en: 'Rides',
                fr: 'Courses',
                es: 'Viajes',
              ),
              value: '${snapshot.ridesCount}',
              icon: Icons.route_rounded,
            ),
            _KpiTileData(
              label: _tr(
                nl: 'Afgerond',
                en: 'Completed',
                fr: 'Terminées',
                es: 'Completados',
              ),
              value: '${snapshot.completedCount}',
              icon: Icons.check_circle_outline_rounded,
            ),
            _KpiTileData(
              label: _tr(
                nl: 'Geannuleerd',
                en: 'Cancelled',
                fr: 'Annulées',
                es: 'Cancelados',
              ),
              value: '${snapshot.cancelledCount}',
              icon: Icons.cancel_outlined,
            ),
          ]),
          const SizedBox(height: 8),
          _sectionTitle(
            _tr(nl: 'Omzet', en: 'Revenue', fr: "Chiffre d'affaires", es: 'Ingresos'),
          ),
          _kpiGrid(columns, [
            _KpiTileData(
              label: _tr(
                nl: 'Totaal',
                en: 'Total',
                fr: 'Total',
                es: 'Total',
              ),
              value: _euro(snapshot.revenueTotal),
              icon: Icons.payments_outlined,
              accent: true,
            ),
            _KpiTileData(
              label: _tr(
                nl: 'Betaald',
                en: 'Paid',
                fr: 'Payé',
                es: 'Pagado',
              ),
              value: _euro(snapshot.paidRevenue),
              icon: Icons.verified_outlined,
            ),
            _KpiTileData(
              label: _tr(
                nl: 'Openstaand',
                en: 'Outstanding',
                fr: 'En attente',
                es: 'Pendiente',
              ),
              value: _euro(snapshot.outstandingRevenue),
              icon: Icons.schedule_rounded,
            ),
            _KpiTileData(
              label: _tr(
                nl: 'Factuur in verwerking',
                en: 'Invoice processing',
                fr: 'Facture en cours',
                es: 'Factura en proceso',
              ),
              value: _euro(snapshot.invoiceInProcessingRevenue),
              icon: Icons.description_outlined,
            ),
          ]),
          const SizedBox(height: 8),
          _sectionTitle(
            _tr(
              nl: 'Gemiddelden',
              en: 'Averages',
              fr: 'Moyennes',
              es: 'Promedios',
            ),
          ),
          _kpiGrid(columns, [
            _KpiTileData(
              label: _tr(
                nl: 'Kilometers',
                en: 'Kilometers',
                fr: 'Kilomètres',
                es: 'Kilómetros',
              ),
              value: _km(snapshot.kmTotal),
              icon: Icons.speed_rounded,
            ),
            _KpiTileData(
              label: _tr(
                nl: 'Gem. ritprijs',
                en: 'Avg. ride price',
                fr: 'Prix moyen',
                es: 'Precio medio',
              ),
              value: snapshot.averageRidePrice == null
                  ? '—'
                  : _euro(snapshot.averageRidePrice!),
              icon: Icons.euro_rounded,
            ),
            _KpiTileData(
              label: _tr(
                nl: 'Gem. ritduur',
                en: 'Avg. ride time',
                fr: 'Durée moyenne',
                es: 'Duración media',
              ),
              value: _duration(snapshot.averageRideDuration),
              icon: Icons.timer_outlined,
            ),
          ]),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Text(
        text,
        style: const TextStyle(
          color: _textMuted,
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _kpiGrid(int columns, List<_KpiTileData> tiles) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final tileWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final tile in tiles)
              SizedBox(width: tileWidth, child: _kpiTile(tile)),
          ],
        );
      },
    );
  }

  Widget _kpiTile(_KpiTileData tile) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: tile.accent ? widget.accentColor.withOpacity(0.55) : _border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            tile.icon,
            size: 20,
            color: tile.accent ? widget.accentColor : _textMuted,
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              tile.value,
              style: TextStyle(
                color: tile.accent ? widget.accentColor : _textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            tile.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _KpiTileData {
  const _KpiTileData({
    required this.label,
    required this.value,
    required this.icon,
    this.accent = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool accent;
}
