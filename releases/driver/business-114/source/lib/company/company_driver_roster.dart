// COMPANY-DISPATCH-P0 — weekly roster helpers for chauffeur work hours.

const String kCompanyDriverRosterTimezone = 'Europe/Brussels';
const List<String> kCompanyDriverRosterDays = <String>[
  'mon',
  'tue',
  'wed',
  'thu',
  'fri',
  'sat',
  'sun',
];

class CompanyRosterBlock {
  const CompanyRosterBlock({required this.start, required this.end});

  final String start;
  final String end;

  bool get isOvernight {
    return _minutes(start) != null &&
        _minutes(end) != null &&
        _minutes(start)! > _minutes(end)!;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'start': start,
    'end': end,
  };
}

int? _minutes(String raw) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(raw.trim());
  if (match == null) return null;
  final hour = int.tryParse(match.group(1)!);
  final minute = int.tryParse(match.group(2)!);
  if (hour == null || minute == null || hour > 23 || minute > 59) return null;
  return hour * 60 + minute;
}

Map<String, List<CompanyRosterBlock>> companyDriverRosterDaysFrom(
  Map<String, dynamic>? raw,
) {
  final source = <String, dynamic>{};
  if (raw != null) {
    final days = raw['days'];
    if (days is Map) {
      source.addAll(Map<String, dynamic>.from(days));
    } else {
      source.addAll(raw);
    }
  }
  return <String, List<CompanyRosterBlock>>{
    for (final day in kCompanyDriverRosterDays)
      day: [
        for (final row in (source[day] is List ? source[day] as List : const []))
          if (row is Map &&
              (row['start'] ?? '').toString().isNotEmpty &&
              (row['end'] ?? '').toString().isNotEmpty)
            CompanyRosterBlock(
              start: row['start'].toString(),
              end: row['end'].toString(),
            ),
      ],
  };
}

Map<String, dynamic> companyDriverRosterToJson({
  required Map<String, List<CompanyRosterBlock>> days,
  String timezone = kCompanyDriverRosterTimezone,
}) {
  return <String, dynamic>{
    'timezone': timezone,
    'days': <String, dynamic>{
      for (final day in kCompanyDriverRosterDays)
        day: [for (final block in days[day] ?? const []) block.toJson()],
    },
  };
}

Map<String, List<CompanyRosterBlock>> companyDriverCopyRosterDay({
  required Map<String, List<CompanyRosterBlock>> days,
  required String fromDay,
  required Iterable<String> toDays,
}) {
  final copied = <String, List<CompanyRosterBlock>>{
    for (final day in kCompanyDriverRosterDays)
      day: [...(days[day] ?? const <CompanyRosterBlock>[])],
  };
  final source = [...(copied[fromDay] ?? const <CompanyRosterBlock>[])];
  for (final day in toDays) {
    if (day == fromDay || !kCompanyDriverRosterDays.contains(day)) continue;
    copied[day] = [...source];
  }
  return copied;
}
