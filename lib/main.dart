import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'dart:convert';
import 'dart:io' show Directory, File, FileMode, Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show ValueListenable, ValueNotifier, kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
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
import 'package:fluxidi_tracking/calculator_page.dart';
import 'package:fluxidi_tracking/customer_booking_store.dart';
import 'package:fluxidi_tracking/customer_bookings_store.dart';
import 'package:fluxidi_tracking/customer_profile_store.dart';
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
import 'package:fluxidi_tracking/business_settings_page.dart';
import 'package:fluxidi_tracking/vehicle_management_page.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company_session_store.dart';
import 'package:fluxidi_tracking/company_onboarding_page.dart';
import 'package:fluxidi_tracking/chiron_compliance_dashboard_page.dart';
import 'package:fluxidi_tracking/driver_documents_store.dart';
import 'package:fluxidi_tracking/driver_document_sheet.dart';
import 'package:fluxidi_tracking/driver_my_documents_page.dart';
import 'package:fluxidi_tracking/driver_session_store.dart';

import 'widgets/cockpit_widget.dart';
import 'widgets/route_marquee.dart';

final bool kIsWindows = !kIsWeb && Platform.isWindows;

CustomerProfile? _cachedCustomerProfile;

Future<void> _refreshCachedCustomerProfile() async {
  _cachedCustomerProfile = await CustomerProfileStore.instance.load();
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

/// ✅ Mapbox token for REST calls (geocoding + directions).
/// Set at run/build time:
/// flutter run --dart-define=MAPBOX_TOKEN=pk.xxx
const String kMapboxToken = String.fromEnvironment(
  'MAPBOX_TOKEN',
  defaultValue: '',
);

Map<String, String> _adminHeaders() {
  final t = kAdminToken.trim();
  if (t.isEmpty) return <String, String>{};
  return <String, String>{'Authorization': 'Bearer $t', 'x-admin-token': t};
}

// Pending Mollie payment tracking lives in lib/payment_return.dart and is
// re-exported above so existing references in this file (and other modules)
// keep working unchanged.

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadLocalTenantState();
  await _refreshCachedCustomerProfile();
  await CompanySessionStore.instance.bootstrap();
  await DriverSessionStore.instance.bootstrap(driversNotifier.value);
  await DriverDocumentsStore.instance.load();
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
  runApp(const FluxidiDriverApp());
}

/// ===============================
/// CONFIG
/// ===============================

/// ✅ Production default Worker base URL (NO trailing slash)
final String kWorkerBaseUrlDefault = appConfig.workerBaseUrl;

/// ✅ Booking API base URL (used for pricing + route helpers).
/// Default points to the booking Worker (NOT the tracking API Worker).
final String kBookingBaseUrlDefault = appConfig.bookingBaseUrl;

/// Optional override via dart-define (handy for staging)
/// flutter run ... --dart-define=BOOKING_BASE_URL=https://...workers.dev
const String kBookingBaseUrlOverride = String.fromEnvironment(
  'BOOKING_BASE_URL',
  defaultValue: '',
);

String get kBookingBaseUrl {
  final v = kBookingBaseUrlOverride.trim();
  if (v.isNotEmpty) return v.endsWith('/') ? v.substring(0, v.length - 1) : v;
  return kBookingBaseUrlDefault;
}

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
String get kDriverId => resolvedDriverTrackingId;

const bool kDriverAllowAllCompanyRidesDebug = false;
const bool kDriverCanSeeUnassignedRides = false;

String _driverOwnershipBlockedMessage() => _tr(
  nl: 'Deze rit is niet aan jou of jouw voertuig toegewezen.',
  en: 'This ride is not assigned to you or your vehicle.',
  fr: 'This ride is not assigned to you or your vehicle.',
  es: 'This ride is not assigned to you or your vehicle.',
);

String _resolvedActiveDriverIdForScope() {
  final sessionId = activeDriverSessionNotifier.value?.driverId.trim() ?? '';
  if (sessionId.isNotEmpty) return sessionId;
  final resolvedId = resolvedDriverTrackingId.trim();
  if (resolvedId.isNotEmpty) return resolvedId;
  return kDriverId.trim();
}

String? _bookingScopeText(Map<String, dynamic> booking, List<String> path) {
  dynamic cursor = booking;
  for (final segment in path) {
    if (cursor is! Map || !cursor.containsKey(segment)) return null;
    cursor = cursor[segment];
  }
  final text = cursor?.toString().trim() ?? '';
  if (text.isEmpty || text.toLowerCase() == 'null') return null;
  return text;
}

String? _bookingScopeFirstText(
  Map<String, dynamic> booking,
  List<List<String>> paths,
) {
  for (final path in paths) {
    final value = _bookingScopeText(booking, path);
    if (value != null) return value;
  }
  return null;
}

Set<String> _activeDriverLinkedVehicleIds() {
  final activeDriverId = _resolvedActiveDriverIdForScope().trim();
  if (activeDriverId.isEmpty) return const <String>{};
  final activeCompany = resolvedCompanyId.trim().isNotEmpty
      ? resolvedCompanyId.trim()
      : kOutboundTenantId.trim();
  final ids = <String>{};
  for (final vehicle in vehiclesNotifier.value) {
    if (!vehicle.isActive) continue;
    final vehicleId = vehicle.id.trim();
    if (vehicleId.isEmpty) continue;
    final driverId = vehicle.driverId?.trim() ?? '';
    if (driverId != activeDriverId) continue;
    final vehicleCompany = vehicle.companyId?.trim() ?? '';
    if (vehicleCompany.isNotEmpty &&
        activeCompany.isNotEmpty &&
        vehicleCompany != activeCompany) {
      continue;
    }
    ids.add(vehicleId);
  }
  return ids;
}

bool _bookingBelongsToActiveDriver(Map<String, dynamic> booking) {
  final activeDriverId = _resolvedActiveDriverIdForScope().trim();
  if (activeDriverId.isEmpty) return false;
  final linkedVehicleIds = _activeDriverLinkedVehicleIds();
  final assignedDriverId = _bookingScopeFirstText(booking, const [
    ['assigned_driver', 'driver_id'],
    ['assigned_driver', 'driverId'],
    ['assigned_driver', 'id'],
    ['assignedDriver', 'driver_id'],
    ['assignedDriver', 'driverId'],
    ['assignedDriver', 'id'],
    ['driver_id'],
    ['driverId'],
    ['booking', 'assigned_driver', 'driver_id'],
    ['booking', 'assigned_driver', 'driverId'],
    ['booking', 'assigned_driver', 'id'],
    ['booking', 'assignedDriver', 'driver_id'],
    ['booking', 'assignedDriver', 'driverId'],
    ['booking', 'assignedDriver', 'id'],
    ['booking', 'driver_id'],
    ['booking', 'driverId'],
    ['record', 'booking', 'assigned_driver', 'driver_id'],
    ['record', 'booking', 'assigned_driver', 'driverId'],
    ['record', 'booking', 'assigned_driver', 'id'],
    ['record', 'booking', 'assignedDriver', 'driver_id'],
    ['record', 'booking', 'assignedDriver', 'driverId'],
    ['record', 'booking', 'assignedDriver', 'id'],
    ['record', 'booking', 'driver_id'],
    ['record', 'booking', 'driverId'],
  ]);
  if (assignedDriverId == activeDriverId) return true;

  final assignedVehicleId = _bookingScopeFirstText(booking, const [
    ['assigned_vehicle_id'],
    ['assignedVehicleId'],
    ['vehicle_id'],
    ['vehicleId'],
    ['booking', 'assigned_vehicle_id'],
    ['booking', 'assignedVehicleId'],
    ['booking', 'vehicle_id'],
    ['booking', 'vehicleId'],
    ['record', 'booking', 'assigned_vehicle_id'],
    ['record', 'booking', 'assignedVehicleId'],
    ['record', 'booking', 'vehicle_id'],
    ['record', 'booking', 'vehicleId'],
  ]);
  if (assignedVehicleId != null &&
      assignedVehicleId.isNotEmpty &&
      linkedVehicleIds.contains(assignedVehicleId)) {
    return true;
  }
  return false;
}

bool _bookingIsUnassigned(Map<String, dynamic> booking) {
  final assignedDriverId = _bookingScopeFirstText(booking, const [
    ['assigned_driver', 'driver_id'],
    ['assigned_driver', 'driverId'],
    ['assigned_driver', 'id'],
    ['assignedDriver', 'driver_id'],
    ['assignedDriver', 'driverId'],
    ['assignedDriver', 'id'],
    ['driver_id'],
    ['driverId'],
    ['booking', 'assigned_driver', 'driver_id'],
    ['booking', 'assigned_driver', 'driverId'],
    ['booking', 'assigned_driver', 'id'],
    ['booking', 'assignedDriver', 'driver_id'],
    ['booking', 'assignedDriver', 'driverId'],
    ['booking', 'assignedDriver', 'id'],
    ['booking', 'driver_id'],
    ['booking', 'driverId'],
  ]);
  final assignedVehicleId = _bookingScopeFirstText(booking, const [
    ['assigned_vehicle_id'],
    ['assignedVehicleId'],
    ['vehicle_id'],
    ['vehicleId'],
    ['booking', 'assigned_vehicle_id'],
    ['booking', 'assignedVehicleId'],
    ['booking', 'vehicle_id'],
    ['booking', 'vehicleId'],
  ]);
  return (assignedDriverId == null || assignedDriverId.isEmpty) &&
      (assignedVehicleId == null || assignedVehicleId.isEmpty);
}

bool _canActiveDriverOperateBooking(Map<String, dynamic> booking) {
  final role = appRoleNotifier.value;
  if (role == AppRole.companyAdmin || role == AppRole.dispatcher) return true;
  if (role != AppRole.driver) return true;
  if (kDriverAllowAllCompanyRidesDebug) return true;
  return _bookingBelongsToActiveDriver(booking);
}

Map<String, dynamic> _driverMutationActorFields({String? actorVehicleId}) {
  if (appRoleNotifier.value != AppRole.driver) return const <String, dynamic>{};
  final driverId = resolvedDriverTrackingId.trim();
  final vehicleId = (actorVehicleId ?? '').trim();
  return <String, dynamic>{
    'actor_role': 'driver',
    'actorRole': 'driver',
    if (driverId.isNotEmpty) ...{
      'actor_driver_id': driverId,
      'actorDriverId': driverId,
      'driver_id': driverId,
      'driverId': driverId,
    },
    if (vehicleId.isNotEmpty) ...{
      'actor_vehicle_id': vehicleId,
      'actorVehicleId': vehicleId,
    },
  };
}

bool _outboundTenantFallbackLogged = false;

/// Tenant id for outbound ride/trip Worker payloads.
///
/// Prefer local [CompanyProfile.companyId] ([resolvedCompanyId]) when available.
/// This value is still MVP/provisional client state: backend must later issue
/// the authoritative tenant id for production compliance (including Chiron).
String get kOutboundTenantId {
  final localCompanyId = companyProfileNotifier.value?.companyId.trim();
  if (localCompanyId != null && localCompanyId.isNotEmpty) {
    return localCompanyId;
  }
  if (!_outboundTenantFallbackLogged) {
    _outboundTenantFallbackLogged = true;
    debugPrint(
      '[TENANT][OUTBOUND][FALLBACK] Using default tenant id (no local company profile id).',
    );
  }
  return kTenantId;
}

Map<String, String> _activeBookingScopeQuery() {
  final tenantId = kOutboundTenantId.trim();
  final companyIdRaw = resolvedCompanyId.trim();
  final companyId = companyIdRaw.isNotEmpty ? companyIdRaw : tenantId;
  return <String, String>{
    'tenant_id': tenantId,
    'company_id': companyId,
    'tenantId': tenantId,
    'companyId': companyId,
  };
}

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

/// Admin token (optional) for driver actions like complete/cancel/delete.
/// Set at run/build time:
/// flutter run --dart-define=ADMIN_TOKEN=yourSecret
const String kAdminToken = String.fromEnvironment(
  'ADMIN_TOKEN',
  defaultValue: '',
);

/// Endpoints (adjust if your Worker uses different paths)
const String kListBookingsPath = '/bookings';
const String kGetBookingPath =
    '/track/booking'; // returns booking + quote/pricing
const String kTrackingBookingPath =
    '/tracking/booking'; // booking Worker detail endpoint

// Admin endpoints (require x-admin-token if enabled in Worker)
const String kUpdateBookingStatusPath =
    '/bookings'; // POST /bookings/:id/status
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

/// Optional: Worker route endpoint (recommended, avoids exposing Mapbox token)
/// Implement later in Worker: POST { from, to } -> { coords:[[lon,lat],...], distance_m, duration_s }
const String kWorkerRoutePath = '/track/route';

String _localScopePathSegment(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return 'default';
  final sanitized = trimmed.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  if (sanitized.isEmpty) return 'default';
  return sanitized;
}

String _maskLocalScopeId(String value) {
  final trimmed = value.trim();
  if (trimmed.length <= 6) return trimmed;
  return '${trimmed.substring(0, 3)}...${trimmed.substring(trimmed.length - 3)}';
}

({String tenantId, String companyId}) _activeLocalScopeIds() {
  final resolvedId = resolvedCompanyId.trim();
  final tenantId = resolvedId.isNotEmpty
      ? resolvedId
      : kOutboundTenantId.trim();
  final companyId = resolvedId.isNotEmpty ? resolvedId : tenantId;
  return (tenantId: tenantId, companyId: companyId);
}

/// Phase 0b local-only compliance ledger sink (append-only JSONL).
/// Best-effort by design: write failures must never break ride UX.
class _ComplianceRideLedgerStore {
  static const String _fileName = 'compliance_ledger_v1.jsonl';

  static Future<File> _legacyFile() async {
    final base = await getApplicationDocumentsDirectory();
    return File('${base.path}${Platform.pathSeparator}$_fileName');
  }

  static Future<File> _scopedFile({
    required String tenantId,
    required String companyId,
  }) async {
    final base = await getApplicationDocumentsDirectory();
    final scopedDir = Directory(
      '${base.path}${Platform.pathSeparator}compliance_state${Platform.pathSeparator}tenant_${_localScopePathSegment(tenantId)}${Platform.pathSeparator}company_${_localScopePathSegment(companyId)}',
    );
    if (!await scopedDir.exists()) {
      await scopedDir.create(recursive: true);
    }
    final file = File('${scopedDir.path}${Platform.pathSeparator}$_fileName');
    debugPrint(
      '[LOCAL_SCOPE][COMPLIANCE_FILTER] target=write tenant=${_maskLocalScopeId(tenantId)} company=${_maskLocalScopeId(companyId)} file=${file.path}',
    );
    return file;
  }

  static Future<File> _fileForRecord(Map<String, dynamic> record) async {
    final activeScope = _activeLocalScopeIds();
    final tenantId = (record['tenant_id'] ?? '').toString().trim().isNotEmpty
        ? (record['tenant_id'] ?? '').toString().trim()
        : activeScope.tenantId;
    final companyId = (record['company_id'] ?? '').toString().trim().isNotEmpty
        ? (record['company_id'] ?? '').toString().trim()
        : activeScope.companyId;
    return _scopedFile(tenantId: tenantId, companyId: companyId);
  }

  static Future<void> append(Map<String, dynamic> record) async {
    if (kIsWeb) return;
    try {
      final file = await _fileForRecord(record);
      if (!await file.exists()) {
        await file.create(recursive: true);
      }
      final line = '${jsonEncode(record)}\n';
      await file.writeAsString(line, mode: FileMode.append, flush: true);
    } catch (_) {
      // Keep stop-flow resilient; caller handles logging.
    }
  }
}

Future<void> _writeComplianceLedgerRecord({
  required Map<String, dynamic> record,
}) async {
  try {
    await _ComplianceRideLedgerStore.append(record);
    debugPrint(
      '[COMPLIANCE_LEDGER][WRITE] event_type=${record['event_type']} ride_type=${record['ride_type']} validation_state=${record['provenance']?['validation_state']} backend_confirmed=${record['provenance']?['backend_confirmed']}',
    );
  } catch (e) {
    debugPrint('[COMPLIANCE_LEDGER][WARN] write_failed reason=$e');
  }
}

/// Local fallback store for direct rides that stayed local-only (no backend trip).
/// Kept isolated from backend history to avoid changing server behavior.
class _LocalDirectTripHistoryStore {
  static const String _fileName = 'local_direct_trip_history_v1.jsonl';

  static Future<File> _legacyFile() async {
    final base = await getApplicationDocumentsDirectory();
    return File('${base.path}${Platform.pathSeparator}$_fileName');
  }

  static Future<File> _scopedFile({
    required String tenantId,
    required String companyId,
  }) async {
    final base = await getApplicationDocumentsDirectory();
    final scopedDir = Directory(
      '${base.path}${Platform.pathSeparator}compliance_state${Platform.pathSeparator}tenant_${_localScopePathSegment(tenantId)}${Platform.pathSeparator}company_${_localScopePathSegment(companyId)}',
    );
    if (!await scopedDir.exists()) {
      await scopedDir.create(recursive: true);
    }
    return File('${scopedDir.path}${Platform.pathSeparator}$_fileName');
  }

  static Future<File> _fileForRecord(Map<String, dynamic> record) async {
    final activeScope = _activeLocalScopeIds();
    final tenantId = (record['tenant_id'] ?? '').toString().trim().isNotEmpty
        ? (record['tenant_id'] ?? '').toString().trim()
        : activeScope.tenantId;
    final companyId = (record['company_id'] ?? '').toString().trim().isNotEmpty
        ? (record['company_id'] ?? '').toString().trim()
        : activeScope.companyId;
    return _scopedFile(tenantId: tenantId, companyId: companyId);
  }

  static bool _matchesScope(
    Map<String, dynamic> row, {
    required String tenantId,
    required String companyId,
    required bool allowLegacyWithoutScope,
  }) {
    final rowTenant = (row['tenant_id'] ?? '').toString().trim();
    final rowCompany = (row['company_id'] ?? '').toString().trim();
    if (rowTenant.isEmpty && rowCompany.isEmpty) {
      return allowLegacyWithoutScope;
    }
    if (rowTenant.isNotEmpty && rowTenant != tenantId.trim()) return false;
    if (rowCompany.isNotEmpty && rowCompany != companyId.trim()) return false;
    return true;
  }

  static Future<List<Map<String, dynamic>>> _readFromFile(
    File file, {
    required String tenantId,
    required String companyId,
    required String driverId,
    required int limit,
    required bool allowLegacyWithoutScope,
  }) async {
    if (!await file.exists()) return const <Map<String, dynamic>>[];
    final lines = await file.readAsLines();
    final parsed = <Map<String, dynamic>>[];
    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      try {
        final decoded = jsonDecode(line);
        if (decoded is! Map) continue;
        final map = Map<String, dynamic>.from(decoded);
        final rowDriver = (map['driver_id'] ?? '').toString().trim();
        if (rowDriver != driverId.trim()) continue;
        if (!_matchesScope(
          map,
          tenantId: tenantId,
          companyId: companyId,
          allowLegacyWithoutScope: allowLegacyWithoutScope,
        )) {
          continue;
        }
        parsed.add(map);
      } catch (_) {
        // Ignore malformed JSONL entries to keep history resilient.
      }
    }
    if (parsed.length <= limit) return parsed;
    return parsed.sublist(parsed.length - limit);
  }

  static Future<void> append(Map<String, dynamic> record) async {
    if (kIsWeb) return;
    try {
      final file = await _fileForRecord(record);
      if (!await file.exists()) {
        await file.create(recursive: true);
      }
      await file.writeAsString(
        '${jsonEncode(record)}\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // Best-effort only; do not break ride stop flow.
    }
  }

  static Future<List<Map<String, dynamic>>> readFor({
    required String tenantId,
    required String driverId,
    int limit = 120,
  }) async {
    if (kIsWeb) return const <Map<String, dynamic>>[];
    try {
      final activeScope = _activeLocalScopeIds();
      final scopedFile = await _scopedFile(
        tenantId: tenantId.trim().isNotEmpty ? tenantId : activeScope.tenantId,
        companyId: activeScope.companyId,
      );
      if (await scopedFile.exists()) {
        return _readFromFile(
          scopedFile,
          tenantId: tenantId,
          companyId: activeScope.companyId,
          driverId: driverId,
          limit: limit,
          allowLegacyWithoutScope: true,
        );
      }
      final legacyFile = await _legacyFile();
      return _readFromFile(
        legacyFile,
        tenantId: tenantId,
        companyId: activeScope.companyId,
        driverId: driverId,
        limit: limit,
        allowLegacyWithoutScope: true,
      );
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }
}

/// ===============================
/// BRANDING (Fluxidi Taxi UI)
/// ===============================

/// Put your logo in this path (recommended):
///   assets/fluxidi/fluxidi_logo.png
/// and add it to pubspec.yaml under flutter/assets.
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

String _receiptText(String key) {
  switch (key) {
    case 'receiptTitle':
      return _tr(nl: 'Ritbon', en: 'Receipt', fr: 'Reçu', es: 'Recibo');
    case 'rideReceipt':
      return _tr(
        nl: 'Bewijs van rit',
        en: 'Ride receipt',
        fr: 'Justificatif de course',
        es: 'Comprobante del viaje',
      );
    case 'receiptUnavailable':
      return _tr(
        nl: 'Ritbon is beschikbaar na afronden van de rit.',
        en: 'Receipt is available after completing the ride.',
        fr: 'Le reçu est disponible après la fin de la course.',
        es: 'El recibo esta disponible despues de finalizar el viaje.',
      );
    case 'tripHistoryTitle':
      return _tr(
        nl: 'Ritten historiek',
        en: 'Ride history',
        fr: 'Historique des courses',
        es: 'Historial de viajes',
      );
    case 'refresh':
      return _tr(
        nl: 'Vernieuw',
        en: 'Refresh',
        fr: 'Actualiser',
        es: 'Actualizar',
      );
    case 'historyLoadFailed':
      return _tr(
        nl: 'Kon ritten historiek niet laden.',
        en: 'Could not load ride history.',
        fr: "Impossible de charger l'historique.",
        es: 'No se pudo cargar el historial.',
      );
    case 'historyEmpty':
      return _tr(
        nl: 'Nog geen ritten gevonden.',
        en: 'No rides found yet.',
        fr: 'Aucune course trouvée.',
        es: 'Aun no hay viajes.',
      );
    case 'archiveTripLabel':
      return _tr(nl: 'Verberg', en: 'Hide', fr: 'Masquer', es: 'Ocultar');
    case 'archiveTripTitle':
      return _tr(
        nl: 'Deze rit verbergen uit de historiek?',
        en: 'Hide this ride from history?',
        fr: 'Masquer cette course de l’historique ?',
        es: '¿Ocultar este viaje del historial?',
      );
    case 'archiveTripBody':
      return _tr(
        nl: 'De ritbon blijft bewaard voor administratie.',
        en: 'The receipt will remain stored for administration.',
        fr: 'Le reçu reste conservé pour l’administration.',
        es: 'El recibo seguirá guardado para la administración.',
      );
    case 'archiveTripCancel':
      return _tr(nl: 'Annuleren', en: 'Cancel', fr: 'Annuler', es: 'Cancelar');
    case 'archiveTripConfirm':
      return _tr(nl: 'Verbergen', en: 'Hide', fr: 'Masquer', es: 'Ocultar');
    case 'archiveTripSuccess':
      return _tr(
        nl: 'Rit verborgen uit historiek.',
        en: 'Ride hidden from history.',
        fr: 'Course masquée de l’historique.',
        es: 'Viaje ocultado del historial.',
      );
    case 'archiveTripFailed':
      return _tr(
        nl: 'Kon rit niet verbergen.',
        en: 'Could not hide ride.',
        fr: 'Impossible de masquer la course.',
        es: 'No se pudo ocultar el viaje.',
      );
    case 'waitingCompact':
      return _tr(nl: 'wachten', en: 'waiting', fr: 'attente', es: 'espera');
    case 'type':
      return _tr(nl: 'Type', en: 'Type', fr: 'Type', es: 'Tipo');
    case 'streetRide':
      return _tr(
        nl: 'Straatrit',
        en: 'Street ride',
        fr: 'Course directe',
        es: 'Viaje directo',
      );
    case 'plannedRide':
      return _tr(
        nl: 'Geplande rit',
        en: 'Planned ride',
        fr: 'Course planifiée',
        es: 'Viaje planificado',
      );
    case 'outboundRide':
      return _tr(
        nl: 'Heenrit',
        en: 'Outbound ride',
        fr: 'Trajet aller',
        es: 'Viaje de ida',
      );
    case 'returnRide':
      return _tr(
        nl: 'Retourrit',
        en: 'Return ride',
        fr: 'Trajet retour',
        es: 'Viaje de vuelta',
      );
    case 'subtype':
      return _tr(nl: 'Subtype', en: 'Subtype', fr: 'Sous-type', es: 'Subtipo');
    case 'receiptNumber':
      return _tr(
        nl: 'Bonnummer',
        en: 'Receipt no.',
        fr: 'Numéro de reçu',
        es: 'Número de recibo',
      );
    case 'planningNumber':
      return _tr(
        nl: 'Planningnummer',
        en: 'Planning no.',
        fr: 'N° de planning',
        es: 'N.º de planificación',
      );
    case 'bookingNumber':
      return _tr(
        nl: 'Boekingsnummer',
        en: 'Booking no.',
        fr: 'N° de réservation',
        es: 'N.º de reserva',
      );
    case 'internalBooking':
      return _tr(
        nl: 'Interne boeking',
        en: 'Internal booking',
        fr: 'Réservation interne',
        es: 'Reserva interna',
      );
    case 'internalTrip':
      return _tr(
        nl: 'Interne rit',
        en: 'Internal trip',
        fr: 'Course interne',
        es: 'Viaje interno',
      );
    case 'tripId':
      return _tr(nl: 'Trip ID', en: 'Trip ID', fr: 'ID course', es: 'ID viaje');
    case 'bookingId':
      return _tr(
        nl: 'Booking ID',
        en: 'Booking ID',
        fr: 'ID réservation',
        es: 'ID reserva',
      );
    case 'date':
      return _tr(nl: 'Datum', en: 'Date', fr: 'Date', es: 'Fecha');
    case 'startTime':
      return _tr(
        nl: 'Starttijd',
        en: 'Start time',
        fr: 'Heure de début',
        es: 'Hora de inicio',
      );
    case 'endTime':
      return _tr(
        nl: 'Stoptijd',
        en: 'End time',
        fr: 'Heure de fin',
        es: 'Hora de fin',
      );
    case 'duration':
      return _tr(nl: 'Duur', en: 'Duration', fr: 'Durée', es: 'Duración');
    case 'pickup':
      return _tr(
        nl: 'Ophaaladres',
        en: 'Pickup',
        fr: 'Prise en charge',
        es: 'Recogida',
      );
    case 'destination':
      return _tr(
        nl: 'Bestemming',
        en: 'Destination',
        fr: 'Destination',
        es: 'Destino',
      );
    case 'from':
      return _tr(nl: 'Van', en: 'From', fr: 'De', es: 'Desde');
    case 'to':
      return _tr(nl: 'Naar', en: 'To', fr: 'À', es: 'A');
    case 'distance':
      return _tr(
        nl: 'Afstand',
        en: 'Distance',
        fr: 'Distance',
        es: 'Distancia',
      );
    case 'actualDistance':
      return _tr(
        nl: 'Werkelijke afstand',
        en: 'Actual distance',
        fr: 'Distance réelle',
        es: 'Distancia real',
      );
    case 'waitingTime':
      return _tr(
        nl: 'Wachttijd',
        en: 'Waiting time',
        fr: "Temps d'attente",
        es: 'Tiempo de espera',
      );
    case 'bookedWaitingTime':
      return _tr(
        nl: 'Geboekte wachttijd',
        en: 'Booked waiting time',
        fr: "Attente réservée",
        es: 'Espera reservada',
      );
    case 'actualWaitingTime':
      return _tr(
        nl: 'Werkelijke wachttijd',
        en: 'Actual waiting time',
        fr: "Attente réelle",
        es: 'Espera real',
      );
    case 'plannedBookingDetails':
      return _tr(
        nl: 'Geplande boeking',
        en: 'Planned booking details',
        fr: 'Détails de réservation',
        es: 'Detalles de reserva',
      );
    case 'bookingDetails':
      return _tr(
        nl: 'Boekingsdetails',
        en: 'Booking details',
        fr: 'Détails de réservation',
        es: 'Detalles de reserva',
      );
    case 'customer':
      return _tr(nl: 'Klant', en: 'Customer', fr: 'Client', es: 'Cliente');
    case 'customerDetails':
      return _tr(
        nl: 'Klantgegevens',
        en: 'Customer details',
        fr: 'Coordonnées client',
        es: 'Datos del cliente',
      );
    case 'customerName':
      return _tr(
        nl: 'Klantnaam',
        en: 'Customer name',
        fr: 'Nom du client',
        es: 'Nombre del cliente',
      );
    case 'customerPhone':
      return _tr(
        nl: 'Telefoon',
        en: 'Customer phone',
        fr: 'Téléphone client',
        es: 'Teléfono del cliente',
      );
    case 'customerEmail':
      return _tr(
        nl: 'E-mail',
        en: 'Customer email',
        fr: 'E-mail client',
        es: 'Email del cliente',
      );
    case 'scheduledPickup':
      return _tr(
        nl: 'Geplande ophaal',
        en: 'Scheduled pickup',
        fr: 'Prise en charge prévue',
        es: 'Recogida programada',
      );
    case 'service':
      return _tr(nl: 'Service', en: 'Service', fr: 'Service', es: 'Servicio');
    case 'passengerTransport':
      return _tr(
        nl: 'Personenvervoer',
        en: 'Passenger transport',
        fr: 'Transport de passagers',
        es: 'Transporte de pasajeros',
      );
    case 'businessRide':
      return _tr(
        nl: 'Zakelijke rit',
        en: 'Business ride',
        fr: "Course d'affaires",
        es: 'Viaje de negocios',
      );
    case 'airportTransfer':
      return _tr(
        nl: 'Luchthavenvervoer',
        en: 'Airport transfer',
        fr: 'Transfert aeroport',
        es: 'Traslado al aeropuerto',
      );
    case 'tier':
      return _tr(nl: 'Tier', en: 'Tier', fr: 'Catégorie', es: 'Categoría');
    case 'tierComfort':
      return _tr(nl: 'Comfort', en: 'Comfort', fr: 'Confort', es: 'Confort');
    case 'tierPrivate':
      return _tr(nl: 'Private', en: 'Private', fr: 'Prive', es: 'Privado');
    case 'tierPremium':
      return _tr(nl: 'Premium', en: 'Premium', fr: 'Premium', es: 'Premium');
    case 'passengers':
      return _tr(
        nl: 'Passagiers / Pax',
        en: 'Passengers / Pax',
        fr: 'Passagers / Pax',
        es: 'Pasajeros / Pax',
      );
    case 'bags':
      return _tr(nl: 'Bagage', en: 'Bags', fr: 'Bagages', es: 'Equipaje');
    case 'extraStops':
      return _tr(
        nl: 'Extra stops',
        en: 'Extra stops',
        fr: 'Arrêts supplémentaires',
        es: 'Paradas extra',
      );
    case 'extras':
      return _tr(nl: 'Extras', en: 'Extras', fr: 'Extras', es: 'Extras');
    case 'notes':
      return _tr(nl: 'Notities', en: 'Notes', fr: 'Notes', es: 'Notas');
    case 'routeAndPrices':
      return _tr(
        nl: 'Route en prijzen',
        en: 'Route and prices',
        fr: 'Itinéraire et prix',
        es: 'Ruta y precios',
      );
    case 'route':
      return _tr(nl: 'Route', en: 'Route', fr: 'Itinéraire', es: 'Ruta');
    case 'routeDetails':
      return _tr(
        nl: 'Route details',
        en: 'Route details',
        fr: "Détails de l'itinéraire",
        es: 'Detalles de ruta',
      );
    case 'outboundRoute':
      return _tr(
        nl: 'Heenroute',
        en: 'Outbound route',
        fr: 'Itinéraire aller',
        es: 'Ruta de ida',
      );
    case 'returnRoute':
      return _tr(
        nl: 'Retour route',
        en: 'Return route',
        fr: 'Itinéraire retour',
        es: 'Ruta de vuelta',
      );
    case 'returnTrip':
      return _tr(
        nl: 'Retourrit',
        en: 'Return trip',
        fr: 'Trajet retour',
        es: 'Viaje de vuelta',
      );
    case 'returnPlanned':
      return _tr(
        nl: 'Retour gepland',
        en: 'Return planned',
        fr: 'Retour prevu',
        es: 'Vuelta programada',
      );
    case 'fixedPrice':
      return _tr(
        nl: 'Vaste prijs',
        en: 'Fixed price',
        fr: 'Prix fixe',
        es: 'Precio fijo',
      );
    case 'fixedQuotePrice':
      return _tr(
        nl: 'Vaste offerteprijs',
        en: 'Fixed quote price',
        fr: 'Prix devis fixe',
        es: 'Precio fijo cotizado',
      );
    case 'packagePrice':
      return _tr(
        nl: 'Pakketprijs incl. btw',
        en: 'Package price incl. VAT',
        fr: 'Prix forfaitaire TVA incl.',
        es: 'Precio paquete IVA incl.',
      );
    case 'ridePrice':
      return _tr(
        nl: 'Ritprijs incl. btw',
        en: 'Ride price incl. VAT',
        fr: 'Prix course TVA incl.',
        es: 'Precio viaje IVA incl.',
      );
    case 'outboundPrice':
      return _tr(
        nl: 'Prijs heen incl. btw',
        en: 'Outbound price incl. VAT',
        fr: 'Prix aller TVA incl.',
        es: 'Precio ida IVA incl.',
      );
    case 'returnPrice':
      return _tr(
        nl: 'Prijs retour incl. btw',
        en: 'Return price incl. VAT',
        fr: 'Prix retour TVA incl.',
        es: 'Precio vuelta IVA incl.',
      );
    case 'total':
      return _tr(nl: 'Totaal', en: 'Total', fr: 'Total', es: 'Total');
    case 'amount':
      return _tr(nl: 'Bedrag', en: 'Amount', fr: 'Montant', es: 'Importe');
    case 'payment':
      return _tr(nl: 'Betalen', en: 'Payment', fr: 'Paiement', es: 'Pago');
    case 'receiptActions':
      return _tr(nl: 'Bon', en: 'Receipt', fr: 'Reçu', es: 'Recibo');
    case 'statusPaymentSection':
      return _tr(
        nl: 'Status en betaling',
        en: 'Status and payment',
        fr: 'Statut et paiement',
        es: 'Estado y pago',
      );
    case 'paymentActions':
      return _tr(nl: 'Betaalzone', en: 'Payment', fr: 'Paiement', es: 'Pago');
    case 'moreOptions':
      return _tr(
        nl: 'Meer opties',
        en: 'More options',
        fr: 'Plus d’options',
        es: 'Más opciones',
      );
    case 'payByQr':
      return _tr(
        nl: 'Betaal via QR',
        en: 'Pay by QR',
        fr: 'Payer par QR',
        es: 'Pagar con QR',
      );
    case 'cashReceived':
      return _tr(
        nl: 'Contant ontvangen',
        en: 'Cash received',
        fr: 'Espèces reçues',
        es: 'Efectivo recibido',
      );
    case 'paidByCardTerminal':
      return _tr(
        nl: 'Betaald via Bancontact',
        en: 'Paid by card terminal',
        fr: 'Payé par terminal bancaire',
        es: 'Pagado con terminal de tarjeta',
      );
    case 'confirmQrPaid':
      return _tr(
        nl: 'QR betaling bevestigd',
        en: 'QR payment confirmed',
        fr: 'Paiement QR confirme',
        es: 'Pago QR confirmado',
      );
    case 'paymentStatus':
      return _tr(
        nl: 'Betaalstatus',
        en: 'Payment status',
        fr: 'Statut du paiement',
        es: 'Estado del pago',
      );
    case 'rideStatus':
      return _tr(
        nl: 'Ritstatus',
        en: 'Ride status',
        fr: 'Statut de la course',
        es: 'Estado del viaje',
      );
    case 'paid':
      return _tr(nl: 'Betaald', en: 'Paid', fr: 'Payé', es: 'Pagado');
    case 'unpaid':
      return _tr(
        nl: 'Onbetaald',
        en: 'Unpaid',
        fr: 'Non payé',
        es: 'No pagado',
      );
    case 'paymentSent':
      return _tr(
        nl: 'Betaalverzoek verstuurd',
        en: 'Payment request sent',
        fr: 'Demande de paiement envoyée',
        es: 'Solicitud de pago enviada',
      );
    case 'paymentMarkedPaid':
      return _tr(
        nl: 'Betaling als betaald opgeslagen.',
        en: 'Payment saved as paid.',
        fr: 'Paiement enregistre comme paye.',
        es: 'Pago guardado como pagado.',
      );
    case 'paymentMarkFailed':
      return _tr(
        nl: 'Kon betaling niet opslaan. Probeer opnieuw.',
        en: 'Could not save payment. Please retry.',
        fr: 'Impossible denregistrer le paiement. Reessayez.',
        es: 'No se pudo guardar el pago. Intentalo de nuevo.',
      );
    case 'bookingIdMissing':
      return _tr(
        nl: 'Boekings-ID ontbreekt.',
        en: 'Booking ID is missing.',
        fr: 'ID de reservation manquant.',
        es: 'Falta el ID de reserva.',
      );
    case 'demoPayment':
      return _tr(
        nl: 'Markeer betaald (demo)',
        en: 'Mark paid (demo)',
        fr: 'Marquer comme payé (demo)',
        es: 'Marcar pagado (demo)',
      );
    case 'qrPayment':
      return _tr(
        nl: 'QR betaling',
        en: 'QR payment',
        fr: 'Paiement QR',
        es: 'Pago QR',
      );
    case 'showPaymentLink':
      return _tr(
        nl: 'Toon betaallink',
        en: 'Show payment link',
        fr: 'Voir le lien de paiement',
        es: 'Mostrar enlace de pago',
      );
    case 'showQrPayment':
      return _tr(
        nl: 'Toon QR betaling',
        en: 'Show QR payment',
        fr: 'Voir le QR de paiement',
        es: 'Mostrar pago QR',
      );
    case 'copyPaymentLink':
      return _tr(
        nl: 'Kopieer betaallink',
        en: 'Copy payment link',
        fr: 'Copier le lien de paiement',
        es: 'Copiar enlace de pago',
      );
    case 'sharePaymentRequest':
      return _tr(
        nl: 'Deel betaalverzoek',
        en: 'Share payment request',
        fr: 'Partager la demande de paiement',
        es: 'Compartir solicitud de pago',
      );
    case 'paymentPlaceholder':
      return _tr(
        nl: 'MVP: deze link is een interne demolink en verwerkt nog geen echte betalingen.',
        en: 'MVP: this is an internal demo link and does not process real payments yet.',
        fr: 'MVP : ce lien est un lien interne de démonstration et ne traite pas encore de paiements réels.',
        es: 'MVP: este enlace es un enlace interno de demostración y aún no procesa pagos reales.',
      );
    case 'driver':
      return _tr(
        nl: 'Chauffeur',
        en: 'Driver',
        fr: 'Chauffeur',
        es: 'Conductor',
      );
    case 'vehicle':
      return _tr(nl: 'Voertuig', en: 'Vehicle', fr: 'Véhicule', es: 'Vehículo');
    case 'licensePlate':
      return _tr(
        nl: 'Nummerplaat',
        en: 'License plate',
        fr: "Plaque d'immatriculation",
        es: 'Matricula',
      );
    case 'status':
      return _tr(nl: 'Status', en: 'Status', fr: 'Statut', es: 'Estado');
    case 'notAvailable':
      return _tr(
        nl: 'Niet beschikbaar',
        en: 'Not available',
        fr: 'Non disponible',
        es: 'No disponible',
      );
    case 'unknown':
      return _tr(
        nl: 'Onbekend',
        en: 'Unknown',
        fr: 'Inconnu',
        es: 'Desconocido',
      );
    case 'close':
      return _tr(nl: 'Sluiten', en: 'Close', fr: 'Fermer', es: 'Cerrar');
    case 'copy':
      return _tr(nl: 'Kopieer', en: 'Copy', fr: 'Copier', es: 'Copiar');
    case 'copyLink':
      return _tr(
        nl: 'Kopieer link',
        en: 'Copy link',
        fr: 'Copier le lien',
        es: 'Copiar enlace',
      );
    case 'share':
      return _tr(nl: 'Delen', en: 'Share', fr: 'Partager', es: 'Compartir');
    case 'shareReceipt':
      return _tr(
        nl: 'Deel bon',
        en: 'Share receipt',
        fr: 'Partager le reçu',
        es: 'Compartir recibo',
      );
    case 'send':
      return _tr(nl: 'Verstuur', en: 'Send', fr: 'Envoyer', es: 'Enviar');
    case 'emailReceipt':
      return _tr(
        nl: 'Mail bon',
        en: 'Email receipt',
        fr: 'Envoyer le reçu',
        es: 'Enviar recibo',
      );
    case 'printReceipt':
      return _tr(
        nl: 'Print bon',
        en: 'Print receipt',
        fr: 'Imprimer le reçu',
        es: 'Imprimir recibo',
      );
    case 'viewPdf':
      return _tr(
        nl: 'Bekijk PDF',
        en: 'View PDF',
        fr: 'Voir PDF',
        es: 'Ver PDF',
      );
    case 'sharePdf':
      return _tr(
        nl: 'Deel PDF',
        en: 'Share PDF',
        fr: 'Partager PDF',
        es: 'Compartir PDF',
      );
    case 'emailPdf':
      return _tr(
        nl: 'Stuur PDF via e-mail',
        en: 'Send PDF by email',
        fr: 'Envoyer PDF par e-mail',
        es: 'Enviar PDF por correo',
      );
    case 'whatsappPdf':
      return _tr(
        nl: 'Stuur PDF via WhatsApp',
        en: 'Send PDF via WhatsApp',
        fr: 'Envoyer PDF via WhatsApp',
        es: 'Enviar PDF por WhatsApp',
      );
    case 'pdfReady':
      return _tr(
        nl: 'PDF klaar om te delen.',
        en: 'PDF is ready to share.',
        fr: 'PDF prêt à partager.',
        es: 'PDF listo para compartir.',
      );
    case 'pdfGenerationFailed':
      return _tr(
        nl: 'PDF maken mislukt, we gebruiken de tekstversie.',
        en: 'PDF generation failed, using text fallback.',
        fr: 'Échec de génération PDF, utilisation de la version texte.',
        es: 'Falló la generación del PDF, usando versión de texto.',
      );
    case 'paymentReceiptLabel':
      return _tr(
        nl: 'Betaalbewijs / Ritbon',
        en: 'Payment receipt / Ride receipt',
        fr: 'Justificatif de paiement / Reçu de course',
        es: 'Comprobante de pago / Recibo de viaje',
      );
    case 'invoiceLabel':
      return _tr(nl: 'Factuur', en: 'Invoice', fr: 'Facture', es: 'Factura');
    case 'subtotalExVat':
      return _tr(
        nl: 'Subtotaal excl. btw',
        en: 'Subtotal excl. VAT',
        fr: 'Sous-total HT',
        es: 'Subtotal sin IVA',
      );
    case 'vatAmount':
      return _tr(
        nl: 'BTW-bedrag',
        en: 'VAT amount',
        fr: 'Montant TVA',
        es: 'Importe IVA',
      );
    case 'vatRate':
      return _tr(
        nl: 'BTW-tarief',
        en: 'VAT rate',
        fr: 'Taux TVA',
        es: 'Tasa IVA',
      );
    case 'paymentMethod':
      return _tr(
        nl: 'Betaalmethode',
        en: 'Payment method',
        fr: 'Méthode de paiement',
        es: 'Método de pago',
      );
    case 'paymentSource':
      return _tr(
        nl: 'Betalingsbron',
        en: 'Payment source',
        fr: 'Source du paiement',
        es: 'Origen del pago',
      );
    case 'company':
      return _tr(nl: 'Bedrijf', en: 'Company', fr: 'Entreprise', es: 'Empresa');
    case 'legalName':
      return _tr(
        nl: 'Juridische naam',
        en: 'Legal name',
        fr: 'Raison sociale',
        es: 'Razón social',
      );
    case 'companyAddress':
      return _tr(nl: 'Adres', en: 'Address', fr: 'Adresse', es: 'Dirección');
    case 'companyVat':
      return _tr(
        nl: 'BTW-nummer',
        en: 'VAT number',
        fr: 'Numéro TVA',
        es: 'NIF/IVA',
      );
    case 'companyPhone':
      return _tr(
        nl: 'Telefoon',
        en: 'Company phone',
        fr: 'Téléphone entreprise',
        es: 'Teléfono de empresa',
      );
    case 'companyEmail':
      return _tr(
        nl: 'E-mail',
        en: 'Company email',
        fr: 'E-mail entreprise',
        es: 'Email de empresa',
      );
    case 'companyWebsite':
      return _tr(nl: 'Website', en: 'Website', fr: 'Site web', es: 'Sitio web');
    case 'printLater':
      return _tr(
        nl: 'Printfunctie wordt later gekoppeld aan printer.',
        en: 'Printing will be connected to a printer later.',
        fr: 'L’impression sera connectée à une imprimante ultérieurement.',
        es: 'La impresión se conectará a una impresora más adelante.',
      );
    case 'whatsappReceipt':
      return _tr(
        nl: 'Stuur bon via WhatsApp',
        en: 'Send receipt via WhatsApp',
        fr: 'Envoyer le reçu via WhatsApp',
        es: 'Enviar recibo por WhatsApp',
      );
    case 'emailReceiptToCustomer':
      return _tr(
        nl: 'Mail bon naar klant',
        en: 'Email receipt to customer',
        fr: 'Envoyer le reçu au client',
        es: 'Enviar recibo al cliente',
      );
    case 'whatsappPaymentRequest':
      return _tr(
        nl: 'Stuur betaallink via WhatsApp',
        en: 'Send payment link via WhatsApp',
        fr: 'Envoyer le lien de paiement via WhatsApp',
        es: 'Enviar enlace de pago por WhatsApp',
      );
    case 'emailPaymentRequest':
      return _tr(
        nl: 'Mail betaallink naar klant',
        en: 'Email payment link to customer',
        fr: 'Envoyer le lien de paiement au client',
        es: 'Enviar enlace de pago al cliente',
      );
    case 'noCustomerContact':
      return _tr(
        nl: 'Geen klantcontactgegevens beschikbaar voor gerichte verzending.',
        en: 'No customer contact details available for targeted sending.',
        fr: 'Aucune coordonnée client disponible pour un envoi ciblé.',
        es: 'No hay datos de contacto del cliente disponibles para el envío directo.',
      );
    case 'phoneNeedsCountryCode':
      return _tr(
        nl: 'Gebruik een telefoonnummer met landcode, bijvoorbeeld +32.',
        en: 'Use a phone number with country code, for example +32.',
        fr: 'Utilisez un numéro avec indicatif pays, par exemple +32.',
        es: 'Usa un número con prefijo internacional, por ejemplo +32.',
      );
    case 'noValidWhatsappPhone':
      return _tr(
        nl: 'Geen klanttelefoonnummer gevonden.',
        en: 'No customer phone number found.',
        fr: 'Aucun numéro de téléphone client trouvé.',
        es: 'No se encontró ningún teléfono del cliente.',
      );
    case 'whatsappOpenFailed':
      return _tr(
        nl: 'WhatsApp kon niet worden geopend.',
        en: 'Could not open WhatsApp.',
        fr: 'Impossible d’ouvrir WhatsApp.',
        es: 'No se pudo abrir WhatsApp.',
      );
    case 'emailOpenFailed':
      return _tr(
        nl: 'E-mailapp kon niet worden geopend.',
        en: 'Could not open email app.',
        fr: 'Impossible d’ouvrir l’application e-mail.',
        es: 'No se pudo abrir la app de correo.',
      );
    case 'receiptEmailSubject':
      return _tr(
        nl: 'Uw ritbon',
        en: 'Your ride receipt',
        fr: 'Votre reçu de course',
        es: 'Su recibo de viaje',
      );
    case 'paymentEmailSubject':
      return _tr(
        nl: 'Betaalverzoek / demolink',
        en: 'Payment request / demo link',
        fr: 'Demande de paiement / lien de démonstration',
        es: 'Solicitud de pago / enlace de demostración',
      );
    case 'paymentRequestDemoTitle':
      return _tr(
        nl: 'Betaalverzoek / demolink',
        en: 'Payment request / demo link',
        fr: 'Demande de paiement / lien de démonstration',
        es: 'Solicitud de pago / enlace de demostración',
      );
    case 'reference':
      return _tr(
        nl: 'Referentie',
        en: 'Reference',
        fr: 'Référence',
        es: 'Referencia',
      );
    case 'ride':
      return _tr(nl: 'Rit', en: 'Ride', fr: 'Course', es: 'Viaje');
    case 'thanksRide':
      return _tr(
        nl: 'Bedankt voor uw rit.',
        en: 'Thank you for your ride.',
        fr: 'Merci pour votre course.',
        es: 'Gracias por su viaje.',
      );
    case 'pdfFooterDefault':
      return _tr(
        nl: 'Bedankt voor uw vertrouwen in Fluxidi.',
        en: 'Thank you for choosing Fluxidi.',
        fr: 'Merci pour votre confiance en Fluxidi.',
        es: 'Gracias por confiar en Fluxidi.',
      );
    case 'currentLocation':
      return _tr(
        nl: 'Huidige locatie',
        en: 'Current location',
        fr: 'Position actuelle',
        es: 'Ubicación actual',
      );
    case 'receiptFrom':
      return _tr(
        nl: 'Bon van',
        en: 'Receipt from',
        fr: 'Reçu de',
        es: 'Recibo de',
      );
    case 'paymentRequestFrom':
      return _tr(
        nl: 'Betaalverzoek van',
        en: 'Payment request from',
        fr: 'Demande de paiement de',
        es: 'Solicitud de pago de',
      );
    case 'downloadSave':
      return _tr(
        nl: 'Download / opslaan',
        en: 'Download / save',
        fr: 'Télécharger / enregistrer',
        es: 'Descargar / guardar',
      );
    case 'comingSoon':
      return _tr(
        nl: 'komt later.',
        en: 'coming later.',
        fr: 'arrive plus tard.',
        es: 'llegara mas tarde.',
      );
    case 'paymentLink':
      return _tr(
        nl: 'Betaallink',
        en: 'Payment link',
        fr: 'Lien de paiement',
        es: 'Enlace de pago',
      );
    case 'paymentLinkCopied':
      return _tr(
        nl: 'Betaallink gekopieerd.',
        en: 'Payment link copied.',
        fr: 'Lien de paiement copié.',
        es: 'Enlace de pago copiado.',
      );
    case 'paymentRequestCopied':
      return _tr(
        nl: 'Betaalverzoek gekopieerd om te delen.',
        en: 'Payment request copied for sharing.',
        fr: 'Demande de paiement copiée pour partage.',
        es: 'Solicitud de pago copiada para compartir.',
      );
    case 'receiptCopied':
      return _tr(
        nl: 'Bontekst gekopieerd om te delen.',
        en: 'Receipt text copied for sharing.',
        fr: 'Texte du reçu copié pour partage.',
        es: 'Texto del recibo copiado para compartir.',
      );
  }
  return key;
}

String _localizedRideKind(String kind) {
  return kind.toLowerCase().trim() == 'planned'
      ? _receiptText('plannedRide')
      : _receiptText('streetRide');
}

String _localizedRideSubtype(String? raw) {
  final value = (raw ?? '').toLowerCase().trim();
  if (value == 'retourrit' || value == 'return ride' || value == 'return') {
    return _receiptText('returnRide');
  }
  if (value == 'heenrit' || value == 'outbound ride' || value == 'outbound') {
    return _receiptText('outboundRide');
  }
  return _receiptText('unknown');
}

String _localizedRideStatus(String? raw) {
  final value = (raw ?? '').toLowerCase().trim();
  switch (value) {
    case 'stopped':
    case 'completed':
    case 'complete':
    case 'done':
      return _tr(
        nl: 'Afgerond',
        en: 'Completed',
        fr: 'Terminée',
        es: 'Finalizada',
      );
    case 'active':
    case 'running':
      return _tr(nl: 'Actief', en: 'Active', fr: 'Active', es: 'Activa');
    case 'waiting':
    case 'wait':
      return _tr(
        nl: 'Wachten',
        en: 'Waiting',
        fr: 'En attente',
        es: 'En espera',
      );
    case 'cancelled':
    case 'canceled':
      return _tr(
        nl: 'Geannuleerd',
        en: 'Cancelled',
        fr: 'Annulée',
        es: 'Cancelada',
      );
  }
  return _receiptText('unknown');
}

bool _looksLikeCoordinatePair(String? value) {
  final text = value?.trim();
  if (text == null || text.isEmpty) return false;
  final normalized = text.replaceAll(RegExp(r'\s+'), ' ');
  final match = RegExp(
    r'^([+-]?\d{1,2}(?:\.\d+)?)\s*[,;\s]\s*([+-]?\d{1,3}(?:\.\d+)?)$',
  ).firstMatch(normalized);
  if (match == null) return false;
  final lat = double.tryParse(match.group(1)!);
  final lon = double.tryParse(match.group(2)!);
  if (lat == null || lon == null) return false;
  return lat.abs() <= 90.0 && lon.abs() <= 180.0;
}

String _receiptStartPointFallback() {
  return _tr(
    nl: 'Straatrit startpunt',
    en: 'Street ride start point',
    fr: 'Point de départ',
    es: 'Punto de inicio',
  );
}

String _receiptStartLocationFallback() {
  return _tr(
    nl: 'Startlocatie',
    en: 'Start location',
    fr: 'Point de départ',
    es: 'Punto de inicio',
  );
}

String _sanitizeCustomerFacingRouteLabel(
  String? raw, {
  required bool isFromField,
}) {
  final fallback = isFromField
      ? _receiptStartPointFallback()
      : _receiptStartLocationFallback();
  final text = raw?.trim() ?? '';
  if (text.isEmpty || text == '-' || text == '—') return fallback;
  if (text.toLowerCase() == _receiptText('currentLocation').toLowerCase()) {
    return fallback;
  }
  if (_looksLikeCoordinatePair(text)) return fallback;
  return text;
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

    return ValueListenableBuilder(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: kAppTitle,
        theme: theme,
        builder: (context, child) {
          return FluxidiFrame(child: child ?? const SizedBox.shrink());
        },
        home: const RoleEntryPage(),
      ),
    );
  }
}

class RoleEntryPage extends StatelessWidget {
  const RoleEntryPage({super.key});

  static const String _startBackgroundAsset =
      'assets/fluxidi/fluxidi_start_background.png';

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) => _tr(nl: nl, en: en, fr: fr, es: es);

  Widget _roleCard({
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required IconData icon,
    required double height,
    bool highlighted = false,
  }) {
    return SizedBox(
      height: height,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF141B2C).withOpacity(0.96),
                  const Color(0xFF0B0F18).withOpacity(0.97),
                ],
              ),
              border: Border.all(
                color: highlighted
                    ? kFluxidiYellow.withOpacity(0.78)
                    : kFluxidiYellow.withOpacity(0.45),
                width: highlighted ? 1.25 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: kFluxidiYellow.withOpacity(highlighted ? 0.26 : 0.15),
                  blurRadius: highlighted ? 16 : 11,
                ),
                const BoxShadow(
                  color: Color(0x99000000),
                  blurRadius: 10,
                  offset: Offset(0, 7),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 74,
                    height: 74,
                    decoration: BoxDecoration(
                      color: kFluxidiYellow.withOpacity(0.22),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: kFluxidiYellow.withOpacity(0.68),
                      ),
                    ),
                    child: Icon(icon, color: kFluxidiYellow, size: 40),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18.2,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.15,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.72),
                            fontSize: 10.8,
                            fontWeight: FontWeight.w600,
                            height: 1.14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: kFluxidiYellow,
                    size: 21,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _languageSelectorPill() {
    final code = currentLanguageCode.toUpperCase();
    return PopupMenuButton<String>(
      onSelected: setAppLanguageByCode,
      color: const Color(0xFF111827),
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: kFluxidiYellow.withOpacity(0.35)),
      ),
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'nl', child: Text('🇳🇱 NL')),
        PopupMenuItem(value: 'en', child: Text('🇬🇧 EN')),
        PopupMenuItem(value: 'fr', child: Text('🇫🇷 FR')),
        PopupMenuItem(value: 'es', child: Text('🇪🇸 ES')),
      ],
      child: Container(
        height: 31,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0E1524).withOpacity(0.9),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: kFluxidiYellow.withOpacity(0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.language_rounded,
              size: 14,
              color: kFluxidiYellow.withOpacity(0.95),
            ),
            const SizedBox(width: 5),
            Text(
              code,
              style: TextStyle(
                color: Colors.white.withOpacity(0.96),
                fontWeight: FontWeight.w800,
                fontSize: 10.8,
              ),
            ),
            const SizedBox(width: 1),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 14,
              color: kFluxidiYellow.withOpacity(0.9),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _goCustomer(BuildContext context) async {
    setAppRole(AppRole.customer);
    final existingProfile = await CustomerProfileStore.instance.load();
    if (!context.mounted) return;
    if (existingProfile != null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const CustomerHomePage()),
      );
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const CustomerOnboardingPage()),
    );
  }

  Future<void> _goBusiness(BuildContext context) async {
    await CompanySessionStore.instance.bootstrap();
    if (!context.mounted) return;
    if (CompanySessionStore.instance.hasValidCompanyContext) {
      setAppRole(AppRole.companyAdmin);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const BusinessHomePage()),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => CompanyOnboardingPage(
            onCompleted: (ctx) {
              setAppRole(AppRole.companyAdmin);
              Navigator.of(ctx).pushReplacement(
                MaterialPageRoute<void>(
                  builder: (_) => const BusinessHomePage(),
                ),
              );
            },
          ),
        ),
      );
    }
  }

  Future<void> _goDriver(BuildContext context) async {
    await DriverSessionStore.instance.bootstrap(driversNotifier.value);
    await DriverDocumentsStore.instance.load();
    if (!context.mounted) return;
    if (activeDriverSessionNotifier.value != null) {
      setAppRole(AppRole.driver);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DriverHomePage()),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ChauffeurLoginPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) => Scaffold(
        backgroundColor: kFluxidiBlack,
        body: SafeArea(
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 96.0,
                bottom: -96.0,
                child: Image.asset(
                  _startBackgroundAsset,
                  fit: BoxFit.cover,
                  alignment: const Alignment(0, 0.75),
                  errorBuilder: (_, __, ___) => const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF101827), Color(0xFF070A10)],
                      ),
                    ),
                    child: SizedBox.expand(),
                  ),
                ),
              ),
              Positioned.fill(
                child: Container(color: Colors.black.withOpacity(0.15)),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.0, 0.46, 0.8, 1.0],
                        colors: [
                          Colors.black.withOpacity(0.02),
                          Colors.black.withOpacity(0.10),
                          Colors.black.withOpacity(0.16),
                          Colors.black.withOpacity(0.22),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final veryCompact = constraints.maxHeight < 680;
                  final narrow = constraints.maxWidth < 390;
                  final contentHorizontalPadding = narrow ? 14.0 : 18.0;
                  final logoTop = veryCompact ? -26.0 : -32.0;
                  final languageTop = veryCompact ? 4.0 : 6.0;
                  final logoMaxBySpace =
                      constraints.maxWidth -
                      (contentHorizontalPadding * 2) -
                      84.0;
                  final logoWidth = math.max(
                    170.0,
                    math.min(
                      logoMaxBySpace,
                      constraints.maxWidth * (narrow ? 0.62 : 0.55),
                    ),
                  );
                  final contentTop = veryCompact ? 112.0 : 136.0;

                  final roleCardHeight = veryCompact ? 92.0 : 98.0;
                  final cardGap = veryCompact ? 5.0 : 6.0;
                  final sectionGap = veryCompact ? 7.0 : 8.0;
                  final roleCardWidth = math.min(
                    392.0,
                    constraints.maxWidth * (narrow ? 0.85 : 0.8),
                  );
                  final reassuranceWidth = math.min(
                    280.0,
                    constraints.maxWidth * (narrow ? 0.78 : 0.66),
                  );

                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 470),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: contentHorizontalPadding,
                        ),
                        child: Stack(
                          children: [
                            Positioned(
                              left: 0,
                              top: logoTop,
                              child: SizedBox(
                                width: logoWidth,
                                child: Align(
                                  alignment: Alignment.topLeft,
                                  child: Image.asset(
                                    kFluxidiLogoAsset,
                                    fit: BoxFit.contain,
                                    alignment: Alignment.topLeft,
                                    errorBuilder: (_, __, ___) => const Text(
                                      'FLUXIDI',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 28,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              right: 0,
                              top: languageTop,
                              child: _languageSelectorPill(),
                            ),
                            Positioned.fill(
                              top: contentTop,
                              child: SingleChildScrollView(
                                padding: EdgeInsets.only(
                                  bottom: veryCompact ? 118 : 136,
                                ),
                                child: Column(
                                  children: [
                                    Center(
                                      child: Column(
                                        children: [
                                          Text(
                                            _t(
                                              nl: 'Welkom bij Fluxidi',
                                              en: 'Welcome to Fluxidi',
                                              fr: 'Bienvenue chez Fluxidi',
                                              es: 'Bienvenido a Fluxidi',
                                            ),
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(
                                                0.97,
                                              ),
                                              fontSize: narrow ? 18 : 19,
                                              fontWeight: FontWeight.w900,
                                              height: 1.08,
                                              shadows: [
                                                Shadow(
                                                  color: Colors.black
                                                      .withOpacity(0.45),
                                                  blurRadius: 10,
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            _t(
                                              nl: 'Kies je rol en vertrek.',
                                              en: 'Choose your role and go.',
                                              fr: 'Choisissez votre rôle et démarrez.',
                                              es: 'Elige tu rol y empieza.',
                                            ),
                                            textAlign: TextAlign.center,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(
                                                0.82,
                                              ),
                                              fontSize: 11.2,
                                              fontWeight: FontWeight.w600,
                                              height: 1.2,
                                              shadows: [
                                                Shadow(
                                                  color: Colors.black
                                                      .withOpacity(0.4),
                                                  blurRadius: 8,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(height: sectionGap),
                                    Text(
                                      _t(
                                        nl: 'Hoe wil je starten?',
                                        en: 'How do you want to start?',
                                        fr: 'Comment voulez-vous commencer ?',
                                        es: '¿Cómo quieres empezar?',
                                      ),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: kFluxidiYellow.withOpacity(0.98),
                                        fontSize: 13.2,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Center(
                                      child: SizedBox(
                                        width: roleCardWidth,
                                        child: _roleCard(
                                          title: _t(
                                            nl: 'Klant',
                                            en: 'Customer',
                                            fr: 'Client',
                                            es: 'Cliente',
                                          ),
                                          subtitle: _t(
                                            nl: 'Boek je rit.',
                                            en: 'Book your ride.',
                                            fr: 'Réservez votre course.',
                                            es: 'Reserva tu viaje.',
                                          ),
                                          icon: Icons.person_outline_rounded,
                                          height: roleCardHeight,
                                          highlighted: true,
                                          onTap: () => _goCustomer(context),
                                        ),
                                      ),
                                    ),
                                    SizedBox(height: cardGap),
                                    Center(
                                      child: SizedBox(
                                        width: roleCardWidth,
                                        child: _roleCard(
                                          title: _t(
                                            nl: 'Bedrijf',
                                            en: 'Business',
                                            fr: 'Entreprise',
                                            es: 'Empresa',
                                          ),
                                          subtitle: _t(
                                            nl: 'Beheer je vloot.',
                                            en: 'Manage your fleet.',
                                            fr: 'Gérez votre flotte.',
                                            es: 'Gestiona tu flota.',
                                          ),
                                          icon: Icons.business_center_rounded,
                                          height: roleCardHeight,
                                          onTap: () =>
                                              unawaited(_goBusiness(context)),
                                        ),
                                      ),
                                    ),
                                    SizedBox(height: cardGap),
                                    Center(
                                      child: SizedBox(
                                        width: roleCardWidth,
                                        child: _roleCard(
                                          title: _t(
                                            nl: 'Chauffeur',
                                            en: 'Driver',
                                            fr: 'Chauffeur',
                                            es: 'Conductor',
                                          ),
                                          subtitle: _t(
                                            nl: 'Start en rij ritten.',
                                            en: 'Start and drive rides.',
                                            fr: 'Démarrez et roulez.',
                                            es: 'Inicia y conduce viajes.',
                                          ),
                                          icon: Icons.local_taxi_rounded,
                                          height: roleCardHeight,
                                          onTap: () => _goDriver(context),
                                        ),
                                      ),
                                    ),
                                    SizedBox(height: sectionGap),
                                    Center(
                                      child: SizedBox(
                                        width: reassuranceWidth,
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.shield_outlined,
                                              color: kFluxidiYellow.withOpacity(
                                                0.86,
                                              ),
                                              size: 17,
                                            ),
                                            const SizedBox(width: 5),
                                            Flexible(
                                              child: Text(
                                                _t(
                                                  nl: 'Keuze wordt onthouden.',
                                                  en: 'Choice remembered.',
                                                  fr: 'Choix mémorisé.',
                                                  es: 'Elección recordada.',
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  color: Colors.white
                                                      .withOpacity(0.78),
                                                  fontSize: 10.6,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
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
      ),
    );
  }
}

class ChauffeurLoginPage extends StatefulWidget {
  const ChauffeurLoginPage({super.key});

  @override
  State<ChauffeurLoginPage> createState() => _ChauffeurLoginPageState();
}

class _ChauffeurLoginPageState extends State<ChauffeurLoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _idCtrl = TextEditingController();
  bool _busy = false;
  String? _lookupError;

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) => _tr(nl: nl, en: en, fr: fr, es: es);

  @override
  void initState() {
    super.initState();
    _idCtrl.addListener(() {
      if (_lookupError != null) setState(() => _lookupError = null);
    });
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _lookupError = null);
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final drivers = driversNotifier.value;
    final match = DriverSessionStore.instance.findDriverByEnteredId(
      drivers,
      _idCtrl.text,
    );
    if (match == null) {
      debugPrint('[DRIVER_LOGIN][FAIL] reason=not_found');
      if (mounted) {
        setState(() {
          _busy = false;
          _lookupError = _t(
            nl: 'Geen actieve chauffeur gevonden met deze ID.',
            en: 'No active driver found with this ID.',
            fr: 'Aucun chauffeur actif trouvé avec cet ID.',
            es: 'No se encontró ningún conductor activo con este ID.',
          );
        });
      }
      return;
    }
    final prev = await DriverSessionStore.instance.load();
    await DriverSessionStore.instance.saveFromDriverProfile(
      match,
      previous: prev,
    );
    DriverSessionStore.instance.logOk(match.id);
    if (!mounted) return;
    setState(() => _busy = false);
    setAppRole(AppRole.driver);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const DriverHomePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) => Scaffold(
        backgroundColor: kFluxidiBlack,
        appBar: AppBar(
          backgroundColor: kFluxidiBlack,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _busy
                ? null
                : () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const RoleEntryPage()),
                    );
                  },
          ),
          title: Text(
            _t(
              nl: 'Chauffeur login',
              en: 'Driver login',
              fr: 'Connexion chauffeur',
              es: 'Acceso conductor',
            ),
          ),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF121A2E),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: const Color(0xFFE5B641).withOpacity(0.3),
                    ),
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _t(
                            nl: 'Vul je chauffeur-ID in om je ritten te openen.',
                            en: 'Enter your driver ID to open your rides.',
                            fr: 'Saisissez votre ID chauffeur pour ouvrir vos courses.',
                            es: 'Introduce tu ID de conductor para abrir tus viajes.',
                          ),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.85),
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _idCtrl,
                          enabled: !_busy,
                          style: const TextStyle(color: Colors.white),
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) {
                            if (!_busy) unawaited(_submit());
                          },
                          decoration: InputDecoration(
                            labelText: _t(
                              nl: 'Chauffeur-ID',
                              en: 'Driver ID',
                              fr: 'ID chauffeur',
                              es: 'ID de conductor',
                            ),
                            labelStyle: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                            ),
                            filled: true,
                            fillColor: const Color(0xFF141B2F),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                          ),
                          validator: (v) {
                            if ((v ?? '').trim().isEmpty) {
                              return _t(
                                nl: 'Vul je chauffeur-ID in.',
                                en: 'Enter your driver ID.',
                                fr: 'Saisissez votre ID chauffeur.',
                                es: 'Introduce tu ID de conductor.',
                              );
                            }
                            return null;
                          },
                        ),
                        if (_lookupError != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            _lookupError!,
                            style: const TextStyle(
                              color: Color(0xFFFF8A8A),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        FilledButton(
                          onPressed: _busy
                              ? null
                              : () {
                                  unawaited(_submit());
                                },
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFE5B641),
                            foregroundColor: Colors.black,
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _busy
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black54,
                                  ),
                                )
                              : Text(
                                  _t(
                                    nl: 'Inloggen',
                                    en: 'Log in',
                                    fr: 'Se connecter',
                                    es: 'Iniciar sesión',
                                  ),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CustomerOnboardingPage extends StatefulWidget {
  const CustomerOnboardingPage({super.key});

  @override
  State<CustomerOnboardingPage> createState() => _CustomerOnboardingPageState();
}

class _CustomerOnboardingPageState extends State<CustomerOnboardingPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _companyNameCtrl = TextEditingController();
  final _vatNumberCtrl = TextEditingController();
  bool _saving = false;

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) => _tr(nl: nl, en: en, fr: fr, es: es);

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _companyNameCtrl.dispose();
    _vatNumberCtrl.dispose();
    super.dispose();
  }

  Future<void> _goToCustomerHome() async {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const CustomerHomePage()),
    );
  }

  Future<void> _saveAndContinue() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final saved = await CustomerProfileStore.instance.save(
      name: _nameCtrl.text,
      phone: _phoneCtrl.text,
      email: _emailCtrl.text,
      companyName: _companyNameCtrl.text,
      vatNumber: _vatNumberCtrl.text,
    );
    _setCachedCustomerProfile(saved);
    if (!mounted) return;
    setState(() => _saving = false);
    await _goToCustomerHome();
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: validator,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF141B2F),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) => Scaffold(
        backgroundColor: kFluxidiBlack,
        appBar: AppBar(
          backgroundColor: kFluxidiBlack,
          elevation: 0,
          title: const Text('FLUXIDI'),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF121A2E),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: const Color(0xFFE5B641).withOpacity(0.3),
                    ),
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _t(
                            nl: 'Maak je ritten makkelijker',
                            en: 'Make your rides easier',
                            fr: 'Simplifiez vos trajets',
                            es: 'Haz tus viajes más fáciles',
                          ),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _t(
                            nl: 'Vul één keer je gegevens in. Dan hoef je ze bij je volgende boeking niet opnieuw te typen.',
                            en: 'Enter your details once, so you do not have to type them again for your next booking.',
                            fr: 'Saisissez vos informations une seule fois pour ne plus devoir les retaper lors de votre prochaine réservation.',
                            es: 'Introduce tus datos una vez para no tener que escribirlos de nuevo en tu próxima reserva.',
                          ),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.82),
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _field(
                          label: _t(
                            nl: 'Naam',
                            en: 'Name',
                            fr: 'Nom',
                            es: 'Nombre',
                          ),
                          controller: _nameCtrl,
                          validator: (v) {
                            final text = (v ?? '').trim();
                            if (text.isEmpty) {
                              return _t(
                                nl: 'Vul je naam in',
                                en: 'Enter your name',
                                fr: 'Saisissez votre nom',
                                es: 'Introduce tu nombre',
                              );
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        _field(
                          label: _t(
                            nl: 'Telefoonnummer',
                            en: 'Phone number',
                            fr: 'Numéro de téléphone',
                            es: 'Número de teléfono',
                          ),
                          controller: _phoneCtrl,
                          keyboardType: TextInputType.phone,
                          validator: (v) {
                            final text = (v ?? '').trim();
                            if (text.isEmpty) {
                              return _t(
                                nl: 'Vul je telefoonnummer in',
                                en: 'Enter your phone number',
                                fr: 'Saisissez votre numéro de téléphone',
                                es: 'Introduce tu número de teléfono',
                              );
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        _field(
                          label: _t(
                            nl: 'E-mailadres',
                            en: 'Email address',
                            fr: 'Adresse e-mail',
                            es: 'Correo electrónico',
                          ),
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          validator: (v) {
                            final text = (v ?? '').trim();
                            if (text.isEmpty) {
                              return _t(
                                nl: 'Vul je e-mail in',
                                en: 'Enter your email',
                                fr: 'Saisissez votre e-mail',
                                es: 'Introduce tu correo',
                              );
                            }
                            if (!text.contains('@') || !text.contains('.')) {
                              return _t(
                                nl: 'Vul een geldig e-mailadres in',
                                en: 'Enter a valid email address',
                                fr: 'Saisissez une adresse e-mail valide',
                                es: 'Introduce un correo electrónico válido',
                              );
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        _field(
                          label: _t(
                            nl: 'Bedrijfsnaam (optioneel)',
                            en: 'Company name (optional)',
                            fr: 'Nom de l’entreprise (facultatif)',
                            es: 'Nombre de la empresa (opcional)',
                          ),
                          controller: _companyNameCtrl,
                        ),
                        const SizedBox(height: 12),
                        _field(
                          label: _t(
                            nl: 'BTW-nummer (optioneel)',
                            en: 'VAT number (optional)',
                            fr: 'Numéro de TVA (facultatif)',
                            es: 'Número de IVA (opcional)',
                          ),
                          controller: _vatNumberCtrl,
                        ),
                        const SizedBox(height: 18),
                        FilledButton(
                          onPressed: _saving ? null : _saveAndContinue,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFE5B641),
                            foregroundColor: Colors.black,
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            _saving
                                ? _t(
                                    nl: 'Opslaan...',
                                    en: 'Saving...',
                                    fr: 'Enregistrement...',
                                    es: 'Guardando...',
                                  )
                                : _t(
                                    nl: 'Opslaan en doorgaan',
                                    en: 'Save and continue',
                                    fr: 'Enregistrer et continuer',
                                    es: 'Guardar y continuar',
                                  ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton(
                          onPressed: _saving ? null : _goToCustomerHome,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFE5B641),
                            side: const BorderSide(
                              color: Color(0xFFE5B641),
                              width: 1.2,
                            ),
                            minimumSize: const Size.fromHeight(50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            _t(
                              nl: 'Later invullen',
                              en: 'Fill in later',
                              fr: 'Compléter plus tard',
                              es: 'Completar más tarde',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CustomerProfileEditPage extends StatefulWidget {
  const CustomerProfileEditPage({super.key});

  @override
  State<CustomerProfileEditPage> createState() =>
      _CustomerProfileEditPageState();
}

class _CustomerProfileEditPageState extends State<CustomerProfileEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _companyNameCtrl = TextEditingController();
  final _vatNumberCtrl = TextEditingController();
  bool _saving = false;

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) => _tr(nl: nl, en: en, fr: fr, es: es);

  @override
  void initState() {
    super.initState();
    unawaited(_loadProfile());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _companyNameCtrl.dispose();
    _vatNumberCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final profile = await CustomerProfileStore.instance.load();
    if (!mounted || profile == null) return;
    _nameCtrl.text = profile.name;
    _phoneCtrl.text = profile.phone;
    _emailCtrl.text = profile.email;
    _companyNameCtrl.text = profile.companyName;
    _vatNumberCtrl.text = profile.vatNumber;
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final saved = await CustomerProfileStore.instance.save(
      name: _nameCtrl.text,
      phone: _phoneCtrl.text,
      email: _emailCtrl.text,
      companyName: _companyNameCtrl.text,
      vatNumber: _vatNumberCtrl.text,
    );
    _setCachedCustomerProfile(saved);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _t(
            nl: 'Gegevens opgeslagen.',
            en: 'Details saved.',
            fr: 'Informations enregistrées.',
            es: 'Datos guardados.',
          ),
        ),
      ),
    );
    Navigator.of(context).pop();
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: validator,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF141B2F),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) => Scaffold(
        backgroundColor: kFluxidiBlack,
        appBar: AppBar(
          backgroundColor: kFluxidiBlack,
          elevation: 0,
          title: Text(
            _t(
              nl: 'Mijn gegevens',
              en: 'My details',
              fr: 'Mes informations',
              es: 'Mis datos',
            ),
          ),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF121A2E),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: const Color(0xFFE5B641).withOpacity(0.3),
                    ),
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _t(
                            nl: 'Beheer je gegevens voor snelle boekingen en facturatie.',
                            en: 'Manage your details for faster bookings and billing.',
                            fr: 'Gérez vos informations pour des réservations et une facturation plus rapides.',
                            es: 'Gestiona tus datos para reservas y facturación más rápidas.',
                          ),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.82),
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _field(
                          label: _t(
                            nl: 'Naam',
                            en: 'Name',
                            fr: 'Nom',
                            es: 'Nombre',
                          ),
                          controller: _nameCtrl,
                          validator: (v) {
                            final text = (v ?? '').trim();
                            if (text.isEmpty) {
                              return _t(
                                nl: 'Vul je naam in',
                                en: 'Enter your name',
                                fr: 'Saisissez votre nom',
                                es: 'Introduce tu nombre',
                              );
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        _field(
                          label: _t(
                            nl: 'Telefoonnummer',
                            en: 'Phone number',
                            fr: 'Numéro de téléphone',
                            es: 'Número de teléfono',
                          ),
                          controller: _phoneCtrl,
                          keyboardType: TextInputType.phone,
                          validator: (v) {
                            final text = (v ?? '').trim();
                            if (text.isEmpty) {
                              return _t(
                                nl: 'Vul je telefoonnummer in',
                                en: 'Enter your phone number',
                                fr: 'Saisissez votre numéro de téléphone',
                                es: 'Introduce tu número de teléfono',
                              );
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        _field(
                          label: _t(
                            nl: 'E-mailadres',
                            en: 'Email address',
                            fr: 'Adresse e-mail',
                            es: 'Correo electrónico',
                          ),
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          validator: (v) {
                            final text = (v ?? '').trim();
                            if (text.isEmpty) {
                              return _t(
                                nl: 'Vul je e-mail in',
                                en: 'Enter your email',
                                fr: 'Saisissez votre e-mail',
                                es: 'Introduce tu correo',
                              );
                            }
                            if (!text.contains('@') || !text.contains('.')) {
                              return _t(
                                nl: 'Vul een geldig e-mailadres in',
                                en: 'Enter a valid email address',
                                fr: 'Saisissez une adresse e-mail valide',
                                es: 'Introduce un correo electrónico válido',
                              );
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        _field(
                          label: _t(
                            nl: 'Bedrijfsnaam (optioneel)',
                            en: 'Company name (optional)',
                            fr: 'Nom de l’entreprise (facultatif)',
                            es: 'Nombre de la empresa (opcional)',
                          ),
                          controller: _companyNameCtrl,
                        ),
                        const SizedBox(height: 12),
                        _field(
                          label: _t(
                            nl: 'BTW-nummer (optioneel)',
                            en: 'VAT number (optional)',
                            fr: 'Numéro de TVA (facultatif)',
                            es: 'Número de IVA (opcional)',
                          ),
                          controller: _vatNumberCtrl,
                        ),
                        const SizedBox(height: 18),
                        FilledButton(
                          onPressed: _saving ? null : _save,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFE5B641),
                            foregroundColor: Colors.black,
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            _saving
                                ? _t(
                                    nl: 'Opslaan...',
                                    en: 'Saving...',
                                    fr: 'Enregistrement...',
                                    es: 'Guardando...',
                                  )
                                : _t(
                                    nl: 'Opslaan',
                                    en: 'Save',
                                    fr: 'Enregistrer',
                                    es: 'Guardar',
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BusinessHomePage extends StatelessWidget {
  const BusinessHomePage({super.key});

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) => _tr(nl: nl, en: en, fr: fr, es: es);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) => Scaffold(
        backgroundColor: const Color(0xFF0B1020),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0B1020),
          title: const Text('FLUXIDI'),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                _t(
                  nl: 'Bedrijf',
                  en: 'Business',
                  fr: 'Entreprise',
                  es: 'Empresa',
                ),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _t(
                  nl: 'Beheer je bedrijf, voertuigen en boekingen.',
                  en: 'Manage your company, vehicles, and bookings.',
                  fr: 'Gerez votre entreprise, vos vehicules et vos reservations.',
                  es: 'Gestiona tu empresa, vehiculos y reservas.',
                ),
                style: TextStyle(color: Colors.white.withOpacity(0.72)),
              ),
              const SizedBox(height: 16),
              ValueListenableBuilder<CompanyProfile?>(
                valueListenable: companyProfileNotifier,
                builder: (context, profile, _) {
                  if (profile == null) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Card(
                        color: const Color(0xFF141B2F),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                profile.companyName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: profile.isSuspended
                                        ? const Color(0xFF3A1010)
                                        : profile.isVerified
                                        ? const Color(0xFF12331F)
                                        : const Color(0xFF2A2410),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: profile.isSuspended
                                          ? Colors.red.withOpacity(0.45)
                                          : profile.isVerified
                                          ? const Color(
                                              0xFF4ADE80,
                                            ).withOpacity(0.45)
                                          : const Color(
                                              0xFFE5B641,
                                            ).withOpacity(0.55),
                                    ),
                                  ),
                                  child: Text(
                                    profile.verificationBadgeLabel(
                                      appConfig.currentLanguage,
                                    ),
                                    style: TextStyle(
                                      color: profile.isSuspended
                                          ? const Color(0xFFFFB4B4)
                                          : profile.isVerified
                                          ? const Color(0xFFB8F5C8)
                                          : const Color(0xFFE5D4A1),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                              if (profile.showsPendingVerificationNotice) ...[
                                const SizedBox(height: 8),
                                Text(
                                  profile.verificationPendingNotice(
                                    appConfig.currentLanguage,
                                  ),
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.62),
                                    fontSize: 12,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 6),
                              Text(
                                '${_t(nl: 'Bedrijfs-ID:', en: 'Company ID:', fr: 'ID entreprise :', es: 'ID de empresa:')} ${profile.companyId}',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.85),
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${_t(nl: 'Contact:', en: 'Contact:', fr: 'Contact :', es: 'Contacto:')} ${profile.email}',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(
                                          0xFFE5B641,
                                        ),
                                        side: const BorderSide(
                                          color: Color(0xFFE5B641),
                                        ),
                                      ),
                                      onPressed: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute<void>(
                                            builder: (_) =>
                                                const CompanyProfileEditPage(),
                                          ),
                                        );
                                      },
                                      child: Text(
                                        _t(
                                          nl: 'Bedrijfsgegevens',
                                          en: 'Company details',
                                          fr: 'Données de l’entreprise',
                                          es: 'Datos de empresa',
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: TextButton(
                                      onPressed: () async {
                                        await CompanySessionStore.instance
                                            .clearLocalCompanyState();
                                        if (!context.mounted) return;
                                        Navigator.of(
                                          context,
                                        ).pushAndRemoveUntil(
                                          MaterialPageRoute<void>(
                                            builder: (_) =>
                                                const RoleEntryPage(),
                                          ),
                                          (route) => false,
                                        );
                                      },
                                      child: Text(
                                        _t(
                                          nl: 'Ander bedrijf',
                                          en: 'Other company',
                                          fr: 'Autre entreprise',
                                          es: 'Otra empresa',
                                        ),
                                        style: TextStyle(
                                          color: Colors.redAccent.shade100,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  );
                },
              ),
              Card(
                color: const Color(0xFF141B2F),
                child: ListTile(
                  leading: const Icon(Icons.calculate_outlined),
                  title: Text(
                    appConfig.strings.calculatorTitle.of(
                      appConfig.currentLanguage,
                    ),
                  ),
                  subtitle: Text(kCalculatorMenuSubtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CalculatorPage(
                          bookingBaseUrl: kBookingBaseUrl,
                          mapboxToken: kMapboxToken,
                        ),
                      ),
                    );
                  },
                ),
              ),
              Card(
                color: const Color(0xFF141B2F),
                child: ListTile(
                  leading: const Icon(Icons.business_center_outlined),
                  title: Text(kDrawerBusinessSettingsLabel),
                  subtitle: Text(kDrawerBusinessSettingsSubtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const BusinessSettingsPage(),
                      ),
                    );
                  },
                ),
              ),
              Card(
                color: const Color(0xFF141B2F),
                child: ListTile(
                  leading: const Icon(Icons.credit_card_outlined),
                  title: Text(
                    _t(
                      nl: 'Abonnement & facturatie',
                      en: 'Subscription & billing',
                      fr: 'Abonnement & facturation',
                      es: 'Suscripción y facturación',
                    ),
                  ),
                  subtitle: Text(
                    _t(
                      nl: 'Beheer plan, limieten en modules',
                      en: 'Manage plan, limits and modules',
                      fr: 'Gérez le plan, les limites et les modules',
                      es: 'Gestiona el plan, los límites y los módulos',
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CompanySubscriptionBillingPage(),
                      ),
                    );
                  },
                ),
              ),
              Card(
                color: const Color(0xFF141B2F),
                child: ListTile(
                  leading: const Icon(Icons.directions_car_filled_outlined),
                  title: Text(kDrawerVehiclesLabel),
                  subtitle: Text(kDrawerVehiclesSubtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const VehicleManagementPage(),
                      ),
                    );
                  },
                ),
              ),
              Card(
                color: const Color(0xFF141B2F),
                child: ListTile(
                  leading: const Icon(Icons.fact_check_outlined),
                  title: Text(
                    _t(
                      nl: 'Chiron-complianceoverzicht',
                      en: 'Chiron compliance dashboard',
                      fr: 'Tableau de conformité Chiron',
                      es: 'Panel de cumplimiento Chiron',
                    ),
                  ),
                  subtitle: Text(
                    _t(
                      nl: 'Alleen-lezen compliancecontrole',
                      en: 'Read-only compliance overview',
                      fr: 'Vue conformité en lecture seule',
                      es: 'Vista de cumplimiento de solo lectura',
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ChironComplianceDashboardPage(),
                      ),
                    );
                  },
                ),
              ),
              Card(
                color: const Color(0xFF141B2F),
                child: ListTile(
                  leading: const Icon(Icons.local_taxi_outlined),
                  title: Text(
                    _t(
                      nl: 'Chauffeurs beheren',
                      en: 'Manage drivers',
                      fr: 'Gérer les chauffeurs',
                      es: 'Gestionar conductores',
                    ),
                  ),
                  subtitle: Text(
                    _t(
                      nl: 'Beheer chauffeurs en beschikbaarheid',
                      en: 'Manage drivers and availability',
                      fr: 'Gérez les chauffeurs et disponibilités',
                      es: 'Gestiona conductores y disponibilidad',
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const CompanyDriverManagementPage(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              const FluxidiBackToStartButton(),
            ],
          ),
        ),
      ),
    );
  }
}

class CompanyDriverManagementPage extends StatelessWidget {
  const CompanyDriverManagementPage({super.key});

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) => _tr(nl: nl, en: en, fr: fr, es: es);

  AppLanguage get _lang => appConfig.currentLanguage;

  String _displayDriverName(String rawName) {
    final trimmed = rawName.trim();
    final normalized = trimmed.toLowerCase();
    if (normalized == 'standaard chauffeur' ||
        normalized == 'default driver' ||
        normalized == 'chauffeur standard' ||
        normalized == 'conductor estándar') {
      return _t(
        nl: 'Standaard chauffeur',
        en: 'Default driver',
        fr: 'Chauffeur standard',
        es: 'Conductor estándar',
      );
    }
    return trimmed;
  }

  Widget _driverField(
    TextEditingController ctrl,
    String label, {
    bool enabled = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: ctrl,
        enabled: enabled,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          filled: true,
          fillColor: const Color(0xFF0B0B0B),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0x22FFFFFF)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0x22FFFFFF)),
          ),
        ),
      ),
    );
  }

  Future<void> _openEditDriverDialog(
    BuildContext context,
    DriverProfile existing,
  ) async {
    final nameCtrl = TextEditingController(text: existing.fullName);
    final idCtrl = TextEditingController(text: existing.employeeNumber);
    final phoneCtrl = TextEditingController(text: existing.phone);
    final taxiCardNumberCtrl = TextEditingController(
      text: existing.taxiDriverCardNumber,
    );
    final taxiCardExpiryCtrl = TextEditingController(
      text: existing.taxiDriverCardExpiry,
    );
    var active = existing.isActive;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          backgroundColor: const Color(0xFF141B2F),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            _t(
              nl: 'Chauffeur bewerken',
              en: 'Edit driver',
              fr: 'Modifier le chauffeur',
              es: 'Editar conductor',
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _driverField(
                  nameCtrl,
                  _t(nl: 'Naam', en: 'Name', fr: 'Nom', es: 'Nombre'),
                ),
                _driverField(
                  idCtrl,
                  _t(
                    nl: 'Chauffeur-ID',
                    en: 'Driver ID',
                    fr: 'ID chauffeur',
                    es: 'ID conductor',
                  ),
                  enabled: false,
                ),
                _driverField(
                  phoneCtrl,
                  _t(
                    nl: 'Telefoonnummer',
                    en: 'Phone number',
                    fr: 'Numéro de téléphone',
                    es: 'Número de teléfono',
                  ),
                ),
                _driverField(
                  taxiCardNumberCtrl,
                  _t(
                    nl: 'Kaartnummer',
                    en: 'Card number',
                    fr: 'N° carte',
                    es: 'N.º tarjeta',
                  ),
                ),
                _driverField(
                  taxiCardExpiryCtrl,
                  _t(
                    nl: 'Vervaldatum kaart',
                    en: 'Card expiry',
                    fr: 'Expiration carte',
                    es: 'Caducidad tarjeta',
                  ),
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: active,
                  onChanged: (v) => setDialogState(() => active = v),
                  title: Text(
                    _t(nl: 'Actief', en: 'Active', fr: 'Actif', es: 'Activo'),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(
                          _t(
                            nl: 'Annuleren',
                            en: 'Cancel',
                            fr: 'Annuler',
                            es: 'Cancelar',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          final updated = existing.copyWith(
                            fullName: nameCtrl.text.trim(),
                            phone: phoneCtrl.text.trim(),
                            taxiDriverCardNumber: taxiCardNumberCtrl.text
                                .trim(),
                            taxiDriverCardExpiry: taxiCardExpiryCtrl.text
                                .trim(),
                            isActive: active,
                          );
                          updateDriver(existing.id, updated);
                          Navigator.pop(ctx);
                        },
                        child: Text(
                          _t(
                            nl: 'Opslaan',
                            en: 'Save',
                            fr: 'Enregistrer',
                            es: 'Guardar',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _line(String label, String value) {
    final shown = value.trim().isEmpty ? '—' : value.trim();
    return Text(
      '$label: $shown',
      style: const TextStyle(color: Colors.white70, fontSize: 12),
    );
  }

  Future<void> _confirmDeleteDocument(
    BuildContext context,
    DriverDocument doc,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141B2F),
        title: Text(
          _t(
            nl: 'Document verwijderen?',
            en: 'Delete document?',
            fr: 'Supprimer le document ?',
            es: '¿Eliminar documento?',
          ),
        ),
        content: Text(
          _t(
            nl: 'Deze actie kan niet ongedaan worden gemaakt.',
            en: 'This action cannot be undone.',
            fr: 'Cette action est irreversible.',
            es: 'Esta acción no se puede deshacer.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              _t(nl: 'Annuleren', en: 'Cancel', fr: 'Annuler', es: 'Cancelar'),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              _t(
                nl: 'Verwijderen',
                en: 'Delete',
                fr: 'Supprimer',
                es: 'Eliminar',
              ),
            ),
          ),
        ],
      ),
    );
    if (ok == true) {
      await DriverDocumentsStore.instance.deleteDocument(doc.documentId);
    }
  }

  Future<void> _openDocumentEditor(
    BuildContext context,
    DriverProfile driver, {
    DriverDocument? existing,
  }) => showDriverDocumentEditorSheet(
    context,
    driver: driver,
    existing: existing,
  );

  Widget _driverDocumentTile(
    BuildContext context,
    DriverProfile driver,
    DriverDocument doc,
  ) {
    final typeLabel = driverDocumentTypeLabel(doc.documentType, _lang);
    final statusLabel = driverDocumentStatusLabel(doc.status, _lang);
    final expiredVisual =
        doc.isExpiredByDate || doc.status == DriverDocumentStatuses.expired;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: expiredVisual
              ? Colors.orange.withOpacity(0.6)
              : Colors.white24,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            typeLabel,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (doc.title.trim().isNotEmpty)
            Text(
              doc.title,
              style: const TextStyle(fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 4),
          Text(
            '${_t(nl: 'Status', en: 'Status', fr: 'Statut', es: 'Estado')}: $statusLabel'
            '${doc.isExpiredByDate && doc.status != DriverDocumentStatuses.expired ? ' (${_t(nl: 'datum verlopen', en: 'date expired', fr: 'date expiree', es: 'fecha caducada')})' : ''}',
            style: TextStyle(
              color: expiredVisual ? Colors.orangeAccent : Colors.white70,
              fontSize: 12,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          if (doc.expiryDate.trim().isNotEmpty)
            Text(
              '${_t(nl: 'Vervaldatum', en: 'Expiry', fr: 'Expiration', es: 'Caducidad')}: ${doc.expiryDate}',
              style: const TextStyle(fontSize: 11, color: Colors.white54),
            ),
          if (doc.filePath.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '${_t(nl: 'Bestand', en: 'File', fr: 'Fichier', es: 'Archivo')}: ${doc.filePath}',
              style: const TextStyle(fontSize: 10, color: Colors.white38),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (doc.notes.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '${_t(nl: 'Notities', en: 'Notes', fr: 'Notes', es: 'Notas')}: ${doc.notes}',
              style: const TextStyle(fontSize: 11, color: Colors.white60),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 6),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: doc.filePath.trim().isEmpty
                    ? null
                    : () =>
                          openDriverDocumentFile(context, doc.filePath, _lang),
                child: Text(
                  _t(nl: 'Openen', en: 'Open', fr: 'Ouvrir', es: 'Abrir'),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () =>
                    _openDocumentEditor(context, driver, existing: doc),
                child: Text(
                  _t(nl: 'Bewerken', en: 'Edit', fr: 'Modifier', es: 'Editar'),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => _confirmDeleteDocument(context, doc),
                child: Text(
                  _t(
                    nl: 'Verwijderen',
                    en: 'Delete',
                    fr: 'Supprimer',
                    es: 'Eliminar',
                  ),
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) => Scaffold(
        backgroundColor: const Color(0xFF0B1020),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0B1020),
          title: Text(
            _t(
              nl: 'Chauffeurs beheren',
              en: 'Manage drivers',
              fr: 'Gérer les chauffeurs',
              es: 'Gestionar conductores',
            ),
          ),
        ),
        body: ValueListenableBuilder<List<DriverDocument>>(
          valueListenable: driverDocumentsNotifier,
          builder: (context, _, __) => ValueListenableBuilder<List<DriverProfile>>(
            valueListenable: driversNotifier,
            builder: (context, drivers, _) {
              final visible = drivers
                  .where(
                    (d) =>
                        fleetRecordBelongsToActiveCompanyOrLegacy(d.companyId),
                  )
                  .toList(growable: false);
              if (visible.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _t(
                        nl: 'Nog geen chauffeurs beschikbaar.',
                        en: 'No drivers available yet.',
                        fr: 'Aucun chauffeur disponible.',
                        es: 'Todavía no hay conductores disponibles.',
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(14),
                itemCount: visible.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final d = visible[i];
                  final status = d.isActive
                      ? _t(
                          nl: 'Actief',
                          en: 'Active',
                          fr: 'Actif',
                          es: 'Activo',
                        )
                      : _t(
                          nl: 'Inactief',
                          en: 'Inactive',
                          fr: 'Inactif',
                          es: 'Inactivo',
                        );
                  final docs = DriverDocumentsStore.instance
                      .documentsVisibleForDriver(d.id);
                  final count = docs.length;
                  final gap = DriverDocumentsStore.instance
                      .hasCoreDocumentGapForDriver(d.id);
                  final docCountLabel = _lang == AppLanguage.fr
                      ? ((count == 0 || count == 1) ? 'document' : 'documents')
                      : _t(
                          nl: 'documenten',
                          en: 'documents',
                          fr: 'documents',
                          es: 'documentos',
                        );
                  return Card(
                    color: const Color(0xFF141B2F),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  d.fullName.trim().isEmpty
                                      ? _t(
                                          nl: 'Naamloze chauffeur',
                                          en: 'Unnamed driver',
                                          fr: 'Chauffeur sans nom',
                                          es: 'Conductor sin nombre',
                                        )
                                      : _displayDriverName(d.fullName),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: d.isActive
                                      ? Colors.green.withOpacity(0.18)
                                      : Colors.white10,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  status,
                                  style: TextStyle(
                                    color: d.isActive
                                        ? Colors.greenAccent
                                        : Colors.white54,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _line(
                            _t(
                              nl: 'Chauffeur-ID',
                              en: 'Driver ID',
                              fr: 'ID chauffeur',
                              es: 'ID conductor',
                            ),
                            d.employeeNumber,
                          ),
                          _line(
                            _t(
                              nl: 'Telefoon',
                              en: 'Phone',
                              fr: 'Téléphone',
                              es: 'Teléfono',
                            ),
                            d.phone,
                          ),
                          _line(
                            _t(
                              nl: 'Chauffeurskaartnummer',
                              en: 'Driver card number',
                              fr: 'N° carte chauffeur',
                              es: 'N.º tarjeta de conductor',
                            ),
                            d.taxiDriverCardNumber,
                          ),
                          _line(
                            _t(
                              nl: 'Vervaldatum chauffeurskaart',
                              en: 'Driver card expiry',
                              fr: 'Expiration carte chauffeur',
                              es: 'Caducidad tarjeta de conductor',
                            ),
                            d.taxiDriverCardExpiry,
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.black26,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: gap
                                    ? Colors.orange.withOpacity(0.5)
                                    : Colors.white24,
                              ),
                            ),
                            child: Text(
                              '$count $docCountLabel'
                              '${gap ? ' · ${_t(nl: 'Controleer documenten', en: 'Check documents', fr: 'Vérifier les documents', es: 'Revise documentos')}' : ''}',
                              style: TextStyle(
                                color: gap
                                    ? Colors.orangeAccent
                                    : Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: Text(
                              _t(
                                nl: 'Documenten',
                                en: 'Documents',
                                fr: 'Documents',
                                es: 'Documentos',
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                              ),
                            ),
                            subtitle: Text(
                              docs.isEmpty
                                  ? _t(
                                      nl: 'Nog geen documenten.',
                                      en: 'No documents.',
                                      fr: 'Aucun document.',
                                      es: 'Sin documentos.',
                                    )
                                  : _t(
                                      nl: 'Tik om te bekijken en beheren',
                                      en: 'Tap to view and manage',
                                      fr: 'Touchez pour voir et gerer',
                                      es: 'Toca para ver y gestionar',
                                    ),
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (docs.isEmpty)
                                      Text(
                                        _t(
                                          nl: 'Nog geen documenten.',
                                          en: 'No documents.',
                                          fr: 'Aucun document.',
                                          es: 'Sin documentos.',
                                        ),
                                        style: const TextStyle(
                                          color: Colors.white54,
                                        ),
                                      )
                                    else
                                      ...docs.map(
                                        (doc) => _driverDocumentTile(
                                          context,
                                          d,
                                          doc,
                                        ),
                                      ),
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: OutlinedButton.icon(
                                        onPressed: () =>
                                            _openDocumentEditor(context, d),
                                        icon: const Icon(Icons.add, size: 18),
                                        label: Text(
                                          _t(
                                            nl: 'Document toevoegen',
                                            en: 'Add document',
                                            fr: 'Ajouter',
                                            es: 'Agregar',
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  _openEditDriverDialog(context, d),
                              icon: const Icon(Icons.edit_outlined, size: 16),
                              label: Text(
                                _t(
                                  nl: 'Bewerken',
                                  en: 'Edit',
                                  fr: 'Modifier',
                                  es: 'Editar',
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class CompanySubscriptionBillingPage extends StatefulWidget {
  const CompanySubscriptionBillingPage({super.key});

  @override
  State<CompanySubscriptionBillingPage> createState() =>
      _CompanySubscriptionBillingPageState();
}

class _CompanySubscriptionBillingPageState
    extends State<CompanySubscriptionBillingPage> {
  late Future<BackendSubscriptionProfile> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) => _tr(nl: nl, en: en, fr: fr, es: es);

  String _activeCompanyId() {
    final fromProfile = companyProfileNotifier.value?.companyId.trim() ?? '';
    if (fromProfile.isNotEmpty) return fromProfile;
    final resolved = resolvedCompanyId.trim();
    if (resolved.isNotEmpty) return resolved;
    return kTenantId;
  }

  Future<BackendSubscriptionProfile> _fetch() async {
    final scopeId = _activeCompanyId();
    return fetchBackendSubscriptionProfile(
      tenantId: scopeId,
      companyId: scopeId,
    );
  }

  Widget _buildInfoItem({required String label, required String value}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value.trim().isEmpty ? '—' : value.trim(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _planLabel(String plan) {
    switch (plan.trim().toLowerCase()) {
      case 'starter':
        return 'Starter';
      case 'pro':
        return 'Pro';
      case 'business':
        return _t(
          nl: 'Business',
          en: 'Business',
          fr: 'Business',
          es: 'Business',
        );
      case 'enterprise':
        return 'Enterprise';
      default:
        return plan.trim().isEmpty
            ? _t(
                nl: 'Onbekend',
                en: 'Unknown',
                fr: 'Inconnu',
                es: 'Desconocido',
              )
            : plan.trim();
    }
  }

  String _statusLabel(String status) {
    switch (status.trim().toLowerCase()) {
      case 'trialing':
      case 'trial':
      case 'trial_active':
        return _t(
          nl: 'Proefperiode',
          en: 'Trial',
          fr: 'Période d’essai',
          es: 'Periodo de prueba',
        );
      case 'active':
        return _t(nl: 'Actief', en: 'Active', fr: 'Actif', es: 'Activo');
      case 'past_due':
        return _t(
          nl: 'Betaling vereist',
          en: 'Payment required',
          fr: 'Paiement requis',
          es: 'Pago requerido',
        );
      case 'cancelled':
      case 'canceled':
        return _t(
          nl: 'Geannuleerd',
          en: 'Cancelled',
          fr: 'Annulé',
          es: 'Cancelado',
        );
      case 'inactive':
        return _t(
          nl: 'Inactief',
          en: 'Inactive',
          fr: 'Inactif',
          es: 'Inactivo',
        );
      case 'suspended':
        return _t(
          nl: 'Opgeschort',
          en: 'Suspended',
          fr: 'Suspendu',
          es: 'Suspendido',
        );
      default:
        return status.trim().isEmpty
            ? _t(
                nl: 'Onbekend',
                en: 'Unknown',
                fr: 'Inconnu',
                es: 'Desconocido',
              )
            : status.trim();
    }
  }

  String _featureLabel(String rawKey) {
    switch (rawKey.trim().toLowerCase()) {
      case 'compliance_dashboard':
        return _t(
          nl: 'Complianceoverzicht',
          en: 'Compliance dashboard',
          fr: 'Tableau de conformité',
          es: 'Panel de cumplimiento',
        );
      case 'receipt_pdf':
        return _t(
          nl: 'PDF-ritbonnen',
          en: 'PDF receipts',
          fr: 'Reçus PDF',
          es: 'Recibos PDF',
        );
      case 'whatsapp_email_receipts':
        return _t(
          nl: 'WhatsApp/e-mail ritbonnen',
          en: 'WhatsApp/email receipts',
          fr: 'Reçus WhatsApp/e-mail',
          es: 'Recibos por WhatsApp/e-mail',
        );
      default:
        final normalized = rawKey
            .trim()
            .replaceAll('_', ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .toLowerCase();
        if (normalized.isEmpty) {
          return _t(
            nl: 'Onbekend',
            en: 'Unknown',
            fr: 'Inconnu',
            es: 'Desconocido',
          );
        }
        final words = normalized.split(' ');
        return words
            .map(
              (w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}',
            )
            .join(' ');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: LayoutBuilder(
          builder: (context, constraints) {
            return SizedBox(
              height: 26,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  _t(
                    nl: 'Abonnement & facturatie',
                    en: 'Subscription & billing',
                    fr: 'Abonnement & facturation',
                    es: 'Suscripción y facturación',
                  ),
                  maxLines: 1,
                ),
              ),
            );
          },
        ),
      ),
      body: FutureBuilder<BackendSubscriptionProfile>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  _t(
                    nl: 'Abonnementsgegevens konden niet worden geladen.',
                    en: 'Subscription data could not be loaded.',
                    fr: 'Les données d abonnement n ont pas pu être chargées.',
                    es: 'No se pudieron cargar los datos de suscripción.',
                  ),
                  style: const TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final profile = snap.data ?? BackendSubscriptionProfile.defaults();
          final enabledFeatures = profile.features.entries
              .where((e) => e.value == true)
              .map((e) => _featureLabel(e.key))
              .toList(growable: false);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: const Color(0xFF141B2F),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoItem(
                        label: _t(
                          nl: 'Plan',
                          en: 'Plan',
                          fr: 'Plan',
                          es: 'Plan',
                        ),
                        value: _planLabel(profile.plan),
                      ),
                      _buildInfoItem(
                        label: _t(
                          nl: 'Status',
                          en: 'Status',
                          fr: 'Statut',
                          es: 'Estado',
                        ),
                        value: _statusLabel(profile.status),
                      ),
                      _buildInfoItem(
                        label: _t(
                          nl: 'Proefperiode start/einde',
                          en: 'Trial start/end',
                          fr: 'Début/fin essai',
                          es: 'Inicio/fin de prueba',
                        ),
                        value:
                            '${profile.trialStartedAt.trim().isEmpty ? "—" : profile.trialStartedAt.trim()} / ${profile.trialEndsAt.trim().isEmpty ? "—" : profile.trialEndsAt.trim()}',
                      ),
                      _buildInfoItem(
                        label: _t(
                          nl: 'Facturatie-email',
                          en: 'Billing email',
                          fr: 'E-mail de facturation',
                          es: 'Correo de facturación',
                        ),
                        value: profile.billingEmail,
                      ),
                      _buildInfoItem(
                        label: _t(
                          nl: 'Inbegrepen voertuigen',
                          en: 'Included vehicles',
                          fr: 'Véhicules inclus',
                          es: 'Vehículos incluidos',
                        ),
                        value: profile.includedVehicles.toString(),
                      ),
                      _buildInfoItem(
                        label: _t(
                          nl: 'Max voertuigen',
                          en: 'Max vehicles',
                          fr: 'Véhicules max',
                          es: 'Máx vehículos',
                        ),
                        value: profile.maxVehicles.toString(),
                      ),
                      _buildInfoItem(
                        label: _t(
                          nl: 'Max chauffeurs',
                          en: 'Max drivers',
                          fr: 'Chauffeurs max',
                          es: 'Máx conductores',
                        ),
                        value: profile.maxDrivers.toString(),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _t(
                                nl: 'Ingeschakelde modules',
                                en: 'Enabled modules',
                                fr: 'Modules actifs',
                                es: 'Módulos habilitados',
                              ),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            if (enabledFeatures.isEmpty)
                              const Text(
                                '—',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              )
                            else
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: enabledFeatures
                                    .map(
                                      (feature) => Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.08),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                          border: Border.all(
                                            color: Colors.white.withOpacity(
                                              0.20,
                                            ),
                                          ),
                                        ),
                                        child: Text(
                                          feature,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(growable: false),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _t(
                          nl: 'In deze fase worden limieten alleen weergegeven. Harde blokkering volgt later.',
                          en: 'In this phase, limits are display-only. Hard blocking comes later.',
                          fr: 'Dans cette phase, les limites sont uniquement affichées. Le blocage strict viendra plus tard.',
                          es: 'En esta fase, los límites solo se muestran. El bloqueo estricto llegará después.',
                        ),
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class FluxidiBackToStartButton extends StatelessWidget {
  const FluxidiBackToStartButton({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const RoleEntryPage()),
            (route) => false,
          );
        },
        icon: const Icon(Icons.home_outlined),
        label: Text(
          _tr(
            nl: 'Terug naar startpagina',
            en: 'Back to start page',
            fr: 'Retour à l’accueil',
            es: 'Volver a la pantalla inicial',
          ),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFE5B641),
          backgroundColor: const Color(0xFF10182C),
          side: const BorderSide(color: Color(0xFFE5B641), width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        ),
      ),
    );
  }
}

class CustomerHomePage extends StatelessWidget {
  const CustomerHomePage({super.key});

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) => _tr(nl: nl, en: en, fr: fr, es: es);

  String _comingSoonMessage() => _t(
    nl: 'Deze functie komt binnenkort.',
    en: 'This feature is coming soon.',
    fr: 'Cette fonction arrive bientôt.',
    es: 'Esta función estará disponible pronto.',
  );

  void _comingSoon(BuildContext context) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_comingSoonMessage())));
  }

  String _customerDisplayName() {
    final name = _cachedCustomerProfile?.name.trim() ?? '';
    return name;
  }

  Widget _customerLanguagePill() {
    final code = currentLanguageCode.toUpperCase();
    return PopupMenuButton<String>(
      onSelected: setAppLanguageByCode,
      color: const Color(0xFF111827),
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: kFluxidiYellow.withOpacity(0.35)),
      ),
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'nl', child: Text('🇳🇱 NL')),
        PopupMenuItem(value: 'en', child: Text('🇬🇧 EN')),
        PopupMenuItem(value: 'fr', child: Text('🇫🇷 FR')),
        PopupMenuItem(value: 'es', child: Text('🇪🇸 ES')),
      ],
      child: Container(
        height: 31,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0E1524).withOpacity(0.9),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: kFluxidiYellow.withOpacity(0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.language_rounded,
              size: 14,
              color: kFluxidiYellow.withOpacity(0.95),
            ),
            const SizedBox(width: 5),
            Text(
              code,
              style: TextStyle(
                color: Colors.white.withOpacity(0.96),
                fontWeight: FontWeight.w800,
                fontSize: 10.8,
              ),
            ),
            const SizedBox(width: 1),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 14,
              color: kFluxidiYellow.withOpacity(0.9),
            ),
          ],
        ),
      ),
    );
  }

  void _openCalculator(BuildContext context, {required bool scheduledIntent}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CalculatorPage(
          bookingBaseUrl: kBookingBaseUrl,
          mapboxToken: kMapboxToken,
          onGoToStartPage: () {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const RoleEntryPage()),
              (route) => false,
            );
          },
        ),
      ),
    );
    if (scheduledIntent) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Plan rit opent nu de boekingsflow (scheduled intent volgt).',
              en: 'Scheduled ride currently opens the booking flow (scheduled intent pending).',
              fr: 'La course planifiee ouvre actuellement le flux de reservation (option planifiee a venir).',
              es: 'El viaje programado abre actualmente el flujo de reserva (intencion programada pendiente).',
            ),
          ),
        ),
      );
    }
  }

  Widget _customerHomeHero(BuildContext context) {
    final customerName = _customerDisplayName();
    return Container(
      height: 312,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kFluxidiYellow.withOpacity(0.26)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Transform.scale(
            scale: 1.16,
            alignment: const Alignment(0.45, 0.45),
            child: Image.asset(
              'assets/fluxidi/fluxidi_start_background.png',
              fit: BoxFit.cover,
              alignment: const Alignment(0.45, 0.45),
              errorBuilder: (_, __, ___) => Image.asset(
                'assets/fluxidi/fluxidi_hero_taxi.png',
                fit: BoxFit.cover,
                alignment: const Alignment(0.45, 0.45),
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.black.withOpacity(0.58),
                  Colors.black.withOpacity(0.34),
                  Colors.black.withOpacity(0.12),
                ],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.06),
                  Colors.black.withOpacity(0.11),
                  Colors.black.withOpacity(0.52),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Image.asset(
                      kFluxidiLogoAsset,
                      width: 152,
                      fit: BoxFit.contain,
                    ),
                    const Spacer(),
                    _customerLanguagePill(),
                  ],
                ),
                const Spacer(),
                Text(
                  _t(
                    nl: 'Welkom!',
                    en: 'Welcome!',
                    fr: 'Bienvenue !',
                    es: '¡Bienvenido!',
                  ),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 27,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (customerName.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    customerName,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.84),
                      fontSize: 14.2,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _customerPrimaryCta(BuildContext context) {
    return GestureDetector(
      onTap: () => _openCalculator(context, scheduledIntent: false),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kFluxidiYellow.withOpacity(0.46)),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF101010), Color(0xFF07080C)],
          ),
          boxShadow: [
            BoxShadow(
              color: kFluxidiYellow.withOpacity(0.11),
              blurRadius: 16,
              spreadRadius: 0.9,
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    kFluxidiYellow.withOpacity(0.3),
                    const Color(0xFF15120A),
                  ],
                ),
                shape: BoxShape.circle,
                border: Border.all(color: kFluxidiYellow.withOpacity(0.5)),
                boxShadow: [
                  BoxShadow(
                    color: kFluxidiYellow.withOpacity(0.09),
                    blurRadius: 9,
                    spreadRadius: 0.3,
                  ),
                ],
              ),
              child: const Icon(
                Icons.local_taxi_outlined,
                color: Color(0xFFE5B641),
                size: 30,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _t(
                      nl: 'Bereken & boek je rit',
                      en: 'Calculate & book your ride',
                      fr: 'Calculez & réservez votre trajet',
                      es: 'Calcula y reserva tu viaje',
                    ),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15.6,
                    ),
                    maxLines: 1,
                    softWrap: false,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 31,
              height: 31,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF15120A).withOpacity(0.7),
                border: Border.all(color: kFluxidiYellow.withOpacity(0.34)),
              ),
              child: Icon(
                Icons.arrow_forward_rounded,
                color: kFluxidiYellow.withOpacity(0.98),
                size: 19,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _customerQuickActionCard({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF101010), Color(0xFF07080C)],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kFluxidiYellow.withOpacity(0.15)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.34),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
            BoxShadow(
              color: kFluxidiYellow.withOpacity(0.035),
              blurRadius: 7,
              spreadRadius: 0.2,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF15120A).withOpacity(0.72),
                border: Border.all(color: kFluxidiYellow.withOpacity(0.24)),
              ),
              child: Icon(
                icon,
                color: kFluxidiYellow.withOpacity(0.98),
                size: 29,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11.6,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _customerQuickActionGrid(BuildContext context) {
    final actions = <({IconData icon, String label, VoidCallback onTap})>[
      (
        icon: Icons.receipt_long_outlined,
        label: _t(
          nl: 'Mijn boekingen',
          en: 'My bookings',
          fr: 'Mes réservations',
          es: 'Mis reservas',
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CustomerSavedBookingsPage()),
        ),
      ),
      (
        icon: Icons.person_outline_rounded,
        label: _t(
          nl: 'Mijn gegevens',
          en: 'My details',
          fr: 'Mes données',
          es: 'Mis datos',
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CustomerProfileEditPage()),
        ),
      ),
      (
        icon: Icons.local_taxi_outlined,
        label: _t(
          nl: 'Taxi in de buurt',
          en: 'Taxi nearby',
          fr: 'Taxi à proximité',
          es: 'Taxi cerca',
        ),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const NearbyPartnersPage())),
      ),
      (
        icon: Icons.app_registration_outlined,
        label: _t(
          nl: 'Registreer je regio',
          en: 'Register your region',
          fr: 'Enregistrer votre région',
          es: 'Registrar tu región',
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const CustomerRegionRegistrationPage(),
          ),
        ),
      ),
      (
        icon: Icons.flight_takeoff_rounded,
        label: _t(
          nl: 'Luchthavenritten',
          en: 'Airport rides',
          fr: 'Trajets aéroport',
          es: 'Traslados aeropuerto',
        ),
        onTap: () => _comingSoon(context),
      ),
      (
        icon: Icons.hotel_rounded,
        label: _t(
          nl: 'Hotels & B&B',
          en: 'Hotels & B&B',
          fr: 'Hôtels & B&B',
          es: 'Hoteles & B&B',
        ),
        onTap: () => _comingSoon(context),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 430 ? 3 : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: actions.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 9,
            mainAxisSpacing: 9,
            mainAxisExtent: 98,
          ),
          itemBuilder: (_, i) => _customerQuickActionCard(
            context: context,
            icon: actions[i].icon,
            label: actions[i].label,
            onTap: actions[i].onTap,
          ),
        );
      },
    );
  }

  Widget _customerWideCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    String? ctaLabel,
    String? visualAsset,
    double? visualHeight,
    Alignment? visualAlignment,
    required VoidCallback onTap,
  }) {
    final hasVisual = visualAsset != null && visualAsset.trim().isNotEmpty;
    final iconChipSize = hasVisual ? 58.0 : 52.0;
    final iconSize = hasVisual ? 31.0 : 28.0;
    final titleFontSize = hasVisual ? 16.8 : 15.2;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: hasVisual ? (visualHeight ?? 130.0) : null,
        clipBehavior: Clip.antiAlias,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: kFluxidiYellow.withOpacity(0.26)),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF101010), Color(0xFF07080C)],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasVisual) ...[
              Positioned.fill(
                child: Image.asset(
                  visualAsset,
                  fit: BoxFit.cover,
                  alignment: visualAlignment ?? Alignment.centerRight,
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      stops: const [0.0, 0.46, 0.78, 1.0],
                      colors: [
                        const Color(0xFF07080C).withOpacity(0.96),
                        const Color(0xFF07080C).withOpacity(0.82),
                        const Color(0xFF07080C).withOpacity(0.38),
                        const Color(0xFF07080C).withOpacity(0.08),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            Row(
              children: [
                Container(
                  width: iconChipSize,
                  height: iconChipSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: kFluxidiYellow.withOpacity(0.18),
                    border: Border.all(color: kFluxidiYellow.withOpacity(0.45)),
                  ),
                  child: Icon(icon, color: kFluxidiYellow, size: iconSize),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: titleFontSize,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle.trim().isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.72),
                            fontSize: 12.4,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (ctaLabel != null) ...[
                        const SizedBox(height: 9),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            color: kFluxidiYellow.withOpacity(0.18),
                            border: Border.all(
                              color: kFluxidiYellow.withOpacity(0.5),
                            ),
                          ),
                          child: Text(
                            ctaLabel,
                            style: const TextStyle(
                              color: Color(0xFFE5B641),
                              fontSize: 11.7,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: kFluxidiYellow.withOpacity(0.94),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _customerBottomNav(BuildContext context) {
    final items = <String>[
      _t(nl: 'Home', en: 'Home', fr: 'Accueil', es: 'Inicio'),
      _t(nl: 'Boek rit', en: 'Book ride', fr: 'Réserver', es: 'Reservar'),
      _t(nl: 'Boekingen', en: 'Bookings', fr: 'Réservations', es: 'Reservas'),
      _t(
        nl: 'Meldingen',
        en: 'Notifications',
        fr: 'Notifications',
        es: 'Notificaciones',
      ),
      _t(nl: 'Profiel', en: 'Profile', fr: 'Profil', es: 'Perfil'),
    ];
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0E1524),
        border: Border(
          top: BorderSide(color: kFluxidiYellow.withOpacity(0.2), width: 0.8),
        ),
      ),
      child: SafeArea(
        top: false,
        child: BottomNavigationBar(
          currentIndex: 0,
          onTap: (i) {
            if (i == 0) return;
            if (i == 1) {
              _openCalculator(context, scheduledIntent: false);
              return;
            }
            if (i == 2) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const CustomerSavedBookingsPage(),
                ),
              );
              return;
            }
            if (i == 4) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const CustomerProfileEditPage(),
                ),
              );
              return;
            }
            _comingSoon(context);
          },
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.transparent,
          selectedItemColor: kFluxidiYellow,
          unselectedItemColor: Colors.white60,
          showUnselectedLabels: true,
          selectedFontSize: 11,
          unselectedFontSize: 11,
          items: [
            BottomNavigationBarItem(
              icon: const Icon(Icons.home_outlined),
              label: items[0],
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.directions_car_outlined),
              label: items[1],
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.receipt_long_outlined),
              label: items[2],
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.notifications_none_rounded),
              label: items[3],
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.person_outline_rounded),
              label: items[4],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) => Scaffold(
        backgroundColor: const Color(0xFF0B1020),
        bottomNavigationBar: _customerBottomNav(context),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              children: [
                _customerHomeHero(context),
                const SizedBox(height: 14),
                _customerPrimaryCta(context),
                const SizedBox(height: 14),
                _customerQuickActionGrid(context),
                const SizedBox(height: 12),
                _customerWideCard(
                  context: context,
                  icon: Icons.celebration_outlined,
                  title: _t(
                    nl: 'Evenementen',
                    en: 'Events',
                    fr: 'Événements',
                    es: 'Eventos',
                  ),
                  subtitle: '',
                  visualAsset: 'assets/fluxidi/fluxidi_event_crowd_night.jpg',
                  visualHeight: 130,
                  visualAlignment: Alignment.centerRight,
                  onTap: () => _comingSoon(context),
                ),
                const SizedBox(height: 10),
                _customerWideCard(
                  context: context,
                  icon: Icons.business_center_outlined,
                  title: _t(
                    nl: 'Zakelijk',
                    en: 'Business',
                    fr: 'Pro',
                    es: 'Empresas',
                  ),
                  subtitle: '',
                  visualAsset:
                      'assets/fluxidi/fluxidi_business_briefcase_night.jpg',
                  visualHeight: 130,
                  visualAlignment: const Alignment(0.65, 0.0),
                  onTap: () => _comingSoon(context),
                ),
                const SizedBox(height: 12),
                const FluxidiBackToStartButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CustomerSavedBookingsPage extends StatefulWidget {
  const CustomerSavedBookingsPage({super.key});

  @override
  State<CustomerSavedBookingsPage> createState() =>
      _CustomerSavedBookingsPageState();
}

class _CustomerSavedBookingsPageState extends State<CustomerSavedBookingsPage> {
  bool _loading = true;
  String? _error;
  List<CustomerSavedBooking> _bookings = const <CustomerSavedBooking>[];

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) => _tr(nl: nl, en: en, fr: fr, es: es);

  @override
  void initState() {
    super.initState();
    unawaited(_loadLocal());
  }

  Future<void> _loadLocal() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await CustomerBookingStore.instance.loadAll();
      final visible = items
          .where((item) => _isActiveCustomerLifecycleStatus(item.bookingStatus))
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _bookings = visible;
        _loading = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _t(
          nl: 'Laden mislukt.',
          en: 'Loading failed.',
          fr: 'Chargement echoue.',
          es: 'Error al cargar.',
        );
      });
    }
  }

  Set<String> _aliasesForSavedBooking(CustomerSavedBooking booking) {
    return _customerBookingDeleteAliases(
      bookingId: booking.bookingId,
      publicBookingReference: booking.publicReference,
      bookingReference: booking.publicReference,
      publicReference: booking.publicReference,
      source: booking.rawSnapshot,
    );
  }

  String _formatPickup(String iso) {
    if (iso.trim().isEmpty) return '-';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    String two(int n) => n.toString().padLeft(2, '0');
    final local = dt.toLocal();
    return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
  }

  String _formatPrice(CustomerSavedBooking booking) {
    final amount = booking.price;
    if (amount == null) return '-';
    final currency = booking.currency.toUpperCase().trim();
    final symbol = currency.isEmpty || currency == 'EUR' ? '€' : '$currency ';
    return '$symbol${amount.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  String _paymentLabel(CustomerSavedBooking booking) {
    final p = booking.paymentStatus.toLowerCase().trim();
    if (p == 'paid' || p == 'confirmed' || p == 'completed' || p == 'success') {
      return _t(nl: 'Betaald', en: 'Paid', fr: 'Paye', es: 'Pagado');
    }
    if (p == 'pending' || p == 'unpaid' || p == 'pay_in_car') {
      return _t(
        nl: 'Te betalen in de wagen',
        en: 'To pay in the vehicle',
        fr: 'A payer dans le vehicule',
        es: 'A pagar en el vehiculo',
      );
    }
    return p.isEmpty
        ? '-'
        : _t(nl: 'Onbekend', en: 'Unknown', fr: 'Inconnu', es: 'Desconocido');
  }

  String _bookingStatusLabel(CustomerSavedBooking booking) {
    final status = _normalizeCustomerLifecycleStatus(booking.bookingStatus);
    if (status == 'PENDING') {
      return _t(
        nl: 'In behandeling',
        en: 'Pending',
        fr: 'En cours',
        es: 'Pendiente',
      );
    }
    if (status == 'CONFIRMED') {
      return _t(
        nl: 'Bevestigd',
        en: 'Confirmed',
        fr: 'Confirmee',
        es: 'Confirmada',
      );
    }
    if (status == 'COMPLETED') {
      return _t(
        nl: 'Voltooid',
        en: 'Completed',
        fr: 'Terminee',
        es: 'Finalizada',
      );
    }
    if (status == 'CANCELLED') {
      return _t(
        nl: 'Geannuleerd',
        en: 'Cancelled',
        fr: 'Annulee',
        es: 'Cancelada',
      );
    }
    return status.isEmpty
        ? '-'
        : _t(nl: 'Onbekend', en: 'Unknown', fr: 'Inconnu', es: 'Desconocido');
  }

  Future<void> _openSavedBooking(CustomerSavedBooking booking) async {
    final id = booking.bookingId.trim();
    if (id.isEmpty) return;
    final beforeCount = _bookings.length;
    final aliases = _aliasesForSavedBooking(booking);
    try {
      final uri = _withActiveBookingScope(
        kBookingBaseUrl,
        '/bookings/${Uri.encodeComponent(id)}',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        if (decoded is Map<String, dynamic> && decoded['ok'] == true) {
          final view = CustomerBookingView.fromResponse(id, decoded);
          if (!mounted) return;
          final result = await Navigator.of(context).push<dynamic>(
            MaterialPageRoute(
              builder: (_) => CustomerBookingDetailPage(
                bookingId: id,
                initialView: view,
                startsFromLocalCache: false,
              ),
            ),
          );
          final action = _customerDetailResultAction(result);
          if (action == _customerDetailResultRemovedLocal ||
              action == _customerDetailResultCancelledServer) {
            if (mounted) {
              setState(() {
                _bookings = _bookings
                    .where(
                      (item) => !_customerAliasesIntersect(
                        _aliasesForSavedBooking(item),
                        aliases,
                      ),
                    )
                    .toList(growable: false);
              });
            }
            await _loadLocal();
          }
          if (mounted) {
            debugPrint(
              '[CUSTOMER_BOOKINGS][DETAIL_RETURN] action=${action ?? "-"} beforeCount=$beforeCount afterCount=${_bookings.length}',
            );
          }
          return;
        }
      }
    } catch (_) {
      // fall back to local-safe minimal view
    }

    final fallback = StoredCustomerBooking(
      bookingId: id,
      publicBookingId: booking.publicReference.trim().isNotEmpty
          ? booking.publicReference.trim()
          : id,
      customerName: '',
      customerPhone: '',
      customerEmail: '',
      from: booking.from,
      to: booking.to,
      pickupIso: booking.pickupIso,
      price: booking.price,
      currency: booking.currency,
      paymentStatus: booking.paymentStatus,
      status: booking.bookingStatus,
      createdAt: booking.createdAt,
      updatedAt: booking.createdAt,
    );
    if (!mounted) return;
    final result = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute(
        builder: (_) => CustomerBookingDetailPage(
          bookingId: id,
          initialView: CustomerBookingView.fromStored(fallback),
          startsFromLocalCache: true,
        ),
      ),
    );
    final action = _customerDetailResultAction(result);
    if (action == _customerDetailResultRemovedLocal ||
        action == _customerDetailResultCancelledServer) {
      if (mounted) {
        setState(() {
          _bookings = _bookings
              .where(
                (item) => !_customerAliasesIntersect(
                  _aliasesForSavedBooking(item),
                  aliases,
                ),
              )
              .toList(growable: false);
        });
      }
      await _loadLocal();
    }
    if (mounted) {
      debugPrint(
        '[CUSTOMER_BOOKINGS][DETAIL_RETURN] action=${action ?? "-"} beforeCount=$beforeCount afterCount=${_bookings.length}',
      );
    }
  }

  Future<void> _clearAllLocalBookings() async {
    debugPrint('[CUSTOMER_BOOKINGS][CLEAR_ALL_REQ] count=${_bookings.length}');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          _t(
            nl: 'Alle boekingen verwijderen?',
            en: 'Remove all bookings?',
            fr: 'Supprimer toutes les réservations ?',
            es: '¿Eliminar todas las reservas?',
          ),
        ),
        content: Text(
          _t(
            nl: 'Hiermee verwijder je alleen de boekingen uit je lokale overzicht op dit toestel. De bedrijfsadministratie, ritgeschiedenis en betalingen blijven bewaard.',
            en: 'This only removes the bookings from your local overview on this device. Company records, ride history and payments remain stored.',
            fr: 'Cela supprime uniquement les réservations de votre aperçu local sur cet appareil. L’administration, l’historique des trajets et les paiements restent conservés.',
            es: 'Esto solo elimina las reservas de tu vista local en este dispositivo. La administración de la empresa, el historial de viajes y los pagos se conservan.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              _t(nl: 'Annuleren', en: 'Cancel', fr: 'Annuler', es: 'Cancelar'),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              _t(
                nl: 'Alles verwijderen',
                en: 'Remove all',
                fr: 'Tout supprimer',
                es: 'Eliminar todo',
              ),
            ),
          ),
        ],
      ),
    );
    debugPrint(
      '[CUSTOMER_BOOKINGS][DELETE_CONFIRM] action=clear_all confirmed=${confirmed == true} count=${_bookings.length}',
    );
    if (confirmed != true) return;
    try {
      await CustomerBookingStore.instance.clearLocalTestData();
      if (!mounted) return;
      setState(() {
        _bookings = const <CustomerSavedBooking>[];
      });
      await _loadLocal();
      if (!mounted) return;
      debugPrint(
        '[CUSTOMER_BOOKINGS][CLEAR_ALL_OK] remaining=${_bookings.length}',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Alle lokale boekingen zijn verwijderd.',
              en: 'All local bookings have been removed.',
              fr: 'Toutes les réservations locales ont été supprimées.',
              es: 'Todas las reservas locales han sido eliminadas.',
            ),
          ),
        ),
      );
    } catch (err) {
      debugPrint('[CUSTOMER_BOOKINGS][CLEAR_ALL_ERROR] err=$err');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) {
        debugPrint(
          '[CUSTOMER_BOOKINGS][VISIBLE_BUILD] count=${_bookings.length}',
        );
        return Scaffold(
          backgroundColor: const Color(0xFF0B1020),
          appBar: AppBar(
            backgroundColor: const Color(0xFF0B1020),
            title: Text(
              _t(
                nl: 'Mijn boekingen',
                en: 'My bookings',
                fr: 'Mes reservations',
                es: 'Mis reservas',
              ),
            ),
            actions: [
              IconButton(
                tooltip: _t(
                  nl: 'Alles verwijderen',
                  en: 'Remove all',
                  fr: 'Tout supprimer',
                  es: 'Eliminar todo',
                ),
                onPressed: _bookings.isEmpty ? null : _clearAllLocalBookings,
                icon: const Icon(Icons.delete_sweep),
              ),
              IconButton(
                tooltip: _t(
                  nl: 'Vernieuwen',
                  en: 'Refresh',
                  fr: 'Actualiser',
                  es: 'Actualizar',
                ),
                onPressed: _loadLocal,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.withOpacity(0.4)),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Color(0xFFFFB4B4)),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_loading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (_bookings.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141B2F),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      _t(
                        nl: 'Nog geen boekingen op dit toestel.',
                        en: 'No bookings on this device yet.',
                        fr: 'Aucune réservation sur cet appareil pour le moment.',
                        es: 'Aún no hay reservas en este dispositivo.',
                      ),
                      style: const TextStyle(color: Colors.white70),
                    ),
                  )
                else
                  ..._bookings.map(
                    (booking) => Card(
                      color: const Color(0xFF141B2F),
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _openSavedBooking(booking),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${booking.from.trim().isEmpty ? '-' : booking.from} → ${booking.to.trim().isEmpty ? '-' : booking.to}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${_t(nl: 'Ophaal', en: 'Pickup', fr: 'Prise en charge', es: 'Recogida')}: ${_formatPickup(booking.pickupIso)}',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.82),
                                ),
                              ),
                              Text(
                                '${_t(nl: 'Prijs', en: 'Price', fr: 'Prix', es: 'Precio')}: ${_formatPrice(booking)}',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.82),
                                ),
                              ),
                              Text(
                                '${_t(nl: 'Betaalstatus', en: 'Payment status', fr: 'Statut de paiement', es: 'Estado de pago')}: ${_paymentLabel(booking)}',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.82),
                                ),
                              ),
                              Text(
                                '${_t(nl: 'Boekingsstatus', en: 'Booking status', fr: 'Statut de réservation', es: 'Estado de la reserva')}: ${_bookingStatusLabel(booking)}',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.82),
                                ),
                              ),
                              Text(
                                '${_t(nl: 'Referentie', en: 'Reference', fr: 'Référence', es: 'Referencia')}: ${(booking.publicReference.trim().isNotEmpty ? booking.publicReference.trim() : booking.bookingId.trim())}',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.82),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.search_outlined),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CustomerBookingLookupPage(),
                      ),
                    ),
                    label: Text(
                      _t(
                        nl: 'Boeking handmatig zoeken',
                        en: 'Find booking manually',
                        fr: 'Rechercher une réservation manuellement',
                        es: 'Buscar reserva manualmente',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class CustomerBookingsPage extends StatefulWidget {
  const CustomerBookingsPage({super.key});

  @override
  State<CustomerBookingsPage> createState() => _CustomerBookingsPageState();
}

dynamic _customerBookingValueAtPath(Map<String, dynamic> root, String path) {
  dynamic current = root;
  for (final segment in path.split('.')) {
    if (current is Map && current.containsKey(segment)) {
      current = current[segment];
    } else {
      return null;
    }
  }
  return current;
}

Set<String> _customerBookingAliasesFromSource(Map<String, dynamic> source) {
  const aliasPaths = <String>[
    'booking_id',
    'bookingId',
    'id',
    'public_booking_reference',
    'publicBookingReference',
    'booking_reference',
    'bookingReference',
    'public_reference',
    'publicReference',
    'planning_reference',
    'planningReference',
    'receipt_reference',
    'receiptReference',
    'booking.booking_id',
    'booking.bookingId',
    'booking.id',
    'booking.public_booking_reference',
    'booking.publicBookingReference',
    'booking.booking_reference',
    'booking.bookingReference',
    'booking.public_reference',
    'booking.publicReference',
    'booking.planning_reference',
    'booking.planningReference',
    'booking.receipt_reference',
    'booking.receiptReference',
    'record.booking_id',
    'record.bookingId',
    'record.id',
    'record.booking.booking_id',
    'record.booking.bookingId',
    'record.booking.id',
    'record.references.public_booking_reference',
    'record.references.publicBookingReference',
    'record.references.booking_reference',
    'record.references.bookingReference',
    'record.references.public_reference',
    'record.references.publicReference',
    'record.references.planning_reference',
    'record.references.planningReference',
    'record.references.receipt_reference',
    'record.references.receiptReference',
    'payload.booking_id',
    'payload.bookingId',
    'payload.id',
    'payload.booking.booking_id',
    'payload.booking.bookingId',
    'payload.booking.id',
    'payload.references.public_booking_reference',
    'payload.references.publicBookingReference',
    'payload.references.booking_reference',
    'payload.references.bookingReference',
    'payload.references.public_reference',
    'payload.references.publicReference',
    'payload.references.planning_reference',
    'payload.references.planningReference',
    'payload.references.receipt_reference',
    'payload.references.receiptReference',
    'references.public_booking_reference',
    'references.publicBookingReference',
    'references.booking_reference',
    'references.bookingReference',
    'references.public_reference',
    'references.publicReference',
    'references.planning_reference',
    'references.planningReference',
    'references.receipt_reference',
    'references.receiptReference',
  ];
  final aliases = <String>{};
  void addAlias(dynamic value) {
    final text = _cleanBusinessReferenceText(value?.toString());
    if (text == null) return;
    aliases.add(text.toLowerCase());
  }

  for (final path in aliasPaths) {
    addAlias(_customerBookingValueAtPath(source, path));
  }
  return aliases;
}

Set<String> _customerBookingDeleteAliases({
  String? bookingId,
  String? publicBookingReference,
  String? bookingReference,
  String? publicReference,
  String? planningReference,
  String? receiptReference,
  String? paymentBookingId,
  Map<String, dynamic>? source,
}) {
  final aliases = <String>{};
  void addAlias(String? value) {
    final text = _cleanBusinessReferenceText(value);
    if (text == null) return;
    aliases.add(text.toLowerCase());
  }

  addAlias(bookingId);
  addAlias(publicBookingReference);
  addAlias(bookingReference);
  addAlias(publicReference);
  addAlias(planningReference);
  addAlias(receiptReference);
  addAlias(paymentBookingId);
  if (source != null && source.isNotEmpty) {
    aliases.addAll(_customerBookingAliasesFromSource(source));
  }
  return aliases;
}

Set<String> _customerBookingAliasesFromStored(StoredCustomerBooking booking) {
  return _customerBookingDeleteAliases(
    bookingId: booking.bookingId,
    publicBookingReference: booking.publicBookingReference,
    bookingReference: booking.bookingReference,
    publicReference: booking.publicReference,
    planningReference: booking.planningReference,
    receiptReference: booking.receiptReference,
    paymentBookingId: booking.paymentBookingId,
  );
}

const String _customerDetailResultRemovedLocal = 'removed_local';
const String _customerDetailResultCancelledServer = 'cancelled_server';

String? _customerDetailResultAction(dynamic result) {
  if (result == true) return _customerDetailResultRemovedLocal;
  if (result is String && result.trim().isNotEmpty) return result.trim();
  if (result is Map) {
    final action = result['action']?.toString().trim();
    if (action != null && action.isNotEmpty) return action;
  }
  return null;
}

String _normalizeCustomerLifecycleStatus(String raw) {
  final value = raw.trim().toUpperCase();
  if (value.isEmpty) return '';
  switch (value) {
    case 'PENDING':
    case 'IN_REVIEW':
      return 'PENDING';
    case 'CONFIRMED':
    case 'ACCEPTED':
    case 'ASSIGNED':
    case 'ACTIVE':
    case 'IN_PROGRESS':
    case 'ON_ROUTE':
    case 'ARRIVED':
    case 'STARTED':
      return 'CONFIRMED';
    case 'COMPLETED':
    case 'FINISHED':
    case 'DONE':
    case 'CLOSED':
      return 'COMPLETED';
    case 'CANCELLED':
    case 'CANCELED':
      return 'CANCELLED';
    case 'DELETED':
    case 'REMOVED':
      return 'DELETED';
    case 'FAILED':
    case 'ERROR':
      return 'FAILED';
    case 'EXPIRED':
      return 'EXPIRED';
    case 'DECLINED':
    case 'REJECTED':
      return 'DECLINED';
    default:
      return value;
  }
}

bool _isActiveCustomerLifecycleStatus(String status) {
  final s = _normalizeCustomerLifecycleStatus(status);
  if (s.isEmpty) return true;
  return s != 'CANCELLED' &&
      s != 'DELETED' &&
      s != 'FAILED' &&
      s != 'EXPIRED' &&
      s != 'DECLINED';
}

StoredCustomerBooking _hydrateStoredCustomerBookingFromView({
  required StoredCustomerBooking stored,
  required CustomerBookingView view,
  required String source,
}) {
  final normalizedStatus = _normalizeCustomerLifecycleStatus(
    view.lifecycleStatus,
  );
  final normalizedPayment = view.rawPaymentStatus.trim().toLowerCase();
  // Business/invoice fields must reflect this booking record only. Do not let
  // prior locally stored profile/business values turn a private booking into a
  // business booking during hydration.
  final rawCompanyName = view.companyName.trim();
  final rawVatNumber = view.vatNumber.trim();
  final rawInvoiceEmail = view.invoiceEmail.trim();
  final rawInvoiceAddress = view.invoiceAddress.trim();
  final hasVat = rawVatNumber.isNotEmpty;
  final hasBusinessIntent = view.businessCustomer || view.invoiceRequested;
  final isBusinessBooking = hasVat && hasBusinessIntent;
  final mergedCompanyName = isBusinessBooking ? rawCompanyName : '';
  final mergedVatNumber = isBusinessBooking ? rawVatNumber : '';
  final mergedInvoiceEmail = isBusinessBooking ? rawInvoiceEmail : '';
  final mergedInvoiceAddress = isBusinessBooking ? rawInvoiceAddress : '';
  final mergedBusinessDetected = isBusinessBooking;
  final mergedInvoiceRequested = isBusinessBooking;
  debugPrint(
    '[CUSTOMER_BOOKING][HYDRATE_STATUS] source=$source booking=${_safeRefPreview(view.bookingId)} raw=${view.lifecycleStatus} normalized=$normalizedStatus',
  );
  // #region agent log H2 status normalization result
  unawaited(
    _agentDebugLog(
      runId: 'initial',
      hypothesisId: 'H2',
      location: 'main.dart:_hydrateStoredCustomerBookingFromView',
      message: '[CUSTOMER_BOOKING][HYDRATE_STATUS]',
      data: <String, dynamic>{
        'source': source,
        'booking': _safeRefPreview(view.bookingId),
        'rawStatus': view.lifecycleStatus,
        'normalizedStatus': normalizedStatus,
        'storedStatusBefore': stored.status,
        'storedStatusAfter': normalizedStatus.isNotEmpty
            ? normalizedStatus
            : stored.status,
      },
    ),
  );
  // #endregion
  debugPrint(
    '[CUSTOMER_BOOKING][BUSINESS_FIELDS] source=$source booking=${_safeRefPreview(view.bookingId)} business=$mergedBusinessDetected invoiceRequested=$mergedInvoiceRequested companyFound=${mergedCompanyName.trim().isNotEmpty} vatFound=${mergedVatNumber.trim().isNotEmpty} invoiceEmailFound=${mergedInvoiceEmail.trim().isNotEmpty} invoiceAddressFound=${mergedInvoiceAddress.trim().isNotEmpty}',
  );
  // #region agent log H3 business merge result
  unawaited(
    _agentDebugLog(
      runId: 'initial',
      hypothesisId: 'H3',
      location: 'main.dart:_hydrateStoredCustomerBookingFromView',
      message: '[CUSTOMER_BOOKING][BUSINESS_FIELDS]',
      data: <String, dynamic>{
        'source': source,
        'booking': _safeRefPreview(view.bookingId),
        'viewBusiness': view.businessCustomer,
        'viewInvoiceRequested': view.invoiceRequested,
        'storedBusinessBefore': stored.businessDetected,
        'storedInvoiceRequestedBefore': stored.invoiceRequested,
        'mergedBusiness': mergedBusinessDetected,
        'mergedInvoiceRequested': mergedInvoiceRequested,
        'companyFound': mergedCompanyName.trim().isNotEmpty,
        'vatFound': mergedVatNumber.trim().isNotEmpty,
        'invoiceEmailFound': mergedInvoiceEmail.trim().isNotEmpty,
        'invoiceAddressFound': mergedInvoiceAddress.trim().isNotEmpty,
      },
    ),
  );
  // #endregion
  return stored.copyWith(
    status: normalizedStatus.isNotEmpty ? normalizedStatus : stored.status,
    paymentStatus: normalizedPayment.isNotEmpty
        ? normalizedPayment
        : stored.paymentStatus,
    businessDetected: mergedBusinessDetected,
    invoiceRequested: mergedInvoiceRequested,
    companyName: mergedCompanyName,
    vatNumber: mergedVatNumber,
    invoiceEmail: mergedInvoiceEmail,
    invoiceAddress: mergedInvoiceAddress,
  );
}

bool _customerAliasesIntersect(Set<String> a, Set<String> b) {
  for (final value in a) {
    if (b.contains(value)) return true;
  }
  return false;
}

Future<({bool removed, bool storeA, bool storeB, int remaining})>
_removeLocalCustomerBookingEverywhere({
  required String bookingForLog,
  required Set<String> aliases,
}) async {
  final sortedAliases = aliases.toList(growable: false)..sort();
  debugPrint(
    '[CUSTOMER_BOOKING][DELETE_REQ] booking=${_safeRefPreview(bookingForLog)} aliases=${sortedAliases.join(',')}',
  );
  final result = await CustomerBookingStore.instance
      .removeLocalBookingByAnyReference(aliases);
  debugPrint(
    '[CUSTOMER_BOOKING][DELETE_RESULT] removed=${result.removed} storeA=${result.storeA} storeB=${result.storeB} remaining=${result.remaining}',
  );
  return result;
}

class _CustomerBookingsPageState extends State<CustomerBookingsPage> {
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  DateTime? _lastUpdated;
  List<StoredCustomerBooking> _bookings = const <StoredCustomerBooking>[];

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) => _tr(nl: nl, en: en, fr: fr, es: es);

  @override
  void initState() {
    super.initState();
    _loadLocal();
  }

  Future<void> _loadLocal() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await CustomerBookingsStore.instance.loadAll();
      final visible = items
          .where((item) => _isActiveCustomerLifecycleStatus(item.status))
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _bookings = visible;
        _loading = false;
        _lastUpdated = DateTime.now();
      });
      debugPrint(
        '[CUSTOMER_BOOKINGS][RELOAD_AFTER_DELETE] count=${visible.length}',
      );
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _t(
          nl: 'Laden mislukt.',
          en: 'Loading failed.',
          fr: 'Chargement echoue.',
          es: 'Error al cargar.',
        );
      });
      debugPrint('[CUSTOMER_BOOKINGS][LOAD_SCREEN_ERROR] $err');
    }
  }

  Future<void> _refreshAuthoritative() async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      _error = null;
    });
    try {
      final snapshot = await CustomerBookingsStore.instance.loadAll();
      for (final item in snapshot) {
        final id = item.canonicalBookingId.trim();
        if (id.isEmpty) continue;
        try {
          final uri = _withActiveBookingScope(
            kBookingBaseUrl,
            '/bookings/${Uri.encodeComponent(id)}',
          );
          final res = await http.get(uri).timeout(const Duration(seconds: 12));
          if (res.statusCode != 200) continue;
          final decoded = jsonDecode(utf8.decode(res.bodyBytes));
          if (decoded is! Map<String, dynamic> || decoded['ok'] != true)
            continue;
          final authoritativeView = CustomerBookingView.fromResponse(
            id,
            decoded,
          );
          final stored = StoredCustomerBooking.fromAuthoritativeResponse(
            bookingId: id,
            response: decoded,
            fallback: item,
          );
          await CustomerBookingsStore.instance.upsert(
            _hydrateStoredCustomerBookingFromView(
              stored: stored,
              view: authoritativeView,
              source: 'customer_list_refresh',
            ),
          );
        } catch (_) {
          // Keep refresh resilient: skip individual booking failures.
        }
      }
      final refreshed = await CustomerBookingsStore.instance.loadAll();
      final visible = refreshed
          .where((item) => _isActiveCustomerLifecycleStatus(item.status))
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _bookings = visible;
        _refreshing = false;
        _lastUpdated = DateTime.now();
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _refreshing = false;
        _error = _t(
          nl: 'Vernieuwen mislukt.',
          en: 'Refresh failed.',
          fr: "Echec de l'actualisation.",
          es: 'Error al actualizar.',
        );
      });
      debugPrint('[CUSTOMER_BOOKINGS][REFRESH_ERROR] $err');
    }
  }

  String _formatPickup(String iso) {
    if (iso.trim().isEmpty) return '-';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
  }

  String _formatPrice(StoredCustomerBooking booking) {
    final amount = booking.price;
    if (amount == null) return '-';
    final currency = booking.currency.toUpperCase().trim();
    final symbol = currency.isEmpty || currency == 'EUR' ? '€' : '$currency ';
    return '$symbol${amount.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  String _statusLabel(StoredCustomerBooking booking) {
    final status = _normalizeCustomerLifecycleStatus(booking.status);
    if (status == 'PENDING') {
      return _t(
        nl: 'In behandeling',
        en: 'Pending',
        fr: 'En cours',
        es: 'Pendiente',
      );
    }
    if (status == 'CONFIRMED') {
      return _t(
        nl: 'Bevestigd',
        en: 'Confirmed',
        fr: 'Confirmee',
        es: 'Confirmada',
      );
    }
    if (status == 'COMPLETED') {
      return _t(
        nl: 'Voltooid',
        en: 'Completed',
        fr: 'Terminee',
        es: 'Finalizada',
      );
    }
    if (status == 'CANCELLED') {
      return _t(
        nl: 'Geannuleerd',
        en: 'Cancelled',
        fr: 'Annulee',
        es: 'Cancelada',
      );
    }
    return status.isEmpty
        ? '-'
        : _t(nl: 'Onbekend', en: 'Unknown', fr: 'Inconnu', es: 'Desconocido');
  }

  String _paymentLabel(StoredCustomerBooking booking) {
    final p = booking.paymentStatus.toLowerCase().trim();
    if (p == 'paid' || p == 'confirmed' || p == 'success' || p == 'completed') {
      return _t(nl: 'Betaald', en: 'Paid', fr: 'Paye', es: 'Pagado');
    }
    if (p == 'unpaid' || p == 'pending' || p == 'pay_in_car') {
      return _t(
        nl: 'Te betalen in de wagen',
        en: 'To pay in the vehicle',
        fr: 'A payer dans le vehicule',
        es: 'A pagar en el vehiculo',
      );
    }
    return _t(
      nl: 'Te betalen in de wagen',
      en: 'To pay in the vehicle',
      fr: 'A payer dans le vehicule',
      es: 'A pagar en el vehiculo',
    );
  }

  String _formatLastUpdated() {
    final value = _lastUpdated;
    if (value == null) return '-';
    String two(int n) => n.toString().padLeft(2, '0');
    final local = value.toLocal();
    return '${two(local.day)}/${two(local.month)} ${two(local.hour)}:${two(local.minute)}';
  }

  Future<void> _openDetails(StoredCustomerBooking booking) async {
    final id = booking.canonicalBookingId.trim();
    if (id.isEmpty) return;
    final aliases = _customerBookingAliasesFromStored(booking);
    final result = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute(
        builder: (_) => CustomerBookingDetailPage(
          bookingId: id,
          initialView: CustomerBookingView.fromStored(booking),
          startsFromLocalCache: true,
        ),
      ),
    );
    final action = _customerDetailResultAction(result);
    if (action == _customerDetailResultRemovedLocal ||
        action == _customerDetailResultCancelledServer) {
      if (mounted) {
        setState(() {
          _bookings = _bookings
              .where(
                (item) => !_customerAliasesIntersect(
                  _customerBookingAliasesFromStored(item),
                  aliases,
                ),
              )
              .toList(growable: false);
        });
      }
      await _loadLocal();
      if (!mounted) return;
      if (action == _customerDetailResultRemovedLocal) {
        final message = _t(
          nl: 'Boeking verwijderd uit je lokale overzicht.',
          en: 'Booking removed from your local overview.',
          fr: 'Réservation supprimée de votre aperçu local.',
          es: 'Reserva eliminada de tu vista local.',
        );
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
      return;
    }
    await _loadLocal();
  }

  Future<void> _removeFromMyBookings(StoredCustomerBooking booking) async {
    final bookingId = booking.canonicalBookingId.trim();
    if (bookingId.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          _t(
            nl: 'Boeking verwijderen?',
            en: 'Remove booking?',
            fr: 'Supprimer la réservation ?',
            es: '¿Eliminar reserva?',
          ),
        ),
        content: Text(
          _t(
            nl: 'Deze boeking wordt alleen uit jouw lokale overzicht verwijderd. De bedrijfsadministratie en ritgeschiedenis blijven bewaard.',
            en: 'This booking will only be removed from your local overview. Company administration and ride history remain stored.',
            fr: 'Cette réservation sera supprimée uniquement de votre aperçu local. L’administration de l’entreprise et l’historique des trajets restent conservés.',
            es: 'Esta reserva solo se eliminará de tu vista local. La administración de la empresa y el historial del viaje se conservan.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              _t(nl: 'Annuleren', en: 'Cancel', fr: 'Annuler', es: 'Cancelar'),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              _t(
                nl: 'Verwijderen',
                en: 'Remove',
                fr: 'Supprimer',
                es: 'Eliminar',
              ),
            ),
          ),
        ],
      ),
    );
    debugPrint(
      '[CUSTOMER_BOOKINGS][DELETE_CONFIRM] action=remove_one confirmed=${confirmed == true} booking=${_safeRefPreview(bookingId)}',
    );
    if (confirmed != true || !mounted) return;
    final result = await _removeLocalCustomerBookingEverywhere(
      bookingForLog: bookingId,
      aliases: _customerBookingDeleteAliases(
        bookingId: booking.bookingId,
        publicBookingReference: booking.publicBookingReference,
        bookingReference: booking.bookingReference,
        publicReference: booking.publicReference,
        planningReference: booking.planningReference,
        receiptReference: booking.receiptReference,
        paymentBookingId: booking.paymentBookingId,
      ),
    );
    await _loadLocal();
    if (!mounted) return;
    final message = result.removed
        ? _t(
            nl: 'Boeking verwijderd uit je lokale overzicht.',
            en: 'Booking removed from your local overview.',
            fr: 'Réservation supprimée de votre aperçu local.',
            es: 'Reserva eliminada de tu vista local.',
          )
        : _t(
            nl: 'Boeking niet gevonden in lokale opslag.',
            en: 'Booking not found in local storage.',
            fr: 'Réservation introuvable dans le stockage local.',
            es: 'Reserva no encontrada en el almacenamiento local.',
          );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _removeAllFromMyBookings() async {
    debugPrint('[CUSTOMER_BOOKINGS][CLEAR_ALL_REQ]');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          _t(
            nl: 'Alle boekingen verwijderen?',
            en: 'Remove all bookings?',
            fr: 'Supprimer toutes les réservations ?',
            es: '¿Eliminar todas las reservas?',
          ),
        ),
        content: Text(
          _t(
            nl: 'Hiermee verwijder je alleen de boekingen uit je lokale overzicht op dit toestel. De bedrijfsadministratie, ritgeschiedenis en betalingen blijven bewaard.',
            en: 'This only removes the bookings from your local overview on this device. Company records, ride history and payments remain stored.',
            fr: 'Cela supprime uniquement les réservations de votre aperçu local sur cet appareil. L’administration, l’historique des trajets et les paiements restent conservés.',
            es: 'Esto solo elimina las reservas de tu vista local en este dispositivo. La administración de la empresa, el historial de viajes y los pagos se conservan.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              _t(nl: 'Annuleren', en: 'Cancel', fr: 'Annuler', es: 'Cancelar'),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              _t(
                nl: 'Alles verwijderen',
                en: 'Remove all',
                fr: 'Tout supprimer',
                es: 'Eliminar todo',
              ),
            ),
          ),
        ],
      ),
    );
    debugPrint(
      '[CUSTOMER_BOOKINGS][DELETE_CONFIRM] action=remove_all confirmed=${confirmed == true} count=${_bookings.length}',
    );
    if (confirmed != true) return;
    try {
      await CustomerBookingStore.instance.clearLocalTestData();
      if (!mounted) return;
      setState(() {
        _bookings = const <StoredCustomerBooking>[];
        _lastUpdated = DateTime.now();
      });
      await _loadLocal();
      if (!mounted) return;
      debugPrint(
        '[CUSTOMER_BOOKINGS][CLEAR_ALL_OK] remaining=${_bookings.length}',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Alle lokale boekingen zijn verwijderd.',
              en: 'All local bookings have been removed.',
              fr: 'Toutes les réservations locales ont été supprimées.',
              es: 'Todas las reservas locales han sido eliminadas.',
            ),
          ),
        ),
      );
    } catch (err) {
      debugPrint('[CUSTOMER_BOOKINGS][CLEAR_ALL_ERROR] err=$err');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) => Scaffold(
        backgroundColor: const Color(0xFF0B1020),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0B1020),
          title: Text(
            _t(
              nl: 'Mijn boekingen',
              en: 'My bookings',
              fr: 'Mes reservations',
              es: 'Mis reservas',
            ),
          ),
          actions: [
            IconButton(
              tooltip: _t(
                nl: 'Vernieuwen',
                en: 'Refresh',
                fr: 'Actualiser',
                es: 'Actualizar',
              ),
              onPressed: _refreshing ? null : _refreshAuthoritative,
              icon: _refreshing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
          ],
        ),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _refreshAuthoritative,
            child: ListView(
              padding: const EdgeInsets.all(16),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                Text(
                  '${_t(nl: 'Laatst bijgewerkt', en: 'Last updated', fr: 'Derniere mise a jour', es: 'Ultima actualizacion')}: ${_formatLastUpdated()}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.65),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _bookings.isEmpty
                        ? null
                        : _removeAllFromMyBookings,
                    icon: const Icon(Icons.delete_sweep, size: 18),
                    label: Text(
                      _t(
                        nl: 'Alles verwijderen',
                        en: 'Remove all',
                        fr: 'Tout supprimer',
                        es: 'Eliminar todo',
                      ),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.withOpacity(0.4)),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Color(0xFFFFB4B4)),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                if (_loading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (_bookings.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141B2F),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      _t(
                        nl: 'Geen boekingen gevonden.',
                        en: 'No bookings found.',
                        fr: 'Aucune reservation trouvee.',
                        es: 'No se encontraron reservas.',
                      ),
                      style: const TextStyle(color: Colors.white70),
                    ),
                  )
                else
                  ..._bookings.map(
                    (booking) => Card(
                      color: const Color(0xFF141B2F),
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _t(
                                nl: 'Route',
                                en: 'Route',
                                fr: 'Itineraire',
                                es: 'Ruta',
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_t(nl: 'Ophaaladres', en: 'Pickup', fr: 'Prise en charge', es: 'Recogida')}: ${booking.from.isEmpty ? '-' : booking.from}',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.86),
                              ),
                              softWrap: true,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${_t(nl: 'Bestemming', en: 'Destination', fr: 'Destination', es: 'Destino')}: ${booking.to.isEmpty ? '-' : booking.to}',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.86),
                              ),
                              softWrap: true,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${_t(nl: 'Geplande ophaal', en: 'Scheduled pickup', fr: 'Prise en charge prevue', es: 'Recogida programada')}: ${_formatPickup(booking.pickupIso)}',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                              ),
                            ),
                            Text(
                              '${_t(nl: 'Status', en: 'Status', fr: 'Statut', es: 'Estado')}: ${_statusLabel(booking)}',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                              ),
                            ),
                            Text(
                              '${_t(nl: 'Betaalstatus', en: 'Payment status', fr: 'Statut de paiement', es: 'Estado de pago')}: ${_paymentLabel(booking)}',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${_t(nl: 'Prijs', en: 'Price', fr: 'Prix', es: 'Precio')}: ',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.8),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    _formatPrice(booking),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    textAlign: TextAlign.right,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                OutlinedButton(
                                  onPressed: () =>
                                      _removeFromMyBookings(booking),
                                  child: Text(
                                    _t(
                                      nl: 'Verwijder uit mijn boekingen',
                                      en: 'Remove from my bookings',
                                      fr: 'Supprimer de mes réservations',
                                      es: 'Eliminar de mis reservas',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton(
                                  onPressed: () => _openDetails(booking),
                                  child: Text(
                                    _t(
                                      nl: 'Boeking bekijken',
                                      en: 'View booking',
                                      fr: 'Voir la reservation',
                                      es: 'Ver reserva',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.search_outlined),
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const CustomerBookingLookupPage(),
                        ),
                      );
                      await _loadLocal();
                    },
                    label: Text(
                      _t(
                        nl: 'Andere boeking opzoeken',
                        en: 'Look up another booking',
                        fr: 'Rechercher une autre reservation',
                        es: 'Buscar otra reserva',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Customer-facing booking lookup screen.
///
/// Lets a customer enter a booking reference (and optionally phone/email for
/// validation) and retrieves authoritative booking details via
/// `GET /bookings/{id}`. Read-only — does not touch payment, pricing, booking
/// creation or driver flows.
class CustomerBookingLookupPage extends StatefulWidget {
  const CustomerBookingLookupPage({super.key});

  @override
  State<CustomerBookingLookupPage> createState() =>
      _CustomerBookingLookupPageState();
}

class _CustomerBookingLookupPageState extends State<CustomerBookingLookupPage> {
  final _formKey = GlobalKey<FormState>();
  final _bookingIdCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) => _tr(nl: nl, en: en, fr: fr, es: es);

  @override
  void dispose() {
    _bookingIdCtrl.dispose();
    _contactCtrl.dispose();
    super.dispose();
  }

  String _normalizePhone(String v) {
    final digits = StringBuffer();
    for (final ch in v.codeUnits) {
      if (ch >= 0x30 && ch <= 0x39) digits.writeCharCode(ch);
    }
    final out = digits.toString();
    if (out.length >= 7) {
      return out.substring(out.length - 7);
    }
    return out;
  }

  bool _matchesContact(CustomerBookingView view, String contact) {
    final c = contact.trim();
    if (c.isEmpty) return true;
    if (c.contains('@')) {
      final email = view.customerEmail.toLowerCase();
      return email.isNotEmpty && c.toLowerCase() == email;
    }
    final cNorm = _normalizePhone(c);
    final pNorm = _normalizePhone(view.customerPhone);
    if (cNorm.isEmpty || pNorm.isEmpty) return false;
    return pNorm.endsWith(cNorm) || cNorm.endsWith(pNorm);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final bookingId = _bookingIdCtrl.text.trim();
    final contact = _contactCtrl.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final uri = _withActiveBookingScope(
        kBookingBaseUrl,
        '/bookings/${Uri.encodeComponent(bookingId)}',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = _t(
            nl: 'Boeking niet gevonden. Controleer de referentie.',
            en: 'Booking not found. Please check your reference.',
            fr: 'Reservation introuvable. Verifiez votre reference.',
            es: 'Reserva no encontrada. Verifica tu referencia.',
          );
        });
        return;
      }
      final dynamic decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map<String, dynamic> || decoded['ok'] != true) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = _t(
            nl: 'Boeking niet gevonden. Controleer de referentie.',
            en: 'Booking not found. Please check your reference.',
            fr: 'Reservation introuvable. Verifiez votre reference.',
            es: 'Reserva no encontrada. Verifica tu referencia.',
          );
        });
        return;
      }
      final view = CustomerBookingView.fromResponse(bookingId, decoded);
      if (contact.isNotEmpty && !_matchesContact(view, contact)) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = _t(
            nl: 'Gegevens komen niet overeen met deze boeking.',
            en: 'Details do not match this booking.',
            fr: 'Les coordonnees ne correspondent pas a cette reservation.',
            es: 'Los datos no coinciden con esta reserva.',
          );
        });
        return;
      }
      final stored = StoredCustomerBooking.fromAuthoritativeResponse(
        bookingId: bookingId,
        response: decoded,
      );
      await CustomerBookingsStore.instance.upsert(
        _hydrateStoredCustomerBookingFromView(
          stored: stored,
          view: view,
          source: 'customer_lookup',
        ),
      );
      if (!mounted) return;
      setState(() => _busy = false);
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CustomerBookingDetailPage(
            bookingId: bookingId,
            initialView: view,
            startsFromLocalCache: false,
          ),
        ),
      );
    } catch (err) {
      if (!mounted) return;
      debugPrint(
        '[CUSTOMER_LOOKUP][ERROR] bookingId=${_bookingIdCtrl.text.trim()} error=$err',
      );
      setState(() {
        _busy = false;
        _error = _t(
          nl: 'Verbinding mislukt. Probeer het opnieuw.',
          en: 'Connection failed. Please try again.',
          fr: 'Connexion echouee. Veuillez reessayer.',
          es: 'Conexion fallida. Intentalo de nuevo.',
        );
      });
    }
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    String? Function(String?)? validator,
    TextInputType keyboardType = TextInputType.text,
    String? hintText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          validator: validator,
          keyboardType: keyboardType,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: const Color(0xFF141B2F),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) => Scaffold(
        backgroundColor: const Color(0xFF0B1020),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0B1020),
          title: Text(
            _t(
              nl: 'Controleer of volg je boeking',
              en: 'Check or follow your booking',
              fr: 'Verifier ou suivre votre reservation',
              es: 'Consulta o sigue tu reserva',
            ),
          ),
        ),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  _t(
                    nl: 'Vul je boekingsreferentie in om je boeking terug te vinden.',
                    en: 'Enter your booking reference to look up your booking.',
                    fr: 'Entrez votre reference pour retrouver la reservation.',
                    es: 'Introduce tu referencia para encontrar tu reserva.',
                  ),
                  style: TextStyle(color: Colors.white.withOpacity(0.78)),
                ),
                const SizedBox(height: 14),
                _field(
                  label: _t(
                    nl: 'Boekingsreferentie',
                    en: 'Booking reference',
                    fr: 'Reference de reservation',
                    es: 'Referencia de reserva',
                  ),
                  controller: _bookingIdCtrl,
                  hintText: 'bv. 2026-04-538473',
                  validator: (v) {
                    final s = (v ?? '').trim();
                    if (s.isEmpty) {
                      return _t(
                        nl: 'Voer je boekingsreferentie in',
                        en: 'Enter your booking reference',
                        fr: 'Entrez votre reference',
                        es: 'Introduce tu referencia',
                      );
                    }
                    if (s.length < 4) {
                      return _t(
                        nl: 'Referentie lijkt te kort',
                        en: 'Reference looks too short',
                        fr: 'Reference trop courte',
                        es: 'La referencia es muy corta',
                      );
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                _field(
                  label: _t(
                    nl: 'E-mail of telefoon (optioneel)',
                    en: 'Email or phone (optional)',
                    fr: 'E-mail ou telephone (optionnel)',
                    es: 'Email o telefono (opcional)',
                  ),
                  controller: _contactCtrl,
                  hintText: _t(
                    nl: 'Extra controle op je gegevens',
                    en: 'Extra check against your details',
                    fr: 'Verification supplementaire',
                    es: 'Verificacion adicional',
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.withOpacity(0.4)),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Color(0xFFFFB4B4)),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _busy ? null : _submit,
                  icon: const Icon(Icons.search),
                  label: Text(
                    _busy
                        ? _t(
                            nl: 'Zoeken...',
                            en: 'Searching...',
                            fr: 'Recherche...',
                            es: 'Buscando...',
                          )
                        : _t(
                            nl: 'Zoek mijn boeking',
                            en: 'Find my booking',
                            fr: 'Trouver ma reservation',
                            es: 'Buscar mi reserva',
                          ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE5B641),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Read-only customer-safe view extracted from the authoritative booking
/// record returned by `GET /bookings/{id}`. Driver/admin/internal fields
/// (raw tokens, vehicle assignments, internal IDs) are intentionally not
/// surfaced.
class CustomerBookingView {
  CustomerBookingView({
    required this.bookingId,
    required this.lifecycleStatus,
    required this.booking,
    required this.record,
    required this.source,
  });

  final String bookingId;
  final String lifecycleStatus;
  final Map<String, dynamic> booking;
  final Map<String, dynamic> record;
  final Map<String, dynamic> source;

  factory CustomerBookingView.fromResponse(
    String bookingId,
    Map<String, dynamic> response,
  ) {
    final mergedSource = Map<String, dynamic>.from(response);
    final rawRecord = mergedSource['record'];
    final record = (rawRecord is Map)
        ? Map<String, dynamic>.from(rawRecord)
        : <String, dynamic>{};
    final rawBooking = record['booking'];
    final booking = (rawBooking is Map)
        ? Map<String, dynamic>.from(rawBooking)
        : <String, dynamic>{};
    final rawPayload = record['payload'];
    final payload = (rawPayload is Map)
        ? Map<String, dynamic>.from(rawPayload)
        : <String, dynamic>{};
    final lifecycleRaw =
        response['status']?.toString().trim() ??
        response['stage']?.toString().trim() ??
        record['status']?.toString().trim() ??
        record['stage']?.toString().trim() ??
        booking['status']?.toString().trim() ??
        '';
    final lifecycle = _normalizeCustomerLifecycleStatus(lifecycleRaw);
    final businessPayload = _deriveCustomerBusinessInvoicePayload(
      source: <String, dynamic>{
        ...mergedSource,
        ...record,
        ...booking,
        ...payload,
      },
    );
    if (businessPayload.isNotEmpty) {
      booking.addAll(businessPayload);
      payload.addAll(businessPayload);
      record.addAll(businessPayload);
      record['booking'] = booking;
      record['payload'] = payload;
      mergedSource.addAll(businessPayload);
      mergedSource['record'] = record;
      mergedSource['booking'] = booking;
      mergedSource['payload'] = payload;
    }
    // #region agent log H1 hydrate source flags
    unawaited(
      _agentDebugLog(
        runId: 'initial',
        hypothesisId: 'H1',
        location: 'main.dart:CustomerBookingView.fromResponse',
        message: '[CUSTOMER_BOOKING][BUSINESS_PAYLOAD]',
        data: <String, dynamic>{
          'booking': _safeRefPreview(bookingId),
          'rawStatus': lifecycleRaw,
          'normalizedStatus': lifecycle,
          'service': (booking['service'] ?? booking['extra_service'] ?? '')
              .toString(),
          'businessDetected':
              (booking['business_detected'] ??
                      booking['businessDetected'] ??
                      record['business_detected'] ??
                      record['businessDetected'] ??
                      response['business_detected'] ??
                      response['businessDetected'] ??
                      '')
                  .toString(),
          'invoiceRequested':
              (booking['invoice_requested'] ??
                      booking['invoiceRequested'] ??
                      record['invoice_requested'] ??
                      record['invoiceRequested'] ??
                      response['invoice_requested'] ??
                      response['invoiceRequested'] ??
                      '')
                  .toString(),
          'companyName':
              (booking['company_name'] ??
                      booking['companyName'] ??
                      response['company_name'] ??
                      response['companyName'] ??
                      '')
                  .toString(),
          'vatNumber':
              (booking['vat_number'] ??
                      booking['vatNumber'] ??
                      response['vat_number'] ??
                      response['vatNumber'] ??
                      '')
                  .toString(),
          'invoiceEmail':
              (booking['invoice_email'] ??
                      booking['invoiceEmail'] ??
                      response['invoice_email'] ??
                      response['invoiceEmail'] ??
                      '')
                  .toString(),
          'derivedBusiness': (businessPayload['business_detected'] ?? '')
              .toString(),
          'derivedInvoiceRequested':
              (businessPayload['invoice_requested'] ?? '').toString(),
          'derivedCompanyName': (businessPayload['company_name'] ?? '')
              .toString(),
          'derivedVatNumber': (businessPayload['vat_number'] ?? '').toString(),
          'derivedInvoiceEmail': (businessPayload['invoice_email'] ?? '')
              .toString(),
        },
      ),
    );
    // #endregion
    return CustomerBookingView(
      bookingId: bookingId,
      lifecycleStatus: lifecycle,
      booking: booking,
      record: record,
      source: mergedSource,
    );
  }

  factory CustomerBookingView.fromStored(StoredCustomerBooking stored) {
    final booking = <String, dynamic>{
      'from': stored.from,
      'to': stored.to,
      'pickup_iso': stored.pickupIso,
      'customer_name': stored.customerName,
      'customer_phone': stored.customerPhone,
      'customer_email': stored.customerEmail,
      'price_incl_vat': stored.price,
      'currency': stored.currency,
      'service': stored.service,
      'tier': stored.tier,
      'pax': stored.pax,
      'bags': stored.bags,
      'payment_status': stored.paymentStatus,
      'company_name': stored.companyName,
      'vat_number': stored.vatNumber,
      'invoice_email': stored.invoiceEmail,
      'invoice_address': stored.invoiceAddress,
      'business_customer': stored.businessDetected,
      'invoice_requested': stored.invoiceRequested,
      'quote': stored.quote,
    };
    final businessPayload = _deriveCustomerBusinessInvoicePayload(
      source: <String, dynamic>{
        ...booking,
        'business_detected': stored.businessDetected,
        'businessDetected': stored.businessDetected,
        'invoice_requested': stored.invoiceRequested,
        'invoiceRequested': stored.invoiceRequested,
      },
    );
    booking.addAll(businessPayload);
    final record = <String, dynamic>{
      'status': stored.status,
      'payment_status': stored.paymentStatus,
      'booking': booking,
      'payload': <String, dynamic>{
        'from': stored.from,
        'to': stored.to,
        'pickup_iso': stored.pickupIso,
        'service': stored.service,
        'tier': stored.tier,
        'pax': stored.pax,
        'bags': stored.bags,
        ...businessPayload,
      },
      ...businessPayload,
    };
    final source = <String, dynamic>{
      'record': record,
      'booking': booking,
      'quote': stored.quote,
      'payload': record['payload'],
      ...businessPayload,
    };
    return CustomerBookingView(
      bookingId: stored.canonicalBookingId,
      lifecycleStatus: stored.status.toUpperCase(),
      booking: booking,
      record: record,
      source: source,
    );
  }

  bool _isMeaningful(String value) {
    final s = value.trim().toLowerCase();
    if (s.isEmpty) return false;
    if (s == '-' || s == 'null' || s == 'undefined') return false;
    return true;
  }

  String _firstNonEmpty(List<dynamic> values) {
    for (final v in values) {
      if (v == null) continue;
      final s = v.toString().trim();
      if (_isMeaningful(s)) return s;
    }
    return '';
  }

  dynamic _valueAtPath(String path) {
    dynamic current = source;
    for (final segment in path.split('.')) {
      if (current is Map && current.containsKey(segment)) {
        current = current[segment];
      } else {
        return null;
      }
    }
    return current;
  }

  String _firstPathValue(List<String> paths) {
    for (final path in paths) {
      final raw = _valueAtPath(path);
      final s = raw?.toString().trim() ?? '';
      if (_isMeaningful(s)) return s;
    }
    return '';
  }

  double? _firstPathNum(List<String> paths) {
    for (final path in paths) {
      final raw = _valueAtPath(path);
      if (raw is num) return raw.toDouble();
      final s = raw?.toString().trim() ?? '';
      if (!_isMeaningful(s)) continue;
      final parsed = double.tryParse(s.replaceAll(',', '.'));
      if (parsed != null) return parsed;
    }
    return null;
  }

  double? _sumQuoteLegMetric({
    required List<String> listPaths,
    required List<String> keyCandidates,
  }) {
    for (final path in listPaths) {
      final raw = _valueAtPath(path);
      if (raw is! List || raw.isEmpty) continue;
      var sum = 0.0;
      var found = false;
      for (final item in raw) {
        if (item is! Map) continue;
        for (final key in keyCandidates) {
          final value = item[key];
          if (value is num) {
            sum += value.toDouble();
            found = true;
            break;
          }
          final text = value?.toString().trim() ?? '';
          if (!_isMeaningful(text)) continue;
          final parsed = double.tryParse(text.replaceAll(',', '.'));
          if (parsed != null) {
            sum += parsed;
            found = true;
            break;
          }
        }
      }
      if (found) return sum;
    }
    return null;
  }

  String _quoteLegEndpointLabel({required bool fromField}) {
    final candidates = <dynamic>[
      _valueAtPath('quote.legs'),
      _valueAtPath('record.quote.legs'),
    ];
    for (final raw in candidates) {
      if (raw is! List || raw.isEmpty) continue;
      final edge = fromField ? raw.first : raw.last;
      if (edge is! Map) continue;
      final label = fromField
          ? _firstNonEmpty([
              edge['from'],
              edge['origin'],
              edge['start'],
              edge['start_address'],
              edge['startAddress'],
            ])
          : _firstNonEmpty([
              edge['to'],
              edge['destination'],
              edge['end'],
              edge['end_address'],
              edge['endAddress'],
            ]);
      if (_isMeaningful(label)) return label;
    }
    return '';
  }

  bool _toBool(dynamic value) {
    if (value is bool) return value;
    final text = value?.toString().trim().toLowerCase() ?? '';
    return text == 'true' || text == '1' || text == 'yes' || text == 'ja';
  }

  bool _firstPathBool(List<String> paths) {
    for (final path in paths) {
      final raw = _valueAtPath(path);
      if (raw == null) continue;
      return _toBool(raw);
    }
    return false;
  }

  String _preferNonEmptyText(String authoritative, String localFallback) {
    if (_isMeaningful(authoritative)) return authoritative;
    if (_isMeaningful(localFallback)) return localFallback;
    return '';
  }

  CustomerBookingView mergedWithExisting(CustomerBookingView existing) {
    final mergedBooking = <String, dynamic>{...existing.booking, ...booking};
    final mergedRecord = <String, dynamic>{...existing.record, ...record};
    final mergedSource = <String, dynamic>{...existing.source, ...source};

    final mergedFrom = _preferNonEmptyText(fromAddress, existing.fromAddress);
    final mergedTo = _preferNonEmptyText(toAddress, existing.toAddress);
    final mergedPickupIso = _preferNonEmptyText(pickupIso, existing.pickupIso);
    final mergedName = _preferNonEmptyText(customerName, existing.customerName);
    final mergedPhone = _preferNonEmptyText(
      customerPhone,
      existing.customerPhone,
    );
    final mergedEmail = _preferNonEmptyText(
      customerEmail,
      existing.customerEmail,
    );
    final mergedService = _preferNonEmptyText(service, existing.service);
    final mergedTier = _preferNonEmptyText(tier, existing.tier);
    final mergedPax = _preferNonEmptyText(pax, existing.pax);
    final mergedBags = _preferNonEmptyText(bags, existing.bags);
    final mergedCurrency = _preferNonEmptyText(currency, existing.currency);
    final mergedPaymentStatus = _preferNonEmptyText(
      rawPaymentStatus,
      existing.rawPaymentStatus,
    );
    final mergedLifecycleStatus = _preferNonEmptyText(
      lifecycleStatus,
      existing.lifecycleStatus,
    );
    final mergedPrice = totalAmount ?? existing.totalAmount;

    if (_isMeaningful(mergedFrom)) {
      mergedSource['from'] = mergedFrom;
      mergedBooking['from'] = mergedFrom;
      mergedRecord['from'] = mergedFrom;
    }
    if (_isMeaningful(mergedTo)) {
      mergedSource['to'] = mergedTo;
      mergedBooking['to'] = mergedTo;
      mergedRecord['to'] = mergedTo;
    }
    if (_isMeaningful(mergedPickupIso)) {
      mergedBooking['pickup_iso'] = mergedPickupIso;
      mergedRecord['pickup_iso'] = mergedPickupIso;
    }
    if (_isMeaningful(mergedName)) mergedBooking['customer_name'] = mergedName;
    if (_isMeaningful(mergedPhone))
      mergedBooking['customer_phone'] = mergedPhone;
    if (_isMeaningful(mergedEmail))
      mergedBooking['customer_email'] = mergedEmail;
    if (_isMeaningful(mergedService)) mergedBooking['service'] = mergedService;
    if (_isMeaningful(mergedTier)) mergedBooking['tier'] = mergedTier;
    if (_isMeaningful(mergedPax)) mergedBooking['pax'] = mergedPax;
    if (_isMeaningful(mergedBags)) mergedBooking['bags'] = mergedBags;
    if (_isMeaningful(mergedCurrency))
      mergedBooking['currency'] = mergedCurrency;
    if (_isMeaningful(mergedPaymentStatus)) {
      mergedBooking['payment_status'] = mergedPaymentStatus;
      mergedRecord['payment_status'] = mergedPaymentStatus;
    }
    if (_isMeaningful(mergedLifecycleStatus)) {
      mergedRecord['status'] = mergedLifecycleStatus;
    }
    if (mergedPrice != null) {
      mergedBooking['price_incl_vat'] = mergedPrice;
      mergedRecord['amount'] = mergedPrice;
      mergedSource['price_incl_vat'] = mergedPrice;
    }

    mergedRecord['booking'] = mergedBooking;
    mergedSource['record'] = mergedRecord;
    mergedSource['booking'] = mergedBooking;

    return CustomerBookingView(
      bookingId: _preferNonEmptyText(bookingId, existing.bookingId),
      lifecycleStatus: mergedLifecycleStatus,
      booking: mergedBooking,
      record: mergedRecord,
      source: mergedSource,
    );
  }

  String get fromAddress => _firstNonEmpty([
    _firstPathValue(const <String>[
      'from',
      'pickup',
      'pickup_address',
      'pickupAddress',
      'origin',
      'booking.from',
      'booking.pickup',
      'booking.pickup_address',
      'booking.pickupAddress',
      'record.from',
      'record.booking.from',
      'record.booking.pickup',
      'record.booking.pickup_address',
      'record.booking_details.from',
      'record.booking_details.pickup_address',
      'record.quote.from',
      'data.record.booking.from',
      'data.record.booking_details.from',
      'payload.from',
      'payload.pickup_address',
      'quote.from',
      'quote.inputs.from',
    ]),
    _quoteLegEndpointLabel(fromField: true),
  ]);
  String get toAddress => _firstNonEmpty([
    _firstPathValue(const <String>[
      'to',
      'destination',
      'destination_address',
      'destinationAddress',
      'dropoff',
      'dropoff_address',
      'booking.to',
      'booking.destination',
      'booking.destination_address',
      'record.to',
      'record.booking.to',
      'record.booking.destination',
      'record.booking.destination_address',
      'record.booking_details.to',
      'record.booking_details.destination_address',
      'record.quote.to',
      'data.record.booking.to',
      'data.record.booking_details.to',
      'payload.to',
      'payload.destination_address',
      'quote.to',
      'quote.inputs.to',
    ]),
    _quoteLegEndpointLabel(fromField: false),
  ]);
  String get pickupIso => _firstNonEmpty([
    _firstPathValue(const <String>[
      'pickup_iso',
      'record.pickup_iso',
      'record.booking.pickup_iso',
      'record.booking.pickupStartIso',
      'record.quote.pickup_iso',
      'quote.pickup_iso',
    ]),
    booking['pickupStartIso'],
    booking['pickup_iso'],
    booking['pickup_at'],
    booking['pickupAt'],
    record['pickup_iso'],
  ]);
  String get customerName => _firstNonEmpty([
    booking['customer_name'],
    booking['name'],
    record['customer_name'],
  ]);
  String get customerPhone => _firstNonEmpty([
    booking['customer_phone'],
    booking['phone'],
    booking['customer_phone_e164'],
  ]);
  String get customerEmail => _firstNonEmpty([
    booking['customer_email'],
    booking['email'],
  ]).toLowerCase();
  String get service => _firstNonEmpty([
    _firstPathValue(const <String>[
      'service',
      'extra_service',
      'extra_service_key',
      'booking.service',
      'booking.extra_service',
      'record.booking.service',
      'record.booking.extra_service',
      'payload.service',
      'quote.inputs.service',
    ]),
  ]);
  String get tier => _firstNonEmpty([
    _firstPathValue(const <String>[
      'tier',
      'booking.tier',
      'record.booking.tier',
      'record.booking_details.tier',
      'payload.tier',
      'quote.inputs.tier',
    ]),
  ]);
  String get pax => _firstNonEmpty([
    _firstPathValue(const <String>[
      'pax',
      'passengers',
      'booking.pax',
      'booking.passengers',
      'record.booking.pax',
      'record.booking_details.pax',
      'payload.pax',
      'quote.inputs.pax',
    ]),
  ]);
  String get bags => _firstNonEmpty([
    _firstPathValue(const <String>[
      'bags',
      'booking.bags',
      'record.booking.bags',
      'record.booking_details.bags',
      'payload.bags',
      'quote.inputs.bags',
    ]),
  ]);
  String get currency => _firstNonEmpty([
    _firstPathValue(const <String>[
      'currency',
      'booking.currency',
      'record.currency',
      'record.booking.currency',
      'record.booking_details.currency',
      'quote.currency',
      'payload.currency',
    ]),
    'EUR',
  ]);
  double? get totalAmount {
    return _firstPathNum(const <String>[
      'price',
      'total',
      'amount',
      'final_total',
      'total_price',
      'price_incl_vat',
      'priceInclVat',
      'booking.price',
      'booking.total',
      'booking.amount',
      'booking.final_total',
      'booking.total_price',
      'booking.price_incl_vat',
      'record.price',
      'record.total',
      'record.amount',
      'record.final_total',
      'record.total_price',
      'record.price_incl_vat',
      'record.booking.price',
      'record.booking.total',
      'record.booking.amount',
      'record.booking.final_total',
      'record.booking.total_price',
      'record.booking_details.price',
      'record.booking_details.total',
      'record.booking_details.amount',
      'record.booking_details.final_total',
      'record.booking_details.total_price',
      'record.booking_details.price_incl_vat',
      'record.quote.price',
      'record.quote.total_price',
      'record.quote.total',
      'record.quote.price_incl_vat',
      'record.quote.pricing.price_incl_vat',
      'record.quote.pricing_main.price_incl_vat',
      'record.quote.pricing_main.breakdown.total_incl',
      'quote.price_incl_vat',
      'quote.priceInclVat',
      'quote.total_price',
      'quote.total',
      'quote.pricing.price_incl_vat',
      'quote.pricing_main.price_incl_vat',
      'quote.pricing_main.breakdown.total_incl',
      'payload.price',
      'payload.total',
      'payload.amount',
      'payload.final_total',
      'payload.total_price',
      'payload.price_incl_vat',
      'payload.quote.price_incl_vat',
    ]);
  }

  double? get distanceKm {
    return _firstPathNum(const <String>[
          'distance_km',
          'record.distance_km',
          'record.quote.distance_km',
          'quote.distance_km',
        ]) ??
        _sumQuoteLegMetric(
          listPaths: const <String>['quote.legs', 'record.quote.legs'],
          keyCandidates: const <String>['distance_km', 'km', 'distance'],
        );
  }

  double? get durationMin {
    return _firstPathNum(const <String>[
          'duration_min',
          'record.duration_min',
          'record.booking.duration_route_min',
          'record.quote.duration_min',
          'quote.duration_min',
        ]) ??
        _sumQuoteLegMetric(
          listPaths: const <String>['quote.legs', 'record.quote.legs'],
          keyCandidates: const <String>['duration_min', 'minutes', 'duration'],
        );
  }

  String get companyName => _firstNonEmpty([
    _firstPathValue(const <String>[
      'company_name',
      'companyName',
      'customer_company',
      'customerCompany',
      'booking.company_name',
      'booking.companyName',
      'record.company_name',
      'record.companyName',
      'record.booking.company_name',
      'record.booking.companyName',
      'record.booking_details.company_name',
      'record.booking_details.companyName',
      'payload.company_name',
      'payload.companyName',
      'payload.booking.company_name',
      'payload.booking.companyName',
    ]),
    booking['company_name'],
    booking['companyName'],
    booking['company'],
  ]);
  String get vatNumber => _firstNonEmpty([
    _firstPathValue(const <String>[
      'vat_number',
      'vatNumber',
      'customer_vat',
      'customerVat',
      'booking.vat_number',
      'booking.vatNumber',
      'record.vat_number',
      'record.vatNumber',
      'record.booking.vat_number',
      'record.booking.vatNumber',
      'record.booking_details.vat_number',
      'record.booking_details.vatNumber',
      'payload.vat_number',
      'payload.vatNumber',
      'payload.booking.vat_number',
      'payload.booking.vatNumber',
    ]),
    booking['vat_number'],
    booking['vatNumber'],
    booking['vat'],
  ]);
  bool get invoiceRequested => _firstPathBool(const <String>[
    'invoice_requested',
    'invoiceRequested',
    'booking.invoice_requested',
    'booking.invoiceRequested',
    'record.invoice_requested',
    'record.invoiceRequested',
    'record.booking.invoice_requested',
    'record.booking.invoiceRequested',
    'record.booking_details.invoice_requested',
    'record.booking_details.invoiceRequested',
    'payload.invoice_requested',
    'payload.invoiceRequested',
    'payload.booking.invoice_requested',
    'payload.booking.invoiceRequested',
  ]);
  String get invoiceEmail => _firstNonEmpty([
    _firstPathValue(const <String>[
      'invoice_email',
      'invoiceEmail',
      'booking.invoice_email',
      'booking.invoiceEmail',
      'record.invoice_email',
      'record.invoiceEmail',
      'record.booking.invoice_email',
      'record.booking.invoiceEmail',
      'record.booking_details.invoice_email',
      'record.booking_details.invoiceEmail',
    ]),
  ]);
  String get invoiceAddress => _firstNonEmpty([
    _firstPathValue(const <String>[
      'invoice_address',
      'invoiceAddress',
      'billing_address',
      'billingAddress',
      'company_address',
      'companyAddress',
      'booking.invoice_address',
      'booking.invoiceAddress',
      'booking.billing_address',
      'booking.billingAddress',
      'booking.company_address',
      'booking.companyAddress',
      'record.invoice_address',
      'record.invoiceAddress',
      'record.billing_address',
      'record.billingAddress',
      'record.company_address',
      'record.companyAddress',
      'record.booking.invoice_address',
      'record.booking.invoiceAddress',
      'record.booking.billing_address',
      'record.booking.billingAddress',
      'record.booking.company_address',
      'record.booking.companyAddress',
    ]),
  ]);
  String get invoiceUrl => _firstNonEmpty([
    _firstPathValue(const <String>[
      'invoice_url',
      'invoiceUrl',
      'invoice_pdf_url',
      'invoicePdfUrl',
      'invoice_download_url',
      'invoiceDownloadUrl',
      'booking.invoice_url',
      'booking.invoiceUrl',
      'booking.invoice_pdf_url',
      'booking.invoicePdfUrl',
      'booking.invoice_download_url',
      'booking.invoiceDownloadUrl',
      'record.invoice_url',
      'record.invoiceUrl',
      'record.invoice_pdf_url',
      'record.invoicePdfUrl',
      'record.invoice_download_url',
      'record.invoiceDownloadUrl',
      'record.booking.invoice_url',
      'record.booking.invoiceUrl',
      'record.booking.invoice_pdf_url',
      'record.booking.invoicePdfUrl',
      'record.booking.invoice_download_url',
      'record.booking.invoiceDownloadUrl',
    ]),
  ]);
  bool get invoiceEmailAvailable => _firstPathBool(const <String>[
    'invoice_email_available',
    'invoiceEmailAvailable',
    'booking.invoice_email_available',
    'booking.invoiceEmailAvailable',
    'record.invoice_email_available',
    'record.invoiceEmailAvailable',
    'record.booking.invoice_email_available',
    'record.booking.invoiceEmailAvailable',
  ]);
  bool get businessCustomer {
    final hasVat = vatNumber.isNotEmpty;
    if (!hasVat) return false;
    if (invoiceRequested) return true;
    return _firstPathBool(const <String>[
      'business_customer',
      'businessCustomer',
      'is_business',
      'isBusiness',
      'business_detected',
      'businessDetected',
      'booking.business_customer',
      'booking.businessCustomer',
      'booking.is_business',
      'booking.isBusiness',
      'booking.business_detected',
      'booking.businessDetected',
      'record.business_customer',
      'record.businessCustomer',
      'record.is_business',
      'record.isBusiness',
      'record.business_detected',
      'record.businessDetected',
      'record.booking.business_customer',
      'record.booking.businessCustomer',
      'record.booking.is_business',
      'record.booking.isBusiness',
      'record.booking.business_detected',
      'record.booking.businessDetected',
      'record.booking_details.business_customer',
      'record.booking_details.businessCustomer',
      'record.booking_details.is_business',
      'record.booking_details.isBusiness',
      'payload.business_customer',
      'payload.businessCustomer',
      'payload.is_business',
      'payload.isBusiness',
      'payload.business_detected',
      'payload.businessDetected',
    ]);
  }

  String get rawPaymentStatus {
    final candidates = <dynamic>[
      record['payment_status'],
      record['paymentStatus'],
      booking['payment_status'],
      booking['paymentStatus'],
      _firstPathValue(const <String>[
        'payment_status',
        'paymentStatus',
        'record.booking.payment_status',
        'record.booking.paymentStatus',
        'record.booking_details.payment_status',
        'record.booking_details.paymentStatus',
      ]),
    ];
    for (final v in candidates) {
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s.toLowerCase();
    }
    return '';
  }

  String get paymentMethod {
    return _firstNonEmpty([
      _firstPathValue(const <String>[
        'payment_method',
        'paymentMethod',
        'booking.payment_method',
        'booking.paymentMethod',
        'record.payment_method',
        'record.paymentMethod',
        'record.booking.payment_method',
        'record.booking.paymentMethod',
        'record.booking_details.payment_method',
        'record.booking_details.paymentMethod',
      ]),
    ]).toLowerCase();
  }

  String get receiptReference => _firstPathValue(const <String>[
    'receipt_reference',
    'receiptReference',
    'booking.receipt_reference',
    'booking.receiptReference',
    'record.receipt_reference',
    'record.receiptReference',
    'record.booking.receipt_reference',
    'record.booking.receiptReference',
    'record.references.receipt_reference',
    'record.references.receiptReference',
    'payload.receipt_reference',
    'payload.receiptReference',
    'payload.booking.receipt_reference',
    'payload.booking.receiptReference',
    'payload.references.receipt_reference',
    'payload.references.receiptReference',
  ]);

  String get planningReference => _firstPathValue(const <String>[
    'planning_reference',
    'planningReference',
    'booking.planning_reference',
    'booking.planningReference',
    'record.planning_reference',
    'record.planningReference',
    'record.booking.planning_reference',
    'record.booking.planningReference',
    'record.references.planning_reference',
    'record.references.planningReference',
    'payload.planning_reference',
    'payload.planningReference',
    'payload.booking.planning_reference',
    'payload.booking.planningReference',
    'payload.references.planning_reference',
    'payload.references.planningReference',
  ]);

  String get publicBookingReference => _firstPathValue(const <String>[
    'public_booking_reference',
    'publicBookingReference',
    'booking_reference',
    'bookingReference',
    'public_reference',
    'publicReference',
    'booking.public_booking_reference',
    'booking.publicBookingReference',
    'booking.booking_reference',
    'booking.bookingReference',
    'booking.public_reference',
    'booking.publicReference',
    'record.public_booking_reference',
    'record.publicBookingReference',
    'record.booking_reference',
    'record.bookingReference',
    'record.public_reference',
    'record.publicReference',
    'record.booking.public_booking_reference',
    'record.booking.publicBookingReference',
    'record.booking.booking_reference',
    'record.booking.bookingReference',
    'record.booking.public_reference',
    'record.booking.publicReference',
    'record.references.public_booking_reference',
    'record.references.publicBookingReference',
    'record.references.booking_reference',
    'record.references.bookingReference',
    'record.references.public_reference',
    'record.references.publicReference',
    'payload.public_booking_reference',
    'payload.publicBookingReference',
    'payload.booking_reference',
    'payload.bookingReference',
    'payload.public_reference',
    'payload.publicReference',
    'payload.booking.public_booking_reference',
    'payload.booking.publicBookingReference',
    'payload.booking.booking_reference',
    'payload.booking.bookingReference',
    'payload.booking.public_reference',
    'payload.booking.publicReference',
    'payload.references.public_booking_reference',
    'payload.references.publicBookingReference',
    'payload.references.booking_reference',
    'payload.references.bookingReference',
    'payload.references.public_reference',
    'payload.references.publicReference',
  ]);

  String get internalBookingId => _firstNonEmpty([
    bookingId,
    _firstPathValue(const <String>[
      'booking_id',
      'bookingId',
      'id',
      'booking.booking_id',
      'booking.bookingId',
      'record.booking_id',
      'record.bookingId',
      'record.booking.booking_id',
      'record.booking.bookingId',
      'payload.booking_id',
      'payload.bookingId',
      'payload.booking.booking_id',
      'payload.booking.bookingId',
    ]),
  ]);

  bool get _methodImpliesPaid {
    const inCarPaidMethods = <String>{'cash', 'bancontact', 'qr', 'card'};
    return inCarPaidMethods.contains(paymentMethod);
  }

  bool get isPaid {
    final s = rawPaymentStatus;
    return s == 'paid' ||
        s == 'confirmed' ||
        s == 'completed' ||
        s == 'success' ||
        _methodImpliesPaid;
  }

  String get extraOptions {
    final direct = _firstPathValue(const <String>[
      'extras',
      'extra_service',
      'extra_service_key',
      'premium_options',
      'selected_options',
      'booking.extras',
      'booking.extra_service',
      'booking.extra_service_key',
      'booking.premium_options',
      'booking.selected_options',
      'record.booking.extras',
      'record.booking.extra_service',
      'record.booking.extra_service_key',
      'record.booking.premium_options',
      'record.booking.selected_options',
      'payload.extras',
      'payload.extra_service',
      'payload.extra_service_key',
      'payload.premium_options',
      'payload.selected_options',
      'quote.inputs.extras',
      'quote.inputs.extra_service',
      'quote.inputs.extra_service_key',
    ]);
    if (direct.isNotEmpty) return direct;

    String normalizeList(dynamic raw) {
      if (raw is! List) return '';
      final values = raw
          .map((e) => e?.toString().trim() ?? '')
          .where((e) => _isMeaningful(e))
          .toList(growable: false);
      if (values.isEmpty) return '';
      return values.join(', ');
    }

    final listValue = normalizeList(_valueAtPath('extras'));
    if (listValue.isNotEmpty) return listValue;
    final bookingListValue = normalizeList(_valueAtPath('booking.extras'));
    if (bookingListValue.isNotEmpty) return bookingListValue;
    final payloadListValue = normalizeList(_valueAtPath('payload.extras'));
    if (payloadListValue.isNotEmpty) return payloadListValue;
    return '';
  }
}

/// Customer-facing booking detail screen. Read-only; pull-to-refresh re-fetches
/// the same `GET /bookings/{id}` endpoint. Does not expose driver/admin data
/// or modify any backend state.
class CustomerBookingDetailPage extends StatefulWidget {
  const CustomerBookingDetailPage({
    super.key,
    required this.bookingId,
    required this.initialView,
    this.startsFromLocalCache = false,
  });

  final String bookingId;
  final CustomerBookingView initialView;
  final bool startsFromLocalCache;

  @override
  State<CustomerBookingDetailPage> createState() =>
      _CustomerBookingDetailPageState();
}

class _CustomerBookingDetailPageState extends State<CustomerBookingDetailPage> {
  late CustomerBookingView _view = widget.initialView;
  bool _refreshing = false;
  bool _cancelling = false;
  String? _refreshError;
  late bool _usingLocalCache = widget.startsFromLocalCache;

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) => _tr(nl: nl, en: en, fr: fr, es: es);

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      _refreshError = null;
    });
    try {
      final uri = _withActiveBookingScope(
        kBookingBaseUrl,
        '/bookings/${Uri.encodeComponent(widget.bookingId)}',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final dynamic decoded = jsonDecode(utf8.decode(res.bodyBytes));
        if (decoded is Map<String, dynamic> && decoded['ok'] == true) {
          final authoritativeView = CustomerBookingView.fromResponse(
            widget.bookingId,
            decoded,
          );
          final sourceTag = (authoritativeView.record['quote'] is Map)
              ? 'record.quote'
              : ((authoritativeView.source['quote'] is Map)
                    ? 'quote'
                    : 'record.booking');
          debugPrint(
            '[BOOKING_DETAIL][HYDRATE] fromFound=${authoritativeView.fromAddress.trim().isNotEmpty} toFound=${authoritativeView.toAddress.trim().isNotEmpty} priceFound=${authoritativeView.totalAmount != null} source=$sourceTag',
          );
          final view = authoritativeView.mergedWithExisting(_view);
          final localFallback = StoredCustomerBooking(
            bookingId: _view.bookingId,
            publicBookingId: _view.bookingId,
            customerName: _view.customerName,
            customerPhone: _view.customerPhone,
            customerEmail: _view.customerEmail,
            from: _view.fromAddress,
            to: _view.toAddress,
            pickupIso: _view.pickupIso,
            price: _view.totalAmount,
            currency: _view.currency,
            service: _view.service,
            tier: _view.tier,
            pax: _view.pax,
            bags: _view.bags,
            paymentStatus: _view.rawPaymentStatus,
            status: _view.lifecycleStatus,
            createdAt: DateTime.now().toIso8601String(),
            updatedAt: DateTime.now().toIso8601String(),
          );
          final stored = StoredCustomerBooking.fromAuthoritativeResponse(
            bookingId: widget.bookingId,
            response: decoded,
            fallback: localFallback,
          );
          await CustomerBookingsStore.instance.upsert(
            _hydrateStoredCustomerBookingFromView(
              stored: stored,
              view: view,
              source: 'customer_detail_refresh',
            ),
          );
          if (!mounted) return;
          setState(() {
            _view = view;
            _usingLocalCache = false;
            _refreshing = false;
          });
          return;
        }
      }
      if (!mounted) return;
      setState(() {
        _refreshing = false;
        _usingLocalCache = true;
        _refreshError = _t(
          nl: 'Vernieuwen mislukt.',
          en: 'Refresh failed.',
          fr: "Echec de l'actualisation.",
          es: 'Error al actualizar.',
        );
      });
    } catch (err) {
      if (!mounted) return;
      debugPrint(
        '[CUSTOMER_DETAIL][REFRESH_ERROR] bookingId=${widget.bookingId} error=$err',
      );
      setState(() {
        _refreshing = false;
        _usingLocalCache = true;
        _refreshError = _t(
          nl: 'Verbinding mislukt. Probeer het opnieuw.',
          en: 'Connection failed. Please try again.',
          fr: 'Connexion echouee. Veuillez reessayer.',
          es: 'Conexion fallida. Intentalo de nuevo.',
        );
      });
    }
  }

  String _formatPickup(String iso) {
    if (iso.isEmpty) return '-';
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    final local = parsed.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
  }

  String _formatPrice(double? amount, String currency) {
    if (amount == null) return '-';
    final cur = currency.toUpperCase();
    final symbol = cur.isEmpty || cur == 'EUR' ? '€' : '$cur ';
    final formatted = amount.toStringAsFixed(2).replaceAll('.', ',');
    return '$symbol$formatted';
  }

  String _notFilled() => _t(
    nl: 'Nog niet ingevuld',
    en: 'Not filled in yet',
    fr: 'Pas encore renseigne',
    es: 'Aún no completado',
  );

  ({String label, String value, String? internalSecondary})
  _customerBookingReferenceDisplay(CustomerBookingView view) {
    final publicRef = view.publicBookingReference.trim();
    final planningRef = view.planningReference.trim();
    final receiptRef = view.receiptReference.trim();
    final internalRef = view.internalBookingId.trim();

    final selectedValue = publicRef.isNotEmpty
        ? publicRef
        : (receiptRef.isNotEmpty
              ? receiptRef
              : (planningRef.isNotEmpty
                    ? planningRef
                    : (internalRef.isNotEmpty ? internalRef : '-')));
    final selectedLabel = publicRef.isNotEmpty
        ? _t(
            nl: 'Boekingsnummer',
            en: 'Booking no.',
            fr: 'N° de réservation',
            es: 'N.º de reserva',
          )
        : (receiptRef.isNotEmpty
              ? _t(
                  nl: 'Bonnummer',
                  en: 'Receipt no.',
                  fr: 'N° de reçu',
                  es: 'N.º de recibo',
                )
              : (planningRef.isNotEmpty
                    ? _t(
                        nl: 'Planningnummer',
                        en: 'Planning no.',
                        fr: 'N° de planning',
                        es: 'N.º de planificación',
                      )
                    : _t(
                        nl: 'Interne boeking',
                        en: 'Internal booking',
                        fr: 'Réservation interne',
                        es: 'Reserva interna',
                      )));
    final internalSecondary =
        internalRef.isNotEmpty && internalRef != selectedValue
        ? internalRef
        : null;

    debugPrint(
      '[CUSTOMER_BOOKING][REF_SELECTED] booking=${_safeRefPreview(internalRef)} public=$publicRef planning=$planningRef receipt=$receiptRef selected=$selectedValue',
    );
    return (
      label: selectedLabel,
      value: selectedValue,
      internalSecondary: internalSecondary,
    );
  }

  Future<void> _openExternalUrl(BuildContext context, String rawUrl) async {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Kon link niet openen.',
              en: 'Could not open link.',
              fr: "Impossible d'ouvrir le lien.",
              es: 'No se pudo abrir el enlace.',
            ),
          ),
        ),
      );
    }
  }

  _TripHistoryItem _asTripHistoryItem() {
    final publicRef = _view.publicBookingReference.trim();
    final planningRef = _view.planningReference.trim();
    final receiptRef = _view.receiptReference.trim();
    final refs = <String, dynamic>{};
    void setRef(String key, String value) {
      if (value.isEmpty) return;
      refs[key] = value;
    }

    setRef('public_booking_reference', publicRef);
    setRef('publicBookingReference', publicRef);
    setRef('booking_reference', publicRef);
    setRef('bookingReference', publicRef);
    setRef('public_reference', publicRef);
    setRef('publicReference', publicRef);
    setRef('planning_reference', planningRef);
    setRef('planningReference', planningRef);
    setRef('receipt_reference', receiptRef);
    setRef('receiptReference', receiptRef);

    final bookingDetails = <String, dynamic>{
      ..._view.source,
      'booking_id': _view.bookingId,
      'bookingId': _view.bookingId,
      ...refs,
      'customer_name': _view.customerName,
      'customer_phone': _view.customerPhone,
      'customer_email': _view.customerEmail,
      'from': _view.fromAddress,
      'to': _view.toAddress,
      'service_type': _view.service,
      'tier': _view.tier,
      'passengers': _view.pax,
      'luggage_count': _view.bags,
      'distance_km': _view.distanceKm,
      'duration_min': _view.durationMin,
      'booking_total_eur': _view.totalAmount,
      'currency': _view.currency,
      'payment_status': _view.rawPaymentStatus,
      'payment_method': _view.paymentMethod,
      'company_name': _view.companyName,
      'vat_number': _view.vatNumber,
      'invoice_email': _view.invoiceEmail,
      'invoice_address': _view.invoiceAddress,
      'extras': _view.extraOptions,
      'scheduled_pickup_at': _view.pickupIso,
      'references': refs,
      'booking': <String, dynamic>{
        ...refs,
        'booking_id': _view.bookingId,
        'bookingId': _view.bookingId,
        'customer_name': _view.customerName,
        'customer_phone': _view.customerPhone,
        'customer_email': _view.customerEmail,
        'from': _view.fromAddress,
        'to': _view.toAddress,
        'service_type': _view.service,
        'tier': _view.tier,
        'payment_status': _view.rawPaymentStatus,
      },
    };

    return _TripHistoryItem.fromJson(<String, dynamic>{
      'trip_id': _view.bookingId,
      'booking_id': _view.bookingId,
      'kind': 'planned',
      'status': _view.lifecycleStatus,
      'started_at': _view.pickupIso,
      'stopped_at': _view.pickupIso,
      'origin': _view.fromAddress,
      'destination': _view.toAddress,
      'wait_seconds_total': 0,
      'total_eur': _view.totalAmount,
      'currency': _view.currency,
      'booking_details': bookingDetails,
    });
  }

  Future<void> _openReceiptAction(
    BuildContext context,
    _ReceiptQuickAction action,
  ) async {
    final item = _asTripHistoryItem();
    switch (action) {
      case _ReceiptQuickAction.viewPdf:
        await _ReceiptPdfActionRunner.previewPdf(context: context, item: item);
        break;
      case _ReceiptQuickAction.sharePdf:
        await _ReceiptPdfActionRunner.sharePdf(context: context, item: item);
        break;
      case _ReceiptQuickAction.whatsappPdf:
        await _ReceiptPdfActionRunner.sharePdfViaWhatsApp(
          context: context,
          item: item,
        );
        break;
      case _ReceiptQuickAction.emailPdf:
        await _ReceiptPdfActionRunner.sharePdfViaEmail(
          context: context,
          item: item,
        );
        break;
      case _ReceiptQuickAction.printPdf:
        await _ReceiptPdfActionRunner.printPdf(context: context, item: item);
        break;
    }
  }

  Future<void> _removeFromMyBookings() async {
    final bookingId = widget.bookingId.trim();
    if (bookingId.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          _t(
            nl: 'Boeking verwijderen?',
            en: 'Remove booking?',
            fr: 'Supprimer la réservation ?',
            es: '¿Eliminar reserva?',
          ),
        ),
        content: Text(
          _t(
            nl: 'Deze boeking wordt alleen uit jouw lokale overzicht verwijderd. De bedrijfsadministratie en ritgeschiedenis blijven bewaard.',
            en: 'This booking will only be removed from your local overview. Company administration and ride history remain stored.',
            fr: 'Cette réservation sera supprimée uniquement de votre aperçu local. L’administration de l’entreprise et l’historique des trajets restent conservés.',
            es: 'Esta reserva solo se eliminará de tu vista local. La administración de la empresa y el historial del viaje se conservan.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              _t(nl: 'Annuleren', en: 'Cancel', fr: 'Annuler', es: 'Cancelar'),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              _t(
                nl: 'Verwijderen',
                en: 'Remove',
                fr: 'Supprimer',
                es: 'Eliminar',
              ),
            ),
          ),
        ],
      ),
    );
    debugPrint(
      '[CUSTOMER_BOOKINGS][DELETE_CONFIRM] action=detail_remove_one confirmed=${confirmed == true} booking=${_safeRefPreview(bookingId)}',
    );
    if (confirmed != true || !mounted) return;
    final result = await _removeLocalCustomerBookingEverywhere(
      bookingForLog: bookingId,
      aliases: _customerBookingDeleteAliases(
        bookingId: bookingId,
        publicBookingReference: _view.publicBookingReference,
        bookingReference: _view.publicBookingReference,
        publicReference: _view.publicBookingReference,
        planningReference: _view.planningReference,
        receiptReference: _view.receiptReference,
        source: _view.source,
      ),
    );
    final aliases = _customerBookingDeleteAliases(
      bookingId: bookingId,
      publicBookingReference: _view.publicBookingReference,
      bookingReference: _view.publicBookingReference,
      publicReference: _view.publicBookingReference,
      planningReference: _view.planningReference,
      receiptReference: _view.receiptReference,
      source: _view.source,
    );
    final localAfterDelete = await CustomerBookingsStore.instance.loadAll();
    final stillExists = localAfterDelete.any(
      (entry) => _customerAliasesIntersect(
        _customerBookingAliasesFromStored(entry),
        aliases,
      ),
    );
    if (!mounted) return;
    if (result.removed || !stillExists) {
      debugPrint(
        '[CUSTOMER_BOOKING][DELETE_POP] booking=${_safeRefPreview(bookingId)} reason=${result.removed ? 'removed' : 'already_absent'}',
      );
      Navigator.of(
        context,
      ).pop(<String, dynamic>{'action': _customerDetailResultRemovedLocal});
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _t(
            nl: 'Boeking niet gevonden in lokale opslag.',
            en: 'Booking not found in local storage.',
            fr: 'Réservation introuvable dans le stockage local.',
            es: 'Reserva no encontrada en el almacenamiento local.',
          ),
        ),
      ),
    );
  }

  Map<String, String> _cancelHeaders() {
    final h = <String, String>{'Content-Type': 'application/json'};
    if (kAdminToken.trim().isNotEmpty) {
      h['x-admin-token'] = kAdminToken.trim();
    }
    return h;
  }

  bool get _canCancelBooking {
    final status = _view.lifecycleStatus.trim().toUpperCase();
    return status != 'CANCELLED' &&
        status != 'COMPLETED' &&
        status != 'DELETED' &&
        status != 'FAILED' &&
        status != 'EXPIRED' &&
        status != 'DECLINED';
  }

  Future<void> _cancelBookingServerSide() async {
    final bookingId = widget.bookingId.trim();
    if (bookingId.isEmpty || _cancelling || !_canCancelBooking) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          _t(
            nl: 'Boeking annuleren',
            en: 'Cancel booking',
            fr: 'Annuler la réservation',
            es: 'Cancelar reserva',
          ),
        ),
        content: Text(
          _t(
            nl: 'Weet je zeker dat je deze boeking wil annuleren?',
            en: 'Are you sure you want to cancel this booking?',
            fr: 'Voulez-vous vraiment annuler cette réservation ?',
            es: '¿Seguro que quieres cancelar esta reserva?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              _t(
                nl: 'Niet annuleren',
                en: 'Keep booking',
                fr: 'Garder',
                es: 'Mantener',
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              _t(
                nl: 'Annuleren',
                en: 'Cancel booking',
                fr: 'Annuler',
                es: 'Cancelar',
              ),
            ),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() {
      _cancelling = true;
      _refreshError = null;
    });
    final scope = _activeBookingScopeQuery();
    final payload = <String, dynamic>{
      'booking_id': bookingId,
      'status': 'CANCELLED',
      'tenant_id': scope['tenant_id'],
      'company_id': scope['company_id'],
      'tenantId': scope['tenantId'],
      'companyId': scope['companyId'],
      'actor_role': 'customer',
      'actorRole': 'customer',
    };
    final uri = _withActiveBookingScope(
      kBookingBaseUrl,
      '$kUpdateBookingStatusPath/${Uri.encodeComponent(bookingId)}/status',
    );
    debugPrint(
      '[CUSTOMER_BOOKING][CANCEL_REQ] booking=${_safeRefPreview(bookingId)}',
    );
    try {
      final res = await http
          .post(uri, headers: _cancelHeaders(), body: jsonEncode(payload))
          .timeout(const Duration(seconds: 15));
      debugPrint(
        '[CUSTOMER_BOOKING][CANCEL_RES] booking=${_safeRefPreview(bookingId)} code=${res.statusCode}',
      );
      dynamic decoded;
      try {
        decoded = jsonDecode(utf8.decode(res.bodyBytes));
      } catch (_) {
        decoded = null;
      }
      final ok = decoded is Map ? decoded['ok'] == true : false;
      if (res.statusCode != 200 || !ok) {
        throw Exception('HTTP ${res.statusCode}: ${res.body}');
      }

      final aliases = _customerBookingDeleteAliases(
        bookingId: bookingId,
        publicBookingReference: _view.publicBookingReference,
        bookingReference: _view.publicBookingReference,
        publicReference: _view.publicBookingReference,
        planningReference: _view.planningReference,
        receiptReference: _view.receiptReference,
        source: _view.source,
      );
      final localResult = await _removeLocalCustomerBookingEverywhere(
        bookingForLog: bookingId,
        aliases: aliases,
      );
      debugPrint(
        '[CUSTOMER_BOOKING][CANCEL_LOCAL_UPDATE] booking=${_safeRefPreview(bookingId)} removed=${localResult.removed} remaining=${localResult.remaining}',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Boeking geannuleerd.',
              en: 'Booking cancelled.',
              fr: 'Réservation annulée.',
              es: 'Reserva cancelada.',
            ),
          ),
        ),
      );
      Navigator.of(
        context,
      ).pop(<String, dynamic>{'action': _customerDetailResultCancelledServer});
    } catch (err) {
      debugPrint(
        '[CUSTOMER_BOOKING][CANCEL_ERROR] booking=${_safeRefPreview(bookingId)} error=$err',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Annuleren mislukt. Probeer opnieuw.',
              en: 'Cancellation failed. Please try again.',
              fr: 'Échec de l’annulation. Réessayez.',
              es: 'No se pudo cancelar. Inténtalo de nuevo.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _cancelling = false);
      }
    }
  }

  String _lifecycleLabel(String s) {
    final normalized = _normalizeCustomerLifecycleStatus(s);
    switch (normalized) {
      case 'COMPLETED':
        return _t(
          nl: 'Voltooid',
          en: 'Completed',
          fr: 'Terminee',
          es: 'Finalizada',
        );
      case 'CANCELLED':
        return _t(
          nl: 'Geannuleerd',
          en: 'Cancelled',
          fr: 'Annulee',
          es: 'Cancelada',
        );
      case 'PENDING':
        return _t(
          nl: 'In behandeling',
          en: 'Pending',
          fr: 'En cours',
          es: 'Pendiente',
        );
      case 'CONFIRMED':
        return _t(
          nl: 'Bevestigd',
          en: 'Confirmed',
          fr: 'Confirmee',
          es: 'Confirmada',
        );
      default:
        return normalized.isEmpty ? '-' : normalized;
    }
  }

  String _tokenLabel(String value) {
    final text = value.trim();
    if (text.isEmpty) return '-';
    final normalized = text.replaceAll('_', ' ').replaceAll('-', ' ');
    return normalized
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .map(
          (part) => part.length == 1
              ? part.toUpperCase()
              : '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  String _serviceLabel(String raw) {
    final value = raw.trim().toLowerCase();
    if (value.isEmpty) return '-';
    if (value == 'passenger' || value == 'personenvervoer') {
      return _t(
        nl: 'Personenvervoer',
        en: 'Passenger transport',
        fr: 'Transport de passagers',
        es: 'Transporte de pasajeros',
      );
    }
    if (value == 'business' || value == 'zakelijk') {
      return _t(
        nl: 'Zakelijke rit',
        en: 'Business ride',
        fr: "Course d'affaires",
        es: 'Viaje de negocios',
      );
    }
    if (value == 'airport' || value == 'luchthaven') {
      return _t(
        nl: 'Luchthavenvervoer',
        en: 'Airport transfer',
        fr: 'Transfert aeroport',
        es: 'Traslado al aeropuerto',
      );
    }
    return _tokenLabel(raw);
  }

  String _tierLabel(String raw) {
    final value = raw.trim().toLowerCase();
    if (value.isEmpty) return '-';
    if (value == 'comfort')
      return _t(nl: 'Comfort', en: 'Comfort', fr: 'Confort', es: 'Confort');
    if (value == 'private')
      return _t(nl: 'Private', en: 'Private', fr: 'Prive', es: 'Privado');
    if (value == 'premium')
      return _t(nl: 'Premium', en: 'Premium', fr: 'Premium', es: 'Premium');
    return _tokenLabel(raw);
  }

  Widget _section({required String title, required List<Widget> children}) {
    return Card(
      color: const Color(0xFF141B2F),
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: Color(0xFFE5B641),
              ),
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _kv(
    String label,
    String value, {
    bool stacked = false,
    String? emptyText,
  }) {
    final v = value.trim().isEmpty ? (emptyText ?? '-') : value.trim();
    if (stacked) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: Colors.white.withOpacity(0.7))),
            const SizedBox(height: 4),
            Text(v, style: const TextStyle(color: Colors.white)),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white.withOpacity(0.7)),
            ),
          ),
          Expanded(
            child: Text(v, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) {
        final v = _view;
        final paid = v.isPaid;
        final business = v.businessCustomer;
        final invoiceEmail = v.invoiceEmail.trim().isEmpty
            ? _notFilled()
            : v.invoiceEmail.trim();
        final invoiceAddress = v.invoiceAddress.trim().isEmpty
            ? _notFilled()
            : v.invoiceAddress.trim();
        final invoiceFieldsExist =
            v.companyName.isNotEmpty ||
            v.vatNumber.isNotEmpty ||
            v.invoiceEmail.isNotEmpty ||
            v.invoiceAddress.isNotEmpty;
        final showInvoiceSection = business || invoiceFieldsExist;

        return Scaffold(
          backgroundColor: const Color(0xFF0B1020),
          appBar: AppBar(
            backgroundColor: const Color(0xFF0B1020),
            title: Text(
              _t(
                nl: 'Boekingsdetail',
                en: 'Booking detail',
                fr: 'Detail de reservation',
                es: 'Detalle de reserva',
              ),
            ),
            actions: [
              IconButton(
                tooltip: _t(
                  nl: 'Boeking annuleren',
                  en: 'Cancel booking',
                  fr: 'Annuler la réservation',
                  es: 'Cancelar reserva',
                ),
                onPressed: (!_canCancelBooking || _cancelling)
                    ? null
                    : _cancelBookingServerSide,
                icon: _cancelling
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cancel_outlined),
              ),
              IconButton(
                tooltip: _t(
                  nl: 'Verwijder uit mijn boekingen',
                  en: 'Remove from my bookings',
                  fr: 'Supprimer de mes réservations',
                  es: 'Eliminar de mis reservas',
                ),
                onPressed: _removeFromMyBookings,
                icon: const Icon(Icons.delete_outline),
              ),
              IconButton(
                tooltip: _t(
                  nl: 'Vernieuwen',
                  en: 'Refresh',
                  fr: 'Actualiser',
                  es: 'Actualizar',
                ),
                onPressed: _refreshing ? null : _refresh,
                icon: _refreshing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
              ),
            ],
          ),
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (_refreshError != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.withOpacity(0.4)),
                      ),
                      child: Text(
                        _refreshError!,
                        style: const TextStyle(color: Color(0xFFFFB4B4)),
                      ),
                    ),
                  if (_usingLocalCache)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2410),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE5B641)),
                      ),
                      child: Text(
                        _t(
                          nl: 'Je ziet lokale gegevens. Vernieuwen voor de laatste status.',
                          en: 'Showing local data. Refresh for the latest status.',
                          fr: 'Donnees locales affichees. Actualisez pour le statut le plus recent.',
                          es: 'Mostrando datos locales. Actualiza para ver el estado mas reciente.',
                        ),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  if (_canCancelBooking) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _cancelling
                            ? null
                            : _cancelBookingServerSide,
                        icon: _cancelling
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.cancel_outlined),
                        label: Text(
                          _t(
                            nl: 'Boeking annuleren',
                            en: 'Cancel booking',
                            fr: 'Annuler la réservation',
                            es: 'Cancelar reserva',
                          ),
                        ),
                      ),
                    ),
                  ],
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: paid
                          ? const Color(0xFF11331F)
                          : const Color(0xFF2A2410),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: paid
                            ? const Color(0xFF34D29A)
                            : const Color(0xFFE5B641),
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          paid
                              ? Icons.verified_outlined
                              : Icons.payments_outlined,
                          color: paid
                              ? const Color(0xFF34D29A)
                              : const Color(0xFFE5B641),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                paid
                                    ? _t(
                                        nl: 'Betaald',
                                        en: 'Paid',
                                        fr: 'Paye',
                                        es: 'Pagado',
                                      )
                                    : _t(
                                        nl: 'Te betalen in de wagen',
                                        en: 'To pay in the vehicle',
                                        fr: 'A payer dans le vehicule',
                                        es: 'A pagar en el vehiculo',
                                      ),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                paid
                                    ? _t(
                                        nl: 'Je betaling is bevestigd.',
                                        en: 'Your payment has been confirmed.',
                                        fr: 'Votre paiement est confirme.',
                                        es: 'Tu pago esta confirmado.',
                                      )
                                    : _t(
                                        nl: 'Voldoe het bedrag bij de chauffeur.',
                                        en: 'Pay the driver during your ride.',
                                        fr: 'Reglez le chauffeur pendant la course.',
                                        es: 'Paga al conductor durante el viaje.',
                                      ),
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.85),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  _section(
                    title: _t(
                      nl: 'Boeking',
                      en: 'Booking',
                      fr: 'Reservation',
                      es: 'Reserva',
                    ),
                    children: [
                      (() {
                        final bookingRef = _customerBookingReferenceDisplay(v);
                        return Column(
                          children: [
                            _kv(bookingRef.label, bookingRef.value),
                            if (bookingRef.internalSecondary != null)
                              _kv(
                                _t(
                                  nl: 'Interne boeking',
                                  en: 'Internal booking',
                                  fr: 'Réservation interne',
                                  es: 'Reserva interna',
                                ),
                                bookingRef.internalSecondary!,
                              ),
                          ],
                        );
                      })(),
                      _kv(
                        _t(
                          nl: 'Status',
                          en: 'Status',
                          fr: 'Statut',
                          es: 'Estado',
                        ),
                        _lifecycleLabel(v.lifecycleStatus),
                      ),
                      _kv(
                        _t(
                          nl: 'Betaalstatus',
                          en: 'Payment status',
                          fr: 'Statut de paiement',
                          es: 'Estado de pago',
                        ),
                        paid
                            ? _t(
                                nl: 'Betaald',
                                en: 'Paid',
                                fr: 'Paye',
                                es: 'Pagado',
                              )
                            : _t(
                                nl: 'Te betalen in de wagen',
                                en: 'To pay in the vehicle',
                                fr: 'A payer dans le vehicule',
                                es: 'A pagar en el vehiculo',
                              ),
                      ),
                    ],
                  ),
                  _section(
                    title: _t(
                      nl: 'Route',
                      en: 'Route',
                      fr: 'Itineraire',
                      es: 'Ruta',
                    ),
                    children: [
                      _kv(
                        _t(
                          nl: 'Ophaaladres',
                          en: 'Pickup',
                          fr: 'Prise en charge',
                          es: 'Recogida',
                        ),
                        v.fromAddress,
                        stacked: true,
                      ),
                      _kv(
                        _t(
                          nl: 'Bestemming',
                          en: 'Destination',
                          fr: 'Destination',
                          es: 'Destino',
                        ),
                        v.toAddress,
                        stacked: true,
                      ),
                      _kv(
                        _t(
                          nl: 'Geplande ophaal',
                          en: 'Scheduled pickup',
                          fr: 'Prise en charge prevue',
                          es: 'Recogida programada',
                        ),
                        _formatPickup(v.pickupIso),
                      ),
                    ],
                  ),
                  _section(
                    title: _t(
                      nl: 'Klantgegevens',
                      en: 'Customer',
                      fr: 'Client',
                      es: 'Cliente',
                    ),
                    children: [
                      _kv(
                        _t(nl: 'Naam', en: 'Name', fr: 'Nom', es: 'Nombre'),
                        v.customerName,
                      ),
                      _kv(
                        _t(
                          nl: 'Telefoon',
                          en: 'Phone',
                          fr: 'Téléphone',
                          es: 'Teléfono',
                        ),
                        v.customerPhone,
                      ),
                      _kv(
                        _t(
                          nl: 'E-mail',
                          en: 'Email',
                          fr: 'E-mail',
                          es: 'Email',
                        ),
                        v.customerEmail,
                        stacked: true,
                      ),
                    ],
                  ),
                  _section(
                    title: _t(
                      nl: 'Rit details',
                      en: 'Ride details',
                      fr: 'Details de course',
                      es: 'Detalles del viaje',
                    ),
                    children: [
                      _kv(
                        _t(
                          nl: 'Service',
                          en: 'Service',
                          fr: 'Service',
                          es: 'Servicio',
                        ),
                        _serviceLabel(v.service),
                      ),
                      _kv(
                        _t(
                          nl: 'Tier',
                          en: 'Tier',
                          fr: 'Categorie',
                          es: 'Categoria',
                        ),
                        _tierLabel(v.tier),
                      ),
                      _kv(
                        _t(
                          nl: 'Passagiers',
                          en: 'Passengers',
                          fr: 'Passagers',
                          es: 'Pasajeros',
                        ),
                        v.pax,
                      ),
                      _kv(
                        _t(
                          nl: 'Bagage',
                          en: 'Bags',
                          fr: 'Bagages',
                          es: 'Equipaje',
                        ),
                        v.bags,
                      ),
                      _kv(
                        _t(
                          nl: 'Extra opties',
                          en: 'Extra options',
                          fr: 'Options supplementaires',
                          es: 'Opciones extra',
                        ),
                        v.extraOptions.isEmpty
                            ? _t(
                                nl: 'Geen extra opties',
                                en: 'No extra options',
                                fr: 'Aucune option supplementaire',
                                es: 'Sin opciones extra',
                              )
                            : _tokenLabel(v.extraOptions),
                      ),
                    ],
                  ),
                  _section(
                    title: _t(
                      nl: 'Prijs',
                      en: 'Price',
                      fr: 'Prix',
                      es: 'Precio',
                    ),
                    children: [
                      _kv(
                        _t(nl: 'Totaal', en: 'Total', fr: 'Total', es: 'Total'),
                        _formatPrice(v.totalAmount, v.currency),
                      ),
                    ],
                  ),
                  if (showInvoiceSection)
                    _section(
                      title: _t(
                        nl: 'Zakelijk / Factuur',
                        en: 'Business / Invoice',
                        fr: 'Professionnel / Facture',
                        es: 'Empresa / Factura',
                      ),
                      children: [
                        _kv(
                          _t(
                            nl: 'Zakelijke klant',
                            en: 'Business customer',
                            fr: 'Client professionnel',
                            es: 'Cliente empresa',
                          ),
                          business
                              ? _t(nl: 'Ja', en: 'Yes', fr: 'Oui', es: 'Si')
                              : _t(nl: 'Nee', en: 'No', fr: 'Non', es: 'No'),
                        ),
                        _kv(
                          _t(
                            nl: 'Bedrijfsnaam',
                            en: 'Company name',
                            fr: "Nom de l'entreprise",
                            es: 'Empresa',
                          ),
                          v.companyName,
                          stacked: true,
                        ),
                        _kv(
                          _t(
                            nl: 'BTW-nummer',
                            en: 'VAT number',
                            fr: 'Numero de TVA',
                            es: 'NIF/IVA',
                          ),
                          v.vatNumber,
                          stacked: true,
                        ),
                        _kv(
                          _t(
                            nl: 'Factuur e-mail',
                            en: 'Invoice email',
                            fr: 'E-mail facture',
                            es: 'Email de factura',
                          ),
                          invoiceEmail,
                          stacked: true,
                          emptyText: _notFilled(),
                        ),
                        _kv(
                          _t(
                            nl: 'Factuuradres',
                            en: 'Invoice address',
                            fr: 'Adresse de facturation',
                            es: 'Dirección de factura',
                          ),
                          invoiceAddress,
                          stacked: true,
                          emptyText: _notFilled(),
                        ),
                        const SizedBox(height: 8),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => _openReceiptAction(
                                context,
                                _ReceiptQuickAction.viewPdf,
                              ),
                              icon: const Icon(Icons.visibility_outlined),
                              label: Text(
                                _t(
                                  nl: 'Bekijk PDF',
                                  en: 'View PDF',
                                  fr: 'Voir PDF',
                                  es: 'Ver PDF',
                                ),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => _openReceiptAction(
                                context,
                                _ReceiptQuickAction.sharePdf,
                              ),
                              icon: const Icon(Icons.download_outlined),
                              label: Text(
                                _t(
                                  nl: 'Deel PDF',
                                  en: 'Share PDF',
                                  fr: 'Partager PDF',
                                  es: 'Compartir PDF',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

final List<Map<String, dynamic>> _customerRegionLeadInbox =
    <Map<String, dynamic>>[];

class CustomerRegionRegistrationPage extends StatefulWidget {
  const CustomerRegionRegistrationPage({super.key});

  @override
  State<CustomerRegionRegistrationPage> createState() =>
      _CustomerRegionRegistrationPageState();
}

class _CustomerRegionRegistrationPageState
    extends State<CustomerRegionRegistrationPage> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _postalCodeCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _wantsUpdates = true;
  bool _submitting = false;

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) => _tr(nl: nl, en: en, fr: fr, es: es);

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _postalCodeCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  String? _required(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) {
      return _t(
        nl: 'Dit veld is verplicht',
        en: 'This field is required',
        fr: 'Ce champ est obligatoire',
        es: 'Este campo es obligatorio',
      );
    }
    return null;
  }

  String? _emailValidator(String? value) {
    final requiredError = _required(value);
    if (requiredError != null) return requiredError;
    final v = value!.trim();
    if (!v.contains('@') || !v.contains('.')) {
      return _t(
        nl: 'Voer een geldig e-mailadres in',
        en: 'Enter a valid email address',
        fr: 'Entrez une adresse e-mail valide',
        es: 'Introduce un correo electronico valido',
      );
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);

    // Temporary safe local capture until backend lead endpoint is introduced.
    _customerRegionLeadInbox.add(<String, dynamic>{
      'first_name': _firstNameCtrl.text.trim(),
      'last_name': _lastNameCtrl.text.trim(),
      'postal_code': _postalCodeCtrl.text.trim(),
      'email': _emailCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
      'notify_updates': _wantsUpdates,
      'created_at': DateTime.now().toIso8601String(),
    });

    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (!mounted) return;
    setState(() => _submitting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _t(
            nl: 'Bedankt! We hebben je regio geregistreerd.',
            en: 'Thank you! We have registered your region.',
            fr: 'Merci ! Nous avons enregistre votre region.',
            es: 'Gracias. Hemos registrado tu region.',
          ),
        ),
      ),
    );
    Navigator.pop(context);
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    String? Function(String?)? validator,
    TextInputType keyboardType = TextInputType.text,
    String? hintText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          validator: validator,
          keyboardType: keyboardType,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: const Color(0xFF141B2F),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) => Scaffold(
        backgroundColor: const Color(0xFF0B1020),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0B1020),
          title: Text(
            _t(
              nl: 'Registreer je regio',
              en: 'Register your region',
              fr: 'Enregistrez votre region',
              es: 'Registra tu region',
            ),
          ),
        ),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  _t(
                    nl: 'Laat je gegevens achter zodat we je kunnen informeren wanneer Fluxidi actief wordt in jouw regio.',
                    en: 'Leave your details so we can inform you when Fluxidi becomes active in your region.',
                    fr: 'Laissez vos coordonnees afin que nous puissions vous informer lorsque Fluxidi sera actif dans votre region.',
                    es: 'Deja tus datos para que podamos avisarte cuando Fluxidi este activo en tu region.',
                  ),
                  style: TextStyle(color: Colors.white.withOpacity(0.78)),
                ),
                const SizedBox(height: 14),
                _field(
                  label: _t(
                    nl: 'Voornaam',
                    en: 'First name',
                    fr: 'Prenom',
                    es: 'Nombre',
                  ),
                  controller: _firstNameCtrl,
                  validator: _required,
                ),
                const SizedBox(height: 12),
                _field(
                  label: _t(
                    nl: 'Naam',
                    en: 'Last name',
                    fr: 'Nom',
                    es: 'Apellido',
                  ),
                  controller: _lastNameCtrl,
                  validator: _required,
                ),
                const SizedBox(height: 12),
                _field(
                  label: _t(
                    nl: 'Postcode',
                    en: 'Postal code',
                    fr: 'Code postal',
                    es: 'Codigo postal',
                  ),
                  controller: _postalCodeCtrl,
                  validator: _required,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                _field(
                  label: _t(
                    nl: 'E-mail',
                    en: 'Email',
                    fr: 'E-mail',
                    es: 'Correo electronico',
                  ),
                  controller: _emailCtrl,
                  validator: _emailValidator,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                _field(
                  label: _t(
                    nl: 'Telefoon (optioneel)',
                    en: 'Phone (optional)',
                    fr: 'Téléphone (optionnel)',
                    es: 'Teléfono (opcional)',
                  ),
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: _wantsUpdates,
                  onChanged: (v) => setState(() => _wantsUpdates = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  activeColor: const Color(0xFFE5B641),
                  title: Text(
                    _t(
                      nl: 'Hou me op de hoogte wanneer Fluxidi beschikbaar is in mijn regio',
                      en: 'Keep me updated when Fluxidi is available in my region',
                      fr: 'Tenez-moi informe lorsque Fluxidi est disponible dans ma region',
                      es: 'Mantenme informado cuando Fluxidi este disponible en mi region',
                    ),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _submitting
                          ? _t(
                              nl: 'Bezig...',
                              en: 'Sending...',
                              fr: 'Envoi...',
                              es: 'Enviando...',
                            )
                          : _t(
                              nl: 'Verzenden',
                              en: 'Send',
                              fr: 'Envoyer',
                              es: 'Enviar',
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    _t(
                      nl: 'Terug naar klantenpagina',
                      en: 'Back to customer page',
                      fr: 'Retour a la page client',
                      es: 'Volver a la pagina de cliente',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class NearbyPartnersPage extends StatefulWidget {
  const NearbyPartnersPage({super.key});

  @override
  State<NearbyPartnersPage> createState() => _NearbyPartnersPageState();
}

class _NearbyPartnersPageState extends State<NearbyPartnersPage> {
  final TextEditingController _postalCodeCtrl = TextEditingController();
  bool _searching = false;
  bool _searched = false;
  String _normalizedPostcode = '';
  List<Map<String, dynamic>> _partners = const <Map<String, dynamic>>[];

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) => _tr(nl: nl, en: en, fr: fr, es: es);

  @override
  void dispose() {
    _postalCodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _searchPartners() async {
    final raw = _postalCodeCtrl.text.trim();
    if (raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Vul eerst een postcode in.',
              en: 'Enter a postal code first.',
              fr: 'Entrez d abord un code postal.',
              es: 'Introduce primero un codigo postal.',
            ),
          ),
        ),
      );
      return;
    }
    final postcode = raw.toUpperCase().replaceAll(RegExp(r'\s+'), '');
    setState(() {
      _searching = true;
      _searched = false;
      _normalizedPostcode = postcode;
      _partners = const <Map<String, dynamic>>[];
    });
    try {
      final uri = Uri.parse(
        '$kBookingBaseUrl/partners/nearby?postcode=${Uri.encodeQueryComponent(postcode)}',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}');
      }
      final decoded = jsonDecode(res.body);
      final partnersRaw =
          decoded is Map<String, dynamic> && decoded['partners'] is List
          ? (decoded['partners'] as List)
                .whereType<Map<String, dynamic>>()
                .toList()
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searched = true;
        _partners = partnersRaw;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searched = true;
        _partners = const <Map<String, dynamic>>[];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Zoeken van partners is momenteel niet beschikbaar.',
              en: 'Partner search is currently unavailable.',
              fr: 'La recherche de partenaires est actuellement indisponible.',
              es: 'La busqueda de socios no esta disponible actualmente.',
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) => Scaffold(
        backgroundColor: const Color(0xFF0B1020),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0B1020),
          title: Text(
            _t(
              nl: "Taxi's in de buurt",
              en: 'Taxis nearby',
              fr: 'Taxis a proximite',
              es: 'Taxis cercanos',
            ),
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                _t(
                  nl: 'Zoek actieve Fluxidi-partners in jouw regio op basis van postcode.',
                  en: 'Search active Fluxidi partners in your area by postal code.',
                  fr: 'Recherchez des partenaires Fluxidi actifs dans votre region par code postal.',
                  es: 'Busca socios activos de Fluxidi en tu zona por codigo postal.',
                ),
                style: TextStyle(color: Colors.white.withOpacity(0.78)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _postalCodeCtrl,
                style: const TextStyle(color: Colors.white),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _searchPartners(),
                decoration: InputDecoration(
                  labelText: _t(
                    nl: 'Postcode',
                    en: 'Postal code',
                    fr: 'Code postal',
                    es: 'Codigo postal',
                  ),
                  labelStyle: const TextStyle(color: Colors.white70),
                  hintText: _t(
                    nl: 'Bijv. 2000',
                    en: 'e.g. 2000',
                    fr: 'ex. 2000',
                    es: 'ej. 2000',
                  ),
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: const Color(0xFF141B2F),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: _searching ? null : _searchPartners,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    _searching
                        ? _t(
                            nl: 'Zoeken...',
                            en: 'Searching...',
                            fr: 'Recherche...',
                            es: 'Buscando...',
                          )
                        : _t(
                            nl: 'Zoek actieve partners',
                            en: 'Search active partners',
                            fr: 'Rechercher des partenaires actifs',
                            es: 'Buscar socios activos',
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF141B2F),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white10),
                ),
                child: !_searched
                    ? Text(
                        _t(
                          nl: 'Voer je postcode in om te controleren welke partners actief zijn.',
                          en: 'Enter your postal code to check which partners are active.',
                          fr: 'Saisissez votre code postal pour verifier quels partenaires sont actifs.',
                          es: 'Ingresa tu codigo postal para verificar que socios estan activos.',
                        ),
                        style: TextStyle(color: Colors.white.withOpacity(0.75)),
                      )
                    : _partners.isNotEmpty
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _t(
                              nl: 'Actieve partners in $_normalizedPostcode',
                              en: 'Active partners in $_normalizedPostcode',
                              fr: 'Partenaires actifs dans $_normalizedPostcode',
                              es: 'Socios activos en $_normalizedPostcode',
                            ),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          ..._partners.map((p) {
                            final company = (p['company_name'] ?? '')
                                .toString()
                                .trim();
                            final partnerId = (p['partner_id'] ?? '')
                                .toString()
                                .trim();
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F1628),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.business_outlined,
                                    color: Color(0xFFE5B641),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          company.isEmpty ? partnerId : company,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        if (partnerId.isNotEmpty)
                                          Text(
                                            partnerId,
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(
                                                0.58,
                                              ),
                                              fontSize: 12,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _t(
                              nl: 'Voor postcode $_normalizedPostcode hebben we nog geen actieve partners gevonden.',
                              en: 'No active partners found yet for postal code $_normalizedPostcode.',
                              fr: 'Aucun partenaire actif trouve pour le code postal $_normalizedPostcode.',
                              es: 'Aun no se encontraron socios activos para el codigo postal $_normalizedPostcode.',
                            ),
                            style: const TextStyle(color: Colors.white),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const CustomerRegionRegistrationPage(),
                                ),
                              );
                            },
                            child: Text(
                              _t(
                                nl: 'Registreer je regio',
                                en: 'Register your region',
                                fr: 'Enregistrez votre region',
                                es: 'Registra tu region',
                              ),
                            ),
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

class FluxidiFrame extends StatelessWidget {
  final Widget child;
  const FluxidiFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    // Hard Frame A: a visible yellow HUD border that *contains* the whole UI.
    // Target: visually ~2–3mm on phone screens.
    return Container(
      color: kFluxidiBlack,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: kFluxidiBlack,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: kFluxidiYellow.withOpacity(0.98),
                width: 3.0,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 18,
                  spreadRadius: 2,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: kFluxidiBlack,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: kFluxidiYellow.withOpacity(0.55),
                    width: 1.5,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BookingItem {
  final String bookingId;
  final String? pickupIso;
  final String? from;
  final String? to;
  final String? tier;
  final int? pax;
  final int? bags;
  final String? status;
  final num? price; // optional
  final String? currency; // optional
  final Map<String, dynamic> details;

  // Tracking API (fluxidi-tracking-api)
  final String? sessionId;
  final String? createdAtIso;
  final double? lastLat;
  final double? lastLon;
  final String? lastPingTs;
  final num? lastSpeed;
  final num? lastHeading;

  BookingItem({
    required this.bookingId,
    this.sessionId,
    this.pickupIso,
    this.from,
    this.to,
    this.tier,
    this.pax,
    this.bags,
    this.status,
    this.price,
    this.currency,
    this.details = const <String, dynamic>{},
    this.createdAtIso,
    this.lastLat,
    this.lastLon,
    this.lastPingTs,
    this.lastSpeed,
    this.lastHeading,
  });

  String get shortId {
    if (bookingId.length <= 12) return bookingId;
    return '${bookingId.substring(0, 4)}…${bookingId.substring(bookingId.length - 4)}';
  }

  static String? _extractPlaceLabel(dynamic v) {
    if (v == null) return null;
    if (v is String) {
      final s = v.trim();
      return s.isEmpty ? null : s;
    }
    if (v is Map<String, dynamic>) {
      // Common shapes: {address: "..."} or {label:"..."} or {text:"..."} etc.
      const keys = [
        'address',
        'label',
        'text',
        'name',
        'formatted',
        'display',
        'place_name',
        'full_address',
      ];
      for (final k in keys) {
        final vv = v[k];
        if (vv is String && vv.trim().isNotEmpty) return vv.trim();
      }

      // Sometimes nested like {pickup:{address:"..."}} already handled upstream,
      // but also allow {location:{address:"..."}} style.
      for (final nestedKey in ['location', 'place', 'geo', 'data']) {
        final nested = v[nestedKey];
        if (nested is Map<String, dynamic>) {
          for (final k in keys) {
            final vv = nested[k];
            if (vv is String && vv.trim().isNotEmpty) return vv.trim();
          }
        }
      }
    }
    return null;
  }

  BookingItem copyWith({
    String? bookingId,
    String? pickupIso,
    String? from,
    String? to,
    String? tier,
    int? pax,
    int? bags,
    String? status,
    num? price,
    String? currency,
    Map<String, dynamic>? details,
    String? sessionId,
    String? createdAtIso,
    double? lastLat,
    double? lastLon,
    String? lastPingTs,
    num? lastSpeed,
    num? lastHeading,
  }) {
    return BookingItem(
      bookingId: bookingId ?? this.bookingId,
      pickupIso: pickupIso ?? this.pickupIso,
      from: from ?? this.from,
      to: to ?? this.to,
      tier: tier ?? this.tier,
      pax: pax ?? this.pax,
      bags: bags ?? this.bags,
      status: status ?? this.status,
      price: price ?? this.price,
      currency: currency ?? this.currency,
      details: details ?? this.details,
      sessionId: sessionId ?? this.sessionId,
      createdAtIso: createdAtIso ?? this.createdAtIso,
      lastLat: lastLat ?? this.lastLat,
      lastLon: lastLon ?? this.lastLon,
      lastPingTs: lastPingTs ?? this.lastPingTs,
      lastSpeed: lastSpeed ?? this.lastSpeed,
      lastHeading: lastHeading ?? this.lastHeading,
    );
  }

  factory BookingItem.fromJson(Map<String, dynamic> j) {
    // Support both booking-api payloads and tracking-api payloads.
    final lastPing = (j['last_ping'] is Map<String, dynamic>)
        ? (j['last_ping'] as Map<String, dynamic>)
        : null;

    String? pickLabel = _extractPlaceLabel(j['pickup'] ?? j['from']);
    String? dropLabel = _extractPlaceLabel(j['dropoff'] ?? j['to']);

    // Extra common field names across versions/backends
    pickLabel ??= _extractPlaceLabel(
      j['pickup_address'] ?? j['pickup_label'] ?? j['from_address'],
    );
    dropLabel ??= _extractPlaceLabel(
      j['dropoff_address'] ?? j['dropoff_label'] ?? j['to_address'],
    );

    // If backend already provides plain strings, prefer those
    final fromStr = (j['from'] is String) ? (j['from'] as String) : null;
    final toStr = (j['to'] is String) ? (j['to'] as String) : null;

    return BookingItem(
      bookingId: (j['booking_id'] ?? j['id'] ?? '').toString(),
      pickupIso: j['pickup_iso']?.toString(),
      from: (fromStr?.trim().isNotEmpty ?? false)
          ? fromStr!.trim()
          : (pickLabel?.trim().isNotEmpty ?? false ? pickLabel!.trim() : null),
      to: (toStr?.trim().isNotEmpty ?? false)
          ? toStr!.trim()
          : (dropLabel?.trim().isNotEmpty ?? false ? dropLabel!.trim() : null),
      tier: j['tier']?.toString(),
      pax: _toIntOrNull(
        j['pax'] ??
            j['passengers'] ??
            j['persons'] ??
            j['pax_count'] ??
            j['paxCount'],
      ),
      bags: _toIntOrNull(
        j['bags'] ?? j['luggage'] ?? j['bags_count'] ?? j['bagsCount'],
      ),
      status: (j['status'] ?? j['stage'])?.toString(),
      price: _toNumOrNull(
        j['price'] ??
            j['total_price'] ??
            j['total'] ??
            j['amount'] ??
            j['eur'] ??
            ((j['quote'] is Map) ? (j['quote'] as Map)['price'] : null) ??
            ((j['quote'] is Map) ? (j['quote'] as Map)['total_price'] : null) ??
            ((j['quote'] is Map) ? (j['quote'] as Map)['total'] : null) ??
            ((j['quote'] is Map) ? (j['quote'] as Map)['amount'] : null) ??
            ((j['quote'] is Map) ? (j['quote'] as Map)['eur'] : null) ??
            (((j['quote'] is Map) && ((j['quote'] as Map)['pricing'] is Map))
                ? ((j['quote'] as Map)['pricing'] as Map)['price_incl_vat']
                : null) ??
            (((j['quote'] is Map) && ((j['quote'] as Map)['pricing'] is Map))
                ? ((j['quote'] as Map)['pricing'] as Map)['total_price']
                : null) ??
            (((j['quote'] is Map) && ((j['quote'] as Map)['pricing'] is Map))
                ? ((j['quote'] as Map)['pricing'] as Map)['total']
                : null) ??
            (((j['quote'] is Map) && ((j['quote'] as Map)['pricing'] is Map))
                ? ((j['quote'] as Map)['pricing'] as Map)['price']
                : null) ??
            (((j['quote'] is Map) && ((j['quote'] as Map)['pricing'] is Map))
                ? ((j['quote'] as Map)['pricing'] as Map)['amount']
                : null) ??
            (((j['quote'] is Map) && ((j['quote'] as Map)['pricing'] is Map))
                ? ((j['quote'] as Map)['pricing'] as Map)['eur']
                : null),
      ),
      currency: (j['currency'] ?? 'EUR')?.toString(),
      details: Map<String, dynamic>.from(j),
      sessionId: j['session_id']?.toString(),
      createdAtIso: j['created_at']?.toString(),
      lastLat: _toDoubleOrNull(lastPing?['lat']),
      lastLon: _toDoubleOrNull(lastPing?['lon']),
      lastPingTs: lastPing?['ts']?.toString(),
      lastSpeed: _toNumOrNull(lastPing?['speed']),
      lastHeading: _toNumOrNull(lastPing?['heading']),
    );
  }

  static int? _toIntOrNull(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse(v.toString());
  }

  static num? _toNumOrNull(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    return num.tryParse(v.toString());
  }

  static double? _toDoubleOrNull(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }
}

enum _CameraMode { overview, follow }

enum _RideRoutePhase { toPickup, trip }

enum MapThemeMode { light, dark }

class _PlaceSuggestion {
  final String label;
  final double? lon;
  final double? lat;
  const _PlaceSuggestion({required this.label, this.lon, this.lat});
}

class _DirectRideDestinationResult {
  final String label;
  final double? lon;
  final double? lat;

  const _DirectRideDestinationResult({required this.label, this.lon, this.lat});
}

class _TripHistoryItem {
  final String tripId;
  final String kind;
  final String? bookingId;
  final String driverId;
  final String? vehicleId;
  final String? startedAt;
  final String? stoppedAt;
  final String origin;
  final String destination;
  final double? kmTotal;
  final int waitSecondsTotal;
  final double? totalEur;
  final String status;
  final String currency;
  final Map<String, dynamic> bookingDetails;
  final Map<String, dynamic> rawSource;
  final String? customerName;
  final String? customerPhone;
  final String? customerEmail;

  const _TripHistoryItem({
    required this.tripId,
    required this.kind,
    required this.bookingId,
    required this.driverId,
    required this.vehicleId,
    required this.startedAt,
    required this.stoppedAt,
    required this.origin,
    required this.destination,
    required this.kmTotal,
    required this.waitSecondsTotal,
    required this.totalEur,
    required this.status,
    required this.currency,
    required this.bookingDetails,
    required this.rawSource,
    required this.customerName,
    required this.customerPhone,
    required this.customerEmail,
  });

  _TripHistoryItem copyWith({
    Map<String, dynamic>? bookingDetails,
    Map<String, dynamic>? rawSource,
  }) {
    return _TripHistoryItem(
      tripId: tripId,
      kind: kind,
      bookingId: bookingId,
      driverId: driverId,
      vehicleId: vehicleId,
      startedAt: startedAt,
      stoppedAt: stoppedAt,
      origin: origin,
      destination: destination,
      kmTotal: kmTotal,
      waitSecondsTotal: waitSecondsTotal,
      totalEur: totalEur,
      status: status,
      currency: currency,
      bookingDetails: bookingDetails ?? this.bookingDetails,
      rawSource: rawSource ?? this.rawSource,
      customerName: customerName,
      customerPhone: customerPhone,
      customerEmail: customerEmail,
    );
  }

  factory _TripHistoryItem.fromJson(Map<String, dynamic> json) {
    final origin = json['origin'];
    final destination = json['destination'];
    final originLabel = origin is Map ? origin['label']?.toString() : null;
    final label = destination is Map ? destination['label']?.toString() : null;
    final bookingDetails = json['booking_details'] is Map
        ? Map<String, dynamic>.from(json['booking_details'] as Map)
        : <String, dynamic>{};
    if (bookingDetails.isEmpty) {
      final fallbackBookingDetails =
          _pathValue(json, 'record.booking_details') ??
          _pathValue(json, 'record.bookingDetails') ??
          _pathValue(json, 'record.payload.booking_details') ??
          _pathValue(json, 'record.payload.bookingDetails');
      if (fallbackBookingDetails is Map) {
        bookingDetails.addAll(
          Map<String, dynamic>.from(fallbackBookingDetails),
        );
      }
    }
    final rawSource = Map<String, dynamic>.from(json);
    void copyRootDetail(String rootKey, String detailKey) {
      final value = json[rootKey];
      if (value == null) return;
      final text = value.toString().trim();
      if (text.isEmpty || text.toLowerCase() == 'null') return;
      bookingDetails.putIfAbsent(detailKey, () => value);
    }

    copyRootDetail('payment_status', 'payment_status');
    copyRootDetail('paymentStatus', 'paymentStatus');
    copyRootDetail('paid_at', 'paid_at');
    copyRootDetail('paidAt', 'paidAt');
    copyRootDetail('payment_provider', 'payment_provider');
    copyRootDetail('paymentProvider', 'paymentProvider');
    copyRootDetail('payment_id', 'payment_id');
    copyRootDetail('paymentId', 'paymentId');
    final tripIdRaw = (json['trip_id'] ?? '').toString().trim();
    String? resolveReference(List<String> paths) {
      return _resolveScalarLabel(json, paths);
    }

    void setIfMeaningful(
      Map<String, dynamic> target,
      String key,
      String? value,
    ) {
      final text = _cleanBusinessReferenceText(value);
      if (text == null) return;
      target[key] = text;
    }

    bool shouldAcceptReceiptReference(
      String? candidate, {
      required String? bookingId,
      required String? planningReference,
      required String? publicBookingReference,
    }) {
      final normalized = _cleanBusinessReferenceText(candidate);
      if (normalized == null) return false;
      return _isRealReceiptReference(
        candidate: normalized,
        canonicalBookingId: bookingId,
        tripId: tripIdRaw.isEmpty ? null : tripIdRaw,
        planningReference: planningReference,
        publicBookingReference: publicBookingReference,
        legacyTripReceiptNumber: tripIdRaw.isEmpty
            ? null
            : _legacyTripReceiptNumber(tripIdRaw),
      );
    }

    final resolvedBookingId = _resolveScalarLabel(json, const <String>[
      'booking_id',
      'bookingId',
      'id',
      'booking.booking_id',
      'booking.bookingId',
      'booking.id',
      'record.booking_id',
      'record.bookingId',
      'record.booking.booking_id',
      'record.booking.bookingId',
      'record.booking.id',
      'payload.booking_id',
      'payload.bookingId',
      'payload.booking.booking_id',
      'payload.booking.bookingId',
      'data.record.booking_id',
      'data.record.bookingId',
      'data.record.booking.booking_id',
      'data.record.booking.bookingId',
      'data.booking.booking_id',
      'data.booking.bookingId',
      'response.record.booking_id',
      'response.record.bookingId',
      'response.record.booking.booking_id',
      'response.record.booking.bookingId',
      'response.booking.booking_id',
      'response.booking.bookingId',
      'public_reference',
      'publicReference',
      'receipt_reference',
      'receiptReference',
      'booking.public_reference',
      'booking.publicReference',
      'booking.receipt_reference',
      'booking.receiptReference',
    ]);
    final planningReference = resolveReference(const <String>[
      'planning_reference',
      'planningReference',
      'references.planning_reference',
      'references.planningReference',
      'booking.planning_reference',
      'booking.planningReference',
      'record.planning_reference',
      'record.planningReference',
      'record.references.planning_reference',
      'record.references.planningReference',
      'record.booking.planning_reference',
      'record.booking.planningReference',
      'payload.planning_reference',
      'payload.planningReference',
      'payload.references.planning_reference',
      'payload.references.planningReference',
      'payload.booking.planning_reference',
      'payload.booking.planningReference',
      'data.record.planning_reference',
      'data.record.planningReference',
      'data.record.references.planning_reference',
      'data.record.references.planningReference',
      'data.booking.planning_reference',
      'data.booking.planningReference',
      'response.record.planning_reference',
      'response.record.planningReference',
      'response.record.references.planning_reference',
      'response.record.references.planningReference',
      'response.booking.planning_reference',
      'response.booking.planningReference',
    ]);
    final publicBookingReference = resolveReference(const <String>[
      'public_booking_reference',
      'publicBookingReference',
      'booking_reference',
      'bookingReference',
      'public_reference',
      'publicReference',
      'references.public_booking_reference',
      'references.publicBookingReference',
      'references.booking_reference',
      'references.bookingReference',
      'references.public_reference',
      'references.publicReference',
      'booking.public_booking_reference',
      'booking.publicBookingReference',
      'booking.booking_reference',
      'booking.bookingReference',
      'booking.public_reference',
      'booking.publicReference',
      'record.public_booking_reference',
      'record.publicBookingReference',
      'record.booking_reference',
      'record.bookingReference',
      'record.public_reference',
      'record.publicReference',
      'record.references.public_booking_reference',
      'record.references.publicBookingReference',
      'record.references.booking_reference',
      'record.references.bookingReference',
      'record.references.public_reference',
      'record.references.publicReference',
      'record.booking.public_booking_reference',
      'record.booking.publicBookingReference',
      'record.booking.booking_reference',
      'record.booking.bookingReference',
      'record.booking.public_reference',
      'record.booking.publicReference',
      'payload.public_booking_reference',
      'payload.publicBookingReference',
      'payload.booking_reference',
      'payload.bookingReference',
      'payload.public_reference',
      'payload.publicReference',
      'payload.references.public_booking_reference',
      'payload.references.publicBookingReference',
      'payload.references.booking_reference',
      'payload.references.bookingReference',
      'payload.references.public_reference',
      'payload.references.publicReference',
      'payload.booking.public_booking_reference',
      'payload.booking.publicBookingReference',
      'payload.booking.booking_reference',
      'payload.booking.bookingReference',
      'payload.booking.public_reference',
      'payload.booking.publicReference',
      'data.record.public_booking_reference',
      'data.record.publicBookingReference',
      'data.record.booking_reference',
      'data.record.bookingReference',
      'data.record.public_reference',
      'data.record.publicReference',
      'data.booking.public_booking_reference',
      'data.booking.publicBookingReference',
      'data.booking.booking_reference',
      'data.booking.bookingReference',
      'data.booking.public_reference',
      'data.booking.publicReference',
      'response.record.public_booking_reference',
      'response.record.publicBookingReference',
      'response.record.booking_reference',
      'response.record.bookingReference',
      'response.record.public_reference',
      'response.record.publicReference',
      'response.booking.public_booking_reference',
      'response.booking.publicBookingReference',
      'response.booking.booking_reference',
      'response.booking.bookingReference',
      'response.booking.public_reference',
      'response.booking.publicReference',
    ]);
    final bookingReference = resolveReference(const <String>[
      'booking_reference',
      'bookingReference',
      'references.booking_reference',
      'references.bookingReference',
      'booking.booking_reference',
      'booking.bookingReference',
      'record.booking_reference',
      'record.bookingReference',
      'record.references.booking_reference',
      'record.references.bookingReference',
      'record.booking.booking_reference',
      'record.booking.bookingReference',
      'payload.booking_reference',
      'payload.bookingReference',
      'payload.references.booking_reference',
      'payload.references.bookingReference',
      'payload.booking.booking_reference',
      'payload.booking.bookingReference',
      'data.record.booking_reference',
      'data.record.bookingReference',
      'data.booking.booking_reference',
      'data.booking.bookingReference',
      'response.record.booking_reference',
      'response.record.bookingReference',
      'response.booking.booking_reference',
      'response.booking.bookingReference',
    ]);
    final publicReference = resolveReference(const <String>[
      'public_reference',
      'publicReference',
      'references.public_reference',
      'references.publicReference',
      'booking.public_reference',
      'booking.publicReference',
      'record.public_reference',
      'record.publicReference',
      'record.references.public_reference',
      'record.references.publicReference',
      'record.booking.public_reference',
      'record.booking.publicReference',
      'payload.public_reference',
      'payload.publicReference',
      'payload.references.public_reference',
      'payload.references.publicReference',
      'payload.booking.public_reference',
      'payload.booking.publicReference',
      'data.record.public_reference',
      'data.record.publicReference',
      'data.booking.public_reference',
      'data.booking.publicReference',
      'response.record.public_reference',
      'response.record.publicReference',
      'response.booking.public_reference',
      'response.booking.publicReference',
    ]);
    final receiptReference = resolveReference(const <String>[
      'receipt_reference',
      'receiptReference',
      'references.receipt_reference',
      'references.receiptReference',
      'booking.receipt_reference',
      'booking.receiptReference',
      'record.receipt_reference',
      'record.receiptReference',
      'record.references.receipt_reference',
      'record.references.receiptReference',
      'record.booking.receipt_reference',
      'record.booking.receiptReference',
      'payload.receipt_reference',
      'payload.receiptReference',
      'payload.references.receipt_reference',
      'payload.references.receiptReference',
      'payload.booking.receipt_reference',
      'payload.booking.receiptReference',
      'data.record.receipt_reference',
      'data.record.receiptReference',
      'data.booking.receipt_reference',
      'data.booking.receiptReference',
      'response.record.receipt_reference',
      'response.record.receiptReference',
      'response.booking.receipt_reference',
      'response.booking.receiptReference',
    ]);
    setIfMeaningful(bookingDetails, 'planning_reference', planningReference);
    setIfMeaningful(bookingDetails, 'planningReference', planningReference);
    setIfMeaningful(
      bookingDetails,
      'public_booking_reference',
      publicBookingReference,
    );
    setIfMeaningful(
      bookingDetails,
      'publicBookingReference',
      publicBookingReference,
    );
    setIfMeaningful(bookingDetails, 'booking_reference', bookingReference);
    setIfMeaningful(bookingDetails, 'bookingReference', bookingReference);
    setIfMeaningful(bookingDetails, 'public_reference', publicReference);
    setIfMeaningful(bookingDetails, 'publicReference', publicReference);
    if (shouldAcceptReceiptReference(
      receiptReference,
      bookingId: resolvedBookingId,
      planningReference: planningReference,
      publicBookingReference: publicBookingReference,
    )) {
      setIfMeaningful(bookingDetails, 'receipt_reference', receiptReference);
      setIfMeaningful(bookingDetails, 'receiptReference', receiptReference);
    }
    final referencesMap = bookingDetails['references'] is Map
        ? Map<String, dynamic>.from(bookingDetails['references'] as Map)
        : <String, dynamic>{};
    setIfMeaningful(referencesMap, 'planning_reference', planningReference);
    setIfMeaningful(referencesMap, 'planningReference', planningReference);
    setIfMeaningful(
      referencesMap,
      'public_booking_reference',
      publicBookingReference,
    );
    setIfMeaningful(
      referencesMap,
      'publicBookingReference',
      publicBookingReference,
    );
    setIfMeaningful(referencesMap, 'booking_reference', bookingReference);
    setIfMeaningful(referencesMap, 'bookingReference', bookingReference);
    setIfMeaningful(referencesMap, 'public_reference', publicReference);
    setIfMeaningful(referencesMap, 'publicReference', publicReference);
    if (shouldAcceptReceiptReference(
      receiptReference,
      bookingId: resolvedBookingId,
      planningReference: planningReference,
      publicBookingReference: publicBookingReference,
    )) {
      setIfMeaningful(referencesMap, 'receipt_reference', receiptReference);
      setIfMeaningful(referencesMap, 'receiptReference', receiptReference);
    }
    if (referencesMap.isNotEmpty) {
      bookingDetails['references'] = referencesMap;
    }
    setIfMeaningful(rawSource, 'planning_reference', planningReference);
    setIfMeaningful(rawSource, 'planningReference', planningReference);
    setIfMeaningful(
      rawSource,
      'public_booking_reference',
      publicBookingReference,
    );
    setIfMeaningful(
      rawSource,
      'publicBookingReference',
      publicBookingReference,
    );
    setIfMeaningful(rawSource, 'booking_reference', bookingReference);
    setIfMeaningful(rawSource, 'bookingReference', bookingReference);
    setIfMeaningful(rawSource, 'public_reference', publicReference);
    setIfMeaningful(rawSource, 'publicReference', publicReference);
    if (shouldAcceptReceiptReference(
      receiptReference,
      bookingId: resolvedBookingId,
      planningReference: planningReference,
      publicBookingReference: publicBookingReference,
    )) {
      setIfMeaningful(rawSource, 'receipt_reference', receiptReference);
      setIfMeaningful(rawSource, 'receiptReference', receiptReference);
    }
    final customerName = _resolveScalarLabel(json, const <String>[
      'customer.name',
      'customer_name',
      'customerName',
      'custName',
      'name',
      'booking.customer.name',
      'booking.customer_name',
      'booking.customerName',
      'booking.custName',
      'booking.name',
      'record.customer_name',
      'record.booking.customer_name',
      'record.booking.customerName',
      'record.booking.custName',
      'payload.customer_name',
      'payload.booking.customer_name',
      'booking_details.customer_name',
      'booking_details.customerName',
      'booking_details.custName',
    ]);
    final customerPhone = _resolveScalarLabel(json, const <String>[
      'customer.phone',
      'customer_phone',
      'customerPhone',
      'custPhone',
      'phone',
      'tel',
      'mobile',
      'booking.customer.phone',
      'booking.customer_phone',
      'booking.customerPhone',
      'booking.custPhone',
      'booking.phone',
      'record.customer_phone',
      'record.booking.customer_phone',
      'record.booking.customerPhone',
      'record.booking.custPhone',
      'payload.customer_phone',
      'payload.booking.customer_phone',
      'booking_details.customer_phone',
      'booking_details.customerPhone',
      'booking_details.custPhone',
      'booking_details.phone',
      'booking_details.tel',
      'booking_details.mobile',
    ]);
    final customerEmail = _resolveEmailLabel(json, const <String>[
      'customer.email',
      'customer_email',
      'customerEmail',
      'custEmail',
      'email',
      'invoiceEmail',
      'invoice_email',
      'booking.customer.email',
      'booking.customer_email',
      'booking.customerEmail',
      'booking.custEmail',
      'booking.email',
      'record.customer_email',
      'record.booking.customer_email',
      'record.booking.customerEmail',
      'record.booking.custEmail',
      'payload.customer_email',
      'payload.booking.customer_email',
      'booking_details.customer_email',
      'booking_details.customerEmail',
      'booking_details.custEmail',
      'booking_details.email',
      'booking_details.invoice_email',
      'booking_details.invoiceEmail',
    ]);
    final fromResolved = _resolveRouteLabel(json, const <String>[
      'from',
      'pickup',
      'pickup_address',
      'pickupAddress',
      'pickupLocation',
      'pickup_location',
      'origin',
      'start_address',
      'startAddress',
      'booking.from',
      'booking.pickup',
      'booking.pickup_address',
      'booking.pickupAddress',
      'record.from',
      'record.booking.from',
      'record.booking.pickup',
      'payload.from',
      'payload.booking.from',
      'quote.inputs.from',
      'booking_details.from',
      'booking_details.pickup',
      'booking_details.pickup_address',
      'booking_details.pickupAddress',
    ]);
    final toResolved = _resolveRouteLabel(json, const <String>[
      'to',
      'destination',
      'destination_address',
      'destinationAddress',
      'dropoff',
      'dropoff_address',
      'dropoffAddress',
      'end_address',
      'endAddress',
      'booking.to',
      'booking.destination',
      'booking.destination_address',
      'booking.destinationAddress',
      'record.to',
      'record.booking.to',
      'record.booking.destination',
      'payload.to',
      'payload.booking.to',
      'quote.inputs.to',
      'booking_details.to',
      'booking_details.destination',
      'booking_details.destination_address',
      'booking_details.destinationAddress',
    ]);
    double? asDouble(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse((value ?? '').toString().replaceAll(',', '.'));
    }

    int asInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.round();
      return int.tryParse((value ?? '').toString()) ?? 0;
    }

    final rootKmTotal = asDouble(json['km_total']);

    return _TripHistoryItem(
      tripId: (json['trip_id'] ?? '').toString(),
      kind: (json['kind'] ?? 'direct').toString(),
      bookingId: resolvedBookingId,
      driverId: (json['driver_id'] ?? '').toString(),
      vehicleId: json['vehicle_id']?.toString(),
      startedAt: json['started_at']?.toString(),
      stoppedAt: json['stopped_at']?.toString(),
      origin:
          fromResolved.value ??
          _placeLabel(origin, originLabel ?? _receiptText('currentLocation')),
      destination:
          toResolved.value ??
          ((label == null || label.trim().isEmpty) ? '—' : label.trim()),
      kmTotal:
          rootKmTotal ??
          asDouble(bookingDetails['km_total']) ??
          asDouble(bookingDetails['distance_km']),
      waitSecondsTotal: asInt(json['wait_seconds_total']),
      totalEur: asDouble(json['total_eur']),
      status: (json['status'] ?? '—').toString(),
      currency: (json['currency'] ?? 'EUR').toString(),
      bookingDetails: bookingDetails,
      rawSource: rawSource,
      customerName: customerName,
      customerPhone: customerPhone,
      customerEmail: customerEmail,
    );
  }

  static String _placeLabel(dynamic value, String fallback) {
    if (value is Map) {
      final label = value['label']?.toString().trim();
      if (label != null && label.isNotEmpty) return label;
      final lat = value['lat'];
      final lon = value['lon'];
      if (lat != null && lon != null) return '$lat, $lon';
    }
    return fallback;
  }

  static ({String? value, String? key}) _resolveRouteLabel(
    Map<String, dynamic> root,
    List<String> paths,
  ) {
    for (final path in paths) {
      final value = _pathValue(root, path);
      final label = _extractRouteLabel(value);
      if (label != null && label.isNotEmpty) {
        return (value: label, key: path);
      }
    }
    return (value: null, key: null);
  }

  static String? _resolveScalarLabel(
    Map<String, dynamic> root,
    List<String> paths,
  ) {
    for (final path in paths) {
      final value = _pathValue(root, path);
      final text = _cleanText(value);
      if (text != null) return text;
    }
    return null;
  }

  static String? _resolveEmailLabel(
    Map<String, dynamic> root,
    List<String> paths,
  ) {
    for (final path in paths) {
      final value = _pathValue(root, path);
      final text = _cleanText(value);
      if (text == null) continue;
      if (_looksLikeEmail(text)) return text;
    }
    return null;
  }

  static String? _cleanText(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty || text == '—' || text.toLowerCase() == 'null')
      return null;
    return text;
  }

  static bool _looksLikeEmail(String value) {
    final at = value.indexOf('@');
    if (at <= 0 || at >= value.length - 1) return false;
    final dotAfterAt = value.indexOf('.', at + 1);
    if (dotAfterAt <= at + 1 || dotAfterAt >= value.length - 1) return false;
    return !value.contains(RegExp(r'\s'));
  }

  static dynamic _pathValue(Map<String, dynamic> root, String path) {
    dynamic current = root;
    for (final segment in path.split('.')) {
      if (current is Map && current.containsKey(segment)) {
        current = current[segment];
      } else {
        return null;
      }
    }
    return current;
  }

  static String? _extractRouteLabel(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      final text = value.trim();
      if (text.isEmpty || text == '—') return null;
      return text;
    }
    if (value is Map) {
      final label = value['label']?.toString().trim();
      if (label != null && label.isNotEmpty && label != '—') return label;
    }
    final fallback = value.toString().trim();
    if (fallback.isEmpty || fallback == '—') return null;
    return fallback;
  }

  bool get isCompletedForReceipt {
    final s = status.toLowerCase().trim();
    return s == 'stopped' || s == 'completed';
  }

  bool get isLocalOnlyDirectFallback {
    final source = (rawSource['history_source'] ?? '').toString().trim();
    final detailsSource = (bookingDetails['history_source'] ?? '')
        .toString()
        .trim();
    return source == 'local_only_direct_fallback' ||
        detailsSource == 'local_only_direct_fallback';
  }

  String get receiptNumber {
    return _businessReferenceDisplayForItem(
      this,
      source: 'trip_item_receipt_number',
    ).value;
  }

  String get kindLabel {
    return _localizedRideKind(kind);
  }

  String? detail(String key) {
    final value = bookingDetails[key];
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}

String? _paymentUpdateText(dynamic value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty || text.toLowerCase() == 'null') {
    return null;
  }
  return text;
}

String _normalizePaymentUpdateStatus(dynamic value) {
  final raw = _paymentUpdateText(value);
  if (raw == null) return 'unknown';
  final normalized = raw
      .toLowerCase()
      .replaceAll('-', '_')
      .replaceAll(' ', '_')
      .trim();
  switch (normalized) {
    case 'paid':
    case 'succeeded':
    case 'success':
    case 'completed':
    case 'settled':
    case 'confirmed':
      return 'paid';
    case 'pending':
    case 'open':
    case 'authorized':
    case 'authorised':
    case 'processing':
      return 'pending';
    case 'failed':
    case 'error':
    case 'declined':
      return 'failed';
    case 'cancelled':
    case 'canceled':
      return 'cancelled';
    case 'unpaid':
    case 'not_paid':
      return 'unpaid';
    default:
      return 'unknown';
  }
}

String _normalizePaymentUpdateMethod(dynamic value) {
  final raw = _paymentUpdateText(value);
  if (raw == null) return 'unknown';
  final normalized = raw
      .toLowerCase()
      .replaceAll('-', '_')
      .replaceAll(' ', '_')
      .trim();
  switch (normalized) {
    case 'cash':
    case 'contant':
      return 'cash';
    case 'qr':
    case 'qr_code':
      return 'qr';
    case 'bancontact':
      return 'bancontact';
    case 'card':
    case 'terminal':
    case 'card_terminal':
      return 'card_terminal';
    case 'payment_link':
    case 'link':
    case 'online':
      return 'payment_link';
    case 'mollie':
      return 'mollie';
    default:
      return 'unknown';
  }
}

String? _paymentUpdateField(Map<String, dynamic> fields, List<String> keys) {
  for (final key in keys) {
    final text = _paymentUpdateText(fields[key]);
    if (text != null) return text;
  }
  return null;
}

String? _cleanBusinessReferenceText(dynamic value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) return null;
  final token = text.toLowerCase();
  if (token == 'null' ||
      token == 'undefined' ||
      token == 'unknown' ||
      token == '-' ||
      token == '—') {
    return null;
  }
  return text;
}

String? _businessReferenceAtPath(Map<String, dynamic> root, List<String> path) {
  dynamic current = root;
  for (final key in path) {
    if (current is Map && current.containsKey(key)) {
      current = current[key];
    } else {
      return null;
    }
  }
  return _cleanBusinessReferenceText(current);
}

String? _pickReferenceAliasFromMaps(
  List<Map<String, dynamic>> maps,
  List<List<String>> paths,
) {
  for (final map in maps) {
    if (map.isEmpty) continue;
    for (final path in paths) {
      final value = _businessReferenceAtPath(map, path);
      if (value != null) return value;
    }
  }
  return null;
}

Map<String, dynamic>? _referenceMapAtPath(
  Map<String, dynamic> root,
  List<String> path,
) {
  dynamic current = root;
  for (final key in path) {
    if (current is Map && current.containsKey(key)) {
      current = current[key];
    } else {
      return null;
    }
  }
  if (current is Map) {
    return Map<String, dynamic>.from(current);
  }
  return null;
}

List<Map<String, dynamic>> _referenceMapsFromRoot(Map<String, dynamic> root) {
  const nestedPaths = <List<String>>[
    <String>['references'],
    <String>['booking'],
    <String>['record'],
    <String>['record', 'references'],
    <String>['record', 'booking'],
    <String>['record', 'payload'],
    <String>['record', 'payload', 'references'],
    <String>['record', 'payload', 'booking'],
    <String>['payload'],
    <String>['payload', 'references'],
    <String>['payload', 'booking'],
    <String>['data'],
    <String>['data', 'record'],
    <String>['data', 'record', 'references'],
    <String>['data', 'record', 'booking'],
    <String>['data', 'booking'],
    <String>['data', 'booking', 'references'],
    <String>['response'],
    <String>['response', 'record'],
    <String>['response', 'record', 'references'],
    <String>['response', 'record', 'booking'],
    <String>['response', 'booking'],
    <String>['response', 'booking', 'references'],
  ];
  final out = <Map<String, dynamic>>[root];
  for (final path in nestedPaths) {
    final map = _referenceMapAtPath(root, path);
    if (map != null && map.isNotEmpty) out.add(map);
  }
  return out;
}

List<Map<String, dynamic>> _referenceLookupMaps(
  List<Map<String, dynamic>> roots,
) {
  final out = <Map<String, dynamic>>[];
  for (final root in roots) {
    if (root.isEmpty) continue;
    out.addAll(_referenceMapsFromRoot(root));
  }
  return out;
}

const List<List<String>> _receiptReferenceAliasPaths = <List<String>>[
  <String>['receipt_reference'],
  <String>['receiptReference'],
];

const List<List<String>> _planningReferenceAliasPaths = <List<String>>[
  <String>['planning_reference'],
  <String>['planningReference'],
];

const List<List<String>> _publicBookingReferenceAliasPaths = <List<String>>[
  <String>['public_booking_reference'],
  <String>['publicBookingReference'],
  <String>['booking_reference'],
  <String>['bookingReference'],
  <String>['public_reference'],
  <String>['publicReference'],
];

const List<List<String>> _bookingReferenceAliasPaths = <List<String>>[
  <String>['booking_reference'],
  <String>['bookingReference'],
];

const List<List<String>> _publicReferenceAliasPaths = <List<String>>[
  <String>['public_reference'],
  <String>['publicReference'],
];

({
  String? receipt,
  String? planning,
  String? publicBooking,
  String? booking,
  String? publicRef,
})
_extractBusinessReferenceAliasesFromMaps(List<Map<String, dynamic>> maps) {
  final receipt = _pickReferenceAliasFromMaps(
    maps,
    _receiptReferenceAliasPaths,
  );
  final planning = _pickReferenceAliasFromMaps(
    maps,
    _planningReferenceAliasPaths,
  );
  final publicBooking = _pickReferenceAliasFromMaps(
    maps,
    _publicBookingReferenceAliasPaths,
  );
  final bookingRef = _pickReferenceAliasFromMaps(
    maps,
    _bookingReferenceAliasPaths,
  );
  final publicRef = _pickReferenceAliasFromMaps(
    maps,
    _publicReferenceAliasPaths,
  );
  return (
    receipt: receipt,
    planning: planning,
    publicBooking: publicBooking,
    booking: bookingRef,
    publicRef: publicRef,
  );
}

Map<String, dynamic> _mergeBusinessReferencesIntoSource({
  required Map<String, dynamic> source,
  required Map<String, dynamic> authoritative,
  String? canonicalBookingId,
  String? tripId,
  required String sourceTag,
}) {
  final merged = Map<String, dynamic>.from(source);
  final sourceMaps = _referenceLookupMaps(<Map<String, dynamic>>[merged]);
  final authoritativeMaps = _referenceLookupMaps(<Map<String, dynamic>>[
    authoritative,
  ]);
  final existing = _extractBusinessReferenceAliasesFromMaps(sourceMaps);
  final incoming = _extractBusinessReferenceAliasesFromMaps(authoritativeMaps);
  final selectedPlanning = incoming.planning ?? existing.planning;
  final selectedPublicBooking =
      incoming.publicBooking ?? existing.publicBooking;
  final selectedBooking = incoming.booking ?? existing.booking;
  final selectedPublic = incoming.publicRef ?? existing.publicRef;
  final existingReceipt = existing.receipt;
  final incomingReceipt = incoming.receipt;
  final resolvedReceipt =
      (incomingReceipt != null &&
          _isRealReceiptReference(
            candidate: incomingReceipt,
            canonicalBookingId: canonicalBookingId,
            tripId: tripId,
            planningReference: selectedPlanning,
            publicBookingReference: selectedPublicBooking,
            legacyTripReceiptNumber: tripId == null
                ? null
                : _legacyTripReceiptNumber(tripId),
          ))
      ? incomingReceipt
      : existingReceipt;

  void setIfMeaningful(Map<String, dynamic> target, String key, String? value) {
    final text = _cleanBusinessReferenceText(value);
    if (text == null) return;
    target[key] = text;
  }

  final references = merged['references'] is Map
      ? Map<String, dynamic>.from(merged['references'] as Map)
      : <String, dynamic>{};
  final booking = merged['booking'] is Map
      ? Map<String, dynamic>.from(merged['booking'] as Map)
      : <String, dynamic>{};

  setIfMeaningful(merged, 'planning_reference', selectedPlanning);
  setIfMeaningful(merged, 'planningReference', selectedPlanning);
  setIfMeaningful(merged, 'public_booking_reference', selectedPublicBooking);
  setIfMeaningful(merged, 'publicBookingReference', selectedPublicBooking);
  setIfMeaningful(merged, 'booking_reference', selectedBooking);
  setIfMeaningful(merged, 'bookingReference', selectedBooking);
  setIfMeaningful(merged, 'public_reference', selectedPublic);
  setIfMeaningful(merged, 'publicReference', selectedPublic);
  setIfMeaningful(merged, 'receipt_reference', resolvedReceipt);
  setIfMeaningful(merged, 'receiptReference', resolvedReceipt);

  setIfMeaningful(references, 'planning_reference', selectedPlanning);
  setIfMeaningful(references, 'planningReference', selectedPlanning);
  setIfMeaningful(
    references,
    'public_booking_reference',
    selectedPublicBooking,
  );
  setIfMeaningful(references, 'publicBookingReference', selectedPublicBooking);
  setIfMeaningful(references, 'booking_reference', selectedBooking);
  setIfMeaningful(references, 'bookingReference', selectedBooking);
  setIfMeaningful(references, 'public_reference', selectedPublic);
  setIfMeaningful(references, 'publicReference', selectedPublic);
  setIfMeaningful(references, 'receipt_reference', resolvedReceipt);
  setIfMeaningful(references, 'receiptReference', resolvedReceipt);

  setIfMeaningful(booking, 'planning_reference', selectedPlanning);
  setIfMeaningful(booking, 'planningReference', selectedPlanning);
  setIfMeaningful(booking, 'public_booking_reference', selectedPublicBooking);
  setIfMeaningful(booking, 'publicBookingReference', selectedPublicBooking);
  setIfMeaningful(booking, 'booking_reference', selectedBooking);
  setIfMeaningful(booking, 'bookingReference', selectedBooking);
  setIfMeaningful(booking, 'public_reference', selectedPublic);
  setIfMeaningful(booking, 'publicReference', selectedPublic);
  setIfMeaningful(booking, 'receipt_reference', resolvedReceipt);
  setIfMeaningful(booking, 'receiptReference', resolvedReceipt);

  if (references.isNotEmpty) merged['references'] = references;
  if (booking.isNotEmpty) merged['booking'] = booking;

  debugPrint(
    '[RECEIPT][REF_ENRICH] source=$sourceTag booking=${_safeRefPreview(canonicalBookingId ?? '')} planning=${selectedPlanning ?? ''} public=${selectedPublicBooking ?? ''} receipt=${resolvedReceipt ?? ''}',
  );
  return merged;
}

String _safeRefPreview(String value) {
  final text = value.trim();
  if (text.isEmpty) return '';
  if (text.length <= 10) return text;
  return '${text.substring(0, 4)}…${text.substring(text.length - 4)}';
}

Future<void> _agentDebugLog({
  required String runId,
  required String hypothesisId,
  required String location,
  required String message,
  required Map<String, dynamic> data,
}) async {
  try {
    final payload = <String, dynamic>{
      'sessionId': '59ce83',
      'runId': runId,
      'hypothesisId': hypothesisId,
      'location': location,
      'message': message,
      'data': data,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    await File('debug-59ce83.log').writeAsString(
      '${jsonEncode(payload)}\n',
      mode: FileMode.append,
      flush: true,
    );
  } catch (_) {
    // Keep debug logging non-blocking.
  }
}

void _debugReceiptReferenceSelection({
  required String source,
  required _TripHistoryItem item,
  required String selected,
}) {
  final maps = _referenceLookupMaps(<Map<String, dynamic>>[
    item.rawSource,
    item.bookingDetails,
  ]);
  final refs = _extractBusinessReferenceAliasesFromMaps(maps);
  debugPrint(
    '[RECEIPT][REF_SELECTED] booking=${_safeRefPreview(item.bookingId ?? '')} receipt=${refs.receipt ?? ''} planning=${refs.planning ?? ''} public=${refs.publicBooking ?? ''} selected=$selected source=$source',
  );
}

String _legacyTripReceiptNumber(String tripId) {
  final normalized = tripId.trim();
  if (normalized.length <= 10) return normalized;
  return '${normalized.substring(0, 6)}-${normalized.substring(normalized.length - 4)}';
}

bool _sameReference(String? a, String? b) {
  final left = _cleanBusinessReferenceText(a);
  final right = _cleanBusinessReferenceText(b);
  if (left == null || right == null) return false;
  return left.trim().toLowerCase() == right.trim().toLowerCase();
}

bool _isLegacyTripReceiptNumber(String? value) {
  final text = _cleanBusinessReferenceText(value);
  if (text == null) return false;
  final lower = text.toLowerCase();
  if (lower.startsWith('planne-')) return true;
  return RegExp(r'^planne-[a-z0-9]{3,}$').hasMatch(lower);
}

bool _isDerivedPlannedTripReference({
  required String candidate,
  String? canonicalBookingId,
  String? tripId,
}) {
  final lower = candidate.trim().toLowerCase();
  if (lower.startsWith('planned_')) return true;
  final canonical = _cleanBusinessReferenceText(canonicalBookingId);
  if (canonical != null && _sameReference(candidate, 'planned_$canonical')) {
    return true;
  }
  if (tripId != null &&
      _sameReference(candidate, tripId) &&
      lower.startsWith('planned_')) {
    return true;
  }
  return false;
}

bool _isRealReceiptReference({
  required String candidate,
  String? canonicalBookingId,
  String? tripId,
  String? planningReference,
  String? publicBookingReference,
  String? legacyTripReceiptNumber,
}) {
  final normalized = _cleanBusinessReferenceText(candidate);
  if (normalized == null) return false;
  if (_sameReference(normalized, canonicalBookingId)) return false;
  if (_sameReference(normalized, tripId)) return false;
  if (_sameReference(normalized, planningReference)) return false;
  if (_sameReference(normalized, publicBookingReference)) return false;
  if (_sameReference(normalized, legacyTripReceiptNumber)) return false;
  if (_isLegacyTripReceiptNumber(normalized)) return false;
  if (_isDerivedPlannedTripReference(
    candidate: normalized,
    canonicalBookingId: canonicalBookingId,
    tripId: tripId,
  )) {
    return false;
  }
  return true;
}

String _pickBusinessReference({
  required Map<String, dynamic> rawSource,
  Map<String, dynamic> details = const <String, dynamic>{},
  String? bookingId,
  String? tripId,
  String? legacyFallback,
}) {
  final maps = _referenceLookupMaps(<Map<String, dynamic>>[rawSource, details]);

  const receiptPaths = <List<String>>[
    <String>['receipt_reference'],
    <String>['receiptReference'],
    <String>['references', 'receipt_reference'],
    <String>['references', 'receiptReference'],
    <String>['booking', 'receipt_reference'],
    <String>['booking', 'receiptReference'],
  ];
  const planningPaths = <List<String>>[
    <String>['planning_reference'],
    <String>['planningReference'],
    <String>['references', 'planning_reference'],
    <String>['references', 'planningReference'],
    <String>['booking', 'planning_reference'],
    <String>['booking', 'planningReference'],
  ];
  const publicBookingPaths = <List<String>>[
    <String>['public_booking_reference'],
    <String>['publicBookingReference'],
    <String>['booking_reference'],
    <String>['bookingReference'],
    <String>['public_reference'],
    <String>['publicReference'],
    <String>['references', 'public_booking_reference'],
    <String>['references', 'publicBookingReference'],
    <String>['references', 'booking_reference'],
    <String>['references', 'bookingReference'],
    <String>['references', 'public_reference'],
    <String>['references', 'publicReference'],
    <String>['booking', 'public_booking_reference'],
    <String>['booking', 'publicBookingReference'],
    <String>['booking', 'booking_reference'],
    <String>['booking', 'bookingReference'],
    <String>['booking', 'public_reference'],
    <String>['booking', 'publicReference'],
  ];
  const canonicalBookingPaths = <List<String>>[
    <String>['booking_id'],
    <String>['bookingId'],
    <String>['references', 'booking_id'],
    <String>['references', 'bookingId'],
    <String>['booking', 'booking_id'],
    <String>['booking', 'bookingId'],
    <String>['id'],
  ];
  const tripPaths = <List<String>>[
    <String>['trip_id'],
    <String>['tripId'],
    <String>['references', 'trip_id'],
    <String>['references', 'tripId'],
    <String>['booking', 'trip_id'],
    <String>['booking', 'tripId'],
  ];

  final canonicalBookingId =
      _cleanBusinessReferenceText(bookingId) ??
      _pickReferenceAliasFromMaps(maps, canonicalBookingPaths);
  final effectiveTripId =
      _cleanBusinessReferenceText(tripId) ??
      _pickReferenceAliasFromMaps(maps, tripPaths);
  final planningRef = _pickReferenceAliasFromMaps(maps, planningPaths);
  final publicBookingRef = _pickReferenceAliasFromMaps(
    maps,
    publicBookingPaths,
  );
  final receiptRef = _pickReferenceAliasFromMaps(maps, receiptPaths);
  final legacyTripReceiptNumber =
      _cleanBusinessReferenceText(legacyFallback) ??
      (effectiveTripId == null
          ? null
          : _legacyTripReceiptNumber(effectiveTripId));
  if (receiptRef != null &&
      _isRealReceiptReference(
        candidate: receiptRef,
        canonicalBookingId: canonicalBookingId,
        tripId: effectiveTripId,
        planningReference: planningRef,
        publicBookingReference: publicBookingRef,
        legacyTripReceiptNumber: legacyTripReceiptNumber,
      )) {
    return receiptRef;
  }

  if (planningRef != null) return planningRef;
  if (publicBookingRef != null) return publicBookingRef;
  if (canonicalBookingId != null) return canonicalBookingId;
  if (effectiveTripId != null) return effectiveTripId;

  final fallback = _cleanBusinessReferenceText(legacyTripReceiptNumber);
  return fallback ?? '—';
}

enum _BusinessReferenceKind {
  receipt,
  planning,
  publicBooking,
  canonicalBooking,
  internalTrip,
  unknown,
}

_BusinessReferenceKind _classifyBusinessReferenceSelection({
  required String selectedValue,
  required Map<String, dynamic> rawSource,
  required Map<String, dynamic> details,
  String? bookingId,
  String? tripId,
}) {
  final selected = _cleanBusinessReferenceText(selectedValue);
  if (selected == null) return _BusinessReferenceKind.unknown;
  final maps = _referenceLookupMaps(<Map<String, dynamic>>[rawSource, details]);
  final refs = _extractBusinessReferenceAliasesFromMaps(maps);
  final canonicalBookingId =
      _cleanBusinessReferenceText(bookingId) ??
      _pickReferenceAliasFromMaps(maps, const [
        ['booking_id'],
        ['bookingId'],
        ['id'],
      ]);
  final effectiveTripId =
      _cleanBusinessReferenceText(tripId) ??
      _pickReferenceAliasFromMaps(maps, const [
        ['trip_id'],
        ['tripId'],
      ]);
  if (_sameReference(selected, refs.receipt) &&
      _isRealReceiptReference(
        candidate: selected,
        canonicalBookingId: canonicalBookingId,
        tripId: effectiveTripId,
        planningReference: refs.planning,
        publicBookingReference: refs.publicBooking,
        legacyTripReceiptNumber: effectiveTripId == null
            ? null
            : _legacyTripReceiptNumber(effectiveTripId),
      )) {
    return _BusinessReferenceKind.receipt;
  }
  if (_sameReference(selected, refs.planning)) {
    return _BusinessReferenceKind.planning;
  }
  if (_sameReference(selected, refs.publicBooking) ||
      _sameReference(selected, refs.booking) ||
      _sameReference(selected, refs.publicRef)) {
    return _BusinessReferenceKind.publicBooking;
  }
  if (_sameReference(selected, canonicalBookingId)) {
    return _BusinessReferenceKind.canonicalBooking;
  }
  if (_sameReference(selected, effectiveTripId) ||
      _isLegacyTripReceiptNumber(selected) ||
      _isDerivedPlannedTripReference(
        candidate: selected,
        canonicalBookingId: canonicalBookingId,
        tripId: effectiveTripId,
      )) {
    return _BusinessReferenceKind.internalTrip;
  }
  return _BusinessReferenceKind.unknown;
}

String _receiptReferenceLabelForKind(_BusinessReferenceKind kind) {
  switch (kind) {
    case _BusinessReferenceKind.receipt:
      return _receiptText('receiptNumber');
    case _BusinessReferenceKind.planning:
      return _receiptText('planningNumber');
    case _BusinessReferenceKind.publicBooking:
      return _receiptText('bookingNumber');
    case _BusinessReferenceKind.canonicalBooking:
      return _receiptText('internalBooking');
    case _BusinessReferenceKind.internalTrip:
      return _receiptText('internalTrip');
    case _BusinessReferenceKind.unknown:
      return _receiptText('reference');
  }
}

({String label, String value, _BusinessReferenceKind kind})
_businessReferenceDisplayForItem(
  _TripHistoryItem item, {
  required String source,
}) {
  final selected = _pickBusinessReference(
    rawSource: item.rawSource,
    details: item.bookingDetails,
    bookingId: item.bookingId,
    tripId: item.tripId,
    legacyFallback: _legacyTripReceiptNumber(item.tripId),
  );
  final kind = _classifyBusinessReferenceSelection(
    selectedValue: selected,
    rawSource: item.rawSource,
    details: item.bookingDetails,
    bookingId: item.bookingId,
    tripId: item.tripId,
  );
  _debugReceiptReferenceSelection(
    source: source,
    item: item,
    selected: selected,
  );
  return (
    label: _receiptReferenceLabelForKind(kind),
    value: selected,
    kind: kind,
  );
}

String? _paymentUpdatePaidAtUtc(Map<String, dynamic> fields) {
  final raw = _paymentUpdateField(fields, const [
    'paid_at_utc',
    'paidAtUtc',
    'paid_at',
    'paidAt',
  ]);
  if (raw == null) return null;
  final parsed = DateTime.tryParse(raw);
  return parsed == null ? raw : parsed.toUtc().toIso8601String();
}

bool _isPaidPaymentUpdate(Map<String, dynamic> fields) {
  return _normalizePaymentUpdateStatus(
        _paymentUpdateField(fields, const ['payment_status', 'paymentStatus']),
      ) ==
      'paid';
}

Map<String, dynamic> _buildCompliancePaymentUpdateLedgerRecord({
  required _TripHistoryItem item,
  required Map<String, dynamic> paymentFields,
  required String method,
  required String source,
  required DateTime eventAt,
  bool? backendConfirmed,
}) {
  final bookingId = (item.bookingId ?? '').trim();
  final tripId = item.tripId.trim();
  final normalizedRideType = item.kind.trim().toLowerCase();
  final rideType =
      normalizedRideType == 'direct' || normalizedRideType == 'planned'
      ? normalizedRideType
      : (bookingId.isNotEmpty
            ? 'planned'
            : (tripId.isNotEmpty ? 'direct' : 'unknown'));
  final paidAtUtc =
      _paymentUpdatePaidAtUtc(paymentFields) ??
      eventAt.toUtc().toIso8601String();
  final status = _normalizePaymentUpdateStatus(
    _paymentUpdateField(paymentFields, const [
      'payment_status',
      'paymentStatus',
    ]),
  );
  final normalizedMethod = _normalizePaymentUpdateMethod(
    _paymentUpdateField(paymentFields, const [
          'payment_method',
          'paymentMethod',
        ]) ??
        method,
  );
  final paymentSource =
      _paymentUpdateField(paymentFields, const [
        'payment_source',
        'paymentSource',
      ]) ??
      source;
  final provider = _paymentUpdateField(paymentFields, const [
    'payment_provider',
    'paymentProvider',
  ]);
  final paymentId = _paymentUpdateField(paymentFields, const [
    'payment_id',
    'paymentId',
  ]);
  final maps = _referenceLookupMaps(<Map<String, dynamic>>[
    paymentFields,
    item.bookingDetails,
    item.rawSource,
  ]);
  final receiptReference = _pickReferenceAliasFromMaps(maps, const [
    ['receipt_reference'],
    ['receiptReference'],
  ]);
  final planningReference = _pickReferenceAliasFromMaps(maps, const [
    ['planning_reference'],
    ['planningReference'],
  ]);
  final publicBookingReference = _pickReferenceAliasFromMaps(maps, const [
    ['public_booking_reference'],
    ['publicBookingReference'],
    ['booking_reference'],
    ['bookingReference'],
    ['public_reference'],
    ['publicReference'],
  ]);
  final bookingReference = _pickReferenceAliasFromMaps(maps, const [
    ['booking_reference'],
    ['bookingReference'],
  ]);
  final publicReference = _pickReferenceAliasFromMaps(maps, const [
    ['public_reference'],
    ['publicReference'],
  ]);
  final reference = _pickBusinessReference(
    rawSource: item.rawSource,
    details: item.bookingDetails,
    bookingId: bookingId,
    tripId: tripId,
    legacyFallback: _legacyTripReceiptNumber(item.tripId),
  );
  final effectiveReceiptReference =
      (receiptReference != null &&
          _isRealReceiptReference(
            candidate: receiptReference,
            canonicalBookingId: bookingId,
            tripId: tripId,
            planningReference: planningReference,
            publicBookingReference: publicBookingReference,
            legacyTripReceiptNumber: _legacyTripReceiptNumber(item.tripId),
          ))
      ? receiptReference
      : reference;
  final eventKey = reference.isEmpty
      ? eventAt.toUtc().millisecondsSinceEpoch
      : reference;

  return <String, dynamic>{
    'ledger_version': '1.0',
    'event_type': 'payment_update',
    'event_id': 'payment_update_${eventKey}_${normalizedMethod}_$paidAtUtc',
    'ride_id': null,
    'ride_type': rideType,
    'lifecycle_status': 'payment_updated',
    'tenant_id': kOutboundTenantId,
    'company_id': resolvedCompanyId,
    'driver_id': item.driverId.trim().isNotEmpty
        ? item.driverId.trim()
        : kDriverId,
    'vehicle_id': (item.vehicleId ?? '').trim().isEmpty
        ? null
        : item.vehicleId!.trim(),
    'booking_id': bookingId.isEmpty ? null : bookingId,
    'trip_id': tripId.isEmpty ? null : tripId,
    'session_id': null,
    'payment': <String, dynamic>{
      'status': status,
      if (normalizedMethod != 'unknown') 'method': normalizedMethod,
      if (paymentSource.trim().isNotEmpty) 'source': paymentSource.trim(),
      if (provider != null) 'provider': provider,
      if (paymentId != null) 'payment_id': paymentId,
      'paid_at_utc': paidAtUtc,
    },
    'references': <String, dynamic>{
      'receipt_reference': effectiveReceiptReference.isEmpty
          ? null
          : effectiveReceiptReference,
      'planning_reference': planningReference,
      'public_booking_reference': publicBookingReference,
      'booking_reference': bookingReference,
      'public_reference': publicReference,
      'invoice_reference': null,
    },
    'provenance': <String, dynamic>{
      'backend_confirmed': backendConfirmed,
      'validation_state': 'payment_update',
      'source': 'in_car_payment_mark',
    },
    'created_at_utc': eventAt.toUtc().toIso8601String(),
    'finalized_at_utc': eventAt.toUtc().toIso8601String(),
  };
}

bool _isPaidForReceiptPaymentFallback(String? rawStatus) {
  final normalized = (rawStatus ?? '')
      .trim()
      .toLowerCase()
      .replaceAll('-', '_')
      .replaceAll(' ', '_');
  return normalized == 'paid' ||
      normalized == 'settled' ||
      normalized == 'confirmed' ||
      normalized == 'completed' ||
      normalized == 'succeeded' ||
      normalized == 'success';
}

bool _isMissingOrUnknownReceiptPaymentField(String? value) {
  final normalized = (value ?? '')
      .trim()
      .toLowerCase()
      .replaceAll('-', '_')
      .replaceAll(' ', '_');
  return normalized.isEmpty || normalized == 'unknown';
}

String? _paymentFieldWithMolliePaidFallback({
  required String? value,
  required String? paymentStatus,
  required String? paymentProvider,
}) {
  if (!_isMissingOrUnknownReceiptPaymentField(value)) {
    return value?.trim();
  }
  final providerNormalized = (paymentProvider ?? '')
      .trim()
      .toLowerCase()
      .replaceAll('-', '_')
      .replaceAll(' ', '_');
  if (providerNormalized == 'mollie' &&
      _isPaidForReceiptPaymentFallback(paymentStatus)) {
    return 'mollie';
  }
  return value?.trim();
}

class _DirectRideDestinationDialog extends StatefulWidget {
  final String initialText;
  final Future<List<_PlaceSuggestion>> Function(String query) search;

  const _DirectRideDestinationDialog({
    required this.initialText,
    required this.search,
  });

  @override
  State<_DirectRideDestinationDialog> createState() =>
      _DirectRideDestinationDialogState();
}

class _DirectRideDestinationDialogState
    extends State<_DirectRideDestinationDialog> {
  late final TextEditingController _controller;
  Timer? _debounce;
  List<_PlaceSuggestion> _suggestions = <_PlaceSuggestion>[];
  _PlaceSuggestion? _selected;
  bool _loading = false;
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _selected = null;
    _debounce?.cancel();
    final q = value.trim();
    if (q.length < 3) {
      setState(() {
        _loading = false;
        _searched = false;
        _suggestions = <_PlaceSuggestion>[];
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted) return;
      setState(() {
        _loading = true;
        _searched = true;
      });
      final results = await widget.search(q);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _suggestions = results;
      });
    });
  }

  void _pick(_PlaceSuggestion suggestion) {
    setState(() {
      _selected = suggestion;
      _controller.text = suggestion.label;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
      _suggestions = <_PlaceSuggestion>[];
      _searched = false;
    });
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final selected = _selected;
    Navigator.of(context).pop(
      _DirectRideDestinationResult(
        label: selected?.label ?? text,
        lon: selected?.lon,
        lat: selected?.lat,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _tr(
          nl: 'Straatrit',
          en: 'Direct ride',
          fr: 'Course directe',
          es: 'Viaje directo',
        ),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: _tr(
                  nl: 'Bestemming',
                  en: 'Destination',
                  fr: 'Destination',
                  es: 'Destino',
                ),
                hintText: _tr(
                  nl: 'Typ minstens 3 tekens',
                  en: 'Type at least 3 characters',
                  fr: 'Tapez au moins 3 caracteres',
                  es: 'Escribe al menos 3 caracteres',
                ),
                suffixIcon: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
              ),
              onChanged: _onChanged,
              onSubmitted: (_) => _submit(),
            ),
            if (_suggestions.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 10),
                constraints: const BoxConstraints(maxHeight: 220),
                decoration: BoxDecoration(
                  color: const Color(0xFF0B0F1C),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0x44FFD54A)),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _suggestions.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: Color(0x22FFFFFF)),
                  itemBuilder: (context, index) {
                    final suggestion = _suggestions[index];
                    return ListTile(
                      dense: true,
                      title: Text(
                        suggestion.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => _pick(suggestion),
                    );
                  },
                ),
              )
            else if (_searched && !_loading)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _tr(
                      nl: 'Geen adres gevonden',
                      en: 'No address found',
                      fr: 'Aucune adresse trouvee',
                      es: 'No se encontro direccion',
                    ),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.70),
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            _tr(nl: 'Annuleren', en: 'Cancel', fr: 'Annuler', es: 'Cancelar'),
          ),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(
            _tr(
              nl: 'Doorgaan',
              en: 'Continue',
              fr: 'Continuer',
              es: 'Continuar',
            ),
          ),
        ),
      ],
    );
  }
}

class _LonLat {
  final double lon;
  final double lat;
  const _LonLat(this.lon, this.lat);
}

class _ExternalNavTarget {
  final double? lat;
  final double? lon;
  final String? query;

  const _ExternalNavTarget({this.lat, this.lon, this.query});

  bool get hasCoordinates => lat != null && lon != null;
  bool get hasQuery => (query ?? '').trim().isNotEmpty;
}

class _NavStep {
  final double lat;
  final double lon;
  final String instruction;
  final String street;
  final String type;
  final String modifier;
  final double distanceAlongRouteM;
  final double? distanceM;
  final int? durationSec;

  const _NavStep({
    required this.lat,
    required this.lon,
    required this.instruction,
    required this.street,
    required this.type,
    required this.modifier,
    required this.distanceAlongRouteM,
    this.distanceM,
    this.durationSec,
  });
}

class _RouteSnap {
  final _LonLat point;
  final double distanceFromRouteM;
  final double distanceAlongRouteM;
  final int segmentIndex;
  final double segmentT;

  const _RouteSnap({
    required this.point,
    required this.distanceFromRouteM,
    required this.distanceAlongRouteM,
    required this.segmentIndex,
    required this.segmentT,
  });
}

class _UnauthorizedMapbox implements Exception {
  final String where;
  _UnauthorizedMapbox(this.where);

  @override
  String toString() => 'Mapbox unauthorized ($where)';
}

class DriverHomePage extends StatefulWidget {
  const DriverHomePage({super.key});

  @override
  State<DriverHomePage> createState() => _DriverHomePageState();
}

class _DriverHomePageState extends State<DriverHomePage>
    with TickerProviderStateMixin {
  String? _lastPaymentConfirmationSnackbarId;
  DateTime? _trackingStartedAt; // tracking start timestamp
  bool _isStartingTrip = false; // UX: start button state
  Timer? _meterTicker;
  DateTime? _lastMeterDebugAt;

  // Manual (GPS-style) mode when no booking is active
  final TextEditingController _manualFromCtrl = TextEditingController();
  final TextEditingController _manualToCtrl = TextEditingController();
  // --- Manual A→B autocomplete (Mapbox Geocoding) ---
  final FocusNode _fromFocus = FocusNode();
  final FocusNode _toFocus = FocusNode();
  Timer? _fromDebounce;
  Timer? _toDebounce;
  List<_PlaceSuggestion> _fromSuggestions = <_PlaceSuggestion>[];
  List<_PlaceSuggestion> _toSuggestions = <_PlaceSuggestion>[];
  mb.Point? _manualFromPoint;
  mb.Point? _manualToPoint;

  // Ride mode (driving vs waiting)
  bool _isWaiting = false;
  DateTime? _waitStartedAt;
  Duration _waitElapsed = Duration.zero;

  // Pricing (UI-only fallback; worker remains source of truth)
  static const double _fallbackStartFee = 3.0;
  static const double _fallbackPerKm =
      1.50; // placeholder until worker streams live rates
  static const double _fallbackWaitPerMin =
      40.0 / 60.0; // €40/h = €0.666.../min

  final _scaffoldKey = GlobalKey<ScaffoldState>();

  List<BookingItem> _bookings = [];
  bool _loadingBookings = true;
  String? _bookingsError;
  final Set<String> _bookingActionInFlight = <String>{};
  final Map<String, String> _bookingStatusOverrides = <String, String>{};
  final Set<String> _deletedBookingIds = <String>{};
  final ValueNotifier<int> _bookingsUiVersion = ValueNotifier<int>(0);

  Timer? _bookingPollTimer; // auto-refresh bookings
  Future<void>? _bookingsRefreshInFlight;
  DateTime? _lastBookingsRefreshAt;
  DateTime? _lastStatusTriggeredRefreshAt;
  DateTime? _lastManualRefreshAt;
  bool _bookingsHubVisible = false;
  int? _activeBookingPollIntervalMs;
  static const Duration _bookingsPollIntervalFastList = Duration(seconds: 9);
  static const Duration _bookingsPollIntervalSafeLive = Duration(seconds: 25);
  static const Duration _bookingsMinRefreshIntervalFastList = Duration(
    seconds: 8,
  );
  static const Duration _bookingsMinRefreshIntervalSafeLive = Duration(
    seconds: 20,
  );
  static const Duration _manualRefreshCooldown = Duration(seconds: 4);
  static const Duration _statusRefreshCooldown = Duration(seconds: 8);
  int _activeBookingRefreshTimerCount = 0;

  // Boot splash (logo on dark background + loader)
  bool _bootSplashVisible = true;

  bool _showBootSplash = true; // alias for older/other UI refs
  bool _bootMinElapsed = false;
  bool _bootFirstLoadDone = false;
  DateTime? _bootStartedAt;

  // Active trip state
  String? _activeTripId;
  String? _activeDirectTripId;
  BookingItem? _activeBooking;
  bool _directRideActive = false;
  bool _directTripStartWorkerOk = false;
  bool _directTripStopWorkerOk = false;
  String? _directRideDestinationText;
  _LonLat? _directRideDestinationPoint;

  // Location tracking
  StreamSubscription<geo.Position>? _posSub;
  int _activeGeolocatorSubscriptionCount = 0;
  geo.Position? _lastPos;
  geo.Position? _startPos;
  double _kmDriven = 0.0;

  // Ping status
  String _lastPing = '—';
  int _pingCount = 0;

  // Map controller
  mb.MapboxMap? _map;
  mb.PointAnnotationManager? _driverPointManager;
  mb.PointAnnotationManager? _pinsPointManager;
  mb.PolylineAnnotationManager? _routeLineManager;
  String _activeMapStyleUri = '';

  mb.PointAnnotation? _driverMarker;
  mb.PointAnnotation? _pickupPin;
  mb.PointAnnotation? _dropoffPin;
  mb.PolylineAnnotation? _routeLineOutline;
  mb.PolylineAnnotation? _routeLine;
  String _driverMarkerIcon = 'triangle-15';
  late final Widget _stableMapWidget;
  String? _pendingMapStyleUri;
  DateTime? _lastMapWidgetBuildLogAt;
  DateTime? _lastDriverBuildLogAt;

  // Splash animations (premium boot feel)
  late final AnimationController _splashAnimCtrl;
  late final Animation<double> _splashPulse;

  // Active HUD pulse (only meaningful when tracking)
  late final AnimationController _activePulseCtrl;
  late final Animation<double> _activePulse;
  // UI/Camera
  bool _followCar = false;
  _CameraMode _cameraMode = _CameraMode.overview;
  MapThemeMode? _mapThemeOverride;
  bool _navigationWakelockEnabled = false;
  bool _hasSwitchedToFollow = false;
  double _lastKnownBearing = 0.0;
  bool _allowOverviewCamera = false;
  DateTime? _lastFollowCameraAt;
  bool _followCameraInFlight = false;

  // Route stats
  List<_LonLat> _routeCoords = [];
  double? _routeKm;
  int? _routeDurationSec;
  String _lastPinsDrawSignature = '';
  DateTime? _lastPinsDrawAt;
  String _lastRouteDrawSignature = '';
  DateTime? _lastRouteDrawAt;
  static const Duration _routeDrawDebounce = Duration(seconds: 2);
  _RideRoutePhase _routePhase = _RideRoutePhase.trip;
  List<_NavStep> _routeSteps = const <_NavStep>[];
  int _nextStepIndex = 0;
  String? _nextNavInstruction;
  String? _nextNavStreet;
  double? _nextNavDistanceM;
  String? _nextNavType;
  String? _nextNavModifier;
  bool _navStepsLoading = false;
  double _uiArrowBearing = 0.0;
  _RouteSnap? _lastRouteSnap;
  double? _lastMovementBearing;
  bool _useMatchedVisual = false;
  int _matchEnterHits = 0;
  int _matchExitHits = 0;
  double? _lastVisualProgressM;
  bool _routeLineProgressTrimmed = false;
  double _lastRouteLineTrimProgressM = 0.0;
  DateTime? _lastRouteLineTrimAt;
  double _lastMarkerLagM = 0.0;
  final Map<String, DateTime> _lastNavDebugAt = <String, DateTime>{};
  bool _offRouteLikely = false;
  int _offRouteHitCount = 0;
  int _routeCleanupEpoch = 0;
  int _mapRedrawCountThisMinute = 0;
  int _routeRedrawCountThisMinute = 0;
  Timer? _renderDebugWindowTimer;

  void _resetNavProgressState({bool clearRoute = false}) {
    if (clearRoute) {
      _routeCoords = [];
      _routeKm = null;
      _routeDurationSec = null;
    }
    _routeSteps = const <_NavStep>[];
    _nextStepIndex = 0;
    _nextNavInstruction = null;
    _nextNavStreet = null;
    _nextNavDistanceM = null;
    _nextNavType = null;
    _nextNavModifier = null;
    _lastRouteSnap = null;
    _lastMovementBearing = null;
    _useMatchedVisual = false;
    _matchEnterHits = 0;
    _matchExitHits = 0;
    _lastVisualProgressM = null;
    _routeLineProgressTrimmed = false;
    _lastRouteLineTrimProgressM = 0.0;
    _lastRouteLineTrimAt = null;
    _lastMarkerLagM = 0.0;
    _offRouteHitCount = 0;
    _offRouteLikely = false;
  }

  bool _isRouteTaskStillValid({
    required int epoch,
    String? expectedBookingId,
    bool requireDirectRide = false,
  }) {
    if (epoch != _routeCleanupEpoch) return false;
    if (requireDirectRide && !_directRideActive) return false;
    if (expectedBookingId != null) {
      final activeId = _activeBooking?.bookingId;
      if (activeId == null || activeId != expectedBookingId) return false;
    }
    return true;
  }

  Future<void> _clearActiveRouteAndNavigationState({
    required String reason,
    String? bookingId,
    bool clearActiveSelection = true,
  }) async {
    final activeBookingId = _activeBooking?.bookingId;
    final hasPolylineBefore = _routeLine != null || _routeLineOutline != null;
    final routeCoordsBefore = _routeCoords.length;
    final navStepsBefore = _routeSteps.length;
    if (!clearActiveSelection &&
        !hasPolylineBefore &&
        routeCoordsBefore == 0 &&
        navStepsBefore == 0) {
      return;
    }

    try {
      if (_routeLineManager != null) {
        if (_routeLineOutline != null) {
          await _routeLineManager!.delete(_routeLineOutline!);
        }
        if (_routeLine != null) {
          await _routeLineManager!.delete(_routeLine!);
        }
      }
      _routeLineOutline = null;
      _routeLine = null;

      if (_pinsPointManager != null) {
        if (_pickupPin != null) {
          await _pinsPointManager!.delete(_pickupPin!);
        }
        if (_dropoffPin != null) {
          await _pinsPointManager!.delete(_dropoffPin!);
        }
      }
      _pickupPin = null;
      _dropoffPin = null;
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _routeCleanupEpoch++;
      _resetNavProgressState(clearRoute: true);
      _routePhase = _RideRoutePhase.trip;
      _navStepsLoading = false;
      _cameraMode = _CameraMode.overview;
      _hasSwitchedToFollow = false;
      _followCar = false;
      _allowOverviewCamera = false;
      if (clearActiveSelection) {
        _activeTripId = null;
        _activeDirectTripId = null;
        _activeBooking = null;
        _directRideActive = false;
        _directRideDestinationText = null;
        _directRideDestinationPoint = null;
        _lastPing = '—';
        _pingCount = 0;
        _kmDriven = 0.0;
        _trackingStartedAt = null;
        _isWaiting = false;
        _waitStartedAt = null;
        _waitElapsed = Duration.zero;
      }
    });
    _setNavigationWakelock(false);
    await _applyMapStyleForMode();
    if (!_liveRideActive) {
      _startBookingPolling(reason: 'route_state_cleared');
    }
  }

  bool _isClosedRideStatus(String? rawStatus) {
    final s = (rawStatus ?? '').trim().toUpperCase();
    return s == 'COMPLETED' || s == 'CANCELLED' || s == 'DELETED';
  }

  String? _effectiveStatusFor(BookingItem b) {
    return _bookingStatusOverrides[b.bookingId] ?? b.status;
  }

  Map<String, dynamic> _bookingScopeViewFor(BookingItem b) {
    return <String, dynamic>{
      ...b.details,
      'booking_id': b.bookingId,
      'bookingId': b.bookingId,
      if (b.details['booking'] is! Map)
        'booking': <String, dynamic>{...b.details},
    };
  }

  bool _canOperateBookingWithGuard(
    Map<String, dynamic> booking, {
    required String action,
  }) {
    final allowed = _canActiveDriverOperateBooking(booking);
    final bookingId =
        _bookingScopeFirstText(booking, const [
          ['booking_id'],
          ['bookingId'],
          ['id'],
          ['booking', 'booking_id'],
          ['booking', 'bookingId'],
        ]) ??
        'unknown';
    final assignedVehicleId =
        _bookingScopeFirstText(booking, const [
          ['assigned_vehicle_id'],
          ['assignedVehicleId'],
          ['vehicle_id'],
          ['vehicleId'],
          ['booking', 'assigned_vehicle_id'],
          ['booking', 'assignedVehicleId'],
          ['booking', 'vehicle_id'],
          ['booking', 'vehicleId'],
        ]) ??
        '';
    final activeDriverId = _resolvedActiveDriverIdForScope();
    if (!allowed) {
      debugPrint(
        '[DRIVER_SCOPE][BLOCK] action=$action booking_id=$bookingId assigned_vehicle_id=$assignedVehicleId active_driver_id=$activeDriverId allowed=false',
      );
      _toast(_driverOwnershipBlockedMessage());
      return false;
    }
    return true;
  }

  List<BookingItem> get _visibleBookings => _bookings
      .where((b) => !_deletedBookingIds.contains(b.bookingId))
      .where((b) => !_isClosedRideStatus(_effectiveStatusFor(b)))
      .where((b) {
        final role = appRoleNotifier.value;
        if (role != AppRole.driver) return true;
        if (kDriverAllowAllCompanyRidesDebug) return true;
        final booking = _bookingScopeViewFor(b);
        final allowed =
            _bookingBelongsToActiveDriver(booking) ||
            (kDriverCanSeeUnassignedRides && _bookingIsUnassigned(booking));
        final bookingId = b.bookingId;
        final assignedVehicleId =
            _bookingScopeFirstText(booking, const [
              ['assigned_vehicle_id'],
              ['assignedVehicleId'],
              ['vehicle_id'],
              ['vehicleId'],
              ['booking', 'assigned_vehicle_id'],
              ['booking', 'assignedVehicleId'],
              ['booking', 'vehicle_id'],
              ['booking', 'vehicleId'],
            ]) ??
            '';
        debugPrint(
          '[DRIVER_SCOPE][FILTER] booking_id=$bookingId assigned_vehicle_id=$assignedVehicleId active_driver_id=${_resolvedActiveDriverIdForScope()} allowed=$allowed',
        );
        return allowed;
      })
      .toList();

  void _markBookingsUiDirty() {
    _bookingsUiVersion.value = _bookingsUiVersion.value + 1;
  }

  bool get _mapSupported => !kIsWindows && !kIsWeb;
  bool get kIsWindows => !kIsWeb && Platform.isWindows;
  bool _isAssetRef(String v) => v.trim().toLowerCase().startsWith('assets/');

  void _setNavigationWakelock(bool enabled) {
    if (_navigationWakelockEnabled == enabled) return;
    _navigationWakelockEnabled = enabled;
    final op = enabled ? WakelockPlus.enable() : WakelockPlus.disable();
    unawaited(
      op.catchError((Object e, StackTrace st) {
        debugPrint('[WAKELOCK][WARN] enabled=$enabled error=$e');
      }),
    );
  }

  void _onAppLanguageChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Widget _tenantLogo({
    required double height,
    BoxFit fit = BoxFit.contain,
    Widget? fallback,
  }) {
    return ValueListenableBuilder<BusinessSettingsState>(
      valueListenable: businessSettingsNotifier,
      builder: (context, s, _) {
        final ref = s.logoAssetPath.trim().isNotEmpty
            ? s.logoAssetPath.trim()
            : kFluxidiLogoAsset;
        if (_isAssetRef(ref)) {
          return Image.asset(
            ref,
            height: height,
            fit: fit,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, __, ___) =>
                fallback ??
                Text(
                  kCompanyName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
          );
        }
        if (kIsWeb) {
          return Image.network(
            ref,
            height: height,
            fit: fit,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, __, ___) =>
                fallback ??
                const Icon(Icons.local_taxi, size: 72, color: Colors.white70),
          );
        }
        return Image.file(
          File(ref),
          height: height,
          fit: fit,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, __, ___) =>
              fallback ??
              const Icon(Icons.local_taxi, size: 72, color: Colors.white70),
        );
      },
    );
  }

  // ===============================
  // JSON helpers (local)
  // ===============================
  dynamic _getNested(dynamic root, List<String> path) {
    dynamic cur = root;
    for (final k in path) {
      if (cur is Map && cur.containsKey(k)) {
        cur = cur[k];
      } else {
        return null;
      }
    }
    return cur;
  }

  int? _toIntOrNullLocal(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse(v.toString());
  }

  // Best-effort: hydrate missing booking fields via Tracking API Worker /track/booking (GET).
  // This endpoint exists on fluxidi-tracking-api (V2):
  //   GET /track/booking?booking_id=TEST-001
  // and returns pickup/dropoff + session status + last ping.
  Future<void> _hydrateActiveBookingDetails(String bookingId) async {
    try {
      final uri = _withActiveBookingScope(
        kWorkerBaseUrl,
        kGetBookingPath,
        extraQuery: <String, String>{'booking_id': bookingId},
      );
      final res = await http
          .get(uri, headers: _headers(admin: true))
          .timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) return;

      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) return;
      if (decoded['ok'] != true) return;

      // Tracking API returns flat fields
      final pickup = decoded['pickup']?.toString();
      final dropoff = decoded['dropoff']?.toString();
      final sessionId = decoded['session_id']?.toString();
      final status = decoded['status']?.toString();

      if (!mounted) return;

      setState(() {
        if (_activeBooking != null && _activeBooking!.bookingId == bookingId) {
          _activeBooking = _activeBooking!.copyWith(
            from: pickup ?? _activeBooking!.from,
            to: dropoff ?? _activeBooking!.to,
            sessionId: sessionId ?? _activeBooking!.sessionId,
            status: status ?? _activeBooking!.status,
            details: <String, dynamic>{
              ..._activeBooking!.details,
              'tracking_booking': decoded,
            },
          );
        }

        final idx = _bookings.indexWhere((x) => x.bookingId == bookingId);
        if (idx >= 0) {
          _bookings[idx] = _bookings[idx].copyWith(
            from: pickup ?? _bookings[idx].from,
            to: dropoff ?? _bookings[idx].to,
            sessionId: sessionId ?? _bookings[idx].sessionId,
            status: status ?? _bookings[idx].status,
            details: <String, dynamic>{
              ..._bookings[idx].details,
              'tracking_booking': decoded,
            },
          );
        }
      });
    } catch (_) {
      // silent best-effort
    }
  }

  @override
  void initState() {
    super.initState();
    debugPrint('[MAP][HOSTING_MODE] mode=HC textureView=true');
    final initialStyle = _styleForMode(_cameraMode);
    _activeMapStyleUri = initialStyle;
    _stableMapWidget = mb.MapWidget(
      key: const ValueKey('mapbox_map'),
      onMapCreated: _onMapCreated,
      textureView: true,
      androidHostingMode: mb.AndroidPlatformViewHostingMode.HC,
      styleUri: initialStyle,
      cameraOptions: mb.CameraOptions(
        center: _mbPoint(3.62, 50.78),
        zoom: 12.0,
      ),
    );
    appLanguageNotifier.addListener(_onAppLanguageChanged);
    fluxidiPendingPaymentNotifier.addListener(_onPendingPaymentStatusChanged);

    _splashAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _splashPulse = CurvedAnimation(
      parent: _splashAnimCtrl,
      curve: Curves.easeInOut,
    );

    _activePulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat(reverse: true);
    _activePulse = CurvedAnimation(
      parent: _activePulseCtrl,
      curve: Curves.easeInOut,
    );

    _bootStartedAt = DateTime.now();
    // Minimum splash duration so it feels intentional (not a flicker)
    // Christophe wants it to linger a bit longer for a more premium feel.
    Timer(const Duration(milliseconds: 8000), () {
      if (!mounted) return;
      _bootMinElapsed = true;
      _maybeHideBootSplash();
    });
    _refreshBookings(trigger: 'init_boot');
    _startBookingPolling(reason: 'init');
    _renderDebugWindowTimer?.cancel();
    _renderDebugWindowTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      debugPrint(
        '[RIDES][DEBUG_COUNTERS][MINUTE] bookingTimers=$_activeBookingRefreshTimerCount geolocatorSubs=$_activeGeolocatorSubscriptionCount mapRedrawPerMin=$_mapRedrawCountThisMinute routeRedrawPerMin=$_routeRedrawCountThisMinute',
      );
      _mapRedrawCountThisMinute = 0;
      _routeRedrawCountThisMinute = 0;
    });
  }

  // ---------------------------------------------------------------------------
  // Mollie return-to-app + payment finalization fallback
  // ---------------------------------------------------------------------------
  // The deep-link listener, lifecycle observer, and /pay/status reconciliation
  // now live in `PaymentReturnCoordinator` (lib/payment_return.dart) and are
  // started once from main(), so they don't depend on this State being mounted.
  void _onPendingPaymentStatusChanged() {
    final pending = fluxidiPendingPaymentNotifier.value;
    if (!mounted || pending == null) return;
    if (pending.status != FluxidiPaymentStatus.confirmed) return;
    if (_lastPaymentConfirmationSnackbarId == pending.paymentBookingId) return;
    _lastPaymentConfirmationSnackbarId = pending.paymentBookingId;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _tr(
            nl: 'Betaling bevestigd. Je boeking is bevestigd.',
            en: 'Payment confirmed. Your booking is confirmed.',
            fr: 'Paiement confirme. Votre reservation est confirmee.',
            es: 'Pago confirmado. Tu reserva esta confirmada.',
          ),
        ),
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Preload the splash logo so we don't hit the errorBuilder fallback on first frame.
    // If the asset path is wrong, Flutter will throw during precache and we'll still fall back.
    unawaited(
      precacheImage(AssetImage(kFluxidiLogoAsset), context).catchError((_) {}),
    );
  }

  @override
  void dispose() {
    debugPrint('[MAP][DISPOSE] mounted=$mounted style=$_activeMapStyleUri');
    _setNavigationWakelock(false);
    appLanguageNotifier.removeListener(_onAppLanguageChanged);
    fluxidiPendingPaymentNotifier.removeListener(
      _onPendingPaymentStatusChanged,
    );
    _bookingsUiVersion.dispose();
    _splashAnimCtrl.dispose();
    _activePulseCtrl.dispose();
    _stopMeterTicker();
    _stopTrackingInternal();
    _stopBookingPolling(reason: 'dispose');
    _renderDebugWindowTimer?.cancel();
    _renderDebugWindowTimer = null;
    _manualFromCtrl.dispose();
    _manualToCtrl.dispose();
    _directRideDestinationText = null;
    _directRideDestinationPoint = null;
    _fromDebounce?.cancel();
    _toDebounce?.cancel();
    _fromFocus.dispose();
    _toFocus.dispose();
    super.dispose();
  }

  Map<String, String> _headers({bool admin = false}) {
    final h = <String, String>{'Content-Type': 'application/json'};
    if (admin && kAdminToken.trim().isNotEmpty) {
      h['x-admin-token'] = kAdminToken.trim();
    }
    return h;
  }

  void _startBookingPolling({required String reason}) {
    if (_liveRideActive) {
      _stopBookingPolling(reason: 'tracking_started');
      return;
    }
    final fastListMode = _bookingsHubVisible && !_liveRideActive;
    final interval = fastListMode
        ? _bookingsPollIntervalFastList
        : _bookingsPollIntervalSafeLive;
    final mode = fastListMode ? 'fast_list' : 'safe_live';
    if (_bookingPollTimer != null &&
        _activeBookingPollIntervalMs == interval.inMilliseconds) {
      return;
    }
    _bookingPollTimer?.cancel();
    debugPrint(
      '[RIDES][POLL][MODE] mode=$mode intervalMs=${interval.inMilliseconds}',
    );
    _bookingPollTimer = Timer.periodic(interval, (_) {
      if (!mounted) return;
      if (_liveRideActive) return;
      _refreshBookings(trigger: 'periodic_poll');
    });
    _activeBookingRefreshTimerCount = 1;
    _activeBookingPollIntervalMs = interval.inMilliseconds;
    debugPrint(
      '[RIDES][POLL][START] reason=$reason activeTimers=$_activeBookingRefreshTimerCount',
    );
  }

  void _stopBookingPolling({required String reason}) {
    if (_bookingPollTimer == null) return;
    _bookingPollTimer?.cancel();
    _bookingPollTimer = null;
    _activeBookingRefreshTimerCount = 0;
    _activeBookingPollIntervalMs = null;
    debugPrint(
      '[RIDES][POLL][STOP] reason=$reason activeTimers=$_activeBookingRefreshTimerCount',
    );
  }

  Future<void> _refreshBookings({
    bool force = false,
    String trigger = 'unknown',
  }) async {
    if (!mounted) return;
    if (_bookingsRefreshInFlight != null) {
      debugPrint('[RIDES][REFRESH][SKIP] reason=in_flight trigger=$trigger');
      return _bookingsRefreshInFlight!;
    }
    final now = DateTime.now();
    final isManualTrigger =
        trigger == 'drawer_manual' || trigger == 'list_manual';
    if (force && isManualTrigger && _lastManualRefreshAt != null) {
      final elapsed = now.difference(_lastManualRefreshAt!);
      if (elapsed < _manualRefreshCooldown) {
        debugPrint(
          '[RIDES][REFRESH][SKIP] reason=manual_cooldown trigger=$trigger elapsedMs=${elapsed.inMilliseconds}',
        );
        return;
      }
    }
    if (force && isManualTrigger) {
      _lastManualRefreshAt = now;
    }

    final fastListMode = _bookingsHubVisible && !_liveRideActive;
    final minInterval = fastListMode
        ? _bookingsMinRefreshIntervalFastList
        : _bookingsMinRefreshIntervalSafeLive;
    final minIntervalReason = fastListMode
        ? 'min_interval_fast_list'
        : 'min_interval_safe_live';
    if (!force && _lastBookingsRefreshAt != null) {
      final elapsed = now.difference(_lastBookingsRefreshAt!);
      if (elapsed < minInterval) {
        debugPrint(
          '[RIDES][REFRESH][SKIP] reason=$minIntervalReason trigger=$trigger elapsedMs=${elapsed.inMilliseconds}',
        );
        return;
      }
    }
    if (force &&
        trigger == 'status_change' &&
        _lastStatusTriggeredRefreshAt != null) {
      final elapsed = now.difference(_lastStatusTriggeredRefreshAt!);
      if (elapsed < _statusRefreshCooldown) {
        debugPrint(
          '[RIDES][REFRESH][SKIP] reason=status_cooldown trigger=$trigger elapsedMs=${elapsed.inMilliseconds}',
        );
        return;
      }
    }
    if (force && trigger == 'status_change') {
      _lastStatusTriggeredRefreshAt = now;
    }
    _lastBookingsRefreshAt = now;
    final task = _performRefreshBookings(trigger: trigger);
    _bookingsRefreshInFlight = task;
    try {
      await task;
    } finally {
      _bookingsRefreshInFlight = null;
    }
  }

  Future<void> _performRefreshBookings({required String trigger}) async {
    if (!mounted) return;
    setState(() {
      _loadingBookings = true;
      _bookingsError = null;
    });
    _markBookingsUiDirty();

    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final primaryUri = _withActiveBookingScope(
        kBookingBaseUrl,
        kListBookingsPath,
        extraQuery: <String, String>{'limit': '50', 't': '$ts'},
      );
      debugPrint('[RIDES][REFRESH][REQ] trigger=$trigger GET $primaryUri');
      final res = await http.get(primaryUri, headers: _headers(admin: true));
      debugPrint(
        '[RIDES][REFRESH][RES] code=${res.statusCode} body=${res.body}',
      );

      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}: ${res.body}');
      }

      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Invalid response');
      }

      // Worker variants:
      // - tracking-api V2: { ok, count, bookings:[...] }
      // - booking-worker tracking bridge: { ok, items:[...] }
      final raw =
          (decoded['bookings'] as List<dynamic>? ??
          decoded['items'] as List<dynamic>? ??
          const []);
      final prevStatusById = <String, String?>{
        for (final b in _bookings) b.bookingId: _effectiveStatusFor(b),
      };
      final items = raw.whereType<Map<String, dynamic>>().map((j) {
        final parsed = BookingItem.fromJson(j);
        final apiStatus = parsed.status?.trim();
        final mergedStatus = (apiStatus != null && apiStatus.isNotEmpty)
            ? apiStatus
            : (prevStatusById[parsed.bookingId] ??
                  _bookingStatusOverrides[parsed.bookingId]);
        return mergedStatus == null
            ? parsed
            : parsed.copyWith(status: mergedStatus);
      }).toList();

      final apiReturnedIds = items.map((e) => e.bookingId).toSet();
      _deletedBookingIds.removeWhere((id) => !apiReturnedIds.contains(id));
      for (final b in items) {
        final apiStatus = b.status?.trim();
        if (apiStatus != null && apiStatus.isNotEmpty) {
          _bookingStatusOverrides[b.bookingId] = apiStatus;
        }
      }

      final parsedStatuses = items
          .map(
            (b) =>
                '${b.shortId}:${(_effectiveStatusFor(b) ?? 'null').toUpperCase()}',
          )
          .join(', ');
      final visibleStatuses = items
          .where((b) => !_deletedBookingIds.contains(b.bookingId))
          .where((b) => !_isClosedRideStatus(_effectiveStatusFor(b)))
          .map(
            (b) =>
                '${b.shortId}:${(_effectiveStatusFor(b) ?? 'null').toUpperCase()}',
          )
          .join(', ');
      final visibleCount = items
          .where((b) => !_deletedBookingIds.contains(b.bookingId))
          .where((b) => !_isClosedRideStatus(_effectiveStatusFor(b)))
          .length;
      debugPrint(
        '[RIDES][REFRESH][PARSED] total=${items.length} visible=$visibleCount all=[$parsedStatuses] visibleOnly=[$visibleStatuses]',
      );

      if (!mounted) return;
      setState(() {
        _bookings = items;
        _loadingBookings = false;
      });
      _markBookingsUiDirty();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bookingsError = e.toString();
        _loadingBookings = false;
      });
      _markBookingsUiDirty();
    } finally {
      _markBootFirstLoadDone();
    }
  }

  /// Open a booking in "ride preview" mode:
  /// - show route in OVERVIEW
  /// - do NOT create a trip_id yet
  /// - driver presses START on the map to begin tracking + streetview/follow cam
  Future<void> _goToRide(BookingItem b) async {
    try {
      if (!_canOperateBookingWithGuard(
        _bookingScopeViewFor(b),
        action: 'open_ride',
      )) {
        return;
      }
      // We are typically called from the Bookings Hub page.
      // UX: return to the main map/cockpit immediately.
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).popUntil((r) => r.isFirst);
      }

      if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
        Navigator.of(context).pop();
      }

      setState(() {
        _activeBooking = b;
        _activeTripId = null;
        _activeDirectTripId = null;
        _directRideActive = false;
        _directRideDestinationText = null;
        _directRideDestinationPoint = null;
        _isStartingTrip = false;
        _routePhase = _RideRoutePhase.toPickup;

        _kmDriven = 0.0;
        _pingCount = 0;
        _lastPing = '—';

        _resetNavProgressState(clearRoute: true);

        _cameraMode = _CameraMode.overview;
        _hasSwitchedToFollow = false;
        _followCar = false;
        _allowOverviewCamera = true;

        _isWaiting = false;
        _waitStartedAt = null;
        _waitElapsed = Duration.zero;

        _trackingStartedAt = null;
      });
      _setNavigationWakelock(true);
      await _applyMapStyleForMode();

      await _hydrateActiveBookingDetails(b.bookingId);
      await _hydrateActiveBookingPrice(b.bookingId);
      await _ensureLocationPermission();
      if (_lastPos == null) {
        try {
          final pos = await geo.Geolocator.getCurrentPosition(
            desiredAccuracy: geo.LocationAccuracy.best,
          );
          if (mounted) {
            setState(() => _lastPos = pos);
          } else {
            _lastPos = pos;
          }
        } catch (_) {
          // best-effort: fallback route logic below remains safe
        }
      }

      // Start location stream for map + marker (pings are guarded by _activeTripId).
      _startTrackingInternal();

      final bb = _activeBooking ?? b;
      await _buildOverviewRoute(bb);

      // Stay in overview mode after opening a booking.
      // Driver explicitly presses START to begin an active tracking session & follow-cam.

      if (mounted) setState(() => _isStartingTrip = false);
    } catch (e) {
      _toast('Open ride failed: $e');
    }
  }

  void _clearActiveSelection() {
    _stopTrackingInternal();
    unawaited(
      _clearActiveRouteAndNavigationState(
        reason: 'manual_clear_selection',
        bookingId: _activeBooking?.bookingId,
        clearActiveSelection: true,
      ),
    );
  }

  Future<void> _startTrip(BookingItem b) async {
    try {
      if (!_canOperateBookingWithGuard(
        _bookingScopeViewFor(b),
        action: 'start_tracking',
      )) {
        return;
      }
      if (mounted) setState(() => _isStartingTrip = true);

      // UX rule: Start in Drawer → Drawer closes → Map becomes primary focus
      if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
        Navigator.of(context).pop();
      }
      final uri = _withActiveBookingScope(kWorkerBaseUrl, kStartTripPath);
      final actorVehicleId = _directRideVehicleId();
      final payload = {
        'booking_id': b.bookingId,
        'driver_id': kDriverId,
        'vehicle_id': actorVehicleId,
        ..._activeBookingScopeQuery(),
        // Optional context (helps debugging / future UI)
        'pickup': (b.from ?? '').toString(),
        'dropoff': (b.to ?? '').toString(),
        ..._driverMutationActorFields(actorVehicleId: actorVehicleId),
      };

      final res = await http
          .post(uri, headers: _headers(admin: true), body: jsonEncode(payload))
          .timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}: ${res.body}');
      }

      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final sessionId = (j['session_id'] ?? j['sessionId'] ?? '').toString();
      if (sessionId.isEmpty)
        throw Exception('No session_id returned by Worker.');

      setState(() {
        _activeTripId = sessionId;
        _activeDirectTripId = null;
        _activeBooking = b;
        _directRideActive = false;
        _directRideDestinationText = null;
        _directRideDestinationPoint = null;
        _routePhase = _RideRoutePhase.trip;
        _kmDriven = 0.0;
        _trackingStartedAt = DateTime.now();
        _pingCount = 0;
        _lastPing = '—';

        _resetNavProgressState(clearRoute: true);

        _cameraMode = _CameraMode.follow;
        _hasSwitchedToFollow = true;
        _followCar = true;
        _allowOverviewCamera = false;

        _isWaiting = false;
        _waitStartedAt = null;
        _waitElapsed = Duration.zero;
      });
      _setNavigationWakelock(true);
      await _applyMapStyleForMode();

      // Fetch canonical booking details (incl. fixed price) for display
      await _hydrateActiveBookingDetails(b.bookingId);
      await _hydrateActiveBookingPrice(b.bookingId);

      await _ensureLocationPermission();

      _startTrackingInternal();
      _startMeterTicker();
      await _forceFollowCameraNow(caller: 'start_trip');
      final bb = _activeBooking ?? b;
      await _buildNavRouteToDestination(bb);
    } catch (e) {
      if (mounted) setState(() => _isStartingTrip = false);
      _toast('Start failed: $e');
    }
  }

  Future<void> _hydrateActiveBookingPrice(String bookingId) async {
    // Pricing is owned by the BOOKING Worker (not the tracking Worker).
    // If the booking isn't known there yet (e.g. TEST-xxx created only in tracking),
    // we just skip without breaking tracking.
    try {
      final uri = _withActiveBookingScope(
        kBookingBaseUrl,
        kTrackingBookingPath,
      );
      final res = await http
          .post(
            uri,
            headers: _headers(admin: true),
            body: jsonEncode(<String, dynamic>{
              'booking_id': bookingId,
              ..._activeBookingScopeQuery(),
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) return;

      final j = jsonDecode(res.body) as Map<String, dynamic>;
      if (j['ok'] != true) return;

      bool isEmptyHydrationValue(dynamic value) {
        if (value == null) return true;
        if (value is String) return value.trim().isEmpty;
        if (value is Map) return value.isEmpty;
        if (value is Iterable) return value.isEmpty;
        return false;
      }

      Map<String, dynamic> mergeNonEmptyDetails(
        Map<String, dynamic> existing,
        Map<String, dynamic> incoming,
      ) {
        final next = <String, dynamic>{...existing};
        for (final entry in incoming.entries) {
          final incomingValue = entry.value;
          if (isEmptyHydrationValue(incomingValue)) continue;
          final existingValue = next[entry.key];
          if (existingValue is Map && incomingValue is Map) {
            next[entry.key] = mergeNonEmptyDetails(
              Map<String, dynamic>.from(existingValue),
              Map<String, dynamic>.from(incomingValue),
            );
          } else {
            next[entry.key] = incomingValue;
          }
        }
        return next;
      }

      if (!mounted) return;
      setState(() {
        if (_activeBooking != null && _activeBooking!.bookingId == bookingId) {
          _activeBooking = _activeBooking!.copyWith(
            details: mergeNonEmptyDetails(_activeBooking!.details, j),
          );
        }
      });

      final record = (j['record'] is Map)
          ? (j['record'] as Map).cast<String, dynamic>()
          : null;
      final quoteSource = j['quote'] ?? record?['quote'];
      final quote = (quoteSource is Map)
          ? quoteSource.cast<String, dynamic>()
          : null;
      final pricing = (quote != null && quote['pricing'] is Map)
          ? (quote['pricing'] as Map).cast<String, dynamic>()
          : null;

      num? pickNum(dynamic v) {
        if (v is num) return v;
        if (v is String) return num.tryParse(v.replaceAll(',', '.'));
        return null;
      }

      // Booking worker /quote shapes we've used across versions:
      // pricing: { price_incl_vat | total_price | total | amount | eur | price }
      // quote:   { price | total | total_price | amount | eur }
      final dynamic pMap = pricing;
      final num? price = (pMap is Map<String, dynamic>)
          ? (pickNum(pMap['price_incl_vat']) ??
                pickNum(pMap['total_price']) ??
                pickNum(pMap['total']) ??
                pickNum(pMap['price']) ??
                pickNum(pMap['amount']) ??
                pickNum(pMap['eur']))
          : null;

      final num? fallbackFromQuote =
          pickNum(quote?['price']) ??
          pickNum(quote?['total_price']) ??
          pickNum(quote?['total']) ??
          pickNum(quote?['amount']) ??
          pickNum(quote?['eur']);

      final num? resolved = price ?? fallbackFromQuote;
      if (resolved == null) return;

      if (!mounted) return;
      setState(() {
        if (_activeBooking != null && _activeBooking!.bookingId == bookingId) {
          _activeBooking = _activeBooking!.copyWith(
            price: resolved,
            currency: 'EUR',
          );
        }
      });
    } catch (_) {
      // silent
    }
  }

  Future<void> _setBookingStatus(BookingItem b, String status) async {
    if (!mounted) return;
    if (!_canOperateBookingWithGuard(
      _bookingScopeViewFor(b),
      action: 'status_$status',
    )) {
      return;
    }
    final bookingId = b.bookingId;
    setState(() => _bookingActionInFlight.add(bookingId));
    _markBookingsUiDirty();
    try {
      final uri = _withActiveBookingScope(
        kBookingBaseUrl,
        '$kUpdateBookingStatusPath/${Uri.encodeComponent(bookingId)}/status',
      );
      final payload = <String, dynamic>{
        'booking_id': bookingId,
        'status': status,
        ..._activeBookingScopeQuery(),
        ..._driverMutationActorFields(
          actorVehicleId: _bookingScopeFirstText(
            _bookingScopeViewFor(b),
            const [
              ['assigned_vehicle_id'],
              ['assignedVehicleId'],
              ['vehicle_id'],
              ['vehicleId'],
              ['booking', 'assigned_vehicle_id'],
              ['booking', 'assignedVehicleId'],
              ['booking', 'vehicle_id'],
              ['booking', 'vehicleId'],
            ],
          ),
        ),
      };
      debugPrint(
        '[RIDES][STATUS][REQ] url=$uri payload=${jsonEncode(payload)}',
      );
      var statusPersistedOnWorker = false;
      try {
        final res = await http
            .post(
              uri,
              headers: _headers(admin: true),
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 12));
        debugPrint(
          '[RIDES][STATUS][RES] code=${res.statusCode} body=${res.body}',
        );
        dynamic decoded;
        try {
          decoded = jsonDecode(res.body);
        } catch (_) {
          decoded = null;
        }
        final ok = decoded is Map ? decoded['ok'] == true : false;
        if (res.statusCode == 200 && ok) {
          statusPersistedOnWorker = true;
        } else {
          throw Exception('HTTP ${res.statusCode}: ${res.body}');
        }
      } catch (e) {
        // Keep safe compatibility with worker versions that don't expose this endpoint.
        debugPrint('[RIDES][STATUS][WARN] fallback-local-only reason=$e');
      }

      if (!mounted) return;
      setState(() {
        _bookingStatusOverrides[bookingId] = status;
        final idx = _bookings.indexWhere((x) => x.bookingId == bookingId);
        if (idx >= 0) {
          _bookings[idx] = _bookings[idx].copyWith(status: status);
        }
        if (_activeBooking?.bookingId == bookingId) {
          _activeBooking = _activeBooking!.copyWith(status: status);
        }
      });
      final normalizedStatus = status.trim().toUpperCase();
      final shouldRouteCleanup =
          _activeBooking?.bookingId == bookingId &&
          !_liveRideActive &&
          (normalizedStatus == 'COMPLETED' ||
              normalizedStatus == 'CANCELLED' ||
              normalizedStatus == 'DELETED');
      if (shouldRouteCleanup) {
        _stopTrackingInternal();
        _stopMeterTicker();
        await _clearActiveRouteAndNavigationState(
          reason: normalizedStatus.toLowerCase(),
          bookingId: bookingId,
          clearActiveSelection: true,
        );
      }
      _markBookingsUiDirty();
      _toast('✅ $status: ${b.shortId}');
      if (!statusPersistedOnWorker) {
        // Fallback for tracking-worker variants that have no status endpoint:
        // removing from tracking index makes closed rides persistently disappear
        // from the "available rides" source after app restart.
        await _archiveClosedRideByDelete(bookingId: bookingId, status: status);
      }
      await _debugFetchBookingSnapshot(
        bookingId: bookingId,
        contextLabel: 'STATUS_AFTER_WRITE',
      );
      final authoritativeFields = await _fetchPaymentFieldsForHistory(
        bookingId,
      );
      if (authoritativeFields.isNotEmpty && mounted) {
        setState(() {
          final idx = _bookings.indexWhere((x) => x.bookingId == bookingId);
          if (idx >= 0) {
            final mergedDetails = _mergeBusinessReferencesIntoSource(
              source: Map<String, dynamic>.from(_bookings[idx].details),
              authoritative: authoritativeFields,
              canonicalBookingId: bookingId,
              tripId: null,
              sourceTag: 'status_after_write_booking_list',
            )..addAll(authoritativeFields);
            _bookings[idx] = _bookings[idx].copyWith(details: mergedDetails);
          }
          if (_activeBooking?.bookingId == bookingId) {
            final mergedDetails = _mergeBusinessReferencesIntoSource(
              source: Map<String, dynamic>.from(_activeBooking!.details),
              authoritative: authoritativeFields,
              canonicalBookingId: bookingId,
              tripId: null,
              sourceTag: 'status_after_write_active_booking',
            )..addAll(authoritativeFields);
            _activeBooking = _activeBooking!.copyWith(details: mergedDetails);
          }
        });
      }
      await _refreshBookings(force: true, trigger: 'status_change');
    } catch (e) {
      _toast('❌ Status update failed: $e');
    } finally {
      if (!mounted) return;
      setState(() => _bookingActionInFlight.remove(bookingId));
      _markBookingsUiDirty();
    }
  }

  Future<void> _deleteBooking(BookingItem b) async {
    if (!mounted) return;
    if (!_canOperateBookingWithGuard(
      _bookingScopeViewFor(b),
      action: 'delete_booking',
    )) {
      return;
    }
    final bookingId = b.bookingId;
    setState(() => _bookingActionInFlight.add(bookingId));
    _markBookingsUiDirty();
    try {
      final uri = _withActiveBookingScope(
        kBookingBaseUrl,
        '$kDeleteBookingPath/${Uri.encodeComponent(bookingId)}/delete',
      );
      final payload = <String, dynamic>{
        'booking_id': bookingId,
        ..._activeBookingScopeQuery(),
        ..._driverMutationActorFields(
          actorVehicleId: _bookingScopeFirstText(
            _bookingScopeViewFor(b),
            const [
              ['assigned_vehicle_id'],
              ['assignedVehicleId'],
              ['vehicle_id'],
              ['vehicleId'],
              ['booking', 'assigned_vehicle_id'],
              ['booking', 'assignedVehicleId'],
              ['booking', 'vehicle_id'],
              ['booking', 'vehicleId'],
            ],
          ),
        ),
      };
      debugPrint(
        '[RIDES][DELETE][REQ] url=$uri payload=${jsonEncode(payload)}',
      );

      final res = await http
          .post(uri, headers: _headers(admin: true), body: jsonEncode(payload))
          .timeout(const Duration(seconds: 15));
      debugPrint(
        '[RIDES][DELETE][RES] code=${res.statusCode} body=${res.body}',
      );

      final j = jsonDecode(res.body);
      if (res.statusCode != 200 || (j is Map && j['ok'] != true)) {
        throw Exception('Worker error: ${res.statusCode} ${res.body}');
      }

      if (!mounted) return;
      setState(() {
        _deletedBookingIds.add(bookingId);
        _bookingStatusOverrides[bookingId] = 'DELETED';
        _bookings.removeWhere((x) => x.bookingId == bookingId);
      });
      if (_activeBooking?.bookingId == bookingId) {
        _stopTrackingInternal();
        _stopMeterTicker();
        await _clearActiveRouteAndNavigationState(
          reason: 'delete',
          bookingId: bookingId,
          clearActiveSelection: true,
        );
      }
      if (!_liveRideActive) _setNavigationWakelock(false);
      _markBookingsUiDirty();
      _toast('🗑️ Verwijderd: ${b.shortId}');
      await _debugFetchBookingSnapshot(
        bookingId: bookingId,
        contextLabel: 'DELETE_AFTER_WRITE',
      );
      await _refreshBookings(force: true, trigger: 'delete_action');
    } catch (e) {
      _toast('❌ Delete failed: $e');
    } finally {
      if (!mounted) return;
      setState(() => _bookingActionInFlight.remove(bookingId));
      _markBookingsUiDirty();
    }
  }

  Future<void> _confirmDelete(BookingItem b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rit verwijderen?'),
        content: Text(
          'This will remove the booking from the list (KV).\n\nID: ${b.bookingId}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, delete'),
          ),
        ],
      ),
    );
    if (ok == true) await _deleteBooking(b);
  }

  Future<void> _archiveClosedRideByDelete({
    required String bookingId,
    required String status,
  }) async {
    try {
      final uri = _withActiveBookingScope(
        kBookingBaseUrl,
        '$kDeleteBookingPath/${Uri.encodeComponent(bookingId)}/delete',
      );
      final payload = <String, dynamic>{
        'booking_id': bookingId,
        ..._activeBookingScopeQuery(),
      };
      debugPrint(
        '[RIDES][STATUS->DELETE][REQ] status=$status url=$uri payload=${jsonEncode(payload)}',
      );
      final res = await http
          .post(uri, headers: _headers(admin: true), body: jsonEncode(payload))
          .timeout(const Duration(seconds: 15));
      debugPrint(
        '[RIDES][STATUS->DELETE][RES] code=${res.statusCode} body=${res.body}',
      );
      dynamic decoded;
      try {
        decoded = jsonDecode(res.body);
      } catch (_) {
        decoded = null;
      }
      final ok = decoded is Map ? decoded['ok'] == true : false;
      if (res.statusCode == 200 && ok) {
        if (!mounted) return;
        setState(() {
          _deletedBookingIds.add(bookingId);
          _bookingStatusOverrides[bookingId] = 'DELETED';
          _bookings.removeWhere((x) => x.bookingId == bookingId);
        });
        _markBookingsUiDirty();
      }
    } catch (e) {
      debugPrint('[RIDES][STATUS->DELETE][WARN] $e');
    }
  }

  Future<void> _debugFetchBookingSnapshot({
    required String bookingId,
    required String contextLabel,
  }) async {
    try {
      final uri = _withActiveBookingScope(
        kBookingBaseUrl,
        '/bookings/${Uri.encodeComponent(bookingId)}',
      );
      final res = await http
          .get(uri, headers: _headers(admin: true))
          .timeout(const Duration(seconds: 12));
      debugPrint(
        '[RIDES][$contextLabel][SNAPSHOT] url=$uri code=${res.statusCode} body=${res.body}',
      );
    } catch (e) {
      debugPrint('[RIDES][$contextLabel][SNAPSHOT][WARN] $e');
    }
  }

  Future<Map<String, dynamic>> _fetchPaymentFieldsForHistory(
    String bookingId,
  ) async {
    Map<String, dynamic> asMap(dynamic value) =>
        value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
    List<dynamic> asList(dynamic value) => value is List ? value : const [];
    String? text(dynamic value) {
      final s = value?.toString().trim();
      if (s == null || s.isEmpty || s.toLowerCase() == 'null') return null;
      return s;
    }

    Map<String, dynamic> parsePayment(dynamic rootRaw) {
      final root = asMap(rootRaw);
      final data = asMap(root['data']);
      final record = asMap(root['record']);
      final booking = asMap(root['booking']);
      final dataRecord = asMap(data['record']);
      final dataBooking = asMap(data['booking']);
      final recordBooking = asMap(record['booking']);
      final dataRecordBooking = asMap(dataRecord['booking']);

      final paymentStatus = text(
        root['payment_status'] ??
            root['paymentStatus'] ??
            record['payment_status'] ??
            record['paymentStatus'] ??
            recordBooking['payment_status'] ??
            recordBooking['paymentStatus'] ??
            booking['payment_status'] ??
            booking['paymentStatus'] ??
            data['payment_status'] ??
            data['paymentStatus'] ??
            dataRecord['payment_status'] ??
            dataRecord['paymentStatus'] ??
            dataBooking['payment_status'] ??
            dataBooking['paymentStatus'] ??
            dataRecordBooking['payment_status'] ??
            dataRecordBooking['paymentStatus'],
      );
      final paidAt = text(
        root['paid_at'] ??
            root['paidAt'] ??
            record['paid_at'] ??
            record['paidAt'] ??
            booking['paid_at'] ??
            booking['paidAt'] ??
            data['paid_at'] ??
            data['paidAt'] ??
            dataRecord['paid_at'] ??
            dataRecord['paidAt'] ??
            dataBooking['paid_at'] ??
            dataBooking['paidAt'],
      );
      final paymentProvider = text(
        root['payment_provider'] ??
            root['paymentProvider'] ??
            record['payment_provider'] ??
            record['paymentProvider'] ??
            booking['payment_provider'] ??
            booking['paymentProvider'] ??
            data['payment_provider'] ??
            data['paymentProvider'] ??
            dataRecord['payment_provider'] ??
            dataRecord['paymentProvider'] ??
            dataBooking['payment_provider'] ??
            dataBooking['paymentProvider'],
      );
      final paymentId = text(
        root['payment_id'] ??
            root['paymentId'] ??
            record['payment_id'] ??
            record['paymentId'] ??
            booking['payment_id'] ??
            booking['paymentId'] ??
            data['payment_id'] ??
            data['paymentId'] ??
            dataRecord['payment_id'] ??
            dataRecord['paymentId'] ??
            dataBooking['payment_id'] ??
            dataBooking['paymentId'],
      );
      final maps = _referenceLookupMaps(<Map<String, dynamic>>[
        root,
        data,
        record,
        booking,
        dataRecord,
        dataBooking,
        recordBooking,
        dataRecordBooking,
      ]);
      final refs = _extractBusinessReferenceAliasesFromMaps(maps);

      return <String, dynamic>{
        if (paymentStatus != null) ...{
          'payment_status': paymentStatus,
          'paymentStatus': paymentStatus,
        },
        if (paidAt != null) ...{'paid_at': paidAt, 'paidAt': paidAt},
        if (paymentProvider != null) ...{
          'payment_provider': paymentProvider,
          'paymentProvider': paymentProvider,
        },
        if (paymentId != null) ...{
          'payment_id': paymentId,
          'paymentId': paymentId,
        },
        if (refs.receipt != null) ...{
          'receipt_reference': refs.receipt,
          'receiptReference': refs.receipt,
        },
        if (refs.planning != null) ...{
          'planning_reference': refs.planning,
          'planningReference': refs.planning,
        },
        if (refs.publicBooking != null) ...{
          'public_booking_reference': refs.publicBooking,
          'publicBookingReference': refs.publicBooking,
        },
        if (refs.booking != null) ...{
          'booking_reference': refs.booking,
          'bookingReference': refs.booking,
        },
        if (refs.publicRef != null) ...{
          'public_reference': refs.publicRef,
          'publicReference': refs.publicRef,
        },
      };
    }

    Future<Map<String, dynamic>> fetchAndParse(Uri uri) async {
      final res = await http
          .get(uri, headers: _headers(admin: true))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode < 200 || res.statusCode >= 300)
        return <String, dynamic>{};
      final decoded = jsonDecode(res.body);
      if (decoded is! Map) return <String, dynamic>{};

      final root = Map<String, dynamic>.from(decoded);
      var parsed = parsePayment(root);
      if (parsed.isNotEmpty) return parsed;

      // Fallback shape: /bookings?limit=... returns a list under items/data/items.
      final candidateLists = <List<dynamic>>[
        asList(root['items']),
        asList(asMap(root['data'])['items']),
        asList(root['bookings']),
        asList(asMap(root['data'])['bookings']),
      ];
      for (final list in candidateLists) {
        for (final raw in list) {
          final item = asMap(raw);
          final itemBookingId = text(
            item['booking_id'] ?? item['bookingId'] ?? item['id'],
          );
          if (itemBookingId == null || itemBookingId.trim() != bookingId)
            continue;
          parsed = parsePayment(item);
          if (parsed.isNotEmpty) return parsed;
        }
      }
      return <String, dynamic>{};
    }

    try {
      final byId = _withActiveBookingScope(
        kBookingBaseUrl,
        '/bookings/${Uri.encodeComponent(bookingId)}',
      );
      final parsedById = await fetchAndParse(byId);
      if (parsedById.isNotEmpty) return parsedById;
    } catch (_) {}

    try {
      final listUrl = _withActiveBookingScope(
        kBookingBaseUrl,
        '/bookings',
        extraQuery: <String, String>{
          'limit': '200',
          't': '${DateTime.now().millisecondsSinceEpoch}',
        },
      );
      final parsedList = await fetchAndParse(listUrl);
      if (parsedList.isNotEmpty) return parsedList;
    } catch (_) {}

    return <String, dynamic>{};
  }

  void _enterWaitMode() {
    if (!_liveRideActive) return;
    if (_isWaiting) return;
    setState(() {
      _isWaiting = true;
      _waitStartedAt = DateTime.now();
    });
    debugPrint(
      '[METER][WAIT_START] km=${_kmDriven.toStringAsFixed(3)} waitSec=${_effectiveWaitElapsed.inSeconds} total=${_liveMeterTotalEur.toStringAsFixed(2)}',
    );
    _startMeterTicker();
    unawaited(
      _sendDirectTripWaitEvent(
        path: kDirectTripWaitStartPath,
        logLabel: 'WAIT_START',
        timestampKey: 'client_wait_started_at',
      ),
    );
  }

  void _exitWaitMode() {
    if (!_liveRideActive) return;
    if (!_isWaiting) return;
    final started = _waitStartedAt;
    setState(() {
      _isWaiting = false;
      _waitStartedAt = null;
      if (started != null) {
        _waitElapsed += DateTime.now().difference(started);
      }
    });
    debugPrint(
      '[METER][WAIT_RESUME] km=${_kmDriven.toStringAsFixed(3)} waitSec=${_effectiveWaitElapsed.inSeconds} total=${_liveMeterTotalEur.toStringAsFixed(2)}',
    );
    _startMeterTicker();
    unawaited(
      _sendDirectTripWaitEvent(
        path: kDirectTripWaitEndPath,
        logLabel: 'WAIT_END',
        timestampKey: 'client_wait_ended_at',
      ),
    );
  }

  void _startMeterTicker() {
    _meterTicker?.cancel();
    if (!_liveRideActive) return;
    _meterTicker = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_liveRideActive) {
        _meterTicker?.cancel();
        _meterTicker = null;
        return;
      }
      _debugLiveMeter(reason: 'ticker');
      setState(() {});
    });
  }

  void _stopMeterTicker() {
    _meterTicker?.cancel();
    _meterTicker = null;
  }

  Duration get _effectiveWaitElapsed {
    if (_isWaiting && _waitStartedAt != null) {
      return _waitElapsed + DateTime.now().difference(_waitStartedAt!);
    }
    return _waitElapsed;
  }

  bool get _liveRideActive => _activeTripId != null || _directRideActive;
  bool get _directRideDraft =>
      !_directRideActive &&
      _activeTripId == null &&
      _activeBooking == null &&
      (_directRideDestinationText ?? '').trim().isNotEmpty;

  double? get _fixedBookingPriceEur {
    final b = _activeBooking;
    if (b == null) return null;
    final p = b.price;
    if (p is num) return p.toDouble();
    return null;
  }

  double get _liveMeterTotalEur {
    final km = _kmDriven;
    final waitMin = _effectiveWaitElapsed.inMilliseconds / 60000.0;
    return _fallbackStartFee +
        (km * _fallbackPerKm) +
        (waitMin * _fallbackWaitPerMin);
  }

  void _debugLiveMeter({required String reason}) {
    final now = DateTime.now();
    final last = _lastMeterDebugAt;
    if (last != null && now.difference(last).inSeconds < 5) return;
    _lastMeterDebugAt = now;
    final waitMin = _effectiveWaitElapsed.inMilliseconds / 60000.0;
    final kmCost = _kmDriven * _fallbackPerKm;
    final waitCost = waitMin * _fallbackWaitPerMin;
    final total = _fallbackStartFee + kmCost + waitCost;
    debugPrint(
      '[METER][$reason] waiting=$_isWaiting km=${_kmDriven.toStringAsFixed(3)} kmCost=${kmCost.toStringAsFixed(2)} waitSec=${_effectiveWaitElapsed.inSeconds} waitCost=${waitCost.toStringAsFixed(2)} total=${total.toStringAsFixed(2)}',
    );
  }

  /// Price text shown in the cockpit:
  /// - Booking selected: show fixed price if known, otherwise "€ —" (never show live meter for bookings)
  /// - No booking selected: show the live meter total
  String get _displayTotalText {
    if (_liveRideActive) {
      final live = _liveMeterTotalEur;
      return '€ ${live.toStringAsFixed(2)}';
    }
    final fixed = _fixedBookingPriceEur;
    if (_activeBooking != null) {
      if (fixed != null && fixed > 0) return '€ ${fixed.toStringAsFixed(2)}';
      return '€ —';
    }
    final live = _liveMeterTotalEur;
    return '€ ${live.toStringAsFixed(2)}';
  }

  String get _cockpitPriceText =>
      _displayTotalText.replaceFirst('€', '').trim();

  Future<void> _sendDirectTripWaitEvent({
    required String path,
    required String logLabel,
    required String timestampKey,
  }) async {
    final tripId = _activeDirectTripId;
    if (!_directRideActive || tripId == null || tripId.trim().isEmpty) return;
    try {
      final payload = <String, dynamic>{
        'trip_id': tripId,
        ..._activeBookingScopeQuery(),
        timestampKey: DateTime.now().toUtc().toIso8601String(),
      };
      final res = await http
          .post(
            _withActiveBookingScope(kWorkerBaseUrl, path),
            headers: _headers(admin: true),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}: ${res.body}');
      }
      debugPrint('[DIRECT_TRIP][$logLabel][OK] trip_id=$tripId');
    } catch (e) {
      debugPrint('[DIRECT_TRIP][$logLabel][WARN] local wait only: $e');
    }
  }

  String _directRideVehicleId() {
    for (final vehicle in vehiclesNotifier.value) {
      if (vehicle.isActive &&
          vehicle.driverId == kDriverId &&
          vehicle.id.trim().isNotEmpty) {
        return vehicle.id.trim();
      }
    }
    for (final vehicle in vehiclesNotifier.value) {
      if (vehicle.isActive && vehicle.id.trim().isNotEmpty) {
        return vehicle.id.trim();
      }
    }
    if (vehiclesNotifier.value.isNotEmpty) {
      final firstId = vehiclesNotifier.value.first.id.trim();
      if (firstId.isNotEmpty) return firstId;
    }
    return 'vh_1';
  }

  Map<String, dynamic> _currentOriginPayload(geo.Position? pos) {
    if (pos == null) {
      return <String, dynamic>{'label': _receiptText('currentLocation')};
    }
    return <String, dynamic>{
      'label':
          '${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}',
      'lat': pos.latitude,
      'lon': pos.longitude,
    };
  }

  Map<String, dynamic> _plannedBookingDetailsPayload(BookingItem booking) {
    Map<String, dynamic> asMap(dynamic value) =>
        value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
    List<dynamic> asList(dynamic value) => value is List ? value : const [];
    String? text(dynamic value) {
      final s = value?.toString().trim();
      return s == null || s.isEmpty ? null : s;
    }

    num? number(dynamic value) {
      if (value is num) return value;
      if (value is String) return num.tryParse(value.replaceAll(',', '.'));
      return null;
    }

    dynamic pick(List<List<String>> paths) {
      for (final path in paths) {
        dynamic current = booking.details;
        for (final key in path) {
          if (current is Map && current.containsKey(key)) {
            current = current[key];
          } else {
            current = null;
            break;
          }
        }
        if (current != null) return current;
      }
      return null;
    }

    final bookingMap = asMap(booking.details['booking']);
    final detailMap = booking.details;
    final quote = asMap(booking.details['quote']);
    final record = asMap(booking.details['record']);
    final recordQuote = asMap(record['quote']);
    final recordPayload = asMap(record['payload']);
    final payloadQuote = asMap(recordPayload['quote']);
    if (quote.isEmpty && recordQuote.isNotEmpty) {
      quote.addAll(recordQuote);
    }
    if (quote.isEmpty && payloadQuote.isNotEmpty) {
      quote.addAll(payloadQuote);
    }
    final inputs = asMap(quote['inputs']);
    final pricing = asMap(quote['pricing']);
    final pricingMain = asMap(quote['pricing_main'] ?? quote['pricingMain']);
    final pricingReturn = asMap(
      quote['pricing_return'] ?? quote['pricingReturn'],
    );
    final returnInfo = asMap(quote['return']);
    final tracking = asMap(booking.details['tracking_booking']);
    final payload = recordPayload;
    final customer = asMap(payload['customer']);
    final bookingCustomer = asMap(bookingMap['customer']);
    final payloadBooking = asMap(payload['booking']);
    final payloadBookingCustomer = asMap(payloadBooking['customer']);
    final customerName = text(
      bookingMap['custName'] ??
          bookingMap['customer_name'] ??
          bookingMap['customerName'] ??
          bookingMap['name'] ??
          bookingCustomer['name'] ??
          bookingCustomer['full_name'] ??
          detailMap['customer_name'] ??
          detailMap['customerName'] ??
          detailMap['name'] ??
          payload['name'] ??
          payload['customer_name'] ??
          payload['customerName'] ??
          payloadBooking['customer_name'] ??
          payloadBooking['customerName'] ??
          payloadBooking['name'] ??
          payloadBookingCustomer['name'] ??
          payloadBookingCustomer['full_name'] ??
          customer['name'] ??
          customer['full_name'] ??
          pick([
            ['customer', 'name'],
            ['booking', 'customer', 'name'],
            ['record', 'payload', 'customer', 'name'],
            ['record', 'payload', 'booking', 'customer', 'name'],
          ]),
    );
    final customerPhone = text(
      bookingMap['custPhone'] ??
          bookingMap['customer_phone'] ??
          bookingMap['customerPhone'] ??
          bookingMap['phone'] ??
          bookingMap['tel'] ??
          bookingMap['mobile'] ??
          bookingCustomer['phone'] ??
          bookingCustomer['tel'] ??
          bookingCustomer['mobile'] ??
          detailMap['customer_phone'] ??
          detailMap['customerPhone'] ??
          detailMap['phone'] ??
          detailMap['tel'] ??
          detailMap['mobile'] ??
          payload['phone'] ??
          payload['customer_phone'] ??
          payload['customerPhone'] ??
          payload['tel'] ??
          payload['mobile'] ??
          payloadBooking['customer_phone'] ??
          payloadBooking['customerPhone'] ??
          payloadBooking['phone'] ??
          payloadBooking['tel'] ??
          payloadBooking['mobile'] ??
          payloadBookingCustomer['phone'] ??
          payloadBookingCustomer['tel'] ??
          payloadBookingCustomer['mobile'] ??
          customer['phone'] ??
          customer['tel'] ??
          customer['mobile'] ??
          pick([
            ['customer', 'phone'],
            ['booking', 'customer', 'phone'],
            ['record', 'payload', 'customer', 'phone'],
            ['record', 'payload', 'booking', 'customer', 'phone'],
          ]),
    );
    final customerEmail = text(
      bookingMap['custEmail'] ??
          bookingMap['customer_email'] ??
          bookingMap['customerEmail'] ??
          bookingMap['email'] ??
          bookingCustomer['email'] ??
          detailMap['customer_email'] ??
          detailMap['customerEmail'] ??
          detailMap['email'] ??
          payload['email'] ??
          payload['customer_email'] ??
          payload['customerEmail'] ??
          payloadBooking['customer_email'] ??
          payloadBooking['customerEmail'] ??
          payloadBooking['email'] ??
          payloadBookingCustomer['email'] ??
          customer['email'] ??
          pick([
            ['customer', 'email'],
            ['booking', 'customer', 'email'],
            ['record', 'payload', 'customer', 'email'],
            ['record', 'payload', 'booking', 'customer', 'email'],
          ]),
    );
    final customerCountry = text(
      bookingMap['customer_country'] ??
          bookingMap['customerCountry'] ??
          bookingMap['country'] ??
          bookingMap['countryCode'] ??
          bookingMap['country_iso'] ??
          bookingMap['countryIso'] ??
          detailMap['customer_country'] ??
          detailMap['customerCountry'] ??
          detailMap['country'] ??
          detailMap['countryCode'] ??
          detailMap['country_iso'] ??
          detailMap['countryIso'] ??
          payload['customer_country'] ??
          payload['customerCountry'] ??
          payload['country'] ??
          payload['countryCode'] ??
          payload['country_iso'] ??
          payload['countryIso'] ??
          payload['locale'] ??
          payload['language'] ??
          customer['country'] ??
          customer['countryCode'] ??
          customer['countryIso'],
    );
    final phoneCountryCode = text(
      bookingMap['phone_country_code'] ??
          bookingMap['phoneCountryCode'] ??
          detailMap['phone_country_code'] ??
          detailMap['phoneCountryCode'] ??
          payload['phone_country_code'] ??
          payload['phoneCountryCode'] ??
          customer['phone_country_code'] ??
          customer['phoneCountryCode'],
    );
    final dialCode = text(
      bookingMap['dial_code'] ??
          bookingMap['dialCode'] ??
          detailMap['dial_code'] ??
          detailMap['dialCode'] ??
          payload['dial_code'] ??
          payload['dialCode'] ??
          customer['dial_code'] ??
          customer['dialCode'],
    );

    final pickupAddress =
        text(booking.from) ??
        text(quote['from']) ??
        text(inputs['from']) ??
        text(bookingMap['from']) ??
        text(tracking['pickup']);
    final destinationAddress =
        text(booking.to) ??
        text(quote['to']) ??
        text(inputs['to']) ??
        text(bookingMap['to']) ??
        text(tracking['dropoff']);
    final service =
        text(bookingMap['service']) ??
        text(inputs['service']) ??
        text(
          pick([
            ['service'],
          ]),
        );
    final tier =
        text(booking.tier) ?? text(bookingMap['tier']) ?? text(inputs['tier']);
    final scheduledPickup =
        text(booking.pickupIso) ??
        text(bookingMap['pickupStartIso']) ??
        text(bookingMap['pickup_iso']) ??
        text(inputs['pickup_iso']);
    final totalPackage =
        number(bookingMap['price_incl_vat']) ??
        number(pricing['price_incl_vat']) ??
        number(pricing['total_price_incl_vat']) ??
        number(quote['total_price_incl_vat']) ??
        number(quote['price_incl_vat']) ??
        booking.price;
    final segmentPrice = booking.bookingId.endsWith('-R')
        ? (number(bookingMap['price_incl_vat_return']) ??
              number(pricingReturn['price_incl_vat']) ??
              number(returnInfo['price_incl_vat']) ??
              number(asMap(returnInfo['pricing'])['price_incl_vat']))
        : (number(bookingMap['price_incl_vat_main']) ??
              number(pricingMain['price_incl_vat']) ??
              number(quote['price_incl_vat']));
    final returnPickup =
        text(bookingMap['returnPickupIso']) ??
        text(inputs['return_pickup_iso']) ??
        text(
          pick([
            ['return_pickup_iso'],
          ]),
        );
    final returnFrom =
        text(bookingMap['return_from']) ??
        text(inputs['return_from']) ??
        text(returnInfo['from']);
    final returnTo =
        text(bookingMap['return_to']) ??
        text(inputs['return_to']) ??
        text(returnInfo['to']);
    final hasReturnInfo =
        returnPickup != null ||
        returnFrom != null ||
        returnTo != null ||
        returnInfo['enabled'] == true ||
        pricingReturn.isNotEmpty;
    final paymentStatus = text(
      bookingMap['payment_status'] ??
          bookingMap['paymentStatus'] ??
          detailMap['payment_status'] ??
          detailMap['paymentStatus'] ??
          payload['payment_status'] ??
          payload['paymentStatus'] ??
          pick([
            ['payment_status'],
            ['paymentStatus'],
            ['booking', 'payment_status'],
            ['booking', 'paymentStatus'],
          ]),
    );
    final paidAt = text(
      bookingMap['paid_at'] ??
          bookingMap['paidAt'] ??
          detailMap['paid_at'] ??
          detailMap['paidAt'] ??
          payload['paid_at'] ??
          payload['paidAt'],
    );
    final paymentProvider = text(
      bookingMap['payment_provider'] ??
          bookingMap['paymentProvider'] ??
          detailMap['payment_provider'] ??
          detailMap['paymentProvider'] ??
          payload['payment_provider'] ??
          payload['paymentProvider'],
    );
    final paymentId = text(
      bookingMap['payment_id'] ??
          bookingMap['paymentId'] ??
          detailMap['payment_id'] ??
          detailMap['paymentId'] ??
          payload['payment_id'] ??
          payload['paymentId'],
    );

    List<Map<String, dynamic>> normalizeSegments(dynamic raw) {
      final result = <Map<String, dynamic>>[];
      for (final value in asList(raw)) {
        if (value is! Map) continue;
        final segment = Map<String, dynamic>.from(value);
        final from = text(
          segment['from'] ??
              segment['origin'] ??
              segment['start'] ??
              segment['start_address'],
        );
        final to = text(
          segment['to'] ??
              segment['destination'] ??
              segment['end'] ??
              segment['end_address'],
        );
        result.add(<String, dynamic>{
          if (from != null) 'from': from,
          if (to != null) 'to': to,
          if (number(segment['distance_km'] ?? segment['km']) != null)
            'distance_km': number(segment['distance_km'] ?? segment['km']),
          if (number(segment['duration_min'] ?? segment['minutes']) != null)
            'duration_min': number(
              segment['duration_min'] ?? segment['minutes'],
            ),
        });
      }
      return result;
    }

    final routeSegments = normalizeSegments(
      quote['route_segments'] ??
          quote['legs'] ??
          bookingMap['route_segments'] ??
          bookingMap['legs'],
    );
    if (routeSegments.isEmpty &&
        pickupAddress != null &&
        destinationAddress != null) {
      final distance = number(
        quote['distance_km'] ?? bookingMap['distance_km'],
      );
      final duration = number(
        quote['duration_min'] ?? bookingMap['duration_route_min'],
      );
      if (distance != null || duration != null) {
        routeSegments.add(<String, dynamic>{
          'from': pickupAddress,
          'to': destinationAddress,
          if (distance != null) 'distance_km': distance,
          if (duration != null) 'duration_min': duration,
        });
      }
    }
    if (hasReturnInfo) {
      final returnDistance = number(
        returnInfo['distance_km'] ?? bookingMap['return_distance_km'],
      );
      final returnDuration = number(
        returnInfo['duration_min'] ?? bookingMap['return_duration_min'],
      );
      if (returnFrom != null ||
          returnTo != null ||
          returnDistance != null ||
          returnDuration != null) {
        routeSegments.add(<String, dynamic>{
          if (returnFrom != null) 'from': returnFrom,
          if (returnTo != null) 'to': returnTo,
          if (returnDistance != null) 'distance_km': returnDistance,
          if (returnDuration != null) 'duration_min': returnDuration,
          'kind': 'return',
        });
      }
    }
    final refMaps = _referenceLookupMaps(<Map<String, dynamic>>[
      detailMap,
      bookingMap,
      payload,
      quote,
      record,
      recordPayload,
      payloadBooking,
    ]);
    final refs = _extractBusinessReferenceAliasesFromMaps(refMaps);

    return <String, dynamic>{
      if (pickupAddress != null) 'pickup_address': pickupAddress,
      if (destinationAddress != null) 'destination_address': destinationAddress,
      if (scheduledPickup != null) 'scheduled_pickup_at': scheduledPickup,
      if (booking.bookingId.endsWith('-R')) 'subtype': 'Retourrit',
      if (!booking.bookingId.endsWith('-R') && hasReturnInfo)
        'subtype': 'Heenrit',
      if (customerName != null) 'customer_name': customerName,
      if (customerPhone != null) 'customer_phone': customerPhone,
      if (customerEmail != null) 'customer_email': customerEmail,
      if (customerName != null ||
          customerPhone != null ||
          customerEmail != null)
        'customer': <String, dynamic>{
          if (customerName != null) 'name': customerName,
          if (customerPhone != null) 'phone': customerPhone,
          if (customerEmail != null) 'email': customerEmail,
        },
      if (customerCountry != null) 'customer_country': customerCountry,
      if (phoneCountryCode != null) 'phone_country_code': phoneCountryCode,
      if (dialCode != null) 'dial_code': dialCode,
      if (service != null) 'service_type': service,
      if (tier != null) 'tier': tier,
      if (number(booking.pax ?? bookingMap['pax'] ?? inputs['pax']) != null)
        'passengers': number(booking.pax ?? bookingMap['pax'] ?? inputs['pax']),
      if (number(booking.bags ?? bookingMap['bags'] ?? inputs['bags']) != null)
        'luggage_count': number(
          booking.bags ?? bookingMap['bags'] ?? inputs['bags'],
        ),
      if (number(bookingMap['wait_min'] ?? inputs['wait_min']) != null)
        'booked_wait_minutes': number(
          bookingMap['wait_min'] ?? inputs['wait_min'],
        ),
      if ((booking.status ?? '').trim().isNotEmpty)
        'booking_status': booking.status!.trim(),
      if (paymentStatus != null) ...{
        'payment_status': paymentStatus,
        'paymentStatus': paymentStatus,
      },
      if (paidAt != null) ...{'paid_at': paidAt, 'paidAt': paidAt},
      if (paymentProvider != null) ...{
        'payment_provider': paymentProvider,
        'paymentProvider': paymentProvider,
      },
      if (paymentId != null) ...{
        'payment_id': paymentId,
        'paymentId': paymentId,
      },
      if (refs.receipt != null) ...{
        'receipt_reference': refs.receipt,
        'receiptReference': refs.receipt,
      },
      if (refs.planning != null) ...{
        'planning_reference': refs.planning,
        'planningReference': refs.planning,
      },
      if (refs.publicBooking != null) ...{
        'public_booking_reference': refs.publicBooking,
        'publicBookingReference': refs.publicBooking,
      },
      if (refs.booking != null) ...{
        'booking_reference': refs.booking,
        'bookingReference': refs.booking,
      },
      if (refs.publicRef != null) ...{
        'public_reference': refs.publicRef,
        'publicReference': refs.publicRef,
      },
      if (totalPackage != null) 'booking_total_eur': totalPackage,
      if (segmentPrice != null) 'segment_price_eur': segmentPrice,
      if (bookingMap['price_incl_vat_main'] != null ||
          pricingMain['price_incl_vat'] != null)
        'outbound_price_eur': number(
          bookingMap['price_incl_vat_main'] ?? pricingMain['price_incl_vat'],
        ),
      if (bookingMap['price_incl_vat_return'] != null ||
          pricingReturn['price_incl_vat'] != null)
        'return_price_eur': number(
          bookingMap['price_incl_vat_return'] ??
              pricingReturn['price_incl_vat'],
        ),
      if (returnPickup != null) 'return_scheduled_pickup_at': returnPickup,
      if (returnFrom != null || returnTo != null)
        'return_route': [returnFrom, returnTo].whereType<String>().join(' → '),
      if (routeSegments.isNotEmpty) 'route_segments': routeSegments,
      if (asList(
        bookingMap['stops'] ?? inputs['stops'] ?? quote['stops'],
      ).isNotEmpty)
        'stops': asList(
          bookingMap['stops'] ?? inputs['stops'] ?? quote['stops'],
        ).join(' → '),
      if (text(
            bookingMap['extra_service_label'] ?? inputs['extra_service_label'],
          ) !=
          null)
        'extras': text(
          bookingMap['extra_service_label'] ?? inputs['extra_service_label'],
        ),
      if (text(
            bookingMap['message'] ??
                payload['message'] ??
                customer['message'] ??
                pick([
                  ['customer', 'message'],
                ]),
          ) !=
          null)
        'notes': text(
          bookingMap['message'] ??
              payload['message'] ??
              customer['message'] ??
              pick([
                ['customer', 'message'],
              ]),
        ),
      if ((booking.currency ?? '').trim().isNotEmpty)
        'currency': booking.currency!.trim(),
    };
  }

  Future<void> _startDirectTripSessionOnWorker({
    required String destination,
  }) async {
    try {
      final point = _directRideDestinationPoint;
      final destinationPayload = <String, dynamic>{
        'label': destination,
        if (point != null) 'lat': point.lat,
        if (point != null) 'lon': point.lon,
      };
      final payload = <String, dynamic>{
        ..._activeBookingScopeQuery(),
        'driver_id': kDriverId,
        'vehicle_id': _directRideVehicleId(),
        'origin': _currentOriginPayload(_lastPos),
        'destination': destinationPayload,
        'pricing_snapshot': <String, dynamic>{
          'start_fee': _fallbackStartFee,
          'per_km': _fallbackPerKm,
          'wait_per_min': _fallbackWaitPerMin,
          'currency': kDefaultCurrency,
        },
        'client_started_at': (_trackingStartedAt ?? DateTime.now())
            .toUtc()
            .toIso8601String(),
        ..._driverMutationActorFields(actorVehicleId: _directRideVehicleId()),
      };
      final res = await http
          .post(
            _withActiveBookingScope(kWorkerBaseUrl, kStartDirectTripPath),
            headers: _headers(admin: true),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}: ${res.body}');
      }
      final decoded = jsonDecode(res.body);
      if (decoded is! Map || decoded['ok'] != true) {
        throw Exception('Invalid direct trip start response: ${res.body}');
      }
      final tripId = (decoded['trip_id'] ?? '').toString().trim();
      if (tripId.isEmpty) throw Exception('No trip_id returned');
      if (!mounted || !_directRideActive) return;
      setState(() {
        _activeDirectTripId = tripId;
        _directTripStartWorkerOk = true;
        _directTripStopWorkerOk = false;
      });
      debugPrint('[DIRECT_TRIP][START][OK] trip_id=$tripId');
    } catch (e) {
      debugPrint('[DIRECT_TRIP][START][WARN] local-only direct ride: $e');
    }
  }

  Future<double?> _stopDirectTripSessionOnWorker({
    required String tripId,
    required double kmTotal,
    required int waitSecondsTotal,
  }) async {
    try {
      final payload = <String, dynamic>{
        'trip_id': tripId,
        ..._activeBookingScopeQuery(),
        'km_total': kmTotal,
        'wait_seconds_total': waitSecondsTotal,
        'client_stopped_at': DateTime.now().toUtc().toIso8601String(),
        ..._driverMutationActorFields(actorVehicleId: _directRideVehicleId()),
      };
      final res = await http
          .post(
            _withActiveBookingScope(kWorkerBaseUrl, kStopDirectTripPath),
            headers: _headers(admin: true),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}: ${res.body}');
      }
      final decoded = jsonDecode(res.body);
      if (decoded is! Map || decoded['ok'] != true) {
        throw Exception('Invalid direct trip stop response: ${res.body}');
      }
      final totals = decoded['totals'];
      final total = totals is Map ? totals['total_eur'] : null;
      _directTripStopWorkerOk = true;
      if (total is num) return total.toDouble();
      return double.tryParse((total ?? '').toString().replaceAll(',', '.'));
    } catch (e) {
      _directTripStopWorkerOk = false;
      debugPrint('[DIRECT_TRIP][STOP][WARN] using local total: $e');
      return null;
    }
  }

  Future<void> _recordPlannedTripStopOnWorker({
    required BookingItem booking,
    required double kmTotal,
    required int waitSecondsTotal,
    required DateTime? startedAt,
    required DateTime stoppedAt,
  }) async {
    try {
      var bookingDetails = _plannedBookingDetailsPayload(booking);
      final authoritativeFields = await _fetchPaymentFieldsForHistory(
        booking.bookingId,
      );
      if (authoritativeFields.isNotEmpty) {
        bookingDetails = _mergeBusinessReferencesIntoSource(
          source: bookingDetails,
          authoritative: authoritativeFields,
          canonicalBookingId: booking.bookingId,
          tripId: null,
          sourceTag: 'planned_trip_stop_authoritative_fields',
        );
        bookingDetails.addAll(authoritativeFields);
        final existingBooking = bookingDetails['booking'];
        if (existingBooking is Map) {
          final mergedBooking = _mergeBusinessReferencesIntoSource(
            source: Map<String, dynamic>.from(existingBooking),
            authoritative: authoritativeFields,
            canonicalBookingId: booking.bookingId,
            tripId: null,
            sourceTag: 'planned_trip_stop_booking_nested',
          );
          if (authoritativeFields['payment_status'] != null) {
            mergedBooking['payment_status'] =
                authoritativeFields['payment_status'];
            mergedBooking['paymentStatus'] =
                authoritativeFields['payment_status'];
          }
          if (authoritativeFields['paid_at'] != null) {
            mergedBooking['paid_at'] = authoritativeFields['paid_at'];
            mergedBooking['paidAt'] = authoritativeFields['paid_at'];
          }
          if (authoritativeFields['payment_provider'] != null) {
            mergedBooking['payment_provider'] =
                authoritativeFields['payment_provider'];
            mergedBooking['paymentProvider'] =
                authoritativeFields['payment_provider'];
          }
          if (authoritativeFields['payment_id'] != null) {
            mergedBooking['payment_id'] = authoritativeFields['payment_id'];
            mergedBooking['paymentId'] = authoritativeFields['payment_id'];
          }
          bookingDetails['booking'] = mergedBooking;
        }
      }
      final price =
          booking.price ??
          BookingItem._toNumOrNull(bookingDetails['booking_total_eur']);
      final payload = <String, dynamic>{
        'booking_id': booking.bookingId,
        ..._activeBookingScopeQuery(),
        'driver_id': kDriverId,
        'vehicle_id': _directRideVehicleId(),
        'origin': <String, dynamic>{
          'label': (booking.from ?? _receiptText('currentLocation')).toString(),
        },
        'destination': <String, dynamic>{
          'label': (booking.to ?? booking.from ?? booking.shortId).toString(),
        },
        'booking_details': bookingDetails,
        if (startedAt != null)
          'started_at': startedAt.toUtc().toIso8601String(),
        'stopped_at': stoppedAt.toUtc().toIso8601String(),
        'km_total': kmTotal,
        'wait_seconds_total': waitSecondsTotal,
        if (price != null) 'total_eur': price.toDouble(),
        'currency': booking.currency ?? kDefaultCurrency,
        if (bookingDetails['payment_status'] != null)
          'payment_status': bookingDetails['payment_status'],
        if (bookingDetails['paymentStatus'] != null)
          'paymentStatus': bookingDetails['paymentStatus'],
        if (bookingDetails['paid_at'] != null)
          'paid_at': bookingDetails['paid_at'],
        if (bookingDetails['paidAt'] != null)
          'paidAt': bookingDetails['paidAt'],
        if (bookingDetails['payment_provider'] != null)
          'payment_provider': bookingDetails['payment_provider'],
        if (bookingDetails['paymentProvider'] != null)
          'paymentProvider': bookingDetails['paymentProvider'],
        if (bookingDetails['payment_id'] != null)
          'payment_id': bookingDetails['payment_id'],
        if (bookingDetails['paymentId'] != null)
          'paymentId': bookingDetails['paymentId'],
        if (bookingDetails['receipt_reference'] != null)
          'receipt_reference': bookingDetails['receipt_reference'],
        if (bookingDetails['planning_reference'] != null)
          'planning_reference': bookingDetails['planning_reference'],
        if (bookingDetails['public_booking_reference'] != null)
          'public_booking_reference':
              bookingDetails['public_booking_reference'],
        if (bookingDetails['booking_reference'] != null)
          'booking_reference': bookingDetails['booking_reference'],
        if (bookingDetails['public_reference'] != null)
          'public_reference': bookingDetails['public_reference'],
        ..._driverMutationActorFields(actorVehicleId: _directRideVehicleId()),
      };
      final res = await http
          .post(
            _withActiveBookingScope(kWorkerBaseUrl, kRecordPlannedTripStopPath),
            headers: _headers(admin: true),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}: ${res.body}');
      }
      debugPrint('[PLANNED_TRIP][HISTORY][OK] booking=${booking.bookingId}');
    } catch (e) {
      debugPrint(
        '[PLANNED_TRIP][HISTORY][WARN] booking=${booking.bookingId} reason=$e',
      );
    }
  }

  String _complianceRideId({
    required String rideType,
    String? bookingId,
    String? tripId,
    required DateTime stoppedAt,
  }) {
    final seed = (bookingId ?? tripId ?? '').trim();
    final ts = stoppedAt.toUtc().millisecondsSinceEpoch;
    if (seed.isNotEmpty) return 'rlg_${rideType}_${seed}_$ts';
    return 'rlg_${rideType}_$ts';
  }

  String _complianceReceiptReference({
    String? bookingId,
    String? tripId,
    required String rideId,
  }) {
    final booking = (bookingId ?? '').trim();
    if (booking.isNotEmpty) return booking;
    final trip = (tripId ?? '').trim();
    if (trip.isNotEmpty) return 'TRIP-$trip';
    return rideId.trim();
  }

  String _complianceValidationState({
    required String rideType,
    required bool backendConfirmed,
    required String driverId,
    required String receiptReference,
    required DateTime? startedAt,
    required DateTime stoppedAt,
    String? bookingId,
  }) {
    if (driverId.trim().isEmpty ||
        driverId.trim() == kFallbackDriverTrackingId.trim()) {
      return 'blocked';
    }
    if (startedAt == null || startedAt.isAfter(stoppedAt)) return 'blocked';
    if (receiptReference.trim().isEmpty) return 'blocked';
    if (rideType == 'direct' && !backendConfirmed) return 'blocked';
    if (rideType == 'planned' && (bookingId ?? '').trim().isEmpty) {
      return 'incomplete';
    }
    return 'exportable';
  }

  String? _complianceText(dynamic value) {
    final s = value?.toString().trim();
    if (s == null || s.isEmpty || s.toLowerCase() == 'null') return null;
    return s;
  }

  String? _compliancePathText(Map<String, dynamic> root, String path) {
    dynamic cursor = root;
    for (final part in path.split('.')) {
      if (cursor is! Map) return null;
      cursor = cursor[part];
    }
    return _complianceText(cursor);
  }

  String? _firstComplianceText(List<dynamic> candidates) {
    for (final candidate in candidates) {
      final text = _complianceText(candidate);
      if (text != null) return text;
    }
    return null;
  }

  String _normalizeCompliancePaymentStatus(dynamic value) {
    final raw = _complianceText(value);
    if (raw == null) return 'unknown';
    final normalized = raw
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_')
        .trim();
    switch (normalized) {
      case 'paid':
      case 'succeeded':
      case 'success':
      case 'completed':
      case 'settled':
      case 'confirmed':
        return 'paid';
      case 'pending':
      case 'open':
      case 'authorized':
      case 'authorised':
      case 'processing':
        return 'pending';
      case 'failed':
      case 'error':
      case 'declined':
        return 'failed';
      case 'cancelled':
      case 'canceled':
        return 'cancelled';
      case 'unpaid':
      case 'not_paid':
        return 'unpaid';
      case 'unknown':
        return 'unknown';
      default:
        return 'unknown';
    }
  }

  String _normalizeCompliancePaymentMethod(dynamic value) {
    final raw = _complianceText(value);
    if (raw == null) return 'unknown';
    final normalized = raw
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_')
        .trim();
    switch (normalized) {
      case 'cash':
      case 'contant':
        return 'cash';
      case 'qr':
      case 'qr_code':
        return 'qr';
      case 'bancontact':
        return 'bancontact';
      case 'card':
      case 'terminal':
      case 'card_terminal':
        return 'card_terminal';
      case 'payment_link':
      case 'link':
      case 'online':
        return 'payment_link';
      case 'mollie':
        return 'mollie';
      case 'in_car':
      case 'unknown':
        return 'unknown';
      default:
        return 'unknown';
    }
  }

  Map<String, dynamic> _buildCompliancePaymentPayload({
    dynamic status,
    dynamic method,
    dynamic source,
    dynamic provider,
    dynamic paymentId,
    dynamic paidAtUtc,
  }) {
    final normalizedStatus = _normalizeCompliancePaymentStatus(status);
    final normalizedMethod = _normalizeCompliancePaymentMethod(method);
    final sourceText = _complianceText(source);
    final providerText = _complianceText(provider);
    final paymentIdText = _complianceText(paymentId);
    final paidAtText = _complianceText(paidAtUtc);
    final parsedPaidAt = paidAtText == null
        ? null
        : DateTime.tryParse(paidAtText);

    return <String, dynamic>{
      'status': normalizedStatus,
      if (normalizedMethod != 'unknown') 'method': normalizedMethod,
      if (sourceText != null) 'source': sourceText,
      if (providerText != null) 'provider': providerText,
      if (paymentIdText != null) 'payment_id': paymentIdText,
      if (parsedPaidAt != null)
        'paid_at_utc': parsedPaidAt.toUtc().toIso8601String()
      else if (paidAtText != null)
        'paid_at_utc': paidAtText,
    };
  }

  Map<String, dynamic> _buildCompliancePlannedLedgerRecord({
    required BookingItem booking,
    required DateTime? startedAt,
    required DateTime stoppedAt,
    required double kmTotal,
    required int waitSecondsTotal,
    required bool backendConfirmed,
  }) {
    final bookingId = booking.bookingId.trim();
    final driverId = kDriverId.trim();
    final vehicleId = _directRideVehicleId().trim();
    final rideId = _complianceRideId(
      rideType: 'planned',
      bookingId: bookingId,
      stoppedAt: stoppedAt,
    );
    final receiptReference = _complianceReceiptReference(
      bookingId: bookingId,
      rideId: rideId,
    );
    final total = booking.price?.toDouble();
    final details = booking.details;
    final plannedPaymentStatus = _firstComplianceText([
      details['payment_status'],
      details['paymentStatus'],
      _compliancePathText(details, 'booking.payment_status'),
      _compliancePathText(details, 'booking.paymentStatus'),
      _compliancePathText(details, 'mollie.status'),
      _compliancePathText(details, 'record.mollie.status'),
    ]);
    final plannedPaymentMethod = _firstComplianceText([
      details['payment_method'],
      details['paymentMethod'],
      _compliancePathText(details, 'booking.payment_method'),
      _compliancePathText(details, 'booking.paymentMethod'),
    ]);
    final plannedPaymentSource = _firstComplianceText([
      details['payment_source'],
      details['paymentSource'],
      _compliancePathText(details, 'booking.payment_source'),
      _compliancePathText(details, 'booking.paymentSource'),
    ]);
    final plannedPaymentProvider = _firstComplianceText([
      details['payment_provider'],
      details['paymentProvider'],
      _compliancePathText(details, 'booking.payment_provider'),
      _compliancePathText(details, 'booking.paymentProvider'),
    ]);
    final plannedPaymentId = _firstComplianceText([
      details['payment_id'],
      details['paymentId'],
      _compliancePathText(details, 'booking.payment_id'),
      _compliancePathText(details, 'booking.paymentId'),
    ]);
    final plannedPaidAt = _firstComplianceText([
      details['paid_at'],
      details['paidAt'],
      _compliancePathText(details, 'booking.paid_at'),
      _compliancePathText(details, 'booking.paidAt'),
    ]);
    final referenceMaps = _referenceLookupMaps(<Map<String, dynamic>>[details]);
    final planningReference = _pickReferenceAliasFromMaps(referenceMaps, const [
      ['planning_reference'],
      ['planningReference'],
    ]);
    final publicBookingReference = _pickReferenceAliasFromMaps(
      referenceMaps,
      const [
        ['public_booking_reference'],
        ['publicBookingReference'],
        ['booking_reference'],
        ['bookingReference'],
        ['public_reference'],
        ['publicReference'],
      ],
    );
    final bookingReference = _pickReferenceAliasFromMaps(referenceMaps, const [
      ['booking_reference'],
      ['bookingReference'],
    ]);
    final publicReference = _pickReferenceAliasFromMaps(referenceMaps, const [
      ['public_reference'],
      ['publicReference'],
    ]);
    final effectiveReceiptReference = _pickBusinessReference(
      rawSource: details,
      details: details,
      bookingId: bookingId,
      tripId: null,
      legacyFallback: receiptReference,
    );
    final validationState = _complianceValidationState(
      rideType: 'planned',
      backendConfirmed: backendConfirmed,
      driverId: driverId,
      receiptReference: effectiveReceiptReference,
      startedAt: startedAt,
      stoppedAt: stoppedAt,
      bookingId: bookingId,
    );

    return <String, dynamic>{
      'ledger_version': '1.0',
      'ride_id': rideId,
      'ride_type': 'planned',
      'lifecycle_status': 'completed',
      'tenant_id': kOutboundTenantId,
      'company_id': resolvedCompanyId,
      'driver_id': driverId,
      'vehicle_id': vehicleId,
      'booking_id': bookingId,
      'trip_id': null,
      'session_id': _activeTripId,
      'started_at_utc': startedAt?.toUtc().toIso8601String(),
      'ended_at_utc': stoppedAt.toUtc().toIso8601String(),
      'duration_seconds': startedAt == null
          ? null
          : stoppedAt.difference(startedAt).inSeconds,
      'pickup': <String, dynamic>{'label': (booking.from ?? '').trim()},
      'dropoff': <String, dynamic>{'label': (booking.to ?? '').trim()},
      'distance_km': kmTotal,
      'wait_seconds_total': waitSecondsTotal,
      'fare': <String, dynamic>{
        'total_eur': total,
        'currency': booking.currency ?? kDefaultCurrency,
      },
      'payment': _buildCompliancePaymentPayload(
        status: plannedPaymentStatus,
        method: plannedPaymentMethod,
        source: plannedPaymentSource,
        provider: plannedPaymentProvider,
        paymentId: plannedPaymentId,
        paidAtUtc: plannedPaidAt,
      ),
      'references': <String, dynamic>{
        'receipt_reference': effectiveReceiptReference,
        'planning_reference': planningReference,
        'public_booking_reference': publicBookingReference,
        'booking_reference': bookingReference,
        'public_reference': publicReference,
        'invoice_reference': null,
      },
      'provenance': <String, dynamic>{
        'backend_confirmed': backendConfirmed,
        'validation_state': validationState,
      },
      'created_at_utc': DateTime.now().toUtc().toIso8601String(),
      'finalized_at_utc': stoppedAt.toUtc().toIso8601String(),
    };
  }

  Map<String, dynamic> _buildComplianceDirectLedgerRecord({
    required String? tripId,
    required DateTime? startedAt,
    required DateTime stoppedAt,
    required double kmTotal,
    required int waitSecondsTotal,
    required double totalEur,
    required bool backendConfirmed,
  }) {
    final driverId = kDriverId.trim();
    final vehicleId = _directRideVehicleId().trim();
    final rideId = _complianceRideId(
      rideType: 'direct',
      tripId: tripId,
      stoppedAt: stoppedAt,
    );
    final receiptReference = _complianceReceiptReference(
      tripId: tripId,
      rideId: rideId,
    );
    final validationState = _complianceValidationState(
      rideType: 'direct',
      backendConfirmed: backendConfirmed,
      driverId: driverId,
      receiptReference: receiptReference,
      startedAt: startedAt,
      stoppedAt: stoppedAt,
    );

    return <String, dynamic>{
      'ledger_version': '1.0',
      'ride_id': rideId,
      'ride_type': 'direct',
      'lifecycle_status': 'completed',
      'tenant_id': kOutboundTenantId,
      'company_id': resolvedCompanyId,
      'driver_id': driverId,
      'vehicle_id': vehicleId,
      'booking_id': null,
      'trip_id': (tripId ?? '').trim().isEmpty ? null : tripId!.trim(),
      'session_id': null,
      'started_at_utc': startedAt?.toUtc().toIso8601String(),
      'ended_at_utc': stoppedAt.toUtc().toIso8601String(),
      'duration_seconds': startedAt == null
          ? null
          : stoppedAt.difference(startedAt).inSeconds,
      'pickup': _currentOriginPayload(_startPos ?? _lastPos),
      'dropoff': <String, dynamic>{
        'label': (_directRideDestinationText ?? '').trim(),
        if (_directRideDestinationPoint != null)
          'lat': _directRideDestinationPoint!.lat,
        if (_directRideDestinationPoint != null)
          'lon': _directRideDestinationPoint!.lon,
      },
      'distance_km': kmTotal,
      'wait_seconds_total': waitSecondsTotal,
      'fare': <String, dynamic>{
        'total_eur': totalEur,
        'currency': kDefaultCurrency,
      },
      'payment': _buildCompliancePaymentPayload(),
      'references': <String, dynamic>{
        'receipt_reference': receiptReference,
        'planning_reference': null,
        'public_booking_reference': null,
        'booking_reference': null,
        'public_reference': null,
        'invoice_reference': null,
      },
      'provenance': <String, dynamic>{
        'backend_confirmed': backendConfirmed,
        'validation_state': validationState,
      },
      'created_at_utc': DateTime.now().toUtc().toIso8601String(),
      'finalized_at_utc': stoppedAt.toUtc().toIso8601String(),
    };
  }

  Map<String, dynamic> _buildLocalOnlyDirectHistoryRecord({
    required DateTime stoppedAt,
    required DateTime? startedAt,
    required double kmTotal,
    required int waitSecondsTotal,
    required double totalEur,
  }) {
    final localTripId =
        'local_direct_${stoppedAt.toUtc().millisecondsSinceEpoch}';
    final origin = _currentOriginPayload(_startPos ?? _lastPos);
    final destination = <String, dynamic>{
      'label': (_directRideDestinationText ?? '').trim(),
      if (_directRideDestinationPoint != null)
        'lat': _directRideDestinationPoint!.lat,
      if (_directRideDestinationPoint != null)
        'lon': _directRideDestinationPoint!.lon,
    };
    final payment = _buildCompliancePaymentPayload();

    return <String, dynamic>{
      'trip_id': localTripId,
      'kind': 'direct',
      'status': 'COMPLETED',
      'tenant_id': kOutboundTenantId,
      'driver_id': kDriverId,
      'vehicle_id': _directRideVehicleId(),
      'started_at': startedAt?.toUtc().toIso8601String(),
      'stopped_at': stoppedAt.toUtc().toIso8601String(),
      'origin': origin,
      'destination': destination,
      'km_total': kmTotal,
      'wait_seconds_total': waitSecondsTotal,
      'total_eur': totalEur,
      'currency': kDefaultCurrency,
      'payment_status': payment['status'] ?? 'unknown',
      'booking_details': <String, dynamic>{
        'payment_status': payment['status'] ?? 'unknown',
        if (payment['method'] != null) 'payment_method': payment['method'],
        if (payment['source'] != null) 'payment_source': payment['source'],
        if (payment['provider'] != null)
          'payment_provider': payment['provider'],
        if (payment['payment_id'] != null) 'payment_id': payment['payment_id'],
        if (payment['paid_at_utc'] != null) 'paid_at': payment['paid_at_utc'],
        'history_source': 'local_only_direct_fallback',
        'backend_confirmed': false,
      },
      'history_source': 'local_only_direct_fallback',
      'backend_confirmed': false,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  Future<void> _persistLocalOnlyDirectHistoryFallback({
    required DateTime stoppedAt,
    required DateTime? startedAt,
    required double kmTotal,
    required int waitSecondsTotal,
    required double totalEur,
  }) async {
    final record = _buildLocalOnlyDirectHistoryRecord(
      stoppedAt: stoppedAt,
      startedAt: startedAt,
      kmTotal: kmTotal,
      waitSecondsTotal: waitSecondsTotal,
      totalEur: totalEur,
    );
    await _LocalDirectTripHistoryStore.append(record);
  }

  Future<void> _stopTrip() async {
    final trip = _activeTripId;
    if (trip == null && !_directRideActive) return;
    final stoppedBooking = _activeBooking;
    if (stoppedBooking != null &&
        !_canOperateBookingWithGuard(
          _bookingScopeViewFor(stoppedBooking),
          action: 'stop_complete_booking',
        )) {
      return;
    }
    final wasDirectRide = _directRideActive;
    final directTripId = _activeDirectTripId;
    final finalTotal = _liveMeterTotalEur;
    final stoppedAt = DateTime.now();
    final startedAt = _trackingStartedAt;
    final kmAtStop = _kmDriven;
    var plannedSessionStopOk = false;

    if (_isWaiting && _waitStartedAt != null) {
      final started = _waitStartedAt!;
      _waitElapsed += DateTime.now().difference(started);
      _waitStartedAt = null;
      _isWaiting = false;
    }

    if (trip != null) {
      try {
        final uri = _withActiveBookingScope(kWorkerBaseUrl, kStopTripPath);
        final payload = <String, dynamic>{
          'session_id': trip,
          'driver_id': kDriverId,
          ..._activeBookingScopeQuery(),
          ..._driverMutationActorFields(actorVehicleId: _directRideVehicleId()),
        };
        final res = await http
            .post(
              uri,
              headers: _headers(admin: true),
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 10));
        plannedSessionStopOk = res.statusCode == 200;
      } catch (_) {}
    }

    if (!wasDirectRide && stoppedBooking != null && plannedSessionStopOk) {
      await _recordPlannedTripStopOnWorker(
        booking: stoppedBooking,
        kmTotal: kmAtStop,
        waitSecondsTotal: _effectiveWaitElapsed.inSeconds,
        startedAt: startedAt,
        stoppedAt: stoppedAt,
      );
    }

    double? serverDirectTotal;
    if (wasDirectRide &&
        directTripId != null &&
        directTripId.trim().isNotEmpty) {
      serverDirectTotal = await _stopDirectTripSessionOnWorker(
        tripId: directTripId,
        kmTotal: _kmDriven,
        waitSecondsTotal: _effectiveWaitElapsed.inSeconds,
      );
    }

    _stopMeterTicker();
    _stopTrackingInternal();

    if (stoppedBooking != null) {
      await _completeStoppedBooking(stoppedBooking);
    }
    if (!wasDirectRide && stoppedBooking != null) {
      final plannedLedger = _buildCompliancePlannedLedgerRecord(
        booking: stoppedBooking,
        startedAt: startedAt,
        stoppedAt: stoppedAt,
        kmTotal: kmAtStop,
        waitSecondsTotal: _effectiveWaitElapsed.inSeconds,
        backendConfirmed: plannedSessionStopOk,
      );
      unawaited(_writeComplianceLedgerRecord(record: plannedLedger));
    }
    if (wasDirectRide) {
      final directBackendConfirmed =
          _directTripStartWorkerOk && _directTripStopWorkerOk;
      final finalDirectTotal = serverDirectTotal ?? finalTotal;
      final directLedger = _buildComplianceDirectLedgerRecord(
        tripId: directTripId,
        startedAt: startedAt,
        stoppedAt: stoppedAt,
        kmTotal: _kmDriven,
        waitSecondsTotal: _effectiveWaitElapsed.inSeconds,
        totalEur: finalDirectTotal,
        backendConfirmed: directBackendConfirmed,
      );
      unawaited(_writeComplianceLedgerRecord(record: directLedger));
      final isLocalOnlyDirect =
          directTripId == null || directTripId.trim().isEmpty;
      if (isLocalOnlyDirect) {
        await _persistLocalOnlyDirectHistoryFallback(
          stoppedAt: stoppedAt,
          startedAt: startedAt,
          kmTotal: _kmDriven,
          waitSecondsTotal: _effectiveWaitElapsed.inSeconds,
          totalEur: finalDirectTotal,
        );
      }
      _directTripStartWorkerOk = false;
      _directTripStopWorkerOk = false;
    }
    await _clearActiveRouteAndNavigationState(
      reason: 'stop',
      bookingId: stoppedBooking?.bookingId,
      clearActiveSelection: true,
    );
    if (wasDirectRide) {
      final shownTotal = serverDirectTotal ?? finalTotal;
      _toast('Straatrit afgerond: € ${shownTotal.toStringAsFixed(2)}');
    }
  }

  Future<void> _completeStoppedBooking(BookingItem b) async {
    final bookingId = b.bookingId;
    try {
      await _setBookingStatus(b, 'COMPLETED');
    } catch (e) {
      debugPrint('[RIDES][STOP_COMPLETE][WARN] $e');
    }
    if (!mounted) return;
    setState(() {
      _bookingStatusOverrides[bookingId] = 'COMPLETED';
      _bookings.removeWhere((x) => x.bookingId == bookingId);
      _deletedBookingIds.add(bookingId);
    });
    _markBookingsUiDirty();
  }

  Future<void> _ensureLocationPermission() async {
    final enabled = await geo.Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      _toast('Location is disabled on the phone.');
      return;
    }

    geo.LocationPermission perm = await geo.Geolocator.checkPermission();
    if (perm == geo.LocationPermission.denied) {
      perm = await geo.Geolocator.requestPermission();
    }
    if (perm == geo.LocationPermission.denied ||
        perm == geo.LocationPermission.deniedForever) {
      _toast('Location permission denied.');
      return;
    }
  }

  void _startTrackingInternal() {
    if (_posSub != null) {
      debugPrint(
        '[RIDES][TRACKING][SKIP_START] reason=already_active geolocatorSubs=$_activeGeolocatorSubscriptionCount',
      );
      return;
    }
    _stopBookingPolling(reason: 'tracking_started');

    const settings = geo.LocationSettings(
      accuracy: geo.LocationAccuracy.bestForNavigation,
      distanceFilter: 3,
    );

    _posSub = geo.Geolocator.getPositionStream(locationSettings: settings).listen((
      pos,
    ) async {
      final prev = _lastPos;
      _lastPos = pos;
      _startPos ??= pos;

      if (prev != null) {
        final meters = geo.Geolocator.distanceBetween(
          prev.latitude,
          prev.longitude,
          pos.latitude,
          pos.longitude,
        );
        if (meters.isFinite && meters > 0) {
          // Only count driven distance once the trip is actually started.
          if (_liveRideActive && !_isWaiting) {
            if (mounted) setState(() => _kmDriven += meters / 1000.0);
          } else if (_liveRideActive && _isWaiting) {
            debugPrint(
              '[METER][WAIT_DISTANCE_SKIPPED] meters=${meters.toStringAsFixed(1)} km=${_kmDriven.toStringAsFixed(3)}',
            );
          }
        }

        if (_liveRideActive && !_hasSwitchedToFollow && _startPos != null) {
          final movedFromStart = geo.Geolocator.distanceBetween(
            _startPos!.latitude,
            _startPos!.longitude,
            pos.latitude,
            pos.longitude,
          );
          final speedKmh = (pos.speed.isFinite ? (pos.speed * 3.6) : 0.0);
          if (speedKmh >= 3.0 || movedFromStart >= 25.0) {
            _hasSwitchedToFollow = true;
            _cameraMode = _CameraMode.follow;
          }
        }

        final movementBearing = _bearingFromPoints(
          prev.latitude,
          prev.longitude,
          pos.latitude,
          pos.longitude,
        );
        if (movementBearing != null && meters >= 1.8) {
          _lastMovementBearing = movementBearing;
        }
      }

      if (pos.heading.isFinite &&
          pos.heading >= 0 &&
          _speedKmhFor(pos) >= 2.0) {
        _lastKnownBearing = pos.heading;
      }

      _updateRouteSnapState(pos);
      await _syncVisibleRouteLineWithProgress(pos);

      if (_mapSupported && _map != null && _driverPointManager != null) {
        await _updateDriverMarker(pos);
        if (_cameraMode == _CameraMode.follow) {
          await _followCameraTesla(pos);
        }
      }
      final uiBearing = _adaptiveBearingFor(pos, snap: _lastRouteSnap).bearing;
      if (mounted && _cameraMode == _CameraMode.follow) {
        setState(() => _uiArrowBearing = uiBearing);
      } else {
        _uiArrowBearing = uiBearing;
      }
      _updateNextNavInstruction(pos);

      await _sendPing(pos);
    });
    _activeGeolocatorSubscriptionCount = 1;
    debugPrint(
      '[RIDES][TRACKING][START] geolocatorSubs=$_activeGeolocatorSubscriptionCount',
    );
  }

  void _stopTrackingInternal() {
    if (_posSub == null) return;
    _posSub?.cancel();
    _posSub = null;
    _activeGeolocatorSubscriptionCount = 0;
    debugPrint(
      '[RIDES][TRACKING][STOP] geolocatorSubs=$_activeGeolocatorSubscriptionCount',
    );
    _startPos = null;
    _lastFollowCameraAt = null;
    _followCameraInFlight = false;
    if (!_liveRideActive) {
      _startBookingPolling(reason: 'tracking_stopped');
    }
  }

  /// ===============================
  /// HUD COMPUTED TEXTS (single source of truth)
  /// ===============================

  bool get _isTracking => _liveRideActive && _posSub != null;

  String get _etaText {
    // Countdown style ETA (remaining), used both in preview and in active trip.
    final total = _routeDurationSec;
    if (total == null || total <= 0) return '';

    // When tracking, subtract progress (based on km fraction). When previewing, show total.
    int remainingSec;
    if (_isTracking) {
      remainingSec = _timeRemainingSeconds ?? total;
    } else {
      // Not tracking yet (preview)
      remainingSec = total;
    }

    remainingSec = math.max(0, remainingSec);
    if (remainingSec < 60) return '<1 min';

    final minutes = (remainingSec / 60).ceil();
    if (minutes < 60) return '$minutes min';

    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  String get _kmRemainingText {
    // Show in preview as soon as we have a route.

    final remaining = _kmRemaining;
    if (remaining == null) return '';
    if (remaining < 0.05) return '0.0';
    return remaining.toStringAsFixed(1);
  }

  String get _timeRemainingText {
    if (!_isTracking) return '';
    final sec = _timeRemainingSeconds;
    if (sec == null) return '';
    final minutes = (sec / 60.0).round();
    if (minutes <= 0) return '0m';
    if (minutes < 60) return '${minutes}m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return '${h}h ${m}m';
  }

  double? get _kmRemaining {
    final rk = _routeKm;
    if (rk == null) return null;

    // ✅ Countdown starts only once we actually move (Google Maps style).
    // Before movement, keep the full route distance as "remaining".
    if (_isTracking && !_hasSwitchedToFollow) return rk;

    final v = rk - _kmDriven;
    return v < 0 ? 0 : v;
  }

  int? get _timeRemainingSeconds {
    final total = _routeDurationSec;
    final rk = _routeKm;
    if (total == null || rk == null) return null;

    // ✅ Countdown starts only once we actually move (Google Maps style).
    if (_isTracking && !_hasSwitchedToFollow) return total;

    if (rk <= 0.01) return total;
    final fracDriven = (_kmDriven / rk).clamp(0.0, 1.0);
    final remaining = (total * (1.0 - fracDriven)).round();
    return remaining < 0 ? 0 : remaining;
  }

  /// Map HUD actions
  Future<void> _stopTracking() async {
    // Stop UI + pings immediately (best UX)
    _stopTrackingInternal();

    // Try to notify Worker (best-effort)
    try {
      await _stopTrip();
    } catch (_) {
      // ignore
    }

    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openNavigation() async {
    // NAV always forces follow mode for live street-level navigation.
    if (_map == null) return;
    final booking = _activeBooking;
    if (booking != null &&
        !_canOperateBookingWithGuard(
          _bookingScopeViewFor(booking),
          action: 'open_navigation',
        )) {
      return;
    }

    setState(() {
      _cameraMode = _CameraMode.follow;
      _hasSwitchedToFollow = true;
      _followCar = true;
      _allowOverviewCamera = false;
    });
    _setNavigationWakelock(true);
    await _applyMapStyleForMode();
    await _forceFollowCameraNow(caller: 'nav_button');
    final b = _activeBooking;
    if (b != null && _activeTripId == null) {
      await _buildNavRouteToPickup(b);
    } else if (b != null && _activeTripId != null) {
      await _buildNavRouteToDestination(b);
    } else if ((_directRideDestinationText ?? '').trim().isNotEmpty) {
      await _buildDirectRouteToDestination(_directRideDestinationText!.trim());
    }
  }

  Future<void> _openDirectRideEntry() async {
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
    final destination = await showDialog<_DirectRideDestinationResult>(
      context: context,
      builder: (_) => _DirectRideDestinationDialog(
        initialText: _directRideDestinationText ?? '',
        search: _fetchPlaceSuggestions,
      ),
    );
    if (!mounted || destination == null || destination.label.trim().isEmpty)
      return;
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    final selectedPoint = (destination.lon != null && destination.lat != null)
        ? _LonLat(destination.lon!, destination.lat!)
        : null;

    setState(() {
      _activeBooking = null;
      _activeTripId = null;
      _activeDirectTripId = null;
      _directRideActive = false;
      _directTripStartWorkerOk = false;
      _directTripStopWorkerOk = false;
      _directRideDestinationText = destination.label.trim();
      _directRideDestinationPoint = selectedPoint;
      _kmDriven = 0.0;
      _resetNavProgressState(clearRoute: true);
      _routePhase = _RideRoutePhase.trip;
      _cameraMode = _CameraMode.overview;
      _hasSwitchedToFollow = false;
      _followCar = false;
      _allowOverviewCamera = false;
      _isWaiting = false;
      _waitStartedAt = null;
      _waitElapsed = Duration.zero;
      _trackingStartedAt = null;
    });
    _toast('Straatrit klaar. Druk START om te rijden.');
  }

  Future<void> _startDirectRide() async {
    final destination = (_directRideDestinationText ?? '').trim();
    if (destination.isEmpty) {
      await _openDirectRideEntry();
      return;
    }
    await _ensureLocationPermission();
    var pos = _lastPos;
    if (pos == null) {
      try {
        pos = await geo.Geolocator.getCurrentPosition(
          desiredAccuracy: geo.LocationAccuracy.best,
        );
        _lastPos = pos;
      } catch (_) {
        pos = null;
      }
    }
    if (pos == null) {
      _toast('GPS-locatie nog niet beschikbaar');
      return;
    }

    setState(() {
      _directRideActive = true;
      _activeTripId = null;
      _activeDirectTripId = null;
      _directTripStartWorkerOk = false;
      _directTripStopWorkerOk = false;
      _activeBooking = null;
      _cameraMode = _CameraMode.follow;
      _hasSwitchedToFollow = true;
      _followCar = true;
      _allowOverviewCamera = false;
      _kmDriven = 0.0;
      _trackingStartedAt = DateTime.now();
      _isWaiting = false;
      _waitStartedAt = null;
      _waitElapsed = Duration.zero;
    });
    _setNavigationWakelock(true);
    await _applyMapStyleForMode();
    _startTrackingInternal();
    _startMeterTicker();
    unawaited(_startDirectTripSessionOnWorker(destination: destination));
    await _forceFollowCameraNow(caller: 'direct_ride_start');
    await _buildDirectRouteToDestination(destination);
  }

  void _handleCockpitStart() {
    final b = _activeBooking;
    if (b != null) {
      _startTrip(b);
      return;
    }
    if (_directRideDraft || _directRideActive) {
      _startDirectRide();
      return;
    }
    _toast('Kies eerst een rit of start een straatrit.');
  }

  Future<void> _sendPing(geo.Position pos) async {
    final trip = _activeTripId;
    if (trip == null) return;

    try {
      final uri = _withActiveBookingScope(kWorkerBaseUrl, kPingPath);
      final actorVehicleId = _directRideVehicleId();
      final payload = {
        'session_id': trip,
        'driver_id': kDriverId,
        'vehicle_id': actorVehicleId,
        ..._activeBookingScopeQuery(),
        'lat': pos.latitude,
        'lon': pos.longitude,
        'speed': (pos.speed.isFinite ? (pos.speed * 3.6) : 0.0),
        'heading': (pos.heading.isFinite ? pos.heading : 0.0),
        'accuracy_m': pos.accuracy,
        'ts': DateTime.now().toIso8601String(),
        ..._driverMutationActorFields(actorVehicleId: actorVehicleId),
      };

      final res = await http
          .post(uri, headers: _headers(admin: true), body: jsonEncode(payload))
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;

      setState(() {
        _pingCount += 1;
        _lastPing = (res.statusCode == 200) ? 'OK' : 'HTTP ${res.statusCode}';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _lastPing = 'ERR');
    }
  }

  Future<void> _onMapCreated(mb.MapboxMap mapboxMap) async {
    debugPrint('[MAP][CREATED] style=$_activeMapStyleUri');
    _map = mapboxMap;
    await _applyMapStyleForMode();
    await _recreateAnnotationManagers();

    final pos = _lastPos;
    if (pos != null) {
      await _updateDriverMarker(
        pos,
        moveCamera: _cameraMode != _CameraMode.follow,
      );
      if (_cameraMode == _CameraMode.follow) {
        await _followCameraTesla(pos, force: true);
      }
    }
  }

  Future<void> _recreateAnnotationManagers() async {
    if (_map == null) return;
    _routeLineManager = await _map!.annotations
        .createPolylineAnnotationManager();
    _pinsPointManager = await _map!.annotations.createPointAnnotationManager();
    _driverPointManager = await _map!.annotations
        .createPointAnnotationManager();
  }

  MapThemeMode _effectiveMapThemeFor(_CameraMode mode) {
    return _mapThemeOverride ??
        (mode == _CameraMode.follow ? MapThemeMode.light : MapThemeMode.dark);
  }

  String _styleForTheme(MapThemeMode theme) {
    return theme == MapThemeMode.light
        ? 'mapbox://styles/mapbox/streets-v12'
        : 'mapbox://styles/mapbox/navigation-night-v1';
  }

  String _styleForMode(_CameraMode mode) {
    return _styleForTheme(_effectiveMapThemeFor(mode));
  }

  Future<void> _applyMapStyleForMode() async {
    if (_map == null) return;
    final theme = _effectiveMapThemeFor(_cameraMode);
    final target = _styleForMode(_cameraMode);
    debugPrint(
      '[MAP][STYLE_REQ] theme=${theme == MapThemeMode.light ? 'light' : 'dark'} target=$target active=$_activeMapStyleUri pending=${_pendingMapStyleUri ?? ''}',
    );
    if (_activeMapStyleUri == target) {
      debugPrint('[MAP][STYLE_SKIP] reason=already_active target=$target');
      return;
    }
    if (_pendingMapStyleUri == target) {
      debugPrint('[MAP][STYLE_SKIP] reason=in_flight target=$target');
      return;
    }
    _pendingMapStyleUri = target;
    try {
      debugPrint(
        '[MAP_THEME] selected=${theme == MapThemeMode.light ? 'light' : 'dark'} style=$target',
      );
      await _map!.style.setStyleURI(target);
      _activeMapStyleUri = target;
      _mapRedrawCountThisMinute += 1;
      await _recreateAnnotationManagers();
      _driverMarker = null;
      _pickupPin = null;
      _dropoffPin = null;
      _routeLine = null;
      _routeLineOutline = null;
      if (_routeCoords.length >= 2) {
        await _drawRouteLine(_routeCoords);
        await _drawPins(_routeCoords.first, _routeCoords.last);
      }
      if (_lastPos != null) {
        _updateRouteSnapState(_lastPos!);
        await _syncVisibleRouteLineWithProgress(_lastPos!);
        await _updateDriverMarker(_lastPos!);
      }
      debugPrint(
        '[MAP_THEME] redraw route=${_routeCoords.length >= 2} marker=${_lastPos != null} pins=${_routeCoords.length >= 2}',
      );
      debugPrint('[MAP][STYLE_DONE] target=$target');
    } catch (e) {
      debugPrint('[MAP][STYLE_SKIP] reason=error target=$target error=$e');
    } finally {
      if (_pendingMapStyleUri == target) {
        _pendingMapStyleUri = null;
      }
    }
  }

  Future<void> _setMapTheme(MapThemeMode theme) async {
    if (!mounted) return;
    setState(() => _mapThemeOverride = theme);
    await _applyMapStyleForMode();
  }

  mb.Point _mbPoint(double lon, double lat) =>
      mb.Point(coordinates: mb.Position(lon, lat));

  double _metersBetween(_LonLat a, _LonLat b) {
    return geo.Geolocator.distanceBetween(a.lat, a.lon, b.lat, b.lon);
  }

  double _snapThresholdFor(geo.Position pos) {
    final accuracy = pos.accuracy.isFinite && pos.accuracy > 0
        ? pos.accuracy
        : 20.0;
    return math.max(35.0, math.min(90.0, accuracy * 1.8));
  }

  double _speedKmhFor(geo.Position pos) {
    if (!pos.speed.isFinite || pos.speed < 0) return 0.0;
    return pos.speed * 3.6;
  }

  void _logNavBounded(String tag, String message, {int intervalMs = 900}) {
    final now = DateTime.now();
    final last = _lastNavDebugAt[tag];
    if (last != null && now.difference(last).inMilliseconds < intervalMs)
      return;
    _lastNavDebugAt[tag] = now;
    debugPrint('[$tag] $message');
  }

  ({double enterThresholdM, double exitThresholdM}) _matchThresholdsFor(
    geo.Position pos,
  ) {
    final base = _snapThresholdFor(pos);
    final speedKmh = _speedKmhFor(pos);
    final navAgeSec = _trackingStartedAt == null
        ? 999.0
        : DateTime.now().difference(_trackingStartedAt!).inMilliseconds /
              1000.0;
    final justStarted = navAgeSec <= 18.0;
    final movingFast = speedKmh >= 35.0;
    final enter = justStarted
        ? math.max(base, 70.0)
        : (movingFast ? math.max(base, 48.0) : base);
    final exit = enter + 18.0;
    return (enterThresholdM: enter, exitThresholdM: exit);
  }

  bool _isProgressPlausible(_RouteSnap snap, geo.Position pos) {
    final prev = _lastVisualProgressM;
    if (prev == null) return true;
    final speedKmh = _speedKmhFor(pos);
    final backwardToleranceM = speedKmh < 6.0 ? 35.0 : 22.0;
    if (snap.distanceAlongRouteM < prev - backwardToleranceM) {
      return false;
    }
    final maxForwardJumpM = math.max(70.0, speedKmh * 2.8 + 38.0);
    if (snap.distanceAlongRouteM > prev + maxForwardJumpM) {
      return false;
    }
    return true;
  }

  bool _canSnapToRoute(geo.Position pos, _RouteSnap? snap) {
    if (snap == null) return false;
    final thresholds = _matchThresholdsFor(pos);
    final threshold = _useMatchedVisual
        ? thresholds.exitThresholdM
        : thresholds.enterThresholdM;
    if (snap.distanceFromRouteM > threshold) return false;
    return _isProgressPlausible(snap, pos);
  }

  _RouteSnap? _snapToRouteOn(List<_LonLat> routeCoords, _LonLat raw) {
    if (routeCoords.length < 2) return null;
    final refLatRad = raw.lat * math.pi / 180.0;
    const metersPerDegLat = 111320.0;
    final metersPerDegLon = math.max(
      1.0,
      metersPerDegLat * math.cos(refLatRad),
    );

    var bestDistance = double.infinity;
    var bestAlong = 0.0;
    var bestSegment = 0;
    var bestT = 0.0;
    _LonLat? bestPoint;
    var cumulative = 0.0;

    for (var i = 0; i < routeCoords.length - 1; i++) {
      final a = routeCoords[i];
      final b = routeCoords[i + 1];
      final ax = (a.lon - raw.lon) * metersPerDegLon;
      final ay = (a.lat - raw.lat) * metersPerDegLat;
      final bx = (b.lon - raw.lon) * metersPerDegLon;
      final by = (b.lat - raw.lat) * metersPerDegLat;
      final vx = bx - ax;
      final vy = by - ay;
      final len2 = vx * vx + vy * vy;
      final t = len2 <= 0 ? 0.0 : ((-ax * vx - ay * vy) / len2).clamp(0.0, 1.0);
      final px = ax + vx * t;
      final py = ay + vy * t;
      final approxDistance = math.sqrt(px * px + py * py);
      final segmentMeters = _metersBetween(a, b);
      if (approxDistance < bestDistance) {
        bestDistance = approxDistance;
        bestAlong = cumulative + segmentMeters * t;
        bestSegment = i;
        bestT = t;
        bestPoint = _LonLat(
          a.lon + (b.lon - a.lon) * t,
          a.lat + (b.lat - a.lat) * t,
        );
      }
      cumulative += segmentMeters;
    }

    final point = bestPoint;
    if (point == null || !bestDistance.isFinite) return null;
    return _RouteSnap(
      point: point,
      distanceFromRouteM: bestDistance,
      distanceAlongRouteM: bestAlong,
      segmentIndex: bestSegment,
      segmentT: bestT,
    );
  }

  _RouteSnap? _snapToRoute(_LonLat raw) => _snapToRouteOn(_routeCoords, raw);

  double _distanceAlongRouteFor(_LonLat point) {
    return _snapToRoute(point)?.distanceAlongRouteM ?? 0.0;
  }

  double _distanceAlongRouteForCoords(
    List<_LonLat> routeCoords,
    _LonLat point,
  ) {
    return _snapToRouteOn(routeCoords, point)?.distanceAlongRouteM ?? 0.0;
  }

  void _updateRouteSnapState(geo.Position pos) {
    final rawPoint = _LonLat(pos.longitude, pos.latitude);
    final snap = _snapToRoute(rawPoint);
    _lastRouteSnap = snap;
    final bool canUseMatched = _canSnapToRoute(pos, snap);
    if (canUseMatched) {
      _matchEnterHits += 1;
      _matchExitHits = 0;
      if (!_useMatchedVisual && _matchEnterHits >= 2) {
        _useMatchedVisual = true;
      }
    } else {
      _matchExitHits += 1;
      _matchEnterHits = 0;
      if (_useMatchedVisual && _matchExitHits >= 2) {
        _useMatchedVisual = false;
      }
    }
    if (_useMatchedVisual && snap != null) {
      _lastVisualProgressM = snap.distanceAlongRouteM;
    }

    final offRouteThreshold = math.max(70.0, _snapThresholdFor(pos) + 25.0);
    final snapDistance = snap?.distanceFromRouteM ?? double.infinity;
    if (snapDistance > offRouteThreshold) {
      _offRouteHitCount += 1;
    } else {
      _offRouteHitCount = 0;
    }
    final offRoute = _offRouteHitCount >= 3;
    if (offRoute != _offRouteLikely) {
      _offRouteLikely = offRoute;
    }

    final displayPoint = (_useMatchedVisual && snap != null)
        ? snap.point
        : rawPoint;
    _lastMarkerLagM = geo.Geolocator.distanceBetween(
      rawPoint.lat,
      rawPoint.lon,
      displayPoint.lat,
      displayPoint.lon,
    );

    _logNavBounded(
      'NAV_MATCH',
      'rawLat=${rawPoint.lat.toStringAsFixed(6)} rawLon=${rawPoint.lon.toStringAsFixed(6)} '
          'snapDistM=${snapDistance.isFinite ? snapDistance.toStringAsFixed(1) : 'inf'} '
          'gpsAccuracyM=${(pos.accuracy.isFinite ? pos.accuracy : -1).toStringAsFixed(1)} '
          'useMatchedVisual=$_useMatchedVisual reason=${canUseMatched ? 'confidence_ok' : 'confidence_low'}',
    );
  }

  _LonLat _displayRoutePointFor(geo.Position pos) {
    final snap =
        _lastRouteSnap ?? _snapToRoute(_LonLat(pos.longitude, pos.latitude));
    if (_useMatchedVisual && snap != null) return snap.point;
    return _LonLat(pos.longitude, pos.latitude);
  }

  double? _effectiveRouteProgressM(geo.Position pos) {
    final snap =
        _lastRouteSnap ?? _snapToRoute(_LonLat(pos.longitude, pos.latitude));
    if (_useMatchedVisual && snap != null) return snap.distanceAlongRouteM;
    return null;
  }

  List<_LonLat> _routeCoordsFromSnap(_RouteSnap snap) {
    if (_routeCoords.length < 2) return _routeCoords;
    final i = snap.segmentIndex.clamp(0, _routeCoords.length - 2);
    final out = <_LonLat>[snap.point, ..._routeCoords.sublist(i + 1)];
    if (out.length < 2) {
      out.add(_routeCoords.last);
    }
    return out;
  }

  Future<void> _syncVisibleRouteLineWithProgress(geo.Position pos) async {
    if (_routeCoords.length < 2 || _routeLineManager == null) return;
    final snap =
        _lastRouteSnap ?? _snapToRoute(_LonLat(pos.longitude, pos.latitude));
    final progressM = _effectiveRouteProgressM(pos);

    if (_cameraMode != _CameraMode.follow || !_liveRideActive) {
      if (_routeLineProgressTrimmed) {
        _routeLineProgressTrimmed = false;
        _lastRouteLineTrimProgressM = 0.0;
        await _drawRouteLine(_routeCoords, force: true);
      }
      return;
    }

    if (!_useMatchedVisual || snap == null || progressM == null) {
      if (_routeLineProgressTrimmed) {
        _routeLineProgressTrimmed = false;
        _lastRouteLineTrimProgressM = 0.0;
        await _drawRouteLine(_routeCoords, force: true);
      }
      _logNavBounded(
        'NAV_PROGRESS',
        'progressM=-1 routeLineTrimmed=false markerLagM=${_lastMarkerLagM.toStringAsFixed(1)}',
      );
      return;
    }

    final now = DateTime.now();
    final deltaM = (progressM - _lastRouteLineTrimProgressM).abs();
    final recentDraw =
        _lastRouteLineTrimAt != null &&
        now.difference(_lastRouteLineTrimAt!).inMilliseconds < 320;
    if (_routeLineProgressTrimmed && deltaM < 12.0 && recentDraw) {
      _logNavBounded(
        'NAV_PROGRESS',
        'progressM=${progressM.toStringAsFixed(1)} routeLineTrimmed=true markerLagM=${_lastMarkerLagM.toStringAsFixed(1)}',
      );
      return;
    }

    final trimmed = _routeCoordsFromSnap(snap);
    if (trimmed.length >= 2) {
      _routeLineProgressTrimmed = true;
      _lastRouteLineTrimProgressM = progressM;
      _lastRouteLineTrimAt = now;
      await _drawRouteLine(trimmed, force: true);
    }
    _logNavBounded(
      'NAV_PROGRESS',
      'progressM=${progressM.toStringAsFixed(1)} routeLineTrimmed=${trimmed.length >= 2} markerLagM=${_lastMarkerLagM.toStringAsFixed(1)}',
    );
  }

  double? _routeBearingAtSnap(_RouteSnap? snap) {
    if (snap == null || _routeCoords.length < 2) return null;
    final i = snap.segmentIndex.clamp(0, _routeCoords.length - 2);
    final a = _routeCoords[i];
    final b = _routeCoords[i + 1];
    return _bearingFromPoints(a.lat, a.lon, b.lat, b.lon);
  }

  Future<void> _updateDriverMarker(
    geo.Position pos, {
    bool moveCamera = false,
  }) async {
    final mgr = _driverPointManager;
    if (mgr == null) return;

    final snap =
        _lastRouteSnap ?? _snapToRoute(_LonLat(pos.longitude, pos.latitude));
    final displayPoint = _displayRoutePointFor(pos);
    final p = _mbPoint(displayPoint.lon, displayPoint.lat);
    final bearingData = _adaptiveBearingFor(pos, snap: snap);
    final markerBearing = bearingData.bearing;

    if (_driverMarker == null) {
      try {
        _driverMarkerIcon = 'triangle-15';
        _driverMarker = await mgr.create(
          mb.PointAnnotationOptions(
            geometry: p,
            iconImage: _driverMarkerIcon,
            iconColor: 0xFFFFD21F,
            iconSize: 1.5,
            iconRotate: markerBearing,
          ),
        );
      } catch (_) {
        _driverMarkerIcon = 'marker-15';
        _driverMarker = await mgr.create(
          mb.PointAnnotationOptions(
            geometry: p,
            iconImage: _driverMarkerIcon,
            iconColor: 0xFFFFD21F,
            iconSize: 1.7,
            iconRotate: markerBearing,
          ),
        );
      }
    } else {
      _driverMarker!.geometry = p;
      _driverMarker!.iconRotate = markerBearing;
      await mgr.update(_driverMarker!);
    }

    if (moveCamera && _cameraMode != _CameraMode.follow) {
      await _map?.flyTo(
        mb.CameraOptions(center: p, zoom: 13.5),
        mb.MapAnimationOptions(duration: 700),
      );
    }
  }

  Future<void> _followCameraTesla(
    geo.Position pos, {
    bool force = false,
  }) async {
    final now = DateTime.now();
    final last = _lastFollowCameraAt;
    if (!force && last != null && now.difference(last).inMilliseconds < 320) {
      return;
    }
    if (!force && _followCameraInFlight) return;
    _lastFollowCameraAt = now;
    _followCameraInFlight = true;
    final snap =
        _lastRouteSnap ?? _snapToRoute(_LonLat(pos.longitude, pos.latitude));
    final displayPoint = _displayRoutePointFor(pos);
    final p = _mbPoint(displayPoint.lon, displayPoint.lat);
    final heading = _adaptiveBearingFor(pos, snap: snap).bearing;

    try {
      await _map?.flyTo(
        mb.CameraOptions(
          center: p,
          zoom: 18.8,
          bearing: heading,
          pitch: 68.0,
          padding: mb.MbxEdgeInsets(
            top: MediaQuery.of(context).padding.top + 120,
            left: 24,
            bottom: MediaQuery.of(context).padding.bottom + 260,
            right: 24,
          ),
        ),
        mb.MapAnimationOptions(duration: 280),
      );
    } finally {
      _followCameraInFlight = false;
    }
  }

  void _updateNextNavInstruction(geo.Position pos) {
    if (_routeSteps.isEmpty) {
      if (_nextNavInstruction != null ||
          _nextNavStreet != null ||
          _nextNavDistanceM != null ||
          _nextNavType != null ||
          _nextNavModifier != null) {
        if (mounted) {
          setState(() {
            _nextNavInstruction = null;
            _nextNavStreet = null;
            _nextNavDistanceM = null;
            _nextNavType = null;
            _nextNavModifier = null;
          });
        } else {
          _nextNavInstruction = null;
          _nextNavStreet = null;
          _nextNavDistanceM = null;
          _nextNavType = null;
          _nextNavModifier = null;
        }
      }
      return;
    }

    final snap =
        _lastRouteSnap ?? _snapToRoute(_LonLat(pos.longitude, pos.latitude));
    final progressM = (_useMatchedVisual && snap != null)
        ? snap.distanceAlongRouteM
        : null;
    final progressSource = progressM == null ? 'raw_fallback' : 'matched';
    while (_nextStepIndex < _routeSteps.length - 1) {
      final current = _routeSteps[_nextStepIndex];
      final straightLineM = geo.Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        current.lat,
        current.lon,
      );
      final passedByRouteProgress =
          progressM != null && progressM >= current.distanceAlongRouteM + 18.0;
      if (straightLineM <= 32 || passedByRouteProgress) {
        _nextStepIndex += 1;
      } else {
        break;
      }
    }

    final step = _routeSteps[_nextStepIndex];
    final distanceM = progressM == null
        ? geo.Geolocator.distanceBetween(
            pos.latitude,
            pos.longitude,
            step.lat,
            step.lon,
          )
        : math.max(0.0, step.distanceAlongRouteM - progressM);
    _logNavBounded(
      'NAV_STEP',
      'progressSource=$progressSource nextDistanceM=${distanceM.toStringAsFixed(1)}',
    );

    if (!mounted) {
      _nextNavInstruction = step.instruction;
      _nextNavStreet = step.street;
      _nextNavDistanceM = distanceM;
      _nextNavType = step.type;
      _nextNavModifier = step.modifier;
      return;
    }

    setState(() {
      _nextNavInstruction = step.instruction;
      _nextNavStreet = step.street;
      _nextNavDistanceM = distanceM;
      _nextNavType = step.type;
      _nextNavModifier = step.modifier;
    });
  }

  Future<void> _buildNavRouteToPickup(BookingItem b) async {
    final epoch = _routeCleanupEpoch;
    final expectedBookingId = b.bookingId;
    if (!_isRouteTaskStillValid(
      epoch: epoch,
      expectedBookingId: expectedBookingId,
    )) {
      return;
    }
    if (_lastPos == null) return;
    final pickupText = (b.from ?? '').trim();
    if (pickupText.isEmpty) return;
    if (mounted) {
      setState(() {
        _routePhase = _RideRoutePhase.toPickup;
        _navStepsLoading = true;
      });
    } else {
      _routePhase = _RideRoutePhase.toPickup;
      _navStepsLoading = true;
    }
    debugPrint('[NAV_PHASE] toPickup');
    try {
      final fromLL = _LonLat(_lastPos!.longitude, _lastPos!.latitude);
      final toLL = await _geocodeOne(pickupText);
      final route = await _directionsRoute(fromLL, toLL);
      final coords = route.$1;
      if (coords.length < 2) return;
      if (!_isRouteTaskStillValid(
        epoch: epoch,
        expectedBookingId: expectedBookingId,
      )) {
        return;
      }
      if (mounted) {
        setState(() {
          _routeCoords = coords;
          _routeKm = route.$2 / 1000.0;
          _routeDurationSec = route.$3;
        });
      } else {
        _routeCoords = coords;
        _routeKm = route.$2 / 1000.0;
        _routeDurationSec = route.$3;
      }
      if (_lastPos != null) {
        _updateRouteSnapState(_lastPos!);
        _updateNextNavInstruction(_lastPos!);
        await _syncVisibleRouteLineWithProgress(_lastPos!);
      }
      await _drawPins(fromLL, toLL);
      await _drawRouteLine(coords);
    } catch (_) {
      // Keep previous route if pickup route fetch fails.
    } finally {
      if (_isRouteTaskStillValid(
        epoch: epoch,
        expectedBookingId: expectedBookingId,
      )) {
        if (mounted) {
          setState(() => _navStepsLoading = false);
        } else {
          _navStepsLoading = false;
        }
      }
    }
  }

  Future<void> _buildNavRouteToDestination(BookingItem b) async {
    final epoch = _routeCleanupEpoch;
    final expectedBookingId = b.bookingId;
    if (!_isRouteTaskStillValid(
      epoch: epoch,
      expectedBookingId: expectedBookingId,
    )) {
      return;
    }
    if (_lastPos == null) return;
    final dropoffText = (b.to ?? '').trim();
    if (dropoffText.isEmpty) return;
    if (mounted) {
      setState(() {
        _routePhase = _RideRoutePhase.trip;
        _navStepsLoading = true;
      });
    } else {
      _routePhase = _RideRoutePhase.trip;
      _navStepsLoading = true;
    }
    debugPrint('[NAV_PHASE] trip');
    try {
      final fromLL = _LonLat(_lastPos!.longitude, _lastPos!.latitude);
      final toLL = await _geocodeOne(dropoffText);
      final route = await _directionsRoute(fromLL, toLL);
      final coords = route.$1;
      if (coords.length < 2) return;
      if (!_isRouteTaskStillValid(
        epoch: epoch,
        expectedBookingId: expectedBookingId,
      )) {
        return;
      }
      if (mounted) {
        setState(() {
          _routeCoords = coords;
          _routeKm = route.$2 / 1000.0;
          _routeDurationSec = route.$3;
        });
      } else {
        _routeCoords = coords;
        _routeKm = route.$2 / 1000.0;
        _routeDurationSec = route.$3;
      }
      if (_lastPos != null) {
        _updateRouteSnapState(_lastPos!);
        _updateNextNavInstruction(_lastPos!);
        await _syncVisibleRouteLineWithProgress(_lastPos!);
      }
      await _drawPins(fromLL, toLL);
      await _drawRouteLine(coords);
    } catch (_) {
      // Keep previous route if destination route fetch fails.
    } finally {
      if (_isRouteTaskStillValid(
        epoch: epoch,
        expectedBookingId: expectedBookingId,
      )) {
        if (mounted) {
          setState(() => _navStepsLoading = false);
        } else {
          _navStepsLoading = false;
        }
      }
    }
  }

  Future<void> _buildDirectRouteToDestination(String destinationText) async {
    final epoch = _routeCleanupEpoch;
    if (!_isRouteTaskStillValid(epoch: epoch, requireDirectRide: true)) {
      return;
    }
    if (_lastPos == null) return;
    final dropoffText = destinationText.trim();
    if (dropoffText.isEmpty) return;
    if (mounted) {
      setState(() {
        _routePhase = _RideRoutePhase.trip;
        _navStepsLoading = true;
      });
    } else {
      _routePhase = _RideRoutePhase.trip;
      _navStepsLoading = true;
    }
    debugPrint('[NAV_PHASE] direct_trip');
    try {
      final fromLL = _LonLat(_lastPos!.longitude, _lastPos!.latitude);
      final toLL =
          _directRideDestinationPoint ?? await _geocodeOne(dropoffText);
      final route = await _directionsRoute(fromLL, toLL);
      final coords = route.$1;
      if (coords.length < 2) return;
      if (!_isRouteTaskStillValid(epoch: epoch, requireDirectRide: true)) {
        return;
      }
      if (mounted) {
        setState(() {
          _routeCoords = coords;
          _routeKm = route.$2 / 1000.0;
          _routeDurationSec = route.$3;
        });
      } else {
        _routeCoords = coords;
        _routeKm = route.$2 / 1000.0;
        _routeDurationSec = route.$3;
      }
      if (_lastPos != null) {
        _updateRouteSnapState(_lastPos!);
        _updateNextNavInstruction(_lastPos!);
        await _syncVisibleRouteLineWithProgress(_lastPos!);
      }
      await _drawPins(fromLL, toLL);
      await _drawRouteLine(coords);
    } catch (e) {
      _toast('Straatrit route mislukt: $e');
    } finally {
      if (_isRouteTaskStillValid(epoch: epoch, requireDirectRide: true)) {
        if (mounted) {
          setState(() => _navStepsLoading = false);
        } else {
          _navStepsLoading = false;
        }
      }
    }
  }

  Future<void> _forceFollowCameraNow({required String caller}) async {
    geo.Position? pos = _lastPos;
    if (pos == null) {
      try {
        pos = await geo.Geolocator.getCurrentPosition(
          desiredAccuracy: geo.LocationAccuracy.best,
        );
        _lastPos = pos;
      } catch (_) {
        pos = null;
      }
    }

    if (pos == null) {
      _toast('GPS-locatie nog niet beschikbaar');
      return;
    }
    await _followCameraTesla(pos, force: true);
  }

  double _cameraBearingFor(geo.Position pos) {
    if (pos.heading.isFinite && pos.heading >= 0) return pos.heading;
    if (_lastMovementBearing != null && _lastMovementBearing!.isFinite) {
      return _lastMovementBearing!;
    }
    if (_lastKnownBearing.isFinite && _lastKnownBearing > 0)
      return _lastKnownBearing;
    return 0.0;
  }

  ({
    double bearing,
    String source,
    double? gpsHeading,
    double? movementBearing,
    double? routeBearing,
  })
  _adaptiveBearingFor(geo.Position pos, {_RouteSnap? snap}) {
    final speedKmh = _speedKmhFor(pos);
    final gpsHeading = (pos.heading.isFinite && pos.heading >= 0)
        ? pos.heading
        : null;
    final movementBearing = _lastMovementBearing;
    final routeBearing = _routeBearingAtSnap(snap);

    if (movementBearing != null &&
        movementBearing.isFinite &&
        (speedKmh >= 7.0 || (gpsHeading == null && speedKmh >= 3.0))) {
      _lastKnownBearing = movementBearing;
      _logNavBounded(
        'NAV_BEARING',
        'gpsHeading=${gpsHeading?.toStringAsFixed(1) ?? 'na'} movementBearing=${movementBearing.toStringAsFixed(1)} '
            'routeBearing=${routeBearing?.toStringAsFixed(1) ?? 'na'} usedBearing=${movementBearing.toStringAsFixed(1)} source=movement',
      );
      return (
        bearing: movementBearing,
        source: 'movement',
        gpsHeading: gpsHeading,
        movementBearing: movementBearing,
        routeBearing: routeBearing,
      );
    }
    if (gpsHeading != null && speedKmh >= 2.0) {
      _lastKnownBearing = gpsHeading;
      _logNavBounded(
        'NAV_BEARING',
        'gpsHeading=${gpsHeading.toStringAsFixed(1)} movementBearing=${movementBearing?.toStringAsFixed(1) ?? 'na'} '
            'routeBearing=${routeBearing?.toStringAsFixed(1) ?? 'na'} usedBearing=${gpsHeading.toStringAsFixed(1)} source=gps_heading',
      );
      return (
        bearing: gpsHeading,
        source: 'gps_heading',
        gpsHeading: gpsHeading,
        movementBearing: movementBearing,
        routeBearing: routeBearing,
      );
    }
    if (_useMatchedVisual && routeBearing != null && routeBearing.isFinite) {
      _lastKnownBearing = routeBearing;
      _logNavBounded(
        'NAV_BEARING',
        'gpsHeading=${gpsHeading?.toStringAsFixed(1) ?? 'na'} movementBearing=${movementBearing?.toStringAsFixed(1) ?? 'na'} '
            'routeBearing=${routeBearing.toStringAsFixed(1)} usedBearing=${routeBearing.toStringAsFixed(1)} source=route_segment',
      );
      return (
        bearing: routeBearing,
        source: 'route_segment',
        gpsHeading: gpsHeading,
        movementBearing: movementBearing,
        routeBearing: routeBearing,
      );
    }
    if (_lastKnownBearing.isFinite && _lastKnownBearing > 0) {
      _logNavBounded(
        'NAV_BEARING',
        'gpsHeading=${gpsHeading?.toStringAsFixed(1) ?? 'na'} movementBearing=${movementBearing?.toStringAsFixed(1) ?? 'na'} '
            'routeBearing=${routeBearing?.toStringAsFixed(1) ?? 'na'} usedBearing=${_lastKnownBearing.toStringAsFixed(1)} source=last_stable',
      );
      return (
        bearing: _lastKnownBearing,
        source: 'last_stable',
        gpsHeading: gpsHeading,
        movementBearing: movementBearing,
        routeBearing: routeBearing,
      );
    }
    final safeFallback =
        routeBearing ??
        movementBearing ??
        gpsHeading ??
        (_lastKnownBearing.isFinite ? _lastKnownBearing : 0.0);
    _lastKnownBearing = safeFallback;
    _logNavBounded(
      'NAV_BEARING',
      'gpsHeading=${gpsHeading?.toStringAsFixed(1) ?? 'na'} movementBearing=${movementBearing?.toStringAsFixed(1) ?? 'na'} '
          'routeBearing=${routeBearing?.toStringAsFixed(1) ?? 'na'} usedBearing=${safeFallback.toStringAsFixed(1)} source=safe_fallback',
    );
    return (
      bearing: safeFallback,
      source: 'safe_fallback',
      gpsHeading: gpsHeading,
      movementBearing: movementBearing,
      routeBearing: routeBearing,
    );
  }

  double? _bearingFromPoints(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const degToRad = math.pi / 180.0;
    const radToDeg = 180.0 / math.pi;
    final dLon = (lon2 - lon1) * degToRad;
    final y = math.sin(dLon) * math.cos(lat2 * degToRad);
    final x =
        math.cos(lat1 * degToRad) * math.sin(lat2 * degToRad) -
        math.sin(lat1 * degToRad) * math.cos(lat2 * degToRad) * math.cos(dLon);
    if (!x.isFinite || !y.isFinite) return null;
    final brng = math.atan2(y, x) * radToDeg;
    return (brng + 360.0) % 360.0;
  }

  Future<geo.Position?> _fetchCurrentPositionForRecenter() async {
    final serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('[GPS][RECENTER][SERVICE_DISABLED]');
      _toast(
        _tr(
          nl: 'Locatieservice staat uit. Zet GPS aan om te centreren.',
          en: 'Location service is disabled. Enable GPS to recenter.',
          fr: 'Le service de localisation est desactive. Activez le GPS pour recentrer.',
          es: 'El servicio de ubicacion esta desactivado. Activa el GPS para recentrar.',
        ),
      );
      return null;
    }

    var permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
    }
    if (permission == geo.LocationPermission.denied ||
        permission == geo.LocationPermission.deniedForever) {
      debugPrint('[GPS][RECENTER][PERMISSION_DENIED]');
      _toast(
        _tr(
          nl: 'Geen locatiepermissie. Geef toegang om te centreren.',
          en: 'Location permission denied. Grant access to recenter.',
          fr: 'Permission de localisation refusee. Autorisez-la pour recentrer.',
          es: 'Permiso de ubicacion denegado. Concedelo para recentrar.',
        ),
      );
      return null;
    }

    debugPrint('[GPS][RECENTER][FETCH_START]');
    try {
      final pos = await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.best,
      ).timeout(const Duration(seconds: 10));
      debugPrint(
        '[GPS][RECENTER][FETCH_OK] lat=${pos.latitude.toStringAsFixed(6)} lng=${pos.longitude.toStringAsFixed(6)}',
      );
      return pos;
    } catch (e) {
      debugPrint('[GPS][RECENTER][ERROR] $e');
      _toast(
        _tr(
          nl: 'GPS-positie ophalen mislukt. Probeer opnieuw.',
          en: 'Failed to get GPS position. Please try again.',
          fr: 'Impossible de recuperer la position GPS. Reessayez.',
          es: 'No se pudo obtener la posicion GPS. Intentalo de nuevo.',
        ),
      );
      return null;
    }
  }

  Future<void> _centerOnMe() async {
    debugPrint('[GPS][RECENTER][TAP]');
    geo.Position? pos = _lastPos;
    if (pos != null) {
      debugPrint('[GPS][RECENTER][CACHE_HIT]');
    } else {
      pos = await _fetchCurrentPositionForRecenter();
      if (pos == null) return;
      _lastPos = pos;
    }

    if (_mapSupported && _map != null && _driverPointManager != null) {
      await _updateDriverMarker(pos, moveCamera: false);
    }

    // If NAV is enabled and a trip is active, use navigation follow camera.
    if (_cameraMode == _CameraMode.follow && _liveRideActive) {
      await _followCameraTesla(pos, force: true);
      return;
    }

    final p = _mbPoint(pos.longitude, pos.latitude);
    await _map?.flyTo(
      mb.CameraOptions(center: p, zoom: 13.5),
      mb.MapAnimationOptions(duration: 650),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  _ExternalNavTarget? _resolveExternalNavTarget() {
    if (_directRideDestinationPoint != null) {
      return _ExternalNavTarget(
        lat: _directRideDestinationPoint!.lat,
        lon: _directRideDestinationPoint!.lon,
      );
    }

    if (_routeCoords.isNotEmpty) {
      final destination = _routeCoords.last;
      return _ExternalNavTarget(lat: destination.lat, lon: destination.lon);
    }

    final bookingDestination = (_activeBooking?.to ?? '').trim();
    if (bookingDestination.isNotEmpty) {
      return _ExternalNavTarget(query: bookingDestination);
    }

    final directDestination = (_directRideDestinationText ?? '').trim();
    if (directDestination.isNotEmpty) {
      return _ExternalNavTarget(query: directDestination);
    }

    return null;
  }

  Future<void> _launchExternalNavUri(Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (ok || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _tr(
            nl: 'Navigatie-app kon niet worden geopend.',
            en: 'Could not open navigation app.',
            fr: 'Impossible d’ouvrir l’application de navigation.',
            es: 'No se pudo abrir la aplicación de navegación.',
          ),
        ),
      ),
    );
  }

  Future<void> _openInGoogleMaps() async {
    final target = _resolveExternalNavTarget();
    if (target == null) return;
    Uri uri;
    if (target.hasCoordinates) {
      uri = Uri.https('www.google.com', '/maps/dir/', <String, String>{
        'api': '1',
        'destination': '${target.lat},${target.lon}',
      });
    } else if (target.hasQuery) {
      uri = Uri.https('www.google.com', '/maps/dir/', <String, String>{
        'api': '1',
        'destination': target.query!.trim(),
      });
    } else {
      return;
    }
    await _launchExternalNavUri(uri);
  }

  Future<void> _openInWaze() async {
    final target = _resolveExternalNavTarget();
    if (target == null) return;
    Uri uri;
    if (target.hasCoordinates) {
      uri = Uri.https('waze.com', '/ul', <String, String>{
        'll': '${target.lat},${target.lon}',
        'navigate': 'yes',
      });
    } else if (target.hasQuery) {
      uri = Uri.https('waze.com', '/ul', <String, String>{
        'q': target.query!.trim(),
        'navigate': 'yes',
      });
    } else {
      return;
    }
    await _launchExternalNavUri(uri);
  }

  Widget _buildExternalNavButtons() {
    if (_resolveExternalNavTarget() == null) return const SizedBox.shrink();
    final buttonStyle = OutlinedButton.styleFrom(
      foregroundColor: Colors.white,
      backgroundColor: const Color(0xCC0B1326),
      side: BorderSide(color: kFluxidiYellow.withOpacity(0.78), width: 1.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          OutlinedButton.icon(
            style: buttonStyle,
            onPressed: _openInGoogleMaps,
            icon: const Icon(Icons.map, size: 16),
            label: Text(
              _tr(
                nl: 'Openen in Google Maps',
                en: 'Open in Google Maps',
                fr: 'Ouvrir dans Google Maps',
                es: 'Abrir en Google Maps',
              ),
            ),
          ),
          OutlinedButton.icon(
            style: buttonStyle,
            onPressed: _openInWaze,
            icon: const Icon(Icons.alt_route, size: 16),
            label: Text(
              _tr(
                nl: 'Openen in Waze',
                en: 'Open in Waze',
                fr: 'Ouvrir dans Waze',
                es: 'Abrir en Waze',
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------
  // ROUTE (Overview -> Follow)
  // -------------------------------

  Future<void> _buildOverviewRoute(BookingItem b) async {
    final epoch = _routeCleanupEpoch;
    final expectedBookingId = b.bookingId;
    if (!_isRouteTaskStillValid(
      epoch: epoch,
      expectedBookingId: expectedBookingId,
    )) {
      return;
    }
    if (!_mapSupported || _map == null) return;
    if ((b.from ?? '').isEmpty || (b.to ?? '').isEmpty) return;

    try {
      final pickupText = (b.from ?? '').trim();
      final dropoffText = (b.to ?? '').trim();
      // Preview must always represent booked ride path: pickup -> destination.
      // Never use current GPS here.
      try {
        if (_routeLineManager != null && _routeLineOutline != null) {
          await _routeLineManager!.delete(_routeLineOutline!);
        }
        if (_routeLineManager != null && _routeLine != null) {
          await _routeLineManager!.delete(_routeLine!);
        }
        _routeLineOutline = null;
        _routeLine = null;
        if (_pinsPointManager != null) {
          if (_pickupPin != null) await _pinsPointManager!.delete(_pickupPin!);
          if (_dropoffPin != null)
            await _pinsPointManager!.delete(_dropoffPin!);
        }
        _pickupPin = null;
        _dropoffPin = null;
      } catch (_) {}

      // Prefer server-side routing (Worker) so the app never needs to call Mapbox Directions directly.
      await _tryWorkerRouteFallback(
        fromText: pickupText,
        toText: dropoffText,
        epoch: epoch,
        expectedBookingId: expectedBookingId,
      );
      if (_routeCoords.length >= 2) return;

      // Fallback: direct Mapbox REST (dev only). If MAPBOX_TOKEN isn't provided, we stop here.
      if (kMapboxToken.trim().isEmpty) {
        await _tryWorkerRouteFallback(
          fromText: pickupText,
          toText: dropoffText,
          epoch: epoch,
          expectedBookingId: expectedBookingId,
        );
        return;
      }

      final fromLL = await _geocodeOne(pickupText);
      final toLL = await _geocodeOne(dropoffText);

      final route = await _directionsRoute(fromLL, toLL);
      final coords = route.$1;
      final distanceMeters = route.$2;
      final durationSec = route.$3;

      if (coords.length < 2) return;
      if (!_isRouteTaskStillValid(
        epoch: epoch,
        expectedBookingId: expectedBookingId,
      )) {
        return;
      }

      setState(() {
        _routeCoords = coords;
        _routeKm = distanceMeters / 1000.0;
        _routeDurationSec = durationSec;
        _routePhase = _RideRoutePhase.trip;
      });
      await _drawPins(fromLL, toLL);
      await _drawRouteLine(coords);
      final allowFit =
          _allowOverviewCamera &&
          _cameraMode == _CameraMode.overview &&
          _activeTripId == null;
      if (allowFit) {
        await _fitBoundsToRoute(coords);
      }
    } on _UnauthorizedMapbox catch (_) {
      _toast('Mapbox REST token refused (401) — using Worker route instead.');
      await _tryWorkerRouteFallback(
        fromText: b.from!,
        toText: b.to!,
        epoch: epoch,
        expectedBookingId: expectedBookingId,
      );
    } catch (e) {
      _toast('Route overview failed: $e');
      await _tryWorkerRouteFallback(
        fromText: b.from!,
        toText: b.to!,
        epoch: epoch,
        expectedBookingId: expectedBookingId,
      );
    }
  }

  Future<void> _tryWorkerRouteFallback({
    required String fromText,
    required String toText,
    required int epoch,
    required String expectedBookingId,
  }) async {
    try {
      final uri = Uri.parse('$kWorkerBaseUrl$kWorkerRoutePath');
      final payload = {'from': fromText, 'to': toText};

      final res = await http
          .post(uri, headers: _headers(admin: true), body: jsonEncode(payload))
          .timeout(const Duration(seconds: 12));

      if (res.statusCode == 404) {
        _toast(
          'Route via Worker not available yet (404). Implement $kWorkerRoutePath to avoid exposing Mapbox token.',
        );
        return;
      }

      if (res.statusCode != 200) {
        throw Exception('Worker route HTTP ${res.statusCode}: ${res.body}');
      }

      final j = jsonDecode(res.body) as Map<String, dynamic>;

      final coordsAny =
          (j['coords'] ?? j['coordinates'] ?? j['route_coords'] ?? j['points']);
      List<dynamic> raw;
      if (coordsAny is List) {
        raw = coordsAny;
      } else if (j['geometry'] is Map<String, dynamic>) {
        raw = (j['geometry']['coordinates'] as List<dynamic>? ?? []);
      } else {
        raw = const [];
      }

      final out = <_LonLat>[];
      for (final c in raw) {
        if (c is List && c.length >= 2) {
          out.add(_LonLat((c[0] as num).toDouble(), (c[1] as num).toDouble()));
        }
      }

      if (out.length < 2) return;
      if (!_isRouteTaskStillValid(
        epoch: epoch,
        expectedBookingId: expectedBookingId,
      )) {
        return;
      }

      final dist =
          (j['distance_m'] ?? j['distanceMeters'] ?? j['distance'] ?? 0) as num;
      final dur =
          (j['duration_s'] ?? j['durationSec'] ?? j['duration'] ?? 0) as num;

      final fromLL = out.first;
      final toLL = out.last;

      setState(() {
        _routeCoords = out;
        _routeKm = dist.toDouble() / 1000.0;
        _routeDurationSec = dur.toInt();
        _routePhase = _RideRoutePhase.trip;
      });
      await _drawPins(fromLL, toLL);
      await _drawRouteLine(out);
      final allowFit =
          _allowOverviewCamera &&
          _cameraMode == _CameraMode.overview &&
          _activeTripId == null;
      if (allowFit) {
        await _fitBoundsToRoute(out);
      }
    } catch (e) {
      _toast('Worker route failed: $e');
    }
  }

  Future<_LonLat> _geocodeOne(String query) async {
    final q = Uri.encodeComponent(query);
    final uri = Uri.parse(
      'https://api.mapbox.com/geocoding/v5/mapbox.places/$q.json'
      '?access_token=$kMapboxToken&limit=1&country=BE&language=nl',
    );

    final res = await http.get(uri).timeout(const Duration(seconds: 12));

    if (res.statusCode == 401) throw _UnauthorizedMapbox('geocoding');
    if (res.statusCode != 200) {
      throw Exception('Geocode HTTP ${res.statusCode}');
    }

    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final feats = (j['features'] as List<dynamic>? ?? []);
    if (feats.isEmpty) throw Exception('No geocode result for "$query"');
    final center =
        (feats.first as Map<String, dynamic>)['center'] as List<dynamic>;
    final lon = (center[0] as num).toDouble();
    final lat = (center[1] as num).toDouble();
    return _LonLat(lon, lat);
  }

  Future<(List<_LonLat>, double, int)> _directionsRoute(
    _LonLat from,
    _LonLat to,
  ) async {
    final coords = '${from.lon},${from.lat};${to.lon},${to.lat}';
    final lang = _mapboxDirectionsLanguageCode();
    final uri = Uri.parse(
      'https://api.mapbox.com/directions/v5/mapbox/driving/$coords'
      '?alternatives=false&geometries=geojson&overview=full&steps=true'
      '&language=$lang'
      '&access_token=$kMapboxToken',
    );

    final res = await http.get(uri).timeout(const Duration(seconds: 15));

    if (res.statusCode == 401) throw _UnauthorizedMapbox('directions');
    if (res.statusCode != 200) {
      throw Exception('Directions HTTP ${res.statusCode}');
    }

    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final routes = (j['routes'] as List<dynamic>? ?? []);
    if (routes.isEmpty) throw Exception('No route returned.');
    final r0 = routes.first as Map<String, dynamic>;
    final distance = (r0['distance'] as num?)?.toDouble() ?? 0.0;
    final duration = (r0['duration'] as num?)?.toInt() ?? 0;
    final geom = (r0['geometry'] as Map<String, dynamic>?) ?? {};
    final line = (geom['coordinates'] as List<dynamic>? ?? []);
    final out = <_LonLat>[];
    for (final c in line) {
      final pair = c as List<dynamic>;
      out.add(
        _LonLat((pair[0] as num).toDouble(), (pair[1] as num).toDouble()),
      );
    }
    final navSteps = <_NavStep>[];
    final legs = (r0['legs'] as List<dynamic>? ?? const <dynamic>[]);
    for (final legAny in legs) {
      final leg = (legAny is Map<String, dynamic>)
          ? legAny
          : <String, dynamic>{};
      final steps = (leg['steps'] as List<dynamic>? ?? const <dynamic>[]);
      for (final stepAny in steps) {
        final step = (stepAny is Map<String, dynamic>)
            ? stepAny
            : <String, dynamic>{};
        final maneuver = (step['maneuver'] is Map<String, dynamic>)
            ? (step['maneuver'] as Map<String, dynamic>)
            : <String, dynamic>{};
        final loc =
            (maneuver['location'] as List<dynamic>? ?? const <dynamic>[]);
        if (loc.length < 2) continue;
        final lon = (loc[0] as num?)?.toDouble();
        final lat = (loc[1] as num?)?.toDouble();
        if (lat == null || lon == null) continue;
        final rawInstruction = (maneuver['instruction'] ?? '')
            .toString()
            .trim();
        final instruction = _localizeNavInstructionMvp(rawInstruction);
        final street = (step['name'] ?? '').toString().trim();
        final type = (maneuver['type'] ?? '').toString().trim();
        final modifier = (maneuver['modifier'] ?? '').toString().trim();
        final stepDistance = (step['distance'] as num?)?.toDouble();
        final stepDuration = (step['duration'] as num?)?.toInt();
        if (instruction.isEmpty && street.isEmpty) continue;
        navSteps.add(
          _NavStep(
            lat: lat,
            lon: lon,
            instruction: instruction,
            street: street,
            type: type,
            modifier: modifier,
            distanceAlongRouteM: _distanceAlongRouteForCoords(
              out,
              _LonLat(lon, lat),
            ),
            distanceM: stepDistance,
            durationSec: stepDuration,
          ),
        );
      }
    }
    _routeSteps = navSteps;
    _nextStepIndex = 0;
    if (navSteps.isNotEmpty) {
      _nextNavInstruction = navSteps.first.instruction;
      _nextNavStreet = navSteps.first.street;
      _nextNavDistanceM = null;
      _nextNavType = navSteps.first.type;
      _nextNavModifier = navSteps.first.modifier;
    } else {
      _nextNavInstruction = null;
      _nextNavStreet = null;
      _nextNavDistanceM = null;
      _nextNavType = null;
      _nextNavModifier = null;
    }
    debugPrint('[NAV_STEPS] count=${navSteps.length}');
    return (out, distance, duration);
  }

  String _mapboxDirectionsLanguageCode() {
    final lang = appConfig.currentLanguage;
    if (lang == AppLanguage.fr) return 'fr';
    if (lang == AppLanguage.es) return 'es';
    if (lang == AppLanguage.en) return 'en';
    return 'nl';
  }

  String _localizeNavInstructionMvp(String raw) {
    if (raw.isEmpty) return raw;
    final lang = appConfig.currentLanguage;
    if (lang == AppLanguage.en) return raw;
    final lower = raw.toLowerCase();

    if (lower.contains('your destination is on the left')) {
      return _tr(
        nl: 'Je bestemming bevindt zich links',
        en: 'Your destination is on the left',
        fr: 'Votre destination se trouve sur la gauche',
        es: 'Tu destino está a la izquierda',
      );
    }
    if (lower.contains('your destination is on the right')) {
      return _tr(
        nl: 'Je bestemming bevindt zich rechts',
        en: 'Your destination is on the right',
        fr: 'Votre destination se trouve sur la droite',
        es: 'Tu destino está a la derecha',
      );
    }
    if (lower.startsWith('turn left') || lower.contains(' turn left')) {
      return _tr(
        nl: 'Sla linksaf',
        en: 'Turn left',
        fr: 'Tournez à gauche',
        es: 'Gira a la izquierda',
      );
    }
    if (lower.startsWith('turn right') || lower.contains(' turn right')) {
      return _tr(
        nl: 'Sla rechtsaf',
        en: 'Turn right',
        fr: 'Tournez à droite',
        es: 'Gira a la derecha',
      );
    }
    if (lower.startsWith('continue') || lower.contains(' continue')) {
      return _tr(
        nl: 'Rijd rechtdoor',
        en: 'Continue',
        fr: 'Continuez',
        es: 'Continúa',
      );
    }
    return raw;
  }

  String _navDistanceText(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000.0).toStringAsFixed(1).replaceAll('.', ',')} km';
  }

  bool _navTypeIsArrival(String? type) {
    final t = (type ?? '').toLowerCase();
    return t.contains('arrive') || t.contains('destination');
  }

  bool _navTypeIsRoundabout(String? type) {
    final t = (type ?? '').toLowerCase();
    return t.contains('roundabout') || t.contains('rotary');
  }

  String _shortNavAction(String instruction, String? type, String? modifier) {
    if (_navTypeIsArrival(type)) {
      return _tr(
        nl: 'bestemming bereikt',
        en: 'destination reached',
        fr: 'destination atteinte',
        es: 'destino alcanzado',
      );
    }
    if (_navTypeIsRoundabout(type)) {
      return _tr(
        nl: 'neem de rotonde',
        en: 'take the roundabout',
        fr: 'prenez le rond-point',
        es: 'toma la rotonda',
      );
    }
    final mod = (modifier ?? '').toLowerCase();
    if (mod.contains('slight left')) {
      return _tr(
        nl: 'flauw linksaf',
        en: 'slight left',
        fr: 'légèrement à gauche',
        es: 'ligeramente a la izquierda',
      );
    }
    if (mod.contains('slight right')) {
      return _tr(
        nl: 'flauw rechtsaf',
        en: 'slight right',
        fr: 'légèrement à droite',
        es: 'ligeramente a la derecha',
      );
    }
    if (mod.contains('left')) {
      return _tr(
        nl: 'linksaf',
        en: 'turn left',
        fr: 'tournez à gauche',
        es: 'gira a la izquierda',
      );
    }
    if (mod.contains('right')) {
      return _tr(
        nl: 'rechtsaf',
        en: 'turn right',
        fr: 'tournez à droite',
        es: 'gira a la derecha',
      );
    }
    if (mod.contains('straight') || mod.contains('forward')) {
      return _tr(
        nl: 'rechtdoor',
        en: 'continue straight',
        fr: 'continuez tout droit',
        es: 'sigue recto',
      );
    }

    final lower = instruction.toLowerCase();
    if (lower.contains('links') ||
        lower.contains('left') ||
        lower.contains('gauche')) {
      return _tr(
        nl: 'linksaf',
        en: 'turn left',
        fr: 'tournez à gauche',
        es: 'gira a la izquierda',
      );
    }
    if (lower.contains('rechts') ||
        lower.contains('right') ||
        lower.contains('droite')) {
      return _tr(
        nl: 'rechtsaf',
        en: 'turn right',
        fr: 'tournez à droite',
        es: 'gira a la derecha',
      );
    }
    if (lower.contains('rotonde') ||
        lower.contains('roundabout') ||
        lower.contains('rond-point')) {
      return _tr(
        nl: 'neem de rotonde',
        en: 'take the roundabout',
        fr: 'prenez le rond-point',
        es: 'toma la rotonda',
      );
    }
    if (lower.contains('rechtdoor') ||
        lower.contains('continue') ||
        lower.contains('straight')) {
      return _tr(
        nl: 'rechtdoor',
        en: 'continue straight',
        fr: 'continuez tout droit',
        es: 'sigue recto',
      );
    }
    return instruction;
  }

  IconData _maneuverIconData(
    String? type,
    String? modifier,
    String instruction,
  ) {
    if (_navTypeIsArrival(type)) return Icons.flag_rounded;
    if (_navTypeIsRoundabout(type)) return Icons.roundabout_right_rounded;
    final combined = '${modifier ?? ''} $instruction'.toLowerCase();
    if (combined.contains('slight left')) return Icons.turn_slight_left_rounded;
    if (combined.contains('slight right'))
      return Icons.turn_slight_right_rounded;
    if (combined.contains('left') ||
        combined.contains('links') ||
        combined.contains('gauche')) {
      return Icons.turn_left_rounded;
    }
    if (combined.contains('right') ||
        combined.contains('rechts') ||
        combined.contains('droite')) {
      return Icons.turn_right_rounded;
    }
    if ((type ?? '').toLowerCase().contains('exit') ||
        combined.contains('exit') ||
        combined.contains('afrit')) {
      return Icons.call_split_rounded;
    }
    return Icons.straight_rounded;
  }

  Future<void> _drawPins(_LonLat pickup, _LonLat dropoff) async {
    final mgr = _pinsPointManager;
    if (mgr == null) return;
    final now = DateTime.now();
    final signature =
        '${pickup.lon.toStringAsFixed(5)},${pickup.lat.toStringAsFixed(5)}|${dropoff.lon.toStringAsFixed(5)},${dropoff.lat.toStringAsFixed(5)}';
    final lastPinsAt = _lastPinsDrawAt;
    if (signature == _lastPinsDrawSignature &&
        lastPinsAt != null &&
        now.difference(lastPinsAt) < _routeDrawDebounce) {
      return;
    }
    _lastPinsDrawSignature = signature;
    _lastPinsDrawAt = now;

    try {
      if (_pickupPin != null) await mgr.delete(_pickupPin!);
      if (_dropoffPin != null) await mgr.delete(_dropoffPin!);
    } catch (_) {}

    _pickupPin = await mgr.create(
      mb.PointAnnotationOptions(
        geometry: _mbPoint(pickup.lon, pickup.lat),
        iconSize: 1.1,
      ),
    );

    _dropoffPin = await mgr.create(
      mb.PointAnnotationOptions(
        geometry: _mbPoint(dropoff.lon, dropoff.lat),
        iconSize: 1.1,
      ),
    );
  }

  Future<void> _drawRouteLine(
    List<_LonLat> coords, {
    bool force = false,
  }) async {
    final mgr = _routeLineManager;
    if (mgr == null) return;
    if (coords.length < 2) return;
    final first = coords.first;
    final last = coords.last;
    final now = DateTime.now();
    final signature =
        '${coords.length}:${first.lon.toStringAsFixed(5)},${first.lat.toStringAsFixed(5)}>${last.lon.toStringAsFixed(5)},${last.lat.toStringAsFixed(5)}';
    final lastRouteAt = _lastRouteDrawAt;
    if (!force &&
        signature == _lastRouteDrawSignature &&
        lastRouteAt != null &&
        now.difference(lastRouteAt) < _routeDrawDebounce) {
      return;
    }
    _lastRouteDrawSignature = signature;
    _lastRouteDrawAt = now;
    _routeRedrawCountThisMinute += 1;

    try {
      if (_routeLineOutline != null) await mgr.delete(_routeLineOutline!);
      if (_routeLine != null) await mgr.delete(_routeLine!);
    } catch (_) {}

    final geometry = mb.LineString(
      coordinates: coords.map((c) => mb.Position(c.lon, c.lat)).toList(),
    );

    // Dark underlay for contrast on light/dark roads.
    _routeLineOutline = await mgr.create(
      mb.PolylineAnnotationOptions(
        geometry: geometry,
        lineWidth: 15.0,
        lineOpacity: 0.62,
        lineColor: 0xCC0B1220,
      ),
    );

    // Bright active route shown above the outline.
    _routeLine = await mgr.create(
      mb.PolylineAnnotationOptions(
        geometry: geometry,
        lineWidth: 11.0,
        lineOpacity: 0.98,
        lineColor: 0xFF2D8CFF,
      ),
    );
  }

  Future<void> _fitBoundsToRoute(List<_LonLat> coords) async {
    final skip =
        _cameraMode == _CameraMode.follow ||
        _activeTripId != null ||
        !_allowOverviewCamera;
    if (_map == null || coords.isEmpty) return;
    if (skip) return;

    double minLon = coords.first.lon, maxLon = coords.first.lon;
    double minLat = coords.first.lat, maxLat = coords.first.lat;
    for (final c in coords) {
      if (c.lon < minLon) minLon = c.lon;
      if (c.lon > maxLon) maxLon = c.lon;
      if (c.lat < minLat) minLat = c.lat;
      if (c.lat > maxLat) maxLat = c.lat;
    }

    final topPad = MediaQuery.of(context).padding.top + 86;
    final bottomPad = MediaQuery.of(context).padding.bottom + 210;

    try {
      final cam = await _map!.cameraForCoordinateBounds(
        mb.CoordinateBounds(
          southwest: _mbPoint(minLon, minLat),
          northeast: _mbPoint(maxLon, maxLat),
          infiniteBounds: false,
        ),
        mb.MbxEdgeInsets(top: topPad, left: 40, bottom: bottomPad, right: 40),
        null,
        null,
        null,
        null,
      );
      await _map!.flyTo(cam, mb.MapAnimationOptions(duration: 900));
    } catch (_) {
      final center = _mbPoint((minLon + maxLon) / 2, (minLat + maxLat) / 2);
      await _map!.flyTo(
        mb.CameraOptions(center: center, zoom: 12.5),
        mb.MapAnimationOptions(duration: 900),
      );
    }
  }

  void _markBootFirstLoadDone() {
    if (_bootFirstLoadDone) return;
    _bootFirstLoadDone = true;
    _maybeHideBootSplash();
  }

  void _maybeHideBootSplash() {
    if (!_bootSplashVisible) return;
    if (!_bootMinElapsed) return;
    if (!_bootFirstLoadDone) return;
    if (!mounted) return;
    setState(() {
      _bootSplashVisible = false;
      _showBootSplash = false;
    });
  }

  InputDecoration _inputDeco(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.white.withOpacity(0.55)),
      filled: true,
      fillColor: Colors.black.withOpacity(0.35),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.18)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: kGlow, width: 1.2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  Future<List<_PlaceSuggestion>> _fetchPlaceSuggestions(String query) async {
    final q = query.trim();
    if (q.isEmpty || kMapboxToken.trim().isEmpty) return <_PlaceSuggestion>[];
    final encoded = Uri.encodeComponent(q);
    final uri = Uri.parse(
      'https://api.mapbox.com/geocoding/v5/mapbox.places/$encoded.json'
      '?autocomplete=true&limit=6&country=be&language=nl&access_token=$kMapboxToken',
    );
    try {
      final res = await http.get(uri);
      if (res.statusCode != 200) return <_PlaceSuggestion>[];
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final feats = (data['features'] as List<dynamic>? ?? const <dynamic>[]);
      final out = <_PlaceSuggestion>[];
      for (final f in feats) {
        final m = f as Map<String, dynamic>;
        final label = (m['place_name'] as String?) ?? '';
        final center = (m['center'] as List<dynamic>?);
        if (label.trim().isEmpty) continue;
        double? lon;
        double? lat;
        if (center != null && center.length >= 2) {
          lon = (center[0] as num?)?.toDouble();
          lat = (center[1] as num?)?.toDouble();
        }
        out.add(_PlaceSuggestion(label: label, lon: lon, lat: lat));
      }
      return out;
    } catch (_) {
      return <_PlaceSuggestion>[];
    }
  }

  void _onFromChanged(String v) {
    _fromDebounce?.cancel();
    _fromDebounce = Timer(const Duration(milliseconds: 220), () async {
      final list = await _fetchPlaceSuggestions(v);
      if (!mounted) return;
      setState(() => _fromSuggestions = list);
    });
  }

  void _onToChanged(String v) {
    _toDebounce?.cancel();
    _toDebounce = Timer(const Duration(milliseconds: 220), () async {
      final list = await _fetchPlaceSuggestions(v);
      if (!mounted) return;
      setState(() => _toSuggestions = list);
    });
  }

  Future<void> _useCurrentLocationAsFrom() async {
    try {
      final perm = await geo.Geolocator.checkPermission();
      if (perm == geo.LocationPermission.denied ||
          perm == geo.LocationPermission.deniedForever) {
        final req = await geo.Geolocator.requestPermission();
        if (req == geo.LocationPermission.denied ||
            req == geo.LocationPermission.deniedForever)
          return;
      }
      final pos = await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.best,
      );
      _manualFromPoint = mb.Point(
        coordinates: mb.Position(pos.longitude, pos.latitude),
      );
      _manualFromCtrl.text = 'Mijn locatie';
      setState(() {
        _fromSuggestions = <_PlaceSuggestion>[];
      });
    } catch (_) {}
  }

  Widget _suggestionList({
    required List<_PlaceSuggestion> items,
    required void Function(_PlaceSuggestion) onPick,
  }) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0F1C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x44FFD54A)),
      ),
      constraints: const BoxConstraints(maxHeight: 220),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 6),
        shrinkWrap: true,
        itemCount: items.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, color: Color(0x22000000)),
        itemBuilder: (_, i) {
          final s = items[i];
          return ListTile(
            dense: true,
            title: Text(
              s.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white),
            ),
            onTap: () => onPick(s),
          );
        },
      ),
    );
  }

  Future<void> _startManualTrip() async {
    final from = _manualFromCtrl.text.trim();
    final to = _manualToCtrl.text.trim();
    if (from.isEmpty || to.isEmpty) {
      _toast('Vul zowel "Van" als "Naar" in.');
      return;
    }

    final id = 'MANUAL-${DateTime.now().millisecondsSinceEpoch}';
    final b = BookingItem(
      bookingId: id,
      from: from,
      to: to,
      pickupIso: DateTime.now().toUtc().toIso8601String(),
      status: 'manual',
      currency: 'EUR',
    );

    await _startTrip(b);
  }

  Widget _buildBrandBar(bool tripActive) {
    // Robust top bar: larger logo + stronger presence.
    // Pulse only when a trip is active (cockpit mode).
    final pulse = tripActive ? (0.70 + 0.30 * _activePulse.value) : 0.0;

    return AnimatedBuilder(
      animation: _activePulse,
      builder: (context, _) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              height: 68,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: kFluxidiPanel.withOpacity(0.88),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white.withOpacity(0.10)),
                boxShadow: [
                  BoxShadow(
                    color: kFluxidiYellowSoft.withOpacity(
                      tripActive ? 0.55 * pulse : 0.20,
                    ),
                    blurRadius: tripActive ? (28 * pulse) : 18,
                    spreadRadius: tripActive ? (2 * pulse) : 1,
                  ),
                ],
              ),
              child: Row(
                children: [
                  _GlowIconButton(
                    icon: Icons.menu,
                    tooltip: 'Menu',
                    onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                  ),
                  const SizedBox(width: 10),
                  // Pulsing logo capsule (only on active trip)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      color: Colors.black.withOpacity(0.18),
                      border: Border.all(
                        color: const Color(0xFFFFD36A).withOpacity(
                          tripActive ? (0.30 + 0.25 * pulse) : 0.18,
                        ),
                      ),
                      boxShadow: tripActive
                          ? [
                              BoxShadow(
                                color: const Color(
                                  0x66F5C400,
                                ).withOpacity(0.55 * pulse),
                                blurRadius: 26 * pulse,
                                spreadRadius: 2 * pulse,
                              ),
                            ]
                          : const [],
                    ),
                    child: Transform.scale(
                      scale: tripActive ? (1.00 + 0.05 * pulse) : 1.0,
                      child: _tenantLogo(
                        height: 40,
                        fallback: Text(
                          kCompanyName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      tripActive ? 'Rit actief' : 'Driver console',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.92),
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: tripActive
                          ? const Color(0xFF4CD964)
                          : Colors.white38,
                      shape: BoxShape.circle,
                      boxShadow: tripActive
                          ? [
                              BoxShadow(
                                color: const Color(0x554CD964).withOpacity(0.7),
                                blurRadius: 14,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
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

  /// ===============================
  /// Fluxidi Cockpit UI (Design v1)
  /// ===============================

  /// Top status strip: branding + single dot (no extra text)
  Widget _buildStatusStrip(int state) {
    final bool active = state != 0;
    final media = MediaQuery.of(context);
    final bool compactNavHeader =
        media.orientation == Orientation.portrait &&
        _cameraMode == _CameraMode.follow;
    final dotColor = (state == 2)
        ? Colors.greenAccent
        : (state == 1)
        ? Colors.amberAccent
        : Colors.redAccent;

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          height: compactNavHeader ? 118 : 140,
          padding: EdgeInsets.symmetric(horizontal: compactNavHeader ? 10 : 14),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(compactNavHeader ? 0.30 : 0.22),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
          ),
          child: Row(
            children: [
              // Hamburger (everyone understands this)
              IconButton(
                tooltip: 'Menu',
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                icon: Icon(
                  Icons.menu_rounded,
                  color: Colors.white.withOpacity(0.88),
                  size: compactNavHeader ? 28 : 32,
                ),
              ),

              // Center logo (bigger, cockpit-style)
              Expanded(
                child: Center(
                  child: AnimatedBuilder(
                    animation: _activePulseCtrl,
                    builder: (_, __) {
                      final pulse = active
                          ? (0.98 + 0.04 * _activePulse.value)
                          : 1.0;
                      return Transform.scale(
                        scale: compactNavHeader
                            ? (pulse * 1.28)
                            : (pulse * 1.6),
                        child: _tenantLogo(
                          height: compactNavHeader ? 68 : 92,
                          fallback: const Icon(
                            Icons.local_taxi,
                            size: 32,
                            color: Colors.white70,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              // Single status dot (pulses only when active)
              AnimatedBuilder(
                animation: _activePulseCtrl,
                builder: (_, __) {
                  final pulse = active
                      ? (0.75 + 0.25 * _activePulse.value)
                      : 1.0;
                  return Transform.scale(
                    scale: compactNavHeader ? (pulse * 1.2) : (pulse * 1.6),
                    child: Container(
                      width: compactNavHeader ? 11 : 14,
                      height: compactNavHeader ? 11 : 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: dotColor.withOpacity(active ? 1.0 : 0.9),
                        boxShadow: [
                          BoxShadow(
                            color: dotColor.withOpacity(active ? 0.55 : 0.35),
                            blurRadius: active ? 18 : 10,
                            spreadRadius: active ? 2 : 1,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              SizedBox(width: compactNavHeader ? 6 : 12),
            ],
          ),
        ),
      ),
    );
  }

  /// Bottom glass HUD (map remains primary)
  Widget _buildCockpitHud({required bool liveActive}) {
    final b = _activeBooking;
    final from = (b?.from ?? '').trim();
    final to = (b?.to ?? '').trim();

    final routeText = [
      if (from.isNotEmpty) 'A: $from',
      if (to.isNotEmpty) 'B: $to',
    ].join('  ->  ');

    // Fallback if destination is missing
    final hasB = to.isNotEmpty;
    final routeTextSafe = hasB
        ? routeText
        : (routeText.isNotEmpty ? (routeText + '  ->  B: —') : 'B: —');

    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.18),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
          ),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Route ticker (only route, no labels/icons beyond A/B)
                if (routeText.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      color: Colors.white.withOpacity(0.06),
                      child: Center(
                        child: RouteMarquee(
                          key: const ValueKey('route_marquee'),
                          text: routeTextSafe,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            letterSpacing: 0.2,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Price orb + mode (fixed/live) — minimal, cockpit-style
                  Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withOpacity(0.18),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.12),
                          ),
                          boxShadow: [
                            BoxShadow(
                              blurRadius: 18,
                              spreadRadius: 1,
                              color:
                                  (liveActive
                                          ? Colors.greenAccent
                                          : Colors.amberAccent)
                                      .withOpacity(0.12),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            liveActive ? '●' : '◐',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: liveActive
                                  ? Colors.greenAccent
                                  : Colors.amberAccent,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                // Primary action
                Center(
                  child: SizedBox(
                    width: 220,
                    height: 56,
                    child: FilledButton(
                      style:
                          FilledButton.styleFrom(
                            backgroundColor: liveActive
                                ? Colors.redAccent.withOpacity(0.95)
                                : const Color(0xFF1B7F3A),
                            shape: const StadiumBorder(),
                            elevation: 0,
                          ).copyWith(
                            side: MaterialStateProperty.all(
                              BorderSide(
                                color: liveActive
                                    ? Colors.redAccent.withOpacity(0.95)
                                    : kFluxidiYellow.withOpacity(0.95),
                                width: 1.2,
                              ),
                            ),
                            overlayColor: MaterialStateProperty.all(
                              kFluxidiYellowSoft,
                            ),
                          ),
                      onPressed: () async {
                        if (liveActive) {
                          await _stopTripSafely();
                        } else {
                          final b = _activeBooking;
                          if (b == null) return;
                          await _startTrip(b);
                        }
                      },
                      child: Text(
                        liveActive ? 'STOP' : 'START',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dial({
    required String label,
    required String value,
    required bool big,
  }) {
    final size = big ? 92.0 : 78.0;
    final valueStyle = TextStyle(
      color: Colors.white,
      fontSize: big ? 26 : 18,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.3,
    );

    return Center(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.06),
          border: Border.all(color: Colors.white.withOpacity(0.10)),
          boxShadow: [
            BoxShadow(
              color: Colors.white.withOpacity(0.06),
              blurRadius: 14,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value, textAlign: TextAlign.center, style: valueStyle),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.55),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Active trip elapsed time
  Duration get _activeElapsed {
    final started = _trackingStartedAt;
    if (started == null) return Duration.zero;
    final now = DateTime.now();
    final d = now.difference(started);
    if (d.isNegative) return Duration.zero;
    return d;
  }

  String get _etaString {
    // ETA as countdown (remaining time), not clock-time.
    final totalSec = _routeDurationSec;
    if (totalSec == null || totalSec <= 0) return '—';

    final elapsed = _activeElapsed.inSeconds;
    final remaining = math.max(0, totalSec - elapsed);

    if (remaining < 60) return '<1 min';

    final minutes = (remaining / 60).ceil();
    if (minutes < 60) return '$minutes min';

    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (mins == 0) return '${hours}h';
    return '${hours}h ${mins}m';
  }

  Future<void> _stopTripSafely() async {
    // Keep existing stop logic if present
    await _stopTrip();
  }

  String _formatHms(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Widget _buildBootSplashOverlay() {
    final pulse = _splashPulse.value;

    // Premium boot overlay: subtle golden aura + animated ring + logo shimmer.
    return IgnorePointer(
      ignoring: true,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 280),
        opacity: _showBootSplash ? 1 : 0,
        child: Container(
          color: const Color(0xFF070709),
          child: Stack(
            children: [
              // Background aura
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -0.25),
                      radius: 0.95,
                      colors: [
                        const Color(
                          0x33FFD36A,
                        ).withOpacity(0.35 + 0.15 * pulse),
                        const Color(0x00070709),
                      ],
                    ),
                  ),
                ),
              ),

              // Center brand
              Center(
                child: AnimatedBuilder(
                  animation: _splashAnimCtrl,
                  builder: (context, _) {
                    final p = _splashPulse.value;
                    final ringAlpha = (0.22 + 0.18 * p).clamp(0.0, 1.0);
                    final glowAlpha = (0.45 + 0.30 * p).clamp(0.0, 1.0);
                    final scale = 0.985 + 0.025 * p;

                    return Transform.scale(
                      scale: scale,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 280,
                            height: 280,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // Outer animated ring
                                Container(
                                  width: 268,
                                  height: 268,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Color.fromRGBO(
                                        255,
                                        211,
                                        106,
                                        ringAlpha,
                                      ),
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Color.fromRGBO(
                                          255,
                                          211,
                                          106,
                                          glowAlpha,
                                        ),
                                        blurRadius: 28 + 18 * p,
                                        spreadRadius: 2 + 2 * p,
                                      ),
                                    ],
                                  ),
                                ),

                                // Inner soft ring
                                Container(
                                  width: 214,
                                  height: 214,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Color.fromRGBO(
                                        255,
                                        211,
                                        106,
                                        (ringAlpha * 0.55).clamp(0.0, 1.0),
                                      ),
                                      width: 1,
                                    ),
                                  ),
                                ),

                                // Logo + shimmer mask
                                ShaderMask(
                                  shaderCallback: (rect) {
                                    // Shimmer sweeps horizontally across the logo
                                    final t = _splashAnimCtrl.value; // 0..1
                                    final start = -0.6 + 1.6 * t;
                                    return LinearGradient(
                                      begin: Alignment(start, 0),
                                      end: Alignment(start + 0.8, 0),
                                      colors: const [
                                        Color(0x66FFFFFF),
                                        Color(0xFFFFFFFF),
                                        Color(0x66FFFFFF),
                                      ],
                                      stops: const [0.0, 0.5, 1.0],
                                    ).createShader(rect);
                                  },
                                  blendMode: BlendMode.srcATop,
                                  child: SizedBox(
                                    width: 210,
                                    height: 210,
                                    child: _tenantLogo(
                                      height: 210,
                                      fallback: const Text(
                                        'FLUXIDI',
                                        style: TextStyle(
                                          color: Color(0xFFFFD36A),
                                          fontSize: 32,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 4,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 22),
                          Text(
                            kCompanyName,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Driver • Live Tracking',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.78),
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 18),
                          // Minimal loading hint
                          SizedBox(
                            width: 120,
                            child: LinearProgressIndicator(
                              minHeight: 3,
                              backgroundColor: const Color(0x22FFFFFF),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Color.fromRGBO(
                                  255,
                                  211,
                                  106,
                                  (0.75 + 0.20 * p).clamp(0.0, 1.0),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  ButtonStyle _ghostButtonStyle() {
    return OutlinedButton.styleFrom(
      foregroundColor: Colors.white,
      side: BorderSide(color: kFluxidiYellow.withOpacity(0.85), width: 1.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ).copyWith(overlayColor: MaterialStateProperty.all(kFluxidiYellowSoft));
  }

  ButtonStyle _startButtonStyle() {
    return FilledButton.styleFrom(
      backgroundColor: Colors.black.withOpacity(0.55),
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    ).copyWith(
      side: MaterialStateProperty.all(
        BorderSide(color: kFluxidiYellow.withOpacity(0.95), width: 1.2),
      ),
      shadowColor: MaterialStateProperty.all(kFluxidiYellowSoft),
      elevation: MaterialStateProperty.all(0),
      overlayColor: MaterialStateProperty.all(kFluxidiYellowSoft),
    );
  }

  String _rideStatusLabel(String rawStatus) {
    final s = rawStatus.trim().toUpperCase();
    if (s.isEmpty || s == 'PENDING') return kRideStatusPendingLabel;
    if (s == 'COMPLETED') return kRideActionCompletedLabel;
    if (s == 'CANCELLED') return kRideActionCancelledLabel;
    return rawStatus.trim();
  }

  // -------------------------------
  // UI helpers for stats
  // -------------------------------

  int? _remainingSec() {
    final remainingKm = (_routeKm != null)
        ? (_routeKm! - _kmDriven).clamp(0.0, 999999.0)
        : null;
    if (_routeDurationSec == null ||
        _routeKm == null ||
        _routeKm! <= 0 ||
        remainingKm == null)
      return null;
    final ratio = (remainingKm / _routeKm!).clamp(0.0, 1.0);
    return (_routeDurationSec! * ratio).round();
  }

  String _fmtDur(int? sec) {
    if (sec == null) return '—';
    final m = (sec / 60).round();
    if (m < 60) return '$m min';
    final h = (m / 60).floor();
    final mm = m % 60;
    return '${h}u ${mm}m';
  }

  String _fmtRemainingKm() {
    final remainingKm = (_routeKm != null)
        ? (_routeKm! - _kmDriven).clamp(0.0, 999999.0)
        : null;
    if (remainingKm == null) return '—';
    return remainingKm.toStringAsFixed(1);
  }

  String _fmtPrice() {
    final b = _activeBooking;
    if (b?.price == null) return '—';
    return b!.price!.toStringAsFixed(2);
  }

  String _fmtMoney(num amount, String currency) {
    // Keep it simple & predictable (no locale surprises)
    final value = amount.toDouble().toStringAsFixed(2);
    final cur = currency.toUpperCase();
    if (cur == 'EUR' || cur == 'EURO' || cur == '€') return '€ $value';
    if (cur.length <= 3) return '$cur $value';
    return '$value';
  }

  // -------------------------------
  // UI
  // -------------------------------

  Widget _buildHintPanel() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF081126).withOpacity(0.78),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFFFFD36A).withOpacity(0.22),
              width: 1.1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.info_outline, color: Color(0xFFFFD36A)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _hintPanelText(),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.72),
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _openDirectRideEntry,
                  icon: const Icon(Icons.local_taxi_outlined, size: 18),
                  label: Text(
                    _tr(
                      nl: 'Straatrit starten',
                      en: 'Start direct ride',
                      fr: 'Demarrer une course directe',
                      es: 'Iniciar viaje directo',
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFFD36A),
                    side: BorderSide(
                      color: const Color(0xFFFFD36A).withOpacity(0.70),
                      width: 1.1,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(
                      vertical: 11,
                      horizontal: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTurnInstructionBanner({required bool compact}) {
    final dist = _nextNavDistanceM ?? 0.0;
    final instruction = (_nextNavInstruction ?? '').trim();
    final street = (_nextNavStreet ?? '').trim();
    final action = _shortNavAction(instruction, _nextNavType, _nextNavModifier);
    final distanceText = _navDistanceText(dist);
    final line1 = _navTypeIsArrival(_nextNavType)
        ? action
        : _tr(
            nl: 'Over ${_navDistanceText(dist)} $action',
            en: 'In ${_navDistanceText(dist)} $action',
            fr: 'Dans ${_navDistanceText(dist)} $action',
            es: 'En ${_navDistanceText(dist)} $action',
          );
    final icon = _maneuverIconData(_nextNavType, _nextNavModifier, instruction);

    return ClipRRect(
      borderRadius: BorderRadius.circular(compact ? 14 : 16),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: compact ? 7 : 9,
          sigmaY: compact ? 7 : 9,
        ),
        child: Container(
          constraints: BoxConstraints(maxHeight: compact ? 58 : 64),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 10,
            vertical: compact ? 4 : 5,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF07142D).withOpacity(0.88),
            borderRadius: BorderRadius.circular(compact ? 14 : 16),
            border: Border.all(color: const Color(0x662D8CFF), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.30),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: compact ? 34 : 38,
                height: compact ? 34 : 38,
                decoration: BoxDecoration(
                  color: const Color(0xFF2D8CFF),
                  borderRadius: BorderRadius.circular(compact ? 10 : 12),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.80),
                    width: 1.2,
                  ),
                ),
                child: Icon(icon, size: compact ? 22 : 24, color: Colors.white),
              ),
              SizedBox(width: compact ? 6 : 8),
              if (!_navTypeIsArrival(_nextNavType))
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 6 : 7,
                    vertical: compact ? 3 : 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x332D8CFF),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white.withOpacity(0.18)),
                  ),
                  child: Text(
                    distanceText,
                    style: TextStyle(
                      fontSize: compact ? 10 : 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.white.withOpacity(0.96),
                    ),
                  ),
                ),
              if (!_navTypeIsArrival(_nextNavType))
                SizedBox(width: compact ? 6 : 8),
              Expanded(
                child: Text(
                  street.isNotEmpty ? '$line1 • $street' : line1,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 13 : 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavLoadingBanner({required bool compact}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(compact ? 9 : 10),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: compact ? 7 : 8,
          sigmaY: compact ? 7 : 8,
        ),
        child: Container(
          constraints: BoxConstraints(maxHeight: compact ? 44 : 48),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 9,
            vertical: compact ? 3 : 4,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF0B1733).withOpacity(0.78),
            borderRadius: BorderRadius.circular(compact ? 9 : 10),
            border: Border.all(color: const Color(0x332D8CFF)),
          ),
          child: Text(
            'Route-instructies worden geladen...',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w700,
              color: Colors.white.withOpacity(0.92),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNoNavInstructionsBanner({required bool compact}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(compact ? 9 : 10),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: compact ? 7 : 8,
          sigmaY: compact ? 7 : 8,
        ),
        child: Container(
          constraints: BoxConstraints(maxHeight: compact ? 44 : 48),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 9,
            vertical: compact ? 3 : 4,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF0B1733).withOpacity(0.78),
            borderRadius: BorderRadius.circular(compact ? 9 : 10),
            border: Border.all(color: const Color(0x33FF8A80)),
          ),
          child: Text(
            'Geen route-instructies beschikbaar',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w700,
              color: Colors.white.withOpacity(0.92),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecenterButton() {
    return Tooltip(
      message: kCenterOnMeLabel,
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _centerOnMe,
              child: Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF07142D).withOpacity(0.88),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFFFD36A).withOpacity(0.55),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.30),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.my_location,
                  color: Color(0xFFFFD36A),
                  size: 24,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _hintPanelText() {
    final lang = appConfig.currentLanguage;
    if (lang == AppLanguage.en) {
      return 'Open menu -> Bookings to choose a ride and start it to drive.';
    }
    if (lang == AppLanguage.fr) {
      return 'Ouvrez le menu -> Courses pour choisir une course et la demarrer.';
    }
    if (lang == AppLanguage.es) {
      return 'Abre el menu -> Reservas para elegir un viaje e iniciarlo.';
    }
    return 'Open menu -> Ritten om een rit te kiezen en start hem om te rijden.';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final lastBuildLog = _lastDriverBuildLogAt;
    if (lastBuildLog == null || now.difference(lastBuildLog).inSeconds >= 5) {
      _lastDriverBuildLogAt = now;
      debugPrint(
        '[DRIVER][BUILD] live=$_liveRideActive mode=$_cameraMode loadingBookings=$_loadingBookings',
      );
    }
    final bool liveActive = _liveRideActive;
    final bool hasSelection = _activeBooking != null;
    final bool hasDirectDraft = _directRideDraft;
    final int state = liveActive
        ? 2
        : ((hasSelection || hasDirectDraft) ? 1 : 0);
    final bool showCockpit = liveActive || hasSelection || hasDirectDraft;
    final bool showExternalNavButtons =
        showCockpit && _resolveExternalNavTarget() != null;
    final screenH = MediaQuery.of(context).size.height;
    final screenW = MediaQuery.of(context).size.width;
    final bool isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final bool collapseTopBarInLandscapeNav =
        isLandscape && _cameraMode == _CameraMode.follow;
    final bool collapseTopBarInPortraitNav =
        !isLandscape && _cameraMode == _CameraMode.follow;
    final double arrowBottom = isLandscape ? 106.0 : 152.0;
    final double safeBottomInset = MediaQuery.of(context).padding.bottom;
    final double recenterBottom = isLandscape
        ? (showCockpit ? (showExternalNavButtons ? 184.0 : 128.0) : 112.0) +
              safeBottomInset
        : (showCockpit ? (showExternalNavButtons ? 266.0 : 188.0) : 150.0) +
              safeBottomInset;
    final double navBannerLandscapeMaxWidth = math.min(760.0, screenW * 0.46);
    final double navBannerPortraitMaxWidth = math.min(screenW * 0.88, 700.0);
    final double navBannerTop =
        MediaQuery.of(context).padding.top +
        (isLandscape ? 8 : (_cameraMode == _CameraMode.follow ? 58 : 74));
    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildDrawer(),
      body: Stack(
        clipBehavior: Clip.none,
        children: [
          // Map always at the back.
          Positioned.fill(child: _buildMapLayer()),

          // Top status / header (Fluxidi strip).
          if (!collapseTopBarInLandscapeNav && !collapseTopBarInPortraitNav)
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              left: 12,
              right: 12,
              child: _buildStatusStrip(state),
            ),
          if (collapseTopBarInLandscapeNav || collapseTopBarInPortraitNav)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 10,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.26),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withOpacity(0.14)),
                    ),
                    child: IconButton(
                      tooltip: 'Menu',
                      onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                      icon: const Icon(Icons.menu_rounded, size: 22),
                    ),
                  ),
                ),
              ),
            ),
          if (_cameraMode == _CameraMode.follow && _nextNavInstruction != null)
            Positioned(
              top: navBannerTop,
              left: isLandscape ? 62 : 0,
              right: isLandscape ? null : 0,
              child: isLandscape
                  ? ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: navBannerLandscapeMaxWidth,
                      ),
                      child: _buildTurnInstructionBanner(compact: true),
                    )
                  : Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: navBannerPortraitMaxWidth,
                        ),
                        child: _buildTurnInstructionBanner(compact: false),
                      ),
                    ),
            ),
          if (_cameraMode == _CameraMode.follow &&
              _nextNavInstruction == null &&
              _navStepsLoading)
            Positioned(
              top: navBannerTop,
              left: isLandscape ? 62 : 0,
              right: isLandscape ? null : 0,
              child: isLandscape
                  ? ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: navBannerLandscapeMaxWidth,
                      ),
                      child: _buildNavLoadingBanner(compact: true),
                    )
                  : Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: navBannerPortraitMaxWidth,
                        ),
                        child: _buildNavLoadingBanner(compact: false),
                      ),
                    ),
            ),
          if (_cameraMode == _CameraMode.follow &&
              !_navStepsLoading &&
              _routeSteps.isEmpty)
            Positioned(
              top: navBannerTop,
              left: isLandscape ? 62 : 0,
              right: isLandscape ? null : 0,
              child: isLandscape
                  ? ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: navBannerLandscapeMaxWidth,
                      ),
                      child: _buildNoNavInstructionsBanner(compact: true),
                    )
                  : Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: navBannerPortraitMaxWidth,
                        ),
                        child: _buildNoNavInstructionsBanner(compact: false),
                      ),
                    ),
            ),
          if (_cameraMode == _CameraMode.follow)
            Positioned(
              left: 0,
              right: 0,
              bottom: arrowBottom,
              child: IgnorePointer(
                child: Center(
                  child: Transform.rotate(
                    angle: _uiArrowBearing * math.pi / 180.0,
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2D8CFF).withOpacity(0.96),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withOpacity(0.92),
                          width: 2.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.42),
                            blurRadius: 14,
                            spreadRadius: 1.0,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.navigation,
                        color: Colors.white,
                        size: 34,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (_mapSupported)
            Positioned(
              right: 14,
              bottom: recenterBottom,
              child: _buildRecenterButton(),
            ),

          // Bottom overlay layer (cockpit / idle / hint).
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeOut,
              child: isLandscape
                  ? SafeArea(
                      key: ValueKey<String>(
                        'landscape_${showCockpit ? 'cockpit' : 'hint'}',
                      ),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: EdgeInsets.only(
                            left: 10,
                            right: 10,
                            bottom:
                                MediaQuery.of(context).viewInsets.bottom + 4,
                          ),
                          child: showCockpit
                              ? SizedBox(
                                  width: double.infinity,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      CockpitWidget(
                                        etaText: _etaText,
                                        kmText: _kmRemainingText,
                                        priceText: _cockpitPriceText,
                                        tripStarted: _liveRideActive,
                                        isWaiting: _isWaiting,
                                        navActive:
                                            _cameraMode == _CameraMode.follow,
                                        onNav: _openNavigation,
                                        onStart: _handleCockpitStart,
                                        onStop: _stopTrip,
                                        onWait: _enterWaitMode,
                                        onGo: _exitWaitMode,
                                      ),
                                      if (showExternalNavButtons)
                                        _buildExternalNavButtons(),
                                    ],
                                  ),
                                )
                              : ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: math.min(
                                      420,
                                      MediaQuery.of(context).size.width * 0.5,
                                    ),
                                  ),
                                  child: _buildHintPanel(),
                                ),
                        ),
                      ),
                    )
                  : SafeArea(
                      key: ValueKey<String>(
                        'portrait_${showCockpit ? 'cockpit' : 'hint'}',
                      ),
                      minimum: const EdgeInsets.only(bottom: 6),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: EdgeInsets.only(
                            left: 12,
                            right: 12,
                            bottom:
                                MediaQuery.of(context).viewInsets.bottom + 6,
                          ),
                          child: showCockpit
                              ? Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CockpitWidget(
                                      etaText: _etaText,
                                      kmText: _kmRemainingText,
                                      priceText: _cockpitPriceText,
                                      tripStarted: _liveRideActive,
                                      isWaiting: _isWaiting,
                                      navActive:
                                          _cameraMode == _CameraMode.follow,
                                      onNav: _openNavigation,
                                      onStart: _handleCockpitStart,
                                      onStop: _stopTrip,
                                      onWait: _enterWaitMode,
                                      onGo: _exitWaitMode,
                                    ),
                                    if (showExternalNavButtons)
                                      _buildExternalNavButtons(),
                                  ],
                                )
                              : _buildHintPanel(),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapLayer() {
    final now = DateTime.now();
    final lastBuildLog = _lastMapWidgetBuildLogAt;
    if (lastBuildLog == null || now.difference(lastBuildLog).inSeconds >= 5) {
      _lastMapWidgetBuildLogAt = now;
      debugPrint(
        '[MAP][WIDGET_BUILD] mapSupported=$_mapSupported hasMap=${_map != null}',
      );
    }
    if (kIsWindows) {
      return _mapPlaceholder(
        title: 'Map unavailable on Windows',
        subtitle: 'Run on Android to see the live map.',
      );
    }

    if (kIsWeb) {
      return _mapPlaceholder(
        title: 'Map unavailable on Web',
        subtitle: 'Run on Android to see the live map.',
      );
    }

    return _stableMapWidget;
  }

  Widget _mapPlaceholder({required String title, required String subtitle}) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          radius: 1.2,
          colors: [Color(0xFF141B2F), Color(0xFF070A10)],
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Container(
            margin: const EdgeInsets.all(18),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF141B2F),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(subtitle, style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopStatus(bool active) {
    if (!active) return const SizedBox.shrink();

    final eta = _fmtDur(_remainingSec());
    final km = _fmtRemainingKm();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFF141B2F).withOpacity(0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          const Icon(Icons.circle, size: 10, color: Color(0xFF4CD964)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Tracking actief • Ping: $_lastPing • ETA: $eta • KM: $km',
              style: const TextStyle(fontWeight: FontWeight.w800),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFED6A5A).withOpacity(0.28),
              foregroundColor: const Color(0xFFFFB4AA),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: _stopTrip,
            child: Text(kStopShortLabel),
          ),
        ],
      ),
    );
  }

  Widget _buildBookingsSheet(double screenH) {
    final padding = MediaQuery.of(context).padding.bottom;

    return Container(
      margin: const EdgeInsets.all(12),
      padding: EdgeInsets.only(
        left: 14,
        right: 14,
        top: 14,
        bottom: 14 + padding,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF141B2F).withOpacity(0.94),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white12),
        boxShadow: [
          BoxShadow(blurRadius: 18, spreadRadius: 2, color: Colors.black54),
          BoxShadow(blurRadius: 26, spreadRadius: 1, color: kFluxidiYellowSoft),
        ],
      ),
      child: _buildBookingsList(screenH),
    );
  }

  Widget _buildBookingsList(double screenH) {
    final visibleBookings = _visibleBookings;
    return Column(
      mainAxisSize: MainAxisSize.max,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                kAvailableBookingsTitle,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            OutlinedButton.icon(
              style: _ghostButtonStyle(),
              onPressed: _loadingBookings ? null : _refreshBookings,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(kRefreshShortLabel),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_loadingBookings)
          const Padding(
            padding: EdgeInsets.all(18),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_bookingsError != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Error: $_bookingsError',
              style: const TextStyle(color: Colors.redAccent),
            ),
          )
        else if (visibleBookings.isEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(kBookingsEmptyLabel),
          )
        else
          Expanded(
            child: ListView.separated(
              itemCount: visibleBookings.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _bookingCard(visibleBookings[i]),
            ),
          ),
      ],
    );
  }

  ({String label, String value}) _driverCardReferenceDisplay(BookingItem b) {
    final canonicalBookingId = _cleanBusinessReferenceText(b.bookingId) ?? '';
    final detailsMap = Map<String, dynamic>.from(b.details);
    if (canonicalBookingId.isNotEmpty) {
      detailsMap['booking_id'] = canonicalBookingId;
      detailsMap['bookingId'] = canonicalBookingId;
    }
    final maps = _referenceLookupMaps(<Map<String, dynamic>>[detailsMap]);
    final refs = _extractBusinessReferenceAliasesFromMaps(maps);
    final planning = refs.planning ?? '';
    final publicBooking =
        refs.publicBooking ?? refs.booking ?? refs.publicRef ?? '';

    String label;
    String value;
    if (planning.isNotEmpty) {
      label = _tr(
        nl: 'Planningnummer',
        en: 'Planning no.',
        fr: 'N° de planning',
        es: 'N.º de planificación',
      );
      value = planning;
    } else if (publicBooking.isNotEmpty) {
      label = _tr(
        nl: 'Boekingsnummer',
        en: 'Booking no.',
        fr: 'N° de réservation',
        es: 'N.º de reserva',
      );
      value = publicBooking;
    } else {
      label = _tr(
        nl: 'Interne boeking',
        en: 'Internal booking',
        fr: 'Réservation interne',
        es: 'Reserva interna',
      );
      value = canonicalBookingId.isEmpty ? b.shortId : canonicalBookingId;
    }
    debugPrint(
      '[RIDES][CARD_REF_SELECTED] booking=${_safeRefPreview(canonicalBookingId)} planning=$planning public=$publicBooking selected=$value',
    );
    return (label: label, value: value);
  }

  Widget _bookingCard(BookingItem b) {
    final dt = _formatPickup(b.pickupIso);
    final actionBusy = _bookingActionInFlight.contains(b.bookingId);
    final cardReference = _driverCardReferenceDisplay(b);

    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth < 380;
        final tight = c.maxWidth < 340;
        final actionHeight = narrow ? 44.0 : 42.0;
        final statusText = _rideStatusLabel(
          (_effectiveStatusFor(b) ?? 'PENDING'),
        );

        return Container(
          padding: EdgeInsets.all(tight ? 12 : 14),
          decoration: BoxDecoration(
            color: const Color(0xFF1A2240),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: kFluxidiYellow.withOpacity(0.18)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (narrow) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _pill(icon: Icons.schedule, text: dt),
                    _pill(
                      icon: Icons.timelapse,
                      text: statusText,
                      borderColor: const Color(0xFFB07A2A),
                      textColor: const Color(0xFFE7B46A),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: actionHeight,
                  child: FilledButton(
                    style: _startButtonStyle().copyWith(
                      padding: MaterialStateProperty.all(
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                      ),
                    ),
                    onPressed: () => _goToRide(b),
                    child: Text(
                      kRideGoToRideLabel,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        height: 1.05,
                      ),
                    ),
                  ),
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _pill(icon: Icons.schedule, text: dt),
                          _pill(
                            icon: Icons.timelapse,
                            text: statusText,
                            borderColor: const Color(0xFFB07A2A),
                            textColor: const Color(0xFFE7B46A),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: actionHeight,
                      child: FilledButton(
                        style: _startButtonStyle().copyWith(
                          padding: MaterialStateProperty.all(
                            const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 0,
                            ),
                          ),
                        ),
                        onPressed: () => _goToRide(b),
                        child: Text(
                          kRideGoToRideLabel,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            height: 1.05,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              _line(
                icon: Icons.radio_button_checked,
                title: kPickupLabel,
                value: b.from ?? '—',
                maxLines: narrow ? 2 : 3,
              ),
              const SizedBox(height: 6),
              _line(
                icon: Icons.place,
                title: kDropoffLabel,
                value: b.to ?? '—',
                maxLines: narrow ? 2 : 3,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _pill(text: (b.tier ?? 'premium').toUpperCase()),
                  _pill(text: '${b.pax ?? 0} pax'),
                  _pill(text: '${b.bags ?? 0} bags'),
                  _pill(
                    text: '${cardReference.label}: ${cardReference.value}',
                    textColor: Colors.white70,
                  ),
                  if (b.price != null)
                    _pill(text: _fmtMoney(b.price!, b.currency ?? 'EUR')),
                ],
              ),
              const SizedBox(height: 10),
              if (narrow) ...[
                SizedBox(
                  width: double.infinity,
                  height: actionHeight,
                  child: OutlinedButton.icon(
                    style: _ghostButtonStyle(),
                    onPressed: actionBusy
                        ? null
                        : () => _setBookingStatus(b, 'COMPLETED'),
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: Text(
                      kRideActionCompletedLabel,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: actionHeight,
                        child: OutlinedButton.icon(
                          style: _ghostButtonStyle(),
                          onPressed: actionBusy
                              ? null
                              : () => _setBookingStatus(b, 'CANCELLED'),
                          icon: const Icon(Icons.cancel_outlined, size: 18),
                          label: Text(
                            kRideActionCancelledLabel,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: actionHeight,
                      width: actionHeight + 2,
                      child: IconButton(
                        onPressed: actionBusy ? null : () => _confirmDelete(b),
                        icon: const Icon(Icons.delete_outline),
                        tooltip: kRideDeleteLabel,
                      ),
                    ),
                  ],
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: actionHeight,
                        child: OutlinedButton.icon(
                          style: _ghostButtonStyle(),
                          onPressed: actionBusy
                              ? null
                              : () => _setBookingStatus(b, 'COMPLETED'),
                          icon: const Icon(
                            Icons.check_circle_outline,
                            size: 18,
                          ),
                          label: Text(kRideActionCompletedLabel),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: actionHeight,
                        child: OutlinedButton.icon(
                          style: _ghostButtonStyle(),
                          onPressed: actionBusy
                              ? null
                              : () => _setBookingStatus(b, 'CANCELLED'),
                          icon: const Icon(Icons.cancel_outlined, size: 18),
                          label: Text(kRideActionCancelledLabel),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: actionHeight,
                      width: actionHeight + 2,
                      child: IconButton(
                        onPressed: actionBusy ? null : () => _confirmDelete(b),
                        icon: const Icon(Icons.delete_outline),
                        tooltip: kRideDeleteLabel,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildCockpitWidget() {
    // ✅ Minimal cockpit (driving only):
    // - Big ETA + KM remaining (countdown starts when we move)
    // - Bottom controls: NAV | START/STOP | WACHT/GA
    final eta = _etaText.isNotEmpty ? _etaText : '—';
    final km = _kmRemainingText.isNotEmpty ? _kmRemainingText : '—';

    final bool tripStarted = _activeTripId != null;
    final bool waiting = _isWaiting;

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              decoration: BoxDecoration(
                color: const Color(0xFF0B1733).withOpacity(0.78),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: kGlow.withOpacity(tripStarted ? 0.50 : 0.22),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: kGlow.withOpacity(tripStarted ? 0.18 : 0.10),
                    blurRadius: tripStarted ? 16 : 10,
                    spreadRadius: 0.5,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // === Big numbers ===
                  Row(
                    children: [
                      Expanded(
                        child: _bigMetric(label: 'ETA', value: eta),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _bigMetric(label: 'KM', value: km, suffix: 'km'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // === Controls ===
                  Row(
                    children: [
                      Expanded(
                        child: _cockpitButton(
                          label: 'NAV',
                          icon: Icons.navigation,
                          onTap: _openNavigation,
                          enabled: _routeCoords.isNotEmpty,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _cockpitButton(
                          label: tripStarted ? 'STOP' : 'START',
                          icon: tripStarted
                              ? Icons.stop_circle_outlined
                              : Icons.play_circle_outline,
                          onTap: () {
                            final b = _activeBooking;
                            if (!tripStarted) {
                              if (b == null) {
                                _toast('Kies eerst een rit in Ritten.');
                                return;
                              }
                              _startTrip(b);
                            } else {
                              _stopTrip();
                            }
                          },
                          emphasis: true,
                          enabled: (tripStarted || _activeBooking != null),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _cockpitButton(
                          label: waiting ? 'GA' : 'WACHT',
                          icon: waiting ? Icons.play_arrow : Icons.pause,
                          onTap: () {
                            if (!tripStarted) {
                              _toast('Start eerst de rit.');
                              return;
                            }
                            if (waiting) {
                              _exitWaitMode();
                            } else {
                              _enterWaitMode();
                            }
                          },
                          enabled: tripStarted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bigMetric({
    required String label,
    required String value,
    String? suffix,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white.withOpacity(0.06),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.70),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (suffix != null) ...[
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    suffix,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.70),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _cockpitButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    bool enabled = true,
    bool emphasis = false,
  }) {
    final baseOpacity = enabled ? 1.0 : 0.45;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: enabled ? onTap : null,
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.white.withOpacity(emphasis ? 0.10 : 0.06),
          border: Border.all(
            color: kGlow.withOpacity(
              emphasis ? 0.55 * baseOpacity : 0.28 * baseOpacity,
            ),
            width: 1.1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: Colors.white.withOpacity(baseOpacity)),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
                color: Colors.white.withOpacity(baseOpacity),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dialGauge({
    required String label,
    required String value,
    required IconData icon,
    required bool highlight,
  }) {
    return AnimatedBuilder(
      animation: _activePulse,
      builder: (context, _) {
        final t = highlight ? (0.55 + 0.45 * _activePulse.value) : 0.0;

        return Container(
          height: 86,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: const Color(0xFF0B1733).withOpacity(0.55),
            border: Border.all(
              color: const Color(0xFFFFD36A).withOpacity(0.20 + 0.18 * t),
              width: 1.0,
            ),
            boxShadow: [
              if (highlight)
                BoxShadow(
                  color: const Color(0x66F5C400).withOpacity(0.10 * t),
                  blurRadius: 22 * t,
                  spreadRadius: 1 * t,
                ),
            ],
          ),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Round dial
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withOpacity(0.18),
                    border: Border.all(
                      color: const Color(
                        0xFFFFD36A,
                      ).withOpacity(0.22 + 0.22 * t),
                      width: 1.0,
                    ),
                    boxShadow: [
                      if (highlight)
                        BoxShadow(
                          color: const Color(0x66F5C400).withOpacity(0.18 * t),
                          blurRadius: 18 * t,
                          spreadRadius: 1 * t,
                        ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        icon,
                        size: 16,
                        color: const Color(0xFFFFD36A).withOpacity(0.92),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // Label (right side)
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.62),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _dialAction({
    required String label,
    required IconData icon,
    required bool filled,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedBuilder(
        animation: _activePulse,
        builder: (context, _) {
          final t = (0.65 + 0.35 * _activePulse.value);
          return Container(
            height: 86,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: filled
                  ? const Color(0xFF3B2230)
                  : const Color(0xFF0B1733).withOpacity(0.45),
              border: Border.all(
                color: filled
                    ? const Color(0xFFFFA7C0).withOpacity(0.50 + 0.25 * t)
                    : const Color(0xFFFFD36A).withOpacity(0.26 + 0.14 * t),
                width: 1.2,
              ),
              boxShadow: filled
                  ? [
                      BoxShadow(
                        color: const Color(0x66FFA7C0).withOpacity(0.16 * t),
                        blurRadius: 18 * t,
                        spreadRadius: 1 * t,
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: const Color(0x66F5C400).withOpacity(0.10 * t),
                        blurRadius: 18 * t,
                        spreadRadius: 1 * t,
                      ),
                    ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: filled
                      ? const Color(0xFFFFA7C0)
                      : const Color(0xFFFFD36A),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _cockpitGauge({
    required String label,
    required String value,
    required IconData icon,
    required bool highlight,
  }) {
    return AnimatedBuilder(
      animation: _activePulse,
      builder: (context, child) {
        final t = highlight ? (0.55 + 0.45 * _activePulse.value) : 0.0;
        return Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: const Color(0xFF0B1733).withOpacity(0.65),
            border: Border.all(
              color: const Color(0xFFFFD36A).withOpacity(0.22 + 0.18 * t),
              width: 1.0,
            ),
            boxShadow: [
              if (highlight)
                BoxShadow(
                  color: const Color(0xFFFFD36A).withOpacity(0.10 * t),
                  blurRadius: 18 * t,
                  spreadRadius: 1 * t,
                ),
            ],
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: const Color(0xFFFFD36A).withOpacity(0.9),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.55),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _cockpitAction({
    required String label,
    required IconData icon,
    required bool filled,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: filled
              ? const Color(0xFF3B2230)
              : const Color(0xFF0B1733).withOpacity(0.55),
          border: Border.all(
            color: filled
                ? const Color(0xFFFFA7C0).withOpacity(0.55)
                : const Color(0xFFFFD36A).withOpacity(0.28),
            width: 1.1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: filled ? const Color(0xFFFFA7C0) : const Color(0xFFFFD36A),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.95),
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tinyStat(String k, String v) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$k: ',
            style: TextStyle(
              color: Colors.white.withOpacity(0.70),
              fontSize: 12,
            ),
          ),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _buildActiveDetailsSheet() {
    final b = _activeBooking;

    return DraggableScrollableSheet(
      // ✅ smaller collapsed size so it doesn't hide the values
      initialChildSize: 0.10,
      minChildSize: 0.10,
      // ✅ lower max so it doesn't dominate
      maxChildSize: 0.56,
      builder: (context, controller) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF141B2F).withOpacity(0.94),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            border: Border.all(color: Colors.white12),
            boxShadow: const [
              BoxShadow(blurRadius: 18, spreadRadius: 2, color: Colors.black54),
            ],
          ),
          child: ListView(
            controller: controller,
            padding: EdgeInsets.only(
              left: 14,
              right: 14,
              top: 10,
              bottom: 18 + MediaQuery.of(context).padding.bottom + 50,
            ),
            children: [
              Center(
                child: Container(
                  width: 48,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                kActiveRideTitle,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              if (b != null) ...[
                _line(
                  icon: Icons.confirmation_number,
                  title: 'Trip ID',
                  value: _activeTripId ?? '—',
                  maxLines: 1,
                ),
                const SizedBox(height: 8),
                _line(
                  icon: Icons.radio_button_checked,
                  title: kPickupLabel,
                  value: b.from ?? '—',
                  maxLines: 3,
                ),
                const SizedBox(height: 8),
                _line(
                  icon: Icons.place,
                  title: kDropoffLabel,
                  value: b.to ?? '—',
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _pill(text: (b.tier ?? 'premium').toUpperCase()),
                    _pill(text: '${b.pax ?? 0} pax'),
                    _pill(text: '${b.bags ?? 0} bags'),
                    _pill(
                      text: 'Pings: $_pingCount',
                      textColor: Colors.white70,
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFED6A5A).withOpacity(0.30),
                    foregroundColor: const Color(0xFFFFB4AA),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  onPressed: _stopTrip,
                  child: const Text(
                    'Stop rit',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _pill({
    IconData? icon,
    required String text,
    Color? borderColor,
    Color? textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor ?? Colors.white10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: (textColor ?? Colors.white70)),
            const SizedBox(width: 6),
          ],
          Text(text, style: TextStyle(color: textColor ?? Colors.white)),
        ],
      ),
    );
  }

  Widget _line({
    required IconData icon,
    required String title,
    required String value,
    int maxLines = 2,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.white70),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.72),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
                // ✅ FIX: w650 doesn't exist -> w600
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatPickup(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      String two(int v) => v.toString().padLeft(2, '0');
      return '${two(dt.day)}-${two(dt.month)} ${two(dt.hour)}:${two(dt.minute)}';
    } catch (_) {
      return iso;
    }
  }

  bool _canAccessDriverOpsScreens() {
    final role = appRoleNotifier.value;
    return role == AppRole.driver ||
        role == AppRole.dispatcher ||
        role == AppRole.companyAdmin;
  }

  bool _canAccessCustomerBookingScreens() {
    final role = appRoleNotifier.value;
    return role == AppRole.customer ||
        role == AppRole.driver ||
        role == AppRole.companyAdmin;
  }

  bool _canAccessAdminManagementScreens() {
    return appRoleNotifier.value == AppRole.companyAdmin;
  }

  void _denyRoleAccess() {
    _toast('Geen toegang voor jouw rol.');
  }

  void _openBookingsHub() async {
    if (!_canAccessDriverOpsScreens()) {
      Navigator.pop(context);
      _denyRoleAccess();
      return;
    }
    // Close drawer first for a clean transition.
    Navigator.pop(context);
    if (mounted) {
      setState(() => _bookingsHubVisible = true);
    } else {
      _bookingsHubVisible = true;
    }
    _startBookingPolling(reason: 'bookings_hub_open');
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => _BookingsHubPage(
          title: kBookingsTitle,
          buildList: (h) => _buildBookingsList(h),
          onRefresh: () =>
              _refreshBookings(force: true, trigger: 'list_manual'),
          repaintListenable: _bookingsUiVersion,
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _bookingsHubVisible = false);
    _startBookingPolling(reason: 'bookings_hub_closed');
  }

  void _openLiveRide() async {
    if (!_canAccessDriverOpsScreens()) {
      Navigator.pop(context);
      _denyRoleAccess();
      return;
    }
    // Close drawer first for a clean transition.
    Navigator.pop(context);

    if (!_liveRideActive) {
      _toast('Geen actieve rit. Start een rit vanuit Ritten.');
      return;
    }

    // Bring driver focus back to the cockpit/map.
    try {
      setState(() {
        _cameraMode = _CameraMode.follow;
        _followCar = true;
        _hasSwitchedToFollow = true;
        _allowOverviewCamera = false;
      });
      await _applyMapStyleForMode();
      await _forceFollowCameraNow(caller: 'open_live_ride');
    } catch (_) {
      // Never crash the UI from a camera move.
    }
  }

  void _openTripHistory() {
    if (!_canAccessDriverOpsScreens()) {
      Navigator.pop(context);
      _denyRoleAccess();
      return;
    }
    Navigator.pop(context);
    final bookingDetailsById = <String, Map<String, dynamic>>{};
    for (final booking in _bookings) {
      final bookingId = booking.bookingId.trim();
      if (bookingId.isEmpty) continue;
      final details = Map<String, dynamic>.from(booking.details);
      details['booking_id'] = bookingId;
      details['bookingId'] = bookingId;
      final nestedBooking = details['booking'] is Map
          ? Map<String, dynamic>.from(details['booking'] as Map)
          : <String, dynamic>{};
      nestedBooking['booking_id'] = bookingId;
      nestedBooking['bookingId'] = bookingId;
      details['booking'] = nestedBooking;
      bookingDetailsById[bookingId] = details;
    }
    final activeBookingId = _activeBooking?.bookingId.trim() ?? '';
    if (activeBookingId.isNotEmpty) {
      final activeDetails = Map<String, dynamic>.from(_activeBooking!.details);
      activeDetails['booking_id'] = activeBookingId;
      activeDetails['bookingId'] = activeBookingId;
      final nestedBooking = activeDetails['booking'] is Map
          ? Map<String, dynamic>.from(activeDetails['booking'] as Map)
          : <String, dynamic>{};
      nestedBooking['booking_id'] = activeBookingId;
      nestedBooking['bookingId'] = activeBookingId;
      activeDetails['booking'] = nestedBooking;
      bookingDetailsById[activeBookingId] = activeDetails;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => _TripHistoryPage(
          workerBaseUrl: kWorkerBaseUrl,
          tenantId: kOutboundTenantId,
          companyId: resolvedCompanyId.trim().isNotEmpty
              ? resolvedCompanyId.trim()
              : kOutboundTenantId,
          driverId: kDriverId,
          headers: _headers(admin: true),
          bookingDetailsById: bookingDetailsById,
        ),
      ),
    );
  }

  void _openCalculator() {
    if (!_canAccessCustomerBookingScreens()) {
      Navigator.pop(context);
      _denyRoleAccess();
      return;
    }
    // Close drawer first for a clean transition.
    Navigator.pop(context);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => CalculatorPage(
          bookingBaseUrl: kBookingBaseUrl,
          mapboxToken: kMapboxToken,
        ),
      ),
    );
  }

  void _openBusinessSettings() {
    if (!_canAccessAdminManagementScreens()) {
      Navigator.pop(context);
      _denyRoleAccess();
      return;
    }
    Navigator.pop(context);
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (ctx) => const BusinessSettingsPage()));
  }

  void _openVehicles() {
    if (!_canAccessAdminManagementScreens()) {
      Navigator.pop(context);
      _denyRoleAccess();
      return;
    }
    Navigator.pop(context);
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (ctx) => const VehicleManagementPage()));
  }

  Drawer _buildDrawer() {
    final role = appRoleNotifier.value;
    final isCustomer = role == AppRole.customer;
    final isDriver = role == AppRole.driver;
    final isCompanyAdmin = role == AppRole.companyAdmin;
    final isDispatcher = role == AppRole.dispatcher;
    final canSeeDriverOps = isDriver || isDispatcher || isCompanyAdmin;
    final canSeeAdminManagement = isCompanyAdmin;
    final canSeeCustomerBooking = isCustomer || isDriver || isCompanyAdmin;

    return Drawer(
      backgroundColor: const Color(0xFF141B2F),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            const Text(
              'Fluxidi Driver',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Text(
              kDrawerLanguageLabel,
              style: TextStyle(
                color: Colors.white.withOpacity(0.80),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: currentLanguageCode,
              items: const [
                DropdownMenuItem(value: 'nl', child: Text('Nederlands')),
                DropdownMenuItem(value: 'en', child: Text('English')),
                DropdownMenuItem(value: 'fr', child: Text('Francais')),
                DropdownMenuItem(value: 'es', child: Text('Espanol')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setAppLanguageByCode(v);
                setState(() {});
              },
              dropdownColor: const Color(0xFF111111),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: const Color(0xFF0B0B0B),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0x22FFFFFF)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0x22FFFFFF)),
                ),
              ),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 12),
            Text(
              _tr(
                nl: 'Kaartmodus',
                en: 'Map mode',
                fr: 'Mode de carte',
                es: 'Modo de mapa',
              ),
              style: TextStyle(
                color: Colors.white.withOpacity(0.80),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<MapThemeMode>(
              value: _effectiveMapThemeFor(_cameraMode),
              items: [
                DropdownMenuItem(
                  value: MapThemeMode.light,
                  child: Text(
                    _tr(nl: 'Licht', en: 'Light', fr: 'Clair', es: 'Claro'),
                  ),
                ),
                DropdownMenuItem(
                  value: MapThemeMode.dark,
                  child: Text(
                    _tr(nl: 'Donker', en: 'Dark', fr: 'Sombre', es: 'Oscuro'),
                  ),
                ),
              ],
              onChanged: (v) {
                if (v == null) return;
                _setMapTheme(v);
              },
              dropdownColor: const Color(0xFF111111),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: const Color(0xFF0B0B0B),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0x22FFFFFF)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0x22FFFFFF)),
                ),
              ),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.white12),
            const SizedBox(height: 8),
            ValueListenableBuilder<ActiveDriverSession?>(
              valueListenable: activeDriverSessionNotifier,
              builder: (context, session, _) {
                if (!(isDriver && session != null)) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.folder_copy_outlined),
                        title: Text(
                          _tr(
                            nl: 'Mijn documenten',
                            en: 'My documents',
                            fr: 'Mes documents',
                            es: 'Mis documentos',
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const DriverMyDocumentsPage(),
                            ),
                          );
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.swap_horiz_rounded),
                        title: Text(
                          _tr(
                            nl: 'Andere chauffeur',
                            en: 'Switch driver',
                            fr: 'Changer de chauffeur',
                            es: 'Cambiar conductor',
                          ),
                        ),
                        subtitle: Text(
                          _tr(
                            nl: 'Afmelden en opnieuw inloggen met een ander ID.',
                            en: 'Sign out and log in with a different ID.',
                            fr: 'Se déconnecter et se reconnecter avec un autre ID.',
                            es: 'Cerrar sesión e iniciar con otro ID.',
                          ),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.65),
                            fontSize: 12,
                          ),
                        ),
                        onTap: () async {
                          Navigator.pop(context);
                          await DriverSessionStore.instance.clear();
                          if (!context.mounted) return;
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(
                              builder: (_) => const ChauffeurLoginPage(),
                            ),
                            (route) => false,
                          );
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
            // === Menu: Bookings hub ===
            if (canSeeDriverOps)
              ListTile(
                leading: const Icon(Icons.list_alt),
                title: Text(kBookingsTitle),
                subtitle: Text(
                  kBookingsMenuSubtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.65),
                    fontSize: 12,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openBookingsHub,
              ),

            // === Menu: Live rit ===
            if (canSeeDriverOps)
              ListTile(
                leading: const Icon(Icons.play_arrow),
                title: Text(kLiveRideTitle),
                subtitle: Text(
                  kLiveRideMenuSubtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.65),
                    fontSize: 12,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openLiveRide,
              ),

            if (canSeeDriverOps)
              ListTile(
                leading: const Icon(Icons.local_taxi_outlined),
                title: Text(
                  _tr(
                    nl: 'Straatrit',
                    en: 'Direct ride',
                    fr: 'Course directe',
                    es: 'Viaje directo',
                  ),
                ),
                subtitle: Text(
                  _tr(
                    nl: 'Start een rit zonder voorafgaande boeking',
                    en: 'Start a ride without a planned booking',
                    fr: 'Demarrer une course sans reservation',
                    es: 'Iniciar un viaje sin reserva',
                  ),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.65),
                    fontSize: 12,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openDirectRideEntry,
              ),

            if (canSeeDriverOps)
              ListTile(
                leading: const Icon(Icons.history),
                title: Text(
                  _tr(
                    nl: 'Ritgeschiedenis',
                    en: 'Ride history',
                    fr: 'Historique des courses',
                    es: 'Historial de viajes',
                  ),
                ),
                subtitle: Text(
                  _tr(
                    nl: 'Bekijk afgeronde straatritten',
                    en: 'View completed direct rides',
                    fr: 'Voir les courses directes terminees',
                    es: 'Ver viajes directos completados',
                  ),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.65),
                    fontSize: 12,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openTripHistory,
              ),

            // === Menu: Calculator ===
            if (canSeeCustomerBooking)
              ListTile(
                leading: const Icon(Icons.calculate_outlined),
                title: Text(
                  _tr(
                    nl: 'Ritprijs berekenen',
                    en: 'Fare calculator',
                    fr: 'Calculateur de tarif',
                    es: 'Calculadora de tarifa',
                  ),
                ),
                subtitle: Text(
                  appConfig.currentLanguage == AppLanguage.nl
                      ? 'Bereken en boek ritten'
                      : kCalculatorMenuSubtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.65),
                    fontSize: 12,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openCalculator,
              ),
            if (canSeeAdminManagement)
              ListTile(
                leading: const Icon(Icons.business_center_outlined),
                title: Text(kDrawerBusinessSettingsLabel),
                subtitle: Text(
                  kDrawerBusinessSettingsSubtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.65),
                    fontSize: 12,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openBusinessSettings,
              ),
            if (canSeeAdminManagement)
              ListTile(
                leading: const Icon(Icons.directions_car_filled_outlined),
                title: Text(kDrawerVehiclesLabel),
                subtitle: Text(
                  kDrawerVehiclesSubtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.65),
                    fontSize: 12,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openVehicles,
              ),

            // === Menu: Actieve rit (alleen zichtbaar wanneer een rit actief is) ===
            if (canSeeDriverOps && _liveRideActive)
              ListTile(
                leading: const Icon(Icons.directions_car),
                title: Text(kActiveRideTitle),
                subtitle: Text(
                  kActiveRideMenuSubtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.65),
                    fontSize: 12,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openLiveRide,
              ),

            const SizedBox(height: 8),
            const Divider(color: Colors.white12),
            const SizedBox(height: 8),
            if (canSeeDriverOps)
              ListTile(
                leading: const Icon(Icons.refresh),
                title: Text(kRefreshBookingsLabel),
                onTap: () {
                  Navigator.pop(context);
                  _refreshBookings(force: true, trigger: 'drawer_manual');
                },
              ),
            if (canSeeDriverOps)
              ListTile(
                leading: const Icon(Icons.my_location),
                title: Text(kCenterOnMeLabel),
                onTap: () async {
                  Navigator.pop(context);
                  await _centerOnMe();
                },
              ),
            if (canSeeDriverOps) const SizedBox(height: 8),
            if (canSeeDriverOps) const FluxidiBackToStartButton(),
          ],
        ),
      ),
    );
  }
}

/// Small icon button with Fluxidi yellow glow.
///
/// Used in the brand bar (menu icon, etc.). Keeps hit-area large for in-car use.

/// Full-screen Bookings Hub opened from the drawer.
/// Keeps the map screen clean: operations live here.
class _TripHistoryPage extends StatefulWidget {
  final String workerBaseUrl;
  final String tenantId;
  final String companyId;
  final String driverId;
  final Map<String, String> headers;
  final Map<String, Map<String, dynamic>> bookingDetailsById;

  const _TripHistoryPage({
    required this.workerBaseUrl,
    required this.tenantId,
    required this.companyId,
    required this.driverId,
    required this.headers,
    this.bookingDetailsById = const <String, Map<String, dynamic>>{},
  });

  @override
  State<_TripHistoryPage> createState() => _TripHistoryPageState();
}

class _TripHistoryPageState extends State<_TripHistoryPage> {
  late Future<List<_TripHistoryItem>> _future;

  _TripHistoryItem _enrichTripHistoryItemWithBusinessRefs(
    _TripHistoryItem item, {
    required String sourceTag,
  }) {
    final bookingId = item.bookingId?.trim() ?? '';
    if (bookingId.isEmpty) return item;
    final authoritative = widget.bookingDetailsById[bookingId];
    if (authoritative == null || authoritative.isEmpty) return item;

    final mergedRawSource = _mergeBusinessReferencesIntoSource(
      source: Map<String, dynamic>.from(item.rawSource),
      authoritative: authoritative,
      canonicalBookingId: item.bookingId,
      tripId: item.tripId,
      sourceTag: sourceTag,
    );
    final mergedBookingDetails = _mergeBusinessReferencesIntoSource(
      source: Map<String, dynamic>.from(item.bookingDetails),
      authoritative: authoritative,
      canonicalBookingId: item.bookingId,
      tripId: item.tripId,
      sourceTag: '${sourceTag}_booking_details',
    );
    if (mergedBookingDetails.isNotEmpty) {
      mergedRawSource['booking_details'] = mergedBookingDetails;
      mergedRawSource['bookingDetails'] = mergedBookingDetails;
    }

    return item.copyWith(
      rawSource: mergedRawSource,
      bookingDetails: mergedBookingDetails,
    );
  }

  ({bool hasPlanning, bool hasPublicBooking, bool hasRealReceipt})
  _referencePresenceForItem(_TripHistoryItem item) {
    final maps = _referenceLookupMaps(<Map<String, dynamic>>[
      item.rawSource,
      item.bookingDetails,
    ]);
    final refs = _extractBusinessReferenceAliasesFromMaps(maps);
    final canonicalBookingId =
        _cleanBusinessReferenceText(item.bookingId) ??
        _pickReferenceAliasFromMaps(maps, const <List<String>>[
          <String>['booking_id'],
          <String>['bookingId'],
          <String>['id'],
          <String>['booking', 'booking_id'],
          <String>['booking', 'bookingId'],
          <String>['record', 'booking_id'],
          <String>['record', 'bookingId'],
        ]);
    final effectiveTripId =
        _cleanBusinessReferenceText(item.tripId) ??
        _pickReferenceAliasFromMaps(maps, const <List<String>>[
          <String>['trip_id'],
          <String>['tripId'],
        ]);
    final hasRealReceipt =
        refs.receipt != null &&
        _isRealReceiptReference(
          candidate: refs.receipt!,
          canonicalBookingId: canonicalBookingId,
          tripId: effectiveTripId,
          planningReference: refs.planning,
          publicBookingReference: refs.publicBooking,
          legacyTripReceiptNumber: effectiveTripId == null
              ? null
              : _legacyTripReceiptNumber(effectiveTripId),
        );
    return (
      hasPlanning: refs.planning != null,
      hasPublicBooking:
          refs.publicBooking != null ||
          refs.booking != null ||
          refs.publicRef != null,
      hasRealReceipt: hasRealReceipt,
    );
  }

  String _canonicalBookingIdFromItem(_TripHistoryItem item) {
    final direct = _cleanBusinessReferenceText(item.bookingId) ?? '';
    if (direct.isNotEmpty) return direct;
    final maps = _referenceLookupMaps(<Map<String, dynamic>>[
      item.rawSource,
      item.bookingDetails,
    ]);
    return _pickReferenceAliasFromMaps(maps, const <List<String>>[
          <String>['booking_id'],
          <String>['bookingId'],
          <String>['id'],
          <String>['booking', 'booking_id'],
          <String>['booking', 'bookingId'],
          <String>['record', 'booking_id'],
          <String>['record', 'bookingId'],
          <String>['record', 'booking', 'booking_id'],
          <String>['record', 'booking', 'bookingId'],
          <String>['payload', 'booking_id'],
          <String>['payload', 'bookingId'],
          <String>['payload', 'booking', 'booking_id'],
          <String>['payload', 'booking', 'bookingId'],
        ]) ??
        '';
  }

  Future<_TripHistoryItem> _enrichTripHistoryItemForReceipt(
    _TripHistoryItem item,
  ) async {
    var enriched = _enrichTripHistoryItemWithBusinessRefs(
      item,
      sourceTag: 'trip_history_open_receipt_cache',
    );
    final before = _referencePresenceForItem(enriched);
    if (before.hasPlanning ||
        before.hasPublicBooking ||
        before.hasRealReceipt) {
      debugPrint(
        '[DRIVER_HISTORY][REF_FETCH] booking=${_safeRefPreview(_canonicalBookingIdFromItem(enriched))} foundPlanning=${before.hasPlanning} foundPublic=${before.hasPublicBooking} foundReceipt=${before.hasRealReceipt} source=already_present',
      );
      return enriched;
    }

    final bookingId = _canonicalBookingIdFromItem(enriched);
    if (bookingId.isEmpty) {
      debugPrint(
        '[DRIVER_HISTORY][REF_FETCH] booking= foundPlanning=false foundPublic=false foundReceipt=false source=skipped_no_booking',
      );
      return enriched;
    }

    try {
      final uri = _withActiveBookingScope(
        kBookingBaseUrl,
        '/bookings/${Uri.encodeComponent(bookingId)}',
      );
      final res = await http
          .get(uri, headers: widget.headers)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        debugPrint(
          '[DRIVER_HISTORY][REF_FETCH] booking=${_safeRefPreview(bookingId)} foundPlanning=false foundPublic=false foundReceipt=false source=fetch_failed',
        );
        return enriched;
      }
      final decodedRaw = jsonDecode(utf8.decode(res.bodyBytes));
      if (decodedRaw is! Map || decodedRaw['ok'] != true) {
        debugPrint(
          '[DRIVER_HISTORY][REF_FETCH] booking=${_safeRefPreview(bookingId)} foundPlanning=false foundPublic=false foundReceipt=false source=fetch_failed',
        );
        return enriched;
      }
      final decoded = Map<String, dynamic>.from(decodedRaw);
      final record = decoded['record'];
      final booking = record is Map ? record['booking'] : null;
      final authoritative = <String, dynamic>{
        ...decoded,
        if (record is Map) 'record': Map<String, dynamic>.from(record),
        if (booking is Map) 'booking': Map<String, dynamic>.from(booking),
        'booking_id': bookingId,
        'bookingId': bookingId,
      };
      final authoritativePresence = _extractBusinessReferenceAliasesFromMaps(
        _referenceLookupMaps(<Map<String, dynamic>>[authoritative]),
      );
      final mergedRawSource = _mergeBusinessReferencesIntoSource(
        source: Map<String, dynamic>.from(enriched.rawSource),
        authoritative: authoritative,
        canonicalBookingId: bookingId,
        tripId: enriched.tripId,
        sourceTag: 'trip_history_open_receipt_booking_detail_fetch',
      );
      final mergedBookingDetails = _mergeBusinessReferencesIntoSource(
        source: Map<String, dynamic>.from(enriched.bookingDetails),
        authoritative: authoritative,
        canonicalBookingId: bookingId,
        tripId: enriched.tripId,
        sourceTag: 'trip_history_open_receipt_booking_detail_fetch_details',
      );
      if (mergedBookingDetails.isNotEmpty) {
        mergedRawSource['booking_details'] = mergedBookingDetails;
        mergedRawSource['bookingDetails'] = mergedBookingDetails;
      }
      enriched = enriched.copyWith(
        rawSource: mergedRawSource,
        bookingDetails: mergedBookingDetails,
      );
      final after = _referencePresenceForItem(enriched);
      debugPrint(
        '[DRIVER_HISTORY][REF_FETCH] booking=${_safeRefPreview(bookingId)} foundPlanning=${authoritativePresence.planning != null || after.hasPlanning} foundPublic=${authoritativePresence.publicBooking != null || authoritativePresence.booking != null || authoritativePresence.publicRef != null || after.hasPublicBooking} foundReceipt=${authoritativePresence.receipt != null || after.hasRealReceipt} source=booking_detail_fetch',
      );
      return enriched;
    } catch (_) {
      debugPrint(
        '[DRIVER_HISTORY][REF_FETCH] booking=${_safeRefPreview(bookingId)} foundPlanning=false foundPublic=false foundReceipt=false source=fetch_failed',
      );
      return enriched;
    }
  }

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<_TripHistoryItem>> _fetch() async {
    DateTime? parseIso(String? iso) {
      final text = iso?.trim();
      if (text == null || text.isEmpty) return null;
      return DateTime.tryParse(text);
    }

    void sortNewestFirst(List<_TripHistoryItem> items) {
      items.sort((a, b) {
        final aStopped = parseIso(a.stoppedAt);
        final bStopped = parseIso(b.stoppedAt);
        if (aStopped != null && bStopped != null) {
          final c = bStopped.compareTo(aStopped);
          if (c != 0) return c;
        } else if (aStopped == null && bStopped != null) {
          return 1;
        } else if (aStopped != null && bStopped == null) {
          return -1;
        }
        final aStarted = parseIso(a.startedAt);
        final bStarted = parseIso(b.startedAt);
        if (aStarted != null && bStarted != null) {
          final c = bStarted.compareTo(aStarted);
          if (c != 0) return c;
        } else if (aStarted == null && bStarted != null) {
          return 1;
        } else if (aStarted != null && bStarted == null) {
          return -1;
        }
        return b.tripId.compareTo(a.tripId);
      });
    }

    Future<List<_TripHistoryItem>> readLocalItems() async {
      final localRecords = await _LocalDirectTripHistoryStore.readFor(
        tenantId: widget.tenantId,
        driverId: widget.driverId,
        limit: 120,
      );
      return localRecords
          .map(_TripHistoryItem.fromJson)
          .where((e) => e.tripId.trim().isNotEmpty)
          .toList(growable: false);
    }

    late final List<_TripHistoryItem> backendItems;
    try {
      final uri = Uri.parse(
        '${widget.workerBaseUrl}$kTripsHistoryPath'
        '?tenant_id=${Uri.encodeQueryComponent(widget.tenantId)}'
        '&company_id=${Uri.encodeQueryComponent(widget.companyId)}'
        '&tenantId=${Uri.encodeQueryComponent(widget.tenantId)}'
        '&companyId=${Uri.encodeQueryComponent(widget.companyId)}'
        '&driver_id=${Uri.encodeQueryComponent(widget.driverId)}'
        '&limit=100',
      );
      final res = await http
          .get(uri, headers: widget.headers)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}: ${res.body}');
      }
      final decoded = jsonDecode(res.body);
      if (decoded is! Map || decoded['ok'] != true) {
        throw Exception('Ongeldig antwoord van Worker');
      }
      final trips = decoded['trips'];
      backendItems = trips is! List
          ? <_TripHistoryItem>[]
          : trips
                .whereType<Map>()
                .map(
                  (e) =>
                      _TripHistoryItem.fromJson(Map<String, dynamic>.from(e)),
                )
                .where((e) => e.tripId.trim().isNotEmpty)
                .toList(growable: false);
    } catch (_) {
      final localItems = await readLocalItems();
      if (localItems.isEmpty) rethrow;
      sortNewestFirst(localItems);
      return localItems;
    }

    final localItems = await readLocalItems();
    final mergedByTripId = <String, _TripHistoryItem>{};
    for (final item in backendItems) {
      mergedByTripId[item.tripId.trim()] = item;
    }
    for (final item in localItems) {
      mergedByTripId.putIfAbsent(item.tripId.trim(), () => item);
    }
    final merged = mergedByTripId.values
        .map(
          (item) => _enrichTripHistoryItemWithBusinessRefs(
            item,
            sourceTag: 'trip_history_fetch_merge',
          ),
        )
        .toList(growable: false);
    sortNewestFirst(merged);
    return merged;
  }

  void _refresh() {
    setState(() {
      _future = _fetch();
    });
  }

  String _formatDate(String? iso) {
    if (iso == null || iso.trim().isEmpty) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      String two(int v) => v.toString().padLeft(2, '0');
      return '${two(dt.day)}-${two(dt.month)}-${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
    } catch (_) {
      return iso;
    }
  }

  String _formatWait(int seconds) {
    if (seconds <= 0) return '0 min';
    final min = seconds ~/ 60;
    final sec = seconds % 60;
    if (min <= 0) return '${sec}s';
    if (sec == 0) return '$min min';
    return '$min min ${sec}s';
  }

  Future<void> _openReceipt(_TripHistoryItem item) async {
    final enrichedItem = await _enrichTripHistoryItemForReceipt(item);
    if (!mounted) return;
    if (!enrichedItem.isCompletedForReceipt) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_receiptText('receiptUnavailable'))),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _RideReceiptPage(item: enrichedItem)),
    );
  }

  Future<void> _archiveTrip(_TripHistoryItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_receiptText('archiveTripTitle')),
        content: Text(_receiptText('archiveTripBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(_receiptText('archiveTripCancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(_receiptText('archiveTripConfirm')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final scopeQuery = <String, String>{
        'tenant_id': widget.tenantId,
        'company_id': widget.companyId,
        'tenantId': widget.tenantId,
        'companyId': widget.companyId,
      };
      final res = await http
          .post(
            Uri.parse(
              '${widget.workerBaseUrl}$kTripsArchivePath',
            ).replace(queryParameters: scopeQuery),
            headers: widget.headers,
            body: jsonEncode({
              'tenant_id': widget.tenantId,
              'company_id': widget.companyId,
              'tenantId': widget.tenantId,
              'companyId': widget.companyId,
              'driver_id': widget.driverId,
              'trip_id': item.tripId,
              'archived': true,
            }),
          )
          .timeout(const Duration(seconds: 10));
      final decoded = jsonDecode(res.body);
      if (res.statusCode != 200 || decoded is! Map || decoded['ok'] != true) {
        throw Exception('archive_failed');
      }
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_receiptText('archiveTripSuccess'))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_receiptText('archiveTripFailed'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) => Scaffold(
        backgroundColor: const Color(0xFF0B1020),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0B1020),
          elevation: 0,
          title: Text(_receiptText('tripHistoryTitle')),
          actions: [
            IconButton(
              tooltip: _receiptText('refresh'),
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: FutureBuilder<List<_TripHistoryItem>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    '${_receiptText('historyLoadFailed')}\n${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              );
            }
            final items = snapshot.data ?? const <_TripHistoryItem>[];
            if (items.isEmpty) {
              return Center(
                child: Text(
                  _receiptText('historyEmpty'),
                  style: const TextStyle(color: Colors.white70),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = items[index];
                final km = item.kmTotal == null
                    ? '—'
                    : '${item.kmTotal!.toStringAsFixed(1)} km';
                final total = item.totalEur == null
                    ? '€ —'
                    : '€ ${item.totalEur!.toStringAsFixed(2)}';
                return Card(
                  color: const Color(0xFF141B2F),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _openReceipt(item),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 4, 12, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ListTile(
                            leading: const Icon(
                              Icons.local_taxi_outlined,
                              color: Colors.white70,
                            ),
                            title: Text(
                              item.destination,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '${item.kindLabel}${item.isLocalOnlyDirectFallback ? ' • Lokaal' : ''} • ${_formatDate(item.startedAt)}\n$km • ${_receiptText('waitingCompact')} ${_formatWait(item.waitSecondsTotal)} • ${_localizedRideStatus(item.status)}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  height: 1.35,
                                ),
                              ),
                            ),
                            trailing: Text(
                              total,
                              style: const TextStyle(
                                color: Color(0xFFFFD400),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            contentPadding: const EdgeInsets.only(left: 16),
                            isThreeLine: true,
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.end,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () => _archiveTrip(item),
                                  icon: const Icon(
                                    Icons.archive_outlined,
                                    size: 18,
                                  ),
                                  label: Text(_receiptText('archiveTripLabel')),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white70,
                                    side: const BorderSide(
                                      color: Colors.white24,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ),
                                FilledButton.icon(
                                  onPressed: () => _openReceipt(item),
                                  icon: const Icon(
                                    Icons.receipt_long,
                                    size: 18,
                                  ),
                                  label: Text(_receiptText('receiptTitle')),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFFFFD400),
                                    foregroundColor: const Color(0xFF101010),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _RideReceiptPage extends StatelessWidget {
  final _TripHistoryItem item;
  final _ReceiptQuickAction? initialAction;
  final bool autoPopAfterInitialAction;
  final bool showReceiptUi;

  const _RideReceiptPage({
    required this.item,
    this.initialAction,
    this.autoPopAfterInitialAction = false,
    this.showReceiptUi = true,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) => _RideReceiptBody(
        item: item,
        initialAction: initialAction,
        autoPopAfterInitialAction: autoPopAfterInitialAction,
        showReceiptUi: showReceiptUi,
      ),
    );
  }
}

class _RideReceiptBody extends StatefulWidget {
  final _TripHistoryItem item;
  final _ReceiptQuickAction? initialAction;
  final bool autoPopAfterInitialAction;
  final bool showReceiptUi;

  const _RideReceiptBody({
    required this.item,
    this.initialAction,
    this.autoPopAfterInitialAction = false,
    this.showReceiptUi = true,
  });

  @override
  State<_RideReceiptBody> createState() => _RideReceiptBodyState();
}

enum _ReceiptPaymentStatus { pending, sent, paid }

enum _ReceiptQuickAction { viewPdf, sharePdf, whatsappPdf, emailPdf, printPdf }

class _ReceiptPdfBundle {
  final Uint8List bytes;
  final File file;

  const _ReceiptPdfBundle({required this.bytes, required this.file});
}

class _ReceiptPdfActionRunner {
  static Future<void> previewPdf({
    required BuildContext context,
    required _TripHistoryItem item,
  }) async {
    final bundle = await _buildReceiptPdfBundle(context: context, item: item);
    if (bundle == null) {
      await _fallbackCopyText(context: context, item: item);
      return;
    }
    debugPrint('[PDF][ACTION][CUSTOMER_DIRECT_VIEW] hasPdf=true');
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ReceiptPdfPreviewPage(
          title: _receiptText('viewPdf'),
          bytes: bundle.bytes,
        ),
      ),
    );
  }

  static Future<void> sharePdf({
    required BuildContext context,
    required _TripHistoryItem item,
  }) async {
    final bundle = await _buildReceiptPdfBundle(context: context, item: item);
    if (bundle == null) {
      await _fallbackCopyText(context: context, item: item);
      return;
    }
    debugPrint('[PDF][ACTION][CUSTOMER_DIRECT_SHARE] hasPdf=true');
    debugPrint('[PDF][ACTION][PDF_SHARE] hasPdf=true');
    await Share.shareXFiles(
      <XFile>[XFile(bundle.file.path)],
      text: _receiptCustomerMessage(item),
      subject: _receiptText('receiptEmailSubject'),
    );
  }

  static Future<void> sharePdfViaWhatsApp({
    required BuildContext context,
    required _TripHistoryItem item,
  }) async {
    final bundle = await _buildReceiptPdfBundle(context: context, item: item);
    if (bundle == null) {
      await _fallbackWhatsAppText(context: context, item: item);
      return;
    }
    final contact = _resolvePdfContact(item);
    final phone = _normalizePhoneForWhatsApp(
      contact.phoneRaw,
      countryContext: _customerCountryContext(item),
    );
    final phoneFound = phone != null;
    const packageTarget = 'share_sheet';
    debugPrint(
      '[PDF][ACTION][WHATSAPP_PDF] phoneFound=$phoneFound hasPdf=true packageTarget=$packageTarget',
    );

    if (phoneFound && context.mounted) {
      await Clipboard.setData(ClipboardData(text: phone));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              nl: 'Klantnummer gekopieerd. Kies WhatsApp en selecteer of plak de klant om de PDF te sturen.',
              en: 'Customer number copied. Choose WhatsApp and select or paste the customer to send the PDF.',
              fr: 'Numéro client copié. Choisissez WhatsApp puis sélectionnez ou collez le client pour envoyer le PDF.',
              es: 'Número del cliente copiado. Elija WhatsApp y seleccione o pegue el cliente para enviar el PDF.',
            ),
          ),
        ),
      );
    }

    final message = _tr(
      nl: 'Beste klant, in bijlage vindt u uw betaalbewijs/ritbon (PDF).',
      en: 'Dear customer, your ride receipt PDF is attached.',
      fr: 'Cher client, votre reçu de course PDF est en pièce jointe.',
      es: 'Estimado cliente, su comprobante de viaje en PDF está adjunto.',
    );

    try {
      await Share.shareXFiles(
        <XFile>[XFile(bundle.file.path)],
        text: message,
        subject: _receiptText('whatsappPdf'),
      );
    } catch (_) {
      await _fallbackWhatsAppText(context: context, item: item);
    }
  }

  static Future<void> sharePdfViaEmail({
    required BuildContext context,
    required _TripHistoryItem item,
  }) async {
    final contact = _resolvePdfContact(item);
    final recipient = (contact.email ?? '').trim();
    final bundle = await _buildReceiptPdfBundle(context: context, item: item);
    if (bundle == null) {
      await _fallbackEmailText(context: context, item: item);
      return;
    }
    final serverResult = await _sendReceiptEmailViaWorker(
      item: item,
      language: _currentLanguageCode(),
      source: 'flutter_receipt_button',
    );
    final serverStatus = (serverResult['status'] ?? '').toString();
    final serverOk = serverResult['ok'] == true;
    if (!context.mounted) return;
    if (serverOk && serverStatus == 'sent') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              nl: 'E-mail verzonden naar klant.',
              en: 'Email sent to customer.',
              fr: 'E-mail envoye au client.',
              es: 'Correo enviado al cliente.',
            ),
          ),
        ),
      );
      return;
    }
    if (serverOk && serverStatus == 'already_sent') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              nl: 'Factuur werd al verzonden.',
              en: 'Invoice was already sent.',
              fr: 'La facture a deja ete envoyee.',
              es: 'La factura ya fue enviada.',
            ),
          ),
        ),
      );
      return;
    }
    if (serverStatus == 'missing_email') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              nl: 'Geen klantmail gevonden.',
              en: 'No customer email found.',
              fr: 'Aucun e-mail client trouve.',
              es: 'No se encontro correo del cliente.',
            ),
          ),
        ),
      );
      return;
    }
    if (!serverOk || serverStatus == 'skipped' || serverStatus == 'error') {
      debugPrint(
        '[PDF][ACTION][EMAIL_PDF] emailFound=${recipient.isNotEmpty} hasPdf=true composer=server_failed status=$serverStatus',
      );
      await _showEmailFallbackOptions(
        context: context,
        bundle: bundle,
        recipient: recipient,
        item: item,
      );
      return;
    }
    final shortBody = _tr(
      nl: 'Beste klant, in bijlage vindt u uw betaalbewijs/ritbon (PDF).',
      en: 'Dear customer, your ride receipt PDF is attached.',
      fr: 'Cher client, votre reçu de course PDF est en pièce jointe.',
      es: 'Estimado cliente, su comprobante de viaje en PDF está adjunto.',
    );
    if (recipient.isNotEmpty &&
        !kIsWeb &&
        (Platform.isAndroid || Platform.isIOS)) {
      try {
        final email = Email(
          recipients: <String>[recipient],
          subject: _receiptText('receiptEmailSubject'),
          body: shortBody,
          attachmentPaths: <String>[bundle.file.path],
          isHTML: false,
        );
        await FlutterEmailSender.send(email);
        debugPrint(
          '[PDF][ACTION][EMAIL_PDF] emailFound=true hasPdf=true composer=native',
        );
        return;
      } catch (_) {
        // Fall through to share-sheet fallback.
      }
    }
    debugPrint(
      '[PDF][ACTION][EMAIL_PDF] emailFound=${recipient.isNotEmpty} hasPdf=true composer=share_fallback',
    );
    await Share.shareXFiles(
      <XFile>[XFile(bundle.file.path)],
      text: shortBody,
      subject: _receiptText('receiptEmailSubject'),
    );
    if (!context.mounted) return;
    if (recipient.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: recipient));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              nl: 'E-mailadres gekopieerd. Deel de PDF nu via de gekozen mail-app.',
              en: 'Email copied. Share the PDF now via the selected mail app.',
              fr: 'E-mail copié. Partagez maintenant le PDF via l’application e-mail choisie.',
              es: 'Correo copiado. Comparta ahora el PDF mediante la app de correo elegida.',
            ),
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_receiptText('noCustomerContact'))),
      );
    }
  }

  static Future<void> printPdf({
    required BuildContext context,
    required _TripHistoryItem item,
  }) async {
    final bundle = await _buildReceiptPdfBundle(context: context, item: item);
    if (bundle == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_receiptText('printLater'))));
      return;
    }
    await Printing.layoutPdf(onLayout: (_) async => bundle.bytes);
  }

  static Future<void> _fallbackCopyText({
    required BuildContext context,
    required _TripHistoryItem item,
  }) async {
    await Clipboard.setData(ClipboardData(text: _receiptCustomerMessage(item)));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_receiptText('receiptCopied'))));
  }

  static Future<void> _fallbackWhatsAppText({
    required BuildContext context,
    required _TripHistoryItem item,
  }) async {
    final contact = _resolvePdfContact(item);
    final phone = _normalizePhoneForWhatsApp(
      contact.phoneRaw,
      countryContext: _customerCountryContext(item),
    );
    debugPrint(
      '[PDF][ACTION][WHATSAPP_TEXT] phoneFound=${phone != null} source=${contact.source}',
    );
    if (phone == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_receiptText('noValidWhatsappPhone'))),
      );
      return;
    }
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    final uri = Uri.https('wa.me', '/$digits', <String, String>{
      'text': _tr(
        nl: 'Beste klant, uw betaalbewijs/ritbon is klaar. Ik stuur de PDF zo meteen door.',
        en: 'Dear customer, your ride receipt is ready. I will send the PDF shortly.',
        fr: 'Cher client, votre reçu de course est prêt. Je vais envoyer le PDF dans un instant.',
        es: 'Estimado cliente, su comprobante de viaje está listo. Enviaré el PDF en un momento.',
      ),
    });
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_receiptText('whatsappOpenFailed'))),
      );
    }
  }

  static Future<void> _fallbackEmailText({
    required BuildContext context,
    required _TripHistoryItem item,
  }) async {
    final contact = _resolvePdfContact(item);
    final recipient = (contact.email ?? '').trim();
    final encodedSubject = Uri.encodeComponent(
      _receiptText('receiptEmailSubject'),
    );
    final encodedBody = Uri.encodeComponent(_receiptCustomerMessage(item));
    final uri = Uri.parse(
      recipient.isNotEmpty
          ? 'mailto:${Uri.encodeComponent(recipient)}?subject=$encodedSubject&body=$encodedBody'
          : 'mailto:?subject=$encodedSubject&body=$encodedBody',
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_receiptText('emailOpenFailed'))));
    }
  }

  static Future<Map<String, dynamic>> _sendReceiptEmailViaWorker({
    required _TripHistoryItem item,
    required String language,
    required String source,
  }) async {
    final bookingId = (item.bookingId ?? '').trim().isNotEmpty
        ? (item.bookingId ?? '').trim()
        : (_firstPathText(item, const [
                    ['booking_id'],
                    ['bookingId'],
                    ['id'],
                    ['booking', 'booking_id'],
                    ['booking', 'bookingId'],
                    ['booking', 'id'],
                    ['record', 'booking_id'],
                    ['record', 'bookingId'],
                    ['record', 'booking', 'booking_id'],
                    ['record', 'booking', 'bookingId'],
                    ['record', 'booking', 'id'],
                    ['payload', 'booking_id'],
                    ['payload', 'bookingId'],
                    ['payload', 'booking', 'booking_id'],
                    ['payload', 'booking', 'bookingId'],
                    ['public_reference'],
                    ['publicReference'],
                    ['receipt_reference'],
                    ['receiptReference'],
                    ['booking', 'public_reference'],
                    ['booking', 'publicReference'],
                    ['booking', 'receipt_reference'],
                    ['booking', 'receiptReference'],
                  ]) ??
                  '')
              .trim();
    if (bookingId.isEmpty) {
      return <String, dynamic>{
        'ok': false,
        'status': 'error',
        'message': 'Missing booking id',
      };
    }
    final uri = Uri.parse(
      '$kBookingBaseUrl/bookings/${Uri.encodeComponent(bookingId)}/receipt/email',
    );
    final payload = <String, dynamic>{
      'manual': true,
      'language': _normalizeLanguageCode(language),
      'source': source,
    };
    final headers = <String, String>{
      'Content-Type': 'application/json',
      ..._adminHeaders(),
    };
    try {
      final res = await http
          .post(uri, headers: headers, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 20));
      final decoded = jsonDecode(res.body);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return <String, dynamic>{
        'ok': false,
        'status': 'error',
        'message': 'Unexpected server response',
      };
    } catch (err) {
      return <String, dynamic>{
        'ok': false,
        'status': 'error',
        'message': err.toString(),
      };
    }
  }

  static Future<void> _showEmailFallbackOptions({
    required BuildContext context,
    required _ReceiptPdfBundle bundle,
    required String recipient,
    required _TripHistoryItem item,
  }) async {
    if (!context.mounted) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.email_outlined),
              title: Text(
                _tr(
                  nl: 'Open mail-app',
                  en: 'Open mail app',
                  fr: 'Ouvrir app e-mail',
                  es: 'Abrir app de correo',
                ),
              ),
              onTap: () => Navigator.of(sheetContext).pop('open_mail'),
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: Text(
                _tr(
                  nl: 'Deel PDF',
                  en: 'Share PDF',
                  fr: 'Partager le PDF',
                  es: 'Compartir PDF',
                ),
              ),
              onTap: () => Navigator.of(sheetContext).pop('share_pdf'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || choice == null) return;
    if (choice == 'open_mail') {
      await _openMailComposerFallback(
        context: context,
        bundle: bundle,
        recipient: recipient,
        item: item,
      );
      return;
    }
    await _sharePdfFallback(
      context: context,
      bundle: bundle,
      recipient: recipient,
      item: item,
    );
  }

  static Future<void> _openMailComposerFallback({
    required BuildContext context,
    required _ReceiptPdfBundle bundle,
    required String recipient,
    required _TripHistoryItem item,
  }) async {
    final shortBody = _tr(
      nl: 'Beste klant, in bijlage vindt u uw betaalbewijs/ritbon (PDF).',
      en: 'Dear customer, your ride receipt PDF is attached.',
      fr: 'Cher client, votre reçu de course PDF est en pièce jointe.',
      es: 'Estimado cliente, su comprobante de viaje en PDF está adjunto.',
    );
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        final email = Email(
          recipients: recipient.isNotEmpty
              ? <String>[recipient]
              : const <String>[],
          subject: _receiptText('receiptEmailSubject'),
          body: shortBody,
          attachmentPaths: <String>[bundle.file.path],
          isHTML: false,
        );
        await FlutterEmailSender.send(email);
        debugPrint(
          '[PDF][ACTION][EMAIL_PDF] emailFound=${recipient.isNotEmpty} hasPdf=true composer=native',
        );
        return;
      } catch (_) {
        // Fall through to share fallback.
      }
    }
    await _sharePdfFallback(
      context: context,
      bundle: bundle,
      recipient: recipient,
      item: item,
    );
  }

  static Future<void> _sharePdfFallback({
    required BuildContext context,
    required _ReceiptPdfBundle bundle,
    required String recipient,
    required _TripHistoryItem item,
  }) async {
    final shortBody = _tr(
      nl: 'Beste klant, in bijlage vindt u uw betaalbewijs/ritbon (PDF).',
      en: 'Dear customer, your ride receipt PDF is attached.',
      fr: 'Cher client, votre reçu de course PDF est en pièce jointe.',
      es: 'Estimado cliente, su comprobante de viaje en PDF está adjunto.',
    );
    debugPrint(
      '[PDF][ACTION][EMAIL_PDF] emailFound=${recipient.isNotEmpty} hasPdf=true composer=share_fallback',
    );
    await Share.shareXFiles(
      <XFile>[XFile(bundle.file.path)],
      text: shortBody,
      subject: _receiptText('receiptEmailSubject'),
    );
    if (!context.mounted) return;
    if (recipient.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: recipient));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              nl: 'E-mailadres gekopieerd. Deel de PDF nu via de gekozen mail-app.',
              en: 'Email copied. Share the PDF now via the selected mail app.',
              fr: 'E-mail copie. Partagez maintenant le PDF via l app e-mail choisie.',
              es: 'Correo copiado. Comparta ahora el PDF mediante la app de correo elegida.',
            ),
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_receiptText('noCustomerContact'))),
      );
    }
  }

  static String _normalizeLanguageCode(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'nl' ||
        normalized == 'en' ||
        normalized == 'fr' ||
        normalized == 'es') {
      return normalized;
    }
    return 'nl';
  }

  static String _currentLanguageCode() {
    switch (appConfig.currentLanguage) {
      case AppLanguage.en:
        return 'en';
      case AppLanguage.fr:
        return 'fr';
      case AppLanguage.es:
        return 'es';
      case AppLanguage.nl:
        return 'nl';
    }
  }

  static Future<_ReceiptPdfBundle?> _buildReceiptPdfBundle({
    required BuildContext context,
    required _TripHistoryItem item,
  }) async {
    try {
      final smartRef = _businessReferenceDisplayForItem(
        item,
        source: 'receipt_pdf_bundle_static_layout',
      );
      final contact = _resolvePdfContact(item);
      final keyList = contact.keys.join(',');
      debugPrint(
        '[PDF][CONTACT] emailFound=${contact.email != null} phoneFound=${contact.phoneRaw != null} source=${contact.source} keys=$keyList',
      );
      final route = _resolveRoute(item);
      debugPrint(
        '[PDF][ROUTE] fromFound=${route.from != _receiptText('currentLocation')} toFound=${route.to != '-'} source=${route.source}',
      );

      final seller = await _buildSellerProfile();
      final logoBytes = await _loadReceiptLogoBytes(seller['logoPath']);
      final doc = pw.Document();
      final baseFont = await PdfGoogleFonts.notoSansRegular();
      final boldFont = await PdfGoogleFonts.notoSansBold();
      final amounts = _resolvedReceiptAmounts(item);
      final paymentStatusRaw = _firstPathText(item, const [
        ['payment_status'],
        ['paymentStatus'],
        ['booking', 'payment_status'],
        ['booking', 'paymentStatus'],
        ['mollie', 'status'],
        ['record', 'mollie', 'status'],
      ]);
      final paymentProviderRaw = _firstPathText(item, const [
        ['payment_provider'],
        ['paymentProvider'],
        ['booking', 'payment_provider'],
        ['booking', 'paymentProvider'],
      ]);
      final paymentMethodRaw = _firstPathText(item, const [
        ['payment_method'],
        ['paymentMethod'],
        ['booking', 'payment_method'],
        ['booking', 'paymentMethod'],
      ]);
      final paymentSourceRaw = _firstPathText(item, const [
        ['payment_source'],
        ['paymentSource'],
        ['booking', 'payment_source'],
        ['booking', 'paymentSource'],
      ]);
      final paymentMethod = _localizedPaymentMethodValue(
        _paymentFieldWithMolliePaidFallback(
          value: paymentMethodRaw,
          paymentStatus: paymentStatusRaw,
          paymentProvider: paymentProviderRaw,
        ),
      );
      final paymentSource = _localizedPaymentSourceValue(
        _paymentFieldWithMolliePaidFallback(
          value: paymentSourceRaw,
          paymentStatus: paymentStatusRaw,
          paymentProvider: paymentProviderRaw,
        ),
      );
      final rideDateText =
          _firstPathText(item, const [
                ['scheduled_pickup_at'],
                ['booking', 'scheduled_pickup_at'],
              ]) !=
              null
          ? _formatDate(
              _firstPathText(item, const [
                ['scheduled_pickup_at'],
                ['booking', 'scheduled_pickup_at'],
              ]),
            )
          : _formatDate(item.startedAt);
      final serviceText = _displayServiceToken(
        _firstPathText(item, const [
          ['service_type'],
          ['booking', 'service_type'],
        ]),
      );
      final tierText = _displayTierToken(
        _firstPathText(item, const [
          ['tier'],
          ['booking', 'tier'],
        ]),
      );
      final durationText =
          _minutesText(
            _firstPathDouble(item, 'duration_route_min') ??
                _firstPathDouble(item, 'route_minutes'),
          ) ??
          _receiptText('notAvailable');
      final businessFields = _resolveBusinessFields(item);
      debugPrint(
        '[RECEIPT][BUSINESS_FIELDS] source=static_pdf booking=${_safeRefPreview(item.bookingId ?? item.tripId)} business=${businessFields.isBusinessDocument} invoiceRequested=${businessFields.invoiceRequested} companyFound=${businessFields.companyName.isNotEmpty} vatFound=${businessFields.vatNumber.isNotEmpty} invoiceEmailFound=${businessFields.invoiceEmail.isNotEmpty} invoiceAddressFound=${businessFields.invoiceAddress.isNotEmpty}',
      );
      // #region agent log H4 static receipt business projection
      unawaited(
        _agentDebugLog(
          runId: 'initial',
          hypothesisId: 'H4',
          location: 'main.dart:_ReceiptPdfActionRunner._buildReceiptPdfBundle',
          message: '[RECEIPT][BUSINESS_FIELDS]',
          data: <String, dynamic>{
            'source': 'static_pdf',
            'booking': _safeRefPreview(item.bookingId ?? item.tripId),
            'business': businessFields.isBusinessDocument,
            'invoiceRequested': businessFields.invoiceRequested,
            'companyFound': businessFields.companyName.isNotEmpty,
            'vatFound': businessFields.vatNumber.isNotEmpty,
            'invoiceEmailFound': businessFields.invoiceEmail.isNotEmpty,
            'invoiceAddressFound': businessFields.invoiceAddress.isNotEmpty,
          },
        ),
      );
      // #endregion
      final documentTitle = businessFields.isBusinessDocument
          ? _receiptText('invoiceLabel')
          : _receiptText('paymentReceiptLabel');
      final footerText = seller['footer']?.trim().isNotEmpty == true
          ? seller['footer']!.trim()
          : _receiptText('pdfFooterDefault');

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          build: (pw.Context pdfContext) => [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                if (logoBytes != null)
                  pw.Container(
                    width: 82,
                    height: 82,
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey300),
                    ),
                    child: pw.Image(
                      pw.MemoryImage(logoBytes),
                      fit: pw.BoxFit.contain,
                    ),
                  ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        seller['companyName'] ?? kCompanyName,
                        style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                          font: boldFont,
                        ),
                        textAlign: pw.TextAlign.right,
                      ),
                      if ((seller['legalName'] ?? '').trim().isNotEmpty &&
                          seller['legalName'] != seller['companyName'])
                        pw.Text(
                          seller['legalName']!,
                          textAlign: pw.TextAlign.right,
                        ),
                      if ((seller['address'] ?? '').trim().isNotEmpty)
                        pw.Text(
                          seller['address']!,
                          textAlign: pw.TextAlign.right,
                        ),
                      if ((seller['vatNumber'] ?? '').trim().isNotEmpty)
                        pw.Text(
                          '${_receiptText('companyVat')}: ${seller['vatNumber']!}',
                          textAlign: pw.TextAlign.right,
                        ),
                      if ((seller['phone'] ?? '').trim().isNotEmpty)
                        pw.Text(
                          '${_receiptText('companyPhone')}: ${seller['phone']!}',
                          textAlign: pw.TextAlign.right,
                        ),
                      if ((seller['email'] ?? '').trim().isNotEmpty)
                        pw.Text(
                          '${_receiptText('companyEmail')}: ${seller['email']!}',
                          textAlign: pw.TextAlign.right,
                        ),
                      if ((seller['website'] ?? '').trim().isNotEmpty)
                        pw.Text(
                          '${_receiptText('companyWebsite')}: ${seller['website']!}',
                          textAlign: pw.TextAlign.right,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 18),
            pw.Text(
              documentTitle,
              style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
                font: boldFont,
              ),
            ),
            pw.SizedBox(height: 10),
            _pdfInfoRow(smartRef.label, smartRef.value),
            _pdfInfoRow(_receiptText('date'), rideDateText),
            _pdfInfoRow(_receiptText('type'), item.kindLabel),
            _pdfInfoRow(_receiptText('service'), serviceText),
            _pdfInfoRow(_receiptText('tier'), tierText),
            _pdfInfoRow(_receiptText('from'), route.from),
            _pdfInfoRow(_receiptText('to'), route.to),
            _pdfInfoRow(_receiptText('distance'), _kmText(item)),
            _pdfInfoRow(_receiptText('duration'), durationText),
            pw.SizedBox(height: 12),
            pw.Text(
              _receiptText('customerDetails'),
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                font: boldFont,
              ),
            ),
            pw.SizedBox(height: 6),
            _pdfInfoRow(
              _receiptText('customerName'),
              contact.name ?? _receiptText('notAvailable'),
            ),
            _pdfInfoRow(
              _receiptText('customerEmail'),
              contact.email ?? _receiptText('notAvailable'),
            ),
            _pdfInfoRow(
              _receiptText('customerPhone'),
              contact.phoneRaw ?? _receiptText('notAvailable'),
            ),
            if (businessFields.isBusinessDocument) ...[
              pw.SizedBox(height: 12),
              pw.Text(
                _tr(
                  nl: 'Zakelijk / Factuur',
                  en: 'Business / Invoice',
                  fr: 'Professionnel / Facture',
                  es: 'Empresa / Factura',
                ),
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  font: boldFont,
                ),
              ),
              pw.SizedBox(height: 6),
              _pdfInfoRow(
                _tr(
                  nl: 'Bedrijfsnaam',
                  en: 'Company name',
                  fr: "Nom de l'entreprise",
                  es: 'Empresa',
                ),
                businessFields.companyName.isEmpty
                    ? _receiptText('notAvailable')
                    : businessFields.companyName,
              ),
              _pdfInfoRow(
                _tr(
                  nl: 'BTW-nummer',
                  en: 'VAT number',
                  fr: 'Numero de TVA',
                  es: 'NIF/IVA',
                ),
                businessFields.vatNumber.isEmpty
                    ? _receiptText('notAvailable')
                    : businessFields.vatNumber,
              ),
              _pdfInfoRow(
                _tr(
                  nl: 'Factuur e-mail',
                  en: 'Invoice email',
                  fr: 'E-mail facture',
                  es: 'Email de factura',
                ),
                businessFields.invoiceEmail.isEmpty
                    ? _receiptText('notAvailable')
                    : businessFields.invoiceEmail,
              ),
              _pdfInfoRow(
                _tr(
                  nl: 'Factuuradres',
                  en: 'Invoice address',
                  fr: 'Adresse de facturation',
                  es: 'Direccion de factura',
                ),
                businessFields.invoiceAddress.isEmpty
                    ? _receiptText('notAvailable')
                    : businessFields.invoiceAddress,
              ),
            ],
            pw.SizedBox(height: 12),
            pw.Text(
              _receiptText('paymentActions'),
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                font: boldFont,
              ),
            ),
            pw.SizedBox(height: 6),
            _pdfInfoRow(
              _receiptText('paymentStatus'),
              _paymentStatusText(item),
            ),
            _pdfInfoRow(_receiptText('paymentMethod'), paymentMethod),
            _pdfInfoRow(_receiptText('paymentSource'), paymentSource),
            pw.Divider(color: PdfColors.grey400),
            _pdfInfoRow(
              _receiptText('subtotalExVat'),
              '€ ${amounts.subtotal.toStringAsFixed(2)}',
            ),
            _pdfInfoRow(
              '${_receiptText('vatAmount')} (${(amounts.vatRate * 100).toStringAsFixed(0)}%)',
              '€ ${amounts.vatAmount.toStringAsFixed(2)}',
            ),
            _pdfInfoRow(
              _receiptText('total'),
              '€ ${amounts.total.toStringAsFixed(2)}',
            ),
            pw.SizedBox(height: 16),
            pw.Text(
              footerText,
              style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 10),
            ),
          ],
          theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
        ),
      );

      final bytes = await doc.save();
      final tempDir = await getTemporaryDirectory();
      final receiptsDir = Directory(
        '${tempDir.path}${Platform.pathSeparator}fluxidi_receipts',
      );
      if (!await receiptsDir.exists()) {
        await receiptsDir.create(recursive: true);
      }
      final fileName = _sanitizeFilePart(_customerReference(item));
      final file = File(
        '${receiptsDir.path}${Platform.pathSeparator}$fileName.pdf',
      );
      await file.writeAsBytes(bytes, flush: true);
      return _ReceiptPdfBundle(bytes: bytes, file: file);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_receiptText('pdfGenerationFailed'))),
        );
      }
      return null;
    }
  }

  static ({String from, String to, String source}) _resolveRoute(
    _TripHistoryItem item,
  ) {
    bool isPlaceholder(String? value) {
      final text = value?.trim();
      if (text == null || text.isEmpty) return true;
      if (text == '-' || text == '—') return true;
      return text.toLowerCase() ==
          _receiptText('currentLocation').toLowerCase();
    }

    String? pickLabel(List<List<String>> paths) {
      for (final path in paths) {
        final text = _cleanContactText(_detailAt(item, path));
        if (!isPlaceholder(text)) return text;
      }
      return null;
    }

    final normalizedFrom = isPlaceholder(item.origin)
        ? null
        : item.origin.trim();
    final normalizedTo = isPlaceholder(item.destination)
        ? null
        : item.destination.trim();
    final rawFrom = pickLabel(const [
      ['from'],
      ['pickup'],
      ['pickup_address'],
      ['pickupAddress'],
      ['pickupLocation'],
      ['pickup_location'],
      ['origin'],
      ['start_address'],
      ['startAddress'],
      ['booking', 'from'],
      ['booking', 'pickup'],
      ['booking', 'pickup_address'],
      ['booking', 'pickupAddress'],
      ['record', 'from'],
      ['record', 'booking', 'from'],
      ['record', 'booking', 'pickup'],
      ['payload', 'from'],
      ['payload', 'booking', 'from'],
      ['quote', 'inputs', 'from'],
    ]);
    final rawTo = pickLabel(const [
      ['to'],
      ['destination'],
      ['destination_address'],
      ['destinationAddress'],
      ['dropoff'],
      ['dropoff_address'],
      ['dropoffAddress'],
      ['end_address'],
      ['endAddress'],
      ['booking', 'to'],
      ['booking', 'destination'],
      ['booking', 'destination_address'],
      ['booking', 'destinationAddress'],
      ['record', 'to'],
      ['record', 'booking', 'to'],
      ['record', 'booking', 'destination'],
      ['payload', 'to'],
      ['payload', 'booking', 'to'],
      ['quote', 'inputs', 'to'],
    ]);
    final from = _sanitizeCustomerFacingRouteLabel(
      normalizedFrom ?? rawFrom ?? _receiptText('currentLocation'),
      isFromField: true,
    );
    final to = _sanitizeCustomerFacingRouteLabel(
      normalizedTo ?? rawTo ?? '-',
      isFromField: false,
    );
    final source = (normalizedFrom != null || normalizedTo != null)
        ? 'normalized'
        : ((rawFrom != null || rawTo != null) ? 'raw' : 'fallback');
    return (from: from, to: to, source: source);
  }

  static _ResolvedPdfContact _resolvePdfContact(_TripHistoryItem item) {
    String? pick(
      List<List<String>> paths,
      List<String> usedKeys, {
      bool email = false,
    }) {
      for (final path in paths) {
        final text = _cleanContactText(_detailAt(item, path));
        if (text == null || text.isEmpty) continue;
        final normalized = email ? _validEmail(text) : text;
        if (normalized == null || normalized.isEmpty) continue;
        usedKeys.add(path.join('.'));
        return normalized;
      }
      return null;
    }

    final keys = <String>[];
    final normalizedName = _cleanContactText(item.customerName);
    final normalizedPhone = _cleanContactText(item.customerPhone);
    final normalizedEmail = _validEmail(item.customerEmail);
    if (normalizedName != null) keys.add('normalized.customerName');
    if (normalizedPhone != null) keys.add('normalized.customerPhone');
    if (normalizedEmail != null) keys.add('normalized.customerEmail');
    final hasNormalized =
        normalizedName != null ||
        normalizedPhone != null ||
        normalizedEmail != null;
    if (hasNormalized) {
      return _ResolvedPdfContact(
        name: normalizedName,
        phoneRaw: normalizedPhone,
        email: normalizedEmail,
        keys: keys,
        source: 'normalized',
      );
    }

    final name = pick(const [
      ['customer', 'name'],
      ['customer_name'],
      ['customerName'],
      ['custName'],
      ['name'],
      ['booking', 'customer', 'name'],
      ['booking', 'customer_name'],
      ['booking', 'customerName'],
      ['booking', 'custName'],
      ['booking', 'name'],
      ['record', 'customer_name'],
      ['record', 'booking', 'customer_name'],
      ['record', 'booking', 'customerName'],
      ['payload', 'customer_name'],
      ['payload', 'booking', 'customer_name'],
      ['record', 'payload', 'customer_name'],
      ['record', 'payload', 'customerName'],
      ['record', 'payload', 'custName'],
      ['record', 'payload', 'name'],
      ['record', 'payload', 'booking', 'customer_name'],
      ['record', 'payload', 'booking', 'customerName'],
      ['record', 'payload', 'booking', 'custName'],
      ['record', 'payload', 'booking', 'name'],
    ], keys);

    final phoneRaw = pick(const [
      ['customer', 'phone'],
      ['customer_phone'],
      ['customerPhone'],
      ['custPhone'],
      ['phone'],
      ['tel'],
      ['mobile'],
      ['booking', 'customer', 'phone'],
      ['booking', 'customer_phone'],
      ['booking', 'customerPhone'],
      ['booking', 'custPhone'],
      ['booking', 'phone'],
      ['booking', 'tel'],
      ['booking', 'mobile'],
      ['record', 'customer_phone'],
      ['record', 'booking', 'customer_phone'],
      ['record', 'booking', 'customerPhone'],
      ['record', 'booking', 'custPhone'],
      ['payload', 'customer_phone'],
      ['payload', 'booking', 'customer_phone'],
      ['record', 'payload', 'customer_phone'],
      ['record', 'payload', 'customerPhone'],
      ['record', 'payload', 'custPhone'],
      ['record', 'payload', 'phone'],
      ['record', 'payload', 'tel'],
      ['record', 'payload', 'mobile'],
      ['record', 'payload', 'booking', 'customer_phone'],
      ['record', 'payload', 'booking', 'customerPhone'],
      ['record', 'payload', 'booking', 'custPhone'],
      ['record', 'payload', 'booking', 'phone'],
    ], keys);

    final email = pick(
      const [
        ['customer', 'email'],
        ['customer_email'],
        ['customerEmail'],
        ['custEmail'],
        ['email'],
        ['invoice_email'],
        ['invoiceEmail'],
        ['booking', 'customer', 'email'],
        ['booking', 'customer_email'],
        ['booking', 'customerEmail'],
        ['booking', 'custEmail'],
        ['booking', 'email'],
        ['booking', 'invoice_email'],
        ['booking', 'invoiceEmail'],
        ['record', 'customer_email'],
        ['record', 'booking', 'customer_email'],
        ['record', 'booking', 'customerEmail'],
        ['record', 'booking', 'custEmail'],
        ['payload', 'customer_email'],
        ['payload', 'booking', 'customer_email'],
        ['record', 'payload', 'customer_email'],
        ['record', 'payload', 'customerEmail'],
        ['record', 'payload', 'custEmail'],
        ['record', 'payload', 'email'],
        ['record', 'payload', 'invoice_email'],
        ['record', 'payload', 'invoiceEmail'],
        ['record', 'payload', 'booking', 'customer_email'],
        ['record', 'payload', 'booking', 'customerEmail'],
        ['record', 'payload', 'booking', 'custEmail'],
        ['record', 'payload', 'booking', 'email'],
        ['record', 'payload', 'booking', 'invoice_email'],
        ['record', 'payload', 'booking', 'invoiceEmail'],
      ],
      keys,
      email: true,
    );

    final hasRaw = name != null || phoneRaw != null || email != null;
    return _ResolvedPdfContact(
      name: name,
      phoneRaw: phoneRaw,
      email: email,
      keys: keys,
      source: hasRaw ? 'raw' : 'none',
    );
  }

  static String? _customerCountryContext(_TripHistoryItem item) {
    final value = _firstPathText(item, const [
      ['phone_country_code'],
      ['phoneCountryCode'],
      ['dial_code'],
      ['dialCode'],
      ['customer_country'],
      ['customerCountry'],
      ['country'],
      ['countryCode'],
      ['country_iso'],
      ['countryIso'],
      ['locale'],
      ['language'],
    ]);
    if (value != null && value.trim().isNotEmpty) return value;
    if (kTenantId.toLowerCase().trim() == 'fluxidi') return 'BE';
    return null;
  }

  static dynamic _detailAt(_TripHistoryItem item, List<String> path) {
    dynamic current = item.bookingDetails;
    for (final key in path) {
      if (current is Map && current.containsKey(key)) {
        current = current[key];
      } else {
        current = null;
        break;
      }
    }
    if (current != null) return current;
    current = item.rawSource;
    for (final key in path) {
      if (current is Map && current.containsKey(key)) {
        current = current[key];
      } else {
        return null;
      }
    }
    return current;
  }

  static String? _cleanContactText(dynamic value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty || text == 'null') return null;
    return text;
  }

  static String? _firstPathText(
    _TripHistoryItem item,
    List<List<String>> paths,
  ) {
    for (final path in paths) {
      final text = _cleanContactText(_detailAt(item, path));
      if (text != null) return text;
    }
    return null;
  }

  static String? _validEmail(String? value) {
    final email = value?.trim();
    if (email == null || email.isEmpty) return null;
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) return null;
    return email;
  }

  static String? _normalizePhoneForWhatsApp(
    String? raw, {
    String? countryContext,
  }) {
    final input = raw?.trim();
    if (input == null || input.isEmpty) return null;
    var cleaned = input.replaceAll(RegExp(r'[\s\-\(\)\/\.]'), '');
    if (cleaned.startsWith('00')) cleaned = '+${cleaned.substring(2)}';
    if (cleaned.startsWith('+')) {
      final digits = cleaned.substring(1).replaceAll(RegExp(r'\D'), '');
      if (digits.length < 8 || digits.length > 15) return null;
      return '+$digits';
    }
    final digits = cleaned.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 6) return null;

    final context = countryContext?.toUpperCase().trim() ?? '';
    if ((context == 'BE' || context == 'BELGIUM' || context.isEmpty) &&
        digits.startsWith('0') &&
        digits.length >= 9) {
      final national = digits.replaceFirst(RegExp(r'^0+'), '');
      if (national.isEmpty) return null;
      return '+32$national';
    }
    return null;
  }

  static String _formatDate(String? iso) {
    if (iso == null || iso.trim().isEmpty) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      String two(int v) => v.toString().padLeft(2, '0');
      return '${two(dt.day)}-${two(dt.month)}-${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
    } catch (_) {
      return iso;
    }
  }

  static double? _detailDouble(_TripHistoryItem item, String key) {
    final value = item.bookingDetails[key];
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString().replaceAll(',', '.'));
  }

  static double? _firstPathDouble(_TripHistoryItem item, String key) {
    final direct = _detailDouble(item, key);
    if (direct != null) return direct;
    final text = _firstPathText(item, <List<String>>[
      <String>[key],
      <String>['booking', key],
    ]);
    if (text == null) return null;
    return double.tryParse(text.replaceAll(',', '.'));
  }

  static double? _receiptTotalAmount(_TripHistoryItem item) {
    if (item.kind.toLowerCase().trim() == 'planned') {
      return _detailDouble(item, 'booking_total_eur') ?? item.totalEur;
    }
    return item.totalEur;
  }

  static String _moneyText(double? value) {
    if (value == null) return _receiptText('notAvailable');
    return '€ ${value.toStringAsFixed(2)}';
  }

  static String _totalText(_TripHistoryItem item) =>
      _moneyText(_receiptTotalAmount(item));

  static String _kmText(_TripHistoryItem item) {
    final km = item.kmTotal;
    if (km == null) return _receiptText('notAvailable');
    return '${km.toStringAsFixed(2)} km';
  }

  static String? _minutesText(double? value) {
    if (value == null) return null;
    return '${value.round()} min';
  }

  static ({
    bool isBusinessDocument,
    bool invoiceRequested,
    String companyName,
    String vatNumber,
    String invoiceEmail,
    String invoiceAddress,
  })
  _resolveBusinessFields(_TripHistoryItem item) {
    final invoiceRequested = _toBoolFlag(
      _firstPathText(item, const [
        ['invoice_requested'],
        ['invoiceRequested'],
        ['booking', 'invoice_requested'],
        ['booking', 'invoiceRequested'],
        ['booking_details', 'invoice_requested'],
        ['booking_details', 'invoiceRequested'],
        ['record', 'invoice_requested'],
        ['record', 'invoiceRequested'],
        ['record', 'booking', 'invoice_requested'],
        ['record', 'booking', 'invoiceRequested'],
        ['record', 'booking_details', 'invoice_requested'],
        ['record', 'booking_details', 'invoiceRequested'],
        ['payload', 'invoice_requested'],
        ['payload', 'invoiceRequested'],
        ['payload', 'booking', 'invoice_requested'],
        ['payload', 'booking', 'invoiceRequested'],
      ]),
    );
    final businessFlag = _toBoolFlag(
      _firstPathText(item, const [
        ['business_customer'],
        ['businessCustomer'],
        ['is_business'],
        ['isBusiness'],
        ['business_detected'],
        ['businessDetected'],
        ['booking', 'business_customer'],
        ['booking', 'businessCustomer'],
        ['booking', 'is_business'],
        ['booking', 'isBusiness'],
        ['booking', 'business_detected'],
        ['booking', 'businessDetected'],
        ['booking_details', 'business_customer'],
        ['booking_details', 'businessCustomer'],
        ['booking_details', 'is_business'],
        ['booking_details', 'isBusiness'],
        ['record', 'business_customer'],
        ['record', 'businessCustomer'],
        ['record', 'is_business'],
        ['record', 'isBusiness'],
        ['record', 'business_detected'],
        ['record', 'businessDetected'],
        ['record', 'booking', 'business_customer'],
        ['record', 'booking', 'businessCustomer'],
        ['record', 'booking', 'is_business'],
        ['record', 'booking', 'isBusiness'],
        ['record', 'booking', 'business_detected'],
        ['record', 'booking', 'businessDetected'],
      ]),
    );
    final customerCompany = _firstPathText(item, const [
      ['company_name'],
      ['companyName'],
      ['customer_company'],
      ['customerCompany'],
      ['booking', 'company_name'],
      ['booking', 'companyName'],
      ['booking_details', 'company_name'],
      ['booking_details', 'companyName'],
      ['record', 'company_name'],
      ['record', 'companyName'],
      ['record', 'booking', 'company_name'],
      ['record', 'booking', 'companyName'],
      ['record', 'booking_details', 'company_name'],
      ['record', 'booking_details', 'companyName'],
      ['payload', 'company_name'],
      ['payload', 'companyName'],
      ['payload', 'booking', 'company_name'],
      ['payload', 'booking', 'companyName'],
    ]);
    final customerVat = _firstPathText(item, const [
      ['vat_number'],
      ['vatNumber'],
      ['customer_vat'],
      ['customerVat'],
      ['booking', 'vat_number'],
      ['booking', 'vatNumber'],
      ['booking_details', 'vat_number'],
      ['booking_details', 'vatNumber'],
      ['record', 'vat_number'],
      ['record', 'vatNumber'],
      ['record', 'booking', 'vat_number'],
      ['record', 'booking', 'vatNumber'],
      ['record', 'booking_details', 'vat_number'],
      ['record', 'booking_details', 'vatNumber'],
      ['payload', 'vat_number'],
      ['payload', 'vatNumber'],
      ['payload', 'booking', 'vat_number'],
      ['payload', 'booking', 'vatNumber'],
    ]);
    final invoiceEmail =
        _firstPathText(item, const [
          ['invoice_email'],
          ['invoiceEmail'],
          ['booking', 'invoice_email'],
          ['booking', 'invoiceEmail'],
          ['booking_details', 'invoice_email'],
          ['booking_details', 'invoiceEmail'],
          ['record', 'invoice_email'],
          ['record', 'invoiceEmail'],
          ['record', 'booking', 'invoice_email'],
          ['record', 'booking', 'invoiceEmail'],
          ['record', 'booking_details', 'invoice_email'],
          ['record', 'booking_details', 'invoiceEmail'],
          ['payload', 'invoice_email'],
          ['payload', 'invoiceEmail'],
          ['payload', 'booking', 'invoice_email'],
          ['payload', 'booking', 'invoiceEmail'],
        ]) ??
        '';
    final invoiceAddress =
        _firstPathText(item, const [
          ['invoice_address'],
          ['invoiceAddress'],
          ['billing_address'],
          ['billingAddress'],
          ['company_address'],
          ['companyAddress'],
          ['booking', 'invoice_address'],
          ['booking', 'invoiceAddress'],
          ['booking', 'billing_address'],
          ['booking', 'billingAddress'],
          ['booking_details', 'invoice_address'],
          ['booking_details', 'invoiceAddress'],
          ['record', 'invoice_address'],
          ['record', 'invoiceAddress'],
          ['record', 'billing_address'],
          ['record', 'billingAddress'],
          ['record', 'booking', 'invoice_address'],
          ['record', 'booking', 'invoiceAddress'],
          ['record', 'booking_details', 'invoice_address'],
          ['record', 'booking_details', 'invoiceAddress'],
          ['payload', 'invoice_address'],
          ['payload', 'invoiceAddress'],
          ['payload', 'booking', 'invoice_address'],
          ['payload', 'booking', 'invoiceAddress'],
        ]) ??
        '';
    final hasBusiness =
        invoiceRequested ||
        businessFlag ||
        (customerCompany != null && customerCompany.trim().isNotEmpty) ||
        (customerVat != null && customerVat.trim().isNotEmpty);
    return (
      isBusinessDocument: hasBusiness,
      invoiceRequested: invoiceRequested,
      companyName: (customerCompany ?? '').trim(),
      vatNumber: (customerVat ?? '').trim(),
      invoiceEmail: invoiceEmail.trim(),
      invoiceAddress: invoiceAddress.trim(),
    );
  }

  static bool _isBusinessDocument(_TripHistoryItem item) {
    return _resolveBusinessFields(item).isBusinessDocument;
  }

  static bool _toBoolFlag(String? value) {
    final normalized = value?.toLowerCase().trim() ?? '';
    return normalized == '1' ||
        normalized == 'true' ||
        normalized == 'yes' ||
        normalized == 'ja';
  }

  static ({double subtotal, double vatAmount, double total, double vatRate})
  _resolvedReceiptAmounts(_TripHistoryItem item) {
    final settingsVatRate = businessSettingsNotifier.value.pricingVatRate;
    final vatRateCandidates = <double?>[
      _detailDouble(item, 'vat_rate'),
      _detailDouble(item, 'vatRate'),
      _detailDouble(item, 'booking_vat_rate'),
      _detailDouble(item, 'bookingVatRate'),
    ];
    double vatRate = settingsVatRate.clamp(0.0, 1.0);
    for (final candidate in vatRateCandidates) {
      if (candidate == null || !candidate.isFinite) continue;
      if (candidate > 1.0) {
        vatRate = candidate / 100.0;
        break;
      }
      if (candidate >= 0.0) {
        vatRate = candidate;
        break;
      }
    }
    final total =
        _receiptTotalAmount(item) ??
        _detailDouble(item, 'total') ??
        _detailDouble(item, 'booking_total_eur') ??
        0.0;
    final subtotalCandidate =
        _detailDouble(item, 'subtotal_ex_vat') ??
        _detailDouble(item, 'subtotalExVat') ??
        _detailDouble(item, 'price_ex_vat') ??
        _detailDouble(item, 'priceExVat');
    final vatAmountCandidate =
        _detailDouble(item, 'vat_amount') ??
        _detailDouble(item, 'vatAmount') ??
        _detailDouble(item, 'price_vat') ??
        _detailDouble(item, 'priceVat');

    final subtotal =
        subtotalCandidate ?? (vatRate > 0 ? (total / (1.0 + vatRate)) : total);
    final vatAmount = vatAmountCandidate ?? (total - subtotal);
    return (
      subtotal: subtotal.isFinite ? subtotal : 0.0,
      vatAmount: vatAmount.isFinite ? vatAmount : 0.0,
      total: total.isFinite ? total : 0.0,
      vatRate: vatRate.isFinite ? vatRate : 0.0,
    );
  }

  static String _customerReference(_TripHistoryItem item) {
    return _businessReferenceDisplayForItem(
      item,
      source: 'receipt_pdf_bundle_static',
    ).value;
  }

  static String _localizedPaymentMethodValue(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return _receiptText('notAvailable');
    final normalized = value
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
    switch (normalized) {
      case 'cash':
        return _tr(nl: 'Contant', en: 'Cash', fr: 'Espèces', es: 'Efectivo');
      case 'bancontact':
        return _tr(
          nl: 'Bancontact',
          en: 'Bancontact',
          fr: 'Bancontact',
          es: 'Bancontact',
        );
      case 'card':
        return _tr(nl: 'Kaart', en: 'Card', fr: 'Carte', es: 'Tarjeta');
      case 'qr':
      case 'qr_code':
        return _tr(
          nl: 'QR-code',
          en: 'QR code',
          fr: 'Code QR',
          es: 'Código QR',
        );
      case 'mollie':
        return _tr(
          nl: 'Online betaling',
          en: 'Online payment',
          fr: 'Paiement en ligne',
          es: 'Pago en línea',
        );
      default:
        return _titleCaseToken(value);
    }
  }

  static String _localizedPaymentSourceValue(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return _receiptText('notAvailable');
    final normalized = value
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
    switch (normalized) {
      case 'in_car':
        return _tr(
          nl: 'In de wagen',
          en: 'In vehicle',
          fr: 'Dans le véhicule',
          es: 'En el vehículo',
        );
      case 'payment_link':
        return _tr(
          nl: 'Betaallink',
          en: 'Payment link',
          fr: 'Lien de paiement',
          es: 'Enlace de pago',
        );
      case 'mollie':
        return _tr(nl: 'Mollie', en: 'Mollie', fr: 'Mollie', es: 'Mollie');
      default:
        return _titleCaseToken(value);
    }
  }

  static String _displayServiceToken(String? value) {
    final raw = value?.trim() ?? '';
    final normalized = raw.toLowerCase().replaceAll('-', '_').trim();
    if (normalized == 'passenger' ||
        normalized == 'personenvervoer' ||
        normalized == 'passenger_transport') {
      return _receiptText('passengerTransport');
    }
    if (normalized == 'airport' ||
        normalized == 'airport_transfer' ||
        normalized == 'luchthaven') {
      return _receiptText('airportTransfer');
    }
    return _titleCaseToken(raw);
  }

  static String _displayTierToken(String? value) {
    final raw = value?.trim() ?? '';
    final normalized = raw.toLowerCase().replaceAll('-', '_').trim();
    if (normalized == 'comfort') return _receiptText('tierComfort');
    if (normalized == 'private') return _receiptText('tierPrivate');
    if (normalized == 'premium') return _receiptText('tierPremium');
    return _titleCaseToken(raw);
  }

  static String _paymentStatusText(_TripHistoryItem item) {
    final raw = _firstPathText(item, const [
      ['payment_status'],
      ['paymentStatus'],
      ['booking', 'payment_status'],
      ['booking', 'paymentStatus'],
      ['record', 'payment_status'],
      ['record', 'paymentStatus'],
      ['record', 'booking', 'payment_status'],
      ['record', 'booking', 'paymentStatus'],
      ['mollie', 'status'],
      ['record', 'mollie', 'status'],
    ])?.toLowerCase().trim();
    if (raw == 'paid' || raw == 'settled' || raw == 'confirmed') {
      return _receiptText('paid');
    }
    if (raw == 'open' || raw == 'pending' || raw == 'authorized') {
      return _receiptText('paymentSent');
    }
    return _receiptText('unpaid');
  }

  static String _receiptCustomerMessage(_TripHistoryItem item) {
    final route = _resolveRoute(item);
    final lines = <String>[
      '${_receiptText('receiptFrom')} $kCompanyName',
      '${_receiptText('type')}: ${item.kindLabel}',
      '${_receiptText('reference')}: ${_customerReference(item)}',
      '${_receiptText('from')}: ${route.from}',
      '${_receiptText('to')}: ${route.to}',
      if (_firstPathText(item, const [
            ['scheduled_pickup_at'],
            ['booking', 'scheduled_pickup_at'],
          ]) !=
          null)
        '${_receiptText('scheduledPickup')}: ${_formatDate(_firstPathText(item, const [
          ['scheduled_pickup_at'],
          ['booking', 'scheduled_pickup_at'],
        ]))}',
      if (item.startedAt?.trim().isNotEmpty ?? false)
        '${_receiptText('startTime')}: ${_formatDate(item.startedAt)}',
      if (item.stoppedAt?.trim().isNotEmpty ?? false)
        '${_receiptText('endTime')}: ${_formatDate(item.stoppedAt)}',
      '${_receiptText('distance')}: ${_kmText(item)}',
      '${_receiptText('total')}: ${_totalText(item)}',
      '${_receiptText('paymentStatus')}: ${_paymentStatusText(item)}',
      '',
      _receiptText('thanksRide'),
    ];
    return lines.join('\n');
  }

  static String _sanitizeFilePart(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    return cleaned.isEmpty ? 'receipt' : cleaned;
  }

  static String _titleCaseToken(String value) {
    final normalized = value.trim().replaceAll('_', ' ').replaceAll('-', ' ');
    if (normalized.isEmpty) return '—';
    return normalized
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .map(
          (part) => part.length == 1
              ? part.toUpperCase()
              : '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  static pw.Widget _pdfInfoRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 140,
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey700,
              ),
            ),
          ),
          pw.Expanded(child: pw.Text(value)),
        ],
      ),
    );
  }

  static Future<Uint8List?> _loadReceiptLogoBytes(String? preferredPath) async {
    final candidates = <String>[
      if (preferredPath != null && preferredPath.trim().isNotEmpty)
        preferredPath.trim(),
      kFluxidiLogoAsset,
    ];
    for (final candidate in candidates) {
      try {
        if (candidate.startsWith('assets/')) {
          final data = await rootBundle.load(candidate);
          return data.buffer.asUint8List();
        }
        final f = File(candidate);
        if (await f.exists()) {
          return await f.readAsBytes();
        }
      } catch (_) {
        // Ignore and try next candidate.
      }
    }
    return null;
  }

  static Future<Map<String, String>> _buildSellerProfile() async {
    final settings = businessSettingsNotifier.value;
    BackendBusinessProfile? backendProfile;
    try {
      backendProfile = await fetchBackendBusinessProfile();
    } catch (_) {
      backendProfile = null;
    }
    final profile =
        backendProfile ??
        localBackendBusinessProfileNotifier.value ??
        BackendBusinessProfile.defaults();
    final postcodeCity = [
      profile.postcode.trim(),
      profile.city.trim(),
    ].where((e) => e.isNotEmpty).join(' ');
    final address = [
      profile.address.trim().isNotEmpty
          ? profile.address.trim()
          : settings.address.trim(),
      if (postcodeCity.isNotEmpty) postcodeCity,
      if (profile.country.trim().isNotEmpty) profile.country.trim(),
    ].where((e) => e.isNotEmpty).join('\n');

    final companyName = profile.companyName.trim().isNotEmpty
        ? profile.companyName.trim()
        : settings.companyName.trim().isNotEmpty
        ? settings.companyName.trim()
        : kCompanyName;
    final legalName = profile.legalName.trim().isNotEmpty
        ? profile.legalName.trim()
        : companyName;
    final profileJson = profile.toJson();
    String localizedFooterFromProfile(AppLanguage lang) {
      final localized = switch (lang) {
        AppLanguage.en =>
          (profileJson['invoiceReceiptFooterTextEn'] ?? '').toString().trim(),
        AppLanguage.fr =>
          (profileJson['invoiceReceiptFooterTextFr'] ?? '').toString().trim(),
        AppLanguage.es =>
          (profileJson['invoiceReceiptFooterTextEs'] ?? '').toString().trim(),
        _ =>
          (profileJson['invoiceReceiptFooterTextNl'] ?? '').toString().trim(),
      };
      return localized;
    }

    final hasAnyLocalizedFooter =
        (profileJson['invoiceReceiptFooterTextNl'] ?? '')
            .toString()
            .trim()
            .isNotEmpty ||
        (profileJson['invoiceReceiptFooterTextEn'] ?? '')
            .toString()
            .trim()
            .isNotEmpty ||
        (profileJson['invoiceReceiptFooterTextFr'] ?? '')
            .toString()
            .trim()
            .isNotEmpty ||
        (profileJson['invoiceReceiptFooterTextEs'] ?? '')
            .toString()
            .trim()
            .isNotEmpty;
    final appLang = appConfig.currentLanguage;
    final localizedFooter = localizedFooterFromProfile(appLang);
    final legacyFooter = profile.invoiceReceiptFooterText.trim();
    final footerText = localizedFooter.isNotEmpty
        ? localizedFooter
        : (legacyFooter.isNotEmpty &&
              (appLang == AppLanguage.nl || !hasAnyLocalizedFooter))
        ? legacyFooter
        : _receiptText('pdfFooterDefault');

    return <String, String>{
      'companyName': companyName,
      'legalName': legalName,
      'address': address,
      'vatNumber': profile.vatNumber.trim().isNotEmpty
          ? profile.vatNumber.trim()
          : settings.vatCompanyNumber.trim(),
      'phone': profile.phone.trim().isNotEmpty
          ? profile.phone.trim()
          : settings.supportPhone.trim(),
      'email': profile.email.trim().isNotEmpty
          ? profile.email.trim()
          : settings.supportEmail.trim(),
      'website': profile.website.trim(),
      'footer': footerText,
      'logoPath': settings.logoAssetPath.trim(),
    };
  }
}

class _ResolvedPdfContact {
  final String? name;
  final String? phoneRaw;
  final String? email;
  final List<String> keys;
  final String source;

  const _ResolvedPdfContact({
    required this.name,
    required this.phoneRaw,
    required this.email,
    required this.keys,
    required this.source,
  });
}

class _RideReceiptBodyState extends State<_RideReceiptBody> {
  _ReceiptPaymentStatus _paymentStatus = _ReceiptPaymentStatus.pending;

  _TripHistoryItem get item => widget.item;

  Map<String, dynamic> _driverScopeBookingViewForReceipt() {
    final map = <String, dynamic>{...item.bookingDetails};
    final bookingId = (item.bookingId ?? '').trim();
    if (bookingId.isNotEmpty) {
      map['booking_id'] = bookingId;
      map['bookingId'] = bookingId;
    }
    if (map['booking'] is! Map) {
      map['booking'] = <String, dynamic>{...item.bookingDetails};
    }
    if ((item.vehicleId ?? '').trim().isNotEmpty) {
      map['vehicle_id'] = item.vehicleId!.trim();
      map['vehicleId'] = item.vehicleId!.trim();
    }
    if (item.driverId.trim().isNotEmpty) {
      map['driver_id'] = item.driverId.trim();
      map['driverId'] = item.driverId.trim();
    }
    return map;
  }

  bool _guardDriverReceiptOperation({required String action}) {
    final booking = _driverScopeBookingViewForReceipt();
    final allowed = _canActiveDriverOperateBooking(booking);
    if (allowed) return true;
    final bookingId =
        _bookingScopeFirstText(booking, const [
          ['booking_id'],
          ['bookingId'],
          ['id'],
          ['booking', 'booking_id'],
          ['booking', 'bookingId'],
        ]) ??
        'unknown';
    final assignedVehicleId =
        _bookingScopeFirstText(booking, const [
          ['assigned_vehicle_id'],
          ['assignedVehicleId'],
          ['vehicle_id'],
          ['vehicleId'],
          ['booking', 'assigned_vehicle_id'],
          ['booking', 'assignedVehicleId'],
          ['booking', 'vehicle_id'],
          ['booking', 'vehicleId'],
        ]) ??
        '';
    debugPrint(
      '[DRIVER_SCOPE][BLOCK] action=$action booking_id=$bookingId assigned_vehicle_id=$assignedVehicleId active_driver_id=${_resolvedActiveDriverIdForScope()} allowed=false',
    );
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_driverOwnershipBlockedMessage())));
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _paymentStatus = _initialPaymentStatus();
    unawaited(_resolveReceiptPaymentStatus());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final action = widget.initialAction;
      if (action != null) {
        unawaited(_runInitialAction(context, action));
      }
    });
  }

  Future<void> _runInitialAction(
    BuildContext context,
    _ReceiptQuickAction action,
  ) async {
    try {
      switch (action) {
        case _ReceiptQuickAction.viewPdf:
          await _viewReceiptPdf(context);
          break;
        case _ReceiptQuickAction.sharePdf:
          await _shareReceiptPdf(context);
          break;
        case _ReceiptQuickAction.whatsappPdf:
          await _shareReceiptPdfViaWhatsApp(context);
          break;
        case _ReceiptQuickAction.emailPdf:
          await _shareReceiptPdfViaEmail(context);
          break;
        case _ReceiptQuickAction.printPdf:
          await _printReceiptPdf(context);
          break;
      }
    } finally {
      if (widget.autoPopAfterInitialAction && context.mounted) {
        Navigator.of(context).maybePop();
      }
    }
  }

  String _formatDate(String? iso) {
    if (iso == null || iso.trim().isEmpty) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      String two(int v) => v.toString().padLeft(2, '0');
      return '${two(dt.day)}-${two(dt.month)}-${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
    } catch (_) {
      return iso;
    }
  }

  String _formatWait(int seconds) {
    if (seconds <= 0) return '0 min';
    final min = seconds ~/ 60;
    final sec = seconds % 60;
    if (min <= 0) return '${sec}s';
    if (sec == 0) return '$min min';
    return '$min min ${sec}s';
  }

  bool get _isPlannedReceipt => item.kind.toLowerCase().trim() == 'planned';

  String? _detailText(String key) {
    final text = item.detail(key);
    return text == null || text == 'null' ? null : text;
  }

  _ReceiptPaymentStatus _initialPaymentStatus() {
    final raw = _firstDetailPathText(const [
      ['payment_status'],
      ['paymentStatus'],
      ['booking', 'payment_status'],
      ['booking', 'paymentStatus'],
      ['record', 'payment_status'],
      ['record', 'paymentStatus'],
      ['record', 'booking', 'payment_status'],
      ['record', 'booking', 'paymentStatus'],
      ['mollie', 'status'],
      ['record', 'mollie', 'status'],
    ])?.toLowerCase().trim();
    if (raw == 'paid' || raw == 'settled' || raw == 'confirmed') {
      return _ReceiptPaymentStatus.paid;
    }
    if (raw == 'open' || raw == 'pending' || raw == 'authorized') {
      return _ReceiptPaymentStatus.sent;
    }
    return _ReceiptPaymentStatus.pending;
  }

  _ReceiptPaymentStatus _paymentStatusFromRaw(String? raw) {
    final normalized = raw?.toLowerCase().trim();
    if (normalized == 'paid' ||
        normalized == 'settled' ||
        normalized == 'confirmed') {
      return _ReceiptPaymentStatus.paid;
    }
    if (normalized == 'open' ||
        normalized == 'pending' ||
        normalized == 'authorized') {
      return _ReceiptPaymentStatus.sent;
    }
    return _ReceiptPaymentStatus.pending;
  }

  String? _mapText(Map<String, dynamic> map, String key) {
    final value = map[key];
    final text = value?.toString().trim();
    if (text == null || text.isEmpty || text.toLowerCase() == 'null')
      return null;
    return text;
  }

  String? _historyTopLevelPaymentStatus() {
    return _mapText(item.bookingDetails, 'payment_status') ??
        _mapText(item.bookingDetails, 'paymentStatus');
  }

  String? _historyNestedPaymentStatus() {
    return _firstDetailPathText(const [
      ['booking', 'payment_status'],
      ['booking', 'paymentStatus'],
      ['booking_details', 'payment_status'],
      ['booking_details', 'paymentStatus'],
      ['record', 'payment_status'],
      ['record', 'paymentStatus'],
      ['record', 'booking', 'payment_status'],
      ['record', 'booking', 'paymentStatus'],
      ['mollie', 'status'],
      ['record', 'mollie', 'status'],
    ]);
  }

  void _mergePaymentFieldsIntoReceiptDetails(Map<String, dynamic> fields) {
    for (final entry in fields.entries) {
      final value = entry.value?.toString().trim();
      if (value == null || value.isEmpty || value.toLowerCase() == 'null')
        continue;
      item.bookingDetails[entry.key] = entry.value;
    }
    final bookingMap = item.bookingDetails['booking'];
    if (bookingMap is Map) {
      final mutableBooking = Map<String, dynamic>.from(bookingMap);
      if (fields['payment_status'] != null)
        mutableBooking['payment_status'] = fields['payment_status'];
      if (fields['paymentStatus'] != null)
        mutableBooking['paymentStatus'] = fields['paymentStatus'];
      if (fields['paid_at'] != null)
        mutableBooking['paid_at'] = fields['paid_at'];
      if (fields['paidAt'] != null) mutableBooking['paidAt'] = fields['paidAt'];
      if (fields['payment_provider'] != null)
        mutableBooking['payment_provider'] = fields['payment_provider'];
      if (fields['paymentProvider'] != null)
        mutableBooking['paymentProvider'] = fields['paymentProvider'];
      if (fields['payment_id'] != null)
        mutableBooking['payment_id'] = fields['payment_id'];
      if (fields['paymentId'] != null)
        mutableBooking['paymentId'] = fields['paymentId'];
      if (fields['payment_method'] != null)
        mutableBooking['payment_method'] = fields['payment_method'];
      if (fields['paymentMethod'] != null)
        mutableBooking['paymentMethod'] = fields['paymentMethod'];
      if (fields['payment_source'] != null)
        mutableBooking['payment_source'] = fields['payment_source'];
      if (fields['paymentSource'] != null)
        mutableBooking['paymentSource'] = fields['paymentSource'];
      item.bookingDetails['booking'] = mutableBooking;
    }
  }

  void _appendPaymentUpdateLedgerIfPaid({
    required Map<String, dynamic> fields,
    required String method,
    required String source,
    bool? backendConfirmed,
  }) {
    if (!_isPaidPaymentUpdate(fields)) return;
    final record = _buildCompliancePaymentUpdateLedgerRecord(
      item: item,
      paymentFields: fields,
      method: method,
      source: source,
      eventAt: DateTime.now(),
      backendConfirmed: backendConfirmed,
    );
    unawaited(_writeComplianceLedgerRecord(record: record));
  }

  Map<String, dynamic>? _extractAuthoritativePaymentFields(
    Map<String, dynamic> root,
  ) {
    Map<String, dynamic> asMap(dynamic value) =>
        value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
    String? text(dynamic value) {
      final s = value?.toString().trim();
      if (s == null || s.isEmpty || s.toLowerCase() == 'null') return null;
      return s;
    }

    final data = asMap(root['data']);
    final record = asMap(root['record']);
    final booking = asMap(root['booking']);
    final recordBooking = asMap(record['booking']);
    final dataRecord = asMap(data['record']);
    final dataBooking = asMap(data['booking']);
    final dataRecordBooking = asMap(dataRecord['booking']);

    String? firstHit(String snake, String camel, Map<String, dynamic> map) {
      final hit = text(map[snake] ?? map[camel]);
      return hit;
    }

    final paymentStatus =
        firstHit('payment_status', 'paymentStatus', root) ??
        firstHit('payment_status', 'paymentStatus', record) ??
        firstHit('payment_status', 'paymentStatus', recordBooking) ??
        firstHit('payment_status', 'paymentStatus', booking) ??
        firstHit('payment_status', 'paymentStatus', data) ??
        firstHit('payment_status', 'paymentStatus', dataRecord) ??
        firstHit('payment_status', 'paymentStatus', dataBooking) ??
        firstHit('payment_status', 'paymentStatus', dataRecordBooking);
    final paidAt = text(
      root['paid_at'] ??
          root['paidAt'] ??
          record['paid_at'] ??
          record['paidAt'] ??
          recordBooking['paid_at'] ??
          recordBooking['paidAt'] ??
          booking['paid_at'] ??
          booking['paidAt'] ??
          data['paid_at'] ??
          data['paidAt'] ??
          dataRecord['paid_at'] ??
          dataRecord['paidAt'] ??
          dataBooking['paid_at'] ??
          dataBooking['paidAt'] ??
          dataRecordBooking['paid_at'] ??
          dataRecordBooking['paidAt'],
    );
    final paymentProvider = text(
      root['payment_provider'] ??
          root['paymentProvider'] ??
          record['payment_provider'] ??
          record['paymentProvider'] ??
          booking['payment_provider'] ??
          booking['paymentProvider'] ??
          data['payment_provider'] ??
          data['paymentProvider'] ??
          dataRecord['payment_provider'] ??
          dataRecord['paymentProvider'] ??
          dataBooking['payment_provider'] ??
          dataBooking['paymentProvider'],
    );
    final paymentId = text(
      root['payment_id'] ??
          root['paymentId'] ??
          record['payment_id'] ??
          record['paymentId'] ??
          booking['payment_id'] ??
          booking['paymentId'] ??
          data['payment_id'] ??
          data['paymentId'] ??
          dataRecord['payment_id'] ??
          dataRecord['paymentId'] ??
          dataBooking['payment_id'] ??
          dataBooking['paymentId'],
    );
    final paymentMethod = text(
      root['payment_method'] ??
          root['paymentMethod'] ??
          record['payment_method'] ??
          record['paymentMethod'] ??
          booking['payment_method'] ??
          booking['paymentMethod'] ??
          data['payment_method'] ??
          data['paymentMethod'] ??
          dataRecord['payment_method'] ??
          dataRecord['paymentMethod'] ??
          dataBooking['payment_method'] ??
          dataBooking['paymentMethod'],
    );
    final paymentSource = text(
      root['payment_source'] ??
          root['paymentSource'] ??
          record['payment_source'] ??
          record['paymentSource'] ??
          booking['payment_source'] ??
          booking['paymentSource'] ??
          data['payment_source'] ??
          data['paymentSource'] ??
          dataRecord['payment_source'] ??
          dataRecord['paymentSource'] ??
          dataBooking['payment_source'] ??
          dataBooking['paymentSource'],
    );

    if (paymentStatus == null &&
        paidAt == null &&
        paymentProvider == null &&
        paymentId == null &&
        paymentMethod == null &&
        paymentSource == null) {
      return null;
    }
    return <String, dynamic>{
      if (paymentStatus != null) ...{
        'payment_status': paymentStatus,
        'paymentStatus': paymentStatus,
      },
      if (paidAt != null) ...{'paid_at': paidAt, 'paidAt': paidAt},
      if (paymentProvider != null) ...{
        'payment_provider': paymentProvider,
        'paymentProvider': paymentProvider,
      },
      if (paymentId != null) ...{
        'payment_id': paymentId,
        'paymentId': paymentId,
      },
      if (paymentMethod != null) ...{
        'payment_method': paymentMethod,
        'paymentMethod': paymentMethod,
      },
      if (paymentSource != null) ...{
        'payment_source': paymentSource,
        'paymentSource': paymentSource,
      },
    };
  }

  String? _paymentMethodFromDetails() {
    return _firstDetailPathText(const [
      ['payment_method'],
      ['paymentMethod'],
      ['booking', 'payment_method'],
      ['booking', 'paymentMethod'],
      ['booking_details', 'payment_method'],
      ['booking_details', 'paymentMethod'],
      ['record', 'payment_method'],
      ['record', 'paymentMethod'],
      ['record', 'booking', 'payment_method'],
      ['record', 'booking', 'paymentMethod'],
    ])?.toLowerCase().trim();
  }

  String? _paymentSourceFromDetails() {
    return _firstDetailPathText(const [
      ['payment_source'],
      ['paymentSource'],
      ['booking', 'payment_source'],
      ['booking', 'paymentSource'],
      ['record', 'payment_source'],
      ['record', 'paymentSource'],
      ['record', 'booking', 'payment_source'],
      ['record', 'booking', 'paymentSource'],
    ])?.toLowerCase().trim();
  }

  bool _methodImpliesPaid(String? method) {
    final m = method?.toLowerCase().trim() ?? '';
    return m == 'cash' || m == 'bancontact' || m == 'qr' || m == 'card';
  }

  Future<Map<String, dynamic>?> _fetchAuthoritativePaymentFields(
    String bookingId,
  ) async {
    Map<String, dynamic> asMap(dynamic value) =>
        value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
    List<dynamic> asList(dynamic value) => value is List ? value : const [];
    try {
      final uri = _withActiveBookingScope(
        kBookingBaseUrl,
        '/bookings/${Uri.encodeComponent(bookingId)}',
      );
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (kAdminToken.trim().isNotEmpty) {
        headers['x-admin-token'] = kAdminToken.trim();
      }
      final res = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 12));
      Map<String, dynamic>? parsed;
      dynamic decoded;
      if (res.statusCode >= 200 && res.statusCode < 300) {
        decoded = jsonDecode(res.body);
        if (decoded is Map) {
          final root = Map<String, dynamic>.from(decoded);
          parsed = _extractAuthoritativePaymentFields(root);
          if (parsed == null || parsed.isEmpty) {
            for (final list in <List<dynamic>>[
              asList(root['items']),
              asList(asMap(root['data'])['items']),
              asList(root['bookings']),
              asList(asMap(root['data'])['bookings']),
            ]) {
              for (final raw in list) {
                final entry = asMap(raw);
                final entryBookingId =
                    (entry['booking_id'] ??
                            entry['bookingId'] ??
                            entry['id'] ??
                            '')
                        .toString()
                        .trim();
                if (entryBookingId != bookingId) continue;
                parsed = _extractAuthoritativePaymentFields(entry);
                if (parsed != null && parsed.isNotEmpty) break;
              }
              if (parsed != null && parsed.isNotEmpty) break;
            }
          }
        }
      }
      if (parsed != null && parsed.isNotEmpty) return parsed;

      final listUri = _withActiveBookingScope(
        kBookingBaseUrl,
        '/bookings',
        extraQuery: <String, String>{
          'limit': '200',
          't': '${DateTime.now().millisecondsSinceEpoch}',
        },
      );
      final listRes = await http
          .get(listUri, headers: headers)
          .timeout(const Duration(seconds: 12));
      Map<String, dynamic>? listParsed;
      if (listRes.statusCode >= 200 && listRes.statusCode < 300) {
        final listDecoded = jsonDecode(listRes.body);
        if (listDecoded is Map) {
          final root = Map<String, dynamic>.from(listDecoded);
          for (final list in <List<dynamic>>[
            asList(root['items']),
            asList(asMap(root['data'])['items']),
            asList(root['bookings']),
            asList(asMap(root['data'])['bookings']),
          ]) {
            for (final raw in list) {
              final entry = asMap(raw);
              final entryBookingId =
                  (entry['booking_id'] ??
                          entry['bookingId'] ??
                          entry['id'] ??
                          '')
                      .toString()
                      .trim();
              if (entryBookingId != bookingId) continue;
              listParsed = _extractAuthoritativePaymentFields(entry);
              if (listParsed != null && listParsed.isNotEmpty) break;
            }
            if (listParsed != null && listParsed.isNotEmpty) break;
          }
        }
      }
      if (listParsed != null && listParsed.isNotEmpty) return listParsed;
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _resolveReceiptPaymentStatus() async {
    final bookingId = (item.bookingId ?? '').trim();
    final historyPaymentStatus = _historyTopLevelPaymentStatus();
    final nestedPaymentStatus = _historyNestedPaymentStatus();

    String? authoritativePaymentStatus;
    String? authoritativePaymentMethod;
    if (bookingId.isNotEmpty) {
      final fields = await _fetchAuthoritativePaymentFields(bookingId);
      if (fields != null && fields.isNotEmpty) {
        _mergePaymentFieldsIntoReceiptDetails(fields);
        authoritativePaymentStatus =
            _mapText(fields, 'payment_status') ??
            _mapText(fields, 'paymentStatus');
        authoritativePaymentMethod =
            _mapText(fields, 'payment_method') ??
            _mapText(fields, 'paymentMethod');
      }
    }

    String? resolved = authoritativePaymentStatus;
    if (resolved != null && resolved.isNotEmpty) {
    } else if (historyPaymentStatus != null &&
        historyPaymentStatus.isNotEmpty) {
      resolved = historyPaymentStatus;
    } else if (nestedPaymentStatus != null && nestedPaymentStatus.isNotEmpty) {
      resolved = nestedPaymentStatus;
    }

    final methodFromDetails =
        authoritativePaymentMethod ?? _paymentMethodFromDetails();
    final sourceFromDetails = _paymentSourceFromDetails();
    final markAsPaidFromMethod =
        _methodImpliesPaid(methodFromDetails) &&
        (sourceFromDetails == null ||
            sourceFromDetails.isEmpty ||
            sourceFromDetails == 'in_car');
    if (!mounted) return;
    setState(() {
      final fromStatus = _paymentStatusFromRaw(resolved);
      _paymentStatus =
          markAsPaidFromMethod && fromStatus != _ReceiptPaymentStatus.paid
          ? _ReceiptPaymentStatus.paid
          : fromStatus;
    });
  }

  String? _cleanContactText(dynamic value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty || text == 'null') return null;
    return text;
  }

  dynamic _detailAt(List<String> path) {
    dynamic current = item.bookingDetails;
    for (final key in path) {
      if (current is Map && current.containsKey(key)) {
        current = current[key];
      } else {
        current = null;
        break;
      }
    }
    if (current != null) return current;
    return _rawAt(path);
  }

  dynamic _rawAt(List<String> path) {
    dynamic current = item.rawSource;
    for (final key in path) {
      if (current is Map && current.containsKey(key)) {
        current = current[key];
      } else {
        return null;
      }
    }
    return current;
  }

  String? _firstDetailPathText(List<List<String>> paths) {
    for (final path in paths) {
      final text = _cleanContactText(_detailAt(path));
      if (text != null) return text;
    }
    return null;
  }

  String? _firstDetailText(List<String> keys) {
    for (final key in keys) {
      final text = _detailText(key);
      if (text != null) return text;
    }
    return null;
  }

  double? _detailDouble(String key) {
    final value = item.bookingDetails[key];
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString().replaceAll(',', '.'));
  }

  double? _receiptTotalAmount() {
    if (_isPlannedReceipt) {
      return _detailDouble('booking_total_eur') ?? item.totalEur;
    }
    return item.totalEur;
  }

  String _moneyText(double? value) {
    if (value == null) return _receiptText('notAvailable');
    return '€ ${value.toStringAsFixed(2)}';
  }

  String _totalText() {
    return _moneyText(_receiptTotalAmount());
  }

  String _kmText() {
    final km = item.kmTotal;
    if (km == null) return _receiptText('notAvailable');
    return '${km.toStringAsFixed(2)} km';
  }

  bool _isPlaceholderRouteLabel(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return true;
    if (text == '-' || text == '—') return true;
    return text.toLowerCase() == _receiptText('currentLocation').toLowerCase();
  }

  ({String from, String to}) _resolvedRouteForPdf() {
    final normalizedFrom = _isPlaceholderRouteLabel(item.origin)
        ? null
        : item.origin.trim();
    final normalizedTo = _isPlaceholderRouteLabel(item.destination)
        ? null
        : item.destination.trim();

    String? pickLabel(List<List<String>> paths) {
      for (final path in paths) {
        final text = _cleanContactText(_detailAt(path));
        if (!_isPlaceholderRouteLabel(text)) return text;
      }
      return null;
    }

    final rawFrom = pickLabel(const [
      ['from'],
      ['pickup'],
      ['pickup_address'],
      ['pickupAddress'],
      ['pickupLocation'],
      ['pickup_location'],
      ['origin'],
      ['start_address'],
      ['startAddress'],
      ['booking', 'from'],
      ['booking', 'pickup'],
      ['booking', 'pickup_address'],
      ['booking', 'pickupAddress'],
      ['record', 'from'],
      ['record', 'booking', 'from'],
      ['record', 'booking', 'pickup'],
      ['payload', 'from'],
      ['payload', 'booking', 'from'],
      ['quote', 'inputs', 'from'],
    ]);
    final rawTo = pickLabel(const [
      ['to'],
      ['destination'],
      ['destination_address'],
      ['destinationAddress'],
      ['dropoff'],
      ['dropoff_address'],
      ['dropoffAddress'],
      ['end_address'],
      ['endAddress'],
      ['booking', 'to'],
      ['booking', 'destination'],
      ['booking', 'destination_address'],
      ['booking', 'destinationAddress'],
      ['record', 'to'],
      ['record', 'booking', 'to'],
      ['record', 'booking', 'destination'],
      ['payload', 'to'],
      ['payload', 'booking', 'to'],
      ['quote', 'inputs', 'to'],
    ]);

    final from = _sanitizeCustomerFacingRouteLabel(
      normalizedFrom ?? rawFrom ?? _receiptText('currentLocation'),
      isFromField: true,
    );
    final to = _sanitizeCustomerFacingRouteLabel(
      normalizedTo ?? rawTo ?? '-',
      isFromField: false,
    );
    final source = (normalizedFrom != null || normalizedTo != null)
        ? 'normalized'
        : ((rawFrom != null || rawTo != null) ? 'raw' : 'fallback');
    debugPrint(
      '[PDF][ROUTE] fromFound=${from != _receiptText('currentLocation')} toFound=${to != '-'} source=$source',
    );
    return (from: from, to: to);
  }

  ({
    String? name,
    String? phoneRaw,
    String? email,
    List<String> keys,
    String source,
  })
  _resolvePdfContact() {
    String? pick(
      List<List<String>> paths,
      List<String> usedKeys, {
      bool email = false,
    }) {
      for (final path in paths) {
        final text = _cleanContactText(_detailAt(path));
        if (text == null || text.isEmpty) continue;
        final normalized = email ? _validEmail(text) : text;
        if (normalized == null || normalized.isEmpty) continue;
        usedKeys.add(path.join('.'));
        return normalized;
      }
      return null;
    }

    final keys = <String>[];
    final normalizedName = _cleanContactText(item.customerName);
    final normalizedPhone = _cleanContactText(item.customerPhone);
    final normalizedEmail = _validEmail(item.customerEmail);
    if (normalizedName != null) keys.add('normalized.customerName');
    if (normalizedPhone != null) keys.add('normalized.customerPhone');
    if (normalizedEmail != null) keys.add('normalized.customerEmail');

    final hasNormalized =
        normalizedName != null ||
        normalizedPhone != null ||
        normalizedEmail != null;
    if (hasNormalized) {
      return (
        name: normalizedName,
        phoneRaw: normalizedPhone,
        email: normalizedEmail,
        keys: keys,
        source: 'normalized',
      );
    }

    final name = pick(const [
      ['customer', 'name'],
      ['customer_name'],
      ['customerName'],
      ['custName'],
      ['name'],
      ['booking', 'customer', 'name'],
      ['booking', 'customer_name'],
      ['booking', 'customerName'],
      ['booking', 'custName'],
      ['booking', 'name'],
      ['record', 'customer_name'],
      ['record', 'booking', 'customer_name'],
      ['record', 'booking', 'customerName'],
      ['payload', 'customer_name'],
      ['payload', 'booking', 'customer_name'],
      ['record', 'payload', 'customer_name'],
      ['record', 'payload', 'customerName'],
      ['record', 'payload', 'custName'],
      ['record', 'payload', 'name'],
      ['record', 'payload', 'booking', 'customer_name'],
      ['record', 'payload', 'booking', 'customerName'],
      ['record', 'payload', 'booking', 'custName'],
      ['record', 'payload', 'booking', 'name'],
    ], keys);

    final phoneRaw = pick(const [
      ['customer', 'phone'],
      ['customer_phone'],
      ['customerPhone'],
      ['custPhone'],
      ['phone'],
      ['tel'],
      ['mobile'],
      ['booking', 'customer', 'phone'],
      ['booking', 'customer_phone'],
      ['booking', 'customerPhone'],
      ['booking', 'custPhone'],
      ['booking', 'phone'],
      ['booking', 'tel'],
      ['booking', 'mobile'],
      ['record', 'customer_phone'],
      ['record', 'booking', 'customer_phone'],
      ['record', 'booking', 'customerPhone'],
      ['record', 'booking', 'custPhone'],
      ['payload', 'customer_phone'],
      ['payload', 'booking', 'customer_phone'],
      ['record', 'payload', 'customer_phone'],
      ['record', 'payload', 'customerPhone'],
      ['record', 'payload', 'custPhone'],
      ['record', 'payload', 'phone'],
      ['record', 'payload', 'tel'],
      ['record', 'payload', 'mobile'],
      ['record', 'payload', 'booking', 'customer_phone'],
      ['record', 'payload', 'booking', 'customerPhone'],
      ['record', 'payload', 'booking', 'custPhone'],
      ['record', 'payload', 'booking', 'phone'],
    ], keys);

    final email = pick(
      const [
        ['customer', 'email'],
        ['customer_email'],
        ['customerEmail'],
        ['custEmail'],
        ['email'],
        ['invoice_email'],
        ['invoiceEmail'],
        ['booking', 'customer', 'email'],
        ['booking', 'customer_email'],
        ['booking', 'customerEmail'],
        ['booking', 'custEmail'],
        ['booking', 'email'],
        ['booking', 'invoice_email'],
        ['booking', 'invoiceEmail'],
        ['record', 'customer_email'],
        ['record', 'booking', 'customer_email'],
        ['record', 'booking', 'customerEmail'],
        ['record', 'booking', 'custEmail'],
        ['payload', 'customer_email'],
        ['payload', 'booking', 'customer_email'],
        ['record', 'payload', 'customer_email'],
        ['record', 'payload', 'customerEmail'],
        ['record', 'payload', 'custEmail'],
        ['record', 'payload', 'email'],
        ['record', 'payload', 'invoice_email'],
        ['record', 'payload', 'invoiceEmail'],
        ['record', 'payload', 'booking', 'customer_email'],
        ['record', 'payload', 'booking', 'customerEmail'],
        ['record', 'payload', 'booking', 'custEmail'],
        ['record', 'payload', 'booking', 'email'],
        ['record', 'payload', 'booking', 'invoice_email'],
        ['record', 'payload', 'booking', 'invoiceEmail'],
      ],
      keys,
      email: true,
    );

    final hasRaw = name != null || phoneRaw != null || email != null;
    return (
      name: name,
      phoneRaw: phoneRaw,
      email: email,
      keys: keys,
      source: hasRaw ? 'raw' : 'none',
    );
  }

  void _logPdfContactResolution() {
    final resolved = _resolvePdfContact();
    final keyList = resolved.keys.join(',');
    debugPrint(
      '[PDF][CONTACT] emailFound=${resolved.email != null} phoneFound=${resolved.phoneRaw != null} source=${resolved.source} keys=$keyList',
    );
  }

  String? get _customerName => _resolvePdfContact().name;

  String? get _customerPhoneRaw => _resolvePdfContact().phoneRaw;

  String? get _customerEmail => _resolvePdfContact().email;

  String? get _customerCountryContext =>
      _firstDetailText([
        'phone_country_code',
        'phoneCountryCode',
        'dial_code',
        'dialCode',
        'customer_country',
        'customerCountry',
        'country',
        'countryCode',
        'country_iso',
        'countryIso',
        'locale',
        'language',
      ]) ??
      _tenantDefaultCountryIso();

  String? _tenantDefaultCountryIso() {
    // Tenant-level fallback only. Future white-label tenants should move this into tenant config.
    if (kTenantId.toLowerCase().trim() == 'fluxidi') return 'BE';
    return null;
  }

  String? get _customerPhoneE164 => _normalizePhoneForWhatsApp(
    _customerPhoneRaw,
    countryContext: _customerCountryContext,
  );

  bool get _hasAnyRawCustomerContact =>
      (_customerName?.trim().isNotEmpty ?? false) ||
      (_customerPhoneRaw?.trim().isNotEmpty ?? false) ||
      (_customerEmail?.trim().isNotEmpty ?? false);

  String _maskEmailForLog(String? value) {
    final email = value?.trim();
    if (email == null || email.isEmpty) return '-';
    final at = email.indexOf('@');
    if (at <= 0) return '***';
    final first = email.substring(0, 1);
    return '$first***${email.substring(at)}';
  }

  String _maskPhoneForLog(String? value) {
    final digits = value?.replaceAll(RegExp(r'\D'), '') ?? '';
    if (digits.isEmpty) return '-';
    final suffix = digits.length <= 2
        ? digits
        : digits.substring(digits.length - 2);
    return '***$suffix';
  }

  void _debugReceiptContactState(String label, {String? emailOverride}) {
    if (!kDebugMode) return;
    debugPrint(
      '[RITBON][CONTACT][$label] '
      'nameFound=${_customerName != null} '
      'emailFound=${(emailOverride ?? _customerEmail) != null} '
      'phoneFound=${_customerPhoneE164 != null} '
      'keys=${item.bookingDetails.keys.where((key) => key.toLowerCase().contains('customer') || key.toLowerCase().contains('phone') || key.toLowerCase().contains('email')).join(',')}',
    );
  }

  String? _validEmail(String? value) {
    final email = value?.trim();
    if (email == null || email.isEmpty) return null;
    final at = email.indexOf('@');
    if (at <= 0 || at >= email.length - 1) return null;
    final dotAfterAt = email.indexOf('.', at + 1);
    if (dotAfterAt <= at + 1 || dotAfterAt >= email.length - 1) return null;
    if (email.contains(RegExp(r'\s'))) return null;
    return email;
  }

  // MVP E.164-like normalizer. Replace/enhance with libphonenumber-style validation later.
  String? _normalizePhoneForWhatsApp(String? raw, {String? countryContext}) {
    final input = raw?.trim();
    if (input == null || input.isEmpty) return null;
    var cleaned = input.replaceAll(RegExp(r'[\s\-\(\)\/\.]'), '');
    if (cleaned.startsWith('00')) cleaned = '+${cleaned.substring(2)}';
    if (cleaned.startsWith('+')) {
      final digits = cleaned.substring(1).replaceAll(RegExp(r'\D'), '');
      if (digits.length < 8 || digits.length > 15) return null;
      return '+$digits';
    }

    final digits = cleaned.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 6) return null;
    final iso = _countryIsoFromContext(countryContext);
    if (iso == null) return null;
    final dial = _dialCodeForIso(iso);
    if (dial == null) return null;

    String? national;
    switch (iso) {
      case 'BE':
      case 'NL':
      case 'FR':
      case 'DE':
      case 'GB':
      case 'CH':
      case 'AT':
      case 'IE':
        if (!digits.startsWith('0')) return null;
        national = digits.replaceFirst(RegExp(r'^0+'), '');
        break;
      case 'ES':
        if (digits.length != 9 || digits.startsWith('0')) return null;
        national = digits;
        break;
      case 'US':
      case 'CA':
        if (digits.length != 10) return null;
        national = digits;
        break;
      case 'LU':
        if (digits.length < 6 || digits.length > 9) return null;
        national = digits.replaceFirst(RegExp(r'^0+'), '');
        break;
      case 'IT':
      case 'PT':
        if (digits.length < 8 || digits.length > 10) return null;
        national = digits.replaceFirst(RegExp(r'^0+'), '');
        break;
      default:
        return null;
    }
    final normalized = '$dial$national';
    final normalizedDigits = normalized.replaceAll(RegExp(r'\D'), '');
    if (normalizedDigits.length < 8 || normalizedDigits.length > 15)
      return null;
    return normalized;
  }

  String? _countryIsoFromContext(String? context) {
    final raw = context?.trim();
    if (raw == null || raw.isEmpty) return null;
    final lower = raw.toLowerCase();
    if (lower.startsWith('+')) return _isoFromDialCode(lower);
    if (RegExp(r'^\d+$').hasMatch(lower)) return _isoFromDialCode('+$lower');
    final localePart = lower.contains('_') || lower.contains('-')
        ? lower.split(RegExp(r'[_-]')).last
        : lower;
    final c = localePart
        .replaceAll('ë', 'e')
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ï', 'i')
        .replaceAll('ä', 'a')
        .replaceAll('ö', 'o')
        .replaceAll('ü', 'u')
        .replaceAll('ç', 'c')
        .trim();
    const aliases = <String, String>{
      'be': 'BE',
      'belgium': 'BE',
      'belgie': 'BE',
      'belgique': 'BE',
      'belgien': 'BE',
      'nl': 'NL',
      'netherlands': 'NL',
      'nederland': 'NL',
      'pays bas': 'NL',
      'fr': 'FR',
      'france': 'FR',
      'frankrijk': 'FR',
      'es': 'ES',
      'spain': 'ES',
      'spanje': 'ES',
      'espagne': 'ES',
      'espana': 'ES',
      'us': 'US',
      'usa': 'US',
      'united states': 'US',
      'america': 'US',
      'ca': 'CA',
      'canada': 'CA',
      'gb': 'GB',
      'uk': 'GB',
      'united kingdom': 'GB',
      'great britain': 'GB',
      'de': 'DE',
      'germany': 'DE',
      'duitsland': 'DE',
      'allemagne': 'DE',
      'deutschland': 'DE',
      'lu': 'LU',
      'luxembourg': 'LU',
      'luxemburg': 'LU',
      'it': 'IT',
      'italy': 'IT',
      'italie': 'IT',
      'italia': 'IT',
      'pt': 'PT',
      'portugal': 'PT',
      'ch': 'CH',
      'switzerland': 'CH',
      'suisse': 'CH',
      'zwitserland': 'CH',
      'at': 'AT',
      'austria': 'AT',
      'oostenrijk': 'AT',
      'autriche': 'AT',
      'ie': 'IE',
      'ireland': 'IE',
    };
    return aliases[c] ?? aliases[lower];
  }

  String? _isoFromDialCode(String dial) {
    const map = <String, String>{
      '+32': 'BE',
      '+31': 'NL',
      '+33': 'FR',
      '+34': 'ES',
      '+1': 'US',
      '+44': 'GB',
      '+49': 'DE',
      '+352': 'LU',
      '+39': 'IT',
      '+351': 'PT',
      '+41': 'CH',
      '+43': 'AT',
      '+353': 'IE',
    };
    return map[dial];
  }

  String? _dialCodeForIso(String iso) {
    const map = <String, String>{
      'BE': '+32',
      'NL': '+31',
      'FR': '+33',
      'ES': '+34',
      'US': '+1',
      'CA': '+1',
      'GB': '+44',
      'DE': '+49',
      'LU': '+352',
      'IT': '+39',
      'PT': '+351',
      'CH': '+41',
      'AT': '+43',
      'IE': '+353',
    };
    return map[iso];
  }

  String? _displayToken(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return null;
    final normalized = text.replaceAll('_', ' ').replaceAll('-', ' ');
    return normalized
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .map(
          (part) => part.length == 1
              ? part.toUpperCase()
              : '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  String _displayServiceToken(String? value) {
    final raw = value?.trim() ?? '';
    final normalized = raw
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_')
        .trim();
    if (normalized == 'passenger' ||
        normalized == 'personenvervoer' ||
        normalized == 'passenger_transport') {
      return _receiptText('passengerTransport');
    }
    if (normalized == 'business' || normalized == 'zakelijk') {
      return _receiptText('businessRide');
    }
    if (normalized == 'airport' ||
        normalized == 'luchthaven' ||
        normalized == 'airport_transfer') {
      return _receiptText('airportTransfer');
    }
    return _displayToken(value) ?? '—';
  }

  String _displayTierToken(String? value) {
    final raw = value?.trim() ?? '';
    final normalized = raw.toLowerCase().replaceAll('-', '_').trim();
    if (normalized == 'comfort') return _receiptText('tierComfort');
    if (normalized == 'private') return _receiptText('tierPrivate');
    if (normalized == 'premium') return _receiptText('tierPremium');
    return _displayToken(value) ?? '—';
  }

  String? _displayExtraValue(dynamic raw) {
    if (raw == null) return null;
    if (raw is String) {
      final token = _displayToken(raw);
      return token == null || token == '—' ? null : token;
    }
    if (raw is List) {
      final values = raw
          .map(_displayExtraValue)
          .whereType<String>()
          .where((value) => value.trim().isNotEmpty)
          .toList(growable: false);
      if (values.isEmpty) return null;
      return values.join(', ');
    }
    if (raw is Map) {
      final values = <String>[];
      raw.forEach((key, value) {
        final include =
            value == true ||
            value == 1 ||
            value?.toString().toLowerCase().trim() == 'true' ||
            value?.toString().trim() == '1';
        if (!include) return;
        final label = _displayToken(key.toString());
        if (label != null && label != '—') values.add(label);
      });
      if (values.isEmpty) return null;
      return values.join(', ');
    }
    return null;
  }

  String? _plannedExtrasText() {
    const paths = <List<String>>[
      ['extras'],
      ['extra_service'],
      ['extra_service_key'],
      ['selected_options'],
      ['premium_options'],
      ['booking', 'extras'],
      ['booking', 'extra_service'],
      ['booking', 'extra_service_key'],
      ['booking', 'selected_options'],
      ['booking', 'premium_options'],
      ['record', 'payload', 'extras'],
      ['record', 'payload', 'extra_service'],
      ['record', 'payload', 'extra_service_key'],
      ['record', 'payload', 'selected_options'],
      ['record', 'payload', 'premium_options'],
      ['record', 'payload', 'booking', 'extras'],
      ['record', 'payload', 'booking', 'extra_service'],
      ['record', 'payload', 'booking', 'extra_service_key'],
      ['record', 'payload', 'booking', 'selected_options'],
      ['record', 'payload', 'booking', 'premium_options'],
    ];
    for (final path in paths) {
      final text = _displayExtraValue(_detailAt(path));
      if (text != null && text.trim().isNotEmpty) return text;
    }
    return null;
  }

  bool _sameMoney(double? a, double? b) {
    if (a == null || b == null) return false;
    return (a - b).abs() < 0.005;
  }

  bool get _hasReturnPriceSplit {
    final outbound = _detailDouble('outbound_price_eur');
    final ret = _detailDouble('return_price_eur');
    return outbound != null &&
        ret != null &&
        ret > 0 &&
        !_sameMoney(outbound, ret);
  }

  bool get _hasReturnBookingInfo =>
      _detailText('return_scheduled_pickup_at') != null ||
      _detailText('return_route') != null ||
      _hasReturnPriceSplit ||
      (item.bookingId ?? '').endsWith('-R');

  List<Widget> _plannedPriceRows() {
    final package = _detailDouble('booking_total_eur');
    final segment = _detailDouble('segment_price_eur');
    final outbound = _detailDouble('outbound_price_eur');
    final ret = _detailDouble('return_price_eur');
    final rows = <Widget>[];

    if (_hasReturnBookingInfo && (outbound != null || ret != null)) {
      if (package != null &&
          !_sameMoney(package, outbound) &&
          !_sameMoney(package, ret)) {
        rows.add(
          _receiptRow(_receiptText('packagePrice'), _moneyText(package)),
        );
      }
      if (outbound != null) {
        rows.add(
          _receiptRow(_receiptText('outboundPrice'), _moneyText(outbound)),
        );
      }
      if (ret != null && !_sameMoney(ret, outbound)) {
        rows.add(_receiptRow(_receiptText('returnPrice'), _moneyText(ret)));
      }
      if (segment != null &&
          !_sameMoney(segment, package) &&
          !_sameMoney(segment, outbound) &&
          !_sameMoney(segment, ret)) {
        rows.add(_receiptRow(_receiptText('ridePrice'), _moneyText(segment)));
      }
      return rows;
    }

    final single = segment ?? outbound ?? package;
    if (single != null) {
      rows.add(_receiptRow(_receiptText('fixedPrice'), _moneyText(single)));
    }
    return rows;
  }

  String _shareText() {
    return _receiptCustomerMessage();
  }

  String get _customerReference {
    return _businessReferenceDisplayForItem(
      item,
      source: 'receipt_body_customer_reference',
    ).value;
  }

  String _localizedPaymentMethodValue(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return _receiptText('notAvailable');
    final normalized = value
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
    switch (normalized) {
      case 'cash':
        return _tr(nl: 'Contant', en: 'Cash', fr: 'Espèces', es: 'Efectivo');
      case 'bancontact':
        return _tr(
          nl: 'Bancontact',
          en: 'Bancontact',
          fr: 'Bancontact',
          es: 'Bancontact',
        );
      case 'card':
        return _tr(nl: 'Kaart', en: 'Card', fr: 'Carte', es: 'Tarjeta');
      case 'qr':
      case 'qr_code':
        return _tr(
          nl: 'QR-code',
          en: 'QR code',
          fr: 'Code QR',
          es: 'Código QR',
        );
      case 'mollie':
        return _tr(
          nl: 'Online betaling',
          en: 'Online payment',
          fr: 'Paiement en ligne',
          es: 'Pago en línea',
        );
      default:
        return _displayToken(value) ?? value.replaceAll('_', ' ');
    }
  }

  String _localizedPaymentSourceValue(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return _receiptText('notAvailable');
    final normalized = value
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
    switch (normalized) {
      case 'in_car':
        return _tr(
          nl: 'In de wagen',
          en: 'In vehicle',
          fr: 'Dans le véhicule',
          es: 'En el vehículo',
        );
      case 'payment_link':
        return _tr(
          nl: 'Betaallink',
          en: 'Payment link',
          fr: 'Lien de paiement',
          es: 'Enlace de pago',
        );
      case 'mollie':
        return _tr(nl: 'Mollie', en: 'Mollie', fr: 'Mollie', es: 'Mollie');
      default:
        return _displayToken(value) ?? value.replaceAll('_', ' ');
    }
  }

  String _receiptCustomerMessage() {
    final route = _resolvedRouteForPdf();
    final lines = <String>[
      '${_receiptText('receiptFrom')} $kCompanyName',
      '${_receiptText('type')}: ${item.kindLabel}',
      '${_receiptText('reference')}: $_customerReference',
      '${_receiptText('from')}: ${route.from}',
      '${_receiptText('to')}: ${route.to}',
      if (_detailText('scheduled_pickup_at') != null)
        '${_receiptText('scheduledPickup')}: ${_formatDate(_detailText('scheduled_pickup_at'))}',
      if (item.startedAt?.trim().isNotEmpty ?? false)
        '${_receiptText('startTime')}: ${_formatDate(item.startedAt)}',
      if (item.stoppedAt?.trim().isNotEmpty ?? false)
        '${_receiptText('endTime')}: ${_formatDate(item.stoppedAt)}',
      '${_receiptText('distance')}: ${_kmText()}',
      '${_receiptText('total')}: ${_totalText()}',
      '${_receiptText('paymentStatus')}: ${_paymentStatusText()}',
      '',
      _receiptText('thanksRide'),
    ];
    return lines.join('\n');
  }

  String _paymentStatusText() {
    switch (_paymentStatus) {
      case _ReceiptPaymentStatus.pending:
        return _receiptText('unpaid');
      case _ReceiptPaymentStatus.sent:
        return _receiptText('paymentSent');
      case _ReceiptPaymentStatus.paid:
        return _receiptText('paid');
    }
  }

  String _paymentLink() {
    final amount = _receiptTotalAmount() ?? 0.0;
    return Uri(
      scheme: 'fluxidi',
      host: 'pay',
      queryParameters: <String, String>{
        'ref': _customerReference,
        'amount': amount.toStringAsFixed(2),
        'currency': item.currency,
        'memo':
            '$kCompanyName ${_receiptText('receiptTitle')} $_customerReference',
      },
    ).toString();
  }

  void _markPaymentRequestSent() {
    if (_paymentStatus == _ReceiptPaymentStatus.pending) {
      setState(() => _paymentStatus = _ReceiptPaymentStatus.sent);
    }
  }

  Future<void> _copyPaymentLink(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: _paymentLink()));
    _markPaymentRequestSent();
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_receiptText('paymentLinkCopied'))));
  }

  Future<void> _openWhatsApp(
    BuildContext context, {
    required String phoneE164,
    required String message,
  }) async {
    final digits = phoneE164.replaceAll(RegExp(r'\D'), '');
    final uri = Uri.https('wa.me', '/$digits', <String, String>{
      'text': message,
    });
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_receiptText('whatsappOpenFailed'))),
      );
    }
  }

  Future<void> _openEmail(
    BuildContext context, {
    required String email,
    required String subject,
    required String body,
  }) async {
    final recipient = email.trim();
    final encodedSubject = Uri.encodeComponent(subject);
    final encodedBody = Uri.encodeComponent(body);
    final uri = Uri.parse(
      recipient.isNotEmpty
          ? 'mailto:${Uri.encodeComponent(recipient)}?subject=$encodedSubject&body=$encodedBody'
          : 'mailto:?subject=$encodedSubject&body=$encodedBody',
    );
    _debugReceiptContactState(
      'email_open',
      emailOverride: recipient.isNotEmpty ? recipient : null,
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_receiptText('emailOpenFailed'))));
    }
  }

  Future<void> _sendReceiptWhatsApp(BuildContext context) async {
    final phone = _customerPhoneE164;
    final contactSource = _resolvePdfContact().source;
    debugPrint(
      '[PDF][ACTION][WHATSAPP_TEXT] phoneFound=${phone != null} source=$contactSource',
    );
    if (phone == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_receiptText('noValidWhatsappPhone'))),
      );
      return;
    }
    final message = _tr(
      nl: 'Beste klant, uw betaalbewijs/ritbon is klaar. Ik stuur de PDF zo meteen door.',
      en: 'Dear customer, your ride receipt is ready. I will send the PDF shortly.',
      fr: 'Cher client, votre reçu de course est prêt. Je vais envoyer le PDF dans un instant.',
      es: 'Estimado cliente, su comprobante de viaje está listo. Enviaré el PDF en un momento.',
    );
    await _openWhatsApp(context, phoneE164: phone, message: message);
  }

  Future<void> _emailReceiptGeneric(BuildContext context) async {
    await _openEmail(
      context,
      email: _customerEmail ?? '',
      subject: _receiptText('receiptEmailSubject'),
      body: _receiptCustomerMessage(),
    );
  }

  bool _toBoolFlag(String? value) {
    final normalized = value?.toLowerCase().trim() ?? '';
    return normalized == '1' ||
        normalized == 'true' ||
        normalized == 'yes' ||
        normalized == 'ja';
  }

  ({
    bool isBusinessDocument,
    bool invoiceRequested,
    String companyName,
    String vatNumber,
    String invoiceEmail,
    String invoiceAddress,
  })
  _resolvedReceiptBusinessFields() {
    final invoiceRequested = _toBoolFlag(
      _firstDetailPathText(const [
        ['invoice_requested'],
        ['invoiceRequested'],
        ['booking', 'invoice_requested'],
        ['booking', 'invoiceRequested'],
        ['booking_details', 'invoice_requested'],
        ['booking_details', 'invoiceRequested'],
        ['record', 'invoice_requested'],
        ['record', 'invoiceRequested'],
        ['record', 'booking', 'invoice_requested'],
        ['record', 'booking', 'invoiceRequested'],
        ['record', 'booking_details', 'invoice_requested'],
        ['record', 'booking_details', 'invoiceRequested'],
        ['payload', 'invoice_requested'],
        ['payload', 'invoiceRequested'],
        ['payload', 'booking', 'invoice_requested'],
        ['payload', 'booking', 'invoiceRequested'],
      ]),
    );
    final businessFlag = _toBoolFlag(
      _firstDetailPathText(const [
        ['business_customer'],
        ['businessCustomer'],
        ['is_business'],
        ['isBusiness'],
        ['business_detected'],
        ['businessDetected'],
        ['booking', 'business_customer'],
        ['booking', 'businessCustomer'],
        ['booking', 'is_business'],
        ['booking', 'isBusiness'],
        ['booking', 'business_detected'],
        ['booking', 'businessDetected'],
        ['booking_details', 'business_customer'],
        ['booking_details', 'businessCustomer'],
        ['booking_details', 'is_business'],
        ['booking_details', 'isBusiness'],
        ['record', 'business_customer'],
        ['record', 'businessCustomer'],
        ['record', 'is_business'],
        ['record', 'isBusiness'],
        ['record', 'business_detected'],
        ['record', 'businessDetected'],
        ['record', 'booking', 'business_customer'],
        ['record', 'booking', 'businessCustomer'],
        ['record', 'booking', 'is_business'],
        ['record', 'booking', 'isBusiness'],
        ['record', 'booking', 'business_detected'],
        ['record', 'booking', 'businessDetected'],
      ]),
    );
    final customerCompany = _firstDetailPathText(const [
      ['company_name'],
      ['companyName'],
      ['customer_company'],
      ['customerCompany'],
      ['booking', 'company_name'],
      ['booking', 'companyName'],
      ['booking_details', 'company_name'],
      ['booking_details', 'companyName'],
      ['record', 'company_name'],
      ['record', 'companyName'],
      ['record', 'booking', 'company_name'],
      ['record', 'booking', 'companyName'],
      ['record', 'booking_details', 'company_name'],
      ['record', 'booking_details', 'companyName'],
      ['payload', 'company_name'],
      ['payload', 'companyName'],
      ['payload', 'booking', 'company_name'],
      ['payload', 'booking', 'companyName'],
    ]);
    final customerVat = _firstDetailPathText(const [
      ['vat_number'],
      ['vatNumber'],
      ['customer_vat'],
      ['customerVat'],
      ['booking', 'vat_number'],
      ['booking', 'vatNumber'],
      ['booking_details', 'vat_number'],
      ['booking_details', 'vatNumber'],
      ['record', 'vat_number'],
      ['record', 'vatNumber'],
      ['record', 'booking', 'vat_number'],
      ['record', 'booking', 'vatNumber'],
      ['record', 'booking_details', 'vat_number'],
      ['record', 'booking_details', 'vatNumber'],
      ['payload', 'vat_number'],
      ['payload', 'vatNumber'],
      ['payload', 'booking', 'vat_number'],
      ['payload', 'booking', 'vatNumber'],
    ]);
    final invoiceEmail =
        _firstDetailPathText(const [
          ['invoice_email'],
          ['invoiceEmail'],
          ['booking', 'invoice_email'],
          ['booking', 'invoiceEmail'],
          ['booking_details', 'invoice_email'],
          ['booking_details', 'invoiceEmail'],
          ['record', 'invoice_email'],
          ['record', 'invoiceEmail'],
          ['record', 'booking', 'invoice_email'],
          ['record', 'booking', 'invoiceEmail'],
          ['record', 'booking_details', 'invoice_email'],
          ['record', 'booking_details', 'invoiceEmail'],
          ['payload', 'invoice_email'],
          ['payload', 'invoiceEmail'],
          ['payload', 'booking', 'invoice_email'],
          ['payload', 'booking', 'invoiceEmail'],
        ]) ??
        '';
    final invoiceAddress =
        _firstDetailPathText(const [
          ['invoice_address'],
          ['invoiceAddress'],
          ['billing_address'],
          ['billingAddress'],
          ['company_address'],
          ['companyAddress'],
          ['booking', 'invoice_address'],
          ['booking', 'invoiceAddress'],
          ['booking', 'billing_address'],
          ['booking', 'billingAddress'],
          ['booking_details', 'invoice_address'],
          ['booking_details', 'invoiceAddress'],
          ['record', 'invoice_address'],
          ['record', 'invoiceAddress'],
          ['record', 'billing_address'],
          ['record', 'billingAddress'],
          ['record', 'booking', 'invoice_address'],
          ['record', 'booking', 'invoiceAddress'],
          ['record', 'booking_details', 'invoice_address'],
          ['record', 'booking_details', 'invoiceAddress'],
          ['payload', 'invoice_address'],
          ['payload', 'invoiceAddress'],
          ['payload', 'booking', 'invoice_address'],
          ['payload', 'booking', 'invoiceAddress'],
        ]) ??
        '';
    final hasBusiness =
        invoiceRequested ||
        businessFlag ||
        (customerCompany != null && customerCompany.trim().isNotEmpty) ||
        (customerVat != null && customerVat.trim().isNotEmpty);
    return (
      isBusinessDocument: hasBusiness,
      invoiceRequested: invoiceRequested,
      companyName: (customerCompany ?? '').trim(),
      vatNumber: (customerVat ?? '').trim(),
      invoiceEmail: invoiceEmail.trim(),
      invoiceAddress: invoiceAddress.trim(),
    );
  }

  bool get _isBusinessDocument {
    return _resolvedReceiptBusinessFields().isBusinessDocument;
  }

  double _resolvedVatRate() {
    final settingsVatRate = businessSettingsNotifier.value.pricingVatRate;
    final candidates = <double?>[
      _detailDouble('vat_rate'),
      _detailDouble('vatRate'),
      _detailDouble('booking_vat_rate'),
      _detailDouble('bookingVatRate'),
    ];
    for (final candidate in candidates) {
      if (candidate == null || !candidate.isFinite) continue;
      if (candidate > 1.0) return candidate / 100.0;
      if (candidate >= 0.0) return candidate;
    }
    return settingsVatRate.clamp(0.0, 1.0);
  }

  ({double subtotal, double vatAmount, double total, double vatRate})
  _resolvedReceiptAmounts() {
    final vatRate = _resolvedVatRate();
    final total =
        _receiptTotalAmount() ??
        _detailDouble('total') ??
        _detailDouble('booking_total_eur') ??
        0.0;
    final subtotalCandidate =
        _detailDouble('subtotal_ex_vat') ??
        _detailDouble('subtotalExVat') ??
        _detailDouble('price_ex_vat') ??
        _detailDouble('priceExVat');
    final vatAmountCandidate =
        _detailDouble('vat_amount') ??
        _detailDouble('vatAmount') ??
        _detailDouble('price_vat') ??
        _detailDouble('priceVat');

    final subtotal =
        subtotalCandidate ?? (vatRate > 0 ? (total / (1.0 + vatRate)) : total);
    final vatAmount = vatAmountCandidate ?? (total - subtotal);
    return (
      subtotal: subtotal.isFinite ? subtotal : 0.0,
      vatAmount: vatAmount.isFinite ? vatAmount : 0.0,
      total: total.isFinite ? total : 0.0,
      vatRate: vatRate.isFinite ? vatRate : 0.0,
    );
  }

  String _sanitizeFilePart(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    return cleaned.isEmpty ? 'receipt' : cleaned;
  }

  Future<Uint8List?> _loadReceiptLogoBytes(String? preferredPath) async {
    final candidates = <String>[
      if (preferredPath != null && preferredPath.trim().isNotEmpty)
        preferredPath.trim(),
      kFluxidiLogoAsset,
    ];
    for (final candidate in candidates) {
      try {
        if (candidate.startsWith('assets/')) {
          final data = await rootBundle.load(candidate);
          return data.buffer.asUint8List();
        }
        final f = File(candidate);
        if (await f.exists()) {
          return await f.readAsBytes();
        }
      } catch (_) {
        // Ignore and try next candidate.
      }
    }
    return null;
  }

  Future<Map<String, String>> _buildSellerProfile() async {
    final settings = businessSettingsNotifier.value;
    BackendBusinessProfile? backendProfile;
    try {
      backendProfile = await fetchBackendBusinessProfile();
    } catch (_) {
      backendProfile = null;
    }

    final profile =
        backendProfile ??
        localBackendBusinessProfileNotifier.value ??
        BackendBusinessProfile.defaults();
    final postcodeCity = [
      profile.postcode.trim(),
      profile.city.trim(),
    ].where((e) => e.isNotEmpty).join(' ');
    final address = [
      profile.address.trim().isNotEmpty
          ? profile.address.trim()
          : settings.address.trim(),
      if (postcodeCity.isNotEmpty) postcodeCity,
      if (profile.country.trim().isNotEmpty) profile.country.trim(),
    ].where((e) => e.isNotEmpty).join('\n');

    final companyName = profile.companyName.trim().isNotEmpty
        ? profile.companyName.trim()
        : settings.companyName.trim().isNotEmpty
        ? settings.companyName.trim()
        : kCompanyName;
    final legalName = profile.legalName.trim().isNotEmpty
        ? profile.legalName.trim()
        : companyName;
    final profileJson = profile.toJson();
    String localizedFooterFromProfile(AppLanguage lang) {
      final localized = switch (lang) {
        AppLanguage.en =>
          (profileJson['invoiceReceiptFooterTextEn'] ?? '').toString().trim(),
        AppLanguage.fr =>
          (profileJson['invoiceReceiptFooterTextFr'] ?? '').toString().trim(),
        AppLanguage.es =>
          (profileJson['invoiceReceiptFooterTextEs'] ?? '').toString().trim(),
        _ =>
          (profileJson['invoiceReceiptFooterTextNl'] ?? '').toString().trim(),
      };
      return localized;
    }

    final hasAnyLocalizedFooter =
        (profileJson['invoiceReceiptFooterTextNl'] ?? '')
            .toString()
            .trim()
            .isNotEmpty ||
        (profileJson['invoiceReceiptFooterTextEn'] ?? '')
            .toString()
            .trim()
            .isNotEmpty ||
        (profileJson['invoiceReceiptFooterTextFr'] ?? '')
            .toString()
            .trim()
            .isNotEmpty ||
        (profileJson['invoiceReceiptFooterTextEs'] ?? '')
            .toString()
            .trim()
            .isNotEmpty;
    final appLang = appConfig.currentLanguage;
    final localizedFooter = localizedFooterFromProfile(appLang);
    final legacyFooter = profile.invoiceReceiptFooterText.trim();
    final footerText = localizedFooter.isNotEmpty
        ? localizedFooter
        : (legacyFooter.isNotEmpty &&
              (appLang == AppLanguage.nl || !hasAnyLocalizedFooter))
        ? legacyFooter
        : _receiptText('pdfFooterDefault');

    return <String, String>{
      'companyName': companyName,
      'legalName': legalName,
      'address': address,
      'vatNumber': profile.vatNumber.trim().isNotEmpty
          ? profile.vatNumber.trim()
          : settings.vatCompanyNumber.trim(),
      'phone': profile.phone.trim().isNotEmpty
          ? profile.phone.trim()
          : settings.supportPhone.trim(),
      'email': profile.email.trim().isNotEmpty
          ? profile.email.trim()
          : settings.supportEmail.trim(),
      'website': profile.website.trim(),
      'footer': footerText,
      'logoPath': settings.logoAssetPath.trim(),
    };
  }

  pw.Widget _pdfInfoRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 140,
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey700,
              ),
            ),
          ),
          pw.Expanded(child: pw.Text(value)),
        ],
      ),
    );
  }

  Future<_ReceiptPdfBundle?> _buildReceiptPdfBundle(
    BuildContext context,
  ) async {
    try {
      final smartRef = _businessReferenceDisplayForItem(
        item,
        source: 'receipt_pdf_bundle_stateful_layout',
      );
      _logPdfContactResolution();
      final route = _resolvedRouteForPdf();
      final seller = await _buildSellerProfile();
      final logoBytes = await _loadReceiptLogoBytes(seller['logoPath']);
      final doc = pw.Document();
      final baseFont = await PdfGoogleFonts.notoSansRegular();
      final boldFont = await PdfGoogleFonts.notoSansBold();
      final amounts = _resolvedReceiptAmounts();
      final paymentStatusRaw = _firstDetailPathText(const [
        ['payment_status'],
        ['paymentStatus'],
        ['booking', 'payment_status'],
        ['booking', 'paymentStatus'],
        ['mollie', 'status'],
        ['record', 'mollie', 'status'],
      ]);
      final paymentProviderRaw = _firstDetailPathText(const [
        ['payment_provider'],
        ['paymentProvider'],
        ['booking', 'payment_provider'],
        ['booking', 'paymentProvider'],
      ]);
      final paymentMethod = _localizedPaymentMethodValue(
        _paymentFieldWithMolliePaidFallback(
          value: _paymentMethodFromDetails(),
          paymentStatus: paymentStatusRaw,
          paymentProvider: paymentProviderRaw,
        ),
      );
      final paymentSource = _localizedPaymentSourceValue(
        _paymentFieldWithMolliePaidFallback(
          value: _paymentSourceFromDetails(),
          paymentStatus: paymentStatusRaw,
          paymentProvider: paymentProviderRaw,
        ),
      );
      final rideDateText = _detailText('scheduled_pickup_at') != null
          ? _formatDate(_detailText('scheduled_pickup_at'))
          : _formatDate(item.startedAt);
      final serviceText = _displayServiceToken(_detailText('service_type'));
      final tierText = _displayTierToken(_detailText('tier'));
      final durationText =
          _minutesText('duration_route_min') ??
          _minutesText('route_minutes') ??
          _receiptText('notAvailable');
      final businessFields = _resolvedReceiptBusinessFields();
      debugPrint(
        '[RECEIPT][BUSINESS_FIELDS] source=stateful_pdf booking=${_safeRefPreview(item.bookingId ?? item.tripId)} business=${businessFields.isBusinessDocument} invoiceRequested=${businessFields.invoiceRequested} companyFound=${businessFields.companyName.isNotEmpty} vatFound=${businessFields.vatNumber.isNotEmpty} invoiceEmailFound=${businessFields.invoiceEmail.isNotEmpty} invoiceAddressFound=${businessFields.invoiceAddress.isNotEmpty}',
      );
      // #region agent log H5 stateful receipt business projection
      unawaited(
        _agentDebugLog(
          runId: 'initial',
          hypothesisId: 'H5',
          location: 'main.dart:_RideReceiptBodyState._buildReceiptPdfBundle',
          message: '[RECEIPT][BUSINESS_FIELDS]',
          data: <String, dynamic>{
            'source': 'stateful_pdf',
            'booking': _safeRefPreview(item.bookingId ?? item.tripId),
            'business': businessFields.isBusinessDocument,
            'invoiceRequested': businessFields.invoiceRequested,
            'companyFound': businessFields.companyName.isNotEmpty,
            'vatFound': businessFields.vatNumber.isNotEmpty,
            'invoiceEmailFound': businessFields.invoiceEmail.isNotEmpty,
            'invoiceAddressFound': businessFields.invoiceAddress.isNotEmpty,
          },
        ),
      );
      // #endregion
      final documentTitle = businessFields.isBusinessDocument
          ? _receiptText('invoiceLabel')
          : _receiptText('paymentReceiptLabel');
      final footerText = seller['footer']?.trim().isNotEmpty == true
          ? seller['footer']!.trim()
          : _receiptText('pdfFooterDefault');

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          build: (pw.Context pdfContext) => [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                if (logoBytes != null)
                  pw.Container(
                    width: 82,
                    height: 82,
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey300),
                    ),
                    child: pw.Image(
                      pw.MemoryImage(logoBytes),
                      fit: pw.BoxFit.contain,
                    ),
                  ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        seller['companyName'] ?? kCompanyName,
                        style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                          font: boldFont,
                        ),
                        textAlign: pw.TextAlign.right,
                      ),
                      if ((seller['legalName'] ?? '').trim().isNotEmpty &&
                          seller['legalName'] != seller['companyName'])
                        pw.Text(
                          seller['legalName']!,
                          textAlign: pw.TextAlign.right,
                        ),
                      if ((seller['address'] ?? '').trim().isNotEmpty)
                        pw.Text(
                          seller['address']!,
                          textAlign: pw.TextAlign.right,
                        ),
                      if ((seller['vatNumber'] ?? '').trim().isNotEmpty)
                        pw.Text(
                          '${_receiptText('companyVat')}: ${seller['vatNumber']!}',
                          textAlign: pw.TextAlign.right,
                        ),
                      if ((seller['phone'] ?? '').trim().isNotEmpty)
                        pw.Text(
                          '${_receiptText('companyPhone')}: ${seller['phone']!}',
                          textAlign: pw.TextAlign.right,
                        ),
                      if ((seller['email'] ?? '').trim().isNotEmpty)
                        pw.Text(
                          '${_receiptText('companyEmail')}: ${seller['email']!}',
                          textAlign: pw.TextAlign.right,
                        ),
                      if ((seller['website'] ?? '').trim().isNotEmpty)
                        pw.Text(
                          '${_receiptText('companyWebsite')}: ${seller['website']!}',
                          textAlign: pw.TextAlign.right,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 18),
            pw.Text(
              documentTitle,
              style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
                font: boldFont,
              ),
            ),
            pw.SizedBox(height: 10),
            _pdfInfoRow(smartRef.label, smartRef.value),
            _pdfInfoRow(_receiptText('date'), rideDateText),
            _pdfInfoRow(_receiptText('type'), item.kindLabel),
            _pdfInfoRow(_receiptText('service'), serviceText),
            _pdfInfoRow(_receiptText('tier'), tierText),
            _pdfInfoRow(_receiptText('from'), route.from),
            _pdfInfoRow(_receiptText('to'), route.to),
            _pdfInfoRow(_receiptText('distance'), _kmText()),
            _pdfInfoRow(_receiptText('duration'), durationText),
            pw.SizedBox(height: 12),
            pw.Text(
              _receiptText('customerDetails'),
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                font: boldFont,
              ),
            ),
            pw.SizedBox(height: 6),
            _pdfInfoRow(
              _receiptText('customerName'),
              _customerName ?? _receiptText('notAvailable'),
            ),
            _pdfInfoRow(
              _receiptText('customerEmail'),
              _customerEmail ?? _receiptText('notAvailable'),
            ),
            _pdfInfoRow(
              _receiptText('customerPhone'),
              _customerPhoneRaw ?? _receiptText('notAvailable'),
            ),
            if (businessFields.isBusinessDocument) ...[
              pw.SizedBox(height: 12),
              pw.Text(
                _tr(
                  nl: 'Zakelijk / Factuur',
                  en: 'Business / Invoice',
                  fr: 'Professionnel / Facture',
                  es: 'Empresa / Factura',
                ),
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  font: boldFont,
                ),
              ),
              pw.SizedBox(height: 6),
              _pdfInfoRow(
                _tr(
                  nl: 'Bedrijfsnaam',
                  en: 'Company name',
                  fr: "Nom de l'entreprise",
                  es: 'Empresa',
                ),
                businessFields.companyName.isEmpty
                    ? _receiptText('notAvailable')
                    : businessFields.companyName,
              ),
              _pdfInfoRow(
                _tr(
                  nl: 'BTW-nummer',
                  en: 'VAT number',
                  fr: 'Numero de TVA',
                  es: 'NIF/IVA',
                ),
                businessFields.vatNumber.isEmpty
                    ? _receiptText('notAvailable')
                    : businessFields.vatNumber,
              ),
              _pdfInfoRow(
                _tr(
                  nl: 'Factuur e-mail',
                  en: 'Invoice email',
                  fr: 'E-mail facture',
                  es: 'Email de factura',
                ),
                businessFields.invoiceEmail.isEmpty
                    ? _receiptText('notAvailable')
                    : businessFields.invoiceEmail,
              ),
              _pdfInfoRow(
                _tr(
                  nl: 'Factuuradres',
                  en: 'Invoice address',
                  fr: 'Adresse de facturation',
                  es: 'Direccion de factura',
                ),
                businessFields.invoiceAddress.isEmpty
                    ? _receiptText('notAvailable')
                    : businessFields.invoiceAddress,
              ),
            ],
            pw.SizedBox(height: 12),
            pw.Text(
              _receiptText('paymentActions'),
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                font: boldFont,
              ),
            ),
            pw.SizedBox(height: 6),
            _pdfInfoRow(_receiptText('paymentStatus'), _paymentStatusText()),
            _pdfInfoRow(_receiptText('paymentMethod'), paymentMethod),
            _pdfInfoRow(_receiptText('paymentSource'), paymentSource),
            pw.Divider(color: PdfColors.grey400),
            _pdfInfoRow(
              _receiptText('subtotalExVat'),
              '€ ${amounts.subtotal.toStringAsFixed(2)}',
            ),
            _pdfInfoRow(
              '${_receiptText('vatAmount')} (${(amounts.vatRate * 100).toStringAsFixed(0)}%)',
              '€ ${amounts.vatAmount.toStringAsFixed(2)}',
            ),
            _pdfInfoRow(
              _receiptText('total'),
              '€ ${amounts.total.toStringAsFixed(2)}',
            ),
            pw.SizedBox(height: 16),
            pw.Text(
              footerText,
              style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 10),
            ),
          ],
          theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
        ),
      );

      final bytes = await doc.save();
      final tempDir = await getTemporaryDirectory();
      final receiptsDir = Directory(
        '${tempDir.path}${Platform.pathSeparator}fluxidi_receipts',
      );
      if (!await receiptsDir.exists()) {
        await receiptsDir.create(recursive: true);
      }
      final fileName = _sanitizeFilePart(_customerReference);
      final file = File(
        '${receiptsDir.path}${Platform.pathSeparator}$fileName.pdf',
      );
      await file.writeAsBytes(bytes, flush: true);
      return _ReceiptPdfBundle(bytes: bytes, file: file);
    } catch (err) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_receiptText('pdfGenerationFailed'))),
        );
      }
      return null;
    }
  }

  Future<void> _viewReceiptPdf(BuildContext context) async {
    final bundle = await _buildReceiptPdfBundle(context);
    if (bundle == null) {
      if (!mounted) return;
      await _shareReceipt(this.context);
      return;
    }
    if (!widget.showReceiptUi) {
      debugPrint('[PDF][ACTION][CUSTOMER_DIRECT_VIEW] hasPdf=true');
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ReceiptPdfPreviewPage(
          title: _receiptText('viewPdf'),
          bytes: bundle.bytes,
        ),
      ),
    );
  }

  Future<void> _shareReceiptPdf(BuildContext context) async {
    final bundle = await _buildReceiptPdfBundle(context);
    if (bundle == null) {
      if (!mounted) return;
      await _shareReceipt(this.context);
      return;
    }
    if (!widget.showReceiptUi) {
      debugPrint('[PDF][ACTION][CUSTOMER_DIRECT_SHARE] hasPdf=true');
    }
    debugPrint('[PDF][ACTION][PDF_SHARE] hasPdf=true');
    await Share.shareXFiles(
      <XFile>[XFile(bundle.file.path)],
      text: _receiptCustomerMessage(),
      subject: _receiptText('receiptEmailSubject'),
    );
  }

  Future<void> _shareReceiptPdfViaWhatsApp(BuildContext context) async {
    final bundle = await _buildReceiptPdfBundle(context);
    if (bundle == null) {
      if (!mounted) return;
      await _sendReceiptWhatsApp(this.context);
      return;
    }
    final phone = _customerPhoneE164;
    final phoneFound = phone != null;
    const packageTarget = 'share_sheet';
    debugPrint(
      '[PDF][ACTION][WHATSAPP_PDF] phoneFound=$phoneFound hasPdf=true packageTarget=$packageTarget',
    );

    if (phoneFound && context.mounted) {
      await Clipboard.setData(ClipboardData(text: phone));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              nl: 'Klantnummer gekopieerd. Kies WhatsApp en selecteer of plak de klant om de PDF te sturen.',
              en: 'Customer number copied. Choose WhatsApp and select or paste the customer to send the PDF.',
              fr: 'Numéro client copié. Choisissez WhatsApp puis sélectionnez ou collez le client pour envoyer le PDF.',
              es: 'Número del cliente copiado. Elija WhatsApp y seleccione o pegue el cliente para enviar el PDF.',
            ),
          ),
        ),
      );
    }

    final message = _tr(
      nl: 'Beste klant, in bijlage vindt u uw betaalbewijs/ritbon (PDF).',
      en: 'Dear customer, your ride receipt PDF is attached.',
      fr: 'Cher client, votre reçu de course PDF est en pièce jointe.',
      es: 'Estimado cliente, su comprobante de viaje en PDF está adjunto.',
    );

    try {
      await Share.shareXFiles(
        <XFile>[XFile(bundle.file.path)],
        text: message,
        subject: _receiptText('whatsappPdf'),
      );
    } catch (_) {
      if (!mounted) return;
      await _sendReceiptWhatsApp(this.context);
    }
  }

  Future<void> _shareReceiptPdfViaEmail(BuildContext context) async {
    await _ReceiptPdfActionRunner.sharePdfViaEmail(
      context: context,
      item: item,
    );
  }

  Future<void> _printReceiptPdf(BuildContext context) async {
    final bundle = await _buildReceiptPdfBundle(context);
    if (bundle == null) {
      if (!mounted) return;
      _printReceiptPlaceholder(this.context);
      return;
    }
    await Printing.layoutPdf(onLayout: (_) async => bundle.bytes);
  }

  void _showPaymentLink(BuildContext context) {
    if (!_guardDriverReceiptOperation(action: 'payment_link')) return;
    _markPaymentRequestSent();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_receiptText('paymentLink')),
        content: SelectableText(_paymentLink()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(_receiptText('close')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _copyPaymentLink(context);
            },
            child: Text(_receiptText('copy')),
          ),
        ],
      ),
    );
  }

  void _showPaymentQr(BuildContext context) {
    if (!_guardDriverReceiptOperation(action: 'payment_qr')) return;
    _markPaymentRequestSent();
    final link = _paymentLink();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_receiptText('qrPayment')),
        content: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              QrImageView(
                data: link,
                version: QrVersions.auto,
                size: 220,
                backgroundColor: Colors.white,
              ),
              const SizedBox(height: 12),
              Text(
                _totalText(),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                link,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(_receiptText('close')),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _persistInCarPayment(context: context, method: 'qr');
            },
            child: Text(_receiptText('confirmQrPaid')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _copyPaymentLink(context);
            },
            child: Text(_receiptText('copyLink')),
          ),
        ],
      ),
    );
  }

  void _togglePaidDemo(BuildContext context) {
    setState(() {
      _paymentStatus = _paymentStatus == _ReceiptPaymentStatus.paid
          ? _ReceiptPaymentStatus.sent
          : _ReceiptPaymentStatus.paid;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${_receiptText('paymentStatus')}: ${_paymentStatusText()}',
        ),
      ),
    );
  }

  Future<void> _persistInCarPayment({
    required BuildContext context,
    required String method,
  }) async {
    if (!_guardDriverReceiptOperation(action: 'persist_payment_$method'))
      return;
    final bookingId = (item.bookingId ?? '').trim();
    final normalizedMethod = method.toLowerCase().trim();
    if (bookingId.isEmpty) {
      final tripId = item.tripId.trim();
      if (tripId.isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_receiptText('bookingIdMissing'))),
        );
        return;
      }
      final amount = _receiptTotalAmount();
      final paidAtIso = DateTime.now().toUtc().toIso8601String();
      final payload = <String, dynamic>{
        'trip_id': tripId,
        ..._activeBookingScopeQuery(),
        'payment_status': 'paid',
        'payment_method': normalizedMethod,
        'payment_source': 'in_car',
        'currency': item.currency.trim().isEmpty
            ? 'EUR'
            : item.currency.trim().toUpperCase(),
        'paid_by_driver_id': kDriverId,
        'paid_at': paidAtIso,
        ..._driverMutationActorFields(
          actorVehicleId: (item.vehicleId ?? '').trim(),
        ),
        if (amount != null) 'amount': amount,
      };
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (kAdminToken.trim().isNotEmpty) {
        headers['x-admin-token'] = kAdminToken.trim();
      }
      try {
        final uri = _withActiveBookingScope(kWorkerBaseUrl, '/trip/payment');
        final res = await http
            .post(uri, headers: headers, body: jsonEncode(payload))
            .timeout(const Duration(seconds: 12));
        if (res.statusCode < 200 || res.statusCode >= 300) {
          throw Exception('HTTP ${res.statusCode}');
        }
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        final root = decoded is Map
            ? Map<String, dynamic>.from(decoded)
            : <String, dynamic>{};
        final payment = root['payment'] is Map
            ? Map<String, dynamic>.from(root['payment'] as Map)
            : <String, dynamic>{};
        final extracted = <String, dynamic>{
          'payment_status': (payment['payment_status'] ?? 'paid').toString(),
          'paymentStatus': (payment['payment_status'] ?? 'paid').toString(),
          'payment_method': (payment['payment_method'] ?? normalizedMethod)
              .toString(),
          'paymentMethod': (payment['payment_method'] ?? normalizedMethod)
              .toString(),
          'payment_source': (payment['payment_source'] ?? 'in_car').toString(),
          'paymentSource': (payment['payment_source'] ?? 'in_car').toString(),
          'paid_at': (payment['paid_at'] ?? paidAtIso).toString(),
          'paidAt': (payment['paid_at'] ?? paidAtIso).toString(),
          if (payment['paid_by_driver_id'] != null)
            'paid_by_driver_id': payment['paid_by_driver_id'].toString(),
          if (payment['paid_by_driver_id'] != null)
            'paidByDriverId': payment['paid_by_driver_id'].toString(),
          if (payment['amount'] != null) 'payment_amount': payment['amount'],
          if (payment['amount'] != null) 'paymentAmount': payment['amount'],
        };
        _mergePaymentFieldsIntoReceiptDetails(extracted);
        _appendPaymentUpdateLedgerIfPaid(
          fields: extracted,
          method: normalizedMethod,
          source: 'in_car',
          backendConfirmed: true,
        );
        if (mounted) {
          setState(() => _paymentStatus = _ReceiptPaymentStatus.paid);
        }
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_receiptText('paymentMarkedPaid'))),
        );
      } catch (err) {
        debugPrint(
          '[RECEIPT][TRIP_PAYMENT_MARK_FAILED] tripId=$tripId method=$method err=$err',
        );
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_receiptText('paymentMarkFailed'))),
        );
      }
      return;
    }

    final amount = _receiptTotalAmount();
    final payload = <String, dynamic>{
      'booking_id': bookingId,
      'payment_status': 'paid',
      'payment_method': normalizedMethod,
      'payment_source': 'in_car',
      ..._activeBookingScopeQuery(),
      'currency': item.currency.trim().isEmpty
          ? 'EUR'
          : item.currency.trim().toUpperCase(),
      'paid_by_driver_id': kDriverId,
      'paid_at': DateTime.now().toUtc().toIso8601String(),
      ..._driverMutationActorFields(
        actorVehicleId: (item.vehicleId ?? '').trim(),
      ),
      if (amount != null) 'amount': amount,
    };
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (kAdminToken.trim().isNotEmpty) {
      headers['x-admin-token'] = kAdminToken.trim();
    }

    try {
      final uri = _withActiveBookingScope(
        kBookingBaseUrl,
        '/bookings/${Uri.encodeComponent(bookingId)}/payment',
      );
      final res = await http
          .post(uri, headers: headers, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 12));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('HTTP ${res.statusCode}');
      }
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      final root = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
      final extracted =
          _extractAuthoritativePaymentFields(root) ?? <String, dynamic>{};
      extracted['payment_status'] = 'paid';
      extracted['paymentStatus'] = 'paid';
      extracted['payment_method'] = normalizedMethod;
      extracted['paymentMethod'] = normalizedMethod;
      extracted['payment_source'] = 'in_car';
      extracted['paymentSource'] = 'in_car';
      extracted['paid_at'] ??= payload['paid_at'];
      extracted['paidAt'] ??= payload['paid_at'];
      _mergePaymentFieldsIntoReceiptDetails(extracted);

      if (mounted) {
        setState(() => _paymentStatus = _ReceiptPaymentStatus.paid);
      }

      final paymentBookingId = _firstDetailPathText(const [
        ['payment_booking_id'],
        ['paymentBookingId'],
        ['booking', 'payment_booking_id'],
        ['booking', 'paymentBookingId'],
        ['record', 'payment_booking_id'],
        ['record', 'paymentBookingId'],
        ['record', 'booking', 'payment_booking_id'],
        ['record', 'booking', 'paymentBookingId'],
      ]);
      await CustomerBookingsStore.instance.markPaid(
        bookingId: bookingId,
        paymentBookingId: paymentBookingId,
      );
      _appendPaymentUpdateLedgerIfPaid(
        fields: extracted,
        method: normalizedMethod,
        source: 'in_car',
        backendConfirmed: true,
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_receiptText('paymentMarkedPaid'))),
      );
    } catch (err) {
      debugPrint(
        '[RECEIPT][PAYMENT_MARK_FAILED] bookingId=$bookingId method=$method err=$err',
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_receiptText('paymentMarkFailed'))),
      );
    }
  }

  Future<void> _shareReceipt(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: _shareText()));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_receiptText('receiptCopied'))));
  }

  void _comingSoon(BuildContext context, String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label ${_receiptText('comingSoon')}')),
    );
  }

  void _printReceiptPlaceholder(BuildContext context) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_receiptText('printLater'))));
  }

  Widget _receiptRow(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white60, fontSize: 13),
              softWrap: true,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 7,
            child: Text(
              value,
              textAlign: TextAlign.right,
              softWrap: true,
              style: TextStyle(
                color: highlight ? const Color(0xFFFFD400) : Colors.white,
                fontWeight: highlight ? FontWeight.w900 : FontWeight.w700,
                fontSize: highlight ? 18 : 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _optionalReceiptRow(String label, String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    return _receiptRow(label, text);
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 6),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFFFFD400),
          fontSize: 15,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  String? _minutesText(String key) {
    final value = _detailDouble(key);
    if (value == null) return null;
    final rounded = value.round();
    return '$rounded min';
  }

  String? _plannedSubtype() {
    final explicit = _detailText('subtype');
    if (explicit != null) return _localizedRideSubtype(explicit);
    if ((item.bookingId ?? '').endsWith('-R'))
      return _receiptText('returnRide');
    if (_detailText('return_scheduled_pickup_at') != null ||
        _detailText('return_route') != null) {
      return _receiptText('outboundRide');
    }
    return null;
  }

  String? _routeSegmentsText() {
    final raw = item.bookingDetails['route_segments'];
    if (raw is! List || raw.isEmpty) return null;
    final lines = <String>[];
    for (var i = 0; i < raw.length; i++) {
      final segment = raw[i];
      if (segment is! Map) continue;
      final from = segment['from']?.toString().trim();
      final to = segment['to']?.toString().trim();
      final distance = _segmentNumber(segment['distance_km']);
      final duration = _segmentNumber(segment['duration_min']);
      final parts = <String>[
        if (from != null && from.isNotEmpty) from,
        if (to != null && to.isNotEmpty) '→ $to',
      ];
      final meta = <String>[
        if (distance != null) '${distance.toStringAsFixed(1)} km',
        if (duration != null) '${duration.round()} min',
      ].join(', ');
      final route = parts.isEmpty
          ? '${_receiptText('route')} ${i + 1}'
          : parts.join(' ');
      lines.add('${i + 1}. $route${meta.isEmpty ? '' : ': $meta'}');
    }
    return lines.isEmpty ? null : lines.join('\n');
  }

  double? _segmentNumber(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString().replaceAll(',', '.'));
  }

  Widget _paymentSection(BuildContext context) {
    final receiptTotal = _receiptTotalAmount();
    final alreadyPaid = _paymentStatus == _ReceiptPaymentStatus.paid;
    final canRequestPayment =
        !alreadyPaid && receiptTotal != null && receiptTotal > 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141B2F),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _receiptText('paymentActions'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          _receiptRow(_receiptText('paymentStatus'), _paymentStatusText()),
          _receiptRow(_receiptText('amount'), _totalText(), highlight: true),
          const SizedBox(height: 10),
          if (!alreadyPaid) ...[
            FilledButton.icon(
              onPressed: canRequestPayment
                  ? () => _showPaymentQr(context)
                  : null,
              icon: const Icon(Icons.qr_code_2),
              label: Text(_receiptText('payByQr')),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: canRequestPayment
                  ? () => _persistInCarPayment(context: context, method: 'cash')
                  : null,
              icon: const Icon(Icons.payments_outlined),
              label: Text(_receiptText('cashReceived')),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: canRequestPayment
                  ? () => _persistInCarPayment(
                      context: context,
                      method: 'bancontact',
                    )
                  : null,
              icon: const Icon(Icons.credit_card),
              label: Text(_receiptText('paidByCardTerminal')),
            ),
          ],
        ],
      ),
    );
  }

  Widget _receiptActionsSection(BuildContext context) {
    final hasEmail = (_customerEmail ?? '').trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141B2F),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _receiptText('receiptActions'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: () => _viewReceiptPdf(context),
            icon: const Icon(Icons.visibility_outlined),
            label: Text(_receiptText('viewPdf')),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _shareReceiptPdf(context),
            icon: const Icon(Icons.share_outlined),
            label: Text(_receiptText('sharePdf')),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _shareReceiptPdfViaWhatsApp(context),
            icon: const Icon(Icons.chat_outlined),
            label: Text(_receiptText('whatsappPdf')),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: hasEmail
                ? () => _shareReceiptPdfViaEmail(context)
                : null,
            icon: const Icon(Icons.email_outlined),
            label: Text(_receiptText('emailPdf')),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _printReceiptPdf(context),
            icon: const Icon(Icons.print_outlined),
            label: Text(_receiptText('printReceipt')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final route = _resolvedRouteForPdf();
    final businessFields = _resolvedReceiptBusinessFields();
    final receiptRefDisplay = _businessReferenceDisplayForItem(
      item,
      source: 'receipt_screen_row',
    );
    if (!widget.showReceiptUi) {
      return Scaffold(
        backgroundColor: const Color(0xFF0B1020),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text(
                _receiptText('pdfReady'),
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFF0B1020),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1020),
        elevation: 0,
        title: Text(_receiptText('receiptTitle')),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF141B2F),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Image.asset(
                        kFluxidiLogoAsset,
                        width: 46,
                        height: 46,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.local_taxi,
                          color: Color(0xFFFFD400),
                          size: 38,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Fluxidi',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              _receiptText('rideReceipt'),
                              style: const TextStyle(color: Colors.white60),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _receiptRow(receiptRefDisplay.label, receiptRefDisplay.value),
                  _receiptRow(_receiptText('type'), item.kindLabel),
                  _optionalReceiptRow(
                    _receiptText('subtype'),
                    _plannedSubtype(),
                  ),
                  _receiptRow(
                    _receiptText('startTime'),
                    _formatDate(item.startedAt),
                  ),
                  _receiptRow(
                    _receiptText('endTime'),
                    _formatDate(item.stoppedAt),
                  ),
                  _receiptRow(_receiptText('from'), route.from),
                  _receiptRow(_receiptText('to'), route.to),
                  _receiptRow(_receiptText('distance'), _kmText()),
                  _receiptRow(
                    _receiptText('actualWaitingTime'),
                    _formatWait(item.waitSecondsTotal),
                  ),
                  _receiptRow(
                    _receiptText('total'),
                    _totalText(),
                    highlight: true,
                  ),
                  if (_hasAnyRawCustomerContact) ...[
                    _sectionTitle(_receiptText('customerDetails')),
                    _optionalReceiptRow(
                      _receiptText('customerName'),
                      _customerName,
                    ),
                    _optionalReceiptRow(
                      _receiptText('customerPhone'),
                      _customerPhoneRaw,
                    ),
                    _optionalReceiptRow(
                      _receiptText('customerEmail'),
                      _customerEmail,
                    ),
                  ],
                  if (businessFields.isBusinessDocument) ...[
                    _sectionTitle(
                      _tr(
                        nl: 'Zakelijk / Factuur',
                        en: 'Business / Invoice',
                        fr: 'Professionnel / Facture',
                        es: 'Empresa / Factura',
                      ),
                    ),
                    _optionalReceiptRow(
                      _tr(
                        nl: 'Bedrijfsnaam',
                        en: 'Company name',
                        fr: "Nom de l'entreprise",
                        es: 'Empresa',
                      ),
                      businessFields.companyName.isEmpty
                          ? null
                          : businessFields.companyName,
                    ),
                    _optionalReceiptRow(
                      _tr(
                        nl: 'BTW-nummer',
                        en: 'VAT number',
                        fr: 'Numero de TVA',
                        es: 'NIF/IVA',
                      ),
                      businessFields.vatNumber.isEmpty
                          ? null
                          : businessFields.vatNumber,
                    ),
                    _optionalReceiptRow(
                      _tr(
                        nl: 'Factuur e-mail',
                        en: 'Invoice email',
                        fr: 'E-mail facture',
                        es: 'Email de factura',
                      ),
                      businessFields.invoiceEmail.isEmpty
                          ? null
                          : businessFields.invoiceEmail,
                    ),
                    _optionalReceiptRow(
                      _tr(
                        nl: 'Factuuradres',
                        en: 'Invoice address',
                        fr: 'Adresse de facturation',
                        es: 'Direccion de factura',
                      ),
                      businessFields.invoiceAddress.isEmpty
                          ? null
                          : businessFields.invoiceAddress,
                    ),
                  ],
                  if (_isPlannedReceipt) ...[
                    _sectionTitle(_receiptText('plannedBookingDetails')),
                    _optionalReceiptRow(
                      _receiptText('scheduledPickup'),
                      _detailText('scheduled_pickup_at') == null
                          ? null
                          : _formatDate(_detailText('scheduled_pickup_at')),
                    ),
                    _optionalReceiptRow(
                      _receiptText('service'),
                      _displayServiceToken(_detailText('service_type')),
                    ),
                    _optionalReceiptRow(
                      _receiptText('tier'),
                      _displayTierToken(_detailText('tier')),
                    ),
                    _optionalReceiptRow(
                      _receiptText('passengers'),
                      _detailText('passengers'),
                    ),
                    _optionalReceiptRow(
                      _receiptText('bags'),
                      _detailText('luggage_count'),
                    ),
                    _optionalReceiptRow(
                      _receiptText('bookedWaitingTime'),
                      _minutesText('booked_wait_minutes'),
                    ),
                    _optionalReceiptRow(
                      _receiptText('extraStops'),
                      _detailText('stops'),
                    ),
                    _receiptRow(
                      _receiptText('extras'),
                      _plannedExtrasText() ??
                          _tr(
                            nl: 'Geen extra opties',
                            en: 'No extra options',
                            fr: 'Aucune option supplementaire',
                            es: 'Sin opciones extra',
                          ),
                    ),
                    _optionalReceiptRow(
                      _receiptText('notes'),
                      _detailText('notes'),
                    ),
                    _sectionTitle(_receiptText('routeAndPrices')),
                    _optionalReceiptRow(
                      _receiptText('routeDetails'),
                      _routeSegmentsText(),
                    ),
                    ..._plannedPriceRows(),
                    _optionalReceiptRow(
                      _receiptText('returnPlanned'),
                      _detailText('return_scheduled_pickup_at') == null
                          ? null
                          : _formatDate(
                              _detailText('return_scheduled_pickup_at'),
                            ),
                    ),
                    _optionalReceiptRow(
                      _receiptText('returnRoute'),
                      _detailText('return_route'),
                    ),
                  ],
                  _sectionTitle(_receiptText('statusPaymentSection')),
                  _receiptRow(
                    _receiptText('rideStatus'),
                    _localizedRideStatus(item.status),
                  ),
                  _receiptRow(
                    _receiptText('paymentStatus'),
                    _paymentStatusText(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _paymentSection(context),
            const SizedBox(height: 16),
            _receiptActionsSection(context),
          ],
        ),
      ),
    );
  }
}

class _ReceiptPdfPreviewPage extends StatefulWidget {
  final String title;
  final Uint8List bytes;

  const _ReceiptPdfPreviewPage({required this.title, required this.bytes});

  @override
  State<_ReceiptPdfPreviewPage> createState() => _ReceiptPdfPreviewPageState();
}

class _ReceiptPdfPreviewPageState extends State<_ReceiptPdfPreviewPage> {
  late final Future<List<Uint8List>> _pagesFuture = _renderPages();

  Future<List<Uint8List>> _renderPages() async {
    final pages = <Uint8List>[];
    await for (final page in Printing.raster(widget.bytes, dpi: 200)) {
      pages.add(await page.toPng());
    }
    return pages;
  }

  Future<void> _sharePdf() async {
    final tempDir = await getTemporaryDirectory();
    final file = File(
      '${tempDir.path}${Platform.pathSeparator}receipt-preview.pdf',
    );
    await file.writeAsBytes(widget.bytes, flush: true);
    await Share.shareXFiles(<XFile>[XFile(file.path)], subject: widget.title);
  }

  Future<void> _printPdf() async {
    await Printing.layoutPdf(onLayout: (_) async => widget.bytes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: _receiptText('sharePdf'),
            onPressed: _sharePdf,
            icon: const Icon(Icons.share_outlined),
          ),
          IconButton(
            tooltip: _receiptText('printReceipt'),
            onPressed: _printPdf,
            icon: const Icon(Icons.print_outlined),
          ),
        ],
      ),
      body: FutureBuilder<List<Uint8List>>(
        future: _pagesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final pages = snapshot.data ?? const <Uint8List>[];
          if (pages.isEmpty) {
            return Center(child: Text(_receiptText('pdfGenerationFailed')));
          }
          return PageView.builder(
            itemCount: pages.length,
            itemBuilder: (context, index) {
              final page = pages[index];
              return Container(
                color: const Color(0xFF101010),
                alignment: Alignment.center,
                child: InteractiveViewer(
                  minScale: 1.0,
                  maxScale: 6.0,
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(8),
                    child: Image.memory(
                      page,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _BookingsHubPage extends StatelessWidget {
  final String title;
  final Widget Function(double screenH) buildList;
  final VoidCallback onRefresh;
  final ValueListenable<int> repaintListenable;

  const _BookingsHubPage({
    required this.title,
    required this.buildList,
    required this.onRefresh,
    required this.repaintListenable,
  });

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: const Color(0xFF0B1020),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1020),
        elevation: 0,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Vernieuw',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF141B2F).withOpacity(0.94),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white12),
              ),
              padding: const EdgeInsets.all(14),
              child: ValueListenableBuilder<int>(
                valueListenable: repaintListenable,
                builder: (_, __, ___) => buildList(h),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlowIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  const _GlowIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;

    final btn = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onPressed,
        child: Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: disabled
                ? Colors.white.withOpacity(0.04)
                : Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
            boxShadow: disabled
                ? const []
                : [
                    BoxShadow(
                      color: kFluxidiYellowSoft,
                      blurRadius: 18,
                      spreadRadius: 0.5,
                    ),
                  ],
          ),
          child: Icon(
            icon,
            size: 20,
            color: disabled
                ? Colors.white.withOpacity(0.35)
                : Colors.white.withOpacity(0.90),
          ),
        ),
      ),
    );

    if ((tooltip ?? '').isEmpty) return btn;
    return Tooltip(message: tooltip!, child: btn);
  }
}
