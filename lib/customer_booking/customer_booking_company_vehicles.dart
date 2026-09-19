import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_driver_agenda_style.dart';
import 'package:fluxidi_tracking/company/company_plan_media.dart';
import 'package:fluxidi_tracking/company/company_plan_vehicle_type.dart';
import 'package:fluxidi_tracking/nearby/public_partner_identity.dart';
import 'package:fluxidi_tracking/nearby/public_partner_market.dart';
import 'package:fluxidi_tracking/payment/booking_payment_options.dart';

typedef CustomerBookingProfileGet = Future<http.Response> Function(Uri uri);

/// Published company-settings logo for customer surfaces.
///
/// Nearby cards already read `logo_url` / `media.logo_url`. The booking banner
/// must use the same fields, never the packaged Fluxidi mark.
String customerBookingPublishedLogoUrl(Map<String, dynamic> profile) {
  Map<String, dynamic> nested(String key) {
    final raw = profile[key];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return const <String, dynamic>{};
  }

  final media = nested('media');
  final branding = nested('branding');
  for (final value in <Object?>[
    profile['publicLogoUrl'],
    profile['public_logo_url'],
    profile['logo_url'],
    profile['logoUrl'],
    media['logo_url'],
    media['logoUrl'],
    branding['logo_url'],
    branding['logoUrl'],
  ]) {
    final url = (value ?? '').toString().trim();
    if (customerBookingLogoUrlIsRenderable(url)) return url;
  }
  return '';
}

bool customerBookingLogoUrlIsRenderable(String url) {
  final text = url.trim();
  if (publicPartnerLogoIsRenderable(text)) return true;
  return text.startsWith('http://127.0.0.1') ||
      text.startsWith('http://localhost');
}

List<CompanyPlanVehicleCategory> customerBookingBookableCategories(
  List<Map<String, dynamic>> vehicles, {
  required int passengers,
}) {
  final found = <CompanyPlanVehicleCategory>{};
  for (final vehicle in vehicles) {
    final category = classifyCompanyPlanVehicleCategory(vehicle);
    if (category == null) continue;
    if (passengers > 1 &&
        !companyAgendaVehicleFitsPassengers(vehicle, passengers) &&
        companyAgendaVehicleCapacity(vehicle) > 0) {
      continue;
    }
    found.add(category);
  }
  return CompanyPlanVehicleCategory.values
      .where(found.contains)
      .toList(growable: false);
}

Map<String, dynamic>? customerBookingExampleVehicleForCategory({
  required List<Map<String, dynamic>> vehicles,
  required CompanyPlanVehicleCategory category,
  required int passengers,
}) {
  final matches = [
    for (final vehicle in vehicles)
      if (classifyCompanyPlanVehicleCategory(vehicle) == category) vehicle,
  ];
  if (matches.isEmpty) return null;
  final fitting = [
    for (final vehicle in matches)
      if (companyAgendaVehicleFitsPassengers(vehicle, passengers) ||
          companyAgendaVehicleCapacity(vehicle) <= 0)
        vehicle,
  ];
  return fitting.isNotEmpty ? fitting.first : matches.first;
}

String customerBookingVehiclePhotoUrl(Map<String, dynamic>? vehicle) {
  if (vehicle == null) return '';
  for (final candidate in companyPlanVehiclePhotoCandidates(vehicle)) {
    final raw = candidate.trim();
    if (raw.isEmpty) continue;
    final lower = raw.toLowerCase();
    // Object keys such as public-media/... are storage refs, not a published
    // company photo. Cards must use the category fallback asset instead.
    if (!lower.startsWith('https://') && !lower.startsWith('http://')) {
      continue;
    }
    final https = resolvePublicHttpsMediaUrl(raw);
    if (https.isNotEmpty) return https;
    if (lower.startsWith('https://') && !isLocalOrPrivateMediaRef(raw)) {
      return raw;
    }
    if (lower.startsWith('http://127.0.0.1') ||
        lower.startsWith('http://localhost')) {
      return raw;
    }
  }
  return '';
}

