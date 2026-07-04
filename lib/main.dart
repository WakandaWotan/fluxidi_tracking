import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'dart:convert';
import 'dart:io' show Directory, File, FileMode, Platform;
import 'dart:math' as math;
import 'dart:ui' as ui show ImageByteFormat;

import 'package:flutter/foundation.dart'
    show ValueListenable, ValueNotifier, kDebugMode, kIsWeb, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_email_sender/flutter_email_sender.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:http/http.dart' as http;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:fluxidi_tracking/calculator_page.dart';
import 'package:fluxidi_tracking/active_local_customer_store.dart';
import 'package:fluxidi_tracking/customer_booking_store.dart';
import 'package:fluxidi_tracking/customer_bookings_store.dart';
import 'package:fluxidi_tracking/customer_phone_recovery_page.dart';
import 'package:fluxidi_tracking/customer_profile_store.dart';
import 'package:fluxidi_tracking/customer_session_store.dart';
import 'package:fluxidi_tracking/customer_theme_page.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/customer_theme_store.dart';
import 'package:fluxidi_tracking/payment_return.dart';
export 'package:fluxidi_tracking/payment_return.dart'
    show
        kFluxidiPaymentReturnScheme,
        kFluxidiPaymentReturnHost,
        kFluxidiPaymentReturnUrl,
        FluxidiPaymentStatus,
        FluxidiPendingPayment,
        fluxidiPendingPaymentNotifier,
        setFluxidiPendingPayment,
        clearFluxidiPendingPayment,
        paymentReturnCoordinator,
        PaymentReturnCoordinator;
import 'package:fluxidi_tracking/business_first_run_wizard_page.dart';
import 'package:fluxidi_tracking/main_parts/business_help_manual_page.dart';
import 'package:fluxidi_tracking/business_orientation_flow_page.dart';
import 'package:fluxidi_tracking/business_settings_page.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';
import 'package:fluxidi_tracking/vehicle_management_page.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/document_core/document_core_models.dart';
import 'package:fluxidi_tracking/document_core/document_compliance_profile.dart';
import 'package:fluxidi_tracking/document_core/document_preflight.dart';
import 'package:fluxidi_tracking/company/booking_documents_leg_filter.dart';
import 'package:fluxidi_tracking/company/booking_peppol_readiness.dart';
import 'package:fluxidi_tracking/company_session_store.dart';
import 'package:fluxidi_tracking/company_onboarding_page.dart';
import 'package:fluxidi_tracking/chiron_compliance_dashboard_page.dart';
import 'package:fluxidi_tracking/company_driver_management_page.dart';
import 'package:fluxidi_tracking/compliance_ledger_reader.dart';
import 'package:fluxidi_tracking/compliance_register_receipt_bridge.dart';
import 'package:fluxidi_tracking/local_ride_assignment_cache.dart';
import 'package:fluxidi_tracking/driver_documents_store.dart';
import 'package:fluxidi_tracking/driver_document_sheet.dart';
import 'package:fluxidi_tracking/driver_my_documents_page.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';
import 'package:fluxidi_tracking/company_driver_view_theme_store.dart';
import 'package:fluxidi_tracking/driver_app_theme_store.dart';
import 'package:fluxidi_tracking/driver_theme_store.dart';
import 'package:fluxidi_tracking/driver_creator_dialog.dart';
import 'package:fluxidi_tracking/driver_session_store.dart';
import 'package:fluxidi_tracking/fluxidi_responsive.dart';
import 'package:fluxidi_tracking/security/fluxidi_app_lock_gate_page.dart';
import 'airport/airport_page.dart';
import 'driver_login_qr_scanner_page.dart';
import 'events/events_page.dart';
import 'hotels/hotels_page.dart';
import 'nearby_partners_page.dart';
import 'navigation/driver_navigation_formatters.dart';
import 'navigation/driver_navigation_draw_state.dart';
import 'navigation/driver_navigation_directions_request.dart';
import 'navigation/driver_navigation_geometry.dart';
import 'navigation/driver_navigation_instruction_state.dart';
import 'navigation/driver_navigation_location_config.dart';
import 'navigation/driver_navigation_map_config.dart';
import 'navigation/driver_navigation_models.dart';
import 'navigation/driver_navigation_route_parser.dart';

import 'widgets/cockpit_widget.dart';
import 'widgets/direct_ride_destination_dialog.dart';
import 'widgets/direct_ride_estimate_panel.dart';
import 'widgets/driver_nav_banners.dart';
import 'widgets/route_marquee.dart';

part 'main_parts/fluxidi_painters.dart';
part 'main_parts/fluxidi_shell_widgets.dart';
part 'main_parts/company_bookings_helpers.dart';
part 'main_parts/company_bookings_overview_page.dart';
part 'main_parts/company_subscription_billing_state.dart';
part 'main_parts/business_regional_demand_page_state.dart';
part 'main_parts/customer_profile_edit_page_state.dart';
part 'main_parts/customer_region_registration_page_state.dart';
part 'main_parts/customer_home_page.dart';
part 'main_parts/customer_booking_view.dart';
part 'main_parts/customer_saved_bookings_page.dart';
part 'main_parts/customer_bookings_page.dart';
part 'main_parts/customer_booking_lookup_page.dart';
part 'main_parts/customer_booking_detail_page.dart';
part 'main_parts/trip_history_page.dart';
part 'main_parts/chauffeur_login_page.dart';
part 'main_parts/receipt_text_helpers.dart';
part 'main_parts/booking_item_model.dart';
part 'main_parts/receipt_pdf_preview_page.dart';
part 'main_parts/receipt_pdf_action_runner.dart';
part 'main_parts/company_booking_credit_refund_pdf_action_runner.dart';
part 'main_parts/company_booking_documents_section.dart';
part 'document_core/company_credit_note_draft_builder.dart';
part 'main_parts/bookings_hub_page.dart';
part 'main_parts/company_driver_management_page_body.dart';
part 'main_parts/ride_receipt_body_state.dart';
part 'main_parts/business_home_page_state.dart';
part 'main_parts/role_entry_page.dart';
part 'main_parts/driver_home_page_state.dart';
part 'main_parts/company_driver_management_page_state.dart';
part 'main_parts/customer_onboarding_page.dart';
part 'main_parts/trip_history_receipt_helpers.dart';
part 'main_parts/customer_booking_lifecycle_helpers.dart';
part 'main_parts/tracking_payment_overlay.dart';
part 'main_parts/customer_session_bootstrap.dart';
part 'main_parts/driver_booking_scope_helpers.dart';
part 'main_parts/compliance_local_stores.dart';

final bool kIsWindows = !kIsWeb && Platform.isWindows;

CustomerProfile? _cachedCustomerProfile;
bool _startInCompanyAdminHome = false;
bool _startInDriverHome = false;
bool _startupBlockedCompanySessionRecovery = false;
final RouteObserver<PageRoute<dynamic>> kAppRouteObserver =
    RouteObserver<PageRoute<dynamic>>();

Future<void> _refreshCachedCustomerProfile() async {
  _cachedCustomerProfile = await CustomerProfileStore.instance.load();
}

void _clearCachedCustomerProfile() {
  _cachedCustomerProfile = null;
}

void _setCachedCustomerProfile(CustomerProfile profile) {
  _cachedCustomerProfile = profile;
}

String _businessFieldText(dynamic value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty || text.toLowerCase() == 'null') return '';
  return text;
}

String _firstBusinessFieldText(List<dynamic> values) {
  for (final value in values) {
    final text = _businessFieldText(value);
    if (text.isNotEmpty) return text;
  }
  return '';
}

bool _businessFieldBool(dynamic value) {
  if (value is bool) return value;
  final text = _businessFieldText(value).toLowerCase();
  return text == '1' || text == 'true' || text == 'yes' || text == 'ja';
}

Map<String, dynamic> _deriveCustomerBusinessInvoicePayload({
  required Map<String, dynamic> source,
}) {
  final companyName = _firstBusinessFieldText([
    source['company_name'],
    source['companyName'],
    source['customer_company'],
    source['customerCompany'],
  ]);
  final vatNumber = _firstBusinessFieldText([
    source['vat_number'],
    source['vatNumber'],
    source['customer_vat'],
    source['customerVat'],
  ]);
  final hasVat = vatNumber.isNotEmpty;
  final isBusiness = hasVat;
  final invoiceRequested = hasVat;
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
      ? _firstBusinessFieldText([
          source['invoice_email'],
          source['invoiceEmail'],
        ])
      : _firstBusinessFieldText([
          source['invoice_email'],
          source['invoiceEmail'],
        ]);
  final invoiceAddress = _firstBusinessFieldText([
    source['invoice_address'],
    source['invoiceAddress'],
    source['billing_address'],
    source['billingAddress'],
    source['company_address'],
    source['companyAddress'],
  ]);

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

/// White-label config aliases (keeps existing code paths stable).
final String kAppTitle = appConfig.appTitle;
final String kCompanyName = appConfig.companyName;
String get kBookingsTitle =>
    appConfig.strings.bookingsTitle.of(appConfig.currentLanguage);
String get kLiveRideTitle =>
    appConfig.strings.liveRideTitle.of(appConfig.currentLanguage);
String get kActiveRideTitle =>
    appConfig.strings.activeRideTitle.of(appConfig.currentLanguage);
String get kRefreshBookingsLabel =>
    appConfig.strings.refreshBookingsLabel.of(appConfig.currentLanguage);
String get kCenterOnMeLabel =>
    appConfig.strings.centerOnMeLabel.of(appConfig.currentLanguage);
String get kDrawerDriverIdLabel =>
    appConfig.strings.drawerDriverIdLabel.of(appConfig.currentLanguage);
String get kDrawerWorkerLabel =>
    appConfig.strings.drawerWorkerLabel.of(appConfig.currentLanguage);
String get kDrawerMapboxTokenLabel =>
    appConfig.strings.drawerMapboxTokenLabel.of(appConfig.currentLanguage);
String get kDrawerLanguageLabel =>
    appConfig.strings.drawerLanguageLabel.of(appConfig.currentLanguage);
String get kDrawerBusinessSettingsLabel =>
    appConfig.strings.drawerBusinessSettingsLabel.of(appConfig.currentLanguage);
String get kDrawerBusinessSettingsSubtitle => appConfig
    .strings
    .drawerBusinessSettingsSubtitle
    .of(appConfig.currentLanguage);
String get kDrawerVehiclesLabel =>
    appConfig.strings.drawerVehiclesLabel.of(appConfig.currentLanguage);
String get kDrawerVehiclesSubtitle =>
    appConfig.strings.drawerVehiclesSubtitle.of(appConfig.currentLanguage);
String get kFollowCarLabel =>
    appConfig.strings.followCarLabel.of(appConfig.currentLanguage);
String get kFollowCarSubtitle =>
    appConfig.strings.followCarSubtitle.of(appConfig.currentLanguage);
String get kBookingsMenuSubtitle =>
    appConfig.strings.bookingsMenuSubtitle.of(appConfig.currentLanguage);
String get kLiveRideMenuSubtitle =>
    appConfig.strings.liveRideMenuSubtitle.of(appConfig.currentLanguage);
String get kCalculatorMenuSubtitle =>
    appConfig.strings.calculatorMenuSubtitle.of(appConfig.currentLanguage);
String get kActiveRideMenuSubtitle =>
    appConfig.strings.activeRideMenuSubtitle.of(appConfig.currentLanguage);
String get kAvailableBookingsTitle =>
    appConfig.strings.availableBookingsTitle.of(appConfig.currentLanguage);
String get kRefreshShortLabel =>
    appConfig.strings.refreshShortLabel.of(appConfig.currentLanguage);
String get kBookingsEmptyLabel =>
    appConfig.strings.bookingsEmptyLabel.of(appConfig.currentLanguage);
String get kStopShortLabel =>
    appConfig.strings.stopShortLabel.of(appConfig.currentLanguage);
String get kRideActionCompletedLabel =>
    appConfig.strings.rideActionCompletedLabel.of(appConfig.currentLanguage);
String get kRideActionCancelledLabel =>
    appConfig.strings.rideActionCancelledLabel.of(appConfig.currentLanguage);
String get kRideGoToRideLabel =>
    appConfig.strings.rideGoToRideLabel.of(appConfig.currentLanguage);
String get kRideDeleteLabel =>
    appConfig.strings.rideDeleteLabel.of(appConfig.currentLanguage);
String get kRideStatusPendingLabel =>
    appConfig.strings.rideStatusPendingLabel.of(appConfig.currentLanguage);
String get kPickupLabel =>
    appConfig.strings.pickupLabel.of(appConfig.currentLanguage);
String get kDropoffLabel =>
    appConfig.strings.dropoffLabel.of(appConfig.currentLanguage);
final String kDefaultCurrency = appConfig.defaultCurrency;
final Color kGlow = appConfig.accentColor;

Map<String, String> _adminHeaders() {
  final t = kAdminToken.trim();
  if (t.isEmpty) return <String, String>{};
  return <String, String>{'Authorization': 'Bearer $t', 'x-admin-token': t};
}

String _maskScopeForLog(String value) {
  final text = value.trim();
  if (text.isEmpty) return '—';
  if (text.length <= 4) return '…${text.substring(text.length - 1)}';
  return '${text.substring(0, 2)}…${text.substring(text.length - 2)}';
}

String _shortDriverIdForDiag(String value) {
  final text = value.trim();
  if (text.isEmpty) return 'unknown';
  if (text.length <= 4) return '…${text.substring(text.length - 1)}';
  return '${text.substring(0, 2)}…${text.substring(text.length - 2)}';
}

String _shortUrlForDiag(String value) {
  final raw = value.trim();
  if (raw.isEmpty) return '—';
  try {
    final uri = Uri.parse(raw);
    final host = uri.host.trim();
    final path = uri.path.trim();
    final head = host.isNotEmpty
        ? '$host${path.isNotEmpty ? path : '/'}'
        : (path.isNotEmpty ? path : raw);
    return head.length <= 80 ? head : '${head.substring(0, 80)}…';
  } catch (_) {
    return raw.length <= 80 ? raw : '${raw.substring(0, 80)}…';
  }
}

String _shortErrorForDiag(Object error) {
  final text = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.isEmpty) return 'unknown';
  return text.length <= 180 ? text : '${text.substring(0, 180)}…';
}

