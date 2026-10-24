import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/driver/vehicle_duty_report.dart';

Map<String, dynamic> row(String id, String vehicle) => {
  'driver_id': 'd',
  'vehicle_id': vehicle,
  'duty_id': id,
  'started_at_ms': 1000,
  'ended_at_ms': 3601000,
  'summary': {
    'ok': true,
    'driver_id': 'd',
    'vehicle_id': vehicle,
    'duty_id': id,
    'elapsed_ms': 3600000,
    'pause_ms': 600000,
    'duty_ms': 3000000,
  },
};

void main() {
  test(
    'company recovery is labelled without changing duration or personal ownership',
    () {
      final recovered = {
        ...row('a', 'v'),
        'recovery': {
          'role': 'company_admin',
          'reason': 'device_lost',
          'at_ms': 3601000,
        },
      };
      expect(
        VehicleDutyReport.recoveryLabel(recovered),
        'Door bedrijf afgesloten: toestel verloren',
      );
      expect(
        VehicleDutyReport.fromRows(
          [recovered],
          driverId: 'd',
          complete: true,
        ).dutyMs,
        3000000,
      );
      expect(
        () => VehicleDutyReport.fromRows(
          [
            {...recovered, 'recovery': 'malformed'},
          ],
          driverId: 'd',
          complete: true,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'personal totals combine different vehicles and remain distinct from driving time',
    () {
      final report = VehicleDutyReport.fromRows(
        [row('a', 'v1'), row('b', 'v2')],
        driverId: 'd',
        complete: false,
      );
      expect(report.count, 2);
      expect(report.elapsedMs, 7200000);
      expect(report.pauseMs, 1200000);
      expect(report.dutyMs, 6000000);
      expect(report.complete, false);
    },
  );
  test(
    'foreign chauffeur, inconsistent duration and duplicate pages cannot create totals',
    () {
      for (final changed in [
        {...row('a', 'v'), 'driver_id': 'other'},
        {...row('a', 'v'), 'ended_at_ms': 0},
        {
          ...row('a', 'v'),
          'summary': {...row('a', 'v')['summary'] as Map, 'pause_ms': -1},
        },
      ]) {
        expect(
          () => VehicleDutyReport.fromRows(
            [changed],
            driverId: 'd',
            complete: true,
          ),
          throwsFormatException,
        );
      }
      expect(
        () => VehicleDutyReport.fromRows(
          [row('a', 'v'), row('a', 'v')],
          driverId: 'd',
          complete: true,
        ),
        throwsFormatException,
      );
    },
  );
}
