// Driver working-hours schedule (uurrooster) shared by Chauffeursbeheer, the
// "Chauffeurs nu" strip and the ride planner's availability check.
//
// This layer is pure data + time maths. It never claims a driver is live: a
// schedule only says someone is *planned* to work. Actual duty state keeps
// coming from the driver's own controls (start/pause/resume/stop).

import 'package:fluxidi_tracking/company/company_timezone.dart';

/// What a schedule says about one moment.
enum CompanyDriverScheduleState {
  /// No schedule stored for this driver — keep the previous way of working.
  noSchedule,

  /// A schedule exists but its timezone cannot be converted exactly, so the
  /// hours cannot be placed on the timeline. Distinct from [noSchedule]: the
  /// driver does have working hours, we just cannot say where they fall.
  unresolvableTimezone,

  /// Inside a working block.
  scheduled,

  /// Inside a planned break within a working block.
  onPlannedBreak,

  /// Schedule exists but this moment falls outside every block.
  offHours,

  /// A date exception blocks the whole day (leave / absence).
  absent,
}

/// Why a driver cannot take a ride at the requested moment.
enum CompanyDriverScheduleConflict {
  none,
  noSchedule,
  outsideWorkingHours,
  plannedBreak,
  absent,
  rideEndsAfterWorkingHours,

  /// The roster's timezone is not supported, so availability cannot be
  /// established. This is never treated as permission to assign.
  undeterminable,
}

/// Minutes from local midnight. [endMinute] may exceed 1440 for a block that
/// runs past midnight (18:00–02:00 is 1080 → 1560).
class CompanyDriverShiftBlock {
  const CompanyDriverShiftBlock({
    required this.startMinute,
    required this.endMinute,
    this.breaks = const <CompanyDriverShiftBreak>[],
  });

  final int startMinute;
  final int endMinute;
  final List<CompanyDriverShiftBreak> breaks;

  bool get crossesMidnight => endMinute > 1440;
  int get durationMinutes => endMinute - startMinute;
  bool get isValid =>
      startMinute >= 0 && endMinute > startMinute && endMinute <= 2880;

  static CompanyDriverShiftBlock? fromJson(Map<String, dynamic> raw) {
    final start = companyDriverScheduleMinuteOfDay(
      raw['start'] ?? raw['start_time'] ?? raw['startTime'],
    );
    final end = companyDriverScheduleMinuteOfDay(
      raw['end'] ?? raw['end_time'] ?? raw['endTime'],
    );
    if (start == null || end == null) return null;
    // 18:00–02:00 arrives as 1080 and 120; the end belongs to the next day.
    final normalizedEnd = end <= start ? end + 1440 : end;
    final rawBreaks = raw['breaks'];
    final breaks = <CompanyDriverShiftBreak>[];
    if (rawBreaks is List) {
      for (final item in rawBreaks) {
        if (item is! Map) continue;
        final parsed = CompanyDriverShiftBreak.fromJson(
          Map<String, dynamic>.from(item),
          blockStartMinute: start,
        );
        if (parsed != null) breaks.add(parsed);
      }
    }
    final block = CompanyDriverShiftBlock(
      startMinute: start,
      endMinute: normalizedEnd,
      breaks: List<CompanyDriverShiftBreak>.unmodifiable(breaks),
    );
    return block.isValid ? block : null;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'start': companyDriverScheduleClock(startMinute),
    'end': companyDriverScheduleClock(endMinute),
    if (breaks.isNotEmpty)
      'breaks': <Map<String, dynamic>>[for (final b in breaks) b.toJson()],
  };
}

/// A planned break, stored in the same minute space as its block so an
/// overnight block keeps its break on the correct side of midnight.
class CompanyDriverShiftBreak {
  const CompanyDriverShiftBreak({
    required this.startMinute,
    required this.endMinute,
  });

  final int startMinute;
  final int endMinute;

  bool get isValid => endMinute > startMinute;

