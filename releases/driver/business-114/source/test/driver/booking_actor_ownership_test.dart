import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/driver/booking_actor_ownership.dart';

void main() {
  bool owns(
    String driver,
    String assigned,
    String car, {
    String actorCar = 'shared-car',
  }) => driverBookingBelongsToActor(
    activeDriverId: driver,
    assignedDriverId: assigned,
    assignedVehicleId: car,
    activeVehicleId: actorCar,
    linkedVehicleIds: {'shared-car'},
  );
  test('shared vehicle never authorizes the other assigned driver', () {
    expect(owns('driver-2', 'driver-9', 'shared-car'), isFalse);
    expect(owns('driver-9', 'driver-9', 'shared-car'), isTrue);
    expect(owns('driver-2', 'driver-2', 'different-car'), isTrue);
  });
  test(
    'vehicle-only legacy records still require an identified scoped driver',
    () {
      expect(owns('driver-2', '', 'shared-car'), isTrue);
      expect(owns('driver-2', '', 'unrelated-car'), isFalse);
      expect(owns('', 'driver-9', 'shared-car'), isFalse);
      expect(owns('driver-2', '', ''), isFalse);
    },
  );
}
