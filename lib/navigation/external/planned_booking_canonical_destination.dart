// PLANNED-BOOKING-CANONICAL-GMAPS-HANDOFF-P0-6
//
// Canonical pickup/dropoff resolution for planned/customer bookings.
// Active operational leg wins over parent/quote package fields. Never mix
// pickup from parent with dropoff from leg. Lat/lng beat address fallback.
// Street rides must not use this resolver.

import '../nav_engine/active_navigation_target_snapshot.dart';

enum PlannedEndpointRole { pickup, dropoff }

enum PlannedEndpointCoordSource {
  activeLegCoords,
  parentFallbackCoords,
  addressOnly,
  none,
}

/// One endpoint (pickup or dropoff) from a planned booking / active leg.
class PlannedCanonicalEndpoint {
  const PlannedCanonicalEndpoint({
    required this.role,
    this.latitude,
    this.longitude,
    this.address,
    required this.coordSource,
    this.legId,
    this.parentBookingId,
  });

  final PlannedEndpointRole role;
  final double? latitude;
  final double? longitude;
  final String? address;
  final PlannedEndpointCoordSource coordSource;
  final String? legId;
  final String? parentBookingId;

  bool get hasCoordinates =>
      latitude != null &&
      longitude != null &&
      latitude!.isFinite &&
      longitude!.isFinite &&
      latitude!.abs() <= 90 &&
      longitude!.abs() <= 180 &&
      !(latitude == 0 && longitude == 0);

  bool get hasAddress {
    final a = (address ?? '').trim();
    if (a.isEmpty) return false;
    final lower = a.toLowerCase();
    return lower != 'null' && lower != 'undefined';
  }

  bool get isLaunchable => hasCoordinates || hasAddress;

  String get coordinateHash =>
      navigationTargetCoordinateHash(latitude, longitude);
}

class PlannedCanonicalEndpoints {
  const PlannedCanonicalEndpoints({
    required this.pickup,
    required this.dropoff,
    required this.bookingId,
    this.legId,
    this.parentBookingId,
    this.isOperationalLeg = false,
    this.lifecycleStatus,
  });

  final PlannedCanonicalEndpoint pickup;
  final PlannedCanonicalEndpoint dropoff;
  final String bookingId;
  final String? legId;
  final String? parentBookingId;
  final bool isOperationalLeg;
  final String? lifecycleStatus;

  PlannedCanonicalEndpoint endpointForPhase({required bool toPickup}) =>
      toPickup ? pickup : dropoff;
}

/// Pure planned-booking destination resolver (no I/O, no geocode).
class PlannedBookingCanonicalDestinationResolver {
  /// Leg-scoped latitude paths (active operational leg row).
  static const List<List<String>> _legPickupLat = [
    ['pickup_lat'],
    ['pickupLat'],
    ['from_lat'],
    ['fromLat'],
    ['pickup', 'lat'],
    ['from', 'lat'],
    ['origin', 'lat'],
    ['leg', 'pickup_lat'],
    ['leg', 'pickup', 'lat'],
    ['active_leg', 'pickup_lat'],
    ['active_leg', 'pickup', 'lat'],
    ['operational_leg', 'pickup_lat'],
    ['operational_leg', 'pickup', 'lat'],
  ];

  static const List<List<String>> _legPickupLon = [
    ['pickup_lon'],
    ['pickupLng'],
    ['pickupLon'],
    ['from_lon'],
    ['fromLng'],
    ['fromLon'],
    ['pickup', 'lon'],
    ['pickup', 'lng'],
    ['from', 'lon'],
    ['from', 'lng'],
    ['origin', 'lon'],
    ['origin', 'lng'],
    ['leg', 'pickup_lon'],
    ['leg', 'pickup', 'lon'],
    ['leg', 'pickup', 'lng'],
    ['active_leg', 'pickup_lon'],
    ['active_leg', 'pickup', 'lon'],
    ['operational_leg', 'pickup_lon'],
    ['operational_leg', 'pickup', 'lon'],
  ];

