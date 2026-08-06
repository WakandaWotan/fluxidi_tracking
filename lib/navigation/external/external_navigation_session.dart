// FLUXIDI-PIP-METER-EXTERNAL-NAV-1
//
// Explicit external navigation session state. Survives Activity/lifecycle
// restarts via a small JSON map. No tokens.

enum ExternalNavProvider { googleMaps }

enum ExternalNavPhase { toPickup, activeRide }

class ExternalNavigationDestinationPoint {
  const ExternalNavigationDestinationPoint({
    this.latitude,
    this.longitude,
    this.address,
  });

  final double? latitude;
  final double? longitude;
  final String? address;

  bool get hasCoordinates =>
      latitude != null &&
      longitude != null &&
      latitude!.isFinite &&
      longitude!.isFinite;

  bool get hasAddress => (address ?? '').trim().isNotEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
      };

  factory ExternalNavigationDestinationPoint.fromJson(Map<String, dynamic>? j) {
    if (j == null) {
      return const ExternalNavigationDestinationPoint();
    }
    return ExternalNavigationDestinationPoint(
      latitude: (j['latitude'] as num?)?.toDouble(),
      longitude: (j['longitude'] as num?)?.toDouble(),
      address: j['address'] as String?,
    );
  }
}

class ExternalNavigationSession {
  const ExternalNavigationSession({
    required this.provider,
    required this.bookingId,
    this.legId,
    required this.phase,
    required this.destination,
    required this.launchedAt,
    this.pipActive = false,
    this.nativeGuidanceSuppressed = true,
  });

  final ExternalNavProvider provider;
  final String bookingId;
  final String? legId;
  final ExternalNavPhase phase;
  final ExternalNavigationDestinationPoint destination;
  final DateTime launchedAt;
  final bool pipActive;
  final bool nativeGuidanceSuppressed;

  bool get isGoogleMaps => provider == ExternalNavProvider.googleMaps;

  ExternalNavigationSession copyWith({
    ExternalNavPhase? phase,
    ExternalNavigationDestinationPoint? destination,
    bool? pipActive,
    bool? nativeGuidanceSuppressed,
    String? legId,
    DateTime? launchedAt,
  }) {
    return ExternalNavigationSession(
      provider: provider,
      bookingId: bookingId,
      legId: legId ?? this.legId,
      phase: phase ?? this.phase,
      destination: destination ?? this.destination,
      launchedAt: launchedAt ?? this.launchedAt,
      pipActive: pipActive ?? this.pipActive,
      nativeGuidanceSuppressed:
          nativeGuidanceSuppressed ?? this.nativeGuidanceSuppressed,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'provider': provider.name,
        'bookingId': bookingId,
        'legId': legId,
        'phase': phase.name,
        'destination': destination.toJson(),
        'launchedAt': launchedAt.toIso8601String(),
        'pipActive': pipActive,
        'nativeGuidanceSuppressed': nativeGuidanceSuppressed,
      };

  factory ExternalNavigationSession.fromJson(Map<String, dynamic> j) {
    final providerName = (j['provider'] as String?) ?? 'googleMaps';
    final phaseName = (j['phase'] as String?) ?? 'toPickup';
    return ExternalNavigationSession(
      provider: ExternalNavProvider.values.firstWhere(
        (p) => p.name == providerName,
        orElse: () => ExternalNavProvider.googleMaps,
      ),
      bookingId: (j['bookingId'] as String?)?.trim() ?? '',
      legId: (j['legId'] as String?)?.trim(),
      phase: ExternalNavPhase.values.firstWhere(
        (p) => p.name == phaseName,
        orElse: () => ExternalNavPhase.toPickup,
      ),
      destination: ExternalNavigationDestinationPoint.fromJson(
        (j['destination'] as Map?)?.cast<String, dynamic>(),
      ),
      launchedAt: DateTime.tryParse((j['launchedAt'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      pipActive: j['pipActive'] == true,
      nativeGuidanceSuppressed: j['nativeGuidanceSuppressed'] != false,
    );
  }
}

/// Pure destination resolver for external Google Maps launches.
class ExternalNavDestinationResolver {
  /// Before START/NAV to customer: pickup A.
  /// After START: dropoff B (or active return-leg destination).
  static ExternalNavigationDestinationPoint resolve({
    required ExternalNavPhase phase,
    double? pickupLat,
    double? pickupLon,
    String? pickupAddress,
    double? dropoffLat,
    double? dropoffLon,
    String? dropoffAddress,
  }) {
    if (phase == ExternalNavPhase.toPickup) {
      if (pickupLat != null &&
          pickupLon != null &&
          pickupLat.isFinite &&
          pickupLon.isFinite) {
        return ExternalNavigationDestinationPoint(
          latitude: pickupLat,
          longitude: pickupLon,
          address: pickupAddress,
        );
      }
      return ExternalNavigationDestinationPoint(address: pickupAddress);
    }
    if (dropoffLat != null &&
        dropoffLon != null &&
        dropoffLat.isFinite &&
        dropoffLon.isFinite) {
      return ExternalNavigationDestinationPoint(
        latitude: dropoffLat,
        longitude: dropoffLon,
        address: dropoffAddress,
      );
    }
    return ExternalNavigationDestinationPoint(address: dropoffAddress);
  }
}

/// Whether Fluxidi native maneuver/voice guidance must stay suppressed.
bool shouldSuppressNativeGuidance(ExternalNavigationSession? session) {
  return session != null && session.nativeGuidanceSuppressed;
}
