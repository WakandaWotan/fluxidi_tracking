import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_agenda_labels.dart';
import 'package:fluxidi_tracking/company/company_agenda_models.dart';
import 'package:fluxidi_tracking/company/company_booking_metrics.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';
import 'package:fluxidi_tracking/company/company_driver_agenda_color.dart';
import 'package:fluxidi_tracking/company/company_driver_agenda_style.dart';
import 'package:fluxidi_tracking/company/company_ops_theme.dart';
import 'package:fluxidi_tracking/company/company_ride_options.dart';
import 'package:fluxidi_tracking/company/company_roundtrip.dart';

const Key kCompanyAgendaCalendarKey = Key('company_agenda_calendar');
const Key kCompanyAgendaUnscheduledLaneKey = Key(
  'company_agenda_unscheduled_lane',
);
const Key kCompanyAgendaUnassignedLaneKey = Key(
  'company_agenda_unassigned_lane',
);
const Key kCompanyAgendaByDriverKey = Key('company_agenda_by_driver');
const Key kCompanyAgendaDayHeaderRowKey = Key('company_agenda_day_header_row');
const Key kCompanyAgendaWeekHScrollKey = Key('company_agenda_week_h_scroll');
const Key kCompanyAgendaWeekVScrollKey = Key('company_agenda_week_v_scroll');
const Key kCompanyAgendaHourCompactKey = Key('company_agenda_hour_compact');
const Key kCompanyAgendaHourSpaciousKey = Key('company_agenda_hour_spacious');
const double kCompanyAgendaHourHeightCompact = 72;
const double kCompanyAgendaHourHeightSpacious = 120;
const double kCompanyAgendaHourHeight = kCompanyAgendaHourHeightCompact;
const double kCompanyAgendaOverlapGap = 3;
const double kCompanyAgendaRideInset = 4;
const double kCompanyAgendaMoreRailWidth = 26;
const double kCompanyAgendaMinOverlapRideWidth = 80;
const double kCompanyAgendaDayRideMaxWidth = 312;
const double kCompanyAgendaMinInteractiveRideWidth = 72;
const double kCompanyAgendaConcurrentActionHeight = 40;
const double kCompanyAgendaTimeGutterWidth = 56;
const double kCompanyAgendaDayHeaderHeight = 48;
const double kCompanyAgendaUnknownDurationHeight = 26;
const double kCompanyAgendaWeekMinColumnWidth = 120;
const double kCompanyAgendaByDriverMinColumnWidth = 188;
const List<String> kCompanyAgendaWeekdayNl = <String>[
  'Ma',
  'Di',
  'Wo',
  'Do',
  'Vr',
  'Za',
  'Zo',
];

enum CompanyAgendaHourDensity { compact, spacious }

double companyAgendaHourHeightFor(CompanyAgendaHourDensity density) {
  return density == CompanyAgendaHourDensity.spacious
      ? kCompanyAgendaHourHeightSpacious
      : kCompanyAgendaHourHeightCompact;
}

String companyAgendaSlotKey(DateTime slot) {
  return 'company_agenda_slot_${slot.year}_${slot.month}_${slot.day}_${slot.hour}';
}

String companyAgendaRideKey(String bookingId) {
  return 'company_agenda_ride_$bookingId';
}

Key companyAgendaDayHeaderKey(DateTime day) =>
    Key('company_agenda_day_header_${day.year}_${day.month}_${day.day}');

Key companyAgendaMoreKey(DateTime day, double top) => Key(
  'company_agenda_more_${day.year}_${day.month}_${day.day}_${top.round()}',
);

Key companyAgendaQuarterLineKey(DateTime hour, int quarter) => Key(
  'company_agenda_quarter_${hour.year}_${hour.month}_${hour.day}_${hour.hour}_$quarter',
);

bool companyAgendaShouldCapRideWidth(double columnWidth) {
  return columnWidth >
      kCompanyAgendaDayRideMaxWidth + kCompanyAgendaRideInset * 2 + 24;
}

double companyAgendaRideClusterWidth({
  required double columnWidth,
  required int columnCount,
  required bool reserveMoreRail,
}) {
  final moreW = reserveMoreRail ? kCompanyAgendaMoreRailWidth : 0.0;
  final full = (columnWidth - kCompanyAgendaRideInset * 2 - moreW).clamp(
    0.0,
    double.infinity,
  );
  final count = columnCount < 1 ? 1 : columnCount;
  if (!companyAgendaShouldCapRideWidth(columnWidth)) return full;
  final capped =
      count * kCompanyAgendaDayRideMaxWidth +
      kCompanyAgendaOverlapGap * (count - 1);
  return capped < full ? capped : full;
}

const Key kCompanyAgendaMoreSheetKey = Key('company_agenda_more_sheet');
const Key kCompanyAgendaWeekStripKey = Key('company_agenda_week_strip');
const Key kCompanyAgendaPhoneDayListKey = Key('company_agenda_phone_day_list');
const Key kCompanyAgendaTimeGutterKey = Key('company_agenda_time_gutter');

Key companyAgendaWeekStripDayKey(DateTime day) =>
    Key('company_agenda_week_strip_${day.year}_${day.month}_${day.day}');

String companyAgendaMoreLabel(int hiddenCount, AppLanguage language) {
  return companyAgendaConcurrentLabel(hiddenCount, language);
}

class CompanyAgendaColumnLayout {
  const CompanyAgendaColumnLayout({
    required this.gutterWidth,
    required this.columnWidth,
    required this.gridWidth,
    required this.overflows,
  });

  final double gutterWidth;
  final double columnWidth;
  final double gridWidth;
  final bool overflows;
}

CompanyAgendaColumnLayout companyAgendaColumnLayout({
  required double availableWidth,
  required int columnCount,
  required bool byDriver,
}) {
  final count = columnCount < 1 ? 1 : columnCount;
  const gutter = kCompanyAgendaTimeGutterWidth;
  final daysArea = (availableWidth - gutter).clamp(0.0, double.infinity);
  if (count == 1) {
    return CompanyAgendaColumnLayout(
      gutterWidth: gutter,
      columnWidth: daysArea,
      gridWidth: daysArea,
      overflows: false,
    );
  }
  final minWidth = byDriver
      ? kCompanyAgendaByDriverMinColumnWidth
      : kCompanyAgendaWeekMinColumnWidth;
  final even = daysArea / count;
  final columnWidth = even >= minWidth ? even : minWidth;
  final gridWidth = columnWidth * count;
  return CompanyAgendaColumnLayout(
    gutterWidth: gutter,
    columnWidth: columnWidth,
    gridWidth: gridWidth,
    overflows: gridWidth > daysArea + 0.5,
  );
}

List<CompanyAgendaRide> companyAgendaRidesAssignedTo({
  required List<CompanyAgendaRide> rides,
  String? driverId,
}) {
  final id = (driverId ?? '').trim();
  if (id.isEmpty) return rides;
  return rides
      .where((ride) => ride.assignedDriverId.trim() == id)
      .toList(growable: false);
}

class CompanyAgendaPackedRide {
  const CompanyAgendaPackedRide({
    required this.ride,
    required this.top,
    required this.height,
    required this.columnIndex,
    required this.columnCount,
    this.continuesFromPreviousDay = false,
  });