  static const List<List<String>> _legDropoffLat = [
    ['dropoff_lat'],
    ['dropoffLat'],
    ['to_lat'],
    ['toLat'],
    ['destination_lat'],
    ['destinationLat'],
    ['dropoff', 'lat'],
    ['to', 'lat'],
    ['destination', 'lat'],
    ['leg', 'dropoff_lat'],
    ['leg', 'dropoff', 'lat'],
    ['active_leg', 'dropoff_lat'],
    ['active_leg', 'dropoff', 'lat'],
    ['operational_leg', 'dropoff_lat'],
    ['operational_leg', 'dropoff', 'lat'],
  ];

  static const List<List<String>> _legDropoffLon = [
    ['dropoff_lon'],
    ['dropoffLng'],
    ['dropoffLon'],
    ['to_lon'],
    ['toLng'],
    ['toLon'],
    ['destination_lon'],
    ['destinationLng'],
    ['destinationLon'],
    ['dropoff', 'lon'],
    ['dropoff', 'lng'],
    ['to', 'lon'],
    ['to', 'lng'],
    ['destination', 'lon'],
    ['destination', 'lng'],
    ['leg', 'dropoff_lon'],
    ['leg', 'dropoff', 'lon'],
    ['leg', 'dropoff', 'lng'],
    ['active_leg', 'dropoff_lon'],
    ['active_leg', 'dropoff', 'lon'],
    ['operational_leg', 'dropoff_lon'],
    ['operational_leg', 'dropoff', 'lon'],
  ];

  /// Parent / package / quote paths — only when leg coords are absent.
  static const List<List<String>> _parentPickupLat = [
    ['record', 'booking', 'pickup_lat'],
    ['record', 'booking', 'pickup', 'lat'],
    ['record', 'booking_details', 'pickup_lat'],
    ['record', 'booking_details', 'pickup', 'lat'],
    ['payload', 'pickup_lat'],
    ['payload', 'pickup', 'lat'],
    ['quote', 'pickup', 'lat'],
    ['quote', 'origin', 'lat'],
    ['parent', 'pickup_lat'],
    ['parent', 'pickup', 'lat'],
    ['parent_booking', 'pickup_lat'],
    ['parent_booking', 'pickup', 'lat'],
  ];

  static const List<List<String>> _parentPickupLon = [
    ['record', 'booking', 'pickup_lon'],
    ['record', 'booking', 'pickup', 'lon'],
    ['record', 'booking', 'pickup', 'lng'],
    ['record', 'booking_details', 'pickup_lon'],
    ['record', 'booking_details', 'pickup', 'lon'],
    ['payload', 'pickup_lon'],
    ['payload', 'pickup', 'lon'],
    ['quote', 'pickup', 'lon'],
    ['quote', 'origin', 'lon'],
    ['parent', 'pickup_lon'],
    ['parent', 'pickup', 'lon'],
    ['parent_booking', 'pickup_lon'],
    ['parent_booking', 'pickup', 'lon'],
  ];

  static const List<List<String>> _parentDropoffLat = [
    ['record', 'booking', 'dropoff_lat'],
    ['record', 'booking', 'dropoff', 'lat'],
    ['record', 'booking_details', 'dropoff_lat'],
    ['record', 'booking_details', 'dropoff', 'lat'],
    ['payload', 'dropoff_lat'],
    ['payload', 'dropoff', 'lat'],
    ['quote', 'dropoff', 'lat'],
    ['quote', 'destination', 'lat'],
    ['parent', 'dropoff_lat'],
    ['parent', 'dropoff', 'lat'],
    ['parent_booking', 'dropoff_lat'],
    ['parent_booking', 'dropoff', 'lat'],
  ];

  static const List<List<String>> _parentDropoffLon = [
    ['record', 'booking', 'dropoff_lon'],
    ['record', 'booking', 'dropoff', 'lon'],
    ['record', 'booking', 'dropoff', 'lng'],
    ['record', 'booking_details', 'dropoff_lon'],
    ['record', 'booking_details', 'dropoff', 'lon'],
    ['payload', 'dropoff_lon'],
    ['payload', 'dropoff', 'lon'],
    ['quote', 'dropoff', 'lon'],
    ['quote', 'destination', 'lon'],
    ['parent', 'dropoff_lon'],
    ['parent', 'dropoff', 'lon'],
    ['parent_booking', 'dropoff_lon'],
    ['parent_booking', 'dropoff', 'lon'],
  ];

