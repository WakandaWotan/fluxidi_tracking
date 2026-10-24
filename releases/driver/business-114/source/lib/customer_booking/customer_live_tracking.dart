import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Company of the opened booking. Never a global or last-picked company.
class CustomerLiveTrackingIdentity {
  const CustomerLiveTrackingIdentity({
    required this.tenantId,
    required this.companyId,
    required this.bookingId,
    this.customerId = '',
    this.operationalLeg = 'primary',
  });

  final String tenantId;
  final String companyId;
  final String bookingId;
  final String customerId;
  final String operationalLeg;

  bool get canTrack =>
      tenantId.trim().isNotEmpty &&
      companyId.trim().isNotEmpty &&
      bookingId.trim().isNotEmpty;

  @override
  bool operator ==(Object other) {
    return other is CustomerLiveTrackingIdentity &&
        other.tenantId == tenantId &&
        other.companyId == companyId &&
        other.bookingId == bookingId &&
        other.customerId == customerId &&
        other.operationalLeg == operationalLeg;
  }

  @override
  int get hashCode =>
      Object.hash(tenantId, companyId, bookingId, customerId, operationalLeg);
}

CustomerLiveTrackingIdentity? customerLiveTrackingIdentityFromSources({
  required String bookingId,
  required List<Map<String, dynamic>> maps,
  String? preferredLegType,
}) {
  String read(List<String> keys) {
    for (final map in maps) {
      for (final key in keys) {
        final value = _readPath(map, key).trim();
        if (value.isNotEmpty) return value;
      }
    }
    return '';
  }

  final tenantId = read(const ['tenant_id', 'tenantId']);
  final companyId = read(const ['company_id', 'companyId']);
  final id = bookingId.trim().isNotEmpty
      ? bookingId.trim()
      : read(const ['booking_id', 'bookingId', 'id']);
  if (tenantId.isEmpty || companyId.isEmpty || id.isEmpty) return null;
  var leg = read(const [
    'operational_leg',
    'operationalLeg',
    'customer_tracking_leg',
  ]);
  List<Map> legs = const [];
  for (final map in maps) {
    for (final source in [map, map['booking'], map['record']]) {
      if (source is! Map) continue;
      final raw = source['operational_legs'] ?? source['operationalLegs'];
      if (raw is List && raw.isNotEmpty) {
        legs = raw.whereType<Map>().toList();
        break;
      }
    }
    if (legs.isNotEmpty) break;
  }
  if (legs.length > 1) {
    String type(Map value) =>
        '${value['leg_type'] ?? value['legType'] ?? ''}'.toLowerCase();
    bool open(Map value) => !customerLivePhaseIsTerminal(
      customerLivePhaseFromToken(
        '${value['status'] ?? value['customer_tracking_phase'] ?? ''}',
      ),
    );
    final preferred = preferredLegType?.toLowerCase();
    final candidates = preferred == null
        ? legs.where(open).toList()
        : legs.where((value) => type(value) == preferred).toList();
    if (preferred != null && candidates.isEmpty) return null;
    final selected = candidates.isEmpty
        ? legs.first
        : candidates.firstWhere(
            (value) => type(value) == 'outbound',
            orElse: () => candidates.first,
          );
    leg = '${selected['leg_id'] ?? selected['legId'] ?? ''}'.trim();
    if (leg.isEmpty) return null;
  } else if (legs.length == 1) {
    leg = 'primary';
  }
  return CustomerLiveTrackingIdentity(
    tenantId: tenantId,
    companyId: companyId,
    bookingId: id,
    customerId: read(const ['customer_id', 'customerId']),
    operationalLeg: leg.isEmpty ? 'primary' : leg,
  );
}

String _readPath(Map<String, dynamic> root, String key) {
  final direct = root[key];
  if (direct != null && '$direct'.trim().isNotEmpty && '$direct' != 'null') {
    return '$direct'.trim();
  }
  for (final nestedKey in const ['booking', 'record', 'payload']) {
    final nested = root[nestedKey];
    if (nested is Map) {
      final value = nested[key];
      if (value != null && '$value'.trim().isNotEmpty && '$value' != 'null') {
        return '$value'.trim();
      }
    }
  }
  return '';
}

