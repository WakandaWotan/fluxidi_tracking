// lib/pages/calculator_page.dart
//
// Fluxidi — Calculator page (standalone, compile-safe)
// - Address autocomplete via Mapbox Geocoding API
// - "Use my current location" resolves to a REAL address (reverse geocode)
// - Bags limited to max 3 (Tesla Model 3 rule)
// - Pax limited to max 3
//
// Hook into your existing app by pushing CalculatorPage(...).
//
// NOTE: This file is intentionally self-contained and does not depend on your
// main.dart internals (no private fields). That prevents the kind of breakage
// you saw where Calculator logic ended up outside the State class.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company_session_store.dart';
import 'package:fluxidi_tracking/customer_bookings_store.dart';
import 'package:fluxidi_tracking/customer_profile_store.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:fluxidi_tracking/payment_return.dart';

const bool showPricingDebug = false;

String _calcBusinessText(dynamic value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty || text.toLowerCase() == 'null') return '';
  return text;
}

String _calcFirstBusinessText(List<dynamic> values) {
  for (final value in values) {
    final text = _calcBusinessText(value);
    if (text.isNotEmpty) return text;
  }
  return '';
}

bool _calcBusinessBool(dynamic value) {
  if (value is bool) return value;
  final text = _calcBusinessText(value).toLowerCase();
  return text == '1' || text == 'true' || text == 'yes' || text == 'ja';
}

bool _hasExplicitPrivateBookingIntent(Map<String, dynamic> source) {
  final business = _calcBusinessBool(
    source['business_detected'] ??
        source['businessDetected'] ??
        source['business_customer'] ??
        source['businessCustomer'] ??
        source['is_business'] ??
        source['isBusiness'],
  );
  final invoiceRequested = _calcBusinessBool(
    source['invoice_requested'] ?? source['invoiceRequested'],
  );
  final companyName = _calcFirstBusinessText([
    source['company_name'],
    source['companyName'],
    source['customer_company_name'],
    source['customerCompanyName'],
    source['customer_company'],
    source['customerCompany'],
  ]);
  final vatNumber = _calcFirstBusinessText([
    source['vat_number'],
    source['vatNumber'],
    source['customer_vat_number'],
    source['customerVatNumber'],
    source['customer_vat'],
    source['customerVat'],
  ]);
  return !business &&
      !invoiceRequested &&
      companyName.isEmpty &&
      vatNumber.isEmpty;
}

Map<String, dynamic> _buildBusinessInvoicePayload({
  required Map<String, dynamic> source,
  String? overrideCompanyName,
  String? overrideVatNumber,
  String? overrideInvoiceEmail,
  String? overrideInvoiceAddress,
}) {
  final companyName = overrideCompanyName != null
      ? overrideCompanyName.trim()
      : _calcFirstBusinessText([
          source['company_name'],
          source['companyName'],
          source['customer_company_name'],
          source['customerCompanyName'],
          source['customer_company'],
          source['customerCompany'],
        ]);
  final vatNumber = overrideVatNumber != null
      ? overrideVatNumber.trim()
      : _calcFirstBusinessText([
          source['vat_number'],
          source['vatNumber'],
          source['customer_vat_number'],
          source['customerVatNumber'],
          source['customer_vat'],
          source['customerVat'],
        ]);
  final hasVat = vatNumber.isNotEmpty;
  // VAT is the business/invoice intent gate until a dedicated UI toggle exists.
  // Company name alone must never force a business booking.
  final isBusiness = hasVat;
  final invoiceRequested = isBusiness;
  if (!isBusiness) {
    return <String, dynamic>{
      'business_detected': false,
      'businessDetected': false,
      'invoice_requested': false,
      'invoiceRequested': false,
      'company_name': '',
      'companyName': '',
      'vat_number': '',
      'vatNumber': '',
      'invoice_email': '',
      'invoiceEmail': '',
      'invoice_address': '',
      'invoiceAddress': '',
    };
  }
  final invoiceEmail = isBusiness
      ? (overrideInvoiceEmail != null
            ? overrideInvoiceEmail.trim()
            : _calcFirstBusinessText([
                source['invoice_email'],
                source['invoiceEmail'],
              ]))
      : '';
  final invoiceAddress = isBusiness
      ? (overrideInvoiceAddress != null
            ? overrideInvoiceAddress.trim()
            : _calcFirstBusinessText([
                source['invoice_address'],
                source['invoiceAddress'],
                source['billing_address'],
                source['billingAddress'],
                source['company_address'],
                source['companyAddress'],
              ]))
      : '';
  return <String, dynamic>{
    'business_detected': isBusiness,
    'businessDetected': isBusiness,
    'invoice_requested': invoiceRequested,
    'invoiceRequested': invoiceRequested,
    'company_name': companyName,
    'companyName': companyName,
    'vat_number': vatNumber,
    'vatNumber': vatNumber,
    'invoice_email': invoiceEmail,
    'invoiceEmail': invoiceEmail,
    'invoice_address': invoiceAddress,
    'invoiceAddress': invoiceAddress,
  };
}

String _maskBusinessPreview(String value) {
  final text = value.trim();
  if (text.isEmpty) return '';
  if (text.length <= 3) return '***';
  return '${text.substring(0, 1)}***${text.substring(text.length - 1)}';
}

void _logBusinessPayload({
  required String stage,
  required Map<String, dynamic> payload,
}) {
  final companyName = _calcBusinessText(
    payload['company_name'] ?? payload['companyName'],
  );
  final vatNumber = _calcBusinessText(
    payload['vat_number'] ?? payload['vatNumber'],
  );
  final invoiceEmail = _calcBusinessText(
    payload['invoice_email'] ?? payload['invoiceEmail'],
  );
  final invoiceAddress = _calcBusinessText(
    payload['invoice_address'] ?? payload['invoiceAddress'],
  );
  final business = _calcBusinessBool(
    payload['business_detected'] ?? payload['businessDetected'],
  );
  final invoiceRequested = _calcBusinessBool(
    payload['invoice_requested'] ?? payload['invoiceRequested'],
  );
  debugPrint(
    '[CALCULATOR][BUSINESS_PAYLOAD] stage=$stage business=$business invoiceRequested=$invoiceRequested companyFound=${companyName.isNotEmpty} vatFound=${vatNumber.isNotEmpty} invoiceEmailFound=${invoiceEmail.isNotEmpty} invoiceAddressFound=${invoiceAddress.isNotEmpty} company=${_maskBusinessPreview(companyName)} vat=${_maskBusinessPreview(vatNumber)}',
  );
}

class CalculatorPage extends StatefulWidget {
  const CalculatorPage({
    super.key,
    required this.bookingBaseUrl,
    required this.mapboxToken,
    this.onGoToStartPage,
  });

  final String
  bookingBaseUrl; // e.g. https://fluxidi-booking-api.fluxidi.workers.dev
  final String mapboxToken; // public pk...
  final VoidCallback? onGoToStartPage;

  @override
  State<CalculatorPage> createState() => _CalculatorPageState();
}

class _CalculatorPageState extends State<CalculatorPage> {
  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();

  Timer? _fromDebounce;
  Timer? _toDebounce;

  List<_PlaceSuggestion> _fromSuggestions = const <_PlaceSuggestion>[];
  List<_PlaceSuggestion> _toSuggestions = const <_PlaceSuggestion>[];
  int _fromAutocompleteRequestId = 0;
  int _toAutocompleteRequestId = 0;
  bool _addressSearchUnavailable = false;

  // Business rules (Tesla Model 3)
  int _pax = 1; // max 3
  int _bags = 0; // max 3

  // Booking payload fields
  DateTime? _pickupDateTime;
  DateTime? _returnPickupDateTime;
  String _tier = 'comfort';
  String _service = 'airport';
  String _extraService = 'none';
  bool _returnTrip = false;
  int _waitMin = 0;

  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _lastQuote;
  Map<String, dynamic>? _lastQuoteRequestPayload;
  final _vatCtrl = TextEditingController(
    text: appConfig.defaultVatRate.toStringAsFixed(2),
  );

  int get safeBags => _bags.clamp(0, 3);
  AppLanguage get _lang => appConfig.currentLanguage;
  AppStrings get _s => appConfig.strings;
  BusinessSettingsState get _business => businessSettingsNotifier.value;
  ActiveVatConfig get _activeVatConfig => resolveActiveVatConfig(
    settings: _business,
    taxProfile: localBackendTaxProfileNotifier.value,
  );
  bool get _returnFeatureEnabled => _business.pricingReturnEnabled;

  String get _currencySymbol {
    final configured = appConfig.defaultCurrencySymbol.trim();
    if (configured.isNotEmpty) return configured;
    switch (_business.defaultCurrency.toUpperCase()) {
      case 'EUR':
        return '€';
      case 'USD':
        return '\$';
      case 'GBP':
        return '£';
      default:
        return _business.defaultCurrency.toUpperCase();
    }
  }

  Color get _calcScaffoldColor => appConfig.branding.calculatorScaffoldColor;
  Color get _calcPanelColor => appConfig.branding.calculatorPanelColor;
  Color get _calcDropdownColor => appConfig.branding.calculatorDropdownColor;
  List<AppOption> get _services => appConfig.enabledServices;
  List<AppOption> get _tiers => appConfig.enabledTiers;
  List<AppOption> get _extras => appConfig.enabledExtraOptions;
  bool get _isPremiumTier => _tier == 'premium';

  String _payloadValueFor(
    List<AppOption> options,
    String selectedId, {
    required String fallback,
  }) {
    for (final o in options) {
      if (o.id == selectedId) return o.payloadValue;
    }
    return fallback;
  }

