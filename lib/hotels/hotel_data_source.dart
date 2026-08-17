import 'package:fluxidi_tracking/app_config.dart';

import 'approved_hotel_data.dart';
import 'hotel_model.dart';

// TODO(HOTELS-PARTNER): Switch HotelsPage source to partner-approved once catalog has rows.
// TODO(HOTELS-PROVIDER): Do not add travelpayouts/expedia-rapid/agoda/booking-demand to the
// Flutter mapper allowlist until worker adapters return visually trusted rows.
// TODO(HOTELS-REMOTE): Add pull-to-refresh/provider switch once real provider adapters exist.
// TODO(HOTELS-PROVIDER): Stay22 provider/list API adapter if available.
// TODO(HOTELS-PROVIDER): Expedia/Agoda/Travelpayouts adapters later.
// TODO(HOTELS-PROVIDER): Partner-approved backend catalog later.

class HotelStayQuery {
  const HotelStayQuery({
    this.city,
    this.country,
    this.region,
    this.searchText,
    this.lat,
    this.lng,
    this.radiusKm,
    this.source = 'approved-local',
    this.checkin,
    this.checkout,
    this.rooms,
    this.adults,
    this.childAges = const <int>[],
  });

  final String? city;
  final String? country;
  final String? region;
  final String? searchText;
  final double? lat;
  final double? lng;
  final double? radiusKm;
  final String source;
  final String? checkin;
  final String? checkout;
  final int? rooms;
  final int? adults;
  final List<int> childAges;
}

abstract class HotelDataSource {
  Future<List<HotelStay>> fetchStays({
    HotelStayQuery query = const HotelStayQuery(),
  });
}

class LocalApprovedHotelDataSource implements HotelDataSource {
  const LocalApprovedHotelDataSource();

  @override
  Future<List<HotelStay>> fetchStays({
    HotelStayQuery query = const HotelStayQuery(),
  }) async {
    return List<HotelStay>.from(kApprovedBelgiumHotelData);
  }
}

class RemoteHotelDataSource implements HotelDataSource {
  const RemoteHotelDataSource();

  @override
  Future<List<HotelStay>> fetchStays({
    HotelStayQuery query = const HotelStayQuery(),
  }) async {
    try {
      final payload = await fetchPublicHotelSearch(
        city: query.city,
        country: query.country,
        region: query.region,
        searchText: query.searchText,
        lat: query.lat,
        lng: query.lng,
        radiusKm: query.radiusKm,
        source: query.source,
        checkin: query.checkin,
        checkout: query.checkout,
        rooms: query.rooms,
        adults: query.adults,
        childAges: query.childAges,
      );
      if (payload == null) return const <HotelStay>[];
      if (payload['ok'] != true) return const <HotelStay>[];
      final rawStays = payload['stays'];
      if (rawStays is! List) return const <HotelStay>[];

      final mapped = <HotelStay>[];
      for (final item in rawStays) {
        if (item is! Map) continue;
        final stay = hotelStayFromPublicHotelJson(
          Map<String, dynamic>.from(item),
        );
        if (stay != null) mapped.add(stay);
      }
      return List<HotelStay>.unmodifiable(mapped);
    } catch (_) {
      return const <HotelStay>[];
    }
  }
}

bool _isSafeApprovedCatalogValue(String? value) {
  final normalized = (value ?? '').trim().toLowerCase().replaceAll('_', '-');
  return normalized == 'approved-local' || normalized == 'partner-approved';
}

bool _isGooglePlacesCatalogValue(String? value) {
  final normalized = (value ?? '').trim().toLowerCase().replaceAll('_', '-');
  return normalized == 'google-places' || normalized == 'places';
}

bool isRatehawkCatalogValue(String? value) {
  final normalized = (value ?? '').trim().toLowerCase().replaceAll('_', '-');
  return normalized == 'ratehawk' ||
      normalized == 'rate-hawk' ||
      normalized == 'etg' ||
      normalized == 'emerging-travel';
}

bool _readBool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = (value ?? '').toString().trim().toLowerCase();
  return text == 'true' || text == '1' || text == 'yes';
}

String? _readString(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value == null) continue;
    final text = value.toString().trim();
    if (text.isNotEmpty) return text;
  }
  return null;
}

double? _readDouble(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value == null) continue;
    if (value is num) {
      final parsed = value.toDouble();
      if (parsed.isFinite) return parsed;
      continue;
    }
    final parsed = double.tryParse(value.toString().trim());
    if (parsed != null && parsed.isFinite) return parsed;
  }
  return null;
}

double? _parseLeadingRating(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return null;
  final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(text);
  if (match == null) return null;
  return double.tryParse(match.group(1)!);
}

bool _isApprovedHttpImageUrl(String? value) {
  final trimmed = (value ?? '').trim();
  if (trimmed.isEmpty) return false;
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme) return false;
  final scheme = uri.scheme.toLowerCase();
  return scheme == 'http' || scheme == 'https';
}

String? _resolvePublicHotelImageUrl(String? raw) {
  final trimmed = (raw ?? '').trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.startsWith('/')) {
    final base = appConfig.bookingBaseUrl.replaceAll(RegExp(r'/+$'), '');
    return '$base$trimmed';
  }
  return _isApprovedHttpImageUrl(trimmed) ? trimmed : null;
}