enum CustomerLivePhase {
  unassigned,
  assigned,
  enRoutePickup,
  inProgress,
  stopped,
  completed,
  cancelled,
  expired,
  unknown,
}

CustomerLivePhase customerLivePhaseFromToken(String? raw) {
  switch ((raw ?? '').trim().toLowerCase()) {
    case 'unassigned':
    case 'quoted':
    case 'pending':
      return CustomerLivePhase.unassigned;
    case 'assigned':
    case 'accepted':
    case 'confirmed':
      return CustomerLivePhase.assigned;
    case 'en_route':
    case 'en_route_pickup':
    case 'on_the_way':
    case 'driving_to_pickup':
      return CustomerLivePhase.enRoutePickup;
    case 'started':
    case 'in_progress':
    case 'on_trip':
    case 'picked_up':
    case 'driving':
      return CustomerLivePhase.inProgress;
    case 'stopped':
    case 'stop':
      return CustomerLivePhase.stopped;
    case 'completed':
    case 'complete':
      return CustomerLivePhase.completed;
    case 'cancelled':
    case 'canceled':
      return CustomerLivePhase.cancelled;
    case 'expired':
      return CustomerLivePhase.expired;
    default:
      return raw == null || raw.trim().isEmpty
          ? CustomerLivePhase.unknown
          : CustomerLivePhase.unknown;
  }
}

bool customerLivePhaseIsTerminal(CustomerLivePhase phase) {
  return phase == CustomerLivePhase.stopped ||
      phase == CustomerLivePhase.completed ||
      phase == CustomerLivePhase.cancelled ||
      phase == CustomerLivePhase.expired;
}

bool customerLivePhaseShowsPosition(CustomerLivePhase phase) {
  return phase == CustomerLivePhase.enRoutePickup ||
      phase == CustomerLivePhase.inProgress;
}

enum CustomerLiveFeedHealth { missing, stale, live, closed, unknown }

CustomerLiveFeedHealth customerLiveFeedFromToken(String? raw) {
  switch ((raw ?? '').trim().toLowerCase()) {
    case 'missing':
      return CustomerLiveFeedHealth.missing;
    case 'stale':
      return CustomerLiveFeedHealth.stale;
    case 'live':
      return CustomerLiveFeedHealth.live;
    case 'closed':
      return CustomerLiveFeedHealth.closed;
    default:
      return CustomerLiveFeedHealth.unknown;
  }
}

class CustomerLivePoint {
  const CustomerLivePoint({
    required this.latitude,
    required this.longitude,
    this.heading,
    this.capturedAt = '',
  });

  final double latitude;
  final double longitude;
  final double? heading;
  final String capturedAt;
}

class CustomerLiveEta {
  const CustomerLiveEta({
    required this.target,
    required this.durationSeconds,
    this.source = '',
    this.validUntil = '',
    this.distanceMeters,
  });

  final String target;
  final int durationSeconds;
  final String source;
  final String validUntil;
  final num? distanceMeters;
}

class CustomerLiveSnapshot {
  const CustomerLiveSnapshot({
    required this.phase,
    required this.feed,
    this.position,
    this.pickup,
    this.destination,
    this.eta,
    this.driverName = '',
    this.vehicleLabel = '',
    this.pollAfterSeconds = 0,
    this.accessUntil,
    this.routePoints = const <CustomerLivePoint>[],
    this.operationalRouteMetadata = const <String,dynamic>{},
  });

  final CustomerLivePhase phase;
  final CustomerLiveFeedHealth feed;
  final CustomerLivePoint? position;
  final CustomerLivePoint? pickup;
  final CustomerLivePoint? destination;
  final CustomerLiveEta? eta;
  final String driverName;
  final String vehicleLabel;
  final int pollAfterSeconds;
  final DateTime? accessUntil;
  final List<CustomerLivePoint> routePoints;
  final Map<String,dynamic> operationalRouteMetadata;

  bool get feedBlocksLive =>
      feed == CustomerLiveFeedHealth.closed ||
      feed == CustomerLiveFeedHealth.missing ||
      feed == CustomerLiveFeedHealth.stale ||
      feed == CustomerLiveFeedHealth.unknown;

