/// Loads white-label header branding without changing the shared partner
/// models. FLX-00028 is only a company code here, never a bookable partner id.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:fluxidi_tracking/customer_app_header/customer_app_header_branding.dart';

import 'public_partner_models.dart';

typedef CustomerAppHeaderHttpGet = Future<http.Response> Function(
  Uri url, {
  Map<String, String>? headers,
});

class CustomerAppHeaderBrandingApi {
  CustomerAppHeaderBrandingApi({
    required this.baseUrl,
    CustomerAppHeaderHttpGet? httpGet,
    this.timeout = const Duration(seconds: 12),
  }) : _httpGet = httpGet ?? http.get;

  final String baseUrl;
  final Duration timeout;
  final CustomerAppHeaderHttpGet _httpGet;

  bool get isConfigured => baseUrl.trim().isNotEmpty;

  String get _base => baseUrl.trim().replaceAll(RegExp(r'/+$'), '');

  /// [companyCode] loads settings branding. [publicPartnerId] must be the
  /// canonical bookable partner id when a cover is read from the profile.
  Future<CustomerAppHeaderBranding> load({
    String companyCode = '',
    String publicPartnerId = '',
    String fallbackName = '',
    String fallbackLogoUrl = '',
  }) async {
    var branding = CustomerAppHeaderBranding(
      companyName: fallbackName,
      logoUrl: fallbackLogoUrl,
    );
    if (!isConfigured) return branding;

    final partnerId = publicPartnerId.trim();
    if (partnerId.isNotEmpty && !looksLikePublicCompanyCode(partnerId)) {
      final profileBody = await _getJson(
        Uri.parse('$_base/partners/profile').replace(
          queryParameters: <String, String>{'partner_id': partnerId},
        ),
      );
      final profile = asStringKeyedMap(profileBody?['profile'] ?? profileBody);
      if (profile.isNotEmpty) {
        branding = _merge(branding, CustomerAppHeaderBranding.fromJson(profile));
      }
    }

    final code = normalizePublicCompanyCode(companyCode);
    if (looksLikePublicCompanyCode(code)) {
      final resolved = await _getJson(
        Uri.parse('$_base/public/company/resolve').replace(
          queryParameters: <String, String>{'code': code},
        ),
      );
      if (resolved != null) {
        branding = _merge(
          branding,
          CustomerAppHeaderBranding.fromJson(resolved),
        );
      }
    }
    if (branding.companyName.trim().isEmpty && fallbackName.trim().isNotEmpty) {
      branding = branding.copyWith(companyName: fallbackName);
    }
    return branding;
  }

  CustomerAppHeaderBranding _merge(
    CustomerAppHeaderBranding current,
    CustomerAppHeaderBranding incoming,
  ) {
    return CustomerAppHeaderBranding(
      mode: incoming.hasExplicitMode ? incoming.mode : current.mode,
      logoPosition: incoming.logoPosition,
      hasExplicitMode: incoming.hasExplicitMode || current.hasExplicitMode,
      logoUrl: incoming.logoUrl.isNotEmpty ? incoming.logoUrl : current.logoUrl,
      coverUrl:
          incoming.coverUrl.isNotEmpty ? incoming.coverUrl : current.coverUrl,
      companyName: incoming.companyName.isNotEmpty
          ? incoming.companyName
          : current.companyName,
      mediaRevision: incoming.mediaRevision.isNotEmpty
          ? incoming.mediaRevision
          : current.mediaRevision,
    );
  }

  Future<Map<String, dynamic>?> _getJson(Uri uri) async {
    try {
      final response = await _httpGet(
        uri,
        headers: const <String, String>{'Accept': 'application/json'},
      ).timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      return asStringKeyedMap(decoded);
    } catch (_) {
      return null;
    }
  }
}
