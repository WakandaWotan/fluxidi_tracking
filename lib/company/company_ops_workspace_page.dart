import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/booking_list_page_repository.dart';
import 'package:fluxidi_tracking/company/company_agenda_calendar.dart';
import 'package:fluxidi_tracking/company/company_agenda_http.dart';
import 'package:fluxidi_tracking/company/company_agenda_labels.dart';
import 'package:fluxidi_tracking/company/company_agenda_prefs.dart';
import 'package:fluxidi_tracking/company/company_agenda_models.dart';
import 'package:fluxidi_tracking/company/company_booking_detail_page.dart';
import 'package:fluxidi_tracking/company/company_ops_api.dart';
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
import 'package:fluxidi_tracking/company/company_address_field.dart';
import 'package:fluxidi_tracking/company/company_assignment_choice_field.dart';
import 'package:fluxidi_tracking/company/company_driver_agenda_color_chips.dart';
import 'package:fluxidi_tracking/company/company_drivers_now.dart';
import 'package:fluxidi_tracking/company/company_form_date_time.dart';
import 'package:fluxidi_tracking/company/company_ops_theme.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_field.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';
import 'package:fluxidi_tracking/company/company_fixed_price_breakdown.dart';
import 'package:fluxidi_tracking/company/company_plan_quote.dart';
import 'package:fluxidi_tracking/company/company_plan_quote_panel.dart';
import 'package:fluxidi_tracking/company/company_rate_card_hint.dart';
import 'package:fluxidi_tracking/company/company_ride_options.dart';
import 'package:fluxidi_tracking/company/company_ride_options_form.dart';
import 'package:fluxidi_tracking/company/company_trip_route_fields.dart';
import 'package:fluxidi_tracking/company/company_roundtrip.dart';
import 'package:fluxidi_tracking/company/company_roundtrip_fields.dart';
import 'package:fluxidi_tracking/company/local_synthetic_company_session.dart';
import 'package:fluxidi_tracking/company_session_store.dart';