  bool get showPosition =>
      customerLivePhaseShowsPosition(phase) &&
      !feedBlocksLive &&
      position != null;

  CustomerLiveEta? get showEta {
    if (!customerLivePhaseShowsPosition(phase) || eta == null) return null;
    if (feedBlocksLive) return null;
    if (phase == CustomerLivePhase.enRoutePickup && eta!.target != 'pickup') {
      return null;
    }
    if (phase == CustomerLivePhase.inProgress && eta!.target != 'destination') {
      return null;
    }
    return eta;
  }
}

class CustomerLiveBootstrap {
  const CustomerLiveBootstrap({
    required this.ok,
    this.token = '',
    this.phase = CustomerLivePhase.unknown,
    this.error = '',
    this.assignmentVersion = 0,
  });

  final bool ok;
  final String token;
  final CustomerLivePhase phase;
  final String error;
  final int assignmentVersion;

  bool get hasToken => ok && token.trim().isNotEmpty;
}

CustomerLiveBootstrap parseCustomerLiveBootstrap(Map<String, dynamic> body) {
  final session = body['tracking_session'];
  final token = session is Map
      ? (session['token'] ?? '').toString().trim()
      : '';
  return CustomerLiveBootstrap(
    ok: body['ok'] == true && token.isNotEmpty,
    token: token,
    phase: customerLivePhaseFromToken(
      '${body['tracking_phase'] ?? (body['tracking_sync'] is Map ? body['tracking_sync']['tracking_phase'] : null) ?? body['booking_status'] ?? ''}',
    ),
    assignmentVersion: int.tryParse('${body['assignment_version'] ?? ''}') ?? 0,
    error: (body['error'] ?? '').toString(),
  );
}

CustomerLiveSnapshot parseCustomerLiveSnapshot(Map<String, dynamic> body) {
  final phase = customerLivePhaseFromToken('${body['tracking_phase'] ?? ''}');
  final feedMap = body['feed'];
  final feed = customerLiveFeedFromToken(
    feedMap is Map ? '${feedMap['health'] ?? ''}' : '',
  );
  final refresh = body['refresh'];
  final poll = refresh is Map ? refresh['poll_after_seconds'] : null;
  final pollAfter = poll is num ? poll.round() : int.tryParse('$poll') ?? 0;
  return CustomerLiveSnapshot(
    phase: phase,
    feed: feed,
    position: _point(body['position']),
    pickup: _point(body['pickup']),
    destination: _point(body['destination']),
    eta: _eta(body['eta']),
    driverName: _driverName(body['driver']),
    vehicleLabel: _vehicleLabel(body['vehicle']),
    pollAfterSeconds: pollAfter < 0 ? 0 : pollAfter,
    accessUntil: refresh is Map
        ? DateTime.tryParse('${refresh['access_until'] ?? ''}')
        : null,
    routePoints: _routePoints(body['route']),
    operationalRouteMetadata: phase == CustomerLivePhase.inProgress ? _publicOperationalRoute(body['operational_route']) : const {},
  );
}

CustomerLivePoint? _point(Object? raw) {
  if (raw is! Map) return null;
  final lat = raw['latitude'] ?? raw['lat'];
  final lon = raw['longitude'] ?? raw['lon'] ?? raw['lng'];
  final latitude = lat is num ? lat.toDouble() : double.tryParse('$lat');
  final longitude = lon is num ? lon.toDouble() : double.tryParse('$lon');
  if (latitude == null || longitude == null) return null;
  final headingRaw = raw['heading'];
  final heading = headingRaw is num
      ? headingRaw.toDouble()
      : double.tryParse('${headingRaw ?? ''}');
  return CustomerLivePoint(
    latitude: latitude,
    longitude: longitude,
    heading: heading,
    capturedAt: (raw['captured_at'] ?? '').toString(),
  );
}

