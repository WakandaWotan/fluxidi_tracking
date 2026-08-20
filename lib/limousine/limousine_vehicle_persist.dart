// Bootstrap/reload helpers for limousine vehicle classification.
// Selection is keyed by stable VehicleProfile.id, never by object identity.

import '../app_config.dart';
import 'limousine_business_setup.dart';

class LimousineVehicleClassification {
  const LimousineVehicleClassification({
    this.serviceCategory = '',
    this.serviceClassId = '',
  });

  final String serviceCategory;
  final String serviceClassId;

  bool get isLimousine => serviceCategory == 'limousine';
}

LimousineVehicleClassification parseLimousineVehicleClassification(
  Map<String, dynamic> map,
) {
  final category = (map['service_category'] ?? map['serviceCategory'] ?? '')
      .toString()
      .trim()
      .toLowerCase();
  final classId =
      (map['service_class'] ??
              map['serviceClass'] ??
              map['service_class_id'] ??
              map['serviceClassId'] ??
              '')
          .toString()
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[\s-]+'), '_');
  return LimousineVehicleClassification(
    serviceCategory: category,
    serviceClassId: classId,
  );
}

VehicleProfile mergeBootstrapVehicleClassification({
  required VehicleProfile remote,
  required VehicleProfile local,
}) {
  return remote.copyWith(
    serviceCategory: remote.serviceCategory.trim().isNotEmpty
        ? remote.serviceCategory
        : local.serviceCategory,
    serviceClassId: remote.serviceClassId.trim().isNotEmpty
        ? remote.serviceClassId
        : local.serviceClassId,
  );
}

List<String> limousineSelectedVehicleIds(Iterable<VehicleProfile> vehicles) {
  final ids = <String>[];
  for (final vehicle in vehicles) {
    if (!limousineVehicleAppearsInLimousinePreview(vehicle)) continue;
    final id = vehicle.id.trim();
    if (id.isEmpty || ids.contains(id)) continue;
    ids.add(id);
  }
  return List<String>.from(ids, growable: false);
}

bool limousineSelectionSurvivesReload({
  required List<VehicleProfile> before,
  required List<VehicleProfile> after,
}) {
  final previous = limousineSelectedVehicleIds(before);
  final next = limousineSelectedVehicleIds(after);
  if (previous.length != next.length) return false;
  for (var i = 0; i < previous.length; i++) {
    if (previous[i] != next[i]) return false;
  }
  return true;
}

List<String> parsePersistedLimousineVehicleIds(Object? raw) {
  if (raw is! List) return const <String>[];
  final ids = <String>[];
  for (final item in raw) {
    final id = item.toString().trim();
    if (id.isEmpty || ids.contains(id)) continue;
    ids.add(id);
  }
  return List<String>.from(ids, growable: false);
}

List<VehicleProfile> restoreLimousineSelectionFromIds({
  required List<VehicleProfile> vehicles,
  required List<String> selectedIds,
  String fallbackClassId = '',
}) {
  if (selectedIds.isEmpty) return List<VehicleProfile>.from(vehicles);
  final ids = selectedIds.toSet();
  return vehicles
      .map((vehicle) {
        if (!ids.contains(vehicle.id.trim())) return vehicle;
        if (limousineVehicleAppearsInLimousinePreview(vehicle)) return vehicle;
        final classId = vehicle.serviceClassId.trim().isEmpty
            ? fallbackClassId
            : vehicle.serviceClassId;
        return vehicle.copyWith(
          serviceCategory: 'limousine',
          serviceClassId: classId,
        );
      })
      .toList(growable: false);
}
