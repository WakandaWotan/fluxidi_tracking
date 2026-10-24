/// Explicit company departure origin; never inferred from coverage or GPS.
class CompanyOperationalBase {
  const CompanyOperationalBase({
    required this.address,
    required this.latitude,
    required this.longitude,
  });

  const CompanyOperationalBase.cleared()
    : address = '',
      latitude = null,
      longitude = null;

  final String address;
  final double? latitude;
  final double? longitude;

  bool get isValid =>
      address.trim().isNotEmpty &&
      latitude != null &&
      longitude != null &&
      latitude!.isFinite &&
      longitude!.isFinite &&
      latitude!.abs() <= 90 &&
      longitude!.abs() <= 180 &&
      !(latitude == 0 && longitude == 0);

  static CompanyOperationalBase? fromJson(Map<String, dynamic> json) {
    const keys = [
      'base_lat',
      'base_lng',
      'base_address',
      'baseLat',
      'baseLng',
      'baseAddress',
    ];
    if (!keys.any(json.containsKey)) return null;
    double? coordinate(dynamic raw) => raw is num
        ? raw.toDouble()
        : raw is String
        ? double.tryParse(raw.trim())
        : null;
    final base = CompanyOperationalBase(
      address: (json['base_address'] ?? json['baseAddress'] ?? '')
          .toString()
          .trim(),
      latitude: coordinate(json['base_lat'] ?? json['baseLat']),
      longitude: coordinate(json['base_lng'] ?? json['baseLng']),
    );
    return base.isValid ? base : const CompanyOperationalBase.cleared();
  }

  Map<String, dynamic> toJson() => isValid
      ? {
          'base_lat': latitude,
          'base_lng': longitude,
          'base_address': address.trim(),
        }
      : {
          'base_lat': null,
          'base_lng': null,
          'base_address': '',
          'baseLat': null,
          'baseLng': null,
          'baseAddress': '',
        };
}
