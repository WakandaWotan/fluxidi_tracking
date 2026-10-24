import 'dart:convert';

import 'package:http/http.dart' as http;

/// Presentation adapter to the existing registered identity and public host.
/// Never derives a slug from a name/code or supplies a legacy URL.
const String companyPublicBookingOrigin = 'https://booking.fluxidi.com';

typedef CompanyBookingContextLoader =
    Future<Map<String, dynamic>> Function(String slug);

class CompanyBookingLinkUnavailable implements Exception {
  const CompanyBookingLinkUnavailable();
}

class CompanyPublicBookingLink {
  const CompanyPublicBookingLink._({
    required this.slug,
    required this.companyId,
    required this.companyName,
    required this.logoUrl,
  });

  final String slug;
  final String companyId;
  final String companyName;
  final String logoUrl;
  String get url => '$companyPublicBookingOrigin/$slug';
}

String _consistentText(List<Map<String, dynamic>> rows, List<String> keys) {
  final values = <String>{
    for (final row in rows)
      for (final key in keys)
        if ((row[key]?.toString().trim() ?? '').isNotEmpty)
          row[key].toString().trim(),
  };
  if (values.length != 1) throw const CompanyBookingLinkUnavailable();
  return values.single;
}

bool _ownScope(Object? value, String tenant, String company) {
  if (value is List) {
    return value.every((child) => _ownScope(child, tenant, company));
  }
  if (value is! Map) return true;
  for (final key in const ['tenant_id', 'tenantId']) {
    if (value[key] != null && value[key].toString() != tenant) return false;
  }
  for (final key in const ['company_id', 'companyId']) {
    if (value[key] != null && value[key].toString() != company) return false;
  }
  for (final key in const [
    'partner_id',
    'partnerId',
    'public_partner_id',
    'publicPartnerId',
  ]) {
    final partner = value[key]?.toString();
    if (partner != null &&
        partner.startsWith('company:') &&
        partner != 'company:$tenant:$company')
      return false;
  }
  return value.values.every((child) => _ownScope(child, tenant, company));
}

Future<Map<String, dynamic>> fetchCompanyBookingContext(String slug) async {
  final client = http.Client();
  try {
    final request = http.Request(
      'GET',
      Uri.parse('$companyPublicBookingOrigin/api/$slug/app-context'),
    )..followRedirects = false;
    request.headers['Accept'] = 'application/json';
    // Public endpoint: no company/admin/driver credentials leave the backend.
    final response = await client
        .send(request)
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw const CompanyBookingLinkUnavailable();
    }
    final body = await response.stream.bytesToString().timeout(
      const Duration(seconds: 12),
    );
    final decoded = jsonDecode(body);
    if (decoded is! Map) throw const CompanyBookingLinkUnavailable();
    return Map<String, dynamic>.from(decoded);
  } finally {
    client.close();
  }
}

Future<CompanyPublicBookingLink> resolveCompanyPublicBookingLink({
  required String expectedCompanyId,
  required Future<Map<String, dynamic>> Function() profileLoader,
  CompanyBookingContextLoader contextLoader = fetchCompanyBookingContext,
  bool Function()? scopeIsCurrent,
}) async {
  void checkCurrent() {
    if (expectedCompanyId.trim().isEmpty || scopeIsCurrent?.call() == false) {
      throw const CompanyBookingLinkUnavailable();
    }
  }

  checkCurrent();
  final profile = await profileLoader();
  checkCurrent();
  final rows = <Map<String, dynamic>>[
    profile,
    for (final key in const ['company', 'business_profile'])
      if (profile[key] is Map) Map<String, dynamic>.from(profile[key] as Map),
  ];
  final company = _consistentText(rows, const ['company_id', 'companyId']);
  final tenant = _consistentText(rows, const ['tenant_id', 'tenantId']);
  if (company != expectedCompanyId.trim() ||
      !_ownScope(profile, tenant, company)) {
    throw const CompanyBookingLinkUnavailable();
  }
  final slugs = <String>{
    for (final row in rows)
      for (final key in const ['public_company_slug', 'publicCompanySlug'])
        if ((row[key]?.toString().trim() ?? '').isNotEmpty)
          row[key].toString().trim().toLowerCase(),
  };
  if (slugs.length != 1) throw const CompanyBookingLinkUnavailable();
  final slug = slugs.single;
  if (slug.length > 64 ||
      !RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(slug) ||
      RegExp(r'^flx-?\d+$').hasMatch(slug) ||
      const [
        'api',
        'assets',
        'book',
        'pages',
        'platform',
        'theme',
        'canonical',
      ].contains(slug)) {
    throw const CompanyBookingLinkUnavailable();
  }
  final context = await contextLoader(slug);
  checkCurrent();
  final publicCompany = context['company'];
  final publicProfile = context['profile'];
  if (context['ok'] != true ||
      context['slug'] != slug ||
      publicCompany is! Map ||
      publicProfile is! Map ||
      publicCompany['company_id'] != company ||
      publicCompany['tenant_id'] != tenant ||
      publicProfile['is_active'] != true ||
      publicProfile['bookable'] != true ||
      publicProfile['profile_enabled'] == false ||
      const [
        'inactive',
        'blocked',
        'suspended',
        'deleted',
        'closed',
        'retired',
      ].contains(publicProfile['account_state']?.toString().toLowerCase()) ||
      !_ownScope(context, tenant, company)) {
    throw const CompanyBookingLinkUnavailable();
  }
  final name = publicCompany['company_name']?.toString().trim() ?? '';
  if (name.isEmpty ||
      RegExp(r'^FLX-\d+', caseSensitive: false).hasMatch(name)) {
    throw const CompanyBookingLinkUnavailable();
  }
  final logo = Uri.tryParse(publicCompany['logo_url']?.toString() ?? '');
  return CompanyPublicBookingLink._(
    slug: slug,
    companyId: company,
    companyName: name,
    logoUrl: logo?.scheme == 'https' && logo!.host.isNotEmpty
        ? logo.toString()
        : '',
  );
}
