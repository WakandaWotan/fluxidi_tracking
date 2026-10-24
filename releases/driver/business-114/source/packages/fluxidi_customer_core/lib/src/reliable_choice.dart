import 'dart:convert';
import 'package:http/http.dart' as http;

/// Reads authorised server evidence. No route provider, eligibility or fare
/// calculation lives in this client. Credentials never appear in URLs/logs.
class ReliableChoiceApiV1 {
  ReliableChoiceApiV1({required this.base, required this.token, required this.client});
  final Uri base;
  final String token;
  final http.Client client;
  static final _id = RegExp(r'^[a-zA-Z0-9_.:-]{1,128}$');
  Uri _url(String path, [Map<String, String>? query]) {
    if (base.userInfo.isNotEmpty || base.hasQuery || base.hasFragment ||
        !(base.scheme == 'https' || base.scheme == 'http' && ['localhost', '127.0.0.1', '::1'].contains(base.host))) {
      throw StateError('reliable_base_invalid');
    }
    return base.replace(path: path, queryParameters: query);
  }
  Future<Map<String, dynamic>> _call(String path, {Map<String, String>? query, Map<String, dynamic>? body}) async {
    if (token.isEmpty || token.contains('\n') || token.contains('\r')) throw StateError('reliable_session_required');
    final headers = {'authorization': 'Bearer $token', 'content-type': 'application/json'};
    final url = _url(path, query);
    final response = body == null ? await client.get(url, headers: headers) : await client.post(url, headers: headers, body: jsonEncode(body));
    if (response.bodyBytes.length > 128000 || response.statusCode != 200) throw StateError('reliable_request_failed');
    final result = jsonDecode(response.body);
    if (result is! Map<String, dynamic> || result['ok'] != true) throw StateError('reliable_response_invalid');
    return result;
  }
  String _booking(String id) {
    if (!_id.hasMatch(id)) throw StateError('reliable_booking_invalid');
    return '/public/customer/reliable-choice/$id/';
  }
  Future<List<Map<String, dynamic>>> vehicles(String id, {int? nowMs}) async {
    final result = await _call('${_booking(id)}vehicles'), rows = result['vehicles'];
    if (result['schema'] != 'fluxidi-reliable-choice-v1' || rows is! List || rows.length > 10) throw StateError('reliable_list_invalid');
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final output = <Map<String, dynamic>>[], seen = <String>{};
    for (final row in rows) {
      if (row is! Map<String, dynamic> || row['schema'] != 'fluxidi-reliable-choice-v1' || row['estimate'] != true ||
          row['vehicle_id'] is! String || !_id.hasMatch(row['vehicle_id']) || !seen.add(row['vehicle_id']) ||
          row['valid_until_ms'] is! int || row['valid_until_ms'] <= now || row['evidence_revision'] is! String || row['evidence_revision'].isEmpty ||
          row['graph_version'] is! String || row['graph_version'].isEmpty) throw StateError('reliable_vehicle_invalid');
      final range = row['pickup_eta_range_seconds'], seconds = row['pickup_eta_seconds'], distance = row['pickup_distance_meters'];
      if (row['status'] == 'available_for_selected_time') {
        if (range != null || seconds != null || distance != null) throw StateError('reliable_scheduled_invalid');
      } else if (row['status'] != 'estimated_availability' || row['route_evidence_id'] is! String || row['route_evidence_id'].isEmpty || range is! List || range.length != 2 || range.any((x) => x is! num || !x.isFinite || x < 0) ||
          range[1] < range[0] || seconds is! num || !seconds.isFinite || seconds < range[0] || seconds > range[1] || distance is! num || !distance.isFinite || distance < 0) {
        throw StateError('reliable_estimate_invalid');
      }
      // Whitelist the public projection, even if an incompatible server sends
      // driver/traffic fields accidentally. It never enters customer UI state.
      const fields = ['schema','vehicle_id','vehicle_name','vehicle_type','vehicle_category','photo_url','passenger_capacity','luggage_capacity','pickup_eta_seconds','pickup_eta_range_seconds','pickup_distance_meters','status','estimate','graph_version','route_evidence_id','evidence_revision','valid_until_ms'];
      output.add({for (final key in fields) if (row.containsKey(key)) key: row[key]});
    }
    return output;
  }
  Future<Map<String, dynamic>> choose(String booking, String vehicle, {String kind = 'exact'}) {
    if (!_id.hasMatch(vehicle) || !['exact','type'].contains(kind)) throw StateError('reliable_choice_invalid');
    return _call('${_booking(booking)}choice', body: {'vehicle_id': vehicle, 'kind': kind});
  }
  Future<Map<String, dynamic>> status(String id) => _call('${_booking(id)}status');
  Future<List<Map<String, dynamic>>> dispatcherQueue(String tenant, String company) async {
    if (!_id.hasMatch(tenant) || !_id.hasMatch(company)) throw StateError('reliable_scope_invalid');
    final result = await _call('/admin/company/reliable-choice/queue', query: {'tenant_id': tenant, 'company_id': company});
    final rows = result['items'];
    if (rows is! List || rows.length > 25 || rows.any((r) => r is! Map<String, dynamic> || r['tenant_id'] != tenant || r['company_id'] != company)) throw StateError('reliable_dispatcher_scope');
    return rows.cast<Map<String, dynamic>>();
  }
  Future<Map<String, dynamic>> manualAssign(String booking, String tenant, String company, String vehicle, String driver) {
    if ([booking,tenant,company,vehicle,driver].any((id) => !_id.hasMatch(id))) throw StateError('reliable_assignment_invalid');
    return _call('/company/agenda/rides/$booking/assign', body: {'tenant_id':tenant,'company_id':company,'assigned_vehicle_id':vehicle,'assigned_driver_id':driver});
  }
}