List<Map<String, dynamic>> customerBookingVehiclesFromProfile(
  Map<String, dynamic> profile,
) {
  return publicPartnerSafeTaxiVehicles(
    publicPartnerTaxiCatalogVehicles(profile),
    limousineVehicleIds: publicPartnerLimousineAssignedVehicleIds(profile),
  );
}

Map<String, dynamic> customerBookingProfileMap(Object? decoded) {
  if (decoded is! Map) return const <String, dynamic>{};
  final root = Map<String, dynamic>.from(decoded);
  final nested = root['profile'];
  if (nested is Map) return Map<String, dynamic>.from(nested);
  return root;
}

String customerBookingCompanyNameFromProfile(Map<String, dynamic> profile) {
  for (final key in const <String>[
    'display_name',
    'company_name',
    'legal_name',
    'public_name',
    'trading_name',
    'name',
  ]) {
    final value = (profile[key] ?? '').toString().trim();
    if (value.isNotEmpty) return value;
  }
  return '';
}

String customerBookingVehicleCapacityLabel({
  required Map<String, dynamic>? vehicle,
  required CompanyPlanVehicleCategory category,
  required AppLanguage language,
}) {
  final seats = vehicle == null
      ? null
      : companyAgendaVehiclePassengerSeats(vehicle);
  final bags = vehicle == null ? 0 : companyAgendaVehicleBagCapacity(vehicle);
  if (seats != null && seats > 0 && bags > 0) {
    return language == AppLanguage.en
        ? '$seats pax · $bags bags'
        : '$seats pax · $bags bagage';
  }
  if (seats != null && seats > 0) {
    return language == AppLanguage.en
        ? '$seats passengers'
        : '$seats passagiers';
  }
  return language == AppLanguage.en
      ? 'Capacity unknown'
      : 'Capaciteit onbekend';
}

class CustomerBookingCompanySnapshot {
  const CustomerBookingCompanySnapshot({
    this.companyName = '',
    this.vehicles = const <Map<String, dynamic>>[],
    this.drivers = const <Map<String, dynamic>>[],
    this.payment = const BookingPaymentCapability.unavailable(),
    this.limousineOffered = false,
    this.profile = const <String, dynamic>{},
  });

  final String companyName;
  final List<Map<String, dynamic>> vehicles;
  final List<Map<String, dynamic>> drivers;
  final BookingPaymentCapability payment;
  final bool limousineOffered;
  final Map<String, dynamic> profile;
}

List<Map<String, dynamic>> customerBookingDriversFromProfile(
  Map<String, dynamic> profile,
) {
  final raw = profile['drivers'];
  if (raw is! List) return const <Map<String, dynamic>>[];
  return [
    for (final item in raw)
      if (item is Map) Map<String, dynamic>.from(item),
  ];
}

bool customerBookingProfileOffersLimousine(Map<String, dynamic> profile) {
  if (profile['limousine_available'] == true ||
      profile['limousine_service_enabled'] == true) {
    return true;
  }
  final services = profile['services'];
  if (services is List &&
      services.any(
        (item) => item.toString().trim().toLowerCase() == 'limousine',
      )) {
    return true;
  }
  final projection = profile['limousine_projection'];
  if (projection is Map &&
      (projection['limousine_available'] == true ||
          projection['limousine_service_enabled'] == true)) {
    return true;
  }
  return false;
}

bool customerBookingVehicleIsLimousineOffer(Map<String, dynamic> vehicle) {
  if (publicPartnerVehicleAssignedToLimousine(vehicle)) return true;
  final token = [
    vehicle['name'],
    vehicle['display_name'],
    vehicle['vehicle_type'],
    vehicle['vehicleType'],
    vehicle['model'],
    vehicle['service_category'],
    vehicle['serviceCategory'],
  ].whereType<Object>().map((part) => part.toString().toLowerCase()).join(' ');
  return token.contains('limousine') ||
      token.contains('party limo') ||
      token.contains('stretch');
}

