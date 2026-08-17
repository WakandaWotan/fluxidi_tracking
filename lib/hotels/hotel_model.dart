import 'package:fluxidi_tracking/discovery/discovery_models.dart';

// TODO(HOTELS-PROVIDER): Expedia Rapid content/availability will be resolved server-side
// via Cloudflare Worker — never add API secrets or direct Rapid calls in Flutter.
// TODO(HOTELS-PROVIDER): Affiliate/deeplink URLs (Booking, Stay22, Travelpayouts) must be
// supplied server-side or through safe configured links; do not scrape or invent URLs here.

enum HotelStayProviderType {
  localApproved,
  expediaRapid,
  bookingAffiliate,
  stay22,
  travelpayouts,
  googlePlaces,
  external,
}

class HotelStayProviderLabels {
  const HotelStayProviderLabels._();

  static String labelFor(HotelStayProviderType type, String languageCode) {
    switch (type) {
      case HotelStayProviderType.localApproved:
        return _t(
          languageCode,
          nl: 'Goedgekeurd door Fluxidi',
          en: 'Fluxidi approved',
          fr: 'Approuvé par Fluxidi',
          es: 'Aprobado por Fluxidi',
        );
      case HotelStayProviderType.expediaRapid:
        return _t(
          languageCode,
          nl: 'Expedia',
          en: 'Expedia',
          fr: 'Expedia',
          es: 'Expedia',
        );
      case HotelStayProviderType.bookingAffiliate:
        return _t(
          languageCode,
          nl: 'Booking.com',
          en: 'Booking.com',
          fr: 'Booking.com',
          es: 'Booking.com',
        );
      case HotelStayProviderType.stay22:
        return _t(
          languageCode,
          nl: 'Stay22',
          en: 'Stay22',
          fr: 'Stay22',
          es: 'Stay22',
        );
      case HotelStayProviderType.travelpayouts:
        return _t(
          languageCode,
          nl: 'Travelpayouts',
          en: 'Travelpayouts',
          fr: 'Travelpayouts',
          es: 'Travelpayouts',
        );
      case HotelStayProviderType.googlePlaces:
        return _t(
          languageCode,
          nl: 'Echte plaatsvermelding',
          en: 'Real place discovery',
          fr: 'Découverte de lieu réel',
          es: 'Descubrimiento de lugar real',
        );
      case HotelStayProviderType.external:
        return _t(
          languageCode,
          nl: 'Extern',
          en: 'External',
          fr: 'Externe',
          es: 'Externo',
        );
    }
  }

  static HotelStayProviderType fromCatalogSource(String? rawSource) {
    final normalized = (rawSource ?? '').trim().toLowerCase().replaceAll(
      '_',
      '-',
    );
    switch (normalized) {
      case 'expedia-rapid':
        return HotelStayProviderType.expediaRapid;
      case 'booking-demand':
      case 'booking-affiliate':
      case 'booking.com':
        return HotelStayProviderType.bookingAffiliate;
      case 'stay22':
        return HotelStayProviderType.stay22;
      case 'travelpayouts':
        return HotelStayProviderType.travelpayouts;
      case 'google-places':
      case 'places':
        return HotelStayProviderType.googlePlaces;
      case 'partner-approved':
      case 'approved-local':
        return HotelStayProviderType.localApproved;
      default:
        return HotelStayProviderType.external;
    }
  }

  static String _t(
    String languageCode, {
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) {
    switch (languageCode) {
      case 'en':
        return en;
      case 'fr':
        return fr;
      case 'es':
        return es;
      case 'nl':
      default:
        return nl;
    }
  }
}

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
    this.providerType = HotelStayProviderType.localApproved,
    this.providerLabel,
    this.externalAvailabilityUrl,
    this.externalProviderReference,
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
    this.isRealApproved = false,
    this.hid,
    this.availabilityLabel,
    this.retrievedAt,
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
  final HotelStayProviderType providerType;
  final String? providerLabel;
  final String? externalAvailabilityUrl;
  final String? externalProviderReference;
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
  final bool isRealApproved;
  final int? hid;
  final String? availabilityLabel;
  final DateTime? retrievedAt;