  static CompanyDriverShiftBreak? fromJson(
    Map<String, dynamic> raw, {
    required int blockStartMinute,
  }) {
    final start = companyDriverScheduleMinuteOfDay(
      raw['start'] ?? raw['start_time'] ?? raw['startTime'],
    );
    final end = companyDriverScheduleMinuteOfDay(
      raw['end'] ?? raw['end_time'] ?? raw['endTime'],
    );
    if (start == null || end == null) return null;
    final normalizedStart = start < blockStartMinute ? start + 1440 : start;
    final normalizedEnd = end <= start ? end + 1440 : end;
    final shifted = normalizedStart > start
        ? normalizedEnd + (normalizedStart - start)
        : normalizedEnd;
    final result = CompanyDriverShiftBreak(
      startMinute: normalizedStart,
      endMinute: shifted,
    );
    return result.isValid ? result : null;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'start': companyDriverScheduleClock(startMinute),
    'end': companyDriverScheduleClock(endMinute),
  };
}

/// A date-specific override: leave, absence or different hours.
class CompanyDriverScheduleException {
  const CompanyDriverScheduleException({
    required this.date,
    required this.blocksDay,
    this.blocks = const <CompanyDriverShiftBlock>[],
    this.reasonCode = '',
  });

  /// Local calendar date in the company timezone (time part ignored).
  final DateTime date;

  /// True for leave / absence: the whole day is blocked regardless of blocks.
  final bool blocksDay;
  final List<CompanyDriverShiftBlock> blocks;
  final String reasonCode;

  static CompanyDriverScheduleException? fromJson(Map<String, dynamic> raw) {
    final dateText = (raw['date'] ?? raw['day'] ?? '').toString().trim();
    final parsed = DateTime.tryParse(dateText);
    if (parsed == null) return null;
    final kind = (raw['kind'] ?? raw['type'] ?? '').toString().trim().toLowerCase();
    final rawBlocks = raw['blocks'] ?? raw['hours'];
    final blocks = <CompanyDriverShiftBlock>[];
    if (rawBlocks is List) {
      for (final item in rawBlocks) {
        if (item is! Map) continue;
        final block = CompanyDriverShiftBlock.fromJson(
          Map<String, dynamic>.from(item),
        );
        if (block != null) blocks.add(block);
      }
    }
    final blocksDay =
        kind == 'leave' ||
        kind == 'verlof' ||
        kind == 'absent' ||
        kind == 'afwezig' ||
        kind == 'unavailable' ||
        (blocks.isEmpty && kind != 'custom_hours' && kind != 'hours');
    return CompanyDriverScheduleException(
      date: DateTime(parsed.year, parsed.month, parsed.day),
      blocksDay: blocksDay,
      blocks: List<CompanyDriverShiftBlock>.unmodifiable(blocks),
      reasonCode: kind,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'date': companyDriverScheduleDateKey(date),
    'kind': reasonCode.isNotEmpty
        ? reasonCode
        : (blocksDay ? 'absent' : 'custom_hours'),
    if (blocks.isNotEmpty)
      'blocks': <Map<String, dynamic>>[for (final b in blocks) b.toJson()],
  };
}

/// A driver's recurring working hours plus date exceptions.
class CompanyDriverSchedule {
  const CompanyDriverSchedule({
    required this.driverId,
    required this.timezone,
    this.weekdayBlocks = const <int, List<CompanyDriverShiftBlock>>{},
    this.exceptions = const <CompanyDriverScheduleException>[],
    this.updatedAtUtc,
    this.explicitlySet = false,
  });

  final String driverId;

  /// IANA zone name of the company (e.g. `Europe/Brussels`).
  final String timezone;

  /// Keyed by [DateTime.weekday] (1 = Monday … 7 = Sunday).
  final Map<int, List<CompanyDriverShiftBlock>> weekdayBlocks;
  final List<CompanyDriverScheduleException> exceptions;
  final DateTime? updatedAtUtc;

  /// True when the administrator saved this roster, even if every day is empty.
  ///
  /// Distinct from [isEmpty]: a never-set roster is not a refusal, a saved
  /// empty week is.
  final bool explicitlySet;

  /// No recurring hours and no exceptions.
  bool get isEmpty => weekdayBlocks.values.every((b) => b.isEmpty) &&
      exceptions.isEmpty;

  /// Whether dispatch may treat this as a real roster.
  bool get isConfigured => explicitlySet || !isEmpty;

