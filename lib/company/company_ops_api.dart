// COMPANY-CUSTOMER-OPS-P0 — existing Worker contracts for the Windows company route.

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:fluxidi_tracking/company/booking_list_page_repository.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';
import 'package:fluxidi_tracking/company/company_customers_repository_factory_web.dart';
import 'package:fluxidi_tracking/company/company_ops_session.dart'
    show companyOpsSessionIsReady;

export 'package:fluxidi_tracking/company/company_customers_repository_factory_web.dart'
    show
        companyOpsLocalDemoBase,
        fetchCompanyLocalBooking,
        fetchCompanyOpsBusinessProfile,
        resolveCompanyOpsLocalSession;

Future<Map<String, String>> companyOpsHeaders() async {
  final session = resolveCompanyOpsLocalSession();
  return <String, String>{
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ${session.sessionToken}',
  };
}

Map<String, String> companyOpsScope() {
  final id = resolveCompanyOpsLocalSession().companyId.trim();
  return <String, String>{
    'tenant_id': id,
    'company_id': id,
    'tenantId': id,
    'companyId': id,
  };
}

Map<String, dynamic> decodeCompanyOpsJson(List<int> bytes) {
  final decoded = jsonDecode(utf8.decode(bytes));
  if (decoded is! Map) {
    throw const CompanyCustomerException('invalid_payload');
  }
  return Map<String, dynamic>.from(decoded);
}

Future<Map<String, dynamic>> loadCompanyOpsBookingListPage({
  required BookingListPageRequest request,
  required int limit,
  required Future<Map<String, String>> Function() headers,
}) async {
  final query = buildBookingListPageQuery(request: request, limit: limit);
  final uri = Uri.parse(
    '${companyOpsLocalDemoBase()}${request.path}',
  ).replace(queryParameters: query);
  final res = await http
      .get(uri, headers: await headers())
      .timeout(const Duration(seconds: 12));
  dynamic decoded;
  try {
    decoded = jsonDecode(utf8.decode(res.bodyBytes));
  } catch (_) {
    decoded = null;
  }
  if (res.statusCode != 200) {
    final apiError = decoded is Map
        ? (decoded['error']?.toString().trim() ?? '')
        : '';
    throw BookingListPageException(
      apiError.isNotEmpty ? apiError : 'http_${res.statusCode}',
    );
  }
  if (decoded is! Map) {
    throw BookingListPageException('invalid_payload');
  }
  return Map<String, dynamic>.from(decoded);
}

final BookingListPageRepository companyOpsBookingListRepository =
    BookingListPageRepository(transport: loadCompanyOpsBookingListPage);

Future<BookingListPageResult> fetchCompanyOpsBookingPage({
  String cursor = '',
  bool forceRefresh = false,
}) async {
  final scope = companyOpsScope();
  final companyId = scope['company_id'] ?? '';
  return companyOpsBookingListRepository.fetch(
    request: BookingListPageRequest(
      actor: BookingListActor.company,
      tenantId: companyId,
      companyId: companyId,
      historyMode: BookingListHistoryMode.active,
      cursor: cursor,
      scopeQuery: scope,
    ),
    headers: companyOpsHeaders,
    forceRefresh: forceRefresh,
    reason: cursor.trim().isEmpty
        ? (forceRefresh
              ? BookingListPageReason.manualRefresh
              : BookingListPageReason.opportunistic)
        : BookingListPageReason.nextPage,
  );
}

Future<Map<String, dynamic>> fetchCompanyOpsBookingDetail(String bookingId) {
  return fetchCompanyLocalBooking(bookingId);
}

Future<Map<String, dynamic>> saveCompanyOpsBusinessProfile(
  Map<String, dynamic> profile,
) async {
  final scope = companyOpsScope();
  final uri = Uri.parse(
    '${companyOpsLocalDemoBase()}/admin/business/profile',
  ).replace(queryParameters: scope);
  final res = await http
      .post(
        uri,
        headers: await companyOpsHeaders(),
        body: jsonEncode(<String, dynamic>{
          ...scope,
          'business_profile': profile,
        }),
      )
      .timeout(const Duration(seconds: 12));
  final decoded = decodeCompanyOpsJson(res.bodyBytes);
  if (res.statusCode < 200 || res.statusCode >= 300 || decoded['ok'] != true) {
    throw CompanyCustomerException(
      decoded['error']?.toString() ?? 'business_profile_save_failed',
    );
  }
  final saved = decoded['business_profile'];
  if (saved is Map) return Map<String, dynamic>.from(saved);
  return decoded;
}

