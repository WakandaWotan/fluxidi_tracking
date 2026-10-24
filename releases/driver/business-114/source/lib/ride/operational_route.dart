import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'operational_route_pending_io.dart'
    if (dart.library.html) 'operational_route_pending_web.dart';

class OperationalRouteException implements Exception {
  const OperationalRouteException(this.code, {this.uncertain = false});
  final String code;
  final bool uncertain;
}

Map<String, dynamic> operationalMap(Object? raw) =>
    raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};

bool _splitRecord(Map<String, dynamic> record) =>
    (record['roundtrip_dispatch_mode'] ??
        operationalMap(record['booking'])['roundtrip_dispatch_mode']) ==
    'split_no_wait';

bool operationalRideRunning(Map<String, dynamic> source) {
  final phase = '${source['customer_tracking_phase'] ?? ''}'.toLowerCase();
  final status = '${source['status'] ?? source['lifecycle_status'] ?? ''}'
      .toUpperCase();
  if (const {'completed', 'cancelled', 'canceled', 'ended'}.contains(phase) ||
      const {
        'STOP',
        'STOPPED',
        'COMPLETED',
        'DONE',
        'FINISHED',
        'CANCELLED',
        'CANCELED',
        'NO_SHOW',
        'REJECTED',
      }.contains(status))
    return false;
  return phase == 'in_progress' || status == 'IN_PROGRESS';
}

class OperationalStop {
  const OperationalStop({
    required this.address,
    required this.latitude,
    required this.longitude,
    this.waitSeconds = 0,
    this.notBefore,
  });
  final String address;
  final double latitude, longitude;
  final int waitSeconds;
  final DateTime? notBefore;
  static OperationalStop? fromMap(Object? raw) {
    final value = operationalMap(raw);
    final address = value['address'],
        lat = value['lat'],
        lng = value['lng'],
        wait = value['wait_seconds'] ?? 0;
    final date = value['not_before_iso'];
    final notBefore = date is String ? DateTime.tryParse(date) : null;
    if (address is! String ||
        address.trim().isEmpty ||
        address.length > 400 ||
        lat is! num ||
        lng is! num ||
        !lat.isFinite ||
        !lng.isFinite ||
        lat.abs() > 90 ||
        lng.abs() > 180 ||
        wait is! int ||
        wait < 0 ||
        wait > 43200 ||
        date != null && notBefore == null)
      return null;
    return OperationalStop(
      address: address.trim(),
      latitude: lat.toDouble(),
      longitude: lng.toDouble(),
      waitSeconds: wait,
      notBefore: notBefore?.toUtc(),
    );
  }

  Map<String, dynamic> toMap() => {
    'address': address,
    'lat': latitude,
    'lng': longitude,
    'wait_seconds': waitSeconds,
    if (notBefore != null)
      'not_before_iso': notBefore!.toUtc().toIso8601String(),
  };
}

class OperationalRoute {
  const OperationalRoute({
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.expectedEnd,
    this.remainingStops = const [],
    this.remainingRouteComplete = false,
  });
  final String address;
  final double latitude, longitude;
  final DateTime expectedEnd;
  final List<OperationalStop> remainingStops;
  final bool remainingRouteComplete;
  OperationalStop get nextDestination => remainingStops.isNotEmpty
      ? remainingStops.first
      : OperationalStop(
          address: address,
          latitude: latitude,
          longitude: longitude,
        );
  static OperationalRoute? fromMap(Object? raw) {
    final value = operationalMap(raw),
        point = operationalMap(value['destination']);
    final address = point['address'], lat = point['lat'], lng = point['lng'];
    final end = DateTime.tryParse('${value['expected_end_iso'] ?? ''}');
    if (address is! String ||
        address.trim().isEmpty ||
        address.length > 400 ||
        lat is! num ||
        lng is! num ||
        !lat.isFinite ||
        !lng.isFinite ||
        lat.abs() > 90 ||
        lng.abs() > 180 ||
        end == null)
      return null;
    final rawStops = value['remaining_stops'];
    final declared = value['remaining_route_complete'];
    if ((rawStops != null || declared != null) &&
        (declared != true || rawStops is! List || rawStops.length > 8))
      return null;
    final stops = <OperationalStop>[];
    for (final raw in rawStops is List ? rawStops : const []) {
      final stop = OperationalStop.fromMap(raw);
      if (stop == null ||
          stop.notBefore != null && stop.notBefore!.isAfter(end))
        return null;
      stops.add(stop);
    }
    if (stops.fold<int>(0, (sum, stop) => sum + stop.waitSeconds) > 86400)
      return null;
    return OperationalRoute(
      address: address.trim(),
      latitude: lat.toDouble(),
      longitude: lng.toDouble(),
      expectedEnd: end.toUtc(),
      remainingStops: List.unmodifiable(stops),
      remainingRouteComplete: declared == true,
    );
  }

