import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_driver_agenda_style.dart';
import 'package:fluxidi_tracking/company/company_plan_media.dart';
import 'package:fluxidi_tracking/company/company_plan_vehicle_type.dart';
import 'package:fluxidi_tracking/nearby/public_partner_market.dart';
import 'package:fluxidi_tracking/payment/booking_payment_options.dart';

typedef CustomerBookingProfileGet = Future<http.Response> Function(Uri uri);

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
  return resolveCompanyPlanVehicleMedia(vehicle: vehicle).photoUrl.trim();
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
  final seats = vehicle == null ? 0 : companyAgendaVehicleCapacity(vehicle);
  final bags = vehicle == null ? 0 : companyAgendaVehicleBagCapacity(vehicle);
  if (seats > 0 && bags > 0) {
    return language == AppLanguage.en
        ? '$seats pax · $bags bags'
        : '$seats pax · $bags bagage';
  }
  if (seats > 0) {
    return language == AppLanguage.en ? '$seats passengers' : '$seats passagiers';
  }
  return companyPlanVehicleTypeCapacityLabel(
    companyPlanVehicleTypeForCategory(category),
    language,
  );
}

class CustomerBookingCompanySnapshot {
  const CustomerBookingCompanySnapshot({
    this.companyName = '',
    this.vehicles = const <Map<String, dynamic>>[],
    this.payment = const BookingPaymentCapability.unavailable(),
  });

  final String companyName;
  final List<Map<String, dynamic>> vehicles;
  final BookingPaymentCapability payment;
}

CustomerBookingCompanySnapshot customerBookingCompanySnapshotFromProfile(
  Map<String, dynamic> profile,
) {
  return CustomerBookingCompanySnapshot(
    companyName: customerBookingCompanyNameFromProfile(profile),
    vehicles: customerBookingVehiclesFromProfile(profile),
    payment: BookingPaymentCapability.fromPublicJson(profile),
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
  final uri = Uri.parse('$bookingBaseUrl/partners/profile').replace(
    queryParameters: <String, String>{
      'partner_id': id,
    },
  );
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
