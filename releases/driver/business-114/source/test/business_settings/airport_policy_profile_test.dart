import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';

void main() {
  test('airport choices survive the Business profile JSON roundtrip', () {
    final profile = BackendBusinessProfile.fromJson(const {
      'airport_scheduled_dispatch_mode': 'auto_available',
      'airport_out_of_area_mode': 'request_quote',
    });

    expect(profile.airportScheduledDispatchMode, 'auto_available');
    expect(profile.airportOutOfAreaMode, 'request_quote');
    final restored = BackendBusinessProfile.fromJson(profile.toJson());
    expect(restored.airportScheduledDispatchMode, 'auto_available');
    expect(restored.airportOutOfAreaMode, 'request_quote');
    expect(profile.toJson()['airport_scheduled_dispatch_mode'], 'auto_available');
    expect(profile.toJson()['airport_out_of_area_mode'], 'request_quote');
  });

  test('missing airport choices keep the existing client defaults', () {
    final profile = BackendBusinessProfile.fromJson(const {});
    expect(profile.airportScheduledDispatchMode, isEmpty);
    expect(profile.airportOutOfAreaMode, 'calculator');
  });
}