String _lastBridgeBootstrapCompanyId = '';
DateTime? _lastBridgeBootstrapAtUtc;

void _markBridgeBootstrapHydrated(String companyId) {
  final normalized = companyId.trim();
  if (normalized.isEmpty) return;
  _lastBridgeBootstrapCompanyId = normalized;
  _lastBridgeBootstrapAtUtc = DateTime.now().toUtc();
}

bool _isBridgeBootstrapFreshForCompany(String companyId) {
  final normalized = companyId.trim();
  final stamp = _lastBridgeBootstrapAtUtc;
  if (normalized.isEmpty || stamp == null) return false;
  if (_lastBridgeBootstrapCompanyId != normalized) return false;
  final age = DateTime.now().toUtc().difference(stamp);
  return age <= const Duration(minutes: 10);
}

typedef _BridgeTranslator =
    String Function({
      required String nl,
      required String en,
      required String fr,
      required String es,
    });

String _normalizeBridgeTextGlobal(String raw) {
  return raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

String _maskBridgeDriverIdGlobal(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return '—';
  if (text.length <= 4) return '…${text.substring(text.length - 1)}';
  return '${text.substring(0, 2)}…${text.substring(text.length - 2)}';
}

bool _isCompanyAdminDriverViewSession(ActiveDriverSession? session) {
  return session?.isCompanyAdminDriverViewSession == true;
}

bool _isSeededOrPlaceholderBridgeDriver(DriverProfile driver) {
  return isSeededOrPlaceholderDriver(driver);
}

bool _isBusinessAdminPreviewEligibleDriver(DriverProfile driver) {
  final driverId = driver.id.trim();
  final companyId = (driver.companyId ?? '').trim();
  if (!driver.isActive) return false;
  if (_isSeededOrPlaceholderBridgeDriver(driver)) return false;
  if (driverId.isEmpty) return false;
  return fleetRecordBelongsToActiveCompanyOrLegacy(companyId);
}

List<DriverProfile> _resolveSelectableDriverBridgeCandidatesGlobal({
  bool logCandidates = true,
  bool requireEmployeeNumber = true,
}) {
  return _resolveDriverBridgeCandidatesReportGlobal(
    logCandidates: logCandidates,
    requireEmployeeNumber: requireEmployeeNumber,
  ).selectable;
}

List<DriverProfile> _resolveBusinessAdminDriverBridgeCandidatesGlobal({
  bool logCandidates = true,
}) {
  return _resolveSelectableDriverBridgeCandidatesGlobal(
    logCandidates: logCandidates,
    requireEmployeeNumber: false,
  );
}

DriverProfile? _findBusinessAdminEligibleDriverByIdGlobal(String driverId) {
  final normalized = driverId.trim();
  if (normalized.isEmpty) return null;
  for (final driver in driversNotifier.value) {
    if (driver.id.trim() == normalized &&
        _isBusinessAdminPreviewEligibleDriver(driver)) {
      return driver;
    }
  }
  return null;
}

String? _resolveFleetVehicleIdForDriverGlobal(String driverId) {
  final activeCompany = resolvedCompanyId.trim().isNotEmpty
      ? resolvedCompanyId.trim()
      : kOutboundTenantId.trim();
  return resolveFleetVehicleIdForDriver(
    driverId,
    companyId: activeCompany.isNotEmpty ? activeCompany : null,
  );
}

bool _isOperationalCockpitDriverGlobal(
  DriverProfile driver, {
  required String companyId,
}) {
  if (!_isBusinessAdminPreviewEligibleDriver(driver)) return false;
  return resolveFleetVehicleIdForDriver(driver.id, companyId: companyId) !=
      null;
}

List<DriverProfile> _resolveOperationalCockpitDriverBridgeCandidatesGlobal({
  String? companyId,
  String? excludeDriverId,
  bool logCandidates = true,
}) {
  final scopedCompanyId =
      (companyId ?? resolveActiveCompanyIdForFleetUi() ?? '').trim();
  final excluded = (excludeDriverId ?? '').trim();
  final eligible = resolveOperationalCockpitEligibleDrivers(
    companyId: scopedCompanyId.isEmpty ? null : scopedCompanyId,
    logCandidates: logCandidates,
  );
  return eligible
      .map((entry) => entry.driver)
      .where((driver) => excluded.isEmpty || driver.id.trim() != excluded)
      .toList(growable: false);
}

({DriverProfile? driver, String reason})
_resolveBusinessDriverForPreviewGlobal({
  required String tenantId,
  required String companyId,
  BusinessDriverPreviewRecord? savedPreview,
}) {
  final scopedCompanyId = companyId.trim();

  bool tryOperationalPreviewDriver(
    DriverProfile driver, {
    required String selectReason,
    String? savedVehicleId,
  }) {
    if (!_isOperationalCockpitDriverGlobal(
      driver,
      companyId: scopedCompanyId,
    )) {
      debugPrint(
        '[DRIVER_OWNER_BRIDGE][SKIP_PREVIEW] driver=${_maskBridgeDriverIdGlobal(driver.id)} reason=unassigned',
      );
      return false;
    }
    final linkedVehicleId = resolveFleetVehicleIdForDriver(
      driver.id,
      companyId: scopedCompanyId,
    );
    if ((savedVehicleId ?? '').trim().isNotEmpty &&
        linkedVehicleId != savedVehicleId!.trim()) {
      debugPrint(
        '[DRIVER_OWNER_BRIDGE][SKIP_PREVIEW] driver=${_maskBridgeDriverIdGlobal(driver.id)} reason=vehicle_changed vehicle=${_maskBridgeDriverIdGlobal(savedVehicleId)}',
      );
      return false;
    }
    debugPrint(
      '[DRIVER_VIEW_ORIGIN][MANUAL_PREVIEW_LOCK] driver=${_maskBridgeDriverIdGlobal(driver.id)} vehicle=${_maskBridgeDriverIdGlobal(linkedVehicleId ?? '')}',
    );
    debugPrint(
      '[DRIVER_OWNER_BRIDGE][SELECT] driver=${_maskBridgeDriverIdGlobal(driver.id)} reason=$selectReason',
    );
    return true;
  }

  if (savedPreview != null) {
    final previewDriverId = savedPreview.driverId.trim();
    DriverProfile? rawPreviewDriver;
    for (final driver in driversNotifier.value) {
      if (driver.id.trim() == previewDriverId) {
        rawPreviewDriver = driver;
        break;
      }
    }
    if (rawPreviewDriver != null && !rawPreviewDriver.isActive) {
      debugPrint(
        '[DRIVER_OWNER_BRIDGE][SKIP_PREVIEW] driver=${_maskBridgeDriverIdGlobal(previewDriverId)} reason=inactive',
      );
    } else if (rawPreviewDriver != null &&
        isSeededOrPlaceholderDriver(rawPreviewDriver)) {
      debugPrint(
        '[DRIVER_OWNER_BRIDGE][SKIP_PREVIEW] driver=${_maskBridgeDriverIdGlobal(previewDriverId)} reason=placeholder',
      );
    } else {
      final previewDriver = _findBusinessAdminEligibleDriverByIdGlobal(
        previewDriverId,
      );
      if (previewDriver == null) {
        debugPrint(
          '[DRIVER_OWNER_BRIDGE][SKIP_PREVIEW] driver=${_maskBridgeDriverIdGlobal(previewDriverId)} reason=missing_driver',
        );
      } else if (tryOperationalPreviewDriver(
        previewDriver,
        selectReason: 'saved_preview',
        savedVehicleId: savedPreview.vehicleId,
      )) {
        return (driver: previewDriver, reason: 'saved_preview');
      }
    }
  }

  final primaryVehicleId = resolvePrimaryFleetVehicleId(
    companyId: scopedCompanyId,
  );
  if (primaryVehicleId != null) {
    final vehicleDriverId = resolveFleetDriverIdForVehicle(
      primaryVehicleId,
      companyId: scopedCompanyId,
    );
    if ((vehicleDriverId ?? '').trim().isNotEmpty) {
      final vehicleDriver = _findBusinessAdminEligibleDriverByIdGlobal(
        vehicleDriverId!,
      );
      if (vehicleDriver != null &&
          _isOperationalCockpitDriverGlobal(
            vehicleDriver,
            companyId: scopedCompanyId,
          )) {
        debugPrint(
          '[DRIVER_OWNER_BRIDGE][SELECT] driver=${_maskBridgeDriverIdGlobal(vehicleDriver.id)} reason=vehicle_assignment vehicle=${_maskBridgeDriverIdGlobal(primaryVehicleId)}',
        );
        return (driver: vehicleDriver, reason: 'vehicle_assignment');
      }
    }
  }

  final operationalDrivers =
      _resolveOperationalCockpitDriverBridgeCandidatesGlobal(
        companyId: scopedCompanyId,
        logCandidates: true,
      );
  if (operationalDrivers.isNotEmpty) {
    final firstDriver = operationalDrivers.first;
    debugPrint(
      '[DRIVER_OWNER_BRIDGE][SELECT] driver=${_maskBridgeDriverIdGlobal(firstDriver.id)} reason=first_assigned_driver',
    );
    return (driver: firstDriver, reason: 'first_assigned_driver');
  }

  return (driver: null, reason: 'no_match');
}

String _canonicalDriverPortraitUrlGlobal(DriverProfile driver) {
  return (driver.publicPortraitUrl ?? '').trim();
}

Future<void> _saveBusinessDriverPreviewFromProfileGlobal(
  DriverProfile driver, {
  required String tenantId,
  required String companyId,
}) async {
  final photo = _canonicalDriverPortraitUrlGlobal(driver);
  await DriverSessionStore.instance.saveBusinessDriverPreview(
    BusinessDriverPreviewRecord(
      tenantId: tenantId,
      companyId: companyId,
      driverId: driver.id.trim(),
      vehicleId: _resolveFleetVehicleIdForDriverGlobal(driver.id),
      driverName: driver.fullName.trim(),
      driverPhotoUrl: photo.isEmpty ? null : photo,
    ),
  );
}

({
  List<DriverProfile> selectable,
  List<DriverProfile> visibleCompanyDrivers,
  Map<String, int> excludedCounts,
})
_resolveDriverBridgeCandidatesReportGlobal({
  bool logCandidates = true,
  String? excludeDriverId,
  bool requireEmployeeNumber = true,
}) {
  final normalizedExcludedDriverId = (excludeDriverId ?? '').trim();
  final selected = <DriverProfile>[];
  final visibleCompanyDrivers = <DriverProfile>[];
  final excludedCounts = <String, int>{
    'inactive': 0,
    'placeholder': 0,
    'missing_id': 0,
    'missing_employee_number': 0,
    'company_mismatch': 0,
    'current_driver': 0,
  };
  final totalDrivers = driversNotifier.value.length;

  void incrementReason(String reason) {
    excludedCounts[reason] = (excludedCounts[reason] ?? 0) + 1;
  }

  for (final driver in driversNotifier.value) {
    final driverId = driver.id.trim();
    final companyId = (driver.companyId ?? '').trim();
    final employeePresent = driver.employeeNumber.trim().isNotEmpty;
    final placeholder = _isSeededOrPlaceholderBridgeDriver(driver);
    final active = driver.isActive;
    final idPresent = driverId.isNotEmpty;
    final companyVisible = fleetRecordBelongsToActiveCompanyOrLegacy(companyId);
    final isCurrentDriver =
        normalizedExcludedDriverId.isNotEmpty &&
        idPresent &&
        driverId == normalizedExcludedDriverId;
    var reason = 'selectable';

    if (!companyVisible) {
      reason = 'company_mismatch';
    } else if (!active) {
      reason = 'inactive';
    } else if (placeholder) {
      reason = 'placeholder';
    } else if (!idPresent) {
      reason = 'missing_id';
    } else if (isCurrentDriver) {
      reason = 'current_driver';
    } else if (requireEmployeeNumber && !employeePresent) {
      reason = 'missing_employee_number';
    }

    if (companyVisible) {
      visibleCompanyDrivers.add(driver);
    }
    final isSelected = reason == 'selectable';
    if (isSelected) {
      selected.add(driver);
    } else {
      incrementReason(reason);
    }
    if (logCandidates) {
      debugPrint(
        '[DRIVER_OWNER_BRIDGE][CANDIDATE] driver=${_maskBridgeDriverIdGlobal(driverId)} active=$active companyVisible=$companyVisible employeePresent=$employeePresent placeholder=$placeholder selected=$isSelected reason=${isSelected ? "selectable" : reason}',
      );
    }
  }
  if (logCandidates) {
    debugPrint(
      '[DRIVER_OWNER_BRIDGE][COUNTS] total=$totalDrivers visible=${visibleCompanyDrivers.length} selectable=${selected.length} inactive=${excludedCounts["inactive"] ?? 0} placeholder=${excludedCounts["placeholder"] ?? 0} missing_id=${excludedCounts["missing_id"] ?? 0} missing_employee_number=${excludedCounts["missing_employee_number"] ?? 0} company_mismatch=${excludedCounts["company_mismatch"] ?? 0} current_driver=${excludedCounts["current_driver"] ?? 0}',
    );
  }
  return (
    selectable: selected,
    visibleCompanyDrivers: visibleCompanyDrivers,
    excludedCounts: excludedCounts,
  );
}

Future<DriverProfile?> _showDriverOwnerBridgePickerSheet(
  BuildContext context, {
  required List<DriverProfile> selectableDrivers,
  required _BridgeTranslator tr,
}) {
  return showModalBottomSheet<DriverProfile>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          decoration: BoxDecoration(
            color: const Color(0xFF121A2E),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE5B641), width: 1.15),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFE5B641).withOpacity(0.12),
                blurRadius: 14,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        tr(
                          nl: 'Kies chauffeurweergave',
                          en: 'Choose driver view',
                          fr: 'Choisir la vue chauffeur',
                          es: 'Elegir vista de conductor',
                        ),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      icon: const Icon(Icons.close, color: Color(0xFFE5B641)),
                      splashRadius: 18,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0x22E5B641)),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: selectableDrivers.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: Color(0x16E5B641)),
                  itemBuilder: (itemContext, index) {
                    final driver = selectableDrivers[index];
                    return ListTile(
                      dense: true,
                      leading: const Icon(
                        Icons.person_outline_rounded,
                        color: Color(0xFFE5B641),
                      ),
                      title: Text(
                        driver.fullName.trim().isEmpty
                            ? driver.employeeNumber.trim()
                            : driver.fullName.trim(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        driver.employeeNumber.trim(),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.75),
                          fontSize: 12,
                        ),
                      ),
                      onTap: () => Navigator.of(sheetContext).pop(driver),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

String _firstBootstrapText(List<dynamic> values) {
  for (final value in values) {
    final text = (value ?? '').toString().trim();
    if (text.isNotEmpty) return text;
  }
  return '';
}

Future<void> _applyCompanyProfileFromBootstrapPayload(
  Map<String, dynamic> bootstrap,
) async {
  final current = companyProfileNotifier.value;
  if (current == null) return;
  final companyMap = bootstrap['company'] is Map
      ? Map<String, dynamic>.from(bootstrap['company'] as Map)
      : <String, dynamic>{};
  final businessMap = bootstrap['business_profile'] is Map
      ? Map<String, dynamic>.from(bootstrap['business_profile'] as Map)
      : <String, dynamic>{};
  final companyName = _firstBootstrapText(<dynamic>[
    companyMap['display_name'],
    businessMap['companyName'],
    businessMap['company_name'],
    businessMap['legalName'],
    businessMap['legal_name'],
    current.companyName,
  ]);
  final countryCode = _firstBootstrapText(<dynamic>[
    companyMap['country'],
    businessMap['country'],
    current.countryCode,
  ]);
  final updated = current.copyWith(
    companyName: companyName,
    phone: _firstBootstrapText(<dynamic>[businessMap['phone'], current.phone]),
    vatNumber: _firstBootstrapText(<dynamic>[
      businessMap['vatNumber'],
      businessMap['vat_number'],
      current.vatNumber,
    ]),
    addressLine: _firstBootstrapText(<dynamic>[
      businessMap['address'],
      current.addressLine,
    ]),
    postalCode: _firstBootstrapText(<dynamic>[
      businessMap['postcode'],
      current.postalCode,
    ]),
    city: _firstBootstrapText(<dynamic>[businessMap['city'], current.city]),
    countryCode: countryCode.isEmpty ? current.countryCode : countryCode,
    companyEmail: _firstBootstrapText(<dynamic>[
      businessMap['companyEmail'],
      businessMap['company_email'],
      businessMap['email'],
      current.companyEmail,
    ]),
    supportEmail: _firstBootstrapText(<dynamic>[
      businessMap['supportEmail'],
      businessMap['support_email'],
      businessMap['email'],
      current.supportEmail,
    ]),
    billingEmail: _firstBootstrapText(<dynamic>[
      businessMap['billingEmail'],
      businessMap['billing_email'],
      businessMap['invoiceEmail'],
      businessMap['invoice_email'],
      current.billingEmail,
    ]),
    bookingEmail: _firstBootstrapText(<dynamic>[
      businessMap['bookingEmail'],
      businessMap['booking_email'],
      current.bookingEmail,
    ]),
    notificationEmail: _firstBootstrapText(<dynamic>[
      businessMap['notificationEmail'],
      businessMap['notification_email'],
      businessMap['replyToEmail'],
      businessMap['reply_to_email'],
      current.notificationEmail,
    ]),
    updatedAt: DateTime.now().toUtc().toIso8601String(),
    isActive: true,
  );
  await CompanySessionStore.instance.persistProfile(updated);
  CompanySessionStore.instance.applyProfileToBusinessNotifier(updated);
}

String _normalizePublicFluxidiCompanyCode(String raw) {
  return raw
      .trim()
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

bool _isValidPublicFluxidiCompanyCode(String code) {
  if (code.isEmpty) return false;
  return RegExp(r'^FLX(?:-?[0-9]{4,12})$').hasMatch(code);
}

String? _publicCompanyCodeFromBootstrapPayload(Map<String, dynamic> bootstrap) {
  final businessProfileNode = bootstrap['business_profile'];
  if (businessProfileNode is Map) {
    final businessMap = Map<String, dynamic>.from(businessProfileNode);
    final fromBusinessProfile = _normalizePublicFluxidiCompanyCode(
      (businessMap['public_company_code'] ??
              businessMap['publicCompanyCode'] ??
              businessMap['company_code'] ??
              businessMap['companyCode'] ??
              '')
          .toString(),
    );
    if (_isValidPublicFluxidiCompanyCode(fromBusinessProfile)) {
      return fromBusinessProfile;
    }
  }

  final companyNode = bootstrap['company'];
  if (companyNode is Map) {
    final companyMap = Map<String, dynamic>.from(companyNode);
    final fromCompany = _normalizePublicFluxidiCompanyCode(
      (companyMap['public_company_code'] ??
              companyMap['publicCompanyCode'] ??
              companyMap['company_code'] ??
              companyMap['companyCode'] ??
              '')
          .toString(),
    );
    if (_isValidPublicFluxidiCompanyCode(fromCompany)) return fromCompany;
  }

  final fromTopLevel = _normalizePublicFluxidiCompanyCode(
    (bootstrap['public_company_code'] ??
            bootstrap['publicCompanyCode'] ??
            bootstrap['company_code'] ??
            bootstrap['companyCode'] ??
            '')
        .toString(),
  );
  if (_isValidPublicFluxidiCompanyCode(fromTopLevel)) return fromTopLevel;
  return null;
}

Future<bool> _hydrateCompanyBootstrapFromActiveSession({
  required String reason,
  bool clearOnUnauthorized = false,
  bool bootstrapDriverSession = true,
}) async {
  debugPrint('[COMPANY_BOOTSTRAP_REFRESH][START] reason=$reason');
  try {
    var session = activeCompanySessionNotifier.value;
    session ??= await CompanySessionStore.instance.loadSession();
    if (session == null) {
      debugPrint('[COMPANY_BOOTSTRAP_REFRESH][NO_SESSION] reason=$reason');
      return false;
    }
    final resolvedToken = await CompanySessionStore.instance
        .resolveCompanyBootstrapToken(preferredSession: session);
    final token = (resolvedToken.token ?? '').trim();
    final tokenSource = resolvedToken.source;
    debugPrint(
      '[COMPANY_BOOTSTRAP_REFRESH][TOKEN_SOURCE] reason=$reason source=$tokenSource hasToken=${token.isNotEmpty}',
    );
    if (token.isEmpty) {
      debugPrint(
        '[COMPANY_BOOTSTRAP_REFRESH][NO_COMPANY_TOKEN] reason=$reason',
      );
      return false;
    }
    final scopeCompany = session.companyId.trim();
    debugPrint(
      '[COMPANY_BOOTSTRAP_REFRESH][REQUEST] reason=$reason tenant=${_maskScopeForLog(scopeCompany)} company=${_maskScopeForLog(scopeCompany)}',
    );
    final bootstrap = await fetchCompanyBootstrapWithToken(
      companySessionToken: token,
    );
    final status = lastCompanyBootstrapHttpStatusCode;
    final vehiclesRaw = bootstrap?['vehicles'];
    final driversRaw = bootstrap?['drivers'];
    final vehiclesCount = vehiclesRaw is List ? vehiclesRaw.length : null;
    final driversCount = driversRaw is List ? driversRaw.length : null;
    debugPrint(
      '[COMPANY_BOOTSTRAP_REFRESH][FETCH_RESULT] reason=$reason ok=${bootstrap != null} status=${status ?? "unknown"} drivers=${driversCount ?? "unknown"} vehicles=${vehiclesCount ?? "unknown"}',
    );
    if (bootstrap == null) {
      return false;
    }
    if (driversRaw is List) {
      debugPrint('[COMPANY_BOOTSTRAP][DRIVERS] count=${driversRaw.length}');
      for (final row in driversRaw) {
        if (row is! Map) continue;
        final map = Map<String, dynamic>.from(row);
        final driverId = _firstBootstrapText(<dynamic>[
          map['driver_id'],
          map['driverId'],
          map['id'],
        ]);
        final driverName = _firstBootstrapText(<dynamic>[
          map['display_name'],
          map['displayName'],
          map['driver_name'],
          map['driverName'],
          map['full_name'],
          map['fullName'],
        ]);
        final isActiveRaw = map['is_active'] ?? map['isActive'];
        final isActive = isActiveRaw is bool
            ? isActiveRaw
            : isActiveRaw.toString().trim().toLowerCase() == 'true' ||
                  isActiveRaw.toString().trim() == '1';
        final publicPortrait = _firstBootstrapText(<dynamic>[
          map['public_portrait_url'],
          map['publicPortraitUrl'],
        ]);
        final driverPhoto = _firstBootstrapText(<dynamic>[
          map['driver_photo_url'],
          map['driverPhotoUrl'],
        ]);
        debugPrint(
          '[COMPANY_BOOTSTRAP][DRIVER] id=${_shortDriverIdForDiag(driverId)} name=${driverName.trim()} isActive=$isActive publicPortrait=${_shortUrlForDiag(publicPortrait)} driverPhoto=${_shortUrlForDiag(driverPhoto)}',
        );
      }
    } else {
      debugPrint('[COMPANY_BOOTSTRAP][DRIVERS] count=0');
    }
    final hydrated = await hydrateCompanyStateFromBootstrap(bootstrap);
    debugPrint(
      '[COMPANY_BOOTSTRAP_REFRESH][HYDRATE_DONE] reason=$reason ok=$hydrated',
    );
    if (!hydrated) {
      return false;
    }
    final hydratedCompanyCode = _publicCompanyCodeFromBootstrapPayload(
      bootstrap,
    );
    debugPrint(
      '[COMPANY_CODE][HYDRATE] found=${hydratedCompanyCode != null} source=bootstrap',
    );
    if (hydratedCompanyCode != null) {
      await CompanySessionStore.instance.updateActiveSessionCompanyCode(
        hydratedCompanyCode,
        source: 'bootstrap',
      );
    }
    await _applyCompanyProfileFromBootstrapPayload(bootstrap);
    if (bootstrapDriverSession) {
      await DriverSessionStore.instance.bootstrap(
        driversNotifier.value,
        useStandaloneScopePointer: false,
      );
    } else {
      debugPrint(
        '[DRIVER_SESSION][BOOTSTRAP_SKIP] reason=business_preview hydrate_reason=$reason',
      );
    }
    final hydratedCompanyId = _firstBootstrapText(<dynamic>[
      companyProfileNotifier.value?.companyId,
      activeCompanySessionNotifier.value?.companyId,
      scopeCompany,
    ]);
    _markBridgeBootstrapHydrated(hydratedCompanyId);
    debugPrint('[COMPANY_BOOTSTRAP][OK] source=$reason');
    return true;
  } catch (error) {
    debugPrint(
      '[COMPANY_BOOTSTRAP_REFRESH][ERROR] reason=$reason error=${_shortErrorForDiag(error)}',
    );
    return false;
  }
}

String? _activeCompanyScopeIdForSync() {
  final fromProfile = companyProfileNotifier.value?.companyId.trim() ?? '';
  if (fromProfile.isNotEmpty) return fromProfile;
  final fromSession =
      activeCompanySessionNotifier.value?.companyId.trim() ?? '';
  if (fromSession.isNotEmpty) return fromSession;
  return null;
}

Future<({bool hasToken, String source})>
_resolveCompanyBootstrapTokenState() async {
  var session = activeCompanySessionNotifier.value;
  session ??= await CompanySessionStore.instance.loadSession();
  final resolved = await CompanySessionStore.instance
      .resolveCompanyBootstrapToken(preferredSession: session);
  final token = (resolved.token ?? '').trim();
  const acceptedSources = <String>{'notifier', 'session', 'session_alias'};
  final source = resolved.source;
  return (
    hasToken: token.isNotEmpty && acceptedSources.contains(source),
    source: source,
  );
}

Future<bool> _hasUsableCompanyBootstrapToken({
  required String reason,
  bool logDegraded = false,
}) async {
  final state = await _resolveCompanyBootstrapTokenState();
  if (!state.hasToken && logDegraded) {
    debugPrint(
      '[COMPANY_SESSION][DEGRADED_NO_TOKEN] reason=$reason source=${state.source}',
    );
    debugPrint('[COMPANY_SESSION][RECOVERY_REQUIRED] reason=$reason');
  }
  return state.hasToken;
}

Future<void> _navigateToBusinessHomeWithBootstrapHydration(
  BuildContext context, {
  required String reason,
}) async {
  final hasToken = await _hasUsableCompanyBootstrapToken(
    reason: reason,
    logDegraded: true,
  );
  if (!hasToken || !context.mounted) return;
  await _hydrateCompanyBootstrapFromActiveSession(
    reason: reason,
    clearOnUnauthorized: true,
  );
  unawaited(
    _triggerCompanyInventoryBackfillRestore(reason: 'company_home_restore'),
  );
  if (!context.mounted) return;
  setAppRole(AppRole.companyAdmin);
  Navigator.of(context).pushReplacement(
    MaterialPageRoute<void>(builder: (_) => const BusinessHomePage()),
  );
}

Future<void> _blockBusinessHomeEntryWithoutBootstrapToken(
  BuildContext context, {
  required String blockLog,
  required String recoveryReason,
  required String retryReason,
}) async {
  debugPrint(blockLog);
  if (!context.mounted) return;
  await _showDegradedCompanySessionRecoveryDialog(
    context,
    reason: recoveryReason,
  );
  if (!context.mounted) return;
  await _navigateToBusinessHomeWithBootstrapHydration(
    context,
    reason: retryReason,
  );
}

Future<({bool usable, String reasonCode, String tokenSource, String companyId})>
_resolveBackendUsableCompanyContextForAdmin({
  required String reason,
  bool logDegraded = false,
}) async {
  final state = await CompanySessionStore.instance
      .resolveBackendUsableCompanyContext();
  if (!state.ok && logDegraded) {
    debugPrint(
      '[COMPANY_SESSION][DEGRADED_ADMIN_CONTEXT] reason=$reason code=${state.reason} token_source=${state.tokenSource}',
    );
    if (state.reason == 'missing_token') {
      debugPrint('[COMPANY_SESSION][DEGRADED_NO_TOKEN] reason=$reason');
      debugPrint('[COMPANY_SESSION][RECOVERY_REQUIRED] reason=$reason');
    }
  }
  return (
    usable: state.ok,
    reasonCode: state.reason,
    tokenSource: state.tokenSource,
    companyId: state.companyId,
  );
}

Future<void> _runCompanyRelinkActivationFlow(BuildContext context) async {
  const roleEntry = RoleEntryPage();
  final activationCode = await roleEntry._promptCompanyActivationCode(context);
  if (!context.mounted || activationCode == null) return;
  if (activationCode == RoleEntryPage._companyRecoveryIntent) {
    await roleEntry._runCompanyRecoveryFlow(context);
    return;
  }
  if (activationCode == RoleEntryPage._companyPairingOnboardingIntent) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _tr(
            nl: 'Gebruik activatiecode of herstel om als bedrijf in te loggen.',
            en: 'Use activation code or recovery to sign in as business owner.',
            fr: "Utilisez le code d'activation ou la récupération pour vous connecter en tant qu'entreprise.",
            es: 'Usa el código de activación o recuperación para iniciar sesión como empresa.',
          ),
        ),
      ),
    );
    return;
  }
  final parsed = roleEntry._parseCompanyActivationCode(activationCode);
  if (parsed == null) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _tr(
            nl: 'Ongeldige activatiecode. Gebruik bijvoorbeeld FLX-4821-123456.',
            en: 'Invalid activation code. Use for example FLX-4821-123456.',
            fr: 'Code d’activation invalide. Utilisez par exemple FLX-4821-123456.',
            es: 'Código de activación no válido. Usa por ejemplo FLX-4821-123456.',
          ),
        ),
      ),
    );
    return;
  }

  final verified = await roleEntry._verifyCompanyPairingCode(
    companyCode: parsed.companyCode,
    pairingCode: parsed.pairingCode,
  );
  if (!context.mounted) return;
  if (verified['ok'] != true) {
    final errorCode = roleEntry
        ._safePairingText(verified['error'])
        .toLowerCase();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(roleEntry._companyPairingErrorText(errorCode))),
    );
    return;
  }

  final payload = verified['payload'] is Map
      ? Map<String, dynamic>.from(verified['payload'] as Map)
      : <String, dynamic>{};
  await roleEntry._showCompanyPairingSuccessDialog(context);
  if (!context.mounted) return;
  final opened = await roleEntry._openVerifiedCompanySession(context, payload);
  if (!context.mounted) return;
  if (!opened) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          roleEntry._companyPairingErrorText('verification_failed'),
        ),
      ),
    );
  }
}

