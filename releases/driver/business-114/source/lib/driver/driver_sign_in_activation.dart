import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../driver_session_store.dart';
import 'vehicle_duty_client.dart';

/// One explicit successful driver sign-in. Never constructed for app resume,
/// remembered-session restore, a company preview, or merely unlocking a phone.
class DriverSignInActivation {
  DriverSignInActivation(this.session) {
    if (!session.isStandaloneLoginSession ||
        [
          session.tenantId,
          session.companyId,
          session.driverId,
          session.driverSessionToken,
        ].any((s) => s == null || s.trim().isEmpty)) {
      throw StateError('driver_sign_in_required');
    }
  }
  final ActiveDriverSession session;
  final Stopwatch _age = Stopwatch()..start();
  Future<String>? _inFlight;
  String? _confirmed;
  Map<String, dynamic>? _dutyCommand;

  Future<String> activate({
    required String baseUrl,
    required bool Function() isCurrent,
    http.Client? client,
  }) {
    if (!isCurrent()) return Future.error(StateError('driver_sign_in_changed'));
    if (_confirmed != null) return Future.value(_confirmed!);
    return _inFlight ??= _activate(
      baseUrl,
      isCurrent,
      client,
    ).whenComplete(() => _inFlight = null);
  }

  Future<String> _activate(
    String baseUrl,
    bool Function() isCurrent,
    http.Client? client,
  ) async {
    final transport = client ?? http.Client();
    void check() {
      if (!isCurrent() || _age.elapsed >= const Duration(minutes: 5))
        throw StateError('driver_sign_in_changed');
    }

    bool sameScope(Map value) =>
        value['tenant_id'] == session.tenantId &&
        value['company_id'] == session.companyId &&
        value['driver_id'] == session.driverId;
    final headers = {
      'Authorization': 'Bearer ${session.driverSessionToken}',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    Future<({int status, Map data})> request(String path, {Map? body}) async {
      check();
      final uri = Uri.parse(
        '${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/public/driver/$path',
      );
      final response =
          await (body == null
                  ? transport.get(uri, headers: headers)
                  : transport.post(
                      uri,
                      headers: headers,
                      body: jsonEncode(body),
                    ))
              .timeout(const Duration(seconds: 12));
      check();
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map) throw StateError('driver_activation_invalid_response');
      return (status: response.statusCode, data: data);
    }

    Future<String> status() async {
      // No driver_id query: only a genuine driver bearer can select this actor.
      final response = await request('status');
      final value = response.data;
      if (response.status != 200 ||
          value['ok'] != true ||
          !sameScope(value) ||
          value['driver'] is! Map ||
          value['driver']['driver_id'] != session.driverId ||
          value['driver']['is_active'] != true ||
          (value['driver']['assigned_vehicle_id'] ?? '') !=
              (session.assignedVehicleId ?? ''))
        throw StateError('driver_activation_not_authorized');
      final status = value['driver']['availability_status'];
      if (!const [
        'available',
        'offline',
        'paused',
        'busy',
        'on_trip',
      ].contains(status))
        throw StateError('driver_activation_status_unknown');
      return status as String;
    }

    Future<bool> ensureVehicleDuty({bool allowUnconfigured = false}) async {
      if ((session.assignedVehicleId ?? '').isEmpty)
        throw StateError('driver_activation_vehicle_required');
      final duty = VehicleDutyClient(
        baseUrl: baseUrl,
        token: session.driverSessionToken!,
        driverId: session.driverId,
        vehicleId: session.assignedVehicleId!,
        client: transport,
        isCurrent: () { check(); return true; },
      );
      Map<String, dynamic> state;
      try {
        state = await duty.state();
      } on VehicleDutyException catch (error) {
        // The existing server contract checks policy before vehicle-device
        // authorization. Only explicit non-duty configurations may retain the
        // legacy Available flow; auth/runtime failures must never look ready.
        if (allowUnconfigured && const [
          'vehicle_duty_not_configured', 'vehicle_operations_disabled',
        ].contains(error.code)) return false;
        rethrow;
      }
      check();
      final duties = state['duties'] as List;
      if (duties.isEmpty || duties.single['paused_at_ms'] != null) {
        final id = base64UrlEncode(
          List.generate(18, (_) => Random.secure().nextInt(256)),
        );
        _dutyCommand ??= {
          'action': duties.isEmpty ? 'start' : 'resume',
          'duty_id': duties.isEmpty ? 'signin-$id' : duties.single['duty_id'],
          'command_id': 'signin-$id',
          'expected_version': state['version'],
        };
        check();
        await duty.command(_dutyCommand!);
        check();
      }
      return true;
    }

    try {
      final before = await status();
      // An ongoing ride is never turned into a free chauffeur by sign-in.
      if (const ['busy', 'on_trip'].contains(before)) {
        _confirmed = before;
        return before;
      }
      if (before == 'available') {
        // A legacy Available flag is not evidence of a manual vehicle duty.
        // This path still belongs only to an explicit successful sign-in;
        // remembered-session restore and app resume do not call activation.
        final managed = (session.assignedVehicleId ?? '').isNotEmpty &&
            await ensureVehicleDuty(allowUnconfigured: true);
        final after = managed ? await status() : before;
        if (!const ['available', 'busy', 'on_trip'].contains(after))
          throw StateError('driver_activation_not_confirmed');
        _confirmed = after;
        return after;
      }
      final response = await request(
        'availability',
        body: {'availability_status': 'available'},
      );
      if (response.status == 409 &&
          response.data['error'] == 'availability_managed_by_duty') {
        await ensureVehicleDuty();
      } else if (response.status != 200 ||
          response.data['ok'] != true ||
          !sameScope(response.data) ||
          response.data['is_active'] != true ||
          response.data['availability_status'] != 'available') {
        throw StateError('driver_activation_not_confirmed');
      }
      final after = await status();
      if (!const ['available', 'busy', 'on_trip'].contains(after))
        throw StateError('driver_activation_not_confirmed');
      _confirmed = after;
      return after;
    } finally {
      if (client == null) transport.close();
    }
  }
}
