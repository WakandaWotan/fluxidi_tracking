// Four independent facets behind one driver card.
//
// They are deliberately separate because they answer different questions and
// have different evidence:
//   * connection — did the device report in recently?
//   * duty       — what did the driver themself press?
//   * planning   — what does the roster say?
//   * ride       — what is assigned right now and next?
//
// A missing connection never becomes "not working", and a roster block never
// becomes "live".

import 'package:fluxidi_tracking/company/company_driver_schedule.dart';
import 'package:fluxidi_tracking/company/company_timezone.dart';

/// Device link, judged only on the last real signal from the driver.
enum CompanyDriverConnectionState {
  /// A recent signal from the driver's device.
  live,

  /// There was a signal, but it is older than the staleness window.
  staleOrLost,

  /// No signal was ever recorded — not the same as disconnected.
  unknown,
}

/// Duty state, judged only on the driver's own start/pause/resume/stop.
enum CompanyDriverDutyState { working, onBreak, dutyEnded, unknown }

/// Where "Laatst bijgewerkt" came from, so the UI never presents a screen
/// refresh as a new signal from the driver.
enum CompanyDriverUpdateSource { driverSignal, none }

class CompanyDriverStatusFacets {
  const CompanyDriverStatusFacets({
    required this.connection,
    required this.duty,
    required this.schedule,
    required this.lastDriverSignalUtc,
    required this.updateSource,
    this.plannedWindowLabel = '',
  });

  final CompanyDriverConnectionState connection;
  final CompanyDriverDutyState duty;
  final CompanyDriverScheduleState schedule;

  /// Timestamp of the last real driver signal. Null when none was recorded.
  final DateTime? lastDriverSignalUtc;
  final CompanyDriverUpdateSource updateSource;

  /// `18:00–02:00`, or empty when no roster applies today.
  final String plannedWindowLabel;

  bool get hasRoster => schedule != CompanyDriverScheduleState.noSchedule;
}

/// Connection from the last driver signal alone.
CompanyDriverConnectionState companyDriverConnectionState({
  required DateTime? lastSignalUtc,
  required DateTime nowUtc,
  Duration staleAfter = const Duration(minutes: 15),
}) {
  if (lastSignalUtc == null) return CompanyDriverConnectionState.unknown;
  final age = nowUtc.difference(lastSignalUtc);
  if (age.isNegative) return CompanyDriverConnectionState.live;
  return age > staleAfter
      ? CompanyDriverConnectionState.staleOrLost
      : CompanyDriverConnectionState.live;
}

/// Duty from the driver's own controls. Connection is intentionally not an
/// input: a driver who started a shift stays "working" while their phone is
/// out of coverage, and an idle account never becomes "working" on its own.
CompanyDriverDutyState companyDriverDutyState({
  required String rawWorkStatus,
  String rawPresenceLabel = '',
}) {
  final status = rawWorkStatus.trim().toLowerCase();
  final presence = rawPresenceLabel.trim().toLowerCase();
  for (final value in <String>[status, presence]) {
    switch (value) {
      case 'paused':
      case 'on_break':
      case 'break':
      case 'pauze':
        return CompanyDriverDutyState.onBreak;
      case 'available':
      case 'online':
      case 'busy':
      case 'on_trip':
      case 'driving':
      case 'working':
        return CompanyDriverDutyState.working;
      case 'offline':
      case 'offline_work':
      case 'unavailable':
      case 'shift_ended':
      case 'duty_ended':
        return CompanyDriverDutyState.dutyEnded;
    }
  }
  return CompanyDriverDutyState.unknown;
}

/// Combines the facets without letting any of them overrule another.
CompanyDriverStatusFacets companyDriverStatusFacets({
  required DateTime? lastSignalUtc,
  required DateTime nowUtc,
  required String rawWorkStatus,
  String rawPresenceLabel = '',
  CompanyDriverSchedule? schedule,
  Duration staleAfter = const Duration(minutes: 15),
}) {
  final scheduleState = companyDriverScheduleStateAt(
    schedule: schedule,
    atUtc: nowUtc,
  );
  // Without an exact timezone the hours cannot be placed on a clock, so no
  // window is shown rather than one computed from the device.
  final windows =
      schedule == null ||
          schedule.isEmpty ||
          scheduleState == CompanyDriverScheduleState.unresolvableTimezone
      ? const <CompanyDriverScheduleWindow>[]
      : companyDriverScheduleWindowsForDay(
          schedule: schedule,
          localDay: companyDriverScheduleLocalDay(schedule, nowUtc),
        );
  return CompanyDriverStatusFacets(
    connection: companyDriverConnectionState(
      lastSignalUtc: lastSignalUtc,
      nowUtc: nowUtc,
      staleAfter: staleAfter,
    ),
    duty: companyDriverDutyState(
      rawWorkStatus: rawWorkStatus,
      rawPresenceLabel: rawPresenceLabel,
    ),
    schedule: scheduleState,
    lastDriverSignalUtc: lastSignalUtc,
    updateSource: lastSignalUtc == null
        ? CompanyDriverUpdateSource.none
        : CompanyDriverUpdateSource.driverSignal,
    plannedWindowLabel: windows.isEmpty
        ? ''
        : windows.map((w) => w.clockRange).join(' · '),
  );
}

/// Company-local calendar day for an instant, used to pick today's windows.
DateTime companyDriverScheduleLocalDay(
  CompanyDriverSchedule schedule,
  DateTime atUtc,
) {
  final local = companyTimezoneUtcToLocal(atUtc, schedule.timezone);
  return DateTime(local.year, local.month, local.day);
}