Future<void> _switchCompanyFromRecoveryDialog(BuildContext context) async {
  await CompanySessionStore.instance.clearLocalCompanyState();
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute<void>(builder: (_) => const RoleEntryPage()),
    (route) => false,
  );
}

Future<void> _showDegradedCompanySessionRecoveryDialog(
  BuildContext context, {
  required String reason,
}) async {
  final action = await FluxidiResponsiveDialog.show<String>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: const Color(0xFF111111),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: kFluxidiYellow.withOpacity(0.45)),
        ),
        title: Text(
          _tr(
            nl: 'Bedrijfssessie vereist',
            en: 'Company session required',
            fr: 'Session entreprise requise',
            es: 'Se requiere sesión de empresa',
          ),
          style: const TextStyle(color: Colors.white),
        ),
        scrollable: true,
        content: Text(
          _tr(
            nl: 'Je chauffeurmodus kan nog werken, maar beheerfuncties zoals chauffeurs, voertuigen en instellingen vereisen een actieve bedrijfssessie. Herstel of herkoppel je bedrijf om verder te gaan.',
            en: 'Driver mode may still work, but management features like drivers, vehicles, and settings require an active company session. Recover or relink your company to continue.',
            fr: 'Le mode chauffeur peut encore fonctionner, mais les fonctions de gestion comme chauffeurs, véhicules et réglages nécessitent une session entreprise active. Récupérez ou reliez votre entreprise pour continuer.',
            es: 'El modo conductor puede seguir funcionando, pero las funciones de gestión como conductores, vehículos y ajustes requieren una sesión activa de empresa. Recupera o vuelve a vincular tu empresa para continuar.',
          ),
          style: TextStyle(color: Colors.white.withOpacity(0.82)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              _tr(nl: 'Sluiten', en: 'Close', fr: 'Fermer', es: 'Cerrar'),
            ),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(dialogContext).pop('recover'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: kFluxidiYellow.withOpacity(0.5)),
            ),
            child: Text(
              _tr(
                nl: 'Herstel bedrijf',
                en: 'Recover company',
                fr: "Récupérer l’entreprise",
                es: 'Recuperar empresa',
              ),
            ),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(dialogContext).pop('relink'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: kFluxidiYellow.withOpacity(0.5)),
            ),
            child: Text(
              _tr(
                nl: 'Herkoppel met activatiecode',
                en: 'Relink with activation code',
                fr: "Relier avec code d’activation",
                es: 'Volver a vincular con código de activación',
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop('switch_company'),
            child: Text(
              _tr(
                nl: 'Ander bedrijf',
                en: 'Other company',
                fr: 'Autre entreprise',
                es: 'Otra empresa',
              ),
            ),
          ),
        ],
      );
    },
  );
  if (!context.mounted || action == null) return;
  debugPrint(
    '[COMPANY_SESSION][RECOVERY_UI_ACTION] reason=$reason action=$action',
  );
  if (action == 'recover') {
    const roleEntry = RoleEntryPage();
    await roleEntry._runCompanyRecoveryFlow(context);
    return;
  }
  if (action == 'relink') {
    await _runCompanyRelinkActivationFlow(context);
    return;
  }
  if (action == 'switch_company') {
    await _switchCompanyFromRecoveryDialog(context);
  }
}

