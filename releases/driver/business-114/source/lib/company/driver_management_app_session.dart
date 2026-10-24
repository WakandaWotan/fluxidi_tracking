import 'dart:convert';
import 'package:http/http.dart' as http;
import 'driver_management_host_entry.dart';

class DriverManagementAppFailure implements Exception {
  const DriverManagementAppFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Existing company login -> one-use host ticket. Credentials never enter
/// JavaScript, URLs, local storage or an independent login form.
class DriverManagementAppSession {
  DriverManagementAppSession({
    required this.companyId,
    required this.authorization,
    required this.expiresAt,
    required this.sessionUnchanged,
    this.role = 'companyAdmin',
    this.synthetic = false,
    DriverManagementHostEntry? host,
    http.Client? client,
  }) : host = host ?? DriverManagementHostEntry(driverManagementHostOrigin),
       _client = client ?? http.Client();

  final String companyId, authorization, role;
  final DateTime? expiresAt;
  final bool synthetic;
  final DriverManagementHostEntry host;
  final Future<bool> Function() sessionUnchanged;
  final http.Client _client;
  String? tenantId;
  bool _closed = false;

  Future<void> _current() async {
    if (_closed ||
        synthetic ||
        role != 'companyAdmin' ||
        companyId.isEmpty ||
        !authorization.startsWith('Bearer ') ||
        (expiresAt != null && !expiresAt!.isAfter(DateTime.now().toUtc())) ||
        !await sessionUnchanged()) {
      throw const DriverManagementAppFailure(
        'Je bedrijfssessie is gewijzigd of verlopen.',
      );
    }
  }

  Future<http.Response> _send(String method, Uri uri) async {
    await _current();
    if (uri.origin != host.origin.origin ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      throw const DriverManagementAppFailure('Ongeldige beheerhost.');
    }
    final request = http.Request(method, uri)
      ..followRedirects = false
      ..headers.addAll({
        'Authorization': authorization,
        'x-driver-management': '1',
        'Content-Type': 'application/json',
      });
    final response = await http.Response.fromStream(
      await _client.send(request).timeout(const Duration(seconds: 15)),
    );
    await _current();
    if (response.statusCode != 200) {
      throw DriverManagementAppFailure(
        response.statusCode == 401
            ? 'Je bedrijfssessie is verlopen.'
            : response.statusCode == 403
            ? 'Je bedrijfsrechten geven geen toegang tot dit onderdeel.'
            : 'De beheerhost is tijdelijk niet beschikbaar. Probeer opnieuw.',
      );
    }
    return response;
  }

  Future<Uri> connect() async {
    final response = await _send(
      'GET',
      host.origin.resolve('/driver-management/app-readiness'),
    );
    final data = jsonDecode(response.body);
    final operator = data is Map ? data['operator'] : null;
    final caps = data is Map ? data['capabilities'] : null;
    if (data is! Map ||
        data['ok'] != true ||
        data['ready'] != true ||
        data['contract'] != 'fluxidi-driver-management-app-v2' ||
        data['roster_read_only'] != true ||
        operator is! Map ||
        operator['company_id'] != companyId ||
        operator['tenant_id'] is! String ||
        (operator['tenant_id'] as String).trim().isEmpty ||
        caps is! Map ||
        caps['drivers_read'] != true ||
        caps['partner_read'] != true ||
        caps['export_csv'] != true ||
        [
          'settlement_read',
          'settlement_write',
          'financial_rule_write',
          'import_write',
          'bulk_assign',
          'bulk_write',
        ].any((key) => caps[key] != false)) {
      throw const DriverManagementAppFailure(
        'De beheeromgeving is nog niet veilig aangesloten voor je bedrijf.',
      );
    }
    tenantId = operator['tenant_id'] as String;
    return host.open(
      companyId: companyId,
      role: role,
      expiresAt: expiresAt,
      ownerHeaders: {'Authorization': authorization},
      synthetic: synthetic,
      post: (uri, headers) async {
        final r = await _send('POST', uri);
        return (status: r.statusCode, body: r.body);
      },
      sessionUnchanged: sessionUnchanged,
    );
  }

  bool allowsNavigation(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.origin != host.origin.origin ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery)
      return false;
    if (uri.path == '/driver-management/handoff')
      return RegExp(r'^[a-f0-9]{64}$').hasMatch(uri.fragment);
    return (uri.path == '/driver-management/' ||
            uri.path == '/driver-management') &&
        ['', 'partners', 'drivers'].contains(uri.fragment);
  }

  Future<String> exportCsv(String raw) async {
    final uri = Uri.tryParse(raw);
    const allowed = {
      'q',
      'status',
      'active',
      'vehicle',
      'vehicle_type',
      'plate',
      'seen_after',
      'seen_before',
      'sort',
      'direction',
      'limit',
      'company_id',
      'tenant_id',
    };
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.origin != host.origin.origin ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.path != '/driver-management/api/drivers/export' ||
        uri.queryParametersAll.entries.any(
          (e) => !allowed.contains(e.key) || e.value.length != 1,
        ) ||
        (uri.queryParameters.containsKey('company_id') &&
            uri.queryParameters['company_id'] != companyId) ||
        (uri.queryParameters.containsKey('tenant_id') &&
            uri.queryParameters['tenant_id'] != tenantId)) {
      throw const DriverManagementAppFailure(
        'Deze export hoort niet bij je bedrijfsomgeving.',
      );
    }
    final response = await _send('GET', uri);
    if (!(response.headers['content-type'] ?? '').startsWith('text/csv') ||
        response.bodyBytes.length > 8 * 1024 * 1024) {
      throw const DriverManagementAppFailure(
        'De host gaf geen geldige chauffeursexport terug.',
      );
    }
    return response.body;
  }

  void close() {
    _closed = true;
    _client.close();
  }
}