CustomerLiveEta? _eta(Object? raw) {
  if (raw is! Map) return null;
  final secondsRaw = raw['duration_seconds'];
  final seconds = secondsRaw is num
      ? secondsRaw.round()
      : int.tryParse('$secondsRaw');
  final target = (raw['target'] ?? '').toString().trim();
  if (seconds == null || target.isEmpty) return null;
  final distanceRaw = raw['distance_meters'];
  final distance = distanceRaw is num
      ? distanceRaw
      : num.tryParse('${distanceRaw ?? ''}');
  return CustomerLiveEta(
    target: target,
    durationSeconds: seconds,
    source: (raw['source'] ?? '').toString(),
    validUntil: (raw['valid_until'] ?? '').toString(),
    distanceMeters: distance,
  );
}

String _driverName(Object? raw) {
  if (raw is! Map) return '';
  return (raw['display_name'] ?? raw['displayName'] ?? '').toString().trim();
}

String _vehicleLabel(Object? raw) {
  if (raw is! Map) return '';
  final label = (raw['label'] ?? '').toString().trim();
  final color = (raw['color'] ?? '').toString().trim();
  if (label.isEmpty) return color;
  if (color.isEmpty) return label;
  return '$label · $color';
}

List<CustomerLivePoint> _routePoints(Object? raw) {
  if (raw is! Map) return const <CustomerLivePoint>[];
  final coords = raw['coordinates'] ?? raw['points'];
  if (coords is! List) return const <CustomerLivePoint>[];
  final out = <CustomerLivePoint>[];
  for (final item in coords) {
    final point = _point(item);
    if (point != null) out.add(point);
  }
  return out;
}

class CustomerLiveHttpResult {
  const CustomerLiveHttpResult({
    required this.statusCode,
    this.body = const <String, dynamic>{},
    this.failed = false,
  });

  final int statusCode;
  final Map<String, dynamic> body;
  final bool failed;
}

typedef CustomerLiveSend =
    Future<CustomerLiveHttpResult> Function({
      required String method,
      required Uri uri,
      required Map<String, String> headers,
      String? jsonBody,
    });

typedef CustomerLiveSchedule =
    Timer Function(Duration delay, void Function() callback);

enum CustomerLiveTrackingAvailability { idle, unavailable, tracking, ended }

class CustomerLiveTrackingView {
  const CustomerLiveTrackingView({
    this.availability = CustomerLiveTrackingAvailability.idle,
    this.snapshot = const CustomerLiveSnapshot(
      phase: CustomerLivePhase.unknown,
      feed: CustomerLiveFeedHealth.unknown,
    ),
    this.driverName = '',
  });

  final CustomerLiveTrackingAvailability availability;
  final CustomerLiveSnapshot snapshot;
  final String driverName;

  bool get showLivePosition =>
      availability == CustomerLiveTrackingAvailability.tracking &&
      snapshot.showPosition;

  CustomerLiveEta? get showEta =>
      availability == CustomerLiveTrackingAvailability.tracking
      ? snapshot.showEta
      : null;
}

/// One live request at a time. Polls only while [foreground] is true.
class CustomerLiveTrackingController extends ChangeNotifier {
  CustomerLiveTrackingController({
    required this.bookingBaseUrl,
    required this.trackingBaseUrl,
    required this.customerToken,
    CustomerLiveSend? send,
    CustomerLiveSchedule? schedule,
    DateTime Function()? now,
    this.assignedRecheck = const Duration(seconds: 10),
    this.baseBackoff = const Duration(seconds: 2),
    this.maxBackoff = const Duration(seconds: 30),
  }) : _send = send ?? _defaultSend,
       _schedule = schedule ?? Timer.new,
       _now = now ?? DateTime.now;

  final String bookingBaseUrl;
  final String trackingBaseUrl;
  final Future<String?> Function() customerToken;
  final Duration assignedRecheck;
  final Duration baseBackoff;
  final Duration maxBackoff;
  final CustomerLiveSend _send;
  final CustomerLiveSchedule _schedule;
  final DateTime Function() _now;
  // The backend grants 90 seconds. Renew with 30 seconds of headroom.
  static const _renewInterval = Duration(seconds: 60);
  static const _renewHeadroom = Duration(seconds: 30);
  DateTime? _renewAt;