bool _hasRicherLocalCompanyInventoryForBackfill() {
  if (vehiclesNotifier.value.length > 1 || driversNotifier.value.length > 1) {
    return true;
  }
  for (final vehicle in vehiclesNotifier.value) {
    if (vehicle.brandModel.trim().isNotEmpty ||
        vehicle.licensePlate.trim().isNotEmpty ||
        vehicle.exploitationLicenseNumber.trim().isNotEmpty ||
        vehicle.vehicleRegistrationNumber.trim().isNotEmpty ||
        vehicle.primaryPhotoRef.trim().isNotEmpty ||
        vehicle.galleryPhotoRefs.isNotEmpty ||
        (vehicle.publicPhotoUrl ?? '').trim().isNotEmpty ||
        (vehicle.driverId ?? '').trim().isNotEmpty) {
      return true;
    }
  }
  for (final driver in driversNotifier.value) {
    if (driver.taxiDriverCardNumber.trim().isNotEmpty ||
        driver.taxiDriverCardExpiry.trim().isNotEmpty ||
        (driver.publicPortraitUrl ?? '').trim().isNotEmpty ||
        (driver.publicDisplayName ?? '').trim().isNotEmpty ||
        driver.publicProfileEnabled ||
        driver.publicPhotoEnabled) {
      return true;
    }
  }
  return false;
}

