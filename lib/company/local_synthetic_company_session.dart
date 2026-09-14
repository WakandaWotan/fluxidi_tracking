// Local debug-only company session for the full Windows app-shell.
// Activates only against a loopback Worker with a cst_local_* token.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';
import 'package:fluxidi_tracking/company/auth_failure_kind.dart';
import 'package:fluxidi_tracking/company_session_store.dart';
import 'package:fluxidi_tracking/customer_session_store.dart';
import 'package:fluxidi_tracking/driver_session_store.dart';
import 'package:http/http.dart' as http;

const String kLocalSyntheticCompanySessionToken = String.fromEnvironment(
  'COMPANY_SESSION_TOKEN',
);
const String kLocalSyntheticCompanyId = String.fromEnvironment(
  'FLUXIDI_DEV_COMPANY_ID',
);
const String kLocalSyntheticTenantId = String.fromEnvironment(
  'FLUXIDI_DEV_TENANT_ID',
);

const Map<String, String> kLocalSyntheticCompanyNames = <String, String>{
  'demo_company_p0': 'Fluxidi Demo Cars',
  'demo_company_p1': 'Nocturne Limousines',
};

const Map<String, String> kLocalSyntheticCompanyTokens = <String, String>{
  'demo_company_p0': 'cst_local_demo_synthetic',
  'demo_company_p1': 'cst_local_demo_nocturne',
};

const Map<String, String> kLocalSyntheticCompanyCodes = <String, String>{
  'demo_company_p0': 'FLX-DEMO1',
  'demo_company_p1': 'NTC-LIMO1',
};

bool get canOfferLocalSyntheticCompanySwitch =>
    shouldBindLocalSyntheticCompanySession();

const Set<String> kLocalSyntheticCompanyIds = <String>{
  'demo_company_p0',
  'demo_company_p1',
};

bool isLoopbackBookingBaseUrl(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || !uri.hasScheme) return false;
  final host = uri.host.toLowerCase();
  return host == '127.0.0.1' || host == 'localhost';
}

bool isProductionBookingHost(String raw) {
  return raw.toLowerCase().contains(kFluxidiProductionBookingHost);
}

bool isLocalSyntheticCompanyId(String raw) {
  return kLocalSyntheticCompanyIds.contains(raw.trim());
}

bool isLocalSyntheticCompanySessionToken(String raw) {
  return raw.trim().startsWith('cst_local_');
}

bool isLocalSyntheticCompanySessionRecord({
  String? companyId,
  String? sessionToken,
  String? linkMethod,
}) {
  final method = (linkMethod ?? '').trim().toLowerCase();
  if (method == 'local_synthetic_demo' || method == 'dev_pairing_bypass') {
    return true;
  }
  if (isLocalSyntheticCompanySessionToken(sessionToken ?? '')) return true;
  return isLocalSyntheticCompanyId(companyId ?? '');
}

/// Local demo sessions must not restore against production booking.
bool shouldDiscardLocalSyntheticSessionForHost({
  required String bookingBaseUrl,
  String? companyId,
  String? sessionToken,
  String? linkMethod,
}) {
  if (isLoopbackBookingBaseUrl(bookingBaseUrl)) return false;
  return isLocalSyntheticCompanySessionRecord(
    companyId: companyId,
    sessionToken: sessionToken,
    linkMethod: linkMethod,
  );
}

Future<void> discardMismatchedLocalSyntheticAuthSessions() async {
  if (isLoopbackBookingBaseUrl(kBookingBaseUrl)) return;
  await _discardMismatchedLocalSyntheticCompanySession();
  await _discardMismatchedLocalSyntheticCustomerSession();
  await _discardMismatchedLocalSyntheticDriverSession();
}

Future<void> _discardMismatchedLocalSyntheticCompanySession() async {
  final session =
      activeCompanySessionNotifier.value ??
      await CompanySessionStore.instance.loadSession();
  final profile = companyProfileNotifier.value;
  final companyId =
      (session?.companyId ?? profile?.companyId ?? '').trim();
  if (!shouldDiscardLocalSyntheticSessionForHost(
    bookingBaseUrl: kBookingBaseUrl,
    companyId: companyId,
    sessionToken: session?.companySessionToken,
    linkMethod: session?.linkMethod,
  )) {
    return;
  }
  debugPrint(
    '[COMPANY_SESSION][LOCAL_SYNTHETIC] discard reason=host_mismatch '
    'company=$companyId host=${describePublicAuthHost(kBookingBaseUrl)}',
  );
  await CompanySessionStore.instance.clearLocalCompanyState();
}

Future<void> _discardMismatchedLocalSyntheticCustomerSession() async {
  final session = await CustomerSessionStore.instance.load();
  if (session == null) return;
  final companyId = (session.defaultCompanyId ?? '').trim();
  if (!isLocalSyntheticCompanyId(companyId)) return;
  debugPrint(
    '[CUSTOMER_SESSION][LOCAL_SYNTHETIC] discard reason=host_mismatch '
    'company=$companyId host=${describePublicAuthHost(kBookingBaseUrl)}',
  );
  await CustomerSessionStore.instance.clear();
}

