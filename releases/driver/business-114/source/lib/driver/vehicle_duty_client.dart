import 'dart:convert';
import 'package:http/http.dart' as http;
import 'vehicle_duty_report.dart';

class VehicleDutyException implements Exception {
  const VehicleDutyException(this.code);
  final String code;
}

/// Personal driver bearer only. Never accepts a company/admin token fallback.
class VehicleDutyClient {
  VehicleDutyClient({
    required this.baseUrl,
    required this.token,
    required this.driverId,
    required this.vehicleId,
    http.Client? client,
    this.isCurrent,
  }) : _client = client ?? http.Client();
  final String baseUrl, token, driverId, vehicleId;
  final http.Client _client;
  final bool Function()? isCurrent;
  void _checkOwner() {
    if (isCurrent?.call() == false) throw const VehicleDutyException('driver_session_changed');
  }
  void close() => _client.close();
  Future<Map<String, dynamic>> _request(
    String path,
    Map<String, dynamic> body,
  ) async {
    _checkOwner();
    if (token.isEmpty || driverId.isEmpty)
      throw const VehicleDutyException('driver_auth_required');
    final response = await _client
        .post(
          Uri.parse('$baseUrl/public/driver/$path'),
          headers: {
            'authorization': 'Bearer $token',
            'content-type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    _checkOwner();
    final dynamic decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>)
      throw const VehicleDutyException('invalid_response');
    if (response.statusCode >= 400 || decoded['ok'] != true) {
      final code = decoded['error'];
      throw VehicleDutyException(
        code is String && RegExp(r'^[a-z_]{1,80}$').hasMatch(code)
            ? code
            : 'request_failed',
      );
    }
    return decoded;
  }

  Future<Map<String, dynamic>> state() async {
    final result = await _request('vehicle-duty-state', {});
    if (result['version'] is! int ||
        result['duties'] is! List ||
        (result['duties'] as List).length > 1)
      throw const VehicleDutyException('invalid_response');
    for (final duty in result['duties'] as List) {
      if (duty is! Map ||
          duty['driver_id'] != driverId ||
          duty['vehicle_id'] != vehicleId ||
          duty['duty_id'] is! String)
        throw const VehicleDutyException('invalid_response');
    }
    return result;
  }

  Future<Map<String, dynamic>> command(Map<String, dynamic> command) =>
      _request('vehicle-duty', {...command, 'vehicle_id': vehicleId});
  Future<Map<String, dynamic>> history({String? cursor}) async {
    final result = await _request('vehicle-duty-history', {
      if (cursor != null) 'cursor': cursor,
    });
    if (result['items'] is! List ||
        result['cursor'] != null && result['cursor'] is! String)
      throw const VehicleDutyException('invalid_response');
    for (final duty in result['items'] as List) {
      try {
        VehicleDutyReport.validateRow(duty, driverId);
      } on FormatException {
        throw const VehicleDutyException('invalid_response');
      }
    }
    return result;
  }
}
