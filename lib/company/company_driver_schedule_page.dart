// Uurrooster of one driver.
//
// The company administrator edits; a driver opening their own schedule sees
// the same data read-only. Saving hands the schedule back to the caller, which
// owns persistence and therefore the existing permission and company
// separation rules.

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_agenda_labels.dart';
import 'package:fluxidi_tracking/company/company_driver_schedule.dart';
import 'package:fluxidi_tracking/company/company_ops_theme.dart';
import 'package:fluxidi_tracking/company/company_timezone.dart';

const Key kCompanyDriverSchedulePageKey = Key('company_driver_schedule_page');
const Key kCompanyDriverScheduleSaveKey = Key('company_driver_schedule_save');
const Key kCompanyDriverScheduleReadOnlyKey = Key(
  'company_driver_schedule_read_only',
);
const Key kCompanyDriverScheduleTimezoneWarningKey = Key(
  'company_driver_schedule_timezone_warning',
);
const Key kCompanyDriverScheduleSaveUnavailableKey = Key(
  'company_driver_schedule_save_unavailable',
);

/// Stable driver identity used for the roster, taken from the record the
/// company already holds.
String companyDriverRecordId(Object? driver) {
  if (driver == null) return '';
  try {
    final dynamic d = driver;
    final id = (d.id ?? '').toString().trim();
    if (id.isNotEmpty) return id;
  } catch (_) {
    // Not a driver profile shape; fall through.
  }
  return '';
}

/// Entry point for one driver, used by Chauffeursbeheer and the agenda card.
Key companyDriverScheduleActionKey(String driverId) =>
    Key('company_driver_schedule_action_${driverId.trim()}');

/// Who may edit, following the existing roles: the company administrator
/// manages every driver; a driver may only view their own roster.
bool companyDriverScheduleCallerCanEdit({
  required bool isCompanyAdmin,
  required String callerDriverId,
  required String targetDriverId,
}) {
  if (isCompanyAdmin) return true;
  return false;
}

/// Whether this caller may open the roster at all.
bool companyDriverScheduleCallerCanView({
  required bool isCompanyAdmin,
  required String callerDriverId,
  required String targetDriverId,
}) {
  if (isCompanyAdmin) return true;
  final self = callerDriverId.trim();
  final target = targetDriverId.trim();
  return self.isNotEmpty && self == target;
}

Key companyDriverScheduleWeekdayKey(int weekday) =>
    Key('company_driver_schedule_weekday_$weekday');
Key companyDriverScheduleAddBlockKey(int weekday) =>
    Key('company_driver_schedule_add_block_$weekday');
Key companyDriverScheduleBlockKey(int weekday, int index) =>
    Key('company_driver_schedule_block_${weekday}_$index');
Key companyDriverScheduleRemoveBlockKey(int weekday, int index) =>
    Key('company_driver_schedule_remove_block_${weekday}_$index');

/// Opens the schedule editor and returns the saved schedule, or null when the
/// administrator backed out.
Future<CompanyDriverSchedule?> openCompanyDriverSchedulePage(
  BuildContext context, {
  required AppLanguage language,
  required CompanyDriverSchedule schedule,
  required String driverName,
  required bool canEdit,
  bool persistenceAvailable = false,
}) {
  return Navigator.of(context).push<CompanyDriverSchedule>(
    MaterialPageRoute<CompanyDriverSchedule>(
      builder: (_) => CompanyDriverSchedulePage(
        language: language,
        schedule: schedule,
        driverName: driverName,
        canEdit: canEdit,
        persistenceAvailable: persistenceAvailable,
      ),
    ),
  );
}

class CompanyDriverSchedulePage extends StatefulWidget {
  const CompanyDriverSchedulePage({
    super.key,
    required this.language,
    required this.schedule,
    required this.driverName,
    this.canEdit = true,
    this.persistenceAvailable = false,
  });

  final AppLanguage language;
  final CompanyDriverSchedule schedule;
  final String driverName;

  /// False for a driver viewing their own roster.
  final bool canEdit;

  /// Whether the Worker can store the roster for this caller.
  ///
  /// False when the load failed or the endpoint is unavailable, so the
  /// screen does not offer a button that looks like it worked.
  final bool persistenceAvailable;

  @override
  State<CompanyDriverSchedulePage> createState() =>
      _CompanyDriverSchedulePageState();
}

class _CompanyDriverSchedulePageState extends State<CompanyDriverSchedulePage> {
  late Map<int, List<CompanyDriverShiftBlock>> _weekdayBlocks;
  late List<CompanyDriverScheduleException> _exceptions;

  AppLanguage get _language => widget.language;

  @override
  void initState() {
    super.initState();
    _weekdayBlocks = <int, List<CompanyDriverShiftBlock>>{
      for (var weekday = 1; weekday <= 7; weekday += 1)
        weekday: List<CompanyDriverShiftBlock>.from(
          widget.schedule.weekdayBlocks[weekday] ??
              const <CompanyDriverShiftBlock>[],
        ),
    };
    _exceptions = List<CompanyDriverScheduleException>.from(
      widget.schedule.exceptions,
    );
  }

  CompanyDriverSchedule get _current => CompanyDriverSchedule(
    driverId: widget.schedule.driverId,
    timezone: widget.schedule.timezone,
    weekdayBlocks: <int, List<CompanyDriverShiftBlock>>{
      for (final entry in _weekdayBlocks.entries)
        if (entry.value.isNotEmpty) entry.key: entry.value,
    },
    exceptions: _exceptions,
    updatedAtUtc: DateTime.now().toUtc(),
    explicitlySet: true,
  );

