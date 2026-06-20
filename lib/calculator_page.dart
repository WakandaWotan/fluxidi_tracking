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

import 'package:flutter/foundation.dart' show ValueListenable, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/customer_theme_store.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';
import 'package:fluxidi_tracking/driver_theme_store.dart';
import 'package:fluxidi_tracking/company_session_store.dart';
import 'package:fluxidi_tracking/customer_bookings_store.dart';
import 'package:fluxidi_tracking/customer_profile_store.dart';
import 'package:fluxidi_tracking/customer_session_store.dart';
import 'package:fluxidi_tracking/driver_session_store.dart';
import 'package:fluxidi_tracking/effective_tenant_company_scope.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:fluxidi_tracking/payment/payment_booking_selection.dart';
import 'package:fluxidi_tracking/payment/payment_method_catalog.dart';
import 'package:fluxidi_tracking/payment/payment_method_resolver.dart';
import 'package:fluxidi_tracking/payment/payment_qr_panel.dart';
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

String _availabilityReasonCodeFromMap(Map<String, dynamic>? availability) {
  if (availability == null) return '';
  final candidates = <dynamic>[
    availability['block_reason'],
    availability['blockReason'],
    availability['reason_code'],
    availability['reasonCode'],
    availability['reason'],
  ];
  for (final value in candidates) {
    final normalized = (value?.toString().trim().toLowerCase() ?? '');
    if (normalized.isNotEmpty) return normalized;
  }
  return '';
}

