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
  final String source;
  final String? sourceId;
  final String? priceHint;
  final double? rating;
  final List<String> tags;
  final List<String> travelStyles;
  final String? ambience;
  final List<String> popularFor;
}
