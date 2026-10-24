// COMPANY-CUSTOMER-OPS-P0 — shared "Chauffeurs nu" strip from existing sources.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_agenda_labels.dart';
import 'package:fluxidi_tracking/company/company_agenda_models.dart';
import 'package:fluxidi_tracking/company/company_driver_agenda_color.dart';
import 'package:fluxidi_tracking/company/company_driver_agenda_style.dart';
import 'package:fluxidi_tracking/company/company_plan_presence.dart';
import 'package:fluxidi_tracking/company/company_dispatch.dart';
import 'package:fluxidi_tracking/company/company_driver_schedule.dart';
import 'package:fluxidi_tracking/company/company_driver_schedule_page.dart';
import 'package:fluxidi_tracking/company/company_driver_status_facets.dart';

const Key kCompanyDriversNowPaneKey = Key('company_drivers_now_pane');
const Key kCompanyDriversNowListKey = Key('company_drivers_now_list');
const Key kCompanyDriversNowPrevKey = Key('company_drivers_now_prev');
const Key kCompanyDriversNowNextKey = Key('company_drivers_now_next');
const Key kCompanyDriversNowToggleKey = Key('company_drivers_now_toggle');
const Key kCompanyDriversNowAllKey = Key('company_drivers_now_all');

Key companyDriversNowCardKey(String driverId) =>
    Key('company_drivers_now_card_${driverId.trim()}');
const double kCompanyDriversNowCardWidth = 248;
const double kCompanyDriversNowCardGap = 8;
const double kCompanyDriversNowArrowWidth = 36;
const double kCompanyDriversNowListHeight = 118;
const Duration kCompanyDriverNowStaleAfter = Duration(minutes: 15);

enum CompanyDriverNowFreshness { missing, stale, recent }

class CompanyDriverNowRideRef {
  const CompanyDriverNowRideRef({
    required this.bookingId,
    required this.customerName,
    required this.pickupUtc,
    this.durationUnknown = false,
  });

  final String bookingId;
  final String customerName;
  final DateTime pickupUtc;
  final bool durationUnknown;
}

class CompanyDriverNowRow {
  const CompanyDriverNowRow({
    required this.driverId,
    required this.displayName,
    required this.color,
    required this.freshness,
    required this.workStatusRaw,
    this.photoUrl = '',
    this.updatedAtUtc,
    this.currentRide,
    this.nextRide,
    this.presenceLabel = '',
    this.liveConnected = false,
    CompanyDriverSchedule? schedule,
    CompanyDriverStatusFacets? facets,
  }) : _schedule = schedule,
       _facets = facets;

  final CompanyDriverSchedule? _schedule;

  /// Resolved once with the same clock the rest of the row used, so a widget
  /// rebuild cannot silently re-age the driver's last signal.
  final CompanyDriverStatusFacets? _facets;

  final String driverId;
  final String displayName;
  final Color color;
  final String photoUrl;
  final CompanyDriverNowFreshness freshness;
  final String workStatusRaw;
  final DateTime? updatedAtUtc;
  final CompanyDriverNowRideRef? currentRide;
  final CompanyDriverNowRideRef? nextRide;
  final String presenceLabel;
  final bool liveConnected;

  /// Roster for this driver, or null when none is stored.
  CompanyDriverSchedule? get schedule => _schedule;

  /// The four independent facets behind the card.
  CompanyDriverStatusFacets get facets =>
      _facets ?? facetsAt(DateTime.now().toUtc());

  CompanyDriverStatusFacets facetsAt(DateTime nowUtc) {
    return companyDriverStatusFacets(
      lastSignalUtc: updatedAtUtc,
      nowUtc: nowUtc,
      rawWorkStatus: workStatusRaw,
      rawPresenceLabel: presenceLabel,
      schedule: _schedule,
      staleAfter: kCompanyDriverNowStaleAfter,
    );
  }

  bool get workStatusIsCurrent =>
      liveConnected ||
      presenceLabel.isNotEmpty ||
      (freshness == CompanyDriverNowFreshness.recent &&
          workStatusRaw.trim().isNotEmpty);

  bool get hasLiveConnection => liveConnected;
}

const List<String> kCompanyDriverOperationalUpdatedKeys = <String>[
  'work_status_updated_at',
  'workStatusUpdatedAt',
  'presence_updated_at',
  'presenceUpdatedAt',
  'last_seen_at',
  'lastSeenAt',
  'location_updated_at',
  'locationUpdatedAt',
];