Future<void> _discardMismatchedLocalSyntheticDriverSession() async {
  final pointer =
      await DriverSessionStore.instance.loadStandaloneScopePointer();
  final companyId = (pointer?.companyId ??
          activeDriverSessionNotifier.value?.companyId ??
          '')
      .trim();
  if (!isLocalSyntheticCompanyId(companyId)) return;
  debugPrint(
    '[DRIVER_SESSION][LOCAL_SYNTHETIC] discard reason=host_mismatch '
    'company=$companyId host=${describePublicAuthHost(kBookingBaseUrl)}',
  );
  await DriverSessionStore.instance.clear();
}

bool shouldBindLocalSyntheticCompanySession({
  bool releaseMode = kReleaseMode,
  String? bookingBaseUrl,
  String? sessionToken,
  String? companyId,
}) {
  if (releaseMode) return false;
  final url = (bookingBaseUrl ?? kBookingBaseUrl).trim();
  final token = (sessionToken ?? kLocalSyntheticCompanySessionToken).trim();
  final id = (companyId ?? kLocalSyntheticCompanyId).trim();
  if (url.toLowerCase().contains(kFluxidiProductionBookingHost)) return false;
  return isLoopbackBookingBaseUrl(url) &&
      isLocalSyntheticCompanySessionToken(token) &&
      id.isNotEmpty;
}

/// Local dart-defines may replace a production or other company session.
/// Pairing remains the proof on production hosts and release builds.
bool shouldReplaceSessionForLocalSyntheticBind({
  required String? existingCompanyId,
  required String configuredCompanyId,
}) {
  final configured = configuredCompanyId.trim();
  if (configured.isEmpty) return false;
  return (existingCompanyId ?? '').trim() != configured;
}

Future<bool> tryBindLocalSyntheticCompanySession() {
  return bindLocalSyntheticCompanySessionForCompany(
    kLocalSyntheticCompanyId.trim(),
    sessionToken: kLocalSyntheticCompanySessionToken.trim(),
  );
}

Future<bool> bindLocalSyntheticCompanySessionForCompany(
  String companyId, {
  String? sessionToken,
}) async {
  final id = companyId.trim();
  final token = (sessionToken ?? kLocalSyntheticCompanyTokens[id] ?? '').trim();
  if (!shouldBindLocalSyntheticCompanySession(
    sessionToken: token,
    companyId: id,
  )) {
    return false;
  }
  final tenantId = kLocalSyntheticTenantId.trim().isNotEmpty
      ? kLocalSyntheticTenantId.trim()
      : id;
  final directory = await _lookupLocalSyntheticCompany(id);
  final companyName =
      (directory?['name'] ?? kLocalSyntheticCompanyNames[id] ?? id)
          .toString()
          .trim();
  final companyCode = (directory?['code'] ??
          kLocalSyntheticCompanyCodes[id] ??
          '')
      .toString()
      .trim();
  debugPrint(
    '[COMPANY_SESSION][LOCAL_SYNTHETIC] bind company=$id token=cst_local_*',
  );
  final logoUrl = (directory?['logo'] ?? '').toString().trim();
  if (logoUrl.isNotEmpty) {
    final current = localBackendBusinessProfileNotifier.value;
    localBackendBusinessProfileNotifier.value = (current ??
            BackendBusinessProfile.defaults())
        .copyWith(companyName: companyName, publicLogoUrl: logoUrl);
  }
  await CompanySessionStore.instance.saveVerifiedCompanyPairingSession(
    tenantId: tenantId,
    companyId: id,
    companyCode: companyCode,
    companyName: companyName,
    countryCode: 'BE',
    companySessionToken: token,
    issuedAt: DateTime.now().toUtc(),
    expiresAt: DateTime.now().toUtc().add(const Duration(days: 7)),
    linkMethod: 'local_synthetic_demo',
  );
  bindBusinessThemeCompanyScope(id);
  return CompanySessionStore.instance.hasValidCompanyContext &&
      (activeCompanySessionNotifier.value?.companyId ?? '').trim() == id;
}

Future<Map<String, String>?> _lookupLocalSyntheticCompany(
  String companyId,
) async {
  try {
    final res = await http
        .get(
          Uri.parse('$kBookingBaseUrl/local/companies'),
          headers: const <String, String>{'Accept': 'application/json'},
        )
        .timeout(const Duration(seconds: 4));
    if (res.statusCode < 200 || res.statusCode >= 300) return null;
    final decoded = jsonDecode(res.body);
    if (decoded is! Map) return null;
    final items = decoded['items'] ?? decoded['companies'];
    if (items is! List) return null;
    for (final row in items) {
      if (row is! Map) continue;
      final id = (row['id'] ?? row['company_id'] ?? '').toString().trim();
      if (id != companyId) continue;
      return <String, String>{
        'name': (row['name'] ?? row['company_name'] ?? '').toString(),
        'code': (row['code'] ?? row['company_code'] ?? '').toString(),
        'logo': (row['public_logo_url'] ?? row['logo'] ?? '').toString(),
      };
    }
  } catch (_) {}
  return null;
}