  static CompanyDriverSchedule? fromJson(Map<String, dynamic> raw) {
    final driverId = (raw['driver_id'] ?? raw['driverId'] ?? '')
        .toString()
        .trim();
    if (driverId.isEmpty) return null;
    final timezone = (raw['timezone'] ?? raw['time_zone'] ?? raw['tz'] ?? '')
        .toString()
        .trim();
    final weekdayBlocks = <int, List<CompanyDriverShiftBlock>>{};
    final rawWeek = raw['weekdays'] ?? raw['weekday_blocks'] ?? raw['week'];
    if (rawWeek is Map) {
      for (final entry in rawWeek.entries) {
        final weekday = companyDriverScheduleWeekday(entry.key);
        if (weekday == null) continue;
        final rawBlocks = <Map<String, dynamic>>[];
        if (entry.value is List) {
          for (final item in entry.value as List) {
            if (item is Map) {
              rawBlocks.add(Map<String, dynamic>.from(item));
            }
          }
        } else if (entry.value is Map) {
          rawBlocks.add(Map<String, dynamic>.from(entry.value as Map));
        } else {
          continue;
        }
        final blocks = <CompanyDriverShiftBlock>[];
        for (final item in rawBlocks) {
          final block = CompanyDriverShiftBlock.fromJson(item);
          if (block != null) blocks.add(block);
        }
        blocks.sort((a, b) => a.startMinute.compareTo(b.startMinute));
        weekdayBlocks[weekday] = List<CompanyDriverShiftBlock>.unmodifiable(
          blocks,
        );
      }
    }
    final exceptions = <CompanyDriverScheduleException>[];
    final rawExceptions = raw['exceptions'] ?? raw['overrides'];
    if (rawExceptions is List) {
      for (final item in rawExceptions) {
        if (item is! Map) continue;
        final parsed = CompanyDriverScheduleException.fromJson(
          Map<String, dynamic>.from(item),
        );
        if (parsed != null) exceptions.add(parsed);
      }
    }
    return CompanyDriverSchedule(
      driverId: driverId,
      timezone: timezone.isEmpty ? kCompanyDefaultTimezone : timezone,
      weekdayBlocks: Map<int, List<CompanyDriverShiftBlock>>.unmodifiable(
        weekdayBlocks,
      ),
      exceptions: List<CompanyDriverScheduleException>.unmodifiable(exceptions),
      updatedAtUtc: DateTime.tryParse(
        (raw['updated_at'] ?? raw['updatedAt'] ?? '').toString().trim(),
      )?.toUtc(),
      explicitlySet:
          raw['explicitly_set'] == true ||
          raw['explicitlySet'] == true ||
          raw['configured'] == true ||
          raw['present'] == true,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'driver_id': driverId,
    'timezone': timezone,
    'weekdays': <String, dynamic>{
      for (final entry in weekdayBlocks.entries)
        '${entry.key}': <Map<String, dynamic>>[
          for (final block in entry.value) block.toJson(),
        ],
    },
    'exceptions': <Map<String, dynamic>>[
      for (final exception in exceptions) exception.toJson(),
    ],
    if (updatedAtUtc != null) 'updated_at': updatedAtUtc!.toIso8601String(),
    'explicitly_set': explicitlySet,
  };

  CompanyDriverSchedule copyWith({
    String? driverId,
    String? timezone,
    Map<int, List<CompanyDriverShiftBlock>>? weekdayBlocks,
    List<CompanyDriverScheduleException>? exceptions,
    DateTime? updatedAtUtc,
    bool? explicitlySet,
  }) {
    return CompanyDriverSchedule(
      driverId: driverId ?? this.driverId,
      timezone: timezone ?? this.timezone,
      weekdayBlocks: weekdayBlocks ?? this.weekdayBlocks,
      exceptions: exceptions ?? this.exceptions,
      updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
      explicitlySet: explicitlySet ?? this.explicitlySet,
    );
  }
}

/// Reads `weekly_roster` / `driver_schedule` from a company driver record.
CompanyDriverSchedule? companyDriverScheduleFromDriverRecord(
  Map<String, dynamic> raw,
) {
  final driverId = (raw['driver_id'] ?? raw['driverId'] ?? '').toString().trim();
  if (driverId.isEmpty) return null;
  final scheduleRaw = raw['driver_schedule'] ?? raw['driverSchedule'];
  if (scheduleRaw is Map) {
    final parsed = CompanyDriverSchedule.fromJson(
      <String, dynamic>{
        'driver_id': driverId,
        ...Map<String, dynamic>.from(scheduleRaw),
      },
    );
    if (parsed != null) return parsed;
  }
  final roster = raw['weekly_roster'] ?? raw['weeklyRoster'];
  if (roster is! Map) {
    return CompanyDriverSchedule(
      driverId: driverId,
      timezone: kCompanyDefaultTimezone,
    );
  }
  final map = Map<String, dynamic>.from(roster);
  final days = map['days'];
  final weekdays = <String, dynamic>{};
  const keys = <String>['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
  if (days is Map) {
    for (var index = 0; index < keys.length; index += 1) {
      weekdays['${index + 1}'] = days[keys[index]];
    }
  }
  return CompanyDriverSchedule.fromJson(<String, dynamic>{
    'driver_id': driverId,
    'timezone': (map['timezone'] ?? map['time_zone'] ?? kCompanyDefaultTimezone)
        .toString(),
    'weekdays': weekdays.isEmpty ? map['weekdays'] ?? map['weekday_blocks'] : weekdays,
    'exceptions': raw['roster_exceptions'] ??
        raw['rosterExceptions'] ??
        map['exceptions'],
    'explicitly_set': map['explicitly_set'] ?? map['explicitlySet'],
  });
}

Map<String, CompanyDriverSchedule> companyDriverSchedulesFromRecords(
  List<Map<String, dynamic>> drivers,
) {
  final out = <String, CompanyDriverSchedule>{};
  for (final driver in drivers) {
    final parsed = companyDriverScheduleFromDriverRecord(driver);
    if (parsed == null) continue;
    out[parsed.driverId] = parsed;
  }
  return out;
}

/// A concrete working window on the timeline, in UTC.
class CompanyDriverScheduleWindow {
  const CompanyDriverScheduleWindow({
    required this.startUtc,
    required this.endUtc,
    required this.breaks,
    required this.localStartMinute,
    required this.localEndMinute,
  });

  final DateTime startUtc;
  final DateTime endUtc;
  final List<({DateTime startUtc, DateTime endUtc})> breaks;
  final int localStartMinute;
  final int localEndMinute;

  bool contains(DateTime utc) =>
      !utc.isBefore(startUtc) && utc.isBefore(endUtc);

  bool isInBreak(DateTime utc) {
    for (final slot in breaks) {
      if (!utc.isBefore(slot.startUtc) && utc.isBefore(slot.endUtc)) {
        return true;
      }
    }
    return false;
  }

  /// `18:00–02:00` for the planner's "werkuren vandaag" line.
  String get clockRange =>
      '${companyDriverScheduleClock(localStartMinute)}–'
      '${companyDriverScheduleClock(localEndMinute)}';
}

/// Every working window that touches the company-local calendar day of
/// [localDay]. A block started the previous evening is included so a night
/// shift is visible on the day it ends too.
List<CompanyDriverScheduleWindow> companyDriverScheduleWindowsForDay({
  required CompanyDriverSchedule schedule,
  required DateTime localDay,
}) {
  final day = DateTime(localDay.year, localDay.month, localDay.day);
  final windows = <CompanyDriverScheduleWindow>[];
  for (final offset in const <int>[-1, 0]) {
    final base = day.add(Duration(days: offset));
    for (final block in _blocksForLocalDate(schedule, base)) {
      final window = _windowForBlock(
        schedule: schedule,
        localDate: base,
        block: block,
      );
      final endsBeforeDay = !window.endUtc.isAfter(
        companyTimezoneLocalToUtc(day, schedule.timezone),
      );
      final startsAfterDay = !window.startUtc.isBefore(
        companyTimezoneLocalToUtc(day.add(const Duration(days: 1)), schedule.timezone),
      );
      if (endsBeforeDay || startsAfterDay) continue;
      windows.add(window);
    }
  }
  windows.sort((a, b) => a.startUtc.compareTo(b.startUtc));
  return windows;
}

List<CompanyDriverShiftBlock> _blocksForLocalDate(
  CompanyDriverSchedule schedule,
  DateTime localDate,
) {
  for (final exception in schedule.exceptions) {
    if (exception.date.year != localDate.year ||
        exception.date.month != localDate.month ||
        exception.date.day != localDate.day) {
      continue;
    }
    if (exception.blocksDay) return const <CompanyDriverShiftBlock>[];
    return exception.blocks;
  }
  return schedule.weekdayBlocks[localDate.weekday] ??
      const <CompanyDriverShiftBlock>[];
}

CompanyDriverScheduleWindow _windowForBlock({
  required CompanyDriverSchedule schedule,
  required DateTime localDate,
  required CompanyDriverShiftBlock block,
}) {
  DateTime toUtc(int minuteOfDay) {
    final extraDays = minuteOfDay ~/ 1440;
    final minute = minuteOfDay % 1440;
    final local = DateTime(
      localDate.year,
      localDate.month,
      localDate.day + extraDays,
      minute ~/ 60,
      minute % 60,
    );
    return companyTimezoneLocalToUtc(local, schedule.timezone);
  }

  return CompanyDriverScheduleWindow(
    startUtc: toUtc(block.startMinute),
    endUtc: toUtc(block.endMinute),
    breaks: <({DateTime startUtc, DateTime endUtc})>[
      for (final slot in block.breaks)
        (startUtc: toUtc(slot.startMinute), endUtc: toUtc(slot.endMinute)),
    ],
    localStartMinute: block.startMinute,
    localEndMinute: block.endMinute,
  );
}

/// What the schedule says at [atUtc]. Never reports live presence.
CompanyDriverScheduleState companyDriverScheduleStateAt({
  required CompanyDriverSchedule? schedule,
  required DateTime atUtc,
}) {
  if (schedule == null || !schedule.isConfigured) {
    return CompanyDriverScheduleState.noSchedule;
  }
  // The device clock is not a stand-in for the company timezone: using it
  // would place the shift on the wrong hours.
  if (!companyTimezoneIsResolvable(schedule.timezone)) {
    return CompanyDriverScheduleState.unresolvableTimezone;
  }
  final localDay = companyTimezoneUtcToLocal(atUtc, schedule.timezone);
  final windows = companyDriverScheduleWindowsForDay(
    schedule: schedule,
    localDay: localDay,
  );
  for (final window in windows) {
    if (!window.contains(atUtc)) continue;
    return window.isInBreak(atUtc)
        ? CompanyDriverScheduleState.onPlannedBreak
        : CompanyDriverScheduleState.scheduled;
  }
  final blockedDay = schedule.exceptions.any(
    (exception) =>
        exception.blocksDay &&
        exception.date.year == localDay.year &&
        exception.date.month == localDay.month &&
        exception.date.day == localDay.day,
  );
  return blockedDay
      ? CompanyDriverScheduleState.absent
      : CompanyDriverScheduleState.offHours;
}

/// Whether the schedule allows a ride that runs [rideStartUtc] → [rideEndUtc],
/// including the approach time the planner already computes.
///
/// A driver inside working hours is not automatically free: existing rides and
/// vehicle rules stay the caller's responsibility. This only answers the
/// schedule question and names the conflict.
CompanyDriverScheduleConflict companyDriverScheduleConflictFor({
  required CompanyDriverSchedule? schedule,
  required DateTime rideStartUtc,
  required DateTime rideEndUtc,
  Duration approach = Duration.zero,
}) {
  if (schedule == null || !schedule.isConfigured) {
    return CompanyDriverScheduleConflict.noSchedule;
  }
  // Unknown timezone means unknown availability, which must block rather than
  // silently allow an assignment computed on the device clock.
  if (!companyTimezoneIsResolvable(schedule.timezone)) {
    return CompanyDriverScheduleConflict.undeterminable;
  }
  final from = rideStartUtc.subtract(approach);
  final localDay = companyTimezoneUtcToLocal(from, schedule.timezone);
  final windows = <CompanyDriverScheduleWindow>[
    ...companyDriverScheduleWindowsForDay(
      schedule: schedule,
      localDay: localDay,
    ),
    ...companyDriverScheduleWindowsForDay(
      schedule: schedule,
      localDay: localDay.add(const Duration(days: 1)),
    ),
  ];
  for (final window in windows) {
    if (from.isBefore(window.startUtc)) continue;
    if (from.isAfter(window.endUtc) || from == window.endUtc) continue;
    if (rideEndUtc.isAfter(window.endUtc)) {
      return CompanyDriverScheduleConflict.rideEndsAfterWorkingHours;
    }
    for (final slot in window.breaks) {
      final overlapsBreak =
          from.isBefore(slot.endUtc) && rideEndUtc.isAfter(slot.startUtc);
      if (overlapsBreak) return CompanyDriverScheduleConflict.plannedBreak;
    }
    return CompanyDriverScheduleConflict.none;
  }
  final blockedDay = schedule.exceptions.any(
    (exception) =>
        exception.blocksDay &&
        exception.date.year == localDay.year &&
        exception.date.month == localDay.month &&
        exception.date.day == localDay.day,
  );
  return blockedDay
      ? CompanyDriverScheduleConflict.absent
      : CompanyDriverScheduleConflict.outsideWorkingHours;
}

/// `18:00` for 1080, `02:00` for 1560 (next-day minutes wrap).
String companyDriverScheduleClock(int minuteOfDay) {
  final wrapped = minuteOfDay % 1440;
  final hh = (wrapped ~/ 60).toString().padLeft(2, '0');
  final mm = (wrapped % 60).toString().padLeft(2, '0');
  return '$hh:$mm';
}

String companyDriverScheduleDateKey(DateTime date) {
  final mm = date.month.toString().padLeft(2, '0');
  final dd = date.day.toString().padLeft(2, '0');
  return '${date.year}-$mm-$dd';
}

/// Accepts `18:00`, `1800`, `18`, `18:00:00` and plain minute counts.
int? companyDriverScheduleMinuteOfDay(Object? raw) {
  if (raw is num) {
    final value = raw.toInt();
    return value >= 0 && value <= 2880 ? value : null;
  }
  final text = (raw ?? '').toString().trim();
  if (text.isEmpty) return null;
  final colon = RegExp(r'^(\d{1,2}):(\d{2})(?::\d{2})?$').firstMatch(text);
  if (colon != null) {
    final h = int.parse(colon.group(1)!);
    final m = int.parse(colon.group(2)!);
    if (h > 24 || m > 59) return null;
    return h * 60 + m;
  }
  final compact = RegExp(r'^(\d{2})(\d{2})$').firstMatch(text);
  if (compact != null) {
    final h = int.parse(compact.group(1)!);
    final m = int.parse(compact.group(2)!);
    if (h > 24 || m > 59) return null;
    return h * 60 + m;
  }
  final hourOnly = int.tryParse(text);
  if (hourOnly != null && hourOnly >= 0 && hourOnly <= 24) {
    return hourOnly * 60;
  }
  return null;
}

/// Maps `1`, `mon`, `monday`, `maandag` to [DateTime.weekday].
int? companyDriverScheduleWeekday(Object? raw) {
  final text = (raw ?? '').toString().trim().toLowerCase();
  if (text.isEmpty) return null;
  final numeric = int.tryParse(text);
  if (numeric != null) return numeric >= 1 && numeric <= 7 ? numeric : null;
  const names = <String, int>{
    'mon': 1, 'monday': 1, 'ma': 1, 'maandag': 1,
    'tue': 2, 'tuesday': 2, 'di': 2, 'dinsdag': 2,
    'wed': 3, 'wednesday': 3, 'wo': 3, 'woensdag': 3,
    'thu': 4, 'thursday': 4, 'do': 4, 'donderdag': 4,
    'fri': 5, 'friday': 5, 'vr': 5, 'vrijdag': 5,
    'sat': 6, 'saturday': 6, 'za': 6, 'zaterdag': 6,
    'sun': 7, 'sunday': 7, 'zo': 7, 'zondag': 7,
  };
  return names[text];
}