  Map<String, dynamic> toMap() => {
    'destination': {'address': address, 'lat': latitude, 'lng': longitude},
    'expected_end_iso': expectedEnd.toUtc().toIso8601String(),
    if (remainingRouteComplete) ...{
      'remaining_route_complete': true,
      'remaining_stops': remainingStops.map((stop) => stop.toMap()).toList(),
    },
  };
}

// A root quote never supplies an operational destination for a different leg.
Map<String, dynamic> operationalTarget(
  Map<String, dynamic> record,
  String leg,
) {
  final split = _splitRecord(record);
  final legs = record['operational_legs'] is List
      ? record['operational_legs'] as List
      : const [];
  if (!split && legs.length <= 1) return record;
  if (leg.isEmpty && !split) {
    final active = legs
        .map(operationalMap)
        .where(operationalRideRunning)
        .toList();
    if (active.length == 1) return active.single;
  }
  if (leg.isEmpty)
    throw const OperationalRouteException('operational_leg_required');
  for (final row
      in (record['operational_legs'] is List
          ? record['operational_legs'] as List
          : const [])) {
    final target = operationalMap(row);
    if (target['leg_id'] == leg || target['leg_type'] == leg) return target;
  }
  throw const OperationalRouteException('operational_leg_invalid');
}

OperationalRoute? runningOperationalRoute(Map<String, dynamic> source) {
  if (!operationalRideRunning(source)) return null;
  return OperationalRoute.fromMap(source['operational_route']);
}

// Tracking's legacy session keeps the original quoted dropoff. It may arrive
// after a route update; it cannot replace a confirmed running destination.
String? operationalHydratedDestination(
  Map<String, dynamic> details,
  String? trackingDropoff,
  String? currentDestination,
) =>
    runningOperationalRoute(details)?.nextDestination.address ??
    trackingDropoff ??
    currentDestination;

class OperationalRideState {
  const OperationalRideState(
    this.revision,
    this.target,
    this.mutationLeg, {
    this.requiresItinerary = false,
  });
  final int revision;
  final Map<String, dynamic> target;
  final String mutationLeg;
  final bool requiresItinerary;
  OperationalRoute? get route => runningOperationalRoute(target);
  static OperationalRideState fromResponse(
    Map<String, dynamic> body,
    String leg,
  ) {
    final record = body['record'] is Map
        ? operationalMap(body['record'])
        : body;
    final revision = record['revision'];
    if (revision is! int || revision < 1)
      throw const OperationalRouteException('revision_required');
    if (const {
      'COMPLETED',
      'CANCELLED',
      'NO_SHOW',
      'STOPPED',
    }.contains('${record['status']}'.toUpperCase()))
      throw const OperationalRouteException('operational_ride_not_running');
    final target = operationalTarget(record, leg);
    if (!operationalRideRunning(target)) {
      throw const OperationalRouteException('operational_ride_not_running');
    }
    // A synthesized single leg in the driver list is still a root mutation.
    return OperationalRideState(
      revision,
      target,
      !identical(target, record)
          ? '${target['leg_id'] ?? target['leg_type']}'
          : '',
      requiresItinerary:
          (!_splitRecord(record) &&
              (record['return_enabled'] == true ||
                  operationalMap(record['booking'])['return_enabled'] == true ||
                  record['operational_legs'] is List &&
                      (record['operational_legs'] as List).length > 1)) ||
          (num.tryParse(
                    '${record['stop_count'] ?? operationalMap(record['booking'])['stop_count'] ?? 0}',
                  ) ??
                  0) >
              0 ||
          operationalMap(record['booking'])['stops'] is List &&
              (operationalMap(record['booking'])['stops'] as List).isNotEmpty,
    );
  }
}

