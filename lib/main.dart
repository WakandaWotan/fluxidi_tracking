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

Map<String, String> _trackingOverlayHeaders() {
  final headers = <String, String>{};
  final token = kAdminToken.trim();
  if (token.isNotEmpty) {
    headers['x-admin-token'] = token;
  }
  return headers;
}

bool _isPaidTrackingPaymentToken(String? raw) {
  final token = (raw ?? '').trim().toLowerCase().replaceAll('-', '_');
  return token == 'paid' ||
      token == 'settled' ||
      token == 'confirmed' ||
      token == 'completed' ||
      token == 'succeeded' ||
      token == 'success';
}

String _normalizeCustomerPaymentDisplayToken(String? raw) {
  return (raw ?? '')
      .trim()
      .toLowerCase()
      .replaceAll('-', '_')
      .replaceAll(' ', '_');
}

bool _isPaidCustomerPaymentDisplayToken(String token) {
  return token == 'paid' ||
      token == 'confirmed' ||
      token == 'success' ||
      token == 'completed' ||
      token == 'settled' ||
      token == 'succeeded' ||
      token == 'captured';
}

bool _isPartialCustomerPaymentDisplayToken(String token) {
  return token == 'partially_paid' ||
      token == 'partial_paid' ||
      token == 'partial';
}

String _classifyCustomerPaymentDisplayToken({
  required Set<String> aliases,
  required String fallbackToken,
  _TrackingPaymentOverlayMatcher? matcher,
}) {
  final normalizedFallback = _normalizeCustomerPaymentDisplayToken(
    fallbackToken,
  );
  if (matcher != null) {
    final aggregate = matcher.aggregateOperationalLegsForParentAliases(aliases);
    if (aggregate.totalLegs >= 2) {
      if (aggregate.paidLegs == aggregate.totalLegs) return 'paid';
      if (aggregate.paidLegs > 0) return 'partially_paid';
    } else if (matcher.hasAnyPaidForAliases(aliases)) {
      return 'paid';
    }
  }
  if (_isPaidCustomerPaymentDisplayToken(normalizedFallback)) return 'paid';
  if (_isPartialCustomerPaymentDisplayToken(normalizedFallback)) {
    return 'partially_paid';
  }
  return normalizedFallback;
}

String _trackingOverlayCompositeKey(String left, String right) {
  final a = left.trim().toLowerCase();
  final b = right.trim().toLowerCase();
  if (a.isEmpty || b.isEmpty) return '';
  return '$a::$b';
}

class _TrackingTripPaymentEntry {
  const _TrackingTripPaymentEntry({
    required this.tripId,
    required this.bookingId,
    required this.parentBookingId,
    required this.legId,
    required this.legType,
    required this.rowKey,
    required this.paymentStatus,
    required this.isPaid,
    required this.isOperationalLeg,
    required this.aliases,
  });

  final String tripId;
  final String bookingId;
  final String parentBookingId;
  final String legId;
  final String legType;
  final String rowKey;
  final String paymentStatus;
  final bool isPaid;
  final bool isOperationalLeg;
  final Set<String> aliases;

  static String _text(dynamic value) {
    final s = (value ?? '').toString().trim();
    if (s.isEmpty || s.toLowerCase() == 'null') return '';
    return s;
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    return value is Map
        ? Map<String, dynamic>.from(value)
        : <String, dynamic>{};
  }