String _normalizeHotelStayType(String? rawType) {
  final normalized = (rawType ?? '').trim().toLowerCase();
  if (HotelStayType.values.contains(normalized)) return normalized;
  if (normalized == 'bed and breakfast' || normalized == 'bnb') {
    return HotelStayType.bedAndBreakfast;
  }
  return HotelStayType.hotel;
}

String _resolvePublicHotelImageRef(Map<String, dynamic> json) {
  final imageRef = _readString(json, const <String>['image_ref', 'imageRef']);
  if (imageRef != null && imageRef.startsWith('partner_approved:')) {
    final pathSuffix = imageRef.substring('partner_approved:'.length).trim();
    if (pathSuffix.isNotEmpty) return imageRef;
  }
  return '';
}

/// Maps a `/public/hotels/search` stay row to [HotelStay] when customer-safe.
HotelStay? hotelStayFromPublicHotelJson(Map<String, dynamic> json) {
  final name = _readString(json, const <String>['name']);
  if (name == null) return null;

  final provider = _readString(json, const <String>['provider']);
  final source = _readString(json, const <String>['source']);
  final isGooglePlaces =
      _isGooglePlacesCatalogValue(provider) ||
      _isGooglePlacesCatalogValue(source);
  final isRatehawk =
      isRatehawkCatalogValue(provider) || isRatehawkCatalogValue(source);

  if (!isGooglePlaces && !isRatehawk) {
    if (!_readBool(json['is_real_approved'])) return null;
    if (!_isSafeApprovedCatalogValue(provider) &&
        !_isSafeApprovedCatalogValue(source)) {
      return null;
    }
  } else if (isGooglePlaces && !_readBool(json['is_real_approved'])) {
    return null;
  }

  final catalogSource = provider ?? source ?? 'approved-local';
  final providerType = HotelStayProviderLabels.fromCatalogSource(catalogSource);

  final lat = _readDouble(json, const <String>['lat', 'latitude']);
  final lng = _readDouble(json, const <String>['lng', 'longitude']);
  if (lat == null || lng == null) return null;

  final imageRef = _resolvePublicHotelImageRef(json);
  final imageUrlRaw = _readString(json, const <String>[
    'image_url',
    'imageUrl',
  ]);
  final imageUrl = _resolvePublicHotelImageUrl(imageUrlRaw);

  if (!isGooglePlaces && !isRatehawk && imageRef.isEmpty && imageUrl == null) {
    return null;
  }

  final providerId = _readString(json, const <String>[
    'provider_id',
    'providerId',
    'source_id',
    'sourceId',
  ]);
  final externalUrl = _readString(json, const <String>[
    'external_url',
    'externalUrl',
    'external_availability_url',
    'externalAvailabilityUrl',
  ]);
  final priceLabel = _readString(json, const <String>[
    'price_label',
    'priceLabel',
    'price_hint',
    'priceHint',
  ]);
  final ratingLabel = _readString(json, const <String>[
    'rating_label',
    'ratingLabel',
    'rating',
  ]);
  final rating = _parseLeadingRating(ratingLabel);
  final providerLabel = _readString(json, const <String>[
    'provider_label',
    'providerLabel',
  ]);
  final availabilityLabel = _readString(json, const <String>[
    'availability_label',
    'availabilityLabel',
  ]);
  final photoAttribution = _readString(json, const <String>[
    'photo_attribution',
    'photoAttribution',
  ]);

  final address = _readString(json, const <String>['address']) ?? '';
  final city = _readString(json, const <String>['city']) ?? '';
  final region = _readString(json, const <String>['region']) ?? '';
  final country = _readString(json, const <String>['country']) ?? '';

  final descriptionParts = <String>[
    if ((availabilityLabel ?? '').trim().isNotEmpty) availabilityLabel!.trim(),
    if ((photoAttribution ?? '').trim().isNotEmpty) photoAttribution!.trim(),
  ];
  final hidRaw = _readString(json, const <String>['hid', 'provider_id']);
  final hid = int.tryParse(hidRaw ?? '');
  final retrievedRaw = json['retrieved_at'] ?? json['retrievedAt'];
  DateTime? retrievedAt;
  if (retrievedRaw is num && retrievedRaw.isFinite) {
    retrievedAt = DateTime.fromMillisecondsSinceEpoch(retrievedRaw.round());
  } else if (retrievedRaw is String) {
    retrievedAt = DateTime.tryParse(retrievedRaw.trim());
  }

  final explicitId = _readString(json, const <String>['id']);
  final resolvedId = explicitId ?? (hid != null ? 'ratehawk:$hid' : null);
  if (resolvedId == null) return null;

  return HotelStay(
    id: resolvedId,
    name: name,
    type: _normalizeHotelStayType(_readString(json, const <String>['type'])),
    city: city,
    region: region,
    country: country,
    address: address,
    description: descriptionParts.join(' · '),
    imageRef: imageRef,
    lat: lat,
    lng: lng,
    latitude: lat,
    longitude: lng,
    imageUrl: imageUrl,
    provider: catalogSource,
    providerType: providerType,
    providerLabel: providerLabel,
    externalProviderReference: providerId,
    externalProviderId: providerId,
    source: (source ?? 'approved_local').replaceAll('-', '_'),
    sourceId: providerId ?? resolvedId,
    priceHint: priceLabel,
    rating: rating,
    externalAvailabilityUrl: externalUrl,
    preferredBookingUrl: externalUrl,
    isRealApproved: true,
    hid: hid,
    availabilityLabel: availabilityLabel,
    retrievedAt: retrievedAt,
  );
}
