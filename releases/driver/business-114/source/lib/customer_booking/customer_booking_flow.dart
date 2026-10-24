import 'package:fluxidi_tracking/customer_booking/official_address_lookup.dart';
import 'package:fluxidi_tracking/customer_booking/official_address_payload.dart';
import 'customer_booking_airport_window.dart';
import 'customer_booking_stable_vehicle_space.dart';
import 'reliable_choice_api.dart' show ReliableChoiceApiV1;
import 'customer_reliable_choice_panel.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'customer_reliable_choice.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_quote_preference.dart';
import 'package:fluxidi_tracking/airport/airport_catalog_repository.dart';
import 'package:fluxidi_tracking/airport/airport_catalog_search.dart';
import 'package:fluxidi_tracking/airport/airport_selector.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_plan_airport_cards.dart';
import 'package:fluxidi_tracking/company/company_plan_quote.dart';
import 'package:fluxidi_tracking/company/company_plan_ride_mode.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_quote_wire.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_route_geometry.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_route_map.dart';
import 'package:fluxidi_tracking/company/company_plan_vehicle_type.dart';
import 'package:fluxidi_tracking/company/company_ride_options.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_addresses.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_airport_fare.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_book_payload.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_book_result.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_billing.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_checkout.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_company_pick.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_confirm.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_assigned_driver.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_company_vehicles.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_vehicle_cards.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_vehicle_offers.dart';
import 'package:fluxidi_tracking/company/company_driver_agenda_style.dart';
import 'package:fluxidi_tracking/company/company_plan_when.dart';
import 'package:fluxidi_tracking/company/company_form_date_time.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_entry.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_home_notice.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_keys.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_labels.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_layout.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_map_sheet.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_payment_page.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_price_block.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_quote.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_submit.dart';
import 'package:fluxidi_tracking/customer_booking/customer_confirmed_location.dart';
import 'package:fluxidi_tracking/nearby/public_company_presentation.dart';
import 'package:fluxidi_tracking/customer_bookings_store.dart';
import 'package:fluxidi_tracking/customer_profile_store.dart';
import 'package:fluxidi_tracking/customer_session_store.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/customer_theme_store.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_field.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';
import 'package:fluxidi_tracking/limousine/limousine_current_location.dart';
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1a_ux.dart';
import 'package:fluxidi_tracking/payment/booking_billing_identity.dart';
import 'package:fluxidi_tracking/payment/booking_billing_identity_form.dart';
import 'package:fluxidi_tracking/payment/booking_payment_options.dart';
import 'package:fluxidi_tracking/payment/payment_booking_selection.dart';

const int kCustomerBookingMaxStops = 10;

enum CustomerBookingReturnKind { oneWay, noWait, wait }

class CustomerBookingFlow extends StatefulWidget {
  const CustomerBookingFlow({
    super.key,
    required this.entry,
    this.bookingBaseUrl,
    this.language,
    this.lookup,
    this.locationPlatform,
    this.quoteClient,
    this.routeGeometryClient,
    this.autoResolveGps = true,
    this.onGoToStartPage,
    this.profile,
    this.profileGet,
    this.checkoutOpener,
    this.hostedCheckout,
    this.companyPicker,
    this.reliableChoiceApi,
  });

  final CustomerBookingEntryContext entry;
  final String? bookingBaseUrl;
  final AppLanguage? language;
  final LimousinePlaceLookup? lookup;
  final LimousineCurrentLocationPlatform? locationPlatform;
  final CustomerBookingQuoteClient? quoteClient;
  final CustomerBookingRouteGeometryClient? routeGeometryClient;
  final bool autoResolveGps;
  final WidgetBuilder? onGoToStartPage;
  final CustomerProfile? profile;
  final CustomerBookingProfileGet? profileGet;
  final Future<bool> Function(String url)? checkoutOpener;
  final Future<bool> Function(CustomerBookingCheckoutPlan plan)? hostedCheckout;
  final CustomerBookingCompanyPicker? companyPicker;
  /// Explicit local integration capability. Default public booking/payment
  /// behavior stays unchanged until the server runtime is configured.
  final ReliableChoiceApiV1? reliableChoiceApi;

  @override
  State<CustomerBookingFlow> createState() => _CustomerBookingFlowState();
}

class _CustomerBookingFlowState extends State<CustomerBookingFlow> {
  late CustomerBookingEntryContext _entry;
  late final LimousinePlaceLookup _lookup;
  late final CustomerBookingQuoteClient _quoteClient;
  late CompanyPlanQuoteCoordinator _quotes;
  late final LimousineAddressFieldController _pickup;
  late final LimousineAddressFieldController _dropoff;
  late final LimousineAddressFieldController _returnPickup;
  late final LimousineAddressFieldController _returnDropoff;
  late final TextEditingController _flightCtrl;
  late final TextEditingController _arrivalMarginCtrl;
  late final TextEditingController _pickupAfterCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _airportSearchCtrl;
  late final BookingBillingIdentityControllers _billing;
  final List<LimousineAddressFieldController> _stops =
      <LimousineAddressFieldController>[];
  final List<LimousineAddressFieldController> _returnStops =
      <LimousineAddressFieldController>[];

  bool _airportMode = false;
  bool _toAirport = true;
  bool _browseCatalog = false;
  bool _whenNow = true;
  String? _asapCapabilitiesPartner;
  String _asapBookingMode='unavailable';
  int _capabilitiesSeq=0;
  bool get _usesReliableChoice => _whenNow && _asapBookingMode=='reliable_choice' && _asapCapabilitiesPartner==_entry.company.routingPartnerId;
  bool get _usesManualAsap => _whenNow && _asapBookingMode=='manual' && _asapCapabilitiesPartner==_entry.company.routingPartnerId;
  bool _submitting = false;
  final http.Client _reliableHttp=http.Client();
  ReliableChoiceApiV1? _activeReliableApi;
  String? _reliableSelectionToken;
  bool _allowCompatibleReplacement=false;
  bool _requestDispatcherReview=false;
  List<Map<String,dynamic>> _reliableRows=[];
  bool _confirmInFlight = false;
  bool _bookPosted = false;
  bool _bookUncertain = false;
  int? _minPrepMinutes;
  double? _airportMinLeadHours;
  DateTime? _autoRefreshedExpiry;
  bool _gpsBusy = false;
  bool _gpsFallback = false;
  String _countryCode = 'BE';
  String _airportQuery = '';
  AirportCatalogAirport? _airport;
  CustomerBookingReturnKind _returnKind = CustomerBookingReturnKind.oneWay;
  CompanyPlanVehicleType _vehicle = CompanyPlanVehicleType.sedan;
  CompanyPlanVehicleCategory? _vehicleCategory;
  CustomerProfile? _profile;
  List<Map<String, dynamic>> _companyVehicles = const <Map<String, dynamic>>[];
  String? _quotePreferenceVehicleId;
  String? _quotePreferenceCompany;
  List<Map<String, dynamic>> _companyDrivers = const <Map<String, dynamic>>[];
  PublicCompanyPresentation _presentation = const PublicCompanyPresentation();
  CustomerBookingPublicContact _publicContact =
      const CustomerBookingPublicContact();

  /// Never starts from the demo capability: in the real customer flow an
  /// unverified company may not be shown an online checkout it cannot honour.
  BookingPaymentCapability _paymentCapability =
      const BookingPaymentCapability.unavailable();

  /// True when the company profile request itself failed, as opposed to a
  /// profile that simply carries no payment settings.
  bool _paymentCapabilityLoadFailed = false;
  bool _vehiclesLoading = false;
  bool _vehiclesFailed = false;
  bool _businessRide = false;
  bool _pickupOwned = false;
  String? _submitError;
  int _passengers = 1;
  int _bags = 0;
  int _waitMin = 30;
  DateTime? _pickupAt;
  DateTime? _returnAt;
  DateTime? _flightAt;
  int _pickupAfterMin = 0;
  int _arrivalMarginMin = kCompanyPlanDefaultAirportArrivalMarginMin;
  bool _taxiPickupManual = false;
  String? _selectedVehicleId;
  String? _selectedReturnVehicleId;
  List<Map<String,dynamic>> _reliableReturnRows=[];
  CustomerBookingAssignedDriver _assignedDriver =
      const CustomerBookingAssignedDriver();
  CustomerBookingAssignedDriver _assignedReturnDriver =
      const CustomerBookingAssignedDriver();
  CustomerBookingAvailabilitySnapshot _availability =
      const CustomerBookingAvailabilitySnapshot();
  CustomerBookingAvailabilitySnapshot _returnAvailability =
      const CustomerBookingAvailabilitySnapshot();
  int _availabilitySeq = 0;
  bool _availabilityLoading = false;
  bool _returnAvailabilityLoading = false;
  bool _editingContact = false;
  bool _compactCountsOpen = false;
  bool _retainVehicleSpace = false;
  String _companyLogoUrl = '';
  int _quoteSeq = 0;
  CompanyPlanQuoteResult? _quote;
  CompanyPlanQuoteRequest? _quoteRequest;
  String? _quoteError;
  bool _quoteLoading = false;
  String? _successId;
  Timer? _quoteDebounce;
  String _idempotencyKey = '';
  Map<String, dynamic>? _pendingFinancialAcceptance;
  String get _financialRecoveryOwner => (_profile?.customerId.trim().isNotEmpty ?? false)
      ? 'customer:${_profile!.customerId}'
      : 'guest_device';
  int _stopSeq = 0;
  final ScrollController _formScroll = ScrollController();
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  final ValueNotifier<double> _sheetExtentNotifier = ValueNotifier<double>(
    0.50,
  );
  final FocusNode _pickupFocus = FocusNode();
  final FocusNode _dropoffFocus = FocusNode();
  ScrollController? _sheetScroll;
  double _sheetExtent = 0.50;
  double _snappedSheetExtent = 0.50;
  bool _sheetAnimating = false;
  bool _airportPickerOpen = false;
  int? _geometryDurationMin;
  num? _geometryDistanceKm;

  AppLanguage get _language => widget.language ?? appConfig.currentLanguage;

  CustomerThemePalette get _palette =>
      paletteForCustomerTheme(customerThemeNotifier.value);

  LimousineUxTokens get _tokens => LimousineUxTokens.fromCustomer(_palette);

  String _t(LocalizedText text) => text.of(_language);

  bool get _contextInvalid =>
      _entry.lockCompany &&
      !_entry.company.hasPartner &&
      !_entry.company.hasCompany;

  bool get _showAirplane => _airportMode;

  bool get _allowsWait => !_airportMode;

  int? get _rideDurationMin {
    return companyPlanCanonicalDurationMin(
      quoteDurationMin: _quote?.durationMin,
      geometryDurationMin: _geometryDurationMin,
    );
  }

  bool get _hasChosenCompany => customerBookingCompanyIsChosen(_entry.company);

  CompanyRideOptions get _options {
    return CompanyRideOptions(
      service: _airportMode
          ? 'airport'
          : (_entry.kind == CustomerBookingKind.event
                ? 'event'
                : _entry.kind == CustomerBookingKind.stay
                ? 'hotel'
                : 'passenger'),
      bags: _bags,
      waitMin: _airportMode
          ? 0
          : (_returnKind == CustomerBookingReturnKind.wait ? _waitMin : 0),
      flightNumber: _flightCtrl.text.trim().toUpperCase(),
      airportDirection: _airportMode
          ? (_toAirport ? 'to_airport' : 'from_airport')
          : '',
      airportIata: _airport?.iata ?? '',
      returnAirportIata: _airportMode ? (_airport?.iata ?? '') : '',
      airportCountry: _airport?.countryCode ?? '',
      flightAt: _flightAt?.toIso8601String() ?? '',
      pickupAfterMin: _pickupAfterMin,
      arrivalMarginMin: _arrivalMarginMin,
      pickupArrangement: !_toAirport && _pickupAfterMin > 0
          ? 'after_landing'
          : (_airportMode && !_toAirport ? 'scheduled' : ''),
      vehicleType: _vehicleCategory == null
          ? companyPlanVehicleTypeWire(_vehicle)
          : companyPlanVehicleCategoryWire(_vehicleCategory!),
      // Airport fixed-fare rules match comfort, same as AirportPage.
      // Premium vehicle choice stays on vehicle_id, not on the fare tier.
      tier: _airportMode
          ? 'comfort'
          : (_vehicleCategory == CompanyPlanVehicleCategory.premium
                ? 'premium'
                : ''),
    );
  }