class OperationalRouteApi {
  OperationalRouteApi({
    required this.baseUrl,
    required this.bookingId,
    required this.tenantId,
    required this.companyId,
    required this.actorId,
    required this.headers,
    required this.isCurrent,
    this.leg = '',
    http.Client? client,
    OperationalPendingStore? store,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _store = store ?? OperationalPendingStore();
  final String baseUrl, bookingId, tenantId, companyId, actorId, leg;
  final Map<String, String> Function() headers;
  final bool Function() isCurrent;
  final http.Client _client;
  final bool _ownsClient;
  final OperationalPendingStore _store;
  OperationalRideState? _loaded;
  static final Set<String> _savingKeys = {};
  String get pendingKey => sha256
      .convert(
        utf8.encode(
          jsonEncode([baseUrl, tenantId, companyId, actorId, bookingId, leg]),
        ),
      )
      .toString();
  Map<String, String> _headers() {
    final value = headers();
    final authorization =
        value['Authorization'] ?? value['authorization'] ?? '';
    if (!isCurrent() ||
        tenantId.isEmpty ||
        companyId.isEmpty ||
        actorId.isEmpty ||
        !authorization.startsWith('Bearer ') ||
        authorization.substring(7).trim().isEmpty) {
      throw const OperationalRouteException('forbidden');
    }
    return {...value, 'content-type': 'application/json'};
  }

  Uri _uri(String suffix) {
    final url = Uri.parse(baseUrl);
    if (url.scheme != 'https' ||
        url.userInfo.isNotEmpty ||
        url.host.isEmpty ||
        bookingId.isEmpty)
      throw const OperationalRouteException('forbidden');
    return Uri.parse(
      '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/bookings/${Uri.encodeComponent(bookingId)}$suffix',
    ).replace(
      queryParameters: {'tenant_id': tenantId, 'company_id': companyId},
    );
  }

  Future<OperationalRideState> load() async {
    final response = await _client
        .get(_uri(''), headers: _headers())
        .timeout(const Duration(seconds: 15));
    final decoded = _decode(response);
    if (!isCurrent()) throw const OperationalRouteException('forbidden');
    final state = OperationalRideState.fromResponse(decoded, leg);
    _loaded = state;
    return state;
  }

  Map<String, dynamic> prepare(
    OperationalRoute route,
    OperationalRideState state,
  ) {
    final random = Random.secure();
    final id = List.generate(
      24,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return {
      'tenant_id': tenantId,
      'company_id': companyId,
      'revision': state.revision,
      'update_id': id,
      ...route.toMap(),
      if (state.mutationLeg.isNotEmpty) 'operational_leg': state.mutationLeg,
    };
  }

  Future<Map<String, dynamic>?> pending() async {
    final value = await _store.read(pendingKey);
    if (value == null) return null;
    if (value['tenant_id'] != tenantId ||
        value['company_id'] != companyId ||
        ('${value['operational_leg'] ?? ''}'.isNotEmpty &&
            value['operational_leg'] != leg &&
            value['operational_leg'] != '$bookingId:${leg.toUpperCase()}' &&
            value['operational_leg'] != _loaded?.mutationLeg) ||
        OperationalRoute.fromMap(value) == null ||
        value['revision'] is! int ||
        (value['revision'] as int) < 1 ||
        value['update_id'] is! String ||
        !RegExp(
          r'^[A-Za-z0-9_-]{1,100}$',
        ).hasMatch(value['update_id'] as String)) {
      throw const OperationalRouteException('pending_invalid');
    }
    return value;
  }

  Future<OperationalRoute> save(Map<String, dynamic> body) async {
    _headers();
    final requested = OperationalRoute.fromMap(body);
    if (_loaded == null ||
        requested == null ||
        body['tenant_id'] != tenantId ||
        body['company_id'] != companyId ||
        '${body['operational_leg'] ?? ''}' != _loaded!.mutationLeg ||
        body['revision'] is! int ||
        (body['revision'] as int) < 1 ||
        body['update_id'] is! String ||
        !RegExp(
          r'^[A-Za-z0-9_-]{1,100}$',
        ).hasMatch(body['update_id'] as String)) {
      throw const OperationalRouteException('pending_invalid');
    }
    if (!_savingKeys.add(pendingKey))
      throw const OperationalRouteException(
        'confirmation_missing',
        uncertain: true,
      );
    try {
      final previous = await _store.read(pendingKey);
      if (previous != null && jsonEncode(previous) != jsonEncode(body)) {
        throw const OperationalRouteException(
          'confirmation_missing',
          uncertain: true,
        );
      }
      // Persist the exact intent before transport, including across app restarts.
      await _store.write(pendingKey, body);
      final response = await _client
          .post(
            _uri('/operational-route'),
            headers: _headers(),
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
      final decoded = _decode(response);
      final route = OperationalRoute.fromMap(decoded['operational_route']);
      if (decoded['ok'] != true ||
          decoded['booking_id'] != bookingId ||
          route == null ||
          decoded['revision'] is! int ||
          (decoded['revision'] as int) < body['revision'] ||
          route.address != requested.address ||
          route.latitude != requested.latitude ||
          route.longitude != requested.longitude ||
          route.expectedEnd != requested.expectedEnd ||
          jsonEncode(route.toMap()) != jsonEncode(requested.toMap())) {
        throw const OperationalRouteException(
          'confirmation_missing',
          uncertain: true,
        );
      }
      await _store.clear(pendingKey);
      if (!isCurrent()) throw const OperationalRouteException('forbidden');
      return route;
    } on OperationalRouteException catch (error) {
      if (!error.uncertain) await _store.clear(pendingKey);
      rethrow;
    } catch (_) {
      throw const OperationalRouteException(
        'confirmation_missing',
        uncertain: true,
      );
    } finally {
      _savingKeys.remove(pendingKey);
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> body;
    try {
      body = operationalMap(jsonDecode(response.body));
    } catch (_) {
      body = {};
    }
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        body['ok'] == false) {
      throw OperationalRouteException(
        '${body['error'] ?? 'request_failed'}',
        uncertain:
            response.statusCode >= 500 ||
            response.statusCode == 408 ||
            response.statusCode == 429,
      );
    }
    return body;
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
