// COMPANY-CUSTOMER-OPS-P0 — classify list/import HTTP failures without tokens.

import 'package:fluxidi_tracking/company/company_customer_import_models.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';

bool isCompanyCustomersCollectionPath(String path) {
  final normalized = path.trim();
  if (normalized == kCompanyCustomersPath) return true;
  if (normalized == kCompanyCustomerImportPathPrefix) return true;
  if (normalized.startsWith('$kCompanyCustomerImportPathPrefix/')) {
    return true;
  }
  return false;
}

/// Maps a customer-ops HTTP outcome to a stable exception code.
///
/// A missing collection route is not an empty list and not a stale session.
/// Production booking does not host these routes; the local Worker does.
String classifyCompanyCustomerHttpFailure({
  required int statusCode,
  required String path,
  Map<String, dynamic>? decoded,
  required bool loopbackHost,
  required bool jsonBody,
}) {
  if (statusCode == 401 || statusCode == 403) return 'unauthorized';
  final collection = isCompanyCustomersCollectionPath(path);
  final payloadError = (decoded?['error'] ?? '').toString().trim();
  if (collection &&
      (statusCode == 404 ||
          !jsonBody ||
          payloadError == 'route_missing' ||
          payloadError == 'not_found')) {
    return loopbackHost ? 'route_missing' : 'wrong_environment';
  }
  if (!jsonBody) {
    return loopbackHost ? 'route_missing' : 'wrong_environment';
  }
  if (payloadError.isNotEmpty) return payloadError;
  return 'http_$statusCode';
}