  factory _TrackingTripPaymentEntry.fromJson(Map<String, dynamic> raw) {
    final detail = _asMap(raw['booking_details']);
    final booking = _asMap(raw['booking']);
    final paymentStatus = _text(
      raw['payment_status'] ??
          raw['paymentStatus'] ??
          detail['payment_status'] ??
          detail['paymentStatus'] ??
          booking['payment_status'] ??
          booking['paymentStatus'],
    );
    final bookingId = _text(
      raw['booking_id'] ??
          raw['bookingId'] ??
          detail['booking_id'] ??
          detail['bookingId'] ??
          booking['booking_id'] ??
          booking['bookingId'],
    );
    final parentBookingId = _text(
      raw['parent_booking_id'] ??
          raw['parentBookingId'] ??
          detail['parent_booking_id'] ??
          detail['parentBookingId'],
    );
    final legId = _text(
      raw['leg_id'] ?? raw['legId'] ?? detail['leg_id'] ?? detail['legId'],
    );
    final legType = _text(
      raw['leg_type'] ??
          raw['legType'] ??
          detail['leg_type'] ??
          detail['legType'],
    ).toLowerCase();
    final rowKey = _text(
      raw['row_key'] ?? raw['rowKey'] ?? detail['row_key'] ?? detail['rowKey'],
    );
    final operationalToken = _text(
      raw['is_operational_leg'] ??
          raw['isOperationalLeg'] ??
          detail['is_operational_leg'] ??
          detail['isOperationalLeg'],
    ).toLowerCase();
    final isOperationalLeg =
        operationalToken == 'true' ||
        operationalToken == '1' ||
        legId.isNotEmpty ||
        rowKey.isNotEmpty;
    final aliases = <String>{};
    void addAlias(dynamic value) {
      final token = _text(value).toLowerCase();
      if (token.isEmpty) return;
      aliases.add(token);
    }

    addAlias(raw['trip_id'] ?? raw['tripId']);
    addAlias(raw['booking_id'] ?? raw['bookingId']);
    addAlias(raw['public_booking_id'] ?? raw['publicBookingId']);
    addAlias(raw['public_booking_reference'] ?? raw['publicBookingReference']);
    addAlias(raw['booking_reference'] ?? raw['bookingReference']);
    addAlias(raw['public_reference'] ?? raw['publicReference']);
    addAlias(raw['planning_reference'] ?? raw['planningReference']);
    addAlias(raw['payment_booking_id'] ?? raw['paymentBookingId']);
    addAlias(raw['parent_booking_id'] ?? raw['parentBookingId']);
    addAlias(raw['original_booking_id'] ?? raw['originalBookingId']);
    addAlias(detail['booking_id'] ?? detail['bookingId']);
    addAlias(detail['public_booking_id'] ?? detail['publicBookingId']);
    addAlias(
      detail['public_booking_reference'] ?? detail['publicBookingReference'],
    );
    addAlias(detail['booking_reference'] ?? detail['bookingReference']);
    addAlias(detail['public_reference'] ?? detail['publicReference']);
    addAlias(detail['planning_reference'] ?? detail['planningReference']);
    addAlias(detail['payment_booking_id'] ?? detail['paymentBookingId']);
    addAlias(detail['parent_booking_id'] ?? detail['parentBookingId']);
    addAlias(detail['original_booking_id'] ?? detail['originalBookingId']);
    addAlias(booking['booking_id'] ?? booking['bookingId']);
    addAlias(booking['public_booking_id'] ?? booking['publicBookingId']);
    addAlias(
      booking['public_booking_reference'] ?? booking['publicBookingReference'],
    );
    addAlias(booking['booking_reference'] ?? booking['bookingReference']);
    addAlias(booking['public_reference'] ?? booking['publicReference']);
    addAlias(booking['planning_reference'] ?? booking['planningReference']);
    addAlias(booking['payment_booking_id'] ?? booking['paymentBookingId']);
    addAlias(booking['parent_booking_id'] ?? booking['parentBookingId']);
    addAlias(booking['original_booking_id'] ?? booking['originalBookingId']);

    return _TrackingTripPaymentEntry(
      tripId: _text(raw['trip_id'] ?? raw['tripId']),
      bookingId: bookingId,
      parentBookingId: parentBookingId,
      legId: legId,
      legType: legType,
      rowKey: rowKey,
      paymentStatus: paymentStatus,
      isPaid: _isPaidTrackingPaymentToken(paymentStatus),
      isOperationalLeg: isOperationalLeg,
      aliases: aliases,
    );
  }
}

