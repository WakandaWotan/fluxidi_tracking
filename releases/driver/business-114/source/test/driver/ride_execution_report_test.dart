import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/driver/ride_execution_report.dart';

void main() {
  const identity = {
    'tenant_id': 'T',
    'company_id': 'C',
    'driver_id': 'tom',
    'vehicle_id': 'tesla',
    'duty_id': 'original-duty',
  };
  const row = {
    'driver_id': 'tom',
    'vehicle_id': 'tesla',
    'execution_identity': identity,
  };
  bool belongs(Map row, {String driver = 'tom'}) =>
      historyExecutionBelongsToDriver(
        row,
        tenantId: 'T',
        companyId: 'C',
        driverId: driver,
      );
  test('original chauffeur keeps historical ride after vehicle handover', () {
    expect(belongs({...row, 'current_vehicle_driver': 'bart'}), isTrue);
    expect(belongs(row, driver: 'bart'), isFalse);
  });
  test('foreign scope and mismatched vehicle or duty cannot count in KPIs', () {
    for (final patch in [
      {'company_id': 'other'},
      {'tenant_id': 'other'},
      {'vehicle_id': 'vito'},
      {'duty_id': ''},
    ]) {
      expect(
        belongs({
          ...row,
          'execution_identity': {...identity, ...patch},
        }),
        isFalse,
      );
    }
    expect(belongs({...row, 'execution_identity': 'invalid'}), isFalse);
  });
  test('legacy history has no new duty requirement', () {
    expect(belongs({'driver_id': 'tom'}), isTrue);
  });
}
