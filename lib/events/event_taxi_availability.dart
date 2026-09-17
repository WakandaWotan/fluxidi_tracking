import 'dart:convert';

import 'package:http/http.dart' as http;

import 'event_markets.dart';
import 'event_models.dart';

class EventTaxiDestination {
  const EventTaxiDestination({required this.text, this.lat, this.lng});

  final String text;
  final double? lat;
  final double? lng;
}

class EventTaxiAvailability {
  const EventTaxiAvailability({
    required this.bookableCount,
    required this.checked,
  });

  final int bookableCount;
  final bool checked;

  bool get hasBookable => bookableCount > 0;
}

EventTaxiDestination eventTaxiDestination(EventDetailData event) {
  final String text = event.address.trim().isNotEmpty
      ? event.address.trim()
      : (event.locationName.trim().isNotEmpty
            ? event.locationName.trim()
            : event.title.trim());
  final double lat = event.lat;
  final double lng = event.lng;
  final bool usable =
      lat.isFinite &&
      lng.isFinite &&
      !(lat.abs() < 0.01 && lng.abs() < 0.01) &&
      lat >= -90 &&
      lat <= 90 &&
      lng >= -180 &&
      lng <= 180;
  return EventTaxiDestination(
    text: text,
    lat: usable ? lat : null,
    lng: usable ? lng : null,
  );
}

bool isBookableEventPartner(Map<String, dynamic> partner) {
  final dynamic bookable = partner['bookable'];
  if (bookable == false || bookable == 'false') return false;
  if (bookable == true || bookable == 'true') return true;
  final String status = '${partner['availability_status'] ?? partner['availabilityStatus'] ?? ''}'
      .trim()
      .toLowerCase();
  if (status == 'inactive') return false;
  if (status == 'active') return true;
  return partner['is_active'] == true || partner['isActive'] == true;
}

Future<EventTaxiAvailability> checkEventTaxiAvailability({
  required String baseUrl,
  required EventTaxiDestination destination,
  double radiusKm = 50,
}) async {
  if (destination.lat == null || destination.lng == null) {
    return const EventTaxiAvailability(bookableCount: 0, checked: false);
  }
  final Uri uri = Uri.parse('$baseUrl/partners/nearby').replace(
    queryParameters: <String, String>{
      'lat': destination.lat!.toStringAsFixed(6),
      'lng': destination.lng!.toStringAsFixed(6),
      'radius_km': radiusKm.round().toString(),
    },
  );
  try {
    final http.Response res = await http.get(uri).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      return const EventTaxiAvailability(bookableCount: 0, checked: false);
    }
    final dynamic decoded = jsonDecode(res.body);
    final List<Map<String, dynamic>> partners =
        decoded is Map<String, dynamic> && decoded['partners'] is List
        ? (decoded['partners'] as List)
              .whereType<Map<String, dynamic>>()
              .toList()
        : <Map<String, dynamic>>[];
    final int bookable = partners.where(isBookableEventPartner).length;
    return EventTaxiAvailability(bookableCount: bookable, checked: true);
  } catch (_) {
    return const EventTaxiAvailability(bookableCount: 0, checked: false);
  }
}

String eventTaxiAvailabilityMessage(
  EventTaxiAvailability availability, [
  String language = 'nl',
]) {
  if (!availability.hasBookable) {
    return fluxidiEventNoCarriersLabel(language);
  }
  final String lang = language.trim().toLowerCase();
  final int count = availability.bookableCount;
  switch (lang) {
    case 'fr':
      return count == 1
          ? '1 entreprise de taxi trouvée. Choisissez-la pour continuer.'
          : '$count entreprises de taxi trouvées. Choisissez-en une pour continuer.';
    case 'en':
      return count == 1
          ? '1 taxi company found. Choose it to continue.'
          : '$count taxi companies found. Choose one to continue.';
    case 'de':
      return count == 1
          ? '1 Taxiunternehmen gefunden. Wählen Sie es aus, um fortzufahren.'
          : '$count Taxiunternehmen gefunden. Wählen Sie eines aus, um fortzufahren.';
    case 'es':
      return count == 1
          ? '1 empresa de taxi encontrada. Elígela para continuar.'
          : '$count empresas de taxi encontradas. Elige una para continuar.';
    default:
      return count == 1
          ? '1 taxibedrijf gevonden. Kies het om verder te gaan.'
          : '$count taxibedrijven gevonden. Kies een bedrijf om verder te gaan.';
  }
}
