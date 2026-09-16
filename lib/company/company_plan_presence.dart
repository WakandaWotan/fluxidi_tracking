// COMPANY-AGENDA-P0 — presence tone from existing eligibility/availability codes.

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_agenda_labels.dart';
import 'package:fluxidi_tracking/company/company_dispatch.dart';
import 'package:fluxidi_tracking/company/company_driver_schedule.dart';
import 'package:fluxidi_tracking/company/company_driver_agenda_style.dart';
import 'package:fluxidi_tracking/company/company_plan_when.dart';

enum CompanyPlanPresenceTone { available, busy, blocked, unknown }

class CompanyPlanPresence {
  const CompanyPlanPresence({
    required this.tone,
    required this.code,
    required this.icon,
    this.busyUntil,
  });

  final CompanyPlanPresenceTone tone;
  final String code;
  final IconData icon;
  final DateTime? busyUntil;

  bool get suitable => tone == CompanyPlanPresenceTone.available;
}

const Color kCompanyPlanPresenceGreen = Color(0xFF2E7D32);
const Color kCompanyPlanPresenceOrange = Color(0xFFED6C02);
const Color kCompanyPlanPresenceRed = Color(0xFFC62828);
const Color kCompanyPlanPresenceGrey = Color(0xFF607D8B);

Color companyPlanPresenceColor(CompanyPlanPresenceTone tone) {
  return switch (tone) {
    CompanyPlanPresenceTone.available => kCompanyPlanPresenceGreen,
    CompanyPlanPresenceTone.busy => kCompanyPlanPresenceOrange,
    CompanyPlanPresenceTone.blocked => kCompanyPlanPresenceRed,
    CompanyPlanPresenceTone.unknown => kCompanyPlanPresenceGrey,
  };
}

String companyPlanPresenceLabel(
  CompanyPlanPresence presence,
  AppLanguage language, {
  DateTime? plannedLocal,
  bool durationKnown = true,
}) {
  switch (presence.code) {
    case 'available':
      if (!durationKnown) {
        return kCompanyAgendaAvailabilityUnknown.of(language);
      }
      return kCompanyDriverPresenceAvailable.of(language);
    case 'on_trip':
    case 'assignment_driver_on_trip':
      if (presence.busyUntil != null) {
        return kCompanyAgendaBusyMaybeFree
            .of(language)
            .replaceAll('{time}', companyPlanFormatClock(presence.busyUntil!));
      }
      return kCompanyDriverPresenceOnTrip.of(language);
    case 'assignment_overlap':
      return kCompanyAgendaOverlapBlocked.of(language);
    case 'assignment_vehicle_busy':
    case 'assignment_vehicle_overlap':
      return kCompanyAgendaVehicleOccupied.of(language);
    case 'assignment_capacity':
      return kCompanyAgendaCapacityShort.of(language);
    case 'assignment_driver_cannot_reach':
    case 'cannot_reach':
      return kCompanyAgendaCannotReachPickup.of(language);
    case 'assignment_driver_inactive':
    case 'assignment_driver_blocked':
      return kCompanyAgendaDriverInactive.of(language);
    case 'assignment_driver_not_scheduled':
      return kCompanyAgendaOffDuty.of(language);
    case 'assignment_driver_outside_hours':
      return kCompanyDriverConflictOutsideHours.of(language);
    case 'assignment_driver_planned_break':
      return kCompanyDriverConflictBreak.of(language);
    case 'assignment_driver_absent':
      return kCompanyDriverConflictAbsent.of(language);
    case 'assignment_ride_after_hours':
      return kCompanyDriverConflictEndsAfterHours.of(language);
    case 'assignment_schedule_undeterminable':
      return kCompanyDriverScheduleUndeterminable.of(language);
    case 'assignment_driver_paused':
      return kCompanyDriverPresencePaused.of(language);
    case 'assignment_driver_offline':
    case 'assignment_driver_not_live':
    case 'scheduled_no_live':
      return kCompanyDriverPresenceScheduledNoLive.of(language);
    case 'assignment_driver_no_vehicle':
    case 'assignment_vehicle_unavailable':
      return kCompanyAgendaDriverNoVehicle.of(language);
    default:
      if (presence.tone == CompanyPlanPresenceTone.blocked) {
        return kCompanyAgendaOverlapBlocked.of(language);
      }
      if (presence.tone == CompanyPlanPresenceTone.busy) {
        return kCompanyDriverPresenceOnTrip.of(language);
      }
      return presence.tone == CompanyPlanPresenceTone.unknown
          ? kCompanyAgendaAvailabilityUnknown.of(language)
          : kCompanyDriverPresenceAvailable.of(language);
  }
}

