import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/company/company_operating_policy.dart';

void main() {
  test('old profiles do not introduce new operating choices', () {
    final profile = BackendBusinessProfile.fromJson(const {});
    expect(profile.operatingPolicy, isNull);
    expect(profile.toJson().containsKey('operating_policy'), false);
  });
  test('configured preferences survive JSON and unrelated copyWith', () {
    final profile = BackendBusinessProfile.fromJson(const {'operating_policy': {
      'version': 1, 'device_binding': 'vehicle', 'availability_source': 'manual_duty',
      'scheduled_dispatch': 'manager_first', 'immediate_dispatch': 'driver_offer',
      'offer_response_seconds': 45, 'unanswered_offer': 'central',
    }});
    final restored = BackendBusinessProfile.fromJson(profile.copyWith(companyName:'Renamed').toJson());
    expect(restored.operatingPolicy!.deviceBinding, 'vehicle');
    expect(restored.operatingPolicy!.offerResponseSeconds, 45);
    expect(restored.operatingPolicy!.scheduledDispatch, 'manager_first');
    expect(profile.copyWith(clearOperatingPolicy:true).operatingPolicy, isNull);
  });
  test('automatic offers require settings and cannot silently invent a timeout', () {
    const draft=CompanyOperatingPolicy(immediateDispatch:'driver_offer');
    expect(draft.validationError,'offer_policy_incomplete');
    expect(()=>CompanyOperatingPolicy.fromJson(draft.toJson()),throwsFormatException);
    expect(draft.copyWith(offerResponseSeconds:30,unansweredOffer:'next_vehicle').validationError,isNull);
  });
  test('manager threshold roundtrip does not require or select a primary vehicle', () {
    const draft=CompanyOperatingPolicy(deviceBinding:'vehicle',availabilitySource:'manual_duty',
      immediateDispatch:'manager_above_threshold',primaryReviewAboveCents:2500,
      offerResponseSeconds:30,unansweredOffer:'central');
    final restored=CompanyOperatingPolicy.fromJson(draft.toJson());
    expect(restored.validationError,isNull);
    expect(restored.immediateDispatch,'manager_above_threshold');
    expect(restored.primaryReviewAboveCents,2500);
    expect(restored.primaryVehicleId,isNull);
  });

}