  CustomerLiveTrackingView view = const CustomerLiveTrackingView();
  CustomerLiveTrackingIdentity? _identity;
  String _token = '';
  int _assignmentVersion = 0;
  bool _recoveringAssignment = false;
  bool _foreground = false;
  bool _busy = false;
  bool _again = false;
  bool _disposed = false;
  int _generation = 0;
  Timer? _timer;
  Timer? _freshnessTimer;
  int _liveGets = 0;
  int _bootstraps = 0;
  Duration _backoff = const Duration(seconds: 2);

  int get liveGets => _liveGets;
  int get bootstraps => _bootstraps;

  void bind(CustomerLiveTrackingIdentity? identity) {
    if (_identity == identity) {
      _kick();
      return;
    }
    _generation++;
    _freshnessTimer?.cancel();
    view = const CustomerLiveTrackingView();
    _assignmentVersion = 0;
    _recoveringAssignment = false;
    _identity = identity;
    _token = '';
    _backoff = baseBackoff;
    _timer?.cancel();
    if (identity == null || !identity.canTrack) {
      view = const CustomerLiveTrackingView(
        availability: CustomerLiveTrackingAvailability.unavailable,
      );
      notifyListeners();
      return;
    }
    _kick();
  }

  void setForeground(bool value, {bool rebootstrap = false}) {
    if (_disposed) return;
    final becameVisible = value && !_foreground;
    if (value != _foreground || rebootstrap) _generation++;
    _foreground = value;
    if (!value) {
      _timer?.cancel();
      return;
    }
    if (becameVisible || rebootstrap) {
      _token = '';
      _backoff = baseBackoff;
    }
    _kick();
  }

  void _kick() {
    if (_disposed ||
        !_foreground ||
        view.availability == CustomerLiveTrackingAvailability.ended)
      return;
    final identity = _identity;
    if (identity == null || !identity.canTrack) return;
    if (_busy) {
      _again = true;
      return;
    }
    unawaited(_tick());
  }

