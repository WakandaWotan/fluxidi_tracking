import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:fluxidi_tracking/company/company_driver_agenda_style.dart';
import 'package:fluxidi_tracking/company/company_plan_vehicle_fallback.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_company_vehicles.dart';

class CustomerRideAssignedVehicle {
  const CustomerRideAssignedVehicle({
    required this.id,
    this.label = '',
    this.plate = '',
    this.assetPath = '',
    this.photoUrl = '',
  });
  final String id, label, plate, assetPath, photoUrl;
}

/// Resolve published media for a whole company's fleet in one profile read.
/// The partner identity and each vehicle ID must match exactly; duplicate IDs
/// are discarded instead of selecting an arbitrary vehicle by list position.
Map<String, CustomerRideAssignedVehicle> customerPublishedVehicleMediaById({
  required Map<String, dynamic> profile,
  required String tenantId,
  required String companyId,
}) {
  final expected = 'company:${tenantId.trim()}:${companyId.trim()}';
  if (tenantId.trim().isEmpty ||
      companyId.trim().isEmpty ||
      (profile['partner_id'] ?? profile['partnerId'] ?? '').toString() !=
          expected) {
    return const {};
  }
  final raw =
      profile['vehicles'] ??
      profile['public_vehicles'] ??
      profile['publicVehicles'];
  if (raw is! List) return const {};
  final result = <String, CustomerRideAssignedVehicle>{};
  final duplicates = <String>{};
  for (final item in raw) {
    if (item is! Map) continue;
    final vehicle = Map<String, dynamic>.from(item);
    final id = (vehicle['vehicle_id'] ?? vehicle['vehicleId'] ?? '')
        .toString()
        .trim();
    if (id.isEmpty || duplicates.contains(id)) continue;
    if (result.containsKey(id)) {
      result.remove(id);
      duplicates.add(id);
      continue;
    }
    result[id] = CustomerRideAssignedVehicle(
      id: id,
      assetPath: customerSelectedVehicleFallbackAsset(vehicle) ?? '',
      photoUrl: customerBookingVehiclePhotoUrl(vehicle),
    );
  }
  return result;
}

/// A canonical assignment can contain only a vehicle ID. Resolve the exact
/// public vehicle record in the selected booking's company, including its
/// published image. The driver's default vehicle is not a booking assignment.
Future<CustomerRideAssignedVehicle?> customerRideResolveAssignedVehiclePublic({
  required CustomerRideAssignedVehicle? assigned,
  required String tenantId,
  required String companyId,
  required String bookingBaseUrl,
}) async {
  if (assigned == null ||
      assigned.id.trim().isEmpty ||
      tenantId.trim().isEmpty ||
      companyId.trim().isEmpty)
    return assigned;
  final partnerId = 'company:${tenantId.trim()}:${companyId.trim()}';
  final uri = Uri.parse(
    '$bookingBaseUrl/partners/profile',
  ).replace(queryParameters: {'partner_id': partnerId});
  try {
    final response = await http
        .get(uri, headers: const {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 6));
    if (response.statusCode != 200) return assigned;
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    if (body is! Map || body['ok'] != true || body['profile'] is! Map)
      return assigned;
    final profile = Map<String, dynamic>.from(body['profile'] as Map);
    if ((profile['partner_id'] ?? profile['partnerId'] ?? '').toString() !=
        partnerId)
      return assigned;
    final rawVehicles =
        profile['vehicles'] ??
        profile['public_vehicles'] ??
        profile['publicVehicles'];
    if (rawVehicles is! List) return assigned;
    final matches = rawVehicles
        .whereType<Map>()
        .map((raw) => Map<String, dynamic>.from(raw))
        .where(
          (vehicle) =>
              (vehicle['vehicle_id'] ?? vehicle['vehicleId'] ?? '')
                  .toString()
                  .trim() ==
              assigned.id,
        )
        .toList();
    if (matches.length != 1) return assigned;
    final vehicle = matches.single;
    String first(List<String> keys) {
      for (final key in keys) {
        final value = (vehicle[key] ?? '').toString().trim();
        if (value.isNotEmpty) return value;
      }
      return '';
    }

    final name = first(const [
      'name',
      'vehicle_name',
      'vehicleName',
      'display_name',
      'displayName',
      'brand_model',
      'brandModel',
    ]);
    final publicName = name.isNotEmpty && !companyPlanLooksLikeInternalId(name)
        ? name
        : '';
    final asset = customerSelectedVehicleFallbackAsset(vehicle);
    // Only an already published HTTPS vehicle image may be used here. Driver
    // portraits retain their separate consent path in live tracking.
    final photo = customerBookingVehiclePhotoUrl(vehicle);
    return CustomerRideAssignedVehicle(
      id: assigned.id,
      label: publicName.isNotEmpty ? publicName : assigned.label,
      plate: assigned.plate,
      assetPath: asset ?? assigned.assetPath,
      photoUrl: photo.isNotEmpty ? photo : assigned.photoUrl,
    );
  } catch (_) {
    return assigned;
  }
}

