import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';

void main() {
  test(
    'shared vehicle keeps every assigned driver selectable and rejects foreign assignment',
    () {
      final oldDrivers = driversNotifier.value;
      final oldVehicles = vehiclesNotifier.value;
      addTearDown(() {
        driversNotifier.value = oldDrivers;
        vehiclesNotifier.value = oldVehicles;
      });
      vehiclesNotifier.value = [
        const VehicleProfile(
          id: 'tesla',
          vehicleName: 'Tesla',
          brandModel: 'Tesla Model Y',
          licensePlate: '',
          color: '',
          passengerCapacity: 4,
          luggageCapacity: 3,
          tierId: 'comfort',
          isActive: true,
          driverId: 'd1',
          primaryPhotoRef: '',
          galleryPhotoRefs: [],
          companyId: 'mario',
        ),
      ];
      driversNotifier.value = [
        for (var i = 1; i <= 21; i++)
          DriverProfile(
            id: 'd$i',
            fullName: 'Driver $i',
            employeeNumber: 'E$i',
            phone: '',
            isActive: true,
            assignedVehicleId: 'tesla',
            companyId: 'mario',
          ),
      ];
      expect(
        resolveFleetVehicleIdForDriver('d11', companyId: 'mario'),
        'tesla',
      );
      expect(
        resolveOperationalCockpitEligibleDrivers(companyId: 'mario').length,
        21,
      );
      expect(
        resolveFleetVehicleIdForDriver('d11', companyId: 'foreign'),
        isNull,
      );
    },
  );
}