  Future<void> _tick() async {
    if (_disposed ||
        !_foreground ||
        _busy ||
        view.availability == CustomerLiveTrackingAvailability.ended)
      return;
    final identity = _identity;
    if (identity == null || !identity.canTrack) return;
    final generation = _generation;
    var requestToken = _token;
    var requestVersion = _assignmentVersion;
    // Keep the request lock until completion, but discard every async result
    // (including errors) whose lifecycle or grant context has been superseded.
    bool isCurrent() =>
        !_disposed &&
        _foreground &&
        _generation == generation &&
        _identity == identity &&
        _token == requestToken &&
        _assignmentVersion == requestVersion;
    _busy = true;
    _again = false;
    try {
      if (_token.isEmpty) {
        final startedAt = _now();
        final boot = await _bootstrap(identity);
        if (!isCurrent()) return;
        if (!boot.hasToken) {
          _freshnessTimer?.cancel();
          _token = '';
          view = CustomerLiveTrackingView(
            availability: customerLivePhaseIsTerminal(boot.phase)
                ? CustomerLiveTrackingAvailability.ended
                : CustomerLiveTrackingAvailability.unavailable,
            snapshot: CustomerLiveSnapshot(
              phase: boot.phase,
              feed: CustomerLiveFeedHealth.closed,
            ),
          );
          notifyListeners();
          if ((_recoveringAssignment || identity.operationalLeg != 'primary') &&
              !customerLivePhaseIsTerminal(boot.phase) &&
              (boot.error == 'not_assigned' ||
                  boot.error == 'tracking_not_confirmed')) {
            _arm(assignedRecheck);
          }
          return;
        }
        _token = boot.token;
        _assignmentVersion = boot.assignmentVersion;
        requestToken = _token;
        requestVersion = _assignmentVersion;
        _renewAt = startedAt.add(_renewInterval);
      }
      if (_renewAt != null && !_now().isBefore(_renewAt!)) {
        final startedAt = _now();
        final renewal = await _renew(identity);
        if (!isCurrent()) return;
        final renewedVersion =
            int.tryParse('${renewal.body['assignment_version'] ?? ''}') ?? 0;
        if ((renewal.statusCode == 200 || renewal.statusCode == 404) &&
            _assignmentVersion > 0 &&
            renewedVersion > 0 &&
            renewedVersion != _assignmentVersion &&
            !customerLivePhaseIsTerminal(
              customerLivePhaseFromToken(
                '${renewal.body['tracking_phase'] ?? ''}',
              ),
            )) {
          _recoverAssignment();
          return;
        }
        if (renewal.statusCode == 401 ||
            renewal.statusCode == 403 ||
            renewal.statusCode == 404) {
          _endAndClear();
          return;
        }
        final sync = renewal.body['tracking_sync'];
        if (renewal.failed ||
            renewal.statusCode != 200 ||
            renewal.body['ok'] != true ||
            sync is! Map ||
            sync['confirmed'] != true ||
            sync['reason'] != 'renew') {
          _freshnessTimer?.cancel();
          // Unconfirmed renewal must not keep showing a live position.
          view = const CustomerLiveTrackingView(
            availability: CustomerLiveTrackingAvailability.unavailable,
          );
          notifyListeners();
          _scheduleBackoff();
          return;
        }
        _renewAt = startedAt.add(_renewInterval);
      }
      final result = await _live(identity);
      if (!isCurrent()) return;
      if (result.statusCode == 409 &&
          result.body['error'] == 'assignment_changed') {
        _recoverAssignment();
        return;
      }
      if (result.statusCode == 401 ||
          result.statusCode == 403 ||
          result.statusCode == 404) {
        _endAndClear();
        return;
      }
      if (result.failed || result.statusCode != 200) {
        _transientFailure();
        return;
      }
      _freshnessTimer?.cancel();
      _backoff = baseBackoff;
      final snapshot = parseCustomerLiveSnapshot(result.body);
      if (snapshot.accessUntil != null) {
        _renewAt = snapshot.accessUntil!.subtract(_renewHeadroom);
      }
      if (customerLivePhaseIsTerminal(snapshot.phase)) {
        _endAndClear(phase: snapshot.phase, feed: snapshot.feed);
        return;
      }
      final responseVersion =
          int.tryParse('${result.body['assignment_version'] ?? ''}') ?? 0;
      if (_assignmentVersion > 0 &&
          responseVersion > 0 &&
          responseVersion != _assignmentVersion) {
        _recoverAssignment();
        return;
      }
      _recoveringAssignment = false;
      if (snapshot.phase == CustomerLivePhase.assigned) {
        view = CustomerLiveTrackingView(
          availability: CustomerLiveTrackingAvailability.tracking,
          snapshot: CustomerLiveSnapshot(
            phase: CustomerLivePhase.assigned,
            feed: snapshot.feed,
            driverName: snapshot.driverName,
            vehicleLabel: snapshot.vehicleLabel,
          ),
          driverName: snapshot.driverName,
        );
        notifyListeners();
        _token = '';
        _arm(assignedRecheck);
        return;
      }
      view = CustomerLiveTrackingView(
        availability: CustomerLiveTrackingAvailability.tracking,
        snapshot: snapshot,
        driverName: snapshot.driverName,
      );
      _boundFreshness(snapshot);
      notifyListeners();
      if (snapshot.pollAfterSeconds <= 0) return;
      var delay = Duration(seconds: snapshot.pollAfterSeconds);
      final renewDelay = _renewAt?.difference(_now());
      if (renewDelay != null && renewDelay < delay) {
        delay = renewDelay.isNegative ? Duration.zero : renewDelay;
      }
      _arm(delay);
    } catch (_) {
      if (isCurrent()) _transientFailure();
    } finally {
      _busy = false;
      if (_again && _foreground && !_disposed) {
        _again = false;
        unawaited(_tick());
      }
    }
  }

  void _recoverAssignment() {
    _generation++;
    _token = '';
    _renewAt = null;
    _again = false;
    _recoveringAssignment = true;
    _timer?.cancel();
    _freshnessTimer?.cancel();
    // Clear name, vehicle, position and ETA before asking the booking owner
    // endpoint for a new grant. Use the existing assignment recheck interval.
    view = const CustomerLiveTrackingView(
      availability: CustomerLiveTrackingAvailability.unavailable,
    );
    notifyListeners();
    _arm(assignedRecheck);
  }

