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
import 'package:fluxidi_tracking/customer_booking_store.dart';
import 'package:fluxidi_tracking/customer_bookings_store.dart';
import 'package:fluxidi_tracking/customer_phone_recovery_page.dart';
import 'package:fluxidi_tracking/customer_profile_store.dart';
import 'package:fluxidi_tracking/customer_session_store.dart';
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

final bool kIsWindows = !kIsWeb && Platform.isWindows;

CustomerProfile? _cachedCustomerProfile;
bool _startInCompanyAdminHome = false;
bool _startInDriverHome = false;
final RouteObserver<PageRoute<dynamic>> kAppRouteObserver =
    RouteObserver<PageRoute<dynamic>>();

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

const String kCompanyAdminDriverViewLinkMethod = 'company_admin_driver_view';

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
  final id = _normalizeBridgeTextGlobal(driver.id);
  final isDefaultId = id == 'drv_1';
  final employee = _normalizeBridgeTextGlobal(driver.employeeNumber);
  final isDefaultEmployee = employee == 'drv-001';
  final name = _normalizeBridgeTextGlobal(driver.fullName);
  final isDefaultName =
      name == 'standaard chauffeur' ||
      name == 'default driver' ||
      name == 'standard driver';
  if (isDefaultId || isDefaultName) return true;
  return isDefaultEmployee && (isDefaultId || isDefaultName);
}