class _TrackingPaymentOverlayMatcher {
  _TrackingPaymentOverlayMatcher(List<_TrackingTripPaymentEntry> trips)
    : _allTrips = trips {
    for (final entry in trips) {
      for (final alias in entry.aliases) {
        final normalizedAlias = _normalizeAlias(alias);
        if (normalizedAlias.isEmpty) continue;
        _entriesByAlias
            .putIfAbsent(normalizedAlias, () => <_TrackingTripPaymentEntry>[])
            .add(entry);
      }
      if (!entry.isOperationalLeg) continue;
      if (entry.legId.isNotEmpty) {
        _byLegId
            .putIfAbsent(entry.legId, () => <_TrackingTripPaymentEntry>[])
            .add(entry);
      }
      if (entry.bookingId.isNotEmpty && entry.legType.isNotEmpty) {
        final key = _trackingOverlayCompositeKey(
          entry.bookingId,
          entry.legType,
        );
        if (key.isNotEmpty) {
          _byBookingLegType
              .putIfAbsent(key, () => <_TrackingTripPaymentEntry>[])
              .add(entry);
        }
      }
      if (entry.parentBookingId.isNotEmpty && entry.legType.isNotEmpty) {
        final key = _trackingOverlayCompositeKey(
          entry.parentBookingId,
          entry.legType,
        );
        if (key.isNotEmpty) {
          _byParentLegType
              .putIfAbsent(key, () => <_TrackingTripPaymentEntry>[])
              .add(entry);
        }
      }
      final parentKey = entry.parentBookingId.isNotEmpty
          ? entry.parentBookingId
          : entry.bookingId;
      final parentAlias = _normalizeAlias(parentKey);
      if (parentAlias.isNotEmpty) {
        _operationalByParent
            .putIfAbsent(parentAlias, () => <_TrackingTripPaymentEntry>[])
            .add(entry);
      }
    }
  }

  final List<_TrackingTripPaymentEntry> _allTrips;
  final Map<String, List<_TrackingTripPaymentEntry>> _byLegId =
      <String, List<_TrackingTripPaymentEntry>>{};
  final Map<String, List<_TrackingTripPaymentEntry>> _byBookingLegType =
      <String, List<_TrackingTripPaymentEntry>>{};
  final Map<String, List<_TrackingTripPaymentEntry>> _byParentLegType =
      <String, List<_TrackingTripPaymentEntry>>{};
  final Map<String, List<_TrackingTripPaymentEntry>> _operationalByParent =
      <String, List<_TrackingTripPaymentEntry>>{};
  final Map<String, List<_TrackingTripPaymentEntry>> _entriesByAlias =
      <String, List<_TrackingTripPaymentEntry>>{};

  int get totalTrips => _allTrips.length;

  String _normalizeAlias(String value) {
    return value.trim().toLowerCase();
  }

  ({int totalLegs, int paidLegs}) _aggregateFromEntries(
    Iterable<_TrackingTripPaymentEntry> entries,
  ) {
    final paidByLeg = <String, bool>{};
    for (final entry in entries) {
      final legKey = entry.legId.isNotEmpty
          ? 'leg:${entry.legId}'
          : (entry.rowKey.isNotEmpty
                ? 'row:${entry.rowKey}'
                : (entry.legType.isNotEmpty
                      ? 'type:${entry.legType}'
                      : (entry.tripId.isNotEmpty
                            ? 'trip:${entry.tripId}'
                            : '')));
      if (legKey.isEmpty) continue;
      paidByLeg[legKey] = (paidByLeg[legKey] ?? false) || entry.isPaid;
    }
    final total = paidByLeg.length;
    final paid = paidByLeg.values.where((value) => value).length;
    return (totalLegs: total, paidLegs: paid);
  }

  List<_TrackingTripPaymentEntry> matchOperationalLeg({
    required String bookingId,
    required String parentBookingId,
    required String legId,
    required String legType,
  }) {
    final out = <_TrackingTripPaymentEntry>[];
    final seen = <String>{};
    void add(Iterable<_TrackingTripPaymentEntry>? entries) {
      if (entries == null) return;
      for (final entry in entries) {
        final id = entry.tripId.isNotEmpty
            ? entry.tripId
            : '${entry.bookingId}|${entry.parentBookingId}|${entry.legId}|${entry.legType}|${entry.rowKey}';
        if (!seen.add(id)) continue;
        out.add(entry);
      }
    }

    if (legId.trim().isNotEmpty) {
      add(_byLegId[legId.trim()]);
    }
    if (bookingId.trim().isNotEmpty && legType.trim().isNotEmpty) {
      add(
        _byBookingLegType[_trackingOverlayCompositeKey(
          bookingId.trim(),
          legType.trim(),
        )],
      );
    }
    if (parentBookingId.trim().isNotEmpty && legType.trim().isNotEmpty) {
      add(
        _byParentLegType[_trackingOverlayCompositeKey(
          parentBookingId.trim(),
          legType.trim(),
        )],
      );
    }
    return out;
  }