  String _toTitleFromKey(String key) {
    final parts = key
        .replaceAll(RegExp(r'[_\-]+'), ' ')
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) return key;
    return parts
        .map((p) => p[0].toUpperCase() + p.substring(1).toLowerCase())
        .join(' ');
  }

  String _breakdownLabelFor(String key) {
    switch (key) {
      case 'return_fee_ex':
        return _labelFor(
          nl: 'Retourtoeslag',
          en: 'Return surcharge',
          fr: 'Supplément retour',
          es: 'Recargo de vuelta',
        );
      case 'fuel_surcharge_ex':
        return _labelFor(
          nl: 'Brandstoftoeslag',
          en: 'Fuel surcharge',
          fr: 'Supplément carburant',
          es: 'Recargo de combustible',
        );
      case 'surcharge_amount_ex':
        return _labelFor(
          nl: 'Nacht/weekend toeslag',
          en: 'Night/weekend surcharge',
          fr: 'Supplément de nuit/week-end',
          es: 'Recargo nocturno/fin de semana',
        );
      default:
        final label = _s.breakdownLabel(key, _lang);
        return (label == key) ? _toTitleFromKey(key) : label;
    }
  }

  String _labelFor({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) {
    switch (_lang) {
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

  String _serviceLabel(String id, String fallback) {
    switch (id) {
      case 'airport':
        return _labelFor(
          nl: 'Luchthaven',
          en: 'Airport',
          fr: 'Aéroport',
          es: 'Aeropuerto',
        );
      case 'passenger_transport':
      case 'passenger':
        return _labelFor(
          nl: 'Personenvervoer',
          en: 'Passenger transport',
          fr: 'Transport de passagers',
          es: 'Transporte de pasajeros',
        );
      case 'business':
        return _labelFor(
          nl: 'Zakelijk',
          en: 'Business',
          fr: 'Affaires',
          es: 'Negocios',
        );
      case 'courier':
        return _labelFor(
          nl: 'Koerier',
          en: 'Courier',
          fr: 'Coursier',
          es: 'Mensajería',
        );
      case 'care_transport':
      case 'care':
        return _labelFor(
          nl: 'Zorgvervoer',
          en: 'Care transport',
          fr: 'Transport de soins',
          es: 'Transporte asistencial',
        );
      case 'event':
        return _labelFor(
          nl: 'Evenement',
          en: 'Event',
          fr: 'Événement',
          es: 'Evento',
        );
      default:
        return fallback;
    }
  }

  String _tierLabel(String id, String fallback) {
    switch (id) {
      case 'comfort':
        return _labelFor(
          nl: 'Comfort',
          en: 'Comfort',
          fr: 'Confort',
          es: 'Confort',
        );
      case 'private':
        return _labelFor(
          nl: 'Privé',
          en: 'Private',
          fr: 'Privé',
          es: 'Privado',
        );
      case 'premium':
        return _labelFor(
          nl: 'Premium',
          en: 'Premium',
          fr: 'Premium',
          es: 'Premium',
        );
      default:
        return fallback;
    }
  }

  String _extraLabel(String id, String fallback) {
    switch (id) {
      case 'none':
        return _labelFor(
          nl: 'Geen extra service',
          en: 'No extra service',
          fr: 'Aucun service supplémentaire',
          es: 'Sin servicio extra',
        );
      case 'drinks':
        return _labelFor(
          nl: 'Drankservice (water/frisdrank — alcohol op aanvraag)',
          en: 'Drinks service (water/soft drinks — alcohol on request)',
          fr: 'Service boissons (eau/softs — alcool sur demande)',
          es: 'Servicio de bebidas (agua/refrescos — alcohol bajo solicitud)',
        );
      case 'work_table':
      case 'worktable':
        return _labelFor(
          nl: 'Werktafel (laptopmodus)',
          en: 'Work table (laptop)',
          fr: 'Table de travail (mode ordinateur)',
          es: 'Mesa de trabajo (modo portátil)',
        );
      default:
        return fallback;
    }
  }

  String _extraCompactLabel(String id, String fallback) {
    switch (id) {
      case 'none':
        return _labelFor(
          nl: 'Geen extra service',
          en: 'No extra service',
          fr: 'Aucun extra',
          es: 'Sin extra',
        );
      case 'drinks':
        return _labelFor(
          nl: 'Drankservice',
          en: 'Drinks service',
          fr: 'Service boissons',
          es: 'Servicio bebidas',
        );
      case 'work_table':
      case 'worktable':
        return _labelFor(
          nl: 'Werktafel',
          en: 'Work table',
          fr: 'Table de travail',
          es: 'Mesa de trabajo',
        );
      default:
        return fallback;
    }
  }

  IconData _serviceIcon(String id) {
    switch (id) {
      case 'airport':
        return Icons.flight_takeoff;
      case 'passenger_transport':
      case 'passenger':
        return Icons.directions_car;
      case 'business':
        return Icons.business_center;
      case 'courier':
        return Icons.local_shipping;
      case 'care_transport':
      case 'care':
        return Icons.health_and_safety;
      case 'event':
        return Icons.event_available;
      default:
        return Icons.local_taxi;
    }
  }

  IconData _tierIcon(String id) {
    switch (id) {
      case 'comfort':
        return Icons.airline_seat_recline_normal;
      case 'private':
        return Icons.privacy_tip;
      case 'premium':
        return Icons.workspace_premium;
      default:
        return Icons.category_outlined;
    }
  }

  IconData _extraIcon(String id) {
    switch (id) {
      case 'none':
        return Icons.remove_circle_outline;
      case 'drinks':
        return Icons.local_cafe;
      case 'work_table':
      case 'worktable':
        return Icons.laptop_mac;
      default:
        return Icons.extension_outlined;
    }
  }

  Widget _dropdownMenuItemContent({
    required IconData icon,
    required String label,
  }) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFFE5B641), size: 19),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  String _backToStartLabel() {
    return _labelFor(
      nl: 'Terug naar startpagina',
      en: 'Back to start page',
      fr: 'Retour à l’accueil',
      es: 'Volver a la pantalla inicial',
    );
  }

  String _returnTripLabel() {
    return _labelFor(
      nl: 'Retourrit',
      en: 'Return trip',
      fr: 'Trajet retour',
      es: 'Viaje de vuelta',
    );
  }

  String _disabledReturnLabel() {
    return _labelFor(
      nl: 'Uitgeschakeld in de tariefinstellingen van het bedrijf.',
      en: 'Disabled in the company fare settings.',
      fr: 'Désactivé dans les paramètres tarifaires de l’entreprise.',
      es: 'Desactivado en la configuración de tarifas de la empresa.',
    );
  }

  String _fmtDateYmd(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  String _fmtTimeHm(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  String _isoLikeLocal(DateTime dt) {
    final off = dt.timeZoneOffset;
    final sign = off.isNegative ? '-' : '+';
    final totalMin = off.inMinutes.abs();
    final oh = (totalMin ~/ 60).toString().padLeft(2, '0');
    final om = (totalMin % 60).toString().padLeft(2, '0');
    return '${_fmtDateYmd(dt)}T${_fmtTimeHm(dt)}:00$sign$oh:$om';
  }

  String _activeTenantCompanyId() {
    final localCompanyId = companyProfileNotifier.value?.companyId.trim() ?? '';
    if (localCompanyId.isNotEmpty) return localCompanyId;
    final resolved = resolvedCompanyId.trim();
    if (resolved.isNotEmpty) return resolved;
    return kTenantId;
  }

  Map<String, dynamic> _buildQuotePayload(DateTime dt) {
    final vat = _activeVatConfig;
    final tenantCompanyId = _activeTenantCompanyId();
    final returnEnabled = _returnFeatureEnabled && _returnTrip;
    final returnDt =
        _returnPickupDateTime ??
        dt.add(
          Duration(minutes: (_waitMin > 0 ? _waitMin : 30).clamp(0, 24 * 60)),
        );
    final businessPayload = _buildBusinessInvoicePayload(
      source: const <String, dynamic>{},
      overrideCompanyName: '',
      overrideVatNumber: '',
      overrideInvoiceEmail: '',
      overrideInvoiceAddress: '',
    );
    return <String, dynamic>{
      "from": _fromCtrl.text.trim(),
      "to": _toCtrl.text.trim(),
      "date": _fmtDateYmd(dt),
      "time": _fmtTimeHm(dt),
      "pickup_iso": _isoLikeLocal(dt),
      "tier": _payloadValueFor(_tiers, _tier, fallback: 'COMFORT'),
      "service": _payloadValueFor(_services, _service, fallback: 'AIRPORT'),
      "pax": _pax,
      "bags": safeBags,
      "wait_min": _waitMin,
      "return": returnEnabled,
      "return_enabled": returnEnabled,
      "return_from": _toCtrl.text.trim(),
      "return_to": _fromCtrl.text.trim(),
      "return_date": returnEnabled ? _fmtDateYmd(returnDt) : '',
      "return_time": returnEnabled ? _fmtTimeHm(returnDt) : '',
      "return_pickup_iso": returnEnabled ? _isoLikeLocal(returnDt) : '',
      "vat_rate": vat.vatRate,
      "vat_mode": vat.vatMode,
      "pricing_profile": <String, dynamic>{
        "base_fare": _business.pricingBaseFare,
        "price_per_km": _business.pricingPerKm,
        "price_per_minute": _business.pricingPerMinute,
        "minimum_fare": _business.pricingMinimumFare,
        "wait_per_minute": _business.pricingWaitPerMinute,
        "return_enabled": _business.pricingReturnEnabled,
        "return_fee": _business.pricingReturnFee,
        "fuel_surcharge": _business.pricingFuelSurcharge,
        "vat_rate": vat.vatRate,
        "vat_mode": vat.vatMode,
      },
      "surcharge_fuel": _business.pricingFuelSurcharge,
      "return_fee": returnEnabled ? _business.pricingReturnFee : 0,
      "extra_service": _isPremiumTier
          ? _payloadValueFor(_extras, _extraService, fallback: 'NONE')
          : 'NONE',
      "extra_service_key": _isPremiumTier
          ? _payloadValueFor(_extras, _extraService, fallback: 'NONE')
          : 'NONE',
      "tenant_id": tenantCompanyId,
      "company_id": tenantCompanyId,
      "tenantId": tenantCompanyId,
      "companyId": tenantCompanyId,
      ...businessPayload,
    };
  }

  Map<String, dynamic> _buildQuoteRequestPayload(DateTime dt) {
    return _buildQuotePayload(dt);
  }

  void _openBookingConfirmation() {
    final quote = _lastQuote;
    if (quote == null) return;
    final dt =
        _pickupDateTime ?? DateTime.now().add(const Duration(minutes: 15));
    final payload = _lastQuoteRequestPayload != null
        ? Map<String, dynamic>.from(_lastQuoteRequestPayload!)
        : _buildQuotePayload(dt);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _BookingConfirmationPage(
          bookingBaseUrl: widget.bookingBaseUrl,
          language: _lang,
          strings: _s,
          quote: quote,
          payload: payload,
          currencySymbol: _currencySymbol,
          distanceUnitLabel: appConfig.distanceUnitLabel,
          durationUnitLabel: appConfig.durationUnitLabel,
          taxLabel: appConfig.taxDisplayLabel,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    appLanguageNotifier.addListener(_onLanguageChanged);
    businessSettingsNotifier.addListener(_onBusinessSettingsChanged);
    localBackendTaxProfileNotifier.addListener(_onVatProfileChanged);
  }

  void _onLanguageChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _onBusinessSettingsChanged() {
    if (!mounted) return;
    if (!_returnFeatureEnabled && _returnTrip) {
      _returnTrip = false;
      _returnPickupDateTime = null;
    }
    setState(() {});
  }

  void _onVatProfileChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    appLanguageNotifier.removeListener(_onLanguageChanged);
    businessSettingsNotifier.removeListener(_onBusinessSettingsChanged);
    localBackendTaxProfileNotifier.removeListener(_onVatProfileChanged);
    _fromDebounce?.cancel();
    _toDebounce?.cancel();
    _fromCtrl.dispose();
    _toCtrl.dispose();
    _vatCtrl.dispose();
    super.dispose();
  }

  // ---------- Mapbox helpers ----------
  Future<({List<_PlaceSuggestion> results, bool hadError})> _searchPlaces(
    String query,
  ) async {
    if (widget.mapboxToken.trim().isEmpty) {
      return (results: const <_PlaceSuggestion>[], hadError: false);
    }
    final q = query.trim();
    if (q.isEmpty)
      return (results: const <_PlaceSuggestion>[], hadError: false);

    // Bias around Belgium by default. You can tweak later.
    final url = Uri.parse(
      'https://api.mapbox.com/geocoding/v5/mapbox.places/${Uri.encodeComponent(q)}.json'
      '?access_token=${Uri.encodeComponent(widget.mapboxToken)}'
      '&autocomplete=true'
      '&country=be'
      '&language=nl'
      '&limit=6',
    );

    try {
      final res = await http.get(url).timeout(const Duration(seconds: 7));
      if (res.statusCode != 200) {
        return (results: const <_PlaceSuggestion>[], hadError: true);
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final features = (data['features'] as List?) ?? const [];
      final out = features
          .map<_PlaceSuggestion>((f) {
            final m = f as Map<String, dynamic>;
            final placeName = (m['place_name'] ?? '') as String;
            final center = (m['center'] as List?) ?? const [];
            final lon = center.isNotEmpty
                ? (center[0] as num).toDouble()
                : null;
            final lat = center.length > 1
                ? (center[1] as num).toDouble()
                : null;
            return _PlaceSuggestion(label: placeName, lon: lon, lat: lat);
          })
          .toList(growable: false);
      return (results: out, hadError: false);
    } on SocketException {
      debugPrint('[MAPBOX][GEOCODE][ERROR] reason=network');
      return (results: const <_PlaceSuggestion>[], hadError: true);
    } on http.ClientException {
      debugPrint('[MAPBOX][GEOCODE][ERROR] reason=client_exception');
      return (results: const <_PlaceSuggestion>[], hadError: true);
    } on TimeoutException {
      debugPrint('[MAPBOX][GEOCODE][TIMEOUT]');
      return (results: const <_PlaceSuggestion>[], hadError: true);
    } on FormatException {
      debugPrint('[MAPBOX][GEOCODE][ERROR] reason=format');
      return (results: const <_PlaceSuggestion>[], hadError: true);
    } catch (_) {
      debugPrint('[MAPBOX][GEOCODE][ERROR] reason=unexpected');
      return (results: const <_PlaceSuggestion>[], hadError: true);
    }
  }

  String _addressSearchUnavailableMessage() => _labelFor(
    nl: 'Adres zoeken lukt even niet. Controleer je verbinding of vul het adres handmatig in.',
    en: 'Address search is temporarily unavailable. Check your connection or enter the address manually.',
    fr: 'La recherche d’adresse est temporairement indisponible. Vérifiez votre connexion ou saisissez l’adresse manuellement.',
    es: 'La búsqueda de direcciones no está disponible temporalmente. Comprueba tu conexión o introduce la dirección manualmente.',
  );

  Future<String?> _reverseGeocode(double lat, double lon) async {
    if (widget.mapboxToken.trim().isEmpty) return null;
    final url = Uri.parse(
      'https://api.mapbox.com/geocoding/v5/mapbox.places/${lon.toStringAsFixed(6)},${lat.toStringAsFixed(6)}.json'
      '?access_token=${Uri.encodeComponent(widget.mapboxToken)}'
      '&language=nl'
      '&country=be'
      '&limit=1',
    );

    final res = await http.get(url);
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final features = (data['features'] as List?) ?? const [];
    if (features.isEmpty) return null;
    final f = features.first as Map<String, dynamic>;
    return (f['place_name'] ?? '') as String?;
  }

  Future<void> _setFromCurrentLocation() async {
    try {
      final enabled = await geo.Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        _toast(_s.calculatorLocationServiceOffError.of(_lang));
        return;
      }

      var perm = await geo.Geolocator.checkPermission();
      if (perm == geo.LocationPermission.denied) {
        perm = await geo.Geolocator.requestPermission();
      }
      if (perm == geo.LocationPermission.denied ||
          perm == geo.LocationPermission.deniedForever) {
        _toast(_s.calculatorNoLocationPermissionError.of(_lang));
        return;
      }

      final pos = await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.best,
      );

      final addr = await _reverseGeocode(pos.latitude, pos.longitude);

      if (!mounted) return;
      setState(() {
        _fromCtrl.text = (addr != null && addr.trim().isNotEmpty)
            ? addr
            : _s.calculatorCurrentLocationFallbackLabel.of(_lang);
        _fromSuggestions = const <_PlaceSuggestion>[];
      });
    } catch (e) {
      _toast(_s.calculatorCurrentLocationFailedError.of(_lang));
    }
  }

  // ---------- UI helpers ----------
  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _zoneCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(14),
    Color? color,
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? _calcPanelColor.withOpacity(0.94),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE5B641).withOpacity(0.08),
            blurRadius: 18,
            spreadRadius: 1,
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _suggestionList(
    List<_PlaceSuggestion> list,
    void Function(_PlaceSuggestion) onTap,
  ) {
    if (list.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: _calcPanelColor,
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: list.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, color: Colors.white12),
        itemBuilder: (context, i) {
          final s = list[i];
          return ListTile(
            dense: true,
            title: Text(s.label, style: const TextStyle(color: Colors.white)),
            subtitle: Text(
              _s.calculatorSuggestionTapHint.of(_lang),
              style: const TextStyle(color: Colors.white54),
            ),
            onTap: () => onTap(s),
          );
        },
      ),
    );
  }

  Widget _counterRow({
    required String label,
    required String value,
    required VoidCallback? onMinus,
    required VoidCallback? onPlus,
    String? hint,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _calcPanelColor.withOpacity(0.72),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (hint != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    hint,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: onMinus,
            icon: const Icon(
              Icons.remove_circle_outline,
              color: Color(0xFFE5B641),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          IconButton(
            onPressed: onPlus,
            icon: const Icon(
              Icons.add_circle_outline,
              color: Color(0xFFE5B641),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final base = _pickupDateTime ?? now.add(const Duration(minutes: 15));

    final d = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: now.subtract(const Duration(days: 0)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (d == null) return;

    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (t == null) return;

    setState(() {
      _pickupDateTime = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    });
  }

  Future<void> _pickReturnDateTime() async {
    final basePickup =
        _pickupDateTime ?? DateTime.now().add(const Duration(minutes: 15));
    final fallback = basePickup.add(
      Duration(minutes: (_waitMin > 0 ? _waitMin : 30).clamp(0, 24 * 60)),
    );
    final base = _returnPickupDateTime ?? fallback;

    final d = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: basePickup,
      lastDate: basePickup.add(const Duration(days: 365)),
    );
    if (d == null) return;

    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (t == null) return;

    setState(() {
      _returnPickupDateTime = DateTime(
        d.year,
        d.month,
        d.day,
        t.hour,
        t.minute,
      );
    });
  }

  // ---------- quote ----------
  Future<void> _calculate() async {
    FocusScope.of(context).unfocus();

    if (_fromCtrl.text.trim().isEmpty || _toCtrl.text.trim().isEmpty) {
      _toast(_s.calculatorFillFromToError.of(_lang));
      return;
    }

    final dt =
        _pickupDateTime ?? DateTime.now().add(const Duration(minutes: 15));

    // Worker is source of truth; keep payload aligned with your API expectations.
    // Current booking form state is authoritative for business intent.
    final body = _buildQuoteRequestPayload(dt);
    _lastQuoteRequestPayload = Map<String, dynamic>.from(body);

    setState(() {
      _loading = true;
      _error = null;
      _lastQuote = null;
    });

    try {
      final url = Uri.parse('${widget.bookingBaseUrl}/quote');
      _logBusinessPayload(stage: 'quote', payload: body);
      debugPrint('quote_request_body=${jsonEncode(body)}');
      final res = await http.post(
        url,
        headers: const {'content-type': 'application/json'},
        body: jsonEncode(body),
      );

      final txt = res.body;
      debugPrint('quote_response_raw=$txt');
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception(
          'Quote failed: ${res.statusCode} ${txt.isNotEmpty ? txt : ''}',
        );
      }

      final data = jsonDecode(txt) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _lastQuote = data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Widget _quoteBox(Map<String, dynamic> q) {
    double? parseNum(dynamic v) {
      if (v == null) return null;
      if (v is num) {
        final n = v.toDouble();
        return n.isFinite ? n : null;
      }
      var s = v.toString().trim();
      if (s.isEmpty) return null;
      s = s.replaceAll(RegExp(r'[^0-9,\.\-]'), '');
      if (s.contains(',') && !s.contains('.')) s = s.replaceAll(',', '.');
      if (s.contains(',') && s.contains('.')) s = s.replaceAll(',', '');
      final n = double.tryParse(s);
      if (n == null || !n.isFinite) return null;
      return n;
    }

    String fmtNum(dynamic v, {int decimals = 2}) {
      final n = parseNum(v);
      if (n == null) return '—';
      return n.toStringAsFixed(decimals);
    }

    final ret = q['return'] is Map
        ? Map<String, dynamic>.from(q['return'] as Map)
        : <String, dynamic>{};
    final mainEx = parseNum(q['price_ex_vat']) ?? 0.0;
    final mainVat = parseNum(q['price_vat']) ?? 0.0;
    final mainIncl = parseNum(q['price_incl_vat']) ?? 0.0;
    final retEx = parseNum(ret['price_ex_vat']) ?? 0.0;
    final retVat = parseNum(ret['price_vat']) ?? 0.0;
    final retIncl = parseNum(ret['price_incl_vat']) ?? 0.0;
    final priceEx = parseNum(q['total_price_ex_vat']) ?? (mainEx + retEx);
    final priceVat = parseNum(q['total_price_vat']) ?? (mainVat + retVat);
    final priceIncl =
        parseNum(q['total_price_incl_vat']) ?? (mainIncl + retIncl);
    final distanceKm =
        q['distance_km'] ??
        (((q['distance_m'] ?? q['distanceMeters']) is num)
            ? ((q['distance_m'] ?? q['distanceMeters']) as num) / 1000
            : null);
    final durationMin =
        q['duration_min'] ??
        (((q['duration_s'] ?? q['durationSec']) is num)
            ? ((q['duration_s'] ?? q['durationSec']) as num) / 60
            : null);
    final returnDistanceKm =
        ret['distance_km'] ??
        (((ret['distance_m'] ?? ret['distanceMeters']) is num)
            ? ((ret['distance_m'] ?? ret['distanceMeters']) as num) / 1000
            : null);
    final returnDurationMin =
        ret['duration_min'] ??
        (((ret['duration_s'] ?? ret['durationSec']) is num)
            ? ((ret['duration_s'] ?? ret['durationSec']) as num) / 60
            : null);
    final breakdown = q['breakdown'] is Map<String, dynamic>
        ? q['breakdown'] as Map<String, dynamic>
        : (q['breakdown'] is Map
              ? Map<String, dynamic>.from(q['breakdown'] as Map)
              : <String, dynamic>{});
    final vatRateRaw =
        parseNum(q['vat_rate']) ??
        parseNum(breakdown['vat_rate']) ??
        parseNum(
          (q['inputs'] is Map) ? (q['inputs'] as Map)['vat_rate'] : null,
        ) ??
        parseNum(
          (q['pricing_profile'] is Map)
              ? (q['pricing_profile'] as Map)['vat_rate']
              : null,
        ) ??
        _activeVatConfig.vatRate;
    final vatPct = (vatRateRaw <= 1 ? vatRateRaw * 100 : vatRateRaw);
    final durationForTimeCost =
        parseNum(breakdown['duration_min']) ?? parseNum(durationMin) ?? 0.0;
    final distanceForCost =
        parseNum(breakdown['distance_km']) ?? parseNum(distanceKm) ?? 0.0;
    final perKmRateEx = parseNum(breakdown['per_km_ex']) ?? 0.0;
    final perMinRateEx = parseNum(breakdown['per_min_ex']) ?? 0.0;
    final distanceCostEx =
        parseNum(breakdown['distance_cost_ex']) ??
        parseNum(breakdown['per_km_total_ex']) ??
        (distanceForCost * perKmRateEx);
    final timeCostEx =
        parseNum(breakdown['time_cost_ex']) ??
        parseNum(breakdown['per_min_total_ex']) ??
        (durationForTimeCost * perMinRateEx);
    final returnSelected = _returnFeatureEnabled && _returnTrip;
    final waitDisplayMin = _waitMin > 0 ? _waitMin.toDouble() : 0.0;
    final baseDistance = parseNum(distanceKm);
    final baseDuration = parseNum(durationMin);
    final totalDisplayDistance = baseDistance == null
        ? null
        : baseDistance +
              (returnSelected
                  ? (parseNum(returnDistanceKm) ?? baseDistance)
                  : 0.0);
    final totalDisplayDuration = baseDuration == null
        ? null
        : baseDuration +
              (returnSelected
                  ? (parseNum(returnDurationMin) ?? baseDuration)
                  : 0.0) +
              waitDisplayMin;
    final showTotalMetrics = returnSelected || waitDisplayMin > 0;
    final distanceLabel = showTotalMetrics
        ? _labelFor(
            nl: 'Afstand totaal',
            en: 'Total distance',
            fr: 'Distance totale',
            es: 'Distancia total',
          )
        : _s.calculatorDistanceLabel.of(_lang);
    final durationLabel = showTotalMetrics
        ? _labelFor(
            nl: 'Tijd totaal',
            en: 'Total time',
            fr: 'Temps total',
            es: 'Tiempo total',
          )
        : _s.calculatorDurationLabel.of(_lang);
    String fmtMoneyVal(dynamic v) => '$_currencySymbol ${fmtNum(v)}';
    MapEntry<String, String>? breakdownEntry({
      required String key,
      required String label,
    }) {
      final value = parseNum(breakdown[key]);
      if (value == null || value <= 0) return null;
      return MapEntry<String, String>(
        label,
        '$_currencySymbol ${fmtNum(value)}',
      );
    }

    final detailsRows = <MapEntry<String, String>>[
      MapEntry<String, String>(
        _labelFor(nl: 'Tarief', en: 'Service', fr: 'Service', es: 'Servicio'),
        _serviceLabel(_service, _service),
      ),
      if (_returnFeatureEnabled && _returnTrip)
        MapEntry<String, String>(
          _labelFor(
            nl: 'Retourrit',
            en: 'Return ride',
            fr: 'Trajet retour',
            es: 'Viaje de regreso',
          ),
          _labelFor(nl: 'Ja', en: 'Yes', fr: 'Oui', es: 'Si'),
        ),
      if (_waitMin > 0)
        MapEntry<String, String>(
          _labelFor(
            nl: 'Wachttijd',
            en: 'Waiting time',
            fr: 'Temps d\'attente',
            es: 'Tiempo de espera',
          ),
          '$_waitMin ${_labelFor(nl: 'min', en: 'min', fr: 'min', es: 'min')}',
        ),
      if (_bags > 0)
        MapEntry<String, String>(
          _labelFor(nl: 'Bagage', en: 'Baggage', fr: 'Bagages', es: 'Equipaje'),
          '$_bags',
        ),
      if (_isPremiumTier && _extraService != 'none')
        MapEntry<String, String>(
          _labelFor(
            nl: 'Extra service',
            en: 'Extra service',
            fr: 'Service supplementaire',
            es: 'Servicio extra',
          ),
          _extraCompactLabel(
            _extraService,
            _extraLabel(_extraService, _extraService),
          ),
        ),
      ...[
        breakdownEntry(
          key: 'return_fee_ex',
          label: _labelFor(
            nl: 'Retourrit',
            en: 'Return fee',
            fr: 'Frais retour',
            es: 'Tarifa regreso',
          ),
        ),
        breakdownEntry(
          key: 'waiting_ex',
          label: _labelFor(
            nl: 'Wachttijd',
            en: 'Waiting',
            fr: 'Attente',
            es: 'Espera',
          ),
        ),
        breakdownEntry(
          key: 'bags_ex',
          label: _labelFor(
            nl: 'Bagage',
            en: 'Baggage',
            fr: 'Bagages',
            es: 'Equipaje',
          ),
        ),
        breakdownEntry(
          key: 'extra_stops_ex',
          label: _labelFor(
            nl: 'Stops',
            en: 'Stops',
            fr: 'Arrets',
            es: 'Paradas',
          ),
        ),
        breakdownEntry(
          key: 'tier_fee_ex',
          label: _labelFor(
            nl: 'Extra service',
            en: 'Extra service',
            fr: 'Service supplementaire',
            es: 'Servicio extra',
          ),
        ),
      ].whereType<MapEntry<String, String>>(),
      if (parseNum(q['total_price_ex_vat']) != null ||
          parseNum(q['price_ex_vat']) != null)
        MapEntry<String, String>(
          _labelFor(
            nl: 'Prijs excl. btw',
            en: 'Price excl. VAT',
            fr: 'Prix hors TVA',
            es: 'Precio sin IVA',
          ),
          '$_currencySymbol ${fmtNum(priceEx)}',
        ),
      if (parseNum(q['total_price_vat']) != null ||
          parseNum(q['price_vat']) != null)
        MapEntry<String, String>(
          _labelFor(nl: 'Btw', en: 'VAT', fr: 'TVA', es: 'IVA'),
          '$_currencySymbol ${fmtNum(priceVat)}',
        ),
      if (parseNum(q['total_price_incl_vat']) != null ||
          parseNum(q['price_incl_vat']) != null)
        MapEntry<String, String>(
          _labelFor(
            nl: 'Prijs incl. btw',
            en: 'Price incl. VAT',
            fr: 'Prix TTC',
            es: 'Precio con IVA',
          ),
          '$_currencySymbol ${fmtNum(priceIncl)}',
        ),
    ];

    Widget summaryChip({
      required IconData icon,
      required String label,
      required String value,
    }) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 230),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.28),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: const Color(0xFFE5B641)),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  '$label $value',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: _calcPanelColor.withOpacity(0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5B641).withOpacity(0.35)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE5B641).withOpacity(0.08),
            blurRadius: 18,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.place_outlined,
                size: 16,
                color: Color(0xFFE5B641),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _fromCtrl.text.trim().isEmpty
                      ? _s.calculatorFromLabel.of(_lang)
                      : _fromCtrl.text.trim(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 2, top: 2, bottom: 2),
            child: Row(
              children: [
                const SizedBox(width: 14),
                Icon(
                  Icons.south_rounded,
                  size: 14,
                  color: Colors.white.withOpacity(0.5),
                ),
              ],
            ),
          ),
          Row(
            children: [
              const Icon(
                Icons.flag_outlined,
                size: 16,
                color: Color(0xFFE5B641),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _toCtrl.text.trim().isEmpty
                      ? _s.calculatorToLabel.of(_lang)
                      : _toCtrl.text.trim(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              summaryChip(
                icon: Icons.groups_2_outlined,
                label: _labelFor(nl: 'Pax', en: 'Pax', fr: 'Pax', es: 'Pax'),
                value: '$_pax',
              ),
              summaryChip(
                icon: Icons.luggage_outlined,
                label: _labelFor(
                  nl: 'Bagage',
                  en: 'Bags',
                  fr: 'Bagages',
                  es: 'Maletas',
                ),
                value: '$_bags',
              ),
              summaryChip(
                icon: Icons.compare_arrows_outlined,
                label: _labelFor(
                  nl: 'Retour',
                  en: 'Return',
                  fr: 'Retour',
                  es: 'Vuelta',
                ),
                value: _returnFeatureEnabled && _returnTrip
                    ? _labelFor(nl: 'Ja', en: 'Yes', fr: 'Oui', es: 'Si')
                    : _labelFor(nl: 'Nee', en: 'No', fr: 'Non', es: 'No'),
              ),
              if (_waitMin > 0)
                summaryChip(
                  icon: Icons.schedule_outlined,
                  label: _labelFor(
                    nl: 'Wacht',
                    en: 'Wait',
                    fr: 'Attente',
                    es: 'Espera',
                  ),
                  value:
                      '$_waitMin ${_labelFor(nl: 'min', en: 'min', fr: 'min', es: 'min')}',
                ),
              if (_isPremiumTier && _extraService != 'none')
                summaryChip(
                  icon: Icons.stars_outlined,
                  label: _labelFor(
                    nl: 'Extra',
                    en: 'Extra',
                    fr: 'Extra',
                    es: 'Extra',
                  ),
                  value: _extraCompactLabel(
                    _extraService,
                    _extraLabel(_extraService, _extraService),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 9),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.25),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    distanceLabel,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${fmtNum(showTotalMetrics ? totalDisplayDistance : distanceKm, decimals: 2)} ${appConfig.distanceUnitLabel}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    durationLabel,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${fmtNum(showTotalMetrics ? totalDisplayDuration : durationMin, decimals: 0)} ${appConfig.durationUnitLabel}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          ...detailsRows.map((e) => _kv(e.key, e.value)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.35),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _labelFor(
                      nl: 'Totaalprijs',
                      en: 'Total price',
                      fr: 'Prix total',
                      es: 'Precio total',
                    ),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '$_currencySymbol ${fmtNum(priceIncl)}',
                  style: const TextStyle(
                    color: Color(0xFFE5B641),
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                Icons.verified_outlined,
                size: 14,
                color: Colors.white.withOpacity(0.70),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _labelFor(
                    nl: 'Inclusief btw  •  Geen verborgen kosten',
                    en: 'VAT included  •  No hidden costs',
                    fr: 'TVA incluse  •  Aucun frais cache',
                    es: 'IVA incluido  •  Sin costes ocultos',
                  ),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.68),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              k,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              v,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFE5B641);

    return Scaffold(
      backgroundColor: _calcScaffoldColor,
      appBar: AppBar(
        backgroundColor: _calcScaffoldColor,
        title: Text(
          _s.calculatorTitle.of(_lang),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (widget.onGoToStartPage != null)
            TextButton.icon(
              onPressed: widget.onGoToStartPage,
              icon: const Icon(Icons.home_outlined, size: 18),
              label: Text(_backToStartLabel()),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
          children: [
            _zoneCard(
              color: _calcPanelColor.withOpacity(0.88),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: accent.withOpacity(0.18),
                          shape: BoxShape.circle,
                          border: Border.all(color: accent.withOpacity(0.45)),
                        ),
                        child: const Icon(
                          Icons.local_taxi_outlined,
                          color: accent,
                          size: 19,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _s.calculatorTitle.of(_lang),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _s.calculatorMenuSubtitle.of(_lang),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.72),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _zoneCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.route_outlined, size: 18, color: accent),
                      const SizedBox(width: 8),
                      Text(
                        '${_s.calculatorFromLabel.of(_lang)}  ->  ${_s.calculatorToLabel.of(_lang)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _s.calculatorFromLabel.of(_lang),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _fromCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: _calcPanelColor.withOpacity(0.76),
                      hintText: _s.calculatorAddressHint.of(_lang),
                      hintStyle: const TextStyle(color: Colors.white38),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: Colors.white.withOpacity(0.08),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: Colors.white.withOpacity(0.08),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: accent.withOpacity(0.70),
                          width: 1.1,
                        ),
                      ),
                      suffixIcon: IconButton(
                        onPressed: _setFromCurrentLocation,
                        icon: const Icon(
                          Icons.my_location,
                          color: Colors.white70,
                        ),
                        tooltip: _s.calculatorUseCurrentLocationTooltip.of(
                          _lang,
                        ),
                      ),
                    ),
                    onChanged: (v) {
                      _fromDebounce?.cancel();
                      final requestId = ++_fromAutocompleteRequestId;
                      if (v.trim().isEmpty) {
                        setState(() {
                          _fromSuggestions = const <_PlaceSuggestion>[];
                          _addressSearchUnavailable = false;
                        });
                        return;
                      }
                      final query = v.trim();
                      _fromDebounce = Timer(
                        const Duration(milliseconds: 220),
                        () async {
                          final result = await _searchPlaces(query);
                          if (!mounted) return;
                          if (requestId != _fromAutocompleteRequestId ||
                              _fromCtrl.text.trim() != query) {
                            debugPrint(
                              '[MAPBOX][GEOCODE][STALE_SKIP] field=from',
                            );
                            return;
                          }
                          setState(() {
                            _fromSuggestions = result.results;
                            _addressSearchUnavailable = result.hadError;
                          });
                        },
                      );
                    },
                  ),
                  _suggestionList(_fromSuggestions, (s) {
                    setState(() {
                      _fromCtrl.text = s.label;
                      _fromSuggestions = const <_PlaceSuggestion>[];
                    });
                  }),
                  const SizedBox(height: 12),
                  Text(
                    _s.calculatorToLabel.of(_lang),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _toCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: _calcPanelColor.withOpacity(0.76),
                      hintText: _s.calculatorAddressHint.of(_lang),
                      hintStyle: const TextStyle(color: Colors.white38),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: Colors.white.withOpacity(0.08),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: Colors.white.withOpacity(0.08),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: accent.withOpacity(0.70),
                          width: 1.1,
                        ),
                      ),
                    ),
                    onChanged: (v) {
                      _toDebounce?.cancel();
                      final requestId = ++_toAutocompleteRequestId;
                      if (v.trim().isEmpty) {
                        setState(() {
                          _toSuggestions = const <_PlaceSuggestion>[];
                          _addressSearchUnavailable = false;
                        });
                        return;
                      }
                      final query = v.trim();
                      _toDebounce = Timer(
                        const Duration(milliseconds: 220),
                        () async {
                          final result = await _searchPlaces(query);
                          if (!mounted) return;
                          if (requestId != _toAutocompleteRequestId ||
                              _toCtrl.text.trim() != query) {
                            debugPrint(
                              '[MAPBOX][GEOCODE][STALE_SKIP] field=to',
                            );
                            return;
                          }
                          setState(() {
                            _toSuggestions = result.results;
                            _addressSearchUnavailable = result.hadError;
                          });
                        },
                      );
                    },
                  ),
                  _suggestionList(_toSuggestions, (s) {
                    setState(() {
                      _toCtrl.text = s.label;
                      _toSuggestions = const <_PlaceSuggestion>[];
                      _addressSearchUnavailable = false;
                    });
                  }),
                  if (_addressSearchUnavailable) ...[
                    const SizedBox(height: 8),
                    Text(
                      _addressSearchUnavailableMessage(),
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            _zoneCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.tune_rounded, size: 18, color: accent),
                      const SizedBox(width: 8),
                      Text(
                        _s.calculatorServiceLabel.of(_lang),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _counterRow(
                    label: _s.calculatorBagsLabel.of(_lang),
                    value: '$_bags',
                    hint: _s.calculatorMaxBagsHint.of(_lang),
                    onMinus: _bags > 0 ? () => setState(() => _bags--) : null,
                    onPlus: _bags < 3 ? () => setState(() => _bags++) : null,
                  ),
                  const SizedBox(height: 9),
                  _counterRow(
                    label: _s.calculatorPassengersLabel.of(_lang),
                    value: '$_pax',
                    hint: _s.calculatorMaxPassengersHint.of(_lang),
                    onMinus: _pax > 1 ? () => setState(() => _pax--) : null,
                    onPlus: _pax < 3 ? () => setState(() => _pax++) : null,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: _calcPanelColor.withOpacity(0.72),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _s.calculatorPickupTimeLabel.of(_lang),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Flexible(
                          child: Text(
                            _pickupDateTime == null
                                ? _s.calculatorChoosePickupTimeLabel.of(_lang)
                                : '${_pickupDateTime!.day.toString().padLeft(2, '0')}-'
                                      '${_pickupDateTime!.month.toString().padLeft(2, '0')}-'
                                      '${_pickupDateTime!.year} '
                                      '${_pickupDateTime!.hour.toString().padLeft(2, '0')}:'
                                      '${_pickupDateTime!.minute.toString().padLeft(2, '0')}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12.5,
                            ),
                            textAlign: TextAlign.end,
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          onPressed: _pickDateTime,
                          icon: const Icon(Icons.schedule, color: accent),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _dropdown(
                    label: _s.calculatorServiceLabel.of(_lang),
                    value: _service,
                    items: _services
                        .map(
                          (o) => DropdownMenuItem(
                            value: o.id,
                            child: _dropdownMenuItemContent(
                              icon: _serviceIcon(o.id),
                              label: _serviceLabel(o.id, o.labelFor(_lang)),
                            ),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (v) => setState(() => _service = v ?? 'airport'),
                  ),
                  const SizedBox(height: 9),
                  _dropdown(
                    label: _s.calculatorTierLabel.of(_lang),
                    value: _tier,
                    items: _tiers
                        .map(
                          (o) => DropdownMenuItem(
                            value: o.id,
                            child: _dropdownMenuItemContent(
                              icon: _tierIcon(o.id),
                              label: _tierLabel(o.id, o.labelFor(_lang)),
                            ),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (v) {
                      setState(() {
                        _tier = v ?? 'comfort';
                        if (!_isPremiumTier) _extraService = 'none';
                      });
                    },
                  ),
                  const SizedBox(height: 9),
                  if (_isPremiumTier)
                    _dropdown(
                      label: _s.calculatorExtraServiceOptionalLabel.of(_lang),
                      value: _extraService,
                      items: _extras
                          .map(
                            (o) => DropdownMenuItem(
                              value: o.id,
                              child: _dropdownMenuItemContent(
                                icon: _extraIcon(o.id),
                                label: _extraLabel(o.id, o.labelFor(_lang)),
                              ),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (v) =>
                          setState(() => _extraService = v ?? 'none'),
                    ),
                  if (_isPremiumTier) const SizedBox(height: 9),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _returnFeatureEnabled && _returnTrip,
                    onChanged: !_returnFeatureEnabled
                        ? null
                        : (v) => setState(() {
                            _returnTrip = v;
                            if (!v) _returnPickupDateTime = null;
                          }),
                    title: Text(
                      _returnTripLabel(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      _returnFeatureEnabled
                          ? _s.calculatorReturnSubtitle.of(_lang)
                          : _disabledReturnLabel(),
                      style: const TextStyle(color: Colors.white54),
                    ),
                    activeColor: accent,
                  ),
                  if (_returnFeatureEnabled && _returnTrip) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: _calcPanelColor.withOpacity(0.72),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.08),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${_returnTripLabel()} ${_s.calculatorPickupTimeLabel.of(_lang)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Flexible(
                            child: Text(
                              _returnPickupDateTime == null
                                  ? _s.calculatorChoosePickupTimeLabel.of(_lang)
                                  : '${_returnPickupDateTime!.day.toString().padLeft(2, '0')}-'
                                        '${_returnPickupDateTime!.month.toString().padLeft(2, '0')}-'
                                        '${_returnPickupDateTime!.year} '
                                        '${_returnPickupDateTime!.hour.toString().padLeft(2, '0')}:'
                                        '${_returnPickupDateTime!.minute.toString().padLeft(2, '0')}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12.5,
                              ),
                              textAlign: TextAlign.end,
                            ),
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            onPressed: _pickReturnDateTime,
                            icon: const Icon(Icons.schedule, color: accent),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 9),
                  _counterRow(
                    label: _s.calculatorWaitTimeLabel.of(_lang),
                    value: '$_waitMin',
                    hint: _s.calculatorWaitStepHint.of(_lang),
                    onMinus: _waitMin > 0
                        ? () => setState(
                            () => _waitMin = (_waitMin - 5).clamp(0, 9999),
                          )
                        : null,
                    onPlus: () => setState(
                      () => _waitMin = (_waitMin + 5).clamp(0, 9999),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _zoneCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GestureDetector(
                    onTap: _loading ? null : _calculate,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: accent.withOpacity(0.5)),
                        gradient: LinearGradient(
                          colors: [
                            accent.withOpacity(0.95),
                            const Color(0xFFB98722),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withOpacity(0.18),
                            blurRadius: 16,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _loading
                            ? _s.calculatorButtonBusyLabel.of(_lang)
                            : _s.calculatorButtonLabel.of(_lang),
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      '${_s.calculatorErrorPrefix.of(_lang)}: $_error',
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ],
                ],
              ),
            ),
            if (_lastQuote != null) ...[
              const SizedBox(height: 10),
              _zoneCard(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _quoteBox(_lastQuote!),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: _openBookingConfirmation,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: accent.withOpacity(0.55)),
                          color: Colors.black,
                          boxShadow: [
                            BoxShadow(
                              color: accent.withOpacity(0.12),
                              blurRadius: 14,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _s.calculatorBookNowLabel.of(_lang),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.arrow_forward_rounded,
                              color: Color(0xFFE5B641),
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _dropdown({
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          isExpanded: true,
          value: value,
          items: items,
          onChanged: onChanged,
          dropdownColor: _calcDropdownColor,
          decoration: InputDecoration(
            filled: true,
            fillColor: _calcPanelColor.withOpacity(0.72),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: const Color(0xFFE5B641).withOpacity(0.70),
                width: 1.1,
              ),
            ),
          ),
          style: const TextStyle(color: Colors.white),
        ),
      ],
    );
  }
}

class _PlaceSuggestion {
  const _PlaceSuggestion({required this.label, this.lon, this.lat});
  final String label;
  final double? lon;
  final double? lat;
}

class _BookingConfirmationPage extends StatefulWidget {
  const _BookingConfirmationPage({
    required this.bookingBaseUrl,
    required this.language,
    required this.strings,
    required this.quote,
    required this.payload,
    required this.currencySymbol,
    required this.distanceUnitLabel,
    required this.durationUnitLabel,
    required this.taxLabel,
  });

  final String bookingBaseUrl;
  final AppLanguage language;
  final AppStrings strings;
  final Map<String, dynamic> quote;
  final Map<String, dynamic> payload;
  final String currencySymbol;
  final String distanceUnitLabel;
  final String durationUnitLabel;
  final String taxLabel;

  @override
  State<_BookingConfirmationPage> createState() =>
      _BookingConfirmationPageState();
}

class _BookingConfirmationPageState extends State<_BookingConfirmationPage> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _companyNameCtrl = TextEditingController();
  final TextEditingController _vatNumberCtrl = TextEditingController();
  final TextEditingController _messageCtrl = TextEditingController();
  bool _submitting = false;
  String? _submitState;
  bool _submitStateIsError = false;
  Map<String, dynamic>? _finalPricing;
  String? _finalPricingBookingId;
  String? _createdBookingId;
  String? _ownPaymentBookingId;
  bool _paymentConfirmed = false;
  bool _postPaymentNavigated = false;

  @override
  void initState() {
    super.initState();
    fluxidiPendingPaymentNotifier.addListener(_onPendingPaymentChanged);
    unawaited(_prefillFromCustomerProfile());
  }

  Future<void> _prefillFromCustomerProfile() async {
    try {
      final profile = await CustomerProfileStore.instance.load();
      if (!mounted || profile == null) return;
      final explicitPrivateIntent = _hasExplicitPrivateBookingIntent(
        <String, dynamic>{...widget.payload, ...widget.quote},
      );
      void setIfBlank(TextEditingController controller, String value) {
        if (controller.text.trim().isNotEmpty) return;
        final incoming = value.trim();
        if (incoming.isEmpty) return;
        controller.text = incoming;
      }

      setIfBlank(_nameCtrl, profile.name);
      setIfBlank(_phoneCtrl, profile.phone);
      setIfBlank(_emailCtrl, profile.email);
      setIfBlank(_companyNameCtrl, profile.companyName);
      setIfBlank(_vatNumberCtrl, profile.vatNumber);
      debugPrint(
        '[CALCULATOR][BUSINESS_PREFILL] skipProfileBusiness=false explicitPrivateIntent=$explicitPrivateIntent companyPrefilled=${_companyNameCtrl.text.trim().isNotEmpty} vatPrefilled=${_vatNumberCtrl.text.trim().isNotEmpty}',
      );
    } catch (_) {
      // Keep booking flow resilient if local profile load fails.
    }
  }

  void _onPendingPaymentChanged() {
    final pending = fluxidiPendingPaymentNotifier.value;
    if (!mounted) return;
    final ownId = _ownPaymentBookingId;
    if (ownId == null || ownId.isEmpty) return;
    if (pending == null || pending.paymentBookingId != ownId) return;
    if (pending.status == FluxidiPaymentStatus.confirmed &&
        !_paymentConfirmed) {
      setState(() {
        _paymentConfirmed = true;
        _submitStateIsError = false;
        _submitState = [
          widget.strings.bookingSuccessPaidConfirmedMessage.of(widget.language),
          if ((_finalPricingBookingId ?? '').trim().isNotEmpty)
            '${widget.strings.bookingSuccessReferencePrefix.of(widget.language)}: ${_finalPricingBookingId!.trim()}',
        ].join('\n');
      });
      final bookingId = (_createdBookingId ?? _finalPricingBookingId ?? '')
          .trim();
      unawaited(
        CustomerBookingsStore.instance.markPaid(
          bookingId: bookingId,
          paymentBookingId: ownId,
        ),
      );
      if (!_postPaymentNavigated) {
        _postPaymentNavigated = true;
        final messenger = ScaffoldMessenger.maybeOf(context);
        Navigator.of(context).popUntil((route) => route.isFirst);
        final lang = widget.language;
        final confirmation = lang == AppLanguage.en
            ? 'Payment confirmed. Your booking is in My bookings.'
            : lang == AppLanguage.fr
            ? 'Paiement confirme. Votre reservation est disponible dans Mes reservations.'
            : lang == AppLanguage.es
            ? 'Pago confirmado. Tu reserva esta en Mis reservas.'
            : 'Betaling bevestigd. Je boeking staat bij Mijn boekingen.';
        messenger?.showSnackBar(SnackBar(content: Text(confirmation)));
      }
    }
  }

  double? _toNum(dynamic v) {
    if (v == null) return null;
    if (v is num) {
      final n = v.toDouble();
      return n.isFinite ? n : null;
    }
    var s = v.toString().trim();
    if (s.isEmpty) return null;
    s = s.replaceAll(RegExp(r'[^0-9,\.\-]'), '');
    if (s.contains(',') && !s.contains('.')) s = s.replaceAll(',', '.');
    if (s.contains(',') && s.contains('.')) s = s.replaceAll(',', '');
    final n = double.tryParse(s);
    if (n == null || !n.isFinite) return null;
    return n;
  }

  String _fmt(dynamic v, {int decimals = 2}) {
    final n = _toNum(v);
    if (n == null) return '—';
    return n.toStringAsFixed(decimals);
  }

  @override
  void dispose() {
    fluxidiPendingPaymentNotifier.removeListener(_onPendingPaymentChanged);
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _companyNameCtrl.dispose();
    _vatNumberCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  bool _isValidEmail(String value) {
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value);
  }

  String _fmtMoney(dynamic v) {
    final n = _toNum(v);
    if (n == null) return '—';
    return '${widget.currencySymbol} ${n.toStringAsFixed(2)}';
  }

  String _fmtVatPercent(dynamic v) {
    final n = _toNum(v);
    if (n == null) return '—';
    final pct = n <= 1 ? n * 100 : n;
    final rounded = pct.roundToDouble();
    return '${(pct == rounded ? rounded.toStringAsFixed(0) : pct.toStringAsFixed(2))}%';
  }

  String _friendlyBookingError(String raw) {
    final s = raw.trim().toLowerCase();
    if (s.contains('geen geschikt voertuig beschikbaar') ||
        s.contains('no suitable vehicle') ||
        s.contains('vehicle_capacity_exceeded')) {
      if (widget.language == AppLanguage.en) {
        return 'No vehicles are available at this time.';
      }
      if (widget.language == AppLanguage.fr) {
        return 'Aucun vehicule disponible a cet horaire.';
      }
      if (widget.language == AppLanguage.es) {
        return 'No hay vehiculos disponibles en este horario.';
      }
      return 'Geen voertuig meer beschikbaar op dit tijdstip.';
    }
    if (s.contains('token has been expired or revoked') ||
        s.contains('invalid_grant') ||
        s.contains('google access token') ||
        s.contains('failed to refresh google') ||
        s.contains('unauthorized_client') ||
        s.contains('oauth')) {
      if (widget.language == AppLanguage.en) {
        return 'Booking could not be completed due to a temporary connection issue. Please try again or contact the company.';
      }
      if (widget.language == AppLanguage.fr) {
        return 'La reservation n a pas pu etre finalisee en raison d un probleme de connexion temporaire. Reessayez ou contactez l entreprise.';
      }
      if (widget.language == AppLanguage.es) {
        return 'La reserva no pudo completarse por un problema temporal de conexion. Intentalo de nuevo o contacta con la empresa.';
      }
      return 'Boeking kon niet worden afgerond door een tijdelijke koppeling. Probeer opnieuw of contacteer het bedrijf.';
    }
    return raw;
  }

  bool _isCustomerSafeCheckoutUrl(String value) {
    final url = value.trim();
    if (url.isEmpty) return false;
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) return false;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    if (host.contains('workers.dev') ||
        host.contains('localhost') ||
        host.contains('127.0.0.1')) {
      return false;
    }
    return true;
  }

  Future<void> _copyPaymentLink(String paymentUrl, {String? message}) async {
    await Clipboard.setData(ClipboardData(text: paymentUrl));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message ??
              widget.strings.bookingPaymentLinkCopiedMessage.of(
                widget.language,
              ),
        ),
      ),
    );
  }

  Future<void> _openPaymentUrl(String paymentUrl) async {
    final uri = Uri.tryParse(paymentUrl);
    final opened =
        uri != null &&
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      await _copyPaymentLink(
        paymentUrl,
        message: widget.strings.bookingPaymentOpenFailedCopiedMessage.of(
          widget.language,
        ),
      );
    }
  }

  Future<void> _showBookingSuccessDialog({
    required bool requiresPayment,
    required String paymentUrl,
    required String? publicRef,
  }) async {
    final safePaymentUrl = _isCustomerSafeCheckoutUrl(paymentUrl)
        ? paymentUrl.trim()
        : '';
    final hasPaymentUrl = safePaymentUrl.isNotEmpty;
    final title = requiresPayment
        ? widget.strings.bookingPaymentSuccessTitle.of(widget.language)
        : widget.strings.bookingSuccessCashMessage.of(widget.language);
    final message = requiresPayment
        ? widget.strings.bookingPaymentRequiredMessage.of(widget.language)
        : widget.strings.bookingSuccessCashMessage.of(widget.language);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF141B2F),
          title: Text(title, style: const TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message, style: const TextStyle(color: Colors.white70)),
              if ((publicRef ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  '${widget.strings.bookingSuccessReferencePrefix.of(widget.language)}: ${publicRef!.trim()}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            if (hasPaymentUrl)
              TextButton(
                onPressed: () => _copyPaymentLink(safePaymentUrl),
                child: Text(
                  widget.strings.bookingCopyPaymentLinkLabel.of(
                    widget.language,
                  ),
                ),
              ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(widget.strings.bookingCloseLabel.of(widget.language)),
            ),
            if (hasPaymentUrl)
              FilledButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _openPaymentUrl(safePaymentUrl);
                },
                child: Text(
                  widget.strings.bookingPayNowLabel.of(widget.language),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<Map<String, dynamic>?> _fetchFinalAuthoritativePricing(
    String bookingId,
  ) async {
    try {
      final url = Uri.parse('${widget.bookingBaseUrl}/tracking/booking');
      final res = await http.post(
        url,
        headers: const {'content-type': 'application/json'},
        body: jsonEncode(<String, dynamic>{'booking_id': bookingId}),
      );
      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      final decoded = jsonDecode(res.body);
      if (decoded is! Map) return null;
      final body = Map<String, dynamic>.from(decoded);
      if (body['ok'] != true) return null;
      final Object? quoteRaw = body['quote'];
      if (quoteRaw is! Map<dynamic, dynamic>) return null;
      final Map<String, dynamic> quote = Map<String, dynamic>.from(quoteRaw);
      final Object? pricingRaw = quote['pricing'];
      if (pricingRaw is! Map<dynamic, dynamic>) return null;
      final Map<String, dynamic> pricing = Map<String, dynamic>.from(
        pricingRaw,
      );
      return <String, dynamic>{
        'booking_id': bookingId,
        'price_ex_vat': pricing['price_ex_vat'],
        'price_vat': pricing['price_vat'],
        'price_incl_vat': pricing['price_incl_vat'],
        'distance_km': quote['distance_km'],
        'duration_min': quote['duration_min'],
      };
    } catch (_) {
      return null;
    }
  }

  Future<void> _onConfirmBooking() async {
    FocusScope.of(context).unfocus();
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final companyName = _companyNameCtrl.text.trim();
    final vatNumber = _vatNumberCtrl.text.trim();
    final invoiceAddressFromQuote = _calcBusinessText(
      widget.payload['invoice_address'] ??
          widget.payload['invoiceAddress'] ??
          widget.quote['invoice_address'] ??
          widget.quote['invoiceAddress'],
    );
    final businessPayload = _buildBusinessInvoicePayload(
      source: <String, dynamic>{
        ...widget.payload,
        ...widget.quote,
        'company_name': companyName,
        'companyName': companyName,
        'vat_number': vatNumber,
        'vatNumber': vatNumber,
        'customer_company_name': companyName,
        'customerCompanyName': companyName,
        'customer_vat_number': vatNumber,
        'customerVatNumber': vatNumber,
      },
      overrideCompanyName: companyName,
      overrideVatNumber: vatNumber,
      overrideInvoiceEmail: email,
      overrideInvoiceAddress: invoiceAddressFromQuote,
    );
    final effectiveCompanyName = _calcBusinessText(
      businessPayload['company_name'] ?? businessPayload['companyName'],
    );
    final effectiveVatNumber = _calcBusinessText(
      businessPayload['vat_number'] ?? businessPayload['vatNumber'],
    );
    final effectiveInvoiceEmail = _calcBusinessText(
      businessPayload['invoice_email'] ?? businessPayload['invoiceEmail'],
    );
    final effectiveInvoiceAddress = _calcBusinessText(
      businessPayload['invoice_address'] ?? businessPayload['invoiceAddress'],
    );
    final localCompanyId = companyProfileNotifier.value?.companyId.trim() ?? '';
    final resolvedCompany = resolvedCompanyId.trim();
    final tenantCompanyId = localCompanyId.isNotEmpty
        ? localCompanyId
        : (resolvedCompany.isNotEmpty ? resolvedCompany : kTenantId);
    if (name.isEmpty ||
        phone.isEmpty ||
        email.isEmpty ||
        !_isValidEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.strings.bookingRequiredFieldsError.of(widget.language),
          ),
        ),
      );
      return;
    }

    final payload = <String, dynamic>{
      ...widget.payload, // keep quote payload keys unchanged
      'tenant_id': tenantCompanyId,
      'company_id': tenantCompanyId,
      'booking_source': 'flutter_app',
      'entry_channel': 'flutter_calculator',
      'source_context': <String, dynamic>{
        'role': 'customer_or_app',
        'language': widget.language.name,
        'surface': 'calculator_confirmation',
      },
      // Keep website-compatible aliases
      'return_enabled': (widget.payload['return'] ?? false) == true,
      'extra_service_key': widget.payload['extra_service'] ?? 'NONE',
      // Mollie return-to-app deep link. The Worker uses this to redirect the
      // browser back into the Fluxidi app after a successful payment.
      'return_url': kFluxidiPaymentReturnUrl,
      'customer': <String, dynamic>{
        'name': name,
        'full_name': name,
        'phone': phone,
        'email': email,
        'companyName': effectiveCompanyName,
        'vatNumber': effectiveVatNumber,
        'company_name': effectiveCompanyName,
        'vat_number': effectiveVatNumber,
        'invoice_email': effectiveInvoiceEmail,
        'invoiceEmail': effectiveInvoiceEmail,
        'invoice_address': effectiveInvoiceAddress,
        'invoiceAddress': effectiveInvoiceAddress,
        'business_detected': businessPayload['business_detected'],
        'businessDetected': businessPayload['businessDetected'],
        'invoice_requested': businessPayload['invoice_requested'],
        'invoiceRequested': businessPayload['invoiceRequested'],
        'message': _messageCtrl.text.trim(),
      },
      'name': name,
      'phone': phone,
      'email': email,
      'customer_name': name,
      'customer_phone': phone,
      'customer_email': email,
      'customer_company_name': effectiveCompanyName,
      'customer_vat_number': effectiveVatNumber,
      'customerCompanyName': effectiveCompanyName,
      'customerVatNumber': effectiveVatNumber,
      'companyName': effectiveCompanyName,
      'vatNumber': effectiveVatNumber,
      'billing_company_name': effectiveCompanyName,
      'billing_vat_number': effectiveVatNumber,
      'company_name': effectiveCompanyName,
      'vat_number': effectiveVatNumber,
      ...businessPayload,
      'message': _messageCtrl.text.trim(),
      // Website contract includes full quote object under "quote"
      'quote': widget.quote,
    };

    setState(() {
      _submitting = true;
      _submitState = widget.strings.bookingSubmittingLabel.of(widget.language);
      _submitStateIsError = false;
      _finalPricing = null;
      _finalPricingBookingId = null;
    });

    try {
      final url = Uri.parse('${widget.bookingBaseUrl}/book');
      _logBusinessPayload(stage: 'book', payload: payload);
      final res = await http.post(
        url,
        headers: const {'content-type': 'application/json'},
        body: jsonEncode(payload),
      );

      final rawText = res.body;
      Map<String, dynamic> body = <String, dynamic>{};
      if (rawText.trim().isNotEmpty) {
        final decoded = jsonDecode(rawText);
        if (decoded is Map<String, dynamic>) {
          body = decoded;
        } else if (decoded is Map) {
          body = Map<String, dynamic>.from(decoded);
        }
      }

      final ok =
          res.statusCode >= 200 &&
          res.statusCode < 300 &&
          (body['ok'] == null || body['ok'] == true);
      if (!ok) {
        final err =
            (body['error'] ?? body['message'] ?? 'HTTP ${res.statusCode}')
                .toString();
        throw Exception(err);
      }

      final bookingRef =
          (body['bookingId'] ??
                  body['booking_id'] ??
                  (body['booking'] is Map
                      ? (body['booking']['bookingId'] ??
                            body['booking']['booking_id'])
                      : null) ??
                  '')
              .toString();
      final publicRefRaw =
          (body['public_reference'] ??
                  body['publicReference'] ??
                  body['customer_reference'] ??
                  body['customerReference'] ??
                  body['receipt_number'] ??
                  body['receiptNumber'] ??
                  (body['booking'] is Map
                      ? (body['booking']['public_reference'] ??
                            body['booking']['publicReference'] ??
                            body['booking']['customer_reference'] ??
                            body['booking']['customerReference'] ??
                            body['booking']['receipt_number'] ??
                            body['booking']['receiptNumber'])
                      : null) ??
                  '')
              .toString()
              .trim();
      // Fallback: many /book responses only return booking_id / bookingId.
      // Use that as the customer-facing reference when no dedicated public
      // reference field is set.
      final publicRef = publicRefRaw.isNotEmpty
          ? publicRefRaw
          : bookingRef.trim();
      final requiresPayment =
          (body['requiresPayment'] == true || body['payment_required'] == true);
      final checkoutUrl =
          (body['checkoutUrl'] ??
                  body['paymentUrl'] ??
                  body['payment_url'] ??
                  '')
              .toString()
              .trim();
      final safeCheckoutUrl = _isCustomerSafeCheckoutUrl(checkoutUrl)
          ? checkoutUrl
          : '';
      final paymentFlow = requiresPayment || safeCheckoutUrl.isNotEmpty;
      final paymentBookingId =
          (body['paymentBookingId'] ??
                  body['payment_booking_id'] ??
                  (body['booking'] is Map
                      ? (body['booking']['paymentBookingId'] ??
                            body['booking']['payment_booking_id'])
                      : null) ??
                  '')
              .toString()
              .trim();
      // Register the pending payment so deep link / lifecycle handlers in
      // _DriverHomePageState can reconcile via /pay/status when the user
      // returns from Mollie checkout.
      if (paymentFlow && paymentBookingId.isNotEmpty) {
        _ownPaymentBookingId = paymentBookingId;
        _paymentConfirmed = false;
        setFluxidiPendingPayment(
          paymentBookingId: paymentBookingId,
          publicBookingId: publicRef.isNotEmpty ? publicRef : null,
        );
      }
      final storedBooking =
          StoredCustomerBooking.fromBookSuccess(
            response: body,
            requestPayload: payload,
            customerName: name,
            customerPhone: phone,
            customerEmail: email,
          ).copyWith(
            bookingId: bookingRef.isNotEmpty ? bookingRef : publicRef,
            publicBookingId: publicRef,
            paymentBookingId: paymentBookingId,
            paymentStatus: paymentFlow
                ? (paymentBookingId.isNotEmpty ? 'pending' : 'unpaid')
                : 'unpaid',
            status: paymentFlow ? 'PENDING' : 'CONFIRMED',
            companyName: effectiveCompanyName,
            vatNumber: effectiveVatNumber,
            invoiceEmail: effectiveInvoiceEmail,
            invoiceAddress: effectiveInvoiceAddress,
            businessDetected:
                businessPayload['business_detected'] == true ||
                businessPayload['businessDetected'] == true,
            invoiceRequested:
                businessPayload['invoice_requested'] == true ||
                businessPayload['invoiceRequested'] == true,
          );
      await CustomerBookingsStore.instance.upsert(storedBooking);
      final localBookingId = (bookingRef.isNotEmpty ? bookingRef : publicRef)
          .trim();
      if (localBookingId.isEmpty) {
        debugPrint('[CUSTOMER_BOOKINGS][SAVE][SKIP] reason=missing_booking_id');
      } else {
        debugPrint('[CUSTOMER_BOOKINGS][SAVE][OK] booking=$localBookingId');
      }
      final finalPricing = bookingRef.isNotEmpty
          ? await _fetchFinalAuthoritativePricing(bookingRef)
          : null;

      final successMessage = [
        paymentFlow
            ? widget.strings.bookingSuccessPaymentRequiredMessage.of(
                widget.language,
              )
            : widget.strings.bookingSuccessCashMessage.of(widget.language),
        if (publicRef.isNotEmpty)
          '${widget.strings.bookingSuccessReferencePrefix.of(widget.language)}: $publicRef',
      ].join('\n');

      if (!mounted) return;
      setState(() {
        _submitState = successMessage;
        _submitStateIsError = false;
        _finalPricing = finalPricing;
        _finalPricingBookingId = publicRef.isNotEmpty ? publicRef : null;
        _createdBookingId = bookingRef.isNotEmpty ? bookingRef : publicRef;
      });
      if (safeCheckoutUrl.isNotEmpty) {
        await _showBookingSuccessDialog(
          requiresPayment: true,
          paymentUrl: safeCheckoutUrl,
          publicRef: publicRef,
        );
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(successMessage)));
      }
    } catch (e) {
      if (!mounted) return;
      final rawErr = e.toString().replaceFirst('Exception: ', '').trim();
      final friendlyErr = _friendlyBookingError(rawErr);
      final msg =
          '${widget.strings.bookingSubmitFailedPrefix.of(widget.language)}: $friendlyErr';
      setState(() {
        _submitState = msg;
        _submitStateIsError = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (!mounted) return;
      setState(() {
        _submitting = false;
      });
    }
  }

  String _optionLabelForPayloadValue(
    List<AppOption> options,
    String payloadValue,
  ) {
    for (final o in options) {
      if (o.payloadValue == payloadValue) return o.labelFor(widget.language);
    }
    return payloadValue;
  }

  @override
  Widget build(BuildContext context) {
    final effectiveQuote = <String, dynamic>{
      ...widget.quote,
      if (_finalPricing != null) ..._finalPricing!,
    };
    final ret = effectiveQuote['return'] is Map
        ? Map<String, dynamic>.from(effectiveQuote['return'] as Map)
        : <String, dynamic>{};
    final mainEx = _toNum(effectiveQuote['price_ex_vat']) ?? 0.0;
    final mainVat = _toNum(effectiveQuote['price_vat']) ?? 0.0;
    final mainIncl = _toNum(effectiveQuote['price_incl_vat']) ?? 0.0;
    final retEx = _toNum(ret['price_ex_vat']) ?? 0.0;
    final retVat = _toNum(ret['price_vat']) ?? 0.0;
    final retIncl = _toNum(ret['price_incl_vat']) ?? 0.0;
    final totalEx =
        _toNum(effectiveQuote['total_price_ex_vat']) ?? (mainEx + retEx);
    final taxAmount =
        _toNum(effectiveQuote['total_price_vat']) ?? (mainVat + retVat);
    final totalIncl =
        _toNum(effectiveQuote['total_price_incl_vat']) ?? (mainIncl + retIncl);
    final vatRate =
        effectiveQuote['vat_rate'] ??
        (effectiveQuote['breakdown'] is Map
            ? (effectiveQuote['breakdown'] as Map)['vat_rate']
            : null);
    final distanceKm =
        effectiveQuote['distance_km'] ??
        (((effectiveQuote['distance_m'] ?? effectiveQuote['distanceMeters'])
                is num)
            ? ((effectiveQuote['distance_m'] ??
                          effectiveQuote['distanceMeters'])
                      as num) /
                  1000
            : null);
    final durationMin =
        effectiveQuote['duration_min'] ??
        (((effectiveQuote['duration_s'] ?? effectiveQuote['durationSec'])
                is num)
            ? ((effectiveQuote['duration_s'] ?? effectiveQuote['durationSec'])
                      as num) /
                  60
            : null);

    final from = (widget.payload['from'] ?? '').toString();
    final to = (widget.payload['to'] ?? '').toString();
    final date = (widget.payload['date'] ?? '').toString();
    final time = (widget.payload['time'] ?? '').toString();
    final service = (widget.payload['service'] ?? '').toString();
    final tier = (widget.payload['tier'] ?? '').toString();
    final pax = (widget.payload['pax'] ?? '').toString();
    final bags = (widget.payload['bags'] ?? '').toString();
    final waitMin = (widget.payload['wait_min'] ?? '').toString();
    final returnTrip = (widget.payload['return'] ?? false) == true;
    final waitDisplayMin = _toNum(waitMin) ?? 0.0;
    final retMetrics = effectiveQuote['return'] is Map
        ? Map<String, dynamic>.from(effectiveQuote['return'] as Map)
        : <String, dynamic>{};
    final returnDistanceKm =
        retMetrics['distance_km'] ??
        (((retMetrics['distance_m'] ?? retMetrics['distanceMeters']) is num)
            ? ((retMetrics['distance_m'] ?? retMetrics['distanceMeters'])
                      as num) /
                  1000
            : null);
    final returnDurationMin =
        retMetrics['duration_min'] ??
        (((retMetrics['duration_s'] ?? retMetrics['durationSec']) is num)
            ? ((retMetrics['duration_s'] ?? retMetrics['durationSec']) as num) /
                  60
            : null);
    final baseDistance = _toNum(distanceKm);
    final baseDuration = _toNum(durationMin);
    final totalDisplayDistance = baseDistance == null
        ? null
        : baseDistance +
              (returnTrip ? (_toNum(returnDistanceKm) ?? baseDistance) : 0.0);
    final totalDisplayDuration = baseDuration == null
        ? null
        : baseDuration +
              (returnTrip ? (_toNum(returnDurationMin) ?? baseDuration) : 0.0) +
              waitDisplayMin;
    final showTotalMetrics = returnTrip || waitDisplayMin > 0;
    final distanceLabel = showTotalMetrics
        ? _localizedText(
            nl: 'Afstand totaal',
            en: 'Total distance',
            fr: 'Distance totale',
            es: 'Distancia total',
          )
        : widget.strings.calculatorDistanceLabel.of(widget.language);
    final durationLabel = showTotalMetrics
        ? _localizedText(
            nl: 'Tijd totaal',
            en: 'Total time',
            fr: 'Temps total',
            es: 'Tiempo total',
          )
        : widget.strings.calculatorDurationLabel.of(widget.language);
    final extraService = (widget.payload['extra_service'] ?? 'NONE').toString();
    final serviceLabel = _optionLabelForPayloadValue(
      appConfig.enabledServices,
      service,
    );
    final tierLabel = _optionLabelForPayloadValue(appConfig.enabledTiers, tier);
    final extraServiceLabel = _optionLabelForPayloadValue(
      appConfig.enabledExtraOptions,
      extraService,
    );
    final compactExtraServiceLabel = _compactExtraServiceLabel(
      value: extraService,
      fallbackLabel: extraServiceLabel,
    );

    return Scaffold(
      backgroundColor: appConfig.branding.calculatorScaffoldColor,
      appBar: AppBar(
        backgroundColor: appConfig.branding.calculatorScaffoldColor,
        title: Text(
          widget.strings.bookingConfirmationTitle.of(widget.language),
          style: const TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
        children: [
          _sectionCard(
            title: widget.strings.bookingSummaryRouteLabel.of(widget.language),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.place_outlined,
                      size: 16,
                      color: Color(0xFFE5B641),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        from,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 2, top: 2, bottom: 2),
                  child: Icon(
                    Icons.south_rounded,
                    size: 14,
                    color: Colors.white.withOpacity(0.5),
                  ),
                ),
                Row(
                  children: [
                    const Icon(
                      Icons.flag_outlined,
                      size: 16,
                      color: Color(0xFFE5B641),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        to,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _confirmationChip(
                      icon: Icons.miscellaneous_services_outlined,
                      text: serviceLabel,
                    ),
                    _confirmationChip(
                      icon: Icons.workspace_premium_outlined,
                      text: tierLabel,
                    ),
                    _confirmationChip(
                      icon: Icons.groups_2_outlined,
                      text: 'PAX $pax',
                    ),
                    _confirmationChip(
                      icon: Icons.luggage_outlined,
                      text: 'BAG $bags',
                    ),
                    if (returnTrip)
                      _confirmationChip(
                        icon: Icons.compare_arrows_outlined,
                        text: _yesLabel(),
                      ),
                    if (waitMin.trim().isNotEmpty && waitMin.trim() != '0')
                      _confirmationChip(
                        icon: Icons.schedule_outlined,
                        text: '$waitMin min',
                      ),
                    if (compactExtraServiceLabel.trim().isNotEmpty &&
                        extraService.trim().toUpperCase() != 'NONE')
                      _confirmationChip(
                        icon: Icons.stars_outlined,
                        text: compactExtraServiceLabel,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 9),
          _sectionCard(
            title: widget.strings.bookingSummaryPickupLabel.of(widget.language),
            child: Text(
              '$date  $time',
              style: const TextStyle(color: Colors.white),
            ),
          ),
          const SizedBox(height: 9),
          if (returnTrip) ...[
            _sectionCard(
              title: widget.strings.bookingSummaryReturnLabel.of(
                widget.language,
              ),
              child: Text(
                widget.strings.commonYesLabel.of(widget.language),
                style: const TextStyle(color: Colors.white),
              ),
            ),
            const SizedBox(height: 9),
          ],
          if (waitMin.trim().isNotEmpty && waitMin.trim() != '0') ...[
            _sectionCard(
              title: widget.strings.bookingSummaryWaitTimeLabel.of(
                widget.language,
              ),
              child: Text(
                '$waitMin min',
                style: const TextStyle(color: Colors.white),
              ),
            ),
            const SizedBox(height: 9),
          ],
          if (compactExtraServiceLabel.trim().isNotEmpty &&
              extraService.trim().toUpperCase() != 'NONE') ...[
            _sectionCard(
              title: 'Extra service',
              child: Text(
                compactExtraServiceLabel,
                style: const TextStyle(color: Colors.white),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 9),
          ],
          _sectionCard(
            title: widget.strings.bookingSummaryQuoteLabel.of(widget.language),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _confirmationRow(
                  widget.strings.calculatorPriceExVatLabel.of(widget.language),
                  '${widget.currencySymbol} ${_fmt(totalEx)}',
                ),
                _confirmationRow(
                  widget.taxLabel,
                  '${widget.currencySymbol} ${_fmt(taxAmount)}',
                ),
                if (_fmtVatPercent(vatRate) != '—')
                  _confirmationRow(
                    _localizedText(
                      nl: 'Btw-tarief',
                      en: 'VAT rate',
                      fr: 'Taux TVA',
                      es: 'Tasa IVA',
                    ),
                    _fmtVatPercent(vatRate),
                  ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          distanceLabel,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${_fmt(showTotalMetrics ? totalDisplayDistance : distanceKm, decimals: 2)} ${widget.distanceUnitLabel}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          durationLabel,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${_fmt(showTotalMetrics ? totalDisplayDuration : durationMin, decimals: 0)} ${widget.durationUnitLabel}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _localizedText(
                            nl: 'Totaalprijs',
                            en: 'Total price',
                            fr: 'Prix total',
                            es: 'Precio total',
                          ),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                      Text(
                        '${widget.currencySymbol} ${_fmt(totalIncl)}',
                        style: const TextStyle(
                          color: Color(0xFFE5B641),
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.verified_outlined,
                      size: 14,
                      color: Colors.white.withOpacity(0.70),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _localizedText(
                          nl: 'Inclusief btw  •  Geen verborgen kosten',
                          en: 'VAT included  •  No hidden costs',
                          fr: 'TVA incluse  •  Aucun frais cache',
                          es: 'IVA incluido  •  Sin costes ocultos',
                        ),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.66),
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 9),
          _sectionCard(
            title: widget.strings.bookingCustomerSectionTitle.of(
              widget.language,
            ),
            child: Column(
              children: [
                _input(
                  _nameCtrl,
                  widget.strings.bookingFullNameLabel.of(widget.language),
                  icon: Icons.person_outline,
                ),
                const SizedBox(height: 8),
                _input(
                  _phoneCtrl,
                  widget.strings.bookingPhoneLabel.of(widget.language),
                  keyboardType: TextInputType.phone,
                  icon: Icons.phone_outlined,
                ),
                const SizedBox(height: 8),
                _input(
                  _emailCtrl,
                  widget.strings.bookingEmailLabel.of(widget.language),
                  keyboardType: TextInputType.emailAddress,
                  icon: Icons.alternate_email,
                ),
                const SizedBox(height: 8),
                _input(
                  _companyNameCtrl,
                  widget.strings.bookingCompanyNameOptionalLabel.of(
                    widget.language,
                  ),
                  icon: Icons.business_outlined,
                ),
                const SizedBox(height: 8),
                _input(
                  _vatNumberCtrl,
                  widget.strings.bookingVatNumberOptionalLabel.of(
                    widget.language,
                  ),
                  icon: Icons.receipt_long_outlined,
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.strings.bookingVatNumberHelpText.of(widget.language),
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 8),
                _input(
                  _messageCtrl,
                  widget.strings.bookingMessageOptionalLabel.of(
                    widget.language,
                  ),
                  maxLines: 3,
                  icon: Icons.message_outlined,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _submitting ? null : _onConfirmBooking,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFFE5B641).withOpacity(0.5),
                ),
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFE5B641).withOpacity(0.95),
                    const Color(0xFFB98722),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE5B641).withOpacity(0.18),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _submitting
                        ? widget.strings.bookingSubmittingLabel.of(
                            widget.language,
                          )
                        : widget.strings.bookingConfirmButtonLabel.of(
                            widget.language,
                          ),
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: Colors.black,
                  ),
                ],
              ),
            ),
          ),
          if (_submitState != null) ...[
            const SizedBox(height: 10),
            Text(
              _submitState!,
              style: TextStyle(
                color: _submitStateIsError
                    ? Colors.redAccent
                    : Colors.greenAccent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (_finalPricing != null) ...[
            const SizedBox(height: 9),
            _sectionCard(
              title:
                  '${widget.strings.bookingSummaryQuoteLabel.of(widget.language)} (final)',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((_finalPricingBookingId ?? '').isNotEmpty)
                    Text(
                      '${widget.strings.bookingSuccessReferencePrefix.of(widget.language)}: $_finalPricingBookingId',
                      style: const TextStyle(color: Colors.white),
                    ),
                  const SizedBox(height: 6),
                  _confirmationRow(
                    widget.strings.calculatorPriceInclVatLabel.of(
                      widget.language,
                    ),
                    _fmtMoney(_finalPricing!['price_incl_vat']),
                    emphasizeValue: true,
                  ),
                  _confirmationRow(
                    widget.strings.calculatorPriceExVatLabel.of(
                      widget.language,
                    ),
                    _fmtMoney(_finalPricing!['price_ex_vat']),
                  ),
                  _confirmationRow(
                    widget.taxLabel,
                    _fmtMoney(_finalPricing!['price_vat']),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
      decoration: BoxDecoration(
        color: appConfig.branding.calculatorPanelColor.withOpacity(0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5B641).withOpacity(0.35)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE5B641).withOpacity(0.08),
            blurRadius: 18,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: Colors.white.withOpacity(0.92),
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 7),
          child,
        ],
      ),
    );
  }

  Widget _confirmationChip({required IconData icon, required String text}) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.28),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: const Color(0xFFE5B641)),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _confirmationRow(
    String label,
    String value, {
    bool emphasizeValue = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: emphasizeValue ? const Color(0xFFE5B641) : Colors.white,
                fontSize: emphasizeValue ? 13 : 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _compactExtraServiceLabel({
    required String value,
    required String fallbackLabel,
  }) {
    switch (value.trim().toLowerCase()) {
      case 'none':
      case 'no_extra':
        return _localizedText(
          nl: 'Geen extra service',
          en: 'No extra service',
          fr: 'Aucun service supplémentaire',
          es: 'Sin servicio extra',
        );
      case 'drinks':
        return _localizedText(
          nl: 'Drankservice',
          en: 'Drinks service',
          fr: 'Service boissons',
          es: 'Servicio de bebidas',
        );
      case 'work_table':
      case 'worktable':
        return _localizedText(
          nl: 'Werktafel',
          en: 'Work table',
          fr: 'Table de travail',
          es: 'Mesa de trabajo',
        );
      default:
        return fallbackLabel;
    }
  }

  String _yesLabel() {
    return widget.strings.commonYesLabel.of(widget.language);
  }

  String _localizedText({
    required String nl,
    required String en,
    required String fr,
    required String es,
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
    }
  }

  Widget _input(
    TextEditingController ctrl,
    String label, {
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    IconData? icon,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: label,
        hintStyle: const TextStyle(color: Colors.white54),
        prefixIcon: icon == null
            ? null
            : Icon(icon, size: 18, color: const Color(0xFFE5B641)),
        filled: true,
        fillColor: appConfig.branding.calculatorScaffoldColor.withOpacity(0.82),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: const Color(0xFFE5B641).withOpacity(0.70),
            width: 1.1,
          ),
        ),
      ),
    );
  }
}