Future<String> uploadCompanyOpsPartnerMedia({
  required String mediaType,
  required Uint8List bytes,
  required String filename,
  String? contentType,
}) async {
  final scope = companyOpsScope();
  final uri = Uri.parse(
    '${companyOpsLocalDemoBase()}/admin/partners/media/upload',
  ).replace(queryParameters: scope);
  final request = http.MultipartRequest('POST', uri);
  request.headers['Authorization'] =
      'Bearer ${resolveCompanyOpsLocalSession().sessionToken}';
  request.headers['Accept'] = 'application/json';
  request.fields['tenant_id'] = scope['tenant_id'] ?? '';
  request.fields['company_id'] = scope['company_id'] ?? '';
  request.fields['media_type'] = mediaType;
  request.files.add(
    http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: filename,
      contentType: MediaType.parse(
        (contentType ?? '').trim().isEmpty ? 'image/png' : contentType!.trim(),
      ),
    ),
  );
  final streamed = await request.send().timeout(const Duration(seconds: 20));
  final res = await http.Response.fromStream(streamed);
  final decoded = decodeCompanyOpsJson(res.bodyBytes);
  if (res.statusCode < 200 || res.statusCode >= 300 || decoded['ok'] != true) {
    throw CompanyCustomerException(
      decoded['error']?.toString() ?? 'media_upload_failed',
    );
  }
  final url = (decoded['url'] ?? '').toString().trim();
  if (url.isEmpty) {
    throw const CompanyCustomerException('media_url_missing');
  }
  return url;
}

Future<List<Map<String, dynamic>>> fetchCompanyOpsVehicles() async {
  if (!companyOpsSessionIsReady(resolveCompanyOpsLocalSession())) {
    return const <Map<String, dynamic>>[];
  }
  final uri = Uri.parse(
    '${companyOpsLocalDemoBase()}/admin/fleet/vehicles',
  ).replace(queryParameters: companyOpsScope());
  final res = await http
      .get(uri, headers: await companyOpsHeaders())
      .timeout(const Duration(seconds: 12));
  final decoded = decodeCompanyOpsJson(res.bodyBytes);
  if (res.statusCode != 200 || decoded['ok'] != true) {
    throw CompanyCustomerException(
      decoded['error']?.toString() ?? 'fleet_list_failed',
    );
  }
  final vehicles = decoded['vehicles'];
  if (vehicles is! List) return const <Map<String, dynamic>>[];
  return [
    for (final item in vehicles)
      if (item is Map) Map<String, dynamic>.from(item),
  ];
}

Future<List<Map<String, dynamic>>> saveCompanyOpsVehicles(
  List<Map<String, dynamic>> vehicles,
) async {
  final scope = companyOpsScope();
  final uri = Uri.parse(
    '${companyOpsLocalDemoBase()}/admin/fleet/vehicles',
  ).replace(queryParameters: scope);
  final res = await http
      .post(
        uri,
        headers: await companyOpsHeaders(),
        body: jsonEncode(<String, dynamic>{
          ...scope,
          'vehicles': vehicles,
        }),
      )
      .timeout(const Duration(seconds: 12));
  final decoded = decodeCompanyOpsJson(res.bodyBytes);
  if (res.statusCode < 200 || res.statusCode >= 300 || decoded['ok'] != true) {
    throw CompanyCustomerException(
      decoded['error']?.toString() ?? 'fleet_save_failed',
    );
  }
  final saved = decoded['vehicles'];
  if (saved is! List) return vehicles;
  return [
    for (final item in saved)
      if (item is Map) Map<String, dynamic>.from(item),
  ];
}

