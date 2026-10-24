import 'package:http/http.dart' as http;
import 'company_public_booking_link.dart';

/// Resolve the existing public alias without following arbitrary redirects.
Future<String> fetchRegisteredBookingSlug(
  String code, {
  http.Client? client,
}) async {
  if (!RegExp(r'^FLX-[0-9]{5,12}$').hasMatch(code)) {
    throw const CompanyBookingLinkUnavailable();
  }
  final transport = client ?? http.Client();
  try {
    final request = http.Request(
      'HEAD',
      Uri.parse(
        '$companyPublicBookingOrigin/book',
      ).replace(queryParameters: {'company_code': code}),
    )..followRedirects = false;
    final response = await transport
        .send(request)
        .timeout(const Duration(seconds: 12));
    final location = response.headers['location'];
    if (response.statusCode != 308 || location == null)
      throw const CompanyBookingLinkUnavailable();
    final target = request.url.resolve(location);
    if (target.origin != companyPublicBookingOrigin ||
        target.userInfo.isNotEmpty ||
        target.hasQuery ||
        target.hasFragment ||
        !RegExp(r'^/[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(target.path)) {
      throw const CompanyBookingLinkUnavailable();
    }
    return target.path.substring(1);
  } finally {
    if (client == null) transport.close();
  }
}

/// The directory is obtained with the existing verified device credential.
/// Public context is checked against that exact scope, never against a name.
Future<CompanyPublicBookingLink> resolveDriverPublicBookingLink({
  required String tenantId,
  required String companyId,
  required String vehicleId,
  required String driverId,
  required Future<void> Function() verifyDriver,
  required Future<Map<String, dynamic>?> Function() directoryLoader,
  required bool Function() scopeIsCurrent,
  String? verifiedSessionCompanyCode,
  Future<String> Function(String)? slugLoader,
  CompanyBookingContextLoader contextLoader = fetchCompanyBookingContext,
}) async {
  void current() {
    if ([
          tenantId,
          companyId,
          vehicleId,
          driverId,
        ].any((v) => v.trim().isEmpty) ||
        !scopeIsCurrent()) {
      throw const CompanyBookingLinkUnavailable();
    }
  }

  current();
  await verifyDriver();
  current();
  final directory = await directoryLoader();
  current();
  if (directory == null ||
      directory['tenant_id'] != tenantId ||
      directory['company_id'] != companyId ||
      directory['vehicle_id'] != vehicleId ||
      directory['drivers'] is! List ||
      !(directory['drivers'] as List).any(
        (row) => row is Map && row['driver_id'] == driverId,
      )) {
    throw const CompanyBookingLinkUnavailable();
  }
  // The directory code is optional. The existing personal session is verified
  // above; its public code may locate an alias, never authorize a company.
  // The public context below must still match the exact tenant/company scope.
  final code = (directory['company_code'] ?? verifiedSessionCompanyCode)
          ?.toString() ?? '';
  final slug = await (slugLoader ?? fetchRegisteredBookingSlug)(code);
  current();
  return resolveCompanyPublicBookingLink(
    expectedCompanyId: companyId,
    scopeIsCurrent: scopeIsCurrent,
    profileLoader: () async => {
      'tenant_id': tenantId,
      'company_id': companyId,
      'public_company_slug': slug,
    },
    contextLoader: (value) async {
      final context = await contextLoader(value);
      current();
      // Explicit check against the authenticated tenant, not just company ID.
      if (context['company'] is! Map ||
          context['company']['tenant_id'] != tenantId) {
        throw const CompanyBookingLinkUnavailable();
      }
      return context;
    },
  );
}
