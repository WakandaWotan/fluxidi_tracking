import 'dart:convert';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Encrypted device binding survives personal chauffeur logout.
class VehicleDeviceStore {
  VehicleDeviceStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  static const _key = 'vehicle_device_binding_v1';
  static const _pendingKey = 'vehicle_device_transition_pending_v1';
  static Future<void> _transitionQueue = Future<void>.value();
  Future<bool> hasPendingTransition() async => await _storage.read(key: _pendingKey) != null;
  Future<String?> pendingTransitionOperation() async {
    final raw = await _storage.read(key:_pendingKey);
    return raw == null ? null : (jsonDecode(raw) as Map)['operation'] as String?;
  }

  /// Caller performs scoped personal-session cleanup only after server success.
  /// A pending encrypted command survives a lost response and blocks new login.
  Future<void> transition(String? rawQr, String baseUrl, {
    required String operation,
    required Future<void> Function(Map<String, dynamic> oldScope) afterServerConfirmed,
    http.Client? client,
  }) {
    final result = _transitionQueue.then((_) async {
      if (!['switch', 'unlink'].contains(operation)) throw StateError('device_transition_invalid');
      final rawPending = await _storage.read(key: _pendingKey);
      Map<String, dynamic> pending;
      if (rawPending != null) {
        pending = Map<String, dynamic>.from(jsonDecode(rawPending) as Map);
        if (pending['operation'] != operation) throw StateError('device_transition_pending');
      } else {
        final oldRaw = await _storage.read(key: _key);
        if (oldRaw == null || rawQr == null) throw StateError('device_binding_required');
        final old = Map<String, dynamic>.from(jsonDecode(oldRaw) as Map);
        final qr = jsonDecode(rawQr);
        if (qr is! Map || qr['kind'] != 'fluxidi_vehicle_device_transition' || qr['version'] != 1 ||
            qr['operation'] != operation || qr['tenant_id'] != old['tenant_id'] ||
            qr['company_id'] != old['company_id'] || qr['device_id'] != old['device_id'] ||
            qr['challenge_id'] is! String || qr['pairing_token'] is! String ||
            operation == 'switch' && qr['vehicle_id'] is! String) throw StateError('device_transition_qr_invalid');
        String randomHex(int count) { final r = Random.secure(); return List.generate(count, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join(); }
        pending = {
          'operation': operation, 'old': old,
          'request': {
            for (final key in ['tenant_id','company_id','device_id','challenge_id','pairing_token','vehicle_id']) key: qr[key],
            'operation': operation, 'device_token': old['device_token'],
            if (operation == 'switch') ...{'replacement_device_id': randomHex(16), 'replacement_token': randomHex(32)},
          },
        };
        await _storage.write(key: _pendingKey, value: jsonEncode(pending));
      }
      final old = Map<String, dynamic>.from(pending['old'] as Map);
      final request = Map<String, dynamic>.from(pending['request'] as Map);
      final transport = client ?? http.Client();
      try {
        final response = await transport.post(Uri.parse('$baseUrl/public/vehicle-device/transition'),
          headers: {'content-type':'application/json'}, body:jsonEncode(request)).timeout(const Duration(seconds:15));
        final body = jsonDecode(response.body);
        // These authoritative denials precede any registry writes. An unknown
        // response/timeout keeps the encrypted retry command and login fence.
        if (body is Map && body['ok'] == false && const {
          'active_duty_blocks_device_change', 'active_operation_blocks_device_change',
          'duty_projection_pending', 'gps_publication_blocks_device_change',
          'vehicle_device_transition_expired',
        }.contains(body['error'])) {
          await _storage.delete(key:_pendingKey);
        }
        if (response.statusCode != 200 || body is! Map || body['ok'] != true ||
            body['operation'] != operation || body['revoked_device_id'] != old['device_id'] ||
            body['tenant_id'] != old['tenant_id'] || body['company_id'] != old['company_id'] ||
            operation == 'switch' && (body['device_id'] != request['replacement_device_id'] ||
              body['vehicle_id'] != request['vehicle_id'] || body['expires_at_ms'] is! int)) {
          throw StateError('device_transition_unconfirmed');
        }
        final currentRaw = await _storage.read(key:_key);
        final current = currentRaw == null ? null : jsonDecode(currentRaw);
        if (current != null && (current['tenant_id'] != old['tenant_id'] || current['company_id'] != old['company_id'] ||
            current['device_id'] != old['device_id'] && current['device_id'] != request['replacement_device_id'])) throw StateError('device_transition_owner_changed');
        await afterServerConfirmed(old);
        if (operation == 'unlink') {
          await _storage.delete(key:_key);
        } else {
          await _storage.write(key:_key,value:jsonEncode({
            for (final key in ['tenant_id','company_id','device_id','vehicle_id','expires_at_ms']) key:body[key],
            'device_token':request['replacement_token'],
          }));
        }
        await _storage.delete(key:_pendingKey);
      } finally { if (client == null) transport.close(); }
    });
    _transitionQueue = result.catchError((Object _) {});
    return result;
  }
  Future<Map<String, dynamic>?> pinScope() async {
    // Expired or removed bindings cannot unlock remembered driver credentials.
    if (await loginIdentity() == null) return null;
    final stored = jsonDecode((await _storage.read(key: _key))!);
    return {for (final key in ['tenant_id', 'company_id', 'vehicle_id', 'device_id']) key: stored[key]};
  }
  Future<Map<String, dynamic>?> driverChoices(
    String baseUrl, {
    http.Client? client,
  }) async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    final stored = jsonDecode(raw) as Map<String, dynamic>;
    final identity = await loginIdentity();
    final transport = client ?? http.Client();
    try {
      final response = await transport
          .post(
            Uri.parse('$baseUrl/public/vehicle-device/drivers'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              'tenant_id': stored['tenant_id'],
              'company_id': stored['company_id'],
              ...identity!,
            }),
          )
          .timeout(const Duration(seconds: 15));
      final dynamic result = jsonDecode(response.body);
      if (response.statusCode != 200 ||
          result is! Map ||
          result['ok'] != true ||
          result['tenant_id'] != stored['tenant_id'] ||
          result['company_id'] != stored['company_id'] ||
          result['vehicle_id'] != stored['vehicle_id'] ||
          result['drivers'] is! List ||
          (result['drivers'] as List).any(
            (row) =>
                row is! Map ||
                row['driver_id'] is! String ||
                row['name'] is! String,
          )) {
        throw StateError('vehicle_driver_choices_unavailable');
      }
      return {
        'tenant_id': result['tenant_id'],
        'company_id': result['company_id'],
        'vehicle_id': result['vehicle_id'],
        'drivers': result['drivers'],
        if (result['vehicle_label'] is String) 'vehicle_label': result['vehicle_label'],
        if (result['company_code'] is String)
          'company_code': result['company_code'],
        if (result['company_presentation'] is Map)
          'company_presentation': {
            for (final key in ['company_name','public_logo_url','customer_app_header_media_revision'])
              if (result['company_presentation'][key] is String) key: result['company_presentation'][key],
          },
      };
    } finally {
      if (client == null) transport.close();
    }
  }

  Future<Map<String, dynamic>?> loginIdentity() async {
    if (await hasPendingTransition()) throw StateError('device_transition_pending');
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    final stored = jsonDecode(raw) as Map<String, dynamic>;
    if (stored['expires_at_ms'] is! int ||
        stored['expires_at_ms'] <= DateTime.now().millisecondsSinceEpoch)
      throw StateError('vehicle_device_expired');
    return {
      'device_id': stored['device_id'],
      'device_token': stored['device_token'],
    };
  }

  Future<void> pair(
    String rawQr,
    String backendBaseUrl, {
    http.Client? client,
    String? expectedTenantId,
    String? expectedCompanyId,
    String? expectedVehicleId,
  }) async {
    if (await hasPendingTransition() || await _storage.read(key:_key) != null) throw StateError('device_transition_required');
    final dynamic qr = jsonDecode(rawQr);
    if (qr is! Map ||
        qr['kind'] != 'fluxidi_vehicle_device' ||
        qr['version'] != 1 ||
        [
          'tenant_id',
          'company_id',
          'challenge_id',
          'pairing_token',
        ].any((key) => qr[key] is! String))
      throw const FormatException('vehicle_device_qr_invalid');
    if ((expectedTenantId != null && qr['tenant_id'] != expectedTenantId) ||
        (expectedCompanyId != null && qr['company_id'] != expectedCompanyId)) {
      throw StateError('vehicle_device_company_mismatch');
    }
    final transport = client ?? http.Client();
    try {
      final response = await transport
          .post(
            Uri.parse('$backendBaseUrl/public/vehicle-device/redeem'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              for (final key in [
                'tenant_id',
                'company_id',
                'challenge_id',
                'pairing_token',
              ])
                key: qr[key],
            }),
          )
          .timeout(const Duration(seconds: 15));
      final dynamic result = jsonDecode(response.body);
      if (response.statusCode != 200 ||
          result is! Map ||
          result['ok'] != true ||
          result['tenant_id'] != qr['tenant_id'] ||
          result['company_id'] != qr['company_id'] ||
          result['device_id'] is! String ||
          result['vehicle_id'] is! String ||
          result['device_token'] is! String ||
          result['expires_at_ms'] is! int)
        throw StateError('vehicle_device_pairing_failed');
      if (expectedVehicleId != null && result['vehicle_id'] != expectedVehicleId) {
        throw StateError('vehicle_device_vehicle_mismatch');
      }
      await _storage.write(
        key: _key,
        value: jsonEncode({
          for (final key in [
            'tenant_id',
            'company_id',
            'device_id',
            'vehicle_id',
            'device_token',
            'expires_at_ms',
          ])
            key: result[key],
        }),
      );
    } finally {
      if (client == null) transport.close();
    }
  }
}
