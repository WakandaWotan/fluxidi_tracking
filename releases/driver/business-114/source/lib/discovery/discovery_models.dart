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

  String get prefillDestinationText {
    final address = destinationAddress.trim();
    if (address.isNotEmpty) return address;
    final name = destinationName.trim();
    if (name.isNotEmpty) return name;
    final cityValue = city.trim();
    if (cityValue.isNotEmpty) return cityValue;
    return '$region, $country';
  }
}