  @override
  void initState() {
    super.initState();
    _entry = widget.entry;
    _lookup = widget.lookup ?? OfficialAddressLookup(operatorSession: false);
    _quoteClient =
        widget.quoteClient ??
        CustomerBookingQuoteClient(bookingBaseUrl: widget.bookingBaseUrl ?? '');
    _quotes = CompanyPlanQuoteCoordinator(transport: _runQuote);
    _idempotencyKey =
        'cust-${DateTime.now().microsecondsSinceEpoch}-${_entry.kind.name}';
    _flightCtrl = TextEditingController();
    _arrivalMarginCtrl = TextEditingController(
      text: '$kCompanyPlanDefaultAirportArrivalMarginMin',
    );
    _pickupAfterCtrl = TextEditingController();
    _nameCtrl = TextEditingController();
    _phoneCtrl = TextEditingController();
    _emailCtrl = TextEditingController();
    _airportSearchCtrl = TextEditingController();
    _billing = BookingBillingIdentityControllers();
    _pickup = _makeAddress('pickup');
    _dropoff = _makeAddress('dropoff');
    _returnPickup = _makeAddress('return_pickup');
    _returnDropoff = _makeAddress('return_dropoff');
    limousineBindSiblingSearchBias(field: _pickup, sibling: _dropoff);
    limousineBindSiblingSearchBias(field: _dropoff, sibling: _pickup);
    limousineBindSiblingSearchBias(
      field: _returnPickup,
      sibling: _returnDropoff,
    );
    limousineBindSiblingSearchBias(
      field: _returnDropoff,
      sibling: _returnPickup,
    );
    _airportMode = _entry.kind == CustomerBookingKind.airport;
    _airportPickerOpen = _entry.airport == null;
    _toAirport = _entry.toAirport;
    _airport = _entry.airport;
    _companyVehicles = List<Map<String, dynamic>>.from(_entry.company.vehicles);
    _companyLogoUrl = customerBookingLogoUrlIsRenderable(_entry.company.logoUrl)
        ? _entry.company.logoUrl.trim()
        : '';
    _profile = widget.profile;
    _syncVehicleFromFleet();
    if (_airport != null) {
      _countryCode = _airport!.countryCode;
      _applyAirport(_airport!, browse: false, notify: false);
    }
    final pickup = _entry.pickup;
    if (pickup != null && pickup.displayAddress.isNotEmpty) {
      _pickup.acceptCopy(customerBookingAddressFromPlace(pickup));
      _pickupOwned = true;
    }
    final dest = _entry.destination;
    if (dest != null && dest.displayAddress.isNotEmpty) {
      _dropoff.acceptCopy(customerBookingAddressFromPlace(dest));
    }
    final scheduled = dest?.startsAt ?? pickup?.startsAt;
    if (scheduled != null) {
      _whenNow = false;
      _pickupAt = scheduled;
    }
    _pickup.addListener(_onPickupChanged);
    _dropoff.addListener(_onDraftChanged);
    _returnPickup.addListener(_onDraftChanged);
    _returnDropoff.addListener(_onDraftChanged);
    _sheetController.addListener(_onSheetControllerTick);
    appLanguageNotifier.addListener(_onAppLanguageChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_loadProfile().then((_) => _refreshQuote()));
    });
    unawaited(_loadProfile());
    unawaited(_loadCompanyVehicles());
    if (widget.autoResolveGps &&
        (_entry.kind == CustomerBookingKind.taxi ||
            (_entry.kind == CustomerBookingKind.business && !_airportMode))) {
      unawaited(_resolveGpsAfterProfile());
    }
  }

  Future<void>? _profileLoad;
  Timer? _profileGpsWaitTimer;
  Completer<void>? _profileGpsWaitCompletion;

  Future<void> _resolveGpsAfterProfile() async {
    // A saved profile address must win over a later GPS fix. Wait for the
    // profile itself; only fall back to GPS when the pickup is still vacant.
    final waiting = Completer<void>();
    _profileGpsWaitCompletion = waiting;
    void finishWait() {
      if (!waiting.isCompleted) waiting.complete();
    }
    _profileGpsWaitTimer = Timer(const Duration(milliseconds: 250), finishWait);
    unawaited(_loadProfile().then<void>((_) => finishWait(), onError: (Object _, StackTrace __) => finishWait()));
    await waiting.future;
    _profileGpsWaitTimer?.cancel();
    _profileGpsWaitTimer = null;
    _profileGpsWaitCompletion = null;
    if (!mounted) return;
    if (_pickupOwned || !customerBookingPickupIsVacant(_pickup.value)) return;
    await _resolveGps();
  }

  LimousineAddressFieldController _makeAddress(String id) {
    return LimousineAddressFieldController(
      lookup: _lookup,
      fieldId: id,
      language: _language.name,
    );
  }

  List<CompanyPlanVehicleCategory> get _bookableCategories {
    return customerBookingBookableCategories(
      _companyVehicles,
      passengers: _passengers,
    );
  }

  void _syncVehicleFromFleet() {
    final categories = _bookableCategories;
    if (categories.isEmpty) {
      _vehicleCategory = null;
      return;
    }
    if (_vehicleCategory == null || !categories.contains(_vehicleCategory)) {
      _vehicleCategory = categories.first;
      _vehicle = companyPlanVehicleTypeForCategory(_vehicleCategory!);
    }
  }

  Future<void> _loadCompanyVehicles() async {
    if (!_hasChosenCompany) return;
    final partnerId = _entry.company.routingPartnerId;
    setState(() {
      _vehiclesLoading = _companyVehicles.isEmpty;
      _vehiclesFailed = false;
    });
    try {
      final snapshot = await fetchCustomerBookingCompanySnapshot(
        bookingBaseUrl: widget.bookingBaseUrl ?? _quoteClient.bookingBaseUrl,
        partnerId: _entry.company.routingPartnerId,
        httpGet: widget.profileGet,
      );
      if (!mounted || partnerId != _entry.company.routingPartnerId) return;
      setState(() {
        _publicContact = customerBookingPublicContactFromProfile(
          snapshot.profile,
        );
        _companyVehicles = snapshot.vehicles;
        _companyDrivers = snapshot.drivers;
        _presentation = publicCompanyPresentationFrom(
          snapshot.profile,
          language: _language,
        );
        if (snapshot.companyName.isNotEmpty &&
            _entry.company.companyName.trim().isEmpty) {
          _entry = _entry.copyWith(
            company: _entry.company.copyWith(companyName: snapshot.companyName),
          );
        }
        try {
          final published = customerBookingPublishedLogoUrl(snapshot.profile);
          final fromEntry = _entry.company.logoUrl.trim();
          _companyLogoUrl = published.isNotEmpty
              ? published
              : (customerBookingLogoUrlIsRenderable(fromEntry)
                    ? fromEntry
                    : '');
        } catch (_) {
          _companyLogoUrl =
              customerBookingLogoUrlIsRenderable(_entry.company.logoUrl)
              ? _entry.company.logoUrl.trim()
              : '';
        }
        _paymentCapability = snapshot.payment;
        _paymentCapabilityLoadFailed =
            snapshot.payment.projectionStatus ==
            BookingPaymentCapabilityStatus.loadFailed;
        _vehiclesLoading = false;
        _vehiclesFailed = false;
        _syncVehicleFromFleet();
        _preselectSoleBookableVehicle(inbound: false);
        _minPrepMinutes = customerBookingMinPrepMinutes(snapshot.profile);
        final airportHours = num.tryParse(
          '${snapshot.profile['airport_fixed_fare_min_lead_hours']}',
        );
        _airportMinLeadHours =
            airportHours != null && airportHours.isFinite && airportHours > 0
            ? airportHours.toDouble()
            : null;
        if (_airportMode && _airportMinLeadHours != null && _whenNow) {
          _whenNow = false;
          _pickupAt = null;
        }
      });
      _onDraftChanged();
    } catch (err) {
      if (!mounted) return;
      // A failed read is not the same as a company without payment settings:
      // keep the capability unknown-but-unavailable so the payment screen can
      // say the settings could not be loaded instead of silently offering
      // only the in-vehicle option.
      debugPrint(
        '[CUSTOMER_BOOKING][COMPANY_PROFILE] ok=false reason=${err.runtimeType}',
      );
      setState(() {
        _vehiclesLoading = false;
        _vehiclesFailed = _companyVehicles.isEmpty;
        _paymentCapabilityLoadFailed = true;
        _paymentCapability = const BookingPaymentCapability.unavailable();
      });
    }
  }

  Future<void> _loadProfile() {
    return _profileLoad ??= _loadProfileOnce();
  }

  Future<void> _loadProfileOnce() async {
    try {
      final profile =
          widget.profile ?? await CustomerProfileStore.instance.load();
      if (!mounted) return;
      if (profile == null) {
        final pending = await _quoteClient.pendingAcceptance(_entry, _financialRecoveryOwner);
        if (mounted && pending != null) setState(() => _pendingFinancialAcceptance = pending);
        return;
      }
      setState(() {
        _profile = profile;
        if (_nameCtrl.text.trim().isEmpty) _nameCtrl.text = profile.name;
        if (_phoneCtrl.text.trim().isEmpty) {
          _phoneCtrl.text = customerBookingInternationalPhone(
            phone: profile.phone,
            phoneCountry: profile.phoneCountry,
          );
        }
        if (_emailCtrl.text.trim().isEmpty) _emailCtrl.text = profile.email;
        customerBookingPrefillBillingFromProfile(_billing, profile);
      });
      if (!_airportMode || _toAirport) {
        _applyProfileAddressIfVacant();
      }
      final pending = await _quoteClient.pendingAcceptance(_entry, _financialRecoveryOwner);
      if (mounted && pending != null) setState(() => _pendingFinancialAcceptance = pending);
    } catch (_) {}
  }

  int _pickupGeocodeSeq = 0;
  int _pickupInspectSeq = 0;

  bool get _pickupNeedsConfirm => customerBookingPickupNeedsConfirm(_pickup);

  Future<void> _geocodePickupIfNeeded() async {
    if (customerBookingPickupIsVacant(_pickup.value)) return;
    if (_pickup.locationUserConfirmed && _pickup.value.hasCoordinates) return;
    final seq = ++_pickupGeocodeSeq;
    final query = _pickup.value.displayText.trim().isEmpty
        ? _pickup.textController.text.trim()
        : _pickup.value.displayText.trim();
    try {
      final stored = await CustomerConfirmedLocationStore.instance
          .readFor(query)
          .timeout(const Duration(milliseconds: 200), onTimeout: () => null);
      if (!mounted || seq != _pickupGeocodeSeq) return;
      if (stored != null &&
          stored.isUsable &&
          (customerConfirmedLocationMatches(
                _pickup.value.displayText,
                stored,
              ) ||
              customerConfirmedLocationMatches(query, stored))) {
        _pickup.acceptCopy(
          customerBookingAddressFromText(
            stored.label,
            latitude: stored.latitude,
            longitude: stored.longitude,
          ),
          userConfirmed: true,
        );
        setState(() => _gpsFallback = false);
        _onDraftChanged();
        return;
      }
    } catch (_) {}
    if (!mounted || seq != _pickupGeocodeSeq) return;
    await customerBookingGeocodeIfNeeded(_pickup);
    if (!mounted || seq != _pickupGeocodeSeq) return;
    setState(() {});
    _onDraftChanged();
  }

  void _applyOwnedPickup(LimousineAddressValue address) {
    final label = address.displayText.trim().isNotEmpty
        ? address.displayText.trim()
        : address.canonicalLabel.trim();
    final profile = _profile ?? widget.profile;
    final needsConfirm =
        profile != null && customerProfileAddressNeedsMapConfirm(profile);
    final next = customerBookingAddressFromText(
      label,
      latitude: address.lat,
      longitude: address.lon,
    );
    _pickup.acceptCopy(
      next,
      userConfirmed: next.hasCoordinates && !needsConfirm,
    );
    if (needsConfirm) {
      _pickup.locationNeedsConfirm = true;
    }
    setState(() {
      _pickupOwned = true;
      _gpsFallback = false;
      _submitError = null;
    });
    _onDraftChanged();
    if (next.hasCoordinates) {
      return;
    }
    unawaited(_resolveOwnedPickup(label));
  }

  Future<void> _resolveOwnedPickup(String label) async {
    await _restoreConfirmedPickup(label);
    if (!mounted) return;
    if (_pickup.locationUserConfirmed && _pickup.value.hasCoordinates) {
      setState(() {});
      _onDraftChanged();
      return;
    }
    await _geocodePickupIfNeeded();
  }

  Future<void> _restoreConfirmedPickup(String label) async {
    try {
      final stored = await CustomerConfirmedLocationStore.instance
          .readFor(label)
          .timeout(const Duration(milliseconds: 200), onTimeout: () => null);
      if (!mounted || stored == null || !stored.isUsable) return;
      if (!customerConfirmedLocationMatches(
            _pickup.value.displayText,
            stored,
          ) &&
          !customerConfirmedLocationMatches(label, stored)) {
        return;
      }
      _pickup.acceptCopy(
        customerBookingAddressFromText(
          stored.label,
          latitude: stored.latitude,
          longitude: stored.longitude,
        ),
        userConfirmed: true,
      );
      setState(() => _gpsFallback = false);
      _onDraftChanged();
    } catch (_) {}
  }

  void _applyProfileAddressIfVacant() {
    final profile = _profile;
    if (profile == null || _pickupOwned) return;
    final address = customerBookingAddressFromProfile(profile);
    if (address == null) return;
    _applyOwnedPickup(address);
  }

  Future<void> _useMyAddress() async {
    final profile = _profile ?? widget.profile;
    if (profile == null) return;
    final address = customerBookingAddressFromProfile(profile);
    if (address == null) return;
    _applyOwnedPickup(address);
  }

  Future<void> _resolveGps({bool userRequested = false}) async {
    if (!userRequested &&
        (_pickupOwned || !customerBookingPickupIsVacant(_pickup.value))) {
      return;
    }
    setState(() {
      _gpsBusy = true;
      _gpsFallback = false;
    });
    try {
      final resolver = LimousineCurrentLocationResolver(
        lookup: _lookup,
        platform: widget.locationPlatform,
        positionTimeout: const Duration(seconds: 5),
      );
      final place = await resolver.resolve(language: _language.name);
      if (!mounted) return;
      if (!userRequested &&
          (_pickupOwned || !customerBookingPickupIsVacant(_pickup.value))) {
        setState(() {
          _gpsBusy = false;
          _gpsFallback = false;
        });
        return;
      }
      if (place != null && place.label.trim().isNotEmpty) {
        _pickup.acceptCopy(
          customerBookingAddressFromText(
            place.label,
            latitude: place.lat,
            longitude: place.lon,
          ),
          userConfirmed: true,
        );
        setState(() {
          _gpsBusy = false;
          _gpsFallback = false;
          if (userRequested) _pickupOwned = true;
        });
        _onDraftChanged();
        return;
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _gpsBusy = false;
      _gpsFallback = true;
    });
  }

  void _onPickupChanged() {
    _pickupOwned = _pickup.value.displayText.trim().isNotEmpty;
    _onDraftChanged();
  }

  void _clearCurrentQuote() {
    _quote = null;
    _quoteRequest = null;
    _quoteError = null;
  }

  void _invalidateStaleRide() {
    _quoteSeq += 1;
    _clearCurrentQuote();
    _quoteLoading = false;
    _selectedVehicleId = null;
    _selectedReturnVehicleId = null;
    _assignedDriver = const CustomerBookingAssignedDriver();
    _assignedReturnDriver = const CustomerBookingAssignedDriver();
    _availability = const CustomerBookingAvailabilitySnapshot();
    _returnAvailability = const CustomerBookingAvailabilitySnapshot();
    _availabilityLoading = false;
    _returnAvailabilityLoading = false;
  }

  void _onSheetControllerTick() {
    if (!_sheetController.isAttached) return;
    final next = _sheetController.size;
    if ((next - _sheetExtentNotifier.value).abs() < 0.002) return;
    _sheetExtent = next;
    _sheetExtentNotifier.value = next;
    if (!mounted) return;
    final height = MediaQuery.sizeOf(context).height;
    final sizes = customerBookingSheetSizes(
      height: height,
      keyboardOpen: MediaQuery.viewInsetsOf(context).bottom > 80,
      textScale: MediaQuery.textScalerOf(context).scale(1),
    );
    if (customerBookingSheetIsSnapped(next, sizes)) {
      _snappedSheetExtent = next;
    }
  }

  void _dragSheetBy(
    double deltaDy,
    double parentHeight,
    CustomerBookingSheetSizes sizes,
  ) {
    if (!_sheetController.isAttached || parentHeight <= 0) return;
    final next = (_sheetController.size - deltaDy / parentHeight).clamp(
      sizes.min,
      sizes.max,
    );
    _sheetController.jumpTo(next);
    _sheetExtent = next;
    _sheetExtentNotifier.value = next;
  }

  void _onDraftChanged({
    bool resetOffer = true,
    bool keepOutboundQuote = false,
  }) {
    _availabilitySeq += 1;
    _capabilitiesSeq += 1;
    _quoteDebounce?.cancel();
    _quotes.invalidate();
    if ((_quote?.financialQuoteId ?? '').isNotEmpty) {
      _quoteSeq += 1;
      _clearCurrentQuote();
    }
    if (resetOffer) {
      if (keepOutboundQuote) {
        _quoteSeq += 1;
        _selectedReturnVehicleId = null;
        _assignedReturnDriver = const CustomerBookingAssignedDriver();
        _returnAvailability = const CustomerBookingAvailabilitySnapshot();
        _returnAvailabilityLoading = false;
        if (mounted) setState(() {});
      } else {
        final hadOffer =
            _quote != null ||
            _quoteRequest != null ||
            _selectedVehicleId != null ||
            _selectedReturnVehicleId != null;
        _invalidateStaleRide();
        if (hadOffer && mounted) setState(() {});
      }
    } else if (_quote?.requiresAirportFareContact == true) {
      _quoteSeq += 1;
      _clearCurrentQuote();
      if (mounted) setState(() {});
    }
    _quoteDebounce = Timer(kCompanyPlanQuoteDebounce, () {
      unawaited(_refreshQuote());
      unawaited(_refreshAvailability());
    });
  }

  DateTime? get _asapPickup =>
      _availability.pickupTimes[_selectedVehicleId ??
          _availability.recommendedVehicleId];

  DateTime? get _effectivePickupUtc {
    if (_whenNow) return _asapPickup ?? DateTime.now().toUtc();
    final local = _pickupAt;
    if (local == null) return null;
    return companyPlanPickupUtc(local);
  }

  DateTime? get _effectiveReturnUtc {
    if (_returnKind != CustomerBookingReturnKind.noWait) return null;
    final local = _returnAt;
    if (local == null) return null;
    return companyPlanPickupUtc(local);
  }

  bool get _splitReturn => _returnKind == CustomerBookingReturnKind.noWait;

  void _dropStaleVehicle({
    required bool inbound,
    required CustomerBookingAvailabilitySnapshot snapshot,
  }) {
    if (!snapshot.resolved) return;
    if (inbound) {
      if (_selectedReturnVehicleId != null &&
          !snapshot.availableIds.contains(_selectedReturnVehicleId)) {
        _selectedReturnVehicleId = null;
        _assignedReturnDriver = const CustomerBookingAssignedDriver();
      }
      return;
    }
    if (_selectedVehicleId != null &&
        !snapshot.availableIds.contains(_selectedVehicleId)) {
      _selectedVehicleId = null;
      _assignedDriver = const CustomerBookingAssignedDriver();
    }
  }

  Future<CustomerBookingAvailabilitySnapshot> _fetchLegAvailability({
    required DateTime pickupUtc,
    required int durationMin,
    int waitMin = 0,
    int returnDurationMin = 0,
    LimousineAddressValue? pickupAddress,
    LimousineAddressValue? dropoffAddress,
  }) {
    final origin = pickupAddress ?? _effectivePickupAddress;
    final destination =
        dropoffAddress ??
        (_returnKind == CustomerBookingReturnKind.wait
            ? _quotedReturnTo
            : _effectiveDropoffAddress);
    return fetchCustomerBookingAvailability(
      bookingBaseUrl: widget.bookingBaseUrl ?? _quoteClient.bookingBaseUrl,
      partnerId: _entry.company.routingPartnerId,
      pickupUtc: pickupUtc,
      passengers: _passengers,
      durationMin: durationMin,
      waitMin: waitMin,
      returnDurationMin: returnDurationMin,
      httpGet: widget.profileGet,
      pickupLatitude: origin.lat,
      pickupLongitude: origin.lon,
      dropoffLatitude: destination.lat,
      dropoffLongitude: destination.lon,
      baggage: _bags,
      asap: _whenNow && pickupAddress == null,
    );
  }

  Future<void> _refreshReliableAvailability() async {
    if(!_hasChosenCompany||!_rideDetailsReady||_pickupNeedsConfirm||_quote?.requiresAirportFareContact==true){
      _availabilitySeq++;setState((){_availabilityLoading=false;_reliableRows=[];_reliableSelectionToken=null;_availability=const CustomerBookingAvailabilitySnapshot();});return;
    }
    final seq=++_availabilitySeq,partner=_entry.company.routingPartnerId;
    setState((){_availabilityLoading=true;_reliableSelectionToken=null;_reliableRows=[];_reliableReturnRows=[];});
    try{
      final request=_quoteRequest;
      if(request==null||!_rideDetailsReady||_pickupNeedsConfirm)throw StateError('reliable_request_not_ready');
      final token=widget.reliableChoiceApi?.token??await _customerAuthToken();
      final api=widget.reliableChoiceApi??ReliableChoiceApiV1(base:Uri.parse(widget.bookingBaseUrl??(_quoteClient.bookingBaseUrl.isEmpty?kBookingBaseUrl:_quoteClient.bookingBaseUrl)),token:token,client:_reliableHttp,postTransport:_quoteClient.httpPost);
      final result=await api.prebooking(_quoteClient.decorateBody({..._publicQuoteBody(request),'pickup_mode':'asap','bags':_bags,'pax':_passengers},_entry));
      if(!mounted||seq!=_availabilitySeq||partner!=_entry.company.routingPartnerId||!_whenNow)return;
      setState((){
        if(result.vehicles.isNotEmpty)_requestDispatcherReview=false;
        _activeReliableApi=api;_reliableRows=result.vehicles;_reliableSelectionToken=result.token;
        _reliableReturnRows=_splitReturn?result.returnVehicles:[];
        _returnAvailability=CustomerBookingAvailabilitySnapshot(fetched:true,availableIds:_reliableReturnRows.map((r)=>r['vehicle_id'] as String).toSet());
        _returnAvailabilityLoading=false;
        if(!_reliableReturnRows.any((r)=>r['vehicle_id']==_selectedReturnVehicleId))_selectedReturnVehicleId=null;
        if(_splitReturn)_preselectSoleBookableVehicle(inbound:true);
        _availability=CustomerBookingAvailabilitySnapshot(fetched:true,availableIds:result.vehicles.map((r)=>r['vehicle_id'] as String).toSet());
        _availabilityLoading=false;
        if(!result.vehicles.any((r)=>r['vehicle_id']==_selectedVehicleId)){_selectedVehicleId=null;_assignedDriver=customerBookingProposedDriverFromRecord(null);}
        _preselectSoleBookableVehicle(inbound:false);
      });
    }catch(_){if(mounted&&seq==_availabilitySeq)setState((){_reliableRows=[];_reliableReturnRows=[];_returnAvailability=const CustomerBookingAvailabilitySnapshot(fetched:true,loadFailed:true);_returnAvailabilityLoading=false;_reliableSelectionToken=null;_availabilityLoading=false;_availability=const CustomerBookingAvailabilitySnapshot(fetched:true,loadFailed:true);});}
  }

  Future<void> _refreshAvailability() async {
    // Incomplete drafts must retire pending evidence before any session or
    // subscription request. Capability replies belong to the same ride draft.
    if (_whenNow && (!_hasChosenCompany || _pickupNeedsConfirm || !_rideDetailsReady || _quote?.requiresAirportFareContact == true)) {
      _capabilitiesSeq += 1;
      _availabilitySeq += 1;
      if (mounted) setState(() {
        _asapCapabilitiesPartner = null;
        _asapBookingMode = 'unavailable';
        _reliableRows = [];
        _reliableReturnRows = [];
        _activeReliableApi = null;
        _reliableSelectionToken = null;
        _requestDispatcherReview = false;
        _availability = const CustomerBookingAvailabilitySnapshot();
        _returnAvailability = const CustomerBookingAvailabilitySnapshot();
        _availabilityLoading = false;
        _returnAvailabilityLoading = false;
        _selectedVehicleId = null;
        _selectedReturnVehicleId = null;
      });
      return;
    }
    if(_whenNow){
      if(!_hasChosenCompany)return;
      final capSeq=++_capabilitiesSeq,partner=_entry.company.routingPartnerId;
      setState((){_availabilityLoading=true;_asapCapabilitiesPartner=null;_asapBookingMode='unavailable';_reliableSelectionToken=null;_requestDispatcherReview=false;});
      try{
        final token=widget.reliableChoiceApi?.token??await _customerAuthToken();
        final api=widget.reliableChoiceApi??ReliableChoiceApiV1(base:Uri.parse(widget.bookingBaseUrl??(_quoteClient.bookingBaseUrl.isEmpty?kBookingBaseUrl:_quoteClient.bookingBaseUrl)),token:token,client:_reliableHttp,postTransport:_quoteClient.httpPost);
        final capabilities=await api.capabilities(partner);
        if(!mounted||capSeq!=_capabilitiesSeq||partner!=_entry.company.routingPartnerId||!_whenNow)return;
        setState((){_asapCapabilitiesPartner=partner;_asapBookingMode=capabilities.mode;_reliableRows=[];_reliableReturnRows=[];_activeReliableApi=null;});
        if(_usesReliableChoice){await _refreshReliableAvailability();return;}
        if(!_usesManualAsap)throw StateError('asap_booking_unavailable');
      }catch(_){
        if(mounted&&capSeq==_capabilitiesSeq&&partner==_entry.company.routingPartnerId&&_whenNow)setState((){_asapBookingMode='unavailable';_availabilityLoading=false;_availability=const CustomerBookingAvailabilitySnapshot(fetched:true,loadFailed:true);});
        return;
      }
    }
    if (!_hasChosenCompany) return;
    final pickup = _effectivePickupUtc;
    if (pickup == null) return;
    void clearOutbound() {
      _availabilitySeq += 1;
      if (_availability.fetched || _availabilityLoading) {
        setState(() {
          _availability = const CustomerBookingAvailabilitySnapshot();
          _availabilityLoading = false;
        });
      }
    }

    if (_pickupNeedsConfirm || !_rideDetailsReady) {
      clearOutbound();
      return;
    }
    final duration = _rideDurationMin;
    if (duration == null || duration <= 0) {
      clearOutbound();
      return;
    }
    final seq = ++_availabilitySeq;
    final waitCombined = _returnKind == CustomerBookingReturnKind.wait;
    setState(() {
      _availabilityLoading = true;
      if (_splitReturn) _returnAvailabilityLoading = true;
    });
    try {
      final outbound = await _fetchLegAvailability(
        pickupUtc: pickup,
        durationMin: duration,
        waitMin: waitCombined ? _options.waitMin : 0,
        returnDurationMin: waitCombined
            ? (_quote?.returnDurationMin ?? duration)
            : 0,
      );
      CustomerBookingAvailabilitySnapshot inbound =
          const CustomerBookingAvailabilitySnapshot();
      if (_splitReturn) {
        final returnUtc = _effectiveReturnUtc;
        final returnDuration = _quote?.returnDurationMin ?? duration;
        if (returnUtc != null && returnDuration > 0) {
          inbound = await _fetchLegAvailability(
            pickupUtc: returnUtc,
            durationMin: returnDuration,
            pickupAddress: _quotedReturnFrom,
            dropoffAddress: _quotedReturnTo,
          );
        }
      }
      if (!mounted || seq != _availabilitySeq) return;
      setState(() {
        _availability = outbound;
        if (_whenNow &&
            outbound.availableIds.contains(outbound.recommendedVehicleId)) {
          _selectedVehicleId = outbound.recommendedVehicleId;
        }
        _availabilityLoading = false;
        if (_splitReturn) {
          _returnAvailability = inbound;
          _returnAvailabilityLoading = false;
          _dropStaleVehicle(inbound: true, snapshot: inbound);
        } else {
          _returnAvailability = const CustomerBookingAvailabilitySnapshot();
          _returnAvailabilityLoading = false;
        }
        _dropStaleVehicle(inbound: false, snapshot: outbound);
        _preselectSoleBookableVehicle(inbound: false);
        if (_splitReturn) _preselectSoleBookableVehicle(inbound: true);
      });
      if (customerBookingOfferIsExpired(expiresAt: outbound.expiresAt)) {
        unawaited(_refreshExpiredOffer());
      }
    } catch (_) {
      if (!mounted || seq != _availabilitySeq) return;
      setState(() {
        _availabilityLoading = false;
        _returnAvailabilityLoading = false;
        _availability = const CustomerBookingAvailabilitySnapshot(
          loadFailed: true,
          fetched: true,
        );
        if (_splitReturn) {
          _returnAvailability = const CustomerBookingAvailabilitySnapshot(
            loadFailed: true,
            fetched: true,
          );
        }
      });
    }
  }

  void _applyAirport(
    AirportCatalogAirport airport, {
    required bool browse,
    bool notify = true,
  }) {
    final address = customerBookingAddressFromAirport(airport);
    if (_toAirport) {
      _dropoff.acceptCopy(address);
    } else {
      _pickup.acceptCopy(address);
    }
    void assign() {
      _airport = airport;
      _countryCode = airport.countryCode;
      _browseCatalog = browse;
      _airportPickerOpen = browse;
      _entry = _entry.copyWith(airport: airport, toAirport: _toAirport);
    }

    if (notify && mounted) {
      setState(assign);
    } else {
      assign();
    }
    if (notify) _onDraftChanged();
  }

  void _setAirportMode(bool airport) {
    setState(() {
      _airportMode = airport;
      _entry = _entry.copyWith(
        kind: airport
            ? CustomerBookingKind.airport
            : (_entry.kind == CustomerBookingKind.airport
                  ? CustomerBookingKind.taxi
                  : _entry.kind),
      );
      if (airport) {
        if (_airportMinLeadHours != null && _whenNow) {
          _whenNow = false;
          _pickupAt = null;
        }
        if (_returnKind == CustomerBookingReturnKind.wait) {
          _returnKind = CustomerBookingReturnKind.noWait;
        }
        _waitMin = 0;
      }
      if (!airport) {
        _browseCatalog = false;
        if (_toAirport) {
          _dropoff.clear();
        } else {
          _pickup.clear();
          _pickupOwned = false;
        }
        _airport = null;
      } else {
        if (_toAirport) {
          _dropoff.clear();
        } else if (!_pickupOwned) {
          _pickup.clear();
        }
        if (_airport != null) {
          _applyAirport(_airport!, browse: false, notify: false);
        }
      }
    });
    _onDraftChanged();
  }

  void _setDirection(bool toAirport) {
    final airport = _airport;
    setState(() => _toAirport = toAirport);
    if (airport != null) {
      _applyAirport(airport, browse: false);
    } else {
      _onDraftChanged();
    }
  }

  Map<String, dynamic> _publicQuoteBody(CompanyPlanQuoteRequest request) => {
    ...request.body,
    if(_splitReturn && _effectiveReturnUtc!=null)'return_pickup_iso':_effectiveReturnUtc!.toIso8601String(),
    'stop_coordinates':[for(final stop in _stops)officialOperationalStop(_quoteAddress(stop))],
    'return_stop_coordinates':[for(final stop in _returnStops)officialOperationalStop(_quoteAddress(stop))],
    if (customerBookingBodyHasWhenNow(request.body)) 'pickup_mode':'asap',
    ...customerBookingBillingPayloadFields(
      businessRide:_businessRide, identity:_billing.identity,
      defaultEmail:_emailCtrl.text, defaultPhone:_bookingPhone),
    if (_splitReturn && (_selectedReturnVehicleId ?? '').trim().isNotEmpty)
      'return_vehicle_id':_selectedReturnVehicleId!.trim(),
  };

  Future<CompanyPlanQuoteResult> _runQuote(CompanyPlanQuoteRequest request) {
    return _quoteClient.quote(request:CompanyPlanQuoteRequest(
      fingerprint:request.fingerprint,body:_publicQuoteBody(request)),entry:_entry);
  }

  LimousineAddressValue _quoteAddress(LimousineAddressFieldController field) {
    if (field.locationNeedsConfirm && !field.locationUserConfirmed) {
      return field.value;
    }
    if (field.value.isRouteReady) return field.value;
    final text = field.textController.text.trim();
    if (text.isEmpty) return field.value;
    return customerBookingAddressFromText(
      text,
      latitude: field.value.lat,
      longitude: field.value.lon,
    );
  }

  LimousineAddressValue get _effectivePickupAddress {
    if (_airportMode && !_toAirport && _airport != null) {
      final filled = _quoteAddress(_pickup);
      if (customerBookingAddressReady(filled)) return filled;
      return customerBookingAddressFromAirport(_airport!);
    }
    return _quoteAddress(_pickup);
  }

  LimousineAddressValue get _effectiveDropoffAddress {
    if (_airportMode && _toAirport && _airport != null) {
      final filled = _quoteAddress(_dropoff);
      if (customerBookingAddressReady(filled)) return filled;
      return customerBookingAddressFromAirport(_airport!);
    }
    return _quoteAddress(_dropoff);
  }

  bool get _rideIsBookable => _confirmDecision.canConfirm;

  String get _selectedBookableDriverId {
    final id = (_selectedVehicleId ?? '').trim();
    if (id.isEmpty) return _assignedDriver.driverId.trim();
    for (final offer in _outboundVehicleOffers) {
      if (offer.vehicleId == id && offer.driverId.isNotEmpty) {
        return offer.driverId;
      }
    }
    return _assignedDriver.driverId.trim();
  }

  bool get _airportWindowBlocked => customerBookingAirportWindowBlocked(
    airport: _airportMode,
    minimumHours: _airportMinLeadHours,
    whenNow: _whenNow,
    pickup: _pickupAt,
    now: DateTime.now(),
  );

  CustomerBookingConfirmDecision get _confirmDecision {
    return customerBookingConfirmDecision(
      hasCompany: _hasChosenCompany,
      pickup: _effectivePickupAddress,
      dropoff: _effectiveDropoffAddress,
      pickupNeedsConfirm: _pickupNeedsConfirm,
      whenNow: _whenNow,
      pickupLocal: _pickupAt,
      name: _nameCtrl.text,
      phone: _phoneCtrl.text,
      quoteLoading: _quoteLoading || (_airportMode && _vehiclesLoading),
      quote: _quote,
      quoteError: _airportWindowBlocked
          ? 'airport_minimum_advance_booking:$_airportMinLeadHours'
          : _quoteError,
      successId: _successId,
      submitting: _submitting,
      confirmInFlight: _confirmInFlight,
      bookPosted: _bookPosted,
      bookUncertain: _bookUncertain,
      outboundOffers: _outboundVehicleOffers,
      selectedVehicleId: _selectedVehicleId,
      selectedDriverId: _selectedBookableDriverId,
      splitReturn: _splitReturn,
      returnOffers: _returnVehicleOffers,
      selectedReturnVehicleId: _selectedReturnVehicleId,
      availabilityFailed:
          _availability.loadFailed ||
          (_splitReturn && _returnAvailability.loadFailed),
      passengers: _passengers,
      minPrepMinutes: _minPrepMinutes,
      offerExpiresAt: _availability.expiresAt,
      geometryDurationMin: _geometryDurationMin,
      geometryDistanceKm: _geometryDistanceKm,
      selectedVehicleSeats: _selectedVehicleSeats,
      dispatcherRequested:_usesReliableChoice&&_requestDispatcherReview&&_reliableSelectionToken!=null&&_reliableRows.isEmpty,
    );
  }

  String _quotedRequestLabel(String key) {
    final raw = _quoteRequest?.body[key];
    return raw == null ? '' : raw.toString().trim();
  }

  LimousineAddressValue _bookAddress(
    LimousineAddressFieldController field, {
    double? fallbackLat,
    double? fallbackLon,
    String quotedLabel = '',
  }) {
    final value = _quoteAddress(field);
    final label = value.routeText.trim().isNotEmpty
        ? value.routeText
        : value.displayText;
    final lat = customerBookingReuseQuotedCoordinate(
      currentLabel: label,
      quotedLabel: quotedLabel,
      current: value.lat,
      quoted: fallbackLat,
    );
    final lon = customerBookingReuseQuotedCoordinate(
      currentLabel: label,
      quotedLabel: quotedLabel,
      current: value.lon,
      quoted: fallbackLon,
    );
    if (value.hasCoordinates || lat == null || lon == null) {
      return value;
    }
    return customerBookingAddressFromText(label, latitude: lat, longitude: lon);
  }

  LimousineAddressValue get _quotedReturnFrom {
    return customerBookingReturnFromAddress(
      returnPickup: _quoteAddress(_returnPickup),
      outboundDropoff: _effectiveDropoffAddress,
    );
  }

  LimousineAddressValue get _quotedReturnTo {
    return customerBookingReturnToAddress(
      returnDropoff: _quoteAddress(_returnDropoff),
      outboundPickup: _effectivePickupAddress,
    );
  }

  Future<void> _refreshQuote() async {
    if (_pendingFinancialAcceptance != null) return;
    if (!mounted) return;
    _syncReturnDefaults();
    final seq = ++_quoteSeq;
    final quotePartnerId = _entry.company.routingPartnerId;
    bool quoteIsCurrent() =>
        mounted &&
        seq == _quoteSeq &&
        quotePartnerId == _entry.company.routingPartnerId;
    if (_pickupNeedsConfirm) {
      setState(() {
        _clearCurrentQuote();
        _quoteLoading = false;
      });
      unawaited(_refreshAvailability());
      return;
    }
    if (!_hasChosenCompany) {
      setState(() {
        _clearCurrentQuote();
        _quoteError = null;
        _quoteLoading = false;
      });
      return;
    }
    if (_airportMode && !customerBookingAirportMetadataReady(_airport)) {
      if (!quoteIsCurrent()) return;
      setState(() {
        _clearCurrentQuote();
        _quoteError = kCustomerBookingIssueNeedAirport;
        _quoteLoading = false;
      });
      unawaited(_refreshAvailability());
      return;
    }
    final pickupAt = _whenNow ? DateTime.now() : _pickupAt;
    final airportReturn =
        _airportMode && _returnKind == CustomerBookingReturnKind.noWait;
    final combinedReturn = _returnKind != CustomerBookingReturnKind.oneWay;
    final request = companyPlanQuoteRequestFromAddresses(
      from: _effectivePickupAddress,
      to: _effectiveDropoffAddress,
      pickupLocal: pickupAt,
      options: _options,
      passengers: _passengers,
      returnEnabled: combinedReturn,
      returnPickupLocal: combinedReturn
          ? (_returnKind==CustomerBookingReturnKind.noWait ? (_returnAt ?? pickupAt) : null)
          : null,
      returnFrom: combinedReturn ? _quotedReturnFrom : null,
      returnTo: combinedReturn ? _quotedReturnTo : null,
      stops: [for (final stop in _stops) _quoteAddress(stop)],
      returnStops: combinedReturn
          ? [for (final stop in _returnStops) _quoteAddress(stop)]
          : const <LimousineAddressValue>[],
      whenNow: _whenNow,
      vehicleId: _selectedVehicleId ?? '',
      partnerId: quotePartnerId,
    );
    if (request == null) {
      if (!quoteIsCurrent()) return;
      setState(() {
        _clearCurrentQuote();
        _quoteError = customerBookingIncompleteQuoteIssue(
          from: _effectivePickupAddress,
          to: _effectiveDropoffAddress,
          whenNow: _whenNow,
          pickupLocal: pickupAt,
        );
        _quoteLoading = false;
      });
      unawaited(_refreshAvailability());
      return;
    }
    setState(() {
      _quoteLoading = true;
      _quoteError = null;
    });
    try {
      var result = await _quotes.quote(request);
      if (!quoteIsCurrent()) return;
      if (_splitReturn && !airportReturn) {
        final inboundFrom = _quotedReturnFrom;
        final inboundTo = _quotedReturnTo;
        final inboundPickup = _returnAt ?? pickupAt;
        if (inboundPickup != null &&
            customerBookingAddressReady(inboundFrom) &&
            customerBookingAddressReady(inboundTo) &&
            companyPlanQuoteNeedsInboundLeg(result)) {
          final inboundRequest = companyPlanQuoteRequestFromAddresses(
            from: inboundFrom,
            to: inboundTo,
            pickupLocal: inboundPickup,
            whenNow: false,
            options: _options.forInboundLeg(),
            passengers: _passengers,
            stops: [for (final stop in _returnStops) _quoteAddress(stop)],
            vehicleId: _selectedReturnVehicleId ?? '',
            partnerId: quotePartnerId,
          );
          if (inboundRequest != null) {
            final inbound = await _quotes.quote(inboundRequest);
            if (!quoteIsCurrent()) return;
            result = companyPlanMergeLegQuotes(
              outbound: result,
              inbound: inbound,
            );
          }
        }
      }
      _absorbQuoteCoordinates(result, request);
      if (!quoteIsCurrent()) return;
      setState(() {
        _quote = result;
        _quoteRequest = request;
        _quoteLoading = false;
        _quoteError = null;
        _applySuggestedPickup();
      });
      unawaited(_refreshAvailability());
    } catch (error) {
      if (!quoteIsCurrent()) return;
      final issue = customerBookingQuoteIssueFromRaw(error.toString());
      if (issue == kCustomerBookingIssueRequestQuoteRequired) {
        setState(() {
          _quote = customerBookingAirportContactQuote(
            _quote,
            quoteReason: _airportMode ? '' : 'taxi_work_area_unverified',
          );
          _quoteRequest = request;
          _quoteLoading = false;
          _quoteError = null;
        });
        return;
      }
      debugPrint('[CUSTOMER_BOOKING][QUOTE][ERR] $error');
      setState(() {
        _clearCurrentQuote();
        _quoteLoading = false;
        _quoteError = issue;
      });
      unawaited(_refreshAvailability());
    }
  }

  void _syncReturnDefaults() {
    if (_returnKind == CustomerBookingReturnKind.oneWay) return;
    if (_returnPickup.value.isEmpty &&
        customerBookingAddressReady(_effectiveDropoffAddress)) {
      _returnPickup.acceptCopy(_effectiveDropoffAddress);
    }
    if (_returnDropoff.value.isEmpty &&
        customerBookingAddressReady(_effectivePickupAddress)) {
      _returnDropoff.acceptCopy(_effectivePickupAddress);
    }
  }

  void _addStop({required bool inbound}) {
    final list = inbound ? _returnStops : _stops;
    if (list.length >= kCustomerBookingMaxStops) return;
    final controller = _makeAddress(
      inbound ? 'return_stop_${_stopSeq++}' : 'stop_${_stopSeq++}',
    );
    controller.addListener(_onDraftChanged);
    limousineBindSiblingSearchBias(field: controller, sibling: _pickup);
    setState(() => list.add(controller));
  }

  void _absorbQuoteCoordinates(
    CompanyPlanQuoteResult result,
    CompanyPlanQuoteRequest request,
  ) {
    final pickupText = _pickup.value.displayText;
    final quotedFrom = (request.body['from'] ?? '').toString();
    final quotedTo = (request.body['to'] ?? '').toString();
    final pickupHasHouse = limousineParseStreetHouse(pickupText).hasNumber;
    final pickupHasLocality =
        limousineAddressQueryPostcode(pickupText) != null ||
        limousineAddressQueryLocality(pickupText) != null;
    if (!_pickup.value.hasCoordinates &&
        !_pickupOwned &&
        !pickupHasHouse &&
        !pickupHasLocality &&
        customerBookingQuotedLabelMatches(pickupText, quotedFrom) &&
        result.pickupLat != null &&
        result.pickupLon != null) {
      _pickup.acceptCopy(
        _pickup.value.copyWith(lat: result.pickupLat, lon: result.pickupLon),
      );
    }
    final dropoffText = _dropoff.value.displayText;
    if (!_dropoff.value.hasCoordinates &&
        customerBookingQuotedLabelMatches(dropoffText, quotedTo) &&
        result.dropoffLat != null &&
        result.dropoffLon != null) {
      _dropoff.acceptCopy(
        _dropoff.value.copyWith(lat: result.dropoffLat, lon: result.dropoffLon),
      );
    }
  }

  void _suggestVehicleIfNeeded() {
    final categories = _bookableCategories;
    if (categories.isEmpty) return;
    final suggested = companyPlanSuggestedTypeForCapacity(
      passengers: _passengers,
      bags: _bags,
      available: [
        for (final category in categories)
          companyPlanVehicleTypeForCategory(category),
      ],
    );
    setState(() {
      if (suggested != null) _vehicle = suggested;
      _syncVehicleFromFleet();
    });
  }

  Future<void> _pickDateTime({required bool inbound}) async {
    final now = DateTime.now();
    final initial = inbound
        ? (_returnAt ?? now.add(const Duration(hours: 3)))
        : (_pickupAt ?? now.add(const Duration(hours: 1)));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    final next = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() {
      if (inbound) {
        _returnAt = next;
      } else {
        _pickupAt = next;
      }
    });
    _onDraftChanged(keepOutboundQuote: inbound);
  }

  Future<void> _pickFlightWhen() async {
    final now = DateTime.now();
    final initial = _flightAt ?? now.add(const Duration(hours: 4));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    setState(() {
      _flightAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      _applySuggestedPickup();
    });
    _onDraftChanged();
  }

  bool get _flightTooLate {
    if (!_airportMode || !_toAirport || _flightAt == null) return false;
    final pickup = _whenNow ? DateTime.now() : _pickupAt;
    final duration = _rideDurationMin;
    if (pickup == null || duration == null) return false;
    return pickup.add(Duration(minutes: duration)).isAfter(_flightAt!);
  }

  DateTime? get _suggestedPickup {
    if (!_airportMode || _flightAt == null) return null;
    final iso = _flightAt!.toIso8601String();
    if (_toAirport) {
      return companyPlanSuggestedToAirportPickup(
        flightAt: iso,
        durationMin: _rideDurationMin,
        arrivalMarginMin: _arrivalMarginMin,
      );
    }
    return companyPlanSuggestedFromAirportPickup(
      flightAt: iso,
      pickupAfterMin: _pickupAfterMin,
    );
  }

  void _applySuggestedPickup({bool force = false}) {
    final suggested = _suggestedPickup;
    if (suggested == null) return;
    if (!force && _taxiPickupManual) return;
    _whenNow = false;
    _pickupAt = suggested;
    if (force) _taxiPickupManual = false;
  }

  Future<void> _changeCompany() async {
    if (!mounted) return;
    final airportCapableOnly = _airportMode;
    final picker = widget.companyPicker;
    final CustomerBookingCompany? picked;
    if (picker != null) {
      picked = await picker(context, airportCapableOnly: airportCapableOnly);
    } else {
      picked = await pickCustomerBookingCompany(
        context,
        airportCapableOnly: airportCapableOnly,
        customerHomeBuilder: widget.onGoToStartPage,
      );
    }
    if (!mounted || picked == null) return;
    final chosen = picked;
    setState(() {
      _entry = _entry.copyWith(company: chosen);
      _airportMinLeadHours = null;
      _companyVehicles = List<Map<String, dynamic>>.from(chosen.vehicles);
      _companyDrivers = const <Map<String, dynamic>>[];
      _presentation = const PublicCompanyPresentation();
      _publicContact = const CustomerBookingPublicContact();
      _availability = const CustomerBookingAvailabilitySnapshot();
      _returnAvailability = const CustomerBookingAvailabilitySnapshot();
      _availabilityLoading = false;
      _returnAvailabilityLoading = false;
      _selectedVehicleId = null;
      _selectedReturnVehicleId = null;
      _assignedDriver = const CustomerBookingAssignedDriver();
      _assignedReturnDriver = const CustomerBookingAssignedDriver();
      _clearCurrentQuote();
      _submitError = null;
      _quotes = CompanyPlanQuoteCoordinator(transport: _runQuote);
      _idempotencyKey =
          'cust-${DateTime.now().microsecondsSinceEpoch}-${_entry.kind.name}';
      _syncVehicleFromFleet();
    });
    unawaited(_loadCompanyVehicles());
    _onDraftChanged();
  }

  String? get _billingWarning {
    if (!_businessRide) return null;
    final missing = firstMissingBookingBillingIdentityField(_billing.identity);
    if (missing == null) return null;
    return bookingBillingIdentityMissingFieldMessage(missing, _copy);
  }

  String _copy({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) {
    switch (_language) {
      case AppLanguage.en:
        return en;
      case AppLanguage.fr:
        return fr;
      case AppLanguage.es:
        return es;
      case AppLanguage.nl:
      case AppLanguage.de:
        return nl;
    }
  }

  Future<void> _confirm() async {
    if (!customerBookingAllowsAnotherBookAttempt(
      submitting: _submitting,
      confirmInFlight: _confirmInFlight,
      successId: _successId,
      bookPosted: _bookPosted,
      bookUncertain: _bookUncertain,
    )) {
      return;
    }
    final decision = _confirmDecision;
    final failure = decision.firstFailure;
    if (failure != null) {
      setState(() {
        _submitError = _visibleConfirmReasonText(
          failure,
          _language,
          suggestedPickup: decision.suggestedPickup,
        );
      });
      _revealSubmitIssue(
        CustomerBookingSubmitIssue(
          code: failure.id,
          focusKey: failure.focusKey,
        ),
      );
      if (failure.id == kCustomerBookingIssueOfferExpired) {
        unawaited(_refreshExpiredOffer());
      }
      return;
    }
    _confirmInFlight = true;
    setState(() {});
    try {
      if (_contextInvalid) return;
      setState(() => _submitError = null);
      final selection = await openCustomerBookingPaymentOptions(
        context,
        language: _language,
        palette: _palette,
        capability: _paymentCapability,
        countryCode: _countryCode,
        quoteSummary: _tripSummaryLine,
        billingWarning: _billingWarning,
        loadFailed: _paymentCapabilityLoadFailed,
      );
      if (!mounted || selection == null) return;
      await _book(selection);
    } finally {
      if (mounted && _successId == null) {
        _confirmInFlight = false;
        setState(() {});
      }
    }
  }

  bool _offerRefreshInFlight = false;

  Future<void> _refreshExpiredOffer() async {
    if (_offerRefreshInFlight) return;
    if (_availabilityLoading || _quoteLoading) return;
    final expiry = _availability.expiresAt;
    if (expiry == null) return;
    if (_autoRefreshedExpiry == expiry) return;
    _offerRefreshInFlight = true;
    _autoRefreshedExpiry = expiry;
    try {
      await _refreshQuote();
      if (!mounted) return;
      await _refreshAvailability();
    } finally {
      _offerRefreshInFlight = false;
    }
  }

  Future<void> _book(BookingPaymentSelection selection) async {
    if (!customerBookingAllowsAnotherBookAttempt(
      submitting: _submitting,
      confirmInFlight: false,
      successId: _successId,
      bookPosted: _bookPosted,
      bookUncertain: _bookUncertain,
    )) {
      return;
    }
    if (_quote != null && _quote!.requiresAirportFareContact) {
      setState(() {
        _submitting = false;
        _submitError = null;
        _quote = customerBookingAirportContactQuote(_quote);
      });
      return;
    }
    _submitting = true;
    setState(() => _submitError = null);
    try {
      _syncReturnDefaults();
      if (_airportMode && !customerBookingAirportMetadataReady(_airport)) {
        throw const CustomerBookingBookException(
          statusCode: 400,
          code: kCustomerBookingIssueNeedAirport,
          raw: 'need_airport',
        );
      }
      if (!_effectivePickupAddress.hasCoordinates) {
        await _geocodePickupIfNeeded();
      }
      if (_whenNow && _asapPickup != null) {
        await _refreshAvailability();
        if (!_requestDispatcherReview&&!_availability.availableIds.contains(_selectedVehicleId)) {
          throw const CustomerBookingBookException(
            statusCode: 409,
            code: kCustomerBookingIssueUnavailable,
            raw: 'availability_changed',
          );
        }
      }
      final pickupAt = _whenNow
          ? (_asapPickup?.toLocal() ?? DateTime.now())
          : _pickupAt;
      LimousineAddressValue bookEnd({
        required LimousineAddressFieldController field,
        required LimousineAddressValue effective,
        double? fallbackLat,
        double? fallbackLon,
        required String quotedLabel,
      }) {
        final booked = _bookAddress(
          field,
          fallbackLat: fallbackLat,
          fallbackLon: fallbackLon,
          quotedLabel: quotedLabel,
        );
        if (customerBookingAddressReady(booked) && booked.hasCoordinates) {
          return booked;
        }
        return effective;
      }

      final request = companyPlanQuoteRequestFromAddresses(
        from: bookEnd(
          field: _pickup,
          effective: _effectivePickupAddress,
          fallbackLat: _quote?.pickupLat,
          fallbackLon: _quote?.pickupLon,
          quotedLabel: _quotedRequestLabel('from'),
        ),
        to: bookEnd(
          field: _dropoff,
          effective: _effectiveDropoffAddress,
          fallbackLat: _quote?.dropoffLat,
          fallbackLon: _quote?.dropoffLon,
          quotedLabel: _quotedRequestLabel('to'),
        ),
        pickupLocal: pickupAt,
        options: _options,
        passengers: _passengers,
        returnEnabled: _returnKind != CustomerBookingReturnKind.oneWay,
        returnPickupLocal: _returnKind == CustomerBookingReturnKind.noWait
            ? _returnAt
            : null,
        returnFrom: _returnKind == CustomerBookingReturnKind.oneWay
            ? null
            : _quotedReturnFrom,
        returnTo: _returnKind == CustomerBookingReturnKind.oneWay
            ? null
            : _quotedReturnTo,
        stops: [for (final stop in _stops) _quoteAddress(stop)],
        returnStops: [for (final stop in _returnStops) _quoteAddress(stop)],
        whenNow: _whenNow && _asapPickup == null,
        vehicleId: _selectedVehicleId ?? '',
        partnerId: _entry.company.routingPartnerId,
      );
      if (request == null) {
        throw StateError(kCustomerBookingIssueNeedRoute);
      }
      final token = await _customerAuthToken();
      final headers = <String, String>{};
      if (token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
      String assignedDriverId = _assignedDriver.driverId.trim();
      for (final offer in _outboundVehicleOffers) {
        if (offer.vehicleId == _selectedVehicleId &&
            offer.driverId.isNotEmpty) {
          assignedDriverId = offer.driverId;
          break;
        }
      }
      String returnAssignedDriverId = _assignedReturnDriver.driverId.trim();
      if (_splitReturn) {
        for (final offer in _returnVehicleOffers) {
          if (offer.vehicleId == _selectedReturnVehicleId &&
              offer.driverId.isNotEmpty) {
            returnAssignedDriverId = offer.driverId;
            break;
          }
        }
      }
      final totalPrice = _quote?.displayTotalPrice;
      String selectedPlate = '';
      for (final offer in _outboundVehicleOffers) {
        if (offer.vehicleId == (_selectedVehicleId ?? '').trim()) {
          selectedPlate = companyAgendaVehiclePlate(offer.vehicle);
          break;
        }
      }
      if(_usesReliableChoice&&(_reliableSelectionToken==null||!(_requestDispatcherReview&&_reliableRows.isEmpty)&&!_outboundVehicleOffers.any((o)=>o.vehicleId==_selectedVehicleId)))throw StateError('reliable_selection_expired');
      final body = <String, dynamic>{
        ...request.body,
        if(_whenNow)'pickup_mode':'asap',
        if(_whenNow)'stop_coordinates':[for(final stop in _stops)officialOperationalStop(_quoteAddress(stop))],
        if(_whenNow)'return_stop_coordinates':[for(final stop in _returnStops)officialOperationalStop(_quoteAddress(stop))],
        if(_usesReliableChoice)'reliable_choice':_requestDispatcherReview?{'selection_token':_reliableSelectionToken,'kind':'dispatcher'}:{'selection_token':_reliableSelectionToken,'vehicle_id':_selectedVehicleId,'kind':_allowCompatibleReplacement?'type':'exact'},
        'name': _nameCtrl.text.trim(),
        // Sent in international form for private and business rides alike.
        'phone': _bookingPhone,
        'email': _emailCtrl.text.trim(),
        'pax': _passengers,
        if ((_selectedVehicleId ?? '').trim().isNotEmpty)
          'preferred_vehicle_id': _selectedVehicleId!.trim(),
        if ((_selectedVehicleId ?? '').trim().isNotEmpty)
          'vehicle_id': _selectedVehicleId!.trim(),
        if (selectedPlate.isNotEmpty) 'license_plate': selectedPlate,
        if (selectedPlate.isNotEmpty) 'licensePlate': selectedPlate,
        if (assignedDriverId.isNotEmpty) 'assigned_driver_id': assignedDriverId,
        if (_splitReturn && (_selectedReturnVehicleId ?? '').trim().isNotEmpty)
          'preferred_return_vehicle_id': _selectedReturnVehicleId!.trim(),
        if (_splitReturn && (_selectedReturnVehicleId ?? '').trim().isNotEmpty)
          'return_vehicle_id': _selectedReturnVehicleId!.trim(),
        if (_splitReturn && returnAssignedDriverId.isNotEmpty)
          'return_assigned_driver_id': returnAssignedDriverId,
        if (totalPrice != null) ...<String, dynamic>{
          'price_incl_vat': totalPrice,
          'total_price_incl_vat': totalPrice,
        },
        if (_quote?.outboundPriceInclVat != null)
          'outbound_price_incl_vat': _quote!.outboundPriceInclVat,
        if (_quote?.returnPriceInclVat != null)
          'return_price_incl_vat': _quote!.returnPriceInclVat,
        'idempotency_key': _idempotencyKey,
        'idempotencyKey': _idempotencyKey,
        ...customerBookingBillingPayloadFields(
          businessRide: _businessRide,
          identity: _billing.identity,
          defaultEmail: _emailCtrl.text,
          defaultPhone: _bookingPhone,
        ),
        ...customerBookingBookContractFields(
          selection: selection,
          kind: _airportMode
              ? CustomerBookingKind.airport
              : CustomerBookingKind.taxi,
          quote: _quote,
        ),
      };
      if (_airportMode) {
        companyRideOptionsStripWaitFields(body);
      }
      final result = await _quoteClient.book(
        body: customerBookingBindFinancialQuote(body, _quote),
        entry: _entry,
        headers: headers,
        recoveryOwner: _financialRecoveryOwner,
      );
      _bookPosted = true;
      final checkout = customerBookingCheckoutPlan(
        isMollieCheckout: selection.isMollieCheckout,
        response: result,
      );
      if (checkout.requiredCheckout && !checkout.hasSafeUrl) {
        throw const CustomerBookingBookException(
          statusCode: 200,
          code: kCustomerBookingIssueCheckoutStart,
          raw: 'checkout_url_missing',
        );
      }
      final bookingId = customerBookingIdFromResponse(result);
      final assigned = customerBookingAssignedDriverFromMaps(booking: result);
      final paymentBookingId = checkout.paymentBookingId.isNotEmpty
          ? checkout.paymentBookingId
          : bookingId;
      final stored = StoredCustomerBooking(
        bookingId: bookingId.isEmpty ? _idempotencyKey : bookingId,
        tenantId: _entry.company.tenantId,
        companyId: _entry.company.companyId,
        paymentBookingId: paymentBookingId,
        from: _pickup.value.routeText,
        to: _dropoff.value.routeText,
        pickupIso: pickupAt == null
            ? ''
            : (_whenNow
                  ? pickupAt.toUtc().toIso8601String()
                  : companyPlanPickupIso(pickupAt)),
        price: _quote?.displayTotalPrice?.toDouble(),
        currency: _quote?.currency ?? 'EUR',
        service: _options.service,
        pax: '$_passengers',
        bags: '$_bags',
        paymentStatus: customerBookingStoredPaymentStatus(
          isMollieCheckout: selection.isMollieCheckout,
          response: result,
        ),
        status: 'CONFIRMED',
        companyName: _entry.company.companyName,
        quote: <String, dynamic>{
          if (_quote?.financialQuoteId.isNotEmpty ?? false) 'financial_quote_id': _quote!.financialQuoteId,
          if (result['financial_snapshot'] != null) 'financial_snapshot': result['financial_snapshot'],
          if (totalPrice != null) 'price_incl_vat': totalPrice,
          if (totalPrice != null) 'total_price_incl_vat': totalPrice,
          if (_quote?.outboundPriceInclVat != null)
            'outbound_price_incl_vat': _quote!.outboundPriceInclVat,
          if (_quote?.returnPriceInclVat != null)
            'return_price_incl_vat': _quote!.returnPriceInclVat,
          if (assigned.assigned)
            'assigned_driver': <String, dynamic>{
              'driver_id': assigned.driverId,
              'first_name': assigned.firstName,
              'photo_url': assigned.photoUrl,
              'rating_avg': assigned.ratingAverage,
              'rating_count': assigned.ratingCount,
              'reviews_url': assigned.reviewsUrl,
            },
          if (_splitReturn && returnAssignedDriverId.isNotEmpty)
            'return_assigned_driver': <String, dynamic>{
              'driver_id': returnAssignedDriverId,
              'first_name': _assignedReturnDriver.firstName,
              'photo_url': _assignedReturnDriver.photoUrl,
            },
        },
      );
      if (!mounted) return;
      setState(() {
        _successId = stored.bookingId;
        _submitting = false;
        _submitError = null;
        _assignedDriver = assigned;
      });
      await _persistBookedRide(stored);
      if (!mounted) return;
      if (checkout.requiredCheckout) {
        final hosted = widget.hostedCheckout;
        final opened = hosted != null
            ? await hosted(checkout)
            : await (widget.checkoutOpener ?? _launchCustomerBookingCheckout)(
                checkout.checkoutUrl,
              );
        if (!opened) {
          if (!mounted) return;
          setState(() {
            _submitError = customerBookingSubmitIssueText(
              kCustomerBookingIssueCheckoutStart,
              _language,
            );
          });
          return;
        }
      }
      if (!mounted) return;
      if ((_quote?.financialQuoteId ?? '').isNotEmpty) {
        await _quoteClient.financialJournal.complete(_quoteClient.acceptanceKey(_entry, _financialRecoveryOwner));
      }
      _returnToCustomerHome(
        notice: checkout.requiredCheckout
            ? _t(kCustomerBookingCompletePayment)
            : _t(kCustomerBookingSuccess),
      );
    } catch (error) {
      if (!mounted) return;
      if (error is StateError && error.message == 'requote_required') {
        _quotes.invalidate();
        setState(() { _quote = null; _bookPosted = false; _bookUncertain = false; _submitting = false;
          _submitError = 'Deze offerte is verlopen. Controleer de nieuwe prijs.'; });
        unawaited(_refreshQuote());
        return;
      }
      if ((_quote?.financialQuoteId ?? '').isNotEmpty) {
        final pending = await _quoteClient.pendingAcceptance(_entry, _financialRecoveryOwner);
        if (mounted && pending != null) setState(() => _pendingFinancialAcceptance = pending);
      }
      final mapped = customerBookingBookExceptionFromCaught(error);
      customerBookingLogBookFailure(mapped);
      final code = customerBookingBookIssueFromException(mapped);
      if (code == kCustomerBookingIssueRequestQuoteRequired) {
        _bookPosted = false;
        _bookUncertain = false;
        if (!mounted) return;
        setState(() {
          _submitting = false;
          _submitError = null;
          _quoteLoading = false;
          _quoteError = null;
          _quote = customerBookingAirportContactQuote(
            _quote,
            quoteReason: mapped.quoteReason.isNotEmpty
                ? mapped.quoteReason
                : _airportMode
                ? ''
                : 'taxi_work_area_unverified',
          );
        });
        return;
      }
      if (mapped.uncertain) _bookUncertain = true;
      if (mapped.sent && mapped.statusCode >= 200 && mapped.statusCode < 300) {
        _bookPosted = true;
      }
      setState(() {
        _submitting = false;
        _submitError = customerBookingSubmitIssueText(code, _language);
      });
      if (code == kCustomerBookingIssueNeedPickup ||
          code == kCustomerBookingIssueNeedDropoff ||
          code == kCustomerBookingIssueNeedWhen ||
          code == kCustomerBookingIssueNeedName ||
          code == kCustomerBookingIssueNeedPhone ||
          code == kCustomerBookingIssueNeedCompany) {
        _revealSubmitIssue(
          CustomerBookingSubmitIssue(
            code: code,
            focusKey: switch (code) {
              kCustomerBookingIssueNeedPickup => 'pickup',
              kCustomerBookingIssueNeedDropoff => 'dropoff',
              kCustomerBookingIssueNeedWhen => 'when',
              kCustomerBookingIssueNeedName => 'name',
              kCustomerBookingIssueNeedPhone => 'phone',
              _ => 'company',
            },
          ),
        );
      }
    }
  }

  Future<String> _customerAuthToken() async {
    try {
      final cached = CustomerSessionStore.instance.peekCachedSession();
      if (cached != null && CustomerSessionStore.instance.isValid(cached)) {
        return cached.customerSessionToken.trim();
      }
    } catch (_) {}
    try {
      final session = await CustomerSessionStore.instance
          .loadValidSession()
          .timeout(const Duration(milliseconds: 250));
      return (session?.customerSessionToken ?? '').trim();
    } catch (_) {
      return '';
    }
  }

  Future<void> _persistBookedRide(StoredCustomerBooking stored) async {
    try {
      await CustomerBookingsStore.instance.upsert(stored);
    } catch (_) {
      // Keep acceptance recovery when storing a financial ride fails.
      if (stored.quote['financial_quote_id'] != null) rethrow;
    }
  }

  Future<bool> _launchCustomerBookingCheckout(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _returnToCustomerHome({String? notice}) {
    if (!mounted) return;
    CustomerBookingHomeNotice.set(notice ?? _t(kCustomerBookingSuccess));
    final home = widget.onGoToStartPage;
    if (home != null) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: home),
        (route) => route.isFirst,
      );
      return;
    }
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(_successId);
    }
  }

  ScrollController get _activeFormScroll =>
      (_sheetScroll != null && _sheetScroll!.hasClients)
      ? _sheetScroll!
      : _formScroll;

  Future<void> _animateSheetTo(double size) async {
    if (!_sheetController.isAttached) {
      if (mounted) setState(() => _sheetExtent = size);
      return;
    }
    _sheetAnimating = true;
    try {
      await _sheetController.animateTo(
        size,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } catch (_) {
      if (_sheetController.isAttached) {
        _sheetController.jumpTo(size);
      }
    }
    _sheetAnimating = false;
    if (!mounted) return;
    final next = _sheetController.isAttached ? _sheetController.size : size;
    setState(() => _sheetExtent = next);
  }

  void _revealSubmitIssue(CustomerBookingSubmitIssue issue) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (_sheetController.isAttached) {
        final sizes = customerBookingSheetSizes(
          height: MediaQuery.sizeOf(context).height,
          keyboardOpen: MediaQuery.viewInsetsOf(context).bottom > 80,
          textScale: MediaQuery.textScalerOf(context).scale(1),
        );
        await _animateSheetTo(sizes.max);
      }
      if (!mounted || !_activeFormScroll.hasClients) return;
      final jumpDown =
          issue.focusKey == 'name' ||
          issue.focusKey == 'phone' ||
          issue.focusKey == 'quote' ||
          issue.focusKey == 'when';
      final target = jumpDown
          ? _activeFormScroll.position.maxScrollExtent
          : 0.0;
      _activeFormScroll.animateTo(
        target,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    });
  }

  void _onAppLanguageChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _reliableHttp.close();
    _profileGpsWaitTimer?.cancel();
    final gpsWait = _profileGpsWaitCompletion;
    if (gpsWait != null && !gpsWait.isCompleted) gpsWait.complete();
    _profileGpsWaitCompletion = null;
    appLanguageNotifier.removeListener(_onAppLanguageChanged);
    _quoteDebounce?.cancel();
    _sheetController.removeListener(_onSheetControllerTick);
    _sheetController.dispose();
    _sheetExtentNotifier.dispose();
    _pickupFocus.dispose();
    _dropoffFocus.dispose();
    _formScroll.dispose();
    _pickup.dispose();
    _dropoff.dispose();
    _returnPickup.dispose();
    _returnDropoff.dispose();
    for (final stop in _stops) {
      stop.dispose();
    }
    for (final stop in _returnStops) {
      stop.dispose();
    }
    _flightCtrl.dispose();
    _arrivalMarginCtrl.dispose();
    _pickupAfterCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _airportSearchCtrl.dispose();
    _billing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CustomerThemeVariant>(
      valueListenable: customerThemeNotifier,
      builder: (context, _, __) {
        final theme = themeForCustomerPalette(Theme.of(context), _palette);
        return Theme(
          data: theme,
          child: Scaffold(
            key: kCustomerBookingFlowKey,
            backgroundColor: _palette.background,
            appBar: AppBar(
              title: Text(
                _t(customerBookingTitleFor(_entry)),
                key: kCustomerBookingTitleKey,
              ),
            ),
            body: SafeArea(
              child: _contextInvalid
                  ? Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        _t(kCustomerBookingInvalidContext),
                        key: kCustomerBookingContextErrorKey,
                        style: theme.textTheme.bodyLarge,
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final media = MediaQuery.of(context);
                        final textScale = media.textScaler.scale(1);
                        final keyboardOpen = media.viewInsets.bottom > 80;
                        final short = constraints.maxHeight < 520;
                        final sheet = customerBookingSheetSizes(
                          height: constraints.maxHeight,
                          keyboardOpen: keyboardOpen,
                          textScale: textScale,
                        );
                        final map = ValueListenableBuilder<double>(
                          valueListenable: _sheetExtentNotifier,
                          builder: (context, extent, _) {
                            return _bookingMap(
                              wide: false,
                              height: constraints.maxHeight,
                              sheetExtent: extent.clamp(sheet.min, sheet.max),
                            );
                          },
                        );
                        final confirm = _confirmBar(
                          compact: true,
                          inlinePrice: true,
                        );
                        final audience = Padding(
                          padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _audienceToggle(),
                              if (_businessRide) _billingForm(),
                            ],
                          ),
                        );
                        final planeHeight = customerBookingAirplaneHeight(
                          wide: constraints.maxWidth >= 720,
                          short: short,
                        );
                        final airplane = _showAirplane && planeHeight > 0
                            ? Padding(
                                padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
                                child: KeyedSubtree(
                                  key: kCustomerBookingAirplaneVisualKey,
                                  child: CompanyPlanAirportModeVisual(
                                    semanticLabel: _t(
                                      kCustomerBookingAirportMode,
                                    ),
                                    height: planeHeight,
                                  ),
                                ),
                              )
                            : const SizedBox.shrink();
                        final airportChrome = _airportMode
                            ? Padding(
                                padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
                                child: Column(
                                  key: kCustomerBookingAirportChromeKey,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: _airportChromeFields(theme),
                                ),
                              )
                            : const SizedBox.shrink();
                        return CustomerBookingMapSheetShell(
                          palette: _palette,
                          sizes: sheet,
                          controller: _sheetController,
                          map: map,
                          handle: _sheetHandle(
                            parentHeight: constraints.maxHeight,
                            sizes: sheet,
                          ),
                          formChildren: _phoneBookingFields(
                            theme,
                            airplane: airplane,
                            audience: audience,
                            airportChrome: airportChrome,
                          ),
                          confirm: confirm,
                          onExtent: (extent) {
                            _sheetExtent = extent;
                            _sheetExtentNotifier.value = extent;
                          },
                          onAssignScroll: (scrollController) {
                            _sheetScroll = scrollController;
                          },
                        );
                      },
                    ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _phoneBookingFields(
    ThemeData theme, {
    required Widget airplane,
    required Widget audience,
    required Widget airportChrome,
  }) {
    final showDropoff = !_airportMode || !_toAirport || _airport == null;
    return [
      Column(
        key: kCustomerBookingCompactSummaryKey,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_airportMode) airplane,
          if (_airportMode) airportChrome,
          if (!_hasChosenCompany)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FilledButton(
                key: kCustomerBookingCompanyChooseKey,
                onPressed: _changeCompany,
                child: Text(_t(kCustomerBookingChooseCompany)),
              ),
            )
          else
            _companyBanner(),
          audience,
          if (_entry.showTaxiAirportToggle) _modeToggle(),
          if (_gpsFallback)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _t(kCustomerBookingGpsFallback),
                key: kCustomerBookingGpsFallbackKey,
              ),
            ),
          if (_gpsBusy)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: LinearProgressIndicator(),
            ),
          LimousineAddressField(
            controller: _pickup,
            label: _t(kCustomerBookingPickupAsk),
            tokens: _tokens,
            language: _language,
            showCanonicalEcho: false,
            showCurrentLocation: false,
            isPickupField: true,
            inputKey: kCustomerBookingPickupKey,
            focusNode: _pickupFocus,
          ),
          if (_pickupNeedsConfirm)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _t(kCustomerBookingCheckPickup),
                    key: kCustomerBookingConfirmPickupBannerKey,
                    style: TextStyle(
                      color: _palette.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  OverflowBar(
                    spacing: 4,
                    children: [
                      TextButton(
                        key: kCustomerBookingInspectPickupKey,
                        onPressed: _inspectPickupOnMap,
                        child: Text(_t(kCustomerBookingInspectPickup)),
                      ),
                      TextButton(
                        key: kCustomerBookingAddressConfirmKey,
                        onPressed: _confirmPickupOnMap,
                        child: Text(_t(kCustomerBookingAddressConfirmMap)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          if (!_airportMode || _toAirport) _pickupActions(),
          ..._stopFields(inbound: false),
          if (showDropoff)
            LimousineAddressField(
              controller: _dropoff,
              label: _t(kCustomerBookingDropoffAsk),
              tokens: _tokens,
              language: _language,
              showCanonicalEcho: false,
              inputKey: kCustomerBookingDropoffKey,
              focusNode: _dropoffFocus,
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: kCustomerBookingAddStopKey,
              onPressed: () => _addStop(inbound: false),
              child: Text(_t(kCustomerBookingAddStop)),
            ),
          ),
          if (!_airportMode) _whenToggle(),
          _laterWhenFields(),
          CustomerBookingStableVehicleSpace(
            key: ValueKey('booking_vehicle_layout_slot_${_entry.company.routingPartnerId}_$_airportMode'),
            retain: _retainVehicleSpace,
            updating: (_quoteDebounce?.isActive ?? false) || _quoteLoading || _availabilityLoading || _returnAvailabilityLoading,
            child: _vehicleRow(),
          ),
          _paxCompactRow(),
          if (!companyPlanVehicleTypeFitsCapacity(
            type: _vehicle,
            passengers: _passengers,
            bags: _bags,
          ))
            Text(_t(kCustomerBookingSuggestLarger)),
          _phoneReturnSection(),
          ..._contactFields(),
          if (_successId != null && _whenNow && _activeReliableApi != null)
            CustomerReliableChoicePanelV1(api:_activeReliableApi!,bookingId:_successId!,statusOnly:true,language:_language,palette:_palette),
          if (_successId != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                [
                  _t(kCustomerBookingSuccess),
                  if (customerBookingCompanyVisibleName(
                    _entry.company,
                  ).isNotEmpty)
                    customerBookingCompanyVisibleName(_entry.company),
                  _successId!,
                ].where((part) => part.trim().isNotEmpty).join(' · '),
                key: kCustomerBookingSuccessKey,
              ),
            ),
        ],
      ),
    ];
  }

  String get _tripSummaryLine {
    final quote = _quote;
    if (quote == null || !quote.hasRoute) return '';
    final from = _pickup.value.displayText.trim();
    final to = _dropoff.value.displayText.trim();
    return [
      if (from.isNotEmpty && to.isNotEmpty) '$from → $to',
      formatCompanyPlanQuoteRoute(quote, _language),
      if (!_whenNow && _pickupAt != null)
        '${_t(kCustomerBookingDate)} ${_formatDate(_pickupAt)} · ${_t(kCustomerBookingTime)} ${_formatClock(_pickupAt)}',
    ].where((part) => part.trim().isNotEmpty).join(' · ');
  }

  Widget _bookingMap({
    required bool wide,
    required double height,
    required double sheetExtent,
  }) {
    final candidate = _pickup.locationCandidate;
    final hasRoute = _quote?.hasRoute == true;
    return CustomerBookingRouteMap(
      key: kCustomerBookingMapKey,
      language: _language,
      palette: _palette,
      pickup: _pickup.value,
      dropoff: _dropoff.value,
      stops: [for (final stop in _stops) stop.value],
      quote: _quote,
      quoteLoading: _quoteLoading && !hasRoute,
      errorText: hasRoute || !_hasChosenCompany ? null : _quoteError,
      onRetry: hasRoute || !_hasChosenCompany ? null : _refreshQuote,
      pickupLocal: _whenNow ? DateTime.now() : _pickupAt,
      geometryClient: widget.routeGeometryClient,
      pickupNeedsConfirm: _pickupNeedsConfirm,
      confirmLat: candidate?.lat ?? _pickup.value.lat,
      confirmLon: candidate?.lon ?? _pickup.value.lon,
      onConfirmPickup: _confirmPickupOnMap,
      pickupInspectSeq: _pickupInspectSeq,
      fitInsets: customerBookingMapFitInsets(
        wide: wide,
        height: height,
        sheetExtent: sheetExtent,
      ),
      cameraFitInsets: customerBookingMapFitInsets(
        wide: wide,
        height: height,
        sheetExtent: wide ? 0.0 : _snappedSheetExtent,
      ),
      framed: wide,
      onEditPickup: () => _editAddressFromMap(pickup: true),
      onEditDropoff: () => _editAddressFromMap(pickup: false),
      onRouteMetrics: (geometry) {
        final nextMin = geometry?.durationMin;
        final nextKm = geometry?.distanceKm;
        if (nextMin == _geometryDurationMin && nextKm == _geometryDistanceKm) {
          return;
        }
        setState(() {
          _geometryDurationMin = nextMin;
          _geometryDistanceKm = nextKm;
        });
        _applySuggestedPickup();
        unawaited(_refreshAvailability());
      },
    );
  }

  Widget _sheetHandle({
    required double parentHeight,
    required CustomerBookingSheetSizes sizes,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (details) {
        _dragSheetBy(details.delta.dy, parentHeight, sizes);
      },
      child: SizedBox(
        height: 28,
        child: Center(
          child: Container(
            key: kCustomerBookingSheetHandleKey,
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: _palette.border,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
      ),
    );
  }

  Widget _paxCompactRow() {
    return Column(
      children: [
        Material(
          key: kCustomerBookingPaxSummaryKey,
          color: Colors.transparent,
          child: InkWell(
            onTap: () =>
                setState(() => _compactCountsOpen = !_compactCountsOpen),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.person_outline,
                    color: _palette.textMuted,
                    size: 20,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$_passengers',
                    style: TextStyle(
                      color: _palette.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Icon(
                    Icons.luggage_outlined,
                    color: _palette.textMuted,
                    size: 20,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$_bags',
                    style: TextStyle(
                      color: _palette.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_compactCountsOpen ||
            _quote?.requiresAirportFareContact == true) ...[
          _countRow(
            label: _t(kCustomerBookingPassengers),
            value: _passengers,
            incrementKey: kCustomerBookingPaxIncKey,
            onChanged: (value) {
              setState(() {
                _compactCountsOpen = true;
                _retainVehicleSpace = true;
                _passengers = _clampPassengers(value);
              });
              _suggestVehicleIfNeeded();
              _onDraftChanged(resetOffer: false);
            },
          ),
          _countRow(
            label: _t(kCustomerBookingBags),
            value: _bags,
            incrementKey: kCustomerBookingBagsIncKey,
            onChanged: (value) {
              setState(() {
                _compactCountsOpen = true;
                _retainVehicleSpace = true;
                _bags = value;
              });
              _suggestVehicleIfNeeded();
              _onDraftChanged(resetOffer: false);
            },
          ),
        ],
      ],
    );
  }

  Widget _phoneReturnSection({bool compact = false}) {
    if (_returnKind == CustomerBookingReturnKind.oneWay) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: kCustomerBookingAddReturnKey,
          onPressed: () {
            setState(() {
              _returnKind = CustomerBookingReturnKind.noWait;
              _selectedReturnVehicleId = null;
              _assignedReturnDriver = const CustomerBookingAssignedDriver();
              _returnAvailability = const CustomerBookingAvailabilitySnapshot();
              _returnAt ??= (_pickupAt ?? DateTime.now()).add(
                const Duration(days: 1),
              );
            });
            _syncReturnDefaults();
            _onDraftChanged();
          },
          icon: Icon(Icons.add, color: _palette.textPrimary),
          label: Text(
            _t(kCustomerBookingAddReturn),
            style: TextStyle(
              color: _palette.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _t(kCustomerBookingReturnNoWait),
                style: TextStyle(
                  color: _palette.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton(
              key: kCustomerBookingOneWayKey,
              onPressed: () {
                setState(() {
                  _returnKind = CustomerBookingReturnKind.oneWay;
                  _selectedReturnVehicleId = null;
                  _assignedReturnDriver = const CustomerBookingAssignedDriver();
                  _returnAvailability =
                      const CustomerBookingAvailabilitySnapshot();
                });
                _onDraftChanged();
              },
              child: Text(_t(kCustomerBookingRemoveReturn)),
            ),
          ],
        ),
        if (_allowsWait)
          FilterChip(
            key: kCustomerBookingReturnWaitKey,
            label: Text(_t(kCustomerBookingWaitOption)),
            selected: _returnKind == CustomerBookingReturnKind.wait,
            onSelected: (selected) {
              setState(() {
                _returnKind = selected
                    ? CustomerBookingReturnKind.wait
                    : CustomerBookingReturnKind.noWait;
              });
              _syncReturnDefaults();
              _onDraftChanged();
            },
          ),
        if (!compact) ...[
          if (_returnKind != CustomerBookingReturnKind.oneWay) ...[
            LimousineAddressField(
              controller: _returnPickup,
              label: _t(kCustomerBookingReturnPickup),
              tokens: _tokens,
              language: _language,
              showCanonicalEcho: false,
            ),
            LimousineAddressField(
              controller: _returnDropoff,
              label: _t(kCustomerBookingReturnDropoff),
              tokens: _tokens,
              language: _language,
              showCanonicalEcho: false,
            ),
          ],
          if (_returnKind == CustomerBookingReturnKind.noWait)
            _returnWhenFields(),
          if (_returnKind == CustomerBookingReturnKind.wait && _allowsWait)
            _waitChips(),
        ],
      ],
    );
  }

  Future<void> _editAddressFromMap({required bool pickup}) async {
    if (!pickup && _airportMode && _toAirport) {
      setState(() => _airportPickerOpen = true);
    }
    if (_sheetController.isAttached) {
      final sizes = customerBookingSheetSizes(
        height: MediaQuery.sizeOf(context).height,
        keyboardOpen: MediaQuery.viewInsetsOf(context).bottom > 80,
        textScale: MediaQuery.textScalerOf(context).scale(1),
      );
      await _animateSheetTo(sizes.max);
    }
    if (!mounted) return;
    if (!pickup && _airportMode && _toAirport) return;
    (pickup ? _pickupFocus : _dropoffFocus).requestFocus();
  }

  Future<void> _launchPublicUri(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _openAirportFareContact() async {
    final contact = _publicContact;
    if (!mounted) return;
    if (!contact.hasAny) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          key: kCustomerBookingAirportNoContactKey,
          content: Text(_t(kCustomerBookingAirportNoPublicContact)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            key: kCustomerBookingPublicContactSheetKey,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                title: Text(
                  _copy(
                    nl: 'Offerteaanvraag kopiëren',
                    en: 'Copy quote request',
                    fr: 'Copier la demande de devis',
                    es: 'Copiar solicitud de presupuesto',
                  ),
                ),
                subtitle: Text(
                  _copy(
                    nl: 'Met ritgegevens, passagiers, bagage en voertuigvoorkeur.',
                    en: 'Includes ride details, passengers, luggage and vehicle preference.',
                    fr: 'Trajet, passagers, bagages et véhicule souhaité.',
                    es: 'Incluye trayecto, pasajeros, equipaje y vehículo preferido.',
                  ),
                ),
                onTap: () async {
                  await Clipboard.setData(
                    ClipboardData(text: _quoteContactSummary),
                  );
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
              if (contact.phone.isNotEmpty)
                ListTile(
                  key: kCustomerBookingPublicPhoneKey,
                  title: Text(contact.phone),
                  onTap: () => unawaited(
                    _launchPublicUri(
                      Uri(
                        scheme: 'tel',
                        path: contact.phone.replaceAll(RegExp(r'\s'), ''),
                      ),
                    ),
                  ),
                ),
              if (contact.email.isNotEmpty)
                ListTile(
                  key: kCustomerBookingPublicEmailKey,
                  title: Text(contact.email),
                  onTap: () => unawaited(
                    _launchPublicUri(
                      customerQuoteEmailUri(
                        contact.email,
                        _quoteContactSummary,
                      ),
                    ),
                  ),
                ),
              if (contact.website.isNotEmpty)
                ListTile(
                  key: kCustomerBookingPublicWebsiteKey,
                  title: Text(contact.website),
                  onTap: () {
                    final uri = Uri.tryParse(contact.website);
                    if (uri != null) unawaited(_launchPublicUri(uri));
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  String _visibleConfirmReasonText(
    CustomerBookingConfirmCondition failure,
    AppLanguage language, {
    DateTime? suggestedPickup,
  }) {
    if (_whenNow &&
        failure.detail != 'choose_vehicle' &&
        const {
          kCustomerBookingIssueNeedVehicle,
          kCustomerBookingIssueUnavailable,
        }.contains(failure.id)) {
      final message = customerBookingLiveAvailabilityMessage(
        _availability.reasons.values,
      );
      if (message != null) return message.of(language);
    }
    return customerBookingConfirmReasonText(
      failure,
      language,
      suggestedPickup: suggestedPickup,
    );
  }

  Widget _confirmBar({bool compact = false, bool inlinePrice = false}) {
    if (_pendingFinancialAcceptance != null) return _financialRecoveryPanel();
    final quote = _quote;
    if (quote != null &&
        !_pickupNeedsConfirm &&
        quote.requiresAirportFareContact) {
      final failure = _confirmDecision.firstFailure;
      final failureText =
          failure == null ||
              failure.id == kCustomerBookingIssueRequestQuoteRequired
          ? null
          : _visibleConfirmReasonText(
              failure,
              _language,
              suggestedPickup: _confirmDecision.suggestedPickup,
            );
      final reason = (_submitError ?? failureText)?.trim();
      return Material(
        color: _palette.background,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            compact ? 2 : 8,
            16,
            compact ? 6 : 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (reason != null && reason.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    reason,
                    key: kCustomerBookingConfirmReasonKey,
                    style: TextStyle(
                      color: _palette.danger,
                      fontWeight: FontWeight.w700,
                      fontSize: compact ? 11 : 13,
                    ),
                  ),
                ),
              CustomerBookingAirportFareNotice(
                language: _language,
                companyName: customerBookingCompanyVisibleName(_entry.company),
                quoteReason: quote.quoteReason,
                leadTimeLabel: quote.leadTimeLabel,
                showLeadTime: quote.conditionCodes.contains('lead_time'),
                onContact: () => unawaited(_openAirportFareContact()),
              ),
            ],
          ),
        ),
      );
    }
    final onRequest =
        quote != null &&
        !_pickupNeedsConfirm &&
        customerBookingQuoteIsOnRequest(quote);
    final incl = quote == null ? null : customerBookingQuoteInclVat(quote);
    final excl = quote == null ? null : customerBookingQuoteExVat(quote);
    final Widget? price = onRequest
        ? Text(
            _t(kCustomerBookingPriceOnRequest),
            key: kCustomerBookingPriceKey,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _palette.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: compact ? 14 : 16,
            ),
          )
        : incl == null
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                formatCompanyPlanQuoteMoney(incl, quote!.currency),
                key: kCustomerBookingPriceKey,
                style: TextStyle(
                  color: _palette.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: compact ? 18 : 20,
                ),
              ),
              Text(
                _t(kCustomerBookingTotalInclVat),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _palette.textMuted,
                  fontSize: compact ? 10 : 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (excl != null && !compact)
                Text(
                  '${formatCompanyPlanQuoteMoney(excl, quote.currency)} ${_t(kCustomerBookingTotalExVat)}',
                  style: TextStyle(color: _palette.textMuted, fontSize: 11),
                ),
            ],
          );
    final decision = _confirmDecision;
    final failure = decision.firstFailure;
    final quoteIssueText = (_quoteError ?? '').trim().isEmpty
        ? ''
        : customerBookingQuoteErrorText(_quoteError, _language);
    final failureText = failure == null
        ? null
        : (failure.id == kCustomerBookingIssueNeedQuote &&
                  quoteIssueText.isNotEmpty
              ? quoteIssueText
              : _visibleConfirmReasonText(
                  failure,
                  _language,
                  suggestedPickup: decision.suggestedPickup,
                ));
    final reasonText = _successId != null || _confirmInFlight || _submitting
        ? _submitError
        : (_submitError ?? failureText);
    final button = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: FilledButton(
        key: kCustomerBookingConfirmKey,
        onPressed: decision.canConfirm ? _confirm : null,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          textStyle: TextStyle(
            fontSize: compact ? 14 : 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        child: _submitting
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(
                _t(
                  compact
                      ? kCustomerBookingConfirmShort
                      : kCustomerBookingConfirm,
                ),
              ),
      ),
    );
    return Material(
      color: _palette.background,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, compact ? 2 : 8, 16, compact ? 6 : 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (reasonText != null)
              Padding(
                key: kCustomerBookingConfirmReasonKey,
                padding: EdgeInsets.only(bottom: compact ? 4 : 8),
                child: Text(
                  reasonText,
                  key: _submitError != null
                      ? kCustomerBookingSubmitErrorKey
                      : const ValueKey('customer_booking_confirm_reason_text'),
                  maxLines: compact ? 1 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _palette.danger,
                    fontWeight: FontWeight.w700,
                    fontSize: compact ? 11 : 13,
                  ),
                ),
              ),
            if (_submitting)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _t(kCustomerBookingSubmitting),
                  key: kCustomerBookingSubmittingKey,
                ),
              ),
            if (inlinePrice && compact && price != null)
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: price),
                  const SizedBox(width: 12),
                  Flexible(child: button),
                ],
              )
            else ...[
              if (inlinePrice && price != null) ...[
                price,
                const SizedBox(height: 8),
              ],
              SizedBox(width: double.infinity, child: button),
            ],
          ],
        ),
      ),
    );
  }

  Widget _companyBanner() {
    final chosen = _hasChosenCompany;
    final name = customerBookingCompanyVisibleName(_entry.company);
    return Material(
      key: kCustomerBookingCompanyBannerKey,
      color: _palette.surface,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final layout = customerBookingCompanyBannerLayout(
              innerWidth: constraints.maxWidth,
              textScale: MediaQuery.textScalerOf(context).scale(1),
            );
            final logo = _companyLogoMark(
              maxWidth: layout.logoMaxWidth,
              maxHeight: layout.logoMaxHeight,
            );
            final text = chosen
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        key: kCustomerBookingCompanyLockKey,
                        style: TextStyle(
                          color: _palette.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (!_entry.lockCompany)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            key: kCustomerBookingChangeCompanyKey,
                            onPressed: _changeCompany,
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(_t(kCustomerBookingChangeCompany)),
                          ),
                        ),
                      if (_presentation.hasBadge || _presentation.hasNotice)
                        PublicCompanyPresentationBanner(
                          presentation: _presentation,
                          compact: true,
                          onInfo: _presentation.hasNotice
                              ? () => _showExampleNotice()
                              : null,
                        ),
                    ],
                  )
                : Text(
                    _t(kCustomerBookingChooseCompany),
                    key: kCustomerBookingCompanyChooseKey,
                    style: TextStyle(
                      color: _palette.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  );
            if (layout.stack) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(alignment: Alignment.center, child: logo),
                  SizedBox(height: layout.gap),
                  text,
                ],
              );
            }
            if (layout.equalSplit) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Align(alignment: Alignment.center, child: logo),
                  ),
                  SizedBox(width: layout.gap),
                  Expanded(child: text),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                logo,
                SizedBox(width: layout.gap),
                Expanded(child: text),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _companyLogoMark({
    required double maxWidth,
    required double maxHeight,
  }) {
    final iconSize = maxHeight.clamp(22.0, 40.0);
    if (_companyLogoUrl.isNotEmpty) {
      return SizedBox(
        width: maxWidth,
        height: maxHeight,
        child: Image.network(
          _companyLogoUrl,
          key: kCustomerBookingCompanyLogoImageKey,
          width: maxWidth,
          height: maxHeight,
          fit: BoxFit.contain,
          alignment: Alignment.center,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) =>
              Center(child: _neutralCompanyIcon(iconSize)),
        ),
      );
    }
    return SizedBox(
      width: maxWidth,
      height: maxHeight,
      child: Center(child: _neutralCompanyIcon(iconSize)),
    );
  }

  Widget _neutralCompanyIcon(double size) {
    return Icon(
      Icons.apartment_outlined,
      key: kCustomerBookingCompanyLogoFallbackKey,
      size: size,
      color: _palette.textMuted,
    );
  }

  void _inspectPickupOnMap() {
    setState(() => _pickupInspectSeq += 1);
  }

  void _confirmPickupOnMap() {
    _pickupGeocodeSeq += 1;
    final candidate = _pickup.locationCandidate;
    if (candidate != null && candidate.hasCoordinates) {
      _pickup.confirmCandidateLocation();
    } else if (_pickup.value.hasCoordinates) {
      _pickup.confirmCandidateLocation();
    } else {
      LimousinePlaceSuggestion? pin;
      for (final item in _pickup.suggestions) {
        if (item.hasCoordinates && item.isStreetLevel) {
          pin = item;
          break;
        }
      }
      if (pin == null) {
        for (final item in _pickup.suggestions) {
          if (item.hasCoordinates) {
            pin = item;
            break;
          }
        }
      }
      if (pin == null) return;
      _pickup.locationCandidate = pin;
      _pickup.confirmCandidateLocation();
    }
    final confirmed = _pickup.value;
    if (confirmed.hasCoordinates) {
      unawaited(
        CustomerConfirmedLocationStore.instance.save(
          label: confirmed.displayText,
          latitude: confirmed.lat!,
          longitude: confirmed.lon!,
        ),
      );
    }
    setState(() {});
    _onDraftChanged();
  }

  bool get _contactComplete {
    return _nameCtrl.text.trim().isNotEmpty &&
        _phoneCtrl.text.trim().isNotEmpty &&
        _emailCtrl.text.trim().isNotEmpty &&
        _phoneHint == null;
  }

  List<Widget> _contactFields() {
    if (_contactComplete && !_editingContact) {
      return [
        ListTile(
          key: kCustomerBookingContactSummaryKey,
          dense: true,
          visualDensity: VisualDensity.compact,
          contentPadding: EdgeInsets.zero,
          title: Text(
            [
              _nameCtrl.text.trim(),
              _phoneCtrl.text.trim(),
              _emailCtrl.text.trim(),
            ].where((part) => part.isNotEmpty).join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          trailing: TextButton(
            onPressed: () => setState(() => _editingContact = true),
            child: Text(_t(kCustomerBookingContactChange)),
          ),
        ),
      ];
    }
    return [
      TextField(
        key: kCustomerBookingNameKey,
        controller: _nameCtrl,
        decoration: InputDecoration(labelText: _t(kCustomerBookingName)),
        onChanged: (_) => setState(() {}),
      ),
      TextField(
        key: kCustomerBookingPhoneKey,
        controller: _phoneCtrl,
        decoration: InputDecoration(
          labelText: _t(kCustomerBookingPhone),
          helperText: _phoneHint,
          helperMaxLines: 3,
          helperStyle: TextStyle(color: _palette.danger),
        ),
        keyboardType: TextInputType.phone,
        onChanged: (_) => setState(() {}),
      ),
      TextField(
        controller: _emailCtrl,
        decoration: InputDecoration(labelText: _t(kCustomerBookingEmail)),
        keyboardType: TextInputType.emailAddress,
        onChanged: (_) => setState(() {}),
      ),
      if (_contactComplete)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => setState(() => _editingContact = false),
            child: Text(_t(kCustomerBookingContactChange)),
          ),
        ),
    ];
  }

  List<Widget> _airportChromeFields(ThemeData theme) {
    final size = MediaQuery.sizeOf(context);
    final showPicker = _airport == null || _airportPickerOpen || _browseCatalog;
    void expandSheetForCatalog() {
      unawaited(
        _animateSheetTo(
          customerBookingSheetSizes(
            height: size.height,
            keyboardOpen: MediaQuery.viewInsetsOf(context).bottom > 80,
            textScale: MediaQuery.textScalerOf(context).scale(1),
          ).max,
        ),
      );
    }

    return [
      _directionToggle(),
      const SizedBox(height: 12),
      if (!showPicker && _airport != null)
        _selectedAirportCard(theme, _airport!, compact: true)
      else ...[
        if (_airport != null)
          Offstage(
            offstage: true,
            child: Text(
              customerBookingAirportSummary(_airport!),
              key: kCustomerBookingAirportSummaryKey,
            ),
          ),
        CompanyPlanAirportDestinationCards(
          language: _language,
          selectedIata: _airport?.iata ?? '',
          compact: true,
          cardKeyOf: customerBookingAirportCardKey,
          onSelectedIata: (iata) {
            final record = companyPlanAirportCatalogRecord(iata);
            if (record != null) {
              _applyAirport(record, browse: false);
            }
          },
          onSelectedOther: () {
            setState(() {
              _browseCatalog = true;
              _airportPickerOpen = true;
            });
            expandSheetForCatalog();
          },
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: kCustomerBookingBrowseAllAirportsKey,
            onPressed: () {
              setState(() {
                _browseCatalog = true;
                _airportPickerOpen = true;
              });
              expandSheetForCatalog();
            },
            child: Text(_t(kCustomerBookingBrowseAllAirports)),
          ),
        ),
      ],
      if (_browseCatalog) _catalogPicker(),
      _flightFields(phone: true),
    ];
  }

  Widget _selectedAirportCard(
    ThemeData theme,
    AirportCatalogAirport airport, {
    bool compact = false,
  }) {
    final asset = companyPlanAirportCardAsset(airport.iata);
    final photo = asset.isEmpty
        ? ColoredBox(color: _palette.surfaceAlt)
        : Image.asset(
            asset,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                ColoredBox(color: _palette.surfaceAlt),
          );
    final summary = Text(
      compact
          ? customerBookingAirportCompactSummary(airport)
          : customerBookingAirportSummary(airport),
      key: kCustomerBookingAirportSummaryKey,
      maxLines: compact ? 1 : 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
    );
    final change = TextButton(
      onPressed: () {
        setState(() {
          _airportPickerOpen = true;
          _browseCatalog = false;
        });
      },
      child: Text(_t(kCustomerBookingChangeCompany)),
    );
    return Material(
      key: kCustomerBookingAirportSelectedKey,
      color: _palette.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: compact
          ? SizedBox(
              height: 68,
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(width: 56, height: 56, child: photo),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _t(
                              _toAirport
                                  ? kCustomerBookingToAirport
                                  : kCustomerBookingFromAirport,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: _palette.textMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          summary,
                          Offstage(
                            offstage: true,
                            child: Text(customerBookingAirportSummary(airport)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  change,
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(aspectRatio: 16 / 7, child: photo),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                  child: Row(
                    children: [
                      Expanded(child: summary),
                      change,
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  void _showExampleNotice() {
    if (!_presentation.hasNotice) return;
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            _presentation.badge.isEmpty
                ? _t(kCustomerBookingBookWith)
                : _presentation.badge,
          ),
          content: Text(
            _presentation.notice,
            key: kCustomerBookingExampleNoticeKey,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(_t(kCustomerBookingChangeCompany)),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _bookingFormFields(
    ThemeData theme, {
    bool includeWhen = true,
    bool includeCompany = true,
    bool phoneLayout = false,
    double confirmReserve = 16,
    bool includeConfirm = false,
    bool includeExtras = true,
  }) {
    return [
      if (includeWhen) ...[_whenToggle(), if (!_whenNow) _laterWhenFields()],
      if (includeCompany && !_hasChosenCompany)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: FilledButton(
            key: kCustomerBookingCompanyChooseKey,
            onPressed: _changeCompany,
            child: Text(_t(kCustomerBookingChooseCompany)),
          ),
        )
      else if (includeCompany)
        _companyBanner(),
      if (includeCompany) const SizedBox(height: 8),
      if (_entry.showTaxiAirportToggle) _modeToggle(),
      if (_gpsFallback)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            _t(kCustomerBookingGpsFallback),
            key: kCustomerBookingGpsFallbackKey,
          ),
        ),
      if (_gpsBusy)
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: LinearProgressIndicator(),
        ),
      LimousineAddressField(
        controller: _pickup,
        label: _t(kCustomerBookingPickupAsk),
        tokens: _tokens,
        language: _language,
        showCanonicalEcho: false,
        showCurrentLocation: true,
        isPickupField: true,
        inputKey: kCustomerBookingPickupKey,
        focusNode: _pickupFocus,
      ),
      if (_pickupNeedsConfirm)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _t(kCustomerBookingCheckPickup),
                key: kCustomerBookingConfirmPickupBannerKey,
                style: TextStyle(
                  color: _palette.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              OverflowBar(
                spacing: 4,
                children: [
                  TextButton(
                    key: kCustomerBookingInspectPickupKey,
                    onPressed: _inspectPickupOnMap,
                    child: Text(_t(kCustomerBookingInspectPickup)),
                  ),
                  TextButton(
                    key: kCustomerBookingAddressConfirmKey,
                    onPressed: _confirmPickupOnMap,
                    child: Text(_t(kCustomerBookingAddressConfirmMap)),
                  ),
                ],
              ),
            ],
          ),
        ),
      if (!_airportMode || _toAirport) _pickupActions(),
      ..._stopFields(inbound: false),
      if (!_airportMode || !_toAirport || _airport == null)
        LimousineAddressField(
          controller: _dropoff,
          label: _t(kCustomerBookingDropoffAsk),
          tokens: _tokens,
          language: _language,
          showCanonicalEcho: false,
          inputKey: kCustomerBookingDropoffKey,
          focusNode: _dropoffFocus,
        ),
      if (_airportMode && _toAirport && _airport != null)
        const SizedBox.shrink(),
      if (includeExtras)
        TextButton(
          key: kCustomerBookingAddStopKey,
          onPressed: () => _addStop(inbound: false),
          child: Text(_t(kCustomerBookingAddStop)),
        ),
      if (phoneLayout && includeExtras)
        _phoneReturnSection()
      else if (!phoneLayout)
        _returnToggle(),
      if (!phoneLayout && _returnKind != CustomerBookingReturnKind.oneWay) ...[
        LimousineAddressField(
          controller: _returnPickup,
          label: _t(kCustomerBookingReturnPickup),
          tokens: _tokens,
          language: _language,
          showCanonicalEcho: false,
        ),
        ..._stopFields(inbound: true),
        LimousineAddressField(
          controller: _returnDropoff,
          label: _t(kCustomerBookingReturnDropoff),
          tokens: _tokens,
          language: _language,
          showCanonicalEcho: false,
        ),
        TextButton(
          onPressed: () => _addStop(inbound: true),
          child: Text(_t(kCustomerBookingAddStop)),
        ),
      ],
      if (!phoneLayout && _returnKind == CustomerBookingReturnKind.noWait)
        _returnWhenFields(),
      if (!phoneLayout &&
          _returnKind == CustomerBookingReturnKind.wait &&
          _allowsWait)
        _waitChips(),
      const SizedBox(height: 8),
      if (!phoneLayout)
        Text(_t(kCustomerBookingVehicle), style: theme.textTheme.titleSmall),
      CustomerBookingStableVehicleSpace(
            key: ValueKey('booking_vehicle_layout_slot_${_entry.company.routingPartnerId}_$_airportMode'),
            retain: _retainVehicleSpace,
            updating: (_quoteDebounce?.isActive ?? false) || _quoteLoading || _availabilityLoading || _returnAvailabilityLoading,
            child: _vehicleRow(),
          ),
      const SizedBox(height: 8),
      if (includeExtras) ...[
        _countRow(
          label: _t(kCustomerBookingPassengers),
          value: _passengers,
          incrementKey: kCustomerBookingPaxIncKey,
          onChanged: (value) {
            setState(() {
                _compactCountsOpen = true;
                _retainVehicleSpace = true;
                _passengers = _clampPassengers(value);
              });
            _suggestVehicleIfNeeded();
            _onDraftChanged(resetOffer: false);
          },
        ),
        _countRow(
          label: _t(kCustomerBookingBags),
          value: _bags,
          incrementKey: kCustomerBookingBagsIncKey,
          onChanged: (value) {
            setState(() {
                _compactCountsOpen = true;
                _retainVehicleSpace = true;
                _bags = value;
              });
            _suggestVehicleIfNeeded();
            _onDraftChanged(resetOffer: false);
          },
        ),
        if (!companyPlanVehicleTypeFitsCapacity(
          type: _vehicle,
          passengers: _passengers,
          bags: _bags,
        ))
          Text(_t(kCustomerBookingSuggestLarger)),
      ],
      const SizedBox(height: 12),
      _quotePanel(hideTotals: phoneLayout),
      if (includeExtras) ..._contactFields(),
      const SizedBox(height: 12),
      if (includeConfirm) _confirmBar(compact: true),
      SizedBox(height: confirmReserve),
      if (_successId != null && _whenNow && _activeReliableApi != null)
        CustomerReliableChoicePanelV1(api:_activeReliableApi!,bookingId:_successId!,statusOnly:true,language:_language,palette:_palette),
      if (_successId != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            [
              _t(kCustomerBookingSuccess),
              if (customerBookingCompanyVisibleName(_entry.company).isNotEmpty)
                customerBookingCompanyVisibleName(_entry.company),
              _successId!,
            ].where((part) => part.trim().isNotEmpty).join(' · '),
            key: kCustomerBookingSuccessKey,
          ),
        ),
    ];
  }

  List<Widget> _stopFields({required bool inbound}) {
    final list = inbound ? _returnStops : _stops;
    return [
      for (var i = 0; i < list.length; i++)
        LimousineAddressField(
          controller: list[i],
          label: '${_t(kCustomerBookingAddStop)} ${i + 1}',
          tokens: _tokens,
          language: _language,
          showCanonicalEcho: false,
          inputKey: inbound ? null : customerBookingStopKey(i),
        ),
    ];
  }

  /// Contact phone in international form. Same rule for both audiences.
  ///
  /// The phone country comes from the stored profile only, never from the
  /// billing address.
  CustomerBookingPhone get _phoneState => resolveCustomerBookingPhone(
    phone: _phoneCtrl.text,
    phoneCountry: _profile?.phoneCountry ?? '',
  );

  String get _bookingPhone => customerBookingInternationalPhone(
    phone: _phoneCtrl.text,
    phoneCountry: _profile?.phoneCountry ?? '',
  );

  /// Asks the customer to clarify instead of guessing a country.
  String? get _phoneHint {
    switch (_phoneState.state) {
      case CustomerBookingPhoneState.needsCountry:
        return _t(kCustomerBookingPhoneNeedsCountry);
      case CustomerBookingPhoneState.invalid:
        return _t(kCustomerBookingPhoneInvalid);
      case CustomerBookingPhoneState.empty:
      case CustomerBookingPhoneState.international:
        return null;
    }
  }

  Widget _billingForm() {
    return BookingBillingIdentityForm(
      enabled: true,
      showToggle: false,
      controllers: _billing,
      style: BookingBillingFormStyle(
        accentColor: _palette.gold,
        labelColor: _palette.textPrimary,
        mutedColor: _palette.textMuted,
        fieldBackground: _palette.surface,
        fieldBorderColor: _palette.border,
        warningColor: _palette.danger,
      ),
      t: _copy,
      onEnabledChanged: (_) {},
      onChanged: () => setState(() {}),
      warning: _billingWarning,
    );
  }

  Widget _audienceToggle() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: _audienceChoice(
              key: kCustomerBookingPrivateRideKey,
              label: _t(kCustomerBookingPrivateRide),
              selected: !_businessRide,
              onTap: () => setState(() => _businessRide = false),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _audienceChoice(
              key: kCustomerBookingBusinessRideKey,
              label: _t(kCustomerBookingBusinessRide),
              selected: _businessRide,
              onTap: () {
                setState(() {
                  _businessRide = true;
                  customerBookingPrefillBillingFromProfile(_billing, _profile);
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _audienceChoice({
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      key: key,
      color: selected
          ? _palette.gold.withValues(alpha: 0.22)
          : _palette.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Center(
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _palette.textPrimary,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _modeToggle() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SegmentedButton<bool>(
        segments: [
          ButtonSegment(
            value: false,
            label: Text(
              _t(kCustomerBookingStreetMode),
              key: kCustomerBookingStreetModeKey,
            ),
            icon: const Icon(Icons.directions_car_outlined),
          ),
          ButtonSegment(
            value: true,
            label: Text(
              _t(kCustomerBookingAirportMode),
              key: kCustomerBookingAirportModeKey,
            ),
            icon: const Icon(Icons.flight_takeoff),
          ),
        ],
        selected: {_airportMode},
        onSelectionChanged: (value) => _setAirportMode(value.first),
      ),
    );
  }

  Widget _directionToggle() {
    return SegmentedButton<bool>(
      segments: [
        ButtonSegment(
          value: true,
          label: Text(
            _t(kCustomerBookingToAirport),
            key: kCustomerBookingToAirportKey,
          ),
        ),
        ButtonSegment(
          value: false,
          label: Text(
            _t(kCustomerBookingFromAirport),
            key: kCustomerBookingFromAirportKey,
          ),
        ),
      ],
      selected: {_toAirport},
      onSelectionChanged: (value) => _setDirection(value.first),
    );
  }

  Widget _returnToggle() {
    return Wrap(
      spacing: 8,
      children: [
        ChoiceChip(
          key: kCustomerBookingOneWayKey,
          label: Text(_t(kCustomerBookingOneWay)),
          selected: _returnKind == CustomerBookingReturnKind.oneWay,
          onSelected: (_) {
            setState(() {
              _returnKind = CustomerBookingReturnKind.oneWay;
              _selectedReturnVehicleId = null;
              _assignedReturnDriver = const CustomerBookingAssignedDriver();
              _returnAvailability = const CustomerBookingAvailabilitySnapshot();
            });
            _onDraftChanged();
          },
        ),
        ChoiceChip(
          key: kCustomerBookingReturnNoWaitKey,
          label: Text(_t(kCustomerBookingReturnNoWait)),
          selected: _returnKind == CustomerBookingReturnKind.noWait,
          onSelected: (_) {
            setState(() {
              _returnKind = CustomerBookingReturnKind.noWait;
              _selectedReturnVehicleId = null;
              _assignedReturnDriver = const CustomerBookingAssignedDriver();
              _returnAt ??= (_pickupAt ?? DateTime.now()).add(
                const Duration(days: 1),
              );
            });
            _syncReturnDefaults();
            _onDraftChanged();
          },
        ),
        if (_allowsWait)
          ChoiceChip(
            key: kCustomerBookingReturnWaitKey,
            label: Text(_t(kCustomerBookingReturnWait)),
            selected: _returnKind == CustomerBookingReturnKind.wait,
            onSelected: (_) {
              setState(() => _returnKind = CustomerBookingReturnKind.wait);
              _syncReturnDefaults();
              _onDraftChanged();
            },
          ),
      ],
    );
  }

  Widget _whenToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SegmentedButton<bool>(
        segments: [
          ButtonSegment(
            value: true,
            label: Text(_t(kCustomerBookingNow), key: kCustomerBookingNowKey),
          ),
          ButtonSegment(
            value: false,
            label: Text(
              _t(kCustomerBookingLater),
              key: kCustomerBookingLaterKey,
            ),
          ),
        ],
        selected: {_whenNow},
        onSelectionChanged: (value) {
          setState(() {
            _whenNow = value.first;
            if (_whenNow) {
              if (_suggestedPickup != null) {
                _taxiPickupManual = false;
                _applySuggestedPickup();
              } else {
                _taxiPickupManual = true;
              }
            } else if (_pickupAt == null) {
              _pickupAt = DateTime.now().add(const Duration(hours: 1));
              _taxiPickupManual = true;
            }
          });
          _onDraftChanged();
        },
      ),
    );
  }

  Widget _waitChips() {
    return Wrap(
      spacing: 8,
      children: [
        for (final minutes in kCompanyPlanAirportWaitPresets)
          ChoiceChip(
            key: customerBookingWaitChipKey(minutes),
            label: Text('$minutes'),
            selected: _waitMin == minutes,
            onSelected: (_) {
              setState(() => _waitMin = minutes);
              _onDraftChanged();
            },
          ),
      ],
    );
  }

  Widget _pickupActions() {
    final profile = _profile ?? widget.profile;
    final hasProfile =
        profile != null &&
        customerProfileDefaultAddressLine(profile).isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          if (hasProfile)
            Expanded(
              child: TextButton.icon(
                key: kCustomerBookingMyAddressKey,
                onPressed: _useMyAddress,
                icon: const Icon(Icons.home_outlined, size: 18),
                label: Text(_t(kCustomerBookingMyAddress)),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ),
          Expanded(
            child: TextButton.icon(
              key: kCustomerBookingUseLocationKey,
              onPressed: () => unawaited(_resolveGps(userRequested: true)),
              icon: const Icon(Icons.my_location_outlined, size: 18),
              label: Text(_t(kCustomerBookingCurrentLocation)),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _publishedDriversFor(
    CustomerBookingAvailabilitySnapshot snapshot,
  ) {
    return customerBookingMergePublishedDrivers(
      companyDrivers: [
        for (final driver in _companyDrivers)
          customerBookingPublishedDriverCard(driver),
      ],
      snapshotDrivers: snapshot.drivers,
    );
  }

  List<CustomerBookingVehicleOffer> _offersFor({
    required CustomerBookingAvailabilitySnapshot snapshot,
    required DateTime? pickupUtc,
    required int? durationMin,
    required bool rideReady,
  }) {
    return customerBookingVehicleOffers(
      vehicles: _companyVehicles,
      drivers: _publishedDriversFor(snapshot),
      passengers: _passengers,
      pickupUtc: pickupUtc,
      durationMin: durationMin ?? 30,
      durationKnown: durationMin != null && durationMin > 0,
      rideReady: rideReady,
      availableVehicleIds: snapshot.availableIds,
      unavailableVehicleIds: snapshot.unavailableIds,
      unavailableReasons: snapshot.reasons,
      proposedDriverIds: snapshot.driverIds,
      availabilityResolved: snapshot.resolved,
      availabilityFailed: snapshot.loadFailed,
    );
  }

  // Public presentation only. A body label fills an absent published model;
  // the service category/tier and accepted financial request stay unchanged.
  String _reliablePublicVehicleName(Map<String,dynamic> row) {
    final name=(row['vehicle_name']??'').toString().trim();
    if(name.isNotEmpty)return name;
    final body=classifyCompanyPlanVehicleCategory({'vehicle_type':row['vehicle_type']});
    return body==null?'':companyPlanVehicleCategoryLabel(body,_language);
  }

  List<CustomerBookingVehicleOffer> get _outboundVehicleOffers {
    if(_whenNow&&!_usesReliableChoice&&!_usesManualAsap)return [];
    if(_usesReliableChoice)return [for(final r in _reliableRows)if(CustomerReliableChoiceEstimate.parse(r,vehicleId:r['vehicle_id'] as String)!=null)CustomerBookingVehicleOffer(vehicle:{'vehicle_id':r['vehicle_id'],'name':_reliablePublicVehicleName(r),'vehicle_type':r['vehicle_type'],'category':r['vehicle_category'],'tier':r['vehicle_category'],'photo_url':r['photo_url'],'passenger_capacity':r['passenger_capacity'],'luggage_capacity':r['luggage_capacity'],'reliable_choice_v1':r},passengerSeats:r['passenger_capacity'] as int?,baggageCapacity:r['luggage_capacity'] as int?)];
    return _offersFor(
      snapshot: _availability,
      pickupUtc: _effectivePickupUtc,
      durationMin: _rideDurationMin,
      rideReady: _rideDetailsReady,
    );
  }

  List<CustomerBookingVehicleOffer> get _returnVehicleOffers {
    if(_usesReliableChoice && _splitReturn)return [for(final r in _reliableReturnRows)CustomerBookingVehicleOffer(vehicle:{'vehicle_id':r['vehicle_id'],'name':_reliablePublicVehicleName(r),'vehicle_type':r['vehicle_type'],'category':r['vehicle_category'],'tier':r['vehicle_category'],'photo_url':r['photo_url'],'passenger_capacity':r['passenger_capacity'],'luggage_capacity':r['luggage_capacity'],'reliable_choice_v1':r},passengerSeats:r['passenger_capacity'] as int?,baggageCapacity:r['luggage_capacity'] as int?)];
    return _offersFor(
      snapshot: _returnAvailability,
      pickupUtc: _effectiveReturnUtc,
      durationMin: _quote?.returnDurationMin ?? _rideDurationMin,
      rideReady: _rideDetailsReady && _returnAt != null,
    );
  }

  List<CustomerBookingVehicleOffer> get _vehicleOffers =>
      _outboundVehicleOffers;

  bool _hasBookableVehicle(
    List<CustomerBookingVehicleOffer> offers,
    String? vehicleId,
  ) {
    return customerBookingHasBookableVehicle(
      offers: offers,
      vehicleId: vehicleId,
    );
  }

  void _preselectSoleBookableVehicle({required bool inbound}) {
    final offers = customerBookingBookableOffers(
      inbound ? _returnVehicleOffers : _outboundVehicleOffers,
    );
    if (offers.length != 1) return;
    final only = offers.first;
    if (inbound) {
      if (_selectedReturnVehicleId == only.vehicleId) return;
      _selectedReturnVehicleId = only.vehicleId;
      _assignedReturnDriver = customerBookingProposedDriverFromRecord(
        only.driver,
      );
      return;
    }
    if (_selectedVehicleId == only.vehicleId) return;
    _selectedVehicleId = only.vehicleId;
    _assignedDriver = customerBookingProposedDriverFromRecord(only.driver);
    final category = classifyCompanyPlanVehicleCategory(only.vehicle);
    _vehicleCategory = category;
    if (category != null) {
      _vehicle = companyPlanVehicleTypeForCategory(category);
    }
  }

  bool _addressQuoteReady(LimousineAddressValue value) {
    return companyPlanAddressIsQuoteReady(value);
  }

  bool get _rideDetailsReady {
    final hasAirport = _airport != null;
    return customerBookingRideDetailsReady(
      pickupFilled:
          (!_pickupNeedsConfirm && _addressQuoteReady(_pickup.value)) ||
          (_airportMode && !_toAirport && hasAirport),
      dropoffFilled:
          _addressQuoteReady(_dropoff.value) ||
          (_airportMode && _toAirport && hasAirport),
      airportMode: _airportMode,
      toAirport: _toAirport,
      hasAirport: hasAirport,
    );
  }

  int? get _selectedVehicleSeats {
    for (final offer in _vehicleOffers) {
      if (offer.vehicleId == _selectedVehicleId) return offer.passengerSeats;
    }
    return null;
  }

  int _clampPassengers(int value) {
    final seats = _selectedVehicleSeats;
    if (seats != null && seats > 0 && value > seats) return seats;
    return value < 1 ? 1 : value;
  }

  void _selectVehicleOffer(
    CustomerBookingVehicleOffer offer, {
    required bool inbound,
  }) {
    final category = classifyCompanyPlanVehicleCategory(offer.vehicle);
    final seats = offer.passengerSeats;
    setState(() {
      if (inbound) {
        _selectedReturnVehicleId = offer.vehicleId;
        _assignedReturnDriver = customerBookingProposedDriverFromRecord(
          offer.driver,
        );
      } else {
        _selectedVehicleId = offer.vehicleId;
        _allowCompatibleReplacement=false;
        _requestDispatcherReview=false;
        _assignedDriver = customerBookingProposedDriverFromRecord(offer.driver);
        _vehicleCategory = category;
        if (category != null) {
          _vehicle = companyPlanVehicleTypeForCategory(category);
        }
      }
      if (seats != null && seats > 0 && _passengers > seats) {
        _passengers = seats;
      }
      _submitError = null;
    });
    _onDraftChanged(resetOffer: false);
  }

  Widget _vehicleSection({
    required List<CustomerBookingVehicleOffer> offers,
    required String? selectedId,
    required ValueChanged<CustomerBookingVehicleOffer> onSelected,
    required CustomerBookingAvailabilitySnapshot availability,
    required bool checking,
    required Key gridKey,
    Key emptyKey = kCustomerBookingNoVehicleAtTimeKey,
    Key otherTimeKey = kCustomerBookingChooseOtherTimeKey,
    Key retryKey = kCustomerBookingAvailabilityRetryKey,
    Key loadingKey = kCustomerBookingVehiclesLoadingKey,
    Key checkingKey = kCustomerBookingAvailabilityCheckingKey,
    Key failedKey = kCustomerBookingVehiclesFailedKey,
    VoidCallback? onChooseOtherTime,
  }) {
    if (_quote?.requiresAirportFareContact == true ||
        (_airportMode && (_vehiclesLoading || _airportWindowBlocked))) {
      return _quoteVehiclePreferenceSection();
    }
    final state = customerBookingVehicleOfferState(
      hasCompany: _hasChosenCompany,
      rideReady: _rideDetailsReady,
      loading: _vehiclesLoading,
      loadFailed: _vehiclesFailed || availability.loadFailed,
      offers: offers,
      availabilityLoading: checking,
    );
    final bookable = customerBookingBookableOffers(offers);
    final grid = bookable.isEmpty
        ? null
        : CustomerBookingVehiclePhotoCardGrid(
            key: gridKey,
            offers: bookable,
            language: _language,
            selectedVehicleId: selectedId,
            palette: _palette,
            bookableOnly: true,
            reliableChoiceOnly: _usesReliableChoice,
            onSelected: onSelected,
          );
    Widget message(String text, Key key, {VoidCallback? retry}) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, key: key),
          if (retry != null)
            TextButton(
              key: retryKey,
              onPressed: retry,
              child: Text(_t(kCustomerBookingAvailabilityRetry)),
            ),
        ],
      );
    }

    switch (state) {
      case CustomerBookingVehicleOfferState.needCompany:
        return const SizedBox.shrink();
      case CustomerBookingVehicleOfferState.loading:
        return message(_t(kCustomerBookingVehiclesLoading), loadingKey);
      case CustomerBookingVehicleOfferState.checking:
        return message(_t(kCustomerBookingAvailabilityChecking), checkingKey);
      case CustomerBookingVehicleOfferState.loadFailed:
        return message(
          _t(kCustomerBookingVehiclesLoadFailed),
          failedKey,
          retry: () {
            unawaited(_loadCompanyVehicles());
            unawaited(_refreshAvailability());
          },
        );
      case CustomerBookingVehicleOfferState.incompleteRide:
        return message(
          _t(kCustomerBookingVehiclesNeedRide),
          kCustomerBookingVehiclesNeedRideKey,
        );
      case CustomerBookingVehicleOfferState.noneSuitable:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _t(
                _whenNow && availability == _availability
                    ? customerBookingLiveAvailabilityMessage(
                            availability.reasons.values,
                          ) ??
                          kCustomerBookingNoVehicleAtTime
                    : kCustomerBookingNoVehicleAtTime,
              ),
              key: emptyKey,
            ),
            if (_whenNow &&
                availability == _availability &&
                customerBookingLiveAvailabilityMessage(
                      availability.reasons.values,
                    ) !=
                    null)
              TextButton(
                key: retryKey,
                onPressed: () => unawaited(_refreshAvailability()),
                child: Text(_t(kCustomerBookingAvailabilityRetry)),
              ),
            if(_usesReliableChoice&&!_splitReturn&&_reliableSelectionToken!=null)
              TextButton(key:const ValueKey('p21-request-dispatcher'),onPressed:_submitting?null:()=>setState((){_requestDispatcherReview=true;_selectedVehicleId=null;_assignedDriver=customerBookingProposedDriverFromRecord(null);}),
                child:Text(_t(const LocalizedText(nl:'Vraag dispatch om je rit te bekijken',en:'Ask dispatch to review your ride',fr:'Demander à la répartition de vérifier le trajet',es:'Pedir a despacho que revise el viaje',de:'Disposition um Prüfung der Fahrt bitten')))),
            TextButton(
              key: otherTimeKey,
              onPressed: onChooseOtherTime ?? _chooseOtherOutboundTime,
              child: Text(_t(kCustomerBookingChooseOtherTime)),
            ),
          ],
        );
      case CustomerBookingVehicleOfferState.ready:
        return grid ?? const SizedBox.shrink();
    }
  }

  List<CustomerBookingVehicleOffer> get _quotePreferenceOffers =>
      customerQuoteVehiclePreferences(
        _companyVehicles,
        passengers: _passengers,
        baggage: _bags,
        service: _airportMode ? 'airport' : 'taxi',
      );

  CustomerBookingVehicleOffer? get _quotePreference {
    if (_quotePreferenceCompany != _entry.company.routingPartnerId) return null;
    for (final offer in _quotePreferenceOffers) {
      if (offer.vehicleId == _quotePreferenceVehicleId && offer.available)
        return offer;
    }
    return null;
  }

  Widget _quoteVehiclePreferenceSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        _copy(
          nl: 'Voertuigvoorkeur voor je offerte',
          en: 'Vehicle preference for your quote',
          fr: 'Véhicule souhaité pour votre devis',
          es: 'Vehículo preferido para su presupuesto',
        ),
      ),
      const SizedBox(height: 6),
      Text(
        _copy(
          nl: 'Dit is een voorkeur. Het bedrijf bevestigt de prijs en het voertuig.',
          en: 'This is a preference. The company confirms the price and vehicle.',
          fr: 'Il s’agit d’une préférence. L’entreprise confirme le prix et le véhicule.',
          es: 'Es una preferencia. La empresa confirma el precio y el vehículo.',
        ),
      ),
      const SizedBox(height: 8),
      if (_vehiclesLoading)
        Text(_t(kCustomerBookingVehiclesLoading))
      else if (_vehiclesFailed)
        TextButton(
          onPressed: () => unawaited(_loadCompanyVehicles()),
          child: Text(_t(kCustomerBookingAvailabilityRetry)),
        )
      else
        CustomerBookingVehiclePhotoCardGrid(
          key: const ValueKey('quote_vehicle_preferences'),
          cardKeyFor: (id) => ValueKey('quote_preference_$id'),
          offers: _quotePreferenceOffers,
          language: _language,
          selectedVehicleId: _quotePreference?.vehicleId,
          palette: _palette,
          onSelected: (offer) => setState(() {
            _quotePreferenceCompany = _entry.company.routingPartnerId;
            _quotePreferenceVehicleId = offer.vehicleId;
          }),
        ),
    ],
  );

  String get _quoteContactSummary => [
    'Offerteaanvraag — geen bevestigde boeking',
    'Bedrijf: ${customerBookingCompanyVisibleName(_entry.company)}',
    'Ophalen: ${_pickup.textController.text}',
    'Bestemming: ${_dropoff.textController.text}',
    if (_airport != null) 'Luchthaven: ${_airport!.name}',
    for (final stop in _stops)
      if (stop.textController.text.trim().isNotEmpty)
        'Tussenstop: ${stop.textController.text}',
    'Datum/tijd: ${_pickupAt == null ? "Nog te bespreken" : "${_formatDate(_pickupAt)} ${_formatClock(_pickupAt)}"}',
    'Passagiers: $_passengers',
    'Bagage (koffers): $_bags',
    'Voertuigvoorkeur: ${_quotePreference == null ? "Geen voorkeur" : companyAgendaVehicleName(_quotePreference!.vehicle)}',
    if (_returnKind != CustomerBookingReturnKind.oneWay) ...[
      'Terugrit: ${_returnPickup.textController.text} → ${_returnDropoff.textController.text}',
      'Terugrit datum/tijd: ${_formatDate(_returnAt)} ${_formatClock(_returnAt)}',
      for (final stop in _returnStops)
        if (stop.textController.text.trim().isNotEmpty)
          'Terugrit tussenstop: ${stop.textController.text}',
    ],
    if (_flightCtrl.text.trim().isNotEmpty)
      'Vluchtnummer: ${_flightCtrl.text.trim()}',
    'Naam: ${_nameCtrl.text.trim()}',
    'Telefoon: $_bookingPhone',
    'E-mail: ${_emailCtrl.text.trim()}',
    'Graag prijs en beschikbaarheid bevestigen.',
  ].join('\n');

  Widget _vehicleRow() {
    final outbound = _vehicleSection(
      offers: _outboundVehicleOffers,
      selectedId: _selectedVehicleId,
      onSelected: (offer) => _selectVehicleOffer(offer, inbound: false),
      availability: _availability,
      checking: _availabilityLoading || (_rideDetailsReady && _quoteLoading),
      gridKey: _splitReturn
          ? kCustomerBookingOutboundVehiclesKey
          : kCustomerBookingVehicleHintKey,
      onChooseOtherTime: _chooseOtherOutboundTime,
    );
    if (!_splitReturn) return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[outbound,
      if(_whenNow&&_selectedVehicleId!=null&&_reliableRows.isNotEmpty)CheckboxListTile(
        key:const ValueKey('p21-compatible-vehicle-consent'),contentPadding:EdgeInsets.zero,
        value:_allowCompatibleReplacement,onChanged:_submitting?null:(value)=>setState(()=>_allowCompatibleReplacement=value==true),
        title:Text(_t(const LocalizedText(nl:'Een gelijkwaardige wagen mag bij weigering overnemen',en:'Allow a compatible vehicle if the driver declines',fr:'Autoriser un véhicule compatible en cas de refus',es:'Permitir un vehículo compatible si el conductor rechaza',de:'Bei Ablehnung ein gleichwertiges Fahrzeug erlauben')))),
    ]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _t(kCustomerBookingOutboundWhen),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        outbound,
        const SizedBox(height: 12),
        Text(
          _t(kCustomerBookingReturnWhen),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        _vehicleSection(
          offers: _returnVehicleOffers,
          selectedId: _selectedReturnVehicleId,
          onSelected: (offer) => _selectVehicleOffer(offer, inbound: true),
          availability: _returnAvailability,
          checking:
              _returnAvailabilityLoading ||
              (_rideDetailsReady && _quoteLoading),
          gridKey: kCustomerBookingReturnVehiclesKey,
          emptyKey: kCustomerBookingReturnNoVehicleAtTimeKey,
          otherTimeKey: kCustomerBookingReturnChooseOtherTimeKey,
          retryKey: kCustomerBookingReturnAvailabilityRetryKey,
          loadingKey: kCustomerBookingReturnVehiclesLoadingKey,
          checkingKey: kCustomerBookingReturnAvailabilityCheckingKey,
          failedKey: kCustomerBookingReturnVehiclesFailedKey,
          onChooseOtherTime: _pickReturnTime,
        ),
      ],
    );
  }

  Widget _countRow({
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
    Key? incrementKey,
  }) {
    return Focus(
      key: ValueKey('count_row_$incrementKey'),
      descendantsAreFocusable: false,
      canRequestFocus: false,
      child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: _palette.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        IconButton(
          key: ValueKey('count_decrement_$incrementKey'),
          onPressed: value > 0 ? () => onChanged(value - 1) : null,
          icon: Icon(Icons.remove_circle_outline, color: _palette.textPrimary),
        ),
        Text(
          '$value',
          style: TextStyle(
            color: _palette.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        IconButton(
          key: incrementKey,
          onPressed: () => onChanged(value + 1),
          icon: Icon(Icons.add_circle_outline, color: _palette.textPrimary),
        ),
      ],
      ),
    );
  }

  Widget _catalogPicker() {
    final catalog = publishedAirportCatalog();
    final countries = publishedAirportCountryCodes(catalog);
    final query = _airportQuery.trim();
    final airports = query.isEmpty
        ? airportsForCountry(_countryCode, catalog)
        : searchPublishedAirports(query, limit: 40, airports: catalog);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _t(kCustomerBookingChooseCountry),
          key: kCustomerBookingChooseCountryKey,
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final code in countries)
              ChoiceChip(
                key: customerBookingCountryKey(code),
                label: Text(airportCountryLabel(code, _language)),
                selected: _countryCode == code,
                onSelected: (_) {
                  setState(() {
                    _countryCode = code;
                    _airportQuery = '';
                    _airportSearchCtrl.clear();
                  });
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _t(kCustomerBookingChooseAirport),
          key: kCustomerBookingChooseAirportKey,
        ),
        TextField(
          key: kCustomerBookingAirportSearchKey,
          controller: _airportSearchCtrl,
          decoration: InputDecoration(
            hintText: _t(kCustomerBookingSearchAirport),
            prefixIcon: const Icon(Icons.search),
          ),
          onChanged: (value) => setState(() => _airportQuery = value),
          textInputAction: TextInputAction.search,
          onSubmitted: (value) {
            final matches = query.isEmpty
                ? airports
                : searchPublishedAirports(value, limit: 1, airports: catalog);
            if (matches.isNotEmpty) {
              _applyAirport(matches.first, browse: false);
            }
          },
        ),
        SizedBox(
          height: 240,
          child: ListView.builder(
            itemCount: airports.length,
            itemBuilder: (context, index) {
              final airport = airports[index];
              return ListTile(
                key: customerBookingAirportListKey(airport.iata),
                title: Text(airport.displayLabel),
                subtitle: Text(airport.formattedAddress),
                onTap: () => _applyAirport(airport, browse: false),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _flightFields({bool phone = false}) {
    return Column(
      key: kCustomerBookingFlightWhenKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: kCustomerBookingFlightNumberKey,
          controller: _flightCtrl,
          decoration: InputDecoration(
            labelText: _t(kCustomerBookingFlightNumber),
            isDense: true,
          ),
          textCapitalization: TextCapitalization.characters,
          onChanged: (_) => _onDraftChanged(),
        ),
        if (!phone) ...[
          const SizedBox(height: 12),
          Text(
            _t(
              _toAirport
                  ? kCustomerBookingFlightDepart
                  : kCustomerBookingFlightArrive,
            ),
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          CompanyDateTimeFields(
            fieldId: 'customer_flight',
            language: _language,
            value: _flightAt,
            dateLabel: _t(kCustomerBookingFlightDate),
            timeLabel: _t(kCustomerBookingFlightTime),
            onChanged: (next) {
              setState(() {
                _flightAt = next;
                _applySuggestedPickup();
              });
              _onDraftChanged();
            },
          ),
          if (_toAirport)
            TextField(
              key: kCustomerBookingArrivalMarginKey,
              keyboardType: TextInputType.number,
              controller: _arrivalMarginCtrl,
              decoration: InputDecoration(
                labelText: _t(kCustomerBookingArrivalMargin),
              ),
              onChanged: (value) {
                setState(() {
                  _arrivalMarginMin =
                      (int.tryParse(value.trim()) ??
                              kCompanyPlanDefaultAirportArrivalMarginMin)
                          .clamp(0, 180);
                  _applySuggestedPickup();
                });
                _onDraftChanged();
              },
            )
          else ...[
            Text(
              _t(kCustomerBookingLandingNotPickup),
              key: kCustomerBookingLandingHintKey,
            ),
            TextField(
              key: kCustomerBookingPickupAfterMinKey,
              keyboardType: TextInputType.number,
              controller: _pickupAfterCtrl,
              decoration: InputDecoration(
                labelText: _t(kCustomerBookingDeboardMinutes),
              ),
              onChanged: (value) {
                setState(() {
                  _pickupAfterMin = (int.tryParse(value.trim()) ?? 0).clamp(
                    0,
                    240,
                  );
                  _applySuggestedPickup();
                });
                _onDraftChanged();
              },
            ),
          ],
          if (_suggestedPickup != null) ...[
            Text(
              '${_t(kCustomerBookingPickupAdvice)}: ${_formatWhen(_suggestedPickup)}',
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: kCustomerBookingApplySuggestedPickupKey,
                onPressed: () {
                  setState(() => _applySuggestedPickup(force: true));
                  _onDraftChanged();
                },
                child: Text(_t(kCustomerBookingApplySuggestedPickup)),
              ),
            ),
          ],
          if (_flightTooLate) Text(_t(kCustomerBookingTooLateForFlight)),
        ] else if (!_toAirport)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _t(kCustomerBookingLandingNotPickup),
              key: kCustomerBookingLandingHintKey,
            ),
          ),
      ],
    );
  }

  Future<void> _resumeFinancialAcceptance() async {
    if (_submitting || _pendingFinancialAcceptance == null) return;
    setState(() => _submitting = true);
    try {
      final pending = _pendingFinancialAcceptance!;
      if (['expired', 'requote_required'].contains(pending['status'])) {
        await _quoteClient.financialJournal.complete(_quoteClient.acceptanceKey(_entry, _financialRecoveryOwner));
        if (mounted) {
          setState(() { _pendingFinancialAcceptance = null; _bookUncertain = false; });
          await _refreshQuote();
        }
        return;
      }
      final body = Map<String, dynamic>.from(pending['body'] as Map);
      final token = await _customerAuthToken();
      final result = await _quoteClient.book(body: body, entry: _entry,
        headers: {if (token.isNotEmpty) 'Authorization': 'Bearer $token'},
        recoveryOwner: _financialRecoveryOwner);
      final id = customerBookingIdFromResponse(result);
      if (id.isEmpty) throw StateError('booking_recovery_pending');
      final money = result['financial_snapshot'] is Map
          ? result['financial_snapshot']['money'] as Map? : null;
      final checkout = customerBookingCheckoutPlan(
        isMollieCheckout: body['payment_mode'] == 'mollie', response: result);
      if (checkout.requiredCheckout && !checkout.hasSafeUrl) throw StateError('checkout_url_missing');
      await _persistBookedRide(StoredCustomerBooking(bookingId: id,
        tenantId: _entry.company.tenantId, companyId: _entry.company.companyId,
        companyName: _entry.company.companyName, from: '${body['from'] ?? ''}',
        to: '${body['to'] ?? ''}', customerName: '${body['name'] ?? ''}',
        customerEmail: '${body['email'] ?? ''}', customerPhone: '${body['phone'] ?? ''}',
        pickupIso: '${body['pickup_iso'] ?? ''}',
        paymentBookingId: checkout.paymentBookingId,
        paymentMode: '${body['payment_mode'] ?? ''}',
        paymentStatus: checkout.requiredCheckout ? 'pending' : '',
        price: money?['gross_cents'] is num ? (money!['gross_cents'] as num).toDouble()/100 : null,
        currency: '${money?['currency'] ?? 'EUR'}',
        quote: {'financial_quote_id': body['financial_quote_id'],
          if (result['financial_snapshot'] != null) 'financial_snapshot': result['financial_snapshot']}));
      if (checkout.requiredCheckout) {
        final opened = widget.hostedCheckout != null
          ? await widget.hostedCheckout!(checkout)
          : await (widget.checkoutOpener ?? _launchCustomerBookingCheckout)(checkout.checkoutUrl);
        if (!opened) throw StateError('checkout_open_failed');
      }
      await _quoteClient.financialJournal.complete(_quoteClient.acceptanceKey(_entry, _financialRecoveryOwner));
      if (mounted) {
        setState(() => _pendingFinancialAcceptance = null);
        _returnToCustomerHome();
      }
    } catch (_) {
      if (mounted) setState(() => _submitError = 'Boeking nog niet bevestigd. Controleer opnieuw.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _financialRecoveryPanel() => Padding(
    padding: const EdgeInsets.all(12), child: _quotePanel());

  Widget _quotePanel({bool hideTotals = false}) {
    if (_pendingFinancialAcceptance != null) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Er is een onderbroken boeking. Controleer die voordat je opnieuw boekt.'),
        FilledButton(onPressed: _submitting ? null : _resumeFinancialAcceptance,
          child: Text(['expired', 'requote_required'].contains(_pendingFinancialAcceptance!['status'])
            ? 'Nieuwe offerte aanvragen' : 'Boeking controleren')),
      ]);
    }
    return _financialPricePanel(hideTotals: hideTotals);
  }

  Widget _financialPricePanel({bool hideTotals = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: CustomerBookingPriceBlock(
        language: _language,
        loading: _quoteLoading,
        quote: _pickupNeedsConfirm ? null : _quote,
        error: _pickupNeedsConfirm || !_hasChosenCompany ? null : _quoteError,
        onRetry: () => unawaited(_refreshQuote()),
        hideTotals: hideTotals,
        companyName: customerBookingCompanyVisibleName(_entry.company),
        onAirportContact: () => unawaited(_openAirportFareContact()),
      ),
    );
  }

  String _formatShortDate(DateTime? value) {
    if (value == null) return '—';
    final local = value.toLocal();
    const months = <String>[
      'jan',
      'feb',
      'mrt',
      'apr',
      'mei',
      'jun',
      'jul',
      'aug',
      'sep',
      'okt',
      'nov',
      'dec',
    ];
    return '${local.day} ${months[local.month - 1]}';
  }

  String _formatWhen(DateTime? value) {
    if (value == null) return '—';
    return '${_formatDate(value)} ${_formatClock(value)}';
  }

  String _formatDate(DateTime? value) {
    if (value == null) return '—';
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }

  String _formatClock(DateTime? value) {
    if (value == null) return '—';
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  bool get _laterPickupInvalid {
    if (_whenNow || _pickupAt == null) return false;
    return !companyPlanLaterPickupIsValid(_pickupAt!);
  }

  Future<void> _pickLaterDate() async {
    final now = DateTime.now();
    final initial = _pickupAt ?? now.add(const Duration(hours: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: companyPlanLaterFirstDate(now),
      lastDate: now.add(const Duration(days: 365)),
      helpText: _t(kCustomerBookingDate),
    );
    if (date == null || !mounted) return;
    setState(() {
      final time = _pickupAt ?? initial;
      _pickupAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      _whenNow = false;
      _taxiPickupManual = true;
    });
    _onDraftChanged();
  }

  Future<void> _chooseOtherOutboundTime() async {
    if (_whenNow) {
      setState(() => _whenNow = false);
    }
    await _pickLaterTime();
  }

  Future<void> _pickLaterTime() async {
    final now = DateTime.now();
    final initial = _pickupAt ?? now.add(const Duration(hours: 1));
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: _t(kCustomerBookingTime),
    );
    if (time == null || !mounted) return;
    setState(() {
      final date = _pickupAt ?? initial;
      _pickupAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      _whenNow = false;
      _taxiPickupManual = true;
    });
    _onDraftChanged();
  }

  Future<void> _pickReturnDate() async {
    final now = DateTime.now();
    final initial =
        _returnAt ?? (_pickupAt ?? now).add(const Duration(days: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: companyPlanLaterFirstDate(now),
      lastDate: now.add(const Duration(days: 365)),
      helpText: _t(kCustomerBookingReturnDate),
    );
    if (date == null || !mounted) return;
    setState(() {
      final time = _returnAt ?? initial;
      _returnAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      _selectedReturnVehicleId = null;
      _assignedReturnDriver = const CustomerBookingAssignedDriver();
    });
    _onDraftChanged(keepOutboundQuote: true);
  }

  Future<void> _pickReturnTime() async {
    final now = DateTime.now();
    final initial =
        _returnAt ?? (_pickupAt ?? now).add(const Duration(hours: 3));
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: _t(kCustomerBookingReturnTime),
    );
    if (time == null || !mounted) return;
    setState(() {
      final date = _returnAt ?? initial;
      _returnAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      _selectedReturnVehicleId = null;
      _assignedReturnDriver = const CustomerBookingAssignedDriver();
    });
    _onDraftChanged(keepOutboundQuote: true);
  }

  Widget _returnWhenFields() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Column(
        key: kCustomerBookingReturnClockRowKey,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _compactWhenField(
                  key: kCustomerBookingReturnDateKey,
                  label: _t(kCustomerBookingReturnDate),
                  value: _formatDate(_returnAt),
                  icon: Icons.calendar_today_outlined,
                  onTap: _pickReturnDate,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _compactWhenField(
                  key: kCustomerBookingReturnTimeKey,
                  label: _t(kCustomerBookingReturnTime),
                  value: _formatClock(_returnAt),
                  icon: Icons.schedule_outlined,
                  onTap: _pickReturnTime,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _laterWhenFields() {
    final airportHoursLabel =
        _airportMinLeadHours?.toStringAsFixed(
          _airportMinLeadHours! % 1 == 0 ? 0 : 1,
        ) ??
        '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        key: kCustomerBookingClockRowKey,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_airportMode && _airportMinLeadHours != null)
            Padding(
              key: const Key('airport_minimum_advance_notice'),
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _t(
                  LocalizedText(
                    nl: 'Luchthavenvervoer: boek minstens $airportHoursLabel uur op voorhand.',
                    en: 'Airport transfers: book at least $airportHoursLabel hours in advance.',
                    fr: 'Transfert aéroport : réservez au moins $airportHoursLabel heures à l’avance.',
                    es: 'Traslados al aeropuerto: reserva con $airportHoursLabel horas de antelación.',
                    de: 'Flughafentransfer: mindestens $airportHoursLabel Stunden im Voraus buchen.',
                  ),
                ),
              ),
            ),
          Text(
            _t(kCustomerBookingTaxiReadyAt),
            key: kCustomerBookingTaxiReadyAtKey,
            style: TextStyle(
              color: _palette.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _compactWhenField(
                  key: kCustomerBookingDateKey,
                  label: _t(kCustomerBookingDate),
                  value: _formatDate(
                    _whenNow ? _asapPickup?.toLocal() : _pickupAt,
                  ),
                  icon: Icons.calendar_today_outlined,
                  onTap: () async {
                    setState(() {
                      _whenNow = false;
                      _pickupAt ??= DateTime.now().add(
                        const Duration(hours: 1),
                      );
                      _taxiPickupManual = true;
                    });
                    _onDraftChanged();
                    await _pickLaterDate();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _compactWhenField(
                  key: kCustomerBookingTimeKey,
                  label: _t(kCustomerBookingTime),
                  value: _formatClock(
                    _whenNow ? _asapPickup?.toLocal() : _pickupAt,
                  ),
                  icon: Icons.schedule_outlined,
                  onTap: () async {
                    setState(() {
                      _whenNow = false;
                      _pickupAt ??= DateTime.now().add(
                        const Duration(hours: 1),
                      );
                      _taxiPickupManual = true;
                    });
                    _onDraftChanged();
                    await _pickLaterTime();
                  },
                ),
              ),
            ],
          ),
          if (_laterPickupInvalid ||
              (_confirmDecision.firstFailure?.id ==
                  kCustomerBookingIssueMinPrep))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _visibleConfirmReasonText(
                      _confirmDecision.firstFailure ??
                          const CustomerBookingConfirmCondition(
                            id: kCustomerBookingIssueLaterInvalid,
                            ok: false,
                            detail: 'past',
                            focusKey: 'when',
                          ),
                      _language,
                      suggestedPickup: _confirmDecision.suggestedPickup,
                    ),
                    key: kCustomerBookingLaterInvalidKey,
                    style: TextStyle(
                      color: _palette.danger,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (_confirmDecision.suggestedPickup != null)
                    TextButton(
                      key: kCustomerBookingSuggestedTimeKey,
                      onPressed: () {
                        final suggested = _confirmDecision.suggestedPickup!;
                        setState(() {
                          _pickupAt = DateTime(
                            suggested.year,
                            suggested.month,
                            suggested.day,
                            suggested.hour,
                            suggested.minute,
                          );
                          _whenNow = false;
                          _taxiPickupManual = true;
                          _submitError = null;
                        });
                        _onDraftChanged();
                      },
                      child: Text(
                        _t(kCustomerBookingUseSuggestedTime).replaceAll(
                          '{time}',
                          companyPlanFormatClock(
                            _confirmDecision.suggestedPickup!,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _compactWhenField({
    required Key key,
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      key: key,
      color: _palette.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 18, color: _palette.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _palette.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
