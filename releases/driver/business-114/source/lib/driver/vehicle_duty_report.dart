/// Completed personal duty totals. These are not driving time or trip revenue.
class VehicleDutyReport {
  static String recoveryLabel(Map<String, dynamic> row) =>
      switch (row['recovery']?['reason']) {
        'device_lost' => 'Door bedrijf afgesloten: toestel verloren',
        'device_replaced' => 'Door bedrijf afgesloten: toestel vervangen',
        _ => '',
      };
  const VehicleDutyReport({
    required this.count,
    required this.elapsedMs,
    required this.pauseMs,
    required this.dutyMs,
    required this.complete,
  });
  final int count, elapsedMs, pauseMs, dutyMs;
  final bool complete;

  static void validateRow(dynamic row, String driverId) {
    if (row is! Map ||
        row['driver_id'] != driverId ||
        row['duty_id'] is! String ||
        (row['duty_id'] as String).isEmpty ||
        row['vehicle_id'] is! String ||
        (row['vehicle_id'] as String).isEmpty ||
        row['started_at_ms'] is! int ||
        row['ended_at_ms'] is! int) {
      throw const FormatException('invalid_duty_report');
    }
    final start = row['started_at_ms'] as int, end = row['ended_at_ms'] as int;
    final recovery = row['recovery'];
    if (recovery != null &&
        (recovery is! Map ||
            recovery['role'] != 'company_admin' ||
            !['device_lost', 'device_replaced'].contains(recovery['reason']) ||
            recovery['at_ms'] != end)) {
      throw const FormatException('invalid_duty_report');
    }
    final summary = row['summary'];
    if (start < 0 ||
        end < start ||
        summary is! Map ||
        summary['ok'] != true ||
        summary['driver_id'] != driverId ||
        summary['vehicle_id'] != row['vehicle_id'] ||
        summary['duty_id'] != row['duty_id']) {
      throw const FormatException('invalid_duty_report');
    }
    final elapsed = summary['elapsed_ms'],
        pause = summary['pause_ms'],
        duty = summary['duty_ms'];
    if (elapsed is! int ||
        pause is! int ||
        duty is! int ||
        elapsed != end - start ||
        pause < 0 ||
        duty < 0 ||
        pause + duty != elapsed) {
      throw const FormatException('invalid_duty_report');
    }
  }

  factory VehicleDutyReport.fromRows(
    List<Map<String, dynamic>> rows, {
    required String driverId,
    required bool complete,
  }) {
    var elapsed = 0, pause = 0, duty = 0;
    final ids = <String>{};
    for (final row in rows) {
      validateRow(row, driverId);
      if (!ids.add(row['duty_id'] as String))
        throw const FormatException('duplicate_duty_report');
      final summary = row['summary'] as Map;
      elapsed += summary['elapsed_ms'] as int;
      pause += summary['pause_ms'] as int;
      duty += summary['duty_ms'] as int;
    }
    return VehicleDutyReport(
      count: rows.length,
      elapsedMs: elapsed,
      pauseMs: pause,
      dutyMs: duty,
      complete: complete,
    );
  }
}