  ({int totalLegs, int paidLegs}) aggregateOperationalLegsForParent(
    String parentBookingId,
  ) {
    final key = _normalizeAlias(parentBookingId);
    if (key.isEmpty) return (totalLegs: 0, paidLegs: 0);
    final entries =
        _operationalByParent[key] ?? const <_TrackingTripPaymentEntry>[];
    return _aggregateFromEntries(entries);
  }

  ({int totalLegs, int paidLegs}) aggregateOperationalLegsForParentAliases(
    Set<String> aliases,
  ) {
    if (aliases.isEmpty) return (totalLegs: 0, paidLegs: 0);
    final seenTripKeys = <String>{};
    final merged = <_TrackingTripPaymentEntry>[];
    for (final alias in aliases) {
      final key = _normalizeAlias(alias);
      if (key.isEmpty) continue;
      final entries = _operationalByParent[key];
      if (entries == null || entries.isEmpty) continue;
      for (final entry in entries) {
        final identity = entry.tripId.isNotEmpty
            ? entry.tripId
            : '${entry.bookingId}|${entry.parentBookingId}|${entry.legId}|${entry.legType}|${entry.rowKey}';
        if (!seenTripKeys.add(identity)) continue;
        merged.add(entry);
      }
    }
    return _aggregateFromEntries(merged);
  }

  bool hasAnyPaidForAliases(Set<String> aliases) {
    if (aliases.isEmpty) return false;
    final seenTripKeys = <String>{};
    for (final alias in aliases) {
      final key = _normalizeAlias(alias);
      if (key.isEmpty) continue;
      final entries = _entriesByAlias[key];
      if (entries == null || entries.isEmpty) continue;
      for (final entry in entries) {
        final identity = entry.tripId.isNotEmpty
            ? entry.tripId
            : '${entry.bookingId}|${entry.parentBookingId}|${entry.legId}|${entry.legType}|${entry.rowKey}|${entry.paymentStatus}';
        if (!seenTripKeys.add(identity)) continue;
        if (entry.isPaid) return true;
      }
    }
    return false;
  }
}

Future<List<_TrackingTripPaymentEntry>> _fetchTrackingOverlayTrips({
  required Map<String, String> scopeQuery,
  required String diagTag,
  int limit = 200,
}) async {
  final scoped = <String, String>{...scopeQuery};
  final tenantId = (scoped['tenant_id'] ?? scoped['tenantId'] ?? '')
      .toString()
      .trim();
  final companyId = (scoped['company_id'] ?? scoped['companyId'] ?? '')
      .toString()
      .trim();
  if (tenantId.isEmpty || companyId.isEmpty) {
    debugPrint(
      '[$diagTag][PAYMENT_OVERLAY][WARN] status=skip reason=missing_scope',
    );
    return const <_TrackingTripPaymentEntry>[];
  }
  scoped['tenant_id'] = tenantId;
  scoped['company_id'] = companyId;
  scoped['tenantId'] = tenantId;
  scoped['companyId'] = companyId;
  scoped['limit'] = '${limit.clamp(1, 500)}';

  final uri = Uri.parse(
    '$kWorkerBaseUrl$kTripsHistoryPath',
  ).replace(queryParameters: scoped);
  try {
    final res = await http
        .get(uri, headers: _trackingOverlayHeaders())
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      debugPrint(
        '[$diagTag][PAYMENT_OVERLAY][WARN] status=${res.statusCode} reason=http_error',
      );
      return const <_TrackingTripPaymentEntry>[];
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! Map<String, dynamic> || decoded['ok'] != true) {
      debugPrint(
        '[$diagTag][PAYMENT_OVERLAY][WARN] status=invalid_payload reason=not_ok',
      );
      return const <_TrackingTripPaymentEntry>[];
    }
    final rawTrips = decoded['trips'] is List
        ? (decoded['trips'] as List)
        : const <dynamic>[];
    return rawTrips
        .whereType<Map>()
        .map(
          (entry) =>
              _TrackingTripPaymentEntry.fromJson(entry.cast<String, dynamic>()),
        )
        .toList(growable: false);
  } catch (err) {
    debugPrint(
      '[$diagTag][PAYMENT_OVERLAY][WARN] status=exception reason=$err',
    );
    return const <_TrackingTripPaymentEntry>[];
  }
}

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
    final session = await CustomerSessionStore.instance.loadValidSession();
    final saved = await CustomerProfileStore.instance.save(
      name: _nameCtrl.text,
      phone: _phoneCtrl.text,
      email: _emailCtrl.text,
      companyName: _companyNameCtrl.text,
      vatNumber: _vatNumberCtrl.text,
      sessionCustomerId: session?.customerId,
    );
    _setCachedCustomerProfile(saved);
    final synced = await _syncCustomerProfileToBackendBestEffort(
      reason: 'customer_onboarding_save',
      localProfile: saved,
    );
    if (synced != null) {
      _setCachedCustomerProfile(synced);
    }
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

