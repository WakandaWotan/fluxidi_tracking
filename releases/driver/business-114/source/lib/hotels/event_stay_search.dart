import 'dart:math' as math;

import '../company/company_timezone.dart';
import '../events/event_models.dart';
import 'hotel_model.dart';
import 'stay22_europe_countries.dart';
import 'stay22_search.dart';

/// Nearby radius for an event-centred Google Places search.
///
/// The public hotels route uses Places Nearby Search when these coordinates
/// are present, including photo names when Google returns them. The general
/// hotels page keeps Text Search. Stay22 still receives the coordinates on
/// the booking link.
const double kEventStayNearbyRadiusKm = 15;

enum EventStayCenterKind { coordinates, address, city, unavailable }

/// Search centre for hotels opened from one event.
///
/// Coordinates win. The venue address, then the city, are explicit fallbacks.
/// The venue name is a label, not the hotel filter.
class EventStaySearch {
  const EventStaySearch({
    required this.eventId,
    required this.venueLabel,
    required this.centerKind,
    required this.address,
    required this.city,
    required this.stay22Address,
    this.countryCode,
    this.latitude,
    this.longitude,
    this.arrivalDate,
    this.timeZone,
  });

  factory EventStaySearch.fromEvent(EventDetailData event) {
    final city = event.city.trim();
    final street = event.address.trim();
    final location = event.locationName.trim();
    final title = event.title.trim();
    final venue = location.isNotEmpty
        ? location
        : (city.isNotEmpty ? city : title);
    final countryCode = (event.countryCode ?? '').trim().toUpperCase();
    final hasCoordinates = stay22HasVerifiedCoordinates(event.lat, event.lng);
    final EventStayCenterKind kind;
    if (hasCoordinates) {
      kind = EventStayCenterKind.coordinates;
    } else if (street.isNotEmpty) {
      kind = EventStayCenterKind.address;
    } else if (city.isNotEmpty) {
      kind = EventStayCenterKind.city;
    } else {
      kind = EventStayCenterKind.unavailable;
    }
    final countryName = countryCode.isEmpty
        ? ''
        : (stay22EnglishCountryName(countryCode) ?? '');
    final stay22Address = _stayAddress(
      street: street,
      city: city,
      countryName: countryName,
      latitude: hasCoordinates ? event.lat : null,
      longitude: hasCoordinates ? event.lng : null,
    );
    final zone = (event.timeZone ?? '').trim();
    return EventStaySearch(
      eventId: event.id,
      venueLabel: venue,
      centerKind: kind,
      address: street,
      city: city,
      countryCode: countryCode.isEmpty ? null : countryCode,
      latitude: hasCoordinates ? event.lat : null,
      longitude: hasCoordinates ? event.lng : null,
      stay22Address: stay22Address,
      arrivalDate: eventStayArrivalDate(event.startAtUtc, timeZone: zone),
      timeZone: zone.isEmpty ? null : zone,
    );
  }

  final String eventId;
  final String venueLabel;
  final EventStayCenterKind centerKind;
  final String address;
  final String city;
  final String? countryCode;
  final double? latitude;
  final double? longitude;
  final String stay22Address;
  final DateTime? arrivalDate;
  final String? timeZone;

  bool get hasCoordinates => centerKind == EventStayCenterKind.coordinates;

  DateTime? get departureDate {
    final arrival = arrivalDate;
    if (arrival == null) return null;
    final day = DateTime(arrival.year, arrival.month, arrival.day);
    return day.add(const Duration(days: 1));
  }

  String? get checkinYmd =>
      arrivalDate == null ? null : stay22Ymd(arrivalDate!);

  String? get checkoutYmd =>
      departureDate == null ? null : stay22Ymd(departureDate!);
}

/// Calendar day of [startAtUtc] in the event zone.
///
/// An empty zone uses Europe/Brussels. A named zone that this app cannot
/// resolve uses the device offset from the company timezone helper.
DateTime? eventStayArrivalDate(DateTime? startAtUtc, {String? timeZone}) {
  if (startAtUtc == null) return null;
  final zone = (timeZone ?? '').trim();
  final resolved = zone.isEmpty ? kCompanyDefaultTimezone : zone;
  final wall = companyTimezoneUtcToLocal(startAtUtc.toUtc(), resolved);
  return DateTime(wall.year, wall.month, wall.day);
}

/// Event coordinates stay on the live search until the destination text changes.
bool eventStayCoordinatesStillApply({
  required EventStaySearch search,
  required String destinationText,
}) {
  if (!search.hasCoordinates) return false;
  final destination = destinationText.trim();
  if (destination.isEmpty) return true;
  return destination == search.stay22Address.trim();
}

double eventStayDistanceKm({
  required double fromLatitude,
  required double fromLongitude,
  required double toLatitude,
  required double toLongitude,
}) {
  const earthKm = 6371.0;
  double radians(double degrees) => degrees * math.pi / 180.0;
  final dLat = radians(toLatitude - fromLatitude);
  final dLng = radians(toLongitude - fromLongitude);
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(radians(fromLatitude)) *
          math.cos(radians(toLatitude)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return earthKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

String formatEventStayDistanceKm(double kilometers) {
  if (!kilometers.isFinite || kilometers < 0) return '';
  if (kilometers < 1) return '${(kilometers * 1000).round()} m';
  final rounded = (kilometers * 10).round() / 10;
  return '${rounded.toStringAsFixed(1)} km';
}

double? hotelStayDistanceKmFrom({
  required HotelStay stay,
  required double latitude,
  required double longitude,
}) {
  final lat = stay.latitude ?? stay.lat;
  final lng = stay.longitude ?? stay.lng;
  if (!stay22HasVerifiedCoordinates(lat, lng)) return null;
  return eventStayDistanceKm(
    fromLatitude: latitude,
    fromLongitude: longitude,
    toLatitude: lat,
    toLongitude: lng,
  );
}

/// Stays with coordinates come first, nearest first. The rest keep their order.
List<HotelStay> sortHotelStaysByEventDistance({
  required List<HotelStay> stays,
  required double latitude,
  required double longitude,
}) {
  final indexed = stays.asMap().entries.toList(growable: false);
  indexed.sort((a, b) {
    final left = hotelStayDistanceKmFrom(
      stay: a.value,
      latitude: latitude,
      longitude: longitude,
    );
    final right = hotelStayDistanceKmFrom(
      stay: b.value,
      latitude: latitude,
      longitude: longitude,
    );
    if (left == null && right == null) return a.key.compareTo(b.key);
    if (left == null) return 1;
    if (right == null) return -1;
    final byDistance = left.compareTo(right);
    if (byDistance != 0) return byDistance;
    return a.key.compareTo(b.key);
  });
  return indexed.map((entry) => entry.value).toList(growable: false);
}

String _stayAddress({
  required String street,
  required String city,
  required String countryName,
  required double? latitude,
  required double? longitude,
}) {
  if (street.isNotEmpty || city.isNotEmpty) {
    return composeStay22Address(
      freeText: street,
      city: city,
      country: countryName,
    );
  }
  if (stay22HasVerifiedCoordinates(latitude, longitude)) {
    return '${latitude!.toStringAsFixed(5)}, ${longitude!.toStringAsFixed(5)}';
  }
  return '';
}
