import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String vehicleSource;

  setUpAll(() {
    vehicleSource = File('lib/vehicle_management_page.dart').readAsStringSync();
  });

  test('vehicle add at capacity uses extra-vehicle purchase, not only a snackbar', () {
    expect(vehicleSource.contains('_purchaseExtraVehicleSlotThenAllowCreate'), isTrue);
    expect(vehicleSource.contains('resolveCompanySubscriptionFiscalTreatment'), isTrue);
    expect(vehicleSource.contains('_confirmExtraVehiclePurchaseDialog'), isTrue);
    expect(vehicleSource.contains('openVatSettingsActionLabel'), isTrue);
    expect(vehicleSource.contains('mayOpenVehicleCreateForm'), isTrue);
    expect(vehicleSource.contains('_completeExtraVehicleActivationIfReady'), isTrue);
    expect(vehicleSource.contains('startCompanySubscriptionAddonCheckout'), isTrue);
    expect(
      vehicleSource.contains('_openVehicleEditor()'),
      isTrue,
    );
    expect(
      vehicleSource.contains('_awaitingExtraVehicleActivation'),
      isTrue,
    );
  });
}