CompanyPlanPresence resolveCompanyPlanPresence({
  required Map<String, dynamic> driver,
  String overlapCode = '',
  bool whenNow = true,
  int passengers = 1,
  List<Map<String, dynamic>> vehicles = const <Map<String, dynamic>>[],
  DateTime? busyUntil,
  DateTime? lastSeenUtc,
  DateTime? nowUtc,
  CompanyDriverSchedule? schedule,
  DateTime? rideStartUtc,
  DateTime? rideEndUtc,
  Duration approach = Duration.zero,
}) {
  if (!companyAgendaDriverIsActive(driver)) {
    return const CompanyPlanPresence(
      tone: CompanyPlanPresenceTone.blocked,
      code: 'assignment_driver_inactive',
      icon: Icons.person_off_outlined,
    );
  }
  if (overlapCode == 'assignment_overlap' ||
      overlapCode == 'assignment_vehicle_overlap') {
    return const CompanyPlanPresence(
      tone: CompanyPlanPresenceTone.blocked,
      code: 'assignment_overlap',
      icon: Icons.event_busy_outlined,
    );
  }
  if (overlapCode == 'assignment_vehicle_busy') {
    return const CompanyPlanPresence(
      tone: CompanyPlanPresenceTone.blocked,
      code: 'assignment_vehicle_busy',
      icon: Icons.directions_car_filled_outlined,
    );
  }
  if (overlapCode == 'assignment_driver_cannot_reach' ||
      overlapCode == 'cannot_reach') {
    return const CompanyPlanPresence(
      tone: CompanyPlanPresenceTone.blocked,
      code: 'assignment_driver_cannot_reach',
      icon: Icons.near_me_disabled_outlined,
    );
  }
  // The roster can only refuse, never grant: a driver inside working hours is
  // still subject to every rule below. A driver without a roster keeps the
  // exact behaviour they had before schedules existed.
  final scheduleBlock = _schedulePresenceBlock(
    schedule: schedule,
    rideStartUtc: rideStartUtc,
    rideEndUtc: rideEndUtc,
    approach: approach,
  );
  if (scheduleBlock != null) return scheduleBlock;

  final status = (driver['availability_status'] ??
          driver['availabilityStatus'] ??
          driver['presence_label'] ??
          '')
      .toString()
      .trim()
      .toLowerCase();
  if (status == 'on_trip' || status == 'busy') {
    return CompanyPlanPresence(
      tone: CompanyPlanPresenceTone.busy,
      code: 'on_trip',
      icon: Icons.alt_route_outlined,
      busyUntil: busyUntil,
    );
  }
  if (status == 'paused') {
    return const CompanyPlanPresence(
      tone: CompanyPlanPresenceTone.blocked,
      code: 'assignment_driver_paused',
      icon: Icons.pause_circle_outline,
    );
  }
  final linked = [
    for (final vehicle in vehicles)
      if (companyAgendaVehicleIsSuitable(vehicle, passengers: passengers))
        vehicle,
  ];
  if (linked.isEmpty && vehicles.isNotEmpty) {
    final anyFit = vehicles.any(
      (vehicle) => companyAgendaVehicleFitsPassengers(vehicle, passengers),
    );
    return CompanyPlanPresence(
      tone: CompanyPlanPresenceTone.blocked,
      code: anyFit
          ? 'assignment_driver_no_vehicle'
          : 'assignment_capacity',
      icon: anyFit
          ? Icons.no_transfer_outlined
          : Icons.event_seat_outlined,
    );
  }
  final live = lastSeenUtc == null
      ? true
      : companyDispatchIsLive(
          lastSeenUtc: lastSeenUtc,
          nowUtc: nowUtc ?? DateTime.now().toUtc(),
        );
  if (whenNow && !live && status != 'available' && status != 'online') {
    return const CompanyPlanPresence(
      tone: CompanyPlanPresenceTone.unknown,
      code: 'assignment_driver_not_live',
      icon: Icons.signal_wifi_off_outlined,
    );
  }
  if (status == 'offline' || status == 'offline_work') {
    return CompanyPlanPresence(
      tone: whenNow
          ? CompanyPlanPresenceTone.unknown
          : CompanyPlanPresenceTone.available,
      code: whenNow ? 'assignment_driver_offline' : 'available',
      icon: whenNow
          ? Icons.bedtime_outlined
          : Icons.check_circle_outline,
    );
  }
  final hasLiveField = driver.containsKey('last_seen_at') ||
      driver.containsKey('lastSeenAt') ||
      driver.containsKey('availability_status') ||
      driver.containsKey('availabilityStatus') ||
      driver.containsKey('presence_label');
  if (status.isEmpty) {
    if (!hasLiveField) {
      return const CompanyPlanPresence(
        tone: CompanyPlanPresenceTone.available,
        code: 'available',
        icon: Icons.check_circle_outline,
      );
    }
    return CompanyPlanPresence(
      tone: whenNow
          ? CompanyPlanPresenceTone.unknown
          : CompanyPlanPresenceTone.available,
      code: whenNow ? 'scheduled_no_live' : 'available',
      icon: whenNow
          ? Icons.help_outline
          : Icons.check_circle_outline,
    );
  }
  if (status == 'available' || status == 'online') {
    return const CompanyPlanPresence(
      tone: CompanyPlanPresenceTone.available,
      code: 'available',
      icon: Icons.check_circle_outline,
    );
  }
  return const CompanyPlanPresence(
    tone: CompanyPlanPresenceTone.unknown,
    code: 'scheduled_no_live',
    icon: Icons.help_outline,
  );
}

