// NAV-MOBILE-DATA-MINIMAL-SAFE-RELEASE-P0-1 — Part E
//
// Dedicated meter presentation notifier. Wraps the authoritative
// [DriverRideMetersSnapshot] in a [ValueNotifier] so meter/HUD subtrees can
// rebuild in isolation (via [ValueListenableBuilder]) without invoking
// `setState()` on a state tree that contains MapWidget.
//
// The notifier is pure presentation plumbing — the underlying numeric state
// (`_kmDriven`, `_liveMeterTotalEur`, waiting timers) still lives in the
// driver page state, which remains authoritative for STOP/receipt.

import 'package:flutter/foundation.dart';

import 'driver_ride_meters.dart' show DriverRideMetersSnapshot;

/// Dedicated presentation notifier for the driver ride meters.
///
/// Consumers should render meter text through
/// `ValueListenableBuilder<DriverRideMetersSnapshot>` so a meter tick can
/// repaint only the meter subtree — the MapWidget subtree remains untouched.
class DriverRideMetersNotifier
    extends ValueNotifier<DriverRideMetersSnapshot> {
  DriverRideMetersNotifier(super.initial);

  /// Publish a fresh snapshot. Consumers subscribed via
  /// `ValueListenableBuilder` receive the new value; the enclosing State does
  /// NOT need to call `setState`.
  ///
  /// If the snapshot is identical to the current one, no notification fires
  /// (identity + field equality both suppress duplicate rebuilds).
  void publish(DriverRideMetersSnapshot snapshot) {
    if (identical(value, snapshot)) return;
    if (_sameSnapshot(value, snapshot)) return;
    value = snapshot;
  }

  static bool _sameSnapshot(
    DriverRideMetersSnapshot a,
    DriverRideMetersSnapshot b,
  ) {
    return a.fareText == b.fareText &&
        a.distanceTravelledText == b.distanceTravelledText &&
        a.rideDurationText == b.rideDurationText &&
        a.waitingTimeText == b.waitingTimeText &&
        a.statusText == b.statusText &&
        a.etaText == b.etaText &&
        a.remainingDistanceText == b.remainingDistanceText &&
        a.tariffName == b.tariffName &&
        a.companyName == b.companyName;
  }
}

/// Constructs a placeholder empty snapshot for the initial notifier value
/// before any GPS/meter tick fires.
DriverRideMetersSnapshot emptyDriverRideMetersSnapshot() {
  return const DriverRideMetersSnapshot(
    fareText: '€ 0,00',
    distanceTravelledText: '0.0 km',
    rideDurationText: '00:00',
    waitingTimeText: '00:00',
    statusText: '',
  );
}
