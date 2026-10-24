/// Dedicated authorized save for the customer-app header choice.
///
/// MERGE (one agent, after both features are ready):
/// - Wire GET/POST `/admin/business/customer-app-header` in the booking
///   worker using `workers/booking/modules/customer_app_header_mode.mjs`.
/// - Add `...projectCustomerAppHeaderFields(source)` to
///   `normalizeBusinessProfile`. Do not send a full business profile from
///   this client.
/// - Do not publish the public partner profile from this write.
///
/// Shared files this module must not edit while the tariffs agent is active:
/// `lib/business_settings_page.dart`, `lib/app_config.dart`,
/// `workers/booking/fluxidi_booking_worker.js`.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:fluxidi_tracking/app_config.dart';

import 'customer_app_header_branding.dart';
import 'customer_app_header_mode.dart';

const String kCustomerAppHeaderSettingsPath =
    '/admin/business/customer-app-header';

class CustomerAppHeaderSettingsException implements Exception {
  const CustomerAppHeaderSettingsException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

typedef CustomerAppHeaderHttpSend = Future<http.Response> Function(
  Uri url, {
  Map<String, String>? headers,
  String? body,
});

CustomerAppHeaderBranding customerAppHeaderSettingsFromResponse(
  Map<String, dynamic> json,
) {
  final nested = json['customer_app_header'];
  final source = nested is Map
      ? Map<String, dynamic>.from(nested)
      : json;
  return CustomerAppHeaderBranding.fromJson(source);
}

Future<CustomerAppHeaderBranding> fetchCustomerAppHeaderSettings({
  String? tenantId,
  String? companyId,
  CustomerAppHeaderHttpSend? httpGet,
}) async {
  final endpoint = adminTenantCompanyScopedUri(
    Uri.parse('${appConfig.bookingBaseUrl}$kCustomerAppHeaderSettingsPath'),
    tenantId: tenantId,
    companyId: companyId,
  );
  final auth = await resolveCompanyOwnerAuthHeaders();
  final res = await (httpGet ??
          (url, {headers, body}) => http.get(url, headers: headers))(
        endpoint,
        headers: auth.headers,
      )
      .timeout(const Duration(seconds: 12));
  return _read(res);
}

/// Writes only the header display fields. Never sends the rest of the
/// business profile and never publishes the public partner card.
Future<CustomerAppHeaderBranding> saveCustomerAppHeaderSettings({
  required CustomerAppHeaderMode mode,
  CustomerAppHeaderLogoPosition logoPosition =
      CustomerAppHeaderLogoPosition.topLeft,
  bool? useOnDriverApp,
  bool? useOnBusinessApp,
  String? tenantId,
  String? companyId,
  CustomerAppHeaderHttpSend? httpPost,
}) async {
  final endpoint = adminTenantCompanyScopedUri(
    Uri.parse('${appConfig.bookingBaseUrl}$kCustomerAppHeaderSettingsPath'),
    tenantId: tenantId,
    companyId: companyId,
  );
  final scope = adminTenantCompanyScope(
    tenantId: tenantId,
    companyId: companyId,
  );
  final auth = await resolveCompanyOwnerAuthHeaders();
  final res = await (httpPost ??
          (url, {headers, body}) => http.post(
                url,
                headers: headers,
                body: body,
              ))(
        endpoint,
        headers: auth.headers,
        body: jsonEncode(<String, dynamic>{
          ...scope,
          kCustomerAppHeaderModeField: customerAppHeaderModeWire(mode),
          kCustomerAppHeaderLogoPositionField:
              customerAppHeaderLogoPositionWire(logoPosition),
          if (useOnDriverApp != null)
            kDriverAppUseCompanyHeaderField: useOnDriverApp,
          if (useOnBusinessApp != null)
            kBusinessAppUseCompanyHeaderField: useOnBusinessApp,
        }),
      )
      .timeout(const Duration(seconds: 12));
  return _read(res);
}

CustomerAppHeaderBranding _read(http.Response res) {
  Map<String, dynamic> map;
  try {
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    map = decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
  } catch (_) {
    throw CustomerAppHeaderSettingsException(
      'invalid_response',
      statusCode: res.statusCode,
    );
  }
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw CustomerAppHeaderSettingsException(
      (map['error'] ?? 'customer_app_header_save_failed').toString(),
      statusCode: res.statusCode,
    );
  }
  return customerAppHeaderSettingsFromResponse(map);
}
