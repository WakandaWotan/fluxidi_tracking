// RELEASE-P0-MOLLIE-STREET-CHECKOUT-CONVERGE-1
//
// Single auth + scope helper for street Mollie `/pay/status` polling.
// Used by both the street checkout dialog (via receipt) and
// PaymentReturnCoordinator so company tablets never prefer a stale
// driver session over a valid company session.
import 'package:flutter/foundation.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/company_session_store.dart';
import 'package:fluxidi_tracking/customer_session_store.dart';
import 'package:fluxidi_tracking/driver_session_store.dart';

/// Auth mode selected for street Mollie status polling / receipt refresh.
enum MollieStreetStatusAuthMode {
  companySession,
  driverSession,
  customerSession,
  none,
}

class MollieStreetStatusAuthHeaders {
  const MollieStreetStatusAuthHeaders({
    required this.headers,
    required this.mode,
  });

  final Map<String, String> headers;
  final MollieStreetStatusAuthMode mode;
}

/// Pure selection order for street Mollie status auth.
///
/// 1. company when available
/// 2. driver only as scoped fallback
/// 3. customer only when legitimately bound
/// 4. never unauthenticated
MollieStreetStatusAuthMode selectMollieStreetStatusAuthMode({
  required bool hasCompanySession,
  required bool hasDriverSession,
  required bool hasCustomerSession,
}) {
  if (hasCompanySession) return MollieStreetStatusAuthMode.companySession;
  if (hasDriverSession) return MollieStreetStatusAuthMode.driverSession;
  if (hasCustomerSession) return MollieStreetStatusAuthMode.customerSession;
  return MollieStreetStatusAuthMode.none;
}

/// Sanitized id preview for diagnostics (never full ids / tokens / PII).
String mollieStreetIdHash(String? id) {
  final text = (id ?? '').trim();
  if (text.isEmpty) return '-';
  if (text.length <= 8) return '${text.length}c';
  return '${text.substring(0, 8)}…';
}

/// Bounded diagnostic line for street status polls. Never logs tokens/PII.
void logMollieStreetStatusDiag({
  required MollieStreetStatusAuthMode authMode,
  required int httpStatus,
  String? errorCode,
  String? paymentBookingId,
  String? canonicalBookingId,
}) {
  final err = (errorCode ?? '').trim();
  debugPrint(
    '[MOLLIE_STREET_STATUS] auth=${authMode.name} http=$httpStatus '
    'error=${err.isEmpty ? '-' : err} '
    'pay=${mollieStreetIdHash(paymentBookingId)} '
    'booking=${mollieStreetIdHash(canonicalBookingId)}',
  );
}

/// True when [pendingPaymentId] refers to the same payment shadow as
/// [dialogPaymentId] (exact match after trim).
bool mollieStreetPaymentIdsMatch(
  String? pendingPaymentId,
  String? dialogPaymentId,
) {
  final a = (pendingPaymentId ?? '').trim();
  final b = (dialogPaymentId ?? '').trim();
  if (a.isEmpty || b.isEmpty) return false;
  return a == b;
}

/// Tenant/company query for street Mollie `/pay/status`.
///
/// Prefers company scope; falls back to the active driver session scope when
/// no company context exists. Never invents default tenant ids.
Map<String, String>? resolveMollieStreetStatusScopeQuery() {
  final profileCompanyId = companyProfileNotifier.value?.companyId.trim() ?? '';
  final sessionCompanyId =
      activeCompanySessionNotifier.value?.companyId.trim() ?? '';
  if (profileCompanyId.isNotEmpty &&
      sessionCompanyId.isNotEmpty &&
      profileCompanyId != sessionCompanyId) {
    return null;
  }
  final companyId = profileCompanyId.isNotEmpty
      ? profileCompanyId
      : sessionCompanyId;
  if (companyId.isNotEmpty) {
    return <String, String>{
      'tenant_id': companyId,
      'company_id': companyId,
      'tenantId': companyId,
      'companyId': companyId,
    };
  }

  final driver = activeDriverSessionNotifier.value;
  final driverTenant = (driver?.tenantId ?? '').trim();
  final driverCompany = (driver?.companyId ?? '').trim();
  if (driverTenant.isNotEmpty && driverCompany.isNotEmpty) {
    return <String, String>{
      'tenant_id': driverTenant,
      'company_id': driverCompany,
      'tenantId': driverTenant,
      'companyId': driverCompany,
    };
  }
  return null;
}

/// Company-first auth headers for street Mollie status / receipt refresh.
///
/// Intentionally diverges from [resolveInCarPaymentAuthHeaders] (driver-first
/// for cash/QR mark-paid) so a stale driver session cannot shadow a valid
/// company session on `/pay/status`.
Future<MollieStreetStatusAuthHeaders> resolveMollieStreetStatusAuthHeaders({
  bool json = true,
}) async {
  final headers = <String, String>{'Accept': 'application/json'};
  if (json) headers['Content-Type'] = 'application/json';

  final companyAuth = await resolveCompanyOwnerAuthHeaders(json: json);
  final hasCompany = companyAuth.mode == CompanyOwnerAuthMode.companySession;
  final driverToken =
      (activeDriverSessionNotifier.value?.driverSessionToken ?? '').trim();
  final hasDriver = driverToken.isNotEmpty;

  String customerToken = '';
  try {
    final customerSession =
        await CustomerSessionStore.instance.loadValidSession();
    customerToken = (customerSession?.customerSessionToken ?? '').trim();
  } catch (_) {
    customerToken = '';
  }
  final hasCustomer = customerToken.isNotEmpty;

  final mode = selectMollieStreetStatusAuthMode(
    hasCompanySession: hasCompany,
    hasDriverSession: hasDriver,
    hasCustomerSession: hasCustomer,
  );

  switch (mode) {
    case MollieStreetStatusAuthMode.companySession:
      headers.addAll(companyAuth.headers);
      return MollieStreetStatusAuthHeaders(headers: headers, mode: mode);
    case MollieStreetStatusAuthMode.driverSession:
      headers['Authorization'] = 'Bearer $driverToken';
      return MollieStreetStatusAuthHeaders(headers: headers, mode: mode);
    case MollieStreetStatusAuthMode.customerSession:
      headers['Authorization'] = 'Bearer $customerToken';
      return MollieStreetStatusAuthHeaders(headers: headers, mode: mode);
    case MollieStreetStatusAuthMode.none:
      return MollieStreetStatusAuthHeaders(headers: headers, mode: mode);
  }
}