const Set<String> kCompanyDriverNowExecutingStatuses = <String>{
  'STARTED',
  'IN_PROGRESS',
  'ON_TRIP',
  'PICKED_UP',
  'ARRIVED',
  'EN_ROUTE',
  'DRIVING',
};

DateTime? companyDriverOperationalUpdatedAtUtc(Map<String, dynamic> raw) {
  DateTime? latest;
  for (final key in kCompanyDriverOperationalUpdatedKeys) {
    final parsed = DateTime.tryParse(
      (raw[key] ?? '').toString().trim(),
    )?.toUtc();
    if (parsed == null) continue;
    if (latest == null || parsed.isAfter(latest)) latest = parsed;
  }
  return latest;
}

DateTime? companyDriverUpdatedAtUtc(Map<String, dynamic> raw) {
  return companyDriverOperationalUpdatedAtUtc(raw);
}

CompanyDriverNowFreshness companyDriverNowFreshness({
  required DateTime? updatedAtUtc,
  required DateTime nowUtc,
  Duration staleAfter = kCompanyDriverNowStaleAfter,
}) {
  final updated = updatedAtUtc;
  if (updated == null) return CompanyDriverNowFreshness.missing;
  if (nowUtc.difference(updated) > staleAfter) {
    return CompanyDriverNowFreshness.stale;
  }
  return CompanyDriverNowFreshness.recent;
}