List<Map<String, dynamic>> customerBookingFilterVehiclesForEnabledServices({
  required List<Map<String, dynamic>> vehicles,
  required bool limousineOffered,
  Set<String> limousineVehicleIds = const <String>{},
}) {
  if (limousineOffered) return vehicles;
  return [
    for (final vehicle in vehicles)
      if (!limousineVehicleIds.contains(companyAgendaVehicleId(vehicle)) &&
          !customerBookingVehicleIsLimousineOffer(vehicle))
        vehicle,
  ];
}

CustomerBookingCompanySnapshot customerBookingCompanySnapshotFromProfile(
  Map<String, dynamic> profile,
) {
  return CustomerBookingCompanySnapshot(
    companyName: customerBookingCompanyNameFromProfile(profile),
    vehicles: customerBookingVehiclesFromProfile(profile),
    drivers: customerBookingDriversFromProfile(profile),
    payment: BookingPaymentCapability.fromPublicJson(profile),
    limousineOffered: customerBookingProfileOffersLimousine(profile),
    profile: profile,
  );
}

Future<CustomerBookingCompanySnapshot> fetchCustomerBookingCompanySnapshot({
  required String bookingBaseUrl,
  required String partnerId,
  CustomerBookingProfileGet? httpGet,
}) async {
  final id = partnerId.trim();
  if (id.isEmpty || bookingBaseUrl.trim().isEmpty) {
    return const CustomerBookingCompanySnapshot();
  }
  final uri = Uri.parse(
    '$bookingBaseUrl/partners/profile',
  ).replace(queryParameters: <String, String>{'partner_id': id});
  final getter = httpGet ?? http.get;
  final res = await getter(uri).timeout(const Duration(seconds: 12));
  if (res.statusCode != 200) {
    throw StateError('partner_profile_http_${res.statusCode}');
  }
  final decoded = jsonDecode(res.body);
  return customerBookingCompanySnapshotFromProfile(
    customerBookingProfileMap(decoded),
  );
}

class CustomerBookingAvailabilitySnapshot {
  const CustomerBookingAvailabilitySnapshot({
    this.availableIds = const <String>{},
    this.unavailableIds = const <String>{},
    this.reasons = const <String, String>{},
    this.driverIds = const <String, String>{},
    this.drivers = const <Map<String, dynamic>>[],
    this.loadFailed = false,
    this.fetched = false,
    this.expiresAt,
  });

  final Set<String> availableIds;
  final Set<String> unavailableIds;
  final Map<String, String> reasons;
  final Map<String, String> driverIds;
  final List<Map<String, dynamic>> drivers;
  final bool loadFailed;
  final bool fetched;
  final DateTime? expiresAt;

  bool get resolved => fetched && !loadFailed;
}

Map<String, dynamic>? customerBookingAvailabilityDriverRecord(
  Map<dynamic, dynamic> item,
) {
  final nested =
      item['driver'] ?? item['assigned_driver'] ?? item['assignedDriver'];
  final driverId = (item['driver_id'] ?? item['driverId'] ?? '')
      .toString()
      .trim();
  if (nested is Map) {
    final record = Map<String, dynamic>.from(nested);
    if (companyAgendaDriverId(record).isEmpty && driverId.isNotEmpty) {
      record['driver_id'] = driverId;
    }
    return customerBookingPublishedDriverCard(record);
  }
  if (driverId.isEmpty) return null;
  final stub = <String, dynamic>{'driver_id': driverId};
  for (final key in const <String>[
    'first_name',
    'firstName',
    'display_name',
    'displayName',
    'public_display_name',
    'publicDisplayName',
    'name',
    'public_photo_url',
    'publicPhotoUrl',
    'driver_photo_url',
    'driverPhotoUrl',
    'photo_url',
    'portrait_url',
    'public_profile_enabled',
    'publicProfileEnabled',
    'public_photo_enabled',
    'publicPhotoEnabled',
    'driver_rating_avg',
    'rating_avg',
    'driver_rating_count',
    'rating_count',
  ]) {
    if (item[key] != null) stub[key] = item[key];
  }
  return customerBookingPublishedDriverCard(stub);
}

