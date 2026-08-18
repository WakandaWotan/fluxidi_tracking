import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_entry.dart';

VehicleProfile _baseVehicle({
  String serviceCategory = '',
  String serviceClassId = '',
}) {
  return VehicleProfile(
    id: 'veh_1',
    vehicleName: 'Fleet One',
    brandModel: 'Mercedes S-Class',
    licensePlate: '1-ABC-123',
    color: 'Black',
    passengerCapacity: 3,
    luggageCapacity: 3,
    tierId: 'premium',
    isActive: true,
    driverId: null,
    primaryPhotoRef: '',
    galleryPhotoRefs: const <String>[],
    serviceCategory: serviceCategory,
    serviceClassId: serviceClassId,
  );
}

void main() {
  group('P1 vehicle classification model contract', () {
    test('defaults are empty (fails closed; no inference from brand/tier)', () {
      final v = _baseVehicle();
      expect(v.serviceCategory, '');
      expect(v.serviceClassId, '');
      // A premium Mercedes with no configured class is NOT a limousine class.
      expect(v.tierId, 'premium');
      expect(v.serviceClassId, isEmpty);
    });

    test('copyWith carries authoritative configured classification', () {
      final v = _baseVehicle().copyWith(
        serviceCategory: 'limousine',
        serviceClassId: 'executive_sedan',
      );
      expect(v.serviceCategory, 'limousine');
      expect(v.serviceClassId, 'executive_sedan');
      // Unrelated fields preserved.
      expect(v.tierId, 'premium');
      expect(v.isActive, isTrue);
    });

    test('customer-entry gate remains default off in P1', () {
      expect(LimousineCustomerEntryContract.isVisible, isFalse);
    });
  });
}