  final CompanyAgendaRide ride;
  final double top;
  final double height;
  final int columnIndex;
  final int columnCount;
  final bool continuesFromPreviousDay;

  double get bottom => top + height;
}

class CompanyAgendaRideOverflow {
  const CompanyAgendaRideOverflow({
    required this.top,
    required this.height,
    required this.hidden,
    required this.all,
  });

  final double top;
  final double height;
  final List<CompanyAgendaRide> hidden;
  final List<CompanyAgendaRide> all;
}

class CompanyAgendaDayPack {
  const CompanyAgendaDayPack({
    required this.visible,
    required this.overflows,
  });

  final List<CompanyAgendaPackedRide> visible;
  final List<CompanyAgendaRideOverflow> overflows;
}

class _AgendaPackItem {
  _AgendaPackItem({
    required this.ride,
    required this.top,
    required this.height,
  });

  final CompanyAgendaRide ride;
  final double top;
  final double height;
  int columnIndex = 0;

  double get bottom => top + height;
}

bool companyAgendaIntervalsOverlap(
  double aTop,
  double aBottom,
  double bTop,
  double bBottom,
) {
  return aTop < bBottom - 0.01 && bTop < aBottom - 0.01;
}

int companyAgendaMaxVisibleOverlapColumns(double columnWidth) {
  final usable = (columnWidth - kCompanyAgendaRideInset * 2).clamp(
    0.0,
    double.infinity,
  );
  return ((usable + kCompanyAgendaOverlapGap) /
          (kCompanyAgendaMinOverlapRideWidth + kCompanyAgendaOverlapGap))
      .floor()
      .clamp(1, 4);
}

Rect companyAgendaPackedRideRect({
  required CompanyAgendaPackedRide packed,
  required double columnWidth,
  required bool reserveMoreRail,
}) {
  final area = companyAgendaRideClusterWidth(
    columnWidth: columnWidth,
    columnCount: packed.columnCount,
    reserveMoreRail: reserveMoreRail,
  );
  final count = packed.columnCount < 1 ? 1 : packed.columnCount;
  final width = count == 1
      ? area
      : (area - kCompanyAgendaOverlapGap * (count - 1)) / count;
  final left =
      kCompanyAgendaRideInset +
      packed.columnIndex * (width + kCompanyAgendaOverlapGap);
  return Rect.fromLTWH(
    left,
    packed.top + 1,
    width,
    (packed.height - 2).clamp(6.0, packed.height),
  );
}

List<List<_AgendaPackItem>> _companyAgendaOverlapClusters(
  List<_AgendaPackItem> items,
) {
  final parent = List<int>.generate(items.length, (index) => index);
  int find(int index) {
    var current = index;
    while (parent[current] != current) {
      parent[current] = parent[parent[current]];
      current = parent[current];
    }
    return current;
  }

  void union(int a, int b) {
    final pa = find(a);
    final pb = find(b);
    if (pa != pb) parent[pa] = pb;
  }

  for (var i = 0; i < items.length; i += 1) {
    for (var j = i + 1; j < items.length; j += 1) {
      if (companyAgendaIntervalsOverlap(
        items[i].top,
        items[i].bottom,
        items[j].top,
        items[j].bottom,
      )) {
        union(i, j);
      }
    }
  }
  final groups = <int, List<_AgendaPackItem>>{};
  for (var i = 0; i < items.length; i += 1) {
    groups.putIfAbsent(find(i), () => <_AgendaPackItem>[]).add(items[i]);
  }
  return groups.values.toList(growable: false);
}

CompanyAgendaDayPack companyAgendaPackDayRides({
  required List<CompanyAgendaRide> rides,
  required DateTime day,
  required double columnWidth,
  double hourHeight = kCompanyAgendaHourHeight,
}) {
  final items = <_AgendaPackItem>[];
  for (final ride in rides) {
    final layout = companyAgendaRideLayout(
      ride,
      day,
      hourHeight: hourHeight,
    );
    if (layout == null) continue;
    items.add(
      _AgendaPackItem(ride: ride, top: layout.top, height: layout.height),
    );
  }
  items.sort((a, b) {
    final byTop = a.top.compareTo(b.top);
    if (byTop != 0) return byTop;
    final byHeight = b.height.compareTo(a.height);
    if (byHeight != 0) return byHeight;
    return a.ride.bookingId.compareTo(b.ride.bookingId);
  });
  final columnEnds = <double>[];
  for (final item in items) {
    var placed = false;
    for (var i = 0; i < columnEnds.length; i += 1) {
      if (columnEnds[i] <= item.top + 0.01) {
        item.columnIndex = i;
        columnEnds[i] = item.bottom;
        placed = true;
        break;
      }
    }
    if (!placed) {
      item.columnIndex = columnEnds.length;
      columnEnds.add(item.bottom);
    }
  }
  final maxVisible = companyAgendaMaxVisibleOverlapColumns(columnWidth);
  final visible = <CompanyAgendaPackedRide>[];
  final overflows = <CompanyAgendaRideOverflow>[];
  for (final cluster in _companyAgendaOverlapClusters(items)) {
    var maxCol = 0;
    for (final item in cluster) {
      if (item.columnIndex > maxCol) maxCol = item.columnIndex;
    }
    final columns = maxCol + 1;
    var keepCols = columns > maxVisible ? maxVisible : columns;
    if (columns >= 2 && keepCols < 2) {
      keepCols = 0;
    }
    if (keepCols > 1) {
      final probe = companyAgendaPackedRideRect(
        packed: CompanyAgendaPackedRide(
          ride: cluster.first.ride,
          top: cluster.first.top,
          height: cluster.first.height,
          columnIndex: 0,
          columnCount: keepCols,
        ),
        columnWidth: columnWidth,
        reserveMoreRail: false,
      );
      if (probe.width + 0.01 < kCompanyAgendaMinInteractiveRideWidth) {
        keepCols = 0;
      }
    }
    final hidden = <CompanyAgendaRide>[];
    for (final item in cluster) {
      if (keepCols > 0 && item.columnIndex < keepCols) {
        visible.add(
          CompanyAgendaPackedRide(
            ride: item.ride,
            top: item.top,
            height: item.height,
            columnIndex: item.columnIndex,
            columnCount: keepCols,
            continuesFromPreviousDay: companyAgendaRideContinuesFromPreviousDay(
              item.ride,
              day,
            ),
          ),
        );
      } else {
        hidden.add(item.ride);
      }
    }
    if (hidden.isEmpty) continue;
    var top = cluster.first.top;
    var bottom = cluster.first.bottom;
    for (final item in cluster) {
      if (item.top < top) top = item.top;
      if (item.bottom > bottom) bottom = item.bottom;
    }
    overflows.add(
      CompanyAgendaRideOverflow(
        top: top,
        height: bottom - top,
        hidden: hidden,
        all: <CompanyAgendaRide>[for (final item in cluster) item.ride],
      ),
    );
  }
  return CompanyAgendaDayPack(visible: visible, overflows: overflows);
}

List<DateTime> companyAgendaVisibleDays(CompanyAgendaPeriod period) {
  final start = DateTime(
    period.fromUtc.toLocal().year,
    period.fromUtc.toLocal().month,
    period.fromUtc.toLocal().day,
  );
  if (period.view == CompanyAgendaView.week) {
    return List<DateTime>.generate(
      7,
      (index) => start.add(Duration(days: index)),
    );
  }
  return <DateTime>[start];
}