bool _isDemandIndexTechnicalAvailabilityReason(String reasonCode) {
  switch (reasonCode.trim().toLowerCase()) {
    case 'demand_index_stale':
    case 'demand_index_unavailable':
    case 'demand_index_invalid':
      return true;
    default:
      return false;
  }
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

class _CalculatorScopeSelection {
  const _CalculatorScopeSelection({
    required this.tenantId,
    required this.companyId,
    required this.source,
    required this.isMissing,
    this.driverId,
    this.assignedVehicleId,
  });

  final String tenantId;
  final String companyId;
  final String source;
  final bool isMissing;

  /// Chauffeur ownership fields, only set for driver-entry scope selection.
  final String? driverId;
  final String? assignedVehicleId;
}

enum BookingEntryContext { customer, companyAdmin, driver }

@immutable
class _CalculatorVisualTheme {
  const _CalculatorVisualTheme({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.textPrimary,
    required this.textMuted,
    required this.accent,
    required this.bronze,
    required this.border,
    required this.danger,
    required this.success,
    required this.shadow,
    required this.isDark,
  });

  factory _CalculatorVisualTheme.fromCustomer(CustomerThemePalette palette) {
    return _CalculatorVisualTheme(
      background: palette.background,
      surface: palette.surface,
      surfaceAlt: palette.surfaceAlt,
      textPrimary: palette.textPrimary,
      textMuted: palette.textMuted,
      accent: palette.gold,
      bronze: palette.bronze,
      border: palette.border,
      danger: palette.danger,
      success: palette.success,
      shadow: palette.shadow,
      isDark: palette.isDark,
    );
  }

  factory _CalculatorVisualTheme.fromDriver(DriverThemePalette palette) {
    return _CalculatorVisualTheme(
      background: palette.background,
      surface: palette.surface,
      surfaceAlt: palette.surfaceAlt,
      textPrimary: palette.textPrimary,
      textMuted: palette.textMuted,
      // Driver accent should drive calculator accent in driver context.
      accent: palette.accent,
      bronze: Color.alphaBlend(
        palette.accent.withOpacity(0.72),
        palette.surfaceAlt,
      ),
      border: palette.border,
      danger: palette.danger,
      success: palette.success,
      shadow: palette.shadow,
      isDark: palette.isDark,
    );
  }

  factory _CalculatorVisualTheme.fromBusiness(BusinessThemePalette palette) {
    return _CalculatorVisualTheme(
      background: palette.background,
      surface: palette.surface,
      surfaceAlt: palette.surfaceAlt,
      textPrimary: palette.textPrimary,
      textMuted: palette.textMuted,
      accent: palette.accent,
      bronze: Color.alphaBlend(
        palette.accent.withOpacity(0.72),
        palette.surfaceAlt,
      ),
      border: palette.border,
      danger: palette.danger,
      success: palette.success,
      shadow: palette.shadow,
      isDark: palette.isDark,
    );
  }

  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color textPrimary;
  final Color textMuted;
  final Color accent;
  final Color bronze;
  final Color border;
  final Color danger;
  final Color success;
  final Color shadow;
  final bool isDark;
}

_CalculatorVisualTheme _calculatorVisualThemeForContext(
  BookingEntryContext entryContext,
  ValueListenable<DriverThemeVariant> driverThemeListenable,
) {
  if (entryContext == BookingEntryContext.driver) {
    return _CalculatorVisualTheme.fromDriver(
      paletteForDriverTheme(driverThemeListenable.value),
    );
  }
  if (entryContext == BookingEntryContext.companyAdmin) {
    return _CalculatorVisualTheme.fromBusiness(
      paletteForBusinessTheme(businessThemeNotifier.value),
    );
  }
  return _CalculatorVisualTheme.fromCustomer(
    paletteForCustomerTheme(customerThemeNotifier.value),
  );
}

String _maskCalculatorScopeId(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '-';
  if (trimmed.length <= 6) return '${trimmed.substring(0, 1)}…';
  return '${trimmed.substring(0, 3)}…${trimmed.substring(trimmed.length - 3)}';
}

/// Fail-closed ownership scope for chauffeur-initiated Calculator bookings.
///
/// Standalone chauffeur entry must never inherit the last active business /
/// company / partner context cached on this device. Ownership comes from the
/// active driver session only; when tenant/company/driver is missing the
/// scope is marked missing so quote/book is blocked.
_CalculatorScopeSelection _selectDriverSessionCalculatorScope() {
  final session = activeDriverSessionNotifier.value;
  // Accept standalone chauffeur sessions only: driver_pairing_code,
  // public_driver_login, standalone_driver (legacy sessions without a link
  // method are treated as standalone, mirroring DriverSessionStore restore).
  final isUsableStandaloneSession =
      session != null &&
      !session.isCompanyAdminDriverViewSession &&
      (session.isStandaloneLoginSession ||
          (session.linkMethod ?? '').trim().isEmpty);
  final tenantId = isUsableStandaloneSession
      ? (session.tenantId ?? '').trim()
      : '';
  final companyId = isUsableStandaloneSession
      ? (session.companyId ?? '').trim()
      : '';
  final driverId = isUsableStandaloneSession ? session.driverId.trim() : '';
  final assignedVehicleId = isUsableStandaloneSession
      ? (session.assignedVehicleId ?? '').trim()
      : '';

  final activeCompanySessionId =
      (activeCompanySessionNotifier.value?.companyId ?? '').trim();
  final staleCompanyId = activeCompanySessionId.isNotEmpty
      ? activeCompanySessionId
      : (companyProfileNotifier.value?.companyId ?? '').trim();
  if (staleCompanyId.isNotEmpty && staleCompanyId != companyId) {
    debugPrint(
      '[CALCULATOR][IGNORED_STALE_COMPANY_SCOPE] company=${_maskCalculatorScopeId(staleCompanyId)}',
    );
  }

  if (tenantId.isEmpty || companyId.isEmpty || driverId.isEmpty) {
    debugPrint(
      '[CALCULATOR][DRIVER_SCOPE] source=driver_session_missing tenant=${_maskCalculatorScopeId(tenantId)} company=${_maskCalculatorScopeId(companyId)} driver=${_maskCalculatorScopeId(driverId)}',
    );
    return const _CalculatorScopeSelection(
      tenantId: '',
      companyId: '',
      source: 'driver_session_missing',
      isMissing: true,
    );
  }

  debugPrint(
    '[CALCULATOR][DRIVER_SCOPE] source=driver_session tenant=${_maskCalculatorScopeId(tenantId)} company=${_maskCalculatorScopeId(companyId)} driver=${_maskCalculatorScopeId(driverId)}',
  );
  return _CalculatorScopeSelection(
    tenantId: tenantId,
    companyId: companyId,
    source: 'driver_session',
    isMissing: false,
    driverId: driverId,
    assignedVehicleId: assignedVehicleId.isEmpty ? null : assignedVehicleId,
  );
}

_CalculatorScopeSelection _withPreviewAssignmentIfNeeded({
  required _CalculatorScopeSelection scope,
  required BookingEntryContext entryContext,
  String? previewAssignedDriverId,
  String? previewAssignedVehicleId,
}) {
  if (entryContext != BookingEntryContext.companyAdmin) {
    return scope;
  }
  final driverId = (previewAssignedDriverId ?? '').trim();
  if (driverId.isEmpty) {
    return scope;
  }
  final vehicleId = (previewAssignedVehicleId ?? '').trim();
  debugPrint(
    '[CALCULATOR][PREVIEW_ASSIGNMENT] driver=${_maskCalculatorScopeId(driverId)} vehicle=${_maskCalculatorScopeId(vehicleId)}',
  );
  return _CalculatorScopeSelection(
    tenantId: scope.tenantId,
    companyId: scope.companyId,
    source: scope.source,
    isMissing: scope.isMissing,
    driverId: driverId,
    assignedVehicleId: vehicleId.isEmpty ? null : vehicleId,
  );
}

_CalculatorScopeSelection _selectCalculatorBookingScope({
  required String publicPartnerId,
  required BookingEntryContext entryContext,
  String? previewAssignedDriverId,
  String? previewAssignedVehicleId,
}) {
  // Driver entry is fail-closed on the active chauffeur session and must not
  // use partner context, company session/profile, or default fallback scope.
  if (entryContext == BookingEntryContext.driver) {
    return _selectDriverSessionCalculatorScope();
  }

  final partnerId = publicPartnerId.trim();
  if (partnerId.isNotEmpty) {
    debugPrint(
      '[CALCULATOR][SCOPE_SELECTED] source=public_partner tenant=$partnerId company=$partnerId',
    );
    return _withPreviewAssignmentIfNeeded(
      scope: _CalculatorScopeSelection(
        tenantId: partnerId,
        companyId: partnerId,
        source: 'public_partner',
        isMissing: false,
      ),
      entryContext: entryContext,
      previewAssignedDriverId: previewAssignedDriverId,
      previewAssignedVehicleId: previewAssignedVehicleId,
    );
  }

  final effectiveScope = resolveEffectiveTenantCompanyScope(
    allowDriverFallback: true,
  );
  final fallback = kTenantId.trim().isNotEmpty ? kTenantId.trim() : 'fluxidi';
  final tenantId = effectiveScope.tenantId.trim().isNotEmpty
      ? effectiveScope.tenantId.trim()
      : fallback;
  final companyId = effectiveScope.companyId.trim().isNotEmpty
      ? effectiveScope.companyId.trim()
      : fallback;
  final isDefaultFallback =
      effectiveScope.isFallback ||
      effectiveScope.source == 'default_fallback' ||
      (tenantId == fallback && companyId == fallback);

  if (isDefaultFallback) {
    debugPrint(
      '[CALCULATOR][SCOPE_SELECTED] source=missing tenant=$tenantId company=$companyId',
    );
    return _withPreviewAssignmentIfNeeded(
      scope: _CalculatorScopeSelection(
        tenantId: tenantId,
        companyId: companyId,
        source: 'missing',
        isMissing: true,
      ),
      entryContext: entryContext,
      previewAssignedDriverId: previewAssignedDriverId,
      previewAssignedVehicleId: previewAssignedVehicleId,
    );
  }

  debugPrint(
    '[CALCULATOR][SCOPE_SELECTED] source=paired_context tenant=$tenantId company=$companyId',
  );
  return _withPreviewAssignmentIfNeeded(
    scope: _CalculatorScopeSelection(
      tenantId: tenantId,
      companyId: companyId,
      source: 'paired_context',
      isMissing: false,
    ),
    entryContext: entryContext,
    previewAssignedDriverId: previewAssignedDriverId,
    previewAssignedVehicleId: previewAssignedVehicleId,
  );
}

class CalculatorPage extends StatefulWidget {
  const CalculatorPage({
    super.key,
    required this.bookingBaseUrl,
    required this.mapboxToken,
    this.persistToCustomerBookings = false,
    this.onGoToStartPage,
    this.publicPartnerId,
    this.publicPartnerName,
    this.entryContext = BookingEntryContext.customer,
    this.initialFromAddress,
    this.initialFromLabel,
    this.initialFromLat,
    this.initialFromLng,
    this.initialToAddress,
    this.initialDestinationLabel,
    this.initialToLat,
    this.initialToLng,
    this.initialServiceId,
    this.driverThemeListenable,
    this.previewAssignedDriverId,
    this.previewAssignedVehicleId,
  });

  final String
  bookingBaseUrl; // e.g. https://fluxidi-booking-api.fluxidi.workers.dev
  final String mapboxToken; // public pk...
  final bool persistToCustomerBookings;
  final VoidCallback? onGoToStartPage;
  final String? publicPartnerId;
  final String? publicPartnerName;
  final BookingEntryContext entryContext;
  final String? initialFromAddress;
  final String? initialFromLabel;
  final double? initialFromLat;
  final double? initialFromLng;
  final String? initialToAddress;
  final String? initialDestinationLabel;
  final double? initialToLat;
  final double? initialToLng;
  final String? initialServiceId;
  final ValueListenable<DriverThemeVariant>? driverThemeListenable;

  /// Business/admin chauffeur preview assignment only (not standalone auth).
  final String? previewAssignedDriverId;
  final String? previewAssignedVehicleId;

  @override
  State<CalculatorPage> createState() => _CalculatorPageState();
}

class _CalculatorPageState extends State<CalculatorPage> {
  ValueListenable<DriverThemeVariant> get _driverThemeListenable =>
      widget.driverThemeListenable ?? driverThemeNotifier;

  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();

  Timer? _fromDebounce;
  Timer? _toDebounce;

  List<_PlaceSuggestion> _fromSuggestions = const <_PlaceSuggestion>[];
  List<_PlaceSuggestion> _toSuggestions = const <_PlaceSuggestion>[];
  double? _fromLat;
  double? _fromLng;
  double? _toLat;
  double? _toLng;
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

  _CalculatorVisualTheme get _visualTheme => _calculatorVisualThemeForContext(
    widget.entryContext,
    _driverThemeListenable,
  );
  bool get _isDarkTheme => _visualTheme.isDark;
  Color get _calcScaffoldColor => _visualTheme.background;
  Color get _calcPanelColor => _visualTheme.surface;
  Color get _calcPanelAltColor => _visualTheme.surfaceAlt;
  Color get _calcDropdownColor => _visualTheme.surfaceAlt;
  Color get _calcTextPrimary => _visualTheme.textPrimary;
  Color get _calcTextMuted => _visualTheme.textMuted;
  Color get _calcAccent => _visualTheme.accent;
  Color get _calcBorder => _visualTheme.border;
  Color get _calcShadow => _visualTheme.shadow;
  Color get _calcDanger => _visualTheme.danger;
  Color get _calcSuccess => _visualTheme.success;
  Color get _calcAccentOnColor =>
      _isDarkTheme ? Colors.black : const Color(0xFF1F1706);
  List<AppOption> get _services => appConfig.enabledServices;
  List<AppOption> get _tiers => appConfig.enabledTiers;
  List<AppOption> get _extras => appConfig.enabledExtraOptions;
  bool get _isPremiumTier => _tier == 'premium';
  String get _publicPartnerId => (widget.publicPartnerId ?? '').trim();
  String get _publicPartnerName => (widget.publicPartnerName ?? '').trim();
  bool get _hasPublicPartnerContext => _publicPartnerId.isNotEmpty;
  String get _publicPartnerLabel =>
      _publicPartnerName.isNotEmpty ? _publicPartnerName : _publicPartnerId;

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
        Icon(icon, color: _calcAccent, size: 19),
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

  bool _hasFiniteCoordPair(double? lat, double? lng) {
    return lat != null && lng != null && lat.isFinite && lng.isFinite;
  }

  ({bool drinkService, bool workTable, List<String> extras})
  _derivePublicExtrasAliases(String extraServiceRaw) {
    final normalized = extraServiceRaw.trim().toLowerCase();
    if (normalized.isEmpty || normalized == 'none') {
      return (drinkService: false, workTable: false, extras: const <String>[]);
    }
    final drink =
        normalized.contains('drink') ||
        normalized.contains('drank') ||
        normalized.contains('water') ||
        normalized.contains('fris');
    final work =
        normalized.contains('worktable') ||
        normalized.contains('work_table') ||
        normalized.contains('werk') ||
        normalized.contains('tafel') ||
        normalized.contains('laptop');
    final extras = <String>[if (drink) 'drink_service', if (work) 'work_table'];
    return (drinkService: drink, workTable: work, extras: extras);
  }

  Map<String, dynamic> _buildQuotePayload(DateTime dt) {
    final vat = _activeVatConfig;
    final selectedScope = _selectCalculatorBookingScope(
      publicPartnerId: _publicPartnerId,
      entryContext: widget.entryContext,
      previewAssignedDriverId: widget.previewAssignedDriverId,
      previewAssignedVehicleId: widget.previewAssignedVehicleId,
    );
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
    final fromText = _fromCtrl.text.trim();
    final toText = _toCtrl.text.trim();
    final extraServiceValue = _isPremiumTier
        ? _payloadValueFor(_extras, _extraService, fallback: 'NONE')
        : 'NONE';
    final extrasAliases = _isPremiumTier
        ? _derivePublicExtrasAliases(extraServiceValue)
        : (drinkService: false, workTable: false, extras: const <String>[]);
    return <String, dynamic>{
      "from": fromText,
      "to": toText,
      "from_label": fromText,
      "from_raw": fromText,
      "to_label": toText,
      "to_raw": toText,
      if (_hasFiniteCoordPair(_fromLat, _fromLng)) ...{
        "from_lat": _fromLat,
        "from_lng": _fromLng,
        "fromLat": _fromLat,
        "fromLng": _fromLng,
      },
      if (_hasFiniteCoordPair(_toLat, _toLng)) ...{
        "to_lat": _toLat,
        "to_lng": _toLng,
        "toLat": _toLat,
        "toLng": _toLng,
      },
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
      "return_from": toText,
      "return_to": fromText,
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
      "extra_service": extraServiceValue,
      "extra_service_key": extraServiceValue,
      "drink_service": extrasAliases.drinkService,
      "work_table": extrasAliases.workTable,
      if (extrasAliases.extras.isNotEmpty) "extras": extrasAliases.extras,
      "tenant_id": selectedScope.tenantId,
      "company_id": selectedScope.companyId,
      "tenantId": selectedScope.tenantId,
      "companyId": selectedScope.companyId,
      if ((selectedScope.driverId ?? '').trim().isNotEmpty) ...{
        "driver_id": selectedScope.driverId,
        "driverId": selectedScope.driverId,
        "assigned_driver_id": selectedScope.driverId,
        "assignedDriverId": selectedScope.driverId,
      },
      if ((selectedScope.assignedVehicleId ?? '').trim().isNotEmpty) ...{
        "assigned_vehicle_id": selectedScope.assignedVehicleId,
        "assignedVehicleId": selectedScope.assignedVehicleId,
      },
      // Partner routing keys must never accompany a driver-entry booking:
      // the Worker re-routes tenant scope from public_partner_id.
      if (_hasPublicPartnerContext &&
          widget.entryContext != BookingEntryContext.driver) ...{
        "public_partner_id": _publicPartnerId,
        "publicPartnerId": _publicPartnerId,
        "partner_id": _publicPartnerId,
        "partnerId": _publicPartnerId,
        if (_publicPartnerName.isNotEmpty)
          "public_partner_name": _publicPartnerName,
        if (_publicPartnerName.isNotEmpty)
          "publicPartnerName": _publicPartnerName,
      },
      ...businessPayload,
    };
  }

  Map<String, dynamic> _buildQuoteRequestPayload(DateTime dt) {
    return _buildQuotePayload(dt);
  }

  Map<String, dynamic>? _quoteAvailabilityMap(Map<String, dynamic> quote) {
    final raw = quote['availability'];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  bool? _quoteAvailabilityValue(Map<String, dynamic> quote) {
    final availability = _quoteAvailabilityMap(quote);
    if (availability == null) return null;
    if (availability['checked'] != true) return null;
    final rawAvailable = availability['available'];
    if (rawAvailable is bool) return rawAvailable;
    return null;
  }

  bool _quoteAvailabilityUsesDemandIndexTechnicalState(
    Map<String, dynamic> quote,
  ) {
    final reasonCode = _availabilityReasonCodeFromMap(
      _quoteAvailabilityMap(quote),
    );
    return _isDemandIndexTechnicalAvailabilityReason(reasonCode);
  }

  String _availabilityAvailableMessage() {
    return _labelFor(
      nl: 'Voertuig beschikbaar rond dit tijdstip.',
      en: 'Vehicle available around this time.',
      fr: 'Véhicule disponible à cet horaire.',
      es: 'Vehículo disponible en este horario.',
    );
  }

  String _availabilityUnavailableMessage() {
    return _availabilityUnavailableMessageForQuote();
  }

  String _availabilityUnavailableMessageForQuote([
    Map<String, dynamic>? quote,
  ]) {
    if (quote != null &&
        _quoteAvailabilityUsesDemandIndexTechnicalState(quote)) {
      return _labelFor(
        nl: 'Beschikbaarheid wordt vernieuwd. Bereken opnieuw of probeer straks opnieuw.',
        en: 'Availability is being refreshed. Recalculate or try again shortly.',
        fr: 'La disponibilité est en cours d’actualisation. Recalculez ou réessayez dans un instant.',
        es: 'La disponibilidad se está actualizando. Vuelve a calcular o inténtalo de nuevo en breve.',
      );
    }
    return _labelFor(
      nl: 'Geen voertuig beschikbaar op dit tijdstip. Kies een ander tijdstip en bereken opnieuw.',
      en: 'No vehicle is available at this time. Choose another time and recalculate.',
      fr: 'Aucun véhicule disponible à cet horaire. Choisissez un autre horaire et recalculez.',
      es: 'No hay vehículos disponibles en este horario. Elige otro horario y vuelve a calcular.',
    );
  }

  String _bookCtaUnavailableLabel([Map<String, dynamic>? quote]) {
    if (quote != null &&
        _quoteAvailabilityUsesDemandIndexTechnicalState(quote)) {
      return _labelFor(
        nl: 'Bereken opnieuw',
        en: 'Recalculate',
        fr: 'Recalculez',
        es: 'Vuelve a calcular',
      );
    }
    return _labelFor(
      nl: 'Kies ander tijdstip',
      en: 'Choose another time',
      fr: 'Choisissez un autre horaire',
      es: 'Elige otro horario',
    );
  }

  Future<void> _openBookingConfirmation() async {
    final quote = _lastQuote;
    if (quote == null) return;
    final availability = _quoteAvailabilityValue(quote);
    if (availability == false) {
      _showThemedSnackBar(_availabilityUnavailableMessageForQuote(quote));
      return;
    }
    final dt =
        _pickupDateTime ?? DateTime.now().add(const Duration(minutes: 15));
    final payload = _lastQuoteRequestPayload != null
        ? Map<String, dynamic>.from(_lastQuoteRequestPayload!)
        : _buildQuotePayload(dt);
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _BookingConfirmationPage(
          bookingBaseUrl: widget.bookingBaseUrl,
          language: _lang,
          strings: _s,
          quote: quote,
          payload: payload,
          persistToCustomerBookings: widget.persistToCustomerBookings,
          entryContext: widget.entryContext,
          driverThemeListenable: _driverThemeListenable,
          onGoToStartPage: widget.onGoToStartPage,
          currencySymbol: _currencySymbol,
          distanceUnitLabel: appConfig.distanceUnitLabel,
          durationUnitLabel: appConfig.durationUnitLabel,
          taxLabel: appConfig.taxDisplayLabel,
          previewAssignedDriverId: widget.previewAssignedDriverId,
          previewAssignedVehicleId: widget.previewAssignedVehicleId,
        ),
      ),
    );
    if (created == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  void initState() {
    super.initState();
    customerThemeNotifier.addListener(_onThemeChanged);
    _driverThemeListenable.addListener(_onThemeChanged);
    businessThemeNotifier.addListener(_onThemeChanged);
    appLanguageNotifier.addListener(_onLanguageChanged);
    businessSettingsNotifier.addListener(_onBusinessSettingsChanged);
    localBackendTaxProfileNotifier.addListener(_onVatProfileChanged);
    final initialServiceId = (widget.initialServiceId ?? '').trim();
    if (initialServiceId.isNotEmpty &&
        _services.any((service) => service.id == initialServiceId)) {
      _service = initialServiceId;
    }
    final initialFromAddress = (widget.initialFromAddress ?? '').trim();
    final initialFromLabel = (widget.initialFromLabel ?? '').trim();
    if (initialFromAddress.isNotEmpty) {
      _fromCtrl.text = initialFromAddress;
    } else if (initialFromLabel.isNotEmpty) {
      _fromCtrl.text = initialFromLabel;
    }
    if (_hasFiniteCoordPair(widget.initialFromLat, widget.initialFromLng)) {
      _fromLat = widget.initialFromLat;
      _fromLng = widget.initialFromLng;
    }
    final initialToAddress = (widget.initialToAddress ?? '').trim();
    final initialDestinationLabel = (widget.initialDestinationLabel ?? '')
        .trim();
    if (initialToAddress.isNotEmpty) {
      _toCtrl.text = initialToAddress;
    } else if (initialDestinationLabel.isNotEmpty) {
      _toCtrl.text = initialDestinationLabel;
    }
    if (initialDestinationLabel.isNotEmpty) {
      debugPrint(
        '[CALCULATOR][DESTINATION_PREFILL] label="$initialDestinationLabel"',
      );
    }
    if (_hasFiniteCoordPair(widget.initialToLat, widget.initialToLng)) {
      _toLat = widget.initialToLat;
      _toLng = widget.initialToLng;
    }
    _toSuggestions = const <_PlaceSuggestion>[];
  }

  void _onLanguageChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _onThemeChanged() {
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
    customerThemeNotifier.removeListener(_onThemeChanged);
    _driverThemeListenable.removeListener(_onThemeChanged);
    businessThemeNotifier.removeListener(_onThemeChanged);
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
        _fromLat = pos.latitude;
        _fromLng = pos.longitude;
        _fromSuggestions = const <_PlaceSuggestion>[];
      });
    } catch (e) {
      _toast(_s.calculatorCurrentLocationFailedError.of(_lang));
    }
  }

  // ---------- UI helpers ----------
  void _showThemedSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: _calcPanelAltColor,
        content: Text(msg, style: TextStyle(color: _calcTextPrimary)),
      ),
    );
  }

  void _toast(String msg) {
    _showThemedSnackBar(msg);
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
        border: Border.all(
          color: _calcBorder.withOpacity(_isDarkTheme ? 0.45 : 1),
        ),
        boxShadow: [
          BoxShadow(
            color: _calcAccent.withOpacity(_isDarkTheme ? 0.08 : 0.05),
            blurRadius: 18,
            spreadRadius: 1,
          ),
          BoxShadow(
            color: _calcShadow.withOpacity(_isDarkTheme ? 0.55 : 0.16),
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
        color: _calcPanelAltColor,
        border: Border.all(
          color: _calcBorder.withOpacity(_isDarkTheme ? 0.45 : 1),
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: list.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          color: _calcBorder.withOpacity(_isDarkTheme ? 0.45 : 1),
        ),
        itemBuilder: (context, i) {
          final s = list[i];
          return ListTile(
            dense: true,
            title: Text(s.label, style: TextStyle(color: _calcTextPrimary)),
            subtitle: Text(
              _s.calculatorSuggestionTapHint.of(_lang),
              style: TextStyle(color: _calcTextMuted),
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
        color: _calcPanelAltColor.withOpacity(_isDarkTheme ? 0.72 : 0.9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _calcBorder.withOpacity(_isDarkTheme ? 0.45 : 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: _calcTextPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (hint != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    hint,
                    style: TextStyle(
                      color: _calcTextMuted.withOpacity(0.9),
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: onMinus,
            icon: Icon(Icons.remove_circle_outline, color: _calcAccent),
          ),
          Text(
            value,
            style: TextStyle(
              color: _calcTextPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          IconButton(
            onPressed: onPlus,
            icon: Icon(Icons.add_circle_outline, color: _calcAccent),
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
    if (!mounted) return;

    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (t == null) return;
    if (!mounted) return;

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
    if (!mounted) return;

    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (t == null) return;
    if (!mounted) return;

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

  String _driverScopeMissingMessage() => _labelFor(
    nl: 'Geen actieve chauffeurssessie gevonden. Log opnieuw in als chauffeur en probeer het nog eens.',
    en: 'No active chauffeur session found. Log in again as chauffeur and retry.',
    fr: 'Aucune session chauffeur active trouvée. Reconnectez-vous en tant que chauffeur et réessayez.',
    es: 'No se encontró una sesión de chófer activa. Inicia sesión de nuevo como chófer e inténtalo otra vez.',
  );

  // ---------- quote ----------
  Future<void> _calculate() async {
    FocusScope.of(context).unfocus();

    if (_fromCtrl.text.trim().isEmpty || _toCtrl.text.trim().isEmpty) {
      _toast(_s.calculatorFillFromToError.of(_lang));
      return;
    }

    // Driver entry is fail-closed: without a usable standalone chauffeur
    // session scope, never quote (and thus never book) against a stale or
    // default tenant/company.
    if (widget.entryContext == BookingEntryContext.driver) {
      final driverScope = _selectCalculatorBookingScope(
        publicPartnerId: _publicPartnerId,
        entryContext: widget.entryContext,
      );
      if (driverScope.isMissing) {
        _toast(_driverScopeMissingMessage());
        return;
      }
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
      if (mounted) {
        setState(() => _loading = false);
      }
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
    final availability = _quoteAvailabilityValue(q);
    final availabilityIsAvailable = availability == true;
    final availabilityMessage = availability == null
        ? null
        : (availability
              ? _availabilityAvailableMessage()
              : _availabilityUnavailableMessageForQuote(q));
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
            color: _calcPanelAltColor.withOpacity(_isDarkTheme ? 0.78 : 0.92),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: _calcBorder.withOpacity(_isDarkTheme ? 0.45 : 1),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: _calcAccent),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  '$label $value',
                  style: TextStyle(
                    color: _calcTextPrimary,
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
        border: Border.all(
          color: _calcAccent.withOpacity(_isDarkTheme ? 0.35 : 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: _calcAccent.withOpacity(_isDarkTheme ? 0.08 : 0.05),
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
              Icon(Icons.place_outlined, size: 16, color: _calcAccent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _fromCtrl.text.trim().isEmpty
                      ? _s.calculatorFromLabel.of(_lang)
                      : _fromCtrl.text.trim(),
                  style: TextStyle(
                    color: _calcTextPrimary,
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
                  color: _calcTextMuted.withOpacity(0.8),
                ),
              ],
            ),
          ),
          Row(
            children: [
              Icon(Icons.flag_outlined, size: 16, color: _calcAccent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _toCtrl.text.trim().isEmpty
                      ? _s.calculatorToLabel.of(_lang)
                      : _toCtrl.text.trim(),
                  style: TextStyle(
                    color: _calcTextPrimary,
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
              color: _calcPanelAltColor.withOpacity(_isDarkTheme ? 0.78 : 0.92),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    distanceLabel,
                    style: TextStyle(color: _calcTextMuted, fontSize: 11.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${fmtNum(showTotalMetrics ? totalDisplayDistance : distanceKm, decimals: 2)} ${appConfig.distanceUnitLabel}',
                  style: TextStyle(
                    color: _calcTextPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    durationLabel,
                    textAlign: TextAlign.right,
                    style: TextStyle(color: _calcTextMuted, fontSize: 11.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${fmtNum(showTotalMetrics ? totalDisplayDuration : durationMin, decimals: 0)} ${appConfig.durationUnitLabel}',
                  style: TextStyle(
                    color: _calcTextPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (availabilityMessage != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: availabilityIsAvailable
                    ? _calcSuccess.withOpacity(_isDarkTheme ? 0.25 : 0.18)
                    : _calcDanger.withOpacity(_isDarkTheme ? 0.25 : 0.18),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: availabilityIsAvailable
                      ? _calcSuccess.withOpacity(0.8)
                      : _calcDanger.withOpacity(0.8),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    availabilityIsAvailable
                        ? Icons.check_circle_outline
                        : Icons.warning_amber_rounded,
                    size: 16,
                    color: availabilityIsAvailable ? _calcSuccess : _calcDanger,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      availabilityMessage,
                      style: TextStyle(
                        color: _calcTextPrimary,
                        fontSize: 11.8,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          ...detailsRows.map((e) => _kv(e.key, e.value)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _calcPanelAltColor.withOpacity(_isDarkTheme ? 0.82 : 0.95),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _calcBorder.withOpacity(_isDarkTheme ? 0.45 : 1),
              ),
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
                    style: TextStyle(
                      color: _calcTextPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '$_currencySymbol ${fmtNum(priceIncl)}',
                  style: TextStyle(
                    color: _calcAccent,
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
                color: _calcTextMuted.withOpacity(0.9),
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
                    color: _calcTextMuted.withOpacity(0.88),
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
              style: TextStyle(
                color: _calcTextMuted,
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
              style: TextStyle(
                color: _calcTextPrimary,
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
    return Scaffold(
      backgroundColor: _calcScaffoldColor,
      appBar: AppBar(
        backgroundColor: _calcScaffoldColor,
        title: Text(
          _s.calculatorTitle.of(_lang),
          style: TextStyle(
            color: _calcTextPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        iconTheme: IconThemeData(color: _calcTextPrimary),
        actions: [
          if (widget.onGoToStartPage != null)
            TextButton.icon(
              onPressed: widget.onGoToStartPage,
              icon: const Icon(Icons.home_outlined, size: 18),
              label: Text(_backToStartLabel()),
              style: TextButton.styleFrom(foregroundColor: _calcTextPrimary),
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
                          color: _calcAccent.withOpacity(0.18),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _calcAccent.withOpacity(0.45),
                          ),
                        ),
                        child: Icon(
                          Icons.local_taxi_outlined,
                          color: _calcAccent,
                          size: 19,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _s.calculatorTitle.of(_lang),
                          style: TextStyle(
                            color: _calcTextPrimary,
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
                      color: _calcTextMuted.withOpacity(0.9),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            if (_hasPublicPartnerContext) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: _calcPanelAltColor.withOpacity(
                    _isDarkTheme ? 0.76 : 0.9,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _calcBorder.withOpacity(_isDarkTheme ? 0.45 : 1),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.storefront_outlined,
                      size: 15,
                      color: _calcAccent.withOpacity(0.95),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        _labelFor(
                          nl: 'Boeking bij $_publicPartnerLabel',
                          en: 'Booking with $_publicPartnerLabel',
                          fr: 'Réservation avec $_publicPartnerLabel',
                          es: 'Reserva con $_publicPartnerLabel',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _calcAccent.withOpacity(0.96),
                          fontSize: 12.2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            _zoneCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.route_outlined, size: 18, color: _calcAccent),
                      const SizedBox(width: 8),
                      Text(
                        '${_s.calculatorFromLabel.of(_lang)}  ->  ${_s.calculatorToLabel.of(_lang)}',
                        style: TextStyle(
                          color: _calcTextPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _s.calculatorFromLabel.of(_lang),
                    style: TextStyle(color: _calcTextMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _fromCtrl,
                    style: TextStyle(color: _calcTextPrimary),
                    cursorColor: _calcAccent,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: _calcPanelAltColor.withOpacity(
                        _isDarkTheme ? 0.76 : 0.92,
                      ),
                      hintText: _s.calculatorAddressHint.of(_lang),
                      hintStyle: TextStyle(
                        color: _calcTextMuted.withOpacity(0.75),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: _calcBorder.withOpacity(
                            _isDarkTheme ? 0.45 : 1,
                          ),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: _calcBorder.withOpacity(
                            _isDarkTheme ? 0.45 : 1,
                          ),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: _calcAccent.withOpacity(0.7),
                          width: 1.1,
                        ),
                      ),
                      suffixIcon: IconButton(
                        onPressed: _setFromCurrentLocation,
                        icon: Icon(Icons.my_location, color: _calcTextMuted),
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
                          _fromLat = null;
                          _fromLng = null;
                          _fromSuggestions = const <_PlaceSuggestion>[];
                          _addressSearchUnavailable = false;
                        });
                        return;
                      }
                      if (_fromLat != null || _fromLng != null) {
                        setState(() {
                          _fromLat = null;
                          _fromLng = null;
                        });
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
                      _fromLat = s.lat;
                      _fromLng = s.lon;
                      _fromSuggestions = const <_PlaceSuggestion>[];
                    });
                  }),
                  const SizedBox(height: 12),
                  Text(
                    _s.calculatorToLabel.of(_lang),
                    style: TextStyle(color: _calcTextMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _toCtrl,
                    style: TextStyle(color: _calcTextPrimary),
                    cursorColor: _calcAccent,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: _calcPanelAltColor.withOpacity(
                        _isDarkTheme ? 0.76 : 0.92,
                      ),
                      hintText: _s.calculatorAddressHint.of(_lang),
                      hintStyle: TextStyle(
                        color: _calcTextMuted.withOpacity(0.75),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: _calcBorder.withOpacity(
                            _isDarkTheme ? 0.45 : 1,
                          ),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: _calcBorder.withOpacity(
                            _isDarkTheme ? 0.45 : 1,
                          ),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: _calcAccent.withOpacity(0.7),
                          width: 1.1,
                        ),
                      ),
                    ),
                    onChanged: (v) {
                      _toDebounce?.cancel();
                      final requestId = ++_toAutocompleteRequestId;
                      if (v.trim().isEmpty) {
                        setState(() {
                          _toLat = null;
                          _toLng = null;
                          _toSuggestions = const <_PlaceSuggestion>[];
                          _addressSearchUnavailable = false;
                        });
                        return;
                      }
                      if (_toLat != null || _toLng != null) {
                        setState(() {
                          _toLat = null;
                          _toLng = null;
                        });
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
                      _toLat = s.lat;
                      _toLng = s.lon;
                      _toSuggestions = const <_PlaceSuggestion>[];
                      _addressSearchUnavailable = false;
                    });
                  }),
                  if (_addressSearchUnavailable) ...[
                    const SizedBox(height: 8),
                    Text(
                      _addressSearchUnavailableMessage(),
                      style: TextStyle(
                        color: _calcTextMuted.withOpacity(0.85),
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
                      Icon(Icons.tune_rounded, size: 18, color: _calcAccent),
                      const SizedBox(width: 8),
                      Text(
                        _s.calculatorServiceLabel.of(_lang),
                        style: TextStyle(
                          color: _calcTextPrimary,
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
                      color: _calcPanelAltColor.withOpacity(
                        _isDarkTheme ? 0.72 : 0.9,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _calcBorder.withOpacity(_isDarkTheme ? 0.45 : 1),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _s.calculatorPickupTimeLabel.of(_lang),
                            style: TextStyle(
                              color: _calcTextPrimary,
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
                            style: TextStyle(
                              color: _calcTextMuted,
                              fontSize: 12.5,
                            ),
                            textAlign: TextAlign.end,
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          onPressed: _pickDateTime,
                          icon: Icon(Icons.schedule, color: _calcAccent),
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
                      style: TextStyle(
                        color: _calcTextPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      _returnFeatureEnabled
                          ? _s.calculatorReturnSubtitle.of(_lang)
                          : _disabledReturnLabel(),
                      style: TextStyle(color: _calcTextMuted),
                    ),
                    activeColor: _calcAccent,
                  ),
                  if (_returnFeatureEnabled && _returnTrip) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: _calcPanelAltColor.withOpacity(
                          _isDarkTheme ? 0.72 : 0.9,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _calcBorder.withOpacity(
                            _isDarkTheme ? 0.45 : 1,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${_returnTripLabel()} ${_s.calculatorPickupTimeLabel.of(_lang)}',
                              style: TextStyle(
                                color: _calcTextPrimary,
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
                              style: TextStyle(
                                color: _calcTextMuted,
                                fontSize: 12.5,
                              ),
                              textAlign: TextAlign.end,
                            ),
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            onPressed: _pickReturnDateTime,
                            icon: Icon(Icons.schedule, color: _calcAccent),
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
                        border: Border.all(color: _calcAccent.withOpacity(0.5)),
                        gradient: LinearGradient(
                          colors: [
                            _calcAccent.withOpacity(0.95),
                            _visualTheme.bronze.withOpacity(0.95),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _calcAccent.withOpacity(0.18),
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
                        style: TextStyle(
                          color: _calcAccentOnColor,
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
                      style: TextStyle(color: _calcDanger),
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
                    Builder(
                      builder: (_) {
                        final quoteUnavailable =
                            _quoteAvailabilityValue(_lastQuote!) == false;
                        final ctaLabel = quoteUnavailable
                            ? _bookCtaUnavailableLabel(_lastQuote!)
                            : _s.calculatorBookNowLabel.of(_lang);
                        return GestureDetector(
                          onTap: _openBookingConfirmation,
                          child: Opacity(
                            opacity: quoteUnavailable ? 0.62 : 1,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: quoteUnavailable
                                      ? _calcBorder.withOpacity(
                                          _isDarkTheme ? 0.55 : 1,
                                        )
                                      : _calcAccent.withOpacity(0.55),
                                ),
                                color: _calcPanelAltColor,
                                boxShadow: [
                                  BoxShadow(
                                    color: quoteUnavailable
                                        ? _calcShadow.withOpacity(0.1)
                                        : _calcAccent.withOpacity(0.12),
                                    blurRadius: 14,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                              alignment: Alignment.center,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Flexible(
                                    child: Text(
                                      ctaLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: _calcTextPrimary,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Icon(
                                    Icons.arrow_forward_rounded,
                                    color: _calcAccent,
                                    size: 18,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
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
          style: TextStyle(
            color: _calcTextMuted,
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
            fillColor: _calcPanelAltColor.withOpacity(
              _isDarkTheme ? 0.72 : 0.9,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: _calcBorder.withOpacity(_isDarkTheme ? 0.45 : 1),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: _calcBorder.withOpacity(_isDarkTheme ? 0.45 : 1),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: _calcAccent.withOpacity(0.7),
                width: 1.1,
              ),
            ),
          ),
          style: TextStyle(color: _calcTextPrimary),
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
    required this.persistToCustomerBookings,
    required this.entryContext,
    required this.driverThemeListenable,
    this.onGoToStartPage,
    required this.currencySymbol,
    required this.distanceUnitLabel,
    required this.durationUnitLabel,
    required this.taxLabel,
    this.previewAssignedDriverId,
    this.previewAssignedVehicleId,
  });

  final String bookingBaseUrl;
  final AppLanguage language;
  final AppStrings strings;
  final Map<String, dynamic> quote;
  final Map<String, dynamic> payload;
  final bool persistToCustomerBookings;
  final BookingEntryContext entryContext;
  final ValueListenable<DriverThemeVariant> driverThemeListenable;
  final VoidCallback? onGoToStartPage;
  final String currencySymbol;
  final String distanceUnitLabel;
  final String durationUnitLabel;
  final String taxLabel;
  final String? previewAssignedDriverId;
  final String? previewAssignedVehicleId;

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
  String _selectedPaymentMethodId = PaymentMethodIds.inVehicleCard;
  _CalculatorVisualTheme get _visualTheme => _calculatorVisualThemeForContext(
    widget.entryContext,
    widget.driverThemeListenable,
  );
  bool get _isDarkTheme => _visualTheme.isDark;
  Color get _bg => _visualTheme.background;
  Color get _panel => _visualTheme.surface;
  Color get _panelAlt => _visualTheme.surfaceAlt;
  Color get _gold => _visualTheme.accent;
  Color get _textPrimary => _visualTheme.textPrimary;
  Color get _textMuted => _visualTheme.textMuted;
  Color get _border => _visualTheme.border;
  Color get _shadow => _visualTheme.shadow;
  Color get _danger => _visualTheme.danger;
  Color get _success => _visualTheme.success;
  Color get _actionOnGold =>
      _isDarkTheme ? Colors.black : const Color(0xFF1F1706);
  bool get _allowsCustomerSessionLink =>
      widget.entryContext == BookingEntryContext.customer;
  bool get _shouldReturnToOriginAfterSuccess =>
      widget.entryContext != BookingEntryContext.customer;

  void _goToCustomerStartHome() {
    if (!mounted) return;
    if (widget.onGoToStartPage != null) {
      widget.onGoToStartPage!.call();
    }
  }

  @override
  void initState() {
    super.initState();
    customerThemeNotifier.addListener(_onThemeChanged);
    widget.driverThemeListenable.addListener(_onThemeChanged);
    businessThemeNotifier.addListener(_onThemeChanged);
    fluxidiPendingPaymentNotifier.addListener(_onPendingPaymentChanged);
    _logPaymentPickerResolution();
    if (_allowsCustomerSessionLink) {
      unawaited(_prefillFromCustomerProfile());
    }
  }

  void _onThemeChanged() {
    if (!mounted) return;
    setState(() {});
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
    if (pending.isChecking && !_paymentConfirmed) {
      setState(() {
        _submitStateIsError = false;
        _submitState = _paymentCheckingStatusLabel();
      });
      debugPrint(
        '[PAYMENT_RETURN][NAV_SKIP] reason=still_pending booking=$ownId',
      );
    }
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
      if (_postPaymentNavigated) {
        debugPrint(
          '[PAYMENT_RETURN][NAV_SKIP] reason=already_navigated booking=$ownId',
        );
      } else if (!_allowsCustomerSessionLink) {
        debugPrint(
          '[PAYMENT_RETURN][NAV_SKIP] reason=not_customer_flow booking=$ownId',
        );
      } else {
        _postPaymentNavigated = true;
        debugPrint(
          '[PAYMENT_RETURN][NAVIGATE_CONFIRMED] booking=$ownId target=customer_area',
        );
        final messenger = ScaffoldMessenger.maybeOf(context);
        if (widget.onGoToStartPage != null) {
          _goToCustomerStartHome();
        } else if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop(true);
        }
        final lang = widget.language;
        final confirmation = lang == AppLanguage.en
            ? 'Payment confirmed. Your booking is in My bookings.'
            : lang == AppLanguage.fr
            ? 'Paiement confirme. Votre reservation est disponible dans Mes reservations.'
            : lang == AppLanguage.es
            ? 'Pago confirmado. Tu reserva esta en Mis reservas.'
            : 'Betaling bevestigd. Je boeking staat bij Mijn boekingen.';
        messenger?.showSnackBar(
          SnackBar(
            backgroundColor: _panelAlt,
            content: Text(confirmation, style: TextStyle(color: _textPrimary)),
          ),
        );
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
    customerThemeNotifier.removeListener(_onThemeChanged);
    widget.driverThemeListenable.removeListener(_onThemeChanged);
    businessThemeNotifier.removeListener(_onThemeChanged);
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

  BookingPaymentSelection get _bookingPaymentSelection =>
      BookingPaymentSelection.fromMethodId(_selectedPaymentMethodId);

  PaymentOwnershipGate get _paymentOwnershipGate {
    final profile = localBackendBusinessProfileNotifier.value;
    if (profile == null) return const PaymentOwnershipGate();
    return PaymentOwnershipGate(
      paymentOwnerMode: profile.paymentOwnerMode,
      paymentDemoMode: profile.paymentDemoMode,
      mollieConnected: profile.mollieConnected,
    );
  }

  bool get _isApplePaymentPlatform => !kIsWeb && Platform.isIOS;

  PaymentMethodClientContext get _paymentClientContext {
    final profile = localBackendBusinessProfileNotifier.value;
    final forcedTestMode = PaymentMethodResolver.inferMollieForcedTestMode(
      gate: _paymentOwnershipGate,
      livePaymentsEnabled: profile?.livePaymentsEnabled,
      mollieForcedTestMode: profile?.mollieForcedTestMode,
    );
    return PaymentMethodClientContext.forPlatform(
      isApplePlatform: _isApplePaymentPlatform,
      supportsGooglePayCheckout: !forcedTestMode,
    );
  }

  bool get _blocksGooglePayBookSubmit {
    final profile = localBackendBusinessProfileNotifier.value;
    return PaymentMethodResolver.blocksGooglePayBookSubmit(
      gate: _paymentOwnershipGate,
      livePaymentsEnabled: profile?.livePaymentsEnabled,
      mollieForcedTestMode: profile?.mollieForcedTestMode,
    );
  }

  bool _isGooglePaySubmitBlocked(String methodId) =>
      PaymentMethodResolver.isGooglePayMethodId(methodId) &&
      _blocksGooglePayBookSubmit;

  bool _blockGooglePayBookSubmitWithMessage() {
    if (!_isGooglePaySubmitBlocked(_selectedPaymentMethodId)) return false;
    _showThemedSnackBar(
      PaymentMethodResolver.googlePayTestModeUnavailableMessage(
        languageCode: widget.language.name,
      ),
    );
    return true;
  }

  List<String> get _enabledCompanyPaymentOptionIds {
    final profile = localBackendBusinessProfileNotifier.value;
    return profile == null
        ? const <String>[]
        : filterPublicPartnerPaymentOptionIds(profile.publicPaymentOptions);
  }

  String _normalizePaymentMarketCountry(String raw) {
    final normalized = normalizeCountryCode(raw);
    if (normalized.isNotEmpty &&
        PaymentCountryCodes.supported.contains(normalized)) {
      return normalized;
    }
    switch (raw.trim().toLowerCase()) {
      case 'belgie':
      case 'belgië':
      case 'belgium':
        return PaymentCountryCodes.belgium;
      case 'nederland':
      case 'netherlands':
        return PaymentCountryCodes.netherlands;
      case 'frankrijk':
      case 'france':
        return PaymentCountryCodes.france;
      case 'spanje':
      case 'spain':
      case 'españa':
      case 'espana':
        return PaymentCountryCodes.spain;
      default:
        return '';
    }
  }

  String _paymentMarketCountryCode() {
    final profile = localBackendBusinessProfileNotifier.value;
    final companyCountry = _normalizePaymentMarketCountry(
      profile?.country ?? '',
    );
    if (companyCountry.isNotEmpty) return companyCountry;
    return PaymentCountryCodes.belgium;
  }

  ResolvedPaymentMethods get _resolvedPaymentMethods =>
      PaymentMethodResolver.resolve(
        countryCode: _paymentMarketCountryCode(),
        enabledPublicPaymentOptionIds: _enabledCompanyPaymentOptionIds,
        ownershipGate: _paymentOwnershipGate,
        clientContext: _paymentClientContext,
        languageCode: widget.language.name,
      );

  List<String> get _visiblePaymentMethodIds => _resolvedPaymentMethods.ids;

  bool _isDisplayOnlyPaymentMethod(String methodId) {
    final id = normalizePaymentMethodId(methodId);
    final def = PaymentMethodCatalog.definitionFor(id);
    if (def == null) return true;
    if (id == PaymentMethodIds.inVehicleCard) return false;
    if (id == PaymentMethodIds.qrCode) return !_isQrPaymentConfigured();
    if (PaymentMethodResolver.isGooglePayMethodId(id) &&
        _blocksGooglePayBookSubmit) {
      return true;
    }
    return !def.isSupportedMollieCheckout;
  }

  bool _isDirectCheckoutPaymentMethod(String methodId) {
    if (_isDisplayOnlyPaymentMethod(methodId)) return false;
    return PaymentMethodCatalog.definitionFor(
          methodId,
        )?.isSupportedMollieCheckout ??
        false;
  }

  bool _isSelectableExternalPaymentMethod(String methodId) {
    final id = normalizePaymentMethodId(methodId);
    final def = PaymentMethodCatalog.definitionFor(id);
    if (def == null) return false;
    if (def.isSupportedMollieCheckout) return false;
    if (id == PaymentMethodIds.inVehicleCard) return true;
    if (id == PaymentMethodIds.qrCode) return _isQrPaymentConfigured();
    return false;
  }

  void _logPaymentPickerResolution() {
    final profile = localBackendBusinessProfileNotifier.value;
    final companyCountryRaw = profile?.country ?? '';
    final market = _paymentMarketCountryCode();
    final enabled = _enabledCompanyPaymentOptionIds;
    final visible = _visiblePaymentMethodIds;
    final direct = visible
        .where(_isDirectCheckoutPaymentMethod)
        .toList(growable: false);
    final selectableExternal = visible
        .where(_isSelectableExternalPaymentMethod)
        .toList(growable: false);
    final displayOnly = visible
        .where(_isDisplayOnlyPaymentMethod)
        .toList(growable: false);
    final visibleSet = visible.toSet();
    final hidden = enabled
        .where((id) => !visibleSet.contains(id))
        .map((id) {
          final def = PaymentMethodCatalog.definitionFor(id);
          final reason = def == null
              ? 'unknown'
              : id == PaymentMethodIds.cash
              ? 'represented_by_pay_in_car'
              : id == PaymentMethodIds.onlinePayment
              ? 'category_not_method'
              : def.isSupportedMollieCheckout
              ? 'market_or_owner_gate'
              : def.capability.name;
          return '$id:$reason';
        })
        .join('|');
    debugPrint(
      '[PAYMENT_PICKER][RESOLVE] surface=calculator market=$market companyCountryRaw=$companyCountryRaw routeCountryRaw=- enabledOptionIds=${enabled.join("|")} directCheckoutOptionIds=${direct.join("|")} selectableExternalOptionIds=${selectableExternal.join("|")} displayOnlyOptionIds=${displayOnly.join("|")} hiddenOptionIdsWithReason=$hidden qrConfigured=${_isQrPaymentConfigured() ? "true" : "false"} qrMissingBankDetails=${_isQrPaymentMissingBankDetails() ? "true" : "false"}',
    );
  }

  String? get _onlinePaymentsBlockedMessage =>
      _resolvedPaymentMethods.onlinePaymentsBlockedMessage;

  String _paymentChoiceTitle() {
    return _localizedText(
      nl: 'Betaalmethode',
      en: 'Payment method',
      fr: 'Mode de paiement',
      es: 'Método de pago',
    );
  }

  String _paymentChoiceSubtitle() {
    return _localizedText(
      nl: 'Kies hoe je wilt betalen voor deze rit.',
      en: 'Choose how you want to pay for this ride.',
      fr: 'Choisissez comment payer ce trajet.',
      es: 'Elige cómo quieres pagar este viaje.',
    );
  }

  void _showThemedSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: _panelAlt,
        content: Text(message, style: TextStyle(color: _textPrimary)),
      ),
    );
  }

  String _paymentMethodUnavailableMessage() {
    return _localizedText(
      nl: 'Deze betaalmethode is niet beschikbaar voor dit bedrijf.',
      en: 'This payment method is not available for this company.',
      fr: 'Ce moyen de paiement n’est pas disponible pour cette entreprise.',
      es: 'Este método de pago no está disponible para esta empresa.',
    );
  }

  String _qrPaymentSetupRequiredMessage() {
    return _localizedText(
      nl: 'Vul eerst de bankgegevens in bij de bedrijfsinstellingen.',
      en: 'Add bank details in business settings first.',
      fr: 'Ajoutez d’abord les coordonnées bancaires dans les paramètres de l’entreprise.',
      es: 'Añade primero los datos bancarios en la configuración de la empresa.',
    );
  }

  String _payconiqWeroPendingMessage() {
    return _localizedText(
      nl: 'Payconiq / Wero wordt later als aparte betaaloptie gekoppeld.',
      en: 'Payconiq / Wero will be connected later as a separate payment option.',
      fr: 'Payconiq / Wero sera connecté plus tard comme option de paiement séparée.',
      es: 'Payconiq / Wero se conectará más adelante como una opción de pago separada.',
    );
  }

  bool _isQrPaymentConfigured() {
    final profile = localBackendBusinessProfileNotifier.value;
    return (profile?.iban.trim().isNotEmpty ?? false);
  }

  bool _isQrPaymentMissingBankDetails() {
    return _visiblePaymentMethodIds.contains(PaymentMethodIds.qrCode) &&
        !_isQrPaymentConfigured();
  }

  String _displayOnlyPaymentMessage(String methodId) {
    final id = normalizePaymentMethodId(methodId);
    if (id == PaymentMethodIds.qrCode) {
      return _qrPaymentSetupRequiredMessage();
    }
    if (id == PaymentMethodIds.payconiqWero) {
      return _payconiqWeroPendingMessage();
    }
    if (id == PaymentMethodIds.googlePay) {
      return PaymentMethodResolver.googlePayTestModeUnavailableMessage(
        languageCode: widget.language.name,
      );
    }
    return _paymentMethodUnavailableMessage();
  }

  String _paymentMethodLabel(String methodId) {
    switch (normalizePaymentMethodId(methodId)) {
      case PaymentMethodIds.inVehicleCard:
        return _localizedText(
          nl: 'Betalen in de auto',
          en: 'Pay in the car',
          fr: 'Payer dans la voiture',
          es: 'Pagar en el coche',
        );
      case PaymentMethodIds.bancontact:
        return 'Bancontact';
      case PaymentMethodIds.kbcCbc:
        return 'KBC/CBC Payment Button';
      case PaymentMethodIds.belfius:
        return 'Belfius Pay Button';
      case PaymentMethodIds.bancontactQr:
        return 'Payconiq / Bancontact Pay QR';
      case PaymentMethodIds.qrCode:
        return _localizedText(
          nl: 'QR-betaling',
          en: 'QR payment',
          fr: 'Paiement par QR',
          es: 'Pago por QR',
        );
      case PaymentMethodIds.ideal:
        return 'iDEAL';
      case PaymentMethodIds.cardPayment:
        return _localizedText(
          nl: 'Kaartbetaling',
          en: 'Card payment',
          fr: 'Paiement par carte',
          es: 'Pago con tarjeta',
        );
      case PaymentMethodIds.applePay:
        return 'Apple Pay';
      case PaymentMethodIds.googlePay:
        return 'Google Pay';
      case PaymentMethodIds.paypal:
        return 'PayPal';
      case PaymentMethodIds.bizum:
        return 'Bizum';
      case PaymentMethodIds.cartesBancaires:
        return 'Carte Bancaire / CB';
      case PaymentMethodIds.payconiqWero:
        return 'Payconiq / Wero';
      default:
        return methodId;
    }
  }

  String _paymentMethodDescription(String methodId) {
    final id = normalizePaymentMethodId(methodId);
    if (id == PaymentMethodIds.inVehicleCard || id == PaymentMethodIds.cash) {
      return _localizedText(
        nl: 'Boeking wordt meteen aangemaakt, betaling volgt tijdens de rit.',
        en: 'Booking is created immediately, payment follows during the ride.',
        fr: 'La réservation est créée immédiatement, paiement pendant le trajet.',
        es: 'La reserva se crea al instante, el pago se realiza durante el trayecto.',
      );
    }
    if (id == PaymentMethodIds.qrCode) {
      if (!_isQrPaymentConfigured()) {
        return _localizedText(
          nl: 'Bankgegevens ontbreken in de bedrijfsinstellingen.',
          en: 'Bank details are missing in business settings.',
          fr: 'Les coordonnées bancaires manquent dans les paramètres de l’entreprise.',
          es: 'Faltan los datos bancarios en la configuración de la empresa.',
        );
      }
      return _localizedText(
        nl: 'Scan en betaal naar de rekening van het bedrijf.',
        en: 'Scan and pay to the company bank account.',
        fr: 'Scannez et payez sur le compte bancaire de l’entreprise.',
        es: 'Escanea y paga a la cuenta bancaria de la empresa.',
      );
    }
    if (id == PaymentMethodIds.payconiqWero) {
      return _localizedText(
        nl: 'Payconiq / Wero — binnenkort beschikbaar',
        en: 'Payconiq / Wero — coming soon',
        fr: 'Payconiq / Wero — bientôt disponible',
        es: 'Payconiq / Wero — próximamente',
      );
    }
    if (id == PaymentMethodIds.bancontactQr) {
      return _localizedText(
        nl: 'Scan met Bancontact Pay, Payconiq by Bancontact of je bank-app.',
        en: 'Scan with Bancontact Pay, Payconiq by Bancontact, or your Belgian banking app.',
        fr: 'Scannez avec Bancontact Pay, Payconiq by Bancontact ou votre application bancaire belge.',
        es: 'Escanea con Bancontact Pay, Payconiq by Bancontact o tu app bancaria belga.',
      );
    }
    if (id == PaymentMethodIds.kbcCbc || id == PaymentMethodIds.belfius) {
      return _localizedText(
        nl: 'Open de beveiligde betaalpagina na het bevestigen.',
        en: 'Open the secure checkout page after confirming.',
        fr: 'Ouvrez la page de paiement sécurisée après confirmation.',
        es: 'Abre la página de pago segura tras confirmar.',
      );
    }
    return _localizedText(
      nl: 'Open de beveiligde betaalpagina na het bevestigen.',
      en: 'Open the secure checkout page after confirming.',
      fr: 'Ouvrez la page de paiement sécurisée après confirmation.',
      es: 'Abre la página de pago segura tras confirmar.',
    );
  }

  IconData _paymentMethodIcon(String methodId) {
    final id = normalizePaymentMethodId(methodId);
    if (id == PaymentMethodIds.inVehicleCard) {
      return Icons.local_taxi_rounded;
    }
    if (id == PaymentMethodIds.qrCode) {
      return Icons.qr_code_2_rounded;
    }
    if (id == PaymentMethodIds.payconiqWero) {
      return Icons.schedule_rounded;
    }
    if (id == PaymentMethodIds.bancontactQr) {
      return Icons.qr_code_2_rounded;
    }
    if (id == PaymentMethodIds.kbcCbc || id == PaymentMethodIds.belfius) {
      return Icons.account_balance_rounded;
    }
    return Icons.language_rounded;
  }

  String? _qrSrcFromBookResponse(Map<String, dynamic> body) {
    Map<String, dynamic>? asMap(dynamic value) {
      if (value is Map<String, dynamic>) return value;
      if (value is Map) return Map<String, dynamic>.from(value);
      return null;
    }

    final candidates = <Map<String, dynamic>?>[
      asMap(body['qr_code']),
      asMap(body['qrCode']),
      asMap(
        body['payment'] is Map ? (body['payment'] as Map)['qr_code'] : null,
      ),
      asMap(body['payment'] is Map ? (body['payment'] as Map)['qrCode'] : null),
      if (body['booking'] is Map) ...[
        asMap((body['booking'] as Map)['qr_code']),
        asMap((body['booking'] as Map)['qrCode']),
      ],
    ];
    for (final qr in candidates) {
      final src = qr?['src']?.toString().trim() ?? '';
      if (src.isNotEmpty) return src;
    }
    return null;
  }

  Future<void> _showPaymentQrDialog({
    required String qrSrc,
    required String checkoutUrl,
    String? paymentBookingId,
  }) async {
    final safePaymentUrl = _isCustomerSafeCheckoutUrl(checkoutUrl)
        ? checkoutUrl.trim()
        : '';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: _panelAlt,
          content: PaymentQrPanel(
            language: widget.language,
            qrSrc: qrSrc,
            checkoutUrl: safePaymentUrl.isEmpty ? null : safePaymentUrl,
            onOpenCheckout: safePaymentUrl.isEmpty
                ? null
                : () {
                    final ownPaymentBookingId = (paymentBookingId ?? '').trim();
                    if (ownPaymentBookingId.isNotEmpty) {
                      markFluxidiPendingPaymentChecking(
                        paymentBookingId: ownPaymentBookingId,
                      );
                    }
                    Navigator.of(dialogContext).pop();
                    _openPaymentUrl(safePaymentUrl);
                  },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(widget.strings.bookingCloseLabel.of(widget.language)),
            ),
          ],
        );
      },
    );
  }

  Widget _paymentMethodChoiceOption(String methodId) {
    final selected = _selectedPaymentMethodId == methodId;
    final displayOnly = _isDisplayOnlyPaymentMethod(methodId);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _submitting
          ? null
          : displayOnly
          ? () => _showThemedSnackBar(_displayOnlyPaymentMessage(methodId))
          : () => setState(() {
              _selectedPaymentMethodId = methodId;
            }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? _panelAlt
              : _panel.withOpacity(_isDarkTheme ? 0.45 : 0.75),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? _gold
                : _border.withOpacity(_isDarkTheme ? 0.45 : 1),
            width: selected ? 1.2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              _paymentMethodIcon(methodId),
              color: displayOnly
                  ? _textMuted.withOpacity(0.72)
                  : selected
                  ? _gold
                  : _textPrimary.withOpacity(0.8),
              size: 18,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _paymentMethodLabel(methodId),
                    style: TextStyle(
                      color: displayOnly ? _textMuted : _textPrimary,
                      fontSize: 12.8,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _paymentMethodDescription(methodId),
                    style: TextStyle(
                      color: _textMuted.withOpacity(0.92),
                      fontSize: 11.2,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              displayOnly
                  ? Icons.info_outline_rounded
                  : selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              color: displayOnly
                  ? _textMuted.withOpacity(0.72)
                  : selected
                  ? _gold
                  : _textMuted.withOpacity(0.8),
              size: 18,
            ),
          ],
        ),
      ),
    );
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
    if (s.contains('clientsoftware caused connection abort') ||
        s.contains('uri=https://') ||
        s.contains('socketexception') ||
        s.contains('timeoutexception') ||
        s.contains('connection abort') ||
        s.contains('connection reset') ||
        s.contains('failed host lookup') ||
        s.contains('network is unreachable')) {
      if (widget.language == AppLanguage.en) {
        return "We couldn't confirm the booking yet. Check My bookings or refresh.";
      }
      if (widget.language == AppLanguage.fr) {
        return 'Nous n avons pas encore pu confirmer la reservation. Verifiez Mes reservations ou actualisez.';
      }
      if (widget.language == AppLanguage.es) {
        return 'Todavia no pudimos confirmar la reserva. Revisa Mis reservas o actualiza.';
      }
      return 'We konden de boeking nog niet bevestigen. Kijk bij Mijn boekingen of vernieuw.';
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
    _showThemedSnackBar(
      message ??
          widget.strings.bookingPaymentLinkCopiedMessage.of(widget.language),
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
    String? paymentBookingId,
  }) async {
    final safePaymentUrl = _isCustomerSafeCheckoutUrl(paymentUrl)
        ? paymentUrl.trim()
        : '';
    final hasPaymentUrl = safePaymentUrl.isNotEmpty;
    final title = requiresPayment
        ? widget.strings.bookingPaymentSuccessTitle.of(widget.language)
        : widget.strings.bookingSuccessCashMessage.of(widget.language);
    final defaultPaymentMessage = widget.strings.bookingPaymentRequiredMessage
        .of(widget.language);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return ValueListenableBuilder<FluxidiPendingPayment?>(
          valueListenable: fluxidiPendingPaymentNotifier,
          builder: (_, pending, __) {
            final ownPaymentBookingId = (paymentBookingId ?? '').trim();
            final isSamePending =
                ownPaymentBookingId.isNotEmpty &&
                pending != null &&
                pending.paymentBookingId == ownPaymentBookingId;
            final isChecking = isSamePending && pending.isChecking;
            final isPaidOrConfirmed =
                isSamePending &&
                (pending.status == FluxidiPaymentStatus.paid ||
                    pending.status == FluxidiPaymentStatus.confirmed);
            final allowPayNow =
                hasPaymentUrl && !isChecking && !isPaidOrConfirmed;
            if (requiresPayment && (isChecking || isPaidOrConfirmed)) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!dialogContext.mounted) return;
                final route = ModalRoute.of(dialogContext);
                if (route?.isCurrent == true) {
                  Navigator.of(dialogContext).pop();
                }
              });
            }
            final message = requiresPayment
                ? (isChecking
                      ? _paymentCheckingStatusLabel()
                      : defaultPaymentMessage)
                : widget.strings.bookingSuccessCashMessage.of(widget.language);

            return AlertDialog(
              backgroundColor: _panelAlt,
              title: Text(title, style: TextStyle(color: _textPrimary)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (requiresPayment && isChecking) ...[
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(
                          message,
                          style: TextStyle(color: _textMuted),
                        ),
                      ),
                    ],
                  ),
                  if ((publicRef ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      '${widget.strings.bookingSuccessReferencePrefix.of(widget.language)}: ${publicRef!.trim()}',
                      style: TextStyle(
                        color: _textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                if (allowPayNow)
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
                  child: Text(
                    widget.strings.bookingCloseLabel.of(widget.language),
                  ),
                ),
                if (allowPayNow)
                  FilledButton(
                    onPressed: () {
                      final ownPaymentBookingId = (paymentBookingId ?? '')
                          .trim();
                      if (ownPaymentBookingId.isNotEmpty) {
                        markFluxidiPendingPaymentChecking(
                          paymentBookingId: ownPaymentBookingId,
                        );
                      }
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

  String _bookingCheckingStatusLabel() {
    switch (widget.language) {
      case AppLanguage.en:
        return 'Checking booking status...';
      case AppLanguage.fr:
        return 'Vérification de la réservation...';
      case AppLanguage.es:
        return 'Comprobando la reserva...';
      case AppLanguage.nl:
        return 'Boeking wordt gecontroleerd...';
    }
  }

  String _paymentCheckingStatusLabel() {
    switch (widget.language) {
      case AppLanguage.en:
        return 'Checking payment...';
      case AppLanguage.fr:
        return 'Vérification du paiement...';
      case AppLanguage.es:
        return 'Comprobando el pago...';
      case AppLanguage.nl:
        return 'Betaling controleren...';
    }
  }

  String _bookingUncertainStatusLabel() {
    switch (widget.language) {
      case AppLanguage.en:
        return "We couldn't confirm the booking. Check My bookings or refresh.";
      case AppLanguage.fr:
        return "Nous n'avons pas pu confirmer la réservation. Vérifiez Mes réservations ou actualisez.";
      case AppLanguage.es:
        return 'No pudimos confirmar la reserva. Revisa Mis reservas o actualiza.';
      case AppLanguage.nl:
        return 'We konden de bevestiging niet controleren. Kijk bij Mijn boekingen of vernieuw.';
    }
  }

  bool _isBookingTransportError(String raw) {
    final s = raw.toLowerCase();
    return s.contains('clientsoftware caused connection abort') ||
        s.contains('connection abort') ||
        s.contains('connection reset') ||
        s.contains('socketexception') ||
        s.contains('timeoutexception') ||
        s.contains('failed host lookup') ||
        s.contains('network is unreachable') ||
        s.contains('uri=https://');
  }

  Future<Map<String, dynamic>?> _postBookAndDecode(
    Map<String, dynamic> payload, {
    Duration timeout = const Duration(seconds: 20),
    String? customerSessionToken,
    String? driverSessionToken,
    BookingEntryContext? entryContext,
  }) async {
    final url = Uri.parse('${widget.bookingBaseUrl}/book');
    final headers = <String, String>{'content-type': 'application/json'};
    final driverToken = (driverSessionToken ?? '').trim();
    final customerToken = (customerSessionToken ?? '').trim();
    final bookEntryContext = entryContext ?? widget.entryContext;
    if (driverToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $driverToken';
    } else if (bookEntryContext == BookingEntryContext.companyAdmin) {
      final auth = await resolveCompanyOwnerAuthHeaders();
      headers.addAll(auth.headers);
      final companyIdForLog =
          activeCompanySessionNotifier.value?.companyId.trim() ?? '';
      debugPrint(
        '[CALCULATOR][COMPANY_BOOK_AUTH] token_present=${auth.mode != CompanyOwnerAuthMode.none} mode=${auth.mode.name} company=${_maskCalculatorScopeId(companyIdForLog.isNotEmpty ? companyIdForLog : '-')}',
      );
    } else if (customerToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $customerToken';
    }
    final res = await http
        .post(url, headers: headers, body: jsonEncode(payload))
        .timeout(timeout);
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
      final err = (body['error'] ?? body['message'] ?? 'HTTP ${res.statusCode}')
          .toString();
      throw Exception(err);
    }
    debugPrint('[BOOK][SUCCESS_RAW] status=${res.statusCode} body=$rawText');
    return body;
  }

  Future<Map<String, dynamic>?> _verifyBookAfterTransportError(
    Map<String, dynamic> payload, {
    String? customerSessionToken,
    String? driverSessionToken,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        if (attempt > 0) {
          await Future<void>.delayed(const Duration(milliseconds: 700));
        }
        final body = await _postBookAndDecode(
          payload,
          timeout: const Duration(seconds: 15),
          customerSessionToken: customerSessionToken,
          driverSessionToken: driverSessionToken,
          entryContext: widget.entryContext,
        );
        if (body != null && body.isNotEmpty) return body;
      } catch (_) {
        // Keep retry bounded; this verification flow is best-effort only.
      }
    }
    return null;
  }

  Future<void> _handleBookSuccess({
    required Map<String, dynamic> body,
    required Map<String, dynamic> payload,
    required String name,
    required String phone,
    required String email,
    required String effectiveCompanyName,
    required String effectiveVatNumber,
    required String effectiveInvoiceEmail,
    required String effectiveInvoiceAddress,
    required Map<String, dynamic> businessPayload,
    required CustomerSession? customerSession,
    required _CalculatorScopeSelection selectedScope,
  }) async {
    bool isOnlinePaymentMode(String value) {
      final normalized = value.trim().toLowerCase();
      return normalized == 'mollie' ||
          normalized == 'online' ||
          normalized == 'online_payment' ||
          normalized == 'online-payments' ||
          normalized == 'online_payments';
    }

    bool boolish(dynamic value) {
      if (value is bool) return value;
      final raw = (value ?? '').toString().trim().toLowerCase();
      return raw == '1' || raw == 'true' || raw == 'yes' || raw == 'on';
    }

    String firstNonEmpty(List<dynamic> values) {
      for (final value in values) {
        final text = (value ?? '').toString().trim();
        if (text.isNotEmpty) return text;
      }
      return '';
    }

    final bookingRef = firstNonEmpty([
      body['bookingId'],
      body['booking_id'],
      body['public_booking_id'],
      body['publicBookingId'],
      body['id'],
      body['booking'] is Map ? body['booking']['bookingId'] : null,
      body['booking'] is Map ? body['booking']['booking_id'] : null,
      body['booking'] is Map ? body['booking']['public_booking_id'] : null,
      body['booking'] is Map ? body['booking']['publicBookingId'] : null,
      body['booking'] is Map ? body['booking']['id'] : null,
    ]);
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
    final publicRef = publicRefRaw.isNotEmpty
        ? publicRefRaw
        : bookingRef.trim();
    final bookingObj = body['booking'] is Map
        ? Map<String, dynamic>.from(body['booking'] as Map)
        : const <String, dynamic>{};
    final requiresPayment =
        boolish(body['requiresPayment']) ||
        boolish(body['payment_required']) ||
        boolish(body['requires_payment']) ||
        boolish(bookingObj['requiresPayment']) ||
        boolish(bookingObj['payment_required']) ||
        boolish(bookingObj['requires_payment']);
    final checkoutUrl = firstNonEmpty([
      body['checkoutUrl'],
      body['checkout_url'],
      body['paymentUrl'],
      body['payment_url'],
      bookingObj['checkoutUrl'],
      bookingObj['checkout_url'],
      bookingObj['paymentUrl'],
      bookingObj['payment_url'],
    ]);
    final safeCheckoutUrl = _isCustomerSafeCheckoutUrl(checkoutUrl)
        ? checkoutUrl
        : '';
    final paymentMode = firstNonEmpty([
      body['paymentMode'],
      body['payment_mode'],
      bookingObj['paymentMode'],
      bookingObj['payment_mode'],
    ]).toLowerCase();
    final paymentProvider = firstNonEmpty([
      body['payment_provider'],
      body['paymentProvider'],
      bookingObj['payment_provider'],
      bookingObj['paymentProvider'],
    ]).toLowerCase();
    final paymentStatusRaw = firstNonEmpty([
      body['payment_status'],
      body['paymentStatus'],
      bookingObj['payment_status'],
      bookingObj['paymentStatus'],
    ]).toLowerCase();
    final responseBusinessDetected =
        boolish(body['business_detected']) ||
        boolish(body['businessDetected']) ||
        boolish(bookingObj['business_detected']) ||
        boolish(bookingObj['businessDetected']);
    final responseInvoiceRequested =
        boolish(body['invoice_requested']) ||
        boolish(body['invoiceRequested']) ||
        boolish(bookingObj['invoice_requested']) ||
        boolish(bookingObj['invoiceRequested']);
    final requestBusinessIntent =
        boolish(businessPayload['business_detected']) ||
        boolish(businessPayload['businessDetected']) ||
        boolish(businessPayload['invoice_requested']) ||
        boolish(businessPayload['invoiceRequested']) ||
        boolish(payload['business_detected']) ||
        boolish(payload['businessDetected']) ||
        boolish(payload['invoice_requested']) ||
        boolish(payload['invoiceRequested']);
    final responseBusinessIntent =
        responseBusinessDetected || responseInvoiceRequested;
    final requestPaymentMode = firstNonEmpty([
      payload['paymentMode'],
      payload['payment_mode'],
      payload['payment_method'],
      payload['paymentMethod'],
      payload['payment_type'],
      payload['paymentType'],
      payload['quote'] is Map ? payload['quote']['paymentMode'] : null,
      payload['quote'] is Map ? payload['quote']['payment_mode'] : null,
    ]).toLowerCase();
    final requestPaymentProvider = firstNonEmpty([
      payload['paymentProvider'],
      payload['payment_provider'],
    ]).toLowerCase();
    final explicitOnlineRequested =
        isOnlinePaymentMode(requestPaymentMode) ||
        requestPaymentProvider == 'mollie';
    final backendRequiresOnlineCheckout =
        requiresPayment ||
        isOnlinePaymentMode(paymentMode) ||
        paymentProvider == 'mollie';
    final onlineCheckoutRequired =
        explicitOnlineRequested && backendRequiresOnlineCheckout;
    if (onlineCheckoutRequired && safeCheckoutUrl.isEmpty) {
      final blockedBooking = bookingRef.isNotEmpty ? bookingRef : publicRef;
      debugPrint(
        '[BOOK][CHECKOUT_MISSING_BLOCKED] booking=$blockedBooking business=${responseBusinessIntent || requestBusinessIntent} invoice=$responseInvoiceRequested requiresPayment=$requiresPayment explicitOnline=$explicitOnlineRequested paymentMode=$paymentMode provider=$paymentProvider',
      );
      throw Exception(
        'Online betaling kon niet worden gestart. Probeer opnieuw.',
      );
    }
    final invoiceManualFlow =
        (responseBusinessIntent || requestBusinessIntent) &&
        !onlineCheckoutRequired &&
        safeCheckoutUrl.isEmpty &&
        (paymentProvider == 'manual' ||
            paymentProvider == 'invoice' ||
            paymentProvider == 'cash' ||
            paymentStatusRaw == 'unpaid' ||
            paymentStatusRaw == 'pending' ||
            !backendRequiresOnlineCheckout);
    final paymentFlow = onlineCheckoutRequired || safeCheckoutUrl.isNotEmpty;
    final privateManualFlow =
        !responseBusinessIntent &&
        !requestBusinessIntent &&
        !onlineCheckoutRequired &&
        safeCheckoutUrl.isEmpty &&
        !paymentFlow;
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
          paymentStatus: firstNonEmpty([
            body['payment_status'],
            body['paymentStatus'],
            bookingObj['payment_status'],
            bookingObj['paymentStatus'],
            paymentFlow
                ? (paymentBookingId.isNotEmpty ? 'pending' : 'unpaid')
                : (invoiceManualFlow ? 'unpaid' : 'unpaid'),
          ]),
          status: firstNonEmpty([
            body['status'],
            body['stage'],
            bookingObj['status'],
            bookingObj['stage'],
            paymentFlow ? 'PENDING' : 'CONFIRMED',
          ]).toUpperCase(),
          companyName: effectiveCompanyName,
          vatNumber: effectiveVatNumber,
          invoiceEmail: effectiveInvoiceEmail,
          invoiceAddress: effectiveInvoiceAddress,
          businessDetected:
              responseBusinessDetected ||
              businessPayload['business_detected'] == true ||
              businessPayload['businessDetected'] == true,
          invoiceRequested:
              responseInvoiceRequested ||
              businessPayload['invoice_requested'] == true ||
              businessPayload['invoiceRequested'] == true,
        );
    if (widget.persistToCustomerBookings) {
      await CustomerBookingsStore.instance.upsert(storedBooking);
    }
    if (widget.persistToCustomerBookings &&
        _allowsCustomerSessionLink &&
        customerSession != null &&
        selectedScope.tenantId.trim().isNotEmpty &&
        selectedScope.companyId.trim().isNotEmpty) {
      final currentTenant = (customerSession.defaultTenantId ?? '').trim();
      final currentCompany = (customerSession.defaultCompanyId ?? '').trim();
      final nextTenant = selectedScope.tenantId.trim();
      final nextCompany = selectedScope.companyId.trim();
      if (currentTenant != nextTenant || currentCompany != nextCompany) {
        final nextSession = CustomerSession(
          customerSessionToken: customerSession.customerSessionToken,
          expiresAt: customerSession.expiresAt,
          customerId: customerSession.customerId,
          phoneE164: customerSession.phoneE164,
          defaultTenantId: nextTenant,
          defaultCompanyId: nextCompany,
          createdAt: customerSession.createdAt,
          updatedAt: customerSession.updatedAt,
        );
        await CustomerSessionStore.instance.save(nextSession);
      }
      debugPrint(
        '[CUSTOMER_BOOKING_LOCAL_SAVE][SCOPE] target=tenant_company tenant=${selectedScope.tenantId} company=${selectedScope.companyId}',
      );
    } else if (widget.persistToCustomerBookings) {
      debugPrint(
        '[CUSTOMER_BOOKING_LOCAL_SAVE][SCOPE] target=customer_session_fallback',
      );
    }
    final localBookingId = (bookingRef.isNotEmpty ? bookingRef : publicRef)
        .trim();
    if (!widget.persistToCustomerBookings) {
      debugPrint(
        '[CUSTOMER_BOOKINGS][SAVE][SKIP] reason=persist_disabled booking=$localBookingId',
      );
    } else if (localBookingId.isEmpty) {
      debugPrint('[CUSTOMER_BOOKINGS][SAVE][SKIP] reason=missing_booking_id');
    } else {
      debugPrint('[CUSTOMER_BOOKINGS][SAVE][OK] booking=$localBookingId');
    }
    final finalPricing = bookingRef.isNotEmpty
        ? await _fetchFinalAuthoritativePricing(bookingRef)
        : null;

    final successMessage = [
      invoiceManualFlow
          ? _localizedText(
              nl: 'Boeking aangemaakt. Betaling in de wagen. Factuur volgt na betaling.',
              en: 'Booking created. Payment in the vehicle. Invoice follows after payment.',
              fr: 'Reservation creee. Paiement dans le vehicule. Facture envoyee apres paiement.',
              es: 'Reserva creada. Pago en el vehiculo. La factura se enviara despues del pago.',
            )
          : privateManualFlow
          ? _localizedText(
              nl: 'Boeking aangemaakt. Betaling in de wagen.',
              en: 'Booking created. Payment in the vehicle.',
              fr: 'Reservation creee. Paiement dans le vehicule.',
              es: 'Reserva creada. Pago en el vehiculo.',
            )
          : paymentFlow
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
    final qrSrc = _qrSrcFromBookResponse(body);
    final prefersQrCheckout =
        normalizePaymentMethodId(_selectedPaymentMethodId) ==
        PaymentMethodIds.bancontactQr;
    if (onlineCheckoutRequired &&
        prefersQrCheckout &&
        (qrSrc ?? '').isNotEmpty) {
      if (paymentBookingId.isNotEmpty) {
        markFluxidiPendingPaymentChecking(paymentBookingId: paymentBookingId);
      }
      if (mounted) {
        setState(() {
          _submitStateIsError = false;
          _submitState = _paymentCheckingStatusLabel();
        });
      }
      await _showPaymentQrDialog(
        qrSrc: qrSrc!,
        checkoutUrl: safeCheckoutUrl,
        paymentBookingId: paymentBookingId,
      );
      if (!mounted) return;
      if (_shouldReturnToOriginAfterSuccess && mounted) {
        Navigator.of(context).pop(true);
      }
    } else if (onlineCheckoutRequired && safeCheckoutUrl.isNotEmpty) {
      final openedBooking = bookingRef.isNotEmpty ? bookingRef : publicRef;
      debugPrint(
        '[BOOK][CHECKOUT_OPEN] booking=$openedBooking urlPresent=true',
      );
      if (paymentBookingId.isNotEmpty) {
        markFluxidiPendingPaymentChecking(paymentBookingId: paymentBookingId);
      }
      if (mounted) {
        setState(() {
          _submitStateIsError = false;
          _submitState = _paymentCheckingStatusLabel();
        });
      }
      await _openPaymentUrl(safeCheckoutUrl);
      if (!mounted) return;
      if (_shouldReturnToOriginAfterSuccess && mounted) {
        Navigator.of(context).pop(true);
      }
    } else if (safeCheckoutUrl.isNotEmpty) {
      await _showBookingSuccessDialog(
        requiresPayment: true,
        paymentUrl: safeCheckoutUrl,
        publicRef: publicRef,
        paymentBookingId: paymentBookingId,
      );
      if (_shouldReturnToOriginAfterSuccess && mounted) {
        Navigator.of(context).pop(true);
      }
    } else if (mounted) {
      _showThemedSnackBar(successMessage);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (_shouldReturnToOriginAfterSuccess && mounted) {
        Navigator.of(context).pop(true);
      } else {
        _goToCustomerStartHome();
      }
    }
  }

  Map<String, dynamic>? _quoteAvailabilityMap() {
    final rawAvailability = widget.quote['availability'];
    if (rawAvailability is Map<String, dynamic>) return rawAvailability;
    if (rawAvailability is Map)
      return Map<String, dynamic>.from(rawAvailability);
    return null;
  }

  bool _quoteAvailabilityUsesDemandIndexTechnicalState() {
    final reasonCode = _availabilityReasonCodeFromMap(_quoteAvailabilityMap());
    return _isDemandIndexTechnicalAvailabilityReason(reasonCode);
  }

  bool _quoteAvailabilityBlocksBooking() {
    final availability = _quoteAvailabilityMap();
    if (availability == null) return false;
    if (availability['checked'] != true) return false;
    return availability['available'] == false;
  }

  String _availabilityUnavailableMessage() {
    if (_quoteAvailabilityUsesDemandIndexTechnicalState()) {
      return _localizedText(
        nl: 'Beschikbaarheid wordt vernieuwd. Bereken opnieuw of probeer straks opnieuw.',
        en: 'Availability is being refreshed. Recalculate or try again shortly.',
        fr: 'La disponibilité est en cours d’actualisation. Recalculez ou réessayez dans un instant.',
        es: 'La disponibilidad se está actualizando. Vuelve a calcular o inténtalo de nuevo en breve.',
      );
    }
    return _localizedText(
      nl: 'Geen voertuig beschikbaar op dit tijdstip. Kies een ander tijdstip en bereken opnieuw.',
      en: 'No vehicle is available at this time. Choose another time and recalculate.',
      fr: 'Aucun véhicule disponible à cet horaire. Choisissez un autre horaire et recalculez.',
      es: 'No hay vehículos disponibles en este horario. Elige otro horario y vuelve a calcular.',
    );
  }

  Future<void> _onConfirmBooking() async {
    FocusScope.of(context).unfocus();
    if (_quoteAvailabilityBlocksBooking()) {
      final availabilityMessage = _availabilityUnavailableMessage();
      _showThemedSnackBar(availabilityMessage);
      return;
    }
    if (!_visiblePaymentMethodIds.contains(_selectedPaymentMethodId)) {
      _showThemedSnackBar(_paymentMethodUnavailableMessage());
      return;
    }
    if (_isDisplayOnlyPaymentMethod(_selectedPaymentMethodId)) {
      _showThemedSnackBar(_displayOnlyPaymentMessage(_selectedPaymentMethodId));
      return;
    }
    if (_blockGooglePayBookSubmitWithMessage()) {
      return;
    }
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
    final publicPartnerId = _calcBusinessText(
      widget.payload['public_partner_id'] ??
          widget.payload['publicPartnerId'] ??
          widget.payload['partner_id'] ??
          widget.payload['partnerId'],
    );
    final selectedScope = _selectCalculatorBookingScope(
      publicPartnerId: publicPartnerId,
      entryContext: widget.entryContext,
      previewAssignedDriverId: widget.previewAssignedDriverId,
      previewAssignedVehicleId: widget.previewAssignedVehicleId,
    );
    final publicPartnerName = _calcBusinessText(
      widget.payload['public_partner_name'] ??
          widget.payload['publicPartnerName'],
    );
    if (name.isEmpty ||
        phone.isEmpty ||
        email.isEmpty ||
        !_isValidEmail(email)) {
      _showThemedSnackBar(
        widget.strings.bookingRequiredFieldsError.of(widget.language),
      );
      return;
    }
    if (selectedScope.isMissing) {
      if (widget.entryContext == BookingEntryContext.driver) {
        _showThemedSnackBar(
          _localizedText(
            nl: 'Geen actieve chauffeurssessie gevonden. Log opnieuw in als chauffeur en probeer het nog eens.',
            en: 'No active chauffeur session found. Log in again as chauffeur and retry.',
            fr: 'Aucune session chauffeur active trouvée. Reconnectez-vous en tant que chauffeur et réessayez.',
            es: 'No se encontró una sesión de chófer activa. Inicia sesión de nuevo como chófer e inténtalo otra vez.',
          ),
        );
        return;
      }
      final chooseCompanyMessage = widget.language == AppLanguage.en
          ? 'Please choose a taxi company first to complete your booking.'
          : widget.language == AppLanguage.fr
          ? 'Veuillez d abord choisir une compagnie de taxi pour finaliser votre reservation.'
          : widget.language == AppLanguage.es
          ? 'Primero elige una empresa de taxi para completar tu reserva.'
          : 'Kies eerst een taxibedrijf om je boeking te voltooien.';
      _showThemedSnackBar(chooseCompanyMessage);
      return;
    }

    String? driverSessionTokenForBook;
    if (widget.entryContext == BookingEntryContext.driver) {
      final driverSession = activeDriverSessionNotifier.value;
      driverSessionTokenForBook = (driverSession?.driverSessionToken ?? '')
          .trim();
      debugPrint(
        '[CALCULATOR][DRIVER_BOOK_AUTH] token_present=${driverSessionTokenForBook.isNotEmpty} driver=${_maskCalculatorScopeId((driverSession?.driverId ?? '').trim())}',
      );
      if (driverSessionTokenForBook.isEmpty) {
        _showThemedSnackBar(
          _localizedText(
            nl: 'Geen actieve chauffeurssessie gevonden. Log opnieuw in als chauffeur en probeer het nog eens.',
            en: 'No active chauffeur session found. Log in again as chauffeur and retry.',
            fr: 'Aucune session chauffeur active trouvée. Reconnectez-vous en tant que chauffeur et réessayez.',
            es: 'No se encontró una sesión de chófer activa. Inicia sesión de nuevo como chófer e inténtalo otra vez.',
          ),
        );
        return;
      }
    }

    final customerSession = _allowsCustomerSessionLink
        ? await CustomerSessionStore.instance.loadValidSession()
        : null;
    final sessionCustomerId = _allowsCustomerSessionLink
        ? (customerSession?.customerId ?? '').trim()
        : '';
    final customerSessionToken = _allowsCustomerSessionLink
        ? (customerSession?.customerSessionToken ?? '').trim()
        : '';
    final sessionPhoneE164 = _allowsCustomerSessionLink
        ? (customerSession?.phoneE164 ?? '').trim()
        : '';
    final useSessionPhoneForBooking =
        _allowsCustomerSessionLink && sessionPhoneE164.isNotEmpty;
    final payloadPhone = useSessionPhoneForBooking ? sessionPhoneE164 : phone;
    debugPrint(
      '[BOOK][CUSTOMER_SESSION_PHONE] used=${useSessionPhoneForBooking ? "true" : "false"}',
    );

    final createdByRole = switch (widget.entryContext) {
      BookingEntryContext.customer => 'customer',
      BookingEntryContext.companyAdmin => 'company_admin',
      BookingEntryContext.driver => 'driver',
    };
    final bookingSource = switch (widget.entryContext) {
      BookingEntryContext.customer => 'flutter_app',
      BookingEntryContext.companyAdmin => 'company_admin_app',
      BookingEntryContext.driver => 'driver_app',
    };
    final customerLinkMode = _allowsCustomerSessionLink
        ? 'customer_session_or_contact'
        : 'explicit_only';
    debugPrint(
      '[CUSTOMER_BOOKING_CREATE][IDENTITY] hasCustomerId=${sessionCustomerId.isNotEmpty} hasToken=${customerSessionToken.isNotEmpty}',
    );

    final paymentSelection = _bookingPaymentSelection;

    final payload = <String, dynamic>{
      ...widget.payload, // keep quote payload keys unchanged
      'tenant_id': selectedScope.tenantId,
      'company_id': selectedScope.companyId,
      'tenantId': selectedScope.tenantId,
      'companyId': selectedScope.companyId,
      if ((selectedScope.driverId ?? '').trim().isNotEmpty) ...{
        'driver_id': selectedScope.driverId,
        'driverId': selectedScope.driverId,
        'assigned_driver_id': selectedScope.driverId,
        'assignedDriverId': selectedScope.driverId,
      },
      if ((selectedScope.assignedVehicleId ?? '').trim().isNotEmpty) ...{
        'assigned_vehicle_id': selectedScope.assignedVehicleId,
        'assignedVehicleId': selectedScope.assignedVehicleId,
      },
      // Partner routing keys must never accompany a driver-entry booking:
      // the Worker re-routes tenant scope from public_partner_id.
      if (publicPartnerId.isNotEmpty &&
          widget.entryContext != BookingEntryContext.driver) ...{
        'public_partner_id': publicPartnerId,
        'publicPartnerId': publicPartnerId,
        'partner_id': publicPartnerId,
        'partnerId': publicPartnerId,
        if (publicPartnerName.isNotEmpty)
          'public_partner_name': publicPartnerName,
        if (publicPartnerName.isNotEmpty)
          'publicPartnerName': publicPartnerName,
      },
      'booking_source': bookingSource,
      'entry_channel': 'flutter_calculator',
      'created_by_role': createdByRole,
      'customer_link_mode': customerLinkMode,
      'suppress_device_customer_session_link': !_allowsCustomerSessionLink,
      'source_context': <String, dynamic>{
        'role': createdByRole,
        'language': widget.language.name,
        'surface': 'calculator_confirmation',
      },
      // Keep website-compatible aliases
      'return_enabled': (widget.payload['return'] ?? false) == true,
      'extra_service_key': widget.payload['extra_service'] ?? 'NONE',
      // Mollie return-to-app deep link. The Worker uses this to redirect the
      // browser back into the Fluxidi app after a successful payment.
      'return_url': kFluxidiPaymentReturnUrl,
      ...paymentSelection.toPayloadFields(),
      'customer': <String, dynamic>{
        'name': name,
        'full_name': name,
        'phone': payloadPhone,
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
        if (sessionCustomerId.isNotEmpty) ...{
          'customer_id': sessionCustomerId,
          'customerId': sessionCustomerId,
        },
        if (useSessionPhoneForBooking) ...{
          'phone_e164': sessionPhoneE164,
          'customer_phone_e164': sessionPhoneE164,
          'customerPhoneE164': sessionPhoneE164,
        },
      },
      'name': name,
      'phone': payloadPhone,
      'email': email,
      'customer_name': name,
      'customer_phone': payloadPhone,
      'customerPhone': payloadPhone,
      'customer_email': email,
      if (sessionCustomerId.isNotEmpty) ...{
        'customer_id': sessionCustomerId,
        'customerId': sessionCustomerId,
      },
      if (useSessionPhoneForBooking) ...{
        'phone_e164': sessionPhoneE164,
        'customer_phone_e164': sessionPhoneE164,
        'customerPhoneE164': sessionPhoneE164,
      },
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
      debugPrint(
        '[CALCULATOR][BOOK_SCOPE] tenant=${selectedScope.tenantId} company=${selectedScope.companyId}',
      );
      _logBusinessPayload(stage: 'book', payload: payload);
      if (_blockGooglePayBookSubmitWithMessage()) {
        if (mounted) {
          setState(() {
            _submitting = false;
          });
        }
        return;
      }
      final body = await _postBookAndDecode(
        payload,
        customerSessionToken: customerSessionToken,
        driverSessionToken: driverSessionTokenForBook,
        entryContext: widget.entryContext,
      );
      if (body == null) {
        throw Exception('book_response_missing');
      }
      await _handleBookSuccess(
        body: body,
        payload: payload,
        name: name,
        phone: phone,
        email: email,
        effectiveCompanyName: effectiveCompanyName,
        effectiveVatNumber: effectiveVatNumber,
        effectiveInvoiceEmail: effectiveInvoiceEmail,
        effectiveInvoiceAddress: effectiveInvoiceAddress,
        businessPayload: businessPayload,
        customerSession: customerSession,
        selectedScope: selectedScope,
      );
    } catch (e) {
      if (!mounted) return;
      final rawErr = e.toString().replaceFirst('Exception: ', '').trim();
      if (_isBookingTransportError(rawErr)) {
        setState(() {
          _submitState = _bookingCheckingStatusLabel();
          _submitStateIsError = false;
        });
        final verified = await _verifyBookAfterTransportError(
          payload,
          customerSessionToken: customerSessionToken,
          driverSessionToken: driverSessionTokenForBook,
        );
        if (!mounted) return;
        if (verified != null) {
          await _handleBookSuccess(
            body: verified,
            payload: payload,
            name: name,
            phone: phone,
            email: email,
            effectiveCompanyName: effectiveCompanyName,
            effectiveVatNumber: effectiveVatNumber,
            effectiveInvoiceEmail: effectiveInvoiceEmail,
            effectiveInvoiceAddress: effectiveInvoiceAddress,
            businessPayload: businessPayload,
            customerSession: customerSession,
            selectedScope: selectedScope,
          );
          return;
        }
        final uncertain = _bookingUncertainStatusLabel();
        setState(() {
          _submitState = uncertain;
          _submitStateIsError = false;
        });
        _showThemedSnackBar(uncertain);
        return;
      }
      final friendlyErr = _friendlyBookingError(rawErr);
      final msg =
          '${widget.strings.bookingSubmitFailedPrefix.of(widget.language)}: $friendlyErr';
      setState(() {
        _submitState = msg;
        _submitStateIsError = true;
      });
      _showThemedSnackBar(msg);
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
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
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        title: Text(
          widget.strings.bookingConfirmationTitle.of(widget.language),
          style: TextStyle(color: _textPrimary),
        ),
        iconTheme: IconThemeData(color: _textPrimary),
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
                    Icon(Icons.place_outlined, size: 16, color: _gold),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        from,
                        style: TextStyle(
                          color: _textPrimary,
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
                    color: _textMuted.withOpacity(0.8),
                  ),
                ),
                Row(
                  children: [
                    Icon(Icons.flag_outlined, size: 16, color: _gold),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        to,
                        style: TextStyle(
                          color: _textPrimary,
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
            child: Text('$date  $time', style: TextStyle(color: _textPrimary)),
          ),
          const SizedBox(height: 9),
          if (returnTrip) ...[
            _sectionCard(
              title: widget.strings.bookingSummaryReturnLabel.of(
                widget.language,
              ),
              child: Text(
                widget.strings.commonYesLabel.of(widget.language),
                style: TextStyle(color: _textPrimary),
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
                style: TextStyle(color: _textPrimary),
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
                style: TextStyle(color: _textPrimary),
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
                    color: _panelAlt.withOpacity(_isDarkTheme ? 0.78 : 0.92),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          distanceLabel,
                          style: TextStyle(color: _textMuted, fontSize: 11.5),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${_fmt(showTotalMetrics ? totalDisplayDistance : distanceKm, decimals: 2)} ${widget.distanceUnitLabel}',
                        style: TextStyle(
                          color: _textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          durationLabel,
                          textAlign: TextAlign.right,
                          style: TextStyle(color: _textMuted, fontSize: 11.5),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${_fmt(showTotalMetrics ? totalDisplayDuration : durationMin, decimals: 0)} ${widget.durationUnitLabel}',
                        style: TextStyle(
                          color: _textPrimary,
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
                    color: _panelAlt.withOpacity(_isDarkTheme ? 0.82 : 0.95),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _border.withOpacity(_isDarkTheme ? 0.45 : 1),
                    ),
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
                          style: TextStyle(
                            color: _textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                      Text(
                        '${widget.currencySymbol} ${_fmt(totalIncl)}',
                        style: TextStyle(
                          color: _gold,
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
                      color: _textMuted.withOpacity(0.9),
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
                          color: _textMuted.withOpacity(0.88),
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
            title: _paymentChoiceTitle(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _paymentChoiceSubtitle(),
                  style: TextStyle(
                    color: _textMuted.withOpacity(0.9),
                    fontSize: 11.5,
                    height: 1.2,
                  ),
                ),
                if (_onlinePaymentsBlockedMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _onlinePaymentsBlockedMessage!,
                    style: TextStyle(
                      color: _textMuted.withOpacity(0.95),
                      fontSize: 11,
                      height: 1.25,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                for (var i = 0; i < _visiblePaymentMethodIds.length; i++) ...[
                  if (i > 0) const SizedBox(height: 7),
                  _paymentMethodChoiceOption(_visiblePaymentMethodIds[i]),
                ],
              ],
            ),
          ),
          const SizedBox(height: 9),
          _sectionCard(
            title: _allowsCustomerSessionLink
                ? widget.strings.bookingCustomerSectionTitle.of(widget.language)
                : _localizedText(
                    nl: 'Passagiersgegevens',
                    en: 'Passenger details',
                    fr: 'Détails du passager',
                    es: 'Datos del pasajero',
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
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _vatNumberCtrl,
                  builder: (_, value, __) => _input(
                    _vatNumberCtrl,
                    widget.strings.bookingVatNumberOptionalLabel.of(
                      widget.language,
                    ),
                    icon: Icons.receipt_long_outlined,
                    suffixIcon: value.text.trim().isEmpty
                        ? null
                        : IconButton(
                            tooltip: _localizedText(
                              nl: 'BTW-nummer wissen',
                              en: 'Clear VAT number',
                              fr: 'Effacer le numéro de TVA',
                              es: 'Borrar número de IVA',
                            ),
                            icon: Icon(
                              Icons.delete_outline,
                              size: 18,
                              color: _gold.withOpacity(0.92),
                            ),
                            onPressed: () => _vatNumberCtrl.clear(),
                          ),
                  ),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.strings.bookingVatNumberHelpText.of(widget.language),
                    style: TextStyle(color: _textMuted, fontSize: 12),
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
                border: Border.all(color: _gold.withOpacity(0.5)),
                gradient: LinearGradient(
                  colors: [
                    _gold.withOpacity(0.95),
                    _visualTheme.bronze.withOpacity(0.95),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: _gold.withOpacity(0.18),
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
                    style: TextStyle(
                      color: _actionOnGold,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: _actionOnGold,
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
                color: _submitStateIsError ? _danger : _success,
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
                      style: TextStyle(color: _textPrimary),
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
        color: _panel.withOpacity(0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border.withOpacity(_isDarkTheme ? 0.45 : 1)),
        boxShadow: [
          BoxShadow(
            color: _gold.withOpacity(_isDarkTheme ? 0.08 : 0.05),
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
              color: _textPrimary.withOpacity(0.95),
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
          color: _panelAlt.withOpacity(_isDarkTheme ? 0.78 : 0.92),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: _border.withOpacity(_isDarkTheme ? 0.45 : 1),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: _gold),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                text,
                style: TextStyle(
                  color: _textPrimary,
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
              style: TextStyle(
                color: _textMuted,
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
                color: emphasizeValue ? _gold : _textPrimary,
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
    Widget? suffixIcon,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: TextStyle(color: _textPrimary),
      cursorColor: _gold,
      decoration: InputDecoration(
        hintText: label,
        hintStyle: TextStyle(color: _textMuted),
        prefixIcon: icon == null ? null : Icon(icon, size: 18, color: _gold),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: _panelAlt.withOpacity(_isDarkTheme ? 0.82 : 0.92),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: _border.withOpacity(_isDarkTheme ? 0.45 : 1),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: _border.withOpacity(_isDarkTheme ? 0.45 : 1),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _gold.withOpacity(0.7), width: 1.1),
        ),
      ),
    );
  }
}