  String? get effectiveBookingUrl {
    final directAvailability = _normalizeHttpUrl(externalAvailabilityUrl);
    if (directAvailability != null) return directAvailability;

    // TODO(H1-F): Support provider-built deep links
    // (e.g. Booking.com affiliate and future Demand API).
    final candidates = <String?>[
      preferredBookingUrl,
      bookingUrl,
      directBookingUrl,
      websiteUrl,
    ];
    for (final candidate in candidates) {
      final normalized = _normalizeHttpUrl(candidate);
      if (normalized != null) return normalized;
    }
    return null;
  }

  String? get effectiveExternalProviderReference {
    final explicit = externalProviderReference?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final legacy = externalProviderId?.trim();
    if (legacy != null && legacy.isNotEmpty) return legacy;
    final sourceRef = sourceId?.trim();
    if (sourceRef != null && sourceRef.isNotEmpty) return sourceRef;
    return null;
  }

  String displayProviderLabel(String languageCode) {
    final custom = providerLabel?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    return HotelStayProviderLabels.labelFor(providerType, languageCode);
  }

  static String? _normalizeHttpUrl(String? raw) {
    final trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) return null;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
    return trimmed;
  }

  HotelStay copyWith({
    String? id,
    String? name,
    String? type,
    String? city,
    String? region,
    String? country,
    String? address,
    String? description,
    String? imageRef,
    double? lat,
    double? lng,
    double? latitude,
    double? longitude,
    String? imageUrl,
    String? websiteUrl,
    String? bookingUrl,
    String? provider,
    HotelStayProviderType? providerType,
    String? providerLabel,
    String? externalAvailabilityUrl,
    String? externalProviderReference,
    String? externalProviderId,
    String? affiliateTrackingId,
    String? directBookingUrl,
    String? preferredBookingUrl,
    String? source,
    String? sourceId,
    String? priceHint,
    double? rating,
    List<String>? tags,
    List<String>? travelStyles,
    String? ambience,
    List<String>? popularFor,
    bool? isRealApproved,
    int? hid,
    String? availabilityLabel,
    DateTime? retrievedAt,
    bool clearPriceHint = false,
    bool clearAvailabilityLabel = false,
  }) {
    return HotelStay(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      city: city ?? this.city,
      region: region ?? this.region,
      country: country ?? this.country,
      address: address ?? this.address,
      description: description ?? this.description,
      imageRef: imageRef ?? this.imageRef,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      imageUrl: imageUrl ?? this.imageUrl,
      websiteUrl: websiteUrl ?? this.websiteUrl,
      bookingUrl: bookingUrl ?? this.bookingUrl,
      provider: provider ?? this.provider,
      providerType: providerType ?? this.providerType,
      providerLabel: providerLabel ?? this.providerLabel,
      externalAvailabilityUrl:
          externalAvailabilityUrl ?? this.externalAvailabilityUrl,
      externalProviderReference:
          externalProviderReference ?? this.externalProviderReference,
      externalProviderId: externalProviderId ?? this.externalProviderId,
      affiliateTrackingId: affiliateTrackingId ?? this.affiliateTrackingId,
      directBookingUrl: directBookingUrl ?? this.directBookingUrl,
      preferredBookingUrl: preferredBookingUrl ?? this.preferredBookingUrl,
      source: source ?? this.source,
      sourceId: sourceId ?? this.sourceId,
      priceHint: clearPriceHint ? null : (priceHint ?? this.priceHint),
      rating: rating ?? this.rating,
      tags: tags ?? this.tags,
      travelStyles: travelStyles ?? this.travelStyles,
      ambience: ambience ?? this.ambience,
      popularFor: popularFor ?? this.popularFor,
      isRealApproved: isRealApproved ?? this.isRealApproved,
      hid: hid ?? this.hid,
      availabilityLabel: clearAvailabilityLabel
          ? null
          : (availabilityLabel ?? this.availabilityLabel),
      retrievedAt: retrievedAt ?? this.retrievedAt,
    );
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
      providerId: effectiveExternalProviderReference ?? id,
      tenantId: tenantId,
      companyId: companyId,
    );
  }
}