  Future<void> _addBlock(int weekday) async {
    final start = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
      helpText: kCompanyDriverScheduleStartTime.of(_language),
    );
    if (start == null || !mounted) return;
    final end = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 17, minute: 0),
      helpText: kCompanyDriverScheduleEndTime.of(_language),
    );
    if (end == null || !mounted) return;
    final startMinute = start.hour * 60 + start.minute;
    final rawEnd = end.hour * 60 + end.minute;
    // An end at or before the start means the shift runs past midnight.
    final endMinute = rawEnd <= startMinute ? rawEnd + 1440 : rawEnd;
    setState(() {
      final blocks = _weekdayBlocks[weekday]!
        ..add(
          CompanyDriverShiftBlock(
            startMinute: startMinute,
            endMinute: endMinute,
          ),
        )
        ..sort((a, b) => a.startMinute.compareTo(b.startMinute));
      _weekdayBlocks[weekday] = blocks;
    });
  }

  void _removeBlock(int weekday, int index) {
    setState(() {
      final blocks = _weekdayBlocks[weekday]!;
      if (index >= 0 && index < blocks.length) blocks.removeAt(index);
    });
  }

  String _weekdayLabel(int weekday) {
    const labels = <int, LocalizedText>{
      1: kCompanyDriverScheduleMonday,
      2: kCompanyDriverScheduleTuesday,
      3: kCompanyDriverScheduleWednesday,
      4: kCompanyDriverScheduleThursday,
      5: kCompanyDriverScheduleFriday,
      6: kCompanyDriverScheduleSaturday,
      7: kCompanyDriverScheduleSunday,
    };
    return labels[weekday]!.of(_language);
  }

  String _blockLabel(CompanyDriverShiftBlock block) {
    final range =
        '${companyDriverScheduleClock(block.startMinute)}–'
        '${companyDriverScheduleClock(block.endMinute)}';
    if (!block.crossesMidnight) return range;
    return '$range · ${kCompanyDriverScheduleOvernight.of(_language)}';
  }

  @override
  Widget build(BuildContext context) {
    return CompanyOpsThemedSurface(
      child: Builder(builder: _buildThemed),
    );
  }

  Widget _buildThemed(BuildContext context) {
    final theme = Theme.of(context);
    final timezoneResolved = companyTimezoneIsResolvable(
      widget.schedule.timezone,
    );
    return Scaffold(
      key: kCompanyDriverSchedulePageKey,
      appBar: AppBar(
        title: Text(
          '${kCompanyDriverScheduleTitle.of(_language)} · ${widget.driverName}',
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Text(
              '${kCompanyDriverScheduleTimezone.of(_language)}: '
              '${widget.schedule.timezone}',
              style: theme.textTheme.bodySmall,
            ),
            if (!timezoneResolved) ...[
              const SizedBox(height: 6),
              Text(
                kCompanyDriverScheduleUndeterminable.of(_language),
                key: kCompanyDriverScheduleTimezoneWarningKey,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                kCompanyDriverScheduleTimezoneUnresolved.of(_language),
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (!widget.canEdit) ...[
              const SizedBox(height: 8),
              Text(
                kCompanyDriverScheduleReadOnly.of(_language),
                key: kCompanyDriverScheduleReadOnlyKey,
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            for (var weekday = 1; weekday <= 7; weekday += 1)
              _weekdayCard(theme, weekday),
            if (_exceptions.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                kCompanyDriverScheduleExceptions.of(_language),
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              for (final exception in _exceptions)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    exception.blocksDay
                        ? Icons.event_busy_outlined
                        : Icons.edit_calendar_outlined,
                  ),
                  title: Text(
                    companyDriverScheduleDateKey(exception.date),
                  ),
                  subtitle: Text(
                    exception.blocksDay
                        ? kCompanyDriverPlanningAbsent.of(_language)
                        : exception.blocks.map(_blockLabel).join(' · '),
                  ),
                ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: widget.canEdit
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!widget.persistenceAvailable) ...[
                      Text(
                        kCompanyDriverScheduleSaveUnavailable.of(_language),
                        key: kCompanyDriverScheduleSaveUnavailableKey,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    SizedBox(
                      height: 48,
                      child: FilledButton(
                        key: kCompanyDriverScheduleSaveKey,
                        // Disabled rather than hidden, so it is visible that
                        // saving exists but is not available yet.
                        onPressed: widget.persistenceAvailable
                            ? () => Navigator.of(context).pop(_current)
                            : null,
                        child: Text(kCompanyDriverScheduleSave.of(_language)),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _weekdayCard(ThemeData theme, int weekday) {
    final blocks = _weekdayBlocks[weekday]!;
    return Padding(
      key: companyDriverScheduleWeekdayKey(weekday),
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _weekdayLabel(weekday),
                  style: theme.textTheme.titleSmall,
                ),
              ),
              if (widget.canEdit)
                TextButton.icon(
                  key: companyDriverScheduleAddBlockKey(weekday),
                  onPressed: () => _addBlock(weekday),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(kCompanyDriverScheduleAddBlock.of(_language)),
                ),
            ],
          ),
          if (blocks.isEmpty)
            Text(
              kCompanyDriverScheduleDayOff.of(_language),
              style: theme.textTheme.bodySmall,
            )
          else
            for (var index = 0; index < blocks.length; index += 1)
              Row(
                key: companyDriverScheduleBlockKey(weekday, index),
                children: [
                  Expanded(child: Text(_blockLabel(blocks[index]))),
                  if (widget.canEdit)
                    IconButton(
                      key: companyDriverScheduleRemoveBlockKey(weekday, index),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _removeBlock(weekday, index),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      tooltip: kCompanyDriverScheduleRemoveBlock.of(_language),
                    ),
                ],
              ),
        ],
      ),
    );
  }
}
