import 'dart:convert';
import 'package:http/http.dart' as http;

typedef DriverTrackingPost =
    Future<http.Response> Function(Uri uri, Map<String, dynamic> payload);

class TrackingLifecycleFailure extends StateError {
  TrackingLifecycleFailure(this.stage, this.statusCode, this.code)
    : super('Tracking lifecycle request rejected');

  final String stage;
  final int statusCode;
  final String code;

  @override
  String toString() =>
      'TrackingLifecycleFailure(stage=$stage, status=$statusCode, code=$code)';
}

String _trackingFailureCode(Object? raw) {
  final code = (raw ?? '').toString().trim().toLowerCase();
  return RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(code) ? code : 'unknown';
}

/// Shared by presence and trip pings. No timer/queue: the existing latest-wins
/// dispatcher supplies the newest sample. Keep this gate across START/context changes.
class DriverGpsUploadCadence {
  DriverGpsUploadCadence({DateTime Function()? now})
    : _now = now ?? DateTime.now;
  static const interval = Duration(seconds: 8);
  final DateTime Function() _now;
  DateTime? _nextAt;
  bool _busy = false;
  int _failures = 0;

  static bool validSample(double latitude, double longitude, double accuracy) =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude.abs() <= 90 &&
      longitude.abs() <= 180 &&
      accuracy.isFinite &&
      accuracy >= 0 &&
      accuracy <= 150;

  Future<http.Response?> send({
    required DateTime capturedAt,
    required Future<http.Response> Function() request,
  }) async {
    final now = _now();
    if (_busy ||
        (_nextAt != null && now.isBefore(_nextAt!)) ||
        now.difference(capturedAt) > const Duration(seconds: 30) ||
        capturedAt.difference(now) > const Duration(seconds: 5))
      return null;
    _busy = true;
    var delay = interval;
    try {
      final response = await request();
      if (response.statusCode == 429) {
        num? seconds = num.tryParse(response.headers['retry-after'] ?? '');
        try {
          final body = jsonDecode(response.body);
          final raw = body is Map ? body['retry_after_seconds'] : null;
          final value = raw is num ? raw : num.tryParse('$raw');
          if (value != null && value.isFinite && value > (seconds ?? 0))
            seconds = value;
        } catch (_) {
          /* Fall back to a full Room window. */
        }
        delay = Duration(
          seconds: seconds != null && seconds.isFinite && seconds > 0
              ? seconds.ceil().clamp(8, 86400)
              : 60,
        );
      } else if (response.statusCode >= 500 || response.statusCode == 408) {
        delay = _failureDelay();
      } else {
        _failures = 0;
      }
      return response;
    } catch (_) {
      delay = _failureDelay();
      rethrow;
    } finally {
      // Completion-based spacing also prevents bursts after a slow request.
      _nextAt = _now().add(delay);
      _busy = false;
    }
  }

  Duration _failureDelay() {
    _failures = (_failures + 1).clamp(1, 3);
    return Duration(seconds: 8 * (1 << (_failures - 1)));
  }
}