Future<void> _triggerCompanyInventoryBackfillRestore({
  required String reason,
}) async {
  if (!_hasRicherLocalCompanyInventoryForBackfill()) return;
  final tokenState = await _resolveCompanyBootstrapTokenState();
  if (!tokenState.hasToken) {
    debugPrint(
      '[COMPANY_SYNC][SKIP_NO_COMPANY_TOKEN] reason=$reason source=${tokenState.source}',
    );
    return;
  }
  final scopeId = _activeCompanyScopeIdForSync();
  if (scopeId == null) {
    debugPrint(
      '[COMPANY_INVENTORY_BACKFILL][SKIP] reason=missing_active_company_context',
    );
    return;
  }
  unawaited(
    syncLocalCompanyInventoryToBackend(
      reason: reason,
      tenantId: scopeId,
      companyId: scopeId,
      requireCompanySessionToken: true,
      hasCompanySessionToken: true,
    ),
  );
}

Future<void> _runDeferredStartupTask({
  required String task,
  required Future<void> Function() action,
}) async {
  debugPrint('[STARTUP_PERF][DEFER] task=$task');
  try {
    await action();
    debugPrint('[STARTUP_PERF][DEFER_DONE] task=$task');
  } catch (error) {
    debugPrint('[STARTUP_PERF][DEFER_WARN] task=$task error=$error');
  }
}

Future<void> _runStartupDeferredWork({
  required bool hasLocalCompanyContext,
  required bool hasBootstrapToken,
}) async {
  await _runDeferredStartupTask(
    task: 'cached_customer_profile_refresh',
    action: _refreshCachedCustomerProfile,
  );
  await _runDeferredStartupTask(
    task: 'driver_documents_load',
    action: () => DriverDocumentsStore.instance.load(),
  );
  if (!hasLocalCompanyContext) return;
  if (!hasBootstrapToken) {
    debugPrint(
      '[COMPANY_BOOTSTRAP][SKIP_REMOTE_NO_TOKEN] reason=deferred_startup',
    );
    return;
  }
  await _runDeferredStartupTask(
    task: 'company_bootstrap_hydrate',
    action: () => _hydrateCompanyBootstrapFromActiveSession(
      reason: 'startup_restore_deferred',
      clearOnUnauthorized: true,
    ),
  );
  await _runDeferredStartupTask(
    task: 'company_inventory_backfill_restore',
    action: () =>
        _triggerCompanyInventoryBackfillRestore(reason: 'company_home_restore'),
  );
}

// Pending Mollie payment tracking lives in lib/payment_return.dart and is
// re-exported above so existing references in this file (and other modules)
// keep working unchanged.

/// Builds best-available auth headers for a server-side booking GET issued
/// from the Local Ride Register bridge. Mirrors the precedence already used
/// by [_ReceiptPdfActionRunner._backendInvoicePdfHeaders]:
///   1) compile-time admin token (dev/ops),
///   2) active driver session bearer (standalone driver / driver-owns booking),
///   3) company-owner / company-session bearer for business-admin context.
///
/// Tokens are never logged. The returned map contains only `Accept` when no
/// trusted source is available, so the caller can decide to skip the GET.
Future<Map<String, String>> _localRegisterBookingFetchHeaders() async {
  final headers = <String, String>{'Accept': 'application/json'};
  final admin = _adminHeaders();
  if (admin.isNotEmpty) {
    headers.addAll(admin);
    return headers;
  }
  final driverSessionToken =
      (activeDriverSessionNotifier.value?.driverSessionToken ?? '').trim();
  if (driverSessionToken.isNotEmpty) {
    headers['Authorization'] = 'Bearer $driverSessionToken';
    return headers;
  }
  final companyAuth = await resolveCompanyOwnerAuthHeaders(json: false);
  if (companyAuth.mode != CompanyOwnerAuthMode.none) {
    headers.addAll(companyAuth.headers);
  }
  return headers;
}

