import 'dart:convert';

import 'package:http/http.dart' as http;

import 'driver_management_host_entry.dart';
import 'driver_management_read_entry.dart';

/// Native adapter for the recovered driver-management read contract.
/// Querying, projection, permissions, cursors and CSV stay server-owned.
class DriverManagementReadFailure implements Exception {
  const DriverManagementReadFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

typedef DriverManagementResponse = ({int status, String body});

class DriverManagementNativeRepository {
  DriverManagementNativeRepository({
    required this.companyId,
    required String authorization,
    required this.sessionUnchanged,
    String origin = driverManagementHostOrigin,
    Future<DriverManagementResponse> Function(Uri, Map<String, String>)? get,
    Future<DriverManagementResponse> Function(Uri, Map<String, String>, String)?
    post,
  }) : _authorization = authorization,
       _origin = DriverManagementHostEntry(origin).origin,
       _get = get ?? _httpsGet,
       _post = post ?? _httpsPost;

  final String companyId;
  final String _authorization;
  final Uri _origin;
  final Future<bool> Function() sessionUnchanged;
  final Future<DriverManagementResponse> Function(Uri, Map<String, String>)
  _get;
  final Future<DriverManagementResponse> Function(
    Uri,
    Map<String, String>,
    String,
  )
  _post;
  String? _tenant;
  bool _closed = false;
  List<String> vehicleTypes = const [];
  List<Map<String, dynamic>> vehicles = const [];
  Map<String, dynamic>? _partnerContext;
  bool get partnerWrite =>
      _partnerContext?['capabilities']?['partner_write'] == true;

  static Future<DriverManagementResponse> _httpsPost(
    Uri uri,
    Map<String, String> headers,
    String body,
  ) async {
    final client = http.Client();
    try {
      final request = http.Request('POST', uri)
        ..followRedirects = false
        ..headers.addAll(headers)
        ..body = body;
      final response = await http.Response.fromStream(
        await client.send(request).timeout(const Duration(seconds: 15)),
      );
      return (status: response.statusCode, body: response.body);
    } finally {
      client.close();
    }
  }