class BusinessHomePage extends StatefulWidget {
  const BusinessHomePage({super.key});

  @override
  State<BusinessHomePage> createState() => _BusinessHomePageState();
}

class CompanyDriverManagementPage extends StatefulWidget {
  const CompanyDriverManagementPage({super.key});

  @override
  State<CompanyDriverManagementPage> createState() =>
      _CompanyDriverManagementPageState();
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
    'public_booking_id',
    'publicBookingId',
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
    'payment_booking_id',
    'paymentBookingId',
    'parent_booking_id',
    'parentBookingId',
    'original_booking_id',
    'originalBookingId',
    'booking.booking_id',
    'booking.bookingId',
    'booking.id',
    'booking.public_booking_id',
    'booking.publicBookingId',
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
    'booking.payment_booking_id',
    'booking.paymentBookingId',
    'booking.parent_booking_id',
    'booking.parentBookingId',
    'booking.original_booking_id',
    'booking.originalBookingId',
    'booking_details.booking_id',
    'booking_details.bookingId',
    'booking_details.public_booking_id',
    'booking_details.publicBookingId',
    'booking_details.public_booking_reference',
    'booking_details.publicBookingReference',
    'booking_details.booking_reference',
    'booking_details.bookingReference',
    'booking_details.public_reference',
    'booking_details.publicReference',
    'booking_details.planning_reference',
    'booking_details.planningReference',
    'booking_details.receipt_reference',
    'booking_details.receiptReference',
    'booking_details.payment_booking_id',
    'booking_details.paymentBookingId',
    'booking_details.parent_booking_id',
    'booking_details.parentBookingId',
    'booking_details.original_booking_id',
    'booking_details.originalBookingId',
    'record.booking_id',
    'record.bookingId',
    'record.id',
    'record.public_booking_id',
    'record.publicBookingId',
    'record.parent_booking_id',
    'record.parentBookingId',
    'record.original_booking_id',
    'record.originalBookingId',
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
    'record.booking_details.booking_id',
    'record.booking_details.bookingId',
    'record.booking_details.public_booking_id',
    'record.booking_details.publicBookingId',
    'record.booking_details.public_booking_reference',
    'record.booking_details.publicBookingReference',
    'record.booking_details.booking_reference',
    'record.booking_details.bookingReference',
    'record.booking_details.public_reference',
    'record.booking_details.publicReference',
    'record.booking_details.planning_reference',
    'record.booking_details.planningReference',
    'record.booking_details.receipt_reference',
    'record.booking_details.receiptReference',
    'record.booking_details.payment_booking_id',
    'record.booking_details.paymentBookingId',
    'record.booking_details.parent_booking_id',
    'record.booking_details.parentBookingId',
    'record.booking_details.original_booking_id',
    'record.booking_details.originalBookingId',
    'payload.booking_id',
    'payload.bookingId',
    'payload.id',
    'payload.public_booking_id',
    'payload.publicBookingId',
    'payload.parent_booking_id',
    'payload.parentBookingId',
    'payload.original_booking_id',
    'payload.originalBookingId',
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
    'payload.booking_details.booking_id',
    'payload.booking_details.bookingId',
    'payload.booking_details.public_booking_id',
    'payload.booking_details.publicBookingId',
    'payload.booking_details.public_booking_reference',
    'payload.booking_details.publicBookingReference',
    'payload.booking_details.booking_reference',
    'payload.booking_details.bookingReference',
    'payload.booking_details.public_reference',
    'payload.booking_details.publicReference',
    'payload.booking_details.planning_reference',
    'payload.booking_details.planningReference',
    'payload.booking_details.receipt_reference',
    'payload.booking_details.receiptReference',
    'payload.booking_details.payment_booking_id',
    'payload.booking_details.paymentBookingId',
    'payload.booking_details.parent_booking_id',
    'payload.booking_details.parentBookingId',
    'payload.booking_details.original_booking_id',
    'payload.booking_details.originalBookingId',
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
    'references.payment_booking_id',
    'references.paymentBookingId',
    'references.parent_booking_id',
    'references.parentBookingId',
    'references.original_booking_id',
    'references.originalBookingId',
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
  String? parentBookingId,
  String? originalBookingId,
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
  addAlias(parentBookingId);
  addAlias(originalBookingId);
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
    source: booking.quote,
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

bool _isCustomerBookingTerminalStatus(String? status) {
  final raw = (status ?? '').trim();
  if (raw.isEmpty) return false;
  final normalized = _normalizeCustomerLifecycleStatus(
    raw,
  ).trim().toUpperCase().replaceAll(RegExp(r'[\s-]+'), '_');
  switch (normalized) {
    case 'CANCELLED':
    case 'CANCELED':
    case 'COMPLETED':
    case 'COMPLETE':
    case 'DELETED':
    case 'ARCHIVED':
    case 'CLOSED':
    case 'DONE':
    case 'FAILED':
    case 'EXPIRED':
    case 'DECLINED':
      return true;
    default:
      return false;
  }
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
  final hideMarked = await CustomerBookingsStore.instance
      .markHiddenByAnyReferenceAliases(aliases);
  debugPrint(
    '[CUSTOMER_BOOKING][HIDE_MARK] aliases=${sortedAliases.join(',')} ok=$hideMarked',
  );
  final result = await CustomerBookingsStore.instance
      .removeByAnyReferenceAliasesAcrossKnownCustomerScopesForDisplayOnly(
        aliases,
      );
  debugPrint(
    '[CUSTOMER_BOOKING][DELETE_RESULT] removed=${result.removed} storeA=${result.removed} storeB=${result.removed} remaining=${result.remaining}',
  );
  return (
    removed: result.removed,
    storeA: result.removed,
    storeB: result.removed,
    remaining: result.remaining,
  );
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
  final strictScope = _strictComplianceScopeFromValues(
    tenantCandidates: <dynamic>[
      paymentFields['tenant_id'],
      paymentFields['tenantId'],
      item.bookingDetails['tenant_id'],
      item.bookingDetails['tenantId'],
      item.rawSource['tenant_id'],
      item.rawSource['tenantId'],
      activeDriverSessionNotifier.value?.tenantId,
    ],
    companyCandidates: <dynamic>[
      paymentFields['company_id'],
      paymentFields['companyId'],
      item.bookingDetails['company_id'],
      item.bookingDetails['companyId'],
      item.rawSource['company_id'],
      item.rawSource['companyId'],
      activeDriverSessionNotifier.value?.companyId,
      companyProfileNotifier.value?.companyId,
      activeCompanySessionNotifier.value?.companyId,
    ],
  );

  return <String, dynamic>{
    'ledger_version': '1.0',
    'event_type': 'payment_update',
    'event_id': 'payment_update_${eventKey}_${normalizedMethod}_$paidAtUtc',
    'ride_id': null,
    'ride_type': rideType,
    'lifecycle_status': 'payment_updated',
    'tenant_id': strictScope?.tenantId ?? '',
    'company_id': strictScope?.companyId ?? '',
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