/// Only the vehicle explicitly assigned to the selected operational leg may
/// appear before the live customer projection supplies vehicle details.
CustomerRideAssignedVehicle? customerRideAssignedVehicleFromBooking({
  required String operationalLeg,
  required List<Map<String, dynamic>> legMaps,
  required List<Map<String, dynamic>> parentMaps,
}) {
  String read(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = (map[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  final parentVehicleId = operationalLeg == 'primary'
      ? parentMaps
                .map(
                  (map) => read(map, const [
                    'assigned_vehicle_id',
                    'assignedVehicleId',
                  ]),
                )
                .where((id) => id.isNotEmpty)
                .firstOrNull ??
            ''
      : '';
  final selected = <Map<String, dynamic>>[
    if (operationalLeg != 'primary')
      for (final leg in legMaps)
        if (read(leg, const ['leg_id', 'legId']) == operationalLeg) leg,
    if (operationalLeg == 'primary')
      for (final leg in legMaps)
        if (parentVehicleId.isNotEmpty &&
            read(leg, const ['assigned_vehicle_id', 'assignedVehicleId']) ==
                parentVehicleId)
          leg,
    if (operationalLeg == 'primary' &&
        parentVehicleId.isEmpty &&
        legMaps.length == 1)
      legMaps.single,
    if (operationalLeg == 'primary') ...parentMaps,
  ];
  for (final map in selected) {
    final id = read(map, const ['assigned_vehicle_id', 'assignedVehicleId']);
    if (id.isEmpty) continue;
    final raw = map['assigned_vehicle'] ?? map['assignedVehicle'];
    final vehicle = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    final nestedId = read(vehicle, const ['vehicle_id', 'vehicleId', 'id']);
    if (nestedId.isNotEmpty && nestedId != id) continue;
    final label = read(map, const [
      'assigned_vehicle_name',
      'assignedVehicleName',
      'assigned_vehicle_brand_model',
      'assignedVehicleBrandModel',
    ]);
    final nestedLabel = read(vehicle, const [
      'name',
      'display_name',
      'brand_model',
      'model',
    ]);
    return CustomerRideAssignedVehicle(
      id: id,
      label: label.isNotEmpty ? label : nestedLabel,
      plate: read(map, const [
        'assigned_vehicle_license_plate',
        'assignedVehicleLicensePlate',
      ]),
      assetPath: customerSelectedVehicleFallbackAsset(vehicle) ?? '',
      photoUrl: customerBookingVehiclePhotoUrl(vehicle),
    );
  }
  return null;
}

/// Only bundled IDs accepted by the published fleet contract may become
/// bundled image paths. Never interpret an arbitrary server string as a path.
String? customerSelectedVehicleFallbackAsset(Map<String, dynamic>? vehicle) {
  if (vehicle == null) return null;
  for (final key in const [
    'fallback_asset',
    'fallbackAsset',
    'vehicle_asset',
    'vehicleAsset',
    'asset_id',
    'assetId',
  ]) {
    final selected = (vehicle[key] ?? '').toString().trim();
    if (selected.isEmpty) continue;
    for (final asset in <String>[
      for (final category in kCompanyPlanFallbackCategories)
        companyPlanVehicleFallbackAsset(category),
      ...kCompanyPlanLimousineFallbackAssets,
    ]) {
      final basename = asset.split('/').last.split('.').first;
      if (selected == asset || selected == basename) return asset;
    }
  }
  return null;
}

/// A declared type can supply a neutral illustration when no per-vehicle
/// choice exists. Passenger count alone does not identify a vehicle type.
String? customerPublicVehicleFallbackAsset(Map<String, dynamic>? vehicle) {
  final selected = customerSelectedVehicleFallbackAsset(vehicle);
  if (selected != null) return selected;
  if (vehicle == null) return null;
  for (final key in const [
    'vehicle_type',
    'vehicleType',
    'type',
    'vehicle_class',
    'vehicleClass',
    'category',
  ]) {
    final category = companyPlanVehicleCategoryFromAlias(
      vehicle[key]?.toString(),
    );
    if (category != null) return companyPlanVehicleFallbackAsset(category);
  }
  return null;
}

/// A profile may show a driver beside a vehicle only with a public, exact ID
/// link. Names, array order and a one-vehicle profile are not assignments.
Map<String, dynamic>? customerPublicDriverForVehicle(
  Map<String, dynamic> vehicle,
  Iterable<Map<String, dynamic>> drivers,
) {
  final vehicleId = (vehicle['vehicle_id'] ?? vehicle['vehicleId'] ?? '')
      .toString()
      .trim();
  if (vehicleId.isEmpty) return null;
  final linkedDriverId =
      (vehicle['assigned_driver_id'] ??
              vehicle['assignedDriverId'] ??
              vehicle['driver_id'] ??
              '')
          .toString()
          .trim();
  final matches = <Map<String, dynamic>>[];
  for (final driver in drivers) {
    final driverId =
        (driver['driver_id'] ?? driver['driverId'] ?? driver['id'] ?? '')
            .toString()
            .trim();
    final driverVehicleId =
        (driver['assigned_vehicle_id'] ??
                driver['assignedVehicleId'] ??
                driver['vehicle_id'] ??
                '')
            .toString()
            .trim();
    if (linkedDriverId.isNotEmpty &&
        (driverId.isEmpty || driverId != linkedDriverId))
      continue;
    if (driverVehicleId.isNotEmpty && driverVehicleId != vehicleId) continue;
    if (linkedDriverId.isEmpty && driverVehicleId != vehicleId) continue;
    matches.add(driver);
  }
  return matches.length == 1 ? matches.single : null;
}