Future<List<Map<String, dynamic>>> fetchCompanyOpsDrivers() async {
  if (!companyOpsSessionIsReady(resolveCompanyOpsLocalSession())) {
    return const <Map<String, dynamic>>[];
  }
  final uri = Uri.parse(
    '${companyOpsLocalDemoBase()}/admin/company/drivers/index',
  ).replace(queryParameters: companyOpsScope());
  final res = await http
      .get(uri, headers: await companyOpsHeaders())
      .timeout(const Duration(seconds: 12));
  final decoded = decodeCompanyOpsJson(res.bodyBytes);
  if (res.statusCode != 200 || decoded['ok'] != true) {
    throw CompanyCustomerException(
      decoded['error']?.toString() ?? 'drivers_list_failed',
    );
  }
  final drivers = decoded['drivers'];
  if (drivers is! List) return const <Map<String, dynamic>>[];
  return [
    for (final item in drivers)
      if (item is Map) Map<String, dynamic>.from(item),
  ];
}

Future<void> upsertCompanyOpsDriver(Map<String, dynamic> driver) async {
  final scope = companyOpsScope();
  final uri = Uri.parse(
    '${companyOpsLocalDemoBase()}/admin/company/drivers/index/upsert',
  ).replace(queryParameters: scope);
  final res = await http
      .post(
        uri,
        headers: await companyOpsHeaders(),
        body: jsonEncode(<String, dynamic>{...scope, ...driver}),
      )
      .timeout(const Duration(seconds: 12));
  final decoded = decodeCompanyOpsJson(res.bodyBytes);
  if (res.statusCode < 200 || res.statusCode >= 300 || decoded['ok'] != true) {
    throw CompanyCustomerException(
      decoded['error']?.toString() ?? 'driver_upsert_failed',
    );
  }
}

Future<void> deleteCompanyOpsDriver(String driverId) async {
  final scope = companyOpsScope();
  final uri = Uri.parse(
    '${companyOpsLocalDemoBase()}/admin/company/drivers/index/delete',
  ).replace(queryParameters: scope);
  final res = await http
      .post(
        uri,
        headers: await companyOpsHeaders(),
        body: jsonEncode(<String, dynamic>{
          ...scope,
          'driver_id': driverId,
        }),
      )
      .timeout(const Duration(seconds: 12));
  final decoded = decodeCompanyOpsJson(res.bodyBytes);
  if (res.statusCode < 200 || res.statusCode >= 300 || decoded['ok'] != true) {
    throw CompanyCustomerException(
      decoded['error']?.toString() ?? 'driver_delete_failed',
    );
  }
}

Future<Map<String, dynamic>> fetchCompanyOpsSubscriptionProfile() async {
  final uri = Uri.parse(
    '${companyOpsLocalDemoBase()}/company/subscription/profile',
  ).replace(queryParameters: companyOpsScope());
  final res = await http
      .get(uri, headers: await companyOpsHeaders())
      .timeout(const Duration(seconds: 12));
  final decoded = decodeCompanyOpsJson(res.bodyBytes);
  if (res.statusCode != 200 || decoded['ok'] != true) {
    throw CompanyCustomerException(
      decoded['error']?.toString() ?? 'subscription_profile_failed',
    );
  }
  final profile = decoded['subscription_profile'] ?? decoded['profile'];
  if (profile is Map) return Map<String, dynamic>.from(profile);
  return decoded;
}

int companyOpsMaxVehicles(Map<String, dynamic> profile) {
  final raw = profile['max_vehicles'] ?? profile['maxVehicles'] ?? 1;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw.toString()) ?? 1;
}

int companyOpsMaxDrivers(Map<String, dynamic> profile) {
  final raw = profile['max_drivers'] ?? profile['maxDrivers'] ?? 1;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw.toString()) ?? 1;
}

enum CompanyBookingCancelScope { fullRoundtrip, singleLeg }

