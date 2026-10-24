import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:fluxidi_tracking/driver_session_store.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'dart:math';

/// Native availability survives backgrounding, but ends on explicit task removal.
class DriverDutyBridge {
  /// Booking stores an active ride as busy. Keep its GPS lease without making
  /// that chauffeur eligible for new dispatch work.
  static bool availabilityAllowsGps(String status) =>
      const ['available', 'busy', 'on_trip'].contains(status);

  static const channel = MethodChannel('fluxidi/driver_duty');
  static int _generation = 0;
  static String _activationId = '';
  static Map<String, Object>? _activationConfig;
  static ActiveDriverSession? _observedOwner;
  static bool _listening = false;
  static String _newActivationId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
  static void initialize() {
    if (_listening) return;
    _listening = true;
    _observedOwner = nativeDriverDutySessionNotifier.value;
    nativeDriverDutySessionNotifier.addListener(() {
      final owner = nativeDriverDutySessionNotifier.value;
      final previous = _observedOwner;
      _observedOwner = owner;
      if (!_sameActor(owner, previous) && previous != null) stop(owner: previous);
    });
  }

  static bool sameAuthenticatedActor(ActiveDriverSession? a, ActiveDriverSession? b) {
    if (a == null || b == null) return a == null && b == null;
    return a.driverSessionToken == b.driverSessionToken &&
        driverDutyIdentity(a).matches(tenantId: b.tenantId ?? '',
          companyId: b.companyId ?? '', driverId: b.driverId,
          vehicleId: b.assignedVehicleId ?? '');
  }

  static bool _sameActor(ActiveDriverSession? a, ActiveDriverSession? b) =>
      sameAuthenticatedActor(a, b);

  static bool activationOwnerIsCurrent(ActiveDriverSession session, {
    required bool businessPreview,
  }) => _sameActor(session, businessPreview
      ? nativeDriverDutySessionNotifier.value
      : activeDriverSessionNotifier.value);

  static Map<String, Object> _config(ActiveDriverSession owner, Map<String, Object> config) =>
      Map<String, Object>.unmodifiable({
        ...config,
        'token': owner.driverSessionToken ?? '',
        'tenant_id': owner.tenantId ?? '', 'company_id': owner.companyId ?? '',
        'driver_id': owner.driverId, 'vehicle_id': owner.assignedVehicleId ?? '',
        'booking': config['booking'] ?? kBookingBaseUrl,
        'tracking': config['tracking'] ?? appConfig.workerBaseUrl,
      }..remove('activation_id'));

  static Future<String?> _runningActivation(Map<String, Object> config) async {
    final raw = await channel.invokeMethod<dynamic>('status', {'expected_config': config});
    if (raw is! Map || raw['running'] != true) return null;
    final activation = (raw['activation_id'] ?? '').toString().trim();
    return activation.isEmpty ? null : activation;
  }

  /// Pre-START and trip GPS share the dedicated native lease only for the exact
  /// authenticated actor. Admin preview has its own bearer and cannot borrow it.
  /// Capture the HTTP bearer before the native await; a late callback never
  /// publishes an old fix with a newly selected actor's credentials.
  static Future<T> sendGps<T>({
    required ActiveDriverSession? session,
    required Map<String, dynamic> payload,
    required String bookingBaseUrl,
    required String trackingBaseUrl,
    required bool Function() isCurrent,
    required Future<T> Function(Map<String, dynamic>, Map<String, String>) request,
  }) async {
    final generation = _generation;
    final owner = nativeDriverDutySessionNotifier.value;
    final proof = <String, String>{};
    if (isNativeDriverDutySession(owner) && _sameActor(session, owner) &&
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      // Optional actor aliases may be absent in a legacy payload, but no
      // conflicting scope/driver/vehicle may inherit the physical device lease.
      final identity = driverDutyIdentity(owner!);
      final expectedActor = {
        'tenant_id': identity.tenantId, 'tenantId': identity.tenantId,
        'company_id': identity.companyId, 'companyId': identity.companyId,
        'driver_id': identity.driverId, 'driverId': identity.driverId,
        'actor_driver_id': identity.driverId, 'actorDriverId': identity.driverId,
        'vehicle_id': identity.vehicleId, 'vehicleId': identity.vehicleId,
        'actor_vehicle_id': identity.vehicleId, 'actorVehicleId': identity.vehicleId,
      };
      if (expectedActor.entries.any((entry) => payload[entry.key] != null &&
          payload[entry.key].toString().trim() != entry.value)) {
        throw StateError('GPS actor changed');
      }
      final raw = await channel.invokeMethod<dynamic>('status', {
        'expected_config': _config(owner, {
          'booking': bookingBaseUrl, 'tracking': trackingBaseUrl,
        }),
      });
      final activation = raw is Map ? '${raw['activation_id'] ?? ''}'.trim() : '';
      final device = raw is Map ? '${raw['native_device_id'] ?? ''}'.trim() : '';
      if (raw is! Map || raw['running'] != true || activation.isEmpty || device.isEmpty) {
        throw StateError('Native GPS owner not ready');
      }
      proof.addAll({'activation_id': activation, 'native_device_id': device});
    }
    if (generation != _generation || !_sameActor(owner, nativeDriverDutySessionNotifier.value) ||
        !isCurrent()) throw StateError('GPS owner changed');
    final token = (session?.driverSessionToken ?? '').trim();
    return request({...payload, ...proof}, {
      'Content-Type': 'application/json',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    });
  }