  static PlannedCanonicalEndpoints resolve({
    required String bookingId,
    required Map<String, dynamic> details,
    String? fromLabel,
    String? toLabel,
  }) {
    final legId = _str(details, const [
      ['leg_id'],
      ['legId'],
      ['active_leg_id'],
      ['activeLegId'],
    ]);
    final parentBookingId = _str(details, const [
      ['parent_booking_id'],
      ['parentBookingId'],
      ['parent_id'],
      ['parentId'],
    ]);
    final status = _str(details, const [
      ['status'],
      ['lifecycle_status'],
      ['lifecycleStatus'],
    ]);
    final isOp = _isOperationalLeg(details, legId);

    final pickupLeg = _point(details, _legPickupLat, _legPickupLon);
    final dropoffLeg = _point(details, _legDropoffLat, _legDropoffLon);

    // Never combine parent pickup with leg dropoff (or the reverse).
    PlannedCanonicalEndpoint pickup;
    PlannedCanonicalEndpoint dropoff;

    if (pickupLeg != null) {
      pickup = PlannedCanonicalEndpoint(
        role: PlannedEndpointRole.pickup,
        latitude: pickupLeg.$1,
        longitude: pickupLeg.$2,
        address: _usableAddress(fromLabel),
        coordSource: PlannedEndpointCoordSource.activeLegCoords,
        legId: legId,
        parentBookingId: parentBookingId,
      );
    } else {
      final parentPickup = _point(details, _parentPickupLat, _parentPickupLon);
      if (parentPickup != null) {
        pickup = PlannedCanonicalEndpoint(
          role: PlannedEndpointRole.pickup,
          latitude: parentPickup.$1,
          longitude: parentPickup.$2,
          address: _usableAddress(fromLabel),
          coordSource: PlannedEndpointCoordSource.parentFallbackCoords,
          legId: legId,
          parentBookingId: parentBookingId,
        );
      } else {
        pickup = PlannedCanonicalEndpoint(
          role: PlannedEndpointRole.pickup,
          address: _usableAddress(fromLabel),
          coordSource: _usableAddress(fromLabel) != null
              ? PlannedEndpointCoordSource.addressOnly
              : PlannedEndpointCoordSource.none,
          legId: legId,
          parentBookingId: parentBookingId,
        );
      }
    }

    if (dropoffLeg != null) {
      dropoff = PlannedCanonicalEndpoint(
        role: PlannedEndpointRole.dropoff,
        latitude: dropoffLeg.$1,
        longitude: dropoffLeg.$2,
        address: _usableAddress(toLabel),
        coordSource: PlannedEndpointCoordSource.activeLegCoords,
        legId: legId,
        parentBookingId: parentBookingId,
      );
    } else {
      final parentDrop = _point(details, _parentDropoffLat, _parentDropoffLon);
      if (parentDrop != null) {
        dropoff = PlannedCanonicalEndpoint(
          role: PlannedEndpointRole.dropoff,
          latitude: parentDrop.$1,
          longitude: parentDrop.$2,
          address: _usableAddress(toLabel),
          coordSource: PlannedEndpointCoordSource.parentFallbackCoords,
          legId: legId,
          parentBookingId: parentBookingId,
        );
      } else {
        dropoff = PlannedCanonicalEndpoint(
          role: PlannedEndpointRole.dropoff,
          address: _usableAddress(toLabel),
          coordSource: _usableAddress(toLabel) != null
              ? PlannedEndpointCoordSource.addressOnly
              : PlannedEndpointCoordSource.none,
          legId: legId,
          parentBookingId: parentBookingId,
        );
      }
    }

    return PlannedCanonicalEndpoints(
      pickup: pickup,
      dropoff: dropoff,
      bookingId: bookingId.trim(),
      legId: legId,
      parentBookingId: parentBookingId,
      isOperationalLeg: isOp,
      lifecycleStatus: status,
    );
  }

