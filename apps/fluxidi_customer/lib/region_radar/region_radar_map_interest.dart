import 'region_interest_client.dart';
import 'region_radar_geocode.dart';

/// What the public radar contract can actually place on the map.
///
/// Today's `GET /region-interest/radar` returns only a regional total
/// (`count`) and a public category (`display_count`, for example `3+`).
/// It does not send individual registrations, names, emails, phones, or
/// coordinates. A value like `3+` is a category, not three locations.
enum RegionRadarMarkerKind { selectedRegion, regionGroup, ownInterest }

class RegionRadarMapMarker {
  const RegionRadarMapMarker({
    required this.kind,
    required this.lat,
    required this.lon,
    required this.country,
    required this.postcode,
    required this.placeName,
    this.displayCount = '',
  });

  final RegionRadarMarkerKind kind;
  final double lat;
  final double lon;
  final String country;
  final String postcode;
  final String placeName;
  final String displayCount;

  String get id =>
      '${kind.name}|$country|$postcode|${lat.toStringAsFixed(5)}|${lon.toStringAsFixed(5)}';
}

/// Builds the honest public map for the selected region.
///
/// Same postcode → one regional position (the Mapbox postcode centre), unless
/// the snapshot already carries bounded approximate cells from the server.
/// Own interest may add a local gold mark on that same position after the
/// server accepted the registration. It does not invent extra dots from
/// `3+`, GPS, or a billing address, and it does not add one to the total.
List<RegionRadarMapMarker> regionRadarMapMarkers({
  RegionRadarPlace? place,
  RegionRadarSnapshot? snapshot,
  required bool ownInThisRegion,
}) {
  if (place == null) return const <RegionRadarMapMarker>[];
  final markers = <RegionRadarMapMarker>[];
  final cells = snapshot?.approximateCells ?? const <RegionRadarApproximateCell>[];
  if (cells.isNotEmpty) {
    for (final cell in cells) {
      markers.add(
        RegionRadarMapMarker(
          kind: RegionRadarMarkerKind.regionGroup,
          lat: cell.lat,
          lon: cell.lon,
          country: place.country,
          postcode: cell.postcode.isEmpty ? place.postcode : cell.postcode,
          placeName: place.placeName,
          displayCount: cell.displayCount,
        ),
      );
    }
  } else if (snapshot != null && snapshot.hasInterest) {
    markers.add(
      RegionRadarMapMarker(
        kind: RegionRadarMarkerKind.regionGroup,
        lat: place.lat,
        lon: place.lon,
        country: place.country,
        postcode: place.postcode,
        placeName: place.placeName,
        displayCount: snapshot.displayCount,
      ),
    );
  } else {
    markers.add(
      RegionRadarMapMarker(
        kind: RegionRadarMarkerKind.selectedRegion,
        lat: place.lat,
        lon: place.lon,
        country: place.country,
        postcode: place.postcode,
        placeName: place.placeName,
      ),
    );
  }
  if (ownInThisRegion) {
    markers.add(
      RegionRadarMapMarker(
        kind: RegionRadarMarkerKind.ownInterest,
        lat: place.lat,
        lon: place.lon,
        country: place.country,
        postcode: place.postcode,
        placeName: place.placeName,
        displayCount: snapshot?.displayCount ?? '',
      ),
    );
  }
  return List<RegionRadarMapMarker>.unmodifiable(markers);
}

/// Groups overlapping regional cells when the camera is zoomed out.
///
/// Own and selected-region marks stay separate. Counts are never added
/// together, so `1+` and `2+` do not become `3`.
List<RegionRadarMapMarker> clusterRegionRadarMarkers({
  required List<RegionRadarMapMarker> markers,
  required double zoom,
}) {
  final groups = <RegionRadarMapMarker>[];
  final pinned = <RegionRadarMapMarker>[];
  for (final marker in markers) {
    if (marker.kind == RegionRadarMarkerKind.regionGroup) {
      groups.add(marker);
    } else {
      pinned.add(marker);
    }
  }
  if (groups.length <= 1) {
    return List<RegionRadarMapMarker>.unmodifiable(<RegionRadarMapMarker>[
      ...groups,
      ...pinned,
    ]);
  }
  final cellSize = zoom >= 10 ? 0.01 : (zoom >= 8 ? 0.04 : 0.25);
  final buckets = <String, List<RegionRadarMapMarker>>{};
  for (final marker in groups) {
    final key =
        '${(marker.lat / cellSize).round()}|${(marker.lon / cellSize).round()}';
    buckets.putIfAbsent(key, () => <RegionRadarMapMarker>[]).add(marker);
  }
  final clustered = <RegionRadarMapMarker>[];
  for (final bucket in buckets.values) {
    if (bucket.length == 1) {
      clustered.add(bucket.single);
      continue;
    }
    final lat =
        bucket.map((marker) => marker.lat).reduce((a, b) => a + b) /
        bucket.length;
    final lon =
        bucket.map((marker) => marker.lon).reduce((a, b) => a + b) /
        bucket.length;
    final counts = bucket
        .map((marker) => marker.displayCount.trim())
        .where((count) => count.isNotEmpty)
        .toSet();
    clustered.add(
      RegionRadarMapMarker(
        kind: RegionRadarMarkerKind.regionGroup,
        lat: lat,
        lon: lon,
        country: bucket.first.country,
        postcode: bucket.first.postcode,
        placeName: bucket.first.placeName,
        displayCount: counts.length == 1 ? counts.single : '',
      ),
    );
  }
  return List<RegionRadarMapMarker>.unmodifiable(<RegionRadarMapMarker>[
    ...clustered,
    ...pinned,
  ]);
}

String regionRadarOwnKey({
  required String country,
  required String postcode,
}) {
  return '${country.trim().toUpperCase()}|${postcode.trim()}';
}

String regionRadarPlaceLine({
  required String postcode,
  required String placeName,
}) {
  return <String>[
    postcode.trim(),
    if (placeName.trim().isNotEmpty) placeName.trim(),
  ].join(' · ');
}

/// Keeps the server category intact: `3+` stays `3+ geïnteresseerden`.
String regionRadarInterestedLabel({
  required String displayCount,
  required String interestedWord,
}) {
  final count = displayCount.trim();
  final word = interestedWord.trim();
  if (count.isEmpty) return word;
  if (word.isEmpty) return count;
  return '$count $word';
}
