import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/airport/airport_catalog_repository.dart';
import 'package:fluxidi_tracking/airport/airport_catalog_search.dart';
import 'package:fluxidi_tracking/airport/airport_selector.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_plan_airport_cards.dart';
import 'package:fluxidi_tracking/company/company_plan_quote.dart';
import 'package:fluxidi_tracking/company/company_plan_ride_mode.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_quote_wire.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_route_camera.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_route_geometry.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_route_map.dart';
import 'package:fluxidi_tracking/company/company_plan_vehicle_type.dart';
import 'package:fluxidi_tracking/company/company_ride_options.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_addresses.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_book_result.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_billing.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_company_pick.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_assigned_driver.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_company_vehicles.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_vehicle_cards.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_vehicle_offers.dart';
import 'package:fluxidi_tracking/company/company_plan_when.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_entry.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_home_notice.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_keys.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_labels.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_layout.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_open.dart';
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
  bool _submitting = false;
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
  List<Map<String, dynamic>> _companyDrivers = const <Map<String, dynamic>>[];
  PublicCompanyPresentation _presentation = const PublicCompanyPresentation();
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
  String? _selectedVehicleId;
  CustomerBookingAssignedDriver _assignedDriver =
      const CustomerBookingAssignedDriver();
  CustomerBookingAvailabilitySnapshot _availability =
      const CustomerBookingAvailabilitySnapshot();
  int _availabilitySeq = 0;
  bool _availabilityLoading = false;
  bool _editingContact = false;
  int _quoteSeq = 0;
  CompanyPlanQuoteResult? _quote;
  String? _quoteError;
  bool _quoteLoading = false;
  String? _successId;
  Timer? _quoteDebounce;
  String _idempotencyKey = '';
  int _stopSeq = 0;
  final ScrollController _formScroll = ScrollController();

  AppLanguage get _language => widget.language ?? appConfig.currentLanguage;

  CustomerThemePalette get _palette =>
      paletteForCustomerTheme(customerThemeNotifier.value);

  LimousineUxTokens get _tokens => LimousineUxTokens.fromCustomer(_palette);

  String _t(LocalizedText text) => text.of(_language);

  bool get _contextInvalid =>
      _entry.lockCompany && !_entry.company.hasPartner && !_entry.company.hasCompany;

  bool get _showAirplane => _airportMode;

  bool get _hasChosenCompany =>
      customerBookingCompanyIsChosen(_entry.company);

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
      waitMin: _returnKind == CustomerBookingReturnKind.wait ? _waitMin : 0,
      flightNumber: _flightCtrl.text.trim().toUpperCase(),
      airportDirection: _airportMode
          ? (_toAirport ? 'to_airport' : 'from_airport')
          : '',
      airportIata: _airport?.iata ?? '',
      airportCountry: _airport?.countryCode ?? '',
      flightAt: _flightAt?.toIso8601String() ?? '',
      vehicleType: _vehicleCategory == null
          ? companyPlanVehicleTypeWire(_vehicle)
          : companyPlanVehicleCategoryWire(_vehicleCategory!),
      tier: _vehicleCategory == CompanyPlanVehicleCategory.premium
          ? 'premium'
          : '',
    );
  }

  @override
  void initState() {
    super.initState();
    _entry = widget.entry;
    _lookup = widget.lookup ?? LimousinePlaceLookup(country: '');
    _quoteClient =
        widget.quoteClient ??
        CustomerBookingQuoteClient(bookingBaseUrl: widget.bookingBaseUrl ?? '');
    _quotes = CompanyPlanQuoteCoordinator(transport: _runQuote);
    _idempotencyKey =
        'cust-${DateTime.now().microsecondsSinceEpoch}-${_entry.kind.name}';
    _flightCtrl = TextEditingController();
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
    limousineBindSiblingSearchBias(field: _returnPickup, sibling: _returnDropoff);
    limousineBindSiblingSearchBias(field: _returnDropoff, sibling: _returnPickup);
    _airportMode = _entry.kind == CustomerBookingKind.airport;
    _toAirport = _entry.toAirport;
    _airport = _entry.airport;
    _companyVehicles = List<Map<String, dynamic>>.from(_entry.company.vehicles);
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refreshQuote());
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

  Future<void> _resolveGpsAfterProfile() async {
    // A saved profile address must win over a later GPS fix. Wait for the
    // profile itself; only fall back to GPS when the pickup is still vacant.
    try {
      await _loadProfile();
    } catch (_) {}
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
      if (!mounted) return;
      setState(() {
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
        _paymentCapability = snapshot.payment;
        _paymentCapabilityLoadFailed =
            snapshot.payment.projectionStatus ==
            BookingPaymentCapabilityStatus.loadFailed;
        _vehiclesLoading = false;
        _vehiclesFailed = false;
        _syncVehicleFromFleet();
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
      final profile = widget.profile ?? await CustomerProfileStore.instance.load();
      if (!mounted || profile == null) return;
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
      final stored = await CustomerConfirmedLocationStore.instance.readFor(query);
      if (!mounted || seq != _pickupGeocodeSeq) return;
      if (stored != null &&
          stored.isUsable &&
          (customerConfirmedLocationMatches(_pickup.value.displayText, stored) ||
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
    final next = customerBookingAddressFromText(
      label,
      latitude: address.lat,
      longitude: address.lon,
    );
    _pickup.acceptCopy(next, userConfirmed: next.hasCoordinates);
    setState(() {
      _pickupOwned = true;
      _gpsFallback = false;
      _submitError = null;
    });
    _onDraftChanged();
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
      final stored = await CustomerConfirmedLocationStore.instance.readFor(label);
      if (!mounted || stored == null || !stored.isUsable) return;
      if (!customerConfirmedLocationMatches(_pickup.value.displayText, stored) &&
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
    if (!userRequested && (_pickupOwned || !customerBookingPickupIsVacant(_pickup.value))) {
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

  void _onDraftChanged() {
    _quoteDebounce?.cancel();
    _quoteDebounce = Timer(kCompanyPlanQuoteDebounce, () {
      unawaited(_refreshQuote());
      unawaited(_refreshAvailability());
    });
  }

  DateTime? get _effectivePickupUtc {
    if (_whenNow) return DateTime.now().toUtc();
    final local = _pickupAt;
    if (local == null) return null;
    return companyPlanPickupUtc(local);
  }

  Future<void> _refreshAvailability() async {
    if (!_hasChosenCompany) return;
    final pickup = _effectivePickupUtc;
    if (pickup == null) return;
    if (_pickupNeedsConfirm) {
      _availabilitySeq += 1;
      if (_availability.fetched || _availabilityLoading) {
        setState(() {
          _availability = const CustomerBookingAvailabilitySnapshot();
          _availabilityLoading = false;
        });
      }
      return;
    }
    if (!_rideDetailsReady) {
      _availabilitySeq += 1;
      if (_availability.fetched || _availabilityLoading) {
        setState(() {
          _availability = const CustomerBookingAvailabilitySnapshot();
          _availabilityLoading = false;
        });
      }
      return;
    }
    final duration = _quote?.durationMin;
    if (duration == null || duration <= 0) {
      _availabilitySeq += 1;
      if (_availability.fetched || _availabilityLoading) {
        setState(() {
          _availability = const CustomerBookingAvailabilitySnapshot();
          _availabilityLoading = false;
        });
      }
      return;
    }
    final seq = ++_availabilitySeq;
    setState(() => _availabilityLoading = true);
    try {
      final snapshot = await fetchCustomerBookingAvailability(
        bookingBaseUrl: widget.bookingBaseUrl ?? _quoteClient.bookingBaseUrl,
        partnerId: _entry.company.routingPartnerId,
        pickupUtc: pickup,
        passengers: _passengers,
        durationMin: duration,
        waitMin: _options.waitMin,
        returnDurationMin: _returnKind == CustomerBookingReturnKind.oneWay
            ? 0
            : (_quote?.returnDurationMin ?? duration),
        httpGet: widget.profileGet,
      );
      if (!mounted || seq != _availabilitySeq) return;
      setState(() {
        _availability = snapshot;
        _availabilityLoading = false;
        if (_selectedVehicleId != null &&
            snapshot.resolved &&
            !snapshot.availableIds.contains(_selectedVehicleId)) {
          _selectedVehicleId = null;
          _assignedDriver = const CustomerBookingAssignedDriver();
          _submitError = _t(kCustomerBookingVehicleUnavailable);
        }
      });
    } catch (_) {
      if (!mounted || seq != _availabilitySeq) return;
      setState(() {
        _availabilityLoading = false;
        _availability = const CustomerBookingAvailabilitySnapshot(
          loadFailed: true,
          fetched: true,
        );
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

  Future<CompanyPlanQuoteResult> _runQuote(CompanyPlanQuoteRequest request) {
    return _quoteClient.quote(request: request, entry: _entry);
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

  LimousineAddressValue _bookAddress(
    LimousineAddressFieldController field, {
    double? fallbackLat,
    double? fallbackLon,
  }) {
    final value = _quoteAddress(field);
    if (value.hasCoordinates || fallbackLat == null || fallbackLon == null) {
      return value;
    }
    final label = value.routeText.trim().isNotEmpty
        ? value.routeText
        : value.displayText;
    return customerBookingAddressFromText(
      label,
      latitude: fallbackLat,
      longitude: fallbackLon,
    );
  }

  Future<void> _refreshQuote() async {
    if (!mounted) return;
    _syncReturnDefaults();
    final seq = ++_quoteSeq;
    if (_pickupNeedsConfirm) {
      setState(() {
        _quote = null;
        _quoteError = null;
        _quoteLoading = false;
      });
      unawaited(_refreshAvailability());
      return;
    }
    if (!_hasChosenCompany) {
      setState(() {
        _quote = null;
        _quoteError = kCustomerBookingIssueNeedCompany;
        _quoteLoading = false;
      });
      return;
    }
    final pickupAt = _whenNow ? DateTime.now() : _pickupAt;
    final request = companyPlanQuoteRequestFromAddresses(
      from: _quoteAddress(_pickup),
      to: _quoteAddress(_dropoff),
      pickupLocal: pickupAt,
      options: _options,
      passengers: _passengers,
      returnEnabled: _returnKind != CustomerBookingReturnKind.oneWay,
      returnPickupLocal: _returnKind == CustomerBookingReturnKind.noWait
          ? _returnAt
          : pickupAt,
      returnFrom: _returnKind == CustomerBookingReturnKind.oneWay
          ? null
          : (_quoteAddress(_returnPickup).isEmpty
              ? _quoteAddress(_dropoff)
              : _quoteAddress(_returnPickup)),
      returnTo: _returnKind == CustomerBookingReturnKind.oneWay
          ? null
          : (_quoteAddress(_returnDropoff).isEmpty
              ? _quoteAddress(_pickup)
              : _quoteAddress(_returnDropoff)),
      stops: [for (final stop in _stops) _quoteAddress(stop)],
      returnStops: [for (final stop in _returnStops) _quoteAddress(stop)],
      whenNow: _whenNow,
      vehicleId: _selectedVehicleId ?? '',
    );
    if (request == null) {
      if (!mounted || seq != _quoteSeq) return;
      setState(() {
        _quote = null;
        _quoteError = customerBookingIncompleteQuoteIssue(
          from: _quoteAddress(_pickup),
          to: _quoteAddress(_dropoff),
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
      _quote = null;
    });
    try {
      final result = await _quotes.quote(request);
      if (!mounted || seq != _quoteSeq) return;
      _absorbQuoteCoordinates(result);
      if (!mounted || seq != _quoteSeq) return;
      setState(() {
        _quote = result;
        _quoteLoading = false;
        _quoteError = null;
      });
      unawaited(_refreshAvailability());
    } catch (error) {
      if (!mounted || seq != _quoteSeq) return;
      debugPrint('[CUSTOMER_BOOKING][QUOTE][ERR] $error');
      setState(() {
        _quote = null;
        _quoteLoading = false;
        _quoteError = customerBookingQuoteIssueFromRaw(error.toString());
      });
      unawaited(_refreshAvailability());
    }
  }

  void _syncReturnDefaults() {
    if (_returnKind == CustomerBookingReturnKind.oneWay) return;
    if (_returnPickup.value.isEmpty && _dropoff.value.isRouteReady) {
      _returnPickup.acceptCopy(_dropoff.value);
    }
    if (_returnDropoff.value.isEmpty && _pickup.value.isRouteReady) {
      _returnDropoff.acceptCopy(_pickup.value);
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

  void _absorbQuoteCoordinates(CompanyPlanQuoteResult result) {
    final pickupText = _pickup.value.displayText;
    final pickupHasLocality = limousineAddressQueryPostcode(pickupText) != null ||
        limousineAddressQueryLocality(pickupText) != null;
    if (!_pickup.value.hasCoordinates &&
        !_pickupOwned &&
        !pickupHasLocality &&
        result.pickupLat != null &&
        result.pickupLon != null) {
      _pickup.acceptCopy(
        _pickup.value.copyWith(
          lat: result.pickupLat,
          lon: result.pickupLon,
        ),
      );
    }
    if (!_dropoff.value.hasCoordinates &&
        result.dropoffLat != null &&
        result.dropoffLon != null) {
      _dropoff.acceptCopy(
        _dropoff.value.copyWith(
          lat: result.dropoffLat,
          lon: result.dropoffLon,
        ),
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
    final next = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (inbound) {
        _returnAt = next;
      } else {
        _pickupAt = next;
      }
    });
    _onDraftChanged();
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
    });
    _onDraftChanged();
  }

  bool get _flightTooLate {
    if (!_airportMode || !_toAirport || _flightAt == null) return false;
    final pickup = _whenNow ? DateTime.now() : _pickupAt;
    final duration = _quote?.durationMin;
    if (pickup == null || duration == null) return false;
    return pickup.add(Duration(minutes: duration)).isAfter(_flightAt!);
  }

  DateTime? get _suggestedPickup {
    if (!_airportMode || !_toAirport || _flightAt == null) return null;
    final duration = _quote?.durationMin;
    if (duration == null) return null;
    return _flightAt!.subtract(Duration(minutes: duration + 15));
  }

  Future<void> _changeCompany() async {
    final picked = await pickCustomerBookingCompany(
      context,
      airportCapableOnly: _airportMode,
      customerHomeBuilder: widget.onGoToStartPage,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _entry = _entry.copyWith(company: picked);
      _companyVehicles = List<Map<String, dynamic>>.from(picked.vehicles);
      _companyDrivers = const <Map<String, dynamic>>[];
      _presentation = const PublicCompanyPresentation();
      _availability = const CustomerBookingAvailabilitySnapshot();
      _availabilityLoading = false;
      _selectedVehicleId = null;
      _assignedDriver = const CustomerBookingAssignedDriver();
      _quote = null;
      _quoteError = null;
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
    if (_submitting || _contextInvalid) return;
    if (_successId != null) return;
    final issues = customerBookingSubmitIssues(
      hasCompany: _hasChosenCompany,
      pickup: _quoteAddress(_pickup),
      dropoff: _quoteAddress(_dropoff),
      whenNow: _whenNow,
      pickupLocal: _pickupAt,
      name: _nameCtrl.text,
      phone: _phoneCtrl.text,
      quoteLoading: _quoteLoading,
      quote: _quote,
      quoteError: _quoteError,
      successId: _successId,
    );
    if (issues.isNotEmpty) {
      setState(() {
        _submitError = customerBookingSubmitIssueText(
          issues.first.code,
          _language,
        );
      });
      _revealSubmitIssue(issues.first);
      return;
    }
    if (_pickupNeedsConfirm) {
      setState(() => _submitError = _t(kCustomerBookingAddressNeedsConfirm));
      return;
    }
    if (_availability.loadFailed) {
      setState(() => _submitError = _t(kCustomerBookingVehiclesLoadFailed));
      return;
    }
    if (_selectedVehicleId != null) {
      final selected = _vehicleOffers.where(
        (offer) => offer.vehicleId == _selectedVehicleId,
      );
      if (selected.isEmpty || !selected.first.available) {
        setState(() {
          _selectedVehicleId = null;
          _submitError = _t(kCustomerBookingVehicleUnavailable);
        });
        return;
      }
    }
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
  }

  Future<void> _book(BookingPaymentSelection selection) async {
    if (_submitting || _successId != null) return;
    _submitting = true;
    setState(() => _submitError = null);
    try {
      _syncReturnDefaults();
      if (!_quoteAddress(_pickup).hasCoordinates) {
        await _geocodePickupIfNeeded();
      }
      final pickupAt = _whenNow ? DateTime.now() : _pickupAt;
      final request = companyPlanQuoteRequestFromAddresses(
        from: _bookAddress(
          _pickup,
          fallbackLat: _quote?.pickupLat,
          fallbackLon: _quote?.pickupLon,
        ),
        to: _bookAddress(
          _dropoff,
          fallbackLat: _quote?.dropoffLat,
          fallbackLon: _quote?.dropoffLon,
        ),
        pickupLocal: pickupAt,
        options: _options,
        passengers: _passengers,
        returnEnabled: _returnKind != CustomerBookingReturnKind.oneWay,
        returnPickupLocal: _returnKind == CustomerBookingReturnKind.noWait
            ? _returnAt
            : pickupAt,
        returnFrom: _returnKind == CustomerBookingReturnKind.oneWay
            ? null
            : (_quoteAddress(_returnPickup).isEmpty
                ? _quoteAddress(_dropoff)
                : _quoteAddress(_returnPickup)),
        returnTo: _returnKind == CustomerBookingReturnKind.oneWay
            ? null
            : (_quoteAddress(_returnDropoff).isEmpty
                ? _quoteAddress(_pickup)
                : _quoteAddress(_returnDropoff)),
        stops: [for (final stop in _stops) _quoteAddress(stop)],
        returnStops: [for (final stop in _returnStops) _quoteAddress(stop)],
        whenNow: _whenNow,
        vehicleId: _selectedVehicleId ?? '',
      );
      if (request == null) {
        throw StateError(kCustomerBookingIssueNeedRoute);
      }
      final token = await _customerAuthToken();
      final headers = <String, String>{};
      if (token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
      String assignedDriverId = '';
      for (final offer in _vehicleOffers) {
        if (offer.vehicleId == _selectedVehicleId && offer.driverId.isNotEmpty) {
          assignedDriverId = offer.driverId;
          break;
        }
      }
      final body = <String, dynamic>{
        ...request.body,
        'name': _nameCtrl.text.trim(),
        // Sent in international form for private and business rides alike.
        'phone': _bookingPhone,
        'email': _emailCtrl.text.trim(),
        'pax': _passengers,
        if ((_selectedVehicleId ?? '').trim().isNotEmpty)
          'preferred_vehicle_id': _selectedVehicleId!.trim(),
        if ((_selectedVehicleId ?? '').trim().isNotEmpty)
          'vehicle_id': _selectedVehicleId!.trim(),
        if (assignedDriverId.isNotEmpty) 'assigned_driver_id': assignedDriverId,
        'idempotency_key': _idempotencyKey,
        'idempotencyKey': _idempotencyKey,
        ...customerBookingBillingPayloadFields(
          businessRide: _businessRide,
          identity: _billing.identity,
          defaultEmail: _emailCtrl.text,
          defaultPhone: _bookingPhone,
        ),
        ...selection.toPayloadFields(),
      };
      final result = await _quoteClient.book(
        body: body,
        entry: _entry,
        headers: headers,
      );
      final bookingId = customerBookingIdFromResponse(result);
      final assigned = customerBookingAssignedDriverFromMaps(booking: result);
      final stored = StoredCustomerBooking(
        bookingId: bookingId.isEmpty ? _idempotencyKey : bookingId,
        tenantId: _entry.company.tenantId,
        companyId: _entry.company.companyId,
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
        status: 'CONFIRMED',
        companyName: _entry.company.companyName,
        quote: <String, dynamic>{
          if (assigned.assigned)
            'assigned_driver': <String, dynamic>{
              'driver_id': assigned.driverId,
              'first_name': assigned.firstName,
              'photo_url': assigned.photoUrl,
              'rating_avg': assigned.ratingAverage,
              'rating_count': assigned.ratingCount,
              'reviews_url': assigned.reviewsUrl,
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
      _returnToCustomerHome();
    } catch (error) {
      if (!mounted) return;
      final mapped = customerBookingBookExceptionFromCaught(error);
      customerBookingLogBookFailure(mapped);
      final code = customerBookingBookIssueFromException(mapped);
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
    } catch (_) {}
  }

  void _returnToCustomerHome() {
    if (!mounted) return;
    CustomerBookingHomeNotice.set(_t(kCustomerBookingSuccess));
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

  void _revealSubmitIssue(CustomerBookingSubmitIssue issue) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_formScroll.hasClients) return;
      final jumpDown = issue.focusKey == 'name' ||
          issue.focusKey == 'phone' ||
          issue.focusKey == 'quote' ||
          issue.focusKey == 'when';
      final target = jumpDown
          ? _formScroll.position.maxScrollExtent
          : 0.0;
      _formScroll.animateTo(
        target,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _quoteDebounce?.cancel();
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
                  final wide = customerBookingUseWideSplit(
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    textScale: textScale,
                  );
                  final short = constraints.maxHeight < 520;
                  final pinConfirm = customerBookingPinConfirmBar(
                    height: constraints.maxHeight,
                    keyboardOpen: keyboardOpen,
                    textScale: textScale,
                  );
                  final confirmReserve = pinConfirm
                      ? 72.0 + media.padding.bottom
                      : 16.0;
                  final form = _bookingFormFields(
                    theme,
                    includeWhen: wide,
                    confirmReserve: confirmReserve,
                    includeConfirm: !pinConfirm,
                  );
                  final map = _bookingMap();
                  final confirm = pinConfirm
                      ? _confirmBar(compact: short || keyboardOpen)
                      : const SizedBox.shrink();
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
                  final when = Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _whenToggle(),
                        if (!_whenNow) _laterWhenFields(),
                      ],
                    ),
                  );
                  final planeHeight = customerBookingAirplaneHeight(
                    wide: wide,
                    short: short,
                  );
                  final airplane = _showAirplane && planeHeight > 0
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
                          child: KeyedSubtree(
                            key: kCustomerBookingAirplaneVisualKey,
                            child: CompanyPlanAirportModeVisual(
                              semanticLabel: _t(kCustomerBookingAirportMode),
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
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: _airportChromeFields(theme),
                          ),
                        )
                      : const SizedBox.shrink();
                  if (wide) {
                    return Column(
                      children: [
                        Expanded(
                          key: kCustomerBookingWideSplitKey,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: ListView(
                                  key: kCustomerBookingFormKey,
                                  controller: _formScroll,
                                  cacheExtent: 2400,
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    12,
                                    16,
                                    24,
                                  ),
                                  children: [
                                    airplane,
                                    audience,
                                    if (_airportMode) airportChrome,
                                    ...form,
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    0,
                                    12,
                                    16,
                                    12,
                                  ),
                                  child: map,
                                ),
                              ),
                            ],
                          ),
                        ),
                        confirm,
                      ],
                    );
                  }
                  final mapHeight = customerBookingStackedMapHeight(
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    textScale: textScale,
                  );
                  return Column(
                    key: kCustomerBookingNarrowStackKey,
                    children: [
                      Expanded(
                        child: CustomScrollView(
                          key: kCustomerBookingFormKey,
                          controller: _formScroll,
                          cacheExtent: 4800,
                          slivers: [
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                              sliver: SliverToBoxAdapter(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    audience,
                                    when,
                                    airplane,
                                    SizedBox(height: mapHeight, child: map),
                                    if (_airportMode) airportChrome,
                                    ...form,
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      confirm,
                    ],
                  );
                },
              ),
          ),
        ),
        );
      },
    );
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

  Widget _bookingMap() {
    final candidate = _pickup.locationCandidate;
    return CustomerBookingRouteMap(
      key: kCustomerBookingMapKey,
      language: _language,
      palette: _palette,
      pickup: _pickup.value,
      dropoff: _dropoff.value,
      stops: [for (final stop in _stops) stop.value],
      quote: _quote,
      quoteLoading: _quoteLoading,
      errorText: _quoteError,
      onRetry: _refreshQuote,
      pickupLocal: _whenNow ? DateTime.now() : _pickupAt,
      geometryClient: widget.routeGeometryClient,
      pickupNeedsConfirm: _pickupNeedsConfirm,
      confirmLat: candidate?.lat ?? _pickup.value.lat,
      confirmLon: candidate?.lon ?? _pickup.value.lon,
      onConfirmPickup: _confirmPickupOnMap,
      pickupInspectSeq: _pickupInspectSeq,
    );
  }

  Widget _confirmBar({bool compact = false}) {
    return Material(
      color: _palette.background,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, compact ? 4 : 8, 16, compact ? 8 : 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_submitError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _submitError!,
                  key: kCustomerBookingSubmitErrorKey,
                  style: TextStyle(
                    color: _palette.danger,
                    fontWeight: FontWeight.w700,
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
            SizedBox(
              width: double.infinity,
              height: compact ? 44 : 48,
              child: FilledButton(
                key: kCustomerBookingConfirmKey,
                onPressed: _submitting || _successId != null ? null : _confirm,
                child: _submitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_t(kCustomerBookingConfirm)),
              ),
            ),
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
      child: InkWell(
        onTap: _changeCompany,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.apartment_outlined, color: _palette.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: chosen
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              key: kCustomerBookingCompanyLockKey,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _palette.textPrimary,
                                fontWeight: FontWeight.w800,
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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _palette.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
                TextButton(
                  key: chosen ? kCustomerBookingCompanyChangeKey : null,
                  onPressed: _changeCompany,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 36),
                  ),
                  child: Text(
                    chosen
                        ? _t(kCustomerBookingChangeCompany)
                        : _t(kCustomerBookingNeedCompanyShortPick),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
          contentPadding: EdgeInsets.zero,
          title: Text(
            [
              _nameCtrl.text.trim(),
              _phoneCtrl.text.trim(),
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            _emailCtrl.text.trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
    return [
      _directionToggle(),
      const SizedBox(height: 12),
      if (_airport != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            customerBookingAirportSummary(_airport!),
            key: kCustomerBookingAirportSummaryKey,
            style: theme.textTheme.titleMedium,
          ),
        ),
      CompanyPlanAirportDestinationCards(
        language: _language,
        selectedIata: _airport?.iata ?? '',
        cardKeyOf: customerBookingAirportCardKey,
        onSelectedIata: (iata) {
          final record = companyPlanAirportCatalogRecord(iata);
          if (record != null) {
            _applyAirport(record, browse: false);
          }
        },
        onSelectedOther: () {
          setState(() => _browseCatalog = true);
        },
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          key: kCustomerBookingBrowseAllAirportsKey,
          onPressed: () {
            setState(() => _browseCatalog = true);
          },
          child: Text(_t(kCustomerBookingBrowseAllAirports)),
        ),
      ),
      if (_browseCatalog) _catalogPicker(),
      _flightFields(),
    ];
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
    double confirmReserve = 16,
    bool includeConfirm = false,
  }) {
    return [
      if (includeWhen) ...[
        _whenToggle(),
        if (!_whenNow) _laterWhenFields(),
      ],
      _companyBanner(),
      const SizedBox(height: 8),
      if (_entry.showBusinessModeChoice) _modeToggle(),
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
        label: _t(kCustomerBookingPickup),
        tokens: _tokens,
        language: _language,
        showCanonicalEcho: false,
        showCurrentLocation: true,
        isPickupField: true,
        inputKey: kCustomerBookingPickupKey,
      ),
      if (_pickupNeedsConfirm)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _t(kCustomerBookingCheckPickup),
                  key: kCustomerBookingConfirmPickupBannerKey,
                  style: TextStyle(
                    color: _palette.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(
                key: kCustomerBookingInspectPickupKey,
                onPressed: _inspectPickupOnMap,
                child: Text(_t(kCustomerBookingInspectPickup)),
              ),
            ],
          ),
        ),
      if (!_airportMode || _toAirport) _pickupActions(),
      ..._stopFields(inbound: false),
      if (!_airportMode || !_toAirport || _airport == null)
        LimousineAddressField(
          controller: _dropoff,
          label: _t(kCustomerBookingDropoff),
          tokens: _tokens,
          language: _language,
          showCanonicalEcho: false,
          inputKey: kCustomerBookingDropoffKey,
        ),
      if (_airportMode && _toAirport && _airport != null)
        const SizedBox.shrink(),
      TextButton(
        key: kCustomerBookingAddStopKey,
        onPressed: () => _addStop(inbound: false),
        child: Text(_t(kCustomerBookingAddStop)),
      ),
      _returnToggle(),
      if (_returnKind != CustomerBookingReturnKind.oneWay) ...[
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
      if (_returnKind == CustomerBookingReturnKind.noWait)
        ListTile(
          title: Text(_t(kCustomerBookingReturnWhen)),
          subtitle: Text(_formatWhen(_returnAt)),
          onTap: () => _pickDateTime(inbound: true),
        ),
      if (_returnKind == CustomerBookingReturnKind.wait) _waitChips(),
      const SizedBox(height: 8),
      Text(_t(kCustomerBookingVehicle), style: theme.textTheme.titleSmall),
      _vehicleRow(),
      const SizedBox(height: 8),
      _countRow(
        label: _t(kCustomerBookingPassengers),
        value: _passengers,
        incrementKey: kCustomerBookingPaxIncKey,
        onChanged: (value) {
          setState(() => _passengers = _clampPassengers(value));
          _suggestVehicleIfNeeded();
          _onDraftChanged();
        },
      ),
      _countRow(
        label: _t(kCustomerBookingBags),
        value: _bags,
        incrementKey: kCustomerBookingBagsIncKey,
        onChanged: (value) {
          setState(() => _bags = value);
          _suggestVehicleIfNeeded();
          _onDraftChanged();
        },
      ),
      if (!companyPlanVehicleTypeFitsCapacity(
        type: _vehicle,
        passengers: _passengers,
        bags: _bags,
      ))
        Text(_t(kCustomerBookingSuggestLarger)),
      const SizedBox(height: 12),
      _quotePanel(),
      ..._contactFields(),
      const SizedBox(height: 12),
      if (includeConfirm) _confirmBar(compact: true),
      SizedBox(height: confirmReserve),
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
          label: Text(_t(kCustomerBookingToAirport), key: kCustomerBookingToAirportKey),
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
            setState(() => _returnKind = CustomerBookingReturnKind.oneWay);
            _onDraftChanged();
          },
        ),
        ChoiceChip(
          key: kCustomerBookingReturnNoWaitKey,
          label: Text(_t(kCustomerBookingReturnNoWait)),
          selected: _returnKind == CustomerBookingReturnKind.noWait,
          onSelected: (_) {
            setState(() => _returnKind = CustomerBookingReturnKind.noWait);
            _syncReturnDefaults();
            _onDraftChanged();
          },
        ),
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
            label: Text(_t(kCustomerBookingLater), key: kCustomerBookingLaterKey),
          ),
        ],
        selected: {_whenNow},
        onSelectionChanged: (value) {
          setState(() {
            _whenNow = value.first;
            if (!_whenNow && _pickupAt == null) {
              _pickupAt = DateTime.now().add(const Duration(hours: 1));
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
    final hasProfile = profile != null &&
        customerProfileDefaultAddressLine(profile).isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 8,
        children: [
          if (hasProfile)
            TextButton.icon(
              key: kCustomerBookingMyAddressKey,
              onPressed: _useMyAddress,
              icon: const Icon(Icons.home_outlined),
              label: Text(_t(kCustomerBookingMyAddress)),
            ),
          TextButton.icon(
            key: kCustomerBookingUseLocationKey,
            onPressed: () => unawaited(_resolveGps(userRequested: true)),
            icon: const Icon(Icons.my_location_outlined),
            label: Text(_t(kCustomerBookingCurrentLocation)),
          ),
        ],
      ),
    );
  }

  List<CustomerBookingVehicleOffer> get _vehicleOffers {
    final duration = _quote?.durationMin;
    return customerBookingVehicleOffers(
      vehicles: _companyVehicles,
      drivers: <Map<String, dynamic>>[
        for (final driver in _companyDrivers)
          customerBookingPublishedDriverCard(driver),
        ..._availability.drivers,
      ],
      passengers: _passengers,
      pickupUtc: _effectivePickupUtc,
      durationMin: duration ?? 30,
      durationKnown: duration != null && duration > 0,
      rideReady: _rideDetailsReady,
      availableVehicleIds: _availability.availableIds,
      unavailableVehicleIds: _availability.unavailableIds,
      unavailableReasons: _availability.reasons,
      proposedDriverIds: _availability.driverIds,
      availabilityResolved: _availability.resolved,
      availabilityFailed: _availability.loadFailed,
    );
  }

  bool _addressQuoteReady(LimousineAddressValue value) {
    return companyPlanAddressIsQuoteReady(value);
  }

  bool get _rideDetailsReady {
    final hasAirport = _airport != null;
    return customerBookingRideDetailsReady(
      pickupFilled: (!_pickupNeedsConfirm && _addressQuoteReady(_pickup.value)) ||
          (_airportMode && !_toAirport && hasAirport),
      dropoffFilled: _addressQuoteReady(_dropoff.value) ||
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

  void _selectVehicleOffer(CustomerBookingVehicleOffer offer) {
    final category = classifyCompanyPlanVehicleCategory(offer.vehicle);
    final seats = offer.passengerSeats;
    setState(() {
      _selectedVehicleId = offer.vehicleId;
      _assignedDriver = customerBookingProposedDriverFromRecord(offer.driver);
      _vehicleCategory = category;
      if (category != null) {
        _vehicle = companyPlanVehicleTypeForCategory(category);
      }
      if (seats != null && seats > 0 && _passengers > seats) {
        _passengers = seats;
      }
      _submitError = null;
    });
    _onDraftChanged();
  }

  Widget _vehicleRow() {
    final offers = _vehicleOffers;
    final state = customerBookingVehicleOfferState(
      hasCompany: _hasChosenCompany,
      rideReady: _rideDetailsReady,
      loading: _vehiclesLoading,
      loadFailed: _vehiclesFailed || _availability.loadFailed,
      offers: offers,
      availabilityLoading: _availabilityLoading ||
          (_rideDetailsReady && _quoteLoading),
    );
    final grid = offers.isEmpty
        ? null
        : CustomerBookingVehiclePhotoCardGrid(
            key: kCustomerBookingVehicleHintKey,
            offers: offers,
            language: _language,
            selectedVehicleId: _selectedVehicleId,
            palette: _palette,
            onSelected: _selectVehicleOffer,
          );
    Widget message(String text, Key key, {VoidCallback? retry}) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, key: key),
          if (retry != null)
            TextButton(
              key: kCustomerBookingAvailabilityRetryKey,
              onPressed: retry,
              child: Text(_t(kCustomerBookingAvailabilityRetry)),
            ),
          if (grid != null) ...[const SizedBox(height: 8), grid],
        ],
      );
    }

    switch (state) {
      case CustomerBookingVehicleOfferState.needCompany:
        return Text(_t(kCustomerBookingNeedCompany));
      case CustomerBookingVehicleOfferState.loading:
        return message(
          _t(kCustomerBookingVehiclesLoading),
          kCustomerBookingVehiclesLoadingKey,
        );
      case CustomerBookingVehicleOfferState.checking:
        return message(
          _t(kCustomerBookingAvailabilityChecking),
          kCustomerBookingAvailabilityCheckingKey,
        );
      case CustomerBookingVehicleOfferState.loadFailed:
        return message(
          _t(kCustomerBookingVehiclesLoadFailed),
          kCustomerBookingVehiclesFailedKey,
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
        return Text(
          _t(kCustomerBookingNoCompanyVehicles),
          key: kCustomerBookingVehicleHintKey,
        );
      case CustomerBookingVehicleOfferState.ready:
        return grid ?? const SizedBox.shrink();
    }
  }

  Widget _countRow({
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
    Key? incrementKey,
  }) {
    return Row(
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
        Text(_t(kCustomerBookingChooseCountry), key: kCustomerBookingChooseCountryKey),
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
        Text(_t(kCustomerBookingChooseAirport), key: kCustomerBookingChooseAirportKey),
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

  Widget _flightFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_t(kCustomerBookingFlightSection)),
        TextField(
          key: kCustomerBookingFlightNumberKey,
          controller: _flightCtrl,
          decoration: InputDecoration(labelText: _t(kCustomerBookingFlightNumber)),
          textCapitalization: TextCapitalization.characters,
          onChanged: (_) => _onDraftChanged(),
        ),
        ListTile(
          key: kCustomerBookingFlightWhenKey,
          title: Text(
            _t(
              _toAirport
                  ? kCustomerBookingFlightDepart
                  : kCustomerBookingFlightArrive,
            ),
          ),
          subtitle: Text(_formatWhen(_flightAt)),
          onTap: _pickFlightWhen,
        ),
        if (!_toAirport)
          Text(
            _t(kCustomerBookingLandingNotPickup),
            key: kCustomerBookingLandingHintKey,
          ),
        if (_toAirport && _suggestedPickup != null)
          Text('${_t(kCustomerBookingPickupAdvice)}: ${_formatWhen(_suggestedPickup)}'),
        if (_flightTooLate) Text(_t(kCustomerBookingTooLateForFlight)),
      ],
    );
  }

  Widget _quotePanel() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: CustomerBookingPriceBlock(
        language: _language,
        loading: _quoteLoading,
        quote: _pickupNeedsConfirm ? null : _quote,
        error: _pickupNeedsConfirm ? null : _quoteError,
        onRetry: () => unawaited(_refreshQuote()),
      ),
    );
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
    });
    _onDraftChanged();
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
    });
    _onDraftChanged();
  }

  Widget _laterWhenFields() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 140, maxWidth: 220),
                child: _compactWhenField(
                  key: kCustomerBookingDateKey,
                  label: _t(kCustomerBookingDate),
                  value: _formatDate(_pickupAt),
                  icon: Icons.calendar_today_outlined,
                  onTap: _pickLaterDate,
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 110, maxWidth: 160),
                child: _compactWhenField(
                  key: kCustomerBookingTimeKey,
                  label: _t(kCustomerBookingTime),
                  value: _formatClock(_pickupAt),
                  icon: Icons.schedule_outlined,
                  onTap: _pickLaterTime,
                ),
              ),
            ],
          ),
          if (_laterPickupInvalid)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _t(kCustomerBookingLaterInvalid),
                key: kCustomerBookingLaterInvalidKey,
                style: TextStyle(
                  color: _palette.danger,
                  fontWeight: FontWeight.w700,
                ),
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
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            suffixIcon: Icon(icon, size: 18),
            isDense: true,
            contentPadding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          ),
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}
