import 'package:flutter/foundation.dart';

/// Counts open booking or payment flows so a lock prompt cannot interrupt them.
class CustomerBookingPresence {
  CustomerBookingPresence._();

  static final CustomerBookingPresence instance = CustomerBookingPresence._();

  int _depth = 0;
  final List<VoidCallback> _idleListeners = <VoidCallback>[];

  bool get isActive => _depth > 0;

  void addIdleListener(VoidCallback listener) {
    if (!_idleListeners.contains(listener)) {
      _idleListeners.add(listener);
    }
  }

  void removeIdleListener(VoidCallback listener) {
    _idleListeners.remove(listener);
  }

  void enter() => _depth += 1;

  void leave() {
    if (_depth > 0) _depth -= 1;
    if (_depth == 0) {
      for (final listener in List<VoidCallback>.from(_idleListeners)) {
        listener();
      }
    }
  }

  void debugReset() => _depth = 0;

  static Future<T> guard<T>(Future<T> Function() body) async {
    instance.enter();
    try {
      return await body();
    } finally {
      instance.leave();
    }
  }
}
