import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/airport/airport_catalog_repository.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_route_map.dart';
import 'package:fluxidi_tracking/customer_theme_store.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/company/booking_list_page_repository.dart';
import 'package:fluxidi_tracking/company/company_agenda_calendar.dart';
import 'package:fluxidi_tracking/company/company_agenda_http.dart';
import 'package:fluxidi_tracking/company/company_agenda_labels.dart';
import 'package:fluxidi_tracking/company/company_agenda_prefs.dart';
import 'package:fluxidi_tracking/company/company_agenda_models.dart';
import 'package:fluxidi_tracking/company/company_booking_detail_page.dart';
import 'package:fluxidi_tracking/company/company_ops_api.dart';
import 'package:fluxidi_tracking/company/company_customer_ground.dart';
import 'package:fluxidi_tracking/company/company_customer_dossier.dart';
import 'package:fluxidi_tracking/company/company_customer_form_page.dart';
import 'package:fluxidi_tracking/company/company_customer_import_page.dart';
import 'package:fluxidi_tracking/company/company_customer_import_session_core.dart';
import 'package:fluxidi_tracking/company/company_customer_labels.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';
import 'package:fluxidi_tracking/company/company_customer_quote_labels.dart';
import 'package:fluxidi_tracking/company/company_customer_quote_page.dart';
import 'package:fluxidi_tracking/company/company_customers_page.dart';
import 'package:fluxidi_tracking/company/company_customers_repository.dart';
import 'package:fluxidi_tracking/company/company_customers_repository_factory.dart'
    if (dart.library.html) 'package:fluxidi_tracking/company/company_customers_repository_factory_web.dart'
    as customer_ops_factory;
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_company_vehicles.dart';
import 'package:fluxidi_tracking/nearby/public_partner_market.dart';
import 'package:fluxidi_tracking/company/company_address_field.dart';
import 'package:fluxidi_tracking/company/company_assignment_choice_field.dart';
import 'package:fluxidi_tracking/company/company_driver_agenda_color_chips.dart';
import 'package:fluxidi_tracking/company/company_driver_agenda_style.dart';
import 'package:fluxidi_tracking/company/company_drivers_now.dart';
import 'package:fluxidi_tracking/company/company_driver_schedule.dart';
import 'package:fluxidi_tracking/company/company_driver_schedule_page.dart';
import 'package:fluxidi_tracking/company/company_timezone.dart';
import 'package:fluxidi_tracking/company/company_form_date_time.dart';
import 'package:fluxidi_tracking/company/company_ops_theme.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_field.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';
import 'package:fluxidi_tracking/company/company_fixed_price_breakdown.dart';
import 'package:fluxidi_tracking/company/company_ops_identity.dart';
import 'package:fluxidi_tracking/company/company_crew_combo.dart';
import 'package:fluxidi_tracking/company/company_plan_media.dart';
import 'package:fluxidi_tracking/company/company_plan_presence.dart';
import 'package:fluxidi_tracking/company/company_plan_quote.dart';
import 'package:fluxidi_tracking/company/company_plan_waypoints.dart';
import 'package:fluxidi_tracking/company/company_plan_ride_form.dart';
import 'package:fluxidi_tracking/company/company_plan_ride_layout.dart';
import 'package:fluxidi_tracking/company/company_plan_route_map.dart';
import 'package:fluxidi_tracking/company/company_plan_vehicle_type.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_vehicle_cards.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_vehicle_offers.dart';
import 'package:fluxidi_tracking/company/company_plan_when.dart';
import 'package:fluxidi_tracking/company/company_trip_route.dart';
import 'package:fluxidi_tracking/company/company_rate_card_hint.dart';
import 'package:fluxidi_tracking/company/company_ride_options.dart';
import 'package:fluxidi_tracking/company/company_ride_options_form.dart';
import 'package:fluxidi_tracking/company/company_trip_route_fields.dart';
import 'package:fluxidi_tracking/company/company_roundtrip.dart';
import 'package:fluxidi_tracking/company/company_roundtrip_fields.dart';
import 'package:fluxidi_tracking/company/local_synthetic_company_session.dart';
import 'package:fluxidi_tracking/company_session_store.dart';

const Key kCompanyOpsWorkspacePageKey = Key('company_ops_workspace_page');
const Key kCompanyOpsPlannerWorkspaceKey = Key('company_ops_planner_workspace');
const Key kCompanyAgendaPhoneNavKey = Key('company_agenda_phone_nav');
const Key kCompanyAgendaPaneKey = Key('company_agenda_pane');
const Key kCompanyAgendaDayKey = Key('company_agenda_day');
const Key kCompanyAgendaWeekKey = Key('company_agenda_week');
const Key kCompanyAgendaTodayKey = Key('company_agenda_today');
const Key kCompanyAgendaPlanRideKey = Key('company_agenda_plan_ride');
const Key kCompanyAgendaPlanCloseKey = Key('company_agenda_plan_close');
const Key kCompanyAgendaSaveRideKey = Key('company_agenda_save_ride');
const Key kCompanyAgendaCancelRideKey = Key('company_agenda_cancel_ride');
const Key kCompanyAgendaRideFormKey = Key('company_agenda_ride_form');
const Key kCompanyAgendaFromFieldKey = Key('company_agenda_from');
const Key kCompanyAgendaToFieldKey = Key('company_agenda_to');
const Key kCompanyAgendaPlanDriverKey = Key('company_agenda_plan_driver');
const Key kCompanyAgendaPlanVehicleKey = Key('company_agenda_plan_vehicle');
const Key kCompanyAgendaPlanChoicesStatusKey = Key(
  'company_agenda_plan_choices_status',
);
const Key kCompanyAgendaSwitchCompanyKey = Key('company_agenda_switch_company');
const Key kCompanyAgendaPrevPeriodKey = Key('company_agenda_prev_period');
const Key kCompanyAgendaNextPeriodKey = Key('company_agenda_next_period');
const Key kCompanyAgendaToggleCustomersKey = Key(
  'company_agenda_toggle_customers',
);
const Key kCompanyAgendaToggleDossierKey = Key('company_agenda_toggle_dossier');
const Key kCompanyAgendaNavGroupKey = Key('company_agenda_nav_group');
const Key kCompanyAgendaPickDateKey = Key('company_agenda_pick_date');
const Key kCompanyAgendaPeriodLabelKey = Key('company_agenda_period_label');
const Key kCompanyAgendaViewGroupKey = Key('company_agenda_view_group');
const Key kCompanyAgendaDensityGroupKey = Key('company_agenda_density_group');
const Key kCompanyCustomerDossierEmptyHintKey = Key(
  'company_customer_dossier_empty_hint',
);
const double kCompanyOpsWorkspaceDesktopWidth = 1100;
const double kCompanyOpsWorkspaceTabletPinListWidth = 1000;
const double kCompanyOpsWorkspaceTabletWidth = 720;
const double kCompanyOpsWorkspaceCustomerPaneWidth = 280;
const double kCompanyOpsWorkspaceDossierPaneWidth = 360;
const double kCompanyOpsWorkspaceCollapsedRailWidth = 44;

enum _WorkspacePhoneSurface { customers, agenda, detail, form }

enum _AgendaChrome { desktop, tablet, phone }

class CompanyOpsWorkspacePage extends StatefulWidget {
  const CompanyOpsWorkspacePage({
    super.key,
    this.customersRepository,
    this.agendaRepository,
    this.driversLoader,
    this.vehiclesLoader,
    this.bookingDetailLoader,
    this.language,
    this.issuerName,
    this.sessionStore,
    this.onOpenBooking,
    this.initialAnchor,
    this.planQuoteTransport,
    this.plannerOnly = true,
    this.initialCustomer,
  });

  final CompanyCustomersRepository? customersRepository;
  final CompanyAgendaRepository? agendaRepository;
  final Future<List<Map<String, dynamic>>> Function()? driversLoader;
  final Future<List<Map<String, dynamic>>> Function()? vehiclesLoader;
  final Future<Map<String, dynamic>> Function(String bookingId)?
  bookingDetailLoader;
  final AppLanguage? language;
  final String? issuerName;
  final CompanyCustomerImportSessionStore? sessionStore;
  final void Function(String bookingId)? onOpenBooking;
  final DateTime? initialAnchor;
  final CompanyPlanQuoteTransport? planQuoteTransport;
  final bool plannerOnly;
  final CompanyCustomer? initialCustomer;

  @override
  State<CompanyOpsWorkspacePage> createState() =>
      CompanyOpsWorkspacePageState();
}

class CompanyOpsWorkspacePageState extends State<CompanyOpsWorkspacePage> {
  late final CompanyCustomersRepository _customers;
  late final CompanyAgendaRepository _agenda;
  final TextEditingController _search = TextEditingController();
  Timer? _searchDebounce;

  bool _loadingCustomers = true;
  bool _loadingMoreCustomers = false;
  bool _hasMoreCustomers = false;
  String? _customerCursor;
  bool _loadingAgenda = false;
  String _query = '';
  String? _customerError;
  String? _agendaError;
  final List<CompanyCustomerListItem> _items = <CompanyCustomerListItem>[];
  CompanyCustomer? _selected;
  CompanyRidePlanDraft? _draft;
  bool _saving = false;
  String? _formError;
  CompanyAgendaView _view = CompanyAgendaView.week;
  CompanyAgendaHourDensity _hourDensity = CompanyAgendaHourDensity.compact;
  bool _driversNowExpanded = true;
  bool _userPickedView = false;
  bool _appliedPortraitDefault = false;
  bool _tabletCustomersOpen = false;
  bool _tabletDossierOpen = false;
  late DateTime _anchor;
  int _quotesRevision = 0;
  bool _customersCollapsed = false;
  bool _dossierCollapsed = false;
  List<CompanyAgendaRide> _rides = const <CompanyAgendaRide>[];
  List<CompanyAgendaRide> _linkedRides = const <CompanyAgendaRide>[];
  List<CompanyAgendaRide> _nowRides = const <CompanyAgendaRide>[];
  List<Map<String, dynamic>> _drivers = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _vehicles = const <Map<String, dynamic>>[];
  bool _limousineOffered = true;
  Set<String> _limousineVehicleIds = const <String>{};
  bool _fleetLoading = true;
  String? _fleetError;
  String _planDriverId = '';
  String _planVehicleId = '';
  String? _planOverlapPreview;
  String? _driverFilter;
  String? _boundCompanyId;
  _WorkspacePhoneSurface _phoneSurface = _WorkspacePhoneSurface.agenda;

  late final LimousinePlaceLookup _placeLookup;
  late final LimousineAddressFieldController _fromAddress;
  late final LimousineAddressFieldController _toAddress;
  late final LimousineAddressFieldController _returnFromAddress;
  late final LimousineAddressFieldController _returnToAddress;
  late final CompanyPlanStopList _outboundStops;
  late final CompanyPlanStopList _returnStops;
  final TextEditingController _priceCtrl = TextEditingController();
  final TextEditingController _durationCtrl = TextEditingController();
  final TextEditingController _returnDurationCtrl = TextEditingController();
  bool _preferSameCrew = true;
  final TextEditingController _noteCtrl = TextEditingController();
  int _passengers = 1;
  CompanyRideOptions _rideOptions = const CompanyRideOptions();
  Map<String, dynamic>? _fixedPriceSnapshot;
  late final CompanyPlanQuoteCoordinator _planQuote;
  Timer? _planQuoteDebounce;
  CompanyPlanQuoteResult? _planQuoteResult;
  bool _planQuoteLoading = false;
  String? _planQuoteError;
  bool _manualPriceLocked = false;
  CompanyRoundtripChoice _roundtripChoice = CompanyRoundtripChoice.single;
  DateTime? _agendaMoment;
  DateTime? _planPickupLocal;
  DateTime? _returnPickupLocal;
  String _planReturnDriverId = '';
  String _planReturnVehicleId = '';
  bool _agendaIncomplete = false;
  bool _planWhenNow = true;
  DateTime? _planLaterConceptLocal;
  CompanyPlanVehicleCategory _planVehicleCategory =
      CompanyPlanVehicleCategory.sedan;
  bool _planDriverUserPicked = false;
  bool _planVehicleUserPicked = false;

  AppLanguage get _lang => widget.language ?? appLanguageNotifier.value;

  CompanyAgendaPeriod get _period =>
      companyAgendaPeriodFor(view: _view, anchorLocal: _anchor);

  CompanyAgendaPeriod get _nowPeriod {
    final now = DateTime.now();
    return CompanyAgendaPeriod(
      view: CompanyAgendaView.day,
      anchor: now,
      fromUtc: now.subtract(const Duration(hours: 12)).toUtc(),
      toUtc: now.add(const Duration(hours: 36)).toUtc(),
    );
  }

