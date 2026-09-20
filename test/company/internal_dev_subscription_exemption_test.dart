import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/company/company_ops_api.dart';

void main() {
  test('other companies keep finite subscription limits', () {
    final profile = BackendSubscriptionProfile.fromJson(<String, dynamic>{
      'max_vehicles': 4,
      'max_drivers': 13,
    });
    expect(profile.isInternalDevAccount, isFalse);
    expect(profile.effectiveMaxVehicles, 4);
    expect(profile.effectiveMaxDrivers, 13);
    expect(
      companyOpsMaxVehicles(<String, dynamic>{'max_vehicles': 2}),
      2,
    );
  });

  test('internal development grant is unlimited and free of collection', () {
    final profile = BackendSubscriptionProfile.fromJson(<String, dynamic>{
      'internal_dev_account': true,
      'subscription_billing_exempt': true,
      'unlimited_vehicles': true,
      'unlimited_drivers': true,
      'max_vehicles': 4,
      'max_drivers': 13,
      'subscription_status': 'cancelled',
    });
    expect(profile.isInternalDevAccount, isTrue);
    expect(profile.effectiveMaxVehicles, 1000000);
    expect(profile.effectiveMaxDrivers, 1000000);
    expect(profile.maxVehicles, 4);
    expect(
      companyOpsMaxVehicles(<String, dynamic>{
        'internal_dev_account': true,
        'max_vehicles': 4,
      }),
      1000000,
    );
    expect(
      companyOpsMaxDrivers(<String, dynamic>{
        'unlimited_drivers': true,
        'max_drivers': 13,
      }),
      1000000,
    );
  });
}