class CompanyAgendaCalendar extends StatelessWidget {
  const CompanyAgendaCalendar({
    super.key,
    required this.period,
    required this.rides,
    required this.language,
    this.drivers = const <Map<String, dynamic>>[],
    this.loading = false,
    this.errorText,
    this.filteredDriverId,
    this.onRetry,
    this.onSelectRide,
    this.onAcceptCustomer,
    this.onAcceptRide,
    this.onFilterDriver,
    this.hourHeight = kCompanyAgendaHourHeight,
  });

  final CompanyAgendaPeriod period;
  final List<CompanyAgendaRide> rides;
  final AppLanguage language;
  final List<Map<String, dynamic>> drivers;
  final bool loading;
  final String? errorText;
  final String? filteredDriverId;
  final double hourHeight;
  final VoidCallback? onRetry;
  final ValueChanged<CompanyAgendaRide>? onSelectRide;
  final Future<void> Function(
    CompanyCustomerListItem customer,
    DateTime pickup,
  )?
  onAcceptCustomer;
  final Future<void> Function(CompanyAgendaRide ride, DateTime pickup)?
  onAcceptRide;
  final ValueChanged<String?>? onFilterDriver;

  @override
  Widget build(BuildContext context) {
    if (loading && rides.isEmpty) {
      return Center(child: Text(kCompanyAgendaLoading.of(language)));
    }
    if (errorText != null && rides.isEmpty) {
      return Center(
        child: TextButton(onPressed: onRetry, child: Text(errorText!)),
      );
    }
    final scheduled = rides.where((ride) => !ride.isUnscheduled).toList();
    final unscheduled = rides.where((ride) => ride.isUnscheduled).toList();
    final visibleUnscheduled = companyAgendaRidesAssignedTo(
      rides: unscheduled,
      driverId: filteredDriverId,
    );
    final visibleScheduled = period.view == CompanyAgendaView.byDriver
        ? scheduled
        : companyAgendaRidesAssignedTo(
            rides: scheduled,
            driverId: filteredDriverId,
          );
    final days = companyAgendaVisibleDays(period);
    final columns = period.view == CompanyAgendaView.byDriver
        ? _driverColumns(scheduled)
        : days.map((_) => const _DayColumnSpec.day()).toList(growable: false);
    return Column(
      key: kCompanyAgendaCalendarKey,
      children: [
        if (visibleUnscheduled.isNotEmpty)
          _UnscheduledStrip(
            rides: visibleUnscheduled,
            language: language,
            drivers: drivers,
            onSelectRide: onSelectRide,
          ),
        if (period.view == CompanyAgendaView.byDriver)
          _DriverFilters(
            language: language,
            drivers: _knownDrivers(scheduled),
            selectedId: filteredDriverId,
            onFilterDriver: onFilterDriver,
          ),
        Expanded(
          child: _TimeGrid(
            days: days,
            columns: columns,
            rides: visibleScheduled,
            language: language,
            drivers: drivers,
            byDriver: period.view == CompanyAgendaView.byDriver,
            hourHeight: hourHeight,
            onSelectRide: onSelectRide,
            onAcceptCustomer: onAcceptCustomer,
            onAcceptRide: onAcceptRide,
          ),
        ),
      ],
    );
  }

  List<CompanyAgendaDriverLook> _knownDrivers(
    List<CompanyAgendaRide> scheduled,
  ) {
    final seen = <String>{};
    final looks = <CompanyAgendaDriverLook>[];
    for (final driver in drivers) {
      final look = companyAgendaDriverLook(driver);
      if (look.driverId.isEmpty || !seen.add(look.driverId)) continue;
      looks.add(look);
    }
    for (final ride in scheduled) {
      final id = ride.assignedDriverId.trim();
      if (id.isEmpty || !seen.add(id)) continue;
      looks.add(companyAgendaLookForDriver(driverId: id, drivers: drivers));
    }
    return looks;
  }

  List<_DayColumnSpec> _driverColumns(List<CompanyAgendaRide> scheduled) {
    final looks = _knownDrivers(scheduled);
    final filtered = (filteredDriverId ?? '').trim();
    final specs = <_DayColumnSpec>[
      if (filtered.isEmpty) const _DayColumnSpec.unassigned(),
    ];
    for (final look in looks) {
      if (filtered.isNotEmpty && look.driverId != filtered) continue;
      specs.add(_DayColumnSpec.driver(look));
    }
    if (specs.isEmpty) {
      specs.add(const _DayColumnSpec.unassigned());
    }
    return specs;
  }
}

class _DayColumnSpec {
  const _DayColumnSpec._({required this.kind, this.driver});

  const _DayColumnSpec.day() : this._(kind: _ColumnKind.day);
  const _DayColumnSpec.unassigned() : this._(kind: _ColumnKind.unassigned);
  const _DayColumnSpec.driver(CompanyAgendaDriverLook look)
    : this._(kind: _ColumnKind.driver, driver: look);

  final _ColumnKind kind;
  final CompanyAgendaDriverLook? driver;

  bool matches(CompanyAgendaRide ride, DateTime day) {
    final pickup = ride.pickupUtc?.toLocal();
    if (pickup == null) return false;
    final end = ride.durationUnknown
        ? pickup.add(const Duration(minutes: 1))
        : (ride.dropoffUtc?.toLocal() ??
              pickup.add(const Duration(minutes: 1)));
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    if (!end.isAfter(dayStart) || !pickup.isBefore(dayEnd)) return false;
    switch (kind) {
      case _ColumnKind.day:
        return true;
      case _ColumnKind.unassigned:
        return ride.isUnassigned;
      case _ColumnKind.driver:
        return ride.assignedDriverId.trim() == (driver?.driverId ?? '');
    }
  }
}

enum _ColumnKind { day, unassigned, driver }

class _UnscheduledStrip extends StatelessWidget {
  const _UnscheduledStrip({
    required this.rides,
    required this.language,
    required this.drivers,
    this.onSelectRide,
  });