/// Best-effort hydration for Local Ride Register receipts via the Tracking
/// Worker `GET /trips/history` projection. This is the SAME shape and source
/// the chauffeur History receipt uses (see `_TripHistoryPageState._fetch`)
/// and carries `origin.label`, `destination.label`, and a `booking_details`
/// block with `pickup_address`, `destination_address`, `scheduled_pickup_at`,
/// `service_type`, `tier`, `passengers`, `luggage_count`, `customer_*`,
/// `payment_*` and price fields — populated when the chauffeur stopped the
/// planned ride via `/trip/record-planned-stop`.
///
/// Skipped gracefully when auth is insufficient (only a pure driver-session
/// bearer is available; `/trips/history` requires admin OR company-session).
/// The caller continues with the booking-worker hydration as before.
Future<Map<String, dynamic>> _hydrateRegisterReceiptFromTripsHistory(
  ComplianceLedgerEntry entry,
  Map<String, dynamic> baseJson,
) async {
  final maskedBooking = _maskScopeForLog(entry.bookingId);
  final maskedTrip = _maskScopeForLog(entry.tripId);
  final tenantId = entry.tenantId.trim();
  final companyId = entry.companyId.trim();
  final driverId = entry.driverId.trim();
  // `missing_scope` means tenant or company is missing — those two are
  // required by the tracking worker. `driver_id` is INTENTIONALLY optional:
  // Local Ride Register entries are an admin / compliance projection that may
  // legitimately have an empty driver_id (e.g. driver-not-linked compliance
  // rows). In that case we still want the tenant/company-scoped trips list so
  // we can match by `trip_id` / `booking_id`.
  if (tenantId.isEmpty || companyId.isEmpty) {
    debugPrint(
      '[LOCAL_RIDE_REGISTER][HYDRATE_TRIP] booking=$maskedBooking trip=$maskedTrip ok=false matched=false trips=0 source=trips_history driver_filter=false reason=missing_scope',
    );
    return baseJson;
  }
  final driverFilterActive = driverId.isNotEmpty;
  try {
    // `/trips/history` is authenticated by `requireAdminOrCompanySessionForScope`
    // in the tracking worker — it accepts ONLY a compile-time admin token or a
    // company-session bearer. A pure driver-session bearer is rejected, so we
    // build headers via `resolveCompanyOwnerAuthHeaders` (the same helper
    // chauffeur History uses via `_companyOwnerHeaders`) instead of the
    // booking-worker helper (which prefers a driver-session bearer when
    // present and would fail-close here).
    final companyAuth = await resolveCompanyOwnerAuthHeaders(json: false);
    if (companyAuth.mode == CompanyOwnerAuthMode.none) {
      debugPrint(
        '[LOCAL_RIDE_REGISTER][HYDRATE_TRIP] booking=$maskedBooking trip=$maskedTrip ok=false matched=false trips=0 source=trips_history driver_filter=$driverFilterActive reason=auth_insufficient',
      );
      return baseJson;
    }
    final headers = <String, String>{
      'Accept': 'application/json',
      ...companyAuth.headers,
    };
    // driver_id filter is added ONLY when we actually have a non-empty driver
    // identifier from the compliance entry. Without it we fetch the broader
    // tenant/company-scoped list and rely on trip_id / booking_id matching.
    final query = <String, String>{
      'tenant_id': tenantId,
      'company_id': companyId,
      'tenantId': tenantId,
      'companyId': companyId,
      if (driverFilterActive) 'driver_id': driverId,
      'include_archived': '1',
      'include_active': '0',
      'limit': '200',
    };
    final uri = Uri.parse(
      '$kWorkerBaseUrl$kTripsHistoryPath',
    ).replace(queryParameters: query);
    final res = await http
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 10));
    final status = res.statusCode;
    if (status != 200) {
      debugPrint(
        '[LOCAL_RIDE_REGISTER][HYDRATE_TRIP] booking=$maskedBooking trip=$maskedTrip ok=false matched=false trips=0 source=trips_history driver_filter=$driverFilterActive reason=http_$status',
      );
      return baseJson;
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! Map || decoded['ok'] != true) {
      debugPrint(
        '[LOCAL_RIDE_REGISTER][HYDRATE_TRIP] booking=$maskedBooking trip=$maskedTrip ok=false matched=false trips=0 source=trips_history driver_filter=$driverFilterActive reason=invalid_body',
      );
      return baseJson;
    }
    final trips = decoded['trips'];
    if (trips is! List) {
      debugPrint(
        '[LOCAL_RIDE_REGISTER][HYDRATE_TRIP] booking=$maskedBooking trip=$maskedTrip ok=true matched=false trips=0 source=trips_history driver_filter=$driverFilterActive reason=no_trips',
      );
      return baseJson;
    }
    final tripCount = trips.length;
    final targetTripId = entry.tripId.trim();
    final targetBookingId = entry.bookingId.trim();
    final targetPlanning = entry.planningReference.trim();
    final targetPublicBooking = entry.publicBookingReference.trim();

    String detailText(Map<String, dynamic>? details, String key) {
      if (details == null) return '';
      final v = details[key];
      if (v == null) return '';
      return v.toString().trim();
    }

    String tripText(Map<String, dynamic> trip, String key) {
      final v = trip[key];
      if (v == null) return '';
      return v.toString().trim();
    }

    Map<String, dynamic>? matchedByTripId;
    Map<String, dynamic>? matchedByBookingId;
    Map<String, dynamic>? matchedByParentBookingId;
    Map<String, dynamic>? matchedByPlanning;
    Map<String, dynamic>? matchedByPublicBooking;
    for (final raw in trips) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      final details = m['booking_details'] is Map
          ? Map<String, dynamic>.from(m['booking_details'] as Map)
          : null;

      if (targetTripId.isNotEmpty && tripText(m, 'trip_id') == targetTripId) {
        matchedByTripId = m;
        break;
      }
      if (matchedByBookingId == null &&
          targetBookingId.isNotEmpty &&
          tripText(m, 'booking_id') == targetBookingId) {
        matchedByBookingId = m;
      }
      if (matchedByParentBookingId == null && targetBookingId.isNotEmpty) {
        final parent = detailText(details, 'parent_booking_id').isNotEmpty
            ? detailText(details, 'parent_booking_id')
            : detailText(details, 'parentBookingId');
        if (parent == targetBookingId) {
          matchedByParentBookingId = m;
        }
      }
      if (matchedByPlanning == null && targetPlanning.isNotEmpty) {
        final planning = <String>[
          tripText(m, 'planning_reference'),
          tripText(m, 'planningReference'),
          tripText(m, 'planning_no'),
          tripText(m, 'planningNo'),
          detailText(details, 'planning_reference'),
          detailText(details, 'planningReference'),
          detailText(details, 'planning_no'),
          detailText(details, 'planningNo'),
        ].firstWhere((v) => v.isNotEmpty, orElse: () => '');
        if (planning == targetPlanning) {
          matchedByPlanning = m;
        }
      }
      if (matchedByPublicBooking == null && targetPublicBooking.isNotEmpty) {
        final pub = <String>[
          tripText(m, 'public_booking_reference'),
          tripText(m, 'publicBookingReference'),
          tripText(m, 'public_reference'),
          tripText(m, 'publicReference'),
          detailText(details, 'public_booking_reference'),
          detailText(details, 'publicBookingReference'),
          detailText(details, 'public_reference'),
          detailText(details, 'publicReference'),
        ].firstWhere((v) => v.isNotEmpty, orElse: () => '');
        if (pub == targetPublicBooking) {
          matchedByPublicBooking = m;
        }
      }
    }
    final matchedTrip =
        matchedByTripId ??
        matchedByBookingId ??
        matchedByParentBookingId ??
        matchedByPlanning ??
        matchedByPublicBooking;
    final matchMethod = matchedByTripId != null
        ? 'trip_id'
        : matchedByBookingId != null
        ? 'booking_id'
        : matchedByParentBookingId != null
        ? 'parent_booking_id'
        : matchedByPlanning != null
        ? 'planning_reference'
        : matchedByPublicBooking != null
        ? 'public_booking_reference'
        : 'none';
    if (matchedTrip == null) {
      debugPrint(
        '[LOCAL_RIDE_REGISTER][HYDRATE_TRIP] booking=$maskedBooking trip=$maskedTrip ok=true matched=false trips=$tripCount source=trips_history driver_filter=$driverFilterActive match=$matchMethod',
      );
      return baseJson;
    }
    final merged = mergeTrackingTripIntoTripHistoryJson(
      tripJson: matchedTrip,
      baseJson: baseJson,
    );
    debugPrint(
      '[LOCAL_RIDE_REGISTER][HYDRATE_TRIP] booking=$maskedBooking trip=$maskedTrip ok=true matched=true trips=$tripCount source=trips_history driver_filter=$driverFilterActive match=$matchMethod',
    );
    return merged;
  } catch (err) {
    debugPrint(
      '[LOCAL_RIDE_REGISTER][HYDRATE_TRIP] booking=$maskedBooking trip=$maskedTrip ok=false matched=false trips=0 source=trips_history driver_filter=$driverFilterActive reason=${_shortErrorForDiag(err)}',
    );
    return baseJson;
  }
}

/// Best-effort hydration for Local Ride Register receipts. Compliance entries
/// often omit pickup/dropoff/customer/fare data; when a `booking_id` is
/// present the booking worker can provide an authoritative record. On any
/// failure (no booking_id, no auth, non-200, malformed body) the original
/// compliance-only JSON is returned unchanged so the receipt page still opens.
///
/// Runs `/trips/history` first to obtain the authoritative chauffeur-recorded
/// trip shape (matches what the chauffeur History receipt sees), then refines
/// with `GET ${kBookingBaseUrl}/bookings/{id}` for business references and any
/// fields the trip projection doesn't carry.
Future<Map<String, dynamic>> _hydrateRegisterReceiptJson(
  ComplianceLedgerEntry entry,
  Map<String, dynamic> baseJson,
) async {
  final bookingId = entry.bookingId.trim();
  final maskedBooking = _maskScopeForLog(bookingId);

  // Snapshot the compliance-derived paid state BEFORE any backend enrichment
  // so the [PAYMENT_AUTHORITY] diagnostic can show what the local-register /
  // ledger actually declared. The merge helpers in
  // `compliance_register_receipt_bridge.dart` are responsible for ensuring
  // this state can never be downgraded; this log just verifies the outcome.
  final basePaid = baseTripHistoryJsonHasPaidStatus(baseJson);

  // Step 1: tracking worker `/trips/history` — authoritative for planned
  // chauffeur-stopped rides (route + booking_details).
  final afterTrip = await _hydrateRegisterReceiptFromTripsHistory(
    entry,
    baseJson,
  );
  // `tripPaid` reflects whether the (protected) trip-history overlay carries
  // a paid signal — same value as `basePaid` whenever compliance was already
  // paid (since the protected merge preserves it). A `tripPaid=false`
  // alongside `basePaid=true` would surface a regression in the trip merge.
  final tripPaid = baseTripHistoryJsonHasPaidStatus(afterTrip);

  void logPaymentAuthority({
    required bool bookingPaid,
    required bool finalPaid,
    required String source,
  }) {
    debugPrint(
      '[LOCAL_RIDE_REGISTER][PAYMENT_AUTHORITY] booking=$maskedBooking'
      ' base_paid=$basePaid trip_paid=$tripPaid booking_paid=$bookingPaid'
      ' final_paid=$finalPaid source=$source',
    );
  }

  String authoritySource({required bool bookingPaid, required bool finalPaid}) {
    if (!finalPaid) return 'none';
    if (basePaid) return 'compliance';
    // After this point base wasn't paid: only the trip or booking layers
    // could have contributed the paid signal.
    if (tripPaid && !bookingPaid) return 'trip';
    if (bookingPaid) return 'booking';
    return 'trip';
  }

  if (bookingId.isEmpty) {
    debugPrint(
      '[LOCAL_RIDE_REGISTER][HYDRATE_BOOKING] booking=$maskedBooking ok=false status=- fields=0 source=register reason=no_booking_id',
    );
    final finalPaid = baseTripHistoryJsonHasPaidStatus(afterTrip);
    logPaymentAuthority(
      bookingPaid: false,
      finalPaid: finalPaid,
      source: authoritySource(bookingPaid: false, finalPaid: finalPaid),
    );
    return afterTrip;
  }
  try {
    final headers = await _localRegisterBookingFetchHeaders();
    if (!headers.containsKey('Authorization') &&
        !headers.containsKey('x-admin-token')) {
      debugPrint(
        '[LOCAL_RIDE_REGISTER][HYDRATE_BOOKING] booking=$maskedBooking ok=false status=- fields=0 source=register reason=no_auth',
      );
      final finalPaid = baseTripHistoryJsonHasPaidStatus(afterTrip);
      logPaymentAuthority(
        bookingPaid: false,
        finalPaid: finalPaid,
        source: authoritySource(bookingPaid: false, finalPaid: finalPaid),
      );
      return afterTrip;
    }
    final uri = _withActiveBookingScope(
      kBookingBaseUrl,
      '/bookings/${Uri.encodeComponent(bookingId)}',
    );
    final res = await http
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 12));
    final status = res.statusCode;
    if (status != 200) {
      debugPrint(
        '[LOCAL_RIDE_REGISTER][HYDRATE_BOOKING] booking=$maskedBooking ok=false status=$status fields=0 source=register',
      );
      final finalPaid = baseTripHistoryJsonHasPaidStatus(afterTrip);
      logPaymentAuthority(
        bookingPaid: false,
        finalPaid: finalPaid,
        source: authoritySource(bookingPaid: false, finalPaid: finalPaid),
      );
      return afterTrip;
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! Map || decoded['ok'] != true) {
      debugPrint(
        '[LOCAL_RIDE_REGISTER][HYDRATE_BOOKING] booking=$maskedBooking ok=false status=$status fields=0 source=register reason=invalid_body',
      );
      final finalPaid = baseTripHistoryJsonHasPaidStatus(afterTrip);
      logPaymentAuthority(
        bookingPaid: false,
        finalPaid: finalPaid,
        source: authoritySource(bookingPaid: false, finalPaid: finalPaid),
      );
      return afterTrip;
    }
    final decodedMap = Map<String, dynamic>.from(decoded);
    // Probe the raw booking-worker record's paid signal BEFORE the merge so
    // the diagnostic shows what the booking record itself reported, not the
    // already-protected merged result.
    Map<String, dynamic> asMap(Object? value) =>
        value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
    final probeRoot = <String, dynamic>{
      ...decodedMap,
      'record': asMap(decodedMap['record']),
      'booking': asMap(asMap(decodedMap['record'])['booking']),
    };
    final bookingPaid = baseTripHistoryJsonHasPaidStatus(probeRoot);
    final merged = mergeBookingRecordIntoTripHistoryJson(
      tripHistoryJson: afterTrip,
      decodedResponse: decodedMap,
    );
    final mergedDetails = merged['booking_details'];
    final fieldCount = mergedDetails is Map ? mergedDetails.length : 0;
    debugPrint(
      '[LOCAL_RIDE_REGISTER][HYDRATE_BOOKING] booking=$maskedBooking ok=true status=$status fields=$fieldCount source=register',
    );
    final finalPaid = baseTripHistoryJsonHasPaidStatus(merged);
    logPaymentAuthority(
      bookingPaid: bookingPaid,
      finalPaid: finalPaid,
      source: authoritySource(bookingPaid: bookingPaid, finalPaid: finalPaid),
    );
    return merged;
  } catch (err) {
    debugPrint(
      '[LOCAL_RIDE_REGISTER][HYDRATE_BOOKING] booking=$maskedBooking ok=false status=- fields=0 source=register reason=${_shortErrorForDiag(err)}',
    );
    final finalPaid = baseTripHistoryJsonHasPaidStatus(afterTrip);
    logPaymentAuthority(
      bookingPaid: false,
      finalPaid: finalPaid,
      source: authoritySource(bookingPaid: false, finalPaid: finalPaid),
    );
    return afterTrip;
  }
}

