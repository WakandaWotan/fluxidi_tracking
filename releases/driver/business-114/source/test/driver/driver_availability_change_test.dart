import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/driver/driver_duty_bridge.dart';

void main() {
  test('active offline chauffeur can request a new duty; offline never enables GPS or dispatch', () {
    expect(driverAvailabilityChangeBlocked(
      currentAvailability: 'offline', targetAvailability: 'available', isActive: true,
    ), isFalse);
    expect(DriverDutyBridge.availabilityAllowsGps('offline'), isFalse);
    expect(driverAvailabilityAllowsDispatch('offline'), isFalse);
  });

  for (final current in ['offline', 'paused', 'available']) {
    test('disabled account cannot become available from $current', () {
      expect(driverAvailabilityChangeBlocked(
        currentAvailability: current, targetAvailability: 'available', isActive: false,
      ), isTrue);
    });
  }

  test('explicit inactive status remains blocked despite stale active profile', () {
    for (final target in ['available', 'paused']) {
      expect(driverAvailabilityChangeBlocked(
        currentAvailability: 'inactive', targetAvailability: target, isActive: true,
      ), isTrue);
    }
  });

  test('ordinary pause and resume remain allowed for an active chauffeur', () {
    expect(driverAvailabilityChangeBlocked(
      currentAvailability: 'available', targetAvailability: 'paused', isActive: true,
    ), isFalse);
    expect(driverAvailabilityChangeBlocked(
      currentAvailability: 'paused', targetAvailability: 'available', isActive: true,
    ), isFalse);
    expect(driverAvailabilityAllowsDispatch('paused'), isFalse);
    expect(DriverDutyBridge.availabilityAllowsGps('paused'), isFalse);
  });
}