  void _endAndClear({
    CustomerLivePhase phase = CustomerLivePhase.unknown,
    CustomerLiveFeedHealth feed = CustomerLiveFeedHealth.closed,
  }) {
    _generation++;
    _token = '';
    _again = false;
    _freshnessTimer?.cancel();
    _timer?.cancel();
    view = CustomerLiveTrackingView(
      availability: CustomerLiveTrackingAvailability.ended,
      snapshot: CustomerLiveSnapshot(phase: phase, feed: feed),
    );
    notifyListeners();
  }

  void _transientFailure() {
    _freshnessTimer?.cancel();
    view = CustomerLiveTrackingView(
      availability: CustomerLiveTrackingAvailability.unavailable,
      snapshot: CustomerLiveSnapshot(
        phase: view.snapshot.phase,
        feed: CustomerLiveFeedHealth.stale,
      ),
      driverName: view.driverName,
    );
    notifyListeners();
    _scheduleBackoff();
  }

  // A response is not proof that its GPS/ETA is recent. Also bound the last
  // successful response so a pending request cannot freeze live data forever.
  void _boundFreshness(CustomerLiveSnapshot snapshot) {
    _freshnessTimer?.cancel();
    final received = _now();
    final cap = received.add(const Duration(seconds: 30));
    DateTime earliest(DateTime a, DateTime? b) =>
        b != null && b.isBefore(a) ? b : a;
    final captured = DateTime.tryParse(snapshot.position?.capturedAt ?? '');
    final positionUntil = earliest(
      earliest(cap, snapshot.accessUntil),
      captured?.add(const Duration(seconds: 300)),
    );
    final etaUntil = earliest(
      positionUntil,
      DateTime.tryParse(snapshot.eta?.validUntil ?? ''),
    );
    void expire() {
      if (_disposed) return;
      final now = _now();
      final positionExpired = !now.isBefore(positionUntil);
      final etaExpired = !now.isBefore(etaUntil);
      view = CustomerLiveTrackingView(
        availability: view.availability,
        snapshot: CustomerLiveSnapshot(
          phase: snapshot.phase,
          feed: positionExpired ? CustomerLiveFeedHealth.stale : snapshot.feed,
          position: positionExpired ? null : snapshot.position,
          eta: etaExpired ? null : snapshot.eta,
          driverName: snapshot.driverName,
          vehicleLabel: snapshot.vehicleLabel,
          pollAfterSeconds: snapshot.pollAfterSeconds,
          accessUntil: snapshot.accessUntil,
          routePoints: snapshot.routePoints,
          pickup: snapshot.pickup,
          destination: snapshot.destination,
          operationalRouteMetadata:snapshot.operationalRouteMetadata,
        ),
        driverName: snapshot.driverName,
      );
      notifyListeners();
      if (!positionExpired) {
        _freshnessTimer = _schedule(positionUntil.difference(now), expire);
      }
    }

    final first = snapshot.eta != null ? etaUntil : positionUntil;
    if (!received.isBefore(first)) {
      expire();
    } else {
      _freshnessTimer = _schedule(first.difference(received), expire);
    }
  }

  void _scheduleBackoff() {
    _again = false;
    final delay = _backoff;
    final nextMs = delay.inMilliseconds * 2;
    _backoff = Duration(
      milliseconds: nextMs > maxBackoff.inMilliseconds
          ? maxBackoff.inMilliseconds
          : nextMs,
    );
    _arm(delay);
  }

  void _arm(Duration delay) {
    _timer?.cancel();
    if (!_foreground || _disposed) return;
    _timer = _schedule(delay, () {
      if (_foreground && !_disposed) unawaited(_tick());
    });
  }

