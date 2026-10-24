// Reuse existing Fluxidi catalogues; only the selected exact official address
// is resolved. Catalogue coordinates never become official address evidence.
import 'dart:convert';
import '../app_config.dart';
import '../events/event_data_source.dart';
import '../events/event_models.dart';
import '../hotels/hotel_data_source.dart';
import 'limousine_address_lookup.dart';
import 'limousine_event_lookup.dart';
import 'limousine_hotel_lookup.dart';
import 'limousine_transfer_endpoint.dart';

Future<LimousinePlaceSuggestion> resolveExactOfficialEndpoint(
  LimousinePlaceLookup addresses, String label, {String language = 'nl'}) async {
  String norm(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  final result = await addresses.search(label, language: language);
  final matches = result.suggestions.where((s) => s.officialAddress != null &&
    s.officialUsable && s.hasCoordinates && norm(s.label) == norm(label)).toList();
  if (result.hadError || matches.length != 1) {
    throw StateError('official_address_selection_required');
  }
  final verified = await addresses.verifySuggestion(matches.single);
  if (!verified.officialUsable || !verified.hasCoordinates ||
      jsonEncode(verified.officialAddress?.toJson()) != jsonEncode(matches.single.officialAddress?.toJson())) {
    throw StateError('official_address_changed');
  }
  return verified;
}

class FluxidiHotelEndpointLookup extends LimousineHotelLookup {
  FluxidiHotelEndpointLookup({required this.addresses,
    this.hotels = const RemoteHotelDataSource()}) : super(token: '');
  final LimousinePlaceLookup addresses;
  final HotelDataSource hotels;
  @override
  Future<LimousineHotelLookupResult> search(String rawQuery, {
    String language = 'nl', double? proximityLat, double? proximityLng}) async {
    if (rawQuery.trim().length < kLimousineHotelMinQueryLength) {
      return const LimousineHotelLookupResult();
    }
    try {
      final rows = await hotels.fetchStays(query: HotelStayQuery(
        searchText: rawQuery.trim(), source: 'approved-local'));
      return LimousineHotelLookupResult(suggestions: [
        for (final h in rows.where((h) => h.isRealApproved && h.address.trim().isNotEmpty && h.name.trim().isNotEmpty).take(kLimousineHotelMaxSuggestions))
          LimousineHotelSuggestion(name: h.name, formattedAddress: h.address,
            city: h.city, providerPlaceId: h.id, needsRetrieve: true),
      ]);
    } catch (_) { return const LimousineHotelLookupResult(hadError: true); }
  }
  @override
  Future<LimousineHotelSuggestion?> resolveSuggestion(LimousineHotelSuggestion suggestion) async {
    final s = suggestion;
    try {
      final a = await resolveExactOfficialEndpoint(addresses, s.formattedAddress);
      return LimousineHotelSuggestion(name: s.name, formattedAddress: a.label,
        latitude: a.lat, longitude: a.lon, providerPlaceId: s.providerPlaceId,
        city: a.locality, postcode: a.postcode, countryCode: a.country,
        officialAddress: a.officialAddress);
    } catch (_) { return null; }
  }
}

class FluxidiEventEndpointLookup extends LimousineEventLookup {
  FluxidiEventEndpointLookup({required this.addresses, EventDataSource? events}) :
    events = events ?? RemoteEventDataSource(baseUrl: appConfig.bookingBaseUrl,
      fallbackDataSource: const EmptyEventDataSource()), super(token: '');
  final LimousinePlaceLookup addresses;
  final EventDataSource events;
  @override
  Future<LimousineEventLookupResult> search(String rawQuery, {
    String language = 'nl', double? proximityLat, double? proximityLng}) async {
    if (rawQuery.trim().length < kLimousineEventMinQueryLength) {
      return const LimousineEventLookupResult();
    }
    try {
      final feed = await events.loadEventFeed(query: EventFeedQuery(
        searchQuery: rawQuery.trim(), locale: language, limit: kLimousineEventMaxSuggestions));
      if (feed.source == 'local_seed' || feed.source == 'empty') {
        return const LimousineEventLookupResult();
      }
      final seen = <String>{};
      return LimousineEventLookupResult(suggestions: [
        for (final e in feed.events.where((e) => e.address.trim().isNotEmpty &&
          e.locationName.trim().isNotEmpty && seen.add('${e.locationName}|${e.address}'))
            .take(kLimousineEventMaxSuggestions))
          LimousineEventVenueSuggestion(name: e.locationName, formattedAddress: e.address,
            city: e.city, providerPlaceId: e.id),
      ]);
    } catch (_) { return const LimousineEventLookupResult(hadError: true); }
  }
  @override
  Future<LimousineEventVenueSuggestion?> resolveSuggestion(LimousineEventVenueSuggestion suggestion) async {
    final s = suggestion;
    try {
      final a = await resolveExactOfficialEndpoint(addresses, s.formattedAddress);
      return LimousineEventVenueSuggestion(name: s.name, formattedAddress: a.label,
        latitude: a.lat, longitude: a.lon, providerPlaceId: s.providerPlaceId,
        city: a.locality, postcode: a.postcode, countryCode: a.country,
        officialAddress: a.officialAddress);
    } catch (_) { return null; }
  }
  @override
  Future<LimousineTransferEndpoint> resolveManual(String raw, {
    String language = 'nl', String eventName = ''}) async {
    try {
      final a = await resolveExactOfficialEndpoint(addresses, raw, language: language);
      return LimousineTransferEndpoint(kind: LimousineTransferEndpointKind.event,
        displayName: raw.trim(), formattedAddress: a.label, latitude: a.lat,
        longitude: a.lon, officialAddress: a.officialAddress,
        eventName: eventName, manual: true);
    } catch (_) { return limousineManualEventEndpoint(raw, eventName: eventName); }
  }
}