void _registerComplianceRegisterReceiptBridge() {
  registerComplianceRegisterReceiptHandler((
    BuildContext context,
    ComplianceLedgerEntry entry, {
    required ComplianceRegisterReceiptAction action,
  }) async {
    final hydratedJson = await _hydrateRegisterReceiptJson(
      entry,
      tripHistoryJsonFromLedgerEntry(entry),
    );
    // Side-effect: cache the resolved driver/vehicle labels so the Local
    // Ride Register dashboard cards can display them on subsequent renders.
    // Receipt rendering itself is unaffected; this just exposes the same
    // identifiers the receipt shows back to the card display layer.
    final assignment = extractLocalRideAssignmentFromMergedJson(hydratedJson);
    if (!assignment.isEmpty) {
      recordLocalRideAssignment(
        bookingId: entry.bookingId,
        tripId: entry.tripId,
        info: assignment,
      );
      debugPrint(
        '[LOCAL_RIDE_REGISTER][ASSIGNMENT_CACHE]'
        ' booking=${_maskScopeForLog(entry.bookingId)}'
        ' trip=${_maskScopeForLog(entry.tripId)}'
        ' driver_found=${assignment.driverLabel != null}'
        ' vehicle_found=${assignment.vehicleLabel != null}',
      );
    }
    if (!context.mounted) return;
    final item = _TripHistoryItem.fromJson(hydratedJson);
    final key = ComplianceLedgerReader.groupKeyFor(entry);
    switch (action) {
      case ComplianceRegisterReceiptAction.viewDetails:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => _RideReceiptPage(item: item)),
        );
      case ComplianceRegisterReceiptAction.downloadReceipt:
        debugPrint(
          '[LOCAL_RIDE_REGISTER][EXPORT_RECEIPT] key=$key source=register',
        );
        await _ReceiptPdfActionRunner.previewReceiptPdf(
          context: context,
          item: item,
        );
      case ComplianceRegisterReceiptAction.downloadInvoice:
        debugPrint(
          '[LOCAL_RIDE_REGISTER][EXPORT_INVOICE] key=$key source=register',
        );
        await _ReceiptPdfActionRunner.previewInvoicePdf(
          context: context,
          item: item,
        );
      case ComplianceRegisterReceiptAction.shareReceipt:
        debugPrint(
          '[LOCAL_RIDE_REGISTER][EXPORT_RECEIPT] key=$key source=share',
        );
        await _ReceiptPdfActionRunner.sharePdf(context: context, item: item);
    }
  });
}

/// Background prewarm: when the Local Ride Register dashboard renders a card
/// whose driver/vehicle could not be resolved from compliance / profile data,
/// it fires `requestLocalRideAssignmentPrewarm(entry)`. That helper calls
/// this handler, which runs the same hydration pipeline the receipt page
/// uses and writes the resulting labels into the assignment cache. The cache
/// notifier then wakes the dashboard so the visible card rebuilds with the
/// resolved labels — no UI layout change, just label replacement.
Future<void> _prewarmLocalRideAssignmentForEntry(
  ComplianceLedgerEntry entry,
) async {
  final maskedBooking = _maskScopeForLog(entry.bookingId);
  final maskedTrip = _maskScopeForLog(entry.tripId);
  try {
    final hydratedJson = await _hydrateRegisterReceiptJson(
      entry,
      tripHistoryJsonFromLedgerEntry(entry),
    );
    final assignment = extractLocalRideAssignmentFromMergedJson(hydratedJson);
    if (assignment.isEmpty) {
      debugPrint(
        '[LOCAL_RIDE_REGISTER][ASSIGNMENT_PREWARM]'
        ' booking=$maskedBooking trip=$maskedTrip'
        ' driver_found=false vehicle_found=false',
      );
      return;
    }
    recordLocalRideAssignment(
      bookingId: entry.bookingId,
      tripId: entry.tripId,
      info: assignment,
    );
    debugPrint(
      '[LOCAL_RIDE_REGISTER][ASSIGNMENT_PREWARM]'
      ' booking=$maskedBooking trip=$maskedTrip'
      ' driver_found=${assignment.driverLabel != null}'
      ' vehicle_found=${assignment.vehicleLabel != null}',
    );
  } catch (err) {
    debugPrint(
      '[LOCAL_RIDE_REGISTER][ASSIGNMENT_PREWARM]'
      ' booking=$maskedBooking trip=$maskedTrip reason=${_shortErrorForDiag(err)}',
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _registerComplianceRegisterReceiptBridge();
  registerLocalRideAssignmentPrewarmHandler(
    _prewarmLocalRideAssignmentForEntry,
  );
  await loadBusinessThemePreference();
  await loadBusinessHomeMobileLayoutPreference();
  await loadDriverHomeMobileLayoutPreference();
  await loadCompanyDriverViewThemePreference();
  await loadDriverAppThemePreference();
  await loadLocalTenantState();
  await CompanySessionStore.instance.bootstrap();
  var hasBootstrapToken = false;
  var startupTokenSource = 'unchecked';
  var hasLocalCompanyContext =
      CompanySessionStore.instance.hasValidCompanyContext;
  if (hasLocalCompanyContext) {
    final startupTokenState = await _resolveCompanyBootstrapTokenState();
    hasBootstrapToken = startupTokenState.hasToken;
    startupTokenSource = startupTokenState.source;
    if (!hasBootstrapToken) {
      debugPrint(
        '[COMPANY_SESSION][DEGRADED_NO_TOKEN] reason=startup_restore source=$startupTokenSource',
      );
      debugPrint('[COMPANY_SESSION][RECOVERY_REQUIRED] reason=startup_restore');
    }
  }
  final startupCompanyProfile = companyProfileNotifier.value;
  final startupCompanySession = activeCompanySessionNotifier.value;
  debugPrint(
    '[STARTUP][COMPANY] hasProfile=${startupCompanyProfile != null}'
    ' profileActive=${startupCompanyProfile?.isActive ?? false}'
    ' hasSession=${startupCompanySession != null}'
    ' hasToken=$hasBootstrapToken'
    ' tokenSource=$startupTokenSource',
  );
  hasLocalCompanyContext = CompanySessionStore.instance.hasValidCompanyContext;
  if (hasLocalCompanyContext) {
    if (hasBootstrapToken) {
      setAppRole(AppRole.companyAdmin);
      _startInCompanyAdminHome = true;
      _startInDriverHome = false;
      debugPrint(
        '[COMPANY_PAIRING][AUTO_ROUTE] target=business_home has_token=true',
      );
    } else {
      _startupBlockedCompanySessionRecovery = true;
      debugPrint('[COMPANY_SESSION][AUTO_ROUTE_BLOCKED_NO_TOKEN]');
      debugPrint(
        '[COMPANY_PAIRING][AUTO_ROUTE] target=role_entry has_token=false',
      );
    }
  } else {
    debugPrint(
      '[COMPANY_PAIRING][AUTO_ROUTE_SKIP] reason=no_valid_company_context',
    );
  }
  DriverSessionStore.instance.prepareStandaloneDriverEntry();
  await DriverSessionStore.instance.bootstrap(
    driversNotifier.value,
    useStandaloneScopePointer: !_startInCompanyAdminHome,
  );
  final startupDriverSession = activeDriverSessionNotifier.value;
  final startupDriverHasToken = (startupDriverSession?.driverSessionToken ?? '')
      .trim()
      .isNotEmpty;
  final startupDriverMode = startupDriverSession?.sessionMode ?? 'none';
  final startupDriverCompany = (startupDriverSession?.companyId ?? '').trim();
  final startupCompanyId = (startupCompanyProfile?.companyId ?? '').trim();
  final startupDriverCompanyMatch = startupDriverSession == null
      ? false
      : (startupDriverCompany.isNotEmpty &&
            startupCompanyId.isNotEmpty &&
            startupDriverCompany == startupCompanyId);
  debugPrint(
    '[STARTUP][DRIVER] hasSession=${startupDriverSession != null}'
    ' mode=$startupDriverMode'
    ' hasToken=$startupDriverHasToken'
    ' companyMatch=$startupDriverCompanyMatch'
    ' useStandalonePointer=${!_startInCompanyAdminHome}',
  );
  if (!_startInCompanyAdminHome && startupDriverSession != null) {
    if (_isCompanyAdminDriverViewSession(startupDriverSession)) {
      debugPrint('[DRIVER_ADMIN_VIEW][IGNORE_FOR_NORMAL_LOGIN]');
    } else {
      setAppRole(AppRole.driver);
      _startInDriverHome = true;
      debugPrint('[DRIVER_PAIRING][AUTO_ROUTE] target=driver_home');
    }
  }
  // Mapbox REST token is optional in this build.
  // If not provided, the app will fall back to Worker-side routing where possible.
  if (kMapboxToken.trim().isEmpty) {
    // ignore: avoid_print
    print('⚠️ MAPBOX_TOKEN not set (using fallback routing).');
  } else {
    mb.MapboxOptions.setAccessToken(kMapboxToken);
  }
  // App-level Mollie return-to-app coordinator. Started here (not inside any
  // screen State) so deep links + lifecycle resume are handled regardless of
  // which page is currently mounted.
  paymentReturnCoordinator.start(bookingBaseUrl: kBookingBaseUrl);
  registerCompanyDriverManagementPageBuilder(
    () => const CompanyDriverManagementPage(),
  );
  runApp(const FluxidiDriverApp());
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(
      _runStartupDeferredWork(
        hasLocalCompanyContext: hasLocalCompanyContext,
        hasBootstrapToken: hasBootstrapToken,
      ),
    );
  });
}