/// Blocks the assignment when the roster refuses this ride, or null when the
/// roster has nothing to say (including when no roster is stored).
CompanyPlanPresence? _schedulePresenceBlock({
  required CompanyDriverSchedule? schedule,
  required DateTime? rideStartUtc,
  required DateTime? rideEndUtc,
  required Duration approach,
}) {
  if (schedule == null || !schedule.isConfigured) return null;
  if (schedule.isEmpty) {
    return const CompanyPlanPresence(
      tone: CompanyPlanPresenceTone.blocked,
      code: 'assignment_driver_not_scheduled',
      icon: Icons.event_busy_outlined,
    );
  }
  if (rideStartUtc == null) return null;
  final conflict = companyDriverScheduleConflictFor(
    schedule: schedule,
    rideStartUtc: rideStartUtc,
    rideEndUtc: rideEndUtc ?? rideStartUtc,
    approach: approach,
  );
  switch (conflict) {
    case CompanyDriverScheduleConflict.outsideWorkingHours:
      return const CompanyPlanPresence(
        tone: CompanyPlanPresenceTone.blocked,
        code: 'assignment_driver_outside_hours',
        icon: Icons.schedule_outlined,
      );
    case CompanyDriverScheduleConflict.plannedBreak:
      return const CompanyPlanPresence(
        tone: CompanyPlanPresenceTone.blocked,
        code: 'assignment_driver_planned_break',
        icon: Icons.free_breakfast_outlined,
      );
    case CompanyDriverScheduleConflict.absent:
      return const CompanyPlanPresence(
        tone: CompanyPlanPresenceTone.blocked,
        code: 'assignment_driver_absent',
        icon: Icons.event_busy_outlined,
      );
    case CompanyDriverScheduleConflict.rideEndsAfterWorkingHours:
      return const CompanyPlanPresence(
        tone: CompanyPlanPresenceTone.blocked,
        code: 'assignment_ride_after_hours',
        icon: Icons.nightlight_outlined,
      );
    case CompanyDriverScheduleConflict.undeterminable:
      return const CompanyPlanPresence(
        tone: CompanyPlanPresenceTone.blocked,
        code: 'assignment_schedule_undeterminable',
        icon: Icons.help_outline,
      );
    case CompanyDriverScheduleConflict.noSchedule:
    case CompanyDriverScheduleConflict.none:
      return null;
  }
}

class CompanyPlanPresenceChip extends StatelessWidget {
  const CompanyPlanPresenceChip({
    super.key,
    required this.presence,
    required this.language,
  });

  final CompanyPlanPresence presence;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final color = companyPlanPresenceColor(presence.tone);
    final label = companyPlanPresenceLabel(presence, language);
    return Semantics(
      label: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(presence.icon, size: 16, color: color),
          const SizedBox(width: 4),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