const Key kCompanyOpsWorkspacePageKey = Key('company_ops_workspace_page');
const Key kCompanyAgendaPaneKey = Key('company_agenda_pane');
const Key kCompanyAgendaDayKey = Key('company_agenda_day');
const Key kCompanyAgendaWeekKey = Key('company_agenda_week');
const Key kCompanyAgendaTodayKey = Key('company_agenda_today');
const Key kCompanyAgendaPlanRideKey = Key('company_agenda_plan_ride');
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
  bool _fleetLoading = true;
  String? _fleetError;
  String _planDriverId = '';
  String _planVehicleId = '';
  String? _planOverlapPreview;
  String? _driverFilter;
  String? _boundCompanyId;
  _WorkspacePhoneSurface _phoneSurface = _WorkspacePhoneSurface.customers;

  late final LimousinePlaceLookup _placeLookup;
  late final LimousineAddressFieldController _fromAddress;
  late final LimousineAddressFieldController _toAddress;
  late final LimousineAddressFieldController _returnFromAddress;
  late final LimousineAddressFieldController _returnToAddress;
  final TextEditingController _priceCtrl = TextEditingController();
  final TextEditingController _durationCtrl = TextEditingController();
  final TextEditingController _returnDurationCtrl = TextEditingController();
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
    final request = companyPlanQuoteRequestFromAddresses(
      from: _fromAddress.value,
      to: _toAddress.value,
      pickupLocal: _planPickupLocal ?? _draft?.pickupLocal,
      options: _rideOptions,
      passengers: _passengers,
      returnEnabled: _roundtripChoice != CompanyRoundtripChoice.single,
      returnPickupLocal: _returnPickupLocal,
      returnFrom: _returnFromAddress.value,
      returnTo: _returnToAddress.value,
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
      final result = await _planQuote.quote(request);
      if (!mounted) return;
      if (result.fingerprint != request.fingerprint) return;
      setState(() {
        _planQuoteResult = result;
        _planQuoteLoading = false;
        _planQuoteError = null;
        _fixedPriceSnapshot = result.fixedPriceSnapshot;
      });
      _applyAutomaticDuration(result);
    } on CompanyAgendaException catch (error) {
      if (!mounted) return;
      setState(() {
        _planQuoteLoading = false;
        _planQuoteError = error.code.trim().isEmpty
            ? 'De route kon niet worden berekend. De ingevulde ritgegevens blijven bewaard.'
            : error.code;
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
    if (_durationCtrl.text.trim() == next) return;
    _durationCtrl.text = next;
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
    if (chosen != null &&
        _draft != null &&
        _draft!.customer.customerId == chosen.customerId &&
        pickup == null) {
      setState(() => _phoneSurface = _WorkspacePhoneSurface.form);
      return;
    }
    if (chosen == null || chosen.isArchived) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(kCompanyAgendaSelectCustomer.of(_lang))),
      );
      return;
    }
    if (pickup != null) {
      _agendaMoment = pickup;
    }
    final when = pickup ?? DateTime(_anchor.year, _anchor.month, _anchor.day);
    final home = chosen.addresses.isEmpty
        ? ''
        : companyCustomerAddressChoiceLabel(chosen.addresses.first);
    setState(() {
      _planPickupLocal = pickup;
      _draft = CompanyRidePlanDraft(
        customer: chosen,
        pickupLocal: when,
        fromAddress: home,
        idempotencyKey:
            'agenda-${chosen.customerId}-${when.toUtc().toIso8601String()}-${DateTime.now().microsecondsSinceEpoch}',
      );
      if (chosen.addresses.isEmpty) {
        _fromAddress.clear();
      } else {
        _fromAddress.acceptCopy(
          companyAddressValueFromSaved(chosen.addresses.first),
        );
      }
      _toAddress.clear();
      _returnFromAddress.clear();
      _returnToAddress.clear();
      _priceCtrl.text = '';
      _durationCtrl.text = '';
      _returnDurationCtrl.text = '';
      _planDriverId = '';
      _planVehicleId = '';
      _planReturnDriverId = '';
      _planReturnVehicleId = '';
      _planOverlapPreview = null;
      _passengers = 1;
      _rideOptions = const CompanyRideOptions();
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
      _phoneSurface = _WorkspacePhoneSurface.form;
    });
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
      final pickupAt = _planPickupLocal ?? draft.pickupLocal;
      _returnPickupLocal ??= pickupAt.add(const Duration(hours: 3));
      if (_returnFromAddress.value.displayText.trim().isEmpty &&
          _toAddress.value.displayText.trim().isNotEmpty) {
        _returnFromAddress.acceptCopy(_toAddress.value);
      }
      if (_returnToAddress.value.displayText.trim().isEmpty &&
          _fromAddress.value.displayText.trim().isNotEmpty) {
        _returnToAddress.acceptCopy(_fromAddress.value);
      }
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
    final raw = int.tryParse(_durationCtrl.text.trim());
    if (raw == null || raw <= 0) return null;
    return raw;
  }

  bool get _planDurationUnknown => _planDurationMin == null;

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
    final pickupAt = _planPickupLocal ?? draft?.pickupLocal;
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
        returnPickupIso: _returnPickupLocal?.toUtc().toIso8601String() ?? '',
        returnDurationMin: int.tryParse(_returnDurationCtrl.text.trim()),
        roundtripMode: companyRoundtripChoiceWire(_roundtripChoice),
      );
      if (!mounted || _draft != draft) return;
      var text = companyAgendaAssignmentOverlapText(check, _lang);
      if (durationUnknown ||
          (_roundtripChoice == CompanyRoundtripChoice.continuousWait &&
              (_planDurationMin == null ||
                  _returnPickupLocal == null ||
                  int.tryParse(_returnDurationCtrl.text.trim()) == null))) {
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
      _formError = null;
      _planDriverId = '';
      _planVehicleId = '';
      _planOverlapPreview = null;
      _phoneSurface = _WorkspacePhoneSurface.agenda;
    });
  }

  Future<void> _saveDraft() async {
    final draft = _draft;
    if (draft == null || _saving) return;
    final fromValue = _fromAddress.value;
    final toValue = _toAddress.value;
    final returnFromValue = _returnFromAddress.value;
    final returnToValue = _returnToAddress.value;
    final from = fromValue.displayText.trim();
    final to = toValue.displayText.trim();
    if (from.isEmpty || to.isEmpty) {
      setState(() => _formError = kCompanyAgendaRouteRequired.of(_lang));
      return;
    }
    if (_planPickupLocal == null) {
      setState(() => _formError = kCompanyAgendaPickupRequired.of(_lang));
      return;
    }
    if (_roundtripChoice != CompanyRoundtripChoice.single &&
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
        'agenda-${draft.customer.customerId}-${_planPickupLocal!.toUtc().toIso8601String()}';
    setState(() {
      _saving = true;
      _formError = null;
    });
    try {
      final filled = draft.copyWith(
        pickupLocal: _planPickupLocal,
        fromAddress: from,
        toAddress: to,
        fromLat: fromSelected ? fromValue.lat : null,
        fromLon: fromSelected ? fromValue.lon : null,
        fromPlaceId: fromSelected ? (fromValue.placeId ?? '') : '',
        toLat: toSelected ? toValue.lat : null,
        toLon: toSelected ? toValue.lon : null,
        toPlaceId: toSelected ? (toValue.placeId ?? '') : '',
        clearFromCoords: !fromSelected,
        clearToCoords: !toSelected,
        passengers: _passengers,
        priceText: _manualPriceLocked
            ? _priceCtrl.text
            : (_planQuoteResult?.priceAvailable == true
                  ? (_planQuoteResult!.priceInclVat?.toString() ??
                        _priceCtrl.text)
                  : _priceCtrl.text),
        durationText: _durationCtrl.text,
        distanceKm: _planQuoteResult?.distanceKm,
        pricingSource: _manualPriceLocked
            ? 'manual'
            : (_planQuoteResult?.pricingSource ?? ''),
        currency: _planQuoteResult?.currency ?? 'EUR',
        durationRouteMin: _planQuoteResult?.durationMin,
        driverId: _planDriverId.trim(),
        vehicleId: _planVehicleId.trim(),
        rideOptions: _rideOptions,
        fixedPriceSnapshot: _fixedPriceSnapshot,
        publicNote: _noteCtrl.text,
        idempotencyKey: key,
        roundtripChoice: _roundtripChoice,
        returnPickupLocal: _returnPickupLocal,
        returnFromAddress: returnFromValue.displayText.trim(),
        returnToAddress: returnToValue.displayText.trim(),
        returnDurationText: _returnDurationCtrl.text,
        returnDriverId: _planReturnDriverId,
        returnVehicleId: _planReturnVehicleId,
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
      if (ride.assignmentWarning.trim().isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${kCompanyAgendaSavedUnassigned.of(_lang)} ${companyAgendaAssignmentExceptionText(CompanyAgendaException(ride.assignmentWarning), _lang)}',
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
    if (!tablet || size.height <= size.width || _view != CompanyAgendaView.week) {
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
          title: Text(kCompanyCustomersTitle.of(_lang)),
          leading: phone && _phoneSurface != _WorkspacePhoneSurface.customers
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    setState(() {
                      if (_phoneSurface == _WorkspacePhoneSurface.form) {
                        _phoneSurface = _WorkspacePhoneSurface.customers;
                      } else if (_phoneSurface ==
                          _WorkspacePhoneSurface.detail) {
                        _phoneSurface = _WorkspacePhoneSurface.customers;
                      } else {
                        _phoneSurface = _WorkspacePhoneSurface.customers;
                      }
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
            TextButton(
              key: kCompanyAgendaPlanRideKey,
              onPressed: () => _beginPlan(),
              child: Text(kCompanyAgendaPlanRide.of(_lang)),
            ),
          ],
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= kCompanyOpsWorkspaceDesktopWidth) {
                return _desktopBody();
              }
              if (constraints.maxWidth >= kCompanyOpsWorkspaceTabletWidth) {
                return _tabletBody();
              }
              return _phoneBody();
            },
          ),
        ),
        bottomNavigationBar: phone && _draft == null
            ? NavigationBar(
                selectedIndex: _phoneSurface == _WorkspacePhoneSurface.agenda
                    ? 1
                    : 0,
                destinations: [
                  NavigationDestination(
                    icon: const Icon(Icons.people_outline),
                    label: kCompanyAgendaCustomersTab.of(_lang),
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: kCompanyAgendaTitle.of(_lang),
                  ),
                ],
                onDestinationSelected: (index) {
                  setState(() {
                    _phoneSurface = index == 1
                        ? _WorkspacePhoneSurface.agenda
                        : _WorkspacePhoneSurface.customers;
                  });
                  if (index == 1) _reloadAgenda(force: true);
                },
              )
            : null,
      ),
    );
  }

  Widget _desktopBody() {
    final showDossier = _draft != null || !_dossierCollapsed;
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
          SizedBox(
            width: kCompanyOpsWorkspaceDossierPaneWidth,
            child: _detailPane(),
          )
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

  Widget _tabletBody() {
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
            child: Material(
              elevation: 3,
              child: _customerList(compact: true),
            ),
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
                    side: BorderSide(
                      color: companyOpsCurrentScheme().outline,
                    ),
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
                    side: BorderSide(
                      color: companyOpsCurrentScheme().outline,
                    ),
                  ),
                  onPressed: _pickAnchorDate,
                  child: Text(kCompanyAgendaPickDate.of(_lang)),
                ),
                if (chrome == _AgendaChrome.desktop)
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
                if (tablet)
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
                    onSelectRide: (ride) =>
                        _openBooking(companyAgendaRideDetailId(ride), ride: ride),
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

  Widget _rideForm() {
    final draft = _draft;
    if (draft == null) return const SizedBox.shrink();
    return Column(
      key: kCompanyAgendaRideFormKey,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${kCompanyAgendaPlanRide.of(_lang)} · ${draft.customer.displayName}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                CompanyDateTimeFields(
                  fieldId: 'agenda_pickup',
                  language: _lang,
                  value: _planPickupLocal,
                  onChanged: (next) {
                    setState(() {
                      _planPickupLocal = next;
                      if (next != null) {
                        _agendaMoment = next;
                        _draft = draft.copyWith(pickupLocal: next);
                      }
                    });
                    unawaited(_previewPlanOverlap());
                    _schedulePlanQuote();
                  },
                ),
                const SizedBox(height: 12),
                CompanyTripRouteFields(
                  language: _lang,
                  pickup: _fromAddress,
                  dropoff: _toAddress,
                  rideOptions: _rideOptions,
                  onRideOptionsChanged: (next) {
                    setState(() {
                      _rideOptions = next;
                      _fixedPriceSnapshot = null;
                      _planQuoteResult = null;
                    });
                    _schedulePlanQuote();
                  },
                  savedAddresses: draft.customer.addresses,
                  pickupInputKey: kCompanyAgendaFromFieldKey,
                  dropoffInputKey: kCompanyAgendaToFieldKey,
                  pickupLabel: kCompanyAgendaPickup.of(_lang),
                  dropoffLabel: kCompanyAgendaDropoff.of(_lang),
                  onRouteIdentityChanged: _onPlanAddressChanged,
                  showReturnAirportFields:
                      _roundtripChoice != CompanyRoundtripChoice.single,
                ),
                const SizedBox(height: 12),
                CompanyRoundtripFields(
                  language: _lang,
                  choice: _roundtripChoice,
                  onChoiceChanged: _onRoundtripChoiceChanged,
                  returnPickup: _returnPickupLocal,
                  onReturnPickupChanged: (next) {
                    setState(() => _returnPickupLocal = next);
                    unawaited(_previewPlanOverlap());
                  },
                  returnFrom: _returnFromAddress,
                  returnTo: _returnToAddress,
                  savedAddresses: draft.customer.addresses,
                  returnDuration: _returnDurationCtrl,
                  onReturnDurationChanged: (_) => _onPlanAssignmentInputsChanged(),
                  extra: _roundtripChoice == CompanyRoundtripChoice.splitNoWait
                      ? Column(
                          children: [
                            const SizedBox(height: 8),
                            CompanyAssignmentSearchField(
                              kind: CompanyAssignmentChoiceKind.driver,
                              language: _lang,
                              label: kCompanyRoundtripReturnDriver.of(_lang),
                              selectedId: _planReturnDriverId,
                              enabled:
                                  !_saving &&
                                  !_fleetLoading &&
                                  _fleetError == null,
                              choices: companyAssignmentDriverChoices(
                                drivers: _drivers,
                                language: _lang,
                                unassignedLabel:
                                    kCompanyAgendaUnassignedLane.of(_lang),
                              ),
                              onSelected: (id) {
                                setState(() => _planReturnDriverId = id);
                                unawaited(_previewPlanOverlap());
                              },
                            ),
                            const SizedBox(height: 8),
                            CompanyAssignmentSearchField(
                              kind: CompanyAssignmentChoiceKind.vehicle,
                              language: _lang,
                              label: kCompanyRoundtripReturnVehicle.of(_lang),
                              selectedId: _planReturnVehicleId,
                              enabled:
                                  !_saving &&
                                  !_fleetLoading &&
                                  _fleetError == null,
                              choices: companyAssignmentVehicleChoices(
                                vehicles: _vehicles,
                                language: _lang,
                                unassignedLabel:
                                    kCompanyAgendaUnassignedLane.of(_lang),
                                passengers: _passengers,
                              ),
                              onSelected: (id) {
                                setState(() => _planReturnVehicleId = id);
                                unawaited(_previewPlanOverlap());
                              },
                            ),
                          ],
                        )
                      : null,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(kCompanyAgendaPassengers.of(_lang)),
                    const Spacer(),
                    IconButton(
                      onPressed: _passengers > 1
                          ? () {
                              setState(() => _passengers -= 1);
                              _schedulePlanQuote();
                            }
                          : null,
                      icon: const Icon(Icons.remove),
                    ),
                    Text('$_passengers'),
                    IconButton(
                      onPressed: () {
                        setState(() => _passengers += 1);
                        _schedulePlanQuote();
                      },
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                CompanyRideOptionsForm(
                  language: _lang,
                  value: _rideOptions,
                  showAirportRouteFields: false,
                  showReturnAirportFields: false,
                  onChanged: (next) {
                    setState(() => _rideOptions = next);
                    _schedulePlanQuote();
                  },
                ),
                const SizedBox(height: 8),
                CompanyPlanQuotePanel(
                  language: _lang,
                  loading: _planQuoteLoading,
                  result: _planQuoteResult,
                  error: _planQuoteError,
                  onRetry: () => unawaited(_refreshPlanQuote(force: true)),
                ),
                if (_fixedPriceSnapshot != null) ...[
                  const SizedBox(height: 8),
                  CompanyFixedPriceBreakdown(
                    language: _lang,
                    snapshot: _fixedPriceSnapshot!,
                  ),
                ],
                const SizedBox(height: 8),
                TextField(
                  controller: _noteCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: kCompanyCustomerQuoteDescription.of(_lang),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  kCompanyCustomerQuotePublicDescriptionHint.of(_lang),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                CompanyInternalRatesPanel(
                  language: _lang,
                  options: _rideOptions,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _priceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: kCompanyAgendaPrice.of(_lang),
                  ),
                ),
                if (_roundtripChoice != CompanyRoundtripChoice.single) ...[
                  const SizedBox(height: 6),
                  Text(
                    kCompanyRoundtripPriceCovers.of(_lang),
                    style: Theme.of(context).textTheme.bodySmall,
                    softWrap: true,
                  ),
                ],
                const SizedBox(height: 8),
                InputDecorator(
                  decoration: InputDecoration(
                    labelText: kCompanyAgendaDuration.of(_lang),
                    border: const OutlineInputBorder(),
                  ),
                  child: Text(
                    _planQuoteResult?.durationMin != null
                        ? '${_planQuoteResult!.durationMin} min'
                        : (_durationCtrl.text.trim().isEmpty
                              ? '—'
                              : '${_durationCtrl.text.trim()} min'),
                  ),
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
                const SizedBox(height: 8),
                if (_planChoicesStatus != null) ...[
                  Text(
                    _planChoicesStatus!,
                    key: kCompanyAgendaPlanChoicesStatusKey,
                  ),
                  const SizedBox(height: 8),
                ],
                CompanyAssignmentSearchField(
                  key: kCompanyAgendaPlanDriverKey,
                  kind: CompanyAssignmentChoiceKind.driver,
                  language: _lang,
                  label: kCompanyAgendaDriver.of(_lang),
                  selectedId: _planDriverId,
                  enabled: !_saving && !_fleetLoading && _fleetError == null,
                  choices: companyAssignmentDriverChoices(
                    drivers: _drivers,
                    language: _lang,
                    unassignedLabel: kCompanyAgendaUnassignedLane.of(_lang),
                  ),
                  onSelected: (id) {
                    setState(() => _planDriverId = id);
                    unawaited(_previewPlanOverlap());
                  },
                ),
                const SizedBox(height: 8),
                CompanyAssignmentSearchField(
                  key: kCompanyAgendaPlanVehicleKey,
                  kind: CompanyAssignmentChoiceKind.vehicle,
                  language: _lang,
                  label: kCompanyAgendaVehicle.of(_lang),
                  selectedId: _planVehicleId,
                  enabled: !_saving && !_fleetLoading && _fleetError == null,
                  choices: companyAssignmentVehicleChoices(
                    vehicles: _vehicles,
                    language: _lang,
                    unassignedLabel: kCompanyAgendaUnassignedLane.of(_lang),
                    passengers: _passengers,
                  ),
                  onSelected: (id) {
                    setState(() => _planVehicleId = id);
                    unawaited(_previewPlanOverlap());
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  kCompanyAgendaOnlineNowHint.of(_lang),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (_planOverlapPreview != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _planOverlapPreview!,
                    key: kCompanyAgendaOverlapPreviewKey,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                if (_formError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _formError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                key: kCompanyAgendaSaveRideKey,
                onPressed: _saving ? null : _saveDraft,
                child: Text(kCompanyAgendaSave.of(_lang)),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                key: kCompanyAgendaCancelRideKey,
                onPressed: _saving ? null : _cancelDraft,
                child: Text(kCompanyAgendaCancel.of(_lang)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
