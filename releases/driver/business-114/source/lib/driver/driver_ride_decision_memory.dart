import 'package:flutter/foundation.dart';

/// Short-lived presentation/transport memory across cockpit and inbox mounts.
/// A confirmed decision is NOT a canonical assignment or permission to START.
class DriverRideDecision {
  DriverRideDecision(this.action, this.retainUntilMs);
  final String action;
  final int retainUntilMs;
  bool inFlight = true;
  bool confirmed = false;
}

class DriverRideDecisionMemory extends ChangeNotifier {
  static final instance = DriverRideDecisionMemory();
  final _entries = <String, DriverRideDecision>{};

  void complete(DriverRideDecision decision) {
    decision.inFlight = false;
    notifyListeners();
  }

  DriverRideDecision? read(String identity, int nowMs) {
    _entries.removeWhere((_, entry) => !entry.inFlight && entry.retainUntilMs <= nowMs);
    return _entries[identity];
  }

  DriverRideDecision? begin(String identity, String action, int deadlineMs, int nowMs) {
    final previous = read(identity, nowMs);
    if (previous != null) {
      if (previous.confirmed || previous.inFlight || previous.action != action) return null;
      previous.inFlight = true;
      return previous;
    }
    // Never evict an unresolved decision to enable another conflicting request.
    if (_entries.length >= 64) return null;
    final retainUntil = deadlineMs > nowMs + 300000 ? deadlineMs : nowMs + 300000;
    return _entries[identity] = DriverRideDecision(action, retainUntil);
  }
}
