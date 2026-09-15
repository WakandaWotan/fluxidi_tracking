// COMPANY-AGENDA-P0 — propose a suitable driver/vehicle from the existing fleet.

import 'package:fluxidi_tracking/company/company_driver_agenda_style.dart';
import 'package:fluxidi_tracking/company/company_plan_vehicle_type.dart';

class CompanyPlanAssignmentProposal {
  const CompanyPlanAssignmentProposal({
    required this.driverId,
    required this.vehicleId,
  });

  final String driverId;
  final String vehicleId;
}

List<String> companyAgendaDriverLinkedVehicleIds(Map<String, dynamic> raw) {
  final ids = <String>{};
  void add(Object? value) {
    if (value is List) {
      for (final item in value) {
        add(item);
      }
      return;
    }
    if (value is Map) {
      final nested = companyAgendaVehicleId(Map<String, dynamic>.from(value));
      if (nested.isNotEmpty) ids.add(nested);
      return;
    }
    final text = value?.toString().trim() ?? '';
    if (text.isNotEmpty) ids.add(text);
  }

  add(raw['vehicle_id']);
  add(raw['vehicleId']);
  add(raw['linked_vehicle_id']);
  add(raw['linkedVehicleId']);
  add(raw['assigned_vehicle_id']);
  add(raw['assignedVehicleId']);
  add(raw['vehicle_ids']);
  add(raw['vehicleIds']);
  add(raw['linked_vehicle_ids']);
  add(raw['linkedVehicleIds']);
  add(raw['vehicles']);
  return ids.toList();
}

CompanyPlanAssignmentProposal proposeCompanyPlanAssignment({
  required List<Map<String, dynamic>> drivers,
  required List<Map<String, dynamic>> vehicles,
  required CompanyPlanVehicleType type,
  required int passengers,
  required bool userPickedDriver,
  required bool userPickedVehicle,
  required String currentDriverId,
  required String currentVehicleId,
}) {
  final suitableDrivers = [
    for (final driver in drivers)
      if (companyAgendaDriverIsSuitable(driver)) driver,
  ];
  final typedVehicles = companyPlanVehiclesForType(
    vehicles: vehicles,
    type: type,
    passengers: passengers,
  );

  var driverId = currentDriverId.trim();
  var vehicleId = currentVehicleId.trim();

  if (!userPickedDriver) {
    driverId = suitableDrivers.isEmpty
        ? ''
        : companyAgendaDriverId(suitableDrivers.first);
  } else if (driverId.isNotEmpty &&
      !suitableDrivers.any(
        (driver) => companyAgendaDriverId(driver) == driverId,
      )) {
    driverId = '';
  }

  if (!userPickedVehicle) {
    Map<String, dynamic>? selectedDriver;
    for (final driver in suitableDrivers) {
      if (companyAgendaDriverId(driver) == driverId) {
        selectedDriver = driver;
        break;
      }
    }
    final linked = selectedDriver == null
        ? const <String>[]
        : companyAgendaDriverLinkedVehicleIds(selectedDriver);
    final linkedSuitable = [
      for (final vehicle in typedVehicles)
        if (linked.contains(companyAgendaVehicleId(vehicle))) vehicle,
    ];
    if (linkedSuitable.length == 1) {
      vehicleId = companyAgendaVehicleId(linkedSuitable.first);
    } else if (linked.isEmpty && typedVehicles.length == 1) {
      vehicleId = companyAgendaVehicleId(typedVehicles.first);
    } else if (vehicleId.isNotEmpty &&
        !typedVehicles.any(
          (vehicle) => companyAgendaVehicleId(vehicle) == vehicleId,
        )) {
      vehicleId = '';
    } else if (linkedSuitable.length > 1) {
      if (vehicleId.isEmpty ||
          !linkedSuitable.any(
            (vehicle) => companyAgendaVehicleId(vehicle) == vehicleId,
          )) {
        vehicleId = '';
      }
    }
  } else if (vehicleId.isNotEmpty &&
      !typedVehicles.any(
        (vehicle) => companyAgendaVehicleId(vehicle) == vehicleId,
      )) {
    vehicleId = '';
  }

  return CompanyPlanAssignmentProposal(
    driverId: driverId,
    vehicleId: vehicleId,
  );
}