Future<void> cancelCompanyOpsBooking({
  required String bookingId,
  String parentBookingId = '',
  String legId = '',
  String legType = '',
  CompanyBookingCancelScope scope = CompanyBookingCancelScope.fullRoundtrip,
}) async {
  final parent = parentBookingId.trim().isNotEmpty
      ? parentBookingId.trim()
      : bookingId.trim();
  if (parent.isEmpty) {
    throw const CompanyCustomerException('missing_booking_id');
  }
  final cancelSingleLeg =
      scope == CompanyBookingCancelScope.singleLeg && legId.trim().isNotEmpty;
  final scopeQuery = companyOpsScope();
  final path = cancelSingleLeg
      ? '/bookings/${Uri.encodeComponent(parent)}/legs/${Uri.encodeComponent(legId.trim())}/status'
      : '/bookings/${Uri.encodeComponent(parent)}/status';
  final uri = Uri.parse('${companyOpsLocalDemoBase()}$path').replace(
    queryParameters: scopeQuery,
  );
  final payload = <String, dynamic>{
    ...scopeQuery,
    'booking_id': parent,
    'parent_booking_id': parent,
    'parentBookingId': parent,
    'status': 'CANCELLED',
    'actor_role': 'admin',
    'actorRole': 'admin',
    if (cancelSingleLeg) ...<String, dynamic>{
      'leg_id': legId.trim(),
      'legId': legId.trim(),
      if (legType.trim().isNotEmpty) 'leg_type': legType.trim(),
      if (legType.trim().isNotEmpty) 'legType': legType.trim(),
      'cancel_scope': 'single_leg',
      'cancelScope': 'single_leg',
    } else ...<String, dynamic>{
      'cancel_scope': 'full_roundtrip',
      'cancelScope': 'full_roundtrip',
    },
  };
  final res = await http
      .post(
        uri,
        headers: await companyOpsHeaders(),
        body: jsonEncode(payload),
      )
      .timeout(const Duration(seconds: 15));
  final decoded = decodeCompanyOpsJson(res.bodyBytes);
  if (res.statusCode != 200 || decoded['ok'] != true) {
    throw CompanyCustomerException(
      decoded['error']?.toString().trim().isNotEmpty == true
          ? decoded['error'].toString()
          : 'http_${res.statusCode}',
    );
  }
}

Future<Map<String, dynamic>> fetchCompanyFixedPrices() async {
  final uri = Uri.parse(
    '${companyOpsLocalDemoBase()}/company/fixed-prices',
  ).replace(queryParameters: companyOpsScope());
  final res = await http
      .get(uri, headers: await companyOpsHeaders())
      .timeout(const Duration(seconds: 12));
  final decoded = decodeCompanyOpsJson(res.bodyBytes);
  if (res.statusCode != 200 || decoded['ok'] != true) {
    throw CompanyCustomerException(
      decoded['error']?.toString() ?? 'fixed_prices_load_failed',
    );
  }
  final doc = decoded['company_fixed_prices'];
  if (doc is Map) return Map<String, dynamic>.from(doc);
  return <String, dynamic>{'fallback': 'calculator', 'rules': <dynamic>[]};
}

Future<Map<String, dynamic>> saveCompanyFixedPrices(
  Map<String, dynamic> document, {
  String view = 'all',
}) async {
  final scope = companyOpsScope();
  final uri = Uri.parse(
    '${companyOpsLocalDemoBase()}/company/fixed-prices',
  ).replace(queryParameters: scope);
  final expected = document['updated_at']?.toString().trim() ?? '';
  final res = await http
      .post(
        uri,
        headers: await companyOpsHeaders(),
        body: jsonEncode(<String, dynamic>{
          ...scope,
          'view': view,
          if (expected.isNotEmpty) 'expected_updated_at': expected,
          'company_fixed_prices': document,
        }),
      )
      .timeout(const Duration(seconds: 15));
  final decoded = decodeCompanyOpsJson(res.bodyBytes);
  if (res.statusCode != 200 || decoded['ok'] != true) {
    throw CompanyCustomerException(
      decoded['error']?.toString() ?? 'fixed_prices_save_failed',
    );
  }
  final doc = decoded['company_fixed_prices'];
  if (doc is Map) return Map<String, dynamic>.from(doc);
  return document;
}

Future<Map<String, dynamic>> previewCompanyFixedPrice(
  Map<String, dynamic> payload,
) async {
  final scope = companyOpsScope();
  final uri = Uri.parse(
    '${companyOpsLocalDemoBase()}/company/fixed-prices/preview',
  ).replace(queryParameters: scope);
  final res = await http
      .post(
        uri,
        headers: await companyOpsHeaders(),
        body: jsonEncode(<String, dynamic>{...scope, ...payload}),
      )
      .timeout(const Duration(seconds: 12));
  final decoded = decodeCompanyOpsJson(res.bodyBytes);
  if (res.statusCode != 200 || decoded['ok'] != true) {
    throw CompanyCustomerException(
      decoded['error']?.toString() ?? 'fixed_price_preview_failed',
    );
  }
  return decoded;
}