  static Future<DriverManagementResponse> _httpsGet(
    Uri uri,
    Map<String, String> headers,
  ) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', uri)
        ..followRedirects = false
        ..headers.addAll(headers);
      final response = await http.Response.fromStream(
        await client.send(request).timeout(const Duration(seconds: 15)),
      );
      return (status: response.statusCode, body: response.body);
    } finally {
      client.close();
    }
  }

  void close() {
    _closed = true;
    _tenant = null;
    vehicleTypes = const [];
    vehicles = const [];
    _partnerContext = null;
  }

  Future<void> assertSession() async {
    if (_closed ||
        companyId.isEmpty ||
        !_authorization.startsWith('Bearer ') ||
        _authorization.length <= 7 ||
        !await sessionUnchanged()) {
      close();
      throw const DriverManagementReadFailure(
        'Je bedrijfssessie is gewijzigd of verlopen. Meld je opnieuw aan.',
      );
    }
  }

  Future<DriverManagementResponse> _request(
    String path, [
    Map<String, String> query = const {},
  ]) async {
    await assertSession();
    final uri = _origin
        .resolve(path)
        .replace(queryParameters: query.isEmpty ? null : query);
    DriverManagementResponse response;
    try {
      response = await _get(uri, {'Authorization': _authorization});
    } catch (_) {
      throw const DriverManagementReadFailure(
        'De beheerhost is niet bereikbaar. Probeer opnieuw.',
      );
    }
    await assertSession();
    if (response.status != 200) {
      if (response.status == 401 || response.status == 403) close();
      throw DriverManagementReadFailure(switch (response.status) {
        401 => 'Je bedrijfslogin is verlopen. Meld je opnieuw aan.',
        403 => 'Je hebt geen toegang tot deze bedrijfsgegevens.',
        404 => 'Deze chauffeur is niet beschikbaar binnen je bedrijf.',
        409 => 'De bedrijfsbron of paginering is gewijzigd. Vernieuw de lijst.',
        _ =>
          'De beheerhost kon de gegevens niet veilig laden. Probeer opnieuw.',
      });
    }
    return response;
  }

  Map<String, dynamic> _decode(String body) {
    try {
      final value = jsonDecode(body);
      if (value is Map<String, dynamic> && value['ok'] == true) return value;
    } catch (_) {
      /* No raw response, token or personal data in errors. */
    }
    throw const DriverManagementReadFailure(
      'De beheerhost gaf geen geldige gegevens terug.',
    );
  }

  Future<void> connect() async {
    Map<String, dynamic>? ready;
    final access = await driverManagementReadAccess(
      entry: DriverManagementHostEntry(_origin.toString()),
      companyId: companyId,
      get: (uri) async {
        final response = await _request(uri.path);
        ready = _decode(response.body);
        return response;
      },
      sessionUnchanged: sessionUnchanged,
    );
    if (access != DriverManagementAccess.ready || ready == null) {
      throw const DriverManagementReadFailure(
        'Bedrijfstoegang niet beschikbaar. Controleer je bedrijfslogin en probeer opnieuw.',
      );
    }
    _tenant = (ready!['operator'] as Map)['tenant_id'] as String;
    final vehicles = ready!['vehicles'];
    if (vehicles is! List)
      throw const DriverManagementReadFailure('Voertuigbron niet geldig.');
    final vehicleIds = <String>{};
    for (final vehicle in vehicles) {
      _scope(vehicle);
      final id = vehicle['vehicle_id'];
      if (id is! String || id.isEmpty || !vehicleIds.add(id)) {
        close();
        throw const DriverManagementReadFailure(
          'De bedrijfsvloot bevat geen eenduidige voertuigen. Vernieuw de lijst.',
        );
      }
    }
    this.vehicles = List<Map<String, dynamic>>.unmodifiable(
      vehicles.map(
        (v) => Map<String, dynamic>.unmodifiable(v as Map<String, dynamic>),
      ),
    );
    vehicleTypes =
        vehicles
            .map((v) => '${v['vehicle_type'] ?? ''}')
            .where((v) => v.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
  }

  void _scope(dynamic value) {
    if (_tenant == null ||
        value is! Map ||
        value['company_id'] != companyId ||
        value['tenant_id'] != _tenant) {
      close();
      throw const DriverManagementReadFailure(
        'De gegevens horen niet bij je bedrijf. Toegang gestopt.',
      );
    }
  }

  Map<String, dynamic> _driver(dynamic value) {
    _scope(value);
    if (value['driver_id'] is! String ||
        (value['driver_id'] as String).isEmpty ||
        value['vehicles'] is! List) {
      throw const DriverManagementReadFailure(
        'Onvolledige chauffeurgegevens ontvangen.',
      );
    }
    final linkedVehicles = <Map<String, dynamic>>[];
    final linkedIds = <String>{};
    for (final vehicle in value['vehicles']) {
      // The published roster DTO omits scope on nested vehicles. Resolve their
      // IDs exclusively against the authenticated, strictly scoped own fleet.
      // Explicit foreign scope is never accepted, even for a known vehicle ID.
      if (vehicle is! Map ||
          vehicle['vehicle_id'] is! String ||
          (vehicle['vehicle_id'] as String).isEmpty) {
        throw const DriverManagementReadFailure(
          'Onvolledige voertuigkoppeling ontvangen. Vernieuw de lijst.',
        );
      }
      if ((vehicle.containsKey('tenant_id') &&
              vehicle['tenant_id'] != _tenant) ||
          (vehicle.containsKey('company_id') &&
              vehicle['company_id'] != companyId)) {
        close();
        throw const DriverManagementReadFailure(
          'De gegevens horen niet bij je bedrijf. Toegang gestopt.',
        );
      }
      final matches = vehicles.where(
        (own) => own['vehicle_id'] == vehicle['vehicle_id'],
      );
      if (matches.length != 1 ||
          !linkedIds.add(vehicle['vehicle_id'] as String)) {
        throw const DriverManagementReadFailure(
          'De voertuigkoppeling is gewijzigd. Vernieuw de lijst.',
        );
      }
      final own = matches.single;
      for (final key in const [
        'vehicle_name',
        'license_plate',
        'vehicle_type',
        'is_active',
      ]) {
        if (vehicle.containsKey(key) && vehicle[key] != own[key]) {
          throw const DriverManagementReadFailure(
            'De voertuiggegevens zijn gewijzigd. Vernieuw de lijst.',
          );
        }
      }
      linkedVehicles.add(own);
    }
    for (final trip in (value['recent_trips'] as List? ?? const [])) {
      _scope(trip);
    }
    if (value['current_trip'] != null) _scope(value['current_trip']);
    return Map<String, dynamic>.unmodifiable({
      ...value,
      'vehicles': List<Map<String, dynamic>>.unmodifiable(linkedVehicles),
    });
  }

  static const _queryKeys = {
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
    'cursor',
  };
  Map<String, String> _query(Map<String, String> query, {bool export = false}) {
    if (query.keys.any((key) => !_queryKeys.contains(key))) {
      throw const DriverManagementReadFailure('Ongeldige beheerfilter.');
    }
    return Map.fromEntries(
      query.entries.where(
        (e) => e.value.isNotEmpty && (!export || e.key != 'cursor'),
      ),
    );
  }

  Future<Map<String, dynamic>> list(Map<String, String> query) async {
    if (_tenant == null)
      throw const DriverManagementReadFailure(
        'Controleer eerst je bedrijfstoegang.',
      );
    final value = _decode(
      (await _request('/driver-management/api/drivers', _query(query))).body,
    );
    if (value['items'] is! List ||
        value['total'] is! int ||
        value['offset'] is! int ||
        (value['items'] as List).length > 100 ||
        (value['next_cursor'] != null && value['next_cursor'] is! String)) {
      throw const DriverManagementReadFailure(
        'De beheerhost gaf geen geldige pagina terug.',
      );
    }
    return {...value, 'items': (value['items'] as List).map(_driver).toList()};
  }

  Future<Map<String, dynamic>> detail(String id) async {
    if (_tenant == null)
      throw const DriverManagementReadFailure(
        'Controleer eerst je bedrijfstoegang.',
      );
    final value = _decode(
      (await _request('/driver-management/api/drivers/detail', {
        'driver_id': id,
      })).body,
    );
    final driver = _driver(value['driver']);
    if (driver['driver_id'] != id)
      throw const DriverManagementReadFailure(
        'De chauffeurselectie is gewijzigd.',
      );
    return driver;
  }

  Future<String> exportCsv(Map<String, String> query) async {
    if (_tenant == null)
      throw const DriverManagementReadFailure(
        'Controleer eerst je bedrijfstoegang.',
      );
    return (await _request(
      '/driver-management/api/drivers/export',
      _query(query, export: true),
    )).body;
  }

  // Same published partner directory DTO and authority as the recovered UI.
  // No settlement, payment, import or cross-company ownership writer here.
  Future<void> connectPartners() async {
    final data = _decode(
      (await _request('/driver-management/app-readiness')).body,
    );
    _scope(data['operator']);
    final caps = data['capabilities'];
    if (data['ready'] != true ||
        data['contract'] != 'fluxidi-driver-management-app-v2' ||
        data['roster_read_only'] != true ||
        caps is! Map ||
        caps['partner_read'] != true ||
        [
          'settlement_read',
          'settlement_write',
          'financial_rule_write',
          'import_write',
          'bulk_assign',
          'bulk_write',
        ].any((k) => caps[k] != false)) {
      throw const DriverManagementReadFailure(
        'Samenwerkingen zijn niet beschikbaar met je huidige bedrijfsrechten.',
      );
    }
    _partnerContext = data;
  }

  Map<String, dynamic> _partner(dynamic value) {
    _scope(value);
    if (value['id'] is! String ||
        value['business_name'] is! String ||
        value['revision'] is! int ||
        value['driver_ids'] is! List ||
        value['vehicle_ids'] is! List ||
        !(value['driver_ids'] as List).every((v) => v is String) ||
        !(value['vehicle_ids'] as List).every((v) => v is String)) {
      throw const DriverManagementReadFailure(
        'De partnergegevens zijn niet geldig.',
      );
    }
    return Map<String, dynamic>.unmodifiable(value);
  }

  Future<List<Map<String, dynamic>>> partners() async {
    if (_partnerContext == null) await connectPartners();
    final data = _decode(
      (await _request('/driver-management/api/drivers/partners')).body,
    );
    if (data['partners'] is! List || (data['partners'] as List).length > 501) {
      throw const DriverManagementReadFailure(
        'Het partneroverzicht kon niet veilig worden geladen.',
      );
    }
    final result = (data['partners'] as List).map(_partner).toList();
    if (result.map((p) => p['id']).toSet().length != result.length) {
      throw const DriverManagementReadFailure(
        'Dubbele partnergegevens ontvangen. Vernieuw het overzicht.',
      );
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> driverOptions() async {
    final items = <String, Map<String, dynamic>>{};
    var cursor = '';
    final seen = <String>{};
    for (var i = 0; i < 100; i++) {
      final page = await list({
        'limit': '100',
        'cursor': cursor,
        'sort': 'name',
        'direction': 'asc',
      });
      for (final d in page['items']) {
        items[d['driver_id'] as String] = d as Map<String, dynamic>;
      }
      final next = page['next_cursor'];
      if (next == null) return items.values.toList();
      if (next is! String || !seen.add(next)) break;
      cursor = next;
    }
    throw const DriverManagementReadFailure(
      'Te veel chauffeurs voor deze selectie. Vernauw de selectie via chauffeurbeheer.',
    );
  }

  Future<Map<String, dynamic>> savePartner(Map<String, dynamic> draft) async {
    await assertSession();
    if (!partnerWrite)
      throw const DriverManagementReadFailure(
        'Je hebt geen recht om partnerbedrijven te wijzigen.',
      );
    const keys = {
      'id',
      'business_name',
      'contact_person',
      'relationship_type',
      'status',
      'expected_revision',
      'driver_ids',
      'vehicle_ids',
      'rule_id',
      'rule_version',
    };
    if (draft.keys.any((k) => !keys.contains(k)))
      throw const DriverManagementReadFailure('Ongeldige partnerwijziging.');
    final uri = _origin.resolve('/driver-management/api/drivers/partners');
    final result = await _post(uri, {
      'Authorization': _authorization,
      'Content-Type': 'application/json',
      'Origin': _origin.origin,
      'x-driver-management': '1',
    }, jsonEncode({'confirm': true, 'partner': draft}));
    await assertSession();
    if (result.status != 200) {
      if (result.status == 401 || result.status == 403) close();
      throw DriverManagementReadFailure(switch (result.status) {
        401 => 'Je bedrijfslogin is verlopen. Meld je opnieuw aan.',
        403 => 'Je hebt geen recht om deze partnergegevens te wijzigen.',
        409 =>
          'De partner is gewijzigd of heeft een afgeschermde financiële koppeling. Vernieuw en controleer de bestaande gegevens.',
        _ => 'Partnergegevens konden niet veilig worden opgeslagen.',
      });
    }
    final saved = _partner(_decode(result.body)['partner']);
    if (saved['id'] != draft['id']) {
      close();
      throw const DriverManagementReadFailure(
        'De partnerselectie is gewijzigd.',
      );
    }
    return saved;
  }
}
