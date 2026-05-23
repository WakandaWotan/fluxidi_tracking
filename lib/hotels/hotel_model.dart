class HotelStayType {
  static const String hotel = 'hotel';
  static const String bedAndBreakfast = 'b&b';
  static const String aparthotel = 'aparthotel';
  static const String guesthouse = 'guesthouse';

  static const Set<String> values = <String>{
    hotel,
    bedAndBreakfast,
    aparthotel,
    guesthouse,
  };
}

/// Reusable discovery destination payload for structured taxi handoff.
///
/// This model is intentionally domain-agnostic to support hotels, events,
/// airports, nightlife, restaurants, and future discovery modules.
class DiscoveryDestination {
  const DiscoveryDestination({
    required this.discoveryType,
    required this.destinationName,
    required this.destinationAddress,
    this.latitude,
    this.longitude,
    required this.city,
    required this.region,
    required this.country,
    required this.provider,
    required this.providerId,
    this.tenantId,
    this.companyId,
  });

  final String discoveryType;
  final String destinationName;
  final String destinationAddress;
  final double? latitude;
  final double? longitude;
  final String city;
  final String region;
  final String country;
  final String provider;
  final String providerId;
  final String? tenantId;
  final String? companyId;
}

class HotelStay {
  const HotelStay({
    required this.id,
    required this.name,
    required this.type,
    required this.city,
    required this.region,
    required this.country,
    required this.address,
    required this.description,
    required this.imageRef,
    required this.lat,
    required this.lng,
    this.latitude,
    this.longitude,
    this.imageUrl,
    this.websiteUrl,
    this.bookingUrl,
    this.provider,
    this.externalProviderId,
    this.affiliateTrackingId,
    this.directBookingUrl,
    this.preferredBookingUrl,
    this.source = 'seed',
    this.sourceId,
    this.priceHint,
    this.rating,
    this.tags = const <String>[],
    this.travelStyles = const <String>[],
    this.ambience,
    this.popularFor = const <String>[],
  });

  final String id;
  final String name;
  final String type;
  final String city;
  final String region;
  final String country;
  final String address;
  final String description;

  /// Placeholder-friendly visual reference (asset key, URL, or label).
  final String imageRef;

  final double lat;
  final double lng;
  final double? latitude;
  final double? longitude;
  final String? imageUrl;
  final String? websiteUrl;
  final String? bookingUrl;
  final String? provider;
  final String? externalProviderId;
  final String? affiliateTrackingId;
  final String? directBookingUrl;
  final String? preferredBookingUrl;
  final String source;
  final String? sourceId;
  final String? priceHint;
  final double? rating;
  final List<String> tags;
  final List<String> travelStyles;
  final String? ambience;
  final List<String> popularFor;

  String? get effectiveBookingUrl {
    // TODO(H1-F): Support provider-built deep links
    // (e.g. Booking.com affiliate and future Demand API).
    final candidates = <String?>[
      preferredBookingUrl,
      bookingUrl,
      directBookingUrl,
      websiteUrl,
    ];
    for (final candidate in candidates) {
      final trimmed = candidate?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }

  String get effectiveProvider {
    final providerValue = provider?.trim();
    if (providerValue != null && providerValue.isNotEmpty) {
      return providerValue;
    }
    final sourceValue = source.trim();
    if (sourceValue.isNotEmpty) return sourceValue;
    return 'curated';
  }

  DiscoveryDestination toDiscoveryDestination({
    String? tenantId,
    String? companyId,
  }) {
    final normalizedName = name.trim().isEmpty ? id : name.trim();
    final normalizedAddress = address.trim().isEmpty
        ? '$city, $region, $country'
        : address.trim();
    return DiscoveryDestination(
      discoveryType: 'accommodation',
      destinationName: normalizedName,
      destinationAddress: normalizedAddress,
      latitude: latitude ?? lat,
      longitude: longitude ?? lng,
      city: city,
      region: region,
      country: country,
      provider: effectiveProvider,
      providerId: externalProviderId?.trim().isNotEmpty == true
          ? externalProviderId!.trim()
          : (sourceId?.trim().isNotEmpty == true ? sourceId!.trim() : id),
      tenantId: tenantId,
      companyId: companyId,
    );
  }
}
