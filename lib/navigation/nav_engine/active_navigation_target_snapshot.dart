// NAVIGATION-SINGLE-ACTIVE-TARGET-TRUTH-P0-5
//
// One immutable active navigation target shared by route request, polyline,
// maneuvers, remaining distance, ETA, arrival, destination banner, Google Maps
// and PiP. No component may independently re-derive pickup vs dropoff.

import 'dart:convert';

/// Product navigation phase for the active target.
enum ActiveNavigationPhase {
  toPickup,
  passengerLeg,
  returnLeg,
}

/// Destination role of the active target.
enum NavigationDestinationKind {
  pickup,
  dropoff,
  returnDestination,
}

/// Immutable canonical navigation target for one leg.
class ActiveNavigationTargetSnapshot {
  const ActiveNavigationTargetSnapshot({
    required this.snapshotId,
    required this.bookingId,
    this.legId,
    required this.navigationPhase,
    required this.destinationKind,
    this.targetLat,
    this.targetLng,
    this.targetAddress,
    this.routeId,
    required this.createdAt,
  });

  final String snapshotId;
  final String bookingId;
  final String? legId;
  final ActiveNavigationPhase navigationPhase;
  final NavigationDestinationKind destinationKind;
  final double? targetLat;
  final double? targetLng;
  final String? targetAddress;
  final String? routeId;
  final DateTime createdAt;

  bool get hasCoordinates =>
      targetLat != null &&
      targetLng != null &&
      targetLat!.isFinite &&
      targetLng!.isFinite &&
      targetLat! >= -90.0 &&
      targetLat! <= 90.0 &&
      targetLng! >= -180.0 &&
      targetLng! <= 180.0;

  bool get isValid =>
      snapshotId.trim().isNotEmpty &&
      bookingId.trim().isNotEmpty &&
      (hasCoordinates ||
          ((targetAddress ?? '').trim().isNotEmpty &&
              (targetAddress ?? '').trim().toLowerCase() != 'null'));

  /// Stable, PII-safe coordinate fingerprint (rounded, short hex).
  String get targetCoordinateHash =>
      navigationTargetCoordinateHash(targetLat, targetLng);

  ActiveNavigationTargetSnapshot copyWith({
    String? routeId,
    double? targetLat,
    double? targetLng,
    String? targetAddress,
    String? legId,
  }) {
    return ActiveNavigationTargetSnapshot(
      snapshotId: snapshotId,
      bookingId: bookingId,
      legId: legId ?? this.legId,
      navigationPhase: navigationPhase,
      destinationKind: destinationKind,
      targetLat: targetLat ?? this.targetLat,
      targetLng: targetLng ?? this.targetLng,
      targetAddress: targetAddress ?? this.targetAddress,
      routeId: routeId ?? this.routeId,
      createdAt: createdAt,
    );
  }
}

/// Owns the single active target. Install replaces; never mutates in place.
class ActiveNavigationTargetOwner {
  ActiveNavigationTargetSnapshot? _current;
  ActiveNavigationTargetSnapshot? _previous;

  ActiveNavigationTargetSnapshot? get current => _current;
  ActiveNavigationTargetSnapshot? get previous => _previous;

  ActiveNavigationTargetSnapshot install(
    ActiveNavigationTargetSnapshot next,
  ) {
    _previous = _current;
    _current = next;
    return next;
  }

  /// Atomically end the previous leg and install a fresh snapshot.
  ActiveNavigationTargetSnapshot replaceForPhaseTransition(
    ActiveNavigationTargetSnapshot next,
  ) {
    return install(next);
  }

  /// Bind route geometry to the current snapshot without changing snapshotId.
  ActiveNavigationTargetSnapshot? bindRoute({
    required String routeId,
    double? targetLat,
    double? targetLng,
  }) {
    final cur = _current;
    if (cur == null) return null;
    _current = cur.copyWith(
      routeId: routeId,
      targetLat: targetLat,
      targetLng: targetLng,
    );
    return _current;
  }

  void clear() {
    _previous = _current;
    _current = null;
  }

  bool get hasActiveTarget => _current != null && _current!.isValid;
}

int _snapshotSeq = 0;

/// Builds a new immutable snapshot. [snapshotId] is unique per install.
ActiveNavigationTargetSnapshot buildActiveNavigationTargetSnapshot({
  required String bookingId,
  String? legId,
  required ActiveNavigationPhase navigationPhase,
  required NavigationDestinationKind destinationKind,
  double? targetLat,
  double? targetLng,
  String? targetAddress,
  String? routeId,
  DateTime? createdAt,
  String? snapshotId,
}) {
  _snapshotSeq += 1;
  final id = (snapshotId ?? '').trim().isNotEmpty
      ? snapshotId!.trim()
      : 'ants_${createdAt?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch}_$_snapshotSeq';
  return ActiveNavigationTargetSnapshot(
    snapshotId: id,
    bookingId: bookingId.trim(),
    legId: (legId ?? '').trim().isEmpty ? null : legId!.trim(),
    navigationPhase: navigationPhase,
    destinationKind: destinationKind,
    targetLat: targetLat,
    targetLng: targetLng,
    targetAddress: (targetAddress ?? '').trim().isEmpty
        ? null
        : targetAddress!.trim(),
    routeId: (routeId ?? '').trim().isEmpty ? null : routeId!.trim(),
    createdAt: createdAt ?? DateTime.now().toUtc(),
  );
}

/// Short booking id for logs (never full PII).
String navigationBookingIdLogToken(String? bookingId) {
  final raw = (bookingId ?? '').trim();
  if (raw.isEmpty) return '-';
  if (raw.length <= 8) return raw;
  final head = raw.substring(0, 4);
  final tail = raw.substring(raw.length - 4);
  return '$head…$tail';
}

/// Rounded lat/lng fingerprint for cross-component equality checks.
String navigationTargetCoordinateHash(double? lat, double? lng) {
  if (lat == null ||
      lng == null ||
      !lat.isFinite ||
      !lng.isFinite) {
    return 'none';
  }
  final key =
      '${lat.toStringAsFixed(5)},${lng.toStringAsFixed(5)}';
  // FNV-1a 32-bit — stable, short, non-cryptographic.
  var hash = 0x811c9dc5;
  for (final unit in utf8.encode(key)) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

NavigationDestinationKind destinationKindForPhase(
  ActiveNavigationPhase phase,
) {
  switch (phase) {
    case ActiveNavigationPhase.toPickup:
      return NavigationDestinationKind.pickup;
    case ActiveNavigationPhase.passengerLeg:
      return NavigationDestinationKind.dropoff;
    case ActiveNavigationPhase.returnLeg:
      return NavigationDestinationKind.returnDestination;
  }
}