/// Keep only fields the public publication contract already allows.
Map<String, dynamic> customerBookingPublishedDriverCard(
  Map<String, dynamic> driver,
) {
  final profileOn =
      driver['public_profile_enabled'] == true ||
      driver['publicProfileEnabled'] == true ||
      (driver['public_display_name'] ?? driver['publicDisplayName'] ?? '')
          .toString()
          .trim()
          .isNotEmpty;
  final photoOn =
      driver['public_photo_enabled'] == true ||
      driver['publicPhotoEnabled'] == true;
  final publicName =
      (driver['public_display_name'] ?? driver['publicDisplayName'] ?? '')
          .toString()
          .trim();
  final publicPhoto =
      (driver['public_photo_url'] ?? driver['publicPhotoUrl'] ?? '')
          .toString()
          .trim();
  final allowedPhoto = publicPhoto.isNotEmpty
      ? publicPhoto
      : (photoOn
            ? (driver['driver_photo_url'] ??
                      driver['driverPhotoUrl'] ??
                      driver['photo_url'] ??
                      driver['portrait_url'] ??
                      '')
                  .toString()
                  .trim()
            : '');
  final firstName =
      (driver['first_name'] ??
              driver['firstName'] ??
              driver['given_name'] ??
              '')
          .toString()
          .trim();
  final id = companyAgendaDriverId(driver);
  return <String, dynamic>{
    if (id.isNotEmpty) 'driver_id': id,
    if (firstName.isNotEmpty && !companyPlanLooksLikeInternalId(firstName))
      'first_name': firstName,
    if (profileOn && publicName.isNotEmpty) ...<String, dynamic>{
      'public_display_name': publicName,
      'display_name': publicName,
    },
    if (allowedPhoto.isNotEmpty) ...<String, dynamic>{
      'public_photo_url': allowedPhoto,
      'photo_url': allowedPhoto,
    },
  };
}

String customerBookingAllowedDriverPhotoUrl(Map<String, dynamic> driver) {
  for (final key in const <String>[
    'public_photo_url',
    'publicPhotoUrl',
    'driver_photo_url',
    'driverPhotoUrl',
    'photo_url',
    'photoUrl',
    'portrait_url',
    'portraitUrl',
  ]) {
    final url = (driver[key] ?? '').toString().trim();
    if (url.isEmpty) continue;
    if (key.startsWith('public') ||
        driver['public_photo_enabled'] == true ||
        driver['publicPhotoEnabled'] == true ||
        url.startsWith('http://') ||
        url.startsWith('https://') ||
        url.startsWith('/')) {
      return url;
    }
  }
  return '';
}

List<Map<String, dynamic>> customerBookingMergePublishedDrivers({
  required List<Map<String, dynamic>> companyDrivers,
  required List<Map<String, dynamic>> snapshotDrivers,
}) {
  final byId = <String, Map<String, dynamic>>{};
  void add(Map<String, dynamic> driver) {
    final id = companyAgendaDriverId(driver);
    if (id.isEmpty) return;
    final current = byId[id];
    if (current == null) {
      byId[id] = Map<String, dynamic>.from(driver);
      return;
    }
    final merged = Map<String, dynamic>.from(current);
    driver.forEach((key, value) {
      if (value == null) return;
      final text = value.toString().trim();
      if (text.isEmpty) return;
      final existing = (merged[key] ?? '').toString().trim();
      if (existing.isEmpty) merged[key] = value;
    });
    final incomingPhoto = customerBookingAllowedDriverPhotoUrl(driver);
    if (incomingPhoto.isNotEmpty) {
      merged['public_photo_url'] = incomingPhoto;
      merged['photo_url'] = incomingPhoto;
    }
    byId[id] = merged;
  }

  for (final driver in companyDrivers) {
    add(driver);
  }
  for (final driver in snapshotDrivers) {
    add(driver);
  }
  return byId.values.toList(growable: false);
}