String companyDriverNowTimeLabel(DateTime utc) {
  final local = utc.toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

bool companyDriverNowRideIsExecuting(CompanyAgendaRide ride) {
  return kCompanyDriverNowExecutingStatuses.contains(
    ride.status.trim().toUpperCase(),
  );
}

bool companyDriverNowRideIsCurrent(CompanyAgendaRide ride, DateTime nowUtc) {
  if (!companyDriverNowRideIsExecuting(ride)) return false;
  final start = ride.pickupUtc;
  if (start == null) return false;
  final end = ride.dropoffUtc;
  if (end == null || ride.durationUnknown) {
    return !nowUtc.isBefore(start);
  }
  return !nowUtc.isBefore(start) && nowUtc.isBefore(end);
}

List<CompanyDriverNowRow> companyDriverNowRows({
  required List<Map<String, dynamic>> drivers,
  required List<CompanyAgendaRide> rides,
  required DateTime nowUtc,
  Duration staleAfter = kCompanyDriverNowStaleAfter,
  Map<String, CompanyDriverSchedule> schedules =
      const <String, CompanyDriverSchedule>{},
}) {
  final now = nowUtc.toUtc();
  return [
    for (final driver in drivers)
      if (companyAgendaDriverId(driver).isNotEmpty)
        _rowForDriver(
          driver: driver,
          rides: rides,
          nowUtc: now,
          staleAfter: staleAfter,
          schedules: schedules,
        ),
  ];
}

CompanyDriverNowRow _rowForDriver({
  required Map<String, dynamic> driver,
  required List<CompanyAgendaRide> rides,
  required DateTime nowUtc,
  required Duration staleAfter,
  Map<String, CompanyDriverSchedule> schedules =
      const <String, CompanyDriverSchedule>{},
}) {
  final look = companyAgendaDriverLook(driver);
  final assigned = rides.where((ride) {
    return ride.assignedDriverId.trim() == look.driverId &&
        ride.pickupUtc != null;
  }).toList()..sort((a, b) => a.pickupUtc!.compareTo(b.pickupUtc!));

  CompanyAgendaRide? current;
  for (final ride in assigned) {
    if (companyDriverNowRideIsCurrent(ride, nowUtc)) {
      current = ride;
      break;
    }
  }

  CompanyAgendaRide? next;
  for (final ride in assigned) {
    if (current != null && ride.bookingId == current.bookingId) continue;
    final start = ride.pickupUtc;
    if (start == null || !start.isAfter(nowUtc)) continue;
    next = ride;
    break;
  }

  final updatedAt = companyDriverUpdatedAtUtc(driver);
  final lastSeen = DateTime.tryParse(
    (driver['last_seen_at'] ?? driver['lastSeenAt'] ?? '').toString(),
  )?.toUtc();
  final live = companyDispatchIsLive(
    lastSeenUtc: lastSeen,
    nowUtc: nowUtc,
  );
  final presenceLabel = (driver['presence_label'] ?? driver['presenceLabel'] ?? '')
      .toString()
      .trim();
  final schedule = schedules[look.driverId];
  final facets = companyDriverStatusFacets(
    lastSignalUtc: lastSeen ?? updatedAt,
    nowUtc: nowUtc,
    rawWorkStatus: look.availabilityStatus.trim(),
    rawPresenceLabel: presenceLabel,
    schedule: schedule,
    staleAfter: staleAfter,
  );
  return CompanyDriverNowRow(
    driverId: look.driverId,
    displayName: look.displayName,
    color: look.color,
    photoUrl: look.photoUrl,
    freshness: companyDriverNowFreshness(
      updatedAtUtc: lastSeen ?? updatedAt,
      nowUtc: nowUtc,
      staleAfter: staleAfter,
    ),
    workStatusRaw: look.availabilityStatus.trim(),
    updatedAtUtc: lastSeen ?? updatedAt,
    currentRide: current == null ? null : _rideRef(current),
    nextRide: next == null ? null : _rideRef(next),
    presenceLabel: presenceLabel,
    liveConnected: live,
    schedule: schedule,
    facets: facets,
  );
}

CompanyDriverNowRideRef _rideRef(CompanyAgendaRide ride) {
  return CompanyDriverNowRideRef(
    bookingId: ride.bookingId,
    customerName: ride.customerName.trim().isEmpty
        ? ride.bookingId
        : ride.customerName.trim(),
    pickupUtc: ride.pickupUtc!,
    durationUnknown: ride.durationUnknown,
  );
}

class CompanyDriversNowStrip extends StatefulWidget {
  const CompanyDriversNowStrip({
    super.key,
    required this.rows,
    required this.language,
    this.selectedDriverId,
    this.expanded = true,
    this.onExpandedChanged,
    this.onSelectDriver,
    this.onClearDriver,
    this.onOpenRide,
    this.onOpenSchedule,
  });

  final List<CompanyDriverNowRow> rows;
  final AppLanguage language;
  final String? selectedDriverId;
  final bool expanded;
  final ValueChanged<bool>? onExpandedChanged;
  final ValueChanged<String>? onSelectDriver;
  final VoidCallback? onClearDriver;
  final ValueChanged<String>? onOpenRide;
  final ValueChanged<String>? onOpenSchedule;

  @override
  State<CompanyDriversNowStrip> createState() => _CompanyDriversNowStripState();
}

class _CompanyDriversNowStripState extends State<CompanyDriversNowStrip> {
  final ScrollController _scroll = ScrollController();
  bool _canBack = false;
  bool _canForward = false;
  bool _syncScheduled = false;
  late bool _expanded = widget.expanded;

  bool get _isExpanded =>
      widget.onExpandedChanged == null ? _expanded : widget.expanded;

  bool get _showArrows => widget.rows.length > 1;

  bool get _hasSelection => (widget.selectedDriverId ?? '').trim().isNotEmpty;

  String _headerTitle(AppLanguage language) {
    if (!_hasSelection) return kCompanyDriversNowTitle.of(language);
    final id = widget.selectedDriverId!.trim();
    for (final row in widget.rows) {
      if (row.driverId == id) {
        return '${kCompanyDriversNowTitle.of(language)} · ${row.displayName}';
      }
    }
    return kCompanyDriversNowTitle.of(language);
  }

  void _clearSelection() {
    if (widget.onClearDriver != null) {
      widget.onClearDriver!();
      return;
    }
    widget.onSelectDriver?.call('');
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_scheduleSync);
    _scheduleSync();
  }

  @override
  void didUpdateWidget(covariant CompanyDriversNowStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expanded != widget.expanded) {
      _expanded = widget.expanded;
    }
    if (oldWidget.rows.length != widget.rows.length) {
      _scheduleSync();
    }
  }

  void _toggleExpanded() {
    final next = !_isExpanded;
    if (widget.onExpandedChanged != null) {
      widget.onExpandedChanged!(next);
    } else {
      setState(() => _expanded = next);
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_scheduleSync);
    _scroll.dispose();
    super.dispose();
  }

  void _scheduleSync() {
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (mounted) _syncArrows();
    });
  }

  void _syncArrows() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final canBack = pos.pixels > 1;
    final canForward =
        pos.maxScrollExtent > 1 && pos.pixels < pos.maxScrollExtent - 1;
    if (canBack == _canBack && canForward == _canForward) return;
    setState(() {
      _canBack = canBack;
      _canForward = canForward;
    });
  }

  Future<void> _page(double direction) async {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.maxScrollExtent <= 0) return;
    final step = kCompanyDriversNowCardWidth + kCompanyDriversNowCardGap;
    final next = (pos.pixels + step * direction).clamp(
      0.0,
      pos.maxScrollExtent,
    );
    if ((next - pos.pixels).abs() < 0.5) return;
    await _scroll.animateTo(
      next,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_scroll.hasClients) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
      if (resolved is! PointerScrollEvent || !_scroll.hasClients) return;
      final next =
          (_scroll.offset + resolved.scrollDelta.dy + resolved.scrollDelta.dx)
              .clamp(0.0, _scroll.position.maxScrollExtent);
      _scroll.jumpTo(next);
    });
  }

  @override
  Widget build(BuildContext context) {
    final language = widget.language;
    final rows = widget.rows;
    return DecoratedBox(
      key: kCompanyDriversNowPaneKey,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 2, 8, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _headerTitle(language),
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_hasSelection)
                  TextButton(
                    key: kCompanyDriversNowAllKey,
                    onPressed: _clearSelection,
                    child: Text(kCompanyAgendaAllDrivers.of(language)),
                  ),
                IconButton(
                  key: kCompanyDriversNowToggleKey,
                  tooltip: _isExpanded
                      ? kCompanyAgendaHidePane.of(language)
                      : kCompanyAgendaShowPane.of(language),
                  visualDensity: VisualDensity.compact,
                  onPressed: _toggleExpanded,
                  icon: Icon(
                    _isExpanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                  ),
                ),
              ],
            ),
            if (_isExpanded) ...[
            const SizedBox(height: 2),
            Text(
              kCompanyDriversNowHint.of(language),
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            if (rows.isEmpty)
              Text(kCompanyAgendaNoRegisteredDrivers.of(language))
            else
              SizedBox(
                height: kCompanyDriversNowListHeight,
                child: Row(
                  children: [
                    if (_showArrows) ...[
                      _DriversNowArrowButton(
                        buttonKey: kCompanyDriversNowPrevKey,
                        tooltip: kCompanyDriversNowPrevious.of(language),
                        icon: Icons.chevron_left,
                        emphasized: _canBack,
                        onPressed: () => _page(-1),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: NotificationListener<ScrollMetricsNotification>(
                        onNotification: (notification) {
                          _scheduleSync();
                          return false;
                        },
                        child: Listener(
                          onPointerSignal: _onPointerSignal,
                          child: ScrollConfiguration(
                            behavior: ScrollConfiguration.of(context).copyWith(
                              dragDevices: const <PointerDeviceKind>{
                                PointerDeviceKind.touch,
                                PointerDeviceKind.stylus,
                              },
                            ),
                            child: ListView.separated(
                              key: kCompanyDriversNowListKey,
                              controller: _scroll,
                              scrollDirection: Axis.horizontal,
                              itemCount: rows.length,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(
                                    width: kCompanyDriversNowCardGap,
                                  ),
                              itemBuilder: (context, index) {
                                return _CompanyDriverNowCard(
                                  row: rows[index],
                                  language: language,
                                  selected:
                                      widget.selectedDriverId ==
                                      rows[index].driverId,
                                  onSelectDriver: widget.onSelectDriver,
                                  onOpenRide: widget.onOpenRide,
                                  onOpenSchedule: widget.onOpenSchedule,
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_showArrows) ...[
                      const SizedBox(width: 6),
                      _DriversNowArrowButton(
                        buttonKey: kCompanyDriversNowNextKey,
                        tooltip: kCompanyDriversNowNext.of(language),
                        icon: Icons.chevron_right,
                        emphasized: _canForward,
                        onPressed: () => _page(1),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DriversNowArrowButton extends StatelessWidget {
  const _DriversNowArrowButton({
    required this.buttonKey,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    required this.emphasized,
  });

  final Key buttonKey;
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: kCompanyDriversNowArrowWidth,
      height: kCompanyDriversNowListHeight,
      child: Material(
        color: emphasized
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        child: Tooltip(
          message: tooltip,
          child: InkWell(
            key: buttonKey,
            onTap: onPressed,
            borderRadius: BorderRadius.circular(10),
            child: Center(
              child: Icon(
                icon,
                color: emphasized
                    ? scheme.onPrimaryContainer
                    : scheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CompanyDriverNowCard extends StatelessWidget {
  const _CompanyDriverNowCard({
    required this.row,
    required this.language,
    this.selected = false,
    this.onSelectDriver,
    this.onOpenRide,
    this.onOpenSchedule,
  });

  final CompanyDriverNowRow row;
  final AppLanguage language;
  final bool selected;
  final ValueChanged<String>? onSelectDriver;
  final ValueChanged<String>? onOpenRide;
  final ValueChanged<String>? onOpenSchedule;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final facets = row.facets;
    final openId = (row.currentRide ?? row.nextRide)?.bookingId ?? '';
    return SizedBox(
      width: kCompanyDriversNowCardWidth,
      child: Tooltip(
        message: kCompanyDriversNowShowAgenda.of(language),
        child: Material(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            key: companyDriversNowCardKey(row.driverId),
            mouseCursor: SystemMouseCursors.click,
            onTap: onSelectDriver != null
                ? () => onSelectDriver!(row.driverId)
                : (onOpenRide == null || openId.isEmpty
                      ? null
                      : () => onOpenRide!(openId)),
            borderRadius: BorderRadius.circular(10),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
                child: ClipRect(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: row.color,
                          backgroundImage: row.photoUrl.isEmpty
                              ? null
                              : NetworkImage(row.photoUrl),
                          child: row.photoUrl.isEmpty
                              ? Text(
                                  companyAgendaInitials(row.displayName),
                                  style: TextStyle(
                                    color: companyAgendaOnColor(row.color),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            row.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (selected)
                          Icon(
                            Icons.check_circle,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                        if (onOpenSchedule != null)
                          Tooltip(
                            message: kCompanyDriverScheduleTitle.of(language),
                            child: InkWell(
                              key: companyDriverScheduleActionKey(row.driverId),
                              customBorder: const CircleBorder(),
                              onTap: () => onOpenSchedule!(row.driverId),
                              child: const Padding(
                                padding: EdgeInsets.all(2),
                                child: Icon(Icons.schedule_outlined, size: 16),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _facetLine(
                      theme,
                      text: _connectionText(facets),
                      color: _connectionColor(facets.connection),
                    ),
                    _facetLine(
                      theme,
                      text: '${kCompanyDriverDutyLabel.of(language)}: '
                          '${_dutyText(facets)}',
                      color: _dutyColor(facets),
                    ),
                    _facetLine(
                      theme,
                      text: '${kCompanyDriverPlanningLabel.of(language)}: '
                          '${_planningText(facets)}',
                      color: _planningColor(facets.schedule),
                    ),
                    _facetLine(
                      theme,
                      text: _rideLine(
                        label: kCompanyDriversNowCurrentRide.of(language),
                        ride: row.currentRide,
                      ),
                    ),
                    _facetLine(
                      theme,
                      text: _rideLine(
                        label: kCompanyDriversNowNextRide.of(language),
                        ride: row.nextRide,
                      ),
                    ),
                  ],
                ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  TextStyle _metaStyle(ThemeData theme) {
    return (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
      color: theme.colorScheme.onSurface,
      fontSize: 11,
      height: 1.2,
    );
  }

  Widget _facetLine(ThemeData theme, {required String text, Color? color}) {
    return Text(
      text,
      style: color == null
          ? _metaStyle(theme)
          : _metaStyle(theme).copyWith(color: color),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// Connection carries the driver's own last signal time, so a screen refresh
  /// can never read as fresh evidence.
  String _connectionText(CompanyDriverStatusFacets facets) {
    final base = switch (facets.connection) {
      CompanyDriverConnectionState.live =>
        kCompanyDriversNowLiveLink.of(language),
      CompanyDriverConnectionState.staleOrLost =>
        kCompanyDriverConnectionLost.of(language),
      CompanyDriverConnectionState.unknown =>
        kCompanyDriverConnectionUnknown.of(language),
    };
    final signal = facets.lastDriverSignalUtc;
    final stamp = signal == null
        ? kCompanyDriverSignalNever.of(language)
        : companyDriverNowTimeLabel(signal);
    return '$base · ${kCompanyDriverSignalAt.of(language)} $stamp';
  }

  Color _connectionColor(CompanyDriverConnectionState state) {
    return switch (state) {
      CompanyDriverConnectionState.live => kCompanyPlanPresenceGreen,
      CompanyDriverConnectionState.staleOrLost => kCompanyPlanPresenceOrange,
      CompanyDriverConnectionState.unknown => kCompanyPlanPresenceGrey,
    };
  }

  String _dutyText(CompanyDriverStatusFacets facets) {
    if (facets.duty == CompanyDriverDutyState.working &&
        facets.connection != CompanyDriverConnectionState.live) {
      return kCompanyDriverDutyStoredAvailable.of(language);
    }
    return switch (facets.duty) {
      CompanyDriverDutyState.working => kCompanyDriverDutyWorking.of(language),
      CompanyDriverDutyState.onBreak =>
        kCompanyDriverPresencePaused.of(language),
      CompanyDriverDutyState.dutyEnded => kCompanyDriverDutyEnded.of(language),
      CompanyDriverDutyState.unknown => kCompanyDriverDutyUnknown.of(language),
    };
  }

  Color _dutyColor(CompanyDriverStatusFacets facets) {
    if (facets.duty == CompanyDriverDutyState.working &&
        facets.connection != CompanyDriverConnectionState.live) {
      return kCompanyPlanPresenceGrey;
    }
    return switch (facets.duty) {
      CompanyDriverDutyState.working => kCompanyPlanPresenceGreen,
      CompanyDriverDutyState.onBreak => kCompanyPlanPresenceOrange,
      CompanyDriverDutyState.dutyEnded => kCompanyPlanPresenceGrey,
      CompanyDriverDutyState.unknown => kCompanyPlanPresenceGrey,
    };
  }

  String _planningText(CompanyDriverStatusFacets facets) {
    if (facets.schedule == CompanyDriverScheduleState.noSchedule) {
      return kCompanyDriverPlanningNone.of(language);
    }
    final hours = facets.plannedWindowLabel;
    if (facets.schedule == CompanyDriverScheduleState.unresolvableTimezone) {
      return kCompanyDriverScheduleUndeterminable.of(language);
    }
    final state = switch (facets.schedule) {
      CompanyDriverScheduleState.absent =>
        kCompanyDriverPlanningAbsent.of(language),
      CompanyDriverScheduleState.onPlannedBreak =>
        kCompanyDriverPlanningBreak.of(language),
      CompanyDriverScheduleState.offHours =>
        kCompanyDriverPlanningOffHours.of(language),
      _ => '',
    };
    if (hours.isEmpty) {
      return state.isEmpty ? kCompanyDriverPlanningNone.of(language) : state;
    }
    return state.isEmpty ? hours : '$hours · $state';
  }

  Color _planningColor(CompanyDriverScheduleState state) {
    return switch (state) {
      CompanyDriverScheduleState.scheduled => kCompanyPlanPresenceGreen,
      CompanyDriverScheduleState.onPlannedBreak => kCompanyPlanPresenceOrange,
      CompanyDriverScheduleState.absent => kCompanyPlanPresenceRed,
      CompanyDriverScheduleState.offHours => kCompanyPlanPresenceGrey,
      CompanyDriverScheduleState.noSchedule => kCompanyPlanPresenceGrey,
      CompanyDriverScheduleState.unresolvableTimezone =>
        kCompanyPlanPresenceRed,
    };
  }

  String _workStatusText() {
    final labeled = companyDispatchPresenceLabelText(
      row.presenceLabel,
      language,
    );
    if (labeled.isNotEmpty) return labeled;
    final status = row.workStatusRaw.trim().toLowerCase();
    if (row.freshness == CompanyDriverNowFreshness.missing) {
      if (status.isEmpty || status == 'available' || status == 'online') {
        return kCompanyDriversNowNoLiveData.of(language);
      }
    }
    if (!row.liveConnected &&
        (status.isEmpty || status == 'available' || status == 'online')) {
      return kCompanyDriverPresenceScheduledNoLive.of(language);
    }
    if (!row.workStatusIsCurrent &&
        status.isEmpty &&
        row.presenceLabel.trim().isEmpty) {
      return kCompanyDriversNowNoLiveData.of(language);
    }
    switch (row.workStatusRaw.trim().toLowerCase()) {
      case 'available':
        return kCompanyDriverPresenceAvailable.of(language);
      case 'busy':
      case 'on_trip':
        return kCompanyDriverPresenceOnTrip.of(language);
      case 'paused':
        return kCompanyDriverPresencePaused.of(language);
      case 'offline':
      case 'unavailable':
        return kCompanyDriverPresenceOfflineWork.of(language);
      default:
        return row.workStatusRaw;
    }
  }

  String _rideLine({
    required String label,
    required CompanyDriverNowRideRef? ride,
  }) {
    if (ride == null) {
      return '$label: ${kCompanyDriversNowNoRide.of(language)}';
    }
    return '$label: ${companyDriverNowTimeLabel(ride.pickupUtc)} · '
        '${ride.customerName}';
  }

  String _updatedText() {
    final updated = row.updatedAtUtc;
    if (updated == null) return kCompanyDriversNowUpdatedUnknown.of(language);
    return companyDriverNowTimeLabel(updated);
  }
}