  final List<CompanyAgendaRide> rides;
  final AppLanguage language;
  final List<Map<String, dynamic>> drivers;
  final ValueChanged<CompanyAgendaRide>? onSelectRide;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: kCompanyAgendaUnscheduledLaneKey,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                kCompanyAgendaUnscheduled.of(language),
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final ride in rides)
                    _RideChip(
                      ride: ride,
                      language: language,
                      look: companyAgendaLookForDriver(
                        driverId: ride.assignedDriverId,
                        drivers: drivers,
                      ),
                      onTap: onSelectRide == null
                          ? null
                          : () => onSelectRide!(ride),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DriverFilters extends StatelessWidget {
  const _DriverFilters({
    required this.language,
    required this.drivers,
    required this.selectedId,
    this.onFilterDriver,
  });

  final AppLanguage language;
  final List<CompanyAgendaDriverLook> drivers;
  final String? selectedId;
  final ValueChanged<String?>? onFilterDriver;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            CompanyOpsSelectableChip(
              selected: (selectedId ?? '').isEmpty,
              label: kCompanyAgendaUnassignedLane.of(language),
              onSelected: (_) => onFilterDriver?.call(null),
            ),
            const SizedBox(width: 8),
            for (final driver in drivers) ...[
              CompanyOpsSelectableChip(
                selected: selectedId == driver.driverId,
                avatar: _DriverAvatar(look: driver, radius: 10),
                label: driver.displayName,
                onSelected: (_) => onFilterDriver?.call(
                  selectedId == driver.driverId ? null : driver.driverId,
                ),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _TimeGrid extends StatefulWidget {
  const _TimeGrid({
    required this.days,
    required this.columns,
    required this.rides,
    required this.language,
    required this.drivers,
    required this.byDriver,
    required this.hourHeight,
    this.onSelectRide,
    this.onAcceptCustomer,
    this.onAcceptRide,
  });

  final List<DateTime> days;
  final List<_DayColumnSpec> columns;
  final List<CompanyAgendaRide> rides;
  final AppLanguage language;
  final List<Map<String, dynamic>> drivers;
  final bool byDriver;
  final double hourHeight;
  final ValueChanged<CompanyAgendaRide>? onSelectRide;
  final Future<void> Function(
    CompanyCustomerListItem customer,
    DateTime pickup,
  )?
  onAcceptCustomer;
  final Future<void> Function(CompanyAgendaRide ride, DateTime pickup)?
  onAcceptRide;

  @override
  State<_TimeGrid> createState() => _TimeGridState();
}

class _TimeGridState extends State<_TimeGrid> {
  final ScrollController _headerH = ScrollController();
  final ScrollController _bodyH = ScrollController();
  final ScrollController _bodyV = ScrollController();
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _headerH.addListener(() => _sync(_headerH, _bodyH));
    _bodyH.addListener(() => _sync(_bodyH, _headerH));
  }

  @override
  void didUpdateWidget(covariant _TimeGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hourHeight == widget.hourHeight || !_bodyV.hasClients) {
      return;
    }
    final hour = _bodyV.offset / oldWidget.hourHeight;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_bodyV.hasClients) return;
      _bodyV.jumpTo(
        (hour * widget.hourHeight).clamp(0.0, _bodyV.position.maxScrollExtent),
      );
    });
  }

  void _sync(ScrollController from, ScrollController to) {
    if (_syncing || !from.hasClients || !to.hasClients) return;
    if ((to.offset - from.offset).abs() < 0.5) return;
    _syncing = true;
    to.jumpTo(from.offset.clamp(0.0, to.position.maxScrollExtent));
    _syncing = false;
  }

  void _scrollVerticallyBy(double delta) {
    if (!_bodyV.hasClients || delta == 0) return;
    _bodyV.position.pointerScroll(delta);
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_bodyV.hasClients) return;
    final dy = event.scrollDelta.dy;
    if (dy.abs() < 0.5 || dy.abs() < event.scrollDelta.dx.abs()) {
      return;
    }
    final next = (_bodyV.offset + dy).clamp(
      _bodyV.position.minScrollExtent,
      _bodyV.position.maxScrollExtent,
    );
    if (next == _bodyV.offset) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
      final scroll = resolved as PointerScrollEvent;
      _scrollVerticallyBy(scroll.scrollDelta.dy);
    });
  }

  Widget _verticalBody({
    required double gridHeight,
    required Widget timeGutter,
    required Widget dayPane,
  }) {
    return ScrollConfiguration(
      behavior: const _AgendaVerticalScrollBehavior(),
      child: Listener(
        onPointerSignal: _onPointerSignal,
        child: Scrollbar(
          key: kCompanyAgendaWeekVScrollKey,
          controller: _bodyV,
          thumbVisibility: true,
          trackVisibility: true,
          interactive: true,
          thickness: 10,
          radius: const Radius.circular(8),
          child: SingleChildScrollView(
            controller: _bodyV,
            primary: false,
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: gridHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  timeGutter,
                  Expanded(child: dayPane),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _horizontalDayPane({
    required bool overflows,
    required Widget dayBodies,
  }) {
    if (!overflows) {
      return KeyedSubtree(
        key: kCompanyAgendaWeekHScrollKey,
        child: dayBodies,
      );
    }
    return Scrollbar(
      key: kCompanyAgendaWeekHScrollKey,
      controller: _bodyH,
      thumbVisibility: true,
      trackVisibility: true,
      interactive: true,
      notificationPredicate: (notification) =>
          notification.metrics.axis == Axis.horizontal,
      child: ScrollConfiguration(
        behavior: const _AgendaHorizontalScrollBehavior(),
        child: SingleChildScrollView(
          controller: _bodyH,
          scrollDirection: Axis.horizontal,
          physics: const AlwaysScrollableScrollPhysics(),
          child: dayBodies,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _headerH.dispose();
    _bodyH.dispose();
    _bodyV.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = companyAgendaColumnLayout(
          availableWidth: constraints.maxWidth,
          columnCount: widget.columns.length,
          byDriver: widget.byDriver,
        );
        final width = layout.columnWidth;
        final hourHeight = widget.hourHeight;
        final gridHeight = 24 * hourHeight;
        DateTime dayFor(int index) {
          return widget.days[widget.byDriver
              ? 0
              : index.clamp(0, widget.days.length - 1)];
        }

        Widget dayHeaders() {
          return SizedBox(
            width: layout.gridWidth,
            height: kCompanyAgendaDayHeaderHeight,
            child: Row(
              children: [
                for (var i = 0; i < widget.columns.length; i += 1)
                  SizedBox(
                    width: width,
                    child: _DayHeader(
                      day: dayFor(i),
                      spec: widget.columns[i],
                      language: widget.language,
                      today: today,
                    ),
                  ),
              ],
            ),
          );
        }

        Widget dayBodies() {
          return SizedBox(
            width: layout.gridWidth,
            height: gridHeight,
            child: Row(
              children: [
                for (var i = 0; i < widget.columns.length; i += 1)
                  SizedBox(
                    width: width,
                    height: gridHeight,
                    child: _DayBody(
                      day: dayFor(i),
                      spec: widget.columns[i],
                      rides: widget.rides,
                      language: widget.language,
                      drivers: widget.drivers,
                      today: today,
                      hourHeight: hourHeight,
                      onSelectRide: widget.onSelectRide,
                      onAcceptCustomer: widget.onAcceptCustomer,
                      onAcceptRide: widget.onAcceptRide,
                    ),
                  ),
              ],
            ),
          );
        }

        return Column(
          children: [
            SizedBox(
              key: kCompanyAgendaDayHeaderRowKey,
              height: kCompanyAgendaDayHeaderHeight,
              child: Row(
                children: [
                  ColoredBox(
                    color: Theme.of(context).colorScheme.surface,
                    child: const SizedBox(width: kCompanyAgendaTimeGutterWidth),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _headerH,
                      scrollDirection: Axis.horizontal,
                      physics: layout.overflows
                          ? const AlwaysScrollableScrollPhysics()
                          : const NeverScrollableScrollPhysics(),
                      child: dayHeaders(),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _verticalBody(
                gridHeight: gridHeight,
                timeGutter: ColoredBox(
                  key: kCompanyAgendaTimeGutterKey,
                  color: Theme.of(context).colorScheme.surface,
                  child: SizedBox(
                    width: kCompanyAgendaTimeGutterWidth,
                    child: Column(
                      children: [
                        for (var hour = 0; hour < 24; hour += 1)
                          SizedBox(
                            height: hourHeight,
                            child: Align(
                              alignment: Alignment.topRight,
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  right: 8,
                                  top: 2,
                                ),
                                child: Text(
                                  '${hour.toString().padLeft(2, '0')}:00',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                dayPane: _horizontalDayPane(
                  overflows: layout.overflows,
                  dayBodies: dayBodies(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AgendaVerticalScrollBehavior extends MaterialScrollBehavior {
  const _AgendaVerticalScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const <PointerDeviceKind>{
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
    PointerDeviceKind.trackpad,
  };
}

class _AgendaHorizontalScrollBehavior extends MaterialScrollBehavior {
  const _AgendaHorizontalScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const <PointerDeviceKind>{
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
  };
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.day,
    required this.spec,
    required this.language,
    required this.today,
  });

  final DateTime day;
  final _DayColumnSpec spec;
  final AppLanguage language;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final isToday = DateUtils.isSameDay(day, today);
    final scheme = Theme.of(context).colorScheme;
    late final String title;
    late final String subtitle;
    if (spec.kind == _ColumnKind.unassigned) {
      title = kCompanyAgendaUnassignedLane.of(language);
      subtitle = '${day.day}/${day.month}';
    } else if (spec.kind == _ColumnKind.driver) {
      title = spec.driver?.displayName ?? '';
      subtitle = '${day.day}/${day.month}';
    } else {
      title = companyAgendaWeekdayLabel(day, language);
      subtitle = '${day.day}/${day.month}';
    }
    final headerColor = isToday ? scheme.primaryContainer : scheme.surface;
    final headerOn = isToday ? scheme.onPrimaryContainer : scheme.onSurface;
    return DecoratedBox(
      key: spec.kind == _ColumnKind.unassigned
          ? kCompanyAgendaUnassignedLaneKey
          : spec.kind == _ColumnKind.driver
          ? Key('company_agenda_driver_header_${spec.driver?.driverId ?? ''}')
          : companyAgendaDayHeaderKey(day),
      decoration: BoxDecoration(
        color: headerColor,
        border: Border(
          bottom: BorderSide(
            color: isToday ? scheme.primary : scheme.outline,
            width: isToday ? 2 : 1,
          ),
          right: BorderSide(color: scheme.outline),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            if (spec.driver != null) ...[
              _DriverAvatar(look: spec.driver!, radius: 12),
              const SizedBox(width: 6),
            ],
            if (isToday)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(Icons.check_circle, size: 14, color: headerOn),
              ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: headerOn,
                      fontWeight: isToday ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: headerOn),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayBody extends StatelessWidget {
  const _DayBody({
    required this.day,
    required this.spec,
    required this.rides,
    required this.language,
    required this.drivers,
    required this.today,
    required this.hourHeight,
    this.onSelectRide,
    this.onAcceptCustomer,
    this.onAcceptRide,
  });

  final DateTime day;
  final _DayColumnSpec spec;
  final List<CompanyAgendaRide> rides;
  final AppLanguage language;
  final List<Map<String, dynamic>> drivers;
  final DateTime today;
  final double hourHeight;
  final ValueChanged<CompanyAgendaRide>? onSelectRide;
  final Future<void> Function(
    CompanyCustomerListItem customer,
    DateTime pickup,
  )?
  onAcceptCustomer;
  final Future<void> Function(CompanyAgendaRide ride, DateTime pickup)?
  onAcceptRide;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isToday = DateUtils.isSameDay(day, today);
    final visible = rides.where((ride) => spec.matches(ride, day)).toList();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isToday
            ? scheme.surfaceContainerLow
            : scheme.surfaceContainerLowest,
        border: Border(right: BorderSide(color: scheme.outline)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final pack = companyAgendaPackDayRides(
            rides: visible,
            day: day,
            columnWidth: constraints.maxWidth,
            hourHeight: hourHeight,
          );
          return Stack(
            children: [
              Column(
                children: [
                  for (var hour = 0; hour < 24; hour += 1)
                    _HourSlot(
                      slot: DateTime(day.year, day.month, day.day, hour),
                      hourHeight: hourHeight,
                      onAcceptCustomer: onAcceptCustomer,
                      onAcceptRide: onAcceptRide,
                    ),
                ],
              ),
              for (final packed in pack.visible)
                _PositionedRide(
                  packed: packed,
                  columnWidth: constraints.maxWidth,
                  reserveMoreRail: false,
                  language: language,
                  look: companyAgendaLookForDriver(
                    driverId: packed.ride.assignedDriverId,
                    drivers: drivers,
                  ),
                  onSelectRide: onSelectRide,
                ),
              for (final overflow in pack.overflows)
                _MoreRidesButton(
                  day: day,
                  overflow: overflow,
                  columnWidth: constraints.maxWidth,
                  language: language,
                  drivers: drivers,
                  onSelectRide: onSelectRide,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _HourSlot extends StatelessWidget {
  const _HourSlot({
    required this.slot,
    required this.hourHeight,
    this.onAcceptCustomer,
    this.onAcceptRide,
  });

  final DateTime slot;
  final double hourHeight;
  final Future<void> Function(
    CompanyCustomerListItem customer,
    DateTime pickup,
  )?
  onAcceptCustomer;
  final Future<void> Function(CompanyAgendaRide ride, DateTime pickup)?
  onAcceptRide;

  @override
  Widget build(BuildContext context) {
    return DragTarget<Object>(
      onWillAcceptWithDetails: (details) =>
          details.data is CompanyCustomerListItem ||
          details.data is CompanyAgendaRide,
      onAcceptWithDetails: (details) async {
        final data = details.data;
        if (data is CompanyCustomerListItem) {
          await onAcceptCustomer?.call(data, slot);
        } else if (data is CompanyAgendaRide) {
          await onAcceptRide?.call(data, slot);
        }
      },
      builder: (context, candidate, rejected) {
        final scheme = Theme.of(context).colorScheme;
        final hourColor = scheme.outline;
        final quarterColor = scheme.outline;
        return Container(
          key: Key(companyAgendaSlotKey(slot)),
          height: hourHeight,
          decoration: BoxDecoration(
            color: candidate.isNotEmpty ? scheme.primaryContainer : null,
            border: Border(top: BorderSide(color: hourColor)),
          ),
          child: Stack(
            children: [
              for (final quarter in const <int>[1, 2, 3])
                Positioned(
                  key: companyAgendaQuarterLineKey(slot, quarter),
                  top: hourHeight * quarter / 4,
                  left: 8,
                  right: 4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: quarterColor, width: 1),
                      ),
                    ),
                    child: const SizedBox(height: 1),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class CompanyAgendaRideLayout {
  const CompanyAgendaRideLayout({
    required this.top,
    required this.height,
    this.compactMarker = false,
    this.continuesFromPreviousDay = false,
  });
  final double top;
  final double height;
  final bool compactMarker;
  final bool continuesFromPreviousDay;
}

class CompanyAgendaRideBlockContent {
  const CompanyAgendaRideBlockContent({
    required this.showAvatar,
    required this.showRoute,
    required this.showExtras,
    required this.showCustomer,
    required this.showDriverLine,
    required this.showDriverInline,
    required this.compact,
    this.splitTime = false,
  });

  final bool showAvatar;
  final bool showRoute;
  final bool showExtras;
  final bool showCustomer;
  final bool showDriverLine;
  final bool showDriverInline;
  final bool compact;
  final bool splitTime;
}

CompanyAgendaRideBlockContent companyAgendaRideBlockContent({
  required double maxHeight,
  required double maxWidth,
  required double textScale,
  required bool hasRoute,
  required bool hasExtras,
  required bool hasDriver,
}) {
  final scale = textScale.clamp(1.0, 2.0);
  final lineH = (13.0 * scale).clamp(11.0, 20.0);
  final splitTime = maxWidth < 96 && maxHeight >= lineH * 2 + 2;
  final titleH = splitTime ? lineH * 2 : (16.0 * scale).clamp(12.0, 28.0);
  final short = maxHeight < titleH + 2 && !splitTime;
  final narrow = maxWidth < 120;
  final compact = short;
  final showAvatar =
      hasDriver && !short && !narrow && maxHeight >= 22 && maxWidth >= 100;
  var used = titleH;
  final showCustomer = !short && maxHeight >= titleH + lineH;
  if (showCustomer) used += lineH;
  final showDriverLine = !short && used + lineH <= maxHeight + 0.5;
  if (showDriverLine) used += lineH;
  final showRoute =
      hasRoute && !short && !narrow && used + lineH <= maxHeight - 1;
  if (showRoute) used += lineH;
  final showExtras =
      hasExtras && !short && !narrow && used + lineH <= maxHeight - 1;
  return CompanyAgendaRideBlockContent(
    showAvatar: showAvatar,
    showRoute: showRoute,
    showExtras: showExtras,
    showCustomer: showCustomer || (short && maxWidth >= 92),
    showDriverLine: showDriverLine,
    showDriverInline: false,
    compact: compact,
    splitTime: splitTime,
  );
}

bool companyAgendaRideContinuesFromPreviousDay(
  CompanyAgendaRide ride,
  DateTime day,
) {
  final start = ride.pickupUtc?.toLocal();
  if (start == null) return false;
  final dayStart = DateTime(day.year, day.month, day.day);
  return start.isBefore(dayStart);
}

List<CompanyAgendaRide> companyAgendaRidesForDay({
  required List<CompanyAgendaRide> rides,
  required DateTime day,
  String? driverId,
}) {
  final filtered = companyAgendaRidesAssignedTo(
    rides: rides,
    driverId: driverId,
  );
  final onDay = filtered
      .where(
        (ride) =>
            !ride.isUnscheduled && companyAgendaRideLayout(ride, day) != null,
      )
      .toList();
  onDay.sort((a, b) {
    final ap = a.pickupUtc ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bp = b.pickupUtc ?? DateTime.fromMillisecondsSinceEpoch(0);
    return ap.compareTo(bp);
  });
  return onDay;
}

CompanyAgendaRideLayout? companyAgendaRideLayout(
  CompanyAgendaRide ride,
  DateTime day, {
  double hourHeight = kCompanyAgendaHourHeight,
}) {
  final start = ride.pickupUtc?.toLocal();
  if (start == null) return null;
  final dayStart = DateTime(day.year, day.month, day.day);
  final dayEnd = dayStart.add(const Duration(days: 1));
  if (ride.durationUnknown) {
    if (start.isBefore(dayStart) || !start.isBefore(dayEnd)) return null;
    final top = start.difference(dayStart).inMinutes / 60.0 * hourHeight;
    return CompanyAgendaRideLayout(
      top: top,
      height: kCompanyAgendaUnknownDurationHeight,
      compactMarker: true,
    );
  }
  final end =
      ride.dropoffUtc?.toLocal() ?? start.add(const Duration(minutes: 1));
  final segStart = start.isAfter(dayStart) ? start : dayStart;
  final segEnd = end.isBefore(dayEnd) ? end : dayEnd;
  if (!segStart.isBefore(segEnd)) return null;
  final top = segStart.difference(dayStart).inMinutes / 60.0 * hourHeight;
  final height = (segEnd.difference(segStart).inMinutes / 60.0 * hourHeight)
      .clamp(8.0, 24 * hourHeight);
  return CompanyAgendaRideLayout(
    top: top,
    height: height,
    continuesFromPreviousDay: start.isBefore(dayStart),
  );
}

class _PositionedRide extends StatelessWidget {
  const _PositionedRide({
    required this.packed,
    required this.columnWidth,
    required this.reserveMoreRail,
    required this.language,
    required this.look,
    this.onSelectRide,
  });

  final CompanyAgendaPackedRide packed;
  final double columnWidth;
  final bool reserveMoreRail;
  final AppLanguage language;
  final CompanyAgendaDriverLook look;
  final ValueChanged<CompanyAgendaRide>? onSelectRide;

  @override
  Widget build(BuildContext context) {
    final ride = packed.ride;
    final rect = companyAgendaPackedRideRect(
      packed: packed,
      columnWidth: columnWidth,
      reserveMoreRail: reserveMoreRail,
    );
    final blockHeight = rect.height;
    return Positioned(
      top: rect.top,
      left: rect.left,
      width: rect.width,
      height: blockHeight,
      child: Draggable<CompanyAgendaRide>(
        data: ride,
        feedback: Material(
          elevation: 6,
          child: SizedBox(
            width: 180,
            height: blockHeight.clamp(26, 80),
            child: _RideBlock(
              ride: ride,
              language: language,
              look: look,
              continuesFromPreviousDay: packed.continuesFromPreviousDay,
            ),
          ),
        ),
        childWhenDragging: Opacity(
          opacity: 0.35,
          child: _RideBlock(
            ride: ride,
            language: language,
            look: look,
            continuesFromPreviousDay: packed.continuesFromPreviousDay,
          ),
        ),
        child: Tooltip(
          message: companyAgendaRideTooltip(
            ride,
            language,
            look,
            continuesFromPreviousDay: packed.continuesFromPreviousDay,
          ),
          waitDuration: const Duration(milliseconds: 400),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onSelectRide == null ? null : () => onSelectRide!(ride),
            child: _RideBlock(
              ride: ride,
              language: language,
              look: look,
              continuesFromPreviousDay: packed.continuesFromPreviousDay,
            ),
          ),
        ),
      ),
    );
  }
}

class _RideBlock extends StatelessWidget {
  const _RideBlock({
    required this.ride,
    required this.language,
    required this.look,
    this.continuesFromPreviousDay = false,
  });

  final CompanyAgendaRide ride;
  final AppLanguage language;
  final CompanyAgendaDriverLook look;
  final bool continuesFromPreviousDay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cancelled = ride.status.toUpperCase().contains('CANCEL');
    final summary = companyAgendaRideSummary(
      ride,
      language,
      driverName: look.displayName,
      continuesFromPreviousDay: continuesFromPreviousDay,
    );
    return DecoratedBox(
      key: Key(companyAgendaRideKey(ride.collectionId)),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(ride.durationUnknown ? 11 : 8),
        border: Border.all(
          color: ride.durationUnknown ? look.color : scheme.outline,
          width: ride.durationUnknown ? 1.4 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.06),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Opacity(
        opacity: cancelled ? 0.55 : 1,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(ride.durationUnknown ? 10 : 7),
          child: Row(
            children: [
              Container(width: ride.durationUnknown ? 4 : 5, color: look.color),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    6,
                    ride.durationUnknown || (ride.durationMin ?? 60) <= 20
                        ? 1
                        : 2,
                    6,
                    1,
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final content = companyAgendaRideBlockContent(
                        maxHeight: constraints.maxHeight,
                        maxWidth: constraints.maxWidth,
                        textScale: MediaQuery.textScalerOf(context).scale(1),
                        hasRoute: summary.route.isNotEmpty,
                        hasExtras: summary.extras.isNotEmpty,
                        hasDriver: ride.assignedDriverId.isNotEmpty,
                      );
                      TextStyle? lineStyle([bool title = false]) {
                        return (title
                                ? (content.compact
                                      ? Theme.of(context).textTheme.labelSmall
                                      : Theme.of(context).textTheme.labelMedium)
                                : Theme.of(context).textTheme.labelSmall)
                            ?.copyWith(
                              color: scheme.onSurface,
                              fontWeight: title ? FontWeight.w700 : FontWeight.w600,
                              height: 1.05,
                              decoration: cancelled
                                  ? TextDecoration.lineThrough
                                  : null,
                            );
                      }

                      final timeText = summary.time;
                      final timeParts = timeText.split('–');
                      final splitTime =
                          content.splitTime && timeParts.length == 2;
                      Widget timeLabel() {
                        if (splitTime) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                timeParts[0],
                                maxLines: 1,
                                overflow: TextOverflow.clip,
                                style: lineStyle(true),
                              ),
                              Text(
                                '–${timeParts[1]}',
                                maxLines: 1,
                                overflow: TextOverflow.clip,
                                style: lineStyle(true),
                              ),
                            ],
                          );
                        }
                        return Text(
                          content.compact && content.showCustomer
                              ? [
                                  if (timeText.isNotEmpty) timeText,
                              companyAgendaRideDisplayTitle(
                                ride,
                                language,
                              ),
                            ].join(' · ')
                              : (timeText.isNotEmpty
                                    ? timeText
                                    : companyAgendaRideDisplayTitle(
                                        ride,
                                        language,
                                      )),
                          maxLines: content.splitTime ? 2 : 1,
                          softWrap: content.splitTime,
                          overflow: TextOverflow.ellipsis,
                          style: lineStyle(true),
                        );
                      }

                      final title = Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (content.showAvatar)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: _DriverAvatar(look: look, radius: 8),
                            ),
                          Expanded(child: timeLabel()),
                        ],
                      );
                      if (content.compact) {
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: title,
                        );
                      }
                      final driverLabel = look.displayName.isNotEmpty
                          ? look.displayName
                          : kCompanyAgendaUnassignedLane.of(language);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          title,
                          if (content.showCustomer &&
                              ride.customerName.isNotEmpty)
                            Text(
                              companyAgendaRideDisplayTitle(ride, language),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: lineStyle(),
                            ),
                          if (content.showDriverLine)
                            Row(
                              children: [
                                if (look.displayName.isNotEmpty &&
                                    constraints.maxWidth >= 70) ...[
                                  _DriverAvatar(look: look, radius: 6),
                                  const SizedBox(width: 4),
                                ],
                                Expanded(
                                  child: Text(
                                    driverLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: lineStyle(),
                                  ),
                                ),
                              ],
                            ),
                          if (content.showRoute)
                            Text(
                              summary.route,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: scheme.onSurface,
                                    height: 1.1,
                                  ),
                            ),
                          if (content.showExtras)
                            Text(
                              summary.extras.join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: scheme.onSurface,
                                    height: 1.1,
                                  ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreRidesButton extends StatelessWidget {
  const _MoreRidesButton({
    required this.day,
    required this.overflow,
    required this.columnWidth,
    required this.language,
    required this.drivers,
    this.onSelectRide,
  });

  final DateTime day;
  final CompanyAgendaRideOverflow overflow;
  final double columnWidth;
  final AppLanguage language;
  final List<Map<String, dynamic>> drivers;
  final ValueChanged<CompanyAgendaRide>? onSelectRide;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final summarize = overflow.hidden.length == overflow.all.length;
    final count = summarize ? overflow.all.length : overflow.hidden.length;
    final label = companyAgendaConcurrentLabel(count, language);
    final width = companyAgendaRideClusterWidth(
      columnWidth: columnWidth,
      columnCount: 1,
      reserveMoreRail: false,
    ).clamp(48.0, columnWidth);
    final height = summarize
        ? overflow.height.clamp(
            kCompanyAgendaConcurrentActionHeight,
            72.0,
          )
        : 32.0;
    return Positioned(
      top: overflow.top + 2,
      left: kCompanyAgendaRideInset,
      width: width,
      height: height,
      child: Tooltip(
        message: label,
        child: Material(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            key: companyAgendaMoreKey(day, overflow.top),
            onTap: () => _openSheet(context),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Center(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.onPrimaryContainer,
                    height: 1.1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openSheet(BuildContext context) async {
    final rides = overflow.all;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            key: kCompanyAgendaMoreSheetKey,
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  kCompanyAgendaMoreRides.of(language),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              for (final ride in rides)
                _ConcurrentRideTile(
                  ride: ride,
                  language: language,
                  drivers: drivers,
                  onTap: () {
                    Navigator.of(context).pop();
                    onSelectRide?.call(ride);
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ConcurrentRideTile extends StatelessWidget {
  const _ConcurrentRideTile({
    required this.ride,
    required this.language,
    required this.drivers,
    this.onTap,
  });

  final CompanyAgendaRide ride;
  final AppLanguage language;
  final List<Map<String, dynamic>> drivers;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final look = companyAgendaLookForDriver(
      driverId: ride.assignedDriverId,
      drivers: drivers,
    );
    final summary = companyAgendaRideSummary(
      ride,
      language,
      driverName: look.displayName,
    );
    final driverLabel = look.displayName.isNotEmpty
        ? look.displayName
        : kCompanyAgendaUnassignedLane.of(language);
    return ListTile(
      key: Key('company_agenda_more_ride_${ride.bookingId}'),
      title: Text(
        [
          summary.time,
          ride.customerName,
        ].where((part) => part.trim().isNotEmpty).join(' · '),
      ),
      subtitle: Text(
        [
          driverLabel,
          if (ride.status.isNotEmpty) ride.status,
        ].join(' · '),
      ),
      onTap: onTap,
    );
  }
}

class CompanyAgendaPhoneDayPane extends StatelessWidget {
  const CompanyAgendaPhoneDayPane({
    super.key,
    required this.anchor,
    required this.rides,
    required this.language,
    this.drivers = const <Map<String, dynamic>>[],
    this.filteredDriverId,
    this.onSelectDay,
    this.onSelectRide,
  });

  final DateTime anchor;
  final List<CompanyAgendaRide> rides;
  final AppLanguage language;
  final List<Map<String, dynamic>> drivers;
  final String? filteredDriverId;
  final ValueChanged<DateTime>? onSelectDay;
  final ValueChanged<CompanyAgendaRide>? onSelectRide;

  @override
  Widget build(BuildContext context) {
    final week = companyAgendaVisibleDays(
      companyAgendaPeriodFor(view: CompanyAgendaView.week, anchorLocal: anchor),
    );
    final day = DateTime(anchor.year, anchor.month, anchor.day);
    final dayRides = companyAgendaRidesForDay(
      rides: rides,
      day: day,
      driverId: filteredDriverId,
    );
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        SizedBox(
          key: kCompanyAgendaWeekStripKey,
          height: 64,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                for (var index = 0; index < week.length; index += 1) ...[
                  if (index > 0) const SizedBox(width: 6),
                  Builder(
                    builder: (context) {
                      final item = week[index];
                      final selected = DateUtils.isSameDay(item, day);
                      final count = companyAgendaRidesForDay(
                        rides: rides,
                        day: item,
                        driverId: filteredDriverId,
                      ).length;
                      return ActionChip(
                        key: companyAgendaWeekStripDayKey(item),
                        avatar: selected
                            ? Icon(
                                Icons.today,
                                size: 16,
                                color: scheme.onSecondaryContainer,
                              )
                            : null,
                        label: Text(
                          '${companyAgendaWeekdayLabel(item, language)} ${item.day}/${item.month}'
                          '${count > 0 ? ' · $count' : ''}',
                        ),
                        backgroundColor: selected
                            ? scheme.secondaryContainer
                            : scheme.surface,
                        side: BorderSide(
                          color: selected ? scheme.primary : scheme.outline,
                        ),
                        labelStyle: TextStyle(
                          color: selected
                              ? scheme.onSecondaryContainer
                              : scheme.onSurface,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w600,
                        ),
                        onPressed: onSelectDay == null
                            ? null
                            : () => onSelectDay!(item),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
        Expanded(
          child: dayRides.isEmpty
              ? Center(child: Text(kCompanyAgendaEmpty.of(language)))
              : ListView.separated(
                  key: kCompanyAgendaPhoneDayListKey,
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                  itemCount: dayRides.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final ride = dayRides[index];
                    final look = companyAgendaLookForDriver(
                      driverId: ride.assignedDriverId,
                      drivers: drivers,
                    );
                    final summary = companyAgendaRideSummary(
                      ride,
                      language,
                      driverName: look.displayName,
                      continuesFromPreviousDay:
                          companyAgendaRideContinuesFromPreviousDay(ride, day),
                    );
                    final driverLabel = ride.isUnassigned
                        ? kCompanyAgendaUnassignedLane.of(language)
                        : (look.displayName.isNotEmpty
                              ? look.displayName
                              : kCompanyAgendaUnassignedLane.of(language));
                    return Card(
                      child: ListTile(
                        key: Key(companyAgendaRideKey(ride.collectionId)),
                        leading: CircleAvatar(
                          backgroundColor: look.color,
                          child: Text(
                            look.initials.isEmpty
                                ? '?'
                                : look.initials,
                            style: TextStyle(
                              color: companyAgendaOnColor(look.color),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        title: Text(
                          [
                            if (summary.time.isNotEmpty) summary.time,
                            companyAgendaRideDisplayTitle(ride, language),
                          ].where((part) => part.trim().isNotEmpty).join(' · '),
                        ),
                        subtitle: Text(
                          [
                            driverLabel,
                            if (ride.status.isNotEmpty) ride.status,
                            if (summary.route.isNotEmpty) summary.route,
                          ].join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: onSelectRide == null
                            ? null
                            : () => onSelectRide!(ride),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _RideChip extends StatelessWidget {
  const _RideChip({
    required this.ride,
    required this.language,
    required this.look,
    this.onTap,
  });

  final CompanyAgendaRide ride;
  final AppLanguage language;
  final CompanyAgendaDriverLook look;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      key: Key(companyAgendaRideKey(ride.collectionId)),
      avatar: _DriverAvatar(look: look, radius: 10),
      label: Text(
        [
          ride.customerName,
          if (ride.fromAddress.isNotEmpty) ride.fromAddress,
        ].join(' · '),
      ),
      onPressed: onTap,
    );
  }
}

class _DriverAvatar extends StatelessWidget {
  const _DriverAvatar({required this.look, this.radius = 12});

  final CompanyAgendaDriverLook look;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final photo = look.photoUrl;
    return CircleAvatar(
      radius: radius,
      backgroundColor: look.color,
      backgroundImage: photo.isEmpty ? null : NetworkImage(photo),
      onBackgroundImageError: photo.isEmpty ? null : (_, _) {},
      child: photo.isEmpty
          ? Text(
              look.initials,
              style: TextStyle(
                fontSize: radius * 0.85,
                color: companyAgendaOnColor(look.color),
                fontWeight: FontWeight.w700,
              ),
            )
          : null,
    );
  }
}

String _hhmm(DateTime value) {
  return '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}

class CompanyAgendaRideSummary {
  const CompanyAgendaRideSummary({
    required this.time,
    required this.route,
    required this.extras,
  });

  final String time;
  final String route;
  final List<String> extras;
}

CompanyAgendaRideSummary companyAgendaRideSummary(
  CompanyAgendaRide ride,
  AppLanguage language, {
  String driverName = '',
  bool continuesFromPreviousDay = false,
}) {
  final pickup = ride.pickupUtc?.toLocal();
  final dropoff = ride.durationUnknown ? null : ride.dropoffUtc?.toLocal();
  final time = pickup == null
      ? ''
      : dropoff == null
      ? _hhmm(pickup)
      : '${_hhmm(pickup)}–${_hhmm(dropoff)}';
  return CompanyAgendaRideSummary(
    time: time,
    route: [
      if (ride.fromAddress.isNotEmpty) ride.fromAddress,
      if (ride.toAddress.isNotEmpty) ride.toAddress,
    ].join(' → '),
    extras: <String>[
      if (continuesFromPreviousDay) kCompanyAgendaContinues.of(language),
      if (ride.isUnassigned) kCompanyAgendaUnassigned.of(language),
      if (!ride.isUnassigned && driverName.isNotEmpty) driverName,
      if (ride.durationUnknown) kCompanyAgendaDurationUnknown.of(language),
      if (!ride.durationUnknown && ride.durationMin != null)
        formatCompanyBookingDurationMin(ride.durationMin!),
      if (ride.priceInclVat != null)
        formatCompanyBookingMoney(ride.priceInclVat!, ride.currency),
      if (ride.status.isNotEmpty) ride.status,
      if (!ride.rideOptions.isEmpty)
        formatCompanyRideOptionsSummary(ride.rideOptions, language: language),
    ],
  );
}

String companyAgendaRideTooltip(
  CompanyAgendaRide ride,
  AppLanguage language,
  CompanyAgendaDriverLook look, {
  bool continuesFromPreviousDay = false,
}) {
  final summary = companyAgendaRideSummary(
    ride,
    language,
    driverName: look.displayName,
    continuesFromPreviousDay: continuesFromPreviousDay,
  );
  return [
    if (summary.time.isNotEmpty) summary.time,
    if (ride.customerName.isNotEmpty) ride.customerName,
    if (look.displayName.isNotEmpty) look.displayName,
    if (summary.route.isNotEmpty) summary.route,
    ...summary.extras,
    if (ride.bookingId.isNotEmpty) ride.bookingId,
  ].where((part) => part.trim().isNotEmpty).join('\n');
}