CustomerBookingAvailabilitySnapshot parseCustomerBookingAvailability(
  Object? decoded,
) {
  if (decoded is! Map) {
    return const CustomerBookingAvailabilitySnapshot(
      loadFailed: true,
      fetched: true,
    );
  }
  final root = Map<String, dynamic>.from(decoded);
  if (root['ok'] == false) {
    return const CustomerBookingAvailabilitySnapshot(
      loadFailed: true,
      fetched: true,
    );
  }
  final rows = root['vehicles'];
  if (rows is! List) {
    return const CustomerBookingAvailabilitySnapshot(
      loadFailed: true,
      fetched: true,
    );
  }
  final available = <String>{};
  final unavailable = <String>{};
  final reasons = <String, String>{};
  final drivers = <String, String>{};
  final records = <Map<String, dynamic>>[];
  final seenDrivers = <String>{};
  for (final item in rows) {
    if (item is! Map) continue;
    final id = (item['vehicle_id'] ?? item['vehicleId'] ?? '')
        .toString()
        .trim();
    if (id.isEmpty) continue;
    final record = customerBookingAvailabilityDriverRecord(item);
    final driverId = record == null
        ? (item['driver_id'] ?? item['driverId'] ?? '').toString().trim()
        : companyAgendaDriverId(record);
    if (driverId.isNotEmpty) drivers[id] = driverId;
    if (record != null && driverId.isNotEmpty && seenDrivers.add(driverId)) {
      records.add(record);
    }
    if (item['available'] == true) {
      available.add(id);
    } else {
      unavailable.add(id);
      reasons[id] = (item['reason'] ?? '').toString();
    }
  }
  DateTime? expiresAt;
  final rawExpiry = root['expires_at'] ?? root['expiresAt'];
  if (rawExpiry != null) {
    expiresAt = DateTime.tryParse(rawExpiry.toString().trim())?.toUtc();
  }
  return CustomerBookingAvailabilitySnapshot(
    availableIds: available,
    unavailableIds: unavailable,
    reasons: reasons,
    driverIds: drivers,
    drivers: records,
    fetched: true,
    expiresAt: expiresAt,
  );
}

Future<CustomerBookingAvailabilitySnapshot> fetchCustomerBookingAvailability({
  required String bookingBaseUrl,
  required String partnerId,
  required DateTime pickupUtc,
  required int passengers,
  int durationMin = 30,
  int waitMin = 0,
  int returnDurationMin = 0,
  CustomerBookingProfileGet? httpGet,
}) async {
  final id = partnerId.trim();
  if (id.isEmpty || bookingBaseUrl.trim().isEmpty) {
    return const CustomerBookingAvailabilitySnapshot();
  }
  final uri = Uri.parse('$bookingBaseUrl/partners/availability').replace(
    queryParameters: <String, String>{
      'partner_id': id,
      'pickup_iso': pickupUtc.toUtc().toIso8601String(),
      'pax': '$passengers',
      'duration_min': '$durationMin',
      if (waitMin > 0) 'wait_min': '$waitMin',
      if (returnDurationMin > 0) 'return_duration_min': '$returnDurationMin',
    },
  );
  final getter = httpGet ?? http.get;
  final res = await getter(uri).timeout(const Duration(seconds: 12));
  if (res.statusCode != 200) {
    return const CustomerBookingAvailabilitySnapshot(
      loadFailed: true,
      fetched: true,
    );
  }
  return parseCustomerBookingAvailability(jsonDecode(res.body));
}

Future<List<Map<String, dynamic>>> fetchCustomerBookingCompanyVehicles({
  required String bookingBaseUrl,
  required String partnerId,
  CustomerBookingProfileGet? httpGet,
}) async {
  final snapshot = await fetchCustomerBookingCompanySnapshot(
    bookingBaseUrl: bookingBaseUrl,
    partnerId: partnerId,
    httpGet: httpGet,
  );
  return snapshot.vehicles;
}
