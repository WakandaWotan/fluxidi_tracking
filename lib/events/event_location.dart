import 'dart:math' as math;

import 'event_models.dart';

const double kEventLocationConflictKm = 5;

class EventTaxiDestination {
  const EventTaxiDestination({
    required this.text,
    this.lat,
    this.lng,
    this.conflict = false,
    this.distanceKm,
    this.city = '',
    this.countryCode = '',
  });

  final String text;
  final double? lat;
  final double? lng;
  final bool conflict;
  final double? distanceKm;
  final String city;
  final String countryCode;

  bool get useCoordinates =>
      !conflict && lat != null && lng != null && lat!.isFinite && lng!.isFinite;
}

String eventFullAddress(EventDetailData event) {
  final parts = <String>[];
  final address = event.address.trim();
  final location = event.locationName.trim();
  final city = event.city.trim();
  final country = (event.countryCode ?? '').trim().toUpperCase();
  if (address.isNotEmpty) parts.add(address);
  if (location.isNotEmpty && !address.toLowerCase().contains(location.toLowerCase())) {
    parts.add(location);
  }
  if (city.isNotEmpty && !parts.join(' ').toLowerCase().contains(city.toLowerCase())) {
    parts.add(city);
  }
  if (country.isNotEmpty && !parts.join(' ').toUpperCase().contains(country)) {
    parts.add(country);
  }
  if (parts.isEmpty) return event.title.trim();
  return parts.join(', ');
}

double eventHaversineKm(double lat1, double lng1, double lat2, double lng2) {
  const earthKm = 6371.0;
  final dLat = _toRad(lat2 - lat1);
  final dLng = _toRad(lng2 - lng1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_toRad(lat1)) *
          math.cos(_toRad(lat2)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return earthKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

EventTaxiDestination resolveEventTaxiDestination(
  EventDetailData event, {
  double? geocodedLat,
  double? geocodedLng,
}) {
  final text = eventFullAddress(event);
  final eventLat = event.lat;
  final eventLng = event.lng;
  final hasEvent = eventLat.isFinite && eventLng.isFinite;
  final hasGeo = geocodedLat != null &&
      geocodedLng != null &&
      geocodedLat.isFinite &&
      geocodedLng.isFinite;
  if (hasEvent && hasGeo) {
    final km = eventHaversineKm(eventLat, eventLng, geocodedLat, geocodedLng);
    if (km > kEventLocationConflictKm) {
      return EventTaxiDestination(
        text: text,
        lat: geocodedLat,
        lng: geocodedLng,
        conflict: true,
        distanceKm: km,
        city: event.city,
        countryCode: event.countryCode ?? '',
      );
    }
    return EventTaxiDestination(
      text: text,
      lat: geocodedLat,
      lng: geocodedLng,
      city: event.city,
      countryCode: event.countryCode ?? '',
    );
  }
  if (hasGeo) {
    return EventTaxiDestination(
      text: text,
      lat: geocodedLat,
      lng: geocodedLng,
      city: event.city,
      countryCode: event.countryCode ?? '',
    );
  }
  if (hasEvent) {
    return EventTaxiDestination(
      text: text,
      lat: eventLat,
      lng: eventLng,
      city: event.city,
      countryCode: event.countryCode ?? '',
    );
  }
  return EventTaxiDestination(
    text: text,
    conflict: true,
    city: event.city,
    countryCode: event.countryCode ?? '',
  );
}

double _toRad(double deg) => deg * math.pi / 180;
