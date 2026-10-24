// COMPANY-AGENDA-P0 — one resolver for booking-detail and planner maps.

import 'package:fluxidi_tracking/company/company_plan_quote.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';

class CompanyBookingRouteEndpoints {
  const CompanyBookingRouteEndpoints({
    required this.pickup,
    required this.dropoff,
    this.polyline = '',
    this.missingReason = '',
  });

  final LimousineAddressValue pickup;
  final LimousineAddressValue dropoff;
  final String polyline;
  final String missingReason;

  bool get hasCoordinates =>
      _hasCoord(pickup.lat, pickup.lon) && _hasCoord(dropoff.lat, dropoff.lon);

  bool get hasPolyline => polyline.trim().isNotEmpty;

  bool get hasAddressText =>
      pickup.displayText.trim().isNotEmpty &&
      dropoff.displayText.trim().isNotEmpty;

  bool get canDrawRoute => hasCoordinates || hasPolyline;
}

bool _hasCoord(double? lat, double? lon) {
  return lat != null && lon != null && lat.isFinite && lon.isFinite;
}

double? companyBookingCoord(Object? raw) {
  if (raw is num && raw.isFinite) return raw.toDouble();
  if (raw is String) {
    final parsed = num.tryParse(raw.trim())?.toDouble();
    if (parsed != null && parsed.isFinite) return parsed;
  }
  return null;
}

Object? companyBookingNestedValue(Map<String, dynamic> source, List<String> keys) {
  for (final key in keys) {
    if (source[key] != null) return source[key];
  }
  return null;
}

Map<String, dynamic> companyBookingFlatten(Map<String, dynamic> row) {
  final out = Map<String, dynamic>.from(row);
  void merge(Object? nested) {
    if (nested is Map) {
      final map = Map<String, dynamic>.from(nested);
      map.forEach((key, value) {
        if (value != null && (out[key] == null || out[key].toString().isEmpty)) {
          out[key] = value;
        }
      });
    }
  }

  merge(row['record']);
  merge(row['booking']);
  merge(row['quote']);
  merge(row['inputs']);
  final record = row['record'] is Map
      ? Map<String, dynamic>.from(row['record'] as Map)
      : out;
  merge(record['booking']);
  merge(record['quote']);
  merge(record['inputs']);
  final legs = record['operational_legs'] ??
      record['operationalLegs'] ??
      out['operational_legs'] ??
      out['operationalLegs'];
  if (legs is List && legs.isNotEmpty && legs.first is Map) {
    merge(legs.first);
  }
  return out;
}

LimousineAddressValue companyBookingAddressValue({
  required String text,
  double? lat,
  double? lon,
}) {
  final display = text.trim();
  final hasCoords = _hasCoord(lat, lon);
  return LimousineAddressValue(
    displayText: display,
    canonicalLabel: display,
    lat: hasCoords ? lat : null,
    lon: hasCoords ? lon : null,
    acceptance: display.isEmpty
        ? LimousineAddressAcceptance.empty
        : (hasCoords
            ? LimousineAddressAcceptance.selected
            : LimousineAddressAcceptance.manualFallback),
  );
}

CompanyBookingRouteEndpoints resolveCompanyBookingRouteEndpoints({
  required Map<String, dynamic> row,
  Map<String, dynamic>? openedLeg,
  CompanyPlanQuoteResult? quote,
  String fromText = '',
  String toText = '',
}) {
  final flat = companyBookingFlatten(row);
  final leg = openedLeg == null
      ? const <String, dynamic>{}
      : Map<String, dynamic>.from(openedLeg);

  double? firstCoord(List<String> keys) {
    for (final key in keys) {
      final value = companyBookingCoord(leg[key]) ??
          companyBookingCoord(flat[key]) ??
          companyBookingCoord(row[key]);
      if (value != null) return value;
    }
    return null;
  }

  String firstText(List<String> keys, String fallback) {
    for (final key in keys) {
      final value = (leg[key] ?? flat[key] ?? row[key])?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return fallback.trim();
  }

  double? nestedCoord(List<String> objectKeys, List<String> coordKeys) {
    for (final objectKey in objectKeys) {
      final nested = leg[objectKey] ?? flat[objectKey] ?? row[objectKey];
      if (nested is! Map) continue;
      final map = Map<String, dynamic>.from(nested);
      for (final key in coordKeys) {
        final value = companyBookingCoord(map[key]);
        if (value != null) return value;
      }
    }
    return null;
  }

  final pickupLat = quote?.pickupLat ??
      firstCoord(const [
        'pickup_lat',
        'from_lat',
        'pickupLat',
        'fromLat',
        'origin_lat',
        'pickup_latitude',
      ]) ??
      nestedCoord(const ['pickup', 'from', 'origin'], const [
        'lat',
        'latitude',
        'pickup_lat',
      ]);
  final pickupLon = quote?.pickupLon ??
      firstCoord(const [
        'pickup_lon',
        'pickup_lng',
        'from_lng',
        'from_lon',
        'pickupLon',
        'pickupLng',
        'fromLng',
        'origin_lon',
        'origin_lng',
        'pickup_longitude',
      ]) ??
      nestedCoord(const ['pickup', 'from', 'origin'], const [
        'lon',
        'lng',
        'longitude',
        'pickup_lon',
      ]);
  final dropoffLat = quote?.dropoffLat ??
      firstCoord(const [
        'dropoff_lat',
        'to_lat',
        'dropoffLat',
        'toLat',
        'destination_lat',
        'dropoff_latitude',
      ]) ??
      nestedCoord(const ['dropoff', 'to', 'destination'], const [
        'lat',
        'latitude',
        'dropoff_lat',
      ]);
  final dropoffLon = quote?.dropoffLon ??
      firstCoord(const [
        'dropoff_lon',
        'dropoff_lng',
        'to_lng',
        'to_lon',
        'dropoffLon',
        'dropoffLng',
        'toLng',
        'destination_lon',
        'destination_lng',
        'dropoff_longitude',
      ]) ??
      nestedCoord(const ['dropoff', 'to', 'destination'], const [
        'lon',
        'lng',
        'longitude',
        'dropoff_lon',
      ]);
  final polyline = firstText(const [
    'route_polyline',
    'polyline',
    'geometry',
    'mapbox_polyline',
  ], '');
  final pickupText = firstText(const ['from', 'pickup'], fromText);
  final dropoffText = firstText(const ['to', 'dropoff'], toText);
  final pickup = companyBookingAddressValue(
    text: pickupText,
    lat: pickupLat,
    lon: pickupLon,
  );
  final dropoff = companyBookingAddressValue(
    text: dropoffText,
    lat: dropoffLat,
    lon: dropoffLon,
  );
  var reason = '';
  if (!_hasCoord(pickupLat, pickupLon) && !_hasCoord(dropoffLat, dropoffLon)) {
    reason = 'missing_booking_and_quote_coordinates';
  } else if (!_hasCoord(pickupLat, pickupLon)) {
    reason = 'missing_pickup_coordinates';
  } else if (!_hasCoord(dropoffLat, dropoffLon)) {
    reason = 'missing_dropoff_coordinates';
  }
  return CompanyBookingRouteEndpoints(
    pickup: pickup,
    dropoff: dropoff,
    polyline: polyline,
    missingReason: reason,
  );
}
