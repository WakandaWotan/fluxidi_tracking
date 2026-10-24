import 'dart:convert';

import 'package:http/http.dart' as http;
import 'vehicle_duty_client.dart';

/// End the personal driver's existing duty/availability, keeping device and
/// company credentials untouched. The backend derives the actor from the bearer.
Future<void> confirmDriverOfflineForSwitch({
  required String bookingBaseUrl,
  required String token,
  required String tenantId,
  required String companyId,
  required String driverId,
  required String vehicleId,
  required bool Function() isCurrent,
  http.Client? client,
}) async {
  if ([token, tenantId, companyId, driverId].any((s) => s.trim().isEmpty)) {
    throw const VehicleDutyException('driver_auth_required');
  }
  final transport = client ?? http.Client();
  final duty = VehicleDutyClient(baseUrl: bookingBaseUrl, token: token,
    driverId: driverId, vehicleId: vehicleId, client: transport);
  void checkCurrent() {
    if (!isCurrent()) throw const VehicleDutyException('driver_session_changed');
  }
  Future<Map<String, dynamic>> request(String path, {Map<String, dynamic>? body}) async {
    checkCurrent();
    final uri = Uri.parse('${bookingBaseUrl.replaceFirst(RegExp(r'/+$'), '')}$path');
    final headers = {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
    final response = await (body == null ? transport.get(uri, headers: headers)
        : transport.post(uri, headers: headers, body: jsonEncode(body)))
      .timeout(const Duration(seconds: 15));
    checkCurrent();
    final dynamic result = jsonDecode(response.body);
    if (result is! Map<String, dynamic> || response.statusCode != 200 || result['ok'] != true) {
      final code = result is Map ? result['error'] : null;
      throw VehicleDutyException(code is String && RegExp(r'^[a-z_]{1,80}$').hasMatch(code)
        ? code : 'driver_offline_not_confirmed');
    }
    if (result['tenant_id'] != tenantId || result['company_id'] != companyId ||
        result['driver_id'] != driverId) {
      throw const VehicleDutyException('driver_session_scope_mismatch');
    }
    return result;
  }
  try {
    // This read also fences busy state for the existing (non-manual-duty) policy.
    final before = await request('/public/driver/status');
    final driver = before['driver'];
    if (driver is! Map || driver['driver_id'] != driverId) {
      throw const VehicleDutyException('invalid_response');
    }
    if (const ['busy', 'on_trip', 'in_progress'].contains(driver['availability_status'])) {
      throw const VehicleDutyException('active_ride_blocks_duty_change');
    }
    bool manualDuty = false;
    if (vehicleId.trim().isNotEmpty) {
      try {
        checkCurrent();
        final state = await duty.state();
        checkCurrent();
        manualDuty = true;
        final duties = state['duties'] as List;
        if (duties.length > 1) throw const VehicleDutyException('invalid_response');
        if (duties.isNotEmpty) {
          await duty.command({
            'action': 'end', 'duty_id': (duties.single as Map)['duty_id'],
            'expected_version': state['version'],
            'command_id': 'switch-end-${DateTime.now().microsecondsSinceEpoch}',
          });
          checkCurrent();
          final ended = await duty.state();
          checkCurrent();
          if ((ended['duties'] as List).isNotEmpty) {
            throw const VehicleDutyException('driver_offline_not_confirmed');
          }
        }
      } on VehicleDutyException catch (error) {
        // These two explicit policy responses select the already existing
        // availability endpoint. Auth/network/duty errors never fall through.
        if (!manualDuty && const ['vehicle_duty_not_configured', 'vehicle_operations_disabled']
            .contains(error.code)) {
          manualDuty = false;
        } else {
          rethrow;
        }
      }
    }
    if (!manualDuty) {
      final offline = await request('/public/driver/availability', body: {'availability_status': 'offline'});
      if (offline['availability_status'] != 'offline') {
        throw const VehicleDutyException('driver_offline_not_confirmed');
      }
    }
    final after = await request('/public/driver/status');
    if (after['driver'] is! Map || after['driver']['driver_id'] != driverId ||
        after['driver']['availability_status'] != 'offline') {
      throw const VehicleDutyException('driver_offline_not_confirmed');
    }
  } finally {
    if (client == null) transport.close();
  }
}