List<DriverProfile> _resolveSelectableDriverBridgeCandidatesGlobal({
  bool logCandidates = true,
}) {
  final activeCompanyId = _firstBootstrapText(<dynamic>[
    companyProfileNotifier.value?.companyId,
    activeCompanySessionNotifier.value?.companyId,
  ]);
  if (activeCompanyId.isEmpty) return const <DriverProfile>[];
  final activeCompanyPresent = activeCompanyId.isNotEmpty;
  final hasValidCompanyContext =
      CompanySessionStore.instance.hasValidCompanyContext;
  final hasFreshBootstrapForScope =
      hasValidCompanyContext &&
      _isBridgeBootstrapFreshForCompany(activeCompanyId);
  final selected = <DriverProfile>[];
  for (final driver in driversNotifier.value) {
    final driverId = driver.id.trim();
    final companyId = (driver.companyId ?? '').trim();
    final companyIdPresent = companyId.isNotEmpty;
    final employeePresent = driver.employeeNumber.trim().isNotEmpty;
    final placeholder = _isSeededOrPlaceholderBridgeDriver(driver);
    final active = driver.isActive;
    final idPresent = driverId.isNotEmpty;
    var scoped = false;
    var reason = 'selectable';

    if (!active) {
      reason = 'inactive';
    } else if (placeholder) {
      reason = 'placeholder';
    } else if (!idPresent) {
      reason = 'missing_id';
    } else if (!employeePresent) {
      // Required because DriverSessionStore validation expects employeeNumber.
      reason = 'missing_employee_number';
    } else if (companyIdPresent && companyId != activeCompanyId) {
      reason = 'company_mismatch';
    } else if (companyIdPresent && companyId == activeCompanyId) {
      scoped = true;
    } else if (hasFreshBootstrapForScope) {
      scoped = true;
      reason = 'scoped_from_bootstrap_context';
    } else {
      reason = 'missing_company_scope';
    }

    final isSelected =
        active && !placeholder && idPresent && employeePresent && scoped;
    if (isSelected) {
      selected.add(driver);
    }
    if (logCandidates) {
      debugPrint(
        '[DRIVER_OWNER_BRIDGE][CANDIDATE] driver=${_maskBridgeDriverIdGlobal(driverId)} active=$active scoped=$scoped companyIdPresent=$companyIdPresent activeCompanyPresent=$activeCompanyPresent employeePresent=$employeePresent placeholder=$placeholder selected=$isSelected reason=${isSelected ? "selectable" : reason}',
      );
    }
  }
  return selected;
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
    await DriverSessionStore.instance.bootstrap(driversNotifier.value);
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

String _activeCompanyScopeIdForSync() {
  final fromProfile = companyProfileNotifier.value?.companyId.trim() ?? '';
  if (fromProfile.isNotEmpty) return fromProfile;
  final fromSession =
      activeCompanySessionNotifier.value?.companyId.trim() ?? '';
  if (fromSession.isNotEmpty) return fromSession;
  final fallback = resolvedCompanyId.trim();
  if (fallback.isNotEmpty) return fallback;
  return kTenantId;
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
    debugPrint('[COMPANY_SESSION][DEGRADED_NO_TOKEN] reason=$reason');
    debugPrint('[COMPANY_SESSION][RECOVERY_REQUIRED] reason=$reason');
  }
  return state.hasToken;
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
            nl: 'Backend synchronisatie vereist een actieve bedrijfssessie. Herkoppel of herstel eerst uw bedrijf.',
            en: 'Backend synchronization requires an active company session. Relink or recover your company first.',
            fr: 'La synchronisation backend nécessite une session entreprise active. Reliez ou récupérez d’abord votre entreprise.',
            es: 'La sincronización backend requiere una sesión activa de empresa. Vuelve a vincular o recupera la empresa primero.',
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

// Pending Mollie payment tracking lives in lib/payment_return.dart and is
// re-exported above so existing references in this file (and other modules)
// keep working unchanged.

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadLocalTenantState();
  await _refreshCachedCustomerProfile();
  await CompanySessionStore.instance.bootstrap();
  var hasBootstrapToken = false;
  var hasLocalCompanyContext =
      CompanySessionStore.instance.hasValidCompanyContext;
  if (hasLocalCompanyContext) {
    hasBootstrapToken = await _hasUsableCompanyBootstrapToken(
      reason: 'startup_restore',
      logDegraded: true,
    );
    if (hasBootstrapToken) {
      await _hydrateCompanyBootstrapFromActiveSession(
        reason: 'startup_restore',
        clearOnUnauthorized: true,
      );
      unawaited(
        _triggerCompanyInventoryBackfillRestore(reason: 'company_home_restore'),
      );
    } else {
      debugPrint(
        '[COMPANY_BOOTSTRAP][SKIP_REMOTE_NO_TOKEN] reason=startup_restore',
      );
    }
  }
  hasLocalCompanyContext = CompanySessionStore.instance.hasValidCompanyContext;
  if (hasLocalCompanyContext) {
    setAppRole(AppRole.companyAdmin);
    _startInCompanyAdminHome = true;
    _startInDriverHome = false;
    debugPrint(
      '[COMPANY_PAIRING][AUTO_ROUTE] target=business_home has_token=$hasBootstrapToken',
    );
  } else {
    debugPrint(
      '[COMPANY_PAIRING][AUTO_ROUTE_SKIP] reason=no_valid_company_context',
    );
  }
  await DriverSessionStore.instance.bootstrap(driversNotifier.value);
  final startupDriverSession = activeDriverSessionNotifier.value;
  if (!_startInCompanyAdminHome && startupDriverSession != null) {
    if (_isCompanyAdminDriverViewSession(startupDriverSession)) {
      debugPrint('[DRIVER_ADMIN_VIEW][IGNORE_FOR_NORMAL_LOGIN]');
    } else {
      setAppRole(AppRole.driver);
      _startInDriverHome = true;
      debugPrint('[DRIVER_PAIRING][AUTO_ROUTE] target=driver_home');
    }
  }
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

String _activeDriverSessionVehicleIdForScope() {
  final sessionVehicleId =
      activeDriverSessionNotifier.value?.assignedVehicleId?.trim() ?? '';
  return sessionVehicleId;
}

bool _bookingBelongsToActiveDriver(Map<String, dynamic> booking) {
  final activeDriverId = _resolvedActiveDriverIdForScope().trim();
  if (activeDriverId.isEmpty) return false;
  final linkedVehicleIds = _activeDriverLinkedVehicleIds();
  final activeSessionVehicleId = _activeDriverSessionVehicleIdForScope();
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
  if (assignedVehicleId != null && assignedVehicleId.isNotEmpty) {
    if (activeSessionVehicleId.isNotEmpty &&
        assignedVehicleId == activeSessionVehicleId) {
      return true;
    }
    if (linkedVehicleIds.contains(assignedVehicleId)) {
      return true;
    }
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

Map<String, dynamic> _driverMutationActorFields({
  String? actorDriverId,
  String? actorVehicleId,
}) {
  if (appRoleNotifier.value != AppRole.driver) return const <String, dynamic>{};
  final driverId = (actorDriverId ?? _resolvedActiveDriverIdForScope()).trim();
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
String _lastDriverScopeLogKey = '';

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
  final activeDriverSession = activeDriverSessionNotifier.value;
  final driverTenantId = (activeDriverSession?.tenantId ?? '').trim();
  final driverCompanyId = (activeDriverSession?.companyId ?? '').trim();
  final hasValidCompanyContext =
      CompanySessionStore.instance.hasValidCompanyContext;
  final canUseVerifiedDriverScope =
      !hasValidCompanyContext &&
      driverTenantId.isNotEmpty &&
      driverCompanyId.isNotEmpty &&
      ((activeDriverSession?.isVerifiedPairingSession ?? false) ||
          appRoleNotifier.value == AppRole.driver);
  if (canUseVerifiedDriverScope) {
    final logKey = 'active::$driverTenantId::$driverCompanyId';
    if (_lastDriverScopeLogKey != logKey) {
      _lastDriverScopeLogKey = logKey;
      debugPrint(
        '[DRIVER_SCOPE][ACTIVE] tenant=$driverTenantId company=$driverCompanyId',
      );
    }
    return <String, String>{
      'tenant_id': driverTenantId,
      'company_id': driverCompanyId,
      'tenantId': driverTenantId,
      'companyId': driverCompanyId,
    };
  }

  final tenantId = kOutboundTenantId.trim();
  final companyIdRaw = resolvedCompanyId.trim();
  final companyId = companyIdRaw.isNotEmpty ? companyIdRaw : tenantId;
  final fallbackReason = hasValidCompanyContext
      ? 'company_context'
      : 'default_scope';
  final logKey = 'fallback::$fallbackReason::$tenantId::$companyId';
  if (_lastDriverScopeLogKey != logKey) {
    _lastDriverScopeLogKey = logKey;
    debugPrint(
      '[DRIVER_SCOPE][FALLBACK] reason=$fallbackReason tenant=$tenantId company=$companyId',
    );
  }
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

String? _normalizedCustomerProofPhone(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return null;
  if (text.toLowerCase() == 'null') return null;
  return text;
}

String? _normalizedCustomerProofEmail(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return null;
  if (text.toLowerCase() == 'null') return null;
  return text.toLowerCase();
}

Future<CustomerProfile?> _loadCachedCustomerProfileIfNeeded() async {
  if (_cachedCustomerProfile != null) return _cachedCustomerProfile;
  final loaded = await CustomerProfileStore.instance.load();
  if (loaded != null) {
    _setCachedCustomerProfile(loaded);
  }
  return loaded;
}

Future<Map<String, String>> _customerOwnershipProof({
  required String bookingId,
  Set<String>? aliases,
  String? fallbackEmail,
  String? fallbackPhone,
  Map<String, dynamic>? source,
}) async {
  final normalizedAliases = <String>{};
  void addAlias(String? value) {
    final cleaned = _cleanBusinessReferenceText(value);
    if (cleaned == null) return;
    normalizedAliases.add(cleaned.toLowerCase());
  }

  addAlias(bookingId);
  for (final alias in aliases ?? const <String>{}) {
    addAlias(alias);
  }
  if (source != null && source.isNotEmpty) {
    normalizedAliases.addAll(_customerBookingAliasesFromSource(source));
  }

  String? storedEmail;
  String? storedPhone;
  if (normalizedAliases.isNotEmpty) {
    try {
      final all = await CustomerBookingsStore.instance.loadAll();
      for (final item in all) {
        final itemAliases = _customerBookingAliasesFromStored(item);
        final matches =
            item.canonicalBookingId.trim() == bookingId.trim() ||
            _customerAliasesIntersect(itemAliases, normalizedAliases);
        if (!matches) continue;
        storedEmail = _normalizedCustomerProofEmail(item.customerEmail);
        storedPhone = _normalizedCustomerProofPhone(item.customerPhone);
        if (storedEmail != null || storedPhone != null) break;
      }
    } catch (_) {
      // Proof lookup is best-effort; continue with profile/view fallbacks.
    }
  }

  final profile = await _loadCachedCustomerProfileIfNeeded();
  final email =
      storedEmail ??
      _normalizedCustomerProofEmail(profile?.email) ??
      _normalizedCustomerProofEmail(fallbackEmail);
  final phone =
      storedPhone ??
      _normalizedCustomerProofPhone(profile?.phone) ??
      _normalizedCustomerProofPhone(fallbackPhone);

  return <String, String>{
    if (email != null) 'customer_email': email,
    if (phone != null) 'customer_phone': phone,
  };
}

dynamic _customerBootstrapValueAtPath(
  Map<String, dynamic> source,
  String path,
) {
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

String _customerBootstrapText(Map<String, dynamic> source, List<String> paths) {
  for (final path in paths) {
    final value = _customerBootstrapValueAtPath(source, path);
    final text = (value ?? '').toString().trim();
    if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
  }
  return '';
}

double? _customerBootstrapDouble(
  Map<String, dynamic> source,
  List<String> paths,
) {
  for (final path in paths) {
    final value = _customerBootstrapValueAtPath(source, path);
    if (value is num) return value.toDouble();
    final text = (value ?? '').toString().trim();
    if (text.isEmpty || text.toLowerCase() == 'null') continue;
    final parsed = double.tryParse(text.replaceAll(',', '.'));
    if (parsed != null) return parsed;
  }
  return null;
}

StoredCustomerBooking? _storedBookingFromCustomerBootstrap(
  Map<String, dynamic> item,
  CustomerSession session,
) {
  final bookingId = _customerBootstrapText(item, const [
    'booking_id',
    'bookingId',
    'id',
    'public_booking_id',
    'publicBookingId',
  ]);
  if (bookingId.isEmpty) return null;
  final nowIso = DateTime.now().toIso8601String();
  final tenantId = _customerBootstrapText(item, const [
    'tenant_id',
    'tenantId',
  ]);
  final companyId = _customerBootstrapText(item, const [
    'company_id',
    'companyId',
  ]);
  return StoredCustomerBooking(
    bookingId: bookingId,
    tenantId: tenantId.isNotEmpty
        ? tenantId
        : (session.defaultTenantId ?? '').trim(),
    companyId: companyId.isNotEmpty
        ? companyId
        : (session.defaultCompanyId ?? '').trim(),
    publicBookingId: _customerBootstrapText(item, const [
      'public_booking_reference',
      'publicBookingReference',
      'booking_reference',
      'bookingReference',
      'public_reference',
      'publicReference',
      'public_booking_id',
      'publicBookingId',
    ]),
    planningReference: _customerBootstrapText(item, const [
      'planning_reference',
      'planningReference',
    ]),
    bookingReference: _customerBootstrapText(item, const [
      'booking_reference',
      'bookingReference',
    ]),
    publicReference: _customerBootstrapText(item, const [
      'public_reference',
      'publicReference',
    ]),
    receiptReference: _customerBootstrapText(item, const [
      'receipt_reference',
      'receiptReference',
    ]),
    paymentBookingId: _customerBootstrapText(item, const [
      'payment_booking_id',
      'paymentBookingId',
    ]),
    customerName: _customerBootstrapText(item, const [
      'customer_name',
      'customerName',
    ]),
    customerPhone: _customerBootstrapText(item, const [
      'customer_phone',
      'customerPhone',
    ]),
    customerEmail: _customerBootstrapText(item, const [
      'customer_email',
      'customerEmail',
    ]),
    from: _customerBootstrapText(item, const [
      'from',
      'pickup_address',
      'pickupAddress',
    ]),
    to: _customerBootstrapText(item, const [
      'to',
      'dropoff_address',
      'dropoffAddress',
    ]),
    pickupIso: _customerBootstrapText(item, const ['pickup_iso', 'pickupIso']),
    price: _customerBootstrapDouble(item, const [
      'price',
      'quoted_price',
      'quotedPrice',
    ]),
    currency: _customerBootstrapText(item, const [
      'currency',
      'quote.currency',
    ]),
    paymentStatus: _customerBootstrapText(item, const [
      'payment_status',
      'paymentStatus',
    ]),
    status: _customerBootstrapText(item, const [
      'status',
      'stage',
      'booking_status',
      'bookingStatus',
    ]),
    service: _customerBootstrapText(item, const [
      'service_type',
      'serviceType',
      'service',
    ]),
    tier: _customerBootstrapText(item, const [
      'tier',
      'vehicle_tier',
      'vehicleTier',
    ]),
    pax: _customerBootstrapText(item, const [
      'passenger_count',
      'passengerCount',
      'pax',
    ]),
    bags: _customerBootstrapText(item, const [
      'luggage_count',
      'luggageCount',
      'bags',
    ]),
    createdAt:
        _customerBootstrapText(item, const [
          'created_at',
          'createdAt',
        ]).isNotEmpty
        ? _customerBootstrapText(item, const ['created_at', 'createdAt'])
        : nowIso,
    updatedAt:
        _customerBootstrapText(item, const [
          'updated_at',
          'updatedAt',
        ]).isNotEmpty
        ? _customerBootstrapText(item, const ['updated_at', 'updatedAt'])
        : nowIso,
    companyName: _customerBootstrapText(item, const [
      'company_name',
      'companyName',
    ]),
    vatNumber: _customerBootstrapText(item, const ['vat_number', 'vatNumber']),
    invoiceEmail: _customerBootstrapText(item, const [
      'invoice_email',
      'invoiceEmail',
    ]),
    invoiceAddress: _customerBootstrapText(item, const [
      'invoice_address',
      'invoiceAddress',
    ]),
    quote: _customerBootstrapValueAtPath(item, 'quote') is Map
        ? Map<String, dynamic>.from(
            _customerBootstrapValueAtPath(item, 'quote') as Map,
          )
        : const <String, dynamic>{},
  );
}

bool _isSafeRecoveredCustomerScopeValue(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return false;
  final normalized = trimmed.toLowerCase();
  if (normalized == 'global' || normalized == 'fluxidi') return false;
  return true;
}

({String tenantId, String companyId})?
_defaultCustomerScopeFromBootstrapResponse({
  required Map<String, dynamic> response,
  required List<dynamic> bookings,
}) {
  final customerNode = response['customer'] is Map
      ? Map<String, dynamic>.from(response['customer'] as Map)
      : const <String, dynamic>{};
  final customerTenant =
      (customerNode['tenant_id'] ?? customerNode['tenantId'] ?? '')
          .toString()
          .trim();
  final customerCompany =
      (customerNode['company_id'] ?? customerNode['companyId'] ?? '')
          .toString()
          .trim();
  if (_isSafeRecoveredCustomerScopeValue(customerTenant) &&
      _isSafeRecoveredCustomerScopeValue(customerCompany)) {
    return (tenantId: customerTenant, companyId: customerCompany);
  }
  for (final entry in bookings) {
    if (entry is! Map) continue;
    final item = Map<String, dynamic>.from(entry);
    final tenant = (item['tenant_id'] ?? item['tenantId'] ?? '')
        .toString()
        .trim();
    final company = (item['company_id'] ?? item['companyId'] ?? '')
        .toString()
        .trim();
    if (_isSafeRecoveredCustomerScopeValue(tenant) &&
        _isSafeRecoveredCustomerScopeValue(company)) {
      return (tenantId: tenant, companyId: company);
    }
  }
  return null;
}

Future<void> _persistCustomerSessionDefaultScopeIfNeeded({
  required CustomerSession session,
  required Map<String, dynamic> response,
  required List<dynamic> bookings,
}) async {
  final inferred = _defaultCustomerScopeFromBootstrapResponse(
    response: response,
    bookings: bookings,
  );
  if (inferred == null) return;
  final currentTenant = (session.defaultTenantId ?? '').trim();
  final currentCompany = (session.defaultCompanyId ?? '').trim();
  if (currentTenant == inferred.tenantId &&
      currentCompany == inferred.companyId) {
    return;
  }
  final nextSession = CustomerSession(
    customerSessionToken: session.customerSessionToken,
    expiresAt: session.expiresAt,
    customerId: session.customerId,
    phoneE164: session.phoneE164,
    defaultTenantId: inferred.tenantId,
    defaultCompanyId: inferred.companyId,
    createdAt: session.createdAt,
    updatedAt: session.updatedAt,
  );
  await CustomerSessionStore.instance.save(nextSession);
  debugPrint(
    '[CUSTOMER_BOOTSTRAP][SESSION_SCOPE] tenant=${inferred.tenantId} company=${inferred.companyId}',
  );
}

Future<int> _bootstrapCustomerSessionAndMergeBookings({
  required String reason,
}) async {
  try {
    final session = await CustomerSessionStore.instance.loadValidSession();
    if (session == null) return 0;
    debugPrint('[CUSTOMER_BOOTSTRAP][REQ] reason=$reason');
    final response = await fetchPublicCustomerSessionBootstrap(
      customerSessionToken: session.customerSessionToken,
    );
    if (response == null) {
      final status = lastCustomerBootstrapHttpStatusCode;
      if (status == 401 || status == 403) {
        await CustomerSessionStore.instance.clear();
        debugPrint('[CUSTOMER_BOOTSTRAP][SESSION_EXPIRED]');
      } else {
        debugPrint(
          '[CUSTOMER_BOOTSTRAP][FAIL] reason=$reason status=${status ?? 0}',
        );
      }
      return 0;
    }
    final dynamic bookingsRaw =
        response['bookings'] ??
        _customerBootstrapValueAtPath(response, 'data.bookings') ??
        const <dynamic>[];
    final bookings = bookingsRaw is List ? bookingsRaw : const <dynamic>[];
    await _persistCustomerSessionDefaultScopeIfNeeded(
      session: session,
      response: response,
      bookings: bookings,
    );
    debugPrint('[CUSTOMER_BOOTSTRAP][OK] count=${bookings.length}');
    var merged = 0;
    for (final entry in bookings) {
      if (entry is! Map) continue;
      final stored = _storedBookingFromCustomerBootstrap(
        Map<String, dynamic>.from(entry),
        session,
      );
      if (stored == null) continue;
      final aliases = _customerBookingAliasesFromStored(stored);
      final hidden = await CustomerBookingsStore.instance
          .isAnyReferenceAliasHidden(
            aliases,
            tenantIdHint: stored.tenantId,
            companyIdHint: stored.companyId,
            customerSessionIdHint: session.customerId,
          );
      if (hidden) {
        debugPrint(
          '[CUSTOMER_BOOTSTRAP][SKIP_HIDDEN] booking=${_safeRefPreview(stored.canonicalBookingId)}',
        );
        continue;
      }
      await CustomerBookingsStore.instance.upsert(stored);
      merged += 1;
    }
    debugPrint('[CUSTOMER_BOOTSTRAP][MERGE] count=$merged');
    return merged;
  } catch (err) {
    debugPrint('[CUSTOMER_BOOTSTRAP][FAIL] reason=$reason error=$err');
    return 0;
  }
}

Future<CustomerProfile?> _syncCustomerProfileFromBackendBestEffort({
  required String reason,
}) async {
  try {
    final session = await CustomerSessionStore.instance.loadValidSession();
    if (session == null) {
      debugPrint(
        '[CUSTOMER_PROFILE_SYNC][PULL] ok=false reason=$reason stage=no_valid_session',
      );
      return null;
    }
    final remote = await fetchPublicCustomerProfile(
      customerSessionToken: session.customerSessionToken,
    );
    if (remote == null) {
      final status = lastCustomerProfileHttpStatusCode ?? 0;
      if (status == 401 || status == 403) {
        await CustomerSessionStore.instance.clear();
      }
      debugPrint(
        '[CUSTOMER_PROFILE_SYNC][PULL] ok=false reason=$reason stage=fetch_failed status=$status',
      );
      return null;
    }
    final merged = await CustomerProfileStore.instance
        .mergeBackendProfileForSession(
          remote,
          sessionCustomerId: session.customerId,
          sessionPhoneE164: session.phoneE164,
        );
    _setCachedCustomerProfile(merged);
    debugPrint('[CUSTOMER_PROFILE_SYNC][PULL] ok=true reason=$reason');
    return merged;
  } catch (err) {
    debugPrint(
      '[CUSTOMER_PROFILE_SYNC][PULL] ok=false reason=$reason stage=error error=$err',
    );
    return null;
  }
}

Future<CustomerProfile?> _syncCustomerProfileToBackendBestEffort({
  required String reason,
  required CustomerProfile localProfile,
}) async {
  try {
    final session = await CustomerSessionStore.instance.loadValidSession();
    if (session == null) {
      debugPrint(
        '[CUSTOMER_PROFILE_SYNC][PUSH] ok=false reason=$reason stage=no_valid_session',
      );
      return null;
    }
    final remote = await upsertPublicCustomerProfile(
      customerSessionToken: session.customerSessionToken,
      payload: <String, dynamic>{
        'name': localProfile.name,
        'phone': localProfile.phone,
        'email': localProfile.email,
        'preferred_postcode': localProfile.preferredPostcode,
        'company_name': localProfile.companyName,
        'vat_number': localProfile.vatNumber,
      },
    );
    if (remote == null) {
      final status = lastCustomerProfileHttpStatusCode ?? 0;
      if (status == 401 || status == 403) {
        await CustomerSessionStore.instance.clear();
      }
      debugPrint(
        '[CUSTOMER_PROFILE_SYNC][PUSH] ok=false reason=$reason stage=post_failed status=$status',
      );
      return null;
    }
    final merged = await CustomerProfileStore.instance
        .mergeBackendProfileForSession(
          remote,
          sessionCustomerId: session.customerId,
          sessionPhoneE164: session.phoneE164,
        );
    _setCachedCustomerProfile(merged);
    debugPrint('[CUSTOMER_PROFILE_SYNC][PUSH] ok=true reason=$reason');
    return merged;
  } catch (err) {
    debugPrint(
      '[CUSTOMER_PROFILE_SYNC][PUSH] ok=false reason=$reason stage=error error=$err',
    );
    return null;
  }
}

/// Admin token (optional) for driver actions like complete/cancel/delete.
/// Set at run/build time:
/// flutter run --dart-define=ADMIN_TOKEN=yourSecret
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

({String tenantId, String companyId})? _strictActiveLocalScopeIds() {
  final activeCompanyId = companyProfileNotifier.value?.companyId.trim() ?? '';
  if (activeCompanyId.isNotEmpty) {
    return (tenantId: activeCompanyId, companyId: activeCompanyId);
  }
  final sessionCompanyId =
      activeCompanySessionNotifier.value?.companyId.trim() ?? '';
  if (sessionCompanyId.isNotEmpty) {
    return (tenantId: sessionCompanyId, companyId: sessionCompanyId);
  }
  final driverSession = activeDriverSessionNotifier.value;
  final driverTenantId = (driverSession?.tenantId ?? '').trim();
  final driverCompanyId = (driverSession?.companyId ?? '').trim();
  if ((driverSession?.isVerifiedPairingSession ?? false) &&
      driverTenantId.isNotEmpty &&
      driverCompanyId.isNotEmpty) {
    return (tenantId: driverTenantId, companyId: driverCompanyId);
  }
  return null;
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
  final tenantId = (record['tenant_id'] ?? '').toString().trim();
  final companyId = (record['company_id'] ?? '').toString().trim();
  if (tenantId.isEmpty || companyId.isEmpty) {
    debugPrint(
      '[COMPLIANCE_LEDGER][SKIP_SCOPE] reason=missing_tenant_company_scope',
    );
    return;
  }
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
    required String companyId,
    required String driverId,
    int limit = 120,
  }) async {
    if (kIsWeb) return const <Map<String, dynamic>>[];
    try {
      final normalizedTenantId = tenantId.trim();
      final normalizedCompanyId = companyId.trim();
      if (normalizedTenantId.isEmpty || normalizedCompanyId.isEmpty) {
        return const <Map<String, dynamic>>[];
      }
      final scopedFile = await _scopedFile(
        tenantId: normalizedTenantId,
        companyId: normalizedCompanyId,
      );
      if (await scopedFile.exists()) {
        return _readFromFile(
          scopedFile,
          tenantId: normalizedTenantId,
          companyId: normalizedCompanyId,
          driverId: driverId,
          limit: limit,
          allowLegacyWithoutScope: false,
        );
      }
      final legacyFile = await _legacyFile();
      return _readFromFile(
        legacyFile,
        tenantId: normalizedTenantId,
        companyId: normalizedCompanyId,
        driverId: driverId,
        limit: limit,
        allowLegacyWithoutScope: false,
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
        : (_startInDriverHome ? const DriverHomePage() : const RoleEntryPage());
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
  const DriverHomePage({super.key});

  @override
  State<DriverHomePage> createState() => _DriverHomePageState();
}

class _RideReceiptPage extends StatelessWidget {
  final _TripHistoryItem item;

  const _RideReceiptPage({required this.item});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) => _RideReceiptBody(
        item: item,
        initialAction: null,
        autoPopAfterInitialAction: false,
        showReceiptUi: true,
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
