import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// One link-load attempt, local logs only. No credentials or response body logs.
/// The HTTP zone covers only the personal QR loader, not other login/ride work.
class DriverBookingLinkTrace {
  DriverBookingLinkTrace({void Function(String)? log,
    this.tenantId, this.companyId, this.vehicleId, this.driverId})
    : _log = log ?? debugPrint,
      _attempt = '${DateTime.now().microsecondsSinceEpoch}-${_next++}';

  static int _next = 0;
  final void Function(String) _log;
  final String _attempt;
  final String? tenantId, companyId, vehicleId, driverId;
  String _stage = 'local_session';
  static const _facts = {
    'driver_present', 'standalone', 'operator_minted', 'token_present',
    'expiry_valid', 'tenant_present', 'company_present', 'vehicle_present',
    'company_code_present', 'company_code_valid', 'context_current',
    'binding_present', 'binding_unchanged', 'tenant_equal', 'company_equal',
    'vehicle_equal', 'driver_in_directory', 'directory_present',
    'public_active', 'public_bookable', 'public_profile_enabled',
    'response_ok', 'driver_active', 'driver_equal', 'directory_schema_valid',
  };
  static const _codes = {
    'verification_failed', 'unauthorized', 'forbidden', 'method_not_allowed',
    'driver_not_found', 'vehicle_not_active_in_company',
    'vehicle_device_not_configured', 'vehicle_operations_disabled',
    'pin_server_session_invalid', 'pin_server_session_rejected',
    'vehicle_driver_choices_unavailable', 'vehicle_device_expired',
    'device_transition_pending',
  };

  void _emit(String event, Map<String, Object?> values) {
    try {
      _log('[PUBLIC_BOOKING_LINK] ${jsonEncode({
        'attempt': _attempt, 'at_utc': DateTime.now().toUtc().toIso8601String(),
        'stage': _stage, 'event': event, ...values,
      })}');
    } catch (_) {
      // An unavailable log sink must never change authorization or UI results.
    }
  }

  void facts(Map<String, bool> values) => _emit('checks', {
    for (final entry in values.entries)
      if (_facts.contains(entry.key)) entry.key: entry.value,
  });

  Future<T> step<T>(String stage, Future<T> Function() body) async {
    _stage = stage;
    _emit('begin', {});
    final result = await body();
    _emit('pass', {});
    return result;
  }

  Future<T> run<T>(Future<T> Function() body, {http.Client? transport}) async {
    // Create the real client outside the zone to avoid recursive factories.
    final delegate = transport ?? http.Client();
    final client = _TraceClient(delegate, this);
    try {
      return await http.runWithClient(() async {
        _emit('begin', {});
        final result = await body();
        _stage = 'complete';
        _emit('pass', {});
        return result;
      }, () => client);
    } catch (error) {
      final code = error is StateError && _codes.contains(error.message)
          ? error.message : null;
      _emit('fail', {
        if (code != null) 'code': code,
        'failure': error is TimeoutException ? 'timeout'
            : error is FormatException ? 'invalid_response'
            : error is http.ClientException ? 'transport'
            : 'guard_or_loader',
      });
      rethrow;
    } finally {
      delegate.close();
    }
  }

  void _response(String stage, http.StreamedResponse response, List<int>? bytes,
      bool truncated) {
    final values = <String, Object?>{'http_status': response.statusCode};
    for (final entry in {
      'request_id': response.headers['x-request-id'] ?? response.headers['x-fluxidi-request-id'],
      'cf_ray': response.headers['cf-ray'],
    }.entries) {
      final value = entry.value;
      final valid = value != null && (entry.key == 'cf_ray'
          ? RegExp(r'^[a-fA-F0-9]{16}-[A-Z]{3}$').hasMatch(value)
          : RegExp(r'^(?:[a-fA-F0-9]{32}|[a-fA-F0-9]{8}(?:-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12})$').hasMatch(value));
      if (valid) values[entry.key] = value;
    }
    if (bytes != null) {
      values['body_truncated'] = truncated;
      if (!truncated) {
        try {
          final body = jsonDecode(utf8.decode(bytes));
          if (body is Map) {
            if (response.statusCode == 200 &&
                (stage == 'driver_status' || stage == 'device_directory')) {
              final driver = body['driver'];
              final drivers = body['drivers'];
              values.addAll({
                'response_ok': body['ok'] == true,
                'tenant_equal': tenantId != null && body['tenant_id'] == tenantId,
                'company_equal': companyId != null && body['company_id'] == companyId,
                'vehicle_equal': vehicleId != null && (stage == 'driver_status'
                    ? driver is Map && driver['assigned_vehicle_id'] == vehicleId
                    : body['vehicle_id'] == vehicleId),
                if (stage == 'driver_status') ...{
                  'driver_equal': driverId != null && body['driver_id'] == driverId &&
                      driver is Map && driver['driver_id'] == driverId,
                  'driver_active': driver is Map && driver['is_active'] == true,
                },
                if (stage == 'device_directory') ...{
                  'directory_schema_valid': drivers is List && drivers.every(
                    (row) => row is Map && row['driver_id'] is String && row['name'] is String),
                  'driver_in_directory': driverId != null && drivers is List && drivers.any(
                    (row) => row is Map && row['driver_id'] == driverId),
                  'company_code_present': body['company_code'] is String && body['company_code'].isNotEmpty,
                  'company_code_valid': body['company_code'] is String &&
                      RegExp(r'^FLX-[0-9]{5,12}$').hasMatch(body['company_code']),
                },
              });
            }
            for (final field in ['error', 'code', 'reason']) {
              final value = body[field];
              if (_codes.contains(value)) values[field] = value;
              else if (value != null) values['${field}_redacted'] = true;
            }
          }
        } catch (_) {
          values['body_unavailable'] = true;
        }
      }
    }
    // Use the send-time stage even if an async callback has since moved on.
    final previous = _stage;
    _stage = stage;
    _emit('http', values);
    _stage = previous;
  }
}

class _TraceClient extends http.BaseClient {
  _TraceClient(this.delegate, this.trace);
  final http.Client delegate;
  final DriverBookingLinkTrace trace;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final stage = trace._stage;
    final response = await delegate.send(request);
    if (response.statusCode < 400 && stage != 'driver_status' && stage != 'device_directory') {
      trace._response(stage, response, null, false);
      return response;
    }
    // Tee bounded status/directory evidence without consuming or replacing it.
    final bytes = <int>[];
    var truncated = false;
    final stream = response.stream.transform(StreamTransformer<List<int>, List<int>>.fromHandlers(
      handleData: (chunk, sink) {
        final remaining = 8192 - bytes.length;
        bytes.addAll(chunk.take(remaining));
        if (chunk.length > remaining) truncated = true;
        sink.add(chunk);
      },
      handleDone: (sink) {
        trace._response(stage, response, bytes, truncated);
        sink.close();
      },
    ));
    return http.StreamedResponse(stream, response.statusCode,
      contentLength: response.contentLength, request: response.request,
      headers: response.headers, isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection, reasonPhrase: response.reasonPhrase);
  }

  @override
  void close() {} // Existing per-request clients close; the attempt owns delegate.
}
