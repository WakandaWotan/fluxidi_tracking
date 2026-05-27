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

class _CompanyDriverManagementPageState
    extends State<CompanyDriverManagementPage>
    with WidgetsBindingObserver {
  bool _refreshInFlight = false;
  bool _adminDocsRefreshInFlight = false;
  bool _hasSuccessfulRefresh = false;
  bool _lastRefreshOk = false;
  bool _recoveryHintShown = false;
  DateTime? _lastRefreshAtUtc;
  final Set<String> _docRefreshFailedDriverIds = <String>{};
  final Map<String, ({bool active, DateTime atUtc})>
  _recentConfirmedDriverActiveById =
      <String, ({bool active, DateTime atUtc})>{};

  Future<void> _ensureCompanySessionTokenForAdminView({
    required String reason,
  }) async {
    final hasToken = await _hasUsableCompanyBootstrapToken(
      reason: reason,
      logDegraded: true,
    );
    if (!mounted || hasToken || _recoveryHintShown) return;
    _recoveryHintShown = true;
    await _showDegradedCompanySessionRecoveryDialog(context, reason: reason);
  }

  ({String tenantId, String companyId}) _adminScopeForDriver(
    DriverProfile driver,
  ) {
    final scoped = driver.companyId?.trim() ?? '';
    if (scoped.isNotEmpty) {
      return (tenantId: scoped, companyId: scoped);
    }
    final fromProfile = companyProfileNotifier.value?.companyId.trim() ?? '';
    if (fromProfile.isNotEmpty) {
      return (tenantId: fromProfile, companyId: fromProfile);
    }
    final fromSession =
        activeCompanySessionNotifier.value?.companyId.trim() ?? '';
    if (fromSession.isNotEmpty) {
      return (tenantId: fromSession, companyId: fromSession);
    }
    final resolved = resolvedCompanyId.trim();
    if (resolved.isNotEmpty) {
      return (tenantId: resolved, companyId: resolved);
    }
    return (tenantId: kTenantId, companyId: kTenantId);
  }

  List<DriverProfile> _adminVisibleDrivers() {
    return driversNotifier.value
        .where((d) => fleetRecordBelongsToActiveCompanyOrLegacy(d.companyId))
        .toList(growable: false);
  }

  bool _isExpiryWithinDaysForDiag(String raw, {required int days}) {
    final text = raw.trim();
    if (text.isEmpty) return false;
    final dt = DateTime.tryParse(text);
    if (dt == null) return false;
    final now = DateTime.now().toUtc();
    final target = dt.toUtc();
    if (target.isBefore(now)) return false;
    return target.difference(now).inDays <= days;
  }

  Future<void> _refreshAdminDocumentsForVisibleDrivers({
    required String reason,
    bool force = false,
    String? onlyDriverId,
  }) async {
    if (_adminDocsRefreshInFlight) return;
    var refreshFailureStateChanged = false;
    final allVisible = _adminVisibleDrivers();
    final targetDriverId = (onlyDriverId ?? '').trim();
    final targets = targetDriverId.isEmpty
        ? allVisible
        : allVisible
              .where((d) => d.id.trim() == targetDriverId)
              .toList(growable: false);
    if (targets.isEmpty) return;
    final token =
        (activeCompanySessionNotifier.value?.companySessionToken ?? '').trim();
    if (token.isEmpty) {
      for (final driver in targets) {
        final safeDriverRef = _shortDriverIdForDiag(driver.id);
        final scope = _adminScopeForDriver(driver);
        if (_docRefreshFailedDriverIds.add(driver.id.trim())) {
          refreshFailureStateChanged = true;
        }
        debugPrint('[DRIVER_DOCS_SYNC][AUDIT_START] driver=$safeDriverRef');
        debugPrint(
          '[DRIVER_DOCS_SYNC][SCOPE] driver=$safeDriverRef tenant=${_maskScopeForLog(scope.tenantId)} company=${_maskScopeForLog(scope.companyId)}',
        );
        debugPrint('[DRIVER_DOCS_SYNC][BACKEND] driver=$safeDriverRef count=0');
        debugPrint(
          '[DRIVER_DOCS_SYNC][MISMATCH] driver=$safeDriverRef reason=no_company_session_token',
        );
        debugPrint(
          '[DRIVER_DOCS][REFRESH_FAILED] driver=${_shortDriverIdForDiag(driver.id)} error=no_company_session_token',
        );
      }
      if (mounted && refreshFailureStateChanged) {
        setState(() {});
      }
      return;
    }
    _adminDocsRefreshInFlight = true;
    for (final driver in targets) {
      if (_docRefreshFailedDriverIds.add(driver.id.trim())) {
        refreshFailureStateChanged = true;
      }
    }
    debugPrint(
      '[DRIVER_DOCS_ADMIN][REFRESH_START] drivers=${targets.length} reason=$reason force=$force',
    );
    try {
      for (final driver in targets) {
        final safeDriverRef = _shortDriverIdForDiag(driver.id);
        debugPrint('[DRIVER_DOCS_SYNC][AUDIT_START] driver=$safeDriverRef');
        debugPrint('[DRIVER_DOCS][REFRESH_START] driver=$safeDriverRef');
        final scope = _adminScopeForDriver(driver);
        debugPrint(
          '[DRIVER_DOCS_SYNC][SCOPE] driver=$safeDriverRef tenant=${_maskScopeForLog(scope.tenantId)} company=${_maskScopeForLog(scope.companyId)}',
        );
        final localBefore = DriverDocumentsStore.instance
            .documentsVisibleForCompanyAdminDriver(
              driver.id,
              tenantId: scope.tenantId,
              companyId: scope.companyId,
            )
            .length;
        debugPrint(
          '[DRIVER_DOCS_SYNC][LOCAL] driver=$safeDriverRef count=$localBefore',
        );
        await DriverDocumentsStore.instance
            .backfillLocalDriverDocumentsToBackendForDriver(
              bookingBaseUrl: kBookingBaseUrl,
              companySessionToken: token,
              tenantId: scope.tenantId,
              companyId: scope.companyId,
              driverId: driver.id,
            );
        final refreshResult = await DriverDocumentsStore.instance
            .refreshDriverDocumentsFromBackendDetailed(
              bookingBaseUrl: kBookingBaseUrl,
              companySessionToken: token,
              tenantId: scope.tenantId,
              companyId: scope.companyId,
              driverId: driver.id,
            );
        debugPrint(
          '[DRIVER_DOCS_BACKFILL][AUDIT] driver=$safeDriverRef local=$localBefore backend=${refreshResult.backendCount}',
        );
        final ok = refreshResult.ok;
        final visibleCount = DriverDocumentsStore.instance
            .documentsVisibleForCompanyAdminDriver(
              driver.id,
              tenantId: scope.tenantId,
              companyId: scope.companyId,
            )
            .length;
        debugPrint(
          '[DRIVER_DOCS_SYNC][BACKEND] driver=$safeDriverRef count=${refreshResult.backendCount}',
        );
        final compliance = DriverDocumentsStore.instance
            .complianceSummaryForCompanyAdminDriver(
              driver.id,
              tenantId: scope.tenantId,
              companyId: scope.companyId,
            );
        final visibleDocs = DriverDocumentsStore.instance
            .documentsVisibleForCompanyAdminDriver(
              driver.id,
              tenantId: scope.tenantId,
              companyId: scope.companyId,
            );
        final expiringSoonForDriver = visibleDocs
            .where(
              (doc) => _isExpiryWithinDaysForDiag(doc.expiryDate, days: 30),
            )
            .length;
        var localOnlyCount = 0;
        for (final doc in visibleDocs) {
          final hasMetadata =
              doc.documentType.trim().isNotEmpty ||
              doc.title.trim().isNotEmpty ||
              doc.status.trim().isNotEmpty;
          final artifactSource = driverDocumentArtifactSource(doc);
          final hasArtifact = artifactSource != 'missing';
          debugPrint(
            '[DRIVER_DOCS][ARTIFACT_CHECK] driver=$safeDriverRef doc=${_shortDriverIdForDiag(doc.documentId)} hasMetadata=$hasMetadata hasArtifact=$hasArtifact source=$artifactSource',
          );
          if (!hasArtifact) {
            final normalizedType = normalizeDriverDocumentTypeForCompliance(
              rawType: doc.documentType,
              title: doc.title,
            );
            debugPrint(
              '[DRIVER_DOCS][ARTIFACT_MISSING] driver=$safeDriverRef doc=${_shortDriverIdForDiag(doc.documentId)} type=$normalizedType',
            );
          }
          final likelyLocalOnly =
              doc.backendFileName.trim().isEmpty &&
              doc.backendContentType.trim().isEmpty &&
              doc.backendSizeBytes <= 0 &&
              doc.storageState.trim().isEmpty;
          if (likelyLocalOnly) {
            localOnlyCount++;
          }
        }
        if (localOnlyCount > 0) {
          debugPrint(
            '[DRIVER_DOCS_SYNC][UPLOAD_REQUIRED] driver=$safeDriverRef localOnly=$localOnlyCount',
          );
        }
        if (ok && refreshResult.backendCount == 0) {
          debugPrint(
            '[DRIVER_DOCS_SYNC][MISMATCH] driver=$safeDriverRef reason=backend_empty_for_scope',
          );
          if (localBefore == 0) {
            debugPrint(
              '[DRIVER_DOCS_BACKFILL][SOURCE_DEVICE_REQUIRED] driver=$safeDriverRef count=0',
            );
          }
        }
        if (ok) {
          if (_docRefreshFailedDriverIds.remove(driver.id.trim())) {
            refreshFailureStateChanged = true;
          }
          debugPrint(
            '[DRIVER_DOCS][REFRESH_DONE] driver=$safeDriverRef count=$visibleCount',
          );
        } else {
          if (_docRefreshFailedDriverIds.add(driver.id.trim())) {
            refreshFailureStateChanged = true;
          }
          debugPrint(
            '[DRIVER_DOCS_SYNC][MISMATCH] driver=$safeDriverRef reason=${refreshResult.errorCode}',
          );
          debugPrint(
            '[DRIVER_DOCS][REFRESH_FAILED] driver=$safeDriverRef error=backend_refresh_failed',
          );
        }
        debugPrint(
          '[DRIVER_DOCS][COMPLIANCE] driver=$safeDriverRef valid=${compliance.validRequiredCount}/7 uploaded=${compliance.uploadedRequiredCount}/7 missing=${compliance.missingRequiredTypeIds.length} expired=${compliance.expiredRequiredTypeIds.length} pending=${compliance.pendingRequiredTypeIds.length} rejected=${compliance.rejectedRequiredTypeIds.length} attachmentMissing=${compliance.missingAttachmentRequiredTypeIds.length}',
        );
        debugPrint(
          '[DRIVER_DOC_EDIT][COMPLIANCE] driver=$safeDriverRef valid=${compliance.validRequiredCount}/7 expired=${compliance.expiredRequiredTypeIds.length} expiringSoon=$expiringSoonForDriver missing=${compliance.missingRequiredTypeIds.length} attachmentMissing=${compliance.missingAttachmentRequiredTypeIds.length}',
        );
        debugPrint(
          '[DRIVER_DOCS_SYNC][DONE] driver=$safeDriverRef visible=$visibleCount',
        );
        debugPrint(
          '[DRIVER_DOCS_ADMIN][REFRESH_DRIVER] driver=${_shortDriverIdForDiag(driver.id)} ok=$ok count=$visibleCount',
        );
      }
    } finally {
      _adminDocsRefreshInFlight = false;
      if (mounted && refreshFailureStateChanged) {
        setState(() {});
      }
    }
  }

  Future<void> _refreshDriversFromBootstrap({
    required String reason,
    bool force = false,
  }) async {
    if (_refreshInFlight) {
      debugPrint(
        '[DRIVERS_PAGE][REFRESH_SKIP] reason=$reason throttle=false inFlight=true',
      );
      return;
    }
    final now = DateTime.now().toUtc();
    if (!force && _hasSuccessfulRefresh && _lastRefreshAtUtc != null) {
      final elapsed = now.difference(_lastRefreshAtUtc!);
      if (elapsed < const Duration(seconds: 5)) {
        debugPrint(
          '[DRIVERS_PAGE][REFRESH_SKIP] reason=$reason throttle=true inFlight=false',
        );
        return;
      }
    }
    debugPrint('[DRIVERS_PAGE][REFRESH_START] reason=$reason');
    _refreshInFlight = true;
    try {
      final ok = await _hydrateCompanyBootstrapFromActiveSession(
        reason: reason,
      );
      _reapplyRecentConfirmedDriverState();
      _lastRefreshOk = ok;
      try {
        await _refreshAdminDocumentsForVisibleDrivers(
          reason: reason,
          force: force,
        );
      } catch (error) {
        debugPrint(
          '[DRIVER_DOCS_ADMIN][REFRESH_OPTIONAL_ERROR] reason=$reason error=${_shortErrorForDiag(error)}',
        );
      }
      if (ok) {
        _lastRefreshAtUtc = DateTime.now().toUtc();
        _hasSuccessfulRefresh = true;
      }
      debugPrint('[DRIVERS_PAGE][REFRESH_DONE] reason=$reason ok=$ok');
    } finally {
      _refreshInFlight = false;
    }
  }

  void _reapplyRecentConfirmedDriverState() {
    final now = DateTime.now().toUtc();
    const keepFor = Duration(seconds: 25);
    final staleIds = <String>[];
    for (final entry in _recentConfirmedDriverActiveById.entries) {
      final driverId = entry.key.trim();
      final expected = entry.value.active;
      final atUtc = entry.value.atUtc;
      if (driverId.isEmpty || now.difference(atUtc) > keepFor) {
        staleIds.add(driverId);
        continue;
      }
      DriverProfile? current;
      for (final driver in driversNotifier.value) {
        if (driver.id.trim() == driverId) {
          current = driver;
          break;
        }
      }
      if (current == null) {
        staleIds.add(driverId);
        continue;
      }
      if (current.isActive == expected) continue;
      updateDriver(
        current.id,
        current.copyWith(isActive: expected),
        syncInventory: false,
      );
      debugPrint(
        '[DRIVER_STATE_PROPAGATE][NOTIFIER] driver=${_shortDriverIdForDiag(current.id)} updated=true drivers=${driversNotifier.value.length}',
      );
    }
    for (final id in staleIds) {
      _recentConfirmedDriverActiveById.remove(id);
    }
  }

  void _propagateDriverStateAfterConfirmedSave(DriverProfile updated) {
    final driverId = updated.id.trim();
    debugPrint(
      '[DRIVER_STATE_PROPAGATE][START] driver=${_shortDriverIdForDiag(driverId)} active=${updated.isActive}',
    );
    var existedBefore = false;
    for (final driver in driversNotifier.value) {
      if (driver.id.trim() == driverId) {
        existedBefore = true;
        break;
      }
    }
    debugPrint(
      '[DRIVER_STATE_PROPAGATE][LOCAL_LIST] driver=${_shortDriverIdForDiag(driverId)} updated=$existedBefore',
    );
    updateDriver(updated.id, updated, syncInventory: false);
    _recentConfirmedDriverActiveById[driverId] = (
      active: updated.isActive,
      atUtc: DateTime.now().toUtc(),
    );
    final total = driversNotifier.value.length;
    final active = driversNotifier.value.where((d) => d.isActive).length;
    debugPrint(
      '[DRIVER_STATE_PROPAGATE][NOTIFIER] driver=${_shortDriverIdForDiag(driverId)} updated=true drivers=$total',
    );
    debugPrint(
      '[DRIVER_STATE_PROPAGATE][TENANT_CACHE] driver=${_shortDriverIdForDiag(driverId)} saved=true',
    );
    debugPrint('[DRIVER_STATE_PROPAGATE][KPI] active=$active total=$total');
    debugPrint(
      '[DRIVER_STATE_PROPAGATE][DONE] driver=${_shortDriverIdForDiag(driverId)} active=${updated.isActive}',
    );
  }

  Future<void> _refreshAfterMutation({required String reason}) async {
    debugPrint('[DRIVER_MANAGEMENT][REFRESH_AFTER_MUTATION] reason=$reason');
    if (mounted) {
      setState(() {});
    }
    try {
      await _refreshDriversFromBootstrap(reason: reason, force: true);
      if (mounted) {
        setState(() {});
      }
      final driversCount = _adminVisibleDrivers().length;
      if (_lastRefreshOk) {
        debugPrint(
          '[DRIVER_MANAGEMENT][REFRESH_DONE] reason=$reason drivers=$driversCount',
        );
      } else {
        debugPrint(
          '[DRIVER_MANAGEMENT][REFRESH_FAILED] reason=$reason error=bootstrap_refresh_failed',
        );
      }
    } catch (error) {
      debugPrint(
        '[DRIVER_MANAGEMENT][REFRESH_FAILED] reason=$reason error=${_shortErrorForDiag(error)}',
      );
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(
      _ensureCompanySessionTokenForAdminView(reason: 'drivers_page_open'),
    );
    unawaited(
      _refreshDriversFromBootstrap(reason: 'drivers_page_open', force: true),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(
        _ensureCompanySessionTokenForAdminView(reason: 'drivers_page_resume'),
      );
      unawaited(_refreshDriversFromBootstrap(reason: 'drivers_page_resume'));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _CompanyDriverManagementPageBody(
      onRequestAdminDriverDocumentsRefresh:
          _refreshAdminDocumentsForVisibleDrivers,
      onRequestMutationRefresh: _refreshAfterMutation,
      documentRefreshFailedDriverIds: _docRefreshFailedDriverIds,
      onPropagateConfirmedDriverState: _propagateDriverStateAfterConfirmedSave,
    );
  }
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
  bool _driverManualPause = false;
  bool _driverAvailabilitySaving = false;
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
  int? _completedTodayCount;
  bool _completedTodayLoading = false;
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
  double? _directRideEstimatedFare;
  bool _directRideEstimateLoading = false;
  String? _directRideEstimateError;
  String _directRideEstimateCurrency = kDefaultCurrency;
  Timer? _directRideEstimateDebounce;
  int _directRideEstimateRequestSeq = 0;
  String? _directRideEstimateSignature;

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
  final Map<String, Future<_RoutePreviewData?>> _nextRidePreviewCache =
      <String, Future<_RoutePreviewData?>>{};
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

  Future<void> _clearRouteAndPinAnnotationsOnly() async {
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

    await _clearRouteAndPinAnnotationsOnly();

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
        _directRideEstimatedFare = null;
        _directRideEstimateLoading = false;
        _directRideEstimateError = null;
        _directRideEstimateCurrency = kDefaultCurrency;
        _directRideEstimateSignature = null;
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
    return s == 'COMPLETED' ||
        s == 'COMPLETE' ||
        s == 'CANCELLED' ||
        s == 'CANCELED' ||
        s == 'DELETED' ||
        s == 'ARCHIVED' ||
        s == 'CLOSED' ||
        s == 'DONE' ||
        s == 'FAILED' ||
        s == 'EXPIRED' ||
        s == 'DECLINED';
  }

  String _bookingActionKeyForUi(BookingItem b) {
    if (b.isOperationalLeg && b.legId.trim().isNotEmpty) {
      return b.rowKey;
    }
    return b.bookingId;
  }

  String? _effectiveStatusFor(BookingItem b) {
    return _bookingStatusOverrides[b.rowKey] ??
        _bookingStatusOverrides[b.bookingId] ??
        b.status;
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

  String _resolvedAssignedVehicleIdFromBookingItem(BookingItem b) {
    final booking = _bookingScopeViewFor(b);
    return (_bookingScopeFirstText(booking, const [
              ['assigned_vehicle_id'],
              ['assignedVehicleId'],
              ['vehicle_id'],
              ['vehicleId'],
              ['details', 'assigned_vehicle_id'],
              ['details', 'assignedVehicleId'],
              ['details', 'vehicle_id'],
              ['details', 'vehicleId'],
              ['booking', 'assigned_vehicle_id'],
              ['booking', 'assignedVehicleId'],
              ['booking', 'vehicle_id'],
              ['booking', 'vehicleId'],
              ['record', 'assigned_vehicle_id'],
              ['record', 'assignedVehicleId'],
              ['record', 'vehicle_id'],
              ['record', 'vehicleId'],
              ['record', 'booking', 'assigned_vehicle_id'],
              ['record', 'booking', 'assignedVehicleId'],
              ['record', 'booking', 'vehicle_id'],
              ['record', 'booking', 'vehicleId'],
            ]) ??
            '')
        .trim();
  }

  ({String actorVehicleId, String source}) _plannedTripActorVehicleContext(
    BookingItem b,
  ) {
    final assignedVehicleId = _resolvedAssignedVehicleIdFromBookingItem(b);
    if (assignedVehicleId.isNotEmpty) {
      return (actorVehicleId: assignedVehicleId, source: 'assigned_vehicle');
    }
    final sessionVehicleId =
        activeDriverSessionNotifier.value?.assignedVehicleId?.trim() ?? '';
    if (sessionVehicleId.isNotEmpty) {
      return (actorVehicleId: sessionVehicleId, source: 'session_vehicle');
    }
    final linkedVehicleIds = _activeDriverLinkedVehicleIds().toList(
      growable: false,
    )..sort();
    if (linkedVehicleIds.isNotEmpty) {
      return (actorVehicleId: linkedVehicleIds.first, source: 'linked_vehicle');
    }
    return (
      actorVehicleId: _directRideVehicleId().trim(),
      source: 'fallback_direct',
    );
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
        '[DRIVER_SCOPE][BLOCK] action=$action booking_id=$bookingId assigned_vehicle_id=$assignedVehicleId active_driver_id=$activeDriverId active_vehicle_id=${_activeDriverSessionVehicleIdForScope()} allowed=false',
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
          '[DRIVER_SCOPE][FILTER] booking_id=$bookingId assigned_vehicle_id=$assignedVehicleId active_driver_id=${_resolvedActiveDriverIdForScope()} active_vehicle_id=${_activeDriverSessionVehicleIdForScope()} allowed=$allowed',
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
    String? safeRemoteImageUrl(String? value) {
      final text = (value ?? '').trim();
      if (text.isEmpty) return null;
      if (text.startsWith('https://') || text.startsWith('http://')) {
        return text;
      }
      return null;
    }

    bool isHttpImageRef(String value) {
      final lower = value.trim().toLowerCase();
      return lower.startsWith('https://') || lower.startsWith('http://');
    }

    Widget resolvedFallback() {
      return fallback ??
          Image.asset(
            kFluxidiLogoAsset,
            height: height,
            fit: fit,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.local_taxi, size: 72, color: Colors.white70),
          );
    }

    return ValueListenableBuilder<BusinessSettingsState>(
      valueListenable: businessSettingsNotifier,
      builder: (context, s, _) {
        final localRef = s.logoAssetPath.trim();
        final sessionLogoRef = safeRemoteImageUrl(
          activeDriverSessionNotifier.value?.companyLogoUrl,
        );
        final ref = localRef.isNotEmpty
            ? localRef
            : (sessionLogoRef ?? kFluxidiLogoAsset);
        if (_isAssetRef(ref)) {
          return Image.asset(
            ref,
            height: height,
            fit: fit,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, __, ___) => resolvedFallback(),
          );
        }
        if (isHttpImageRef(ref)) {
          return Image.network(
            ref,
            height: height,
            fit: fit,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, __, ___) => resolvedFallback(),
          );
        }
        if (kIsWeb) return resolvedFallback();
        return Image.file(
          File(ref),
          height: height,
          fit: fit,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, __, ___) => resolvedFallback(),
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
      textureView: kDriverMapTextureView,
      androidHostingMode: kDriverMapHostingMode,
      styleUri: initialStyle,
      cameraOptions: mb.CameraOptions(
        center: _mbPoint(
          kDriverMapInitialCenterLon,
          kDriverMapInitialCenterLat,
        ),
        zoom: kDriverMapInitialZoom,
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
    unawaited(_refreshCompletedTodayCount(reason: 'init_boot'));
    _syncDriverPauseFromProfile(reason: 'init_boot');
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

  void _syncDriverPauseFromProfile({required String reason}) {
    final profile = _dashboardActiveDriverProfile();
    if (profile == null) return;
    final paused =
        normalizeDriverAvailabilityState(
          profile.availabilityStatus,
          fallback: 'available',
        ) ==
        'paused';
    if (_driverManualPause == paused) return;
    _driverManualPause = paused;
    debugPrint(
      '[DRIVER_AVAILABILITY][SESSION_PATCH] driver=${_shortDriverIdForDiag(profile.id)} availability=${paused ? 'paused' : 'available'}',
    );
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
    _directRideEstimateDebounce?.cancel();
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
      final activeDriverSession = activeDriverSessionNotifier.value;
      final driverTokenMode =
          appRoleNotifier.value == AppRole.driver &&
          (activeDriverSession?.linkMethod ?? '').trim().toLowerCase() ==
              'public_driver_login';
      final driverSessionToken = (activeDriverSession?.driverSessionToken ?? '')
          .trim();
      Uri primaryUri;
      Map<String, String> requestHeaders;
      final useDriverToken = driverTokenMode && driverSessionToken.isNotEmpty;
      if (useDriverToken) {
        primaryUri = Uri.parse(
          '$kBookingBaseUrl$kDriverBookingsPath',
        ).replace(queryParameters: <String, String>{'limit': '50', 't': '$ts'});
        requestHeaders = <String, String>{
          'Accept': 'application/json',
          'Authorization': 'Bearer $driverSessionToken',
        };
        debugPrint('[RIDES][REFRESH][MODE] source=driver_token');
      } else {
        primaryUri = _withActiveBookingScope(
          kBookingBaseUrl,
          kListBookingsPath,
          extraQuery: <String, String>{'limit': '50', 't': '$ts'},
        );
        requestHeaders = _headers(admin: true);
        if (driverTokenMode) {
          debugPrint(
            '[RIDES][REFRESH][MODE] source=admin_fallback reason=no_driver_token',
          );
        }
      }
      debugPrint('[RIDES][REFRESH][REQ] trigger=$trigger GET $primaryUri');
      final res = await http.get(primaryUri, headers: requestHeaders);
      debugPrint(
        '[RIDES][REFRESH][RES] code=${res.statusCode} body=${res.body}',
      );

      if (useDriverToken && res.statusCode == 401) {
        debugPrint('[RIDES][REFRESH][AUTH_EXPIRED]');
        _stopBookingPolling(reason: 'driver_token_auth_expired');
        if (!mounted) return;
        setState(() {
          _bookingsError = _tr(
            nl: 'Je chauffeurssessie is verlopen. Log opnieuw in.',
            en: 'Your driver session expired. Please log in again.',
            fr: 'Votre session chauffeur a expire. Reconnectez-vous.',
            es: 'Tu sesion de conductor ha caducado. Inicia sesion de nuevo.',
          );
          _loadingBookings = false;
        });
        _markBookingsUiDirty();
        return;
      }

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
      final prevStatusByRowKey = <String, String?>{
        for (final b in _bookings) b.rowKey: _effectiveStatusFor(b),
      };
      final prevStatusByBookingId = <String, String?>{
        for (final b in _bookings) b.bookingId: _effectiveStatusFor(b),
      };
      final items = raw.whereType<Map<String, dynamic>>().map((j) {
        final parsed = BookingItem.fromJson(j);
        final apiStatus = parsed.status?.trim();
        final mergedStatus = (apiStatus != null && apiStatus.isNotEmpty)
            ? apiStatus
            : (prevStatusByRowKey[parsed.rowKey] ??
                  prevStatusByBookingId[parsed.bookingId] ??
                  _bookingStatusOverrides[parsed.rowKey] ??
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
          _bookingStatusOverrides[b.rowKey] = apiStatus;
          if (!(b.isOperationalLeg && b.legId.trim().isNotEmpty)) {
            _bookingStatusOverrides[b.bookingId] = apiStatus;
          }
        }
      }

      final parsedStatuses = items
          .map(
            (b) =>
                '${_safeRefPreview(b.rowKey)}:${(_effectiveStatusFor(b) ?? 'null').toUpperCase()}',
          )
          .join(', ');
      final visibleStatuses = items
          .where((b) => !_deletedBookingIds.contains(b.bookingId))
          .where((b) => !_isClosedRideStatus(_effectiveStatusFor(b)))
          .map(
            (b) =>
                '${_safeRefPreview(b.rowKey)}:${(_effectiveStatusFor(b) ?? 'null').toUpperCase()}',
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
      // Prevent old bookings-hub optimized panel from flashing during
      // route pop/transition back to map/cockpit.
      if (_bookingsHubVisible) {
        if (mounted) {
          setState(() => _bookingsHubVisible = false);
        } else {
          _bookingsHubVisible = false;
        }
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
      final actorDriverId = _resolvedActiveDriverIdForScope().trim();
      final vehicleContext = _plannedTripActorVehicleContext(b);
      final actorVehicleId = vehicleContext.actorVehicleId.trim();
      debugPrint(
        '[PLANNED_TRIP][START][IDENTITY] booking=${_shortDriverIdForDiag(b.bookingId)} driver=${_shortDriverIdForDiag(actorDriverId)} vehicle=${_shortDriverIdForDiag(actorVehicleId)} vehicle_source=${vehicleContext.source}',
      );
      final payload = {
        'booking_id': b.bookingId,
        'driver_id': actorDriverId,
        'driverId': actorDriverId,
        'actor_driver_id': actorDriverId,
        'actorDriverId': actorDriverId,
        'vehicle_id': actorVehicleId,
        'vehicleId': actorVehicleId,
        'actor_vehicle_id': actorVehicleId,
        'actorVehicleId': actorVehicleId,
        ..._activeBookingScopeQuery(),
        // Optional context (helps debugging / future UI)
        'pickup': (b.from ?? '').toString(),
        'dropoff': (b.to ?? '').toString(),
        ..._driverMutationActorFields(
          actorDriverId: actorDriverId,
          actorVehicleId: actorVehicleId,
        ),
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

  bool _isRideMutationTransportError(Object err) {
    final text = err.toString().toLowerCase();
    return text.contains('clientsoftware caused connection abort') ||
        text.contains('connection abort') ||
        text.contains('connection reset') ||
        text.contains('socketexception') ||
        text.contains('timeoutexception') ||
        text.contains('failed host lookup') ||
        text.contains('network is unreachable') ||
        text.contains('uri=https://');
  }

  Future<String?> _fetchAuthoritativeRideStatus(String bookingId) async {
    try {
      final uri = _withActiveBookingScope(
        kBookingBaseUrl,
        '$kListBookingsPath/${Uri.encodeComponent(bookingId)}',
      );
      final res = await http
          .get(uri, headers: _headers(admin: true))
          .timeout(const Duration(seconds: 12));
      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) return null;
      final direct = (decoded['status'] ?? '').toString().trim();
      if (direct.isNotEmpty) return direct.toUpperCase();
      final record = decoded['record'];
      if (record is Map) {
        final recordStatus = (record['status'] ?? '').toString().trim();
        if (recordStatus.isNotEmpty) return recordStatus.toUpperCase();
        final booking = record['booking'];
        if (booking is Map) {
          final bookingStatus = (booking['status'] ?? '').toString().trim();
          if (bookingStatus.isNotEmpty) return bookingStatus.toUpperCase();
        }
      }
      return null;
    } catch (_) {
      return null;
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
    final actionKey = _bookingActionKeyForUi(b);
    setState(() => _bookingActionInFlight.add(actionKey));
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
      final res = await http
          .post(uri, headers: _headers(admin: true), body: jsonEncode(payload))
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
      if (res.statusCode != 200 || !ok) {
        throw Exception('HTTP ${res.statusCode}: status_update_failed');
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
      final normalizedStatus = status.trim().toUpperCase();
      if (_isRideMutationTransportError(e)) {
        final authoritative = await _fetchAuthoritativeRideStatus(bookingId);
        if (authoritative == normalizedStatus) {
          if (!mounted) return;
          setState(() {
            _bookingStatusOverrides[bookingId] = normalizedStatus;
            final idx = _bookings.indexWhere((x) => x.bookingId == bookingId);
            if (idx >= 0) {
              _bookings[idx] = _bookings[idx].copyWith(
                status: normalizedStatus,
              );
            }
            if (_activeBooking?.bookingId == bookingId) {
              _activeBooking = _activeBooking!.copyWith(
                status: normalizedStatus,
              );
            }
          });
          _markBookingsUiDirty();
          _toast('✅ $status: ${b.shortId}');
          await _refreshBookings(
            force: true,
            trigger: 'status_change_verified',
          );
          return;
        }
      }
      _toast(
        _tr(
          nl: 'Status bijwerken mislukt. Vernieuw en probeer opnieuw.',
          en: 'Status update failed. Refresh and try again.',
          fr: 'La mise a jour du statut a echoue. Actualisez puis reessayez.',
          es: 'No se pudo actualizar el estado. Actualiza e intentalo de nuevo.',
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _bookingActionInFlight.remove(actionKey));
        _markBookingsUiDirty();
      }
    }
  }

  Future<void> _setOperationalLegStatus(BookingItem b, String status) async {
    if (!mounted) return;
    if (!_canOperateBookingWithGuard(
      _bookingScopeViewFor(b),
      action: 'leg_status_$status',
    )) {
      return;
    }
    final bookingId = b.bookingId.trim();
    final legId = b.legId.trim();
    if (bookingId.isEmpty || legId.isEmpty) {
      _toast(
        _tr(
          nl: 'Legstatus bijwerken mislukt. Vernieuw en probeer opnieuw.',
          en: 'Leg status update failed. Refresh and try again.',
          fr: 'La mise a jour du statut du trajet a echoue. Actualisez puis reessayez.',
          es: 'No se pudo actualizar el estado del tramo. Actualiza e intentalo de nuevo.',
        ),
      );
      return;
    }
    final actionKey = _bookingActionKeyForUi(b);
    setState(() => _bookingActionInFlight.add(actionKey));
    _markBookingsUiDirty();
    try {
      final uri = _withActiveBookingScope(
        kBookingBaseUrl,
        '/bookings/${Uri.encodeComponent(bookingId)}/legs/${Uri.encodeComponent(legId)}/status',
      );
      final actorRole = appRoleNotifier.value == AppRole.driver
          ? 'driver'
          : 'admin';
      final payload = <String, dynamic>{
        'booking_id': bookingId,
        'leg_id': legId,
        'status': status,
        'actor_role': actorRole,
        'actorRole': actorRole,
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
        '[RIDES][LEG_STATUS][REQ] url=$uri payload=${jsonEncode(payload)}',
      );
      final res = await http
          .post(uri, headers: _headers(admin: true), body: jsonEncode(payload))
          .timeout(const Duration(seconds: 12));
      debugPrint(
        '[RIDES][LEG_STATUS][RES] code=${res.statusCode} body=${res.body}',
      );
      dynamic decoded;
      try {
        decoded = jsonDecode(res.body);
      } catch (_) {
        decoded = null;
      }
      final ok = decoded is Map ? decoded['ok'] == true : false;
      if (res.statusCode != 200 || !ok) {
        throw Exception('HTTP ${res.statusCode}: leg_status_update_failed');
      }

      if (!mounted) return;
      setState(() {
        _bookingStatusOverrides[b.rowKey] = status;
        final idx = _bookings.indexWhere((x) => x.rowKey == b.rowKey);
        if (idx >= 0) {
          _bookings[idx] = _bookings[idx].copyWith(status: status);
        }
        if (_activeBooking?.rowKey == b.rowKey) {
          _activeBooking = _activeBooking!.copyWith(status: status);
        }
      });
      _markBookingsUiDirty();
      _toast('✅ $status: ${b.shortId}');
      final normalizedStatus = status.trim().toUpperCase();
      if (normalizedStatus == 'COMPLETED') {
        await _recordOperationalLegPlannedStopBestEffort(b);
      }
      await _debugFetchBookingSnapshot(
        bookingId: bookingId,
        contextLabel: 'LEG_STATUS_AFTER_WRITE',
      );
      await _refreshBookings(force: true, trigger: 'leg_status_change');
    } catch (e) {
      _toast(
        _tr(
          nl: 'Legstatus bijwerken mislukt. Vernieuw en probeer opnieuw.',
          en: 'Leg status update failed. Refresh and try again.',
          fr: 'La mise a jour du statut du trajet a echoue. Actualisez puis reessayez.',
          es: 'No se pudo actualizar el estado del tramo. Actualiza e intentalo de nuevo.',
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _bookingActionInFlight.remove(actionKey));
        _markBookingsUiDirty();
      }
    }
  }

  String? _sanitizeOperationalTripIdentityToken(String? raw) {
    final value = raw?.trim().toLowerCase();
    if (value == null || value.isEmpty) return null;
    final sanitized = value
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (sanitized.isEmpty) return null;
    return sanitized.length > 96 ? sanitized.substring(0, 96) : sanitized;
  }

  String _operationalLegTypeToken(BookingItem b) {
    final explicit = _bookingScopeFirstText(_bookingScopeViewFor(b), const [
      ['leg_type'],
      ['legType'],
      ['booking', 'leg_type'],
      ['booking', 'legType'],
    ]);
    final normalized = (explicit ?? '').trim().toLowerCase();
    if (normalized == 'return') return 'return';
    return 'outbound';
  }

  num? _operationalLegDetailNum(
    Map<String, dynamic> details,
    List<List<String>> paths,
  ) {
    for (final path in paths) {
      dynamic cursor = details;
      for (final key in path) {
        if (cursor is Map && cursor.containsKey(key)) {
          cursor = cursor[key];
        } else {
          cursor = null;
          break;
        }
      }
      if (cursor is num) return cursor;
      if (cursor is String) {
        final parsed = num.tryParse(cursor.replaceAll(',', '.').trim());
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  Future<void> _recordOperationalLegPlannedStopBestEffort(
    BookingItem booking,
  ) async {
    if (!mounted) return;
    if (!booking.isOperationalLeg) return;
    final bookingId = booking.bookingId.trim();
    final legId = booking.legId.trim();
    if (bookingId.isEmpty || legId.isEmpty) return;

    try {
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final bookingScope = _bookingScopeViewFor(booking);
      final legType = _operationalLegTypeToken(booking);
      final parentBookingId =
          (_bookingScopeFirstText(bookingScope, const [
                    ['parent_booking_id'],
                    ['parentBookingId'],
                    ['booking', 'parent_booking_id'],
                    ['booking', 'parentBookingId'],
                  ]) ??
                  bookingId)
              .trim();
      final rowKey = booking.rowKey.trim();
      final tripSuffix =
          _sanitizeOperationalTripIdentityToken(legId) ??
          _sanitizeOperationalTripIdentityToken(rowKey);
      final deterministicTripId = tripSuffix == null || tripSuffix.isEmpty
          ? 'planned_$bookingId'
          : 'planned_${bookingId}_$tripSuffix';
      final actorVehicleId = _bookingScopeFirstText(bookingScope, const [
        ['assigned_vehicle_id'],
        ['assignedVehicleId'],
        ['vehicle_id'],
        ['vehicleId'],
        ['booking', 'assigned_vehicle_id'],
        ['booking', 'assignedVehicleId'],
        ['booking', 'vehicle_id'],
        ['booking', 'vehicleId'],
      ]);
      final segmentAmount = _operationalLegDetailNum(booking.details, const [
        ['leg_price_incl_vat'],
        ['legPriceInclVat'],
        ['segment_price_eur'],
        ['booking', 'leg_price_incl_vat'],
        ['booking', 'legPriceInclVat'],
      ]);
      final parentAmount = _operationalLegDetailNum(booking.details, const [
        ['parent_total_price'],
        ['parentTotalPrice'],
        ['parent_price_incl_vat'],
        ['parentPriceInclVat'],
        ['booking_total_eur'],
        ['booking', 'price_incl_vat'],
      ]);
      final pickupLat = _operationalLegDetailNum(booking.details, const [
        ['pickup_lat'],
        ['pickupLat'],
        ['from_lat'],
        ['fromLat'],
        ['origin', 'lat'],
        ['pickup', 'lat'],
      ]);
      final pickupLon = _operationalLegDetailNum(booking.details, const [
        ['pickup_lon'],
        ['pickupLon'],
        ['pickup_lng'],
        ['pickupLng'],
        ['from_lon'],
        ['fromLon'],
        ['from_lng'],
        ['fromLng'],
        ['origin', 'lon'],
        ['origin', 'lng'],
        ['pickup', 'lon'],
        ['pickup', 'lng'],
      ]);
      final dropoffLat = _operationalLegDetailNum(booking.details, const [
        ['dropoff_lat'],
        ['dropoffLat'],
        ['to_lat'],
        ['toLat'],
        ['destination', 'lat'],
        ['dropoff', 'lat'],
      ]);
      final dropoffLon = _operationalLegDetailNum(booking.details, const [
        ['dropoff_lon'],
        ['dropoffLon'],
        ['dropoff_lng'],
        ['dropoffLng'],
        ['to_lon'],
        ['toLon'],
        ['to_lng'],
        ['toLng'],
        ['destination', 'lon'],
        ['destination', 'lng'],
        ['dropoff', 'lon'],
        ['dropoff', 'lng'],
      ]);
      final payload = <String, dynamic>{
        'trip_id': deterministicTripId,
        'booking_id': bookingId,
        'parent_booking_id': parentBookingId,
        'leg_id': legId,
        'leg_type': legType,
        'row_key': rowKey,
        ..._activeBookingScopeQuery(),
        'driver_id': kDriverId,
        'vehicle_id': _directRideVehicleId(),
        'origin': <String, dynamic>{
          'label': (booking.from ?? _receiptText('currentLocation')).toString(),
          if (pickupLat != null) 'lat': pickupLat.toDouble(),
          if (pickupLon != null) 'lon': pickupLon.toDouble(),
        },
        'destination': <String, dynamic>{
          'label': (booking.to ?? booking.from ?? booking.shortId).toString(),
          if (dropoffLat != null) 'lat': dropoffLat.toDouble(),
          if (dropoffLon != null) 'lon': dropoffLon.toDouble(),
        },
        'booking_details': <String, dynamic>{
          ..._plannedBookingDetailsPayload(booking),
          'leg_id': legId,
          'legId': legId,
          'leg_type': legType,
          'legType': legType,
          'row_key': rowKey,
          'rowKey': rowKey,
          'parent_booking_id': parentBookingId,
          'parentBookingId': parentBookingId,
          'is_operational_leg': true,
          'isOperationalLeg': true,
          if (segmentAmount != null) 'segment_price_eur': segmentAmount,
          if (segmentAmount != null) 'leg_price_incl_vat': segmentAmount,
          if (segmentAmount != null) 'legPriceInclVat': segmentAmount,
          if (parentAmount != null) 'booking_total_eur': parentAmount,
        },
        'status': 'stopped',
        'started_at': nowIso,
        'stopped_at': nowIso,
        'km_total': 0,
        'wait_seconds_total': 0,
        if (segmentAmount != null) 'total_eur': segmentAmount.toDouble(),
        'currency': booking.currency ?? kDefaultCurrency,
        ..._driverMutationActorFields(actorVehicleId: actorVehicleId),
      };
      debugPrint(
        '[RIDES][LEG_STATUS][PLANNED_STOP][REQ] trip=$deterministicTripId booking=$bookingId leg=$legId type=$legType',
      );
      final res = await http
          .post(
            _withActiveBookingScope(kWorkerBaseUrl, kRecordPlannedTripStopPath),
            headers: _headers(admin: true),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 10));
      debugPrint(
        '[RIDES][LEG_STATUS][PLANNED_STOP][RES] code=${res.statusCode} trip=$deterministicTripId booking=$bookingId leg=$legId',
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('HTTP ${res.statusCode}');
      }
    } catch (err) {
      debugPrint(
        '[RIDES][LEG_STATUS][PLANNED_STOP][WARN] booking=${booking.bookingId} leg=${booking.legId} err=$err',
      );
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
    final actionKey = _bookingActionKeyForUi(b);
    setState(() => _bookingActionInFlight.add(actionKey));
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
      if (mounted) {
        setState(() => _bookingActionInFlight.remove(actionKey));
        _markBookingsUiDirty();
      }
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
      final parsed = parsePayment(root);
      if (parsed.isNotEmpty) return parsed;
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

  ({
    String source,
    double startFee,
    double perKm,
    double waitPerMin,
    double vatRate,
    String vatMode,
    String currency,
  })
  _resolveDirectRidePricing() {
    final settings = businessSettingsNotifier.value;
    final vat = localBackendTaxProfileNotifier.value;
    final base = settings.pricingBaseFare;
    final perKm = settings.pricingPerKm;
    final wait = settings.pricingWaitPerMinute;
    final settingsUsable =
        base.isFinite &&
        base >= 0 &&
        perKm.isFinite &&
        perKm >= 0 &&
        wait.isFinite &&
        wait >= 0;
    final source = settingsUsable ? 'settings' : 'fallback';
    final vatRateBase = vat?.vatRate ?? settings.pricingVatRate;
    final vatRate =
        (vatRateBase.isFinite ? vatRateBase : settings.pricingVatRate)
            .clamp(0.0, 1.0)
            .toDouble();
    var vatMode = (vat?.vatDisplayMode ?? settings.pricingVatMode)
        .trim()
        .toLowerCase();
    if (vatMode.isEmpty) vatMode = 'incl';
    if (vatMode != 'incl' && vatMode != 'excl') vatMode = 'incl';
    final currency = settings.defaultCurrency.trim().isEmpty
        ? kDefaultCurrency
        : settings.defaultCurrency.trim().toUpperCase();
    return (
      source: source,
      startFee: settingsUsable ? base : _fallbackStartFee,
      perKm: settingsUsable ? perKm : _fallbackPerKm,
      waitPerMin: settingsUsable ? wait : _fallbackWaitPerMin,
      vatRate: vatRate,
      vatMode: vatMode,
      currency: currency,
    );
  }

  double _directRideCustomerTotalFromRaw(double rawTotal) {
    final pricing = _resolveDirectRidePricing();
    if (pricing.vatMode == 'excl') {
      return rawTotal * (1.0 + pricing.vatRate);
    }
    return rawTotal;
  }

  Map<String, dynamic> _directRidePricingSnapshotPayload() {
    final pricing = _resolveDirectRidePricing();
    debugPrint(
      '[DIRECT_RIDE][PRICING_SNAPSHOT] source=${pricing.source} '
      'base=${pricing.startFee.toStringAsFixed(2)} '
      'perKm=${pricing.perKm.toStringAsFixed(2)} '
      'wait=${pricing.waitPerMin.toStringAsFixed(4)} '
      'vatRate=${pricing.vatRate.toStringAsFixed(4)} '
      'vatMode=${pricing.vatMode}',
    );
    return <String, dynamic>{
      'start_fee': pricing.startFee,
      'per_km': pricing.perKm,
      'wait_per_min': pricing.waitPerMin,
      'vat_rate': pricing.vatRate,
      'vat_mode': pricing.vatMode,
      'currency': pricing.currency,
    };
  }

  double get _liveMeterTotalEur {
    final km = _kmDriven;
    final waitMin = _effectiveWaitElapsed.inMilliseconds / 60000.0;
    final pricing = _resolveDirectRidePricing();
    final raw =
        pricing.startFee +
        (km * pricing.perKm) +
        (waitMin * pricing.waitPerMin);
    return _directRideCustomerTotalFromRaw(raw);
  }

  void _debugLiveMeter({required String reason}) {
    final now = DateTime.now();
    final last = _lastMeterDebugAt;
    if (last != null && now.difference(last).inSeconds < 5) return;
    _lastMeterDebugAt = now;
    final waitMin = _effectiveWaitElapsed.inMilliseconds / 60000.0;
    final pricing = _resolveDirectRidePricing();
    final kmCost = _kmDriven * pricing.perKm;
    final waitCost = waitMin * pricing.waitPerMin;
    final raw = pricing.startFee + kmCost + waitCost;
    final total = _directRideCustomerTotalFromRaw(raw);
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

  String _formatDirectRideEstimateText(double amount, String currency) {
    final normalizedCurrency = currency.trim().isEmpty
        ? kDefaultCurrency
        : currency.trim().toUpperCase();
    if (normalizedCurrency == 'EUR') {
      return '€ ${amount.toStringAsFixed(2)}';
    }
    return '$normalizedCurrency ${amount.toStringAsFixed(2)}';
  }

  double? _quoteNumber(dynamic value) {
    if (value is num) {
      final v = value.toDouble();
      return v.isFinite ? v : null;
    }
    if (value is String) {
      var s = value.trim();
      if (s.isEmpty) return null;
      s = s.replaceAll(RegExp(r'[^0-9,\.\-]'), '');
      if (s.contains(',') && !s.contains('.')) s = s.replaceAll(',', '.');
      if (s.contains(',') && s.contains('.')) s = s.replaceAll(',', '');
      final parsed = double.tryParse(s);
      if (parsed == null || !parsed.isFinite) return null;
      return parsed;
    }
    return null;
  }

  String _directRideEstimateCurrencyFrom(dynamic data) {
    if (data is! Map) return kDefaultCurrency;
    final map = Map<String, dynamic>.from(data);
    final direct = map['currency']?.toString().trim();
    if (direct != null && direct.isNotEmpty) return direct.toUpperCase();
    final quote = map['quote'];
    if (quote is Map) {
      final nested = quote['currency']?.toString().trim();
      if (nested != null && nested.isNotEmpty) return nested.toUpperCase();
      final pricing = quote['pricing'];
      if (pricing is Map) {
        final pricingCurrency = pricing['currency']?.toString().trim();
        if (pricingCurrency != null && pricingCurrency.isNotEmpty) {
          return pricingCurrency.toUpperCase();
        }
      }
    }
    final pricing = map['pricing'];
    if (pricing is Map) {
      final pricingCurrency = pricing['currency']?.toString().trim();
      if (pricingCurrency != null && pricingCurrency.isNotEmpty) {
        return pricingCurrency.toUpperCase();
      }
    }
    return kDefaultCurrency;
  }

  double? _extractQuoteEstimateTotal(dynamic data) {
    Map<String, dynamic> asMap(dynamic value) =>
        value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
    final root = asMap(data);
    final quote = asMap(root['quote']);
    final pricing = asMap(root['pricing']);
    final quotePricing = asMap(quote['pricing']);
    final quotePricingMain = asMap(
      quote['pricing_main'] ?? quote['pricingMain'],
    );
    final pricingMain = asMap(root['pricing_main'] ?? root['pricingMain']);
    final candidates = <dynamic>[
      root['total_price_incl_vat'],
      root['price_incl_vat'],
      root['total_price'],
      root['total'],
      root['price'],
      root['amount'],
      root['eur'],
      quote['total_price_incl_vat'],
      quote['price_incl_vat'],
      quote['total_price'],
      quote['total'],
      quote['price'],
      quote['amount'],
      quote['eur'],
      pricing['price_incl_vat'],
      pricing['total_price'],
      pricing['total'],
      pricing['price'],
      pricing['amount'],
      pricing['eur'],
      quotePricing['price_incl_vat'],
      quotePricing['total_price'],
      quotePricing['total'],
      quotePricing['price'],
      quotePricing['amount'],
      quotePricing['eur'],
      quotePricingMain['price_incl_vat'],
      pricingMain['price_incl_vat'],
    ];
    for (final candidate in candidates) {
      final parsed = _quoteNumber(candidate);
      if (parsed != null) return parsed;
    }
    return null;
  }

  void _scheduleDirectRideEstimateRefresh({required String reason}) {
    if (!_directRideDraft) {
      _directRideEstimateDebounce?.cancel();
      return;
    }
    final destination = (_directRideDestinationText ?? '').trim();
    if (destination.isEmpty) {
      _directRideEstimateDebounce?.cancel();
      if (!mounted) return;
      setState(() {
        _directRideEstimatedFare = null;
        _directRideEstimateLoading = false;
        _directRideEstimateError = null;
        _directRideEstimateCurrency = kDefaultCurrency;
        _directRideEstimateSignature = null;
      });
      return;
    }
    _directRideEstimateDebounce?.cancel();
    _directRideEstimateDebounce = Timer(const Duration(milliseconds: 450), () {
      unawaited(_refreshDirectRideEstimate(reason: reason));
    });
  }

  Future<void> _refreshDirectRideEstimate({required String reason}) async {
    final destination = (_directRideDestinationText ?? '').trim();
    final shouldEstimate = _directRideDraft;
    if (!shouldEstimate || destination.isEmpty) return;

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
      if (!mounted) return;
      setState(() {
        _directRideEstimateLoading = false;
        _directRideEstimateError = 'location_unavailable';
      });
      return;
    }

    final pickupText =
        '${pos.longitude.toStringAsFixed(6)},${pos.latitude.toStringAsFixed(6)}';
    final signature =
        '$pickupText|$destination|${_routeKm?.toStringAsFixed(3) ?? '-'}|${_routeDurationSec ?? -1}';
    if (!_directRideEstimateLoading &&
        _directRideEstimateSignature == signature &&
        _directRideEstimatedFare != null) {
      return;
    }

    final requestSeq = ++_directRideEstimateRequestSeq;
    if (mounted) {
      setState(() {
        _directRideEstimateLoading = true;
        _directRideEstimateError = null;
      });
    }

    final settings = businessSettingsNotifier.value;
    final vat = localBackendTaxProfileNotifier.value;
    final vatRateBase = vat?.vatRate ?? settings.pricingVatRate;
    final vatRate =
        (vatRateBase.isFinite ? vatRateBase : settings.pricingVatRate)
            .clamp(0.0, 1.0)
            .toDouble();
    final vatMode = (vat?.vatDisplayMode ?? 'incl').trim().isEmpty
        ? 'incl'
        : (vat?.vatDisplayMode ?? 'incl').trim();
    final scope = _activeBookingScopeQuery();
    final pickupAt = DateTime.now().add(const Duration(minutes: 5));
    String two(int v) => v.toString().padLeft(2, '0');
    final date = '${pickupAt.year}-${two(pickupAt.month)}-${two(pickupAt.day)}';
    final time = '${two(pickupAt.hour)}:${two(pickupAt.minute)}';
    final pickupIso = '${date}T$time:00';

    final body = <String, dynamic>{
      'from': pickupText,
      'to': destination,
      'date': date,
      'time': time,
      'pickup_iso': pickupIso,
      'tier': 'COMFORT',
      'service': 'AIRPORT',
      'pax': 1,
      'bags': 0,
      'wait_min': 0,
      'return': false,
      'return_enabled': false,
      'return_from': '',
      'return_to': '',
      'return_date': '',
      'return_time': '',
      'return_pickup_iso': '',
      'vat_rate': vatRate,
      'vat_mode': vatMode,
      'pricing_profile': <String, dynamic>{
        'base_fare': settings.pricingBaseFare,
        'price_per_km': settings.pricingPerKm,
        'price_per_minute': settings.pricingPerMinute,
        'minimum_fare': settings.pricingMinimumFare,
        'wait_per_minute': settings.pricingWaitPerMinute,
        'return_enabled': settings.pricingReturnEnabled,
        'return_fee': settings.pricingReturnFee,
        'fuel_surcharge': settings.pricingFuelSurcharge,
        'vat_rate': vatRate,
        'vat_mode': vatMode,
      },
      'surcharge_fuel': settings.pricingFuelSurcharge,
      'return_fee': 0,
      'extra_service': 'NONE',
      'extra_service_key': 'NONE',
      ...scope,
    };

    try {
      final uri = _withActiveBookingScope(kBookingBaseUrl, '/quote');
      final res = await http
          .post(uri, headers: _headers(admin: true), body: jsonEncode(body))
          .timeout(const Duration(seconds: 12));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        final bodySnippet = res.body
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim()
            .replaceAll(RegExp(r'[\r\n\t]'), ' ');
        final safeSnippet = bodySnippet.length > 280
            ? '${bodySnippet.substring(0, 280)}...'
            : bodySnippet;
        throw Exception(
          'quote_http_${res.statusCode}${safeSnippet.isNotEmpty ? ': $safeSnippet' : ''}',
        );
      }
      final decoded = jsonDecode(res.body);
      final estimate = _extractQuoteEstimateTotal(decoded);
      if (estimate == null) {
        throw Exception('quote_total_missing');
      }
      if (!mounted || requestSeq != _directRideEstimateRequestSeq) return;
      setState(() {
        _directRideEstimatedFare = estimate;
        _directRideEstimateCurrency = _directRideEstimateCurrencyFrom(decoded);
        _directRideEstimateLoading = false;
        _directRideEstimateError = null;
        _directRideEstimateSignature = signature;
      });
      debugPrint(
        '[DIRECT_RIDE][ESTIMATE][OK] reason=$reason amount=${estimate.toStringAsFixed(2)}',
      );
    } catch (e) {
      if (!mounted || requestSeq != _directRideEstimateRequestSeq) return;
      setState(() {
        _directRideEstimateLoading = false;
        _directRideEstimateError = e.toString();
      });
      debugPrint('[DIRECT_RIDE][ESTIMATE][WARN] reason=$reason error=$e');
    }
  }

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
    final activeCompanyId =
        companyProfileNotifier.value?.companyId.trim().isNotEmpty == true
        ? companyProfileNotifier.value!.companyId.trim()
        : (activeCompanySessionNotifier.value?.companyId.trim().isNotEmpty ==
                  true
              ? activeCompanySessionNotifier.value!.companyId.trim()
              : '');
    final activeDriverId = kDriverId.trim();
    final candidateVehicles = activeCompanyId.isNotEmpty
        // Company-scoped fallback prevents cross-company vehicle reuse in direct rides.
        ? vehiclesNotifier.value
              .where(
                (vehicle) =>
                    (vehicle.companyId?.trim() ?? '') == activeCompanyId,
              )
              .toList(growable: false)
        : vehiclesNotifier.value;

    for (final vehicle in candidateVehicles) {
      if (vehicle.isActive &&
          vehicle.driverId == activeDriverId &&
          vehicle.id.trim().isNotEmpty) {
        return vehicle.id.trim();
      }
    }
    for (final vehicle in candidateVehicles) {
      if (vehicle.isActive && vehicle.id.trim().isNotEmpty) {
        return vehicle.id.trim();
      }
    }
    if (candidateVehicles.isNotEmpty) {
      final firstId = candidateVehicles.first.id.trim();
      if (firstId.isNotEmpty) return firstId;
    }
    if (activeCompanyId.isNotEmpty) return '';
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
    String? normalizeServiceToken(String? raw) {
      final token = raw?.trim();
      if (token == null || token.isEmpty) return null;
      final normalized = token
          .toLowerCase()
          .replaceAll('-', '_')
          .replaceAll(' ', '_');
      if (normalized == 'airport' ||
          normalized == 'airport_transfer' ||
          normalized == 'luchthaven') {
        return 'airport';
      }
      if (normalized == 'business' || normalized == 'zakelijk') {
        return 'business';
      }
      if (normalized == 'passenger' ||
          normalized == 'passenger_transport' ||
          normalized == 'personenvervoer') {
        return 'passenger';
      }
      return normalized;
    }

    String? normalizeTierToken(String? raw) {
      final token = raw?.trim();
      if (token == null || token.isEmpty) return null;
      final normalized = token
          .toLowerCase()
          .replaceAll('-', '_')
          .replaceAll(' ', '_');
      if (normalized == 'comfort' ||
          normalized == 'private' ||
          normalized == 'premium') {
        return normalized;
      }
      return normalized;
    }

    final service = normalizeServiceToken(
      text(
        bookingMap['service_type'] ??
            bookingMap['serviceType'] ??
            bookingMap['service'] ??
            detailMap['service_type'] ??
            detailMap['serviceType'] ??
            detailMap['service'] ??
            payload['service_type'] ??
            payload['serviceType'] ??
            payload['service'] ??
            inputs['service_type'] ??
            inputs['serviceType'] ??
            inputs['service'] ??
            pick([
              ['service_type'],
              ['serviceType'],
              ['service'],
            ]),
      ),
    );
    final tier = normalizeTierToken(
      text(
        booking.tier ??
            bookingMap['tier'] ??
            bookingMap['vehicle_tier'] ??
            bookingMap['vehicleTier'] ??
            detailMap['tier'] ??
            detailMap['vehicle_tier'] ??
            detailMap['vehicleTier'] ??
            payload['tier'] ??
            payload['vehicle_tier'] ??
            payload['vehicleTier'] ??
            inputs['tier'] ??
            inputs['vehicle_tier'] ??
            inputs['vehicleTier'],
      ),
    );
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
      if (service != null) ...{
        'service_type': service,
        'serviceType': service,
        'service': service,
      },
      if (tier != null) ...{
        'tier': tier,
        'vehicle_tier': tier,
        'vehicleTier': tier,
      },
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
        'pricing_snapshot': _directRidePricingSnapshotPayload(),
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
    final strictScope = _strictComplianceScopeFromValues(
      tenantCandidates: <dynamic>[
        details['tenant_id'],
        details['tenantId'],
        _compliancePathText(details, 'booking.tenant_id'),
        _compliancePathText(details, 'booking.tenantId'),
        activeDriverSessionNotifier.value?.tenantId,
      ],
      companyCandidates: <dynamic>[
        details['company_id'],
        details['companyId'],
        _compliancePathText(details, 'booking.company_id'),
        _compliancePathText(details, 'booking.companyId'),
        activeDriverSessionNotifier.value?.companyId,
        companyProfileNotifier.value?.companyId,
        activeCompanySessionNotifier.value?.companyId,
      ],
    );

    return <String, dynamic>{
      'ledger_version': '1.0',
      'ride_id': rideId,
      'ride_type': 'planned',
      'lifecycle_status': 'completed',
      'tenant_id': strictScope?.tenantId ?? '',
      'company_id': strictScope?.companyId ?? '',
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
    final strictScope = _strictComplianceScopeFromValues(
      tenantCandidates: <dynamic>[activeDriverSessionNotifier.value?.tenantId],
      companyCandidates: <dynamic>[
        activeDriverSessionNotifier.value?.companyId,
        companyProfileNotifier.value?.companyId,
        activeCompanySessionNotifier.value?.companyId,
      ],
    );

    return <String, dynamic>{
      'ledger_version': '1.0',
      'ride_id': rideId,
      'ride_type': 'direct',
      'lifecycle_status': 'completed',
      'tenant_id': strictScope?.tenantId ?? '',
      'company_id': strictScope?.companyId ?? '',
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
    unawaited(_refreshCompletedTodayCount(reason: 'trip_stop'));
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

    final settings = buildDriverTrackingLocationSettings();

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
    final destination = await showDialog<DirectRideDestinationResult>(
      context: context,
      builder: (_) => DirectRideDestinationDialog(
        initialText: _directRideDestinationText ?? '',
        search: (query) async {
          final results = await _fetchPlaceSuggestions(query);
          return results
              .map(
                (s) => DirectRideSuggestion(
                  label: s.label,
                  lon: s.lon,
                  lat: s.lat,
                ),
              )
              .toList(growable: false);
        },
        tr: _tr,
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
      _directRideEstimatedFare = null;
      _directRideEstimateLoading = false;
      _directRideEstimateError = null;
      _directRideEstimateCurrency = kDefaultCurrency;
      _directRideEstimateSignature = null;
    });
    _toast('Straatrit klaar. Druk START om te rijden.');
    _scheduleDirectRideEstimateRefresh(reason: 'destination_changed');
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
    return driverMapStyleForTheme(isLightTheme: theme == MapThemeMode.light);
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
    return driverMetersBetween(a, b);
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
    return driverSnapToRouteOn(routeCoords, raw);
  }

  _RouteSnap? _snapToRoute(_LonLat raw) => _snapToRouteOn(_routeCoords, raw);

  double _distanceAlongRouteFor(_LonLat point) {
    return _snapToRoute(point)?.distanceAlongRouteM ?? 0.0;
  }

  double _distanceAlongRouteForCoords(
    List<_LonLat> routeCoords,
    _LonLat point,
  ) {
    return driverDistanceAlongRouteForCoords(routeCoords, point);
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
    return driverRouteCoordsFromSnap(_routeCoords, snap);
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
    return driverRouteBearingAtSnap(_routeCoords, snap);
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
    final nextInstruction = computeDriverNextNavInstruction(
      routeSteps: _routeSteps,
      nextStepIndex: _nextStepIndex,
      posLat: pos.latitude,
      posLon: pos.longitude,
      lastRouteSnap: _lastRouteSnap,
      routeCoords: _routeCoords,
      useMatchedVisual: _useMatchedVisual,
    );
    _nextStepIndex = nextInstruction.nextStepIndex;

    if (nextInstruction.shouldClear) {
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

    final distanceM = nextInstruction.distanceMeters!;
    _logNavBounded(
      'NAV_STEP',
      'progressSource=${nextInstruction.progressSource} nextDistanceM=${distanceM.toStringAsFixed(1)}',
    );

    if (!mounted) {
      _nextNavInstruction = nextInstruction.instruction;
      _nextNavStreet = nextInstruction.street;
      _nextNavDistanceM = distanceM;
      _nextNavType = nextInstruction.type;
      _nextNavModifier = nextInstruction.modifier;
      return;
    }

    setState(() {
      _nextNavInstruction = nextInstruction.instruction;
      _nextNavStreet = nextInstruction.street;
      _nextNavDistanceM = distanceM;
      _nextNavType = nextInstruction.type;
      _nextNavModifier = nextInstruction.modifier;
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
      _scheduleDirectRideEstimateRefresh(reason: 'route_changed');
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
    return driverBearingFromPoints(lat1, lon1, lat2, lon2);
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
      await _clearRouteAndPinAnnotationsOnly();

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
    final lang = _mapboxDirectionsLanguageCode();
    final uri = buildDriverDirectionsUri(
      from: from,
      to: to,
      languageCode: lang,
      accessToken: kMapboxToken,
    );

    final res = await http.get(uri).timeout(const Duration(seconds: 15));

    if (res.statusCode == 401) throw _UnauthorizedMapbox('directions');
    if (res.statusCode != 200) {
      throw Exception('Directions HTTP ${res.statusCode}');
    }

    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final parsed = parseDriverDirectionsResponse(
      response: j,
      localizeInstruction: _localizeNavInstructionMvp,
      distanceAlongRouteForCoords: _distanceAlongRouteForCoords,
    );
    final out = parsed.coords;
    final navSteps = parsed.navSteps;
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
    return (out, parsed.distanceMeters, parsed.durationSeconds);
  }

  String _mapboxDirectionsLanguageCode() {
    final lang = appConfig.currentLanguage;
    if (lang == AppLanguage.fr) return 'fr';
    if (lang == AppLanguage.es) return 'es';
    if (lang == AppLanguage.en) return 'en';
    return 'nl';
  }

  String _localizeNavInstructionMvp(String raw) {
    return localizeDriverNavInstructionMvp(
      raw: raw,
      languageCode: _mapboxDirectionsLanguageCode(),
      tr: _tr,
    );
  }

  String _nextRidePreviewCacheKey(BookingItem booking) {
    final bookingRowKey = booking.rowKey.trim();
    final from = (booking.from ?? '').trim().toLowerCase();
    final to = (booking.to ?? '').trim().toLowerCase();
    final pickupIso = (booking.pickupIso ?? '').trim();
    return '$bookingRowKey|$from|$to|$pickupIso';
  }

  Future<_RoutePreviewData?> _nextRidePreviewFuture(BookingItem booking) {
    final key = _nextRidePreviewCacheKey(booking);
    final cached = _nextRidePreviewCache[key];
    if (cached != null) return cached;
    final future = _loadNextRideRoutePreview(booking);
    _nextRidePreviewCache[key] = future;
    if (_nextRidePreviewCache.length > 16) {
      final oldestKey = _nextRidePreviewCache.keys.first;
      _nextRidePreviewCache.remove(oldestKey);
    }
    return future;
  }

  num? _previewNum(dynamic raw) {
    if (raw is num) return raw;
    if (raw is String) return num.tryParse(raw.trim().replaceAll(',', '.'));
    return null;
  }

  _LonLat? _previewPointFromDetailPaths(
    Map<String, dynamic> details,
    List<List<String>> latPaths,
    List<List<String>> lonPaths,
  ) {
    num? lat;
    num? lon;
    for (final path in latPaths) {
      final v = _previewNum(_getNested(details, path));
      if (v != null) {
        lat = v;
        break;
      }
    }
    for (final path in lonPaths) {
      final v = _previewNum(_getNested(details, path));
      if (v != null) {
        lon = v;
        break;
      }
    }
    if (lat == null || lon == null) return null;
    final latD = lat.toDouble();
    final lonD = lon.toDouble();
    if (!latD.isFinite || !lonD.isFinite) return null;
    if (latD.abs() > 90 || lonD.abs() > 180) return null;
    return _LonLat(lonD, latD);
  }

  ({_LonLat? pickup, _LonLat? dropoff}) _extractPreviewEndpoints(
    BookingItem booking,
  ) {
    final d = booking.details;
    final pickup = _previewPointFromDetailPaths(
      d,
      const [
        ['pickup_lat'],
        ['pickupLat'],
        ['from_lat'],
        ['fromLat'],
        ['pickup', 'lat'],
        ['from', 'lat'],
        ['record', 'pickup_lat'],
        ['record', 'pickup', 'lat'],
        ['record', 'booking', 'pickup_lat'],
        ['record', 'booking', 'pickup', 'lat'],
        ['record', 'booking_details', 'pickup_lat'],
        ['record', 'booking_details', 'pickup', 'lat'],
        ['payload', 'pickup_lat'],
        ['payload', 'pickup', 'lat'],
        ['quote', 'pickup', 'lat'],
        ['quote', 'origin', 'lat'],
      ],
      const [
        ['pickup_lon'],
        ['pickupLng'],
        ['pickupLon'],
        ['from_lon'],
        ['fromLng'],
        ['fromLon'],
        ['pickup', 'lon'],
        ['pickup', 'lng'],
        ['from', 'lon'],
        ['from', 'lng'],
        ['record', 'pickup_lon'],
        ['record', 'pickup', 'lon'],
        ['record', 'pickup', 'lng'],
        ['record', 'booking', 'pickup_lon'],
        ['record', 'booking', 'pickup', 'lon'],
        ['record', 'booking', 'pickup', 'lng'],
        ['record', 'booking_details', 'pickup_lon'],
        ['record', 'booking_details', 'pickup', 'lon'],
        ['record', 'booking_details', 'pickup', 'lng'],
        ['payload', 'pickup_lon'],
        ['payload', 'pickup', 'lon'],
        ['payload', 'pickup', 'lng'],
        ['quote', 'pickup', 'lon'],
        ['quote', 'pickup', 'lng'],
        ['quote', 'origin', 'lon'],
        ['quote', 'origin', 'lng'],
      ],
    );
    final dropoff = _previewPointFromDetailPaths(
      d,
      const [
        ['dropoff_lat'],
        ['dropoffLat'],
        ['to_lat'],
        ['toLat'],
        ['destination_lat'],
        ['destinationLat'],
        ['dropoff', 'lat'],
        ['to', 'lat'],
        ['destination', 'lat'],
        ['record', 'dropoff_lat'],
        ['record', 'dropoff', 'lat'],
        ['record', 'booking', 'dropoff_lat'],
        ['record', 'booking', 'dropoff', 'lat'],
        ['record', 'booking_details', 'dropoff_lat'],
        ['record', 'booking_details', 'dropoff', 'lat'],
        ['payload', 'dropoff_lat'],
        ['payload', 'dropoff', 'lat'],
        ['quote', 'dropoff', 'lat'],
        ['quote', 'destination', 'lat'],
      ],
      const [
        ['dropoff_lon'],
        ['dropoffLng'],
        ['dropoffLon'],
        ['to_lon'],
        ['toLng'],
        ['toLon'],
        ['destination_lon'],
        ['destinationLng'],
        ['destinationLon'],
        ['dropoff', 'lon'],
        ['dropoff', 'lng'],
        ['to', 'lon'],
        ['to', 'lng'],
        ['destination', 'lon'],
        ['destination', 'lng'],
        ['record', 'dropoff_lon'],
        ['record', 'dropoff', 'lon'],
        ['record', 'dropoff', 'lng'],
        ['record', 'booking', 'dropoff_lon'],
        ['record', 'booking', 'dropoff', 'lon'],
        ['record', 'booking', 'dropoff', 'lng'],
        ['record', 'booking_details', 'dropoff_lon'],
        ['record', 'booking_details', 'dropoff', 'lon'],
        ['record', 'booking_details', 'dropoff', 'lng'],
        ['payload', 'dropoff_lon'],
        ['payload', 'dropoff', 'lon'],
        ['payload', 'dropoff', 'lng'],
        ['quote', 'dropoff', 'lon'],
        ['quote', 'dropoff', 'lng'],
        ['quote', 'destination', 'lon'],
        ['quote', 'destination', 'lng'],
      ],
    );
    return (pickup: pickup, dropoff: dropoff);
  }

  Future<List<_LonLat>> _workerRouteForPreview({
    required String fromText,
    required String toText,
  }) async {
    if (fromText.trim().isEmpty || toText.trim().isEmpty)
      return const <_LonLat>[];
    final uri = Uri.parse('$kWorkerBaseUrl$kWorkerRoutePath');
    final payload = <String, dynamic>{
      'from': fromText.trim(),
      'to': toText.trim(),
    };
    final res = await http
        .post(uri, headers: _headers(admin: true), body: jsonEncode(payload))
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return const <_LonLat>[];
    final j = jsonDecode(res.body);
    if (j is! Map<String, dynamic>) return const <_LonLat>[];
    final coordsAny =
        (j['coords'] ?? j['coordinates'] ?? j['route_coords'] ?? j['points']);
    List<dynamic> raw = const <dynamic>[];
    if (coordsAny is List<dynamic>) {
      raw = coordsAny;
    } else if (j['geometry'] is Map<String, dynamic>) {
      raw =
          (j['geometry']['coordinates'] as List<dynamic>? ?? const <dynamic>[]);
    }
    final out = <_LonLat>[];
    for (final c in raw) {
      if (c is List && c.length >= 2) {
        final lon = _previewNum(c[0])?.toDouble();
        final lat = _previewNum(c[1])?.toDouble();
        if (lon != null && lat != null) out.add(_LonLat(lon, lat));
      }
    }
    return out.length >= 2 ? out : const <_LonLat>[];
  }

  Future<List<_LonLat>> _mapboxRouteForPreview({
    required _LonLat from,
    required _LonLat to,
  }) async {
    if (kMapboxToken.trim().isEmpty) return const <_LonLat>[];
    final coords = '${from.lon},${from.lat};${to.lon},${to.lat}';
    final uri = Uri.parse(
      'https://api.mapbox.com/directions/v5/mapbox/driving/$coords'
      '?alternatives=false&geometries=geojson&overview=full'
      '&access_token=$kMapboxToken',
    );
    final res = await http.get(uri).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return const <_LonLat>[];
    final j = jsonDecode(res.body);
    if (j is! Map<String, dynamic>) return const <_LonLat>[];
    final routes = (j['routes'] as List<dynamic>? ?? const <dynamic>[]);
    if (routes.isEmpty) return const <_LonLat>[];
    final r0 = routes.first;
    if (r0 is! Map<String, dynamic>) return const <_LonLat>[];
    final geometry =
        (r0['geometry'] as Map<String, dynamic>? ?? const <String, dynamic>{});
    final line =
        (geometry['coordinates'] as List<dynamic>? ?? const <dynamic>[]);
    final out = <_LonLat>[];
    for (final c in line) {
      if (c is List && c.length >= 2) {
        final lon = _previewNum(c[0])?.toDouble();
        final lat = _previewNum(c[1])?.toDouble();
        if (lon != null && lat != null) out.add(_LonLat(lon, lat));
      }
    }
    return out.length >= 2 ? out : const <_LonLat>[];
  }

  List<_LonLat> _downsamplePreviewRoute(
    List<_LonLat> coords, {
    int maxPoints = 100,
  }) {
    if (coords.length <= maxPoints) return coords;
    final out = <_LonLat>[coords.first];
    final stride = (coords.length - 2) / (maxPoints - 2);
    var cursor = 1.0;
    while (out.length < maxPoints - 1) {
      final idx = cursor.round().clamp(1, coords.length - 2);
      out.add(coords[idx]);
      cursor += stride;
    }
    out.add(coords.last);
    return out;
  }

  String _encodePolyline5(List<_LonLat> points) {
    if (points.isEmpty) return '';
    final sb = StringBuffer();
    var lastLat = 0;
    var lastLon = 0;
    void encodeDelta(int delta) {
      var v = delta < 0 ? ~(delta << 1) : (delta << 1);
      while (v >= 0x20) {
        sb.writeCharCode((0x20 | (v & 0x1f)) + 63);
        v >>= 5;
      }
      sb.writeCharCode(v + 63);
    }

    for (final p in points) {
      final lat = (p.lat * 1e5).round();
      final lon = (p.lon * 1e5).round();
      encodeDelta(lat - lastLat);
      encodeDelta(lon - lastLon);
      lastLat = lat;
      lastLon = lon;
    }
    return sb.toString();
  }

  String _buildStaticRoutePreviewUrl({
    required List<_LonLat> route,
    required _LonLat pickup,
    required _LonLat dropoff,
  }) {
    final compact = _downsamplePreviewRoute(route, maxPoints: 92);
    final polyline = Uri.encodeComponent(_encodePolyline5(compact));
    final overlays =
        'pin-s-a+f4c542(${pickup.lon},${pickup.lat}),'
        'pin-s-b+ff5a4f(${dropoff.lon},${dropoff.lat}),'
        'path-5+2d8cff-0.86($polyline)';
    return 'https://api.mapbox.com/styles/v1/mapbox/navigation-night-v1/static/'
        '$overlays/auto/720x280?padding=34,22,34,22&access_token=$kMapboxToken';
  }

  Future<_RoutePreviewData?> _loadNextRideRoutePreview(
    BookingItem booking,
  ) async {
    if (kMapboxToken.trim().isEmpty) return null;
    final fromText = (booking.from ?? '').trim();
    final toText = (booking.to ?? '').trim();
    if (fromText.isEmpty || toText.isEmpty) return null;

    final endpoints = _extractPreviewEndpoints(booking);
    _LonLat? pickup = endpoints.pickup;
    _LonLat? dropoff = endpoints.dropoff;

    List<_LonLat> routeCoords = await _workerRouteForPreview(
      fromText: fromText,
      toText: toText,
    );
    if (routeCoords.isNotEmpty) {
      pickup ??= routeCoords.first;
      dropoff ??= routeCoords.last;
    }

    if ((pickup == null || dropoff == null) && kMapboxToken.trim().isNotEmpty) {
      try {
        pickup ??= await _geocodeOne(fromText);
        dropoff ??= await _geocodeOne(toText);
      } catch (_) {}
    }
    if (pickup == null || dropoff == null) return null;

    if (routeCoords.length < 2) {
      routeCoords = await _mapboxRouteForPreview(from: pickup, to: dropoff);
    }
    if (routeCoords.length < 2) return null;

    final staticUrl = _buildStaticRoutePreviewUrl(
      route: routeCoords,
      pickup: pickup,
      dropoff: dropoff,
    );
    return _RoutePreviewData(
      staticMapUrl: staticUrl,
      routePointCount: routeCoords.length,
    );
  }

  Widget _buildNextRideRoutePreview(BookingItem booking, {double? height}) {
    final future = _nextRidePreviewFuture(booking);
    return Container(
      height: height ?? 136,
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF0E1012),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x66FFD36A)),
      ),
      child: FutureBuilder<_RoutePreviewData?>(
        future: future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          final data = snap.data;
          if (data == null || data.staticMapUrl.trim().isEmpty) {
            return Center(
              child: Text(
                _tr(
                  nl: 'Route-preview niet beschikbaar',
                  en: 'Route preview unavailable',
                  fr: "Apercu d'itineraire indisponible",
                  es: 'Vista previa de ruta no disponible',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.72),
                  fontWeight: FontWeight.w700,
                  fontSize: 12.2,
                ),
              ),
            );
          }
          return Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                data.staticMapUrl,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, __, ___) => Center(
                  child: Text(
                    _tr(
                      nl: 'Route-preview niet beschikbaar',
                      en: 'Route preview unavailable',
                      fr: "Apercu d'itineraire indisponible",
                      es: 'Vista previa de ruta no disponible',
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.72),
                      fontWeight: FontWeight.w700,
                      fontSize: 12.2,
                    ),
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.center,
                    colors: [
                      Colors.black.withOpacity(0.36),
                      Colors.transparent,
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

  String _navDistanceText(double meters) {
    return driverNavDistanceText(meters);
  }

  bool _navTypeIsArrival(String? type) {
    return driverNavTypeIsArrival(type);
  }

  bool _navTypeIsRoundabout(String? type) {
    return driverNavTypeIsRoundabout(type);
  }

  String _shortNavAction(String instruction, String? type, String? modifier) {
    return driverShortNavAction(instruction, type, modifier, tr: _tr);
  }

  IconData _maneuverIconData(
    String? type,
    String? modifier,
    String instruction,
  ) {
    return driverManeuverIconData(type, modifier, instruction);
  }

  Future<void> _drawPins(_LonLat pickup, _LonLat dropoff) async {
    final mgr = _pinsPointManager;
    if (mgr == null) return;
    final now = DateTime.now();
    final signature = driverPinsDrawSignature(pickup: pickup, dropoff: dropoff);
    if (driverShouldSkipDraw(
      signature: signature,
      lastSignature: _lastPinsDrawSignature,
      lastDrawAt: _lastPinsDrawAt,
      debounce: _routeDrawDebounce,
      now: now,
    )) {
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
    final now = DateTime.now();
    final signature = driverRouteDrawSignature(coords);
    if (driverShouldSkipDraw(
      signature: signature,
      lastSignature: _lastRouteDrawSignature,
      lastDrawAt: _lastRouteDrawAt,
      debounce: _routeDrawDebounce,
      force: force,
      now: now,
    )) {
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
                            ? (pulse * 1.06)
                            : (pulse * 1.18),
                        child: ClipRect(
                          child: SizedBox(
                            width: compactNavHeader ? 132 : 164,
                            height: compactNavHeader ? 46 : 58,
                            child: Center(
                              child: _tenantLogo(
                                height: compactNavHeader ? 38 : 50,
                                fit: BoxFit.contain,
                                fallback: const Icon(
                                  Icons.local_taxi,
                                  size: 32,
                                  color: Colors.white70,
                                ),
                              ),
                            ),
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

  BookingItem? _nextVisibleBookingForDashboard() {
    final visible = _visibleBookings;
    if (visible.isEmpty) return null;
    final now = DateTime.now();
    final upcoming = visible
        .where((b) {
          final raw = (b.pickupIso ?? '').trim();
          if (raw.isEmpty) return true;
          final dt = DateTime.tryParse(raw);
          if (dt == null) return true;
          return !dt.toLocal().isBefore(
            now.subtract(const Duration(minutes: 5)),
          );
        })
        .toList(growable: false);
    final base = upcoming.isNotEmpty ? upcoming : visible;
    final sorted = [...base]
      ..sort((a, b) {
        DateTime normalize(BookingItem item) {
          final raw = (item.pickupIso ?? '').trim();
          final parsed = DateTime.tryParse(raw);
          return parsed?.toLocal() ??
              DateTime.fromMillisecondsSinceEpoch(1 << 62);
        }

        return normalize(a).compareTo(normalize(b));
      });
    return sorted.first;
  }

  String _dashboardDriverName() {
    final session = activeDriverSessionNotifier.value;
    final fullName = session?.fullName.trim() ?? '';
    if (fullName.isNotEmpty) return fullName;
    final employee = session?.employeeNumber.trim() ?? '';
    if (employee.isNotEmpty) return employee;
    return 'chauffeur';
  }

  DriverProfile? _dashboardActiveDriverProfile() {
    final session = activeDriverSessionNotifier.value;
    final sessionDriverId = session?.driverId.trim() ?? '';
    if (sessionDriverId.isEmpty) return null;
    for (final driver in driversNotifier.value) {
      if (driver.id.trim() == sessionDriverId) return driver;
    }
    return null;
  }

  String? _dashboardAvatarPhotoPath() {
    final candidate =
        _dashboardActiveDriverProfile()?.profilePhotoPath?.trim() ?? '';
    if (candidate.isEmpty) return null;
    if (kIsWeb) return null;
    try {
      return File(candidate).existsSync() ? candidate : null;
    } catch (_) {
      return null;
    }
  }

  String? _dashboardAvatarNetworkUrl() {
    bool isHttpUrl(String value) {
      final lower = value.trim().toLowerCase();
      return lower.startsWith('https://') || lower.startsWith('http://');
    }

    bool isPreferredFluxidiMediaUrl(String value) {
      final lower = value.trim().toLowerCase();
      return lower.contains('/public/media/') ||
          lower.contains('public-media/') ||
          lower.contains('/public-media/');
    }

    final profile = _dashboardActiveDriverProfile();
    final session = activeDriverSessionNotifier.value;
    final backendPhoto = (profile?.publicPortraitUrl ?? '').trim();
    final sessionPhoto = (session?.driverPhotoUrl ?? '').trim();

    String source = 'fallback';
    String? selected;
    if (backendPhoto.isNotEmpty && isHttpUrl(backendPhoto)) {
      selected = backendPhoto;
      source = 'backend';
    } else if (sessionPhoto.isNotEmpty && isHttpUrl(sessionPhoto)) {
      selected = sessionPhoto;
      source = 'session';
    }
    if (backendPhoto.isNotEmpty &&
        isPreferredFluxidiMediaUrl(backendPhoto) &&
        sessionPhoto.isNotEmpty &&
        !isPreferredFluxidiMediaUrl(sessionPhoto)) {
      debugPrint(
        '[DRIVER_PHOTO_CANONICAL][LEGACY_IGNORED] driver=${_shortDriverIdForDiag(profile?.id ?? session?.driverId ?? "")} reason=session_legacy_remote_overridden',
      );
    }
    debugPrint(
      '[DRIVER_PHOTO_CANONICAL][SOURCE] driver=${_shortDriverIdForDiag(profile?.id ?? session?.driverId ?? "")} source=$source',
    );
    debugPrint(
      '[DRIVER_PHOTO_CANONICAL][DONE] driver=${_shortDriverIdForDiag(profile?.id ?? session?.driverId ?? "")} urlSource=$source',
    );
    return selected;
  }

  String _dashboardGreeting() {
    final name = _dashboardDriverName();
    if (name.toLowerCase() == 'chauffeur') {
      return _tr(
        nl: 'Welkom chauffeur',
        en: 'Welcome driver',
        fr: 'Bienvenue chauffeur',
        es: 'Bienvenido conductor',
      );
    }
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return _tr(
        nl: 'Goedemorgen, $name!',
        en: 'Good morning, $name!',
        fr: 'Bonjour, $name !',
        es: 'Buenos dias, $name!',
      );
    }
    if (hour < 18) {
      return _tr(
        nl: 'Goedemiddag, $name!',
        en: 'Good afternoon, $name!',
        fr: 'Bon apres-midi, $name !',
        es: 'Buenas tardes, $name!',
      );
    }
    return _tr(
      nl: 'Goedenavond, $name!',
      en: 'Good evening, $name!',
      fr: 'Bonsoir, $name !',
      es: 'Buenas noches, $name!',
    );
  }

  _DriverDashboardStatus _dashboardDriverStatus() {
    final activeRide = _liveRideActive || _isTracking;
    if (activeRide && _isWaiting) return _DriverDashboardStatus.waiting;
    if (activeRide) return _DriverDashboardStatus.busy;

    final hasNavLeg =
        _activeBooking != null ||
        (_cameraMode == _CameraMode.follow &&
            (_activeBooking != null ||
                (_directRideDestinationText ?? '').trim().isNotEmpty));
    if (hasNavLeg) return _DriverDashboardStatus.onTheWay;

    _syncDriverPauseFromProfile(reason: 'dashboard_status_eval');
    if (_driverManualPause) return _DriverDashboardStatus.pause;
    return _DriverDashboardStatus.ready;
  }

  String _dashboardStatusLabel() {
    switch (_dashboardDriverStatus()) {
      case _DriverDashboardStatus.busy:
        return _tr(nl: 'Bezet', en: 'Busy', fr: 'Occupe', es: 'Ocupado');
      case _DriverDashboardStatus.waiting:
        return _tr(
          nl: 'Wachten',
          en: 'Waiting',
          fr: 'En attente',
          es: 'Esperando',
        );
      case _DriverDashboardStatus.onTheWay:
        return _tr(
          nl: 'Onderweg',
          en: 'On the way',
          fr: 'En route',
          es: 'En camino',
        );
      case _DriverDashboardStatus.pause:
        return _tr(nl: 'Pauze', en: 'Pause', fr: 'Pause', es: 'Pausa');
      case _DriverDashboardStatus.ready:
        return _tr(nl: 'Klaar', en: 'Ready', fr: 'Pret', es: 'Listo');
    }
  }

  String _dashboardNextRideTime(BookingItem? booking) {
    if (booking == null) return '—';
    final raw = (booking.pickupIso ?? '').trim();
    if (raw.isEmpty) return '—';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return '—';
    final local = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}';
  }

  bool _isCompletedTripStatusForDashboard(dynamic rawStatus) {
    final status = (rawStatus ?? '')
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
    return status == 'completed' ||
        status == 'stopped' ||
        status == 'finalized' ||
        status == 'finished' ||
        status == 'done' ||
        status == 'closed';
  }

  DateTime? _dashboardTripCompletionLocalDate(Map<String, dynamic> trip) {
    final candidates = <dynamic>[
      trip['stopped_at'],
      trip['stoppedAt'],
      trip['ended_at'],
      trip['endedAt'],
      trip['completed_at'],
      trip['completedAt'],
      trip['created_at'],
      trip['createdAt'],
    ];
    for (final candidate in candidates) {
      final text = candidate?.toString().trim() ?? '';
      if (text.isEmpty) continue;
      final parsed = DateTime.tryParse(text);
      if (parsed != null) return parsed.toLocal();
    }
    return null;
  }

  bool _isSameLocalDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _completedTodayCardValue() {
    if (_completedTodayLoading) return '—';
    return _completedTodayCount?.toString() ?? '—';
  }

  Future<void> _refreshCompletedTodayCount({required String reason}) async {
    if (!mounted) return;
    setState(() => _completedTodayLoading = true);

    try {
      final strictScope = _strictActiveLocalScopeIds();
      if (strictScope == null) {
        debugPrint(
          '[DRIVER_DASHBOARD][COMPLETED_TODAY][SKIP_SCOPE] reason=missing_tenant_company_scope source=$reason',
        );
        if (!mounted) return;
        setState(() {
          _completedTodayCount = null;
          _completedTodayLoading = false;
        });
        return;
      }
      final driverId = kDriverId.trim();
      if (driverId.isEmpty) {
        if (!mounted) return;
        setState(() {
          _completedTodayCount = null;
          _completedTodayLoading = false;
        });
        return;
      }

      final uri = Uri.parse(
        '$kWorkerBaseUrl$kTripsHistoryPath'
        '?tenant_id=${Uri.encodeQueryComponent(strictScope.tenantId)}'
        '&company_id=${Uri.encodeQueryComponent(strictScope.companyId)}'
        '&tenantId=${Uri.encodeQueryComponent(strictScope.tenantId)}'
        '&companyId=${Uri.encodeQueryComponent(strictScope.companyId)}'
        '&driver_id=${Uri.encodeQueryComponent(driverId)}'
        '&limit=200',
      );
      final res = await http
          .get(uri, headers: _headers(admin: true))
          .timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) {
        throw Exception('history_http_${res.statusCode}');
      }

      final decoded = jsonDecode(res.body);
      if (decoded is! Map || decoded['ok'] != true) {
        throw Exception('history_invalid_payload');
      }

      final tripsRaw = decoded['trips'];
      final trips = tripsRaw is List
          ? tripsRaw.whereType<Map>().map((e) => Map<String, dynamic>.from(e))
          : const Iterable<Map<String, dynamic>>.empty();
      final today = DateTime.now();
      final seenTripIds = <String>{};
      var completedToday = 0;
      for (final trip in trips) {
        final tripId = (trip['trip_id'] ?? trip['tripId'] ?? '')
            .toString()
            .trim();
        if (tripId.isNotEmpty && !seenTripIds.add(tripId)) {
          continue;
        }
        if (!_isCompletedTripStatusForDashboard(trip['status'])) continue;
        final completionDate = _dashboardTripCompletionLocalDate(trip);
        if (completionDate == null) continue;
        if (_isSameLocalDay(completionDate, today)) {
          completedToday++;
        }
      }

      if (!mounted) return;
      setState(() {
        _completedTodayCount = completedToday;
        _completedTodayLoading = false;
      });
    } catch (e) {
      debugPrint(
        '[DRIVER_DASHBOARD][COMPLETED_TODAY][WARN] reason=$reason error=$e',
      );
      if (!mounted) return;
      setState(() {
        _completedTodayCount = null;
        _completedTodayLoading = false;
      });
    }
  }

  void _goBackToStartFromDashboard() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RoleEntryPage()),
      (route) => false,
    );
  }

  bool _hasCompanyAdminDriverBridgeContext() {
    return CompanySessionStore.instance.hasValidCompanyContext &&
        _isCompanyAdminDriverViewSession(activeDriverSessionNotifier.value);
  }

  void _goBackToBusinessPageFromDashboard() {
    setAppRole(AppRole.companyAdmin);
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const BusinessHomePage()),
      (route) => false,
    );
  }

  Future<void> _changeDriverViewFromDashboard() async {
    if (!_hasCompanyAdminDriverBridgeContext()) return;
    final selectableDrivers = _resolveSelectableDriverBridgeCandidatesGlobal(
      logCandidates: true,
    );
    if (selectableDrivers.isEmpty) {
      debugPrint('[DRIVER_OWNER_BRIDGE][SKIP] reason=no_selectable_driver');
      _toast(
        _tr(
          nl: 'Geen beschikbare chauffeursweergave gevonden.',
          en: 'No selectable driver view found.',
          fr: 'Aucune vue chauffeur disponible.',
          es: 'No se encontró vista de conductor seleccionable.',
        ),
      );
      return;
    }
    DriverProfile? selectedDriver;
    if (selectableDrivers.length == 1) {
      selectedDriver = selectableDrivers.first;
    } else {
      debugPrint(
        '[DRIVER_OWNER_BRIDGE][PICKER_OPEN] count=${selectableDrivers.length}',
      );
      selectedDriver = await _showDriverOwnerBridgePickerSheet(
        context,
        selectableDrivers: selectableDrivers,
        tr: _tr,
      );
      if (!mounted) return;
    }
    if (selectedDriver == null) return;
    debugPrint(
      '[DRIVER_OWNER_BRIDGE][SELECTED] driver=${_maskBridgeDriverIdGlobal(selectedDriver.id)}',
    );
    await DriverSessionStore.instance.saveFromDriverProfile(
      selectedDriver,
      linkMethodOverride: kCompanyAdminDriverViewLinkMethod,
    );
    await DriverSessionStore.instance.bootstrap(driversNotifier.value);
    if (!mounted) return;
    if (activeDriverSessionNotifier.value != null) {
      setAppRole(AppRole.driver);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const DriverHomePage()),
      );
      return;
    }
    _toast(
      _tr(
        nl: 'Chauffeurweergave kon niet worden geladen.',
        en: 'Could not load driver view.',
        fr: 'Impossible de charger la vue chauffeur.',
        es: 'No se pudo cargar la vista de conductor.',
      ),
    );
  }

  String _dashboardAvatarLabel() {
    final raw = _dashboardDriverName().trim();
    if (raw.isEmpty) return 'D';
    final parts = raw
        .split(RegExp(r'\s+'))
        .where((p) => p.trim().isNotEmpty)
        .toList(growable: false);
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return raw[0].toUpperCase();
  }

  Widget _dashboardAvatarFallback() {
    return Text(
      _dashboardAvatarLabel(),
      style: TextStyle(
        color: Colors.white.withOpacity(0.95),
        fontSize: 13.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.2,
      ),
    );
  }

  Future<void> _handleDriverStatusAction() async {
    if (_driverAvailabilitySaving) return;
    final status = _dashboardDriverStatus();
    final activeRideStatus =
        status == _DriverDashboardStatus.busy ||
        status == _DriverDashboardStatus.waiting ||
        status == _DriverDashboardStatus.onTheWay;
    if (activeRideStatus) {
      _toast(
        _tr(
          nl: 'Je bent bezig met een rit.',
          en: 'You are currently on a ride.',
          fr: 'Vous etes en course.',
          es: 'Estas realizando un viaje.',
        ),
      );
      return;
    }
    final profile = _dashboardActiveDriverProfile();
    if (profile != null && !profile.isActive && _driverManualPause) {
      _toast(
        _tr(
          nl: 'Account is inactief. Vraag je bedrijf om activatie.',
          en: 'Your account is inactive. Ask your company to reactivate it.',
          fr: 'Votre compte est inactif. Demandez une réactivation.',
          es: 'Tu cuenta está inactiva. Solicita reactivación.',
        ),
      );
      return;
    }
    final desired = _driverManualPause ? 'available' : 'paused';
    final safeDriverRef = _shortDriverIdForDiag(
      profile?.id ?? activeDriverSessionNotifier.value?.driverId ?? '',
    );
    debugPrint('[DRIVER_AVAILABILITY][PAUSE_START] driver=$safeDriverRef');
    final sessionBeforeRecovery = activeDriverSessionNotifier.value;
    var token = (sessionBeforeRecovery?.driverSessionToken ?? '').trim();
    if (token.isEmpty) {
      var recoverySource = 'not_attempted';
      debugPrint(
        '[DRIVER_AVAILABILITY][RECOVER_ATTEMPT] has_session=${sessionBeforeRecovery != null} has_token_before=${token.isNotEmpty}',
      );
      try {
        final loadedSession = await DriverSessionStore.instance.load();
        recoverySource = loadedSession == null ? 'load_empty' : 'load_hit';
        await DriverSessionStore.instance.bootstrap(driversNotifier.value);
        recoverySource = '$recoverySource+bootstrap';
      } catch (_) {
        recoverySource = 'load_bootstrap_error';
      }
      final sessionAfterRecovery = activeDriverSessionNotifier.value;
      token = (sessionAfterRecovery?.driverSessionToken ?? '').trim();
      debugPrint(
        '[DRIVER_AVAILABILITY][RECOVER_RESULT] has_session=${sessionAfterRecovery != null} has_token_after=${token.isNotEmpty}',
      );
      if (token.isEmpty) {
        final driverIdPresent =
            (sessionAfterRecovery?.driverId ?? '').trim().isNotEmpty ||
            (profile?.id ?? '').trim().isNotEmpty;
        debugPrint(
          '[DRIVER_AVAILABILITY][BLOCKED_NO_TOKEN] has_session=${sessionAfterRecovery != null} driver_id_present=$driverIdPresent source=$recoverySource',
        );
        _toast(
          _tr(
            nl: 'Chauffeurssessie ontbreekt. Log opnieuw in als chauffeur om je status te wijzigen.',
            en: 'Driver session missing. Please log in as driver again to change your status.',
            fr: 'Session chauffeur manquante. Reconnectez-vous comme chauffeur pour modifier votre statut.',
            es: 'Falta sesión de conductor. Vuelve a iniciar sesión como conductor para cambiar tu estado.',
          ),
        );
        return;
      }
    }
    setState(() => _driverAvailabilitySaving = true);
    try {
      debugPrint(
        '[DRIVER_AVAILABILITY][REQUEST] driver=$safeDriverRef status=$desired endpoint=/public/driver/availability',
      );
      final result = await syncPublicDriverAvailabilityToBackend(
        driverSessionToken: token,
        availabilityStatus: desired,
      );
      debugPrint(
        '[DRIVER_AVAILABILITY][RESPONSE] driver=$safeDriverRef status=${result.statusCode ?? 0} ok=${result.ok}',
      );
      if (!result.ok) {
        debugPrint(
          '[DRIVER_AVAILABILITY][FAILED] driver=$safeDriverRef error=${result.errorCode}',
        );
        _toast(
          _tr(
            nl: 'Status kon niet worden opgeslagen. Probeer opnieuw.',
            en: 'Could not save status. Please try again.',
            fr: 'Le statut n’a pas pu être enregistré.',
            es: 'No se pudo guardar el estado.',
          ),
        );
        return;
      }
      final savedStatus = normalizeDriverAvailabilityState(
        result.availabilityStatus,
        fallback: desired,
      );
      final paused = savedStatus == 'paused';
      if (mounted) {
        setState(() {
          _driverManualPause = paused;
        });
      } else {
        _driverManualPause = paused;
      }
      if (profile != null) {
        final updated = profile.copyWith(availabilityStatus: savedStatus);
        updateDriver(updated.id, updated, syncInventory: false);
        debugPrint(
          '[DRIVER_AVAILABILITY][ADMIN_VISIBLE] driver=$safeDriverRef availability=$savedStatus',
        );
      }
      debugPrint(
        '[DRIVER_AVAILABILITY][SESSION_PATCH] driver=$safeDriverRef availability=$savedStatus',
      );
      if (savedStatus == 'paused') {
        debugPrint(
          '[DRIVER_AVAILABILITY][DISPATCH_EXCLUDE] driver=$safeDriverRef reason=paused',
        );
      }
      _toast(
        paused
            ? _tr(
                nl: 'Status aangepast: Pauze',
                en: 'Status updated: Pause',
                fr: 'Statut mis a jour : Pause',
                es: 'Estado actualizado: Pausa',
              )
            : _tr(
                nl: 'Status aangepast: Klaar',
                en: 'Status updated: Ready',
                fr: 'Statut mis a jour : Pret',
                es: 'Estado actualizado: Listo',
              ),
      );
    } finally {
      if (mounted) {
        setState(() => _driverAvailabilitySaving = false);
      } else {
        _driverAvailabilitySaving = false;
      }
    }
  }

  void _showDashboardMoreSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF101113),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _tr(nl: 'Meer', en: 'More', fr: 'Plus', es: 'Mas'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.calculate_rounded,
                    color: Color(0xFFFFD36A),
                  ),
                  title: Text(
                    _tr(
                      nl: 'Prijs berekenen',
                      en: 'Fare calculator',
                      fr: 'Calcul de tarif',
                      es: 'Calcular tarifa',
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _openCalculatorFromDashboard();
                  },
                ),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.receipt_long_outlined,
                    color: Color(0xFFFFD36A),
                  ),
                  title: Text(
                    _tr(
                      nl: 'Ritbonnen / bewijzen',
                      en: 'Receipts / proofs',
                      fr: 'Recus / preuves',
                      es: 'Recibos / comprobantes',
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    _tr(
                      nl: 'Via afgewerkte ritten in historiek',
                      en: 'Via completed rides in history',
                      fr: 'Via les courses terminees',
                      es: 'Via viajes completados en historial',
                    ),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.62),
                      fontSize: 11.5,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _openTripHistoryFromDashboard();
                  },
                ),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.toggle_on_outlined,
                    color: Color(0xFFFFD36A),
                  ),
                  title: Text(
                    _tr(
                      nl: 'Beschikbaarheid',
                      en: 'Availability',
                      fr: 'Disponibilite',
                      es: 'Disponibilidad',
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    unawaited(_handleDriverStatusAction());
                  },
                ),
                if (_hasCompanyAdminDriverBridgeContext())
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.business_center_outlined,
                      color: Color(0xFFFFD36A),
                    ),
                    title: Text(
                      _tr(
                        nl: 'Terug naar bedrijfspagina',
                        en: 'Back to business page',
                        fr: "Retour a la page entreprise",
                        es: 'Volver a pagina de empresa',
                      ),
                      style: const TextStyle(color: Colors.white),
                    ),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _goBackToBusinessPageFromDashboard();
                    },
                  ),
                if (_hasCompanyAdminDriverBridgeContext())
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.switch_account_outlined,
                      color: Color(0xFFFFD36A),
                    ),
                    title: Text(
                      _tr(
                        nl: 'Chauffeur wijzigen',
                        en: 'Change driver view',
                        fr: 'Changer de vue chauffeur',
                        es: 'Cambiar vista de conductor',
                      ),
                      style: const TextStyle(color: Colors.white),
                    ),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      unawaited(_changeDriverViewFromDashboard());
                    },
                  ),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.home_outlined,
                    color: Color(0xFFFFD36A),
                  ),
                  title: Text(
                    _tr(
                      nl: 'Terug naar startpagina',
                      en: 'Back to start page',
                      fr: "Retour a l'accueil",
                      es: 'Volver al inicio',
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _goBackToStartFromDashboard();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _driverLanguagePill() {
    final code = currentLanguageCode.toUpperCase();
    return PopupMenuButton<String>(
      onSelected: setAppLanguageByCode,
      color: const Color(0xFF111827),
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: const Color(0xFFFFD36A).withOpacity(0.35)),
      ),
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'nl', child: Text('🇳🇱 NL')),
        PopupMenuItem(value: 'en', child: Text('🇬🇧 EN')),
        PopupMenuItem(value: 'fr', child: Text('🇫🇷 FR')),
        PopupMenuItem(value: 'es', child: Text('🇪🇸 ES')),
      ],
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF111214),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0x55FFD36A)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.language_rounded,
              size: 13,
              color: Color(0xFFFFD36A),
            ),
            const SizedBox(width: 4),
            Text(
              code,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 10.3,
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 14,
              color: Color(0xFFFFD36A),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDriverDashboardHeader() {
    final screenW = MediaQuery.of(context).size.width;
    const driverLogoTargetMaxWidth = 260.0;
    final logoWidth = math.min(
      driverLogoTargetMaxWidth,
      math.max(220.0, screenW - 118),
    );
    final logoHeight = logoWidth * 0.39;
    final topBandHeight = math.max(62.0, logoHeight - 34.0);
    const headerIconButtonSize = 46.0;
    const headerIconGlyphSize = 25.0;
    const headerLeftPull = -16.0;
    const headerTopPull = -8.0;
    const logoVisualLift = -14.0;
    final avatarPhotoPath = _dashboardAvatarPhotoPath();
    final avatarPhotoUrl = _dashboardAvatarNetworkUrl();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: headerLeftPull,
            right: -headerLeftPull,
            top: headerTopPull,
          ),
          child: SizedBox(
            height: topBandHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: logoVisualLift,
                  left: 0,
                  child: SizedBox(
                    width: logoWidth,
                    height: logoHeight,
                    child: _tenantLogo(
                      height: logoHeight,
                      fit: BoxFit.contain,
                      fallback: Image.asset(
                        kFluxidiLogoAsset,
                        height: logoHeight,
                        fit: BoxFit.contain,
                        alignment: Alignment.topLeft,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 0,
                  child: Row(
                    children: [
                      _driverLanguagePill(),
                      const SizedBox(width: 8),
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: headerIconButtonSize,
                            height: headerIconButtonSize,
                            decoration: BoxDecoration(
                              color: const Color(0xFF111214),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.10),
                              ),
                            ),
                            child: const Icon(
                              Icons.notifications_none_rounded,
                              color: Colors.white,
                              size: headerIconGlyphSize,
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFFFFD36A),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 8),
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0xFF16181B),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withOpacity(0.20),
                              ),
                            ),
                            child: ClipOval(
                              child: SizedBox.expand(
                                child: avatarPhotoPath == null
                                    ? (avatarPhotoUrl == null
                                          ? Center(
                                              child: _dashboardAvatarFallback(),
                                            )
                                          : Image.network(
                                              avatarPhotoUrl,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) => Center(
                                                child:
                                                    _dashboardAvatarFallback(),
                                              ),
                                            ))
                                    : Image.file(
                                        File(avatarPhotoPath),
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Center(
                                          child: _dashboardAvatarFallback(),
                                        ),
                                      ),
                              ),
                            ),
                          ),
                          Positioned(
                            right: -1,
                            bottom: 1,
                            child: Container(
                              width: 11,
                              height: 11,
                              decoration: BoxDecoration(
                                color: const Color(0xFF2ECC71),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFF050505),
                                  width: 1.2,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDriverSummaryCards({
    required BookingItem? nextRide,
    bool compactLandscape = false,
    double? compactMinHeight,
  }) {
    const summaryIconContainerSize = 52.0;
    const summaryIconGlyphSize = 30.0;
    const compactIconContainerSize = 36.0;
    const compactIconGlyphSize = 20.0;
    Widget card({
      required IconData icon,
      required String label,
      required String value,
      required Color accentColor,
      VoidCallback? onTap,
    }) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          constraints: compactLandscape && compactMinHeight != null
              ? BoxConstraints(minHeight: compactMinHeight)
              : null,
          padding: compactLandscape
              ? const EdgeInsets.fromLTRB(8, 6, 8, 6)
              : const EdgeInsets.fromLTRB(8, 8, 8, 8),
          decoration: BoxDecoration(
            color: const Color(0xFF111214),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
          ),
          child: compactLandscape
              ? Row(
                  children: [
                    Container(
                      width: compactIconContainerSize,
                      height: compactIconContainerSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accentColor.withOpacity(0.16),
                        border: Border.all(
                          color: accentColor.withOpacity(0.55),
                        ),
                      ),
                      child: Icon(
                        icon,
                        size: compactIconGlyphSize,
                        color: accentColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.78),
                          fontSize: 11.2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
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
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: summaryIconContainerSize,
                      height: summaryIconContainerSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accentColor.withOpacity(0.16),
                        border: Border.all(
                          color: accentColor.withOpacity(0.55),
                        ),
                      ),
                      child: Icon(
                        icon,
                        size: summaryIconGlyphSize,
                        color: accentColor,
                      ),
                    ),
                    const SizedBox(height: 7),
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
                    const SizedBox(height: 2),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.66),
                        fontSize: 10.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: card(
            icon: Icons.event_note_rounded,
            accentColor: const Color(0xFF2ECC71),
            label: _tr(
              nl: 'Gepland',
              en: 'Planned',
              fr: 'Prevues',
              es: 'Planificados',
            ),
            value: '${_visibleBookings.length}',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: card(
            icon: Icons.check_circle_outline_rounded,
            accentColor: const Color(0xFF4C9BFF),
            label: _tr(
              nl: 'Voltooid',
              en: 'Completed',
              fr: 'Terminees',
              es: 'Completados',
            ),
            value: _completedTodayCardValue(),
            onTap: _openTripHistoryFromDashboard,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: card(
            icon: Icons.schedule_rounded,
            accentColor: const Color(0xFFFFB54D),
            label: _tr(
              nl: 'Volgende',
              en: 'Next',
              fr: 'Prochaine',
              es: 'Siguiente',
            ),
            value: _dashboardNextRideTime(nextRide),
          ),
        ),
      ],
    );
  }

  Widget _buildNextRideHeroCard({
    required BookingItem? nextRide,
    double? routePreviewHeight,
  }) {
    if (nextRide == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF101113),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.10)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _tr(
                nl: 'Geen ritten gepland',
                en: 'No rides planned',
                fr: 'Aucune course planifiee',
                es: 'No hay viajes planificados',
              ),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _tr(
                nl: 'Haal nieuwe planning op of start een straatrit.',
                en: 'Fetch latest planning or start a direct ride.',
                fr: 'Actualisez le planning ou demarrez une course directe.',
                es: 'Actualiza la planificación o inicia un viaje directo.',
              ),
              style: TextStyle(
                color: Colors.white.withOpacity(0.68),
                fontSize: 11.2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: _ghostButtonStyle(),
                    onPressed: () =>
                        _refreshBookings(force: true, trigger: 'list_manual'),
                    icon: const Icon(Icons.refresh, size: 17),
                    label: Text(
                      _tr(
                        nl: 'Vernieuw',
                        en: 'Refresh',
                        fr: 'Actualiser',
                        es: 'Actualizar',
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    style: _startButtonStyle(),
                    onPressed: _openDirectRideEntry,
                    icon: const Icon(Icons.local_taxi_outlined, size: 18),
                    label: Text(
                      _tr(
                        nl: 'Straatrit starten',
                        en: 'Start direct ride',
                        fr: 'Demarrer course directe',
                        es: 'Iniciar viaje directo',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final pickup = _formatPickup(nextRide.pickupIso);
    final from = (nextRide.from ?? '').trim().isNotEmpty ? nextRide.from! : '—';
    final to = (nextRide.to ?? '').trim().isNotEmpty ? nextRide.to! : '—';
    final tier = (nextRide.tier ?? 'premium').toUpperCase();
    final details = nextRide.details;
    String? detailText(List<String> keys) {
      for (final key in keys) {
        final value = details[key];
        if (value is String && value.trim().isNotEmpty) return value.trim();
      }
      return null;
    }

    num? detailNum(List<String> keys) {
      for (final key in keys) {
        final value = details[key];
        if (value is num) return value;
        if (value is String) {
          final parsed = num.tryParse(value.trim());
          if (parsed != null) return parsed;
        }
      }
      return null;
    }

    final returnRaw = detailText([
      'return_trip',
      'returnTrip',
      'round_trip',
      'roundTrip',
      'is_return',
      'isReturn',
    ]);
    final returnTrip = (returnRaw ?? '').toLowerCase();
    final hasReturnTrip =
        returnTrip == 'true' ||
        returnTrip == '1' ||
        returnTrip == 'yes' ||
        returnTrip == 'ja';
    final legType = (detailText(['leg_type', 'legType']) ?? '')
        .trim()
        .toLowerCase();
    final isOperationalLeg = nextRide.isOperationalLeg;
    String subtypeLabel() {
      if (isOperationalLeg) {
        if (legType == 'return') {
          return _tr(
            nl: 'Terugrit',
            en: 'Return ride',
            fr: 'Trajet retour',
            es: 'Viaje de vuelta',
          );
        }
        return _tr(
          nl: 'Heenrit',
          en: 'Outbound ride',
          fr: 'Trajet aller',
          es: 'Viaje de ida',
        );
      }
      return hasReturnTrip
          ? _tr(nl: 'Retour', en: 'Return', fr: 'Retour', es: 'Regreso')
          : _tr(nl: 'Enkel', en: 'One-way', fr: 'Aller simple', es: 'Solo ida');
    }

    String? serviceChipLabel() {
      final raw =
          (detailText([
                    'service',
                    'service_type',
                    'serviceType',
                    'booking_type',
                    'bookingType',
                  ]) ??
                  '')
              .trim()
              .toLowerCase();
      if (raw.isEmpty) return null;
      if (raw.startsWith('airport') || raw.contains('luchthaven')) {
        return _tr(
          nl: 'Luchthavenvervoer',
          en: 'Airport transfer',
          fr: 'Transfert aeroport',
          es: 'Traslado al aeropuerto',
        );
      }
      return raw
          .replaceAll('_', ' ')
          .split(RegExp(r'\s+'))
          .where((p) => p.isNotEmpty)
          .map(
            (p) => p.length == 1
                ? p.toUpperCase()
                : '${p[0].toUpperCase()}${p.substring(1)}',
          )
          .join(' ');
    }

    final serviceLabel = serviceChipLabel();
    final distanceKm = detailNum([
      'distance_km',
      'distanceKm',
      'distance',
      'route_distance_km',
    ]);
    final durationMin = detailNum([
      'duration_min',
      'durationMin',
      'duration_minutes',
      'duration',
      'estimated_duration_min',
    ]);
    final extraService = detailText([
      'extra_service',
      'extraService',
      'service',
      'service_label',
      'serviceLabel',
      'service_type',
      'serviceType',
      'ride_type',
      'rideType',
    ]);
    final statusText = _rideStatusLabel(
      _effectiveStatusFor(nextRide) ?? 'PENDING',
    );
    Widget metaChip({IconData? icon, required String text}) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF17191C),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0x33FFD36A)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: const Color(0xFFFFD36A)),
              const SizedBox(width: 4),
            ],
            Text(
              text,
              style: const TextStyle(
                color: Color(0xFFF2D691),
                fontSize: 10.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    Widget infoLine({
      required IconData icon,
      required String text,
      Color color = const Color(0xFFFFD36A),
    }) {
      return Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFF3D486),
                fontSize: 10.8,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF101113),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x55FFD36A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _tr(
                    nl: 'Volgende rit',
                    en: 'Next ride',
                    fr: 'Prochaine course',
                    es: 'Siguiente viaje',
                  ),
                  style: TextStyle(
                    color: const Color(0xFFFFD36A).withOpacity(0.95),
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                  ),
                ),
              ),
              metaChip(
                icon: Icons.schedule,
                text: pickup == '—' ? statusText : pickup,
              ),
            ],
          ),
          const SizedBox(height: 9),
          infoLine(icon: Icons.radio_button_checked, text: from),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Icon(
              Icons.south_rounded,
              size: 14,
              color: Colors.white.withOpacity(0.35),
            ),
          ),
          const SizedBox(height: 2),
          infoLine(icon: Icons.flag_rounded, text: to),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              metaChip(icon: Icons.workspace_premium_rounded, text: tier),
              metaChip(
                icon: Icons.person_rounded,
                text: '${nextRide.pax ?? 0} pax',
              ),
              metaChip(
                icon: Icons.luggage_rounded,
                text: '${nextRide.bags ?? 0} bagage',
              ),
              metaChip(
                icon: Icons.compare_arrows_rounded,
                text: subtypeLabel(),
              ),
              if (serviceLabel != null)
                metaChip(icon: Icons.local_taxi_rounded, text: serviceLabel),
              if (extraService != null)
                metaChip(
                  icon: Icons.miscellaneous_services_rounded,
                  text: extraService,
                ),
              metaChip(icon: Icons.info_outline_rounded, text: statusText),
              if (distanceKm != null)
                metaChip(
                  icon: Icons.straighten_rounded,
                  text: '${distanceKm.toStringAsFixed(1)} km',
                ),
              if (durationMin != null)
                metaChip(
                  icon: Icons.timer_outlined,
                  text: '${durationMin.round()} min',
                ),
              if (nextRide.price != null)
                metaChip(
                  icon: Icons.payments_outlined,
                  text:
                      'Totaal ${_fmtMoney(nextRide.price!, nextRide.currency ?? 'EUR')}',
                ),
            ],
          ),
          const SizedBox(height: 8),
          _buildNextRideRoutePreview(nextRide, height: routePreviewHeight),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: _ghostButtonStyle(),
                  onPressed: () async {
                    await _goToRide(nextRide);
                    if (!mounted) return;
                    await _openNavigation();
                  },
                  icon: const Icon(Icons.navigation_outlined, size: 15),
                  label: const Text('Navigeer'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  style: _startButtonStyle(),
                  onPressed: () async {
                    await _goToRide(nextRide);
                  },
                  icon: const Icon(Icons.chevron_right_rounded, size: 15),
                  label: const Text('Ga naar rit'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDriverQuickActionsGrid({
    bool isTabletPortrait = false,
    double? tabletPortraitCardMinHeight,
    bool isTabletLandscape = false,
    int? forcedColumns,
    double? landscapeCardMinHeight,
    double? landscapeSpacing,
    bool compactLandscape = false,
    bool useImageBackgrounds = false,
    double? tabletPortraitSpacing,
  }) {
    const quickActionIconContainerSize = 56.0;
    const quickActionIconGlyphSize = 31.0;
    Widget quickAction({
      required IconData icon,
      required String title,
      String subtitle = '',
      required VoidCallback onTap,
      bool active = false,
      String? backgroundAsset,
    }) {
      final hasImageBackground =
          useImageBackgrounds && (backgroundAsset ?? '').trim().isNotEmpty;
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: BoxConstraints(
            minHeight: isTabletPortrait
                ? (tabletPortraitCardMinHeight ?? 120.0)
                : isTabletLandscape
                ? (landscapeCardMinHeight ?? 98.0)
                : 68.0,
          ),
          decoration: BoxDecoration(
            color: hasImageBackground
                ? const Color(0xFF0A0A0A).withOpacity(0.88)
                : const Color(0xFF111111).withOpacity(0.96),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: active
                  ? const Color(0x66FFD36A)
                  : Colors.white.withOpacity(0.12),
            ),
          ),
          child: Stack(
            children: [
              if (hasImageBackground)
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.asset(
                      backgroundAsset!,
                      fit: BoxFit.cover,
                      alignment: Alignment.centerRight,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              if (hasImageBackground)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.16),
                          Colors.black.withOpacity(0.26),
                          Colors.black.withOpacity(0.56),
                        ],
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: EdgeInsets.all(compactLandscape ? 8 : 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: quickActionIconContainerSize,
                      height: quickActionIconContainerSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: active
                            ? const Color(0xFF21180A)
                            : const Color(0xFF17130B),
                        border: Border.all(
                          color: active
                              ? const Color(0x88FFD36A)
                              : const Color(0x55FFD36A),
                        ),
                      ),
                      child: Icon(
                        icon,
                        color: const Color(0xFFFFD36A),
                        size: quickActionIconGlyphSize,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 10.4,
                            ),
                          ),
                          if (subtitle.trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.67),
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        final gap = isTabletPortrait
            ? (tabletPortraitSpacing ?? 11.0)
            : isTabletLandscape
            ? (landscapeSpacing ?? 8.0)
            : 8.0;
        int columns;
        if (isTabletPortrait) {
          columns = 2;
        } else if (isTabletLandscape) {
          columns = forcedColumns ?? 3;
          final preferredWidth = (c.maxWidth - (gap * (columns - 1))) / columns;
          if (preferredWidth < 105.0) {
            columns = 2;
          }
        } else {
          const minTileWidth = 162.0;
          columns = (c.maxWidth / minTileWidth).floor();
          columns = columns.clamp(2, 4);
        }
        final width = (c.maxWidth - (gap * (columns - 1))) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            SizedBox(
              width: width,
              child: quickAction(
                icon: Icons.local_taxi_outlined,
                title: _tr(
                  nl: 'Straatrit',
                  en: 'Street ride',
                  fr: 'Course directe',
                  es: 'Viaje directo',
                ),
                onTap: _openDirectRideEntry,
                backgroundAsset: 'assets/fluxidi/driver_action_street_ride.png',
              ),
            ),
            SizedBox(
              width: width,
              child: quickAction(
                icon: Icons.calculate_rounded,
                title: _tr(
                  nl: 'Prijs berekenen',
                  en: 'Fare calculator',
                  fr: 'Calcul de tarif',
                  es: 'Calcular tarifa',
                ),
                onTap: _openCalculatorFromDashboard,
                backgroundAsset:
                    'assets/fluxidi/driver_action_fare_calculator.png',
              ),
            ),
            SizedBox(
              width: width,
              child: quickAction(
                icon: Icons.list_alt_rounded,
                title: _tr(
                  nl: 'Mijn ritten',
                  en: 'My rides',
                  fr: 'Mes courses',
                  es: 'Mis viajes',
                ),
                onTap: _openBookingsHubFromDashboard,
                backgroundAsset: 'assets/fluxidi/driver_action_my_rides.png',
              ),
            ),
            SizedBox(
              width: width,
              child: quickAction(
                icon: Icons.history_rounded,
                title: _tr(
                  nl: 'Historiek',
                  en: 'History',
                  fr: 'Historique',
                  es: 'Historial',
                ),
                onTap: _openTripHistoryFromDashboard,
                backgroundAsset: 'assets/fluxidi/driver_action_history.png',
              ),
            ),
            SizedBox(
              width: width,
              child: quickAction(
                icon: Icons.receipt_long_outlined,
                title: _tr(
                  nl: 'Ritbonnen',
                  en: 'Receipts',
                  fr: 'Recus',
                  es: 'Recibos',
                ),
                onTap: _openTripHistoryFromDashboard,
                backgroundAsset: 'assets/fluxidi/driver_action_receipts.png',
              ),
            ),
            SizedBox(
              width: width,
              child: quickAction(
                icon: Icons.folder_copy_outlined,
                title: _tr(
                  nl: 'Documenten',
                  en: 'Documents',
                  fr: 'Documents',
                  es: 'Documentos',
                ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const DriverMyDocumentsPage(),
                    ),
                  );
                },
                backgroundAsset: 'assets/fluxidi/driver_action_documents.png',
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPremiumDriverDashboard() {
    const navIconSize = 25.0;
    final nextRide = _nextVisibleBookingForDashboard();
    final driverName = _dashboardDriverName();
    final statusKind = _dashboardDriverStatus();
    final statusLabel = _dashboardStatusLabel();
    final statusReady = statusKind == _DriverDashboardStatus.ready;
    double clampDouble(double v, double min, double max) =>
        v < min ? min : (v > max ? max : v);
    final size = MediaQuery.sizeOf(context);
    final W = size.width;
    final H = size.height;
    final screenClass = FluxidiBreakpoints.classifyWidth(W);
    final isTabletPortrait =
        (screenClass == FluxidiScreenClass.tablet ||
            screenClass == FluxidiScreenClass.desktop) &&
        W < H &&
        H >= 900;
    final isTabletLandscape =
        (screenClass == FluxidiScreenClass.tablet ||
            screenClass == FluxidiScreenClass.desktop) &&
        W > H &&
        H >= 700;
    final driverHeaderHeight = isTabletPortrait
        ? clampDouble(H * 0.24, 300.0, 360.0)
        : 0.0;
    final driverLandscapeHeaderHeight = isTabletLandscape
        ? clampDouble(H * 0.19, 140.0, 185.0)
        : 0.0;
    final driverQuickActionCardMinHeight = isTabletPortrait
        ? clampDouble(H * 0.12, 110.0, 140.0)
        : 68.0;
    final driverQuickActionGap = isTabletPortrait ? 11.0 : 8.0;
    final driverLandscapeQuickActionCardMinHeight = isTabletLandscape
        ? clampDouble(H * 0.175, 132.0, 162.0)
        : 98.0;
    final driverLandscapeQuickActionGap = isTabletLandscape ? 8.0 : 8.0;
    final driverLandscapeSummaryCardMinHeight = isTabletLandscape
        ? clampDouble(H * 0.09, 70.0, 86.0)
        : 70.0;
    final driverLandscapeRoutePreviewHeight = isTabletLandscape
        ? clampDouble(H * 0.24, 170.0, 220.0)
        : 136.0;
    final driverScrollBottomPadding = isTabletLandscape ? 18.0 : 10.0;
    Widget sectionTitle(String text) {
      return Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13.5,
          fontWeight: FontWeight.w800,
        ),
      );
    }

    Widget navItem({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
      bool active = false,
    }) {
      final color = active ? const Color(0xFFFFD36A) : Colors.white70;
      return Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: navIconSize, color: color),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 10.1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget driverIdentityBlock() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _tr(
              nl: 'Chauffeur',
              en: 'Driver',
              fr: 'Chauffeur',
              es: 'Conductor',
            ),
            style: TextStyle(
              color: Colors.white.withOpacity(0.72),
              fontSize: 13.2,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.30,
            ),
          ),
          const SizedBox(height: 1),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  driverName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: _handleDriverStatusAction,
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF101113),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: statusReady
                          ? const Color(0x664CD964)
                          : const Color(0x66FFD36A),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: statusReady
                              ? const Color(0xFF2ECC71)
                              : const Color(0xFFFFD36A),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        statusLabel,
                        style: TextStyle(
                          color: statusReady
                              ? const Color(0xFFBCF6D0)
                              : const Color(0xFFFFE4A8),
                          fontWeight: FontWeight.w800,
                          fontSize: 11.5,
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: Colors.white54,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }

    return ColoredBox(
      color: const Color(0xFF050505),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  14,
                  2,
                  14,
                  driverScrollBottomPadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isTabletPortrait) ...[
                      Container(
                        height: driverHeaderHeight,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0x55FFD36A)),
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.asset(
                              'assets/fluxidi/driver_header_portrait_tablet.png',
                              fit: BoxFit.cover,
                              alignment: Alignment.centerRight,
                              errorBuilder: (_, __, ___) => const DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Color(0xFF101010),
                                      Color(0xFF07080C),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.black.withOpacity(0.16),
                                      Colors.black.withOpacity(0.26),
                                      Colors.black.withOpacity(0.56),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Positioned.fill(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  10,
                                  8,
                                  10,
                                  10,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildDriverDashboardHeader(),
                                    const Spacer(),
                                    driverIdentityBlock(),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      _buildDriverSummaryCards(nextRide: nextRide),
                      const SizedBox(height: 10),
                      _buildNextRideHeroCard(nextRide: nextRide),
                      const SizedBox(height: 10),
                      sectionTitle(
                        _tr(
                          nl: 'Snelle acties',
                          en: 'Quick actions',
                          fr: 'Actions rapides',
                          es: 'Acciones rapidas',
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildDriverQuickActionsGrid(
                        isTabletPortrait: isTabletPortrait,
                        tabletPortraitCardMinHeight:
                            driverQuickActionCardMinHeight,
                        useImageBackgrounds: isTabletPortrait,
                        tabletPortraitSpacing: driverQuickActionGap,
                      ),
                    ] else if (isTabletLandscape) ...[
                      Container(
                        height: driverLandscapeHeaderHeight,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0x55FFD36A)),
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.asset(
                              'assets/fluxidi/driver_header_landscape_tablet.png',
                              fit: BoxFit.cover,
                              alignment: Alignment.center,
                              errorBuilder: (_, __, ___) => const DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Color(0xFF101010),
                                      Color(0xFF07080C),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.black.withOpacity(0.20),
                                      Colors.black.withOpacity(0.32),
                                      Colors.black.withOpacity(0.62),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Positioned.fill(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  10,
                                  6,
                                  10,
                                  8,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildDriverDashboardHeader(),
                                    const SizedBox(height: 2),
                                    driverIdentityBlock(),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 60,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildDriverSummaryCards(
                                  nextRide: nextRide,
                                  compactLandscape: true,
                                  compactMinHeight:
                                      driverLandscapeSummaryCardMinHeight,
                                ),
                                const SizedBox(height: 10),
                                _buildNextRideHeroCard(
                                  nextRide: nextRide,
                                  routePreviewHeight:
                                      driverLandscapeRoutePreviewHeight,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            flex: 40,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                sectionTitle(
                                  _tr(
                                    nl: 'Snelle acties',
                                    en: 'Quick actions',
                                    fr: 'Actions rapides',
                                    es: 'Acciones rapidas',
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _buildDriverQuickActionsGrid(
                                  isTabletLandscape: true,
                                  forcedColumns: 2,
                                  landscapeCardMinHeight:
                                      driverLandscapeQuickActionCardMinHeight,
                                  landscapeSpacing:
                                      driverLandscapeQuickActionGap,
                                  compactLandscape: true,
                                  useImageBackgrounds: true,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      _buildDriverDashboardHeader(),
                      const SizedBox(height: 1),
                      driverIdentityBlock(),
                      const SizedBox(height: 6),
                      _buildDriverSummaryCards(nextRide: nextRide),
                      const SizedBox(height: 10),
                      _buildNextRideHeroCard(nextRide: nextRide),
                      const SizedBox(height: 10),
                      sectionTitle(
                        _tr(
                          nl: 'Snelle acties',
                          en: 'Quick actions',
                          fr: 'Actions rapides',
                          es: 'Acciones rapidas',
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildDriverQuickActionsGrid(
                        isTabletPortrait: isTabletPortrait,
                        tabletPortraitCardMinHeight:
                            driverQuickActionCardMinHeight,
                        useImageBackgrounds: isTabletPortrait,
                        tabletPortraitSpacing: driverQuickActionGap,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Container(
              margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF101113),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.10)),
              ),
              child: Row(
                children: [
                  navItem(
                    icon: Icons.home_filled,
                    label: _tr(
                      nl: 'Home',
                      en: 'Home',
                      fr: 'Accueil',
                      es: 'Inicio',
                    ),
                    active: true,
                    onTap: () {},
                  ),
                  navItem(
                    icon: Icons.list_alt_rounded,
                    label: _tr(
                      nl: 'Ritten',
                      en: 'Rides',
                      fr: 'Courses',
                      es: 'Viajes',
                    ),
                    onTap: _openBookingsHubFromDashboard,
                  ),
                  navItem(
                    icon: Icons.local_taxi_outlined,
                    label: _tr(
                      nl: 'Straatrit',
                      en: 'Street ride',
                      fr: 'Course directe',
                      es: 'Viaje directo',
                    ),
                    onTap: _openDirectRideEntry,
                  ),
                  navItem(
                    icon: Icons.menu_rounded,
                    label: _tr(nl: 'Meer', en: 'More', fr: 'Plus', es: 'Mas'),
                    onTap: _showDashboardMoreSheet,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------
  // UI
  // -------------------------------

  Widget _buildHintPanel() {
    return _buildPremiumDriverDashboard();
  }

  Widget _buildTurnInstructionBanner({required bool compact}) {
    final dist = _nextNavDistanceM ?? 0.0;
    final instruction = (_nextNavInstruction ?? '').trim();
    final street = (_nextNavStreet ?? '').trim();
    final action = _shortNavAction(instruction, _nextNavType, _nextNavModifier);
    final distanceText = _navDistanceText(dist);
    final isArrival = _navTypeIsArrival(_nextNavType);
    final line1 = _navTypeIsArrival(_nextNavType)
        ? action
        : _tr(
            nl: 'Over ${_navDistanceText(dist)} $action',
            en: 'In ${_navDistanceText(dist)} $action',
            fr: 'Dans ${_navDistanceText(dist)} $action',
            es: 'En ${_navDistanceText(dist)} $action',
          );
    final icon = _maneuverIconData(_nextNavType, _nextNavModifier, instruction);
    return DriverTurnInstructionBanner(
      compact: compact,
      isArrival: isArrival,
      distanceText: distanceText,
      line1: line1,
      street: street,
      icon: icon,
    );
  }

  Widget _buildNavLoadingBanner({required bool compact}) {
    return DriverNavLoadingBanner(compact: compact);
  }

  Widget _buildNoNavInstructionsBanner({required bool compact}) {
    return DriverNoNavInstructionsBanner(compact: compact);
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
          if (!showCockpit)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: const Color(0xFF040404).withOpacity(0.985),
                ),
              ),
            ),

          // Top status / header (Fluxidi strip).
          if (showCockpit &&
              !collapseTopBarInLandscapeNav &&
              !collapseTopBarInPortraitNav)
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              left: 12,
              right: 12,
              child: _buildStatusStrip(state),
            ),
          if (showCockpit &&
              (collapseTopBarInLandscapeNav || collapseTopBarInPortraitNav))
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 10,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.26),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.14),
                          ),
                        ),
                        child: IconButton(
                          tooltip: 'Menu',
                          onPressed: () =>
                              _scaffoldKey.currentState?.openDrawer(),
                          icon: const Icon(Icons.menu_rounded, size: 22),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IgnorePointer(
                    child: Container(
                      width: isLandscape ? 146 : 124,
                      height: isLandscape ? 48 : 44,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.38),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0x66FFD36A)),
                      ),
                      child: Center(
                        child: SizedBox(
                          width: double.infinity,
                          child: _tenantLogo(
                            height: isLandscape ? 36 : 30,
                            fit: BoxFit.contain,
                            fallback: Image.asset(
                              kFluxidiLogoAsset,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) =>
                                  const SizedBox.shrink(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
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

          if (!showCockpit) Positioned.fill(child: _buildHintPanel()),

          // Bottom overlay layer (cockpit only).
          if (showCockpit)
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeOut,
                child: isLandscape
                    ? SafeArea(
                        key: const ValueKey<String>('landscape_cockpit'),
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Padding(
                            padding: EdgeInsets.only(
                              left: 10,
                              right: 10,
                              bottom:
                                  MediaQuery.of(context).viewInsets.bottom + 4,
                            ),
                            child: SizedBox(
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
                                  _buildDirectRideEstimatePanel(),
                                  if (showExternalNavButtons)
                                    _buildExternalNavButtons(),
                                ],
                              ),
                            ),
                          ),
                        ),
                      )
                    : SafeArea(
                        key: const ValueKey<String>('portrait_cockpit'),
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
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CockpitWidget(
                                  etaText: _etaText,
                                  kmText: _kmRemainingText,
                                  priceText: _cockpitPriceText,
                                  tripStarted: _liveRideActive,
                                  isWaiting: _isWaiting,
                                  navActive: _cameraMode == _CameraMode.follow,
                                  onNav: _openNavigation,
                                  onStart: _handleCockpitStart,
                                  onStop: _stopTrip,
                                  onWait: _enterWaitMode,
                                  onGo: _exitWaitMode,
                                ),
                                _buildDirectRideEstimatePanel(),
                                if (showExternalNavButtons)
                                  _buildExternalNavButtons(),
                              ],
                            ),
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
    final emptyTitle = _tr(
      nl: 'Geen ritten klaar',
      en: 'No rides ready',
      fr: 'Aucune course prête',
      es: 'No hay viajes listos',
    );
    final emptyBody = _tr(
      nl: 'Nieuwe boekingen verschijnen hier zodra ze aan jou of je bedrijf zijn gekoppeld.',
      en: 'New bookings appear here once they are assigned to you or your company.',
      fr: 'Les nouvelles réservations apparaissent ici dès qu’elles sont liées à vous ou à votre entreprise.',
      es: 'Las nuevas reservas aparecerán aquí cuando estén vinculadas a ti o a tu empresa.',
    );
    final emptyInfoTitle = _tr(
      nl: 'Geen rit gevonden?',
      en: 'No ride found?',
      fr: 'Aucune course trouvée ?',
      es: '¿No encontraste un viaje?',
    );
    final emptyInfoBody = _tr(
      nl: 'Er zijn momenteel geen ritten beschikbaar. Trek omlaag om te vernieuwen.',
      en: 'There are currently no rides available. Pull down to refresh.',
      fr: 'Aucune course n’est disponible pour le moment. Tirez vers le bas pour actualiser.',
      es: 'Actualmente no hay viajes disponibles. Desliza hacia abajo para actualizar.',
    );
    return Column(
      mainAxisSize: MainAxisSize.max,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: const Color(0xFF101113),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kFluxidiYellow.withOpacity(0.30)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _ridesSegmentChip(
                  label: _tr(
                    nl: 'Beschikbaar',
                    en: 'Available',
                    fr: 'Disponibles',
                    es: 'Disponibles',
                  ),
                  active: true,
                ),
                const SizedBox(width: 6),
                _ridesSegmentChip(
                  label: _tr(
                    nl: 'Mijn ritten',
                    en: 'My rides',
                    fr: 'Mes courses',
                    es: 'Mis viajes',
                  ),
                ),
                const SizedBox(width: 6),
                _ridesSegmentChip(
                  label: _tr(
                    nl: 'Historiek',
                    en: 'History',
                    fr: 'Historique',
                    es: 'Historial',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (_loadingBookings)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 18),
            decoration: BoxDecoration(
              color: const Color(0xFF101113),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: kFluxidiYellow.withOpacity(0.30)),
            ),
            child: Column(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: kFluxidiYellow,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _tr(
                    nl: 'Ritten worden geladen...',
                    en: 'Loading rides...',
                    fr: 'Chargement des courses...',
                    es: 'Cargando viajes...',
                  ),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.78),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          )
        else if (_bookingsError != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1B1212),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF7A2A2A).withOpacity(0.8),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _tr(
                    nl: 'Ritten konden niet geladen worden.',
                    en: 'Could not load rides.',
                    fr: 'Impossible de charger les courses.',
                    es: 'No se pudieron cargar los viajes.',
                  ),
                  style: const TextStyle(
                    color: Color(0xFFFFB3B3),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Error: $_bookingsError',
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ],
            ),
          )
        else if (visibleBookings.isEmpty)
          Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF101113),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: kFluxidiYellow.withOpacity(0.30)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      emptyTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      emptyBody,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.72),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF101113),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: kFluxidiYellow.withOpacity(0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      emptyInfoTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      emptyInfoBody,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.70),
                        fontSize: 12.4,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
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

  bool _bookingIsOperationalLeg(BookingItem b) {
    return b.isOperationalLeg;
  }

  bool _bookingIsRoundtripParent(BookingItem b) {
    final token =
        (b.details['is_roundtrip_parent'] ??
                b.details['isRoundtripParent'] ??
                '')
            .toString()
            .trim()
            .toLowerCase();
    return token == 'true' || token == '1';
  }

  String _bookingLegType(BookingItem b) {
    return (b.details['leg_type'] ?? b.details['legType'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
  }

  String _bookingLegLabel(BookingItem b) {
    final legType = _bookingLegType(b);
    if (legType == 'return') {
      return _tr(
        nl: 'Terugrit',
        en: 'Return ride',
        fr: 'Trajet retour',
        es: 'Viaje de vuelta',
      );
    }
    if (legType == 'outbound') {
      return _tr(
        nl: 'Heenrit',
        en: 'Outbound ride',
        fr: 'Trajet aller',
        es: 'Viaje de ida',
      );
    }
    return _tr(
      nl: 'Geplande rit',
      en: 'Planned ride',
      fr: 'Course planifiée',
      es: 'Viaje planificado',
    );
  }

  Widget _bookingCard(BookingItem b) {
    final dt = _formatPickup(b.pickupIso);
    final actionBusy = _bookingActionInFlight.contains(
      _bookingActionKeyForUi(b),
    );
    final cardReference = _driverCardReferenceDisplay(b);
    final isOperationalLeg = _bookingIsOperationalLeg(b);
    final isRoundtripParent = _bookingIsRoundtripParent(b);
    final legLabel = _bookingLegLabel(b);
    final parentBookingId =
        (b.details['parent_booking_id'] ?? b.details['parentBookingId'] ?? '')
            .toString()
            .trim();
    final customerName =
        _bookingScopeFirstText(_bookingScopeViewFor(b), const [
          ['customer_name'],
          ['customerName'],
          ['customer', 'name'],
          ['booking', 'customer_name'],
          ['booking', 'customerName'],
          ['booking', 'customer', 'name'],
        ]) ??
        '';

    return LayoutBuilder(
      builder: (context, c) {
        final compactPortrait =
            c.maxWidth < 390 &&
            MediaQuery.of(context).orientation == Orientation.portrait;
        final narrow = c.maxWidth < 380;
        final tight = c.maxWidth < 340;
        final actionHeight = narrow ? 40.0 : 38.0;
        final statusText = _rideStatusLabel(
          (_effectiveStatusFor(b) ?? 'PENDING'),
        );
        final referenceChipText =
            '${cardReference.label}: ${cardReference.value}';
        final bagLabel = _tr(
          nl: '${b.bags ?? 0} bagage',
          en: '${b.bags ?? 0} bags',
          fr: '${b.bags ?? 0} bagages',
          es: '${b.bags ?? 0} equipaje',
        );
        final goToRideLabel = _tr(
          nl: 'Ga naar rit',
          en: 'Open ride',
          fr: 'Aller à la course',
          es: 'Ir al viaje',
        );

        if (compactPortrait) {
          final compactActionHeight = 36.0;
          return Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF151515), Color(0xFF0B0B0B)],
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: kFluxidiYellow.withOpacity(0.24)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.24),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _pill(
                  icon: Icons.schedule,
                  text: dt,
                  borderColor: const Color(0x55FFD36A),
                  textColor: const Color(0xFFFFD98A),
                  compact: true,
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 34,
                      child: Column(
                        children: [
                          Container(
                            width: 13,
                            height: 13,
                            decoration: const BoxDecoration(
                              color: Color(0xFFFFD36A),
                              shape: BoxShape.circle,
                            ),
                          ),
                          Container(
                            width: 2,
                            height: 28,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.34),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                          Icon(
                            Icons.flag_rounded,
                            size: 19,
                            color: Colors.white.withOpacity(0.86),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            b.from ?? '—',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15.1,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            b.to ?? '—',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.90),
                              fontSize: 15.0,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            ),
                          ),
                          if (customerName.trim().isNotEmpty) ...[
                            const SizedBox(height: 7),
                            Text(
                              '${_tr(nl: 'Klant', en: 'Customer', fr: 'Client', es: 'Cliente')}: $customerName',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.62),
                                fontSize: 11.8,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (isOperationalLeg && isRoundtripParent)
                      _pill(
                        text: legLabel,
                        borderColor: const Color(0xFF52B6FF),
                        textColor: const Color(0xFF9DD8FF),
                        compact: true,
                      ),
                    _pill(
                      text: statusText,
                      borderColor: const Color(0xFFB07A2A),
                      textColor: const Color(0xFFE7B46A),
                      compact: true,
                    ),
                    _pill(
                      text: (b.tier ?? 'premium').toUpperCase(),
                      compact: true,
                    ),
                    _pill(text: '${b.pax ?? 0} pax', compact: true),
                    _pill(text: bagLabel, compact: true),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (b.price != null)
                      _pill(
                        text: _fmtMoney(b.price!, b.currency ?? 'EUR'),
                        borderColor: const Color(0x55FFD36A),
                        textColor: const Color(0xFFFFD98A),
                        compact: true,
                      ),
                    const Spacer(),
                    SizedBox(
                      height: 42,
                      width: 42,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          padding: EdgeInsets.zero,
                          backgroundColor: const Color(0x33FFD36A),
                          foregroundColor: const Color(0xFFFFE4AA),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => _goToRide(b),
                        child: const Icon(
                          Icons.arrow_forward_rounded,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
                if (cardReference.value.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    isOperationalLeg &&
                            isRoundtripParent &&
                            parentBookingId.isNotEmpty
                        ? '$referenceChipText · ${_tr(nl: 'Parent', en: 'Parent', fr: 'Parent', es: 'Padre')}: ${_safeRefPreview(parentBookingId)}'
                        : referenceChipText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.44),
                      fontSize: 10.8,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: compactActionHeight,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: kFluxidiYellow,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: actionBusy ? null : () => _goToRide(b),
                    icon: const Icon(Icons.navigation_rounded, size: 16),
                    label: Text(
                      goToRideLabel,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  height: compactActionHeight,
                  child: OutlinedButton.icon(
                    style: _ghostButtonStyle(),
                    onPressed: actionBusy
                        ? null
                        : () =>
                              (b.isOperationalLeg && b.legId.trim().isNotEmpty)
                              ? _setOperationalLegStatus(b, 'COMPLETED')
                              : _setBookingStatus(b, 'COMPLETED'),
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: Text(
                      kRideActionCompletedLabel,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: compactActionHeight,
                        child: OutlinedButton.icon(
                          style: _ghostButtonStyle(),
                          onPressed: actionBusy
                              ? null
                              : () =>
                                    (b.isOperationalLeg &&
                                        b.legId.trim().isNotEmpty)
                                    ? _setOperationalLegStatus(b, 'CANCELLED')
                                    : _setBookingStatus(b, 'CANCELLED'),
                          icon: const Icon(Icons.cancel_outlined, size: 16),
                          label: Text(
                            kRideActionCancelledLabel,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      height: compactActionHeight,
                      width: compactActionHeight + 2,
                      child: IconButton(
                        onPressed: actionBusy ? null : () => _confirmDelete(b),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        tooltip: kRideDeleteLabel,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }

        return Container(
          padding: EdgeInsets.all(tight ? 11 : 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF151515), Color(0xFF0B0B0B)],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kFluxidiYellow.withOpacity(0.24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.24),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.035),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.07)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: Color(0xFFFFD36A),
                            shape: BoxShape.circle,
                          ),
                        ),
                        Container(
                          width: 2,
                          height: narrow ? 28 : 32,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.30),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                        Icon(
                          Icons.flag_rounded,
                          size: 15,
                          color: Colors.white.withOpacity(0.80),
                        ),
                      ],
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            b.from ?? '—',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            b.to ?? '—',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.85),
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            ),
                          ),
                          if (customerName.trim().isNotEmpty) ...[
                            const SizedBox(height: 7),
                            Text(
                              '${_tr(nl: 'Klant', en: 'Customer', fr: 'Client', es: 'Cliente')}: $customerName',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.66),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _pill(
                          icon: Icons.schedule,
                          text: dt,
                          borderColor: const Color(0x55FFD36A),
                          textColor: const Color(0xFFFFD98A),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 34,
                          width: 34,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              padding: EdgeInsets.zero,
                              backgroundColor: const Color(0x33FFD36A),
                              foregroundColor: const Color(0xFFFFE4AA),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: () => _goToRide(b),
                            child: const Icon(
                              Icons.arrow_forward_rounded,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (isOperationalLeg && isRoundtripParent)
                    _pill(
                      text: legLabel,
                      borderColor: const Color(0xFF52B6FF),
                      textColor: const Color(0xFF9DD8FF),
                    ),
                  _pill(
                    text: statusText,
                    borderColor: const Color(0xFFB07A2A),
                    textColor: const Color(0xFFE7B46A),
                  ),
                  _pill(text: (b.tier ?? 'premium').toUpperCase()),
                  _pill(text: '${b.pax ?? 0} pax'),
                  _pill(text: bagLabel),
                  if (b.price != null)
                    _pill(text: _fmtMoney(b.price!, b.currency ?? 'EUR')),
                ],
              ),
              if (cardReference.value.trim().isNotEmpty) ...[
                const SizedBox(height: 7),
                Text(
                  isOperationalLeg &&
                          isRoundtripParent &&
                          parentBookingId.isNotEmpty
                      ? '$referenceChipText · ${_tr(nl: 'Parent', en: 'Parent', fr: 'Parent', es: 'Padre')}: ${_safeRefPreview(parentBookingId)}'
                      : referenceChipText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.48),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              if (narrow) ...[
                SizedBox(
                  width: double.infinity,
                  height: actionHeight,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: kFluxidiYellow,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: actionBusy ? null : () => _goToRide(b),
                    icon: const Icon(Icons.navigation_rounded, size: 16),
                    label: Text(
                      goToRideLabel,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  height: actionHeight,
                  child: OutlinedButton.icon(
                    style: _ghostButtonStyle(),
                    onPressed: actionBusy
                        ? null
                        : () =>
                              (b.isOperationalLeg && b.legId.trim().isNotEmpty)
                              ? _setOperationalLegStatus(b, 'COMPLETED')
                              : _setBookingStatus(b, 'COMPLETED'),
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: Text(
                      kRideActionCompletedLabel,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: actionHeight,
                        child: OutlinedButton.icon(
                          style: _ghostButtonStyle(),
                          onPressed: actionBusy
                              ? null
                              : () =>
                                    (b.isOperationalLeg &&
                                        b.legId.trim().isNotEmpty)
                                    ? _setOperationalLegStatus(b, 'CANCELLED')
                                    : _setBookingStatus(b, 'CANCELLED'),
                          icon: const Icon(Icons.cancel_outlined, size: 16),
                          label: Text(
                            kRideActionCancelledLabel,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      height: actionHeight,
                      width: actionHeight + 2,
                      child: IconButton(
                        onPressed: actionBusy ? null : () => _confirmDelete(b),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        tooltip: kRideDeleteLabel,
                      ),
                    ),
                  ],
                ),
              ] else ...[
                SizedBox(
                  width: double.infinity,
                  height: actionHeight,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: kFluxidiYellow,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: actionBusy ? null : () => _goToRide(b),
                    icon: const Icon(Icons.navigation_rounded, size: 16),
                    label: Text(
                      goToRideLabel,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: actionHeight,
                        child: OutlinedButton.icon(
                          style: _ghostButtonStyle(),
                          onPressed: actionBusy
                              ? null
                              : () =>
                                    (b.isOperationalLeg &&
                                        b.legId.trim().isNotEmpty)
                                    ? _setOperationalLegStatus(b, 'COMPLETED')
                                    : _setBookingStatus(b, 'COMPLETED'),
                          icon: const Icon(
                            Icons.check_circle_outline,
                            size: 16,
                          ),
                          label: Text(kRideActionCompletedLabel),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: SizedBox(
                        height: actionHeight,
                        child: OutlinedButton.icon(
                          style: _ghostButtonStyle(),
                          onPressed: actionBusy
                              ? null
                              : () =>
                                    (b.isOperationalLeg &&
                                        b.legId.trim().isNotEmpty)
                                    ? _setOperationalLegStatus(b, 'CANCELLED')
                                    : _setBookingStatus(b, 'CANCELLED'),
                          icon: const Icon(Icons.cancel_outlined, size: 16),
                          label: Text(kRideActionCancelledLabel),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      height: actionHeight,
                      width: actionHeight + 2,
                      child: IconButton(
                        onPressed: actionBusy ? null : () => _confirmDelete(b),
                        icon: const Icon(Icons.delete_outline, size: 18),
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

  Widget _buildDirectRideEstimatePanel() {
    final destination = (_directRideDestinationText ?? '').trim();
    final showEstimate =
        _directRideDraft && _activeBooking == null && destination.isNotEmpty;
    final label = _tr(
      nl: 'Geschatte ritprijs',
      en: 'Estimated fare',
      fr: 'Prix estimé',
      es: 'Precio estimado',
    );
    final note = _tr(
      nl: 'Incl. btw • Definitieve prijs bij STOP',
      en: 'Incl. VAT • Final price at STOP',
      fr: 'TVA incl. • Prix final à l’arrêt',
      es: 'IVA incl. • Precio final al finalizar',
    );
    final loadingText = _tr(
      nl: 'Prijs berekenen…',
      en: 'Calculating fare…',
      fr: 'Calcul du prix…',
      es: 'Calculando precio…',
    );
    final unavailableText = _tr(
      nl: 'Schatting niet beschikbaar. De ritmeter blijft werken.',
      en: 'Estimate unavailable. The live meter still works.',
      fr: 'Estimation indisponible. Le taximètre reste actif.',
      es: 'Estimación no disponible. El taxímetro sigue funcionando.',
    );
    return DirectRideEstimatePanel(
      visible: showEstimate,
      estimatedFare: _directRideEstimatedFare,
      isLoading: _directRideEstimateLoading,
      error: _directRideEstimateError,
      currency: _directRideEstimateCurrency,
      label: label,
      note: note,
      loadingText: loadingText,
      unavailableText: unavailableText,
      formatAmount: _formatDirectRideEstimateText,
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
    bool compact = false,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 5 : 6,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: borderColor ?? Colors.white.withOpacity(0.18),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: compact ? 14 : 16,
              color: (textColor ?? Colors.white70),
            ),
            SizedBox(width: compact ? 4 : 6),
          ],
          Text(
            text,
            style: TextStyle(
              color: textColor ?? Colors.white,
              fontSize: compact ? 12.2 : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _ridesSegmentChip({required String label, bool active = false}) {
    return Container(
      constraints: const BoxConstraints(minHeight: 34, minWidth: 108),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? const Color(0xFF17120A) : const Color(0xFF111214),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active
              ? kFluxidiYellow.withOpacity(0.68)
              : Colors.white.withOpacity(0.14),
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.fade,
        softWrap: false,
        style: TextStyle(
          color: active
              ? kFluxidiYellow.withOpacity(0.98)
              : Colors.white.withOpacity(0.78),
          fontWeight: active ? FontWeight.w700 : FontWeight.w600,
          fontSize: 11.9,
        ),
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

  void _openBookingsHubFromDashboard() async {
    if (!_canAccessDriverOpsScreens()) {
      _denyRoleAccess();
      return;
    }
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
    _openTripHistoryFromDashboard();
  }

  void _openTripHistoryFromDashboard() {
    if (!_canAccessDriverOpsScreens()) {
      _denyRoleAccess();
      return;
    }
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
    final strictScope = _strictActiveLocalScopeIds();
    if (strictScope == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              nl: 'Bedrijfscontext ontbreekt. Ritgeschiedenis kan niet veilig geladen worden.',
              en: 'Company context is missing. Trip history cannot be loaded safely.',
              fr: 'Le contexte entreprise est manquant. L’historique des trajets ne peut pas être chargé en toute sécurité.',
              es: 'Falta el contexto de empresa. El historial de viajes no puede cargarse de forma segura.',
            ),
          ),
        ),
      );
      return;
    }
    unawaited(
      Navigator.of(context)
          .push(
            MaterialPageRoute(
              builder: (ctx) => _TripHistoryPage(
                workerBaseUrl: kWorkerBaseUrl,
                tenantId: strictScope.tenantId,
                companyId: strictScope.companyId,
                driverId: kDriverId,
                headers: _headers(admin: true),
                bookingDetailsById: bookingDetailsById,
              ),
            ),
          )
          .then((_) {
            if (!mounted) return;
            unawaited(
              _refreshCompletedTodayCount(reason: 'trip_history_return'),
            );
          }),
    );
  }

  Future<void> _openCalculatorFromDashboard() async {
    if (!_canAccessCustomerBookingScreens()) {
      _denyRoleAccess();
      return;
    }
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (ctx) => CalculatorPage(
          bookingBaseUrl: kBookingBaseUrl,
          mapboxToken: kMapboxToken,
          persistToCustomerBookings: false,
          entryContext: BookingEntryContext.driver,
        ),
      ),
    );
    if (created == true && mounted) {
      await _refreshBookings(force: true, trigger: 'calculator_created');
    }
  }

  Future<void> _openCalculator() async {
    if (!_canAccessCustomerBookingScreens()) {
      Navigator.pop(context);
      _denyRoleAccess();
      return;
    }
    // Close drawer first for a clean transition.
    Navigator.pop(context);

    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (ctx) => CalculatorPage(
          bookingBaseUrl: kBookingBaseUrl,
          mapboxToken: kMapboxToken,
          persistToCustomerBookings: false,
          entryContext: BookingEntryContext.driver,
        ),
      ),
    );
    if (created == true && mounted) {
      await _refreshBookings(force: true, trigger: 'calculator_created');
    }
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

    const drawerBg = Color(0xFF050505);
    const cardBg = Color(0xFF101010);
    const rowBg = Color(0xFF121212);
    const gold = Color(0xFFE5B641);
    const divider = Color(0x33E5B641);

    InputDecoration compactSelectDecoration() => InputDecoration(
      isDense: true,
      filled: true,
      fillColor: rowBg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0x35E5B641)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0x35E5B641)),
      ),
    );

    Widget controlLabel(String text) => Text(
      text,
      style: TextStyle(
        color: Colors.white.withOpacity(0.83),
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
    );

    final screenWidth = MediaQuery.of(context).size.width;
    final railWidth = screenWidth < 380
        ? 94.0
        : (screenWidth < 700 ? 110.0 : 126.0);

    Widget cockpitRailButton({
      required IconData icon,
      required String semanticLabel,
      required VoidCallback onTap,
    }) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Tooltip(
          message: semanticLabel,
          child: Semantics(
            button: true,
            label: semanticLabel,
            child: Material(
              color: rowBg,
              borderRadius: BorderRadius.circular(13),
              child: InkWell(
                borderRadius: BorderRadius.circular(13),
                onTap: onTap,
                child: Container(
                  width: double.infinity,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: const Color(0x33E5B641)),
                  ),
                  child: Icon(icon, size: 24, color: gold),
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget miniAction({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
    }) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Tooltip(
          message: label,
          child: Semantics(
            button: true,
            label: label,
            child: SizedBox(
              width: double.infinity,
              height: 54,
              child: OutlinedButton(
                onPressed: onTap,
                style: OutlinedButton.styleFrom(
                  foregroundColor: gold,
                  backgroundColor: cardBg,
                  side: BorderSide(color: gold.withOpacity(0.66), width: 1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 6,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 18),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Drawer(
      width: railWidth + 20,
      backgroundColor: drawerBg,
      child: SafeArea(
        child: Center(
          child: SizedBox(
            width: railWidth,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(0, 10, 0, 12),
              children: [
                Text(
                  _tr(
                    nl: 'Cockpit',
                    en: 'Cockpit',
                    fr: 'Cockpit',
                    es: 'Cabina',
                  ),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
                Text(
                  'Fluxidi',
                  style: TextStyle(
                    color: gold.withOpacity(0.92),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.35,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0x24E5B641)),
                  ),
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      controlLabel(
                        _tr(
                          nl: 'Taal',
                          en: 'Language',
                          fr: 'Langue',
                          es: 'Idioma',
                        ),
                      ),
                      const SizedBox(height: 5),
                      DropdownButtonFormField<String>(
                        value: currentLanguageCode,
                        items: const [
                          DropdownMenuItem(value: 'nl', child: Text('NL')),
                          DropdownMenuItem(value: 'en', child: Text('EN')),
                          DropdownMenuItem(value: 'fr', child: Text('FR')),
                          DropdownMenuItem(value: 'es', child: Text('ES')),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setAppLanguageByCode(v);
                          setState(() {});
                        },
                        dropdownColor: cardBg,
                        decoration: compactSelectDecoration(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        iconEnabledColor: gold,
                      ),
                      const SizedBox(height: 9),
                      controlLabel(
                        _tr(nl: 'Kaart', en: 'Map', fr: 'Carte', es: 'Mapa'),
                      ),
                      const SizedBox(height: 5),
                      DropdownButtonFormField<MapThemeMode>(
                        value: _effectiveMapThemeFor(_cameraMode),
                        items: [
                          DropdownMenuItem(
                            value: MapThemeMode.light,
                            child: Text(
                              _tr(
                                nl: 'Licht',
                                en: 'Light',
                                fr: 'Clair',
                                es: 'Claro',
                              ),
                            ),
                          ),
                          DropdownMenuItem(
                            value: MapThemeMode.dark,
                            child: Text(
                              _tr(
                                nl: 'Donker',
                                en: 'Dark',
                                fr: 'Sombre',
                                es: 'Oscuro',
                              ),
                            ),
                          ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          _setMapTheme(v);
                        },
                        dropdownColor: cardBg,
                        decoration: compactSelectDecoration(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        iconEnabledColor: gold,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                const Divider(color: divider),
                const SizedBox(height: 6),
                ValueListenableBuilder<ActiveDriverSession?>(
                  valueListenable: activeDriverSessionNotifier,
                  builder: (context, session, _) {
                    if (!(isDriver && session != null)) {
                      return const SizedBox.shrink();
                    }
                    return Column(
                      children: [
                        cockpitRailButton(
                          icon: Icons.folder_copy_outlined,
                          semanticLabel: _tr(
                            nl: 'Documenten',
                            en: 'Documents',
                            fr: 'Documents',
                            es: 'Documentos',
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
                        cockpitRailButton(
                          icon: Icons.swap_horiz_rounded,
                          semanticLabel: _tr(
                            nl: 'Wissel',
                            en: 'Switch',
                            fr: 'Changer',
                            es: 'Cambiar',
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
                    );
                  },
                ),
                if (canSeeDriverOps)
                  cockpitRailButton(
                    icon: Icons.list_alt_rounded,
                    semanticLabel: _tr(
                      nl: 'Ritten',
                      en: 'Rides',
                      fr: 'Courses',
                      es: 'Viajes',
                    ),
                    onTap: _openBookingsHub,
                  ),
                if (canSeeDriverOps)
                  cockpitRailButton(
                    icon: Icons.local_taxi_outlined,
                    semanticLabel: _tr(
                      nl: 'Straatrit',
                      en: 'Street',
                      fr: 'Rue',
                      es: 'Calle',
                    ),
                    onTap: _openDirectRideEntry,
                  ),
                if (canSeeDriverOps)
                  cockpitRailButton(
                    icon: Icons.history,
                    semanticLabel: _tr(
                      nl: 'Historiek',
                      en: 'History',
                      fr: 'Historique',
                      es: 'Historial',
                    ),
                    onTap: _openTripHistory,
                  ),
                if (canSeeCustomerBooking)
                  cockpitRailButton(
                    icon: Icons.calculate_outlined,
                    semanticLabel: _tr(
                      nl: 'Prijs',
                      en: 'Price',
                      fr: 'Prix',
                      es: 'Precio',
                    ),
                    onTap: _openCalculator,
                  ),
                if (canSeeAdminManagement)
                  cockpitRailButton(
                    icon: Icons.business_center_outlined,
                    semanticLabel: _tr(
                      nl: 'Bedrijf',
                      en: 'Business',
                      fr: 'Entreprise',
                      es: 'Empresa',
                    ),
                    onTap: _openBusinessSettings,
                  ),
                if (canSeeAdminManagement)
                  cockpitRailButton(
                    icon: Icons.directions_car_filled_outlined,
                    semanticLabel: _tr(
                      nl: 'Voertuigen',
                      en: 'Vehicles',
                      fr: 'Vehicules',
                      es: 'Vehiculos',
                    ),
                    onTap: _openVehicles,
                  ),
                const SizedBox(height: 2),
                const Divider(color: divider),
                const SizedBox(height: 6),
                if (canSeeDriverOps)
                  cockpitRailButton(
                    icon: Icons.refresh_rounded,
                    semanticLabel: _tr(
                      nl: 'Vernieuw',
                      en: 'Refresh',
                      fr: 'Actualiser',
                      es: 'Actualizar',
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _refreshBookings(force: true, trigger: 'drawer_manual');
                    },
                  ),
                if (canSeeDriverOps)
                  cockpitRailButton(
                    icon: Icons.my_location_rounded,
                    semanticLabel: _tr(
                      nl: 'Centreer',
                      en: 'Center',
                      fr: 'Centrer',
                      es: 'Centrar',
                    ),
                    onTap: () async {
                      Navigator.pop(context);
                      await _centerOnMe();
                    },
                  ),
                if (canSeeDriverOps) const SizedBox(height: 6),
                if (canSeeDriverOps)
                  Column(
                    children: [
                      miniAction(
                        icon: Icons.home_outlined,
                        label: _tr(
                          nl: 'Start',
                          en: 'Start',
                          fr: 'Accueil',
                          es: 'Inicio',
                        ),
                        onTap: () {
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(
                              builder: (_) => const RoleEntryPage(),
                            ),
                            (route) => false,
                          );
                        },
                      ),
                      miniAction(
                        icon: Icons.badge_outlined,
                        label: _tr(
                          nl: 'Chauffeur',
                          en: 'Driver',
                          fr: 'Chauffeur',
                          es: 'Conductor',
                        ),
                        onTap: () {
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(
                              builder: (_) => const DriverHomePage(),
                            ),
                            (route) => false,
                          );
                        },
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
}

/// Small icon button with Fluxidi yellow glow.
///
/// Used in the brand bar (menu icon, etc.). Keeps hit-area large for in-car use.

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
