import 'dart:async';
import 'package:flutter/foundation.dart';
import 'driver_ride_alert.dart';

/// Presentation only. The host supplies an already server-validated offer and
/// its existing deadline. This controller never fetches or decides a booking.
class DriverRideAlertController extends ChangeNotifier {
  DriverRideAlertController({
    Future<void> Function(bool)? play,
    Future<void> Function()? stop,
    int Function()? nowMs,
  }) : _play = play,
       _stop = stop ?? DriverRideAlert.stop,
       _now = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);
  static final instance = DriverRideAlertController();
  final Future<void> Function(bool)? _play;
  final Future<void> Function() _stop;
  final int Function() _now;
  Timer? _expiry;
  Object? _owner;
  String? _identity;
  int _generation = 0;
  bool _active = false, _disposed = false;
  Future<void> _effects = SynchronousFuture<void>(null);
  final Map<String, int> _announced = {};
  bool get active => _active;

  void present({
    required Object owner,
    required String identity,
    required int deadlineMs,
    bool flashlight = false,
    Map<String, Object?>? offerScope,
  }) {
    final remaining = deadlineMs - _now();
    if (_disposed || identity.isEmpty || remaining <= 0) {
      stop(owner: owner);
      return;
    }
    final changed = !_active || _identity != identity;
    _owner = owner;
    _identity = identity;
    _active = true;
    _expiry?.cancel();
    _expiry = Timer(
      Duration(milliseconds: remaining),
      () => stop(owner: owner),
    );
    // Attention history is not an availability lease. Keep a short bounded
    // history across receipt-driven deadline updates without extending effects.
    final retention = deadlineMs > _now() + 300000 ? deadlineMs : _now() + 300000;
    if (_announced.containsKey(identity)) _announced[identity] = retention;
    if (!changed) return;
    final generation = ++_generation;
    _announced.removeWhere((_, deadline) => deadline <= _now());
    final announce =
        !_announced.containsKey(identity) && _announced.length < 64;
    _effects = _effects
        .then((_) async {
          await _stop();
          if (!_disposed && _active && generation == _generation && announce) {
        _announced[identity] = retention;
            if (_play != null) {
              await _play(flashlight);
            } else {
              await DriverRideAlert.play(
                flashlight: flashlight,
                offerScope: offerScope,
              );
            }
          }
        })
        .catchError((Object _) {});
    notifyListeners();
  }

  /// A covered/disposed older host cannot stop a newer inbox host's effects.
  void stop({required Object owner}) {
    if (_disposed || !identical(_owner, owner)) return;
    _expiry?.cancel();
    _expiry = null;
    _generation++;
    _owner = null;
    _identity = null;
    final changed = _active;
    _active = false;
    unawaited(_stop().catchError((Object _) {}));
    _effects = _effects.then((_) => _stop()).catchError((Object _) {});
    if (changed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _expiry?.cancel();
    _disposed = true;
    _active = false;
    _generation++;
    unawaited(_stop().catchError((Object _) {}));
    _effects = _effects.then((_) => _stop()).catchError((Object _) {});
    super.dispose();
  }
}