  /// Compact PII-safe audit line for street-vs-planned differential logs.
  static String auditLine({
    required PlannedCanonicalEndpoints endpoints,
    required bool toPickup,
    required String rideKind, // street | planned
    String? activePhase,
    String? externalSessionToken,
  }) {
    final ep = endpoints.endpointForPhase(toPickup: toPickup);
    final qKind = ep.hasCoordinates
        ? 'coords'
        : (ep.hasAddress ? 'address' : 'none');
    return 'ride_kind=$rideKind '
        'booking=${navigationBookingIdLogToken(endpoints.bookingId)} '
        'leg=${(endpoints.legId ?? '-').trim().isEmpty ? '-' : endpoints.legId} '
        'parent=${navigationBookingIdLogToken(endpoints.parentBookingId)} '
        'op_leg=${endpoints.isOperationalLeg} '
        'status=${endpoints.lifecycleStatus ?? '-'} '
        'phase=${activePhase ?? '-'} '
        'role=${ep.role.name} '
        'coord_src=${ep.coordSource.name} '
        'q_kind=$qKind '
        'target_hash=${ep.coordinateHash} '
        'addr_present=${ep.hasAddress} '
        'session=${externalSessionToken ?? '-'}';
  }

  static bool _isOperationalLeg(Map<String, dynamic> d, String? legId) {
    final flag = d['is_operational_leg'] ?? d['isOperationalLeg'];
    if (flag == true) return true;
    if (flag is String) {
      final s = flag.trim().toLowerCase();
      if (s == 'true' || s == '1') return true;
    }
    return (legId ?? '').trim().isNotEmpty;
  }

  static String? _usableAddress(String? raw) {
    final a = (raw ?? '').trim();
    if (a.isEmpty) return null;
    final lower = a.toLowerCase();
    if (lower == 'null' || lower == 'undefined') return null;
    return a;
  }

  static String? _str(Map<String, dynamic> d, List<List<String>> paths) {
    for (final path in paths) {
      final v = _getNested(d, path);
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty && s.toLowerCase() != 'null') return s;
    }
    return null;
  }

  static (double, double)? _point(
    Map<String, dynamic> d,
    List<List<String>> latPaths,
    List<List<String>> lonPaths,
  ) {
    num? lat;
    num? lon;
    for (final path in latPaths) {
      final v = _asNum(_getNested(d, path));
      if (v != null) {
        lat = v;
        break;
      }
    }
    for (final path in lonPaths) {
      final v = _asNum(_getNested(d, path));
      if (v != null) {
        lon = v;
        break;
      }
    }
    if (lat == null || lon == null) return null;
    final la = lat.toDouble();
    final lo = lon.toDouble();
    if (!la.isFinite || !lo.isFinite) return null;
    if (la.abs() > 90 || lo.abs() > 180) return null;
    if (la == 0 && lo == 0) return null;
    return (la, lo);
  }

  static num? _asNum(dynamic raw) {
    if (raw is num) return raw;
    if (raw is String) return num.tryParse(raw.trim().replaceAll(',', '.'));
    return null;
  }

  static dynamic _getNested(Map<String, dynamic> root, List<String> path) {
    dynamic cur = root;
    for (final key in path) {
      if (cur is! Map) return null;
      cur = cur[key];
    }
    return cur;
  }
}

/// Street-ride destination contract — kept separate so planned fixes cannot
/// alter street launch semantics.
class StreetRideGmapsDestinationContract {
  const StreetRideGmapsDestinationContract({
    required this.latitude,
    required this.longitude,
    required this.address,
    this.destinationSource = 'street_direct_destination',
  });

  final double? latitude;
  final double? longitude;
  final String? address;
  final String destinationSource;

  bool get hasCoordinates =>
      latitude != null &&
      longitude != null &&
      latitude!.isFinite &&
      longitude!.isFinite;

  /// Semantic fingerprint used by street regression tests.
  String get contractFingerprint {
    final lat = hasCoordinates ? latitude!.toStringAsFixed(6) : '-';
    final lng = hasCoordinates ? longitude!.toStringAsFixed(6) : '-';
    final addr = (address ?? '').trim();
    return 'src=$destinationSource|lat=$lat|lng=$lng|addr_len=${addr.length}';
  }
}
