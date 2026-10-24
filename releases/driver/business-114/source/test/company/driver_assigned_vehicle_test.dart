import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/company/driver_assigned_vehicle.dart';

DriverProfile driver(String id, {String? assignedVehicleId}) => DriverProfile(
  id: id,
  fullName: id,
  employeeNumber: id,
  phone: '',
  isActive: true,
  companyId: 'taxi-mario',
  assignedVehicleId: assignedVehicleId,
);

VehicleProfile vehicle(String id, {String? companyId, String? driverId}) =>
    VehicleProfile(
      id: id,
      vehicleName: id,
      brandModel: 'Toyota Corolla',
      licensePlate: '',
      color: '',
      passengerCapacity: 4,
      luggageCapacity: 3,
      tierId: 'comfort',
      isActive: true,
      driverId: driverId,
      companyId: companyId,
      primaryPhotoRef: '',
      galleryPhotoRefs: const [],
    );

void main() {
  bool inTaxiMario(VehicleProfile v) => v.companyId == 'taxi-mario';

  test('shift driver sees the exact assigned car even when reverse link names another driver', () {
    final cars = [
      vehicle('corolla', companyId: 'taxi-mario', driverId: 'driver-2'),
    ];
    final selected = assignedVehicleForDriver(
      driver('driver-9', assignedVehicleId: 'corolla'),
      cars,
      inCompany: inTaxiMario,
    );
    expect(selected?.id, 'corolla');
  });

  test('explicit assignment never falls back to another car or company', () {
    final cars = [
      vehicle('corolla', companyId: 'other-company', driverId: 'driver-9'),
      vehicle('vito', companyId: 'taxi-mario', driverId: 'driver-9'),
    ];
    final selected = assignedVehicleForDriver(
      driver('driver-9', assignedVehicleId: 'corolla'),
      cars,
      inCompany: inTaxiMario,
    );
    expect(selected, isNull);
  });

  test('legacy reverse link is used only when assignment is absent', () {
    final cars = [
      vehicle('other', companyId: 'other-company', driverId: 'driver-9'),
      vehicle('corolla', companyId: 'taxi-mario', driverId: 'driver-9'),
    ];
    final selected = assignedVehicleForDriver(
      driver('driver-9'),
      cars,
      inCompany: inTaxiMario,
    );
    expect(selected?.id, 'corolla');
  });

  test('one vehicle shows all shift drivers and excludes other companies', () {
    final car = vehicle('corolla', companyId: 'taxi-mario', driverId: 'driver-1');
    final drivers = [
      driver('driver-1', assignedVehicleId: 'corolla'),
      driver('driver-9', assignedVehicleId: 'corolla'),
      driver('driver-17', assignedVehicleId: 'corolla'),
      driver('driver-20', assignedVehicleId: 'vito'),
      driver('other', assignedVehicleId: 'corolla').copyWith(companyId: 'other-company'),
    ];
    expect(
      driversAssignedToVehicle(
        car,
        drivers,
        inCompany: (d) => d.companyId == 'taxi-mario',
      ).map((d) => d.id),
      ['driver-1', 'driver-9', 'driver-17'],
    );
  });

  test('legacy reverse link cannot override an explicit different assignment', () {
    final car = vehicle('corolla', companyId: 'taxi-mario', driverId: 'driver-1');
    expect(
      driversAssignedToVehicle(
        car,
        [driver('driver-1', assignedVehicleId: 'vito')],
        inCompany: (_) => true,
      ),
      isEmpty,
    );
  });
}