  Future<CustomerLiveBootstrap> _bootstrap(
    CustomerLiveTrackingIdentity identity,
  ) async {
    _bootstraps += 1;
    final token = (await customerToken())?.trim() ?? '';
    if (token.isEmpty) {
      return const CustomerLiveBootstrap(
        ok: false,
        error: 'no_customer_session',
      );
    }
    final uri = Uri.parse(
      '${_trim(bookingBaseUrl)}/bookings/${Uri.encodeComponent(identity.bookingId)}/customer-tracking',
    );
    final result = await _send(
      method: 'POST',
      uri: uri,
      headers: <String, String>{
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'cache-control': 'no-store',
      },
      jsonBody: identity.operationalLeg == 'primary'
          ? '{}'
          : jsonEncode({'operational_leg': identity.operationalLeg}),
    );
    if (result.failed ||
        result.statusCode >= 500 ||
        result.statusCode == 408 ||
        result.statusCode == 429) {
      throw StateError('tracking_temporarily_unavailable');
    }

    if (result.body.isEmpty) {
      return const CustomerLiveBootstrap(ok: false, error: 'bootstrap_failed');
    }
    return parseCustomerLiveBootstrap(result.body);
  }

  Future<CustomerLiveHttpResult> _renew(
    CustomerLiveTrackingIdentity identity,
  ) async {
    final token = (await customerToken())?.trim() ?? '';
    if (token.isEmpty) {
      return const CustomerLiveHttpResult(statusCode: 401);
    }
    return _send(
      method: 'POST',
      uri: Uri.parse(
        '${_trim(bookingBaseUrl)}/bookings/${Uri.encodeComponent(identity.bookingId)}/customer-tracking',
      ),
      headers: <String, String>{
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'cache-control': 'no-store',
      },
      jsonBody: identity.operationalLeg == 'primary'
          ? '{"action":"renew"}'
          : jsonEncode({
              'action': 'renew',
              'operational_leg': identity.operationalLeg,
            }),
    );
  }

  Future<CustomerLiveHttpResult> _live(
    CustomerLiveTrackingIdentity identity,
  ) async {
    _liveGets += 1;
    final uri = Uri.parse('${_trim(trackingBaseUrl)}/track/customer/live')
        .replace(
          queryParameters: <String, String>{
            'tenant_id': identity.tenantId,
            'company_id': identity.companyId,
            'booking_id': identity.bookingId,
            if (identity.customerId.trim().isNotEmpty)
              'customer_id': identity.customerId.trim(),
            'operational_leg': identity.operationalLeg,
            if (_assignmentVersion > 0)
              'assignment_version': '$_assignmentVersion',
          },
        );
    return _send(
      method: 'GET',
      uri: uri,
      headers: <String, String>{
        'Authorization': 'Bearer $_token',
        'cache-control': 'no-store',
      },
    );
  }

  @override
  void dispose() {
    _freshnessTimer?.cancel();
    _generation++;
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

String _trim(String base) {
  final value = base.trim();
  if (value.endsWith('/')) return value.substring(0, value.length - 1);
  return value;
}

Future<CustomerLiveHttpResult> _defaultSend({
  required String method,
  required Uri uri,
  required Map<String, String> headers,
  String? jsonBody,
}) async {
  final client = http.Client();
  try {
    final response = method == 'POST'
        ? await client
              .post(uri, headers: headers, body: jsonBody ?? '{}')
              .timeout(const Duration(seconds: 12))
        : await client
              .get(uri, headers: headers)
              .timeout(const Duration(seconds: 12));
    // Preserve HTTP error semantics even for an HTML/empty error response.
    if (response.statusCode != 200) {
      Map<String, dynamic> body = const {};
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map) body = Map<String, dynamic>.from(decoded);
      } catch (_) {
        /* HTTP status remains authoritative for non-JSON errors. */
      }
      return CustomerLiveHttpResult(
        statusCode: response.statusCode,
        body: body,
      );
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    return CustomerLiveHttpResult(
      statusCode: response.statusCode,
      body: decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : const <String, dynamic>{},
    );
  } catch (_) {
    return const CustomerLiveHttpResult(statusCode: 0, failed: true);
  } finally {
    client.close();
  }
}

Map<String,dynamic> _publicOperationalRoute(Object? raw) {
  if (raw is! Map) return const {};
  final address = raw['destination_address'], end = raw['expected_end_iso'];
  if (address is! String || address.trim().isEmpty || address.length > 400 ||
      end is! String || DateTime.tryParse(end) == null) return const {};
  return Map<String,dynamic>.unmodifiable({'destination_address':address.trim(), 'expected_end_iso':end});
}
