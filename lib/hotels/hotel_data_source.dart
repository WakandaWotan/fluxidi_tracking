import 'package:fluxidi_tracking/app_config.dart';

import 'approved_hotel_data.dart';
import 'hotel_model.dart';

// TODO(HOTELS-REMOTE): Wire HotelsPage to RemoteHotelDataSource with local fallback
// after runtime validation.
// TODO(HOTELS-PROVIDER): Stay22 provider/list API adapter if available.
// TODO(HOTELS-PROVIDER): Expedia/Agoda/Travelpayouts adapters later.
// TODO(HOTELS-PROVIDER): Partner-approved backend catalog later.

class HotelStayQuery {
  const HotelStayQuery({
    this.city,
    this.country,
    this.lat,
    this.lng,
    this.radiusKm,
    this.source = 'approved-local',
  });

  final String? city;
  final String? country;
  final double? lat;
  final double? lng;
  final double? radiusKm;
  final String source;
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
        lat: query.lat,
        lng: query.lng,
        radiusKm: query.radiusKm,
        source: query.source,
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
  return normalized == 'approved-local';
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

bool _isApprovedHttpImageUrl(String? value) {
  final trimmed = (value ?? '').trim();
  if (trimmed.isEmpty) return false;
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme) return false;
  final scheme = uri.scheme.toLowerCase();
  return scheme == 'http' || scheme == 'https';
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
  if (imageRef != null && imageRef.startsWith('approved_asset:')) {
    final pathSuffix = imageRef.substring('approved_asset:'.length).trim();
    if (pathSuffix.isNotEmpty) return imageRef;
  }
  return '';
}

/// Maps a `/public/hotels/search` stay row to [HotelStay] when customer-safe.
HotelStay? hotelStayFromPublicHotelJson(Map<String, dynamic> json) {
  if (!_readBool(json['is_real_approved'])) return null;

  final id = _readString(json, const <String>['id']);
  final name = _readString(json, const <String>['name']);
  if (id == null || name == null) return null;

  final provider = _readString(json, const <String>['provider']);
  final source = _readString(json, const <String>['source']);
  if (!_isSafeApprovedCatalogValue(provider) &&
      !_isSafeApprovedCatalogValue(source)) {
    return null;
  }

  final lat = _readDouble(json, const <String>['lat', 'latitude']);
  final lng = _readDouble(json, const <String>['lng', 'longitude']);
  if (lat == null || lng == null) return null;

  final imageRef = _resolvePublicHotelImageRef(json);
  final imageUrlRaw = _readString(json, const <String>[
    'image_url',
    'imageUrl',
  ]);
  final imageUrl = _isApprovedHttpImageUrl(imageUrlRaw) ? imageUrlRaw : null;

  // Customer-facing cards require approved local assets or approved https URLs.
  if (imageRef.isEmpty && imageUrl == null) return null;

  final providerId = _readString(json, const <String>[
    'provider_id',
    'providerId',
    'source_id',
    'sourceId',
  ]);
  final externalUrl = _readString(json, const <String>[
    'external_url',
    'externalUrl',
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
  final rating = ratingLabel == null ? null : double.tryParse(ratingLabel);

  final address = _readString(json, const <String>['address']) ?? '';
  final city = _readString(json, const <String>['city']) ?? '';
  final region = _readString(json, const <String>['region']) ?? '';
  final country = _readString(json, const <String>['country']) ?? '';

  return HotelStay(
    id: id,
    name: name,
    type: _normalizeHotelStayType(_readString(json, const <String>['type'])),
    city: city,
    region: region,
    country: country,
    address: address,
    description: '',
    imageRef: imageRef,
    lat: lat,
    lng: lng,
    latitude: lat,
    longitude: lng,
    imageUrl: imageUrl,
    provider: provider ?? 'approved-local',
    externalProviderId: providerId,
    source: (source ?? 'approved_local').replaceAll('-', '_'),
    sourceId: providerId ?? id,
    priceHint: priceLabel,
    rating: rating,
    preferredBookingUrl: externalUrl,
    isRealApproved: true,
  );
}
