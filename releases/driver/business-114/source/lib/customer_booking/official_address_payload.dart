import '../limousine/limousine_address_lookup.dart';

/// Carries the selected source identity, not a claim of road access. A GPS
/// fix keeps its original sensor evidence and never becomes an official ID.
Map<String, dynamic> officialOperationalInput(LimousineAddressValue value) => {
  'kind': value.fromCurrentLocation ? 'gps' : 'address',
  'label': value.routeText,
  if (!value.fromCurrentLocation && value.officialAddress != null) ...{
    'official_address': value.officialAddress!.toJson(),
    if (value.hasCoordinates) 'lat': value.lat,
    if (value.hasCoordinates) 'lng': value.lon,
  },
  if (value.fromCurrentLocation && value.gpsCapturedAt != null)
    'capturedAt': value.gpsCapturedAt!.millisecondsSinceEpoch,
  if (value.fromCurrentLocation && value.gpsAccuracyMeters != null)
    'accuracyMeters': value.gpsAccuracyMeters,
};

Map<String, dynamic> officialOperationalStop(LimousineAddressValue value) => {
  'address': value.routeText,
  'lat': value.lat,
  'lng': value.lon,
  if (value.officialAddress != null || value.fromCurrentLocation)
    'input': officialOperationalInput(value),
};
