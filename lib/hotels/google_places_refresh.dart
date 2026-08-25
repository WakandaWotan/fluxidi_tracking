import 'hotel_data_source.dart';
import 'hotel_model.dart';
import 'stay22_europe_countries.dart';

/// Latest-query-wins gate for native Google Places discovery.
class GooglePlacesRefreshGate {
  int _generation = 0;
  String? _inflightKey;
  String? appliedKey;

  int get generation => _generation;

  bool shouldStart(String key) {
    if (key.isEmpty) return false;
    return key != appliedKey && key != _inflightKey;
  }

  int start(String key) {
    _inflightKey = key;
    _generation += 1;
    return _generation;
  }

  /// Drop any in-flight generation immediately when the user changes query.
  void invalidate() {
    _generation += 1;
    _inflightKey = null;
  }

  bool shouldApply(int generation) => generation == _generation;

  void complete({required int generation, required String key}) {
    if (generation != _generation) return;
    appliedKey = key;
    _inflightKey = null;
  }

  void fail(int generation) {
    if (generation != _generation) return;
    _inflightKey = null;
  }
}

String googlePlacesQueryKey(HotelStayQuery query) {
  return <String>[
    (query.countryCode ?? '').trim().toUpperCase(),
    (query.country ?? '').trim().toLowerCase(),
    (query.destination ?? '').trim().toLowerCase(),
    (query.city ?? '').trim().toLowerCase(),
    (query.region ?? '').trim().toLowerCase(),
    (query.searchText ?? '').trim().toLowerCase(),
  ].join('|');
}

String formatHotelStayLocation({
  String city = '',
  String region = '',
  String country = '',
}) {
  return <String>[city, region, country]
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .join(', ');
}

String hotelStayLocationLabel(HotelStay stay, String languageCode) {
  final iso = stay22ResolveIsoCountryCode(stay.country);
  final countryLabel = iso == null
      ? stay.country.trim()
      : (stay22CountryIdentityFor(
              countryCode: iso,
              languageCode: languageCode,
            )?.localizedLabel ??
            stay.country.trim());
  return formatHotelStayLocation(
    city: stay.city,
    region: stay.region,
    country: countryLabel,
  );
}

/// Extension point for a later explicit, user-triggered extra page.
const bool kGooglePlacesManualNextPageEnabled = false;