/// Connects planned Driver actions to the existing booking lifecycle and GPS session.
/// The caller activates the cockpit only after this future has succeeded.
class PlannedTrackingLifecycle {
  PlannedTrackingLifecycle({
    required this.bookingBaseUrl,
    required this.trackingBaseUrl,
    required this.post,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;
  final String bookingBaseUrl;
  final String trackingBaseUrl;
  final DriverTrackingPost post;
  final DateTime Function() _now;
  Map<String, dynamic>? _presence;
  final Map<String, String> _trackingLegBindings = {};
  String _bindingKey(Map<String, dynamic> p) => jsonEncode([
    p['tenant_id'],
    p['company_id'],
    p['booking_id'],
    p['driver_id'],
    p['operational_leg'],
  ]);
  Future<void>? _presenceRequest;
  late final gpsUploads = DriverGpsUploadCadence(now: _now);
  int _contextGeneration = 0;
  bool get preStartActive => _presence != null;

  bool presenceMatches({required String bookingId, required String legId}) =>
      _presence?['booking_id'] == bookingId &&
      (_presence?['requested_operational_leg'] ??
              _presence?['operational_leg']) ==
          (legId.isEmpty ? 'primary' : legId);

  /// Invalidate synchronously, then drain the one in-flight upload before START.
  /// An old NAV response cannot re-arm a context that has been left or started.
  Future<void> stopPresence() async {
    _contextGeneration++;
    _presence = null;
    await _presenceRequest;
  }

  /// Fed by the existing Geolocator stream/dispatcher; owns no GPS subscription
  /// or timer. Paused delivery resumes on the next fresh device sample.
  Future<void> uploadPreStart({
    required double latitude,
    required double longitude,
    required double speedMps,
    required double heading,
    required double accuracy,
    required DateTime capturedAt,
  }) async {
    final context = _presence;
    if (context == null || _presenceRequest != null) return;
    if (!DriverGpsUploadCadence.validSample(latitude, longitude, accuracy))
      return;
    final generation = _contextGeneration;
    final request = _uploadPresence(context, generation, {
      'lat': latitude,
      'lon': longitude,
      'speed': speedMps.isFinite ? speedMps : 0,
      'heading': heading.isFinite ? heading : 0,
      'accuracy_m': accuracy,
      'captured_at': capturedAt.toUtc().toIso8601String(),
    });
    _presenceRequest = request;
    try {
      await request;
    } finally {
      _presenceRequest = null;
    }
  }

  Future<void> _uploadPresence(
    Map<String, dynamic> context,
    int generation,
    Map<String, dynamic> sample,
  ) async {
    try {
      final response = await gpsUploads.send(
        capturedAt: DateTime.parse(sample['captured_at'] as String),
        request: () => post(
          Uri.parse('$trackingBaseUrl/track/driver/location'),
          {...context, ...sample, 'pre_start': true},
        ),
      );
      if (response == null) return;
      if (generation != _contextGeneration) return;
      if (response.statusCode >= 400 &&
          response.statusCode < 500 &&
          response.statusCode != 408 &&
          response.statusCode != 429) {
        _presence = null;
        return;
      }
      if (response.statusCode != 200)
        throw StateError('Presence temporarily unavailable');
      final body = jsonDecode(response.body) as Map;
      if (body['ok'] != true) throw StateError('Presence not confirmed');
      if (const [
        'driver_not_found',
        'driver_inactive',
        'driver_off_duty',
        'driver_paused',
      ].contains(body['reason'])) {
        _presence = null;
        return;
      }
    } catch (_) {
      // The shared upload gate applies bounded retry spacing. Wait for a fresh sample.
    }
  }

  final Map<String, Future<Map<String, dynamic>>> _starting = {};

  Map<String, dynamic> _payload(
    Map<String, dynamic> payload,
    String legId,
    bool isOperationalLeg,
  ) {
    if (isOperationalLeg && legId.trim().isEmpty)
      throw StateError('Missing operational leg');
    return {
      ...payload,
      'operational_leg': legId.trim().isEmpty ? 'primary' : legId.trim(),
    };
  }

  Future<Map<String, dynamic>> _send(
    String base,
    String path,
    Map<String, dynamic> payload,
  ) async {
    final response = await post(Uri.parse('$base$path'), payload);
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw TrackingLifecycleFailure(
        path,
        response.statusCode,
        'invalid_response',
      );
    }
    if (response.statusCode != 200 ||
        decoded is! Map ||
        decoded['ok'] != true) {
      throw TrackingLifecycleFailure(
        path,
        response.statusCode,
        _trackingFailureCode(
          decoded is Map ? (decoded['error'] ?? decoded['reason']) : null,
        ),
      );
    }
    final body = Map<String, dynamic>.from(decoded);
    if (body['tracking_sync'] is! Map ||
        body['tracking_sync']['confirmed'] != true) {
      throw TrackingLifecycleFailure(
        path,
        response.statusCode,
        'tracking_not_confirmed',
      );
    }
    return body;
  }

  Future<void> enRoute(
    Map<String, dynamic> payload, {
    required String legId,
    required bool isOperationalLeg,
  }) async {
    if (_starting.isNotEmpty) throw StateError('Trip start pending');
    final generation = _contextGeneration;
    final scoped = _payload(payload, legId, isOperationalLeg);
    final response = await _send(bookingBaseUrl, '/tracking/en-route', scoped);
    if (generation != _contextGeneration) return;
    final sync = response['tracking_sync'];
    final version = sync['assignment_version'];
    if (sync['tracking_phase'] != 'en_route_pickup' ||
        version is! int ||
        version <= 0)
      return;
    final next = {
      ...scoped,
      'requested_operational_leg': scoped['operational_leg'],
      'operational_leg': _confirmedTrackingLeg(response, scoped),
      'assignment_version': version,
    };
    const identity = [
      'tenant_id',
      'company_id',
      'booking_id',
      'operational_leg',
      'driver_id',
      'assignment_version',
    ];
    if (_presence != null &&
        identity.every((field) => _presence![field] == next[field]))
      return;
    _contextGeneration++;
    _presence = next;
  }

  Future<void> confirmPickupArrival() async {
    final context = _presence;
    if (context == null || _starting.isNotEmpty) {
      throw StateError('No active pickup approach');
    }
    final generation = _contextGeneration;
    final response = await _send(bookingBaseUrl, '/tracking/arrived', {...context});
    if (generation != _contextGeneration ||
        response['tracking_sync']['tracking_phase'] != 'arrived_pickup') {
      throw StateError('Arrival context changed');
    }
    // Keep the presence service and GPS cadence; START alone creates the trip.
  }

  Future<Map<String, dynamic>> start(
    Map<String, dynamic> payload, {
    required String legId,
    required bool isOperationalLeg,
  }) {
    final scoped = _payload(payload, legId, isOperationalLeg);
    final key = jsonEncode([
      scoped['tenant_id'],
      scoped['company_id'],
      scoped['booking_id'],
      scoped['operational_leg'],
      scoped['driver_id'],
    ]);
    return _starting.putIfAbsent(
      key,
      () => _start(scoped).whenComplete(() {
        _starting.remove(key);
      }),
    );
  }

  Future<Map<String, dynamic>> _start(Map<String, dynamic> payload) async {
    // A list row uses its canonical OUTBOUND/RETURN ID. Tracking uses primary
    // for a single-leg booking. Resolve that alias only from Booking's confirmed
    // ownership response; never retry a rejected Tracking start against primary.
    var trackingPayload = payload;
    if (payload['operational_leg'] != 'primary') {
      final existing = _presence;
      const scope = ['tenant_id', 'company_id', 'booking_id', 'driver_id'];
      final confirmedLeg = _trackingLegBindings[_bindingKey(payload)];
      if (confirmedLeg != null) {
        trackingPayload = {...payload, 'operational_leg': confirmedLeg};
      } else if (existing != null &&
          scope.every((key) => existing[key] == payload[key]) &&
          existing['requested_operational_leg'] == payload['operational_leg']) {
        trackingPayload = {
          ...payload,
          'operational_leg': existing['operational_leg'],
        };
      } else {
        final binding = await _send(
          bookingBaseUrl,
          '/tracking/en-route',
          payload,
        );
        trackingPayload = {
          ...payload,
          'operational_leg': _confirmedTrackingLeg(binding, payload),
        };
      }
    }
    await stopPresence();
    final session = await _send(trackingBaseUrl, '/track/session/start', {
      ...trackingPayload,
      'reuse_bound_session': true,
    });
    final id = '${session['session_id'] ?? ''}';
    final version = session['tracking_sync']['assignment_version'];
    if (id.isEmpty || version is! num || version <= 0)
      throw StateError('Missing tracking binding');
    await _send(bookingBaseUrl, '/tracking/start', {
      ...trackingPayload,
      'session_id': id,
      'assignment_version': version,
    });
    return session;
  }

  String _confirmedTrackingLeg(
    Map<String, dynamic> response,
    Map<String, dynamic> requested,
  ) {
    final sync = response['tracking_sync'];
    final assignment = sync is Map ? sync['public_assignment'] : null;
    if (assignment is! Map) return requested['operational_leg'] as String;
    const scope = ['tenant_id', 'company_id', 'booking_id'];
    final leg = assignment['operational_leg'];
    if (!scope.every((key) => assignment[key] == requested[key]) ||
        (leg != 'primary' && leg != requested['operational_leg'])) {
      throw TrackingLifecycleFailure(
        '/tracking/en-route',
        200,
        'tracking_binding_mismatch',
      );
    }
    if (_trackingLegBindings.length >= 16) {
      _trackingLegBindings.remove(_trackingLegBindings.keys.first);
    }
    _trackingLegBindings[_bindingKey(requested)] = leg as String;
    return leg;
  }
}