  @override
  void initState() {
    super.initState();
    _anchor = widget.initialAnchor ?? DateTime.now();
    _placeLookup = LimousinePlaceLookup(country: '');
    _fromAddress = LimousineAddressFieldController(
      lookup: _placeLookup,
      fieldId: 'agenda_from',
      language: _lang.name,
    );
    _toAddress = LimousineAddressFieldController(
      lookup: _placeLookup,
      fieldId: 'agenda_to',
      language: _lang.name,
    );
    _returnFromAddress = LimousineAddressFieldController(
      lookup: _placeLookup,
      fieldId: 'agenda_return_from',
      language: _lang.name,
    );
    _returnToAddress = LimousineAddressFieldController(
      lookup: _placeLookup,
      fieldId: 'agenda_return_to',
      language: _lang.name,
    );
    _outboundStops = CompanyPlanStopList(
      lookup: _placeLookup,
      fieldPrefix: 'outbound',
      language: _lang.name,
      onChanged: _onPlanAddressChanged,
    );
    _returnStops = CompanyPlanStopList(
      lookup: _placeLookup,
      fieldPrefix: 'return',
      language: _lang.name,
      onChanged: _onPlanAddressChanged,
    );
    _customers =
        widget.customersRepository ??
        customer_ops_factory.createCompanyCustomersRepository();
    _agenda = widget.agendaRepository ?? CompanyAgendaRepository();
    _boundCompanyId = _agenda.companyId;
    activeCompanySessionNotifier.addListener(_onCompanyScopeChanged);
    companyProfileNotifier.addListener(_onCompanyScopeChanged);
    companyDriverAgendaColorsTick.addListener(_onAgendaColorsChanged);
    _planQuote = CompanyPlanQuoteCoordinator(
      transport: widget.planQuoteTransport ?? fetchCompanyAgendaQuote,
    );
    _durationCtrl.addListener(_onPlanAssignmentInputsChanged);
    _priceCtrl.addListener(_onManualPriceEdited);
    _fromAddress.addListener(_onPlanAddressChanged);
    _toAddress.addListener(_onPlanAddressChanged);
    _returnFromAddress.addListener(_onPlanAddressChanged);
    _returnToAddress.addListener(_onPlanAddressChanged);
    _reloadCustomers();
    _reloadAgenda();
    _reloadFleet();
    unawaited(_restoreAgendaPrefs());
    final initial = widget.initialCustomer;
    if (initial != null && companyCustomerIsSpecified(initial)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_beginPlan(customer: initial));
      });
    }
  }

  void _onPlanAddressChanged() {
    if (!mounted) return;
    setState(() {
      _fixedPriceSnapshot = null;
      _planQuoteResult = null;
      _planQuoteError = null;
    });
    _schedulePlanQuote();
  }

  void _onManualPriceEdited() {
    if (_priceCtrl.text.trim().isNotEmpty) {
      _manualPriceLocked = true;
    }
  }

  void _schedulePlanQuote() {
    _planQuoteDebounce?.cancel();
    if (_draft == null) return;
    _planQuoteDebounce = Timer(kCompanyPlanQuoteDebounce, () {
      unawaited(_refreshPlanQuote());
    });
  }

  Future<void> _refreshPlanQuote({bool force = false}) async {
    final returnTo = _canonicalReturnTo();
    final request = companyPlanQuoteRequestFromAddresses(
      from: _fromAddress.value,
      to: _toAddress.value,
      pickupLocal: _planWhenNow ? null : _planPickupLocal,
      whenNow: _planWhenNow,
      options: _rideOptions,
      passengers: _passengers,
      returnEnabled: _roundtripChoice != CompanyRoundtripChoice.single,
      returnPickupLocal:
          _roundtripChoice == CompanyRoundtripChoice.continuousWait
          ? (_continuousWaitReturnPickup() ??
                (_planWhenNow ? companyPlanNowLocal() : _planPickupLocal))
          : _returnPickupLocal,
      returnFrom: _toAddress.value,
      returnTo: returnTo,
      stops: _outboundStops.values,
      returnStops: _returnStops.values,
    );
    if (request == null) {
      if (!mounted) return;
      setState(() {
        _planQuoteLoading = false;
        if (force) _planQuoteError = null;
      });
      return;
    }
    if (!force &&
        _planQuote.cached?.fingerprint == request.fingerprint &&
        _planQuote.cached != null) {
      if (!mounted) return;
      setState(() {
        _planQuoteResult = _planQuote.cached;
        _planQuoteLoading = false;
        _planQuoteError = null;
      });
      _applyAutomaticDuration(_planQuote.cached);
      return;
    }
    if (force) _planQuote.invalidate();
    if (!mounted) return;
    setState(() {
      _planQuoteLoading = true;
      _planQuoteError = null;
      if (_planQuoteResult?.fingerprint != request.fingerprint) {
        _planQuoteResult = null;
        _fixedPriceSnapshot = null;
      }
    });
    try {
      var result = await _planQuote.quote(request);
      if (!mounted) return;
      if (result.fingerprint != request.fingerprint &&
          !result.fingerprint.startsWith(request.fingerprint)) {
        return;
      }
      if (_roundtripChoice != CompanyRoundtripChoice.single &&
          !result.hasReturnRoute &&
          companyPlanAddressIsQuoteReady(_toAddress.value) &&
          companyPlanAddressIsQuoteReady(returnTo)) {
        final inboundRequest = companyPlanQuoteRequestFromAddresses(
          from: _toAddress.value,
          to: returnTo,
          pickupLocal: _roundtripChoice == CompanyRoundtripChoice.continuousWait
              ? (_continuousWaitReturnPickup() ??
                    (_planWhenNow ? companyPlanNowLocal() : _planPickupLocal))
              : _returnPickupLocal,
          whenNow: false,
          options: _rideOptions.copyWith(waitMin: 0),
          passengers: _passengers,
          stops: _returnStops.values,
        );
        if (inboundRequest != null) {
          final inbound = await _planQuote.quote(inboundRequest);
          if (!mounted) return;
          result = companyPlanMergeLegQuotes(
            outbound: result,
            inbound: inbound,
          );
        }
      }
      setState(() {
        _planQuoteResult = result;
        _planQuoteLoading = false;
        _planQuoteError = null;
        _fixedPriceSnapshot = result.fixedPriceSnapshot;
      });
      _applyAutomaticDuration(result);
      _syncPlanAssignmentProposal();
    } on CompanyAgendaException catch (error) {
      if (!mounted) return;
      final endpointsReady =
          companyPlanAddressIsQuoteReady(_fromAddress.value) &&
          companyPlanAddressIsQuoteReady(_toAddress.value);
      setState(() {
        _planQuoteLoading = false;
        _planQuoteError = !endpointsReady && error.code == 'route_required'
            ? 'route_required'
            : (error.code.trim().isEmpty
                  ? kCompanyAgendaRouteRetry.of(_lang)
                  : error.code);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _planQuoteLoading = false;
        _planQuoteError = kCompanyAgendaRouteRetry.of(_lang);
      });
    }
  }

  void _applyAutomaticDuration(CompanyPlanQuoteResult? result) {
    if (result == null || result.durationMin == null) return;
    final next = '${result.durationMin}';
    if (_durationCtrl.text.trim() != next) {
      _durationCtrl.text = next;
    }
    final returnMin = companyPlanReturnDurationMin(
      choice: _roundtripChoice,
      outboundDurationMin: result.durationMin,
      quotedReturnDurationMin: result.returnDurationMin,
    );
    if (returnMin != null) {
      final text = '$returnMin';
      if (_returnDurationCtrl.text.trim() != text) {
        _returnDurationCtrl.text = text;
      }
    }
  }

  String _compactAddress(LimousineAddressValue value) {
    final text = value.displayText.trim();
    if (text.isEmpty) return '';
    return text.split(',').first.trim();
  }

  LimousineAddressValue _canonicalReturnTo() {
    if (_roundtripChoice == CompanyRoundtripChoice.single) {
      return const LimousineAddressValue();
    }
    if (companyPlanAddressIsQuoteReady(_returnToAddress.value)) {
      return _returnToAddress.value;
    }
    return _fromAddress.value;
  }

  Future<void> _restoreAgendaPrefs() async {
    final density = await loadCompanyAgendaHourDensity();
    if (!mounted) return;
    setState(() => _hourDensity = density);
  }

  Future<void> _setHourDensity(CompanyAgendaHourDensity density) async {
    setState(() => _hourDensity = density);
    await saveCompanyAgendaHourDensity(density);
  }

  void _setView(CompanyAgendaView view) {
    setState(() {
      _userPickedView = true;
      _view = view;
    });
    _reloadAgenda(force: true);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _planQuoteDebounce?.cancel();
    activeCompanySessionNotifier.removeListener(_onCompanyScopeChanged);
    companyProfileNotifier.removeListener(_onCompanyScopeChanged);
    companyDriverAgendaColorsTick.removeListener(_onAgendaColorsChanged);
    _search.dispose();
    _fromAddress.removeListener(_onPlanAddressChanged);
    _toAddress.removeListener(_onPlanAddressChanged);
    _returnFromAddress.removeListener(_onPlanAddressChanged);
    _returnToAddress.removeListener(_onPlanAddressChanged);
    _outboundStops.dispose();
    _returnStops.dispose();
    _fromAddress.dispose();
    _toAddress.dispose();
    _returnFromAddress.dispose();
    _returnToAddress.dispose();
    _placeLookup.dispose();
    _priceCtrl.removeListener(_onManualPriceEdited);
    _priceCtrl.dispose();
    _durationCtrl.removeListener(_onPlanAssignmentInputsChanged);
    _durationCtrl.dispose();
    _returnDurationCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _onCompanyScopeChanged() {
    final companyId = _agenda.companyId;
    if (companyId == _boundCompanyId) return;
    _agenda.clearCompanyScoped();
    _boundCompanyId = companyId;
    _items.clear();
    _hasMoreCustomers = false;
    _customerCursor = null;
    _selected = null;
    _draft = null;
    _rides = const <CompanyAgendaRide>[];
    _nowRides = const <CompanyAgendaRide>[];
    _drivers = const <Map<String, dynamic>>[];
    _vehicles = const <Map<String, dynamic>>[];
    _fleetLoading = true;
    _fleetError = null;
    _planDriverId = '';
    _planVehicleId = '';
    _planDriverUserPicked = false;
    _planVehicleUserPicked = false;
    _planOverlapPreview = null;
    _driverFilter = null;
    _formError = null;
    _phoneSurface = _WorkspacePhoneSurface.customers;
    _reloadCustomers();
    _reloadAgenda(force: true);
    _reloadFleet();
  }

  void _onAgendaColorsChanged() {
    unawaited(_reloadFleet());
  }

  Future<void> _reloadFleet() async {
    final showLoading = _drivers.isEmpty && _vehicles.isEmpty;
    if (showLoading && mounted) {
      setState(() {
        _fleetLoading = true;
        _fleetError = null;
      });
    }
    try {
      final results = await Future.wait<List<Map<String, dynamic>>>([
        (widget.driversLoader ?? fetchCompanyOpsDrivers)(),
        (widget.vehiclesLoader ?? fetchCompanyOpsVehicles)(),
      ]);
      if (!mounted) return;
      setState(() {
        _drivers = results[0];
        _vehicles = results[1];
        _fleetLoading = false;
        _fleetError = null;
      });
      unawaited(_reloadNowRides());
      unawaited(_reloadPublicServiceFlags());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _drivers = const <Map<String, dynamic>>[];
        _vehicles = const <Map<String, dynamic>>[];
        _fleetLoading = false;
        _fleetError = kCompanyAgendaChoicesLoadFailed.of(_lang);
      });
    }
  }

  Future<void> _reloadNowRides({bool force = false}) async {
    try {
      final rides = await _agenda.listPeriod(_nowPeriod, force: force);
      if (!mounted) return;
      setState(() => _nowRides = rides);
    } catch (_) {
      if (!mounted) return;
      setState(() => _nowRides = const <CompanyAgendaRide>[]);
    }
  }

  Future<void> _reloadCustomers() async {
    setState(() {
      _loadingCustomers = true;
      _loadingMoreCustomers = false;
      _customerError = null;
      _hasMoreCustomers = false;
      _customerCursor = null;
    });
    try {
      final page = await _customers.list(status: 'active', query: _query);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _hasMoreCustomers = page.hasMore;
        _customerCursor = page.nextCursor;
        _loadingCustomers = false;
      });
    } on CompanyCustomerException catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingCustomers = false;
        _customerError = companyCustomersExceptionText(error, _lang);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingCustomers = false;
        _customerError = kCompanyCustomersError.of(_lang);
      });
    }
  }

  Future<void> _loadMoreCustomers() async {
    final cursor = (_customerCursor ?? '').trim();
    if (_loadingMoreCustomers || !_hasMoreCustomers || cursor.isEmpty) {
      return;
    }
    setState(() => _loadingMoreCustomers = true);
    try {
      final page = await _customers.list(
        status: 'active',
        query: _query,
        cursor: cursor,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _hasMoreCustomers = page.hasMore;
        _customerCursor = page.nextCursor;
        _loadingMoreCustomers = false;
      });
    } on CompanyCustomerException catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingMoreCustomers = false;
        _customerError = companyCustomersExceptionText(error, _lang);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingMoreCustomers = false;
        _customerError = kCompanyCustomersError.of(_lang);
      });
    }
  }

  Future<void> _reloadAgenda({bool force = false}) async {
    setState(() {
      _loadingAgenda = true;
      _agendaError = null;
    });
    try {
      var rides = await _agenda.listPeriod(_period, force: force);
      if (!force &&
          rides.isEmpty &&
          mounted &&
          widget.agendaRepository == null) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        if (!mounted) return;
        rides = await _agenda.listPeriod(_period, force: true);
      }
      if (!mounted) return;
      setState(() {
        _rides = rides;
        _agendaIncomplete = _agenda.isPeriodIncomplete(_period);
        _loadingAgenda = false;
      });
      unawaited(_reloadLinkedRides(force: force));
      if (force) {
        unawaited(_reloadFleet());
        unawaited(_reloadNowRides(force: true));
      }
    } on CompanyAgendaException catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingAgenda = false;
        _agendaError = error.offline
            ? kCompanyCustomersOffline.of(_lang)
            : kCompanyAgendaError.of(_lang);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingAgenda = false;
        _agendaError = kCompanyAgendaError.of(_lang);
      });
    }
  }

  Future<void> _reloadLinkedRides({bool force = false}) async {
    try {
      final rides = await _agenda.listPeriod(
        companyAgendaLinkedBookingsPeriod(),
        force: force,
      );
      if (!mounted) return;
      setState(() => _linkedRides = rides);
    } catch (_) {
      if (!mounted) return;
      setState(() => _linkedRides = _rides);
    }
  }

  Future<CompanyCustomer?> _loadCustomer(String customerId) async {
    try {
      return await _customers.getById(customerId);
    } on CompanyCustomerException {
      return null;
    }
  }

  Future<void> _selectCustomer(CompanyCustomerListItem item) async {
    final detail = await _loadCustomer(item.customerId);
    if (!mounted) return;
    setState(() {
      _selected = detail;
      _dossierCollapsed = false;
      final width = MediaQuery.sizeOf(context).width;
      final height = MediaQuery.sizeOf(context).height;
      if (width < kCompanyOpsWorkspaceTabletWidth) {
        _phoneSurface = _WorkspacePhoneSurface.detail;
      } else if (width < kCompanyOpsWorkspaceDesktopWidth && height > width) {
        _tabletDossierOpen = true;
      }
    });
  }

  Future<void> _beginPlan({CompanyCustomer? customer, DateTime? pickup}) async {
    final chosen = customer ?? _selected;
    // Reopening the planner must never discard what was already typed. That
    // includes a draft whose customer is still to be picked.
    if (_draft != null && pickup == null) {
      final sameCustomer =
          chosen == null || _draft!.customer.customerId == chosen.customerId;
      if (sameCustomer) {
        setState(() => _phoneSurface = _WorkspacePhoneSurface.form);
        return;
      }
    }
    // Opening the planner without a chosen customer is legitimate: the form
    // shows an empty, searchable customer field. Only an archived customer
    // that was explicitly picked is refused.
    if (chosen != null && chosen.isArchived) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(kCompanyAgendaSelectCustomer.of(_lang))),
      );
      return;
    }
    final selected = chosen ?? const CompanyCustomer.unchosen();
    if (pickup != null) {
      _agendaMoment = pickup;
    }
    final whenNow = pickup == null;
    final when = pickup;
    final preferred = companyCustomerPreferredAddress(selected);
    final home = preferred == null
        ? ''
        : companyCustomerAddressChoiceLabel(preferred);
    setState(() {
      _planWhenNow = whenNow;
      _planLaterConceptLocal = when;
      _planPickupLocal = when;
      _planVehicleCategory = CompanyPlanVehicleCategory.sedan;
      _planDriverUserPicked = false;
      _planVehicleUserPicked = false;
      _draft = CompanyRidePlanDraft(
        customer: selected,
        pickupLocal: when ?? companyPlanNowLocal(),
        whenNow: whenNow,
        fromAddress: home,
        idempotencyKey:
            'agenda-${selected.customerId}-${whenNow ? 'now' : when!.toUtc().toIso8601String()}-${DateTime.now().microsecondsSinceEpoch}',
      );
      _fromAddress.clear();
      _toAddress.clear();
      _returnFromAddress.clear();
      _returnToAddress.clear();
      _outboundStops.clear();
      _returnStops.clear();
      _preferSameCrew = true;
      _priceCtrl.text = '';
      _durationCtrl.text = '';
      _returnDurationCtrl.text = '';
      _planDriverId = '';
      _planVehicleId = '';
      _planReturnDriverId = '';
      _planReturnVehicleId = '';
      _planOverlapPreview = null;
      _passengers = 1;
      _rideOptions = const CompanyRideOptions(
        vehicleType: kCompanyPlanVehicleTypeSedan,
      );
      _fixedPriceSnapshot = null;
      _planQuote.invalidate();
      _planQuoteResult = null;
      _planQuoteError = null;
      _planQuoteLoading = false;
      _manualPriceLocked = false;
      _roundtripChoice = CompanyRoundtripChoice.single;
      _returnPickupLocal = null;
      _noteCtrl.text = '';
      _formError = null;
      // Never make an unchosen placeholder look like a selected customer.
      if (selected.isChosen) _selected = selected;
      _phoneSurface = _WorkspacePhoneSurface.form;
    });
    if (selected.isChosen) {
      companyApplyCustomerGroundAddress(
        customer: selected,
        options: _rideOptions,
        pickup: _fromAddress,
        dropoff: _toAddress,
      );
      unawaited(_geocodeOwnedPlanAddresses());
      return;
    }
    _schedulePlanQuote();
  }

  Future<void> _geocodeOwnedPlanAddresses() async {
    await companyAddressGeocodeIfNeeded(_fromAddress);
    await companyAddressGeocodeIfNeeded(_toAddress);
    if (!mounted) return;
    _schedulePlanQuote();
  }

  void _fillReturnRouteFromOutbound({bool forceReturnTo = false}) {
    if (_toAddress.value.displayText.trim().isNotEmpty) {
      _returnFromAddress.acceptCopy(_toAddress.value);
    }
    if (forceReturnTo || _returnToAddress.value.displayText.trim().isEmpty) {
      if (_fromAddress.value.displayText.trim().isNotEmpty) {
        _returnToAddress.acceptCopy(_fromAddress.value);
      }
    }
  }

  DateTime? _continuousWaitReturnPickup() {
    final duration = _planDurationMin;
    final wait = _rideOptions.waitMin > 0 ? _rideOptions.waitMin : 45;
    final start = _planWhenNow ? companyPlanNowLocal() : _planPickupLocal;
    if (duration == null || start == null) return null;
    return start.add(Duration(minutes: duration + wait));
  }

  void _onRoundtripChoiceChanged(CompanyRoundtripChoice next) {
    final draft = _draft;
    if (draft == null) return;
    setState(() {
      _roundtripChoice = next;
      _draft = draft.copyWith(roundtripChoice: next);
      if (next == CompanyRoundtripChoice.single) {
        _returnPickupLocal = null;
        return;
      }
      _fillReturnRouteFromOutbound(forceReturnTo: true);
      if (next == CompanyRoundtripChoice.continuousWait) {
        if (_rideOptions.waitMin <= 0) {
          _rideOptions = _rideOptions.copyWith(waitMin: 45);
        }
        _returnPickupLocal = _continuousWaitReturnPickup();
        return;
      }
      final pickupAt = _planWhenNow
          ? companyPlanNowLocal()
          : (_planPickupLocal ?? draft.pickupLocal);
      _returnPickupLocal ??= pickupAt.add(const Duration(hours: 3));
    });
    unawaited(_previewPlanOverlap());
    _schedulePlanQuote();
  }

  int get _stepDays => _view == CompanyAgendaView.week ? 7 : 1;

  Future<void> _pickAnchorDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _anchor,
      firstDate: DateTime(_anchor.year - 1),
      lastDate: DateTime(_anchor.year + 2),
      helpText: kCompanyAgendaPickDate.of(_lang),
    );
    if (picked == null || !mounted) return;
    setState(() => _anchor = picked);
    await _reloadAgenda(force: true);
  }

  Future<void> _acceptCustomerOnSlot(
    CompanyCustomerListItem item,
    DateTime pickup,
  ) async {
    final customer = await _loadCustomer(item.customerId);
    if (!mounted || customer == null || customer.isArchived) return;
    await _beginPlan(customer: customer, pickup: pickup);
  }

  Future<void> _acceptRideOnSlot(
    CompanyAgendaRide ride,
    DateTime pickup,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(
          '${kCompanyAgendaRescheduleConfirm.of(_lang)}\n'
          '${pickup.day}/${pickup.month} ${pickup.hour.toString().padLeft(2, '0')}:00',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(kCompanyAgendaCancel.of(_lang)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(kCompanyAgendaReschedule.of(_lang)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _agenda.rescheduleRide(
        bookingId: companyAgendaRideDetailId(ride),
        pickupLocal: pickup,
        revision: ride.revision,
        legId: ride.legId,
        legType: ride.legType,
      );
      await _reloadAgenda(force: true);
    } on CompanyAgendaException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_agendaExceptionText(error))));
    }
  }

  String _agendaExceptionText(CompanyAgendaException error) {
    return companyAgendaAssignmentExceptionText(error, _lang);
  }

  void _onPlanAssignmentInputsChanged() {
    if (_draft == null) return;
    unawaited(_previewPlanOverlap());
  }

  int? get _planDurationMin {
    return companyPlanCanonicalDurationMin(
      quoteDurationMin: _planQuoteResult?.durationMin,
      durationRouteMin:
          _draft?.durationRouteMin ?? _planQuoteResult?.durationMin,
      durationText: _durationCtrl.text,
    );
  }

  bool get _planDurationUnknown => _planDurationMin == null;

  bool get _assignmentBlocked {
    final outbound = companyPlanFindCrewCombo(
      combos: _planCrewCombos,
      driverId: _planDriverId,
      vehicleId: _planVehicleId,
    );
    if (outbound != null && !outbound.suitable) return true;
    final preview = (_planOverlapPreview ?? '').trim();
    if (preview.isEmpty) return false;
    if (preview == kCompanyAgendaAvailabilityUnknown.of(_lang)) {
      return false;
    }
    return true;
  }

  CompanyPlanVehicleType get _planVehicleType {
    return parseCompanyPlanVehicleType(_rideOptions.vehicleType) ??
        companyPlanVehicleTypeForPassengers(_passengers);
  }

  bool get _planAirportMode {
    return companyTripRouteKindIsAirport(companyTripRouteKindOf(_rideOptions));
  }

  List<Map<String, dynamic>> get _planVehicleChoices {
    return companyPlanVehiclesForCategory(
      vehicles: _vehicles,
      category: _planVehicleCategory,
      passengers: _passengers,
    );
  }

  List<CompanyCrewCombo> get _planCrewCombos {
    return _crewCombosForWindow(
      whenNow: _planWhenNow,
      driverId: _planDriverId,
      vehicleId: _planVehicleId,
    );
  }

  List<CompanyCrewCombo> get _planReturnCrewCombos {
    if (_roundtripChoice != CompanyRoundtripChoice.splitNoWait) {
      return _planCrewCombos;
    }
    return _crewCombosForWindow(
      whenNow: false,
      driverId: _planReturnDriverId,
      vehicleId: _planReturnVehicleId,
    );
  }

  List<CompanyCrewCombo> _crewCombosForWindow({
    required bool whenNow,
    required String driverId,
    required String vehicleId,
  }) {
    final pickup = whenNow
        ? companyPlanNowLocal().toUtc()
        : (_planPickupLocal ?? _draft?.pickupLocal)?.toUtc();
    final durationMin = _planDurationMin;
    final raw = companyPlanCrewCombos(
      drivers: _drivers,
      vehicles: _vehicles,
      type: _planVehicleType,
      passengers: _passengers,
      whenNow: whenNow,
      rideStartUtc: pickup,
      rideEndUtc: pickup == null || durationMin == null
          ? pickup
          : pickup.add(Duration(minutes: durationMin)),
      schedules: companyDriverSchedulesFromRecords(_drivers),
    );
    final overlap = (_planOverlapPreview ?? '').trim();
    if (overlap.isEmpty ||
        overlap == kCompanyAgendaAvailabilityUnknown.of(_lang)) {
      return raw;
    }
    return [
      for (final combo in raw)
        if (combo.driverId == driverId && combo.vehicleId == vehicleId)
          companyCrewComboWithPresence(
            combo,
            resolveCompanyPlanPresence(
              driver: combo.driver,
              overlapCode: 'assignment_overlap',
              whenNow: whenNow,
              vehicles: combo.vehicleId.isEmpty
                  ? const <Map<String, dynamic>>[]
                  : [combo.vehicle],
            ),
          )
        else
          combo,
    ];
  }

  bool get _preferSameCrewWindowsChecked {
    return companyPlanCrewComboAvailableOnBoth(
      outbound: _planCrewCombos,
      inbound: _planReturnCrewCombos,
      driverId: _planDriverId,
      vehicleId: _planVehicleId,
    );
  }

  void _syncPlanAssignmentProposal() {
    if (_draft == null) return;
    final combos = _planCrewCombos;
    final next = proposeCompanyPlanCrewAssignment(
      combos: combos,
      userPicked: _planDriverUserPicked || _planVehicleUserPicked,
      currentDriverId: _planDriverId,
      currentVehicleId: _planVehicleId,
    );
    var returnDriver = _planReturnDriverId;
    var returnVehicle = _planReturnVehicleId;
    if (_roundtripChoice == CompanyRoundtripChoice.continuousWait) {
      returnDriver = next.driverId;
      returnVehicle = next.vehicleId;
    } else if (_roundtripChoice == CompanyRoundtripChoice.splitNoWait) {
      final sameOk = companyPlanCrewComboAvailableOnBoth(
        outbound: combos,
        inbound: _planReturnCrewCombos,
        driverId: next.driverId,
        vehicleId: next.vehicleId,
      );
      if (_preferSameCrew && !sameOk && next.driverId.isNotEmpty) {
        _preferSameCrew = false;
      }
      final inbound = proposeCompanyPlanReturnCrew(
        combos: _planReturnCrewCombos,
        outboundDriverId: next.driverId,
        outboundVehicleId: next.vehicleId,
        preferSame: _preferSameCrew && sameOk,
        outboundAvailableForReturn: sameOk,
      );
      if (!_planDriverUserPicked || _planReturnDriverId.isEmpty) {
        returnDriver = inbound.driverId;
        returnVehicle = inbound.vehicleId;
      }
    }
    if (mounted &&
        (next.driverId != _planDriverId ||
            next.vehicleId != _planVehicleId ||
            returnDriver != _planReturnDriverId ||
            returnVehicle != _planReturnVehicleId)) {
      setState(() {
        _planDriverId = next.driverId;
        _planVehicleId = next.vehicleId;
        _planReturnDriverId = returnDriver;
        _planReturnVehicleId = returnVehicle;
      });
    }
    unawaited(_previewPlanOverlap());
  }

  void _setPlanWhenNow(bool now) {
    setState(() {
      if (now) {
        if (!_planWhenNow && _planPickupLocal != null) {
          _planLaterConceptLocal = _planPickupLocal;
        }
        _planWhenNow = true;
        _planPickupLocal = null;
        final draft = _draft;
        if (draft != null) {
          _draft = draft.copyWith(
            whenNow: true,
            idempotencyKey:
                'agenda-${draft.customer.customerId}-now-${DateTime.now().microsecondsSinceEpoch}',
          );
        }
      } else {
        _planWhenNow = false;
        var later = _planLaterConceptLocal;
        if (later != null && !companyPlanLaterPickupIsValid(later)) {
          later = null;
          _planLaterConceptLocal = null;
        }
        _planPickupLocal = later;
        final draft = _draft;
        if (draft != null) {
          _draft = draft.copyWith(
            whenNow: false,
            pickupLocal: later ?? draft.pickupLocal,
            idempotencyKey: later == null
                ? 'agenda-${draft.customer.customerId}-later-${DateTime.now().microsecondsSinceEpoch}'
                : 'agenda-${draft.customer.customerId}-${later.toUtc().toIso8601String()}',
          );
        }
      }
    });
    unawaited(_previewPlanOverlap());
    _schedulePlanQuote();
  }

  void _setPlanVehicleCategory(CompanyPlanVehicleCategory category) {
    _planVehicleCategory = category;
    _setPlanVehicleType(companyPlanVehicleTypeForCategory(category));
    setState(() {
      _rideOptions = _rideOptions.copyWith(
        vehicleType: companyPlanVehicleCategoryWire(category),
      );
    });
  }

  int _clampPlanPassengers(int next) {
    if (_planVehicleId.isEmpty) return next;
    for (final vehicle in _vehicles) {
      if (companyAgendaVehicleId(vehicle) != _planVehicleId) continue;
      final seats = companyAgendaVehiclePassengerSeats(vehicle);
      if (seats != null && seats > 0 && next > seats) return seats;
    }
    return next;
  }

  List<Map<String, dynamic>> get _planOfferVehicles {
    return customerBookingFilterVehiclesForEnabledServices(
      vehicles: _vehicles,
      limousineOffered: _limousineOffered,
      limousineVehicleIds: _limousineVehicleIds,
    );
  }

  Future<void> _reloadPublicServiceFlags() async {
    final companyId =
        (_boundCompanyId ?? companyOpsIdentityNotifier.value.companyId).trim();
    if (companyId.isEmpty) return;
    try {
      final snapshot = await fetchCustomerBookingCompanySnapshot(
        bookingBaseUrl: kBookingBaseUrl,
        partnerId: 'company:$companyId:$companyId',
      );
      if (!mounted) return;
      setState(() {
        _limousineOffered = snapshot.limousineOffered;
        _limousineVehicleIds = publicPartnerLimousineAssignedVehicleIds(
          snapshot.profile,
        );
        if (_planVehicleId.isNotEmpty &&
            !_planOfferVehicles.any(
              (vehicle) => companyAgendaVehicleId(vehicle) == _planVehicleId,
            )) {
          _planVehicleId = '';
          _planVehicleUserPicked = false;
        }
      });
    } catch (_) {}
  }

  Widget? _planVehicleOfferCards() {
    final offers = customerBookingVehicleOffers(
      vehicles: _planOfferVehicles,
      drivers: _drivers,
      passengers: _passengers,
      pickupUtc: (_planWhenNow ? companyPlanNowLocal() : _planPickupLocal)
          ?.toUtc(),
      durationMin: _planDurationMin ?? 30,
    );
    if (offers.isEmpty) return null;
    return CustomerBookingVehiclePhotoCardGrid(
      offers: offers,
      language: _lang,
      selectedVehicleId: _planVehicleId,
      cardKeyFor: companyAgendaVehicleOfferKey,
      onSelected: (offer) {
        final category = classifyCompanyPlanVehicleCategory(offer.vehicle);
        final seats = offer.passengerSeats;
        setState(() {
          _planVehicleId = offer.vehicleId;
          _planVehicleUserPicked = true;
          if (offer.driverId.isNotEmpty) {
            _planDriverId = offer.driverId;
            _planDriverUserPicked = true;
          }
          if (category != null) {
            _planVehicleCategory = category;
            _rideOptions = _rideOptions.copyWith(
              vehicleType: companyPlanVehicleCategoryWire(category),
            );
          }
          if (seats != null && seats > 0 && _passengers > seats) {
            _passengers = seats;
          }
        });
        _syncPlanAssignmentProposal();
        _schedulePlanQuote();
      },
    );
  }

  void _setPlanVehicleType(CompanyPlanVehicleType type) {
    var passengers = _passengers;
    if (type == CompanyPlanVehicleType.sedan &&
        passengers > kCompanyPlanSedanMaxPassengers) {
      passengers = kCompanyPlanSedanMaxPassengers;
    }
    setState(() {
      _passengers = passengers;
      _rideOptions = _rideOptions.copyWith(
        vehicleType: companyPlanVehicleTypeWire(type),
      );
      _planVehicleUserPicked = false;
    });
    _syncPlanAssignmentProposal();
    _schedulePlanQuote();
  }

  void _setPlanAirportMode(bool enabled) {
    final current = companyTripRouteKindOf(_rideOptions);
    final next = enabled
        ? (companyTripRouteKindIsAirport(current)
              ? current
              : CompanyTripRouteKind.toAirport)
        : CompanyTripRouteKind.address;
    setState(() {
      _rideOptions = companyTripRouteOptionsForKind(
        current: _rideOptions,
        kind: next,
      ).copyWith(vehicleType: _rideOptions.vehicleType);
      _fixedPriceSnapshot = null;
      _planQuoteResult = null;
      if (enabled) {
        if (next == CompanyTripRouteKind.toAirport) {
          _toAddress.clear();
        } else if (next == CompanyTripRouteKind.fromAirport) {
          _fromAddress.clear();
        }
      } else {
        final iata = current == CompanyTripRouteKind.address
            ? ''
            : _rideOptions.airportIata;
        final airport = iata.trim().isEmpty ? null : airportByIata(iata);
        if (airport != null) {
          if (companyTripAddressIsAirport(_fromAddress.value, airport)) {
            _fromAddress.clear();
          }
          if (companyTripAddressIsAirport(_toAddress.value, airport)) {
            _toAddress.clear();
          }
        }
      }
    });
    _schedulePlanQuote();
  }

  Future<void> _applyPlanCustomerItem(CompanyCustomerListItem item) async {
    final detail = await _loadCustomer(item.customerId);
    if (!mounted || detail == null || detail.isArchived) return;
    _applyPlanCustomer(detail);
  }

  void _applyPlanCustomer(CompanyCustomer customer) {
    final draft = _draft;
    setState(() {
      _selected = customer;
      if (draft != null) {
        _draft = draft.copyWith(customer: customer);
        companyApplyCustomerGroundAddress(
          customer: customer,
          options: _rideOptions,
          pickup: _fromAddress,
          dropoff: _toAddress,
        );
      }
    });
    unawaited(_geocodeOwnedPlanAddresses());
  }

  Future<void> _addPlanCustomer() async {
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute<Object?>(
        builder: (_) =>
            CompanyCustomerFormPage(repository: _customers, language: _lang),
      ),
    );
    if (!mounted) return;
    if (result is CompanyCustomerMutationResult) {
      await _reloadCustomers();
      _applyPlanCustomer(result.customer);
      return;
    }
    if (result is CompanyCustomer) {
      await _reloadCustomers();
      _applyPlanCustomer(result);
    }
  }

  String? get _planChoicesStatus {
    return companyAgendaAssignmentChoicesStatus(
      language: _lang,
      loading: _fleetLoading,
      error: _fleetError,
      drivers: _drivers,
      vehicles: _vehicles,
      passengers: _passengers,
    );
  }

  Future<void> _previewPlanOverlap() async {
    final draft = _draft;
    final driverId = _planDriverId.trim();
    final vehicleId = _planVehicleId.trim();
    final pickupAt = _planWhenNow ? companyPlanNowLocal() : _planPickupLocal;
    if (draft == null ||
        pickupAt == null ||
        (driverId.isEmpty && vehicleId.isEmpty)) {
      if (mounted) setState(() => _planOverlapPreview = null);
      return;
    }
    final durationUnknown = _planDurationUnknown;
    try {
      final check = await _agenda.checkOverlap(
        driverId: driverId,
        vehicleId: vehicleId,
        pickupIso: pickupAt.toUtc().toIso8601String(),
        durationMin: _planDurationMin,
        returnPickupIso:
            (_roundtripChoice == CompanyRoundtripChoice.continuousWait
                    ? _continuousWaitReturnPickup()
                    : _returnPickupLocal)
                ?.toUtc()
                .toIso8601String() ??
            '',
        returnDurationMin: companyPlanReturnDurationMin(
          choice: _roundtripChoice,
          outboundDurationMin: _planDurationMin,
          quotedReturnDurationMin: _planQuoteResult?.returnDurationMin,
          returnDurationText: _returnDurationCtrl.text,
        ),
        roundtripMode: companyRoundtripChoiceWire(_roundtripChoice),
      );
      if (!mounted || _draft != draft) return;
      var text = companyAgendaAssignmentOverlapText(check, _lang);
      if (durationUnknown) {
        text ??= kCompanyAgendaAvailabilityUnknown.of(_lang);
      }
      setState(() => _planOverlapPreview = text);
    } on CompanyAgendaException catch (error) {
      if (!mounted || _draft != draft) return;
      setState(() => _planOverlapPreview = _agendaExceptionText(error));
    } catch (_) {
      if (!mounted || _draft != draft) return;
      setState(() {
        _planOverlapPreview = durationUnknown
            ? kCompanyAgendaAvailabilityUnknown.of(_lang)
            : null;
      });
    }
  }

  void _cancelDraft() {
    setState(() {
      _draft = null;
      _planPickupLocal = null;
      _planLaterConceptLocal = null;
      _planWhenNow = true;
      _formError = null;
      _planDriverId = '';
      _planVehicleId = '';
      _planDriverUserPicked = false;
      _planVehicleUserPicked = false;
      _planOverlapPreview = null;
      _phoneSurface = _WorkspacePhoneSurface.agenda;
    });
  }

  Future<void> _saveDraft() async {
    final draft = _draft;
    if (draft == null || _saving) return;
    final fromValue = _fromAddress.value;
    final toValue = _toAddress.value;
    final returnFromValue = _toAddress.value;
    final returnToValue = _canonicalReturnTo();
    final from = fromValue.displayText.trim();
    final to = toValue.displayText.trim();
    // The customer is validated here, not at open: the planner may be filled
    // in first and the customer picked afterwards. The typed ride data stays.
    if (!draft.customer.isChosen) {
      setState(() => _formError = kCompanyAgendaSelectCustomer.of(_lang));
      return;
    }
    if (from.isEmpty || to.isEmpty) {
      setState(() => _formError = kCompanyAgendaRouteRequired.of(_lang));
      return;
    }
    if (_planQuoteResult != null &&
        !companyPlanQuoteSanityCheck(_planQuoteResult!).ok) {
      setState(() => _formError = kCompanyAgendaPriceInvalid.of(_lang));
      return;
    }
    if (!_planWhenNow && _planPickupLocal == null) {
      setState(() => _formError = kCompanyAgendaPickupRequired.of(_lang));
      return;
    }
    if (!_planWhenNow &&
        _planPickupLocal != null &&
        !companyPlanLaterPickupIsValid(_planPickupLocal!)) {
      setState(() => _formError = kCompanyAgendaLaterPickupInvalid.of(_lang));
      return;
    }
    if (_roundtripChoice == CompanyRoundtripChoice.splitNoWait &&
        _returnPickupLocal == null) {
      setState(() => _formError = kCompanyRoundtripReturnRequired.of(_lang));
      return;
    }
    final fromSelected =
        fromValue.acceptance == LimousineAddressAcceptance.selected;
    final toSelected =
        toValue.acceptance == LimousineAddressAcceptance.selected;
    final key =
        draft.idempotencyKey ??
        (_planWhenNow
            ? 'agenda-${draft.customer.customerId}-now-${DateTime.now().microsecondsSinceEpoch}'
            : 'agenda-${draft.customer.customerId}-${_planPickupLocal!.toUtc().toIso8601String()}');
    setState(() {
      _saving = true;
      _formError = null;
    });
    try {
      final filled = draft.copyWith(
        whenNow: _planWhenNow,
        pickupLocal: _planWhenNow ? companyPlanNowLocal() : _planPickupLocal,
        fromAddress: from,
        toAddress: to,
        fromLat: fromValue.lat ?? _planQuoteResult?.pickupLat,
        fromLon: fromValue.lon ?? _planQuoteResult?.pickupLon,
        fromPlaceId: fromSelected ? (fromValue.placeId ?? '') : '',
        toLat: toValue.lat ?? _planQuoteResult?.dropoffLat,
        toLon: toValue.lon ?? _planQuoteResult?.dropoffLon,
        toPlaceId: toSelected ? (toValue.placeId ?? '') : '',
        clearFromCoords:
            fromValue.lat == null && _planQuoteResult?.pickupLat == null,
        clearToCoords:
            toValue.lat == null && _planQuoteResult?.dropoffLat == null,
        stops: _outboundStops.routeTexts,
        returnStops: _returnStops.routeTexts,
        passengers: _passengers,
        priceText: _manualPriceLocked
            ? _priceCtrl.text
            : (_planQuoteResult?.priceAvailable == true
                  ? (_planQuoteResult!.priceInclVat?.toString() ??
                        _priceCtrl.text)
                  : _priceCtrl.text),
        durationText: '${_planDurationMin ?? ''}',
        distanceKm: _planQuoteResult?.distanceKm,
        pricingSource: _manualPriceLocked
            ? 'manual'
            : (_planQuoteResult?.pricingSource ?? ''),
        currency: _planQuoteResult?.currency ?? 'EUR',
        durationRouteMin: _planQuoteResult?.durationMin,
        driverId: _assignmentBlocked ? '' : _planDriverId.trim(),
        vehicleId: _assignmentBlocked ? '' : _planVehicleId.trim(),
        rideOptions: _rideOptions,
        fixedPriceSnapshot: _fixedPriceSnapshot,
        publicNote: _noteCtrl.text,
        idempotencyKey: key,
        roundtripChoice: _roundtripChoice,
        returnPickupLocal:
            _roundtripChoice == CompanyRoundtripChoice.continuousWait
            ? _continuousWaitReturnPickup()
            : _returnPickupLocal,
        returnFromAddress: returnFromValue.displayText.trim(),
        returnToAddress: returnToValue.displayText.trim(),
        returnDurationText:
            companyPlanReturnDurationMin(
              choice: _roundtripChoice,
              outboundDurationMin: _planDurationMin,
              quotedReturnDurationMin: _planQuoteResult?.returnDurationMin,
              returnDurationText: _returnDurationCtrl.text,
            )?.toString() ??
            '',
        returnDriverId: _assignmentBlocked ? '' : _planReturnDriverId,
        returnVehicleId: _assignmentBlocked ? '' : _planReturnVehicleId,
        returnFromLat:
            returnFromValue.acceptance == LimousineAddressAcceptance.selected
            ? returnFromValue.lat
            : null,
        returnFromLon:
            returnFromValue.acceptance == LimousineAddressAcceptance.selected
            ? returnFromValue.lon
            : null,
        returnFromPlaceId:
            returnFromValue.acceptance == LimousineAddressAcceptance.selected
            ? (returnFromValue.placeId ?? '')
            : '',
        returnToLat:
            returnToValue.acceptance == LimousineAddressAcceptance.selected
            ? returnToValue.lat
            : null,
        returnToLon:
            returnToValue.acceptance == LimousineAddressAcceptance.selected
            ? returnToValue.lon
            : null,
        returnToPlaceId:
            returnToValue.acceptance == LimousineAddressAcceptance.selected
            ? (returnToValue.placeId ?? '')
            : '',
        clearReturnCoords:
            returnFromValue.acceptance != LimousineAddressAcceptance.selected &&
            returnToValue.acceptance != LimousineAddressAcceptance.selected,
      );
      final ride = await _agenda.createRide(draft: filled, idempotencyKey: key);
      final scope = _agenda.scope;
      if (scope != null) {
        bookingListPageRepository.invalidateBookingListsForAffectedCompany(
          tenantId: scope['tenant_id'] ?? '',
          companyId: scope['company_id'] ?? '',
        );
      }
      if (!mounted) return;
      setState(() {
        _saving = false;
        _draft = null;
        _phoneSurface = _WorkspacePhoneSurface.agenda;
      });
      await _reloadAgenda(force: true);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(kCompanyAgendaSaved.of(_lang))));
      await _openBooking(companyAgendaRideDetailId(ride), ride: ride);
      if (!mounted) return;
      if (ride.assignmentWarning.trim().isNotEmpty || _assignmentBlocked) {
        final combo = companyPlanFindCrewCombo(
          combos: _planCrewCombos,
          driverId: _planDriverId,
          vehicleId: _planVehicleId,
        );
        final driverName = combo == null
            ? kCompanyAgendaDriverFallback.of(_lang)
            : companyPlanPublicDriverName(combo.driver, _lang);
        final vehicleName = combo == null
            ? kCompanyAgendaVehicleFallback.of(_lang)
            : companyPlanPublicVehicleName(combo.vehicle, _lang);
        final reason = ride.assignmentWarning.trim().isNotEmpty
            ? companyPlanAssignmentWarningReason(ride.assignmentWarning)
            : 'overlappende rit';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              companyPlanAssignmentRaceWarning(
                driverName: driverName,
                vehicleName: vehicleName,
                reason: reason,
              ),
            ),
          ),
        );
      }
    } on CompanyAgendaException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _formError = _agendaExceptionText(error);
      });
    }
  }

  CompanyAgendaRide? _rideForOpenedId(String id) {
    final needle = id.trim();
    if (needle.isEmpty) return null;
    for (final ride in [..._rides, ..._linkedRides]) {
      if (ride.collectionId == needle ||
          ride.agendaItemId == needle ||
          ride.legId == needle) {
        return ride;
      }
    }
    return null;
  }

  Future<void> _openAgendaDriverSchedule(String driverId) async {
    final id = driverId.trim();
    if (id.isEmpty) return;
    Map<String, dynamic>? driver;
    for (final row in _drivers) {
      if (companyAgendaDriverId(row) == id) {
        driver = row;
        break;
      }
    }
    final name = driver == null ? id : companyAgendaDriverName(driver);
    final loaded = await fetchCompanyOpsDriverSchedule(id);
    if (!mounted) return;
    final result = await openCompanyDriverSchedulePage(
      context,
      language: _lang,
      schedule:
          loaded.schedule ??
          CompanyDriverSchedule(
            driverId: id,
            timezone: kCompanyDefaultTimezone,
          ),
      driverName: name.isEmpty ? id : name,
      canEdit: companyDriverScheduleCallerCanEdit(
        isCompanyAdmin: true,
        callerDriverId: '',
        targetDriverId: id,
      ),
      persistenceAvailable: loaded.canPersist,
    );
    if (result == null || !loaded.canPersist) return;
    try {
      await saveCompanyOpsDriverSchedule(result);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Uurrooster bewaren mislukt.')),
      );
    }
  }

  Future<void> _openBooking(String bookingId, {CompanyAgendaRide? ride}) async {
    final opened = ride ?? _rideForOpenedId(bookingId);
    final parentId = opened != null
        ? companyAgendaRideDetailId(opened)
        : bookingId.split(':').first;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CompanyBookingDetailPage(
          bookingId: parentId,
          openedLegId: opened?.legId ?? '',
          openedLegType: opened?.legType ?? '',
          linkedBookingHint: opened?.linkedAgendaItemId ?? '',
          language: _lang,
          openedFrom: CompanyBookingOpenedFrom.bookingsList,
          agendaRepository: _agenda,
          loader: widget.bookingDetailLoader,
          driversLoader: widget.driversLoader ?? fetchCompanyOpsDrivers,
          vehiclesLoader: widget.vehiclesLoader ?? fetchCompanyOpsVehicles,
        ),
      ),
    );
    if (mounted) await _reloadAgenda(force: true);
  }

  Future<void> _addCustomer() async {
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute<Object?>(
        builder: (_) =>
            CompanyCustomerFormPage(repository: _customers, language: _lang),
      ),
    );
    if (result is CompanyCustomerMutationResult || result is CompanyCustomer) {
      await _reloadCustomers();
    }
  }

  Future<void> _importCustomers() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => CompanyCustomerImportPage(
          repository: _customers,
          language: _lang,
          sessionStore:
              widget.sessionStore ??
              customer_ops_factory.createCompanyCustomerImportSessionStore(),
        ),
      ),
    );
    if (changed == true) await _reloadCustomers();
  }

  Future<void> _editSelected() async {
    final current = _selected;
    if (current == null) return;
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute<Object?>(
        builder: (_) => CompanyCustomerFormPage(
          repository: _customers,
          existing: current,
          language: _lang,
        ),
      ),
    );
    if (result is CompanyCustomer) {
      setState(() => _selected = result);
      await _reloadCustomers();
    }
  }

  Future<void> _quoteSelected() async {
    final current = _selected;
    if (current == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CompanyCustomerQuotePage(
          repository: _customers,
          customer: current,
          language: _lang,
          issuerName: widget.issuerName,
          initialStartAt: _agendaMoment,
          onOpenBooking: (bookingId) {
            _openBooking(bookingId);
          },
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _quotesRevision += 1);
  }

  Future<void> _switchSyntheticCompany(String companyId) async {
    final changed = await bindLocalSyntheticCompanySessionForCompany(companyId);
    if (!changed || !mounted) return;
    _onCompanyScopeChanged();
  }

  void _maybeDefaultTabletPortrait(Size size) {
    if (_appliedPortraitDefault || _userPickedView) return;
    final tablet =
        size.width >= kCompanyOpsWorkspaceTabletWidth &&
        size.width < kCompanyOpsWorkspaceDesktopWidth;
    if (!tablet ||
        size.height <= size.width ||
        _view != CompanyAgendaView.week) {
      return;
    }
    _appliedPortraitDefault = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _userPickedView) return;
      setState(() => _view = CompanyAgendaView.day);
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    _maybeDefaultTabletPortrait(size);
    final width = size.width;
    final phone = width < kCompanyOpsWorkspaceTabletWidth;
    return CompanyOpsThemedScope(
      builder: (context) => Scaffold(
        key: kCompanyOpsWorkspacePageKey,
        appBar: AppBar(
          title: Text(
            widget.plannerOnly
                ? kCompanyAgendaPlanRide.of(_lang)
                : kCompanyCustomersTitle.of(_lang),
          ),
          leading: phone && _phoneSurface == _WorkspacePhoneSurface.form
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    setState(() {
                      _phoneSurface = _WorkspacePhoneSurface.agenda;
                    });
                  },
                )
              : null,
          actions: [
            if (canOfferLocalSyntheticCompanySwitch)
              PopupMenuButton<String>(
                key: kCompanyAgendaSwitchCompanyKey,
                tooltip: 'Bedrijf',
                onSelected: _switchSyntheticCompany,
                itemBuilder: (context) => [
                  for (final company in kLocalSyntheticCompanyNames.entries)
                    PopupMenuItem<String>(
                      value: company.key,
                      child: Text(company.value),
                    ),
                ],
              ),
            if (_draft != null &&
                (!phone || _phoneSurface == _WorkspacePhoneSurface.form))
              IconButton(
                key: kCompanyAgendaPlanCloseKey,
                tooltip: kCompanyAgendaCancel.of(_lang),
                onPressed: _saving ? null : _cancelDraft,
                icon: const Icon(Icons.close),
              )
            else
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton(
                  key: kCompanyAgendaPlanRideKey,
                  onPressed: () => _beginPlan(),
                  child: Text(kCompanyAgendaPlanRide.of(_lang)),
                ),
              ),
          ],
        ),
        body: KeyedSubtree(
          key: widget.plannerOnly
              ? kCompanyOpsPlannerWorkspaceKey
              : const ValueKey<String>('company_ops_combined_workspace'),
          child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              if (companyOpsShowAgendaBesidePlanner(
                size,
                desktopWidth: kCompanyOpsWorkspaceDesktopWidth,
              )) {
                return _desktopBody();
              }
              if (constraints.maxWidth >= kCompanyOpsWorkspaceTabletWidth) {
                return _tabletBody();
              }
              return _phoneBody();
            },
          ),
        ),
        ),
        bottomNavigationBar: phone && widget.plannerOnly
            ? NavigationBar(
                key: kCompanyAgendaPhoneNavKey,
                selectedIndex: _phoneSurface == _WorkspacePhoneSurface.form
                    ? 1
                    : 0,
                destinations: [
                  NavigationDestination(
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: kCompanyAgendaTitle.of(_lang),
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.local_taxi_outlined),
                    label: kCompanyAgendaNewRideTab.of(_lang),
                  ),
                ],
                onDestinationSelected: (index) {
                  if (index == 1) {
                    unawaited(_beginPlan());
                    return;
                  }
                  setState(() => _phoneSurface = _WorkspacePhoneSurface.agenda);
                  unawaited(_reloadAgenda(force: true));
                },
              )
            : null,
      ),
    );
  }

  Widget _desktopBody() {
    if (widget.plannerOnly) return _plannerDesktopBody();
    final showDossier = _draft != null || !_dossierCollapsed;
    return LayoutBuilder(
      builder: (context, constraints) {
        final plannerWidth = companyOpsPlannerPaneWidth(
          totalWidth: constraints.maxWidth,
          customersCollapsed: _customersCollapsed,
          planning: _draft != null,
          dossierOpen: showDossier,
          customerPaneWidth: kCompanyOpsWorkspaceCustomerPaneWidth,
          dossierPaneWidth: kCompanyOpsWorkspaceDossierPaneWidth,
          collapsedRailWidth: kCompanyOpsWorkspaceCollapsedRailWidth,
        );
        return Row(
          children: [
            if (_customersCollapsed)
              _collapsedRail(
                key: kCompanyAgendaToggleCustomersKey,
                tooltip:
                    '${kCompanyAgendaShowPane.of(_lang)} ${kCompanyAgendaCustomerPane.of(_lang)}',
                icon: Icons.people_outline,
                onPressed: () => setState(() => _customersCollapsed = false),
              )
            else
              SizedBox(
                width: kCompanyOpsWorkspaceCustomerPaneWidth,
                child: _customerList(compact: true),
              ),
            const VerticalDivider(width: 1),
            Expanded(child: _agendaPane(_AgendaChrome.desktop)),
            const VerticalDivider(width: 1),
            if (showDossier)
              SizedBox(width: plannerWidth, child: _detailPane())
            else
              _collapsedRail(
                key: kCompanyAgendaToggleDossierKey,
                tooltip:
                    '${kCompanyAgendaShowPane.of(_lang)} ${kCompanyAgendaDossierPane.of(_lang)}',
                icon: Icons.badge_outlined,
                onPressed: () => setState(() => _dossierCollapsed = false),
              ),
          ],
        );
      },
    );
  }

  Widget _collapsedRail({
    required Key key,
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: kCompanyOpsWorkspaceCollapsedRailWidth,
      child: Center(
        child: IconButton(
          key: key,
          tooltip: tooltip,
          color: companyOpsCurrentScheme().onSurface,
          onPressed: onPressed,
          icon: Icon(icon, color: companyOpsCurrentScheme().onSurface),
        ),
      ),
    );
  }

  Widget _plannerDesktopBody() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final plannerWidth = companyOpsPlannerPaneWidth(
          totalWidth: constraints.maxWidth,
          customersCollapsed: true,
          planning: true,
          dossierOpen: true,
          customerPaneWidth: 0,
          collapsedRailWidth: 0,
        );
        return Row(
          children: [
            Expanded(child: _agendaPane(_AgendaChrome.desktop)),
            const VerticalDivider(width: 1),
            SizedBox(
              width: plannerWidth,
              child: _draft != null ? _rideForm() : _plannerEmptyPane(),
            ),
          ],
        );
      },
    );
  }

  Widget _plannerEmptyPane() {
    final scheme = companyOpsCurrentScheme();
    return ColoredBox(
      color: scheme.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                kCompanyAgendaHint.of(_lang),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('company_ops_planner_empty_start'),
                onPressed: () => unawaited(_beginPlan()),
                child: Text(kCompanyAgendaNewRideTab.of(_lang)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabletBody() {
    if (widget.plannerOnly) {
      if (_draft != null) return _rideForm();
      return _agendaPane(_AgendaChrome.tablet);
    }
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width >= size.height;
    if (_draft != null) return _rideForm();
    if (_tabletDossierOpen && _selected != null && !landscape) {
      return Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              tooltip: kCompanyAgendaTitle.of(_lang),
              onPressed: () => setState(() => _tabletDossierOpen = false),
              icon: const Icon(Icons.arrow_back),
            ),
          ),
          Expanded(child: _detailPane()),
        ],
      );
    }
    final pinList =
        landscape &&
        size.width >= kCompanyOpsWorkspaceTabletPinListWidth &&
        _tabletCustomersOpen;
    return Stack(
      children: [
        Column(
          children: [
            if (_selected != null) _selectedCustomerBanner(),
            Expanded(child: _agendaPane(_AgendaChrome.tablet)),
          ],
        ),
        if (pinList)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 260,
            child: Material(elevation: 3, child: _customerList(compact: true)),
          )
        else if (_tabletCustomersOpen)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 280,
            child: Material(
              elevation: 8,
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      tooltip:
                          '${kCompanyAgendaHidePane.of(_lang)} ${kCompanyAgendaCustomerPane.of(_lang)}',
                      onPressed: () =>
                          setState(() => _tabletCustomersOpen = false),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                  Expanded(child: _customerList(compact: true)),
                ],
              ),
            ),
          ),
        if (_tabletDossierOpen && _selected != null && landscape)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 360,
            child: Material(
              elevation: 8,
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      tooltip:
                          '${kCompanyAgendaHidePane.of(_lang)} ${kCompanyAgendaDossierPane.of(_lang)}',
                      onPressed: () =>
                          setState(() => _tabletDossierOpen = false),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                  Expanded(child: _detailPane()),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _phoneBody() {
    if (widget.plannerOnly) {
      if (_phoneSurface == _WorkspacePhoneSurface.form) return _rideForm();
      return _agendaPane(_AgendaChrome.phone);
    }
    switch (_phoneSurface) {
      case _WorkspacePhoneSurface.form:
        return _rideForm();
      case _WorkspacePhoneSurface.detail:
        return _detailPane();
      case _WorkspacePhoneSurface.agenda:
        return _agendaPane(_AgendaChrome.phone);
      case _WorkspacePhoneSurface.customers:
        return _customerList(compact: false);
    }
  }

  Widget _selectedCustomerBanner() {
    final customer = _selected;
    if (customer == null) return const SizedBox.shrink();
    return Material(
      color: companyOpsCurrentScheme().surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                customer.displayName,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    TextButton(
                      onPressed: _editSelected,
                      child: Text(kCompanyCustomersEdit.of(_lang)),
                    ),
                    TextButton(
                      onPressed: _quoteSelected,
                      child: Text(kCompanyCustomerQuoteCreate.of(_lang)),
                    ),
                    TextButton(
                      onPressed: () => _beginPlan(customer: customer),
                      child: Text(kCompanyAgendaPlanRide.of(_lang)),
                    ),
                    TextButton(
                      onPressed: () =>
                          setState(() => _tabletDossierOpen = true),
                      child: Text(kCompanyAgendaDossierPane.of(_lang)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _customerList({required bool compact}) {
    return ColoredBox(
      color: companyOpsCurrentScheme().surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TextField(
              key: kCompanyCustomersSearchFieldKey,
              controller: _search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: kCompanyCustomersSearchHint.of(_lang),
              ),
              onChanged: (value) {
                _query = value.trim();
                _searchDebounce?.cancel();
                _searchDebounce = Timer(const Duration(milliseconds: 280), () {
                  if (mounted) _reloadCustomers();
                });
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonal(
                  key: kCompanyCustomersAddButtonKey,
                  onPressed: _addCustomer,
                  child: Text(kCompanyCustomersAddLabel.of(_lang)),
                ),
                OutlinedButton(
                  key: kCompanyCustomersImportButtonKey,
                  onPressed: _importCustomers,
                  child: Text(kCompanyCustomersImportLabel.of(_lang)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: _customerListBody(compact: compact)),
        ],
      ),
    );
  }

  Widget _customerListBody({required bool compact}) {
    if (_loadingCustomers) {
      return Center(child: Text(kCompanyCustomersLoading.of(_lang)));
    }
    if (_customerError != null && _items.isEmpty) {
      return Center(
        child: TextButton(
          onPressed: _reloadCustomers,
          child: Text(_customerError!),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(child: Text(kCompanyCustomersEmptyActive.of(_lang)));
    }
    return ListView.builder(
      key: kCompanyCustomersListKey,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: _items.length + (_hasMoreCustomers ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _items.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: OutlinedButton(
              key: kCompanyCustomersLoadMoreKey,
              onPressed: _loadingMoreCustomers ? null : _loadMoreCustomers,
              child: Text(kCompanyCustomersLoadMore.of(_lang)),
            ),
          );
        }
        final item = _items[index];
        final selected = _selected?.customerId == item.customerId;
        final tile = Card(
          key: Key('company_customer_row_${item.customerId}'),
          color: selected
              ? companyOpsCurrentScheme().surfaceContainerHighest
              : null,
          child: ListTile(
            title: Text(item.displayName, overflow: TextOverflow.ellipsis),
            subtitle: compact
                ? null
                : Text(item.emailMasked, overflow: TextOverflow.ellipsis),
            onTap: () => _selectCustomer(item),
          ),
        );
        return Draggable<CompanyCustomerListItem>(
          data: item,
          feedback: Material(
            elevation: 6,
            child: SizedBox(
              width: 220,
              child: ListTile(title: Text(item.displayName)),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.4, child: tile),
          child: tile,
        );
      },
    );
  }

  Widget _agendaPane(_AgendaChrome chrome) {
    final phone = chrome == _AgendaChrome.phone;
    final tablet = chrome == _AgendaChrome.tablet;
    return ColoredBox(
      key: kCompanyAgendaPaneKey,
      color: companyOpsCurrentScheme().surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (!phone)
                  _toolbarGroup(
                    key: kCompanyAgendaViewGroupKey,
                    children: [
                      CompanyOpsSelectableChip(
                        key: kCompanyAgendaDayKey,
                        selected: _view == CompanyAgendaView.day,
                        label: kCompanyAgendaDay.of(_lang),
                        onSelected: (_) => _setView(CompanyAgendaView.day),
                      ),
                      CompanyOpsSelectableChip(
                        key: kCompanyAgendaWeekKey,
                        selected: _view == CompanyAgendaView.week,
                        label: kCompanyAgendaWeek.of(_lang),
                        onSelected: (_) => _setView(CompanyAgendaView.week),
                      ),
                      CompanyOpsSelectableChip(
                        key: kCompanyAgendaByDriverKey,
                        selected: _view == CompanyAgendaView.byDriver,
                        label: kCompanyAgendaByDriver.of(_lang),
                        onSelected: (_) => _setView(CompanyAgendaView.byDriver),
                      ),
                    ],
                  ),
                if (!phone)
                  _toolbarGroup(
                    key: kCompanyAgendaDensityGroupKey,
                    children: [
                      CompanyOpsSelectableChip(
                        key: kCompanyAgendaHourCompactKey,
                        selected:
                            _hourDensity == CompanyAgendaHourDensity.compact,
                        label: kCompanyAgendaHourCompact.of(_lang),
                        onSelected: (_) => unawaited(
                          _setHourDensity(CompanyAgendaHourDensity.compact),
                        ),
                      ),
                      CompanyOpsSelectableChip(
                        key: kCompanyAgendaHourSpaciousKey,
                        selected:
                            _hourDensity == CompanyAgendaHourDensity.spacious,
                        label: kCompanyAgendaHourSpacious.of(_lang),
                        onSelected: (_) => unawaited(
                          _setHourDensity(CompanyAgendaHourDensity.spacious),
                        ),
                      ),
                    ],
                  ),
                _periodNavGroup(),
                OutlinedButton(
                  key: kCompanyAgendaTodayKey,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: companyOpsCurrentScheme().onSurface,
                    side: BorderSide(color: companyOpsCurrentScheme().outline),
                  ),
                  onPressed: () {
                    setState(() => _anchor = DateTime.now());
                    _reloadAgenda(force: true);
                  },
                  child: Text(kCompanyAgendaToday.of(_lang)),
                ),
                OutlinedButton(
                  key: kCompanyAgendaPickDateKey,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: companyOpsCurrentScheme().onSurface,
                    side: BorderSide(color: companyOpsCurrentScheme().outline),
                  ),
                  onPressed: _pickAnchorDate,
                  child: Text(kCompanyAgendaPickDate.of(_lang)),
                ),
                if (chrome == _AgendaChrome.desktop && !widget.plannerOnly)
                  _toolbarGroup(
                    children: [
                      IconButton(
                        key: _customersCollapsed
                            ? null
                            : kCompanyAgendaToggleCustomersKey,
                        tooltip:
                            '${_customersCollapsed ? kCompanyAgendaShowPane.of(_lang) : kCompanyAgendaHidePane.of(_lang)} ${kCompanyAgendaCustomerPane.of(_lang)}',
                        onPressed: () {
                          setState(
                            () => _customersCollapsed = !_customersCollapsed,
                          );
                        },
                        color: companyOpsCurrentScheme().onSurface,
                        icon: Icon(
                          _customersCollapsed
                              ? Icons.people_outline
                              : Icons.view_sidebar_outlined,
                          color: companyOpsCurrentScheme().onSurface,
                        ),
                      ),
                      IconButton(
                        key: _dossierCollapsed || _draft != null
                            ? null
                            : kCompanyAgendaToggleDossierKey,
                        tooltip:
                            '${_dossierCollapsed ? kCompanyAgendaShowPane.of(_lang) : kCompanyAgendaHidePane.of(_lang)} ${kCompanyAgendaDossierPane.of(_lang)}',
                        onPressed: _draft != null
                            ? null
                            : () {
                                setState(
                                  () => _dossierCollapsed = !_dossierCollapsed,
                                );
                              },
                        color: companyOpsCurrentScheme().onSurface,
                        icon: Icon(
                          _dossierCollapsed
                              ? Icons.badge_outlined
                              : Icons.chrome_reader_mode_outlined,
                          color: companyOpsCurrentScheme().onSurface,
                        ),
                      ),
                    ],
                  ),
                if (tablet && !widget.plannerOnly)
                  IconButton(
                    key: kCompanyAgendaToggleCustomersKey,
                    tooltip:
                        '${_tabletCustomersOpen ? kCompanyAgendaHidePane.of(_lang) : kCompanyAgendaShowPane.of(_lang)} ${kCompanyAgendaCustomerPane.of(_lang)}',
                    onPressed: () {
                      setState(
                        () => _tabletCustomersOpen = !_tabletCustomersOpen,
                      );
                    },
                    color: companyOpsCurrentScheme().onSurface,
                    icon: Icon(
                      _tabletCustomersOpen
                          ? Icons.view_sidebar_outlined
                          : Icons.people_outline,
                      color: companyOpsCurrentScheme().onSurface,
                    ),
                  ),
              ],
            ),
          ),
          if (!phone)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                kCompanyAgendaHint.of(_lang),
                style: TextStyle(
                  color: companyOpsCurrentScheme().onSurface,
                  fontSize: 13,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: CompanyDriversNowStrip(
              language: _lang,
              selectedDriverId: _driverFilter,
              expanded: _driversNowExpanded,
              onExpandedChanged: (next) {
                setState(() => _driversNowExpanded = next);
              },
              rows: companyDriverNowRows(
                drivers: _drivers,
                rides: _nowRides,
                nowUtc: DateTime.now().toUtc(),
              ),
              onSelectDriver: (driverId) {
                setState(() {
                  if (driverId.isEmpty || _driverFilter == driverId) {
                    _driverFilter = null;
                  } else {
                    _driverFilter = driverId;
                  }
                });
              },
              onClearDriver: () => setState(() => _driverFilter = null),
              onOpenRide: _openBooking,
              onOpenSchedule: _openAgendaDriverSchedule,
            ),
          ),
          if (_agendaIncomplete && !_loadingAgenda)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    kCompanyAgendaIncompleteOverview.of(_lang),
                    key: const Key('company_agenda_incomplete_overview'),
                    softWrap: true,
                  ),
                  TextButton(
                    key: const Key('company_agenda_smaller_period'),
                    onPressed: () {
                      setState(() {
                        _view = CompanyAgendaView.day;
                        _userPickedView = true;
                      });
                      _reloadAgenda(force: true);
                    },
                    child: Text(kCompanyAgendaSmallerPeriod.of(_lang)),
                  ),
                ],
              ),
            ),
          if (!phone &&
              _rides.isEmpty &&
              !_loadingAgenda &&
              _agendaError == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(kCompanyAgendaEmpty.of(_lang)),
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: phone
                ? CompanyAgendaPhoneDayPane(
                    anchor: _anchor,
                    rides: _rides,
                    language: _lang,
                    drivers: _drivers,
                    filteredDriverId: _driverFilter,
                    onSelectDay: (day) {
                      setState(() => _anchor = day);
                      _reloadAgenda(force: true);
                    },
                    onSelectRide: (ride) => _openBooking(
                      companyAgendaRideDetailId(ride),
                      ride: ride,
                    ),
                  )
                : _agendaCalendar(),
          ),
        ],
      ),
    );
  }

  Widget _toolbarGroup({Key? key, required List<Widget> children}) {
    return Row(
      key: key,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i += 1) ...[
          if (i > 0) const SizedBox(width: 8),
          children[i],
        ],
      ],
    );
  }

  ButtonStyle get _periodNavButtonStyle => IconButton.styleFrom(
    minimumSize: const Size(48, 48),
    tapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
    padding: EdgeInsets.zero,
  );

  Widget _periodNavGroup() {
    final scheme = companyOpsCurrentScheme();
    return Material(
      key: kCompanyAgendaNavGroupKey,
      color: scheme.surfaceContainerHigh,
      shape: StadiumBorder(side: BorderSide(color: scheme.outline)),
      clipBehavior: Clip.antiAlias,
      child: IconTheme(
        data: IconThemeData(color: scheme.onSurface),
        child: DefaultTextStyle.merge(
          style: TextStyle(
            color: scheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                key: kCompanyAgendaPrevPeriodKey,
                tooltip: kCompanyAgendaPreviousPeriod.of(_lang),
                style: _periodNavButtonStyle,
                color: scheme.onSurface,
                onPressed: () {
                  setState(() {
                    _anchor = _anchor.subtract(Duration(days: _stepDays));
                  });
                  _reloadAgenda(force: true);
                },
                icon: const Icon(Icons.chevron_left),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: 88,
                  maxWidth: 148,
                  minHeight: 48,
                ),
                child: InkWell(
                  key: kCompanyAgendaPeriodLabelKey,
                  onTap: _pickAnchorDate,
                  child: Center(
                    child: Text(
                      _periodLabel(),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                key: kCompanyAgendaNextPeriodKey,
                tooltip: kCompanyAgendaNextPeriod.of(_lang),
                style: _periodNavButtonStyle,
                color: scheme.onSurface,
                onPressed: () {
                  setState(() {
                    _anchor = _anchor.add(Duration(days: _stepDays));
                  });
                  _reloadAgenda(force: true);
                },
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _periodLabel() {
    final period = _period;
    final from = period.fromUtc.toLocal();
    if (_view == CompanyAgendaView.day || _view == CompanyAgendaView.byDriver) {
      return '${from.day}/${from.month}/${from.year}';
    }
    final to = period.toUtc.toLocal().subtract(const Duration(minutes: 1));
    return '${from.day}/${from.month} – ${to.day}/${to.month}';
  }

  Widget _agendaCalendar() {
    return CompanyAgendaCalendar(
      period: _period,
      rides: _rides,
      language: _lang,
      drivers: _drivers,
      loading: _loadingAgenda,
      errorText: _agendaError,
      filteredDriverId: _driverFilter,
      hourHeight: companyAgendaHourHeightFor(_hourDensity),
      onRetry: () => _reloadAgenda(force: true),
      onSelectRide: (ride) =>
          _openBooking(companyAgendaRideDetailId(ride), ride: ride),
      onAcceptCustomer: _acceptCustomerOnSlot,
      onAcceptRide: _acceptRideOnSlot,
      onFilterDriver: (id) => setState(() => _driverFilter = id),
    );
  }

  Widget _detailPane() {
    if (_draft != null) return _rideForm();
    final scheme = companyOpsCurrentScheme();
    final customer = _selected;
    if (customer == null) {
      return ColoredBox(
        color: scheme.surface,
        child: Center(
          child: Text(
            kCompanyCustomersSelectHint.of(_lang),
            key: kCompanyCustomerDossierEmptyHintKey,
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
    return ColoredBox(
      color: scheme.surface,
      child: IconTheme(
        data: IconThemeData(color: scheme.onSurface),
        child: DefaultTextStyle(
          style: TextStyle(color: scheme.onSurface, fontSize: 14),
          child: CompanyCustomerDossier(
            customer: customer,
            language: _lang,
            repository: _customers,
            issuerName: widget.issuerName,
            reloadToken: _quotesRevision,
            plannedRides: _linkedRides
                .where((ride) => ride.customerId == customer.customerId)
                .toList(),
            onOpenBooking: (bookingId) {
              _openBooking(bookingId);
            },
            onEdit: _editSelected,
            actions: [
              FilledButton(
                key: kCompanyCustomersEditButtonKey,
                onPressed: _editSelected,
                child: Text(kCompanyCustomersEdit.of(_lang)),
              ),
              OutlinedButton(
                key: kCompanyCustomersQuoteButtonKey,
                onPressed: _quoteSelected,
                child: Text(kCompanyCustomerQuoteCreate.of(_lang)),
              ),
              OutlinedButton(
                onPressed: () => _beginPlan(customer: customer),
                child: Text(kCompanyAgendaPlanRide.of(_lang)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _planQuoteSummary() {
    final quote = _planQuoteResult;
    final split = _roundtripChoice != CompanyRoundtripChoice.single;
    final sanity = quote == null
        ? const CompanyPlanQuoteSanity(ok: true)
        : companyPlanQuoteSanityCheck(quote);
    final waitIncl = companyPlanQuoteLineIncl(
      quote?.breakdown,
      quote?.breakdown?.waitingEx,
    );
    final bagsIncl = companyPlanQuoteLineIncl(
      quote?.breakdown,
      quote?.breakdown?.bagsEx,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (quote != null && quote.hasRoute) ...[
          if (split) ...[
            Text(
              formatCompanyPlanQuoteLegLine(
                label: kCompanyRoundtripOutbound.of(_lang),
                result: quote,
                inbound: false,
                language: _lang,
                pickupLocal: _planWhenNow
                    ? companyPlanNowLocal()
                    : _planPickupLocal,
              ),
              key: const Key('company_plan_quote_outbound'),
            ),
            if (quote.hasReturnRoute)
              Text(
                formatCompanyPlanQuoteLegLine(
                  label: kCompanyRoundtripReturn.of(_lang),
                  result: quote,
                  inbound: true,
                  language: _lang,
                  pickupLocal:
                      _roundtripChoice == CompanyRoundtripChoice.continuousWait
                      ? _continuousWaitReturnPickup()
                      : _returnPickupLocal,
                ),
                key: const Key('company_plan_quote_return'),
              ),
            if ((waitIncl ?? 0) > 0)
              Text(
                '${kCompanyAgendaWaitPrice.of(_lang)} · ${formatCompanyPlanQuoteMoney(waitIncl!, quote.currency)}',
                key: kCompanyAgendaWaitPriceKey,
              ),
            if ((bagsIncl ?? 0) > 0)
              Text(
                '${kCompanyAgendaBagsPrice.of(_lang)} · ${formatCompanyPlanQuoteMoney(bagsIncl!, quote.currency)}',
                key: kCompanyAgendaBagsPriceKey,
              ),
            if (quote.displayTotalPrice != null)
              Text(
                '${kCompanyAgendaQuoteTotal.of(_lang)} · ${formatCompanyPlanQuoteMoney(quote.displayTotalPrice!, quote.currency)}',
                key: const Key('company_plan_quote_total'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
          ] else if (formatCompanyPlanQuotePrice(quote, _lang).isNotEmpty)
            Text(formatCompanyPlanQuotePrice(quote, _lang)),
          if (!quote.priceAvailable)
            Text(
              kCompanyAgendaQuoteUnavailable.of(_lang),
              key: kCompanyPlanQuotePriceKey,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
        if (!sanity.ok)
          Text(
            kCompanyAgendaPriceInvalid.of(_lang),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ExpansionTile(
          key: const Key('company_plan_price_breakdown'),
          tilePadding: EdgeInsets.zero,
          title: Text(kCompanyAgendaPriceBreakdown.of(_lang)),
          children: [
            if (quote != null &&
                formatCompanyPlanQuotePrice(quote, _lang).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(formatCompanyPlanQuotePrice(quote, _lang)),
              ),
            if (_fixedPriceSnapshot != null)
              CompanyFixedPriceBreakdown(
                language: _lang,
                snapshot: _fixedPriceSnapshot!,
              ),
            CompanyInternalRatesPanel(language: _lang, options: _rideOptions),
          ],
        ),
      ],
    );
  }

  Widget _planAssignmentFields() {
    final combos = _planCrewCombos;
    final outbound = companyPlanFindCrewCombo(
      combos: combos,
      driverId: _planDriverId,
      vehicleId: _planVehicleId,
    );
    final inbound = companyPlanFindCrewCombo(
      combos: combos,
      driverId: _planReturnDriverId,
      vehicleId: _planReturnVehicleId,
    );
    final split = _roundtripChoice == CompanyRoundtripChoice.splitNoWait;
    final waiting = _roundtripChoice == CompanyRoundtripChoice.continuousWait;
    final fromText = _fromAddress.value.displayText;
    final toText = _toAddress.value.displayText;
    final returnToText = _returnToAddress.value.displayText;
    final outboundTitle = waiting
        ? kCompanyAgendaAssignmentContinuous.of(_lang)
        : companyPlanCrewLegTitle(
            prefix: kCompanyRoundtripOutbound.of(_lang),
            from: fromText,
            to: toText,
          );
    final returnTitle = companyPlanCrewLegTitle(
      prefix: kCompanyRoundtripReturn.of(_lang),
      from: toText,
      to: returnToText.isEmpty ? fromText : returnToText,
      fromFallback: 'B',
      toFallback: 'A',
    );
    final unsuitable = companyAssignmentUnsuitableDriverChoices(
      drivers: _drivers,
      language: _lang,
      currentDriverId: _planDriverId,
      vehicles: _planVehicleChoices,
      whenNow: _planWhenNow,
      companyId: _boundCompanyId ?? '',
    );
    final sameUnavailable =
        split &&
        _preferSameCrew &&
        outbound != null &&
        inbound != null &&
        (inbound.driverId != outbound.driverId ||
            inbound.vehicleId != outbound.vehicleId);
    return Column(
      key: kCompanyAgendaPlanDriverKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_planChoicesStatus != null) ...[
          Text(_planChoicesStatus!, key: kCompanyAgendaPlanChoicesStatusKey),
          const SizedBox(height: 8),
        ],
        CompanyCrewComboPicker(
          key: kCompanyAgendaOutboundCrewKey,
          language: _lang,
          title: outboundTitle,
          combos: combos,
          selectedId:
              outbound?.id ?? companyCrewComboId(_planDriverId, _planVehicleId),
          plannedLocal: _planWhenNow ? companyPlanNowLocal() : _planPickupLocal,
          includePlate: true,
          unsuitableChoices: unsuitable,
          onSelected: (id) {
            final parsed = parseCompanyCrewComboId(id);
            setState(() {
              _planDriverId = parsed.driverId;
              _planVehicleId = parsed.vehicleId;
              _planDriverUserPicked = true;
              _planVehicleUserPicked = true;
              _planOverlapPreview = null;
              if (!split) {
                _planReturnDriverId = parsed.driverId;
                _planReturnVehicleId = parsed.vehicleId;
              } else if (_preferSameCrew &&
                  companyPlanCrewComboAvailableOnBoth(
                    outbound: combos,
                    inbound: _planReturnCrewCombos,
                    driverId: parsed.driverId,
                    vehicleId: parsed.vehicleId,
                  )) {
                _planReturnDriverId = parsed.driverId;
                _planReturnVehicleId = parsed.vehicleId;
              }
            });
            _syncPlanAssignmentProposal();
          },
        ),
        if (split) ...[
          const SizedBox(height: 8),
          SwitchListTile(
            key: kCompanyAgendaPreferSameCrewKey,
            contentPadding: EdgeInsets.zero,
            title: Text(kCompanyAgendaSameCrewIfAvailable.of(_lang)),
            value: _preferSameCrew,
            onChanged: (next) {
              setState(() {
                _preferSameCrew = next;
                if (next && _preferSameCrewWindowsChecked) {
                  _planReturnDriverId = _planDriverId;
                  _planReturnVehicleId = _planVehicleId;
                } else if (next && !_preferSameCrewWindowsChecked) {
                  _preferSameCrew = false;
                }
              });
              _syncPlanAssignmentProposal();
            },
          ),
          if (sameUnavailable)
            Text(
              kCompanyAgendaSameCrewUnavailable.of(_lang),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          CompanyCrewComboPicker(
            key: kCompanyAgendaReturnCrewKey,
            language: _lang,
            title: returnTitle,
            combos: _planReturnCrewCombos,
            selectedId:
                inbound?.id ??
                companyCrewComboId(_planReturnDriverId, _planReturnVehicleId),
            plannedLocal: _returnPickupLocal,
            includePlate: true,
            unsuitableChoices: unsuitable,
            onSelected: (id) {
              final parsed = parseCompanyCrewComboId(id);
              setState(() {
                _planReturnDriverId = parsed.driverId;
                _planReturnVehicleId = parsed.vehicleId;
                _planOverlapPreview = null;
                _preferSameCrew =
                    parsed.driverId == _planDriverId &&
                    parsed.vehicleId == _planVehicleId &&
                    companyPlanCrewComboAvailableOnBoth(
                      outbound: combos,
                      inbound: _planReturnCrewCombos,
                      driverId: parsed.driverId,
                      vehicleId: parsed.vehicleId,
                    );
              });
              unawaited(_previewPlanOverlap());
            },
          ),
        ],
        if (_planOverlapPreview != null) ...[
          const SizedBox(height: 8),
          Text(
            _planOverlapPreview!,
            key: kCompanyAgendaOverlapPreviewKey,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }

  Widget _rideForm() {
    final draft = _draft;
    if (draft == null) return const SizedBox.shrink();
    final airportMode = _planAirportMode;
    return KeyedSubtree(
      key: kCompanyAgendaRideFormKey,
      child: CompanyPlanRideForm(
        language: _lang,
        title: kCompanyAgendaPlanRide.of(_lang),
        brand: resolveCompanyPlanBrand(
          identity: companyOpsIdentityNotifier.value,
        ),
        whenNow: _planWhenNow,
        onWhenNowChanged: _setPlanWhenNow,
        selectedCategory: _planVehicleCategory,
        onCategoryChanged: _setPlanVehicleCategory,
        categoryPhotoUrls: companyPlanCategoryPhotoUrls(
          vehicles: _planOfferVehicles,
          tenantId: _agenda.scope?['tenant_id'] ?? '',
          companyId: _boundCompanyId ?? '',
        ),
        categoryPassengerCaps: companyPlanCategoryPassengerCaps(
          vehicles: _planOfferVehicles,
        ),
        vehicleOfferCards: _planVehicleOfferCards(),
        bookableCategories: companyPlanBookableCategories(
          vehicles: _planOfferVehicles,
          passengers: _passengers,
        ),
        unsuitableCategories: <CompanyPlanVehicleCategory>{
          for (final category in companyPlanBookableCategories(
            vehicles: _planOfferVehicles,
            passengers: _passengers,
          ))
            if (!companyPlanVehicleTypeFitsCapacity(
              type: companyPlanVehicleTypeForCategory(category),
              passengers: _passengers,
              bags: _rideOptions.bags,
            ))
              category,
        },
        capacityWarning: () {
          if (companyPlanVehicleTypeFitsCapacity(
            type: _planVehicleType,
            passengers: _passengers,
            bags: _rideOptions.bags,
          )) {
            return null;
          }
          final suggested = companyPlanSuggestedTypeForCapacity(
            passengers: _passengers,
            bags: _rideOptions.bags,
            available: companyPlanBookableCategories(
              vehicles: _planOfferVehicles,
              passengers: _passengers,
            ).map(companyPlanVehicleTypeForCategory),
          );
          if (suggested == null) {
            return kCompanyAgendaCapacityUnsuitable.of(_lang);
          }
          return kCompanyAgendaCapacitySuggest
              .of(_lang)
              .replaceAll(
                '{type}',
                companyPlanVehicleTypeLabel(suggested, _lang),
              );
        }(),
        unavailableReasons: <CompanyPlanVehicleCategory, String>{
          for (final category in companyPlanBookableCategories(
            vehicles: _planOfferVehicles,
            passengers: _passengers,
          ))
            if (companyPlanCategoryUnavailableReason(
                  category: category,
                  vehicles: _planOfferVehicles,
                  passengers: _passengers,
                  language: _lang,
                )
                case final reason?)
              category: reason,
        },
        customer: draft.customer,
        customers: _items,
        onCustomerSelected: (item) => unawaited(_applyPlanCustomerItem(item)),
        onAddCustomer: () => unawaited(_addPlanCustomer()),
        vehicleType: _planVehicleType,
        airportMode: airportMode,
        onVehicleTypeChanged: _setPlanVehicleType,
        onAirportModeChanged: _setPlanAirportMode,
        routeFields: CompanyTripRouteFields(
          language: _lang,
          pickup: _fromAddress,
          dropoff: _toAddress,
          rideOptions: _rideOptions,
          onRideOptionsChanged: (next) {
            setState(() {
              _rideOptions = next.copyWith(
                vehicleType: _rideOptions.vehicleType,
              );
              _fixedPriceSnapshot = null;
              _planQuoteResult = null;
            });
            _schedulePlanQuote();
          },
          savedAddresses: draft.customer.addresses,
          pickupInputKey: kCompanyAgendaFromFieldKey,
          dropoffInputKey: kCompanyAgendaToFieldKey,
          pickupLabel: kCompanyAgendaPickupPlace.of(_lang),
          dropoffLabel: kCompanyAgendaDropoffPlace.of(_lang),
          sectionTitle: kCompanyRoundtripOutbound.of(_lang),
          onRouteIdentityChanged: () {
            _fillReturnRouteFromOutbound();
            _onPlanAddressChanged();
          },
          showReturnAirportFields: false,
          showRouteKindChips: false,
          showAirportDestinationCards: false,
          hideAddressKindChip: true,
          pickupLocal: _planPickupLocal,
          whenNow: _planWhenNow,
          routeDurationMin: _planDurationMin,
          showFlightBlock: false,
          betweenEndpoints: CompanyPlanWaypointFields(
            language: _lang,
            stops: _outboundStops,
            savedAddresses: draft.customer.addresses,
          ),
        ),
        roundtripChoiceFields: CompanyRoundtripChoiceControl(
          language: _lang,
          choice: _roundtripChoice,
          onChoiceChanged: _onRoundtripChoiceChanged,
        ),
        returnRouteFields: _roundtripChoice == CompanyRoundtripChoice.single
            ? null
            : CompanyRoundtripFields(
                language: _lang,
                choice: _roundtripChoice,
                onChoiceChanged: _onRoundtripChoiceChanged,
                returnPickup: _returnPickupLocal,
                onReturnPickupChanged: (next) {
                  setState(() => _returnPickupLocal = next);
                  unawaited(_previewPlanOverlap());
                  _schedulePlanQuote();
                },
                returnTo: _returnToAddress,
                savedAddresses: draft.customer.addresses,
                waitMin: _rideOptions.waitMin,
                showChoice: false,
                showReturnWhen: false,
                showWait: false,
                returnFromText: _compactAddress(_toAddress.value),
                returnToText: _compactAddress(_canonicalReturnTo()),
                returnStops: CompanyPlanWaypointFields(
                  language: _lang,
                  stops: _returnStops,
                  savedAddresses: draft.customer.addresses,
                  addLabel: kCompanyAgendaAddReturnStop.of(_lang),
                  addKey: kCompanyPlanAddReturnStopKey,
                  showCount: false,
                ),
              ),
        returnWhenFields: _roundtripChoice == CompanyRoundtripChoice.splitNoWait
            ? CompanyDateTimeFields(
                fieldId: 'roundtrip_return',
                language: _lang,
                value: _returnPickupLocal,
                leadingLabel: kCompanyRoundtripReturn.of(_lang),
                onChanged: (next) {
                  setState(() => _returnPickupLocal = next);
                  unawaited(_previewPlanOverlap());
                  _schedulePlanQuote();
                },
              )
            : null,
        waitFields: _roundtripChoice == CompanyRoundtripChoice.continuousWait
            ? CompanyRoundtripFields(
                language: _lang,
                choice: _roundtripChoice,
                onChoiceChanged: _onRoundtripChoiceChanged,
                returnPickup: _returnPickupLocal,
                onReturnPickupChanged: (_) {},
                returnTo: _returnToAddress,
                waitMin: _rideOptions.waitMin,
                onWaitMinChanged: (next) {
                  setState(() {
                    _rideOptions = _rideOptions.copyWith(waitMin: next);
                    _returnPickupLocal = _continuousWaitReturnPickup();
                  });
                  unawaited(_previewPlanOverlap());
                  _schedulePlanQuote();
                },
                showChoice: false,
                showReturnTo: false,
                showReturnWhen: false,
                showWait: true,
              )
            : null,
        flightFields: airportMode
            ? CompanyTripRouteFields(
                language: _lang,
                pickup: _fromAddress,
                dropoff: _toAddress,
                rideOptions: _rideOptions,
                onRideOptionsChanged: (next) {
                  setState(() {
                    _rideOptions = next.copyWith(
                      vehicleType: _rideOptions.vehicleType,
                    );
                    _fixedPriceSnapshot = null;
                    _planQuoteResult = null;
                  });
                  _schedulePlanQuote();
                },
                savedAddresses: draft.customer.addresses,
                onRouteIdentityChanged: () {
                  _fillReturnRouteFromOutbound();
                  _onPlanAddressChanged();
                },
                showReturnAirportFields: false,
                showRouteKindChips: true,
                showAirportDestinationCards: true,
                hideAddressKindChip: true,
                pickupLocal: _planPickupLocal,
                whenNow: _planWhenNow,
                routeDurationMin: _planDurationMin,
                showFlightBlock: true,
                showGroundAddresses: false,
              )
            : null,
        whenLaterFields: CompanyDateTimeFields(
          fieldId: 'agenda_pickup',
          language: _lang,
          value: _planPickupLocal,
          firstDate: companyPlanLaterFirstDate(),
          rejectPast: true,
          leadingLabel: kCompanyRoundtripOutbound.of(_lang),
          onChanged: (next) {
            setState(() {
              _planPickupLocal = next;
              _planLaterConceptLocal = next;
              if (next != null) {
                _agendaMoment = next;
                _draft = draft.copyWith(whenNow: false, pickupLocal: next);
              }
            });
            unawaited(_previewPlanOverlap());
            _schedulePlanQuote();
          },
        ),
        passengers: _passengers,
        onPassengersChanged: (next) {
          final capped = _clampPlanPassengers(next);
          final type = _planVehicleId.isNotEmpty
              ? _planVehicleType
              : (capped > kCompanyPlanSedanMaxPassengers
                  ? CompanyPlanVehicleType.minivan
                  : _planVehicleType);
          setState(() {
            _passengers = capped;
            if (type != _planVehicleType) {
              _rideOptions = _rideOptions.copyWith(
                vehicleType: companyPlanVehicleTypeWire(type),
              );
            }
          });
          _syncPlanAssignmentProposal();
          _schedulePlanQuote();
        },
        bags: _rideOptions.bags,
        onBagsChanged: (next) {
          setState(() => _rideOptions = _rideOptions.copyWith(bags: next));
          _schedulePlanQuote();
        },
        quote: _planQuoteSummary(),
        proposedAssignment: _planAssignmentFields(),
        unsuitableDrivers: null,
        moreOptions: [
          CompanyRideOptionsForm(
            language: _lang,
            value: _rideOptions,
            showTitle: false,
            showService: false,
            showTier: false,
            showBags: false,
            showWait: false,
            showAirportRouteFields: false,
            showReturnAirportFields: false,
            showMeetAndGreet: true,
            onChanged: (next) {
              setState(
                () => _rideOptions = next.copyWith(
                  vehicleType: _rideOptions.vehicleType,
                  bags: _rideOptions.bags,
                  waitMin: _rideOptions.waitMin,
                ),
              );
              _schedulePlanQuote();
            },
          ),
          TextField(
            controller: _noteCtrl,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: kCompanyCustomerQuoteDescription.of(_lang),
              alignLabelWithHint: true,
            ),
          ),
          TextField(
            controller: _priceCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: kCompanyAgendaPrice.of(_lang),
            ),
          ),
          if (_roundtripChoice != CompanyRoundtripChoice.single)
            Text(
              kCompanyRoundtripPriceCovers.of(_lang),
              style: Theme.of(context).textTheme.bodySmall,
              softWrap: true,
            ),
          ExpansionTile(
            key: kCompanyPlanQuoteManualDurationKey,
            tilePadding: EdgeInsets.zero,
            title: Text(kCompanyAgendaManualDuration.of(_lang)),
            subtitle: Text(
              kCompanyAgendaManualDurationHint.of(_lang),
              softWrap: true,
            ),
            children: [
              TextField(
                controller: _durationCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: kCompanyAgendaManualDuration.of(_lang),
                ),
              ),
            ],
          ),
        ],
        primary: FilledButton(
          key: kCompanyAgendaSaveRideKey,
          onPressed: _saving ? null : _saveDraft,
          child: Text(kCompanyAgendaPlanRide.of(_lang)),
        ),
        secondary: OutlinedButton(
          key: kCompanyAgendaCancelRideKey,
          onPressed: _saving ? null : _cancelDraft,
          child: Text(kCompanyAgendaCancel.of(_lang)),
        ),
        map: Builder(
          builder: (context) {
            final window = MediaQuery.sizeOf(context);
            if (companyOpsShowAgendaBesidePlanner(window)) {
              return CompanyPlanRouteMap(
                language: _lang,
                pickup: _fromAddress.value,
                dropoff: _toAddress.value,
                quote: _planQuoteResult,
                loading: _planQuoteLoading,
                error: _planQuoteError,
                onRetry: () => unawaited(_refreshPlanQuote(force: true)),
                pickupLocal:
                    _planWhenNow ? companyPlanNowLocal() : _planPickupLocal,
              );
            }
            return KeyedSubtree(
              key: kCompanyAgendaPlanMapKey,
              child: CustomerBookingRouteMap(
              language: _lang,
              palette: paletteForCustomerTheme(customerThemeNotifier.value),
              pickup: _fromAddress.value,
              dropoff: _toAddress.value,
              stops: _outboundStops.values,
              quote: _planQuoteResult,
              quoteLoading: _planQuoteLoading,
              errorText: _planQuoteError,
              onRetry: () => unawaited(_refreshPlanQuote(force: true)),
              pickupLocal:
                  _planWhenNow ? companyPlanNowLocal() : _planPickupLocal,
              ),
            );
          },
        ),
        errorText: _formError,
      ),
    );
  }
}