  static Future<bool> consentAccepted() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    return await channel.invokeMethod<bool>('consent') ?? false;
  }

  static Future<bool> start(Map<String, Object> config) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    initialize();
    final token = config['token'] as String;
    final owner = nativeDriverDutySessionNotifier.value;
    if (!isNativeDriverDutySession(owner) || owner?.driverSessionToken != token) return false;
    final expected = _config(owner!, config);
    var generation = _generation;
    if (mapEquals(_activationConfig, expected) && _activationId.isNotEmpty) {
      final status = await channel.invokeMethod<dynamic>('status', {'activation_id': _activationId});
      if (generation != _generation || !_sameActor(owner, nativeDriverDutySessionNotifier.value)) return false;
      // Another accepted publisher retired this lease. Repeated foreground
      // sync must not create competing activations. Explicit pause/stop clears
      // our activation, after which Available may start a new authenticated one.
      if (status is Map && status['reason'] == 'location_owner_retired') return false;
      final running = await channel.invokeMethod<bool>('running', {'activation_id': _activationId}) == true;
      if (generation != _generation || !_sameActor(owner, nativeDriverDutySessionNotifier.value)) return false;
      if (running) return true;
    }
    final restoredActivation = await _runningActivation(expected);
    if (generation != _generation || !_sameActor(owner, nativeDriverDutySessionNotifier.value)) return false;
    if (restoredActivation != null) {
      _activationId = restoredActivation;
      _activationConfig = expected;
      return true;
    }
    generation = ++_generation;
    final activation = _newActivationId();
    _activationId = activation;
    _activationConfig = expected;
    final started = await channel.invokeMethod<bool>('start', {...expected, 'activation_id': activation}) ?? false;
    if (generation != _generation || !_sameActor(owner, nativeDriverDutySessionNotifier.value)) {
      // An old completion must not stop the replacement owner.
      await channel.invokeMethod<void>('stop', {'activation_id': activation});
      return false;
    }
    if (!started && _activationId == activation) {
      _activationId = '';
      _activationConfig = null;
    }
    return started;
  }

  /// Explicit logout waits for native publisher teardown before clearing the
  /// driver session. A confirmed local stop queues the existing immutable
  /// withdrawal; it does not promise delivery while the device is offline.
  static Future<bool> stopConfirmed({
    required ActiveDriverSession owner,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    initialize();
    bool ownsConfig(Map<String, Object>? config) =>
        config == null ||
        (config['token'] == owner.driverSessionToken &&
            driverDutyIdentity(owner).toJson().entries.every(
              (entry) => config[entry.key] == entry.value,
            ));
    final nativeOwner = nativeDriverDutySessionNotifier.value;
    if (!ownsConfig(_activationConfig) ||
        (nativeOwner != null && !_sameActor(owner, nativeOwner)))
      return false;
    final generation = ++_generation;
    final expected = _activationConfig ?? _config(owner, const {});
    bool current() =>
        generation == _generation &&
        ownsConfig(_activationConfig) &&
        (nativeDriverDutySessionNotifier.value == null ||
            _sameActor(owner, nativeDriverDutySessionNotifier.value));
    bool stopped(dynamic raw) =>
        raw is Map &&
        raw['running'] == false &&
        const ['stopped', 'failed'].contains(raw['state']);
    void forgetActivation() {
      _activationId = '';
      _activationConfig = null;
    }

    try {
      final raw = await channel.invokeMethod<dynamic>('status', {
        'expected_config': expected,
      });
      if (!current() || raw is! Map) return false;
      if (raw['reason'] == 'owner_not_current') {
        // Expected-owner status deliberately hides a foreign lease. Only an
        // explicit process-wide stopped state can confirm the no-op safely.
        final actual = await channel.invokeMethod<dynamic>('status');
        if (!current() || !stopped(actual)) return false;
        forgetActivation();
        return true;
      }
      final activation = '${raw['activation_id'] ?? ''}'.trim();
      if (stopped(raw)) {
        forgetActivation();
        return true;
      }
      if (!const ['starting', 'ready'].contains(raw['state']) ||
          activation.isEmpty)
        return false;
      final acknowledged = await channel.invokeMethod<bool>('stop', {
        'activation_id': activation,
      });
      if (!current() || acknowledged != true) return false;
      forgetActivation();
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<void> stop({bool global = false, ActiveDriverSession? owner}) async {
    final currentConfig = _activationConfig;
    if (owner != null && currentConfig != null &&
        (currentConfig['token'] != owner.driverSessionToken ||
         driverDutyIdentity(owner).toJson().entries.any((entry) => currentConfig[entry.key] != entry.value))) {
      // A delayed old actor callback is not an explicit stop of the new owner.
      return;
    }
    final generation = ++_generation;
    var activation = _activationId;
    final expected = _activationConfig ?? (owner == null ? null : _config(owner, const {}));
    _activationId = '';
    _activationConfig = null;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      if (activation.isEmpty && expected != null) {
        activation = await _runningActivation(expected) ?? '';
        if (generation != _generation) return;
      }
      if (activation.isNotEmpty) {
        await channel.invokeMethod<void>('stop', {'activation_id': activation});
      } else if (global) {
        await channel.invokeMethod<void>('stop');
      }
    } on PlatformException {
      /* Already stopped. */
    } on MissingPluginException {
      /* No native task on this engine. */
    }
  }
}