/// ===============================
/// CONFIG
/// ===============================

/// ✅ Production default Worker base URL (NO trailing slash)
final String kWorkerBaseUrlDefault = appConfig.workerBaseUrl;

/// Optional override via dart-define (handig voor staging)
/// flutter run ... --dart-define=WORKER_BASE_URL=https://...workers.dev
const String kWorkerBaseUrlOverride = String.fromEnvironment(
  'WORKER_BASE_URL',
  defaultValue: '',
);

String get kWorkerBaseUrl {
  final v = kWorkerBaseUrlOverride.trim();
  if (v.isNotEmpty) return v.endsWith('/') ? v.substring(0, v.length - 1) : v;
  return kWorkerBaseUrlDefault;
}

/// Driver id for Worker `driver_id` fields — chauffeur session [DriverProfile.id] when logged in,
/// otherwise [kFallbackDriverTrackingId] for legacy/company-preview driver view.

Uri _withActiveBookingScope(
  String baseUrl,
  String path, {
  Map<String, String>? extraQuery,
}) {
  final scoped = <String, String>{
    ..._activeBookingScopeQuery(),
    ...?extraQuery,
  };
  return Uri.parse('$baseUrl$path').replace(queryParameters: scoped);
}

({String tenantId, String companyId})? _strictComplianceScopeFromValues({
  required List<dynamic> tenantCandidates,
  required List<dynamic> companyCandidates,
}) {
  String pick(List<dynamic> values) {
    for (final value in values) {
      final text = (value ?? '').toString().trim();
      if (text.isEmpty) continue;
      final lower = text.toLowerCase();
      if (lower == 'null' || lower == 'undefined') continue;
      return text;
    }
    return '';
  }

  final tenantId = pick(tenantCandidates);
  final companyId = pick(companyCandidates);
  if (tenantId.isEmpty || companyId.isEmpty) return null;
  return (tenantId: tenantId, companyId: companyId);
}

const String kAdminToken = String.fromEnvironment(
  'ADMIN_TOKEN',
  defaultValue: '',
);
const bool _fluxidiDevPairingBypass = bool.fromEnvironment(
  'FLUXIDI_DEV_PAIRING_BYPASS',
);
const String _fluxidiDevTenantId = String.fromEnvironment(
  'FLUXIDI_DEV_TENANT_ID',
);
const String _fluxidiDevCompanyId = String.fromEnvironment(
  'FLUXIDI_DEV_COMPANY_ID',
);
bool get _effectiveFluxidiDevPairingBypass =>
    _fluxidiDevPairingBypass && !kReleaseMode;

/// Endpoints (adjust if your Worker uses different paths)
const String kListBookingsPath = '/bookings';
const String kDriverBookingsPath = '/driver/bookings';
const String kGetBookingPath =
    '/track/booking'; // returns booking + quote/pricing
const String kTrackingBookingPath =
    '/tracking/booking'; // booking Worker detail endpoint

// Admin endpoints (require x-admin-token if enabled in Worker)
const String kUpdateBookingStatusPath =
    '/bookings'; // POST /bookings/:id/status
const String kBookingCreditDecisionPath =
    '/bookings'; // POST /bookings/:id/credit-decision
const String kBookingMollieRefundPath =
    '/bookings'; // POST /bookings/:id/mollie-refund
const String kBookingMollieRefundStatusRefreshPath =
    '/bookings'; // POST /bookings/:id/mollie-refund/status-refresh
const String kDeleteBookingPath = '/bookings'; // POST /bookings/:id/delete

const String kStartTripPath = '/track/session/start';
const String kPingPath = '/track/ping';
const String kStopTripPath = '/track/session/stop'; // optional
const String kStartDirectTripPath = '/trip/start-direct';
const String kRecordPlannedTripStopPath = '/trip/record-planned-stop';
const String kDirectTripWaitStartPath = '/trip/wait-start';
const String kDirectTripWaitEndPath = '/trip/wait-end';
const String kStopDirectTripPath = '/trip/stop';
const String kTripsHistoryPath = '/trips/history';
const String kTripsArchivePath = '/trips/archive';

const String kWorkerRoutePath = '/track/route';

final String kFluxidiLogoAsset = appConfig.logoAsset;

/// Fluxidi Taxi colors (premium black + warm taxi yellow)
final Color kFluxidiYellow = appConfig.primaryColor;
final Color kFluxidiYellowSoft = appConfig.branding.softAccentColor;
final Color kFluxidiBlack = appConfig.backgroundColor;
final Color kFluxidiPanel = appConfig.branding.surfaceColor;
final Color kFluxidiCard = appConfig.branding.cardColor;
final Color kFluxidiTextSoft = appConfig.branding.textSoftColor;

String _tr({
  required String nl,
  required String en,
  required String fr,
  required String es,
}) {
  final lang = appConfig.currentLanguage;
  if (lang == AppLanguage.en) return en;
  if (lang == AppLanguage.fr) return fr;
  if (lang == AppLanguage.es) return es;
  return nl;
}

class _CompanySessionRecoveryRoleEntryGate extends StatefulWidget {
  const _CompanySessionRecoveryRoleEntryGate();

  @override
  State<_CompanySessionRecoveryRoleEntryGate> createState() =>
      _CompanySessionRecoveryRoleEntryGateState();
}

class _CompanySessionRecoveryRoleEntryGateState
    extends State<_CompanySessionRecoveryRoleEntryGate> {
  @override
  void initState() {
    super.initState();
    if (!_startupBlockedCompanySessionRecovery) return;
    _startupBlockedCompanySessionRecovery = false;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _showDegradedCompanySessionRecoveryDialog(
        context,
        reason: 'startup_blocked_no_token',
      );
      if (!mounted) return;
      await _navigateToBusinessHomeWithBootstrapHydration(
        context,
        reason: 'startup_after_recovery',
      );
    });
  }

  @override
  Widget build(BuildContext context) => const RoleEntryPage();
}

class FluxidiDriverApp extends StatelessWidget {
  const FluxidiDriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    // ✅ Less dark / better contrast
    final theme = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: kFluxidiBlack,
      colorScheme: ColorScheme.dark(
        primary: kFluxidiYellow,
        secondary: kFluxidiYellow,
        surface: kFluxidiPanel,
        error: const Color(0xFFED6A5A),
        onPrimary: Colors.black,
        onSecondary: Colors.black,
      ),
      textTheme: Typography.whiteMountainView.apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: kFluxidiYellow,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(color: kFluxidiYellow, width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );

    final Widget startupTarget = _startInCompanyAdminHome
        ? const BusinessHomePage()
        : (_startInDriverHome
              ? const DriverHomePage()
              : const _CompanySessionRecoveryRoleEntryGate());
    final bool shouldGateStartupSession =
        _startInCompanyAdminHome || _startInDriverHome;

    return ValueListenableBuilder(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: kAppTitle,
        theme: theme,
        navigatorObservers: <NavigatorObserver>[kAppRouteObserver],
        builder: (context, child) {
          return FluxidiFrame(child: child ?? const SizedBox.shrink());
        },
        home: FluxidiAppLockGatePage(
          target: startupTarget,
          shouldGate: shouldGateStartupSession,
        ),
      ),
    );
  }
}

class CompanyDriverManagementPage extends StatefulWidget {
  const CompanyDriverManagementPage({super.key});

  @override
  State<CompanyDriverManagementPage> createState() =>
      _CompanyDriverManagementPageState();
}

final List<Map<String, dynamic>> _customerRegionLeadInbox =
    <Map<String, dynamic>>[];

enum _CameraMode { overview, follow }

enum _RideRoutePhase { toPickup, trip }

enum _DriverDashboardStatus { busy, waiting, onTheWay, pause, ready }

enum MapThemeMode { light, dark }

class _PlaceSuggestion {
  final String label;
  final double? lon;
  final double? lat;
  const _PlaceSuggestion({required this.label, this.lon, this.lat});
}

class _ExternalNavTarget {
  final double? lat;
  final double? lon;
  final String? query;

  const _ExternalNavTarget({this.lat, this.lon, this.query});

  bool get hasCoordinates => lat != null && lon != null;
  bool get hasQuery => (query ?? '').trim().isNotEmpty;
}

typedef _LonLat = DriverLonLat;
typedef _NavStep = DriverNavStep;
typedef _RouteSnap = DriverRouteSnap;

class _RoutePreviewData {
  final String staticMapUrl;
  final int routePointCount;

  const _RoutePreviewData({
    required this.staticMapUrl,
    required this.routePointCount,
  });
}

class _UnauthorizedMapbox implements Exception {
  final String where;
  _UnauthorizedMapbox(this.where);

  @override
  String toString() => 'Mapbox unauthorized ($where)';
}

class DriverHomePage extends StatefulWidget {
  const DriverHomePage({super.key, this.openedFromBusinessHome = false});

  final bool openedFromBusinessHome;

  @override
  State<DriverHomePage> createState() => _DriverHomePageState();
}

class _RideReceiptPage extends StatelessWidget {
  final _TripHistoryItem item;

  /// Effective chauffeur-theme source for this receipt. Mirrors the pattern
  /// already used by [_TripHistoryPage], [_BookingsHubPage], [CalculatorPage]
  /// and [DriverMyDocumentsPage]: when omitted the page falls back to the
  /// global [driverThemeNotifier] (standalone personal driver theme), and
  /// when provided it follows the caller's active driver-theme listenable.
  /// Opening from Driver History forwards `_activeDriverThemeListenable`,
  /// which resolves to `companyDriverViewThemeNotifier` in the business /
  /// admin chauffeur view and to `driverAppThemeNotifier` in the standalone
  /// driver app, so the receipt detail uses the same chauffeur palette as
  /// the History list.
  final ValueListenable<DriverThemeVariant>? driverThemeListenable;

  const _RideReceiptPage({required this.item, this.driverThemeListenable});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) => _RideReceiptBody(
        item: item,
        initialAction: null,
        autoPopAfterInitialAction: false,
        showReceiptUi: true,
        driverThemeListenable: driverThemeListenable,
      ),
    );
  }
}

class _RideReceiptBody extends StatefulWidget {
  final _TripHistoryItem item;
  final _ReceiptQuickAction? initialAction;
  final bool autoPopAfterInitialAction;
  final bool showReceiptUi;
  final ValueListenable<DriverThemeVariant>? driverThemeListenable;

  const _RideReceiptBody({
    required this.item,
    this.initialAction,
    this.autoPopAfterInitialAction = false,
    this.showReceiptUi = true,
    this.driverThemeListenable,
  });

  @override
  State<_RideReceiptBody> createState() => _RideReceiptBodyState();
}
