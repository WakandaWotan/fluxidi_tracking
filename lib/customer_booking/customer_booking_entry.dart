import 'package:fluxidi_tracking/airport/airport_catalog_repository.dart';

enum CustomerBookingKind {
  taxi,
  airport,
  event,
  stay,
  business,
  companyPage,
  bookingLink,
  qr,
}

class CustomerBookingCompany {
  const CustomerBookingCompany({
    this.partnerId = '',
    this.tenantId = '',
    this.companyId = '',
    this.companyCode = '',
    this.companyName = '',
    this.vehicles = const <Map<String, dynamic>>[],
  });

  final String partnerId;
  final String tenantId;
  final String companyId;
  final String companyCode;
  final String companyName;
  final List<Map<String, dynamic>> vehicles;

  bool get hasPartner => partnerId.trim().isNotEmpty;
  bool get hasCompany =>
      companyId.trim().isNotEmpty || tenantId.trim().isNotEmpty;

  CustomerBookingCompany copyWith({
    String? partnerId,
    String? tenantId,
    String? companyId,
    String? companyCode,
    String? companyName,
    List<Map<String, dynamic>>? vehicles,
  }) {
    return CustomerBookingCompany(
      partnerId: partnerId ?? this.partnerId,
      tenantId: tenantId ?? this.tenantId,
      companyId: companyId ?? this.companyId,
      companyCode: companyCode ?? this.companyCode,
      companyName: companyName ?? this.companyName,
      vehicles: vehicles ?? this.vehicles,
    );
  }

  String get routingPartnerId {
    final partner = partnerId.trim();
    if (partner.isNotEmpty) return partner;
    return companyId.trim();
  }
}

class CustomerBookingPlace {
  const CustomerBookingPlace({
    this.id = '',
    this.name = '',
    this.address = '',
    this.latitude,
    this.longitude,
    this.startsAt,
    this.attribution = '',
  });

  final String id;
  final String name;
  final String address;
  final double? latitude;
  final double? longitude;
  final DateTime? startsAt;
  final String attribution;

  String get displayAddress {
    final line = address.trim();
    if (line.isNotEmpty) return line;
    return name.trim();
  }
}

/// How the customer entered the single taxi booking flow.
class CustomerBookingEntryContext {
  const CustomerBookingEntryContext({
    required this.kind,
    this.company = const CustomerBookingCompany(),
    this.pickup,
    this.destination,
    this.airport,
    this.toAirport = true,
    this.campaignId = '',
    this.affiliateId = '',
    this.sourceLabel = '',
    this.lockCompany = false,
    this.allowModeToggle = false,
  });

  final CustomerBookingKind kind;
  final CustomerBookingCompany company;
  final CustomerBookingPlace? pickup;
  final CustomerBookingPlace? destination;
  final AirportCatalogAirport? airport;
  final bool toAirport;
  final String campaignId;
  final String affiliateId;
  final String sourceLabel;
  final bool lockCompany;
  final bool allowModeToggle;

  bool get isAirport =>
      kind == CustomerBookingKind.airport || airport != null;

  bool get showBusinessModeChoice =>
      kind == CustomerBookingKind.business || allowModeToggle;

  CustomerBookingEntryContext copyWith({
    CustomerBookingKind? kind,
    CustomerBookingCompany? company,
    CustomerBookingPlace? pickup,
    CustomerBookingPlace? destination,
    AirportCatalogAirport? airport,
    bool? toAirport,
    bool? allowModeToggle,
  }) {
    return CustomerBookingEntryContext(
      kind: kind ?? this.kind,
      company: company ?? this.company,
      pickup: pickup ?? this.pickup,
      destination: destination ?? this.destination,
      airport: airport ?? this.airport,
      toAirport: toAirport ?? this.toAirport,
      campaignId: campaignId,
      affiliateId: affiliateId,
      sourceLabel: sourceLabel,
      lockCompany: lockCompany,
      allowModeToggle: allowModeToggle ?? this.allowModeToggle,
    );
  }
}

const List<String> kCustomerBookingTaxiCtaInventory = <String>[
  'customer_home.airport_rides',
  'customer_home.business',
  'customer_home.events.on_book_event',
  'customer_home.hotels.taxi_to_stay',
  'customer_home.hotels.manual_taxi',
  'nearby_partners.book_partner',
  'partner_public_profile.taxi',
  'partner_public_profile.airport',
  'partner_public_profile.fixed_price',
  'events.detail.book_taxi',
  'events.category.taxi_to_event',
  'events.saved.book_taxi',
  'hotels.taxi_to_stay',
  'hotels.taxi_to_event',
  'hotels.plan_taxi_search',
];
